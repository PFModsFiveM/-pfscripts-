-- ============================================================================
-- PF Police MDT - relays for the custody, evidence, lab and telemetry pages (batch 21, unit 21B)
-- ============================================================================
-- The pages html/pages/custody.js, evidence_coc.js, lab.js and timeline.js read state other
-- resources own. This file only relays: it never stores anything and runs no SQL. Every answer is
-- what the owner returned, with the caller as the viewer or actor so the owner applies its own
-- rules (duty, rank, distance, lab qualification, timeline reader):
--   * pf-justice (15B/15C): GetCustody, GetBooking, GetPropertyReceipt, GetCustodyLog,
--     GetActiveIncarceration, GetOrders, GetBail, AddCustodyLog. The sentence clock is shown read-only; nothing here changes an order;
--   * pfm-policejob evidence (15D/18D): ListEvidence, GetEvidence, TransferEvidence, SubmitToLab,
--     ListLabJobs, ReleaseLabResult;
--   * pfm-policejob telemetry (18C): GetTimeline. It is a metadata timeline, never video.
-- The use-of-force, IA, review and qualification pages call server/personnel_ext.lua directly.
--
-- Endpoints (QBCore callbacks, one table argument; answer { ok, success, ... } or { ok = false,
-- success = false, error, message }). Every name is behind server/access.lua (police only); writes
-- also need duty and the grade of their action:
--   pf_mdt:pages:access                   what the caller may do (navigation; the owners check again)
--   pf_mdt:custody:get                    custody, booking, property receipt, the newest custody log page, sentence
--                                         clock, orders and bail (on duty; every read audited)
--   pf_mdt:custody:history                an older page of the custody log (on duty; audited)
--   pf_mdt:custody:log                    custodyLog      one custody log entry (rights read, meal ...)
--   pf_mdt:evidence:list, :get            reads (paged list; one item with chain and integrity)
--   pf_mdt:evidence:transfer              evidenceHandle  hand evidence in at a lab, locker or court
--   pf_mdt:lab:queue                      evidence held at a lab with its lab jobs
--   pf_mdt:lab:submit                     evidenceHandle  request tests on evidence at the lab
--   pf_mdt:lab:release                    labRelease      release a ready result (lab tech qualification)
--   pf_mdt:timeline:get                   an officer's telemetry rows (own; supervisors per pfm-policejob)

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtPagesExt = PFMdtPagesExt or {}
local X = PFMdtPagesExt
local Access = PFMdtAccess

-- Grades used when config.lua has no entry (same pattern as server/personnel_ext.lua).
local DEFAULT_GRADES = {
    custodyLog = 0,      -- add a custody log entry
    evidenceHandle = 0,  -- transfer evidence and request lab tests (pfm-policejob checks holder and place)
    labRelease = 0,      -- release a lab result (pfm-policejob also needs the lab tech qualification)
}
Config.Permissions = Config.Permissions or {}
for action, grade in pairs(DEFAULT_GRADES) do
    if Config.Permissions[action] == nil then Config.Permissions[action] = grade end
end

function X.Cfg()
    local c = type(Config.PagesExt) == 'table' and Config.PagesExt or {}
    return {
        LabRole = type(c.LabRole) == 'string' and c.LabRole or 'lab_tech',          -- pfm-policejob Config.Evidence.LabRole
        TimelineSupervisorGrade = tonumber(c.TimelineSupervisorGrade) or 2,       -- pfm-policejob Telemetry.SupervisorGrade
        TimelineMaxWindow = tonumber(c.TimelineMaxWindow) or 6 * 3600,            -- pfm-policejob Telemetry.MaxWindowSeconds
        EvidencePage = tonumber(c.EvidencePage) or 25,
        LabPage = tonumber(c.LabPage) or 10,                                      -- items per lab queue page (one ListLabJobs for the page)
        OrdersShown = tonumber(c.OrdersShown) or 20,
        LogPage = tonumber(c.LogPage) or 25,                                      -- custody log rows per page (pf-justice caps at 50)
        ReadRateMs = tonumber(c.ReadRateMs) or 300,
        WriteRateMs = tonumber(c.WriteRateMs) or 1500,
    }
end

-- Kinds of custody log entry an officer adds from the MDT (pf-justice LOG_KINDS; it checks again).
X.LogKinds = { rights_read = true, phone_call = true, attorney_visit = true, interview_start = true, interview_end = true,
    meal = true, medical_check = true, use_of_force = true, note = true }
X.TransferKinds = { lab = true, court = true, locker = true }
X.Tests = { dna = true, prints = true, ballistics = true, tox = true, drug_id = true, gsr = true, trace = true }

-- ── helpers ─────────────────────────────────────────────────────────────────

local function err(code, message, extra)
    local out = { ok = false, success = false, error = code, message = message or code }
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end

-- An owner's answer as the page reads it: success mirrors ok, a refusal keeps its code and message.
local function relay(res)
    if type(res) ~= 'table' then return err('unavailable', 'The records service did not answer') end
    if res.ok then res.success = true return res end
    return err(tostring(res.error or 'unavailable'):sub(1, 32), type(res.message) == 'string' and res.message:sub(1, 200) or nil)
end

local function int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n)
    if not n or (min and n < min) or (max and n > max) then return nil end
    return n
end

local function cidOf(v)
    if type(v) ~= 'string' or #v < 1 or #v > 32 or not v:match('^[%w_%-]+$') then return nil end
    return v
end

local function text(v, maxLen)
    if type(v) ~= 'string' then return nil end
    local s = v:gsub('%c', ' '):match('^%s*(.-)%s*$')
    if s == '' then return nil end
    return s:sub(1, maxLen)
end

local function started(res) return GetResourceState(res) == 'started' end

-- One export call into another resource; nil, 'offline' | 'error' when it is not running or broke off.
local function call(res, name, ...)
    if not started(res) then return nil, 'offline' end
    local n, args = select('#', ...), { ... }
    local ok, out = pcall(function()
        local e = exports[res]
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok then
        print(('^3[pf-policemdt]^7 pages: %s:%s failed: %s'):format(res, name, tostring(out)))
        return nil, 'error'
    end
    return out
end
X.Call = call

local OFFLINE = {
    ['pf-justice'] = 'Justice records are not available right now',
    ['pfm-policejob'] = 'Evidence and telemetry are not available right now',
}
local function owner(res, name, ...)
    local out, why = call(res, name, ...)
    if why then return err('unavailable', OFFLINE[res]) end
    return relay(out)
end

local function actorOf(src)
    local job, P = Access.Job(src)
    if not job or not P or not (Config.AllowedJobs and Config.AllowedJobs[job.name]) then return nil end
    return { src = src, cid = P.PlayerData.citizenid, grade = job.grade, onduty = job.onduty, job = job.name }
end

-- One pf_mdt_record_audit 'read' row, written and waited for (same insert as pages_records.lua).
-- Returns true when the row was stored.
local function auditRead(entity, entityId, actor, detail)
    local d = json.encode(detail or {})
    if #d > 4000 then d = d:sub(1, 4000) end
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT INTO pf_mdt_record_audit (entity, entity_id, action, by_cid, by_job, detail, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { entity, tostring(entityId), 'read', actor.cid, actor.job, d, os.time() })
    end)
    if not ok then print(('^1[pf-policemdt]^7 pages: audit insert failed: %s'):format(tostring(id))) end
    return ok and id ~= nil and id ~= false
end
X.AuditRead = auditRead

-- The booking fields the custody page shows; anything else pf-justice adds stays on the server.
X.BookingFields = { 'bookingNo', 'at', 'bookedBy', 'height', 'marks', 'screening', 'fingerprint', 'bloodtype', 'dnaSampleRef',
    'notes', 'mugshotUrl', 'clientSupplied', 'receiptId' }
local function bookingView(b)
    if type(b) ~= 'table' then return nil end
    local out = {}
    for _, k in ipairs(X.BookingFields) do out[k] = b[k] end
    return out
end

-- The property receipt as the page shows it: item names, amounts and states (item info such as
-- serials stays on the server; the evidence id says where a forfeited item went).
X.ReceiptFields = { 'id', 'state', 'reason', 'seizedBy', 'seizedAt', 'returnedAt', 'orderId' }
local function receiptView(r)
    if type(r) ~= 'table' then return nil end
    local out = {}
    for _, k in ipairs(X.ReceiptFields) do out[k] = r[k] end
    out.items = {}
    for i, it in ipairs(type(r.items) == 'table' and r.items or {}) do
        if i > 100 then break end
        out.items[i] = { name = it.name, amount = it.amount, state = it.state, evidenceId = it.evidenceId }
    end
    return out
end

-- One page of custody log rows as pf-justice answered it (rows bounded; data kept as the owner wrote it).
local function logView(res)
    local list = {}
    for i, l in ipairs(type(res.list) == 'table' and res.list or {}) do
        if i > 50 then break end
        list[i] = { id = l.id, kind = l.kind, data = type(l.data) == 'table' and l.data or nil, actorCid = l.actorCid, at = l.at }
    end
    return list, int(res.nextBefore, 1)
end

local function hasQual(cid, qual)
    local res = call('pf-government', 'HasQualification', cid, qual)
    return res == true
end

-- ── access ──────────────────────────────────────────────────────────────────

--- What the caller may do, for the pages' navigation and buttons. A hint only: every owner checks
--- again on each call (a hidden button is never the only gate).
function X.Access(src)
    local a = actorOf(src)
    if not a then return err('no_access', 'Police only') end
    local c = X.Cfg()
    local can = {}
    for _, action in ipairs({ 'forceReports', 'forceReview', 'forceClose', 'iaIntake', 'iaManage', 'perfReview', 'viewPersonnel',
        'custodyLog', 'evidenceHandle', 'labRelease' }) do
        can[action] = Access.Rank(src, action) == true
    end
    can.timelineOthers = a.grade >= c.TimelineSupervisorGrade
    can.labTech = hasQual(a.cid, c.LabRole)
    return { ok = true, success = true, cid = a.cid, grade = a.grade, onduty = a.onduty == true, can = can,
        services = { justice = started('pf-justice'), evidence = started('pfm-policejob'), government = started('pf-government') } }
end

-- ── custody ─────────────────────────────────────────────────────────────────

--- The custody record of a citizen: open custody (or the latest closed one), its booking, the
--- active incarceration with the server's remaining time (read-only), recent orders and bail.
--- On-duty officers only. The booking holds identification and medical screening, so every read
--- is audited (entity 'citizen', never deduplicated, like the death record of pages_records.lua) and
--- written before the answer leaves: a read that cannot be audited is not shown.
function X.CustodyGet(src, data)
    local a = actorOf(src)
    if not a then return err('no_access', 'Police only') end
    if not a.onduty then return err('not_on_duty', 'You must be on duty to read custody records') end
    local cid = cidOf(type(data) == 'table' and data.cid or nil)
    if not cid then return err('bad_args', 'Enter a citizen id') end
    if not started('pf-justice') then return err('unavailable', OFFLINE['pf-justice']) end
    local cu = owner('pf-justice', 'GetCustody', cid, { latest = true })
    if not cu.ok then return cu end
    local out = { ok = true, success = true, cid = cid, custody = cu.custody, at = os.time() }
    local custodyId = type(cu.custody) == 'table' and int(cu.custody.id, 1) or nil
    if custodyId then
        local b = owner('pf-justice', 'GetBooking', custodyId)
        if b.ok then out.booking = bookingView(b.booking)
        elseif b.error ~= 'not_found' then out.bookingError = b.message end
        local receiptId = out.booking and int(out.booking.receiptId, 1) or nil
        if receiptId then
            local r = owner('pf-justice', 'GetPropertyReceipt', receiptId, { viewer = src })
            if r.ok then out.receipt = receiptView(r.receipt) else out.receiptError = r.message end
        end
        local log = owner('pf-justice', 'GetCustodyLog', custodyId, { viewer = src, limit = X.Cfg().LogPage })
        if log.ok then out.log, out.logNext = logView(log) else out.logError = log.message end
    end
    local inc = owner('pf-justice', 'GetActiveIncarceration', cid)
    if inc.ok then
        out.incarceration = inc.order and { order = inc.order, remainingSeconds = int(inc.remainingSeconds, 0) or 0, facility = inc.facility } or nil
    else
        out.incarcerationError = inc.message
    end
    local orders = owner('pf-justice', 'GetOrders', cid, { limit = X.Cfg().OrdersShown })
    if orders.ok then out.orders = orders.list else out.ordersError = orders.message end
    local bail = owner('pf-justice', 'GetBail', cid)
    if bail.ok then out.bail = bail.bail end
    if not auditRead('citizen', cid, a, { op = 'custody', custodyId = custodyId, booking = out.booking ~= nil or nil,
        receipt = out.receipt and out.receipt.id or nil, log = out.log ~= nil or nil }) then
        return err('db_unavailable', 'The read could not be audited; try again')
    end
    return out
end

--- An older page of one custody's log (the newest page comes with pf_mdt:custody:get). On-duty
--- officers only (pf-justice checks the viewer again); audited before the answer leaves, like the
--- custody read.
function X.CustodyHistory(src, data)
    local a = actorOf(src)
    if not a then return err('no_access', 'Police only') end
    if not a.onduty then return err('not_on_duty', 'You must be on duty to read custody records') end
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    if not Access.AllowRate(src, 'pages:custodyHistory', X.Cfg().ReadRateMs) then return err('rate_limited', 'Slow down') end
    local custodyId = int(data.custodyId, 1)
    if not custodyId then return err('bad_args', 'Unknown custody') end
    local before = int(data.before, 1)
    if not before then return err('bad_args', 'Bad page') end
    local res = owner('pf-justice', 'GetCustodyLog', custodyId, { viewer = src, before = before, limit = X.Cfg().LogPage })
    if not res.ok then return res end
    local list, nextBefore = logView(res)
    if not auditRead('custody', custodyId, a, { op = 'custody_log', before = before, rows = #list }) then
        return err('db_unavailable', 'The read could not be audited; try again')
    end
    return { ok = true, success = true, custodyId = custodyId, log = list, logNext = nextBefore }
end

function X.CustodyLog(src, data)
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    if not Access.AllowRate(src, 'pages:custodyLog', X.Cfg().WriteRateMs) then return err('rate_limited', 'Slow down') end
    local custodyId = int(data.custodyId, 1)
    if not custodyId then return err('bad_args', 'Unknown custody') end
    local kind = type(data.kind) == 'string' and data.kind or ''
    if not X.LogKinds[kind] then return err('bad_args', 'Unknown log entry') end
    local note = text(data.text, 500)
    if kind == 'note' and not note then return err('bad_args', 'Write the note') end
    return owner('pf-justice', 'AddCustodyLog', custodyId, kind, note and { text = note } or {}, { actor = { src = src } })
end

-- ── evidence ────────────────────────────────────────────────────────────────

local function evidenceId(v)
    if type(v) == 'string' and #v <= 24 and v:match('^%u+%-%d+%-%d+$') then return v end
    return int(v, 1)
end

function X.EvidenceList(src, data)
    data = type(data) == 'table' and data or {}
    if not Access.AllowRate(src, 'pages:evidenceList', X.Cfg().ReadRateMs) then return err('rate_limited', 'Slow down') end
    local filter = { viewer = src, limit = X.Cfg().EvidencePage }
    if data.caseId ~= nil and data.caseId ~= '' then
        local caseId = int(data.caseId, 1)
        if not caseId then return err('bad_args', 'Bad case number') end
        filter.caseRef = { type = 'case', id = tostring(caseId) }
    end
    if data.kind ~= nil and data.kind ~= '' then
        if type(data.kind) ~= 'string' or #data.kind > 24 or not data.kind:match('^[%w_]+$') then return err('bad_args', 'Bad kind') end
        filter.kind = data.kind
    end
    if data.state ~= nil and data.state ~= '' then
        if type(data.state) ~= 'string' or #data.state > 16 or not data.state:match('^[%a_]+$') then return err('bad_args', 'Bad state') end
        filter.state = data.state
    end
    if data.mine == true then
        local a = actorOf(src)
        if not a then return err('no_access', 'Police only') end
        filter.holder = { ref = 'player:' .. a.cid }
    elseif data.holderKind ~= nil and data.holderKind ~= '' then
        if type(data.holderKind) ~= 'string' or #data.holderKind > 12 or not data.holderKind:match('^[%a_]+$') then return err('bad_args', 'Bad holder') end
        filter.holder = { kind = data.holderKind }
    end
    if data.after ~= nil then
        filter.after = int(data.after, 1)
        if not filter.after then return err('bad_args', 'Bad page') end
    end
    return owner('pfm-policejob', 'ListEvidence', filter)
end

function X.EvidenceGet(src, data)
    local id = evidenceId(type(data) == 'table' and data.id or nil)
    if not id then return err('bad_args', 'Unknown evidence') end
    return owner('pfm-policejob', 'GetEvidence', id, { viewer = src })
end

function X.EvidenceTransfer(src, data)
    if type(data) ~= 'table' or type(data.to) ~= 'table' then return err('bad_args', 'Bad request') end
    if not Access.AllowRate(src, 'pages:evidenceWrite', X.Cfg().WriteRateMs) then return err('rate_limited', 'Slow down') end
    local id = int(data.id, 1)
    if not id then return err('bad_args', 'Unknown evidence') end
    local kind = data.to.kind
    if not X.TransferKinds[kind] then return err('bad_args', 'Hand it to a lab, a locker or a court') end
    local to = { kind = kind }
    if kind == 'lab' then
        to.labId = type(data.to.labId) == 'string' and data.to.labId:match('^[%w_]+$') and data.to.labId:sub(1, 32) or 'main'
    elseif kind == 'court' then
        local caseId = type(data.to.caseId) == 'string' and data.to.caseId:match('^[%w_%-:]+$') and data.to.caseId or nil
        if not caseId or #caseId > 48 then return err('bad_args', 'Enter the court case id') end
        to.caseId = caseId
    else
        local lockerId = int(data.to.lockerId, 1)
        if not lockerId then return err('bad_args', 'Enter the locker number') end
        to.lockerId = lockerId
    end
    return owner('pfm-policejob', 'TransferEvidence', id, to, { actor = { src = src }, note = text(data.note, 200) })
end

-- ── lab ─────────────────────────────────────────────────────────────────────

--- Evidence held at a lab, newest first, each with its lab jobs (state, ETA, released result).
--- Two owner calls per page: ListEvidence, then one ListLabJobs for the page's ids (the caller is
--- the viewer of both, so pfm-policejob applies its duty and lab-tech rules).
function X.LabQueue(src, data)
    data = type(data) == 'table' and data or {}
    if not Access.AllowRate(src, 'pages:labQueue', X.Cfg().ReadRateMs) then return err('rate_limited', 'Slow down') end
    local filter = { viewer = src, holder = { kind = 'lab' }, limit = X.Cfg().LabPage }
    if data.state ~= nil and data.state ~= '' then
        if data.state ~= 'at_lab' and data.state ~= 'analysed' then return err('bad_args', 'Bad state') end
        filter.state = data.state
    end
    if data.after ~= nil then
        filter.after = int(data.after, 1)
        if not filter.after then return err('bad_args', 'Bad page') end
    end
    local list = owner('pfm-policejob', 'ListEvidence', filter)
    if not list.ok then return list end
    local items, ids = type(list.list) == 'table' and list.list or {}, {}
    for _, item in ipairs(items) do
        local id = int(item.id, 1)
        if id and #ids < 50 then ids[#ids + 1] = id end
    end
    if #ids == 0 then return list end
    local jobs = call('pfm-policejob', 'ListLabJobs', { evidenceIds = ids, viewer = src })
    local byItem = {}
    if type(jobs) == 'table' and jobs.ok then
        for _, j in ipairs(type(jobs.jobs) == 'table' and jobs.jobs or {}) do
            local k = int(j.evidenceId, 1)
            if k then
                byItem[k] = byItem[k] or {}
                byItem[k][#byItem[k] + 1] = j
            end
        end
    end
    for _, item in ipairs(items) do
        if type(jobs) == 'table' and jobs.ok then item.labs = byItem[int(item.id, 1) or 0] or {}
        else item.labsError = 'The lab jobs could not be read' end
    end
    return list
end

function X.LabSubmit(src, data)
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    if not Access.AllowRate(src, 'pages:evidenceWrite', X.Cfg().WriteRateMs) then return err('rate_limited', 'Slow down') end
    local id = int(data.id, 1)
    if not id then return err('bad_args', 'Unknown evidence') end
    if type(data.tests) ~= 'table' then return err('bad_args', 'Pick at least one test') end
    local tests, seen = {}, {}
    for _, t in ipairs(data.tests) do
        if type(t) ~= 'string' or not X.Tests[t] then return err('bad_args', 'Unknown test') end
        if not seen[t] then seen[t] = true tests[#tests + 1] = t end
    end
    if #tests == 0 then return err('bad_args', 'Pick at least one test') end
    return owner('pfm-policejob', 'SubmitToLab', id, tests, { actor = { src = src } })
end

function X.LabRelease(src, data)
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    if not Access.AllowRate(src, 'pages:evidenceWrite', X.Cfg().WriteRateMs) then return err('rate_limited', 'Slow down') end
    local jobId = int(data.jobId, 1)
    if not jobId then return err('bad_args', 'Unknown lab job') end
    return owner('pfm-policejob', 'ReleaseLabResult', jobId, { actor = { src = src }, note = text(data.note, 200) })
end

-- ── telemetry ───────────────────────────────────────────────────────────────

--- One page of an officer's telemetry (own, or another's for a supervisor: pfm-policejob decides).
function X.Timeline(src, data)
    data = type(data) == 'table' and data or {}
    if not Access.AllowRate(src, 'pages:timeline', X.Cfg().ReadRateMs) then return err('rate_limited', 'Slow down') end
    local a = actorOf(src)
    if not a then return err('no_access', 'Police only') end
    local cid = a.cid
    if data.officerCid ~= nil and data.officerCid ~= '' then
        cid = cidOf(data.officerCid)
        if not cid then return err('bad_args', 'Bad officer id') end
    end
    local from, to = int(data.from, 0), int(data.to, 0)
    if not from or not to or to <= from then return err('bad_args', 'Pick a time window') end
    if to - from > X.Cfg().TimelineMaxWindow then return err('bad_args', ('A window covers at most %d hours'):format(X.Cfg().TimelineMaxWindow // 3600)) end
    local after = data.after ~= nil and int(data.after, 0) or nil
    if data.after ~= nil and not after then return err('bad_args', 'Bad page') end
    local res = owner('pfm-policejob', 'GetTimeline', cid, from, to, { viewer = src, after = after, limit = 100 })
    if res.ok then
        res.officerCid, res.from, res.to = cid, from, to
        res.kindNote = 'metadata, not video'
    end
    return res
end

-- ── gate entries and endpoints ──────────────────────────────────────────────

X.Actions = {
    ['pf_mdt:custody:log'] = { action = 'custodyLog' },
    ['pf_mdt:evidence:transfer'] = { action = 'evidenceHandle' },
    ['pf_mdt:lab:submit'] = { action = 'evidenceHandle' },
    ['pf_mdt:lab:release'] = { action = 'labRelease' },
}
Access.RegisterActions(X.Actions)

X.Endpoints = {
    ['pf_mdt:pages:access'] = X.Access,
    ['pf_mdt:custody:get'] = X.CustodyGet,
    ['pf_mdt:custody:history'] = X.CustodyHistory,
    ['pf_mdt:custody:log'] = X.CustodyLog,
    ['pf_mdt:evidence:list'] = X.EvidenceList,
    ['pf_mdt:evidence:get'] = X.EvidenceGet,
    ['pf_mdt:evidence:transfer'] = X.EvidenceTransfer,
    ['pf_mdt:lab:queue'] = X.LabQueue,
    ['pf_mdt:lab:submit'] = X.LabSubmit,
    ['pf_mdt:lab:release'] = X.LabRelease,
    ['pf_mdt:timeline:get'] = X.Timeline,
}

for name, fn in pairs(X.Endpoints) do
    QBCore.Functions.CreateCallback(name, function(source, cb, data)
        local src = tonumber(source)
        local ok, res = pcall(fn, src, data)
        if not ok then
            print(('^1[pf-policemdt]^7 %s failed: %s'):format(name, tostring(res)))
            res = err('unavailable', 'The request failed; read the record again before retrying')
        end
        if Access.Callable(cb) then cb(res) end
    end)
end
