-- pf-justice exports of unit 15B (PF_ARCHITECTURE 4.7.1). Each export checks the calling resource
-- against Config.Callers first (GetInvokingResource; pf-justice itself always passes) and passes the
-- invoker on, so results are filtered per Config.OrderFields / Config.RecordFields. Custody, booking,
-- property and bail exports are registered by their own files (15C) with the same check
-- (PFJustice.Callers.Check).
--
-- Server-only events (AddEventHandler only):
--   pf-justice:server:orderCreated(order)              once per new order
--   pf-justice:server:orderChanged(order, change)      every state change, credit, forfeit, modify
--   pf-justice:server:releaseOrdered(cid, orderId, reason)  once, when no open incarceration is left
--   pf-justice:server:paymentSettled(order, state)     'paid', 'failed' when an unclear payment settled as refused, or
--                                                      'refunded' when a phone invoice paid after its order stopped
--                                                      waiting for it was paid back to the payer
--   pf-justice:server:recordChanged(cid, change)       a record entry was added or expunged
-- Client event: pf-justice:client:Sentence(summary | nil) to the inmate on each whole-minute change.

PFJustice = PFJustice or {}
local J = PFJustice
local O = J.Orders
local R = J.Records

local function guard(name)
    local allowed, res = J.Callers.Check(name, GetInvokingResource())
    if not allowed then return nil, res end
    return { invoker = res }
end

local function filterOrder(order, invoker)
    return J.Callers.Filter(order, J.Callers.FieldRule(Config.OrderFields, invoker))
end

-- A write export: allowlist, then the module function with the invoker.
local function writer(name, fn)
    exports(name, function(...)
        local ctx, err = guard(name)
        if not ctx then return err end
        return fn(ctx, ...)
    end)
end

writer('CreateOrder', function(ctx, spec, opts) return O.Create(spec, opts, ctx) end)
writer('AdjustOrder', function(ctx, orderId, change, opts) return O.Adjust(orderId, change, opts, ctx) end)
writer('SetOrderState', function(ctx, orderId, to, opts) return O.SetState(orderId, to, opts, ctx) end)
writer('ReleaseNow', function(ctx, who, reason, opts) return O.ReleaseNow(who, reason, opts, ctx) end)
writer('IssueCitation', function(ctx, spec, opts) return O.IssueCitation(spec, opts, ctx) end)
writer('ContestCitation', function(ctx, orderId, opts) return O.ContestCitation(orderId, opts, ctx) end)
writer('DecideCitation', function(ctx, orderId, upheld, opts) return O.DecideCitation(orderId, upheld, opts, ctx) end)
writer('PayOrder', function(ctx, orderId, opts) return O.Pay(orderId, opts, ctx) end)
writer('AddRecordEntry', function(ctx, cid, entry, opts) return R.Add(cid, entry, opts, ctx) end)
writer('Expunge', function(ctx, cid, entryIds, opts) return R.Expunge(cid, entryIds, opts, ctx) end)
writer('GetRecord', function(ctx, cid, opts) return R.Get(cid, opts, ctx) end)

writer('GetOrder', function(ctx, orderId)
    local res = O.Get(orderId)
    if res.ok then res.order = filterOrder(res.order, ctx.invoker) end
    return res
end)

writer('GetOrders', function(ctx, cid, filter)
    local res = O.List(cid, filter)
    if res.ok then
        for i, order in ipairs(res.list) do res.list[i] = filterOrder(order, ctx.invoker) end
    end
    return res
end)

writer('GetActiveIncarceration', function(ctx, who)
    local res = O.GetActiveIncarceration(who)
    if res.ok and res.order then res.order = filterOrder(res.order, ctx.invoker) end
    return res
end)

-- The same functions for other modules of this resource (15C custody, bail, compat): no allowlist,
-- no field filter, pf-justice acts as itself. Never hand this table to another resource.
J.API = {
    CreateOrder = function(spec, opts) return O.Create(spec, opts, {}) end,
    GetOrder = function(orderId) return O.Get(orderId) end,
    GetOrders = function(cid, filter) return O.List(cid, filter) end,
    GetActiveIncarceration = function(who) return O.GetActiveIncarceration(who) end,
    IsIncarcerated = function(who) return O.IsIncarcerated(who) end,
    GetJailMinutes = function(who) return O.GetJailMinutes(who) end,
    AdjustOrder = function(orderId, change, opts) return O.Adjust(orderId, change, opts, {}) end,
    SetOrderState = function(orderId, to, opts) return O.SetState(orderId, to, opts, {}) end,
    ReleaseNow = function(who, reason, opts) return O.ReleaseNow(who, reason, opts, {}) end,
    IssueCitation = function(spec, opts) return O.IssueCitation(spec, opts, {}) end,
    PayOrder = function(orderId, opts) return O.Pay(orderId, opts, {}) end,
    GetRecord = function(cid, opts) return R.Get(cid, opts, {}) end,
    AddRecordEntry = function(cid, entry, opts) return R.Add(cid, entry, opts, {}) end,
    Expunge = function(cid, entryIds, opts) return R.Expunge(cid, entryIds, opts, {}) end,
}

-- Plain-value exports (legacy-shaped callers such as pfm-prison GetJailTime read them directly).
exports('IsIncarcerated', function(who)
    if not guard('IsIncarcerated') then return false end
    return O.IsIncarcerated(who)
end)

exports('GetJailMinutes', function(who)
    if not guard('GetJailMinutes') then return 0 end
    return O.GetJailMinutes(who)
end)
