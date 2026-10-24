-- Vehicle Component Damage System with Environmental Effects and Realistic Failures
local QBCore = exports['pfm-core']:GetCoreObject()

-- Global safe state setter so this file never crashes on state:set
if not SafeStateSet then
    function SafeStateSet(veh, key, value)
        if not veh or veh == 0 or not DoesEntityExist(veh) then return end
        local st = Entity(veh).state
        if st and st.set then
            st:set(key, value, true)
        else
            TriggerServerEvent('pf_mech:server:setState', NetworkGetNetworkIdFromEntity(veh), key, value)
        end
    end
end

-- Helper: Debug notify (only shows if Config.Debug = true)
local function DebugNotify(msg, type)
    if Config.Debug then
        QBCore.Functions.Notify(msg, type or 'primary', 3000)
    end
    if Config.Debug then
        print('[DAMAGE DEBUG] ' .. tostring(msg))
    end
end

-- Configuration
local DamageConfig = {
    enabled = true,
    checkInterval = 5000,
    damageRates = {
        alternator = 0.03,
        sparkplugs = 0.08,
        carbattery = 0.04,
        oil = 0.02,              -- RESTORE: was 0.00
        oil_filter = 0.01,       -- RESTORE: was 0.00
        brakes = 0.05,
        suspension = 0.04,
        axle = 0.03,
        fuel_injector = 0.01,    -- RESTORE: was 0.00
        powersteeringpump = 0.00,
        power_steering_fluid = 0.00,
        radiator = 0.00,
        transmissionfluid = 0.00,
        brakefluid = 0.00,
        coolant = 0.00,
    },
    
    -- Starting thresholds
    starting = {
        battery_hard_start = 50,
        battery_may_fail = 30,
        battery_power_cut = 30,
        sparkplug_misfire = 40,
        alternator_stutter = 60,
        attempts_max = 5
    },
    
    -- Brake degradation
    brakes = {
        fade_threshold = 60,     -- Below 60% = reduced braking
        critical_threshold = 30, -- Below 30% = severe brake fade
        max_power_loss = 0.6     -- Up to 60% brake power loss
    },
    
    -- Alternator stuttering
    alternator = {
        stutter_interval = 300000,  -- 5 minutes between stutters
        damage_per_stutter = 10,    -- 10% damage per stutter event
        base_stutter_duration = 2000, -- 2 seconds at 60%
        max_stutter_duration = 15000  -- 15 seconds at 0%
    },
    
    -- Environmental damage multipliers
    environmental = {
        mud_multiplier = 3.0,
        water_depth_critical = 0.5,
        offroad_protection = 0.3,
        no_snorkel_penalty = 2.0
    },
    
    -- Thresholds
    warningThreshold = 30,
    criticalThreshold = 10
}

-- Track vehicle states
local vehicleStates = {}
local lastWarnings = {}
local lastEnvironmentalWarning = 0
local batteryDeadNotified = {}
local lastAlternatorStutter = {}
local lastBrakeWarning = {}
local repairInProgress = {} -- NEW: Track vehicles being repaired [plate] = true

-- Offroad vehicle classes (get less environmental damage)
local OffroadVehicleClasses = {
    [8] = true,   -- Motorcycles (some)
    [9] = true,   -- Off-road
    [11] = true,  -- Utility
    [18] = true   -- Emergency (some have snorkels)
}

-- Vehicles with snorkels (custom list - expand as needed)
local VehiclesWithSnorkel = {
    [`bifta`] = true,
    [`bfinjection`] = true,
    [`dubsta3`] = true,
    [`kalahari`] = true,
    [`mesa3`] = true,
    [`rebel`] = true,
    [`rebel2`] = true,
    [`sandking`] = true,
    [`sandking2`] = true,
    [`dloader`] = true,
    [`blazer`] = true,
    [`insurgent`] = true,
    [`insurgent2`] = true,
    [`technical`] = true,
    [`guardian`] = true,
    [`dubsta`] = true,
    [`dubsta2`] = true
}

-- Helper: Check if vehicle has snorkel
local function hasSnorkel(veh)
    local model = GetEntityModel(veh)
    return VehiclesWithSnorkel[model] or false
end

-- Helper: Check if vehicle is offroad type
local function isOffroadVehicle(veh)
    local class = GetVehicleClass(veh)
    return OffroadVehicleClasses[class] or false
end

-- Helper: Get water/mud depth (add IsEntityInWater fallback)
local function getWaterDepth(veh)
    if not veh or not DoesEntityExist(veh) then return 0.0 end
    local x,y,z = table.unpack(GetEntityCoords(veh))
    local found, height = GetWaterHeight(x, y, z)
    if found then
        local depth = (height - z)
        if depth < 0 then depth = 0 end
        return depth
    end
    if IsEntityInWater(veh) then
        -- Fallback: treat as at least shallow (0.3) when native fails
        return 0.3
    end
    return 0.0
end

-- Increase speed wear factors (more visible)
local function speedWearFactor(mph)
    if mph <= 40.0 then return 0.00 end
    if mph <= 80.0 then return 0.30 end
    if mph <= 100.0 then return 0.80 end
    if mph <= 120.0 then return 1.60 end
    local over = mph - 120.0
    return 2.5 + (over * 0.12)       -- >120 ramps sharply
end

-- Helper: Check if vehicle is in mud/dirt (heuristic)
local function isInMud(veh)
    if not veh or not DoesEntityExist(veh) then return false end
    
    local coords = GetEntityCoords(veh)
    local rayHandle = StartShapeTestRay(coords.x, coords.y, coords.z + 2.0, coords.x, coords.y, coords.z - 2.0, 1, veh, 0)
    local _, hit, _, _, materialHash = GetShapeTestResult(rayHandle)
    
    if hit then
        -- Common mud/dirt material hashes (approximations)
        local mudMaterials = {
            [-1286696947] = true, -- dirt
            [1109728704] = true,  -- mud
            [2128369009] = true,  -- grass_dirt
            [-1885547121] = true, -- sand
        }
        
        return mudMaterials[materialHash] or false
    end
    
    return false
end

-- Helper: Get or initialize vehicle damage state
local function getVehicleDamage(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    local state = Entity(veh)
    if not state or not state.state then return nil end
    
    local damage = state.state.partDamage or {}
    
    damage.alternator = damage.alternator or 0
    damage.sparkplugs = damage.sparkplugs or 0
    damage.carbattery = damage.carbattery or 0
    damage.oil = damage.oil or 0
    damage.oil_filter = damage.oil_filter or 0
    damage.brakes = damage.brakes or 0  -- NEW
    damage.suspension = damage.suspension or 0
    damage.axle = damage.axle or 0
    damage.fuel_injector = damage.fuel_injector or 0
    damage.powersteeringpump = damage.powersteeringpump or 0
    damage.radiator = damage.radiator or 0
    damage.power_steering_fluid = damage.power_steering_fluid or 0
    damage.transmissionfluid = damage.transmissionfluid or 0
    damage.brakefluid = damage.brakefluid or 0
    damage.coolant = damage.coolant or 0
    damage.engine_part = damage.engine_part or 0
    damage.body_part   = damage.body_part or 0
    return damage
end

-- Helper: Apply damage to vehicle state (ADD engine_part/body_part preservation)
local function applyDamage(veh, damage)
    if not veh or not DoesEntityExist(veh) or not damage then 
        print('[DAMAGE ERROR] applyDamage called with invalid parameters')
        return 
    end
    
    local state = Entity(veh)
    if not state or not state.state then 
        print('[DAMAGE ERROR] Vehicle entity state not available')
        return 
    end
    
    local cleanDamage = {
        alternator = math.min(100, math.max(0, tonumber(damage.alternator) or 0)),
        sparkplugs = math.min(100, math.max(0, tonumber(damage.sparkplugs) or 0)),
        carbattery = math.min(100, math.max(0, tonumber(damage.carbattery) or 0)),
        brakes     = math.min(100, math.max(0, tonumber(damage.brakes) or 0)),
        suspension = math.min(100, math.max(0, tonumber(damage.suspension) or 0)),
        axle       = math.min(100, math.max(0, tonumber(damage.axle) or 0)),
        -- NEW: keep virtual damage values for engine/body so debug menu can reflect them
        engine_part = math.min(100, math.max(0, tonumber(damage.engine_part) or 0)),
        body_part   = math.min(100, math.max(0, tonumber(damage.body_part) or 0)),
    }

    -- Fractional (round to 2 decimals to minimize network spam)
    local function keep(key)
        local v = tonumber(damage[key]) or 0
        v = math.min(100, math.max(0, v))
        cleanDamage[key] = tonumber(string.format('%.2f', v))
    end
    keep('oil')
    keep('oil_filter')
    keep('fuel_injector')
    keep('powersteeringpump')
    keep('radiator')
    keep('power_steering_fluid')
    keep('transmissionfluid')
    keep('brakefluid')
    keep('coolant')

    -- Debug only when oil actually changes noticeably
    if (Entity(veh).state.partDamage and Entity(veh).state.partDamage.oil) then
        local prev = tonumber(Entity(veh).state.partDamage.oil) or 0
        if math.abs(prev - cleanDamage.oil) >= 0.10 then
            print(string.format('[DAMAGE DEBUG] Oil damage %.2f -> %.2f', prev, cleanDamage.oil))
        end
    end

    SafeStateSet(veh, 'partDamage', cleanDamage)
    
    -- Wait a frame to ensure state is set
    Wait(0)
    
    -- Verify the state was actually set
    local verify = (Entity(veh).state.partDamage) or {}
    print('[DAMAGE DEBUG] Verified partDamage after set:', json.encode(verify))
end

-- NEW: Handle vehicle starting with battery/sparkplug/alternator failures
local function attemptVehicleStart(veh, damage)
    local batteryHealth = 100 - (tonumber(damage.carbattery) or 0)
    local sparkplugHealth = 100 - (tonumber(damage.sparkplugs) or 0)
    local alternatorHealth = 100 - (tonumber(damage.alternator) or 0)
    local injectorHealth   = 100 - (tonumber(damage.fuel_injector) or 0)
    
    print('[DAMAGE DEBUG] Attempting start - Battery:', batteryHealth, '% Sparkplugs:', sparkplugHealth, '% Alternator:', alternatorHealth, '%')
    
    local plate = GetVehicleNumberPlateText(veh) or 'UNKNOWN'
    
    -- Dead battery = no start (only notify once)
    if batteryHealth <= 0 then
        if not batteryDeadNotified[plate] then
            batteryDeadNotified[plate] = true
        end
        SetVehicleEngineOn(veh, false, true, true)
        return false
    end
    
    if sparkplugHealth <= 0 then
        SetVehicleEngineOn(veh, false, true, true)
        return false
    end
    
    -- Calculate start chance based on battery, sparkplugs & alternator
    local startChance = 100
    
    -- Battery affects starting
    if batteryHealth < DamageConfig.starting.battery_hard_start then
        if batteryHealth < DamageConfig.starting.battery_may_fail then
            startChance = math.max(20, batteryHealth * 2)
        else
            startChance = 70 + (batteryHealth - 30) * 1.5
        end
    end
    
    -- Sparkplugs affect starting
    if sparkplugHealth < DamageConfig.starting.sparkplug_misfire then
        startChance = startChance * (sparkplugHealth / 100)
    end
    
    -- Bad alternator makes starting harder (drains battery faster)
    if alternatorHealth < 50 then
        startChance = startChance * (alternatorHealth / 100)
    end
    
    -- Make starting harder if fuel injector is damaged
    if injectorHealth < 60 then
        startChance = startChance * (injectorHealth / 100.0)
    end
    
    print('[DAMAGE DEBUG] Start chance:', startChance, '%')
    
    local roll = math.random(1, 100)
    local started = roll <= startChance
    
    if not started then
        damage.carbattery = math.min(100, (damage.carbattery or 0) + 1)
        applyDamage(veh, damage)
        
        -- Suppressed damage notifications
        print('[DAMAGE DEBUG] Start FAILED (rolled', roll, 'needed <=', startChance, ')')
    else
        -- Suppressed damage notifications
        print('[DAMAGE DEBUG] Start SUCCESS')
    end
    
    return started
end

-- Helper: Calculate environmental damage multiplier (MOVE THIS UP)
local function calculateEnvironmentalMultiplier(veh)
    if not veh or not DoesEntityExist(veh) then return 1.0 end
    
    local multiplier = 1.0
    local speed = GetEntitySpeed(veh) * 2.236936 -- MPH
    
    -- Check water depth
    local waterDepth = getWaterDepth(veh)
    local inMud = isInMud(veh)
    
    if waterDepth > 0.1 or inMud then
        local isOffroad = isOffroadVehicle(veh)
        local hasSnork = hasSnorkel(veh)
        
        -- Base environmental damage
        multiplier = DamageConfig.environmental.mud_multiplier
        
        -- Offroad vehicles handle it better
        if isOffroad then
            multiplier = multiplier * DamageConfig.environmental.offroad_protection
        end
        
        -- Deep water without snorkel = disaster
        if waterDepth > DamageConfig.environmental.water_depth_critical and not hasSnork then
            multiplier = multiplier * DamageConfig.environmental.no_snorkel_penalty
            
            -- Chance of immediate stall
            if math.random(100) < 15 then
                SetVehicleEngineOn(veh, false, true, true)
                SetVehicleUndriveable(veh, true)
                Wait(3000)
                SetVehicleUndriveable(veh, false)
            end
        end
        
        -- Moving fast through water/mud = worse
        if speed > 30 then
            multiplier = multiplier * 1.5
        end
    end
    
    return multiplier
end

-- REPLACE: Alternator stuttering system with dynamic intervals
CreateThread(function()
    while true do
        Wait(1000) -- Check every second
        
        if not DamageConfig.enabled then goto skip end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then goto skip end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then goto skip end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto skip end
        
        if not GetIsVehicleEngineRunning(veh) then goto skip end
        
        local damage = getVehicleDamage(veh)
        if not damage then goto skip end
        
        local plate = GetVehicleNumberPlateText(veh)
        local alternatorHealth = 100 - (tonumber(damage.alternator) or 0)
        
        -- Check if alternator should stutter
        if alternatorHealth < DamageConfig.starting.alternator_stutter then
            local now = GetGameTimer()
            lastAlternatorStutter[plate] = lastAlternatorStutter[plate] or 0
            
            -- Calculate dynamic stutter interval based on health
            -- 60% = 5 minutes, 30% = 2.5 minutes, 0% = 30 seconds
            local healthRatio = alternatorHealth / 60 -- 0-1 scale (60% to 0%)
            local minInterval = 30000 -- 30 seconds minimum
            local maxInterval = 300000 -- 5 minutes maximum
            local dynamicInterval = minInterval + (healthRatio * (maxInterval - minInterval))
            
            print(string.format('[DAMAGE DEBUG] Alternator health: %d%% | Next stutter in: %.1f seconds', 
                alternatorHealth, 
                (dynamicInterval - (now - lastAlternatorStutter[plate])) / 1000
            ))
            
            -- Time for next stutter?
            if (now - lastAlternatorStutter[plate]) >= dynamicInterval then
                print('[DAMAGE DEBUG] Alternator stutter starting!')
                
                -- Calculate stutter duration based on damage
                local stutterPercent = (60 - alternatorHealth) / 60 -- 0-1 scale
                local stutterDuration = DamageConfig.alternator.base_stutter_duration + 
                    (stutterPercent * (DamageConfig.alternator.max_stutter_duration - DamageConfig.alternator.base_stutter_duration))
                
                -- Suppressed damage notifications
                
                -- Stutter effect: rapid on/off
                local stutterEnd = now + stutterDuration
                CreateThread(function()
                    while GetGameTimer() < stutterEnd do
                        if not DoesEntityExist(veh) then break end
                        
                        -- Turn off
                        SetVehicleEngineOn(veh, false, false, false)
                        SetVehicleLights(veh, 1) -- Force lights off
                        Wait(math.random(200, 500))
                        
                        -- Turn on
                        SetVehicleEngineOn(veh, true, false, false)
                        SetVehicleLights(veh, 0) -- Normal lights
                        Wait(math.random(300, 700))
                    end
                    
                    -- Ensure engine is on after stutter
                    if DoesEntityExist(veh) then
                        SetVehicleEngineOn(veh, true, false, false)
                    end
                end)
                
                -- Damage alternator further from stuttering
                damage.alternator = math.min(100, (damage.alternator or 0) + DamageConfig.alternator.damage_per_stutter)
                
                -- Stuttering also drains battery
                damage.carbattery = math.min(100, (damage.carbattery or 0) + 2)
                
                applyDamage(veh, damage)
                
                lastAlternatorStutter[plate] = now
                
                print(string.format('[DAMAGE DEBUG] Alternator stuttered for %dms. Health now: %d%%. Next stutter in: %.1f seconds', 
                    math.floor(stutterDuration), 
                    100 - damage.alternator,
                    dynamicInterval / 1000
                ))
            end
        end
        
        ::skip::
    end
end)

-- NEW: Monitor power cuts while driving
CreateThread(function()
    while true do
        Wait(5000) -- Check every 5 seconds
        
        if not DamageConfig.enabled then goto skip end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then goto skip end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then goto skip end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto skip end
        
        if not GetIsVehicleEngineRunning(veh) then goto skip end
        
        local damage = getVehicleDamage(veh)
        if not damage then goto skip end
        
        local batteryHealth = 100 - (tonumber(damage.carbattery) or 0)
        
        -- Power cuts when battery below 30%
        if batteryHealth < DamageConfig.starting.battery_power_cut then
            local cutChance = (30 - batteryHealth) * 2 -- 0-60% chance
            
            if math.random(100) < cutChance then
                -- Power cut!
                SetVehicleEngineOn(veh, false, true, false)
                
                -- Damage battery from power cut
                damage.carbattery = math.min(100, (damage.carbattery or 0) + 2)
                applyDamage(veh, damage)
                
                -- Suppressed damage notifications
                
                -- Wait random time before can restart
                Wait(math.random(2000, 5000))
                
                -- More power cuts = more battery damage
                if batteryHealth < 15 then
                    damage.carbattery = math.min(100, (damage.carbattery or 0) + 3)
                    applyDamage(veh, damage)
                end
            end
        end
        
        ::skip::
    end
end)

-- REPLACE: Intercept engine starting (better detection)
local lastEngineState = {}

CreateThread(function()
    while true do
        Wait(100) -- Check every 100ms
        
        if not DamageConfig.enabled then goto continue end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then 
            lastEngineState = {}
            goto continue 
        end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then goto continue end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto continue end
        
        local plate = GetVehicleNumberPlateText(veh)
        local isEngineOn = GetIsVehicleEngineRunning(veh)
        local wasEngineOn = lastEngineState[plate]
        
        -- Detect engine start attempt (engine went from off to on)
        if isEngineOn and not wasEngineOn then
            print('[DAMAGE DEBUG] Engine start detected!') -- Debug
            
            local damage = getVehicleDamage(veh)
            if damage then
                vehicleStates[plate] = vehicleStates[plate] or { startAttempts = 0 }
                
                -- Check if start should succeed
                if not attemptVehicleStart(veh, damage) then
                    print('[DAMAGE DEBUG] Forcing engine off') -- Debug
                    -- Failed to start - force engine off
                    SetVehicleEngineOn(veh, false, true, true)
                    
                    vehicleStates[plate].startAttempts = vehicleStates[plate].startAttempts + 1
                    
                    if vehicleStates[plate].startAttempts >= DamageConfig.starting.attempts_max then
                        -- Suppressed damage notifications
                        damage.carbattery = math.min(100, (damage.carbattery or 0) + 5)
                        applyDamage(veh, damage)
                        vehicleStates[plate].startAttempts = 0
                    end
                else
                    vehicleStates[plate].startAttempts = 0
                end
            end
        end
        
        lastEngineState[plate] = isEngineOn
        
        ::continue::
    end
end)

-- Helper: Calculate driving condition damage multiplier
local function calculateDrivingMultiplier(veh, partKey)
    if not veh or not DoesEntityExist(veh) then return 1.0 end
    
    local speed = GetEntitySpeed(veh) * 2.236936
    local rpm = GetVehicleCurrentRpm(veh)
    local multiplier = 1.0
    
    if partKey == 'alternator' then
        if speed > 80 or rpm > 0.85 then
            multiplier = 1.5
        end
        
    elseif partKey == 'sparkplugs' then
        if speed > 100 then multiplier = 2.0
        elseif rpm > 0.9 then multiplier = 1.5 end
        
    elseif partKey == 'carbattery' then
        local damage = getVehicleDamage(veh)
        if damage then
            local alternatorHealth = 100 - (tonumber(damage.alternator) or 0)
            if alternatorHealth < 50 then
                multiplier = 2.0
            end
        end
        if GetIsVehicleEngineRunning(veh) then
            multiplier = multiplier * 1.0
        else
            multiplier = multiplier * 1.5
        end
        
    elseif partKey == 'brakes' then
        -- NEW: Brake wear based on usage
        local isBraking = IsControlPressed(0, 72) -- Brake key
        
        if isBraking then
            -- Heavy braking at high speed = more wear
            if speed > 60 then
                multiplier = 3.0
            elseif speed > 30 then
                multiplier = 2.0
            else
                multiplier = 1.5
            end
            
            -- Hard braking (full pressure) = extra wear
            local brakeValue = GetControlValue(0, 72)
            if brakeValue > 200 then
                multiplier = multiplier * 1.5
            end
        else
            multiplier = 0.1 -- Minimal wear when not braking
        end
        
    elseif partKey == 'oil' or partKey == 'oil_filter' then
        if speed > 80 then multiplier = 1.8 end
        
    elseif partKey == 'suspension' then
        if not IsVehicleOnAllWheels(veh) then multiplier = 3.0
        elseif speed > 60 then multiplier = 1.5 end
        
    elseif partKey == 'axle' then
        if HasEntityCollidedWithAnything(veh) then multiplier = 5.0
        elseif speed > 70 then multiplier = 1.3 end
    end
    
    return multiplier
end

-- Cache for original handling values to avoid compounding multipliers
local BrakeHandlingBase = {}      -- [veh] = { brake = number, hand = number }
local BrakeLastMultiplier = {}    -- [veh] = number
-- NEW: keep the original unmodified handling so we can fully restore
local OriginalBrakeHandling = {}  -- [veh] = { brake = number, hand = number }

-- NEW: Function to reset brake cache (call after repairs)
local function ResetBrakeCache(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    -- If we never captured originals, approximate them by undoing last multiplier
    local lastMult = BrakeLastMultiplier[veh] or 1.0
    local curBrake = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce') or 1.0
    local curHand  = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce') or 1.0
    local approxOrig = { brake = (lastMult > 0 and (curBrake / lastMult) or curBrake), hand = (lastMult > 0 and (curHand / lastMult) or curHand) }

    -- Prefer previously saved originals if present
    local orig = OriginalBrakeHandling[veh] or approxOrig

    -- Restore originals immediately
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', orig.brake)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce', orig.hand)

    -- Rebuild caches
    OriginalBrakeHandling[veh] = orig
    BrakeHandlingBase[veh] = { brake = orig.brake, hand = orig.hand }
    BrakeLastMultiplier[veh] = 1.0

    if Config.Debug then
        print(string.format('[BRAKE RESET] Restored base: brake=%.4f hand=%.4f', orig.brake, orig.hand))
    end
end

-- Export for other scripts to call
exports('ResetBrakeCache', ResetBrakeCache)

-- REPLACE the brake force thread completely
CreateThread(function()
    while true do
        Wait(0)

        if not DamageConfig.enabled then goto next end

        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then goto next end

        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 or not DoesEntityExist(veh) then goto next end

        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto next end

        local dmg = getVehicleDamage(veh)
        if not dmg then goto next end

        local effBrakeDmg = math.max(tonumber(dmg.brakes) or 0, tonumber(dmg.brakefluid) or 0)
        local brakeHealth = math.max(0, math.min(100, 100 - effBrakeDmg))

        if brakeHealth <= 0 then
            local vel = GetEntityVelocity(veh)
            local fwd = GetEntityForwardVector(veh)
            local fwdSpeed = vel.x*fwd.x + vel.y*fwd.y + vel.z*fwd.z
            local speed = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)
            if fwdSpeed > 0.5 and speed > 0.5 then
                DisableControlAction(0, 72, true)
            end
        end

        local brakeMultiplier = brakeHealth / 100.0

        if not BrakeHandlingBase[veh] then
            local curBrake = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce') or 0.0
            local curHand  = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce') or 0.0
            local lastMult = BrakeLastMultiplier[veh] or 1.0
            local origBrake = (lastMult > 0 and curBrake / lastMult) or curBrake
            local origHand  = (lastMult > 0 and curHand  / lastMult) or curHand
            if not OriginalBrakeHandling[veh] then
                OriginalBrakeHandling[veh] = { brake = origBrake, hand = origHand }
            end
            BrakeHandlingBase[veh] = { brake = OriginalBrakeHandling[veh].brake, hand = OriginalBrakeHandling[veh].hand }
        end

        local base = BrakeHandlingBase[veh]
        if base and base.brake and base.brake > 0 then
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', base.brake * brakeMultiplier)
        end
        if base and base.hand and base.hand > 0 then
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce', base.hand * brakeMultiplier)
        end

        BrakeLastMultiplier[veh] = brakeMultiplier

        -- NEW: If fully healthy (pads and fluid), force-restore to originals immediately
        if brakeMultiplier >= 0.999 then
            local orig = OriginalBrakeHandling[veh]
            if orig then
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', orig.brake)
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce', orig.hand)
                BrakeHandlingBase[veh] = { brake = orig.brake, hand = orig.hand }
                BrakeLastMultiplier[veh] = 1.0
            end
        end

        ::next::
    end
end)

-- NEW: Enhanced damage effects with oil-related engine damage
local function applyDamageEffects(veh, damage)
    if not veh or not DoesEntityExist(veh) or not damage then return end
    
    -- Spark plugs: Reduce power & chance of misfires
    local sparkplugDmg = tonumber(damage.sparkplugs) or 0
    if sparkplugDmg > 50 then
        local penalty = (sparkplugDmg - 50) / 50
        SetVehicleEnginePowerMultiplier(veh, math.max(0.4, 1.0 - (penalty * 0.4)))
        
        -- Random misfires
        if sparkplugDmg > 70 and math.random(100) < 5 then
            SetVehicleEngineOn(veh, false, false, false)
            Wait(500)
            SetVehicleEngineOn(veh, true, false, false)
        end
    end
    
    -- Battery: Power cuts and stalling
    local batteryDmg = tonumber(damage.carbattery) or 0
    if batteryDmg > 80 and math.random(100) < 3 then
        SetVehicleEngineOn(veh, false, true, true)
    end
    
    -- Oil: Direct engine damage when low
    local oilDmg = tonumber(damage.oil) or 0
    local oilHealth = 100 - oilDmg
    
    if oilHealth < 50 then
        local engineHealth = GetVehicleEngineHealth(veh)
        if engineHealth > 100 then
            -- Oil below 50% = progressive engine damage
            local damageRate = (50 - oilHealth) / 10 -- 0-5 damage per tick
            SetVehicleEngineHealth(veh, engineHealth - damageRate)
        end
    end
    
    if oilHealth < 20 then
        -- Critical oil = severe engine damage
        local engineHealth = GetVehicleEngineHealth(veh)
        if engineHealth > 100 then
            SetVehicleEngineHealth(veh, engineHealth - 10)
        end
        
        -- Suppressed smoke notification
    end
    
    -- Oil filter: Degrades with dirty oil
    if oilDmg > 50 then
        damage.oil_filter = math.min(100, (damage.oil_filter or 0) + 0.3)
    end
    
    -- Dirty oil filter makes oil degrade faster (feedback loop)
    local filterDmg = tonumber(damage.oil_filter) or 0
    if filterDmg > 60 then
        damage.oil = math.min(100, (damage.oil or 0) + 0.2)
    end
    
    -- Fuel injector: hard to start if damaged
    local injectorDmg = tonumber(damage.fuel_injector) or 0
    if injectorDmg > 70 then
        if math.random(100) < injectorDmg - 60 then
            SetVehicleEngineOn(veh, false, true, true)
        end
    end

    -- Power steering pump: harder to steer if damaged
    local psDmg = tonumber(damage.powersteeringpump) or 0
    if psDmg > 0 then
        local mult = 1.0 - (psDmg / 100)
        SetVehicleSteeringScale(veh, mult)
        -- Suppressed power steering notification
    end

    -- Radiator: overheating if damaged
    local radDmg = tonumber(damage.radiator) or 0
    if radDmg > 70 then
        if math.random(100) < (radDmg - 60) then
            SetVehicleEngineTemperature(veh, 120.0)
            if radDmg > 90 and math.random(100) < 10 then
                SetVehicleEngineOn(veh, false, true, true)
            end
        end
    end

    -- Transmission fluid: delays gear change if low
    local tfDmg = tonumber(damage.transmissionfluid) or 0
    if tfDmg > 50 then
        local delay = math.floor((tfDmg - 50) * 10)
        Citizen.Wait(delay)
    end

    -- Brake fluid: acts like damaged brakes
    local bfDmg = tonumber(damage.brakefluid) or 0
    if bfDmg > 50 then
        -- Use same logic as brakes (reduce brake force)
        -- (Handled in brake thread)
    end

    -- Coolant: overheating and fire if low
    local coolantDmg = tonumber(damage.coolant) or 0
    if coolantDmg > 80 then
        if math.random(100) < (coolantDmg - 80) then
            SetVehicleEngineTemperature(veh, 150.0)
            -- Steam effect (SYNCED)
            pcall(function()
                TriggerServerEvent('pf_mech:vfx:oneshot', {
                    dict='core',
                    name='exp_grd_petrol_pump',
                    type='entity',
                    netId=NetworkGetNetworkIdFromEntity(veh),
                    pos={0.0, 2.0, 1.0},
                    rot={0.0, 0.0, 0.0},
                    scale=1.0
                })
            end)
            if coolantDmg >= 100 and math.random(100) < 20 then
                -- Fire!
                StartEntityFire(veh)
            end
        end
    end

    -- Note: Brakes are handled in dedicated thread
end

-- Helper: Show environmental warnings
local function checkEnvironmentalWarnings(veh, envMultiplier)
    if not veh or not DoesEntityExist(veh) then return end
    
    local now = GetGameTimer()
    if (now - lastEnvironmentalWarning) < 30000 then return end -- Once per 30s
    
    local waterDepth = getWaterDepth(veh)
    local inMud = isInMud(veh)
    local hasSnork = hasSnorkel(veh)
    local isOffroad = isOffroadVehicle(veh)
    
    if waterDepth > DamageConfig.environmental.water_depth_critical and not hasSnork then
        lastEnvironmentalWarning = now
    elseif (waterDepth > 0.2 or inMud) and not isOffroad and not hasSnork then
        lastEnvironmentalWarning = now
    end
end

-- Helper: Show component warnings
local function checkComponentWarnings(veh, damage)
    if not veh or not DoesEntityExist(veh) or not damage then return end
    
    local plate = GetVehicleNumberPlateText(veh) or 'UNKNOWN'
    local now = GetGameTimer()
    
    lastWarnings[plate] = lastWarnings[plate] or {}
    
    local partNames = {
        alternator = 'Alternator',
        sparkplugs = 'Spark Plugs',
        carbattery = 'Battery',
        oil = 'Engine Oil',
        oil_filter = 'Oil Filter',
        brakes = 'Brake Pads',  -- NEW
        suspension = 'Suspension',
        axle = 'Axle'
    }
    
    for part, dmg in pairs(damage) do
        dmg = tonumber(dmg) or 0
        
        if dmg >= 70 and dmg < 100 then
            if not lastWarnings[plate][part] or (now - lastWarnings[plate][part]) > 120000 then
                lastWarnings[plate][part] = now
            end
        end
    end
end

-- NEW: Track mileage per vehicle (persisted in entity state)
local function getVehicleMileage(veh)
    if not veh or not DoesEntityExist(veh) then return 0 end
    local state = Entity(veh).state
    return tonumber(state.mileage) or 0
end
local function addMileage(veh, miles)
    if not veh or not DoesEntityExist(veh) then return end
    local state = Entity(veh).state
    local current = tonumber(state.mileage) or 0
    SafeStateSet(veh, 'mileage', current + miles)
end

-- NEW: Tables used but previously undefined
local LastBrakePress = {}
local BrakeHeat = {}

-- DEBUG: Valid parts for damage commands
local debugValidParts = {
    alternator=true, sparkplugs=true, carbattery=true, oil=true, oil_filter=true,
    brakes=true, suspension=true, axle=true, fuel_injector=true, powersteeringpump=true,
    radiator=true, power_steering_fluid=true, transmissionfluid=true, brakefluid=true,
    coolant=true
}

local function applyAndSyncDamage(veh, damage)
    applyDamage(veh, damage)
    applyDamageEffects(veh, damage)
end

local function setPartDamage(veh, part, value)
    if not DoesEntityExist(veh) then return false, 'No vehicle' end
    if not debugValidParts[part] then return false, 'Invalid part' end
    local damage = getVehicleDamage(veh) or {}
    damage[part] = math.max(0, math.min(100, tonumber(value) or 0))
    applyAndSyncDamage(veh, damage)
    return true
end

local function addPartDamage(veh, part, add)
    if not DoesEntityExist(veh) then return false, 'No vehicle' end
    if not debugValidParts[part] then return false, 'Invalid part' end
    local damage = getVehicleDamage(veh) or {}
    local current = tonumber(damage[part]) or 0
    damage[part] = math.max(0, math.min(100, current + (tonumber(add) or 0)))
    applyAndSyncDamage(veh, damage)
    return true
end

-- DEBUG COMMANDS (only register if Config.Debug = true)
if Config.Debug then
    RegisterCommand('damagepart', function(_, args)
        local part, value = args[1], args[2]
        if not part or not value then
            print('Usage: /damagepart <part> <value 0-100>')
            return
        end
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        local ok, err = setPartDamage(veh, part, value)
        if ok then QBCore.Functions.Notify(('Set %s damage to %s%%'):format(part, value), 'success')
        else QBCore.Functions.Notify(err, 'error') end
    end)

    RegisterCommand('damageadd', function(_, args)
        local part, value = args[1], args[2]
        if not part or not value then
            print('Usage: /damageadd <part> <delta>')
            return
        end
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        local ok, err = addPartDamage(veh, part, value)
        if ok then QBCore.Functions.Notify(('Added %s%% damage to %s'):format(value, part), 'warning')
        else QBCore.Functions.Notify(err, 'error') end
    end)

    RegisterCommand('damageall', function(_, args)
        local value = tonumber(args[1]) or 0
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then return QBCore.Functions.Notify('No vehicle', 'error') end
        local damage = getVehicleDamage(veh) or {}
        for part,_ in pairs(debugValidParts) do
            damage[part] = math.max(0, math.min(100, value))
        end
        applyAndSyncDamage(veh, damage)
        QBCore.Functions.Notify(('All parts set to %d%%'):format(value), 'success')
    end)

    RegisterCommand('damagereset', function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then return QBCore.Functions.Notify('No vehicle', 'error') end
        local damage = getVehicleDamage(veh) or {}
        for part,_ in pairs(debugValidParts) do damage[part] = 0 end
        applyAndSyncDamage(veh, damage)
        QBCore.Functions.Notify('All part damage reset', 'success')
    end)

    -- Convenience damage commands: /damageoil 80, /damagebrakes 60, etc.
    local function clamp01(v) return math.max(0, math.min(100, tonumber(v) or 0)) end
    local function setPartAndSync(veh, part, value)
        local d = getVehicleDamage(veh) or {}
        d[part] = clamp01(value)
        applyDamage(veh, d)
        applyDamageEffects(veh, d)
    end
    local function regDamageCommand(cmd, partKey)
        RegisterCommand(cmd, function(_, args)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 then QBCore.Functions.Notify('Not in a vehicle', 'error'); return end
            local val = args[1]
            if val == nil then
                QBCore.Functions.Notify(('Usage: /%s <0-100>'):format(cmd), 'error')
                return
            end
            setPartAndSync(veh, partKey, val)
            QBCore.Functions.Notify(('Set %s damage to %d%%'):format(partKey, clamp01(val)), 'primary')
        end, false)
    end

    -- Register per-part commands
    regDamageCommand('damageoil',                'oil')
    regDamageCommand('damagebrakes',             'brakes')
    regDamageCommand('damagebattery',            'carbattery')
    regDamageCommand('damagecarbattery',         'carbattery')
    regDamageCommand('damagesparkplugs',         'sparkplugs')
    regDamageCommand('damagealternator',         'alternator')
    regDamageCommand('damageradiator',           'radiator')
    regDamageCommand('damagecoolant',            'coolant')
    regDamageCommand('damagebrakefluid',         'brakefluid')
    regDamageCommand('damagetransmissionfluid',  'transmissionfluid')
    regDamageCommand('damagepowersteeringpump',  'powersteeringpump')
    regDamageCommand('damagepowersteeringfluid', 'power_steering_fluid')
    regDamageCommand('damagesuspension',         'suspension')
    regDamageCommand('damageaxle',               'axle')
end -- END Config.Debug block

-- Debug command
if Config.Debug then
  RegisterCommand('coalstatus', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
      local veh = GetVehiclePedIsIn(ped, false)
      local plate = _GetPlate(veh)
      
      -- Get damage state
      local damage = getVehicleDamage(veh) or {}
      
      print('=== VEHICLE DIAGNOSTICS ===')
      print('Plate:', plate)
      print('Engine Health:', math.floor(GetVehicleEngineHealth(veh)/10)..'%')
      print('Body Health:', math.floor(GetVehicleBodyHealth(veh)/10)..'%')
      print('')
      print('--- COMPONENT HEALTH (100% = perfect) ---')
      print(string.format('Oil:        %3d%% (damage: %.1f%%)', 100 - (damage.oil or 0), damage.oil or 0))
      print(string.format('Brakes:     %3d%% (damage: %.1f%%)', 100 - (damage.brakes or 0), damage.brakes or 0))
      print(string.format('Sparkplugs: %3d%% (damage: %.1f%%)', 100 - (damage.sparkplugs or 0), damage.sparkplugs or 0))
      print(string.format('Battery:    %3d%% (damage: %.1f%%)', 100 - (damage.carbattery or 0), damage.carbattery or 0))
      print(string.format('Alternator: %3d%% (damage: %.1f%%)', 100 - (damage.alternator or 0), damage.alternator or 0))
      print(string.format('Radiator:   %3d%% (damage: %.1f%%)', 100 - (damage.radiator or 0), damage.radiator or 0))
      print(string.format('Coolant:    %3d%% (damage: %.1f%%)', 100 - (damage.coolant or 0), damage.coolant or 0))
      print('==========================')
    else
      print('Not in vehicle')
    end
  end, false)
end

-- NEW: Main damage accumulation loop (MISSING - this is why natural wear doesn't show)
CreateThread(function()
    while true do
        Wait(DamageConfig.checkInterval) -- 5 seconds
        
        if not DamageConfig.enabled then goto skip end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then goto skip end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then goto skip end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto skip end
        
        if not GetIsVehicleEngineRunning(veh) then goto skip end
        
        local damage = getVehicleDamage(veh)
        if not damage then goto skip end
        
        local speed = GetEntitySpeed(veh) * 2.236936 -- MPH
        local rpm = GetVehicleCurrentRpm(veh)
        
        -- Get environmental multiplier
        local envMultiplier = calculateEnvironmentalMultiplier(veh)
        
        -- Apply wear to each component
        local damageApplied = false
        
        for partKey, baseRate in pairs(DamageConfig.damageRates) do
            if baseRate > 0 then
                -- Get driving-specific multiplier
                local drivingMult = calculateDrivingMultiplier(veh, partKey)
                
                -- Calculate total damage this tick
                local totalDamage = baseRate * drivingMult * envMultiplier * speedWearFactor(speed)
                
                if totalDamage > 0.01 then -- Only apply if meaningful
                    damage[partKey] = math.min(100, (damage[partKey] or 0) + totalDamage)
                    damageApplied = true
                end
            end
        end
        
        -- FIX: Apply damage to vehicle state so it shows in diagnostics
        if damageApplied then
            applyDamage(veh, damage)
            applyDamageEffects(veh, damage)
            
            -- Check for warnings
            checkComponentWarnings(veh, damage)
            checkEnvironmentalWarnings(veh, envMultiplier)
        end
        
        ::skip::
    end
end)