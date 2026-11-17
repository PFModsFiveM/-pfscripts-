-- =====================================================
-- DEPARTMENTS: TRAINING (batch 20, unit 20E)
-- =====================================================
-- One pf_gov_dept_training row per training session of an employee (Config.Departments.Training).
-- A pass of a course with `grants` grants that qualification through the qualification store
-- (GovDept.Q.Grant, source 'training', the system actor of this resource), never by writing the
-- qualification table here. The grant has its own key (pf-government:training:<id>:grant), so a
-- replay of the training key finishes a grant that failed the first time and never grants twice.
--
-- Who may record (read on the server): the instructor works for the course's department, is on
-- duty, and manages it or holds the course's instructorQual; the trainee works for the department;
-- nobody records their own training. Admins (ACE) may record for anyone in the department.
--
-- Exports: RecordTraining(cid, course, result, opts), ListTraining(cid, filter), both through
-- Config.Departments.Callers.

GovDept = GovDept or {}
local D = GovDept
local U = D.U
D.T = D.T or {}
local T = D.T

local RESULTS = { pass = true, fail = true, in_progress = true }
T.RESULTS = RESULTS

local function tcfg() return D.Cfg().Training or {} end

function T.Course(course)
    if type(course) ~= 'string' or #course > 32 then return nil end
    return (tcfg().Courses or {})[course]
end

--- The courses of a department: { { id, label, grants?, grantsLabel?, instructorQual?, validDays? } }.
function T.Courses(dept)
    local out = {}
    for id, c in pairs(tcfg().Courses or {}) do
        if c.dept == dept then
            local q = c.grants and D.Q.Def(c.grants)
            out[#out + 1] = { id = id, label = c.label or id, grants = c.grants, grantsLabel = q and q.label or nil,
                instructorQual = c.instructorQual, validDays = c.validDays }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function grantKey(id) return ('pf-government:training:%d:grant'):format(id) end

--- Grants the course's qualification for a passed training row through the qualification store.
--- Returns granted:boolean, error code?.
local function applyGrant(row, course)
    local qual = row.grants_qual
    if not qual or row.result ~= 'pass' then return false end
    if tonumber(row.qual_granted) == 1 then return true end
    local opts = { actor = { kind = 'system', label = 'training' }, source = 'training', key = grantKey(tonumber(row.id)),
        reason = 'Training: ' .. tostring(course and course.label or row.course) }
    local expires = tonumber(row.expires_at)
    if expires then opts.expiresAt = expires end
    -- invoker nil: this resource itself, the only caller allowed to act as the system
    local res = D.Q.Grant(row.citizenid, qual, opts, nil)
    if type(res) == 'table' and res.ok then
        MySQL.update.await('UPDATE pf_gov_dept_training SET qual_granted = 1 WHERE id = ?', { row.id })
        return true
    end
    return false, type(res) == 'table' and res.error or 'db_unavailable'
end

local function rowView(r)
    local c = T.Course(r.course)
    return {
        id = tonumber(r.id), cid = r.citizenid, dept = r.dept, course = r.course, courseLabel = c and c.label or r.course,
        result = r.result, score = tonumber(r.score), instructor = r.instructor_cid, qual = r.grants_qual,
        granted = tonumber(r.qual_granted) == 1, expiresAt = tonumber(r.expires_at), note = r.note, at = tonumber(r.at),
    }
end
T.View = rowView

--- RecordTraining(cid, course, result, opts); opts = { key, actor, score?, note? }.
--- -> { ok, id, granted, qual?, expiresAt?, grantError?, duplicate? }
function T.Record(cid, courseId, result, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    if not U.validCid(cid) then return U.fail('bad_args', 'Invalid citizen id.') end
    local course = T.Course(courseId)
    if not course or not D.IsDept(course.dept) then return U.fail('bad_args', 'Unknown course.') end
    if not RESULTS[result] then return U.fail('bad_args', 'The result is pass, fail or in_progress.') end
    local key = opts.key
    if not U.validKey(key) then return U.fail('bad_args', 'A valid key is required.') end
    local score
    if opts.score ~= nil then
        score = U.int(opts.score, 0, 100)
        if not score then return U.fail('bad_args', 'The score must be 0 to 100.') end
    end
    local note
    if opts.note ~= nil then
        note = U.cleanText(opts.note, 255)
        if not note then return U.fail('bad_args', 'Invalid note.') end
    end
    local dept = course.dept
    if course.grants and not D.Q.Def(course.grants) then return U.fail('bad_args', 'The course grants an unknown qualification.') end

    local actor, aerr = D.ResolveActor(opts.actor, invoker)
    if not actor then return aerr end
    if actor.kind == 'system' then return U.fail('no_permission', 'Training is recorded by an instructor.') end
    if actor.cid == cid then return U.fail('no_permission', 'You cannot record your own training.') end
    if actor.kind == 'player' then
        local m = actor.member
        if m.dept ~= dept then return U.fail('no_permission', 'You do not work for this department.') end
        if not m.onDuty then return U.fail('not_on_duty', 'You must be on duty.') end
        if not D.IsManager(m, dept) then
            if not course.instructorQual or not D.Q.Has(m.cid, course.instructorQual) then
                return U.fail('no_permission', 'You are not qualified to instruct this course.')
            end
        end
    end

    return U.withLocks({ 'dtk:' .. key, 'dt:' .. cid }, function()
        if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
        local prior = MySQL.single.await([[SELECT id, citizenid, dept, course, result, score, instructor_cid, grants_qual, qual_granted,
            expires_at, note, at FROM pf_gov_dept_training WHERE idem_key = ? LIMIT 1]], { key })
        if prior then
            if prior.citizenid ~= cid or prior.course ~= courseId or prior.result ~= result then
                return U.fail('key_reused', 'This key was used for a different training record.')
            end
            -- the same record again: finish a grant that did not go through the first time
            local granted, gerr = applyGrant(prior, course)
            return { ok = true, duplicate = true, id = tonumber(prior.id), granted = granted, qual = prior.grants_qual,
                expiresAt = tonumber(prior.expires_at), grantError = gerr }
        end
        local target = D.MemberByCid(cid)
        if target == false then error('players lookup failed') end
        if not target then return U.fail('not_found', 'No such citizen.') end
        if target.dept ~= dept then return U.fail('invalid_state', 'This citizen does not work for this department.') end

        local t = U.now()
        local grants = result == 'pass' and course.grants or nil
        local days = U.int(course.validDays, 1, 3650)
        local expiresAt = (result == 'pass' and days) and (t + days * 86400) or nil
        local ok, id = pcall(MySQL.insert.await, [[INSERT INTO pf_gov_dept_training
            (citizenid, dept, course, result, score, instructor_cid, grants_qual, qual_granted, expires_at, note, at, idem_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)]],
            { cid, dept, courseId, result, score, actor.cid, grants, expiresAt, note, t, key })
        if not ok then
            if tostring(id):lower():find('duplicate', 1, true) then
                return U.fail('key_reused', 'This key was used for a different training record.')
            end
            error(id)
        end
        D.Audit(dept, 'training_record', actor.cid, cid, {
            course = courseId, result = result, score = score, grants = grants, key = key, actorKind = actor.kind,
        }, invoker and invoker:sub(1, 48) or nil)
        local row = { id = id, citizenid = cid, course = courseId, result = result, grants_qual = grants, qual_granted = 0, expires_at = expiresAt }
        local granted, gerr = applyGrant(row, course)
        TriggerEvent('pf-government:server:trainingRecorded', { id = id, cid = cid, dept = dept, course = courseId, result = result, granted = granted })
        if target.src then
            local msg = ('Training recorded: %s (%s)'):format(course.label or courseId, result:gsub('_', ' '))
            TriggerClientEvent('QBCore:Notify', target.src, msg, result == 'pass' and 'success' or 'primary')
        end
        return { ok = true, id = id, granted = granted, qual = grants, expiresAt = expiresAt, grantError = gerr }
    end)
end

--- ListTraining(cid, filter): filter = { dept?, limit 1..100 } -> { ok, list } (newest first).
function T.List(cid, filter)
    filter = type(filter) == 'table' and filter or {}
    local where, params = {}, {}
    if cid ~= nil then
        if not U.validCid(cid) then return U.fail('bad_args', 'Invalid citizen id.') end
        where[#where + 1] = 'citizenid = ?'; params[#params + 1] = cid
    end
    if filter.dept ~= nil then
        if not D.IsDept(filter.dept) then return U.fail('bad_args', 'Unknown department.') end
        where[#where + 1] = 'dept = ?'; params[#params + 1] = filter.dept
    end
    if #where == 0 then return U.fail('bad_args', 'A citizen or a department is required.') end
    if filter.beforeId ~= nil then
        local before = U.int(filter.beforeId, 1, 2147483647)
        if not before then return U.fail('bad_args', 'Invalid cursor.') end
        where[#where + 1] = 'id < ?'; params[#params + 1] = before
    end
    local limit = 50
    if filter.limit ~= nil then
        limit = U.int(filter.limit, 1, 100)
        if not limit then return U.fail('bad_args', 'The limit must be 1 to 100.') end
    end
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local ok, rows = pcall(MySQL.query.await, [[SELECT id, citizenid, dept, course, result, score, instructor_cid, grants_qual,
        qual_granted, expires_at, note, at FROM pf_gov_dept_training WHERE ]] .. table.concat(where, ' AND ')
        .. ' ORDER BY id DESC LIMIT ' .. limit, params)
    if not ok or type(rows) ~= 'table' then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = rowView(r) end
    return { ok = true, list = list, nextCursor = #list == limit and list[#list].id or nil }
end

-- a deleted character's training history goes with their qualifications (core.lua removes those)
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if not U.validCid(citizenid) or not U.dbReady() then return end
    local ok, err = pcall(MySQL.update.await, 'DELETE FROM pf_gov_dept_training WHERE citizenid = ?', { citizenid })
    if not ok then print('^1[PF-GOVERNMENT]^7 training cleanup of ' .. citizenid .. ' failed: ' .. tostring(err)) end
end)

-- ── exports ─────────────────────────────────────────────────────────────

exports('RecordTraining', function(cid, course, result, opts)
    local allowed, inv = U.callerAllowed('RecordTraining')
    if not allowed then return U.notAllowed() end
    return T.Record(cid, course, result, opts, inv)
end)

exports('ListTraining', function(cid, filter)
    local allowed = U.callerAllowed('ListTraining')
    if not allowed then return U.notAllowed() end
    return T.List(cid, filter)
end)
