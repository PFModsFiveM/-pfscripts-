-- =====================================================
-- CITY INFRASTRUCTURE SYSTEM
-- =====================================================

local Infrastructure = {
    DepartmentState = {},
    DistrictState = {},
    WeeklyState = nil,
    LastSimulationRun = 0,
    LastSnapshotRun = 0,
    LastAlertHash = ''
}

local function asNumber(value, default)
    local parsed = tonumber(value)
    if parsed == nil then
        return default or 0
    end
    return parsed
end

local function asBool(value)
    if type(value) == 'boolean' then
        return value
    end
    if type(value) == 'number' then
        return value == 1
    end
    if type(value) == 'string' then
        local lowered = value:lower()
        return lowered == '1' or lowered == 'true'
    end
    return false
end

local function clamp(value, minValue, maxValue)
    value = asNumber(value, 0)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function roundCurrency(value)
    value = asNumber(value, 0)
    return math.floor((value * 100) + 0.5) / 100
end

local function utcDateTimeNow()
    return os.date('!%Y-%m-%d %H:%M:%S')
end

local function formatDateTime(epoch)
    return os.date('!%Y-%m-%d %H:%M:%S', epoch)
end

local function parseDateTime(value)
    if not value or value == '' then
        return nil
    end

    if type(value) == 'number' then
        return value
    end

    local year, month, day, hour, minute, second = tostring(value):match('^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)$')
    if not year then
        return nil
    end

    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second)
    })
end

local function getOnlinePlayerCount()
    local players = GetPlayers() or {}
    return #players
end

local function getInfrastructureConfig()
    return Config.Infrastructure or {}
end

local function getDepartmentConfig(department)
    local departments = getInfrastructureConfig().Departments or {}
    return departments[department]
end

local function getDepartmentPriority()
    return getInfrastructureConfig().DepartmentPriority or {}
end

local function getDepartmentJobName(department)
    local map = getInfrastructureConfig().DepartmentJobMap or {}
    return map[department]
end

local function getPayrollBounds()
    local payroll = getInfrastructureConfig().Payroll or {}
    return asNumber(payroll.PaycheckMultiplierMin, 0.5), asNumber(payroll.PaycheckMultiplierMax, 2.0)
end

local function ensureInfrastructureTables()
    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_department_state` (
            `department` VARCHAR(50) PRIMARY KEY,
            `budget_allocated` DECIMAL(15,2) DEFAULT 0,
            `weekly_upkeep_base` DECIMAL(15,2) DEFAULT 0,
            `weekly_upkeep_dynamic` DECIMAL(15,2) DEFAULT 0,
            `reserve_current` DECIMAL(15,2) DEFAULT 0,
            `reserve_max` DECIMAL(15,2) DEFAULT 0,
            `condition_percent` DECIMAL(5,2) DEFAULT 100,
            `staffing_score` DECIMAL(5,2) DEFAULT 100,
            `morale_percent` DECIMAL(5,2) DEFAULT 100,
            `risk_level` VARCHAR(20) DEFAULT 'low',
            `upgrade_tier` INT DEFAULT 0,
            `support_received_this_cycle` DECIMAL(15,2) DEFAULT 0,
            `last_upkeep_paid_at` DATETIME NULL,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_district_state` (
            `district_name` VARCHAR(50) PRIMARY KEY,
            `power_stage` INT DEFAULT 1,
            `water_stage` INT DEFAULT 1,
            `dot_stage` INT DEFAULT 1,
            `lighting_enabled` TINYINT(1) DEFAULT 1,
            `traffic_enabled` TINYINT(1) DEFAULT 1,
            `road_condition` DECIMAL(5,2) DEFAULT 100,
            `hydrant_pressure` DECIMAL(5,2) DEFAULT 100,
            `blackout_flicker_enabled` TINYINT(1) DEFAULT 0,
            `priority_order` INT DEFAULT 100,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_upkeep_cycles` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `cycle_start` DATETIME NOT NULL,
            `cycle_end` DATETIME NOT NULL,
            `treasury_before` DECIMAL(15,2) DEFAULT 0,
            `total_required` DECIMAL(15,2) DEFAULT 0,
            `shortfall` DECIMAL(15,2) DEFAULT 0,
            `support_received` DECIMAL(15,2) DEFAULT 0,
            `treasury_after` DECIMAL(15,2) DEFAULT 0,
            `status` VARCHAR(20) DEFAULT 'completed',
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_treasury_snapshots` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `recorded_at` DATETIME NOT NULL,
            `treasury_balance` DECIMAL(15,2) DEFAULT 0,
            `online_players` INT DEFAULT 0,
            `weekly_tax_revenue` DECIMAL(15,2) DEFAULT 0,
            `weekly_other_revenue` DECIMAL(15,2) DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_support_history` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `support_type` VARCHAR(50) NOT NULL,
            `reason` VARCHAR(255) NOT NULL,
            `amount` DECIMAL(15,2) DEFAULT 0,
            `granted_at` DATETIME NOT NULL,
            `cycle_id` INT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_weekly_state` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `last_upkeep_paid_at` DATETIME NULL,
            `next_upkeep_due_at` DATETIME NULL,
            `running_tax_revenue` DECIMAL(15,2) DEFAULT 0,
            `running_other_revenue` DECIMAL(15,2) DEFAULT 0,
            `running_avg_population` DECIMAL(10,2) DEFAULT 0,
            `snapshot_count` INT DEFAULT 0,
            `support_dependency_level` DECIMAL(5,2) DEFAULT 0,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_payroll_overrides` (
            `department` VARCHAR(50) PRIMARY KEY,
            `paycheck_multiplier` DECIMAL(5,2) DEFAULT 1.00,
            `updated_by` VARCHAR(64) NULL,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

local function seedDepartmentState()
    local departments = getInfrastructureConfig().Departments or {}

    for department, cfg in pairs(departments) do
        local baseline = roundCurrency(asNumber(cfg.baseline_upkeep, 0))
        local reserveMax = roundCurrency(asNumber(cfg.reserve_max, 0))
        local reserveStart = clamp(roundCurrency(asNumber(cfg.reserve_start, reserveMax)), 0, reserveMax)

        MySQL.insert.await(
            'INSERT IGNORE INTO pf_gov_department_state (department, budget_allocated, weekly_upkeep_base, weekly_upkeep_dynamic, reserve_current, reserve_max, condition_percent, staffing_score, morale_percent, risk_level, upgrade_tier, support_received_this_cycle, last_upkeep_paid_at) VALUES (?, ?, ?, 0, ?, ?, 100, 100, 100, ?, 0, 0, NULL)',
            { department, baseline, baseline, reserveStart, reserveMax, 'low' }
        )
    end
end

local function seedDistrictState()
    local districts = getInfrastructureConfig().Districts or {}

    for district, cfg in pairs(districts) do
        MySQL.insert.await(
            'INSERT IGNORE INTO pf_gov_district_state (district_name, power_stage, water_stage, dot_stage, lighting_enabled, traffic_enabled, road_condition, hydrant_pressure, blackout_flicker_enabled, priority_order) VALUES (?, 1, 1, 1, 1, 1, 100, 100, 0, ?)',
            { district, asNumber(cfg.priority, 100) }
        )
    end
end

local function seedWeeklyState()
    local existing = MySQL.single.await('SELECT id FROM pf_gov_weekly_state ORDER BY id ASC LIMIT 1', {})
    if existing then
        return
    end

    local now = os.time()
    local interval = asNumber(getInfrastructureConfig().UpkeepIntervalSeconds, 604800)

    MySQL.insert.await(
        'INSERT INTO pf_gov_weekly_state (last_upkeep_paid_at, next_upkeep_due_at, running_tax_revenue, running_other_revenue, running_avg_population, snapshot_count, support_dependency_level) VALUES (?, ?, 0, 0, 0, 0, 0)',
        { formatDateTime(now), formatDateTime(now + interval) }
    )
end

local function seedPayrollOverrides()
    local jobMap = getInfrastructureConfig().DepartmentJobMap or {}
    for department, _ in pairs(jobMap) do
        MySQL.insert.await('INSERT IGNORE INTO pf_gov_payroll_overrides (department, paycheck_multiplier) VALUES (?, 1.00)', { department })
    end
end

local function loadDepartmentState()
    Infrastructure.DepartmentState = {}

    local rows = MySQL.query.await('SELECT * FROM pf_gov_department_state', {}) or {}
    for _, row in ipairs(rows) do
        Infrastructure.DepartmentState[row.department] = {
            department = row.department,
            budget_allocated = roundCurrency(asNumber(row.budget_allocated, 0)),
            weekly_upkeep_base = roundCurrency(asNumber(row.weekly_upkeep_base, 0)),
            weekly_upkeep_dynamic = roundCurrency(asNumber(row.weekly_upkeep_dynamic, 0)),
            reserve_current = roundCurrency(asNumber(row.reserve_current, 0)),
            reserve_max = roundCurrency(asNumber(row.reserve_max, 0)),
            condition_percent = clamp(asNumber(row.condition_percent, 100), 0, 100),
            staffing_score = clamp(asNumber(row.staffing_score, 100), 0, 100),
            morale_percent = clamp(asNumber(row.morale_percent, 100), 0, 100),
            risk_level = tostring(row.risk_level or 'low'),
            upgrade_tier = math.max(0, math.floor(asNumber(row.upgrade_tier, 0))),
            support_received_this_cycle = roundCurrency(asNumber(row.support_received_this_cycle, 0)),
            last_upkeep_paid_at = row.last_upkeep_paid_at,
            updated_at = row.updated_at
        }
    end
end

local function loadDistrictState()
    Infrastructure.DistrictState = {}

    local rows = MySQL.query.await('SELECT * FROM pf_gov_district_state ORDER BY priority_order ASC, district_name ASC', {}) or {}
    for _, row in ipairs(rows) do
        Infrastructure.DistrictState[row.district_name] = {
            district_name = row.district_name,
            power_stage = math.max(1, math.floor(asNumber(row.power_stage, 1))),
            water_stage = math.max(1, math.floor(asNumber(row.water_stage, 1))),
            dot_stage = math.max(1, math.floor(asNumber(row.dot_stage, 1))),
            lighting_enabled = asBool(row.lighting_enabled),
            traffic_enabled = asBool(row.traffic_enabled),
            road_condition = clamp(asNumber(row.road_condition, 100), 0, 100),
            hydrant_pressure = clamp(asNumber(row.hydrant_pressure, 100), 0, 100),
            blackout_flicker_enabled = asBool(row.blackout_flicker_enabled),
            priority_order = asNumber(row.priority_order, 100),
            updated_at = row.updated_at
        }
    end
end

local function loadWeeklyState()
    local row = MySQL.single.await('SELECT * FROM pf_gov_weekly_state ORDER BY id ASC LIMIT 1', {})
    if row then
        Infrastructure.WeeklyState = row
    end
end

local function getWeeklyState()
    if Infrastructure.WeeklyState then
        return Infrastructure.WeeklyState
    end
    loadWeeklyState()
    return Infrastructure.WeeklyState
end

local function saveDepartmentState(state)
    MySQL.update.await([[ 
        UPDATE pf_gov_department_state
        SET budget_allocated = ?, weekly_upkeep_base = ?, weekly_upkeep_dynamic = ?, reserve_current = ?, reserve_max = ?, condition_percent = ?, staffing_score = ?, morale_percent = ?, risk_level = ?, upgrade_tier = ?, support_received_this_cycle = ?, last_upkeep_paid_at = ?
        WHERE department = ?
    ]], {
        roundCurrency(state.budget_allocated),
        roundCurrency(state.weekly_upkeep_base),
        roundCurrency(state.weekly_upkeep_dynamic),
        roundCurrency(state.reserve_current),
        roundCurrency(state.reserve_max),
        clamp(state.condition_percent, 0, 100),
        clamp(state.staffing_score, 0, 100),
        clamp(state.morale_percent, 0, 100),
        tostring(state.risk_level or 'low'),
        math.max(0, math.floor(asNumber(state.upgrade_tier, 0))),
        roundCurrency(state.support_received_this_cycle),
        state.last_upkeep_paid_at,
        state.department
    })
end

local function saveDistrictState(state)
    MySQL.update.await([[ 
        UPDATE pf_gov_district_state
        SET power_stage = ?, water_stage = ?, dot_stage = ?, lighting_enabled = ?, traffic_enabled = ?, road_condition = ?, hydrant_pressure = ?, blackout_flicker_enabled = ?, priority_order = ?
        WHERE district_name = ?
    ]], {
        math.max(1, math.floor(asNumber(state.power_stage, 1))),
        math.max(1, math.floor(asNumber(state.water_stage, 1))),
        math.max(1, math.floor(asNumber(state.dot_stage, 1))),
        state.lighting_enabled and 1 or 0,
        state.traffic_enabled and 1 or 0,
        clamp(state.road_condition, 0, 100),
        clamp(state.hydrant_pressure, 0, 100),
        state.blackout_flicker_enabled and 1 or 0,
        asNumber(state.priority_order, 100),
        state.district_name
    })
end

local function saveWeeklyState(state)
    if not state then
        return
    end

    MySQL.update.await([[ 
        UPDATE pf_gov_weekly_state
        SET last_upkeep_paid_at = ?, next_upkeep_due_at = ?, running_tax_revenue = ?, running_other_revenue = ?, running_avg_population = ?, snapshot_count = ?, support_dependency_level = ?
        WHERE id = ?
    ]], {
        state.last_upkeep_paid_at,
        state.next_upkeep_due_at,
        roundCurrency(asNumber(state.running_tax_revenue, 0)),
        roundCurrency(asNumber(state.running_other_revenue, 0)),
        roundCurrency(asNumber(state.running_avg_population, 0)),
        math.max(0, math.floor(asNumber(state.snapshot_count, 0))),
        clamp(asNumber(state.support_dependency_level, 0), 0, 100),
        state.id
    })
end

local function computeRiskLevel(conditionPercent, reserveCurrent, reserveMax)
    conditionPercent = clamp(conditionPercent, 0, 100)
    reserveCurrent = asNumber(reserveCurrent, 0)
    reserveMax = math.max(0, asNumber(reserveMax, 0))

    local reserveRatio = reserveMax > 0 and (reserveCurrent / reserveMax) or 0

    if conditionPercent <= 25 or reserveRatio <= 0.05 then
        return 'critical'
    end

    if conditionPercent <= 45 or reserveRatio <= 0.20 then
        return 'high'
    end

    if conditionPercent <= 70 or reserveRatio <= 0.40 then
        return 'medium'
    end

    return 'low'
end

local function getPayrollMultiplier(department)
    local row = MySQL.single.await('SELECT paycheck_multiplier FROM pf_gov_payroll_overrides WHERE department = ? LIMIT 1', { department })
    if not row then
        return 1.0
    end
    return asNumber(row.paycheck_multiplier, 1.0)
end

local function getJobDefinition(jobName)
    if not QBCore or not QBCore.Shared or not QBCore.Shared.Jobs then
        return nil
    end
    return QBCore.Shared.Jobs[jobName]
end

local function getEmployeeCountsByGrade(jobName)
    local result = {}

    local rows = MySQL.query.await(
        'SELECT job FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, "$.name")) = ?',
        { jobName }
    ) or {}

    for _, row in ipairs(rows) do
        local payload = row.job
        local decoded = nil
        if type(payload) == 'string' and payload ~= '' then
            decoded = json.decode(payload)
        elseif type(payload) == 'table' then
            decoded = payload
        end

        if decoded and tostring(decoded.name or '') == tostring(jobName) then
            local grade = decoded.grade
            local gradeLevel = nil

            if type(grade) == 'table' then
                gradeLevel = asNumber(grade.level, asNumber(grade.grade, 0))
            else
                gradeLevel = asNumber(grade, 0)
            end

            local key = tostring(math.floor(gradeLevel or 0))
            result[key] = (result[key] or 0) + 1
        end
    end

    return result
end

local function calculateDepartmentPayroll(jobName, multiplier)
    local jobDef = getJobDefinition(jobName)
    if not jobDef or type(jobDef.grades) ~= 'table' then
        return 0, 0
    end

    local counts = getEmployeeCountsByGrade(jobName)
    local totalEmployees = 0
    local totalPayroll = 0

    for gradeKey, count in pairs(counts) do
        local gradeData = jobDef.grades[gradeKey] or jobDef.grades[tonumber(gradeKey)]
        local payment = 0

        if type(gradeData) == 'table' then
            payment = asNumber(gradeData.payment, 0)
        end

        totalEmployees = totalEmployees + count
        totalPayroll = totalPayroll + (payment * count)
    end

    totalPayroll = totalPayroll * asNumber(multiplier, 1.0)

    return roundCurrency(totalPayroll), totalEmployees
end

local function getWeeklyPaycheckCycles()
    local payrollCfg = getInfrastructureConfig().Payroll or {}
    local configured = asNumber(payrollCfg.PaychecksPerWeek, 0)
    if configured > 0 then
        return math.max(1, math.floor(configured))
    end

    local timeoutMinutes = nil
    if QBCore and QBCore.Config and QBCore.Config.Money then
        timeoutMinutes = asNumber(QBCore.Config.Money.PayCheckTimeOut, 0)
    end

    if timeoutMinutes and timeoutMinutes > 0 then
        local cycles = math.floor(604800 / (timeoutMinutes * 60))
        return math.max(1, cycles)
    end

    return 1
end

local function calculateResponderWeeklyRequirement(department, qbJobName, payMultiplier)
    local payrollCfg = getInfrastructureConfig().Payroll or {}
    local equipmentMap = payrollCfg.EquipmentOverheadPerEmployee or {}
    local fleetMap = payrollCfg.FleetOverheadPerEmployee or {}
    local facilityMap = payrollCfg.FacilityOverhead or {}

    local payrollPerCycle, totalEmployees = calculateDepartmentPayroll(qbJobName, payMultiplier)
    local paychecksPerWeek = getWeeklyPaycheckCycles()
    local payrollCost = payrollPerCycle * paychecksPerWeek

    local equipmentOverhead = asNumber(equipmentMap[department], 0) * totalEmployees
    local fleetOverhead = asNumber(fleetMap[department], 0) * totalEmployees
    local facilityOverhead = asNumber(facilityMap[department], 0)

    local required = payrollCost + equipmentOverhead + fleetOverhead + facilityOverhead

    return {
        required = roundCurrency(required),
        payroll = roundCurrency(payrollCost),
        payroll_per_cycle = roundCurrency(payrollPerCycle),
        paychecks_per_week = paychecksPerWeek,
        totalEmployees = totalEmployees,
        equipment = roundCurrency(equipmentOverhead),
        fleet = roundCurrency(fleetOverhead),
        facility = roundCurrency(facilityOverhead)
    }
end

local function buildDepartmentRequirement(department)
    local state = Infrastructure.DepartmentState[department]
    local cfg = getDepartmentConfig(department)

    if not state or not cfg then
        return nil
    end

    local baseline = roundCurrency(asNumber(cfg.baseline_upkeep, state.weekly_upkeep_base or 0))
    local upgradeMultiplier = asNumber(cfg.upgrade_upkeep_multiplier, 0)
    local dynamic = roundCurrency(asNumber(state.weekly_upkeep_dynamic, 0))
    local upgradeCost = roundCurrency(baseline * upgradeMultiplier * math.max(0, asNumber(state.upgrade_tier, 0)))

    local requirement = {
        department = department,
        baseline = baseline,
        dynamic = dynamic,
        upgradeCost = upgradeCost,
        payroll = 0,
        totalEmployees = 0,
        equipment = 0,
        fleet = 0,
        facility = 0,
        required = 0
    }

    local jobName = getDepartmentJobName(department)
    if jobName and jobName ~= '' then
        local minMultiplier, maxMultiplier = getPayrollBounds()
        local multiplier = clamp(getPayrollMultiplier(department), minMultiplier, maxMultiplier)
        local responder = calculateResponderWeeklyRequirement(department, jobName, multiplier)

        requirement.payroll = responder.payroll
        requirement.totalEmployees = responder.totalEmployees
        requirement.equipment = responder.equipment
        requirement.fleet = responder.fleet
        requirement.facility = responder.facility
        requirement.required = roundCurrency(responder.required + dynamic + upgradeCost)
    else
        requirement.required = roundCurrency(baseline + dynamic + upgradeCost)
    end

    return requirement
end

local function computeAllRequirements()
    local requirements = {}
    local totalRequired = 0
    local totalUpgradeCosts = 0

    for department, _ in pairs(getInfrastructureConfig().Departments or {}) do
        local req = buildDepartmentRequirement(department)
        if req then
            requirements[department] = req
            totalRequired = totalRequired + req.required
            totalUpgradeCosts = totalUpgradeCosts + req.upgradeCost
        end
    end

    return requirements, roundCurrency(totalRequired), roundCurrency(totalUpgradeCosts)
end

local function applyDepartmentFundingResults(requirements, payable, totalRequired)
    local funding = {}
    local remaining = roundCurrency(asNumber(payable, 0))
    local priority = getDepartmentPriority()
    local seen = {}

    for _, department in ipairs(priority) do
        local req = requirements[department]
        if req then
            local required = roundCurrency(asNumber(req.required, 0))
            local funded = roundCurrency(math.min(required, remaining))
            local deficit = roundCurrency(required - funded)
            remaining = roundCurrency(remaining - funded)
            funding[department] = {
                required = required,
                funded = funded,
                deficit = deficit
            }
            seen[department] = true
        end
    end

    for department, req in pairs(requirements) do
        if not seen[department] then
            local required = roundCurrency(asNumber(req.required, 0))
            local funded = roundCurrency(math.min(required, remaining))
            local deficit = roundCurrency(required - funded)
            remaining = roundCurrency(remaining - funded)
            funding[department] = {
                required = required,
                funded = funded,
                deficit = deficit
            }
        end
    end

    local paidTotal = 0
    for _, item in pairs(funding) do
        paidTotal = paidTotal + item.funded
    end

    return funding, roundCurrency(paidTotal), roundCurrency(math.max(0, totalRequired - paidTotal))
end

local function handleDepartmentDeficit(state, deficit, required)
    local cfg = getDepartmentConfig(state.department) or {}
    deficit = roundCurrency(asNumber(deficit, 0))
    required = math.max(1, roundCurrency(asNumber(required, 0)))

    if deficit <= 0 then
        return
    end

    local reserveUse = math.min(state.reserve_current, deficit)
    state.reserve_current = roundCurrency(state.reserve_current - reserveUse)

    local remainingDeficit = roundCurrency(deficit - reserveUse)
    if remainingDeficit > 0 then
        local degradeRate = asNumber(cfg.degrade_rate, 2.0)
        local ratio = remainingDeficit / required
        local degrade = math.max(0.25, degradeRate * ratio * 20)

        state.condition_percent = clamp(state.condition_percent - degrade, 0, 100)
        state.staffing_score = clamp(state.staffing_score - (degrade * 0.5), 0, 100)
        state.morale_percent = clamp(state.morale_percent - (degrade * 0.7), 0, 100)
    else
        state.morale_percent = clamp(state.morale_percent - 0.5, 0, 100)
    end
end

local function handleDepartmentHealthyFunding(state)
    local cfg = getDepartmentConfig(state.department) or {}

    local reserveRecover = asNumber(state.weekly_upkeep_base, 0) * 0.05
    state.reserve_current = clamp(state.reserve_current + reserveRecover, 0, state.reserve_max)

    local recoverRate = asNumber(cfg.recover_rate, 1.0)
    state.condition_percent = clamp(state.condition_percent + recoverRate, 0, 100)
    state.staffing_score = clamp(state.staffing_score + (recoverRate * 0.50), 0, 100)
    state.morale_percent = clamp(state.morale_percent + (recoverRate * 0.70), 0, 100)
end

local function computeSupportGrant(shortfall, totalRequired, totalUpgradeCosts)
    local infra = getInfrastructureConfig()
    local supportCfg = infra.Support or {}
    local weekly = getWeeklyState()

    if not supportCfg.Enabled then
        return 0, 'support_disabled'
    end

    local avgPlayers = asNumber(weekly and weekly.running_avg_population or 0, 0)
    if avgPlayers >= asNumber(supportCfg.MinAveragePlayers, 15) then
        return 0, 'population_not_eligible'
    end

    shortfall = roundCurrency(asNumber(shortfall, 0))
    if shortfall <= 0 then
        return 0, 'no_shortfall'
    end

    local cushion = math.min(
        roundCurrency(asNumber(totalRequired, 0) * asNumber(supportCfg.CushionPercent, 0.20)),
        roundCurrency(asNumber(supportCfg.MaxCushionAmount, 30000))
    )

    local eligibleShortfall = shortfall
    if not supportCfg.CoversUpgrades then
        eligibleShortfall = math.max(0, shortfall - asNumber(totalUpgradeCosts, 0))
    end

    local requested = roundCurrency(eligibleShortfall + cushion)
    local maxSupport = roundCurrency(asNumber(totalRequired, 0) * asNumber(supportCfg.MaxCoveragePercent, 0.40))
    local granted = roundCurrency(math.min(requested, maxSupport))

    if granted <= 0 then
        return 0, 'support_capped_to_zero'
    end

    return granted, ('avg_players_%0.2f_shortfall_%0.2f'):format(avgPlayers, shortfall)
end

local function mapDepartmentStage(state)
    local reserveRatio = 0
    if state.reserve_max > 0 then
        reserveRatio = state.reserve_current / state.reserve_max
    end

    local condition = clamp(state.condition_percent, 0, 100)

    if condition >= 85 and reserveRatio >= 0.50 then
        return 1
    end
    if condition >= 70 and reserveRatio >= 0.35 then
        return 2
    end
    if condition >= 50 and reserveRatio >= 0.20 then
        return 3
    end
    if condition >= 30 and reserveRatio >= 0.10 then
        return 4
    end
    return 5
end

local function updatePowerDistrictStates()
    local powerState = Infrastructure.DepartmentState.power
    if not powerState then
        return
    end

    local powerStage = mapDepartmentStage(powerState)
    local ordered = {}
    for _, districtState in pairs(Infrastructure.DistrictState) do
        ordered[#ordered + 1] = districtState
    end

    table.sort(ordered, function(a, b)
        return asNumber(a.priority_order, 100) < asNumber(b.priority_order, 100)
    end)

    local count = #ordered
    for index, districtState in ipairs(ordered) do
        local appliedStage = powerStage

        if powerStage >= 4 then
            local ratio = count > 0 and (index / count) or 1
            if ratio >= 0.50 then
                appliedStage = 5
            elseif ratio >= 0.35 then
                appliedStage = math.max(appliedStage, 4)
            end
        end

        districtState.power_stage = appliedStage
        districtState.blackout_flicker_enabled = appliedStage >= 3

        saveDistrictState(districtState)
    end
end

local function updateWaterDistrictStates()
    local waterState = Infrastructure.DepartmentState.water
    if not waterState then
        return
    end

    local waterStage = mapDepartmentStage(waterState)
    local pressureLoss = asNumber((getInfrastructureConfig().Water or {}).PressureLossPerStage, 25)

    for _, districtState in pairs(Infrastructure.DistrictState) do
        local stage = waterStage
        if districtState.power_stage >= 4 then
            stage = math.min(5, stage + 1)
        elseif districtState.power_stage >= 3 then
            stage = math.min(5, stage + 0)
        end

        districtState.water_stage = stage
        local pressure = 100 - (math.max(0, stage - 1) * pressureLoss)
        districtState.hydrant_pressure = clamp(pressure, 0, 100)

        saveDistrictState(districtState)
    end
end

local function updateDotDistrictStates()
    local dotState = Infrastructure.DepartmentState.dot
    if not dotState then
        return
    end

    local dotStage = mapDepartmentStage(dotState)

    for _, districtState in pairs(Infrastructure.DistrictState) do
        districtState.dot_stage = dotStage

        if dotStage >= 4 then
            districtState.lighting_enabled = false
            districtState.traffic_enabled = false
        elseif dotStage >= 3 then
            districtState.lighting_enabled = true
            districtState.traffic_enabled = false
        else
            districtState.lighting_enabled = true
            districtState.traffic_enabled = true
        end

        if dotStage >= 3 then
            districtState.road_condition = clamp(districtState.road_condition - (dotStage - 2), 0, 100)
        else
            districtState.road_condition = clamp(districtState.road_condition + 0.5, 0, 100)
        end

        saveDistrictState(districtState)
    end
end

local function buildInfrastructureAlerts()
    local alerts = {}

    local power = Infrastructure.DepartmentState.power
    local water = Infrastructure.DepartmentState.water
    local dot = Infrastructure.DepartmentState.dot
    local police = Infrastructure.DepartmentState.police
    local ems = Infrastructure.DepartmentState.ems

    if power and power.reserve_max > 0 and (power.reserve_current / power.reserve_max) <= 0.20 then
        alerts[#alerts + 1] = { type = 'power_reserve_low', severity = 'high', message = 'Power reserve is below 20%.' }
    end

    local minPressure = 100
    for _, district in pairs(Infrastructure.DistrictState) do
        minPressure = math.min(minPressure, district.hydrant_pressure or 100)
    end

    if minPressure <= 35 then
        alerts[#alerts + 1] = { type = 'water_pressure_critical', severity = 'high', message = 'One or more districts have critical hydrant pressure.' }
    end

    local highHazardCount = 0
    for _, district in pairs(Infrastructure.DistrictState) do
        if asNumber(district.dot_stage, 1) >= 4 then
            highHazardCount = highHazardCount + 1
        end
    end

    if dot and highHazardCount > 0 then
        alerts[#alerts + 1] = { type = 'dot_hazard_high', severity = 'medium', message = ('%s district(s) at severe DOT stage.'):format(highHazardCount) }
    end

    if police and (police.risk_level == 'high' or police.risk_level == 'critical') then
        alerts[#alerts + 1] = { type = 'police_budget_risk', severity = police.risk_level, message = 'Police budget capacity is at risk.' }
    end

    if ems and (ems.risk_level == 'high' or ems.risk_level == 'critical') then
        alerts[#alerts + 1] = { type = 'ems_budget_risk', severity = ems.risk_level, message = 'EMS budget capacity is at risk.' }
    end

    local weekly = getWeeklyState()
    if weekly and asNumber(weekly.support_dependency_level, 0) >= 35 then
        alerts[#alerts + 1] = { type = 'support_dependency_rising', severity = 'medium', message = 'Support dependency is increasing this cycle.' }
    end

    local supportApplied = 0
    for _, departmentState in pairs(Infrastructure.DepartmentState) do
        supportApplied = supportApplied + asNumber(departmentState.support_received_this_cycle, 0)
    end
    if supportApplied > 0 then
        alerts[#alerts + 1] = {
            type = 'support_grant_applied_cycle',
            severity = 'medium',
            message = ('Support grant applied this cycle: $%.2f'):format(roundCurrency(supportApplied))
        }
    end

    return alerts
end

local function notifyOnAlertChanges(alerts)
    local serialized = json.encode(alerts)
    if serialized == Infrastructure.LastAlertHash then
        return
    end

    Infrastructure.LastAlertHash = serialized

    for _, alert in ipairs(alerts) do
        if alert.severity == 'high' or alert.severity == 'critical' then
            NotifyGovernment(('Infrastructure Alert: %s'):format(alert.message), 'error')
        end
    end
end

local function updateDistrictSimulation()
    updatePowerDistrictStates()
    updateWaterDistrictStates()
    updateDotDistrictStates()

    local alerts = buildInfrastructureAlerts()
    notifyOnAlertChanges(alerts)
end

local function recordTreasurySnapshot()
    local weekly = getWeeklyState()
    if not weekly then
        return
    end

    local currentPlayers = getOnlinePlayerCount()
    local treasuryBalance = roundCurrency(asNumber(GetTreasuryBalance(), 0))
    local taxRevenue = roundCurrency(asNumber(weekly.running_tax_revenue, 0))
    local otherRevenue = roundCurrency(asNumber(weekly.running_other_revenue, 0))

    MySQL.insert.await(
        'INSERT INTO pf_gov_treasury_snapshots (recorded_at, treasury_balance, online_players, weekly_tax_revenue, weekly_other_revenue) VALUES (?, ?, ?, ?, ?)',
        { utcDateTimeNow(), treasuryBalance, currentPlayers, taxRevenue, otherRevenue }
    )

    local oldAvg = asNumber(weekly.running_avg_population, 0)
    local oldCount = math.max(0, math.floor(asNumber(weekly.snapshot_count, 0)))
    local newAvg = ((oldAvg * oldCount) + currentPlayers) / (oldCount + 1)

    weekly.running_avg_population = newAvg
    weekly.snapshot_count = oldCount + 1

    saveWeeklyState(weekly)
end

local function applySupportGrantIfEligible(shortfall, totalRequired, totalUpgradeCosts)
    local supportAmount, reason = computeSupportGrant(shortfall, totalRequired, totalUpgradeCosts)
    if supportAmount <= 0 then
        return 0
    end

    local before = roundCurrency(asNumber(GetTreasuryBalance(), 0))
    local after = roundCurrency(before + supportAmount)

    UpdateTreasuryBalance(after, 'infrastructure_support')

    MySQL.insert.await(
        'INSERT INTO pf_gov_support_history (support_type, reason, amount, granted_at, cycle_id) VALUES (?, ?, ?, ?, NULL)',
        { 'population_support', reason, supportAmount, utcDateTimeNow() }
    )

    NotifyGovernment(('State support grant applied: $%.2f'):format(supportAmount), 'success')

    return supportAmount
end

local function processUpkeepCycle()
    local weekly = getWeeklyState()
    if not weekly then
        return false, 'missing_weekly_state'
    end

    local nowEpoch = os.time()
    local lastPaidEpoch = parseDateTime(weekly.last_upkeep_paid_at) or nowEpoch

    local requirements, totalRequired, totalUpgradeCosts = computeAllRequirements()
    local treasuryBefore = roundCurrency(asNumber(GetTreasuryBalance(), 0))
    local shortfall = roundCurrency(math.max(0, totalRequired - treasuryBefore))

    local supportReceived = 0
    if shortfall > 0 then
        supportReceived = applySupportGrantIfEligible(shortfall, totalRequired, totalUpgradeCosts)
    end

    local payable = roundCurrency(treasuryBefore + supportReceived)
    local funding, paidTotal, postFundingShortfall = applyDepartmentFundingResults(requirements, payable, totalRequired)

    local treasuryAfter = roundCurrency(math.max(0, payable - paidTotal))
    UpdateTreasuryBalance(treasuryAfter, 'infrastructure_upkeep')

    local cycleNow = utcDateTimeNow()

    for department, state in pairs(Infrastructure.DepartmentState) do
        local req = requirements[department] or {
            baseline = 0,
            dynamic = 0,
            required = 0
        }

        local funded = funding[department] and funding[department].funded or 0
        local deficit = funding[department] and funding[department].deficit or 0

        state.weekly_upkeep_base = roundCurrency(asNumber(req.baseline, state.weekly_upkeep_base))
        state.weekly_upkeep_dynamic = roundCurrency(asNumber(req.dynamic, state.weekly_upkeep_dynamic))
        state.budget_allocated = roundCurrency(funded)
        state.last_upkeep_paid_at = cycleNow

        if deficit > 0 then
            handleDepartmentDeficit(state, deficit, req.required)
        else
            handleDepartmentHealthyFunding(state)
        end

        if paidTotal > 0 then
            state.support_received_this_cycle = roundCurrency(supportReceived * (funded / paidTotal))
        else
            state.support_received_this_cycle = 0
        end

        state.risk_level = computeRiskLevel(state.condition_percent, state.reserve_current, state.reserve_max)
        saveDepartmentState(state)
    end

    local cycleId = MySQL.insert.await(
        'INSERT INTO pf_gov_upkeep_cycles (cycle_start, cycle_end, treasury_before, total_required, shortfall, support_received, treasury_after, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        {
            formatDateTime(lastPaidEpoch),
            cycleNow,
            treasuryBefore,
            totalRequired,
            postFundingShortfall,
            supportReceived,
            treasuryAfter,
            postFundingShortfall > 0 and 'partial' or 'completed'
        }
    )

    if supportReceived > 0 and cycleId then
        MySQL.update.await(
            'UPDATE pf_gov_support_history SET cycle_id = ? WHERE cycle_id IS NULL ORDER BY id DESC LIMIT 1',
            { cycleId }
        )
    end

    local interval = asNumber(getInfrastructureConfig().UpkeepIntervalSeconds, 604800)
    weekly.last_upkeep_paid_at = cycleNow
    weekly.next_upkeep_due_at = formatDateTime(nowEpoch + interval)
    weekly.running_tax_revenue = 0
    weekly.running_other_revenue = 0
    weekly.running_avg_population = 0
    weekly.snapshot_count = 0

    local previousDependency = asNumber(weekly.support_dependency_level, 0)
    local cycleDependency = totalRequired > 0 and ((supportReceived / totalRequired) * 100) or 0
    weekly.support_dependency_level = clamp(((previousDependency * 0.4) + (cycleDependency * 0.6)), 0, 100)

    saveWeeklyState(weekly)

    updateDistrictSimulation()

    return true, {
        cycleId = cycleId,
        totalRequired = totalRequired,
        supportReceived = supportReceived,
        shortfall = postFundingShortfall,
        treasuryBefore = treasuryBefore,
        treasuryAfter = treasuryAfter,
        dueAt = weekly.next_upkeep_due_at
    }
end

local function processOverdueUpkeepIfNeeded()
    local weekly = getWeeklyState()
    if not weekly then
        return
    end

    local dueEpoch = parseDateTime(weekly.next_upkeep_due_at)
    local nowEpoch = os.time()

    if not dueEpoch or dueEpoch <= nowEpoch then
        local ok, result = processUpkeepCycle()
        if ok then
            DebugPrint(('Infrastructure upkeep processed on startup. Next due: %s'):format(result.dueAt or 'unknown'))
        else
            print(('^1[PF-GOVERNMENT]^7 Failed to process startup upkeep: %s'):format(tostring(result)))
        end
    end
end

local function runSimulationIfDue(force)
    local intervalSeconds = asNumber(getInfrastructureConfig().SimulationIntervalMinutes, 5) * 60
    local now = os.time()

    if force or Infrastructure.LastSimulationRun == 0 or (now - Infrastructure.LastSimulationRun) >= intervalSeconds then
        Infrastructure.LastSimulationRun = now
        updateDistrictSimulation()
    end
end

local function runSnapshotIfDue(force)
    local intervalSeconds = asNumber(getInfrastructureConfig().SnapshotIntervalMinutes, 60) * 60
    local now = os.time()

    if Infrastructure.LastSnapshotRun == 0 then
        local latest = MySQL.single.await('SELECT recorded_at FROM pf_gov_treasury_snapshots ORDER BY id DESC LIMIT 1', {})
        local latestEpoch = latest and parseDateTime(latest.recorded_at) or nil
        Infrastructure.LastSnapshotRun = latestEpoch or now
    end

    if force or Infrastructure.LastSnapshotRun == 0 or (now - Infrastructure.LastSnapshotRun) >= intervalSeconds then
        Infrastructure.LastSnapshotRun = now
        recordTreasurySnapshot()
    end
end

local function runUpkeepIfDue(force)
    local weekly = getWeeklyState()
    if not weekly then
        return
    end

    local dueEpoch = parseDateTime(weekly.next_upkeep_due_at)
    local nowEpoch = os.time()

    if force or not dueEpoch or nowEpoch >= dueEpoch then
        processUpkeepCycle()
    end
end

function TrackWeeklyRevenue(revenueType, amount)
    local weekly = getWeeklyState()
    if not weekly then
        return
    end

    amount = roundCurrency(asNumber(amount, 0))
    if amount <= 0 then
        return
    end

    if tostring(revenueType or '') == 'tax' then
        weekly.running_tax_revenue = roundCurrency(asNumber(weekly.running_tax_revenue, 0) + amount)
    else
        weekly.running_other_revenue = roundCurrency(asNumber(weekly.running_other_revenue, 0) + amount)
    end

    saveWeeklyState(weekly)
end

function GetDepartmentState(department)
    if not department or department == '' then
        return nil
    end
    if next(Infrastructure.DepartmentState) == nil then
        loadDepartmentState()
    end
    return Infrastructure.DepartmentState[department]
end

local function getDistrictState(district)
    if not district or district == '' then
        return nil
    end
    if next(Infrastructure.DistrictState) == nil then
        loadDistrictState()
    end
    return Infrastructure.DistrictState[district]
end

function HasDistrictPower(district)
    local state = getDistrictState(district)
    if not state then
        return true
    end
    return asNumber(state.power_stage, 1) < 5
end

function HasDistrictWater(district)
    local state = getDistrictState(district)
    if not state then
        return true
    end
    return asNumber(state.water_stage, 1) < 4
end

function GetDistrictWaterPressure(district)
    local state = getDistrictState(district)
    if not state then
        return 100
    end
    return clamp(asNumber(state.hydrant_pressure, 100), 0, 100)
end

function GetRoadHazardLevel(district)
    local state = getDistrictState(district)
    local dotCfg = getInfrastructureConfig().DOT or {}

    if not state then
        return {
            stage = 1,
            roadCondition = 100,
            slipMultiplier = 1.0,
            tirePopChance = 0,
            potholeChance = 0
        }
    end

    local stage = asNumber(state.dot_stage, 1)
    local potholeChance = 0
    local tirePopChance = 0
    local slipMultiplier = 1.0

    if stage >= 4 then
        potholeChance = asNumber(dotCfg.PotholeChanceStage4, 25)
        tirePopChance = asNumber(dotCfg.TirePopChanceStage4, 8)
        slipMultiplier = asNumber(dotCfg.SlipMultiplierStage4, 1.25)
    elseif stage >= 3 then
        potholeChance = asNumber(dotCfg.PotholeChanceStage3, 10)
    end

    return {
        stage = stage,
        roadCondition = clamp(asNumber(state.road_condition, 100), 0, 100),
        slipMultiplier = slipMultiplier,
        tirePopChance = tirePopChance,
        potholeChance = potholeChance
    }
end

function GetWeeklyUpkeepSummary()
    local weekly = getWeeklyState()
    local cycle = MySQL.single.await('SELECT * FROM pf_gov_upkeep_cycles ORDER BY id DESC LIMIT 1', {})

    return {
        weeklyState = weekly,
        latestCycle = cycle,
        alerts = buildInfrastructureAlerts(),
        departments = Infrastructure.DepartmentState,
        districts = Infrastructure.DistrictState
    }
end

function SetDepartmentPaycheckMultiplier(source, department, multiplier)
    if not department or department == '' then
        return false, 'invalid_department'
    end

    local jobName = getDepartmentJobName(department)
    if not jobName then
        return false, 'department_not_payroll_managed'
    end

    local minMultiplier, maxMultiplier = getPayrollBounds()
    multiplier = clamp(asNumber(multiplier, 1.0), minMultiplier, maxMultiplier)

    local current = getPayrollMultiplier(department)
    local actorId = GetPlayerIdentifier(source)
    local actorName = GetPlayerName(source)

    MySQL.update.await(
        'UPDATE pf_gov_payroll_overrides SET paycheck_multiplier = ?, updated_by = ? WHERE department = ?',
        { multiplier, actorId or 'system', department }
    )

    LogAudit('payroll_multiplier_update', actorId or 'system', actorName or 'System', 'infrastructure_payroll', department, {
        department = department,
        old_multiplier = current,
        new_multiplier = multiplier
    })

    return true, { department = department, old = current, new = multiplier }
end

local function getDepartmentUpgradeCost(department, currentTier)
    local cfg = getDepartmentConfig(department) or {}
    local baseline = asNumber(cfg.baseline_upkeep, 0)
    local baseCost = math.max(1000, baseline * 0.50)
    local tier = math.max(0, math.floor(asNumber(currentTier, 0)))
    return roundCurrency(baseCost * (tier + 1))
end

function PurchaseDepartmentUpgrade(department, actorId, actorName)
    local state = Infrastructure.DepartmentState[department]
    if not state then
        return false, 'invalid_department'
    end

    local cost = getDepartmentUpgradeCost(department, state.upgrade_tier)
    local treasury = roundCurrency(asNumber(GetTreasuryBalance(), 0))
    if treasury < cost then
        return false, 'insufficient_treasury'
    end

    local newTier = math.max(0, math.floor(asNumber(state.upgrade_tier, 0))) + 1
    state.upgrade_tier = newTier
    saveDepartmentState(state)

    UpdateTreasuryBalance(roundCurrency(treasury - cost), actorId or 'infrastructure_upgrade')

    LogAudit('infrastructure_upgrade_purchase', actorId or 'system', actorName or 'System', 'infrastructure_department', department, {
        department = department,
        tier = newTier,
        cost = cost
    })

    return true, {
        department = department,
        upgrade_tier = newTier,
        cost = cost
    }
end

function UninstallDepartmentUpgrade(department, actorId, actorName)
    local state = Infrastructure.DepartmentState[department]
    if not state then
        return false, 'invalid_department'
    end

    local currentTier = math.max(0, math.floor(asNumber(state.upgrade_tier, 0)))
    if currentTier <= 0 then
        return false, 'no_upgrade_installed'
    end

    state.upgrade_tier = currentTier - 1
    saveDepartmentState(state)

    LogAudit('infrastructure_upgrade_uninstall', actorId or 'system', actorName or 'System', 'infrastructure_department', department, {
        department = department,
        old_tier = currentTier,
        new_tier = state.upgrade_tier,
        refund = 0
    })

    return true, {
        department = department,
        upgrade_tier = state.upgrade_tier,
        refund = 0
    }
end

function GetPayrollOverrides()
    local rows = MySQL.query.await('SELECT * FROM pf_gov_payroll_overrides ORDER BY department ASC', {}) or {}
    return rows
end

function InitializeInfrastructure()
    ensureInfrastructureTables()
    seedDepartmentState()
    seedDistrictState()
    seedWeeklyState()
    seedPayrollOverrides()

    loadDepartmentState()
    loadDistrictState()
    loadWeeklyState()

    processOverdueUpkeepIfNeeded()
    runSimulationIfDue(true)
    runSnapshotIfDue(false)

    print('^2[PF-GOVERNMENT]^7 Infrastructure system initialized')
end

function StartInfrastructureTasks()
    CreateThread(function()
        while true do
            Wait(60000)
            runSnapshotIfDue(false)
            runSimulationIfDue(false)
            runUpkeepIfDue(false)
        end
    end)
end

-- =====================================================
-- NUI CALLBACKS
-- =====================================================

RegisterNUICallback('infra:getOverview', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    cb({
        ok = true,
        summary = GetWeeklyUpkeepSummary(),
        payrollOverrides = GetPayrollOverrides()
    })
end)

RegisterNUICallback('infra:getDepartmentState', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    cb({ ok = true, state = GetDepartmentState(data.department) })
end)

RegisterNUICallback('infra:getDistrictState', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local district = getDistrictState(data.district)
    cb({ ok = true, state = district })
end)

RegisterNUICallback('infra:getPayrollOverrides', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    cb({ ok = true, overrides = GetPayrollOverrides() })
end)

RegisterNUICallback('infra:setPayrollMultiplier', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local ok, result = SetDepartmentPaycheckMultiplier(src, data.department, data.multiplier)
    if not ok then
        cb({ ok = false, error = result })
        return
    end

    cb({ ok = true, result = result })
end)

RegisterNUICallback('infra:runUpkeepNow', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local ok, result = processUpkeepCycle()
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('infra:buyUpgrade', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, result = PurchaseDepartmentUpgrade(data.department, actorId, actorName)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('infra:uninstallUpgrade', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, result = UninstallDepartmentUpgrade(data.department, actorId, actorName)
    cb({ ok = ok, result = result })
end)

-- =====================================================
-- EXPORTS
-- =====================================================

exports('HasDistrictPower', function(district)
    return HasDistrictPower(district)
end)

exports('HasDistrictWater', function(district)
    return HasDistrictWater(district)
end)

exports('GetDistrictWaterPressure', function(district)
    return GetDistrictWaterPressure(district)
end)

exports('GetRoadHazardLevel', function(district)
    return GetRoadHazardLevel(district)
end)

exports('GetDepartmentState', function(department)
    return GetDepartmentState(department)
end)

exports('GetWeeklyUpkeepSummary', function()
    return GetWeeklyUpkeepSummary()
end)

exports('PurchaseDepartmentUpgrade', function(department, actorId, actorName)
    return PurchaseDepartmentUpgrade(department, actorId, actorName)
end)

exports('UninstallDepartmentUpgrade', function(department, actorId, actorName)
    return UninstallDepartmentUpgrade(department, actorId, actorName)
end)

print('^2[PF-GOVERNMENT]^7 Infrastructure module loaded')
