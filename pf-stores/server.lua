local QBCore = exports['pfm-core']:GetCoreObject()

local checkoutLocks = {}

local function dbg(...)
    if not (Config and Config.Debug) then return end
    print('[pf-stores]', ...)
end

local function nowMs()
    return os.time() * 1000
end

local function roundCurrency(value)
    value = tonumber(value) or 0
    return math.floor((value * 100) + 0.5) / 100
end

local function getSalesTaxBreakdown(subtotal)
    local safeSubtotal = roundCurrency(math.max(0, tonumber(subtotal) or 0))
    local fallback = {
        subtotal = safeSubtotal,
        tax = 0,
        total = safeSubtotal,
        rate = 0
    }

    if GetResourceState('pf-government') ~= 'started' then
        return fallback
    end

    local ok, result = pcall(function()
        return exports['pf-government']:GetSalesTaxBreakdown(safeSubtotal)
    end)

    if ok and type(result) == 'table' and result.total ~= nil and result.tax ~= nil then
        return {
            subtotal = safeSubtotal,
            tax = roundCurrency(result.tax),
            total = roundCurrency(result.total),
            rate = tonumber(result.rate) or 0
        }
    end

    local okRate, decimalRate = pcall(function()
        return exports['pf-government']:GetSalesTaxRate()
    end)

    if not okRate then
        return fallback
    end

    local normalizedRate = tonumber(decimalRate) or 0
    local tax = roundCurrency(safeSubtotal * normalizedRate)
    local total = roundCurrency(safeSubtotal + tax)

    return {
        subtotal = safeSubtotal,
        tax = tax,
        total = total,
        rate = normalizedRate * 100
    }
end

-- Money ------------------------------------------------------------------------
-- Every store money move goes through the pfm-banking ledger (exports Transfer / LedgerAutoKey).
-- Shoppers pay into system:pf-stores; a player-owned store's revenue is then moved to its bank
-- society account store_<storeId> (type 'business'). pf_stores.balance is no longer used: existing
-- balances are moved to the bank once at start (migrateBalancesToBank).
local SALES_ACCOUNT = 'system:pf-stores'

local function bankReady()
    if GetResourceState('pfm-banking') ~= 'started' then return false end
    local ok, ready = pcall(function() return exports['pfm-banking']:IsLedgerReady() end)
    return ok and ready == true
end

local function ledgerTransfer(opts)
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

local function newKey(prefix)
    local ok, key = pcall(function() return exports['pfm-banking']:LedgerAutoKey(prefix) end)
    if ok and type(key) == 'string' then return key end
    return ('%s:%d:%d'):format(prefix, os.time(), math.random(1, 1000000000))
end

local function storeAccountName(storeId)
    return 'store_' .. (tostring(storeId):gsub('[^%w_%-%.]', '_')):sub(1, 44)
end

local function storeAccountRef(storeId)
    return 'society:' .. storeAccountName(storeId)
end

local function ensureStoreAccount(storeId)
    local ok, exists = pcall(function()
        return exports['pfm-banking']:EnsureSocietyAccount(storeAccountName(storeId), 'business')
    end)
    return ok and exists == true
end

local function getStoreBalance(storeId)
    local ok, balance = pcall(function() return exports['pfm-banking']:GetAccountBalance(storeAccountName(storeId)) end)
    if not ok then return 0 end
    return roundCurrency(tonumber(balance) or 0)
end

-- Pays a charge back (from the sales account unless `fromRef` says otherwise); the key ties the refund
-- to the charge, so it happens once.
local function refundCharge(charge, toRef, amount, suffix, reason, fromRef)
    if not (charge and charge.txId) or amount <= 0 then return true end
    local res = ledgerTransfer({
        from = fromRef or SALES_ACCOUNT, to = toRef, amount = amount,
        key = ('refund:%s:%s'):format(charge.txId, suffix or 'full'), kind = 'refund', reason = reason,
    })
    if not res.ok then
        print(('^1[pf-stores]^7 refund of %.2f for %s failed (%s)'):format(amount, charge.txId, tostring(res.error)))
    end
    return res.ok
end

-- Supply orders: the store's account pays. Pickup orders go straight to the supplier; trucking orders
-- are held in the freight escrow account until delivered, then the trucker's pay (paid by pf-trucking
-- from escrow) and the supplier's share are released.
local SUPPLIER_ACCOUNT = 'system:pf-stores-supplier'
local ESCROW_NAME = 'freight_escrow'
local ESCROW_ACCOUNT = 'society:' .. ESCROW_NAME

local function ensureEscrowAccount()
    local ok, exists = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(ESCROW_NAME, 'business') end)
    return ok and exists == true
end

-- Hands the treasury exactly the tax that was charged. Returns the amount it accepted (0 on failure).
local function collectSalesTax(taxAmount, subtotal, targetType, targetId, collectedBy, key)
    if taxAmount <= 0 or GetResourceState('pf-government') ~= 'started' then
        return 0
    end
    local ok, value = pcall(function()
        return exports['pf-government']:CollectTaxAmount(taxAmount, 'sales', targetType, targetId, collectedBy, key, subtotal)
    end)
    if not ok then
        return 0
    end
    return roundCurrency(tonumber(value) or 0)
end

local function getCitizenId(src)
    local Player = QBCore.Functions.GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end

local function getStoreDef(storeId)
    if not (Config and Config.Stores) then return nil end
    return Config.Stores[storeId]
end

-- True when the player stands within `range` of the configured point (no point configured: true).
-- Buying from the storefront or buying the store itself used to work from anywhere on the map.
local function nearPoint(src, point, range)
    if not point then return true end
    local pos = GetEntityCoords(GetPlayerPed(src))
    return #(vector3(pos.x, pos.y, pos.z) - vector3(point.x, point.y, point.z)) <= range
end

local function getStoreRow(storeId)
    local rows = MySQL.query.await('SELECT store_id, label, store_type, owner_citizenid, purchased_at FROM pf_stores WHERE store_id = ? LIMIT 1', { storeId })
    local row = rows and rows[1] or nil
    if row then
        -- the store's money lives in its bank account (see "Money" above)
        row.balance = getStoreBalance(storeId)
    end
    return row
end

local function getStoreOwner(storeId)
    local row = getStoreRow(storeId)
    local owner = row and row.owner_citizenid or nil
    if owner == nil or tostring(owner) == '' then return nil end
    return tostring(owner)
end

-- ── pf-government business registry ──────────────────────────────────────────
-- A player-owned store is registered as store:<id> under its owner, so government licenses,
-- closures, utilities and business tax apply to it. NPC (ownerless) stores are not registered.
local function govStarted() return GetResourceState('pf-government') == 'started' end
local function govId(storeId) return 'store:' .. tostring(storeId) end

local function registerStoreWithGovernment(storeId, ownerCid, label)
    if not govStarted() or not ownerCid or ownerCid == '' then return end
    pcall(function()
        exports['pf-government']:RegisterBusinessWithGovernment(govId(storeId), label or tostring(storeId), 'store', ownerCid, nil)
    end)
end

--- false + reason when the government closed this store or cut its power
local function storeMayTrade(storeId)
    if not govStarted() then return true end
    local ok, allowed, why = pcall(function() return exports['pf-government']:CanBusinessTrade(govId(storeId)) end)
    if ok and allowed == false then return false, why end
    return true
end

local function reportStoreRevenue(storeId, amount, key)
    if not govStarted() or not amount or amount <= 0 then return end
    pcall(function() exports['pf-government']:AddBusinessRevenue(govId(storeId), amount, key, storeAccountRef(storeId)) end)
end

local function resolveOwnedStoreId(src, storeId)
    storeId = storeId ~= nil and tostring(storeId) or ''
    if storeId ~= '' then
        return storeId
    end

    local citizenid = getCitizenId(src)
    if not citizenid then return nil end

    local rows = MySQL.query.await(
        'SELECT store_id FROM pf_stores WHERE owner_citizenid = ? ORDER BY purchased_at DESC LIMIT 1',
        { citizenid }
    )
    local found = rows and rows[1] and rows[1].store_id or nil
    return found ~= nil and tostring(found) or nil
end

local storefrontLocks = {}

local function hasValidImage(sharedItem, configuredImage)
    local img = configuredImage
    if (img == nil or tostring(img) == '') and sharedItem and sharedItem.image ~= nil then
        img = sharedItem.image
    end
    if img == nil then return false end
    img = tostring(img)
    if img == '' then return false end
    if img == 'placeholder.png' then return false end
    return true
end

local function isConsumable(sharedItem)
    if type(sharedItem) ~= 'table' then return false end
    if sharedItem.useable == true then return true end
    local name = tostring(sharedItem.name or ''):lower()
    if name:find('water') or name:find('cola') or name:find('coffee') or name:find('juice') or name:find('beer') or name:find('whiskey') or name:find('vodka') or name:find('wine') then
        return true
    end
    if name:find('sandwich') or name:find('tosti') or name:find('candy') or name:find('chips') or name:find('milk') then
        return true
    end
    return false
end

local function isAllowedStorefrontItem(itemDef)
    if type(itemDef) ~= 'table' or not itemDef.name then
        return false
    end

    local key = tostring(itemDef.name):lower()
    local sharedItem = QBCore and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[key] or nil

    if sharedItem and isConsumable(sharedItem) then
        return hasValidImage(sharedItem, itemDef.image)
    end

    return true
end

local function getStorefrontItems(storeDef)
    local out = {}
    local sf = storeDef and storeDef.storefront or nil
    if not sf or type(sf.items) ~= 'table' then return out end

    for _, it in ipairs(sf.items) do
        if isAllowedStorefrontItem(it) then
            out[#out + 1] = it
        end
    end

    return out
end

local function normalizeStorefrontCart(cart)
    if type(cart) ~= 'table' then return {} end
    local out = {}
    for _, entry in ipairs(cart) do
        if type(entry) == 'table' then
            local name = entry.name ~= nil and tostring(entry.name) or nil
            local qty = math.floor(tonumber(entry.quantity or 0) or 0)
            if name and name ~= '' then
                if qty < 1 then qty = 1 end
                if qty > 100 then qty = 100 end
                out[#out + 1] = { name = name:lower(), quantity = qty }
            end
        end
    end
    return out
end

local function buildStorefrontItemMap(storeDef)
    local map = {}
    for _, it in ipairs(getStorefrontItems(storeDef)) do
        if type(it) == 'table' and it.name and it.price ~= nil then
            local name = tostring(it.name):lower()
            local price = tonumber(it.price)
            if name ~= '' and price and price >= 0 then
                map[name] = {
                    name = name,
                    label = it.label,
                    category = it.category,
                    price = price,
                    maxQuantity = tonumber(it.maxQuantity or 50) or 50,
                }
            end
        end
    end
    return map
end

-- Owner pricing -------------------------------------------------------------

local MAX_PRICE_MULTIPLIER = 50

local function clampOwnerPrice(price, defaultPrice)
    local p = tonumber(price) or 0
    local d = tonumber(defaultPrice) or 0
    if p < 0 then p = 0 end
    local maxPrice = d * MAX_PRICE_MULTIPLIER
    if p > maxPrice then p = maxPrice end
    return roundCurrency(p)
end

local function getOwnerPriceMap(storeId)
    local rows = MySQL.query.await('SELECT item, price FROM pf_store_prices WHERE store_id = ?', { storeId })
    local map = {}
    for _, r in ipairs(rows or {}) do
        local item = tostring(r.item or ''):lower()
        local price = tonumber(r.price)
        if item ~= '' and price ~= nil and price >= 0 then
            map[item] = roundCurrency(price)
        end
    end
    return map
end

-- Effective (charged/displayed) price for one storefront item definition.
local function effectivePrice(itemDef, ownerPrices)
    local defaultPrice = tonumber(itemDef and itemDef.price or 0) or 0
    local key = itemDef and tostring(itemDef.name or ''):lower() or ''
    local override = ownerPrices and ownerPrices[key] or nil
    if override == nil then
        return roundCurrency(defaultPrice), false
    end
    return clampOwnerPrice(override, defaultPrice), true
end

-- Owner validation + mutation rate limiting ---------------------------------

local mutationLocks = {}

local function checkRateLimit(key, seconds)
    local now = os.time()
    local last = mutationLocks[key]
    if last and (now - last) < (seconds or 2) then
        return false
    end
    mutationLocks[key] = now
    return true
end

-- Validates that the source player owns the store. Citizenid always comes
-- from the server-side Player object, never from the client payload.
local function requireOwnedStore(src, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        return nil, 'invalid_store'
    end

    local Player = QBCore.Functions.GetPlayer(src)
    local citizenid = Player and Player.PlayerData and Player.PlayerData.citizenid or nil
    if not citizenid then
        return nil, 'no_player'
    end

    local row = getStoreRow(storeId)
    if not row then
        return nil, 'store_not_found'
    end

    local owner = row.owner_citizenid ~= nil and tostring(row.owner_citizenid) or ''
    if owner == '' or owner ~= tostring(citizenid) then
        return nil, 'not_owner'
    end

    return { storeId = storeId, Player = Player, citizenid = tostring(citizenid), row = row }
end

local function insertLedgerEntry(storeId, item, amount, unitPrice, total, tax, buyerCitizenid, createdAt)
    MySQL.insert.await(
        'INSERT INTO pf_store_ledger (store_id, item, amount, unit_price, total, tax, buyer_citizenid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { storeId, item, math.floor(tonumber(amount) or 0), roundCurrency(unitPrice), roundCurrency(total), roundCurrency(tax), buyerCitizenid, createdAt or nowMs() }
    )
end

-- Supply catalog
--
-- Historically, supplies were configured under storeDef.supplyItems with display names.
-- The storefront uses QBCore item names under storeDef.storefront.items.
-- To avoid configuration drift (and to make stock enforcement work), we treat storefront
-- items as the supply catalog unless supplyItems explicitly maps to an item name.
local function buildSupplyCatalog(storeDef)
    local out = {}
    if not storeDef then return out end

    local function push(itemName, label, category, cost, initialStock)
        local key = itemName ~= nil and tostring(itemName):lower() or nil
        if not key or key == '' then return end
        out[#out + 1] = {
            name = key,
            label = (label ~= nil and tostring(label)) or (QBCore.Shared.Items[key] and QBCore.Shared.Items[key].label) or key,
            category = category or 'Supplies',
            cost = tonumber(cost or 0) or 0,
            initialStock = math.floor(tonumber(initialStock or 0) or 0),
        }
    end

    local hasMappedSupplyItems = false
    if type(storeDef.supplyItems) == 'table' and #storeDef.supplyItems > 0 then
        for _, s in ipairs(storeDef.supplyItems) do
            if type(s) == 'table' and (s.item or s.itemName) then
                hasMappedSupplyItems = true
                break
            end
        end
    end

    if hasMappedSupplyItems then
        for _, s in ipairs(storeDef.supplyItems or {}) do
            if type(s) == 'table' then
                local itemName = s.item or s.itemName
                if itemName then
                    push(itemName, s.label or s.name, s.category, s.cost, s.initialStock)
                end
            end
        end
        return out
    end

    local sf = storeDef.storefront
    if sf and type(sf.items) == 'table' then
        for _, it in ipairs(sf.items) do
            if type(it) == 'table' and it.name then
                -- If you want separate wholesale costs, add `cost` on the storefront item.
                local cost = it.cost
                if cost == nil then cost = it.price end
                push(it.name, it.label, it.category, cost, 0)
            end
        end
    end

    return out
end

local function buildSupplyByName(storeDef)
    local map = {}
    for _, it in ipairs(buildSupplyCatalog(storeDef) or {}) do
        if it and it.name then
            map[tostring(it.name):lower()] = it
        end
    end
    return map
end

local function coordsToTable(c)
    if not c then return nil end
    if type(c) == 'table' then
        return { x = c.x or c[1] or 0.0, y = c.y or c[2] or 0.0, z = c.z or c[3] or 0.0 }
    end
    return { x = c.x or 0.0, y = c.y or 0.0, z = c.z or 0.0 }
end

local function coordsToTable4(c)
    if not c then return nil end
    if type(c) == 'table' then
        return { x = c.x or c[1] or 0.0, y = c.y or c[2] or 0.0, z = c.z or c[3] or 0.0, w = c.w or c[4] or c.h or c.heading or 0.0 }
    end
    return { x = c.x or 0.0, y = c.y or 0.0, z = c.z or 0.0, w = c.w or 0.0 }
end

local function ensureTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_stores (
        store_id VARCHAR(64) NOT NULL,
        label VARCHAR(128) NOT NULL,
        store_type VARCHAR(32) NOT NULL,
        owner_citizenid VARCHAR(64) NULL,
        purchased_at BIGINT NULL,
        balance DECIMAL(14,2) NOT NULL DEFAULT 0,
        PRIMARY KEY (store_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_store_supply_stock (
        store_id VARCHAR(64) NOT NULL,
        supply_name VARCHAR(128) NOT NULL,
        stock_cases INT NOT NULL DEFAULT 0,
        PRIMARY KEY (store_id, supply_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_store_supply_orders (
        id INT NOT NULL AUTO_INCREMENT,
        store_id VARCHAR(64) NOT NULL,
        owner_citizenid VARCHAR(64) NOT NULL,
        method VARCHAR(16) NOT NULL,
        status VARCHAR(32) NOT NULL,
        total DECIMAL(12,2) NOT NULL DEFAULT 0,
        items_json LONGTEXT NOT NULL,
        created_at BIGINT NOT NULL,
        delivered_at BIGINT NULL,
        external_contract_id VARCHAR(64) NULL,
        PRIMARY KEY (id),
        INDEX idx_store_id (store_id),
        INDEX idx_owner (owner_citizenid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_store_prices (
        store_id VARCHAR(64) NOT NULL,
        item VARCHAR(128) NOT NULL,
        price DECIMAL(12,2) NOT NULL DEFAULT 0,
        PRIMARY KEY (store_id, item)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS pf_store_ledger (
        id INT NOT NULL AUTO_INCREMENT,
        store_id VARCHAR(64) NOT NULL,
        item VARCHAR(128) NOT NULL,
        amount INT NOT NULL DEFAULT 0,
        unit_price DECIMAL(12,2) NOT NULL DEFAULT 0,
        total DECIMAL(12,2) NOT NULL DEFAULT 0,
        tax DECIMAL(12,2) NOT NULL DEFAULT 0,
        buyer_citizenid VARCHAR(64) NULL,
        created_at BIGINT NOT NULL,
        PRIMARY KEY (id),
        INDEX idx_store (store_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    -- Migrate existing installs: add pf_stores.balance if it's missing.
    local cols = MySQL.query.await([[SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pf_stores' AND COLUMN_NAME = 'balance']])
    local hasBalance = cols and cols[1] and (tonumber(cols[1].cnt) or 0) or 0
    if hasBalance < 1 then
        local ok, err = pcall(function()
            MySQL.query.await([[ALTER TABLE pf_stores ADD COLUMN balance DECIMAL(14,2) NOT NULL DEFAULT 0]])
        end)
        if not ok then
            print('[pf-stores] failed to add pf_stores.balance column: ' .. tostring(err))
        else
            dbg('added pf_stores.balance column')
        end
    end

    -- Trucking supply orders keep the trucker's escrowed pay so a restart can re-post the contract.
    local payoutCols = MySQL.query.await([[SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pf_store_supply_orders' AND COLUMN_NAME = 'freight_payout']])
    if not (payoutCols and payoutCols[1] and (tonumber(payoutCols[1].cnt) or 0) > 0) then
        local ok, err = pcall(function()
            MySQL.query.await([[ALTER TABLE pf_store_supply_orders ADD COLUMN freight_payout DECIMAL(12,2) NULL]])
        end)
        if not ok then print('[pf-stores] failed to add pf_store_supply_orders.freight_payout: ' .. tostring(err)) end
    end
end

local function seedStores()
    if not (Config and Config.Stores) then return end

    for storeId, def in pairs(Config.Stores) do
        if def and def.id and def.label and def.type then
            MySQL.query.await(
                'INSERT IGNORE INTO pf_stores (store_id, label, store_type, owner_citizenid, purchased_at) VALUES (?, ?, ?, NULL, NULL)',
                { def.id, def.label, def.type }
            )

            local items = buildSupplyCatalog(def)
            local isPurchasable = tostring(def.type or '') == 'purchasable'
            
            for _, item in ipairs(items or {}) do
                if item and item.name then
                    local itemName = tostring(item.name):lower()
                    
                    if isPurchasable then
                        -- Purchasable stores: start with 0 stock, players must order supplies
                        MySQL.query.await(
                            'INSERT IGNORE INTO pf_store_supply_stock (store_id, supply_name, stock_cases) VALUES (?, ?, 0)',
                            { def.id, itemName }
                        )
                    else
                        -- Non-purchasable (community/chain) stores: always reset to 50 per restart
                        MySQL.query.await(
                            'INSERT INTO pf_store_supply_stock (store_id, supply_name, stock_cases) VALUES (?, ?, 50) ON DUPLICATE KEY UPDATE stock_cases = 50',
                            { def.id, itemName }
                        )
                    end
                end
            end
        end
    end
end

local function canAccessStoreSupplies(src, storeId)
    if Config and Config.DebugAllowAnyOrderSupplies then
        return true
    end

    local citizenid = getCitizenId(src)
    if not citizenid then return false end

    local rows = MySQL.query.await('SELECT owner_citizenid FROM pf_stores WHERE store_id = ? LIMIT 1', { storeId })
    local owner = rows and rows[1] and rows[1].owner_citizenid or nil
    return owner ~= nil and owner == citizenid
end

local function getSupplyStockMap(storeId)
    local rows = MySQL.query.await('SELECT supply_name, stock_cases FROM pf_store_supply_stock WHERE store_id = ?', { storeId })
    local map = {}
    for _, r in ipairs(rows or {}) do
        map[tostring(r.supply_name)] = tonumber(r.stock_cases or 0) or 0
    end
    return map
end

local function normalizeCart(cart)
    if type(cart) ~= 'table' then return {} end
    local out = {}
    for _, entry in ipairs(cart) do
        if type(entry) == 'table' then
            local name = entry.name ~= nil and tostring(entry.name) or nil
            local qty = tonumber(entry.quantity or 0) or 0
            if name and name ~= '' then
                qty = math.floor(qty)
                if qty < 1 then qty = 1 end
                if qty > 100 then qty = 100 end
                out[#out + 1] = { name = name:lower(), quantity = qty }
            end
        end
    end
    return out
end

local function getPricedItemsFromCart(storeDef, cart)
    local items = {}
    local total = 0.0
    local byName = buildSupplyByName(storeDef)

    for _, c in ipairs(cart or {}) do
        local def = byName[tostring(c.name or ''):lower()]
        if def then
            local cost = tonumber(def.cost or 0) or 0
            local qty = tonumber(c.quantity or 0) or 0
            if qty > 0 and cost >= 0 then
                items[#items + 1] = { name = tostring(def.name):lower(), quantity = qty, cost = cost, category = def.category }
                total = total + (cost * qty)
            end
        end
    end

    -- Round to cents
    total = math.floor(total * 100 + 0.5) / 100
    return items, total
end

local function safeDecodeItems(itemsJson)
    if not itemsJson or itemsJson == '' then return {} end
    local ok, parsed = pcall(function()
        return json.decode(itemsJson)
    end)
    if not ok or type(parsed) ~= 'table' then return {} end
    return parsed
end

local function GetOrderSuppliesConfig(src, payload)
    -- For now, we only expose SmoKing as the first implemented store.
    -- Accept a storeId override so pf-computer can explicitly refresh the correct store.
    local storeId = payload and payload.storeId or nil
    storeId = resolveOwnedStoreId(src, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        return { ok = false, error = 'not_owner' }
    end
    local def = getStoreDef(storeId)
    if not def then
        return { ok = false, error = 'store_not_configured' }
    end

    if not canAccessStoreSupplies(src, storeId) then
        return { ok = false, error = 'not_owner' }
    end

    local rawStockMap = getSupplyStockMap(storeId)
    local stockMap = {}
    for k, v in pairs(rawStockMap or {}) do
        stockMap[tostring(k):lower()] = tonumber(v or 0) or 0
    end

    local ingredients = {}
    for _, item in ipairs(buildSupplyCatalog(def) or {}) do
        if item and item.name then
            local key = tostring(item.name):lower()
            ingredients[#ingredients + 1] = {
                name = key,
                label = item.label,
                category = item.category or 'Supplies',
                cost = tonumber(item.cost or 0) or 0,
                stock = tonumber(stockMap[key] or 0) or 0,
            }
        end
    end

    local truckingCfg = def.trucking or {}
    local truckingEnabled = (truckingCfg.enabled ~= false)
    local hasPickup = (truckingCfg.pickup ~= nil and truckingCfg.pickup.coords ~= nil)
    local hasDropoff = (truckingCfg.dropoff ~= nil and truckingCfg.dropoff.coords ~= nil)
    local truckingConfigured = truckingEnabled and hasPickup and hasDropoff

    local truckingReason = nil
    if not truckingEnabled then
        truckingReason = 'disabled'
    elseif not hasPickup then
        truckingReason = 'missing_pickup_coords'
    elseif not hasDropoff then
        truckingReason = 'missing_dropoff_coords'
    end

    dbg('GetOrderSuppliesConfig', storeId,
        'trucking.enabled=', tostring(truckingCfg.enabled),
        'pickup=', json.encode(coordsToTable4(truckingCfg.pickup and truckingCfg.pickup.coords or nil) or coordsToTable(truckingCfg.pickup and truckingCfg.pickup.coords or nil)),
        'dropoff=', json.encode(coordsToTable(truckingCfg.dropoff and truckingCfg.dropoff.coords or nil)),
        'configured=', tostring(truckingConfigured),
        'reason=', tostring(truckingReason)
    )

    return {
        ok = true,
        data = {
            storeId = storeId,
            businessName = def.label,
            businessType = 'store',
            delivery = {
                pickup = { available = true },
                trucking = {
                    available = truckingConfigured == true,
                    configured = truckingConfigured == true,
                    reason = truckingReason,
                }
            },
            businessTypeConfig = {
                name = 'Store',
                icon = '🏪',
                features = { 'inventory', 'transactions' },
                ingredients = ingredients,
            }
        }
    }
end

local function GetStoreManagerData(src, payload)
    local storeId = payload and payload.storeId or nil
    storeId = resolveOwnedStoreId(src, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        return { ok = false, error = 'not_owner' }
    end

    local def = getStoreDef(storeId)
    if not def then
        return { ok = false, error = 'store_not_configured' }
    end

    if not canAccessStoreSupplies(src, storeId) then
        return { ok = false, error = 'not_owner' }
    end

    local storeRow = getStoreRow(storeId)
    local orderRows = MySQL.query.await(
        'SELECT id, method, status, total, items_json, created_at, delivered_at FROM pf_store_supply_orders WHERE store_id = ? ORDER BY id DESC LIMIT 50',
        { storeId }
    )

    local rawStockMap = getSupplyStockMap(storeId)
    local stockMap = {}
    for k, v in pairs(rawStockMap or {}) do
        stockMap[tostring(k):lower()] = tonumber(v or 0) or 0
    end

    local supply = buildSupplyCatalog(def)
    local stock = {}
    local stockTotalCases = 0
    local lowStockCount = 0
    for _, it in ipairs(supply or {}) do
        if it and it.name then
            local key = tostring(it.name):lower()
            local cases = math.floor(tonumber(stockMap[key] or 0) or 0)
            stock[#stock + 1] = { name = key, label = it.label, category = it.category, stockCases = cases }
            stockTotalCases = stockTotalCases + cases
            if cases <= 5 then
                lowStockCount = lowStockCount + 1
            end
        end
    end

    local orders = {}
    local pendingOrders = 0
    for _, r in ipairs(orderRows or {}) do
        local items = safeDecodeItems(r.items_json)
        local itemCount = 0
        local casesTotal = 0
        for _, it in ipairs(items or {}) do
            if type(it) == 'table' then
                itemCount = itemCount + 1
                casesTotal = casesTotal + (tonumber(it.quantity or 0) or 0)
            end
        end

        local status = tostring(r.status or '')
        if status ~= 'unpacked' and status ~= 'cancelled' and status ~= 'failed' then
            pendingOrders = pendingOrders + 1
        end

        orders[#orders + 1] = {
            id = tonumber(r.id or 0) or 0,
            method = tostring(r.method or ''),
            status = status,
            total = tonumber(r.total or 0) or 0,
            itemCount = itemCount,
            casesTotal = casesTotal,
            createdAt = tonumber(r.created_at or 0) or 0,
            deliveredAt = r.delivered_at ~= nil and (tonumber(r.delivered_at) or 0) or nil,
        }
    end

    local sinceMs = nowMs() - (7 * 24 * 60 * 60 * 1000)
    local spend7dRows = MySQL.query.await(
        'SELECT SUM(total) AS spend FROM pf_store_supply_orders WHERE store_id = ? AND created_at >= ?',
        { storeId, sinceMs }
    )
    local spend7d = 0
    if spend7dRows and spend7dRows[1] and spend7dRows[1].spend ~= nil then
        spend7d = tonumber(spend7dRows[1].spend) or 0
    end

    return {
        ok = true,
        data = {
            store = {
                storeId = storeId,
                label = (storeRow and storeRow.label) or def.label,
                storeType = (storeRow and storeRow.store_type) or def.type,
                purchasedAt = storeRow and storeRow.purchased_at or nil,
            },
            stats = {
                stockItemCount = #stock,
                stockTotalCases = stockTotalCases,
                lowStockCount = lowStockCount,
                pendingOrders = pendingOrders,
                spend7d = spend7d,
            },
            stock = stock,
            orders = orders,
        }
    }
end

-- pf-stores is the 'store' buyer of the shared supply order service
PFOrders.RegisterBuyerKind('store', {
    canManage = function(src, storeId) return canAccessStoreSupplies(src, storeId) == true end,
    account = function(storeId) return storeAccountRef(storeId) end,
    ensureAccount = function(storeId) return ensureStoreAccount(storeId) end,
    price = function(storeId, cart)
        local def = getStoreDef(storeId)
        if not def then return {}, 0 end
        local lines, total = getPricedItemsFromCart(def, normalizeCart(cart or {}))
        local byName = buildSupplyByName(def)
        for _, l in ipairs(lines) do
            local d = byName[l.name]
            l.label = d and d.label or l.name
        end
        return lines, total
    end,
    route = function(storeId)
        local def = getStoreDef(storeId)
        local trucking = def and def.trucking or nil
        if not trucking or trucking.enabled == false or not (trucking.pickup and trucking.pickup.coords and trucking.dropoff and trucking.dropoff.coords) then
            return nil
        end
        return {
            pickup = { label = trucking.pickup.label or 'Pickup', coords = coordsToTable4(trucking.pickup.coords) },
            dropoff = { label = trucking.dropoff.label or 'Dropoff', coords = coordsToTable(trucking.dropoff.coords) },
            unload = trucking.unload and { label = 'Unload', coords = coordsToTable4(trucking.unload) } or nil,
            trucking = trucking,
        }
    end,
    unpack = function(storeId, lines)
        for _, it in ipairs(lines or {}) do
            local qty = math.floor(tonumber(it.quantity) or 0)
            if it.name and qty > 0 then
                MySQL.query.await(
                    'INSERT INTO pf_store_supply_stock (store_id, supply_name, stock_cases) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE stock_cases = stock_cases + VALUES(stock_cases)',
                    { tostring(storeId), tostring(it.name), qty }
                )
            end
        end
        return true
    end,
})

local function CheckoutSupplies(src, payload)
    local storeId = payload and payload.storeId or nil
    storeId = resolveOwnedStoreId(src, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        return { ok = false, error = 'not_owner' }
    end

    local def = getStoreDef(storeId)
    if not def then
        return { ok = false, error = 'store_not_configured' }
    end

    if not canAccessStoreSupplies(src, storeId) then
        return { ok = false, error = 'not_owner' }
    end

    local method = payload and payload.method or nil
    method = tostring(method or ''):lower()
    if method ~= 'pickup' and method ~= 'trucking' then
        return { ok = false, error = 'invalid_method' }
    end

    local cart = normalizeCart(payload and payload.cart or {})
    if #cart == 0 then
        return { ok = false, error = 'empty_cart' }
    end

    local priced, total = getPricedItemsFromCart(def, cart)
    if #priced == 0 then
        return { ok = false, error = 'invalid_items' }
    end

    local citizenid = getCitizenId(src)
    if not citizenid then
        return { ok = false, error = 'no_player' }
    end

    local createdAt = nowMs()

    -- Deduplicate double-fired NUI callbacks.
    -- We lock by (player, store, method, total, items) and also look for a matching recent order.
    local itemsJsonForLock = json.encode(priced)
    local lockKey = ('%s|%s|%s|%.2f|%s'):format(tostring(citizenid), tostring(storeId), tostring(method), tonumber(total) or 0, itemsJsonForLock)

    if checkoutLocks[lockKey] then
        local waited = 0
        while checkoutLocks[lockKey] and waited < 1500 do
            Wait(50)
            waited = waited + 50
        end
    end

    checkoutLocks[lockKey] = true

    local function unlock()
        checkoutLocks[lockKey] = nil
    end

    local function findRecentDuplicate()
        local since = createdAt - 15000
        local rows = MySQL.query.await(
            'SELECT id, method, status, external_contract_id, total, created_at FROM pf_store_supply_orders WHERE store_id = ? AND owner_citizenid = ? AND method = ? AND total = ? AND items_json = ? AND created_at >= ? ORDER BY id DESC LIMIT 1',
            { storeId, citizenid, method, total, itemsJsonForLock, since }
        )
        return rows and rows[1] or nil
    end

    local recent = findRecentDuplicate()
    if recent and recent.id then
        unlock()
        return {
            ok = true,
            data = {
                orderId = tonumber(recent.id) or 0,
                total = tonumber(recent.total) or total,
                contractId = recent.external_contract_id ~= nil and tostring(recent.external_contract_id) or nil,
                createdAt = tonumber(recent.created_at) or createdAt,
                items = priced,
            },
            message = 'Order already placed.'
        }
    end

    -- Everything after this point (payment, supplier, trucking, delivery, stock) is the order
    -- service's (server_orders.lua): one persistent order with one id from payment to unpacking.
    local res = PFOrders.Create(src, { kind = 'store', buyerId = storeId, method = method, cart = cart, deferDelivery = payload and payload.deferDelivery == true })
    unlock()
    if not res.ok then
        if res.error == 'insufficient_funds' then res.error = 'insufficient_store_funds' end
        res.data = res.data or {}
        res.data.balance = getStoreBalance(storeId)
        return res
    end
    if method == 'pickup' then
        res.message = (payload and payload.deferDelivery) and 'Order placed.' or 'Order delivered to your store stock.'
    else
        res.message = 'Order posted for suppliers and Trucking Dispatch.'
    end
    return res
end

QBCore.Functions.CreateCallback('pf-stores:server:getStorePurchaseState', function(source, cb, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        cb({ ok = false, error = 'invalid_store' })
        return
    end

    local row = getStoreRow(storeId)
    local owned = false
    local purchasedAt = nil
    if row and row.owner_citizenid ~= nil and tostring(row.owner_citizenid) ~= '' then
        owned = true
        purchasedAt = row.purchased_at
    end

    cb({
        ok = true,
        data = {
            storeId = storeId,
            owned = owned,
            purchasedAt = purchasedAt,
        }
    })
end)

QBCore.Functions.CreateCallback('pf-stores:server:getStorefrontStock', function(source, cb, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        cb({ ok = false, error = 'invalid_store' })
        return
    end

    local def = getStoreDef(storeId)
    if not def or not def.storefront or def.storefront.enabled == false then
        cb({ ok = false, error = 'storefront_disabled' })
        return
    end

    local raw = getSupplyStockMap(storeId)
    local stockLower = {}
    for k, v in pairs(raw or {}) do
        stockLower[tostring(k):lower()] = math.floor(tonumber(v or 0) or 0)
    end

    local ownerPrices = getOwnerPriceMap(storeId)

    local out = {}
    local prices = {}
    for _, it in ipairs(getStorefrontItems(def)) do
        if it and it.name then
            local key = tostring(it.name):lower()
            out[key] = tonumber(stockLower[key] or 0) or 0
            if it.price ~= nil then
                prices[key] = effectivePrice(it, ownerPrices)
            end
        end
    end

    local citizenid = getCitizenId(source)
    local owner = getStoreOwner(storeId)
    local isOwner = citizenid ~= nil and owner ~= nil and owner == tostring(citizenid)

    cb({ ok = true, data = { storeId = storeId, stock = out, prices = prices, isOwner = isOwner == true } })
end)

exports('GetOrderSuppliesConfig', GetOrderSuppliesConfig)
exports('CheckoutSupplies', CheckoutSupplies)
exports('GetStoreManagerData', GetStoreManagerData)

-- Export config for cross-resource integration (pf-computer foreclosure upgrades)
exports('GetStoreConfig', function()
    return Config
end)

--- The bank balance of a store the player owns (for the pf-computer Order Supplies app).
exports('GetStoreBalance', function(src, payload)
    local storeId = tostring(resolveOwnedStoreId(src, payload and payload.storeId or nil) or '')
    if storeId == '' or not canAccessStoreSupplies(src, storeId) then
        return { ok = false, error = 'not_owner' }
    end
    return { ok = true, data = { storeId = storeId, balance = getStoreBalance(storeId) } }
end)

exports('ListOwnedStores', function(src)
    local citizenid = getCitizenId(src)
    if not citizenid then
        return { ok = false, error = 'no_player' }
    end

    local rows = MySQL.query.await(
        'SELECT store_id, label, store_type, purchased_at FROM pf_stores WHERE owner_citizenid = ? ORDER BY purchased_at DESC',
        { citizenid }
    )

    local stores = {}
    for _, r in ipairs(rows or {}) do
        stores[#stores + 1] = {
            storeId = tostring(r.store_id or ''),
            label = tostring(r.label or r.store_id or 'Store'),
            storeType = tostring(r.store_type or 'store'),
            purchasedAt = r.purchased_at ~= nil and (tonumber(r.purchased_at) or 0) or nil,
        }
    end

    return { ok = true, data = { stores = stores } }
end)

exports('ListSupplyOrders', function(src, payload)
    local storeId = payload and payload.storeId or nil
    storeId = resolveOwnedStoreId(src, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        return { ok = false, error = 'not_owner' }
    end
    if not canAccessStoreSupplies(src, storeId) then
        return { ok = false, error = 'not_owner' }
    end

    local rows = MySQL.query.await(
        'SELECT id, method, status, total, items_json, created_at, delivered_at FROM pf_store_supply_orders WHERE store_id = ? ORDER BY id DESC LIMIT 100',
        { storeId }
    )

    local orders = {}
    for _, r in ipairs(rows or {}) do
        local parsed = safeDecodeItems(r.items_json)
        local items = {}
        local totalCases = 0
        for _, it in ipairs(parsed or {}) do
            if type(it) == 'table' then
                local qty = math.floor(tonumber(it.quantity or 0) or 0)
                if qty > 0 then
                    totalCases = totalCases + qty
                end

                items[#items + 1] = {
                    item = tostring(it.name or ''),
                    label = tostring(it.label or it.name or ''),
                    category = tostring(it.category or 'Supplies'),
                    caseSize = 1,
                    caseContents = '1 case',
                    pricePerCase = tonumber(it.cost or 0) or 0,
                    quantity = qty,
                    lineTotal = tonumber(it.cost or 0) * qty,
                }
            end
        end

        orders[#orders + 1] = {
            id = tonumber(r.id or 0) or 0,
            storeId = storeId,
            method = tostring(r.method or ''),
            status = tostring(r.status or ''),
            total = tonumber(r.total or 0) or 0,
            totalCases = totalCases,
            items = items,
            createdAt = tonumber(r.created_at or 0) or 0,
            deliveredAt = r.delivered_at ~= nil and (tonumber(r.delivered_at) or 0) or nil,
        }
    end

    return { ok = true, data = { storeId = storeId, orders = orders } }
end)

exports('DeliverSupplyOrder', function(src, payload)
    local storeId = tostring(resolveOwnedStoreId(src, payload and payload.storeId or nil) or '')
    if storeId == '' or not canAccessStoreSupplies(src, storeId) then
        return { ok = false, error = 'not_owner' }
    end
    local orderId = tonumber(payload and payload.orderId or 0) or 0
    if orderId <= 0 then return { ok = false, error = 'invalid_order' } end
    return PFOrders.Collect(src, 'store', storeId, orderId)
end)

--- Cancels a delivery order nobody is delivering yet and refunds the store.
exports('CancelSupplyOrder', function(src, payload)
    local storeId = tostring(resolveOwnedStoreId(src, payload and payload.storeId or nil) or '')
    if storeId == '' or not canAccessStoreSupplies(src, storeId) then
        return { ok = false, error = 'not_owner' }
    end
    return PFOrders.Cancel(src, 'store', storeId, tonumber(payload and payload.orderId or 0) or 0)
end)

-- kept for callers of the old name: re-posts open delivery contracts (with their drivers)
function RepostOpenSupplyOrders()
    return PFOrders.RecoverContracts()
end

-- Moves balances still held in pf_stores.balance (from before stores banked through the ledger) into
-- each store's bank account. Safe to run on every start: the key includes the store and amount, and the
-- column is only zeroed once the bank holds the money.
function MigrateStoreBalancesToBank()
    local rows = MySQL.query.await('SELECT store_id, balance FROM pf_stores WHERE balance > 0') or {}
    local moved = 0
    for _, row in ipairs(rows) do
        local storeId = tostring(row.store_id)
        local amount = roundCurrency(tonumber(row.balance) or 0)
        if amount > 0 and ensureStoreAccount(storeId) then
            local res = ledgerTransfer({
                from = 'system:pf-stores-migration', to = storeAccountRef(storeId), amount = amount,
                key = ('pf-stores:balance-to-bank:%s:%.2f'):format(storeId, amount),
                kind = 'migration', reason = 'Store balance moved to bank account',
            })
            if res.ok then
                MySQL.update.await('UPDATE pf_stores SET balance = 0 WHERE store_id = ? AND balance = ?', { storeId, row.balance })
                moved = moved + 1
            else
                print(('^1[pf-stores]^7 could not move balance of %s to the bank (%s); will retry next start'):format(storeId, tostring(res.error)))
            end
        end
    end
    if moved > 0 then print(('[pf-stores] moved %d store balance(s) into bank accounts'):format(moved)) end
    return moved
end

CreateThread(function()
    ensureTables()
    seedStores()
    for _, row in ipairs(MySQL.query.await("SELECT store_id, label, owner_citizenid FROM pf_stores WHERE owner_citizenid IS NOT NULL AND owner_citizenid <> ''") or {}) do
        registerStoreWithGovernment(row.store_id, row.owner_citizenid, row.label)
    end
    -- wait for the bank ledger (it runs its own migrations at start)
    local waited = 0
    while not bankReady() and waited < 120 do
        Wait(1000)
        waited = waited + 1
    end
    if bankReady() then
        MigrateStoreBalancesToBank()
        ensureEscrowAccount()
        if PFOrders.Start() then
            PFOrders.RecoverPayments()
            if GetResourceState('pf-trucking') == 'started' then
                local n = PFOrders.RecoverContracts()
                if n > 0 then print(('[pf-stores] re-posted %d open supply delivery contract(s)'):format(n)) end
            end
            CreateThread(function()
                while true do
                    local ok, err = pcall(PFOrders.Tick)
                    if not ok then print('^1[pf-stores]^7 supply order timer: ' .. tostring(err)) end
                    Wait(5000)
                end
            end)
        end
    else
        print('^1[pf-stores]^7 pfm-banking ledger not available: store sales and withdrawals are disabled until it is')
    end
    dbg('server started')
end)

QBCore.Functions.CreateCallback('pf-stores:server:getStore', function(source, cb, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        cb({ ok = false, error = 'invalid_store' })
        return
    end

    local row = getStoreRow(storeId)
    if not row then
        cb({ ok = false, error = 'store_not_found' })
        return
    end

    -- the owner and the store's bank balance are for the owner only
    local Player = QBCore.Functions.GetPlayer(source)
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if not cid or tostring(row.owner_citizenid or '') ~= tostring(cid) then
        row = { store_id = row.store_id, label = row.label, store_type = row.store_type, owned = row.owner_citizenid ~= nil and tostring(row.owner_citizenid) ~= '' }
    end

    cb({ ok = true, data = row })
end)

QBCore.Functions.CreateCallback('pf-stores:server:purchaseStore', function(source, cb, storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then
        cb({ ok = false, error = 'invalid_store' })
        return
    end

    local def = getStoreDef(storeId)
    if not def then
        cb({ ok = false, error = 'store_not_configured' })
        return
    end

    if tostring(def.type or '') ~= 'purchasable' then
        cb({ ok = false, error = 'not_purchasable' })
        return
    end
    if not nearPoint(source, def.purchase and def.purchase.coords, 10.0) then
        cb({ ok = false, error = 'too_far' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, error = 'no_player' })
        return
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if not citizenid then
        cb({ ok = false, error = 'no_citizenid' })
        return
    end

    local row = getStoreRow(storeId)
    if not row then
        cb({ ok = false, error = 'store_not_found' })
        return
    end

    if row.owner_citizenid ~= nil and tostring(row.owner_citizenid) ~= '' then
        cb({ ok = false, error = 'already_owned' })
        return
    end

    local purchaseCfg = def.purchase or {}
    local price = tonumber(purchaseCfg.price or 0) or 0
    local moneyType = tostring(purchaseCfg.moneyType or 'bank')
    if moneyType ~= 'bank' and moneyType ~= 'cash' then
        moneyType = 'bank'
    end

    if not bankReady() then
        cb({ ok = false, error = 'bank_unavailable' })
        return
    end

    -- Charge first, then claim; if someone else claimed it in the meantime the charge is refunded.
    local buyerRef = ('player:%s:%s'):format(citizenid, moneyType)
    local charge
    if price > 0 then
        charge = ledgerTransfer({
            from = buyerRef, to = SALES_ACCOUNT, amount = price,
            key = newKey('storebuy'), kind = 'purchase', reason = ('Store purchase: %s'):format(storeId), actor = citizenid,
            metadata = { store = storeId },
        })
        if not charge.ok then
            if charge.error == 'insufficient_funds' then
                cb({ ok = false, error = 'not_enough_money', data = { price = price, moneyType = moneyType } })
            else
                cb({ ok = false, error = 'payment_failed' })
            end
            return
        end
    end

    local purchasedAt = nowMs()
    local updated = MySQL.update.await(
        'UPDATE pf_stores SET owner_citizenid = ?, purchased_at = ? WHERE store_id = ? AND (owner_citizenid IS NULL OR owner_citizenid = \'\')',
        { citizenid, purchasedAt, storeId }
    )

    if not updated or updated < 1 then
        refundCharge(charge, buyerRef, price, 'full', ('Store purchase refund: %s'):format(storeId))
        cb({ ok = false, error = 'already_owned' })
        return
    end
    ensureStoreAccount(storeId)
    registerStoreWithGovernment(storeId, citizenid, def and def.label)

    TriggerClientEvent('pf-stores:client:onStorePurchased', -1, storeId)

    cb({ ok = true, data = { storeId = storeId, purchasedAt = purchasedAt, price = price, moneyType = moneyType } })
end)

QBCore.Functions.CreateCallback('pf-stores:server:storefrontCheckout', function(source, cb, storeId, cart, moneyTypeOverride)
    storeId = tostring(storeId or '')
    if storeId == '' then
        cb({ ok = false, error = 'invalid_store', errorMessage = 'Invalid store.' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, error = 'no_player', errorMessage = 'Player not found.' })
        return
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if not citizenid then
        cb({ ok = false, error = 'no_citizenid', errorMessage = 'Character not loaded.' })
        return
    end

    local def = getStoreDef(storeId)
    if not def or not def.storefront or def.storefront.enabled == false then
        cb({ ok = false, error = 'storefront_disabled', errorMessage = 'Storefront not configured.' })
        return
    end
    if not nearPoint(source, def.npc and def.npc.coords, 10.0) then
        cb({ ok = false, error = 'too_far', errorMessage = 'You need to be at the store.' })
        return
    end
    local mayTrade, closedWhy = storeMayTrade(storeId)
    if not mayTrade then
        cb({ ok = false, error = 'closed', errorMessage = closedWhy == 'no_power' and 'The store has no power.' or 'This store has been closed by the government.' })
        return
    end

    -- Basic anti-doublefire lock
    local lockKey = tostring(source)
    local ts = os.time()
    if storefrontLocks[lockKey] and (ts - storefrontLocks[lockKey]) < 2 then
        cb({ ok = false, error = 'cooldown', errorMessage = 'Please wait a moment.' })
        return
    end
    storefrontLocks[lockKey] = ts

    local allowedMoneyTypes = {}
    if type(def.storefront.moneyTypes) == 'table' then
        for _, mt in ipairs(def.storefront.moneyTypes) do
            local v = tostring(mt or '')
            if v == 'cash' or v == 'bank' then
                allowedMoneyTypes[v] = true
            end
        end
    end
    if not next(allowedMoneyTypes) then
        local v = tostring(def.storefront.moneyType or 'cash')
        if v ~= 'cash' and v ~= 'bank' then v = 'cash' end
        allowedMoneyTypes[v] = true
    end

    local moneyType = tostring(def.storefront.defaultMoneyType or def.storefront.moneyType or 'cash')
    if moneyType ~= 'cash' and moneyType ~= 'bank' then
        moneyType = 'cash'
    end
    if not allowedMoneyTypes[moneyType] then
        moneyType = allowedMoneyTypes['cash'] and 'cash' or 'bank'
    end

    if moneyTypeOverride ~= nil then
        local picked = tostring(moneyTypeOverride or '')
        if picked == 'cash' or picked == 'bank' then
            if allowedMoneyTypes[picked] then
                moneyType = picked
            else
                cb({ ok = false, error = 'invalid_payment_method', errorMessage = 'Invalid payment method.' })
                return
            end
        end
    end

    local normalizedCart = normalizeStorefrontCart(cart)
    if #normalizedCart == 0 then
        cb({ ok = false, error = 'empty_cart', errorMessage = 'Your cart is empty.' })
        return
    end

    local itemMap = buildStorefrontItemMap(def)
    if not next(itemMap) then
        cb({ ok = false, error = 'no_items', errorMessage = (def.label or storeId) .. ' storefront not configured yet.' })
        return
    end

    -- Owner price overrides replace config prices (server-side; the client price is never trusted).
    local ownerPrices = getOwnerPriceMap(storeId)

    local subtotal = 0
    local toGive = {}

    for _, entry in ipairs(normalizedCart) do
        local itemDef = itemMap[entry.name]
        if not itemDef then
            cb({ ok = false, error = 'invalid_item', errorMessage = 'Invalid item in cart.' })
            return
        end

        local maxQty = math.floor(tonumber(itemDef.maxQuantity or 50) or 50)
        if maxQty < 1 then maxQty = 1 end
        if maxQty > 100 then maxQty = 100 end
        local qty = math.floor(tonumber(entry.quantity or 0) or 0)
        if qty < 1 then qty = 1 end
        if qty > maxQty then qty = maxQty end

        local price = effectivePrice(itemDef, ownerPrices)
        subtotal = subtotal + (price * qty)
        toGive[#toGive + 1] = { name = entry.name, quantity = qty, price = price }
    end

    subtotal = roundCurrency(subtotal)
    local taxData = getSalesTaxBreakdown(subtotal)
    local taxAmount = roundCurrency(taxData.tax)
    local total = roundCurrency(taxData.total)

    if subtotal > 0 and taxAmount <= 0 and GetResourceState('pf-government') == 'started' then
        print(('[pf-stores] Sales tax resolved to 0. store=%s subtotal=%.2f rate=%.4f'):format(storeId, subtotal, tonumber(taxData.rate) or 0))
    end

    if total < 0 then total = 0 end

    -- Enforce stock using the same DB table as Business Manager / Order Supplies.
    -- We treat 1 case == 1 unit for storefront sales.
    local rawStock = getSupplyStockMap(storeId)
    local stock = {}
    for k, v in pairs(rawStock or {}) do
        stock[tostring(k):lower()] = tonumber(v or 0) or 0
    end

    for _, give in ipairs(toGive) do
        local available = tonumber(stock[give.name] or 0) or 0
        if available < give.quantity then
            cb({
                ok = false,
                error = 'out_of_stock',
                errorMessage = ('%s is out of stock.'):format((itemMap[give.name] and (itemMap[give.name].label or give.name)) or give.name),
            })
            return
        end
    end

    if total > 0 and not bankReady() then
        cb({ ok = false, error = 'bank_unavailable', errorMessage = 'Payments are unavailable right now.' })
        return
    end

    -- 1. Charge the shopper. Everything after this either completes or refunds through the ledger.
    local checkoutKey = newKey('storefront')
    local buyerRef = ('player:%s:%s'):format(citizenid, moneyType)
    local charge
    if total > 0 then
        charge = ledgerTransfer({
            from = buyerRef, to = SALES_ACCOUNT, amount = total,
            key = checkoutKey .. ':charge', kind = 'purchase', reason = ('Storefront: %s'):format(storeId), actor = citizenid,
            metadata = { store = storeId, subtotal = subtotal, tax = taxAmount },
        })
        if not charge.ok then
            if charge.error == 'insufficient_funds' then
                cb({
                    ok = false,
                    error = 'not_enough_money',
                    errorMessage = ('Not enough money. Subtotal: $%.2f | Tax: $%.2f | Total: $%.2f'):format(subtotal, taxAmount, total)
                })
            else
                cb({ ok = false, error = 'payment_failed', errorMessage = 'Payment failed.' })
            end
            return
        end
    end

    -- 2. Take the stock (conditional, so two shoppers cannot buy the last unit twice).
    local decremented = {}
    local function restoreStock()
        for _, d in ipairs(decremented) do
            MySQL.update.await(
                'UPDATE pf_store_supply_stock SET stock_cases = stock_cases + ? WHERE store_id = ? AND supply_name = ?',
                { d.quantity, storeId, d.name }
            )
        end
    end

    for _, give in ipairs(toGive) do
        local qty = math.floor(tonumber(give.quantity or 0) or 0)
        if qty > 0 then
            local updated = MySQL.update.await(
                'UPDATE pf_store_supply_stock SET stock_cases = stock_cases - ? WHERE store_id = ? AND supply_name = ? AND stock_cases >= ?',
                { qty, storeId, give.name, qty }
            )
            if not updated or updated < 1 then
                restoreStock()
                refundCharge(charge, buyerRef, total, 'full', ('Storefront refund: %s'):format(storeId))
                cb({
                    ok = false,
                    error = 'out_of_stock',
                    errorMessage = ('%s went out of stock during checkout. Payment refunded.'):format((itemMap[give.name] and (itemMap[give.name].label or give.name)) or give.name),
                })
                return
            end
            decremented[#decremented + 1] = { name = give.name, quantity = qty }
        end
    end

    -- 3. Hand over the items.
    local added = {}
    for _, give in ipairs(toGive) do
        local ok = Player.Functions.AddItem(give.name, give.quantity, false, nil, ('pf-stores-storefront:%s'):format(storeId))
        if not ok then
            for _, a in ipairs(added) do
                Player.Functions.RemoveItem(a.name, a.quantity, false, ('pf-stores-storefront-rollback:%s'):format(storeId))
            end
            restoreStock()
            refundCharge(charge, buyerRef, total, 'full', ('Storefront refund: %s'):format(storeId))
            cb({ ok = false, error = 'inventory_full', errorMessage = 'Not enough inventory space.' })
            return
        end

        added[#added + 1] = { name = give.name, quantity = give.quantity }

        local itemInfo = QBCore.Shared.Items[give.name]
        if itemInfo then
            TriggerClientEvent('qb-inventory:client:ItemBox', source, itemInfo, 'add', give.quantity)
        end
    end

    -- 4. Sales tax: the treasury gets exactly what the shopper paid in tax. Whatever it could not
    --    accept (government down, treasury error) goes back to the shopper instead of vanishing.
    local collectedTax = 0
    if charge and taxAmount > 0 then
        collectedTax = collectSalesTax(taxAmount, subtotal, 'citizen', citizenid, ('storefront:%s'):format(storeId), checkoutKey .. ':tax')
        if collectedTax < taxAmount then
            refundCharge(charge, buyerRef, roundCurrency(taxAmount - collectedTax), 'tax', ('Uncollected sales tax: %s'):format(storeId))
        end
    end

    -- 5. Revenue: a player-owned store's account receives the subtotal. Ownerless (NPC) stores keep
    --    the old behaviour: the money leaves the economy (it stays in system:pf-stores).
    local ownerCitizenid = getStoreOwner(storeId)
    if ownerCitizenid then
        if charge and subtotal > 0 then
            local revenue = { ok = false, error = 'no_account' }
            if ensureStoreAccount(storeId) then
                revenue = ledgerTransfer({
                    from = SALES_ACCOUNT, to = storeAccountRef(storeId), amount = subtotal,
                    key = checkoutKey .. ':revenue', kind = 'sale', reason = 'Storefront sale', actor = citizenid,
                    metadata = { store = storeId, sale = charge.txId },
                })
            end
            if revenue.ok then
                -- recorded once per checkout; the business tax comes out of the store account
                reportStoreRevenue(storeId, subtotal, checkoutKey)
            end
            if not revenue.ok then
                -- the shopper paid and has the goods; the owner's share is recorded as a failed ledger
                -- transfer under this key so it can be found and paid out
                print(('^1[pf-stores]^7 revenue %.2f for %s not credited (%s), key %s'):format(subtotal, storeId, tostring(revenue.error), checkoutKey .. ':revenue'))
            end
        end

        local soldAt = nowMs()
        for _, give in ipairs(toGive) do
            local lineTotal = roundCurrency((tonumber(give.price) or 0) * give.quantity)
            local lineTax = 0
            if subtotal > 0 and collectedTax > 0 then
                lineTax = roundCurrency(collectedTax * (lineTotal / subtotal))
            end
            insertLedgerEntry(storeId, give.name, give.quantity, give.price, lineTotal, lineTax, citizenid, soldAt)
        end
    end

    -- report what the shopper actually paid (an uncollected tax was refunded above)
    local paidTax = charge and collectedTax or 0
    local paidTotal = charge and roundCurrency(subtotal + paidTax) or 0
    cb({
        ok = true,
        data = {
            subtotal = subtotal,
            tax = paidTax,
            total = paidTotal,
            moneyType = moneyType
        },
        message = ('Purchase complete. Subtotal: $%.2f | Tax: $%.2f | Total: $%.2f'):format(subtotal, paidTax, paidTotal)
    })
end)

-- Owner management ------------------------------------------------------------

QBCore.Functions.CreateCallback('pf-stores:server:setItemPrice', function(source, cb, payload)
    local ctx, err = requireOwnedStore(source, payload and payload.storeId or nil)
    if not ctx then
        cb({ ok = false, error = err })
        return
    end

    if not checkRateLimit(('setprice:%s'):format(ctx.citizenid), 1) then
        cb({ ok = false, error = 'cooldown' })
        return
    end

    local def = getStoreDef(ctx.storeId)
    if not def or not def.storefront or def.storefront.enabled == false then
        cb({ ok = false, error = 'storefront_disabled' })
        return
    end

    local itemMap = buildStorefrontItemMap(def)
    local item = tostring(payload and payload.item or ''):lower()
    local itemDef = itemMap[item]
    if item == '' or not itemDef then
        cb({ ok = false, error = 'invalid_item' })
        return
    end

    local defaultPrice = roundCurrency(tonumber(itemDef.price or 0) or 0)
    local rawPrice = payload and payload.price or nil
    local price = tonumber(rawPrice)

    -- nil / non-numeric / <= 0 resets the override back to the config default.
    if rawPrice == nil or price == nil or price <= 0 then
        MySQL.query.await('DELETE FROM pf_store_prices WHERE store_id = ? AND item = ?', { ctx.storeId, item })
        dbg(('setItemPrice reset %s/%s'):format(ctx.storeId, item))
        cb({ ok = true, data = { storeId = ctx.storeId, item = item, price = nil, defaultPrice = defaultPrice } })
        return
    end

    local clamped = clampOwnerPrice(price, defaultPrice)
    MySQL.query.await(
        'INSERT INTO pf_store_prices (store_id, item, price) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE price = VALUES(price)',
        { ctx.storeId, item, clamped }
    )

    dbg(('setItemPrice %s/%s -> %.2f (default %.2f)'):format(ctx.storeId, item, clamped, defaultPrice))
    cb({ ok = true, data = { storeId = ctx.storeId, item = item, price = clamped, defaultPrice = defaultPrice } })
end)

QBCore.Functions.CreateCallback('pf-stores:server:withdrawBalance', function(source, cb, payload)
    local ctx, err = requireOwnedStore(source, payload and payload.storeId or nil)
    if not ctx then
        cb({ ok = false, error = err })
        return
    end

    if not checkRateLimit(('withdraw:%s'):format(ctx.citizenid), 2) then
        cb({ ok = false, error = 'cooldown' })
        return
    end

    local amount = roundCurrency(tonumber(payload and payload.amount or 0) or 0)
    if amount ~= amount or amount <= 0 or amount > 100000000 then
        cb({ ok = false, error = 'invalid_amount' })
        return
    end

    local currentBalance = roundCurrency(tonumber(ctx.row.balance or 0) or 0)
    if amount > currentBalance then
        cb({ ok = false, error = 'insufficient_balance', data = { balance = currentBalance } })
        return
    end

    -- One ledger transfer from the store's bank account; the bank refuses overdrafts.
    local res = ledgerTransfer({
        from = storeAccountRef(ctx.storeId), to = ('player:%s:bank'):format(ctx.citizenid), amount = amount,
        key = newKey('storewd'), kind = 'withdraw', reason = ('Store withdrawal: %s'):format(ctx.storeId), actor = ctx.citizenid,
    })
    if not res.ok then
        cb({ ok = false, error = res.error == 'insufficient_funds' and 'insufficient_balance' or 'payment_failed' })
        return
    end

    insertLedgerEntry(ctx.storeId, '__withdraw__', 1, amount, -amount, 0, ctx.citizenid, nowMs())

    local row = getStoreRow(ctx.storeId)
    local newBalance = roundCurrency(tonumber(row and row.balance or 0) or 0)
    dbg(('withdrawBalance %s -> %.2f (left %.2f)'):format(ctx.storeId, amount, newBalance))
    cb({ ok = true, data = { storeId = ctx.storeId, amount = amount, balance = newBalance } })
end)

-- Owner funds the store (e.g. to pay for supplies) from their own bank balance.
QBCore.Functions.CreateCallback('pf-stores:server:depositBalance', function(source, cb, payload)
    local ctx, err = requireOwnedStore(source, payload and payload.storeId or nil)
    if not ctx then
        cb({ ok = false, error = err })
        return
    end

    if not checkRateLimit(('deposit:%s'):format(ctx.citizenid), 2) then
        cb({ ok = false, error = 'cooldown' })
        return
    end

    local amount = roundCurrency(tonumber(payload and payload.amount or 0) or 0)
    if amount <= 0 or amount ~= amount or amount > 100000000 then
        cb({ ok = false, error = 'invalid_amount' })
        return
    end

    if not bankReady() or not ensureStoreAccount(ctx.storeId) then
        cb({ ok = false, error = 'bank_unavailable' })
        return
    end

    local res = ledgerTransfer({
        from = ('player:%s:bank'):format(ctx.citizenid), to = storeAccountRef(ctx.storeId), amount = amount,
        key = newKey('storedep'), kind = 'deposit', reason = ('Store deposit: %s'):format(ctx.storeId), actor = ctx.citizenid,
    })
    if not res.ok then
        cb({ ok = false, error = res.error == 'insufficient_funds' and 'insufficient_bank' or 'payment_failed' })
        return
    end

    insertLedgerEntry(ctx.storeId, '__deposit__', 1, amount, amount, 0, ctx.citizenid, nowMs())
    local newBalance = getStoreBalance(ctx.storeId)
    cb({ ok = true, data = { storeId = ctx.storeId, amount = amount, balance = newBalance } })
end)

QBCore.Functions.CreateCallback('pf-stores:server:getManagementData', function(source, cb, payload)
    local ctx, err = requireOwnedStore(source, payload and payload.storeId or nil)
    if not ctx then
        cb({ ok = false, error = err })
        return
    end

    local def = getStoreDef(ctx.storeId)
    if not def then
        cb({ ok = false, error = 'store_not_configured' })
        return
    end

    local ownerPrices = getOwnerPriceMap(ctx.storeId)

    local rawStock = getSupplyStockMap(ctx.storeId)
    local stockLower = {}
    for k, v in pairs(rawStock or {}) do
        stockLower[tostring(k):lower()] = math.floor(tonumber(v or 0) or 0)
    end

    -- Catalog + stock as the storefront computes them (1 case == 1 sellable unit).
    local catalog = {}
    local stock = {}
    local labelByItem = {}
    for _, it in ipairs(getStorefrontItems(def)) do
        if it and it.name and it.price ~= nil then
            local key = tostring(it.name):lower()
            local cases = tonumber(stockLower[key] or 0) or 0
            local defaultPrice = roundCurrency(tonumber(it.price or 0) or 0)
            local supplyCost = it.cost ~= nil and roundCurrency(tonumber(it.cost) or 0) or nil
            local override = ownerPrices[key]

            labelByItem[key] = tostring(it.label or key)
            stock[key] = { cases = cases, units = cases, unitsPerCase = 1 }
            catalog[#catalog + 1] = {
                name = key,
                label = tostring(it.label or key),
                category = it.category,
                defaultPrice = defaultPrice,
                ownerPrice = override ~= nil and clampOwnerPrice(override, defaultPrice) or nil,
                price = effectivePrice(it, ownerPrices),
                supplyCost = supplyCost,
                stockCases = cases,
                maxPrice = roundCurrency(defaultPrice * MAX_PRICE_MULTIPLIER),
            }
        end
    end

    -- Revenue summary (sales only; withdrawals are excluded by item name).
    local t = os.date('*t')
    t.hour, t.min, t.sec = 0, 0, 0
    local todayStartMs = os.time(t) * 1000
    local weekStartMs = nowMs() - (7 * 24 * 60 * 60 * 1000)

    local function sumSalesSince(sinceMs)
        local rows
        if sinceMs ~= nil then
            rows = MySQL.query.await(
                "SELECT SUM(total) AS revenue, SUM(amount) AS units FROM pf_store_ledger WHERE store_id = ? AND item NOT IN ('__withdraw__', '__deposit__') AND created_at >= ?",
                { ctx.storeId, sinceMs }
            )
        else
            rows = MySQL.query.await(
                "SELECT SUM(total) AS revenue, SUM(amount) AS units FROM pf_store_ledger WHERE store_id = ? AND item NOT IN ('__withdraw__', '__deposit__')",
                { ctx.storeId }
            )
        end
        local r = rows and rows[1] or nil
        return {
            revenue = roundCurrency(r and tonumber(r.revenue or 0) or 0),
            units = math.floor(r and tonumber(r.units or 0) or 0),
        }
    end

    local topRows = MySQL.query.await(
        "SELECT item, SUM(amount) AS units, SUM(total) AS revenue FROM pf_store_ledger WHERE store_id = ? AND item NOT IN ('__withdraw__', '__deposit__') GROUP BY item ORDER BY revenue DESC LIMIT 5",
        { ctx.storeId }
    )
    local topItems = {}
    for _, r in ipairs(topRows or {}) do
        local item = tostring(r.item or '')
        topItems[#topItems + 1] = {
            item = item,
            label = labelByItem[item] or item,
            units = math.floor(tonumber(r.units or 0) or 0),
            revenue = roundCurrency(tonumber(r.revenue or 0) or 0),
        }
    end

    local recentRows = MySQL.query.await(
        'SELECT id, item, amount, unit_price, total, tax, buyer_citizenid, created_at FROM pf_store_ledger WHERE store_id = ? ORDER BY id DESC LIMIT 25',
        { ctx.storeId }
    )
    local recent = {}
    for _, r in ipairs(recentRows or {}) do
        local item = tostring(r.item or '')
        recent[#recent + 1] = {
            id = tonumber(r.id or 0) or 0,
            item = item,
            label = item == '__withdraw__' and 'Withdrawal' or item == '__deposit__' and 'Deposit' or (labelByItem[item] or item),
            amount = math.floor(tonumber(r.amount or 0) or 0),
            unitPrice = roundCurrency(tonumber(r.unit_price or 0) or 0),
            total = roundCurrency(tonumber(r.total or 0) or 0),
            tax = roundCurrency(tonumber(r.tax or 0) or 0),
            createdAt = tonumber(r.created_at or 0) or 0,
        }
    end

    cb({
        ok = true,
        data = {
            storeId = ctx.storeId,
            label = (ctx.row and ctx.row.label) or def.label or ctx.storeId,
            balance = roundCurrency(tonumber(ctx.row.balance or 0) or 0),
            prices = ownerPrices,
            stock = stock,
            catalog = catalog,
            ledgerSummary = {
                today = sumSalesSince(todayStartMs),
                last7days = sumSalesSince(weekStartMs),
                totalSales = sumSalesSince(nil),
                topItems = topItems,
            },
            recent = recent,
        }
    })
end)
