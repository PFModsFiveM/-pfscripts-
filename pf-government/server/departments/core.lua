-- =====================================================
-- DEPARTMENTS: CORE (membership, managers, audit)
-- =====================================================
-- The public-service departments (police, ems, corrections, doj, government, dot) as pf-government
-- sees them (owner decision D13). Membership and rank always come from the live pfm-core job (ranks,
-- hiring and firing stay in pfm-management); this module adds what a job alone cannot hold:
--   * qualifications (server/departments/qualifications.lua): implied by grade, granted or revoked
--     by department managers;
--   * shifts (server/departments/shifts.lua): one row per stretch on duty;
--   * the department audit (pf_gov_dept_audit, written here).
--
-- Exports (architecture 4.12): GetDepartmentOf (here), HasQualification, ListQualifications,
-- GrantQualification, RevokeQualification, GetShift, ListShifts, LogDepartmentAudit (here).
-- Writes and private reads check GetInvokingResource() against Config.Departments.Callers; this
-- resource itself (no invoker) always passes. Internal callers use GovDept.* directly.

GovDept = GovDept or {}
local D = GovDept
D.U = D.U or {}
local U = D.U

function D.Cfg() return Config.Departments or {} end
local cfg = D.Cfg

-- ── small helpers shared by the department files ────────────────────────

function U.now() return os.time() end

function U.fail(code, message, extra)
    local r = { ok = false, error = code, message = message }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end

function U.int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n)
    if not n or n < min or n > max then return nil end
    return n
end

function U.validCid(c)
    return type(c) == 'string' and #c >= 1 and #c <= 64 and c:match('^[%w]+$') ~= nil
end

function U.validKey(k)
    return type(k) == 'string' and #k >= 1 and #k <= 128 and k:match('^[%w%-_:%.]+$') ~= nil
end

function U.cleanText(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

--- Same test as pfm-core: values from other resources arrive as funcrefs (tables), never functions.
function U.callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

function U.dbReady() return GovSchema and GovSchema.Ensure and GovSchema.Ensure() == true end

function U.started(res) return GetResourceState(res) == 'started' end

-- ── per-entity locks (taken before the first database wait) ─────────────

local locks = {}
D.locks = locks

--- Runs fn holding every named lock; `busy` when one is held. Errors become db_unavailable.
function U.withLocks(names, fn)
    for _, n in ipairs(names) do
        if locks[n] then return U.fail('busy', 'This record is being updated. Try again.') end
    end
    for _, n in ipairs(names) do locks[n] = true end
    local ok, res = pcall(fn)
    for _, n in ipairs(names) do locks[n] = nil end
    if not ok then
        print('^1[PF-GOVERNMENT]^7 department action failed: ' .. tostring(res))
        return U.fail('db_unavailable', 'Department records are unavailable right now. Nothing was changed.')
    end
    return res
end

-- ── caller allowlists (architecture 3.4) ────────────────────────────────

local warned = {}

--- True when the invoking resource may use export `name`. Exports not listed in Callers are open.
function U.callerAllowed(name)
    local inv = GetInvokingResource()
    if inv == nil or inv == GetCurrentResourceName() then return true, nil end
    local list = (cfg().Callers or {})[name]
    if list == nil or list == '*' then return true, inv end
    if type(list) == 'table' and list[inv] == true then return true, inv end
    local t, k = U.now(), name .. ':' .. inv
    if not warned[k] or t - warned[k] >= 60 then
        warned[k] = t
        print(('^3[PF-GOVERNMENT]^7 %s refused for %s (not in Config.Departments.Callers)'):format(name, inv))
    end
    return false, inv
end

function U.notAllowed() return U.fail('not_allowed', 'This resource may not use that department export.') end

-- ── departments and membership ──────────────────────────────────────────

--- Every department id the config knows (job map targets and labels).
function D.IsDept(dept)
    if type(dept) ~= 'string' or #dept > 16 then return false end
    local c = cfg()
    if (c.Labels or {})[dept] then return true end
    for _, d in pairs(c.Jobs or {}) do if d == dept then return true end end
    return false
end

function D.DeptOfJob(jobName)
    if type(jobName) ~= 'string' then return nil end
    return (cfg().Jobs or {})[jobName]
end

function U.getPlayer(src)
    if not QBCore or not QBCore.Functions then return nil end
    return QBCore.Functions.GetPlayer(src)
end

function U.getPlayerByCid(cid)
    if not QBCore or not QBCore.Functions or not U.validCid(cid) then return nil end
    return QBCore.Functions.GetPlayerByCitizenId(cid)
end

--- The member view of a live job: { cid, src, job, grade, onDuty, isBoss, dept, manager }.
local function memberOf(pd, src)
    local job = pd.job or {}
    local grade = type(job.grade) == 'table' and (tonumber(job.grade.level) or 0) or (tonumber(job.grade) or 0)
    local m = {
        cid = pd.citizenid, src = src, job = job.name, grade = math.tointeger(grade) or 0,
        onDuty = job.onduty == true, isBoss = job.isboss == true or (type(job.grade) == 'table' and job.grade.isboss == true),
        dept = D.DeptOfJob(job.name),
    }
    local need = m.job and (cfg().ManagerGrade or {})[m.job]
    m.manager = m.dept ~= nil and tonumber(need) ~= nil and m.grade >= tonumber(need)
    return m
end

--- The live member view of an online player (read fresh: a player object is a snapshot).
function D.Member(src)
    src = U.int(src, 1, 65535)
    local P = src and U.getPlayer(src)
    if not P or not P.PlayerData then return nil end
    return memberOf(P.PlayerData, src)
end

--- The member view of a citizen: live when online, else the saved job in pfm-core's players row.
--- Returns nil when the citizen does not exist; false, 'db' when the database did not answer.
function D.MemberByCid(cid)
    if not U.validCid(cid) then return nil end
    local P = U.getPlayerByCid(cid)
    if P and P.PlayerData then return memberOf(P.PlayerData, P.PlayerData.source) end
    local ok, raw = pcall(MySQL.scalar.await, 'SELECT job FROM players WHERE citizenid = ? LIMIT 1', { cid })
    if not ok then return false, 'db' end
    if raw == nil then return nil end
    local job = type(raw) == 'string' and json.decode(raw) or raw
    if type(job) ~= 'table' then job = {} end
    -- an offline citizen is never on duty
    job.onduty = false
    return memberOf({ citizenid = cid, job = job }, nil)
end

--- Department of a server id (its live job) or of a job name.
function D.GetDepartmentOf(srcOrJob)
    if type(srcOrJob) == 'number' then
        local m = D.Member(srcOrJob)
        return m and m.dept or nil
    end
    if type(srcOrJob) ~= 'string' or #srcOrJob > 50 then return nil end
    return D.DeptOfJob(srcOrJob)
end

--- True when `m` (a member view) manages department `dept` (Config.Departments.ManagerGrade).
function D.IsManager(m, dept)
    return type(m) == 'table' and m.manager == true and m.dept == dept
end

-- ── actors (architecture 3.5) ───────────────────────────────────────────

--- Normalises opts.actor: { kind = 'player'|'admin'|'system', src?, cid?, member?, label }.
--- A player's job and grade are read here from the server, never taken from the caller.
--- System actors are accepted only from this resource itself (invoker nil).
function D.ResolveActor(actor, invoker)
    if type(actor) ~= 'table' then return nil, U.fail('bad_args', 'An actor is required.') end
    if actor.kind == 'system' then
        if invoker ~= nil then return nil, U.fail('no_permission', 'Only pf-government may act as the system.') end
        return { kind = 'system', label = U.cleanText(actor.label, 48) or 'system' }
    end
    local src = U.int(actor.src, 1, 65535)
    if not src then return nil, U.fail('bad_args', 'Invalid actor.') end
    local m = D.Member(src)
    if not m then return nil, U.fail('offline', 'The acting player is not online.') end
    if actor.kind == 'admin' then
        if not IsPlayerAceAllowed(tostring(src), 'command') then
            return nil, U.fail('no_permission', 'You are not an administrator.')
        end
        return { kind = 'admin', src = src, cid = m.cid, member = m, label = 'admin' }
    end
    return { kind = 'player', src = src, cid = m.cid, member = m }
end

-- ── department audit (architecture 3.8) ─────────────────────────────────

local MAX_DETAIL = 4096

local function encodeDetail(detail)
    if detail == nil then return nil end
    if type(detail) ~= 'table' then detail = { note = U.cleanText(tostring(detail), 500) } end
    local ok, s = pcall(json.encode, detail)
    if not ok or type(s) ~= 'string' then return nil end
    if #s > MAX_DETAIL then
        s = json.encode({ truncated = true, size = #s })
    end
    return s
end

--- One pf_gov_dept_audit row. actorCid and resource may be nil. Returns the row id, or nil.
function D.Audit(dept, action, actorCid, target, detail, resource)
    local ok, id = pcall(MySQL.insert.await,
        'INSERT INTO pf_gov_dept_audit (dept, action, actor_cid, actor_resource, target, detail, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { dept, action, actorCid, resource, target, encodeDetail(detail), U.now() })
    if not ok then
        print(('^1[PF-GOVERNMENT]^7 department audit %s/%s not written: %s'):format(tostring(dept), tostring(action), tostring(id)))
        return nil
    end
    return id
end

--- LogDepartmentAudit(dept, action, actor, target, detail) for listed department resources.
--- actor: a citizen id, { src } (read on the server) or { kind = 'system', label } / nil.
function D.LogAudit(dept, action, actor, target, detail, invoker)
    if not D.IsDept(dept) then return U.fail('bad_args', 'Unknown department.') end
    if type(action) ~= 'string' or #action < 1 or #action > 32 or not action:match('^[%w_%.%-]+$') then
        return U.fail('bad_args', 'Invalid audit action.')
    end
    local actorCid
    if type(actor) == 'string' then
        if not U.validCid(actor) then return U.fail('bad_args', 'Invalid actor.') end
        actorCid = actor
    elseif type(actor) == 'table' and actor.src ~= nil then
        local m = D.Member(actor.src)
        if not m then return U.fail('bad_args', 'Invalid actor.') end
        actorCid = m.cid
    elseif actor ~= nil and not (type(actor) == 'table' and actor.kind == 'system') then
        return U.fail('bad_args', 'Invalid actor.')
    end
    local tgt
    if target ~= nil then
        if type(target) == 'number' then target = tostring(math.tointeger(target) or target) end
        tgt = U.cleanText(target, 64)
        if not tgt then return U.fail('bad_args', 'Invalid audit target.') end
    end
    if detail ~= nil and type(detail) ~= 'table' and type(detail) ~= 'string' then
        return U.fail('bad_args', 'Invalid audit detail.')
    end
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local id = D.Audit(dept, action, actorCid, tgt, detail, invoker and invoker:sub(1, 48) or nil)
    if not id then return U.fail('db_unavailable', 'The audit row could not be written.') end
    return { ok = true, id = id }
end

-- ── retention (daily, batches of 500) ───────────────────────────────────

D.SWEEP_BATCH = 500

--- Deletes audit rows older than AuditRetentionDays and ended shifts older than ShiftRetentionDays.
--- Returns { audit = n, shifts = n }. Each table stops after `maxBatches` batches per call.
function D.Sweep(maxBatches)
    maxBatches = maxBatches or 20
    local out = { audit = 0, shifts = 0 }
    if not U.dbReady() then return out end
    local t = U.now()
    local jobs = {
        { 'audit', 'DELETE FROM pf_gov_dept_audit WHERE at < ? LIMIT ' .. D.SWEEP_BATCH, cfg().AuditRetentionDays },
        { 'shifts', 'DELETE FROM pf_gov_dept_shifts WHERE ended_at IS NOT NULL AND ended_at < ? LIMIT ' .. D.SWEEP_BATCH, cfg().ShiftRetentionDays },
    }
    for _, j in ipairs(jobs) do
        local days = U.int(j[3] or 180, 1, 36500) or 180
        local cutoff = t - days * 86400
        for _ = 1, maxBatches do
            local ok, n = pcall(MySQL.update.await, j[2], { cutoff })
            n = ok and (tonumber(n) or 0) or 0
            out[j[1]] = out[j[1]] + n
            if n < D.SWEEP_BATCH then break end
        end
    end
    return out
end

local lastSweep = 0
--- Hourly check; sweeps once per 24 h.
function D.SweepTick()
    local t = U.now()
    if t - lastSweep < 86400 then return false end
    lastSweep = t
    D.Sweep()
    return true
end

CreateThread(function()
    Wait(60000)
    while true do
        pcall(D.SweepTick)
        Wait(3600000)
    end
end)

-- ── deleted characters ──────────────────────────────────────────────────

--- Removes a deleted character's qualification and shift rows (audit rows age out by retention).
function D.RemoveCharacter(cid)
    if not U.validCid(cid) then return nil end
    local out = {}
    for name, sql in pairs({
        qualifications = 'DELETE FROM pf_gov_dept_qualifications WHERE citizenid = ?',
        shifts = 'DELETE FROM pf_gov_dept_shifts WHERE citizenid = ?',
    }) do
        local ok, n = pcall(MySQL.update.await, sql, { cid })
        out[name] = ok and (tonumber(n) or 0) or false
        if not ok then print(('^1[PF-GOVERNMENT]^7 department cleanup (%s) of %s failed: %s'):format(name, cid, tostring(n))) end
    end
    if D.Q and D.Q.Forget then D.Q.Forget(cid) end
    return out
end

-- pfm-core raises it after removing the character; a client cannot (no RegisterNetEvent), and a
-- call carrying a player source is ignored like in server/characters.lua.
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    D.RemoveCharacter(citizenid)
end)

-- ── exports ─────────────────────────────────────────────────────────────

exports('GetDepartmentOf', function(srcOrJob) return D.GetDepartmentOf(srcOrJob) end)

exports('LogDepartmentAudit', function(dept, action, actor, target, detail)
    local allowed, inv = U.callerAllowed('LogDepartmentAudit')
    if not allowed then return U.notAllowed() end
    return D.LogAudit(dept, action, actor, target, detail, inv)
end)
