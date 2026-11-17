-- pf-justice restitution paid by another resource on the ledger (19A follow-up for 19E prison economy).
--
-- pfm-prison moves an inmate's restitution share from its trust escrow straight to the victim with a keyed
-- ledger Transfer, then reports it here:
--   exports['pf-justice']:RecordRestitution(orderId, { amount, ledgerKey, from = 'system:pfm-prison-trust' },
--       { key = ledgerKey, actor })
--   -> { ok = true, orderId, applied, paidAmount, state, settled }       credited (applied <= what was still owed)
--   -> { ok = true, duplicate = true, ... }                              the same key again: nothing credited twice
--   -> { ok = false, error = 'pending' }                                 the ledger has not settled the key yet:
--                                                                        retry later with the SAME key
--   -> { ok = false, error = 'bad_args' | 'not_found' | 'invalid_state' | 'busy' | 'key_reused' | 'ledger_failed'
--         | 'amount_mismatch' | 'payee_mismatch' | 'source_mismatch' | 'bank_unavailable' | 'db_unavailable' }
-- Nothing is credited unless the ledger shows the key completed, for that amount, from that source, to the
-- order's payee (player:<victim>:bank, the account PayOrder pays restitution to). The order event carrying the
-- key is written before paid_amount changes (a crash in between is a duplicate on retry, never a second credit).
-- A fully paid order settles to 'paid' through the order state machine (record entry, paymentSettled).
-- orderId 0 (pfm-prison's probe) is refused with bad_args before any lock or query.

PFJustice = PFJustice or {}
PFJustice.Restitution = PFJustice.Restitution or {}
local J = PFJustice
local Rs = J.Restitution
local U = J.Util
local Err = J.Result.Err

Rs.SQL = {
    eventByKey = 'SELECT * FROM pf_justice_order_events WHERE idem_key = ? LIMIT 1',
    deleteEvent = 'DELETE FROM pf_justice_order_events WHERE idem_key = ?',
    credit = [[UPDATE pf_justice_orders SET paid_amount = ?, updated_at = ? WHERE id = ? AND state = ? AND paid_amount = ?]],
}
local SQL = Rs.SQL

-- States a restitution credit may land in (the payable states of the fine machine; a payment or phone
-- invoice in flight must settle first).
local CREDITABLE = { issued = true, overdue = true, referred = true }

--- The ledger account restitution is paid to (orders.lua payTarget).
function Rs.Payee(row) return ('player:%s:bank'):format(tostring(row.victim_cid)) end

local function one(sql, params)
    local ok, row = pcall(MySQL.single.await, sql, params or {})
    if not ok then return nil, false end
    if type(row) == 'table' and row[1] and row.id == nil then row = row[1] end
    if type(row) ~= 'table' or next(row) == nil then return nil, true end
    return row, true
end

--- Reads the ledger transaction of `key`: tx | nil, err.
local function ledgerTx(key)
    if GetResourceState('pfm-banking') ~= 'started' then return nil, Err('bank_unavailable', 'The bank is not available') end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
    if not ok then return nil, Err('pending', 'The ledger did not answer; retry with the same key') end
    if type(tx) ~= 'table' or tx.tx_id == nil and tx.state == nil then return nil, Err('not_found', 'No ledger transaction has this key') end
    return tx
end

function Rs.Record(orderId, spec, opts, ctx)
    -- the probe and every argument error answer before any lock or query
    local id = U.Int(orderId, 1, 2147483647)
    if not id then return Err('bad_args', 'orderId must be a positive integer') end
    if type(spec) ~= 'table' then return Err('bad_args', 'spec must be a table') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local amount = U.Int(spec.amount, 1, Config.Fines.MaxAmount)
    if not amount then return Err('bad_args', 'amount must be a positive whole number') end
    local key = opts.key or spec.ledgerKey
    if not U.ValidKey(key) or (spec.ledgerKey ~= nil and spec.ledgerKey ~= key) then
        return Err('bad_args', 'opts.key must be the ledger key (spec.ledgerKey)')
    end
    local from = spec.from
    if from ~= nil and (type(from) ~= 'string' or #from > 96) then return Err('bad_args', 'from is invalid') end
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end

    -- the order lock (and the citizen's) is taken before the first query
    return J.Orders.WithOrder(id, function(row)
        local ev, okq = one(SQL.eventByKey, { key })
        if not okq then return Err('db_unavailable', 'The justice database did not answer') end
        if ev then
            local d = U.Decode(ev.detail) or {}
            if tonumber(ev.order_id) ~= id or ev.action ~= 'restitution' or tonumber(d.amount) ~= amount then
                return Err('key_reused', 'This key was recorded for a different payment')
            end
            return { ok = true, duplicate = true, orderId = id, applied = tonumber(d.applied) or 0,
                paidAmount = tonumber(row.paid_amount) or 0, state = row.state }
        end
        if row.kind ~= 'restitution' then return Err('bad_args', 'The order is not a restitution order') end
        if not CREDITABLE[row.state] then
            if row.state == 'payment_pending' or row.state == 'invoiced' then
                return Err('busy', 'A payment of this order is in flight (' .. row.state .. '); retry with the same key')
            end
            return Err('invalid_state', 'The order is ' .. tostring(row.state))
        end
        local tx, terr = ledgerTx(key)
        if not tx then return terr end
        local state = tx.state
        if state == 'pending' or state == 'debited' then return Err('pending', 'The ledger has not settled this payment yet') end
        if state ~= 'completed' then return Err('ledger_failed', 'The ledger payment is ' .. tostring(state)) end
        if math.abs((tonumber(tx.amount) or -1) - amount) > 0.001 then return Err('amount_mismatch', 'The ledger moved a different amount') end
        if tx.to_account ~= Rs.Payee(row) then return Err('payee_mismatch', 'The ledger paid someone other than the victim') end
        if from ~= nil and tx.from_account ~= from then return Err('source_mismatch', 'The ledger paid from another account') end

        local paid, owed = tonumber(row.paid_amount) or 0, tonumber(row.amount) or 0
        local applied = math.max(0, math.min(amount, owed - paid))
        local okEv, evErr = J.Orders.Event(id, 'restitution', { amount = amount, applied = applied, key = key, from = tx.from_account,
            to = tx.to_account, tx = tx.tx_id }, actor, key)
        if not okEv then
            if evErr == 'duplicate' then return { ok = true, duplicate = true, orderId = id, paidAmount = paid, state = row.state } end
            return Err('db_unavailable', 'The payment could not be recorded; retry with the same key')
        end
        local now = os.time()
        local okUp, res = pcall(MySQL.update.await, SQL.credit, { paid + applied, now, id, row.state, paid })
        if not okUp or U.Affected(res) ~= 1 then
            pcall(MySQL.update.await, SQL.deleteEvent, { key })
            return Err('busy', 'The order changed meanwhile; retry with the same key')
        end
        row.paid_amount = paid + applied
        local settled = false
        if row.paid_amount >= owed then
            local okMove = J.Orders.MoveLocked(row, 'paid', 'restitution paid', actor, { key = key })
            settled = okMove == true
            if settled then J.Emit('paymentSettled', J.Orders.Public(row), 'paid') end
        else
            J.Emit('orderChanged', J.Orders.Public(row), { action = 'restitution', applied = applied })
        end
        return { ok = true, orderId = id, applied = applied, paidAmount = row.paid_amount, state = row.state, settled = settled }
    end)
end

exports('RecordRestitution', function(orderId, spec, opts)
    local allowed, res = J.Callers.Check('RecordRestitution', GetInvokingResource())
    if not allowed then return res end
    return Rs.Record(orderId, spec, opts, { invoker = res })
end)
