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

-- Records the treasury's balance in the mirror table and checks the low-balance warning.
-- In society-account mode the balance is always re-read from pfm-banking, so the mirror
-- can never drift from the money that actually exists.
local function RecordTreasuryBalance(balance, updatedBy)
    TreasuryCache.balance = balance
    TreasuryCache.lastUpdate = os.time()
    MySQL.update('UPDATE pf_gov_treasury SET balance = ?, updated_by = ?, updated_at = NOW() WHERE id = (SELECT id FROM (SELECT id FROM pf_gov_treasury ORDER BY id DESC LIMIT 1) AS tmp)',
        {balance, updatedBy})
    if Config.Treasury.LowBalanceWarning > 0 and balance < Config.Treasury.LowBalanceWarning then
        NotifyGovernment('⚠️ Treasury balance is low: $' .. balance, 'warning')
    end
end

-- Moves money into (delta > 0) or out of (delta < 0) the treasury's society account.
-- Returns whether pfm-banking actually moved it, and whether this was a retry of a key that
-- already moved (the money moved once, earlier; callers must not log it again).
local function MoveTreasuryMoney(delta, reason, idempotencyKey)
    local ok, moved, res = pcall(function()
        if delta > 0 then
            return exports['pfm-banking']:AddMoney(Config.Treasury.SocietyAccount, delta, reason, idempotencyKey)
        end
        return exports['pfm-banking']:RemoveMoney(Config.Treasury.SocietyAccount, -delta, reason, idempotencyKey)
    end)
    local done = ok and moved == true
    return done, done and type(res) == 'table' and res.duplicate == true
end

--- Adds money to the treasury and updates the mirror; no transaction log entry (callers log their
--- own, e.g. tax collection). Returns ok, the treasury balance afterwards, and whether the call
--- was a retry of an idempotency key that was already credited (nothing new moved).
function CreditTreasury(amount, reason, performedBy, idempotencyKey)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount <= 0 then return false, GetTreasuryBalance() end
    if UseSocietyAccount() then
        local moved, duplicate = MoveTreasuryMoney(amount, reason or 'Government Treasury Deposit', idempotencyKey)
        if not moved then
            return false, GetTreasuryBalance()
        end
        local balance = GetTreasuryBalance()
        RecordTreasuryBalance(balance, performedBy)
        return true, balance, duplicate
    end
    local balance = TreasuryCache.balance + amount
    RecordTreasuryBalance(balance, performedBy)
    return true, balance
end

--- Sets the treasury to an exact balance (admin correction). Prefer DepositToTreasury /
--- WithdrawFromTreasury for normal money flow: they move a known amount instead of a computed difference.
function UpdateTreasuryBalance(newBalance, updatedBy)
    newBalance = tonumber(newBalance)
    if not newBalance or newBalance ~= newBalance then return false end

    if UseSocietyAccount() then
        local delta = newBalance - GetTreasuryBalance()
        if delta ~= 0 and not MoveTreasuryMoney(delta, 'Government Treasury Adjustment') then return false end
        RecordTreasuryBalance(GetTreasuryBalance(), updatedBy)
        return true
    end

    RecordTreasuryBalance(newBalance, updatedBy)
    return true
end

function DepositToTreasury(amount, source, description, performedBy, idempotencyKey)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount <= 0 then
        return false, 'Invalid amount'
    end

    local currentBalance = GetTreasuryBalance()
    local credited, newBalance, duplicate = CreditTreasury(amount, 'Government Treasury Deposit', performedBy, idempotencyKey)
    if not credited then
        return false, 'Deposit failed'
    end
    if duplicate then
        return true, 'Deposit already applied', newBalance
    end

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

function WithdrawFromTreasury(amount, reason, performedBy, performedByName, idempotencyKey)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount <= 0 then
        return false, 'Invalid amount'
    end

    local currentBalance = GetTreasuryBalance()

    -- Check if withdrawal would make balance negative (the society account itself never overdraws)
    if not Config.Treasury.AllowNegative and (currentBalance - amount) < 0 then
        return false, 'Insufficient treasury funds'
    end

    local newBalance = currentBalance - amount

    if UseSocietyAccount() then
        local moved, duplicate = MoveTreasuryMoney(-amount, reason or 'Government Treasury Withdrawal', idempotencyKey)
        if not moved then
            return false, 'Insufficient treasury funds'
        end
        newBalance = GetTreasuryBalance()
        RecordTreasuryBalance(newBalance, performedBy)
        if duplicate then
            return true, 'Withdrawal already applied', newBalance
        end
    else
        RecordTreasuryBalance(newBalance, performedBy)
    end
    
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

-- Treasury actions reach the server through the government callbacks (server/callbacks.lua).
-- NUI callbacks cannot be registered server-side (RegisterNUICallback is client-only and made this
-- file error on every start), and the removed handlers trusted a client-supplied `data.source` as
-- the acting player.

print('^2[PF-GOVERNMENT]^7 Treasury system loaded')
