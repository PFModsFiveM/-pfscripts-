-- Government business loans: due dates, interest, installments, auto-pay and defaults.
--
-- Each due date (next_due_at) is claimed once with a guarded UPDATE: interest for the period is
-- added to the remaining amount, an installment is added to amount_due, and the due date moves
-- one interval on. Loans with auto_pay then pay amount_due from the business account (its
-- account_ref on the registry) to the treasury. An unpaid installment counts as a missed payment;
-- after Config.Loans.DefaultAfterMissed the loan is defaulted and the business marked non-compliant.

Loans = Loans or {}
local L = Loans

local function cfg() return Config.Loans or {} end
local function round2(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end

local columnsReady = false
function L.EnsureColumns()
    if columnsReady then return end
    GovEnsureBusinessExtensions()
    for _, col in ipairs({
        { 'missed_payments', 'INT NOT NULL DEFAULT 0' },
        { 'amount_due', 'DECIMAL(15,2) NOT NULL DEFAULT 0.00' },
    }) do
        local has = MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { 'pf_gov_business_loans', col[1] })
        if tonumber(has or 0) == 0 then
            pcall(function() MySQL.query.await(('ALTER TABLE pf_gov_business_loans ADD COLUMN `%s` %s'):format(col[1], col[2])) end)
        end
    end
    columnsReady = true
end

local function treasuryRef()
    local t = Config.Treasury and Config.Treasury.UseSocietyAccount and Config.Treasury.SocietyAccount
    return (t and t ~= '') and ('society:' .. t) or nil
end

--- The ledger account of a registered business (its account_ref), or nil.
function L.AccountFor(businessId)
    local row = MySQL.single.await('SELECT account_ref FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })
    local ref = row and row.account_ref
    return (type(ref) == 'string' and ref ~= '') and ref or nil
end

local function transfer(from, to, amount, key, kind, reason, actor)
    if GetResourceState('pfm-banking') ~= 'started' then return { ok = false, error = 'banking_unavailable' } end
    local ok, res = pcall(function()
        return exports['pfm-banking']:Transfer({ from = from, to = to, amount = amount, key = key, kind = kind, reason = reason, actor = actor })
    end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'payment_failed' } end
    return res
end
L.Transfer = transfer

local function flagCompliance(businessId, level)
    -- only ever makes the record worse; an inspection sets it back
    local order = { compliant = 0, warning = 1, non_compliant = 2, flagged = 3 }
    local cur = MySQL.scalar.await('SELECT compliance_status FROM pf_gov_businesses WHERE business_id = ?', { businessId })
    if (order[cur] or 0) < (order[level] or 0) then
        MySQL.update.await('UPDATE pf_gov_businesses SET compliance_status = ?, updated_at = NOW() WHERE business_id = ?', { level, businessId })
    end
end

--- Applies a payment to a loan row (after the money moved). Returns remaining, status, due.
function L.ApplyPayment(loan, paid)
    local remaining = math.max(0, round2((tonumber(loan.remaining_amount) or 0) - paid))
    local due = math.max(0, round2((tonumber(loan.amount_due) or 0) - paid))
    local missed = tonumber(loan.missed_payments) or 0
    if due <= 0 then missed = 0 end
    local status = remaining <= 0 and 'paid' or ((loan.status == 'defaulted' and due > 0) and 'defaulted' or 'active')
    MySQL.update.await('UPDATE pf_gov_business_loans SET remaining_amount = ?, amount_due = ?, missed_payments = ?, status = ?, updated_at = NOW() WHERE id = ?',
        { remaining, due, missed, status, loan.id })
    return remaining, status, due
end

--- One due date of one loan.
function L.ProcessDue(loan)
    local c = cfg()
    local interest = round2((tonumber(loan.remaining_amount) or 0) * (tonumber(loan.interest_rate) or 0) / 100)
    local remainingAfter = round2((tonumber(loan.remaining_amount) or 0) + interest)
    local installment = round2(math.max(tonumber(c.MinInstallment) or 100,
        (tonumber(loan.principal_amount) or 0) * (tonumber(c.InstallmentPercent) or 10) / 100))
    local dueAfter = math.min(remainingAfter, round2((tonumber(loan.amount_due) or 0) + installment))

    -- claim this due date once (another tick or server cannot process it again)
    local claimed = MySQL.update.await([[UPDATE pf_gov_business_loans
        SET remaining_amount = ?, amount_due = ?, next_due_at = DATE_ADD(next_due_at, INTERVAL GREATEST(1, payment_interval_days) DAY), updated_at = NOW()
        WHERE id = ? AND status = 'active' AND UNIX_TIMESTAMP(next_due_at) = ?]], { remainingAfter, dueAfter, loan.id, loan.due_ts })
    if (tonumber(claimed) or 0) == 0 then return 'skipped' end
    loan.remaining_amount, loan.amount_due = remainingAfter, dueAfter

    local paidOk = false
    if tonumber(loan.auto_pay) == 1 and dueAfter > 0 then
        local from, to = L.AccountFor(loan.business_id), treasuryRef()
        if from and to then
            local res = transfer(from, to, dueAfter, ('pf-government:loandue:%s:%s:%s'):format(loan.id, tostring(loan.due_ts), PFPayout.NewId()),
                'loan_repayment', 'Government loan installment (auto-pay)', 'system')
            if res.ok then
                L.ApplyPayment(loan, dueAfter)
                paidOk = true
            end
        end
    end
    if paidOk or dueAfter <= 0 then return 'paid' end

    local missed = (tonumber(loan.missed_payments) or 0) + 1
    local defaultAfter = math.max(1, tonumber(c.DefaultAfterMissed) or 3)
    local status = missed >= defaultAfter and 'defaulted' or 'active'
    MySQL.update.await('UPDATE pf_gov_business_loans SET missed_payments = ?, status = ?, updated_at = NOW() WHERE id = ?', { missed, status, loan.id })
    if status == 'defaulted' then
        flagCompliance(loan.business_id, 'non_compliant')
        LogAudit('loan_defaulted', 'system', 'Treasury', 'business', loan.business_id, { loanId = loan.id, owed = dueAfter, remaining = remainingAfter })
        GovEmit('gov.loan.defaulted', function()
            local facts = GovBusinessFacts(loan.business_id)
            return { businessId = loan.business_id, business = facts.business, businessType = facts.businessType,
                owed = dueAfter, remaining = remainingAfter, missedPayments = missed,
                businessName = facts.business, type = facts.businessType, amount = remainingAfter },
                { title = ('%s defaults on its city loan'):format(tostring(facts.business)), district = facts.district, coords = facts.coords }
        end)
        if c.CloseBusinessOnDefault == true then
            local closed = MySQL.update.await("UPDATE pf_gov_businesses SET business_status = 'closed', closed_at = NOW(), updated_at = NOW() WHERE business_id = ? AND COALESCE(business_status, 'active') <> 'closed'", { loan.business_id })
            if (tonumber(closed) or 0) > 0 then
                GovAnnounceBusiness('gov.business.closed', loan.business_id, { reason = 'Defaulted on a city loan' }, 'system')
            end
        end
        return 'defaulted'
    end
    flagCompliance(loan.business_id, 'warning')
    LogAudit('loan_payment_missed', 'system', 'Treasury', 'business', loan.business_id, { loanId = loan.id, owed = dueAfter, missed = missed })
    return 'missed'
end

function L.Tick()
    L.EnsureColumns()
    local due = MySQL.query.await([[SELECT *, UNIX_TIMESTAMP(next_due_at) AS due_ts FROM pf_gov_business_loans
        WHERE status = 'active' AND next_due_at IS NOT NULL AND next_due_at <= NOW() ORDER BY next_due_at LIMIT 50]]) or {}
    for _, loan in ipairs(due) do
        local ok, err = pcall(L.ProcessDue, loan)
        if not ok then print('^1[PF-GOVERNMENT]^7 loan ' .. tostring(loan.id) .. ' failed: ' .. tostring(err)) end
    end
    return #due
end

CreateThread(function()
    Wait(30000)
    while true do
        if cfg().Enabled ~= false then pcall(L.Tick) end
        Wait(math.max(1, tonumber(cfg().CheckMinutes) or 5) * 60000)
    end
end)
