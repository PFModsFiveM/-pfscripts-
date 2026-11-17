-- EMS equipment presentation (batch 17D). The server (server/ems/equipment.lua) owns every prop,
-- who lies on it, who pushes it and who is loaded in a rig; this file only:
--   * turns a radial or target choice into pf-ambulancejob:server:Equipment(action, hints), where
--     the hints are net ids and a server id the server checks again (never a position);
--   * plays what the replicated state bags say: the patient attaches their own ped to the prop
--     (`pf:onStretcher` on their player), the pusher attaches the prop to their ped (`pusher` in the
--     prop's `pf:stretcher`). Attachments and animations sync to everyone, late joiners included;
--   * repairs an interrupted attachment or animation while it lasts (the only loops run while this
--     player is on equipment or pushing it).

local function C() return Config.EMS or {} end
local function cfgFor(kind) return kind == 'wheelchair' and (C().Wheelchairs or {}) or (C().Stretchers or {}) end

local myId = GetPlayerServerId(PlayerId())
local onNet, onKind = nil, nil       -- the prop this player lies / sits on
local pushNet, pushKind = nil, nil   -- the prop this player pushes

local function send(action, args)
    TriggerServerEvent('pf-ambulancejob:server:Equipment', action, args or {})
end

local function loadDict(dict)
    if not dict or HasAnimDictLoaded(dict) then return dict ~= nil end
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 100 do tries = tries + 1 Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function entityOf(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return 0 end
    return NetworkGetEntityFromNetworkId(net)
end

local function bagOf(entity)
    if not entity or entity == 0 then return nil end
    return Entity(entity).state['pf:stretcher']
end

local function amDown()
    local d = LocalPlayer.state['pf:down']
    return d ~= nil and d ~= false
end

-- ── hints for the server (nearest things) ──────────────────────────────────────────────────────

local function nearestEquipment(kinds, range)
    local me = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, obj in ipairs(GetGamePool('CObject')) do
        local d = #(GetEntityCoords(obj) - me)
        if d <= range and (not bestD or d < bestD) then
            local bag = bagOf(obj)
            local medbag = Entity(obj).state['pf:medbag']
            local kind = (bag and bag.kind) or (medbag and 'medbag') or nil
            if kind and kinds[kind] and NetworkGetEntityIsNetworked(obj) then best, bestD = obj, d end
        end
    end
    return best and NetworkGetNetworkIdFromEntity(best) or nil, best
end

local rigHashes
local function nearestRig(range)
    if not rigHashes then
        rigHashes = {}
        for model in pairs(C().Rigs or {}) do rigHashes[GetHashKey(model)] = true end
    end
    local me = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if rigHashes[GetEntityModel(veh)] then
            local d = #(GetEntityCoords(veh) - me)
            if d <= range and (not bestD or d < bestD) and NetworkGetEntityIsNetworked(veh) then best, bestD = veh, d end
        end
    end
    return best and NetworkGetNetworkIdFromEntity(best) or nil
end

local function nearestPlayer(range)
    local ped = PlayerPedId()
    local me = GetEntityCoords(ped)
    local best, bestD
    for _, pid in ipairs(GetActivePlayers()) do
        local other = GetPlayerPed(pid)
        if other ~= ped then
            local d = #(GetEntityCoords(other) - me)
            if d <= range and (not bestD or d < bestD) then best, bestD = GetPlayerServerId(pid), d end
        end
    end
    return best
end

local STRETCHER, WHEELCHAIR = { stretcher = true }, { wheelchair = true }
local BOTH, MEDBAG = { stretcher = true, wheelchair = true }, { medbag = true }

--- Builds the hints for one action and sends it. entityNet (optional) comes from a target option.
local function request(action, entityNet)
    local args = {}
    if action == 'spawn_stretcher' or action == 'place_medbag' or action == 'unload' then
        args.rig = nearestRig(8.0)
    elseif action == 'spawn_wheelchair' then
        args.rig = nearestRig(8.0) -- none: the server looks for a hospital point
    elseif action == 'place_patient' or action == 'seat' then
        args.entity = entityNet or nearestEquipment(action == 'seat' and WHEELCHAIR or STRETCHER, 3.0)
        args.target = nearestPlayer(2.5)
    elseif action == 'load' then
        args.entity = entityNet or pushNet or nearestEquipment(STRETCHER, 3.0)
        args.rig = nearestRig(8.0)
    elseif action == 'pickup_medbag' or action == 'open_medbag' then
        args.entity = entityNet or nearestEquipment(MEDBAG, 3.0)
    elseif action == 'take_patient' or action == 'fold' then
        args.entity = entityNet or nearestEquipment(STRETCHER, 3.0)
    elseif action == 'unseat' then
        args.entity = entityNet or nearestEquipment(WHEELCHAIR, 3.0)
    elseif action == 'push' then
        if pushNet then action, args.entity = 'release', pushNet
        else args.entity = entityNet or nearestEquipment(BOTH, 3.0) end
    elseif action == 'release' then
        args.entity = entityNet or pushNet
    elseif action == 'return' then
        args.entity = entityNet or pushNet or nearestEquipment(BOTH, 3.0)
        args.rig = nearestRig(8.0)
    end
    send(action, args)
end

-- Radial entries (pfm-radialmenu config: { equipment = 'spawn_stretcher' }) and other scripts
-- (TriggerEvent('pf-ambulancejob:client:Equipment', { action = 'spawn_stretcher' }) or the bare name).
AddEventHandler('pf-ambulancejob:client:Equipment', function(data)
    local action = data
    if type(data) == 'table' then action = data.equipment or data.action end
    if type(action) ~= 'string' then return end
    request(action, type(data) == 'table' and tonumber(data.entity) or nil)
end)

-- ── the patient's own ped ──────────────────────────────────────────────────────────────────────

local function attachSelf(net, kind)
    local ped = PlayerPedId()
    local obj = entityOf(net)
    if obj == 0 then return false end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then TaskLeaveVehicle(ped, veh, 16) end
    local o = cfgFor(kind).PatientOffset or {}
    if not IsEntityAttachedToEntity(ped, obj) then
        AttachEntityToEntity(ped, obj, 0, o.x or 0.0, o.y or 0.0, o.z or 1.0, o.rx or 0.0, o.ry or 0.0, o.rz or 180.0, false, false, false, false, 2, true)
    end
    -- a down patient keeps the down animation (dead.lua / laststand.lua play it); the lying pose suits a stretcher
    local a = cfgFor(kind).PatientAnim
    if a and not amDown() and not IsEntityPlayingAnim(ped, a.dict, a.name, 3) and loadDict(a.dict) then
        TaskPlayAnim(ped, a.dict, a.name, 8.0, 8.0, -1, a.flag or 1, 0, false, false, false)
    end
    return true
end

local function detachSelf()
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    local a = onKind and cfgFor(onKind).PatientAnim
    if a and IsEntityPlayingAnim(ped, a.dict, a.name, 3) then StopAnimTask(ped, a.dict, a.name, 2.0) end
    onNet, onKind = nil, nil
end

local function startPatient(net, kind)
    if not net then return end
    if onNet == net then return end
    onNet, onKind = net, kind or 'stretcher'
    CreateThread(function()
        -- the prop may not exist on this client yet (just spawned, streaming in)
        local tries = 0
        while onNet == net and not attachSelf(net, onKind) and tries < 50 do tries = tries + 1 Wait(100) end
        while onNet == net do
            Wait(500)
            if onNet ~= net then break end
            attachSelf(net, onKind) -- re-attach / re-play after an interruption (ragdoll, other script)
        end
    end)
end

local function onMyBag(value)
    if value then
        local bag = bagOf(entityOf(value))
        startPatient(value, bag and bag.kind or onKind)
    elseif onNet then
        detachSelf()
    end
end

AddStateBagChangeHandler('pf:onStretcher', ('player:%s'):format(myId), function(_, _, value)
    onMyBag(value)
end)

RegisterNetEvent('pf-ambulancejob:client:EquipmentPlaced', function(net, kind)
    if type(net) ~= 'number' then return end
    startPatient(net, kind == 'wheelchair' and 'wheelchair' or 'stretcher')
end)

RegisterNetEvent('pf-ambulancejob:client:EquipmentReleased', function()
    detachSelf()
end)

-- ── pushing ────────────────────────────────────────────────────────────────────────────────────

local function stopPushLocal()
    local obj = entityOf(pushNet)
    local ped = PlayerPedId()
    if obj ~= 0 and IsEntityAttachedToEntity(obj, ped) and NetworkHasControlOfEntity(obj) then DetachEntity(obj, true, false) end
    local a = pushKind and cfgFor(pushKind).PushAnim
    if a and IsEntityPlayingAnim(ped, a.dict, a.name, 3) then StopAnimTask(ped, a.dict, a.name, 2.0) end
    pushNet, pushKind = nil, nil
end

local function attachPush(net, kind)
    local obj = entityOf(net)
    if obj == 0 then return false end
    local ped = PlayerPedId()
    if not NetworkHasControlOfEntity(obj) then
        NetworkRequestControlOfEntity(obj)
        return false
    end
    if not IsEntityAttachedToEntity(obj, ped) then
        local o = cfgFor(kind).PushOffset or {}
        AttachEntityToEntity(obj, ped, 0, o.x or 0.0, o.y or 1.2, o.z or -0.95, o.rx or 0.0, o.ry or 0.0, o.rz or 180.0, false, false, false, false, 2, true)
    end
    local a = cfgFor(kind).PushAnim
    if a and not IsEntityPlayingAnim(ped, a.dict, a.name, 3) and loadDict(a.dict) then
        TaskPlayAnim(ped, a.dict, a.name, 8.0, 8.0, -1, a.flag or 50, 0, false, false, false)
    end
    return true
end

local function startPush(net, kind)
    if pushNet == net then return end
    pushNet, pushKind = net, kind
    CreateThread(function()
        local nextCheck = 0
        while pushNet == net do
            local ped = PlayerPedId()
            -- no sprinting, jumping, fighting or entering vehicles while pushing
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            if IsPedRagdoll(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
                send('release', { entity = net })
                stopPushLocal()
                break
            end
            if GetGameTimer() >= nextCheck then
                nextCheck = GetGameTimer() + 500
                attachPush(net, kind) -- also after the prop migrated to another client
            end
            Wait(0)
        end
    end)
end

AddStateBagChangeHandler('pf:stretcher', nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 then return end
    local net = NetworkGetNetworkIdFromEntity(entity)
    if type(value) == 'table' and value.pusher == myId then
        startPush(net, value.kind)
    elseif pushNet == net then
        stopPushLocal()
    end
end)

RegisterNetEvent('pf-ambulancejob:client:EquipmentStopPush', function(net)
    if pushNet and (net == nil or net == pushNet) then stopPushLocal() end
end)

-- One key (default G, rebindable): get off by yourself, or stop pushing.
RegisterCommand('pf_equipment', function()
    if pushNet then
        send('release', { entity = pushNet })
    elseif onNet and not amDown() then -- G is also the down player's call-for-help key
        send(onKind == 'wheelchair' and 'unseat' or 'take_patient', { entity = onNet })
    end
end, false)
RegisterKeyMapping('pf_equipment', 'EMS equipment: get off / stop pushing', 'keyboard', 'G')

-- ── target options on the props ────────────────────────────────────────────────────────────────

CreateThread(function()
    if GetResourceState('pfm-target') ~= 'started' then return end
    local jobs = {}
    for job in pairs(C().Jobs or { ambulance = true }) do jobs[job] = 0 end
    -- only props the server spawned carry a bag (the same models also stand in hospitals)
    local function ours(entity)
        return bagOf(entity) ~= nil or Entity(entity).state['pf:medbag'] ~= nil
    end
    local function opt(label, icon, action, extra)
        return {
            icon = icon, label = label, job = jobs,
            action = function(entity) request(action, NetworkGetNetworkIdFromEntity(entity)) end,
            canInteract = function(entity) return ours(entity) and (not extra or extra(entity) and true or false) end,
        }
    end
    local function bag(entity) return bagOf(entity) or {} end
    local stretcherOpts = {
        opt('Push / stop', 'fas fa-hand', 'push'),
        opt('Place patient', 'fas fa-bed-pulse', 'place_patient', function(e) return not bag(e).patient and not bag(e).folded end),
        opt('Take patient off', 'fas fa-person-walking', 'take_patient', function(e) return bag(e).patient end),
        opt('Load into ambulance', 'fas fa-truck-medical', 'load', function(e) return bag(e).patient end),
        opt('Fold / unfold', 'fas fa-compress', 'fold', function(e) return not bag(e).patient end),
        opt('Put back in ambulance', 'fas fa-rotate-left', 'return', function(e) return not bag(e).patient end),
    }
    local wheelchairOpts = {
        opt('Push / stop', 'fas fa-hand', 'push'),
        opt('Seat patient', 'fas fa-wheelchair', 'seat', function(e) return not bag(e).patient end),
        opt('Help patient up', 'fas fa-person-walking', 'unseat', function(e) return bag(e).patient end),
        opt('Put away', 'fas fa-rotate-left', 'return', function(e) return not bag(e).patient end),
    }
    local medbagOpts = {
        opt('Open medbag', 'fas fa-kit-medical', 'open_medbag'),
        opt('Pick up medbag', 'fas fa-hand', 'pickup_medbag'),
    }
    exports['pfm-target']:AddTargetModel({ (C().Stretchers or {}).Model or 'v_med_emptybed' }, { options = stretcherOpts, distance = 2.5 })
    exports['pfm-target']:AddTargetModel({ (C().Wheelchairs or {}).Model or 'prop_wheelchair_01' }, { options = wheelchairOpts, distance = 2.5 })
    exports['pfm-target']:AddTargetModel({ (C().Medbags or {}).Model or 'xm_prop_x17_bag_med_01a' }, { options = medbagOpts, distance = 2.5 })
end)

-- ── lifecycle ──────────────────────────────────────────────────────────────────────────────────

-- this resource restarted while the player was on equipment: pick the state up again
CreateThread(function()
    Wait(1000)
    local v = LocalPlayer.state['pf:onStretcher']
    if v then onMyBag(v) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if pushNet then stopPushLocal() end
    if onNet then detachSelf() end
end)
