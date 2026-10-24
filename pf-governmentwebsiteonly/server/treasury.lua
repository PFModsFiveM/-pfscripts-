-- =====================================================
-- TREASURY SYSTEM
-- =====================================================

local TreasuryCache = {
    balance = 0,
    lastUpdate = 0
}

local function UseSocietyAccount()
    return Config.Treasury.UseSocietyAccount
        and Config.Treasury.SocietyAccount
        and Config.Treasury.SocietyAccount ~= ''
        and GetResourceState('pfm-banking') == 'started'
end

local function EnsureSocietyAccount()
    if not UseSocietyAccount() then
        return
    end

    local accountName = Config.Treasury.SocietyAccount
    local ok, account = pcall(function()
        return exports['pfm-banking']:GetAccount(accountName)
    end)

    if ok and account then
        return
    end

    pcall(function()
        exports['pfm-banking']:CreateJobAccount(accountName, Config.Treasury.StartingBalance)
    end)
end

function InitializeTreasury()
    if UseSocietyAccount() then
        EnsureSocietyAccount()
        local balance = exports['pfm-banking']:GetAccountBalance(Config.Treasury.SocietyAccount) or 0
        TreasuryCache.balance = tonumber(balance) or 0
        TreasuryCache.lastUpdate = os.time()
        print('^2[PF-GOVERNMENT]^7 Treasury initialized from society account: $' .. TreasuryCache.balance)
        return
    end

    MySQL.query('SELECT balance FROM pf_gov_treasury ORDER BY id DESC LIMIT 1', {}, function(result)
        if result and #result > 0 then
            TreasuryCache.balance = tonumber(result[1].balance) or 0
            TreasuryCache.lastUpdate = os.time()
            print('^2[PF-GOVERNMENT]^7 Treasury initialized with balance: $' .. TreasuryCache.balance)
        else
            -- Create initial treasury record
            MySQL.insert('INSERT INTO pf_gov_treasury (balance) VALUES (?)', {Config.Treasury.StartingBalance}, function(insertId)
                TreasuryCache.balance = Config.Treasury.StartingBalance
                TreasuryCache.lastUpdate = os.time()
                print('^2[PF-GOVERNMENT]^7 Treasury created with starting balance: $' .. Config.Treasury.StartingBalance)
            end)
        end
    end)
end

function GetTreasuryBalance()
    if UseSocietyAccount() then
        local balance = exports['pfm-banking']:GetAccountBalance(Config.Treasury.SocietyAccount) or 0
        TreasuryCache.balance = tonumber(balance) or 0
        TreasuryCache.lastUpdate = os.time()
        return TreasuryCache.balance
    end
    return TreasuryCache.balance
end

function UpdateTreasuryBalance(newBalance, updatedBy)
    newBalance = tonumber(newBalance) or 0

    if UseSocietyAccount() then
        local currentBalance = GetTreasuryBalance()
        local delta = newBalance - currentBalance
        if delta > 0 then
            exports['pfm-banking']:AddMoney(Config.Treasury.SocietyAccount, delta, 'Government Treasury Deposit')
        elseif delta < 0 then
            exports['pfm-banking']:RemoveMoney(Config.Treasury.SocietyAccount, math.abs(delta), 'Government Treasury Withdrawal')
        end
    end

    TreasuryCache.balance = newBalance
    TreasuryCache.lastUpdate = os.time()
    
    MySQL.update('UPDATE pf_gov_treasury SET balance = ?, updated_by = ?, updated_at = NOW() WHERE id = (SELECT id FROM (SELECT id FROM pf_gov_treasury ORDER BY id DESC LIMIT 1) AS tmp)', 
        {newBalance, updatedBy})
    
    -- Check for low balance warning
    if Config.Treasury.LowBalanceWarning > 0 and newBalance < Config.Treasury.LowBalanceWarning then
        NotifyGovernment('⚠️ Treasury balance is low: $' .. newBalance, 'warning')
    end
    
    return true
end

function DepositToTreasury(amount, source, description, performedBy)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'Invalid amount'
    end
    
    local currentBalance = GetTreasuryBalance()
    local newBalance = currentBalance + amount
    
    -- Update treasury
    UpdateTreasuryBalance(newBalance, performedBy)
    
    -- Log transaction
    LogTransaction('deposit', amount, currentBalance, newBalance, source, nil, description, performedBy)

    if type(TrackWeeklyRevenue) == 'function' and tostring(source or '') ~= 'tax' and tostring(source or '') ~= 'tax_collection' then
        TrackWeeklyRevenue('other', amount)
    end
    
    -- Log audit
    LogAudit('treasury_deposit', performedBy, nil, nil, nil, nil, {
        amount = amount,
        source = source,
        description = description,
        balance_after = newBalance
    })
    
    DebugPrint('Treasury deposit: $' .. amount .. ' | New balance: $' .. newBalance)
    return true, 'Deposit successful', newBalance
end

function WithdrawFromTreasury(amount, reason, performedBy, performedByName)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'Invalid amount'
    end
    
    local currentBalance = GetTreasuryBalance()
    
    -- Check if withdrawal would make balance negative
    if not Config.Treasury.AllowNegative and (currentBalance - amount) < 0 then
        return false, 'Insufficient treasury funds'
    end
    
    local newBalance = currentBalance - amount
    
    -- Update treasury
    UpdateTreasuryBalance(newBalance, performedBy)
    
    -- Log transaction
    LogTransaction('withdrawal', amount, currentBalance, newBalance, nil, nil, reason, performedBy)
    
    -- Log audit
    LogAudit('treasury_withdrawal', performedBy, performedByName, nil, nil, nil, {
        amount = amount,
        reason = reason,
        balance_after = newBalance
    })
    
    DebugPrint('Treasury withdrawal: $' .. amount .. ' | New balance: $' .. newBalance)
    return true, 'Withdrawal successful', newBalance
end

function LogTransaction(transactionType, amount, balanceBefore, balanceAfter, sourceType, sourceId, description, performedBy)
    MySQL.insert('INSERT INTO pf_gov_transactions (transaction_type, amount, balance_before, balance_after, source_type, source_id, description, performed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        {transactionType, amount, balanceBefore, balanceAfter, sourceType, sourceId, description, performedBy})
end

-- =====================================================
-- NUI CALLBACKS - TREASURY
-- =====================================================

RegisterNUICallback('treasury:getBalance', function(data, cb)
    cb({
        ok = true,
        balance = GetTreasuryBalance()
    })
end)

RegisterNUICallback('treasury:getTransactions', function(data, cb)
    local limit = data.limit or 50
    
    MySQL.query('SELECT * FROM pf_gov_transactions ORDER BY created_at DESC LIMIT ?', {limit}, function(result)
        cb({
            ok = true,
            transactions = result or {}
        })
    end)
end)

RegisterNUICallback('treasury:deposit', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local amount = tonumber(data.amount)
    local description = data.description or 'Manual deposit'
    local citizenid = GetPlayerIdentifier(src)
    
    local success, message, newBalance = DepositToTreasury(amount, 'manual', description, citizenid)
    
    cb({
        ok = success,
        message = message,
        balance = newBalance
    })
end)

RegisterNUICallback('treasury:withdraw', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local amount = tonumber(data.amount)
    local reason = data.reason or 'Manual withdrawal'
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message, newBalance = WithdrawFromTreasury(amount, reason, citizenid, name)
    
    cb({
        ok = success,
        message = message,
        balance = newBalance
    })
end)

print('^2[PF-GOVERNMENT]^7 Treasury system loaded')
