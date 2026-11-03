-- =====================================================
-- BILLS AND FINES SYSTEM
-- =====================================================

function InitializeBills()
    print('^2[PF-GOVERNMENT]^7 Bills system initialized')
end

local function cents(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end

-- the bill states a payment, a collection or a waiver can still change
local PAYABLE = { unpaid = true, partial = true, delinquent = true }

-- One payment, collection or waiver per bill at a time (the terminal, the Bills app, the reconcile
-- loop and a waiver all take it).
local billPayLocks = {}

local function billCfg() return Config.Bills or {} end

--- Creates a bill. `recurring` (optional) = { ref = 'house:<name>', period = '2026-11-02' } makes it
--- one bill per ref and period: the database refuses a second one (unique key, migration v2), so a
--- billing job that runs twice, after a restart or on two threads bills once. For a recurring bill
--- that already exists it returns false, 'duplicate', <id of the existing bill>.
function CreateBill(targetType, targetId, amount, billType, dueDate, description, issuedBy, issuedByName, recurring)
    amount = tonumber(amount)

    -- NaN passed `<= 0`; an infinite amount would be a debt nobody can ever pay
    if not amount or amount ~= amount or amount <= 0 or amount == math.huge then
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

        DebugPrint(('Bill created: %s for %s %s - $%s'):format(tostring(billType), tostring(targetType), tostring(targetId), tostring(amount)))
        -- the citizen Bills app (pf-citizen) shows new bills at once instead of on its next poll
        TriggerEvent('pf-government:server:billCreated', insertId, targetType, targetId)
        return true, 'Bill created successfully', insertId
    end

    return false, 'Database error'
end

-- the utility account a bill's delinquency cuts and its payment restores (server/utilities.lua);
-- `owners`: who owns each house now, when the caller has read it from pfm-houses
local function accountOfBill(bill, owners)
    if UtilityAccountOfBill then return UtilityAccountOfBill(bill, owners) end
    return bill.target_type, bill.target_id
end

-- The system's power cut for `bill`'s account is lifted once that account has no delinquent bill
-- left (paid or waived). A cut made by staff for another reason stays until staff restore it. A
-- house utility bill is billed to the owner: the house comes back once the owner's delinquent bills
-- for it are settled. A side effect of a payment or a waive: it never fails them.
local function restoreIfSettled(bill)
    local ok, err = pcall(function()
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
    end)
    if not ok then print(('^1[PF-GOVERNMENT]^7 restoring the utilities of bill #%s failed: %s'):format(tostring(bill.id), tostring(err))) end
end

--- Applies a payment to a bill and deposits it in the treasury. `payKey` (optional) is the row in
--- pf_gov_bill_payments of the charge behind it: the bill and that row are written in one statement,
--- so a charge is credited once however often it is settled again, and the treasury deposit is keyed
--- by it. Returns ok, message, new status, the amount applied (less than asked when less was due).
function PayBill(billId, amount, paidBy, paidByName, payKey)
    billId = tonumber(billId)
    amount = tonumber(amount)

    if not billId or not amount or amount ~= amount or amount <= 0 or amount == math.huge then
        return false, 'Invalid parameters'
    end
    if payKey ~= nil and type(payKey) ~= 'string' then payKey = nil end

    -- The write lands only while the bill is as it was read (its amount and what was paid): a late
    -- fee or another payment landing in between makes it miss, and the bill is read again, so the
    -- fee is not marked paid without being paid and neither payment overwrites the other.
    local bill, newAmountPaid, newStatus
    local wanted = amount
    for _ = 1, 3 do
        local rows = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE id = ?', {billId})
        if not rows or #rows == 0 then
            return false, 'Bill not found'
        end
        local row = rows[1]
        if row.status == 'paid' then
            return false, 'Bill already paid'
        end
        -- a waived bill stays waived (a payment used to reopen it as partial or paid)
        if not PAYABLE[row.status] then
            return false, 'This bill cannot be paid'
        end
        local total, paid = tonumber(row.amount) or 0, tonumber(row.amount_paid) or 0
        amount = math.max(0, math.min(wanted, total - paid))
        newAmountPaid = paid + amount
        newStatus = newAmountPaid >= total and 'paid' or 'partial'
        local changed
        if payKey then
            -- refunded: 0 when the whole charge is applied, NULL while the rest is owed back
            changed = MySQL.update.await([[UPDATE pf_gov_bills b JOIN pf_gov_bill_payments p ON p.pay_key = ? AND p.state = 'pending'
                SET b.amount_paid = ?, b.status = ?, b.paid_at = NOW(), p.state = 'applied', p.applied = ?,
                    p.refunded = IF(p.amount - ? < 0.005, 0, NULL)
                WHERE b.id = ? AND ABS(b.amount - ?) < 0.005 AND ABS(b.amount_paid - ?) < 0.005
                    AND b.status IN ('unpaid', 'partial', 'delinquent')]],
                {payKey, newAmountPaid, newStatus, amount, amount, billId, total, paid})
        else
            changed = MySQL.update.await([[UPDATE pf_gov_bills SET amount_paid = ?, status = ?, paid_at = NOW()
                WHERE id = ? AND ABS(amount - ?) < 0.005 AND ABS(amount_paid - ?) < 0.005]],
                {newAmountPaid, newStatus, billId, total, paid})
        end
        if type(changed) ~= 'number' or changed > 0 then bill = row break end
    end
    if not bill then
        return false, 'The bill changed meanwhile, try again'
    end

    -- Deposit to treasury (keyed by the charge when there is one, so it is deposited once)
    if amount > 0 then
        DepositToTreasury(amount, bill.bill_type, 'Bill payment #' .. billId, paidBy, payKey and ('pf-government:treasury:' .. payKey) or nil)
    end

    -- Log audit
    LogAudit('bill_payment', paidBy, paidByName, 'bill', billId, {
        bill_id = billId,
        amount_paid = amount,
        total_paid = newAmountPaid,
        status = newStatus
    })

    -- the last delinquent bill paid: power the system cut off for it comes back
    if newStatus == 'paid' then restoreIfSettled(bill) end

    DebugPrint('Bill payment: #' .. billId .. ' - $' .. tostring(amount))
    -- the fourth value: what was applied (less than asked when less was still due)
    return true, 'Payment successful', newStatus, amount
end

-- ── the bank ledger ─────────────────────────────────────────────────────

--- A transfer in the ledger by key: the row, nil when there is none, false when the bank cannot be asked.
local function ledgerTx(key)
    if GetResourceState('pfm-banking') ~= 'started' then return false end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
    if not ok then return false end
    if type(tx) ~= 'table' then return nil end
    return tx
end

-- errors the ledger gives before it writes anything (nothing moved)
local REFUSED_BEFORE_WRITE = {
    insufficient_funds = true, invalid_request = true, invalid_account = true, same_account = true,
    invalid_amount = true, invalid_key = true, bank_unavailable = true, ledger_unavailable = true,
}

--- Whether a ledger answer (a Transfer result or a stored row) means nothing moved and nothing will:
--- a refusal before any write, a failed transfer (not one the recovery could not verify) or one that
--- was refunded. Anything else (pending, debited, in progress, interrupted_unverified, an internal
--- error) is not known yet and must not be tried again under a new key.
local function settledWithoutMoving(r)
    if type(r) ~= 'table' or r.ok then return false end
    if r.state == 'compensated' then return true end
    if r.state == 'failed' then return r.error ~= 'interrupted_unverified' end
    if r.state == nil and r.txId == nil and r.tx_id == nil then return REFUSED_BEFORE_WRITE[r.error] == true end
    return false
end

--- The ledger key for the next try of a money move that must happen once: base:1, base:2, ... A try
--- the ledger refused (nothing moved) is passed over, so the next try gets a fresh key. A try that
--- completed or whose outcome is not known yet is returned with 'completed' or 'unclear': the caller
--- must not move the money again. Returns false when the bank cannot be asked.
function GovAttemptKey(base)
    for n = 1, 100 do
        local key = base .. ':' .. n
        local tx = ledgerTx(key)
        if tx == false then return false end
        if tx == nil then return key, nil end
        if tx.state == 'completed' then return key, 'completed' end
        if not settledWithoutMoving(tx) then return key, 'unclear' end
    end
    return false
end

-- ── charges that pay bills (pf_gov_bill_payments, schema v4) ────────────

local function paymentRow(payKey)
    return MySQL.single.await('SELECT * FROM pf_gov_bill_payments WHERE pay_key = ? LIMIT 1', { payKey })
end

local function recordCharge(payKey, ledgerKey, billId, citizenid, amount)
    MySQL.insert.await('INSERT INTO pf_gov_bill_payments (pay_key, ledger_key, bill_id, citizenid, amount) VALUES (?, ?, ?, ?, ?)',
        { payKey, ledgerKey, billId, citizenid, amount })
end

local function markChargeFailed(payKey)
    MySQL.update.await("UPDATE pf_gov_bill_payments SET state = 'failed' WHERE pay_key = ? AND state = 'pending'", { payKey })
end

--- The ledger key for a charge's refund: <pay_key>:refund, then <pay_key>:refund:2, ... A refund the
--- ledger refused keeps its key failed, so the next try moves on; one that completed or is not known
--- yet is returned with 'completed' / 'unclear' (never refunded again under a new key). false when
--- the bank cannot be asked.
local function refundAttemptKey(payKey)
    for n = 1, 100 do
        local key = n == 1 and (payKey .. ':refund') or ('%s:refund:%d'):format(payKey, n)
        local tx = ledgerTx(key)
        if tx == false then return false end
        if tx == nil then return key, nil end
        if tx.state == 'completed' then return key, 'completed' end
        if not settledWithoutMoving(tx) then return key, 'unclear' end
    end
    return false
end

--- Gives back what a charge took beyond what the bill still owed (it was paid or waived meanwhile),
--- from the fines account it went to. Keyed per charge and try: retried by the reconcile loop until
--- done, under a new numbered key after a refusal, under the same key while the outcome is unclear.
local function refundChargeSurplus(row)
    if not row or row.state ~= 'applied' or row.refunded ~= nil then return true end
    local surplus = cents((tonumber(row.amount) or 0) - (tonumber(row.applied) or 0))
    if surplus >= 0.01 then
        local key, state = refundAttemptKey(row.pay_key)
        if not key or state == 'unclear' then return false end
        if state ~= 'completed' then
            local back = PFPayout.Transfer({ from = 'system:pf-government-fines', to = ('player:%s:bank'):format(row.citizenid), amount = surplus,
                key = key, kind = 'refund', reason = 'Bill #' .. tostring(row.bill_id) .. ' refund', actor = row.citizenid })
            if not back.ok then
                print(('^1[PF-GOVERNMENT]^7 bill %s: refund of %s to %s not done yet (%s), key %s'):format(tostring(row.bill_id), surplus, tostring(row.citizenid), tostring(back.error), key))
                return false
            end
        end
    end
    MySQL.update.await('UPDATE pf_gov_bill_payments SET refunded = ? WHERE pay_key = ? AND refunded IS NULL', { math.max(0, surplus), row.pay_key })
    return true
end

--- A charge the ledger completed, credited to its bill: what the bill still owes of it is applied
--- (bill and charge row in one write, PayBill), the rest goes back to the payer. Safe to run again
--- for the same charge. Returns ok, message, new status, applied.
local function applyCharge(row, payerName)
    local billId, take = tonumber(row.bill_id), cents(row.amount)
    local fresh = MySQL.single.await('SELECT amount, amount_paid, status FROM pf_gov_bills WHERE id = ? LIMIT 1', { billId })
    local stillDue = (fresh and PAYABLE[fresh.status]) and cents((tonumber(fresh.amount) or 0) - (tonumber(fresh.amount_paid) or 0)) or 0
    local apply = math.min(take, stillDue)
    local ok, message, status, applied = false, 'This bill cannot be paid', nil, nil
    if apply > 0 then ok, message, status, applied = PayBill(billId, apply, row.citizenid, payerName, row.pay_key) end
    local now = paymentRow(row.pay_key)
    if not ok then
        if now and now.state == 'applied' then
            -- settled before (another settle of the same charge got there first)
            ok, message, applied = (tonumber(now.applied) or 0) > 0, 'Payment successful', tonumber(now.applied)
        else
            -- nothing of it can be applied: the whole charge goes back
            MySQL.update.await("UPDATE pf_gov_bill_payments SET state = 'applied', applied = 0, refunded = NULL WHERE pay_key = ? AND state = 'pending'", { row.pay_key })
            now = paymentRow(row.pay_key)
        end
    end
    refundChargeSurplus(now)
    if not ok then return false, message, nil, 'not_open' end
    return true, message, status, applied
end

--- Settles the charges of a bill the bank had not finished: credited once the ledger completed
--- them, dropped once it refused them; refunds still owed are paid. Returns true when `citizenid`
--- (if given) still has a charge for this bill whose outcome is not known. The caller holds the
--- bill's lock, so none of these charges is running right now (a charge with no ledger row never
--- reached the bank).
local function settleBillCharges(billId, citizenid)
    local open = false
    local rows = MySQL.query.await("SELECT * FROM pf_gov_bill_payments WHERE bill_id = ? AND (state = 'pending' OR (state = 'applied' AND refunded IS NULL)) ORDER BY created_at",
        { billId }) or {}
    for _, row in ipairs(rows) do
        if row.state == 'applied' then
            refundChargeSurplus(row)
        else
            local tx = ledgerTx(row.ledger_key)
            if tx == false then
                if row.citizenid == citizenid then open = true end
            elseif tx == nil or settledWithoutMoving(tx) then
                markChargeFailed(row.pay_key)
            elseif tx.state == 'completed' then
                applyCharge(row, nil)
            else
                if row.state == 'pending' and tx.error == 'interrupted_unverified' then
                    print(('^3[PF-GOVERNMENT]^7 bill %s: the bank could not verify charge %s after a restart; check it with /ledgerreconcile'):format(tostring(billId), tostring(row.ledger_key)))
                end
                if row.citizenid == citizenid then open = true end
            end
        end
    end
    return open
end

local function hasUnsettledCharges(billId)
    local n = MySQL.scalar.await("SELECT COUNT(*) FROM pf_gov_bill_payments WHERE bill_id = ? AND state = 'pending'", { billId })
    return (tonumber(n) or 0) > 0
end

--- Settles every charge the bank finished late (every PaymentReconcileSeconds, main.lua). A bill
--- someone is paying right now is left for the next run. Returns how many bills it looked at.
function ReconcileBillPayments()
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then return 0 end
    local bills = MySQL.query.await([[SELECT DISTINCT bill_id FROM pf_gov_bill_payments
        WHERE (state = 'pending' AND created_at < (NOW() - INTERVAL 20 SECOND)) OR (state = 'applied' AND refunded IS NULL) LIMIT 200]]) or {}
    local n = 0
    for _, r in ipairs(bills) do
        local billId = tonumber(r.bill_id)
        if billId and not billPayLocks[billId] then
            billPayLocks[billId] = true
            local ok, err = pcall(settleBillCharges, billId, nil)
            billPayLocks[billId] = nil
            if not ok then print(('^1[PF-GOVERNMENT]^7 settling the payments of bill #%s failed: %s'):format(tostring(billId), tostring(err))) end
            n = n + 1
        end
    end
    return n
end

-- ── waivers ─────────────────────────────────────────────────────────────

-- where a waived fine's money goes back to: the citizen's bank, or the business's account
local function refundTargetOf(bill)
    if bill.target_type == 'citizen' then return ('player:%s:bank'):format(bill.target_id) end
    local ok, acct = pcall(MySQL.scalar.await, 'SELECT account_ref FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { bill.target_id })
    if ok and type(acct) == 'string' and acct ~= '' then return acct end
    return nil
end

-- payments are deposited in the treasury (PayBill), so a refund comes out of it
local function treasuryRef()
    local t = Config.Treasury or {}
    if t.UseSocietyAccount and type(t.SocietyAccount) == 'string' and t.SocietyAccount ~= '' then
        return 'society:' .. t.SocietyAccount, true
    end
    return 'system:pf-government-fines', false
end

--- The treasury's own record of a fine refund (the mirror balance outside society-account mode, the
--- transaction log, the bill_refund audit), written once per bill: also when the refund came back
--- unclear and a later waiver finds it completed. The transaction log row is the mark.
local function bookFineRefund(billId, refund, to, key, waivedBy, waivedByName, society)
    local okCount, n = pcall(MySQL.scalar.await, "SELECT COUNT(*) FROM pf_gov_transactions WHERE source_type = 'fine_refund' AND source_id = ?", { tostring(billId) })
    if okCount and (tonumber(n) or 0) > 0 then return end
    local before, after
    if society then
        -- the society account is the treasury: it is re-read, and the refund already left it
        after = GetTreasuryBalance()
        before = after + refund
    else
        before = GetTreasuryBalance()
        after = before - refund
        UpdateTreasuryBalance(after, waivedBy)
    end
    pcall(MySQL.insert.await, 'INSERT INTO pf_gov_transactions (transaction_type, amount, balance_before, balance_after, source_type, source_id, description, performed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { 'withdrawal', refund, before, after, 'fine_refund', tostring(billId), ('Fine #%d waived: refunded'):format(billId), waivedBy })
    LogAudit('bill_refund', waivedBy, waivedByName, 'bill', billId, { bill_id = billId, amount = refund, to = to, key = key })
end

local function waiveLocked(billId, waivedBy, waivedByName, reason)
    if GovSchema and GovSchema.Ensure then GovSchema.Ensure() end   -- the notes column (v1), the charges table (v4)
    local bill = MySQL.single.await('SELECT id, bill_type, target_type, target_id, bill_ref, status, amount, amount_paid FROM pf_gov_bills WHERE id = ?', { billId })
    if type(bill) ~= 'table' or not bill.id then return false, 'Bill not found or not open', 'not_open' end
    local paid = cents(bill.amount_paid)
    -- an open bill is waived as it stands. A fine is annulled, also once paid: what it took goes back
    -- (a fine collected by mistake used to keep the money after its waiver).
    local isFine = bill.bill_type == 'fine'
    if not (PAYABLE[bill.status] or (isFine and bill.status == 'paid' and paid > 0)) then
        return false, 'Bill not found or not open', 'not_open'
    end
    local refund = isFine and paid or 0
    if refund > 0 then
        -- a charge the bank has not settled may still add to what was paid
        if hasUnsettledCharges(billId) then return false, 'A payment for this bill is still being processed', 'payment_pending' end
        local to = refundTargetOf(bill)
        if not to then return false, 'This business has no account to refund the fine to', 'no_refund_account' end
        local from, society = treasuryRef()
        local key, state = GovAttemptKey(('pf-government:fine:%d:waive'):format(billId))
        if not key then return false, 'The bank is not responding', 'bank_unavailable' end
        if state == 'unclear' then return false, 'The refund is still being processed by the bank', 'refund_pending' end
        if state ~= 'completed' then
            local res = PFPayout.Transfer({ from = from, to = to, amount = refund, key = key, kind = 'refund',
                reason = ('Fine #%d waived'):format(billId), actor = waivedBy })
            if not res.ok then
                if not settledWithoutMoving(res) then return false, 'The refund is still being processed by the bank', 'refund_pending' end
                return false, res.error == 'insufficient_funds' and 'The treasury cannot cover the refund' or 'The refund did not go through', 'refund_failed'
            end
        else
            -- refunded by an earlier waiver whose answer was unclear: what the ledger moved is booked
            local tx = ledgerTx(key)
            if type(tx) == 'table' and tonumber(tx.amount) then refund = cents(tx.amount) end
        end
        bookFineRefund(billId, refund, to, key, waivedBy, waivedByName, society)
    end

    local note = reason ~= nil and tostring(reason):sub(1, 500) or nil
    if refund > 0 then note = ((note and note .. ' ') or '') .. ('(refunded $%.2f)'):format(refund) end
    -- only while the bill is as it was read
    local changed = MySQL.update.await("UPDATE pf_gov_bills SET status = 'waived', notes = ? WHERE id = ? AND status = ? AND ABS(amount_paid - ?) < 0.005",
        { note, billId, bill.status, paid })
    if type(changed) == 'number' and changed < 1 then
        return false, 'The bill changed meanwhile, try again', 'changed'
    end
    -- a waived debt is no debt: power the system cut for it comes back like after a payment
    if bill.status == 'delinquent' then restoreIfSettled(bill) end

    -- Log audit
    LogAudit('bill_waive', waivedBy, waivedByName, 'bill', billId, {
        bill_id = billId,
        reason = reason,
        refunded = refund > 0 and refund or nil,
    })

    DebugPrint('Bill waived: #' .. billId)
    return true, 'Bill waived', refund > 0 and refund or nil
end

--- Waives an open bill. A fine is annulled even once paid, and what it collected is refunded through
--- the ledger from the treasury (key pf-government:fine:<id>:waive:<try>). Returns ok, message,
--- refunded amount | error code.
function WaiveBill(billId, waivedBy, waivedByName, reason)
    billId = tonumber(billId)
    if not billId or billId ~= math.floor(billId) then return false, 'Invalid bill', 'bad_request' end
    if billPayLocks[billId] then return false, 'A payment for this bill is in progress', 'busy' end
    billPayLocks[billId] = true
    local ok, a, b, c = pcall(waiveLocked, billId, waivedBy, waivedByName, reason)
    billPayLocks[billId] = nil
    if not ok then
        print(('^1[PF-GOVERNMENT]^7 waiving bill #%s failed: %s'):format(tostring(billId), tostring(a)))
        return false, 'Server error', 'server_error'
    end
    return a, b, c
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
-- the bill, so a retried collection never takes the money twice, and credits the bill with it. Each
-- charge is recorded first (pf_gov_bill_payments): one the bank settles late is credited by the
-- reconcile loop instead of being lost. Works for offline citizens too (the ledger updates
-- players.money). Returns what was credited and what is still being settled by the bank.
local function collectFineFromCitizen(citizenid, amount, billId)
    amount = tonumber(amount) or 0
    if amount <= 0 or not billId or GetResourceState('pfm-banking') ~= 'started' then
        return 0, 0
    end
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then return 0, 0 end

    local bank, cash = 0, 0
    local onlinePlayer = QBCore and QBCore.Functions and QBCore.Functions.GetPlayerByCitizenId
        and QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if onlinePlayer then
        bank = tonumber(onlinePlayer.PlayerData.money.bank or 0) or 0
        cash = tonumber(onlinePlayer.PlayerData.money.cash or 0) or 0
    else
        local row = MySQL.single.await('SELECT money FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
        if not row then return 0, 0 end
        local money = decodeMoney(row.money)
        bank = tonumber(money.bank or 0) or 0
        cash = tonumber(money.cash or 0) or 0
    end

    local collected, unsettled = 0, 0
    local bankTake = math.min(math.max(bank, 0), amount)
    local cashTake = math.min(math.max(cash, 0), amount - bankTake)
    for _, part in ipairs({ { 'bank', bankTake }, { 'cash', cashTake } }) do
        local account, take = part[1], math.floor(part[2] * 100) / 100
        if take > 0 then
            local key = ('pf-government:fine:%s:%s'):format(billId, account)
            recordCharge(key, key, billId, citizenid, take)
            local res = PFPayout.Transfer({
                from = ('player:%s:%s'):format(citizenid, account), to = 'system:pf-government-fines',
                amount = take, key = key, kind = 'fine', reason = 'government-fine-collection', actor = citizenid,
            })
            if res.ok then
                local ok, _, _, applied = applyCharge({ pay_key = key, bill_id = billId, citizenid = citizenid, amount = take }, nil)
                if ok then collected = cents(collected + (tonumber(applied) or take)) end
            elseif settledWithoutMoving(res) then
                markChargeFailed(key)
            else
                unsettled = cents(unsettled + take)   -- the reconcile loop credits it once the bank settles
            end
        end
    end
    return collected, unsettled
end

local function dueFromNow()
    local days = math.floor(tonumber(billCfg().DueDays) or 7)
    days = math.max(1, math.min(60, days))
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + days * 86400)
end

--- Creates a fine bill and collects it at once from the citizen through the ledger (bank, then
--- cash; offline citizens too). For an official's fine use IssueOfficialFine, which collects only
--- in person. The due date of what is left is always the server's (Config.Bills.DueDays); the
--- sixth argument (a due date) is no longer used.
function IssueFineImmediate(targetCitizenId, amount, description, issuedBy, issuedByName)
    if type(targetCitizenId) ~= 'string' or targetCitizenId == '' or #targetCitizenId > 50 then
        return false, 'invalid_target'
    end
    -- fines are whole amounts within the configured limit
    amount = tonumber(amount)
    local maxFine = tonumber(billCfg().MaxFine) or 50000
    if not amount or amount ~= amount or amount < 1 or amount > maxFine then
        return false, 'invalid_amount'
    end
    amount = math.floor(amount)

    local ok, msg, billId = CreateBill('citizen', targetCitizenId, amount, 'fine', dueFromNow(), description or 'City fine', issuedBy, issuedByName)
    if not ok then
        return false, msg
    end

    -- the citizen sees the new bill in the Bills app at once: hold the bill while it is collected (if
    -- they are already paying it themselves, that payment stands and nothing is collected)
    local okC, collected, unsettled = true, 0, 0
    if not billPayLocks[billId] then
        billPayLocks[billId] = true
        okC, collected, unsettled = pcall(collectFineFromCitizen, targetCitizenId, amount, billId)
        billPayLocks[billId] = nil
    end
    if not okC then
        print(('^1[PF-GOVERNMENT]^7 collecting fine #%s failed: %s'):format(tostring(billId), tostring(collected)))
        collected, unsettled = 0, 0
    end

    local remaining = math.max(0, amount - collected)

    return true, {
        billId = billId,
        collected = collected,
        processing = unsettled > 0 and unsettled or nil,
        remaining = remaining,
        status = remaining <= 0 and 'paid' or (collected > 0 and 'partial' or 'unpaid')
    }
end

-- ── what officials issue: fines and manual bills ─────────────────────────

local issuing = {}   -- [official citizenid] = true while one of their fines or bills is being made

--- The configured limits on what officials issue, counted from the bills table (a restart does not
--- reset them). Returns an error code when one is reached.
local function issueLimitReached(officialCid, targetType, targetId)
    local cfg = billCfg()
    local perHour = math.floor(tonumber(cfg.FinesPerHour) or 10)
    local perTarget = math.floor(tonumber(cfg.FinesPerTargetPerDay) or 3)
    if perHour > 0 then
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM pf_gov_bills WHERE issued_by = ? AND issued_at > (NOW() - INTERVAL 1 HOUR)', { officialCid })
        if (tonumber(n) or 0) >= perHour then return 'rate_limited' end
    end
    if perTarget > 0 then
        local n = MySQL.scalar.await([[SELECT COUNT(*) FROM pf_gov_bills WHERE target_type = ? AND target_id = ? AND bill_type = 'fine'
            AND issued_by <> 'system' AND issued_at > (NOW() - INTERVAL 1 DAY)]], { targetType, targetId })
        if (tonumber(n) or 0) >= perTarget then return 'target_limit' end
    end
    return nil
end

--- Runs fn while the official holds their issuing lock (taken before any database wait, so two
--- requests cannot both pass the limits). Returns fn's results, or false, 'busy' / 'server_error'.
local function asOfficial(officialCid, fn)
    if issuing[officialCid] then return false, 'busy' end
    issuing[officialCid] = true
    local res = table.pack(pcall(fn))
    issuing[officialCid] = nil
    if not res[1] then
        print('^1[PF-GOVERNMENT]^7 issuing failed: ' .. tostring(res[2]))
        return false, 'server_error'
    end
    return table.unpack(res, 2, res.n)
end

local function wholeAmount(v, max)
    local n = tonumber(v)
    if not n or n ~= n or n < 1 or n > max or n ~= math.floor(n) then return nil end
    return n
end

local function validCitizenId(v)
    if type(v) ~= 'string' or #v < 1 or #v > 50 or not v:match('^[%w]+$') then return nil end
    return v
end

local function citizenExists(cid)
    if QBCore.Functions.GetPlayerByCitizenId(cid) then return true end
    return MySQL.scalar.await('SELECT 1 FROM players WHERE citizenid = ? LIMIT 1', { cid }) ~= nil
end

local function playerPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

--- Whether the citizen stands within Config.GovApps.FineRange of the official (both read on the server).
local function inPerson(officialSrc, targetSrc)
    local a, b = playerPos(officialSrc), playerPos(targetSrc)
    if not a or not b then return false end
    local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    local range = tonumber(Config.GovApps and Config.GovApps.FineRange) or 5.0
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= range
end

-- the citizen is told about a fine: a notification when online, a letter in their mail either way
local function tellFined(targetCid, billId, amount, description, collected)
    local target = QBCore.Functions.GetPlayerByCitizenId(targetCid)
    local due = amount - (collected or 0)
    if target then
        local text = (collected or 0) > 0
            and ('City fine #%d: $%d (%s). Collected $%s%s'):format(billId, amount, description, tostring(collected), due > 0 and (', $' .. tostring(due) .. ' due in the Bills app') or '')
            or ('City fine #%d: $%d (%s). Pay it in the Bills app.'):format(billId, amount, description)
        NotifyPlayer(target.PlayerData.source, text, 'error')
    end
    if (collected or 0) <= 0 and GetResourceState('pf-citizen') == 'started' then
        pcall(function()
            exports['pf-citizen']:SendMail(targetCid, {
                sender = 'City Hall', senderType = 'government', subject = ('City fine #%d'):format(billId),
                message = ('You were fined $%d: %s\nPay it in the Bills app before it is due (%d days). Unpaid fines become delinquent.'):format(
                    amount, description, math.floor(tonumber(billCfg().DueDays) or 7)),
                ref = 'gov-fine-' .. billId,
            })
        end)
    end
end

--- A fine an official gives a citizen, from any screen (the City Hall terminal, the tablet Fines app,
--- the computer). In person (the citizen online and within Config.GovApps.FineRange of the official,
--- positions read on the server) it is collected at once through the ledger. Otherwise it is an
--- unpaid fine bill the citizen pays in the Bills app (a remote fine used to take the money at once,
--- even from offline citizens). The due date is the server's. Limited per official and per citizen.
--- data = { targetCitizenId, amount, description }. Returns ok, result table | error code.
function IssueOfficialFine(src, data)
    if not HasPermission(src, 'fines') then return false, 'no_permission' end
    if type(data) ~= 'table' then return false, 'bad_request' end
    local officialCid, officialName = GetPlayerIdentifier(src), GetPlayerName(src)
    if not officialCid then return false, 'no_player' end
    local target = validCitizenId(data.targetCitizenId)
    if not target then return false, 'invalid_target' end
    if target == officialCid then return false, 'invalid_target' end
    local amount = wholeAmount(data.amount, tonumber(billCfg().MaxFine) or 50000)
    if not amount then return false, 'invalid_amount' end
    local description = GovCleanText(data.description, 200) or 'City fine'

    return asOfficial(officialCid, function()
        if not citizenExists(target) then return false, 'target_not_found' end
        local limited = issueLimitReached(officialCid, 'citizen', target)
        if limited then return false, limited end
        local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(target)
        if targetPlayer and inPerson(src, targetPlayer.PlayerData.source) then
            local ok, res = IssueFineImmediate(target, amount, description, officialCid, officialName)
            if not ok then return false, res end
            res.inPerson = true
            tellFined(target, res.billId, amount, description, res.collected)
            return true, res
        end
        local ok, msg, billId = CreateBill('citizen', target, amount, 'fine', dueFromNow(), description, officialCid, officialName)
        if not ok then return false, msg end
        tellFined(target, billId, amount, description, 0)
        return true, { billId = billId, collected = 0, remaining = amount, status = 'unpaid', inPerson = false }
    end)
end

--- A bill an official writes by hand (the tablet Fines app fines a business through it). Only the
--- server reaches it (server/callbacks.lua refuses bill:create from clients). The target must exist,
--- the amount is whole and at most Config.Bills.MaxBill, the type one of ManualTypes, a description
--- is required and the due date is the server's (a client's past due date made the bill delinquent
--- within the hour, suspending licenses and cutting power). Limited like fines.
--- Returns ok, bill id | error code.
function CreateOfficialBill(src, data)
    if not HasPermission(src, 'fines') then return false, 'no_permission' end
    if type(data) ~= 'table' then return false, 'bad_request' end
    local officialCid, officialName = GetPlayerIdentifier(src), GetPlayerName(src)
    if not officialCid then return false, 'no_player' end
    local cfg = billCfg()
    local targetType = data.targetType
    if targetType ~= 'citizen' and targetType ~= 'business' then return false, 'invalid_target' end
    local targetId
    if targetType == 'citizen' then
        targetId = validCitizenId(data.targetId)
    elseif type(data.targetId) == 'string' and #data.targetId <= 50 and not data.targetId:find('[%c%s]') and data.targetId ~= '' then
        targetId = data.targetId
    end
    if not targetId then return false, 'invalid_target' end
    local amount = wholeAmount(data.amount, tonumber(cfg.MaxBill) or tonumber(cfg.MaxFine) or 50000)
    if not amount then return false, 'invalid_amount' end
    local billType
    for _, t in ipairs(type(cfg.ManualTypes) == 'table' and cfg.ManualTypes or { 'fine' }) do
        if data.billType == t then billType = t end
    end
    if not billType then return false, 'invalid_type' end
    local description = GovCleanText(data.description, 200)
    if not description then return false, 'description_required' end

    return asOfficial(officialCid, function()
        if targetType == 'citizen' then
            if not citizenExists(targetId) then return false, 'target_not_found' end
        elseif not MySQL.scalar.await('SELECT 1 FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { targetId }) then
            return false, 'target_not_found'
        end
        local limited = issueLimitReached(officialCid, targetType, targetId)
        if limited then return false, limited end
        local ok, msg, billId = CreateBill(targetType, targetId, amount, billType, dueFromNow(), description, officialCid, officialName)
        if not ok then return false, msg end
        if targetType == 'citizen' then tellFined(targetId, billId, amount, description, 0) end
        return true, billId
    end)
end

local OPEN_SQL = "('unpaid', 'partial', 'delinquent')"
local lateFeesRunning = false

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

-- One overdue bill made delinquent, with the escalation actions. False when it was paid or waived
-- since it was read (the status update is guarded), so nothing is done to a settled bill.
local function escalateBill(bill, liveOwners)
    local changed = MySQL.update.await("UPDATE pf_gov_bills SET status = 'delinquent' WHERE id = ? AND status IN ('unpaid', 'partial')", { bill.id })
    if type(changed) == 'number' and changed < 1 then return false end

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
        -- the power of the account the bill is for: a business, or the house of a house utility bill
        -- while the billed citizen still owns it (citizens have no account of their own). For a
        -- house, who owns it now comes from pfm-houses when it can say: a house sold without the
        -- sale reaching us is not cut for the seller's bill.
        local house = type(bill.bill_ref) == 'string' and bill.bill_ref:find('^utility:property:') ~= nil
        local accountType, accountId = accountOfBill(bill, house and liveOwners() or nil)
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
    return true
end

--- Bills still open EscalationDays after their due date become delinquent (escalateBill). Each bill
--- is its own step: one that fails is logged and the others still go. Returns how many escalated.
function ProcessBillEscalation()
    if not Config.Bills.EscalationEnabled then
        return
    end
    
    local escalationSeconds = Config.Bills.EscalationDays * 86400
    local escalationDate = os.date('%Y-%m-%d %H:%M:%S', os.time() - escalationSeconds)
    
    local result = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE status IN (?, ?) AND due_date < ?',
        {'unpaid', 'partial', escalationDate})
    -- house -> its owner now, read from pfm-houses once per run and only if a house bill needs it;
    -- nil when pfm-houses cannot say (then the owner last synced is used)
    local owners
    local function liveOwners()
        if owners == nil then
            owners = false
            local list = PropertyTax and PropertyTax.Houses and PropertyTax.Houses()
            if type(list) == 'table' then
                owners = {}
                for _, h in ipairs(list) do owners[h.house] = h.citizenid end
            end
        end
        return owners or nil
    end
    local escalated = 0
    for _, bill in ipairs(result or {}) do
        local ok, res = pcall(escalateBill, bill, liveOwners)
        if not ok then
            print(('^1[PF-GOVERNMENT]^7 escalating bill #%s failed: %s'):format(tostring(bill.id), tostring(res)))
        elseif res then
            escalated = escalated + 1
        end
    end
    return escalated
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

-- Server-only: the router (server/callbacks.lua) refuses it from clients; the tablet Fines app
-- reaches it through GovApps.CallNui. Every rule is in CreateOfficialBill.
RegisterNUICallback('bill:create', function(data, cb)
    local src = data.source
    local ok, res = CreateOfficialBill(src, data)
    if not ok then
        cb({ ok = false, error = res, message = res })
        return
    end
    cb({ ok = true, message = 'Bill created successfully', billId = res })
end)

-- The payer pays from their bank through the ledger, then the bill is marked. (It used to mark the
-- bill paid and credit the treasury without charging anyone, so any client could clear its fines
-- and put money into the treasury.) One payment per bill at a time. Each charge is recorded before
-- it is made (pf_gov_bill_payments): when the bank cannot say at once whether it went through, the
-- player is told it is being processed (not that they lack the money), cannot pay that bill again
-- until the bank settles it, and the reconcile loop credits the bill once the charge completes.
local function payBillFromPlayer(src, billId, amount)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false, 'Player not found' end
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then return false, 'Payments are unavailable right now', nil, 'server_error' end
    local cid = Player.PlayerData.citizenid
    if settleBillCharges(billId, cid) then
        return false, 'The bank is still processing your earlier payment of this bill. Try again in a minute.', nil, 'payment_pending'
    end
    local bill = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE id = ?', { billId })
    bill = bill and bill[1]
    if not bill then return false, 'Bill not found' end
    if not PAYABLE[bill.status] then return false, 'This bill cannot be paid', nil, 'not_open' end
    local remaining = (tonumber(bill.amount) or 0) - (tonumber(bill.amount_paid) or 0)
    local take = math.floor(math.min(amount, remaining) * 100) / 100
    if take <= 0 then return false, 'Nothing left to pay', nil, 'not_open' end
    local payKey = ('pf-government:billpay:%d:%s'):format(billId, PFPayout.NewId())
    recordCharge(payKey, payKey .. ':bank', billId, cid, take)   -- PFPayout.Charge keys the bank transfer key .. ':bank'
    local charged, res = PFPayout.Charge(Player, 'bank', take, {
        key = payKey, to = 'system:pf-government-fines', kind = 'fine', reason = 'Bill #' .. billId, quiet = true,
    })
    if not charged then
        if type(res) == 'table' and res.unclear then
            return false, 'The bank is still processing this payment. Nothing more was charged; the bill is credited once it goes through.', nil, 'payment_pending'
        end
        markChargeFailed(payKey)
        if type(res) == 'table' and (res.error == 'bank_unavailable' or res.error == 'ledger_unavailable') then
            return false, 'The bank is not responding. Nothing was charged.', nil, 'bank_unavailable'
        end
        return false, 'Not enough money in the bank', nil, 'insufficient_funds'
    end
    -- the bill may have been paid, auto-paid or waived meanwhile by a path outside this lock; only
    -- what is still due is applied and the rest goes back to the player (applyCharge)
    return applyCharge({ pay_key = payKey, bill_id = billId, citizenid = cid, amount = take }, GetPlayerName(src))
end

local function payLocked(src, billId, amount)
    if billPayLocks[billId] then return false, 'A payment for this bill is in progress', nil, 'in_progress' end
    billPayLocks[billId] = true
    local okCall, a, b, c, d = pcall(payBillFromPlayer, src, billId, amount)
    billPayLocks[billId] = nil
    if not okCall then
        print(('^1[PF-GOVERNMENT]^7 paying bill #%s failed: %s'):format(tostring(billId), tostring(a)))
        return false, 'Payment failed', nil, 'server_error'
    end
    return a, b, c, d
end

RegisterNUICallback('bill:pay', function(data, cb)
    local src = data.source or source
    local billId, amount = tonumber(data.billId), tonumber(data.amount)
    if not billId or not amount or amount ~= amount or amount <= 0 or amount == math.huge then
        cb({ ok = false, message = 'Invalid parameters' })
        return
    end
    local success, message, status, code = payLocked(src, billId, amount)

    if success then
        NotifyPlayer(src, 'Payment successful', 'success')
    end

    cb({
        ok = success,
        message = message,
        status = status,
        error = not success and code or nil,
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

    local success, message, extra = WaiveBill(data.billId, citizenid, name, GovCleanText(data.reason, 500))

    if success then
        NotifyPlayer(src, extra and ('Bill waived, $%.2f refunded'):format(extra) or 'Bill waived', 'success')
    end

    cb({
        ok = success,
        message = message,
        refunded = success and extra or nil,
        error = not success and extra or nil,
    })
end)

-- A fine from an official (the City Hall terminal, and the tablet Fines app through GovApps.CallNui):
-- collected at once only in person, otherwise an unpaid fine bill (IssueOfficialFine). Any due date
-- the client sends is ignored.
RegisterNUICallback('fine:issueImmediate', function(data, cb)
    local src = data.source
    local success, result = IssueOfficialFine(src, data)
    if not success then
        cb({ ok = false, error = result, result = result })
        return
    end
    cb({ ok = true, result = result })
end)

print('^2[PF-GOVERNMENT]^7 Bills system loaded')

--- Creates a fine bill for `targetCitizenId` and collects it at once (server callers only; the
--- caller decides the fine is due now). The due date of what is left is the server's. For a fine an
--- official issues, use IssueFineAs: it collects only in person and applies the limits.
exports('IssueFineImmediate', function(targetCitizenId, amount, description, issuedBy, issuedByName)
    return IssueFineImmediate(targetCitizenId, amount, GovCleanText(description, 200) or 'City fine', issuedBy, issuedByName)
end)

--- A fine the official `src` issues from another resource's screen (pf-computer's City Hall),
--- through the same rules as the government's own screens. data = { targetCitizenId, amount,
--- description }. Returns ok, result | error code.
exports('IssueFineAs', function(src, data)
    return IssueOfficialFine(tonumber(src), data)
end)

--- Pays (part of) a bill from the player's bank through the same locked path as the city hall
--- terminal, so the Bills app and a terminal can never pay the same bill twice at once.
--- Returns ok, message, new status, error code ('insufficient_funds' | 'not_open' | 'payment_pending'
--- | 'in_progress' | 'bank_unavailable' | 'server_error').
exports('PayBillFromPlayer', function(src, billId, amount)
    billId, amount = tonumber(billId), tonumber(amount)
    if not billId or not amount or amount ~= amount or amount <= 0 or amount == math.huge then return false, 'Invalid amount' end
    return payLocked(src, billId, amount)
end)
