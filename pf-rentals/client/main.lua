-- Main client script for pf-rentals
local QBCore = exports['pfm-core']:GetCoreObject()

-- Variables
local rentalPeds = {}
local rentalBlips = {}
local currentRentalLocation = nil

-- ============================================================================
-- SPAWN RENTAL PEDS
-- ============================================================================

Citizen.CreateThread(function()
    -- Wait for the game to be loaded
    Wait(1000)
    
    for i, location in ipairs(Config.RentalLocations) do
        -- Create ped
        local pedModel = GetHashKey(location.ped.model)
        RequestModel(pedModel)
        
        while not HasModelLoaded(pedModel) do
            Wait(10)
        end
        
        local ped = CreatePed(4, pedModel, location.coords.x, location.coords.y, location.coords.z - 1.0, location.heading, false, true)
        
        SetEntityAsMissionEntity(ped, true, true)
        SetPedFleeAttributes(ped, 0, 0)
        SetPedDiesWhenInjured(ped, false)
        SetPedKeepTask(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        
        -- Set ped task/scenario
        if location.ped.scenario then
            TaskStartScenarioInPlace(ped, location.ped.scenario, 0, true)
        end
        
        -- Store ped
        rentalPeds[i] = ped
        
        -- Add qb-target interaction
        exports['pfm-target']:AddTargetEntity(ped, {
            options = {
                {
                    type = "client",
                    event = "pf-rentals:client:openRentals",
                    icon = "fas fa-car",
                    label = "Browse Rental Vehicles",
                    location = i
                }
            },
            distance = 2.5
        })
        
        -- Create blip if enabled
        if location.blip.enabled then
            local blip = AddBlipForCoord(location.coords.x, location.coords.y, location.coords.z)
            SetBlipSprite(blip, location.blip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, location.blip.scale)
            SetBlipColour(blip, location.blip.color)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(location.blip.label)
            EndTextCommandSetBlipName(blip)
            
            rentalBlips[i] = blip
        end
        
        SetModelAsNoLongerNeeded(pedModel)
    end
    
    if Config.Debug then
        print('^2[pf-rentals]^7 Spawned ' .. #rentalPeds .. ' rental peds')
    end
end)

-- ============================================================================
-- OPEN RENTAL UI EVENT
-- ============================================================================

RegisterNetEvent('pf-rentals:client:openRentals', function(data)
    currentRentalLocation = data.location
    OpenRentalUI()
end)

-- ============================================================================
-- CLEANUP ON RESOURCE STOP
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Delete peds
    for i, ped in ipairs(rentalPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    
    -- Remove blips
    for i, blip in ipairs(rentalBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
end)

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get current rental location spawn point
function GetRentalSpawnPoint()
    if currentRentalLocation and Config.RentalLocations[currentRentalLocation] then
        return Config.RentalLocations[currentRentalLocation].spawnPoint
    end
    
    -- Default fallback
    return vector4(0.0, 0.0, 0.0, 0.0)
end

print('^2[pf-rentals]^7 Main client script loaded!')
