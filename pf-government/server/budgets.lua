-- =====================================================
-- MONTHLY DEPARTMENT BUDGETS + LINKED SOCIETY ACCOUNTS
-- =====================================================

local BudgetCache = {}

local SPEND_CATEGORIES = {
    salary = true,
    equipment = true,
    vehicles = true,
    maintenance = true,
    upgrades = true,
    operations = true,
    emergency = true,
    treasury_funding = true
}

local function asNumber(v, fallback)
    local n = tonumber(v)
    if n == nil then return fallback or 0 end
    return n
end

local function round2(v)
    v = asNumber(v, 0)
    return math.floor((v * 100) + 0.5) / 100
end

local function currentMonthKey()
    return os.date('%Y-%m')
end

local function triggerInfrastructureRefreshNow()
    if GetResourceState(GetCurrentResourceName()) ~= 'started' then return end
    local ok = pcall(function()
        exports[GetCurrentResourceName()]:RecalculateInfrastructureNow()
    end)
    if not ok then
        DebugPrint('Infrastructure refresh export unavailable during budget mutation')
    end
end

local function isBankingAvailable()
    return GetResourceState('pfm-banking') == 'started'
end

local function getLinkedSocietyName(department)
    local map = (Config.Budgets and Config.Budgets.LinkedSocietyAccounts) or {}
    return map[department] or department
end

local function ensureSocietyAccount(society)
    if not isBankingAvailable() or not society or society == '' then return end
    local ok = pcall(function()
        local acc = exports['pfm-banking']:GetAccount(society)
        if not acc then
            exports['pfm-banking']:CreateJobAccount(society, 0)
        end
    end)
    if not ok then
        DebugPrint(('Unable to ensure society account for %s'):format(society))
    end
end

local function getSocietyBalance(society)
    if not society or society == '' then return 0 end
    if isBankingAvailable() then
        local ok, bal = pcall(function()
            return exports['pfm-banking']:GetAccountBalance(society)
        end)
        if ok then
            return round2(asNumber(bal, 0))
        end
    end

    local row = MySQL.single.await('SELECT society_balance FROM pf_gov_department_monthly_plans WHERE linked_society_name = ? LIMIT 1', { society })
    return round2(asNumber(row and row.society_balance, 0))
end

local function syncSocietyBalanceInDb(department, society, balance)
    MySQL.update.await('UPDATE pf_gov_department_monthly_plans SET society_balance = ? WHERE department = ? AND month_key = ?', {
        round2(balance), department, currentMonthKey()
    })
end

-- Both helpers report whether money actually moved: pfm-banking's own result, not merely that the
-- call did not throw. Without banking there is no society account to move money in, so they fail
-- closed instead of pretending.
local function addMoneyToSociety(society, amount, reason)
    amount = round2(amount)
    if amount <= 0 or not isBankingAvailable() then return false end
    local ok, moved = pcall(function()
        return exports['pfm-banking']:AddMoney(society, amount, reason or 'Department funding')
    end)
    return ok and moved == true
end

local function removeMoneyFromSociety(society, amount, reason)
    amount = round2(amount)
    if amount <= 0 or not isBankingAvailable() then return false end
    local ok, moved = pcall(function()
        return exports['pfm-banking']:RemoveMoney(society, amount, reason or 'Department spend')
    end)
    return ok and moved == true
end

local function getPaychecksPerMonth()
    local configured = asNumber(Config.Budgets and Config.Budgets.PaychecksPerMonth, 0)
    if configured > 0 then
        return math.max(1, math.floor(configured))
    end

    local timeoutMinutes = nil
    if QBCore and QBCore.Config and QBCore.Config.Money then
        timeoutMinutes = asNumber(QBCore.Config.Money.PayCheckTimeOut, 0)
    end

    if timeoutMinutes and timeoutMinutes > 0 then
        local cycles = math.floor((30 * 24 * 60) / timeoutMinutes)
        return math.max(1, cycles)
    end

    return 30
end

local function getEmployeeCountsByGrade(jobName)
    local result = {}
    local rows = MySQL.query.await('SELECT job FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, "$.name")) = ?', { jobName }) or {}
    for _, row in ipairs(rows) do
        local decoded = nil
        if type(row.job) == 'string' and row.job ~= '' then
            decoded = json.decode(row.job)
        elseif type(row.job) == 'table' then
            decoded = row.job
        end

        if decoded and tostring(decoded.name or '') == tostring(jobName) then
            local grade = decoded.grade
            local gradeLevel = 0
            if type(grade) == 'table' then
                gradeLevel = asNumber(grade.level, asNumber(grade.grade, 0))
            else
                gradeLevel = asNumber(grade, 0)
            end
            local key = tostring(math.floor(gradeLevel))
            result[key] = (result[key] or 0) + 1
        end
    end
    return result
end

local function calculateJobMonthlySalary(jobName)
    local jobDef = QBCore and QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[jobName]
    if not jobDef or type(jobDef.grades) ~= 'table' then
        return 0, 0
    end

    local counts = getEmployeeCountsByGrade(jobName)
    local paychecksPerMonth = getPaychecksPerMonth()

    local monthly = 0
    local employees = 0
    for gradeKey, count in pairs(counts) do
        local gradeData = jobDef.grades[gradeKey] or jobDef.grades[tonumber(gradeKey)]
        local payment = type(gradeData) == 'table' and asNumber(gradeData.payment, 0) or 0
        local employeeMinimum = (payment * paychecksPerMonth) * 1.10
        monthly = monthly + (employeeMinimum * count)
        employees = employees + count
    end

    return round2(monthly), employees
end

local function determineBudgetStatus(balance, minimumRequired, projectedMonthEnd)
    balance = asNumber(balance, 0)
    minimumRequired = math.max(1, asNumber(minimumRequired, 1))
    local ratio = balance / minimumRequired

    if projectedMonthEnd < 0 or ratio < 0.65 then return 'Underfunded' end
    if ratio < 0.85 then return 'At Risk' end
    if ratio < 1.00 then return 'Tight' end
    if ratio < 1.20 then return 'Stable' end
    return 'Healthy'
end

local function ensureBudgetTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_department_monthly_plans` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `department` VARCHAR(50) NOT NULL,
            `month_key` VARCHAR(7) NOT NULL,
            `approved_monthly_budget` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `linked_society_name` VARCHAR(100) NOT NULL,
            `society_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `spent_this_month` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `minimum_required_monthly` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `recommended_monthly_budget` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `projected_month_end_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `budget_status` VARCHAR(20) NOT NULL DEFAULT 'Stable',
            `salary_obligation_monthly` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `equipment_plan` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `fleet_plan` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `facility_plan` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `emergency_buffer` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `projected_obligations_remaining` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `updated_by` VARCHAR(64) NULL,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY `uniq_department_month` (`department`, `month_key`),
            INDEX `idx_month` (`month_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_budget_transactions` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `department` VARCHAR(50) NOT NULL,
            `month_key` VARCHAR(7) NOT NULL,
            `transaction_type` ENUM('treasury_funding','society_spend','adjustment') NOT NULL,
            `category` VARCHAR(50) NOT NULL,
            `amount` DECIMAL(15,2) NOT NULL,
            `society_before` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `society_after` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `actor_id` VARCHAR(64) NULL,
            `actor_name` VARCHAR(255) NULL,
            `reason` VARCHAR(255) NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_department_month` (`department`, `month_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

local function getManagedDepartments()
    local departments = {}
    local seen = {}

    local function addDepartment(department)
        department = tostring(department or '')
        if department == '' or seen[department] then return end
        seen[department] = true
        departments[#departments + 1] = department
    end

    for department, _ in pairs((Config.Budgets and Config.Budgets.Defaults) or {}) do
        addDepartment(department)
    end
    for department, _ in pairs((Config.Budgets and Config.Budgets.LinkedSocietyAccounts) or {}) do
        addDepartment(department)
    end

    local dbRows = MySQL.query.await('SELECT DISTINCT department FROM pf_gov_department_monthly_plans', {}) or {}
    for _, row in ipairs(dbRows) do
        addDepartment(row.department)
    end

    return departments
end

function EnsureDepartmentBudgetMonth(department, monthKey)
    if not department or department == '' then return nil end
    monthKey = monthKey or currentMonthKey()

    local existing = MySQL.single.await(
        'SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1',
        { department, monthKey }
    )
    if existing then return existing end

    local previous = MySQL.single.await(
        'SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? ORDER BY month_key DESC LIMIT 1',
        { department }
    )

    local defaultBudget = asNumber(Config.Budgets and Config.Budgets.Defaults and Config.Budgets.Defaults[department], 0)
    local approvedBudget = previous and asNumber(previous.approved_monthly_budget, defaultBudget) or defaultBudget
    local linkedSociety = previous and tostring(previous.linked_society_name or '') or getLinkedSocietyName(department)
    if linkedSociety == '' then
        linkedSociety = getLinkedSocietyName(department)
    end

    ensureSocietyAccount(linkedSociety)
    local societyBalance = getSocietyBalance(linkedSociety)

    MySQL.insert.await(
        'INSERT INTO pf_gov_department_monthly_plans (department, month_key, approved_monthly_budget, linked_society_name, society_balance, spent_this_month, minimum_required_monthly, recommended_monthly_budget, projected_month_end_balance, budget_status, salary_obligation_monthly, equipment_plan, fleet_plan, facility_plan, emergency_buffer, projected_obligations_remaining, updated_by) VALUES (?, ?, ?, ?, ?, 0, 0, 0, 0, ?, 0, 0, 0, 0, 0, 0, ?)',
        { department, monthKey, round2(approvedBudget), linkedSociety, round2(societyBalance), 'Stable', previous and previous.updated_by or nil }
    )

    local created = MySQL.single.await(
        'SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1',
        { department, monthKey }
    )
    return created
end

local function ensureCurrentMonthRows()
    local monthKey = currentMonthKey()
    for _, department in ipairs(getManagedDepartments()) do
        EnsureDepartmentBudgetMonth(department, monthKey)
    end
end

local function computeRequirementBreakdown(department)
    local planCfg = (Config.Budgets and Config.Budgets.Planning) or {}
    local equipPerEmployee = asNumber(planCfg.EquipmentPerEmployee and planCfg.EquipmentPerEmployee[department], 0)
    local fleetPerEmployee = asNumber(planCfg.FleetPerEmployee and planCfg.FleetPerEmployee[department], 0)
    local facilityBase = asNumber(planCfg.FacilityBase and planCfg.FacilityBase[department], 0)
    local emergencyPct = asNumber(planCfg.EmergencyBufferPercent, 0.10)

    local salaryMonthly = 0
    local employeeCount = 0

    local salaryJobs = (Config.Budgets and Config.Budgets.SalaryTrackedJobs) or {
        police = 'police',
        ems = 'ambulance'
    }

    local jobName = salaryJobs[department]
    if jobName and jobName ~= '' then
        salaryMonthly, employeeCount = calculateJobMonthlySalary(jobName)
    end

    local minimumRequired = salaryMonthly
    local equipmentPlan = round2(equipPerEmployee * employeeCount)
    local fleetPlan = round2(fleetPerEmployee * employeeCount)
    local facilityPlan = round2(facilityBase)
    local emergencyBuffer = round2((minimumRequired + equipmentPlan + fleetPlan + facilityPlan) * emergencyPct)

    local recommended = round2(minimumRequired + equipmentPlan + fleetPlan + facilityPlan + emergencyBuffer)

    return {
        minimumRequired = round2(minimumRequired),
        salaryMonthly = round2(salaryMonthly),
        employeeCount = employeeCount,
        equipmentPlan = equipmentPlan,
        fleetPlan = fleetPlan,
        facilityPlan = facilityPlan,
        emergencyBuffer = emergencyBuffer,
        recommended = recommended
    }
end

local function buildSnapshotForDepartment(department)
    local monthKey = currentMonthKey()
    local row = MySQL.single.await('SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1', { department, monthKey })
    if not row then
        return nil
    end

    local req = computeRequirementBreakdown(department)
    local societyBalance = getSocietyBalance(row.linked_society_name)
    local spent = asNumber(row.spent_this_month, 0)

    local projectedRemaining = math.max(0, req.recommended - spent)
    local projectedMonthEnd = round2(societyBalance - projectedRemaining)
    local status = determineBudgetStatus(societyBalance, req.minimumRequired, projectedMonthEnd)

    MySQL.update.await([[
        UPDATE pf_gov_department_monthly_plans
        SET society_balance = ?,
            minimum_required_monthly = ?,
            recommended_monthly_budget = ?,
            projected_month_end_balance = ?,
            budget_status = ?,
            salary_obligation_monthly = ?,
            equipment_plan = ?,
            fleet_plan = ?,
            facility_plan = ?,
            emergency_buffer = ?,
            projected_obligations_remaining = ?
        WHERE id = ?
    ]], {
        societyBalance,
        req.minimumRequired,
        req.recommended,
        projectedMonthEnd,
        status,
        req.salaryMonthly,
        req.equipmentPlan,
        req.fleetPlan,
        req.facilityPlan,
        req.emergencyBuffer,
        projectedRemaining,
        row.id
    })

    return {
        department = department,
        month_key = monthKey,
        approved_monthly_budget = round2(row.approved_monthly_budget),
        linked_society_name = row.linked_society_name,
        society_balance = round2(societyBalance),
        spent_this_month = round2(spent),
        minimum_required_monthly = req.minimumRequired,
        recommended_monthly_budget = req.recommended,
        projected_month_end_balance = projectedMonthEnd,
        budget_status = status,
        salary_obligation_monthly = req.salaryMonthly,
        equipment_plan = req.equipmentPlan,
        fleet_plan = req.fleetPlan,
        facility_plan = req.facilityPlan,
        emergency_buffer = req.emergencyBuffer,
        projected_obligations_remaining = projectedRemaining,
        -- Compatibility fields
        weekly_budget = round2(row.approved_monthly_budget),
        spent_this_week = round2(spent)
    }
end

function RecalculateDepartmentMonthlyRequirements(department)
    if not department or department == '' then
        return false, 'invalid_department'
    end

    EnsureDepartmentBudgetMonth(department, currentMonthKey())
    local snapshot = buildSnapshotForDepartment(department)
    if not snapshot then
        return false, 'department_not_found'
    end

    BudgetCache[department] = snapshot
    return true, snapshot
end

function GetDepartmentSocietyBalance(department)
    local monthKey = currentMonthKey()
    EnsureDepartmentBudgetMonth(department, monthKey)
    local row = MySQL.single.await('SELECT linked_society_name FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1', { department, monthKey })
    if not row then return 0 end
    return getSocietyBalance(row.linked_society_name)
end

local keyedSocietyMove -- defined below

--- Moves treasury money into a department's society account. With `key` (optional, a stable id of
--- this real-world funding, e.g. pf-government:dept:<dept>:<purpose>:<id>) the move is idempotent:
--- the same key never moves money twice (see keyedSocietyMove). Without a key it behaves as before.
function AddFundsToDepartmentSociety(department, amount, actorId, actorName, reason, key)
    if key ~= nil then return keyedSocietyMove('treasury_funding', department, amount, 'treasury_funding', actorId, actorName, reason, key) end
    amount = round2(amount)
    if not department or department == '' then return false, 'invalid_department' end
    if amount <= 0 then return false, 'invalid_amount' end

    local monthKey = currentMonthKey()
    EnsureDepartmentBudgetMonth(department, monthKey)
    local row = MySQL.single.await('SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1', { department, monthKey })
    if not row then return false, 'department_not_found' end

    local treasuryOk, treasuryMsg = WithdrawFromTreasury(amount, reason or ('Treasury funding for ' .. department), actorId, actorName)
    if not treasuryOk then return false, treasuryMsg or 'treasury_withdraw_failed' end

    local before = getSocietyBalance(row.linked_society_name)
    local added = addMoneyToSociety(row.linked_society_name, amount, reason or 'Treasury funding')
    if not added then
        DepositToTreasury(amount, 'adjustment', 'Rollback: failed society add', actorId)
        return false, 'society_credit_failed'
    end

    local after = getSocietyBalance(row.linked_society_name)
    syncSocietyBalanceInDb(department, row.linked_society_name, after)

    MySQL.insert.await(
        'INSERT INTO pf_gov_budget_transactions (department, month_key, transaction_type, category, amount, society_before, society_after, actor_id, actor_name, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { department, monthKey, 'treasury_funding', 'treasury_funding', amount, before, after, actorId, actorName, reason or 'Treasury funding' }
    )

    LogAudit('department_treasury_funding', actorId or 'system', actorName or 'System', 'department_budget', department, {
        department = department,
        amount = amount,
        month_key = monthKey,
        reason = reason
    })

    local _, snapshot = RecalculateDepartmentMonthlyRequirements(department)
    triggerInfrastructureRefreshNow()
    return true, snapshot
end

--- Spends from a department's society account. `key` (optional) as for AddFundsToDepartmentSociety.
function SpendFromDepartmentSociety(department, amount, category, actorId, actorName, reason, key)
    if key ~= nil then return keyedSocietyMove('society_spend', department, amount, category, actorId, actorName, reason, key) end
    amount = round2(amount)
    category = tostring(category or 'operations'):lower()

    if not department or department == '' then return false, 'invalid_department' end
    if amount <= 0 then return false, 'invalid_amount' end
    if not SPEND_CATEGORIES[category] then return false, 'invalid_category' end

    local monthKey = currentMonthKey()
    EnsureDepartmentBudgetMonth(department, monthKey)
    local row = MySQL.single.await('SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1', { department, monthKey })
    if not row then return false, 'department_not_found' end

    local before = getSocietyBalance(row.linked_society_name)
    if before < amount then
        return false, 'insufficient_society_funds'
    end

    local spent = removeMoneyFromSociety(row.linked_society_name, amount, reason or 'Department spend')
    if not spent then return false, 'society_debit_failed' end

    local after = getSocietyBalance(row.linked_society_name)
    local newSpent = round2(asNumber(row.spent_this_month, 0) + amount)

    MySQL.update.await('UPDATE pf_gov_department_monthly_plans SET spent_this_month = ?, society_balance = ? WHERE id = ?', {
        newSpent, after, row.id
    })

    MySQL.insert.await(
        'INSERT INTO pf_gov_budget_transactions (department, month_key, transaction_type, category, amount, society_before, society_after, actor_id, actor_name, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { department, monthKey, 'society_spend', category, amount, before, after, actorId, actorName, reason or category }
    )

    LogAudit('department_society_spend', actorId or 'system', actorName or 'System', 'department_budget', department, {
        department = department,
        amount = amount,
        category = category,
        month_key = monthKey,
        reason = reason
    })

    local _, snapshot = RecalculateDepartmentMonthlyRequirements(department)
    triggerInfrastructureRefreshNow()
    return true, snapshot
end

-- ── keyed society moves (schema v6) ─────────────────────────────────────
-- The move's row in pf_gov_budget_transactions is written first, under the caller's key (unique):
--   pending  the ledger move is under way, or its outcome is not known yet: never moved again under
--            a new key; ReconcileBudgetMoves settles it from the ledger
--   failed   the ledger clearly refused it (nothing moved): a retry with the same key moves the
--            money under the next numbered ledger key (<key>:1, <key>:2, ...)
--   applied  moved and booked: a retry returns the first result, nothing moves again

local keyLocks = {}

local function validMoveKey(k)
    -- the ledger key adds ':<n>' and must stay within 128 characters
    return type(k) == 'string' and #k >= 1 and #k <= 120 and k:match('^[%w%-_:%.]+$') ~= nil
end

local function treasuryIsLedger()
    return Config.Treasury and Config.Treasury.UseSocietyAccount and Config.Treasury.SocietyAccount
        and Config.Treasury.SocietyAccount ~= '' and isBankingAvailable()
end

local function moveRow(key)
    return MySQL.single.await('SELECT * FROM pf_gov_budget_transactions WHERE idem_key = ? LIMIT 1', { key })
end

-- the ledger's stored transfer as a result IsClearFailure understands
local function ledgerResult(key)
    if not isBankingAvailable() then return nil end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
    if not ok or type(tx) ~= 'table' then return nil end
    return { ok = tx.state == 'completed', state = tx.state, error = tx.error, txId = tx.tx_id }
end

--- Books an applied move once: the row turns 'applied' (only from pending/failed), then the plan's
--- balance and spend, the treasury mirror and the audit follow.
local function bookKeyedMove(row, actorId, actorName)
    local department = row.department
    local plan = MySQL.single.await('SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1', { department, currentMonthKey() })
    local society = plan and plan.linked_society_name or getLinkedSocietyName(department)
    local after = getSocietyBalance(society)
    local n = MySQL.update.await("UPDATE pf_gov_budget_transactions SET state = 'applied', society_after = ? WHERE id = ? AND state IN ('pending', 'failed')", { after, row.id })
    if asNumber(n, 0) < 1 then return false end
    local amount = round2(asNumber(row.amount, 0))
    if row.transaction_type == 'society_spend' then
        if plan then
            MySQL.update.await('UPDATE pf_gov_department_monthly_plans SET spent_this_month = spent_this_month + ?, society_balance = ? WHERE id = ?', { amount, after, plan.id })
        end
        LogAudit('department_society_spend', actorId or row.actor_id or 'system', actorName or row.actor_name or 'System', 'department_budget', department, {
            department = department, amount = amount, category = row.category, month_key = row.month_key, reason = row.reason, key = row.idem_key,
        })
    else
        syncSocietyBalanceInDb(department, society, after)
        if treasuryIsLedger() then
            -- the money left the treasury account in the ledger transfer; refresh the mirror (a zero
            -- adjustment moves nothing) and keep the treasury's own log
            local balance = GetTreasuryBalance()
            UpdateTreasuryBalance(balance, actorId or row.actor_id)
            LogTransaction('withdrawal', amount, balance + amount, balance, nil, nil, row.reason, actorId or row.actor_id)
        else
            -- a treasury kept as a number (no ledger account): it is lowered once the society holds the money
            WithdrawFromTreasury(amount, row.reason or ('Treasury funding for ' .. department), actorId or row.actor_id, actorName or row.actor_name)
        end
        LogAudit('department_treasury_funding', actorId or row.actor_id or 'system', actorName or row.actor_name or 'System', 'department_budget', department, {
            department = department, amount = amount, month_key = row.month_key, reason = row.reason, key = row.idem_key,
        })
    end
    return true
end

local function keyedMoveLocked(txType, department, amount, category, actorId, actorName, reason, key)
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then return false, 'db_unavailable' end
    if not isBankingAvailable() then return false, 'bank_unavailable' end
    local monthKey = currentMonthKey()
    EnsureDepartmentBudgetMonth(department, monthKey)
    local plan = MySQL.single.await('SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1', { department, monthKey })
    if not plan then return false, 'department_not_found' end
    local society = plan.linked_society_name

    local row = moveRow(key)
    if row then
        if row.department ~= department or row.transaction_type ~= txType or row.category ~= category
            or math.abs(round2(asNumber(row.amount, 0)) - amount) >= 0.005 then
            return false, 'key_reused'
        end
        if row.state == 'applied' or row.state == nil then
            local _, snapshot = RecalculateDepartmentMonthlyRequirements(department)
            return true, snapshot, 'duplicate'
        end
    end

    -- the next ledger attempt: <key>:1, or the next number after attempts the ledger refused
    local ledgerKey, status = GovAttemptKey(key)
    if ledgerKey == false then return false, 'bank_unavailable' end
    if status == 'unclear' then
        -- held: the row stays (or becomes) pending under that ledger key, so the reconcile books it
        if row then
            MySQL.update.await("UPDATE pf_gov_budget_transactions SET state = 'pending', ledger_key = ? WHERE id = ? AND state <> 'applied'", { ledgerKey, row.id })
        else
            MySQL.insert.await([[INSERT IGNORE INTO pf_gov_budget_transactions
                (department, month_key, transaction_type, category, amount, actor_id, actor_name, reason, idem_key, state, ledger_key)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)]], { department, monthKey, txType, category, amount, actorId, actorName, reason, key, ledgerKey })
        end
        return false, 'payment_unclear'
    end
    if status ~= 'completed' then
        local before = getSocietyBalance(society)
        if txType == 'society_spend' and before < amount then return false, 'insufficient_society_funds' end
        if txType == 'treasury_funding' and not (Config.Treasury and Config.Treasury.AllowNegative) and GetTreasuryBalance() < amount then
            return false, 'Insufficient treasury funds'
        end
        if row then
            MySQL.update.await("UPDATE pf_gov_budget_transactions SET state = 'pending', ledger_key = ?, society_before = ? WHERE id = ? AND state = 'failed'", { ledgerKey, before, row.id })
        else
            local id = MySQL.insert.await([[INSERT IGNORE INTO pf_gov_budget_transactions
                (department, month_key, transaction_type, category, amount, society_before, society_after, actor_id, actor_name, reason, idem_key, state, ledger_key)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)]], {
                department, monthKey, txType, category, amount, before, before, actorId, actorName,
                reason or (txType == 'society_spend' and category or 'Treasury funding'), key, ledgerKey,
            })
            if asNumber(id, 0) < 1 then return false, 'busy' end   -- another server wrote this key meanwhile
        end
        row = moveRow(key)

        local res
        local text = reason or (txType == 'society_spend' and 'Department spend' or 'Treasury funding')
        if txType == 'society_spend' then
            local ok, moved, r = pcall(function() return exports['pfm-banking']:RemoveMoney(society, amount, text, ledgerKey) end)
            res = ok and type(r) == 'table' and r or { ok = ok and moved == true, error = ok and nil or 'bank_unavailable' }
        elseif treasuryIsLedger() then
            res = PFPayout.Transfer({
                from = 'society:' .. Config.Treasury.SocietyAccount, to = 'society:' .. society, amount = amount,
                key = ledgerKey, kind = 'transfer', reason = text, actor = actorId,
            })
        else
            local ok, moved, r = pcall(function() return exports['pfm-banking']:AddMoney(society, amount, text, ledgerKey) end)
            res = ok and type(r) == 'table' and r or { ok = ok and moved == true, error = ok and nil or 'bank_unavailable' }
        end
        if not res.ok then
            if PFPayout.IsClearFailure(res) then
                MySQL.update.await("UPDATE pf_gov_budget_transactions SET state = 'failed' WHERE id = ? AND state = 'pending'", { row.id })
                if res.error == 'insufficient_funds' then
                    return false, txType == 'society_spend' and 'insufficient_society_funds' or 'Insufficient treasury funds'
                end
                return false, txType == 'society_spend' and 'society_debit_failed' or 'society_credit_failed'
            end
            return false, 'payment_unclear'   -- held as pending: the reconcile books it once the ledger knows
        end
    end

    row = row or moveRow(key)
    if not row then
        -- the ledger moved it under an earlier attempt but our row is gone (restored backup): write it now
        MySQL.insert.await([[INSERT IGNORE INTO pf_gov_budget_transactions
            (department, month_key, transaction_type, category, amount, actor_id, actor_name, reason, idem_key, state, ledger_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)]], { department, monthKey, txType, category, amount, actorId, actorName, reason, key, ledgerKey })
        row = moveRow(key)
    end
    if row then
        MySQL.update.await('UPDATE pf_gov_budget_transactions SET ledger_key = ? WHERE id = ?', { ledgerKey, row.id })
        bookKeyedMove(row, actorId, actorName)
    end
    local _, snapshot = RecalculateDepartmentMonthlyRequirements(department)
    triggerInfrastructureRefreshNow()
    return true, snapshot
end

keyedSocietyMove = function(txType, department, amount, category, actorId, actorName, reason, key)
    amount = round2(amount)
    category = tostring(category or 'operations'):lower()
    if type(department) ~= 'string' or department == '' then return false, 'invalid_department' end
    if amount <= 0 or amount ~= amount or amount == math.huge then return false, 'invalid_amount' end
    if txType == 'society_spend' and not SPEND_CATEGORIES[category] then return false, 'invalid_category' end
    if not validMoveKey(key) then return false, 'invalid_key' end
    if reason ~= nil then reason = tostring(reason):gsub('%c', ' '):sub(1, 255) end
    -- one move per key at a time, taken before the first database wait
    if keyLocks[key] then return false, 'busy' end
    keyLocks[key] = true
    local ok, a, b, c = pcall(keyedMoveLocked, txType, department, amount, category, actorId, actorName, reason, key)
    keyLocks[key] = nil
    if not ok then
        print('^1[PF-GOVERNMENT]^7 keyed budget move failed: ' .. tostring(a))
        return false, 'db_unavailable'
    end
    return a, b, c
end

--- Settles keyed moves left pending (an unclear ledger answer, a crash between the move and the
--- booking): completed in the ledger -> booked once; clearly refused -> failed (a retry may move
--- it under the next numbered key); still unknown -> left pending. Returns how many it settled.
function ReconcileBudgetMoves()
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) or not isBankingAvailable() then return 0 end
    local rows = MySQL.query.await("SELECT * FROM pf_gov_budget_transactions WHERE state = 'pending' AND idem_key IS NOT NULL ORDER BY id LIMIT 50") or {}
    local settled = 0
    for _, row in ipairs(rows) do
        if not keyLocks[row.idem_key] and row.ledger_key then
            keyLocks[row.idem_key] = true
            local ok, err = pcall(function()
                local res = ledgerResult(row.ledger_key)
                if res and res.ok then
                    if bookKeyedMove(row) then
                        settled = settled + 1
                        RecalculateDepartmentMonthlyRequirements(row.department)
                    end
                elseif res and PFPayout.IsClearFailure(res) then
                    settled = settled + asNumber(MySQL.update.await("UPDATE pf_gov_budget_transactions SET state = 'failed' WHERE id = ? AND state = 'pending'", { row.id }), 0)
                end
            end)
            keyLocks[row.idem_key] = nil
            if not ok then print('^1[PF-GOVERNMENT]^7 budget move reconcile failed: ' .. tostring(err)) end
        end
    end
    return settled
end

--- Records money another module paid out of a department's society account through the ledger
--- (e.g. a work order payout) in the department's books, once per key. Moves no money.
function BudgetRecordSocietyPayout(department, amount, category, reason, key)
    amount = round2(amount)
    category = SPEND_CATEGORIES[category] and category or 'operations'
    if type(department) ~= 'string' or amount <= 0 or not validMoveKey(key) then return false end
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then return false end
    local monthKey = currentMonthKey()
    EnsureDepartmentBudgetMonth(department, monthKey)
    local plan = MySQL.single.await('SELECT * FROM pf_gov_department_monthly_plans WHERE department = ? AND month_key = ? LIMIT 1', { department, monthKey })
    if not plan then return false end
    local after = getSocietyBalance(plan.linked_society_name)
    local id = MySQL.insert.await([[INSERT IGNORE INTO pf_gov_budget_transactions
        (department, month_key, transaction_type, category, amount, society_before, society_after, actor_id, actor_name, reason, idem_key, state, ledger_key)
        VALUES (?, ?, 'society_spend', ?, ?, ?, ?, 'system', 'System', ?, ?, 'applied', ?)]], {
        department, monthKey, category, amount, round2(after + amount), after, reason, key, key,
    })
    if asNumber(id, 0) < 1 then return false end   -- recorded before
    MySQL.update.await('UPDATE pf_gov_department_monthly_plans SET spent_this_month = spent_this_month + ?, society_balance = ? WHERE id = ?', { amount, after, plan.id })
    return true
end

function GetDepartmentMonthlyBudgetSnapshot(department)
    EnsureDepartmentBudgetMonth(department, currentMonthKey())
    local snapshot = buildSnapshotForDepartment(department)
    if snapshot then
        BudgetCache[department] = snapshot
    end
    return snapshot
end

local function getDepartmentTransactions(department, monthKey, limit)
    return MySQL.query.await(
        'SELECT * FROM pf_gov_budget_transactions WHERE department = ? AND month_key = ? ORDER BY id DESC LIMIT ?',
        { department, monthKey, math.max(1, math.floor(asNumber(limit, 50))) }
    ) or {}
end

function GetAllBudgetDetails()
    local monthKey = currentMonthKey()
    ensureCurrentMonthRows()
    local rows = MySQL.query.await('SELECT department FROM pf_gov_department_monthly_plans WHERE month_key = ? ORDER BY department ASC', { monthKey }) or {}
    local out = {}

    for _, row in ipairs(rows) do
        local snap = buildSnapshotForDepartment(row.department)
        if snap then
            out[#out + 1] = snap
            BudgetCache[row.department] = snap
        end
    end

    return out
end

local function setDepartmentMonthlyBudget(department, approvedMonthlyBudget, updatedBy)
    approvedMonthlyBudget = round2(approvedMonthlyBudget)
    if not department or department == '' then return false, 'invalid_department' end
    if approvedMonthlyBudget < 0 then return false, 'invalid_budget' end

    local monthKey = currentMonthKey()
    local current = EnsureDepartmentBudgetMonth(department, monthKey)
    local oldBudget = current and round2(current.approved_monthly_budget) or nil
    local society = getLinkedSocietyName(department)
    ensureSocietyAccount(society)

    local affected = MySQL.update.await(
        'UPDATE pf_gov_department_monthly_plans SET approved_monthly_budget = ?, linked_society_name = ?, updated_by = ? WHERE department = ? AND month_key = ?',
        { approvedMonthlyBudget, society, updatedBy, department, monthKey }
    )

    if not affected or affected == 0 then
        MySQL.insert.await(
            'INSERT INTO pf_gov_department_monthly_plans (department, month_key, approved_monthly_budget, linked_society_name, society_balance, updated_by) VALUES (?, ?, ?, ?, ?, ?)',
            { department, monthKey, approvedMonthlyBudget, society, getSocietyBalance(society), updatedBy }
        )
    end

    local _, snapshot = RecalculateDepartmentMonthlyRequirements(department)
    triggerInfrastructureRefreshNow()
    return true, snapshot, oldBudget
end

function CheckBudgetReset()
    -- Legacy weekly reset flow disabled; only monthly row carry-forward remains.
    ensureCurrentMonthRows()
    return true
end

function InitializeBudgets()
    ensureBudgetTables()
    ensureCurrentMonthRows()

    local details = GetAllBudgetDetails()
    for _, row in ipairs(details) do
        BudgetCache[row.department] = row
    end

    print(('^2[PF-GOVERNMENT]^7 Monthly budget system loaded (%d departments)'):format(#details))
end

-- =====================================================
-- LEGACY-COMPAT WRAPPERS
-- =====================================================

function GetBudget(department)
    return BudgetCache[department] or GetDepartmentMonthlyBudgetSnapshot(department)
end

function GetAllBudgets()
    return BudgetCache
end

function SetBudget(department, monthlyBudget, updatedBy, updatedByName)
    local ok, result, oldBudget = setDepartmentMonthlyBudget(department, monthlyBudget, updatedBy)
    if not ok then return false, result end

    LogAudit('budget_change', updatedBy, updatedByName, 'budget', department, {
        department = department,
        new_budget = monthlyBudget,
        model = 'monthly'
    })

    local newBudget = round2(monthlyBudget)
    if oldBudget ~= nil and oldBudget ~= newBudget then
        local label = (Config.Budgets and Config.Budgets.DepartmentNames and Config.Budgets.DepartmentNames[department]) or department
        GovEmit('gov.budget.changed', {
            department = department, label = label, oldBudget = oldBudget, newBudget = newBudget,
            change = round2(newBudget - oldBudget), direction = newBudget > oldBudget and 'up' or 'down',
        }, {
            title = ('%s budget %s to $%s a month'):format(label, newBudget > oldBudget and 'raised' or 'cut', tostring(newBudget)),
            actor = updatedBy,
        })
    end

    return true, 'Monthly budget updated successfully'
end

function SpendFromBudget(department, amount, reason, spentBy)
    return false, 'legacy_budget_system_disabled'
end

function ResetBudget(department)
    return false, 'legacy_budget_system_disabled'
end

function ResetAllBudgets()
    return false, 'legacy_budget_system_disabled'
end

function LoadBudgets()
    return true
end

-- =====================================================
-- NUI CALLBACKS
-- =====================================================

RegisterNUICallback('budget:getAll', function(_, cb)
    cb({ ok = true, budgets = GetAllBudgetDetails() })
end)

RegisterNUICallback('budget:getSnapshot', function(data, cb)
    local department = data and data.department
    if not department or department == '' then
        cb({ ok = false, error = 'invalid_department' })
        return
    end

    local snapshot = GetDepartmentMonthlyBudgetSnapshot(department)
    if not snapshot then
        cb({ ok = false, error = 'not_found' })
        return
    end

    cb({
        ok = true,
        snapshot = snapshot,
        transactions = getDepartmentTransactions(department, currentMonthKey(), 100)
    })
end)

RegisterNUICallback('budget:update', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local department = data.department
    local monthlyBudget = asNumber(data.monthlyBudget, asNumber(data.approvedMonthlyBudget, asNumber(data.weeklyBudget, -1)))
    if not department or monthlyBudget < 0 then
        cb({ ok = false, error = 'missing_data' })
        return
    end

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)

    local ok, result = SetBudget(department, monthlyBudget, citizenid, name)
    cb({ ok = ok, message = ok and 'Monthly budget updated' or tostring(result), snapshot = ok and GetDepartmentMonthlyBudgetSnapshot(department) or nil })
end)

RegisterNUICallback('budget:allocate', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local department = data.department
    local amount = asNumber(data.amount, 0)
    local reason = data.reason or 'Treasury funding transfer'
    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)

    local ok, result = AddFundsToDepartmentSociety(department, amount, actorId, actorName, reason)
    cb({ ok = ok, message = ok and 'Funding transferred to linked society account' or tostring(result), snapshot = ok and result or nil })
end)

RegisterNUICallback('budget:spend', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local department = data.department
    local amount = asNumber(data.amount, 0)
    local category = data.category or 'operations'
    local reason = data.reason or 'Department expense'
    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)

    local ok, result = SpendFromDepartmentSociety(department, amount, category, actorId, actorName, reason)
    cb({ ok = ok, message = ok and 'Department spend recorded' or tostring(result), snapshot = ok and result or nil })
end)

RegisterNUICallback('budget:reset', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    cb({ ok = false, error = 'legacy_budget_system_disabled' })
end)

print('^2[PF-GOVERNMENT]^7 Budget module (monthly + linked society) loaded')

exports('GetAllBudgetDetails', function()
    return GetAllBudgetDetails()
end)

exports('SetDepartmentBudget', function(department, monthlyBudget, updatedBy, updatedByName)
    return SetBudget(department, monthlyBudget, updatedBy, updatedByName)
end)

exports('GetDepartmentSocietyBalance', function(department)
    return GetDepartmentSocietyBalance(department)
end)

-- key (optional, last): a stable id of this real-world move; the same key never moves money twice.
-- Returns ok, snapshot | error ('payment_unclear': the bank has not settled it yet; retry later
-- with the SAME key), and 'duplicate' as a third value when the key had already moved.
exports('AddFundsToDepartmentSociety', function(department, amount, actorId, actorName, reason, key)
    return AddFundsToDepartmentSociety(department, amount, actorId, actorName, reason, key)
end)

exports('SpendFromDepartmentSociety', function(department, amount, category, actorId, actorName, reason, key)
    return SpendFromDepartmentSociety(department, amount, category, actorId, actorName, reason, key)
end)

exports('GetDepartmentMonthlyBudgetSnapshot', function(department)
    return GetDepartmentMonthlyBudgetSnapshot(department)
end)

exports('RecalculateDepartmentMonthlyRequirements', function(department)
    return RecalculateDepartmentMonthlyRequirements(department)
end)
