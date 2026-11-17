-- Functional effect profile of a patient, computed on the server from the true injuries, the
-- derived vitals, active drugs/toxins and the persisted restrictions (shared/medical/effects_model.lua
-- combines everything by MAXIMUM per channel). Push sends the profile and the restriction kinds to
-- the owner's client applier (client/effects.lua) only when they changed; the client never decides
-- what it suffers from.

PFMed = PFMed or {}
PFMed.Effects = PFMed.Effects or {}
local F = PFMed.Effects
local P, EM = PFMed.Physiology, PFMed.EffectsModel

local function rcfg() return Config.Medical.Recovery or {} end

local sent = {}         -- [cid] = signature of the last payload sent to that patient's client
local seenUpdate = {}   -- [cid] = p.updated_at when the last payload was built
local seq = 0           -- one counter for every push of this session: a newer push always has a higher version

--- Modifiers from the patient's state: analgesia from active drugs, toxin intensities, crutches.
function F.Mods(p, at)
    local c = P.Cfg(Config.Medical)
    local mods = { toxins = {} }
    for name, def in pairs(c.Drugs) do
        if def.analgesia and P.DrugActive(p, name, at, c) then mods.analgesia = true end
    end
    for name in pairs(p.toxins or {}) do mods.toxins[name] = P.ToxinIntensity(p, name, at, c) end
    if type(p.restrictions) == 'table' and p.restrictions.crutches then mods.crutches = true end
    return mods
end

-- Open persisted restrictions of a patient as a list sorted by kind (from server/medical/recovery.lua).
local function persisted(p, at)
    local out = {}
    if type(p.restrictions) ~= 'table' then return out end
    for kind, r in pairs(p.restrictions) do
        if type(r) == 'table' and (r.untilAt == nil or r.untilAt > at) then out[#out + 1] = r
        elseif r == true then out[#out + 1] = { kind = kind } end
    end
    table.sort(out, function(a, b) return tostring(a.kind) < tostring(b.kind) end)
    return out
end

--- Raises channels to the floors the persisted restrictions set (after painkillers: a cast stays a cast).
function F.ApplyRestrictionFloors(profile, list)
    local floors = rcfg().RestrictionEffects or {}
    for _, r in ipairs(list) do
        local f = floors[r.kind]
        if type(f) == 'table' then
            for ch, v in pairs(f) do
                v = math.max(0, math.min(3, math.floor(tonumber(v) or 0)))
                if profile[ch] ~= nil and v > profile[ch] then profile[ch] = v end
            end
        end
    end
    return profile
end

--- Profile of a cached patient object.
function F.ProfileOf(p, at)
    at = at or os.time()
    local v = PFMed.Engine.Vitals(p, at)
    local profile = EM.Combine(p.injuries, v, F.Mods(p, at))
    return F.ApplyRestrictionFloors(profile, persisted(p, at))
end

--- Profile by citizen id (nil when the patient is not in memory).
function F.Profile(cid, at)
    local p = PFMed.Store.Peek(cid)
    if not p then return nil end
    return F.ProfileOf(p, at)
end

--- Restrictions of a patient: the ones that follow from the profile (derived) and the persisted ones
--- (discharge orders, casts, concussion), one entry per kind. A persisted entry wins over a derived
--- one of the same kind (it has an end time). Entries: { kind, reason, untilAt?, persisted? }.
--- A persisted restriction's own reason (it may name the injury) is given only with opts.detail;
--- otherwise it reads 'injury', so the summary for police, prison and courts stays generic.
--- opts.detail = false: every reason becomes the generic 'injury'.
function F.Restrictions(p, at, opts)
    at = at or os.time()
    local detail = opts and opts.detail
    local profile = F.ProfileOf(p, at)
    local out, byKind = {}, {}
    for _, r in ipairs(persisted(p, at)) do
        local e = { kind = r.kind, reason = detail and r.reason or 'injury', untilAt = r.untilAt, persisted = true }
        out[#out + 1] = e
        byKind[r.kind] = e
    end
    for _, r in ipairs(EM.Restrictions(profile, p.injuries)) do
        if not byKind[r.kind] then
            local e = { kind = r.kind, reason = r.reason }
            out[#out + 1] = e
            byKind[r.kind] = e
        end
    end
    if opts and opts.detail == false then
        for _, e in ipairs(out) do e.reason = 'injury' end
    end
    return out, profile
end

--- What the client receives: every channel (0..3) plus `restrictions`, a sorted list of kinds.
function F.Payload(p, at)
    local list, profile = F.Restrictions(p, at)
    local payload, kinds = {}, {}
    for _, ch in ipairs(EM.Channels) do payload[ch] = profile[ch] or 0 end
    for i, r in ipairs(list) do kinds[i] = r.kind end
    table.sort(kinds)
    payload.restrictions = kinds
    return payload, EM.Signature(profile) .. '|' .. table.concat(kinds, ','), profile
end

local function resolve(who)
    local Store = PFMed.Store
    if type(who) == 'number' then
        local cid = Store.CidOf(who)
        return cid, cid and Store.Peek(cid)
    elseif type(who) == 'string' then
        return who, Store.Peek(who)
    end
    return nil, nil
end

--- The payload and whether it differs from the last one sent to this patient.
function F.Changed(cid, at)
    local p = PFMed.Store.Peek(cid)
    if not p then return nil, false end
    local payload, sig = F.Payload(p, at or os.time())
    return payload, sent[cid] ~= sig, sig
end

--- Sends the profile to the patient's own client when it changed (opts.force: always, e.g. at load).
--- who: server id or citizen id of an online, cached patient. Returns true when something was sent.
function F.Push(who, opts)
    opts = opts or {}
    local cid, p = resolve(who)
    if not p or not p.src then return false end
    local at = opts.at or os.time()
    local payload, changed, sig = F.Changed(cid, at)
    seenUpdate[cid] = p.updated_at
    if PFMed.Recovery and PFMed.Recovery.Watch then PFMed.Recovery.Watch(p, payload, at) end
    if not changed and not opts.force then return false end
    sent[cid] = sig
    seq = seq + 1
    TriggerClientEvent('pf-ambulancejob:client:Effects', p.src, payload, seq)
    return true
end

--- One pass over online patients whose record changed or who are ticking (the 5 s loop). A healthy
--- patient who changed nothing costs one table lookup.
function F.Sync(at)
    at = at or os.time()
    local n, due = 0, {}
    PFMed.Store.Each(function(cid, p)
        if p.src and (PFMed.Engine.IsActive(cid) or seenUpdate[cid] ~= p.updated_at) then due[#due + 1] = cid end
    end)
    -- the list is taken first: a recovery pass may wait on the database while other loads change the cache
    for _, cid in ipairs(due) do
        local p = PFMed.Store.Peek(cid)
        if p and p.src then
            -- a treatment may have completed a stage (treated -> recovering is immediate)
            if PFMed.Recovery and p.stage ~= 'healthy' then PFMed.Recovery.Advance(cid, at, { noPush = true }) end
            if F.Push(p.src, { at = at }) then n = n + 1 end
        end
    end
    return n
end

function F.Forget(cid)
    sent[cid] = nil
    seenUpdate[cid] = nil
end

-- a change of consciousness changes the profile at once (vision, drive)
if PFMed.Engine and PFMed.Engine.OnConsciousness then
    PFMed.Engine.OnConsciousness(function(cid) F.Push(cid) end)
end

CreateThread(function()
    while true do
        Wait((rcfg().SyncSeconds or 5) * 1000)
        local ok, err = pcall(F.Sync, os.time())
        if not ok then print('^1[pf-ambulancejob]^7 effect sync failed: ' .. tostring(err)) end
    end
end)
