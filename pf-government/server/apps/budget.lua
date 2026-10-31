-- City Budget (tablet, read only): treasury, department budgets, district power / water / roads and
-- recent spending. Editing budgets stays on the government computer.

local A = GovApps

local handlers = {}

function handlers.overview(src)
    local budgets = GovSafe(GetAllBudgetDetails) or {}
    local infra = GovSafe(GetInfrastructureOverview) or {}
    local districtCfg = (Config.Infrastructure and Config.Infrastructure.Districts) or {}
    local departments = {}
    for _, b in ipairs(budgets) do
        local state = (infra.departments or {})[b.department] or {}
        departments[#departments + 1] = {
            id = b.department, label = (Config.Budgets.DepartmentNames or {})[b.department] or b.department,
            budget = b.approved_monthly_budget, balance = b.society_balance, spent = b.spent_this_month,
            recommended = b.recommended_monthly_budget, status = b.budget_status,
            condition = state.condition_percent, stage = state.district_impact_stage, infraStatus = state.status,
        }
    end
    local districts = {}
    for name, d in pairs(infra.districts or {}) do
        districts[#districts + 1] = {
            id = name, label = (districtCfg[name] or {}).label or name, priority = (districtCfg[name] or {}).priority or 100,
            powerStage = d.power_stage, waterStage = d.water_stage, roadStage = d.dot_stage, blackout = d.blackout == true,
            flicker = d.flicker == true, water = HasDistrictWater(name), waterPressure = GetDistrictWaterPressure(name),
            roadCondition = d.road_condition, trafficLights = d.has_traffic_signals, streetLights = d.has_street_lights,
        }
    end
    table.sort(districts, function(a, b) return a.priority < b.priority end)
    local spending = GovSafe(function()
        return MySQL.query.await([[SELECT department, transaction_type, category, amount, actor_name, reason, UNIX_TIMESTAMP(created_at) AS at
            FROM pf_gov_budget_transactions ORDER BY id DESC LIMIT 25]])
    end) or {}
    local upgrades = GovSafe(function()
        return MySQL.query.await([[SELECT department, transaction_type, category, amount, actor_name, reason, UNIX_TIMESTAMP(created_at) AS at
            FROM pf_gov_infra_transactions ORDER BY id DESC LIMIT 15]])
    end) or {}
    local recent = {}
    for _, list in ipairs({ spending, upgrades }) do
        for _, r in ipairs(list) do
            recent[#recent + 1] = { department = r.department, type = r.transaction_type, category = r.category,
                amount = tonumber(r.amount) or 0, by = r.actor_name, reason = r.reason, at = tonumber(r.at) }
        end
    end
    table.sort(recent, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return {
        ok = true, treasury = GovSafe(GetTreasuryBalance) or 0, month = infra.month_key,
        departments = departments, districts = districts, recent = recent,
    }
end

A.Define({
    id = 'govbudget', name = 'City Budget', icon = '💰',
    devices = { 'tablet' },
    entry = 'html/apps/budget.js', styles = { 'html/apps/gov.css' },
    category = 'government', order = 23,
    access = { gov = { 'budgets', 'audit' } },
    description = 'Treasury, department budgets and district power and water',
    window = { width = 980, height = 660 },
}, handlers)

GovApps.Budget = handlers
