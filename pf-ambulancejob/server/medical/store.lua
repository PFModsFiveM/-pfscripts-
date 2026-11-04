-- Patient store: loads a citizen's medical state (pf_med_patients + open pf_med_injuries) into a
-- memory cache, writes changes back in batches (write-behind every Config.Medical.WriteBehindSeconds),
-- and keeps the diagnosis layers (pf_med_findings / pf_med_diagnoses) apart from the true injuries.
--
-- Lifecycle: load on QBCore:Server:PlayerLoaded (with offline catch-up from absolute timestamps),
-- flush and drop from memory on playerDropped / logout, flush everything on resource stop, delete
-- every row of a deleted character. Every SQL statement is in PFMed.SQL so the real-DB specs run
-- them as they are and the mocked specs can swap the table for an in-memory one.

PFMed = PFMed or {}
PFMed.Store = PFMed.Store or {}
PFMed.SQL = PFMed.SQL or {}
local Store, Q = PFMed.Store, PFMed.SQL

local function cfg() return Config.Medical end
local function now() return os.time() end

-- ── helpers ────────────────────────────────────────────────────────────────────────────────────

local function decode(s)
    if type(s) ~= 'string' or s == '' then return {} end
    local ok, v = pcall(json.decode, s)
    if ok and type(v) == 'table' then return v end
    return {}
end

local function encode(t)
    if type(t) ~= 'table' or next(t) == nil then return nil end
    return json.encode(t)
end

local function num(v, default)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return default end
    return v
end

local function clampNum(v, lo, hi)
    v = num(v, lo)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- One row of placeholders. A nil value becomes a literal NULL instead of a hole in the parameter
-- list (a Lua list with holes does not cross the resource boundary as a list).
local function bindRow(values, n, params)
    local marks = {}
    for i = 1, n do
        local v = values[i]
        if v == nil then marks[i] = 'NULL' else marks[i] = '?'; params[#params + 1] = v end
    end
    return '(' .. table.concat(marks, ', ') .. ')'
end
Q.BindRow = bindRow

function Store.ValidCitizenId(cid)
    return type(cid) == 'string' and cid ~= '' and #cid <= 64 and cid:match('^[%w_%-]+$') ~= nil
end

-- ── SQL (every statement of the store) ─────────────────────────────────────────────────────────

local PATIENT_COLS = { 'citizenid', 'consciousness', 'stage', 'blood_ml', 'hgb_factor', 'airway', 'breathing', 'pain', 'temp_c',
    'toxins', 'drugs', 'arrest_since', 'down_since', 'dead_at', 'can_respawn_at', 'last_tick_at', 'updated_at', 'hold_until' }
local INJURY_COLS = { 'id', 'citizenid', 'type', 'subtype', 'region', 'structure', 'severity', 'stage', 'bleed_ml_min', 'pain',
    'mechanism', 'attrs', 'treatments', 'source_attacker_cid', 'created_at', 'stabilized_at', 'treated_at', 'recover_at', 'recovered_at' }
local INJURY_UPDATE = { 'severity', 'stage', 'bleed_ml_min', 'pain', 'attrs', 'treatments', 'stabilized_at', 'treated_at', 'recover_at', 'recovered_at' }

local function updateClause(cols, skip)
    local out = {}
    for _, c in ipairs(cols) do if not skip or not skip[c] then out[#out + 1] = ('`%s` = VALUES(`%s`)'):format(c, c) end end
    return table.concat(out, ', ')
end

function Q.LoadPatient(cid)
    return MySQL.single.await('SELECT * FROM `pf_med_patients` WHERE `citizenid` = ?', { cid })
end

function Q.LoadOpenInjuries(cid, limit)
    return MySQL.query.await("SELECT * FROM `pf_med_injuries` WHERE `citizenid` = ? AND `stage` <> 'recovered' ORDER BY `id` LIMIT ?", { cid, limit }) or {}
end

function Q.FindInjuryByKey(key)
    return MySQL.single.await('SELECT `id`, `citizenid`, `attrs` FROM `pf_med_injuries` WHERE `idem_key` = ?', { key })
end

function Q.InjuryOwner(id)
    return MySQL.scalar.await('SELECT `citizenid` FROM `pf_med_injuries` WHERE `id` = ?', { id })
end

--- Inserts one injury and returns its id.
function Q.InsertInjury(r)
    local params = {}
    local values = bindRow({ r.citizenid, r.type, r.subtype, r.region, r.structure, r.severity, r.stage, r.bleed_ml_min, r.pain,
        r.mechanism, r.attrs, r.treatments, r.source_attacker_cid, r.idem_key, r.created_at }, 15, params)
    return MySQL.insert.await('INSERT INTO `pf_med_injuries` (`citizenid`, `type`, `subtype`, `region`, `structure`, `severity`, `stage`, `bleed_ml_min`, `pain`, `mechanism`, `attrs`, `treatments`, `source_attacker_cid`, `idem_key`, `created_at`) VALUES ' .. values, params)
end

--- Writes many patients in one statement.
function Q.UpsertPatients(rows)
    if #rows == 0 then return true end
    local params, tuples = {}, {}
    for i, r in ipairs(rows) do
        local vals = {}
        for j, c in ipairs(PATIENT_COLS) do vals[j] = r[c] end
        tuples[i] = bindRow(vals, #PATIENT_COLS, params)
    end
    MySQL.query.await(('INSERT INTO `pf_med_patients` (`%s`) VALUES %s ON DUPLICATE KEY UPDATE %s'):format(
        table.concat(PATIENT_COLS, '`, `'), table.concat(tuples, ', '), updateClause(PATIENT_COLS, { citizenid = true })), params)
    return true
end

--- Writes the changed fields of many existing injuries in one statement.
function Q.UpsertInjuries(rows)
    if #rows == 0 then return true end
    local params, tuples = {}, {}
    for i, r in ipairs(rows) do
        local vals = {}
        for j, c in ipairs(INJURY_COLS) do vals[j] = r[c] end
        tuples[i] = bindRow(vals, #INJURY_COLS, params)
    end
    MySQL.query.await(('INSERT INTO `pf_med_injuries` (`%s`) VALUES %s ON DUPLICATE KEY UPDATE %s'):format(
        table.concat(INJURY_COLS, '`, `'), table.concat(tuples, ', '), updateClause(INJURY_UPDATE)), params)
    return true
end

function Q.InsertEvents(rows)
    if #rows == 0 then return true end
    local params, tuples = {}, {}
    for i, e in ipairs(rows) do
        tuples[i] = bindRow({ e.citizenid, e.action, e.actor_cid, e.actor_src, e.actor_job, e.detail, e.at }, 7, params)
    end
    MySQL.query.await('INSERT INTO `pf_med_events` (`citizenid`, `action`, `actor_cid`, `actor_src`, `actor_job`, `detail`, `at`) VALUES ' .. table.concat(tuples, ', '), params)
    return true
end

Q.CharacterSteps = {
    { name = 'patients', sql = 'DELETE FROM `pf_med_patients` WHERE `citizenid` = ?' },
    { name = 'injuries', sql = 'DELETE FROM `pf_med_injuries` WHERE `citizenid` = ?' },
    { name = 'events', sql = 'DELETE FROM `pf_med_events` WHERE `citizenid` = ?' },
    { name = 'findings', sql = 'DELETE FROM `pf_med_findings` WHERE `citizenid` = ?' },
    { name = 'diagnoses', sql = 'DELETE FROM `pf_med_diagnoses` WHERE `citizenid` = ?' },
    -- the legacy injury layer (its treatment log rows go first: they point at the injury rows)
    { name = 'legacy_treatments', sql = ('DELETE FROM `%s` WHERE `citizen_id` = ?'):format(Config.Database.PlayerTreatmentLog) },
    { name = 'legacy_injuries', sql = ('DELETE FROM `%s` WHERE `citizen_id` = ?'):format(Config.Database.PlayerInjuries) },
}

--- Deletes every row of a citizen; each step runs on its own. Returns { [step] = rows | false }.
function Q.DeleteCharacter(cid)
    local out = {}
    for _, step in ipairs(Q.CharacterSteps) do
        local ok, n = pcall(MySQL.update.await, step.sql, { cid })
        if ok then out[step.name] = tonumber(n) or 0 else
            out[step.name] = false
            print(('^1[pf-ambulancejob]^7 cleanup (%s) of deleted character %s failed: %s'):format(step.name, cid, tostring(n)))
        end
    end
    return out
end

--- Retention: recovered injuries and old events, in batches. Returns rows deleted per table.
function Q.Sweep(injuriesBefore, eventsBefore, batch, maxRounds)
    local out = { injuries = 0, events = 0 }
    for _, job in ipairs({
        { 'injuries', "DELETE FROM `pf_med_injuries` WHERE `stage` = 'recovered' AND `recovered_at` IS NOT NULL AND `recovered_at` < ? LIMIT " .. batch, injuriesBefore },
        { 'events', 'DELETE FROM `pf_med_events` WHERE `at` < ? LIMIT ' .. batch, eventsBefore },
    }) do
        for _ = 1, maxRounds do
            local n = tonumber(MySQL.update.await(job[2], { job[3] })) or 0
            out[job[1]] = out[job[1]] + n
            if n < batch then break end
        end
    end
    return out
end

function Q.InsertFinding(r)
    local params = {}
    local values = bindRow({ r.citizenid, r.injury_id, r.modality, r.region, r.structure, r.sign, r.certainty, r.value, r.by_cid, r.by_tier, r.at }, 11, params)
    return MySQL.insert.await('INSERT INTO `pf_med_findings` (`citizenid`, `injury_id`, `modality`, `region`, `structure`, `sign`, `certainty`, `value`, `by_cid`, `by_tier`, `at`) VALUES ' .. values, params)
end

function Q.ListFindings(cid, since, limit)
    return MySQL.query.await('SELECT * FROM `pf_med_findings` WHERE `citizenid` = ? AND `at` >= ? ORDER BY `id` DESC LIMIT ?', { cid, since, limit }) or {}
end

function Q.InsertDiagnosis(r)
    local params = {}
    local values = bindRow({ r.citizenid, r.injury_id, r.structure, r.injury_type, r.status, r.source, r.by_cid, r.note, r.at }, 9, params)
    return MySQL.insert.await('INSERT INTO `pf_med_diagnoses` (`citizenid`, `injury_id`, `structure`, `injury_type`, `status`, `source`, `by_cid`, `note`, `at`) VALUES ' .. values, params)
end

function Q.ListDiagnoses(cid, status, limit)
    if status then
        return MySQL.query.await('SELECT * FROM `pf_med_diagnoses` WHERE `citizenid` = ? AND `status` = ? ORDER BY `id` DESC LIMIT ?', { cid, status, limit }) or {}
    end
    return MySQL.query.await('SELECT * FROM `pf_med_diagnoses` WHERE `citizenid` = ? ORDER BY `id` DESC LIMIT ?', { cid, limit }) or {}
end

-- ── cache ──────────────────────────────────────────────────────────────────────────────────────

local cache = {}       -- [cid] = patient
local bySrc = {}       -- [src] = cid
local dirty = {}       -- [cid] = true
local loading = {}     -- [cid] = true while a load waits on the database
local locks = {}       -- [cid] = true while a check-then-write runs
local pendingAttach = {} -- [cid] = src: a character that came online while its row was loading
local LOAD_WAIT_MS = 5000
local events = {}      -- audit rows waiting for the next flush
local MAX_EVENTS = 2000
local OFFLINE_TTL = 120

Store.stats = { peeks = 0, gets = 0, loads = 0, flushes = 0 }

function Store.Ready() return PFMed.Schema ~= nil and PFMed.Schema.Ready() end

local function injuryFromRow(r)
    return {
        id = tonumber(r.id), citizenid = r.citizenid, type = r.type, subtype = r.subtype, region = r.region, structure = r.structure,
        severity = tonumber(r.severity) or 1, stage = r.stage or 'injured', bleed_ml_min = num(r.bleed_ml_min, 0), pain = num(r.pain, 0),
        mechanism = r.mechanism, attrs = decode(r.attrs), treatments = decode(r.treatments), source_attacker_cid = r.source_attacker_cid,
        idem_key = r.idem_key, created_at = tonumber(r.created_at), stabilized_at = tonumber(r.stabilized_at),
        treated_at = tonumber(r.treated_at), recover_at = tonumber(r.recover_at), recovered_at = tonumber(r.recovered_at),
    }
end

function Store.NewPatient(cid, at)
    local s = PFMed.Physiology.NewState(Config.Medical)
    return {
        cid = cid, consciousness = 'alert', stage = 'healthy', blood_ml = s.blood_ml, hgb_factor = s.hgb_factor, airway = s.airway,
        breathing = s.breathing, pain = 0, temp_c = s.temp_c, toxins = {}, drugs = {}, injuries = {}, ctx = {}, dirtyInj = {},
        last_tick_at = at, updated_at = at, persisted = false,
    }
end

local function patientFromRow(cid, r, at)
    local p = Store.NewPatient(cid, at)
    if not r then return p end
    p.persisted = true
    p.consciousness = r.consciousness or 'alert'
    p.stage = r.stage or 'healthy'
    p.blood_ml = num(r.blood_ml, p.blood_ml)
    p.hgb_factor = num(r.hgb_factor, 1)
    p.airway = r.airway or 'clear'
    p.breathing = num(r.breathing, 1)
    p.pain = num(r.pain, 0)
    p.temp_c = num(r.temp_c, 37.0)
    p.toxins = decode(r.toxins)
    p.drugs = decode(r.drugs)
    p.arrest_since, p.down_since, p.dead_at = tonumber(r.arrest_since), tonumber(r.down_since), tonumber(r.dead_at)
    p.can_respawn_at, p.last_tick_at, p.updated_at = tonumber(r.can_respawn_at), tonumber(r.last_tick_at) or at, tonumber(r.updated_at) or at
    p.ctx.holdUntil = tonumber(r.hold_until)
    return p
end

--- The cached patient, never touching the database (cheap; what the engine tick uses).
function Store.Peek(cid)
    Store.stats.peeks = Store.stats.peeks + 1
    return cache[cid]
end

--- Loads a citizen from the database into the cache. Returns patient or nil, error code.
function Store.Load(cid, at)
    if not Store.ValidCitizenId(cid) then return nil, 'bad_args' end
    if not Store.Ready() then return nil, 'db_unavailable' end
    if cache[cid] then return cache[cid] end
    if loading[cid] then
        -- another caller is loading this citizen: wait for that load instead of failing
        local deadline = GetGameTimer() + LOAD_WAIT_MS
        while loading[cid] and GetGameTimer() < deadline do Wait(0) end
        if cache[cid] then return cache[cid] end
        return nil, 'busy'
    end
    loading[cid] = true
    Store.stats.loads = Store.stats.loads + 1
    local ok, p = pcall(function()
        local row = Q.LoadPatient(cid)
        local p2 = patientFromRow(cid, row, at or now())
        for _, r in ipairs(Q.LoadOpenInjuries(cid, cfg().MaxOpenInjuries or 40)) do
            local inj = injuryFromRow(r)
            if inj.id then p2.injuries[inj.id] = inj end
        end
        return p2
    end)
    loading[cid] = nil
    if not ok then
        print('^1[pf-ambulancejob]^7 loading patient ' .. cid .. ' failed: ' .. tostring(p))
        return nil, 'db_unavailable'
    end
    cache[cid] = p
    -- a PlayerLoaded that arrived during this load: attach and catch up now
    local waiting = pendingAttach[cid]
    if waiting then
        pendingAttach[cid] = nil
        if bySrc[waiting] == cid then
            p.src, p.offline = waiting, nil
            if PFMed.Engine then PFMed.Engine.OnLoaded(p, now()) end
        end
    end
    return p
end

--- The patient (cached, or loaded now). Returns patient or nil, error code.
function Store.Get(cid)
    Store.stats.gets = Store.stats.gets + 1
    local p = cache[cid]
    if p then p.touched = now() return p end
    local loaded, err = Store.Load(cid)
    if loaded then loaded.touched = now() end
    return loaded, err
end

function Store.MarkDirty(cid, injuryId)
    local p = cache[cid]
    if not p then return end
    p.dirty = true
    if injuryId then p.dirtyInj[injuryId] = true end
    dirty[cid] = true
end

function Store.IsDirty(cid) return dirty[cid] == true end

function Store.Lock(cid)
    if locks[cid] then return false end
    locks[cid] = true
    return true
end
function Store.Unlock(cid) locks[cid] = nil end

-- online players
function Store.Attach(src, cid)
    bySrc[src] = cid
    local p = cache[cid]
    if p then p.src = src; p.offline = nil end
end
function Store.CidOf(src) return bySrc[tonumber(src) or -1] end
function Store.SourceOf(cid)
    local p = cache[cid]
    return p and p.src or nil
end
function Store.OnlineCount()
    local n = 0
    for _ in pairs(bySrc) do n = n + 1 end
    return n
end
function Store.CachedCount()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end
function Store.Each(fn) for cid, p in pairs(cache) do fn(cid, p) end end

-- ── injuries ───────────────────────────────────────────────────────────────────────────────────

--- Stores a new injury (immediate insert: its id and idempotency key must exist at once).
--- Returns id or nil, error code.
function Store.InsertInjury(p, inj)
    local ok, id = pcall(Q.InsertInjury, {
        citizenid = p.cid, type = inj.type, subtype = inj.subtype, region = inj.region, structure = inj.structure,
        severity = inj.severity, stage = inj.stage, bleed_ml_min = clampNum(inj.bleed_ml_min, 0, 99999), pain = clampNum(inj.pain, 0, 10),
        mechanism = inj.mechanism, attrs = encode(inj.attrs), treatments = encode(inj.treatments),
        source_attacker_cid = inj.source_attacker_cid, idem_key = inj.idem_key, created_at = inj.created_at,
    })
    if not ok then
        if tostring(id):find('Duplicate', 1, true) then return nil, 'duplicate' end
        print('^1[pf-ambulancejob]^7 storing an injury failed: ' .. tostring(id))
        return nil, 'db_unavailable'
    end
    id = tonumber(id)
    if not id or id <= 0 then return nil, 'db_unavailable' end
    inj.id = id
    inj.citizenid = p.cid
    p.injuries[id] = inj
    return id
end

--- An injury that already holds this idempotency key: { id, citizenid, attrs } or nil.
function Store.FindByKey(key)
    for cid, p in pairs(cache) do
        for id, inj in pairs(p.injuries) do
            if inj.idem_key == key then return { id = id, citizenid = cid, attrs = inj.attrs } end
        end
    end
    if not Store.Ready() then return nil end
    local ok, row = pcall(Q.FindInjuryByKey, key)
    if ok and row then return { id = tonumber(row.id), citizenid = row.citizenid, attrs = decode(row.attrs) } end
    return nil
end

-- ── audit ──────────────────────────────────────────────────────────────────────────────────────

--- Queues one pf_med_events row (written with the next flush). actor = { cid, src, job } or nil.
function Store.Audit(cid, action, actor, detail)
    if #events >= MAX_EVENTS then table.remove(events, 1) end
    actor = type(actor) == 'table' and actor or {}
    if type(detail) == 'table' and (actor.kind or actor.label) then detail.by = { kind = actor.kind, label = actor.label } end
    local text = detail ~= nil and json.encode(detail) or nil
    if text and #text > 4096 then text = json.encode({ truncated = true, size = #text }) end
    events[#events + 1] = {
        citizenid = cid, action = tostring(action):sub(1, 32), actor_cid = actor.cid, actor_src = tonumber(actor.src),
        actor_job = type(actor.job) == 'string' and actor.job:sub(1, 32) or nil, detail = text, at = now(),
    }
end
function Store.PendingEvents() return #events end

-- ── write-behind ───────────────────────────────────────────────────────────────────────────────

local function patientRow(p)
    return {
        citizenid = p.cid, consciousness = p.consciousness, stage = p.stage, blood_ml = math.floor(clampNum(p.blood_ml, 0, 99999) + 0.5),
        hgb_factor = clampNum(p.hgb_factor, 0, 9.999), airway = p.airway or 'clear', breathing = clampNum(p.breathing, 0, 9.999),
        pain = clampNum(p.pain, 0, 10), temp_c = clampNum(p.temp_c, 0, 99.9), toxins = encode(p.toxins), drugs = encode(p.drugs),
        arrest_since = p.arrest_since, down_since = p.down_since, dead_at = p.dead_at, can_respawn_at = p.can_respawn_at,
        last_tick_at = p.last_tick_at, updated_at = p.updated_at or now(),
        hold_until = p.ctx and p.ctx.holdUntil and p.ctx.holdUntil > now() and p.ctx.holdUntil or nil,
    }
end

local function injuryRow(cid, inj)
    return {
        id = inj.id, citizenid = cid, type = inj.type, subtype = inj.subtype, region = inj.region, structure = inj.structure,
        severity = inj.severity, stage = inj.stage, bleed_ml_min = clampNum(inj.bleed_ml_min, 0, 99999), pain = clampNum(inj.pain, 0, 10),
        mechanism = inj.mechanism, attrs = encode(inj.attrs), treatments = encode(inj.treatments), source_attacker_cid = inj.source_attacker_cid,
        created_at = inj.created_at, stabilized_at = inj.stabilized_at, treated_at = inj.treated_at, recover_at = inj.recover_at,
        recovered_at = inj.recovered_at,
    }
end

--- Writes dirty patients (one statement), their changed injuries (one statement) and the queued
--- audit rows (one statement). `only` limits it to one citizen. Failed writes stay dirty.
function Store.Flush(only)
    if not Store.Ready() then return false end
    Store.stats.flushes = Store.stats.flushes + 1
    -- The dirty marks are taken before the database wait: a change made while the write is in
    -- flight marks the patient again and is written by the next pass instead of being lost.
    local taken, prows, irows = {}, {}, {}
    for cid in pairs(dirty) do
        if not only or cid == only then
            local p = cache[cid]
            dirty[cid] = nil
            if p then
                taken[cid] = p.dirtyInj
                p.dirtyInj, p.dirty = {}, false
                prows[#prows + 1] = patientRow(p)
                for id in pairs(taken[cid]) do
                    local inj = p.injuries[id]
                    if inj then irows[#irows + 1] = injuryRow(cid, inj) end
                end
            end
        end
    end
    local ok = true
    if #prows > 0 then
        local okP, errP = pcall(Q.UpsertPatients, prows)
        local okI, errI = true, nil
        if okP then okI, errI = pcall(Q.UpsertInjuries, irows) end
        if okP and okI then
            for cid, ids in pairs(taken) do
                local p = cache[cid]
                if p then
                    p.persisted = true
                    -- recovered injuries are history now: they leave the cache once written
                    for id in pairs(ids) do
                        local inj = p.injuries[id]
                        if inj and inj.stage == 'recovered' and not p.dirtyInj[id] then p.injuries[id] = nil end
                    end
                end
            end
        else
            ok = false
            print('^1[pf-ambulancejob]^7 saving patients failed: ' .. tostring(errP or errI))
            for cid, ids in pairs(taken) do
                local p = cache[cid]
                if p then
                    for id in pairs(ids) do p.dirtyInj[id] = true end
                    p.dirty, dirty[cid] = true, true
                end
            end
        end
    end
    if not only and #events > 0 then
        local batch = events
        events = {}
        local okE, errE = pcall(Q.InsertEvents, batch)
        if not okE then
            print('^1[pf-ambulancejob]^7 saving medical events failed: ' .. tostring(errE))
            for i = #batch, 1, -1 do if #events < MAX_EVENTS then table.insert(events, 1, batch[i]) end end
            ok = false
        end
    end
    return ok
end

--- Drops clean offline patients that were not used for a while (bounded cache).
function Store.EvictIdle(at)
    at = at or now()
    for cid, p in pairs(cache) do
        if not p.src and not dirty[cid] and not locks[cid] and (at - (p.touched or 0)) >= OFFLINE_TTL then
            cache[cid] = nil
            if PFMed.Engine then PFMed.Engine.Deactivate(cid) end
        end
    end
end

function Store.Evict(cid)
    cache[cid] = nil
    dirty[cid] = nil
    if PFMed.Engine then PFMed.Engine.Deactivate(cid) end
    if PFMed.Effects then PFMed.Effects.Forget(cid) end
end

--- One write-behind pass (the 10 s loop calls this).
function Store.WriteBehind()
    Store.Flush()
    Store.EvictIdle()
end

-- ── lifecycle ──────────────────────────────────────────────────────────────────────────────────

--- A character came online: load, catch up the offline time, start ticking if needed.
function Store.OnPlayerLoaded(src, cid)
    src = tonumber(src)
    if not src or src <= 0 or not Store.ValidCitizenId(cid) then return nil, 'bad_args' end
    local old = bySrc[src]
    if old and old ~= cid then Store.OnPlayerLeft(src) end
    bySrc[src] = cid
    local p, err = Store.Get(cid)
    if not p then
        -- still loading for someone else: the load attaches this player when it finishes
        if err == 'busy' then pendingAttach[cid] = src end
        return nil, err
    end
    p.src, p.offline = src, nil
    if PFMed.Engine then PFMed.Engine.OnLoaded(p, now()) end
    return p
end

--- A player left (drop or logout): write their state now and free the memory.
function Store.OnPlayerLeft(src)
    src = tonumber(src)
    local cid = src and bySrc[src]
    if not cid then return end
    bySrc[src] = nil
    local p = cache[cid]
    if not p then return end
    p.src = nil
    if PFMed.Engine then PFMed.Engine.Deactivate(cid) end
    if PFMed.Effects then PFMed.Effects.Forget(cid) end
    if Store.Flush(cid) and not dirty[cid] then
        cache[cid] = nil
    else
        p.offline, p.touched = true, now() -- stays dirty; the write-behind loop retries and then evicts
    end
end

function Store.FlushAll()
    return Store.Flush()
end

--- A deleted character: every pf_med_* row (and the legacy injury rows) goes.
function Store.DeleteCharacter(cid)
    if not Store.ValidCitizenId(cid) then return nil end
    for i = #events, 1, -1 do if events[i].citizenid == cid then table.remove(events, i) end end
    local p = cache[cid]
    if p and p.src then bySrc[p.src] = nil end
    Store.Evict(cid)
    if not Store.Ready() then return nil end
    return Q.DeleteCharacter(cid)
end

--- Retention sweep (daily).
function Store.Sweep(at)
    if not Store.Ready() then return nil end
    at = at or now()
    local c = cfg()
    local ok, res = pcall(Q.Sweep, at - (c.HistoryDays or 60) * 86400, at - (c.EventRetentionDays or 180) * 86400, c.SweepBatch or 500, 20)
    if not ok then print('^1[pf-ambulancejob]^7 medical retention sweep failed: ' .. tostring(res)) return nil end
    return res
end

--- Loads everyone already online (resource restart).
function Store.LoadOnline()
    local core = PFAmbulance and PFAmbulance.GetCore and PFAmbulance.GetCore()
    if not core then return 0 end
    local n = 0
    local ok, players = pcall(function() return core.Functions.GetQBPlayers() end)
    if not ok or type(players) ~= 'table' then return 0 end
    for src, Player in pairs(players) do
        local pd = type(Player) == 'table' and Player.PlayerData
        if pd and pd.citizenid then
            if Store.OnPlayerLoaded(tonumber(pd.source) or tonumber(src), pd.citizenid) then n = n + 1 end
        end
    end
    return n
end

-- ── diagnosis layers (what providers found and concluded; never the injuries themselves) ─────

Store.Modalities = {
    look = true, ask = true, palpate = true, auscultate = true, pupils = true, pulse = true, bp_cuff = true, spo2_probe = true,
    ecg = true, glucose = true, temperature = true, pain_scale = true, fast_us = true, xray = true, ct = true, labs = true,
    surgery = true,
}
Store.Certainty = { observed = true, suspected = true, confirmed = true }
Store.DiagnosisStatus = { suspected = true, confirmed = true, ruled_out = true }
Store.DiagnosisSource = { provider = true, imaging = true, lab = true, surgery = true }

local function cleanText(v, max)
    if v == nil then return nil end
    if type(v) ~= 'string' then return false end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

-- an injury id must belong to the citizen (a finding never points at someone else's wound)
local function injuryBelongs(cid, injuryId)
    local p = cache[cid]
    if p and p.injuries[injuryId] then return true end
    local ok, owner = pcall(Q.InjuryOwner, injuryId)
    return ok and owner == cid
end

--- Records a finding. f = { injuryId?, modality, region?, structure?, sign, certainty, value?, byCid?, byTier? }.
--- Returns id or nil, error code.
function Store.AddFinding(cid, f)
    if not Store.ValidCitizenId(cid) or type(f) ~= 'table' then return nil, 'bad_args' end
    if not Store.Ready() then return nil, 'db_unavailable' end
    local A = PFMed.Anatomy
    if not Store.Modalities[f.modality] or not Store.Certainty[f.certainty] then return nil, 'bad_args' end
    local sign = cleanText(f.sign, 48)
    local value = cleanText(f.value, 64)
    if not sign or value == false then return nil, 'bad_args' end
    if f.region ~= nil and not A.IsRegion(f.region) then return nil, 'bad_args' end
    if f.structure ~= nil and not A.IsStructure(f.structure) then return nil, 'bad_args' end
    local injuryId = f.injuryId and math.tointeger(tonumber(f.injuryId)) or nil
    if f.injuryId ~= nil and (not injuryId or not injuryBelongs(cid, injuryId)) then return nil, 'not_found' end
    local tier = f.byTier and math.tointeger(tonumber(f.byTier)) or nil
    if tier and (tier < 0 or tier > 5) then return nil, 'bad_args' end
    if f.byCid ~= nil and not Store.ValidCitizenId(f.byCid) then return nil, 'bad_args' end
    local ok, id = pcall(Q.InsertFinding, { citizenid = cid, injury_id = injuryId, modality = f.modality, region = f.region,
        structure = f.structure, sign = sign, certainty = f.certainty, value = value or nil, by_cid = f.byCid, by_tier = tier, at = now() })
    if not ok or not tonumber(id) then return nil, 'db_unavailable' end
    return tonumber(id)
end

function Store.ListFindings(cid, opts)
    if not Store.ValidCitizenId(cid) or not Store.Ready() then return {} end
    opts = opts or {}
    local limit = math.max(1, math.min(100, math.tointeger(tonumber(opts.limit)) or 50))
    local since = math.tointeger(tonumber(opts.since)) or 0
    local ok, rows = pcall(Q.ListFindings, cid, since, limit)
    return ok and rows or {}
end

--- Records a diagnosis. d = { injuryId?, structure?, injuryType, status, source, byCid?, note? }.
--- A provider may suspect or rule out; only imaging, labs or surgery confirm (architecture 4.2).
--- The diagnosis can be wrong: nothing here checks it against, or changes, the true injuries.
function Store.SetDiagnosis(cid, d)
    if not Store.ValidCitizenId(cid) or type(d) ~= 'table' then return nil, 'bad_args' end
    if not Store.Ready() then return nil, 'db_unavailable' end
    if not PFMed.Injuries.Types[d.injuryType] then return nil, 'bad_args' end
    if not Store.DiagnosisStatus[d.status] or not Store.DiagnosisSource[d.source] then return nil, 'bad_args' end
    if d.status == 'confirmed' and d.source == 'provider' then return nil, 'invalid_state' end
    if d.structure ~= nil and not PFMed.Anatomy.IsStructure(d.structure) then return nil, 'bad_args' end
    local note = cleanText(d.note, 255)
    if note == false then return nil, 'bad_args' end
    local injuryId = d.injuryId and math.tointeger(tonumber(d.injuryId)) or nil
    if d.injuryId ~= nil and (not injuryId or not injuryBelongs(cid, injuryId)) then return nil, 'not_found' end
    if d.byCid ~= nil and not Store.ValidCitizenId(d.byCid) then return nil, 'bad_args' end
    local ok, id = pcall(Q.InsertDiagnosis, { citizenid = cid, injury_id = injuryId, structure = d.structure, injury_type = d.injuryType,
        status = d.status, source = d.source, by_cid = d.byCid, note = note, at = now() })
    if not ok or not tonumber(id) then return nil, 'db_unavailable' end
    return tonumber(id)
end

function Store.ListDiagnoses(cid, opts)
    if not Store.ValidCitizenId(cid) or not Store.Ready() then return {} end
    opts = opts or {}
    local status = opts.status
    if status ~= nil and not Store.DiagnosisStatus[status] then return {} end
    local limit = math.max(1, math.min(100, math.tointeger(tonumber(opts.limit)) or 50))
    local ok, rows = pcall(Q.ListDiagnoses, cid, status, limit)
    return ok and rows or {}
end

-- ── events and loops ───────────────────────────────────────────────────────────────────────────

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local pd = type(Player) == 'table' and Player.PlayerData
    if not pd then return end
    Store.OnPlayerLoaded(pd.source, pd.citizenid)
end)

AddEventHandler('playerDropped', function()
    Store.OnPlayerLeft(source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    Store.OnPlayerLeft(src)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Store.FlushAll()
end)

-- pfm-core raises this server-only event after it deleted a character; a player cannot send it.
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    Store.DeleteCharacter(citizenid)
end)

if PFMed.Schema then
    PFMed.Schema.OnReady(function()
        Store.LoadOnline()
        Store.Sweep()
    end)
end

CreateThread(function()
    while true do
        Wait((cfg().WriteBehindSeconds or 10) * 1000)
        local ok, err = pcall(Store.WriteBehind)
        if not ok then print('^1[pf-ambulancejob]^7 medical write-behind failed: ' .. tostring(err)) end
    end
end)

CreateThread(function()
    while true do
        Wait((cfg().SweepHours or 24) * 3600 * 1000)
        Store.Sweep()
    end
end)
