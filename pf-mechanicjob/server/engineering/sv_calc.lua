-- ============================================================================
-- PF MECHANIC JOB - ENGINEERING CALCULATIONS
-- ============================================================================

local EngineConfig = require('config.engineering')

local Calc = {}

-- ============================================================================
-- Power and Torque Calculations
-- ============================================================================

---Calculate estimated HP for a given build
---@param tuning table Tuning record
---@return number estimated HP
function Calc:EstimateHP(tuning)
    if not tuning then return EngineConfig.StockStats.default_hp end
    
    local baseHP = EngineConfig.StockStats.default_hp
    
    -- Engine block modifier
    local engineMod = (EngineConfig.Engine[tuning.engine_block] or EngineConfig.Engine.stock).hp_modifier or 1.0
    
    -- Internals modifier
    local internalsMod = (EngineConfig.Internals[tuning.internals] or EngineConfig.Internals.stock).hp_modifier or 1.0
    
    -- Forced induction modifier
    local boostMod = (EngineConfig.ForcedInduction[tuning.forced_induction] or EngineConfig.ForcedInduction.none).hp_modifier or 1.0
    
    -- Intake modifier
    local intakeMod = (EngineConfig.Intake[tuning.intake] or EngineConfig.Intake.stock).hp_modifier or 1.0
    
    -- Exhaust modifier
    local exhaustMod = (EngineConfig.Exhaust[tuning.exhaust] or EngineConfig.Exhaust.stock).hp_modifier or 1.0
    
    -- ECU map modifier
    local ecuMod = (EngineConfig.ECUMaps[tuning.ecu_map] or EngineConfig.ECUMaps.stock).hp_modifier or 1.0
    
    -- Calculate total
    local estimatedHP = baseHP * engineMod * internalsMod * boostMod * intakeMod * exhaustMod * ecuMod
    
    -- Apply wear penalties
    local wearPenalty = 1.0 - (tuning.engine_wear / 100.0) * 0.5  -- Max 50% reduction at 100% wear
    estimatedHP = estimatedHP * wearPenalty
    
    -- Apply power limit multiplier
    estimatedHP = estimatedHP * (tuning.power_limit_multiplier or 1.0)
    
    return math.floor(estimatedHP)
end

---Calculate estimated torque
---@param tuning table Tuning record
---@return number estimated torque (Nm)
function Calc:EstimateTorque(tuning)
    if not tuning then return EngineConfig.StockStats.default_torque_nm end
    
    local baseTorque = EngineConfig.StockStats.default_torque_nm
    
    local engineMod = (EngineConfig.Engine[tuning.engine_block] or EngineConfig.Engine.stock).torque_modifier or 1.0
    local internalsMod = (EngineConfig.Internals[tuning.internals] or EngineConfig.Internals.stock).torque_modifier or 1.0
    local boostMod = (EngineConfig.ForcedInduction[tuning.forced_induction] or EngineConfig.ForcedInduction.none).torque_modifier or 1.0
    local exhaustMod = (EngineConfig.Exhaust[tuning.exhaust] or EngineConfig.Exhaust.stock).backpressure or 1.0  -- Lower backpressure = more torque
    
    local ecuMod = (EngineConfig.ECUMaps[tuning.ecu_map] or EngineConfig.ECUMaps.stock).torque_modifier or 1.0
    
    local estimatedTorque = baseTorque * engineMod * internalsMod * boostMod * (2.0 - exhaustMod) * ecuMod
    
    -- Apply wear penalties
    local wearPenalty = 1.0 - (tuning.engine_wear / 100.0) * 0.4
    estimatedTorque = estimatedTorque * wearPenalty
    
    -- Apply torque limit multiplier
    estimatedTorque = estimatedTorque * (tuning.torque_limit_multiplier or 1.0)
    
    return math.floor(estimatedTorque)
end

-- ============================================================================
-- Validation and Safety Checks
-- ============================================================================

---Validate a build for safety and compatibility
---@param tuning table Tuning record
---@return boolean isValid
---@return string errorMessage or empty
function Calc:ValidateBuild(tuning)
    if not tuning then return false, "No tuning data" end
    
    local rules = EngineConfig.ValidationRules
    
    -- Turbo Stage 2+ requires intercooler
    if rules.turbo_stage2_requires_intercooler then
        if (tuning.forced_induction == 'turbo_stage2' or tuning.forced_induction == 'turbo_stage3') then
            if tuning.intercooler == 'none' then
                return false, "Turbo Stage 2+ requires an intercooler"
            end
        end
    end
    
    -- High boost requires forged internals
    if rules.high_boost_requires_forged then
        if (tuning.target_boost_psi or 0) > rules.high_boost_threshold_psi then
            if tuning.internals ~= 'forged' then
                return false, string.format("Boost above %d PSI requires forged internals", rules.high_boost_threshold_psi)
            end
        end
    end
    
    -- Turbo Stage 2 requires fuel upgrade
    if rules.turbo_stage2_requires_fuel_upgrade then
        if tuning.forced_induction == 'turbo_stage2' or tuning.forced_induction == 'turbo_stage3' then
            if tuning.fuel_injectors == 'stock' or tuning.fuel_pump == 'stock' then
                return false, "High-stage turbos require upgraded fuel system (injectors + pump)"
            end
        end
    end
    
    -- Drivetrain limits
    if rules.enforce_drivetrain_limits then
        local estimatedTorque = self:EstimateTorque(tuning)
        local drivetrainRating = tuning.drivetrain_rating_nm or 300
        
        if estimatedTorque > (drivetrainRating * 1.5) then
            return false, string.format("Estimated torque (%d Nm) exceeds safe drivetrain limits (%d Nm)", estimatedTorque, drivetrainRating)
        end
    end
    
    -- Cooling requirements
    if rules.enforce_cooling_limits then
        local estimatedHP = self:EstimateHP(tuning)
        local coolingEfficiency = (EngineConfig.Cooling[tuning.cooling] or EngineConfig.Cooling.stock).cooling_efficiency or 1.0
        
        if estimatedHP > 250 and coolingEfficiency < 1.35 then
            return false, "High-power builds require upgraded cooling"
        end
    end
    
    -- Tire grip requirements
    if rules.enforce_tire_limits then
        local estimatedHP = self:EstimateHP(tuning)
        local tireGrip = (EngineConfig.Tires[tuning.tire_compound] or EngineConfig.Tires.street).grip_coefficient or 1.0
        local requiredGrip = estimatedHP * 0.001  -- Ratio
        
        if tireGrip < (requiredGrip * rules.tire_grip_ratio_minimum) then
            return false, "Tires don't have enough grip for power output"
        end
    end
    
    return true, ""
end

---Calculate drivetrain rating based on components
---@param tuning table Tuning record
---@return number rating in Nm
function Calc:CalcDriventrainRating(tuning)
    if not tuning then return EngineConfig.StockStats.default_drivetrain_rating end
    
    local clutchRating = (EngineConfig.Clutch[tuning.clutch] or EngineConfig.Clutch.stock).torque_rating_nm or 300
    local gearboxRating = (EngineConfig.Gearbox[tuning.gearbox] or EngineConfig.Gearbox.stock).torque_rating_nm or 300
    
    -- Limiting factor is the weakest link
    return math.min(clutchRating, gearboxRating)
end

-- ============================================================================
-- Heat Calculation
-- ============================================================================

---Calculate heat generation factor based on driving conditions
---@param rpm number Current RPM
---@param boost number Current boost PSI
---@param throttle number Throttle input 0-1
---@param speed number Vehicle speed MPH
---@return number heat generation multiplier
function Calc:CalcHeatGeneration(rpm, boost, throttle, speed)
    local heat = EngineConfig.Heat
    
    local rpmFactor = (rpm / 7500) * heat.rpmHeatMultiplier
    local boostFactor = (boost / 10) * heat.boostHeatMultiplier  -- Boost is major heat source
    local throttleFactor = throttle * 1.0
    
    return (rpmFactor + boostFactor) * throttleFactor
end

---Calculate heat dissipation based on conditions
---@param speed number Vehicle speed MPH
---@param cooling table Cooling config
---@param coolingQuality number Coolant quality 0-100
---@return number heat dissipation per tick
function Calc:CalcHeatDissipation(speed, cooling, coolingQuality)
    local heat = EngineConfig.Heat
    local coolingEff = (cooling.cooling_efficiency or 1.0) * heat.engineHeatDissipation
    local airflowBonus = (speed / 100) * heat.airflowCooling * 100
    local qualityMult = (coolingQuality / 100) * heat.coolantQualityCooling * 100
    
    return coolingEff + airflowBonus + qualityMult
end

-- ============================================================================
-- Fuel Consumption Calculation
-- ============================================================================

---Calculate fuel consumption multiplier
---@param tuning table Tuning record
---@param rpm number Current RPM
---@param throttle number Throttle 0-1
---@param maxRpm number Max RPM
---@return number consumption multiplier
function Calc:CalcFuelConsumption(tuning, rpm, throttle, maxRpm)
    if not tuning then return 1.0 end
    
    local fuel = EngineConfig.FuelConsumption
    local hp = self:EstimateHP(tuning)
    local stockHP = EngineConfig.StockStats.default_hp
    
    local hpRatio = hp / stockHP
    local baseMult = 1.0 + (math.pow(hpRatio, fuel.hpRatioExponent) - 1.0)
    
    -- Throttle factor
    local throttleFactor = 0.7 + (throttle * fuel.throttleScale)
    
    -- RPM factor
    local rpmRatio = rpm / maxRpm
    local rpmFactor = 0.8 + math.pow(rpmRatio, fuel.rpmScale)
    
    local consumption = baseMult * throttleFactor * rpmFactor
    
    -- ECU Map adjustments
    local ecuCons = (EngineConfig.ECUMaps[tuning.ecu_map] or EngineConfig.ECUMaps.stock).fuel_consumption or 1.0
    consumption = consumption * ecuCons
    
    -- Eco map reduction
    if tuning.ecu_map == 'eco' then
        consumption = consumption * (1.0 - fuel.ecoModeReduction)
    end
    
    -- Fuel type adjustments
    if tuning.fuel_type == 'e85' then
        consumption = consumption * (1.0 + fuel.e85Penalty)
    end
    
    -- Condition penalties
    if tuning.oil_quality < 50 then
        consumption = consumption * (1.0 + fuel.poorOilQualityPenalty)
    end
    
    if tuning.coolant_quality < 50 then
        consumption = consumption * (1.0 + fuel.lowCoolingEfficiency)
    end
    
    if tuning.engine_wear > 70 then
        consumption = consumption * (1.0 + fuel.highWearPenalty)
    end
    
    return consumption
end

-- ============================================================================
-- Wear Calculations
-- ============================================================================

---Calculate stress factor (0-1+) based on operating conditions
---@param rpm number Current RPM
---@param boost number Current boost PSI
---@param engineHeat number Current engine temperature 0-100
---@param torqueOutput number Estimated torque
---@param torqueRating number Drivetrain rating
---@param oilQuality number Oil quality 0-100
---@return number stress multiplier
function Calc:CalcStress(rpm, boost, engineHeat, torqueOutput, torqueRating, oilQuality)
    local wear = EngineConfig.Wear
    local maxRpm = 7500
    
    local rpmStress = math.min((rpm / maxRpm) * 1.0, 1.5)
    local boostStress = (boost / 20) * 2.0  -- Boost is major stress
    local heatStress = math.max((engineHeat - 50) / 50, 0)
    local torqueOverload = math.max((torqueOutput / torqueRating) - 1.0, 0) * 2.0
    local oilStress = math.max(1.0 - (oilQuality / 100), 0)
    
    local totalStress = rpmStress + boostStress + heatStress + torqueOverload + oilStress
    return math.min(totalStress, 5.0)  -- Cap at 5x
end

---Calculate engine wear rate
---@param stress number Stress multiplier
---@param dt number Delta time in seconds
---@return number wear increase
function Calc:CalcEngineWear(stress, dt)
    local wear = EngineConfig.Wear
    return wear.baseEngineWearRate * wear.stressMultiplier * stress * dt
end

---Calculate turbo wear rate
---@param boost number Current boost PSI
---@param engineHeat number Engine heat 0-100
---@param dt number Delta time
---@return number wear increase
function Calc:CalcTurboWear(boost, engineHeat, dt)
    local wear = EngineConfig.Wear
    local boostFactor = (boost / 15) * wear.boostWearMultiplier
    local heatFactor = math.max((engineHeat - 60) / 40, 0) * wear.temperatureWearMultiplier
    
    return wear.baseTurboWearRate * (boostFactor + heatFactor) * dt
end

---Calculate clutch wear
---@param torqueRatio number Torque output / rating
---@param wheelSpin number Wheel spin 0-1
---@param dt number Delta time
---@return number wear increase
function Calc:CalcClutchWear(torqueRatio, wheelSpin, dt)
    local wear = EngineConfig.Wear
    local overloadWear = math.max((torqueRatio - 1.0) * 2.0, 0)
    local slipWear = wheelSpin * 0.5
    
    return wear.baseClutchWearRate * (1.0 + overloadWear + slipWear) * dt
end

-- ============================================================================
-- Torque Curve Selection
-- ============================================================================

---Select appropriate torque curve for build
---@param tuning table Tuning record
---@return table torque curve points
function Calc:SelectTorqueCurve(tuning)
    local curves = EngineConfig.TorqueCurves
    
    if tuning.forced_induction == 'turbo_stage3' or tuning.forced_induction == 'supercharger_stage2' then
        if tuning.target_hp and tuning.target_hp > 500 then
            return curves.turbo_extreme or curves.turbo
        end
    end
    
    if tuning.forced_induction:match('turbo') then
        return curves.turbo
    elseif tuning.forced_induction:match('supercharger') then
        return curves.supercharger
    elseif tuning.intake == 'race' and tuning.exhaust == 'race' then
        return curves.high_cam
    end
    
    return curves.stock
end

---Interpolate torque multiplier at a given RPM
---@param rpmPoints table Torque curve
---@param rpm number Target RPM
---@return number multiplier
function Calc:InterpolateTorque(rpmPoints, rpm)
    for i = 1, #rpmPoints - 1 do
        local p1 = rpmPoints[i]
        local p2 = rpmPoints[i + 1]
        
        if rpm >= p1.rpm and rpm <= p2.rpm then
            local t = (rpm - p1.rpm) / (p2.rpm - p1.rpm)
            return p1.multiplier + (p2.multiplier - p1.multiplier) * t
        end
    end
    
    return rpmPoints[#rpmPoints].multiplier
end

-- ============================================================================
-- Maintenance Cost Calculation
-- ============================================================================

---Calculate maintenance cost multiplier
---@param tuning table Tuning record
---@return number cost multiplier
function Calc:CalcMaintenanceCost(tuning)
    local multiplier = 1.0
    
    -- Boost adds cost
    if tuning.forced_induction ~= 'none' then
        multiplier = multiplier + 0.5
    end
    
    -- High output tools increase cost
    local hp = self:EstimateHP(tuning)
    local stockHP = EngineConfig.StockStats.default_hp
    multiplier = multiplier * (1.0 + ((hp / stockHP) - 1.0) * 0.3)
    
    -- Wear increases cost
    local avgWear = (tuning.engine_wear + tuning.turbo_wear + tuning.clutch_wear + tuning.gearbox_wear + tuning.diff_wear) / 5
    multiplier = multiplier * (1.0 + (avgWear / 100) * 0.5)
    
    return math.min(multiplier, 5.0)  -- Cap at 5x
end

return Calc
