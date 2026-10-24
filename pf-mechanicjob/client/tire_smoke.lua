local QBCore = exports['pfm-core']:GetCoreObject()

-- Config with safe defaults (override via Config.TireSmoke in your config.lua if desired)
local TS = (Config and Config.TireSmoke) or {}
local ENABLED   = (TS.enabled ~= false)
local DEBUG     = TS.debug or false
local MAX_MPH   = TS.maxMph or 25.0          -- max speed to emit heavy smoke (burnouts/launches)
local MIN_RPM   = TS.minRpm or 0.35          -- min RPM to consider "push"
local TICK_MS   = TS.tick or 100
local SCALE     = TS.scale or 1.65              -- CHANGED: larger base scale
local PER_WHEEL = 1                              -- (unused now; replaced by LOOPS_PER_WHEEL)
-- NEW: base particle effect (was missing → no smoke loaded)
local DICT      = TS.dict or 'core'
local NAME      = TS.name or 'exp_grd_tire_smoke'
-- NEW: density & behavior tuning
local LOOPS_PER_WHEEL = math.min(10, math.max(1, TS.loops or 5))      -- CHANGED: higher default loops
local HEAVY_ENABLED   = (TS.heavyEnabled ~= false)                    -- NEW
local HEAVY_INTERVAL  = TS.heavyInterval or 120                       -- NEW ms between heavy bursts
local HEAVY_PER_WHEEL = math.min(8, math.max(2, TS.heavyPerWheel or 4))-- NEW bursts per wheel each interval
local HEAVY_LIFETIME  = TS.heavyLifetime or 2200                      -- NEW ms heavy burst life
local MAX_HEAVY_ACTIVE= TS.maxHeavyActive or 160                      -- NEW global cap

-- Track current vehicle/bone effects
local currentVeh    = 0
local currentNet    = nil
local boneFx        = {}   -- [boneIndex] = { fx1, fx2, ... }
local dictLoaded    = false
local enabledLocal  = ENABLED

-- NEW: track extra (non-looped) particles & last spawn time
local extraFx     = {}   -- [bone] = { {handle=*, dieAt=ms}, ... }
local lastBurstAt = {}   -- [bone] = timestamp

local function mph(v) return (GetEntitySpeed(v) * 2.236936) end

local function loadPtfx()
    if dictLoaded then return true end
    RequestNamedPtfxAsset(DICT)
    local untilAt = GetGameTimer() + 2000
    while not HasNamedPtfxAssetLoaded(DICT) do
        if GetGameTimer() > untilAt then break end
        Wait(0)
    end
    dictLoaded = HasNamedPtfxAssetLoaded(DICT)
    return dictLoaded
end

local WHEEL_BONE_NAMES = {
    'wheel_lf','wheel_rf','wheel_lr','wheel_rr',  -- common
    'wheel_lm1','wheel_rm1','wheel_lm2','wheel_rm2','wheel_lm3','wheel_rm3' -- multi-axle
}

local function getWheelBones(veh)
    local out = {}
    for _, n in ipairs(WHEEL_BONE_NAMES) do
        local idx = GetEntityBoneIndexByName(veh, n)
        if idx ~= -1 then out[#out+1] = idx end
    end
    return out
end

local function clearAllFx()
    for _, handles in pairs(boneFx) do
        for _, fx in ipairs(handles) do
            if fx then pcall(function() StopParticleFxLooped(fx, true) end) end
        end
    end
    boneFx = {}
end

local function stopForVehicle()
    if currentVeh ~= 0 then clearAllFx() end
    currentVeh, currentNet = 0, nil
end

-- REPLACED startFxForBone: use entity bone loops (stack better)
local function startFxForBone(veh, bone)
    if not dictLoaded and not loadPtfx() then return end
    boneFx[bone] = boneFx[bone] or {}
    for i = 1, LOOPS_PER_WHEEL do
        if not boneFx[bone][i] or not DoesParticleFxLoopedExist(boneFx[bone][i]) then
            UseParticleFxAssetNextCall(DICT)
            local ox = (math.random() - 0.5) * 0.045
            local oy = -0.02 + (math.random() - 0.5) * 0.04
            local oz = (math.random() - 0.5) * 0.025
            boneFx[bone][i] = StartParticleFxLoopedOnEntityBone(NAME, veh, ox, oy, oz, 0.0,0.0,0.0, bone, SCALE, false,false,false)
        end
    end
end

-- NEW: dynamic scale adjust (rpm ↑ => more, speed ↑ => fade)
local function adjustFxScale(veh)
    if veh == 0 or not DoesEntityExist(veh) then return end
    local rpm  = GetVehicleCurrentRpm(veh) or 0.0
    local mphV = mph(veh)
    local fade = 1.0 - math.min(1.0, mphV / FADE_MPH)
    local dynScale = SCALE * math.max(0.55, math.min(2.4, (0.55 + rpm * RPM_MULT) * fade))
    for _, arr in pairs(boneFx) do
        for _, fx in ipairs(arr) do
            if fx and DoesParticleFxLoopedExist(fx) then
                -- Try evolution; if asset does not support "size" silently ignore
                pcall(function() SetParticleFxLoopedEvolution(fx, 'size', dynScale, false) end)
            end
        end
    end
end

-- (RESTORED + ENHANCED) supplemental non-looped bursts
local function spawnExtraBursts(veh, bone)
    if not HEAVY_ENABLED or not dictLoaded and not loadPtfx() then return end
    local now = GetGameTimer()
    local last = lastBurstAt[bone] or 0
    if (now - last) < HEAVY_INTERVAL then return end
    lastBurstAt[bone] = now

    -- global cap
    local active = 0
    for _, arr in pairs(extraFx) do active = active + #arr end
    if active >= MAX_HEAVY_ACTIVE then return end

    extraFx[bone] = extraFx[bone] or {}

    for i = 1, HEAVY_PER_WHEEL do
        if active >= MAX_HEAVY_ACTIVE then break end
        UseParticleFxAssetNextCall(DICT)
        local ox = (math.random() - 0.5) * 0.09
        local oy = -0.04 + (math.random() * 0.08)
        local oz = (math.random() - 0.5) * 0.05
        local h = StartParticleFxNonLoopedOnEntityBone(NAME, veh, ox, oy, oz, 0.0,0.0,0.0, bone, SCALE * 1.15)
        extraFx[bone][#extraFx[bone] + 1] = { handle = h, dieAt = now + HEAVY_LIFETIME }
        active = active + 1
    end
end

local function pruneExtraFx()
    local now = GetGameTimer()
    for b, arr in pairs(extraFx) do
        local keep = {}
        for _, data in ipairs(arr) do
            if data.dieAt > now then keep[#keep+1] = data end
        end
        extraFx[b] = keep
    end
end

-- CHANGED: ensureFx (call adjustFxScale after spawning)
local function ensureFx(veh)
    if veh == 0 or not DoesEntityExist(veh) then return end
    if veh ~= currentVeh then
        stopForVehicle()
        currentVeh = veh
        currentNet = VehToNet(veh)
    end
    local bones = getWheelBones(veh)
    for _, b in ipairs(bones) do
        startFxForBone(veh, b)
        spawnExtraBursts(veh, b) -- CHANGED: heavier bursts
    end
    adjustFxScale(veh)
    pruneExtraFx()
end

local function stopFxIfAny()
    -- CHANGED: simple loop; no change besides existing
    if next(boneFx) ~= nil then clearAllFx() end
    extraFx, lastBurstAt = {}, {} -- NEW: reset burst tracking
end

local function burnoutOrLaunch(veh, ped)
    if veh == 0 or not DoesEntityExist(veh) then return false end
    -- GTA native burnout condition or manual heuristic:
    local isBurnout = IsVehicleInBurnout(veh)
    local accHeld   = IsControlPressed(0, 71) -- accelerate
    local brakeHeld = IsControlPressed(0, 72) or IsControlPressed(0, 76) -- brake/handbrake
    local vMph      = mph(veh)
    local rpm       = GetVehicleCurrentRpm(veh) or 0.0

    -- Burnout or hard launch (low speed + high RPM + accel)
    if isBurnout then return true end
    if accHeld and (vMph <= MAX_MPH) and (rpm >= MIN_RPM) then return true end
    if accHeld and brakeHeld then return true end

    return false
end

-- Toggle (command + event)
RegisterCommand('tiresmoke', function()
    enabledLocal = not enabledLocal
    if not enabledLocal then stopForVehicle() end
    QBCore.Functions.Notify(('Tire smoke %s'):format(enabledLocal and 'enabled' or 'disabled'), enabledLocal and 'success' or 'primary')
end, false)
RegisterNetEvent('pf_mech:tireSmoke:toggle', function(on)
    enabledLocal = (on == nil) and (not enabledLocal) or (on and true or false)
    if not enabledLocal then stopForVehicle() end
end)

-- Main loop
CreateThread(function()
    while true do
        Wait(TICK_MS)
        if not enabledLocal then goto continue end

        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            if currentVeh ~= 0 then stopForVehicle() end
            goto continue
        end

        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
            if currentVeh ~= 0 then stopForVehicle() end
            goto continue
        end

        if burnoutOrLaunch(veh, ped) then
            ensureFx(veh)
        else
            stopFxIfAny()
        end

        ::continue::
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopForVehicle()
    extraFx, lastBurstAt = {}, {}
end)

if DEBUG then
    CreateThread(function()
        while true do
            Wait(1000)
            if currentVeh ~= 0 then
                print(('[TIRE SMOKE] active bones=%d'):format((function(t) local c=0; for _ in pairs(t) do c=c+1 end; return c end)(boneFx)))
            end
        end
    end)
end

-- OPTIONAL: debug extra counts
if DEBUG then
    CreateThread(function()
        while true do
            Wait(2000)
            local total = 0
            for _, arr in pairs(extraFx) do total = total + #arr end
            if currentVeh ~= 0 then
                print(('[TIRE SMOKE] base loops=%d extraActive=%d'):format(
                    (function(t) local c=0 for _ in pairs(t) do c=c+1 end return c end)(boneFx),
                    total
                ))
            end
        end
    end)
end

-- OPTIONAL: debug print density
if DEBUG then
    CreateThread(function()
        while true do
            Wait(3000)
            if currentVeh ~= 0 then
                local loops = 0
                for _, arr in pairs(boneFx) do loops = loops + #arr end
                print(string.format('[TIRE SMOKE] veh=%s loops=%d scaleBase=%.2f dynAdjust=ON', tostring(currentVeh), loops, SCALE))
            end
        end
    end)
end

-- OPTIONAL DEBUG: show heavy count
if DEBUG then
    CreateThread(function()
        while true do
            Wait(2500)
            if currentVeh ~= 0 then
                local loops = 0
                for _, arr in pairs(boneFx) do loops = loops + #arr end
                local heavy = 0
                for _, arr in pairs(extraFx) do heavy = heavy + #arr end
                print(string.format('[TIRE SMOKE] veh=%s loops=%d heavy=%d', tostring(currentVeh), loops, heavy))
            end
        end
    end)
end
