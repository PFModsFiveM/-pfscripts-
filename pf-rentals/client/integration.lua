-- Client-side integration for pf-rentals
local QBCore = exports['pfm-core']:GetCoreObject()

-- UI State
local rentalUIOpen = false
local currentRentalVehicle = nil
local rentalVehicleNetId = nil

-- ============================================================================
-- OPEN/CLOSE UI
-- ============================================================================

-- Open the rental UI and send available vehicles
function OpenRentalUI()
    if rentalUIOpen then return end
    
    local playerPed = PlayerPedId()
    local vehicles = GetAvailableRentalVehicles()
    
    SendNUIMessage({
        action = 'openRentalUI',
        vehicles = vehicles
    })
    
    SetNuiFocus(true, true)
    rentalUIOpen = true
end

-- Close the rental UI
function CloseRentalUI()
    SendNUIMessage({
        action = 'closeRentalUI'
    })
    
    SetNuiFocus(false, false)
    rentalUIOpen = false
end

-- ============================================================================
-- GET AVAILABLE VEHICLES
-- ============================================================================

function GetAvailableRentalVehicles()
    local p = promise.new()
    
    QBCore.Functions.TriggerCallback('pf-rentals:getAvailableVehicles', function(vehicles)
        -- If screenshot-basic is enabled, generate screenshots for vehicles
        if Config.UseScreenshotBasic and GetResourceState('screenshot-basic') == 'started' then
            for i, vehicle in ipairs(vehicles) do
                -- Generate screenshot URL for each vehicle
                vehicles[i].image = 'nui://screenshot-basic/screenshot.png?model=' .. vehicle.model
            end
        end
        
        p:resolve(vehicles or {})
    end)
    
    return Citizen.Await(p)
end

-- ============================================================================
-- NUI CALLBACKS
-- ============================================================================

RegisterNUICallback('confirmRental', function(data, cb)
    if data then
        TriggerServerEvent('pf-rentals:confirmRental', data)
    end
    cb('ok')
end)

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================

RegisterNetEvent('pf-rentals:rentedVehicle', function(vehicleData)
    CloseRentalUI()
    
    -- Spawn in the rented vehicle
    SpawnRentalVehicle(vehicleData)
    
    -- Notify player
    if Config.UseQBNotifications then
        QBCore.Functions.Notify('Vehicle rented for ' .. vehicleData.duration .. ' day(s). Total: $' .. vehicleData.totalPrice, 'success', 5000)
    else
        TriggerEvent('chat:addMessage', {
            args = {'Rental', 'Vehicle rented for ' .. vehicleData.duration .. ' day(s). Total: $' .. vehicleData.totalPrice},
            color = {0, 255, 0}
        })
    end
end)

RegisterNetEvent('pf-rentals:rentalError', function(message)
    if Config.UseQBNotifications then
        QBCore.Functions.Notify(message, 'error', 5000)
    else
        TriggerEvent('chat:addMessage', {
            args = {'Rental Error', message},
            color = {255, 0, 0}
        })
    end
end)

RegisterNetEvent('pf-rentals:rentalExpired', function(data)
    if Config.UseQBNotifications then
        QBCore.Functions.Notify('Your rental period has expired! The vehicle has been returned.', 'error', 7000)
    else
        TriggerEvent('chat:addMessage', {
            args = {'Rental', 'Your rental period has expired!'},
            color = {255, 165, 0}
        })
    end
    
    -- Delete the rental vehicle if it exists
    if currentRentalVehicle and DoesEntityExist(currentRentalVehicle) then
        DeleteVehicle(currentRentalVehicle)
        currentRentalVehicle = nil
        rentalVehicleNetId = nil
    end
end)

-- ============================================================================
-- SPAWN RENTAL VEHICLE
-- ============================================================================

function SpawnRentalVehicle(vehicleData)
    local spawnPoint = GetRentalSpawnPoint()
    
    -- Request server to spawn the vehicle (like Gruppe6)
    TriggerServerEvent('pf-rentals:spawnVehicle', vehicleData.modelName, spawnPoint, vehicleData)
end

-- Handle server-spawned vehicle
RegisterNetEvent('pf-rentals:vehicleSpawned', function(netId, plate)
    print('[pf-rentals] Received vehicle spawn, netId:', netId)
    
    -- Wait for the network id to propagate
    local timeout = 0
    while not NetworkDoesNetworkIdExist(netId) and timeout < 300 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if not NetworkDoesNetworkIdExist(netId) then
        if Config.UseQBNotifications then
            QBCore.Functions.Notify('Failed to sync vehicle', 'error')
        end
        return
    end
    
    -- Get the vehicle entity from the network ID
    local vehicle = NetToVeh(netId)
    
    -- Wait for the vehicle to exist
    local entityTimeout = 0
    while (not vehicle or not DoesEntityExist(vehicle)) and entityTimeout < 200 do
        Wait(10)
        vehicle = NetToVeh(netId)
        entityTimeout = entityTimeout + 1
    end
    
    if not vehicle or not DoesEntityExist(vehicle) then
        if Config.UseQBNotifications then
            QBCore.Functions.Notify('Failed to find vehicle', 'error')
        end
        return
    end
    
    print('[pf-rentals] Vehicle entity obtained:', vehicle)
    
    -- Set fuel (if using LegacyFuel or qb-fuel or other fuel systems)
    if GetResourceState('LegacyFuel') == 'started' then
        exports['LegacyFuel']:SetFuel(vehicle, 100.0)
    elseif GetResourceState('pfm-fuel') == 'started' then
        exports['pfm-fuel']:SetFuel(vehicle, 100.0)
    end
    
    -- Set vehicle keys
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    
    -- Warp player into vehicle
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    
    -- Store rental vehicle reference
    currentRentalVehicle = vehicle
    rentalVehicleNetId = netId
    
    if Config.UseQBNotifications then
        QBCore.Functions.Notify('Vehicle spawned! Enjoy your rental.', 'success')
    end
end)

-- Helper function to get the nearest rental spawn point
function GetRentalSpawnPoint()
    local playerPos = GetEntityCoords(PlayerPedId())
    local closestSpawnPoint = nil
    local closestDistance = 999999.0
    
    for _, location in ipairs(Config.RentalLocations) do
        local distance = #(playerPos - location.coords)
        if distance < closestDistance then
            closestDistance = distance
            closestSpawnPoint = location.spawnPoint
        end
    end
    
    return closestSpawnPoint or vector4(0.0, 0.0, 0.0, 0.0)
end

-- ============================================================================
-- COMMANDS
-- ============================================================================

RegisterCommand('openrentals', function()
    OpenRentalUI()
end, false)

RegisterCommand('closerentals', function()
    CloseRentalUI()
end, false)

-- ============================================================================
-- KEYBOARD CONTROLS
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        -- ESC to close UI
        if rentalUIOpen and IsControlJustReleased(0, 322) then
            CloseRentalUI()
        end
    end
end)

-- ============================================================================
-- HANDLE UI BEING DISPOSED
-- ============================================================================

RegisterNUICallback('closeRentalUI', function(data, cb)
    CloseRentalUI()
    cb('ok')
end)

-- Cleanup when player logs out or changes character
AddEventHandler('playerLogout', function()
    if rentalUIOpen then
        CloseRentalUI()
    end
end)

print('^2[pf-rentals]^7 Client integration loaded!')
