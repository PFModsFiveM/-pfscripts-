-- Client-side integration with pf-mechanicjob and pf-policemdt
local QBCore = exports['pfm-core']:GetCoreObject()

-- Configuration
local Config = {
    Debug = false,
    MechanicJobResource = 'pf-mechanicjob',
    MDTResource = 'pf-policemdt-DEV',
    RefreshInterval = 30000, -- Update vehicle data every 30 seconds
}

-- Cache
local cachedVehicleData = {}
local lastRefresh = 0

-- ============================================================================
-- VEHICLE DATA GATHERING
-- ============================================================================

-- Get comprehensive vehicle data for garage UI
local function GetVehicleData(plate)
    if not plate then return nil end
    
    local p = promise.new()
    
    QBCore.Functions.TriggerCallback('pf-garage:getVehicleData', function(data)
        p:resolve(data)
    end, plate)
    
    return Citizen.Await(p)
end

-- Get all player vehicles with full integration data
function GetAllPlayerVehicles()
    local p = promise.new()
    
    QBCore.Functions.TriggerCallback('pf-garage:getAllVehicles', function(vehicles)
        if vehicles then
            cachedVehicleData = vehicles
            lastRefresh = GetGameTimer()
        end
        p:resolve(vehicles or {})
    end)
    
    return Citizen.Await(p)
end

-- ============================================================================
-- VEHICLE STATE SYNC (Real-time Updates)
-- ============================================================================

-- Update vehicle state in real-time (called when vehicle changes)
function SyncVehicleState(vehicle, plate)
    if not DoesEntityExist(vehicle) or not plate then return end
    
    local vehState = Entity(vehicle).state
    local partDamage = vehState.partDamage or {}
    
    local data = {
        plate = plate,
        fuel = GetVehicleFuelLevel(vehicle),
        engineHealth = GetVehicleEngineHealth(vehicle),
        bodyHealth = GetVehicleBodyHealth(vehicle),
        tankHealth = GetVehiclePetrolTankHealth(vehicle),
        dirtLevel = GetVehicleDirtLevel(vehicle),
        mileage = vehState.mileage or 0,
        heading = GetEntityHeading(vehicle),
        coords = GetEntityCoords(vehicle),
        
        -- Part damage from mechanic job
        partDamage = {
            oil = partDamage.oil or 0,
            brakes = partDamage.brakes or 0,
            suspension = partDamage.suspension or 0,
            engine_part = partDamage.engine_part or 0,
            body_part = partDamage.body_part or 0,
            -- Add all other parts...
        },
        
        -- Mods/Upgrades
        hasNOS = vehState.hasnitrom or false,
        nosLevel = vehState.noslevel or 0,
        nosColor = vehState.noscolor or nil,
        
        -- Vehicle properties for full customization tracking
        properties = QBCore.Functions.GetVehicleProperties(vehicle)
    }
    
    -- Send to server for caching/saving
    TriggerServerEvent('pf-garage:syncVehicleState', data)
end

-- ============================================================================
-- VEHICLE SPAWNING
-- ============================================================================

-- Handle vehicle spawn from garage UI
RegisterNUICallback('spawnVehicle', function(data, cb)
    local vehicleId = data.vehicleId
    local plate = data.plate
    
    if not plate then
        cb({ success = false, error = 'Invalid plate' })
        return
    end
    
    -- Close UI
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeGarage' })
    
    -- Get vehicle data
    QBCore.Functions.TriggerCallback('pf-garage:canSpawnVehicle', function(canSpawn, vehicle)
        if not canSpawn then
            QBCore.Functions.Notify('Cannot spawn this vehicle', 'error')
            cb({ success = false, error = 'Cannot spawn' })
            return
        end
        
        -- Spawn vehicle (use your existing garage system)
        -- This is a placeholder - integrate with your garage script
        TriggerEvent('garage:client:spawnVehicle', vehicle)
        
        cb({ success = true })
    end, plate)
end)

-- ============================================================================
-- FOLDER MANAGEMENT
-- ============================================================================

RegisterNUICallback('createFolder', function(data, cb)
    TriggerServerEvent('pf-garage:createFolder', data.name, data.icon)
    cb('ok')
end)

RegisterNUICallback('addVehicleToFolder', function(data, cb)
    TriggerServerEvent('pf-garage:addVehicleToFolder', data.vehicleId, data.folderId)
    cb('ok')
end)

RegisterNUICallback('removeVehicleFromFolder', function(data, cb)
    TriggerServerEvent('pf-garage:removeVehicleFromFolder', data.vehicleId)
    cb('ok')
end)

-- ============================================================================
-- FAVORITES
-- ============================================================================

RegisterNUICallback('toggleFavorite', function(data, cb)
    TriggerServerEvent('pf-garage:toggleFavorite', data.plate)
    cb('ok')
end)

-- ============================================================================
-- UI CONTROL
-- ============================================================================

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Open garage UI
RegisterNetEvent('pf-garage:client:openUI', function(garageLocation)
    local vehicles = GetAllPlayerVehicles()
    
    if not vehicles or #vehicles == 0 then
        QBCore.Functions.Notify('No vehicles found', 'error')
        return
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openGarage',
        vehicles = vehicles,
        location = garageLocation
    })
end)

-- Update specific vehicle in UI
RegisterNetEvent('pf-garage:client:updateVehicle', function(plate, data)
    SendNUIMessage({
        action = 'updateVehicle',
        plate = plate,
        data = data
    })
end)

-- ============================================================================
-- MECHANIC JOB INTEGRATION EVENTS
-- ============================================================================

-- Listen for mechanic job repairs/upgrades
RegisterNetEvent('pf-mechanicjob:client:vehicleRepaired', function(plate, partName, newValue)
    -- Update UI if open
    SendNUIMessage({
        action = 'updateVehiclePart',
        plate = plate,
        part = partName,
        value = newValue
    })
end)

RegisterNetEvent('pf-mechanicjob:client:vehicleUpgraded', function(plate, upgradeType, upgradeData)
    -- Update UI if open
    SendNUIMessage({
        action = 'updateVehicleUpgrade',
        plate = plate,
        upgradeType = upgradeType,
        data = upgradeData
    })
end)

-- ============================================================================
-- AUTO-SYNC ON VEHICLE ENTER/EXIT
-- ============================================================================

local currentVehicle = nil
local currentPlate = nil

CreateThread(function()
    while true do
        Wait(1000)
        
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        
        if veh ~= 0 and veh ~= currentVehicle then
            currentVehicle = veh
            currentPlate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
            
            -- Load vehicle state from mechanic job
            if GetResourceState(Config.MechanicJobResource) == 'started' then
                Wait(500)
                SyncVehicleState(veh, currentPlate)
            end
        elseif veh == 0 and currentVehicle then
            -- Exited vehicle - save final state
            if currentVehicle and DoesEntityExist(currentVehicle) and currentPlate then
                SyncVehicleState(currentVehicle, currentPlate)
            end
            currentVehicle = nil
            currentPlate = nil
        end
    end
end)

-- Periodic sync while in vehicle
CreateThread(function()
    while true do
        Wait(Config.RefreshInterval)
        
        if currentVehicle and DoesEntityExist(currentVehicle) and currentPlate then
            SyncVehicleState(currentVehicle, currentPlate)
        end
    end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('GetVehicleData', GetVehicleData)
exports('GetAllPlayerVehicles', GetAllPlayerVehicles)
exports('OpenGarageUI', function()
    TriggerEvent('pf-garage:client:openUI')
end)
