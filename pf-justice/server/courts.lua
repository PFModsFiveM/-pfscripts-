-- pf-justice courts (PF_ARCHITECTURE 4.7.7, state machine 5.9; unit 19A).
--
--   cases        FileCase from the police MDT (court submission) or pf-justice itself (community-service
--                and supervision violations); the defendant gets a notice and, with Config.Courts.
--                AutoArraignment, an arraignment hearing at once (soon when in custody).
--   hearings     ScheduleHearing by a clerk or judge; every party gets a pf-citizen mail and calendar entry.
--   decisions    RecordDecision by an on-duty judge: plea, verdict, sentence (orders through the 15B
--                CreateOrder API, keyed per decision, court fines to society:doj), dismissal, bail
--                (offer through 15C bail, own recognizance, or remand), release order, appeal.
--   court orders IssueCourtOrder / IssueReleaseOrder / RevokeCourtOrder by a judge; IsCourtOrderValid
--                answers the batch-17/18 callers (medical records, telemetry, evidence disposal, search,
--                property): valid only for an issued, unrevoked, unexpired order of that purpose and person.
--   low population  Courts.AutoTick: with no judge on duty for Config.Courts.AutoAfterSeconds, an arraignment
--                or bail hearing that is that much overdue falls back to the published schedule: a not-guilty
--                plea and bail by charge class (decided_by 'schedule'). Nothing punitive is ever automatic:
--                trials, sentences and warrants wait for a person.
--
-- Court roles (Config.Courts.Roles, on duty): judge, clerk, prosecutor, defender; admins act as every
-- role; pf-justice itself (system actor) as the court. Every write is audited (pf_justice_audit) and raises
-- the server-only event pf-justice:server:caseChanged(case, change).

PFJustice = PFJustice or {}
PFJustice.Courts = PFJustice.Courts or {}
local J = PFJustice
local Courts = J.Courts
local U = J.Util
local Err = J.Result.Err

local function CC() return (Config and Config.Courts) or {} end
local function C(key, default)
    local v = CC()[key]
    if v == nil then return default end
    return v
end
Courts.C = C

Courts.SQL = {
    caseByKey = 'SELECT * FROM pf_justice_cases WHERE idem_key = ? LIMIT 1',
    caseById = 'SELECT * FROM pf_justice_cases WHERE id = ? LIMIT 1',
    insertCase = [[INSERT INTO pf_justice_cases (case_no, citizenid, state, kind, charges, custody_id, mdt_case_id, prosecutor_cid,
        filed_by, filed_at, idem_key) VALUES (?, ?, 'filed', ?, ?, ?, ?, ?, ?, ?, ?)]],
    setCaseNo = 'UPDATE pf_justice_cases SET case_no = ? WHERE id = ?',
    caseState = 'UPDATE pf_justice_cases SET state = ?, closed_at = ? WHERE id = ? AND state = ?',
    caseJudge = 'UPDATE pf_justice_cases SET judge_cid = COALESCE(judge_cid, ?) WHERE id = ?',
    caseDefender = 'UPDATE pf_justice_cases SET defender_cid = ? WHERE id = ?',
    insertRef = 'INSERT IGNORE INTO pf_justice_case_refs (case_id, ref_type, ref_id) VALUES (?, ?, ?)',
    refsOf = 'SELECT ref_type, ref_id FROM pf_justice_case_refs WHERE case_id = ? ORDER BY id LIMIT 200',
    hearingByKey = 'SELECT * FROM pf_justice_hearings WHERE idem_key = ? LIMIT 1',
    hearingById = 'SELECT * FROM pf_justice_hearings WHERE id = ? LIMIT 1',
    insertHearing = [[INSERT INTO pf_justice_hearings (case_id, kind, courtroom, at, judge_cid, state, notes, idem_key)
        VALUES (?, ?, ?, ?, ?, 'scheduled', ?, ?)]],
    cancelHearings = "UPDATE pf_justice_hearings SET state = 'cancelled' WHERE case_id = ? AND kind = ? AND state = 'scheduled' AND id <> ?",
    hearingState = "UPDATE pf_justice_hearings SET state = ? WHERE id = ? AND state = 'scheduled'",
    scheduledOf = "SELECT * FROM pf_justice_hearings WHERE case_id = ? AND kind = ? AND state = 'scheduled' ORDER BY at ASC LIMIT 1",
    hearingsOf = 'SELECT * FROM pf_justice_hearings WHERE case_id = ? ORDER BY at ASC LIMIT 100',
    dueAuto = [[SELECT h.* FROM pf_justice_hearings h WHERE h.state = 'scheduled' AND h.kind IN ('arraignment', 'bail')
        AND h.at <= ? ORDER BY h.at ASC LIMIT 25]],
    docket = [[SELECT h.id, h.case_id, h.kind, h.courtroom, h.at, h.judge_cid, h.state, c.case_no, c.citizenid, c.kind AS case_kind
        FROM pf_justice_hearings h JOIN pf_justice_cases c ON c.id = h.case_id
        WHERE h.state = ? AND h.at >= ? AND h.at <= ? ORDER BY h.at ASC LIMIT ?]],
    decisionByKey = 'SELECT * FROM pf_justice_decisions WHERE idem_key = ? LIMIT 1',
    insertDecision = [[INSERT INTO pf_justice_decisions (case_id, hearing_id, kind, body, decided_by, at, idem_key)
        VALUES (?, ?, ?, ?, ?, ?, ?)]],
    decisionOrders = 'UPDATE pf_justice_decisions SET order_ids = ? WHERE id = ?',
    decisionsOf = 'SELECT * FROM pf_justice_decisions WHERE case_id = ? ORDER BY id ASC LIMIT 100',
    ordersOfDecision = "SELECT id, kind, state FROM pf_justice_orders WHERE source_type = 'court_decision' AND source_id = ?",
    courtOrderByKey = 'SELECT * FROM pf_justice_court_orders WHERE idem_key = ? LIMIT 1',
    courtOrderByRef = 'SELECT * FROM pf_justice_court_orders WHERE ref = ? LIMIT 1',
    insertCourtOrder = [[INSERT INTO pf_justice_court_orders (ref, kind, citizenid, case_id, body, judge_cid, valid_until, at, idem_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    setCourtOrderRef = 'UPDATE pf_justice_court_orders SET ref = ? WHERE id = ?',
    revokeCourtOrder = 'UPDATE pf_justice_court_orders SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL',
    anonCases = 'UPDATE pf_justice_cases SET citizenid = ? WHERE citizenid = ?',
    anonCourtOrders = 'UPDATE pf_justice_court_orders SET citizenid = ? WHERE citizenid = ?',
}
local SQL = Courts.SQL

-- ── database helpers ──────────────────────────────────────────────────────────────────────────

local function one(sql, params)
    local ok, row = pcall(MySQL.single.await, sql, params or {})
    if not ok then return nil, false end
    if type(row) == 'table' and row[1] and row.id == nil then row = row[1] end
    if type(row) ~= 'table' or next(row) == nil then return nil, true end
    return row, true
end
local function many(sql, params)
    local ok, rows = pcall(MySQL.query.await, sql, params or {})
    if not ok or type(rows) ~= 'table' then return nil end
    return rows
end
local function update(sql, params)
    local ok, res = pcall(MySQL.update.await, sql, params or {})
    if not ok then return nil end
    return U.Affected(res)
end
local function insert(sql, params)
    local ok, id = pcall(MySQL.insert.await, sql, params or {})
    id = ok and tonumber(id) or nil
    if id and id > 0 then return id end
    return nil
end
Courts.One, Courts.Many, Courts.Update, Courts.Insert = one, many, update, insert

--- Whether the courts tables (schema v3) are applied.
function Courts.Ready()
    if not J.Ready() then return false end
    local S = J.Schema
    if S and U.Callable(S.Has) then return S.Has(3) == true end
    return true
end
local function notReady() return Err('db_unavailable', 'The court database is not ready') end

-- ── roles (architecture 6.5) ──────────────────────────────────────────────────────────────────

local function gradeMatches(rule, grade)
    if rule == 'any' or rule == true then return true end
    if type(rule) == 'number' then return grade >= rule end
    if type(rule) == 'table' then
        for _, g in ipairs(rule) do if tonumber(g) == grade then return true end end
    end
    return false
end

--- Whether a resolved actor holds a court role. System (pf-justice itself) and admins hold every role;
--- a player needs the job and grade of Config.Courts.Roles[role] and must be on duty.
function Courts.HasRole(actor, role)
    if type(actor) ~= 'table' then return false end
    if actor.kind == 'system' or actor.kind == 'admin' then return true end
    if actor.kind ~= 'player' or not actor.onduty then return false end
    local rules = (C('Roles', {}) or {})[role]
    if type(rules) ~= 'table' then return false end
    local rule = rules[actor.job or '']
    if rule == nil then return false end
    return gradeMatches(rule, tonumber(actor.grade) or 0)
end

--- The roles' refusal: not_on_duty when the job would qualify on duty.
local function roleErr(actor, roles)
    if type(actor) == 'table' and actor.kind == 'player' and not actor.onduty then
        local onduty = {}
        for k, v in pairs(actor) do onduty[k] = v end
        onduty.onduty = true
        for _, r in ipairs(roles) do
            if Courts.HasRole(onduty, r) then return Err('not_on_duty', 'You are off duty') end
        end
    end
    return Err('no_permission', 'Needs the court role: ' .. table.concat(roles, ' or '))
end

local function anyRole(actor, roles)
    for _, r in ipairs(roles) do if Courts.HasRole(actor, r) then return true end end
    return false
end
Courts.AnyRole = anyRole
Courts.RoleErr = roleErr

-- Last time an on-duty judge was seen (memory; boot counts as seen, so a restart never decides at once).
Courts.lastJudgeAt = Courts.lastJudgeAt or os.time()

--- Online, on-duty judges (server ids).
function Courts.JudgesOnDuty()
    local out = {}
    local ok, players = pcall(function() return J.QBCore and J.QBCore.Functions.GetQBPlayers() end)
    if not ok or type(players) ~= 'table' then return out end
    for src, P in pairs(players) do
        local pd = type(P) == 'table' and P.PlayerData
        local job = pd and pd.job
        if type(job) == 'table' and job.onduty then
            local actor = { kind = 'player', job = job.name, onduty = true,
                grade = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade) or 0 }
            if Courts.HasRole(actor, 'judge') then out[#out + 1] = tonumber(pd.source) or tonumber(src) end
        end
    end
    return out
end

-- ── notices (pf-citizen mail and calendar) ────────────────────────────────────────────────────

local function started(res) return GetResourceState(res) == 'started' end

--- Mails a citizen (works offline). ref deduplicates (pf-citizen refuses a second mail with one ref).
function Courts.Mail(cid, subject, message, ref)
    if not U.ValidCid(cid) or not started('pf-citizen') then return false end
    local ok, id = pcall(function()
        return exports['pf-citizen']:SendMail(cid, { sender = C('MailSender', 'San Andreas Superior Court'), senderType = 'government',
            subject = subject, message = message, ref = ref })
    end)
    return ok and id ~= nil
end

--- A personal calendar entry for a hearing date.
function Courts.Calendar(cid, title, description, location, at)
    if not U.ValidCid(cid) or not started('pf-citizen') then return false end
    local ok, id = pcall(function()
        return exports['pf-citizen']:AddCalendarEvent('personal', cid, { title = title, description = description, location = location,
            starts = at, ends = at + 3600, remind = 60 }, C('MailSender', 'San Andreas Superior Court'))
    end)
    return ok and id ~= nil
end

local function fmtTime(at) return os.date('%Y-%m-%d %H:%M', at) end

-- ── public shapes ─────────────────────────────────────────────────────────────────────────────

function Courts.PublicCase(r)
    if not r then return nil end
    return {
        id = tonumber(r.id), caseNo = r.case_no, cid = r.citizenid, state = r.state, kind = r.kind, charges = U.Decode(r.charges),
        custodyId = tonumber(r.custody_id), mdtCaseId = tonumber(r.mdt_case_id), prosecutorCid = r.prosecutor_cid,
        defenderCid = r.defender_cid, judgeCid = r.judge_cid, filedBy = r.filed_by, filedAt = tonumber(r.filed_at),
        closedAt = tonumber(r.closed_at),
    }
end

function Courts.PublicHearing(h)
    if not h then return nil end
    return { id = tonumber(h.id), caseId = tonumber(h.case_id), kind = h.kind, courtroom = h.courtroom, at = tonumber(h.at),
        judgeCid = h.judge_cid, state = h.state, notes = h.notes }
end

function Courts.CaseRow(id) return (one(SQL.caseById, { id })) end

local function changed(row, change)
    J.Emit('caseChanged', Courts.PublicCase(row), change)
end

local CASE_TERMINAL = { dismissed = true, acquitted = true, closed = true }
Courts.CASE_TERMINAL = CASE_TERMINAL

--- Moves a case (compare-and-set on the state it was read in). Returns the fresh row or nil.
local function moveCase(row, to)
    local closedAt = CASE_TERMINAL[to] and os.time() or nil
    if update(SQL.caseState, { to, closedAt, row.id, row.state }) ~= 1 then return nil end
    return Courts.CaseRow(row.id)
end

-- ── validation ────────────────────────────────────────────────────────────────────────────────

local CASE_KINDS = { criminal = true, violation = true, citation_contest = true, appeal = true }

local function cleanCharges(list, required)
    if list == nil then
        if required then return nil end
        return {}
    end
    if type(list) ~= 'table' or #list > 50 then return nil end
    if required and #list == 0 then return nil end
    local out = {}
    for i, c in ipairs(list) do
        if type(c) ~= 'table' then return nil end
        local code = U.Str(c.code, 24)
        local label = U.Str(c.label or c.name, 100)
        if not code and not label then return nil end
        out[i] = { code = code, label = label, count = U.Int(c.count or 1, 1, 99) or 1, class = U.Str(c.class, 16) }
    end
    return out
end

local function cleanRefList(list, max)
    if list == nil then return {} end
    if type(list) ~= 'table' or #list > max then return nil end
    local out = {}
    for _, v in ipairs(list) do
        local s = U.Str(v, 64)
        if not s or not s:match('^[%w%-_:%.]+$') then return nil end
        out[#out + 1] = s
    end
    return out
end

local function caseNo(kind, id)
    local prefix = (C('CaseNoPrefix', {}) or {})[kind] or 'CR'
    return ('%s%s-%05d'):format(prefix, os.date('%y', os.time()), id)
end

-- ── FileCase ──────────────────────────────────────────────────────────────────────────────────

--- FileCase(spec, opts). spec = { cid, charges, kind?, custodyId?, incidentIds?, evidenceIds?, prosecutorCid?,
--- mdtCaseId?, mdtCaseNo?, orderId?, title?, note?, filedBy? }; opts = { key, actor, filedBy }.
--- Returns { ok, caseId, caseNo, duplicate? }. The same key is the same case.
function Courts.FileCase(spec, opts, ctx)
    if not Courts.Ready() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    if type(spec) ~= 'table' then return Err('bad_args', 'spec must be a table') end
    if not U.ValidCid(spec.cid) then return Err('bad_args', 'cid is missing or invalid') end
    local kind = spec.kind or 'criminal'
    if not CASE_KINDS[kind] then return Err('bad_args', 'unknown case kind') end
    local charges = cleanCharges(spec.charges, kind == 'criminal')
    if not charges then return Err('bad_args', kind == 'criminal' and '1..50 charges are required' or 'charges are invalid') end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    if key == nil and not internal then return Err('bad_args', 'opts.key is required') end
    local custodyId
    if spec.custodyId ~= nil then
        custodyId = U.Int(spec.custodyId, 1, 2147483647)
        if not custodyId then return Err('bad_args', 'custodyId is invalid') end
    end
    local incidents = cleanRefList(spec.incidentIds, 50)
    local evidence = cleanRefList(spec.evidenceIds, 100)
    if not incidents or not evidence then return Err('bad_args', 'incidentIds / evidenceIds are invalid') end
    local prosecutor
    if spec.prosecutorCid ~= nil and spec.prosecutorCid ~= '' then
        if not U.ValidCid(spec.prosecutorCid) then return Err('bad_args', 'prosecutorCid is invalid') end
        prosecutor = spec.prosecutorCid
    end
    local mdtCaseId = spec.mdtCaseId ~= nil and U.Int(spec.mdtCaseId, 1, 2147483647) or nil
    local orderId = spec.orderId ~= nil and U.Int(spec.orderId, 1, 2147483647) or nil
    if spec.orderId ~= nil and not orderId then return Err('bad_args', 'orderId is invalid') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    -- the MDT files as a system process (its own gate checked the officer); a player files as prosecutor or clerk
    if actor.kind == 'player' and not anyRole(actor, { 'prosecutor', 'clerk', 'judge' }) then
        return roleErr(actor, { 'prosecutor', 'clerk' })
    end
    local filedBy = U.Str(opts.filedBy or spec.filedBy, 64)
    if filedBy and not U.ValidCid(filedBy) then filedBy = nil end
    filedBy = filedBy or J.Actor.Tag(actor) or 'system'
    local title, note = U.Str(spec.title, 120), U.Str(spec.note, 1000)

    local function duplicate(row)
        if row.citizenid ~= spec.cid or row.kind ~= kind then return Err('key_reused', 'This key was used for a different case') end
        return { ok = true, duplicate = true, caseId = tonumber(row.id), caseNo = row.case_no, state = row.state }
    end

    return J.Locks.With('casefile:' .. (key or spec.cid), function()
        if key then
            local row, okq = one(SQL.caseByKey, { key })
            if not okq then return Err('db_unavailable', 'The court database did not answer') end
            if row then return duplicate(row) end
        end
        local now = os.time()
        -- a unique placeholder, replaced by the number made from the id right after the insert
        local tmp = ('T%d%06d'):format(now % 10000000000, math.random(0, 999999))
        local id = insert(SQL.insertCase, { tmp, spec.cid, kind, U.Encode(charges), custodyId, mdtCaseId, prosecutor, filedBy, now, key })
        if not id then
            if key then
                local row = one(SQL.caseByKey, { key })
                if row then return duplicate(row) end
            end
            return Err('db_unavailable', 'The case could not be stored; nothing was filed')
        end
        local no = caseNo(kind, id)
        update(SQL.setCaseNo, { no, id })
        for _, v in ipairs(incidents) do insert(SQL.insertRef, { id, 'incident', v }) end
        for _, v in ipairs(evidence) do insert(SQL.insertRef, { id, 'evidence', v }) end
        if custodyId then insert(SQL.insertRef, { id, 'custody', tostring(custodyId) }) end
        if mdtCaseId then insert(SQL.insertRef, { id, 'mdt_case', tostring(mdtCaseId) }) end
        if orderId then insert(SQL.insertRef, { id, 'order', tostring(orderId) }) end
        J.Audit.Write('case', id, 'filed', { caseNo = no, kind = kind, charges = #charges, key = key, title = title,
            mdtCaseNo = U.Str(spec.mdtCaseNo, 24), note = note }, actor)
        local row = Courts.CaseRow(id) or { id = id, case_no = no, citizenid = spec.cid, state = 'filed', kind = kind, filed_at = now }
        changed(row, { action = 'filed' })
        Courts.Mail(spec.cid, ('Court case %s filed'):format(no),
            ('A %s case (%s) was filed against you with the San Andreas Superior Court. You will be told the date of your first hearing.')
                :format(kind:gsub('_', ' '), no), ('pf-justice:case:%d:filed'):format(id))
        local res = { ok = true, caseId = id, caseNo = no, state = 'filed' }
        if C('AutoArraignment', true) and kind ~= 'appeal' then
            local inCustody = custodyId ~= nil or Courts.OpenCustody(spec.cid) ~= nil
            local delay = inCustody and C('ArraignmentInCustodySeconds', 1800) or C('ArraignmentAtLargeSeconds', 2 * 86400)
            local hk = kind == 'violation' and 'violation' or 'arraignment'
            local h = Courts.ScheduleLocked(row, { kind = hk, at = now + delay }, { kind = 'system', label = 'court clerk', resource = J.RESOURCE },
                ('pf-justice:case:%d:auto_%s'):format(id, hk))
            if h and h.ok then res.hearingId = h.hearingId res.state = h.state end
        end
        return res
    end)
end

-- ── custody helpers ───────────────────────────────────────────────────────────────────────────

--- The citizen's open custody (public shape) or nil.
function Courts.OpenCustody(cid)
    local Cu = J.Custody
    if type(Cu) ~= 'table' or not U.Callable(Cu.Get) then return nil end
    local ok, res = pcall(Cu.Get, cid)
    local c = ok and type(res) == 'table' and res.custody or nil
    if c and not c.closedAt then return c end
    return nil
end

--- Open remand orders of the citizen.
function Courts.OpenRemands(cid)
    local out = {}
    local rows = J.Orders and J.Orders.OpenIncarceration(cid) or {}
    for _, r in ipairs(rows or {}) do if r.kind == 'remand' then out[#out + 1] = r end end
    return out
end

local function vacateRemands(cid, why, actorSpec)
    local n = 0
    for _, r in ipairs(Courts.OpenRemands(cid)) do
        local res = J.API.SetOrderState(r.id, 'vacated', { reason = why, actor = actorSpec })
        if type(res) == 'table' and res.ok then n = n + 1 end
    end
    return n
end

local function releaseCustody(custodyId, actorSpec, note)
    if not custodyId or not (J.Custody and U.Callable(J.Custody.Release)) then return false end
    local res = J.Custody.Release(custodyId, 'court_order', { actor = actorSpec, note = note })
    return type(res) == 'table' and res.ok == true
end

-- ── hearings ──────────────────────────────────────────────────────────────────────────────────

local HEARING_KINDS = { arraignment = true, bail = true, trial = true, sentencing = true, violation = true, appeal = true }
-- per hearing kind: the case states it may be scheduled in and the state it moves the case to (nil = unchanged)
local HEARING_FROM = {
    arraignment = { from = { filed = true, arraignment_scheduled = true }, to = 'arraignment_scheduled' },
    trial = { from = { plea_not_guilty = true, trial_scheduled = true }, to = 'trial_scheduled' },
    sentencing = { from = { plea_guilty = true, guilty = true, sentencing_scheduled = true }, to = 'sentencing_scheduled' },
    violation = { from = { filed = true, hearing_scheduled = true }, to = 'hearing_scheduled' },
    bail = { from = { filed = true, arraignment_scheduled = true, arraigned = true, plea_not_guilty = true, trial_scheduled = true,
        plea_guilty = true, guilty = true, sentencing_scheduled = true, hearing_scheduled = true } },
    appeal = { from = { appeal_pending = true } },
}

local function courtroomOf(id)
    local list = C('Courtrooms', {}) or {}
    if id == nil then id = C('DefaultCourtroom', nil) end
    for _, r in ipairs(list) do if r.id == id then return r end end
    if id == nil and list[1] then return list[1] end
    return nil
end

--- Schedules with the case lock held. row = the case; spec = { kind, at, courtroom?, judgeCid?, notes? }.
function Courts.ScheduleLocked(row, spec, actor, key)
    local rule = HEARING_FROM[spec.kind]
    if not rule then return Err('bad_args', 'unknown hearing kind') end
    if (spec.kind == 'violation') ~= (row.kind == 'violation') and spec.kind ~= 'bail' and spec.kind ~= 'appeal' then
        return Err('bad_args', spec.kind == 'violation' and 'Only violation cases have violation hearings' or 'A violation case has a violation hearing')
    end
    if not rule.from[row.state] then return Err('invalid_state', ('A %s case cannot get a %s hearing'):format(row.state, spec.kind)) end
    local room = courtroomOf(spec.courtroom)
    if spec.courtroom ~= nil and not room then return Err('bad_args', 'unknown courtroom') end
    local id = insert(SQL.insertHearing, { row.id, spec.kind, room and room.id or nil, spec.at, spec.judgeCid, spec.notes, key })
    if not id then
        if key then
            local h = one(SQL.hearingByKey, { key })
            if h then return { ok = true, duplicate = true, hearingId = tonumber(h.id), state = row.state } end
        end
        return Err('db_unavailable', 'The hearing could not be stored')
    end
    update(SQL.cancelHearings, { row.id, spec.kind, id })
    local state = row.state
    if rule.to and rule.to ~= row.state then
        local new = moveCase(row, rule.to)
        if not new then
            update(SQL.hearingState, { 'cancelled', id })
            return Err('busy', 'The case changed meanwhile; try again')
        end
        row, state = new, new.state
    end
    J.Audit.Write('case', row.id, 'hearing', { hearingId = id, kind = spec.kind, at = spec.at, courtroom = room and room.id }, actor)
    changed(row, { action = 'hearing', hearingId = id, kind = spec.kind, at = spec.at })
    local where = room and room.label or 'Superior Court'
    local title = ('%s hearing, case %s'):format(spec.kind:gsub('^%l', string.upper), row.case_no)
    local text = ('Your %s hearing for case %s is set for %s in %s.'):format(spec.kind, row.case_no, fmtTime(spec.at), where)
    for _, cid in ipairs({ row.citizenid, row.prosecutor_cid, row.defender_cid, spec.judgeCid or row.judge_cid }) do
        if U.ValidCid(cid) then
            Courts.Mail(cid, title, text, ('pf-justice:hearing:%d:%s'):format(id, cid))
            Courts.Calendar(cid, title, text, where, spec.at)
        end
    end
    return { ok = true, hearingId = id, at = spec.at, state = state }
end

--- ScheduleHearing(caseId, spec, opts): a clerk or judge. Rescheduling replaces the scheduled hearing of that kind.
function Courts.ScheduleHearing(caseId, spec, opts, ctx)
    if not Courts.Ready() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local id = U.Int(caseId, 1, 2147483647)
    if not id or type(spec) ~= 'table' or not HEARING_KINDS[spec.kind] then return Err('bad_args', 'caseId and spec.kind are required') end
    local now = os.time()
    local at = U.Int(spec.at, now - 60, now + C('MaxHearingDaysAhead', 60) * 86400)
    if not at then return Err('bad_args', 'at must be a unix time from now to MaxHearingDaysAhead days ahead') end
    local judgeCid
    if spec.judgeCid ~= nil then
        if not U.ValidCid(spec.judgeCid) then return Err('bad_args', 'judgeCid is invalid') end
        judgeCid = spec.judgeCid
    end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if not anyRole(actor, { 'clerk', 'judge' }) then return roleErr(actor, { 'clerk', 'judge' }) end
    if ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    return J.Locks.With('case:' .. id, function()
        if key then
            local h, okq = one(SQL.hearingByKey, { key })
            if not okq then return Err('db_unavailable', 'The court database did not answer') end
            if h then
                if tonumber(h.case_id) ~= id or h.kind ~= spec.kind then return Err('key_reused', 'This key was used for a different hearing') end
                return { ok = true, duplicate = true, hearingId = tonumber(h.id), at = tonumber(h.at) }
            end
        end
        local row = Courts.CaseRow(id)
        if not row then return Err('not_found', 'No such case') end
        if CASE_TERMINAL[row.state] then return Err('invalid_state', 'The case is ' .. row.state) end
        return Courts.ScheduleLocked(row, { kind = spec.kind, at = at, courtroom = spec.courtroom, judgeCid = judgeCid,
            notes = U.Str(spec.notes, 1000) }, actor, key)
    end)
end

-- ── charge classes and the bail schedule ──────────────────────────────────────────────────────

local CLASS_RANK = { infraction = 1, misdemeanor = 2, felony = 3 }

--- The most serious class among the case's charges (spec class, Config.Courts.ChargeClasses, default).
function Courts.ChargeClass(charges)
    local classes = C('ChargeClasses', {}) or {}
    local best, bestRank = nil, 0
    for _, c in ipairs(type(charges) == 'table' and charges or {}) do
        local cls = (CLASS_RANK[c.class or ''] and c.class) or classes[c.code or ''] or C('DefaultChargeClass', 'misdemeanor')
        local rank = CLASS_RANK[cls] or 2
        if rank > bestRank then best, bestRank = cls, rank end
    end
    return best or C('DefaultChargeClass', 'misdemeanor')
end

--- The schedule's bail for a case: amount (0 = own recognizance) or nil when a judge must decide.
function Courts.ScheduleBail(row)
    local cls = Courts.ChargeClass(U.Decode(row.charges))
    if cls == 'felony' and not C('ScheduleBailFelony', true) then return nil, cls end
    local amount = tonumber((C('DefaultBail', {}) or {})[cls])
    if amount == nil then return nil, cls end
    return math.max(0, math.floor(amount)), cls
end

-- ── decisions ─────────────────────────────────────────────────────────────────────────────────

local PRE_JUDGEMENT = HEARING_FROM.bail.from
local DECISION_KINDS = { plea = true, verdict = true, sentence = true, dismissal = true, bail = true, release_order = true, appeal = true }
local SENTENCE_FROM = { plea_guilty = true, guilty = true, sentencing_scheduled = true }
local VIOLATION_SENTENCE_FROM = { filed = true, hearing_scheduled = true }
local ORDER_KINDS = { jail = true, prison = true, fine = true, restitution = true, community_service = true, probation = true, parole = true }

-- Who may record which decision.
local DECISION_ROLES = {
    plea = { 'judge' }, verdict = { 'judge' }, sentence = { 'judge' }, bail = { 'judge' }, release_order = { 'judge' },
    dismissal = { 'judge', 'prosecutor' }, appeal = { 'judge' },
}

local function orderCharges(row)
    local out = {}
    for i, c in ipairs(U.Decode(row.charges) or {}) do
        if i > 50 then break end
        out[#out + 1] = { code = c.code, label = c.label or c.name, count = c.count }
    end
    return out
end

--- Normalises decision.orders into CreateOrder specs (validated by the 15B validator before anything is written).
local function sentenceSpecs(row, list)
    if type(list) ~= 'table' or #list < 1 or #list > 10 then return nil, Err('bad_args', 'a sentence needs 1..10 orders') end
    local specs = {}
    for i, o in ipairs(list) do
        if type(o) ~= 'table' or not ORDER_KINDS[o.kind] then return nil, Err('bad_args', 'order ' .. i .. ': unknown kind') end
        local spec = { cid = row.citizenid, kind = o.kind, minutes = o.minutes, amount = o.amount, units = o.units, days = o.days,
            conditions = o.conditions, victimCid = o.victimCid, facility = o.facility, dueAt = o.dueAt, merge = o.merge,
            charges = orderCharges(row), custodyId = tonumber(row.custody_id) }
        local okv, verr = J.Orders.Validate(spec, nil)
        if not okv then
            local e = verr or Err('bad_args', 'invalid order')
            e.message = ('order %d: %s'):format(i, tostring(e.message))
            return nil, e
        end
        specs[i] = spec
    end
    return specs
end

--- Creates (or finds again, by key) the orders of a sentence decision. Returns ids or nil, err.
function Courts.ApplySentence(row, decisionId, specs, actorSpec)
    local ids = {}
    for i, spec in ipairs(specs) do
        spec.sourceRef = { type = 'court_decision', id = tostring(decisionId) }
        local res = J.API.CreateOrder(spec, { key = ('pf-justice:court:%d:order:%d'):format(decisionId, i), actor = actorSpec })
        if type(res) ~= 'table' or not res.ok then return nil, res or Err('db_unavailable', 'The order could not be created') end
        ids[#ids + 1] = res.orderId
    end
    update(SQL.decisionOrders, { table.concat(ids, ','), decisionId })
    return ids
end

local function exonerateBailFor(row, actorSpec)
    local B = J.Bail
    if type(B) ~= 'table' or not (B.Store and U.Callable(B.Store.openFor)) or not row.custody_id then return nil end
    local b = B.Store.openFor('custody_id', tonumber(row.custody_id))
    if b and b.state == 'posted' then return B.Exonerate(tonumber(b.id), { actor = actorSpec, reason = 'case ended' }) end
    return nil
end

--- The case ended without a conviction (dismissal, acquittal, reversed appeal): remand ends, the case's
--- custody is released, posted bail is refunded.
local function endWithoutConviction(row, actorSpec, why)
    local out = { remandsVacated = vacateRemands(row.citizenid, why, actorSpec) }
    local c = Courts.OpenCustody(row.citizenid)
    if c and (tonumber(row.custody_id) == nil or tonumber(row.custody_id) == c.id) then
        out.custodyReleased = releaseCustody(c.id, actorSpec, why)
    end
    local ex = exonerateBailFor(row, actorSpec)
    out.bailExonerated = type(ex) == 'table' and ex.ok == true or nil
    return out
end

--- The bail part of a decision (judge or schedule). body = { amount?, conditions?, denied? }.
function Courts.ApplyBail(row, body, actorSpec, decisionId)
    local c = Courts.OpenCustody(row.citizenid)
    if body.denied then
        local out = {}
        if c and c.state ~= 'remanded' and J.Custody and U.Callable(J.Custody.SetState) then
            local res = J.Custody.SetState(c.id, 'remanded', { actor = actorSpec, note = 'bail denied by the court' })
            out.custodyRemanded = type(res) == 'table' and res.ok == true
        end
        if #Courts.OpenRemands(row.citizenid) == 0 then
            local res = J.API.CreateOrder({ cid = row.citizenid, kind = 'remand', custodyId = c and c.id or tonumber(row.custody_id),
                charges = orderCharges(row), sourceRef = { type = 'court_decision', id = tostring(decisionId) } },
                { key = ('pf-justice:court:%d:remand'):format(decisionId), actor = actorSpec })
            if type(res) ~= 'table' or not res.ok then return nil, res end
            out.remandOrderId = res.orderId
        end
        return out
    end
    local amount = U.Int(body.amount, 0, (Config.Bail and Config.Bail.MaxAmount) or 1000000)
    if not amount then return nil, Err('bad_args', 'bail amount is invalid') end
    if amount == 0 then
        -- released on own recognizance: remand ends, custody released by court order
        local out = { remandsVacated = vacateRemands(row.citizenid, 'released on own recognizance', actorSpec) }
        if c then out.custodyReleased = releaseCustody(c.id, actorSpec, 'own recognizance') end
        return out
    end
    local ref
    if c then ref = { custodyId = c.id }
    else
        local rem = Courts.OpenRemands(row.citizenid)[1]
        if rem then ref = { orderId = rem.id } end
    end
    if not ref then return { notHeld = true } end
    local res = J.Bail.Offer(ref, { amount = amount, conditions = body.conditions }, { actor = actorSpec })
    if type(res) ~= 'table' or not res.ok then return nil, res end
    -- a court's bail is open for a day (the family has to reach a desk); an officer's offer keeps its 10 minutes
    local open = C('BailOfferSeconds', 86400)
    if not res.duplicate and tonumber(open) and J.Bail.Store and U.Callable(J.Bail.Store.cas) then
        J.Bail.Store.cas(res.bailId, 'offered', { expires_at = os.time() + math.max(60, math.floor(tonumber(open))) })
    end
    return { bailId = res.bailId }
end

--- The schedule's (or a release order's) actor spec for internal calls.
local SCHEDULE_ACTOR = { kind = 'system', label = 'court schedule' }

--- RecordDecision(caseId, decision, opts) -> { ok, decisionId, orders?, ... }. opts = { key?, actor, hearingId? }.
function Courts.RecordDecision(caseId, decision, opts, ctx)
    if not Courts.Ready() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    local id = U.Int(caseId, 1, 2147483647)
    if not id or type(decision) ~= 'table' or not DECISION_KINDS[decision.kind] then
        return Err('bad_args', 'caseId and decision.kind are required')
    end
    local kind = decision.kind
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    if actor.kind == 'system' and not internal then return Err('no_permission', 'A judge decides') end
    local roles = DECISION_ROLES[kind]
    if kind == 'appeal' and decision.outcome == 'filed' then roles = { 'judge', 'defender' } end
    if not anyRole(actor, roles) then return roleErr(actor, roles) end
    -- the decision is authorised above; its effects (orders, custody, bail) act as the court itself, labelled
    -- with who decided, so a prosecutor's dismissal can still release the custody a judge would
    local actorSpec = { kind = 'system', label = ('court %s'):format(J.Actor.Tag(actor) or 'schedule'):sub(1, 48) }
    local decidedBy = opts.decidedBy == 'schedule' and internal and 'schedule' or (J.Actor.Tag(actor) or 'court')

    return J.Locks.With('case:' .. id, function()
        if key then
            local d, okq = one(SQL.decisionByKey, { key })
            if not okq then return Err('db_unavailable', 'The court database did not answer') end
            if d then
                if tonumber(d.case_id) ~= id or d.kind ~= kind then return Err('key_reused', 'This key was used for a different decision') end
                local res = { ok = true, duplicate = true, decisionId = tonumber(d.id) }
                if kind == 'sentence' then
                    -- a sentence cut off half-way is completed by the retry (the order keys make it safe)
                    local row = Courts.CaseRow(id)
                    local specs = row and sentenceSpecs(row, (U.Decode(d.body) or {}).orders)
                    if specs then
                        local ids, e = Courts.ApplySentence(row, tonumber(d.id), specs, actorSpec)
                        if not ids then return e end
                        res.orders = ids
                        if row.state ~= 'sentenced' and (SENTENCE_FROM[row.state] or VIOLATION_SENTENCE_FROM[row.state]) then moveCase(row, 'sentenced') end
                    end
                end
                return res
            end
        end
        local row = Courts.CaseRow(id)
        if not row then return Err('not_found', 'No such case') end
        if CASE_TERMINAL[row.state] then return Err('invalid_state', 'The case is ' .. row.state) end

        -- what the decision does: target state, the hearing it closes, its body
        local to, hearingKinds, body = nil, {}, { note = U.Str(decision.note, 1000) }
        local specs
        if kind == 'plea' then
            if decision.plea ~= 'guilty' and decision.plea ~= 'not_guilty' then return Err('bad_args', 'plea is guilty or not_guilty') end
            if row.state ~= 'filed' and row.state ~= 'arraignment_scheduled' and row.state ~= 'arraigned' then
                return Err('invalid_state', 'A plea is taken at the arraignment (case is ' .. row.state .. ')')
            end
            to, hearingKinds, body.plea = 'plea_' .. decision.plea, { 'arraignment' }, decision.plea
        elseif kind == 'verdict' then
            if decision.verdict ~= 'guilty' and decision.verdict ~= 'acquitted' then return Err('bad_args', 'verdict is guilty or acquitted') end
            if row.state ~= 'trial_scheduled' and row.state ~= 'trial' then return Err('invalid_state', 'No trial is scheduled (case is ' .. row.state .. ')') end
            to, hearingKinds, body.verdict = decision.verdict, { 'trial' }, decision.verdict
        elseif kind == 'sentence' then
            local from = row.kind == 'violation' and VIOLATION_SENTENCE_FROM or SENTENCE_FROM
            if not from[row.state] then return Err('invalid_state', 'The case is not ready for sentencing (' .. row.state .. ')') end
            local e
            specs, e = sentenceSpecs(row, decision.orders)
            if not specs then return e end
            to, hearingKinds, body.orders = 'sentenced', { 'sentencing', 'violation' }, decision.orders
        elseif kind == 'dismissal' then
            if row.state == 'sentenced' or row.state == 'appeal_pending' then return Err('invalid_state', 'A sentenced case ends by appeal') end
            to, hearingKinds = 'dismissed', { 'arraignment', 'bail', 'trial', 'sentencing', 'violation' }
        elseif kind == 'bail' then
            if not PRE_JUDGEMENT[row.state] then return Err('invalid_state', 'Bail is decided before judgement (case is ' .. row.state .. ')') end
            if decision.denied ~= true and U.Int(decision.amount, 0, (Config.Bail and Config.Bail.MaxAmount) or 1000000) == nil then
                return Err('bad_args', 'bail needs an amount (0 = own recognizance) or denied = true')
            end
            hearingKinds = { 'bail' }
            body.amount, body.denied = U.Int(decision.amount, 0), decision.denied == true or nil
            body.conditions = type(decision.conditions) == 'table' and decision.conditions or nil
        elseif kind == 'release_order' then
            body.reason = U.Str(decision.reason, 200) or 'court-ordered release'
        elseif kind == 'appeal' then
            local outcome = decision.outcome
            if outcome == 'filed' then
                if row.state ~= 'sentenced' then return Err('invalid_state', 'Only a sentenced case can be appealed') end
                to = 'appeal_pending'
            elseif outcome == 'affirmed' or outcome == 'reversed' then
                if row.state ~= 'appeal_pending' then return Err('invalid_state', 'No appeal is pending') end
                to, hearingKinds = 'closed', { 'appeal' }
            else
                return Err('bad_args', 'appeal outcome is filed, affirmed or reversed')
            end
            body.outcome = outcome
        end

        local hearing
        for _, hk in ipairs(hearingKinds) do
            hearing = hearing or one(SQL.scheduledOf, { id, hk })
        end
        local hearingId = opts.hearingId and U.Int(opts.hearingId, 1) or (hearing and tonumber(hearing.id)) or nil
        local now = os.time()
        local decisionId = insert(SQL.insertDecision, { id, hearingId, kind, U.Encode(body) or '{}', decidedBy, now, key })
        if not decisionId then return Err('db_unavailable', 'The decision could not be stored; nothing was changed') end
        local res = { ok = true, decisionId = decisionId }

        -- effects that create orders run before the case moves: a failure leaves the decision for a keyed retry
        if kind == 'sentence' then
            local ids, e = Courts.ApplySentence(row, decisionId, specs, actorSpec)
            if not ids then
                e = type(e) == 'table' and e or Err('db_unavailable', 'The sentence could not be applied')
                e.decisionId = decisionId
                return e
            end
            res.orders = ids
            -- the sentence replaces the remand (time held is the court's to credit through AdjustOrder)
            res.remandsVacated = vacateRemands(row.citizenid, 'sentenced', actorSpec)
        elseif kind == 'bail' then
            local out, e = Courts.ApplyBail(row, body, actorSpec, decisionId)
            if not out then
                e = type(e) == 'table' and e or Err('db_unavailable', 'The bail could not be applied')
                e.decisionId = decisionId
                return e
            end
            for k, v in pairs(out) do res[k] = v end
            if out.remandOrderId then update(SQL.decisionOrders, { tostring(out.remandOrderId), decisionId }) end
        elseif kind == 'release_order' then
            local rel = Courts.IssueReleaseLocked(row.citizenid, { reason = body.reason, caseId = id }, actor, actorSpec,
                key and (key .. ':release') or ('pf-justice:court:%d:release'):format(decisionId))
            if not rel.ok then rel.decisionId = decisionId return rel end
            for k, v in pairs(rel) do if k ~= 'ok' then res[k] = v end end
        end

        if to and to ~= row.state then
            local new = moveCase(row, to)
            if not new then return Err('busy', 'The case changed meanwhile; the decision is stored, retry with the same key') end
            row = new
        end
        if hearing then update(SQL.hearingState, { decidedBy == 'schedule' and 'auto' or 'held', hearing.id }) end
        if actor.kind == 'player' and Courts.HasRole(actor, 'judge') then update(SQL.caseJudge, { actor.cid, id }) end

        -- effects after the move (no orders are created here)
        if to == 'dismissed' or to == 'acquitted' then
            for k, v in pairs(endWithoutConviction(row, actorSpec, to)) do res[k] = v end
            if row.kind == 'citation_contest' then Courts.DecideContest(row, false, actorSpec) end
        elseif to == 'guilty' and row.kind == 'citation_contest' then
            Courts.DecideContest(row, true, actorSpec)
        elseif kind == 'appeal' and body.outcome == 'reversed' then
            res.ordersVacated = Courts.VacateSentence(id, actorSpec)
            for k, v in pairs(endWithoutConviction(row, actorSpec, 'reversed on appeal')) do res[k] = v end
        end

        J.Audit.Write('case', id, 'decision', { decisionId = decisionId, kind = kind, to = to, decidedBy = decidedBy, orders = res.orders }, actor)
        changed(row, { action = 'decision', decisionId = decisionId, kind = kind, state = row.state })
        Courts.Mail(row.citizenid, ('Court decision in case %s'):format(row.case_no),
            Courts.DecisionText(row, kind, body), ('pf-justice:decision:%d'):format(decisionId))
        res.state = row.state
        return res
    end)
end

--- One plain sentence describing a decision for the defendant's mail.
function Courts.DecisionText(row, kind, body)
    if kind == 'plea' then return ('A plea of %s was entered in case %s.'):format(body.plea == 'guilty' and 'guilty' or 'not guilty', row.case_no) end
    if kind == 'verdict' then return ('The court found you %s in case %s.'):format(body.verdict == 'guilty' and 'guilty' or 'not guilty', row.case_no) end
    if kind == 'sentence' then return ('You were sentenced in case %s. Your orders are listed at City Hall and in the court records.'):format(row.case_no) end
    if kind == 'dismissal' then return ('Case %s was dismissed.'):format(row.case_no) end
    if kind == 'bail' then
        if body.denied then return ('Bail was denied in case %s; you are remanded until trial.'):format(row.case_no) end
        if (body.amount or 0) == 0 then return ('You were released on your own recognizance in case %s.'):format(row.case_no) end
        return ('Bail of $%d was set in case %s.'):format(body.amount, row.case_no)
    end
    if kind == 'release_order' then return ('The court ordered your release in case %s.'):format(row.case_no) end
    return ('The appeal in case %s: %s.'):format(row.case_no, tostring(body.outcome))
end

--- A citation contest decided by the court: upheld (guilty) or dismissed.
function Courts.DecideContest(row, upheld, actorSpec)
    for _, r in ipairs(many(SQL.refsOf, { row.id }) or {}) do
        if r.ref_type == 'order' and J.Orders and U.Callable(J.Orders.DecideCitation) then
            J.Orders.DecideCitation(tonumber(r.ref_id), upheld, { actor = actorSpec }, {})
        end
    end
end

--- Vacates the open orders every sentence decision of the case created (reversed appeal).
function Courts.VacateSentence(caseId, actorSpec)
    local n = 0
    for _, d in ipairs(many(SQL.decisionsOf, { caseId }) or {}) do
        if d.kind == 'sentence' then
            for _, o in ipairs(many(SQL.ordersOfDecision, { tostring(d.id) }) or {}) do
                if J.States.IsOpen(o.kind, o.state) then
                    local res = J.API.SetOrderState(tonumber(o.id), 'vacated', { reason = 'reversed on appeal', actor = actorSpec })
                    if type(res) == 'table' and res.ok then n = n + 1 end
                end
            end
        end
    end
    return n
end

-- ── court orders (IsCourtOrderValid) ──────────────────────────────────────────────────────────

local function orderRef(id) return ('CO-%s-%d'):format(os.date('%y%m', os.time()), id) end

local function storeCourtOrder(kind, cid, caseId, body, judgeCid, validUntil, key)
    local now = os.time()
    local tmp = ('T%d%06d'):format(now % 10000000000, math.random(0, 999999))
    local id = insert(SQL.insertCourtOrder, { tmp, kind, cid, caseId, U.Encode(body), judgeCid, validUntil, now, key })
    if not id then return nil end
    local ref = orderRef(id)
    update(SQL.setCourtOrderRef, { ref, id })
    return id, ref
end

--- IssueCourtOrder(spec, opts): a judge. spec = { kind (Config.Courts.OrderKinds), cid?, caseId?, hours?,
--- evidenceIds?, tags?, address?, note? }. Returns { ok, courtOrderId, ref, validUntil }.
function Courts.IssueCourtOrder(spec, opts, ctx)
    if not Courts.Ready() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    if type(spec) ~= 'table' or not (C('OrderKinds', {}) or {})[spec.kind] then return Err('bad_args', 'unknown court order kind') end
    local kind = spec.kind
    local cid
    if spec.cid ~= nil and spec.cid ~= '' then
        if not U.ValidCid(spec.cid) then return Err('bad_args', 'cid is invalid') end
        cid = spec.cid
    end
    if (kind == 'medical_records' or kind == 'telemetry') and not cid then return Err('bad_args', 'This order names a person (cid)') end
    local evidenceIds = cleanRefList(spec.evidenceIds, 50)
    local tags = cleanRefList(spec.tags, 50)
    if not evidenceIds or not tags then return Err('bad_args', 'evidenceIds / tags are invalid') end
    if (kind == 'evidence_destroy' or kind == 'evidence_release') and #evidenceIds + #tags == 0 then
        return Err('bad_args', 'An evidence order names the evidence (evidenceIds or tags)')
    end
    if kind == 'search' and not cid and not U.Str(spec.address, 128) then return Err('bad_args', 'A search order names a person or an address') end
    local hours = U.Int(spec.hours or C('OrderHours', 72), 1, C('MaxOrderHours', 720))
    if not hours then return Err('bad_args', 'hours are out of range') end
    local caseId = spec.caseId ~= nil and U.Int(spec.caseId, 1, 2147483647) or nil
    if spec.caseId ~= nil and not caseId then return Err('bad_args', 'caseId is invalid') end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    if actor.kind == 'system' and not (ctx.invoker == nil or ctx.invoker == J.RESOURCE) then return Err('no_permission', 'A judge issues court orders') end
    if not Courts.HasRole(actor, 'judge') then return roleErr(actor, { 'judge' }) end
    return J.Locks.With('courtorder:' .. (key or (cid or 'any')), function()
        if key then
            local r = one(SQL.courtOrderByKey, { key })
            if r then
                if r.kind ~= kind or (r.citizenid or '') ~= (cid or '') then return Err('key_reused', 'This key was used for a different court order') end
                return { ok = true, duplicate = true, courtOrderId = tonumber(r.id), ref = r.ref, validUntil = tonumber(r.valid_until) }
            end
        end
        local validUntil = os.time() + hours * 3600
        local body = { evidenceIds = evidenceIds, tags = tags, address = U.Str(spec.address, 128), note = U.Str(spec.note, 500) }
        local id, ref = storeCourtOrder(kind, cid, caseId, body, J.Actor.Tag(actor) or 'court', validUntil, key)
        if not id then return Err('db_unavailable', 'The court order could not be stored') end
        J.Audit.Write('court_order', id, 'issued', { ref = ref, kind = kind, cid = cid, hours = hours, caseId = caseId }, actor)
        return { ok = true, courtOrderId = id, ref = ref, validUntil = validUntil }
    end)
end

--- RevokeCourtOrder(ref, opts): a judge.
function Courts.RevokeCourtOrder(ref, opts, ctx)
    if not Courts.Ready() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    ref = U.Str(ref, 24)
    if not ref then return Err('bad_args', 'ref is required') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    if not Courts.HasRole(actor, 'judge') then return roleErr(actor, { 'judge' }) end
    local r = one(SQL.courtOrderByRef, { ref })
    if not r then return Err('not_found', 'No such court order') end
    if r.revoked_at then return { ok = true, duplicate = true } end
    if update(SQL.revokeCourtOrder, { os.time(), r.id }) ~= 1 then return Err('busy', 'The court order changed meanwhile') end
    J.Audit.Write('court_order', r.id, 'revoked', { ref = ref, reason = U.Str(opts.reason, 200) }, actor)
    return { ok = true }
end

local function listHas(list, v)
    if v == nil then return false end
    v = tostring(v)
    for _, x in ipairs(type(list) == 'table' and list or {}) do if tostring(x) == v then return true end end
    return false
end

--- IsCourtOrderValid(ref, purpose, cid, ctx?) -> boolean. Valid only for an issued, unrevoked, unexpired order
--- of that purpose whose person matches (an order without a person matches only a call without one); evidence
--- purposes also need the evidence (ctx.evidenceId or ctx.tag) named in the order. Fails closed on any error.
function Courts.IsCourtOrderValid(ref, purpose, cid, ctx)
    if not Courts.Ready() then return false end
    if type(ref) == 'number' then ref = tostring(ref) end
    if type(ref) ~= 'string' or #ref < 1 or #ref > 24 or not ref:match('^[%w%-]+$') then return false end
    if type(purpose) ~= 'string' or not (C('OrderKinds', {}) or {})[purpose] then return false end
    if cid ~= nil and not U.ValidCid(cid) then return false end
    local r, okq = one(SQL.courtOrderByRef, { ref })
    if not okq or not r then return false end
    if r.kind ~= purpose or r.revoked_at ~= nil then return false end
    local untilAt = tonumber(r.valid_until)
    if untilAt and untilAt < os.time() then return false end
    local orderCid = r.citizenid
    if orderCid ~= nil and orderCid ~= '' then
        -- destroying evidence names no person; everything else must be about the order's person
        if cid ~= orderCid and not (purpose == 'evidence_destroy' and cid == nil) then return false end
    elseif cid ~= nil then
        return false
    end
    if purpose == 'evidence_destroy' or purpose == 'evidence_release' then
        local body = U.Decode(r.body) or {}
        ctx = type(ctx) == 'table' and ctx or {}
        if not (listHas(body.evidenceIds, ctx.evidenceId) or listHas(body.tags, ctx.tag)) then return false end
    end
    return true
end

-- ── release orders ────────────────────────────────────────────────────────────────────────────

--- With the case lock held (or none): vacates the citizen's open incarceration orders, releases the open
--- custody by court order and stores the release order. Returns { ok, releaseOrderId, ref, released, custodyReleased }.
function Courts.IssueReleaseLocked(cid, spec, actor, actorSpec, key)
    if key then
        local r = one(SQL.courtOrderByKey, { key })
        if r then return { ok = true, duplicate = true, releaseOrderId = tonumber(r.id), ref = r.ref } end
    end
    local reason = U.Str(spec.reason, 200) or 'court-ordered release'
    local id, ref = storeCourtOrder('release', cid, spec.caseId, { reason = reason }, J.Actor.Tag(actor) or 'court', nil, key)
    if not id then return Err('db_unavailable', 'The release order could not be stored') end
    local rel = J.API.ReleaseNow(cid, 'court order ' .. ref .. ': ' .. reason, { actor = actorSpec })
    local c = Courts.OpenCustody(cid)
    local custodyReleased = c and releaseCustody(c.id, actorSpec, 'court order ' .. ref) or false
    J.Audit.Write('court_order', id, 'release', { ref = ref, cid = cid, released = type(rel) == 'table' and rel.released, custody = c and c.id }, actor)
    Courts.Mail(cid, 'Release order ' .. ref, ('The court ordered your release (%s).'):format(reason), 'pf-justice:release:' .. id)
    return { ok = true, releaseOrderId = id, ref = ref, released = type(rel) == 'table' and rel.released or 0, custodyReleased = custodyReleased }
end

--- IssueReleaseOrder(cid, spec, opts): an on-duty judge (also ends a remand without minutes).
function Courts.IssueReleaseOrder(cid, spec, opts, ctx)
    if not Courts.Ready() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    spec = type(spec) == 'table' and spec or {}
    if not U.ValidCid(cid) then return Err('bad_args', 'cid is invalid') end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    if actor.kind == 'system' and not (ctx.invoker == nil or ctx.invoker == J.RESOURCE) then return Err('no_permission', 'A judge orders a release') end
    if not Courts.HasRole(actor, 'judge') then return roleErr(actor, { 'judge' }) end
    local caseId = spec.caseId ~= nil and U.Int(spec.caseId, 1, 2147483647) or nil
    return J.Locks.With('release:' .. cid, function()
        return Courts.IssueReleaseLocked(cid, { reason = spec.reason, caseId = caseId }, actor,
            { kind = 'system', label = ('court %s'):format(J.Actor.Tag(actor) or 'court'):sub(1, 48) }, key)
    end)
end

-- ── reads ─────────────────────────────────────────────────────────────────────────────────────

function Courts.GetCase(caseId)
    if not Courts.Ready() then return notReady() end
    local id = U.Int(caseId, 1, 2147483647)
    if not id then return Err('bad_args', 'caseId is invalid') end
    local row = Courts.CaseRow(id)
    if not row then return Err('not_found', 'No such case') end
    local case = Courts.PublicCase(row)
    case.hearings, case.decisions, case.refs = {}, {}, {}
    for _, h in ipairs(many(SQL.hearingsOf, { id }) or {}) do case.hearings[#case.hearings + 1] = Courts.PublicHearing(h) end
    for _, d in ipairs(many(SQL.decisionsOf, { id }) or {}) do
        case.decisions[#case.decisions + 1] = { id = tonumber(d.id), kind = d.kind, body = U.Decode(d.body), decidedBy = d.decided_by,
            orderIds = d.order_ids, hearingId = tonumber(d.hearing_id), at = tonumber(d.at) }
    end
    for _, r in ipairs(many(SQL.refsOf, { id }) or {}) do case.refs[#case.refs + 1] = { type = r.ref_type, id = r.ref_id } end
    return { ok = true, case = case }
end

--- ListDocket(filter): hearings by time. filter = { from?, to?, state = 'scheduled', courtroom?, limit <= 100 }.
--- Other resources get the public docket (no citizen ids).
function Courts.ListDocket(filter, ctx)
    if not Courts.Ready() then return notReady() end
    filter = type(filter) == 'table' and filter or {}
    ctx = ctx or {}
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    local now = os.time()
    local from = U.Int(filter.from or (now - 86400), 0) or (now - 86400)
    local to = U.Int(filter.to or (now + 30 * 86400), 0) or (now + 30 * 86400)
    local states = { scheduled = true, held = true, auto = true, cancelled = true, adjourned = true }
    local state = states[filter.state or 'scheduled'] and (filter.state or 'scheduled') or 'scheduled'
    local limit = U.Int(filter.limit or 50, 1, 100) or 50
    local rows = many(SQL.docket, { state, from, to, limit })
    if not rows then return Err('db_unavailable', 'The court database did not answer') end
    local list = {}
    for _, h in ipairs(rows) do
        if filter.courtroom == nil or filter.courtroom == h.courtroom then
            list[#list + 1] = { hearingId = tonumber(h.id), caseId = tonumber(h.case_id), caseNo = h.case_no, caseKind = h.case_kind,
                kind = h.kind, courtroom = h.courtroom, at = tonumber(h.at), state = h.state, judgeCid = h.judge_cid,
                cid = internal and h.citizenid or nil }
        end
    end
    return { ok = true, list = list }
end

-- ── low population: the published schedule (architecture 4.7.7) ──────────────────────────────

--- One pass: arraignment and bail hearings that no judge decided AutoAfterSeconds after their time, while
--- no judge has been on duty for that long, are decided by the schedule (non-punitive only).
function Courts.AutoTick(now)
    if not Courts.Ready() then return 0 end
    now = now or os.time()
    local after = C('AutoAfterSeconds', 900)
    if #Courts.JudgesOnDuty() > 0 then
        Courts.lastJudgeAt = now
        return 0
    end
    if now - (Courts.lastJudgeAt or now) < after then return 0 end
    local n = 0
    for _, h in ipairs(many(SQL.dueAuto, { now - after }) or {}) do
        local row = Courts.CaseRow(tonumber(h.case_id))
        if row and not CASE_TERMINAL[row.state] then
            local opts = { actor = SCHEDULE_ACTOR, decidedBy = 'schedule', hearingId = tonumber(h.id) }
            if h.kind == 'arraignment' and (row.state == 'arraignment_scheduled' or row.state == 'filed') then
                opts.key = ('pf-justice:hearing:%d:auto_plea'):format(h.id)
                local res = Courts.RecordDecision(row.id, { kind = 'plea', plea = 'not_guilty', note = 'Entered by the court schedule' }, opts, {})
                if type(res) == 'table' and res.ok then n = n + 1 end
            end
            -- bail by the schedule when the defendant is held (custody or remand)
            row = Courts.CaseRow(row.id) or row
            local held = Courts.OpenCustody(row.citizenid) or Courts.OpenRemands(row.citizenid)[1]
            local amount = Courts.ScheduleBail(row)
            if held and amount ~= nil and PRE_JUDGEMENT[row.state] then
                local res = Courts.RecordDecision(row.id, { kind = 'bail', amount = amount, note = 'Bail by the court schedule' },
                    { actor = SCHEDULE_ACTOR, decidedBy = 'schedule', key = ('pf-justice:hearing:%d:auto_bail'):format(h.id) }, {})
                if type(res) == 'table' and res.ok then n = n + 1 end
            end
            -- whatever the schedule could not decide stays with a judge; the hearing is marked as passed to them
            update(SQL.hearingState, { 'auto', h.id })
        else
            update(SQL.hearingState, { 'cancelled', h.id })
        end
    end
    return n
end

--- Adds the court functions to PFJustice.API (the internal, unfiltered table of 15B's api.lua, which is
--- built after this file loads): Schema.Run calls this at boot, when every file of the resource is loaded.
function Courts.InstallApi()
    if type(J.API) ~= 'table' then return false end
    J.API.FileCase = function(spec, opts) return Courts.FileCase(spec, opts, {}) end
    J.API.IsCourtOrderValid = function(ref, purpose, cid, extra) return Courts.IsCourtOrderValid(ref, purpose, cid, extra) end
    J.API.RequestWarrantReview = function(spec, opts) return J.Warrants.Request(spec, opts, {}) end
    return true
end

--- The court tick (named for specs; the thread below calls it every Config.Courts.TickSeconds).
function Courts.Tick(now)
    now = now or os.time()
    local n = Courts.AutoTick(now)
    if J.Warrants and U.Callable(J.Warrants.Tick) then J.Warrants.Tick(now) end
    return n
end

--- A deleted character: their cases and court orders stay as court history under an anonymous token.
function Courts.OnCharacterDeleted(cid)
    if not U.ValidCid(cid) or not Courts.Ready() then return 0 end
    local token = ('anon-%08x%04x'):format(math.random(0, 0x7fffffff), math.random(0, 0xffff))
    local n = (update(SQL.anonCases, { token, cid }) or 0) + (update(SQL.anonCourtOrders, { token, cid }) or 0)
    return n
end
AddEventHandler('pfm-core:server:characterDeleted', function(cid) Courts.OnCharacterDeleted(cid) end)

-- ── exports (Config.Callers at the boundary; the module functions get the invoker) ────────────

local function export(name, fn, refused)
    exports(name, function(...)
        local allowed, res = J.Callers.Check(name, GetInvokingResource())
        if not allowed then
            if refused ~= nil then return refused end
            return res
        end
        return fn({ invoker = res }, ...)
    end)
end
Courts.Export = export

export('FileCase', function(ctx, spec, opts) return Courts.FileCase(spec, opts, ctx) end)
export('ScheduleHearing', function(ctx, caseId, spec, opts) return Courts.ScheduleHearing(caseId, spec, opts, ctx) end)
export('RecordDecision', function(ctx, caseId, decision, opts) return Courts.RecordDecision(caseId, decision, opts, ctx) end)
export('IssueReleaseOrder', function(ctx, cid, spec, opts) return Courts.IssueReleaseOrder(cid, spec, opts, ctx) end)
export('IssueCourtOrder', function(ctx, spec, opts) return Courts.IssueCourtOrder(spec, opts, ctx) end)
export('RevokeCourtOrder', function(ctx, ref, opts) return Courts.RevokeCourtOrder(ref, opts, ctx) end)
export('GetCase', function(ctx, caseId) return Courts.GetCase(caseId) end)
export('ListDocket', function(ctx, filter) return Courts.ListDocket(filter, ctx) end)
export('IsCourtOrderValid', function(ctx, ref, purpose, cid, extra)
    local ok, valid = pcall(Courts.IsCourtOrderValid, ref, purpose, cid, extra)
    return ok and valid == true
end, false)

-- ── commands for judges (until the b21 court app): court orders ───────────────────────────────

local function reply(src, text, kind)
    TriggerClientEvent('QBCore:Notify', src, text, kind or 'primary')
    TriggerClientEvent('chat:addMessage', src, { args = { 'Court', text } })
end
Courts.Reply = reply

--- /courtorder <kind> <cid|-> [hours] [evidence ids, comma separated]: a judge issues a court order.
function Courts.CommandCourtOrder(src, args)
    src = U.Src(src)
    if not src then return end
    args = type(args) == 'table' and args or {}
    local spec = { kind = args[1], cid = (args[2] ~= '-' and args[2]) or nil, hours = tonumber(args[3]) }
    if args[4] then
        spec.evidenceIds = {}
        for v in tostring(args[4]):gmatch('[^,]+') do spec.evidenceIds[#spec.evidenceIds + 1] = v end
    end
    local res = Courts.IssueCourtOrder(spec, { actor = { src = src } }, {})
    if res.ok then reply(src, ('Court order %s issued (valid until %s)'):format(res.ref, fmtTime(res.validUntil)), 'success')
    else reply(src, 'Not issued: ' .. tostring(res.message or res.error), 'error') end
    return res
end

if C('Commands', true) then
    RegisterCommand('courtorder', function(source, args) Courts.CommandCourtOrder(source, args) end, false)
end

CreateThread(function()
    while not J.Ready() do Wait(5000) end
    while true do
        Wait(math.max(10, C('TickSeconds', 60)) * 1000)
        local ok, err = pcall(Courts.Tick, os.time())
        if not ok then print(('^1[pf-justice]^7 court tick failed: %s'):format(tostring(err))) end
    end
end)
