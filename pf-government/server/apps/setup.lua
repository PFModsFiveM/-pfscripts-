-- Business Setup (tablet): configure a registered business on site. Needs 'businesses'.
--   * approved equipment slots: list, approve one where the official stands (premises:slot:approve,
--     type from Config.Premises.SlotTypes), withdraw an empty one (premises:slot:remove)
--   * the business's default delivery zone (where supply pallets go when it has no own delivery
--     point), set where the official stands; district default zones the same way
--   * the business's registry location (business:updateLocation) and district
-- Positions are always read on the server; when the registry has a location, the official must be
-- at the business.

local A = GovApps

local function districts()
    local out = {}
    for name, d in pairs((Config.Infrastructure and Config.Infrastructure.Districts) or {}) do
        out[#out + 1] = { id = name, label = d.label or name, priority = d.priority or 100 }
    end
    table.sort(out, function(a, b) return a.priority < b.priority end)
    return out
end

local function zoneView(z)
    if not z then return nil end
    return { id = z.id, scope = z.scope, label = z.label, x = z.x, y = z.y, z = z.z, heading = z.heading, district = z.district, setBy = z.setByName }
end

local function need(src)
    if not HasPermission(src, 'businesses') then return false, 'no_permission' end
    return true
end

local handlers = {}

function handlers.businesses(src)
    if not GovSchema.Ensure() then return { ok = false, error = 'db_unavailable' } end
    local rows = MySQL.query.await([[SELECT business_id, business_name, business_type, COALESCE(business_status, 'active') AS business_status,
        district, location_x, location_y, location_z, location_address FROM pf_gov_businesses ORDER BY business_name LIMIT 300]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.business_id, name = r.business_name, type = r.business_type, status = r.business_status,
            district = r.district, location = A.BusinessPos(r), address = r.location_address }
    end
    local zones = {}
    for _, d in ipairs(districts()) do zones[d.id] = zoneView(DeliveryZones.GetForDistrict(d.id)) end
    return { ok = true, businesses = out, districts = districts(), districtZones = zones,
        slotTypes = (Config.Premises and Config.Premises.SlotTypes) or {} }
end

function handlers.business(src, p)
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local res = A.CallNui('premises:list', src, { businessId = biz.business_id })
    if not res.ok then return res end
    local slots = {}
    for _, s in ipairs((res.data and res.data.slots) or {}) do
        slots[#slots + 1] = { id = tonumber(s.id), type = s.slot_type, label = s.label, x = tonumber(s.x), y = tonumber(s.y), z = tonumber(s.z),
            heading = tonumber(s.heading), equipment = s.equipment_type }
    end
    return {
        ok = true,
        business = { id = biz.business_id, name = biz.business_name, type = biz.business_type, district = biz.district,
            location = A.BusinessPos(biz), address = biz.location_address },
        slots = slots, zone = zoneView(DeliveryZones.GetForBusiness(biz.business_id)), effectiveZone = zoneView(DeliveryZones.Get(biz.business_id)),
        here = A.Pos(src),
    }
end

function handlers.approveSlot(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local here, err = A.AtBusiness(src, biz, false)
    if not here then return { ok = false, error = err } end
    local res = A.CallNui('premises:slot:approve', src, { businessId = biz.business_id, slotType = p.slotType, label = A.Text(p.label, 64) })
    if not res.ok then return { ok = false, error = res.error } end
    return { ok = true, slotId = res.data and res.data.slotId }
end

function handlers.removeSlot(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    local slotId = tonumber(p.slotId)
    local slot = slotId and MySQL.single.await('SELECT id, business_id FROM pf_gov_premises_slots WHERE id = ? AND active = 1', { slotId })
    if not slot or slot.business_id ~= p.businessId then return { ok = false, error = 'slot_not_found' } end
    local res = A.CallNui('premises:slot:remove', src, { slotId = slotId })
    if not res.ok then return { ok = false, error = res.error } end
    return { ok = true }
end

--- The business's default delivery zone where the official stands.
function handlers.setZone(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local here, err = A.AtBusiness(src, biz, false)
    if not here then return { ok = false, error = err } end
    local done, res = DeliveryZones.Set('business', biz.business_id, A.Pos(src), { label = A.Text(p.label, 64), cid = A.Cid(src), name = GetPlayerName(src) })
    if not done then return { ok = false, error = res } end
    return { ok = true, zoneId = res }
end

function handlers.clearZone(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local done, err = DeliveryZones.Clear('business', biz.business_id, A.Cid(src), GetPlayerName(src))
    return { ok = done, error = err }
end

--- A district's fallback delivery zone where the official stands.
function handlers.setDistrictZone(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    if not DeliveryZones.DistrictKnown(p.district) then return { ok = false, error = 'unknown_district' } end
    local done, res = DeliveryZones.Set('district', p.district, A.Pos(src), { label = A.Text(p.label, 64), cid = A.Cid(src), name = GetPlayerName(src) })
    if not done then return { ok = false, error = res } end
    return { ok = true, zoneId = res }
end

function handlers.clearDistrictZone(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    if not DeliveryZones.DistrictKnown(p.district) then return { ok = false, error = 'unknown_district' } end
    local done, err = DeliveryZones.Clear('district', p.district, A.Cid(src), GetPlayerName(src))
    return { ok = done, error = err }
end

function handlers.setDistrict(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local district = p.district ~= nil and p.district ~= '' and p.district or nil
    if district and not DeliveryZones.DistrictKnown(district) then return { ok = false, error = 'unknown_district' } end
    local done, err = DeliveryZones.SetBusinessDistrict(biz.business_id, district)
    if done then LogAudit('business_district', A.Cid(src), GetPlayerName(src), 'business', biz.business_id, { district = district }) end
    return { ok = done, error = err }
end

--- The registry location becomes where the official stands (inspections check against it).
function handlers.setLocation(src, p)
    local ok, why = need(src)
    if not ok then return { ok = false, error = why } end
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local pos = A.Pos(src)
    if not pos then return { ok = false, error = 'no_position' } end
    local res = A.CallNui('business:updateLocation', src, { businessId = biz.business_id, locationX = pos.x, locationY = pos.y, locationZ = pos.z,
        locationAddress = A.Text(p.address, 120) or biz.location_address })
    if not res.ok then return { ok = false, error = res.error } end
    return { ok = true, location = { x = pos.x, y = pos.y, z = pos.z } }
end

A.Define({
    id = 'govsetup', name = 'Business Setup', icon = '📐',
    devices = { 'tablet' },
    entry = 'html/apps/setup.js', styles = { 'html/apps/gov.css' },
    category = 'government', order = 25,
    access = { gov = 'businesses' },
    description = 'Approve equipment slots and delivery zones on site',
    window = { width = 980, height = 660 },
}, handlers)

GovApps.Setup = handlers
