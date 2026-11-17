-- Medical care in custody (batch 19G; architecture 4.1 SetCustodyCare, 4.5, 5.3, 5.4, 6.6).
--
-- A custody patient is a citizen with an open pf-justice custody record or an incarceration order
-- (legacy: metadata injail > 0). For them the hospital works differently:
--   * The prison infirmary (a facility with `custody = true`, beds from the old 'jailbeds') takes
--     inmates through an infirmary visit; intake screening runs automatically when an incarceration
--     order is created (and staff may screen any custody patient).
--   * A transfer to a public hospital needs an on-duty officer (police / corrections) within
--     Custody.EscortDistance of the patient (server positions). The custody record moves to
--     'hospital' (pf-justice TransferCustody) and comes back with ReturnCustody when the admission
--     ends, so custody is continuous. Leaving the hospital, an absent escort, a transfer that never
--     arrives and going offline are REPORTED (custody log, pf_med_custody_reports, officers, a
--     server event), never punished: a custody patient cannot become "left AMA".
--   * Prescriptions for inmates are dispensed from the infirmary stock stash (pf_hosp_prescriptions,
--     pf_hosp_dispense_log; 20A's pharmacy builds on the same tables).
--   * Privacy: corrections and police only ever get fit_for_work, restriction kinds and
--     infirmary_needed (GetInmateMedicalStatus / callback inmateMedical).
-- Care rows (pf_med_custody_care) persist across restarts; at most one active row per citizen
-- (UNIQUE active_cid). This file loads after admissions.lua and wraps A.Close, A.Tick, A.Transfer
-- and A.ExportAdmitPatient (looked up at call time by the callbacks, exports and threads there).

PFHospital = PFHospital or {}
local H = PFHospital
H.Custody = H.Custody or {}
local C = H.Custody
H.SQL = H.SQL or {}
local Q = H.SQL
local A = H.Admissions

local function cfg() return Config.Hospital.Custody end
local function now() return H.Now() end
local SYSTEM = { kind = 'system', label = 'custody_care' }

C.active = {}      -- [cid] = care row + memory fields (escortAwaySince, outsideSince, ...)
C.linking = {}     -- [cid] = true while this module creates/links an admission itself
local ready = false

-- ── SQL (the real-DB spec runs every statement) ─────────────────────────────────────────────

local CARE_COLS = 'id, citizenid, kind, state, custody_id, order_id, facility, admission_id, hospital_id, escort_cid, ju_transfer, by_cid, created_at, closed_at, close_reason, idem_key'

function Q.InsertCare(r)
    return MySQL.insert.await([[INSERT INTO pf_med_custody_care (citizenid, active_cid, kind, state, custody_id, order_id, facility,
        admission_id, hospital_id, escort_cid, ju_transfer, by_cid, created_at, idem_key) VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { r.citizenid, r.citizenid, r.kind, r.custody_id, r.order_id, r.facility, r.admission_id, r.hospital_id, r.escort_cid,
            r.ju_transfer and 1 or 0, r.by_cid, r.created_at, r.idem_key })
end

function Q.FindCareByKey(key)
    return MySQL.single.await('SELECT ' .. CARE_COLS .. ' FROM pf_med_custody_care WHERE idem_key = ? LIMIT 1', { key })
end

function Q.ActiveCareOf(cid)
    return MySQL.single.await('SELECT ' .. CARE_COLS .. ' FROM pf_med_custody_care WHERE active_cid = ? LIMIT 1', { cid })
end

function Q.LoadActiveCare(limit)
    return MySQL.query.await('SELECT ' .. CARE_COLS .. ' FROM pf_med_custody_care WHERE active_cid IS NOT NULL ORDER BY id LIMIT ?', { limit or 1000 }) or {}
end

--- Rewrites the mutable fields of an active care row. Returns rows changed.
function Q.UpdateCare(id, r)
    return H.Affected(MySQL.update.await([[UPDATE pf_med_custody_care SET kind = ?, custody_id = ?, order_id = ?, facility = ?, admission_id = ?,
        hospital_id = ?, escort_cid = ?, ju_transfer = ? WHERE id = ? AND active_cid IS NOT NULL]],
        { r.kind, r.custody_id, r.order_id, r.facility, r.admission_id, r.hospital_id, r.escort_cid, r.ju_transfer and 1 or 0, id }))
end

--- Closes an active care row once (a second close changes nothing). Returns rows changed.
function Q.CloseCare(id, state, reason, at)
    return H.Affected(MySQL.update.await([[UPDATE pf_med_custody_care SET state = ?, close_reason = ?, closed_at = ?, active_cid = NULL
        WHERE id = ? AND active_cid IS NOT NULL]], { state, type(reason) == 'string' and reason:sub(1, 32) or nil, at, id }))
end

function Q.SetAdmissionCustody(admissionId, ref, escortCid)
    return H.Affected(MySQL.update.await('UPDATE pf_hosp_admissions SET custody_ref = ?, escort_cid = ? WHERE id = ?', { ref, escortCid, admissionId }))
end

function Q.InsertCareReport(r)
    return MySQL.insert.await('INSERT INTO pf_med_custody_reports (care_id, citizenid, kind, detail, at) VALUES (?, ?, ?, ?, ?)',
        { r.care_id, r.citizenid, r.kind, r.detail, r.at })
end

function Q.ListCareReports(careId, limit)
    return MySQL.query.await('SELECT id, care_id, citizenid, kind, detail, at FROM pf_med_custody_reports WHERE care_id = ? ORDER BY id LIMIT ?',
        { careId, limit or 50 }) or {}
end

local SCR_COLS = 'id, citizenid, context, custody_ref, result, fit_for_work, infirmary_needed, restrictions, note, by_cid, at, idem_key'

function Q.InsertScreening(r)
    return MySQL.insert.await([[INSERT INTO pf_med_screenings (citizenid, context, custody_ref, result, fit_for_work, infirmary_needed, restrictions,
        note, by_cid, at, idem_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { r.citizenid, r.context, r.custody_ref, r.result, r.fit_for_work and 1 or 0, r.infirmary_needed and 1 or 0, r.restrictions,
            r.note, r.by_cid, r.at, r.idem_key })
end

function Q.FindScreeningByKey(key)
    return MySQL.single.await('SELECT ' .. SCR_COLS .. ' FROM pf_med_screenings WHERE idem_key = ? LIMIT 1', { key })
end

function Q.LatestScreening(cid, since)
    return MySQL.single.await('SELECT ' .. SCR_COLS .. ' FROM pf_med_screenings WHERE citizenid = ? AND at >= ? ORDER BY at DESC, id DESC LIMIT 1',
        { cid, since })
end

local RX_COLS = 'id, citizenid, drug, dose, qty, refills, controlled, prescriber_cid, state, created_at, expires_at, dispensed, interval_seconds, last_dispensed_at, custody_ref, note'

function Q.InsertRx(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_prescriptions (citizenid, drug, dose, qty, refills, controlled, prescriber_cid, state, created_at,
        expires_at, dispensed, interval_seconds, custody_ref, note) VALUES (?, ?, ?, ?, 0, ?, ?, 'active', ?, ?, 0, ?, ?, ?)]],
        { r.citizenid, r.drug, r.dose, r.qty, r.controlled and 1 or 0, r.prescriber_cid, r.created_at, r.expires_at, r.interval_seconds,
            r.custody_ref, r.note })
end

function Q.GetRx(id)
    return MySQL.single.await('SELECT ' .. RX_COLS .. ' FROM pf_hosp_prescriptions WHERE id = ? LIMIT 1', { id })
end

function Q.ActiveRx(cid, at)
    return MySQL.query.await('SELECT ' .. RX_COLS .. " FROM pf_hosp_prescriptions WHERE citizenid = ? AND state = 'active' AND expires_at > ? ORDER BY id LIMIT 20",
        { cid, at }) or {}
end

--- Takes the next dose of an active prescription, only while `dispensed` is still what the caller
--- saw (two requests cannot both take dose n). The last dose fills it. Returns rows changed.
function Q.ReserveDose(id, dispensed, at)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_prescriptions SET state = CASE WHEN dispensed + 1 >= qty THEN 'filled' ELSE state END,
        dispensed = dispensed + 1, last_dispensed_at = ? WHERE id = ? AND state = 'active' AND dispensed = ?]], { at, id, dispensed }))
end

--- Gives a reserved dose back (the items could not be moved). Returns rows changed.
function Q.UndoDose(id, dispensedAfter, prevLastAt)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_prescriptions SET state = 'active', dispensed = dispensed - 1, last_dispensed_at = ?
        WHERE id = ? AND dispensed = ?]], { prevLastAt, id, dispensedAfter }))
end

function Q.InsertDispense(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_dispense_log (prescription_id, citizenid, drug, qty, by_cid, stash, at, dose_no, idem_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], { r.prescription_id, r.citizenid, r.drug, r.qty, r.by_cid, r.stash, r.at, r.dose_no, r.idem_key })
end

function Q.DeleteDispense(key)
    return H.Affected(MySQL.update.await('DELETE FROM pf_hosp_dispense_log WHERE idem_key = ?', { key }))
end

function Q.CancelRx(id)
    return H.Affected(MySQL.update.await("UPDATE pf_hosp_prescriptions SET state = 'cancelled' WHERE id = ? AND state = 'active'", { id }))
end

function Q.ExpireRx(at)
    return H.Affected(MySQL.update.await("UPDATE pf_hosp_prescriptions SET state = 'expired' WHERE state = 'active' AND expires_at <= ?", { at }))
end

-- ── other resources ─────────────────────────────────────────────────────────────────────────

--- Calls a pf-justice export (nil, 'unavailable' when it is not running or the call raised).
local function ju(name, ...)
    if not H.Started('pf-justice') then return nil, 'unavailable' end
    local args = table.pack(...)
    local ok, a, b, c = pcall(function()
        local e = exports['pf-justice']
        return e[name](e, table.unpack(args, 1, args.n))
    end)
    if not ok then return nil, 'unavailable' end
    return a, b, c
end
C.Justice = ju

local function inventory(name, ...)
    local args = table.pack(...)
    local ok, res = pcall(function()
        local e = exports['pfm-inventory']
        return e[name](e, table.unpack(args, 1, args.n))
    end)
    return ok and res or nil
end

-- ── who is in custody, officers ─────────────────────────────────────────────────────────────

--- The custody status of a citizen: { custodyId?, custodyState?, orderId?, facility, legacy? } or nil.
function C.CustodyStatus(cid)
    local st
    local res = ju('GetCustody', cid)
    if type(res) == 'table' and res.ok and type(res.custody) == 'table' and not res.custody.closedAt then
        st = { custodyId = tonumber(res.custody.id), custodyState = res.custody.state, facility = res.custody.facility }
    end
    local inc, orderId, fac = ju('IsIncarcerated', cid)
    if inc == true then
        st = st or {}
        st.orderId, st.facility = tonumber(orderId), st.facility or fac
    end
    if not st then
        local P = H.PlayerByCid(cid)
        local jail = P and tonumber(P.PlayerData.metadata and P.PlayerData.metadata.injail) or 0
        if jail > 0 then st = { facility = Config.Hospital.CustodyFacility, legacy = true } end
    end
    return st
end

function C.RefOf(t)
    if t.custodyId or t.custody_id then return ('custody:%d'):format(t.custodyId or t.custody_id) end
    if t.orderId or t.order_id then return ('order:%d'):format(t.orderId or t.order_id) end
    return ('facility:%s'):format(tostring(t.facility or '?')):sub(1, 64)
end

--- An on-duty officer (police / corrections by job or job type).
function C.IsOfficer(P)
    local job = P and P.PlayerData.job
    if type(job) ~= 'table' or job.onduty ~= true then return false end
    return cfg().OfficerJobs[job.name] == true or (job.type ~= nil and cfg().OfficerJobTypes[job.type] == true)
end

local function players()
    local ok, list = pcall(function() return PFAmbulance.GetCore().Functions.GetQBPlayers() end)
    return ok and type(list) == 'table' and list or {}
end

--- The nearest on-duty officer within EscortDistance of a player (server positions): src, P.
function C.NearestOfficer(patientSrc)
    local pos = H.Pos(patientSrc)
    if not pos then return nil end
    local best, bestP, bestD
    for _, P in pairs(players()) do
        local s = P.PlayerData.source
        if s ~= patientSrc and C.IsOfficer(P) then
            local d = H.Dist(H.Pos(s), pos)
            if d <= cfg().EscortDistance and (not bestD or d < bestD) then best, bestP, bestD = s, P, d end
        end
    end
    return best, bestP
end

--- The escort of a care if they are online, on duty and within EscortDistance of the patient.
function C.EscortNear(care, patientSrc)
    local esrc = care.escort_cid and H.SourceOfCid(care.escort_cid)
    if not esrc or not patientSrc then return nil end
    if not C.IsOfficer(H.Player(esrc)) then return nil end
    if H.Dist(H.Pos(esrc), H.Pos(patientSrc)) > cfg().EscortDistance then return nil end
    return esrc
end

local function notifyOfficers(text, extra)
    local any = false
    for _, P in pairs(players()) do
        if C.IsOfficer(P) then
            any = true
            H.Notify(P.PlayerData.source, text, 'police')
        end
    end
    if extra then H.Notify(extra, text, 'police') end
    return any
end
C.NotifyOfficers = notifyOfficers

local function notifyStaff(text)
    for _, P in pairs(players()) do
        if H.IsStaff(P) then H.Notify(P.PlayerData.source, text, 'ambulance') end
    end
end

local function anyOfficer()
    for _, P in pairs(players()) do if C.IsOfficer(P) then return true end end
    return false
end

-- ── care rows (memory + database) ───────────────────────────────────────────────────────────

local function rememberCare(r)
    r.id = tonumber(r.id)
    r.custody_id, r.order_id, r.admission_id = tonumber(r.custody_id), tonumber(r.order_id), tonumber(r.admission_id)
    r.ju_transfer = r.ju_transfer == true or tonumber(r.ju_transfer) == 1
    r.created_at = tonumber(r.created_at)
    C.active[r.citizenid] = r
    return r
end

function C.Of(cid) return cid and C.active[cid] or nil end

--- The active care linked to an admission (memory).
function C.ForAdmission(a)
    local care = a and C.active[a.citizenid]
    if care and care.admission_id == a.id then return care end
    return nil
end

--- What other resources see of a care (no clinical data).
function C.Public(care)
    if not care then return nil end
    local a = care.admission_id and A.ById(care.admission_id)
    return {
        id = care.id, cid = care.citizenid, kind = care.kind, state = care.state, custodyId = care.custody_id, orderId = care.order_id,
        facility = care.facility, hospitalId = care.hospital_id, admissionId = care.admission_id, admissionState = a and a.state or nil,
        escortCid = care.escort_cid, since = care.created_at,
    }
end

local function emit(care, change)
    TriggerEvent('pf-ambulancejob:server:custodyCareChanged', care.citizenid, C.Public(care), change)
end

--- Opens (or updates) the citizen's active care. spec = { kind, custodyId, orderId, facility,
--- admissionId, hospitalId, escortCid, juTransfer, key, byCid }. Returns care | nil, err.
function C.Upsert(cid, spec)
    local care = C.active[cid]
    if care then
        local row = {
            kind = spec.kind or care.kind, custody_id = spec.custodyId or care.custody_id, order_id = spec.orderId or care.order_id,
            facility = spec.facility or care.facility, admission_id = care.admission_id, hospital_id = care.hospital_id,
            escort_cid = care.escort_cid, ju_transfer = care.ju_transfer,
        }
        if spec.admissionId ~= nil then row.admission_id = spec.admissionId end
        if spec.hospitalId ~= nil then row.hospital_id = spec.hospitalId end
        if spec.escortCid ~= nil then row.escort_cid = spec.escortCid or nil end
        if spec.juTransfer ~= nil then row.ju_transfer = spec.juTransfer end
        local ok, n = pcall(Q.UpdateCare, care.id, row)
        if not ok then return nil, 'db_unavailable' end
        if n ~= 1 then
            -- closed meanwhile: forget it and open a new one below
            C.active[cid] = nil
        else
            for k, v in pairs(row) do care[k] = v end
            emit(care, 'updated')
            return care
        end
    end
    local r = {
        citizenid = cid, kind = spec.kind or 'marked', custody_id = spec.custodyId, order_id = spec.orderId, facility = spec.facility,
        admission_id = spec.admissionId, hospital_id = spec.hospitalId, escort_cid = spec.escortCid or nil, ju_transfer = spec.juTransfer == true,
        by_cid = spec.byCid, created_at = now(), idem_key = spec.key, state = 'active',
    }
    local ok, id = pcall(Q.InsertCare, r)
    id = ok and tonumber(id) or nil
    if not id then
        -- another server path won the UNIQUE active_cid: take that row
        local okRow, row = pcall(Q.ActiveCareOf, cid)
        if okRow and row then return rememberCare(row) end
        return nil, 'db_unavailable'
    end
    r.id = id
    care = rememberCare(r)
    H.Audit(cid, 'custody_care', SYSTEM, { care = id, kind = r.kind, custody = r.custody_id, order = r.order_id })
    emit(care, 'opened')
    return care
end

--- Links an open admission to the care (both rows and memory).
--- escortCid: a citizenid sets the escort, false clears it, nil keeps the care's escort.
function C.LinkAdmission(care, a, escortCid)
    local ref = C.RefOf(care)
    local escort = care.escort_cid
    if escortCid == false then escort = nil elseif escortCid ~= nil then escort = escortCid end
    a.custody_ref, a.escort_cid = ref, escort
    pcall(Q.SetAdmissionCustody, a.id, ref, escort)
    return C.Upsert(care.citizenid, { admissionId = a.id, hospitalId = a.hospital_id, escortCid = escortCid })
end

--- Closes the care for good. Returns true when this call closed it.
function C.CloseCare(care, state, reason)
    local ok, n = pcall(Q.CloseCare, care.id, state, reason, now())
    if not ok then return false end
    if C.active[care.citizenid] == care then C.active[care.citizenid] = nil end
    care.state = state
    if n == 1 then
        H.Audit(care.citizenid, 'custody_care_end', SYSTEM, { care = care.id, state = state, reason = reason })
        emit(care, state)
    end
    return n == 1
end

-- ── reports (never punishments) ─────────────────────────────────────────────────────────────

local REPORT_TEXT = {
    escort_away = 'has no escort officer within %d m',
    escort_back = 'is escorted again',
    left_zone = 'left the hospital grounds',
    returned_zone = 'is back inside the hospital',
    left_infirmary = 'walked out of the infirmary',
    not_arrived = 'has not arrived at the hospital',
    patient_offline = 'disconnected while in hospital custody',
    discharged_no_escort = 'was discharged with no escort present',
    returned_by_system = 'was returned to custody by the facility (no officer on duty)',
}

--- One report: a pf_med_custody_reports row, a pf-justice custody-log note, an audit row, the
--- server event pf-ambulancejob:server:custodyCareAlert and a notice to on-duty officers.
function C.Report(care, kind, detail)
    local t = now()
    local P = H.PlayerByCid(care.citizenid)
    local text = ('%s %s'):format(H.CharName(P), (REPORT_TEXT[kind] or kind):format(math.floor(cfg().EscortDistance)))
    detail = H.Text(detail or text, 255)
    pcall(Q.InsertCareReport, { care_id = care.id, citizenid = care.citizenid, kind = kind:sub(1, 24), detail = detail, at = t })
    if care.custody_id then ju('AddCustodyLog', care.custody_id, 'note', { event = kind, text = detail, hospital = care.hospital_id }) end
    H.Audit(care.citizenid, 'custody_' .. kind, SYSTEM, { care = care.id, hospital = care.hospital_id })
    TriggerEvent('pf-ambulancejob:server:custodyCareAlert', care.citizenid, { careId = care.id, kind = kind, custodyId = care.custody_id,
        orderId = care.order_id, hospitalId = care.hospital_id, facility = care.facility, at = t })
    notifyOfficers(('Custody patient: %s.'):format(text), care.escort_cid and H.SourceOfCid(care.escort_cid) or nil)
end

-- ── ending care: the custody record comes back from 'hospital' ─────────────────────────────

local function placeAt(src, point)
    if not src or not point then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return pcall(SetEntityCoords, ped, point.x + 0.0, point.y + 0.0, point.z + 0.0, false, false, false, false)
end

--- Returns the custody record (pf-justice ReturnCustody while it is in 'hospital'), then closes the
--- care. A refused or unreachable return keeps the care active and the tick retries it.
function C.FinishReturn(care, reason)
    if care.finishing then return false end
    care.finishing = true
    local src = H.SourceOfCid(care.citizenid)
    local esrc = C.EscortNear(care, src)
    if care.custody_id then
        local cur = ju('GetCustody', care.citizenid)
        local c = type(cur) == 'table' and cur.ok and cur.custody or nil
        if cur == nil then care.finishing = false return false end
        if c and tonumber(c.id) == care.custody_id and not c.closedAt and c.state == 'hospital' then
            local res = ju('ReturnCustody', care.custody_id, { actor = esrc and { src = esrc } or nil })
            if type(res) ~= 'table' or not res.ok then
                care.finishing = false
                return false
            end
        end
    end
    local public = care.hospital_id and Config.Hospital.Facilities[care.hospital_id]
    local outside = public and not public.custody
    if outside and src and not esrc then
        C.Report(care, 'discharged_no_escort')
        if cfg().AutoReturnWithoutOfficers and not anyOfficer() then
            local fac = care.facility or Config.Hospital.CustodyFacility
            if placeAt(src, cfg().ReturnPoints[fac or '']) then C.Report(care, 'returned_by_system') end
        end
    elseif outside and esrc then
        H.Notify(esrc, ('%s was discharged: take them back to custody.'):format(H.CharName(H.PlayerByCid(care.citizenid))), 'police')
    end
    C.CloseCare(care, 'returned', reason or 'discharged')
    care.finishing = false
    -- a discharge re-screens the patient, so an old "infirmary needed" does not outlive the care
    if reason == 'discharged' then pcall(C.Screen, care.citizenid, { context = 'infirmary', custodyRef = C.RefOf(care) }) end
    return true
end

-- ── wraps of the admissions module ──────────────────────────────────────────────────────────

-- A custody patient never leaves as left_ama; any other close ends (or, for a transfer, keeps) the care.
local baseClose = A.Close
function A.Close(a, to, ctx)
    local care = C.ForAdmission(a)
    if care and to == 'left_ama' then return nil, 'invalid_state' end
    local res, err = baseClose(a, to, ctx)
    if res and care and to ~= 'transferred' then C.FinishReturn(care, to) end
    return res, err
end

-- Care in custody is not billed to the inmate (Custody.BillPatient = false).
if H.Billing and H.Billing.ForAdmission then
    local baseBill = H.Billing.ForAdmission
    H.Billing.ForAdmission = function(a, ctx)
        if not cfg().BillPatient and a and (a.custody_ref or C.ForAdmission(a)) then return nil end
        return baseBill(a, ctx)
    end
end

--- One pass over custody patients (named for specs): escort distance, leaving the grounds, a
--- transfer that never arrived, offline; returns custody that is due. Runs before the admissions
--- tick and keeps that tick from closing custody admissions as left AMA.
function C.Tick(at)
    at = at or now()
    local c = cfg()
    local list = {}
    for _, care in pairs(C.active) do list[#list + 1] = care end
    table.sort(list, function(x, y) return x.id < y.id end)
    for _, care in ipairs(list) do
        local a = care.admission_id and A.ById(care.admission_id)
        if care.relinking or care.finishing then
            -- an action of this module is moving the care right now
        elseif care.admission_id and not a then
            C.FinishReturn(care, 'admission_closed')
        elseif a then
            local f = Config.Hospital.Facilities[a.hospital_id] or {}
            local src = H.SourceOfCid(care.citizenid)
            if not src then
                if not care.offlineReported then care.offlineReported = true C.Report(care, 'patient_offline') end
                a.offlineSince = at -- custody admissions stay open while the patient is away
            else
                care.offlineReported = nil
                if H.Facility.InFacility(src, a.hospital_id) then
                    if care.outsideReported then C.Report(care, 'returned_zone') end
                    care.insideSeen, care.outsideSince, care.outsideReported = true, nil, nil
                elseif care.insideSeen then
                    care.outsideSince = care.outsideSince or at
                    if not care.outsideReported and at - care.outsideSince >= c.LeaveGraceSeconds then
                        care.outsideReported = true
                        C.Report(care, f.custody and 'left_infirmary' or 'left_zone')
                    end
                    if f.custody and at - care.outsideSince >= c.InfirmaryLeaveCloseSeconds then
                        -- inside the walls but out of the infirmary for long: the bed is freed (a discharge, never left AMA)
                        A.WithAdmission(a.id, function(adm)
                            A.Close(adm, 'discharged', { actor = SYSTEM, reason = 'left_infirmary' })
                            return { ok = true }
                        end)
                    end
                elseif care.arriveBy and at >= care.arriveBy and not care.arriveReported then
                    care.arriveReported = true
                    C.Report(care, 'not_arrived')
                end
                if not f.custody and A.ById(care.admission_id) then
                    if C.EscortNear(care, src) then
                        if care.escortReported then C.Report(care, 'escort_back') end
                        care.escortAwaySince, care.escortReported = nil, nil
                    else
                        care.escortAwaySince = care.escortAwaySince or at
                        if not care.escortReported and at - care.escortAwaySince >= c.EscortGraceSeconds then
                            care.escortReported = true
                            C.Report(care, 'escort_away')
                        end
                    end
                end
            end
            a.outsideSince, a.arriveBy = nil, nil
        end
    end
    if not C.lastExpireAt or at - C.lastExpireAt >= 600 then
        C.lastExpireAt = at
        pcall(Q.ExpireRx, at)
    end
end

local baseTick = A.Tick
function A.Tick(at)
    at = at or now()
    if ready then C.Tick(at) end
    return baseTick(at)
end

-- ── moving a custody patient between facilities ─────────────────────────────────────────────

--- The shared core of every custody move (caller checked roles, distance and the escort).
--- cid, status (C.CustodyStatus), fid = target facility, escortSrc (nil only inside the walls),
--- actor (audit), from = the open admission to close as transferred (or nil).
--- Returns { ok, admissionId, from? } or a failure.
function C.MoveTo(cid, status, fid, escortSrc, actor, from)
    local f = H.Facility.Get(fid)
    local escortCid = escortSrc and H.Player(escortSrc) and H.Player(escortSrc).PlayerData.citizenid or nil
    local res, err = H.WithLock('cid:' .. cid, function()
        local cur = A.OpenOf(cid)
        if cur and cur.hospital_id == fid then
            local care = C.Upsert(cid, { kind = f.custody and 'infirmary' or 'transfer', custodyId = status.custodyId, orderId = status.orderId,
                facility = status.facility })
            if care then C.LinkAdmission(care, cur, escortCid) end
            return { ok = true, duplicate = true, admissionId = cur.id }
        end
        if from and cur ~= from then return H.Fail('invalid_state', 'The admission changed; try again.') end
        -- the custody record moves first: nothing changes here when pf-justice refuses
        local juDone = false
        if status.custodyId and not f.custody and status.custodyState ~= 'hospital' then
            local r = ju('TransferCustody', status.custodyId, { kind = 'hospital', id = fid }, { actor = escortSrc and { src = escortSrc } or nil })
            if type(r) ~= 'table' or not r.ok then
                return H.Fail(type(r) == 'table' and r.error or 'busy', type(r) == 'table' and r.message or 'The custody record could not be moved.')
            end
            juDone = true
        end
        local care = C.active[cid]
        if care then care.relinking = true end
        local fromId
        if cur then
            local closed = A.WithAdmission(cur.id, function(adm)
                local done, cerr = A.Close(adm, 'transferred', { actor = actor, reason = 'custody to ' .. fid })
                if not done then return H.Fail(cerr, 'The admission changed; try again.') end
                return { ok = true }
            end)
            if not closed.ok then
                if care then care.relinking = nil end
                if juDone then ju('ReturnCustody', status.custodyId, { actor = escortSrc and { src = escortSrc } or nil }) end
                return closed
            end
            fromId = cur.id
        end
        C.linking[cid] = true
        local a, cerr = A.Create(cid, { hospitalId = fid, state = 'waiting', reason = f.custody and 'infirmary transfer' or 'custody transfer',
            actor = actor, triage = A.AutoTriage(cid), staff = true })
        C.linking[cid] = nil
        if not a then
            if care then care.relinking = nil end
            if juDone then ju('ReturnCustody', status.custodyId, { actor = escortSrc and { src = escortSrc } or nil }) end
            return H.Fail(cerr or 'db_unavailable', 'The hospital records are unavailable; try again.')
        end
        care = C.Upsert(cid, { kind = f.custody and 'infirmary' or 'transfer', custodyId = status.custodyId, orderId = status.orderId,
            facility = status.facility, juTransfer = juDone or (care and care.ju_transfer) or status.custodyState == 'hospital',
            byCid = actor and actor.cid })
        if care then
            C.LinkAdmission(care, a, escortCid or false)
            care.relinking, care.insideSeen, care.outsideSince, care.outsideReported = nil, false, nil, nil
            care.arriveBy, care.arriveReported = now() + (cfg().ArriveSeconds or 1800), nil
            care.escortAwaySince, care.escortReported = nil, nil
        end
        -- back inside the walls from a public hospital: the custody record leaves 'hospital'
        if f.custody and status.custodyId and status.custodyState == 'hospital' then
            ju('ReturnCustody', status.custodyId, { actor = escortSrc and { src = escortSrc } or nil })
            if care then C.Upsert(cid, { juTransfer = false }) end
        end
        A.OpenRequest(a)
        return { ok = true, admissionId = a.id, from = fromId }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    if res.ok and not res.duplicate then
        local P = H.PlayerByCid(cid)
        notifyStaff(('Custody patient %s is coming to %s.'):format(H.CharName(P), f.label))
        if escortSrc then H.Notify(escortSrc, ('You are the escort: stay within %d m of the patient.'):format(math.floor(cfg().EscortDistance)), 'police') end
    end
    return res
end

-- The medic's transfer callback: a custody patient needs an officer escort within EscortDistance.
local baseTransfer = A.Transfer
function A.Transfer(src, admissionId, to)
    local a = A.ById(admissionId)
    if not a then return baseTransfer(src, admissionId, to) end
    local status = C.CustodyStatus(a.citizenid)
    if not status then return baseTransfer(src, admissionId, to) end
    if H.Limited(src, 'ctransfer', 2) then return H.Fail('rate_limited', 'Slow down.') end
    if type(to) ~= 'table' then return H.Fail('bad_args', 'Choose where to.') end
    local tid = H.Facility.Id(to.hospitalId or to.facility)
    if not tid then return H.Fail('bad_args', 'Unknown facility.') end
    if tid == a.hospital_id then return H.Fail('bad_args', 'The patient is already here.') end
    local P, tierOrErr, msg = H.Provider(src, a.hospital_id, Config.Hospital.Roles.TransferTier)
    if not P then return H.Fail(tierOrErr, msg) end
    local tf = H.Facility.Get(tid)
    if tf.custody and not (status.orderId or status.legacy) then return H.Fail('no_permission', 'Only inmates go to the prison infirmary.') end
    local psrc = H.SourceOfCid(a.citizenid)
    if not psrc then return H.Fail('offline', 'The patient is not here.') end
    local esrc = C.NearestOfficer(psrc)
    if not esrc then
        return H.Fail('too_far', ('An on-duty officer must escort the patient (within %d m).'):format(math.floor(cfg().EscortDistance)))
    end
    return C.MoveTo(a.citizenid, status, tid, esrc, H.ActorOf(src, P), a)
end

-- AdmitPatient with spec.custodyRef (architecture 4.5): pf-justice / pfm-prison admit a custody
-- patient. A public hospital needs opts.escort (an on-duty officer's server id within EscortDistance).
local baseAdmit = A.ExportAdmitPatient
function A.ExportAdmitPatient(cid, spec, opts)
    if type(spec) ~= 'table' or spec.custodyRef == nil then return baseAdmit(cid, spec, opts) end
    -- the caller check comes before pf-justice is asked to move anything
    local okCaller = PFMed.Api.Allowed('AdmitPatient')
    if not okCaller then return H.Fail('not_allowed', 'Not allowed.') end
    if not ready or not A.Ready() then return H.Fail('db_unavailable', 'The hospital is not ready.') end
    if type(opts) ~= 'table' or not H.ValidKey(opts.key) then return H.Fail('bad_args', 'spec and opts.key are required.') end
    local ref = spec.custodyRef
    if type(ref) ~= 'table' then return H.Fail('bad_args', 'custodyRef must be a table.') end
    local custodyId = ref.custodyId ~= nil and H.Int(ref.custodyId, 1) or nil
    local orderId = ref.orderId ~= nil and H.Int(ref.orderId, 1) or nil
    if (ref.custodyId ~= nil and not custodyId) or (ref.orderId ~= nil and not orderId) then return H.Fail('bad_args', 'Invalid custody reference.') end
    local fid = H.Facility.Id(spec.hospitalId)
    local f = fid and H.Facility.Get(fid)
    if not f then return H.Fail('bad_args', 'Unknown hospital.') end
    if type(cid) ~= 'string' or not PFMed.Store.ValidCitizenId(cid) then return H.Fail('bad_args', 'Invalid citizen id.') end
    local status = C.CustodyStatus(cid)
    if not status then return H.Fail('invalid_state', 'The citizen is not in custody.') end
    if custodyId and status.custodyId ~= custodyId then return H.Fail('conflict', 'That custody record is not the open one.') end
    local escortSrc
    if not f.custody then
        local psrc = H.SourceOfCid(cid)
        escortSrc = type(opts) == 'table' and H.Int(opts.escort, 1) or nil
        local EP = escortSrc and H.Player(escortSrc)
        if not psrc then return H.Fail('offline', 'A transfer needs the patient online.') end
        if not EP or not C.IsOfficer(EP) then return H.Fail('no_permission', 'opts.escort must be an on-duty officer.') end
        if H.Dist(H.Pos(escortSrc), H.Pos(psrc)) > cfg().EscortDistance then return H.Fail('too_far', 'The escort is not with the patient.') end
    end
    -- the custody record moves before the admission exists (undone if the admission fails)
    local juDone = false
    if status.custodyId and not f.custody and status.custodyState ~= 'hospital' then
        local r = ju('TransferCustody', status.custodyId, { kind = 'hospital', id = fid }, { actor = escortSrc and { src = escortSrc } or nil })
        if type(r) ~= 'table' or not r.ok then return H.Fail(type(r) == 'table' and r.error or 'busy', 'The custody record could not be moved.') end
        juDone = true
    end
    local plain = {}
    for k, v in pairs(spec) do if k ~= 'custodyRef' then plain[k] = v end end
    C.linking[cid] = true
    local res = baseAdmit(cid, plain, opts)
    C.linking[cid] = nil
    if type(res) ~= 'table' or not res.ok then
        if juDone then ju('ReturnCustody', status.custodyId, {}) end
        return res
    end
    local a = A.ById(res.admissionId)
    if a then
        local care = C.Upsert(cid, { kind = f.custody and 'infirmary' or 'transfer', custodyId = status.custodyId, orderId = status.orderId or orderId,
            facility = ref.facility and H.Text(ref.facility, 32) or status.facility, juTransfer = juDone or status.custodyState == 'hospital' or nil })
        if care then
            local esc = escortSrc and H.Player(escortSrc).PlayerData.citizenid or nil
            C.LinkAdmission(care, a, esc)
            care.insideSeen = H.Facility.InFacility(H.SourceOfCid(cid), fid)
            care.arriveBy = now() + (cfg().ArriveSeconds or 1800)
        end
    end
    res.custodyRef = a and a.custody_ref or nil
    return res
end

-- An admission created by any other path (a respawn of a dead prisoner, a check-in) for a citizen in
-- custody becomes a custody admission at once: custody continuity without an officer present.
function C.AutoAttach(cid, admissionId)
    if not ready or C.linking[cid] then return end
    local a = A.ById(admissionId)
    if not a then return end
    local status = C.CustodyStatus(cid)
    if not status then return end
    local f = H.Facility.Get(a.hospital_id) or {}
    local juDone = false
    if status.custodyId and not f.custody and status.custodyState ~= 'hospital' then
        local r = ju('TransferCustody', status.custodyId, { kind = 'hospital', id = a.hospital_id }, {})
        juDone = type(r) == 'table' and r.ok == true
    end
    local care = C.Upsert(cid, { kind = f.custody and 'infirmary' or 'transfer', custodyId = status.custodyId, orderId = status.orderId,
        facility = status.facility, juTransfer = juDone or status.custodyState == 'hospital' })
    if not care then return end
    local psrc = H.SourceOfCid(cid)
    local esrc = (not f.custody) and psrc and C.NearestOfficer(psrc) or nil
    C.LinkAdmission(care, a, esrc and H.Player(esrc).PlayerData.citizenid or false)
    care.insideSeen = psrc ~= nil and H.Facility.InFacility(psrc, a.hospital_id)
    care.escortAwaySince, care.escortReported = nil, nil
end

AddEventHandler('pf-ambulancejob:server:admissionChanged', function(pub, from)
    if from ~= nil or type(pub) ~= 'table' or type(pub.citizenid) ~= 'string' then return end
    local ok, err = pcall(C.AutoAttach, pub.citizenid, pub.id)
    if not ok then print('^1[pf-ambulancejob]^7 custody care attach failed: ' .. tostring(err)) end
end)

-- ── player actions ──────────────────────────────────────────────────────────────────────────

--- An officer takes a custody patient to a public hospital (the caller is the escort).
function C.StartTransfer(src, target, hospitalId)
    if H.Limited(src, 'ctransfer', 2) then return H.Fail('rate_limited', 'Slow down.') end
    local P = H.Player(src)
    if not P then return H.Fail('offline', 'You are not loaded.') end
    if not C.IsOfficer(P) then
        local job = P.PlayerData.job or {}
        if cfg().OfficerJobs[job.name] then return H.Fail('not_on_duty', 'You are off duty.') end
        return H.Fail('no_permission', 'Only an on-duty officer escorts a custody patient.')
    end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T or target == src then return H.Fail('offline', 'Patient not found.') end
    if H.Dist(H.Pos(src), H.Pos(target)) > cfg().EscortDistance then
        return H.Fail('too_far', ('Stay within %d m of the patient.'):format(math.floor(cfg().EscortDistance)))
    end
    local fid = H.Facility.Id(hospitalId)
    local f = fid and H.Facility.Get(fid)
    if not f then return H.Fail('bad_args', 'Unknown hospital.') end
    if f.custody then return H.Fail('bad_args', 'Use an infirmary visit inside the prison.') end
    local cid = T.PlayerData.citizenid
    local status = C.CustodyStatus(cid)
    if not status then return H.Fail('invalid_state', 'That person is not in custody.') end
    local cur = A.OpenOf(cid)
    return C.MoveTo(cid, status, fid, src, H.ActorOf(src, P), cur and cur.hospital_id ~= fid and cur or nil)
end

--- Another on-duty officer within EscortDistance takes over the escort.
function C.TakeEscort(src, target)
    if H.Limited(src, 'cescort', 2) then return H.Fail('rate_limited', 'Slow down.') end
    local P = H.Player(src)
    if not P or not C.IsOfficer(P) then return H.Fail('no_permission', 'Only an on-duty officer escorts a custody patient.') end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T then return H.Fail('offline', 'Patient not found.') end
    local care = C.Of(T.PlayerData.citizenid)
    local a = care and care.admission_id and A.ById(care.admission_id)
    if not a then return H.Fail('not_found', 'That patient is not in hospital custody.') end
    if H.Dist(H.Pos(src), H.Pos(target)) > cfg().EscortDistance then
        return H.Fail('too_far', ('Stay within %d m of the patient.'):format(math.floor(cfg().EscortDistance)))
    end
    local cid = P.PlayerData.citizenid
    if not C.LinkAdmission(care, a, cid) then return H.Fail('db_unavailable', 'Try again.') end
    care.escortAwaySince, care.escortReported = nil, nil
    H.Audit(care.citizenid, 'custody_escort', H.ActorOf(src, P), { care = care.id })
    return { ok = true, careId = care.id }
end

--- An inmate (or an officer / staff member bringing one) asks for the prison infirmary. The
--- patient must stand in a custody facility (server position).
function C.InfirmaryVisit(src, target)
    if H.Limited(src, 'infirmary', 5) then return H.Fail('rate_limited', 'Slow down.') end
    local P = H.Player(src)
    if not P then return H.Fail('offline', 'You are not loaded.') end
    local psrc = src
    if target ~= nil then
        psrc = H.Int(target, 1)
        if not psrc or not H.Player(psrc) then return H.Fail('offline', 'Patient not found.') end
        if psrc ~= src then
            if not C.IsOfficer(P) and not H.IsStaff(P) then return H.Fail('no_permission', 'Only staff or an officer brings an inmate.') end
            if H.Dist(H.Pos(src), H.Pos(psrc)) > Config.Hospital.Roles.TouchDistance then return H.Fail('too_far', 'Stand next to the inmate.') end
        end
    end
    local T = H.Player(psrc)
    local cid = T.PlayerData.citizenid
    local fid = H.Facility.Of(psrc)
    local f = fid and H.Facility.Get(fid)
    if not f or not f.custody then return H.Fail('too_far', 'Go to the infirmary.') end
    local status = C.CustodyStatus(cid)
    if not status or not (status.orderId or status.legacy) then return H.Fail('no_permission', 'The infirmary only takes inmates.') end
    local res, err = H.WithLock('cid:' .. cid, function()
        local cur = A.OpenOf(cid)
        if cur then
            if cur.hospital_id ~= fid then return H.Fail('conflict', ('Already admitted at %s.'):format(H.Facility.Label(cur.hospital_id))) end
            return { ok = true, duplicate = true, admissionId = cur.id }
        end
        C.linking[cid] = true
        local a, cerr = A.Create(cid, { hospitalId = fid, state = 'checked_in', reason = 'infirmary', triage = A.AutoTriage(cid),
            actor = H.ActorOf(src, P) })
        C.linking[cid] = nil
        if not a then return H.Fail(cerr or 'db_unavailable', 'The infirmary records are unavailable; try again.') end
        local care = C.Upsert(cid, { kind = 'infirmary', custodyId = status.custodyId, orderId = status.orderId, facility = status.facility })
        if care then
            C.LinkAdmission(care, a, false)
            care.insideSeen = true
        end
        A.OpenRequest(a)
        return { ok = true, admissionId = a.id }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    if res.ok and not res.duplicate then
        notifyStaff(('Inmate %s is waiting at %s.'):format(H.CharName(T), f.label))
        H.Notify(psrc, 'You are on the infirmary list. Wait for the medical staff.', 'success')
    end
    return res
end

-- ── screening ───────────────────────────────────────────────────────────────────────────────

local CONTEXTS = { booking = true, prison_intake = true, infirmary = true }
local RESULTS = { fit = true, fit_restricted = true, hospital_required = true }

--- Restriction kinds in force (no reasons).
function C.RestrictionKinds(cid)
    local R = PFMed and PFMed.Recovery
    local out, seen = {}, {}
    if R and H.Callable(R.GetRestrictions) then
        local ok, res = pcall(R.GetRestrictions, cid)
        if ok and type(res) == 'table' and res.ok then
            for _, r in ipairs(res.list or {}) do
                if type(r.kind) == 'string' and not seen[r.kind] then seen[r.kind] = true out[#out + 1] = r.kind end
            end
        end
    end
    table.sort(out)
    return out
end

local function unfitKinds(kinds)
    for _, k in ipairs(kinds) do if cfg().UnfitRestrictions[k] then return true end end
    return false
end

--- The server's own screening of a citizen from the medical engine.
--- Returns { result, fit_for_work, infirmary_needed, restrictions = { kinds } }.
function C.Evaluate(cid)
    local src = H.SourceOfCid(cid)
    local down = src and PFMed.Down and PFMed.Down.IsDown(src) or false
    local triage = A.AutoTriage(cid)
    local kinds = C.RestrictionKinds(cid)
    local result, infirmary = 'fit', false
    if down or triage == 'red' or triage == 'orange' then
        result, infirmary = 'hospital_required', true
    elseif triage == 'yellow' then
        result, infirmary = 'fit_restricted', true
    elseif #kinds > 0 then
        result = 'fit_restricted'
    end
    return { result = result, fit_for_work = result ~= 'hospital_required' and not infirmary and not unfitKinds(kinds), infirmary_needed = infirmary,
        restrictions = kinds }
end

local function screeningView(row)
    local list = type(row.restrictions) == 'string' and json.decode(row.restrictions) or row.restrictions
    return { ok = true, screeningId = tonumber(row.id), result = row.result, fit_for_work = row.fit_for_work == true or tonumber(row.fit_for_work) == 1,
        infirmary_needed = row.infirmary_needed == true or tonumber(row.infirmary_needed) == 1, restrictions = type(list) == 'table' and list or {} }
end

--- Stores a screening. spec = { context, result?, note?, restrictions?, byCid?, key?, custodyRef? }:
--- without `result` the server evaluates the citizen itself.
function C.Screen(cid, spec)
    if spec.key then
        local okF, found = pcall(Q.FindScreeningByKey, spec.key)
        if not okF then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
        if found then
            if found.citizenid ~= cid or found.context ~= spec.context then return H.Fail('key_reused', 'That key was used for another screening.') end
            local v = screeningView(found)
            v.duplicate = true
            return v
        end
    end
    local ev = C.Evaluate(cid)
    local row = { citizenid = cid, context = spec.context, custody_ref = spec.custodyRef, result = spec.result or ev.result, note = spec.note,
        by_cid = spec.byCid, at = now(), idem_key = spec.key }
    local kinds = ev.restrictions
    for _, k in ipairs(spec.restrictions or {}) do
        local dup = false
        for _, have in ipairs(kinds) do if have == k then dup = true end end
        if not dup then kinds[#kinds + 1] = k end
    end
    if spec.result then
        row.infirmary_needed = spec.result == 'hospital_required' or ev.infirmary_needed
        row.fit_for_work = spec.result ~= 'hospital_required' and not row.infirmary_needed and not unfitKinds(kinds)
            and spec.fitForWork ~= false
    else
        row.infirmary_needed, row.fit_for_work = ev.infirmary_needed, ev.fit_for_work
    end
    row.restrictions = json.encode(kinds)
    local ok, id = pcall(Q.InsertScreening, row)
    id = ok and tonumber(id) or nil
    if not id then
        if spec.key then
            local okF, found = pcall(Q.FindScreeningByKey, spec.key)
            if okF and found then local v = screeningView(found) v.duplicate = true return v end
        end
        return H.Fail('db_unavailable', 'Medical records are unavailable.')
    end
    row.id = id
    H.Audit(cid, 'screening', { kind = spec.byCid and 'player' or 'system', cid = spec.byCid, label = 'screening' },
        { id = id, context = spec.context, result = row.result })
    if row.infirmary_needed then
        local name = H.CharName(H.PlayerByCid(cid))
        notifyOfficers(('%s needs the infirmary (screening).'):format(name))
        notifyStaff(('%s needs care after a custody screening.'):format(name))
    end
    return screeningView(row)
end

--- Staff screening of a custody patient next to them: result, restriction orders (kind + hours,
--- written as real restrictions), a clinical note that never leaves the medical side.
function C.StaffScreen(src, target, result, restrictions, note)
    if H.Limited(src, 'cscreen', 2) then return H.Fail('rate_limited', 'Slow down.') end
    if not RESULTS[result] then return H.Fail('bad_args', 'Result: fit, fit_restricted or hospital_required.') end
    local P, tierOrErr, msg = H.Provider(src, nil, cfg().ScreenTier)
    if not P then return H.Fail(tierOrErr, msg) end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T or target == src then return H.Fail('offline', 'Patient not found.') end
    if H.Dist(H.Pos(src), H.Pos(target)) > Config.Hospital.Roles.TouchDistance then return H.Fail('too_far', 'Stand next to the patient.') end
    local cid = T.PlayerData.citizenid
    local status = C.CustodyStatus(cid)
    if not status then return H.Fail('invalid_state', 'That person is not in custody.') end
    local orders = {}
    if restrictions ~= nil then
        local clean, why = A.CleanOrders({ restrictions = restrictions })
        if not clean then return H.Fail('bad_args', why) end
        orders = clean.restrictions or {}
    end
    local res, err = H.WithLock('cid:' .. cid, function()
        local actor = H.ActorOf(src, P)
        if #orders > 0 then A.WriteRestrictions(cid, orders, actor.cid, actor) end
        local kinds = {}
        for _, r in ipairs(orders) do kinds[#kinds + 1] = r.kind end
        return C.Screen(cid, { context = A.OpenOf(cid) and 'infirmary' or (status.orderId and 'prison_intake' or 'booking'), result = result,
            restrictions = kinds, note = H.Text(note, 255), byCid = actor.cid, custodyRef = C.RefOf(status) })
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    if res.ok and status.custodyId then
        ju('AddCustodyLog', status.custodyId, 'medical_check', { result = result, by = P.PlayerData.citizenid }, { actor = { src = src } })
    end
    return res
end

--- Automatic intake screening when an incarceration order at a custody facility is created.
AddEventHandler('pf-justice:server:orderCreated', function(order)
    if not ready or type(order) ~= 'table' then return end
    local kinds = { jail = true, prison = true, remand = true }
    local f = order.facility and Config.Hospital.Facilities[order.facility]
    local id = H.Int(order.id, 1)
    if not kinds[order.kind] or not f or not f.custody or not id or type(order.cid) ~= 'string' then return end
    if not H.SourceOfCid(order.cid) then return end -- screened at the infirmary instead (or by staff)
    pcall(C.Screen, order.cid, { context = 'prison_intake', key = ('pf-ambulancejob:screen:intake:%d'):format(id), custodyRef = ('order:%d'):format(id) })
end)

-- ── privacy-safe status for corrections and police ──────────────────────────────────────────

--- { ok, cid, fit_for_work, restrictions = { kinds }, infirmary_needed } and nothing else.
function C.InmateStatus(cid)
    local at = now()
    local ev = C.Evaluate(cid)
    local fit, infirmary = ev.fit_for_work, ev.infirmary_needed
    local okS, scr = pcall(Q.LatestScreening, cid, at - (cfg().ScreeningValidHours or 72) * 3600)
    if okS and scr then
        if tonumber(scr.fit_for_work) == 0 then fit = false end
        if tonumber(scr.infirmary_needed) == 1 then infirmary = true end
    end
    local a = A.OpenOf(cid)
    if a then fit = false end
    local okR, rx = pcall(Q.ActiveRx, cid, at)
    if okR then
        for _, r in ipairs(rx or {}) do
            local last = tonumber(r.last_dispensed_at)
            if not last or at >= last + (tonumber(r.interval_seconds) or 0) then infirmary = true end
        end
    end
    if a then infirmary = false end -- already in care
    return { ok = true, cid = cid, fit_for_work = fit and true or false, restrictions = ev.restrictions, infirmary_needed = infirmary and true or false }
end

--- Callback for on-duty officers: the safe status of a custody patient (online, by server id).
function C.OfficerView(src, target)
    if H.Limited(src, 'inmatemed', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local P = H.Player(src)
    if not P or not C.IsOfficer(P) then return H.Fail('no_permission', 'On-duty officers only.') end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T then return H.Fail('offline', 'Person not found.') end
    local cid = T.PlayerData.citizenid
    if not C.CustodyStatus(cid) then return H.Fail('invalid_state', 'That person is not in custody.') end
    return C.InmateStatus(cid)
end

-- ── prescriptions dispensed from the infirmary stock ────────────────────────────────────────

function C.Prescribe(src, target, item, doses, intervalHours, note)
    if H.Limited(src, 'crx', 2) then return H.Fail('rate_limited', 'Slow down.') end
    local entry = type(item) == 'string' and cfg().Formulary[item]
    if not entry then return H.Fail('bad_args', 'That is not on the infirmary formulary.') end
    doses = H.Int(doses, 1, entry.maxDoses)
    if not doses then return H.Fail('bad_args', ('Doses: 1-%d.'):format(entry.maxDoses)) end
    intervalHours = H.Int(intervalHours, entry.minIntervalHours, 72)
    if not intervalHours then return H.Fail('bad_args', ('Interval: %d-72 hours.'):format(entry.minIntervalHours)) end
    local P, tierOrErr, msg = H.Provider(src, nil, cfg().PrescribeTier)
    if not P then return H.Fail(tierOrErr, msg) end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T or target == src then return H.Fail('offline', 'Patient not found.') end
    local cid = T.PlayerData.citizenid
    local a = A.OpenOf(cid)
    local near = H.Dist(H.Pos(src), H.Pos(target)) <= Config.Hospital.Roles.TouchDistance
    if not near and not (a and H.Facility.InFacility(src, a.hospital_id)) then return H.Fail('too_far', 'See the patient first.') end
    local status = C.CustodyStatus(cid)
    if not status or not (status.orderId or status.legacy) then return H.Fail('invalid_state', 'Infirmary prescriptions are for inmates.') end
    local t = now()
    local ok, id = pcall(Q.InsertRx, { citizenid = cid, drug = item, dose = entry.dose, qty = doses, controlled = entry.controlled == true,
        prescriber_cid = P.PlayerData.citizenid, created_at = t, expires_at = t + (cfg().RxValidDays or 14) * 86400,
        interval_seconds = intervalHours * 3600, custody_ref = C.RefOf(status), note = H.Text(note, 255) })
    id = ok and tonumber(id) or nil
    if not id then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
    H.Audit(cid, 'prescription', H.ActorOf(src, P), { rx = id, drug = item, qty = doses })
    H.Notify(target, ('A prescription (%s) is ready at the infirmary.'):format(entry.label), 'success')
    return { ok = true, prescriptionId = id }
end

function C.CancelPrescription(src, rxId)
    local P, tierOrErr, msg = H.Provider(src, nil, cfg().PrescribeTier)
    if not P then return H.Fail(tierOrErr, msg) end
    rxId = H.Int(rxId, 1)
    if not rxId then return H.Fail('bad_args', 'Invalid prescription.') end
    local ok, n = pcall(Q.CancelRx, rxId)
    if not ok then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
    if n ~= 1 then return H.Fail('invalid_state', 'That prescription is not active.') end
    return { ok = true }
end

local function rxView(r, at)
    local entry = cfg().Formulary[r.drug] or {}
    local last, every = tonumber(r.last_dispensed_at), tonumber(r.interval_seconds) or 0
    return { id = tonumber(r.id), item = r.drug, label = entry.label or r.drug, dose = r.dose,
        dosesLeft = math.max(0, (tonumber(r.qty) or 0) - (tonumber(r.dispensed) or 0)),
        nextAt = last and (last + every) or at, expiresAt = tonumber(r.expires_at) }
end

--- The inmate's own prescriptions, or a custody patient's for staff (tier ScreenTier, next to them).
function C.ListPrescriptions(src, target)
    local cid
    if target == nil or H.Int(target, 1) == src then
        local P = H.Player(src)
        cid = P and P.PlayerData.citizenid
    else
        local P, tierOrErr, msg = H.Provider(src, nil, cfg().ScreenTier)
        if not P then return H.Fail(tierOrErr, msg) end
        local t = H.Int(target, 1)
        local T = t and H.Player(t)
        if not T then return H.Fail('offline', 'Patient not found.') end
        if H.Dist(H.Pos(src), H.Pos(t)) > Config.Hospital.Roles.TouchDistance * 4 then return H.Fail('too_far', 'See the patient first.') end
        cid = T.PlayerData.citizenid
    end
    if not cid then return H.Fail('offline', 'You are not loaded.') end
    local at = now()
    local ok, rows = pcall(Q.ActiveRx, cid, at)
    if not ok then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = rxView(r, at) end
    return { ok = true, list = list }
end

--- The inmate takes their next due dose at the infirmary: the dose is reserved in the database
--- first (one key per dose number), then the item moves from the infirmary stash to the inmate;
--- any failure gives the dose back.
function C.Dose(src)
    if H.Limited(src, 'crxdose', 3) then return H.Fail('rate_limited', 'Slow down.') end
    local P = H.Player(src)
    if not P then return H.Fail('offline', 'You are not loaded.') end
    local fid = H.Facility.Of(src)
    local f = fid and H.Facility.Get(fid)
    local stash = fid and cfg().Stashes[fid]
    if not f or not f.custody or not stash then return H.Fail('too_far', 'Ask at the infirmary.') end
    local cid = P.PlayerData.citizenid
    local res, err = H.WithLock('rx:' .. cid, function()
        local at = now()
        local ok, rows = pcall(Q.ActiveRx, cid, at)
        if not ok then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
        if #rows == 0 then return H.Fail('not_found', 'You have no prescription.') end
        local due, wait
        for _, r in ipairs(rows) do
            local last, every = tonumber(r.last_dispensed_at), tonumber(r.interval_seconds) or 0
            if (tonumber(r.dispensed) or 0) < (tonumber(r.qty) or 0) then
                if not last or at >= last + every then due = due or r
                else wait = math.min(wait or math.huge, last + every - at) end
            end
        end
        if not due then return { ok = false, error = 'too_soon', remaining = wait, message = ('Your next dose is in %d min.'):format(math.ceil((wait or 0) / 60)) } end
        local id, dispensed, prevLast = tonumber(due.id), tonumber(due.dispensed) or 0, tonumber(due.last_dispensed_at)
        local doseNo = dispensed + 1
        local key = ('pf-ambulancejob:rx:%d:%d'):format(id, doseNo)
        local okR, n = pcall(Q.ReserveDose, id, dispensed, at)
        if not okR then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
        if n ~= 1 then return H.Fail('busy', 'Try again.') end
        local okL, logId = pcall(Q.InsertDispense, { prescription_id = id, citizenid = cid, drug = due.drug, qty = 1, by_cid = 'infirmary', stash = stash.id,
            at = at, dose_no = doseNo, idem_key = key })
        local function undo()
            pcall(Q.UndoDose, id, doseNo, prevLast)
            pcall(Q.DeleteDispense, key)
        end
        if not okL or not logId then undo() return H.Fail('db_unavailable', 'Medical records are unavailable.') end
        if inventory('RemoveItem', stash.id, due.drug, 1, nil, 'infirmary dose ' .. key) ~= true then
            undo()
            notifyStaff(('%s is out of %s.'):format(f.label, (cfg().Formulary[due.drug] or {}).label or due.drug))
            return H.Fail('conflict', 'The infirmary is out of stock; staff were told.')
        end
        if inventory('AddItem', src, due.drug, 1, nil, nil, 'infirmary dose ' .. key) ~= true then
            inventory('AddItem', stash.id, due.drug, 1, nil, nil, 'infirmary dose returned ' .. key)
            undo()
            return H.Fail('conflict', 'You cannot carry it.')
        end
        H.Audit(cid, 'dispense', SYSTEM, { rx = id, dose = doseNo, drug = due.drug })
        return { ok = true, item = due.drug, prescriptionId = id, doseNo = doseNo, dosesLeft = math.max(0, (tonumber(due.qty) or 0) - doseNo) }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

--- On-duty staff inside a custody facility open its stock stash (restocking by hand until 20C).
function C.OpenStock(src)
    local fid = H.Facility.Of(src)
    local f = fid and H.Facility.Get(fid)
    local stash = fid and cfg().Stashes[fid]
    if not f or not f.custody or not stash then return H.Fail('too_far', 'Go to the infirmary.') end
    local P, tierOrErr, msg = H.Provider(src, fid, 1)
    if not P then return H.Fail(tierOrErr, msg) end
    inventory('OpenInventory', src, stash.id, { label = stash.label, maxweight = stash.maxweight, slots = stash.slots })
    return { ok = true, stash = stash.id }
end

-- ── exports ─────────────────────────────────────────────────────────────────────────────────

local refusedLog = {}
local function allowed(name)
    local inv = GetInvokingResource()
    if inv == nil or inv == GetCurrentResourceName() then return true, nil end
    local list = cfg().Callers[name]
    if list == '*' or (type(list) == 'table' and list[inv] == true) then return true, inv end
    local t = os.time()
    if (refusedLog[inv] or 0) + 60 <= t then
        refusedLog[inv] = t
        print(('^3[pf-ambulancejob]^7 %s refused for resource %s (not in Config.Hospital.Custody.Callers)'):format(name, tostring(inv)))
    end
    return false, inv
end

local function resolve(who)
    if PFMed and PFMed.Api and PFMed.Api.Resolve then return (PFMed.Api.Resolve(who)) end
    return type(who) == 'string' and who or nil
end

--- SetCustodyCare(cid, custodyRef = { custodyId?, orderId?, facility } | nil, opts = { key? }).
function C.ExportSetCustodyCare(cid, ref, opts)
    if not allowed('SetCustodyCare') then return H.Fail('not_allowed', 'Not allowed.') end
    if not ready then return H.Fail('db_unavailable', 'Medical records are not ready.') end
    if type(cid) ~= 'string' or not PFMed.Store.ValidCitizenId(cid) then return H.Fail('bad_args', 'Invalid citizen id.') end
    opts = type(opts) == 'table' and opts or {}
    if opts.key ~= nil and not H.ValidKey(opts.key) then return H.Fail('bad_args', 'Bad idempotency key.') end
    local res, err = H.WithLock('cid:' .. cid, function()
        if ref == nil then
            local care = C.active[cid]
            if not care then return { ok = true, unchanged = true } end
            C.CloseCare(care, 'cleared', 'cleared by ' .. tostring(GetInvokingResource() or 'server'))
            return { ok = true }
        end
        if type(ref) ~= 'table' then return H.Fail('bad_args', 'custodyRef must be a table or nil.') end
        local custodyId = ref.custodyId ~= nil and H.Int(ref.custodyId, 1) or nil
        local orderId = ref.orderId ~= nil and H.Int(ref.orderId, 1) or nil
        local facility = H.Text(ref.facility, 32)
        if (ref.custodyId ~= nil and not custodyId) or (ref.orderId ~= nil and not orderId) or not (custodyId or orderId or facility) then
            return H.Fail('bad_args', 'custodyRef needs custodyId, orderId or facility.')
        end
        if opts.key then
            local okF, found = pcall(Q.FindCareByKey, opts.key)
            if not okF then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
            if found then
                if found.citizenid ~= cid then return H.Fail('key_reused', 'That key was used for another citizen.') end
                return { ok = true, duplicate = true, careId = tonumber(found.id) }
            end
        end
        local cur = C.active[cid]
        local care = C.Upsert(cid, { kind = (cur and cur.kind) or 'marked', custodyId = custodyId, orderId = orderId, facility = facility, key = opts.key })
        if not care then return H.Fail('db_unavailable', 'Medical records are unavailable.') end
        local a = A.OpenOf(cid)
        if a and care.admission_id ~= a.id then C.LinkAdmission(care, a) end
        return { ok = true, careId = care.id }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

function C.ExportGetCustodyCare(who)
    if not allowed('GetCustodyCare') then return H.Fail('not_allowed', 'Not allowed.') end
    local cid = resolve(who)
    if not cid then return H.Fail('bad_args', 'Unknown citizen.') end
    return { ok = true, care = C.Public(C.active[cid]) }
end

--- inCare:boolean, kind?, hospitalId? (memory only; cheap).
function C.ExportIsInCustodyCare(who)
    if not allowed('IsInCustodyCare') then return false end
    local cid = resolve(who)
    local care = cid and C.active[cid]
    if not care then return false end
    return true, care.kind, care.hospital_id
end

function C.ExportGetInmateMedicalStatus(who)
    if not allowed('GetInmateMedicalStatus') then return H.Fail('not_allowed', 'Not allowed.') end
    local cid = resolve(who)
    if not cid then return H.Fail('bad_args', 'Unknown citizen.') end
    return C.InmateStatus(cid)
end

--- ScreenPatient(who, context, opts = { key?, custodyRef? }): the server's own screening.
function C.ExportScreenPatient(who, context, opts)
    local okCaller, invoker = allowed('ScreenPatient')
    if not okCaller then return H.Fail('not_allowed', 'Not allowed.') end
    if not ready then return H.Fail('db_unavailable', 'Medical records are not ready.') end
    if not CONTEXTS[context] then return H.Fail('bad_args', 'context: booking, prison_intake or infirmary.') end
    opts = type(opts) == 'table' and opts or {}
    if opts.key ~= nil and not H.ValidKey(opts.key) then return H.Fail('bad_args', 'Bad idempotency key.') end
    local cid = resolve(who)
    if not cid then return H.Fail('bad_args', 'Unknown citizen.') end
    local ref = type(opts.custodyRef) == 'string' and H.Text(opts.custodyRef, 64) or nil
    local res = C.Screen(cid, { context = context, key = opts.key, custodyRef = ref or ('by:' .. tostring(invoker or 'server')):sub(1, 64) })
    if res.ok then
        -- callers get the disposition only (no clinical note)
        return { ok = true, screeningId = res.screeningId, result = res.result, fit_for_work = res.fit_for_work,
            infirmary_needed = res.infirmary_needed, restrictions = res.restrictions, duplicate = res.duplicate }
    end
    return res
end

exports('SetCustodyCare', function(cid, ref, opts) return C.ExportSetCustodyCare(cid, ref, opts) end)
exports('GetCustodyCare', function(who) return C.ExportGetCustodyCare(who) end)
exports('IsInCustodyCare', function(who) return C.ExportIsInCustodyCare(who) end)
exports('GetInmateMedicalStatus', function(who) return C.ExportGetInmateMedicalStatus(who) end)
exports('ScreenPatient', function(who, context, opts) return C.ExportScreenPatient(who, context, opts) end)

-- ── callbacks and staff commands (the device UI comes in batch 21) ──────────────────────────

local function callback(name, fn)
    PFAmbulance.GetCore().Functions.CreateCallback('pf-ambulancejob:server:' .. name, function(source, cb, ...)
        local src = tonumber(source)
        if not src or src <= 0 then return cb(H.Fail('bad_args', 'Invalid source.')) end
        if not ready then return cb(H.Fail('db_unavailable', 'Not ready yet.')) end
        local ok, res = pcall(fn, src, ...)
        if not ok then
            print(('^1[pf-ambulancejob]^7 %s failed: %s'):format(name, tostring(res)))
            res = H.Fail('db_unavailable', 'Something went wrong.')
        end
        cb(res)
    end)
end

callback('custodyTransfer', function(src, target, hospitalId) return C.StartTransfer(src, target, hospitalId) end)
callback('custodyEscort', function(src, target) return C.TakeEscort(src, target) end)
callback('infirmaryVisit', function(src, target) return C.InfirmaryVisit(src, target) end)
callback('custodyScreen', function(src, target, result, restrictions, note) return C.StaffScreen(src, target, result, restrictions, note) end)
callback('inmateMedical', function(src, target) return C.OfficerView(src, target) end)
callback('custodyPrescribe', function(src, target, item, doses, hours, note) return C.Prescribe(src, target, item, doses, hours, note) end)
callback('custodyRxCancel', function(src, rxId) return C.CancelPrescription(src, rxId) end)
callback('custodyRxList', function(src, target) return C.ListPrescriptions(src, target) end)
callback('custodyDose', function(src) return C.Dose(src) end)
callback('infirmaryStock', function(src) return C.OpenStock(src) end)

local function reply(src, res, okText)
    if res and res.ok then H.Notify(src, okText, 'success') else H.Notify(src, (res and res.message) or 'Refused.', 'error') end
end

function C.RegisterCommands()
    local QB = PFAmbulance.GetCore()
    if not QB.Commands or not QB.Commands.Add then return end
    local add = QB.Commands.Add
    add('infirmary', 'Prison: ask for the infirmary (or bring an inmate: id)', { { name = 'id', help = 'Inmate id (optional)' } }, false, function(source, args)
        reply(source, C.InfirmaryVisit(source, args[1] and tonumber(args[1]) or nil), 'On the infirmary list.')
    end)
    add('ctransfer', 'Escort a custody patient to a hospital', { { name = 'id', help = 'Player id' }, { name = 'hospital', help = 'pillbox, paleto' } }, true, function(source, args)
        reply(source, C.StartTransfer(source, args[1], tostring(args[2] or ''):lower()), 'Transfer started: stay with the patient.')
    end)
    add('cescort', 'Take over the escort of a custody patient', { { name = 'id', help = 'Player id' } }, true, function(source, args)
        reply(source, C.TakeEscort(source, args[1]), 'You are the escort now.')
    end)
    add('hscreen', 'Hospital: custody screening (fit, fit_restricted, hospital_required)', { { name = 'id', help = 'Player id' }, { name = 'result', help = 'Result' } }, true, function(source, args)
        reply(source, C.StaffScreen(source, args[1], tostring(args[2] or ''):lower()), 'Screening recorded.')
    end)
    add('hrx', 'Hospital: prescribe for an inmate', { { name = 'id', help = 'Player id' }, { name = 'item', help = 'painkillers, bandage, ifaks' },
        { name = 'doses', help = 'Doses' }, { name = 'hours', help = 'Hours between doses' } }, true, function(source, args)
        reply(source, C.Prescribe(source, args[1], tostring(args[2] or ''):lower(), args[3], args[4]), 'Prescription written.')
    end)
    add('hdose', 'Prison: take your due dose at the infirmary', {}, false, function(source)
        reply(source, C.Dose(source), 'Dose handed out.')
    end)
    add('inmatemed', 'Officer: fit for work / restrictions of a custody patient', { { name = 'id', help = 'Player id' } }, true, function(source, args)
        local res = C.OfficerView(source, args[1])
        if not res.ok then return H.Notify(source, res.message or 'Refused.', 'error') end
        H.Notify(source, ('Fit for work: %s; infirmary needed: %s; restrictions: %s'):format(res.fit_for_work and 'yes' or 'no',
            res.infirmary_needed and 'yes' or 'no', #res.restrictions > 0 and table.concat(res.restrictions, ', ') or 'none'), 'primary')
    end)
    add('infirmarystock', 'Hospital: open the infirmary stock', {}, false, function(source)
        local res = C.OpenStock(source)
        if not res.ok then H.Notify(source, res.message or 'Refused.', 'error') end
    end)
end

-- ── lifecycle ───────────────────────────────────────────────────────────────────────────────

--- Loads active care, links it to the open admissions, creates the stock stashes. Safe to call again.
function C.Start()
    local ok, rows = pcall(Q.LoadActiveCare, 1000)
    if not ok then
        print('^1[pf-ambulancejob]^7 custody care not loaded: ' .. tostring(rows))
        return false
    end
    C.active = {}
    for _, r in ipairs(rows or {}) do
        local care = rememberCare(r)
        local a = care.admission_id and A.ById(care.admission_id)
        if a then a.custody_ref, a.escort_cid = C.RefOf(care), care.escort_cid end
    end
    for _, s in pairs(cfg().Stashes or {}) do
        inventory('CreateInventory', s.id, { label = s.label, maxweight = s.maxweight, slots = s.slots })
    end
    ready = true
    return true
end

function C.Ready() return ready end

-- A custody patient who reconnects is put back: in the bed (admissions.lua does that), at the
-- facility's respawn point when the admission has no bed, or back to custody when it ended meanwhile.
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    if not ready or type(Player) ~= 'table' or type(Player.PlayerData) ~= 'table' then return end
    local care = C.active[Player.PlayerData.citizenid]
    if not care then return end
    local src = Player.PlayerData.source
    care.offlineReported = nil
    local a = care.admission_id and A.ById(care.admission_id)
    if a then
        if not a.bed_id then
            local f = H.Facility.Get(a.hospital_id)
            if f and f.respawnPoint then placeAt(src, f.respawnPoint) end
        end
        care.insideSeen = true
    elseif care.admission_id then
        C.FinishReturn(care, 'reconnect')
    end
end)

CreateThread(function()
    C.RegisterCommands()
    if PFMed and PFMed.Schema and PFMed.Schema.OnReady then
        PFMed.Schema.OnReady(function() C.Start() end)
    end
end)
