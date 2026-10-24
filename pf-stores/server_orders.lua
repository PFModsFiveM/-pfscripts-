-- ============================================================================
-- PF supply orders: the one order service for business supplies.
--
-- Orders live in pf_store_supply_orders (the table pf-stores already had), extended by the migrations
-- below. Any business type can order through it by registering a buyer kind (pf-stores registers
-- 'store'; pf-restaurants registers 'restaurant'). The same order id is used by the computer app, the
-- supplier, the pf-trucking contract (SUP-<id>), the delivery pallet and the unpacking.
--
-- Delivery lifecycle (every change is a guarded UPDATE ... WHERE status = <from>, logged in
-- pf_supply_order_events):
--   created -> paid -> awaiting_supplier -> awaiting_delivery -> assigned -> in_transit -> delivered -> unpacked
--   created -> failed                     (payment did not go through)
--   paid | awaiting_supplier | awaiting_delivery -> cancelled   (refunded from escrow)
--   assigned | in_transit -> awaiting_delivery                    (driver released or timed out)
-- Pickup lifecycle: created -> paid -> ready -> delivered -> unpacked (or straight through when instant).
--
-- Money (pfm-banking ledger, fixed keys per order so every step pays once):
--   buyer account -> escrow            supply:<id>:charge     subtotal + AI markup
--   escrow -> driver (pf-trucking)     freight:supply:<id>    player driver, or system:pf-stores-freight for AI
--   escrow -> supplier                 supply:<id>:supplier   goods share (subtotal - freight)
--   escrow -> AI supplier / refund     supply:<id>:markup...  AI markup, or split when a player supplies
--   escrow -> buyer                    supply:<id>:cancel     cancellation refund
-- ============================================================================

PFOrders = PFOrders or { kinds = {} }
local O = PFOrders
O.NULL = O.NULL or setmetatable({}, { __tostring = function() return 'NULL' end }) -- sets a column to NULL in Transition

local ESCROW_NAME = 'freight_escrow'
local ESCROW = 'society:' .. ESCROW_NAME
local AI_SUPPLIER = 'system:pf-stores-supplier'
local AI_FREIGHT = 'system:pf-stores-freight'

local function cfg()
    local c = (Config and Config.SupplyChain) or {}
    return {
        aiMarkup = tonumber(c.AIMarkup) or 0.15,
        supplierShareOfMarkup = tonumber(c.PlayerSupplierShareOfMarkup) or 0.5,
        supplierOfferSeconds = tonumber(c.SupplierOfferSeconds) or 120,
        driverPrioritySeconds = tonumber(c.DriverPrioritySeconds) or 300,
        driverMaxSeconds = tonumber(c.DriverMaxSeconds) or 3600,
        aiDeliverySeconds = tonumber(c.AIDeliverySeconds) or 600,
        playerSuppliers = c.PlayerSuppliers ~= false,
        palletModel = c.PalletModel or 'prop_boxpile_06b',
    }
end

local function nowMs() return math.floor(os.time() * 1000) end
local function round2(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end

local function bankReady()
    if GetResourceState('pfm-banking') ~= 'started' then return false end
    local ok, ready = pcall(function() return exports['pfm-banking']:IsLedgerReady() end)
    return ok and ready == true
end

local function transfer(opts)
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

local function ensureEscrow()
    local ok, exists = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(ESCROW_NAME, 'business') end)
    return ok and exists == true
end

local function decode(jsonText)
    local ok, v = pcall(json.decode, jsonText or '')
    return ok and v or nil
end

-- ── schema ──────────────────────────────────────────────────────────────────

O.Migrations = {
    {
        version = 1,
        name = 'supply order lifecycle, status history, suppliers',
        up = function()
            local add = {
                { 'freight_payout', 'DECIMAL(12,2) NULL' },  -- also added by ensureTables on older installs
                { 'buyer_kind', "VARCHAR(16) NOT NULL DEFAULT 'store'" },
                { 'buyer_ref', 'VARCHAR(96) NULL' },
                { 'subtotal', 'DECIMAL(12,2) NULL' },
                { 'ai_markup', 'DECIMAL(12,2) NOT NULL DEFAULT 0' },
                { 'payment_tx', 'VARCHAR(32) NULL' },
                { 'payment_state', 'VARCHAR(16) NULL' },
                { 'supplier_kind', 'VARCHAR(16) NULL' },
                { 'supplier_ref', 'VARCHAR(96) NULL' },
                { 'supplier_deadline', 'BIGINT NULL' },
                { 'driver_kind', 'VARCHAR(16) NULL' },
                { 'driver_ref', 'VARCHAR(64) NULL' },
                { 'driver_deadline', 'BIGINT NULL' },
                { 'assigned_at', 'BIGINT NULL' },
                { 'in_transit_at', 'BIGINT NULL' },
                { 'ai_eta', 'BIGINT NULL' },
                { 'unpacked_at', 'BIGINT NULL' },
                { 'cancelled_at', 'BIGINT NULL' },
                { 'settled', 'TINYINT NOT NULL DEFAULT 0' },
                { 'pallet_id', 'VARCHAR(48) NULL' },
            }
            for _, col in ipairs(add) do
                if not MigrationColumnExists('pf_store_supply_orders', col[1]) then
                    MySQL.query.await(('ALTER TABLE pf_store_supply_orders ADD COLUMN `%s` %s'):format(col[1], col[2]))
                end
            end
            if not MigrationIndexExists('pf_store_supply_orders', 'idx_status') then
                MySQL.query.await('ALTER TABLE pf_store_supply_orders ADD INDEX idx_status (status)')
            end
            MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_supply_order_events (
                id BIGINT NOT NULL AUTO_INCREMENT,
                order_id INT NOT NULL,
                from_status VARCHAR(32) NULL,
                to_status VARCHAR(32) NOT NULL,
                actor VARCHAR(64) NULL,
                note VARCHAR(255) NULL,
                at BIGINT NOT NULL,
                PRIMARY KEY (id),
                INDEX idx_order (order_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
            MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_suppliers (
                id INT NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(64) NOT NULL,
                name VARCHAR(64) NOT NULL,
                active TINYINT NOT NULL DEFAULT 1,
                created_at BIGINT NOT NULL,
                PRIMARY KEY (id),
                UNIQUE KEY uq_citizen (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
            MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_supplier_offers (
                supplier_id INT NOT NULL,
                item VARCHAR(128) NOT NULL,
                unit_price DECIMAL(12,2) NOT NULL,
                stock_qty INT NOT NULL DEFAULT 0,
                PRIMARY KEY (supplier_id, item)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
            -- statuses from before the lifecycle existed
            MySQL.update.await("UPDATE pf_store_supply_orders SET status = 'ready', supplier_kind = 'ai' WHERE status = 'ordered'")
            MySQL.update.await("UPDATE pf_store_supply_orders SET status = 'awaiting_delivery', supplier_kind = 'ai', supplier_ref = ?, settled = 0 WHERE status = 'outsource_posted'", { AI_SUPPLIER })
            -- delivered orders already had their stock added and supplier paid by the old code
            MySQL.update.await("UPDATE pf_store_supply_orders SET status = 'unpacked', settled = 1 WHERE status = 'delivered'")
        end,
    },
}

-- ── buyer kinds ─────────────────────────────────────────────────────────────
-- adapter = {
--   canManage(src, buyerId) -> bool          may order, cancel and unpack for this business
--   account(buyerId) -> ledger ref           pays for orders, receives refunds
--   ensureAccount(buyerId) -> bool
--   price(buyerId, cart) -> lines, subtotal  server catalog prices: lines {name, label, quantity, cost, category}
--   route(buyerId) -> { pickup = {label, coords}, dropoff = {label, coords}, trucking = cfg } | nil
--   unpack(buyerId, lines, orderId) -> bool  adds the goods to the business's stock (called once)
-- }
function O.RegisterBuyerKind(kind, adapter)
    assert(type(kind) == 'string' and type(adapter) == 'table', 'RegisterBuyerKind(kind, adapter)')
    O.kinds[kind] = adapter
end

-- ── orders ──────────────────────────────────────────────────────────────────

local ORDER_COLUMNS = [[id, store_id, buyer_kind, buyer_ref, owner_citizenid, method, status, total, subtotal, ai_markup,
    items_json, created_at, delivered_at, freight_payout, payment_tx, payment_state, supplier_kind, supplier_ref,
    supplier_deadline, driver_kind, driver_ref, driver_deadline, assigned_at, in_transit_at, ai_eta, unpacked_at,
    cancelled_at, settled, pallet_id, external_contract_id]]

function O.Get(orderId)
    return MySQL.single.await('SELECT ' .. ORDER_COLUMNS .. ' FROM pf_store_supply_orders WHERE id = ? LIMIT 1', { tonumber(orderId) })
end

local function logEvent(orderId, from, to, actor, note)
    MySQL.insert.await('INSERT INTO pf_supply_order_events (order_id, from_status, to_status, actor, note, at) VALUES (?, ?, ?, ?, ?, ?)',
        { orderId, from, to, actor and tostring(actor):sub(1, 64) or nil, note and tostring(note):sub(1, 255) or nil, nowMs() })
end

--- Moves an order from one status to another, only if it is still in `from`. Extra columns are set
--- in the same UPDATE. Returns true when this call made the change.
function O.Transition(orderId, from, to, actor, note, set)
    local sql, params = 'UPDATE pf_store_supply_orders SET status = ?', { to }
    for col, value in pairs(set or {}) do
        if value == O.NULL then
            sql = sql .. (', `%s` = NULL'):format(col)
        else
            sql = sql .. (', `%s` = ?'):format(col)
            params[#params + 1] = value
        end
    end
    sql = sql .. ' WHERE id = ? AND status = ?'
    params[#params + 1] = orderId
    params[#params + 1] = from
    local changed = MySQL.update.await(sql, params)
    if changed and changed > 0 then
        logEvent(orderId, from, to, actor, note)
        return true
    end
    return false
end

local function key(orderId, part) return ('supply:%d:%s'):format(orderId, part) end

local function freightPayout(trucking, subtotal)
    trucking = trucking or {}
    local payout
    local rate = tonumber(trucking.payoutRate or 0) or 0
    if rate > 0 then payout = math.floor((tonumber(subtotal) or 0) * rate + 0.5) else payout = tonumber(trucking.payout or 0) or 0 end
    if (tonumber(trucking.payoutMin) or 0) > 0 then payout = math.max(payout, tonumber(trucking.payoutMin)) end
    if (tonumber(trucking.payoutMax) or 0) > 0 then payout = math.min(payout, tonumber(trucking.payoutMax)) end
    return round2(math.max(0, math.min(payout, tonumber(subtotal) or 0)))
end

local function citizenOf(src)
    local Player = exports['pfm-core']:GetPlayer(src)
    return Player and Player.PlayerData.citizenid or nil
end

-- ── trucking contracts ──────────────────────────────────────────────────────

local function contractId(orderId) return ('SUP-%d'):format(orderId) end

--- Posts the order's pf-trucking contract (or re-posts it after a restart, with its driver).
function O.PostContract(order, restoreDriver)
    local adapter = O.kinds[order.buyer_kind]
    local route = adapter and adapter.route(order.store_id)
    if not route or GetResourceState('pf-trucking') ~= 'started' then return nil end
    local lines = decode(order.items_json) or {}
    local qty = 0
    for _, l in ipairs(lines) do qty = qty + (tonumber(l.quantity) or 0) end
    local trucking = route.trucking or {}
    local job = {
        id = contractId(order.id),
        kind = 'external',
        title = trucking.title or 'Business Supplies',
        cargoType = trucking.cargoType or 'Supplies',
        cargoQuantity = qty,
        pickup = route.pickup.label or 'Pickup',
        dropoff = route.dropoff.label or 'Dropoff',
        distanceMi = 0.0,
        payout = tonumber(order.freight_payout) or 0,
        requiredTrailer = trucking.requiredTrailer,
        trailerSpawn = route.pickup.coords,
        stops = {
            { label = 'Stop 1 – Pickup', kind = 'Pickup', location = route.pickup.label or 'Pickup', coords = route.pickup.coords },
            { label = 'Stop 2 – Delivery', kind = 'Delivery', location = route.dropoff.label or 'Dropoff', coords = route.dropoff.coords },
        },
        createdAt = tonumber(order.created_at),
        externalType = 'pf-supply:order',
        externalPayload = { orderId = tonumber(order.id), buyerKind = order.buyer_kind, buyerId = order.store_id },
        payFrom = ESCROW,
        payKey = ('freight:supply:%d'):format(order.id),
    }
    if restoreDriver and order.driver_kind == 'player' and order.driver_ref then
        job.assignedCitizenId = order.driver_ref
        job.assignedAt = tonumber(order.assigned_at)
        job.loaded = order.status == 'in_transit'
    end
    local ok, id = pcall(function() return exports['pf-trucking']:CreateExternalJob(job) end)
    return ok and id or nil
end

-- ── settlement ──────────────────────────────────────────────────────────────

-- A player supplier earns part of the AI markup; the rest goes back to the buyer. Fixed keys.
local function splitMarkup(order)
    local markup = tonumber(order.ai_markup) or 0
    if markup <= 0 or order.supplier_kind ~= 'player' or not order.supplier_ref then return true end
    local toSupplier = round2(markup * math.max(0, math.min(1, cfg().supplierShareOfMarkup)))
    local refund = round2(markup - toSupplier)
    local ok = true
    if toSupplier > 0 then
        ok = transfer({ from = ESCROW, to = ('player:%s:bank'):format(order.supplier_ref), amount = toSupplier, key = key(order.id, 'markup-supplier'), kind = 'supplies', reason = 'Supplier bonus' }).ok and ok
    end
    if refund > 0 then
        ok = transfer({ from = ESCROW, to = order.buyer_ref, amount = refund, key = key(order.id, 'markup-refund'), kind = 'refund', reason = 'Player supplier: AI markup refunded' }).ok and ok
    end
    return ok
end

local function supplierAccount(order)
    if order.supplier_kind == 'player' and order.supplier_ref then
        return ('player:%s:bank'):format(order.supplier_ref)
    end
    return AI_SUPPLIER
end

--- Pays the supplier (and the AI markup) for a delivered order. Every transfer has a fixed key, so it
--- is safe to call again after a crash; `settled` is set only when all of them went through.
function O.Settle(order)
    if tonumber(order.settled) == 1 then return true end
    local subtotal = tonumber(order.subtotal) or tonumber(order.total) or 0
    local freight = tonumber(order.freight_payout) or 0
    local markup = tonumber(order.ai_markup) or 0
    local okAll = true
    local goods = round2(subtotal - freight)
    if goods > 0 then
        local r = transfer({ from = ESCROW, to = supplierAccount(order), amount = goods, key = key(order.id, 'supplier'), kind = 'supplies', reason = 'Supply order delivered' })
        okAll = okAll and r.ok
    end
    if markup > 0 and order.supplier_kind ~= 'player' then
        local r = transfer({ from = ESCROW, to = AI_SUPPLIER, amount = markup, key = key(order.id, 'markup'), kind = 'supplies', reason = 'AI supply markup' })
        okAll = okAll and r.ok
    end
    okAll = splitMarkup(order) and okAll
    if okAll then
        MySQL.update.await('UPDATE pf_store_supply_orders SET settled = 1 WHERE id = ?', { order.id })
    end
    return okAll
end

-- ── delivery objects ────────────────────────────────────────────────────────

local function createPallet(order)
    if order.pallet_id or GetResourceState('pfm-worldobjects') ~= 'started' then return nil end
    local adapter = O.kinds[order.buyer_kind]
    local route = adapter and adapter.route(order.store_id)
    local spot = route and (route.unload or route.dropoff)
    if not spot or not spot.coords then return nil end
    local contents = {}
    for _, l in ipairs(decode(order.items_json) or {}) do
        contents[#contents + 1] = { item = 'supply_crate', amount = 1, info = { supply = l.name, label = l.label or l.name, cases = l.quantity, orderId = order.id } }
    end
    local ok, objectId = pcall(function()
        return exports['pfm-worldobjects']:CreateDeliveryObject({
            orderId = order.id, ownerRef = order.buyer_kind .. ':' .. order.store_id, model = cfg().palletModel,
            coords = spot.coords, heading = spot.coords.w or 0.0, contents = contents,
        })
    end)
    if ok and objectId then
        MySQL.update.await('UPDATE pf_store_supply_orders SET pallet_id = ? WHERE id = ? AND pallet_id IS NULL', { objectId, order.id })
        return objectId
    end
    return nil
end

--- Unpacks a delivered order into the business's stock, once. Called by the pallet (pfm-worldobjects)
--- or directly when no pallet is used. `src` must be allowed to manage the buying business.
function O.Unpack(src, orderId, actor)
    local order = O.Get(orderId)
    if not order then return { ok = false, error = 'order_not_found' } end
    local adapter = O.kinds[order.buyer_kind]
    if not adapter then return { ok = false, error = 'unknown_buyer' } end
    if src and not adapter.canManage(src, order.store_id) then return { ok = false, error = 'not_authorized' } end
    if not O.Transition(order.id, 'delivered', 'unpacked', actor or (src and citizenOf(src)), 'unpacked', { unpacked_at = nowMs() }) then
        return { ok = false, error = 'not_unpackable' }
    end
    local ok, done = pcall(adapter.unpack, order.store_id, decode(order.items_json) or {}, order.id)
    if not (ok and done) then
        -- put it back so it can be unpacked again; nothing was added
        O.Transition(order.id, 'unpacked', 'delivered', 'system', 'unpack failed: ' .. tostring(done))
        return { ok = false, error = 'unpack_failed' }
    end
    return { ok = true, data = { orderId = order.id } }
end

--- Marks an order delivered (from in_transit/assigned), settles the money and puts down its pallet.
local function deliver(order, from, actor, note)
    if not O.Transition(order.id, from, 'delivered', actor, note, { delivered_at = nowMs() }) then return false end
    order = O.Get(order.id)
    O.Settle(order)
    if not createPallet(order) and GetResourceState('pfm-worldobjects') ~= 'started' then
        -- no physical pallet available: the goods go straight into stock
        O.Unpack(nil, order.id, 'system')
    end
    return true
end

-- ── creating, cancelling ────────────────────────────────────────────────────

local function suppliersFor(lines)
    if not cfg().playerSuppliers then return {} end
    local candidates = nil
    for _, l in ipairs(lines) do
        local rows = MySQL.query.await([[SELECT o.supplier_id FROM pf_supplier_offers o JOIN pf_suppliers s ON s.id = o.supplier_id
            WHERE s.active = 1 AND o.item = ? AND o.stock_qty >= ? AND o.unit_price <= ?]], { l.name, l.quantity, l.cost }) or {}
        local set = {}
        for _, r in ipairs(rows) do set[tonumber(r.supplier_id)] = true end
        if candidates == nil then candidates = set else
            for id in pairs(candidates) do if not set[id] then candidates[id] = nil end end
        end
    end
    local out = {}
    for id in pairs(candidates or {}) do out[#out + 1] = id end
    return out
end

local function assignAiSupplier(order, actor)
    if not O.Transition(order.id, 'awaiting_supplier', 'awaiting_delivery', actor or 'system', 'AI supplier',
        { supplier_kind = 'ai', supplier_ref = AI_SUPPLIER, driver_deadline = nowMs() + cfg().driverPrioritySeconds * 1000 }) then
        return false
    end
    O.PostContract(O.Get(order.id), false)
    return true
end

--- Places an order. payload = { kind, buyerId, method = 'trucking' | 'pickup', cart, deferDelivery }
function O.Create(src, payload)
    payload = type(payload) == 'table' and payload or {}
    local kind, buyerId = tostring(payload.kind or ''), tostring(payload.buyerId or '')
    local adapter = O.kinds[kind]
    if not adapter then return { ok = false, error = 'unknown_buyer' } end
    if not adapter.canManage(src, buyerId) then return { ok = false, error = 'not_owner' } end
    local method = tostring(payload.method or '')
    if method ~= 'trucking' and method ~= 'pickup' then return { ok = false, error = 'invalid_method' } end
    local lines, subtotal = adapter.price(buyerId, payload.cart)
    if type(lines) ~= 'table' or #lines == 0 then return { ok = false, error = 'invalid_items' } end
    subtotal = round2(subtotal)
    local cid = citizenOf(src)
    if not cid then return { ok = false, error = 'no_player' } end
    if not bankReady() or not ensureEscrow() or not adapter.ensureAccount(buyerId) then return { ok = false, error = 'bank_unavailable' } end

    local route = adapter.route(buyerId)
    local freight, markup = 0, 0
    if method == 'trucking' then
        if not route then return { ok = false, error = 'delivery_locations_not_configured' } end
        freight = freightPayout(route.trucking, subtotal)
        markup = round2(subtotal * cfg().aiMarkup)
    end
    local total = round2(subtotal + markup)
    local createdAt = nowMs()

    local orderId = MySQL.insert.await([[INSERT INTO pf_store_supply_orders
        (store_id, buyer_kind, buyer_ref, owner_citizenid, method, status, total, subtotal, ai_markup, items_json, created_at, freight_payout, payment_state)
        VALUES (?, ?, ?, ?, ?, 'created', ?, ?, ?, ?, ?, ?, 'pending')]],
        { buyerId, kind, adapter.account(buyerId), cid, method, total, subtotal, markup, json.encode(lines), createdAt, freight })
    if not orderId then return { ok = false, error = 'db_insert_failed' } end
    logEvent(orderId, nil, 'created', cid, method)

    -- pickup orders pay the supplier directly; delivery orders are held in escrow until delivered
    local charge = transfer({
        from = adapter.account(buyerId), to = method == 'pickup' and AI_SUPPLIER or ESCROW, amount = total,
        key = key(orderId, 'charge'), kind = 'supplies', reason = ('Supply order #%d'):format(orderId), actor = cid,
        metadata = { order = orderId, buyer = kind .. ':' .. buyerId },
    })
    if not charge.ok then
        O.Transition(orderId, 'created', 'failed', cid, 'payment: ' .. tostring(charge.error), { payment_state = 'failed' })
        return { ok = false, error = charge.error == 'insufficient_funds' and 'insufficient_funds' or 'payment_failed', data = { total = total } }
    end
    O.Transition(orderId, 'created', 'paid', cid, 'paid', { payment_tx = charge.txId, payment_state = 'paid' })

    if method == 'pickup' then
        O.Transition(orderId, 'paid', 'ready', 'system', 'ready for pickup', { supplier_kind = 'ai', supplier_ref = AI_SUPPLIER, settled = 1 })
        if not payload.deferDelivery then
            O.Transition(orderId, 'ready', 'delivered', cid, 'collected', { delivered_at = nowMs() })
            local res = O.Unpack(nil, orderId, cid)
            if not res.ok then return res end
        end
        return { ok = true, data = { orderId = orderId, total = total, subtotal = subtotal, items = lines, createdAt = createdAt } }
    end

    -- delivery: offer it to player suppliers first, then the AI supplier
    local suppliers = suppliersFor(lines)
    O.Transition(orderId, 'paid', 'awaiting_supplier', 'system', #suppliers .. ' player supplier(s) can fill it',
        { supplier_deadline = createdAt + (#suppliers > 0 and cfg().supplierOfferSeconds * 1000 or 0) })
    if #suppliers == 0 then
        assignAiSupplier(O.Get(orderId), 'system')
    else
        O.NotifySuppliers(suppliers, orderId)
    end
    local order = O.Get(orderId)
    return { ok = true, data = { orderId = orderId, total = total, subtotal = subtotal, markup = markup, status = order.status, contractId = contractId(orderId), items = lines, createdAt = createdAt } }
end

--- Collects a deferred pickup order (from `ready`).
function O.Collect(src, kind, buyerId, orderId)
    local adapter = O.kinds[kind]
    if not adapter or not adapter.canManage(src, buyerId) then return { ok = false, error = 'not_owner' } end
    local order = O.Get(orderId)
    if not order or order.store_id ~= tostring(buyerId) or order.buyer_kind ~= kind then return { ok = false, error = 'order_not_found' } end
    if order.method ~= 'pickup' then return { ok = false, error = 'delivered_by_trucking' } end
    if not O.Transition(order.id, 'ready', 'delivered', citizenOf(src), 'collected', { delivered_at = nowMs() }) then
        return { ok = false, error = 'not_deliverable' }
    end
    return O.Unpack(nil, order.id, citizenOf(src))
end

--- Cancels an order that no driver has picked up, refunding what the buyer paid (less any part
--- already refunded). Reserved player-supplier stock goes back to the supplier.
function O.Cancel(src, kind, buyerId, orderId)
    local adapter = O.kinds[kind]
    if not adapter or not adapter.canManage(src, buyerId) then return { ok = false, error = 'not_owner' } end
    local order = O.Get(orderId)
    if not order or order.store_id ~= tostring(buyerId) or order.buyer_kind ~= kind then return { ok = false, error = 'order_not_found' } end
    local from = order.status
    if from ~= 'awaiting_supplier' and from ~= 'awaiting_delivery' then return { ok = false, error = 'not_cancellable' } end
    if from == 'awaiting_delivery' then
        local okCancel, removed = pcall(function() return exports['pf-trucking']:CancelExternalJob(contractId(order.id)) end)
        if GetResourceState('pf-trucking') == 'started' and not (okCancel and removed) then return { ok = false, error = 'already_claimed' } end
    end
    local cid = citizenOf(src)
    if not O.Transition(order.id, from, 'cancelled', cid, 'cancelled by buyer', { cancelled_at = nowMs() }) then
        return { ok = false, error = 'not_cancellable' }
    end
    -- what the buyer already got back (the markup refund when a player supplied it)
    local refunded = 0
    local okTx, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key(order.id, 'markup-refund')) end)
    if okTx and type(tx) == 'table' and tx.state == 'completed' then refunded = tonumber(tx.amount) or 0 end
    local amount = round2((tonumber(order.total) or 0) - refunded)
    if amount > 0 then
        local r = transfer({ from = ESCROW, to = order.buyer_ref or adapter.account(order.store_id), amount = amount, key = key(order.id, 'cancel'), kind = 'refund', reason = 'Supply order cancelled' })
        if not r.ok then print(('^1[pf-stores]^7 refund of cancelled order %d failed (%s); retried at start'):format(order.id, tostring(r.error))) end
    end
    if order.supplier_kind == 'player' and order.supplier_ref then O.ReturnSupplierStock(order) end
    return { ok = true, data = { orderId = order.id, refunded = amount } }
end

-- ── player suppliers ────────────────────────────────────────────────────────

local function supplierOf(src)
    local cid = citizenOf(src)
    if not cid then return nil end
    return MySQL.single.await('SELECT id, citizenid, name, active FROM pf_suppliers WHERE citizenid = ? LIMIT 1', { cid })
end

function O.RegisterSupplier(src, name)
    local cid = citizenOf(src)
    if not cid then return { ok = false, error = 'no_player' } end
    name = type(name) == 'string' and name:gsub('[^%w %-%.\']', ''):sub(1, 64) or ''
    if name == '' then return { ok = false, error = 'invalid_name' } end
    MySQL.insert.await('INSERT INTO pf_suppliers (citizenid, name, active, created_at) VALUES (?, ?, 1, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), active = 1', { cid, name, nowMs() })
    return { ok = true, data = supplierOf(src) }
end

-- items a supplier can offer: anything some buyer kind's catalog sells (the AI price is the ceiling)
function O.SetOffer(src, item, unitPrice)
    local sup = supplierOf(src)
    if not sup then return { ok = false, error = 'not_a_supplier' } end
    item = type(item) == 'string' and item:lower():sub(1, 128) or nil
    unitPrice = tonumber(unitPrice)
    if not item or not unitPrice or unitPrice ~= unitPrice or unitPrice <= 0 or unitPrice > 1000000 then return { ok = false, error = 'invalid_offer' } end
    MySQL.insert.await('INSERT INTO pf_supplier_offers (supplier_id, item, unit_price, stock_qty) VALUES (?, ?, ?, 0) ON DUPLICATE KEY UPDATE unit_price = VALUES(unit_price)', { sup.id, item, round2(unitPrice) })
    return { ok = true }
end

--- A supplier stocks goods they really have: the items are taken from their inventory. One stock
--- unit is one case, made of Config.SupplyChain.CaseSize items (default 1).
function O.DepositStock(src, item, cases)
    local sup = supplierOf(src)
    if not sup then return { ok = false, error = 'not_a_supplier' } end
    item = type(item) == 'string' and item:lower() or nil
    cases = math.floor(tonumber(cases) or 0)
    if not item or cases < 1 or cases > 1000 then return { ok = false, error = 'invalid_amount' } end
    local offer = MySQL.single.await('SELECT stock_qty FROM pf_supplier_offers WHERE supplier_id = ? AND item = ?', { sup.id, item })
    if not offer then return { ok = false, error = 'no_offer' } end
    local per = tonumber(((Config.SupplyChain or {}).CaseSize or {})[item]) or 1
    if not exports['pfm-inventory']:RemoveItem(src, item, cases * per, false, 'pf-supply:stock') then
        return { ok = false, error = 'missing_items' }
    end
    MySQL.update.await('UPDATE pf_supplier_offers SET stock_qty = stock_qty + ? WHERE supplier_id = ? AND item = ?', { cases, sup.id, item })
    return { ok = true }
end

--- Orders a supplier can fill now.
function O.OpenOffersFor(src)
    local sup = supplierOf(src)
    if not sup then return { ok = false, error = 'not_a_supplier' } end
    local rows = MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status = 'awaiting_supplier' ORDER BY id") or {}
    local out = {}
    for _, order in ipairs(rows) do
        for _, id in ipairs(suppliersFor(decode(order.items_json) or {})) do
            if id == tonumber(sup.id) then out[#out + 1] = { orderId = order.id, items = decode(order.items_json), subtotal = order.subtotal } end
        end
    end
    return { ok = true, data = out }
end

function O.NotifySuppliers(supplierIds, orderId)
    for _, id in ipairs(supplierIds) do
        local row = MySQL.single.await('SELECT citizenid FROM pf_suppliers WHERE id = ?', { id })
        local Player = row and exports['pfm-core']:GetPlayerByCitizenId(row.citizenid)
        if Player then
            TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, ('Supply order #%d is open: /supplyaccept %d'):format(orderId, orderId), 'primary')
        end
    end
end

--- A player supplier takes an open order: their stock is reserved atomically, the buyer gets back the
--- part of the AI markup the supplier does not earn, and the delivery is posted to truckers.
function O.AcceptSupply(src, orderId)
    local sup = supplierOf(src)
    if not sup or tonumber(sup.active) ~= 1 then return { ok = false, error = 'not_a_supplier' } end
    local order = O.Get(orderId)
    if not order or order.status ~= 'awaiting_supplier' then return { ok = false, error = 'not_open' } end
    local lines = decode(order.items_json) or {}
    local reserved = {}
    for _, l in ipairs(lines) do
        local changed = MySQL.update.await([[UPDATE pf_supplier_offers SET stock_qty = stock_qty - ?
            WHERE supplier_id = ? AND item = ? AND stock_qty >= ? AND unit_price <= ?]], { l.quantity, sup.id, l.name, l.quantity, l.cost })
        if not changed or changed < 1 then
            for _, r in ipairs(reserved) do
                MySQL.update.await('UPDATE pf_supplier_offers SET stock_qty = stock_qty + ? WHERE supplier_id = ? AND item = ?', { r.quantity, sup.id, r.name })
            end
            return { ok = false, error = 'not_enough_stock' }
        end
        reserved[#reserved + 1] = l
    end
    local cid = citizenOf(src)
    if not O.Transition(order.id, 'awaiting_supplier', 'awaiting_delivery', cid, 'player supplier ' .. sup.name,
        { supplier_kind = 'player', supplier_ref = cid, driver_deadline = nowMs() + cfg().driverPrioritySeconds * 1000 }) then
        for _, r in ipairs(reserved) do
            MySQL.update.await('UPDATE pf_supplier_offers SET stock_qty = stock_qty + ? WHERE supplier_id = ? AND item = ?', { r.quantity, sup.id, r.name })
        end
        return { ok = false, error = 'not_open' }
    end
    -- the AI markup: part to the supplier, the rest back to the buyer (retried by Settle if the bank is down)
    splitMarkup(O.Get(order.id))
    O.PostContract(O.Get(order.id), false)
    return { ok = true, data = { orderId = order.id } }
end

function O.ReturnSupplierStock(order)
    local sup = MySQL.single.await('SELECT id FROM pf_suppliers WHERE citizenid = ?', { order.supplier_ref })
    if not sup then return end
    for _, l in ipairs(decode(order.items_json) or {}) do
        MySQL.update.await('UPDATE pf_supplier_offers SET stock_qty = stock_qty + ? WHERE supplier_id = ? AND item = ?', { l.quantity, sup.id, l.name })
    end
end

-- ── pf-trucking events ──────────────────────────────────────────────────────

local function orderFromJob(jobData)
    if type(jobData) ~= 'table' or jobData.externalType ~= 'pf-supply:order' then return nil end
    local payload = type(jobData.externalPayload) == 'table' and jobData.externalPayload or {}
    return O.Get(tonumber(payload.orderId))
end

AddEventHandler('pf-trucking:server:externalJobClaimed', function(jobData, meta)
    local order = orderFromJob(jobData)
    if not order then return end
    O.Transition(order.id, 'awaiting_delivery', 'assigned', meta and meta.citizenid, 'player driver',
        { driver_kind = 'player', driver_ref = meta and meta.citizenid, assigned_at = nowMs() })
end)

AddEventHandler('pf-trucking:server:externalJobLoaded', function(jobData, meta)
    local order = orderFromJob(jobData)
    if not order then return end
    O.Transition(order.id, 'assigned', 'in_transit', meta and meta.citizenid, 'cargo loaded', { in_transit_at = nowMs() })
end)

AddEventHandler('pf-trucking:server:externalJobReleased', function(jobData, meta)
    local order = orderFromJob(jobData)
    if not order then return end
    local set = { driver_kind = O.NULL, driver_ref = O.NULL, assigned_at = O.NULL, driver_deadline = nowMs() + cfg().driverPrioritySeconds * 1000 }
    if not O.Transition(order.id, 'assigned', 'awaiting_delivery', meta and meta.citizenid, 'driver released', set) then
        O.Transition(order.id, 'in_transit', 'awaiting_delivery', meta and meta.citizenid, 'driver released', set)
    end
end)

-- The driver was paid by pf-trucking from escrow (key freight:supply:<id>); the order is delivered.
AddEventHandler('pf-trucking:server:externalJobCompleted', function(jobData, meta)
    local order = orderFromJob(jobData)
    if not order then return end
    if not deliver(order, 'in_transit', meta and meta.citizenid, 'delivered by player driver') then
        deliver(order, 'assigned', meta and meta.citizenid, 'delivered by player driver')
    end
end)

AddEventHandler('pf-trucking:server:started', function()
    O.RecoverContracts()
end)

-- ── timers: supplier window, driver priority, AI delivery, stalled drivers, retries ──

function O.RecoverContracts()
    local rows = MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE method = 'trucking' AND status IN ('awaiting_delivery', 'assigned', 'in_transit')") or {}
    local posted = 0
    for _, order in ipairs(rows) do
        if order.driver_kind ~= 'ai' and O.PostContract(order, true) then posted = posted + 1 end
    end
    return posted
end

local function aiDeliver(order)
    -- AI driver: the freight share goes to the AI freight account under the same key a player
    -- driver would be paid with, so the trip is paid exactly once whoever drove it
    local freight = tonumber(order.freight_payout) or 0
    if freight > 0 then
        local r = transfer({ from = ESCROW, to = AI_FREIGHT, amount = freight, key = ('freight:supply:%d'):format(order.id), kind = 'wage', reason = 'AI delivery' })
        if not r.ok then return false end
    end
    return deliver(order, 'in_transit', 'ai', 'delivered by AI driver')
end

function O.Tick()
    if not bankReady() then return end
    local now = nowMs()
    local c = cfg()
    -- supplier window over: the AI supplier takes it
    for _, order in ipairs(MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status = 'awaiting_supplier' AND supplier_deadline <= ?", { now }) or {}) do
        assignAiSupplier(order, 'system')
    end
    -- no player driver in time: an AI driver takes the contract (only if nobody claimed it)
    for _, order in ipairs(MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status = 'awaiting_delivery' AND driver_deadline <= ?", { now }) or {}) do
        local removed = true
        if GetResourceState('pf-trucking') == 'started' then
            local ok, res = pcall(function() return exports['pf-trucking']:CancelExternalJob(contractId(order.id)) end)
            removed = ok and res == true
        end
        if removed and O.Transition(order.id, 'awaiting_delivery', 'assigned', 'ai', 'AI driver', { driver_kind = 'ai', driver_ref = 'ai', assigned_at = now }) then
            O.Transition(order.id, 'assigned', 'in_transit', 'ai', 'AI driver on the road', { in_transit_at = now, ai_eta = now + c.aiDeliverySeconds * 1000 })
        end
    end
    -- AI deliveries that arrived
    for _, order in ipairs(MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status = 'in_transit' AND driver_kind = 'ai' AND ai_eta <= ?", { now }) or {}) do
        aiDeliver(order)
    end
    -- player drivers who stalled: the contract goes back to the pool
    for _, order in ipairs(MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status IN ('assigned', 'in_transit') AND driver_kind = 'player' AND assigned_at <= ?", { now - c.driverMaxSeconds * 1000 }) or {}) do
        local ok = pcall(function() return exports['pf-trucking']:ReleaseExternalJob(contractId(order.id)) end)
        if ok then
            local set = { driver_kind = O.NULL, driver_ref = O.NULL, assigned_at = O.NULL, driver_deadline = now + c.driverPrioritySeconds * 1000 }
            if not O.Transition(order.id, 'assigned', 'awaiting_delivery', 'system', 'driver timed out', set) then
                O.Transition(order.id, 'in_transit', 'awaiting_delivery', 'system', 'driver timed out', set)
            end
        end
    end
    -- retries: money for delivered orders, and pallets that could not be placed
    for _, order in ipairs(MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status IN ('delivered', 'unpacked') AND settled = 0") or {}) do
        O.Settle(order)
    end
    if GetResourceState('pfm-worldobjects') == 'started' then
        for _, order in ipairs(MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status = 'delivered' AND pallet_id IS NULL") or {}) do
            createPallet(order)
        end
    end
end

--- At start: orders interrupted while being paid are finished or failed by the ledger's own record.
function O.RecoverPayments()
    for _, order in ipairs(MySQL.query.await("SELECT id FROM pf_store_supply_orders WHERE status = 'created' AND created_at <= ?", { nowMs() - 60000 }) or {}) do
        local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key(order.id, 'charge')) end)
        if ok and type(tx) == 'table' and tx.state == 'completed' then
            O.Transition(order.id, 'created', 'paid', 'system', 'payment recovered', { payment_tx = tx.tx_id, payment_state = 'paid' })
            O.Transition(order.id, 'paid', 'awaiting_supplier', 'system', 'recovered', { supplier_deadline = nowMs() })
        else
            O.Transition(order.id, 'created', 'failed', 'system', 'payment never completed', { payment_state = 'failed' })
        end
    end
    -- orders left at 'paid' (crash between the charge and the next step)
    for _, order in ipairs(MySQL.query.await("SELECT id, method FROM pf_store_supply_orders WHERE status = 'paid'") or {}) do
        if order.method == 'pickup' then
            O.Transition(order.id, 'paid', 'ready', 'system', 'recovered', { supplier_kind = 'ai', supplier_ref = AI_SUPPLIER, settled = 1 })
        else
            O.Transition(order.id, 'paid', 'awaiting_supplier', 'system', 'recovered', { supplier_deadline = nowMs() })
        end
    end
end

function O.Start()
    local ok, err = RunMigrations('pf-stores', O.Migrations)
    if not ok then
        print('^1[pf-stores]^7 supply order migrations failed: ' .. tostring(err))
        return false
    end
    O.ready = true
    return true
end

-- ── exports and commands ────────────────────────────────────────────────────

exports('CreateOrder', function(src, payload) return O.Create(src, payload) end)
exports('CancelOrder', function(src, kind, buyerId, orderId) return O.Cancel(src, kind, buyerId, orderId) end)
exports('CollectOrder', function(src, kind, buyerId, orderId) return O.Collect(src, kind, buyerId, orderId) end)
exports('UnpackSupplyOrder', function(src, orderId) return O.Unpack(src, orderId) end)
exports('GetOrder', function(orderId) return O.Get(orderId) end)
exports('GetOrderHistory', function(orderId)
    return MySQL.query.await('SELECT from_status, to_status, actor, note, at FROM pf_supply_order_events WHERE order_id = ? ORDER BY id', { tonumber(orderId) }) or {}
end)
exports('RegisterBuyerKind', function(kind, adapter) return O.RegisterBuyerKind(kind, adapter) end)
exports('CanManageOrderBuyer', function(src, orderId)
    local order = O.Get(orderId)
    local adapter = order and O.kinds[order.buyer_kind]
    return adapter ~= nil and adapter.canManage(src, order.store_id) == true
end)

local function reply(src, res)
    TriggerClientEvent('QBCore:Notify', src, res.ok and 'Done' or ('Failed: ' .. tostring(res.error)), res.ok and 'success' or 'error')
end

CreateThread(function()
    local QB = exports['pfm-core']:GetCoreObject()
    QB.Commands.Add('supplier', 'Register as a supplier', { { name = 'name', help = 'Business name' } }, true, function(src, args)
        reply(src, O.RegisterSupplier(src, table.concat(args, ' ')))
    end)
    QB.Commands.Add('supplyoffer', 'Offer an item to businesses', { { name = 'item', help = 'Item' }, { name = 'price', help = 'Price per case' } }, true, function(src, args)
        reply(src, O.SetOffer(src, args[1], args[2]))
    end)
    QB.Commands.Add('supplystock', 'Stock cases from your inventory', { { name = 'item', help = 'Item' }, { name = 'cases', help = 'Cases' } }, true, function(src, args)
        reply(src, O.DepositStock(src, args[1], args[2]))
    end)
    QB.Commands.Add('supplyorders', 'Orders you can supply', {}, false, function(src)
        local res = O.OpenOffersFor(src)
        if not res.ok then return reply(src, res) end
        for _, o in ipairs(res.data) do
            TriggerClientEvent('chat:addMessage', src, { args = { 'Supply', ('#%d  %s'):format(o.orderId, json.encode(o.items)) } })
        end
        if #res.data == 0 then TriggerClientEvent('QBCore:Notify', src, 'No open orders you can fill', 'primary') end
    end)
    QB.Commands.Add('supplyaccept', 'Supply an open order', { { name = 'order', help = 'Order number' } }, true, function(src, args)
        reply(src, O.AcceptSupply(src, tonumber(args[1])))
    end)
end)
