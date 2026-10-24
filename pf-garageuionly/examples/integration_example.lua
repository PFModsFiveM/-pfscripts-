-- Example integration script for pf-garageuionly
-- This shows how to integrate the garage UI into your existing scripts

local QBCore = exports['pfm-core']:GetCoreObject()

-- ============================================================================
-- EXAMPLE 1: Replace Old Garage Command
-- ============================================================================

-- Simple command to open garage
RegisterCommand('mygarage', function()
    -- Open the modern garage UI
    exports['pf-garageuionly']:OpenGarageUI()
end)

-- ============================================================================
-- EXAMPLE 2: Open Garage at Specific Location
-- ============================================================================

-- Define your garage zones
local garageZones = {
    {
        name = 'Legion Square Parking',
        coords = vector3(215.09, -810.29, 30.73),
        radius = 25.0
    },
    {
        name = 'Sandy Shores Garage',
        coords = vector3(1737.59, 3710.2, 34.14),
        radius = 25.0
    }
}

-- Check if player is in garage zone
CreateThread(function()
    while true do
        Wait(1000)
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        
        for _, garage in ipairs(garageZones) do
            local dist = #(coords - garage.coords)
            
            if dist < garage.radius then
                -- Show help text
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to open garage')
                EndTextCommandDisplayHelp(0, false, true, -1)
                
                -- Check for key press
                if IsControlJustReleased(0, 38) then -- E key
                    TriggerEvent('pf-garage:client:openUI', garage.name)
                end
            end
        end
    end
end)

-- ============================================================================
-- EXAMPLE 3: Custom Vehicle Spawn Handler
-- ============================================================================

-- Handle vehicle spawn request from garage UI
RegisterNetEvent('garage:client:spawnVehicle', function(vehicleData)
    -- Your custom spawn logic here
    
    QBCore.Functions.SpawnVehicle(vehicleData.vehicle, function(veh)
        -- Set vehicle properties
        if vehicleData.mods then
            QBCore.Functions.SetVehicleProperties(veh, json.decode(vehicleData.mods))
        end
        
        -- Set damage/fuel from integrated data
        SetVehicleFuelLevel(veh, vehicleData.fuelPercent or 100)
        SetVehicleEngineHealth(veh, (vehicleData.enginePercent or 100) * 10)
        SetVehicleBodyHealth(veh, (vehicleData.bodyPercent or 100) * 10)
        
        -- Set dirt level
        SetVehicleDirtLevel(veh, (100 - (vehicleData.cleanliness or 100)))
        
        -- Give keys to player
        TriggerEvent('vehiclekeys:client:SetOwner', vehicleData.plate)
        
        QBCore.Functions.Notify('Vehicle spawned: ' .. vehicleData.plate, 'success')
    end)
end)

-- ============================================================================
-- EXAMPLE 4: Add Custom Events to Timeline
-- ============================================================================

-- When vehicle is washed
RegisterNetEvent('carwash:client:washComplete', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then return end
    
    local plate = GetVehicleNumberPlateText(vehicle):gsub('%s+', ''):upper()
    
    -- Add to timeline (server-side)
    TriggerServerEvent('example:addWashToTimeline', plate)
end)

-- Server-side handler
if IsDuplicityVersion() then
    RegisterNetEvent('example:addWashToTimeline', function(plate)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        
        -- Add event to garage timeline
        if GetResourceState('pf-garageuionly') == 'started' then
            exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
                citizenid = Player.PlayerData.citizenid,
                author = 'Car Wash',
                description = 'Vehicle washed and detailed - $50'
            })
        end
    end)
end

-- ============================================================================
-- EXAMPLE 5: Monitor Vehicle Damage and Update Garage
-- ============================================================================

-- Client-side damage monitoring
local lastDamageCheck = 0

CreateThread(function()
    while true do
        Wait(5000) -- Check every 5 seconds
        
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        
        if vehicle ~= 0 and GetGameTimer() - lastDamageCheck > 10000 then
            lastDamageCheck = GetGameTimer()
            
            local plate = GetVehicleNumberPlateText(vehicle):gsub('%s+', ''):upper()
            local engineHealth = GetVehicleEngineHealth(vehicle)
            local bodyHealth = GetVehicleBodyHealth(vehicle)
            local tankHealth = GetVehiclePetrolTankHealth(vehicle)
            local dirtLevel = GetVehicleDirtLevel(vehicle)
            
            -- Send damage update to server
            TriggerServerEvent('example:updateVehicleDamage', plate, {
                engineHealth = engineHealth,
                bodyHealth = bodyHealth,
                tankHealth = tankHealth,
                dirtLevel = dirtLevel
            })
        end
    end
end)

-- Server-side damage update
if IsDuplicityVersion() then
    RegisterNetEvent('example:updateVehicleDamage', function(plate, damageData)
        -- Update garage UI database
        if GetResourceState('pf-garageuionly') == 'started' then
            exports['pf-garageuionly']:UpdateVehicleDamage(plate, damageData)
        end
    end)
end

-- ============================================================================
-- EXAMPLE 6: Get Vehicle Data for Other Purposes
-- ============================================================================

-- Server-side
if IsDuplicityVersion() then
    RegisterCommand('checkvehicle', function(source, args)
        local plate = args[1]
        if not plate then
            TriggerClientEvent('QBCore:Notify', source, 'Usage: /checkvehicle [plate]', 'error')
            return
        end
        
        -- Get comprehensive vehicle data
        local vehicleData = exports['pf-garageuionly']:GetVehicleData(plate)
        
        if not vehicleData then
            TriggerClientEvent('QBCore:Notify', source, 'Vehicle not found', 'error')
            return
        end
        
        -- Display info
        TriggerClientEvent('QBCore:Notify', source, string.format(
            'Vehicle: %s | Mileage: %d km | Police Heat: %s',
            vehicleData.vehicle,
            vehicleData.mileage,
            vehicleData.policeHeat
        ), 'primary')
        
        -- Check repair history
        local repairCount = 0
        for _, event in ipairs(vehicleData.history or {}) do
            if event.type == 'repair' then
                repairCount = repairCount + 1
            end
        end
        
        TriggerClientEvent('QBCore:Notify', source, 'Repair history: ' .. repairCount .. ' repairs', 'primary')
    end, false)
end

-- ============================================================================
-- EXAMPLE 7: Integration with Mechanic Job
-- ============================================================================

-- Server-side: After completing mechanic repair
if IsDuplicityVersion() then
    RegisterNetEvent('example:mechanicRepairComplete', function(plate, repairType, cost, quality)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        
        -- Add to vehicle timeline
        if GetResourceState('pf-garageuionly') == 'started' then
            exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
                citizenid = Player.PlayerData.citizenid,
                author = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
                description = string.format(
                    'Repair: %s | Quality: %d%% | Cost: $%d',
                    repairType,
                    quality,
                    cost
                )
            })
        end
        
        -- Update vehicle damage state
        if GetResourceState('pf-garageuionly') == 'started' then
            -- Refresh data from mechanic job's vehicle_diagnostics
            local diagData = MySQL.single.await([[
                SELECT engineHealth, bodyHealth, tankHealth, dirtLevel 
                FROM vehicle_diagnostics 
                WHERE plate = ?
            ]], { plate })
            
            if diagData then
                exports['pf-garageuionly']:UpdateVehicleDamage(plate, diagData)
            end
        end
    end)
end

-- ============================================================================
-- EXAMPLE 8: Integration with Police MDT
-- ============================================================================

-- Server-side: When creating police incident involving vehicle
if IsDuplicityVersion() then
    RegisterNetEvent('example:createPoliceIncident', function(incidentData)
        -- Your incident creation logic...
        
        -- Make sure vehicle plates are properly stored
        local vehiclePlates = {}
        for _, vehicle in ipairs(incidentData.involvedVehicles or {}) do
            table.insert(vehiclePlates, vehicle.plate)
        end
        
        -- Save to MDT with proper vehicle linking
        MySQL.insert.await([[
            INSERT INTO pf_mdt_incidents 
            (incidentId, title, involvedVehicles, involvedVehicleIds, ...)
            VALUES (?, ?, ?, ?, ...)
        ]], {
            incidentData.id,
            incidentData.title,
            json.encode(incidentData.involvedVehicles),
            json.encode(vehiclePlates), -- This links to garage UI automatically
            -- ... other fields
        })
        
        -- Garage UI will automatically show this incident in vehicle timeline
    end)
end

-- ============================================================================
-- EXAMPLE 9: Get All Player Vehicles
-- ============================================================================

-- Server-side
if IsDuplicityVersion() then
    RegisterCommand('myvehicles', function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        
        -- Get all vehicles for player
        local vehicles = exports['pf-garageuionly']:GetPlayerVehicles(Player.PlayerData.citizenid)
        
        TriggerClientEvent('QBCore:Notify', source, 'You own ' .. #vehicles .. ' vehicles', 'primary')
        
        -- List vehicles
        for i, vehicle in ipairs(vehicles) do
            print(string.format('%d. %s (%s) - Mileage: %d km',
                i,
                vehicle.vehicle,
                vehicle.plate,
                vehicle.mileage
            ))
        end
    end, false)
end

print('^2[EXAMPLE]^7 pf-garageuionly integration examples loaded')
print('^3Commands:^7 /mygarage, /checkvehicle [plate], /myvehicles')
