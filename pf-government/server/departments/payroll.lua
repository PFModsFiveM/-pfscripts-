-- =====================================================
-- DEPARTMENTS: PAYROLL REPORTS (batch 20, unit 20E)
-- =====================================================
-- A read-only report of what a department cost in a period. Nothing here pays anyone: wages stay
-- in the pfm-core paycheck (PayPaycheck: a bank ledger Transfer of kind 'wage' from
-- society:<job>, or from system:paycheck for an unfunded job, metadata.job = the job).
--   * wages: the ledger's wage transfers of the department's jobs in the period, per employee;
--     completed = paid, pending/debited = not settled yet (shown apart, never as paid or failed),
--     failed/compensated = not paid;
--   * budget: the department's society moves in pf_gov_budget_transactions (treasury funding in,
--     society spending out, adjustments), keyed moves only once applied (pending ones apart);
--   * hours: the department's shifts (pf_gov_dept_shifts) clipped to the period.
-- A closed period can be saved once (pf_gov_dept_payroll_reports, key
-- pf-government:payroll:<dept>:<from>:<to>), so a month's report stays as it was.
-- Who may read: managers of the department and holders of the government permission 'budgets'.

GovDept = GovDept or {}
local D = GovDept
local U = D.U
D.P = D.P or {}
local P = D.P

local function pcfg() return D.Cfg().Payroll or {} end

--- The pfm-core jobs of a department.
function P.JobsOf(dept)
    local out = {}
    for job, d in pairs(D.Cfg().Jobs or {}) do
        if d == dept then out[#out + 1] = job end
    end
    table.sort(out)
    return out
end

--- True when the player may read the department's payroll.
function P.CanView(src, dept)
    local m = D.Member(src)
    if m and D.IsManager(m, dept) then return true end
    return type(HasPermission) == 'function' and HasPermission(src, 'budgets') == true
end

local function round2(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end

local function placeholders(n)
    local t = {}
    for i = 1, n do t[i] = '?' end
    return table.concat(t, ', ')
end

local function decode(v)
    if type(v) == 'table' then return v end
    local ok, out = pcall(json.decode, v or '')
    return ok and type(out) == 'table' and out or {}
end

--- Validates a period: from < to, at most MaxPeriodDays long. Returns from, to or nil, failure.
function P.Period(from, to)
    from, to = U.int(from, 0, 4102444800), U.int(to, 0, 4102444800)
    if not from or not to or from >= to then return nil, U.fail('bad_args', 'The period must start before it ends.') end
    local maxDays = U.int(pcfg().MaxPeriodDays or 92, 1, 3660) or 92
    if to - from > maxDays * 86400 then
        return nil, U.fail('bad_args', ('A payroll report covers at most %d days.'):format(maxDays))
    end
    return from, to
end

--- Builds the report of `dept` for [from, to). -> { ok, report } (see the header).
function P.Build(dept, from, to)
    if not D.IsDept(dept) then return U.fail('bad_args', 'Unknown department.') end
    local f, t2 = P.Period(from, to)
    if not f then return t2 end
    from, to = f, t2
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local now = U.now()
    local jobs = P.JobsOf(dept)
    local people, order = {}, {}
    local function person(cid)
        local p = people[cid]
        if not p then
            p = { cid = cid, wagesPaid = 0, wagesPending = 0, wagesFailed = 0, paychecks = 0, hours = 0, shifts = 0, jobs = {} }
            people[cid] = p
            order[#order + 1] = cid
        end
        return p
    end
    local totals = { wagesPaid = 0, wagesPending = 0, wagesFailed = 0, paychecks = 0, fromSociety = 0, fromState = 0,
        hours = 0, fundingIn = 0, spendOut = 0, adjustments = 0, pendingMoves = 0 }

    -- wages from the bank ledger (pfm-core paychecks of the department's jobs)
    if #jobs > 0 then
        local params = { from, to }
        for _, j in ipairs(jobs) do params[#params + 1] = 'society:' .. j end
        for _, j in ipairs(jobs) do params[#params + 1] = j end
        local ok, rows = pcall(MySQL.query.await, ([[SELECT to_account, from_account, state, JSON_VALUE(metadata, '$.job') AS job,
            COUNT(*) AS n, SUM(amount) AS total FROM pf_transactions
            WHERE kind = 'wage' AND created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)
            AND (from_account IN (%s) OR (from_account = 'system:paycheck' AND JSON_VALUE(metadata, '$.job') IN (%s)))
            GROUP BY to_account, from_account, state, JSON_VALUE(metadata, '$.job')]]):format(placeholders(#jobs), placeholders(#jobs)), params)
        if not ok or type(rows) ~= 'table' then
            return U.fail('bank_unavailable', 'The bank ledger could not be read. No report was made.')
        end
        for _, r in ipairs(rows) do
            local cid = type(r.to_account) == 'string' and r.to_account:match('^player:([%w]+):bank$')
            if cid then
                local p, amount, n = person(cid), round2(r.total), tonumber(r.n) or 0
                if r.job then p.jobs[r.job] = true end
                if r.state == 'completed' then
                    p.wagesPaid, p.paychecks = round2(p.wagesPaid + amount), p.paychecks + n
                    totals.wagesPaid, totals.paychecks = round2(totals.wagesPaid + amount), totals.paychecks + n
                    if r.from_account == 'system:paycheck' then totals.fromState = round2(totals.fromState + amount)
                    else totals.fromSociety = round2(totals.fromSociety + amount) end
                elseif r.state == 'pending' or r.state == 'debited' then
                    p.wagesPending = round2(p.wagesPending + amount)
                    totals.wagesPending = round2(totals.wagesPending + amount)
                else
                    p.wagesFailed = p.wagesFailed + n
                    totals.wagesFailed = totals.wagesFailed + n
                end
            end
        end
    end

    -- hours on duty, clipped to the period
    local okS, shifts = pcall(MySQL.query.await, [[SELECT citizenid, job, COUNT(*) AS n,
        SUM(LEAST(COALESCE(ended_at, ?), ?) - GREATEST(started_at, ?)) AS secs FROM pf_gov_dept_shifts
        WHERE dept = ? AND started_at < ? AND (ended_at IS NULL OR ended_at > ?) GROUP BY citizenid, job]],
        { math.min(now, to), to, from, dept, to, from })
    if not okS or type(shifts) ~= 'table' then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    for _, r in ipairs(shifts) do
        if U.validCid(r.citizenid) then
            local p = person(r.citizenid)
            local hours = math.max(0, tonumber(r.secs) or 0) / 3600
            p.hours = round2(p.hours + hours)
            p.shifts = p.shifts + (tonumber(r.n) or 0)
            if r.job then p.jobs[r.job] = true end
            totals.hours = round2(totals.hours + hours)
        end
    end

    -- the department's society funding and spending
    local okB, moves = pcall(MySQL.query.await, [[SELECT transaction_type, category, COALESCE(state, 'applied') AS st,
        COUNT(*) AS n, SUM(amount) AS total FROM pf_gov_budget_transactions
        WHERE department = ? AND created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)
        GROUP BY transaction_type, category, COALESCE(state, 'applied')]], { dept, from, to })
    if not okB or type(moves) ~= 'table' then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local budget = {}
    for _, r in ipairs(moves) do
        local amount = round2(r.total)
        if r.st == 'applied' then
            budget[#budget + 1] = { type = r.transaction_type, category = r.category, total = amount, count = tonumber(r.n) or 0 }
            if r.transaction_type == 'treasury_funding' then totals.fundingIn = round2(totals.fundingIn + amount)
            elseif r.transaction_type == 'society_spend' then totals.spendOut = round2(totals.spendOut + amount)
            else totals.adjustments = round2(totals.adjustments + amount) end
        elseif r.st == 'pending' then
            totals.pendingMoves = round2(totals.pendingMoves + amount)
        end
    end
    table.sort(budget, function(a, b)
        if a.type ~= b.type then return a.type < b.type end
        return tostring(a.category) < tostring(b.category)
    end)

    -- names and current ranks (the players rows), at most MaxEmployees people
    local maxPeople = U.int(pcfg().MaxEmployees or 300, 1, 5000) or 300
    table.sort(order, function(a, b)
        local pa, pb = people[a], people[b]
        if pa.wagesPaid ~= pb.wagesPaid then return pa.wagesPaid > pb.wagesPaid end
        return a < b
    end)
    local truncated = #order > maxPeople
    local cids = {}
    for i = 1, math.min(#order, maxPeople) do cids[i] = order[i] end
    if #cids > 0 then
        local okN, rows = pcall(MySQL.query.await,
            ('SELECT citizenid, charinfo, job FROM players WHERE citizenid IN (%s)'):format(placeholders(#cids)), cids)
        if okN and type(rows) == 'table' then
            for _, r in ipairs(rows) do
                local p = people[r.citizenid]
                if p then
                    local ci, job = decode(r.charinfo), decode(r.job)
                    p.name = (((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''))
                    if D.DeptOfJob(job.name) == dept then
                        local g = type(job.grade) == 'table' and job.grade or { level = job.grade }
                        p.currentJob, p.grade, p.gradeName = job.name, tonumber(g.level), g.name
                    end
                end
            end
        end
    end
    local list = {}
    for _, cid in ipairs(cids) do
        local p = people[cid]
        local js = {}
        for j in pairs(p.jobs) do js[#js + 1] = j end
        table.sort(js)
        list[#list + 1] = {
            cid = cid, name = p.name ~= '' and p.name or nil, jobs = js, currentJob = p.currentJob, grade = p.grade, gradeName = p.gradeName,
            employed = p.currentJob ~= nil, wagesPaid = p.wagesPaid, wagesPending = p.wagesPending, wagesFailed = p.wagesFailed,
            paychecks = p.paychecks, hours = p.hours, shifts = p.shifts,
        }
    end
    totals.employees = #order
    return { ok = true, report = {
        dept = dept, label = (D.Cfg().Labels or {})[dept] or dept, from = from, to = to, generatedAt = now,
        partial = to > now, truncated = truncated, jobs = jobs, totals = totals, employees = list, budget = budget,
    } }
end

local function reportKey(dept, from, to) return ('pf-government:payroll:%s:%d:%d'):format(dept, from, to) end

local function savedView(r, full)
    local v = { id = tonumber(r.id), dept = r.dept, from = tonumber(r.period_from), to = tonumber(r.period_to),
        employees = tonumber(r.employees), wagesTotal = tonumber(r.wages_total), wagesPending = tonumber(r.wages_pending),
        fundingTotal = tonumber(r.funding_total), spendTotal = tonumber(r.spend_total), by = r.by_cid, at = tonumber(r.at) }
    if full then v.report = decode(r.report) end
    return v
end

--- Saves the report of a closed period once. -> { ok, saved, duplicate? }
function P.Save(dept, from, to, byCid)
    if not D.IsDept(dept) then return U.fail('bad_args', 'Unknown department.') end
    local f, t2 = P.Period(from, to)
    if not f then return t2 end
    from, to = f, t2
    if to > U.now() then return U.fail('invalid_state', 'Only a period that has ended can be saved.') end
    local key = reportKey(dept, from, to)
    return U.withLocks({ 'dpr:' .. key }, function()
        if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
        local prior = MySQL.single.await('SELECT * FROM pf_gov_dept_payroll_reports WHERE idem_key = ? LIMIT 1', { key })
        if prior then return { ok = true, duplicate = true, saved = savedView(prior, false) } end
        local built = P.Build(dept, from, to)
        if not built.ok then return built end
        local r = built.report
        local encoded = json.encode(r)
        if #encoded > 4000000 then return U.fail('bad_args', 'The report is too large to save.') end
        local id = MySQL.insert.await([[INSERT INTO pf_gov_dept_payroll_reports
            (dept, period_from, period_to, employees, wages_total, wages_pending, funding_total, spend_total, report, by_cid, at, idem_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            { dept, from, to, r.totals.employees, r.totals.wagesPaid, r.totals.wagesPending, r.totals.fundingIn, r.totals.spendOut,
                encoded, byCid, U.now(), key })
        if not id then error('payroll report insert failed') end
        D.Audit(dept, 'payroll_saved', byCid, tostring(id), { from = from, to = to, wages = r.totals.wagesPaid })
        local row = MySQL.single.await('SELECT * FROM pf_gov_dept_payroll_reports WHERE id = ? LIMIT 1', { id })
        return { ok = true, saved = savedView(row, false) }
    end)
end

--- The saved reports of a department (newest period first), or one with its full report.
function P.Saved(dept, id)
    if not D.IsDept(dept) then return U.fail('bad_args', 'Unknown department.') end
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    if id ~= nil then
        id = U.int(id, 1, 2147483647)
        if not id then return U.fail('bad_args', 'Invalid report.') end
        local ok, row = pcall(MySQL.single.await, 'SELECT * FROM pf_gov_dept_payroll_reports WHERE id = ? AND dept = ? LIMIT 1', { id, dept })
        if not ok then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
        if not row then return U.fail('not_found', 'No such report.') end
        return { ok = true, saved = savedView(row, true) }
    end
    local ok, rows = pcall(MySQL.query.await, [[SELECT id, dept, period_from, period_to, employees, wages_total, wages_pending,
        funding_total, spend_total, by_cid, at FROM pf_gov_dept_payroll_reports WHERE dept = ? ORDER BY period_from DESC LIMIT 50]], { dept })
    if not ok or type(rows) ~= 'table' then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = savedView(r, false) end
    return { ok = true, list = list }
end
