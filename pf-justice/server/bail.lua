-- pf-justice bail (PF_ARCHITECTURE 4.7.6, state machine 5.12).
--
-- An officer (or a court) offers bail on an open custody or an incarceration order; the payer
-- accepts it standing within Config.Bail.PayerDistance of the officer who offered it, or inside a
-- Config.Bail.Desks zone (server positions), or is the prisoner. Money moves in one ledger Transfer
-- from player:<payer>:bank to society:<Config.Bail.Account> (doj: owner decision D4), keyed
-- pf-justice:bail:<bailId>:<attempt>. The attempt number and key are written before the transfer,
-- so a crash leaves the key on the row:
--   paid       -> posted: the custody is released ('bailed') and a bailed order is vacated;
--   refused    -> back to offered (a new attempt uses a new numbered key);
--   unclear    -> payment_pending; the sweep looks the key up (GetTransaction) and never charges
--                 again under a new key until it settles.
-- Exoneration refunds the payer once (pf-justice:bail:<bailId>:refund, numbered after a clear
-- failure); forfeiture keeps the money with the city.

PFJustice = PFJustice or {}
PFJustice.Bail = PFJustice.Bail or {}
local Bail = PFJustice.Bail
PFJustice.CustodyKit = PFJustice.CustodyKit or {} -- filled by custody.lua; looked up when called
local K = PFJustice.CustodyKit

local OPEN = { 'offered', 'accepted', 'payment_pending' }
local BAIL_COLUMNS = { state = true, payer_cid = true, payer_name = true, pay_attempt = true, pay_key = true, posted_at = true,
    closed_at = true, expires_at = true }

Bail.SQL = {
    insert = [[INSERT INTO pf_justice_bail (citizenid, custody_id, order_id, amount, conditions, state, payer_cid, offered_by,
        offered_at, expires_at, legacy_ref) VALUES (?, ?, ?, ?, ?, 'offered', ?, ?, ?, ?, ?)]],
    byId = 'SELECT * FROM pf_justice_bail WHERE id = ? LIMIT 1',
    openForCustody = "SELECT * FROM pf_justice_bail WHERE custody_id = ? AND state IN ('offered', 'accepted', 'payment_pending', 'posted') ORDER BY id DESC LIMIT 1",
    openForOrder = "SELECT * FROM pf_justice_bail WHERE order_id = ? AND state IN ('offered', 'accepted', 'payment_pending', 'posted') ORDER BY id DESC LIMIT 1",
    latestOf = [[SELECT * FROM pf_justice_bail WHERE citizenid = ?
        ORDER BY (state IN ('offered', 'accepted', 'payment_pending')) DESC, id DESC LIMIT 1]],
    -- payments and refunds to settle, offers to expire, and posted bail whose release has not
    -- happened yet (its custody or order is still open)
    due = [[SELECT b.* FROM pf_justice_bail b WHERE (b.state IN ('accepted', 'payment_pending')
        OR (b.state = 'exonerated' AND b.pay_key IS NOT NULL) OR (b.state = 'offered' AND b.expires_at < ?)
        OR (b.state = 'posted' AND (
            (b.custody_id IS NOT NULL AND EXISTS (SELECT 1 FROM pf_justice_custody c WHERE c.id = b.custody_id AND c.closed_at IS NULL))
            OR (b.order_id IS NOT NULL AND EXISTS (SELECT 1 FROM pf_justice_orders o WHERE o.id = b.order_id
                AND o.state IN ('active', 'pending', 'suspended')))))
        ) AND b.id > ? ORDER BY b.id ASC LIMIT 50]],
    -- why an order was vacated (the newest 'vacated' event); 15B writes { from, to, reason }
    orderVacate = "SELECT detail FROM pf_justice_order_events WHERE order_id = ? AND action = 'vacated' ORDER BY id DESC LIMIT 1",
    openOfCitizen = "SELECT * FROM pf_justice_bail WHERE citizenid = ? AND state IN ('offered', 'accepted', 'payment_pending')",
}

local function one(sql, params)
    local r = K.db('single', sql, params)
    return type(r) == 'table' and r.id and r or nil
end

Bail.Store = {
    insert = function(row)
        return tonumber(K.dbv('insert', Bail.SQL.insert, { row.citizenid, row.custody_id, row.order_id, row.amount, row.conditions,
            row.payer_cid, row.offered_by, row.offered_at, row.expires_at, row.legacy_ref }))
    end,
    get = function(id) return one(Bail.SQL.byId, { id }) end,
    openFor = function(field, id) return one(field == 'custody_id' and Bail.SQL.openForCustody or Bail.SQL.openForOrder, { id }) end,
    latestOf = function(cid) return one(Bail.SQL.latestOf, { cid }) end,
    --- due rows after `afterId` (the sweep walks the whole set page by page, so rows it must leave
    --- for later never hide newer ones)
    due = function(now, afterId) return K.db('query', Bail.SQL.due, { now, afterId or 0 }) or {} end,
    orderVacateReason = function(orderId)
        local r = K.db('single', Bail.SQL.orderVacate, { orderId })
        local d = type(r) == 'table' and K.decode(r.detail)
        return type(d) == 'table' and d.reason or nil
    end,
    openOfCitizen = function(cid) return K.db('query', Bail.SQL.openOfCitizen, { cid }) or {} end,
    --- Compare-and-set from `fromState`. True when the row changed.
    cas = function(id, fromState, fields)
        local set, params = K.setClause(fields, BAIL_COLUMNS)
        params[#params + 1] = id
        params[#params + 1] = fromState
        return K.affected(K.db('update', ('UPDATE pf_justice_bail SET %s WHERE id = ? AND state = ?'):format(set), params)) == 1
    end,
}

function Bail.PayKey(id, attempt) return ('pf-justice:bail:%d:%d'):format(id, attempt) end
function Bail.RefundKey(id, attempt)
    if (attempt or 1) <= 1 then return ('pf-justice:bail:%d:refund'):format(id) end
    return ('pf-justice:bail:%d:refund:%d'):format(id, attempt)
end
local function refundAttempt(key)
    if type(key) ~= 'string' then return 0 end
    local n = key:match(':refund:(%d+)$')
    if n then return tonumber(n) end
    if key:match(':refund$') then return 1 end
    return 0
end

local function account() return 'society:' .. tostring(K.cfg('Bail', 'Account', 'doj')) end

function Bail.Public(b)
    if not b then return nil end
    return {
        id = tonumber(b.id), cid = b.citizenid, custodyId = tonumber(b.custody_id), orderId = tonumber(b.order_id),
        amount = tonumber(b.amount), conditions = K.decode(b.conditions), state = b.state, payerCid = b.payer_cid,
        payerName = b.payer_name, offeredBy = b.offered_by, offeredAt = tonumber(b.offered_at), expiresAt = tonumber(b.expires_at),
        postedAt = tonumber(b.posted_at), closedAt = tonumber(b.closed_at), legacy = b.legacy_ref ~= nil,
    }
end

local function changed(b, change)
    TriggerEvent('pf-justice:server:bailChanged', Bail.Public(b), change)
end

local function log(b, kind, data, actor)
    if b.custody_id and PFJustice.Custody then PFJustice.Custody.Log(tonumber(b.custody_id), kind, data, actor) end
    if b.order_id and PFJustice.Orders and K.callable(PFJustice.Orders.Event) then
        PFJustice.Orders.Event(tonumber(b.order_id), kind, data, actor)
    end
end

-- A bail imported from the MDT jail is paid through the MDT until 16D hands that runtime over.
local function legacyHeld(b) return K.legacyRefLive(b.legacy_ref) end

local function move(b, to, fields, actor, data)
    local okMove, err = K.can('bail', b.state, to)
    if not okMove then return nil, err end
    fields = fields or {}
    fields.state = to
    if not Bail.Store.cas(b.id, b.state, fields) then return nil, K.err('busy', 'The bail changed meanwhile; try again') end
    local from = b.state
    local new = Bail.Store.get(b.id) or b
    log(new, 'bail_' .. to, data or { from = from, bailId = tonumber(b.id) }, actor)
    changed(new, { from = from, to = to })
    return new
end

-- ── offer ────────────────────────────────────────────────────────────────────────────────────────

local function validConditions(list)
    if list == nil then return nil, true end
    if type(list) ~= 'table' or #list > 10 then return nil, false end
    local out = {}
    for _, c in ipairs(list) do
        if type(c) ~= 'table' or type(c.kind) ~= 'string' or #c.kind > 24 then return nil, false end
        out[#out + 1] = { kind = c.kind, note = K.text(c.note, 120), zone = K.text(c.zone, 48) }
    end
    return out, true
end

--- OfferBail(ref, spec, opts): ref = { custodyId } | { orderId }; spec = { amount, conditions?, payerCid? }.
function Bail.Offer(ref, spec, opts)
    opts = type(opts) == 'table' and opts or {}
    if type(ref) ~= 'table' or type(spec) ~= 'table' then return K.err('bad_args', 'ref and spec are required') end
    local custodyId = ref.custodyId ~= nil and K.int(ref.custodyId, 1) or nil
    local orderId = ref.orderId ~= nil and K.int(ref.orderId, 1) or nil
    if (custodyId == nil) == (orderId == nil) then return K.err('bad_args', 'ref needs exactly one of custodyId or orderId') end
    local amount = K.int(spec.amount, 1, tonumber(K.cfg('Bail', 'MaxAmount', 1000000)) or 1000000)
    if not amount then return K.err('bad_args', 'amount must be a whole number within the bail limit') end
    local conditions, condOk = validConditions(spec.conditions)
    if not condOk then return K.err('bad_args', 'conditions must be a list of { kind, note? }') end
    local payerCid = spec.payerCid
    if payerCid ~= nil and not K.validCid(payerCid) then return K.err('bad_args', 'payerCid is invalid') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isOfficer(actor) and not K.isCourt(actor) then return K.roleError(actor) end

    local cid, field, refId, custody
    if custodyId then
        custody = PFJustice.Custody.Store.get(custodyId)
        if not custody or custody.closed_at then return K.err('not_found', 'No open custody') end
        if custody.state == 'remanded' and not K.isCourt(actor) then return K.err('invalid_state', 'The court remanded this citizen without bail') end
        if custody.state == 'hospital' then return K.err('invalid_state', 'The citizen is in hospital') end
        cid, field, refId = custody.citizenid, 'custody_id', custodyId
    else
        local res = K.callApi('GetOrder', orderId)
        local order = type(res) == 'table' and res.order
        if not order then return K.err('not_found', 'No such order') end
        local S = PFJustice.States
        if not (S and S.IncarcerationKinds and S.IncarcerationKinds[order.kind]) or (order.state ~= 'active' and order.state ~= 'pending') then
            return K.err('invalid_state', 'Bail needs an open jail, prison or remand order')
        end
        -- an order imported from an old jail that still runs it: bail is that jail's (no double deal)
        if K.legacyRefLive(order.legacyRef or order.legacy_ref) then
            return K.err('invalid_state', 'This sentence is still run by the old jail; use its bail')
        end
        cid, field, refId = order.cid or order.citizenid, 'order_id', orderId
    end

    return K.withLock('bail:ref:' .. field .. ':' .. refId, function()
        local open = Bail.Store.openFor(field, refId)
        if open then
            if tonumber(open.amount) == amount and open.state == 'offered' and (open.payer_cid or '') == (payerCid or '') then
                return { ok = true, duplicate = true, bailId = tonumber(open.id) }
            end
            return { ok = false, error = 'conflict', message = 'Bail is already ' .. open.state .. ' for this', bailId = tonumber(open.id) }
        end
        local t = K.now()
        local id = Bail.Store.insert({ citizenid = cid, custody_id = custodyId, order_id = orderId, amount = amount,
            conditions = K.encode(conditions), payer_cid = payerCid, offered_by = actor.cid or K.actorCid(actor), offered_at = t,
            expires_at = t + (tonumber(K.cfg('Bail', 'OfferSeconds', 600)) or 600) })
        if not id then return K.err('db_unavailable', 'The bail offer could not be saved') end
        local b = Bail.Store.get(id)
        log(b, 'bail_offered', { bailId = id, amount = amount, payerCid = payerCid }, actor)
        changed(b, { from = nil, to = 'offered' })
        local payerSrc = payerCid and K.srcOf(payerCid)
        if payerSrc then
            K.notify(payerSrc, ('Bail of $%d was offered for %s; pay it with an officer or at a bail desk'):format(amount, cid), 'primary')
        end
        return { ok = true, bailId = id }
    end)
end

-- ── payment ──────────────────────────────────────────────────────────────────────────────────────

--- Payer place: the prisoner themselves, within PayerDistance of the offering officer, or at a desk.
function Bail.PayerPlaceOk(b, payerSrc, payerCid)
    if payerCid == b.citizenid then return true end
    local pos = K.coords(payerSrc)
    if not pos then return false end
    local officer = b.offered_by and K.srcOf(b.offered_by)
    if officer and officer ~= payerSrc and K.dist(pos, K.coords(officer)) <= (tonumber(K.cfg('Bail', 'PayerDistance', 5.0)) or 5.0) then
        return true
    end
    for _, desk in ipairs(K.cfg('Bail', 'Desks', {}) or {}) do
        if K.inZone(pos, desk) then return true end
    end
    return false
end

local OPEN_ORDER = { active = true, pending = true }
local retryLogged = {} -- bail id -> true once a failed release was logged (the sweep retries quietly)

--- Whether the custody or order of a bail can still be bailed: 'open', 'closed' (it ended, a
--- sentence took the citizen over, or a court remanded them after this offer: the offer is dead and
--- a payment still settling goes back to the payer), or 'wait' (not now: hospital, escaped, or the
--- record could not be read).
function Bail.RefStatus(b)
    if b.custody_id then
        local Custody = PFJustice.Custody
        local c = Custody.Store.get(tonumber(b.custody_id))
        if not c or c.closed_at then return 'closed', c end
        -- a holding-cell jail keeps the custody open: the sentence holds them, not the custody
        if Custody.LinkedOrder(c.id) then return 'closed', c end
        if c.state == 'remanded' then
            local at = Custody.RemandedAt(c.id)
            if not at or (tonumber(b.offered_at) or 0) < at then return 'closed', c end
        end
        if c.state == 'hospital' then return 'wait', c end
        return 'open', c
    end
    if b.order_id then
        local res = K.callApi('GetOrder', tonumber(b.order_id))
        if type(res) ~= 'table' then return 'wait' end
        if not res.ok then return res.error == 'not_found' and 'closed' or 'wait' end
        local state = res.order and res.order.state
        if OPEN_ORDER[state] then return 'open', res.order end
        if state == 'suspended' then return 'wait', res.order end
        return 'closed', res.order
    end
    return 'closed'
end

--- The reason pf-justice vacates an order for this bail (checked afterwards: only this vacate counts).
function Bail.VacateReason(id) return 'bail:' .. tostring(id) end

local function vacatedByThisBail(b)
    local fn = Bail.Store.orderVacateReason
    local reason = K.callable(fn) and fn(tonumber(b.order_id)) or nil
    return reason == Bail.VacateReason(b.id)
end

--- Bail posted: release the custody ('bailed') or vacate the bailed order.
--- Returns 'done', 'retry' (the release did not happen now: the sweep tries again while the custody
--- or order is open) or 'void' (it had already ended some other way: the money goes back).
function Bail.Release(b)
    local system = { kind = 'system', label = 'bail' }
    local status, ref = Bail.RefStatus(b)
    local result
    if b.custody_id then
        if status == 'closed' then
            -- done only when this bail released them; anything else (no charges, a sentence, a remand) is void
            result = (ref and ref.closed_at and ref.release_reason == 'bailed') and 'done' or 'void'
        else
            local res = PFJustice.Custody.Release(tonumber(b.custody_id), 'bailed', { actor = system })
            result = (type(res) == 'table' and res.ok) and 'done' or 'retry'
        end
    elseif b.order_id then
        if status == 'closed' then
            -- an order vacated by an appeal, a court or an admin is not this bail's release
            result = (ref and ref.state == 'vacated' and vacatedByThisBail(b)) and 'done' or 'void'
        else
            local fn = PFJustice.Orders and PFJustice.Orders.SetState
            local why = Bail.VacateReason(b.id)
            local res
            if K.callable(fn) then res = fn(tonumber(b.order_id), 'vacated', { reason = why, actor = system })
            else res = K.callApi('SetOrderState', tonumber(b.order_id), 'vacated', { reason = why, actor = system }) end
            result = (type(res) == 'table' and res.ok) and 'done' or 'retry'
        end
    else
        result = 'void'
    end
    if result == 'done' then
        local src = K.srcOf(b.citizenid)
        if src then K.notify(src, 'Your bail was posted', 'success') end
    elseif result == 'retry' and not retryLogged[tonumber(b.id)] then
        retryLogged[tonumber(b.id)] = true
        log(b, 'bail_release_retry', { bailId = tonumber(b.id) }, nil)
    end
    return result
end

local refundNow -- defined with the refunds below

-- Posted (lock held): the release follows; a bail whose custody or order already ended some other
-- way is refunded at once (nobody keeps money for a release that cannot happen).
local function posted(b, actor)
    local new, err = move(b, 'posted', { posted_at = K.now() }, actor, { bailId = tonumber(b.id), key = b.pay_key })
    if not new then return nil, err end
    local status = Bail.Release(new)
    if status == 'void' then
        local ex = move(new, 'exonerated', { pay_key = Bail.RefundKey(new.id, 1) }, { kind = 'system', label = 'bail' },
            { bailId = tonumber(new.id), reason = 'released before the bail settled' })
        if ex then refundNow(ex, nil) end
        return Bail.Store.get(new.id) or new, nil, 'void'
    end
    return new, nil, status
end

local FAIL_TEXT = {
    insufficient_funds = 'Insufficient bank funds', bank_unavailable = 'The bank is not available; nothing was charged',
    ledger_unavailable = 'The bank is not available; nothing was charged',
}

--- AcceptBail(bailId, payerSrc, opts) -> { ok, state = 'posted' } | { ok = false, error = 'payment_unclear', state = 'payment_pending' }.
function Bail.Accept(bailId, payerSrc, opts)
    opts = type(opts) == 'table' and opts or {}
    local id = K.int(bailId, 1)
    local src = K.int(payerSrc, 1)
    if not id or not src then return K.err('bad_args', 'bailId and payerSrc are required') end
    local Payer = K.player(src)
    if not Payer then return K.err('offline', 'The payer is not online') end
    local payerCid = Payer.PlayerData.citizenid
    if not K.rate('bail:' .. src .. ':pay', 5) then return K.err('rate_limited', 'Wait a moment before paying again') end
    if not K.started('pfm-banking') then return K.err('bank_unavailable', 'The bank is not available; nothing was charged') end

    return K.withLock('bail:' .. id, function()
        local b = Bail.Store.get(id)
        if not b then return K.err('not_found', 'No such bail') end
        if b.state == 'posted' then return { ok = true, duplicate = true, state = 'posted' } end
        if b.state ~= 'offered' then return K.err('invalid_state', 'The bail is ' .. tostring(b.state)) end
        if tonumber(b.expires_at) < K.now() then
            move(b, 'expired', { closed_at = K.now() }, nil)
            return K.err('invalid_state', 'The bail offer expired')
        end
        if legacyHeld(b) then return K.err('invalid_state', 'This bail is paid through the MDT') end
        -- the custody or order may have ended since the offer: checked again under the lock
        local status = Bail.RefStatus(b)
        if status == 'closed' then
            move(b, 'expired', { closed_at = K.now() }, nil, { bailId = id, reason = 'released or sentenced meanwhile' })
            return K.err('invalid_state', 'The citizen is no longer held for this bail')
        elseif status ~= 'open' then
            return K.err('invalid_state', 'Bail cannot be paid right now')
        end
        if b.payer_cid and b.payer_cid ~= payerCid then return K.err('no_permission', 'This bail was offered to someone else') end
        if not Bail.PayerPlaceOk(b, src, payerCid) then return K.err('too_far', 'You must be with the officer or at a bail desk') end
        local attempt = (tonumber(b.pay_attempt) or 0) + 1
        local key = Bail.PayKey(id, attempt)
        local name = K.name(Payer)
        -- the key is on the row before any money moves
        local accepted, err = move(b, 'accepted', { payer_cid = payerCid, payer_name = name, pay_attempt = attempt, pay_key = key },
            { kind = 'player', cid = payerCid, src = src }, { bailId = id, attempt = attempt, key = key })
        if not accepted then return err end
        pcall(function() exports['pfm-banking']:EnsureSocietyAccount(K.cfg('Bail', 'Account', 'doj'), 'job') end)
        local res = K.transfer({ from = ('player:%s:bank'):format(payerCid), to = account(), amount = tonumber(b.amount), key = key,
            kind = 'bail', reason = ('Bail #%d for %s'):format(id, b.citizenid):sub(1, 120), actor = payerCid,
            metadata = { bailId = id, custodyId = tonumber(b.custody_id), orderId = tonumber(b.order_id) } })
        local outcome = K.outcome(res)
        if outcome == 'paid' then
            local new, perr, how = posted(accepted, { kind = 'player', cid = payerCid, src = src })
            if not new then return perr end
            if how == 'void' then
                return { ok = false, error = 'invalid_state', state = new.state, bailId = id,
                    message = 'The citizen was released before the payment settled; the bail goes back to the payer' }
            end
            local officer = b.offered_by and K.srcOf(b.offered_by)
            if officer then K.notify(officer, ('Bail #%d was posted'):format(id), 'success') end
            return { ok = true, state = 'posted', bailId = id }
        elseif outcome == 'failed' then
            move(accepted, 'offered', {}, nil, { bailId = id, attempt = attempt, refused = res.error })
            return { ok = false, error = res.error == 'insufficient_funds' and 'insufficient_funds' or 'bank_unavailable',
                message = FAIL_TEXT[res.error] or 'The payment was refused; nothing was charged', state = 'offered' }
        end
        move(accepted, 'payment_pending', {}, nil, { bailId = id, attempt = attempt, key = key })
        return { ok = false, error = 'payment_unclear', state = 'payment_pending',
            message = 'The bank is still confirming the payment; the release follows when it does' }
    end)
end

--- DeclineBail(bailId, payerSrc): the named payer (or the prisoner) refuses the offer.
function Bail.Decline(bailId, payerSrc)
    local id, src = K.int(bailId, 1), K.int(payerSrc, 1)
    if not id or not src then return K.err('bad_args', 'bailId and payerSrc are required') end
    local cid = K.cidOf(src)
    if not cid then return K.err('offline', 'The payer is not online') end
    return K.withLock('bail:' .. id, function()
        local b = Bail.Store.get(id)
        if not b then return K.err('not_found', 'No such bail') end
        if b.state ~= 'offered' then return K.err('invalid_state', 'The bail is ' .. tostring(b.state)) end
        if cid ~= b.citizenid and cid ~= b.payer_cid then return K.err('no_permission', 'This offer is not yours to decline') end
        local new, err = move(b, 'declined', { closed_at = K.now() }, { kind = 'player', cid = cid, src = src })
        if not new then return err end
        local officer = b.offered_by and K.srcOf(b.offered_by)
        if officer then K.notify(officer, ('Bail #%d was declined'):format(id), 'error') end
        return { ok = true }
    end)
end

--- GetBail(who): who = server id, citizen id, or { bailId }.
function Bail.Get(who)
    local b
    if type(who) == 'table' then
        local id = K.int(who.bailId, 1)
        if not id then return K.err('bad_args', 'bailId is invalid') end
        b = Bail.Store.get(id)
    else
        local cid = K.resolveCid(who)
        if not cid then return K.err('bad_args', 'who must be a server id or a citizen id') end
        b = Bail.Store.latestOf(cid)
    end
    return { ok = true, bail = Bail.Public(b) }
end

-- ── exoneration and forfeiture ───────────────────────────────────────────────────────────────────

-- Refunds (lock held, state 'exonerated'). The refund key is written in the same compare-and-set
-- that makes the bail 'exonerated', so only a refund key can ever settle a refund; a clear failure
-- moves to the next numbered refund key.
local function payRefund(b, actor, key)
    local res = K.transfer({ from = account(), to = ('player:%s:bank'):format(b.payer_cid), amount = tonumber(b.amount), key = key,
        kind = 'bail_refund', reason = ('Bail #%d refund'):format(b.id), actor = actor and K.actorCid(actor) or nil,
        metadata = { bailId = tonumber(b.id) } })
    return K.outcome(res), res
end

local function refunded(b, actor)
    local new = move(b, 'refunded', { closed_at = K.now() }, actor, { bailId = tonumber(b.id), key = b.pay_key })
    local payer = K.srcOf(b.payer_cid)
    if new and payer then K.notify(payer, ('Your bail of $%d was refunded'):format(tonumber(b.amount)), 'success') end
    return { ok = true, state = 'refunded' }
end

local refundRetryAt, refundStuck = {}, {} -- bail id -> next automatic retry time / audited as stuck

--- Settles or pays the refund of an exonerated bail. allowNewKey: true (a person asked again: a
--- clearly refused refund goes to the next numbered key at once), or 'auto' (the sweep: the next
--- key only after Config.Bail.RefundRetrySeconds, at most Config.Bail.MaxRefundAttempts keys; then
--- the bail is audited as stuck and waits for ExonerateBail). An unclear refund is never retried.
local function settleRefund(b, actor, allowNewKey)
    local attempt = refundAttempt(b.pay_key)
    if attempt == 0 then
        -- exonerated without a refund key (older rows): give it one before any money moves
        local key = Bail.RefundKey(b.id, 1)
        if not Bail.Store.cas(b.id, 'exonerated', { pay_key = key }) then return K.err('busy', 'The bail changed meanwhile') end
        b.pay_key, attempt = key, 1
    end
    local o = K.keyOutcome(b.pay_key)
    if o == 'paid' then return refunded(b, actor) end
    if o == 'unclear' then return { ok = false, error = 'payment_unclear', state = 'exonerated', message = 'The bank is still confirming the refund' } end
    if o == 'failed' then
        if not allowNewKey then return { ok = false, error = 'bank_unavailable', state = 'exonerated', message = 'The refund was refused' } end
        if allowNewKey == 'auto' then
            local id = tonumber(b.id)
            local cap = tonumber(K.cfg('Bail', 'MaxRefundAttempts', 5)) or 5
            if attempt >= cap then
                if not refundStuck[id] then
                    refundStuck[id] = true
                    log(b, 'bail_refund_stuck', { bailId = id, attempts = attempt, key = b.pay_key }, actor)
                    print(('^1[pf-justice]^7 bail #%d: the refund was refused %d times; ExonerateBail retries it'):format(id, attempt))
                end
                return { ok = false, error = 'bank_unavailable', state = 'exonerated', message = 'The refund keeps being refused' }
            end
            if refundRetryAt[id] and K.now() < refundRetryAt[id] then
                return { ok = false, error = 'bank_unavailable', state = 'exonerated', message = 'The refund is retried later' }
            end
        end
        local key = Bail.RefundKey(b.id, attempt + 1)
        if not Bail.Store.cas(b.id, 'exonerated', { pay_key = key }) then return K.err('busy', 'The bail changed meanwhile') end
        b.pay_key = key
    end
    if not b.payer_cid then return K.err('invalid_state', 'No payer on record') end
    local outcome, res = payRefund(b, actor, b.pay_key)
    if outcome == 'paid' then return refunded(b, actor) end
    if outcome == 'failed' then
        refundRetryAt[tonumber(b.id)] = K.now() + (tonumber(K.cfg('Bail', 'RefundRetrySeconds', 600)) or 600)
        log(b, 'bail_refund_failed', { bailId = tonumber(b.id), key = b.pay_key, error = res.error }, actor)
        return { ok = false, error = res.error == 'insufficient_funds' and 'insufficient_funds' or 'bank_unavailable', state = 'exonerated',
            message = 'The refund was refused; call ExonerateBail again to retry' }
    end
    return { ok = false, error = 'payment_unclear', state = 'exonerated', message = 'The bank is still confirming the refund' }
end
refundNow = function(b, actor) return settleRefund(b, actor, 'auto') end

--- ExonerateBail(bailId, opts): the case closed for the defendant; the payer gets the money back.
function Bail.Exonerate(bailId, opts)
    opts = type(opts) == 'table' and opts or {}
    local id = K.int(bailId, 1)
    if not id then return K.err('bad_args', 'bailId is required') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isCourt(actor) then return K.err('no_permission', 'Only a court exonerates bail') end
    if not K.started('pfm-banking') then return K.err('bank_unavailable', 'The bank is not available') end
    return K.withLock('bail:' .. id, function()
        local b = Bail.Store.get(id)
        if not b then return K.err('not_found', 'No such bail') end
        if b.state == 'refunded' then return { ok = true, duplicate = true, state = 'refunded' } end
        if b.state == 'posted' then
            local new, err = move(b, 'exonerated', { pay_key = Bail.RefundKey(id, 1) }, actor, { bailId = id, reason = K.text(opts.reason, 200) })
            if not new then return err end
            b = new
        elseif b.state ~= 'exonerated' then
            return K.err('invalid_state', 'Only posted bail can be exonerated')
        end
        refundStuck[id] = nil
        return settleRefund(b, actor, true)
    end)
end

--- ForfeitBail(bailId, opts): a violation; the money stays with the city.
function Bail.Forfeit(bailId, opts)
    opts = type(opts) == 'table' and opts or {}
    local id = K.int(bailId, 1)
    if not id then return K.err('bad_args', 'bailId is required') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isCourt(actor) then return K.err('no_permission', 'Only a court forfeits bail') end
    return K.withLock('bail:' .. id, function()
        local b = Bail.Store.get(id)
        if not b then return K.err('not_found', 'No such bail') end
        if b.state == 'forfeited' then return { ok = true, duplicate = true } end
        local new, err = move(b, 'forfeited', { closed_at = K.now() }, actor, { bailId = id, reason = K.text(opts.reason, 200) })
        if not new then return err end
        return { ok = true }
    end)
end

-- ── sweep ────────────────────────────────────────────────────────────────────────────────────────

local seenPending = {} -- bail id -> first time the sweep saw it unsettled (a call may still be in flight)
local sweepCursor = 0  -- the sweep pages through the due rows by id

--- Settles accepted / payment_pending payments and exoneration refunds from the ledger, and
--- expires old offers. Bail imported from the MDT is left to the MDT while it runs its jail.
function Bail.Tick(now)
    now = now or K.now()
    if not K.ready() then return 0 end
    local hold = tonumber(K.cfg('Bail', 'PaymentHoldSeconds', 120)) or 120
    local n = 0
    local rows = Bail.Store.due(now, sweepCursor)
    -- the next sweep starts after this page; a short page means the end, so it starts over
    sweepCursor = #rows >= 50 and tonumber(rows[#rows].id) or 0
    for _, row in ipairs(rows) do
        local id = tonumber(row.id)
        -- an expired offer is closed even when it came from the MDT (nobody can pay it any more)
        local expiredOffer = row.state == 'offered' and tonumber(row.expires_at) < now
        if (expiredOffer or not legacyHeld(row)) and not K.locked('bail:' .. id) then
            K.withLock('bail:' .. id, function()
                local b = Bail.Store.get(id)
                if not b then return end
                if b.state == 'offered' then
                    if tonumber(b.expires_at) < now then
                        move(b, 'expired', { closed_at = now }, nil)
                        n = n + 1
                    end
                    return
                end
                if b.state == 'posted' then
                    -- the release did not happen when it was posted (a lock, a failed write): again
                    local how = Bail.Release(b)
                    if how == 'void' then
                        local ex = move(b, 'exonerated', { pay_key = Bail.RefundKey(id, 1) }, nil, { bailId = id, reason = 'released some other way' })
                        if ex then refundNow(ex, nil) end
                    end
                    n = n + 1
                    return
                end
                if not b.pay_key then return end
                if b.state == 'exonerated' then
                    -- only a refund key settles a refund; an interrupted refund is paid under its own key
                    local res = settleRefund(b, nil, 'auto')
                    if res.ok then n = n + 1 end
                    return
                end
                seenPending[id] = seenPending[id] or now
                if now - seenPending[id] < hold then return end
                local o = K.keyOutcome(b.pay_key)
                if o == 'paid' then
                    if b.state == 'accepted' then
                        local p = move(b, 'payment_pending', {}, nil)
                        b = p or b
                    end
                    if posted(b, nil) then n = n + 1 end
                    seenPending[id] = nil
                elseif o == 'failed' or o == 'none' then
                    if b.state == 'accepted' then b = move(b, 'payment_pending', {}, nil) or b end
                    move(b, 'offered', { expires_at = math.max(tonumber(b.expires_at) or now, now + 60) }, nil,
                        { bailId = id, settled = o, key = b.pay_key })
                    seenPending[id] = nil
                    n = n + 1
                end
            end)
        end
    end
    return n
end

--- Ends the open offer of a custody or order that closed (lock-free when the bail is busy: a
--- payment in progress checks the custody / order again under its own lock).
function Bail.ExpireFor(field, refId, why)
    if (field ~= 'custody_id' and field ~= 'order_id') or not K.int(refId, 1) then return 0 end
    local b = Bail.Store.openFor(field, refId)
    if not b or b.state ~= 'offered' or K.locked('bail:' .. b.id) then return 0 end
    local res = K.withLock('bail:' .. b.id, function()
        local row = Bail.Store.get(b.id)
        if row and row.state == 'offered' then
            return move(row, 'expired', { closed_at = K.now() }, nil, { bailId = tonumber(row.id), reason = why }) and 1 or 0
        end
        return 0
    end)
    return tonumber(res) or 0
end

--- An incarceration order ended (completed, vacated, revoked): its bail offer ends with it.
function Bail.OnOrderChanged(order)
    if type(order) ~= 'table' then return end
    local S = PFJustice.States
    if not (S and S.IncarcerationKinds and S.IncarcerationKinds[order.kind]) then return end
    if OPEN_ORDER[order.state] or order.state == 'suspended' then return end
    Bail.ExpireFor('order_id', tonumber(order.id or order.orderId), 'order ' .. tostring(order.state))
end

AddEventHandler('pf-justice:server:orderChanged', function(order)
    local ok, err = pcall(Bail.OnOrderChanged, order)
    if not ok then print(('^1[pf-justice]^7 bail orderChanged: %s'):format(tostring(err))) end
end)

--- Character deleted: open offers end (nobody can pay them any more).
function Bail.OnCharacterDeleted(cid)
    if not K.validCid(cid) then return end
    for _, b in ipairs(Bail.Store.openOfCitizen(cid)) do
        if b.state == 'offered' then Bail.Store.cas(b.id, 'offered', { state = 'expired', closed_at = K.now() }) end
    end
end

CreateThread(function()
    while true do
        Wait(15000)
        local ok, err = pcall(Bail.Tick)
        if not ok then print(('^1[pf-justice]^7 bail sweep: %s'):format(tostring(err))) end
    end
end)

K.export('OfferBail', function(ref, spec, opts) return Bail.Offer(ref, spec, opts) end)
K.export('AcceptBail', function(id, payerSrc, opts) return Bail.Accept(id, payerSrc, opts) end)
K.export('DeclineBail', function(id, payerSrc) return Bail.Decline(id, payerSrc) end)
K.export('GetBail', function(who) return Bail.Get(who) end)
K.export('ExonerateBail', function(id, opts) return Bail.Exonerate(id, opts) end)
K.export('ForfeitBail', function(id, opts) return Bail.Forfeit(id, opts) end)
