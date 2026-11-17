-- Hospital admissions: check-in, triage, admit, discharge, transfer, respawn intake (batch 17E,
-- architecture 4.5, 5.3). Rows live in pf_hosp_admissions (17C's migration v5); open admissions
-- are also kept in memory (one per citizen) so position checks and the AI never wait on SQL.
--
-- State machine (5.3): arrived -> checked_in -> triaged -> waiting -> in_treatment -> admitted ->
-- discharged, with exits transferred, left_ama (left the building without a discharge;
-- restrictions stay) and deceased. in_treatment and admitted hold a bed. Every move is one
-- conditional UPDATE (WHERE state = <the state we saw>), so two staff, the AI and the leave check
-- can never both close or move one admission; closing makes the one bill (server/hospital/billing.lua).
--
-- Who may act: the patient checks in at a reception desk (server position) while up; on-duty staff
-- triage, admit, discharge and transfer inside the facility, by medical tier (config_hospital.lua
-- Roles). The client never names a price, a bed it did not get from the server, or a result.
-- The server also sets an automatic triage colour from the medical engine at every intake and
-- writes it to the patient record (p.triage), so pf-justice booking screening sees red/orange
-- patients even when no medic is on duty; a staff triage replaces it.

PFHospital = PFHospital or {}
local H = PFHospital
H.Admissions = H.Admissions or {}
local A = H.Admissions
H.SQL = H.SQL or {}
local Q = H.SQL

local function cfg() return Config.Hospital end
local now = function() return H.Now() end

local OPEN = { arrived = true, checked_in = true, triaged = true, waiting = true, in_treatment = true, admitted = true }
local CLOSED = { discharged = true, transferred = true, left_ama = true, deceased = true }
local HOLDS_BED = { in_treatment = true, admitted = true }
A.OPEN, A.CLOSED, A.HOLDS_BED = OPEN, CLOSED, HOLDS_BED

local open = {}     -- [admissionId] = admission (row fields + memory fields)
local byCid = {}    -- [citizenid] = admissionId of the open admission
local ready = false
A.respawned = {}    -- [citizenid] = { deadAt, admissionId }: one intake, wipe and event per death

-- ── SQL (every statement in one place; the real-DB spec runs them) ───────────────────────────

local COLS = 'id, citizenid, hospital_id, state, mode, triage, dept, bed_id, reason, arrived_at, triaged_at, admitted_at, discharged_at, discharge_orders, idem_key'
local OPEN_LIST = "'arrived','checked_in','triaged','waiting','in_treatment','admitted'"

local function affected(r)
    if type(r) == 'number' then return r end
    if type(r) == 'table' then return tonumber(r.affectedRows or r.changedRows) or 0 end
    return 0
end
H.Affected = affected

function Q.InsertAdmission(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_admissions (citizenid, hospital_id, state, mode, triage, dept, bed_id, reason,
        arrived_at, triaged_at, admitted_at, idem_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { r.citizenid, r.hospital_id, r.state, r.mode, r.triage, r.dept, r.bed_id, r.reason, r.arrived_at, r.triaged_at, r.admitted_at, r.idem_key })
end

function Q.FindAdmissionByKey(key)
    return MySQL.single.await('SELECT ' .. COLS .. ' FROM pf_hosp_admissions WHERE idem_key = ? LIMIT 1', { key })
end

function Q.GetAdmission(id)
    return MySQL.single.await('SELECT ' .. COLS .. ' FROM pf_hosp_admissions WHERE id = ? LIMIT 1', { id })
end

function Q.LoadOpenAdmissions(limit)
    return MySQL.query.await('SELECT ' .. COLS .. ' FROM pf_hosp_admissions WHERE state IN (' .. OPEN_LIST .. ') ORDER BY id LIMIT ?', { limit or 1000 }) or {}
end

function Q.ListAdmissions(hospitalId, openOnly, limit)
    local where = openOnly and (' AND state IN (' .. OPEN_LIST .. ')') or ''
    return MySQL.query.await('SELECT ' .. COLS .. ' FROM pf_hosp_admissions WHERE hospital_id = ?' .. where .. ' ORDER BY id DESC LIMIT ?',
        { hospitalId, limit }) or {}
end

local MOVE_FIELDS = { 'state', 'mode', 'triage', 'dept', 'bed_id', 'triaged_at', 'admitted_at', 'discharged_at', 'discharge_orders' }
--- One conditional move: the row changes only while it is still in `fromState`. Returns rows changed.
function Q.MoveAdmission(id, fromState, row)
    -- placed by index: nil fields (no triage yet, no bed) must keep their positions
    local params, n = {}, #MOVE_FIELDS
    for i, f in ipairs(MOVE_FIELDS) do params[i] = row[f] end
    params[n + 1], params[n + 2] = id, fromState
    return affected(MySQL.update.await([[UPDATE pf_hosp_admissions SET state = ?, mode = ?, triage = ?, dept = ?, bed_id = ?,
        triaged_at = ?, admitted_at = ?, discharged_at = ?, discharge_orders = ? WHERE id = ? AND state = ?]], params))
end

function Q.InsertRestriction(r)
    return MySQL.insert.await([[INSERT INTO pf_med_restrictions (citizenid, kind, reason, injury_id, from_at, until_at, by_cid)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], { r.citizenid, r.kind, r.reason, r.injury_id, r.from_at, r.until_at, r.by_cid })
end

-- ── memory ─────────────────────────────────────────────────────────────────────────────────────

local function remember(a)
    a.id = tonumber(a.id)
    a.arrived_at, a.triaged_at, a.admitted_at = tonumber(a.arrived_at), tonumber(a.triaged_at), tonumber(a.admitted_at)
    open[a.id] = a
    byCid[a.citizenid] = a.id
    return a
end

local function forget(a)
    open[a.id] = nil
    if byCid[a.citizenid] == a.id then byCid[a.citizenid] = nil end
end

function A.OpenOf(cid)
    local id = cid and byCid[cid]
    return id and open[id] or nil
end

function A.ById(id) return open[tonumber(id) or -1] end

--- Calls fn(admission) for every open admission (a copy of the list: fn may close some).
function A.Each(fn)
    local list = {}
    for _, a in pairs(open) do list[#list + 1] = a end
    table.sort(list, function(x, y) return x.id < y.id end)
    for _, a in ipairs(list) do if open[a.id] == a then fn(a) end end
end

function A.Ready() return ready end

--- What other resources and the patient see of an admission.
function A.Public(a)
    if not a then return nil end
    local orders = a.discharge_orders
    if type(orders) == 'string' then orders = json.decode(orders) end
    return {
        id = a.id, citizenid = a.citizenid, hospitalId = a.hospital_id, hospital = H.Facility.Label(a.hospital_id),
        state = a.state, mode = a.mode, triage = a.triage, dept = a.dept, bedId = a.bed_id, reason = a.reason,
        arrivedAt = a.arrived_at, triagedAt = a.triaged_at, admittedAt = a.admitted_at, dischargedAt = tonumber(a.discharged_at),
        orders = type(orders) == 'table' and orders or nil, open = OPEN[a.state] == true,
    }
end

local function emitChanged(a, from, to)
    TriggerEvent('pf-ambulancejob:server:admissionChanged', A.Public(a), from, to)
    local src = H.SourceOfCid(a.citizenid)
    if src then TriggerClientEvent('pf-ambulancejob:client:Admission', src, A.Public(a)) end
end

-- ── patient record: triage colour (p.triage, read by GetPatientSummary) ──────────────────────

--- Writes the triage colour to the cached patient record (nil clears it).
function A.SetPatientTriage(cid, color)
    local Store = PFMed and PFMed.Store
    local p = Store and Store.Peek(cid)
    if p and p.triage ~= color then p.triage = color end
end

--- Automatic triage colour from the engine's own state (vitals, consciousness, injuries).
function A.AutoTriage(cid)
    local Store, Engine = PFMed and PFMed.Store, PFMed and PFMed.Engine
    local p = Store and Store.Peek(cid)
    if not p then return nil end
    local auto = cfg().Triage.Auto
    if p.consciousness ~= 'alert' and p.consciousness ~= 'altered' then return 'red' end
    local ok, v = pcall(Engine.Vitals, p, now())
    v = ok and type(v) == 'table' and v or {}
    if (tonumber(v.gcs) or 15) <= auto.Red.gcsMax or (tonumber(v.sbp) or 120) < auto.Red.sbpMin or (tonumber(v.spo2) or 98) < auto.Red.spo2Min then
        return 'red'
    end
    local worst = 0
    for _, inj in pairs(p.injuries or {}) do
        if inj.stage ~= 'recovered' and (tonumber(inj.severity) or 0) > worst then worst = tonumber(inj.severity) or 0 end
    end
    if p.consciousness == 'altered' or (tonumber(v.hr) or 80) > auto.Orange.hrMax or (tonumber(v.pain) or 0) >= auto.Orange.painMin
        or worst >= auto.Orange.severityMin then
        return 'orange'
    end
    if worst >= auto.YellowSeverityMin then return 'yellow' end
    if worst > 0 then return 'green' end
    return 'blue'
end

-- ── Dispatch request for a waiting patient (pf-services) ─────────────────────────────────────

local function services()
    if not H.Started('pf-services') then return nil end
    return exports['pf-services']
end

function A.OpenRequest(a)
    local svc = services()
    if not svc then return end
    local f = H.Facility.Get(a.hospital_id)
    local P = H.PlayerByCid(a.citizenid)
    pcall(function()
        svc:CreateRequest({
            kind = cfg().Request.Kind, title = ('Patient waiting: %s'):format(f and f.label or a.hospital_id),
            details = ('%s, triage %s (%s)'):format(H.CharName(P), tostring(a.triage or 'none'), tostring(a.reason or 'check-in')),
            coords = f and f.reception and f.reception.coords or (f and f.zone.center) or nil,
            ref = { type = 'hospital_admission', id = tostring(a.id) },
            from = { type = 'system', id = GetCurrentResourceName(), name = f and f.label or 'Hospital' },
            meta = { admission = a.id, hospital = a.hospital_id },
        })
    end)
end

function A.CloseRequest(a, status, reason)
    local svc = services()
    if not svc then return end
    pcall(function() svc:CloseByRef('hospital_admission', tostring(a.id), status, reason, cfg().Request.Kind) end)
end

--- Whether a medic accepted this patient's Dispatch request (pf-services keeps that across restarts).
function A.RequestAccepted(a)
    if a.accepted then return true end
    local svc = services()
    if not svc then return false end
    local ok, req = pcall(function() return svc:FindOpenByRef('hospital_admission', tostring(a.id), cfg().Request.Kind) end)
    if ok and type(req) == 'table' and req.status == 'accepted' then
        a.accepted = req.assignee or true
        return true
    end
    return false
end

local function registerRequestKind()
    local svc = services()
    if not svc then return end
    pcall(function()
        svc:RegisterRequestKind(cfg().Request.Kind, {
            label = 'Patient waiting at hospital', icon = '🏥', job = 'ambulance', payer = 'none', reward = 0,
            verify = false, expires = cfg().Request.Expires, citizen = false,
            description = 'A patient checked in at a hospital reception and needs a medic',
        })
        svc:RegisterRequestHandler(cfg().Request.Kind, {
            -- accepting it in the Dispatch app is "a medic took the patient": the AI does not take over
            onAccepted = function(req, src)
                local a = A.ById(req and req.ref and req.ref.id)
                local P = H.Player(tonumber(src))
                if a and P and H.IsStaff(P) then
                    a.accepted = P.PlayerData.citizenid
                    local ps = H.SourceOfCid(a.citizenid)
                    H.Notify(ps, ('%s is coming to see you.'):format(H.CharName(P)), 'success')
                end
            end,
            -- done from the Dispatch app only once staff triaged, admitted or discharged the patient
            canComplete = function(req)
                local a = A.ById(req and req.ref and req.ref.id)
                if not a then return true end
                if a.staffActed then return true end
                return false, 'Triage or admit the patient first'
            end,
        })
    end)
end

-- ── create / move / close ─────────────────────────────────────────────────────────────────────

--- Creates an admission (caller holds the citizen lock). spec = { hospitalId, state, reason, dept,
--- bedId, mode, triage, key }. Returns admission | nil, error.
function A.Create(cid, spec)
    local t = now()
    local row = {
        citizenid = cid, hospital_id = spec.hospitalId, state = spec.state or 'checked_in', mode = spec.mode or 'staff',
        triage = spec.triage, dept = spec.dept, bed_id = spec.bedId, reason = spec.reason, arrived_at = t,
        triaged_at = spec.triage and t or nil, admitted_at = HOLDS_BED[spec.state or ''] and t or nil, idem_key = spec.key,
    }
    local ok, id = pcall(Q.InsertAdmission, row)
    id = ok and tonumber(id) or nil
    if not id then
        if spec.bedId then H.Beds.Release(spec.hospitalId, spec.bedId, nil) end
        return nil, 'db_unavailable'
    end
    row.id = id
    local a = remember(row)
    if a.bed_id then H.Beds.Claim(a.hospital_id, a.bed_id, cid, id) end
    if a.triage then A.SetPatientTriage(cid, a.triage) end
    H.Audit(cid, 'admission', spec.actor, { id = id, hospital = a.hospital_id, state = a.state, reason = a.reason, bed = a.bed_id })
    emitChanged(a, nil, a.state)
    return a
end

--- Moves an open admission (caller holds its lock). set = fields to change. Returns admission |
--- nil, 'invalid_state' | 'db_unavailable'.
function A.Move(a, to, set, actor, detail)
    if not OPEN[a.state] then return nil, 'invalid_state' end
    if not (OPEN[to] or CLOSED[to]) or to == 'arrived' then return nil, 'invalid_state' end
    local row = {}
    for _, f in ipairs(MOVE_FIELDS) do row[f] = a[f] end
    for k, v in pairs(set or {}) do row[k] = v end
    row.state = to
    -- an open state without a bed gives the bed up; a closed row keeps the bed it had (history)
    if OPEN[to] and not HOLDS_BED[to] then row.bed_id = nil end
    if HOLDS_BED[to] and not row.admitted_at then row.admitted_at = now() end
    if type(row.discharge_orders) == 'table' then row.discharge_orders = json.encode(row.discharge_orders) end
    local ok, n = pcall(Q.MoveAdmission, a.id, a.state, row)
    if not ok then return nil, 'db_unavailable' end
    if n ~= 1 then return nil, 'invalid_state' end
    local from = a.state
    local oldBed, oldFacility = a.bed_id, a.hospital_id
    for k, v in pairs(row) do a[k] = v end
    if oldBed and (oldBed ~= a.bed_id or not HOLDS_BED[to]) then H.Beds.Release(oldFacility, oldBed, a.id) end
    if a.bed_id and HOLDS_BED[to] then H.Beds.Claim(a.hospital_id, a.bed_id, a.citizenid, a.id) end
    if a.triage then A.SetPatientTriage(a.citizenid, a.triage) end
    detail = detail or {}
    detail.id, detail.from, detail.to = a.id, from, to
    H.Audit(a.citizenid, 'move', actor, detail)
    if CLOSED[to] then forget(a) end
    emitChanged(a, from, to)
    return a
end

--- Writes discharge restrictions through the recovery module (17C AddRestriction: dedupes per kind,
--- pushes the effect profile); when it is missing or refuses (busy), the row goes into
--- pf_med_restrictions directly and the recovery module re-reads it. Returns rows written.
function A.WriteRestrictions(cid, list, byCid, actor)
    local R = PFMed and PFMed.Recovery
    local t, written, direct = now(), 0, 0
    for _, r in ipairs(list or {}) do
        local done = false
        if R and H.Callable(R.AddRestriction) then
            local ok, res = pcall(R.AddRestriction, cid, { kind = r.kind, reason = r.reason, untilAt = r.untilAt, injuryId = r.injuryId, byCid = byCid },
                { actor = actor })
            done = ok and type(res) == 'table' and res.ok == true
        end
        if not done then
            local ok = pcall(Q.InsertRestriction, { citizenid = cid, kind = r.kind, reason = r.reason, injury_id = r.injuryId,
                from_at = t, until_at = r.untilAt, by_cid = byCid })
            if ok then direct = direct + 1 end
            done = ok
        end
        if done then written = written + 1 end
    end
    if direct > 0 and R and H.Callable(R.ReloadRestrictions) then pcall(R.ReloadRestrictions, cid) end
    return written
end

--- The follow-up appointment in the patient's calendar (pf-citizen). Returns event id | nil.
function A.BookFollowUp(a, at, note)
    if not at or not H.Started('pf-citizen') then return nil end
    local label = H.Facility.Label(a.hospital_id)
    local ok, id = pcall(function()
        return exports['pf-citizen']:AddCalendarEvent('personal', a.citizenid, {
            title = ('Follow-up at %s'):format(label),
            description = note or ('Follow-up visit after your hospital stay (admission #%d). Check in at the reception.'):format(a.id),
            location = label, starts = at, ends = at + 1800, remind = 60,
        }, label)
    end)
    return ok and id or nil
end

--- Closes an open admission (caller holds its lock): to = discharged | transferred | left_ama |
--- deceased. ctx = { actor, orders = { restrictions, followUpAt, note }, reason, key }. The bed is
--- freed, discharge orders are written (restrictions + calendar), the one bill is made.
function A.Close(a, to, ctx)
    ctx = ctx or {}
    local orders = ctx.orders or {}
    local t = now()
    local stored = { restrictions = orders.restrictions, followUpAt = orders.followUpAt, note = orders.note,
        by = ctx.actor and (ctx.actor.cid or ctx.actor.label) or nil, reason = ctx.reason, key = ctx.key, mode = a.mode }
    local bed = a.bed_id
    local moved, err = A.Move(a, to, { discharged_at = t, discharge_orders = stored }, ctx.actor, { reason = ctx.reason })
    if not moved then return nil, err end
    local src = H.SourceOfCid(a.citizenid)
    if bed then H.Beds.SendLeave(src, to) end
    A.SetPatientTriage(a.citizenid, nil)
    if to == 'discharged' then
        A.WriteRestrictions(a.citizenid, orders.restrictions, ctx.actor and ctx.actor.cid, ctx.actor)
        local eventId = A.BookFollowUp(a, orders.followUpAt, orders.note)
        stored.calendarEvent = eventId
    end
    A.CloseRequest(a, a.staffActed and 'completed' or 'cancelled', to)
    if H.Billing and H.Billing.ForAdmission then H.Billing.ForAdmission(a, ctx) end
    if src then
        local msg = ({ discharged = 'You were discharged.', transferred = 'You are being transferred.', left_ama = 'You left the hospital without a discharge.',
            deceased = 'Recorded as deceased.' })[to]
        H.Notify(src, msg, to == 'left_ama' and 'error' or 'primary')
    end
    return a
end

--- Runs fn(admission) under the admission's lock, re-reading it from memory inside.
local function withAdmission(id, fn)
    id = tonumber(id)
    if not id then return H.Fail('bad_args', 'Invalid admission.') end
    local res, err = H.WithLock('adm:' .. id, function()
        local a = open[id]
        if not a then return H.Fail('not_found', 'No open admission with that number.') end
        return fn(a)
    end)
    if res == nil then return H.Fail(err or 'busy', 'The admission is busy; try again.') end
    return res
end
A.WithAdmission = withAdmission

-- ── discharge orders ──────────────────────────────────────────────────────────────────────────

--- Validates discharge orders from staff: { restrictions = { { kind, hours, reason } }, followUpAt
--- (unix) | followUpHours, note }. Returns clean orders | nil, message.
function A.CleanOrders(orders)
    if orders == nil then return {} end
    if type(orders) ~= 'table' then return nil, 'Orders must be a table.' end
    local c = cfg().Discharge
    local out, t = { restrictions = {} }, now()
    if orders.prescriptions ~= nil and (type(orders.prescriptions) ~= 'table' or next(orders.prescriptions) ~= nil) then
        return nil, 'Prescriptions are not available yet (the pharmacy arrives later).'
    end
    local list = orders.restrictions
    if list ~= nil then
        if type(list) ~= 'table' or #list > c.MaxRestrictions then return nil, ('At most %d restrictions.'):format(c.MaxRestrictions) end
        local seen = {}
        for _, r in ipairs(list) do
            if type(r) ~= 'table' or type(r.kind) ~= 'string' or not c.RestrictionKinds[r.kind] then return nil, 'Unknown restriction.' end
            local hours = H.Int(r.hours, 1, c.MaxRestrictionHours)
            if not hours then return nil, ('Restriction hours must be 1-%d.'):format(c.MaxRestrictionHours) end
            if not seen[r.kind] then
                seen[r.kind] = true
                out.restrictions[#out.restrictions + 1] = { kind = r.kind, untilAt = t + hours * 3600, reason = H.Text(r.reason, 128) or 'Discharge order' }
            end
        end
    end
    local at = orders.followUpAt
    if orders.followUpHours ~= nil then
        local h = H.Int(orders.followUpHours, 1, c.MaxFollowUpDays * 24)
        if not h then return nil, 'Follow-up hours out of range.' end
        at = t + h * 3600
    end
    if at ~= nil then
        at = H.Int(at, t + 300, t + c.MaxFollowUpDays * 86400)
        if not at then return nil, ('The follow-up must be within %d days.'):format(c.MaxFollowUpDays) end
        out.followUpAt = at
    end
    out.note = H.Text(orders.note, 255)
    return out
end

-- ── check-in (callback checkIn) ───────────────────────────────────────────────────────────────

--- Seconds until the AI may take this admission (nil when it cannot right now).
function A.AiEta(a)
    if a.mode == 'ai' then return 0 end
    if H.StaffOnDuty() >= (cfg().AI.MinStaff or 2) then return nil end
    return math.max(0, a.arrived_at + (cfg().AI.WaitSeconds or 180) - now())
end

local function notifyStaff(text)
    local ok, list = pcall(function() return PFAmbulance.GetCore().Functions.GetQBPlayers() end)
    if not ok or type(list) ~= 'table' then return end
    for _, P in pairs(list) do
        if H.IsStaff(P) then H.Notify(P.PlayerData.source, text, 'ambulance') end
    end
end

--- A patient checks in at a reception desk. Returns { ok, admissionId, mode, etaSeconds, duplicate }.
function A.CheckIn(src, hospitalId)
    if not ready then return H.Fail('db_unavailable', 'The hospital is not ready yet.') end
    if H.Limited(src, 'checkin', 2) then return H.Fail('rate_limited', 'Slow down.') end
    local P = H.Player(src)
    if not P then return H.Fail('offline', 'You are not loaded.') end
    local fid = H.Facility.Id(hospitalId)
    local f = fid and H.Facility.Get(fid)
    if not f then return H.Fail('bad_args', 'Unknown hospital.') end
    if not f.checkIn then return H.Fail('no_permission', 'This facility takes no walk-in patients.') end
    if not H.Facility.AtReception(src, fid) then return H.Fail('too_far', 'Check in at the reception desk.') end
    if PFMed.Down.IsDown(src) then return H.Fail('invalid_state', 'You need a medic: call for help.') end
    local cid = P.PlayerData.citizenid
    local res, err = H.WithLock('cid:' .. cid, function()
        local cur = A.OpenOf(cid)
        if cur then
            if cur.hospital_id ~= fid then return H.Fail('conflict', ('You are already admitted at %s.'):format(H.Facility.Label(cur.hospital_id))) end
            return { ok = true, duplicate = true, admissionId = cur.id, mode = cur.mode, etaSeconds = A.AiEta(cur) }
        end
        local a, cerr = A.Create(cid, { hospitalId = fid, state = 'checked_in', reason = 'checkin', triage = A.AutoTriage(cid),
            actor = H.ActorOf(src, P) })
        if not a then return H.Fail(cerr, 'The hospital records are unavailable; try again.') end
        a.insideSeen = true
        A.OpenRequest(a)
        if PFEmsRequests and PFEmsRequests.Close then PFEmsRequests.Close(cid, 'cancelled', 'checked_in', true) end
        notifyStaff(('Patient checked in at %s (triage %s).'):format(f.label, tostring(a.triage or 'none')))
        return { ok = true, admissionId = a.id, mode = a.mode, etaSeconds = A.AiEta(a) }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    if res.ok then
        local eta = res.etaSeconds
        H.Notify(src, eta and ('Checked in. A medic is called; the hospital AI takes over in %d s if nobody comes.'):format(eta)
            or 'Checked in. Please wait for a medic.', 'success')
    end
    return res
end

-- ── triage (callback triage) ──────────────────────────────────────────────────────────────────

function A.Triage(src, target, level)
    if H.Limited(src, 'triage', 1) then return H.Fail('rate_limited', 'Slow down.') end
    if type(level) ~= 'string' or not cfg().Triage.Levels[level] then return H.Fail('bad_args', 'Triage level: red, orange, yellow, green or blue.') end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T then return H.Fail('offline', 'Patient not found.') end
    if target == src then return H.Fail('bad_args', 'You cannot triage yourself.') end
    local fid = H.Facility.Of(src)
    if not fid then return H.Fail('too_far', 'You must be in a hospital.') end
    local roles = cfg().Roles
    local P, tierOrErr, msg = H.Provider(src, fid, roles.TriageTierED)
    if not P then return H.Fail(tierOrErr, msg) end
    if tierOrErr < roles.TriageTier and not H.Facility.InDepartment(src, fid, 'ed') then
        return H.Fail('no_permission', 'Triage outside the emergency department needs a nurse.')
    end
    if H.Dist(H.Pos(src), H.Pos(target)) > roles.TouchDistance then return H.Fail('too_far', 'Stand next to the patient.') end
    local cid = T.PlayerData.citizenid
    local actor = H.ActorOf(src, P)
    local res, err = H.WithLock('cid:' .. cid, function()
        local a = A.OpenOf(cid)
        if a and a.hospital_id ~= fid then return H.Fail('conflict', 'The patient is admitted at another hospital.') end
        if not a then
            if not H.Facility.InFacility(target, fid) then return H.Fail('too_far', 'The patient is not in the hospital.') end
            local created, cerr = A.Create(cid, { hospitalId = fid, state = 'triaged', reason = 'walkin', triage = level, actor = actor })
            if not created then return H.Fail(cerr, 'The hospital records are unavailable.') end
            created.insideSeen, created.accepted, created.staffActed = true, actor.cid, true
            return { ok = true, admissionId = created.id, triage = level }
        end
        return withAdmission(a.id, function(adm)
            local to = (adm.state == 'arrived' or adm.state == 'checked_in') and 'triaged' or adm.state
            local moved, merr = A.Move(adm, to, { triage = level, triaged_at = now() }, actor, { triage = level })
            if not moved then return H.Fail(merr, 'The admission changed; try again.') end
            adm.accepted, adm.staffActed = actor.cid, true
            A.CloseRequest(adm, 'completed', 'triaged')
            return { ok = true, admissionId = adm.id, triage = level }
        end)
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

-- ── admit to a department / bed (callback admit) ──────────────────────────────────────────────

function A.Admit(src, admissionId, dept, bedId)
    if H.Limited(src, 'admit', 1) then return H.Fail('rate_limited', 'Slow down.') end
    if type(dept) ~= 'string' or #dept > 16 then return H.Fail('bad_args', 'Choose a department.') end
    if bedId ~= nil and (type(bedId) ~= 'string' or #bedId > 32) then return H.Fail('bad_args', 'Invalid bed.') end
    return withAdmission(admissionId, function(a)
        local f = H.Facility.Get(a.hospital_id)
        local d = f.departments[dept]
        if not d then return H.Fail('bad_args', 'That department is not at this hospital.') end
        local P, tierOrErr, msg = H.Provider(src, a.hospital_id, cfg().Roles.AdmitTier)
        if not P then return H.Fail(tierOrErr, msg) end
        local psrc = H.SourceOfCid(a.citizenid)
        if not psrc then return H.Fail('offline', 'The patient is not here.') end
        if not H.Facility.InFacility(psrc, a.hospital_id) then return H.Fail('too_far', 'The patient is not in the hospital.') end
        if PFMed.Down.IsDown(psrc) then return H.Fail('invalid_state', 'Revive the patient first.') end
        local bed = bedId
        if bed then
            local _, bedDept = H.Beds.Def(a.hospital_id, bed)
            if bedDept ~= dept then return H.Fail('bad_args', 'That bed is not in this department.') end
        elseif a.bed_id and a.dept == dept then
            bed = a.bed_id
        else
            bed = H.Beds.FindFree(a.hospital_id, dept)
        end
        if not bed then return H.Fail('conflict', 'No free bed in that department.') end
        local occ = H.Beds.Occupant(a.hospital_id, bed)
        if occ and occ.admissionId ~= a.id then return H.Fail('conflict', 'That bed is taken.') end
        -- held before the database write so nobody else gets it meanwhile
        H.Beds.Claim(a.hospital_id, bed, a.citizenid, a.id)
        local to = (dept == 'ed') and 'in_treatment' or 'admitted'
        local actor = H.ActorOf(src, P)
        local moved, err = A.Move(a, to, { dept = dept, bed_id = bed, mode = 'staff' }, actor, { dept = dept, bed = bed })
        if not moved then
            if bed ~= a.bed_id then H.Beds.Release(a.hospital_id, bed, a.id) end
            return H.Fail(err, 'The admission changed; try again.')
        end
        a.accepted, a.staffActed, a.aiDoneAt = actor.cid, true, nil
        A.CloseRequest(a, 'completed', 'admitted')
        H.Beds.SendEnter(psrc, a.hospital_id, bed)
        return { ok = true, admissionId = a.id, bedId = bed, dept = dept }
    end)
end

-- ── discharge (callback discharge, export DischargePatient) ───────────────────────────────────

function A.Discharge(src, admissionId, orders)
    if H.Limited(src, 'discharge', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local clean, why = A.CleanOrders(orders)
    if not clean then return H.Fail('bad_args', why) end
    return withAdmission(admissionId, function(a)
        local P, tierOrErr, msg = H.Provider(src, a.hospital_id, cfg().Roles.DischargeTier)
        if not P then return H.Fail(tierOrErr, msg) end
        a.staffActed = true
        local done, err = A.Close(a, 'discharged', { actor = H.ActorOf(src, P), orders = clean, reason = 'staff' })
        if not done then return H.Fail(err, 'The admission changed; try again.') end
        return { ok = true, admissionId = a.id }
    end)
end

-- ── transfer (callback transfer) ──────────────────────────────────────────────────────────────

function A.Transfer(src, admissionId, to)
    if H.Limited(src, 'transfer', 2) then return H.Fail('rate_limited', 'Slow down.') end
    if type(to) ~= 'table' then return H.Fail('bad_args', 'Choose where to.') end
    local target = to.hospitalId or to.facility
    local tid = H.Facility.Id(target)
    if not tid then return H.Fail('bad_args', 'Unknown facility.') end
    local result
    local res = withAdmission(admissionId, function(a)
        if tid == a.hospital_id then return H.Fail('bad_args', 'The patient is already here.') end
        local tf = H.Facility.Get(tid)
        local P, tierOrErr, msg = H.Provider(src, a.hospital_id, cfg().Roles.TransferTier)
        if not P then return H.Fail(tierOrErr, msg) end
        if tf.custody then
            -- the prison infirmary takes only inmates (escorted custody transfers arrive in batch 19)
            local T = H.PlayerByCid(a.citizenid)
            local jailed = T and (tonumber(T.PlayerData.metadata and T.PlayerData.metadata.injail) or 0) > 0
            if not jailed then return H.Fail('no_permission', 'Only inmates go to the prison infirmary.') end
        end
        local actor = H.ActorOf(src, P)
        a.staffActed = true
        local done, err = A.Close(a, 'transferred', { actor = actor, reason = 'to ' .. tid })
        if not done then return H.Fail(err, 'The admission changed; try again.') end
        result = { cid = a.citizenid, from = a.hospital_id, actor = actor }
        return { ok = true, from = a.id }
    end)
    if not res.ok then return res end
    local created = H.WithLock('cid:' .. result.cid, function()
        return A.Create(result.cid, { hospitalId = tid, state = 'waiting', reason = 'transfer', actor = result.actor,
            triage = A.AutoTriage(result.cid) })
    end)
    if not created then return H.Fail('db_unavailable', 'The transfer was recorded, the new admission was not; admit the patient on arrival.') end
    created.transferFrom, created.arriveBy = res.from, now() + (cfg().Intake.TransferArriveSeconds or 3600)
    A.OpenRequest(created)
    return { ok = true, admissionId = created.id, from = res.from }
end

-- ── respawn (dead player -> ED bed, injuries kept) ────────────────────────────────────────────

local function wipeInventory(P, src)
    if not Config.WipeInventoryOnRespawn then return end
    pcall(function() P.ClearInventory() end)
    pcall(function() MySQL.update('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode({}), P.PlayerData.citizenid }) end)
    H.Notify(src, Lang:t('error.possessions_taken'), 'error')
end

local function respawnFacility(src, P, hint)
    local jailed = (tonumber(P.PlayerData.metadata and P.PlayerData.metadata.injail) or 0) > 0
    if jailed and cfg().Facilities[cfg().CustodyFacility] then return cfg().CustodyFacility end
    local pos = H.Pos(src)
    if cfg().RespawnAtNearest and pos then return H.Facility.Nearest(pos) end
    return H.Facility.Id(hint) or cfg().Order[1]
end

--- The respawn reset: injuries kept (only the physiology is reset and bleeding stopped) when the
--- patient would stay conscious that way, else the full heal the old respawn always gave.
local function respawnReset(src)
    local _, p = PFMed.Down.Level(src)
    if p and PFMed.Down.Viable(p, 'physiology') then return 'physiology', true end
    if not p then return 'physiology', true end
    return 'full', false
end

--- Hospital respawn of a dead player: only when the server has them dead and the respawn time
--- passed. Admits them to the facility's respawn department (ED) with their injuries kept; the
--- inventory wipe, the EMS close and the 'respawned' event happen once per death; the revive is
--- applied by the bed after RespawnReviveDelay. Returns true when the respawn started.
function A.Respawn(src, hint)
    local P = H.Player(src)
    if not P then return false end
    if PFMed.Down.Limited(src, 'respawn', 5) then return false end
    local ok, a1, b1 = PFMed.Down.CanRespawn(src)
    local err, info = (not ok) and a1 or nil, ok and a1 or b1
    if not ok then
        if err == 'too_soon' then H.Notify(src, ('You can respawn in %d seconds'):format(math.max(0, ((info or {}).canRespawnAt or 0) - now())), 'error') end
        PFMed.Down.SendState(src)
        return false
    end
    if not ready then H.Notify(src, 'The hospital is not ready yet; try again in a moment.', 'error') return false end
    local cid = P.PlayerData.citizenid
    local deadAt = tonumber(info.deadAt) or 0
    local done = A.respawned[cid]
    local first = not done or done.deadAt ~= deadAt
    local res = H.WithLock('cid:' .. cid, function()
        local a = A.OpenOf(cid)
        if not a then
            local fid = respawnFacility(src, P, hint)
            local f = H.Facility.Get(fid)
            local dept = f.respawnDept
            local bed = H.Beds.FindFree(fid, dept)
            if bed then H.Beds.Claim(fid, bed, cid, -1) end
            local created, cerr = A.Create(cid, { hospitalId = fid, state = bed and 'in_treatment' or 'waiting', dept = dept, bedId = bed,
                reason = 'respawn', key = ('pf-ambulancejob:respawn:%s:%d'):format(cid, deadAt), triage = A.AutoTriage(cid) or 'red',
                actor = { kind = 'system', label = 'respawn' } })
            if not created then
                if bed then H.Beds.Release(fid, bed, -1) end
                return nil, cerr
            end
            a = created
            A.OpenRequest(a)
        elseif first and not a.bed_id then
            -- died while admitted without a bed: give them one now
            local bed = H.Beds.FindFree(a.hospital_id, H.Facility.Get(a.hospital_id).respawnDept)
            if bed then
                withAdmission(a.id, function(adm)
                    H.Beds.Claim(adm.hospital_id, bed, cid, adm.id)
                    if not A.Move(adm, 'in_treatment', { dept = H.Facility.Get(adm.hospital_id).respawnDept, bed_id = bed }, { kind = 'system', label = 'respawn' }) then
                        H.Beds.Release(adm.hospital_id, bed, adm.id)
                    end
                    return { ok = true }
                end)
            end
        end
        a.insideSeen = false
        return a
    end)
    if not res then H.Notify(src, 'The hospital records are unavailable; try again.', 'error') return false end
    local a = res
    A.respawned[cid] = { deadAt = deadAt, admissionId = a.id }
    local reset, kept = respawnReset(src)
    local delay = tonumber(cfg().Intake.RespawnReviveDelay) or 20
    local token = PFMed.Down.IssueReviveToken(src, 'respawn', { delay = delay, send = false, reset = reset })
    PFMed.Down.MoveGrace(src, delay + 30)
    if a.bed_id then
        H.Beds.SendEnter(src, a.hospital_id, a.bed_id, { token = token, reviveIn = delay })
    else
        local f = H.Facility.Get(a.hospital_id)
        TriggerClientEvent('pf-ambulancejob:client:Bed', src, 'spawn', { hospitalId = a.hospital_id, coords = f.respawnPoint, token = token,
            reviveIn = delay, label = f.label })
    end
    if first then
        if PFEmsRequests and PFEmsRequests.Close then PFEmsRequests.Close(cid, 'cancelled', 'respawned', true) end
        wipeInventory(P, src)
        H.Audit(cid, 'respawn', { kind = 'system', label = 'respawn' }, { admission = a.id, injuriesKept = kept, deadAt = deadAt })
        TriggerEvent('pf-ambulancejob:server:respawned', src, cid, a.hospital_id)
    end
    return true
end

-- server/main.lua's RequestRespawn and RespawnAtHospital handlers call this global: the hospital
-- module owns the respawn now (beds, admission, injuries kept).
RespawnPlayer = function(src, hint) return A.Respawn(src, hint) end

-- ── exports (architecture 4.5) ────────────────────────────────────────────────────────────────

local function allowed(name)
    if PFMed and PFMed.Api and PFMed.Api.Allowed then return PFMed.Api.Allowed(name) end
    local inv = GetInvokingResource()
    return inv == nil or inv == GetCurrentResourceName(), inv
end

local function resolve(who)
    if PFMed and PFMed.Api and PFMed.Api.Resolve then
        local cid = PFMed.Api.Resolve(who)
        return cid
    end
    if type(who) == 'string' then return who end
    local P = H.Player(tonumber(who))
    return P and P.PlayerData.citizenid or nil
end

function A.ExportGetAdmission(who)
    if not allowed('GetAdmission') then return H.Fail('not_allowed', 'Not allowed.') end
    local cid = resolve(who)
    if not cid then return H.Fail('bad_args', 'Unknown patient.') end
    return { ok = true, admission = A.Public(A.OpenOf(cid)) }
end

function A.ExportListAdmissions(hospitalId, filter)
    if not allowed('ListAdmissions') then return H.Fail('not_allowed', 'Not allowed.') end
    local fid = H.Facility.Id(hospitalId)
    if not fid then return H.Fail('bad_args', 'Unknown hospital.') end
    filter = type(filter) == 'table' and filter or {}
    local limit = H.Int(filter.limit, 1, 100) or 50
    if filter.open == false then
        local ok, rows = pcall(Q.ListAdmissions, fid, false, limit)
        if not ok then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        local list = {}
        for _, r in ipairs(rows) do list[#list + 1] = A.Public(r) end
        return { ok = true, list = list }
    end
    local list = {}
    A.Each(function(a)
        if a.hospital_id == fid and (filter.state == nil or filter.state == a.state) and #list < limit then list[#list + 1] = A.Public(a) end
    end)
    return { ok = true, list = list }
end

--- inCare, admissionId: an open admission (any facility).
function A.ExportIsInCare(who)
    if not allowed('IsInCare') then return false end
    local cid = resolve(who)
    local a = cid and A.OpenOf(cid)
    if not a then return false end
    return true, a.id
end

function A.ExportGetHospitalStatus(hospitalId)
    if not allowed('GetHospitalStatus') then return H.Fail('not_allowed', 'Not allowed.') end
    return H.Facility.Status(hospitalId)
end

--- AdmitPatient(cid, spec = { hospitalId, dept, reason, custodyRef? }, opts = { key, actor }).
function A.ExportAdmitPatient(cid, spec, opts)
    local okCaller, invoker = allowed('AdmitPatient')
    if not okCaller then return H.Fail('not_allowed', 'Not allowed.') end
    if not ready then return H.Fail('db_unavailable', 'The hospital is not ready.') end
    if type(spec) ~= 'table' or type(opts) ~= 'table' or not H.ValidKey(opts.key) then return H.Fail('bad_args', 'spec and opts.key are required.') end
    if type(cid) ~= 'string' or not PFMed.Store.ValidCitizenId(cid) then return H.Fail('bad_args', 'Invalid citizen id.') end
    if spec.custodyRef ~= nil then return H.Fail('bad_args', 'Custody admissions need the custody-care schema (batch 19).') end
    local fid = H.Facility.Id(spec.hospitalId)
    local f = fid and H.Facility.Get(fid)
    if not f then return H.Fail('bad_args', 'Unknown hospital.') end
    local dept = spec.dept or f.respawnDept
    if type(dept) ~= 'string' or not f.departments[dept] then return H.Fail('bad_args', 'Unknown department.') end
    local reason = H.Text(spec.reason, 200) or ('admitted by ' .. tostring(invoker or 'server'))
    local res, err = H.WithLock('cid:' .. cid, function()
        local okFind, found = pcall(Q.FindAdmissionByKey, opts.key)
        if not okFind then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        if found then
            if found.citizenid ~= cid or found.hospital_id ~= fid or found.dept ~= dept then return H.Fail('key_reused', 'That key was used for another admission.') end
            return { ok = true, duplicate = true, admissionId = tonumber(found.id), bedId = found.bed_id }
        end
        if A.OpenOf(cid) then return H.Fail('conflict', 'The patient already has an open admission.') end
        local bed = H.Beds.FindFree(fid, dept)
        if bed then H.Beds.Claim(fid, bed, cid, -1) end
        local a, cerr = A.Create(cid, { hospitalId = fid, state = bed and (dept == 'ed' and 'in_treatment' or 'admitted') or 'waiting',
            dept = dept, bedId = bed, reason = 'admit: ' .. reason, key = opts.key, triage = A.AutoTriage(cid),
            actor = { kind = 'system', label = invoker or 'server' } })
        if not a then
            if bed then H.Beds.Release(fid, bed, -1) end
            return H.Fail(cerr, 'Hospital records are unavailable.')
        end
        a.staffActed = true
        local src = H.SourceOfCid(cid)
        if bed and src then H.Beds.SendEnter(src, fid, bed) end
        return { ok = true, admissionId = a.id, bedId = bed }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

--- DischargePatient(admissionId, opts = { actor, orders, reason, key }).
function A.ExportDischargePatient(admissionId, opts)
    local okCaller, invoker = allowed('DischargePatient')
    if not okCaller then return H.Fail('not_allowed', 'Not allowed.') end
    opts = type(opts) == 'table' and opts or {}
    if opts.key ~= nil and not H.ValidKey(opts.key) then return H.Fail('bad_args', 'Bad idempotency key.') end
    local clean, why = A.CleanOrders(opts.orders)
    if not clean then return H.Fail('bad_args', why) end
    local id = H.Int(admissionId, 1)
    if not id then return H.Fail('bad_args', 'Invalid admission.') end
    if not open[id] then
        -- already closed: a repeat with the same key is answered as a duplicate
        local okRow, row = pcall(Q.GetAdmission, id)
        if okRow and row and opts.key then
            local o = type(row.discharge_orders) == 'string' and json.decode(row.discharge_orders) or {}
            if type(o) == 'table' and o.key == opts.key then return { ok = true, duplicate = true, admissionId = id } end
        end
        return H.Fail(okRow and row and 'invalid_state' or 'not_found', 'No open admission with that number.')
    end
    local actor
    local a0 = open[id]
    if type(opts.actor) == 'table' and opts.actor.src ~= nil then
        local src = H.Int(opts.actor.src, 1)
        local P, tierOrErr, msg = H.Provider(src, a0.hospital_id, cfg().Roles.DischargeTier)
        if not P then return H.Fail(tierOrErr, msg) end
        actor = H.ActorOf(src, P)
    else
        actor = { kind = 'system', label = H.Text(opts.actor and opts.actor.label, 64) or invoker or 'server' }
    end
    return withAdmission(id, function(a)
        a.staffActed = true
        local done, err = A.Close(a, 'discharged', { actor = actor, orders = clean, reason = H.Text(opts.reason, 64) or 'export', key = opts.key })
        if not done then return H.Fail(err, 'The admission changed; try again.') end
        return { ok = true, admissionId = a.id }
    end)
end

exports('GetAdmission', function(who) return A.ExportGetAdmission(who) end)
exports('ListAdmissions', function(hospitalId, filter) return A.ExportListAdmissions(hospitalId, filter) end)
exports('IsInCare', function(who) return A.ExportIsInCare(who) end)
exports('GetHospitalStatus', function(hospitalId) return A.ExportGetHospitalStatus(hospitalId) end)
exports('AdmitPatient', function(cid, spec, opts) return A.ExportAdmitPatient(cid, spec, opts) end)
exports('DischargePatient', function(id, opts) return A.ExportDischargePatient(id, opts) end)

-- ── callbacks ─────────────────────────────────────────────────────────────────────────────────

local function callback(name, fn)
    PFAmbulance.GetCore().Functions.CreateCallback('pf-ambulancejob:server:' .. name, function(source, cb, ...)
        local src = tonumber(source)
        if not src or src <= 0 then return cb(H.Fail('bad_args', 'Invalid source.')) end
        local ok, res = pcall(fn, src, ...)
        if not ok then
            print(('^1[pf-ambulancejob]^7 %s failed: %s'):format(name, tostring(res)))
            res = H.Fail('db_unavailable', 'Something went wrong.')
        end
        cb(res)
    end)
end

callback('checkIn', function(src, hospitalId) return A.CheckIn(src, hospitalId) end)
callback('triage', function(src, target, level) return A.Triage(src, target, level) end)
callback('admit', function(src, admissionId, dept, bedId) return A.Admit(src, admissionId, dept, bedId) end)
callback('discharge', function(src, admissionId, orders) return A.Discharge(src, admissionId, orders) end)
callback('transfer', function(src, admissionId, to) return A.Transfer(src, admissionId, to) end)

-- legacy check-in from old clients: the reception check-in (isRevive) or lying down in one's bed
RegisterNetEvent('hospital:server:SendToBed', function(_, isRevive, hospitalIndex)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if isRevive == true then A.CheckIn(src, hospitalIndex) else H.Beds.RequestEnter(src) end
end)

-- ── staff commands (until the hospital workstation app, batch 21) ─────────────────────────────

local function admissionOfPlayer(id)
    local P = H.Player(H.Int(id, 1))
    return P and A.OpenOf(P.PlayerData.citizenid) or nil
end

local function reply(src, res, okText)
    if res and res.ok then H.Notify(src, okText, 'success') else H.Notify(src, (res and res.message) or 'Refused.', 'error') end
end

local function registerCommands()
    local QB = PFAmbulance.GetCore()
    if not QB.Commands or not QB.Commands.Add then return end
    QB.Commands.Add('htriage', 'Hospital: triage a patient (red, orange, yellow, green, blue)', { { name = 'id', help = 'Player id' }, { name = 'level', help = 'Colour' } }, true, function(source, args)
        reply(source, A.Triage(source, args[1], tostring(args[2] or ''):lower()), 'Triage recorded.')
    end)
    QB.Commands.Add('hadmit', 'Hospital: admit a patient to a department bed', { { name = 'id', help = 'Player id' }, { name = 'dept', help = 'ed, ward, ...' } }, true, function(source, args)
        local a = admissionOfPlayer(args[1])
        if not a then return H.Notify(source, 'That patient has no open admission.', 'error') end
        reply(source, A.Admit(source, a.id, tostring(args[2] or ''):lower()), 'Patient admitted.')
    end)
    QB.Commands.Add('hdischarge', 'Hospital: discharge a patient', { { name = 'id', help = 'Player id' }, { name = 'followup', help = 'Follow-up in hours (optional)' },
        { name = 'restrictions', help = 'kind:hours,kind:hours (optional)' } }, false, function(source, args)
        local a = admissionOfPlayer(args[1])
        if not a then return H.Notify(source, 'That patient has no open admission.', 'error') end
        local orders = { restrictions = {} }
        if args[2] and tonumber(args[2]) then orders.followUpHours = tonumber(args[2]) end
        for kind, hours in tostring(args[3] or ''):gmatch('([%w_]+):(%d+)') do orders.restrictions[#orders.restrictions + 1] = { kind = kind, hours = tonumber(hours) } end
        reply(source, A.Discharge(source, a.id, orders), 'Patient discharged.')
    end)
    QB.Commands.Add('htransfer', 'Hospital: transfer a patient', { { name = 'id', help = 'Player id' }, { name = 'to', help = 'pillbox, paleto, bolingbroke' } }, true, function(source, args)
        local a = admissionOfPlayer(args[1])
        if not a then return H.Notify(source, 'That patient has no open admission.', 'error') end
        reply(source, A.Transfer(source, a.id, { hospitalId = tostring(args[2] or ''):lower() }), 'Transfer recorded.')
    end)
    QB.Commands.Add('hstatus', 'Hospital: beds and waiting patients here', {}, false, function(source)
        local fid = H.Facility.Of(source)
        local P = H.Player(source)
        if not fid or not H.IsStaff(P) then return H.Notify(source, 'On-duty staff, inside a hospital.', 'error') end
        local s = H.Facility.Status(fid)
        local parts = {}
        for dept, b in pairs(s.beds) do parts[#parts + 1] = ('%s %d/%d free'):format(dept, b.free, b.total) end
        local waiting = 0
        A.Each(function(a) if a.hospital_id == fid and not HOLDS_BED[a.state] then waiting = waiting + 1 end end)
        H.Notify(source, ('%s: %s; %d waiting; staff on duty %d%s'):format(s.label, table.concat(parts, ', '), waiting, s.staffOnDuty, s.aiActive and ' (AI care active)' or ''), 'primary')
    end)
end

-- ── leave / offline / transfer-arrival checks (named tick for specs) ─────────────────────────

--- One pass over open admissions: left the building (left_ama), offline too long, a transfer
--- that never arrived. Also keeps the patient record's triage colour in step.
function A.Tick(at)
    at = at or now()
    local c = cfg().Intake
    A.Each(function(a)
        local src = H.SourceOfCid(a.citizenid)
        if not src then
            a.offlineSince = a.offlineSince or at
            if at - a.offlineSince >= c.OfflineGraceSeconds then
                withAdmission(a.id, function(adm) A.Close(adm, 'left_ama', { reason = 'disconnected', actor = { kind = 'system', label = 'hospital' } }) return { ok = true } end)
            end
            return
        end
        a.offlineSince = nil
        if a.triage then A.SetPatientTriage(a.citizenid, a.triage) end
        if H.Facility.InFacility(src, a.hospital_id) then
            a.insideSeen, a.outsideSince = true, nil
            return
        end
        if a.insideSeen then
            a.outsideSince = a.outsideSince or at
            if at - a.outsideSince >= c.LeaveGraceSeconds then
                withAdmission(a.id, function(adm) A.Close(adm, 'left_ama', { reason = 'left_building', actor = { kind = 'system', label = 'hospital' } }) return { ok = true } end)
            end
        elseif a.arriveBy and at >= a.arriveBy then
            withAdmission(a.id, function(adm) A.Close(adm, 'left_ama', { reason = 'never_arrived', actor = { kind = 'system', label = 'hospital' } }) return { ok = true } end)
        end
    end)
end

-- ── lifecycle ─────────────────────────────────────────────────────────────────────────────────

--- Loads open admissions, rebuilds bed occupancy, registers the Dispatch kind. Safe to call again.
function A.Start()
    local ok, rows = pcall(Q.LoadOpenAdmissions, 1000)
    if not ok then
        print('^1[pf-ambulancejob]^7 hospital admissions not loaded: ' .. tostring(rows))
        return false
    end
    open, byCid = {}, {}
    for _, r in ipairs(rows or {}) do remember(r) end
    local list = {}
    for _, a in pairs(open) do list[#list + 1] = a end
    H.Beds.Rebuild(list)
    ready = true
    registerRequestKind()
    return true
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    if type(Player) ~= 'table' or type(Player.PlayerData) ~= 'table' then return end
    local a = A.OpenOf(Player.PlayerData.citizenid)
    if not a then return end
    local src = Player.PlayerData.source
    a.offlineSince = nil
    if a.triage then A.SetPatientTriage(a.citizenid, a.triage) end
    if a.bed_id then H.Beds.SendEnter(src, a.hospital_id, a.bed_id) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then H.ForgetSource(src) end
end)

AddEventHandler('onResourceStart', function(res)
    if res == 'pf-services' and ready then registerRequestKind() end
end)

CreateThread(function()
    registerCommands()
    if PFMed and PFMed.Schema and PFMed.Schema.OnReady then
        PFMed.Schema.OnReady(function() A.Start() end)
    end
    while true do
        Wait((cfg().Intake.TickSeconds or 15) * 1000)
        if ready then
            local ok, err = pcall(A.Tick, now())
            if not ok then print('^1[pf-ambulancejob]^7 hospital tick failed: ' .. tostring(err)) end
        end
    end
end)
