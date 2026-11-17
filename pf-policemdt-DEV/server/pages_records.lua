-- ============================================================================
-- PF Police MDT - reads for the records pages (batch 21, unit 21A)
-- ============================================================================
-- Two reads the case and citation pages (html/pages/cases.js, citations.js) need from other owners:
--   pf_mdt:cases:deathRecord { caseId, linkId }
--       The death record a case links to (the morgue attached it with AttachExternalRecord). The
--       link must belong to that case and be a death_record link; the record is read from its owner,
--       exports['pf-ambulancejob']:GetDeathRecord(id) (this resource is on that export's allowlist),
--       and only what the record view shows is returned. Every read writes a pf_mdt_record_audit row
--       (entity 'case', action 'read', detail op = 'death_record'), every time: a medical record
--       read is never deduplicated.
--   pf_mdt:citations:list { citizenId, after?, limit? }
--       A citizen's citations. pf-justice owns them: the order (state, amount, paid, due date) comes
--       from exports['pf-justice']:GetOrders(cid, { kinds = { 'citation' }, limit = 100 }) and the
--       citation detail (violation, plate, speed, officer, contest deadline) from pf-justice's
--       pf_justice_citations row of each order. Paged by order id (`after` = the last id shown).
--       Field citations pfm-policejob wrote but pf-justice has not taken yet (pf_police_citations
--       'pending' / 'failed') are listed apart on the first page, never as court orders.
-- Both are reads for on-duty police (server/access.lua gates every pf_mdt: name to police jobs;
-- duty is checked here). Answers: { ok = true, success = true, ... } or { ok = false, error, message }.

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtPagesRecords = PFMdtPagesRecords or {}
local P = PFMdtPagesRecords
local Access = PFMdtAccess

P.RATE_MS = 500
P.PAGE = 20
P.MAX_ORDERS = 100 -- pf-justice GetOrders answers at most 100 rows

local function err(code, message) return { ok = false, success = false, error = code, message = message } end
local function started(res) return GetResourceState(res) == 'started' end

local function int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n)
    if not n or (min and n < min) or (max and n > max) then return nil end
    return n
end

local function cidOf(v)
    if type(v) ~= 'string' or #v < 1 or #v > 64 or not v:match('^[%w_%-]+$') then return nil end
    return v
end

local function db(kind, sql, params)
    local ok, res = pcall(function() return MySQL[kind].await(sql, params or {}) end)
    if not ok then
        print(('^1[pf-policemdt]^7 pages_records: query failed: %s'):format(tostring(res)))
        return nil, false
    end
    return res, true
end

local function decode(s)
    if type(s) == 'table' then return s end
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

-- One call into another resource's export; nil, 'unavailable' when it is not running or broke off.
local function call(res, name, ...)
    if not started(res) then return nil, 'unavailable' end
    local n, args = select('#', ...), { ... }
    local ok, out = pcall(function()
        local e = exports[res]
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok then
        print(('^3[pf-policemdt]^7 pages_records: %s:%s failed: %s'):format(res, name, tostring(out)))
        return nil, 'unavailable'
    end
    return out
end
P.Call = call

-- The calling officer: police job (the gate), on duty (here). Returns actor | nil, refusal.
function P.Actor(src)
    local job, Pl = Access.Job(src)
    if not job or not Pl or not (Config.AllowedJobs and Config.AllowedJobs[job.name]) then return nil, err('no_access', 'Police only') end
    if not job.onduty then return nil, err('not_on_duty', 'You must be on duty to read this') end
    local ci = Pl.PlayerData.charinfo or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
    return { src = src, cid = Pl.PlayerData.citizenid, name = name ~= '' and name or Pl.PlayerData.citizenid, job = job.name, grade = job.grade }
end

local function auditRow(entity, entityId, actor, detail)
    local d = json.encode(detail or {})
    if #d > 4000 then d = d:sub(1, 4000) end
    return db('insert', 'INSERT INTO pf_mdt_record_audit (entity, entity_id, action, by_cid, by_job, detail, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { entity, tostring(entityId), 'read', actor.cid, actor.job, d, os.time() })
end

-- citizen id -> display name (players rows; one query)
local function namesFor(cids)
    local list, seen, out = {}, {}, {}
    for _, c in ipairs(cids) do if cidOf(c) and not seen[c] then seen[c] = true; list[#list + 1] = c end end
    if #list == 0 then return out end
    local marks = string.rep('?,', #list):sub(1, -2)
    for _, r in ipairs(db('query', ('SELECT citizenid, charinfo FROM players WHERE citizenid IN (%s)'):format(marks), list) or {}) do
        local ci = decode(r.charinfo) or {}
        local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
        if name ~= '' then out[r.citizenid] = name end
    end
    return out
end

-- ── death record of a case ──────────────────────────────────────────────────

local TEXT_MAX = 300
local function clip(v, n)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v):gsub('%c', ' ')
    return s:sub(1, n or TEXT_MAX)
end

-- The record as the case page shows it: no raw engine rows, no intake snapshot.
function P.DeathRecordView(r)
    if type(r) ~= 'table' then return nil end
    local f = type(r.findings) == 'table' and r.findings or {}
    local a = type(f.autopsy) == 'table' and f.autopsy or nil
    local view = {
        id = int(r.id, 1), cid = cidOf(r.cid), state = clip(r.state, 16), cause = clip(r.cause), manner = clip(r.manner, 32),
        todText = clip(r.todText, 64), todFrom = int(r.todFrom), todTo = int(r.todTo), examined = a ~= nil,
        examinerCid = cidOf(r.examiner), createdAt = int(r.createdAt), releasedAt = int(r.releasedAt), hospital = clip(r.hospitalId, 32),
    }
    if a then
        local injuries = {}
        for i, inj in ipairs(type(a.injuries) == 'table' and a.injuries or {}) do
            if i > 20 then break end
            if type(inj) == 'table' then
                injuries[#injuries + 1] = { text = clip(inj.text), region = clip(inj.region, 32), severity = tonumber(inj.severity),
                    lethal = inj.lethal == true, attacker = (inj.attacker == 'self' or inj.attacker == 'other') and inj.attacker or nil }
            end
        end
        local toxins = {}
        for k, v in pairs(type(a.toxins) == 'table' and a.toxins or {}) do
            if type(k) == 'string' and tonumber(v) and #toxins < 10 then toxins[#toxins + 1] = { name = clip(k, 32), level = tonumber(v) } end
        end
        table.sort(toxins, function(x, y) return x.name < y.name end)
        view.autopsy = { injuries = injuries, toxins = toxins, suggestedManner = clip(a.derivedManner, 32), note = clip(a.note, 500),
            examinedAt = int(a.examinedAt) }
    end
    return view
end

function P.DeathRecord(src, data)
    local actor, refusal = P.Actor(src)
    if not actor then return refusal end
    data = type(data) == 'table' and data or {}
    local caseId, linkId = int(data.caseId, 1, 2147483647), int(data.linkId, 1, 2147483647)
    if not caseId or not linkId then return err('bad_args', 'Unknown case or link') end
    local link, ok = db('single', 'SELECT id, case_id, ref_type, ref_id FROM pf_mdt_case_links WHERE id = ? LIMIT 1', { linkId })
    if not ok then return err('db_unavailable', 'The case database did not answer') end
    if type(link) ~= 'table' or not link.id or int(link.case_id) ~= caseId then return err('not_found', 'That record is not linked to this case') end
    if link.ref_type ~= 'death_record' then return err('bad_args', 'That link is not a death record') end
    local recordId = int(link.ref_id, 1, 2147483647)
    if not recordId then return err('not_found', 'The linked death record id is invalid') end
    local res = call('pf-ambulancejob', 'GetDeathRecord', recordId)
    if type(res) ~= 'table' then return err('unavailable', 'The morgue records are not available right now') end
    if not res.ok or type(res.record) ~= 'table' then return err(res.error or 'not_found', res.message or 'The morgue has no such record') end
    local view = P.DeathRecordView(res.record)
    -- the read is written before the answer leaves; a record that cannot be audited is not shown
    local _, audited = auditRow('case', caseId, actor, { op = 'death_record', linkId = linkId, recordId = recordId, citizenid = view.cid })
    if not audited then return err('db_unavailable', 'The read could not be audited; try again') end
    return { ok = true, success = true, caseId = caseId, linkId = linkId, record = view }
end

-- ── citations of a citizen ──────────────────────────────────────────────────

function P.CitationList(src, data)
    local actor, refusal = P.Actor(src)
    if not actor then return refusal end
    data = type(data) == 'table' and data or {}
    local cid = cidOf(data.citizenId or data.cid)
    if not cid then return err('bad_args', 'Pick a citizen') end
    local after = data.after ~= nil and int(data.after, 1, 2147483647) or nil
    if data.after ~= nil and not after then return err('bad_args', 'Bad cursor') end
    local limit = int(data.limit, 1, 50) or P.PAGE
    local res = call('pf-justice', 'GetOrders', cid, { kinds = { 'citation' }, limit = P.MAX_ORDERS })
    if type(res) ~= 'table' then return err('unavailable', 'The court system is not available right now') end
    if not res.ok then return err(res.error or 'db_unavailable', res.message or 'The court system did not answer') end

    -- newest first (pf-justice lists by id descending); the cursor is the last order id shown
    local orders = {}
    for _, o in ipairs(type(res.list) == 'table' and res.list or {}) do
        local id = int(o.id, 1)
        if id and o.kind == 'citation' and (not after or id < after) then orders[#orders + 1] = o end
    end
    table.sort(orders, function(a, b) return int(a.id) > int(b.id) end)
    local page = {}
    for i = 1, math.min(#orders, limit) do page[i] = orders[i] end
    local nextCursor = #orders > limit and int(page[#page].id) or nil

    local details = {}
    if #page > 0 then
        local ids = {}
        for i, o in ipairs(page) do ids[i] = int(o.id) end
        local rows = db('query', ('SELECT order_id, uid, violation, plate, speed_kmh, limit_kmh, officer_cid, contest_until, at FROM pf_justice_citations WHERE order_id IN (%s)')
            :format(string.rep('?,', #ids):sub(1, -2)), ids)
        for _, r in ipairs(type(rows) == 'table' and rows or {}) do details[int(r.order_id)] = r end
    end

    local pending = {}
    if not after then
        -- issued in the field, not (yet) a court order: pfm-policejob retries these with the same key
        local rows = db('query', "SELECT uid, code, violation, amount, plate, officer_cid, state, error, created_at FROM pf_police_citations WHERE citizenid = ? AND state IN ('pending', 'failed') ORDER BY id DESC LIMIT 20", { cid })
        for _, r in ipairs(type(rows) == 'table' and rows or {}) do
            pending[#pending + 1] = { uid = clip(r.uid, 32), code = clip(r.code, 16), violation = clip(r.violation, 64), amount = tonumber(r.amount),
                plate = clip(r.plate, 16), officerCid = cidOf(r.officer_cid), state = clip(r.state, 16), error = clip(r.error, 255), createdAt = int(r.created_at) }
        end
    end

    local cids = {}
    for _, d in pairs(details) do cids[#cids + 1] = d.officer_cid end
    for _, p in ipairs(pending) do cids[#cids + 1] = p.officerCid end
    local names = namesFor(cids)

    local list = {}
    for _, o in ipairs(page) do
        local id = int(o.id)
        local d = details[id] or {}
        local officer = cidOf(d.officer_cid)
        list[#list + 1] = {
            orderId = id, state = clip(o.state, 24), amount = tonumber(o.amount), paidAmount = tonumber(o.paidAmount),
            issuedAt = int(d.at) or int(o.createdAt), dueAt = int(o.dueAt), contestUntil = int(d.contest_until),
            reason = clip(d.violation, 64), uid = clip(d.uid, 32), plate = clip(d.plate, 16),
            speed = int(d.speed_kmh), limit = int(d.limit_kmh),
            officerCid = officer, officerName = officer and names[officer] or nil,
        }
    end
    for _, p in ipairs(pending) do p.officerName = p.officerCid and names[p.officerCid] or nil end

    if Access and PFMdtRecords and Access.Callable and Access.Callable(PFMdtRecords.Audit) then
        PFMdtRecords.Audit(src, 'citizen', cid, 'read', { op = 'citations' })
    end
    return { ok = true, success = true, citizenId = cid, list = list, next = nextCursor, pending = pending }
end

-- ── endpoints ───────────────────────────────────────────────────────────────

P.Endpoints = {
    ['pf_mdt:cases:deathRecord'] = P.DeathRecord,
    ['pf_mdt:citations:list'] = P.CitationList,
}

for name, fn in pairs(P.Endpoints) do
    QBCore.Functions.CreateCallback(name, function(source, cb, data)
        if not Access.Callable(cb) then return end
        local src = tonumber(source)
        local res
        if not src or src <= 0 then
            res = err('bad_args', 'Bad caller')
        elseif not Access.AllowRate(src, 'pagesRecords', P.RATE_MS) then
            res = err('rate_limited', 'Slow down')
        elseif PFMdtSchema and Access.Callable(PFMdtSchema.Ready) and not PFMdtSchema.Ready() then
            res = err('db_unavailable', 'The MDT database is not ready')
        else
            local ok, out = pcall(fn, src, data)
            if ok and type(out) == 'table' then res = out
            else
                print(('^1[pf-policemdt]^7 %s failed: %s'):format(name, tostring(out)))
                res = err('db_unavailable', 'The read failed; try again')
            end
        end
        cb(res)
    end)
end
