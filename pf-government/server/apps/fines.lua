-- Fines (tablet): fine a citizen standing next to the official, or a registered business; recent
-- fines, business bills and citizens' house bills (property tax, house utilities); waive. Needs the 'fines' permission. Citizen fines go through fine:issueImmediate
-- (collected through the bank ledger), business fines through bill:create, waivers through bill:waive.

local A = GovApps

local function nearbyPlayers(src)
    local me = A.Pos(src)
    local out = {}
    if not me then return out end
    local range = A.cfg().FineRange or 5.0
    for id, P in pairs(QBCore.Functions.GetQBPlayers() or {}) do
        local target = P.PlayerData and P.PlayerData.source or id
        if tonumber(target) ~= tonumber(src) then
            local d = A.Dist(me, A.Pos(target))
            if d <= range then
                local ci = P.PlayerData.charinfo or {}
                out[#out + 1] = { id = tonumber(target), name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
                    distance = math.floor(d * 10 + 0.5) / 10, cid = P.PlayerData.citizenid }
            end
        end
    end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    return out
end

local function amountOf(v)
    local n = tonumber(v)
    local max = tonumber(Config.Bills and Config.Bills.MaxFine) or 50000
    if not n or n ~= n or n < 1 or n > max or n ~= math.floor(n) then return nil end
    return n
end

local handlers = {}

function handlers.nearby(src)
    local list = nearbyPlayers(src)
    for _, p in ipairs(list) do p.cid = nil end   -- the tablet gets names, never citizen ids
    return { ok = true, people = list, range = A.cfg().FineRange or 5.0 }
end

function handlers.businesses()
    local rows = MySQL.query.await("SELECT business_id, business_name, business_type FROM pf_gov_businesses ORDER BY business_name LIMIT 300") or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = { id = r.business_id, name = r.business_name, type = r.business_type } end
    return { ok = true, businesses = out }
end

--- payload = { target = 'citizen'|'business', playerId | businessId, amount, reason }
function handlers.issue(src, p)
    if not HasPermission(src, 'fines') then return { ok = false, error = 'no_permission' } end
    local amount = amountOf(p.amount)
    if not amount then return { ok = false, error = 'invalid_amount' } end
    local reason = A.Text(p.reason, 200)
    if not reason then return { ok = false, error = 'reason_required' } end

    if p.target == 'citizen' then
        -- the person must be standing next to the official right now
        local targetId = tonumber(p.playerId)
        local target
        for _, near in ipairs(nearbyPlayers(src)) do if near.id == targetId then target = near end end
        if not target then return { ok = false, error = 'not_nearby' } end
        local res = A.CallNui('fine:issueImmediate', src, { targetCitizenId = target.cid, amount = amount, description = reason })
        if not res.ok then return { ok = false, error = (type(res.result) == 'string' and res.result) or res.error or 'fine_failed' } end
        A.Notify(target.id, ('City fine: $%d — %s'):format(amount, reason), 'error')
        local r = type(res.result) == 'table' and res.result or {}
        return { ok = true, billId = r.billId, collected = r.collected, remaining = r.remaining, status = r.status, name = target.name }
    elseif p.target == 'business' then
        local biz = A.Business(p.businessId)
        if not biz then return { ok = false, error = 'business_not_found' } end
        local res = A.CallNui('bill:create', src, { targetType = 'business', targetId = biz.business_id, amount = amount,
            billType = 'fine', description = reason })
        if not res.ok then return { ok = false, error = res.error or res.message or 'fine_failed' } end
        return { ok = true, billId = res.billId, business = biz.business_name }
    end
    return { ok = false, error = 'bad_target' }
end

-- The Recent list: fines, business bills, and the citizens' house bills (the weekly property tax,
-- ref 'house:<name>', and house utilities, ref 'utility:property:<name>'), which staff with the fines
-- permission see and waive like any other bill. The house bills need the bill_ref column (schema v2).
local HOUSE_BILLS = "(target_type = 'citizen' AND (bill_ref LIKE 'house:%' OR bill_ref LIKE 'utility:property:%'))"
local RECENT = {
    all = "bill_type = 'fine' OR target_type = 'business' OR " .. HOUSE_BILLS,
    fines = "bill_type = 'fine'",
    business = "target_type = 'business'",
    houses = HOUSE_BILLS,
}

local function kindOf(r)
    local ref = type(r.bill_ref) == 'string' and r.bill_ref or ''
    if r.target_type == 'citizen' and ref:find('^house:') then return 'Property tax' end
    if r.target_type == 'citizen' and ref:find('^utility:property:') then return 'House utilities' end
    return nil
end

--- payload = { filter = 'all' | 'fines' | 'business' | 'houses' }
function handlers.recent(src, p)
    local filter = type(p) == 'table' and RECENT[p.filter] and p.filter or 'all'
    local where = RECENT[filter]
    local refs = GovSchema and GovSchema.Ensure and GovSchema.Ensure()
    if not refs then
        if filter == 'houses' then return { ok = false, error = 'unavailable' } end
        if filter == 'all' then where = "bill_type = 'fine' OR target_type = 'business'" end
    end
    local rows = MySQL.query.await([[SELECT id, bill_type, target_type, target_id, amount, amount_paid, status, description,
        issued_by_name, UNIX_TIMESTAMP(issued_at) AS issued, UNIX_TIMESTAMP(due_date) AS due]] .. (refs and ', bill_ref' or '') .. [[
        FROM pf_gov_bills WHERE ]] .. where .. ' ORDER BY id DESC LIMIT 80') or {}
    local cids, bizIds = {}, {}
    for _, r in ipairs(rows) do
        if r.target_type == 'citizen' then cids[#cids + 1] = r.target_id else bizIds[#bizIds + 1] = r.target_id end
    end
    local names = {}
    if #cids > 0 then
        for _, r in ipairs(MySQL.query.await('SELECT citizenid, charinfo FROM players WHERE citizenid IN (' .. string.rep('?', #cids, ',') .. ')', cids) or {}) do
            local ok, ci = pcall(json.decode, r.charinfo or '')
            ci = ok and type(ci) == 'table' and ci or {}
            names[r.citizenid] = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        end
    end
    if #bizIds > 0 then
        for _, r in ipairs(MySQL.query.await('SELECT business_id, business_name FROM pf_gov_businesses WHERE business_id IN (' .. string.rep('?', #bizIds, ',') .. ')', bizIds) or {}) do
            names[r.business_id] = r.business_name
        end
    end
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(r.id), type = r.bill_type, kind = kindOf(r), targetType = r.target_type,
            target = (names[r.target_id] ~= nil and names[r.target_id] ~= '') and names[r.target_id] or r.target_id,
            amount = tonumber(r.amount) or 0, paid = tonumber(r.amount_paid) or 0, status = r.status,
            description = r.description, issuedBy = r.issued_by_name, issued = tonumber(r.issued), due = tonumber(r.due),
        }
    end
    return { ok = true, bills = out, filter = filter, canWaive = HasPermission(src, 'fines') }
end

function handlers.waive(src, p)
    if not HasPermission(src, 'fines') then return { ok = false, error = 'no_permission' } end
    local billId = tonumber(p.billId)
    local reason = A.Text(p.reason, 200)
    if not billId or billId ~= math.floor(billId) then return { ok = false, error = 'bad_request' } end
    if not reason then return { ok = false, error = 'reason_required' } end
    local bill = MySQL.single.await('SELECT id, status FROM pf_gov_bills WHERE id = ? LIMIT 1', { billId })
    if not bill then return { ok = false, error = 'bill_not_found' } end
    if bill.status ~= 'unpaid' and bill.status ~= 'partial' and bill.status ~= 'delinquent' then return { ok = false, error = 'not_open' } end
    local res = A.CallNui('bill:waive', src, { billId = billId, reason = reason })
    if not res.ok then return { ok = false, error = res.error or res.message or 'waive_failed' } end
    return { ok = true }
end

A.Define({
    id = 'govfines', name = 'Fines', icon = '🧾',
    devices = { 'tablet' },
    entry = 'html/apps/fines.js', styles = { 'html/apps/gov.css' },
    category = 'government', order = 20,
    access = { gov = 'fines' },
    description = 'Fine a citizen next to you or a registered business; recent fines, business and house bills; waivers',
    window = { width = 900, height = 640 },
}, handlers)

GovApps.Fines = handlers
