-- ============================================================================
-- PF Police MDT - records extension (batch 18F)
-- ============================================================================
-- Loaded after server/main.lua. Owns:
--   * warrants v2: server id and expiry, a real suspect citizen id, type (arrest/search/bench),
--     judge review through pf-justice RequestWarrantReview when it exists, supervisor approval
--     otherwise (Config.Warrants.SupervisorApproval), served -> custody link, expiry sweep;
--   * the BOLO board (people and vehicles) with expiry and broadcast to on-duty units and ALPR;
--   * vehicle flags from a whitelist, cached for GetPlateFlags (PJ ALPR) and announced with the
--     server event pf_mdt:server:plateFlagsChanged;
--   * pf_mdt_vehicle_activity rows (MDT flag/BOLO changes, ALPR hits reported by pfm-policejob);
--   * pf_mdt_record_audit: who read or changed a citizen, incident, report, warrant, BOLO or vehicle;
--   * audited soft-delete (expungement) of incidents and sentences for pf-government / pf-justice.
-- Every table comes from server/schema.lua (v8). Queries use oxmysql's MySQL.*.await, so they run
-- inside the handler's own thread.

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtRecords = PFMdtRecords or {}
local R = PFMdtRecords
local Access = PFMdtAccess
local callable = Access.Callable

local function T(v, n) return (Access.Text(v, n):gsub('^%s+', ''):gsub('%s+$', '')) end
local function now() return os.time() end
local function rows(v) return type(v) == 'table' and v or {} end
local function affected(v)
    if type(v) == 'table' then v = v.affectedRows or v.changedRows end
    return tonumber(v) or 0
end
local function cfg(section)
    local c = Config and Config[section]
    return type(c) == 'table' and c or {}
end
local function decodeList(v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return {} end
    local ok, out = pcall(json.decode, v)
    return ok and type(out) == 'table' and out or {}
end

-- The calling officer from the server's player: cid, display name, job and grade.
local function actorOf(src)
    local job, P = Access.Job(src)
    if not P or not P.PlayerData then return nil end
    local ci = P.PlayerData.charinfo or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return { src = src, cid = P.PlayerData.citizenid, name = name ~= '' and name or 'Officer',
        job = job and job.name or nil, grade = job and job.grade or 0 }
end
R.ActorOf = actorOf

local function notify(src, text, kind)
    if src and tonumber(src) and tonumber(src) > 0 then TriggerClientEvent('QBCore:Notify', src, text, kind or 'primary') end
end

-- Every on-duty officer of an allowed job (for broadcasts).
local function onDutyOfficers()
    local out = {}
    for _, P in pairs(QBCore.Functions.GetQBPlayers() or {}) do
        local pd = P and P.PlayerData
        local job = pd and pd.job
        if job and Config.AllowedJobs and Config.AllowedJobs[job.name] and job.onduty then out[#out + 1] = pd.source end
    end
    return out
end
R.OnDutyOfficers = onDutyOfficers

-- ── record audit ─────────────────────────────────────────────────────────────

local AUDIT_ENTITIES = { citizen = true, incident = true, report = true, warrant = true, bolo = true, vehicle = true,
    cctv = true, sentence = true }
local AUDIT_ACTIONS = { read = true, create = true, update = true, delete = true, status = true }
local readSeen, readSeenCount = {}, 0

--- One audit row. `by` is a player source, or { cid, job } for a server caller (pf-justice, the
--- sweep). Reads of the same record by the same officer are written once per
--- Config.RecordAudit.ReadDedupeSeconds so paging through a profile does not flood the table.
--- Returns true when a row was written (or would be: the insert is not waited for).
function R.Audit(by, entity, entityId, action, detail)
    if not AUDIT_ENTITIES[entity] or not AUDIT_ACTIONS[action] then return false end
    entityId = Access.Text(entityId, 64)
    if entityId == '' then return false end
    local cid, job
    if type(by) == 'table' then
        cid, job = Access.Text(by.cid, 64), by.job and Access.Text(by.job, 32) or nil
    else
        local a = actorOf(by)
        if not a then return false end
        cid, job = a.cid, a.job
    end
    if not cid or cid == '' then return false end
    local t = now()
    if action == 'read' then
        local key = cid .. '|' .. entity .. '|' .. entityId
        local window = tonumber(cfg('RecordAudit').ReadDedupeSeconds) or 300
        if readSeen[key] and t - readSeen[key] < window then return false end
        if readSeenCount > 5000 then readSeen, readSeenCount = {}, 0 end
        if not readSeen[key] then readSeenCount = readSeenCount + 1 end
        readSeen[key] = t
    end
    local d = nil
    if detail ~= nil then
        d = type(detail) == 'table' and json.encode(detail) or tostring(detail)
        if #d > 4000 then d = d:sub(1, 4000) end
    end
    MySQL.insert('INSERT INTO pf_mdt_record_audit (entity, entity_id, action, by_cid, by_job, detail, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { entity, entityId, action, cid, job, d, t })
    return true
end

--- Rows for one record (newest first), for supervisors (pf_mdt:audit:list).
function R.ListAudit(entity, entityId, limit)
    if not AUDIT_ENTITIES[entity] then return {} end
    limit = math.max(1, math.min(tonumber(limit) or 50, 200))
    return rows(MySQL.query.await('SELECT entity, entity_id, action, by_cid, by_job, detail, at FROM pf_mdt_record_audit WHERE entity = ? AND entity_id = ? ORDER BY id DESC LIMIT ' .. math.floor(limit),
        { entity, Access.Text(entityId, 64) }))
end

-- ── plates, flags and the GetPlateFlags cache ────────────────────────────────

--- A plate as GTA shows it: upper case, outer spaces trimmed, letters/digits/inner spaces, 1-8 chars.
function R.NormalizePlate(p)
    if type(p) ~= 'string' and type(p) ~= 'number' then return nil end
    local s = tostring(p):upper():gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' or #s > 8 or not s:match('^[%w ]+$') then return nil end
    return s
end
local normPlate = R.NormalizePlate

local function flagWhitelist()
    local out = {}
    for _, f in ipairs(type(Config.VehicleFlags) == 'table' and Config.VehicleFlags or { 'BOLO', 'DANGEROUS', 'STOLEN', 'IMPOUNDED', 'SEIZED' }) do
        out[tostring(f):upper()] = true
    end
    return out
end

R.PlateCache = R.PlateCache or {}   -- plate -> { flags = { FLAG = true }, bolos = { [id] = true } }
R.PlateCacheLoaded = false

local function plateEntry(plate)
    local e = R.PlateCache[plate]
    if not e then e = { flags = {}, bolos = {} } R.PlateCache[plate] = e end
    return e
end

--- Rebuilds one plate (or every plate when plate is nil) from the database.
function R.RefreshPlate(plate)
    local flagRows, boloRows
    if plate then
        flagRows = rows(MySQL.query.await('SELECT plate, flag FROM pf_mdt_vehicle_flags WHERE plate = ?', { plate }))
        boloRows = rows(MySQL.query.await("SELECT id, plate FROM pf_mdt_bolos WHERE kind = 'vehicle' AND status = 'active' AND plate = ? AND expires_at > ?", { plate, now() }))
        R.PlateCache[plate] = nil
    else
        flagRows = rows(MySQL.query.await('SELECT plate, flag FROM pf_mdt_vehicle_flags', {}))
        boloRows = rows(MySQL.query.await("SELECT id, plate FROM pf_mdt_bolos WHERE kind = 'vehicle' AND status = 'active' AND expires_at > ?", { now() }))
        R.PlateCache = {}
    end
    local allowed = flagWhitelist()
    for _, r in ipairs(flagRows) do
        local p, f = normPlate(r.plate), tostring(r.flag or ''):upper()
        if p and allowed[f] then plateEntry(p).flags[f] = true end
    end
    for _, r in ipairs(boloRows) do
        local p = normPlate(r.plate)
        if p and tonumber(r.id) then plateEntry(p).bolos[tonumber(r.id)] = true end
    end
    if not plate then R.PlateCacheLoaded = true end
end

--- { flags = { 'BOLO', 'STOLEN', ... } (sorted), boloIds = { ... } } for a plate.
function R.GetPlateFlags(plate)
    plate = normPlate(plate)
    local out = { flags = {}, boloIds = {} }
    if not plate then return out end
    if not R.PlateCacheLoaded then R.RefreshPlate(plate) end
    local e = R.PlateCache[plate]
    if not e then return out end
    local set = {}
    for f in pairs(e.flags) do set[f] = true end
    for id in pairs(e.bolos) do out.boloIds[#out.boloIds + 1] = id end
    if #out.boloIds > 0 then set.BOLO = true end
    for f in pairs(set) do out.flags[#out.flags + 1] = f end
    table.sort(out.flags)
    table.sort(out.boloIds)
    return out
end

local function plateChanged(plate)
    R.RefreshPlate(plate)
    local flags = R.GetPlateFlags(plate)
    TriggerEvent('pf_mdt:server:plateFlagsChanged', plate, flags)
    return flags
end

local ACTIVITY_TYPES = { flag_set = true, flag_cleared = true, bolo = true, bolo_cleared = true, strike = true,
    alpr_hit = true, alpr_read = true, impound = true, traffic_stop = true, citation = true }
local activitySeen = {}

--- One pf_mdt_vehicle_activity row (shown on the vehicle profile; the latest ALPR row is "last seen").
--- spec = { type, location?, officerCid?, officerName?, referenceId? }. ALPR rows of one plate are
--- kept at most one per Config.PlateActivity.MinSeconds (a car parked next to a reader).
function R.PlateActivity(plate, spec)
    plate = normPlate(plate)
    if not plate or type(spec) ~= 'table' or not ACTIVITY_TYPES[spec.type] then return false, 'bad_args' end
    if spec.type == 'alpr_hit' or spec.type == 'alpr_read' then
        local key, t = plate .. '|' .. spec.type, now()
        local min = tonumber(cfg('PlateActivity').MinSeconds) or 60
        if activitySeen[key] and t - activitySeen[key] < min then return false, 'duplicate' end
        activitySeen[key] = t
    end
    MySQL.insert('INSERT INTO pf_mdt_vehicle_activity (plate, type, timestamp, location, officer, officerName, referenceId) VALUES (?, ?, NOW(), ?, ?, ?, ?)',
        { plate, spec.type, spec.location and Access.Text(spec.location, 128) or nil, spec.officerCid and Access.Text(spec.officerCid, 64) or nil,
          spec.officerName and Access.Text(spec.officerName, 128) or nil, spec.referenceId and Access.Text(spec.referenceId, 64) or nil })
    return true
end

--- Sets the plate's flag (single-select, as the vehicle page offers it). Returns ok, error.
function R.SetVehicleFlag(src, data)
    local a = actorOf(src)
    if not a or type(data) ~= 'table' then return false, 'bad_args' end
    local plate = normPlate(data.plate)
    local flag = type(data.flag) == 'string' and data.flag:upper():gsub('^%s+', ''):gsub('%s+$', '') or ''
    if not plate then return false, 'bad_plate' end
    if not flagWhitelist()[flag] then return false, 'bad_flag' end
    MySQL.update.await('DELETE FROM pf_mdt_vehicle_flags WHERE plate = ?', { plate })
    MySQL.insert.await('INSERT INTO pf_mdt_vehicle_flags (plate, flag) VALUES (?, ?)', { plate, flag })
    R.Audit(src, 'vehicle', plate, 'update', { flag = flag })
    R.PlateActivity(plate, { type = 'flag_set', officerCid = a.cid, officerName = a.name, referenceId = flag })
    return true, nil, plateChanged(plate)
end

function R.ClearVehicleFlag(src, data)
    local a = actorOf(src)
    if not a or type(data) ~= 'table' then return false, 'bad_args' end
    local plate = normPlate(data.plate)
    if not plate then return false, 'bad_plate' end
    local n = affected(MySQL.update.await('DELETE FROM pf_mdt_vehicle_flags WHERE plate = ?', { plate }))
    if n == 0 then return false, 'not_found' end
    R.Audit(src, 'vehicle', plate, 'update', { flag = false })
    R.PlateActivity(plate, { type = 'flag_cleared', officerCid = a.cid, officerName = a.name })
    return true, nil, plateChanged(plate)
end

-- ── warrants ─────────────────────────────────────────────────────────────────

local WARRANT_COLS = 'id, warrantId, suspectCitizenId, suspectName, charges, officers, witnesses, issuedBy, title, narrative, status, '
    .. 'createdAt, expiresAt, UNIX_TIMESTAMP(expiresAt) AS expires_ts, warrant_type, approval_state, approved_by, review_id, served_custody_id, address'

local function warrantTypes()
    local t = cfg('Warrants').Types
    if type(t) == 'table' and next(t) then return t end
    return { arrest = true, search = true, bench = true }
end

local function publicWarrant(r)
    if not r then return nil end
    return {
        id = tonumber(r.id), warrantId = r.warrantId, type = r.warrant_type or 'arrest', suspectCitizenId = r.suspectCitizenId,
        suspectName = r.suspectName, charges = decodeList(r.charges), officers = decodeList(r.officers),
        witnesses = decodeList(r.witnesses), issuedBy = r.issuedBy, title = r.title, narrative = r.narrative,
        status = r.status, approvalState = r.approval_state or 'legacy', approvedBy = r.approved_by,
        reviewId = tonumber(r.review_id), servedCustodyId = tonumber(r.served_custody_id), address = r.address,
        createdAt = r.createdAt, expiresAt = r.expiresAt, expiresTs = tonumber(r.expires_ts),
    }
end
R.PublicWarrant = publicWarrant

function R.GetWarrantRow(warrantId)
    warrantId = Access.Text(warrantId, 16)
    if warrantId == '' then return nil end
    return MySQL.single.await('SELECT ' .. WARRANT_COLS .. ' FROM pf_mdt_warrants WHERE warrantId = ? LIMIT 1', { warrantId })
end

local function warrantChanged(warrantId, change)
    local w = publicWarrant(R.GetWarrantRow(warrantId))
    if w then TriggerEvent('pf_mdt:server:warrantChanged', w, change) end
    return w
end

-- name of a citizen from the live player or the players row (nil when the citizen does not exist)
local function citizenName(cid)
    local P = QBCore.Functions.GetPlayerByCitizenId and QBCore.Functions.GetPlayerByCitizenId(cid)
    local ci = P and P.PlayerData and P.PlayerData.charinfo
    if not ci then
        local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid })
        if not row then return nil end
        ci = decodeList(row.charinfo)
    end
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or cid
end
R.CitizenName = citizenName

--- A citizen id from free text: an existing citizen id, or the one citizen with exactly this
--- "firstname lastname". Returns cid | nil, 'ambiguous' | nil.
function R.ResolveCitizen(text)
    text = T(text, 128)
    if text == '' then return nil end
    local list = rows(MySQL.query.await([[SELECT citizenid FROM players WHERE citizenid = ?
        OR CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) = ? LIMIT 3]], { text, text }))
    for _, r in ipairs(list) do if r.citizenid == text then return text end end
    if #list == 1 then return list[1].citizenid end
    if #list > 1 then return nil, 'ambiguous' end
    return nil
end

local function newWarrantId()
    return ('W%s%04d'):format(os.date('%y%m%d', now()), math.random(0, 9999))
end

local function justiceStarted()
    return GetResourceState('pf-justice') == 'started'
end

-- Files the judge review (contract 19A). Until pf-justice has RequestWarrantReview the call fails
-- inside pcall and the warrant stays pending_approval for a supervisor (or a later judge resource).
local function requestReview(w, actor)
    if not justiceStarted() then return nil end
    local ok, res = pcall(function()
        return exports['pf-justice']:RequestWarrantReview({
            warrantId = w.warrantId, type = w.type, targetCid = w.suspectCitizenId, address = w.address,
            affidavit = w.narrative, requestedBy = actor.cid,
        }, { key = 'pf-policemdt:warrant:' .. w.warrantId .. ':review' })
    end)
    if not ok or type(res) ~= 'table' or not res.ok or not tonumber(res.reviewId) then return nil end
    MySQL.update.await('UPDATE pf_mdt_warrants SET review_id = ? WHERE warrantId = ? AND review_id IS NULL', { tonumber(res.reviewId), w.warrantId })
    return tonumber(res.reviewId)
end

-- One pending_approval warrant row with a fresh server id (INSERT IGNORE retried on an id clash).
local function insertWarrant(f)
    for _ = 1, 6 do
        local candidate = newWarrantId()
        local id = MySQL.insert.await([[INSERT IGNORE INTO pf_mdt_warrants (warrantId, suspectCitizenId, suspectName, charges, officers, witnesses,
            issuedBy, title, narrative, status, createdAt, expiresAt, warrant_type, approval_state, address)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), ?, ?, 'pending_approval', ?)]],
            { candidate, f.cid, f.suspectName, f.charges, f.officers, f.witnesses, f.issuedBy, f.title, f.narrative, f.expiresAt, f.type, f.address })
        if tonumber(id) and tonumber(id) > 0 then return candidate end
    end
    return nil
end

local function expiryFor(wtype, wanted)
    local wcfg = cfg('Warrants')
    local maxDays = math.max(1, tonumber(wcfg.MaxDays) or 30)
    local defaults = type(wcfg.DefaultDays) == 'table' and wcfg.DefaultDays or {}
    local days = math.floor(tonumber(wanted) or tonumber(defaults[wtype]) or 7)
    days = math.max(1, math.min(days, maxDays))
    return os.date('%Y-%m-%d %H:%M:%S', now() + days * 86400), days
end

--- Creates a warrant request from an on-duty officer (the access gate checked duty and grade).
--- data = { type = 'arrest'|'search'|'bench', suspectCitizenId, address, title, narrative,
---          charges, officers, witnesses, expiryDays }. Id, expiry and suspect name come from the
--- server; the warrant starts 'pending' / 'pending_approval'.
function R.CreateWarrant(src, data)
    local a = actorOf(src)
    if not a then return { success = false, error = 'no_access' } end
    if type(data) ~= 'table' then return { success = false, error = 'bad_args' } end
    if not Access.AllowRate(src, 'warrantCreate', 3000) then return { success = false, error = 'rate_limited' } end
    local wtype = type(data.type or data.warrantType) == 'string' and (data.type or data.warrantType):lower() or 'arrest'
    if not warrantTypes()[wtype] then return { success = false, error = 'bad_type' } end

    local cid = T(data.suspectCitizenId or data.citizenId, 64)
    local address = T(data.address, 128)
    if cid == '' and wtype ~= 'search' then
        -- the current warrant page sends only the suspect's name: take it when it is exactly one
        -- citizen (by citizen id or full name); otherwise the officer must pick the citizen
        local found, err = R.ResolveCitizen(data.suspect)
        if err == 'ambiguous' then return { success = false, error = 'ambiguous_suspect' } end
        cid = found or ''
    end
    local suspectName
    if cid ~= '' then
        if cid == a.cid then return { success = false, error = 'self' } end
        suspectName = citizenName(cid)
        if not suspectName then return { success = false, error = 'unknown_citizen' } end
    elseif wtype == 'search' then
        suspectName = T(data.suspect, 128)
        if suspectName == '' then suspectName = 'Unknown' end
    else
        return { success = false, error = 'suspect_required' }
    end
    if wtype == 'search' and address == '' then return { success = false, error = 'address_required' } end

    local expiresAt, days = expiryFor(wtype, data.expiryDays)

    local title = T(data.title, 255)
    if title == '' then title = ('%s warrant'):format(wtype:sub(1, 1):upper() .. wtype:sub(2)) end
    local narrative = Access.Text(data.narrative or data.affidavit, 8000)
    local charges = Access.JsonList(data.charges, 30, 8000)
    local officers = Access.JsonList(data.officers, 20, 4000)
    local witnesses = Access.JsonList(data.witnesses, 20, 4000)

    local wId = insertWarrant({ cid = cid ~= '' and cid or nil, suspectName = suspectName, charges = charges, officers = officers,
        witnesses = witnesses, issuedBy = a.name, title = title, narrative = narrative, expiresAt = expiresAt, type = wtype,
        address = address ~= '' and address or nil })
    if not wId then return { success = false, error = 'db_error' } end

    R.Audit(src, 'warrant', wId, 'create', { type = wtype, suspect = cid ~= '' and cid or nil, days = days })
    local reviewId = requestReview({ warrantId = wId, type = wtype, suspectCitizenId = cid ~= '' and cid or nil, address = address ~= '' and address or nil,
        narrative = narrative }, a)
    local w = warrantChanged(wId, 'created')
    return { success = true, warrantId = wId, status = 'pending', approvalState = 'pending_approval', reviewId = reviewId, warrant = w }
end

local function becameActive(w, actorCid)
    if PFMdtShared and callable(PFMdtShared.ReportWarrant) and w then
        PFMdtShared.ReportWarrant(w.warrantId, w.suspectName, w.charges, actorCid)
    end
end

local DECISIONS = {
    approve = { approval = 'approved', status = 'active' },
    deny = { approval = 'denied', status = 'denied' },
    needs_info = { approval = 'needs_info', status = 'pending' },
}

--- A supervisor decides a warrant no judge review was filed for (Config.Warrants.SupervisorApproval
--- = the lowest grade that may; false = judges only). Never the officer who requested it.
function R.ReviewWarrant(src, data)
    local a = actorOf(src)
    if not a or type(data) ~= 'table' then return { success = false, error = 'bad_args' } end
    local decision = DECISIONS[data.decision] and data.decision or nil
    if not decision or decision == 'needs_info' then return { success = false, error = 'bad_decision' } end
    local minGrade = tonumber(cfg('Warrants').SupervisorApproval)
    if not minGrade then return { success = false, error = 'judge_only' } end
    if a.grade < minGrade and not Access.IsOwner(src) then return { success = false, error = 'no_permission' } end
    local row = R.GetWarrantRow(data.warrantId)
    if not row then return { success = false, error = 'not_found' } end
    if row.review_id then return { success = false, error = 'judge_review' } end
    local requester = MySQL.single.await("SELECT by_cid FROM pf_mdt_record_audit WHERE entity = 'warrant' AND entity_id = ? AND action = 'create' ORDER BY id ASC LIMIT 1", { row.warrantId })
    if requester and requester.by_cid == a.cid then return { success = false, error = 'own_warrant' } end
    local d = DECISIONS[decision]
    local n = affected(MySQL.update.await([[UPDATE pf_mdt_warrants SET approval_state = ?, status = ?, approved_by = ?
        WHERE warrantId = ? AND approval_state IN ('pending_approval', 'needs_info') AND review_id IS NULL AND status = 'pending']],
        { d.approval, d.status, 'supervisor:' .. a.cid, row.warrantId }))
    if n == 0 then return { success = false, error = 'invalid_state' } end
    R.Audit(src, 'warrant', row.warrantId, 'status', { decision = decision, by = 'supervisor', note = T(data.note, 255) })
    local w = warrantChanged(row.warrantId, decision)
    if decision == 'approve' then becameActive(w, a.cid) end
    return { success = true, warrant = w }
end

--- pf-justice only (contract 19A DecideWarrant -> SetWarrantApproval). decision approve | deny |
--- needs_info; opts = { reviewId, judgeCid, note }. A warrant with a filed review only accepts
--- the decision for that review.
function R.SetWarrantApproval(warrantId, decision, opts)
    opts = type(opts) == 'table' and opts or {}
    local d = DECISIONS[decision]
    if not d then return { ok = false, error = 'bad_args' } end
    local row = R.GetWarrantRow(warrantId)
    if not row then return { ok = false, error = 'not_found' } end
    if row.review_id and tonumber(opts.reviewId) ~= tonumber(row.review_id) then return { ok = false, error = 'conflict' } end
    local judge = Access.Text(opts.judgeCid, 64)
    local n = affected(MySQL.update.await([[UPDATE pf_mdt_warrants SET approval_state = ?, status = ?, approved_by = ?
        WHERE warrantId = ? AND approval_state IN ('pending_approval', 'needs_info') AND status = 'pending']],
        { d.approval, d.status, 'judge:' .. (judge ~= '' and judge or 'court'), row.warrantId }))
    if n == 0 then return { ok = false, error = 'invalid_state' } end
    R.Audit({ cid = judge ~= '' and judge or 'pf-justice', job = 'judge' }, 'warrant', row.warrantId, 'status',
        { decision = decision, by = 'judge', reviewId = tonumber(opts.reviewId), note = Access.Text(opts.note, 255) })
    local w = warrantChanged(row.warrantId, decision)
    if decision == 'approve' then becameActive(w, judge ~= '' and judge or nil) end
    return { ok = true }
end

-- The suspect's custody from pf-justice: the one named (it must be theirs) or the open one.
local function custodyFor(cid, custodyId)
    if not justiceStarted() or not cid then return nil, 'cannot_verify' end
    local ok, res = pcall(function() return exports['pf-justice']:GetCustody(cid, { latest = true }) end)
    local c = ok and type(res) == 'table' and res.ok and res.custody or nil
    if custodyId then
        if not c or tonumber(c.id) ~= custodyId or c.cid ~= cid then return nil, 'custody_mismatch' end
        return c
    end
    if c and not c.closedAt then return c end
    return nil
end

--- served (an approved or legacy active warrant; links the suspect's custody) or removed (recall,
--- Config.Permissions.deleteWarrant).
function R.SetWarrantStatus(src, data)
    local a = actorOf(src)
    if not a or type(data) ~= 'table' then return { success = false, error = 'bad_args' } end
    local status = data.status == 'recalled' and 'removed' or data.status
    if status ~= 'served' and status ~= 'removed' then return { success = false, error = 'bad_status' } end
    if status == 'removed' and not Access.Can(src, 'deleteWarrant') then return { success = false, error = 'no_permission' } end
    local row = R.GetWarrantRow(data.warrantId)
    if not row then return { success = false, error = 'not_found' } end
    local custodyId = nil
    local n
    if status == 'served' then
        if row.status ~= 'active' or not (row.approval_state == 'approved' or row.approval_state == 'legacy' or row.approval_state == nil) then
            return { success = false, error = 'invalid_state' }
        end
        local wanted = tonumber(data.custodyId)
        if wanted then wanted = math.floor(wanted) end
        local c, err = custodyFor(row.suspectCitizenId, wanted)
        if wanted and not c then return { success = false, error = err or 'custody_mismatch' } end
        custodyId = c and tonumber(c.id) or nil
        n = affected(MySQL.update.await("UPDATE pf_mdt_warrants SET status = 'served', served_custody_id = ? WHERE warrantId = ? AND status = 'active'",
            { custodyId, row.warrantId }))
    else
        n = affected(MySQL.update.await("UPDATE pf_mdt_warrants SET status = 'removed' WHERE warrantId = ? AND status IN ('active', 'pending')",
            { row.warrantId }))
    end
    if n == 0 then return { success = false, error = 'invalid_state' } end
    R.Audit(src, 'warrant', row.warrantId, 'status', { status = status, custodyId = custodyId, note = T(data.note, 255) })
    return { success = true, warrant = warrantChanged(row.warrantId, status), custodyId = custodyId }
end

--- Expires active and pending warrants past their expiry (named tick; the thread below runs it).
function R.SweepWarrants()
    local list = rows(MySQL.query.await("SELECT warrantId FROM pf_mdt_warrants WHERE status IN ('active', 'pending') AND expiresAt IS NOT NULL AND expiresAt < NOW() LIMIT 200", {}))
    local n = 0
    for _, r in ipairs(list) do
        if affected(MySQL.update.await("UPDATE pf_mdt_warrants SET status = 'expired' WHERE warrantId = ? AND status IN ('active', 'pending')", { r.warrantId })) > 0 then
            n = n + 1
            R.Audit({ cid = 'system', job = 'system' }, 'warrant', r.warrantId, 'status', { status = 'expired' })
            warrantChanged(r.warrantId, 'expired')
        end
    end
    return n
end

function R.ListWarrantsFor(cid)
    cid = Access.Text(cid, 64)
    if cid == '' then return {} end
    local out = {}
    for _, r in ipairs(rows(MySQL.query.await('SELECT ' .. WARRANT_COLS .. ' FROM pf_mdt_warrants WHERE suspectCitizenId = ? ORDER BY id DESC LIMIT 50', { cid }))) do
        out[#out + 1] = publicWarrant(r)
    end
    return out
end

-- ── warrant requests from other resources (pfm-prison escapes, pf-justice) ──

-- The request key lives in the warrant's own 'create' audit row (by_job = 'request', detail =
-- 'key:<key>'), so no extra column is needed; PruneAudit keeps these rows.
local REQUEST_KEY = '^[%w%-_:%.]+$'
local requestLocks = {}

local function requestedWarrant(key)
    local row = MySQL.single.await("SELECT entity_id FROM pf_mdt_record_audit WHERE entity = 'warrant' AND action = 'create' AND by_job = 'request' AND detail = ? LIMIT 1",
        { 'key:' .. key })
    return row and row.entity_id or nil
end

-- The requester id of a system request ('system_<label>'): only [%w_-], 64 characters at most, so it
-- passes as a citizen-id-shaped requester in pf-justice RequestWarrantReview (batch 19 check B19-1).
local function systemCid(label)
    local clean = tostring(label or 'system'):gsub('[^%w_%-]', '_')
    return ('system_' .. clean):sub(1, 64)
end

local function withKeyLock(key, fn)
    local waited = 0
    while requestLocks[key] do
        if waited >= 10000 then return { ok = false, error = 'busy' } end
        Wait(50)
        waited = waited + 50
    end
    requestLocks[key] = true
    local ok, res = pcall(fn)
    requestLocks[key] = nil
    if not ok then
        print('^1[pf-policemdt]^7 warrant request failed: ' .. tostring(res))
        return { ok = false, error = 'db_unavailable' }
    end
    return res
end

--- RequestWarrant(spec, opts) for Config.Warrants.Requesters. spec = { type = 'arrest'|'bench',
--- suspectCitizenId, title?, narrative?, charges?, source = { type, id }? }; opts = { key (required,
--- 1-128 chars [%w-_:.]), actor = { kind = 'system', label }? }. The same key returns the first warrant.
--- The warrant is made exactly like an officer's: server id and expiry, pending_approval, judge review
--- when pf-justice offers it; supervisors decide otherwise (the system requester is never an officer).
function R.RequestWarrant(spec, opts, invoker)
    if type(spec) ~= 'table' or type(opts) ~= 'table' then return { ok = false, error = 'bad_args' } end
    local key = opts.key
    if type(key) ~= 'string' or #key < 1 or #key > 128 or not key:match(REQUEST_KEY) then return { ok = false, error = 'bad_args' } end
    local wtype = type(spec.type) == 'string' and spec.type:lower() or 'arrest'
    if wtype ~= 'arrest' and wtype ~= 'bench' then return { ok = false, error = 'bad_args' } end
    local cid = T(spec.suspectCitizenId, 64)
    local actorCfg = type(opts.actor) == 'table' and opts.actor or {}
    local label = T(actorCfg.label, 48)
    if label == '' then label = tostring(invoker or GetCurrentResourceName()) end
    local source = type(spec.source) == 'table' and { type = T(spec.source.type, 32), id = T(spec.source.id, 64) } or nil
    return withKeyLock(key, function()
        local existing = requestedWarrant(key)
        if existing then return { ok = true, warrantId = existing, duplicate = true } end
        if cid == '' then return { ok = false, error = 'suspect_required' } end
        local suspectName = citizenName(cid)
        if not suspectName then return { ok = false, error = 'suspect_required' } end
        local expiresAt, days = expiryFor(wtype, nil)
        local title = T(spec.title, 255)
        if title == '' then title = (wtype == 'bench' and 'Bench warrant' or 'Arrest warrant') end
        local narrative = Access.Text(spec.narrative, 8000)
        local actor = { cid = systemCid(label), name = label }
        local wId = insertWarrant({ cid = cid, suspectName = suspectName, charges = Access.JsonList(spec.charges, 30, 8000),
            officers = '[]', witnesses = '[]', issuedBy = label, title = title, narrative = narrative, expiresAt = expiresAt, type = wtype })
        if not wId then return { ok = false, error = 'db_unavailable' } end
        -- the key row first (it is what a retry finds), then the details
        R.Audit({ cid = actor.cid, job = 'request' }, 'warrant', wId, 'create', 'key:' .. key)
        R.Audit({ cid = actor.cid, job = tostring(invoker or 'system') }, 'warrant', wId, 'update',
            { requested = true, type = wtype, suspect = cid, days = days, source = source, resource = invoker })
        local reviewId = requestReview({ warrantId = wId, type = wtype, suspectCitizenId = cid, narrative = narrative }, actor)
        warrantChanged(wId, 'created')
        return { ok = true, warrantId = wId, reviewId = reviewId }
    end)
end

--- RecallWarrant(warrantId, reason, opts): an active or pending warrant is removed (recalled), with an
--- audit row; already removed answers ok with duplicate = true; served, expired or denied: invalid_state.
function R.RecallWarrant(warrantId, reason, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    local row = R.GetWarrantRow(warrantId)
    if not row then return { ok = false, error = 'not_found' } end
    if row.status == 'removed' then return { ok = true, warrantId = row.warrantId, duplicate = true } end
    local n = affected(MySQL.update.await("UPDATE pf_mdt_warrants SET status = 'removed' WHERE warrantId = ? AND status IN ('active', 'pending')", { row.warrantId }))
    if n == 0 then
        local again = R.GetWarrantRow(row.warrantId)
        if again and again.status == 'removed' then return { ok = true, warrantId = row.warrantId, duplicate = true } end
        return { ok = false, error = 'invalid_state' }
    end
    local label = type(opts.actor) == 'table' and T(opts.actor.label, 48) or ''
    if label == '' then label = tostring(invoker or 'system') end
    R.Audit({ cid = systemCid(label), job = tostring(invoker or 'system') }, 'warrant', row.warrantId, 'status',
        { status = 'removed', recalled = true, reason = Access.Text(reason, 255), key = opts.key and Access.Text(opts.key, 128) or nil })
    warrantChanged(row.warrantId, 'removed')
    return { ok = true, warrantId = row.warrantId }
end

-- ── BOLO board ───────────────────────────────────────────────────────────────

local function publicBolo(r)
    if not r then return nil end
    return { id = tonumber(r.id), kind = r.kind, citizenid = r.citizenid, plate = r.plate, description = r.description,
        lastSeen = r.last_seen, danger = tonumber(r.danger) == 1 or r.danger == true, status = r.status, caseId = tonumber(r.case_id),
        byCid = r.by_cid, createdAt = tonumber(r.created_at), expiresAt = tonumber(r.expires_at) }
end
R.PublicBolo = publicBolo

local function getBolo(id)
    return MySQL.single.await('SELECT * FROM pf_mdt_bolos WHERE id = ? LIMIT 1', { id })
end

local function broadcastBolo(b, change)
    for _, s in ipairs(onDutyOfficers()) do
        TriggerClientEvent('pf_mdt:client:boloChanged', s, b, change)
        if change == 'created' then
            local what = b.kind == 'vehicle' and ('vehicle ' .. tostring(b.plate)) or 'person'
            TriggerClientEvent('QBCore:Notify', s, ('BOLO (%s)%s: %s'):format(what, b.danger and ' - DANGER' or '', b.description), b.danger and 'error' or 'primary')
        end
    end
    TriggerEvent('pf_mdt:server:boloChanged', b, change)
end

--- data = { kind = 'person'|'vehicle', citizenid?, plate?, description, lastSeen?, danger?, hours?, caseId? }
function R.CreateBolo(src, data)
    local a = actorOf(src)
    if not a or type(data) ~= 'table' then return { success = false, error = 'bad_args' } end
    if not Access.AllowRate(src, 'boloCreate', 3000) then return { success = false, error = 'rate_limited' } end
    local bcfg = cfg('Bolos')
    local kind = data.kind == 'vehicle' and 'vehicle' or (data.kind == 'person' and 'person' or nil)
    if not kind then return { success = false, error = 'bad_kind' } end
    local description = T(data.description, 500)
    if #description < 3 then return { success = false, error = 'description_required' } end
    local cid, plate = nil, nil
    if kind == 'vehicle' then
        plate = normPlate(data.plate)
        if not plate then return { success = false, error = 'bad_plate' } end
    else
        local c = T(data.citizenid or data.citizenId, 64)
        if c ~= '' then
            if not citizenName(c) then return { success = false, error = 'unknown_citizen' } end
            cid = c
        end
    end
    local caseId = tonumber(data.caseId)
    if caseId then
        caseId = math.floor(caseId)
        if not MySQL.single.await('SELECT id FROM pf_mdt_cases WHERE id = ? LIMIT 1', { caseId }) then return { success = false, error = 'unknown_case' } end
    end
    local hours = math.floor(tonumber(data.hours) or tonumber(bcfg.DefaultHours) or 24)
    hours = math.max(1, math.min(hours, tonumber(bcfg.MaxHours) or 168))
    local active = MySQL.single.await("SELECT COUNT(*) AS c FROM pf_mdt_bolos WHERE status = 'active'", {})
    if (tonumber(active and active.c) or 0) >= (tonumber(bcfg.MaxActive) or 200) then return { success = false, error = 'too_many' } end
    local t = now()
    local id = MySQL.insert.await([[INSERT INTO pf_mdt_bolos (kind, citizenid, plate, description, last_seen, danger, status, case_id, by_cid, created_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?)]],
        { kind, cid, plate, description, T(data.lastSeen, 255) ~= '' and T(data.lastSeen, 255) or nil, data.danger == true and 1 or 0, caseId, a.cid, t, t + hours * 3600 })
    if not tonumber(id) or tonumber(id) <= 0 then return { success = false, error = 'db_error' } end
    id = tonumber(id)
    R.Audit(src, 'bolo', id, 'create', { kind = kind, citizenid = cid, plate = plate, hours = hours })
    if plate then
        R.PlateActivity(plate, { type = 'bolo', officerCid = a.cid, officerName = a.name, referenceId = 'BOLO-' .. id })
        plateChanged(plate)
    end
    local b = publicBolo(getBolo(id))
    if b then broadcastBolo(b, 'created') end
    return { success = true, id = id, bolo = b }
end

--- The author, or a rank with Config.Permissions.clearAnyBolo, clears an active BOLO.
function R.ClearBolo(src, data)
    local a = actorOf(src)
    if not a or type(data) ~= 'table' or not tonumber(data.id) then return { success = false, error = 'bad_args' } end
    local row = getBolo(math.floor(tonumber(data.id)))
    if not row then return { success = false, error = 'not_found' } end
    if row.by_cid ~= a.cid and not Access.Can(src, 'clearAnyBolo') then return { success = false, error = 'no_permission' } end
    local n = affected(MySQL.update.await("UPDATE pf_mdt_bolos SET status = 'cleared' WHERE id = ? AND status = 'active'", { row.id }))
    if n == 0 then return { success = false, error = 'invalid_state' } end
    R.Audit(src, 'bolo', row.id, 'status', { status = 'cleared', reason = T(data.reason, 255) })
    if row.plate then
        R.PlateActivity(row.plate, { type = 'bolo_cleared', officerCid = a.cid, officerName = a.name, referenceId = 'BOLO-' .. row.id })
        plateChanged(normPlate(row.plate))
    end
    local b = publicBolo(getBolo(row.id))
    if b then broadcastBolo(b, 'cleared') end
    return { success = true, bolo = b }
end

function R.ListActiveBolos(kind)
    local sql, params = "SELECT * FROM pf_mdt_bolos WHERE status = 'active' AND expires_at > ?", { now() }
    if kind == 'person' or kind == 'vehicle' then sql = sql .. ' AND kind = ?' params[2] = kind end
    local out = {}
    for _, r in ipairs(rows(MySQL.query.await(sql .. ' ORDER BY id DESC LIMIT 200', params))) do out[#out + 1] = publicBolo(r) end
    return out
end

--- Expires BOLOs past their time (named tick).
function R.SweepBolos()
    local list = rows(MySQL.query.await("SELECT * FROM pf_mdt_bolos WHERE status = 'active' AND expires_at <= ? LIMIT 200", { now() }))
    local n = 0
    for _, r in ipairs(list) do
        if affected(MySQL.update.await("UPDATE pf_mdt_bolos SET status = 'expired' WHERE id = ? AND status = 'active'", { r.id })) > 0 then
            n = n + 1
            R.Audit({ cid = 'system', job = 'system' }, 'bolo', r.id, 'status', { status = 'expired' })
            if r.plate then plateChanged(normPlate(r.plate)) end
            r.status = 'expired'
            broadcastBolo(publicBolo(r), 'expired')
        end
    end
    return n
end

-- ── expungement (soft delete with audit) ─────────────────────────────────────

--- spec = { type = 'incident' | 'conviction', id } or { type = 'convictions', citizenId };
--- opts = { actorCid, reason }. Rows get deleted_at; nothing is removed. Returns { ok, changed }.
function R.Expunge(spec, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    if type(spec) ~= 'table' then return { ok = false, error = 'bad_args' } end
    local by = { cid = Access.Text(opts.actorCid, 64) ~= '' and Access.Text(opts.actorCid, 64) or ('resource:' .. tostring(invoker or '?')), job = invoker and Access.Text(invoker, 32) or nil }
    local reason = Access.Text(opts.reason, 255)
    local t = now()
    if spec.type == 'incident' or spec.type == 'conviction' then
        local id = tonumber(spec.id)
        if not id then return { ok = false, error = 'bad_args' } end
        local tbl = spec.type == 'incident' and 'pf_mdt_incidents' or 'pf_mdt_sentences'
        local n = affected(MySQL.update.await('UPDATE ' .. tbl .. ' SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL', { t, math.floor(id) }))
        if n > 0 then R.Audit(by, spec.type == 'incident' and 'incident' or 'sentence', math.floor(id), 'delete', { expunged = true, reason = reason }) end
        return { ok = true, changed = n }
    elseif spec.type == 'convictions' then
        local cid = Access.Text(spec.citizenId, 64)
        if cid == '' then return { ok = false, error = 'bad_args' } end
        local ids = rows(MySQL.query.await('SELECT id FROM pf_mdt_sentences WHERE citizenId = ? AND deleted_at IS NULL', { cid }))
        local n = 0
        for _, r in ipairs(ids) do
            if affected(MySQL.update.await('UPDATE pf_mdt_sentences SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL', { t, r.id })) > 0 then
                n = n + 1
                R.Audit(by, 'sentence', r.id, 'delete', { expunged = true, citizenId = cid, reason = reason })
            end
        end
        return { ok = true, changed = n }
    end
    return { ok = false, error = 'bad_args' }
end

--- Deletes audit rows past Config.RecordAudit.RetentionDays (bounded batch; named tick).
function R.PruneAudit()
    local days = tonumber(cfg('RecordAudit').RetentionDays) or 365
    if days <= 0 then return 0 end
    -- warrant request keys (by_job = 'request') are kept: a late retry must still find its warrant
    return affected(MySQL.update.await("DELETE FROM pf_mdt_record_audit WHERE at < ? AND (by_job IS NULL OR by_job <> 'request') LIMIT 5000", { now() - days * 86400 }))
end

-- ── permissions for the endpoints below (server/access.lua gates them) ──────

Access.RegisterActions({
    ['pf_mdt:warrants:create'] = { action = 'createWarrant' },
    ['pf_mdt:warrants:review'] = { action = 'serveWarrant' },     -- the handler checks SupervisorApproval
    ['pf_mdt:warrants:setStatus'] = { action = 'serveWarrant' },
    ['pf_mdt:bolos:create'] = { action = 'bolos' },
    ['pf_mdt:bolos:clear'] = { action = 'bolos' },
    ['pf_mdt:vehicles:setFlag'] = { action = 'vehicleRecords' },
    ['pf_mdt:vehicles:clearFlag'] = { action = 'vehicleRecords' },
    ['pf_mdt:audit:list'] = { action = 'viewAudit' },
})

local function answerNotify(src, res, okText)
    if res.success then notify(src, okText, 'success')
    else notify(src, 'Not done: ' .. tostring(res.error), 'error') end
end
R.AnswerNotify = answerNotify

QBCore.Functions.CreateCallback('pf_mdt:warrants:create', function(source, cb, data) cb(R.CreateWarrant(source, data)) end)
QBCore.Functions.CreateCallback('pf_mdt:warrants:review', function(source, cb, data) cb(R.ReviewWarrant(source, data)) end)
QBCore.Functions.CreateCallback('pf_mdt:warrants:setStatus', function(source, cb, data) cb(R.SetWarrantStatus(source, data)) end)
QBCore.Functions.CreateCallback('pf_mdt:warrants:listFor', function(source, cb, data)
    cb({ success = true, list = R.ListWarrantsFor(type(data) == 'table' and data.citizenId or data) })
end)
QBCore.Functions.CreateCallback('pf_mdt:bolos:create', function(source, cb, data) cb(R.CreateBolo(source, data)) end)
QBCore.Functions.CreateCallback('pf_mdt:bolos:clear', function(source, cb, data) cb(R.ClearBolo(source, data)) end)
QBCore.Functions.CreateCallback('pf_mdt:bolos:list', function(source, cb, data)
    cb({ success = true, list = R.ListActiveBolos(type(data) == 'table' and data.kind or nil) })
end)
QBCore.Functions.CreateCallback('pf_mdt:vehicles:setFlag', function(source, cb, data)
    local ok, err, flags = R.SetVehicleFlag(source, data)
    cb({ success = ok, error = err, flags = flags and flags.flags or nil })
end)
QBCore.Functions.CreateCallback('pf_mdt:vehicles:clearFlag', function(source, cb, data)
    local ok, err, flags = R.ClearVehicleFlag(source, data)
    cb({ success = ok, error = err, flags = flags and flags.flags or nil })
end)
QBCore.Functions.CreateCallback('pf_mdt:audit:list', function(source, cb, data)
    if type(data) ~= 'table' then return cb({ success = false, error = 'bad_args' }) end
    cb({ success = true, list = R.ListAudit(data.entity, data.entityId, data.limit) })
end)

-- Until the MDT page has review buttons (21A), supervisors decide from chat:
-- /warrantreview <warrantId> approve|deny. Same rules as the callback (on duty, grade, not own).
RegisterCommand('warrantreview', function(src, args)
    if not src or src == 0 then return end
    local ok, err = Access.Can(src, 'serveWarrant')
    if not ok then return notify(src, 'Not allowed: ' .. tostring(err), 'error') end
    local decision = args and args[2] and tostring(args[2]):lower() or ''
    local res = R.ReviewWarrant(src, { warrantId = args and args[1], decision = decision })
    answerNotify(src, res, ('Warrant %s: %s'):format(tostring(args and args[1]), decision))
end, false)

-- ── exports (server-to-server) ───────────────────────────────────────────────

local function invokerAllowed(list)
    local inv = GetInvokingResource()
    if inv == nil or inv == GetCurrentResourceName() then return true, inv end
    return type(list) == 'table' and list[inv] == true, inv
end
local DEFAULT_READERS = { ['pfm-policejob'] = true, ['pf-justice'] = true }

exports('GetPlateFlags', function(plate) return R.GetPlateFlags(plate) end)
exports('ListActiveBolos', function(kind)
    if not invokerAllowed(cfg('Bolos').Readers or DEFAULT_READERS) then return { ok = false, error = 'not_allowed' } end
    return { ok = true, list = R.ListActiveBolos(kind) }
end)
exports('GetWarrant', function(warrantId)
    if not invokerAllowed(cfg('Warrants').Readers or DEFAULT_READERS) then return { ok = false, error = 'not_allowed' } end
    local w = publicWarrant(R.GetWarrantRow(warrantId))
    if not w then return { ok = false, error = 'not_found' } end
    return { ok = true, warrant = w }
end)
exports('ListWarrantsFor', function(cid)
    if not invokerAllowed(cfg('Warrants').Readers or DEFAULT_READERS) then return { ok = false, error = 'not_allowed' } end
    return { ok = true, list = R.ListWarrantsFor(cid) }
end)
exports('SetWarrantApproval', function(warrantId, decision, opts)
    if GetInvokingResource() ~= 'pf-justice' then return { ok = false, error = 'not_allowed' } end
    return R.SetWarrantApproval(warrantId, decision, opts)
end)
local DEFAULT_REQUESTERS = { ['pfm-prison'] = true, ['pf-justice'] = true }
exports('RequestWarrant', function(spec, opts)
    local allowed, inv = invokerAllowed(cfg('Warrants').Requesters or DEFAULT_REQUESTERS)
    if not allowed then return { ok = false, error = 'not_allowed' } end
    return R.RequestWarrant(spec, opts, inv)
end)
exports('RecallWarrant', function(warrantId, reason, opts)
    local allowed, inv = invokerAllowed(cfg('Warrants').Requesters or DEFAULT_REQUESTERS)
    if not allowed then return { ok = false, error = 'not_allowed' } end
    return R.RecallWarrant(warrantId, reason, opts, inv)
end)
exports('RecordPlateActivity', function(plate, spec)
    if not invokerAllowed(cfg('PlateActivity').Callers or { ['pfm-policejob'] = true }) then return { ok = false, error = 'not_allowed' } end
    local ok, err = R.PlateActivity(plate, spec)
    return { ok = ok, error = err }
end)
exports('ExpungeRecord', function(spec, opts)
    local allowed, inv = invokerAllowed(cfg('Expunge').Callers or { ['pf-government'] = true, ['pf-justice'] = true })
    if not allowed then return { ok = false, error = 'not_allowed' } end
    return R.Expunge(spec, opts, inv)
end)

-- ── start-up and sweeps ──────────────────────────────────────────────────────

--- After the schema: the plate cache, then a sweep. Named for specs (threads do not run there).
function R.Start()
    if type(PFMdtSchema) == 'table' and callable(PFMdtSchema.WaitReady) and not PFMdtSchema.WaitReady() then
        print('^1[pf-policemdt]^7 records not started: the database schema is not ready')
        return false
    end
    R.RefreshPlate(nil)
    R.SweepWarrants()
    R.SweepBolos()
    return true
end

--- One sweep pass (warrants and BOLOs every minute, audit retention once a day).
local lastPrune = 0
function R.Tick()
    R.SweepWarrants()
    R.SweepBolos()
    if now() - lastPrune >= 86400 then
        lastPrune = now()
        R.PruneAudit()
    end
end

CreateThread(function()
    Wait(2000)
    if not R.Start() then return end
    while true do
        Wait((tonumber(cfg('Warrants').SweepSeconds) or 60) * 1000)
        local ok, err = pcall(R.Tick)
        if not ok then print('^1[pf-policemdt]^7 records sweep failed: ' .. tostring(err)) end
    end
end)
