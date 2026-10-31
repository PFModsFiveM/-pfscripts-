-- Bills: everything a citizen owes in one list, each paid through the system that owns it.
--   gov:<id>    pf-government bills and fines (pf_gov_bills) of the citizen and of businesses they
--               manage. Paid the way pf-government's own bill:pay does it: the bank is charged on
--               the ledger into system:pf-government-fines, then pf-government's PayBill marks it.
--   phone:<id>  phone invoices (phone_invoices), paid and declined through pfm-phone's own
--               PayInvoice / DeclineInvoice, so the business, the biller's commission and the
--               phone's mails stay exactly as on the phone.
-- Settled phone invoices are deleted by the phone; their history is kept in pf_citizen_bill_history.

PFCitizen = PFCitizen or {}
PFCitizen.Bills = PFCitizen.Bills or {}
local C = PFCitizen
local B = PFCitizen.Bills
local CFG = CitizenConfig.Bills

local OPEN_GOV = { unpaid = true, partial = true, delinquent = true }
local GOV_TYPES = { fine = 'Fine', tax = 'Tax', utility = 'Utilities', license = 'License fee', invoice = 'Invoice', other = 'City bill' }

local function money(n)
    n = tonumber(n) or 0
    if n % 1 == 0 then return ('$%d'):format(n) end
    return ('$%.2f'):format(n)
end
B.Money = money

local function cents(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end

local function jobLabel(name)
    local ok, jobs = pcall(function() return exports['pfm-core']:GetShared('Jobs') end)
    local job = ok and type(jobs) == 'table' and jobs[name] or nil
    return job and job.label or tostring(name or 'Business')
end

local function govRows(where, params)
    if not C.Started('pf-government') then return {} end
    local ok, rows = pcall(MySQL.query.await, [[SELECT id, bill_type, target_type, target_id, amount, amount_paid, status, description,
        issued_by_name, UNIX_TIMESTAMP(due_date) AS due, UNIX_TIMESTAMP(issued_at) AS issued, UNIX_TIMESTAMP(paid_at) AS settled
        FROM pf_gov_bills WHERE ]] .. where .. ' ORDER BY id DESC LIMIT 100', params)
    return ok and rows or {}
end

local function govView(r, businessName)
    local amount, paid = cents(r.amount), cents(r.amount_paid)
    local remaining = math.max(0, cents(amount - paid))
    local due = tonumber(r.due)
    local status = r.status
    if status == 'unpaid' or status == 'partial' then
        if due and due < os.time() then status = 'overdue' elseif status == 'unpaid' then status = 'open' end
    end
    local label = GOV_TYPES[r.bill_type] or 'City bill'
    local desc = r.description and tostring(r.description) ~= '' and tostring(r.description) or nil
    return {
        key = 'gov:' .. tostring(r.id), source = 'government', id = tonumber(r.id),
        title = desc and C.Cut(desc, 120) or label, kind = label,
        from = r.issued_by_name and tostring(r.issued_by_name) ~= '' and ('City of Los Santos · ' .. tostring(r.issued_by_name)) or 'City of Los Santos',
        business = businessName, amount = amount, paid = paid, remaining = remaining, status = status,
        due = due, issued = tonumber(r.issued), settled = tonumber(r.settled),
        canPay = OPEN_GOV[r.status] == true and remaining > 0, canDecline = false,
        open = OPEN_GOV[r.status] == true,
    }
end

local function phoneView(r)
    local society = tostring(r.society or '')
    local reason = r.reason and tostring(r.reason) ~= '' and tostring(r.reason) or nil
    return {
        key = 'phone:' .. tostring(r.id), source = 'phone', id = tonumber(r.id),
        title = reason and C.Cut(reason, 120) or ('Invoice from ' .. jobLabel(society)), kind = 'Invoice',
        from = ('%s%s'):format(jobLabel(society), r.sender and tostring(r.sender) ~= '' and (' · ' .. tostring(r.sender)) or ''),
        amount = cents(r.amount), paid = 0, remaining = cents(r.amount), status = 'open', due = nil,
        canPay = (tonumber(r.amount) or 0) > 0 and C.Started('pfm-phone'), canDecline = tonumber(r.candecline) == 1 and C.Started('pfm-phone'),
        open = true,
    }
end

function B.List(src)
    local P = C.Player(src)
    if not P then return { ok = false, error = 'no_player' } end
    local cid = P.PlayerData.citizenid
    local open, history = {}, {}
    local function add(v) if v.open then open[#open + 1] = v else history[#history + 1] = v end end

    for _, r in ipairs(govRows("target_type = 'citizen' AND target_id = ?", { cid })) do add(govView(r)) end
    local managed = C.ManagedBusinesses(src)
    if #managed > 0 then
        local ids, names, marks = {}, {}, {}
        for _, b in ipairs(managed) do ids[#ids + 1] = b.business_id; names[b.business_id] = b.business_name; marks[#marks + 1] = '?' end
        for _, r in ipairs(govRows("target_type = 'business' AND target_id IN (" .. table.concat(marks, ',') .. ')', ids)) do
            add(govView(r, names[r.target_id]))
        end
    end
    local okP, invoices = pcall(MySQL.query.await, 'SELECT id, amount, society, sender, candecline, reason FROM phone_invoices WHERE citizenid = ? ORDER BY id DESC LIMIT 100', { cid })
    for _, r in ipairs(okP and invoices or {}) do add(phoneView(r)) end
    for _, h in ipairs(MySQL.query.await([[SELECT source, ref, title, counterparty, amount, outcome, UNIX_TIMESTAMP(settled_at) AS settled
        FROM pf_citizen_bill_history WHERE citizenid = ? ORDER BY settled_at DESC, id DESC LIMIT ?]], { cid, CFG.HistoryLimit }) or {}) do
        history[#history + 1] = { key = h.source .. ':' .. h.ref, source = h.source, title = h.title, from = h.counterparty,
            amount = cents(h.amount), paid = h.outcome == 'paid' and cents(h.amount) or 0, remaining = 0, status = h.outcome,
            settled = tonumber(h.settled), canPay = false, canDecline = false, open = false }
    end
    table.sort(history, function(a, b) return (a.settled or a.issued or 0) > (b.settled or b.issued or 0) end)
    while #history > CFG.HistoryLimit do history[#history] = nil end

    local due, overdue = 0, 0
    for _, v in ipairs(open) do
        due = due + (v.remaining or 0)
        if v.status == 'overdue' or v.status == 'delinquent' then overdue = overdue + 1 end
    end
    local bank = P.PlayerData.money and P.PlayerData.money.bank or nil
    return { ok = true, open = open, history = history, totalDue = cents(due), overdue = overdue, bank = bank }
end

-- ── paying ──────────────────────────────────────────────────────────

local govLocks = {}

local function payGov(src, billId, wanted)
    local P = C.Player(src)
    if not P then return { ok = false, error = 'no_player' } end
    local cid = P.PlayerData.citizenid
    local gov = C.Gov()
    if not gov then return { ok = false, error = 'government_offline' } end
    local bill = MySQL.single.await('SELECT id, target_type, target_id, amount, amount_paid, status FROM pf_gov_bills WHERE id = ? LIMIT 1', { billId })
    if not bill then return { ok = false, error = 'not_found' } end
    if bill.target_type == 'citizen' then
        if bill.target_id ~= cid then return { ok = false, error = 'not_found' } end
    elseif not C.ManagesBusiness(src, bill.target_id) then
        return { ok = false, error = 'not_found' }
    end
    if not OPEN_GOV[bill.status] then return { ok = false, error = 'not_open' } end
    local remaining = cents((tonumber(bill.amount) or 0) - (tonumber(bill.amount_paid) or 0))
    local take = math.floor(math.min(wanted or remaining, remaining) * 100) / 100
    if take <= 0 then return { ok = false, error = 'nothing_due' } end

    -- pf-government's own payment for other resources, once it offers one
    local okX, done, _, status, code = pcall(function() return gov:PayBillFromPlayer(src, billId, take) end)
    if okX and done ~= nil then
        if done ~= true then return { ok = false, error = code or 'payment_failed' } end
        return { ok = true, paid = take, status = status }
    end

    local key = ('pf-citizen:govbill:%d:%s'):format(billId, PFPayout.NewId())
    local account, res = PFPayout.Charge(P, 'bank', take, { key = key, to = CFG.GovFinesAccount, kind = 'fine', reason = 'Bill #' .. billId, quiet = true })
    if not account then return { ok = false, error = (res and res.error == 'bank_unavailable') and 'bank_unavailable' or 'insufficient_funds' } end

    -- read again: a payment made meanwhile elsewhere (the city hall terminal) must not be paid twice
    local fresh = MySQL.single.await('SELECT amount, amount_paid, status FROM pf_gov_bills WHERE id = ? LIMIT 1', { billId })
    local stillDue = (fresh and OPEN_GOV[fresh.status]) and cents((tonumber(fresh.amount) or 0) - (tonumber(fresh.amount_paid) or 0)) or 0
    local apply = math.min(take, stillDue)
    local paidOk, newStatus = false, nil
    if apply > 0 then
        local okP, r1, _, r3 = pcall(function() return gov:PayBill(billId, apply, cid) end)
        paidOk, newStatus = okP and r1 == true, r3
    end
    local refund = paidOk and cents(take - apply) or take
    if refund > 0 then
        local back = PFPayout.Transfer({ from = CFG.GovFinesAccount, to = ('player:%s:bank'):format(cid), amount = refund,
            key = key .. ':refund', kind = 'refund', reason = 'Bill #' .. billId .. ' refund', actor = cid })
        if not back.ok then print(('^1[pf-citizen]^7 bill %d: refund of %s to %s failed (%s), key %s:refund'):format(billId, money(refund), cid, tostring(back.error), key)) end
    end
    if not paidOk then return { ok = false, error = 'not_open' } end
    return { ok = true, paid = apply, status = newStatus }
end

--- Pays one bill by key. amount is optional (government bills may be paid in part).
function B.Pay(src, p)
    local key = C.Token(p.key, 40)
    local kind, id = (key or ''):match('^(%a+):(%d+)$')
    id = C.Int(id, 1)
    if not kind or not id then return { ok = false, error = 'bad_request' } end
    local amount
    if p.amount ~= nil then
        amount = tonumber(p.amount)
        if not amount or amount ~= amount or amount <= 0 or amount == math.huge then return { ok = false, error = 'bad_amount' } end
        amount = math.floor(amount * 100) / 100
    end
    if kind == 'gov' then
        if govLocks[id] then return { ok = false, error = 'in_progress' } end
        govLocks[id] = true
        local ok, res = pcall(payGov, src, id, amount)
        govLocks[id] = nil
        if not ok then
            print(('^1[pf-citizen]^7 paying bill %d failed: %s'):format(id, tostring(res)))
            return { ok = false, error = 'server_error' }
        end
        if res.ok then C.Push(C.Cid(src), 'bills', 'changed', { key = key }) end
        return res
    elseif kind == 'phone' then
        if not C.Started('pfm-phone') then return { ok = false, error = 'phone_offline' } end
        local ok, paid, err = pcall(function() return exports['pfm-phone']:PayInvoice(src, id) end)
        if not ok then return { ok = false, error = 'phone_offline' } end
        if paid ~= true then return { ok = false, error = err or 'payment_failed' } end
        C.Push(C.Cid(src), 'bills', 'changed', { key = key })
        return { ok = true }
    end
    return { ok = false, error = 'bad_request' }
end

function B.Decline(src, p)
    local key = C.Token(p.key, 40)
    local id = C.Int((key or ''):match('^phone:(%d+)$'), 1)
    if not id then return { ok = false, error = 'not_declinable' } end
    if not C.Started('pfm-phone') then return { ok = false, error = 'phone_offline' } end
    local ok, done, err = pcall(function() return exports['pfm-phone']:DeclineInvoice(src, id) end)
    if not ok then return { ok = false, error = 'phone_offline' } end
    if done ~= true then return { ok = false, error = err or 'not_declinable' } end
    return { ok = true }
end

--- Records a settled phone invoice (pfm-phone raises pfm-phone:server:invoiceSettled).
function B.RecordSettled(invoice, outcome)
    if type(invoice) ~= 'table' or not C.Int(invoice.id, 1) or type(invoice.citizenid) ~= 'string' then return false end
    outcome = outcome == 'declined' and 'declined' or 'paid'
    local society = tostring(invoice.society or '')
    local title = C.Text(invoice.reason, 150) or ('Invoice from ' .. jobLabel(society))
    MySQL.update.await([[INSERT IGNORE INTO pf_citizen_bill_history (citizenid, source, ref, title, counterparty, amount, outcome)
        VALUES (?, 'phone', ?, ?, ?, ?, ?)]], { invoice.citizenid, tostring(invoice.id), title, C.Cut(jobLabel(society), 100), cents(invoice.amount), outcome })
    C.Push(invoice.citizenid, 'bills', 'changed', { key = 'phone:' .. tostring(invoice.id) })
    return true
end

-- ── new bills: a push to the open Bills app and a mail with the bill attached ──

local marks = { gov = nil, phone = nil }

local function maxId(sql)
    local ok, v = pcall(MySQL.scalar.await, sql)
    return ok and (tonumber(v) or 0) or nil
end

--- Remembers the newest bill ids, so only bills issued after start are announced.
function B.InitWatch()
    marks.gov = C.Started('pf-government') and maxId('SELECT MAX(id) FROM pf_gov_bills') or nil
    marks.phone = maxId('SELECT MAX(id) FROM phone_invoices')
end

local function announce(cid, view, extra)
    C.Push(cid, 'bills', 'new', { key = view.key, title = view.title, amount = view.amount, from = view.from })
    if not CFG.MailNewBills then return end
    C.Mail.Send(cid, {
        sender = view.source == 'phone' and view.from or 'City of Los Santos',
        senderType = view.source == 'phone' and 'business' or 'government',
        subject = ('New bill: %s (%s)'):format(C.Cut(view.title, 70), money(view.remaining > 0 and view.remaining or view.amount)),
        message = ('%s\n\nFrom: %s\nAmount: %s%s\n%s'):format(view.title, view.from, money(view.amount),
            view.due and ('\nDue: ' .. os.date('%Y-%m-%d', view.due)) or '', extra or 'Open the attachment to pay it in the Bills app.'),
        attachments = { { type = 'bill', ref = view.key, title = view.title } },
        ref = 'bill:' .. view.key,
    }, true)
end

function B.Watch()
    if marks.gov == nil and C.Started('pf-government') then marks.gov = maxId('SELECT MAX(id) FROM pf_gov_bills') end
    if marks.gov then
        for _, r in ipairs(govRows('id > ?', { marks.gov })) do
            marks.gov = math.max(marks.gov, tonumber(r.id) or 0)
            local v = govView(r)
            local extra = (not v.open) and 'It was collected from your account when it was issued.' or nil
            if r.target_type == 'citizen' then
                announce(r.target_id, v, extra)
            elseif r.target_type == 'business' then
                for _, cid in ipairs(C.BusinessBosses(r.target_id) or {}) do announce(cid, v, extra) end
            end
        end
    end
    if marks.phone == nil then marks.phone = maxId('SELECT MAX(id) FROM phone_invoices') end
    if marks.phone then
        local ok, rows = pcall(MySQL.query.await, 'SELECT id, citizenid, amount, society, sender, candecline, reason FROM phone_invoices WHERE id > ? ORDER BY id LIMIT 50', { marks.phone })
        for _, r in ipairs(ok and rows or {}) do
            marks.phone = math.max(marks.phone, tonumber(r.id) or 0)
            if type(r.citizenid) == 'string' then announce(r.citizenid, phoneView(r)) end
        end
    end
end

function B.__marks() return marks end
