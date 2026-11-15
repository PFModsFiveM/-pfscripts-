-- Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
-- Port of whip_core/client/vehicle_hud.lua (the 3D rev dial's feeder). Free software under the GNU Lesser General
-- Public License 3.0 (see COPYING.LESSER and COPYING).
--
-- What the dial shows (rpm, speed, gear, four lights; aircraft instruments; a boat's anchor), read off the vehicle
-- fifteen times a second and sent only when something moved, in one message table refilled each time. The gauges round
-- the dial (fuel, nitrous) ride in client.lua's 'vehicle' message. Nothing is read on foot or with the dial off.
--
-- The rev ranges measured from GTA's engine recordings (data/rpm_by_model.lua) and the dashboard looks per model
-- (data/dash_skins.lua) are made from Rockstar material, so they live in pfm-media-map and are read from it with
-- LoadResourceFile; without it the dial uses Config.VehicleHud's ranges and every car keeps the dial as designed.

HudDial = {}

local CFG = Config.VehicleHud or {}
local MEDIA = Config.MediaMapResource or 'pfm-media-map'

local CLASS_NAMES = {
    [0] = 'compacts', [1] = 'sedans', [2] = 'suvs', [3] = 'coupes', [4] = 'muscle', [5] = 'sportsclassics',
    [6] = 'sports', [7] = 'super', [8] = 'motorcycles', [9] = 'offroad', [10] = 'industrial', [11] = 'utility',
    [12] = 'vans', [13] = 'cycles', [14] = 'boats', [15] = 'helicopters', [16] = 'planes', [17] = 'service',
    [18] = 'emergency', [19] = 'military', [20] = 'commercial', [21] = 'trains', [22] = 'openwheel',
}
local NO_DIAL = { [13] = true, [21] = true }            -- bicycles, trains
local KIND = { [14] = 'boat', [15] = 'air', [16] = 'air' }

local UNITS, ATTITUDE, DASH_SKINS, DIAL_ON, BANK_SIGN = 'mph', 'ball', true, true, 1
local RPM_MAX, REDLINE, RPM_ELECTRIC, IDLE_RPM, IDLE_MEASURED, RPM_BY_CLASS, RPM_BY_MODEL

local function readConfig()
    BANK_SIGN    = CFG.flipBank == true and -1 or 1
    RPM_MAX      = tonumber(CFG.rpmMax) or 8
    REDLINE      = tonumber(CFG.redline) or 0.87
    RPM_ELECTRIC = tonumber(CFG.rpmElectric) or 20
    IDLE_RPM     = tonumber(CFG.idleRpm)
    IDLE_MEASURED = CFG.idleMeasured == true or IDLE_RPM == nil
    RPM_BY_CLASS = type(CFG.rpmByClass) == 'table' and CFG.rpmByClass or {}
    RPM_BY_MODEL = {}
    for name, max in pairs(type(CFG.rpmByModel) == 'table' and CFG.rpmByModel or {}) do
        if type(name) == 'string' and tonumber(max) then RPM_BY_MODEL[GetHashKey(name)] = tonumber(max) end
    end
end
readConfig()

-- ── data from pfm-media-map ──────────────────────────────────────────

local MEASURED, MEASURED_CLASS, DASH_SKIN = {}, {}, {}
local dataLoaded = false

--- A Lua data file from pfm-media-map, run in an empty environment as plain data; nil when it is not there.
local function mediaData(file)
    if GetResourceState(MEDIA) ~= 'started' then return nil end
    local src = LoadResourceFile(MEDIA, file)
    if type(src) ~= 'string' or src == '' then return nil end
    local chunk = load(src, '@' .. MEDIA .. '/' .. file, 't', {})
    if not chunk then return nil end
    local ok, t = pcall(chunk)
    if ok and type(t) == 'table' then return t end
    return nil
end

--- (Re)read the measured rev ranges and the dashboard looks. Answers whether pfm-media-map gave them.
---@return boolean
function HudDial.loadData()
    MEASURED, MEASURED_CLASS, DASH_SKIN = {}, {}, {}
    local rpm = mediaData('data/rpm_by_model.lua')
    if rpm then
        for name, r in pairs(type(rpm.models) == 'table' and rpm.models or {}) do
            local idle, limiter = type(r) == 'table' and tonumber(r[1]), type(r) == 'table' and tonumber(r[2])
            if type(name) == 'string' and idle and limiter and limiter > idle then
                MEASURED[GetHashKey(name)] = { idle, limiter }
            end
        end
        for class, max in pairs(type(rpm.classMax) == 'table' and rpm.classMax or {}) do
            if type(class) == 'string' and tonumber(max) then MEASURED_CLASS[class] = tonumber(max) end
        end
    end
    local skins = mediaData('data/dash_skins.lua')
    if skins then
        for name, id in pairs(skins) do
            if type(name) == 'string' and type(id) == 'string' then DASH_SKIN[GetHashKey(name)] = id end
        end
    end
    dataLoaded = rpm ~= nil and skins ~= nil
    return dataLoaded
end

function HudDial.hasData() return dataLoaded end
function HudDial.skinOf(hash) return DASH_SKIN[hash] end
function HudDial.measured(hash) return MEASURED[hash] end
function HudDial.measuredClass(class) return MEASURED_CLASS[class] end

HudDial.loadData()

-- ── rev range ────────────────────────────────────────────────────────

local IDLE_SHARE = 0.113
local _electric = {}

local function isElectric(hash)
    local e = _electric[hash]
    if e == nil then
        -- _GET_IS_VEHICLE_ELECTRIC (build 3258+); a build without it answers through the pcall: not electric
        local ok, r = pcall(function() return Citizen.InvokeNative(0x1FCB07FE230B6639, hash, Citizen.ReturnResultAnyway()) end)
        e = ok and (r == true or r == 1) or false
        _electric[hash] = e
    end
    return e
end

--- Dial top (thousands), redline, idle. First match: rpmByModel, electric, rpmByClass, measured class top, rpmMax.
function HudDial.revRange(veh)
    local chosenIdle = not IDLE_MEASURED and IDLE_RPM or nil
    local engine = GetEntityModel(veh)
    local class = CLASS_NAMES[GetVehicleClass(veh)]
    local electric = isElectric(engine)
    local max = RPM_BY_MODEL[engine] or (electric and RPM_ELECTRIC)
        or tonumber(RPM_BY_CLASS[class]) or MEASURED_CLASS[class] or RPM_MAX
    max = math.max(2.0, math.min(20.0, max))
    local idle = electric and 0 or chosenIdle or (MEASURED[engine] and MEASURED[engine][1]) or max * IDLE_SHARE
    return max, max * REDLINE, math.min(idle, max * 0.5)
end

-- ── cadence ──────────────────────────────────────────────────────────

local DIAL_TICK_MS = 66        -- fifteen times a second (four frames at 60 fps)
local IDLE_TICK_MS = 250
local RPM_DEADBAND = 0.015
local RPM_LIMITER = 0.985
local ANGLE_STEP, ALT_STEP = 0.25, 0.3
local HAS_LANDING_GEAR, LANDING_GEAR_STATE, BOAT_ANCHORED = 0xE43701C36CAFF1A4, 0x9B0F3DCA3DB0F4CD, 0xB0AD1238A709B1A2

local function yes(v) return v == true or v == 1 end

local function isReversing(veh, gear)
    if GetEntitySpeedVector(veh, true).y < -0.5 then return true end
    return gear == 0 and yes(GetIsVehicleEngineRunning(veh))
end

local function gearLabel(veh, gear, speedKmh, handbrake)
    if isReversing(veh, gear) then return 'R' end
    if (handbrake and speedKmh < 0.5) or gear == 0 then return 'N' end
    return gear
end

local function lightsOf(veh)
    local _, on, high = GetVehicleLightsState(veh)
    if on ~= 1 and on ~= true then return 'off' end
    return (high == 1 or high == true) and 'high' or 'low'
end

local function landingGearOf(veh)
    if not yes(Citizen.InvokeNative(HAS_LANDING_GEAR, veh, Citizen.ReturnResultAnyway())) then return 'none' end
    local g = Citizen.InvokeNative(LANDING_GEAR_STATE, veh, Citizen.ResultAsInteger())
    if g == 0 then return 'down' end
    if g == 4 then return 'up' end
    return 'moving'
end

local function boatGear(veh)
    local ahead = GetEntitySpeedVector(veh, true).y
    return ahead > 0.5 and 'F' or ahead < -0.5 and 'R' or 'N'
end

-- a boat's propeller out of the water with the throttle held: the engine revs free (GTA's boat rpm follows hull speed)
local PROP_HOLD_MS, PROP_THROTTLE = 250, 0.3
local propVeh, propBone, propStern, propOutAt = 0, -1, nil, -1

local function boatPropOut(veh, running, now)
    if veh ~= propVeh then
        propVeh, propOutAt = veh, -1
        propBone = GetEntityBoneIndexByName(veh, 'prop_1')
        propStern = GetModelDimensions(GetEntityModel(veh))
    end
    if running and math.abs(GetVehicleThrottleOffset(veh)) >= PROP_THROTTLE then
        local out = not yes(IsEntityInWater(veh))
        if not out and propStern then
            local p = propBone ~= -1 and GetWorldPositionOfEntityBone(veh, propBone)
                or GetOffsetFromEntityInWorldCoords(veh, 0.0, propStern.y, propStern.z)
            local found, water = GetWaterHeight(p.x, p.y, p.z + 10.0)
            out = not yes(found) or p.z > water
        end
        if out then propOutAt = now end
    end
    return propOutAt >= 0 and now - propOutAt < PROP_HOLD_MS
end

local function quantise(value, step) return math.floor(value / step + 0.5) * step end

-- ── sending ──────────────────────────────────────────────────────────

local _last = {}
local function resetDials() _last = {} end

--- Send everything again on the next read (the page showed sample numbers).
function HudDial.resend() _last = {} end

--- The dial payload, allocated once and refilled on every send.
local _dialMsg = {
    action = 'updateVehicleDials',
    rpm = 0.0, speed = 0, gear = 'N', eng = false, lights = 'off', locked = false, dmg = false, launch = false,
    pitch = 0.0, roll = 0.0, alt = 0.0, gearState = 'none', anchored = false, freeRev = false,
}

local function mediaUrl()
    return GetResourceState(MEDIA) == 'started' and ('https://cfx-nui-%s/'):format(MEDIA) or false
end

function HudDial.sendConfig()
    SendNUIMessage({ action = 'vehicleHudConfig', units = UNITS, attitude = ATTITUDE, skins = DASH_SKINS,
        style = HudDial.style, media = mediaUrl() })
end

local function sendRange(veh)
    local max, redline, idle = HudDial.revRange(veh)
    local class = GetVehicleClass(veh)
    local kind = KIND[class] or 'car'
    SendNUIMessage({ action = 'vehicleDialRange', maxRpm = max, redline = redline, idle = idle,
        dial = DIAL_ON and not NO_DIAL[class], kind = kind,
        skin = DASH_SKINS and kind ~= 'air' and DASH_SKIN[GetEntityModel(veh)] or false })
end

HudDial.style = 'custom'

--- The player's dial settings: style ('custom' | 'pf' | 'simple' | 'none'), speed unit, horizon.
function HudDial.configure(s)
    UNITS = s.speedUnit == 'kmh' and 'kmh' or 'mph'
    ATTITUDE = s.dialHorizon == 'flat' and 'flat' or 'ball'
    local style = s.dialStyle
    if style ~= 'pf' and style ~= 'simple' and style ~= 'none' then style = 'custom' end
    HudDial.style = style
    DASH_SKINS = style == 'custom'
    DIAL_ON = style ~= 'none' and not Config.DisableCarHud
    HudDial.sendConfig()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 and DoesEntityExist(veh) then
        resetDials()
        sendRange(veh)
    end
end

--- client.lua's answer: may the dial read now (logged in, HUD not hidden by cinematic mode)?
HudDial.allowed = function() return true end

local function dialLoop()
    local seatedIn = 0
    local seatedKind, noDial = 'car', false
    while true do
        local veh = HudDial.allowed() and GetVehiclePedIsIn(PlayerPedId(), false) or 0
        local inVehicle = veh ~= 0 and DoesEntityExist(veh)

        if inVehicle and veh ~= seatedIn then
            seatedIn = veh
            local class = GetVehicleClass(veh)
            seatedKind, noDial = KIND[class] or 'car', NO_DIAL[class] == true
            resetDials()
            sendRange(veh)
        end

        if inVehicle and not noDial and DIAL_ON then
            local running   = yes(GetIsVehicleEngineRunning(veh))
            local rpm       = running and quantise(GetVehicleCurrentRpm(veh), 0.005) or 0.0
            local speed     = math.floor(GetEntitySpeed(veh) * 3.6 + 0.5)          -- km/h: the page converts
            local handbrake = yes(GetVehicleHandbrake(veh))
            local rawGear   = GetVehicleCurrentGear(veh)
            local gear      = seatedKind == 'boat' and boatGear(veh) or gearLabel(veh, rawGear, speed, handbrake)
            local launch    = seatedKind == 'car' and (rawGear == 1 or handbrake)
            local lights    = lightsOf(veh)
            local locked    = GetVehicleDoorLockStatus(veh) == 2
            local damaged   = GetVehicleEngineHealth(veh) < 400.0

            local kindMoved = false
            if seatedKind == 'air' then
                local pitch = quantise(GetEntityPitch(veh), ANGLE_STEP)
                local roll  = quantise(GetEntityRoll(veh) * BANK_SIGN, ANGLE_STEP)
                local alt   = quantise(GetEntityCoords(veh).z, ALT_STEP)
                local gs    = landingGearOf(veh)
                kindMoved = pitch ~= _last.pitch or roll ~= _last.roll or alt ~= _last.alt or gs ~= _last.gearState
                _dialMsg.pitch, _dialMsg.roll, _dialMsg.alt, _dialMsg.gearState = pitch, roll, alt, gs
            elseif seatedKind == 'boat' then
                local anchored = yes(Citizen.InvokeNative(BOAT_ANCHORED, veh, Citizen.ReturnResultAnyway()))
                local freeRev = boatPropOut(veh, running, GetGameTimer())
                kindMoved = anchored ~= _last.anchored or freeRev ~= _last.freeRev
                _dialMsg.anchored, _dialMsg.freeRev = anchored, freeRev
            end

            local lastRpm = _last.rpm
            local rpmMoved = lastRpm == nil or math.abs(rpm - lastRpm) >= RPM_DEADBAND
                or (rpm >= RPM_LIMITER) ~= (lastRpm >= RPM_LIMITER) or (rpm == 0) ~= (lastRpm == 0)

            if rpmMoved or kindMoved or speed ~= _last.speed or gear ~= _last.gear or running ~= _last.eng
                or lights ~= _last.lights or locked ~= _last.locked or damaged ~= _last.dmg or launch ~= _last.launch then
                _last.rpm, _last.speed, _last.gear, _last.eng = rpm, speed, gear, running
                _last.lights, _last.locked, _last.dmg, _last.launch = lights, locked, damaged, launch
                _last.pitch, _last.roll, _last.alt, _last.gearState = _dialMsg.pitch, _dialMsg.roll, _dialMsg.alt, _dialMsg.gearState
                _last.anchored, _last.freeRev = _dialMsg.anchored, _dialMsg.freeRev
                _dialMsg.rpm, _dialMsg.speed, _dialMsg.gear, _dialMsg.eng = rpm, speed, gear, running
                _dialMsg.lights, _dialMsg.locked, _dialMsg.dmg, _dialMsg.launch = lights, locked, damaged, launch
                SendNUIMessage(_dialMsg)
            end
            Wait(DIAL_TICK_MS)
        else
            if not inVehicle and seatedIn ~= 0 then
                seatedIn = 0
                resetDials()
            end
            Wait(IDLE_TICK_MS)
        end
    end
end

local started = false
--- Start the loop (once, at the first character load).
function HudDial.start()
    if started then return end
    started = true
    CreateThread(dialLoop)
end

-- pfm-media-map started or stopped after the HUD: the data and the page's skins follow
AddEventHandler('onClientResourceStart', function(res)
    if res ~= MEDIA then return end
    HudDial.loadData()
    HudDial.sendConfig()
end)
AddEventHandler('onClientResourceStop', function(res)
    if res ~= MEDIA then return end
    MEASURED, MEASURED_CLASS, DASH_SKIN, dataLoaded = {}, {}, {}, false
    HudDial.sendConfig()
end)
