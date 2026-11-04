-- pf-justice orders of every kind (PF_ARCHITECTURE 4.7.1): jail, prison, remand, fine, citation,
-- restitution, community service, probation and parole. The row in pf_justice_orders is the truth;
-- every change is a compare-and-set on the state it was read in, writes one pf_justice_order_events
-- row and raises 'pf-justice:server:orderChanged'.
--
-- Incarceration chains: a citizen holds at most one 'active' incarceration order. A second one while
-- one is open is created 'pending' and linked by parent_order_id:
--   concurrent  (default) starts counting at once (starts_at set) alongside the active order;
--   consecutive starts counting only when nothing else is running.
-- When the active order ends, a running concurrent order with time left becomes active (one whose
-- time is already served is completed), otherwise the oldest waiting consecutive one. Only when no
-- open incarceration order is left does 'pf-justice:server:releaseOrdered' fire, once.
-- A 'pending' order without a parent waits for prison intake (Config.Prison.Intake = 'transport').
--
-- Money: PayOrder charges the payer with one ledger Transfer keyed pf-justice:order:<id>:pay:<attempt>
-- to society:<account of the order's source> (restitution: the victim's bank). The attempt number is
-- written before the transfer (state payment_pending), so a crash leaves the key on the row and the
-- sweep settles it through exports['pfm-banking']:GetTransaction(key). A clear refusal returns the
-- order to the state it was paid from (pay_from: issued, overdue, referred or upheld; an issued
-- order of the citizen's own becomes a pfm-phone invoice with ref 'pf-justice:order:<id>'); an
-- unclear result stays payment_pending and is never charged again under a new key until it settles.
-- paid_amount is what the ledger moved. While a payment is pending or invoiced the amount is fixed.
-- The phone settles invoices through pfm-phone:server:invoiceSettled; a settlement that finds a lock
-- held or the database failing is queued (memory + 'settle_queued' event), retried and reloaded at
-- Boot, never dropped. An invoiced order is never closed while its invoice is live: a waiver is
-- recorded first (event key pf-justice:order:<id>:waive), then pfm-phone CancelInvoice (15H) is
-- asked to withdraw the invoice by our ref; when it does, the order is waived at once, otherwise the
-- recorded waiver applies when the phone reports the invoice declined/cancelled (waived) or paid
-- (waived, payment refunded).
-- A 'paid' report for an order that no longer waited for that invoice is logged and refunded to the
-- payer under pf-justice:order:<id>:invoice_refund (numbered after a clear refusal; unclear held).
--
-- Locks: every mutation holds 'cid:<citizenid>' (and 'order:<id>' when it starts from an order id)
-- before its first database wait. Functions named *Locked expect the caller to hold the cid lock.

PFJustice = PFJustice or {}
PFJustice.Orders = PFJustice.Orders or {}
local J = PFJustice
local O = J.Orders
local U = J.Util
local S = J.States
local Err = J.Result.Err

local SQL = J.SQL
SQL.insertOrder = [[INSERT INTO pf_justice_orders (citizenid, kind, state, facility, clock, required_seconds, amount, victim_cid,
    units, days, conditions, charges, source_type, source_id, custody_id, parent_order_id, starts_at, due_at, ends_at, last_tick_at,
    idem_key, legacy_ref, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]]
SQL.orderById = 'SELECT * FROM pf_justice_orders WHERE id = ?'
SQL.orderByKey = 'SELECT * FROM pf_justice_orders WHERE idem_key = ?'
SQL.orderByLegacy = 'SELECT * FROM pf_justice_orders WHERE legacy_ref = ?'
SQL.ordersByCid = 'SELECT * FROM pf_justice_orders WHERE citizenid = ? ORDER BY id DESC LIMIT 500'
SQL.openIncarceration = [[SELECT * FROM pf_justice_orders WHERE citizenid = ? AND kind IN ('jail', 'prison', 'remand')
    AND state IN ('pending', 'active', 'suspended') ORDER BY id]]
SQL.activeIndex = [[SELECT id, citizenid, facility FROM pf_justice_orders WHERE kind IN ('jail', 'prison', 'remand') AND state = 'active']]
SQL.setState = 'UPDATE pf_justice_orders SET state = ?, updated_at = ? WHERE id = ? AND state = ?'
SQL.finish = 'UPDATE pf_justice_orders SET state = ?, ends_at = ?, updated_at = ? WHERE id = ? AND state = ?'
SQL.activate = [[UPDATE pf_justice_orders SET state = 'active', starts_at = COALESCE(starts_at, ?), last_tick_at = ?, updated_at = ?
    WHERE id = ? AND state = ?]]
SQL.saveClock = [[UPDATE pf_justice_orders SET served_seconds = ?, last_tick_at = ?, release_at = ?, updated_at = ?
    WHERE id = ? AND state IN ('active', 'pending')]]
SQL.adjust = [[UPDATE pf_justice_orders SET required_seconds = ?, credit_seconds = ?, forfeit_seconds = ?, units = ?, amount = ?, updated_at = ?
    WHERE id = ? AND state = ?]]
SQL.payBegin = [[UPDATE pf_justice_orders SET state = 'payment_pending', pay_attempt = ?, pay_key = ?, pay_from = ?, updated_at = ?
    WHERE id = ? AND state = ? AND pay_attempt = ?]]
-- paid_amount is what the ledger (or the phone invoice) moved, never the order amount read later
SQL.paid = [[UPDATE pf_justice_orders SET state = 'paid', paid_amount = ?, ends_at = ?, updated_at = ? WHERE id = ? AND state = ?]]
SQL.setInvoice = 'UPDATE pf_justice_orders SET state = ?, invoice_id = ?, updated_at = ? WHERE id = ? AND state = ?'
-- any state: a settlement that arrives after the order stopped waiting for its invoice is still ours
SQL.byInvoice = [[SELECT * FROM pf_justice_orders WHERE invoice_id = ? ORDER BY id DESC LIMIT 1]]
-- id > cursor: rows the bank keeps answering 'wait' for never keep the sweep from newer ones
SQL.duePayments = [[SELECT * FROM pf_justice_orders WHERE state = 'payment_pending' AND updated_at <= ? AND id > ? ORDER BY id LIMIT 50]]
SQL.refundBegin = [[UPDATE pf_justice_orders SET refund_state = 'due', refund_attempt = 0, refund_amount = ?, refund_cid = ?,
    refund_society = ?, refund_invoice = ?, updated_at = ? WHERE id = ? AND refund_state IS NULL]]
SQL.refundStep = [[UPDATE pf_justice_orders SET refund_state = ?, refund_attempt = ?, updated_at = ?
    WHERE id = ? AND refund_state = ? AND refund_attempt = ?]]
SQL.dueRefunds = [[SELECT * FROM pf_justice_orders WHERE refund_state IN ('due', 'unclear') AND updated_at <= ? AND id > ? ORDER BY id LIMIT 50]]
-- read only, at a character deletion: pfm-core has just deleted the character's phone invoices
-- except the ones being paid ('paying'), so a row still there is an invoice that will settle
SQL.phoneInvoice = 'SELECT id FROM phone_invoices WHERE id = ? LIMIT 1'
SQL.dueDeadlines = [[SELECT * FROM pf_justice_orders WHERE kind IN ('fine', 'citation', 'restitution', 'community_service')
    AND state IN ('issued', 'upheld', 'assigned', 'active') AND due_at IS NOT NULL AND due_at <= ? ORDER BY id LIMIT 100]]
SQL.dueSupervision = [[SELECT * FROM pf_justice_orders WHERE kind IN ('probation', 'parole') AND state = 'active'
    AND ends_at IS NOT NULL AND ends_at <= ? ORDER BY id LIMIT 100]]
SQL.anonOrders = 'UPDATE pf_justice_orders SET citizenid = ? WHERE citizenid = ?'
SQL.anonVictim = 'UPDATE pf_justice_orders SET victim_cid = ? WHERE victim_cid = ?'
SQL.anonCreatedBy = 'UPDATE pf_justice_orders SET created_by = ? WHERE created_by = ?'
SQL.anonRefundCid = 'UPDATE pf_justice_orders SET refund_cid = ? WHERE refund_cid = ?'
SQL.anonEventActor = 'UPDATE pf_justice_order_events SET actor_cid = ? WHERE actor_cid = ?'
-- the id inside event details (a payer, a requester): the JSON string "<cid>" becomes "<token>"
SQL.anonEventDetail = 'UPDATE pf_justice_order_events SET detail = REPLACE(detail, ?, ?) WHERE detail LIKE ?'
SQL.anonAuditActor = 'UPDATE pf_justice_audit SET actor_cid = ? WHERE actor_cid = ?'
SQL.anonAuditEntity = "UPDATE pf_justice_audit SET entity_id = ? WHERE entity = 'record' AND entity_id = ?"
SQL.anonAuditDetail = 'UPDATE pf_justice_audit SET detail = REPLACE(detail, ?, ?) WHERE detail LIKE ?'
SQL.insertEvent = [[INSERT INTO pf_justice_order_events (order_id, action, detail, actor_cid, actor_kind, actor_resource, idem_key, at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)]]
SQL.eventByKey = 'SELECT * FROM pf_justice_order_events WHERE idem_key = ?'
SQL.deleteEventByKey = 'DELETE FROM pf_justice_order_events WHERE idem_key = ?'
SQL.countEvents = 'SELECT COUNT(*) FROM pf_justice_order_events WHERE order_id = ? AND action = ?'
SQL.insertCitation = [[INSERT INTO pf_justice_citations (order_id, uid, violation, plate, speed_kmh, limit_kmh, x, y, officer_cid, contest_until, at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]]
SQL.citationByOrder = 'SELECT * FROM pf_justice_citations WHERE order_id = ? LIMIT 1'
SQL.anonOfficer = 'UPDATE pf_justice_citations SET officer_cid = ? WHERE officer_cid = ?'

local NUMERIC = { 'id', 'required_seconds', 'served_seconds', 'credit_seconds', 'forfeit_seconds', 'last_tick_at', 'release_at',
    'amount', 'paid_amount', 'pay_attempt', 'invoice_id', 'units', 'units_done', 'days', 'custody_id', 'parent_order_id',
    'starts_at', 'due_at', 'ends_at', 'created_at', 'updated_at', 'refund_attempt', 'refund_amount', 'refund_invoice' }
local ZERO = { served_seconds = true, credit_seconds = true, forfeit_seconds = true, paid_amount = true, pay_attempt = true, units_done = true,
    refund_attempt = true }

O.activeIndex = O.activeIndex or {} -- [cid] = { orderId, facility }: active incarceration orders (online or not)

-- ── rows ────────────────────────────────────────────────────────────────────────────────────────

--- A database row with its numeric columns as numbers.
function O.Norm(row)
    if type(row) ~= 'table' then return nil end
    local r = {}
    for k, v in pairs(row) do r[k] = v end
    for _, k in ipairs(NUMERIC) do
        local n = tonumber(row[k])
        if n == nil and ZERO[k] then n = 0 end
        r[k] = n
    end
    return r
end

local function one(sql, params)
    local ok, row = pcall(MySQL.single.await, sql, params)
    if not ok then return nil, false end
    if type(row) == 'table' and row[1] ~= nil and row.id == nil then row = row[1] end
    return O.Norm(row), true
end

local function many(sql, params)
    local ok, rows = pcall(MySQL.query.await, sql, params)
    if not ok or type(rows) ~= 'table' then return nil end
    local out = {}
    for i, r in ipairs(rows) do out[i] = O.Norm(r) end
    return out
end
O.Many = many

local function update(sql, params)
    local ok, res = pcall(MySQL.update.await, sql, params)
    return ok and U.Affected(res) or 0
end

function O.Row(id) return (one(SQL.orderById, { id })) end
function O.OpenIncarceration(cid) return many(SQL.openIncarceration, { cid }) end

--- Seconds still to serve on an incarceration order (nil for an order without a fixed time).
function O.Remaining(r)
    if not r or r.required_seconds == nil then return nil end
    local rem = r.required_seconds - (r.served_seconds or 0) - (r.credit_seconds or 0) + (r.forfeit_seconds or 0)
    return rem > 0 and rem or 0
end

--- Seconds until the whole incarceration chain of these rows is served (architecture 4.7.2):
--- the longest running order plus every order still waiting to start.
function O.TimeToRelease(rows)
    local running, waiting = 0, 0
    for _, r in ipairs(rows or {}) do
        local rem = O.Remaining(r) or 0
        if r.state == 'active' or (r.state == 'pending' and r.starts_at) then
            if rem > running then running = rem end
        elseif r.state == 'pending' then
            waiting = waiting + rem
        end
    end
    return running + waiting
end

--- The order as other code sees it (camelCase, decoded JSON, remaining time).
function O.Public(r)
    if not r then return nil end
    return {
        id = r.id, cid = r.citizenid, kind = r.kind, state = r.state, facility = r.facility, clock = r.clock,
        requiredSeconds = r.required_seconds, servedSeconds = r.served_seconds, creditSeconds = r.credit_seconds,
        forfeitSeconds = r.forfeit_seconds, remainingSeconds = O.Remaining(r), lastTickAt = r.last_tick_at,
        releaseAt = r.release_at, amount = r.amount, paidAmount = r.paid_amount, payAttempt = r.pay_attempt,
        invoiceId = r.invoice_id, victimCid = r.victim_cid, units = r.units, unitsDone = r.units_done, days = r.days,
        conditions = U.Decode(r.conditions), charges = U.Decode(r.charges),
        sourceRef = r.source_type and { type = r.source_type, id = r.source_id } or nil,
        custodyId = r.custody_id, parentOrderId = r.parent_order_id, startsAt = r.starts_at, dueAt = r.due_at,
        endsAt = r.ends_at, legacyRef = r.legacy_ref, createdBy = r.created_by, createdAt = r.created_at, updatedAt = r.updated_at,
        refundState = r.refund_state, refundAmount = r.refund_amount,
    }
end

-- ── events, index, locks ────────────────────────────────────────────────────────────────────────

--- One pf_justice_order_events row. Returns true; or false, 'duplicate' when `key` was used before.
function O.Event(orderId, action, detail, actor, key)
    local ok, err = pcall(MySQL.insert.await, SQL.insertEvent, {
        orderId, tostring(action):sub(1, 20), J.Audit.Detail(detail), actor and J.Actor.Tag(actor) or nil,
        actor and actor.kind and actor.kind:sub(1, 8) or nil, actor and actor.resource and actor.resource:sub(1, 48) or nil,
        key, os.time(),
    })
    if ok then return true end
    if key and tostring(err):lower():find('duplicate', 1, true) then return false, 'duplicate' end
    print(('^1[pf-justice]^7 order %s event %s not written: %s'):format(tostring(orderId), tostring(action), tostring(err)))
    return false, 'db'
end

local function changed(r, change)
    J.Emit('orderChanged', O.Public(r), change)
end

--- Rebuilds the active-incarceration index entry of a citizen from their open rows.
function O.Reindex(cid, rows)
    O.activeIndex[cid] = nil
    for _, r in ipairs(rows or {}) do
        if r.state == 'active' then O.activeIndex[cid] = { orderId = r.id, facility = r.facility } end
    end
end

function O.LoadIndex()
    local rows = many(SQL.activeIndex, {})
    if not rows then return false end
    O.activeIndex = {}
    for _, r in ipairs(rows) do O.activeIndex[r.citizenid] = { orderId = r.id, facility = r.facility } end
    return true
end

--- Creates the society accounts fines and bail are paid to (only for known jobs; never throws).
function O.EnsureAccounts()
    if GetResourceState('pfm-banking') ~= 'started' then return end
    local seen = {}
    local names = { Config.Fines.DefaultAccount, Config.Bail and Config.Bail.Account }
    for _, v in pairs(Config.Fines.Accounts or {}) do names[#names + 1] = v end
    for _, name in pairs(names) do
        if type(name) == 'string' and not seen[name] then
            seen[name] = true
            pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(name) end)
        end
    end
end

--- Runs fn with the citizen lock held (busy when another action on them is running).
function O.WithCid(cid, fn)
    return J.Locks.With('cid:' .. cid, fn)
end

--- Runs fn(row) with the order lock and its citizen's lock held (the row is read under both).
function O.WithOrder(orderId, fn)
    return J.Locks.With('order:' .. orderId, function()
        local row = O.Row(orderId)
        if not row then return Err('not_found', 'No such order') end
        return O.WithCid(row.citizenid, function()
            row = O.Row(orderId) or row
            return fn(row)
        end)
    end)
end

-- ── validation per kind ─────────────────────────────────────────────────────────────────────────

local SOURCE_TYPES = { mdt_sentence = true, court_decision = true, citation = true, field = true, admin = true, legacy = true }

local function validCharges(list)
    if list == nil then return true, nil end
    if type(list) ~= 'table' or #list > 50 then return false end
    local out = {}
    for i, c in ipairs(list) do
        if type(c) ~= 'table' then return false end
        local code, label = U.Str(c.code, 24), U.Str(c.label, 100)
        if not code and not label then return false end
        out[i] = { code = code, label = label, count = U.Int(c.count or 1, 1, 99) or 1 }
    end
    local s = U.Encode(out)
    if not s or #s > 16000 then return false end
    return true, s
end

local function validConditions(list)
    if list == nil then return true, nil end
    if type(list) ~= 'table' or #list > 20 then return false end
    local out = {}
    for i, c in ipairs(list) do
        if type(c) ~= 'table' or not (Config.Supervision.ConditionKinds or {})[c.kind] then return false end
        local copy = {}
        for k, v in pairs(c) do
            if type(k) ~= 'string' or #k > 24 then return false end
            local t = type(v)
            if t == 'string' then copy[k] = U.Str(v, 64)
            elseif t == 'number' then if v ~= v or v == math.huge or v == -math.huge then return false end copy[k] = v
            elseif t == 'boolean' then copy[k] = v
            elseif t == 'table' and (k == 'zone' or k == 'center') then
                local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
                if not x or not y then return false end
                copy[k] = { x = x, y = y, z = z, radius = tonumber(v.radius) }
            else return false end
        end
        out[i] = copy
    end
    local s = U.Encode(out)
    if not s or #s > 4096 then return false end
    return true, s
end

--- Normalises a CreateOrder spec. Returns n (validated fields) or nil, err.
function O.Validate(spec, invoker)
    if type(spec) ~= 'table' then return nil, Err('bad_args', 'spec must be a table') end
    local now = os.time()
    local n = { kind = spec.kind }
    if not U.ValidCid(spec.cid) then return nil, Err('bad_args', 'cid is missing or invalid') end
    n.cid = spec.cid
    if not S.Kinds[n.kind] then return nil, Err('bad_args', 'unknown order kind') end

    local okCharges, charges = validCharges(spec.charges)
    if not okCharges then return nil, Err('bad_args', 'charges are invalid') end
    n.charges = charges
    if spec.sourceRef ~= nil then
        local sr = spec.sourceRef
        if type(sr) ~= 'table' or not SOURCE_TYPES[sr.type] then return nil, Err('bad_args', 'sourceRef.type is invalid') end
        n.sourceType, n.sourceId = sr.type, U.Str(sr.id, 64)
    end
    if spec.custodyId ~= nil then
        n.custodyId = U.Int(spec.custodyId, 1, 2147483647)
        if not n.custodyId then return nil, Err('bad_args', 'custodyId is invalid') end
    end

    local policy = Config.Clock.Policy[n.kind]
    if spec.clock ~= nil and spec.clock ~= policy then
        if spec.clock ~= 'online' and spec.clock ~= 'hybrid' and spec.clock ~= 'realtime' then
            return nil, Err('bad_args', 'clock must be online, hybrid or realtime')
        end
        local internal = invoker == nil or invoker == J.RESOURCE
        if not internal and not (Config.Clock.OverrideCallers or {})[invoker] then
            return nil, Err('no_permission', 'The clock policy of this order kind is fixed')
        end
    end

    if S.IncarcerationKinds[n.kind] then
        if spec.minutes ~= nil or n.kind ~= 'remand' then
            local minutes = U.Int(spec.minutes, 1, Config.MaxMinutes)
            if not minutes then return nil, Err('bad_args', ('minutes must be 1..%d'):format(Config.MaxMinutes)) end
            n.required = minutes * 60
        end
        n.facility = spec.facility or Config.DefaultFacility[n.kind]
        local fac = Config.Facilities[n.facility or '']
        if type(n.facility) ~= 'string' or not fac or (fac.kinds and not fac.kinds[n.kind]) then
            return nil, Err('bad_args', 'unknown facility for this order kind')
        end
        n.clock = spec.clock or policy or 'online'
        n.merge = spec.merge or 'concurrent'
        if n.merge ~= 'concurrent' and n.merge ~= 'consecutive' then return nil, Err('bad_args', 'merge must be concurrent or consecutive') end
    elseif S.MoneyKinds[n.kind] then
        n.amount = U.Int(spec.amount, 1, Config.Fines.MaxAmount)
        if not n.amount then return nil, Err('bad_args', 'amount is invalid') end
        if spec.dueAt ~= nil then
            n.dueAt = U.Int(spec.dueAt, now + 60, now + 366 * 86400)
            if not n.dueAt then return nil, Err('bad_args', 'dueAt must be in the future') end
        else
            n.dueAt = now + Config.Fines.DueDays * 86400
        end
        if n.kind == 'restitution' then
            if not U.ValidCid(spec.victimCid) or spec.victimCid == n.cid then return nil, Err('bad_args', 'victimCid is invalid') end
            n.victimCid = spec.victimCid
        end
    elseif n.kind == 'community_service' then
        n.units = U.Int(spec.units, 1, Config.CommunityService.MaxUnits)
        if not n.units then return nil, Err('bad_args', 'units are invalid') end
        if spec.dueAt ~= nil then
            n.dueAt = U.Int(spec.dueAt, now + 3600, now + 366 * 86400)
            if not n.dueAt then return nil, Err('bad_args', 'dueAt must be at least an hour ahead') end
        else
            n.dueAt = now + Config.CommunityService.DefaultDays * 86400
        end
        n.clock = policy or 'realtime'
    elseif S.SupervisionKinds[n.kind] then
        n.days = U.Int(spec.days, 1, Config.Supervision.MaxDays)
        if not n.days then return nil, Err('bad_args', 'days are invalid') end
        local okCond, cond = validConditions(spec.conditions)
        if not okCond then return nil, Err('bad_args', 'conditions are invalid') end
        n.conditions = cond
        n.clock = policy or 'realtime'
    end
    return n
end

-- The arguments a repeated key must match (a citation's uid is generated, so it is not compared).
local function sameOrder(row, n)
    local function eq(a, b) return tostring(a) == tostring(b) end
    if row.citizenid ~= n.cid or row.kind ~= n.kind then return false end
    if not eq(row.required_seconds, n.required) or not eq(row.amount, n.amount) or not eq(row.units, n.units)
        or not eq(row.days, n.days) or not eq(row.victim_cid, n.victimCid) then return false end
    if S.IncarcerationKinds[n.kind] and row.facility ~= n.facility then return false end
    if not eq(row.source_type, n.sourceType) then return false end
    if n.kind ~= 'citation' and not eq(row.source_id, n.sourceId) then return false end
    return true
end

-- ── create ──────────────────────────────────────────────────────────────────────────────────────

local function duplicateOf(row, n)
    if not sameOrder(row, n) then return Err('key_reused', 'This key was used for a different order') end
    return { ok = true, duplicate = true, orderId = row.id, state = row.state }
end

--- CreateOrder (architecture 4.7.1). ctx = { invoker } from the export boundary.
--- opts = { key, actor, legacyRef (pf-justice only) }.
function O.Create(spec, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local invoker = ctx.invoker
    local internal = invoker == nil or invoker == J.RESOURCE
    local n, verr = O.Validate(spec, invoker)
    if not n then return verr end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    if key == nil and not internal then return Err('bad_args', 'opts.key is required') end
    local legacyRef = internal and U.Str(opts.legacyRef, 64) or nil
    local actor, aerr = J.Actor.Resolve(opts.actor, invoker)
    if not actor then return aerr end
    -- like its other write exports: the admin menu acts only for an admin standing behind it
    if invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end

    return O.WithCid(n.cid, function()
        if key then
            local row, okq = one(SQL.orderByKey, { key })
            if not okq then return Err('db_unavailable', 'The justice database did not answer') end
            if row then return duplicateOf(row, n) end
        end
        if legacyRef then
            local row = one(SQL.orderByLegacy, { legacyRef })
            if row then return { ok = true, duplicate = true, orderId = row.id, state = row.state } end
        end

        local now = os.time()
        local state, parent, startsAt, endsAt, existing
        if S.IncarcerationKinds[n.kind] then
            local open = O.OpenIncarceration(n.cid)
            if not open then return Err('db_unavailable', 'The justice database did not answer') end
            if #open > 0 then
                local head = open[1]
                for _, r in ipairs(open) do if r.state == 'active' then head = r end end
                existing = head.id
                state = 'pending'
                if n.merge == 'consecutive' then
                    parent = open[#open].id
                else
                    parent, startsAt = head.id, now
                end
            elseif Config.Prison.Intake == 'transport' and n.kind == 'prison' then
                state = 'pending'
            else
                state, startsAt = 'active', now
            end
        elseif S.SupervisionKinds[n.kind] then
            state, startsAt, endsAt = 'active', now, now + n.days * 86400
        elseif n.kind == 'community_service' then
            state = 'assigned'
        else
            state = 'issued'
        end
        local okState, serr = S.Check(n.kind, nil, state)
        if not okState then return serr end

        local okIns, id = pcall(MySQL.insert.await, SQL.insertOrder, {
            n.cid, n.kind, state, n.facility, n.clock, n.required, n.amount, n.victimCid,
            n.units, n.days, n.conditions, n.charges, n.sourceType, n.sourceId, n.custodyId, parent, startsAt, n.dueAt, endsAt,
            S.IncarcerationKinds[n.kind] and now or nil, key, legacyRef, J.Actor.Tag(actor), now, now,
        })
        id = okIns and tonumber(id) or nil
        if not id or id < 1 then
            -- another server (or a retry racing this one) may have written the key first
            if key then
                local row = one(SQL.orderByKey, { key })
                if row then return duplicateOf(row, n) end
            end
            return Err('db_unavailable', 'The order could not be stored; nothing was changed')
        end

        O.Event(id, 'created', { kind = n.kind, state = state, merge = parent and n.merge or nil, parent = parent,
            minutes = n.required and n.required / 60 or nil, amount = n.amount, units = n.units, days = n.days }, actor)
        local row = O.Row(id) or O.Norm({ id = id, citizenid = n.cid, kind = n.kind, state = state, facility = n.facility, clock = n.clock,
            required_seconds = n.required, amount = n.amount, units = n.units, days = n.days, created_at = now, updated_at = now })
        if S.IncarcerationKinds[n.kind] then
            O.Reindex(n.cid, O.OpenIncarceration(n.cid))
            if J.Clock then J.Clock.Refresh(n.cid) end
        end
        J.Emit('orderCreated', O.Public(row))
        return { ok = true, orderId = id, state = state, existing = existing }
    end)
end

-- ── state changes ───────────────────────────────────────────────────────────────────────────────

--- Moves row to a terminal or other plain state (CAS). Writes the event, emits orderChanged and
--- writes the record entry. Returns true or false, err. Caller holds the cid lock.
function O.MoveLocked(row, to, why, actor, extra)
    local okState, serr = S.Check(row.kind, row.state, to)
    if not okState then return false, serr end
    -- a live phone invoice can still be paid (candecline = 0 and pfm-phone has no cancel export):
    -- the order may only close once the invoice settled or was cancelled (extra.invoice_gone)
    if row.state == 'invoiced' and (to == 'waived' or to == 'vacated') and not (type(extra) == 'table' and extra.invoice_gone) then
        return false, Err('conflict', 'This order is a phone invoice the citizen can still pay')
    end
    local now = os.time()
    local from = row.state
    local n
    if S.IsTerminal(row.kind, to) and to ~= 'paid' then
        n = update(SQL.finish, { to, now, now, row.id, from })
        if n == 1 then row.ends_at = now end
    elseif to == 'active' then
        n = update(SQL.activate, { now, now, now, row.id, from })
        if n == 1 then row.starts_at = row.starts_at or now row.last_tick_at = now end
    else
        n = update(SQL.setState, { to, now, row.id, from })
    end
    if n ~= 1 then return false, Err('busy', 'The order changed meanwhile; try again') end
    row.state, row.updated_at = to, now
    local detail = { from = from, to = to, reason = why }
    if type(extra) == 'table' then for k, v in pairs(extra) do detail[k] = v end end
    O.Event(row.id, to == 'active' and 'activated' or to, detail, actor)
    changed(row, { action = 'state', from = from, to = to, reason = why })
    if J.Records and J.Records.OnOrderEnded then J.Records.OnOrderEnded(row, to) end
    return true
end

--- After an incarceration order of `cid` ended: completes / promotes the rest of the chain and
--- fires releaseOrdered once when nothing open is left. Caller holds the cid lock.
--- Returns 'released', 'running' or 'held' (suspended / waiting for intake).
function O.SettleLocked(cid, lastId, reason, actor)
    for _ = 1, 50 do
        local open = O.OpenIncarceration(cid)
        if not open then return 'running' end
        if #open == 0 then
            O.activeIndex[cid] = nil
            if J.Clock then J.Clock.Refresh(cid) end
            J.Emit('releaseOrdered', cid, lastId, reason)
            return 'released'
        end
        local active, started, waiting, held
        for _, r in ipairs(open) do
            if r.state == 'active' then active = r
            elseif r.state == 'suspended' then held = true
            elseif r.state == 'pending' and r.parent_order_id then
                if r.starts_at then started = started or {} started[#started + 1] = r
                else waiting = waiting or r end
            end
        end
        if active then
            local rem = O.Remaining(active)
            -- an order whose time is served completes; a player who is offline finishes at the next load
            if rem ~= nil and rem <= 0 and J.Clock and J.Clock.IsOnline(cid) then
                if not O.MoveLocked(active, 'completed', 'served', actor) then break end
                lastId, reason = active.id, 'completed'
            else
                O.Reindex(cid, open)
                if J.Clock then J.Clock.Refresh(cid) end
                return 'running'
            end
        elseif held then
            O.Reindex(cid, open)
            if J.Clock then J.Clock.Refresh(cid) end
            return 'held'
        else
            local best
            for _, r in ipairs(started or {}) do
                local rem = O.Remaining(r) or math.huge
                if not best or rem > (O.Remaining(best) or math.huge) then best = r end
            end
            best = best or waiting
            if not best then
                -- only orders waiting for intake are left
                O.Reindex(cid, open)
                if J.Clock then J.Clock.Refresh(cid) end
                return 'held'
            end
            if not O.MoveLocked(best, 'active', 'next in chain', actor, { after = lastId }) then break end
        end
    end
    O.Reindex(cid, O.OpenIncarceration(cid))
    if J.Clock then J.Clock.Refresh(cid) end
    return 'running'
end

-- ── waivers of invoiced orders ──────────────────────────────────────────────────────────────────

function O.WaiveKey(id) return ('pf-justice:order:%d:waive'):format(id) end

--- The waiver recorded for an invoiced order (detail of its keyed 'waive_pending' event), or nil.
--- Second value: false when the database could not be read.
function O.PendingWaiver(orderId)
    local ev, okq = one(SQL.eventByKey, { O.WaiveKey(orderId) })
    if not ev then return nil, okq end
    return U.Decode(ev.detail) or {}, true
end

--- Records that `to` (waived / vacated) was asked for while the order is a live phone invoice. It is
--- applied when pfm-phone reports the invoice settled or declined (OnInvoiceSettled): declined ->
--- the order is waived; paid -> waived and the payment refunded. The first request is kept.
--- Returns true when a waiver is on record.
function O.RequestWaiverLocked(row, to, why, actor)
    local ok, err = O.Event(row.id, 'waive_pending', { to = to, reason = why, by = J.Actor.Tag(actor), invoice = row.invoice_id },
        actor, O.WaiveKey(row.id))
    return ok or err == 'duplicate'
end

local function waiverRefusal(row)
    return { ok = false, error = 'conflict', state = row.state, waiverPending = true, invoiceId = row.invoice_id,
        message = 'This order is a phone invoice the citizen can still pay. The waiver is recorded: it applies when the invoice'
            .. ' is settled or cancelled, and a payment made on the invoice is refunded.' }
end

--- Asks pfm-phone (CancelInvoice, batch 15H) to withdraw the order's invoice, by our ref only (a
--- phone invoice id can be reused). True only when the invoice is gone now; false when the export
--- is missing or refuses (being paid: 'busy'; already charged: 'invalid_state', it is then
--- finished as paid and reported) - the recorded waiver then applies when the phone reports it.
local function cancelInvoice(row, why)
    if GetResourceState('pfm-phone') ~= 'started' then return false end
    local ok, res = pcall(function()
        return exports['pfm-phone']:CancelInvoice(O.InvoiceRef(row.id), { citizenid = row.citizenid, reason = why })
    end)
    return ok and type(res) == 'table' and res.ok == true
end

local DEFAULT_TARGETS = { completed = true, vacated = true, revoked = true, waived = true }

--- SetOrderState (architecture 4.7.1).
function O.SetState(orderId, to, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local invoker = ctx.invoker
    local internal = invoker == nil or invoker == J.RESOURCE
    local id = U.Int(orderId, 1, 2147483647)
    if not id or type(to) ~= 'string' then return Err('bad_args', 'orderId and a target state are required') end
    if not internal then
        local allowed = (Config.SetStateTargets or {})[invoker] or DEFAULT_TARGETS
        if not allowed[to] then return Err('no_permission', 'This resource may not set ' .. to) end
    end
    local actor, aerr = J.Actor.Resolve(opts.actor, invoker)
    if not actor then return aerr end
    if invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    local why = U.Str(opts.reason, 200)

    return O.WithOrder(id, function(row)
        if row.state == to then return { ok = true, duplicate = true, order = O.Public(row) } end
        if to == 'active' and row.state == 'pending' and row.parent_order_id then
            return Err('invalid_state', 'This order waits for the order before it')
        end
        if row.state == 'invoiced' and (to == 'waived' or to == 'vacated') and S.Can(row.kind, row.state, to) then
            -- recorded first: whatever the phone answers, the settlement it reports applies the waiver
            if not O.RequestWaiverLocked(row, to, why, actor) then
                return Err('db_unavailable', 'The waiver could not be recorded; nothing was changed')
            end
            if not cancelInvoice(row, why) then return waiverRefusal(row) end
            local ok, err = O.MoveLocked(row, to, why, actor, { invoice = row.invoice_id, invoice_gone = true, cancelled = true })
            if not ok then return err end
            return { ok = true, order = O.Public(O.Row(id) or row), invoiceCancelled = true }
        end
        local ok, err = O.MoveLocked(row, to, why, actor)
        if not ok then return err end
        if S.IncarcerationKinds[row.kind] then
            if S.IsTerminal(row.kind, to) then O.SettleLocked(row.citizenid, row.id, why or to, actor)
            else
                O.Reindex(row.citizenid, O.OpenIncarceration(row.citizenid))
                if J.Clock then J.Clock.Refresh(row.citizenid) end
            end
        end
        return { ok = true, order = O.Public(O.Row(id) or row) }
    end)
end

--- ReleaseNow: vacates every open incarceration order of the citizen; releaseOrdered fires once.
function O.ReleaseNow(who, reason, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local cid = J.Who(who)
    if not cid then return Err('bad_args', 'Unknown player or citizen id') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    local why = U.Str(reason, 200) or 'released'
    return O.WithCid(cid, function()
        local open = O.OpenIncarceration(cid)
        if not open then return Err('db_unavailable', 'The justice database did not answer') end
        if #open == 0 then return { ok = true, released = 0 } end
        local released, lastId = 0, nil
        -- waiting orders first, so nothing is promoted while the active one is vacated
        table.sort(open, function(a, b)
            if (a.state == 'active') ~= (b.state == 'active') then return b.state == 'active' end
            return a.id < b.id
        end)
        for _, r in ipairs(open) do
            if O.MoveLocked(r, 'vacated', why, actor) then released, lastId = released + 1, r.id end
        end
        if released > 0 then O.SettleLocked(cid, lastId, why, actor) end
        return { ok = true, released = released }
    end)
end

-- ── adjustments ─────────────────────────────────────────────────────────────────────────────────

local ADJUST = { credit = true, forfeit = true, modify = true, suspend = true, resume = true }

--- AdjustOrder (architecture 4.7.1). change = { kind, seconds?, units?, amount?, reason }; opts = { key, actor }.
function O.Adjust(orderId, change, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local invoker = ctx.invoker
    local internal = invoker == nil or invoker == J.RESOURCE
    local id = U.Int(orderId, 1, 2147483647)
    if not id or type(change) ~= 'table' or not ADJUST[change.kind] then return Err('bad_args', 'orderId and change.kind are required') end
    local kind = change.kind
    if not internal and not ((Config.AdjustKinds or {})[invoker] or {})[kind] then
        return Err('no_permission', 'This resource may not ' .. kind .. ' orders')
    end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    if key == nil and not internal and (kind == 'credit' or kind == 'forfeit') then return Err('bad_args', 'opts.key is required') end
    local actor, aerr = J.Actor.Resolve(opts.actor, invoker)
    if not actor then return aerr end
    if invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    local capped = not internal and actor.kind ~= 'admin'
    local maxSeconds = capped and Config.Credits.MaxSecondsPerCall or Config.MaxMinutes * 60
    local seconds = change.seconds ~= nil and U.Int(change.seconds, 1, maxSeconds) or nil
    local why = U.Str(change.reason, 200)

    return O.WithOrder(id, function(row)
        if key then
            local ev = one(SQL.eventByKey, { key })
            if ev then
                local d = U.Decode(ev.detail) or {}
                if tonumber(ev.order_id) ~= id or ev.action ~= ('adjust_' .. kind):sub(1, 20) or tostring(d.seconds) ~= tostring(seconds) then
                    return Err('key_reused', 'This key was used for a different change')
                end
                return { ok = true, duplicate = true, order = O.Public(row), applied = d.applied }
            end
        end
        local incarceration = S.IncarcerationKinds[row.kind]
        local required, credit, forfeit = row.required_seconds, row.credit_seconds, row.forfeit_seconds
        local units, amount = row.units, row.amount
        local applied

        if kind == 'suspend' or kind == 'resume' then
            local to = kind == 'suspend' and 'suspended' or 'active'
            if kind == 'resume' and row.state ~= 'suspended' then return Err('invalid_state', 'The order is ' .. row.state) end
            local okState, serr = S.Check(row.kind, row.state, to)
            if not okState then return serr end
            if key then
                local okEv, evErr = O.Event(id, 'adjust_' .. kind, { kind = kind, reason = why }, actor, key)
                if evErr == 'duplicate' then return { ok = true, duplicate = true, order = O.Public(row) } end
                -- without its key on record a retry could not be told from a new change
                if not okEv then return Err('db_unavailable', 'The change could not be recorded; nothing was changed') end
            end
            local ok, err = O.MoveLocked(row, to, why, actor, { adjust = kind })
            if not ok then
                if key then update(SQL.deleteEventByKey, { key }) end
                return err
            end
            if incarceration then
                O.Reindex(row.citizenid, O.OpenIncarceration(row.citizenid))
                if J.Clock then J.Clock.Refresh(row.citizenid) end
            end
            return { ok = true, order = O.Public(O.Row(id) or row) }
        end

        if not S.IsOpen(row.kind, row.state) then return Err('invalid_state', 'The order is ' .. row.state) end
        -- the amount is being charged (or sits on the citizen's phone): changing it now would record
        -- a paid amount the ledger never moved
        if kind == 'modify' and (row.state == 'payment_pending' or row.state == 'invoiced') then
            return Err('conflict', 'A payment of this order is in progress (' .. row.state .. '); change it after it settles')
        end
        if kind == 'credit' or kind == 'forfeit' then
            if not incarceration or required == nil then return Err('bad_args', 'Only timed incarceration orders take credits') end
            if not seconds then return Err('bad_args', ('seconds must be 1..%d'):format(maxSeconds)) end
            if kind == 'credit' then
                local room = capped and math.max(0, math.floor(required * Config.Credits.MaxShare) - credit) or seconds
                applied = math.min(seconds, room)
                credit = credit + applied
            else
                -- pfm-prison may only take back credits it gave; admins and courts may add time
                local room = capped and math.max(0, credit - forfeit) or seconds
                applied = math.min(seconds, room)
                forfeit = forfeit + applied
            end
        else -- modify
            if change.seconds ~= nil then
                if not incarceration then return Err('bad_args', 'Only incarceration orders have a time') end
                local s = U.Int(change.seconds, 60, Config.MaxMinutes * 60)
                if not s then return Err('bad_args', 'seconds are invalid') end
                required = s
            end
            if change.units ~= nil then
                local u = U.Int(change.units, math.max(1, row.units_done or 0), Config.CommunityService.MaxUnits)
                if row.kind ~= 'community_service' or not u then return Err('bad_args', 'units are invalid') end
                units = u
            end
            if change.amount ~= nil then
                local a = U.Int(change.amount, math.max(1, row.paid_amount or 0), Config.Fines.MaxAmount)
                if not S.MoneyKinds[row.kind] or not a then return Err('bad_args', 'amount is invalid') end
                amount = a
            end
            applied = true
        end

        -- the event (with the key) is written first: a retry after a crash is a duplicate, never a second credit
        local okEv, evErr = O.Event(id, 'adjust_' .. kind, { kind = kind, seconds = seconds, units = units, amount = amount,
            applied = applied, reason = why }, actor, key)
        if not okEv and evErr == 'duplicate' then return { ok = true, duplicate = true, order = O.Public(row) } end
        -- a keyed change whose key could not be stored is not applied: the retry would apply it twice
        if not okEv and key then return Err('db_unavailable', 'The change could not be recorded; nothing was changed') end
        local n = update(SQL.adjust, { required, credit, forfeit, units, amount, os.time(), id, row.state })
        if n ~= 1 then
            if key then update(SQL.deleteEventByKey, { key }) end
            return Err('busy', 'The order changed meanwhile; try again')
        end
        row.required_seconds, row.credit_seconds, row.forfeit_seconds, row.units, row.amount = required, credit, forfeit, units, amount
        changed(row, { action = kind, seconds = seconds, applied = applied, reason = why })
        if incarceration then
            if J.Clock then J.Clock.Refresh(row.citizenid) end
            if row.state == 'active' and (O.Remaining(row) or 1) <= 0 then O.SettleLocked(row.citizenid, row.id, 'served', actor) end
        end
        return { ok = true, order = O.Public(O.Row(id) or row), applied = applied }
    end)
end

-- ── reads ───────────────────────────────────────────────────────────────────────────────────────

function O.Get(orderId)
    local id = U.Int(orderId, 1, 2147483647)
    if not id then return Err('bad_args', 'orderId is invalid') end
    local row, okq = one(SQL.orderById, { id })
    if not okq then return Err('db_unavailable', 'The justice database did not answer') end
    if not row then return Err('not_found', 'No such order') end
    return { ok = true, order = O.Public(row) }
end

--- filter = { kinds = { ... }?, states = { ... }?, limit <= 100 }
function O.List(cid, filter)
    if not U.ValidCid(cid) then return Err('bad_args', 'cid is invalid') end
    filter = type(filter) == 'table' and filter or {}
    local limit = U.Int(filter.limit or 50, 1, 100)
    if not limit then return Err('bad_args', 'limit must be 1..100') end
    local function asSet(list)
        if list == nil then return nil end
        if type(list) ~= 'table' then return false end
        local out = {}
        for _, v in ipairs(list) do if type(v) == 'string' then out[v] = true end end
        return out
    end
    local kinds, states = asSet(filter.kinds), asSet(filter.states)
    if kinds == false or states == false then return Err('bad_args', 'kinds and states must be lists') end
    local rows = many(SQL.ordersByCid, { cid })
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local list = {}
    for _, r in ipairs(rows) do
        if (not kinds or kinds[r.kind]) and (not states or states[r.state]) then
            list[#list + 1] = O.Public(r)
            if #list >= limit then break end
        end
    end
    return { ok = true, list = list }
end

--- The open incarceration rows of `cid` (memory for an online inmate, else the database).
function O.IncarcerationRows(cid)
    local rows = J.Clock and J.Clock.Rows(cid)
    if rows then return rows end
    return O.OpenIncarceration(cid)
end

function O.GetActiveIncarceration(who)
    local cid = J.Who(who)
    if not cid then return Err('bad_args', 'Unknown player or citizen id') end
    local rows = O.IncarcerationRows(cid)
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local head
    for _, r in ipairs(rows) do if r.state == 'active' then head = r end end
    if not head then
        for _, r in ipairs(rows) do if r.state == 'suspended' or r.state == 'pending' then head = head or r end end
    end
    if not head then return { ok = true, remainingSeconds = 0 } end
    return { ok = true, order = O.Public(head), remainingSeconds = O.TimeToRelease(rows), facility = head.facility }
end

--- bool, orderId, facility (memory only).
function O.IsIncarcerated(who)
    local cid = J.Who(who)
    local idx = cid and O.activeIndex[cid]
    if not idx then return false end
    return true, idx.orderId, idx.facility
end

function O.GetJailMinutes(who)
    local cid = J.Who(who)
    if not cid or not O.activeIndex[cid] then return 0 end
    local rows = O.IncarcerationRows(cid) or {}
    return math.ceil(O.TimeToRelease(rows) / 60)
end

-- ── money: fines, citations, restitution ────────────────────────────────────────────────────────

function O.Account(row)
    return (Config.Fines.Accounts or {})[row.source_type or ''] or Config.Fines.DefaultAccount or 'police'
end

local function payTarget(row)
    if row.kind == 'restitution' then return ('player:%s:bank'):format(row.victim_cid) end
    return 'society:' .. O.Account(row)
end

function O.PayKey(id, attempt) return ('pf-justice:order:%d:pay:%d'):format(id, attempt) end
function O.InvoiceRef(id) return ('pf-justice:order:%d'):format(id) end

local LABEL = { fine = 'Fine', citation = 'Citation', restitution = 'Restitution' }

local function backState(row, from)
    if from and from ~= 'payment_pending' and S.Can(row.kind, 'payment_pending', from) then return from end
    return 'issued'
end

local function isAnon(cid) return type(cid) == 'string' and cid:sub(1, 5) == 'anon-' end

--- Marks the order paid with `moved` = what the ledger (or the phone invoice) actually moved.
local function settlePaid(row, from, actor, how, moved)
    local now = os.time()
    moved = tonumber(moved) or ((row.amount or 0) - (row.paid_amount or 0))
    local paidAmount = (row.paid_amount or 0) + moved
    if update(SQL.paid, { paidAmount, now, now, row.id, from }) ~= 1 then return false end
    row.state, row.paid_amount, row.ends_at = 'paid', paidAmount, now
    O.Event(row.id, 'paid', { from = from, how = how, key = row.pay_key, invoice = row.invoice_id, moved = moved }, actor)
    if paidAmount ~= row.amount then
        print(('^3[pf-justice]^7 order %d settled with $%d paid of $%d (%s)'):format(row.id, paidAmount, row.amount or 0, tostring(how)))
    end
    changed(row, { action = 'state', from = from, to = 'paid', reason = how })
    J.Emit('paymentSettled', O.Public(row), 'paid')
    if J.Records and J.Records.OnOrderEnded then J.Records.OnOrderEnded(row, 'paid') end
    local P = J.GetPlayerByCid(row.citizenid)
    if P then J.Notify(P.PlayerData.source, ('%s #%d of $%d is paid'):format(LABEL[row.kind] or 'Order', row.id, moved)) end
    return true
end

local function createInvoice(row, due)
    if GetResourceState('pfm-phone') ~= 'started' then return nil, 'phone_unavailable' end
    local ok, id, err = pcall(function()
        return exports['pfm-phone']:CreateInvoice({
            citizenid = row.citizenid, amount = due, society = O.Account(row), candecline = 0,
            sender = row.source_type == 'court_decision' and 'Court Clerk' or 'Police Department',
            reason = ('%s #%d'):format(LABEL[row.kind] or 'Order', row.id), ref = O.InvoiceRef(row.id),
        })
    end)
    if not ok then return nil, 'phone_error' end
    id = tonumber(id)
    if not id then return nil, err or 'phone_refused' end
    return id
end

--- PayOrder (architecture 4.7.1): opts = { payerSrc, account = 'bank'|'cash', key, actor? }.
function O.Pay(orderId, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    local id = U.Int(orderId, 1, 2147483647)
    local payerSrc = U.Src(opts.payerSrc)
    local account = opts.account or 'bank'
    if not id or not payerSrc or (account ~= 'bank' and account ~= 'cash') then
        return Err('bad_args', 'orderId, an online payerSrc and account bank or cash are required')
    end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    if key == nil and not internal then return Err('bad_args', 'opts.key is required') end
    local payer = J.GetPlayer(payerSrc)
    if not payer then return Err('offline', 'The payer is not online') end
    local payerCid = payer.PlayerData.citizenid
    local actor = { kind = 'player', src = payerSrc, cid = payerCid, resource = ctx.invoker or J.RESOURCE }

    return O.WithOrder(id, function(row)
        if not S.MoneyKinds[row.kind] then return Err('bad_args', 'This order has nothing to pay') end
        if key then
            local ev = one(SQL.eventByKey, { key })
            if ev then
                if tonumber(ev.order_id) ~= id or ev.action ~= 'pay' then return Err('key_reused', 'This key was used for another payment') end
                if row.state == 'paid' then return { ok = true, duplicate = true, state = row.state } end
                return { ok = false, duplicate = true, state = row.state,
                    error = row.state == 'payment_pending' and 'payment_unclear' or 'invalid_state', message = 'The order is ' .. row.state }
            end
        end
        if row.state == 'payment_pending' then
            return { ok = false, error = 'payment_unclear', state = row.state, message = 'The bank is still processing an earlier payment' }
        end
        if row.state == 'invoiced' then return Err('invalid_state', 'This order is a phone invoice; pay it on the phone') end
        if not S.Payable[row.state] then return Err('invalid_state', 'The order is ' .. row.state) end
        if not J.Rate.Allow('pay:' .. payerSrc, Config.Fines.PayCooldownSeconds or 5) then
            return Err('rate_limited', 'Wait a moment before paying again')
        end
        local due = (row.amount or 0) - (row.paid_amount or 0)
        local from = row.state
        local attempt = (row.pay_attempt or 0) + 1
        local ledgerKey = O.PayKey(id, attempt)
        local okEv, evErr = O.Event(id, 'pay', { attempt = attempt, ledgerKey = ledgerKey, payer = payerCid, account = account, from = from, due = due }, actor, key)
        if not okEv and evErr == 'duplicate' then return { ok = false, duplicate = true, state = row.state, error = 'busy' } end
        -- pay_from: where a clear refusal returns the order to (also when the sweep settles it)
        if update(SQL.payBegin, { attempt, ledgerKey, from, os.time(), id, from, row.pay_attempt or 0 }) ~= 1 then
            if key then update(SQL.deleteEventByKey, { key }) end
            return Err('busy', 'The order changed meanwhile; try again')
        end
        row.state, row.pay_attempt, row.pay_key, row.pay_from = 'payment_pending', attempt, ledgerKey, from

        local res = PFPayout.Transfer({
            from = ('player:%s:%s'):format(payerCid, account), to = payTarget(row), amount = due, key = ledgerKey,
            kind = row.kind == 'restitution' and 'restitution' or 'fine',
            reason = ('%s #%d'):format(LABEL[row.kind] or 'Order', id), actor = payerCid, metadata = { order = id },
        })
        res = type(res) == 'table' and res or { ok = false, error = 'bank_unavailable' }
        if res.ok then
            settlePaid(row, 'payment_pending', actor, 'ledger', due)
            return { ok = true, state = 'paid' }
        end
        if not PFPayout.IsClearFailure(res) then
            print(('^3[pf-justice]^7 order %d: payment %s is unclear (%s); it is settled by the sweep'):format(id, ledgerKey, tostring(res.error or res.state)))
            return { ok = false, error = 'payment_unclear', state = 'payment_pending', message = 'The bank is still processing this payment. Nothing more was charged.' }
        end
        -- clearly refused: nothing was taken; the order goes back where it was paid from (a referral
        -- to court or an overdue deadline is kept)
        local back = backState(row, from)
        if update(SQL.setState, { back, os.time(), id, 'payment_pending' }) == 1 then
            row.state = back
            O.Event(id, 'pay_refused', { attempt = attempt, error = res.error, back = back }, actor)
        end
        if res.error == 'bank_unavailable' or res.error == 'ledger_unavailable' then
            return { ok = false, error = 'bank_unavailable', state = row.state, message = 'The bank is not available; nothing was charged' }
        end
        if res.error == 'insufficient_funds' and Config.Fines.InvoiceOnRefusal and payerCid == row.citizenid
            and row.kind ~= 'restitution' and row.state == 'issued' then
            local invoiceId = createInvoice(row, due)
            if invoiceId and update(SQL.setInvoice, { 'invoiced', invoiceId, os.time(), id, 'issued' }) == 1 then
                row.state, row.invoice_id = 'invoiced', invoiceId
                O.Event(id, 'invoiced', { invoice = invoiceId }, actor)
                changed(row, { action = 'state', from = 'issued', to = 'invoiced', reason = 'insufficient_funds' })
                TriggerClientEvent('qb-phone:RefreshPhone', payerSrc)
                return { ok = false, error = 'insufficient_funds', state = 'invoiced', invoiceId = invoiceId,
                    message = 'Not enough money: the order was sent to your phone as an invoice' }
            end
        end
        return { ok = false, error = 'insufficient_funds', state = row.state, message = 'The payment was refused; nothing was charged' }
    end)
end

-- ── refunds of phone invoices paid for an order that no longer waited for them ──────────────────
-- The phone moved the money from player:<cid>:bank to society:<society> (pfm-phone PayerAccount).
-- The refund is one ledger Transfer back under pf-justice:order:<id>:invoice_refund; after a clear
-- refusal the next attempt is numbered (...:invoice_refund:2, ...), an unclear one is held and
-- looked up by the sweep (GetTransaction), never paid again under a new key.

local PHONE = { kind = 'system', label = 'pfm-phone', resource = 'pfm-phone' }
local REFUNDER = { kind = 'system', label = 'invoice refund', resource = J.RESOURCE }

function O.RefundKey(id, attempt)
    if (attempt or 1) <= 1 then return ('pf-justice:order:%d:invoice_refund'):format(id) end
    return ('pf-justice:order:%d:invoice_refund:%d'):format(id, attempt)
end

local function refundMove(row, to, from, attempt, fromAttempt)
    if update(SQL.refundStep, { to, attempt, os.time(), row.id, from, fromAttempt }) ~= 1 then return false end
    row.refund_state, row.refund_attempt = to, attempt
    return true
end

local function refundDone(row, key)
    if not refundMove(row, 'done', 'unclear', row.refund_attempt, row.refund_attempt) then return 'busy' end
    O.Event(row.id, 'refunded', { key = key, amount = row.refund_amount, to = row.refund_cid, invoice = row.refund_invoice }, REFUNDER)
    J.Emit('paymentSettled', O.Public(row), 'refunded')
    local P = J.GetPlayerByCid(row.refund_cid)
    if P then
        J.Notify(P.PlayerData.source, ('$%d paid on invoice #%s for %s #%d was refunded to your bank'):format(row.refund_amount or 0,
            tostring(row.refund_invoice or '?'), (LABEL[row.kind] or 'order'):lower(), row.id), 'success')
    end
    return 'refunded'
end

--- One step of a due or unclear refund (the caller holds the order and cid locks). Returns
--- 'refunded', 'failed' (clear refusal: the next step uses the next numbered key), 'unclear',
--- 'wait', 'manual' (too many refused attempts: an admin settles it), 'busy' or 'skip'.
function O.RefundStepLocked(row)
    if row.refund_state == 'unclear' then
        if GetResourceState('pfm-banking') ~= 'started' then return 'wait' end
        local key = O.RefundKey(row.id, row.refund_attempt)
        local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
        if not ok then return 'wait' end
        if tx ~= nil and tx.state == 'completed' then return refundDone(row, key) end
        if tx == nil or PFPayout.IsClearFailure({ ok = false, state = tx.state, error = tx.error, txId = tx.tx_id }) then
            if not refundMove(row, 'due', 'unclear', row.refund_attempt, row.refund_attempt) then return 'busy' end
            O.Event(row.id, 'refund_failed', { key = key, error = tx and (tx.error or tx.state) or 'not_written' }, REFUNDER)
            return 'failed'
        end
        return 'wait'
    end
    if row.refund_state ~= 'due' then return 'skip' end
    local attempt = (row.refund_attempt or 0) + 1
    if attempt > (Config.Fines.RefundMaxAttempts or 10) then
        if refundMove(row, 'manual', 'due', row.refund_attempt, row.refund_attempt) then
            O.Event(row.id, 'refund_manual', { attempts = row.refund_attempt, amount = row.refund_amount, to = row.refund_cid }, REFUNDER)
            print(('^1[pf-justice]^7 order %d: the refund of $%d to %s was refused %d times; settle it by hand'):format(row.id,
                row.refund_amount or 0, tostring(row.refund_cid), row.refund_attempt or 0))
        end
        return 'manual'
    end
    -- the attempt number is stored before the transfer, so a crash leaves its key to look up
    if not refundMove(row, 'unclear', 'due', attempt, row.refund_attempt or 0) then return 'busy' end
    local key = O.RefundKey(row.id, attempt)
    local res = PFPayout.Transfer({
        from = 'society:' .. tostring(row.refund_society), to = ('player:%s:bank'):format(row.refund_cid), amount = row.refund_amount,
        key = key, kind = 'refund', reason = ('Refund of invoice #%s (%s #%d)'):format(tostring(row.refund_invoice or '?'), LABEL[row.kind] or 'Order', row.id),
        metadata = { order = row.id, invoice = row.refund_invoice },
    })
    res = type(res) == 'table' and res or { ok = false, error = 'bank_unavailable' }
    if res.ok then return refundDone(row, key) end
    if PFPayout.IsClearFailure(res) then
        if refundMove(row, 'due', 'unclear', attempt, attempt) then
            O.Event(row.id, 'refund_failed', { key = key, error = res.error or res.state }, REFUNDER)
        end
        return 'failed'
    end
    print(('^3[pf-justice]^7 order %d: refund %s is unclear (%s); the sweep settles it'):format(row.id, key, tostring(res.error or res.state)))
    return 'unclear'
end

--- A phone invoice of this order was paid although the order no longer waited for it (waived,
--- paid another way, a stale invoice). Never ignored: logged as an order event and refunded to the
--- payer. Caller holds the locks. Returns the refund step's outcome, why there is none, or 'retry'
--- when the database failed (the settlement is then queued and this runs again).
--- `byRef`: the invoice named this order by its ref. pfm-phone reuses invoice ids, so a report
--- matched by id alone may be a later bill of someone else: it is logged for an admin, not refunded.
--- Order of writes: the refund is started (refund_state 'due', refund_invoice) before the keyed log
--- event, so a failure between the two can never leave a logged refund that nothing starts; a retry
--- recognises a started refund by refund_invoice and only adds the missing log.
function O.InvoicePaidLateLocked(row, invoice, why, byRef)
    local invoiceId = U.Int(invoice.id, 1, 2147483647)
    local amount = U.Int(invoice.amount, 1, 2147483647)
    local payer = U.ValidCid(invoice.citizenid) and invoice.citizenid or row.citizenid
    local society = U.Str(invoice.society, 50) or O.Account(row)
    local evKey = ('pf-justice:order:%d:invoice_paid:%d'):format(row.id, invoiceId or 0)
    local function log(refund)
        local okEv, evErr = O.Event(row.id, 'invoice_paid_late', { invoice = invoiceId, amount = amount, payer = payer, society = society,
            state = row.state, why = why, refund = refund }, PHONE, evKey)
        return okEv or evErr == 'duplicate'
    end
    if invoiceId and row.refund_invoice == invoiceId then
        -- a retry: this invoice's refund is already running (the sweep moves it on)
        return log('due') and 'duplicate' or 'retry'
    end
    local ev, okq = one(SQL.eventByKey, { evKey })
    if not okq then return 'retry' end
    if ev then return 'duplicate' end
    local refund
    if isAnon(row.citizenid) then refund = 'payer_deleted'          -- nobody to refund: the character is gone
    elseif not byRef then refund = 'manual_unverified'
    elseif not amount then refund = 'manual_unknown_amount'
    elseif row.refund_state ~= nil then refund = 'manual_second_invoice' -- one refund per order; a second is settled by hand
    else refund = 'due' end
    if refund == 'due' then
        -- under the locks refund_state was read as NULL, so 0 rows here is a failed write
        if update(SQL.refundBegin, { amount, payer, society, invoiceId, os.time(), row.id }) ~= 1 then return 'retry' end
        row.refund_state, row.refund_attempt, row.refund_amount, row.refund_cid, row.refund_society, row.refund_invoice =
            'due', 0, amount, payer, society, invoiceId
    end
    local logged = log(refund)
    print(('^3[pf-justice]^7 order %d (%s): phone invoice %s was paid ($%s by %s); refund: %s'):format(row.id, row.state,
        tostring(invoiceId), tostring(amount), tostring(payer), refund))
    if refund ~= 'due' then return logged and refund or 'retry' end
    local step = O.RefundStepLocked(row)
    return logged and step or 'retry'
end

-- ── invoice settlements (pfm-phone:server:invoiceSettled) ──────────────────────────────────────
-- The phone reports each settlement once. One that cannot be applied now (the order or citizen
-- lock is held by the clock tick, the sweep or another action; a database error) is queued in
-- memory and as a keyed 'settle_queued' order event, retried every tick and by the sweep, and
-- reloaded at Boot. Applying is idempotent (state compare-and-set, keyed late-payment log), so a
-- retry applies a settlement once.

O.settleQueue = O.settleQueue or {} -- [key] = { invoice = { id, ref, amount, citizenid, society }, outcome, orderId }

SQL.settleQueued = "SELECT * FROM pf_justice_order_events WHERE action = 'settle_queued' ORDER BY id LIMIT 200"
SQL.settleDone = "UPDATE pf_justice_order_events SET action = 'settle_done' WHERE idem_key = ?"

local OUTCOMES = { paid = true, declined = true, cancelled = true }

local function invoiceCopy(invoice)
    return {
        id = U.Int(invoice.id, 1, 2147483647),
        ref = type(invoice.ref) == 'string' and #invoice.ref <= 128 and invoice.ref or nil,
        amount = U.Int(invoice.amount, 1, 2147483647),
        citizenid = U.ValidCid(invoice.citizenid) and invoice.citizenid or nil,
        society = U.Str(invoice.society, 50),
    }
end

local function settleKey(orderId, invoice, outcome)
    return ('pf-justice:order:%d:settle:%d:%s'):format(orderId or 0, invoice.id or 0, outcome)
end

local function retry() return { status = 'retry' } end
local function done() return { status = 'done' } end

--- Applies one settlement. Returns 'done' (applied, or nothing of ours to do) or 'retry', and the
--- order id when it is known.
function O.ApplySettlement(invoice, outcome)
    local invoiceId = invoice.id
    local orderId = invoice.ref and U.Int(invoice.ref:match('^pf%-justice:order:(%d+)$'), 1, 2147483647) or nil
    local byRef = orderId ~= nil
    if not orderId then
        if not invoiceId then return 'done' end
        local found, okq = one(SQL.byInvoice, { invoiceId })
        if not okq then return 'retry' end
        if not found then return 'done' end -- not one of ours
        orderId = found.id
    end
    local res = O.WithOrder(orderId, function(row)
        if not S.MoneyKinds[row.kind] then return done() end
        -- an invoice of another character with the same id is not ours
        if invoice.citizenid and invoice.citizenid ~= row.citizenid and not isAnon(row.citizenid) then return done() end
        local current = row.state == 'invoiced' and (invoiceId == nil or row.invoice_id == invoiceId)
        local waiver, okw = O.PendingWaiver(row.id)
        if not okw then return retry() end
        local waiverOfThis = waiver ~= nil and invoiceId ~= nil and tonumber(waiver.invoice) == invoiceId
        if outcome == 'paid' then
            if current then
                -- a deleted character paid before the deletion: the debt is settled, nobody to refund
                if not waiver or isAnon(row.citizenid) then
                    return settlePaid(row, 'invoiced', PHONE, 'invoice', invoice.amount) and done() or retry()
                end
                if not O.MoveLocked(row, 'waived', waiver.reason or 'waived', PHONE,
                    { invoice = invoiceId, invoice_gone = true, requestedBy = waiver.by }) then return retry() end
                return O.InvoicePaidLateLocked(row, invoice, 'waived while invoiced', true) == 'retry' and retry() or done()
            end
            if row.state == 'paid' and invoiceId and row.invoice_id == invoiceId then return done() end -- reported before
            -- trusted when it names the order by ref, or it is the invoice the recorded waiver was for
            local r = O.InvoicePaidLateLocked(row, invoice, 'order is ' .. row.state, byRef or waiverOfThis)
            return r == 'retry' and retry() or done()
        end
        -- declined / cancelled
        if current then
            if update(SQL.setInvoice, { 'issued', nil, os.time(), row.id, 'invoiced' }) ~= 1 then return retry() end
            row.state, row.invoice_id = 'issued', nil
            O.Event(row.id, 'invoice_declined', { invoice = invoiceId, outcome = outcome }, PHONE)
            changed(row, { action = 'state', from = 'invoiced', to = 'issued', reason = 'invoice ' .. outcome })
        elseif not (row.state == 'issued' and waiverOfThis) then
            return done() -- (a retry finds the order issued with the waiver of this invoice still to apply)
        end
        if waiver and not O.MoveLocked(row, 'waived', waiver.reason or 'waived', PHONE, { requestedBy = waiver.by, invoice = invoiceId }) then
            return retry()
        end
        return done()
    end)
    if type(res) ~= 'table' then return 'retry', orderId end
    if res.status then return res.status, orderId end
    if res.error == 'not_found' then
        -- WithOrder could not read the row: missing (nothing to settle) or a failed read (retry)
        local _, okq = one(SQL.orderById, { orderId })
        if okq then
            print(('^3[pf-justice]^7 invoice %s settled (%s) for order %d, which does not exist'):format(tostring(invoiceId), outcome, orderId))
            return 'done', orderId
        end
    end
    return 'retry', orderId -- busy, or the database failed
end

function O.QueueSettlement(invoice, outcome, orderId)
    local key = settleKey(orderId, invoice, outcome)
    if O.settleQueue[key] then return key end
    O.settleQueue[key] = { invoice = invoice, outcome = outcome, orderId = orderId }
    O.Event(orderId or 0, 'settle_queued', { invoice = invoice, outcome = outcome }, PHONE, key)
    print(('^3[pf-justice]^7 invoice %s (%s) could not be applied now; queued'):format(tostring(invoice.id), outcome))
    return key
end

--- pfm-phone settled one of our invoices: 'paid', 'declined' or 'cancelled' (CancelInvoice, 15H).
--- Returns true when applied now; false when it was not ours or is queued for a retry.
function O.OnInvoiceSettled(invoice, outcome)
    if type(invoice) ~= 'table' or not OUTCOMES[outcome] then return false end
    local inv = invoiceCopy(invoice)
    local status, orderId = O.ApplySettlement(inv, outcome)
    if status == 'retry' then
        O.QueueSettlement(inv, outcome, orderId)
        return false
    end
    return true
end

AddEventHandler('pfm-phone:server:invoiceSettled', function(invoice, outcome)
    local src = tonumber(source)
    if src and src > 0 then return end -- server-only
    O.OnInvoiceSettled(invoice, outcome)
end)

local function payRefused(row, actor, err)
    local back = backState(row, row.pay_from)
    if update(SQL.setState, { back, os.time(), row.id, 'payment_pending' }) ~= 1 then return 'busy' end
    row.state = back
    O.Event(row.id, 'pay_refused', { key = row.pay_key, error = err, back = back }, actor)
    J.Emit('paymentSettled', O.Public(row), 'failed')
    -- the character was deleted while the bank decided: nobody is left to pay
    if isAnon(row.citizenid) and S.Can(row.kind, back, 'waived') then O.MoveLocked(row, 'waived', 'character_deleted', actor) end
    return back
end

--- Settles one payment_pending row from the ledger's answer for its key (the caller holds the locks).
function O.SettlePendingLocked(row)
    if row.state ~= 'payment_pending' or type(row.pay_key) ~= 'string' then return 'skip' end
    if GetResourceState('pfm-banking') ~= 'started' then return 'wait' end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(row.pay_key) end)
    if not ok then return 'wait' end
    local actor = { kind = 'system', label = 'payment sweep', resource = J.RESOURCE }
    -- the transfer never reached the ledger (a crash before it was written): nothing moved
    if tx == nil then return payRefused(row, actor, 'not_written') end
    if tx.state == 'completed' then
        return settlePaid(row, 'payment_pending', actor, 'sweep', tonumber(tx.amount)) and 'paid' or 'busy'
    end
    if PFPayout.IsClearFailure({ ok = false, state = tx.state, error = tx.error, txId = tx.tx_id }) then
        return payRefused(row, actor, tx.error or tx.state)
    end
    return 'wait'
end

-- ── citations ───────────────────────────────────────────────────────────────────────────────────

local function newUid()
    return ('CT%X%04X'):format(os.time(), math.random(0, 0xFFFF))
end

--- IssueCitation (architecture 4.7.1): spec = { cid, amount, violation, location?, plate?, speed?, limit?, officerSrc?, contestDays? }.
function O.IssueCitation(spec, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    if type(spec) ~= 'table' then return Err('bad_args', 'spec must be a table') end
    local violation = U.Str(spec.violation, 48)
    if not violation then return Err('bad_args', 'violation is required') end
    local contestDays = U.Int(spec.contestDays or Config.Citations.ContestDays, 0, Config.Citations.MaxContestDays)
    if not contestDays then return Err('bad_args', 'contestDays is invalid') end
    local plate = spec.plate ~= nil and U.Str(spec.plate, 16) or nil
    plate = plate and plate:upper() or nil
    local speed = spec.speed ~= nil and U.Int(spec.speed, 0, 999) or nil
    local limit = spec.limit ~= nil and U.Int(spec.limit, 0, 999) or nil
    if (spec.speed ~= nil and not speed) or (spec.limit ~= nil and not limit) then return Err('bad_args', 'speed and limit must be 0..999') end

    local officerCid, actorSpec, x, y = 'system', opts.actor, nil, nil
    if spec.officerSrc ~= nil then
        local src = U.Src(spec.officerSrc)
        local P = src and J.GetPlayer(src)
        if not P then return Err('offline', 'The officer is not online') end
        local job = P.PlayerData.job or {}
        if not (Config.Citations.OfficerJobTypes or {})[job.type] or job.onduty ~= true then
            return Err('no_permission', 'Only an on-duty officer can issue a citation')
        end
        officerCid, actorSpec = P.PlayerData.citizenid, { src = src }
        -- the place is where the officer stands (server position), not a value the caller sends
        local c = U.Coords(src)
        if c then x, y = c.x, c.y end
    elseif type(spec.location) == 'table' then
        x, y = tonumber(spec.location.x), tonumber(spec.location.y)
    end
    if x and (x ~= x or math.abs(x) > 99999) then x = nil end
    if y and (y ~= y or math.abs(y) > 99999) then y = nil end

    local uid = newUid()
    local res = O.Create({ cid = spec.cid, kind = 'citation', amount = spec.amount, sourceRef = { type = 'citation', id = uid },
        dueAt = spec.dueAt }, { key = opts.key, actor = actorSpec }, ctx)
    if not res.ok then return res end
    local orderId = res.orderId
    local row = O.Row(orderId)
    if not row then return Err('db_unavailable', 'The justice database did not answer') end
    local cit = one(SQL.citationByOrder, { orderId })
    if not cit then
        uid = row.source_id or uid
        local now = os.time()
        local okIns, citId = pcall(MySQL.insert.await, SQL.insertCitation, {
            orderId, uid, violation, plate, speed, limit, x, y, officerCid, now + contestDays * 86400, now,
        })
        if okIns and tonumber(citId) then
            cit = { id = tonumber(citId), uid = uid }
        else
            -- a second call with the same key, racing this one, stored the row first (uq_cit_uid)
            cit = one(SQL.citationByOrder, { orderId })
            if not cit then return Err('db_unavailable', 'The citation could not be stored; retry with the same key') end
            return { ok = true, orderId = orderId, citationId = tonumber(cit.id), uid = cit.uid, duplicate = true }
        end
    end
    return { ok = true, orderId = orderId, citationId = tonumber(cit.id), uid = cit.uid, duplicate = res.duplicate }
end

--- The cited citizen contests within the window (actor = { src } of that citizen, or an admin).
function O.ContestCitation(orderId, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local id = U.Int(orderId, 1, 2147483647)
    if not id then return Err('bad_args', 'orderId is invalid') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    local why = U.Str(opts.reason, 200)
    return O.WithOrder(id, function(row)
        if row.kind ~= 'citation' then return Err('bad_args', 'Not a citation') end
        if actor.kind ~= 'admin' and actor.cid ~= row.citizenid then return Err('no_permission', 'Only the cited citizen can contest') end
        local cit = one(SQL.citationByOrder, { id })
        if not cit or (tonumber(cit.contest_until) or 0) < os.time() then return Err('invalid_state', 'The contest window is closed') end
        local okCount, count = pcall(MySQL.scalar.await, SQL.countEvents, { id, 'contested' })
        if not okCount then return Err('db_unavailable', 'The justice database did not answer') end
        if (tonumber(count) or 0) > 0 then return Err('invalid_state', 'This citation was contested before') end
        local ok, err = O.MoveLocked(row, 'contested', why, actor)
        if not ok then return err end
        return { ok = true, order = O.Public(row) }
    end)
end

--- A court (pf-justice) or an admin decides a contested citation: upheld (payable again) or dismissed.
function O.DecideCitation(orderId, upheld, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local id = U.Int(orderId, 1, 2147483647)
    if not id or type(upheld) ~= 'boolean' then return Err('bad_args', 'orderId and upheld (boolean) are required') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    if not internal and actor.kind ~= 'admin' then return Err('no_permission', 'A judge or admin decides contests') end
    return O.WithOrder(id, function(row)
        if row.kind ~= 'citation' then return Err('bad_args', 'Not a citation') end
        local ok, err = O.MoveLocked(row, upheld and 'upheld' or 'dismissed', U.Str(opts.reason, 200), actor)
        if not ok then return err end
        return { ok = true, order = O.Public(row) }
    end)
end

-- ── sweeps (every Config.Clock.SweepSeconds; called directly by specs) ─────────────────────────

O.cursor = O.cursor or { payments = 0, refunds = 0 }

-- One page of `sql` after the cursor; the cursor moves past it, and back to the start after the
-- last page, so every row is looked at in turn however many keep waiting.
local function page(name, sql, hold)
    local rows = many(sql, { hold, O.cursor[name] or 0 }) or {}
    O.cursor[name] = #rows >= 50 and rows[#rows].id or 0
    return rows
end

function O.Sweep(now)
    now = now or os.time()
    local out = { payments = 0, overdue = 0, supervision = 0, refunds = 0 }
    local system = { kind = 'system', label = 'sweep', resource = J.RESOURCE }
    local hold = now - (Config.Fines.PaymentHoldSeconds or 120)
    out.queued = O.RetryQueued()
    for _, row in ipairs(page('payments', SQL.duePayments, hold)) do
        local r = O.WithOrder(row.id, function(fresh) return { ok = true, outcome = O.SettlePendingLocked(fresh) } end)
        if type(r) == 'table' and r.outcome and r.outcome ~= 'wait' and r.outcome ~= 'busy' then out.payments = out.payments + 1 end
    end
    for _, row in ipairs(page('refunds', SQL.dueRefunds, hold)) do
        local r = O.WithOrder(row.id, function(fresh) return { ok = true, outcome = O.RefundStepLocked(fresh) } end)
        if type(r) == 'table' and r.outcome == 'refunded' then out.refunds = out.refunds + 1 end
    end
    for _, row in ipairs(many(SQL.dueDeadlines, { now }) or {}) do
        O.WithOrder(row.id, function(fresh)
            if fresh.due_at and fresh.due_at <= now and S.Can(fresh.kind, fresh.state, 'overdue')
                and not (fresh.kind == 'community_service' and (fresh.units_done or 0) >= (fresh.units or 0)) then
                if O.MoveLocked(fresh, 'overdue', 'deadline passed', system) then
                    out.overdue = out.overdue + 1
                    local P = J.GetPlayerByCid(fresh.citizenid)
                    if P then J.Notify(P.PlayerData.source, ('Your %s #%d is overdue'):format((fresh.kind:gsub('_', ' ')), fresh.id), 'error') end
                end
            end
            return { ok = true }
        end)
    end
    for _, row in ipairs(many(SQL.dueSupervision, { now }) or {}) do
        O.WithOrder(row.id, function(fresh)
            if fresh.state == 'active' and fresh.ends_at and fresh.ends_at <= now then
                if O.MoveLocked(fresh, 'completed', 'term served', system) then out.supervision = out.supervision + 1 end
            end
            return { ok = true }
        end)
    end
    return out
end

-- ── deleted characters ──────────────────────────────────────────────────────────────────────────

local function anonToken()
    return ('anon-%08x%04x'):format(math.random(0, 0x7fffffff), math.random(0, 0xffff))
end

--- Whether a phone invoice no longer exists (read only; see SQL.phoneInvoice). An unanswered query
--- counts as still there.
function O.PhoneInvoiceGone(invoiceId)
    if not invoiceId then return true end
    local ok, row = pcall(MySQL.single.await, SQL.phoneInvoice, { invoiceId })
    if not ok then return false end
    if type(row) == 'table' and row[1] ~= nil and row.id == nil then row = row[1] end
    return type(row) ~= 'table' or row.id == nil
end

-- How an open order of a deleted character ends: vacated, else waived, else dismissed (a contested
-- citation; the court has no one to hear).
local CLOSE = { 'vacated', 'waived', 'dismissed' }

--- pfm-core deleted the character: open orders end (vacated, waived or dismissed; a payment the bank
--- is still processing is left to the sweep; an invoiced fine whose phone invoice is still being paid
--- keeps a recorded waiver until the phone settles it), then the citizen id on orders, events, audit
--- rows, records and citations is replaced by one random token, so court history stays readable
--- without naming the person.
function O.OnCharacterDeleted(cid)
    if not U.ValidCid(cid) or not J.Ready() then return false end
    local system = { kind = 'system', label = 'character deleted', resource = J.RESOURCE }
    return O.WithCid(cid, function()
        local rows = many(SQL.ordersByCid, { cid })
        if not rows then error('the orders of the deleted character could not be read') end -- queued and retried
        local closed, held = 0, 0
        for _, r in ipairs(rows) do
            if r.state == 'invoiced' then
                if O.PhoneInvoiceGone(r.invoice_id) then
                    if O.MoveLocked(r, 'waived', 'character_deleted', system, { invoice = r.invoice_id, invoice_gone = true }) then closed = closed + 1 end
                elseif O.RequestWaiverLocked(r, 'waived', 'character_deleted', system) then
                    held = held + 1
                end
            elseif S.IsOpen(r.kind, r.state) and r.state ~= 'payment_pending' then
                local to
                for _, c in ipairs(CLOSE) do if not to and S.Can(r.kind, r.state, c) then to = c end end
                if to and O.MoveLocked(r, to, 'character_deleted', system) then closed = closed + 1 end
            end
        end
        local token = anonToken()
        local n = update(SQL.anonOrders, { token, cid })
        for _, sql in ipairs({ SQL.anonVictim, SQL.anonOfficer, SQL.anonCreatedBy, SQL.anonRefundCid, SQL.anonEventActor,
            SQL.anonAuditActor, SQL.anonAuditEntity }) do
            update(sql, { token, cid })
        end
        -- JSON details: the quoted id (payer, requester) only, never a longer id that contains it
        local quoted = '"' .. cid .. '"'
        update(SQL.anonEventDetail, { quoted, '"' .. token .. '"', '%' .. quoted .. '%' })
        update(SQL.anonAuditDetail, { quoted, '"' .. token .. '"', '%' .. quoted .. '%' })
        local m = J.Records and J.Records.Anonymise and J.Records.Anonymise(cid, token) or 0
        O.activeIndex[cid] = nil
        if J.Clock then J.Clock.Forget(cid) end
        J.Audit.Write('character', token, 'anonymised', { orders = n, closed = closed, held = held, records = m }, system)
        update(SQL.deleteDone, { token, cid }) -- a queued deletion is done (and its row no longer names the id)
        return { ok = true, closed = closed, held = held, orders = n, records = m, token = token }
    end)
end

-- A deletion that cannot run now (the citizen lock is held, the database is not ready or fails) is
-- queued: in memory and as a 'delete_queued' audit row (renamed to the token when done), retried
-- every tick and by the sweep, reloaded at Boot.
O.deleteQueue = O.deleteQueue or {} -- [cid] = true
SQL.deleteQueued = "SELECT entity_id FROM pf_justice_audit WHERE entity = 'character' AND action = 'delete_queued' ORDER BY id LIMIT 200"
SQL.deleteDone = "UPDATE pf_justice_audit SET action = 'delete_done', entity_id = ? WHERE entity = 'character' AND entity_id = ? AND action = 'delete_queued'"

function O.QueueDeletion(cid)
    if O.deleteQueue[cid] then return end
    O.deleteQueue[cid] = true
    if J.Ready() then J.Audit.Write('character', cid, 'delete_queued', nil, { kind = 'system', label = 'character deleted', resource = J.RESOURCE }) end
    print(('^3[pf-justice]^7 character deletion of %s could not run now; queued'):format(cid))
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end -- server-only
    if not U.ValidCid(citizenid) then return end
    local res = O.OnCharacterDeleted(citizenid)
    if not (type(res) == 'table' and res.ok == true) then O.QueueDeletion(citizenid) end
end)

-- ── retry queues (settlements, deletions) ───────────────────────────────────────────────────────

--- Runs the queued settlements and deletions once. Returns how many finished.
function O.RetryQueued()
    if not J.Ready() then return 0 end
    local n, keys, cids = 0, {}, {}
    for key in pairs(O.settleQueue) do keys[#keys + 1] = key end
    for cid in pairs(O.deleteQueue) do cids[#cids + 1] = cid end
    for _, key in ipairs(keys) do
        local q = O.settleQueue[key]
        if q and O.ApplySettlement(q.invoice, q.outcome) == 'done' then
            O.settleQueue[key] = nil
            update(SQL.settleDone, { key })
            n = n + 1
        end
    end
    for _, cid in ipairs(cids) do
        local res = O.OnCharacterDeleted(cid)
        if type(res) == 'table' and res.ok == true then
            O.deleteQueue[cid] = nil
            n = n + 1
        end
    end
    return n
end

--- Reloads both queues after a restart (Boot).
function O.LoadQueues()
    for _, ev in ipairs(many(SQL.settleQueued, {}) or {}) do
        local d = U.Decode(ev.detail) or {}
        if type(d.invoice) == 'table' and OUTCOMES[d.outcome] and type(ev.idem_key) == 'string' then
            O.settleQueue[ev.idem_key] = { invoice = invoiceCopy(d.invoice), outcome = d.outcome, orderId = ev.order_id ~= 0 and ev.order_id or nil }
        end
    end
    local ok, rows = pcall(MySQL.query.await, SQL.deleteQueued, {})
    for _, r in ipairs(ok and type(rows) == 'table' and rows or {}) do
        if U.ValidCid(r.entity_id) then O.deleteQueue[r.entity_id] = true end
    end
end

function O.HasQueued() return next(O.settleQueue) ~= nil or next(O.deleteQueue) ~= nil end
