-- =====================================================
-- BILLS AND FINES SYSTEM
-- =====================================================

function InitializeBills()
    print('^2[PF-GOVERNMENT]^7 Bills system initialized')
end

--- Creates a bill. `recurring` (optional) = { ref = 'house:<name>', period = '2026-11-02' } makes it
--- one bill per ref and period: the database refuses a second one (unique key, migration v2), so a
--- billing job that runs twice, after a restart or on two threads bills once. For a recurring bill
--- that already exists it returns false, 'duplicate', <id of the existing bill>.
function CreateBill(targetType, targetId, amount, billType, dueDate, description, issuedBy, issuedByName, recurring)
    amount = tonumber(amount)

    if not amount or amount <= 0 then
        return false, 'Invalid amount'
    end

    if not targetType or not targetId then
        return false, 'Missing target information'
    end

    local ref, period
    if recurring ~= nil then
        ref, period = type(recurring) == 'table' and recurring.ref, type(recurring) == 'table' and recurring.period
        if type(ref) ~= 'string' or ref == '' or #ref > 100 or type(period) ~= 'string' or period == '' or #period > 16 then
            return false, 'Invalid recurring bill'
        end
        if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then
            return false, 'Database error'   -- without the unique key the bill could be made twice
        end
    end

    -- Default due date if not provided (7 days)
    if not dueDate then
        dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + 604800)
    end

    local insertId
    if ref then
        -- IGNORE only skips the duplicate key: the row for this ref and period is already there
        insertId = MySQL.insert.await('INSERT IGNORE INTO pf_gov_bills (bill_type, target_type, target_id, amount, description, due_date, issued_by, issued_by_name, bill_ref, bill_period) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            {billType, targetType, targetId, amount, description, dueDate, issuedBy, issuedByName, ref, period})
        if (tonumber(insertId) or 0) < 1 then
            local existing = MySQL.scalar.await('SELECT id FROM pf_gov_bills WHERE bill_period = ? AND bill_ref = ? LIMIT 1', { period, ref })
            if existing then return false, 'duplicate', tonumber(existing) end
            return false, 'Database error'
        end
    else
        insertId = MySQL.insert.await('INSERT INTO pf_gov_bills (bill_type, target_type, target_id, amount, description, due_date, issued_by, issued_by_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            {billType, targetType, targetId, amount, description, dueDate, issuedBy, issuedByName})
    end

    if insertId then
        -- Log audit
        LogAudit('bill_create', issuedBy, issuedByName, 'bill', insertId, {
            bill_id = insertId,
            bill_type = billType,
            target_type = targetType,
            target_id = targetId,
            amount = amount
        })
        
        DebugPrint('Bill created: ' .. billType .. ' for ' .. targetType .. ' ' .. targetId .. ' - $' .. amount)
        -- the citizen Bills app (pf-citizen) shows new bills at once instead of on its next poll
        TriggerEvent('pf-government:server:billCreated', insertId, targetType, targetId)
        return true, 'Bill created successfully', insertId
    end
    
    return false, 'Database error'
end

-- the utility account a bill's delinquency cuts and its payment restores (server/utilities.lua)
local function accountOfBill(bill)
    if UtilityAccountOfBill then return UtilityAccountOfBill(bill) end
    return bill.target_type, bill.target_id
end

function PayBill(billId, amount, paidBy, paidByName)
    billId = tonumber(billId)
    amount = tonumber(amount)
    
    if not billId or not amount or amount <= 0 then
        return false, 'Invalid parameters'
    end
    
    -- Get bill info
    local bill = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE id = ?', {billId})
    
    if not bill or #bill == 0 then
        return false, 'Bill not found'
    end
    
    bill = bill[1]
    
    -- Check if bill is already paid
    if bill.status == 'paid' then
        return false, 'Bill already paid'
    end
    
    local remaining = tonumber(bill.amount) - tonumber(bill.amount_paid)
    
    if amount > remaining then
        amount = remaining
    end
    
    local newAmountPaid = tonumber(bill.amount_paid) + amount
    local newStatus = 'partial'
    
    if newAmountPaid >= tonumber(bill.amount) then
        newStatus = 'paid'
    end
    
    -- Update bill
    MySQL.update.await('UPDATE pf_gov_bills SET amount_paid = ?, status = ?, paid_at = NOW() WHERE id = ?',
        {newAmountPaid, newStatus, billId})
    
    -- Deposit to treasury
    DepositToTreasury(amount, bill.bill_type, 'Bill payment #' .. billId, paidBy)
    
    -- Log audit
    LogAudit('bill_payment', paidBy, paidByName, 'bill', billId, {
        bill_id = billId,
        amount_paid = amount,
        total_paid = newAmountPaid,
        status = newStatus
    })
    
    -- the last delinquent bill paid: power the system cut off for it comes back (a cut-off made by
    -- staff for another reason stays until staff restore it). A house utility bill is billed to the
    -- owner and restores that house once the owner's delinquent bills for it are paid.
    if newStatus == 'paid' then pcall(function()   -- a side effect: it must never fail the payment
        local accountType, accountId = accountOfBill(bill)
        if not accountType then return end
        local open
        if accountType == 'property' then
            open = MySQL.scalar.await("SELECT COUNT(*) FROM pf_gov_bills WHERE bill_ref = ? AND target_type = 'citizen' AND target_id = ? AND status = 'delinquent'",
                { bill.bill_ref, bill.target_id })
        else
            open = MySQL.scalar.await("SELECT COUNT(*) FROM pf_gov_bills WHERE target_type = ? AND target_id = ? AND status = 'delinquent'",
                { bill.target_type, bill.target_id })
        end
        if (tonumber(open) or 0) == 0 then
            local cut = MySQL.scalar.await("SELECT COUNT(*) FROM pf_gov_utilities WHERE property_type = ? AND property_id = ? AND disconnected_by = 'system'",
                { accountType, accountId })
            if (tonumber(cut) or 0) > 0 then
                RestoreService(accountType, accountId, 'both', 'system', 'System')
            end
        end
    end) end

    DebugPrint('Bill payment: #' .. billId .. ' - $' .. amount)
    return true, 'Payment successful', newStatus
end

function WaiveBill(billId, waivedBy, waivedByName, reason)
    billId = tonumber(billId)
    if not billId then return false, 'Invalid bill' end
    if GovSchema and GovSchema.Ensure then GovSchema.Ensure() end   -- the notes column (migration v1)

    -- only an open bill can be waived; it used to report success for any id, paid or missing
    local changed = MySQL.update.await("UPDATE pf_gov_bills SET status = ?, notes = ? WHERE id = ? AND status IN ('unpaid', 'partial', 'delinquent')",
        {'waived', reason ~= nil and tostring(reason):sub(1, 500) or nil, billId})
    if type(changed) == 'number' and changed < 1 then
        return false, 'Bill not found or not open'
    end
    
    -- Log audit
    LogAudit('bill_waive', waivedBy, waivedByName, 'bill', billId, {
        bill_id = billId,
        reason = reason
    })
    
    DebugPrint('Bill waived: #' .. billId)
    return true, 'Bill waived'
end

function GetBillsByTarget(targetType, targetId)
    local result = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE target_type = ? AND target_id = ? ORDER BY issued_at DESC',
        {targetType, targetId})
    
    return result or {}
end

local function decodeMoney(payload)
    if type(payload) == 'table' then
        return payload
    end
    if type(payload) == 'string' and payload ~= '' then
        local ok, decoded = pcall(json.decode, payload)
        if ok and type(decoded) == 'table' then
            return decoded
        end
    end
    return { cash = 0, bank = 0 }
end

-- Takes up to `amount` from a citizen (bank first, then cash) through the pfm-banking ledger, keyed by
-- the bill, so a retried collection never takes the money twice. Works for offline citizens too (the
-- ledger updates players.money). It used to change balances directly, outside the ledger.
local function collectFineFromCitizen(citizenid, amount, billId)
    amount = tonumber(amount) or 0
    if amount <= 0 or not billId or GetResourceState('pfm-banking') ~= 'started' then
        return 0
    end

    local bank, cash = 0, 0
    local onlinePlayer = QBCore and QBCore.Functions and QBCore.Functions.GetPlayerByCitizenId
        and QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if onlinePlayer then
        bank = tonumber(onlinePlayer.PlayerData.money.bank or 0) or 0
        cash = tonumber(onlinePlayer.PlayerData.money.cash or 0) or 0
    else
        local row = MySQL.single.await('SELECT money FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
        if not row then return 0 end
        local money = decodeMoney(row.money)
        bank = tonumber(money.bank or 0) or 0
        cash = tonumber(money.cash or 0) or 0
    end

    local collected = 0
    local bankTake = math.min(math.max(bank, 0), amount)
    local cashTake = math.min(math.max(cash, 0), amount - bankTake)
    for _, part in ipairs({ { 'bank', bankTake }, { 'cash', cashTake } }) do
        local account, take = part[1], math.floor(part[2] * 100) / 100
        if take > 0 then
            local ok, res = pcall(function()
                return exports['pfm-banking']:Transfer({
                    from = ('player:%s:%s'):format(citizenid, account), to = 'system:pf-government-fines',
                    amount = take, key = ('pf-government:fine:%s:%s'):format(billId, account),
                    kind = 'fine', reason = 'government-fine-collection', actor = citizenid,
                })
            end)
            if ok and type(res) == 'table' and res.ok then collected = collected + take end
        end
    end
    return collected
end

function IssueFineImmediate(targetCitizenId, amount, description, issuedBy, issuedByName, dueDate)
    if not targetCitizenId or targetCitizenId == '' then
        return false, 'invalid_target'
    end
    -- fines are whole amounts within the configured limit
    amount = tonumber(amount)
    local maxFine = tonumber(Config.Bills and Config.Bills.MaxFine) or 50000
    if not amount or amount ~= amount or amount < 1 or amount > maxFine then
        return false, 'invalid_amount'
    end
    amount = math.floor(amount)

    local ok, msg, billId = CreateBill('citizen', targetCitizenId, amount, 'fine', dueDate, description or 'City fine', issuedBy, issuedByName)
    if not ok then
        return false, msg
    end

    local collected = collectFineFromCitizen(targetCitizenId, amount, billId)
    if collected > 0 then
        PayBill(billId, collected, issuedBy, issuedByName)
    end

    local remaining = math.max(0, (tonumber(amount) or 0) - collected)

    return true, {
        billId = billId,
        collected = collected,
        remaining = remaining,
        status = remaining <= 0 and 'paid' or (collected > 0 and 'partial' or 'unpaid')
    }
end

local OPEN_SQL = "('unpaid', 'partial', 'delinquent')"
local lateFeesRunning = false

local function cents(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end

local function applyLateFees(now, pct, interval, maxCount)
    local out = { applied = 0, amount = 0 }
    -- the bills whose next fee is due: open, and (fees so far + 1) intervals past the due date
    local rows = MySQL.query.await([[SELECT id, target_type, target_id, amount, late_fee_amount, late_fee_count, UNIX_TIMESTAMP(due_date) AS due
        FROM pf_gov_bills WHERE status IN ]] .. OPEN_SQL .. [[ AND due_date IS NOT NULL AND due_date <= ? AND late_fee_count < ?
        AND TIMESTAMPADD(SECOND, (late_fee_count + 1) * ?, due_date) <= ? ORDER BY id LIMIT 500]],
        { os.date('%Y-%m-%d %H:%M:%S', now - interval), maxCount, interval, os.date('%Y-%m-%d %H:%M:%S', now) }) or {}
    for _, bill in ipairs(rows) do
        local count, due = math.floor(tonumber(bill.late_fee_count) or 0), tonumber(bill.due)
        -- a share of the original amount (the amount without earlier fees): fees never compound
        local base = (tonumber(bill.amount) or 0) - (tonumber(bill.late_fee_amount) or 0)
        local fee = math.floor(base * pct + 0.5) / 100
        if due and now - due >= (count + 1) * interval and fee >= 0.01 then
            -- `late_fee_count = ?` makes the fee land once even if two runs read the same bill
            local n = MySQL.update.await([[UPDATE pf_gov_bills SET amount = amount + ?, late_fee_amount = late_fee_amount + ?,
                late_fee_count = late_fee_count + 1, last_late_fee_at = NOW() WHERE id = ? AND late_fee_count = ? AND status IN ]] .. OPEN_SQL,
                { fee, fee, bill.id, count })
            if (tonumber(n) or 0) > 0 then
                out.applied = out.applied + 1
                out.amount = cents(out.amount + fee)
                LogAudit('bill_late_fee', 'system', 'System', 'bill', bill.id, { bill_id = bill.id, fee = fee, late_fees = count + 1 })
                DebugPrint(('Late fee applied: Bill #%s +$%.2f'):format(tostring(bill.id), fee))
                if bill.target_type == 'citizen' then pcall(function()
                    local Player = QBCore.Functions.GetPlayerByCitizenId(bill.target_id)
                    if Player then NotifyPlayer(Player.PlayerData.source, ('A late fee of $%.2f was added to overdue bill #%s (Bills app)'):format(fee, tostring(bill.id)), 'error') end
                end) end
            end
        end
    end
    return out
end

--- Late fees (Config.Bills): a bill still open LateFeeInterval seconds after its due date gets
--- LateFeePercentage of its original amount added once; with LateFeeMaxCount above 1, once more after
--- each further interval, up to that many. The count is kept on the bill (schema v3), so the hourly
--- run, a restart or two runs at once never add a fee twice. Returns { applied, amount } or { off }.
function ProcessBillLateFees(now)
    local cfg = Config.Bills or {}
    if not cfg.LateFeeEnabled then return { off = 'disabled' } end
    local pct = tonumber(cfg.LateFeePercentage) or 0
    local interval = math.floor(tonumber(cfg.LateFeeInterval) or 86400)
    local maxCount = math.floor(tonumber(cfg.LateFeeMaxCount) or 1)
    if pct <= 0 or pct ~= pct or interval < 60 or maxCount < 1 then return { off = 'disabled' } end
    if lateFeesRunning then return { off = 'running' } end
    lateFeesRunning = true
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then
        lateFeesRunning = false
        return { off = 'no_schema' }
    end
    local ok, res = pcall(applyLateFees, math.floor(tonumber(now) or os.time()), math.min(pct, 100), interval, maxCount)
    lateFeesRunning = false
    if not ok then
        print('^1[PF-GOVERNMENT]^7 late fees failed: ' .. tostring(res))
        return { off = 'error', error = tostring(res) }
    end
    if res.applied > 0 then DebugPrint(('Late fees applied to %d bills ($%.2f)'):format(res.applied, res.amount)) end
    return res
end

function ProcessBillEscalation()
    if not Config.Bills.EscalationEnabled then
        return
    end
    
    local escalationSeconds = Config.Bills.EscalationDays * 86400
    local escalationDate = os.date('%Y-%m-%d %H:%M:%S', os.time() - escalationSeconds)
    
    local result = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE status IN (?, ?) AND due_date < ?',
        {'unpaid', 'partial', escalationDate})
    for _, bill in ipairs(result or {}) do
        -- Update status to delinquent
        MySQL.update.await('UPDATE pf_gov_bills SET status = ? WHERE id = ?', {'delinquent', bill.id})

        -- Apply escalation actions
        if Config.Bills.EscalationActions.license_suspension then
            -- Suspend licenses for delinquent citizen/business
            MySQL.query('SELECT * FROM pf_gov_licenses WHERE owner_type = ? AND owner_id = ? AND status = ?',
                {bill.target_type, bill.target_id, 'active'}, function(licenses)
                    if licenses and #licenses > 0 then
                        for _, license in ipairs(licenses) do
                            SuspendLicense(license.id, 'system', 'System', 'Delinquent bill #' .. bill.id)
                        end
                    end
                end)
        end

        if Config.Bills.EscalationActions.utility_cutoff and Config.Utilities.EnablePower then
            -- the power of the account the bill is for: a business, or the house of a house utility
            -- bill while the billed citizen still owns it (citizens have no account of their own)
            local accountType, accountId = accountOfBill(bill)
            if accountType then
                DisconnectService(accountType, accountId, 'power', 'system', 'System', 'Delinquent bill #' .. bill.id)
            end
        end

        if Config.Bills.EscalationActions.business_flag and bill.target_type == 'business' then
            -- Flag business for non-compliance
            MySQL.update('UPDATE pf_gov_businesses SET compliance_status = ? WHERE business_id = ?',
                {'non_compliant', bill.target_id})
        end

        DebugPrint('Bill escalated: #' .. bill.id)
    end
end

-- =====================================================
-- NUI CALLBACKS - BILLS
-- =====================================================

RegisterNUICallback('bill:getAll', function(data, cb)
    local src = data.source or source
    local targetType = data.targetType
    local targetId = data.targetId
    local status = data.status
    -- everyone's bills are for government staff; anyone else sees only their own
    if not IsGovernmentEmployee(src) then
        local citizenid = GetPlayerIdentifier(src)
        if not citizenid then
            cb({ ok = false, error = 'no_player' })
            return
        end
        targetType, targetId = 'citizen', citizenid
    end
    
    local query = 'SELECT * FROM pf_gov_bills WHERE 1=1'
    local params = {}
    
    if targetType then
        query = query .. ' AND target_type = ?'
        table.insert(params, targetType)
    end
    
    if targetId then
        query = query .. ' AND target_id = ?'
        table.insert(params, targetId)
    end
    
    if status then
        query = query .. ' AND status = ?'
        table.insert(params, status)
    end
    
    query = query .. ' ORDER BY issued_at DESC'
    
    MySQL.query(query, params, function(result)
        cb({
            ok = true,
            bills = result or {}
        })
    end)
end)

RegisterNUICallback('bill:create', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'fines') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message, billId = CreateBill(
        data.targetType,
        data.targetId,
        data.amount,
        data.billType,
        data.dueDate,
        data.description,
        citizenid,
        name
    )
    
    if success then
        NotifyPlayer(src, 'Bill created', 'success')
    end
    
    cb({
        ok = success,
        message = message,
        billId = billId
    })
end)

-- The payer pays from their bank through the ledger, then the bill is marked. (It used to mark the
-- bill paid and credit the treasury without charging anyone, so any client could clear its fines
-- and put money into the treasury.) One payment per bill at a time.
local billPayLocks = {}
local PAYABLE = { unpaid = true, partial = true, delinquent = true }

local function payBillFromPlayer(src, billId, amount)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false, 'Player not found' end
    local bill = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE id = ?', { billId })
    bill = bill and bill[1]
    if not bill then return false, 'Bill not found' end
    if not PAYABLE[bill.status] then return false, 'This bill cannot be paid' end
    local remaining = (tonumber(bill.amount) or 0) - (tonumber(bill.amount_paid) or 0)
    local take = math.floor(math.min(amount, remaining) * 100) / 100
    if take <= 0 then return false, 'Nothing left to pay' end
    local cid = Player.PlayerData.citizenid
    local key = ('pf-government:billpay:%d:%s'):format(billId, PFPayout.NewId())
    local charged = PFPayout.Charge(Player, 'bank', take, {
        key = key, to = 'system:pf-government-fines', kind = 'fine', reason = 'Bill #' .. billId, quiet = true,
    })
    if not charged then return false, 'Not enough money in the bank', nil, 'insufficient_funds' end
    -- read again after the charge: the bill may have been paid, auto-paid or waived meanwhile by a
    -- path outside this lock; only what is still due is applied and the rest goes back to the player
    local fresh = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE id = ?', { billId })
    fresh = fresh and fresh[1]
    local stillDue = (fresh and PAYABLE[fresh.status]) and ((tonumber(fresh.amount) or 0) - (tonumber(fresh.amount_paid) or 0)) or 0
    local apply = math.floor(math.min(take, stillDue) * 100) / 100
    local ok, message, status = false, 'This bill cannot be paid', nil
    if apply > 0 then ok, message, status = PayBill(billId, apply, cid, GetPlayerName(src)) end
    local refund = (ok and math.floor((take - apply) * 100 + 0.5) / 100) or take
    if refund > 0 then
        local back = PFPayout.Transfer({ from = 'system:pf-government-fines', to = ('player:%s:bank'):format(cid), amount = refund,
            key = key .. ':refund', kind = 'refund', reason = 'Bill #' .. billId .. ' refund', actor = cid })
        if not back.ok then print(('^1[PF-GOVERNMENT]^7 bill %d: refund of %s to %s failed (%s), key %s:refund'):format(billId, refund, cid, tostring(back.error), key)) end
    end
    if not ok then return false, message, nil, 'not_open' end
    return ok, message, status
end

RegisterNUICallback('bill:pay', function(data, cb)
    local src = data.source or source
    local billId, amount = tonumber(data.billId), tonumber(data.amount)
    if not billId or not amount or amount ~= amount or amount <= 0 or amount == math.huge then
        cb({ ok = false, message = 'Invalid parameters' })
        return
    end
    if billPayLocks[billId] then
        cb({ ok = false, message = 'A payment for this bill is in progress' })
        return
    end
    billPayLocks[billId] = true
    local okCall, success, message, status = pcall(payBillFromPlayer, src, billId, amount)
    billPayLocks[billId] = nil
    if not okCall then success, message, status = false, 'Payment failed', nil end

    if success then
        NotifyPlayer(src, 'Payment successful', 'success')
    end
    
    cb({
        ok = success,
        message = message,
        status = status
    })
end)

RegisterNUICallback('bill:waive', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'fines') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = WaiveBill(data.billId, citizenid, name, data.reason)
    
    if success then
        NotifyPlayer(src, 'Bill waived', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('fine:issueImmediate', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'fines') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)

    local success, result = IssueFineImmediate(
        data.targetCitizenId,
        data.amount,
        data.description,
        citizenid,
        name,
        data.dueDate
    )

    cb({ ok = success, result = result })
end)

print('^2[PF-GOVERNMENT]^7 Bills system loaded')

exports('IssueFineImmediate', function(targetCitizenId, amount, description, issuedBy, issuedByName, dueDate)
    return IssueFineImmediate(targetCitizenId, amount, description, issuedBy, issuedByName, dueDate)
end)

--- Pays (part of) a bill from the player's bank through the same locked path as the city hall
--- terminal, so the Bills app and a terminal can never pay the same bill twice at once.
--- Returns ok, message.
exports('PayBillFromPlayer', function(src, billId, amount)
    billId, amount = tonumber(billId), tonumber(amount)
    if not billId or not amount or amount ~= amount or amount <= 0 then return false, 'Invalid amount' end
    if billPayLocks[billId] then return false, 'This bill is already being paid' end
    billPayLocks[billId] = true
    local ok, a, b, c, d = pcall(payBillFromPlayer, src, billId, amount)
    billPayLocks[billId] = nil
    if not ok then return false, 'server_error', nil, 'server_error' end
    return a, b, c, d   -- ok, message, new status, error code ('insufficient_funds' | 'not_open')
end)
