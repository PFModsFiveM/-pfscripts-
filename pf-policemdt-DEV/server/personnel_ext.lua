-- ============================================================================
-- PF Police MDT - personnel extension (batch 20, unit 20F)
-- ============================================================================
-- Owns (tables of server/schema.lua v9):
--   * use-of-force, OIS and pursuit reports drafted from the server telemetry timeline of
--     pfm-policejob (GetTimeline/HoldTimeline, 18C). The automatic part of a report (events, force
--     level, subjects, distance and speeds) is computed here from server rows only; the officer adds
--     the narrative. Rows the timeline marks clientReported are listed apart and never raise the
--     force level. A named tick (AutoDraftTick) drafts a report by itself when an on-duty officer's
--     timeline shows reportable force (tackle, taser, firearm hit);
--   * the review chain: the officer submits, a supervisor of a higher rank approves or returns, and a
--     commander closes. Nobody acts on a report about their own force or about themselves as the
--     subject, and the closer is never the reviewer (two different people sign off);
--   * internal affairs complaints (keyed intake for the citizen records portal of 21F, walk-in
--     complaints taken by an officer, assignment, investigator notes, findings, close). The officer
--     named in a complaint never sees it, and never works it;
--   * performance reviews by supervisors, and the qualification view from pf-government.
-- Every write is gated by server/access.lua (on duty and the action's grade) and audited in
-- pf_mdt_record_audit. Queries use oxmysql's MySQL.*.await inside the handler's thread.
--
-- Endpoints (QBCore callbacks, one table argument; answer { ok, success, ... } or { ok = false, error,
-- message }):
--   pf_mdt:force:draft, :update, :refresh, :submit           forceReports (own reports)
--   pf_mdt:force:review                                      forceReview  (approve | return)
--   pf_mdt:force:close                                       forceClose
--   pf_mdt:force:list, :get                                  reads (own; supervisors all)
--   pf_mdt:ia:file                                           iaIntake (walk-in complaint)
--   pf_mdt:ia:list, :get, :assign, :note, :finding, :close   iaManage
--   pf_mdt:reviews:create                                    perfReview
--   pf_mdt:reviews:list, pf_mdt:personnel:qualifications     reads (own; viewPersonnel for others)
-- Exports: DraftUseOfForce(spec, opts), FileIaComplaint(spec, opts) (caller allowlists below).

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtPersonnel = PFMdtPersonnel or {}
local P = PFMdtPersonnel
local Access = PFMdtAccess
local callable = Access.Callable

-- Grades used when config.lua has no entry (Config.Permissions accepts a plain number for all jobs).
local DEFAULT_GRADES = {
    forceReports = 0,   -- draft, edit, refresh and submit own force/pursuit reports
    forceReview = 2,    -- approve or return a submitted report (plus: a higher rank than the officer)
    forceClose = 3,     -- close a reviewed report
    iaIntake = 0,       -- take a walk-in complaint
    iaManage = 3,       -- internal affairs: read, assign, investigate, decide, close
    perfReview = 2,     -- write performance reviews (lower ranks only)
    viewPersonnel = 2,  -- read another officer's reports, reviews and qualifications
}
Config.Permissions = Config.Permissions or {}
for action, grade in pairs(DEFAULT_GRADES) do
    if Config.Permissions[action] == nil then Config.Permissions[action] = grade end
end

local DEFAULT_CALLERS = {
    DraftUseOfForce = { ['pfm-policejob'] = true, ['pf-justice'] = true },
    FileIaComplaint = { ['pf-justice'] = true, ['pf-citizen'] = true, ['pf-government'] = true },
}

function P.Cfg()
    local c = type(Config.Personnel) == 'table' and Config.Personnel or {}
    return {
        MaxWindowSeconds = tonumber(c.MaxWindowSeconds) or 7200,     -- longest timeline window of one report
        MaxAgeSeconds = tonumber(c.MaxAgeSeconds) or 3 * 86400,      -- how far back a draft may start
        PrePadSeconds = tonumber(c.PrePadSeconds) or 120,            -- auto drafts start this long before the force
        MergeSeconds = tonumber(c.MergeSeconds) or 600,              -- force within this of an open auto draft extends it
        MaxPages = tonumber(c.MaxPages) or 10,                       -- timeline pages (100 rows) read per draft
        AutoDraft = c.AutoDraft ~= false,
        AutoMinLevel = tonumber(c.AutoMinLevel) or 2,                -- tackle 2, taser 3, firearm hit 5
        TickSeconds = tonumber(c.TickSeconds) or 60,
        NarrativeMin = tonumber(c.NarrativeMin) or 20,
        NarrativeMax = tonumber(c.NarrativeMax) or 8000,
        ComplaintMax = tonumber(c.ComplaintMax) or 4000,
        ComplaintsPerDay = tonumber(c.ComplaintsPerDay) or 3,        -- per complainant, portal intake
        ListLimit = tonumber(c.ListLimit) or 50,
        Callers = type(c.Callers) == 'table' and c.Callers or DEFAULT_CALLERS,
    }
end

P.Kinds = { uof = true, pursuit = true, ois = true }
P.States = { draft = true, submitted = true, reviewed = true, returned = true, closed = true }
P.IaStates = { received = true, investigating = true, sustained = true, not_sustained = true, closed = true }
P.IaCategories = { conduct = true, force = true, discourtesy = true, misconduct = true, corruption = true, other = true }
P.ReviewScores = { conduct = true, knowledge = true, reports = true, teamwork = true, initiative = true }

-- Force levels from server-seen timeline rows (0 = listed, no force). Client-reported rows never count.
function P.ForceLevelOf(e)
    if type(e) ~= 'table' or e.clientReported then return 0 end
    local d = type(e.data) == 'table' and e.data or {}
    if e.kind == 'shot_hit' then return 5 end
    if e.kind == 'taser' then return 3 end
    if e.kind == 'use_of_force' then
        if d.action == 'tackle' then return 2 end
        return 1 -- handcuffs, zipties (restraint)
    end
    if e.kind == 'cuff' or e.kind == 'ziptie' then return 1 end
    return 0
end

-- ── helpers ─────────────────────────────────────────────────────────────────

local function now() return os.time() end

local function err(code, message, extra)
    local out = { ok = false, success = false, error = code, message = message or code }
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end
local function okRes(t)
    t = t or {}
    t.ok, t.success = true, true
    return t
end

local function int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n)
    if not n or (min and n < min) or (max and n > max) then return nil end
    return n
end

-- Plain text: control characters become spaces (newlines kept when multiline), trimmed, clipped.
local function text(v, maxLen, multiline)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v)
    if multiline then s = s:gsub('\r\n?', '\n'):gsub('[\0-\9\11-\31\127]', ' ')
    else s = s:gsub('[%c]', ' ') end
    s = s:match('^%s*(.-)%s*$')
    if #s > maxLen then s = s:sub(1, maxLen) end
    return s ~= '' and s or nil
end
P.Text = text

local function cidOf(v)
    if type(v) ~= 'string' or #v < 1 or #v > 64 or not v:match('^[%w_%-]+$') then return nil end
    return v
end
P.CidOf = cidOf

local function keyOf(v)
    if type(v) ~= 'string' or #v < 1 or #v > 128 or not v:match('^[%w%-_:%.]+$') then return nil end
    return v
end

local function db(kind, sql, params)
    local ok, res = pcall(function() return MySQL[kind].await(sql, params or {}) end)
    if not ok then
        print(('^1[pf-policemdt]^7 personnel: query failed: %s'):format(tostring(res)))
        return nil, false
    end
    return res, true
end
local function affected(v)
    if type(v) == 'table' then v = v.affectedRows or v.changedRows end
    return tonumber(v) or 0
end
local function rows(v) return type(v) == 'table' and v or {} end

local function decode(s)
    if type(s) == 'table' then return s end
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

local function charName(charinfo)
    if type(charinfo) == 'string' then charinfo = decode(charinfo) end
    if type(charinfo) ~= 'table' then return nil end
    local name = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):match('^%s*(.-)%s*$')
    return name ~= '' and name:sub(1, 128) or nil
end

local function schemaReady()
    local S = PFMdtSchema
    if type(S) ~= 'table' or not callable(S.Ready) then return true end
    if S.Ready() then return true end
    if S.state == 'running' and callable(S.WaitReady) then return S.WaitReady(15000) == true end
    return false
end

local function started(res) return GetResourceState(res) == 'started' end

-- One call into another resource's export: res, nil on success; nil, 'offline' | 'error' otherwise.
local function call(res, name, ...)
    if not started(res) then return nil, 'offline' end
    local n, args = select('#', ...), { ... }
    local ok, out = pcall(function()
        local e = exports[res]
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok then
        print(('^3[pf-policemdt]^7 personnel: %s:%s failed: %s'):format(res, name, tostring(out)))
        return nil, 'error'
    end
    return out, nil
end
P.Call = call

local function notify(src, msg, kind)
    if src and tonumber(src) and tonumber(src) > 0 then TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary') end
end

local function gradeOf(job)
    if type(job) ~= 'table' then return 0 end
    return type(job.grade) == 'table' and (tonumber(job.grade.level) or 0) or (tonumber(job.grade) or 0)
end

--- A citizen by citizen id: online from pfm-core, else the players row.
--- { cid, name, job, grade, online, src } or nil.
function P.Citizen(cid)
    cid = cidOf(cid)
    if not cid then return nil end
    local Pl = QBCore.Functions.GetPlayerByCitizenId(cid)
    if Pl and Pl.PlayerData then
        local job = Pl.PlayerData.job
        return { cid = cid, name = charName(Pl.PlayerData.charinfo) or cid, job = type(job) == 'table' and job.name or nil,
            grade = gradeOf(job), online = true, src = Pl.PlayerData.source, onduty = type(job) == 'table' and job.onduty == true }
    end
    local row = db('single', 'SELECT citizenid, charinfo, job FROM players WHERE citizenid = ? LIMIT 1', { cid })
    if type(row) ~= 'table' or not row.citizenid then return nil end
    local job = decode(row.job)
    return { cid = cid, name = charName(row.charinfo) or cid, job = type(job) == 'table' and job.name or nil,
        grade = gradeOf(job), online = false }
end

local function isOfficerJob(job) return job ~= nil and Config.AllowedJobs and Config.AllowedJobs[job] == true or false end

--- The acting officer from the server's player; nil when not an MDT officer.
function P.Actor(src)
    local job, Pl = Access.Job(src)
    if not job or not Pl or not isOfficerJob(job.name) then return nil end
    local pd = Pl.PlayerData
    return { src = src, cid = pd.citizenid, name = charName(pd.charinfo) or pd.citizenid, job = job.name, grade = job.grade,
        onduty = job.onduty, owner = Access.IsOwner(src), boss = Access.IsBoss(src) }
end

-- True when the actor outranks the officer: a higher grade in the same job, the boss, or the owner
-- flag. A former officer (no MDT job now) has no rank left; another MDT department is never outranked.
local function outranks(actor, officer)
    if actor.owner or actor.boss then return true end
    if not officer then return false end
    if not isOfficerJob(officer.job) then return true end
    if officer.job ~= actor.job then return false end
    return (actor.grade or 0) > (officer.grade or 0)
end
P.Outranks = outranks

-- Per-entity lock, taken before the first database wait of a check-then-write.
local locks = {}
local function withLock(key, fn)
    if locks[key] then return err('busy', 'Someone else is changing this record; try again') end
    locks[key] = true
    local ok, res = pcall(fn)
    locks[key] = nil
    if not ok then
        print(('^1[pf-policemdt]^7 personnel: %s failed: %s'):format(key, tostring(res)))
        return err('db_unavailable', 'The personnel records failed; check the record before trying again')
    end
    return res
end
P.Locks = locks

local function audit(entity, id, action, by, detail)
    local s = json.encode(detail or {})
    if #s > 4096 then s = s:sub(1, 4096) end
    db('insert', 'INSERT INTO pf_mdt_record_audit (entity, entity_id, action, by_cid, by_job, detail, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { entity, tostring(id), action, by and by.cid or 'system', by and by.job or nil, s, now() })
end

local function rate(src, key, ms)
    return Access.AllowRate(src, 'personnel:' .. key, ms)
end

-- ── telemetry: read and summarise (server rows only) ────────────────────────

--- Reads an officer's timeline window through pfm-policejob GetTimeline (the viewer must be the
--- officer or an on-duty LEO supervisor; PJ checks). Returns events, nil, truncated or nil, reason.
function P.ReadTimeline(cid, from, to, viewer)
    local events, after = {}, nil
    for _ = 1, math.max(1, P.Cfg().MaxPages) do
        local res, why = call('pfm-policejob', 'GetTimeline', cid, from, to, { viewer = viewer, after = after, limit = 100 })
        if why then return nil, why == 'offline' and 'telemetry_offline' or 'telemetry_error' end
        if type(res) ~= 'table' then return nil, 'telemetry_error' end
        if not res.ok then return nil, tostring(res.error or 'telemetry_error'):sub(1, 16) end
        for _, e in ipairs(rows(res.events)) do events[#events + 1] = e end
        if not res.next then return events, nil, false end
        after = res.next
    end
    return events, nil, true
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function cidIn(d)
    if type(d) ~= 'table' then return nil end
    return cidOf(d.target) or cidOf(d.subject)
end

--- The automatic part of a report, from timeline rows. Pure: events = GetTimeline rows.
function P.Summarize(events, from, to)
    local s = { from = from, to = to, rows = 0, counts = {}, force = {}, level = 0, subjects = {}, clientReported = 0,
        weapons = {}, plates = {}, pursuit = { distance = 0, seconds = 0, maxSpeed = 0, avgSpeed = 0 }, ois = false }
    local subjects, weapons, plates = {}, {}, {}
    local lastPos, moving = nil, 0
    local sorted = {}
    for _, e in ipairs(type(events) == 'table' and events or {}) do
        if type(e) == 'table' and type(e.kind) == 'string' then sorted[#sorted + 1] = e end
    end
    table.sort(sorted, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
    for _, e in ipairs(sorted) do
        s.rows = s.rows + 1
        local kind = e.kind:sub(1, 16)
        s.counts[kind] = (s.counts[kind] or 0) + 1
        local d = type(e.data) == 'table' and e.data or {}
        local at = tonumber(e.at) or 0
        if e.clientReported then s.clientReported = s.clientReported + 1 end
        local level = P.ForceLevelOf(e)
        if level > s.level then s.level = level end
        if kind == 'shot_hit' and not e.clientReported then s.ois = true end
        local subject = cidIn(d)
        if subject and not subjects[subject] and #s.subjects < 10 then subjects[subject] = true s.subjects[#s.subjects + 1] = subject end
        local w = type(d.weapon) == 'string' and d.weapon:sub(1, 32) or nil
        if w and not weapons[w] and #s.weapons < 10 then weapons[w] = true s.weapons[#s.weapons + 1] = w end
        local plate = type(d.plate) == 'string' and d.plate:sub(1, 8) or nil
        if plate and not plates[plate] and #s.plates < 10 then plates[plate] = true s.plates[#s.plates + 1] = plate end
        if (level > 0 or kind == 'weapon_out' or kind == 'shot_reported' or kind == 'k9' or kind == 'arrest' or kind == 'detain')
            and #s.force < 50 then
            s.force[#s.force + 1] = {
                at = at, kind = kind, level = level, clientReported = e.clientReported == true or nil,
                action = type(d.action) == 'string' and d.action:sub(1, 24) or (type(d.kind) == 'string' and d.kind:sub(1, 24) or nil),
                weapon = w, subject = subject,
                x = e.coords and tonumber(e.coords.x) or nil, y = e.coords and tonumber(e.coords.y) or nil,
            }
        end
        -- pursuit metrics from consecutive server positions (gaps over 60 s and teleports are skipped)
        if e.coords and tonumber(e.coords.x) and tonumber(e.coords.y) and tonumber(e.coords.z) then
            local pos = { x = tonumber(e.coords.x), y = tonumber(e.coords.y), z = tonumber(e.coords.z), at = at }
            if lastPos then
                local dt = pos.at - lastPos.at
                if dt > 0 and dt <= 60 then
                    local m = dist(pos, lastPos)
                    local v = m / dt
                    if v <= 120 then
                        s.pursuit.distance = s.pursuit.distance + m
                        if v >= 2 then moving = moving + dt end
                        if v > s.pursuit.maxSpeed then s.pursuit.maxSpeed = v end
                    end
                end
            end
            lastPos = pos
        end
    end
    if #sorted > 0 then
        s.pursuit.seconds = math.max(0, (tonumber(sorted[#sorted].at) or 0) - (tonumber(sorted[1].at) or 0))
    end
    s.pursuit.distance = math.floor(s.pursuit.distance + 0.5)
    s.pursuit.maxSpeed = math.floor(s.pursuit.maxSpeed * 10 + 0.5) / 10
    s.pursuit.avgSpeed = moving > 0 and math.floor(s.pursuit.distance / moving * 10 + 0.5) / 10 or 0
    s.note = 'Server metadata timeline (positions, actions the server saw). No video exists; rows marked clientReported rest on a client report and do not set the force level.'
    return s
end

local function summaryJson(s)
    local out = json.encode(s)
    -- the force list is the only part that can grow; trim it until the summary fits
    while #out > 60000 and #s.force > 0 do
        s.force[#s.force] = nil
        out = json.encode(s)
    end
    return out
end

-- ── reports ─────────────────────────────────────────────────────────────────

local function publicReport(r)
    if type(r) ~= 'table' then return nil end
    return {
        id = tonumber(r.id), kind = r.kind, officerCid = r.officer_cid, officerName = r.officer_name, subjectCid = r.subject_cid,
        custodyId = tonumber(r.custody_id), forceLevel = tonumber(r.force_level), from = tonumber(r.telemetry_from),
        to = tonumber(r.telemetry_to), telemetry = r.telemetry_state, holdId = tonumber(r.hold_id), summary = decode(r.auto_summary),
        narrative = r.narrative, state = r.state, origin = r.origin, reviewerCid = r.reviewer_cid, closedBy = r.closed_by,
        createdBy = r.created_by, createdAt = tonumber(r.created_at), submittedAt = tonumber(r.submitted_at),
        updatedAt = tonumber(r.updated_at),
    }
end
P.PublicReport = publicReport

local function loadReport(id)
    id = int(id, 1, 2147483647)
    if not id then return nil, err('bad_args', 'Unknown report') end
    local row, ok = db('single', 'SELECT * FROM pf_mdt_force_reports WHERE id = ?', { id })
    if not ok then return nil, err('db_unavailable', 'The report database did not answer') end
    if type(row) ~= 'table' or not row.id then return nil, err('not_found', 'No such report') end
    return row
end
P.LoadReport = loadReport

local function chainStep(reportId, step, by, note)
    db('insert', 'INSERT INTO pf_mdt_force_reviews (report_id, step, by_cid, by_name, by_grade, note, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { reportId, step, by.cid, by.name, by.grade, note, now() })
end

-- Holds the window past telemetry retention (caseRef pf-policemdt:force:<id>); nil when PJ refused.
local function holdWindow(reportId, cid, from, to)
    local res = call('pfm-policejob', 'HoldTimeline', cid, from, to, 'pf-policemdt:force:' .. tostring(reportId))
    if type(res) == 'table' and res.ok then
        local holdId = int(res.holdId, 1)
        if holdId then db('update', 'UPDATE pf_mdt_force_reports SET hold_id = ? WHERE id = ?', { holdId, reportId }) end
        return holdId
    end
    return nil
end

--- Reads the window again into the automatic part (draft or returned reports). `to` may extend the
--- window (auto drafts that see more force); the window never exceeds MaxWindowSeconds.
local function refreshRow(row, viewer, newTo)
    local c = P.Cfg()
    local from, to = tonumber(row.telemetry_from), tonumber(row.telemetry_to)
    if newTo and newTo > to then to = math.min(newTo, from + c.MaxWindowSeconds) end
    local events, why, truncated = P.ReadTimeline(row.officer_cid, from, to, viewer)
    if not events then return nil, why end
    local s = P.Summarize(events, from, to)
    s.truncated = truncated or nil
    local level = math.max(s.level, tonumber(row.force_level) or 0)
    local kind = row.kind
    if kind == 'uof' and s.ois then kind = 'ois' end
    local n = affected(db('update', [[UPDATE pf_mdt_force_reports SET auto_summary = ?, force_level = ?, kind = ?, telemetry_to = ?,
        telemetry_state = ?, updated_at = ? WHERE id = ? AND state IN ('draft', 'returned')]],
        { summaryJson(s), level, kind, to, truncated and 'truncated' or 'ok', now(), row.id }))
    if n == 0 then return nil, 'invalid_state' end
    holdWindow(row.id, row.officer_cid, from, to)
    return s
end

--- Creates a draft from the officer's timeline. spec = { kind?, officerCid, from, to, subjectCid?,
--- custodyId?, forceLevel? (resource callers only) }; ctx = { key?, viewer?, origin, by = { cid, name, job } }.
--- A key that was seen returns the first report (duplicate = true) or key_reused for other arguments.
function P.DraftForce(spec, ctx)
    if type(spec) ~= 'table' or type(ctx) ~= 'table' then return err('bad_args', 'Bad report request') end
    local c = P.Cfg()
    local kind = spec.kind ~= nil and tostring(spec.kind):lower() or nil
    if kind ~= nil and not P.Kinds[kind] then return err('bad_args', 'Kind must be uof, pursuit or ois') end
    local officerCid = cidOf(spec.officerCid)
    if not officerCid then return err('bad_args', 'Officer missing') end
    local t = now()
    local from, to = int(spec.from, 0), int(spec.to, 0)
    if not from or not to or to <= from then return err('bad_args', 'Bad time window') end
    if to > t + 60 then return err('bad_args', 'The window ends in the future') end
    if to > t then to = t end
    if to - from > c.MaxWindowSeconds then return err('bad_args', ('A report covers at most %d minutes'):format(c.MaxWindowSeconds // 60)) end
    if from < t - c.MaxAgeSeconds then return err('bad_args', 'That window is too old to draft from') end
    local subjectCid = spec.subjectCid ~= nil and cidOf(spec.subjectCid) or nil
    if spec.subjectCid ~= nil and spec.subjectCid ~= '' and not subjectCid then return err('bad_args', 'Bad subject') end
    if subjectCid == officerCid then return err('bad_args', 'The officer cannot be the subject') end
    local custodyId = spec.custodyId ~= nil and int(spec.custodyId, 1) or nil
    local key = ctx.key ~= nil and keyOf(ctx.key) or nil
    if ctx.key ~= nil and not key then return err('bad_args', 'Bad key') end
    local by = type(ctx.by) == 'table' and ctx.by or { cid = 'system' }
    local origin = ctx.origin == 'auto' and 'auto' or (ctx.origin == 'resource' and 'resource' or 'officer')
    local extraLevel = origin == 'resource' and int(spec.forceLevel, 0, 5) or nil
    if not schemaReady() then return err('db_unavailable', 'The MDT database is not ready') end
    return withLock('draft:' .. (key or officerCid), function()
        if key then
            local ex, okq = db('single', 'SELECT id, officer_cid, telemetry_from, telemetry_to FROM pf_mdt_force_reports WHERE idem_key = ? LIMIT 1', { key })
            if not okq then return err('db_unavailable', 'The report database did not answer') end
            if type(ex) == 'table' and ex.id then
                if ex.officer_cid ~= officerCid or tonumber(ex.telemetry_from) ~= from then
                    return err('key_reused', 'That key belongs to another report')
                end
                return okRes({ reportId = tonumber(ex.id), duplicate = true })
            end
        end
        local officer = P.Citizen(officerCid)
        if not officer or not isOfficerJob(officer.job) then return err('not_found', 'No such officer') end
        local events, why, truncated = P.ReadTimeline(officerCid, from, to, ctx.viewer)
        local s = P.Summarize(events or {}, from, to)
        s.truncated = truncated or nil
        local state = why and ('unavailable:' .. why) or (truncated and 'truncated' or 'ok')
        local level = math.max(s.level, extraLevel or 0)
        if not kind then kind = s.ois and 'ois' or 'uof' end
        if kind == 'uof' and s.ois then kind = 'ois' end
        if not subjectCid and #s.subjects == 1 then subjectCid = s.subjects[1] end
        local id, okIns = db('insert', [[INSERT INTO pf_mdt_force_reports (kind, officer_cid, officer_name, subject_cid, custody_id,
            force_level, telemetry_from, telemetry_to, telemetry_state, auto_summary, narrative, state, origin, idem_key, created_by,
            created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 'draft', ?, ?, ?, ?, ?)]],
            { kind, officerCid, officer.name, subjectCid, custodyId, level, from, to, state:sub(1, 32), summaryJson(s), origin, key,
                by.cid or 'system', t, t })
        id = int(id, 1)
        if not okIns or not id then return err('db_unavailable', 'The report was not saved') end
        local holdId = not why and holdWindow(id, officerCid, from, to) or nil
        audit('force_report', id, 'create', by, { kind = kind, officer = officerCid, from = from, to = to, telemetry = state,
            origin = origin, key = key, invoker = ctx.invoker })
        return okRes({ reportId = id, kind = kind, forceLevel = level, telemetry = state, holdId = holdId })
    end)
end

-- The report's officer, a supervisor who outranks them, or nobody.
local function canSee(actor, row)
    if row.officer_cid == actor.cid then return true end
    return Access.Rank(actor.src, 'viewPersonnel') == true
end

local function needActor(src)
    local a = P.Actor(src)
    if not a then return nil, err('no_access', 'Police only') end
    if not schemaReady() then return nil, err('db_unavailable', 'The MDT database is not ready') end
    return a
end

function P.MdtDraft(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad report request') end
    if not rate(src, 'draft', 3000) then return err('rate_limited', 'Slow down') end
    local officerCid = data.officerCid ~= nil and cidOf(data.officerCid) or a.cid
    if not officerCid then return err('bad_args', 'Bad officer') end
    if officerCid ~= a.cid then
        -- drafting for another officer: a supervisor who outranks them
        if not Access.Rank(src, 'forceReview') then return err('no_permission', 'Only a supervisor drafts for another officer') end
        if not outranks(a, P.Citizen(officerCid)) then return err('no_permission', 'You do not outrank that officer') end
    end
    local t = now()
    local from, to
    local minutes = int(data.minutes, 1, P.Cfg().MaxWindowSeconds // 60)
    if minutes then
        from, to = t - minutes * 60, t
    else
        from, to = int(data.from, 0), int(data.to, 0)
    end
    if not from or not to then return err('bad_args', 'Give minutes or a from/to window') end
    local kind = data.kind ~= nil and tostring(data.kind):lower() or 'uof'
    if not P.Kinds[kind] then return err('bad_args', 'Kind must be uof, pursuit or ois') end
    -- a double click with the same window and kind finds the first draft
    local key = ('pf-policemdt:force:mdt:%s:%d:%d:%s'):format(officerCid, from, to, kind)
    local res = P.DraftForce({ kind = kind, officerCid = officerCid, from = from, to = to, subjectCid = data.subjectCid,
        custodyId = data.custodyId }, { key = key, viewer = src, origin = 'officer', by = a })
    if res.ok and officerCid ~= a.cid then
        local o = P.Citizen(officerCid)
        if o and o.online then notify(o.src, ('A supervisor drafted report #%d from your timeline'):format(res.reportId), 'primary') end
    end
    return res
end

function P.MdtList(src, data)
    local a, e = needActor(src)
    if not a then return e end
    data = type(data) == 'table' and data or {}
    local officerCid = data.officerCid ~= nil and cidOf(data.officerCid) or nil
    local state = data.state ~= nil and tostring(data.state) or nil
    if state and not P.States[state] then return err('bad_args', 'Bad state') end
    local all = Access.Rank(src, 'viewPersonnel') == true
    if not all then
        if officerCid and officerCid ~= a.cid then return err('no_permission', 'You may list your own reports') end
        officerCid = a.cid
    end
    local where, params = {}, {}
    if officerCid then where[#where + 1] = 'officer_cid = ?' params[#params + 1] = officerCid end
    if state then where[#where + 1] = 'state = ?' params[#params + 1] = state end
    local sql = 'SELECT id, kind, officer_cid, officer_name, subject_cid, force_level, state, origin, telemetry_state, reviewer_cid, created_at, updated_at FROM pf_mdt_force_reports'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    local list, ok = db('query', sql .. ' ORDER BY id DESC LIMIT ' .. math.floor(P.Cfg().ListLimit), params)
    if not ok then return err('db_unavailable', 'The report database did not answer') end
    local out = {}
    for _, r in ipairs(rows(list)) do
        out[#out + 1] = { id = tonumber(r.id), kind = r.kind, officerCid = r.officer_cid, officerName = r.officer_name,
            subjectCid = r.subject_cid, forceLevel = tonumber(r.force_level), state = r.state, origin = r.origin,
            telemetry = r.telemetry_state, reviewerCid = r.reviewer_cid, createdAt = tonumber(r.created_at), updatedAt = tonumber(r.updated_at) }
    end
    return okRes({ list = out })
end

function P.MdtGet(src, data)
    local a, e = needActor(src)
    if not a then return e end
    local row, e2 = loadReport(type(data) == 'table' and data.id or data)
    if not row then return e2 end
    if not canSee(a, row) then return err('not_found', 'No such report') end
    local chain = rows(db('query', 'SELECT step, by_cid, by_name, by_grade, note, at FROM pf_mdt_force_reviews WHERE report_id = ? ORDER BY id', { row.id }))
    local out = {}
    for _, r in ipairs(chain) do
        out[#out + 1] = { step = r.step, byCid = r.by_cid, byName = r.by_name, byGrade = tonumber(r.by_grade), note = r.note, at = tonumber(r.at) }
    end
    return okRes({ report = publicReport(row), chain = out })
end

local EDITABLE = { draft = true, returned = true }

function P.MdtUpdate(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    if not rate(src, 'update', 1000) then return err('rate_limited', 'Slow down') end
    local id = int(data.id, 1, 2147483647)
    if not id then return err('bad_args', 'Unknown report') end
    local c = P.Cfg()
    local narrative = data.narrative ~= nil and text(data.narrative, c.NarrativeMax, true) or nil
    local subjectCid = data.subjectCid ~= nil and data.subjectCid ~= '' and cidOf(data.subjectCid) or nil
    if data.subjectCid ~= nil and data.subjectCid ~= '' and not subjectCid then return err('bad_args', 'Bad subject') end
    local custodyId = data.custodyId ~= nil and int(data.custodyId, 1) or nil
    return withLock('report:' .. id, function()
        local row, e2 = loadReport(id)
        if not row then return e2 end
        if row.officer_cid ~= a.cid then return err('no_permission', 'Only the officer writes their report') end
        if not EDITABLE[row.state] then return err('invalid_state', ('The report is %s'):format(row.state)) end
        if subjectCid == row.officer_cid then return err('bad_args', 'The officer cannot be the subject') end
        local n = affected(db('update', [[UPDATE pf_mdt_force_reports SET narrative = COALESCE(?, narrative), subject_cid = COALESCE(?, subject_cid),
            custody_id = COALESCE(?, custody_id), updated_at = ? WHERE id = ? AND state IN ('draft', 'returned')]],
            { narrative, subjectCid, custodyId, now(), id }))
        if n == 0 then return err('invalid_state', 'The report changed; reload it') end
        audit('force_report', id, 'update', a, { narrative = narrative and #narrative or nil, subject = subjectCid, custody = custodyId })
        return okRes({ reportId = id })
    end)
end

function P.MdtRefresh(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if not rate(src, 'refresh', 3000) then return err('rate_limited', 'Slow down') end
    local id = int(type(data) == 'table' and data.id or data, 1, 2147483647)
    if not id then return err('bad_args', 'Unknown report') end
    return withLock('report:' .. id, function()
        local row, e2 = loadReport(id)
        if not row then return e2 end
        if row.officer_cid ~= a.cid and not (Access.Rank(src, 'forceReview') and outranks(a, P.Citizen(row.officer_cid))) then
            return err('no_permission', 'Not your report')
        end
        if not EDITABLE[row.state] then return err('invalid_state', ('The report is %s'):format(row.state)) end
        local s, why = refreshRow(row, src)
        if not s then return err(why == 'invalid_state' and 'invalid_state' or 'unavailable', 'The timeline could not be read: ' .. tostring(why)) end
        audit('force_report', id, 'update', a, { refreshed = true, rows = s.rows })
        return okRes({ reportId = id, forceLevel = math.max(s.level, tonumber(row.force_level) or 0) })
    end)
end

function P.MdtSubmit(src, data)
    local a, e = needActor(src)
    if not a then return e end
    local id = int(type(data) == 'table' and data.id or data, 1, 2147483647)
    if not id then return err('bad_args', 'Unknown report') end
    return withLock('report:' .. id, function()
        local row, e2 = loadReport(id)
        if not row then return e2 end
        if row.officer_cid ~= a.cid then return err('no_permission', 'Only the officer submits their report') end
        if not EDITABLE[row.state] then return err('invalid_state', ('The report is %s'):format(row.state)) end
        if #(row.narrative or '') < P.Cfg().NarrativeMin then return err('bad_args', 'Write the narrative first') end
        local t = now()
        local n = affected(db('update', [[UPDATE pf_mdt_force_reports SET state = 'submitted', submitted_at = ?, updated_at = ?
            WHERE id = ? AND state IN ('draft', 'returned')]], { t, t, id }))
        if n == 0 then return err('invalid_state', 'The report changed; reload it') end
        chainStep(id, 'submit', a, nil)
        audit('force_report', id, 'status', a, { state = 'submitted' })
        return okRes({ reportId = id, state = 'submitted' })
    end)
end

--- A supervisor approves ('reviewed') or returns ('returned', a note is required) a submitted report.
--- Never the officer of the report, never its subject, and only someone who outranks the officer.
function P.MdtReview(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    local id = int(data.id, 1, 2147483647)
    local decision = tostring(data.decision or ''):lower()
    if not id or (decision ~= 'approve' and decision ~= 'return') then return err('bad_args', 'Decision must be approve or return') end
    local note = text(data.note, 1000, true)
    if decision == 'return' and not note then return err('bad_args', 'Say what must change') end
    return withLock('report:' .. id, function()
        local row, e2 = loadReport(id)
        if not row then return e2 end
        if row.officer_cid == a.cid or row.subject_cid == a.cid then return err('no_permission', 'You cannot review a report about yourself') end
        if row.state ~= 'submitted' then return err('invalid_state', ('The report is %s'):format(row.state)) end
        if not outranks(a, P.Citizen(row.officer_cid)) then return err('no_permission', 'You do not outrank the officer') end
        local newState = decision == 'approve' and 'reviewed' or 'returned'
        local n = affected(db('update', "UPDATE pf_mdt_force_reports SET state = ?, reviewer_cid = ?, updated_at = ? WHERE id = ? AND state = 'submitted'",
            { newState, a.cid, now(), id }))
        if n == 0 then return err('invalid_state', 'The report changed; reload it') end
        chainStep(id, decision, a, note)
        audit('force_report', id, 'status', a, { state = newState, note = note })
        local o = P.Citizen(row.officer_cid)
        if o and o.online then
            notify(o.src, decision == 'approve' and ('Your report #%d was approved'):format(id)
                or ('Your report #%d was returned: %s'):format(id, note), decision == 'approve' and 'success' or 'error')
        end
        return okRes({ reportId = id, state = newState })
    end)
end

--- A commander closes a reviewed report: not the officer, not the subject, not the reviewer.
function P.MdtClose(src, data)
    local a, e = needActor(src)
    if not a then return e end
    local id = int(type(data) == 'table' and data.id or data, 1, 2147483647)
    if not id then return err('bad_args', 'Unknown report') end
    local note = type(data) == 'table' and text(data.note, 1000, true) or nil
    return withLock('report:' .. id, function()
        local row, e2 = loadReport(id)
        if not row then return e2 end
        if row.officer_cid == a.cid or row.subject_cid == a.cid then return err('no_permission', 'You cannot close a report about yourself') end
        if row.state ~= 'reviewed' then return err('invalid_state', ('The report is %s'):format(row.state)) end
        if row.reviewer_cid == a.cid then return err('no_permission', 'A second supervisor closes the report') end
        if not outranks(a, P.Citizen(row.officer_cid)) then return err('no_permission', 'You do not outrank the officer') end
        local n = affected(db('update', "UPDATE pf_mdt_force_reports SET state = 'closed', closed_by = ?, updated_at = ? WHERE id = ? AND state = 'reviewed'",
            { a.cid, now(), id }))
        if n == 0 then return err('invalid_state', 'The report changed; reload it') end
        chainStep(id, 'close', a, note)
        audit('force_report', id, 'status', a, { state = 'closed', note = note })
        return okRes({ reportId = id, state = 'closed' })
    end)
end

-- ── automatic drafts (named tick; the thread below runs it) ─────────────────

P.Cursor = P.Cursor or {} -- [cid] = { after = last timeline id seen, at = last read }

local function onDutyOfficers()
    local out = {}
    for _, Pl in pairs(QBCore.Functions.GetQBPlayers() or {}) do
        local pd = Pl and Pl.PlayerData
        local job = pd and pd.job
        if job and isOfficerJob(job.name) and job.onduty and pd.citizenid then out[#out + 1] = { src = pd.source, cid = pd.citizenid } end
    end
    return out
end

--- Extends this officer's open auto draft when the new force is within MergeSeconds of its window,
--- else drafts a new report keyed on the first force row. Returns the report id or nil.
function P.AutoDraftFor(src, cid, firstAt, firstId, t)
    local c = P.Cfg()
    local open = db('single', [[SELECT * FROM pf_mdt_force_reports WHERE officer_cid = ? AND origin = 'auto' AND state = 'draft'
        AND telemetry_to >= ? ORDER BY id DESC LIMIT 1]], { cid, firstAt - c.MergeSeconds })
    if type(open) == 'table' and open.id and t - tonumber(open.telemetry_from) <= c.MaxWindowSeconds then
        local res = withLock('report:' .. open.id, function()
            local s = refreshRow(open, src, t)
            return s and okRes({ reportId = tonumber(open.id) }) or err('unavailable')
        end)
        return res.ok and tonumber(open.id) or nil
    end
    local res = P.DraftForce({ officerCid = cid, from = math.max(firstAt - c.PrePadSeconds, t - c.MaxWindowSeconds + 1), to = t },
        { key = ('pf-policemdt:force:auto:%s:%d'):format(cid, firstId), viewer = src, origin = 'auto', by = { cid = 'system', job = 'auto' } })
    if res.ok and not res.duplicate then
        notify(src, ('Use-of-force report #%d was drafted from your telemetry. Complete it in the MDT.'):format(res.reportId), 'primary')
    end
    return res.ok and res.reportId or nil
end

--- One pass: reads the new rows of every on-duty officer's timeline (the officer is the viewer) and
--- drafts or extends a report when they show force of AutoMinLevel or more. Returns drafts touched.
function P.AutoDraftTick()
    local c = P.Cfg()
    if not c.AutoDraft or not started('pfm-policejob') then return 0 end
    if type(PFMdtSchema) == 'table' and callable(PFMdtSchema.Ready) and not PFMdtSchema.Ready() then return 0 end
    local t, touched, seen = now(), 0, {}
    for _, o in ipairs(onDutyOfficers()) do
        seen[o.cid] = true
        local cur = P.Cursor[o.cid]
        if not cur then
            cur = { after = 0, at = t - c.TickSeconds }
            P.Cursor[o.cid] = cur
        end
        -- rows are flushed by GetTimeline before it reads; 60 s of slack covers a row stamped late
        local from = math.max(cur.at - 60, t - c.MaxWindowSeconds + 1)
        local firstAt, firstId, lastId, pages = nil, nil, cur.after, 0
        repeat
            pages = pages + 1
            local res = call('pfm-policejob', 'GetTimeline', o.cid, from, t, { viewer = o.src, after = lastId, limit = 100 })
            if type(res) ~= 'table' or not res.ok then break end
            for _, e in ipairs(rows(res.events)) do
                local id = tonumber(e.id) or 0
                if id > lastId then lastId = id end
                if not firstId and P.ForceLevelOf(e) >= c.AutoMinLevel then firstAt, firstId = tonumber(e.at) or t, id end
            end
            if not res.next then break end
        until pages >= c.MaxPages
        cur.after, cur.at = lastId, t
        if firstId then
            if P.AutoDraftFor(o.src, o.cid, firstAt, firstId, t) then touched = touched + 1 end
        end
    end
    for cid in pairs(P.Cursor) do
        if not seen[cid] then P.Cursor[cid] = nil end
    end
    return touched
end

-- ── internal affairs ────────────────────────────────────────────────────────

local function publicComplaint(r)
    if type(r) ~= 'table' then return nil end
    return {
        id = tonumber(r.id), complainantCid = r.complainant_cid, complainantName = r.complainant_name, officerCid = r.officer_cid,
        officerName = r.officer_name, category = r.category, channel = r.channel, incidentRef = r.incident_ref, summary = r.summary,
        state = r.state, investigatorCid = r.investigator_cid, outcome = r.outcome, takenBy = r.taken_by,
        createdAt = tonumber(r.created_at), updatedAt = tonumber(r.updated_at),
    }
end
P.PublicComplaint = publicComplaint

local function iaEvent(id, action, by, note)
    db('insert', 'INSERT INTO pf_mdt_ia_events (complaint_id, action, by_cid, note, at) VALUES (?, ?, ?, ?, ?)',
        { id, action, by and by.cid or 'system', note, now() })
end

--- Files a complaint. spec = { complainantCid?, complainantName?, officerCid?, officerName?, category?,
--- summary, incidentRef? }; ctx = { key?, channel = 'portal' | 'officer', by = { cid, job } }.
function P.FileComplaint(spec, ctx)
    if type(spec) ~= 'table' or type(ctx) ~= 'table' then return err('bad_args', 'Bad complaint') end
    local c = P.Cfg()
    local summary = text(spec.summary, c.ComplaintMax, true)
    if not summary or #summary < 10 then return err('bad_args', 'Describe what happened') end
    local complainantCid = spec.complainantCid ~= nil and spec.complainantCid ~= '' and cidOf(spec.complainantCid) or nil
    if spec.complainantCid ~= nil and spec.complainantCid ~= '' and not complainantCid then return err('bad_args', 'Bad complainant') end
    local officerCid = spec.officerCid ~= nil and spec.officerCid ~= '' and cidOf(spec.officerCid) or nil
    if spec.officerCid ~= nil and spec.officerCid ~= '' and not officerCid then return err('bad_args', 'Bad officer') end
    local officerName = text(spec.officerName, 128)
    if not officerCid and not officerName then return err('bad_args', 'Name the officer (citizen id, name or callsign)') end
    local category = spec.category ~= nil and tostring(spec.category):lower() or 'conduct'
    if not P.IaCategories[category] then return err('bad_args', 'Unknown category') end
    local incidentRef = spec.incidentRef ~= nil and spec.incidentRef ~= '' and text(spec.incidentRef, 64) or nil
    local key = ctx.key ~= nil and keyOf(ctx.key) or nil
    if ctx.key ~= nil and not key then return err('bad_args', 'Bad key') end
    local channel = ctx.channel == 'portal' and 'portal' or 'officer'
    local by = type(ctx.by) == 'table' and ctx.by or { cid = 'system' }
    if not schemaReady() then return err('db_unavailable', 'The MDT database is not ready') end
    return withLock('iafile:' .. (key or complainantCid or by.cid or 'system'), function()
        if key then
            local ex, okq = db('single', 'SELECT id, complainant_cid, officer_cid FROM pf_mdt_ia_complaints WHERE idem_key = ? LIMIT 1', { key })
            if not okq then return err('db_unavailable', 'The complaint database did not answer') end
            if type(ex) == 'table' and ex.id then
                if (ex.complainant_cid or '') ~= (complainantCid or '') or (ex.officer_cid or '') ~= (officerCid or '') then
                    return err('key_reused', 'That key belongs to another complaint')
                end
                return okRes({ complaintId = tonumber(ex.id), duplicate = true })
            end
        end
        local complainant = complainantCid and P.Citizen(complainantCid) or nil
        if complainantCid and not complainant then return err('not_found', 'No such complainant') end
        if channel == 'portal' then
            if not complainantCid then return err('bad_args', 'The complainant is required') end
            local today = tonumber((db('scalar', 'SELECT COUNT(*) FROM pf_mdt_ia_complaints WHERE complainant_cid = ? AND created_at >= ?',
                { complainantCid, now() - 86400 }))) or 0
            if today >= c.ComplaintsPerDay then return err('rate_limited', 'Too many complaints today; IA will contact you') end
        end
        local officer = officerCid and P.Citizen(officerCid) or nil
        if officerCid and not officer then return err('not_found', 'No such officer') end
        if officer and not officerName then officerName = officer.name end
        if officerCid and officerCid == by.cid then return err('conflict', 'Another officer must take a complaint about you') end
        local t = now()
        local id, okIns = db('insert', [[INSERT INTO pf_mdt_ia_complaints (complainant_cid, complainant_name, officer_cid, officer_name, category,
            channel, incident_ref, summary, state, taken_by, idem_key, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'received', ?, ?, ?, ?)]],
            { complainantCid, complainant and complainant.name or text(spec.complainantName, 128), officerCid, officerName, category, channel,
                incidentRef, summary, channel == 'officer' and by.cid or nil, key, t, t })
        id = int(id, 1)
        if not okIns or not id then return err('db_unavailable', 'The complaint was not saved') end
        iaEvent(id, 'received', by, channel)
        audit('ia_complaint', id, 'create', by, { channel = channel, category = category, key = key })
        return okRes({ complaintId = id, state = 'received' })
    end)
end

local function loadComplaint(id)
    id = int(id, 1, 2147483647)
    if not id then return nil, err('bad_args', 'Unknown complaint') end
    local row, ok = db('single', 'SELECT * FROM pf_mdt_ia_complaints WHERE id = ?', { id })
    if not ok then return nil, err('db_unavailable', 'The complaint database did not answer') end
    if type(row) ~= 'table' or not row.id then return nil, err('not_found', 'No such complaint') end
    return row
end

-- IA staff only, and never the officer the complaint names (they read 'not found', as for any id).
local function iaRow(a, id)
    local row, e = loadComplaint(id)
    if not row then return nil, e end
    if row.officer_cid and row.officer_cid == a.cid then return nil, err('not_found', 'No such complaint') end
    return row
end

function P.MdtFileComplaint(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad complaint') end
    if not rate(src, 'ia_file', 5000) then return err('rate_limited', 'Slow down') end
    -- an optional nonce from the page makes a double submit find the first complaint
    local nonce = type(data.nonce) == 'string' and data.nonce:match('^[%w%-]+$') and #data.nonce <= 40 and data.nonce or nil
    return P.FileComplaint(data, { key = nonce and ('pf-policemdt:ia:mdt:%s:%s'):format(a.cid, nonce) or nil, channel = 'officer', by = a })
end

function P.MdtListComplaints(src, data)
    local a, e = needActor(src)
    if not a then return e end
    data = type(data) == 'table' and data or {}
    local state = data.state ~= nil and tostring(data.state) or nil
    if state and not P.IaStates[state] then return err('bad_args', 'Bad state') end
    local officerCid = data.officerCid ~= nil and cidOf(data.officerCid) or nil
    if officerCid == a.cid then return okRes({ list = {} }) end
    local where, params = { '(officer_cid IS NULL OR officer_cid <> ?)' }, { a.cid }
    if state then where[#where + 1] = 'state = ?' params[#params + 1] = state end
    if officerCid then where[#where + 1] = 'officer_cid = ?' params[#params + 1] = officerCid end
    local list, ok = db('query', 'SELECT * FROM pf_mdt_ia_complaints WHERE ' .. table.concat(where, ' AND ')
        .. ' ORDER BY id DESC LIMIT ' .. math.floor(P.Cfg().ListLimit), params)
    if not ok then return err('db_unavailable', 'The complaint database did not answer') end
    local out = {}
    for _, r in ipairs(rows(list)) do out[#out + 1] = publicComplaint(r) end
    return okRes({ list = out })
end

function P.MdtGetComplaint(src, data)
    local a, e = needActor(src)
    if not a then return e end
    local row, e2 = iaRow(a, type(data) == 'table' and data.id or data)
    if not row then return e2 end
    audit('ia_complaint', row.id, 'read', a, nil)
    local ev = rows(db('query', 'SELECT action, by_cid, note, at FROM pf_mdt_ia_events WHERE complaint_id = ? ORDER BY id', { row.id }))
    local events = {}
    for _, r in ipairs(ev) do events[#events + 1] = { action = r.action, byCid = r.by_cid, note = r.note, at = tonumber(r.at) } end
    return okRes({ complaint = publicComplaint(row), events = events })
end

function P.MdtAssignComplaint(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    local id = int(data.id, 1, 2147483647)
    if not id then return err('bad_args', 'Unknown complaint') end
    local invCid = data.investigatorCid ~= nil and cidOf(data.investigatorCid) or a.cid
    if not invCid then return err('bad_args', 'Bad investigator') end
    return withLock('ia:' .. id, function()
        local row, e2 = iaRow(a, id)
        if not row then return e2 end
        if row.state ~= 'received' and row.state ~= 'investigating' then return err('invalid_state', ('The complaint is %s'):format(row.state)) end
        if invCid == row.officer_cid then return err('conflict', 'The officer named cannot investigate it') end
        if invCid ~= a.cid then
            local inv = P.Citizen(invCid)
            if not inv or not isOfficerJob(inv.job) or inv.grade < Access.MinGrade('iaManage', inv.job) then
                return err('bad_args', 'The investigator must be internal affairs staff')
            end
        end
        local n = affected(db('update', [[UPDATE pf_mdt_ia_complaints SET state = 'investigating', investigator_cid = ?, updated_at = ?
            WHERE id = ? AND state IN ('received', 'investigating')]], { invCid, now(), id }))
        if n == 0 then return err('invalid_state', 'The complaint changed; reload it') end
        iaEvent(id, 'assigned', a, invCid)
        audit('ia_complaint', id, 'status', a, { state = 'investigating', investigator = invCid })
        return okRes({ complaintId = id, state = 'investigating' })
    end)
end

function P.MdtComplaintNote(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    if not rate(src, 'ia_note', 1000) then return err('rate_limited', 'Slow down') end
    local note = text(data.note, 1000, true)
    if not note then return err('bad_args', 'The note is empty') end
    local row, e2 = iaRow(a, data.id)
    if not row then return e2 end
    if row.state ~= 'investigating' then return err('invalid_state', ('The complaint is %s'):format(row.state)) end
    iaEvent(row.id, 'note', a, note)
    db('update', 'UPDATE pf_mdt_ia_complaints SET updated_at = ? WHERE id = ?', { now(), row.id })
    return okRes({ complaintId = tonumber(row.id) })
end

function P.MdtComplaintFinding(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    local id = int(data.id, 1, 2147483647)
    local finding = tostring(data.finding or '')
    if not id or (finding ~= 'sustained' and finding ~= 'not_sustained') then return err('bad_args', 'Finding must be sustained or not_sustained') end
    local outcome = text(data.outcome, 255)
    if not outcome then return err('bad_args', 'State the outcome') end
    return withLock('ia:' .. id, function()
        local row, e2 = iaRow(a, id)
        if not row then return e2 end
        if row.state ~= 'investigating' then return err('invalid_state', ('The complaint is %s'):format(row.state)) end
        local n = affected(db('update', "UPDATE pf_mdt_ia_complaints SET state = ?, outcome = ?, updated_at = ? WHERE id = ? AND state = 'investigating'",
            { finding, outcome, now(), id }))
        if n == 0 then return err('invalid_state', 'The complaint changed; reload it') end
        iaEvent(id, finding, a, outcome)
        audit('ia_complaint', id, 'status', a, { state = finding })
        return okRes({ complaintId = id, state = finding })
    end)
end

function P.MdtCloseComplaint(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad request') end
    local id = int(data.id, 1, 2147483647)
    if not id then return err('bad_args', 'Unknown complaint') end
    local outcome = text(data.outcome, 255)
    return withLock('ia:' .. id, function()
        local row, e2 = iaRow(a, id)
        if not row then return e2 end
        local closable = { received = true, sustained = true, not_sustained = true }
        if not closable[row.state] then return err('invalid_state', ('The complaint is %s'):format(row.state)) end
        -- closing an uninvestigated complaint dismisses it: the reason is required
        if row.state == 'received' and not outcome then return err('bad_args', 'Say why it is dismissed') end
        local n = affected(db('update', [[UPDATE pf_mdt_ia_complaints SET state = 'closed', outcome = COALESCE(?, outcome), updated_at = ?
            WHERE id = ? AND state IN ('received', 'sustained', 'not_sustained')]], { outcome, now(), id }))
        if n == 0 then return err('invalid_state', 'The complaint changed; reload it') end
        iaEvent(id, 'closed', a, outcome)
        audit('ia_complaint', id, 'status', a, { state = 'closed', from = row.state })
        return okRes({ complaintId = id, state = 'closed' })
    end)
end

-- ── performance reviews and qualifications ──────────────────────────────────

function P.MdtCreateReview(src, data)
    local a, e = needActor(src)
    if not a then return e end
    if type(data) ~= 'table' then return err('bad_args', 'Bad review') end
    if not rate(src, 'review', 2000) then return err('rate_limited', 'Slow down') end
    local officerCid = cidOf(data.officerCid)
    if not officerCid then return err('bad_args', 'Bad officer') end
    if officerCid == a.cid then return err('no_permission', 'You cannot review yourself') end
    local period = type(data.period) == 'string' and data.period:upper() or ''
    if not (period:match('^%d%d%d%d%-%d%d$') or period:match('^%d%d%d%d%-Q[1-4]$')) then return err('bad_args', 'Period is YYYY-MM or YYYY-Qn') end
    local scores, n = {}, 0
    for k, v in pairs(type(data.scores) == 'table' and data.scores or {}) do
        local s = int(v, 1, 5)
        if not P.ReviewScores[k] or not s then return err('bad_args', 'Scores are 1-5 for conduct, knowledge, reports, teamwork, initiative') end
        scores[k] = s
        n = n + 1
    end
    if n == 0 then return err('bad_args', 'Give at least one score') end
    local notes = text(data.notes, 4000, true)
    local officer = P.Citizen(officerCid)
    if not officer or not isOfficerJob(officer.job) then return err('not_found', 'No such officer') end
    if not outranks(a, officer) then return err('no_permission', 'You review lower ranks only') end
    local id, ok = db('insert', [[INSERT IGNORE INTO pf_mdt_reviews (officer_cid, reviewer_cid, reviewer_name, period, scores, notes, at)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], { officerCid, a.cid, a.name, period, json.encode(scores), notes, now() })
    if not ok then return err('db_unavailable', 'The review was not saved') end
    id = int(id, 1)
    if not id then return err('conflict', 'You already reviewed this officer for that period') end
    audit('perf_review', id, 'create', a, { officer = officerCid, period = period })
    return okRes({ reviewId = id })
end

-- Own records, or another officer's with viewPersonnel.
local function mayView(a, cid)
    return cid == a.cid or Access.Rank(a.src, 'viewPersonnel') == true
end

function P.MdtListReviews(src, data)
    local a, e = needActor(src)
    if not a then return e end
    local cid = cidOf(type(data) == 'table' and data.officerCid or nil) or a.cid
    if not mayView(a, cid) then return err('no_permission', 'You may read your own reviews') end
    local list, ok = db('query', 'SELECT id, officer_cid, reviewer_cid, reviewer_name, period, scores, notes, at FROM pf_mdt_reviews WHERE officer_cid = ? ORDER BY id DESC LIMIT 50', { cid })
    if not ok then return err('db_unavailable', 'The review database did not answer') end
    local out = {}
    for _, r in ipairs(rows(list)) do
        out[#out + 1] = { id = tonumber(r.id), officerCid = r.officer_cid, reviewerCid = r.reviewer_cid, reviewerName = r.reviewer_name,
            period = r.period, scores = decode(r.scores) or {}, notes = r.notes, at = tonumber(r.at) }
    end
    return okRes({ list = out })
end

--- The officer's qualifications as pf-government sees them (granted and implied, with expiry).
function P.Qualifications(cid)
    local res, why = call('pf-government', 'ListQualifications', cid)
    if why or type(res) ~= 'table' then return err('unavailable', 'Department records are not available') end
    if not res.ok then return err(tostring(res.error or 'unavailable'), res.message) end
    return okRes({ list = rows(res.list), dept = res.dept })
end

function P.MdtQualifications(src, data)
    local a, e = needActor(src)
    if not a then return e end
    local cid = cidOf(type(data) == 'table' and data.officerCid or nil) or a.cid
    if not mayView(a, cid) then return err('no_permission', 'You may read your own qualifications') end
    return P.Qualifications(cid)
end

--- For the officer profile (server/officers.lua): reports by state and the latest ones, reviews,
--- qualifications, and IA counts for IA staff who are not the officer.
function P.ProfileSummary(src, cid)
    cid = cidOf(cid)
    local a = P.Actor(src)
    if not cid or not a or not schemaReady() or not mayView(a, cid) then return nil end
    local out = { force = { counts = {}, recent = {} }, reviews = {} }
    for _, r in ipairs(rows(db('query', 'SELECT state, COUNT(*) AS n FROM pf_mdt_force_reports WHERE officer_cid = ? GROUP BY state', { cid }))) do
        out.force.counts[r.state] = tonumber(r.n) or 0
    end
    for _, r in ipairs(rows(db('query', 'SELECT id, kind, force_level, state, created_at FROM pf_mdt_force_reports WHERE officer_cid = ? ORDER BY id DESC LIMIT 10', { cid }))) do
        out.force.recent[#out.force.recent + 1] = { id = tonumber(r.id), kind = r.kind, forceLevel = tonumber(r.force_level), state = r.state, createdAt = tonumber(r.created_at) }
    end
    for _, r in ipairs(rows(db('query', 'SELECT period, scores, reviewer_name, at FROM pf_mdt_reviews WHERE officer_cid = ? ORDER BY id DESC LIMIT 5', { cid }))) do
        out.reviews[#out.reviews + 1] = { period = r.period, scores = decode(r.scores) or {}, reviewerName = r.reviewer_name, at = tonumber(r.at) }
    end
    local q = P.Qualifications(cid)
    out.qualifications = q.ok and q.list or nil
    if cid ~= a.cid and a.onduty and Access.Rank(src, 'iaManage') then
        out.ia = { open = 0, sustained = 0 }
        for _, r in ipairs(rows(db('query', 'SELECT state, COUNT(*) AS n FROM pf_mdt_ia_complaints WHERE officer_cid = ? GROUP BY state', { cid }))) do
            local k = (r.state == 'received' or r.state == 'investigating') and 'open' or (r.state == 'sustained' and 'sustained' or nil)
            if k then out.ia[k] = out.ia[k] + (tonumber(r.n) or 0) end
        end
    end
    return out
end

-- ── gate entries and endpoints ──────────────────────────────────────────────

local ACTIONS = {
    ['pf_mdt:force:draft'] = { action = 'forceReports' },
    ['pf_mdt:force:update'] = { action = 'forceReports' },
    ['pf_mdt:force:refresh'] = { action = 'forceReports' },
    ['pf_mdt:force:submit'] = { action = 'forceReports' },
    ['pf_mdt:force:review'] = { action = 'forceReview' },
    ['pf_mdt:force:close'] = { action = 'forceClose' },
    ['pf_mdt:ia:file'] = { action = 'iaIntake' },
    ['pf_mdt:ia:list'] = { action = 'iaManage' },
    ['pf_mdt:ia:get'] = { action = 'iaManage' },
    ['pf_mdt:ia:assign'] = { action = 'iaManage' },
    ['pf_mdt:ia:note'] = { action = 'iaManage' },
    ['pf_mdt:ia:finding'] = { action = 'iaManage' },
    ['pf_mdt:ia:close'] = { action = 'iaManage' },
    ['pf_mdt:reviews:create'] = { action = 'perfReview' },
}
P.Actions = ACTIONS
Access.RegisterActions(ACTIONS)

local function endpoint(name, fn)
    QBCore.Functions.CreateCallback(name, function(source, cb, data)
        local ok, res = pcall(fn, source, data)
        if not ok then
            print(('^1[pf-policemdt]^7 %s failed: %s'):format(name, tostring(res)))
            res = err('db_unavailable', 'The personnel records failed')
        end
        if callable(cb) then cb(res) end
    end)
end

endpoint('pf_mdt:force:draft', P.MdtDraft)
endpoint('pf_mdt:force:list', P.MdtList)
endpoint('pf_mdt:force:get', P.MdtGet)
endpoint('pf_mdt:force:update', P.MdtUpdate)
endpoint('pf_mdt:force:refresh', P.MdtRefresh)
endpoint('pf_mdt:force:submit', P.MdtSubmit)
endpoint('pf_mdt:force:review', P.MdtReview)
endpoint('pf_mdt:force:close', P.MdtClose)
endpoint('pf_mdt:ia:file', P.MdtFileComplaint)
endpoint('pf_mdt:ia:list', P.MdtListComplaints)
endpoint('pf_mdt:ia:get', P.MdtGetComplaint)
endpoint('pf_mdt:ia:assign', P.MdtAssignComplaint)
endpoint('pf_mdt:ia:note', P.MdtComplaintNote)
endpoint('pf_mdt:ia:finding', P.MdtComplaintFinding)
endpoint('pf_mdt:ia:close', P.MdtCloseComplaint)
endpoint('pf_mdt:reviews:create', P.MdtCreateReview)
endpoint('pf_mdt:reviews:list', P.MdtListReviews)
endpoint('pf_mdt:personnel:qualifications', P.MdtQualifications)

-- ── exports (server-to-server) ──────────────────────────────────────────────

local deniedAt = {}
local function invokerAllowed(name)
    local inv = GetInvokingResource()
    if inv == nil or inv == GetCurrentResourceName() then return true, inv end
    local list = P.Cfg().Callers[name]
    if list == '*' or (type(list) == 'table' and list[inv] == true) then return true, inv end
    if not deniedAt[inv .. name] or now() - deniedAt[inv .. name] >= 60 then
        deniedAt[inv .. name] = now()
        print(('^3[pf-policemdt]^7 %s is not allowed to call %s'):format(inv, name))
    end
    return false, inv
end

--- DraftUseOfForce(spec, opts): spec = { kind? = 'uof'|'pursuit'|'ois', officerCid, from, to, subjectCid?,
--- custodyId?, forceLevel? }; opts = { key (required), actor = { src }? }. The timeline is read with
--- the actor (an officer or supervisor PJ re-checks) or, without one, the officer while online.
--- Returns { ok, reportId, telemetry, duplicate? }. The force level is never below what the timeline shows.
exports('DraftUseOfForce', function(spec, opts)
    local allowed, inv = invokerAllowed('DraftUseOfForce')
    if not allowed then return err('not_allowed') end
    opts = type(opts) == 'table' and opts or {}
    if not keyOf(opts.key) then return err('bad_args', 'opts.key is required') end
    local viewer = type(opts.actor) == 'table' and int(opts.actor.src, 1) or nil
    if not viewer and type(spec) == 'table' then
        local o = P.Citizen(spec.officerCid)
        viewer = o and o.online and o.src or nil
    end
    local ok, res = pcall(P.DraftForce, spec, { key = opts.key, viewer = viewer, origin = 'resource',
        by = { cid = 'resource:' .. tostring(inv or 'self'), job = tostring(inv or 'self') }, invoker = inv })
    if not ok then
        print(('^1[pf-policemdt]^7 DraftUseOfForce failed: %s'):format(tostring(res)))
        return err('db_unavailable')
    end
    if res.ok and not res.duplicate then
        local o = P.Citizen(spec.officerCid)
        if o and o.online then notify(o.src, ('Report #%d was drafted from your telemetry. Complete it in the MDT.'):format(res.reportId), 'primary') end
    end
    return res
end)

--- FileIaComplaint(spec, opts): citizen intake (records portal). spec = { complainantCid, officerCid?,
--- officerName?, category?, summary, incidentRef? }; opts = { key (required), actor = { src }? }. With
--- an actor the complainant is the actor's own character (read on the server).
exports('FileIaComplaint', function(spec, opts)
    local allowed, inv = invokerAllowed('FileIaComplaint')
    if not allowed then return err('not_allowed') end
    opts = type(opts) == 'table' and opts or {}
    if not keyOf(opts.key) or type(spec) ~= 'table' then return err('bad_args', 'opts.key is required') end
    local actorSrc = type(opts.actor) == 'table' and int(opts.actor.src, 1) or nil
    local s = {}
    for k, v in pairs(spec) do s[k] = v end
    if actorSrc then
        local Pl = QBCore.Functions.GetPlayer(actorSrc)
        if not Pl or not Pl.PlayerData then return err('offline', 'The complainant is not online') end
        s.complainantCid = Pl.PlayerData.citizenid
    end
    local ok, res = pcall(P.FileComplaint, s, { key = opts.key, channel = 'portal',
        by = { cid = s.complainantCid or ('resource:' .. tostring(inv)), job = tostring(inv or 'self') } })
    if not ok then
        print(('^1[pf-policemdt]^7 FileIaComplaint failed: %s'):format(tostring(res)))
        return err('db_unavailable')
    end
    return res
end)

-- ── the automatic draft thread ──────────────────────────────────────────────

CreateThread(function()
    Wait(5000)
    while true do
        local ok, e = pcall(P.AutoDraftTick)
        if not ok then print('^1[pf-policemdt]^7 auto use-of-force drafts failed: ' .. tostring(e)) end
        Wait(math.max(15, P.Cfg().TickSeconds) * 1000)
    end
end)
