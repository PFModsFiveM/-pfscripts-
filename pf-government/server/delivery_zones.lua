-- Default delivery zones: where supply pallets go when a business has no delivery point of its own.
--
-- Staff set them on site from the Business Setup app (position and heading where they stand, read on
-- the server), or by approving a business's delivery zone request. Two scopes:
--   business  ref = registry business id   the zone of that business
--   district  ref = Config.Infrastructure.Districts key   the fallback for businesses in that district
-- pf-stores' order service asks GetDeliveryZone(businessId) when the buyer has no delivery point.

DeliveryZones = DeliveryZones or {}
local Z = DeliveryZones

local function districtKnown(name)
    local districts = (Config.Infrastructure and Config.Infrastructure.Districts) or {}
    return type(name) == 'string' and districts[name] ~= nil
end
Z.DistrictKnown = districtKnown

local function toZone(r)
    if type(r) ~= 'table' or not r.id then return nil end
    return {
        id = tonumber(r.id), scope = r.scope, ref = r.ref, label = r.label,
        x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), heading = tonumber(r.heading) or 0.0,
        requestId = tonumber(r.request_id), setByName = r.set_by_name,
    }
end

local function find(scope, ref)
    if not GovSchema.Ensure() then return nil end
    return toZone(MySQL.single.await('SELECT * FROM pf_gov_delivery_zones WHERE scope = ? AND ref = ? LIMIT 1', { scope, ref }))
end

function Z.GetForBusiness(businessId)
    if type(businessId) ~= 'string' or businessId == '' then return nil end
    return find('business', businessId)
end

function Z.GetForDistrict(district)
    if not districtKnown(district) then return nil end
    return find('district', district)
end

--- The zone that applies to a business: its own, else the zone of its district.
function Z.Get(businessId)
    if type(businessId) ~= 'string' or businessId == '' or #businessId > 100 then return nil end
    local own = Z.GetForBusiness(businessId)
    if own then return own end
    local district = MySQL.scalar.await('SELECT district FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })
    if type(district) == 'string' and district ~= '' then
        local zone = Z.GetForDistrict(district)
        if zone then zone.district = district end
        return zone
    end
    return nil
end

--- Stores a zone at `pos` (a server-read position { x, y, z, heading }). opts = { label, requestId,
--- cid, name }. Returns ok, zone id or error.
function Z.Set(scope, ref, pos, opts)
    opts = opts or {}
    if not GovSchema.Ensure() then return false, 'db_unavailable' end
    if scope == 'business' then
        if type(ref) ~= 'string' or ref == '' or not MySQL.scalar.await('SELECT 1 FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { ref }) then
            return false, 'business_not_found'
        end
    elseif scope == 'district' then
        if not districtKnown(ref) then return false, 'unknown_district' end
    else
        return false, 'bad_scope'
    end
    if type(pos) ~= 'table' or not tonumber(pos.x) or not tonumber(pos.y) or not tonumber(pos.z) then return false, 'no_position' end
    local label = opts.label ~= nil and tostring(opts.label):gsub('[%c<>]', ''):sub(1, 64) or nil
    if label == '' then label = nil end
    MySQL.insert.await([[INSERT INTO pf_gov_delivery_zones (scope, ref, label, x, y, z, heading, request_id, set_by, set_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label), x = VALUES(x), y = VALUES(y), z = VALUES(z), heading = VALUES(heading),
            request_id = VALUES(request_id), set_by = VALUES(set_by), set_by_name = VALUES(set_by_name)]],
        { scope, ref, label, pos.x, pos.y, pos.z, tonumber(pos.heading) or 0.0, opts.requestId, opts.cid, opts.name })
    local zone = find(scope, ref)
    if not zone then return false, 'db_error' end
    LogAudit('delivery_zone_set', opts.cid or 'system', opts.name or 'System', scope, ref,
        { zone = zone.id, x = pos.x, y = pos.y, z = pos.z, request = opts.requestId })
    return true, zone.id
end

function Z.Clear(scope, ref, cid, name)
    if not GovSchema.Ensure() then return false, 'db_unavailable' end
    local n = MySQL.update.await('DELETE FROM pf_gov_delivery_zones WHERE scope = ? AND ref = ?', { scope, tostring(ref or '') })
    if (tonumber(n) or 0) < 1 then return false, 'not_found' end
    LogAudit('delivery_zone_cleared', cid or 'system', name or 'System', scope, ref, {})
    return true
end

--- The district a business trades in (its fallback zone, and the district of its city events).
function Z.SetBusinessDistrict(businessId, district)
    if not GovSchema.Ensure() then return false, 'db_unavailable' end
    if district ~= nil and district ~= '' and not districtKnown(district) then return false, 'unknown_district' end
    if not MySQL.scalar.await('SELECT 1 FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId }) then return false, 'business_not_found' end
    MySQL.update.await('UPDATE pf_gov_businesses SET district = ?, updated_at = NOW() WHERE business_id = ?',
        { (district ~= '' and district) or nil, businessId })
    return true
end

-- { id, scope, ref, label, x, y, z, heading, district? } or nil
exports('GetDeliveryZone', function(businessId) return Z.Get(businessId) end)
exports('GetDistrictDeliveryZone', function(district) return Z.GetForDistrict(district) end)
