-- The city's business registry for government staff with the 'businesses' permission, shown in the
-- shared Business Manager app on the tablet and the computer. This used to be the tablet's own
-- Business Manager (pf-tablet/server/apps/business_manager.lua); it moved here so one app serves both
-- devices. The businesses come from pf-government's read-only registry exports (ListBusinesses; the
-- pf_gov_businesses table is pf-government's own), sales, bills, licences and the audit trail from the
-- records pf-government keeps. Transfers go through pf-government's TransferBusinessOwnershipAs, which
-- checks the permission again and writes the audit log. Each action is in GOV_ACTIONS, so the
-- dispatcher refuses players without the permission.

local C = PFComputer
local handlers = C.handlers
local QBCore = C.QBCore

for _, name in ipairs({ 'registry:overview', 'registry:employees', 'registry:transfer' }) do
    C.GOV_ACTIONS[name] = 'businesses'
end

local function started(res) return GetResourceState(res) == 'started' end
local function num(v) return tonumber(v) or 0 end

local function cap(s)
    s = tostring(s or '')
    return (s:gsub('^%l', string.upper))
end

local function accountBalance(accountRef)
    local society = type(accountRef) == 'string' and accountRef:match('^society:(.+)$')
    if not society or not started('pfm-banking') then return nil end
    local ok, bal = pcall(function() return exports['pfm-banking']:GetAccountBalance(society) end)
    return ok and tonumber(bal) or nil
end

local function taxStatusFor(debt, delinquent)
    if delinquent then return 'Delinquent' end
    if debt > 0 then return 'Late' end
    return 'Current'
end

local function buildRegistry()
    local rows = exports['pf-government']:ListBusinesses({ limit = 300 }) or {}

    local revenue = {}
    for _, r in ipairs(MySQL.query.await([[SELECT business_id,
            SUM(CASE WHEN created_at >= NOW() - INTERVAL 1 DAY THEN amount ELSE 0 END) AS today,
            SUM(CASE WHEN created_at >= NOW() - INTERVAL 7 DAY THEN amount ELSE 0 END) AS week,
            SUM(CASE WHEN created_at < NOW() - INTERVAL 7 DAY AND created_at >= NOW() - INTERVAL 14 DAY THEN amount ELSE 0 END) AS prev_week,
            SUM(CASE WHEN created_at >= NOW() - INTERVAL 30 DAY THEN amount ELSE 0 END) AS month,
            SUM(CASE WHEN created_at >= NOW() - INTERVAL 30 DAY THEN tax ELSE 0 END) AS month_tax,
            COUNT(*) AS sales
        FROM pf_gov_business_revenue WHERE created_at >= NOW() - INTERVAL 30 DAY GROUP BY business_id]]) or {}) do
        revenue[r.business_id] = r
    end

    local bills = {}
    for _, r in ipairs(MySQL.query.await([[SELECT id, target_id, bill_type, amount, amount_paid, status, description, due_date
        FROM pf_gov_bills WHERE target_type = 'business' AND status IN ('unpaid','partial','delinquent')
        ORDER BY issued_at DESC LIMIT 500]]) or {}) do
        local b = bills[r.target_id] or { debt = 0, delinquent = false, list = {} }
        local owed = num(r.amount) - num(r.amount_paid)
        b.debt = b.debt + owed
        b.delinquent = b.delinquent or r.status == 'delinquent'
        b.list[#b.list + 1] = { id = r.id, type = r.bill_type, owed = owed, status = r.status, description = r.description, dueDate = r.due_date and tostring(r.due_date) or nil }
        bills[r.target_id] = b
    end

    local permits = {}
    for _, r in ipairs(MySQL.query.await([[SELECT owner_id, license_type FROM pf_gov_licenses
        WHERE owner_type = 'business' AND status = 'active']]) or {}) do
        permits[r.owner_id] = permits[r.owner_id] or {}
        table.insert(permits[r.owner_id], r.license_type)
    end

    local activity = {}
    for _, r in ipairs(MySQL.query.await([[SELECT target_id, action_type, actor_name, created_at FROM pf_gov_audit_log
        WHERE target_type = 'business' ORDER BY id DESC LIMIT 300]]) or {}) do
        activity[r.target_id] = activity[r.target_id] or {}
        local list = activity[r.target_id]
        if #list < 10 then list[#list + 1] = { date = tostring(r.created_at), action = r.action_type, actor = r.actor_name or '' } end
    end

    local businesses, stats = {}, { totalBusinesses = 0, activeBusinesses = 0, revenueToday = 0, revenueWeek = 0, revenueMonth = 0, taxMonth = 0 }
    local alerts = { unpaidTaxes = 0, unlicensed = 0, incomeSpikes = 0 }
    for _, r in ipairs(rows) do
        local rev = revenue[r.id] or {}
        local bill = bills[r.id] or { debt = 0, delinquent = false, list = {} }
        local week, prevWeek = num(rev.week), num(rev.prev_week)
        local closed = r.status == 'closed'
        local warnings = {}
        if r.compliance and r.compliance ~= 'compliant' then warnings[#warnings + 1] = 'Compliance: ' .. r.compliance end
        if bill.delinquent then warnings[#warnings + 1] = 'Delinquent bills' end
        if closed then warnings[#warnings + 1] = 'Closed by the city' end
        local spike = prevWeek > 0 and week > prevWeek * 2
        local unowned = r.ownerId == nil or r.ownerId == '' or r.ownerId == 'unowned'

        businesses[#businesses + 1] = {
            id = r.id,
            name = r.name,
            owner = unowned and 'Unassigned' or (r.ownerName or r.ownerId),
            ownerId = unowned and '' or r.ownerId,
            type = cap(r.type or 'business'),
            status = closed and 'Closed' or 'Open',
            revenueWeek = week,
            revenueMonth = num(rev.month),
            taxMonth = num(rev.month_tax),
            licenseStatus = cap(r.license or 'none'),
            compliance = cap(r.compliance or 'compliant'),
            taxStatus = taxStatusFor(bill.debt, bill.delinquent),
            taxDebt = bill.debt,
            bills = bill.list,
            balance = accountBalance(r.account),
            location = r.address or (r.coords and ('%.0f, %.0f'):format(num(r.coords.x), num(r.coords.y))) or 'Not recorded',
            sales30d = num(rev.sales),
            permits = permits[r.id] or {},
            warnings = warnings,
            incomeSpike = spike,
            activityLog = activity[r.id] or {},
            -- mechanic shops belong to their job's bosses (pf-government refuses those transfers too)
            transferable = not tostring(r.id):match('^mechanic:'),
        }

        stats.totalBusinesses = stats.totalBusinesses + 1
        if not closed then stats.activeBusinesses = stats.activeBusinesses + 1 end
        stats.revenueToday = stats.revenueToday + num(rev.today)
        stats.revenueWeek = stats.revenueWeek + week
        stats.revenueMonth = stats.revenueMonth + num(rev.month)
        stats.taxMonth = stats.taxMonth + num(rev.month_tax)
        if bill.debt > 0 then alerts.unpaidTaxes = alerts.unpaidTaxes + 1 end
        if r.license ~= 'active' then alerts.unlicensed = alerts.unlicensed + 1 end
        if spike then alerts.incomeSpikes = alerts.incomeSpikes + 1 end
    end

    local auditLog = {}
    for _, r in ipairs(MySQL.query.await([[SELECT action_type, actor_name, target_type, target_id, created_at FROM pf_gov_audit_log
        ORDER BY id DESC LIMIT 30]]) or {}) do
        auditLog[#auditLog + 1] = { timestamp = tostring(r.created_at), action = r.action_type, actor = r.actor_name or '', target = (r.target_type or '') .. ' ' .. (r.target_id or '') }
    end

    -- candidates for a new owner: players online now (a citizen id can also be typed in)
    local citizens = {}
    for _, P in pairs(QBCore.Functions.GetQBPlayers and QBCore.Functions.GetQBPlayers() or {}) do
        local pd = P and P.PlayerData
        local ci = pd and pd.charinfo
        if pd and pd.citizenid then
            local name = ci and ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '') or ''
            citizens[#citizens + 1] = { citizenId = pd.citizenid, name = name ~= '' and name or pd.citizenid }
        end
    end
    table.sort(citizens, function(a, b) return a.name < b.name end)

    return { ok = true, businesses = businesses, stats = stats, alerts = alerts, auditLog = auditLog, citizens = citizens }
end

local function cleanBusinessId(v)
    if type(v) ~= 'string' or v == '' or #v > 100 or v:find('[%c%s]') then return nil end
    return v
end

handlers['registry:overview'] = function()
    if not started('pf-government') then return { ok = false, error = 'government_offline' } end
    local ok, result = pcall(buildRegistry)
    if not ok then
        print('^1[pf-computer]^7 business registry failed: ' .. tostring(result))
        return { ok = false, error = 'registry_unavailable' }
    end
    return result
end

handlers['registry:employees'] = function(payload)
    local businessId = cleanBusinessId(payload.businessId)
    if not businessId then return { ok = false, error = 'business_not_found' } end
    if not started('pf-government') then return { ok = false, error = 'government_offline' } end
    local ok, res = pcall(function() return exports['pf-government']:GetBusinessEmployees(businessId) end)
    return ok and type(res) == 'table' and res or { ok = false, error = 'registry_unavailable' }
end

local lastTransfer = {}
handlers['registry:transfer'] = function(payload, src)
    local now = GetGameTimer()
    if lastTransfer[src] and now - lastTransfer[src] < 2000 then return { ok = false, error = 'too_fast' } end
    lastTransfer[src] = now
    if not started('pf-government') then return { ok = false, error = 'government_offline' } end
    local businessId = cleanBusinessId(payload.businessId)
    if not businessId then return { ok = false, error = 'business_not_found' } end

    local ownerId = payload.ownerId
    if ownerId ~= nil and (type(ownerId) ~= 'string' or #ownerId > 50 or ownerId:find('[%c%s]')) then
        return { ok = false, error = 'unknown_citizen' }
    end
    if ownerId == '' then ownerId = nil end
    local ownerName = nil
    if ownerId then
        local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { ownerId })
        if not row then return { ok = false, error = 'unknown_citizen' } end
        local ci = C.decodeJson(row.charinfo, {})
        ownerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if ownerName == '' then ownerName = ownerId end
    end
    local ok, done, err = pcall(function()
        return exports['pf-government']:TransferBusinessOwnershipAs(src, businessId, ownerId, ownerName)
    end)
    if not ok then return { ok = false, error = 'transfer_failed' } end
    if done ~= true then return { ok = false, error = err or 'transfer_failed' } end
    return { ok = true }
end

AddEventHandler('playerDropped', function() lastTransfer[source] = nil end)
