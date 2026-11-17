-- Recovery stages, restrictions and complications (architecture 5.2, 11.8; batch 17C).
--
-- Stage machine per injury: injured -> stabilized -> treated -> recovering -> recovered, plus
-- complicated (infection, re-bleed) back to stabilized. The patient's stage is the worst open one
-- (the engine derives it). Clocks are absolute (recover_at), so time offline counts: the catch-up
-- runs when the character loads, then every Config.Medical.Recovery.LoopSeconds while online.
--
-- Restrictions (no_drive, crutches, cast_arm_l, concussion, ...) are rows in pf_med_restrictions:
-- set by a wound that enters recovery (they end with it) or by others (17E discharge orders). They
-- are loaded and pushed with the effect profile at load, and survive a relog. The client applier
-- enforces them; the server checks what it can see: a 1 Hz sampler over watched patients only logs
-- a no_drive driver (logged, never punished) and rolls a re-bleed on exertion.

PFMed = PFMed or {}
PFMed.Recovery = PFMed.Recovery or {}
PFMed.SQL = PFMed.SQL or {}
local R, Q = PFMed.Recovery, PFMed.SQL
local I, A, P = PFMed.Injuries, PFMed.Anatomy, PFMed.Physiology
local Store = PFMed.Store

local function cfg() return Config.Medical.Recovery or {} end
local function now() return os.time() end

R.Random = function() return math.random() end   -- specs replace this for determinism
R.stats = { advances = 0, violations = 0, rebleeds = 0, infections = 0 }

local SYSTEM = { kind = 'system', label = 'recovery' }
local busy = {}    -- [cid] = true while an advance or a restriction write waits on the database
local watch = {}   -- [cid] = { noDrive, rebleed, exert, lastRoll, lastViolation }: what the sampler visits

local function finite(v)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function cleanText(v, max)
    if v == nil then return nil end
    if type(v) ~= 'string' then return false end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

function R.ValidKind(kind)
    return type(kind) == 'string' and #kind >= 2 and #kind <= 32 and kind:match('^[a-z][a-z0-9_]*$') ~= nil
end

-- ── SQL ────────────────────────────────────────────────────────────────────────────────────────

function Q.LoadRestrictions(cid, limit)
    return MySQL.query.await('SELECT `id`, `kind`, `reason`, `injury_id`, `from_at`, `until_at`, `by_cid` FROM `pf_med_restrictions` WHERE `citizenid` = ? AND `ended_at` IS NULL ORDER BY `id` LIMIT ?', { cid, limit }) or {}
end

--- Open restrictions that are still running (read path for an offline citizen).
function Q.ReadRestrictions(cid, at, limit)
    return MySQL.query.await('SELECT `kind`, `reason`, `until_at` FROM `pf_med_restrictions` WHERE `citizenid` = ? AND `ended_at` IS NULL AND (`until_at` IS NULL OR `until_at` > ?) ORDER BY `id` LIMIT ?', { cid, at, limit }) or {}
end

function Q.InsertRestriction(r)
    local params = {}
    local values = Q.BindRow({ r.citizenid, r.kind, r.reason, r.injury_id, r.from_at, r.until_at, r.by_cid }, 7, params)
    return MySQL.insert.await('INSERT INTO `pf_med_restrictions` (`citizenid`, `kind`, `reason`, `injury_id`, `from_at`, `until_at`, `by_cid`) VALUES ' .. values, params)
end

function Q.EndRestriction(id, at)
    return MySQL.update.await('UPDATE `pf_med_restrictions` SET `ended_at` = ? WHERE `id` = ? AND `ended_at` IS NULL', { at, id })
end

function Q.SetRestrictionUntil(id, untilAt)
    if untilAt == nil then
        return MySQL.update.await('UPDATE `pf_med_restrictions` SET `until_at` = NULL WHERE `id` = ? AND `ended_at` IS NULL', { id })
    end
    return MySQL.update.await('UPDATE `pf_med_restrictions` SET `until_at` = ? WHERE `id` = ? AND `ended_at` IS NULL', { untilAt, id })
end

function Q.DeleteRestrictions(cid)
    return MySQL.update.await('DELETE FROM `pf_med_restrictions` WHERE `citizenid` = ?', { cid })
end

-- ── restrictions in memory ─────────────────────────────────────────────────────────────────────
-- p.restrictionRows = { [id] = { id, kind, reason, injuryId, fromAt, untilAt, byCid } } (open rows)
-- p.restrictions    = { [kind] = { kind, reason, untilAt } } merged per kind; what effects.lua reads

local function rowFromDb(r)
    return { id = tonumber(r.id), kind = r.kind, reason = r.reason, injuryId = tonumber(r.injury_id), fromAt = tonumber(r.from_at),
        untilAt = tonumber(r.until_at), byCid = r.by_cid }
end

--- Rebuilds the per-kind view from the open rows (a kind with one open-ended row is open-ended).
function R.Rebuild(p)
    local set = {}
    for _, row in pairs(p.restrictionRows or {}) do
        local cur = set[row.kind]
        if not cur then
            set[row.kind] = { kind = row.kind, reason = row.reason, untilAt = row.untilAt }
        else
            if cur.untilAt ~= nil and (row.untilAt == nil or row.untilAt > cur.untilAt) then cur.untilAt = row.untilAt; cur.reason = row.reason or cur.reason end
        end
    end
    p.restrictions = set
    return set
end

--- Loads the open restriction rows of a cached patient once. Returns true or nil, error code.
function R.EnsureLoaded(p)
    if p.restrictionRows then return true end
    if not Store.Ready() then return nil, 'db_unavailable' end
    local ok, rows = pcall(Q.LoadRestrictions, p.cid, 100)
    if not ok then
        print('^1[pf-ambulancejob]^7 loading restrictions of ' .. p.cid .. ' failed: ' .. tostring(rows))
        return nil, 'db_unavailable'
    end
    p.restrictionRows = {}
    for _, r in ipairs(rows) do
        local row = rowFromDb(r)
        if row.id and R.ValidKind(row.kind) then p.restrictionRows[row.id] = row end
    end
    R.Rebuild(p)
    return true
end

local function openRowCount(p)
    local n = 0
    for _ in pairs(p.restrictionRows or {}) do n = n + 1 end
    return n
end

-- Adds (or extends) a restriction of a cached patient whose rows are loaded. The caller holds busy[cid].
local function addLocked(p, spec, at, actor)
    for _, row in pairs(p.restrictionRows) do
        if row.kind == spec.kind and row.injuryId == spec.injuryId then
            -- the same restriction again: keep one row and move its end to the later of the two
            local newUntil = (row.untilAt == nil or spec.untilAt == nil) and nil or math.max(row.untilAt, spec.untilAt)
            if newUntil ~= row.untilAt then
                local ok, err = pcall(Q.SetRestrictionUntil, row.id, newUntil)
                if not ok then print('^1[pf-ambulancejob]^7 extending a restriction failed: ' .. tostring(err)) return nil, 'db_unavailable' end
                row.untilAt = newUntil
                R.Rebuild(p)
                Store.Audit(p.cid, 'restriction', actor, { op = 'extend', id = row.id, kind = row.kind, untilAt = newUntil })
            end
            return { ok = true, id = row.id, extended = true }
        end
    end
    if openRowCount(p) >= (cfg().MaxOpenRestrictions or 30) then return nil, 'conflict' end
    local ok, id = pcall(Q.InsertRestriction, { citizenid = p.cid, kind = spec.kind, reason = spec.reason, injury_id = spec.injuryId,
        from_at = at, until_at = spec.untilAt, by_cid = spec.byCid })
    id = ok and tonumber(id) or nil
    if not id or id <= 0 then
        print('^1[pf-ambulancejob]^7 storing a restriction failed: ' .. tostring(ok and id or id))
        return nil, 'db_unavailable'
    end
    p.restrictionRows[id] = { id = id, kind = spec.kind, reason = spec.reason, injuryId = spec.injuryId, fromAt = at, untilAt = spec.untilAt, byCid = spec.byCid }
    R.Rebuild(p)
    Store.Audit(p.cid, 'restriction', actor, { op = 'add', id = id, kind = spec.kind, injuryId = spec.injuryId, untilAt = spec.untilAt })
    return { ok = true, id = id }
end

local function endRow(p, row, at, actor, why)
    local ok, err = pcall(Q.EndRestriction, row.id, at)
    if not ok then print('^1[pf-ambulancejob]^7 ending a restriction failed: ' .. tostring(err)) return false end
    p.restrictionRows[row.id] = nil
    Store.Audit(p.cid, 'restriction', actor, { op = 'end', id = row.id, kind = row.kind, why = why })
    return true
end

--- Checks a restriction spec. spec = { kind, reason?, untilAt? | seconds?, injuryId?, byCid? }.
--- Returns clean spec or nil, message.
function R.CleanSpec(spec, at)
    if type(spec) ~= 'table' then return nil, 'spec must be a table' end
    if not R.ValidKind(spec.kind) then return nil, 'bad kind' end
    local reason = cleanText(spec.reason, 128)
    if reason == false then return nil, 'reason must be text' end
    local untilAt
    if spec.seconds ~= nil then
        local s = math.tointeger(finite(spec.seconds) or -1)
        if not s or s < 60 or s > 90 * 86400 then return nil, 'seconds must be 60 s .. 90 days' end
        untilAt = at + s
    elseif spec.untilAt ~= nil then
        untilAt = math.tointeger(finite(spec.untilAt) or -1)
        if not untilAt or untilAt <= at or untilAt > at + 90 * 86400 then return nil, 'untilAt must be in the next 90 days' end
    end
    local injuryId
    if spec.injuryId ~= nil then
        injuryId = math.tointeger(finite(spec.injuryId) or -1)
        if not injuryId or injuryId <= 0 then return nil, 'bad injury id' end
    end
    if spec.byCid ~= nil and not Store.ValidCitizenId(spec.byCid) then return nil, 'bad citizen id' end
    return { kind = spec.kind, reason = reason, untilAt = untilAt, injuryId = injuryId, byCid = spec.byCid }
end

--- Adds a restriction (internal API for the hospital and treatment modules; a discharge order is one
--- call per kind). The citizen may be offline. A second call for the same kind (and wound) extends the
--- open row instead of adding one. Returns { ok, id, extended? } or { ok = false, error, message }.
function R.AddRestriction(cid, spec, opts)
    opts = opts or {}
    if not Store.ValidCitizenId(cid) then return { ok = false, error = 'bad_args', message = 'bad citizen id' } end
    local at = now()
    local clean, msg = R.CleanSpec(spec, at)
    if not clean then return { ok = false, error = 'bad_args', message = msg } end
    if not Store.Ready() then return { ok = false, error = 'db_unavailable' } end
    if busy[cid] then return { ok = false, error = 'busy' } end
    busy[cid] = true   -- before the first database wait
    local okCall, res, err = pcall(function()
        local p = Store.Peek(cid)
        if not p then
            -- offline: a throwaway view of the open rows is enough to dedupe; the next load reads them
            local ok, rows = pcall(Q.LoadRestrictions, cid, 100)
            if not ok then return nil, 'db_unavailable' end
            p = { cid = cid, restrictionRows = {} }
            for _, r in ipairs(rows) do local row = rowFromDb(r) if row.id then p.restrictionRows[row.id] = row end end
            return addLocked(p, clean, at, opts.actor)
        end
        local loaded, lerr = R.EnsureLoaded(p)
        if not loaded then return nil, lerr end
        local out, aerr = addLocked(p, clean, at, opts.actor)
        if out and p.src and PFMed.Effects then PFMed.Effects.Push(p.src) end
        return out, aerr
    end)
    busy[cid] = nil
    if not okCall then
        print('^1[pf-ambulancejob]^7 adding a restriction failed: ' .. tostring(res))
        return { ok = false, error = 'db_unavailable' }
    end
    if not res then return { ok = false, error = err or 'db_unavailable' } end
    return res
end

--- Ends every open restriction of `kind` of a cached patient (a clinician lifts it; a cast comes off).
--- Returns { ok, ended = n }.
function R.EndRestriction(cid, kind, opts)
    opts = opts or {}
    if not Store.ValidCitizenId(cid) or not R.ValidKind(kind) then return { ok = false, error = 'bad_args' } end
    local p = Store.Peek(cid)
    if not p then return { ok = false, error = 'offline' } end
    if busy[cid] then return { ok = false, error = 'busy' } end
    busy[cid] = true
    local n = 0
    local ok, err = pcall(function()
        if not R.EnsureLoaded(p) then return end
        for _, row in pairs(p.restrictionRows) do
            if row.kind == kind and (opts.injuryId == nil or row.injuryId == opts.injuryId) then
                if endRow(p, row, now(), opts.actor, 'lifted') then n = n + 1 end
            end
        end
        R.Rebuild(p)
    end)
    busy[cid] = nil
    if not ok then print('^1[pf-ambulancejob]^7 ending restrictions failed: ' .. tostring(err)) return { ok = false, error = 'db_unavailable' } end
    if n > 0 and p.src and PFMed.Effects then PFMed.Effects.Push(p.src) end
    return { ok = true, ended = n }
end

--- Reads a cached patient's open rows again after another module wrote rows itself (17E discharge
--- orders) and pushes the profile. While a pass holds the patient, the reload runs at its end.
--- An offline citizen needs nothing: the next load reads the table. Returns { ok, reloaded | deferred }.
function R.ReloadRestrictions(cid)
    if not Store.ValidCitizenId(cid) then return { ok = false, error = 'bad_args' } end
    local p = Store.Peek(cid)
    if not p then return { ok = true, reloaded = false } end
    if busy[cid] then p.reloadRestrictions = true return { ok = true, deferred = true } end
    busy[cid] = true
    p.restrictionRows = nil
    local ok, loaded = pcall(R.EnsureLoaded, p)
    busy[cid] = nil
    if not ok or not loaded then return { ok = false, error = 'db_unavailable' } end
    if p.src and PFMed.Effects then PFMed.Effects.Push(p.src) end
    return { ok = true, reloaded = true }
end
R.Reload = R.ReloadRestrictions

--- Restrictions a wound sets when it enters recovery: list of { kind, reason }.
function R.InjuryRestrictionKinds(inj)
    local out, seen = {}, {}
    local group = nil
    local s = inj.structure and A.Structures[inj.structure]
    local r = inj.region and A.Regions[inj.region]
    group = (s and s.group) or (r and r.group)
    local kindOfGroup = group and A.GroupKind[group]
    local side = group and group:match('_(%a)$')
    for _, rule in ipairs(cfg().InjuryRestrictions or {}) do
        local typeOk = type(rule.types) ~= 'table' or rule.types[inj.type] == true
        local groupOk = type(rule.groups) ~= 'table' or (kindOfGroup ~= nil and rule.groups[kindOfGroup] == true)
        local sevOk = (tonumber(inj.severity) or 1) >= (rule.minSeverity or 1)
        if typeOk and groupOk and sevOk then
            for _, k in ipairs(rule.kinds or {}) do
                local kind = k
                if kind:find('<side>', 1, true) then kind = side and kind:gsub('<side>', side) or nil end
                if kind and R.ValidKind(kind) and not seen[kind] then
                    seen[kind] = true
                    out[#out + 1] = { kind = kind, reason = rule.reason }
                end
            end
        end
    end
    return out
end

-- ── stage machine ──────────────────────────────────────────────────────────────────────────────

local function treatmentsOf(inj) return type(inj.treatments) == 'table' and inj.treatments or {} end
local function attrsOf(inj) return type(inj.attrs) == 'table' and inj.attrs or {} end

--- True when one of the actions is on the wound's treatments (by action name or by the flag the
--- engine model reads; any surgery_* counts when 'surgery' is set).
function R.HasAny(tr, actions)
    local flags = cfg().TreatmentFlags or {}
    for _, a in ipairs(actions or {}) do
        if tr[a] or (flags[a] and tr[flags[a]]) then return true end
        if type(a) == 'string' and a:sub(1, 8) == 'surgery_' and tr.surgery then return true end
    end
    return false
end

--- Bleeding controlled, no airway/breathing/circulation threat left, and (for structural types)
--- the wound held by a stabilizing treatment.
function R.IsStable(p, inj, at)
    local tr = treatmentsOf(inj)
    if tr.surgery then return true end
    local def = I.Types[inj.type]
    if not def then return false end
    local c = P.Cfg(Config.Medical)
    local bleed = P.WoundBleed(inj, p, at, c)
    if bleed >= (cfg().ControlledBleedMlPerMin or 1.0) and not tr.tourniquet then return false end
    local ph = I.Physiology(inj)
    if ph.tension or ph.tamponade or ph.lethal or ph.arrest then return false end
    if (ph.airway == 'obstructed' or ph.airway == 'partial') and p.airway ~= 'secured' then return false end
    if (cfg().NeedsStabilizer or {})[inj.type] and not R.HasAny(tr, def.stabilizeBy) and not R.HasAny(tr, def.treatBy) then return false end
    return true
end

function R.HasDefinitiveCare(inj)
    local tr = treatmentsOf(inj)
    if tr.surgery then return true end
    local def = I.Types[inj.type]
    return def ~= nil and R.HasAny(tr, def.treatBy)
end

function R.SelfHeals(inj)
    local max = (cfg().SelfHeal or {})[inj.type]
    return max ~= nil and (tonumber(inj.severity) or 5) <= max
end

--- Healing time of a wound from the moment it reaches definitive care.
function R.HealSeconds(inj)
    local def = I.Types[inj.type]
    local sev = I.CleanSeverity(inj.severity) or 1
    local base = def and I.At(def.healSeconds, sev) or 3600
    local mult = cfg().HealMultiplier or 1.0
    if attrsOf(inj).self_heal then mult = mult * (cfg().SelfHealMultiplier or 1.5) end
    return math.max(60, math.floor(base * mult + 0.5))
end

--- A complicated wound may stabilise again once its infection is under antibiotics (or gone).
function R.ComplicationResolved(p, inj)
    local link = math.tointeger(tonumber(attrsOf(inj).infected))
    if not link then return true end
    local x = p.injuries[link]
    if not x or x.stage ~= 'injured' and x.stage ~= 'complicated' then return true end
    return treatmentsOf(x).antibiotics ~= nil
end

local function infectionProne(inj)
    local def = I.Types[inj.type]
    if not def then return false end
    local sub = def.subtypes and inj.subtype and def.subtypes[inj.subtype]
    return def.infection == true or (sub and sub.infection == true) or false
end

local function update(p, inj, patch)
    local res, err = PFMed.Engine.UpdateInjury(p.cid, inj.id, patch, { actor = SYSTEM, source = 'recovery' })
    if not res then print(('^3[pf-ambulancejob]^7 recovery could not update injury %s: %s'):format(tostring(inj.id), tostring(err))) end
    return res ~= nil
end

-- One stage step of one wound. Returns true when the wound moved; `entered` collects wounds that
-- entered recovery (they get their restrictions after the memory pass).
local function step(p, inj, at, entered)
    local st = inj.stage
    if st == 'injured' or st == 'complicated' then
        if R.IsStable(p, inj, at) and (st ~= 'complicated' or R.ComplicationResolved(p, inj)) then
            return update(p, inj, { stage = 'stabilized' })
        end
    elseif st == 'stabilized' then
        if R.HasDefinitiveCare(inj) then return update(p, inj, { stage = 'treated' }) end
        if R.SelfHeals(inj) then return update(p, inj, { stage = 'treated', attrs = { self_heal = true } }) end
    elseif st == 'treated' then
        -- a recover_at set by the treatment (or hospital) module wins over the catalogue time
        local recoverAt = tonumber(inj.recover_at)
        if not recoverAt or recoverAt <= (tonumber(inj.treated_at) or 0) then recoverAt = at + R.HealSeconds(inj) end
        if update(p, inj, { stage = 'recovering', recover_at = math.floor(recoverAt) }) then
            entered[#entered + 1] = inj
            return true
        end
    elseif st == 'recovering' then
        local recoverAt = tonumber(inj.recover_at)
        if not recoverAt then return update(p, inj, { recover_at = at + R.HealSeconds(inj) }) end
        if at >= recoverAt then
            if update(p, inj, { stage = 'recovered' }) then
                -- healed at recover_at, also when that moment passed while offline
                inj.recovered_at = math.min(at, math.floor(recoverAt))
                Store.MarkDirty(p.cid, inj.id)
                return true
            end
        end
    end
    return false
end

-- An open wound left without wound care becomes infected (offline time counts: created_at is absolute).
local function checkInfection(p, inj, at)
    if inj.type == 'infection' or (inj.stage ~= 'injured' and inj.stage ~= 'stabilized') then return false end
    local inf = cfg().Infection or {}
    local attrs = attrsOf(inj)
    if attrs.infected or (tonumber(inj.severity) or 0) < (inf.MinSeverity or 2) or not infectionProne(inj) then return false end
    if R.HasAny(treatmentsOf(inj), inf.CareFlags) then return false end
    if at - (tonumber(inj.created_at) or at) < (inf.AfterSeconds or 7200) then return false end
    if not inj.region and not inj.structure then return false end
    local spec = { mechanism = 'infection', type = 'infection', subtype = 'wound_infection', region = inj.region, severity = 1 }
    if inj.structure and I.AllowsStructure('infection', 'wound_infection', inj.structure) then spec.structure = inj.structure end
    local res, err = PFMed.Engine.AddInjury(p.cid, spec, { key = 'pf-ambulancejob:infection:' .. inj.id, source = 'recovery', actor = SYSTEM })
    if not res or not res.id then
        print(('^3[pf-ambulancejob]^7 infection of injury %s not recorded: %s'):format(tostring(inj.id), tostring(err)))
        return false
    end
    R.stats.infections = R.stats.infections + 1
    return update(p, inj, { stage = 'complicated', attrs = { infected = res.id } })
end

-- An untreated infection gets worse with time (several steps at once after time offline).
local function worsenInfection(p, inj, at)
    if inj.type ~= 'infection' or inj.stage ~= 'injured' or treatmentsOf(inj).antibiotics then return false end
    local inf = cfg().Infection or {}
    local every = inf.WorsenSeconds or 3600
    local maxSev = inf.MaxSeverity or 3
    local sev = tonumber(inj.severity) or 1
    if sev >= maxSev then return false end
    local last = tonumber(attrsOf(inj).worsened_at) or tonumber(inj.created_at) or at
    local steps = math.floor((at - last) / every)
    if steps < 1 then return false end
    local newSev = math.min(maxSev, sev + steps)
    return update(p, inj, { severity = newSev, pain = I.Pain('infection', inj.subtype, newSev), attrs = { worsened_at = last + steps * every } })
end

local function sortedOpen(p)
    local list = {}
    for _, inj in pairs(p.injuries) do if inj.stage ~= 'recovered' then list[#list + 1] = inj end end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return list
end

-- Restriction rows that ended: time passed, or their wound healed. A wound's rows follow a changed recover_at.
local function syncRestrictions(p, at)
    local changed = false
    for _, row in pairs(p.restrictionRows) do
        local inj = row.injuryId and p.injuries[row.injuryId] or nil
        if row.untilAt and row.untilAt <= at then
            changed = endRow(p, row, row.untilAt, SYSTEM, 'expired') or changed
        elseif row.injuryId and (not inj or inj.stage == 'recovered') then
            changed = endRow(p, row, math.min(at, inj and tonumber(inj.recovered_at) or at), SYSTEM, 'healed') or changed
        elseif inj and inj.stage == 'recovering' and tonumber(inj.recover_at) and row.untilAt ~= tonumber(inj.recover_at) then
            local ok = pcall(Q.SetRestrictionUntil, row.id, tonumber(inj.recover_at))
            if ok then row.untilAt = tonumber(inj.recover_at); changed = true end
        end
    end
    if changed then R.Rebuild(p) end
    return changed
end

local function advanceLocked(p, at)
    local changed = 0
    if p.reloadRestrictions then
        -- rows written by another module while an earlier pass held this patient
        p.reloadRestrictions, p.restrictionRows = nil, nil
        changed = changed + 1
    end
    local loaded = R.EnsureLoaded(p)
    for _, inj in ipairs(sortedOpen(p)) do
        if checkInfection(p, inj, at) then changed = changed + 1 end
        if worsenInfection(p, inj, at) then changed = changed + 1 end
    end
    local entered = {}
    -- a wound can move several stages in one pass (e.g. stable, treated and recovering at once)
    for _ = 1, 5 do
        local moved = 0
        for _, inj in ipairs(sortedOpen(p)) do
            if step(p, inj, at, entered) then moved = moved + 1 end
        end
        changed = changed + moved
        if moved == 0 then break end
    end
    if loaded then
        for _, inj in ipairs(entered) do
            for _, k in ipairs(R.InjuryRestrictionKinds(inj)) do
                local recoverAt = tonumber(inj.recover_at)
                local res = addLocked(p, { kind = k.kind, reason = k.reason, injuryId = inj.id,
                    untilAt = recoverAt and recoverAt > at and math.floor(recoverAt) or nil }, at, SYSTEM)
                if res and not res.extended then changed = changed + 1 end
            end
        end
        if syncRestrictions(p, at) then changed = changed + 1 end
    end
    return changed
end

--- One recovery pass for a cached patient: infections, stage steps, restriction start/end.
--- opts.noPush: the caller pushes the effect profile itself. Returns changes or nil, error code.
function R.Advance(cid, at, opts)
    opts = opts or {}
    at = at or now()
    local p = Store.Peek(cid)
    if not p then return nil, 'not_found' end
    if busy[cid] then return nil, 'busy' end
    busy[cid] = true
    R.stats.advances = R.stats.advances + 1
    local ok, res = pcall(advanceLocked, p, at)
    busy[cid] = nil
    if not ok then
        print('^1[pf-ambulancejob]^7 recovery pass failed for ' .. cid .. ': ' .. tostring(res))
        return nil, 'db_unavailable'
    end
    if res > 0 and not opts.noPush and p.src and PFMed.Effects then PFMed.Effects.Push(p.src, { at = at }) end
    return res
end

--- A character loaded (after the engine's offline catch-up): restrictions loaded, offline recovery
--- settled, the profile pushed even when it looks unchanged (the client starts empty).
function R.OnLoaded(p, at)
    at = at or now()
    p.restrictionRows = nil
    R.Advance(p.cid, at, { noPush = true })
    if p.src and PFMed.Effects then PFMed.Effects.Push(p.src, { force = true, at = at }) end
end

--- The 60 s loop: online patients that are not healthy or still have restrictions.
function R.Tick(at)
    at = at or now()
    local n, due = 0, {}
    Store.Each(function(cid, p)
        if p.src and (p.stage ~= 'healthy' or p.restrictionRows == nil or next(p.restrictionRows) ~= nil) then due[#due + 1] = cid end
    end)
    -- taken first: a pass may wait on the database while loads change the cache
    for _, cid in ipairs(due) do
        if R.Advance(cid, at) then n = n + 1 end
    end
    return n
end

-- ── server-side checks: no_drive and exertion (1 Hz, watched patients only) ─────────────────────

--- Wounds held only by a dressing that exertion can open again.
function R.ReBleedCandidate(p)
    for _, inj in ipairs(sortedOpen(p)) do
        local tr = treatmentsOf(inj)
        if inj.stage == 'stabilized' and not tr.tourniquet and not tr.surgery
            and (tr.pressure or tr.hemostatic or tr.pressure_dressing or tr.hemostatic_gauze)
            and not R.HasAny(tr, (cfg().Infection or {}).CareFlags) then
            local first = I.Bleed(inj.type, inj.subtype, inj.structure, I.CleanSeverity(inj.severity) or 1, attrsOf(inj)).mlPerMin
            if first > 0 then return inj, first end
        end
    end
    return nil
end

--- Called by PFMed.Effects.Push with the payload just built: decides whether the sampler watches
--- this patient (no_drive restriction or channel, or a wound that can re-bleed).
function R.Watch(p, payload)
    if not p.src then watch[p.cid] = nil return end
    local noDrive = (tonumber(payload.drive) or 0) >= 2
    for _, k in ipairs(payload.restrictions or {}) do if k == 'no_drive' then noDrive = true end end
    local rebleed = R.ReBleedCandidate(p) ~= nil
    if not noDrive and not rebleed then watch[p.cid] = nil return end
    local w = watch[p.cid] or {}
    w.noDrive, w.rebleed = noDrive, rebleed
    watch[p.cid] = w
end

function R.IsWatched(cid) return watch[cid] end

--- Exertion opened a dressed wound again: it bleeds and is complicated until controlled again.
function R.ReBleed(p, at)
    local inj, first = R.ReBleedCandidate(p)
    if not inj then return false end
    local frac = (cfg().ReBleed or {}).Fraction or 0.5
    local bleed = math.max(tonumber(inj.bleed_ml_min) or 0, math.floor(first * frac * 100 + 0.5) / 100)
    local ok = update(p, inj, { stage = 'complicated', bleed_ml_min = bleed,
        treatments = { pressure = false, hemostatic = false, pressure_dressing = false, hemostatic_gauze = false },
        attrs = { rebleed = (tonumber(attrsOf(inj).rebleed) or 0) + 1 } })
    if not ok then return false end
    R.stats.rebleeds = R.stats.rebleeds + 1
    Store.Audit(p.cid, 'recovery', SYSTEM, { op = 'rebleed', injuryId = inj.id, bleed = bleed })
    if PFMed.Effects then PFMed.Effects.Push(p.src, { at = at }) end
    return true
end

local function horizontalSpeed(ent)
    local v = GetEntityVelocity(ent)
    if v == nil then return 0 end
    local x, y = tonumber(v.x) or 0, tonumber(v.y) or 0
    return math.sqrt(x * x + y * y)
end

--- One sampler pass. Driving with no_drive is logged (one row per ViolationLogSeconds), never punished.
--- A patient who left (no src) drops out of the watch list here, so it stays bounded.
function R.Sample(at)
    at = at or now()
    local c = cfg()
    local rb = c.ReBleed or {}
    local n = 0
    for cid, w in pairs(watch) do
        local p = Store.Peek(cid)
        local ped = p and p.src and GetPlayerPed(p.src) or 0
        if not p or not p.src then
            watch[cid] = nil
        elseif ped and ped ~= 0 then
            n = n + 1
            local veh = GetVehiclePedIsIn(ped, false) or 0
            if w.noDrive and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                if at - (w.lastViolation or 0) >= (c.ViolationLogSeconds or 60) then
                    w.lastViolation = at
                    R.stats.violations = R.stats.violations + 1
                    Store.Audit(cid, 'anomaly', { cid = cid, src = p.src }, { kind = 'no_drive_violation', restriction = 'no_drive' })
                    -- the client may have missed the profile: send it again
                    if PFMed.Effects then PFMed.Effects.Push(p.src, { force = true, at = at }) end
                end
            end
            if w.rebleed then
                if veh == 0 and horizontalSpeed(ped) >= (rb.ExertionSpeed or 5.5) then w.exert = (w.exert or 0) + 1 else w.exert = 0 end
                if w.exert >= (rb.ExertionSamples or 3) then
                    w.exert = 0
                    if at - (w.lastRoll or 0) >= (rb.CooldownSeconds or 120) then
                        w.lastRoll = at
                        if R.Random() < (rb.Chance or 0.1) then R.ReBleed(p, at) end
                    end
                end
            end
        end
    end
    return n
end

-- ── export ─────────────────────────────────────────────────────────────────────────────────────

local function exportFail(code, message) return { ok = false, error = code, message = message or code } end

--- export GetRestrictions(who): { ok, list = { { kind, until, reason } } }. Open to every resource;
--- reasons are given only to the resource itself and medical callers (SummaryFields 'all').
function R.GetRestrictions(who)
    local Api = PFMed.Api
    local okCaller, invoker = Api.Allowed('GetRestrictions')
    if not okCaller then return exportFail('not_allowed', 'This resource may not read restrictions.') end
    local cid, why = Api.Resolve(who)
    if not cid then return exportFail(why == 'not_found' and 'not_found' or 'bad_args') end
    local detail = invoker == nil or (Config.Medical.SummaryFields or {})[invoker] == 'all'
    local at = now()
    local list = {}
    local p = Store.Peek(cid)
    if p and p.restrictionRows then
        for _, r in ipairs((PFMed.Effects.Restrictions(p, at, { detail = detail }))) do
            list[#list + 1] = { kind = r.kind, ['until'] = r.untilAt, reason = r.reason }
        end
    else
        if not Store.Ready() then return exportFail('db_unavailable') end
        local ok, rows = pcall(Q.ReadRestrictions, cid, at, 100)
        if not ok then return exportFail('db_unavailable') end
        local seen = {}
        for _, r in ipairs(rows) do
            local untilAt = tonumber(r.until_at)
            local e = seen[r.kind]
            if not e then
                e = { kind = r.kind, ['until'] = untilAt, reason = detail and r.reason or 'injury' }
                seen[r.kind] = e
                list[#list + 1] = e
            elseif e['until'] ~= nil and (untilAt == nil or untilAt > e['until']) then
                e['until'] = untilAt
            end
        end
    end
    return { ok = true, list = list }
end

exports('GetRestrictions', function(who) return R.GetRestrictions(who) end)

-- ── lifecycle ──────────────────────────────────────────────────────────────────────────────────

-- The engine's load hook (offline catch-up) is the one place every load path passes through, also
-- a PlayerLoaded that arrived while the row was still loading; recovery runs right after it.
do
    local E = PFMed.Engine
    if E and E.OnLoaded and E.OnLoaded ~= R._onLoadedHook then
        local engineOnLoaded = E.OnLoaded
        R._onLoadedHook = function(p, at)
            engineOnLoaded(p, at)
            local ok, err = pcall(R.OnLoaded, p, at)
            if not ok then print('^1[pf-ambulancejob]^7 recovery at load failed: ' .. tostring(err)) end
        end
        E.OnLoaded = R._onLoadedHook
    end
end

-- pfm-core raises this server-only event after it deleted a character; a player cannot send it.
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if not Store.ValidCitizenId(citizenid) then return end
    watch[citizenid] = nil
    if Store.Ready() then
        local ok, err = pcall(Q.DeleteRestrictions, citizenid)
        if not ok then print('^1[pf-ambulancejob]^7 deleting restrictions of ' .. citizenid .. ' failed: ' .. tostring(err)) end
    end
end)

CreateThread(function()
    while true do
        Wait((cfg().LoopSeconds or 60) * 1000)
        local ok, err = pcall(R.Tick, os.time())
        if not ok then print('^1[pf-ambulancejob]^7 recovery loop failed: ' .. tostring(err)) end
    end
end)

CreateThread(function()
    while true do
        Wait((cfg().SampleSeconds or 1) * 1000)
        local ok, err = pcall(R.Sample, os.time())
        if not ok then print('^1[pf-ambulancejob]^7 recovery sampler failed: ' .. tostring(err)) end
    end
end)
