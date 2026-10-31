-- A deleted character leaves every restaurant's staff, including the owner role. pfm-core raises the
-- server-only event 'pfm-core:server:characterDeleted' after it removed the character; a call from a
-- player is ignored. The restaurant re-registers with pf-government under its next owner (or
-- 'unowned'), so the registry cannot be given the deleted citizenid back at the next start.
-- Running it twice changes nothing the second time.

local function validCitizenId(citizenid)
    return type(citizenid) == 'string' and citizenid ~= '' and #citizenid <= 50 and citizenid:match('^[%w]+$') ~= nil
end

local function remove(citizenid)
    local touched = {}
    for _, row in ipairs(MySQL.query.await('SELECT business_id FROM pf_restaurant_employees WHERE citizenid = ?', { citizenid }) or {}) do
        touched[row.business_id] = true
    end
    for businessId, staff in pairs(RestaurantData.employees or {}) do
        if staff[citizenid] then touched[businessId] = true end
    end
    for businessId in pairs(touched) do
        if RestaurantData.employees and RestaurantData.employees[businessId] then
            RestaurantData.employees[businessId][citizenid] = nil
        end
        DB.DeleteEmployee(businessId, citizenid)   -- deletes the row and re-registers the owner
    end
    return touched
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if not validCitizenId(citizenid) then return end
    local ok, err = pcall(remove, citizenid)
    if not ok then print(('^1[pf-restaurants]^7 cleanup of deleted character %s failed: %s'):format(citizenid, tostring(err))) end
end)
