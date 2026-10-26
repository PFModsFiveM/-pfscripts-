-- Who works at a registered business. The registry does not keep its own staff list: it asks the
-- business resource that owns the staff, by business kind, and keeps employee_count in step.
--   restaurant:<id>  pf-restaurants GetStaffList(id)
--   mechanic:<job>   players whose job is <job> (job-owned shops)
--   store:<id>       the owner on the registry (stores have no staff list)
-- Read only; hiring and firing stay in each business app.

local function charName(charinfo)
    local ok, ci = pcall(function() return type(charinfo) == 'string' and json.decode(charinfo) or charinfo end)
    ci = ok and type(ci) == 'table' and ci or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or nil
end

local function namesFor(cids)
    local out = {}
    if #cids == 0 then return out end
    local marks = string.rep('?,', #cids):sub(1, -2)
    for _, r in ipairs(MySQL.query.await('SELECT citizenid, charinfo FROM players WHERE citizenid IN (' .. marks .. ')', cids) or {}) do
        out[r.citizenid] = charName(r.charinfo)
    end
    return out
end

local providers = {}

providers.restaurant = function(localId)
    if GetResourceState('pf-restaurants') ~= 'started' then return nil end
    local ok, list = pcall(function() return exports['pf-restaurants']:GetStaffList(localId) end)
    if not ok or type(list) ~= 'table' then return nil end
    local out = {}
    for _, e in ipairs(list) do
        if type(e) == 'table' and e.citizenid then out[#out + 1] = { citizenid = tostring(e.citizenid), role = tostring(e.role or 'staff') } end
    end
    return out
end

providers.mechanic = function(job)
    local out = {}
    for _, r in ipairs(MySQL.query.await([[SELECT citizenid, job FROM players
        WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ? LIMIT 200]], { job }) or {}) do
        local ok, j = pcall(json.decode, r.job or '{}')
        j = ok and type(j) == 'table' and j or {}
        local grade = type(j.grade) == 'table' and (j.grade.name or j.grade.level) or j.grade
        out[#out + 1] = { citizenid = r.citizenid, role = (j.isboss and 'boss') or tostring(grade or 'employee') }
    end
    return out
end

--- { ok, employees = { { citizenid, name, role } }, source } for a registered business.
function GetBusinessEmployees(businessId)
    if type(businessId) ~= 'string' then return { ok = false, error = 'invalid_business_id' } end
    local biz = MySQL.single.await('SELECT business_id, owner_id, owner_name FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })
    if not biz then return { ok = false, error = 'business_not_found' } end
    local kind, localId = businessId:match('^(%a+):(.+)$')
    local provider = kind and providers[kind]
    local list = provider and provider(localId) or nil
    local source = list and kind or 'registry'
    if not list then
        list = {}
        if biz.owner_id and biz.owner_id ~= 'unowned' and not tostring(biz.owner_id):match('^job:') then
            list[1] = { citizenid = biz.owner_id, role = 'owner' }
        end
    end
    local cids = {}
    for _, e in ipairs(list) do cids[#cids + 1] = e.citizenid end
    local names = namesFor(cids)
    for _, e in ipairs(list) do e.name = names[e.citizenid] or e.citizenid end
    MySQL.update.await('UPDATE pf_gov_businesses SET employee_count = ? WHERE business_id = ? AND employee_count <> ?', { #list, businessId, #list })
    return { ok = true, employees = list, source = source }
end

exports('GetBusinessEmployees', function(businessId) return GetBusinessEmployees(businessId) end)

--- A business's loans (for the business's own apps).
exports('GetBusinessLoans', function(businessId)
    if type(businessId) ~= 'string' then return {} end
    Loans.EnsureColumns()
    return MySQL.query.await([[SELECT id, principal_amount, remaining_amount, interest_rate, auto_pay, payment_interval_days,
        next_due_at, status, missed_payments, amount_due FROM pf_gov_business_loans WHERE business_id = ? ORDER BY id DESC]], { businessId }) or {}
end)

RegisterNUICallback('business:employees', function(data, cb)
    local src = data.source or source
    if not IsGovernmentEmployee(src) then return cb({ ok = false, error = 'not_government' }) end
    cb(GetBusinessEmployees(tostring(data.businessId or '')))
end)
