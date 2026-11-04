-- pf-justice property lockers (PF_ARCHITECTURE 4.7.5).
--
-- Seized items move into the stash pf_justice_property_<receiptId> through pfm-inventory's own
-- exports; pf_justice_property_items is the receipt (what was taken, as recorded at seizure).
--   * Seizure: the receipt rows are written first, the inventory is read again until it matches
--     them, then items are added to the locker and taken from the player with no wait in between;
--     any failed step is rolled back (the player keeps everything, the receipt is removed).
--   * Return adds items back without clearing what the player holds now (the MDT release used to
--     clear the inventory first); what does not fit stays in the locker and comes back at the next
--     load. Taking from the locker happens before giving, so nothing can be doubled.
--   * Forfeiture moves listed items into pfm-policejob evidence (CreateEvidence, 15D).
--
-- Receipt states: held | returning (release ordered, delivery pending) | returned |
-- partially_returned | forfeited | legacy (a receipt imported from a legacy jail whose runtime still
-- holds the items itself in batch 15; legacy_import.lua turns it into held or returned).

PFJustice = PFJustice or {}
PFJustice.Property = PFJustice.Property or {}
local Property = PFJustice.Property
PFJustice.CustodyKit = PFJustice.CustodyKit or {} -- filled by custody.lua; looked up when called
local K = PFJustice.CustodyKit

local function prefix() return K.cfg('Property', 'StashPrefix', 'pf_justice_property_') end
function Property.StashId(id) return prefix() .. tostring(id) end

-- ── store ────────────────────────────────────────────────────────────────────────────────────────

local PROPERTY_COLUMNS = { state = true, order_id = true, returned_at = true, stash_id = true, reason = true }

Property.SQL = {
    insert = [[INSERT INTO pf_justice_property (citizenid, custody_id, order_id, stash_id, state, reason, seized_by, seized_at,
        idem_key, legacy_ref) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    setStash = 'UPDATE pf_justice_property SET stash_id = ? WHERE id = ?',
    byId = 'SELECT * FROM pf_justice_property WHERE id = ? LIMIT 1',
    byKey = 'SELECT * FROM pf_justice_property WHERE idem_key = ? LIMIT 1',
    byLegacy = 'SELECT * FROM pf_justice_property WHERE legacy_ref = ? LIMIT 1',
    delete = 'DELETE FROM pf_justice_property WHERE id = ?',
    addItem = 'INSERT INTO pf_justice_property_items (property_id, item, amount, info, state) VALUES (?, ?, ?, ?, ?)',
    items = 'SELECT * FROM pf_justice_property_items WHERE property_id = ? ORDER BY id ASC',
    deleteItems = 'DELETE FROM pf_justice_property_items WHERE property_id = ?',
    setItemState = 'UPDATE pf_justice_property_items SET state = ?, evidence_id = ? WHERE id = ? AND state = ?',
    linkOrder = "UPDATE pf_justice_property SET order_id = ? WHERE custody_id = ? AND order_id IS NULL AND state = 'held'",
}

local function inList(states)
    local marks = {}
    for i = 1, #states do marks[i] = '?' end
    return table.concat(marks, ', ')
end

local function one(sql, params)
    local r = K.db('single', sql, params)
    return type(r) == 'table' and r.id and r or nil
end

Property.Store = {
    insert = function(row)
        return tonumber(K.dbv('insert', Property.SQL.insert, { row.citizenid, row.custody_id, row.order_id, row.stash_id, row.state,
            row.reason, row.seized_by, row.seized_at, row.idem_key, row.legacy_ref }))
    end,
    setStash = function(id, stash) return K.affected(K.db('update', Property.SQL.setStash, { stash, id })) == 1 end,
    get = function(id) return one(Property.SQL.byId, { id }) end,
    byKey = function(key) return one(Property.SQL.byKey, { key }) end,
    byLegacy = function(ref) return one(Property.SQL.byLegacy, { ref }) end,
    delete = function(id) K.db('query', Property.SQL.delete, { id }) end,
    addItem = function(propertyId, item, amount, info, state)
        return tonumber(K.dbv('insert', Property.SQL.addItem, { propertyId, item, amount, K.encode(info), state or 'held' }))
    end,
    items = function(propertyId) return K.db('query', Property.SQL.items, { propertyId }) or {} end,
    deleteItems = function(propertyId) local _, ok = K.db('query', Property.SQL.deleteItems, { propertyId }) return ok end,
    setItemState = function(itemId, fromState, toState, evidenceId)
        return K.affected(K.db('update', Property.SQL.setItemState, { toState, evidenceId, itemId, fromState })) == 1
    end,
    --- Compare-and-set from one of `fromStates`. True when the row changed.
    cas = function(id, fromStates, fields)
        local set, params = K.setClause(fields, PROPERTY_COLUMNS)
        params[#params + 1] = id
        for _, s in ipairs(fromStates) do params[#params + 1] = s end
        local sql = ('UPDATE pf_justice_property SET %s WHERE id = ? AND state IN (%s)'):format(set, inList(fromStates))
        return K.affected(K.db('update', sql, params)) == 1
    end,
    forField = function(field, value, states)
        local params = { value }
        for _, s in ipairs(states) do params[#params + 1] = s end
        local sql = ('SELECT * FROM pf_justice_property WHERE %s = ? AND state IN (%s) ORDER BY id ASC LIMIT 50'):format(field, inList(states))
        return K.db('query', sql, params) or {}
    end,
    linkOrder = function(custodyId, orderId) K.db('update', Property.SQL.linkOrder, { orderId, custodyId }) end,
}

function Property.Store.forCustody(custodyId, states) return Property.Store.forField('custody_id', custodyId, states) end
function Property.Store.forOrder(orderId, states) return Property.Store.forField('order_id', orderId, states) end
function Property.Store.forCitizen(cid, states) return Property.Store.forField('citizenid', cid, states) end

-- ── inventory ────────────────────────────────────────────────────────────────────────────────────

--- The player's items as the server holds them: { name, amount, slot, info } per slot.
local function readItems(src)
    local P = K.player(src)
    local out = {}
    for _, it in pairs(P and P.PlayerData.items or {}) do
        local amount = type(it) == 'table' and K.int(it.amount, 1)
        if amount and type(it.name) == 'string' then
            out[#out + 1] = { name = it.name, amount = amount, slot = K.int(it.slot, 1), info = type(it.info) == 'table' and it.info or nil }
        end
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out
end
Property.ReadItems = readItems

local function same(a, b) return K.canon(a) == K.canon(b) end

local function ensureStash(stash, id)
    local _, ok = K.inv('CreateInventory', stash, { label = ('Property locker #%s'):format(tostring(id)),
        maxweight = tonumber(K.cfg('Property', 'StashWeight', 250000)) or 250000, slots = tonumber(K.cfg('Property', 'StashSlots', 60)) or 60 })
    return ok
end
Property.EnsureStash = ensureStash

--- The locker's items: { name, amount, slot, info }.
function Property.LockerItems(stash)
    local inv = K.inv('GetInventory', stash)
    local out = {}
    for _, it in pairs(type(inv) == 'table' and type(inv.items) == 'table' and inv.items or {}) do
        local amount = type(it) == 'table' and K.int(it.amount, 1)
        if amount and type(it.name) == 'string' then
            out[#out + 1] = { name = it.name, amount = amount, slot = K.int(it.slot, 1), info = type(it.info) == 'table' and it.info or nil }
        end
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out, type(inv) == 'table'
end

-- Which items to take: everything except the kept names, or the listed slots (checked against the
-- inventory: a list can never take more than the player holds).
local function selectItems(all, opts)
    local keep = {}
    for _, n in ipairs(K.cfg('Property', 'Keep', {}) or {}) do keep[n] = true end
    for _, n in ipairs(type(opts.keep) == 'table' and opts.keep or {}) do if type(n) == 'string' then keep[n] = true end end
    local out = {}
    if opts.items == nil or opts.items == 'all' then
        for _, it in ipairs(all) do if not keep[it.name] then out[#out + 1] = it end end
        return out, next(keep) == nil
    end
    local bySlot = {}
    for _, it in ipairs(all) do if it.slot then bySlot[it.slot] = it end end
    for _, want in ipairs(opts.items) do
        local slot = type(want) == 'table' and K.int(want.slot, 1)
        local have = slot and bySlot[slot]
        if not have or have.name ~= want.name then return nil end
        local amount = want.amount == nil and have.amount or K.int(want.amount, 1, have.amount)
        if not amount then return nil end
        out[#out + 1] = { name = have.name, amount = amount, slot = have.slot, info = have.info }
        bySlot[slot] = nil
    end
    return out, false
end

-- Takes `items` from the player into the locker. No wait happens in here (export calls only).
-- Returns true, or false after undoing every step.
local function move(src, stash, items, clearAll, reason)
    local added = {}
    for _, it in ipairs(items) do
        local ok = K.inv('AddItem', stash, it.name, it.amount, nil, it.info, reason)
        if ok ~= true then
            for _, a in ipairs(added) do K.inv('RemoveItem', stash, a.name, a.amount, nil, 'pf-justice:property:rollback') end
            return false, 'The property locker could not take ' .. tostring(it.name)
        end
        added[#added + 1] = it
    end
    if clearAll then
        local _, ok = K.inv('ClearInventory', src)
        if ok then return true end
    else
        local removed, failed = {}, false
        for _, it in ipairs(items) do
            if K.inv('RemoveItem', src, it.name, it.amount, it.slot, reason) == true then removed[#removed + 1] = it
            else failed = true break end
        end
        if not failed then return true end
        for _, r in ipairs(removed) do K.inv('AddItem', src, r.name, r.amount, r.slot, r.info, 'pf-justice:property:rollback') end
    end
    for _, a in ipairs(added) do K.inv('RemoveItem', stash, a.name, a.amount, nil, 'pf-justice:property:rollback') end
    return false, 'The items could not be taken; nothing was seized'
end

-- ── API ──────────────────────────────────────────────────────────────────────────────────────────

local function publicReceipt(r, items)
    local list = {}
    for _, it in ipairs(items or {}) do
        list[#list + 1] = { id = tonumber(it.id), name = it.item, amount = tonumber(it.amount), info = K.decode(it.info), state = it.state,
            evidenceId = tonumber(it.evidence_id) }
    end
    return { id = tonumber(r.id), cid = r.citizenid, custodyId = tonumber(r.custody_id), orderId = tonumber(r.order_id),
        state = r.state, lockerStash = r.stash_id, reason = r.reason, seizedBy = r.seized_by, seizedAt = tonumber(r.seized_at),
        returnedAt = tonumber(r.returned_at), items = list }
end

--- SeizeProperty(target, opts): opts = { custodyId, orderId?, keep = { 'phone' }?, items = 'all' |
--- { { name, slot, amount } }, reason, key, actor }. Returns { ok, receiptId, items = n }.
function Property.Seize(target, opts)
    opts = type(opts) == 'table' and opts or {}
    local src = K.int(target, 1)
    if not src then return K.err('bad_args', 'target must be a server id') end
    local P = K.player(src)
    if not P then return K.err('offline', 'The citizen is not online') end
    local cid = P.PlayerData.citizenid
    local key = opts.key
    if key ~= nil and not K.validKey(key) then return K.err('bad_args', 'key must be 1-128 characters of [A-Za-z0-9-_:.]') end
    if opts.items ~= nil and opts.items ~= 'all' and (type(opts.items) ~= 'table' or #opts.items == 0 or #opts.items > 100) then
        return K.err('bad_args', "items must be 'all' or a list of { name, slot, amount }")
    end
    local custodyId = opts.custodyId ~= nil and K.int(opts.custodyId, 1) or nil
    local orderId = opts.orderId ~= nil and K.int(opts.orderId, 1) or nil
    if (opts.custodyId ~= nil and not custodyId) or (opts.orderId ~= nil and not orderId) then return K.err('bad_args', 'Bad custodyId or orderId') end
    local reason = K.text(opts.reason, 128)
    local actor, actorErr = opts.actorResolved, nil
    if not actor then actor, actorErr = K.actor(opts) end
    if not actor then return actorErr end
    if not K.isOfficer(actor) then return K.roleError(actor) end
    if actor.kind == 'player' and PFJustice.Custody and not PFJustice.Custody.OfficerPresent(actor, src) then
        return K.err('too_far', 'You must be with the citizen')
    end
    if custodyId then
        local c = PFJustice.Custody.Store.get(custodyId)
        if not c or c.citizenid ~= cid or c.closed_at then return K.err('invalid_state', 'No open custody of this citizen') end
    end
    if not K.started('pfm-inventory') then return K.err('db_unavailable', 'The inventory is not running; nothing was seized') end

    return K.withLock('property:cid:' .. cid, function()
        if key then
            local existing = Property.Store.byKey(key)
            if existing then
                if existing.citizenid ~= cid then return K.err('key_reused', 'This key was used for another receipt') end
                return { ok = true, duplicate = true, receiptId = tonumber(existing.id), items = #Property.Store.items(existing.id) }
            end
        end
        local items, clearAll = selectItems(readItems(src), opts)
        if not items then return K.err('bad_args', 'The listed items are not in the inventory') end
        if #items > (tonumber(K.cfg('Property', 'MaxItems', 200)) or 200) then return K.err('bad_args', 'Too many items for one receipt') end
        local t = K.now()
        local id = Property.Store.insert({ citizenid = cid, custody_id = custodyId, order_id = orderId,
            stash_id = ('%spending_%d_%d'):format(prefix(), t, math.random(100000, 999999)), state = 'held', reason = reason,
            seized_by = actor.cid or K.actorCid(actor), seized_at = t, idem_key = key })
        if not id then return K.err('db_unavailable', 'The receipt could not be saved; nothing was seized') end
        local stash = Property.StashId(id)
        local function abort(msg)
            Property.Store.deleteItems(id)
            Property.Store.delete(id)
            return K.err('db_unavailable', msg)
        end
        if not Property.Store.setStash(id, stash) then return abort('The receipt could not be saved; nothing was seized') end
        -- the receipt is written before anything moves; the inventory is read again until it
        -- matches the receipt, and the move follows that read with no wait (MDT S.Jail pattern)
        local stable = false
        for _ = 1, 3 do
            Property.Store.deleteItems(id)
            for _, it in ipairs(items) do
                if not Property.Store.addItem(id, it.name, it.amount, it.info, 'held') then return abort('The receipt could not be saved; nothing was seized') end
            end
            local again = selectItems(readItems(src), opts)
            if again and same(again, items) then stable = true break end
            if not again then return abort('The listed items are no longer in the inventory') end
            items = again
        end
        if not stable then return abort('The inventory kept changing; try again') end
        if not ensureStash(stash, id) then return abort('The property locker could not be opened; nothing was seized') end
        local moved, why = move(src, stash, items, clearAll, 'pf-justice:property:' .. id)
        if not moved then return abort(why) end
        K.inv('SaveStash', stash)
        if custodyId then
            PFJustice.Custody.Log(custodyId, 'property_seized', { receiptId = id, items = #items }, actor)
        end
        if #items > 0 then K.notify(src, ('Your belongings were taken into a property locker (receipt #%d, %d items)'):format(id, #items), 'error') end
        return { ok = true, receiptId = id, items = #items }
    end)
end

--- GetPropertyReceipt(receiptId, opts): opts.viewer = src limits it to the owner or an officer.
function Property.GetReceipt(receiptId, opts)
    local id = K.int(receiptId, 1)
    if not id then return K.err('bad_args', 'receiptId must be a positive integer') end
    local r = Property.Store.get(id)
    if not r then return K.err('not_found', 'No such receipt') end
    local viewer = type(opts) == 'table' and K.int(opts.viewer, 1) or nil
    if viewer then
        local cid = K.cidOf(viewer)
        if cid ~= r.citizenid then
            local actor = K.actor({ actor = { src = viewer } })
            if not K.isOfficer(actor) then return K.err('not_found', 'No such receipt') end
        end
    end
    return { ok = true, receipt = publicReceipt(r, Property.Store.items(id)) }
end

-- After a delivery: rows still covered by what is left in the locker stay held, the rest returned.
local function settleRows(r, left)
    local remaining = {}
    for _, it in ipairs(left) do remaining[it.name] = (remaining[it.name] or 0) + it.amount end
    local returned, kept = 0, {}
    for _, row in ipairs(Property.Store.items(r.id)) do
        if row.state == 'held' then
            local amount = tonumber(row.amount) or 0
            if (remaining[row.item] or 0) >= amount then
                remaining[row.item] = remaining[row.item] - amount
                kept[#kept + 1] = { name = row.item, amount = amount }
            elseif Property.Store.setItemState(row.id, 'held', 'returned', nil) then
                returned = returned + 1
            end
        end
    end
    return returned, kept
end

--- Moves the locker into the online player's inventory without clearing it. Taking from the
--- locker comes first: an item that cannot be given goes back into the locker.
local function deliver(src, r)
    local stash = r.stash_id
    if not ensureStash(stash, r.id) then return nil end
    local items, present = Property.LockerItems(stash)
    if not present then return nil end
    local given = 0
    for _, it in ipairs(items) do
        local fits = K.inv('CanAddItem', src, it.name, it.amount)
        if fits == true and K.inv('RemoveItem', stash, it.name, it.amount, it.slot, 'pf-justice:property:return') == true then
            if K.inv('AddItem', src, it.name, it.amount, nil, it.info, 'pf-justice:property:return') == true then
                given = given + 1
            else
                K.inv('AddItem', stash, it.name, it.amount, nil, it.info, 'pf-justice:property:kept')
            end
        end
    end
    K.inv('SaveStash', stash)
    local left = Property.LockerItems(stash)
    return given, left
end

--- Finishes a receipt in 'returning' for its online owner. Returns the result table.
function Property.Deliver(r, src)
    local given, left = deliver(src, r)
    if given == nil then return { ok = true, returned = 0, pending = true, kept = {} } end
    local _, kept = settleRows(r, left)
    local final = #left == 0 and 'returned' or 'partially_returned'
    Property.Store.cas(r.id, { 'returning' }, { state = final, returned_at = K.now() })
    if #left > 0 then
        K.notify(src, 'Some of your belongings did not fit; they stay in the property locker until you have room', 'error')
    elseif given > 0 then
        K.notify(src, ('Your belongings were returned (%d)'):format(given), 'success')
    end
    return { ok = true, returned = given, kept = kept, state = final }
end

--- ReturnProperty(receiptId, opts): opts = { toSrc, key, actor }. Gives the locker back to its owner.
--- An offline owner gets it at the next load. A player actor must be an on-duty officer (prison
--- and system callers act as themselves).
function Property.Return(receiptId, opts)
    opts = type(opts) == 'table' and opts or {}
    local id = K.int(receiptId, 1)
    if not id then return K.err('bad_args', 'receiptId must be a positive integer') end
    if opts.key ~= nil and not K.validKey(opts.key) then return K.err('bad_args', 'Bad key') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isOfficer(actor) then return K.roleError(actor) end
    return K.withLock('property:' .. id, function()
        local r = Property.Store.get(id)
        if not r then return K.err('not_found', 'No such receipt') end
        if r.state == 'returned' or r.state == 'forfeited' then return { ok = true, duplicate = true, returned = 0, kept = {}, state = r.state } end
        if r.state == 'legacy' then return K.err('invalid_state', 'These items are still held by the legacy jail') end
        local src = K.srcOf(r.citizenid)
        if opts.toSrc ~= nil then
            local to = K.int(opts.toSrc, 1)
            if not to or K.cidOf(to) ~= r.citizenid then return K.err('bad_args', 'toSrc must be the owner of the receipt') end
            src = to
        end
        if r.state ~= 'returning' and not Property.Store.cas(id, { 'held', 'partially_returned' }, { state = 'returning' }) then
            return K.err('invalid_state', 'The receipt changed meanwhile')
        end
        r.state = 'returning'
        if not src then return { ok = true, returned = 0, pending = true, kept = {} } end
        return Property.Deliver(r, src)
    end)
end

--- Custody released: its receipts (not tied to a sentence) go back now or at the next load.
function Property.ReleaseForCustody(custodyId, cid)
    for _, r in ipairs(Property.Store.forCustody(custodyId, { 'held', 'partially_returned' })) do
        if not r.order_id then Property.Return(r.id, {}) end
    end
end

--- A sentence started from a custody: its receipts now wait for that order's release.
function Property.LinkOrder(custodyId, orderId) Property.Store.linkOrder(custodyId, orderId) end

--- An order was released: its receipts come back.
function Property.OnReleaseOrdered(cid, orderId)
    local id = K.int(orderId, 1)
    if not id then return end
    for _, r in ipairs(Property.Store.forOrder(id, { 'held', 'partially_returned' })) do
        if r.citizenid == cid then Property.Return(r.id, {}) end
    end
end

--- At load: deliveries that could not finish (offline release, a full inventory, a restart).
function Property.OnPlayerLoaded(src)
    local cid = K.cidOf(src)
    if not cid then return 0 end
    local n = 0
    for _, r in ipairs(Property.Store.forCitizen(cid, { 'returning', 'partially_returned' })) do
        local res = Property.Return(r.id, { toSrc = src })
        if type(res) == 'table' and res.ok then n = n + (res.returned or 0) end
    end
    return n
end

local function evidenceKind(name)
    local items = {}
    pcall(function() items = exports['pfm-core']:GetShared('Items') or {} end)
    local def = type(items) == 'table' and items[name] or nil
    if type(def) == 'table' and def.type == 'weapon' then return 'weapon' end
    return 'item'
end

-- The attrs each evidence kind takes (pfm-policejob config_evidence.lua Kinds).
local function evidenceAttrs(kind, item, amount, info)
    if kind == 'weapon' then return { item = item, serial = type(info) == 'table' and (info.serie or info.serial) or nil } end
    return { item = item, amount = amount }
end
Property.EVIDENCE_METHOD = 'seizure' -- one of pfm-policejob Config.Evidence.Methods

--- ForfeitPropertyItems(receiptId, items, opts): items = { { id = rowId } } (or { { name } }, the
--- first held row of that item). The rows move into evidence; the rest of the locker is untouched.
function Property.Forfeit(receiptId, items, opts)
    opts = type(opts) == 'table' and opts or {}
    local id = K.int(receiptId, 1)
    if not id then return K.err('bad_args', 'receiptId must be a positive integer') end
    if type(items) ~= 'table' or #items == 0 or #items > 50 then return K.err('bad_args', 'items must list receipt rows') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isOfficer(actor) then return K.roleError(actor) end
    -- physical evidence goes to the collecting officer or to the named inventory ('stash:<id>' / a server id)
    if actor.kind ~= 'player' and opts.giveTo == nil then return K.err('bad_args', 'giveTo is required without an officer') end
    if not K.started('pfm-policejob') then return K.err('db_unavailable', 'Evidence is not available; nothing was forfeited') end
    return K.withLock('property:' .. id, function()
        local r = Property.Store.get(id)
        if not r then return K.err('not_found', 'No such receipt') end
        if r.state ~= 'held' and r.state ~= 'partially_returned' then return K.err('invalid_state', 'Only held property can be forfeited') end
        local rows, picked = Property.Store.items(id), {}
        for _, want in ipairs(items) do
            local found
            for _, row in ipairs(rows) do
                if row.state == 'held' and not picked[row.id] and ((type(want) == 'table' and tonumber(want.id) == tonumber(row.id))
                    or (type(want) == 'table' and want.id == nil and want.name == row.item)) then found = row break end
            end
            if not found then return K.err('not_found', 'A listed item is not held on this receipt') end
            picked[found.id] = found
        end
        if not ensureStash(r.stash_id, r.id) then return K.err('db_unavailable', 'The property locker could not be opened') end
        local evidenceIds = {}
        for rowId, row in pairs(picked) do
            local amount = tonumber(row.amount) or 1
            local info = K.decode(row.info)
            if K.inv('RemoveItem', r.stash_id, row.item, amount, nil, 'pf-justice:property:forfeit') ~= true then
                return { ok = false, error = 'not_found', message = row.item .. ' is not in the locker', evidenceIds = evidenceIds }
            end
            local kind = evidenceKind(row.item)
            local ok, res = pcall(function()
                return exports['pfm-policejob']:CreateEvidence({
                    kind = kind, label = (row.item .. ' x' .. amount):sub(1, 64),
                    attrs = evidenceAttrs(kind, row.item, amount, info),
                    collectedBy = actor.kind == 'player' and actor.src or nil, method = Property.EVIDENCE_METHOD, sealed = true,
                    origin = { type = 'property', id = tostring(r.id) },
                    caseRef = r.custody_id and { type = 'custody', id = tostring(r.custody_id) } or nil,
                }, { key = ('pf-justice:property:%d:%d'):format(r.id, tonumber(rowId)), giveTo = opts.giveTo })
            end)
            if not ok or type(res) ~= 'table' or not res.ok or not tonumber(res.evidenceId) then
                -- no evidence record: the item goes back into the locker (nothing disappears)
                K.inv('AddItem', r.stash_id, row.item, amount, nil, info, 'pf-justice:property:forfeit_undo')
                return { ok = false, error = (type(res) == 'table' and res.error) or 'db_unavailable',
                    message = 'Evidence could not be created; the item stays in the locker', evidenceIds = evidenceIds }
            end
            Property.Store.setItemState(row.id, 'held', 'forfeited', tonumber(res.evidenceId))
            evidenceIds[#evidenceIds + 1] = tonumber(res.evidenceId)
        end
        K.inv('SaveStash', r.stash_id)
        local anyHeld = false
        for _, row in ipairs(Property.Store.items(id)) do if row.state == 'held' then anyHeld = true break end end
        if not anyHeld then Property.Store.cas(id, { 'held', 'partially_returned' }, { state = 'forfeited' }) end
        if r.custody_id then PFJustice.Custody.Log(r.custody_id, 'property_forfeit', { receiptId = id, evidenceIds = evidenceIds }, actor) end
        return { ok = true, evidenceIds = evidenceIds }
    end)
end

--- Character deleted: lockers of a character that no longer exists are emptied and closed.
function Property.OnCharacterDeleted(cid)
    if not K.validCid(cid) then return end
    for _, r in ipairs(Property.Store.forCitizen(cid, { 'held', 'returning', 'partially_returned', 'legacy' })) do
        K.inv('ClearStash', r.stash_id)
        Property.Store.cas(r.id, { r.state }, { state = 'forfeited', reason = 'character deleted' })
    end
end

K.export('SeizeProperty', function(target, opts) return Property.Seize(target, opts) end)
K.export('GetPropertyReceipt', function(id, opts) return Property.GetReceipt(id, opts) end)
K.export('ReturnProperty', function(id, opts) return Property.Return(id, opts) end)
K.export('ForfeitPropertyItems', function(id, items, opts) return Property.Forfeit(id, items, opts) end)
