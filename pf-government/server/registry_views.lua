-- Read-only views of the business registry for other resources.
-- Other resources must use these exports instead of reading pf_gov_businesses: its columns are
-- added by pf-government at start (EnsureBusinessSchema) and may change with its migrations.
--
--   exports['pf-government']:GetBusiness(businessId)               -> view or nil
--   exports['pf-government']:GetBusinessesOwnedBy(ownerIds, ids)   -> { view, ... } (max 50)
--   exports['pf-government']:ListBusinesses({ limit = 300 })        -> { view, ... }
--
-- view = { id, name, type, ownerId, ownerName, account, status = 'active'|'closed', license,
--          compliance, address, coords = { x, y, z } or nil }

PFGovRegistry = PFGovRegistry or {}

local COLS = [[business_id, business_name, business_type, owner_id, owner_name, account_ref, business_status,
    license_status, compliance_status, location_x, location_y, location_z, location_address]]

local function ensureSchema()
    -- account_ref and business_status are added at start; make sure they exist before selecting them
    if type(EnsureBusinessSchema) == 'function' then pcall(EnsureBusinessSchema) end
end

local function token(v, max)
    return type(v) == 'string' and v ~= '' and #v <= (max or 100)
end

local function view(r)
    if type(r) ~= 'table' or type(r.business_id) ~= 'string' then return nil end
    local x, y, z = tonumber(r.location_x), tonumber(r.location_y), tonumber(r.location_z)
    return {
        id = r.business_id,
        name = r.business_name,
        type = r.business_type,
        ownerId = r.owner_id,
        ownerName = r.owner_name,
        account = r.account_ref,
        status = r.business_status == 'closed' and 'closed' or 'active',
        license = r.license_status,
        compliance = r.compliance_status,
        address = r.location_address,
        coords = (x and y) and { x = x, y = y, z = z or 0.0 } or nil,
    }
end

local function rows(sql, params)
    ensureSchema()
    local ok, res = pcall(MySQL.query.await, sql, params or {})
    local out = {}
    for _, r in ipairs(ok and type(res) == 'table' and res or {}) do
        local v = view(r)
        if v then out[#out + 1] = v end
    end
    return out
end

function PFGovRegistry.GetBusiness(businessId)
    if not token(businessId, 100) then return nil end
    return rows('SELECT ' .. COLS .. ' FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })[1]
end

--- Businesses owned by any of `ownerIds` (a citizenid or 'job:<name>'), plus the businesses named
--- in `businessIds` (for example a job shop's own 'mechanic:<job>' entry).
function PFGovRegistry.GetBusinessesOwnedBy(ownerIds, businessIds)
    local owners, ids = {}, {}
    for _, v in ipairs(type(ownerIds) == 'table' and ownerIds or { ownerIds }) do
        if token(v, 64) and #owners < 5 then owners[#owners + 1] = v end
    end
    for _, v in ipairs(type(businessIds) == 'table' and businessIds or {}) do
        if token(v, 100) and #ids < 5 then ids[#ids + 1] = v end
    end
    if #owners == 0 and #ids == 0 then return {} end
    local where, params = {}, {}
    if #owners > 0 then
        where[#where + 1] = 'owner_id IN (' .. string.rep('?', #owners, ', ') .. ')'
        for _, v in ipairs(owners) do params[#params + 1] = v end
    end
    if #ids > 0 then
        where[#where + 1] = 'business_id IN (' .. string.rep('?', #ids, ', ') .. ')'
        for _, v in ipairs(ids) do params[#params + 1] = v end
    end
    return rows('SELECT ' .. COLS .. ' FROM pf_gov_businesses WHERE ' .. table.concat(where, ' OR ') ..
        ' ORDER BY business_name LIMIT 50', params)
end

function PFGovRegistry.ListBusinesses(opts)
    local limit = math.floor(tonumber(type(opts) == 'table' and opts.limit or nil) or 300)
    if limit < 1 then limit = 1 elseif limit > 300 then limit = 300 end
    return rows('SELECT ' .. COLS .. ' FROM pf_gov_businesses ORDER BY business_name LIMIT ' .. limit)
end

exports('GetBusiness', PFGovRegistry.GetBusiness)
exports('GetBusinessesOwnedBy', PFGovRegistry.GetBusinessesOwnedBy)
exports('ListBusinesses', PFGovRegistry.ListBusinesses)
