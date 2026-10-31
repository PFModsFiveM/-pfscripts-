-- Bus Job Application - Client Side
-- Handles player commands, route navigation, and UI

local CurrentRoute = nil
local CurrentStop = 1
local IsOnBusJob = false
local BusDistance = 0
local RouteStartTime = 0

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Check if player is in allowed bus vehicle
local function isInBusVehicle()
    if not IsPedInAnyVehicle(PlayerPedId(), false) then
        return false
    end
    
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if not DoesEntityExist(vehicle) then
        return false
    end
    
    local model = GetEntityModel(vehicle)
    for _, vehicleModel in ipairs(Config.Bus.AllowedVehicles) do
        if GetHashKey(vehicleModel) == model then
            return true, vehicle
        end
    end
    
    return false
end

-- Calculate distance between two points (3D)
local function calculateDistance(point1, point2)
    local dx = point1.x - point2.x
    local dy = point1.y - point2.y
    local dz = point1.z - point2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Convert distance to miles (GTA uses ~0.00038 miles per unit)
local function unitsToMiles(units)
    return units * 0.00038
end

-- Get vehicle health percent
local function getVehicleHealth()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if not DoesEntityExist(vehicle) then return 100 end
    
    local health = GetEntityHealth(vehicle)
    local maxHealth = GetEntityMaxHealth(vehicle)
    return math.floor((health / maxHealth) * 100)
end

-- ============================================================================
-- ROUTE DISPLAY
-- ============================================================================

-- Display active route information
local function displayRouteUI()
    if not IsOnBusJob or not CurrentRoute then return end
    
    -- Get current stop
    local currentStop = CurrentRoute.stops[CurrentStop]
    if not currentStop then return end
    
    -- Draw 3D waypoint
    DrawMarker(1, currentStop.coords.x, currentStop.coords.y, currentStop.coords.z, 0, 0, 0, 0, 0, 0, 2.0, 2.0, 2.0, 0, 255, 0, 200, false, true, 2, false, nil, nil, false)
    
    -- Draw route heading
    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = calculateDistance(playerCoords, currentStop.coords)
    
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentString(string.format("~b~Bus Route: ~s~%s~n~~b~Stop: ~s~%s~n~~b~Distance: ~s~%.2f m~n~~b~Stop %d/%d", CurrentRoute.name, currentStop.name, distance, CurrentStop, #CurrentRoute.stops))
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- ============================================================================
-- COMMANDS
-- ============================================================================

-- Start bus route
RegisterCommand('busstart', function(source, args, rawCommand)
    local inBus, vehicle = isInBusVehicle()
    if not inBus then
        TriggerEvent('QBCore:Notify', 'You must be in a bus vehicle', 'error')
        return
    end
    
    if IsOnBusJob then
        TriggerEvent('QBCore:Notify', 'You are already on a route', 'error')
        return
    end
    
    -- Open route selection (will use tablet or menu)
    TriggerEvent('bus:client:openRouteMenu')
end)

-- Next stop (complete current stop): /busstop, or the Bus app through bus:client:completeStop
local function checkInStop()
    if not IsOnBusJob or not CurrentRoute then
        TriggerEvent('QBCore:Notify', 'You are not on a route', 'error')
        return
    end
    
    local currentStop = CurrentRoute.stops[CurrentStop]
    if not currentStop then
        TriggerEvent('QBCore:Notify', 'Invalid stop', 'error')
        return
    end
    
    -- Check distance to stop
    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = calculateDistance(playerCoords, currentStop.coords)
    
    if distance > 10 then
        TriggerEvent('QBCore:Notify', 'You are too far from the stop (~r~' .. string.format('%.1f', distance) .. 'm~s~)', 'error')
        return
    end
    
    -- Complete stop
    TriggerServerEvent('bus:server:completeStop', CurrentStop)
    
    -- Move to next stop
    CurrentStop = CurrentStop + 1
    
    if CurrentStop > #CurrentRoute.stops then
        -- Route complete
        TriggerEvent('bus:client:completeRoute')
    else
        -- Set waypoint to next stop
        local nextStop = CurrentRoute.stops[CurrentStop]
        SetNewWaypoint(nextStop.coords.x, nextStop.coords.y)
        TriggerEvent('QBCore:Notify', 'Next stop: ' .. nextStop.name, 'success')
    end
end
RegisterCommand('busstop', function() checkInStop() end)
RegisterNetEvent('bus:client:completeStop', function() checkInStop() end)

-- Complete route
RegisterCommand('buscomplete', function(source, args, rawCommand)
    if not IsOnBusJob or not CurrentRoute then
        TriggerEvent('QBCore:Notify', 'You are not on a route', 'error')
        return
    end
    
    TriggerEvent('bus:client:completeRoute')
end)

-- Cancel current route
RegisterCommand('buscancel', function(source, args, rawCommand)
    if not IsOnBusJob then
        TriggerEvent('QBCore:Notify', 'You are not on a route', 'error')
        return
    end
    
    TriggerServerEvent('bus:server:cancelRoute')
    IsOnBusJob = false
    CurrentRoute = nil
    CurrentStop = 1
    RemoveBlip(GetFirstBlipInfoForDirection(GetBlipFromEntity(PlayerPedId())))
    TriggerEvent('QBCore:Notify', 'Route cancelled', 'info')
end)

-- Show bus stats
RegisterCommand('busstats', function(source, args, rawCommand)
    TriggerServerEvent('bus:server:getStats')
end)

-- ============================================================================
-- ROUTE MANAGEMENT
-- ============================================================================

-- Load route from server
RegisterNetEvent('bus:client:loadRoute', function(route, level)
    CurrentRoute = route
    CurrentStop = 1
    IsOnBusJob = true
    RouteStartTime = GetGameTimer()
    
    -- Set first waypoint
    local firstStop = route.stops[1]
    SetNewWaypoint(firstStop.coords.x, firstStop.coords.y)
    
    TriggerEvent('QBCore:Notify', 'Route loaded: ' .. route.name .. ' - First stop: ' .. firstStop.name, 'success')
end)

-- Complete route and calculate earnings
local function completeRoute()
    if not IsOnBusJob or not CurrentRoute then return end
    
    local inBus, vehicle = isInBusVehicle()
    if not inBus then
        TriggerEvent('QBCore:Notify', 'You must be in a bus to complete the route', 'error')
        return
    end
    
    -- Calculate route completion time
    local completionTime = (GetGameTimer() - RouteStartTime) / 1000 / 60 -- Convert to minutes
    local isOnTime = completionTime <= (CurrentRoute.estimatedTime / 1000 / 60)
    
    -- Get vehicle health
    local vehicleHealth = getVehicleHealth()
    
    -- Get average rating (random for now, can be interactive)
    local averageRating = 4.5 + math.random(0, 10) / 10
    
    local completionData = {
        playerLevel = nil,  -- Will be set by server
        vehicleHealth = vehicleHealth,
        averageRating = averageRating,
        isOnTime = isOnTime,
        completionTime = completionTime,
    }
    
    -- Send to server. The route is cleared when the server confirms (bus:client:updateStats), so a
    -- completion it refused (too early) can be sent again with /buscomplete or from the Bus app.
    TriggerServerEvent('bus:server:completeRoute', completionData)
end

local function clearRoute()
    IsOnBusJob = false
    CurrentRoute = nil
    CurrentStop = 1
end

-- the route was cancelled on the server (for example from the Bus app)
RegisterNetEvent('bus:client:routeCancelled', function()
    clearRoute()
end)

RegisterNetEvent('bus:client:completeRoute', function()
    completeRoute()
end)

-- Update player stats
RegisterNetEvent('bus:client:updateStats', function(stats)
    clearRoute()
    TriggerEvent('QBCore:Notify', string.format('Route stats - Routes: %d | Passengers: %d | Level: %d', stats.routesCompleted, stats.totalPassengers, stats.level), 'success')
end)

-- ============================================================================
-- UI UPDATES
-- ============================================================================

-- Main loop for route display
Citizen.CreateThread(function()
    while true do
        Wait(100)
        
        if IsOnBusJob and CurrentRoute then
            displayRouteUI()
        end
    end
end)

-- ============================================================================
-- MENU/TABLET INTEGRATION
-- ============================================================================

-- Open route selection menu
local routeMenuWanted = false
RegisterNetEvent('bus:client:openRouteMenu', function()
    routeMenuWanted = true
    TriggerServerEvent('bus:server:getRoutes')
end)

-- Receive available routes. The menu opens only when asked for (/busstart): the Bus app and the
-- tablet also fetch the routes, and used to pop this menu up every time.
RegisterNetEvent('bus:client:routesData', function(routes)
    if not routeMenuWanted then return end
    routeMenuWanted = false
    if not routes or #routes == 0 then
        TriggerEvent('QBCore:Notify', 'No routes available for your level', 'error')
        return
    end
    
    -- Create menu options
    local menuOptions = {}
    
    for _, route in ipairs(routes) do
        local baseFare, passengers = calculateFarePreview(route)
        
        table.insert(menuOptions, {
            header = route.name,
            txt = string.format("Difficulty: %s | Time: %d min | Pay: $%d | Passengers: %d", 
                route.difficulty, route.estimatedTime / 1000 / 60, baseFare, passengers),
            params = {
                event = "bus:client:selectRoute",
                args = {routeId = route.id}
            }
        })
    end
    
    TriggerEvent('QBCore:OpenMenu', menuOptions)
end)

-- Select and start route
RegisterNetEvent('bus:client:selectRoute', function(data)
    local routeId = data.routeId
    TriggerServerEvent('bus:server:startRoute', routeId)
end)

-- Helper: Calculate preview fare for display
function calculateFarePreview(route)
    local baseFare = 0
    local totalPassengers = 0
    
    for _, stop in ipairs(route.stops) do
        if stop.isPickup then
            totalPassengers = totalPassengers + stop.passengerCount
        end
    end
    
    baseFare = (totalPassengers * Config.Bus.Pricing.BasePayPerPassenger) + 
               (route.baseDistance * Config.Bus.Pricing.PayPerMile)
    
    return baseFare, totalPassengers
end

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

-- Export functions for other resources
exports('GetCurrentRoute', function()
    return CurrentRoute
end)

exports('IsOnBusJob', function()
    return IsOnBusJob
end)

exports('GetCurrentStop', function()
    return CurrentStop
end)