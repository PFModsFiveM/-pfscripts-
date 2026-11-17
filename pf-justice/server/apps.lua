-- pf-justice apps on pf-devices (batch 21, unit 21F): one module per app, the same on the tablet and the
-- computer (html/apps/court.js, cs.js, records.js; styles html/apps/justice.css).
--
--   court               judges, clerks, prosecutors, defenders (Config.Courts.Roles, on duty), probation
--                       officers (Config.Supervision.OfficerJobs) and the police the warrant fallback may let
--                       decide: docket, cases, hearings, decisions, warrant reviews, court orders, supervision.
--   community-service   citizens with a community-service order (shift, work, task) and supervisors
--                       (Config.CommunityService.SupervisorJobs + GOV 'cs_supervisor'): board, sign-off, orders.
--   justice-records     every citizen: own record, court dates, sentence clock, fines (PayOrder), IA complaints.
--
-- Every handler re-reads the player (job, grade, duty) on the server and calls the existing module function
-- (Courts, Warrants, Supervision, CS, Orders, Records) with actor = { src }: those functions do the real role
-- checks, locks, keys and money; the checks here only decide what to read and refuse early. Idempotency keys
-- are made on the server: forms ask for one with `key` (bound to the player and the form) and send it back,
-- so a retry after a lost answer is the same action; a payment's key comes from the order's attempt counter.

PFJustice = PFJustice or {}
PFJustice.Apps = PFJustice.Apps or {}
local J = PFJustice
local A = J.Apps
local U = J.Util
local Err = J.Result.Err

A.IDS = { court = 'court', cs = 'community-service', records = 'justice-records' }
A.PAGE = 25

local function cfg(key, default)
    local c = Config and Config.JusticeApps
    local v = type(c) == 'table' and c[key] or nil
    if v == nil then return default end
    return v
end

-- ── players and roles ───────────────────────────────────────────────────────────────────────────

--- The actor spec handed to the module functions: admins (Config.AdminAces) act as admins (every court role).
function A.ActorSpec(src)
    if J.Actor.IsAdmin(src) then return { src = src, kind = 'admin' } end
    return { src = src }
end

--- The resolved actor of a player (fresh from pfm-core), or nil when they are not online.
function A.Actor(src)
    local actor = J.Actor.Resolve(A.ActorSpec(src))
    return actor
end

local function fallbackPolice(actor)
    local fb = (Config.Courts or {}).WarrantFallback or {}
    if not fb.Enabled or type(actor) ~= 'table' or actor.kind ~= 'player' then return false end
    local min = (fb.PoliceJobs or {})[actor.job or '']
    return min ~= nil and (tonumber(actor.grade) or 0) >= tonumber(min)
end

--- The roles the Court app offers, from the server's own role rules (never a client value).
function A.CourtRoles(actor)
    local C = J.Courts
    local r = {}
    for _, role in ipairs({ 'judge', 'clerk', 'prosecutor', 'defender' }) do r[role] = C.HasRole(actor, role) end
    r.probation = J.Supervision ~= nil and J.Supervision.IsOfficer(actor) or false
    r.warrants = r.judge or (actor.onduty == true and fallbackPolice(actor))
    r.admin = actor.kind == 'admin'
    r.court = r.judge or r.clerk or r.prosecutor or r.defender
    return r
end

--- Whether the player's job would hold a court or probation role on duty (shown as "go on duty").
local function offDutyRoles(actor)
    if type(actor) ~= 'table' or actor.kind ~= 'player' or actor.onduty then return false end
    local copy = {}
    for k, v in pairs(actor) do copy[k] = v end
    copy.onduty = true
    local r = A.CourtRoles(copy)
    return r.court or r.probation or r.warrants
end

-- pf-devices access rule of the Court app: a job that can hold a court role, a probation officer's job, the
-- police the warrant fallback names, or an admin (duty is checked per action, so off-duty staff see why).
function A.CourtAccess(src)
    local actor = A.Actor(src)
    if not actor then return false end
    if actor.kind == 'admin' then return true end
    local r = A.CourtRoles(actor)
    return r.court or r.probation or r.warrants or offDutyRoles(actor)
end

local function csJob(src)
    local P = J.GetPlayer(src)
    local job = P and P.PlayerData.job
    if type(job) ~= 'table' then return false end
    local min = ((Config.CommunityService or {}).SupervisorJobs or { doj = 3, government = 0 })[job.name or '']
    local grade = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade) or 0
    return min ~= nil and grade >= (tonumber(min) or 0)
end

A.csAccess = A.csAccess or {}   -- [cid] = { at, has } (open community-service orders, cached 60 s)

--- Whether the citizen has an open community-service order (cached briefly: pf-devices asks on every call).
function A.HasCsOrder(cid, now)
    now = now or os.time()
    local c = A.csAccess[cid]
    if c and now - c.at < 60 then return c.has end
    local rows = J.CS and J.CS.OpenOrders and J.CS.OpenOrders(cid)
    local has = type(rows) == 'table' and #rows > 0
    A.csAccess[cid] = { at = now, has = has }
    return has
end

function A.CsAccess(src)
    if csJob(src) then return true end
    local P = J.GetPlayer(src)
    return P ~= nil and A.HasCsOrder(P.PlayerData.citizenid)
end

-- ── server-made idempotency keys ────────────────────────────────────────────────────────────────

A.keys = A.keys or {}       -- [src] = { cid, list = { key... }, [key] = scope } (a new character on the id starts empty)
local SCOPES = { decision = true, hearing = true, file = true, courtorder = true, appointment = true, violation = true, ia = true }
local MAX_KEYS = 30

--- A new key for one form submission of `src`. It stays valid for retries until 30 newer keys exist.
function A.IssueKey(src, scope)
    if not SCOPES[scope] then return nil end
    local P = J.GetPlayer(src)
    local cid = P and P.PlayerData.citizenid
    if not cid then return nil end
    local b = A.keys[src]
    if not b or b.cid ~= cid then b = { cid = cid, list = {} } A.keys[src] = b end
    local key = ('pf-justice:app:%s:%x%06x%04x'):format(scope, math.floor(os.time()), math.random(0, 0xffffff), tonumber(src) % 0x10000)
    b[key] = scope
    b.list[#b.list + 1] = key
    while #b.list > MAX_KEYS do
        b[table.remove(b.list, 1)] = nil
    end
    return key
end

--- The key when this player was given it for this form, else nil.
function A.TakeKey(src, scope, key)
    local b = A.keys[src]
    local P = J.GetPlayer(src)
    if type(key) ~= 'string' or not b or not P or b.cid ~= P.PlayerData.citizenid then return nil end
    if b[key] ~= scope or not U.ValidKey(key) then return nil end
    return key
end

local function needKey(src, scope, payload)
    local key = A.TakeKey(src, scope, payload.key)
    if not key then return nil, Err('bad_key', 'This form expired; open it again') end
    return key
end

-- ── small helpers ───────────────────────────────────────────────────────────────────────────────

--- Display names of citizens from the players table (charinfo), { [cid] = 'First Last' }.
function A.Names(cids)
    local list, seen = {}, {}
    for _, cid in ipairs(cids or {}) do
        if U.ValidCid(cid) and not seen[cid] and #list < 100 then seen[cid] = true list[#list + 1] = cid end
    end
    local out = {}
    if #list == 0 then return out end
    local sql = 'SELECT citizenid, charinfo FROM players WHERE citizenid IN (' .. string.rep('?', #list, ', ') .. ')'
    local ok, rows = pcall(MySQL.query.await, sql, list)
    if not ok or type(rows) ~= 'table' then return out end
    for _, r in ipairs(rows) do
        local ci = U.Decode(r.charinfo) or {}
        local name = U.Str(('%s %s'):format(tostring(ci.firstname or ''), tostring(ci.lastname or '')), 64)
        if name and r.citizenid then out[r.citizenid] = name end
    end
    return out
end

local function push(t, ...)
    for i = 1, select('#', ...) do t[#t + 1] = (select(i, ...)) end
end

local function many(sql, params)
    local ok, rows = pcall(MySQL.query.await, sql, params or {})
    if not ok then print(('^1[pf-justice]^7 apps query failed: %s'):format(tostring(rows))) end
    if not ok or type(rows) ~= 'table' then return nil end
    return rows
end

--- page (1-based) and offset from a payload; one extra row tells whether there is a next page.
local function paging(payload)
    local page = U.Int(payload.page or 1, 1, 1000) or 1
    return page, (page - 1) * A.PAGE
end

local function trimPage(rows)
    local more = #rows > A.PAGE
    if more then rows[#rows] = nil end
    return more
end

--- LIKE-safe search text (letters, digits, spaces, - ' . _), 2..40 characters.
local function searchText(v)
    local s = U.Str(v, 40)
    if not s or #s < 2 or s:find("[^%w%s%-'%._]") then return nil end
    return (s:gsub('[%%_\\]', '\\%0'))
end

local function courtroomLabel(id)
    for _, r in ipairs((Config.Courts or {}).Courtrooms or {}) do
        if r.id == id then return r.label end
    end
    return id
end

local function ready() return J.Ready() end
local function notReady() return Err('db_unavailable', 'The justice database is not ready') end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════
-- Court app
-- ═════════════════════════════════════════════════════════════════════════════════════════════════

A.Court = {}
local Court = A.Court

A.SQL = {
    casesBase = [[SELECT id, case_no, citizenid, state, kind, filed_at, closed_at, judge_cid, prosecutor_cid, defender_cid
        FROM pf_justice_cases]],
    reviewsOpen = [[SELECT * FROM pf_justice_warrant_reviews WHERE state = ? ORDER BY requested_at ASC, id ASC LIMIT ? OFFSET ?]],
    reviewsDone = [[SELECT * FROM pf_justice_warrant_reviews WHERE state = ? ORDER BY decided_at DESC, id DESC LIMIT ? OFFSET ?]],
    courtOrdersActive = [[SELECT id, ref, kind, citizenid, case_id, body, judge_cid, valid_until, revoked_at, at FROM pf_justice_court_orders
        WHERE revoked_at IS NULL AND (valid_until IS NULL OR valid_until > ?) ORDER BY id DESC LIMIT ? OFFSET ?]],
    courtOrdersAll = [[SELECT id, ref, kind, citizenid, case_id, body, judge_cid, valid_until, revoked_at, at FROM pf_justice_court_orders
        ORDER BY id DESC LIMIT ? OFFSET ?]],
    caseloadBase = [[SELECT s.id, s.order_id, s.citizenid, s.officer_cid, s.state, s.next_checkin_at, s.created_at,
        (s.monitor IS NOT NULL) AS monitored, o.kind, o.ends_at
        FROM pf_justice_supervision s JOIN pf_justice_orders o ON o.id = s.order_id
        WHERE s.state IN ('pending', 'active', 'suspended')]],
    csBoard = [[SELECT s.id, s.order_id, s.citizenid, s.site, s.supervisor_cid, s.started_at, o.units, o.units_done, o.due_at,
        o.state AS order_state, t.kind AS task_kind, t.steps_done, t.steps_needed
        FROM pf_justice_cs_shifts s JOIN pf_justice_orders o ON o.id = s.order_id
        LEFT JOIN pf_justice_cs_tasks t ON t.shift_id = s.id AND t.state = 'active'
        WHERE s.ended_at IS NULL ORDER BY s.started_at ASC, s.id ASC LIMIT ? OFFSET ?]],
    csOrders = [[SELECT id, citizenid, units, units_done, due_at, state, created_at FROM pf_justice_orders
        WHERE kind = 'community_service' AND state IN (%s) ORDER BY due_at ASC, id ASC LIMIT ? OFFSET ?]],
    myHearings = [[SELECT h.id, h.case_id, h.kind, h.courtroom, h.at, h.state, c.case_no FROM pf_justice_hearings h
        JOIN pf_justice_cases c ON c.id = h.case_id WHERE c.citizenid = ? AND h.state = 'scheduled' AND h.at >= ?
        ORDER BY h.at ASC LIMIT 20]],
    myCases = 'SELECT id, case_no, state, kind, filed_at, closed_at FROM pf_justice_cases WHERE citizenid = ? ORDER BY id DESC LIMIT 50',
    citations = 'SELECT order_id, violation, plate, contest_until FROM pf_justice_citations WHERE order_id IN (%s)',
    namesLike = [[SELECT citizenid FROM players
        WHERE CONCAT_WS(' ', JSON_VALUE(charinfo, '$.firstname'), JSON_VALUE(charinfo, '$.lastname')) LIKE ? LIMIT 50]],
}
local SQL = A.SQL

--- The court actor of a request; with `roles`, one of them is required (the module function checks again).
local function courtActor(src, roles)
    if not ready() then return nil, notReady() end
    local actor = A.Actor(src)
    if not actor then return nil, Err('offline', 'Player not found') end
    if roles and not J.Courts.AnyRole(actor, roles) then return nil, J.Courts.RoleErr(actor, roles) end
    return actor
end

local HEARING_KINDS = { 'arraignment', 'bail', 'trial', 'sentencing', 'violation', 'appeal' }
local DECISION_KINDS = { 'plea', 'verdict', 'sentence', 'dismissal', 'bail', 'release_order', 'appeal' }
local SENTENCE_KINDS = { 'jail', 'prison', 'fine', 'restitution', 'community_service', 'probation', 'parole' }
local CASE_KINDS = { criminal = true, violation = true, citation_contest = true, appeal = true }

local function sortedKeys(t)
    local out = {}
    for k, v in pairs(t or {}) do if v then out[#out + 1] = k end end
    table.sort(out)
    return out
end

--- Who the player is to the court and the lists the forms offer (all from the server's config).
function Court.Me(src)
    local actor, err = courtActor(src)
    if not actor then return err end
    local roles = A.CourtRoles(actor)
    local facilities = {}
    for id, f in pairs(Config.Facilities or {}) do
        facilities[#facilities + 1] = { id = id, label = f.label or id, kinds = sortedKeys(f.kinds) }
    end
    table.sort(facilities, function(a, b) return a.id < b.id end)
    local courtrooms = {}
    for _, r in ipairs((Config.Courts or {}).Courtrooms or {}) do courtrooms[#courtrooms + 1] = { id = r.id, label = r.label or r.id } end
    local offices = {}
    for i, o in ipairs((Config.Supervision or {}).Offices or {}) do offices[i] = { id = i, label = o.label } end
    local zones = {}
    for id, z in pairs((Config.Supervision or {}).Zones or {}) do zones[#zones + 1] = { id = id, label = z.label or id } end
    table.sort(zones, function(a, b) return a.id < b.id end)
    local violations = {}
    for id, label in pairs(J.Supervision and J.Supervision.VIOLATION_TYPES or {}) do violations[#violations + 1] = { id = id, label = label } end
    table.sort(violations, function(a, b) return a.id < b.id end)
    return {
        ok = true, roles = roles, offDuty = offDutyRoles(actor), name = actor.name, cid = actor.cid,
        courtrooms = courtrooms, hearingKinds = HEARING_KINDS, decisionKinds = DECISION_KINDS, sentenceKinds = SENTENCE_KINDS,
        courtOrderKinds = sortedKeys((Config.Courts or {}).OrderKinds), facilities = facilities,
        conditionKinds = sortedKeys((Config.Supervision or {}).ConditionKinds), offices = offices, zones = zones,
        violationTypes = violations, maxHearingDays = tonumber((Config.Courts or {}).MaxHearingDaysAhead) or 60,
        maxOrderHours = tonumber((Config.Courts or {}).MaxOrderHours) or 720,
    }
end

--- A key for one form: decision, hearing, file, courtorder, appointment, violation.
function Court.Key(src, payload)
    local actor, err = courtActor(src)
    if not actor then return err end
    if payload.scope == 'ia' then return Err('bad_args', 'Unknown form') end
    local key = A.IssueKey(src, payload.scope)
    if not key then return Err('bad_args', 'Unknown form') end
    return { ok = true, key = key }
end

local COURT_ROLES = { 'judge', 'clerk', 'prosecutor', 'defender' }

--- The docket (hearings by time) with defendant names.
function Court.Docket(src, payload)
    local actor, err = courtActor(src, COURT_ROLES)
    if not actor then return err end
    local now = os.time()
    local filter = {
        from = U.Int(payload.from, 0, now + 400 * 86400) or (now - 3600),
        to = U.Int(payload.to, 0, now + 400 * 86400) or (now + 14 * 86400),
        state = U.Str(payload.state, 12) or 'scheduled', limit = 100,
    }
    local room = U.Str(payload.courtroom, 24)
    if room then filter.courtroom = room end
    local res = J.Courts.ListDocket(filter, {})
    if not res.ok then return res end
    local cids = {}
    for _, h in ipairs(res.list) do cids[#cids + 1] = h.cid end
    local names = A.Names(cids)
    for _, h in ipairs(res.list) do
        h.name = names[h.cid]
        h.courtroomLabel = courtroomLabel(h.courtroom)
    end
    return { ok = true, list = res.list }
end

local CASE_SORTS = { filed_desc = 'filed_at DESC, id DESC', filed_asc = 'filed_at ASC, id ASC', case_no = 'case_no ASC' }

--- Cases, server-paged: scope open | closed | mine | all, kind, search (case number, citizen id or name), sort.
function Court.Cases(src, payload)
    local actor, err = courtActor(src, COURT_ROLES)
    if not actor then return err end
    local page, offset = paging(payload)
    local where, params = {}, {}
    local scope = payload.scope or 'open'
    if scope == 'open' then where[#where + 1] = "state NOT IN ('dismissed', 'acquitted', 'closed')"
    elseif scope == 'closed' then where[#where + 1] = "state IN ('dismissed', 'acquitted', 'closed')"
    elseif scope == 'mine' then
        if not actor.cid then return { ok = true, list = {}, page = page, more = false } end
        where[#where + 1] = '(judge_cid = ? OR prosecutor_cid = ? OR defender_cid = ?)'
        push(params, actor.cid, actor.cid, actor.cid)
    elseif scope ~= 'all' then return Err('bad_args', 'Unknown filter') end
    if payload.kind ~= nil and payload.kind ~= '' then
        if not CASE_KINDS[payload.kind] then return Err('bad_args', 'Unknown case kind') end
        where[#where + 1] = 'kind = ?'
        params[#params + 1] = payload.kind
    end
    if payload.q ~= nil and payload.q ~= '' then
        local q = searchText(payload.q)
        if not q then return Err('bad_search', 'Search with 2 to 40 letters or digits') end
        -- names first, in their own query: the players table may use another collation than ours
        local named = many(SQL.namesLike, { '%' .. q .. '%' }) or {}
        local cond = 'case_no LIKE ? OR citizenid = ?'
        push(params, q .. '%', U.Str(payload.q, 40))
        if #named > 0 then
            cond = cond .. ' OR citizenid IN (' .. string.rep('?', #named, ', ') .. ')'
            for _, r in ipairs(named) do push(params, r.citizenid) end
        end
        where[#where + 1] = '(' .. cond .. ')'
    end
    local order = CASE_SORTS[payload.sort or 'filed_desc']
    if not order then return Err('bad_args', 'Unknown sort') end
    local sql = SQL.casesBase .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '') .. ' ORDER BY ' .. order .. ' LIMIT ? OFFSET ?'
    push(params, A.PAGE + 1, offset)
    local rows = many(sql, params)
    if not rows then return Err('db_unavailable', 'The court database did not answer') end
    local more = trimPage(rows)
    local cids = {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.citizenid end
    local names = A.Names(cids)
    local list = {}
    for i, r in ipairs(rows) do
        list[i] = { id = tonumber(r.id), caseNo = r.case_no, cid = r.citizenid, name = names[r.citizenid], state = r.state, kind = r.kind,
            filedAt = tonumber(r.filed_at), closedAt = tonumber(r.closed_at) }
    end
    return { ok = true, list = list, page = page, more = more }
end

--- One case with its hearings, decisions and references, the parties' names and what this player may do.
function Court.Case(src, payload)
    local actor, err = courtActor(src, COURT_ROLES)
    if not actor then return err end
    local res = J.Courts.GetCase(payload.id)
    if not res.ok then return res end
    local c = res.case
    local names = A.Names({ c.cid, c.prosecutorCid, c.defenderCid, c.judgeCid })
    c.name, c.prosecutorName, c.defenderName, c.judgeName = names[c.cid], names[c.prosecutorCid], names[c.defenderCid], names[c.judgeCid]
    for _, h in ipairs(c.hearings) do h.courtroomLabel = courtroomLabel(h.courtroom) end
    local roles = A.CourtRoles(actor)
    local open = not J.Courts.CASE_TERMINAL[c.state]
    res.can = {
        schedule = open and (roles.judge or roles.clerk),
        decide = open and roles.judge,
        dismiss = open and (roles.judge or roles.prosecutor),
        appeal = c.state == 'sentenced' and (roles.judge or roles.defender),
        courtOrder = roles.judge,
    }
    return res
end

--- Schedules (or reschedules) a hearing: clerk or judge (Courts.ScheduleHearing checks).
function Court.Schedule(src, payload)
    local actor, err = courtActor(src, { 'clerk', 'judge' })
    if not actor then return err end
    local key, kerr = needKey(src, 'hearing', payload)
    if not key then return kerr end
    local spec = { kind = U.Str(payload.kind, 12), at = payload.at, courtroom = U.Str(payload.courtroom, 24), notes = U.Str(payload.notes, 1000) }
    if payload.judgeCid ~= nil and payload.judgeCid ~= '' then spec.judgeCid = payload.judgeCid end
    return J.Courts.ScheduleHearing(payload.caseId, spec, { actor = A.ActorSpec(src), key = key }, {})
end

-- Only plain values of the order fields the 15B validator reads; it validates every value again.
local ORDER_FIELDS = { 'kind', 'minutes', 'amount', 'units', 'days', 'victimCid', 'facility', 'dueAt', 'merge' }

local function plain(v) return type(v) == 'string' and U.Str(v, 64) or (type(v) == 'number' and v == v and v) or nil end

local function cleanConditions(list, max)
    if list == nil then return nil end
    if type(list) ~= 'table' or #list > max then return false end
    local out = {}
    for i, c in ipairs(list) do
        if type(c) ~= 'table' then return false end
        local copy = {}
        for _, k in ipairs({ 'kind', 'everyDays', 'from', 'to', 'zone', 'note' }) do
            local v = c[k]
            if type(v) == 'boolean' then copy[k] = v else copy[k] = plain(v) end
        end
        out[i] = copy
    end
    return out
end

local function cleanSentence(list)
    if type(list) ~= 'table' or #list < 1 or #list > 10 then return nil end
    local out = {}
    for i, o in ipairs(list) do
        if type(o) ~= 'table' then return nil end
        local copy = {}
        for _, k in ipairs(ORDER_FIELDS) do copy[k] = plain(o[k]) end
        local cond = cleanConditions(o.conditions, 20)
        if cond == false then return nil end
        copy.conditions = cond
        out[i] = copy
    end
    return out
end

--- Records a decision (Courts.RecordDecision checks the role per kind: judge; dismissal also a prosecutor;
--- filing an appeal also a defender).
function Court.Decide(src, payload)
    local actor, err = courtActor(src, COURT_ROLES)
    if not actor then return err end
    local key, kerr = needKey(src, 'decision', payload)
    if not key then return kerr end
    local d = type(payload.decision) == 'table' and payload.decision or {}
    local decision = { kind = U.Str(d.kind, 16), note = U.Str(d.note, 1000) }
    if decision.kind == 'plea' then decision.plea = U.Str(d.plea, 12)
    elseif decision.kind == 'verdict' then decision.verdict = U.Str(d.verdict, 12)
    elseif decision.kind == 'sentence' then
        decision.orders = cleanSentence(d.orders)
        if not decision.orders then return Err('bad_args', 'A sentence needs 1 to 10 orders') end
    elseif decision.kind == 'bail' then
        decision.denied = d.denied == true
        if not decision.denied then decision.amount = d.amount end
        local cond = cleanConditions(d.conditions, 10)
        if cond == false then return Err('bad_args', 'Bail conditions are invalid') end
        decision.conditions = cond
    elseif decision.kind == 'release_order' then decision.reason = U.Str(d.reason, 200)
    elseif decision.kind == 'appeal' then decision.outcome = U.Str(d.outcome, 12) end
    return J.Courts.RecordDecision(payload.caseId, decision, { actor = A.ActorSpec(src), key = key }, {})
end

local function cleanCharges(list)
    if type(list) ~= 'table' or #list > 50 then return nil end
    local out = {}
    for i, c in ipairs(list) do
        if type(c) ~= 'table' then return nil end
        out[i] = { code = U.Str(c.code, 24), label = U.Str(c.label, 100), count = U.Int(c.count or 1, 1, 99) or 1, class = U.Str(c.class, 16) }
    end
    return out
end

--- Files a case: prosecutor or clerk (Courts.FileCase checks; the defendant gets the notices).
function Court.File(src, payload)
    local actor, err = courtActor(src, { 'prosecutor', 'clerk', 'judge' })
    if not actor then return err end
    local key, kerr = needKey(src, 'file', payload)
    if not key then return kerr end
    if not U.ValidCid(payload.cid) then return Err('bad_args', 'Enter the citizen id of the defendant') end
    local charges = cleanCharges(payload.charges)
    if not charges then return Err('bad_args', 'Charges are invalid') end
    local spec = { cid = payload.cid, kind = CASE_KINDS[payload.kind] and payload.kind or 'criminal', charges = charges,
        title = U.Str(payload.title, 120), note = U.Str(payload.note, 1000) }
    -- no custody, MDT or evidence links here: those come with the MDT's own hand-over (FileCase from the MDT)
    if J.Courts.HasRole(actor, 'prosecutor') and actor.cid then spec.prosecutorCid = actor.cid end
    return J.Courts.FileCase(spec, { actor = A.ActorSpec(src), key = key }, {})
end

local function reviewPublic(r, actor)
    local pub = J.Warrants.Public(r)
    if pub.state == 'requested' then pub.canDecide = (J.Warrants.MayDecide(actor, r)) == true end
    return pub
end

--- Warrant reviews by state (judges; the police the fallback may let decide read the waiting ones).
function Court.Warrants(src, payload)
    local actor, err = courtActor(src)
    if not actor then return err end
    local roles = A.CourtRoles(actor)
    if not roles.warrants then return J.Courts.RoleErr(actor, { 'judge' }) end
    local state = payload.state or 'requested'
    local STATES = { requested = SQL.reviewsOpen, needs_info = SQL.reviewsOpen, approved = SQL.reviewsDone, denied = SQL.reviewsDone }
    if not STATES[state] then return Err('bad_args', 'Unknown filter') end
    if not roles.judge and state ~= 'requested' then return Err('no_permission', 'Only judges read decided reviews') end
    local page, offset = paging(payload)
    local rows = many(STATES[state], { state, A.PAGE + 1, offset })
    if not rows then return Err('db_unavailable', 'The court database did not answer') end
    local more = trimPage(rows)
    local cids = {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.target_cid cids[#cids + 1] = r.requested_by end
    local names = A.Names(cids)
    local list = {}
    for i, r in ipairs(rows) do
        list[i] = reviewPublic(r, actor)
        list[i].targetName, list[i].requestedByName = names[r.target_cid], names[r.requested_by]
    end
    return { ok = true, list = list, page = page, more = more }
end

--- approve | deny | needs_info (Warrants.Decide checks the judge or the fallback, and needs a note to refuse).
function Court.DecideWarrant(src, payload)
    local actor, err = courtActor(src)
    if not actor then return err end
    return J.Warrants.Decide(payload.reviewId, payload.decision, { actor = A.ActorSpec(src), note = payload.note }, {})
end

--- Court orders, newest first: active or all (judges and clerks).
function Court.CourtOrders(src, payload)
    local actor, err = courtActor(src, { 'judge', 'clerk' })
    if not actor then return err end
    local page, offset = paging(payload)
    local rows
    if payload.scope == 'all' then rows = many(SQL.courtOrdersAll, { A.PAGE + 1, offset })
    else rows = many(SQL.courtOrdersActive, { os.time(), A.PAGE + 1, offset }) end
    if not rows then return Err('db_unavailable', 'The court database did not answer') end
    local more = trimPage(rows)
    local cids = {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.citizenid end
    local names = A.Names(cids)
    local list = {}
    for i, r in ipairs(rows) do
        local body = U.Decode(r.body) or {}
        list[i] = { id = tonumber(r.id), ref = r.ref, kind = r.kind, cid = r.citizenid, name = names[r.citizenid], caseId = tonumber(r.case_id),
            judgeCid = r.judge_cid, validUntil = tonumber(r.valid_until), revokedAt = tonumber(r.revoked_at), at = tonumber(r.at),
            evidenceIds = body.evidenceIds, tags = body.tags, address = body.address, note = body.note, reason = body.reason }
    end
    return { ok = true, list = list, page = page, more = more }
end

local function idList(v, max)
    if v == nil or v == '' then return nil end
    if type(v) == 'string' then
        local out = {}
        for part in v:gmatch('[^,%s]+') do out[#out + 1] = part end
        v = out
    end
    if type(v) ~= 'table' or #v > max then return false end
    local out = {}
    for i, x in ipairs(v) do
        local s = plain(x)
        if s == nil then return false end
        out[i] = tostring(s)
    end
    return out
end

--- Issues a court order: judge (Courts.IssueCourtOrder validates purpose, person, evidence, hours).
function Court.IssueOrder(src, payload)
    local actor, err = courtActor(src, { 'judge' })
    if not actor then return err end
    local key, kerr = needKey(src, 'courtorder', payload)
    if not key then return kerr end
    local evidence, tags = idList(payload.evidenceIds, 50), idList(payload.tags, 50)
    if evidence == false or tags == false then return Err('bad_args', 'Evidence ids or tags are invalid') end
    local spec = { kind = U.Str(payload.kind, 24), hours = payload.hours, evidenceIds = evidence, tags = tags,
        address = U.Str(payload.address, 128), note = U.Str(payload.note, 500) }
    if payload.cid ~= nil and payload.cid ~= '' then spec.cid = payload.cid end
    if payload.caseId ~= nil and payload.caseId ~= '' then spec.caseId = payload.caseId end
    return J.Courts.IssueCourtOrder(spec, { actor = A.ActorSpec(src), key = key }, {})
end

function Court.RevokeOrder(src, payload)
    local actor, err = courtActor(src, { 'judge' })
    if not actor then return err end
    return J.Courts.RevokeCourtOrder(payload.ref, { actor = A.ActorSpec(src), reason = payload.reason }, {})
end

-- ── supervision (probation officers) ──

local function probationActor(src)
    if not ready() then return nil, notReady() end
    local actor = A.Actor(src)
    if not actor then return nil, Err('offline', 'Player not found') end
    if not (J.Supervision and J.Supervision.IsOfficer(actor)) then
        if offDutyRoles(actor) then return nil, Err('not_on_duty', 'You are off duty') end
        return nil, Err('no_permission', 'Only an on-duty probation officer or judge')
    end
    return actor
end

--- The caseload: scope mine | unassigned | all, ordered by the next check-in due.
function Court.Caseload(src, payload)
    local actor, err = probationActor(src)
    if not actor then return err end
    local page, offset = paging(payload)
    local sql, params = SQL.caseloadBase, {}
    if payload.scope == 'mine' then sql = sql .. ' AND s.officer_cid = ?' params[1] = actor.cid or ''
    elseif payload.scope == 'unassigned' then sql = sql .. ' AND s.officer_cid IS NULL'
    elseif payload.scope ~= nil and payload.scope ~= 'all' then return Err('bad_args', 'Unknown filter') end
    sql = sql .. ' ORDER BY (s.next_checkin_at IS NULL), s.next_checkin_at ASC, s.id ASC LIMIT ? OFFSET ?'
    push(params, A.PAGE + 1, offset)
    local rows = many(sql, params)
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local more = trimPage(rows)
    local cids = {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.citizenid end
    local names = A.Names(cids)
    local list = {}
    for i, r in ipairs(rows) do
        list[i] = { id = tonumber(r.id), orderId = tonumber(r.order_id), cid = r.citizenid, name = names[r.citizenid], officerCid = r.officer_cid,
            state = r.state, kind = r.kind, nextCheckinAt = tonumber(r.next_checkin_at), endsAt = tonumber(r.ends_at),
            monitored = tonumber(r.monitored) == 1 or r.monitored == true }
    end
    return { ok = true, list = list, page = page, more = more }
end

--- One citizen's supervision with appointments, check-ins, violation reports and notes (full reader).
function Court.Supervision(src, payload)
    local actor, err = probationActor(src)
    if not actor then return err end
    if not U.ValidCid(payload.cid) then return Err('bad_args', 'Enter a citizen id') end
    local res = J.Supervision.Get(payload.cid, {})
    if res.ok then res.name = A.Names({ payload.cid })[payload.cid] end
    return res
end

function Court.Appointment(src, payload)
    local actor, err = probationActor(src)
    if not actor then return err end
    local key, kerr = needKey(src, 'appointment', payload)
    if not key then return kerr end
    return J.Supervision.Schedule(payload.supId, { at = payload.at, office = payload.office, minutes = payload.minutes,
        note = U.Str(payload.note, 500) }, { actor = A.ActorSpec(src), key = key }, {})
end

function Court.CheckIn(src, payload)
    local actor, err = probationActor(src)
    if not actor then return err end
    return J.Supervision.CheckIn(payload.supId, { actor = A.ActorSpec(src) }, {})
end

function Court.Violation(src, payload)
    local actor, err = probationActor(src)
    if not actor then return err end
    local key, kerr = needKey(src, 'violation', payload)
    if not key then return kerr end
    return J.Supervision.Violation(payload.supId, { kind = U.Str(payload.kind, 24), note = U.Str(payload.note, 500) },
        { actor = A.ActorSpec(src), key = key }, {})
end

--- Fits (mode + a house the citizen owns or a configured zone, curfew times) or removes the monitor.
function Court.Monitor(src, payload)
    local actor, err = probationActor(src)
    if not actor then return err end
    if not U.ValidCid(payload.cid) then return Err('bad_args', 'Enter a citizen id') end
    local monitor = false
    if payload.remove ~= true then
        monitor = { mode = U.Str(payload.mode, 8) or 'track' }
        if payload.house ~= nil and payload.house ~= '' then monitor.house = U.Str(payload.house, 64)
        elseif payload.zone ~= nil and payload.zone ~= '' then monitor.zone = U.Str(payload.zone, 64) end
        if payload.from ~= nil and payload.from ~= '' then monitor.from = U.Str(payload.from, 5) end
        if payload.to ~= nil and payload.to ~= '' then monitor.to = U.Str(payload.to, 5) end
    end
    return J.Supervision.SetMonitor(payload.cid, monitor, { actor = A.ActorSpec(src) }, {})
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════
-- Community Service app
-- ═════════════════════════════════════════════════════════════════════════════════════════════════

A.CSApp = {}
local CSA = A.CSApp

local function csReady()
    if not (J.CS and J.CS.Ready()) then return Err('db_unavailable', 'Community service is not available right now') end
    return nil
end

--- A citizen action of the runtime (the same functions the world prompts use), then the world client is
--- told the new state (markers, site, prompts). One action per second per player, like the net events.
local function citizenAction(src, name, fn)
    local e = csReady()
    if e then return e end
    if not J.Rate.Allow(('csapp:%d:%s'):format(src, name), 1) then return Err('rate_limited', 'One moment') end
    local res = fn()
    if type(res) ~= 'table' then res = Err('db_unavailable', 'Something went wrong; nothing was changed') end
    J.CS.Push(src)
    local P = J.GetPlayer(src)
    if P then A.csAccess[P.PlayerData.citizenid] = nil end
    return res
end

function CSA.Me(src)
    local e = csReady()
    if e then return e end
    local P = J.GetPlayer(src)
    if not P then return Err('offline', 'Player not found') end
    local supervisor = J.CS.IsSupervisor(src)
    local job = P.PlayerData.job or {}
    return { ok = true, supervisor = supervisor, supervisorJob = csJob(src), onduty = job.onduty == true,
        hasOrders = A.HasCsOrder(P.PlayerData.citizenid) }
end

--- The citizen's own state (orders, shift, task, sign-in desks) and order history, all from the server.
function CSA.State(src)
    local e = csReady()
    if e then return e end
    local P = J.GetPlayer(src)
    if not P then return Err('offline', 'Player not found') end
    local state = J.CS.State(src) or { orders = {}, signIns = {} }
    local hist = J.CS.Get(P.PlayerData.citizenid)
    if #state.signIns == 0 then
        for _, p in ipairs(J.CSTasks.SignIns()) do
            local c = p.coords
            if c then state.signIns[#state.signIns + 1] = { id = p.id, label = p.label, x = c.x, y = c.y, z = c.z } end
        end
    end
    return { ok = true, state = state, history = hist.ok and hist.orders or {} }
end

function CSA.StartShift(src) return citizenAction(src, 'start', function() return J.CS.StartShift(src) end) end
function CSA.EndShift(src) return citizenAction(src, 'end', function() return J.CS.EndShift(src) end) end
function CSA.ListWork(src) return citizenAction(src, 'list', function() return J.CS.ListWork(src) end) end
function CSA.Claim(src, payload) return citizenAction(src, 'claim', function() return J.CS.Claim(src, payload.workOrderId) end) end
function CSA.Abandon(src, payload) return citizenAction(src, 'abandon', function() return J.CS.Abandon(src, payload.taskId) end) end
function CSA.Complete(src, payload) return citizenAction(src, 'complete', function() return J.CS.Complete(src, payload.taskId) end) end

local function supervisorOnly(src)
    local e = csReady()
    if e then return e end
    if not J.CS.IsSupervisor(src) then
        return Err('no_permission', 'Only an on-duty community service supervisor (GOV qualification cs_supervisor)')
    end
    return nil
end

--- Every open shift with its order and active task (supervisors).
function CSA.Board(src, payload)
    local e = supervisorOnly(src)
    if e then return e end
    local page, offset = paging(payload)
    local rows = many(SQL.csBoard, { A.PAGE + 1, offset })
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local more = trimPage(rows)
    local cids = {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.citizenid end
    local names = A.Names(cids)
    local list = {}
    for i, r in ipairs(rows) do
        local kind = J.CSTasks.Kind(r.task_kind)
        list[i] = { shiftId = tonumber(r.id), orderId = tonumber(r.order_id), cid = r.citizenid, name = names[r.citizenid], site = r.site,
            supervised = r.supervisor_cid ~= nil, startedAt = tonumber(r.started_at), units = tonumber(r.units), unitsDone = tonumber(r.units_done) or 0,
            dueAt = tonumber(r.due_at), orderState = r.order_state, task = r.task_kind and { kind = r.task_kind, label = kind and kind.label or r.task_kind,
                stepsDone = tonumber(r.steps_done) or 0, stepsNeeded = tonumber(r.steps_needed) or 0 } or nil }
    end
    return { ok = true, list = list, page = page, more = more }
end

--- Signed-in workers standing within the supervising distance (server positions), for the sign-off.
function CSA.Nearby(src)
    local e = supervisorOnly(src)
    if e then return e end
    local me = U.Coords(src)
    if not me then return Err('offline', 'Player not found') end
    local maxD = J.CSTasks.Num('SupervisorDistance', 30.0, 2.0, 200.0)
    local ok, players = pcall(function() return J.QBCore and J.QBCore.Functions.GetQBPlayers() end)
    local list = {}
    for id, P in pairs(ok and type(players) == 'table' and players or {}) do
        local pd = type(P) == 'table' and P.PlayerData
        local tsrc = pd and (tonumber(pd.source) or tonumber(id))
        if tsrc and tsrc ~= src then
            local pos = U.Coords(tsrc)
            local d = pos and U.Dist2D(me, pos)
            if d and d <= maxD then
                local shift = J.CS.OpenShift(pd.citizenid)
                if shift then
                    local ci = pd.charinfo or {}
                    list[#list + 1] = { src = tsrc, name = U.Str(('%s %s'):format(tostring(ci.firstname or ''), tostring(ci.lastname or '')), 64),
                        shiftId = tonumber(shift.id), supervised = shift.supervisor_cid ~= nil, distance = math.floor(d + 0.5) }
                end
            end
        end
        if #list >= 20 then break end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return { ok = true, list = list }
end

--- The sign-off: CS.Verify re-checks the supervisor, the distance and the open shift.
function CSA.Verify(src, payload)
    local e = supervisorOnly(src)
    if e then return e end
    if not J.Rate.Allow(('csapp:%d:verify'):format(src), 2) then return Err('rate_limited', 'One moment') end
    local res = J.CS.Verify(src, payload.target)
    if res.ok then
        local t = U.Src(payload.target)
        if t then
            if not res.duplicate then J.Notify(t, 'A supervisor verified your community service shift', 'success') end
            J.CS.Push(t)
        end
    end
    return res
end

local CS_SCOPES = { open = { 'assigned', 'active', 'overdue' }, overdue = { 'overdue' }, completed = { 'completed' }, vacated = { 'vacated' } }

--- Community-service orders by state, earliest deadline first (supervisors).
function CSA.Orders(src, payload)
    local e = supervisorOnly(src)
    if e then return e end
    local states = CS_SCOPES[payload.scope or 'open']
    if not states then return Err('bad_args', 'Unknown filter') end
    local page, offset = paging(payload)
    local params = {}
    for i, s in ipairs(states) do params[i] = s end
    push(params, A.PAGE + 1, offset)
    local rows = many(SQL.csOrders:format(string.rep('?', #states, ', ')), params)
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local more = trimPage(rows)
    local cids = {}
    for _, r in ipairs(rows) do cids[#cids + 1] = r.citizenid end
    local names = A.Names(cids)
    local list = {}
    for i, r in ipairs(rows) do
        list[i] = { id = tonumber(r.id), cid = r.citizenid, name = names[r.citizenid], units = tonumber(r.units), unitsDone = tonumber(r.units_done) or 0,
            dueAt = tonumber(r.due_at), state = r.state, createdAt = tonumber(r.created_at) }
    end
    return { ok = true, list = list, page = page, more = more }
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════
-- Records portal (every citizen, about themselves only: the cid is read from the source)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════

A.Portal = {}
local Portal = A.Portal

local function citizen(src)
    if not ready() then return nil, notReady() end
    local P = J.GetPlayer(src)
    if not P then return nil, Err('offline', 'Player not found') end
    return P.PlayerData.citizenid
end

--- The citizen's criminal record (expunged entries are never listed).
function Portal.Record(src)
    local cid, err = citizen(src)
    if not cid then return err end
    local res = J.Records.Get(cid, { limit = Config.Records and Config.Records.MaxEntries or 100 }, {})
    if not res.ok then return res end
    local list = {}
    for i, e in ipairs(res.entries) do
        list[i] = { id = e.id, kind = e.kind, summary = e.summary, at = e.at }
    end
    return { ok = true, entries = list }
end

--- Upcoming hearings and the citizen's cases.
function Portal.Court(src)
    local cid, err = citizen(src)
    if not cid then return err end
    local hearings = many(SQL.myHearings, { cid, os.time() - 3600 })
    local cases = many(SQL.myCases, { cid })
    if not hearings or not cases then return Err('db_unavailable', 'The court database did not answer') end
    local h, c = {}, {}
    for i, r in ipairs(hearings) do
        h[i] = { id = tonumber(r.id), caseId = tonumber(r.case_id), caseNo = r.case_no, kind = r.kind, at = tonumber(r.at),
            courtroom = courtroomLabel(r.courtroom) or 'Superior Court' }
    end
    for i, r in ipairs(cases) do
        c[i] = { id = tonumber(r.id), caseNo = r.case_no, state = r.state, kind = r.kind, filedAt = tonumber(r.filed_at), closedAt = tonumber(r.closed_at) }
    end
    return { ok = true, hearings = h, cases = c }
end

--- The one sentence clock (incarceration), supervision and community service of the citizen.
function Portal.Sentence(src)
    local cid, err = citizen(src)
    if not cid then return err end
    local out = { ok = true }
    local inc = J.Orders.GetActiveIncarceration(cid)
    if inc.ok and inc.order then
        local o = inc.order
        local fac = (Config.Facilities or {})[o.facility or '']
        out.incarceration = { orderId = o.id, kind = o.kind, state = o.state, facility = fac and fac.label or o.facility, clock = o.clock,
            remainingSeconds = inc.remainingSeconds, requiredSeconds = o.requiredSeconds,
            servedSeconds = (o.servedSeconds or 0) + (o.creditSeconds or 0) - (o.forfeitSeconds or 0) }
    end
    if J.Supervision then
        local sup = J.Supervision.Get(cid, {})
        if sup.ok and sup.supervision then
            local s = sup.supervision
            -- the citizen sees their terms and dates, not the officer's reports and notes
            s.violations, s.notes = nil, nil
            if type(s.monitor) == 'table' then s.monitor = { mode = s.monitor.mode } end
            for _, list in ipairs({ s.appointments or {}, s.checkins or {} }) do
                for _, ev in ipairs(list) do
                    if type(ev.detail) == 'table' then
                        ev.detail = { location = ev.detail.location, minutes = ev.detail.minutes, note = ev.detail.note, where = ev.detail.where }
                    end
                end
            end
            out.supervision = s
        end
    end
    if J.CS then
        local cs = J.CS.Get(cid)
        if cs.ok then out.communityService = cs.orders end
    end
    return out
end

local MONEY = { 'fine', 'citation', 'restitution' }

--- Fines, citations and restitution: what is owed, what can be paid here, what can be contested.
function Portal.Fines(src)
    local cid, err = citizen(src)
    if not cid then return err end
    local res = J.Orders.List(cid, { kinds = MONEY, limit = 100 })
    if not res.ok then return res end
    local ids = {}
    for _, o in ipairs(res.list) do if o.kind == 'citation' then ids[#ids + 1] = o.id end end
    local cits = {}
    if #ids > 0 then
        for _, r in ipairs(many(SQL.citations:format(string.rep('?', #ids, ', ')), ids) or {}) do cits[tonumber(r.order_id)] = r end
    end
    local now, payable = os.time(), J.States.Payable
    local list = {}
    for i, o in ipairs(res.list) do
        local cit = cits[o.id]
        list[i] = { id = o.id, kind = o.kind, state = o.state, amount = o.amount, paidAmount = o.paidAmount, dueAt = o.dueAt,
            createdAt = o.createdAt, charges = o.charges, payable = payable[o.state] == true,
            owed = math.max(0, (o.amount or 0) - (o.paidAmount or 0)),
            violation = cit and cit.violation or nil, plate = cit and cit.plate or nil,
            contestUntil = cit and tonumber(cit.contest_until) or nil,
            contestable = cit ~= nil and o.state == 'issued' and (tonumber(cit.contest_until) or 0) >= now }
    end
    return { ok = true, list = list }
end

--- Pays one of the citizen's own orders through 15B PayOrder (keyed per attempt; the ledger moves the money).
function Portal.Pay(src, payload)
    local cid, err = citizen(src)
    if not cid then return err end
    local id = U.Int(payload.orderId, 1, 2147483647)
    local account = payload.account == 'cash' and 'cash' or (payload.account == nil or payload.account == 'bank') and 'bank' or nil
    if not id or not account then return Err('bad_args', 'Choose an order and bank or cash') end
    local row = J.Orders.Row(id)
    if not row or row.citizenid ~= cid then return Err('not_found', 'No such order') end
    if row.state == 'paid' then return { ok = true, duplicate = true, state = 'paid' } end
    -- the key follows the order's attempt counter: a lost answer repeats the same payment (duplicate), a
    -- clearly refused one moved the counter on, so the next press is a new attempt
    local key = ('pf-justice:portal:%d:pay:%d'):format(id, (tonumber(row.pay_attempt) or 0) + 1)
    return J.Orders.Pay(id, { payerSrc = src, account = account, key = key }, {})
end

--- Contests a citation inside its window (15B ContestCitation: the cited citizen only, once).
function Portal.Contest(src, payload)
    local cid, err = citizen(src)
    if not cid then return err end
    return J.Orders.ContestCitation(payload.orderId, { actor = { src = src }, reason = U.Str(payload.reason, 200) }, {})
end

local IA_CATEGORIES = { 'conduct', 'force', 'discourtesy', 'misconduct', 'corruption', 'other' }

--- The complaint form: categories and a fresh key (the complaint is filed once per key).
function Portal.IaForm(src)
    local cid, err = citizen(src)
    if not cid then return err end
    if GetResourceState('pf-policemdt-DEV') ~= 'started' then return Err('ia_unavailable', 'Internal Affairs is not taking complaints right now') end
    return { ok = true, categories = IA_CATEGORIES, key = A.IssueKey(src, 'ia') }
end

--- Files a complaint with Internal Affairs (pf-policemdt-DEV FileIaComplaint; the complainant is the
--- player's own character, read there from actor.src).
function Portal.FileComplaint(src, payload)
    local cid, err = citizen(src)
    if not cid then return err end
    local key, kerr = needKey(src, 'ia', payload)
    if not key then return kerr end
    if GetResourceState('pf-policemdt-DEV') ~= 'started' then return Err('ia_unavailable', 'Internal Affairs is not taking complaints right now') end
    local spec = { category = U.Str(payload.category, 16), summary = type(payload.summary) == 'string' and payload.summary:sub(1, 4000) or nil,
        officerName = U.Str(payload.officerName, 128), incidentRef = U.Str(payload.incidentRef, 64) }
    if payload.officerCid ~= nil and payload.officerCid ~= '' then
        if not U.ValidCid(payload.officerCid) then return Err('bad_args', 'Bad officer') end
        spec.officerCid = payload.officerCid
    end
    local ok, res = pcall(function() return exports['pf-policemdt-DEV']:FileIaComplaint(spec, { key = key, actor = { src = src } }) end)
    if not ok or type(res) ~= 'table' then return Err('ia_unavailable', 'Internal Affairs did not answer; try again') end
    return res
end

-- ═════════════════════════════════════════════════════════════════════════════════════════════════
-- registration
-- ═════════════════════════════════════════════════════════════════════════════════════════════════

local function bind(fn)
    return function(src, payload) return fn(tonumber(src), type(payload) == 'table' and payload or {}) end
end

A.Defs = {
    {
        def = { id = A.IDS.court, name = 'Court', icon = '⚖️', entry = 'html/apps/court.js', styles = { 'html/apps/justice.css' },
            devices = { 'tablet', 'computer' }, category = 'government', order = 20, access = { handler = true },
            window = { width = 1100, height = 720 }, description = 'Docket, cases, hearings, decisions, warrant reviews and probation' },
        handlers = {
            __access = function(src) return A.CourtAccess(tonumber(src)) == true end,
            me = bind(Court.Me), key = bind(Court.Key), docket = bind(Court.Docket), cases = bind(Court.Cases), case = bind(Court.Case),
            schedule = bind(Court.Schedule), decide = bind(Court.Decide), file = bind(Court.File), warrants = bind(Court.Warrants),
            decideWarrant = bind(Court.DecideWarrant), courtOrders = bind(Court.CourtOrders), issueOrder = bind(Court.IssueOrder),
            revokeOrder = bind(Court.RevokeOrder), caseload = bind(Court.Caseload), supervision = bind(Court.Supervision),
            appointment = bind(Court.Appointment), checkIn = bind(Court.CheckIn), violation = bind(Court.Violation), monitor = bind(Court.Monitor),
        },
    },
    {
        def = { id = A.IDS.cs, name = 'Community Service', icon = '🧹', entry = 'html/apps/cs.js', styles = { 'html/apps/justice.css' },
            devices = { 'tablet', 'computer' }, category = 'government', order = 21, access = { handler = true },
            window = { width = 960, height = 680 }, description = 'Your community service, or supervise shifts' },
        handlers = {
            __access = function(src) return A.CsAccess(tonumber(src)) == true end,
            me = bind(CSA.Me), state = bind(CSA.State), startShift = bind(CSA.StartShift), endShift = bind(CSA.EndShift),
            listWork = bind(CSA.ListWork), claim = bind(CSA.Claim), abandon = bind(CSA.Abandon), complete = bind(CSA.Complete),
            board = bind(CSA.Board), nearby = bind(CSA.Nearby), verify = bind(CSA.Verify), orders = bind(CSA.Orders),
        },
    },
    {
        def = { id = A.IDS.records, name = 'Justice Records', icon = '📜', entry = 'html/apps/records.js', styles = { 'html/apps/justice.css' },
            devices = { 'tablet', 'computer' }, category = 'government', order = 22, access = { anyone = true },
            window = { width = 960, height = 680 }, description = 'Your record, court dates, sentence, fines and complaints' },
        handlers = {
            record = bind(Portal.Record), court = bind(Portal.Court), sentence = bind(Portal.Sentence), fines = bind(Portal.Fines),
            pay = bind(Portal.Pay), contest = bind(Portal.Contest), iaForm = bind(Portal.IaForm), fileComplaint = bind(Portal.FileComplaint),
        },
    },
}

--- Registers the three apps with pf-devices (at start and whenever pf-devices restarts). Returns true when done.
function A.RegisterAll()
    if cfg('Enabled', true) == false or GetResourceState('pf-devices') ~= 'started' then return false end
    local all = true
    for _, entry in ipairs(A.Defs) do
        local ok = pcall(function()
            exports['pf-devices']:RegisterApp(entry.def)
            exports['pf-devices']:RegisterAppHandlers(entry.def.id, entry.handlers)
        end)
        all = all and ok
    end
    return all
end

AddEventHandler('onResourceStart', function(resource)
    if resource == J.RESOURCE or resource == 'pf-devices' then A.RegisterAll() end
end)
AddEventHandler('pf-devices:server:ready', function() A.RegisterAll() end)

-- ── live updates: a case or a warrant review changed (ids only; the app reads the rest) ──

function A.PushCourt(event, payload)
    if GetResourceState('pf-devices') ~= 'started' then return end
    for _, job in ipairs(cfg('PushJobs', { 'judge', 'doj' })) do
        pcall(function() exports['pf-devices']:PushToJob(job, A.IDS.court, event, payload, true) end)
    end
end

AddEventHandler('pf-justice:server:caseChanged', function(case, change)
    if type(case) ~= 'table' then return end
    A.PushCourt('caseChanged', { caseId = tonumber(case.id), action = type(change) == 'table' and change.action or nil })
end)

AddEventHandler('pf-justice:server:warrantReviewChanged', function(review)
    if type(review) ~= 'table' then return end
    A.PushCourt('warrantChanged', { reviewId = tonumber(review.id) })
end)
