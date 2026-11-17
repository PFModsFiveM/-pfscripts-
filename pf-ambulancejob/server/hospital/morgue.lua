-- Morgue and medical examiner (batch 20B; architecture 2 AJ, 4.1 deathRecorded, 4.11 AttachExternalRecord;
-- owner decision D9).
--
-- Ordinary deaths keep respawning (server/medical/downstate.lua and server/main.lua are untouched).
-- Only a character an admin marks deceased (permadeath / character kill, the admin command
-- /markdeceased with a confirmation step) enters the morgue:
--   * intake: one pf_med_death_records row per citizen (idem_key pf-ambulancejob:death:<cid>),
--     state 'intake', the time-of-death range and an intake snapshot taken from the medical engine
--     (level of consciousness, the physiological cause the engine logged, toxin levels). An online
--     character is sent back to character selection; a deceased character that loads again is too.
--   * autopsy: a medical examiner (on-duty staff of ExamTier, inside a morgue zone, after
--     ExamSeconds measured on the server) examines the body. Cause and the suggested manner are
--     built from the engine's own records only: the injuries present at death (pf_med_injuries,
--     ranked with the injury catalogue's lethal rules), the logged state changes (pf_med_events),
--     the toxin levels and the treatments given in the fatal window. The examiner may rule another
--     manner; the engine's suggestion is kept in the findings next to the ruling.
--   * release: the examined body leaves the morgue (state 'released').
--   * a death record linked to a police case or incident is attached to it through
--     pf-policemdt-DEV AttachExternalRecord (keyed by case + record: a repeat is a duplicate, so
--     failed attaches are retried, and re-sent once after a restart).
-- Every write is under a per-record / per-citizen lock taken before the first database wait.
-- Character deletion: unlinked death records go with the rest of the medical record; a record
-- attached to an MDT case stays as case evidence (the case refers to it by id).

PFHospital = PFHospital or {}
local H = PFHospital
H.Morgue = H.Morgue or {}
local M = H.Morgue
H.SQL = H.SQL or {}
local Q = H.SQL

-- Settings: Config.Hospital.Morgue overrides any of these (config_hospital.lua belongs to 20A).
M.DEFAULTS = {
    -- where the morgue is (server positions). The default is the vanilla morgue interior under
    -- Central Los Santos; `hospital` is stored with the record.
    Zones = {
        { id = 'pillbox_morgue', hospital = 'pillbox', label = 'County Morgue', coords = vector3(275.45, -1361.11, 24.54), radius = 12.0 },
    },
    ViewTier = 3,          -- list and read records (paramedic and up)
    ExamTier = 5,          -- autopsy and case links (physician = medical examiner)
    ReleaseTier = 3,       -- release an examined body
    ExamSeconds = 30,      -- the autopsy takes this long on the server
    ExamWindowSeconds = 600, -- a started autopsy must be finished within this time
    LookbackSeconds = 86400, -- state history read around a death
    RecentDeathSeconds = 3600, -- a death this recent (respawned since) is the death a CK refers to
    RetryDays = 7,         -- case links re-sent after a restart for records this new
    RetrySeconds = 60,
    MaxRetries = 30,
    ConfirmSeconds = 60,   -- /markdeceased must be confirmed within this time
    LoginKickDelayMs = 3000, -- a deceased character that loads is sent back to selection after this
    AdminAce = nil,        -- nil: Config.Medical.AdminAce or 'admin'
    ListLimit = 50,
    Callers = {
        GetDeathRecord = { ['pf-policemdt-DEV'] = true, ['pf-justice'] = true, ['pf-emsmdt'] = true },
        ListDeathRecords = { ['pf-emsmdt'] = true, ['pf-justice'] = true },
        IsDeceased = '*',
    },
}

function M.Cfg()
    local c = Config.Hospital and type(Config.Hospital.Morgue) == 'table' and Config.Hospital.Morgue or {}
    local out = {}
    for k, v in pairs(M.DEFAULTS) do if c[k] ~= nil then out[k] = c[k] else out[k] = v end end
    return out
end
local cfg = M.Cfg

local function now() return H.Now() end

M.PENDING_CAUSE = 'Pending examination'
M.MANNERS = { natural = true, accident = true, homicide = true, suicide = true, undetermined = true }
M.STATES = { intake = true, examined = true, released = true }
-- physiological causes the engine logs on a level change (physiology_model ArrestCause / lethal rules)
M.PHYS_LABEL = {
    hemorrhage = 'Exsanguination (blood loss)', hypotension = 'Circulatory shock', hypoxia = 'Asphyxia (lack of oxygen)',
    head_trauma = 'Traumatic brain injury', arrhythmia = 'Fatal cardiac arrhythmia',
}
local DOWN = { unconscious = true, arrest = true, dead = true }
-- manner the engine suggests from the mechanism of the fatal injury
local VIOLENT = { firearm = true, edged = true, blunt = true, explosion = true }
local ACCIDENT = { fall = true, vehicle = true, pedestrian = true, burn = true, electrical = true, drowning = true, environment = true,
    animal = true, crush = true, work = true }
local NATURAL = { illness = true, infection = true }
local TOXIN_LABEL = { ethanol = 'Ethanol', opioid = 'Opioid', stimulant = 'Stimulant', sedative = 'Sedative', cannabis = 'Cannabis',
    poison = 'Poison', carbon_monoxide = 'Carbon monoxide', food_poisoning = 'Food poisoning' }

local ready = false
M.deceased = {}      -- [cid] = record id (every citizen with a death record)
M.pending = {}       -- [recordId] = { ref, tries }: case links waiting for the MDT
M.exams = {}         -- [src] = { id, at }: an autopsy in progress (server clock)
M.confirm = {}       -- [src] = { cid, reason, name, expires }: /markdeceased waiting for confirm

-- ── SQL (the real-DB spec runs every statement) ─────────────────────────────────────────────

local REC_COLS = 'id, citizenid, cause, manner, tod_from, tod_to, examiner_cid, findings, case_ref, state, created_at, released_at, hospital_id, idem_key'

function Q.MorgueInsert(r)
    return MySQL.insert.await([[INSERT INTO pf_med_death_records (citizenid, cause, manner, tod_from, tod_to, findings, state, created_at,
        hospital_id, idem_key) VALUES (?, ?, 'pending', ?, ?, ?, 'intake', ?, ?, ?)]],
        { r.citizenid, r.cause, r.tod_from, r.tod_to, r.findings, r.created_at, r.hospital_id, r.idem_key })
end

function Q.MorgueByKey(key)
    return MySQL.single.await('SELECT ' .. REC_COLS .. ' FROM pf_med_death_records WHERE idem_key = ? LIMIT 1', { key })
end

function Q.MorgueGet(id)
    return MySQL.single.await('SELECT ' .. REC_COLS .. ' FROM pf_med_death_records WHERE id = ? LIMIT 1', { id })
end

function Q.MorgueLatestOf(cid)
    return MySQL.single.await('SELECT ' .. REC_COLS .. ' FROM pf_med_death_records WHERE citizenid = ? ORDER BY id DESC LIMIT 1', { cid })
end

function Q.MorgueListOf(cid, limit)
    return MySQL.query.await('SELECT ' .. REC_COLS .. ' FROM pf_med_death_records WHERE citizenid = ? ORDER BY id DESC LIMIT ?', { cid, limit or 10 }) or {}
end

--- Bodies in the morgue (not released yet), oldest first.
function Q.MorgueOpen(limit)
    return MySQL.query.await('SELECT ' .. REC_COLS .. " FROM pf_med_death_records WHERE state IN ('intake', 'examined') ORDER BY id LIMIT ?",
        { limit or 50 }) or {}
end

--- Every citizen with a death record (the deceased set; CKs are rare, the list is small).
function Q.MorgueDeceased(limit)
    return MySQL.query.await('SELECT citizenid, MAX(id) AS id FROM pf_med_death_records GROUP BY citizenid LIMIT ?', { limit or 5000 }) or {}
end

--- Examined once: only an intake row moves. Returns rows changed.
function Q.MorgueExamine(id, cause, manner, examiner, findings)
    return H.Affected(MySQL.update.await([[UPDATE pf_med_death_records SET cause = ?, manner = ?, examiner_cid = ?, findings = ?, state = 'examined'
        WHERE id = ? AND state = 'intake']], { cause, manner, examiner, findings, id }))
end

function Q.MorgueRelease(id, at)
    return H.Affected(MySQL.update.await("UPDATE pf_med_death_records SET state = 'released', released_at = ? WHERE id = ? AND state = 'examined'", { at, id }))
end

--- Sets the case link once (or again to the same value). Returns rows matched.
function Q.MorgueSetCase(id, ref)
    return H.Affected(MySQL.update.await('UPDATE pf_med_death_records SET case_ref = ? WHERE id = ? AND (case_ref IS NULL OR case_ref = ?)', { ref, id, ref }))
end

--- Clears a case link the MDT refused for good (only while it still holds that ref).
function Q.MorgueClearCase(id, ref)
    return H.Affected(MySQL.update.await('UPDATE pf_med_death_records SET case_ref = NULL WHERE id = ? AND case_ref = ?', { id, ref }))
end

--- An admin revokes a mistaken mark: only an unexamined, unlinked intake goes.
function Q.MorgueDeleteIntake(id)
    return H.Affected(MySQL.update.await("DELETE FROM pf_med_death_records WHERE id = ? AND state = 'intake' AND case_ref IS NULL", { id }))
end

--- A deleted character: unlinked records go; records attached to an MDT case stay as case evidence.
function Q.MorgueDeleteCharacter(cid)
    return tonumber(MySQL.update.await('DELETE FROM pf_med_death_records WHERE citizenid = ? AND case_ref IS NULL', { cid })) or 0
end

--- Case-linked records created since `since` (re-sent to the MDT after a restart; keyed there).
function Q.MorgueLinked(since, limit)
    return MySQL.query.await('SELECT id, case_ref FROM pf_med_death_records WHERE case_ref IS NOT NULL AND created_at >= ? ORDER BY id LIMIT ?',
        { since, limit or 200 }) or {}
end

--- Injuries present at the moment of death: created before it and not recovered before it.
function Q.MorgueInjuriesAt(cid, at, limit)
    return MySQL.query.await([[SELECT id, type, subtype, region, structure, severity, stage, mechanism, attrs, treatments, source_attacker_cid,
        created_at, recovered_at FROM pf_med_injuries WHERE citizenid = ? AND created_at <= ? AND (recovered_at IS NULL OR recovered_at > ?)
        ORDER BY severity DESC, created_at DESC, id DESC LIMIT ?]], { cid, at, at, limit or 40 }) or {}
end

--- The engine's logged level changes (action 'state', detail { from, to, cause }) in a window.
function Q.MorgueStateEvents(cid, from, to, limit)
    return MySQL.query.await([[SELECT detail, at FROM pf_med_events WHERE citizenid = ? AND action = 'state' AND at >= ? AND at <= ?
        ORDER BY at, id LIMIT ?]], { cid, from, to, limit or 200 }) or {}
end

--- Care given in the fatal window (perimortem interventions).
function Q.MorgueTreatments(cid, from, to, limit)
    return MySQL.query.await([[SELECT action, by_job, location, result, at FROM pf_med_treatments WHERE citizenid = ? AND at >= ? AND at <= ?
        ORDER BY at, id LIMIT ?]], { cid, from, to, limit or 20 }) or {}
end

--- Whether a character exists (players), nil when the lookup failed.
function Q.MorgueCharacter(cid)
    return MySQL.single.await('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid })
end

function Q.MorgueNames(cids)
    if #cids == 0 then return {} end
    local marks = {}
    for i = 1, #cids do marks[i] = '?' end
    return MySQL.query.await('SELECT citizenid, charinfo FROM players WHERE citizenid IN (' .. table.concat(marks, ', ') .. ')', cids) or {}
end

-- ── helpers ─────────────────────────────────────────────────────────────────────────────────

local function decode(s)
    if type(s) ~= 'string' or s == '' then return {} end
    local ok, v = pcall(json.decode, s)
    return ok and type(v) == 'table' and v or {}
end

local function validCid(cid)
    return type(cid) == 'string' and cid ~= '' and #cid <= 64 and cid:match('^[%w_%-]+$') ~= nil
end

local function db(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        print('^1[pf-ambulancejob]^7 morgue query failed: ' .. tostring(res))
        return nil, false
    end
    return res, true
end

-- injury attributes without the engine's internals (keys starting with '_', e.g. the key fingerprint)
local function publicAttrs(t)
    local out = {}
    for k, v in pairs(t or {}) do if type(k) == 'string' and k:sub(1, 1) ~= '_' then out[k] = v end end
    return out
end

local function nameOf(charinfo)
    local ci = type(charinfo) == 'table' and charinfo or decode(charinfo)
    local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n or nil
end

local function audit(cid, action, actor, detail)
    if PFMed and PFMed.Store and PFMed.Store.Audit then PFMed.Store.Audit(cid, 'morgue_' .. action, actor, detail) end
end

local function emit(name, ...)
    TriggerEvent('pf-ambulancejob:server:' .. name, ...)
end

function M.KeyOf(cid) return 'pf-ambulancejob:death:' .. cid end

local warned = {}
local function callerAllowed(name)
    local inv = GetInvokingResource()
    if inv == nil or inv == GetCurrentResourceName() then return true end
    local list = (cfg().Callers or {})[name]
    if list == '*' or (type(list) == 'table' and list[inv] == true) then return true end
    local t = now()
    if not warned[inv] or t - warned[inv] >= 60 then
        warned[inv] = t
        print(('^3[pf-ambulancejob]^7 %s refused for resource %s (Config.Hospital.Morgue.Callers)'):format(name, tostring(inv)))
    end
    return false
end

--- The morgue zone a server position is in (nil outside every zone).
function M.ZoneAt(pos)
    if not pos then return nil end
    for _, z in ipairs(cfg().Zones or {}) do
        if z.coords and H.Dist(pos, z.coords) <= (tonumber(z.radius) or 10.0) then return z end
    end
    return nil
end

--- A provider for a morgue action: on-duty staff of `tier`, inside a morgue zone (server position).
--- Returns P, zone | nil, error code, message.
function M.Provider(src, tier)
    local P, err, msg = H.Provider(src, nil, tier)
    if not P then return nil, err, msg end
    local zone = M.ZoneAt(H.Pos(src))
    if not zone then return nil, 'too_far', 'You must be in the morgue.' end
    return P, zone
end

-- ── engine evidence ────────────────────────────────────────────────────────────────────────

--- Last death episode in the logged level changes (rows ascending): { deathAt, onset, physCause }.
--- Walks back from the last change to 'dead' while the patient was already down; the first change
--- out of alert/altered is the onset.
function M.EpisodeFromEvents(rows)
    local list = {}
    for _, r in ipairs(rows or {}) do
        local d = decode(r.detail)
        if d.to then list[#list + 1] = { at = tonumber(r.at) or 0, from = d.from, to = d.to, cause = d.cause } end
    end
    local deathIdx
    for i = #list, 1, -1 do if list[i].to == 'dead' then deathIdx = i break end end
    if not deathIdx then return nil end
    local ep = { deathAt = list[deathIdx].at, onset = list[deathIdx].at }
    for i = deathIdx, 1, -1 do
        local e = list[i]
        ep.onset = e.at
        if not ep.physCause and M.PHYS_LABEL[e.cause] then ep.physCause = e.cause end
        if not DOWN[e.from] then break end
    end
    return ep
end

--- What the engine knows about a citizen's death at `at`: { declared, level, deathAt, onset,
--- physCause, toxins = { { name, level, unit, intensity } } }. `declared` = the engine saw no
--- death (the admin's mark is the time of death).
function M.Evidence(cid, at)
    local out = { declared = true, deathAt = at, onset = at, toxins = {} }
    local S = PFMed and PFMed.Store
    if S and S.Ready and S.Ready() then
        pcall(S.Flush) -- queued level changes and injury stages reach the tables first
        local p = S.Get(cid)
        if p then
            out.level = p.consciousness
            local tcfg = PFMed.Physiology and PFMed.Physiology.Cfg(Config.Medical).Toxins or {}
            for name, level in pairs(p.toxins or {}) do
                local lv, def = tonumber(level), tcfg[name]
                if lv and lv > 0 then
                    out.toxins[#out.toxins + 1] = { name = name, level = lv, unit = def and def.unit or nil,
                        intensity = def and def.severe and def.severe > 0 and math.floor(lv / def.severe * 100 + 0.5) / 100 or nil }
                end
            end
            table.sort(out.toxins, function(a, b) return (a.intensity or 0) > (b.intensity or 0) end)
            local rows = db(Q.MorgueStateEvents, cid, at - cfg().LookbackSeconds, at, 200) or {}
            local ep = M.EpisodeFromEvents(rows)
            if p.consciousness == 'dead' then
                out.declared = false
                out.deathAt = tonumber(p.dead_at) or (ep and ep.deathAt) or at
                local onset = tonumber(p.down_since) or tonumber(p.arrest_since) or out.deathAt
                if ep and ep.onset < onset then onset = ep.onset end
                out.onset = math.min(onset, out.deathAt)
                out.physCause = (ep and ep.physCause) or (M.PHYS_LABEL[p.cause] and p.cause) or nil
            elseif ep and at - ep.deathAt <= cfg().RecentDeathSeconds then
                out.declared = false
                out.deathAt, out.onset, out.physCause = ep.deathAt, ep.onset, ep.physCause
            end
        end
    end
    return out
end

local function typeLabel(t) local d = PFMed.Injuries.Types[t] return d and d.label or tostring(t) end
local function subLabel(t, s)
    local d = PFMed.Injuries.Types[t]
    local sub = d and d.subtypes and s and d.subtypes[s]
    return sub and sub.label or nil
end
local function placeLabel(structure, region)
    local A = PFMed.Anatomy
    local s = structure and A.Structures[structure]
    if s then return s.label end
    local r = region and A.Regions[region]
    return r and r.label or nil
end

--- Short text for an injury: "Gunshot wound (penetrating) of the heart".
function M.InjuryText(inj)
    local text = typeLabel(inj.type)
    local sub = subLabel(inj.type, inj.subtype)
    if sub then text = text .. ' (' .. sub:lower() .. ')' end
    local place = placeLabel(inj.structure, inj.region)
    if place then text = text .. ' of the ' .. place:lower() end
    return text
end

--- Ranks injuries by what the catalogue says kills (lethal / arrest rules), then severity, then
--- the newest. Returns the sorted list (rows decoded).
function M.RankInjuries(rows)
    local list = {}
    for _, r in ipairs(rows or {}) do
        local inj = { id = tonumber(r.id), type = r.type, subtype = r.subtype, region = r.region, structure = r.structure,
            severity = tonumber(r.severity) or 1, stage = r.stage, mechanism = r.mechanism,
            attrs = type(r.attrs) == 'table' and r.attrs or decode(r.attrs), treatments = type(r.treatments) == 'table' and r.treatments or decode(r.treatments),
            attackerCid = r.source_attacker_cid, createdAt = tonumber(r.created_at) or 0 }
        if PFMed.Injuries.Types[inj.type] then
            local okP, phys = pcall(PFMed.Injuries.Physiology, inj)
            inj.lethal = okP and type(phys) == 'table' and (phys.lethal or phys.arrest) and true or false
            inj.lethalCause = okP and type(phys) == 'table' and phys.cause or nil
            list[#list + 1] = inj
        end
    end
    table.sort(list, function(a, b)
        if a.lethal ~= b.lethal then return a.lethal end
        if a.severity ~= b.severity then return a.severity > b.severity end
        if a.createdAt ~= b.createdAt then return a.createdAt > b.createdAt end
        return (a.id or 0) > (b.id or 0)
    end)
    return list
end

--- Manner the engine's evidence points to (the examiner rules the final one).
function M.SuggestManner(cid, primary, toxins)
    if primary then
        local mech = primary.mechanism
        if primary.attackerCid and primary.attackerCid ~= '' then
            if primary.attackerCid ~= cid and VIOLENT[mech] then return 'homicide' end
            return 'undetermined'
        end
        if ACCIDENT[mech] then return 'accident' end
        if NATURAL[mech] then return 'natural' end
        return 'undetermined'
    end
    return 'undetermined'
end

local function clip(s, n) return #s > n and (s:sub(1, n - 3) .. '...') or s end

--- Cause of death text from the evidence (never invented: an unknown part is left out).
function M.CauseText(primary, physCause, toxins)
    local severeTox
    for _, t in ipairs(toxins or {}) do if (t.intensity or 0) >= 1 then severeTox = t break end end
    local toxText = severeTox and ((TOXIN_LABEL[severeTox.name] or severeTox.name) .. ' toxicity') or nil
    local text
    if primary then
        local inj = M.InjuryText(primary)
        if physCause and M.PHYS_LABEL[physCause] then text = M.PHYS_LABEL[physCause] .. ' due to ' .. inj:sub(1, 1):lower() .. inj:sub(2)
        else text = inj end
        if toxText then text = text .. '; contributing: ' .. toxText:lower() end
    elseif toxText then
        text = toxText
        if physCause and M.PHYS_LABEL[physCause] then text = M.PHYS_LABEL[physCause] .. ' due to ' .. toxText:lower() end
    elseif physCause and M.PHYS_LABEL[physCause] then
        text = M.PHYS_LABEL[physCause]
    else
        text = 'Undetermined: no fatal injury, toxin or physiological cause on record'
    end
    return clip(text, 128)
end

--- The autopsy report for a death record row: { cause, derivedManner, findings }.
function M.BuildReport(row)
    local cid = row.citizenid
    local deathAt = tonumber(row.tod_to) or tonumber(row.created_at) or now()
    local onset = tonumber(row.tod_from) or deathAt
    local intake = decode(row.findings).intake or {}
    if PFMed and PFMed.Store and PFMed.Store.Ready and PFMed.Store.Ready() then pcall(PFMed.Store.Flush) end
    local rows = db(Q.MorgueInjuriesAt, cid, deathAt, 40) or {}
    -- the injury rows of a deleted character are gone: the snapshot taken at intake stands in
    if #rows == 0 and type(intake.injuries) == 'table' then rows = intake.injuries end
    local ranked = M.RankInjuries(rows)
    local primary = ranked[1]
    local toxins = type(intake.toxins) == 'table' and intake.toxins or {}
    local physCause = intake.physCause
    if not physCause and primary and primary.lethal and M.PHYS_LABEL[primary.lethalCause] then physCause = primary.lethalCause end
    local injuries = {}
    for i, inj in ipairs(ranked) do
        if i > 20 then break end
        injuries[#injuries + 1] = { id = inj.id, type = inj.type, subtype = inj.subtype, region = inj.region, structure = inj.structure,
            severity = inj.severity, stage = inj.stage, mechanism = inj.mechanism, lethal = inj.lethal, text = M.InjuryText(inj),
            createdAt = inj.createdAt, attacker = inj.attackerCid and (inj.attackerCid == cid and 'self' or 'other') or nil }
    end
    local care = {}
    for _, t in ipairs(db(Q.MorgueTreatments, cid, onset - 1800, deathAt + 60, 20) or {}) do
        care[#care + 1] = { action = t.action, byJob = t.by_job, location = t.location, result = t.result, at = tonumber(t.at), atText = M.Stamp(t.at) }
    end
    return {
        cause = M.CauseText(primary, physCause, toxins),
        derivedManner = M.SuggestManner(cid, primary, toxins),
        findings = { injuries = injuries, primaryInjuryId = primary and primary.id or nil, physCause = physCause, toxins = toxins,
            interventions = care, declared = intake.declared == true, todFrom = onset, todTo = deathAt },
    }
end

-- ── records ─────────────────────────────────────────────────────────────────────────────────

--- A server clock time as text (client scripts have no os.date).
function M.Stamp(t)
    t = tonumber(t)
    if not t then return nil end
    return os.date('%Y-%m-%d %H:%M', t)
end

--- "from to to" text of a time-of-death range.
function M.TodText(from, to)
    from, to = tonumber(from), tonumber(to)
    if not to then return 'unknown' end
    if not from or from == to then return M.Stamp(to) end
    return M.Stamp(from) .. ' to ' .. M.Stamp(to)
end

--- Public shape of a death record. full = with findings.
function M.Public(r, full)
    local out = {
        id = tonumber(r.id), cid = r.citizenid, cause = r.cause, manner = r.manner, todFrom = tonumber(r.tod_from), todTo = tonumber(r.tod_to),
        examiner = r.examiner_cid, caseRef = r.case_ref, state = r.state, createdAt = tonumber(r.created_at),
        releasedAt = tonumber(r.released_at), hospitalId = r.hospital_id, todText = M.TodText(r.tod_from, r.tod_to),
    }
    if full then out.findings = decode(r.findings) end
    return out
end

local function recordEvent(r)
    return { id = tonumber(r.id), cid = r.citizenid, cause = r.cause, manner = r.manner, at = tonumber(r.created_at), examiner = r.examiner_cid,
        state = r.state, todFrom = tonumber(r.tod_from), todTo = tonumber(r.tod_to), caseRef = r.case_ref }
end

--- Death records of a citizen for GetMedicalRecord (newest first, findings included).
function M.ListForCitizen(cid)
    if not ready or not validCid(cid) then return {} end
    local out = {}
    for _, r in ipairs(db(Q.MorgueListOf, cid, 10) or {}) do out[#out + 1] = M.Public(r, true) end
    return out
end

function M.IsDeceased(cid)
    local id = validCid(cid) and M.deceased[cid] or nil
    return id ~= nil, id
end

-- ── MDT case links ─────────────────────────────────────────────────────────────────────────

--- Parses what an examiner typed: "12" / "case:12" -> case 12; "incident:ABC" / "ABC12" -> incident.
--- Returns stored ref ('case:12' | 'incident:ABC'), MDT target | nil.
function M.ParseCaseRef(v)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v):gsub('%s', '')
    local n = s:match('^case:(%d+)$') or s:match('^#?(%d+)$')
    if n then
        local id = math.tointeger(tonumber(n))
        if id and id >= 1 and id <= 2147483647 then return 'case:' .. id, { caseId = id } end
        return nil
    end
    local inc = s:match('^incident:([%w%-]+)$') or s:match('^([%a][%w%-]*)$')
    if inc and #inc <= 16 then return 'incident:' .. inc, { incidentId = inc } end
    return nil
end

local PERMANENT = { not_found = true, bad_args = true, not_allowed = true, conflict = true }

--- Attaches a death record to its case / incident. Returns 'ok' | 'retry' | 'refused', result.
function M.Attach(recordId, ref, actorSrc)
    local _, target = M.ParseCaseRef(ref)
    if not target then return 'refused', { error = 'bad_args' } end
    if not H.Started('pf-policemdt-DEV') then return 'retry', { error = 'offline' } end
    local ok, res = pcall(function()
        return exports['pf-policemdt-DEV']:AttachExternalRecord(target, { type = 'death_record', id = recordId },
            { note = 'Medical examiner death record #' .. recordId, actor = actorSrc and { src = actorSrc } or nil })
    end)
    if not ok or type(res) ~= 'table' then return 'retry', { error = 'db_unavailable' } end
    if res.ok then return 'ok', res end
    if PERMANENT[res.error] then return 'refused', res end
    return 'retry', res
end

function M.QueueAttach(recordId, ref)
    M.pending[recordId] = M.pending[recordId] or { ref = ref, tries = 0 }
    M.pending[recordId].ref = ref
end

--- One retry pass over the case links the MDT has not confirmed yet.
function M.RetryTick()
    if not ready then return end
    for id, p in pairs(M.pending) do
        local outcome, res = M.Attach(id, p.ref)
        if outcome == 'ok' then
            M.pending[id] = nil
        elseif outcome == 'refused' then
            M.pending[id] = nil
            local row = db(Q.MorgueGet, id)
            if db(Q.MorgueClearCase, id, p.ref) == 1 and row then
                audit(row.citizenid, 'link_refused', { kind = 'system', label = 'morgue' }, { id = id, ref = p.ref, error = res and res.error })
            end
        else
            p.tries = p.tries + 1
            if p.tries >= cfg().MaxRetries then
                M.pending[id] = nil
                print(('^3[pf-ambulancejob]^7 death record %d could not be attached to %s; it is re-sent after the next restart'):format(id, p.ref))
            end
        end
    end
end

-- ── intake (admin mark) ────────────────────────────────────────────────────────────────────

--- Sends an online deceased character back to character selection.
function M.SendToSelection(src)
    local P = H.Player(src)
    if not P then return false end
    H.Notify(src, 'This character has died. Returning to character selection.', 'error')
    local logout = (type(P.Functions) == 'table' and P.Functions.Logout) or P.Logout
    if logout and H.Callable(logout) then pcall(logout) end
    TriggerClientEvent('qb-multicharacter:client:chooseChar', src)
    return true
end

--- Marks a citizen deceased (character kill). Only the admin command calls this.
--- ctx = { actor = { kind = 'admin', src?, cid?, label? }, reason }. Returns a result table.
function M.MarkDeceased(cid, ctx)
    ctx = type(ctx) == 'table' and ctx or {}
    if not ready then return H.Fail('db_unavailable', 'The morgue is not ready.') end
    if not validCid(cid) then return H.Fail('bad_args', 'Unknown citizen id.') end
    local reason = H.Text(ctx.reason, 128)
    local res, lockErr = H.WithLock('morgue:cid:' .. cid, function()
        local key = M.KeyOf(cid)
        local existing, okE = db(Q.MorgueByKey, key)
        if not okE then return H.Fail('db_unavailable', 'The morgue database is unavailable.') end
        if existing then
            M.deceased[cid] = tonumber(existing.id)
            return { ok = true, duplicate = true, recordId = tonumber(existing.id) }
        end
        local char, okC = db(Q.MorgueCharacter, cid)
        if not okC then return H.Fail('db_unavailable', 'The character list is unavailable.') end
        if not char then return H.Fail('not_found', 'No character with that citizen id.') end
        local at = now()
        local ev = M.Evidence(cid, at)
        -- the injuries present at death, kept with the record (the autopsy reads the live rows,
        -- this copy only when a deleted character took them away)
        local snap = {}
        for _, r in ipairs(db(Q.MorgueInjuriesAt, cid, ev.deathAt, 40) or {}) do
            snap[#snap + 1] = { id = tonumber(r.id), type = r.type, subtype = r.subtype, region = r.region, structure = r.structure,
                severity = tonumber(r.severity), stage = r.stage, mechanism = r.mechanism, attrs = publicAttrs(decode(r.attrs)), treatments = decode(r.treatments),
                source_attacker_cid = r.source_attacker_cid, created_at = tonumber(r.created_at) }
        end
        local zone = (cfg().Zones or {})[1] or {}
        local actor = ctx.actor or { kind = 'admin' }
        local findings = json.encode({ intake = { declared = ev.declared, level = ev.level, physCause = ev.physCause, toxins = ev.toxins,
            injuries = snap, reason = reason, markedAt = at, by = actor.cid or actor.label or 'console' } })
        local id, okI = db(Q.MorgueInsert, { citizenid = cid, cause = M.PENDING_CAUSE, tod_from = ev.onset, tod_to = ev.deathAt, findings = findings,
            created_at = at, hospital_id = zone.hospital, idem_key = key })
        id = tonumber(id)
        if not okI or not id then
            -- a concurrent insert with the same key won: answer with that row
            local again = db(Q.MorgueByKey, key)
            if again then M.deceased[cid] = tonumber(again.id) return { ok = true, duplicate = true, recordId = tonumber(again.id) } end
            return H.Fail('db_unavailable', 'The death record could not be stored.')
        end
        M.deceased[cid] = id
        audit(cid, 'intake', actor, { id = id, reason = reason, declared = ev.declared, todFrom = ev.onset, todTo = ev.deathAt })
        -- an open hospital stay ends as deceased
        local A = H.Admissions
        local a = A and A.OpenOf and A.OpenOf(cid)
        if a and A.WithAdmission then
            pcall(A.WithAdmission, a.id, function(adm) return A.Close(adm, 'deceased', { actor = actor, reason = 'character_kill' }) end)
        end
        local row = { id = id, citizenid = cid, cause = M.PENDING_CAUSE, manner = 'pending', created_at = at, state = 'intake', tod_from = ev.onset, tod_to = ev.deathAt }
        emit('deathRecorded', recordEvent(row))
        local src = H.SourceOfCid(cid)
        if src then M.SendToSelection(src) end
        return { ok = true, recordId = id, todFrom = ev.onset, todTo = ev.deathAt, declared = ev.declared, name = nameOf(char.charinfo) }
    end)
    if res == nil then return H.Fail(lockErr or 'busy', 'That character is being processed; try again.') end
    return res
end

--- Undoes a mistaken mark while the body is unexamined and unlinked. Admin command only.
function M.Revoke(cid, ctx)
    ctx = type(ctx) == 'table' and ctx or {}
    if not ready then return H.Fail('db_unavailable', 'The morgue is not ready.') end
    if not validCid(cid) then return H.Fail('bad_args', 'Unknown citizen id.') end
    local res, lockErr = H.WithLock('morgue:cid:' .. cid, function()
        local row, ok = db(Q.MorgueByKey, M.KeyOf(cid))
        if not ok then return H.Fail('db_unavailable', 'The morgue database is unavailable.') end
        if not row then return H.Fail('not_found', 'That character is not marked deceased.') end
        local id = tonumber(row.id)
        return H.WithLock('morgue:rec:' .. id, function()
            if row.state ~= 'intake' or row.case_ref then
                return H.Fail('invalid_state', 'Only an unexamined record without a case link can be revoked.')
            end
            if db(Q.MorgueDeleteIntake, id) ~= 1 then return H.Fail('invalid_state', 'The record changed; it was not revoked.') end
            M.deceased[cid] = nil
            M.pending[id] = nil
            audit(cid, 'revoked', ctx.actor, { id = id, reason = H.Text(ctx.reason, 128) })
            emit('deathRevoked', { id = id, cid = cid })
            return { ok = true, recordId = id }
        end) or H.Fail('busy', 'The record is busy; try again.')
    end)
    if res == nil then return H.Fail(lockErr or 'busy', 'That character is being processed; try again.') end
    return res
end

-- ── staff actions (callbacks) ───────────────────────────────────────────────────────────────

local function withRecord(id, fn)
    id = H.Int(id, 1, 2147483647)
    if not id then return H.Fail('bad_args', 'Invalid record.') end
    local res, err = H.WithLock('morgue:rec:' .. id, function()
        local row, ok = db(Q.MorgueGet, id)
        if not ok then return H.Fail('db_unavailable', 'The morgue database is unavailable.') end
        if not row then return H.Fail('not_found', 'No such death record.') end
        return fn(row, id)
    end)
    if res == nil then return H.Fail(err or 'busy', 'The record is busy; try again.') end
    return res
end

--- Bodies in the morgue with names, for staff inside it.
function M.List(src)
    local P, err, msg = M.Provider(src, cfg().ViewTier)
    if not P then return H.Fail(err, msg) end
    local rows, ok = db(Q.MorgueOpen, cfg().ListLimit)
    if not ok then return H.Fail('db_unavailable', 'The morgue database is unavailable.') end
    local cids, list = {}, {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.citizenid end
    local names = {}
    for _, n in ipairs(db(Q.MorgueNames, cids) or {}) do names[n.citizenid] = nameOf(n.charinfo) end
    for _, r in ipairs(rows) do
        local pub = M.Public(r, false)
        pub.name = names[r.citizenid] or 'Unidentified'
        list[#list + 1] = pub
    end
    return { ok = true, list = list, tier = H.Tier(P), examTier = cfg().ExamTier, releaseTier = cfg().ReleaseTier }
end

--- One record with its findings.
function M.Get(src, id)
    local P, err, msg = M.Provider(src, cfg().ViewTier)
    if not P then return H.Fail(err, msg) end
    id = H.Int(id, 1, 2147483647)
    if not id then return H.Fail('bad_args', 'Invalid record.') end
    local row, ok = db(Q.MorgueGet, id)
    if not ok then return H.Fail('db_unavailable', 'The morgue database is unavailable.') end
    if not row then return H.Fail('not_found', 'No such death record.') end
    local pub = M.Public(row, true)
    local char = db(Q.MorgueCharacter, row.citizenid)
    pub.name = char and nameOf(char.charinfo) or 'Unidentified'
    audit(row.citizenid, 'read', H.ActorOf(src, P), { id = id })
    return { ok = true, record = pub, tier = H.Tier(P), examTier = cfg().ExamTier, releaseTier = cfg().ReleaseTier }
end

--- Starts an autopsy: the clock runs on the server; the preview is what the evidence shows now.
function M.AutopsyStart(src, id)
    local P, err, msg = M.Provider(src, cfg().ExamTier)
    if not P then return H.Fail(err, msg) end
    if H.Limited(src, 'morgue_exam', 1) then return H.Fail('rate_limited', 'Slow down.') end
    return withRecord(id, function(row, rid)
        if row.state ~= 'intake' then return H.Fail('invalid_state', 'This body was already examined (' .. tostring(row.state) .. ').') end
        local report = M.BuildReport(row)
        M.exams[src] = { id = rid, at = now() }
        return { ok = true, seconds = cfg().ExamSeconds, preview = { cause = report.cause, derivedManner = report.derivedManner, findings = report.findings } }
    end)
end

--- Finishes an autopsy. manner = the examiner's ruling (nil keeps the engine's suggestion).
function M.Autopsy(src, id, manner, note)
    local P, err, msg = M.Provider(src, cfg().ExamTier)
    if not P then return H.Fail(err, msg) end
    if manner ~= nil and manner ~= '' and not M.MANNERS[manner] then return H.Fail('bad_args', 'Unknown manner of death.') end
    if note ~= nil and type(note) ~= 'string' then return H.Fail('bad_args', 'Invalid note.') end
    local rid = H.Int(id, 1, 2147483647)
    local exam = M.exams[src]
    if not rid or not exam or exam.id ~= rid then return H.Fail('invalid_state', 'Start the autopsy first.') end
    local t = now()
    if t - exam.at < cfg().ExamSeconds then return H.Fail('too_soon', 'The autopsy is not finished.') end
    if t - exam.at > cfg().ExamWindowSeconds then M.exams[src] = nil return H.Fail('invalid_state', 'The autopsy took too long; start again.') end
    local actor = H.ActorOf(src, P)
    return withRecord(rid, function(row)
        if row.state ~= 'intake' then return H.Fail('invalid_state', 'This body was already examined.') end
        local report = M.BuildReport(row)
        local ruling = (manner ~= nil and manner ~= '') and manner or report.derivedManner
        local f = decode(row.findings)
        report.findings.derivedManner = report.derivedManner
        report.findings.note = H.Text(note, 500)
        report.findings.examinedAt = t
        f.autopsy = report.findings
        local text = json.encode(f)
        if db(Q.MorgueExamine, rid, report.cause, ruling, actor.cid, text) ~= 1 then
            return H.Fail('invalid_state', 'The record changed; it was not examined.')
        end
        M.exams[src] = nil
        row.cause, row.manner, row.examiner_cid, row.state = report.cause, ruling, actor.cid, 'examined'
        audit(row.citizenid, 'autopsy', actor, { id = rid, cause = report.cause, manner = ruling, derived = report.derivedManner })
        emit('deathRecorded', recordEvent(row))
        if row.case_ref then
            local outcome = M.Attach(rid, row.case_ref, src)
            if outcome == 'retry' then M.QueueAttach(rid, row.case_ref) end
        end
        return { ok = true, record = M.Public(row, false) }
    end)
end

--- Links a death record to a police case or incident (and attaches it in the MDT).
function M.LinkCase(src, id, refText)
    local P, err, msg = M.Provider(src, cfg().ExamTier)
    if not P then return H.Fail(err, msg) end
    if H.Limited(src, 'morgue_link', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local ref = M.ParseCaseRef(refText)
    if not ref then return H.Fail('bad_args', 'Enter a case number or an incident id.') end
    local actor = H.ActorOf(src, P)
    return withRecord(id, function(row, rid)
        if row.case_ref and row.case_ref ~= ref then return H.Fail('conflict', 'Already linked to ' .. row.case_ref .. '.') end
        local outcome, res = M.Attach(rid, ref, src)
        if outcome == 'refused' then
            return H.Fail(res and res.error or 'not_found', (res and res.message) or 'The MDT refused that case.')
        end
        if db(Q.MorgueSetCase, rid, ref) ~= 1 then return H.Fail('db_unavailable', 'The link could not be saved.') end
        if outcome == 'retry' then M.QueueAttach(rid, ref) else M.pending[rid] = nil end
        audit(row.citizenid, 'link', actor, { id = rid, ref = ref, mdt = outcome })
        return { ok = true, caseRef = ref, pending = outcome == 'retry' or nil }
    end)
end

--- Releases an examined body (to a funeral home / the family: the note says where).
function M.Release(src, id, note)
    local P, err, msg = M.Provider(src, cfg().ReleaseTier)
    if not P then return H.Fail(err, msg) end
    if note ~= nil and type(note) ~= 'string' then return H.Fail('bad_args', 'Invalid note.') end
    if H.Limited(src, 'morgue_release', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local actor = H.ActorOf(src, P)
    return withRecord(id, function(row, rid)
        if row.state ~= 'examined' then
            return H.Fail('invalid_state', row.state == 'intake' and 'The body has not been examined yet.' or 'The body was already released.')
        end
        local t = now()
        if db(Q.MorgueRelease, rid, t) ~= 1 then return H.Fail('invalid_state', 'The record changed; it was not released.') end
        audit(row.citizenid, 'release', actor, { id = rid, note = H.Text(note, 128) })
        return { ok = true, releasedAt = t }
    end)
end

-- ── exports ─────────────────────────────────────────────────────────────────────────────────

function M.ExportIsDeceased(cid)
    if not callerAllowed('IsDeceased') then return false end
    return M.IsDeceased(cid)
end

function M.ExportGetDeathRecord(id)
    if not callerAllowed('GetDeathRecord') then return H.Fail('not_allowed', 'This resource may not read death records.') end
    if not ready then return H.Fail('db_unavailable', 'The morgue is not ready.') end
    id = H.Int(id, 1, 2147483647)
    if not id then return H.Fail('bad_args', 'Invalid record.') end
    local row, ok = db(Q.MorgueGet, id)
    if not ok then return H.Fail('db_unavailable', 'The morgue database is unavailable.') end
    if not row then return H.Fail('not_found', 'No such death record.') end
    audit(row.citizenid, 'read', { kind = 'resource', label = tostring(GetInvokingResource() or 'self') }, { id = id })
    return { ok = true, record = M.Public(row, true) }
end

function M.ExportListDeathRecords(cid)
    if not callerAllowed('ListDeathRecords') then return H.Fail('not_allowed', 'This resource may not read death records.') end
    if not ready then return H.Fail('db_unavailable', 'The morgue is not ready.') end
    if not validCid(cid) then return H.Fail('bad_args', 'Unknown citizen id.') end
    local rows, ok = db(Q.MorgueListOf, cid, 10)
    if not ok then return H.Fail('db_unavailable', 'The morgue database is unavailable.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = M.Public(r, false) end
    return { ok = true, list = list }
end

exports('IsDeceased', function(cid) return M.ExportIsDeceased(cid) end)
exports('GetDeathRecord', function(id) return M.ExportGetDeathRecord(id) end)
exports('ListDeathRecords', function(cid) return M.ExportListDeathRecords(cid) end)

-- ── callbacks and admin commands ────────────────────────────────────────────────────────────

local function callback(name, fn)
    PFAmbulance.GetCore().Functions.CreateCallback('pf-ambulancejob:server:' .. name, function(source, cb, ...)
        local src = tonumber(source)
        if not src or src <= 0 then return cb(H.Fail('bad_args', 'Invalid source.')) end
        if not ready then return cb(H.Fail('db_unavailable', 'The morgue is not ready.')) end
        local ok, res = pcall(fn, src, ...)
        if not ok then
            print(('^1[pf-ambulancejob]^7 %s failed: %s'):format(name, tostring(res)))
            res = H.Fail('db_unavailable', 'Something went wrong.')
        end
        cb(res)
    end)
end

callback('morgueList', function(src) return M.List(src) end)
callback('morgueGet', function(src, id) return M.Get(src, id) end)
callback('morgueAutopsyStart', function(src, id) return M.AutopsyStart(src, id) end)
callback('morgueAutopsy', function(src, id, manner, note) return M.Autopsy(src, id, manner, note) end)
callback('morgueLinkCase', function(src, id, ref) return M.LinkCase(src, id, ref) end)
callback('morgueRelease', function(src, id, note) return M.Release(src, id, note) end)

--- Whether a command source may mark or revoke (console always; players need the ACE).
function M.IsAdmin(src)
    src = tonumber(src)
    if src == 0 then return true end
    if not src or src < 0 then return false end
    local ace = cfg().AdminAce or (Config.Medical and Config.Medical.AdminAce) or 'admin'
    return IsPlayerAceAllowed(src, ace) == true
end

local function adminActor(src)
    if tonumber(src) == 0 then return { kind = 'admin', label = 'console' } end
    local P = H.Player(src)
    return { kind = 'admin', src = src, cid = P and P.PlayerData.citizenid or nil, label = 'admin' }
end

local function say(src, text, kind)
    if tonumber(src) == 0 then print('[pf-ambulancejob] ' .. text) else H.Notify(src, text, kind) end
end

--- /markdeceased <id|citizenid> <reason...>, then /markdeceased confirm within ConfirmSeconds.
function M.CommandMark(src, args)
    src = tonumber(src) or -1
    if not M.IsAdmin(src) then return say(src, 'You may not do that.', 'error') end
    args = type(args) == 'table' and args or {}
    local first = tostring(args[1] or '')
    if first:lower() == 'confirm' then
        local c = M.confirm[src]
        M.confirm[src] = nil
        if not c or now() > c.expires then return say(src, 'Nothing to confirm (or it expired).', 'error') end
        local res = M.MarkDeceased(c.cid, { actor = adminActor(src), reason = c.reason })
        if not res.ok then return say(src, res.message or 'Refused.', 'error') end
        return say(src, ('%s (%s) is deceased: death record #%d%s.'):format(c.name or c.cid, c.cid, res.recordId,
            res.duplicate and ' (already recorded)' or ''), 'success')
    end
    local cid
    local sid = math.tointeger(tonumber(first))
    if sid and sid > 0 then
        local P = H.Player(sid)
        if not P then return say(src, 'No player with that id.', 'error') end
        cid = P.PlayerData.citizenid
    elseif validCid(first) then
        cid = first
    else
        return say(src, 'Usage: /markdeceased <player id | citizen id> <reason>', 'error')
    end
    local reason = H.Text(table.concat(args, ' ', 2), 128)
    if not reason then return say(src, 'Give a reason (it is kept with the death record).', 'error') end
    if M.IsDeceased(cid) then return say(src, cid .. ' is already marked deceased.', 'error') end
    local char = db(Q.MorgueCharacter, cid)
    if not char then return say(src, 'No character with that citizen id.', 'error') end
    M.confirm[src] = { cid = cid, reason = reason, name = nameOf(char.charinfo), expires = now() + cfg().ConfirmSeconds }
    say(src, ('Character kill: %s (%s). This is permanent. Type /markdeceased confirm within %d seconds.'):format(
        nameOf(char.charinfo) or 'Unknown', cid, cfg().ConfirmSeconds), 'primary')
end

--- /revokedeceased <citizenid> <reason...>
function M.CommandRevoke(src, args)
    src = tonumber(src) or -1
    if not M.IsAdmin(src) then return say(src, 'You may not do that.', 'error') end
    args = type(args) == 'table' and args or {}
    local cid = tostring(args[1] or '')
    if not validCid(cid) then return say(src, 'Usage: /revokedeceased <citizen id> <reason>', 'error') end
    local res = M.Revoke(cid, { actor = adminActor(src), reason = table.concat(args, ' ', 2) })
    if not res.ok then return say(src, res.message or 'Refused.', 'error') end
    say(src, ('Death record #%d of %s revoked.'):format(res.recordId, cid), 'success')
end

function M.RegisterCommands()
    local QB = PFAmbulance.GetCore()
    if not QB.Commands or not QB.Commands.Add then return end
    QB.Commands.Add('markdeceased', 'Admin: character kill (permadeath) -> morgue', { { name = 'id', help = 'Player id or citizen id (or confirm)' },
        { name = 'reason', help = 'Reason' } }, false, function(source, args) M.CommandMark(source, args) end, 'admin')
    QB.Commands.Add('revokedeceased', 'Admin: undo a mistaken character kill (before the autopsy)', { { name = 'citizenid', help = 'Citizen id' },
        { name = 'reason', help = 'Reason' } }, true, function(source, args) M.CommandRevoke(source, args) end, 'admin')
end

-- ── lifecycle ───────────────────────────────────────────────────────────────────────────────

--- A deceased character that loaded is sent back to character selection (called after a delay so
--- the character selection resource finished its own load steps).
function M.EnforceDeceased(src, cid)
    local P = H.Player(src)
    if not P or P.PlayerData.citizenid ~= cid then return false end
    if not M.IsDeceased(cid) then return false end
    return M.SendToSelection(src)
end

function M.OnPlayerLoaded(src, cid)
    if not ready or not M.IsDeceased(cid) then return false end
    SetTimeout(cfg().LoginKickDelayMs, function() M.EnforceDeceased(src, cid) end)
    return true
end

--- pfm-core deleted a character: unlinked death records go, case-linked ones stay (case evidence).
function M.OnCharacterDeleted(cid)
    if not validCid(cid) then return nil end
    M.deceased[cid] = nil
    if not ready then return nil end
    return db(Q.MorgueDeleteCharacter, cid)
end

--- Loads the deceased set and re-sends recent case links (the MDT answers a repeat as duplicate).
function M.Start()
    local rows, ok = db(Q.MorgueDeceased, 5000)
    if not ok then return false end
    M.deceased = {}
    for _, r in ipairs(rows) do M.deceased[r.citizenid] = tonumber(r.id) end
    for _, r in ipairs(db(Q.MorgueLinked, now() - cfg().RetryDays * 86400, 200) or {}) do M.QueueAttach(tonumber(r.id), r.case_ref) end
    ready = true
    return true
end

function M.Ready() return ready end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local pd = type(Player) == 'table' and Player.PlayerData
    if type(pd) ~= 'table' then return end
    M.OnPlayerLoaded(pd.source, pd.citizenid)
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then M.exams[src], M.confirm[src] = nil, nil end
end)

-- pfm-core raises this server-only event after it deleted a character; a player cannot send it.
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    M.OnCharacterDeleted(citizenid)
end)

CreateThread(function()
    M.RegisterCommands()
    if PFMed and PFMed.Schema and PFMed.Schema.OnReady then
        PFMed.Schema.OnReady(function() M.Start() end)
    end
    while true do
        Wait(cfg().RetrySeconds * 1000)
        local ok, e = pcall(M.RetryTick)
        if not ok then print('^1[pf-ambulancejob]^7 morgue retry failed: ' .. tostring(e)) end
    end
end)
