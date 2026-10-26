-- PF Tablet Business Manager: the government business registry (pf-government tables)
-- and the player's own supply orders (pf-stores shared order service).
-- Everything is read from the database here; the tablet never sends data it made up.

local QBCore = exports['pfm-core']:GetCoreObject()

local function started(res) return GetResourceState(res) == 'started' end

local function hasGovPermission(src, permission)
    if not started('pf-government') then return false end
    local ok, allowed = pcall(function() return exports['pf-government']:HasPermission(src, permission) end)
    return ok and allowed == true
end

local function cap(s)
    s = tostring(s or '')
    return (s:gsub('^%l', string.upper))
end

local function num(v) return tonumber(v) or 0 end

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

local function buildRegistry(src)
    local rows = MySQL.query.await([[SELECT business_id, business_name, business_type, owner_id, owner_name, employee_count,
        total_revenue, total_taxes_paid, license_status, compliance_status, business_status, location_address,
        location_x, location_y, account_ref FROM pf_gov_businesses ORDER BY business_name]]) or {}

    local revenue = {}
    for _, r in ipairs(MySQL.query.await([[SELECT business_id,
            SUM(CASE WHEN created_at >= NOW() - INTERVAL 1 DAY THEN amount ELSE 0 END) AS today,
            SUM(CASE WHEN created_at >= NOW() - INTERVAL 7 DAY THEN amount ELSE 0 END) AS week,
            SUM(CASE WHEN created_at < NOW() - INTERVAL 7 DAY AND created_at >= NOW() - INTERVAL 14 DAY THEN amount ELSE 0 END) AS prev_week,
            SUM(CASE WHEN created_at >= NOW() - INTERVAL 30 DAY THEN amount ELSE 0 END) AS month,
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
        b.list[#b.list + 1] = { id = r.id, type = r.bill_type, owed = owed, status = r.status, description = r.description, dueDate = r.due_date }
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

    local businesses, stats = {}, { totalBusinesses = 0, activeBusinesses = 0, totalEmployees = 0, revenueToday = 0, revenueWeek = 0, revenueMonth = 0 }
    local alerts = { unpaidTaxes = 0, unlicensed = 0, incomeSpikes = 0 }
    for _, r in ipairs(rows) do
        local rev = revenue[r.business_id] or {}
        local bill = bills[r.business_id] or { debt = 0, delinquent = false, list = {} }
        local week, prevWeek = num(rev.week), num(rev.prev_week)
        local closed = r.business_status == 'closed'
        local warnings = {}
        if r.compliance_status and r.compliance_status ~= 'compliant' then warnings[#warnings + 1] = 'Compliance: ' .. r.compliance_status end
        if bill.delinquent then warnings[#warnings + 1] = 'Delinquent bills' end
        if closed then warnings[#warnings + 1] = 'Closed by the city' end
        local spike = prevWeek > 0 and week > prevWeek * 2

        businesses[#businesses + 1] = {
            id = r.business_id,
            name = r.business_name,
            owner = (r.owner_id == 'unowned' or not r.owner_id) and 'Unassigned' or (r.owner_name or r.owner_id),
            ownerId = r.owner_id ~= 'unowned' and r.owner_id or '',
            type = cap(r.business_type or 'business'),
            status = closed and 'Closed' or 'Open',
            employees = num(r.employee_count),
            revenueWeek = week,
            revenueMonth = num(rev.month),
            licenseStatus = cap(r.license_status or 'none'),
            compliance = cap(r.compliance_status or 'compliant'),
            taxStatus = taxStatusFor(bill.debt, bill.delinquent),
            taxDebt = bill.debt,
            bills = bill.list,
            balance = accountBalance(r.account_ref),
            location = r.location_address or ((r.location_x and r.location_y) and ('%.0f, %.0f'):format(num(r.location_x), num(r.location_y))) or 'Not recorded',
            salesTotal = num(r.total_revenue),
            taxesPaid = num(r.total_taxes_paid),
            sales30d = num(rev.sales),
            permits = permits[r.business_id] or {},
            warnings = warnings,
            incomeSpike = spike,
            activityLog = activity[r.business_id] or {},
            transferable = not tostring(r.business_id):match('^mechanic:'),
        }

        stats.totalBusinesses = stats.totalBusinesses + 1
        if not closed then stats.activeBusinesses = stats.activeBusinesses + 1 end
        stats.totalEmployees = stats.totalEmployees + num(r.employee_count)
        stats.revenueToday = stats.revenueToday + num(rev.today)
        stats.revenueWeek = stats.revenueWeek + week
        stats.revenueMonth = stats.revenueMonth + num(rev.month)
        if bill.debt > 0 then alerts.unpaidTaxes = alerts.unpaidTaxes + 1 end
        if r.license_status ~= 'active' then alerts.unlicensed = alerts.unlicensed + 1 end
        if spike then alerts.incomeSpikes = alerts.incomeSpikes + 1 end
    end

    local auditLog = {}
    for _, r in ipairs(MySQL.query.await([[SELECT action_type, actor_name, target_type, target_id, created_at FROM pf_gov_audit_log
        ORDER BY id DESC LIMIT 30]]) or {}) do
        auditLog[#auditLog + 1] = { timestamp = tostring(r.created_at), action = r.action_type, actor = r.actor_name or '', target = (r.target_type or '') .. ' ' .. (r.target_id or '') }
    end

    -- Candidates for a new owner: players online now (a citizen id can also be typed in).
    local citizens = {}
    for _, pid in ipairs(QBCore.Functions.GetPlayers()) do
        local P = QBCore.Functions.GetPlayer(pid)
        local ci = P and P.PlayerData.charinfo
        if P then citizens[#citizens + 1] = { citizenId = P.PlayerData.citizenid, name = ci and ((ci.firstname or '') .. ' ' .. (ci.lastname or '')) or P.PlayerData.citizenid } end
    end

    return { ok = true, businesses = businesses, stats = stats, alerts = alerts, auditLog = auditLog, citizens = citizens }
end

QBCore.Functions.CreateCallback('pf-tablet:server:bm:registry', function(source, cb)
    if not hasGovPermission(source, 'businesses') then return cb({ ok = false, error = 'no_permission' }) end
    local ok, result = pcall(buildRegistry, source)
    if not ok then
        print('^1[pf-tablet]^7 business registry failed: ' .. tostring(result))
        return cb({ ok = false, error = 'registry_unavailable' })
    end
    cb(result)
end)

QBCore.Functions.CreateCallback('pf-tablet:server:bm:employees', function(source, cb, data)
    if not hasGovPermission(source, 'businesses') then return cb({ ok = false, error = 'no_permission' }) end
    local ok, res = pcall(function() return exports['pf-government']:GetBusinessEmployees(tostring(type(data) == 'table' and data.businessId or '')) end)
    cb(ok and type(res) == 'table' and res or { ok = false, error = 'registry_unavailable' })
end)

local lastTransfer = {}
QBCore.Functions.CreateCallback('pf-tablet:server:bm:transfer', function(source, cb, data)
    data = type(data) == 'table' and data or {}
    local now = GetGameTimer()
    if lastTransfer[source] and now - lastTransfer[source] < 2000 then return cb({ ok = false, error = 'too_fast' }) end
    lastTransfer[source] = now
    if not started('pf-government') then return cb({ ok = false, error = 'government_offline' }) end

    local ownerId = data.ownerId and tostring(data.ownerId) or nil
    if ownerId == '' then ownerId = nil end
    local ownerName = nil
    if ownerId then
        local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { ownerId })
        if not row then return cb({ ok = false, error = 'unknown_citizen' }) end
        local ci = row.charinfo and json.decode(row.charinfo) or {}
        ownerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if ownerName == '' then ownerName = ownerId end
    end
    local ok, done, err = pcall(function()
        return exports['pf-government']:TransferBusinessOwnershipAs(source, tostring(data.businessId or ''), ownerId, ownerName)
    end)
    if not ok then return cb({ ok = false, error = 'transfer_failed' }) end
    cb({ ok = done == true, error = err })
end)

AddEventHandler('playerDropped', function() lastTransfer[source] = nil end)

-- The player's own business orders: their restaurant or job business, and stores they own.
QBCore.Functions.CreateCallback('pf-tablet:server:bm:supplies', function(source, cb)
    if not started('pf-stores') then return cb({ ok = false, error = 'orders_offline' }) end
    local P = QBCore.Functions.GetPlayer(source)
    if not P then return cb({ ok = false, error = 'no_player' }) end

    local buyers = {}
    local job = P.PlayerData.job and P.PlayerData.job.name
    if job and job ~= 'unemployed' then
        local restaurantId
        if started('pf-restaurants') then
            local ok, id = pcall(function() return exports['pf-restaurants']:GetRestaurantForJob(job) end)
            restaurantId = ok and type(id) == 'string' and id or nil
        end
        if restaurantId then
            buyers[#buyers + 1] = { kind = 'restaurant', id = restaurantId, label = P.PlayerData.job.label or job }
        else
            buyers[#buyers + 1] = { kind = 'jobbiz', id = job, label = P.PlayerData.job.label or job }
        end
    end
    local okStores, stores = pcall(function() return exports['pf-stores']:ListOwnedStores(source) end)
    if okStores and type(stores) == 'table' and stores.ok and stores.data then
        for _, s in ipairs(stores.data.stores or {}) do
            buyers[#buyers + 1] = { kind = 'store', id = s.storeId, label = s.label }
        end
    end

    local out = {}
    for _, b in ipairs(buyers) do
        local ok, res = pcall(function() return exports['pf-stores']:ListOrdersFor(source, b.kind, b.id, 25) end)
        if ok and type(res) == 'table' and res.ok then   -- not_owner: the player may not manage this buyer
            local orders = {}
            for _, o in ipairs(res.data or {}) do
                orders[#orders + 1] = { id = o.id, status = o.status, method = o.method, total = num(o.total),
                    items = o.items, createdAt = o.created_at, deliveredAt = o.delivered_at, driver = o.driver_kind }
            end
            out[#out + 1] = { kind = b.kind, id = b.id, label = b.label, orders = orders }
        end
    end
    cb({ ok = true, buyers = out })
end)
