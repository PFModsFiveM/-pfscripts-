-- =====================================================
-- DEPARTMENTS: PROCUREMENT AND FLEET MAINTENANCE (batch 20C)
-- =====================================================
-- Supplies for the public-service facilities (hospital supply rooms, the prison infirmary and
-- kitchen, the police supply room) are bought through the one supply-order service, pf-stores, as
-- the buyer kind 'facility'. Nothing here moves money itself:
--   * a department manager (Config.Departments.ManagerGrade, or the boss) places the order; the
--     order is priced from the facility catalog below (never from the client) and pf-stores charges
--     the department's linked society account once, under its own ledger key supply:<orderId>:charge;
--   * the goods are driven by a pf-trucking contract (SUP-<orderId>) or the AI driver, put down as a
--     pallet at the facility's delivery point and unpacked into the facility stash by on-duty staff;
--   * every purchase is one row in pf_gov_dept_procurements (20E's v7 table): created -> paid ->
--     delivered, or failed / cancelled. A charge whose ledger result is unclear is held as
--     payment_pending (no new order for that facility until the ledger answers) and settled by
--     P.ReconcileTick; a charge that completes for an order pf-stores already failed is held as
--     charge_held for staff (the money sits in the supply escrow) and never charged again.
--   * the department's books get one society_spend line per delivered purchase
--     (BudgetRecordSocietyPayout, key pf-government:dept:<dept>:procurement:<id>; it moves no money).
--
-- Fleet maintenance is a pf-services request kind, 'mechanic.fleet', registered here once (pf-services
-- keeps one handler per kind, so the departments share this one). A department member or a fleet
-- owner resource asks for service of a damaged fleet vehicle; the vehicle's health is read on the
-- server; pf-jobgarages marks it due, then in_service while a mechanic has it; the mechanic's
-- completion counts only when the server sees the vehicle repaired next to them, and the proof is
-- pf-jobgarages SetServiceState(plate, 'ok', { body, engine }) succeeding. A client claim is never
-- part of the proof.
--
-- In-world paths (no UI of their own; the department app of 20E calls GovDept.Procurement):
--   /procure <buyer> <item> <cases>   managers order one catalog line for a facility
--   /supplyroom                       on-duty staff open the stock stash they stand at
--   /fleetservice                     on-duty staff report the fleet vehicle they are in or next to

GovDept = GovDept or {}
local D = GovDept
D.Procurement = D.Procurement or {}
local P = D.Procurement
local U = D.U

-- ── settings (Config.Procurement overrides any of them) ─────────────────
-- Every position is a first placement: check each one in game and move it if needed.
P.DEFAULTS = {
    Enabled = true,
    Kind = 'facility',
    -- the pf-stores warehouse the trucker loads at, and the trucking contract's pay
    Pickup = { label = 'State Supply Warehouse', coords = { x = 1201.02, y = -3237.56, z = 6.06, w = 0.0 } },
    Trucking = { title = 'Public service supplies', cargoType = 'Facility Supplies', payoutRate = 0.10, payoutMin = 200, payoutMax = 1500 },
    BudgetCategory = 'operations',
    StashReach = 3.0,              -- staff to a stash point (server position) for /supplyroom
    MaxLines = 20, MaxCases = 200, -- per order
    ReconcileSeconds = 60,
    PlacingStaleSeconds = 120,     -- a row left 'created' this long (crash while ordering) is looked up
    -- buyer id -> the facility: its department, the stash its goods go into, where staff open that
    -- stash and where a trucker drops the pallet, and which catalog prices it
    Buyers = {
        ['ems:pillbox'] = {
            dept = 'ems', label = 'Pillbox supply room', catalog = 'medical',
            stash = { id = 'pf_hosp_supply_pillbox', label = 'Pillbox supply room', slots = 50, maxweight = 600000 },
            point = { x = 339.6, y = -583.9, z = 43.28 },
            dropoff = { x = 294.3, y = -609.9, z = 43.35, w = 70.0 },
        },
        ['ems:paleto'] = {
            dept = 'ems', label = 'Paleto supply room', catalog = 'medical',
            stash = { id = 'pf_hosp_supply_paleto', label = 'Paleto supply room', slots = 40, maxweight = 400000 },
            point = { x = -250.1, y = 6316.6, z = 32.43 },
            dropoff = { x = -240.6, y = 6334.4, z = 32.4, w = 225.0 },
        },
        -- the pharmacy stock of 20A (pf-ambulancejob Config.Hospital.Pharmacy.Stashes): no stash
        -- point here on purpose, so /supplyroom never opens it; staff draw from it only through the
        -- pharmacy, which logs every controlled drug
        ['ems:pillbox_pharmacy'] = {
            dept = 'ems', label = 'Pillbox pharmacy', catalog = 'pharmacy',
            stash = { id = 'pf_pharmacy_pillbox', label = 'Pillbox pharmacy stock', slots = 40, maxweight = 200000 },
            dropoff = { x = 294.3, y = -609.9, z = 43.35, w = 70.0 },
        },
        ['ems:paleto_pharmacy'] = {
            dept = 'ems', label = 'Paleto pharmacy', catalog = 'pharmacy',
            stash = { id = 'pf_pharmacy_paleto', label = 'Paleto pharmacy stock', slots = 30, maxweight = 100000 },
            dropoff = { x = -240.6, y = 6334.4, z = 32.4, w = 225.0 },
        },
        ['corrections:bolingbroke_infirmary'] = {
            dept = 'corrections', label = 'Bolingbroke infirmary stock', catalog = 'infirmary',
            stash = { id = 'pf_infirmary_bolingbroke', label = 'Infirmary stock', slots = 30, maxweight = 100000 },
            point = { x = 1766.9, y = 2594.8, z = 45.66 },
            dropoff = { x = 1846.2, y = 2585.9, z = 45.67, w = 270.0 },
        },
        ['corrections:bolingbroke_kitchen'] = {
            dept = 'corrections', label = 'Bolingbroke kitchen pantry', catalog = 'kitchen',
            stash = { id = 'pfm_prison_pantry', label = 'Prison pantry', slots = 20, maxweight = 600000 },
            point = { x = 1780.4, y = 2563.0, z = 45.67 },
            dropoff = { x = 1846.2, y = 2585.9, z = 45.67, w = 270.0 },
        },
        ['police:mrpd_armory'] = {
            dept = 'police', label = 'MRPD supply room', catalog = 'police',
            stash = { id = 'pf_police_supply_mrpd', label = 'MRPD supply room', slots = 50, maxweight = 600000 },
            point = { x = 482.6, y = -995.4, z = 30.69 },
            dropoff = { x = 452.3, y = -1018.2, z = 28.45, w = 90.0 },
        },
    },
    -- catalog -> item -> { price per case (whole dollars), caseSize items per case }
    Catalogs = {
        medical = {
            bandage = { price = 60, caseSize = 10 }, ifaks = { price = 160, caseSize = 4 },
            painkillers = { price = 70, caseSize = 10 }, tourniquet = { price = 90, caseSize = 4 },
            pressure_dressing = { price = 80, caseSize = 6 }, hemostatic_gauze = { price = 140, caseSize = 4 },
            chest_seal = { price = 120, caseSize = 4 }, splint = { price = 90, caseSize = 4 },
            c_collar = { price = 80, caseSize = 2 }, iv_kit = { price = 100, caseSize = 4 },
            saline_bag = { price = 90, caseSize = 4 }, burn_dressing = { price = 100, caseSize = 4 },
            suture_kit = { price = 150, caseSize = 4 }, nitrile_gloves = { price = 30, caseSize = 10 },
        },
        -- every item of pf-ambulancejob's pharmacy formulary and ward list (Config.Hospital.Pharmacy)
        pharmacy = {
            painkillers = { price = 70, caseSize = 10 }, bandage = { price = 60, caseSize = 10 }, antibiotics = { price = 200, caseSize = 6 },
            naloxone = { price = 180, caseSize = 4 }, txa = { price = 220, caseSize = 4 }, epinephrine = { price = 160, caseSize = 4 },
            morphine = { price = 260, caseSize = 4 }, fentanyl = { price = 300, caseSize = 4 }, crutches = { price = 120, caseSize = 1 },
        },
        infirmary = {
            painkillers = { price = 70, caseSize = 10 }, bandage = { price = 60, caseSize = 10 },
            ifaks = { price = 160, caseSize = 4 },
        },
        kitchen = {
            prison_food_stock = { price = 120, caseSize = 10 }, -- registered by pfm-prison (server/supplies.lua)
        },
        police = {
            pistol_ammo = { price = 150, caseSize = 5 }, zipties = { price = 40, caseSize = 10 },
            empty_evidence_bag = { price = 30, caseSize = 10 }, nitrile_gloves = { price = 30, caseSize = 10 },
            bandage = { price = 60, caseSize = 10 }, ifaks = { price = 160, caseSize = 4 },
        },
    },
    -- resources that may use the procurement exports (this resource always may)
    Callers = { ['pf-ambulancejob'] = true, ['pfm-prison'] = true, ['pfm-policejob'] = true, ['pf-emsmdt'] = true, ['pf-policemdt-DEV'] = true },
    Fleet = {
        Enabled = true,
        Kind = 'mechanic.fleet',
        Jobs = nil,            -- nil: the jobs of pf-services 'mechanic.roadside' (every mechanic shop)
        DueBody = 850,         -- a vehicle below either value needs service
        DueEngine = 850,
        ServicedBody = 950,    -- the server must read at least these after the repair
        ServicedEngine = 950,
        ReportRange = 6.0,     -- staff to the vehicle they report (server positions)
        ServiceRange = 12.0,   -- mechanic to the vehicle when completing (server positions)
        Reward = 150,          -- call-out fee from the department society (escrowed by pf-services)
        Expires = 7200,
        -- resource -> the fleet jobs it may ask service for (system requests, no player actor)
        Requesters = {
            ['pf-ambulancejob'] = { ambulance = true },
            ['pfm-prison'] = { corrections = true },
            ['pfm-policejob'] = { police = true },
        },
    },
}

local function merged(base, over)
    if type(over) ~= 'table' then return base end
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(over) do out[k] = v end
    return out
end

function P.Cfg()
    local c = merged(P.DEFAULTS, Config.Procurement)
    c.Fleet = merged(P.DEFAULTS.Fleet, type(Config.Procurement) == 'table' and Config.Procurement.Fleet or nil)
    return c
end
local cfg = P.Cfg

local function now() return os.time() end
local function fail(code, message) return U.fail(code, message) end
local function round(n) return math.floor((tonumber(n) or 0) + 0.5) end

local function dept(id) return (cfg().Buyers[id] or {}).dept end

--- The ledger society of a department (Config.Budgets.LinkedSocietyAccounts; ems -> ambulance).
function P.Society(deptId)
    local map = (Config.Budgets and Config.Budgets.LinkedSocietyAccounts) or {}
    return map[deptId] or deptId
end

local function knownItem(name)
    local items = QBCore and QBCore.Shared and QBCore.Shared.Items
    if items and items[name] then return true end
    -- items registered at runtime (pfm-core AddItems) are missing from an older core snapshot
    local ok, core = pcall(function() return exports['pfm-core']:GetCoreObject({ 'Shared' }) end)
    return ok and type(core) == 'table' and core.Shared and core.Shared.Items and core.Shared.Items[name] ~= nil or false
end

local function inv(name, ...)
    local args, n = { ... }, select('#', ...)
    local ok, res = pcall(function()
        local e = exports['pfm-inventory']
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok then return nil end
    return res
end

function P.EnsureStash(s)
    if type(s) ~= 'table' or type(s.id) ~= 'string' then return false end
    if not inv('GetInventory', s.id) then inv('CreateInventory', s.id, { label = s.label, maxweight = s.maxweight, slots = s.slots }) end
    return inv('GetInventory', s.id) ~= nil
end

local function vec(c) return vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0) end
local function posOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end
local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ── who may do what ─────────────────────────────────────────────────────

--- On-duty member of the buyer's department (unpack, list, open its stash).
function P.IsStaff(src, buyerId)
    local d = dept(buyerId)
    local m = D.Member(src)
    return d ~= nil and m ~= nil and m.dept == d and m.onDuty == true, m
end

--- Places and cancels orders: an on-duty manager (ManagerGrade) or the boss of the department.
function P.CanOrder(src, buyerId)
    local staff, m = P.IsStaff(src, buyerId)
    return staff and (m.manager == true or m.isBoss == true), m
end

-- The adapter's canManage gates every pf-stores action on a facility order (create, cancel, list,
-- unpack); it cannot tell them apart, so on-duty staff pass it (they unpack the pallet at the dock).
-- Ordering and cancelling go through P.Create / P.Cancel, which check the manager first and hold
-- these marks while pf-stores runs: canManage then answers for that facility only, and the
-- adapter prices a cart only while P.Create holds the facility, so nothing can order on a
-- department's account by calling pf-stores directly.
P.placing = P.placing or {}   -- [src] = buyerId while P.Create / P.Cancel calls pf-stores
P.ordering = P.ordering or {} -- [buyerId] = true while P.Create places its order

-- ── the pf-stores buyer adapter ─────────────────────────────────────────

P.Adapter = {
    canManage = function(src, buyerId)
        src = tonumber(src)
        if not src then return false end
        if P.placing[src] ~= nil then return P.placing[src] == buyerId end
        return (P.IsStaff(src, buyerId)) == true
    end,
    account = function(buyerId)
        local d = dept(buyerId)
        return d and ('society:' .. P.Society(d)) or nil
    end,
    ensureAccount = function(buyerId)
        local d = dept(buyerId)
        if not d then return false end
        local ok, exists = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(P.Society(d), 'job') end)
        return ok and exists == true
    end,
    governmentId = function() return nil end,
    -- server prices: { name, quantity (cases) } -> lines { name, label, quantity, cost (per case), category, caseSize }
    price = function(buyerId, cart)
        if not P.ordering[buyerId] then return nil, 0 end
        local b = cfg().Buyers[buyerId]
        local catalog = b and cfg().Catalogs[b.catalog]
        if not catalog or type(cart) ~= 'table' or #cart == 0 or #cart > cfg().MaxLines then return nil, 0 end
        local lines, subtotal, seen = {}, 0, {}
        for _, c in ipairs(cart) do
            local name = type(c) == 'table' and type(c.name) == 'string' and c.name:lower() or nil
            local entry = name and catalog[name]
            local qty = type(c) == 'table' and U.int(c.quantity, 1, cfg().MaxCases) or nil
            local price = entry and U.int(entry.price, 0, 1000000)
            local size = entry and U.int(entry.caseSize or 1, 1, 1000)
            if not entry or not qty or not price or not size or seen[name] or not knownItem(name) then return nil, 0 end
            seen[name] = true
            lines[#lines + 1] = { name = name, label = entry.label or name, quantity = qty, cost = price, category = b.catalog, caseSize = size }
            subtotal = subtotal + price * qty
        end
        return lines, subtotal
    end,
    route = function(buyerId)
        local b = cfg().Buyers[buyerId]
        if not b or type(b.dropoff) ~= 'table' then return false end
        local d = b.dropoff
        return {
            pickup = cfg().Pickup,
            dropoff = { label = b.label, coords = { x = d.x, y = d.y, z = d.z } },
            unload = { label = b.label .. ' dock', coords = { x = d.x, y = d.y, z = d.z, w = d.w or 0.0 } },
            trucking = cfg().Trucking,
        }
    end,
    -- all of it or none (pf-stores puts the order back to delivered when this fails)
    unpack = function(buyerId, lines, orderId, deliveredAt)
        return P.Unpack(buyerId, lines, orderId, deliveredAt)
    end,
}

function P.Unpack(buyerId, lines, orderId, deliveredAt)
    local b = cfg().Buyers[buyerId]
    if not b or not P.EnsureStash(b.stash) then return false end
    local added, moved = {}, {}
    for _, l in ipairs(type(lines) == 'table' and lines or {}) do
        local units = math.floor((tonumber(l.quantity) or 0) * (tonumber(l.caseSize) or 1))
        local info = nil
        if deliveredAt then info = inv('DeliveredInfo', l.name, deliveredAt) end
        if units < 1 or inv('AddItem', b.stash.id, l.name, units, nil, info, 'pf-government:procurement:' .. tostring(orderId)) ~= true then
            for _, a in ipairs(added) do inv('RemoveItem', b.stash.id, a.name, a.units, nil, 'pf-government:procurement-undo') end
            return false
        end
        added[#added + 1] = { name = l.name, units = units }
        moved[#moved + 1] = { item = l.name, qty = units }
    end
    inv('SaveStash', b.stash.id)
    local row = MySQL.single.await('SELECT id, dept, total FROM pf_gov_dept_procurements WHERE store_order_id = ? LIMIT 1', { tonumber(orderId) })
    if row then
        MySQL.update.await("UPDATE pf_gov_dept_procurements SET state = 'delivered', updated_at = ? WHERE id = ? AND state IN ('created', 'paid', 'payment_pending')",
            { now(), row.id })
        P.Book(row)
    end
    D.Audit(b.dept, 'procure_delivered', nil, buyerId, { orderId = tonumber(orderId), procurement = row and row.id, items = moved })
    TriggerEvent('pf-government:server:facilityStockDelivered', { buyerId = buyerId, dept = b.dept, stash = b.stash.id, orderId = tonumber(orderId), items = moved })
    return true
end

--- The department's books: one society_spend line per delivered purchase (moves no money; the
--- charge already went through pf-stores). Keyed, so a second call records nothing.
function P.Book(row)
    local amount = tonumber(row.total) or 0
    if amount <= 0 or not BudgetRecordSocietyPayout then return false end
    local ok, done = pcall(BudgetRecordSocietyPayout, row.dept, amount, cfg().BudgetCategory,
        ('Facility supplies #%d'):format(row.id), ('pf-government:dept:%s:procurement:%d'):format(row.dept, row.id))
    return ok and done == true
end

-- ── registering with pf-stores ──────────────────────────────────────────

P.registered = P.registered or false
function P.Register()
    if not cfg().Enabled or not U.started('pf-stores') then return false end
    local ok = pcall(function() exports['pf-stores']:RegisterBuyerKind(cfg().Kind, P.Adapter) end)
    P.registered = ok
    if ok then
        for _, b in pairs(cfg().Buyers) do P.EnsureStash(b.stash) end
    end
    return ok
end

-- ── purchases ───────────────────────────────────────────────────────────

local COLS = 'id, dept, buyer_id, store_order_id, method, items, total, state, by_cid, note, at, updated_at, idem_key'

local function rowById(id) return MySQL.single.await('SELECT ' .. COLS .. ' FROM pf_gov_dept_procurements WHERE id = ? LIMIT 1', { id }) end

local function cartKey(cart)
    local out = {}
    for _, c in ipairs(cart) do out[#out + 1] = tostring(c.name):lower() .. '=' .. tostring(math.tointeger(tonumber(c.quantity)) or c.quantity) end
    table.sort(out)
    return table.concat(out, ',')
end

local function public(r)
    if not r then return nil end
    local items = r.items and json.decode(r.items) or nil
    return {
        id = tonumber(r.id), dept = r.dept, buyerId = r.buyer_id, orderId = tonumber(r.store_order_id), method = r.method,
        items = type(items) == 'table' and items.lines or nil, total = tonumber(r.total) or 0, state = r.state,
        by = r.by_cid, note = r.note, at = tonumber(r.at), updatedAt = tonumber(r.updated_at),
    }
end
P.Public = public

local function setRow(id, state, set)
    local sql, params = 'UPDATE pf_gov_dept_procurements SET state = ?, updated_at = ?', { state, now() }
    for col, v in pairs(set or {}) do
        sql = sql .. (', `%s` = ?'):format(col)
        params[#params + 1] = v
    end
    params[#params + 1] = id
    MySQL.update.await(sql .. ' WHERE id = ?', params)
end

-- The pf-stores order a crash or a failed payment left without a link: the newest facility order of
-- this buyer and person since `sinceMs` that no purchase row claims yet (read-only).
function P.FindStoreOrder(buyerId, cid, sinceMs)
    return MySQL.single.await([[SELECT o.id, o.status, o.total FROM pf_store_supply_orders o
        WHERE o.buyer_kind = ? AND o.store_id = ? AND o.owner_citizenid = ? AND o.created_at >= ?
        AND NOT EXISTS (SELECT 1 FROM pf_gov_dept_procurements p WHERE p.store_order_id = o.id)
        ORDER BY o.id DESC LIMIT 1]], { cfg().Kind, buyerId, cid, sinceMs })
end

--- The ledger's view of an order's charge: 'charged' | 'refused' | 'unclear' | 'none'.
function P.ChargeState(orderId)
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(('supply:%d:charge'):format(orderId)) end)
    if not ok then return 'unclear' end
    if type(tx) ~= 'table' then return 'none' end
    if tx.state == 'completed' then return 'charged' end
    if tx.state == 'compensated' then return 'refused' end
    if tx.state == 'failed' and tx.error ~= 'interrupted_unverified' then return 'refused' end
    return 'unclear'
end

--- What a purchase row is, read from its pf-stores order and the ledger's record of the charge:
--- 'paid' (the order exists and is under way), 'payment_pending' (pf-stores is still being paid, or
--- the charge is unclear), 'charge_held' (pf-stores failed the order but the charge completed:
--- the money sits in the supply escrow for staff) or 'failed' (no order, or no money moved).
function P.StateFromOrder(order)
    if type(order) ~= 'table' or not tonumber(order.id) then return 'failed' end
    if order.status == 'created' then return 'payment_pending' end
    if order.status ~= 'failed' then return 'paid' end
    local charge = P.ChargeState(tonumber(order.id))
    if charge == 'unclear' then return 'payment_pending' end
    if charge == 'charged' then return 'charge_held' end
    return 'failed'
end

local function held(r, orderId)
    D.Audit(r.dept, 'procure_held', nil, r.buyer_id, { procurement = tonumber(r.id), orderId = orderId, charge = 'charged' })
    print(('^3[PF-GOVERNMENT]^7 purchase %d (%s): supply order %d was charged after it failed; refund it from society:freight_escrow'):format(
        tonumber(r.id), tostring(r.buyer_id), orderId))
end

local function orderById(id)
    return MySQL.single.await('SELECT id, status, total FROM pf_store_supply_orders WHERE id = ? LIMIT 1', { id })
end

local function createLocked(src, m, buyerId, cart, key)
    local b = cfg().Buyers[buyerId]
    if key then
        local prev = MySQL.single.await('SELECT ' .. COLS .. ' FROM pf_gov_dept_procurements WHERE idem_key = ? LIMIT 1', { key })
        if prev then
            local items = prev.items and json.decode(prev.items) or {}
            if prev.buyer_id ~= buyerId or items.cart ~= cartKey(cart) then return fail('key_reused', 'That key belongs to another purchase.') end
            local out = { ok = true, duplicate = true, procurement = public(prev) }
            return out
        end
    end
    -- one unclear charge per facility at a time: nothing is ordered again until the ledger answers
    local pending = MySQL.scalar.await("SELECT COUNT(*) FROM pf_gov_dept_procurements WHERE buyer_id = ? AND state = 'payment_pending'", { buyerId })
    if (tonumber(pending) or 0) > 0 then
        return fail('payment_pending', 'An earlier order for this facility is still being processed by the bank.')
    end
    local t = now()
    local startMs = t * 1000
    local id = MySQL.insert.await([[INSERT INTO pf_gov_dept_procurements (dept, buyer_id, store_order_id, method, items, total, state, by_cid, note, at, updated_at, idem_key)
        VALUES (?, ?, NULL, 'trucking', ?, 0, 'created', ?, NULL, ?, ?, ?)]], { b.dept, buyerId, json.encode({ cart = cartKey(cart) }), m.cid, t, t, key })
    id = tonumber(id)
    if not id then return fail('db_unavailable', 'The purchase could not be recorded. Nothing was ordered.') end

    P.placing[src], P.ordering[buyerId] = buyerId, true
    local okCall, res = pcall(function()
        return exports['pf-stores']:CreateOrder(src, { kind = cfg().Kind, buyerId = buyerId, method = 'trucking', cart = cart })
    end)
    P.placing[src], P.ordering[buyerId] = nil, nil
    if not okCall or type(res) ~= 'table' then
        -- pf-stores errored mid-way: what happened is read back from its order and the ledger
        res = { ok = false, error = 'stores_unavailable' }
    end

    if res.ok then
        local data = res.data or {}
        local orderId = tonumber(data.orderId)
        if res.duplicate and orderId then
            local first = MySQL.single.await('SELECT ' .. COLS .. ' FROM pf_gov_dept_procurements WHERE store_order_id = ? LIMIT 1', { orderId })
            if first then
                MySQL.update.await('DELETE FROM pf_gov_dept_procurements WHERE id = ? AND store_order_id IS NULL', { id })
                return { ok = true, duplicate = true, procurement = public(first) }
            end
        end
        setRow(id, 'paid', { store_order_id = orderId, total = round(data.total),
            items = json.encode({ cart = cartKey(cart), lines = data.items }) })
        D.Audit(b.dept, 'procure_order', m.cid, buyerId, { procurement = id, orderId = orderId, total = data.total })
        return { ok = true, procurement = public(rowById(id)), contractId = data.contractId }
    end

    -- not placed as far as the answer says: the order pf-stores made (if any) and the ledger decide
    -- between failed, held and placed after all (an answer lost on the way back)
    local order = P.FindStoreOrder(buyerId, m.cid, startMs)
    local state = P.StateFromOrder(order)
    if state ~= 'failed' then
        setRow(id, state, { store_order_id = tonumber(order.id), total = round(order.total), note = ('order: %s'):format(tostring(res.error)):sub(1, 255) })
        if state == 'paid' then
            D.Audit(b.dept, 'procure_order', m.cid, buyerId, { procurement = id, orderId = tonumber(order.id), total = order.total })
            return { ok = true, procurement = public(rowById(id)) }
        end
        D.Audit(b.dept, 'procure_held', m.cid, buyerId, { procurement = id, orderId = tonumber(order.id), state = state })
        return fail('payment_pending', 'The bank has not confirmed the payment yet. Nothing more will be charged; check back shortly.')
    end
    setRow(id, 'failed', { store_order_id = order and tonumber(order.id) or nil, note = tostring(res.error):sub(1, 255) })
    local out = fail(res.error == 'insufficient_funds' and 'insufficient_funds' or (res.error or 'failed'),
        res.message or (res.error == 'insufficient_funds' and 'The department account cannot cover this order.' or 'The order was not placed.'))
    out.data = res.data
    return out
end

--- A manager orders supplies for a facility of their department.
--- cart = { { name, quantity (cases) }, ... }; opts = { key } (optional idempotency key).
--- Returns { ok, procurement, contractId } or { ok = false, error }.
function P.Create(src, buyerId, cart, opts)
    src = U.int(src, 1, 65535)
    if not src or type(buyerId) ~= 'string' or not cfg().Buyers[buyerId] then return fail('bad_args', 'Unknown facility.') end
    if type(cart) ~= 'table' or #cart < 1 or #cart > cfg().MaxLines then return fail('bad_args', 'The order has no lines.') end
    local clean = {}
    for i, c in ipairs(cart) do
        if type(c) ~= 'table' or type(c.name) ~= 'string' or #c.name > 48 then return fail('bad_args', 'Invalid order line.') end
        local qty = U.int(c.quantity, 1, cfg().MaxCases)
        if not qty then return fail('bad_args', 'Invalid quantity.') end
        clean[i] = { name = c.name:lower(), quantity = qty }
    end
    local key = opts and opts.key
    if key ~= nil and not U.validKey(key) then return fail('bad_args', 'Invalid key.') end
    if not cfg().Enabled then return fail('invalid_state', 'Procurement is switched off.') end
    local may, m = P.CanOrder(src, buyerId)
    if not may then return fail('no_permission', 'Only an on-duty manager of this department can order its supplies.') end
    if not U.dbReady() then return fail('db_unavailable', 'Department records are unavailable right now.') end
    if not P.registered and not P.Register() then return fail('unavailable', 'The supply service is not running.') end
    -- the lock is taken before the first database wait: one purchase per facility at a time
    return U.withLocks({ 'procure:' .. buyerId }, function() return createLocked(src, m, buyerId, clean, key) end)
end

--- A manager cancels a purchase whose goods have not been picked up by a driver (pf-stores refunds
--- the department account from escrow under its own keys).
function P.Cancel(src, procId)
    src = U.int(src, 1, 65535)
    procId = U.int(procId, 1, 2147483647)
    if not src or not procId then return fail('bad_args', 'Invalid purchase.') end
    if not U.dbReady() then return fail('db_unavailable', 'Department records are unavailable right now.') end
    local row = rowById(procId)
    if not row then return fail('not_found', 'No such purchase.') end
    local may, m = P.CanOrder(src, row.buyer_id)
    if not may then return fail('no_permission', 'Only an on-duty manager of this department can cancel its orders.') end
    if row.state ~= 'paid' or not tonumber(row.store_order_id) then return fail('invalid_state', 'This purchase cannot be cancelled.') end
    return U.withLocks({ 'procure:' .. row.buyer_id }, function()
        P.placing[src] = row.buyer_id
        local okCall, res = pcall(function()
            return exports['pf-stores']:CancelOrder(src, cfg().Kind, row.buyer_id, tonumber(row.store_order_id))
        end)
        P.placing[src] = nil
        if not okCall or type(res) ~= 'table' then return fail('unavailable', 'The supply service is not answering.') end
        if not res.ok then return res end
        setRow(row.id, 'cancelled', { note = 'cancelled by ' .. tostring(m.cid) })
        D.Audit(row.dept, 'procure_cancel', m.cid, row.buyer_id, { procurement = row.id, orderId = tonumber(row.store_order_id) })
        return { ok = true, procurement = public(rowById(row.id)) }
    end)
end

--- The facilities, catalogs and recent purchases of the caller's department (staff).
function P.List(src, limit)
    local m = D.Member(U.int(src, 1, 65535))
    if not m or not m.dept or not m.onDuty then return fail('no_permission', 'On-duty department staff only.') end
    if not U.dbReady() then return fail('db_unavailable', 'Department records are unavailable right now.') end
    limit = U.int(limit or 25, 1, 100) or 25
    local rows = MySQL.query.await('SELECT ' .. COLS .. ' FROM pf_gov_dept_procurements WHERE dept = ? ORDER BY id DESC LIMIT ' .. limit, { m.dept }) or {}
    local out = {}
    for i, r in ipairs(rows) do out[i] = public(r) end
    return { ok = true, list = out }
end

function P.Catalog(src)
    local m = D.Member(U.int(src, 1, 65535))
    if not m or not m.dept then return fail('no_permission', 'Department staff only.') end
    local out = {}
    for id, b in pairs(cfg().Buyers) do
        if b.dept == m.dept then
            local items = {}
            for name, e in pairs(cfg().Catalogs[b.catalog] or {}) do
                if knownItem(name) then items[#items + 1] = { name = name, price = e.price, caseSize = e.caseSize or 1 } end
            end
            table.sort(items, function(a, c) return a.name < c.name end)
            out[#out + 1] = { buyerId = id, label = b.label, items = items }
        end
    end
    table.sort(out, function(a, c) return a.buyerId < c.buyerId end)
    local mayOrder = m.onDuty and (m.manager or m.isBoss) or false
    return { ok = true, dept = m.dept, mayOrder = mayOrder, facilities = out }
end

-- ── settling held and stale purchases (every ReconcileSeconds) ──────────

function P.ReconcileTick(t)
    t = t or now()
    if not U.dbReady() then return 0 end
    local done = 0
    -- unclear charges: pf-stores' order and the ledger's own record decide
    for _, r in ipairs(MySQL.query.await("SELECT " .. COLS .. " FROM pf_gov_dept_procurements WHERE state = 'payment_pending' ORDER BY id LIMIT 50") or {}) do
        local orderId = tonumber(r.store_order_id)
        local state = P.StateFromOrder(orderId and orderById(orderId))
        if state ~= 'payment_pending' then
            setRow(r.id, state, { note = state == 'charge_held' and 'charged after the order failed: refund from the supply escrow'
                or (state == 'failed' and 'payment refused by the bank') or 'payment confirmed' })
            if state == 'charge_held' then held(r, orderId) end
            done = done + 1
        end
    end
    -- rows a crash left 'created': linked to their order when pf-stores has one
    local stale = t - (tonumber(cfg().PlacingStaleSeconds) or 120)
    for _, r in ipairs(MySQL.query.await("SELECT " .. COLS .. " FROM pf_gov_dept_procurements WHERE state = 'created' AND at <= ? ORDER BY id LIMIT 50", { stale }) or {}) do
        local order = P.FindStoreOrder(r.buyer_id, r.by_cid, (tonumber(r.at) or 0) * 1000)
        local state = P.StateFromOrder(order)
        setRow(r.id, state, order and { store_order_id = tonumber(order.id), total = round(order.total) } or { note = 'never placed' })
        if state == 'charge_held' then held(r, tonumber(order.id)) end
        done = done + 1
    end
    -- paid purchases whose order ended elsewhere (cancelled or unpacked while this resource was down)
    for _, r in ipairs(MySQL.query.await([[SELECT p.id, p.dept, p.total, p.buyer_id, o.status FROM pf_gov_dept_procurements p
        JOIN pf_store_supply_orders o ON o.id = p.store_order_id
        WHERE p.state = 'paid' AND o.status IN ('unpacked', 'cancelled', 'failed') ORDER BY p.id LIMIT 50]]) or {}) do
        if r.status == 'unpacked' then
            setRow(r.id, 'delivered')
            P.Book(r)
        else
            setRow(r.id, r.status)
        end
        done = done + 1
    end
    return done
end

-- ── facility stashes (staff open the one they stand at) ─────────────────

function P.OpenStash(src)
    src = U.int(src, 1, 65535)
    local pos = src and posOf(src)
    if not pos then return fail('offline', 'You are not loaded.') end
    local best, bestD
    for id, b in pairs(cfg().Buyers) do
        if b.point and b.stash then
            local d = dist(pos, vec(b.point))
            if d <= cfg().StashReach and (not best or d < bestD) then best, bestD = id, d end
        end
    end
    if not best then return fail('too_far', 'There is no supply room here.') end
    if not P.IsStaff(src, best) then return fail('no_permission', 'Only on-duty staff of this facility can open its stock.') end
    local b = cfg().Buyers[best]
    if not P.EnsureStash(b.stash) then return fail('unavailable', 'The stock is unavailable right now.') end
    inv('OpenInventory', src, b.stash.id, { label = b.stash.label, maxweight = b.stash.maxweight, slots = b.stash.slots })
    return { ok = true, buyerId = best, stash = b.stash.id }
end

-- ── fleet maintenance: pf-services kind mechanic.fleet ──────────────────

local F = {}
P.Fleet = F

local function normPlate(plate)
    if type(plate) ~= 'string' then return '' end
    plate = plate:upper():gsub('^%s+', ''):gsub('%s+$', '')
    if #plate > 8 then return '' end
    return plate
end
F.NormPlate = normPlate

local function fleetCfg() return cfg().Fleet end

--- The vehicle entity with this plate on the server, or nil (a stored vehicle has none).
function F.FindVehicle(plate)
    plate = normPlate(plate)
    if plate == '' then return nil end
    for _, veh in ipairs(GetAllVehicles() or {}) do
        if DoesEntityExist(veh) and normPlate(GetVehicleNumberPlateText(veh)) == plate then return veh end
    end
    return nil
end

--- Server-read health of a vehicle: body, engine (whole numbers).
function F.Health(veh)
    return math.floor(tonumber(GetVehicleBodyHealth(veh)) or 0), math.floor(tonumber(GetVehicleEngineHealth(veh)) or 0)
end

local function garages(name, ...)
    local args, n = { ... }, select('#', ...)
    local ok, res = pcall(function()
        local e = exports['pf-jobgarages']
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'unavailable', message = 'The fleet service is not answering.' } end
    return res
end
F.Garages = garages

local function services(name, ...)
    local args, n = { ... }, select('#', ...)
    local ok, res = pcall(function()
        local e = exports['pf-services']
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok then return nil end
    return res
end

local function mechanicJobs()
    local jobs = fleetCfg().Jobs
    if type(jobs) == 'table' then return jobs end
    local def = services('GetRequestKind', 'mechanic.roadside')
    if type(def) == 'table' and def.job then return type(def.job) == 'table' and def.job or { def.job } end
    return { 'mechanic', 'bennys', 'beeker' }
end

F.registered = F.registered or false
function F.Register()
    local fc = fleetCfg()
    if not fc.Enabled or not U.started('pf-services') then return false end
    local okKind = services('RegisterRequestKind', fc.Kind, {
        label = 'Fleet maintenance', icon = '🛠️', job = mechanicJobs(), payer = 'none', reward = 0,
        verify = true, expires = fc.Expires, citizen = false,
        description = 'Service a department vehicle; done when the server reads it repaired',
    })
    local okHandler = services('RegisterRequestHandler', fc.Kind, {
        onAccepted = function(req, src) return F.OnAccepted(req, src) end,
        canComplete = function(req, src) return F.CanComplete(req, src) end,
        onCompleted = function(req) return F.OnCompleted(req) end,
        onClosed = function(req, reason) return F.OnClosed(req, reason) end,
    })
    F.registered = okKind == true and okHandler == true
    return F.registered
end

--- Asks a mechanic to service a fleet vehicle. opts = { actor = { src } } for a department member
--- (on duty, in the vehicle's department, next to it), or no actor from a resource listed in
--- Fleet.Requesters (for its own fleet jobs). The need is read on the server: the vehicle's health
--- or a 'due' service state. Returns { ok, requestId, existing } or { ok = false, error }.
function F.Request(plate, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    local fc = fleetCfg()
    plate = normPlate(plate)
    if plate == '' then return fail('bad_args', 'A plate is required.') end
    if not fc.Enabled then return fail('invalid_state', 'Fleet maintenance is switched off.') end
    local v = garages('GetFleetVehicle', plate)
    if not v.ok then return fail(v.error or 'not_found', v.message or 'This is not a department vehicle.') end
    local deptId = D.DeptOfJob(v.job)
    if not deptId then return fail('not_found', 'This vehicle belongs to no department.') end
    local actorCid
    if type(opts.actor) == 'table' and opts.actor.src ~= nil then
        local m = D.Member(opts.actor.src)
        if not m then return fail('offline', 'The acting player is not online.') end
        if m.dept ~= deptId or not m.onDuty then return fail('no_permission', 'Only on-duty staff of this department can report its vehicles.') end
        actorCid = m.cid
    elseif invoker ~= nil then
        local allowed = (fc.Requesters or {})[invoker]
        if type(allowed) ~= 'table' or allowed[v.job] ~= true then return fail('not_allowed', 'This resource may not report that fleet.') end
    end
    local veh = F.FindVehicle(plate)
    if not veh then return fail('not_found', 'The vehicle must be out of the garage for a mechanic to work on it.') end
    local vpos = GetEntityCoords(veh)
    if actorCid and dist(posOf(opts.actor.src), vpos) > fc.ReportRange then return fail('too_far', 'Stand next to the vehicle.') end
    local body, engine = F.Health(veh)
    local open = services('FindOpenByRef', 'fleet', plate, fc.Kind)
    if type(open) == 'table' and open.id then return { ok = true, requestId = open.id, existing = true } end
    local worn = body < fc.DueBody or engine < fc.DueEngine
    if not worn and v.serviceState ~= 'due' then return fail('invalid_state', 'This vehicle does not need service.') end
    if not F.registered and not F.Register() then return fail('unavailable', 'The service dispatch is not running.') end
    if v.serviceState == 'ok' or v.serviceState == 'due' then
        local s = garages('SetServiceState', plate, 'due', { body = math.max(0, math.min(1000, body)), engine = math.max(-4000, math.min(1000, engine)),
            reason = 'service requested', actor = actorCid and { src = opts.actor.src } or { kind = 'system', label = invoker or 'pf-government' } })
        if not s.ok then return fail(s.error or 'unavailable', s.message or 'The fleet could not be updated.') end
    end
    local res = services('CreateRequest', {
        kind = fc.Kind, title = ('Fleet service: %s %s'):format(tostring(v.label or v.model or 'vehicle'), plate),
        details = ('Body %d, engine %d (server reading). Bill parts and labour to the department at the register.'):format(body, engine),
        coords = { x = vpos.x, y = vpos.y, z = vpos.z }, plate = plate, ref = { type = 'fleet', id = plate },
        from = { type = 'job', id = v.job, name = ((Config.Departments or {}).Labels or {})[deptId] or deptId },
        requester = actorCid, payer = 'society:' .. P.Society(deptId), reward = tonumber(fc.Reward) or 0,
        meta = { dept = deptId, body = body, engine = engine, garageId = v.garageId },
    })
    if type(res) ~= 'table' or not res.ok then return fail('unavailable', 'The service dispatch did not take the request.') end
    D.Audit(deptId, 'fleet_request', actorCid, plate, { requestId = res.id, body = body, engine = engine, by = invoker })
    return { ok = true, requestId = res.id, existing = res.existing == true }
end

function F.OnAccepted(req, src)
    if type(req) ~= 'table' or not req.plate then return end
    garages('SetServiceState', req.plate, 'in_service', { reason = ('mechanic took request #%s'):format(tostring(req.id)), actor = { src = src } })
end

--- The proof: the vehicle is on the server next to the mechanic, the server reads it repaired, and
--- pf-jobgarages records the service (state ok with the readings). Anything the client sends is ignored.
function F.CanComplete(req, src)
    local fc = fleetCfg()
    if type(req) ~= 'table' or not req.plate then return false, 'not_found' end
    local veh = F.FindVehicle(req.plate)
    if not veh then return false, 'vehicle_not_found' end
    if dist(posOf(src), GetEntityCoords(veh)) > fc.ServiceRange then return false, 'too_far' end
    local body, engine = F.Health(veh)
    if body < fc.ServicedBody or engine < fc.ServicedEngine then return false, 'not_repaired' end
    local s = garages('SetServiceState', req.plate, 'ok', { body = math.min(1000, body), engine = math.min(1000, engine),
        reason = ('serviced (request #%s)'):format(tostring(req.id)), actor = { src = src } })
    if not s.ok then return false, s.error or 'fleet_unavailable' end
    return true
end

function F.OnCompleted(req)
    if type(req) ~= 'table' then return end
    local meta = type(req.meta) == 'table' and req.meta or {}
    if D.IsDept(meta.dept) then D.Audit(meta.dept, 'fleet_serviced', req.assignee, req.plate, { requestId = req.id }) end
end

--- A request closed without the work (cancelled, expired, released for good): the vehicle still
--- needs service, so a vehicle left in_service goes back to due (it can be taken out again).
function F.OnClosed(req, reason)
    if type(req) ~= 'table' or not req.plate then return end
    local v = garages('GetFleetVehicle', req.plate)
    if v.ok and v.serviceState == 'in_service' then
        garages('SetServiceState', req.plate, 'due', { reason = ('service request closed: %s'):format(tostring(reason)):sub(1, 128),
            actor = { kind = 'system', label = 'pf-government fleet' } })
    end
end

--- /fleetservice: the vehicle the player sits in, else the nearest one within ReportRange.
function F.Report(src)
    src = U.int(src, 1, 65535)
    local ped = src and GetPlayerPed(src)
    if not ped or ped == 0 then return fail('offline', 'You are not loaded.') end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        local pos, best, bestD = GetEntityCoords(ped), nil, nil
        for _, v in ipairs(GetAllVehicles() or {}) do
            local d = dist(pos, GetEntityCoords(v))
            if d <= fleetCfg().ReportRange and (not best or d < bestD) then best, bestD = v, d end
        end
        veh = best
    end
    if not veh then return fail('not_found', 'Stand next to the vehicle.') end
    return F.Request(GetVehicleNumberPlateText(veh), { actor = { src = src } })
end

-- ── exports (architecture 3.4: writes and private reads are allowlisted) ─

local warned = {}
local function callerOk(name)
    local inv0 = GetInvokingResource()
    if inv0 == nil or inv0 == GetCurrentResourceName() then return true, nil end
    local list = ((Config.Departments or {}).Callers or {})[name]
    if list == nil then list = cfg().Callers end
    if list == '*' or (type(list) == 'table' and list[inv0] == true) then return true, inv0 end
    if not warned[name .. inv0] or now() - warned[name .. inv0] >= 60 then
        warned[name .. inv0] = now()
        print(('^3[PF-GOVERNMENT]^7 %s refused for %s'):format(name, inv0))
    end
    return false, inv0
end

exports('CreateProcurement', function(src, buyerId, cart, opts)
    if not callerOk('CreateProcurement') then return U.notAllowed() end
    return P.Create(src, buyerId, cart, opts)
end)
exports('CancelProcurement', function(src, procId)
    if not callerOk('CancelProcurement') then return U.notAllowed() end
    return P.Cancel(src, procId)
end)
exports('ListProcurements', function(src, limit)
    if not callerOk('ListProcurements') then return U.notAllowed() end
    return P.List(src, limit)
end)
exports('GetProcurementCatalog', function(src) return P.Catalog(src) end)
exports('RequestFleetService', function(plate, opts)
    local ok, invoker = callerOk('RequestFleetService')
    if not ok then return U.notAllowed() end
    if invoker ~= nil and type(opts) == 'table' and type(opts.actor) == 'table' and opts.actor.kind == 'system' then opts.actor = nil end
    return F.Request(plate, opts, invoker)
end)

-- ── commands and start ──────────────────────────────────────────────────

local function tell(src, res, okText)
    TriggerClientEvent('QBCore:Notify', src, res.ok and okText or (res.message or res.error or 'Failed'), res.ok and 'success' or 'error')
end

P.rate = P.rate or {}
local function limited(src, what)
    local k, t = tostring(src) .. what, now()
    if P.rate[k] and t - P.rate[k] < 2 then return true end
    P.rate[k] = t
    return false
end

function P.Commands()
    if not (QBCore and QBCore.Commands and QBCore.Commands.Add) then return false end
    QBCore.Commands.Add('procure', 'Order facility supplies (department managers)', {
        { name = 'facility', help = 'e.g. ems:pillbox' }, { name = 'item', help = 'Item' }, { name = 'cases', help = 'Cases' },
    }, true, function(src, args)
        if limited(src, 'procure') then return end
        local res = P.Create(src, args[1], { { name = args[2], quantity = tonumber(args[3]) } })
        local p = res.procurement
        tell(src, res, p and ('Order #%s placed: $%d, delivery by trucker'):format(tostring(p.orderId), p.total or 0) or 'Order placed')
    end)
    QBCore.Commands.Add('supplyroom', 'Open the facility stock you stand at (on-duty staff)', {}, false, function(src)
        if limited(src, 'stash') then return end
        local res = P.OpenStash(src)
        if not res.ok then tell(src, res) end
    end)
    QBCore.Commands.Add('fleetservice', 'Ask a mechanic to service this department vehicle', {}, false, function(src)
        if limited(src, 'fleet') then return end
        local res = F.Report(src)
        tell(src, res, res.existing and 'A mechanic request for this vehicle is already open' or 'Mechanic requested for this vehicle')
    end)
    return true
end

CreateThread(function()
    Wait(2000)
    P.Commands()
    for _ = 1, 60 do
        if P.registered or P.Register() then break end
        Wait(1000)
    end
    for _ = 1, 60 do
        if F.registered or F.Register() then break end
        Wait(1000)
    end
    while true do
        Wait((tonumber(cfg().ReconcileSeconds) or 60) * 1000)
        local ok, err = pcall(P.ReconcileTick)
        if not ok then print('^1[PF-GOVERNMENT]^7 procurement reconcile failed: ' .. tostring(err)) end
    end
end)

-- a restarted pf-stores / pf-services has forgotten the buyer kind and the request kind
AddEventHandler('onResourceStart', function(name)
    if name == 'pf-stores' then P.registered = false SetTimeout(1000, P.Register) end
    if name == 'pf-services' then F.registered = false SetTimeout(1000, F.Register) end
end)
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then P.placing[src] = nil end
end)
