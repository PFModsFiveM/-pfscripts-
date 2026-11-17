-- Client applier for the functional effect profile (architecture 11.4, batch 17C). The server
-- decides every channel (server/medical/effects.lua) and sends it with
-- 'pf-ambulancejob:client:Effects' only when it changed; this file only applies it.
--
-- Channels 0..3: walk, sprint, jump, climb, aim, reload, drive, stamina, vision, pain. Each native
-- effect is set once per change and undone when its channel returns to 0, so nothing stacks. No
-- thread runs while every channel is 0. While a channel needs input blocking (no sprint, no jump,
-- a driver who must stop) the loop runs every frame; otherwise it wakes every 250 ms.
-- Honest limit: GTA has no native for reload speed, so `reload` is not applied on the client
-- (it still counts for restrictions such as no_heavy_work on the server).

PFEffects = PFEffects or {}
local E = PFEffects

E.Channels = { 'walk', 'sprint', 'jump', 'climb', 'aim', 'reload', 'drive', 'stamina', 'vision', 'pain' }
E.Clipset = 'move_m@injured'
E.MoveRate = { [1] = 1.0, [2] = 0.85, [3] = 0.65 }       -- walk channel -> move rate (1 keeps the limp clipset only)
E.AimShake = { [1] = 0.25, [2] = 0.6, [3] = 1.1 }        -- aim channel -> hand shake while aiming
E.Blur = { [1] = 0.15, [2] = 0.35, [3] = 0.6 }           -- vision channel -> timecycle strength
E.BlurModifier = 'BarryFadeOut'
E.PainEvery = { [1] = 45000, [2] = 25000, [3] = 12000 }  -- pain channel -> ms between pain pulses
E.StaminaDrain = { [1] = 1.0, [2] = 2.5, [3] = 5.0 }     -- stamina channel -> stamina lost per 250 ms of sprinting
E.WobbleEvery = 3500                                      -- drive 1: a small steering pull this often
E.SlowMs = 250

local state = {
    version = 0,          -- the last version applied (older pushes are ignored)
    profile = nil,        -- the clean profile in force
    restrictions = {},    -- [kind] = true
    running = false,      -- the loop thread exists
    applied = {},         -- what this file changed on the game, so it undoes only its own changes
    nextSlow = 0, nextPain = 0, nextWobble = 0,
}
E.state = state

local function clamp3(v)
    v = math.floor(tonumber(v) or 0)
    if v ~= v or v < 0 then return 0 elseif v > 3 then return 3 end
    return v
end

--- A clean profile from whatever arrived: every channel an integer 0..3.
function E.Clean(profile)
    local out = {}
    for _, ch in ipairs(E.Channels) do out[ch] = clamp3(type(profile) == 'table' and profile[ch] or 0) end
    return out
end

function E.IsEmpty(p)
    for _, ch in ipairs(E.Channels) do if (p[ch] or 0) ~= 0 then return false end end
    return true
end

--- What a profile asks of the game (pure; the specs check it). needsFrame: input must be blocked
--- every frame (sprint, jump/climb); the drive check adds it only while the player sits in the
--- driver seat with drive >= 2.
function E.Plan(p)
    local plan = {
        clipset = p.walk >= 1 and E.Clipset or nil,
        moveRate = p.walk >= 2 and E.MoveRate[p.walk] or nil,
        blockSprint = p.sprint >= 2 or p.walk >= 2,
        blockJump = p.jump >= 2 or p.climb >= 2 or p.walk >= 3,
        aimShake = p.aim >= 1 and E.AimShake[p.aim] or nil,
        blur = p.vision >= 1 and E.Blur[p.vision] or nil,
        painEvery = p.pain >= 1 and E.PainEvery[p.pain] or nil,
        staminaDrain = p.stamina >= 1 and E.StaminaDrain[p.stamina] or nil,
        noDrive = p.drive >= 2,
        wobble = p.drive == 1,
    }
    plan.needsFrame = plan.blockSprint or plan.blockJump or plan.moveRate ~= nil
    plan.empty = E.IsEmpty(p)
    return plan
end

local function notify(msg, kind)
    if QBCore and QBCore.Functions and QBCore.Functions.Notify then QBCore.Functions.Notify(msg, kind or 'error') end
end

local function isDown()
    return (isDead == true) or (InLaststand == true) or (ServerDownState ~= nil and ServerDownState ~= false)
end

-- ── undo / apply one effect each ───────────────────────────────────────────────────────────────

local function clearClipset(ped)
    if state.applied.clipset then
        ResetPedMovementClipset(ped, 0.0)
        state.applied.clipset = nil
    end
end

local function clearShake()
    if state.applied.shake then
        StopGameplayCamShaking(true)
        state.applied.shake = nil
    end
end

local function clearBlur()
    if state.applied.blur then
        ClearTimecycleModifier()
        state.applied.blur = nil
    end
end

local function clearSteer()
    if state.applied.steerVeh then
        if DoesEntityExist(state.applied.steerVeh) then SetVehicleSteerBias(state.applied.steerVeh, 0.0) end
        state.applied.steerVeh = nil
    end
end

--- Undoes everything this file changed (profile cleared, player down, character unloaded).
function E.ClearAll()
    local ped = PlayerPedId()
    clearClipset(ped)
    clearShake()
    clearBlur()
    clearSteer()
    if state.applied.moveRate then SetPedMoveRateOverride(ped, 1.0); state.applied.moveRate = nil end
end

-- One slow pass (every 250 ms while the loop runs): effects that are set once and kept.
function E.SlowStep(plan, now)
    local ped = PlayerPedId()
    local pid = PlayerId()
    -- limp clipset: set once, kept while walk >= 1
    if plan.clipset then
        if state.applied.clipset ~= plan.clipset then
            RequestAnimSet(plan.clipset)
            if HasAnimSetLoaded(plan.clipset) then
                SetPedMovementClipset(ped, plan.clipset, 0.25)
                state.applied.clipset = plan.clipset
            end
        end
    else
        clearClipset(ped)
    end
    if not plan.moveRate and state.applied.moveRate then SetPedMoveRateOverride(ped, 1.0); state.applied.moveRate = nil end
    -- hand shake only while aiming
    if plan.aimShake and IsPlayerFreeAiming(pid) then
        if state.applied.shake ~= plan.aimShake then
            ShakeGameplayCam('HAND_SHAKE', plan.aimShake)
            state.applied.shake = plan.aimShake
        end
    else
        clearShake()
    end
    -- blurred vision
    if plan.blur then
        if state.applied.blur ~= plan.blur then
            SetTimecycleModifier(E.BlurModifier)
            SetTimecycleModifierStrength(plan.blur)
            state.applied.blur = plan.blur
        end
    else
        clearBlur()
    end
    -- stamina drains faster while sprinting
    if plan.staminaDrain and IsPedSprinting(ped) then
        local s = GetPlayerStamina(pid)
        if s and s > 0 then SetPlayerStamina(pid, math.max(0.0, s - plan.staminaDrain)) end
    end
    -- pain pulses
    if plan.painEvery and now >= state.nextPain then
        if state.nextPain > 0 then AnimpostfxPlay('FocusOut', 900, false) end
        state.nextPain = now + plan.painEvery
    elseif not plan.painEvery then
        state.nextPain = 0
    end
    -- driving
    local veh = GetVehiclePedIsIn(ped, false)
    local driver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
    state.stopDriving = false
    if plan.noDrive then
        local trying = GetVehiclePedIsTryingToEnter(ped)
        if trying ~= 0 and GetSeatPedIsTryingToEnter(ped) == -1 then
            ClearPedTasks(ped)
            notify('You are not fit to drive.')
        elseif driver then
            -- never thrown out at speed: the car is brought to a stop first, then the seat is left
            if GetEntitySpeed(veh) < 1.0 then
                TaskLeaveVehicle(ped, veh, 0)
                notify('You are not fit to drive.')
            else
                state.stopDriving = true
            end
        end
    end
    if plan.wobble and driver and GetEntitySpeed(veh) > 5.0 then
        if now >= state.nextWobble then
            state.nextWobble = now + E.WobbleEvery
            local bias = (math.random() < 0.5 and -1 or 1) * 0.12
            SetVehicleSteerBias(veh, bias)
            state.applied.steerVeh = veh
            state.wobbleUntil = now + 400
        elseif state.applied.steerVeh and now >= (state.wobbleUntil or 0) then
            clearSteer()
        end
    else
        clearSteer()
    end
end

-- One frame: input blocking only.
function E.FrameStep(plan)
    local ped = PlayerPedId()
    if plan.blockSprint then DisableControlAction(0, 21, true) end   -- sprint
    if plan.blockJump then DisableControlAction(0, 22, true) end     -- jump / climb
    if plan.moveRate then SetPedMoveRateOverride(ped, plan.moveRate); state.applied.moveRate = plan.moveRate end
    if state.stopDriving then
        DisableControlAction(0, 71, true)                             -- accelerate
    end
end

--- One loop iteration. Returns the ms to wait, or nil when the loop must end.
function E.Step(now)
    local profile = state.profile
    if not profile or E.IsEmpty(profile) then
        E.ClearAll()
        return nil
    end
    if isDown() then
        -- the down/death animation owns the ped; effects return when the player is up again
        E.ClearAll()
        state.nextSlow = 0
        return 500
    end
    local plan = state.plan or E.Plan(profile)
    if now >= state.nextSlow then
        state.nextSlow = now + E.SlowMs
        E.SlowStep(plan, now)
    end
    if plan.needsFrame or state.stopDriving then
        E.FrameStep(plan)
        return 0
    end
    return E.SlowMs
end

--- Starts the loop thread unless one runs. Each thread carries a generation number: a thread from
--- before an empty profile stops even if a new loop started before it woke up (never two loops).
function E.StartLoop()
    if state.running then return false end
    state.running = true
    state.nextSlow = 0
    state.gen = (state.gen or 0) + 1
    local gen = state.gen
    CreateThread(function()
        while state.running and state.gen == gen do
            local waitMs = E.Step(GetGameTimer())
            if waitMs == nil then break end
            Wait(waitMs)
        end
        if state.gen == gen then state.running = false end
    end)
    return true
end

--- Applies a pushed profile. Returns true when it was applied (a stale version is ignored).
function E.Apply(profile, version)
    version = tonumber(version) or 0
    if version <= state.version then return false end
    state.version = version
    local clean = E.Clean(profile)
    local kinds = {}
    if type(profile) == 'table' and type(profile.restrictions) == 'table' then
        for _, k in ipairs(profile.restrictions) do
            if type(k) == 'string' and #k <= 32 then kinds[k] = true end
        end
    end
    if kinds.no_drive and not state.restrictions.no_drive then notify('Doctor\'s orders: you must not drive for now.', 'primary') end
    state.restrictions = kinds
    state.profile = clean
    state.plan = E.Plan(clean)
    if state.plan.empty then
        -- nothing to apply: no thread at all; undo what an earlier profile set
        state.running = false
        E.ClearAll()
        return true
    end
    E.StartLoop()
    return true
end

--- Forgets everything (character unloaded): the next character starts from its own push.
function E.Reset()
    state.running = false
    state.profile, state.plan = nil, nil
    state.restrictions = {}
    state.version = 0
    E.ClearAll()
end

--- Read-only copy of the current profile and restriction kinds (other client scripts, HUD).
function E.Current()
    local out = { restrictions = {} }
    for _, ch in ipairs(E.Channels) do out[ch] = state.profile and state.profile[ch] or 0 end
    for k in pairs(state.restrictions) do out.restrictions[#out.restrictions + 1] = k end
    table.sort(out.restrictions)
    return out
end

RegisterNetEvent('pf-ambulancejob:client:Effects', function(profile, version)
    E.Apply(profile, version)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    E.Reset()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then E.ClearAll() end
end)

