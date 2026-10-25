-- ============================================================================
-- PF MECHANIC JOB - ADVANCED ENGINEERING PHYSICS (Client Runtime)
-- ============================================================================

local EngineConfig = require('config.engineering')
local QBCore = exports['pfm-core']:GetCoreObject()

local Physics = {}

-- ============================================================================
-- Runtime State
-- ============================================================================

Physics.CurrentVehicle = nil
Physics.CurrentTuning = nil
Physics.RuntimeState = {
    engineHeat = 0,
    turboHeat = 0,
    engineWear = 0,
    turboWear = 0,
    clutchWear = 0,
    gearboxWear = 0,
    diffWear = 0,
    fuelBurnMultiplier = 1.0,
    lastSync = 0,
    displayedWarning = false
}

-- ============================================================================
-- Initialization
-- ============================================================================

---Initialize physics for a vehicle
---@param vehicle number Vehicle entity
---@param tuning table Tuning data
function Physics:Initialize(vehicle, tuning)
    if not vehicle or not tuning then return end
    
    self.CurrentVehicle = vehicle
    self.CurrentTuning = tuning
    
    -- Reset runtime state
    self.RuntimeState.engineHeat = tuning.engine_heat or 0
    self.RuntimeState.turboHeat = tuning.turbo_heat or 0
    self.RuntimeState.engineWear = tuning.engine_wear or 0
    self.RuntimeState.turboWear = tuning.turbo_wear or 0
    self.RuntimeState.clutchWear = tuning.clutch_wear or 0
    self.RuntimeState.gearboxWear = tuning.gearbox_wear or 0
    self.RuntimeState.diffWear = tuning.diff_wear or 0
    self.RuntimeState.lastSync = GetGameTimer()
    self.RuntimeState.displayedWarning = false
    
    if Config.Debug then
        print(string.format('[Engineering Physics] Initialized for vehicle: '))
    end
end

---Cleanup physics
function Physics:Cleanup()
    self.CurrentVehicle = nil
    self.CurrentTuning = nil
    self.RuntimeState.displayedWarning = false
end

-- ============================================================================
-- Heat Management
-- ============================================================================

---Update engine and turbo heat
---@param rpm number Current RPM (0-8000)
---@param boost number Current boost PSI
---@param throttle number Throttle input 0-1
---@param speed number Vehicle speed MPH
---@param coolingConfig table Cooling part config
---@param dt number Delta time in seconds
function Physics:UpdateHeat(rpm, boost, throttle, speed, coolingConfig, dt)
    if not self.CurrentTuning then return end
    
    local heat = EngineConfig.Heat
    
    -- Heat generation
    local rpmFactor = (rpm / 7500) * heat.rpmHeatMultiplier
    local boostFactor = (boost / 10) * heat.boostHeatMultiplier
    local throttleFactor = throttle
    
    local heatGen = (rpmFactor + boostFactor) * throttleFactor * heat.engineHeatGeneration
    
    -- Heat dissipation
    local coolingEff = (coolingConfig.cooling_efficiency or 1.0) * heat.engineHeatDissipation
    local airflowBonus = (speed / 100) * heat.airflowCooling * 100
    local qualityMult = (self.CurrentTuning.coolant_quality / 100) * heat.coolantQualityCooling * 100
    
    local heatDissipation = coolingEff + airflowBonus + qualityMult
    
    -- Apply net heat change
    self.RuntimeState.engineHeat = self.RuntimeState.engineHeat + (heatGen - heatDissipation) * dt
    self.RuntimeState.engineHeat = math.max(0, math.min(100, self.RuntimeState.engineHeat))
    
    -- Turbo heat (if turbocharged)
    if self.CurrentTuning.forced_induction:match('turbo') then
        local turboGen = (boost / 15) * heat.boostHeatMultiplier * heat.turboHeatGeneration
        local turboDissipation = (coolingConfig.cooling_efficiency or 1.0) * 25 + (speed / 100) * 10
        
        self.RuntimeState.turboHeat = self.RuntimeState.turboHeat + (turboGen - turboDissipation) * dt
        self.RuntimeState.turboHeat = math.max(0, math.min(100, self.RuntimeState.turboHeat))
    else
        self.RuntimeState.turboHeat = math.max(0, self.RuntimeState.turboHeat - 30 * dt)
    end
end

-- ============================================================================
-- Wear System
-- ============================================================================

---Calculate stress factor
---@param rpm number Current RPM
---@param boost number Boost PSI
---@param engineHeat number Engine heat 0-100
---@param throttle number Throttle 0-1
---@param torqueRatio number Torque / rating
---@param oilQuality number Oil quality 0-100
---@return number stress multiplier
function Physics:CalcStress(rpm, boost, engineHeat, throttle, torqueRatio, oilQuality)
    local wear = EngineConfig.Wear
    local maxRpm = 7500
    
    local rpmStress = math.min((rpm / maxRpm) * 1.0, 1.5) * throttle
    local boostStress = (boost / 20) * 2.0
    local heatStress = math.max((engineHeat - 50) / 50, 0)
    local torqueOverload = math.max((torqueRatio - 1.0) * 2.0, 0)
    local oilStress = math.max(1.0 - (oilQuality / 100), 0)
    
    local totalStress = rpmStress + boostStress + heatStress + torqueOverload + oilStress
    return math.min(totalStress, 5.0)
end

---Update engine wear
---@param stress number Stress multiplier
---@param dt number Delta time
function Physics:UpdateEngineWear(stress, dt)
    if not self.CurrentTuning then return end
    
    local wear = EngineConfig.Wear
    local wearIncrease = wear.baseEngineWearRate * wear.stressMultiplier * stress * dt
    
    self.RuntimeState.engineWear = math.min(100, self.RuntimeState.engineWear + wearIncrease)
end

---Update turbo wear
---@param boost number Boost PSI
---@param engineHeat number Engine heat
---@param dt number Delta time
function Physics:UpdateTurboWear(boost, engineHeat, dt)
    if not self.CurrentTuning or not self.CurrentTuning.forced_induction:match('turbo') then
        return
    end
    
    local wear = EngineConfig.Wear
    local boostFactor = (boost / 15) * wear.boostWearMultiplier
    local heatFactor = math.max((engineHeat - 60) / 40, 0) * wear.temperatureWearMultiplier
    
    local wearIncrease = wear.baseTurboWearRate * (boostFactor + heatFactor) * dt
    self.RuntimeState.turboWear = math.min(100, self.RuntimeState.turboWear +wearIncrease)
end

---Update drivetrain wear
---@param engineRpm number Current RPM
---@param vehicleSpeed number Vehicle speed
---@param throttle number Throttle 0-1
---@param gear number Current gear
---@param dt number Delta time
function Physics:UpdateDriventrainWear(engineRpm, vehicleSpeed, throttle, gear, dt)
    if not self.CurrentTuning then return end
    
    local wear = EngineConfig.Wear
    
    -- Launch detection (high RPM, low speed, high throttle)
    local launch = (engineRpm > 4000 and vehicleSpeed < 10 and throttle > 0.8)
    if launch then
        self.RuntimeState.clutchWear = math.min(100, self.RuntimeState.clutchWear + wear.launchWearMultiplier * dt)
        self.RuntimeState.gearboxWear = math.min(100, self.RuntimeState.gearboxWear + wear.launchWearMultiplier * 0.5 * dt)
    end
    
    -- Wheelspin detection
    local wheelSpeed = GetVehicleDeformationFixed(self.CurrentVehicle)  -- Approximation
    local rpmSpeed = (engineRpm / 7500) * 100
    local wheelSpin = math.max(0, (rpmSpeed - vectorSpeed) / rpmSpeed)
    
    if wheelSpin > 0.2 then  -- 20% wheelspin
        self.RuntimeState.diffWear = math.min(100, self.RuntimeState.diffWear + wear.wheelSpinWearMultiplier * wheelSpin * dt)
    end
    
    -- General load-based wear
    local baseClutchWear = wear.baseClutchWearRate * throttle * dt
    local baseGearboxWear = wear.baseGearboxWearRate * throttle * dt
    
    self.RuntimeState.clutchWear = math.min(100, self.RuntimeState.clutchWear + baseClutchWear)
    self.RuntimeState.gearboxWear = math.min(100, self.RuntimeState.gearboxWear + baseGearboxWear)
end

-- ============================================================================
-- Power Modulation
-- ============================================================================

---Apply power multiplier based on tuning
---@param vehicle number Vehicle entity
---@param rpm number Current RPM
---@param engineHeat number Engine heat 0-100
function Physics:ApplyPowerMultiplier(vehicle, rpm, engineHeat)
    if not self.CurrentTuning or not vehicle then return end
    
    local heat = EngineConfig.Heat
    local baseMultiplier = 1.0
    
    -- Check limp mode
    if engineHeat >= heat.heatThresholds.limp_mode then
        baseMultiplier = baseMultiplier * EngineConfig.Limp.power_reduction
    elseif engineHeat >= heat.heatThresholds.performance_reduction then
        -- Gradual reduction as heat increases
        local heatPenalty = (engineHeat - heat.heatThresholds.performance_reduction) / 20
        baseMultiplier = baseMultiplier * (1.0 - heatPenalty)
    end
    
    -- Apply wear penalties
    local wearPenalty = 1.0 - (self.RuntimeState.engineWear / 100) * 0.3
    baseMultiplier = baseMultiplier * wearPenalty
    
    -- Apply tuning multipliers
    baseMultiplier = baseMultiplier * (self.CurrentTuning.power_limit_multiplier or 1.0)
    
    -- Clamp to reasonable range
    baseMultiplier = math.max(0.3, math.min(3.0, baseMultiplier))
    
    SetVehicleEnginePowerMultiplier(vehicle, baseMultiplier)
end

---Apply torque multiplier
---@param vehicle number Vehicle entity
---@param rpm number Current RPM
function Physics:ApplyTorqueMultiplier(vehicle, rpm)
    if not self.CurrentTuning or not vehicle then return end
    
    local baseMultiplier = 1.0
    baseMultiplier = baseMultiplier * (self.CurrentTuning.torque_limit_multiplier or 1.0)
    
    -- Wear reduces torque
    local wearPenalty = 1.0 - (self.RuntimeState.engineWear / 100) * 0.35
    baseMultiplier = baseMultiplier * wearPenalty
    
    baseMultiplier = math.max(0.3, math.min(3.0, baseMultiplier))
    
    SetVehicleEngineTorqueMultiplier(vehicle, baseMultiplier)
end

-- ============================================================================
-- Effects and Feedback
-- ============================================================================

---Apply misfire effect (brief power dip and sound)
---@param vehicle number Vehicle entity
function Physics:ApplyMisfire(vehicle)
    if not vehicle then return end
    
    -- Briefly reduce power
    local currentMult = GetVehicleEnginePowerMultiplier(vehicle)
    SetVehicleEnginePowerMultiplier(vehicle, currentMult * 0.6)
    
    --Restore after 100ms
    SetTimeout(100, function()
        if DoesEntityExist(vehicle) then
            SetVehicleEnginePowerMultiplier(vehicle, currentMult)
        end
    end)
end

---Apply limp mode visual/audio feedback
---@param vehicle number Vehicle entity
function Physics:DisplayLimpMode(vehicle)
    if not vehicle then return end
    
    TriggerEvent('chat:addMessage', {
        color = {255, 0, 0},
        multiline = true,
        args = {"Engine", "LIMP MODE ACTIVE - Engine overheating!"}
    })
    
    -- Could add visual effects here
    self.RuntimeState.displayedWarning = true
end

---Check for catastrophic failure
---@param vehicle number Vehicle entity
---@param stress number Stress multiplier
---@return boolean did fail
function Physics:CheckCatastrophicFailure(vehicle, stress)
    if not vehicle or not self.CurrentTuning then return false end
    
    local failures = EngineConfig.Failures
    local preset = EngineConfig.RealisticPresets[EngineConfig.RealisticMode or 'balanced']
    
    -- Only major power builds can catastrophically fail
    local hp = 150  -- Approximation; would need to query EstimateHP
    if hp < 300 then return false end
    
    -- Failure chance based on stress and conditions
    local baseChance = failures.catastrophic_failure_threshold[EngineConfig.RealisticMode or 'balanced'] or 0.02
    local failureChance = baseChance * stress * (self.RuntimeState.engineWear / 100)
    
    if math.random() < failureChance then
        -- Trigger engine shutdown
        SmashVehicleWindow(vehicle, 0)  -- Placeholder visual
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            multiline = true,
            args = {"Engine", "ENGINE FAILURE - Catastrophic damage!"}
        })
        
        return true
    end
    
    return false
end

-- ============================================================================
-- Periodic Update Loop
-- ============================================================================

---Main physics update loop
---@param vehicle number Vehicle entity
---@param dt number Delta time in seconds
function Physics:Update(vehicle, dt)
    if not vehicle or not self.CurrentTuning then return end
    
    -- Get current vehicle stats
    local rpm = GetVehicleCurrentRpm(vehicle)
    local speed = GetEntitySpeed(vehicle) * 2.237  -- Convert to MPH
    local throttle = GetVehicleAcceleration(vehicle)
    local gear = GetVehicleCurrentGear(vehicle)
    
    -- Get boost (approximation)
    local boost = self.CurrentTuning.target_boost_psi * (rpm / 7500)
    boost = math.max(0, math.min(boost, self.CurrentTuning.target_boost_psi))
    
    -- Get cooling config
    local coolingConfig = EngineConfig.Cooling[self.CurrentTuning.cooling] or EngineConfig.Cooling.stock
    
    -- Update heat
    self:UpdateHeat(rpm, boost, throttle, speed, coolingConfig, dt)
    
    -- Stress calculation
    local torqueRatio = 1.0  -- Would need to calculate from build
    local stress = self:CalcStress(rpm, boost, self.RuntimeState.engineHeat, throttle, torqueRatio, self.CurrentTuning.oil_quality)
    
    -- Update wear
    self:UpdateEngineWear(stress, dt)
    self:UpdateTurboWear(boost, self.RuntimeState.engineHeat, dt)
    self:UpdateDriventrainWear(rpm, speed, throttle, gear, dt)
    
    -- Apply power modulation
    self:ApplyPowerMultiplier(vehicle, rpm, self.RuntimeState.engineHeat)
    self:ApplyTorqueMultiplier(vehicle, rpm)
    
    -- Check for misfire
    local misChance = EngineConfig.Failures.misfire_chance_base + 
                      (self.RuntimeState.engineWear / 100) * EngineConfig.Failures.misfire_wear_scale +
                      (100 - self.CurrentTuning.oil_quality) / 100 * EngineConfig.Failures.misfire_oil_scale
    
    if math.random() < misChance then
        self:ApplyMisfire(vehicle)
    end
    
    -- Heat warning and limp mode
    local heat = EngineConfig.Heat
    if self.RuntimeState.engineHeat >= heat.heatThresholds.limp_mode then
        if not self.RuntimeState.displayedWarning then
            self:DisplayLimpMode(vehicle)
        end
    elseif self.RuntimeState.engineHeat > heat.heatThresholds.warning then
        if not self.RuntimeState.displayedWarning then
            TriggerEvent('chat:addMessage', {
                color = {255, 200, 0},
                multiline = true,
                args = {"Engine", "Warning: Engine temperature rising!"}
            })
            self.RuntimeState.displayedWarning = true
        end
    else
        self.RuntimeState.displayedWarning = false
    end
    
    -- Check catastrophic failure (rare)
    if stress > 3.0 and self.RuntimeState.engineHeat > 95 then
        self:CheckCatastrophicFailure(vehicle, stress)
    end
end

-- ============================================================================
-- Sync to Server
-- ============================================================================

---Sync wear and heat data to server
function Physics:SyncToServer()
    if not self.CurrentTuning or not self.CurrentVehicle then return end
    
    local plate = GetVehicleNumberPlateText(self.CurrentVehicle):gsub('%s+', '')
    
    TriggerServerEvent('engineering:syncWearAndHeat',
        plate,
        self.RuntimeState.engineWear,
        self.RuntimeState.turboWear,
        self.RuntimeState.engineHeat,
        self.RuntimeState.turboHeat
    )
end

return Physics
