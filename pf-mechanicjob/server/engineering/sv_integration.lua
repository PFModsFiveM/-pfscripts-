-- ============================================================================
-- PF MECHANIC JOB - ENGINEERING INTEGRATION
-- (Integration with existing repair, cosmetics, and tablet systems)
-- ============================================================================

local QBCore = exports['pfm-core']:GetCoreObject()
local EngineConfig = require('config.engineering')

if not EngineConfig.Enabled then
    if Config.Debug then
        print('[Engineering Integration] System disabled')
    end
    return
end

-- ============================================================================
-- Repair System Integration
-- ============================================================================

---Hook into existing repair to sync vehicle data
RegisterNetEvent('pf-mechanicjob:server:applyBrakeRepair', function(vehNet, requestedUse)
    local src = source
    -- After repair completes, sync engineering
    SetTimeout(500, function()
        local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
        if veh and DoesEntityExist(veh) then
            local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
            TriggerClientEvent('engineering:requestTuning', src, plate)
        end
    end)
end)

-- ============================================================================
-- Upgrade Items Compatibility
-- ============================================================================

---Upgrade item use handler - map old upgrades to engineering system
-- Server-only: no client sends it, and as a network event it applied upgrades with no item.
AddEventHandler('pf-mechanicjob:server:upgradeItem', function(vehNet, itemName, amount)
    local src = source
    if not vehNet or not itemName then return end
    
    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or not DoesEntityExist(veh) then return end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    local Engineering = require('server.engineering.sv_engineering')
    
    -- Map old items to simple upgrades
    local upgradeMap = {
        ['engine_upgrade_1'] = 'intake_filter',
        ['engine_upgrade_2'] = 'exhaust_catback',
        ['engine_upgrade_3'] = 'ecu_tune_basic',
        ['spark_plugs'] = 'spark_plugs',
        ['oil_change'] = 'oil_change',
        ['coolant_flush'] = 'coolant_flush',
        ['tire_upgrade'] = 'tire_upgrade'
    }
    
    local upgradeId = upgradeMap[itemName]
    if upgradeId then
        local success, message = Engineering:ApplySimpleUpgrade(plate, upgradeId)
        if success then
            TriggerClientEvent('chat:addMessage', src, {
                color = {0, 200, 0},
                multiline = true,
                args = {"Mechanic", "Upgrade applied successfully"}
            })
        else
            TriggerClientEvent('chat:addMessage', src, {
                color = {200, 0, 0},
                multiline = true,
                args = {"Mechanic", message}
            })
        end
    end
end)

-- ============================================================================
-- Service and Maintenance Callbacks
-- ============================================================================

---Callback to check oil condition
QBCore.Functions.CreateCallback('engineering:checkOilCondition', function(source, cb, vehNet)
    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or not DoesEntityExist(veh) then
        cb(nil)
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    local Engineering = require('server.engineering.sv_engineering')
    local tuning = Engineering:GetOrCreateTuning(plate)
    
    local cost = EngineConfig.ServiceCosts.oil_change
    
    cb({
        oil_quality = tuning.oil_quality,
        engine_wear = tuning.engine_wear,
        cost = cost,
        recommended = tuning.oil_quality < 50 or tuning.engine_wear > 30
    })
end)

---Callback to check cooling system
QBCore.Functions.CreateCallback('engineering:checkCoolingSystem', function(source, cb, vehNet)
    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or not DoesEntityExist(veh) then
        cb(nil)
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    local Engineering = require('server.engineering.sv_engineering')
    local tuning = Engineering:GetOrCreateTuning(plate)
    
    local cost = EngineConfig.ServiceCosts.coolant_flush
    
    cb({
        coolant_quality = tuning.coolant_quality,
        engine_heat = tuning.engine_heat,
        cost = cost,
        recommended = tuning.coolant_quality < 40 or tuning.engine_heat > 70
    })
end)

---Callback to check engine condition
QBCore.Functions.CreateCallback('engineering:checkEngineCondition', function(source, cb, vehNet)
    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or not DoesEntityExist(veh) then
        cb(nil)
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    local Engineering = require('server.engineering.sv_engineering')
    local tuning = Engineering:GetOrCreateTuning(plate)
    
    local cost = EngineConfig.ServiceCosts.engine_rebuild
    
    cb({
        engine_wear = tuning.engine_wear,
        turbo_wear = tuning.turbo_wear,
        cost = cost,
        recommended = tuning.engine_wear > 50 or tuning.turbo_wear > 60,
        is_turbocharged = tuning.forced_induction ~= 'none'
    })
end)

---Callback to check clutch condition
QBCore.Functions.CreateCallback('engineering:checkClutchCondition', function(source, cb, vehNet)
    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or not DoesEntityExist(veh) then
        cb(nil)
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    local Engineering = require('server.engineering.sv_engineering')
    local tuning = Engineering:GetOrCreateTuning(plate)
    
    local cost = EngineConfig.ServiceCosts.clutch_replacement
    
    cb({
        clutch_wear = tuning.clutch_wear,
        cost = cost,
        can_replace = tuning.clutch_wear > 50,
        recommended = tuning.clutch_wear > 70
    })
end)

---Callback to check gearbox condition
QBCore.Functions.CreateCallback('engineering:checkGearboxCondition', function(source, cb, vehNet)
    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or not DoesEntityExist(veh) then
        cb(nil)
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    local Engineering = require('server.engineering.sv_engineering')
    local tuning = Engineering:GetOrCreateTuning(plate)
    
    local cost = EngineConfig.ServiceCosts.gearbox_rebuild
    
    cb({
        gearbox_wear = tuning.gearbox_wear,
        cost = cost,
        can_service = tuning.gearbox_wear > 50,
        recommended = tuning.gearbox_wear > 70
    })
end)

-- ============================================================================
-- Tablet Integration Points
-- ============================================================================

---Get full vehicle diagnostic report
QBCore.Functions.CreateCallback('engineering:getDiagnosticReport', function(source, cb, vehNet)
    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or not DoesEntityExist(veh) then
        cb(nil)
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', '')
    local Engineering = require('server.engineering.sv_engineering')
    local summary = Engineering:GetBuildSummary(plate)
    
    local diagnosticReport = {
        plate = plate,
        build = summary,
        services_available = {
            {name = 'Oil Change', cost = EngineConfig.ServiceCosts.oil_change, type = 'oil'},
            {name = 'Cooling Flush', cost = EngineConfig.ServiceCosts.coolant_flush, type = 'cooling'},
            {name = 'Engine Rebuild', cost = EngineConfig.ServiceCosts.engine_rebuild, type = 'engine'},
            {name = 'Clutch Replacement', cost = EngineConfig.ServiceCosts.clutch_replacement, type = 'clutch'},
            {name = 'Gearbox Service', cost = EngineConfig.ServiceCosts.gearbox_rebuild, type = 'gearbox'}
        },
        recommendations = {}
    }
    
    -- Generate recommendations
    local summary = summary
    if summary.oil_quality < 50 then
        table.insert(diagnosticReport.recommendations, "Oil is degraded - recommend service")
    end
    if summary.coolant_quality < 50 then
        table.insert(diagnosticReport.recommendations, "Coolant needs replacement")
    end
    if summary.engine_wear > 50 then
        table.insert(diagnosticReport.recommendations, "Engine is worn - consider rebuild")
    end
    if summary.clutch_wear > 70 then
        table.insert(diagnosticReport.recommendations, "Clutch is near failure - replace")
    end
    if summary.boost_psi > 0 and summary.engine_heat > 80 then
        table.insert(diagnosticReport.recommendations, "Turbo running hot - check cooling")
    end
    
    cb(diagnosticReport)
end)

-- ============================================================================
-- Export Functions for Tablets and Menus
-- ============================================================================

exports('ApplyService', function(plate, serviceType, cost)
    if not EngineConfig.Enabled then return false end
    
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    
    local Engineering = require('server.engineering.sv_engineering')
    local mechanicId = 'system'  -- Or could be player ID
    
    if serviceType == 'oil' then
        return Engineering:ServiceOil(plate, cost, mechanicId)
    elseif serviceType == 'cooling' then
        return Engineering:ServiceCooling(plate, cost, mechanicId)
    elseif serviceType == 'engine' then
        return Engineering:RebuildEngine(plate, cost, mechanicId)
    elseif serviceType == 'clutch' then
        return Engineering:ReplaceClutch(plate, cost, mechanicId)
    elseif serviceType == 'gearbox' then
        return Engineering:RebuildGearbox(plate, cost, mechanicId)
    end
    
    return false
end)

exports('GetServiceCosts', function()
    return EngineConfig.ServiceCosts
end)

exports('GetSimpleUpgrades', function()
    return EngineConfig.SimpleUpgrades
end)

if Config.Debug then
    print('[Engineering Integration] Repair, cosmetic, and tablet integrations loaded')
end
