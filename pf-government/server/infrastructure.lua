-- =====================================================
-- CITY INFRASTRUCTURE (MONTHLY OPERATIONS MODEL)
-- =====================================================

local Infrastructure = {
    DepartmentState = {},
    DistrictState = {},
    LastTick = 0
}

local function asNumber(v, d)
    local n = tonumber(v)
    if n == nil then return d or 0 end
    return n
end

local function clamp(v, mn, mx)
    v = asNumber(v, mn)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function round2(v)
    return math.floor((asNumber(v, 0) * 100) + 0.5) / 100
end

local function nowEpoch()
    return os.time()
end

local function nowDateTime()
    return os.date('!%Y-%m-%d %H:%M:%S')
end

local function currentMonthKey()
    return os.date('%Y-%m')
end

local function infraCfg()
    return Config.Infrastructure or {}
end

local function districtCfg()
    return infraCfg().Districts or {}
end

local function departmentCfg()
    return infraCfg().Departments or {}
end

local function getUpgradesCatalog(department)
    local all = (infraCfg().Upgrades or {})
    return all[department] or {}
end

local function ensureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_infra_department_state` (
            `department` VARCHAR(50) PRIMARY KEY,
            `monthly_operating_budget` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `linked_society_name` VARCHAR(100) NOT NULL,
            `society_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `spent_this_month` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `monthly_maintenance_demand` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `monthly_backlog` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `condition_percent` DECIMAL(5,2) NOT NULL DEFAULT 100,
            `district_impact_stage` INT NOT NULL DEFAULT 1,
            `status` VARCHAR(24) NOT NULL DEFAULT 'Normal',
            `installed_upgrades` LONGTEXT NULL,
            `projected_month_end_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_infra_district_state` (
            `district_name` VARCHAR(60) PRIMARY KEY,
            `priority_order` INT NOT NULL DEFAULT 100,
            `power_stage` INT NOT NULL DEFAULT 1,
            `dot_stage` INT NOT NULL DEFAULT 1,
            `water_stage` INT NOT NULL DEFAULT 1,
            `road_condition` DECIMAL(5,2) NOT NULL DEFAULT 100,
            `pothole_density` DECIMAL(5,2) NOT NULL DEFAULT 0,
            `traffic_light_health` DECIMAL(5,2) NOT NULL DEFAULT 100,
            `street_light_health` DECIMAL(5,2) NOT NULL DEFAULT 100,
            `maintenance_backlog` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `hazard_stage` INT NOT NULL DEFAULT 1,
            `blackout_flicker` TINYINT(1) NOT NULL DEFAULT 0,
            `next_state_change_at` BIGINT NULL,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_infra_transactions` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `department` VARCHAR(50) NOT NULL,
            `month_key` VARCHAR(7) NOT NULL,
            `transaction_type` VARCHAR(50) NOT NULL,
            `category` VARCHAR(50) NOT NULL,
            `amount` DECIMAL(15,2) NOT NULL DEFAULT 0,
            `actor_id` VARCHAR(64) NULL,
            `actor_name` VARCHAR(255) NULL,
            `reason` VARCHAR(255) NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_department_month` (`department`, `month_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

local function decodeUpgrades(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then return decoded end
    return {}
end

local function encodeUpgrades(tbl)
    local ok, encoded = pcall(json.encode, tbl or {})
    if ok then return encoded end
    return '{}'
end

local function seedState()
    for department, cfg in pairs(departmentCfg()) do
        local society = (Config.Budgets and Config.Budgets.LinkedSocietyAccounts and Config.Budgets.LinkedSocietyAccounts[department]) or department
        local snapshot = type(GetDepartmentMonthlyBudgetSnapshot) == 'function' and GetDepartmentMonthlyBudgetSnapshot(department) or nil
        local opBudget = snapshot and asNumber(snapshot.approved_monthly_budget, 0) or asNumber(cfg.monthly_operating_budget, 0)
        local balance = snapshot and asNumber(snapshot.society_balance, 0) or 0
        local spent = snapshot and asNumber(snapshot.spent_this_month, 0) or 0

        MySQL.insert.await(
            'INSERT IGNORE INTO pf_gov_infra_department_state (department, monthly_operating_budget, linked_society_name, society_balance, spent_this_month, monthly_maintenance_demand, monthly_backlog, condition_percent, district_impact_stage, status, installed_upgrades, projected_month_end_balance) VALUES (?, ?, ?, ?, ?, ?, 0, 100, 1, ?, ?, ?)',
            { department, round2(opBudget), society, round2(balance), round2(spent), round2(asNumber(cfg.monthly_maintenance_demand, opBudget * 0.6)), 'Normal', '{}', round2(balance) }
        )
    end

    for district, cfg in pairs(districtCfg()) do
        MySQL.insert.await(
            'INSERT IGNORE INTO pf_gov_infra_district_state (district_name, priority_order, power_stage, dot_stage, water_stage, road_condition, pothole_density, traffic_light_health, street_light_health, maintenance_backlog, hazard_stage, blackout_flicker) VALUES (?, ?, 1, 1, 1, 100, 0, 100, 100, 0, 1, 0)',
            { district, asNumber(cfg.priority, 100) }
        )
    end
end

local function loadState()
    Infrastructure.DepartmentState = {}
    Infrastructure.DistrictState = {}

    local deps = MySQL.query.await('SELECT * FROM pf_gov_infra_department_state', {}) or {}
    for _, row in ipairs(deps) do
        Infrastructure.DepartmentState[row.department] = {
            department = row.department,
            monthly_operating_budget = round2(asNumber(row.monthly_operating_budget, 0)),
            linked_society_name = row.linked_society_name,
            society_balance = round2(asNumber(row.society_balance, 0)),
            spent_this_month = round2(asNumber(row.spent_this_month, 0)),
            monthly_maintenance_demand = round2(asNumber(row.monthly_maintenance_demand, 0)),
            monthly_backlog = round2(asNumber(row.monthly_backlog, 0)),
            condition_percent = clamp(asNumber(row.condition_percent, 100), 0, 100),
            district_impact_stage = math.max(1, math.floor(asNumber(row.district_impact_stage, 1))),
            status = tostring(row.status or 'Normal'),
            installed_upgrades = decodeUpgrades(row.installed_upgrades),
            projected_month_end_balance = round2(asNumber(row.projected_month_end_balance, 0))
        }
    end

    local dRows = MySQL.query.await('SELECT * FROM pf_gov_infra_district_state ORDER BY priority_order ASC, district_name ASC', {}) or {}
    for _, row in ipairs(dRows) do
        Infrastructure.DistrictState[row.district_name] = {
            district_name = row.district_name,
            priority_order = asNumber(row.priority_order, 100),
            power_stage = math.max(1, math.floor(asNumber(row.power_stage, 1))),
            dot_stage = math.max(1, math.floor(asNumber(row.dot_stage, 1))),
            water_stage = math.max(1, math.floor(asNumber(row.water_stage, 1))),
            road_condition = clamp(asNumber(row.road_condition, 100), 0, 100),
            pothole_density = clamp(asNumber(row.pothole_density, 0), 0, 100),
            traffic_light_health = clamp(asNumber(row.traffic_light_health, 100), 0, 100),
            street_light_health = clamp(asNumber(row.street_light_health, 100), 0, 100),
            maintenance_backlog = round2(asNumber(row.maintenance_backlog, 0)),
            hazard_stage = math.max(1, math.floor(asNumber(row.hazard_stage, 1))),
            blackout_flicker = asNumber(row.blackout_flicker, 0) == 1,
            next_state_change_at = asNumber(row.next_state_change_at, 0)
        }
    end
end

local function saveDepartment(state)
    MySQL.update.await(
        'UPDATE pf_gov_infra_department_state SET monthly_operating_budget = ?, linked_society_name = ?, society_balance = ?, spent_this_month = ?, monthly_maintenance_demand = ?, monthly_backlog = ?, condition_percent = ?, district_impact_stage = ?, status = ?, installed_upgrades = ?, projected_month_end_balance = ? WHERE department = ?',
        {
            round2(state.monthly_operating_budget),
            state.linked_society_name,
            round2(state.society_balance),
            round2(state.spent_this_month),
            round2(state.monthly_maintenance_demand),
            round2(state.monthly_backlog),
            clamp(state.condition_percent, 0, 100),
            math.max(1, math.floor(asNumber(state.district_impact_stage, 1))),
            tostring(state.status or 'Normal'),
            encodeUpgrades(state.installed_upgrades),
            round2(state.projected_month_end_balance),
            state.department
        }
    )
end

local function saveDistrict(state)
    MySQL.update.await(
        'UPDATE pf_gov_infra_district_state SET power_stage = ?, dot_stage = ?, water_stage = ?, road_condition = ?, pothole_density = ?, traffic_light_health = ?, street_light_health = ?, maintenance_backlog = ?, hazard_stage = ?, blackout_flicker = ?, next_state_change_at = ? WHERE district_name = ?',
        {
            state.power_stage,
            state.dot_stage,
            state.water_stage,
            state.road_condition,
            state.pothole_density,
            state.traffic_light_health,
            state.street_light_health,
            state.maintenance_backlog,
            state.hazard_stage,
            state.blackout_flicker and 1 or 0,
            state.next_state_change_at,
            state.district_name
        }
    )
end

local function getUpgradeModifier(state, key, default)
    local val = default
    local catalog = getUpgradesCatalog(state.department)
    for _, item in ipairs(catalog) do
        local installed = state.installed_upgrades[item.key]
        if installed and (installed == true or type(installed) == 'table') then
            local mod = item.modifiers and item.modifiers[key]
            if type(mod) == 'number' then
                val = val + mod
            end
        end
    end
    return val
end

local function computeDepartmentStage(state)
    local demand = math.max(1, asNumber(state.monthly_maintenance_demand, 1))
    local available = math.max(0, asNumber(state.society_balance, 0))
    local ratio = available / demand

    if ratio >= 1.25 and state.condition_percent >= 85 then return 1, 'Healthy' end
    if ratio >= 1.00 and state.condition_percent >= 70 then return 2, 'Stable' end
    if ratio >= 0.80 and state.condition_percent >= 50 then return 3, 'Tight' end
    if ratio >= 0.60 and state.condition_percent >= 35 then return 4, 'At Risk' end
    return 5, 'Underfunded'
end

local function recalcDepartmentFromBudget(state)
    local snap = type(GetDepartmentMonthlyBudgetSnapshot) == 'function' and GetDepartmentMonthlyBudgetSnapshot(state.department) or nil
    if snap then
        state.monthly_operating_budget = round2(asNumber(snap.approved_monthly_budget, state.monthly_operating_budget))
        state.society_balance = round2(asNumber(snap.society_balance, state.society_balance))
        state.spent_this_month = round2(asNumber(snap.spent_this_month, state.spent_this_month))
        state.projected_month_end_balance = round2(asNumber(snap.projected_month_end_balance, state.projected_month_end_balance))
    end

    local demandBase = asNumber((departmentCfg()[state.department] or {}).monthly_maintenance_demand, state.monthly_operating_budget * 0.60)
    local demandMod = getUpgradeModifier(state, 'maintenanceDemandDelta', 0)
    state.monthly_maintenance_demand = math.max(1000, round2(demandBase + demandMod))

    local gap = state.monthly_maintenance_demand - state.society_balance
    if gap > 0 then
        state.monthly_backlog = round2(state.monthly_backlog + (gap * 0.15))
        state.condition_percent = clamp(state.condition_percent - 1.25, 0, 100)
    else
        state.monthly_backlog = round2(math.max(0, state.monthly_backlog - (state.monthly_maintenance_demand * 0.08)))
        state.condition_percent = clamp(state.condition_percent + 0.55, 0, 100)
    end

    local stage, status = computeDepartmentStage(state)
    state.district_impact_stage = stage
    state.status = status
end

local function powerWindowForStage(stage)
    if stage <= 2 then
        return { cycle = 0, online = 1, flicker = 0 }
    end
    if stage == 3 then
        return { cycle = 120, online = 90, flicker = 1 }
    end
    if stage == 4 then
        return { cycle = 300, online = 120, flicker = 1 }
    end
    return { cycle = 300, online = 60, flicker = 1 }
end

local function computeDistrictPowerState(stage)
    local now = nowEpoch()
    local rule = powerWindowForStage(stage)
    if rule.cycle == 0 then
        return true, false, now + 60
    end

    local slot = now % rule.cycle
    local online = slot < rule.online
    local nextChange = online and (now + (rule.online - slot)) or (now + (rule.cycle - slot))
    return online, rule.flicker == 1 and stage >= 3, nextChange
end

local function updateDistrictSimulation()
    local dotState = Infrastructure.DepartmentState.dot
    local powerState = Infrastructure.DepartmentState.power
    local waterState = Infrastructure.DepartmentState.water or Infrastructure.DepartmentState.utilities

    for _, district in pairs(Infrastructure.DistrictState) do
        local dotStage = dotState and dotState.district_impact_stage or 1
        local powerStage = powerState and powerState.district_impact_stage or 1
        local waterStage = waterState and waterState.district_impact_stage or 1

        -- Priority keeps hospital/police districts online longer as degradation escalates.
        if powerStage >= 4 and district.priority_order >= 4 then
            powerStage = math.min(5, powerStage + 1)
        end

        district.dot_stage = dotStage
        district.power_stage = powerStage
        district.water_stage = waterStage

        district.hazard_stage = dotStage
        district.maintenance_backlog = round2(district.maintenance_backlog + math.max(0, dotStage - 2) * 120)

        local potholeGain = dotStage >= 4 and 3.0 or (dotStage == 3 and 1.2 or -0.8)
        district.pothole_density = clamp(district.pothole_density + potholeGain, 0, 100)

        local roadDelta = dotStage >= 4 and -2.0 or (dotStage == 3 and -1.0 or 0.75)
        district.road_condition = clamp(district.road_condition + roadDelta, 0, 100)

        local trafficDelta = dotStage >= 4 and -4.0 or (dotStage == 3 and -2.0 or 0.8)
        local streetDelta = dotStage >= 4 and -3.5 or (dotStage == 3 and -1.8 or 0.8)
        district.traffic_light_health = clamp(district.traffic_light_health + trafficDelta, 0, 100)
        district.street_light_health = clamp(district.street_light_health + streetDelta, 0, 100)

        local online, flicker, nextChange = computeDistrictPowerState(powerStage)
        district.blackout_flicker = flicker
        district.next_state_change_at = nextChange
        if not online then
            district.street_light_health = clamp(district.street_light_health - 1.5, 0, 100)
        end

        saveDistrict(district)
    end
end

local function tickSimulation()
    for _, state in pairs(Infrastructure.DepartmentState) do
        recalcDepartmentFromBudget(state)
        saveDepartment(state)
    end

    updateDistrictSimulation()
end

function RecalculateInfrastructureState()
    tickSimulation()
end

function RecalculateInfrastructureNow()
    RecalculateInfrastructureState()
    TriggerClientEvent('pf-government:client:refreshInfrastructureViews', -1)
end

function GetDistrictPowerState(districtName)
    local state = Infrastructure.DistrictState[districtName]
    if not state then
        return {
            online = true,
            flicker = false,
            stage = 1,
            nextStateChangeAt = nowEpoch() + 60
        }
    end

    local online, flicker, nextChange = computeDistrictPowerState(state.power_stage)
    return {
        online = online,
        flicker = flicker,
        stage = state.power_stage,
        nextStateChangeAt = nextChange
    }
end

function HasDistrictPower(district)
    return GetDistrictPowerState(district).online
end

function CanChargeElectricVehicle(district)
    local power = GetDistrictPowerState(district)
    -- EV charging requires stable power; flicker-only windows are treated as unavailable.
    return power.online and not power.flicker
end

function HasDistrictWater(district)
    local state = Infrastructure.DistrictState[district]
    if not state then return true end
    return asNumber(state.water_stage, 1) < 5
end

function GetDistrictWaterPressure(district)
    local state = Infrastructure.DistrictState[district]
    if not state then return 100 end
    local stage = asNumber(state.water_stage, 1)
    local pressure = 100 - ((math.max(0, stage - 1)) * 20)
    return clamp(pressure, 0, 100)
end

function HasDistrictTrafficSignals(district)
    local state = Infrastructure.DistrictState[district]
    if not state then return true end
    return state.traffic_light_health >= 35 and state.dot_stage < 5
end

function HasDistrictStreetLights(district)
    local state = Infrastructure.DistrictState[district]
    if not state then return true end
    local power = GetDistrictPowerState(district)
    return power.online and state.street_light_health >= 35 and state.dot_stage < 5
end

function GetRoadHazardLevel(district)
    local state = Infrastructure.DistrictState[district]
    if not state then
        return {
            stage = 1,
            roadCondition = 100,
            potholeDensity = 0,
            slipMultiplier = 1.0,
            tirePopChance = 0,
            potholeChance = 0
        }
    end

    local stage = state.dot_stage
    local slip = 1.0
    local tire = 0
    local pothole = state.pothole_density

    if stage >= 5 then
        slip = 1.40
        tire = 15
    elseif stage == 4 then
        slip = 1.25
        tire = 8
    elseif stage == 3 then
        slip = 1.12
        tire = 3
    end

    return {
        stage = stage,
        roadCondition = round2(state.road_condition),
        potholeDensity = round2(pothole),
        slipMultiplier = slip,
        tirePopChance = tire,
        potholeChance = round2(pothole)
    }
end

local function getDepartmentSummary()
    local out = {}
    for department, state in pairs(Infrastructure.DepartmentState) do
        out[department] = {
            department = department,
            monthly_operating_budget = round2(state.monthly_operating_budget),
            linked_society_name = state.linked_society_name,
            society_balance = round2(state.society_balance),
            spent_this_month = round2(state.spent_this_month),
            monthly_maintenance_demand = round2(state.monthly_maintenance_demand),
            monthly_backlog = round2(state.monthly_backlog),
            condition_percent = round2(state.condition_percent),
            district_impact_stage = state.district_impact_stage,
            status = state.status,
            installed_upgrades = state.installed_upgrades,
            projected_month_end_balance = round2(state.projected_month_end_balance)
        }
    end
    return out
end

local function getDistrictSummary()
    local out = {}
    for district, state in pairs(Infrastructure.DistrictState) do
        local power = GetDistrictPowerState(district)
        out[district] = {
            district = district,
            power_stage = state.power_stage,
            dot_stage = state.dot_stage,
            water_stage = state.water_stage,
            road_condition = round2(state.road_condition),
            pothole_density = round2(state.pothole_density),
            traffic_light_health = round2(state.traffic_light_health),
            street_light_health = round2(state.street_light_health),
            has_traffic_signals = HasDistrictTrafficSignals(district),
            has_street_lights = HasDistrictStreetLights(district),
            hazard_stage = state.hazard_stage,
            blackout = not power.online,
            flicker = power.flicker,
            next_state_change_at = power.nextStateChangeAt
        }
    end
    return out
end

function GetInfrastructureOverview()
    local treasuryBalance = asNumber(GetTreasuryBalance and GetTreasuryBalance() or 0, 0)
    local upgradeCatalog = {}

    for department, upgrades in pairs(infraCfg().Upgrades or {}) do
        local state = Infrastructure.DepartmentState[department] or {}
        local installedUpgrades = state.installed_upgrades or {}
        upgradeCatalog[department] = {}

        for _, item in ipairs(upgrades) do
            local installed = installedUpgrades[item.key]
            local effectParts = {}
            for modKey, modValue in pairs(item.modifiers or {}) do
                effectParts[#effectParts + 1] = ('%s %s%s'):format(modKey, modValue >= 0 and '+' or '', tostring(modValue))
            end

            upgradeCatalog[department][#upgradeCatalog[department] + 1] = {
                key = item.key,
                name = item.name,
                description = item.description,
                cost = asNumber(item.cost, 0),
                modifiers = item.modifiers or {},
                effectSummary = #effectParts > 0 and table.concat(effectParts, ', ') or 'Operational improvement',
                installed = installed and true or false,
                installed_at = type(installed) == 'table' and installed.installed_at or nil,
                installed_by = type(installed) == 'table' and installed.installed_by or nil
            }
        end
    end

    return {
        month_key = currentMonthKey(),
        departments = getDepartmentSummary(),
        districts = getDistrictSummary(),
        treasury_balance = treasuryBalance,
        upgradeCatalog = upgradeCatalog
    }
end

function GetWeeklyUpkeepSummary()
    -- Compatibility payload name retained; content is monthly infrastructure overview.
    return GetInfrastructureOverview()
end

function PurchaseDepartmentUpgrade(department, upgradeKey, actorId, actorName)
    local state = Infrastructure.DepartmentState[department]
    if not state then return false, 'invalid_department' end
    if not upgradeKey or tostring(upgradeKey) == '' then return false, 'invalid_upgrade' end

    local catalog = getUpgradesCatalog(department)
    local found = nil

    for _, item in ipairs(catalog) do
        if item.key == upgradeKey then
            found = item
            break
        end
    end

    if not found then return false, 'invalid_upgrade' end
    if state.installed_upgrades[upgradeKey] then return false, 'already_installed' end

    local cost = round2(asNumber(found.cost, 0))
    local ok, msg = WithdrawFromTreasury(cost, ('Infrastructure upgrade: %s (%s)'):format(department, found.name), actorId, actorName)
    if not ok then return false, msg or 'treasury_withdraw_failed' end

    state.installed_upgrades[upgradeKey] = {
        installed = true,
        installed_at = nowEpoch(),
        installed_by = actorName or 'System'
    }
    saveDepartment(state)

    MySQL.insert.await(
        'INSERT INTO pf_gov_infra_transactions (department, month_key, transaction_type, category, amount, actor_id, actor_name, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { department, currentMonthKey(), 'upgrade_purchase', 'upgrades', cost, actorId, actorName, found.name }
    )

    LogAudit('infrastructure_upgrade_purchase', actorId or 'system', actorName or 'System', 'infrastructure_department', department, {
        department = department,
        upgrade_key = upgradeKey,
        upgrade_name = found.name,
        cost = cost
    })

    RecalculateInfrastructureNow()
    return true, { department = department, upgrade = found, upgrade_key = upgradeKey, cost = cost }
end

function UninstallDepartmentUpgrade(department, upgradeKey, actorId, actorName)
    local state = Infrastructure.DepartmentState[department]
    if not state then return false, 'invalid_department' end
    if not upgradeKey or tostring(upgradeKey) == '' then return false, 'invalid_upgrade' end
    if not state.installed_upgrades[upgradeKey] then return false, 'not_installed' end

    state.installed_upgrades[upgradeKey] = nil
    saveDepartment(state)

    MySQL.insert.await(
        'INSERT INTO pf_gov_infra_transactions (department, month_key, transaction_type, category, amount, actor_id, actor_name, reason) VALUES (?, ?, ?, ?, 0, ?, ?, ?)',
        { department, currentMonthKey(), 'upgrade_uninstall', 'upgrades', actorId, actorName, upgradeKey }
    )

    LogAudit('infrastructure_upgrade_uninstall', actorId or 'system', actorName or 'System', 'infrastructure_department', department, {
        department = department,
        upgrade_key = upgradeKey
    })

    RecalculateInfrastructureNow()
    return true, { department = department, upgrade_key = upgradeKey }
end

function InitializeInfrastructure()
    ensureTables()
    seedState()
    loadState()
    tickSimulation()
    print('^2[PF-GOVERNMENT]^7 Infrastructure module initialized (monthly model)')
end

-- Publishes which districts have power right now, so clients can switch the lights.
-- Only writes GlobalState when something changed.
local lastPublishedPower = nil
function PublishDistrictPower()
    local world = Config.InfrastructureWorld
    local out = {}
    if world and world.Enabled ~= false then
        for name in pairs(Infrastructure.DistrictState) do
            local p = GetDistrictPowerState(name)
            out[name] = p.online and 1 or 0
        end
    end
    local key = json.encode(out)
    if key ~= lastPublishedPower then
        lastPublishedPower = key
        GlobalState.pfGovDistrictPower = out
    end
    return out
end

function StartInfrastructureTasks()
    CreateThread(function()
        while true do
            Wait(60000)
            tickSimulation()
        end
    end)
    CreateThread(function()
        while true do
            PublishDistrictPower()
            local world = Config.InfrastructureWorld
            Wait(math.max(5, tonumber(world and world.PublishSeconds) or 10) * 1000)
        end
    end)
end

function TrackMonthlyRevenue(_, _)
    -- Placeholder hook for future infra funding analytics.
end

-- Compatibility alias used by treasury.lua.
function TrackWeeklyRevenue(revenueType, amount)
    TrackMonthlyRevenue(revenueType, amount)
end

-- =====================================================
-- NUI CALLBACKS
-- =====================================================

RegisterNUICallback('infra:getOverview', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    cb({ ok = true, summary = GetInfrastructureOverview() })
end)

RegisterNUICallback('infra:getDepartmentState', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local department = data and data.department
    cb({ ok = true, state = department and Infrastructure.DepartmentState[department] or nil })
end)

RegisterNUICallback('infra:getDistrictState', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local district = data and data.district
    cb({ ok = true, state = district and Infrastructure.DistrictState[district] or nil, power = district and GetDistrictPowerState(district) or nil })
end)

RegisterNUICallback('infra:runUpkeepNow', function(data, cb)
    if not HasPermission(data.source or source, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    RecalculateInfrastructureNow()
    cb({ ok = true, summary = GetInfrastructureOverview() })
end)

RegisterNUICallback('infra:buyUpgrade', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, result = PurchaseDepartmentUpgrade(data.department, data.upgradeKey, actorId, actorName)
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
    local ok, result = UninstallDepartmentUpgrade(data.department, data.upgradeKey, actorId, actorName)
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

exports('GetDistrictPowerState', function(district)
    return GetDistrictPowerState(district)
end)

exports('CanChargeElectricVehicle', function(district)
    return CanChargeElectricVehicle(district)
end)

exports('HasDistrictTrafficSignals', function(district)
    return HasDistrictTrafficSignals(district)
end)

exports('HasDistrictStreetLights', function(district)
    return HasDistrictStreetLights(district)
end)

exports('GetRoadHazardLevel', function(district)
    return GetRoadHazardLevel(district)
end)

exports('GetDepartmentState', function(department)
    return Infrastructure.DepartmentState[department]
end)

exports('GetWeeklyUpkeepSummary', function()
    return GetWeeklyUpkeepSummary()
end)

exports('GetInfrastructureOverview', function()
    return GetInfrastructureOverview()
end)

exports('PurchaseDepartmentUpgrade', function(department, upgradeKey, actorId, actorName)
    return PurchaseDepartmentUpgrade(department, upgradeKey, actorId, actorName)
end)

exports('UninstallDepartmentUpgrade', function(department, upgradeKey, actorId, actorName)
    return UninstallDepartmentUpgrade(department, upgradeKey, actorId, actorName)
end)

exports('RecalculateInfrastructureNow', function()
    return RecalculateInfrastructureNow()
end)

print('^2[PF-GOVERNMENT]^7 Infrastructure module (monthly model) loaded')
