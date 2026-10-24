-- server/work_orders_debug.lua
-- Debug utilities for work order system testing

local QBCore = exports['pfm-core']:GetCoreObject()

-- Command to get player's current work order data
RegisterCommand('workorder_debug', function(source, args, rawCommand)
    if not (Config and Config.Debug) then return end
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    TriggerClientEvent('pf-mechanicjob:client:debugWorkOrders', source)
end)

-- Client-side debug command
RegisterNetEvent('pf-mechanicjob:client:debugWorkOrders', function()
    if not (Config and Config.Debug) then return end

    PFMech.Debug('[Work Orders Debug] Player vehicle data requested')
    
    if ActiveWorkOrderVehicle then
        PFMech.Debug('[Work Orders Debug] Active Vehicle Data:')
        PFMech.Debug('  Vehicle Handle: ' .. tostring(ActiveWorkOrderVehicle.vehicle))
        PFMech.Debug('  Order ID: ' .. tostring(ActiveWorkOrderVehicle.orderId))
        PFMech.Debug('  Repair Type: ' .. tostring(ActiveWorkOrderVehicle.repairType))
        PFMech.Debug('  Blip: ' .. tostring(VehicleBlip))
        
        local veh = ActiveWorkOrderVehicle.vehicle
        if DoesEntityExist(veh) then
            local coords = GetEntityCoords(veh)
            PFMech.Debug('  Vehicle Position: X=' .. coords.x .. ' Y=' .. coords.y .. ' Z=' .. coords.z)
            PFMech.Debug('  Vehicle Health: ' .. GetVehicleEngineHealth(veh))
        else
            PFMech.Debug('  Vehicle Entity: DOES NOT EXIST')
        end
    else
        PFMech.Debug('[Work Orders Debug] No active vehicle spawned')
    end
end)

-- List all available vehicle models
RegisterCommand('workorder_vehicles', function(source, args, rawCommand)
    if not (Config and Config.Debug) then return end
    local vehList = Config.WorkOrderSystem.vehicles
    PFMech.Debug('[Work Orders] Available Vehicles:')
    for i, veh in ipairs(vehList) do
        PFMech.Debug('  ' .. i .. '. ' .. veh)
    end
    PFMech.Debug('[Work Orders] Total: ' .. #vehList .. ' vehicles')
end)

-- Test spawn a vehicle at current location
RegisterCommand('spawn_test_vehicle', function(source, args, rawCommand)
    if not (Config and Config.Debug) then return end
    local model = args[1] or 'oracle'
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    PFMech.Debug('[Work Orders Test] Attempting to spawn test vehicle: ' .. model)
    TriggerClientEvent('pf-mechanicjob:client:spawnTestVehicle', source, model)
end)

-- Get work order spawn locations
RegisterCommand('workorder_spawns', function(source, args, rawCommand)
    if not (Config and Config.Debug) then return end
    local spawns = Config.WorkOrderSystem.vehicleSpawnLocations
    PFMech.Debug('[Work Orders] Vehicle Spawn Locations:')
    for i, spawn in ipairs(spawns) do
        PFMech.Debug(string.format('  %d. X=%.2f Y=%.2f Z=%.2f H=%.2f', i, spawn.x, spawn.y, spawn.z, spawn.w))
    end
    PFMech.Debug('[Work Orders] Total: ' .. #spawns .. ' spawn locations')
end)

if Config and Config.Debug then
    PFMech.Debug('[Work Orders] Debug utilities loaded')
end
