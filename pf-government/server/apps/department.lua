-- Department admin app (pf-devices, tablet and computer; batch 20 unit 20E). The handlers behind
-- the department app (the module html/apps/department.js comes in batch 21, unit 21G): roster,
-- qualifications, shifts, training, the asset register, procurements, the budget and payroll.
--
-- Every handler reads the viewer's department, rank and duty from the live pfm-core job on the
-- server (GovDept.Member) and checks the role its action needs; the pf-devices access rule only
-- lets department employees open the app. Managers (Config.Departments.ManagerGrade) see and change
-- their department's records; any employee sees their own. Writes go through the department
-- modules (qualifications, training, assets), which check the role again.
-- Keys: a write carries a client nonce (`key`, 8..64 letters, digits, - or _); the server keys the
-- action as pf-government:app:<viewer cid>:<nonce>, so a resent request never applies twice and
-- one viewer cannot replay another's key.

local A = GovApps
local D = GovDept
local U = D.U

local APP_ID = 'department'
local handlers = {}

local function deny(code, message) return U.fail(code, message) end

--- The viewer's live member view; nil + failure when they work for no department.
local function viewer(src)
    local m = D.Member(src)
    if not m or not m.dept then return nil, deny('no_permission', 'You do not work for a department.') end
    return m
end

local function manager(src)
    local m, err = viewer(src)
    if not m then return nil, err end
    if not D.IsManager(m, m.dept) then return nil, deny('no_permission', 'Only a manager of your department can do that.') end
    return m
end

local function payload(p) return type(p) == 'table' and p or {} end

local function appKey(m, nonce)
    if type(nonce) ~= 'string' or #nonce < 8 or #nonce > 64 or not nonce:match('^[%w%-_]+$') then return nil end
    return ('pf-government:app:%s:%s'):format(m.cid, nonce)
end

local function needKey(m, p)
    local key = appKey(m, p.key)
    if not key then return nil, deny('bad_args', 'A request key is required.') end
    return key
end

--- The department whose budget or payroll is read: the viewer's own, or any department for a
--- holder of the government permission 'budgets'.
local function financeDept(src, p)
    local m = D.Member(src)
    local dept = p.dept ~= nil and p.dept or (m and m.dept)
    if not D.IsDept(dept) then return nil, deny('bad_args', 'Unknown department.') end
    if not D.P.CanView(src, dept) then return nil, deny('no_permission', 'Only managers and budget officials see this.') end
    return dept
end

local function cidArg(v)
    if not U.validCid(v) then return nil end
    return v
end

-- ── overview ────────────────────────────────────────────────────────────

function handlers.overview(src)
    local m, err = viewer(src)
    if not m then return err end
    local isManager = D.IsManager(m, m.dept)
    local quals = D.Q.List(m.cid)
    local mine = D.A.List(m.dept, { holder = m.cid, state = 'issued', limit = 100 })
    local shift = D.S.Get(src)
    local onDuty = 0
    for _, s in pairs(D.S.open) do if s.dept == m.dept then onDuty = onDuty + 1 end end
    local kinds = {}
    for id, k in pairs((D.Cfg().Assets or {}).Kinds or {}) do
        if type(k.depts) == 'table' and k.depts[m.dept] then
            kinds[#kinds + 1] = { id = id, label = k.label or id, selfIssue = k.selfIssue ~= false }
        end
    end
    table.sort(kinds, function(a, b) return a.label < b.label end)
    local deptQuals = {}
    for id, q in pairs(D.Cfg().Qualifications or {}) do
        if q.dept == m.dept then deptQuals[#deptQuals + 1] = { id = id, label = q.label or id } end
    end
    table.sort(deptQuals, function(a, b) return a.label < b.label end)
    return {
        ok = true,
        me = { cid = m.cid, dept = m.dept, job = m.job, grade = m.grade, onDuty = m.onDuty, manager = isManager, boss = m.isBoss },
        dept = { id = m.dept, label = (D.Cfg().Labels or {})[m.dept] or m.dept, onDuty = onDuty,
            assets = isManager and D.A.Counts(m.dept) or nil },
        can = { manage = isManager, payroll = D.P.CanView(src, m.dept), budget = D.P.CanView(src, m.dept) },
        quals = quals.ok and quals.list or {},
        myAssets = mine.ok and mine.list or {},
        shift = shift.ok and shift.shift or nil,
        courses = D.T.Courses(m.dept),
        assetKinds = kinds,
        qualifications = deptQuals,
    }
end

-- ── roster (pfm-management for the boss's own job, the players table for the rest) ──

local function rosterFromPlayers(dept, jobs, skip)
    local want = {}
    for _, j in ipairs(jobs) do if not skip[j] then want[#want + 1] = j end end
    if #want == 0 then return {} end
    local marks = {}
    for i = 1, #want do marks[i] = '?' end
    local ok, rows = pcall(MySQL.query.await, ([[SELECT citizenid, charinfo, job FROM players
        WHERE JSON_VALUE(job, '$.name') IN (%s) LIMIT 500]]):format(table.concat(marks, ', ')), want)
    if not ok or type(rows) ~= 'table' then return nil end
    local out = {}
    for _, r in ipairs(rows) do
        local live = U.getPlayerByCid(r.citizenid)
        local job, ci
        if live and live.PlayerData then
            job, ci = live.PlayerData.job or {}, live.PlayerData.charinfo or {}
        else
            local okJ, j = pcall(json.decode, r.job or '')
            local okC, c = pcall(json.decode, r.charinfo or '')
            job, ci = okJ and type(j) == 'table' and j or {}, okC and type(c) == 'table' and c or {}
        end
        if D.DeptOfJob(job.name) == dept and not skip[job.name] then
            local g = type(job.grade) == 'table' and job.grade or { level = job.grade }
            out[#out + 1] = {
                cid = r.citizenid, name = (((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')),
                job = job.name, grade = tonumber(g.level) or 0, gradeName = g.name,
                boss = job.isboss == true or g.isboss == true, online = live ~= nil,
                onDuty = live ~= nil and job.onduty == true,
            }
        end
    end
    return out
end

function handlers.roster(src)
    local m, err = manager(src)
    if not m then return err end
    local jobs = D.P.JobsOf(m.dept)
    local list, fromManagement = {}, {}
    -- the boss's own job: pfm-management's roster (the same list as the boss menu)
    if m.isBoss and U.started('pfm-management') then
        local ok, members = pcall(function() return exports['pfm-management']:ListEmployees(src, 'job') end)
        if ok and type(members) == 'table' then
            fromManagement[m.job] = true
            for _, e in ipairs(members) do
                local g = type(e.grade) == 'table' and e.grade or {}
                list[#list + 1] = { cid = e.citizenid, name = e.name, job = m.job, grade = tonumber(g.level) or 0, gradeName = g.name,
                    boss = e.isboss == true, online = e.online == true, onDuty = e.onduty == true }
            end
        end
    end
    local rest = rosterFromPlayers(m.dept, jobs, fromManagement)
    if not rest then return deny('db_unavailable', 'The roster could not be read.') end
    for _, r in ipairs(rest) do list[#list + 1] = r end
    -- open shifts (memory) and issued equipment per person
    local shiftOf = {}
    for _, s in pairs(D.S.open) do if s.dept == m.dept then shiftOf[s.cid] = s.startedAt end end
    local held = {}
    local okH, rows = pcall(MySQL.query.await,
        "SELECT holder_cid, COUNT(*) AS n FROM pf_gov_dept_assets WHERE dept = ? AND state = 'issued' GROUP BY holder_cid", { m.dept })
    if okH and type(rows) == 'table' then
        for _, r in ipairs(rows) do if r.holder_cid then held[r.holder_cid] = tonumber(r.n) or 0 end end
    end
    for _, r in ipairs(list) do
        r.shiftStartedAt = shiftOf[r.cid]
        r.assets = held[r.cid] or 0
        r.me = r.cid == m.cid
    end
    table.sort(list, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        return tostring(a.name) < tostring(b.name)
    end)
    return { ok = true, list = list, dept = m.dept }
end

-- ── one employee ────────────────────────────────────────────────────────

function handlers.member(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    local cid = cidArg(p.cid) or m.cid
    if cid ~= m.cid and not D.IsManager(m, m.dept) then return deny('no_permission', 'Only managers see other employees.') end
    local target = D.MemberByCid(cid)
    if target == false then return deny('db_unavailable', 'Department records are unavailable right now.') end
    if not target then return deny('not_found', 'No such citizen.') end
    if cid ~= m.cid and target.dept ~= m.dept then
        -- a former member may still hold equipment or records here: managers see those
        local holds = D.A.List(m.dept, { holder = cid, limit = 1 })
        if not (holds.ok and #holds.list > 0) then return deny('not_found', 'This citizen does not work for your department.') end
    end
    local quals = D.Q.List(cid)
    local training = D.T.List(cid, { dept = m.dept, limit = 50 })
    local assets = D.A.List(m.dept, { holder = cid, limit = 100 })
    local shifts = D.S.List(m.dept, { cid = cid, viewer = src, limit = 20 })
    return {
        ok = true,
        member = { cid = cid, job = target.job, grade = target.grade, dept = target.dept, online = target.src ~= nil, onDuty = target.onDuty },
        quals = quals.ok and quals.list or {},
        training = training.ok and training.list or {},
        assets = assets.ok and assets.list or {},
        shifts = shifts.ok and shifts.list or {},
    }
end

-- ── qualifications (the qualification store checks manager, rank and department again) ──

local function qualChange(fn, src, p)
    p = payload(p)
    local m, err = manager(src)
    if not m then return err end
    local cid = cidArg(p.cid)
    if not cid then return deny('bad_args', 'Invalid citizen id.') end
    local key, kerr = needKey(m, p)
    if not key then return kerr end
    local def = D.Q.Def(p.qual)
    if not def or def.dept ~= m.dept then return deny('bad_args', 'Unknown qualification of your department.') end
    local opts = { actor = { src = src }, key = key }
    if p.expiresAt ~= nil then opts.expiresAt = p.expiresAt end
    if p.reason ~= nil then opts.reason = p.reason end
    return fn(cid, p.qual, opts, nil)
end

function handlers.grantQual(src, p) return qualChange(D.Q.Grant, src, p) end
function handlers.revokeQual(src, p) return qualChange(D.Q.Revoke, src, p) end

-- ── shifts ──────────────────────────────────────────────────────────────

function handlers.shifts(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    -- ListShifts with a viewer limits a non-manager to their own shifts
    return D.S.List(m.dept, { cid = p.cid, open = p.open == true or nil, beforeId = p.beforeId, viewer = src, limit = 50 })
end

-- ── training ────────────────────────────────────────────────────────────

function handlers.training(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    local cid = p.cid
    if cid ~= nil and cid ~= m.cid and not D.IsManager(m, m.dept) then
        return deny('no_permission', 'Only managers see the training of others.')
    end
    if cid == nil and not D.IsManager(m, m.dept) then cid = m.cid end
    if cid ~= nil and not cidArg(cid) then return deny('bad_args', 'Invalid citizen id.') end
    return D.T.List(cid, { dept = m.dept, beforeId = p.beforeId, limit = 50 })
end

function handlers.recordTraining(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    local key, kerr = needKey(m, p)
    if not key then return kerr end
    local course = D.T.Course(p.course)
    if not course or course.dept ~= m.dept then return deny('bad_args', 'Unknown course of your department.') end
    -- training.lua checks the instructor (duty, manager or instructor qualification) and the trainee
    return D.T.Record(p.cid, p.course, p.result, { actor = { src = src }, key = key, score = p.score, note = p.note }, nil)
end

-- ── asset register ──────────────────────────────────────────────────────

function handlers.assets(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    local filter = { state = p.state, kind = p.kind, beforeId = p.beforeId, limit = 50 }
    if D.IsManager(m, m.dept) then
        filter.holder = p.holder
    else
        filter.holder = m.cid
    end
    return D.A.List(m.dept, filter)
end

function handlers.assetHistory(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    local got = D.A.Get(p.serial)
    if not got.ok then return got end
    if got.asset.dept ~= m.dept then return deny('not_found', 'No asset of your department has that serial.') end
    if not D.IsManager(m, m.dept) and got.asset.holder ~= m.cid then
        return deny('no_permission', 'Only managers see the history of equipment they do not hold.')
    end
    local hist = D.A.History(p.serial)
    if not hist.ok then return hist end
    return { ok = true, asset = got.asset, list = hist.list }
end

function handlers.registerAsset(src, p)
    p = payload(p)
    local m, err = manager(src)
    if not m then return err end
    local key, kerr = needKey(m, p)
    if not key then return kerr end
    return D.A.Register(m.dept, { kind = p.kind, serial = p.serial, item = p.item, label = p.label, location = p.location, cost = p.cost },
        { actor = { src = src }, key = key }, nil)
end

--- An asset of the viewer's department, or a failure.
local function ownAsset(m, serial)
    local got = D.A.Get(serial)
    if not got.ok then return nil, got end
    if got.asset.dept ~= m.dept then return nil, deny('not_found', 'No asset of your department has that serial.') end
    return got.asset
end

function handlers.issueAsset(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    local key, kerr = needKey(m, p)
    if not key then return kerr end
    local asset, aerr = ownAsset(m, p.serial)
    if not asset then return aerr end
    -- assets.lua checks duty, manager-only issues and the holder's department
    return D.A.Issue(asset.serial, p.cid, { actor = { src = src }, key = key, note = p.note }, nil)
end

function handlers.returnAsset(src, p)
    p = payload(p)
    local m, err = viewer(src)
    if not m then return err end
    local key, kerr = needKey(m, p)
    if not key then return kerr end
    local asset, aerr = ownAsset(m, p.serial)
    if not asset then return aerr end
    return D.A.Return(asset.serial, { actor = { src = src }, key = key, to = p.to, note = p.note }, nil)
end

function handlers.assetAction(src, p)
    p = payload(p)
    local m, err = manager(src)
    if not m then return err end
    local key, kerr = needKey(m, p)
    if not key then return kerr end
    local asset, aerr = ownAsset(m, p.serial)
    if not asset then return aerr end
    return D.A.Move(asset.serial, p.action, { actor = { src = src }, key = key, note = p.note }, nil)
end

-- ── procurements (rows written by server/departments/procurement.lua) ──

function handlers.procurements(src, p)
    p = payload(p)
    local m, err = manager(src)
    if not m then return err end
    local where, params = { 'dept = ?' }, { m.dept }
    if p.beforeId ~= nil then
        local before = U.int(p.beforeId, 1, 2147483647)
        if not before then return deny('bad_args', 'Invalid cursor.') end
        where[#where + 1] = 'id < ?'; params[#params + 1] = before
    end
    if not U.dbReady() then return deny('db_unavailable', 'Department records are unavailable right now.') end
    local ok, rows = pcall(MySQL.query.await, [[SELECT id, buyer_id, store_order_id, method, items, total, state, by_cid, note, at, updated_at
        FROM pf_gov_dept_procurements WHERE ]] .. table.concat(where, ' AND ') .. ' ORDER BY id DESC LIMIT 50', params)
    if not ok or type(rows) ~= 'table' then return deny('db_unavailable', 'Department records are unavailable right now.') end
    local list = {}
    for _, r in ipairs(rows) do
        local okI, items = pcall(json.decode, r.items or '')
        list[#list + 1] = { id = tonumber(r.id), buyer = r.buyer_id, order = tonumber(r.store_order_id), method = r.method,
            items = okI and type(items) == 'table' and items or nil, total = tonumber(r.total), state = r.state, by = r.by_cid,
            note = r.note, at = tonumber(r.at), updatedAt = tonumber(r.updated_at) }
    end
    return { ok = true, list = list, nextCursor = #list == 50 and list[#list].id or nil }
end

-- purchases go through server/departments/procurement.lua (20C), which checks an on-duty manager
-- of the facility's department, prices from its catalog and lets pf-stores charge the society
local function procurement()
    local P = D.Procurement
    if type(P) ~= 'table' or type(P.Create) ~= 'function' then return nil end
    return P
end

function handlers.procurementCatalog(src)
    local m, err = manager(src)
    if not m then return err end
    local P = procurement()
    if not P then return deny('unavailable', 'Purchasing is not available.') end
    return P.Catalog(src)
end

function handlers.placeProcurement(src, p)
    p = payload(p)
    local m, err = manager(src)
    if not m then return err end
    local key, kerr = needKey(m, p)
    if not key then return kerr end
    local P = procurement()
    if not P then return deny('unavailable', 'Purchasing is not available.') end
    if type(p.buyerId) ~= 'string' or type(p.cart) ~= 'table' then return deny('bad_args', 'A facility and order lines are required.') end
    return P.Create(src, p.buyerId, p.cart, { key = key })
end

function handlers.cancelProcurement(src, p)
    p = payload(p)
    local m, err = manager(src)
    if not m then return err end
    local P = procurement()
    if not P then return deny('unavailable', 'Purchasing is not available.') end
    return P.Cancel(src, p.id)
end

-- ── budget (read only; budgets are set on the government computer) ──

function handlers.budget(src, p)
    p = payload(p)
    local dept, err = financeDept(src, p)
    if not dept then return err end
    local snap = GovSafe(GetDepartmentMonthlyBudgetSnapshot, dept)
    local ok, rows = pcall(MySQL.query.await, [[SELECT id, transaction_type, category, amount, society_after, actor_name, reason, state,
        UNIX_TIMESTAMP(created_at) AS at FROM pf_gov_budget_transactions WHERE department = ? ORDER BY id DESC LIMIT 25]], { dept })
    local recent = {}
    if ok and type(rows) == 'table' then
        for _, r in ipairs(rows) do
            recent[#recent + 1] = { id = tonumber(r.id), type = r.transaction_type, category = r.category, amount = tonumber(r.amount) or 0,
                after = tonumber(r.society_after), by = r.actor_name, reason = r.reason, state = r.state, at = tonumber(r.at) }
        end
    end
    local view
    if type(snap) == 'table' then
        view = { budget = tonumber(snap.approved_monthly_budget), balance = tonumber(snap.society_balance),
            spent = tonumber(snap.spent_this_month), recommended = tonumber(snap.recommended_monthly_budget),
            minimum = tonumber(snap.minimum_required_monthly), salaries = tonumber(snap.salary_obligation_monthly),
            status = snap.budget_status, month = snap.month_key, society = snap.linked_society_name }
    end
    return { ok = true, dept = dept, snapshot = view, recent = recent }
end

-- ── payroll reports ─────────────────────────────────────────────────────

function handlers.payroll(src, p)
    p = payload(p)
    local dept, err = financeDept(src, p)
    if not dept then return err end
    return D.P.Build(dept, p.from, p.to)
end

function handlers.savePayroll(src, p)
    p = payload(p)
    local dept, err = financeDept(src, p)
    if not dept then return err end
    return D.P.Save(dept, p.from, p.to, A.Cid(src))
end

function handlers.payrollReports(src, p)
    p = payload(p)
    local dept, err = financeDept(src, p)
    if not dept then return err end
    return D.P.Saved(dept, p.id)
end

-- ── registration ────────────────────────────────────────────────────────

GovApps.Department = handlers

--- Every department job may open the app (grade 0); the handlers decide what each one sees.
local function accessJobs()
    local jobs = {}
    for job in pairs(D.Cfg().Jobs or {}) do jobs[job] = 0 end
    return jobs
end

local ENTRY = 'html/apps/department.js'

--- The app is offered only once its module ships (batch 21 adds html/apps/department.js), so no
--- device shows an app that cannot load.
function GovApps.DepartmentModuleReady()
    if type(LoadResourceFile) ~= 'function' then return false end
    local ok, src = pcall(LoadResourceFile, GetCurrentResourceName(), ENTRY)
    return ok and type(src) == 'string' and #src > 0
end

if GovApps.DepartmentModuleReady() then
    A.Define({
        id = APP_ID, name = 'Department', icon = '🏛️',
        devices = { 'tablet', 'computer' },
        entry = ENTRY, styles = { 'html/apps/gov.css' },
        category = 'government', order = 20,
        access = { jobs = accessJobs() },
        description = 'Roster, qualifications, shifts, training, equipment, purchases, budget and payroll',
        window = { width = 1040, height = 680 },
    }, handlers)
end
