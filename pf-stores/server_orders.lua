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
-- Money (pfm-banking ledger, one key per order and step so every step pays once):
--   buyer account -> escrow            supply:<id>:charge     goods + AI markup + freight (delivery);
--                                                             goods only, straight to the AI supplier (pickup)
--   escrow -> driver (pf-trucking)     freight:supply:<id>    player driver, or system:pf-stores-freight for AI
--   escrow -> supplier                 supply:<id>:supplier   the goods value (O.GoodsShare)
--   escrow -> AI supplier / refund     supply:<id>:markup...  AI markup, or split when a player supplies
--                                                             (paid at delivery, never at accept)
--   escrow -> buyer                    supply:<id>:cancel     cancellation refund
-- The ledger keeps a failed transfer under its key for good, so a payout from escrow whose attempt
-- failed is retried under the next numbered key (<key>:1, <key>:2, ...; see payoutState). A payee
-- whose account no longer exists (a deleted character) is given up on after PAYEE_GONE_ATTEMPTS:
-- a supplier's share then goes back to the buyer (<key>:buyer), and what nobody can take stays in
-- escrow, recorded in pf_supply_order_payouts for staff.
-- What leaves escrow for an order always adds up to what the order put in: freight + goods + markup
-- = total. Orders placed before the buyer paid freight on top (total = goods + markup, freight taken
-- out of the goods) still settle by the same rule: the supplier gets total - markup - freight.
-- A trucking delivery must carry goods worth at least Config.SupplyChain.MinDeliveryGoods (unset:
-- the business's freight minimum), so the freight on top can never dwarf the goods.
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
        duplicateWindowSeconds = tonumber(c.DuplicateWindowSeconds) or 10,
    }
end

local function nowMs() return math.floor(os.time() * 1000.0) end   -- float math: no integer overflow on 32-bit Lua builds
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
    {
        version = 2,
        name = 'supply order cancellation refunds are retried',
        up = function()
            -- refund_state: NULL (no refund owed), 'pending' (owed, retried), 'done'
            -- refund_attempt: which key the refund uses (0 = supply:<id>:cancel, n = supply:<id>:cancel:<n>)
            if not MigrationColumnExists('pf_store_supply_orders', 'refund_state') then
                MySQL.query.await('ALTER TABLE pf_store_supply_orders ADD COLUMN `refund_state` VARCHAR(16) NULL')
            end
            if not MigrationColumnExists('pf_store_supply_orders', 'refund_attempt') then
                MySQL.query.await('ALTER TABLE pf_store_supply_orders ADD COLUMN `refund_attempt` INT NOT NULL DEFAULT 0')
            end
            -- orders cancelled before this whose refund failed in the ledger: owed again
            local ok, err = pcall(function()
                MySQL.update.await([[UPDATE pf_store_supply_orders o
                    JOIN pf_transactions t ON t.idempotency_key = CONCAT('supply:', o.id, ':cancel')
                    SET o.refund_state = 'pending'
                    WHERE o.status = 'cancelled' AND o.refund_state IS NULL AND t.state IN ('failed', 'compensated')]])
            end)
            if not ok then print('^3[pf-stores]^7 failed cancellation refunds of older orders not looked up: ' .. tostring(err)) end
        end,
    },
    {
        version = 3,
        name = 'cancelled supply orders whose refund never went through are owed',
        up = function()
            -- version 2 found refunds the ledger stored as failed; a refund call that never reached
            -- the ledger (bank down, crash) left no row at all. Owed: the buyer's payment into escrow
            -- completed and no cancellation refund under the first key did.
            local ok, err = pcall(function()
                MySQL.update.await([[UPDATE pf_store_supply_orders o SET o.refund_state = 'pending'
                    WHERE o.status = 'cancelled' AND o.refund_state IS NULL AND o.method = 'trucking'
                    AND EXISTS (SELECT 1 FROM pf_transactions c WHERE c.idempotency_key = CONCAT('supply:', o.id, ':charge') AND c.state = 'completed')
                    AND NOT EXISTS (SELECT 1 FROM pf_transactions r WHERE r.idempotency_key = CONCAT('supply:', o.id, ':cancel') AND r.state = 'completed')]])
            end)
            if not ok then print('^3[pf-stores]^7 unpaid cancellation refunds of older orders not looked up: ' .. tostring(err)) end
        end,
    },
    {
        version = 4,
        name = 'supply order payouts nobody could take',
        up = function()
            -- One row per share of an order whose payee's account is gone for good (a deleted
            -- character): 'returned' = paid back to the buyer instead, 'held' = nobody can take it, so
            -- it stays in the escrow account for staff. Cancellation refunds a buyer can no longer
            -- take are 'held' under part 'cancel' (the order's refund_state is then 'forfeited').
            MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_supply_order_payouts (
                order_id INT NOT NULL,
                part VARCHAR(32) NOT NULL,
                outcome VARCHAR(16) NOT NULL,
                payee VARCHAR(96) NULL,
                paid_to VARCHAR(96) NULL,
                amount DECIMAL(12,2) NOT NULL,
                at BIGINT NOT NULL,
                PRIMARY KEY (order_id, part),
                INDEX idx_outcome (outcome)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
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
--   unpack(buyerId, lines, orderId, deliveredAt) -> bool  adds the goods to stock (called once; deliveredAt in seconds)
-- }
function O.RegisterBuyerKind(kind, adapter)
    assert(type(kind) == 'string' and type(adapter) == 'table', 'RegisterBuyerKind(kind, adapter)')
    O.kinds[kind] = adapter
end

-- A function passed through an export (or inside a table passed through one) reaches this resource
-- as a callable table (a FiveM function reference), not as a Lua function. Buyer adapters registered
-- by other resources (pf-restaurants, pf-computer's job businesses) are made of those, so an
-- adapter's functions are tested with this, never with type(x) == 'function'.
local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end
O.Callable = callable

-- ── delivery position ───────────────────────────────────────────────────────
-- Where a trucking order is delivered, in this order of precedence:
--   1. the business's own delivery point: its buyer adapter's route (a store's configured dropoff,
--      the point a boss set on the business computer, a restaurant's receiving zone);
--   2. the government default delivery zone of that business (pf-government GetDeliveryZone: the
--      zone city staff approved for the business on site, else the zone of its district);
--   3. none: trucking delivery is not available (pickup orders still work).
-- An adapter whose route returns false has delivery switched off; no zone overrides that. With a
-- government zone, the pickup and trucking settings still come from the adapter's route when it
-- has them, else from Config.SupplyChain.DefaultPickup / DefaultTrucking (built-in defaults below).
local GOV_BUSINESS_IDS = { store = 'store:%s', restaurant = 'restaurant:%s', jobbiz = 'mechanic:%s' }
local DEFAULT_PICKUP = { label = 'Wholesale Distributor', coords = { x = 1012.4, y = -2520.7, z = 28.31, w = 92.0 } }
local DEFAULT_TRUCKING = { title = 'Business Supplies', cargoType = 'Business Supplies', payoutRate = 0.12, payoutMin = 150 }

--- The pf-government registry id of a buyer (adapter.governmentId(buyerId) overrides the default).
function O.GovernmentId(kind, buyerId)
    local adapter = O.kinds[kind]
    if adapter and callable(adapter.governmentId) then
        local ok, id = pcall(adapter.governmentId, buyerId)
        if ok and type(id) == 'string' and id ~= '' then return id end
    end
    local fmt = GOV_BUSINESS_IDS[kind]
    return fmt and fmt:format(tostring(buyerId)) or nil
end

local function governmentZone(govId)
    if not govId or GetResourceState('pf-government') ~= 'started' then return nil end
    local ok, zone = pcall(function() return exports['pf-government']:GetDeliveryZone(govId) end)
    if not ok or type(zone) ~= 'table' or not tonumber(zone.x) or not tonumber(zone.y) then return nil end
    return zone
end

--- The route of a buyer's deliveries: { pickup, dropoff, unload, trucking, source } or nil.
--- source = 'business' | 'government_zone' | 'district_zone'.
function O.Route(kind, buyerId)
    local adapter = O.kinds[kind]
    if not adapter or not callable(adapter.route) then return nil end
    -- an adapter whose resource has stopped errors when called: no delivery until it registers again
    local okRoute, route = pcall(adapter.route, buyerId)
    if not okRoute then
        print(('^3[pf-stores]^7 delivery route of %s %s not available: %s'):format(kind, tostring(buyerId), tostring(route)))
        return nil
    end
    if route == false then return nil end
    if type(route) == 'table' and route.dropoff and route.dropoff.coords then
        route.source = route.source or 'business'
        return route
    end
    local zone = governmentZone(O.GovernmentId(kind, buyerId))
    if not zone then return nil end
    local base = type(route) == 'table' and route or {}
    local c = (Config and Config.SupplyChain) or {}
    local spot = { x = tonumber(zone.x), y = tonumber(zone.y), z = tonumber(zone.z) or 0.0, w = tonumber(zone.heading) or 0.0 }
    return {
        pickup = (base.pickup and base.pickup.coords) and base.pickup or c.DefaultPickup or DEFAULT_PICKUP,
        dropoff = { label = zone.label or (base.dropoff and base.dropoff.label) or tostring(buyerId), coords = { x = spot.x, y = spot.y, z = spot.z } },
        unload = { label = zone.label or 'Delivery zone', coords = spot },
        trucking = base.trucking or c.DefaultTrucking or DEFAULT_TRUCKING,
        source = zone.scope == 'district' and 'district_zone' or 'government_zone',
    }
end

-- ── orders ──────────────────────────────────────────────────────────────────

local ORDER_COLUMNS = [[id, store_id, buyer_kind, buyer_ref, owner_citizenid, method, status, total, subtotal, ai_markup,
    items_json, created_at, delivered_at, freight_payout, payment_tx, payment_state, supplier_kind, supplier_ref,
    supplier_deadline, driver_kind, driver_ref, driver_deadline, assigned_at, in_transit_at, ai_eta, unpacked_at,
    cancelled_at, settled, pallet_id, external_contract_id, refund_state, refund_attempt]]

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

-- The trucker's pay for a delivery: payoutRate x the goods value (or a flat payout), within
-- payoutMin..payoutMax. The buyer pays it on top of the goods, so it is no longer capped at the goods
-- value (that cap only kept it from eating the supplier's money): the configured minimum is a real
-- minimum, and a small order costs at least that much to have delivered.
local function freightPayout(trucking, subtotal)
    trucking = trucking or {}
    local payout
    local rate = tonumber(trucking.payoutRate or 0) or 0
    if rate > 0 then payout = math.floor((tonumber(subtotal) or 0) * rate + 0.5) else payout = tonumber(trucking.payout or 0) or 0 end
    if (tonumber(trucking.payoutMin) or 0) > 0 then payout = math.max(payout, tonumber(trucking.payoutMin)) end
    if (tonumber(trucking.payoutMax) or 0) > 0 then payout = math.min(payout, tonumber(trucking.payoutMax)) end
    return round2(math.max(0, payout))
end

--- The least goods value a trucking delivery may carry on this route: Config.SupplyChain.
--- MinDeliveryGoods when set (0 = no minimum), else the business's freight minimum (the freight an
--- order of no value would pay). The buyer pays the freight on top, so without it anyone allowed to
--- order could place tiny deliveries ($4 of goods, $250 of freight) and drive them, moving the
--- business's money to themselves as freight.
local function minDeliveryGoods(route)
    local set = tonumber(((Config and Config.SupplyChain) or {}).MinDeliveryGoods)
    if set and set == set and set >= 0 and set < 1e9 then return round2(set) end
    return freightPayout(route and route.trucking, 0)
end

local function dollars(n)
    n = round2(n)
    if n == math.floor(n) then return ('$%d'):format(math.floor(n)) end
    return ('$%.2f'):format(n)
end

--- What a delivery adds on top of the goods for this buyer: { markupRate, freight = { rate, flat,
--- min, max }, markupRefundShare, minGoods }, or nil when the buyer has no delivery route. For the
--- order screens' estimate; the order itself is priced by O.Quote.
function O.Pricing(kind, buyerId)
    local route = O.Route(kind, buyerId)
    if not route then return nil end
    local t = route.trucking or {}
    return {
        markupRate = cfg().aiMarkup,
        freight = {
            rate = tonumber(t.payoutRate) or 0, flat = tonumber(t.payout) or 0,
            min = tonumber(t.payoutMin) or 0, max = tonumber(t.payoutMax) or 0,
        },
        -- the part of the markup that comes back to the buyer when a player supplier fills the order
        markupRefundShare = round2(1 - math.max(0, math.min(1, cfg().supplierShareOfMarkup))),
        -- a delivery with goods worth less than this is refused (collect it instead)
        minGoods = minDeliveryGoods(route),
    }
end

-- The price of an order from its goods value: pickup is the goods only; a delivery adds the AI
-- markup and the trucker's freight on top. Returns { subtotal, markup, freight, total }.
local function quote(method, route, subtotal)
    subtotal = round2(subtotal)
    local markup, freight = 0, 0
    if method == 'trucking' then
        freight = freightPayout(route and route.trucking, subtotal)
        markup = round2(subtotal * cfg().aiMarkup)
    end
    return { subtotal = subtotal, markup = markup, freight = freight, total = round2(subtotal + markup + freight) }
end

--- The price of goods worth `subtotal` for this buyer and method, as an order would be charged:
--- { subtotal, markup, freight, total }, or nil when delivery is not available for the buyer. A
--- delivery quote also says the minimum goods value (minGoods) and whether this one is under it.
function O.Quote(kind, buyerId, method, subtotal)
    subtotal = tonumber(subtotal)
    if not subtotal or subtotal ~= subtotal or subtotal < 0 or subtotal > 1e9 then return nil end
    if method ~= 'trucking' then return quote('pickup', nil, subtotal) end
    local route = O.Route(kind, buyerId)
    if not route then return nil end
    local q = quote('trucking', route, subtotal)
    q.minGoods = minDeliveryGoods(route)
    q.belowMinimum = q.subtotal < q.minGoods
    return q
end

--- The supplier's goods money for an order: what is left in escrow after the freight and the markup.
--- For orders with freight on top that is the full goods value (subtotal); for orders placed before
--- that, the goods less the freight, as they were charged. Never more than the order put in.
function O.GoodsShare(order)
    local total = tonumber(order.total) or 0
    return round2(math.max(0, total - (tonumber(order.ai_markup) or 0) - (tonumber(order.freight_payout) or 0)))
end

local function citizenOf(src)
    local Player = exports['pfm-core']:GetPlayer(src)
    return Player and Player.PlayerData.citizenid or nil
end

-- ── trucking contracts ──────────────────────────────────────────────────────

local function contractId(orderId) return ('SUP-%d'):format(orderId) end

--- Posts the order's pf-trucking contract (or re-posts it after a restart, with its driver).
function O.PostContract(order, restoreDriver)
    local route = O.Route(order.buyer_kind, order.store_id)
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

-- ── payouts from escrow, under numbered attempt keys ────────────────────────

local function ledgerTx(idOrKey)
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(idOrKey) end)
    return ok and type(tx) == 'table' and tx or nil
end

-- The ledger keeps a failed transfer under its key for good (the same key returns the same failure),
-- so a payout whose attempt failed is tried again under the next key: base, base:1, base:2, ...
-- Each attempt's own ledger record decides what happens next:
--   completed                     paid (and never paid again under another key)
--   failed or compensated         that attempt is over: the next key may be tried
--   pending or debited, or failed 'interrupted_unverified'
--                                 unclear: wait for the ledger's recovery, never a new key
--   no record                     the key to try now
-- An attempt the payee's account refused because it does not exist (compensated 'unknown_account':
-- a deleted character, a closed account) is counted; after PAYEE_GONE_ATTEMPTS of them, made after
-- growing waits, the payee is gone for good.
local PAYEE_GONE_ATTEMPTS = 5
local MAX_PAYOUT_ATTEMPTS = 240   -- about ten days of hourly retries; then it waits for staff

local function attemptKey(base, n) return n > 0 and ('%s:%d'):format(base, n) or base end
local function attemptOver(tx)
    return tx.state == 'compensated' or (tx.state == 'failed' and tx.error ~= 'interrupted_unverified')
end
local function payeeRefused(tx) return tx.state == 'compensated' and tx.error == 'unknown_account' end

--- Where a payout stands: 'paid', 'waiting' (an attempt is unclear), 'gone' (the payee's account no
--- longer exists), or 'open' with the key to try now.
local function payoutState(base)
    local gone = 0
    for n = 0, MAX_PAYOUT_ATTEMPTS do
        local k = attemptKey(base, n)
        local tx = ledgerTx(k)
        if not tx then return gone >= PAYEE_GONE_ATTEMPTS and 'gone' or 'open', k end
        if tx.state == 'completed' then return 'paid', k end
        if not attemptOver(tx) then return 'waiting', k end
        if payeeRefused(tx) then gone = gone + 1 end
    end
    print(('^1[pf-stores]^7 payout %s failed %d times; left for staff'):format(base, MAX_PAYOUT_ATTEMPTS + 1))
    return 'waiting', nil
end

--- Makes at most one attempt at a payout from escrow. Returns 'paid', 'gone' or 'waiting'.
local function payFromEscrow(base, to, amount, kind, reason)
    local state, k = payoutState(base)
    if state ~= 'open' then return state end
    local r = transfer({ from = ESCROW, to = to, amount = amount, key = k, kind = kind, reason = reason })
    return r.ok and 'paid' or 'waiting'
end

--- Records a share of an order nobody could be paid: 'returned' (paid to the buyer instead) or
--- 'held' (it stays in escrow, for staff). Once per order and part.
local function recordUnpaid(orderId, part, outcome, payee, paidTo, amount)
    local n = MySQL.update.await([[INSERT IGNORE INTO pf_supply_order_payouts (order_id, part, outcome, payee, paid_to, amount, at)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], { orderId, part, outcome, payee, paidTo, round2(amount), nowMs() })
    if (tonumber(n) or 0) > 0 then
        print(('^3[pf-stores]^7 order %d: %s share of %s for %s (account gone) %s'):format(orderId, part, dollars(amount), tostring(payee),
            outcome == 'returned' and ('returned to ' .. tostring(paidTo)) or 'held in escrow for staff'))
    end
end

-- ── settlement ──────────────────────────────────────────────────────────────

local function supplierAccount(order)
    if order.supplier_kind == 'player' and order.supplier_ref then
        return ('player:%s:bank'):format(order.supplier_ref)
    end
    return AI_SUPPLIER
end

local function buyerAccountOf(order)
    if type(order.buyer_ref) == 'string' and order.buyer_ref ~= '' then return order.buyer_ref end
    local adapter = O.kinds[order.buyer_kind]
    local ok, ref = pcall(function() return adapter and adapter.account(order.store_id) end)
    return ok and type(ref) == 'string' and ref ~= '' and ref or nil
end

-- What escrow pays out for a delivered order besides the freight: the goods value to the supplier,
-- and the AI markup to the AI supplier, or split when a player supplied (their bonus, the rest back
-- to the buyer). The split is paid only at delivery: until then the whole markup stays in escrow, so
-- a cancelled order refunds the buyer in full and the supplier earns nothing.
local function settlementShares(order)
    local shares = {}
    local markup = tonumber(order.ai_markup) or 0
    local goods = O.GoodsShare(order)
    local player = order.supplier_kind == 'player' and order.supplier_ref ~= nil
    if goods > 0 then
        shares[#shares + 1] = { part = 'supplier', to = supplierAccount(order), amount = goods, kind = 'supplies',
            reason = 'Supply order delivered', supplierShare = player }
    end
    if markup > 0 and not player then
        shares[#shares + 1] = { part = 'markup', to = AI_SUPPLIER, amount = markup, kind = 'supplies', reason = 'AI supply markup' }
    elseif markup > 0 then
        local toSupplier = round2(markup * math.max(0, math.min(1, cfg().supplierShareOfMarkup)))
        local refund = round2(markup - toSupplier)
        if toSupplier > 0 then
            shares[#shares + 1] = { part = 'markup-supplier', to = supplierAccount(order), amount = toSupplier, kind = 'supplies',
                reason = 'Supplier bonus', supplierShare = true }
        end
        if refund > 0 then
            shares[#shares + 1] = { part = 'markup-refund', to = buyerAccountOf(order), amount = refund, kind = 'refund',
                reason = 'Player supplier: AI markup refunded' }
        end
    end
    return shares
end

-- One share: true once it is paid, or settled for good because its payee's account is gone. A
-- supplier's share then goes back to the buyer who paid it (the goods were delivered from stock of
-- a character that no longer exists); what the buyer cannot take either stays in escrow, recorded
-- for staff. Either way the sweep stops, and no money is made or lost.
local function settleShare(order, s)
    if not s.to then return false end   -- the buyer's account is not known right now
    local base = key(order.id, s.part)
    local state = payFromEscrow(base, s.to, s.amount, s.kind, s.reason)
    if state == 'paid' then return true end
    if state ~= 'gone' then return false end
    local buyer = buyerAccountOf(order)
    if s.supplierShare and buyer and buyer ~= s.to then
        local back = payFromEscrow(base .. ':buyer', buyer, s.amount, 'refund', 'Supply payment returned: the supplier\'s account is closed')
        if back == 'waiting' then return false end
        if back == 'paid' then
            recordUnpaid(order.id, s.part, 'returned', s.to, buyer, s.amount)
            return true
        end
    end
    recordUnpaid(order.id, s.part, 'held', s.to, nil, s.amount)
    return true
end

--- Pays the supplier (and the AI markup) for a delivered order; the driver's freight is paid by
--- pf-trucking (or aiDeliver) from the same escrow. Each payout makes at most one new ledger attempt
--- per call (see payoutState), so it is safe to call again after a crash or a refusal; `settled` is
--- set only when every share is paid or settled for good.
function O.Settle(order)
    if tonumber(order.settled) == 1 then return true end
    local okAll = true
    for _, s in ipairs(settlementShares(order)) do
        okAll = settleShare(order, s) and okAll
    end
    if okAll then
        MySQL.update.await('UPDATE pf_store_supply_orders SET settled = 1 WHERE id = ?', { order.id })
    end
    return okAll
end

-- Retry waits for money that could not be moved yet: 15 s, 30 s, ... at most an hour, so a payout
-- or refund the ledger keeps refusing does not write a failed transaction every timer pass. Kept in
-- memory: after a restart everything owed is tried once at once.
local RETRY_MAX_SECONDS = 3600
local function retryWaits() return { fails = {}, at = {} } end
local function retryDue(w, id) return (w.at[id] or 0) <= os.time() end
local function retryResult(w, id, done)
    if done then
        w.fails[id], w.at[id] = nil, nil
        return
    end
    local fails = (w.fails[id] or 0) + 1
    w.fails[id] = fails
    w.at[id] = os.time() + math.min(RETRY_MAX_SECONDS, 15 * 2 ^ math.min(fails - 1, 8))
end
local settleWaits, freightWaits = retryWaits(), retryWaits()
local settling = {}

--- O.Settle, one call at a time per order, with the retry wait.
local function trySettle(order)
    local id = tonumber(order.id)
    if not id or settling[id] then return false end
    settling[id] = true
    local ok, done = pcall(O.Settle, order)
    settling[id] = nil
    if not ok then
        print(('^1[pf-stores]^7 settlement of order %s: %s'):format(tostring(id), tostring(done)))
        done = false
    end
    retryResult(settleWaits, id, done == true)
    return done == true
end

-- ── delivery objects ────────────────────────────────────────────────────────

local function createPallet(order)
    if order.pallet_id or GetResourceState('pfm-worldobjects') ~= 'started' then return nil end
    local route = O.Route(order.buyer_kind, order.store_id)
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
    print(('^1[pf-stores]^7 order %d: delivery pallet not created (%s)'):format(order.id, tostring(ok and 'no object' or objectId)))
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
    -- the delivery time lets perishable goods age for the time they waited packed
    local deliveredAt = (tonumber(order.delivered_at) or nowMs()) / 1000
    -- a missing or impossible time (future, or older than 30 days) counts as delivered just now
    if deliveredAt ~= deliveredAt or deliveredAt > os.time() or deliveredAt < os.time() - 30 * 86400 then deliveredAt = os.time() end
    deliveredAt = math.floor(deliveredAt)
    local ok, done = pcall(adapter.unpack, order.store_id, decode(order.items_json) or {}, order.id, deliveredAt)
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
    trySettle(order)
    if not createPallet(order) and GetResourceState('pfm-worldobjects') ~= 'started' then
        -- no physical pallet available: the goods go straight into stock
        O.Unpack(nil, order.id, 'system')
    end
    return true
end

-- ── creating, cancelling ────────────────────────────────────────────────────

--- Items in one unit of a player supplier's stock of `item` (Config.SupplyChain.CaseSize, default
--- 1). The one place the case size is read, so stocking, matching, reserving and giving stock back
--- all count the same: a whole number of at least 1 (a 0 or fractional setting would let a supplier
--- stock a case for fewer items than it delivers).
local function caseSizeOf(item)
    local per = tonumber(((Config and Config.SupplyChain or {}).CaseSize or {})[type(item) == 'string' and item:lower() or item])
    if not per or per ~= per or per < 1 then return 1 end
    return math.floor(per)
end
O.CaseSizeOf = caseSizeOf

--- Player supplier stock is counted in units of Config.SupplyChain.CaseSize items (default 1). A
--- buyer's line is quantity x caseSize items (caseSize defaults to 1: stores and restaurants order
--- single items; job businesses order parts in cases of 10 and unpack quantity x caseSize items), so
--- the stock a supplier hands over is converted to exactly what the buyer unpacks. Returns the stock
--- units and the most the supplier may ask per unit (the buyer's price for the same items), or nil
--- when the sizes do not divide evenly: then no player supplier can fill the line exactly and the
--- order goes to the AI supplier.
local function supplierUnits(l)
    local qty = math.floor(tonumber(l.quantity) or 0)
    local cost = tonumber(l.cost) or 0
    local size = tonumber(l.caseSize) or 1
    if size <= 0 or size ~= math.floor(size) then return nil end
    local per = caseSizeOf(l.name)
    local items = qty * size
    if items < 1 or items % per ~= 0 then return nil end
    local units = items // per
    if units < 1 then return nil end
    return units, cost * qty / units + 0.0001
end
O.SupplierUnits = supplierUnits

--- An order's lines as a player supplier fills them: what accepting it reserves from their stock.
--- { name, label, units (stock units, i.e. cases), items (items those hold), cost (the buyer's price
--- per unit: what the supplier is paid for it) } per line, or nil when a line cannot be filled from
--- supplier stock.
function O.SupplierLines(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
        local units, maxPrice = supplierUnits(l)
        if not units then return nil end
        out[#out + 1] = { name = l.name, label = l.label, units = units,
            items = math.floor(tonumber(l.quantity) or 0) * math.floor(tonumber(l.caseSize) or 1),
            cost = math.floor((maxPrice - 0.0001) * 100 + 0.5) / 100 }
    end
    return out
end

local function suppliersFor(lines)
    if not cfg().playerSuppliers then return {} end
    local candidates = nil
    for _, l in ipairs(lines) do
        local units, maxPrice = supplierUnits(l)
        if not units then return {} end
        local rows = MySQL.query.await([[SELECT o.supplier_id FROM pf_supplier_offers o JOIN pf_suppliers s ON s.id = o.supplier_id
            WHERE s.active = 1 AND o.item = ? AND o.stock_qty >= ? AND o.unit_price <= ?]], { l.name, units, maxPrice }) or {}
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

-- the same items, quantities and method in the same order
local function sameLines(a, b)
    local function canon(lines)
        local out = {}
        for _, l in ipairs(lines or {}) do out[#out + 1] = tostring(l.name) .. '=' .. tostring(l.quantity) end
        table.sort(out)
        return table.concat(out, ',')
    end
    return canon(a) == canon(b)
end

local function createOrder(src, payload)
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

    -- the same order placed again by the same person a moment later (a double click, a resent event)
    -- returns the order already placed instead of charging twice
    local recent = MySQL.query.await([[SELECT id, total, subtotal, ai_markup, freight_payout, status, items_json, created_at FROM pf_store_supply_orders
        WHERE buyer_kind = ? AND store_id = ? AND owner_citizenid = ? AND method = ? AND created_at >= ?
        AND status NOT IN ('failed', 'cancelled') ORDER BY id DESC LIMIT 5]],
        { kind, buyerId, cid, method, nowMs() - cfg().duplicateWindowSeconds * 1000 }) or {}
    for _, r in ipairs(recent) do
        if sameLines(decode(r.items_json), lines) then
            return { ok = true, duplicate = true, data = { orderId = r.id, total = tonumber(r.total), subtotal = tonumber(r.subtotal),
                markup = tonumber(r.ai_markup), freight = tonumber(r.freight_payout), status = r.status, items = decode(r.items_json),
                createdAt = tonumber(r.created_at) } }
        end
    end
    if not bankReady() or not ensureEscrow() or not adapter.ensureAccount(buyerId) then return { ok = false, error = 'bank_unavailable' } end

    local route = method == 'trucking' and O.Route(kind, buyerId) or nil
    if method == 'trucking' and not route then return { ok = false, error = 'delivery_locations_not_configured' } end
    if method == 'trucking' then
        local minGoods = minDeliveryGoods(route)
        if subtotal < minGoods then
            return { ok = false, error = 'below_delivery_minimum', data = { subtotal = subtotal, minGoods = minGoods },
                message = ('Trucker delivery needs at least %s of goods; this order has %s. Add more, or collect it yourself.'):format(dollars(minGoods), dollars(subtotal)) }
        end
    end
    -- the buyer pays the goods, plus for a delivery the AI markup and the trucker's freight on top
    local price = quote(method, route, subtotal)
    local freight, markup, total = price.freight, price.markup, price.total
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
        return { ok = false, error = charge.error == 'insufficient_funds' and 'insufficient_funds' or 'payment_failed',
            data = { total = total, subtotal = subtotal, markup = markup, freight = freight } }
    end
    O.Transition(orderId, 'created', 'paid', cid, 'paid', { payment_tx = charge.txId, payment_state = 'paid' })

    if method == 'pickup' then
        O.Transition(orderId, 'paid', 'ready', 'system', 'ready for pickup', { supplier_kind = 'ai', supplier_ref = AI_SUPPLIER, settled = 1 })
        if not payload.deferDelivery then
            O.Transition(orderId, 'ready', 'delivered', cid, 'collected', { delivered_at = nowMs() })
            local res = O.Unpack(nil, orderId, cid)
            if not res.ok then return res end
        end
        return { ok = true, data = { orderId = orderId, total = total, subtotal = subtotal, markup = 0, freight = 0, items = lines, createdAt = createdAt } }
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
    return { ok = true, data = { orderId = orderId, total = total, subtotal = subtotal, markup = markup, freight = freight, status = order.status,
        contractId = contractId(orderId), items = lines, createdAt = createdAt } }
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

local function refundKey(orderId, attempt)
    attempt = math.floor(tonumber(attempt) or 0)
    if attempt > 0 then return key(orderId, 'cancel:' .. attempt) end
    return key(orderId, 'cancel')
end

-- Every payout from escrow an order can have besides its cancellation refund: the first key of each
-- (the later attempts are numbered after it), and pf-trucking's rental fee (a fixed key).
local function escrowPayoutBases(orderId)
    local freight = ('freight:supply:%d'):format(orderId)
    local out = { freight, freight .. ':rental' }
    for _, part in ipairs({ 'markup-supplier', 'markup-refund', 'supplier', 'markup' }) do
        out[#out + 1] = key(orderId, part)
        out[#out + 1] = key(orderId, part) .. ':buyer'
    end
    return out
end

-- What already left escrow for an order before it was cancelled: orders accepted by a player
-- supplier before the markup split moved to delivery had it paid at accept (to the supplier and back
-- to the buyer). The other payouts are counted too, so a refund can never make escrow pay out more
-- for an order than it took in, whatever happened to it. nil while one of them is still being
-- settled by the ledger.
local function paidOutOfEscrow(order)
    local out = 0
    for _, base in ipairs(escrowPayoutBases(order.id)) do
        for n = 0, MAX_PAYOUT_ATTEMPTS do
            local tx = ledgerTx(attemptKey(base, n))
            if not tx then break end
            if tx.from_account == ESCROW then
                if tx.state == 'completed' then
                    out = out + (tonumber(tx.amount) or 0)
                elseif not attemptOver(tx) then
                    return nil
                end
            end
        end
    end
    return round2(out)
end

local refunding = {}

local function refundCancelled(orderId)
    local order = O.Get(orderId)
    if not order or order.status ~= 'cancelled' then return false end
    if order.refund_state == 'done' then return true end
    if order.refund_state ~= 'pending' then return false end
    local paid = paidOutOfEscrow(order)
    if not paid then return false end
    -- the escrowed total less what already left escrow for this order: escrow never pays out more
    -- for an order than it took in
    local amount = round2((tonumber(order.total) or 0) - paid)
    if amount <= 0 then
        MySQL.update.await("UPDATE pf_store_supply_orders SET refund_state = 'done' WHERE id = ? AND refund_state = 'pending'", { order.id })
        return true, 0
    end
    local to = buyerAccountOf(order)
    if not to then return false end
    local attempt = math.floor(tonumber(order.refund_attempt) or 0)
    local k = refundKey(order.id, attempt)
    local tx = ledgerTx(k)
    if tx and attemptOver(tx) then
        -- A buyer account that refused the refund PAYEE_GONE_ATTEMPTS times because it no longer
        -- exists is gone for good (as pf-services' forfeited refunds): the money stays in escrow,
        -- recorded for staff, and the retries stop.
        local gone = 0
        for n = 0, attempt do
            local t = n == attempt and tx or ledgerTx(refundKey(order.id, n))
            if t and payeeRefused(t) then gone = gone + 1 end
        end
        if gone >= PAYEE_GONE_ATTEMPTS then
            local n = MySQL.update.await("UPDATE pf_store_supply_orders SET refund_state = 'forfeited' WHERE id = ? AND refund_state = 'pending'", { order.id })
            if not n or n < 1 then return false end
            recordUnpaid(order.id, 'cancel', 'held', to, nil, amount)
            return true, 0, 'forfeited'
        end
        -- the ledger keeps a failed transfer under its key (the same key returns that failure again):
        -- the next try needs a fresh key, taken by one caller only
        local changed = MySQL.update.await('UPDATE pf_store_supply_orders SET refund_attempt = ? WHERE id = ? AND refund_attempt = ?',
            { attempt + 1, order.id, attempt })
        if not changed or changed < 1 then return false end
        attempt = attempt + 1
        k = refundKey(order.id, attempt)
    elseif tx and tx.state ~= 'completed' then
        return false   -- unclear (still in flight): the ledger's recovery settles it, the next pass continues
    end
    local r = transfer({ from = ESCROW, to = to, amount = amount, key = k, kind = 'refund', reason = 'Supply order cancelled' })
    if r.ok then
        MySQL.update.await("UPDATE pf_store_supply_orders SET refund_state = 'done' WHERE id = ? AND refund_state = 'pending'", { order.id })
        return true, amount
    end
    print(('^1[pf-stores]^7 refund of cancelled order %d failed (%s); retried by the order timer'):format(order.id, tostring(r.error)))
    return false
end

-- failed refunds wait before the next try (retryWaits: 15 s, 30 s, ... at most an hour)
local refundWaits = retryWaits()

--- Refunds a cancelled order's escrow to the buyer, once. Safe to call again and from several
--- places (cancel, start, the order timer): returns true (and the amount when this call paid it)
--- once the refund is done or forfeited (third value 'forfeited': the buyer's account is gone for
--- good and the money is held in escrow), false while it is still owed.
function O.RefundCancelled(orderId)
    orderId = tonumber(orderId)
    if not orderId or refunding[orderId] then return false end
    refunding[orderId] = true
    local ok, done, amount, outcome = pcall(refundCancelled, orderId)
    refunding[orderId] = nil
    if not ok then
        print(('^1[pf-stores]^7 refund of cancelled order %s: %s'):format(tostring(orderId), tostring(done)))
        done = false
    end
    retryResult(refundWaits, orderId, done == true)
    if done == true then return true, amount, outcome end
    return false
end

--- Retries every cancellation refund still owed whose wait is over (all of them with `all`, as at
--- start). Returns how many were refunded.
function O.RetryRefunds(all)
    local n = 0
    for _, order in ipairs(MySQL.query.await("SELECT id FROM pf_store_supply_orders WHERE status = 'cancelled' AND refund_state = 'pending'") or {}) do
        local id = tonumber(order.id)
        if all or retryDue(refundWaits, id) then
            local done, _, outcome = O.RefundCancelled(id)
            if done and outcome ~= 'forfeited' then n = n + 1 end
        end
    end
    return n
end

--- Cancels an order that no driver has picked up, refunding what the buyer paid into escrow (less
--- anything that already left escrow for it). Reserved player-supplier stock goes back to the
--- supplier. A refund that cannot be made now stays owed and is retried.
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
    -- the refund is owed from the moment the order is cancelled (same UPDATE), so a failed or
    -- interrupted refund is found again by the retries
    if not O.Transition(order.id, from, 'cancelled', cid, 'cancelled by buyer', { cancelled_at = nowMs(), refund_state = 'pending' }) then
        return { ok = false, error = 'not_cancellable' }
    end
    if order.supplier_kind == 'player' and order.supplier_ref then O.ReturnSupplierStock(order) end
    local done, amount = O.RefundCancelled(order.id)
    if not done then
        return { ok = true, data = { orderId = order.id, refundPending = true } }
    end
    return { ok = true, data = { orderId = order.id, refunded = amount } }
end

-- One order at a time per business: a second request while one is being placed is refused rather
-- than racing it (both would pass the duplicate check before either is stored).
local creating = {}

--- Places an order. payload = { kind, buyerId, method = 'trucking' | 'pickup', cart, deferDelivery }
--- Returns { ok, data = { orderId, ... }, duplicate = true when it is a repeat of a moment ago }.
function O.Create(src, payload)
    payload = type(payload) == 'table' and payload or {}
    local lockKey = tostring(payload.kind) .. ':' .. tostring(payload.buyerId)
    if creating[lockKey] then return { ok = false, error = 'busy' } end
    creating[lockKey] = true
    local ok, res = pcall(createOrder, src, payload)
    creating[lockKey] = nil
    if not ok then
        print(('^1[pf-stores]^7 order creation failed: %s'):format(tostring(res)))
        return { ok = false, error = 'internal_error' }
    end
    return res
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
    local per = caseSizeOf(item)
    local inv = exports['pfm-inventory']
    local okP, perishable = pcall(function() return inv:IsPerishable(item) end)
    if okP and perishable then
        -- Food is stocked only while still fresh enough: supplier stock is counted in cases and is
        -- delivered as a new batch, so stale or spoiled food would otherwise come out fresh.
        local accepted = (Config.SupplyChain or {}).StockFreshness or { fresh = true, good = true }
        local plan, left = {}, cases * per
        for _, it in ipairs(inv:GetItemsByName(src, item) or {}) do
            if left <= 0 then break end
            local f = inv:GetFreshness(it.name, it.info)
            if f and accepted[f.state] then
                local n = math.min(left, tonumber(it.amount) or 0)
                if n > 0 then
                    plan[#plan + 1] = { slot = it.slot, amount = n, info = type(it.info) == 'table' and json.decode(json.encode(it.info)) or nil }
                    left = left - n
                end
            end
        end
        if left > 0 then return { ok = false, error = 'not_fresh_enough' } end
        local taken = {}
        for _, p in ipairs(plan) do
            if not inv:RemoveItem(src, item, p.amount, p.slot, 'pf-supply:stock') then
                for _, back in ipairs(taken) do inv:AddItem(src, item, back.amount, false, back.info, 'pf-supply:stock-undo') end
                return { ok = false, error = 'missing_items' }
            end
            taken[#taken + 1] = p
        end
    elseif not inv:RemoveItem(src, item, cases * per, false, 'pf-supply:stock') then
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
    local share = math.max(0, math.min(1, cfg().supplierShareOfMarkup))
    for _, order in ipairs(rows) do
        for _, id in ipairs(suppliersFor(decode(order.items_json) or {})) do
            if id == tonumber(sup.id) then
                -- what the supplier is paid when it is delivered: the goods and their share of the markup
                local items = decode(order.items_json)
                out[#out + 1] = { orderId = order.id, items = items, lines = O.SupplierLines(items), subtotal = tonumber(order.subtotal),
                    pays = O.GoodsShare(order), bonus = round2((tonumber(order.ai_markup) or 0) * share) }
            end
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

--- A player supplier takes an open order: their stock is reserved atomically and the delivery is
--- posted to truckers. No money moves yet: the supplier's goods share and markup bonus, and the
--- part of the AI markup that goes back to the buyer, are paid when the order is delivered.
function O.AcceptSupply(src, orderId)
    local sup = supplierOf(src)
    if not sup or tonumber(sup.active) ~= 1 then return { ok = false, error = 'not_a_supplier' } end
    local order = O.Get(orderId)
    if not order or order.status ~= 'awaiting_supplier' then return { ok = false, error = 'not_open' } end
    local lines = decode(order.items_json) or {}
    local reserved = {}
    for _, l in ipairs(lines) do
        local units, maxPrice = supplierUnits(l)
        local changed = units and MySQL.update.await([[UPDATE pf_supplier_offers SET stock_qty = stock_qty - ?
            WHERE supplier_id = ? AND item = ? AND stock_qty >= ? AND unit_price <= ?]], { units, sup.id, l.name, units, maxPrice })
        if not changed or changed < 1 then
            for _, r in ipairs(reserved) do
                MySQL.update.await('UPDATE pf_supplier_offers SET stock_qty = stock_qty + ? WHERE supplier_id = ? AND item = ?', { r.units, sup.id, r.name })
            end
            return { ok = false, error = 'not_enough_stock' }
        end
        reserved[#reserved + 1] = { name = l.name, units = units }
        -- what was really taken from the supplier, so a cancel gives back exactly that
        l.reservedUnits = units
    end
    local cid = citizenOf(src)
    if not O.Transition(order.id, 'awaiting_supplier', 'awaiting_delivery', cid, 'player supplier ' .. sup.name,
        { supplier_kind = 'player', supplier_ref = cid, driver_deadline = nowMs() + cfg().driverPrioritySeconds * 1000,
          items_json = json.encode(lines) }) then
        for _, r in ipairs(reserved) do
            MySQL.update.await('UPDATE pf_supplier_offers SET stock_qty = stock_qty + ? WHERE supplier_id = ? AND item = ?', { r.units, sup.id, r.name })
        end
        return { ok = false, error = 'not_open' }
    end
    O.PostContract(O.Get(order.id), false)
    return { ok = true, data = { orderId = order.id } }
end

--- Gives a player supplier back the stock reserved for an order (on cancel). It is the reservation
--- recorded on the order's lines at accept (reservedUnits, in the supplier's own stock units), not a
--- recount from the line, so a CaseSize change in between cannot give back more or less than was taken.
function O.ReturnSupplierStock(order)
    local sup = MySQL.single.await('SELECT id FROM pf_suppliers WHERE citizenid = ?', { order.supplier_ref })
    if not sup then return end
    for _, l in ipairs(decode(order.items_json) or {}) do
        -- orders accepted before reservations were recorded reserved their line quantity
        local units = math.floor(tonumber(l.reservedUnits) or tonumber(l.quantity) or 0)
        if units > 0 then
            MySQL.update.await('UPDATE pf_supplier_offers SET stock_qty = stock_qty + ? WHERE supplier_id = ? AND item = ?', { units, sup.id, l.name })
        end
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

-- pf-trucking (re)started: re-post the open contracts. Before this resource's own migrations have run
-- the order table may still lack the lifecycle columns (seen on staging, where pf-trucking started
-- first); O.Start's caller recovers the contracts itself once the migrations are done.
AddEventHandler('pf-trucking:server:started', function()
    if not O.ready then return end
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
    -- AI driver: the freight share goes to the AI freight account. Its first key is the one a player
    -- driver is paid under (pf-trucking), so the trip is paid exactly once whoever drove it; after a
    -- stored failure (escrow short) the next numbered key is tried, after the retry wait.
    local freight = tonumber(order.freight_payout) or 0
    if freight > 0 and payFromEscrow(('freight:supply:%d'):format(order.id), AI_FREIGHT, freight, 'wage', 'AI delivery') ~= 'paid' then
        return false
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
        local id = tonumber(order.id)
        if retryDue(freightWaits, id) then
            local ok, delivered = pcall(aiDeliver, order)
            if not ok then print(('^1[pf-stores]^7 AI delivery of order %s: %s'):format(tostring(id), tostring(delivered))) end
            retryResult(freightWaits, id, ok and delivered == true)
        end
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
    -- retries (each after its wait): money for delivered orders, and pallets that could not be placed
    for _, order in ipairs(MySQL.query.await("SELECT " .. ORDER_COLUMNS .. " FROM pf_store_supply_orders WHERE status IN ('delivered', 'unpacked') AND settled = 0") or {}) do
        if retryDue(settleWaits, tonumber(order.id)) then trySettle(order) end
    end
    -- cancellation refunds that could not be made yet (each after its retry wait)
    O.RetryRefunds(false)
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
    -- cancellation refunds still owed (failed, or interrupted by a restart)
    local n = O.RetryRefunds(true)
    if n > 0 then print(('[pf-stores] refunded %d cancelled supply order(s)'):format(n)) end
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

--- A buyer's recent orders (for the business apps), when `src` may manage that buyer.
function O.ListFor(src, kind, buyerId, limit)
    local adapter = O.kinds[kind]
    if not adapter or not adapter.canManage(src, tostring(buyerId)) then return { ok = false, error = 'not_owner' } end
    local rows = MySQL.query.await('SELECT ' .. ORDER_COLUMNS .. ' FROM pf_store_supply_orders WHERE buyer_kind = ? AND store_id = ? ORDER BY id DESC LIMIT ?',
        { kind, tostring(buyerId), math.max(1, math.min(tonumber(limit) or 50, 200)) }) or {}
    for _, r in ipairs(rows) do r.items = decode(r.items_json) or {} end
    return { ok = true, data = rows }
end

exports('ListOrdersFor', function(src, kind, buyerId, limit) return O.ListFor(src, kind, buyerId, limit) end)
exports('CreateOrder', function(src, payload) return O.Create(src, payload) end)
exports('CancelOrder', function(src, kind, buyerId, orderId) return O.Cancel(src, kind, buyerId, orderId) end)
exports('CollectOrder', function(src, kind, buyerId, orderId) return O.Collect(src, kind, buyerId, orderId) end)
exports('UnpackSupplyOrder', function(src, orderId) return O.Unpack(src, orderId) end)
exports('GetOrder', function(orderId) return O.Get(orderId) end)
exports('GetOrderHistory', function(orderId)
    return MySQL.query.await('SELECT from_status, to_status, actor, note, at FROM pf_supply_order_events WHERE order_id = ? ORDER BY id', { tonumber(orderId) }) or {}
end)
exports('RegisterBuyerKind', function(kind, adapter) return O.RegisterBuyerKind(kind, adapter) end)
-- where a buyer's deliveries go (own delivery point, else the government zone); nil = no delivery
exports('GetDeliveryRoute', function(kind, buyerId) return O.Route(kind, buyerId) end)
-- what a delivery adds on top of the goods for a buyer ({ markupRate, freight = { rate, flat, min,
-- max }, markupRefundShare }; nil = no delivery), for the order screens' estimate
exports('GetDeliveryPricing', function(kind, buyerId) return O.Pricing(kind, buyerId) end)
-- the price of goods worth `subtotal` as an order would be charged ({ subtotal, markup, freight, total })
exports('QuoteOrder', function(kind, buyerId, method, subtotal) return O.Quote(kind, buyerId, method, subtotal) end)
--- Server-only, for staff tools: shares of orders whose payee's account was gone for good, newest
--- first. outcome 'held' = still in the escrow account (society:freight_escrow); 'returned' = paid
--- back to the buyer instead.
function O.ListUnpaid(outcome, limit)
    limit = math.max(1, math.min(math.floor(tonumber(limit) or 50), 500))
    if outcome ~= nil and outcome ~= 'held' and outcome ~= 'returned' then return {} end
    local rows = MySQL.query.await('SELECT order_id, part, outcome, payee, paid_to, amount, at FROM pf_supply_order_payouts'
        .. (outcome and ' WHERE outcome = ?' or '') .. ' ORDER BY at DESC LIMIT ?', outcome and { outcome, limit } or { limit }) or {}
    for _, r in ipairs(rows) do r.amount = tonumber(r.amount) end
    return rows
end
exports('ListUnpaidSupplyPayouts', function(outcome, limit) return O.ListUnpaid(outcome, limit) end)
exports('CanManageOrderBuyer', function(src, orderId)
    local order = O.Get(orderId)
    local adapter = order and O.kinds[order.buyer_kind]
    return adapter ~= nil and adapter.canManage(src, order.store_id) == true
end)

--- One open order as a supplier sees it: what accepting it takes from their stock (in their own
--- cases, O.SupplierLines) and what they are paid on delivery.
function O.DescribeOffer(o, sharedItems)
    local parts = {}
    for _, l in ipairs(o.lines or {}) do
        local def = sharedItems and sharedItems[l.name]
        local label = l.label and l.label ~= l.name and l.label or (def and def.label) or tostring(l.name)
        local per = l.units > 0 and math.floor(l.items / l.units) or 1
        local cases = ('%d %s of %s'):format(l.units, l.units == 1 and 'case' or 'cases', label)
        if per > 1 then cases = cases .. (' (%d per case, %d items)'):format(per, l.items) end
        parts[#parts + 1] = ('%s at %s a case'):format(cases, dollars(l.cost))
    end
    return ('#%d: %s. Pays %s + %s bonus on delivery. /supplyaccept %d'):format(o.orderId, table.concat(parts, ', '),
        dollars(o.pays or 0), dollars(o.bonus or 0), o.orderId)
end

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
            TriggerClientEvent('chat:addMessage', src, { args = { 'Supply', O.DescribeOffer(o, QB.Shared.Items) } })
        end
        if #res.data == 0 then TriggerClientEvent('QBCore:Notify', src, 'No open orders you can fill', 'primary') end
    end)
    QB.Commands.Add('supplyaccept', 'Supply an open order', { { name = 'order', help = 'Order number' } }, true, function(src, args)
        reply(src, O.AcceptSupply(src, tonumber(args[1])))
    end)
    -- staff: supply payouts nobody could take (deleted characters), held in the escrow account
    QB.Commands.Add('supplyheld', 'Supply order payouts held in escrow (staff)', {}, false, function(src)
        local rows = O.ListUnpaid('held', 20)
        for _, r in ipairs(rows) do
            TriggerClientEvent('chat:addMessage', src, { args = { 'Supply', ('#%d %s: %s for %s, held in escrow'):format(tonumber(r.order_id) or 0,
                tostring(r.part), dollars(r.amount or 0), tostring(r.payee or 'unknown')) } })
        end
        if #rows == 0 then TriggerClientEvent('QBCore:Notify', src, 'No supply payouts are held', 'primary') end
    end, 'admin')
end)
