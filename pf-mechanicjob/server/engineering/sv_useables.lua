-- ============================================================================
-- PF MECHANIC JOB - ENGINEERING ITEMS USE HANDLERS (Server)
-- Handles when players use upgrade/service items
-- ============================================================================

local QBCore = exports['pfm-core']:GetCoreObject()
local EngineConfig = require('config.engineering')

if not EngineConfig.Enabled then return end

-- ============================================================================
-- Simple Upgrade Use Handlers
-- ============================================================================

-- Air Filter Upgrade
QBCore.Functions.CreateUseableItem('intake_filter', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success, message = Engineering:ApplySimpleUpgrade(plate, 'intake_filter')
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Air filter installed!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", message}
        })
    end
end)

-- Cat-Back Exhaust
QBCore.Functions.CreateUseableItem('exhaust_catback', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success, message = Engineering:ApplySimpleUpgrade(plate, 'exhaust_catback')
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Cat-back exhaust installed!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", message}
        })
    end
end)

-- Spark Plugs
QBCore.Functions.CreateUseableItem('spark_plugs', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success, message = Engineering:ApplySimpleUpgrade(plate, 'spark_plugs')
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Spark plugs installed!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", message}
        })
    end
end)

-- ECU Tune Basic
QBCore.Functions.CreateUseableItem('ecu_tune_basic', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success, message = Engineering:ApplySimpleUpgrade(plate, 'ecu_tune_basic')
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Basic ECU tune installed!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", message}
        })
    end
end)

-- Premium Oil Service
QBCore.Functions.CreateUseableItem('premium_oil', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success = Engineering:ServiceOil(plate, 250, tostring(source))
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Oil service completed!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "Oil service failed"}
        })
    end
end)

-- Coolant Flush
QBCore.Functions.CreateUseableItem('coolant_flush', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success = Engineering:ServiceCooling(plate, 400, tostring(source))
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Cooling system flushed!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "Service failed"}
        })
    end
end)

-- Sport Tires
QBCore.Functions.CreateUseableItem('sport_tires', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success, message = Engineering:ApplySimpleUpgrade(plate, 'tire_upgrade')
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Sport tires installed!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", message}
        })
    end
end)

-- ============================================================================
-- Major Component Use Handlers
-- ============================================================================

local function InstallComponentItem(source, item, componentType, componentValue, itemName)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success, message = Engineering:InstallComponent(plate, componentType, componentValue)
    
    if success then
        Player.Functions.RemoveItem(itemName, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[itemName], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Component installed successfully!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", message}
        })
    end
end

-- Engine Blocks
QBCore.Functions.CreateUseableItem('engine_block_strengthened', function(source, item)
    InstallComponentItem(source, item, 'engine_block', 'strengthened', item.name)
end)

-- Internals
QBCore.Functions.CreateUseableItem('internals_forged', function(source, item)
    InstallComponentItem(source, item, 'internals', 'forged', item.name)
end)

-- Turbos
QBCore.Functions.CreateUseableItem('turbo_stage1', function(source, item)
    InstallComponentItem(source, item, 'forced_induction', 'turbo_stage1', item.name)
end)

QBCore.Functions.CreateUseableItem('turbo_stage2', function(source, item)
    InstallComponentItem(source, item, 'forced_induction', 'turbo_stage2', item.name)
end)

QBCore.Functions.CreateUseableItem('turbo_stage3', function(source, item)
    InstallComponentItem(source, item, 'forced_induction', 'turbo_stage3', item.name)
end)

-- Superchargers
QBCore.Functions.CreateUseableItem('supercharger_s1', function(source, item)
    InstallComponentItem(source, item, 'forced_induction', 'supercharger_stage1', item.name)
end)

QBCore.Functions.CreateUseableItem('supercharger_s2', function(source, item)
    InstallComponentItem(source, item, 'forced_induction', 'supercharger_stage2', item.name)
end)

-- Intercoolers
QBCore.Functions.CreateUseableItem('intercooler_street', function(source, item)
    InstallComponentItem(source, item, 'intercooler', 'street', item.name)
end)

QBCore.Functions.CreateUseableItem('intercooler_race', function(source, item)
    InstallComponentItem(source, item, 'intercooler', 'race', item.name)
end)

-- Fuel Injectors
QBCore.Functions.CreateUseableItem('fuel_injectors_550', function(source, item)
    InstallComponentItem(source, item, 'fuel_injectors', '550cc', item.name)
end)

QBCore.Functions.CreateUseableItem('fuel_injectors_1000', function(source, item)
    InstallComponentItem(source, item, 'fuel_injectors', '1000cc', item.name)
end)

QBCore.Functions.CreateUseableItem('fuel_injectors_2000', function(source, item)
    InstallComponentItem(source, item, 'fuel_injectors', '2000cc', item.name)
end)

-- Fuel Pumps
QBCore.Functions.CreateUseableItem('fuel_pump_street', function(source, item)
    InstallComponentItem(source, item, 'fuel_pump', 'street', item.name)
end)

QBCore.Functions.CreateUseableItem('fuel_pump_race', function(source, item)
    InstallComponentItem(source, item, 'fuel_pump', 'race', item.name)
end)

-- Intakes
QBCore.Functions.CreateUseableItem('intake_race', function(source, item)
    InstallComponentItem(source, item, 'intake', 'race', item.name)
end)

-- Exhausts
QBCore.Functions.CreateUseableItem('exhaust_race', function(source, item)
    InstallComponentItem(source, item, 'exhaust', 'race', item.name)
end)

-- Cooling
QBCore.Functions.CreateUseableItem('cooling_race', function(source, item)
    InstallComponentItem(source, item, 'cooling', 'race', item.name)
end)

-- Oil System
QBCore.Functions.CreateUseableItem('oil_system_upgraded', function(source, item)
    InstallComponentItem(source, item, 'oil_system', 'upgraded', item.name)
end)

-- Clutches
QBCore.Functions.CreateUseableItem('clutch_street', function(source, item)
    InstallComponentItem(source, item, 'clutch', 'street', item.name)
end)

QBCore.Functions.CreateUseableItem('clutch_race', function(source, item)
    InstallComponentItem(source, item, 'clutch', 'race', item.name)
end)

-- Gearboxes
QBCore.Functions.CreateUseableItem('gearbox_strengthened', function(source, item)
    InstallComponentItem(source, item, 'gearbox', 'strengthened', item.name)
end)

QBCore.Functions.CreateUseableItem('gearbox_race', function(source, item)
    InstallComponentItem(source, item, 'gearbox', 'race', item.name)
end)

-- Differentials
QBCore.Functions.CreateUseableItem('differential_lsd', function(source, item)
    InstallComponentItem(source, item, 'differential', 'lsd', item.name)
end)

QBCore.Functions.CreateUseableItem('differential_race', function(source, item)
    InstallComponentItem(source, item, 'differential', 'race', item.name)
end)

-- ============================================================================
-- Service Items
-- ============================================================================

QBCore.Functions.CreateUseableItem('service_engine_rebuild', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success = Engineering:RebuildEngine(plate, 15000, tostring(source))
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Engine completely rebuilt!"}
        })
    end
end)

QBCore.Functions.CreateUseableItem('service_transmission_rebuild', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)
    
    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
    
    local Engineering = require('server.engineering.sv_engineering')
    local success = Engineering:RebuildGearbox(plate, 12000, tostring(source))
    
    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Transmission completely rebuilt!"}
        })
    end
end)

QBCore.Functions.CreateUseableItem('service_clutch_replacement', function(source, item)
    if Config.AdvancedSystems and Config.AdvancedSystems.Enabled and Config.AdvancedSystems.ClutchWorkflow and Config.AdvancedSystems.ClutchWorkflow.Enabled then
        TriggerClientEvent('pf-mechanicjob:client:advanced:beginClutchWorkflow', source)
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    local ped = GetPlayerPed(source)

    if not IsPedInAnyVehicle(ped, false) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {200, 0, 0},
            multiline = true,
            args = {"Mechanic", "You must be in a vehicle"}
        })
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')

    local Engineering = require('server.engineering.sv_engineering')
    local success = Engineering:ReplaceClutch(plate, 4000, tostring(source))

    if success then
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", "Clutch replaced!"}
        })
    end
end)

-- ============================================================================
-- ECU Tunes
-- ============================================================================

local ecuTunes = {
    ['ecu_tune_eco'] = 'eco',
    ['ecu_tune_street'] = 'street',
    ['ecu_tune_performance'] = 'performance',
    ['ecu_tune_race'] = 'race',
    ['ecu_tune_valet'] = 'valet'
}

for itemName, mapName in pairs(ecuTunes) do
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        local Player = QBCore.Functions.GetPlayer(source)
        local ped = GetPlayerPed(source)
        
        if not IsPedInAnyVehicle(ped, false) then
            TriggerClientEvent('chat:addMessage', source, {
                color = {200, 0, 0},
                multiline = true,
                args = {"Mechanic", "You must be in a vehicle"}
            })
            return
        end
        
        local vehicle = GetVehiclePedIsIn(ped, false)
        local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
        
        local Engineering = require('server.engineering.sv_engineering')
        local success = Engineering:SetECUMap(plate, mapName)
        
        if success then
            Player.Functions.RemoveItem(item.name, 1)
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
            TriggerClientEvent('chat:addMessage', source, {
                color = {0, 200, 0},
                multiline = true,
                args = {"Mechanic", string.format("ECU map changed to: %s", mapName)}
            })
        end
    end)
end

-- ============================================================================
-- Tires
-- ============================================================================

local tireSets = {
    ['tire_semi_slick'] = 'semi_slick',
    ['tire_slick'] = 'slick'
}

for itemName, tireType in pairs(tireSets) do
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        local Player = QBCore.Functions.GetPlayer(source)
        local ped = GetPlayerPed(source)
        
        if not IsPedInAnyVehicle(ped, false) then
            TriggerClientEvent('chat:addMessage', source, {
                color = {200, 0, 0},
                multiline = true,
                args = {"Mechanic", "You must be in a vehicle"}
            })
            return
        end
        
        local vehicle = GetVehiclePedIsIn(ped, false)
        local plate = GetVehicleNumberPlate(vehicle):gsub('%s+', '')
        
        local Engineering = require('server.engineering.sv_engineering')
        local tuning = Engineering:GetOrCreateTuning(plate)
        tuning.tire_compound = tireType
        Engineering:SaveTuning(plate, tuning)
        
        Player.Functions.RemoveItem(item.name, 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 200, 0},
            multiline = true,
            args = {"Mechanic", string.format("Tires changed to: %s", tireType)}
        })
    end)
end

if Config.Debug then
    print('[Engineering] Item use handlers registered')
end
