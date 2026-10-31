-- Tow job ↔ other jobs (pf-services requests worked in the Dispatch app):
--   tow.impound   police order a car to the impound lot (pfm-policejob); the city pays the tow.
--   tow.recovery  a citizen (Services app) or a mechanic shop asks for a broken car to be taken to a
--                 mechanic shop; the requester pays the call-out fee.
-- The tow driver hooks the car with the flatbed (pfm-towjob's hook works on any car), drives it to
-- the destination and presses Complete. These checks decide on the server whether the work is done:
-- the car with that plate must be at the destination and the driver next to it.

local TowRequests = {
    Destinations = {
        -- mechanic shops a recovered car may be brought to (extend with your shops)
        { label = 'LS Customs Burton', coords = vector3(-337.39, -136.92, 39.01), radius = 45.0 },
        { label = 'LS Customs La Mesa', coords = vector3(731.81, -1088.82, 22.17), radius = 45.0 },
        { label = 'LS Customs Airport', coords = vector3(-1155.54, -2007.18, 13.18), radius = 45.0 },
        { label = 'LS Customs Harmony', coords = vector3(1175.04, 2640.21, 37.75), radius = 45.0 },
        { label = "Benny's", coords = vector3(-211.55, -1324.55, 30.89), radius = 45.0 },
        { label = "Beeker's Paleto", coords = vector3(110.83, 6626.46, 31.79), radius = 45.0 },
    },
    DriverRange = 40.0, -- the driver must be this close to the delivered car
}

local function trimPlate(p)
    return (tostring(p or ''):gsub('^%s+', ''):gsub('%s+$', '')):upper()
end

local function findVehicle(plate)
    plate = trimPlate(plate)
    if plate == '' then return nil end
    for _, veh in ipairs(GetAllVehicles()) do
        if trimPlate(GetVehicleNumberPlateText(veh)) == plate then return veh end
    end
    return nil
end

local function within(a, b, r)
    return #(vector3(a.x, a.y, a.z or 0.0) - vector3(b.x, b.y, b.z or 0.0)) <= r
end

local function impoundLots()
    if GetResourceState('pfm-policejob') ~= 'started' then return {} end
    local ok, lots = pcall(function() return exports['pfm-policejob']:GetImpoundLots() end)
    return ok and type(lots) == 'table' and lots or {}
end

-- The delivered car must be at one of `places` and the driver next to it.
local function deliveredAt(req, src, places)
    local veh = findVehicle(req.plate)
    if not veh or not DoesEntityExist(veh) then return false, 'vehicle_not_found' end
    local pos = GetEntityCoords(veh)
    local atPlace = false
    for _, p in ipairs(places) do
        if within(pos, p.coords, p.radius or 40.0) then atPlace = true break end
    end
    if not atPlace then return false, 'not_at_destination' end
    if not within(GetEntityCoords(GetPlayerPed(src)), pos, TowRequests.DriverRange) then return false, 'too_far' end
    return true
end

local function recoveryPlaces(req)
    local dest = req.meta and req.meta.destination
    if type(dest) == 'table' and tonumber(dest.x) and tonumber(dest.y) then
        return { { coords = vector3(tonumber(dest.x), tonumber(dest.y), tonumber(dest.z) or 0.0), radius = tonumber(dest.radius) or 45.0 } }
    end
    return TowRequests.Destinations
end

local function register()
    if GetResourceState('pf-services') ~= 'started' then return end
    local services = exports['pf-services']
    services:RegisterRequestHandler('tow.impound', {
        canComplete = function(req, src)
            if not req.plate then return false, 'no_plate' end
            return deliveredAt(req, src, impoundLots())
        end,
        onCompleted = function(req)
            if GetResourceState('pfm-policejob') == 'started' then
                pcall(function() exports['pfm-policejob']:FinalizeImpound(req.plate, req.meta or {}) end)
            end
        end,
    })
    services:RegisterRequestHandler('tow.recovery', {
        canComplete = function(req, src)
            if not req.plate then return false, 'no_plate' end
            return deliveredAt(req, src, recoveryPlaces(req))
        end,
    })
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pf-services' then register() end
end)

exports('GetTowDestinations', function() return TowRequests.Destinations end)
