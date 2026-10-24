-- ============================================================================
-- PF MECHANIC JOB - TABLET TUNING APP INTEGRATION
-- (Data and logic for tablet UI - Tuning and Dyno apps)
-- ============================================================================

local QBCore = exports['pfm-core']:GetCoreObject()
local EngineConfig = require('config.engineering')

if not EngineConfig.Enabled then return end

-- ============================================================================
-- Tuning App Data Provider
-- ============================================================================

---Get all simple upgrades for tablet display
QBCore.Functions.CreateCallback('tablet:tuning:getSimpleUpgrades', function(source, cb, currentUsingUpgrades)
    local upgrades = EngineConfig.SimpleUpgrades
    local formatted = {}
    
    for upgradeId, upgrade in pairs(upgrades) do
        table.insert(formatted, {
            id = upgradeId,
            label = upgrade.label,
            hp_gain = upgrade.hp_gain_percent,
            cost = upgrade.cost,
            description = string.format("Gain ~y~%d%% HP~s~. Cost: ~g~$%d", upgrade.hp_gain_percent, upgrade.cost)
        })
    end
    
    cb(formatted)
end)

---Get available major components for tablet tuning menu
QBCore.Functions.CreateCallback('tablet:tuning:getMajorComponents', function(source, cb, componentType)
    local components = {}
    
    if componentType == 'engine_block' then
        components = EngineConfig.Engine
    elseif componentType == 'internals' then
        components = EngineConfig.Internals
    elseif componentType == 'forced_induction' then
        components = EngineConfig.ForcedInduction
    elseif componentType == 'intercooler' then
        components = EngineConfig.Intercooler
    elseif componentType == 'intake' then
        components = EngineConfig.Intake
    elseif componentType == 'exhaust' then
        components = EngineConfig.Exhaust
    elseif componentType == 'fuel_injectors' then
        components = EngineConfig.FuelInjectors
    elseif componentType == 'fuel_pump' then
        components = EngineConfig.FuelPump
    elseif componentType == 'ecu_map' then
        components = EngineConfig.ECUMaps
    elseif componentType == 'clutch' then
        components = EngineConfig.Clutch
    elseif componentType == 'gearbox' then
        components = EngineConfig.Gearbox
    elseif componentType == 'differential' then
        components = EngineConfig.Differential
    elseif componentType == 'tire_compound' then
        components = EngineConfig.Tires
    end
    
    local formatted = {}
    for key, component in pairs(components) do
        table.insert(formatted, {
            id = key,
            label = component.label or key,
            cost = component.cost or 0,
            description = component.description or ""
        })
    end
    
    cb(formatted)
end)

---Get available ECU maps
QBCore.Functions.CreateCallback('tablet:tuning:getECUMaps', function(source, cb)
    local maps = {}
    
    for mapId, mapData in pairs(EngineConfig.ECUMaps) do
        table.insert(maps, {
            id = mapId,
            label = mapData.label,
            hp_mod = mapData.hp_modifier,
            fuel_mod = mapData.fuel_consumption,
            reliability = mapData.reliability,
            cost = mapData.cost
        })
    end
    
    cb(maps)
end)

---Get part compatibility warnings
QBCore.Functions.CreateCallback('tablet:tuning:validateBuild', function(source, cb, tuning)
    if not tuning then
        cb({ valid = false, errors = {"No tuning data"} })
        return
    end
    
    local Calc = require('server.engineering.sv_calc')
    local valid, errMsg = Calc:ValidateBuild(tuning)
    
    local result = {
        valid = valid,
        errors = valid and {} or {errMsg},
        estimatedHP = Calc:EstimateHP(tuning),
        estimatedTorque = Calc:EstimateTorque(tuning),
        warnings = {}
    }
    
    -- Add warnings
    if tuning.engine_wear > 70 then
        table.insert(result.warnings, "Engine wear is critical")
    end
    if tuning.clutch_wear > 70 then
        table.insert(result.warnings, "Clutch is near failure")
    end
    if tuning.engine_heat > 80 then
        table.insert(result.warnings, "Engine running hot")
    end
    
    cb(result)
end)

-- ============================================================================
-- Dyno Simulation
-- ============================================================================

---Run simulated dyno test
QBCore.Functions.CreateCallback('tablet:tuning:runDyno', function(source, cb, vehNet, tuning)
    if not vehNet or not tuning then
        cb(nil)
        return
    end
    
    local veh = NetworkGetEntityFromNetworkId(vehNet)
    if not veh or not DoesEntityExist(veh) then
        cb(nil)
        return
    end
    
    local Calc = require('server.engineering.sv_calc')
    local estimatedHP = Calc:EstimateHP(tuning)
    local estimatedTorque = Calc:EstimateTorque(tuning)
    
    -- Generate torque curve
    local curve = Calc:SelectTorqueCurve(tuning)
    local dynoResults = {
        hp = estimatedHP,
        torque = estimatedTorque,
        points = {}
    }
    
    -- Generate RPM sweep
    for rpm = 1000, 7500, 500 do
        local multiplier = Calc:InterpolateTorque(curve, rpm)
        local torque = estimatedTorque * multiplier
        local hp = (torque * (rpm / 5252))  -- Convert torque to HP
        
        table.insert(dynoResults.points, {
            rpm = rpm,
            torque = math.floor(torque),
            hp = math.floor(hp),
            multiplier = math.floor(multiplier * 100)
        })
    end
    
    cb(dynoResults)
end)

-- ============================================================================
-- Receipt and Invoice Generation
-- ============================================================================

---Generate service receipt
QBCore.Functions.CreateCallback('tablet:tuning:generateReceipt', function(source, cb, plate, services)
    if not plate or not services then
        cb(nil)
        return
    end
    
    local Engineering = require('server.engineering.sv_engineering')
    local summary = Engineering:GetBuildSummary(plate)
    
    local totalCost = 0
    local items = {}
    
    if services and type(services) == 'table' then
        for _, service in ipairs(services) do
            local cost = EngineConfig.ServiceCosts[service] or 0
            totalCost = totalCost + cost
            table.insert(items, {
                name = service,
                cost = cost
            })
        end
    end
    
    local receipt = {
        plate = plate,
        date = os.date("%Y-%m-%d %H:%M:%S"),
        items = items,
        subtotal = totalCost,
        tax = math.floor(totalCost * (Config.DefaultTax or 0.08)),
        total = totalCost + math.floor(totalCost * (Config.DefaultTax or 0.08)),
        build = summary
    }
    
    cb(receipt)
end)

-- ============================================================================
-- Parts and Pricing
-- ============================================================================

---Get parts catalog with categories
QBCore.Functions.CreateCallback('tablet:tuning:getPartsCatalog', function(source, cb)
    local catalog = {
        engine = {
            name = "Engine Components",
            parts = {}
        },
        drivetrain = {
            name = "Drivetrain",
            parts = {}
        },
        fuel = {
            name = "Fuel System",
            parts = {}
        },
        cooling = {
            name = "Cooling System",
            parts = {}
        },
        tires = {
            name = "Tires",
            parts = {}
        }
    }
    
    -- Engine components
    for key, part in pairs(EngineConfig.Engine) do
        if key ~= 'stock' and part.cost > 0 then
            table.insert(catalog.engine.parts, {
                id = key,
                label = part.label,
                cost = part.cost
            })
        end
    end
    
    -- Drivetrain
    for key, part in pairs(EngineConfig.Clutch) do
        if key ~= 'stock' and part.cost > 0 then
            table.insert(catalog.drivetrain.parts, {
                id = key,
                label = part.label,
                type = 'clutch',
                cost = part.cost
            })
        end
    end
    
    -- Fuel system
    for key, part in pairs(EngineConfig.FuelPump) do
        if key ~= 'stock' and part.cost > 0 then
            table.insert(catalog.fuel.parts, {
                id = key,
                label = part.label,
                type = 'fuel_pump',
                cost = part.cost
            })
        end
    end
    
    -- Cooling system
    for key, part in pairs(EngineConfig.Cooling) do
        if key ~= 'stock' and part.cost > 0 then
            table.insert(catalog.cooling.parts, {
                id = key,
                label = part.label,
                cost = part.cost
            })
        end
    end
    
    -- Tires
    for key, part in pairs(EngineConfig.Tires) do
        if part.cost > 0 then
            table.insert(catalog.tires.parts, {
                id = key,
                label = part.label,
                cost = part.cost
            })
        end
    end
    
    cb(catalog)
end)

-- ============================================================================
-- Build Recommendations
-- ============================================================================

---Get recommended upgrade paths
QBCore.Functions.CreateCallback('tablet:tuning:getUpgradePath', function(source, cb, plate, targetHP)
    if not plate then
        cb(nil)
        return
    end
    
    targetHP = tonumber(targetHP) or 200
    
    local recommendations = {
        label = string.format("Upgrade Path to ~g~%d HP~s~", targetHP),
        steps = {},
        total_cost = 0
    }
    
    -- Recommend progression
    if targetHP < 200 then
        table.insert(recommendations.steps, {
            name = "Budget Upgrade",
            parts = {"intake_filter", "exhaust_catback"},
            hp = 5,
            cost = 2300,
            safety = "Safe"
        })
    elseif targetHP < 250 then
        table.insert(recommendations.steps, {
            name = "Street Setup",
            parts = {"ecu_tune_basic", "exhaust_catback", "spark_plugs"},
            hp = 10,
            cost = 4700,
            safety = "Safe"
        })
    else
        table.insert(recommendations.steps, {
            name = "Performance Build",
            parts = {"engine_block_strengthened", "internals_forged", "turbo_stage1", "fuel_pump_street"},
            hp = 100,
            cost = 50000,
            safety = "Moderate"
        })
    end
    
    -- Calculate total
    for _, step in ipairs(recommendations.steps) do
        recommendations.total_cost = recommendations.total_cost + step.cost
    end
    
    cb(recommendations)
end)

-- ============================================================================
-- Export Data Providers
-- ============================================================================

exports('GetECUMaps', function()
    return EngineConfig.ECUMaps
end)

exports('GetSimpleUpgrades', function()
    return EngineConfig.SimpleUpgrades
end)

exports('GetComponentCatalog', function(componentType)
    if componentType == 'engine' then
        return EngineConfig.Engine
    elseif componentType == 'clutch' then
        return EngineConfig.Clutch
    elseif componentType == 'gearbox' then
        return EngineConfig.Gearbox
    end
    return nil
end)

if Config.Debug then
    print('[Engineering Tablet Integration] Tuning app data providers loaded')
end
