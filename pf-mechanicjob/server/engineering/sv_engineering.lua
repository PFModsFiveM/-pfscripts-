-- ============================================================================
-- PF MECHANIC JOB - ADVANCED ENGINEERING API (Server)
-- ============================================================================

local QBCore = exports['pfm-core']:GetCoreObject()
local EngineConfig = require('config.engineering')
local TuningStore = require('server.engineering.sv_tuning_store')
local Calc = require('server.engineering.sv_calc')

local Engineering = {}

-- ============================================================================
-- Core API Functions
-- ============================================================================

---Get or create tuning record for a vehicle
---@param plate string Vehicle plate
---@param model string Vehicle model (optional)
---@return table tuning data
function Engineering:GetOrCreateTuning(plate, model)
    if not EngineConfig.Enabled then
        return { is_stock = true }
    end
    
    return TuningStore:GetOrCreateTuning(plate, model)
end

---Get tuning data for a vehicle
---@param plate string Vehicle plate
---@return table tuning data or nil
function Engineering:GetTuning(plate)
    if not EngineConfig.Enabled then return nil end
    return TuningStore:GetTuning(plate)
end

---Save tuning data
---@param plate string Vehicle plate
---@param tuningData table Tuning data to save
---@return boolean success
function Engineering:SaveTuning(plate, tuningData)
    if not EngineConfig.Enabled then return false end
    return TuningStore:SaveTuning(plate, tuningData)
end

-- ============================================================================
-- Upgrade System
-- ============================================================================

---Apply a simple mode upgrade to a vehicle
---@param plate string Vehicle plate
---@param upgradeId string Upgrade ID from SimpleUpgrades
---@return boolean success
---@return string message
function Engineering:ApplySimpleUpgrade(plate, upgradeId)
    if not EngineConfig.Enabled then return false, "Engineering disabled" end
    
    local upgrade = EngineConfig.SimpleUpgrades[upgradeId]
    if not upgrade then
        return false, "Upgrade not found"
    end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then
        return false, "Tuning data not found"
    end
    
    -- Apply upgrade properties
    if upgrade.intake then
        tuning.intake = upgrade.intake
    end
    if upgrade.exhaust then
        tuning.exhaust = upgrade.exhaust
    end
    if upgrade.ignition then
        tuning.ignition = upgrade.ignition
    end
    if upgrade.ecu_map then
        tuning.ecu_map = upgrade.ecu_map
    end
    if upgrade.tire_compound then
        tuning.tire_compound = upgrade.tire_compound
    end
    
    -- Reset wear/quality if service
    if upgrade.oil_quality then
        tuning.oil_quality = upgrade.oil_quality
    end
    if upgrade.coolant_quality then
        tuning.coolant_quality = upgrade.coolant_quality
    end
    
    local success = self:SaveTuning(plate, tuning)
    return success, success and "Upgrade applied" or "Failed to save upgrade"
end

---Install a major component (engine, turbo, etc.)
---@param plate string Vehicle plate
---@param componentType string Type: engine_block, forced_induction, etc.
---@param componentValue string Component value (stock, forged, turbo_stage1, etc.)
---@return boolean success
---@return string message
function Engineering:InstallComponent(plate, componentType, componentValue)
    if not EngineConfig.Enabled then return false, "Engineering disabled" end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then
        return false, "Tuning data not found"
    end
    
    -- Validate component exists
    if componentType == 'engine_block' then
        if not EngineConfig.Engine[componentValue] then
            return false, "Invalid engine block type"
        end
        tuning.engine_block = componentValue
    elseif componentType == 'internals' then
        if not EngineConfig.Internals[componentValue] then
            return false, "Invalid internals type"
        end
        tuning.internals = componentValue
    elseif componentType == 'forced_induction' then
        if not EngineConfig.ForcedInduction[componentValue] then
            return false, "Invalid forced induction type"
        end
        tuning.forced_induction = componentValue
        tuning.target_boost_psi = 0  -- Reset boost on change
    elseif componentType == 'intercooler' then
        if not EngineConfig.Intercooler[componentValue] then
            return false, "Invalid intercooler type"
        end
        tuning.intercooler = componentValue
    elseif componentType == 'intake' then
        if not EngineConfig.Intake[componentValue] then
            return false, "Invalid intake type"
        end
        tuning.intake = componentValue
    elseif componentType == 'exhaust' then
        if not EngineConfig.Exhaust[componentValue] then
            return false, "Invalid exhaust type"
        end
        tuning.exhaust = componentValue
    elseif componentType == 'ecu_map' then
        if not EngineConfig.ECUMaps[componentValue] then
            return false, "Invalid ECU map"
        end
        tuning.ecu_map = componentValue
    elseif componentType == 'clutch' then
        if not EngineConfig.Clutch[componentValue] then
            return false, "Invalid clutch type"
        end
        tuning.clutch = componentValue
        tuning.clutch_wear = 0
    elseif componentType == 'gearbox' then
        if not EngineConfig.Gearbox[componentValue] then
            return false, "Invalid gearbox type"
        end
        tuning.gearbox = componentValue
        tuning.drivetrain_rating_nm = Calc:CalcDriventrainRating(tuning)
        tuning.gearbox_wear = 0
    else
        return false, "Unknown component type"
    end
    
    -- Validate build after change
    local valid, errMsg = Calc:ValidateBuild(tuning)
    if not valid then
        return false, errMsg
    end
    
    local success = self:SaveTuning(plate, tuning)
    return success, success and "Component installed" or "Failed to install component"
end

---Set ECU map for a vehicle
---@param plate string Vehicle plate
---@param mapName string ECU map name (stock, street, performance, race, valet)
---@return boolean success
function Engineering:SetECUMap(plate, mapName)
    if not EngineConfig.Enabled then return false end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning or not EngineConfig.ECUMaps[mapName] then
        return false
    end
    
    tuning.ecu_map = mapName
    return self:SaveTuning(plate, tuning)
end

---Set boost target for turbo/supercharger
---@param plate string Vehicle plate
---@param psi number Boost PSI
---@return boolean success
---@return string message
function Engineering:SetBoost(plate, psi)
    if not EngineConfig.Enabled then return false, "Engineering disabled" end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then
        return false, "Tuning data not found"
    end
    
    psi = tonumber(psi) or 0
    psi = math.max(0, math.min(psi, 25))  -- Clamp to 0-25 PSI
    
    -- Check if forced induction exists for boost
    if psi > 0 and tuning.forced_induction == 'none' then
        return false, "Vehicle must have forced induction to set boost"
    end
    
    -- Check safe limits
    local safeLimit = EngineConfig.ForcedInduction[tuning.forced_induction]
    if safeLimit and psi > (safeLimit.max_boost_safe or 0) then
        return false, string.format("Boost exceeds safe limit of %d PSI for this setup", safeLimit.max_boost_safe or 0)
    end
    
    tuning.target_boost_psi = psi
    return self:SaveTuning(plate, tuning), "Boost updated"
end

-- ============================================================================
-- Service and Maintenance
-- ============================================================================

---Service engine (oil change) to reset wear
---@param plate string Vehicle plate
---@param cost integer Service cost
---@param mechanicId string ID of mechanic performing service
---@return boolean success
function Engineering:ServiceOil(plate, cost, mechanicId)
    if not EngineConfig.Enabled then return false end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then return false end
    
    tuning.oil_quality = 100
    tuning.engine_wear = math.max(0, tuning.engine_wear - 15)  -- Reduce wear
    
    local success = self:SaveTuning(plate, tuning)
    if success then
        TuningStore:AddServiceHistory(plate, 'oil_change', cost, mechanicId)
    end
    
    return success
end

---Service cooling system
---@param plate string Vehicle plate
---@param cost integer Service cost
---@param mechanicId string ID of mechanic
---@return boolean success
function Engineering:ServiceCooling(plate, cost, mechanicId)
    if not EngineConfig.Enabled then return false end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then return false end
    
    tuning.coolant_quality = 100
    tuning.engine_heat = math.max(0, tuning.engine_heat - 20)
    tuning.turbo_heat = math.max(0, tuning.turbo_heat - 15)
    
    local success = self:SaveTuning(plate, tuning)
    if success then
        TuningStore:AddServiceHistory(plate, 'cooling_service', cost, mechanicId)
    end
    
    return success
end

---Rebuild engine to reset major wear
---@param plate string Vehicle plate
---@param cost integer Rebuild cost
---@param mechanicId string ID of mechanic
---@return boolean success
function Engineering:RebuildEngine(plate, cost, mechanicId)
    if not EngineConfig.Enabled then return false end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then return false end
    
    tuning.engine_wear = 0
    tuning.oil_quality = 100
    tuning.coolant_quality = 100
    tuning.engine_heat = 0
    tuning.turbo_heat = 0
    
    local success = self:SaveTuning(plate, tuning)
    if success then
        TuningStore:AddServiceHistory(plate, 'engine_rebuild', cost, mechanicId)
    end
    
    return success
end

---Replace clutch
---@param plate string Vehicle plate
---@param cost integer Replacement cost
---@param mechanicId string ID of mechanic
---@return boolean success
function Engineering:ReplaceClutch(plate, cost, mechanicId)
    if not EngineConfig.Enabled then return false end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then return false end
    
    tuning.clutch_wear = 0
    
    local success = self:SaveTuning(plate, tuning)
    if success then
        TuningStore:AddServiceHistory(plate, 'clutch_replacement', cost, mechanicId)
    end
    
    return success
end

---Rebuild gearbox
---@param plate string Vehicle plate
---@param cost integer Rebuild cost
---@param mechanicId string ID of mechanic
---@return boolean success
function Engineering:RebuildGearbox(plate, cost, mechanicId)
    if not EngineConfig.Enabled then return false end
    
    local tuning = self:GetOrCreateTuning(plate)
    if not tuning then return false end
    
    tuning.gearbox_wear = 0
    
    local success = self:SaveTuning(plate, tuning)
    if success then
        TuningStore:AddServiceHistory(plate, 'gearbox_service', cost, mechanicId)
    end
    
    return success
end

-- ============================================================================
-- Build Summary and Display
-- ============================================================================

---Get a user-friendly build summary for UI and receipts
---@param plate string Vehicle plate
---@return table summary
function Engineering:GetBuildSummary(plate)
    if not EngineConfig.Enabled then
        return { is_stock = true }
    end
    
    local tuning = self:GetTuning(plate)
    if not tuning then
        return { is_stock = true }
    end
    
    local estimatedHP = Calc:EstimateHP(tuning)
    local estimatedTorque = Calc:EstimateTorque(tuning)
    local maintenanceMult = Calc:CalcMaintenanceCost(tuning)
    
    return {
        plate = plate,
        estimated_hp = estimatedHP,
        estimated_torque = estimatedTorque,
        
        -- Components
        engine_block = tuning.engine_block,
        internals = tuning.internals,
        forced_induction = tuning.forced_induction,
        intercooler = tuning.intercooler,
        intake = tuning.intake,
        exhaust = tuning.exhaust,
        fuel_injectors = tuning.fuel_injectors,
        fuel_pump = tuning.fuel_pump,
        fuel_type = tuning.fuel_type,
        ecu_map = tuning.ecu_map,
        clutch = tuning.clutch,
        gearbox = tuning.gearbox,
        differential = tuning.differential,
        tire_compound = tuning.tire_compound,
        
        -- Condition
        engine_wear = tuning.engine_wear,
        turbo_wear = tuning.turbo_wear,
        clutch_wear = tuning.clutch_wear,
        gearbox_wear = tuning.gearbox_wear,
        oil_quality = tuning.oil_quality,
        coolant_quality = tuning.coolant_quality,
        tire_wear = tuning.tire_wear,
        
        -- Performance
        boost_psi = tuning.target_boost_psi,
        fuel_consumption_multiplier = tuning.fuel_consumption_multiplier,
        maintenance_cost_multiplier = maintenanceMult,
        
        -- Status
        is_stock = (tuning.forced_induction == 'none' and tuning.ecu_map == 'stock')
    }
end

-- ============================================================================
-- Events for Client Communication
-- ============================================================================

---Sync tuning data to client
---@param src number Player ID
---@param plate string Vehicle plate
function Engineering:SyncToClient(src, plate)
    if not EngineConfig.Enabled then return end
    
    local tuning = self:GetTuning(plate)
    if not tuning then
        tuning = self:GetOrCreateTuning(plate)
    end
    
    if tuning then
        TriggerClientEvent('engineering:syncTuning', src, tuning)
    end
end

---Trigger server-side wear and heat sync
---@param src number Player ID
---@param plate string Vehicle plate
---@param engineWear number New engine wear
---@param turboWear number New turbo wear
---@param engineHeat number New engine heat
---@param turboHeat number New turbo heat
function Engineering:SyncWearAndHeat(src, plate, engineWear, turboWear, engineHeat, turboHeat)
    if not EngineConfig.Enabled then return end
    
    local tuning = self:GetTuning(plate)
    if not tuning then return end
    
    -- Clamp values
    tuning.engine_wear = math.min(100, math.max(0, engineWear or 0))
    tuning.turbo_wear = math.min(100, math.max(0, turboWear or 0))
    tuning.engine_heat = math.min(100, math.max(0, engineHeat or 0))
    tuning.turbo_heat = math.min(100, math.max(0, turboHeat or 0))
    
    TuningStore:MarkDirty(plate)
end

return Engineering
