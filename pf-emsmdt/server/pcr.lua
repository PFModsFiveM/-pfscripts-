-- Patient care reports (batch 20, architecture 4.11). A PCR is charted by the server only:
--   * it opens on the first treatment an on-duty medic gives a patient who is not in hospital care
--     (pf-ambulancejob:server:treatmentApplied) and keeps charting that patient while it stays open
--     and active within Config.PCR.CallWindowSeconds;
--   * lines come from pf-ambulancejob's server events (treatments by their pf_med_treatments id,
--     admissions, revivals, deaths), vitals snapshots from GetPatientSummary, times from the unit
--     board (dispatch, on scene, departure) and the handover;
--   * the narrative is the only typed part (lead or crew, capped at Config.PCR.NarrativeMax);
--   * the handover is acknowledged by on-duty receiving hospital staff next to the patient, who is
--     checked in at a hospital (GetAdmission); the crew cannot acknowledge their own handover.
-- pf-ambulancejob stays the clinical record: PCR lines hold its ids and a short summary.
--
-- States: open -> handed_over -> closed; open -> closed (treated on scene, refused, deceased,
-- cancelled, or no activity). Per patient, every change runs under one lock (P.Serial / withPcr), taken
-- before the first database wait; AJ events that arrive while it is held run after it, in order.
--
-- Callbacks (answer { ok = true, ... } or { ok = false, error, message }):
--   pf_emsmdt:pcr:list { scope = 'mine' | 'patient', citizenId? }, pf_emsmdt:pcr:get { id },
--   pf_emsmdt:pcr:saveNarrative { id, text }, pf_emsmdt:pcr:acknowledgeHandover { id },
--   pf_emsmdt:pcr:close { id, disposition }, pf_emsmdt:pcr:pendingHandovers.
-- Exports: GetPcr(pcrId, opts), ListPcrFor(cid, opts); opts = { viewer = src, purpose = 'treatment' |
-- 'self' | 'court_order', courtOrderId? } (privacy as GetMedicalRecord, architecture 6.6).

PFEmsPcr = PFEmsPcr or {}
local P = PFEmsPcr
local QBCore = PFMdt.GetCore()

P.OpenByCid = {}   -- [cid] = open PCR row (this resource is the only writer of open PCRs)

local function cfg() return Config.PCR or {} end
local function now() return os.time() end
local function fail(code, message) return { ok = false, error = code, message = message } end

local function ready() return PFEmsSchema ~= nil and PFEmsSchema.Ready() end

local function validCid(v) return type(v) == 'string' and #v >= 1 and #v <= 64 and v:match('^[%w_%-]+$') ~= nil end

local function int(v, lo, hi)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n)
    if not n or (lo and n < lo) or (hi and n > hi) then return nil end
    return n
end

--- Plain one-line text (control characters become spaces), trimmed and cut to max bytes.
local function line(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

--- Cuts a UTF-8 string at max bytes without splitting a character.
local function utf8Cut(s, max)
    if #s <= max then return s, false end
    s = s:sub(1, max)
    while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
    return s, true
end

local function humanize(id)
    local s = tostring(id or ''):gsub('_', ' ')
    return (s:gsub('^%l', string.upper))
end

local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) == 'table' then
        if rawget(v, '__cfx_functionReference') then return true end
        local mt = getmetatable(v)
        return type(mt) == 'table' and mt.__call ~= nil
    end
    return false
end

local function player(src)
    local Pl = QBCore.Functions.GetPlayer(src)
    if type(Pl) == 'table' and type(Pl.PlayerData) == 'table' then return Pl end
    return nil
end

local function playerByCid(cid)
    if not validCid(cid) then return nil end
    local Pl = QBCore.Functions.GetPlayerByCitizenId(cid)
    if type(Pl) == 'table' and type(Pl.PlayerData) == 'table' then return Pl end
    return nil
end

local function jobOf(Pl) return Pl and type(Pl.PlayerData.job) == 'table' and Pl.PlayerData.job or nil end

local function isMedic(Pl)
    local job = jobOf(Pl)
    return job ~= nil and Config.AllowedJobs and Config.AllowedJobs[job.name] == true and job.onduty == true
end

local function isHospitalStaff(Pl)
    local job = jobOf(Pl)
    local jobs = (cfg().Handover or {}).StaffJobs or { ambulance = true }
    return job ~= nil and jobs[job.name] == true and job.onduty == true
end

local function isSupervisor(Pl)
    local job = jobOf(Pl)
    if not job then return false end
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    local list = Config.SupervisorGrades and Config.SupervisorGrades[job.name]
    return type(list) == 'table' and list[tonumber(grade) or -1] == true
end

local function nameOf(Pl, fallback)
    local ci = Pl and Pl.PlayerData.charinfo or {}
    local name = (tostring(ci.firstname or '') .. ' ' .. tostring(ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or fallback
end

local function nameOfCid(cid) return nameOf(playerByCid(cid), cid) end

local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function posOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function aj(name, ...)
    local res = cfg().Source or 'pf-ambulancejob'
    if GetResourceState(res) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, out = pcall(function() return exports[res][name](exports[res], table.unpack(args, 1, args.n)) end)
    if ok and type(out) == 'table' then return out end
    return nil
end

--- The patient's open admission (pf-ambulancejob GetAdmission), or nil.
function P.AdmissionOf(cid)
    local res = aj('GetAdmission', cid)
    if res and res.ok and type(res.admission) == 'table' and res.admission.open ~= false then return res.admission end
    return nil
end

-- ── locks ──────────────────────────────────────────────────────────────────────────────────────

local locks, pending = {}, {}
local MAX_PENDING = 50

local function acquire(key)
    if locks[key] then return false end
    locks[key] = true
    return true
end

local function release(key)
    -- events queued while the lock was held run first, still under it
    while pending[key] and #pending[key] > 0 do
        local fn = table.remove(pending[key], 1)
        local ok, err = pcall(fn)
        if not ok then print('^3[pf-emsmdt]^7 PCR charting failed: ' .. tostring(err)) end
    end
    pending[key] = nil
    locks[key] = nil
end

--- Runs fn under the patient's lock now, or after the current holder (AJ events are never dropped
--- for a busy lock; a backlog past MAX_PENDING is dropped with a console line).
function P.Serial(cid, fn)
    local key = 'cid:' .. cid
    if not acquire(key) then
        pending[key] = pending[key] or {}
        if #pending[key] >= MAX_PENDING then
            print(('^3[pf-emsmdt]^7 PCR backlog full for %s; an event was not charted'):format(cid))
            return false
        end
        pending[key][#pending[key] + 1] = fn
        return true
    end
    local ok, err = pcall(fn)
    if not ok then print('^3[pf-emsmdt]^7 PCR charting failed: ' .. tostring(err)) end
    release(key)
    return true
end

function P.Locked(cid) return locks['cid:' .. cid] == true end

-- ── rows ───────────────────────────────────────────────────────────────────────────────────────

local ROW_COLS = 'p.`id`, p.`citizenid`, p.`call_ref`, p.`unit`, p.`lead_cid`, p.`state`, p.`narrative`, p.`dispatch_at`, p.`arrive_at`, '
    .. 'p.`depart_at`, p.`handover_at`, p.`handover_by`, p.`hospital_id`, p.`admission_id`, p.`disposition`, p.`closed_at`, '
    .. 'p.`created_at`, p.`updated_at`, (SELECT COUNT(*) FROM `pf_emsmdt_pcr_entries` e WHERE e.`pcr_id` = p.`id`) AS `entries`'

local function normalise(r)
    if type(r) ~= 'table' then return nil end
    r.id = int(r.id)
    for _, k in ipairs({ 'dispatch_at', 'arrive_at', 'depart_at', 'handover_at', 'admission_id', 'closed_at', 'created_at', 'updated_at', 'entries' }) do
        r[k] = int(r[k])
    end
    r.entries = r.entries or 0
    return r
end

function P.Load(id)
    local rows = MySQL.query.await('SELECT ' .. ROW_COLS .. ' FROM `pf_emsmdt_pcr` p WHERE p.`id` = ? LIMIT 1', { id }) or {}
    return normalise(rows[1])
end

function P.LoadOpen()
    P.OpenByCid = {}
    local rows = MySQL.query.await('SELECT ' .. ROW_COLS .. " FROM `pf_emsmdt_pcr` p WHERE p.`state` = 'open' ORDER BY p.`id`") or {}
    for _, r in ipairs(rows) do
        r = normalise(r)
        local cur = P.OpenByCid[r.citizenid]
        if cur then
            -- two open PCRs for one patient cannot be made by this code; keep the newest charting
            P.CloseRow(cur, 'no_activity', now())
        end
        P.OpenByCid[r.citizenid] = r
    end
end

--- Whether cid is the lead or charted a line of the PCR.
function P.IsCrew(row, cid)
    if not validCid(cid) then return false end
    if row.lead_cid == cid then return true end
    return MySQL.scalar.await('SELECT 1 FROM `pf_emsmdt_pcr_entries` WHERE `pcr_id` = ? AND `by_cid` = ? LIMIT 1', { row.id, cid }) ~= nil
end

--- Whether cid rides on the transporting unit: the crew of the PCR's unit or of the lead's current unit
--- (server/units.lua). A partner who charted nothing is still crew for the handover.
function P.OnCrewUnit(row, cid)
    local U = PFEmsUnits
    if not U or not validCid(cid) then return false end
    for i = 1, 2 do
        local name = (i == 1) and row.unit or U.UnitOf(row.lead_cid) -- either may be nil
        local u = name and U.Get(name)
        if u then for _, member in ipairs(u.crew or {}) do if member == cid then return true end end end
    end
    return false
end

--- Crew for the handover rule: the lead, anyone who charted a line, or a member of the unit.
function P.IsHandoverCrew(row, cid) return P.IsCrew(row, cid) or P.OnCrewUnit(row, cid) end

--- One charted line. Returns true when written (a repeat of the same AJ id is ignored).
function P.AddEntry(row, kind, refId, byCid, summary, at)
    if row.entries >= (tonumber(cfg().MaxEntries) or 300) then return false end
    summary = line(summary, 255) or humanize(kind)
    local id = MySQL.insert.await('INSERT IGNORE INTO `pf_emsmdt_pcr_entries` (`pcr_id`, `kind`, `ref_id`, `by_cid`, `summary`, `at`) VALUES (?, ?, ?, ?, ?, ?)',
        { row.id, kind, refId, byCid, summary, at or now() })
    if (tonumber(id) or 0) > 0 then
        row.entries = row.entries + 1
        return true
    end
    return false
end

local function touch(row, at)
    row.updated_at = at or now()
    MySQL.update.await('UPDATE `pf_emsmdt_pcr` SET `updated_at` = ? WHERE `id` = ?', { row.updated_at, row.id })
end

--- Vitals line from GetPatientSummary (the engine's values, as the monitor shows them), at most one
--- per Config.PCR.VitalsEverySeconds unless forced.
function P.Vitals(row, force)
    local t = now()
    if not force and row.vitalsAt and t - row.vitalsAt < (tonumber(cfg().VitalsEverySeconds) or 60) then return false end
    local s = aj('GetPatientSummary', row.citizenid)
    if not (s and s.ok and type(s.vitals) == 'table') then return false end
    local v, parts = s.vitals, {}
    local function n(x) x = tonumber(x) if not x or x ~= x then return nil end return math.floor(x + 0.5) end
    if n(v.hr) then parts[#parts + 1] = ('HR %d'):format(n(v.hr)) end
    if n(v.sbp) and n(v.dbp) then parts[#parts + 1] = ('BP %d/%d'):format(n(v.sbp), n(v.dbp)) end
    if n(v.rr) then parts[#parts + 1] = ('RR %d'):format(n(v.rr)) end
    if n(v.spo2) then parts[#parts + 1] = ('SpO2 %d%%'):format(n(v.spo2)) end
    if tonumber(v.temp) then parts[#parts + 1] = ('Temp %.1f'):format(tonumber(v.temp)) end
    if n(v.gcs) then parts[#parts + 1] = ('GCS %d'):format(n(v.gcs)) end
    if n(v.pain) then parts[#parts + 1] = ('Pain %d/10'):format(n(v.pain)) end
    if type(s.consciousness) == 'string' then parts[#parts + 1] = humanize(s.consciousness) end
    if #parts == 0 then return false end
    row.vitalsAt = t
    return P.AddEntry(row, 'vitals', nil, nil, table.concat(parts, ', '), t)
end

--- Closes a row (state guard in the UPDATE) and drops it from the open cache.
function P.CloseRow(row, disposition, at)
    at = at or now()
    local n = MySQL.update.await("UPDATE `pf_emsmdt_pcr` SET `state` = 'closed', `disposition` = ?, `closed_at` = ?, `updated_at` = ? WHERE `id` = ? AND `state` <> 'closed'",
        { disposition, at, at, row.id })
    if P.OpenByCid[row.citizenid] and P.OpenByCid[row.citizenid].id == row.id then P.OpenByCid[row.citizenid] = nil end
    if (tonumber(n) or 0) > 0 then
        row.state, row.disposition, row.closed_at, row.updated_at = 'closed', disposition, at, at
        return true
    end
    return false
end

--- The open PCR of a patient that is still within the call window; a stale one is closed.
function P.OpenFor(cid, at)
    local row = P.OpenByCid[cid]
    if not row then return nil end
    if (at or now()) - (row.updated_at or 0) > (tonumber(cfg().CallWindowSeconds) or 3600) then
        P.AddEntry(row, 'note', nil, nil, 'Closed: no activity', at)
        P.CloseRow(row, 'no_activity', at)
        return nil
    end
    return row
end

--- Opens a PCR led by leadCid; the unit and call come from the unit board and the dispatch board.
function P.Open(cid, leadCid, at)
    local U = PFEmsUnits
    local unitName = U and U.UnitOf(leadCid) or nil
    local unit = unitName and U.Get(unitName) or nil
    local D = PFEmsDispatch
    local call = (unit and unit.callRef and D and D.GetCall(unit.callRef)) or (D and D.CallOf(leadCid)) or nil
    local callRef = call and tostring(call.id):sub(1, 64) or (unit and unit.callRef) or nil
    local dispatchAt = call and int(call.createdAt) or nil
    local arriveAt = (unit and unit.status == 'on_scene' and unit.statusAt) or at
    local id = MySQL.insert.await([[INSERT INTO `pf_emsmdt_pcr` (`citizenid`, `call_ref`, `unit`, `lead_cid`, `state`, `dispatch_at`, `arrive_at`, `created_at`, `updated_at`)
        VALUES (?, ?, ?, ?, 'open', ?, ?, ?, ?)]], { cid, callRef, unitName, leadCid, dispatchAt, arriveAt, at, at })
    id = int(id, 1)
    if not id then return nil end
    local row = { id = id, citizenid = cid, call_ref = callRef, unit = unitName, lead_cid = leadCid, state = 'open', dispatch_at = dispatchAt,
        arrive_at = arriveAt, created_at = at, updated_at = at, entries = 0 }
    P.OpenByCid[cid] = row
    P.AddEntry(row, 'note', nil, leadCid, ('PCR opened by %s%s'):format(nameOfCid(leadCid), unitName and (' (' .. unitName .. ')') or ''), at)
    return row
end

-- ── charting from pf-ambulancejob events ───────────────────────────────────────────────────────

--- One treatment (already validated). Opens a PCR when an on-duty medic treats a patient who has
--- none and is not in hospital care; self-care and bystander care never open one.
function P.ChartTreatment(cid, ev)
    local row = P.OpenFor(cid, ev.at)
    if not row then
        if not ev.byCid or ev.byCid == cid then return false end
        if not isMedic(playerByCid(ev.byCid)) then return false end
        if P.AdmissionOf(cid) then return false end -- hospital care is charted by pf-ambulancejob itself
        row = P.Open(cid, ev.byCid, ev.at)
        if not row then return false end
    end
    local who = ev.byCid and nameOfCid(ev.byCid) or 'unknown'
    local written = P.AddEntry(row, 'treatment', ev.id, ev.byCid, ('%s by %s (%s)'):format(humanize(ev.action), who, humanize(ev.result or 'applied')), ev.at)
    if written then P.Vitals(row, false) end
    touch(row, math.max(ev.at, row.updated_at or 0))
    return written
end

--- A note on the patient's open PCR (never opens one).
function P.ChartNote(cid, text, opts)
    opts = opts or {}
    local at = now()
    local row = P.OpenFor(cid, at)
    if not row then return false end
    if opts.patch then
        local sets, args = {}, {}
        for k, v in pairs(opts.patch) do sets[#sets + 1] = ('`%s` = ?'):format(k) args[#args + 1] = v row[k] = v end
        args[#args + 1] = row.id
        MySQL.update.await('UPDATE `pf_emsmdt_pcr` SET ' .. table.concat(sets, ', ') .. ' WHERE `id` = ?', args)
    end
    P.AddEntry(row, 'note', opts.refId, opts.byCid, text, at)
    if opts.vitals then P.Vitals(row, true) end
    touch(row, at)
    return true
end

local backlog = {}
local MAX_BACKLOG = 200
local started = false -- the open PCRs are loaded (events before that wait in the backlog)

local function whenReady(fn)
    if started and ready() then return fn() end
    if #backlog < MAX_BACKLOG then backlog[#backlog + 1] = fn end
end

--- Server event from pf-ambulancejob (17B): cid, t = { id, action, byCid, at, injuryId?, result }.
function P.OnTreatment(cid, t)
    if not validCid(cid) or type(t) ~= 'table' then return false end
    local ev = {
        id = int(t.id, 1), action = line(t.action, 32), byCid = validCid(t.byCid) and t.byCid or nil,
        at = int(t.at, 0, now() + 60) or now(), result = line(t.result, 24),
    }
    if not ev.action then return false end
    whenReady(function() P.Serial(cid, function() P.ChartTreatment(cid, ev) end) end)
    return true
end

function P.OnAdmission(admission, from, to)
    if type(admission) ~= 'table' or not validCid(admission.citizenid) then return end
    local cid = admission.citizenid
    local hospital = line(admission.hospitalId, 32)
    local id = int(admission.id, 1)
    local label = line(admission.hospital, 64) or humanize(hospital)
    whenReady(function()
        P.Serial(cid, function()
            local patch = admission.open ~= false and hospital and { hospital_id = hospital, admission_id = id } or nil
            P.ChartNote(cid, ('%s: %s'):format(label, humanize(line(to, 24) or 'changed')), { patch = patch })
        end)
    end)
end

function P.OnRevived(cid, mode)
    if not validCid(cid) then return end
    whenReady(function()
        P.Serial(cid, function() P.ChartNote(cid, ('Patient revived (%s)'):format(humanize(line(mode, 24) or 'revive')), { vitals = true }) end)
    end)
end

function P.OnDied(cid)
    if not validCid(cid) then return end
    whenReady(function() P.Serial(cid, function() P.ChartNote(cid, 'Patient died') end) end)
end

--- Unit board hook (server/units.lua): departure and hospital arrival on the crew's open PCRs.
function P.OnUnitStatus(unitName, crew, status, at)
    if status ~= 'transporting' and status ~= 'at_hospital' and status ~= 'on_scene' then return end
    local members = {}
    for _, cid in ipairs(type(crew) == 'table' and crew or {}) do members[cid] = true end
    for cid, row in pairs(P.OpenByCid) do
        if row.unit == unitName or members[row.lead_cid] then
            P.Serial(cid, function()
                local r = P.OpenByCid[cid]
                if not r then return end
                if status == 'transporting' then
                    P.ChartNote(cid, 'Departed scene, transporting', { patch = not r.depart_at and { depart_at = at } or nil, vitals = true })
                elseif status == 'at_hospital' then
                    P.ChartNote(cid, 'Arrived at hospital')
                else
                    P.ChartNote(cid, 'Unit on scene')
                end
            end)
        end
    end
end

local function fromAJ()
    local s = tonumber(source)
    if s and s > 0 then return false end
    return GetInvokingResource() == (cfg().Source or 'pf-ambulancejob')
end

AddEventHandler('pf-ambulancejob:server:treatmentApplied', function(cid, t) if fromAJ() then P.OnTreatment(cid, t) end end)
AddEventHandler('pf-ambulancejob:server:admissionChanged', function(a, from, to) if fromAJ() then P.OnAdmission(a, from, to) end end)
AddEventHandler('pf-ambulancejob:server:patientRevived', function(_, cid, _, mode) if fromAJ() then P.OnRevived(cid, mode) end end)
AddEventHandler('pf-ambulancejob:server:patientDied', function(_, cid) if fromAJ() then P.OnDied(cid) end end)

-- ── actions ────────────────────────────────────────────────────────────────────────────────────

--- Runs fn(row) under the PCR's lock and the patient's lock (both taken before the database reads).
local function withPcr(id, fn)
    if not ready() then return fail('db_unavailable', 'Reports are not available yet.') end
    local pkey = 'pcr:' .. id
    if not acquire(pkey) then return fail('busy', 'The report is being changed; try again.') end
    local ok, res = pcall(function()
        local row = P.Load(id)
        if not row then return fail('not_found', 'No such report.') end
        local ckey = 'cid:' .. row.citizenid
        if not acquire(ckey) then return fail('busy', 'The report is being charted; try again.') end
        local ok2, res2 = pcall(function()
            local fresh = P.Load(id) -- the patient's events may have changed it before the lock
            local cached = P.OpenByCid[fresh.citizenid]
            if cached and cached.id == fresh.id then fresh.vitalsAt = cached.vitalsAt end
            return fn(fresh)
        end)
        release(ckey)
        if not ok2 then error(res2, 0) end
        return res2
    end)
    release(pkey)
    if not ok then
        print('^3[pf-emsmdt]^7 PCR action failed: ' .. tostring(res))
        return fail('db_unavailable', 'The report could not be changed.')
    end
    return res
end

local function syncCache(row)
    local cached = P.OpenByCid[row.citizenid]
    if row.state == 'open' then
        if cached and cached.id == row.id then
            for k, v in pairs(row) do cached[k] = v end
        end
    elseif cached and cached.id == row.id then
        P.OpenByCid[row.citizenid] = nil
    end
end

--- The narrative (lead or crew, not after closing). Longer text is cut at Config.PCR.NarrativeMax.
function P.SaveNarrative(src, id, text)
    local Pl = player(src)
    if not Pl then return fail('offline', 'You are not loaded.') end
    if not isMedic(Pl) then return fail('not_on_duty', 'Medics on duty only.') end
    id = int(id, 1)
    if not id or type(text) ~= 'string' then return fail('bad_args', 'Invalid report or text.') end
    -- keep line breaks; other control characters go
    text = text:gsub('\r\n', '\n'):gsub('[%z\1-\9\11-\31\127]', ' ')
    local clipped
    text, clipped = utf8Cut(text, tonumber(cfg().NarrativeMax) or 4000)
    local cid = Pl.PlayerData.citizenid
    return withPcr(id, function(row)
        if row.state == 'closed' then return fail('invalid_state', 'The report is closed.') end
        if not P.IsCrew(row, cid) then return fail('no_permission', 'Only the crew writes the narrative.') end
        local at = now()
        MySQL.update.await('UPDATE `pf_emsmdt_pcr` SET `narrative` = ?, `updated_at` = ? WHERE `id` = ?', { text, at, row.id })
        row.narrative, row.updated_at = text, at
        syncCache(row)
        return { ok = true, clipped = clipped or nil, length = #text }
    end)
end

--- Receiving hospital staff acknowledge the handover: on duty in a staff job, not the crew, next to
--- the patient, who is checked in at a hospital (pf-ambulancejob GetAdmission).
function P.AcknowledgeHandover(src, id)
    local Staff = player(src)
    if not Staff then return fail('offline', 'You are not loaded.') end
    local job = jobOf(Staff)
    local jobs = (cfg().Handover or {}).StaffJobs or { ambulance = true }
    if not (job and jobs[job.name]) then return fail('no_permission', 'Hospital staff only.') end
    if job.onduty ~= true then return fail('not_on_duty', 'You are off duty.') end
    id = int(id, 1)
    if not id then return fail('bad_args', 'Invalid report.') end
    local staffCid = Staff.PlayerData.citizenid
    return withPcr(id, function(row)
        if row.state ~= 'open' then return fail('invalid_state', 'The report is ' .. tostring(row.state) .. '.') end
        if not (cfg().Handover or {}).CrewMayAcknowledge and P.IsHandoverCrew(row, staffCid) then
            return fail('no_permission', 'The crew cannot accept their own handover.')
        end
        local admission = P.AdmissionOf(row.citizenid)
        if not admission then return fail('invalid_state', 'The patient is not checked in at a hospital.') end
        local patient = playerByCid(row.citizenid)
        if not patient then return fail('offline', 'The patient is not here.') end
        if dist(posOf(src), posOf(patient.PlayerData.source)) > (tonumber((cfg().Handover or {}).Radius) or 8.0) then
            return fail('too_far', 'Stand with the patient to take the handover.')
        end
        local at = now()
        local hospital = line(admission.hospitalId, 32)
        local n = MySQL.update.await([[UPDATE `pf_emsmdt_pcr` SET `state` = 'handed_over', `handover_at` = ?, `handover_by` = ?, `hospital_id` = ?,
            `admission_id` = ?, `updated_at` = ? WHERE `id` = ? AND `state` = 'open']], { at, staffCid, hospital, int(admission.id, 1), at, row.id })
        if (tonumber(n) or 0) < 1 then return fail('invalid_state', 'The report changed; try again.') end
        row.state, row.handover_at, row.handover_by, row.hospital_id, row.admission_id, row.updated_at = 'handed_over', at, staffCid, hospital, int(admission.id, 1), at
        syncCache(row)
        P.AddEntry(row, 'note', nil, staffCid, ('Handed over to %s at %s'):format(nameOf(Staff, staffCid), line(admission.hospital, 64) or humanize(hospital)), at)
        P.Vitals(row, true)
        return { ok = true, pcr = P.Public(row, false) }
    end)
end

--- Closes a report: the lead or a supervisor; 'transported' only after the handover, and a handed-over
--- report closes only as transported.
function P.Close(src, id, disposition)
    local Pl = player(src)
    if not Pl then return fail('offline', 'You are not loaded.') end
    if not isMedic(Pl) then return fail('not_on_duty', 'Medics on duty only.') end
    id = int(id, 1)
    local dispositions = cfg().Dispositions or {}
    if not id or type(disposition) ~= 'string' or not dispositions[disposition] then return fail('bad_args', 'Choose how the call ended.') end
    local cid = Pl.PlayerData.citizenid
    local supervisor = isSupervisor(Pl)
    return withPcr(id, function(row)
        if row.state == 'closed' then return fail('invalid_state', 'The report is closed.') end
        if row.lead_cid ~= cid and not supervisor then return fail('no_permission', 'Only the lead or a supervisor closes a report.') end
        if (disposition == 'transported') ~= (row.state == 'handed_over') then
            return fail('invalid_state', row.state == 'handed_over' and 'A handed-over report closes as transported.' or 'Transported needs the hospital to accept the handover.')
        end
        local at = now()
        if not P.CloseRow(row, disposition, at) then return fail('invalid_state', 'The report changed; try again.') end
        P.AddEntry(row, 'note', nil, cid, 'Closed: ' .. tostring(dispositions[disposition]), at)
        return { ok = true, pcr = P.Public(row, false) }
    end)
end

--- Closes reports nobody touched for Config.PCR.AutoCloseSeconds (named tick).
function P.Sweep(at)
    if not ready() then return 0 end
    at = at or now()
    local limit = at - (tonumber(cfg().AutoCloseSeconds) or 21600)
    local closed = tonumber(MySQL.update.await([[UPDATE `pf_emsmdt_pcr` SET `state` = 'closed', `disposition` = 'transported', `closed_at` = ?, `updated_at` = ?
        WHERE `state` = 'handed_over' AND `updated_at` < ?]], { at, at, limit })) or 0
    local stale = {}
    for cid, row in pairs(P.OpenByCid) do if (row.updated_at or 0) < limit then stale[#stale + 1] = cid end end
    for _, cid in ipairs(stale) do
        P.Serial(cid, function()
            local row = P.OpenByCid[cid]
            if row and (row.updated_at or 0) < limit and P.CloseRow(row, 'no_activity', at) then closed = closed + 1 end
        end)
    end
    return closed
end

-- ── reading ────────────────────────────────────────────────────────────────────────────────────

local function entriesOf(id)
    local out = {}
    local rows = MySQL.query.await('SELECT `id`, `kind`, `ref_id`, `by_cid`, `summary`, `at` FROM `pf_emsmdt_pcr_entries` WHERE `pcr_id` = ? ORDER BY `at`, `id` LIMIT ?',
        { id, tonumber(cfg().MaxEntries) or 300 }) or {}
    for _, e in ipairs(rows) do
        out[#out + 1] = { id = int(e.id), kind = e.kind, refId = int(e.ref_id), by = e.by_cid, byName = e.by_cid and nameOfCid(e.by_cid) or nil,
            summary = e.summary, at = int(e.at) }
    end
    return out
end

--- What viewers and callers see of a report.
function P.Public(row, withEntries)
    local out = {
        id = row.id, citizenid = row.citizenid, patientName = nameOf(playerByCid(row.citizenid), nil), callRef = row.call_ref, unit = row.unit,
        lead = { citizenid = row.lead_cid, name = nameOfCid(row.lead_cid) }, state = row.state, narrative = row.narrative,
        dispatchAt = row.dispatch_at, arriveAt = row.arrive_at, departAt = row.depart_at, handoverAt = row.handover_at,
        handoverBy = row.handover_by and { citizenid = row.handover_by, name = nameOfCid(row.handover_by) } or nil,
        hospitalId = row.hospital_id, admissionId = row.admission_id, disposition = row.disposition,
        dispositionLabel = row.disposition and ((cfg().Dispositions or {})[row.disposition] or humanize(row.disposition)) or nil,
        closedAt = row.closed_at, createdAt = row.created_at, updatedAt = row.updated_at, entryCount = row.entries,
    }
    if withEntries then out.entries = entriesOf(row.id) end
    return out
end

local function listRows(sql, args)
    local out = {}
    for _, r in ipairs(MySQL.query.await(sql, args) or {}) do out[#out + 1] = normalise(r) end
    return out
end

--- Reports where cid is the lead or charted a line, newest first.
function P.ListMine(cid)
    return listRows('SELECT ' .. ROW_COLS .. ' FROM `pf_emsmdt_pcr` p WHERE p.`lead_cid` = ? OR EXISTS (SELECT 1 FROM `pf_emsmdt_pcr_entries` e '
        .. 'WHERE e.`pcr_id` = p.`id` AND e.`by_cid` = ?) ORDER BY p.`id` DESC LIMIT ?', { cid, cid, tonumber(cfg().ListLimit) or 25 })
end

function P.ListPatient(cid)
    return listRows('SELECT ' .. ROW_COLS .. ' FROM `pf_emsmdt_pcr` p WHERE p.`citizenid` = ? ORDER BY p.`id` DESC LIMIT ?', { cid, tonumber(cfg().ListLimit) or 25 })
end

--- A patient's reports for a viewer: all of them when pf-ambulancejob lets the viewer see the medical
--- record (recordAllowed), otherwise only the ones the viewer crewed.
function P.ListForViewer(src, cid, recordAllowed)
    if not ready() or not validCid(cid) then return {} end
    local Pl = player(src)
    if not Pl then return {} end
    local viewer = Pl.PlayerData.citizenid
    local out = {}
    for _, row in ipairs(P.ListPatient(cid)) do
        if recordAllowed or viewer == cid or P.IsCrew(row, viewer) then out[#out + 1] = P.Public(row, false) end
    end
    return out
end

--- Whether pf-ambulancejob lets this player see the patient's medical record (an audited read there).
function P.RecordAllowed(src, cid)
    local Pl = player(src)
    if not Pl then return false end
    local purpose = Pl.PlayerData.citizenid == cid and 'self' or 'treatment'
    local res = aj('GetMedicalRecord', cid, { viewer = src, purpose = purpose })
    return res ~= nil and res.ok == true
end

--- Viewer access to one report: the crew, receiving staff while it waits for handover at a hospital,
--- the patient, or anyone pf-ambulancejob lets see the record.
function P.CanView(src, row)
    local Pl = player(src)
    if not Pl then return false end
    local cid = Pl.PlayerData.citizenid
    if cid == row.citizenid then return true end
    if not (isMedic(Pl) or isHospitalStaff(Pl)) then return false end
    if P.IsCrew(row, cid) then return true end
    if row.state == 'open' and row.hospital_id and isHospitalStaff(Pl) then return true end
    return P.RecordAllowed(src, row.citizenid)
end

-- ── exports (Config.Callers, privacy as GetMedicalRecord) ──────────────────────────────────────

local function callerAllowed(name)
    local invoker = GetInvokingResource()
    if invoker == nil or invoker == GetCurrentResourceName() then return true end
    local list = Config.Callers and Config.Callers[name]
    return list == '*' or (type(list) == 'table' and list[invoker] == true)
end

local function courtOrderValid(ref, cid)
    if GetResourceState('pf-justice') ~= 'started' then return false end
    local ok, valid = pcall(function() return exports['pf-justice']:IsCourtOrderValid(ref, 'medical_records', cid) end)
    return ok and valid == true
end

--- Returns a filter(row) -> bool for opts, or nil, error.
local function exportAccess(cid, opts)
    if type(opts) ~= 'table' then return nil, 'bad_args' end
    local purpose = opts.purpose
    if purpose == 'court_order' then
        local ref = opts.courtOrderId
        if not ((type(ref) == 'string' and ref ~= '' and #ref <= 64) or int(ref, 1)) then return nil, 'bad_args' end
        if not courtOrderValid(ref, cid) then return nil, 'no_permission' end
        return function() return true end
    end
    local src = int(opts.viewer, 1)
    if not src then return nil, 'bad_args' end
    local Pl = player(src)
    if not Pl then return nil, 'offline' end
    if purpose == 'self' then
        if Pl.PlayerData.citizenid ~= cid then return nil, 'no_permission' end
        return function() return true end
    elseif purpose == 'treatment' then
        if not (isMedic(Pl) or isHospitalStaff(Pl)) then return nil, 'no_permission' end
        local all = P.RecordAllowed(src, cid)
        local viewer = Pl.PlayerData.citizenid
        return function(row) return all or P.IsCrew(row, viewer) end
    end
    return nil, 'bad_args'
end

function P.ExportGetPcr(id, opts)
    if not callerAllowed('GetPcr') then return fail('not_allowed', 'Not allowed.') end
    id = int(id, 1)
    if not id then return fail('bad_args', 'Invalid report.') end
    if not ready() then return fail('db_unavailable', 'Reports are not available.') end
    local row = P.Load(id)
    if not row then return fail('not_found', 'No such report.') end
    local filter, err = exportAccess(row.citizenid, opts)
    if not filter then return fail(err) end
    if not filter(row) then return fail('not_found', 'No such report.') end
    return { ok = true, pcr = P.Public(row, true) }
end

function P.ExportListPcrFor(cid, opts)
    if not callerAllowed('ListPcrFor') then return fail('not_allowed', 'Not allowed.') end
    if not validCid(cid) then return fail('bad_args', 'Invalid citizen.') end
    if not ready() then return fail('db_unavailable', 'Reports are not available.') end
    local filter, err = exportAccess(cid, opts)
    if not filter then return fail(err) end
    local list = {}
    for _, row in ipairs(P.ListPatient(cid)) do if filter(row) then list[#list + 1] = P.Public(row, false) end end
    return { ok = true, list = list }
end

exports('GetPcr', function(id, opts) return P.ExportGetPcr(id, opts) end)
exports('ListPcrFor', function(cid, opts) return P.ExportListPcrFor(cid, opts) end)

-- ── callbacks ──────────────────────────────────────────────────────────────────────────────────

-- per source: writes 1 per second, reads 5 per second (server ids are reused, so the table stays small)
local last = {}
local function limited(src, write)
    local key, gap = write and 'w' or 'r', write and 1000 or 200
    last[src] = last[src] or {}
    local t = GetGameTimer()
    if last[src][key] and t - last[src][key] < gap then return true end
    last[src][key] = t
    return false
end

local function gate(source, write)
    local src = tonumber(source)
    if not src or src <= 0 then return nil, fail('bad_args', 'Invalid player.') end
    if limited(src, write) then return nil, fail('rate_limited', 'Slow down.') end
    if not ready() then return nil, fail('db_unavailable', 'Reports are not available yet.') end
    return src
end

QBCore.Functions.CreateCallback('pf_emsmdt:pcr:list', function(source, cb, data)
    local src, err = gate(source)
    if not src then return cb(err) end
    local Pl = player(src)
    if not (isMedic(Pl) or isHospitalStaff(Pl)) then return cb(fail('no_permission', 'EMS and hospital staff only.')) end
    data = type(data) == 'table' and data or {}
    if data.scope == 'patient' then
        local cid = data.citizenId
        if not validCid(cid) then return cb(fail('bad_args', 'Invalid citizen.')) end
        return cb({ ok = true, list = P.ListForViewer(src, cid, P.RecordAllowed(src, cid)) })
    end
    local list = {}
    for _, row in ipairs(P.ListMine(Pl.PlayerData.citizenid)) do list[#list + 1] = P.Public(row, false) end
    cb({ ok = true, list = list })
end)

QBCore.Functions.CreateCallback('pf_emsmdt:pcr:get', function(source, cb, data)
    local src, err = gate(source)
    if not src then return cb(err) end
    local id = int(type(data) == 'table' and data.id, 1)
    if not id then return cb(fail('bad_args', 'Invalid report.')) end
    local row = P.Load(id)
    if not row or not P.CanView(src, row) then return cb(fail('not_found', 'No such report.')) end
    local Pl = player(src)
    local cid = Pl.PlayerData.citizenid
    local crew = P.IsCrew(row, cid)
    local out = P.Public(row, true)
    out.can = {
        narrative = row.state ~= 'closed' and crew and isMedic(Pl),
        close = row.state ~= 'closed' and isMedic(Pl) and (row.lead_cid == cid or isSupervisor(Pl)),
        acknowledge = row.state == 'open' and isHospitalStaff(Pl) and ((cfg().Handover or {}).CrewMayAcknowledge == true or not (crew or P.OnCrewUnit(row, cid))),
    }
    cb({ ok = true, pcr = out, dispositions = cfg().Dispositions or {}, narrativeMax = tonumber(cfg().NarrativeMax) or 4000 })
end)

QBCore.Functions.CreateCallback('pf_emsmdt:pcr:saveNarrative', function(source, cb, data)
    local src, err = gate(source, true)
    if not src then return cb(err) end
    data = type(data) == 'table' and data or {}
    cb(P.SaveNarrative(src, data.id, data.text))
end)

QBCore.Functions.CreateCallback('pf_emsmdt:pcr:acknowledgeHandover', function(source, cb, data)
    local src, err = gate(source, true)
    if not src then return cb(err) end
    cb(P.AcknowledgeHandover(src, type(data) == 'table' and data.id or nil))
end)

QBCore.Functions.CreateCallback('pf_emsmdt:pcr:close', function(source, cb, data)
    local src, err = gate(source, true)
    if not src then return cb(err) end
    data = type(data) == 'table' and data or {}
    cb(P.Close(src, data.id, data.disposition))
end)

--- Open reports of patients who are at a hospital (pf-ambulancejob admission seen), for staff.
QBCore.Functions.CreateCallback('pf_emsmdt:pcr:pendingHandovers', function(source, cb)
    local src, err = gate(source)
    if not src then return cb(err) end
    if not isHospitalStaff(player(src)) then return cb(fail('no_permission', 'Hospital staff only.')) end
    local list = {}
    for _, row in pairs(P.OpenByCid) do
        if row.hospital_id then list[#list + 1] = P.Public(row, false) end
    end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    cb({ ok = true, list = list })
end)

-- ── lifecycle ──────────────────────────────────────────────────────────────────────────────────

AddEventHandler('pfm-core:server:characterDeleted', function(cid)
    local s = tonumber(source)
    if s and s > 0 then return end
    if not validCid(cid) or not ready() then return end
    P.OpenByCid[cid] = nil
    MySQL.query.await('DELETE FROM `pf_emsmdt_pcr` WHERE `citizenid` = ?', { cid }) -- lines go with them (ON DELETE CASCADE)
end)

function P.Start()
    P.LoadOpen()
    started = true
    local queued = backlog
    backlog = {}
    for _, fn in ipairs(queued) do pcall(fn) end
end

if PFEmsSchema and PFEmsSchema.OnReady then
    PFEmsSchema.OnReady(function()
        local ok, err = pcall(P.Start)
        if not ok then print('^3[pf-emsmdt]^7 open PCRs not loaded: ' .. tostring(err)) end
    end)
end

function P.Tick() return P.Sweep(now()) end

CreateThread(function()
    while true do
        Wait(math.max(30, tonumber(cfg().SweepSeconds) or 300) * 1000)
        pcall(P.Tick)
    end
end)
