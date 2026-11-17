-- EMS equipment (architecture 4.6, batch 17D): stretchers, wheelchairs, medbags and loading a patient
-- into an ambulance ("rig").
--
-- The server owns all of it:
--   * every prop is created here (CreateObjectNoOffset) at a position computed from server
--     positions (the rig's coords and heading, the medic's ped); a client never sends a position;
--   * who lies on what and who pushes what lives in this file's memory and is mirrored to the
--     replicated state bags the clients render from: entity `pf:stretcher` = { kind, patient, pusher,
--     folded, rig } (late joiners get it with the entity), player `pf:onStretcher` = netId | false,
--     player `pf:inRig` = rig netId | false (added: a patient loaded in a rig), vehicle `pf:rig`;
--   * loading seats the patient with the server RPC native SetPedIntoVehicle; unloading moves them
--     out with SetEntityCoords; the client only plays the attachment and the animation;
--   * the 16A movement check (downstate.lua) treats `pf:onStretcher` like an escort, and a
--     patient in a rig is in a vehicle, so a down patient being moved is not an anomaly.
-- Safety: a patient is released at their last server position when they, their pusher, the prop or
-- the rig disappear (playerDropped, logout, entityRemoved, the 1 s safety pass) and when this
-- resource stops; props whose rig is gone are deleted.
--
-- Net event: pf-ambulancejob:server:Equipment(action, args) with action in
--   spawn_stretcher, place_patient, take_patient, push, release, load, unload, fold, return,
--   spawn_wheelchair, seat, unseat, place_medbag, pickup_medbag, open_medbag (added: opens the stash)
-- args: { entity = equipment netId, rig = vehicle netId, target = server id } (hints the server
-- re-checks). The result goes back as pf-ambulancejob:client:EquipmentResult(action, result).

PFEms = PFEms or {}
local E = PFEms

local function C() return Config.EMS or {} end
local function S() return C().Stretchers or {} end
local function W() return C().Wheelchairs or {} end
local function B() return C().Medbags or {} end
local function now() return os.time() end
local function num(v, d)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
    return v
end
local function int(v, lo, hi)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
    v = math.tointeger(v)
    if not v or v < lo or v > hi then return nil end
    return v
end

local MESSAGES = {
    bad_args = 'Invalid request.',
    no_permission = 'You cannot do that.',
    not_on_duty = 'You must be on duty as EMS.',
    too_far = 'You are too far away.',
    not_found = 'That is no longer there.',
    invalid_state = 'That cannot be done right now.',
    conflict = 'That is already in use.',
    busy = 'Try again in a moment.',
    rate_limited = 'Slow down.',
    offline = 'That person is not here.',
}
local function fail(code, message) return { ok = false, error = code, message = message or MESSAGES[code] or code } end
local function done(t) t = t or {} t.ok = true return t end

-- ── state ──────────────────────────────────────────────────────────────────────────────────────
local items = {}       -- [id] = { id, kind, entity, net, rig = veh|nil, owner, patient, patientCid, pusher, folded, stash, lastPos, farPush, farPatient }
local byEntity = {}    -- [entity] = id
local rigs = {}        -- [veh] = { veh, net, plate, lastPos, loaded = { patient, cid, seat, reseats, out } }
local patientOf = {}   -- [src] = item id they lie / sit on
local pusherOf = {}    -- [src] = item id they push
local rigOfPatient = {} -- [src] = veh they are loaded in
local rate = {}        -- [src] = { t, n }
local seq = 0
E.stats = { spawned = 0, released = 0, orphaned = 0 }

-- ── natives and helpers ────────────────────────────────────────────────────────────────────────

--- Calls a native that may be missing (older server builds, the test harness) without failing.
local function native(name, ...)
    local f = _G[name]
    if f == nil then return nil end
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function alive(e)
    if not e or e == 0 then return false end
    return DoesEntityExist(e) == true
end

local function getPlayer(src)
    if not src then return nil end
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(P) == 'table' and type(P.PlayerData) == 'table' then return P end
    return nil
end

local function pedOf(src)
    local ped = src and GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return ped
end

local function posOf(src)
    local ped = pedOf(src)
    return ped and GetEntityCoords(ped) or nil
end

local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- GTA headings turn counter-clockwise from north: forward is (-sin, cos), right is (cos, sin)
local function fwd(h)
    local r = math.rad(num(h, 0))
    return -math.sin(r), math.cos(r)
end
local function offset(pos, h, ahead, right, up)
    local fx, fy = fwd(h)
    return vector3(pos.x + fx * ahead + fy * right, pos.y + fy * ahead - fx * right, pos.z + (up or 0))
end

local function inVehicle(src)
    local ped = pedOf(src)
    return ped ~= nil and GetVehiclePedIsIn(ped, false) ~= 0
end

local function isMedic(P)
    local job = P and P.PlayerData and P.PlayerData.job
    return type(job) == 'table' and (C().Jobs or { ambulance = true })[job.name] == true and job.onduty == true
end
local function medicError(P)
    local job = P and P.PlayerData and P.PlayerData.job
    if type(job) == 'table' and (C().Jobs or { ambulance = true })[job.name] == true then return fail('not_on_duty') end
    return fail('no_permission')
end

local function meta(src)
    local P = getPlayer(src)
    return (P and P.PlayerData.metadata) or {}
end

--- Down by the server's own state (16A), with the metadata mirror as a fallback.
local function isDown(src)
    if PFMed and PFMed.Down and PFMed.Down.IsDown then
        local ok, down = pcall(PFMed.Down.IsDown, src)
        if ok then return down == true end
    end
    local m = meta(src)
    return m.isdead == true or m.inlaststand == true
end
local function isCuffed(src) return meta(src).ishandcuffed == true end
local function escorted(src)
    local ok, v = pcall(function() return Player(src).state['pf:escort'] end)
    return ok and v ~= nil and v ~= false
end

local function setPlayerBag(src, key, value)
    pcall(function() Player(src).state:set(key, value, true) end)
end
local function setEntityBag(e, key, value)
    if not alive(e) then return end
    pcall(function() Entity(e).state:set(key, value, true) end)
end

local function moveGrace(src, seconds)
    if PFMed and PFMed.Down and PFMed.Down.MoveGrace then pcall(PFMed.Down.MoveGrace, src, seconds or 6) end
end
--- A down patient taken off equipment gets the down state again so their client re-plays it.
local function resendDown(src)
    if PFMed and PFMed.Down and PFMed.Down.SendState and isDown(src) then pcall(PFMed.Down.SendState, src, 'equipment') end
end

local function audit(cid, action, actorSrc, detail)
    if not cid or not (PFMed and PFMed.Store and PFMed.Store.Audit) then return end
    local actor = { kind = 'system', label = 'ems equipment' }
    if actorSrc then
        local P = getPlayer(actorSrc)
        actor = { src = actorSrc, cid = P and P.PlayerData.citizenid or nil, job = P and P.PlayerData.job and P.PlayerData.job.name or nil }
    end
    pcall(PFMed.Store.Audit, cid, ('equip_' .. action):sub(1, 32), actor, detail or {})
end

local function cidOf(src)
    local P = getPlayer(src)
    return P and P.PlayerData.citizenid or nil
end

local function limited(src)
    local t, r = now(), rate[src]
    if not r or r.t ~= t then rate[src] = { t = t, n = 1 } return false end
    if r.n >= num(C().RatePerSecond, 2) then return true end
    r.n = r.n + 1
    return false
end

-- ── rigs ───────────────────────────────────────────────────────────────────────────────────────

local function h32(v)
    v = math.tointeger(tonumber(v) or 0) or 0
    return v & 0xFFFFFFFF
end
local rigByHash
local function rigCfg(veh)
    if not rigByHash then
        rigByHash = {}
        for model, cfg in pairs(C().Rigs or {}) do rigByHash[h32(GetHashKey(model))] = cfg end
    end
    if GetEntityType and native('GetEntityType', veh) ~= 2 then return nil end
    return rigByHash[h32(GetEntityModel(veh))]
end

local function plateId(veh, net)
    local plate = tostring(native('GetVehicleNumberPlateText', veh) or ''):gsub('[^%w]', ''):upper():sub(1, 8)
    if plate == '' then plate = 'NET' .. tostring(net) end
    return plate
end

local function ensureRig(veh)
    local rig = rigs[veh]
    if not rig then
        local net = NetworkGetNetworkIdFromEntity(veh)
        rig = { veh = veh, net = net, plate = plateId(veh, net), lastPos = GetEntityCoords(veh) }
        rigs[veh] = rig
    end
    return rig
end

local function countFor(pred)
    local n = 0
    for _, it in pairs(items) do if pred(it) then n = n + 1 end end
    return n
end
local function rigCount(veh, kind)
    local n = countFor(function(it) return it.rig == veh and it.kind == kind end)
    local rig = rigs[veh]
    if kind == 'stretcher' and rig and rig.loaded then n = n + 1 end -- the loaded stretcher is inside
    return n
end

local function pushRigBag(rig)
    if not rig then return end
    local out = rigCount(rig.veh, 'stretcher') - (rig.loaded and 1 or 0)
    setEntityBag(rig.veh, 'pf:rig', { stretchersOut = out, loaded = rig.loaded and rig.loaded.patient or false })
end

--- The rig's rear doors (server position), its heading and its config.
local function rearOf(veh, cfg)
    local pos, h = GetEntityCoords(veh), num(native('GetEntityHeading', veh), 0)
    return offset(pos, h, num(cfg.rear, -3.6), 0), h, pos
end

local function freeSeat(veh, cfg)
    for _, seat in ipairs(cfg.seats or { 1, 2 }) do
        if GetPedInVehicleSeat(veh, seat) == 0 then return seat end
    end
    return nil
end

-- ── equipment props ────────────────────────────────────────────────────────────────────────────

local function pushBag(it)
    if it.kind == 'medbag' then
        setEntityBag(it.entity, 'pf:medbag', { id = it.id, rig = (it.rig and rigs[it.rig] and rigs[it.rig].net) or false })
        return
    end
    setEntityBag(it.entity, 'pf:stretcher', {
        kind = it.kind,
        patient = it.patient or false,
        pusher = it.pusher or false,
        folded = it.folded == true,
        rig = (it.rig and rigs[it.rig] and rigs[it.rig].net) or false,
    })
end

local function spawnProp(model, pos, heading)
    local obj = CreateObjectNoOffset(GetHashKey(model), pos.x, pos.y, pos.z, true, true, false)
    if not obj or obj == 0 then return nil end
    native('SetEntityHeading', obj, heading or 0.0)
    native('FreezeEntityPosition', obj, true)
    native('SetEntityOrphanMode', obj, 2) -- keep it when its network owner leaves; this file deletes it
    return obj
end

local function newItem(kind, obj, veh, owner)
    seq = seq + 1
    local it = {
        id = seq, kind = kind, entity = obj, net = NetworkGetNetworkIdFromEntity(obj), rig = veh, owner = owner,
        patient = false, pusher = false, folded = false, lastPos = GetEntityCoords(obj), farPush = 0, farPatient = 0,
    }
    items[it.id], byEntity[obj] = it, it.id
    E.stats.spawned = E.stats.spawned + 1
    pushBag(it)
    return it
end

local function propCount() return countFor(function() return true end) end

--- Stops pushing. With opts.clampTo (the pusher's server position) a stretcher the pusher's client
--- left somewhere else is put back beside the pusher.
function E.StopPushing(it, opts)
    opts = opts or {}
    local p = it.pusher
    if not p then return false end
    it.pusher, it.farPush = false, 0
    if pusherOf[p] == it.id then pusherOf[p] = nil end
    if alive(it.entity) then
        local pos = GetEntityCoords(it.entity)
        if opts.clampTo and dist(pos, opts.clampTo) > num(S().PusherMaxDistance, 4.0) then
            pos = vector3(opts.clampTo.x, opts.clampTo.y, opts.clampTo.z - 0.95)
            native('SetEntityCoords', it.entity, pos.x, pos.y, pos.z, false, false, false, false)
        end
        native('FreezeEntityPosition', it.entity, true)
        it.lastPos = pos
        pushBag(it)
    end
    if getPlayer(p) then TriggerClientEvent('pf-ambulancejob:client:EquipmentStopPush', p, it.net) end
    return true
end

--- Takes the patient off. They are put beside their own last server position (the patient's ped,
--- attached to the stretcher, is where the stretcher is); opts.pos overrides it.
function E.ReleasePatient(it, reason, actorSrc, opts)
    opts = opts or {}
    local p = it.patient
    if not p then return false end
    local cid = it.patientCid or cidOf(p)
    it.patient, it.patientCid, it.farPatient = false, nil, 0
    if patientOf[p] == it.id then patientOf[p] = nil end
    setPlayerBag(p, 'pf:onStretcher', false)
    pushBag(it)
    local ped = pedOf(p)
    if ped then
        local at = opts.pos or GetEntityCoords(ped)
        local h = alive(it.entity) and num(native('GetEntityHeading', it.entity), 0) or 0
        local spot = offset(at, h, 0, num(opts.side, 0.9), opts.up or 0)
        moveGrace(p, 6)
        native('SetEntityCoords', ped, spot.x, spot.y, spot.z, false, false, false, false)
        TriggerClientEvent('pf-ambulancejob:client:EquipmentReleased', p, it.net, reason)
        resendDown(p)
    end
    E.stats.released = E.stats.released + 1
    audit(cid, 'release', actorSrc, { reason = reason, kind = it.kind })
    return true
end

--- Forgets a prop (and deletes it when deleteProp). Its patient and pusher must be cleared first.
function E.Forget(it, deleteProp)
    items[it.id] = nil
    if byEntity[it.entity] == it.id then byEntity[it.entity] = nil end
    if it.pusher and pusherOf[it.pusher] == it.id then pusherOf[it.pusher] = nil end
    if it.patient and patientOf[it.patient] == it.id then patientOf[it.patient] = nil end
    if deleteProp and alive(it.entity) then DeleteEntity(it.entity) end
    if it.rig then pushRigBag(rigs[it.rig]) end
end

--- Clears a loaded patient from a rig. opts.pos puts them there (the rig is gone).
local function clearLoaded(rig, reason, opts)
    opts = opts or {}
    local l = rig.loaded
    if not l then return end
    rig.loaded = nil
    if rigOfPatient[l.patient] == rig.veh then rigOfPatient[l.patient] = nil end
    setPlayerBag(l.patient, 'pf:inRig', false)
    local ped = pedOf(l.patient)
    if ped and opts.pos then
        local spot = offset(opts.pos, 0, 0, 2.0, 0.5)
        moveGrace(l.patient, 6)
        native('SetEntityCoords', ped, spot.x, spot.y, spot.z, false, false, false, false)
        TriggerClientEvent('pf-ambulancejob:client:EquipmentReleased', l.patient, rig.net, reason)
        resendDown(l.patient)
    end
    E.stats.released = E.stats.released + 1
    audit(l.cid, 'unload_safety', nil, { reason = reason })
    pushRigBag(rig)
end

-- ── argument resolution (hints, re-checked) ────────────────────────────────────────────────────

local MAX_NET = 2147483647

local function itemArg(args, kinds)
    local net = int(args.entity or args.stretcher or args.wheelchair or args.medbag, 1, MAX_NET)
    if not net then return nil, fail('bad_args') end
    local e = NetworkGetEntityFromNetworkId(net)
    local id = e and byEntity[e]
    local it = id and items[id]
    if not it or it.net ~= net then return nil, fail('not_found') end
    if kinds and not kinds[it.kind] then return nil, fail('bad_args') end
    if not alive(it.entity) then
        E.OnEntityRemoved(it.entity)
        return nil, fail('not_found')
    end
    return it
end

local function rigArg(args)
    local net = int(args.rig, 1, MAX_NET)
    if not net then return nil, nil, fail('bad_args') end
    local veh = NetworkGetEntityFromNetworkId(net)
    if not alive(veh) then return nil, nil, fail('not_found') end
    local cfg = rigCfg(veh)
    if not cfg then return nil, nil, fail('bad_args', 'That is not an ambulance.') end
    return ensureRig(veh), cfg
end

local function targetArg(args, src)
    local t = int(args.target, 1, 65535)
    if not t or t == src then return nil, fail('bad_args') end
    if not pedOf(t) or not getPlayer(t) then return nil, fail('offline') end
    return t
end

-- ── actions ────────────────────────────────────────────────────────────────────────────────────

local H = {}

H.spawn_stretcher = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local rig, cfg, err = rigArg(args)
    if not rig then return err end
    if inVehicle(src) then return fail('invalid_state') end
    local rear, h = rearOf(rig.veh, cfg)
    if dist(posOf(src), rear) > num(C().RigRange, 4.0) then return fail('too_far', 'Stand at the rear doors of the ambulance.') end
    if rigCount(rig.veh, 'stretcher') >= num(S().PerRig, 1) then return fail('conflict', 'This ambulance\'s stretcher is already out.') end
    if propCount() >= num(C().MaxProps, 64) then return fail('busy') end
    local pos = offset(rear, h, -num(S().SpawnBehind, 1.2), 0, num(cfg.groundZ, -0.9))
    local obj = spawnProp(S().Model or 'v_med_emptybed', pos, h)
    if not obj then return fail('busy') end
    local it = newItem('stretcher', obj, rig.veh, src)
    pushRigBag(rig)
    return done({ id = it.id, net = it.net })
end

H.spawn_wheelchair = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    if inVehicle(src) then return fail('invalid_state') end
    if countFor(function(it) return it.kind == 'wheelchair' and it.owner == src end) >= num(W().MaxPerMedic, 2) then
        return fail('conflict', 'You already have wheelchairs out.')
    end
    if propCount() >= num(C().MaxProps, 64) then return fail('busy') end
    local me = posOf(src)
    local pos, h, veh
    if args.rig ~= nil then
        local rig, cfg, err = rigArg(args)
        if not rig then return err end
        local rear
        rear, h = rearOf(rig.veh, cfg)
        if dist(me, rear) > num(C().RigRange, 4.0) then return fail('too_far', 'Stand at the rear doors of the ambulance.') end
        if rigCount(rig.veh, 'wheelchair') >= num(W().PerRig, 1) then return fail('conflict', 'This ambulance\'s wheelchair is already out.') end
        pos, veh = offset(rear, h, -1.0, 0, num(cfg.groundZ, -0.9)), rig.veh
    else
        local near = false
        for _, pt in ipairs(W().Points or (Config.Locations and Config.Locations['checking']) or {}) do
            if dist(me, pt) <= num(W().PointRange, 3.0) then near = true break end
        end
        if not near then return fail('too_far', 'Take a wheelchair at an ambulance or a hospital desk.') end
        h = num(native('GetEntityHeading', pedOf(src)), 0)
        pos = offset(me, h, 1.0, 0, -0.98)
    end
    local obj = spawnProp(W().Model or 'prop_wheelchair_01', pos, h)
    if not obj then return fail('busy') end
    local it = newItem('wheelchair', obj, veh, src)
    if veh then pushRigBag(rigs[veh]) end
    return done({ id = it.id, net = it.net })
end

--- place_patient (stretcher) and seat (wheelchair).
local function placeOn(kind)
    return function(src, P, args)
        if not isMedic(P) then return medicError(P) end
        local it, err = itemArg(args, { [kind] = true })
        if not it then return err end
        local t, terr = targetArg(args, src)
        if not t then return terr end
        if it.patient then return fail('conflict') end
        if it.folded then return fail('invalid_state', 'Unfold the stretcher first.') end
        if patientOf[t] or rigOfPatient[t] or pusherOf[t] then return fail('conflict', 'That person is already on other equipment.') end
        local tp = posOf(t)
        if dist(posOf(src), tp) > num(C().TouchRange, 2.5) or dist(GetEntityCoords(it.entity), tp) > num(C().TouchRange, 2.5) then
            return fail('too_far')
        end
        if inVehicle(t) or inVehicle(src) then return fail('invalid_state') end
        if escorted(t) then return fail('conflict', 'That person is being escorted.') end
        local down = isDown(t)
        -- a down patient lies on a stretcher; a wheelchair needs someone who can sit up
        if kind == 'wheelchair' and down then return fail('invalid_state', 'Use a stretcher for that patient.') end
        if kind == 'stretcher' and not down and not isCuffed(t) and S().AllowConscious == false then return fail('no_permission') end
        it.patient, it.patientCid, it.farPatient = t, cidOf(t), 0
        patientOf[t] = it.id
        setPlayerBag(t, 'pf:onStretcher', it.net)
        pushBag(it)
        TriggerClientEvent('pf-ambulancejob:client:EquipmentPlaced', t, it.net, it.kind)
        audit(it.patientCid, 'place', src, { kind = it.kind, down = down })
        return done({ patient = t })
    end
end
H.place_patient = placeOn('stretcher')
H.seat = placeOn('wheelchair')

--- take_patient (stretcher) and unseat (wheelchair). The patient may get off by themselves unless
--- they are down or cuffed, so nobody can be carried off against their will.
local function takeOff(kind)
    return function(src, P, args)
        local it, err = itemArg(args, { [kind] = true })
        if not it then return err end
        if not it.patient then return fail('invalid_state', 'Nobody is on it.') end
        local self = it.patient == src
        if self then
            if isDown(src) or isCuffed(src) then return fail('no_permission', 'You cannot get off by yourself.') end
        else
            if patientOf[src] then return fail('invalid_state') end
            if not isMedic(P) then return medicError(P) end
            if dist(posOf(src), GetEntityCoords(it.entity)) > num(C().TouchRange, 2.5) then return fail('too_far') end
        end
        local p = it.patient
        E.ReleasePatient(it, self and 'self' or 'medic', src)
        return done({ patient = p })
    end
end
H.take_patient = takeOff('stretcher')
H.unseat = takeOff('wheelchair')

H.push = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local it, err = itemArg(args, { stretcher = true, wheelchair = true })
    if not it then return err end
    if it.pusher == src then return done({ duplicate = true }) end
    if it.pusher then return fail('conflict', 'Someone is already pushing it.') end
    if pusherOf[src] or patientOf[src] or inVehicle(src) then return fail('invalid_state') end
    if it.patient == src then return fail('invalid_state') end
    if dist(posOf(src), GetEntityCoords(it.entity)) > num(C().TouchRange, 2.5) then return fail('too_far') end
    it.pusher, it.farPush = src, 0
    pusherOf[src] = it.id
    native('FreezeEntityPosition', it.entity, false)
    pushBag(it)
    return done()
end

H.release = function(src, P, args)
    local it, err = itemArg(args, { stretcher = true, wheelchair = true })
    if not it then return err end
    if it.pusher ~= src then return fail('invalid_state', 'You are not pushing it.') end
    E.StopPushing(it, { clampTo = posOf(src) })
    return done()
end

H.load = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local it, err = itemArg(args, { stretcher = true })
    if not it then return err end
    local rig, cfg, rerr = rigArg(args)
    if not rig then return rerr end
    if not it.patient then return fail('invalid_state', 'Nobody is on the stretcher; put it back instead.') end
    if it.rig ~= rig.veh then return fail('conflict', 'This stretcher belongs to another ambulance.') end
    if rig.loaded then return fail('conflict', 'This ambulance already carries a patient.') end
    local rear = rearOf(rig.veh, cfg)
    local range = num(C().RigRange, 4.0)
    if dist(posOf(src), rear) > range or dist(GetEntityCoords(it.entity), rear) > range then return fail('too_far', 'Bring the stretcher to the rear doors.') end
    local seat = freeSeat(rig.veh, cfg)
    if not seat then return fail('conflict', 'No free seat in the back.') end
    local p = it.patient
    local ped = pedOf(p)
    if not ped then return fail('offline') end
    local cid = it.patientCid or cidOf(p)
    -- the stretcher goes in with the patient: the prop is removed, the rig remembers it is inside
    it.patient = false
    if patientOf[p] == it.id then patientOf[p] = nil end
    if it.pusher then E.StopPushing(it) end
    rig.loaded = { patient = p, cid = cid, seat = seat, reseats = 0, out = 0, at = now() }
    rigOfPatient[p] = rig.veh
    E.Forget(it, true)
    setPlayerBag(p, 'pf:onStretcher', false)
    setPlayerBag(p, 'pf:inRig', rig.net)
    moveGrace(p, 8)
    SetPedIntoVehicle(ped, rig.veh, seat)
    TriggerClientEvent('pf-ambulancejob:client:EquipmentLoaded', p, rig.net, seat)
    pushRigBag(rig)
    audit(cid, 'load', src, { plate = rig.plate, seat = seat })
    return done({ seat = seat })
end

H.unload = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local rig, cfg, err = rigArg(args)
    if not rig then return err end
    if not rig.loaded then return fail('invalid_state', 'Nobody is loaded in this ambulance.') end
    if inVehicle(src) then return fail('invalid_state') end
    local rear, h = rearOf(rig.veh, cfg)
    if dist(posOf(src), rear) > num(C().RigRange, 4.0) then return fail('too_far', 'Stand at the rear doors of the ambulance.') end
    local l = rig.loaded
    local ped = pedOf(l.patient)
    if not ped then
        clearLoaded(rig, 'patient_gone')
        return fail('offline')
    end
    if propCount() >= num(C().MaxProps, 64) then return fail('busy') end
    local pos = offset(rear, h, -num(S().SpawnBehind, 1.2), 0, num(cfg.groundZ, -0.9))
    local obj = spawnProp(S().Model or 'v_med_emptybed', pos, h)
    if not obj then return fail('busy') end
    rig.loaded = nil
    if rigOfPatient[l.patient] == rig.veh then rigOfPatient[l.patient] = nil end
    local it = newItem('stretcher', obj, rig.veh, src)
    it.patient, it.patientCid = l.patient, l.cid
    patientOf[l.patient] = it.id
    setPlayerBag(l.patient, 'pf:inRig', false)
    setPlayerBag(l.patient, 'pf:onStretcher', it.net)
    pushBag(it)
    moveGrace(l.patient, 8)
    -- out of the seat onto the stretcher; the patient's client attaches to the prop
    native('SetEntityCoords', ped, pos.x, pos.y, pos.z + 1.0, false, false, false, false)
    TriggerClientEvent('pf-ambulancejob:client:EquipmentPlaced', l.patient, it.net, 'stretcher')
    pushRigBag(rig)
    audit(l.cid, 'unload', src, { plate = rig.plate })
    return done({ net = it.net, patient = l.patient })
end

H.fold = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local it, err = itemArg(args, { stretcher = true })
    if not it then return err end
    if it.patient then return fail('invalid_state', 'Take the patient off first.') end
    if it.pusher and it.pusher ~= src then return fail('conflict') end
    if dist(posOf(src), GetEntityCoords(it.entity)) > num(C().TouchRange, 2.5) then return fail('too_far') end
    it.folded = not it.folded
    pushBag(it)
    return done({ folded = it.folded })
end

H['return'] = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local it, err = itemArg(args, { stretcher = true, wheelchair = true })
    if not it then return err end
    if it.patient then return fail('invalid_state', 'Take the patient off first.') end
    if it.pusher and it.pusher ~= src then return fail('conflict') end
    local here = GetEntityCoords(it.entity)
    if dist(posOf(src), here) > num(C().TouchRange, 2.5) then return fail('too_far') end
    if it.kind == 'stretcher' then
        -- a stretcher goes back into its own rig
        local veh = it.rig
        local cfg = veh and alive(veh) and rigCfg(veh)
        if not cfg then return fail('not_found') end
        local rear = rearOf(veh, cfg)
        if dist(here, rear) > num(C().RigRange, 4.0) then return fail('too_far', 'Bring the stretcher to its ambulance.') end
    end
    if it.pusher then E.StopPushing(it) end
    E.Forget(it, true)
    return done()
end

H.place_medbag = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local rig, cfg, err = rigArg(args)
    if not rig then return err end
    if inVehicle(src) then return fail('invalid_state') end
    local me = posOf(src)
    if dist(me, (rearOf(rig.veh, cfg))) > num(C().StockRange, 6.0) then return fail('too_far', 'Take the bag from the back of the ambulance.') end
    if rigCount(rig.veh, 'medbag') >= num(B().PerRig, 1) then return fail('conflict', 'This ambulance\'s medbag is already out.') end
    if propCount() >= num(C().MaxProps, 64) then return fail('busy') end
    local h = num(native('GetEntityHeading', pedOf(src)), 0)
    local pos = offset(me, h, 0.7, 0, -0.98)
    local obj = spawnProp(B().Model or 'xm_prop_x17_bag_med_01a', pos, h)
    if not obj then return fail('busy') end
    local it = newItem('medbag', obj, rig.veh, src)
    it.stash = 'pf_medbag_' .. rig.plate
    pcall(function() exports['pfm-inventory']:CreateInventory(it.stash, { label = B().Label or 'Medbag', maxweight = num(B().MaxWeight, 40000), slots = num(B().Slots, 20) }) end)
    pushBag(it)
    return done({ id = it.id, net = it.net, stash = it.stash })
end

H.pickup_medbag = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local it, err = itemArg(args, { medbag = true })
    if not it then return err end
    if dist(posOf(src), GetEntityCoords(it.entity)) > num(C().TouchRange, 2.5) then return fail('too_far') end
    E.Forget(it, true)
    return done()
end

H.open_medbag = function(src, P, args)
    if not isMedic(P) then return medicError(P) end
    local it, err = itemArg(args, { medbag = true })
    if not it then return err end
    if dist(posOf(src), GetEntityCoords(it.entity)) > num(C().TouchRange, 2.5) then return fail('too_far') end
    local ok = pcall(function()
        exports['pfm-inventory']:OpenInventory(src, it.stash, { label = B().Label or 'Medbag', maxweight = num(B().MaxWeight, 40000), slots = num(B().Slots, 20) })
    end)
    if not ok then return fail('busy') end
    return done({ stash = it.stash })
end

E.Actions = H

--- One equipment action for a player (the net event; specs call it directly).
function E.Handle(src, action, args)
    src = tonumber(src)
    if not src or src <= 0 then return fail('bad_args') end
    if type(action) ~= 'string' or not H[action] then return fail('bad_args') end
    if args ~= nil and type(args) ~= 'table' then return fail('bad_args') end
    if limited(src) then return fail('rate_limited') end
    local P = getPlayer(src)
    if not P or not pedOf(src) then return fail('offline') end
    args = args or {}
    -- a self-release is the patient's own action; everything else needs an able actor
    local selfRelease = (action == 'take_patient' or action == 'unseat') and patientOf[src] ~= nil
    if not selfRelease and (isDown(src) or isCuffed(src) or patientOf[src] or rigOfPatient[src]) then
        return fail('invalid_state')
    end
    return H[action](src, P, args)
end

RegisterNetEvent('pf-ambulancejob:server:Equipment', function(action, args)
    local src = source
    local res = E.Handle(src, action, args)
    if type(src) == 'number' and src > 0 then
        TriggerClientEvent('pf-ambulancejob:client:EquipmentResult', src, type(action) == 'string' and action:sub(1, 32) or '', res)
        if not res.ok and res.error ~= 'rate_limited' then TriggerClientEvent('QBCore:Notify', src, res.message, 'error') end
    end
end)

-- ── safety ─────────────────────────────────────────────────────────────────────────────────────

--- A prop or rig was removed (entityRemoved, or found missing by the safety pass).
function E.OnEntityRemoved(entity)
    local id = byEntity[entity]
    local it = id and items[id]
    if it then
        E.ReleasePatient(it, 'prop_removed')
        if it.pusher then
            local p = it.pusher
            it.pusher = false
            if pusherOf[p] == it.id then pusherOf[p] = nil end
            if getPlayer(p) then TriggerClientEvent('pf-ambulancejob:client:EquipmentStopPush', p, it.net) end
        end
        E.Forget(it, false)
        return true
    end
    if rigs[entity] then
        E.OnRigGone(entity)
        return true
    end
    return false
end

--- A rig is gone: its loaded patient is put down where it last was, and its props (orphans now)
--- are emptied and deleted.
function E.OnRigGone(veh)
    local rig = rigs[veh]
    if not rig then return end
    rigs[veh] = nil
    if rig.loaded then clearLoaded(rig, 'rig_removed', { pos = rig.lastPos }) end
    for _, it in pairs(items) do
        if it.rig == veh then
            E.ReleasePatient(it, 'rig_removed')
            if it.pusher then E.StopPushing(it) end
            it.rig = nil
            E.Forget(it, true)
            E.stats.orphaned = E.stats.orphaned + 1
        end
    end
end

--- A player left (drop or logout to the character menu).
function E.OnLeft(src)
    src = tonumber(src)
    if not src then return end
    local id = patientOf[src]
    if id and items[id] then E.ReleasePatient(items[id], 'patient_left') end
    patientOf[src] = nil
    local veh = rigOfPatient[src]
    if veh and rigs[veh] then clearLoaded(rigs[veh], 'patient_left') end
    rigOfPatient[src] = nil
    id = pusherOf[src]
    if id and items[id] then
        local it = items[id]
        E.ReleasePatient(it, 'pusher_left')
        E.StopPushing(it)
    end
    pusherOf[src] = nil
    -- wheelchairs and medbags the medic took out leave with them (a stretcher stays with its rig)
    for _, it in pairs(items) do
        if it.owner == src and it.kind ~= 'stretcher' then
            E.ReleasePatient(it, 'owner_left')
            if it.pusher then E.StopPushing(it) end
            E.Forget(it, true)
        end
    end
    rate[src] = nil
end

--- The 1 s safety pass: props or rigs that vanished, pushers who walked off or went off duty,
--- patients who are no longer on their prop, loaded patients who left the rig. Idle rig records are
--- dropped. Returns how many props were visited.
function E.Tick()
    local n = 0
    local far = num(S().FarTicks, 2)
    for _, it in pairs(items) do
        n = n + 1
        if not alive(it.entity) then
            E.OnEntityRemoved(it.entity)
        else
            local pos = GetEntityCoords(it.entity)
            it.lastPos = pos
            if it.pusher then
                local pp = posOf(it.pusher)
                if not pp or not isMedic(getPlayer(it.pusher)) or dist(pp, pos) > num(S().PusherMaxDistance, 4.0) then
                    it.farPush = (it.farPush or 0) + 1
                    if it.farPush >= far then E.StopPushing(it) end
                else
                    it.farPush = 0
                end
            end
            if it.patient then
                local pp = posOf(it.patient)
                if not pp then
                    E.ReleasePatient(it, 'patient_gone')
                elseif dist(pp, pos) > num(S().PatientMaxDistance, 3.0) then
                    it.farPatient = (it.farPatient or 0) + 1
                    if it.farPatient >= far then E.ReleasePatient(it, 'detached') end
                else
                    it.farPatient = 0
                end
            end
        end
    end
    for veh, rig in pairs(rigs) do
        if not alive(veh) then
            E.OnRigGone(veh)
        else
            rig.lastPos = GetEntityCoords(veh)
            local l = rig.loaded
            if l then
                local ped = pedOf(l.patient)
                if not ped or not getPlayer(l.patient) then
                    clearLoaded(rig, 'patient_gone')
                elseif GetVehiclePedIsIn(ped, false) ~= veh then
                    l.out = (l.out or 0) + 1
                    local cfg = rigCfg(veh)
                    if isDown(l.patient) and (l.reseats or 0) < 3 and dist(GetEntityCoords(ped), rig.lastPos) <= 8.0 and cfg then
                        -- a down patient thrown out of the seat (client hiccup) goes back in
                        l.reseats = (l.reseats or 0) + 1
                        SetPedIntoVehicle(ped, veh, l.seat)
                    elseif l.out >= far then
                        -- they left the rig: the stretcher stays inside
                        clearLoaded(rig, 'left_rig')
                    end
                else
                    l.out = 0
                end
            elseif countFor(function(it) return it.rig == veh end) == 0 then
                rigs[veh] = nil
                setEntityBag(veh, 'pf:rig', nil)
            end
        end
    end
    return n
end

--- Resource stop: every patient is released and every prop deleted.
function E.Shutdown()
    for _, rig in pairs(rigs) do
        if rig.loaded then
            local p = rig.loaded.patient
            rig.loaded = nil
            rigOfPatient[p] = nil
            setPlayerBag(p, 'pf:inRig', false) -- a seated patient stays in the seat
        end
        setEntityBag(rig.veh, 'pf:rig', nil)
    end
    for _, it in pairs(items) do
        E.ReleasePatient(it, 'resource_stop')
        if it.pusher then E.StopPushing(it) end
        E.Forget(it, true)
    end
    rigs = {}
end

--- Resource start: nobody can be on equipment yet; clear what a crash may have left on players.
function E.Boot()
    local ok, list = pcall(GetPlayers)
    if not ok or type(list) ~= 'table' then return end
    for _, s in ipairs(list) do
        local src = tonumber(s)
        if src then
            local okb, st = pcall(function() return Player(src).state end)
            if okb and st then
                if st['pf:onStretcher'] then setPlayerBag(src, 'pf:onStretcher', false) end
                if st['pf:inRig'] then setPlayerBag(src, 'pf:inRig', false) end
            end
        end
    end
end

--- What a player is on (specs, other modules): item id, rig vehicle.
function E.PatientOf(src) return patientOf[src], rigOfPatient[src] end
function E.Item(id) return items[id] end
function E.Rig(veh) return rigs[veh] end

AddEventHandler('playerDropped', function() E.OnLeft(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) E.OnLeft(src) end)
AddEventHandler('entityRemoved', function(entity) E.OnEntityRemoved(entity) end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then E.Shutdown() end end)
AddEventHandler('onResourceStart', function(res) if res == GetCurrentResourceName() then E.Boot() end end)

CreateThread(function()
    while true do
        Wait(math.max(1, num(C().TickSeconds, 1)) * 1000)
        local ok, err = pcall(E.Tick)
        if not ok then print('^1[pf-ambulancejob]^7 equipment tick failed: ' .. tostring(err)) end
    end
end)
