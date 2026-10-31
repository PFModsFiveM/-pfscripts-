-- Bus job (client): the depot, the route on the map, stop check-ins and the passengers you see.
-- The server decides everything that counts (stops, who boards, pay); this script only asks it and
-- shows the result. The Bus app (html/apps/bus.js) drives the same events.

local QBCore = exports['pfm-core']:GetCoreObject()

local CurrentRoute = nil
local CurrentStop = 1
local IsOnBusJob = false
local StopBlip = nil
local DepotBlip = nil
local MyBus = nil          -- entity of the depot bus
local RidingPeds = {}      -- passenger peds sitting in the bus (visual only)
local CheckInPending = false

local function cfg() return Config.Bus or {} end

-- ── helpers ─────────────────────────────────────────────────────────

local function isInBusVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return false end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(vehicle) then return false end
    local model = GetEntityModel(vehicle)
    for _, m in ipairs(cfg().AllowedVehicles or {}) do
        if GetHashKey(m) == model then return true, vehicle end
    end
    return false
end

local function distanceTo(c)
    return #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z))
end

local function removeStopBlip()
    if StopBlip and DoesBlipExist(StopBlip) then RemoveBlip(StopBlip) end
    StopBlip = nil
end

local function markStop(stop)
    removeStopBlip()
    if not stop then return end
    StopBlip = AddBlipForCoord(stop.coords.x, stop.coords.y, stop.coords.z)
    SetBlipSprite(StopBlip, 513)
    SetBlipColour(StopBlip, 3)
    SetBlipRoute(StopBlip, true)
    SetBlipRouteColour(StopBlip, 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Bus stop: ' .. (stop.name or ''))
    EndTextCommandSetBlipName(StopBlip)
end

local function pedModels()
    local list = cfg().PedModels
    if type(list) == 'table' and #list > 0 then return list end
    return { 'a_m_y_business_01', 'a_f_y_business_01', 'a_m_m_bevhills_01', 'a_f_y_tourist_01' }
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 100 do Wait(20) t = t + 1 end
    return HasModelLoaded(hash) and hash or nil
end

local function freeSeat(veh)
    local seats = GetVehicleMaxNumberOfPassengers(veh)
    for i = seats - 1, 0, -1 do
        if IsVehicleSeatFree(veh, i) then return i end
    end
    return nil
end

-- Passengers getting off walk away and are removed a little later.
local function letOff(veh, count)
    for _ = 1, count do
        local ped = table.remove(RidingPeds)
        if not ped then break end
        if DoesEntityExist(ped) then
            TaskLeaveVehicle(ped, veh, 0)
            SetEntityAsNoLongerNeeded(ped)
            SetTimeout(30000, function() if DoesEntityExist(ped) then DeletePed(ped) end end)
        end
    end
end

-- Waiting passengers walk up and take a free seat (at most PassengerPeds per stop).
local function letOn(veh, stop, count)
    count = math.min(count, tonumber(cfg().PassengerPeds) or 4)
    local models = pedModels()
    for i = 1, count do
        local seat = freeSeat(veh)
        if not seat then break end
        local hash = loadModel(models[math.random(#models)])
        if not hash then break end
        local a = (i / count) * 2 * math.pi
        local pos = vector3(stop.coords.x + math.cos(a) * 3.0, stop.coords.y + math.sin(a) * 3.0, stop.coords.z)
        local ped = CreatePed(4, hash, pos.x, pos.y, pos.z - 0.98, 0.0, false, true)
        SetModelAsNoLongerNeeded(hash)
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskEnterVehicle(ped, veh, 15000, seat, 1.0, 1, 0)
        RidingPeds[#RidingPeds + 1] = ped
    end
end

local function clearPeds()
    for _, ped in ipairs(RidingPeds) do
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    RidingPeds = {}
end

local function clearRoute()
    IsOnBusJob = false
    CurrentRoute = nil
    CurrentStop = 1
    CheckInPending = false
    removeStopBlip()
end

-- ── route ───────────────────────────────────────────────────────────

RegisterNetEvent('bus:client:loadRoute', function(route, level)
    CurrentRoute = route
    CurrentStop = 1
    IsOnBusJob = true
    CheckInPending = false
    local first = route.stops[1]
    markStop(first)
    QBCore.Functions.Notify(('Route loaded: %s. First stop: %s'):format(route.name, first.name), 'success')
end)

-- /busstop and the Bus app: ask the server to check the current stop in.
local function checkInStop()
    if not IsOnBusJob or not CurrentRoute then
        QBCore.Functions.Notify('You are not on a route', 'error')
        return
    end
    local stop = CurrentRoute.stops[CurrentStop]
    if not stop then return end
    local d = distanceTo(stop.coords)
    if d > 10 then
        QBCore.Functions.Notify(('You are too far from the stop (%.1f m)'):format(d), 'error')
        return
    end
    if CheckInPending then return end
    CheckInPending = true
    SetTimeout(3000, function() CheckInPending = false end)
    TriggerServerEvent('bus:server:completeStop', CurrentStop)
end
RegisterCommand('busstop', function() checkInStop() end)
RegisterNetEvent('bus:client:completeStop', function() checkInStop() end)

local function completeRoute()
    if not IsOnBusJob or not CurrentRoute then return end
    if not isInBusVehicle() then
        QBCore.Functions.Notify('You must be in your bus to finish the route', 'error')
        return
    end
    -- the route is cleared when the server confirms it (bus:client:updateStats)
    TriggerServerEvent('bus:server:completeRoute')
end
RegisterNetEvent('bus:client:completeRoute', function() completeRoute() end)

-- The server confirmed a stop: show who got off and on, then head for the next one.
RegisterNetEvent('bus:client:stopCompleted', function(stopNumber, total, info)
    CheckInPending = false
    if not CurrentRoute then return end
    info = type(info) == 'table' and info or {}
    local stop = CurrentRoute.stops[stopNumber]
    CurrentStop = stopNumber + 1
    local inBus, veh = isInBusVehicle()
    if inBus and stop then
        letOff(veh, tonumber(info.alighted) or 0)
        if stopNumber < total then letOn(veh, stop, tonumber(info.boarded) or 0) end
    end
    if CurrentStop > total then
        clearPeds()
        removeStopBlip()
        completeRoute()
    else
        local nextStop = CurrentRoute.stops[CurrentStop]
        markStop(nextStop)
        QBCore.Functions.Notify('Next stop: ' .. nextStop.name, 'primary')
    end
end)

RegisterCommand('buscomplete', function()
    if not IsOnBusJob or not CurrentRoute then
        QBCore.Functions.Notify('You are not on a route', 'error')
        return
    end
    completeRoute()
end)

RegisterCommand('buscancel', function()
    if not IsOnBusJob then
        QBCore.Functions.Notify('You are not on a route', 'error')
        return
    end
    TriggerServerEvent('bus:server:cancelRoute')
end)

RegisterCommand('busstats', function() TriggerServerEvent('bus:server:getStats') end)

-- the route was cancelled on the server (for example from the Bus app)
RegisterNetEvent('bus:client:routeCancelled', function()
    clearPeds()
    clearRoute()
end)

RegisterNetEvent('bus:client:updateStats', function(stats)
    clearPeds()
    clearRoute()
    if type(stats) == 'table' then
        QBCore.Functions.Notify(('Routes: %d | Passengers: %d | Level: %d'):format(stats.routesCompleted or 0, stats.totalPassengers or 0, stats.level or 1), 'success')
    end
end)

-- Stop marker and help text while on a route
CreateThread(function()
    while true do
        local wait = 1000
        if IsOnBusJob and CurrentRoute then
            local stop = CurrentRoute.stops[CurrentStop]
            if stop then
                local d = distanceTo(stop.coords)
                if d < 120.0 then
                    wait = 0
                    DrawMarker(1, stop.coords.x, stop.coords.y, stop.coords.z - 1.0, 0, 0, 0, 0, 0, 0, 6.0, 6.0, 1.0, 0, 200, 120, 120, false, false, 2, false, nil, nil, false)
                    if d < 10.0 then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName(('~b~%s~s~ (stop %d/%d)~n~/busstop or the Bus app to check in'):format(stop.name, CurrentStop, #CurrentRoute.stops))
                        EndTextCommandDisplayHelp(0, false, false, -1)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ── route menu (/busstart) ──────────────────────────────────────────

RegisterCommand('busstart', function()
    if not isInBusVehicle() then
        QBCore.Functions.Notify('You must be in a bus', 'error')
        return
    end
    if IsOnBusJob then
        QBCore.Functions.Notify('You are already on a route', 'error')
        return
    end
    TriggerEvent('bus:client:openRouteMenu')
end)

local routeMenuWanted = false
RegisterNetEvent('bus:client:openRouteMenu', function()
    routeMenuWanted = true
    TriggerServerEvent('bus:server:getRoutes')
end)

-- The menu opens only when asked for (/busstart): the Bus app also fetches the routes.
RegisterNetEvent('bus:client:routesData', function(routes)
    if not routeMenuWanted then return end
    routeMenuWanted = false
    if not routes or #routes == 0 then
        QBCore.Functions.Notify('No routes available for your level', 'error')
        return
    end
    local options = {}
    for _, route in ipairs(routes) do
        options[#options + 1] = {
            header = route.name,
            txt = ('%s | %d stops | ~%d min | ~%d passengers | from $%d'):format(route.difficulty or 'easy', route.stopCount or 0,
                math.floor((route.estimatedTime or 0) / 60000), route.expectedPassengers or 0, route.estimatedPay or 0),
            params = { event = 'bus:client:selectRoute', args = { routeId = route.id } },
        }
    end
    exports['pfm-menu']:openMenu(options)
end)

RegisterNetEvent('bus:client:selectRoute', function(data)
    if type(data) ~= 'table' then return end
    TriggerServerEvent('bus:server:startRoute', data.routeId)
end)

-- ── depot ───────────────────────────────────────────────────────────

RegisterNetEvent('bus:client:vehicleSpawned', function(netId, plate)
    local t = 0
    while not NetworkDoesNetworkIdExist(netId) and t < 300 do Wait(10) t = t + 1 end
    local veh = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
    t = 0
    while (veh == 0 or not DoesEntityExist(veh)) and t < 200 do Wait(10) veh = NetToVeh(netId) t = t + 1 end
    if veh == 0 or not DoesEntityExist(veh) then return end
    MyBus = veh
    pcall(function() exports['LegacyFuel']:SetFuel(veh, 100.0) end)
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    SetVehicleEngineOn(veh, true, true, false)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
end)

RegisterNetEvent('bus:client:busReturned', function()
    clearPeds()
    MyBus = nil
end)

RegisterNetEvent('bus:client:takeBus', function(data)
    local model = type(data) == 'table' and data.model or 'bus'
    TriggerServerEvent('bus:server:spawnBus', model)
end)

RegisterNetEvent('bus:client:returnBus', function()
    TriggerServerEvent('bus:server:returnBus')
end)

local function setupDepot()
    local depot = cfg().Depot
    if not cfg().Enabled or not depot or not depot.coords then return end
    if not DepotBlip then
        DepotBlip = AddBlipForCoord(depot.coords.x, depot.coords.y, depot.coords.z)
        SetBlipSprite(DepotBlip, 513)
        SetBlipDisplay(DepotBlip, 4)
        SetBlipScale(DepotBlip, 0.6)
        SetBlipAsShortRange(DepotBlip, true)
        SetBlipColour(DepotBlip, 49)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(depot.label or 'Bus Depot')
        EndTextCommandSetBlipName(DepotBlip)
    end
    local options = {}
    for _, v in ipairs(cfg().Vehicles or {}) do
        options[#options + 1] = { type = 'client', event = 'bus:client:takeBus', icon = 'fas fa-bus',
            label = ('Take a %s (level %d)'):format(v.label or v.model, v.minLevel or 1), model = v.model }
    end
    options[#options + 1] = { type = 'client', event = 'bus:client:returnBus', icon = 'fas fa-warehouse', label = 'Return your bus' }
    pcall(function()
        exports['pfm-target']:AddBoxZone('pf_bus_depot', vector3(depot.coords.x, depot.coords.y, depot.coords.z), 6.0, 6.0, {
            name = 'pf_bus_depot', heading = 0, debugPoly = false, minZ = depot.coords.z - 2.0, maxZ = depot.coords.z + 3.0,
        }, { options = options, distance = 4.0 })
    end)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then setupDepot() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearPeds()
    removeStopBlip()
end)

exports('GetCurrentRoute', function() return CurrentRoute end)
exports('IsOnBusJob', function() return IsOnBusJob end)
exports('GetCurrentStop', function() return CurrentStop end)
