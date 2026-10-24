-- =====================================================
-- BUDGET SYSTEM
-- =====================================================

local BudgetCache = {}

function InitializeBudgets()
    MySQL.query('SELECT * FROM pf_gov_budgets', {}, function(result)
        if result then
            for _, budget in ipairs(result) do
                BudgetCache[budget.department] = {
                    weekly_budget = tonumber(budget.weekly_budget),
                    spent_this_week = tonumber(budget.spent_this_week),
                    last_reset = budget.last_reset,
                    enabled = budget.enabled == 1,
                    description = budget.description
                }
            end
            print('^2[PF-GOVERNMENT]^7 Loaded ' .. #result .. ' department budgets')
        end
    end)
end

function GetBudget(department)
    return BudgetCache[department]
end

function GetAllBudgets()
    return BudgetCache
end

function GetAllBudgetDetails()
    local rows = MySQL.query.await('SELECT * FROM pf_gov_budgets ORDER BY department ASC', {}) or {}
    local details = {}
    for _, row in ipairs(rows) do
        local department = tostring(row.department or '')
        local label = (Config.Budgets.DepartmentNames and Config.Budgets.DepartmentNames[department]) or department
        details[#details + 1] = {
            department = department,
            label = label,
            weekly_budget = tonumber(row.weekly_budget) or 0,
            spent_this_week = tonumber(row.spent_this_week) or 0,
            remaining = math.max(0, (tonumber(row.weekly_budget) or 0) - (tonumber(row.spent_this_week) or 0)),
            enabled = tonumber(row.enabled or 1) == 1,
            description = row.description or (label .. ' operational budget and service delivery funding.')
        }
    end
    return details
end

function SetBudget(department, weeklyBudget, updatedBy, updatedByName)
    weeklyBudget = tonumber(weeklyBudget)
    
    if not weeklyBudget or weeklyBudget < 0 then
        return false, 'Invalid budget amount'
    end
    
    -- Update cache
    if not BudgetCache[department] then
        BudgetCache[department] = {
            weekly_budget = 0,
            spent_this_week = 0,
            enabled = true
        }
    end
    
    local oldBudget = BudgetCache[department].weekly_budget
    BudgetCache[department].weekly_budget = weeklyBudget
    
    -- Update database
    MySQL.update('UPDATE pf_gov_budgets SET weekly_budget = ?, updated_by = ?, updated_at = NOW() WHERE department = ?',
        {weeklyBudget, updatedBy, department}, function(affectedRows)
            if affectedRows == 0 then
                -- Insert new department
                MySQL.insert('INSERT INTO pf_gov_budgets (department, weekly_budget, updated_by) VALUES (?, ?, ?)',
                    {department, weeklyBudget, updatedBy})
            end
        end)
    
    -- Log audit
    LogAudit('budget_change', updatedBy, updatedByName, 'budget', department, {
        department = department,
        old_budget = oldBudget,
        new_budget = weeklyBudget
    })
    
    DebugPrint('Budget updated: ' .. department .. ' -> $' .. weeklyBudget)
    return true, 'Budget updated successfully'
end

function SpendFromBudget(department, amount, reason, spentBy)
    amount = tonumber(amount)
    
    if not amount or amount <= 0 then
        return false, 'Invalid amount'
    end
    
    local budget = GetBudget(department)
    if not budget then
        return false, 'Department budget not found'
    end
    
    -- Check if budget is enabled
    if not budget.enabled then
        return false, 'Department budget is disabled'
    end
    
    -- Check if there's enough budget remaining
    local remaining = budget.weekly_budget - budget.spent_this_week
    if amount > remaining then
        return false, 'Insufficient budget remaining ($' .. remaining .. ' available)'
    end
    
    -- Update spent amount
    budget.spent_this_week = budget.spent_this_week + amount
    BudgetCache[department] = budget
    
    MySQL.update('UPDATE pf_gov_budgets SET spent_this_week = ? WHERE department = ?',
        {budget.spent_this_week, department})
    
    -- Withdraw from treasury
    WithdrawFromTreasury(amount, 'Budget allocation: ' .. department .. ' - ' .. reason, spentBy)
    
    DebugPrint('Budget spent: ' .. department .. ' -> $' .. amount)
    return true, 'Budget allocation successful'
end

function CheckBudgetReset()
    local currentTime = os.time()
    
    MySQL.query('SELECT * FROM pf_gov_budgets WHERE enabled = 1', {}, function(result)
        if result then
            for _, budget in ipairs(result) do
                local lastReset = budget.last_reset
                
                if not lastReset then
                    -- No reset recorded, reset now
                    ResetBudget(budget.department)
                else
                    -- Check if reset interval has passed
                    local lastResetTime = tonumber(lastReset)
                    local timeSinceReset = currentTime - lastResetTime
                    
                    if timeSinceReset >= Config.Budgets.ResetInterval then
                        ResetBudget(budget.department)
                    end
                end
            end
        end
    end)
end

function ResetBudget(department)
    MySQL.update('UPDATE pf_gov_budgets SET spent_this_week = 0, last_reset = NOW() WHERE department = ?', 
        {department})
    
    if BudgetCache[department] then
        BudgetCache[department].spent_this_week = 0
    end
    
    DebugPrint('Budget reset: ' .. department)
    
    -- Notify government
    NotifyGovernment('Department budget reset: ' .. department, 'primary')
    
    -- Log audit
    LogAudit('budget_reset', 'system', 'System', 'budget', department, {
        department = department
    })
end

function ResetAllBudgets()
    MySQL.update('UPDATE pf_gov_budgets SET spent_this_week = 0, last_reset = NOW()', {})
    
    for department, _ in pairs(BudgetCache) do
        BudgetCache[department].spent_this_week = 0
    end
    
    NotifyGovernment('All department budgets have been reset', 'success')
    DebugPrint('All budgets reset')
end

-- =====================================================
-- NUI CALLBACKS - BUDGETS
-- =====================================================

RegisterNUICallback('budget:getAll', function(data, cb)
    MySQL.query('SELECT * FROM pf_gov_budgets ORDER BY department', {}, function(result)
        cb({
            ok = true,
            budgets = result or {}
        })
    end)
end)

RegisterNUICallback('budget:update', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local department = data.department
    local weeklyBudget = tonumber(data.weeklyBudget)
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    if not department or not weeklyBudget then
        cb({ ok = false, error = 'missing_data' })
        return
    end
    
    local success, message = SetBudget(department, weeklyBudget, citizenid, name)
    
    if success then
        NotifyPlayer(src, 'Budget updated: ' .. department, 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('budget:allocate', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local department = data.department
    local amount = tonumber(data.amount)
    local reason = data.reason or 'Budget allocation'
    local citizenid = GetPlayerIdentifier(src)
    
    local success, message = SpendFromBudget(department, amount, reason, citizenid)
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('budget:reset', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local department = data.department
    
    if department == 'all' then
        ResetAllBudgets()
        NotifyPlayer(src, 'All budgets reset', 'success')
    else
        ResetBudget(department)
        NotifyPlayer(src, 'Budget reset: ' .. department, 'success')
    end
    
    cb({ ok = true })
end)

print('^2[PF-GOVERNMENT]^7 Budget system loaded')

exports('GetAllBudgetDetails', function()
    return GetAllBudgetDetails()
end)

exports('SetDepartmentBudget', function(department, weeklyBudget, updatedBy, updatedByName)
    return SetBudget(department, weeklyBudget, updatedBy, updatedByName)
end)
