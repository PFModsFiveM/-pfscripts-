-- ============================================================================
-- PF Police MDT - cases and investigations (batch 18, unit 18E)
-- ============================================================================
-- A case gathers the records of one investigation: incidents, reports, PJ evidence, warrants,
-- pf-justice custodies/orders/citations, BOLOs, the people involved (suspects, witnesses,
-- victims, persons of interest), and append-only entries (statements, interviews, leads,
-- surveillance logs, notes, assignments). A lead detective runs it through
-- open -> active <-> suspended -> ready_for_court -> submitted -> closed.
--
-- Court submission: each suspect is submitted on its own row (pf_mdt_case_submissions) with the key
-- pf-policemdt:case:<caseId>:court:<submissionId> and handed to exports['pf-justice']:FileCase
-- (contract 19A). Until pf-justice answers with a court case id the row stays 'pending' and the
-- case 'ready_for_court'; SweepSubmissions hands pending rows over once FileCase exists. Nothing
-- reports a filing that did not happen.
--
-- Endpoints (QBCore callbacks, one table argument, answer { ok, success, ... } or
-- { ok = false, error, message }); server/access.lua gates every pf_mdt: name to police jobs and the
-- write names below to on-duty officers with the action's grade (Config.Permissions):
--   pf_mdt:cases:list, :get, :incidentLinks                       (reads)
--   pf_mdt:cases:create                                           caseCreate
--   pf_mdt:cases:update, :setStatus, :setLead, :link, :unlink,
--     :addPerson, :removePerson, :addEntry, :setEntryStatus       caseEdit (+ lead/supervisor rules here)
--   pf_mdt:cases:submit, :withdrawSubmission                      caseSubmit
-- Export: AttachExternalRecord(target, ref, opts) for pfm-policejob, pf-justice, pf-ambulancejob.
-- Server-only event: pf_mdt:server:caseChanged(case, change) after every change.

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtCases = PFMdtCases or {}
local Cases = PFMdtCases

local RATE_MS = 1000 -- new MDT writes: 1 per second per officer (architecture 6.3)

-- Grades used when config.lua has no entry (Config.Permissions accepts a plain number for all jobs).
local DEFAULT_GRADES = { caseCreate = 0, caseEdit = 0, caseSubmit = 2, caseSupervise = 3 }
Config.Permissions = Config.Permissions or {}
for action, grade in pairs(DEFAULT_GRADES) do
    if Config.Permissions[action] == nil then Config.Permissions[action] = grade end
end

-- Resources that may attach their records to cases and incidents (Config.Cases.Callers overrides).
local DEFAULT_CALLERS = { ['pfm-policejob'] = true, ['pf-justice'] = true, ['pf-ambulancejob'] = true }

function Cases.Cfg()
    local c = type(Config.Cases) == 'table' and Config.Cases or {}
    return {
        MaxPeople = tonumber(c.MaxPeople) or 60,
        MaxEntries = tonumber(c.MaxEntries) or 1000,
        MaxLinks = tonumber(c.MaxLinks) or 300,
        MaxBody = tonumber(c.MaxBody) or 4000,
        MaxCharges = tonumber(c.MaxCharges) or 20,
        ListLimit = tonumber(c.ListLimit) or 50,
        EntriesShown = tonumber(c.EntriesShown) or 300,
        SweepSeconds = tonumber(c.SweepSeconds) or 60,
        Callers = c.Callers or DEFAULT_CALLERS,
    }
end

Cases.Statuses = { open = true, active = true, suspended = true, ready_for_court = true, submitted = true, closed = true }
-- Moves an officer may make by hand. ready_for_court and submitted are reached only through a
-- court submission; reopening a closed case or pulling back a submitted one is a supervisor's call.
Cases.Moves = {
    open = { active = true, suspended = true, closed = true },
    active = { suspended = true, closed = true },
    suspended = { active = true, closed = true },
    ready_for_court = { active = true, closed = true },
    submitted = { active = true, closed = true },
    closed = { active = true },
}
local SUPERVISOR_MOVES = { ['closed>active'] = true, ['submitted>active'] = true }
-- Records can be added while the investigation runs; a submitted or closed case is read-only.
local EDITABLE = { open = true, active = true, suspended = true, ready_for_court = true }
local SUBMITTABLE = { open = true, active = true, ready_for_court = true }

Cases.Roles = { suspect = true, witness = true, victim = true, person_of_interest = true }
Cases.EntryKinds = { statement = true, interview = true, lead = true, surveillance = true, note = true, assignment = true }
local ENTRY_STATUS = {
    lead = { open = true, followed = true, dismissed = true },
    assignment = { open = true, done = true, cancelled = true },
}
-- Links an officer makes from the MDT (each is checked against its owner) ...
Cases.LinkTypes = { incident = true, report = true, evidence = true, warrant = true, custody = true, order = true, citation = true, bolo = true }
-- ... and the records other resources attach through AttachExternalRecord.
Cases.ExternalTypes = { evidence = true, custody = true, order = true, death_record = true, citation = true, telemetry = true }

-- ── helpers ─────────────────────────────────────────────────────────────────

local function now() return os.time() end

local function err(code, message, extra)
    local out = { ok = false, error = code, message = message }
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end
Cases.Err = err

local callable = PFMdtAccess.Callable

local function int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n)
    if not n or (min and n < min) or (max and n > max) then return nil end
    return n
end

-- Plain text: control characters become spaces (newlines kept when multiline), trimmed, clipped;
-- nil when empty.
local function text(v, maxLen, multiline)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v)
    if multiline then s = s:gsub('\r\n?', '\n'):gsub('[\0-\9\11-\31\127]', ' ')
    else s = s:gsub('[%c]', ' ') end
    s = s:match('^%s*(.-)%s*$')
    if #s > maxLen then s = s:sub(1, maxLen) end
    return s ~= '' and s or nil
end

local function cidOf(v)
    if type(v) ~= 'string' or #v < 1 or #v > 64 or not v:match('^[%w_%-]+$') then return nil end
    return v
end

-- record ids other resources and MDT tables use: letters, digits and - _ : .
local function refId(v, maxLen)
    if type(v) == 'number' then v = int(v, 1) and tostring(int(v, 1)) or nil end
    if type(v) ~= 'string' or #v < 1 or #v > (maxLen or 64) or not v:match('^[%w%-_:%.]+$') then return nil end
    return v
end

local function db(kind, sql, params)
    local ok, res = pcall(function() return MySQL[kind].await(sql, params or {}) end)
    if not ok then
        print(('^1[pf-policemdt]^7 cases: query failed: %s'):format(tostring(res)))
        return nil, false
    end
    return res, true
end
Cases.Query = db

-- a COUNT(*) (0 when the query failed)
local function count(sql, params) return tonumber((db('scalar', sql, params))) or 0 end

local function decode(s)
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

--- A citizen by citizen id: online from pfm-core, else the players row. { cid, name, job } or nil.
function Cases.Citizen(cid)
    cid = cidOf(cid)
    if not cid then return nil end
    local P = QBCore.Functions.GetPlayerByCitizenId(cid)
    if P and P.PlayerData then
        local job = P.PlayerData.job
        return { cid = cid, name = charName(P.PlayerData.charinfo) or cid, job = type(job) == 'table' and job.name or nil, online = true }
    end
    local row = db('single', 'SELECT citizenid, charinfo, job FROM players WHERE citizenid = ? LIMIT 1', { cid })
    if type(row) ~= 'table' or not row.citizenid then return nil end
    local job = decode(row.job)
    return { cid = cid, name = charName(row.charinfo) or cid, job = type(job) == 'table' and job.name or nil, online = false }
end

local function isPoliceCitizen(c)
    return c ~= nil and c.job ~= nil and Config.AllowedJobs and Config.AllowedJobs[c.job] == true
end

--- The acting officer, read from the server's player. nil when not an MDT officer.
function Cases.Actor(src)
    local job, P = PFMdtAccess.Job(src)
    if not job or not P or not (Config.AllowedJobs and Config.AllowedJobs[job.name]) then return nil end
    local pd = P.PlayerData
    return {
        src = src, cid = pd.citizenid, name = charName(pd.charinfo) or pd.citizenid, job = job.name, grade = job.grade,
        onduty = job.onduty, supervisor = PFMdtAccess.Rank(src, 'caseSupervise') == true,
    }
end

-- Per-case lock: taken before the first database wait of a check-then-write.
local locks = {}
local function withLock(key, fn)
    if locks[key] then return err('busy', 'Someone else is changing this case; try again') end
    locks[key] = true
    local ok, res = pcall(fn)
    locks[key] = nil
    if not ok then
        print(('^1[pf-policemdt]^7 cases: %s failed: %s'):format(key, tostring(res)))
        return err('db_unavailable', 'The case system failed; check the case before trying again')
    end
    return res
end
Cases.Locks = locks

local function audit(caseId, action, actor, detail)
    local s = json.encode(detail or {})
    if #s > 4096 then s = s:sub(1, 4096) end
    db('insert', 'INSERT INTO pf_mdt_record_audit (entity, entity_id, action, by_cid, by_job, detail, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { 'case', tostring(caseId), action, actor and actor.cid or 'system', actor and actor.job or nil, s, now() })
end

local function publicCase(row)
    if type(row) ~= 'table' then return nil end
    return {
        id = tonumber(row.id), caseNo = row.case_no, title = row.title, status = row.status, priority = tonumber(row.priority),
        leadCid = row.lead_cid, summary = row.summary, courtCaseId = tonumber(row.court_case_id), createdBy = row.created_by,
        createdAt = tonumber(row.created_at), updatedAt = tonumber(row.updated_at),
    }
end
Cases.Public = publicCase

local function loadCase(id)
    id = int(id, 1, 2147483647)
    if not id then return nil, err('bad_args', 'Unknown case') end
    local row, ok = db('single', 'SELECT * FROM pf_mdt_cases WHERE id = ?', { id })
    if not ok then return nil, err('db_unavailable', 'The case database did not answer') end
    if type(row) ~= 'table' or not row.id then return nil, err('not_found', 'No such case') end
    return row
end
Cases.Load = loadCase

local function changed(caseId, change)
    local row = db('single', 'SELECT * FROM pf_mdt_cases WHERE id = ?', { caseId })
    TriggerEvent('pf_mdt:server:caseChanged', publicCase(row), change)
end

local function touch(caseId)
    db('update', 'UPDATE pf_mdt_cases SET updated_at = ? WHERE id = ?', { now(), caseId })
end

-- The lead, or the creator of a case without a lead, or a supervisor (Config.Permissions.caseSupervise).
local function canManage(actor, row)
    if actor.supervisor then return true end
    if row.lead_cid and row.lead_cid ~= '' then return row.lead_cid == actor.cid end
    return row.created_by == actor.cid
end
Cases.CanManage = canManage

local function needEditable(row)
    if not EDITABLE[row.status] then return err('invalid_state', ('The case is %s; reopen it first'):format(row.status)) end
end

local function started(res) return GetResourceState(res) == 'started' end

-- One call into another resource's export; nil when it is not running or the call broke off.
local function call(res, name, ...)
    if not started(res) then return nil end
    local n, args = select('#', ...), { ... }
    local ok, out = pcall(function()
        local e = exports[res]
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok then
        print(('^3[pf-policemdt]^7 cases: %s:%s failed: %s'):format(res, name, tostring(out)))
        return nil
    end
    return out
end
Cases.Call = call

-- ── endpoint plumbing ───────────────────────────────────────────────────────

local function schemaReady() return PFMdtSchema ~= nil and PFMdtSchema.Ready() end

Cases.Handlers = {}

local function endpoint(name, write, handler)
    Cases.Handlers[name] = handler
    QBCore.Functions.CreateCallback(name, function(source, cb, data)
        if not callable(cb) then return end
        local src = tonumber(source)
        local res
        if not src or src <= 0 then
            res = err('bad_args', 'Bad caller')
        elseif write and not PFMdtAccess.AllowRate(src, 'cases:write', RATE_MS) then
            res = err('rate_limited', 'Slow down')
        elseif not schemaReady() then
            res = err('db_unavailable', 'The MDT database is not ready')
        else
            local actor = Cases.Actor(src)
            if not actor then
                res = err('no_permission', 'Police only')
            elseif write and not actor.onduty then
                res = err('not_on_duty', 'You must be on duty to do that')
            else
                local ok, out = pcall(handler, actor, type(data) == 'table' and data or {})
                if ok and type(out) == 'table' then res = out
                else
                    print(('^1[pf-policemdt]^7 %s failed: %s'):format(name, tostring(out)))
                    res = err('db_unavailable', 'The case system failed; check the case before trying again')
                end
            end
        end
        res.success = res.ok == true
        cb(res)
    end)
end

-- the gate entries (server/access.lua): on duty and the action's grade for every write
local ACTIONS = {
    ['pf_mdt:cases:create'] = { action = 'caseCreate' },
    ['pf_mdt:cases:update'] = { action = 'caseEdit' },
    ['pf_mdt:cases:setStatus'] = { action = 'caseEdit' },
    ['pf_mdt:cases:setLead'] = { action = 'caseEdit' },
    ['pf_mdt:cases:link'] = { action = 'caseEdit' },
    ['pf_mdt:cases:unlink'] = { action = 'caseEdit' },
    ['pf_mdt:cases:addPerson'] = { action = 'caseEdit' },
    ['pf_mdt:cases:removePerson'] = { action = 'caseEdit' },
    ['pf_mdt:cases:addEntry'] = { action = 'caseEdit' },
    ['pf_mdt:cases:setEntryStatus'] = { action = 'caseEdit' },
    ['pf_mdt:cases:submit'] = { action = 'caseSubmit' },
    ['pf_mdt:cases:withdrawSubmission'] = { action = 'caseSubmit' },
}
Cases.Actions = ACTIONS
if callable(PFMdtAccess.RegisterActions) then
    PFMdtAccess.RegisterActions(ACTIONS)
elseif type(PFMdtAccess.Actions) == 'table' then
    -- before the 18F helper exists: the same table the gate reads at call time
    for name, entry in pairs(ACTIONS) do
        if PFMdtAccess.Actions[name] == nil then PFMdtAccess.Actions[name] = entry end
    end
end

-- ── cases ───────────────────────────────────────────────────────────────────

function Cases.Create(actor, data)
    local title = text(data.title, 128)
    if not title then return err('bad_args', 'A case needs a title') end
    local summary = text(data.summary, Cases.Cfg().MaxBody, true)
    local priority = data.priority == nil and 2 or int(data.priority, 1, 4)
    if not priority then return err('bad_args', 'Priority is 1 to 4') end
    local t = now()
    -- the number comes from the row id; the placeholder only has to be unique for a moment
    local tmp = ('T%d%04d'):format(t % 100000000, math.random(0, 9999))
    local id = db('insert', 'INSERT INTO pf_mdt_cases (case_no, title, status, priority, lead_cid, summary, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { tmp, title, 'open', priority, actor.cid, summary, actor.cid, t, t })
    id = int(id, 1)
    if not id then return err('db_unavailable', 'The case could not be created') end
    local caseNo = ('C-%06d'):format(id)
    db('update', 'UPDATE pf_mdt_cases SET case_no = ? WHERE id = ?', { caseNo, id })
    audit(id, 'create', actor, { title = title, priority = priority })
    changed(id, { action = 'created' })
    return { ok = true, caseId = id, caseNo = caseNo }
end

function Cases.Update(actor, data)
    local row, e = loadCase(data.caseId)
    if not row then return e end
    if not canManage(actor, row) then return err('no_permission', 'Only the lead detective or a supervisor edits the case') end
    local bad = needEditable(row)
    if bad then return bad end
    local sets, params, detail = {}, {}, {}
    if data.title ~= nil then
        local title = text(data.title, 128)
        if not title then return err('bad_args', 'A case needs a title') end
        sets[#sets + 1] = 'title = ?'; params[#params + 1] = title; detail.title = title
    end
    if data.summary ~= nil then
        sets[#sets + 1] = 'summary = ?'; params[#params + 1] = text(data.summary, Cases.Cfg().MaxBody, true); detail.summary = true
    end
    if data.priority ~= nil then
        local p = int(data.priority, 1, 4)
        if not p then return err('bad_args', 'Priority is 1 to 4') end
        sets[#sets + 1] = 'priority = ?'; params[#params + 1] = p; detail.priority = p
    end
    if #sets == 0 then return err('bad_args', 'Nothing to change') end
    sets[#sets + 1] = 'updated_at = ?'; params[#params + 1] = now()
    params[#params + 1] = row.id
    local _, ok = db('update', 'UPDATE pf_mdt_cases SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', params)
    if not ok then return err('db_unavailable', 'The case could not be saved') end
    audit(row.id, 'update', actor, detail)
    changed(row.id, { action = 'updated' })
    return { ok = true, caseId = tonumber(row.id) }
end

local function countOpenSubmissions(caseId)
    return count("SELECT COUNT(*) FROM pf_mdt_case_submissions WHERE case_id = ? AND state = 'pending'", { caseId })
end

--- Compare-and-set of the case status. true when this call moved it.
local function moveStatus(caseId, from, to)
    local n = db('update', 'UPDATE pf_mdt_cases SET status = ?, updated_at = ? WHERE id = ? AND status = ?', { to, now(), caseId, from })
    return (tonumber(n) or 0) == 1
end
Cases.MoveStatus = moveStatus

function Cases.SetStatus(actor, data)
    local to = type(data.status) == 'string' and data.status or nil
    if not to or not Cases.Statuses[to] then return err('bad_args', 'Unknown status') end
    local caseId = int(data.caseId, 1, 2147483647)
    if not caseId then return err('bad_args', 'Unknown case') end
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        if row.status == to then return { ok = true, unchanged = true, status = to } end
        if not (Cases.Moves[row.status] or {})[to] then
            return err('invalid_state', ('A %s case cannot become %s'):format(row.status, to))
        end
        if not canManage(actor, row) then return err('no_permission', 'Only the lead detective or a supervisor changes the status') end
        if SUPERVISOR_MOVES[row.status .. '>' .. to] and not actor.supervisor then
            return err('no_permission', 'A supervisor reopens this case')
        end
        -- a pending court submission must be withdrawn first: it could be filed meanwhile
        if (row.status == 'ready_for_court' or to == 'closed') and countOpenSubmissions(row.id) > 0 then
            return err('conflict', 'Withdraw the pending court submissions first')
        end
        if not moveStatus(row.id, row.status, to) then return err('busy', 'The case changed meanwhile; read it again') end
        audit(row.id, 'status', actor, { from = row.status, to = to })
        changed(row.id, { action = 'status', from = row.status, to = to })
        return { ok = true, caseId = tonumber(row.id), status = to }
    end)
end

function Cases.SetLead(actor, data)
    local row, e = loadCase(data.caseId)
    if not row then return e end
    local bad = needEditable(row)
    if bad then return bad end
    local hasLead = row.lead_cid ~= nil and row.lead_cid ~= ''
    local leadCid
    if data.leadCid ~= nil and data.leadCid ~= '' then
        leadCid = cidOf(data.leadCid)
        if not leadCid then return err('bad_args', 'Bad citizen id') end
    end
    -- an officer may take a case nobody leads; otherwise the lead hands over or a supervisor assigns
    local selfClaim = not hasLead and leadCid == actor.cid
    if not (selfClaim or canManage(actor, row)) then return err('no_permission', 'Only the lead detective or a supervisor assigns the lead') end
    if not leadCid and not actor.supervisor then return err('no_permission', 'A supervisor removes the lead') end
    local name
    if leadCid then
        local c = Cases.Citizen(leadCid)
        if not isPoliceCitizen(c) then return err('bad_args', 'The lead must be a police officer') end
        name = c.name
    end
    local _, ok = db('update', 'UPDATE pf_mdt_cases SET lead_cid = ?, updated_at = ? WHERE id = ?', { leadCid, now(), row.id })
    if not ok then return err('db_unavailable', 'The case could not be saved') end
    audit(row.id, 'update', actor, { lead = leadCid or false, from = row.lead_cid })
    changed(row.id, { action = 'lead', leadCid = leadCid })
    if leadCid and leadCid ~= actor.cid then
        local P = QBCore.Functions.GetPlayerByCitizenId(leadCid)
        if P and P.PlayerData then TriggerClientEvent('QBCore:Notify', P.PlayerData.source, ('You lead case %s'):format(row.case_no), 'primary') end
    end
    return { ok = true, caseId = tonumber(row.id), leadCid = leadCid, leadName = name }
end

-- ── list and read ───────────────────────────────────────────────────────────

local function namesFor(cids)
    local list, seen = {}, {}
    for _, c in ipairs(cids) do
        if type(c) == 'string' and c ~= '' and not seen[c] then seen[c] = true; list[#list + 1] = c end
    end
    local out = {}
    if #list == 0 then return out end
    local marks = string.rep('?,', #list):sub(1, -2)
    for _, r in ipairs(db('query', ('SELECT citizenid, charinfo FROM players WHERE citizenid IN (%s)'):format(marks), list) or {}) do
        out[r.citizenid] = charName(r.charinfo)
    end
    return out
end

function Cases.List(actor, data)
    local cfg = Cases.Cfg()
    local where, params = {}, {}
    if data.status ~= nil then
        if not Cases.Statuses[data.status] then return err('bad_args', 'Unknown status') end
        where[#where + 1] = 'c.status = ?'; params[#params + 1] = data.status
    elseif data.includeClosed ~= true then
        where[#where + 1] = "c.status <> 'closed'"
    end
    if data.q ~= nil then
        local q = text(data.q, 64)
        if q then
            local like = '%' .. q:gsub('[!%%_]', '!%0') .. '%'
            where[#where + 1] = "(c.title LIKE ? ESCAPE '!' OR c.case_no LIKE ? ESCAPE '!')"
            params[#params + 1] = like; params[#params + 1] = like
        end
    end
    if data.mine == true then
        where[#where + 1] = "(c.lead_cid = ? OR c.id IN (SELECT case_id FROM pf_mdt_case_entries WHERE kind = 'assignment' AND assignee_cid = ? AND status = 'open'))"
        params[#params + 1] = actor.cid; params[#params + 1] = actor.cid
    end
    if data.after ~= nil then
        local after = int(data.after, 1)
        if not after then return err('bad_args', 'Bad cursor') end
        where[#where + 1] = 'c.id < ?'; params[#params + 1] = after
    end
    local limit = int(data.limit, 1, cfg.ListLimit) or 25
    params[#params + 1] = limit + 1
    local rows, ok = db('query', 'SELECT c.id, c.case_no, c.title, c.status, c.priority, c.lead_cid, c.court_case_id, c.created_by, c.created_at, c.updated_at FROM pf_mdt_cases c'
        .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '') .. ' ORDER BY c.id DESC LIMIT ?', params)
    if not ok then return err('db_unavailable', 'The case database did not answer') end
    local list, cids = {}, {}
    for i, r in ipairs(rows or {}) do
        if i > limit then break end
        local c = publicCase(r)
        list[#list + 1] = c
        cids[#cids + 1] = c.leadCid
    end
    local names = namesFor(cids)
    for _, c in ipairs(list) do c.leadName = c.leadCid and names[c.leadCid] or nil end
    local nextCursor = (#(rows or {}) > limit and #list > 0) and list[#list].id or nil
    return { ok = true, list = list, next = nextCursor }
end

function Cases.Get(actor, data)
    local row, e = loadCase(data.caseId)
    if not row then return e end
    local cfg = Cases.Cfg()
    local c = publicCase(row)
    local links = {}
    for _, r in ipairs(db('query', 'SELECT id, ref_type, ref_id, note, by_cid, at FROM pf_mdt_case_links WHERE case_id = ? ORDER BY id', { row.id }) or {}) do
        links[#links + 1] = { id = tonumber(r.id), type = r.ref_type, refId = r.ref_id, note = r.note, by = r.by_cid, at = tonumber(r.at) }
    end
    local people = {}
    for _, r in ipairs(db('query', 'SELECT id, role, citizenid, manual_id, name, note FROM pf_mdt_case_people WHERE case_id = ? ORDER BY id', { row.id }) or {}) do
        people[#people + 1] = { id = tonumber(r.id), role = r.role, citizenid = r.citizenid, manualId = tonumber(r.manual_id), name = r.name, note = r.note }
    end
    local entries = {}
    for _, r in ipairs(db('query', 'SELECT id, kind, person_id, assignee_cid, status, body, by_cid, by_name, at FROM pf_mdt_case_entries WHERE case_id = ? ORDER BY id DESC LIMIT ?', { row.id, cfg.EntriesShown }) or {}) do
        entries[#entries + 1] = { id = tonumber(r.id), kind = r.kind, personId = tonumber(r.person_id), assigneeCid = r.assignee_cid,
            status = r.status, body = r.body, by = r.by_cid, byName = r.by_name, at = tonumber(r.at) }
    end
    local submissions = {}
    for _, r in ipairs(db('query', 'SELECT id, person_id, citizenid, state, spec, court_case_id, attempts, last_error, by_cid, created_at, updated_at FROM pf_mdt_case_submissions WHERE case_id = ? ORDER BY id', { row.id }) or {}) do
        local spec = decode(r.spec) or {}
        submissions[#submissions + 1] = { id = tonumber(r.id), personId = tonumber(r.person_id), citizenid = r.citizenid, state = r.state,
            charges = spec.charges, courtCaseId = tonumber(r.court_case_id), attempts = tonumber(r.attempts), lastError = r.last_error,
            by = r.by_cid, createdAt = tonumber(r.created_at), updatedAt = tonumber(r.updated_at) }
    end
    -- evidence as PJ holds it now (custody state, integrity); the links above say what was attached
    local evidence, evidenceNote = nil, nil
    local ev = call('pfm-policejob', 'ListEvidence', { caseRef = { type = 'case', id = tostring(row.id) }, viewer = actor.src, limit = 100 })
    if type(ev) == 'table' and ev.ok then evidence = ev.list
    else evidenceNote = 'Evidence storage is not available right now' end
    local cids = { c.leadCid, c.createdBy }
    for _, en in ipairs(entries) do cids[#cids + 1] = en.assigneeCid end
    local names = namesFor(cids)
    c.leadName = c.leadCid and names[c.leadCid] or nil
    c.createdByName = names[c.createdBy]
    for _, en in ipairs(entries) do en.assigneeName = en.assigneeCid and names[en.assigneeCid] or nil end
    return {
        ok = true, case = c, links = links, people = people, entries = entries, submissions = submissions,
        evidence = evidence, evidenceNote = evidenceNote,
        -- what the viewer may do (the server checks again on every write)
        can = { manage = canManage(actor, row), supervise = actor.supervisor, edit = EDITABLE[row.status] == true and actor.onduty == true,
            submit = SUBMITTABLE[row.status] == true and canManage(actor, row) and PFMdtAccess.Rank(actor.src, 'caseSubmit') == true },
    }
end

-- ── links ───────────────────────────────────────────────────────────────────

local function exists(sql, params)
    local v, ok = db('scalar', sql, params)
    if not ok then return nil end
    return v ~= nil
end

--- Checks a link an officer asks for against the record's owner. Returns the stored ref id or nil, error.
local function resolveLink(actor, row, refType, data)
    if refType == 'incident' then
        local id = refId(data.refId, 16)
        if not id then return nil, err('bad_args', 'Bad incident id') end
        local found = exists('SELECT incidentId FROM pf_mdt_incidents WHERE incidentId = ? AND deleted_at IS NULL LIMIT 1', { id })
        if found == nil then return nil, err('db_unavailable', 'The MDT database did not answer') end
        if not found then return nil, err('not_found', 'No such incident') end
        return id
    elseif refType == 'report' then
        local id = refId(data.refId, 16)
        if not id then return nil, err('bad_args', 'Bad report id') end
        local found = exists('SELECT reportId FROM pf_mdt_reports WHERE reportId = ? LIMIT 1', { id })
        if found == nil then return nil, err('db_unavailable', 'The MDT database did not answer') end
        if not found then return nil, err('not_found', 'No such report') end
        return id
    elseif refType == 'warrant' then
        local id = refId(data.refId, 16)
        if not id then return nil, err('bad_args', 'Bad warrant id') end
        local found = exists('SELECT warrantId FROM pf_mdt_warrants WHERE warrantId = ? LIMIT 1', { id })
        if found == nil then return nil, err('db_unavailable', 'The MDT database did not answer') end
        if not found then return nil, err('not_found', 'No such warrant') end
        return id
    elseif refType == 'bolo' then
        local id = int(data.refId, 1, 2147483647)
        if not id then return nil, err('bad_args', 'Bad BOLO id') end
        local found = exists('SELECT id FROM pf_mdt_bolos WHERE id = ? LIMIT 1', { id })
        if found == nil then return nil, err('db_unavailable', 'The MDT database did not answer') end
        if not found then return nil, err('not_found', 'No such BOLO') end
        return tostring(id)
    elseif refType == 'order' or refType == 'citation' then
        local id = int(data.refId, 1, 2147483647)
        if not id then return nil, err('bad_args', 'Bad order id') end
        local res = call('pf-justice', 'GetOrder', id)
        if type(res) ~= 'table' then return nil, err('db_unavailable', 'pf-justice is not available; nothing was linked') end
        if not res.ok or type(res.order) ~= 'table' then return nil, err('not_found', 'No such order') end
        if refType == 'citation' and res.order.kind ~= 'citation' then return nil, err('bad_args', 'That order is not a citation') end
        return tostring(id)
    elseif refType == 'custody' then
        -- pf-justice looks custodies up by citizen: the citizen's open custody, else the latest one
        local cid = cidOf(data.citizenid)
        if not cid then return nil, err('bad_args', 'Name the citizen whose custody to link') end
        local res = call('pf-justice', 'GetCustody', cid, { latest = true })
        if type(res) ~= 'table' then return nil, err('db_unavailable', 'pf-justice is not available; nothing was linked') end
        local custody = res.ok and res.custody or nil
        if type(custody) ~= 'table' or not int(custody.id, 1) then return nil, err('not_found', 'That citizen has no custody record') end
        if data.refId ~= nil and int(data.refId, 1) ~= int(custody.id, 1) then
            return nil, err('not_found', 'That custody is not the citizen\'s current or latest one')
        end
        return tostring(int(custody.id, 1))
    end
    return nil, err('bad_args', 'Records of this kind are attached by the system')
end

local function linkCount(caseId)
    return count('SELECT COUNT(*) FROM pf_mdt_case_links WHERE case_id = ?', { caseId })
end

local function findLink(caseId, refType, id)
    local v = db('scalar', 'SELECT id FROM pf_mdt_case_links WHERE case_id = ? AND ref_type = ? AND ref_id = ? LIMIT 1', { caseId, refType, id })
    return int(v, 1)
end

function Cases.Link(actor, data)
    local refType = type(data.refType) == 'string' and data.refType or nil
    if not refType or not Cases.LinkTypes[refType] then return err('bad_args', 'Unknown record type') end
    local caseId = int(data.caseId, 1, 2147483647)
    if not caseId then return err('bad_args', 'Unknown case') end
    local note = text(data.note, 255)
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        local bad = needEditable(row)
        if bad then return bad end
        if linkCount(row.id) >= Cases.Cfg().MaxLinks then return err('conflict', 'This case has too many linked records') end
        local id, linkedEvidence
        if refType == 'evidence' then
            -- PJ owns the evidence and its case links: it checks the officer and records a custody event
            if data.refId == nil or (type(data.refId) ~= 'number' and not refId(data.refId)) then return err('bad_args', 'Bad evidence id') end
            local res = call('pfm-policejob', 'LinkEvidence', data.refId, { type = 'case', id = tostring(row.id) }, { actor = { src = actor.src } })
            if type(res) ~= 'table' then return err('db_unavailable', 'Evidence storage is not available; nothing was linked') end
            if not res.ok then return err(res.error or 'bad_args', res.message or 'The evidence could not be linked') end
            id = refId(res.evidenceId or data.refId)
            linkedEvidence = true
        else
            local e2
            id, e2 = resolveLink(actor, row, refType, data)
            if not id then return e2 end
        end
        local existing = findLink(row.id, refType, id)
        if existing then return { ok = true, duplicate = true, linkId = existing } end
        local linkId = int(db('insert', 'INSERT INTO pf_mdt_case_links (case_id, ref_type, ref_id, note, by_cid, at) VALUES (?, ?, ?, ?, ?, ?)',
            { row.id, refType, id, note, actor.cid, now() }), 1)
        if not linkId then
            -- keep PJ's side in step with ours
            if linkedEvidence then call('pfm-policejob', 'UnlinkEvidence', id, { type = 'case', id = tostring(row.id) }, { actor = { src = actor.src } }) end
            return err('db_unavailable', 'The link could not be saved')
        end
        touch(row.id)
        audit(row.id, 'update', actor, { op = 'link', type = refType, id = id })
        changed(row.id, { action = 'linked', type = refType, refId = id })
        return { ok = true, linkId = linkId, refId = id }
    end)
end

function Cases.Unlink(actor, data)
    local linkId = int(data.linkId, 1, 2147483647)
    if not linkId then return err('bad_args', 'Unknown link') end
    local link = db('single', 'SELECT id, case_id, ref_type, ref_id FROM pf_mdt_case_links WHERE id = ?', { linkId })
    if type(link) ~= 'table' or not link.id then return err('not_found', 'No such link') end
    local caseId = int(link.case_id, 1)
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        local bad = needEditable(row)
        if bad then return bad end
        if not canManage(actor, row) then return err('no_permission', 'Only the lead detective or a supervisor removes links') end
        -- records attached by another resource stay unless a supervisor removes them
        if not Cases.LinkTypes[link.ref_type] and not actor.supervisor then return err('no_permission', 'A supervisor removes system records') end
        if link.ref_type == 'evidence' then
            local res = call('pfm-policejob', 'UnlinkEvidence', link.ref_id, { type = 'case', id = tostring(caseId) }, { actor = { src = actor.src } })
            if type(res) ~= 'table' then return err('db_unavailable', 'Evidence storage is not available; nothing was changed') end
            if not res.ok and res.error ~= 'not_found' then return err(res.error or 'bad_args', res.message or 'The evidence could not be unlinked') end
        end
        local n = db('update', 'DELETE FROM pf_mdt_case_links WHERE id = ?', { linkId })
        if (tonumber(n) or 0) ~= 1 then return err('busy', 'The link changed meanwhile') end
        touch(caseId)
        audit(caseId, 'update', actor, { op = 'unlink', type = link.ref_type, id = link.ref_id })
        changed(caseId, { action = 'unlinked', type = link.ref_type, refId = link.ref_id })
        return { ok = true }
    end)
end

-- ── people ──────────────────────────────────────────────────────────────────

function Cases.AddPerson(actor, data)
    local role = type(data.role) == 'string' and data.role or nil
    if not role or not Cases.Roles[role] then return err('bad_args', 'Role is suspect, witness, victim or person_of_interest') end
    local caseId = int(data.caseId, 1, 2147483647)
    if not caseId then return err('bad_args', 'Unknown case') end
    local note = text(data.note, 255)
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        local bad = needEditable(row)
        if bad then return bad end
        local cid, manualId, name
        if data.citizenid ~= nil and data.citizenid ~= '' then
            local c = Cases.Citizen(data.citizenid)
            if not c then return err('not_found', 'No such citizen') end
            cid, name = c.cid, c.name
        elseif data.manualId ~= nil then
            manualId = int(data.manualId, 1, 2147483647)
            if not manualId then return err('bad_args', 'Bad manual record id') end
            local m = db('single', 'SELECT firstname, lastname FROM pf_mdt_manual_citizens WHERE id = ?', { manualId })
            if type(m) ~= 'table' or not m.firstname then return err('not_found', 'No such manual record') end
            name = text((m.firstname or '') .. ' ' .. (m.lastname or ''), 128)
        else
            -- an unidentified person ("unknown male, red jacket") until they are identified
            name = text(data.name, 128)
            if not name then return err('bad_args', 'Name the person or pick a citizen') end
        end
        if cid then
            local dup = int(db('scalar', 'SELECT id FROM pf_mdt_case_people WHERE case_id = ? AND role = ? AND citizenid = ? LIMIT 1', { row.id, role, cid }), 1)
            if dup then return { ok = true, duplicate = true, personId = dup } end
        end
        if count('SELECT COUNT(*) FROM pf_mdt_case_people WHERE case_id = ?', { row.id }) >= Cases.Cfg().MaxPeople then return err('conflict', 'This case lists too many people') end
        local personId = int(db('insert', 'INSERT INTO pf_mdt_case_people (case_id, role, citizenid, manual_id, name, note) VALUES (?, ?, ?, ?, ?, ?)',
            { row.id, role, cid, manualId, name, note }), 1)
        if not personId then return err('db_unavailable', 'The person could not be added') end
        touch(row.id)
        audit(row.id, 'update', actor, { op = 'person', role = role, citizenid = cid, manualId = manualId })
        changed(row.id, { action = 'person', role = role })
        return { ok = true, personId = personId, name = name }
    end)
end

function Cases.RemovePerson(actor, data)
    local personId = int(data.personId, 1, 2147483647)
    if not personId then return err('bad_args', 'Unknown person') end
    local p = db('single', 'SELECT id, case_id, role, citizenid FROM pf_mdt_case_people WHERE id = ?', { personId })
    if type(p) ~= 'table' or not p.id then return err('not_found', 'No such person on a case') end
    local caseId = int(p.case_id, 1)
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        local bad = needEditable(row)
        if bad then return bad end
        if not canManage(actor, row) then return err('no_permission', 'Only the lead detective or a supervisor removes people') end
        -- statements and interviews keep the person they were taken from; a submission keeps its suspect
        local used = count('SELECT COUNT(*) FROM pf_mdt_case_entries WHERE person_id = ?', { personId })
        used = used + (count("SELECT COUNT(*) FROM pf_mdt_case_submissions WHERE person_id = ? AND state IN ('pending', 'filed')", { personId }))
        if used > 0 then return err('conflict', 'Statements, interviews or a court submission refer to this person') end
        local n = db('update', 'DELETE FROM pf_mdt_case_people WHERE id = ?', { personId })
        if (tonumber(n) or 0) ~= 1 then return err('busy', 'The person changed meanwhile') end
        touch(caseId)
        audit(caseId, 'update', actor, { op = 'remove_person', role = p.role, citizenid = p.citizenid })
        changed(caseId, { action = 'person_removed', role = p.role })
        return { ok = true }
    end)
end

-- ── entries: statements, interviews, leads, surveillance, notes, assignments ──
-- Entries are append-only: what a witness said or what was observed is never rewritten. Leads and
-- assignments carry a status that moves on.

function Cases.AddEntry(actor, data)
    local kind = type(data.kind) == 'string' and data.kind or nil
    if not kind or not Cases.EntryKinds[kind] then return err('bad_args', 'Unknown entry kind') end
    local caseId = int(data.caseId, 1, 2147483647)
    if not caseId then return err('bad_args', 'Unknown case') end
    local body = text(data.body, Cases.Cfg().MaxBody, true)
    if not body then return err('bad_args', 'Write the entry first') end
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        local bad = needEditable(row)
        if bad then return bad end
        local personId, assignee, status
        if kind == 'statement' or kind == 'interview' then
            personId = int(data.personId, 1, 2147483647)
            if not personId then return err('bad_args', 'Pick the person this ' .. kind .. ' is from') end
            local onCase = int(db('scalar', 'SELECT id FROM pf_mdt_case_people WHERE id = ? AND case_id = ?', { personId, row.id }), 1)
            if not onCase then return err('not_found', 'That person is not on this case') end
        elseif kind == 'lead' then
            status = 'open'
        elseif kind == 'assignment' then
            assignee = cidOf(data.assigneeCid)
            if not assignee then return err('bad_args', 'Pick the officer to assign') end
            -- the lead or a supervisor hands out tasks; any officer may take one on themselves
            if assignee ~= actor.cid and not canManage(actor, row) then return err('no_permission', 'Only the lead detective or a supervisor assigns others') end
            if assignee ~= actor.cid and not isPoliceCitizen(Cases.Citizen(assignee)) then return err('bad_args', 'Assignments go to police officers') end
            status = 'open'
        end
        if count('SELECT COUNT(*) FROM pf_mdt_case_entries WHERE case_id = ?', { row.id }) >= Cases.Cfg().MaxEntries then return err('conflict', 'This case has too many entries') end
        local entryId = int(db('insert', 'INSERT INTO pf_mdt_case_entries (case_id, kind, person_id, assignee_cid, status, body, by_cid, by_name, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { row.id, kind, personId, assignee, status, body, actor.cid, actor.name, now() }), 1)
        if not entryId then return err('db_unavailable', 'The entry could not be saved') end
        touch(row.id)
        audit(row.id, 'update', actor, { op = 'entry', kind = kind, entryId = entryId, personId = personId, assignee = assignee })
        changed(row.id, { action = 'entry', kind = kind, entryId = entryId })
        if assignee and assignee ~= actor.cid then
            local P = QBCore.Functions.GetPlayerByCitizenId(assignee)
            if P and P.PlayerData then TriggerClientEvent('QBCore:Notify', P.PlayerData.source, ('New task on case %s'):format(row.case_no), 'primary') end
        end
        return { ok = true, entryId = entryId }
    end)
end

function Cases.SetEntryStatus(actor, data)
    local entryId = int(data.entryId, 1, 2147483647)
    if not entryId then return err('bad_args', 'Unknown entry') end
    local en = db('single', 'SELECT id, case_id, kind, status, assignee_cid, by_cid FROM pf_mdt_case_entries WHERE id = ?', { entryId })
    if type(en) ~= 'table' or not en.id then return err('not_found', 'No such entry') end
    local allowed = ENTRY_STATUS[en.kind]
    if not allowed then return err('invalid_state', 'Only leads and assignments have a status') end
    local to = type(data.status) == 'string' and data.status or nil
    if not to or not allowed[to] then return err('bad_args', 'Unknown status for a ' .. en.kind) end
    local caseId = int(en.case_id, 1)
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        local bad = needEditable(row)
        if bad then return bad end
        if not (canManage(actor, row) or en.by_cid == actor.cid or en.assignee_cid == actor.cid) then
            return err('no_permission', 'Only the lead, the author or the assignee changes this')
        end
        if en.status == to then return { ok = true, unchanged = true } end
        local n = db('update', 'UPDATE pf_mdt_case_entries SET status = ? WHERE id = ? AND status = ?', { to, entryId, en.status })
        if (tonumber(n) or 0) ~= 1 then return err('busy', 'The entry changed meanwhile') end
        touch(caseId)
        audit(caseId, 'update', actor, { op = 'entry_status', entryId = entryId, from = en.status, to = to })
        changed(caseId, { action = 'entry_status', entryId = entryId, status = to })
        return { ok = true, entryId = entryId, status = to }
    end)
end

-- ── court submission ────────────────────────────────────────────────────────

function Cases.SubmissionKey(caseId, submissionId) return ('pf-policemdt:case:%d:court:%d'):format(caseId, submissionId) end

-- pf-justice refusals that a retry with the same key cannot change; anything else stays pending
local FINAL_REFUSALS = { bad_args = true, not_found = true, invalid_state = true, conflict = true, key_reused = true, no_permission = true }

--- Hands one pending submission to pf-justice FileCase. The caller holds the case lock.
--- Returns the submission's state afterwards ('pending' | 'filed' | 'refused') and a message.
function Cases.HandOver(sub)
    local subId, caseId = int(sub.id, 1), int(sub.case_id, 1)
    local spec = decode(sub.spec)
    if not subId or not caseId or type(spec) ~= 'table' then return 'pending', 'Unreadable submission' end
    if sub.state ~= 'pending' then return sub.state, nil end
    local key = sub.idem_key or Cases.SubmissionKey(caseId, subId)
    if not started('pf-justice') then
        return 'pending', 'Stored as ready for court: the court system is not available yet'
    end
    local ok, res = pcall(function()
        local ju = exports['pf-justice']
        return ju:FileCase(spec, { key = key, actor = { kind = 'system', label = 'pf-policemdt case submission' }, filedBy = sub.by_cid })
    end)
    local t = now()
    if not ok or type(res) ~= 'table' then
        -- no FileCase yet (19A), or the call broke off: the same key is tried again later
        db('update', 'UPDATE pf_mdt_case_submissions SET attempts = attempts + 1, last_error = ?, updated_at = ? WHERE id = ?',
            { 'court system not available', t, subId })
        return 'pending', 'Stored as ready for court: the court system is not available yet'
    end
    local courtCaseId = int(res.caseId, 1)
    if res.ok and courtCaseId then
        local n = db('update', "UPDATE pf_mdt_case_submissions SET state = 'filed', court_case_id = ?, attempts = attempts + 1, last_error = NULL, updated_at = ? WHERE id = ? AND state = 'pending'",
            { courtCaseId, t, subId })
        if (tonumber(n) or 0) ~= 1 then return 'pending', 'The submission changed meanwhile' end
        db('update', 'UPDATE pf_mdt_cases SET court_case_id = COALESCE(court_case_id, ?), updated_at = ? WHERE id = ?', { courtCaseId, t, caseId })
        -- the case is submitted once nothing is left waiting
        if countOpenSubmissions(caseId) == 0 then moveStatus(caseId, 'ready_for_court', 'submitted') end
        audit(caseId, 'status', nil, { op = 'filed', submissionId = subId, courtCaseId = courtCaseId, key = key })
        changed(caseId, { action = 'filed', submissionId = subId, courtCaseId = courtCaseId })
        return 'filed', 'Filed with the court'
    end
    local code = type(res.error) == 'string' and res.error or 'unknown'
    local msg = text(res.message or code, 255) or code
    if FINAL_REFUSALS[code] then
        db('update', "UPDATE pf_mdt_case_submissions SET state = 'refused', attempts = attempts + 1, last_error = ?, updated_at = ? WHERE id = ? AND state = 'pending'",
            { msg, t, subId })
        audit(caseId, 'status', nil, { op = 'court_refused', submissionId = subId, error = code })
        changed(caseId, { action = 'court_refused', submissionId = subId })
        return 'refused', msg
    end
    db('update', 'UPDATE pf_mdt_case_submissions SET attempts = attempts + 1, last_error = ?, updated_at = ? WHERE id = ?', { msg, t, subId })
    return 'pending', 'Stored as ready for court: ' .. msg
end

function Cases.Submit(actor, data)
    local caseId = int(data.caseId, 1, 2147483647)
    if not caseId then return err('bad_args', 'Unknown case') end
    local personId = int(data.personId, 1, 2147483647)
    if not personId then return err('bad_args', 'Pick the suspect to submit') end
    local cfg = Cases.Cfg()
    if type(data.charges) ~= 'table' or #data.charges == 0 or #data.charges > cfg.MaxCharges then
        return err('bad_args', ('Pick 1 to %d charges'):format(cfg.MaxCharges))
    end
    local codes, seen = {}, {}
    for _, c in ipairs(data.charges) do
        local code = refId(c, 16)
        if not code then return err('bad_args', 'Bad charge code') end
        if not seen[code] then seen[code] = true; codes[#codes + 1] = code end
    end
    local prosecutor
    if data.prosecutorCid ~= nil and data.prosecutorCid ~= '' then
        prosecutor = cidOf(data.prosecutorCid)
        if not prosecutor then return err('bad_args', 'Bad prosecutor id') end
    end
    local note = text(data.note, 1000, true)
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        if not SUBMITTABLE[row.status] then return err('invalid_state', ('A %s case cannot be submitted'):format(row.status)) end
        if not canManage(actor, row) then return err('no_permission', 'The lead detective or a supervisor submits the case') end
        local p = db('single', 'SELECT id, role, citizenid, name FROM pf_mdt_case_people WHERE id = ? AND case_id = ?', { personId, row.id })
        if type(p) ~= 'table' or not p.id then return err('not_found', 'That person is not on this case') end
        if p.role ~= 'suspect' or not cidOf(p.citizenid) then return err('bad_args', 'Only an identified suspect can be submitted') end
        local open = db('single', "SELECT id, state FROM pf_mdt_case_submissions WHERE case_id = ? AND citizenid = ? AND state IN ('pending', 'filed') LIMIT 1", { row.id, p.citizenid })
        if type(open) == 'table' and open.id then
            return { ok = true, duplicate = true, submissionId = int(open.id, 1), state = open.state }
        end
        -- charges from the penal code table, never the names a client sends
        local marks = string.rep('?,', #codes):sub(1, -2)
        local found = {}
        for _, r in ipairs(db('query', ('SELECT code, name FROM pf_mdt_charges WHERE code IN (%s)'):format(marks), codes) or {}) do found[r.code] = r.name end
        local charges = {}
        for _, code in ipairs(codes) do
            if not found[code] then return err('bad_args', 'Unknown charge ' .. code) end
            charges[#charges + 1] = { code = code, name = found[code] }
        end
        if prosecutor then
            local pc = Cases.Citizen(prosecutor)
            if not pc or pc.job ~= 'doj' then return err('bad_args', 'The prosecutor must work for the DOJ') end
        end
        -- the records the court receives: linked incidents, evidence and the suspect's linked custody
        local incidentIds, evidenceIds, custodyIds = {}, {}, {}
        for _, l in ipairs(db('query', "SELECT ref_type, ref_id FROM pf_mdt_case_links WHERE case_id = ? AND ref_type IN ('incident', 'evidence', 'custody')", { row.id }) or {}) do
            if l.ref_type == 'incident' then incidentIds[#incidentIds + 1] = l.ref_id
            elseif l.ref_type == 'evidence' then evidenceIds[#evidenceIds + 1] = int(l.ref_id, 1) or l.ref_id
            else custodyIds[l.ref_id] = true end
        end
        local custodyId
        local cu = call('pf-justice', 'GetCustody', p.citizenid, { latest = true })
        if type(cu) == 'table' and cu.ok and type(cu.custody) == 'table' and custodyIds[tostring(int(cu.custody.id, 1))] then
            custodyId = int(cu.custody.id, 1)
        end
        local spec = {
            cid = p.citizenid, charges = charges, custodyId = custodyId, incidentIds = incidentIds, evidenceIds = evidenceIds,
            prosecutorCid = prosecutor, mdtCaseId = tonumber(row.id), mdtCaseNo = row.case_no, title = row.title, note = note,
            filedBy = actor.cid,
        }
        local t = now()
        local subId = int(db('insert', "INSERT INTO pf_mdt_case_submissions (case_id, person_id, citizenid, state, spec, by_cid, created_at, updated_at) VALUES (?, ?, ?, 'pending', ?, ?, ?, ?)",
            { row.id, personId, p.citizenid, json.encode(spec), actor.cid, t, t }), 1)
        if not subId then return err('db_unavailable', 'The submission could not be stored') end
        local key = Cases.SubmissionKey(row.id, subId)
        db('update', 'UPDATE pf_mdt_case_submissions SET idem_key = ? WHERE id = ?', { key, subId })
        if row.status ~= 'ready_for_court' and not moveStatus(row.id, row.status, 'ready_for_court') then
            -- cannot happen under the lock unless the row was edited by hand; keep the submission withdrawable
            print(('^3[pf-policemdt]^7 case %s did not move to ready_for_court'):format(row.case_no))
        end
        audit(row.id, 'status', actor, { op = 'submit', submissionId = subId, citizenid = p.citizenid, charges = codes, key = key })
        changed(row.id, { action = 'submitted', submissionId = subId })
        local state, message = Cases.HandOver({ id = subId, case_id = row.id, state = 'pending', spec = json.encode(spec), idem_key = key, by_cid = actor.cid })
        local after = db('single', 'SELECT court_case_id FROM pf_mdt_case_submissions WHERE id = ?', { subId })
        return { ok = true, submissionId = subId, state = state, message = message, key = key,
            courtCaseId = type(after) == 'table' and int(after.court_case_id, 1) or nil }
    end)
end

function Cases.WithdrawSubmission(actor, data)
    local subId = int(data.submissionId, 1, 2147483647)
    if not subId then return err('bad_args', 'Unknown submission') end
    local sub = db('single', 'SELECT id, case_id, state, by_cid FROM pf_mdt_case_submissions WHERE id = ?', { subId })
    if type(sub) ~= 'table' or not sub.id then return err('not_found', 'No such submission') end
    local caseId = int(sub.case_id, 1)
    return withLock('case:' .. caseId, function()
        local row, e = loadCase(caseId)
        if not row then return e end
        if not (canManage(actor, row) or sub.by_cid == actor.cid) then return err('no_permission', 'Only the submitter, the lead or a supervisor withdraws it') end
        local n = db('update', "UPDATE pf_mdt_case_submissions SET state = 'cancelled', updated_at = ? WHERE id = ? AND state IN ('pending', 'refused')", { now(), subId })
        if (tonumber(n) or 0) ~= 1 then return err('invalid_state', 'Only a pending or refused submission can be withdrawn') end
        -- nothing waiting any more: submitted when something was filed, else the investigation is active again
        if row.status == 'ready_for_court' and countOpenSubmissions(caseId) == 0 then
            local filed = count("SELECT COUNT(*) FROM pf_mdt_case_submissions WHERE case_id = ? AND state = 'filed'", { caseId })
            moveStatus(caseId, 'ready_for_court', filed > 0 and 'submitted' or 'active')
        end
        audit(caseId, 'status', actor, { op = 'withdraw', submissionId = subId })
        changed(caseId, { action = 'withdrawn', submissionId = subId })
        return { ok = true, submissionId = subId, state = 'cancelled' }
    end)
end

--- Hands every pending submission to pf-justice once it can take them (named tick: specs call it).
function Cases.SweepSubmissions()
    if not schemaReady() or not started('pf-justice') then return 0 end
    local rows = db('query', "SELECT id, case_id, state, spec, idem_key, by_cid FROM pf_mdt_case_submissions WHERE state = 'pending' ORDER BY id LIMIT 25") or {}
    local filed = 0
    for _, sub in ipairs(rows) do
        local caseId = int(sub.case_id, 1)
        if caseId and not locks['case:' .. caseId] then
            local res = withLock('case:' .. caseId, function()
                local fresh = db('single', 'SELECT id, case_id, state, spec, idem_key, by_cid FROM pf_mdt_case_submissions WHERE id = ?', { sub.id })
                if type(fresh) ~= 'table' or fresh.state ~= 'pending' then return { ok = true } end
                local state = Cases.HandOver(fresh)
                return { ok = true, state = state }
            end)
            if res.state == 'filed' then filed = filed + 1 end
        end
    end
    return filed
end

-- ── incident links (AttachExternalRecord with an incident target) ─────────────

function Cases.IncidentLinks(actor, data)
    local id = refId(data.incidentId, 16)
    if not id then return err('bad_args', 'Bad incident id') end
    local list = {}
    for _, r in ipairs(db('query', 'SELECT id, ref_type, ref_id, note, by_cid, at FROM pf_mdt_incident_links WHERE incident_id = ? ORDER BY id', { id }) or {}) do
        list[#list + 1] = { id = tonumber(r.id), type = r.ref_type, refId = r.ref_id, note = r.note, by = r.by_cid, at = tonumber(r.at) }
    end
    local cases = {}
    for _, r in ipairs(db('query', "SELECT c.id, c.case_no, c.title, c.status FROM pf_mdt_case_links l JOIN pf_mdt_cases c ON c.id = l.case_id WHERE l.ref_type = 'incident' AND l.ref_id = ?", { id }) or {}) do
        cases[#cases + 1] = { id = tonumber(r.id), caseNo = r.case_no, title = r.title, status = r.status }
    end
    return { ok = true, links = list, cases = cases }
end

-- ── export: AttachExternalRecord ────────────────────────────────────────────

local warned = {}
local function callerAllowed(name)
    local invoker = GetInvokingResource()
    if invoker == nil or invoker == GetCurrentResourceName() then return true, invoker end
    local list = Cases.Cfg().Callers
    if list == '*' or (type(list) == 'table' and list[invoker] == true) then return true, invoker end
    local t = os.time()
    if not warned[invoker] or t - warned[invoker] >= 60 then
        warned[invoker] = t
        print(('^3[pf-policemdt]^7 %s refused for resource %s (Config.Cases.Callers)'):format(name, tostring(invoker)))
    end
    return false, invoker
end

--- AttachExternalRecord(target, ref, opts): target = { caseId } | { incidentId },
--- ref = { type = evidence|custody|order|death_record|citation|telemetry, id }, opts = { note?, actor? }.
--- The same record attached twice answers { ok = true, duplicate = true }.
function Cases.AttachExternalRecord(target, ref, opts)
    local allowed, invoker = callerAllowed('AttachExternalRecord')
    if not allowed then return err('not_allowed', 'This resource may not attach records') end
    if not schemaReady() then return err('db_unavailable', 'The MDT database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    if type(target) ~= 'table' or type(ref) ~= 'table' then return err('bad_args', 'target and ref must be tables') end
    local refType = type(ref.type) == 'string' and ref.type or nil
    if not refType or not Cases.ExternalTypes[refType] then return err('bad_args', 'Unknown record type') end
    local id = refId(ref.id)
    if not id then return err('bad_args', 'Bad record id') end
    local note = text(opts.note, 255)
    -- who attached it: a player read from the server, else the calling resource
    local byCid = 'system:' .. tostring(invoker or GetCurrentResourceName())
    local actor = { cid = byCid, job = nil }
    if type(opts.actor) == 'table' and opts.actor.src ~= nil then
        local P = QBCore.Functions.GetPlayer(int(opts.actor.src, 1, 65535) or -1)
        if P and P.PlayerData then actor = { cid = P.PlayerData.citizenid, job = P.PlayerData.job and P.PlayerData.job.name } byCid = actor.cid end
    end
    if target.caseId ~= nil then
        local caseId = int(target.caseId, 1, 2147483647)
        if not caseId then return err('bad_args', 'Unknown case') end
        return withLock('case:' .. caseId, function()
            local row, e = loadCase(caseId)
            if not row then return e end
            local existing = findLink(row.id, refType, id)
            if existing then return { ok = true, duplicate = true, linkId = existing } end
            if linkCount(row.id) >= Cases.Cfg().MaxLinks then return err('conflict', 'This case has too many linked records') end
            local linkId = int(db('insert', 'INSERT INTO pf_mdt_case_links (case_id, ref_type, ref_id, note, by_cid, at) VALUES (?, ?, ?, ?, ?, ?)',
                { row.id, refType, id, note, byCid, now() }), 1)
            if not linkId then return err('db_unavailable', 'The record could not be attached') end
            touch(row.id)
            audit(row.id, 'update', actor, { op = 'attach', type = refType, id = id, by = invoker })
            changed(row.id, { action = 'attached', type = refType, refId = id })
            return { ok = true, linkId = linkId }
        end)
    elseif target.incidentId ~= nil then
        local incident
        if type(target.incidentId) == 'number' then
            incident = db('scalar', 'SELECT incidentId FROM pf_mdt_incidents WHERE id = ? AND deleted_at IS NULL', { int(target.incidentId, 1) or -1 })
        else
            local iid = refId(target.incidentId, 16)
            if not iid then return err('bad_args', 'Bad incident id') end
            incident = db('scalar', 'SELECT incidentId FROM pf_mdt_incidents WHERE incidentId = ? AND deleted_at IS NULL', { iid })
        end
        if type(incident) ~= 'string' then return err('not_found', 'No such incident') end
        return withLock('incident:' .. incident, function()
            local existing = int(db('scalar', 'SELECT id FROM pf_mdt_incident_links WHERE incident_id = ? AND ref_type = ? AND ref_id = ? LIMIT 1', { incident, refType, id }), 1)
            if existing then return { ok = true, duplicate = true, linkId = existing } end
            local linkId = int(db('insert', 'INSERT INTO pf_mdt_incident_links (incident_id, ref_type, ref_id, note, by_cid, at) VALUES (?, ?, ?, ?, ?, ?)',
                { incident, refType, id, note, byCid, now() }), 1)
            if not linkId then return err('db_unavailable', 'The record could not be attached') end
            db('insert', 'INSERT INTO pf_mdt_record_audit (entity, entity_id, action, by_cid, by_job, detail, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
                { 'incident', incident, 'update', actor.cid, actor.job, json.encode({ op = 'attach', type = refType, id = id, by = invoker }), now() })
            return { ok = true, linkId = linkId }
        end)
    end
    return err('bad_args', 'target needs caseId or incidentId')
end

exports('AttachExternalRecord', function(target, ref, opts)
    local ok, res = pcall(Cases.AttachExternalRecord, target, ref, opts)
    if not ok then
        print(('^1[pf-policemdt]^7 AttachExternalRecord failed: %s'):format(tostring(res)))
        return err('db_unavailable', 'The record could not be attached')
    end
    return res
end)

-- ── endpoints ───────────────────────────────────────────────────────────────

endpoint('pf_mdt:cases:list', false, Cases.List)
endpoint('pf_mdt:cases:get', false, Cases.Get)
endpoint('pf_mdt:cases:incidentLinks', false, Cases.IncidentLinks)
endpoint('pf_mdt:cases:create', true, Cases.Create)
endpoint('pf_mdt:cases:update', true, Cases.Update)
endpoint('pf_mdt:cases:setStatus', true, Cases.SetStatus)
endpoint('pf_mdt:cases:setLead', true, Cases.SetLead)
endpoint('pf_mdt:cases:link', true, Cases.Link)
endpoint('pf_mdt:cases:unlink', true, Cases.Unlink)
endpoint('pf_mdt:cases:addPerson', true, Cases.AddPerson)
endpoint('pf_mdt:cases:removePerson', true, Cases.RemovePerson)
endpoint('pf_mdt:cases:addEntry', true, Cases.AddEntry)
endpoint('pf_mdt:cases:setEntryStatus', true, Cases.SetEntryStatus)
endpoint('pf_mdt:cases:submit', true, Cases.Submit)
endpoint('pf_mdt:cases:withdrawSubmission', true, Cases.WithdrawSubmission)

-- ── deleted characters ──────────────────────────────────────────────────────
-- The case keeps that someone was involved, not who: the person row loses its citizen id and name,
-- and a submission still waiting for the court is cancelled. Filed submissions are court records.
function Cases.ForgetCharacter(cid)
    cid = cidOf(cid)
    if not cid or not schemaReady() then return false end
    db('update', "UPDATE pf_mdt_case_people SET citizenid = NULL, name = 'Deleted character' WHERE citizenid = ?", { cid })
    db('update', "UPDATE pf_mdt_case_submissions SET state = 'cancelled', last_error = 'character deleted', updated_at = ? WHERE citizenid = ? AND state IN ('pending', 'refused')", { now(), cid })
    return true
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    pcall(Cases.ForgetCharacter, citizenid)
end)

-- pf-justice (re)started: pending submissions may be taken now
AddEventHandler('onResourceStart', function(res)
    if res == 'pf-justice' then CreateThread(function() Wait(2000) Cases.SweepSubmissions() end) end
end)

CreateThread(function()
    if PFMdtSchema and not PFMdtSchema.WaitReady() then return end
    while true do
        Wait(Cases.Cfg().SweepSeconds * 1000)
        local ok, e = pcall(Cases.SweepSubmissions)
        if not ok then print(('^1[pf-policemdt]^7 case submission sweep failed: %s'):format(tostring(e))) end
    end
end)
