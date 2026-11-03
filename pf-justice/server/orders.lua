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
-- order to 'issued' (and, for the citizen's own fine, turns it into a pfm-phone invoice with
-- ref 'pf-justice:order:<id>'); an unclear result stays payment_pending and is never charged again
-- under a new key until it settles. The phone settles invoices through pfm-phone:server:invoiceSettled.
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
SQL.payBegin = [[UPDATE pf_justice_orders SET state = 'payment_pending', pay_attempt = ?, pay_key = ?, updated_at = ?
    WHERE id = ? AND state = ? AND pay_attempt = ?]]
SQL.paid = [[UPDATE pf_justice_orders SET state = 'paid', paid_amount = amount, ends_at = ?, updated_at = ? WHERE id = ? AND state = ?]]
SQL.setInvoice = 'UPDATE pf_justice_orders SET state = ?, invoice_id = ?, updated_at = ? WHERE id = ? AND state = ?'
SQL.byInvoice = [[SELECT * FROM pf_justice_orders WHERE invoice_id = ? AND state = 'invoiced' LIMIT 1]]
SQL.duePayments = [[SELECT * FROM pf_justice_orders WHERE state = 'payment_pending' AND updated_at <= ? ORDER BY id LIMIT 50]]
SQL.dueDeadlines = [[SELECT * FROM pf_justice_orders WHERE kind IN ('fine', 'citation', 'restitution', 'community_service')
    AND state IN ('issued', 'upheld', 'assigned', 'active') AND due_at IS NOT NULL AND due_at <= ? ORDER BY id LIMIT 100]]
SQL.dueSupervision = [[SELECT * FROM pf_justice_orders WHERE kind IN ('probation', 'parole') AND state = 'active'
    AND ends_at IS NOT NULL AND ends_at <= ? ORDER BY id LIMIT 100]]
SQL.anonOrders = 'UPDATE pf_justice_orders SET citizenid = ? WHERE citizenid = ?'
SQL.anonVictim = 'UPDATE pf_justice_orders SET victim_cid = ? WHERE victim_cid = ?'
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
    'starts_at', 'due_at', 'ends_at', 'created_at', 'updated_at' }
local ZERO = { served_seconds = true, credit_seconds = true, forfeit_seconds = true, paid_amount = true, pay_attempt = true, units_done = true }

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
            if key and select(2, O.Event(id, 'adjust_' .. kind, { kind = kind, reason = why }, actor, key)) == 'duplicate' then
                return { ok = true, duplicate = true, order = O.Public(row) }
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

local function settlePaid(row, from, actor, how)
    local now = os.time()
    if update(SQL.paid, { now, now, row.id, from }) ~= 1 then return false end
    row.state, row.paid_amount, row.ends_at = 'paid', row.amount, now
    O.Event(row.id, 'paid', { from = from, how = how, key = row.pay_key, invoice = row.invoice_id }, actor)
    changed(row, { action = 'state', from = from, to = 'paid', reason = how })
    J.Emit('paymentSettled', O.Public(row), 'paid')
    if J.Records and J.Records.OnOrderEnded then J.Records.OnOrderEnded(row, 'paid') end
    local P = J.GetPlayerByCid(row.citizenid)
    if P then J.Notify(P.PlayerData.source, ('%s #%d of $%d is paid'):format(LABEL[row.kind] or 'Order', row.id, row.amount)) end
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
        local okEv, evErr = O.Event(id, 'pay', { attempt = attempt, ledgerKey = ledgerKey, payer = payerCid, account = account, from = from }, actor, key)
        if not okEv and evErr == 'duplicate' then return { ok = false, duplicate = true, state = row.state, error = 'busy' } end
        if update(SQL.payBegin, { attempt, ledgerKey, os.time(), id, from, row.pay_attempt or 0 }) ~= 1 then
            if key then update(SQL.deleteEventByKey, { key }) end
            return Err('busy', 'The order changed meanwhile; try again')
        end
        row.state, row.pay_attempt, row.pay_key = 'payment_pending', attempt, ledgerKey

        local res = PFPayout.Transfer({
            from = ('player:%s:%s'):format(payerCid, account), to = payTarget(row), amount = due, key = ledgerKey,
            kind = row.kind == 'restitution' and 'restitution' or 'fine',
            reason = ('%s #%d'):format(LABEL[row.kind] or 'Order', id), actor = payerCid, metadata = { order = id },
        })
        res = type(res) == 'table' and res or { ok = false, error = 'bank_unavailable' }
        if res.ok then
            settlePaid(row, 'payment_pending', actor, 'ledger')
            return { ok = true, state = 'paid' }
        end
        if not PFPayout.IsClearFailure(res) then
            print(('^3[pf-justice]^7 order %d: payment %s is unclear (%s); it is settled by the sweep'):format(id, ledgerKey, tostring(res.error or res.state)))
            return { ok = false, error = 'payment_unclear', state = 'payment_pending', message = 'The bank is still processing this payment. Nothing more was charged.' }
        end
        -- clearly refused: nothing was taken
        if update(SQL.setState, { 'issued', os.time(), id, 'payment_pending' }) == 1 then
            row.state = 'issued'
            O.Event(id, 'pay_refused', { attempt = attempt, error = res.error }, actor)
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

--- pfm-phone settled one of our invoices (paid or declined).
function O.OnInvoiceSettled(invoice, outcome)
    if type(invoice) ~= 'table' then return false end
    local invoiceId = U.Int(invoice.id, 1, 2147483647)
    local orderId = type(invoice.ref) == 'string' and U.Int(invoice.ref:match('^pf%-justice:order:(%d+)$'), 1, 2147483647) or nil
    if not orderId then
        if not invoiceId then return false end
        local row = one(SQL.byInvoice, { invoiceId })
        orderId = row and row.id
    end
    if not orderId then return false end
    local res = O.WithOrder(orderId, function(row)
        if row.state ~= 'invoiced' or (invoiceId and row.invoice_id ~= invoiceId) then return { ok = false } end
        local actor = { kind = 'system', label = 'pfm-phone', resource = 'pfm-phone' }
        if outcome == 'paid' then
            return { ok = settlePaid(row, 'invoiced', actor, 'invoice') }
        elseif outcome == 'declined' then
            if update(SQL.setInvoice, { 'issued', nil, os.time(), row.id, 'invoiced' }) ~= 1 then return { ok = false } end
            row.state, row.invoice_id = 'issued', nil
            O.Event(row.id, 'invoice_declined', { invoice = invoiceId }, actor)
            changed(row, { action = 'state', from = 'invoiced', to = 'issued', reason = 'invoice declined' })
            return { ok = true }
        end
        return { ok = false }
    end)
    return type(res) == 'table' and res.ok == true
end

AddEventHandler('pfm-phone:server:invoiceSettled', function(invoice, outcome)
    local src = tonumber(source)
    if src and src > 0 then return end -- server-only
    O.OnInvoiceSettled(invoice, outcome)
end)

--- Settles one payment_pending row from the ledger's answer for its key (the caller holds the locks).
function O.SettlePendingLocked(row)
    if row.state ~= 'payment_pending' or type(row.pay_key) ~= 'string' then return 'skip' end
    if GetResourceState('pfm-banking') ~= 'started' then return 'wait' end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(row.pay_key) end)
    if not ok then return 'wait' end
    local actor = { kind = 'system', label = 'payment sweep', resource = J.RESOURCE }
    if tx == nil then
        -- the transfer never reached the ledger (a crash before it was written): nothing moved
        if update(SQL.setState, { 'issued', os.time(), row.id, 'payment_pending' }) == 1 then
            row.state = 'issued'
            O.Event(row.id, 'pay_refused', { key = row.pay_key, error = 'not_written' }, actor)
            J.Emit('paymentSettled', O.Public(row), 'failed')
            return 'issued'
        end
        return 'busy'
    end
    if tx.state == 'completed' then return settlePaid(row, 'payment_pending', actor, 'sweep') and 'paid' or 'busy' end
    if PFPayout.IsClearFailure({ ok = false, state = tx.state, error = tx.error, txId = tx.tx_id }) then
        if update(SQL.setState, { 'issued', os.time(), row.id, 'payment_pending' }) == 1 then
            row.state = 'issued'
            O.Event(row.id, 'pay_refused', { key = row.pay_key, error = tx.error or tx.state }, actor)
            J.Emit('paymentSettled', O.Public(row), 'failed')
            return 'issued'
        end
        return 'busy'
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
        if not okIns or not tonumber(citId) then return Err('db_unavailable', 'The citation could not be stored; retry with the same key') end
        cit = { id = tonumber(citId), uid = uid }
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

function O.Sweep(now)
    now = now or os.time()
    local out = { payments = 0, overdue = 0, supervision = 0 }
    local system = { kind = 'system', label = 'sweep', resource = J.RESOURCE }
    for _, row in ipairs(many(SQL.duePayments, { now - (Config.Fines.PaymentHoldSeconds or 120) }) or {}) do
        local r = O.WithOrder(row.id, function(fresh) return { ok = true, outcome = O.SettlePendingLocked(fresh) } end)
        if type(r) == 'table' and r.outcome and r.outcome ~= 'wait' and r.outcome ~= 'busy' then out.payments = out.payments + 1 end
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

--- pfm-core deleted the character: open orders end (vacated; open fines waived; a payment the bank
--- is still processing is left to the sweep), then the citizen id on orders, records and citations is
--- replaced by one random token, so court history stays readable without naming the person.
function O.OnCharacterDeleted(cid)
    if not U.ValidCid(cid) or not J.Ready() then return false end
    local system = { kind = 'system', label = 'character deleted', resource = J.RESOURCE }
    return O.WithCid(cid, function()
        local rows = many(SQL.ordersByCid, { cid }) or {}
        local closed = 0
        for _, r in ipairs(rows) do
            if S.IsOpen(r.kind, r.state) and r.state ~= 'payment_pending' then
                local to = S.Can(r.kind, r.state, 'vacated') and 'vacated' or (S.Can(r.kind, r.state, 'waived') and 'waived' or nil)
                if to and O.MoveLocked(r, to, 'character_deleted', system) then closed = closed + 1 end
            end
        end
        local token = anonToken()
        local n = update(SQL.anonOrders, { token, cid })
        update(SQL.anonVictim, { token, cid })
        update(SQL.anonOfficer, { token, cid })
        local m = J.Records and J.Records.Anonymise and J.Records.Anonymise(cid, token) or 0
        O.activeIndex[cid] = nil
        if J.Clock then J.Clock.Forget(cid) end
        J.Audit.Write('character', token, 'anonymised', { orders = n, closed = closed, records = m }, system)
        return { ok = true, closed = closed, orders = n, records = m, token = token }
    end)
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end -- server-only
    O.OnCharacterDeleted(citizenid)
end)
