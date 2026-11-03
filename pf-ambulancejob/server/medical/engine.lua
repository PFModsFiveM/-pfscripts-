-- Medical engine: adds injuries and toxins to a patient, advances physiology for active patients only
-- (bleeding, down, toxins, drugs), runs the consciousness machine and tells the rest of the resource
-- (and other resources) when a patient's level of consciousness changes.
--
-- A healthy player is never touched by the tick: only patients in the active set are, and they leave
-- it as soon as nothing about them changes over time. An inactive patient's slow processes (blood
-- regeneration) are settled from the absolute timestamps when they become active again.

PFMed = PFMed or {}
PFMed.Engine = PFMed.Engine or {}
local E = PFMed.Engine
local P, I, A = PFMed.Physiology, PFMed.Injuries, PFMed.Anatomy
local Store = PFMed.Store

local active = {}      -- [cid] = true
local listeners = {}   -- consciousness subscribers (fn(cid, from, to, cause))

E.Random = function() return math.random() end   -- specs replace this for determinism

local function now() return os.time() end
local function modelCfg() return P.Cfg(Config.Medical) end

local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

local function finite(v)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- the parts of a patient the model reads
local function stateOf(p)
    return { blood_ml = p.blood_ml, hgb_factor = p.hgb_factor, airway = p.airway, breathing = p.breathing, pain = p.pain,
        temp_c = p.temp_c, toxins = p.toxins, drugs = p.drugs }
end

local function applyState(p, s)
    p.blood_ml, p.hgb_factor, p.airway, p.breathing = s.blood_ml, s.hgb_factor, s.airway, s.breathing
    p.temp_c, p.toxins, p.drugs = s.temp_c, s.toxins, s.drugs
end

local function applyBleeds(p, bleeds)
    for id, b in pairs(bleeds) do
        local inj = p.injuries[id]
        if inj and math.abs((tonumber(inj.bleed_ml_min) or 0) - b) >= 0.005 then
            inj.bleed_ml_min = b
            p.dirtyInj[id] = true
        end
    end
end

--- Worst stage of the open injuries ('healthy' when none is open).
function E.StageOf(p)
    local worst, rank = 'healthy', 0
    for _, inj in pairs(p.injuries) do
        local r = I.StageRank[inj.stage] or 0
        if inj.stage ~= 'recovered' and r > rank then worst, rank = inj.stage, r end
    end
    return worst
end

--- Bleeding now (ml/min): total, external (visible) and internal.
function E.Bleeding(p, at, c)
    c = c or modelCfg()
    local s = stateOf(p)
    local out = { total = 0, external = 0, internal = 0 }
    for _, inj in pairs(p.injuries) do
        local r = P.WoundBleed(inj, s, at, c)
        if r > 0 then
            out.total = out.total + r
            local attrs = type(inj.attrs) == 'table' and inj.attrs or {}
            if attrs.internal or attrs.fluid then out.internal = out.internal + r else out.external = out.external + r end
        end
    end
    return out
end

--- Bleeding level 0..4 from ml/min (none, minor, moderate, severe, massive).
function E.BleedLevel(ml)
    ml = tonumber(ml) or 0
    if ml <= 0 then return 0 elseif ml < 5 then return 1 elseif ml < 30 then return 2 elseif ml < 100 then return 3 end
    return 4
end

--- Whether anything about the patient changes over time (only then does the tick visit them).
function E.NeedsTick(p, at, c)
    c = c or modelCfg()
    local level = p.consciousness
    if level == 'dead' then return false end
    if level ~= 'alert' then return true end
    if next(p.toxins or {}) then return true end
    for name in pairs(p.drugs or {}) do
        if P.DrugActive(p, name, at, c) then return true end
    end
    if p.ctx and p.ctx.holdUntil and at < p.ctx.holdUntil then return true end
    if E.Bleeding(p, at, c).total > 0 then return true end
    local conds = P.Conditions(p.injuries, c)
    local target = c.Physiology.NormalTemp + conds.fever
    if math.abs((tonumber(p.temp_c) or target) - target) > 0.05 then return true end
    return false
end

-- ── consciousness ──────────────────────────────────────────────────────────────────────────────

--- fn(cid, from, to, cause) runs on every change (16A's down state subscribes).
function E.OnConsciousness(fn)
    if callable(fn) then listeners[#listeners + 1] = fn end
end

local function setLevel(p, to, cause, at, actor)
    local from = p.consciousness
    if from == to then return false end
    p.consciousness = to
    if to == 'unconscious' then
        p.down_since = p.down_since or at
        if from == 'arrest' then p.arrest_since = nil end
    elseif to == 'arrest' then
        p.down_since = p.down_since or at
        p.arrest_since = at
    elseif to == 'dead' then
        p.dead_at = at
        p.can_respawn_at = at + (modelCfg().Consciousness.RespawnAfterSeconds or 300)
    else
        p.down_since, p.arrest_since, p.dead_at, p.can_respawn_at = nil, nil, nil, nil
    end
    p.updated_at = at
    Store.MarkDirty(p.cid)
    Store.Audit(p.cid, 'state', actor, { from = from, to = to, cause = cause })
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, p.cid, from, to, cause)
        if not ok then print('^1[pf-ambulancejob]^7 consciousness listener failed: ' .. tostring(err)) end
    end
    TriggerEvent('pf-ambulancejob:server:consciousnessChanged', p.src, p.cid, from, to, cause)
    return true
end

--- Recomputes the vitals and runs one step of the automatic consciousness machine.
function E.Evaluate(p, at, c)
    c = c or modelCfg()
    local v = P.Vitals(stateOf(p), p.injuries, at, c, p.consciousness)
    local ctx = {}
    for k, val in pairs(p.ctx or {}) do ctx[k] = val end
    ctx.arrestSince = p.arrest_since
    local nextLevel, cause, nctx = P.NextConsciousness(p.consciousness, v, ctx, at, c)
    nctx.arrestSince = nil
    p.ctx = nctx
    if nextLevel ~= p.consciousness then
        p.cause = cause
        setLevel(p, nextLevel, cause, at, { kind = 'system' })
        v = P.Vitals(stateOf(p), p.injuries, at, c, p.consciousness)
    end
    if p.consciousness == 'arrest' or p.consciousness == 'dead' then v.rhythm = P.Rhythm(v, v.conditions, p.consciousness, p.cause) end
    if p.pain ~= v.pain then p.pain = v.pain end
    p.vitals, p.vitals_at = v, at
    local stage = E.StageOf(p)
    if stage ~= p.stage then p.stage = stage; Store.MarkDirty(p.cid) end
    return v
end

--- Forced change of consciousness by another module (16A down state, 17B ROSC, revive/respawn).
--- kind: 'report' | 'rosc' | 'revive' | 'respawn'. opts = { actor, holdSeconds }.
function E.SetConsciousness(cid, to, kind, cause, opts)
    opts = opts or {}
    if not P.Levels[to] then return nil, 'bad_args' end
    local p, err = Store.Get(cid)
    if not p then return nil, err end
    local at = now()
    if p.consciousness == to then return true end
    if not P.CanTransition(p.consciousness, to, kind) then return nil, 'invalid_state', p.consciousness end
    E.Touch(p, at)
    p.cause = cause
    setLevel(p, to, cause, at, opts.actor)
    local hold = finite(opts.holdSeconds)
    if hold and hold > 0 then p.ctx.holdUntil = at + math.min(hold, 3600) end
    p.ctx.okSince = nil
    E.Activate(cid)
    return true
end

-- ── active set and tick ────────────────────────────────────────────────────────────────────────

function E.IsActive(cid) return active[cid] == true end
function E.ActiveCount()
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    return n
end

--- Settles the time since the last tick for a patient that was not ticking (no blood is lost:
--- an inactive patient does not bleed). maxBleed > 0 for the offline catch-up at load.
function E.Settle(p, at, c, maxBleed)
    c = c or modelCfg()
    local last = tonumber(p.last_tick_at)
    if not last then p.last_tick_at = at return end
    local gap = at - last
    if gap <= 0 then return end
    if p.consciousness ~= 'dead' then
        local s, bleeds = P.Rest(stateOf(p), p.injuries, gap, last, c, maxBleed or 0)
        applyState(p, s)
        applyBleeds(p, bleeds)
    end
    p.last_tick_at = at
    Store.MarkDirty(p.cid)
end

--- Brings an inactive patient up to date before a change is applied.
function E.Touch(p, at)
    if not active[p.cid] then E.Settle(p, at) end
end

function E.Activate(cid)
    local p = Store.Peek(cid)
    if not p then return false end
    if not active[cid] then E.Settle(p, now()) end
    active[cid] = true
    return true
end

function E.Deactivate(cid) active[cid] = nil end

local function tickOne(p, at, c)
    local last = tonumber(p.last_tick_at) or at
    local dt = at - last
    if dt <= 0 then return end
    if dt > (Config.Medical.MaxTickGap or 60) then dt = Config.Medical.MaxTickGap or 60 end
    if p.consciousness == 'dead' then p.last_tick_at = at return end
    -- CPR ticks (17B sets cpr_last_at) pause the arrest-to-death timer
    if p.consciousness == 'arrest' and p.arrest_since and p.cpr_last_at and at - p.cpr_last_at <= c.Consciousness.CprWindowSeconds then
        p.arrest_since = p.arrest_since + dt
    end
    local s, bleeds = P.Step(stateOf(p), p.injuries, dt, at - dt, c, { arrest = p.consciousness == 'arrest' })
    applyState(p, s)
    applyBleeds(p, bleeds)
    p.last_tick_at, p.updated_at = at, at
    E.Evaluate(p, at, c)
    Store.MarkDirty(p.cid)
end

--- One pass over the active patients. Returns how many were visited.
function E.Tick(at)
    at = at or now()
    local c = modelCfg()
    local n = 0
    for cid in pairs(active) do
        local p = Store.Peek(cid)
        if not p then
            active[cid] = nil
        else
            n = n + 1
            local ok, err = pcall(tickOne, p, at, c)
            if not ok then print('^1[pf-ambulancejob]^7 medical tick failed for ' .. cid .. ': ' .. tostring(err)) end
            if not E.NeedsTick(p, at, c) then active[cid] = nil end
        end
    end
    return n
end

--- A patient came online: offline catch-up from the absolute timestamps, then ticking if needed.
function E.OnLoaded(p, at)
    local c = modelCfg()
    E.Settle(p, at, c, Config.Medical.Offline and Config.Medical.Offline.MaxBleedSeconds or 120)
    E.Evaluate(p, at, c)
    if E.NeedsTick(p, at, c) then active[p.cid] = true end
end

-- ── injuries ───────────────────────────────────────────────────────────────────────────────────

local RESERVED_ATTRS = { arterial = true, internal = true, noclot = true, fluid = true, note = true }

local function cleanAttrs(t)
    local out, n = {}, 0
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        if n >= 16 then break end
        if type(k) == 'string' and #k <= 24 and k:match('^%a[%w_]*$') and not RESERVED_ATTRS[k] then
            local tv = type(v)
            if tv == 'number' and finite(v) then out[k] = v; n = n + 1
            elseif tv == 'boolean' then out[k] = v; n = n + 1
            elseif tv == 'string' then out[k] = (v:gsub('%c', '')):sub(1, 64); n = n + 1 end
        end
    end
    return out
end
E.CleanAttrs = cleanAttrs

function E.ValidKey(key)
    return type(key) == 'string' and #key >= 1 and #key <= 128 and key:match('^[%w%-_:%.]+$') ~= nil
end

--- Checks an injury spec against the catalogue and fills in what the anatomy decides (region of a
--- structure, a structure in a region by its hit weights). Returns clean spec or nil, message.
function E.CleanSpec(spec)
    if type(spec) ~= 'table' then return nil, 'spec must be a table' end
    local t = type(spec.type) == 'string' and I.Types[spec.type] or nil
    if not t then return nil, 'unknown injury type' end
    if type(spec.mechanism) ~= 'string' or not I.Mechanisms[spec.mechanism] then return nil, 'unknown mechanism' end
    local severity = I.CleanSeverity(spec.severity)
    if not severity then return nil, 'severity must be 1..5' end
    local region, structure = spec.region, spec.structure
    if region ~= nil and not A.IsRegion(region) then return nil, 'unknown region' end
    if structure ~= nil and not A.IsStructure(structure) then return nil, 'unknown structure' end
    if region and structure and not A.StructureInRegion(structure, region) then return nil, 'structure is not in that region' end

    local subtype = spec.subtype
    if subtype ~= nil then
        if type(subtype) ~= 'string' or not t.subtypes or not t.subtypes[subtype] then return nil, 'unknown subtype' end
    elseif t.defaultSubtype then
        subtype = t.defaultSubtype
    elseif t.subtypes then
        -- the structure decides (a dislocated knee is the 'knee' subtype)
        local names = {}
        for name in pairs(t.subtypes) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local sub = t.subtypes[name]
            if structure and sub.structures then
                for _, id in ipairs(sub.structures) do if id == structure then subtype = name end end
            end
            if subtype then break end
        end
        if not subtype then return nil, 'subtype needed' end
    end
    local sub = t.subtypes and t.subtypes[subtype] or {}

    if not structure then
        local list = sub.structures or t.structures
        if region then
            if list then
                for _, id in ipairs(list) do if A.StructureInRegion(id, region) then structure = id break end end
            end
            if not structure then
                local surfaceOk = (t.surface == true) and true or false
                local picked, _, found = A.PickStructure(region, E.Random(), function(id) return I.AllowsStructure(spec.type, subtype, id) end, surfaceOk)
                if not found then return nil, 'this injury type does not fit that region' end
                structure = picked
            end
        elseif t.systemic then
            structure = t.defaultStructure
        elseif list then
            structure = list[1]
        else
            return nil, 'region or structure needed'
        end
    end
    if structure and not region then region = A.DefaultRegion(structure) end
    if not I.AllowsStructure(spec.type, subtype, structure) then return nil, 'this injury type cannot affect that structure' end

    local note = spec.note
    if note ~= nil then
        if type(note) ~= 'string' then return nil, 'note must be text' end
        note = note:gsub('%c', ' '):sub(1, 255)
    end
    local attacker = spec.attackerCid
    if attacker ~= nil and not Store.ValidCitizenId(attacker) then return nil, 'bad attacker citizen id' end
    return {
        type = spec.type, subtype = subtype, region = region, structure = structure, severity = severity,
        mechanism = spec.mechanism, attrs = cleanAttrs(spec.attrs), note = note, attackerCid = attacker,
        -- what the caller asked for (the idempotency fingerprint; picks are not part of it)
        fp = table.concat({ spec.mechanism, spec.type, tostring(spec.subtype or ''), tostring(spec.region or ''),
            tostring(spec.structure or ''), tostring(severity) }, '|'),
    }
end

--- Public shape of an injury (events, exports): no idempotency fingerprint, no internals.
function E.PublicInjury(inj)
    local attrs = {}
    for k, v in pairs(inj.attrs or {}) do if k:sub(1, 1) ~= '_' then attrs[k] = v end end
    return { id = inj.id, type = inj.type, subtype = inj.subtype, region = inj.region, structure = inj.structure,
        severity = inj.severity, mechanism = inj.mechanism, stage = inj.stage, attrs = attrs }
end

local function openCount(p)
    local n = 0
    for _, inj in pairs(p.injuries) do if inj.stage ~= 'recovered' then n = n + 1 end end
    return n
end

local function mergeAtCap(p, clean, at)
    for id, inj in pairs(p.injuries) do
        if inj.stage ~= 'recovered' and inj.type == clean.type and inj.region == clean.region and inj.structure == clean.structure then
            inj.severity = math.min(5, math.max(inj.severity, clean.severity) + 1)
            local bleed = I.Bleed(inj.type, inj.subtype, inj.structure, inj.severity, inj.attrs)
            inj.bleed_ml_min = math.max(tonumber(inj.bleed_ml_min) or 0, bleed.mlPerMin)
            inj.pain = math.max(tonumber(inj.pain) or 0, I.Pain(inj.type, inj.subtype, inj.severity))
            p.dirtyInj[id] = true
            return inj
        end
    end
    return nil
end

local function duplicateOf(p, key, fp)
    local hit = Store.FindByKey(key)
    if not hit then return nil end
    if hit.citizenid ~= p.cid or type(hit.attrs) ~= 'table' or hit.attrs._fp ~= fp then return false end
    return p.injuries[hit.id] or { id = hit.id }
end

local function addLocked(p, clean, ctx, at)
    local key = ctx.key
    if key then
        local dup = duplicateOf(p, key, clean.fp)
        if dup == false then return nil, 'key_reused' end
        if dup then return dup, nil, true end
    end
    E.Touch(p, at)
    if openCount(p) >= (Config.Medical.MaxOpenInjuries or 40) then
        local merged = mergeAtCap(p, clean, at)
        if not merged then return nil, 'conflict', 'too many open injuries' end
        Store.MarkDirty(p.cid, merged.id)
        E.Evaluate(p, at)
        if E.NeedsTick(p, at) then active[p.cid] = true end
        return merged
    end
    local bleed = I.Bleed(clean.type, clean.subtype, clean.structure, clean.severity, clean.attrs)
    local attrs = clean.attrs
    attrs.arterial = bleed.arterial or nil
    attrs.internal = bleed.internal or nil
    attrs.noclot = bleed.noclot or nil
    attrs.fluid = bleed.fluid or nil
    attrs.note = clean.note
    attrs._fp = clean.fp
    local inj = {
        type = clean.type, subtype = clean.subtype, region = clean.region, structure = clean.structure, severity = clean.severity,
        stage = 'injured', bleed_ml_min = bleed.mlPerMin, pain = I.Pain(clean.type, clean.subtype, clean.severity),
        mechanism = clean.mechanism, attrs = attrs, treatments = {}, source_attacker_cid = clean.attackerCid,
        idem_key = key, created_at = at,
    }
    local id, err = Store.InsertInjury(p, inj)
    if not id then
        if err == 'duplicate' and key then
            local dup = duplicateOf(p, key, clean.fp)
            if dup == false then return nil, 'key_reused' end
            if dup then return dup, nil, true end
        end
        return nil, err == 'duplicate' and 'db_unavailable' or err
    end
    p.updated_at = at
    Store.MarkDirty(p.cid)
    Store.Audit(p.cid, 'injury', ctx.actor, {
        id = id, type = inj.type, subtype = inj.subtype, region = inj.region, structure = inj.structure, severity = inj.severity,
        mechanism = inj.mechanism, source = ctx.source, invoker = ctx.invoker, key = key,
    })
    E.Evaluate(p, at)
    if E.NeedsTick(p, at) then active[p.cid] = true end
    TriggerEvent('pf-ambulancejob:server:injuryAdded', p.cid, E.PublicInjury(inj))
    return inj
end

--- Adds a server-attested injury. ctx = { actor = { cid, src, job, kind, label }, key, source, invoker }.
--- Returns injury, nil, duplicate | nil, error code, message.
function E.AddInjury(cid, spec, ctx)
    ctx = ctx or {}
    local clean, msg = E.CleanSpec(spec)
    if not clean then return nil, 'bad_args', msg end
    if ctx.key ~= nil and not E.ValidKey(ctx.key) then return nil, 'bad_args', 'bad idempotency key' end
    local p, err = Store.Get(cid)
    if not p then return nil, err end
    if not Store.Lock(cid) then return nil, 'busy' end
    local ok, a, b, c = pcall(addLocked, p, clean, ctx, now())
    Store.Unlock(cid)
    if not ok then
        print('^1[pf-ambulancejob]^7 adding an injury failed: ' .. tostring(a))
        return nil, 'db_unavailable'
    end
    return a, b, c
end

local STAGE_TIME = { stabilized = 'stabilized_at', treated = 'treated_at', recovered = 'recovered_at' }

--- Changes an injury (treatment and recovery modules). patch = { stage, severity, bleed_ml_min,
--- pain, treatments = { key = value | false }, attrs = { ... }, recover_at }.
--- Returns injury | nil, error code, message.
function E.UpdateInjury(cid, injuryId, patch, ctx)
    ctx = ctx or {}
    if type(patch) ~= 'table' then return nil, 'bad_args' end
    local p, err = Store.Get(cid)
    if not p then return nil, err end
    local inj = p.injuries[tonumber(injuryId) or -1]
    if not inj then return nil, 'not_found' end
    local at = now()
    E.Touch(p, at)
    local changed = {}
    if patch.stage ~= nil and patch.stage ~= inj.stage then
        if not I.CanTransition(inj.stage, patch.stage) then return nil, 'invalid_state', inj.stage end
        changed.stage = { inj.stage, patch.stage }
        inj.stage = patch.stage
        local col = STAGE_TIME[patch.stage]
        if col then inj[col] = at end
    end
    if patch.severity ~= nil then
        local s = I.CleanSeverity(patch.severity)
        if not s then return nil, 'bad_args', 'severity must be 1..5' end
        inj.severity, changed.severity = s, s
    end
    if patch.bleed_ml_min ~= nil then
        local b = finite(patch.bleed_ml_min)
        if not b or b < 0 or b > 99999 then return nil, 'bad_args', 'bleed out of range' end
        inj.bleed_ml_min, changed.bleed_ml_min = b, b
    end
    if patch.pain ~= nil then
        local v = finite(patch.pain)
        if not v or v < 0 or v > 10 then return nil, 'bad_args', 'pain out of range' end
        inj.pain, changed.pain = v, v
    end
    if type(patch.treatments) == 'table' then
        inj.treatments = type(inj.treatments) == 'table' and inj.treatments or {}
        for k, v in pairs(cleanAttrs(patch.treatments)) do
            if v == false then inj.treatments[k] = nil else inj.treatments[k] = v end
        end
        changed.treatments = true
    end
    if type(patch.attrs) == 'table' then
        inj.attrs = type(inj.attrs) == 'table' and inj.attrs or {}
        for k, v in pairs(cleanAttrs(patch.attrs)) do inj.attrs[k] = v end
        changed.attrs = true
    end
    if patch.recover_at ~= nil then
        local r = math.tointeger(finite(patch.recover_at) or -1)
        if not r or r < 0 then return nil, 'bad_args', 'recover_at must be unix seconds' end
        inj.recover_at = r
    end
    p.updated_at = at
    Store.MarkDirty(cid, inj.id)
    Store.Audit(cid, 'injury_update', ctx.actor, { id = inj.id, changed = changed, source = ctx.source })
    E.Evaluate(p, at)
    if E.NeedsTick(p, at) then active[cid] = true end
    return inj
end

-- ── toxins ─────────────────────────────────────────────────────────────────────────────────────

--- Adds an amount of a toxin (in its unit). Returns the new level | nil, error code, message.
function E.AddToxin(cid, toxin, amount, ctx)
    ctx = ctx or {}
    local c = modelCfg()
    local def = type(toxin) == 'string' and c.Toxins[toxin] or nil
    if not def then return nil, 'bad_args', 'unknown toxin' end
    amount = finite(amount)
    if not amount or amount <= 0 or amount > def.max then return nil, 'bad_args', 'amount out of range' end
    local p, err = Store.Get(cid)
    if not p then return nil, err end
    local at = now()
    E.Touch(p, at)
    local level = math.min(def.max, (tonumber(p.toxins[toxin]) or 0) + amount)
    p.toxins[toxin] = P.Round(level, 4)
    p.updated_at = at
    Store.MarkDirty(cid)
    Store.Audit(cid, 'toxin', ctx.actor, { toxin = toxin, amount = amount, level = p.toxins[toxin], source = ctx.source, invoker = ctx.invoker })
    E.Evaluate(p, at, c)
    if E.NeedsTick(p, at, c) then active[cid] = true end
    return p.toxins[toxin]
end

-- ── reads ──────────────────────────────────────────────────────────────────────────────────────

--- Current vitals of a cached patient (derived now, never stored as facts).
function E.Vitals(p, at)
    at = at or now()
    if p.vitals and p.vitals_at == at then return p.vitals end
    local v = P.Vitals(stateOf(p), p.injuries, at, modelCfg(), p.consciousness)
    if p.consciousness == 'arrest' or p.consciousness == 'dead' then v.rhythm = P.Rhythm(v, v.conditions, p.consciousness, p.cause) end
    return v
end

--- down:boolean, level:string from memory only (no database read).
function E.IsDown(cid)
    local p = Store.Peek(cid)
    if not p then return false, 'unknown' end
    local level = p.consciousness
    return level == 'unconscious' or level == 'arrest' or level == 'dead', level
end

CreateThread(function()
    while true do
        Wait((Config.Medical.TickSeconds or 5) * 1000)
        local ok, err = pcall(E.Tick, os.time())
        if not ok then print('^1[pf-ambulancejob]^7 medical tick failed: ' .. tostring(err)) end
    end
end)
