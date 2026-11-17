-- Hospital bills: itemised, built from server records only, paid once (batch 17E, architecture
-- 4.5.1, owner decisions D5/D6).
--
-- A bill is made once per admission, when the admission closes (discharge, transfer, left AMA).
-- Its lines come from the admission row (intake fee by reason, bed hours by department, AI mode)
-- and the treatment log (pf_med_treatments, including the AI care rows), priced by
-- Config.Hospital.Tariff; nothing the client sends is used. Coverage (D6: no insurer exists) is a
-- flat discount by the patient's server job.
--
-- Payment goes straight from the patient's bank to society:ambulance in one ledger transfer
-- (replacing the old charge-to-the-resource-then-mint-to-the-society). Keys:
--   charge    pf-ambulancejob:bill:<billId>:<attempt>  (PFPayout.Charge adds ':bank')
--   invoice   ref pf-ambulancejob:bill:<billId>        (pfm-phone, cannot be declined)
-- The attempt number is stored (state 'charging') before the ledger call, so a crash leaves a key
-- to look up. Outcomes:
--   paid                 -> 'paid'
--   clear refusal (no funds, or MaxChargeAttempts reached) -> a phone invoice -> 'invoiced', and
--                           'paid' when pfm-phone reports the invoice settled
--   bank not running     -> 'open'; the sweep tries again with the next numbered key
--   unclear              -> 'payment_pending'; the sweep looks the key up (GetTransaction) and never
--                           charges again under a new key until it is clearly failed
-- A patient who cannot pay is still treated (the bill comes after the care).

PFHospital = PFHospital or {}
local H = PFHospital
H.Billing = H.Billing or {}
local Bl = H.Billing
H.SQL = H.SQL or {}
local Q = H.SQL

local function cfg() return Config.Hospital end
local now = function() return H.Now() end

-- ── SQL ───────────────────────────────────────────────────────────────────────────────────────

local BILL_COLS = 'id, citizenid, admission_id, hospital_id, total, discount, state, attempt, pay_key, invoice_id, created_at, settled_at, next_check_at'

function Q.FindBillByAdmission(admissionId)
    return MySQL.single.await('SELECT ' .. BILL_COLS .. ' FROM pf_hosp_bills WHERE admission_id = ? ORDER BY id LIMIT 1', { admissionId })
end

function Q.GetBill(id)
    return MySQL.single.await('SELECT ' .. BILL_COLS .. ' FROM pf_hosp_bills WHERE id = ? LIMIT 1', { id })
end

function Q.InsertBill(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_bills (citizenid, admission_id, hospital_id, total, discount, state, attempt, created_at, next_check_at)
        VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)]], { r.citizenid, r.admission_id, r.hospital_id, r.total, r.discount, r.state, r.created_at, r.next_check_at })
end

--- All lines of one bill in one statement (all or none).
function Q.InsertBillLines(billId, lines)
    if #lines == 0 then return true end
    local values, params, n = {}, {}, 0
    for _, l in ipairs(lines) do
        values[#values + 1] = '(?, ?, ?, ?, ?, ?)'
        -- placed by index: a nil ref_id must keep its position
        params[n + 1], params[n + 2], params[n + 3] = billId, l.kind, l.ref_id
        params[n + 4], params[n + 5], params[n + 6] = l.label, l.qty, l.unit_price
        n = n + 6
    end
    MySQL.insert.await('INSERT INTO pf_hosp_bill_lines (bill_id, kind, ref_id, label, qty, unit_price) VALUES ' .. table.concat(values, ', '), params)
    return true
end

function Q.BillLines(billId)
    return MySQL.query.await('SELECT id, kind, ref_id, label, qty, unit_price FROM pf_hosp_bill_lines WHERE bill_id = ? ORDER BY id', { billId }) or {}
end

--- One conditional step: changes the bill only while it is still in (state, attempt).
function Q.MoveBill(id, fromState, fromAttempt, r)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_bills SET state = ?, attempt = ?, pay_key = ?, invoice_id = ?, settled_at = ?, next_check_at = ?
        WHERE id = ? AND state = ? AND attempt = ?]], { r.state, r.attempt, r.pay_key, r.invoice_id, r.settled_at, r.next_check_at, id, fromState, fromAttempt }))
end

function Q.DueBills(at, limit)
    return MySQL.query.await([[SELECT id FROM pf_hosp_bills WHERE state IN ('open', 'charging', 'payment_pending')
        AND (next_check_at IS NULL OR next_check_at <= ?) ORDER BY id LIMIT ?]], { at, limit or 50 }) or {}
end

function Q.TreatmentsFor(cid, admissionId, fromAt, toAt)
    return MySQL.query.await([[SELECT id, action, location, result, admission_id, by_cid, by_job, at FROM pf_med_treatments
        WHERE citizenid = ? AND (admission_id = ? OR (admission_id IS NULL AND location IN ('hospital', 'or') AND at >= ? AND at <= ?))
        ORDER BY id LIMIT 200]], { cid, admissionId, fromAt, toAt }) or {}
end

-- ── lines from server records ─────────────────────────────────────────────────────────────────

local function pretty(action)
    local label = tostring(action):gsub('_', ' ')
    return (label:gsub('^%l', string.upper))
end

local function treatmentLine(row, tariff)
    local action = tostring(row.action)
    local price, kind = tariff.Drugs[action], 'drug'
    if price == nil then
        price = tariff.Treatments[action]
        kind = action:find('^ai_') and 'ai_care' or (action:find('^surgery_') and 'procedure' or 'treatment')
    end
    if price == nil then price = tariff.DefaultTreatment or 0 end
    return { kind = kind, ref_id = tonumber(row.id), label = pretty(action):sub(1, 96), qty = 1, unit_price = math.floor(price) }
end

--- Only care the hospital gave is billed: the AI's own rows, or a row by hospital staff (a job in
--- Config.Hospital.StaffJobs) on someone else. Self-care (by_cid = the patient), care by a civilian
--- or by another job, and rows with no provider are never billed.
function Bl.Billable(row, patientCid)
    if row.by_job == 'ai_care' then return true end
    if type(row.by_cid) ~= 'string' or row.by_cid == '' or row.by_cid == patientCid then return false end
    return cfg().StaffJobs[tostring(row.by_job)] == true
end

--- The bill lines for a closed admission (from the row and the treatment log). Returns lines | nil, err.
function Bl.Lines(a)
    local tariff = cfg().Tariff
    local lines = {}
    local reasonKey = tostring(a.reason or ''):match('^(%a+)') or 'checkin'
    local fee = tariff.Admission[reasonKey]
    if fee and fee > 0 then
        lines[#lines + 1] = { kind = 'procedure', ref_id = a.id, label = ('Admission (%s)'):format(reasonKey), qty = 1, unit_price = math.floor(fee) }
    end
    local closedAt = tonumber(a.discharged_at) or now()
    if a.admitted_at and a.dept then
        local perHour = tariff.BedHour[a.dept] or 0
        if perHour > 0 then
            local hours = math.max(tariff.BedMinHours or 1, math.ceil(math.max(0, closedAt - a.admitted_at) / 3600))
            lines[#lines + 1] = { kind = 'bed', ref_id = a.id, label = ('Bed, %s'):format(a.dept), qty = hours, unit_price = math.floor(perHour) }
        end
    end
    local ok, rows = pcall(Q.TreatmentsFor, a.citizenid, a.id, a.arrived_at or 0, closedAt)
    if not ok then return nil, 'db_unavailable' end
    for _, row in ipairs(rows or {}) do
        if tariff.BillableResults[tostring(row.result)] and Bl.Billable(row, a.citizenid) then
            local line = treatmentLine(row, tariff)
            if line.unit_price > 0 then lines[#lines + 1] = line end
        end
    end
    if a.mode == 'ai' then
        -- AI care costs more (D17); staff care is the better deal
        local mult = cfg().AI.PriceMultiplier or 1.5
        for _, l in ipairs(lines) do l.unit_price = math.floor(l.unit_price * mult + 0.5) end
    end
    return lines
end

--- Discount percent and label for a citizen (server job when online; none offline).
function Bl.Coverage(cid)
    local P = H.PlayerByCid(cid)
    local job = P and P.PlayerData.job
    if type(job) ~= 'table' then return 0 end
    for _, c in ipairs(cfg().Coverage or {}) do
        if c.jobs[job.name] and (not c.onDuty or job.onduty == true) then
            return math.max(0, math.min(100, tonumber(c.percent) or 0)), c.label
        end
    end
    return 0
end

function Bl.Key(id, attempt) return ('pf-ambulancejob:bill:%d:%d'):format(id, attempt) end
function Bl.Ref(id) return ('pf-ambulancejob:bill:%d'):format(id) end

local function net(bill) return math.max(0, (tonumber(bill.total) or 0) - (tonumber(bill.discount) or 0)) end
Bl.Net = net

local function step(bill, to)
    local r = { state = bill.state, attempt = tonumber(bill.attempt) or 0, pay_key = bill.pay_key, invoice_id = bill.invoice_id,
        settled_at = bill.settled_at, next_check_at = bill.next_check_at }
    for k, v in pairs(to) do r[k] = v end
    if to.next_check_at == false then r.next_check_at = nil end
    if to.invoice_id == false then r.invoice_id = nil end
    local ok, n = pcall(Q.MoveBill, tonumber(bill.id), bill.state, tonumber(bill.attempt) or 0, r)
    if not ok or n ~= 1 then return false end
    for k, v in pairs(r) do bill[k] = v end
    return true
end

local function tell(cid, text, kind)
    H.Notify(H.SourceOfCid(cid), text, kind)
end

local function mail(bill, lines)
    if not cfg().Billing.Mail or not H.Started('pf-citizen') then return end
    local label = H.Facility.Label(bill.hospital_id)
    local out = { ('Bill #%d from %s'):format(bill.id, label), '' }
    for _, l in ipairs(lines) do out[#out + 1] = ('%s x%d  $%d'):format(l.label, l.qty, l.qty * l.unit_price) end
    out[#out + 1] = ''
    if (tonumber(bill.discount) or 0) > 0 then out[#out + 1] = ('Coverage discount  -$%d'):format(bill.discount) end
    out[#out + 1] = ('Total due  $%d'):format(net(bill))
    out[#out + 1] = 'Your bank is charged; if it cannot pay, the bill arrives as a phone invoice.'
    pcall(function()
        exports['pf-citizen']:SendMail(bill.citizenid, { sender = label, senderType = 'system', subject = ('Hospital bill #%d'):format(bill.id),
            message = table.concat(out, '\n'), ref = Bl.Ref(bill.id) })
    end)
end

-- ── collect ───────────────────────────────────────────────────────────────────────────────────

local function paid(bill)
    if not step(bill, { state = 'paid', settled_at = now(), next_check_at = false }) then return 'busy' end
    tell(bill.citizenid, ('Hospital bill #%d paid ($%d).'):format(bill.id, net(bill)), 'success')
    return 'paid'
end

local function invoice(bill)
    local maxed = math.max(tonumber(bill.attempt) or 0, cfg().Billing.MaxChargeAttempts or 5)
    if not H.Started('pfm-phone') then
        step(bill, { attempt = maxed, next_check_at = now() + (cfg().Billing.SweepSeconds or 120) })
        return 'wait'
    end
    local label = cfg().Billing.InvoiceSender or H.Facility.Label(bill.hospital_id)
    local ok, id, err = pcall(function()
        return exports['pfm-phone']:CreateInvoice({ citizenid = bill.citizenid, amount = net(bill), society = cfg().Billing.Account,
            sender = label, candecline = 0, reason = ('Hospital bill #%d (%s)'):format(bill.id, label), ref = Bl.Ref(bill.id) })
    end)
    id = ok and tonumber(id) or nil
    if not id then
        print(('^3[pf-ambulancejob]^7 bill %d: invoice not created (%s); the sweep tries again'):format(bill.id, tostring(ok and err or id)))
        step(bill, { attempt = maxed, next_check_at = now() + (cfg().Billing.SweepSeconds or 120) })
        return 'wait'
    end
    if not step(bill, { state = 'invoiced', attempt = maxed, invoice_id = id, next_check_at = false }) then return 'busy' end
    tell(bill.citizenid, ('Your bank could not pay hospital bill #%d: it is now a phone invoice ($%d).'):format(bill.id, net(bill)), 'error')
    return 'invoiced'
end

local function charge(bill)
    local attempt = (tonumber(bill.attempt) or 0) + 1
    local key = Bl.Key(bill.id, attempt)
    -- stored before the ledger call, so a crash leaves this key to look up
    if not step(bill, { state = 'charging', attempt = attempt, pay_key = key, next_check_at = now() + (cfg().Billing.SweepSeconds or 120) }) then
        return 'busy'
    end
    local acct, res = PFPayout.Charge(bill.citizenid, { 'bank' }, net(bill), {
        key = key, to = 'society:' .. cfg().Billing.Account, kind = 'medical', quiet = true,
        reason = ('Hospital bill #%d'):format(bill.id), metadata = { bill = bill.id, admission = tonumber(bill.admission_id) },
    })
    if acct then return paid(bill) end
    res = type(res) == 'table' and res or { ok = false, error = 'bank_unavailable' }
    if PFPayout.IsClearFailure(res) then
        if res.error == 'bank_unavailable' or res.error == 'ledger_unavailable' then
            step(bill, { state = 'open', next_check_at = now() + (cfg().Billing.SweepSeconds or 120) })
            return 'wait'
        end
        -- a clear refusal (no funds): no more bank charges, the rest goes to a phone invoice
        if not step(bill, { state = 'open', attempt = math.max(attempt, cfg().Billing.MaxChargeAttempts or 5), next_check_at = false }) then return 'busy' end
        return invoice(bill)
    end
    step(bill, { state = 'payment_pending', next_check_at = now() + (cfg().Billing.SweepSeconds or 120) })
    print(('^3[pf-ambulancejob]^7 bill %d: charge %s is unclear (%s); the sweep settles it'):format(bill.id, key, tostring(res.error or res.state)))
    return 'pending'
end

--- A charge whose outcome was not known: look the key up, never charge again until it clearly failed.
local function checkKey(bill)
    if not H.Started('pfm-banking') then return 'wait' end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(tostring(bill.pay_key) .. ':bank') end)
    if not ok then return 'wait' end
    if type(tx) == 'table' and tx.state == 'completed' then return paid(bill) end
    if tx == nil or PFPayout.IsClearFailure({ ok = false, state = tx.state, error = tx.error, txId = tx.tx_id }) then
        if not step(bill, { state = 'open', next_check_at = false }) then return 'busy' end
        return 'failed'
    end
    step(bill, { next_check_at = now() + (cfg().Billing.SweepSeconds or 120) })
    return 'wait'
end

--- One collection step for a bill. Returns 'paid' | 'invoiced' | 'pending' | 'failed' | 'wait' |
--- 'busy' | 'skip' | 'waived'.
function Bl.Collect(id)
    id = tonumber(id)
    if not id then return 'skip' end
    local res = H.WithLock('bill:' .. id, function()
        local ok, bill = pcall(Q.GetBill, id)
        if not ok or not bill then return 'skip' end
        bill.id = tonumber(bill.id)
        if bill.state == 'charging' or bill.state == 'payment_pending' then
            local r = checkKey(bill)
            if r ~= 'failed' then return r end
        end
        if bill.state ~= 'open' then return 'skip' end
        if net(bill) <= 0 then
            return step(bill, { state = 'waived', settled_at = now(), next_check_at = false }) and 'waived' or 'busy'
        end
        if (tonumber(bill.attempt) or 0) >= (cfg().Billing.MaxChargeAttempts or 5) then return invoice(bill) end
        return charge(bill)
    end)
    return res or 'busy'
end

--- Makes the one bill of a closed admission and starts collecting it. Returns bill id | nil.
function Bl.ForAdmission(a, ctx)
    if not a or not a.id then return nil end
    local res = H.WithLock('bill:adm:' .. a.id, function()
        local okFind, existing = pcall(Q.FindBillByAdmission, a.id)
        if not okFind then return nil end
        if existing then return tonumber(existing.id), true end
        local lines = Bl.Lines(a)
        if not lines then return nil end
        local total = 0
        for _, l in ipairs(lines) do total = total + l.qty * l.unit_price end
        if total <= 0 then return nil end
        local pct = Bl.Coverage(a.citizenid)
        local discount = math.floor(total * pct / 100)
        local t = now()
        local okIns, id = pcall(Q.InsertBill, { citizenid = a.citizenid, admission_id = a.id, hospital_id = a.hospital_id, total = total,
            discount = discount, state = 'open', created_at = t, next_check_at = t })
        id = okIns and tonumber(id) or nil
        if not id then return nil end
        local okLines = pcall(Q.InsertBillLines, id, lines)
        if not okLines then print(('^1[pf-ambulancejob]^7 bill %d: the lines were not written'):format(id)) end
        H.Audit(a.citizenid, 'bill', ctx and ctx.actor, { bill = id, admission = a.id, total = total, discount = discount })
        mail({ id = id, citizenid = a.citizenid, hospital_id = a.hospital_id, total = total, discount = discount }, lines)
        return id
    end)
    if res then Bl.Collect(res) end
    return res
end

--- Pass over bills that wait for a key lookup, a retry or an invoice (named for specs).
function Bl.Sweep(at)
    local ok, rows = pcall(Q.DueBills, at or now(), 50)
    if not ok then return 0 end
    local n = 0
    for _, r in ipairs(rows or {}) do
        Bl.Collect(r.id)
        n = n + 1
    end
    return n
end

--- pfm-phone settled an invoice: only ours (by ref, never by the reused id) and for the bill's amount.
function Bl.OnInvoiceSettled(invoice, status)
    if type(invoice) ~= 'table' or type(invoice.ref) ~= 'string' then return nil end
    local id = tonumber(invoice.ref:match('^pf%-ambulancejob:bill:(%d+)$'))
    if not id then return nil end
    return H.WithLock('bill:' .. id, function()
        local ok, bill = pcall(Q.GetBill, id)
        if not ok or not bill then return nil end
        bill.id = tonumber(bill.id)
        if bill.state ~= 'invoiced' then return 'skip' end
        if tonumber(invoice.amount) ~= net(bill) or invoice.citizenid ~= bill.citizenid then
            print(('^3[pf-ambulancejob]^7 invoice for bill %d settled with another amount or payer; ignored'):format(id))
            return 'mismatch'
        end
        if status == 'paid' then return paid(bill) end
        if status == 'cancelled' then
            -- withdrawn in pfm-phone (an admin): the debt is dropped, and that is recorded
            return step(bill, { state = 'waived', settled_at = now(), next_check_at = false }) and 'waived' or 'busy'
        end
        -- any other end (a decline that should not be possible): invoice again from the sweep
        return step(bill, { state = 'open', invoice_id = false, next_check_at = false }) and 'reopened' or 'busy'
    end)
end

-- server-only: pfm-phone raises it with TriggerEvent; a client cannot (a player source is ignored)
AddEventHandler('pfm-phone:server:invoiceSettled', function(invoice, status)
    local s = tonumber(source)
    if s and s > 0 then return end
    Bl.OnInvoiceSettled(invoice, status)
end)

CreateThread(function()
    while true do
        Wait((cfg().Billing.SweepSeconds or 120) * 1000)
        if H.Admissions and H.Admissions.Ready() then
            local ok, err = pcall(Bl.Sweep, now())
            if not ok then print('^1[pf-ambulancejob]^7 bill sweep failed: ' .. tostring(err)) end
        end
    end
end)
