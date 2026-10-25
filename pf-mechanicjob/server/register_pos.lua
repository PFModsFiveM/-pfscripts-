-- server/register_pos.lua
-- ADDITIVE POS (cash register) logic. Does not modify existing mechanic/work order flows.

local QBCore = exports['pfm-core']:GetCoreObject()

local registeredReceiptUseables = {}

CreateThread(function()
    Wait(500)
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS mechanic_mandatory_charges (
                id INT AUTO_INCREMENT PRIMARY KEY,
                business VARCHAR(64) NOT NULL,
                item VARCHAR(120) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_business_item (business, item)
            )
        ]])
    end)
end)

local function GetBusinessDisplayName(business)
    if business and business ~= '' then
        local row = MySQL.single.await('SELECT name FROM pf_business WHERE business = ? LIMIT 1', { business })
        if row and row.name and row.name ~= '' then
            return row.name
        end
    end

    local branding = (Config.BusinessBranding and Config.BusinessBranding[business]) or nil
    if branding and branding.name and branding.name ~= '' then
        return branding.name
    end
    return business or 'Mechanic Shop'
end

local function ResolveReceiptItemName()
    if QBCore.Shared.Items['mech_receipt'] then
        return 'mech_receipt'
    end

    for _, itemName in ipairs(Config.ReceiptItems or {}) do
        if QBCore.Shared.Items[itemName] then
            return itemName
        end
    end

    return nil
end

local function BuildReceiptMetadata(payload)
    local lines = {}
    local summaryParts = {}

    for _, entry in ipairs(payload.items or {}) do
        local qty = tonumber(entry.qty or 1) or 1
        if qty < 1 then qty = 1 end
        local unit = tonumber(entry.unitPrice or 0) or 0
        local lineTotal = tonumber(entry.lineTotal or (unit * qty)) or 0
        local label = entry.label or entry.item or 'Item'

        lines[#lines + 1] = {
            item = entry.item,
            label = label,
            qty = qty,
            unitPrice = unit,
            lineTotal = lineTotal,
        }
        summaryParts[#summaryParts + 1] = ('%sx %s (€%s)'):format(qty, label, lineTotal)
    end

    local createdAt = tonumber(payload.timestamp) or os.time()
    local timeText = os.date('%Y-%m-%d %H:%M:%S', createdAt)
    local summary = (#summaryParts > 0) and table.concat(summaryParts, ', ') or 'No items'

    local description = string.format(
        'Shop: %s\nCharged By: %s\nTime: %s\nItems: %s\nSubtotal: €%s\nTax: €%s\nTotal: €%s',
        payload.shopName or 'Mechanic Shop',
        payload.chargedBy or 'Unknown',
        timeText,
        summary,
        tonumber(payload.subtotal or 0) or 0,
        tonumber(payload.tax or 0) or 0,
        tonumber(payload.total or 0) or 0
    )

    return {
        receiptId = payload.receiptId,
        shopKey = payload.business,
        shopName = payload.shopName,
        chargedBy = payload.chargedBy,
        customerName = payload.customerName,
        customerCitizenId = payload.customerCitizenId,
        paymentType = payload.paymentType,
        subtotal = tonumber(payload.subtotal or 0) or 0,
        tax = tonumber(payload.tax or 0) or 0,
        total = tonumber(payload.total or 0) or 0,
        createdAt = createdAt,
        createdAtText = timeText,
        items = lines,
        itemSummary = summary,
        description = description,
    }
end

local function registerReceiptUseables()
    local candidates = { 'mech_receipt' }
    for _, itemName in ipairs(Config.ReceiptItems or {}) do
        candidates[#candidates + 1] = itemName
    end

    for _, itemName in ipairs(candidates) do
        if not registeredReceiptUseables[itemName] and QBCore.Shared.Items[itemName] then
            registeredReceiptUseables[itemName] = true
            QBCore.Functions.CreateUseableItem(itemName, function(source, item)
                if not item then return end
                TriggerClientEvent('pf_mech:receipt:use', source, item.info or {})
            end)
        end
    end
end

registerReceiptUseables()

local function canManagePricing(Player, business)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then
        return false
    end

    local job = Player.PlayerData.job
    local playerBusiness = Config.GetBusinessKey(job.name)
    if playerBusiness ~= business then
        return false
    end

    return job.isboss == true
end

-- Helper: tax rate
local function GetMechanicTaxRate()
    if Config.UseGovernmentTax then
        if GetResourceState('pf-government') == 'started' then
            local ok, tax = pcall(function()
                local exp = exports['pf-government']
                if exp and type(exp.GetSalesTaxRate) == 'function' then
                    return exp:GetSalesTaxRate()
                end
                return nil
            end)
            if ok and tax and type(tax) == 'number' then
                return tax
            end
        end
    end
    return Config.DefaultTax or 0.0
end

-- Helper: load full price list for a business (base + overrides + custom)
local function SeedPosItemsFromConfig(business)
    if not Config or not Config.RegisterItems then
        return
    end

    for itemId, itemData in pairs(Config.RegisterItems) do
        pcall(function()
            MySQL.insert.await([[
                INSERT INTO pf_pos_items (business, item_id, category, label, price, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, NOW(), NOW())
            ]], {
                business,
                itemId,
                itemData.category or 'General',
                itemData.label or itemId,
                tonumber(itemData.basePrice) or 0
            })
        end)
    end
end

local function GetBusinessPriceList(business)
    local prices = {}

    -- 1) Prefer POS items table (keeps tablet in sync with Business Manager edits)
    local posRows = MySQL.query.await(
        'SELECT item_id, category, label, price FROM pf_pos_items WHERE business = ? ORDER BY category, label',
        { business }
    ) or {}

    if #posRows == 0 then
        SeedPosItemsFromConfig(business)
        posRows = MySQL.query.await(
            'SELECT item_id, category, label, price FROM pf_pos_items WHERE business = ? ORDER BY category, label',
            { business }
        ) or {}
    end

    if #posRows > 0 then
        for _, row in ipairs(posRows) do
            if row.item_id and row.item_id ~= '' then
                prices[row.item_id] = {
                    label = row.label or row.item_id,
                    price = tonumber(row.price) or 0,
                    category = row.category or 'General',
                    isCustom = false,
                }
            end
        end
    else
        -- Fallback to Config.RegisterItems if POS table is still empty
        for item, data in pairs(Config.RegisterItems or {}) do
            prices[item] = {
                label = data.label,
                price = data.basePrice,
                category = data.category,
                isCustom = false,
            }
        end
    end

    -- 2) apply DB overrides/customs, respecting soft deletes
    local rows = MySQL.query.await(
        'SELECT item, label, category, price, is_custom, is_deleted FROM mechanic_prices WHERE business = ? ORDER BY category, label',
        { business }
    ) or {}

    for _, row in ipairs(rows) do
        if row.is_deleted == 1 then
            if row.item and row.item ~= '' then
                prices[row.item] = nil
            end
        else
            if row.is_custom == 0 then
                -- Override base entry if present; otherwise add it
                prices[row.item] = prices[row.item] or {
                    label = row.label or row.item,
                    price = tonumber(row.price) or 0,
                    category = row.category or 'General',
                    isCustom = false,
                }
                prices[row.item].price = tonumber(row.price) or prices[row.item].price
                prices[row.item].label = row.label or prices[row.item].label
                prices[row.item].category = row.category or prices[row.item].category
            else
                -- Custom POS-only item
                prices[row.item] = {
                    label = row.label,
                    price = row.price,
                    category = row.category,
                    isCustom = true,
                }
            end
        end
    end

    return prices
end

local function GetMandatoryChargeKeys(business)
    local rows = MySQL.query.await(
        'SELECT item FROM mechanic_mandatory_charges WHERE business = ? ORDER BY id ASC',
        { business }
    ) or {}

    local keys = {}
    for _, row in ipairs(rows) do
        if row.item and row.item ~= '' then
            keys[#keys + 1] = row.item
        end
    end

    return keys
end

local function GetMandatoryChargeEntries(business)
    local prices = GetBusinessPriceList(business)
    local keys = GetMandatoryChargeKeys(business)
    local out = {}

    for _, item in ipairs(keys) do
        local entry = prices[item]
        if entry then
            out[#out + 1] = {
                item = item,
                label = entry.label or item,
                category = entry.category or 'General',
                price = tonumber(entry.price or 0) or 0,
            }
        end
    end

    return out
end

-- Callback: management UI fetches price list
QBCore.Functions.CreateCallback('mechanic:server:getBusinessPrices', function(source, cb, business)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({}) return end
    local b = business or (Player.PlayerData.job and Config.GetBusinessKey(Player.PlayerData.job.name)) or 'mechanic'
    cb({
        business = b,
        prices = GetBusinessPriceList(b),
        mandatoryCharges = GetMandatoryChargeEntries(b),
        taxRate = GetMechanicTaxRate(),
        canEdit = canManagePricing(Player, b),
    })
end)

-- Callback: upsert price entry (base override or custom)
QBCore.Functions.CreateCallback('mechanic:server:savePriceEntry', function(source, cb, payload)
    -- payload: business, item, label, category, price, isCustom
    if not payload or not payload.business or not payload.item then
        cb(false, 'invalid_payload')
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not canManagePricing(Player, payload.business) then
        cb(false, 'not_authorized')
        return
    end

    local isCustom = payload.isCustom and 1 or 0
    local price = tonumber(payload.price) or 0
    if price < 0 then price = 0 end

    MySQL.insert.await([[INSERT INTO mechanic_prices (business, item, label, category, price, is_custom)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label), category = VALUES(category), price = VALUES(price), is_custom = VALUES(is_custom), is_deleted = 0
    ]], { payload.business, payload.item, payload.label or payload.item, payload.category or 'Uncategorized', price, isCustom })

    cb(true)
end)

-- Callback: delete custom entry only
QBCore.Functions.CreateCallback('mechanic:server:deleteCustomEntry', function(source, cb, payload)
    if not payload or not payload.business or not payload.item then
        cb(false, 'invalid_payload')
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not canManagePricing(Player, payload.business) then
        cb(false, 'not_authorized')
        return
    end

    MySQL.execute.await('DELETE FROM mechanic_prices WHERE business = ? AND item = ? AND is_custom = 1', { payload.business, payload.item })
    cb(true)
end)

-- Callback: soft-delete any item (config or custom) for a business
QBCore.Functions.CreateCallback('mechanic:server:deletePriceEntry', function(source, cb, payload)
    if not payload or not payload.business or not payload.item then
        cb(false, 'invalid_payload')
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not canManagePricing(Player, payload.business) then
        cb(false, 'not_authorized')
        return
    end

    local isCustom = (Config.RegisterItems and Config.RegisterItems[payload.item]) and 0 or 1
    local existing = MySQL.scalar.await(
        'SELECT id FROM mechanic_prices WHERE business = ? AND item = ? LIMIT 1',
        { payload.business, payload.item }
    )

    if existing then
        MySQL.update.await(
            'UPDATE mechanic_prices SET is_deleted = 1 WHERE business = ? AND item = ?',
            { payload.business, payload.item }
        )
    else
        MySQL.insert.await(
            'INSERT INTO mechanic_prices (business, item, label, category, price, is_custom, is_deleted) VALUES (?, ?, ?, ?, ?, ?, 1)',
            { payload.business, payload.item, payload.item, 'Uncategorized', 0, isCustom }
        )
    end

    cb(true)
end)

QBCore.Functions.CreateCallback('mechanic:server:resetBusinessPricing', function(source, cb, payload)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb(false, 'no_player')
        return
    end

    local business = (payload and payload.business) or (Player.PlayerData.job and Config.GetBusinessKey(Player.PlayerData.job.name)) or 'mechanic'
    if not canManagePricing(Player, business) then
        cb(false, 'not_authorized')
        return
    end

    MySQL.execute.await('DELETE FROM mechanic_prices WHERE business = ?', { business })
    MySQL.execute.await('DELETE FROM mechanic_mandatory_charges WHERE business = ?', { business })
    cb(true)
end)

QBCore.Functions.CreateCallback('mechanic:server:setMandatoryCharge', function(source, cb, payload)
    if not payload or not payload.business or not payload.item then
        cb(false, 'invalid_payload')
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not canManagePricing(Player, payload.business) then
        cb(false, 'not_authorized')
        return
    end

    local prices = GetBusinessPriceList(payload.business)
    if not prices[payload.item] then
        cb(false, 'item_not_found')
        return
    end

    MySQL.insert.await(
        'INSERT INTO mechanic_mandatory_charges (business, item) VALUES (?, ?) ON DUPLICATE KEY UPDATE item = VALUES(item)',
        { payload.business, payload.item }
    )

    cb(true)
end)

QBCore.Functions.CreateCallback('mechanic:server:removeMandatoryCharge', function(source, cb, payload)
    if not payload or not payload.business or not payload.item then
        cb(false, 'invalid_payload')
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not canManagePricing(Player, payload.business) then
        cb(false, 'not_authorized')
        return
    end

    MySQL.execute.await('DELETE FROM mechanic_mandatory_charges WHERE business = ? AND item = ?', {
        payload.business,
        payload.item,
    })

    cb(true)
end)

-- Event: hard reset all pricing for a business
RegisterNetEvent('mechanic:server:resetBusinessPricing', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local business = Config.GetBusinessKey(Player.PlayerData.job.name)
    if not business then return end

    if not canManagePricing(Player, business) then
        TriggerClientEvent('QBCore:Notify', src, 'Only the business owner can reset pricing', 'error')
        return
    end

    -- Hard delete all overrides, deletions, and customs
    MySQL.execute.await('DELETE FROM mechanic_prices WHERE business = ?', { business })
    
    TriggerClientEvent('QBCore:Notify', src, 'Pricing reset to defaults', 'success')
end)

-- Event: open register app (no customer required)
RegisterNetEvent('mechanic:server:openRegisterApp', function(business)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local b = business or (Player.PlayerData.job and Config.GetBusinessKey(Player.PlayerData.job.name)) or 'mechanic'
    local payload = {
        business = b,
        items = GetBusinessPriceList(b),
        mandatoryCharges = GetMandatoryChargeEntries(b),
        taxRate = GetMechanicTaxRate(),
        canEdit = canManagePricing(Player, b),
    }

    TriggerClientEvent('mechanic:client:openRegister', src, payload)
end)

-- POS money ---------------------------------------------------------------------------------------
-- A sale is a chain of ledger transfers sharing one key prefix:
--   customer -> system:pf-mechanicjob (charge)  -> treasury (tax, when forwarded)
--   system:pf-mechanicjob -> society:<shop> (takings)  -> charging mechanic (commission)
-- The shop is always the charging mechanic's own job; the client no longer picks it.
local POS_ACCOUNT = 'system:pf-mechanicjob'

local function posBankReady()
    if GetResourceState('pfm-banking') ~= 'started' then return false end
    local ok, ready = pcall(function() return exports['pfm-banking']:IsLedgerReady() end)
    return ok and ready == true
end

local function posTransfer(opts)
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

local function posDistance(a, b)
    local pa, pb = GetEntityCoords(GetPlayerPed(a)), GetEntityCoords(GetPlayerPed(b))
    if not pa or not pb then return math.huge end
    local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, (pa.z or 0) - (pb.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Charging a customer is two steps: the mechanic's register sends the bill, the customer sees it on
-- their own screen and accepts or declines. Money only moves on accept (charging yourself needs no
-- prompt). Pending bills live here, one per customer and one per mechanic, and expire.
local PendingCharges = {}      -- [invoiceId] = invoice
local nextInvoiceId = 0

local function confirmSeconds()
    return tonumber(Config.POS and Config.POS.ConfirmSeconds) or 60
end

local function findPending(field, value)
    for id, inv in pairs(PendingCharges) do
        if inv[field] == value then return id, inv end
    end
end

local function dropExpiredCharges()
    local now = os.time()
    for id, inv in pairs(PendingCharges) do
        if now > inv.expiresAt then
            PendingCharges[id] = nil
            TriggerClientEvent('QBCore:Notify', inv.mechSrc, 'The customer did not answer the bill', 'error')
            TriggerClientEvent('mechanic:client:chargeClosed', inv.customerSrc, id)
        end
    end
end

local executeCharge -- defined below

-- Event: charge customer (cash / card)
RegisterNetEvent('mechanic:server:chargeCustomer', function(data)
    local src = source
    local mech = QBCore.Functions.GetPlayer(src)
    if not mech then return end

    if type(data) ~= 'table' or not data.customerId then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid charge request', 'error')
        return
    end

    -- Only mechanics charge, and only for their own shop (this used to take the shop name from the
    -- client, so anyone could charge anyone and send the money to any society account).
    local job = mech.PlayerData.job and mech.PlayerData.job.name or nil
    if not job or not Config.IsMechanicJob(job) then
        TriggerClientEvent('QBCore:Notify', src, 'Only mechanics can use the register', 'error')
        return
    end
    local business = Config.GetBusinessKey(job)
    if data.business ~= nil and tostring(data.business) ~= business then
        TriggerClientEvent('QBCore:Notify', src, 'You can only charge for your own shop', 'error')
        return
    end

    local customer = QBCore.Functions.GetPlayer(tonumber(data.customerId))
    if not customer then
        TriggerClientEvent('QBCore:Notify', src, 'Customer not found nearby', 'error')
        return
    end
    local isChargingSelf = customer.PlayerData.source == mech.PlayerData.source
    if not isChargingSelf and posDistance(src, customer.PlayerData.source) > ((Config.POS and Config.POS.MaxChargeDistance) or 10.0) then
        TriggerClientEvent('QBCore:Notify', src, 'Customer not found nearby', 'error')
        return
    end

    if not posBankReady() then
        TriggerClientEvent('QBCore:Notify', src, 'Payments are unavailable right now', 'error')
        return
    end
    local okAccount, hasAccount = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(business) end)
    if not (okAccount and hasAccount) then
        TriggerClientEvent('QBCore:Notify', src, 'This shop has no bank account', 'error')
        return
    end

    -- Rebuild totals server-side to avoid tampering
    local priceList = GetBusinessPriceList(business)
    local subtotal = 0
    local billedItems = {}
    local cartItems = type(data.items) == 'table' and data.items or {}
    local mandatoryKeys = GetMandatoryChargeKeys(business)
    local seen = {}
    for _, item in ipairs(cartItems) do
        if type(item) == 'table' and item.item then
            seen[item.item] = true
        end
    end
    for _, mandatoryItem in ipairs(mandatoryKeys) do
        if not seen[mandatoryItem] then
            cartItems[#cartItems + 1] = { item = mandatoryItem, qty = 1 }
        end
    end
    for _, item in ipairs(cartItems) do
        local entry = type(item) == 'table' and priceList[item.item] or nil
        if entry then
            local qty = math.floor(tonumber(item.qty or item.quantity or 1) or 1)
            if qty < 1 then qty = 1 end
            if qty > 100 then qty = 100 end
            local lineTotal = entry.price * qty
            subtotal = subtotal + lineTotal
            billedItems[#billedItems + 1] = {
                item = item.item,
                label = entry.label or item.item,
                qty = qty,
                unitPrice = entry.price,
                lineTotal = lineTotal,
            }
        end
    end

    local taxRate = GetMechanicTaxRate()
    local taxAmount = math.floor(subtotal * taxRate)
    local total = subtotal + taxAmount

    if total <= 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Nothing to charge', 'error')
        return
    end

    local invoice = {
        business = business,
        mechSrc = src,
        mechCid = mech.PlayerData.citizenid,
        customerSrc = customer.PlayerData.source,
        customerCid = customer.PlayerData.citizenid,
        payType = (data.paymentType == 'card') and 'bank' or 'cash',
        items = billedItems,
        subtotal = subtotal,
        tax = taxAmount,
        total = total,
        isChargingSelf = isChargingSelf,
    }

    if isChargingSelf then
        executeCharge(invoice)
        return
    end

    -- Send the bill to the customer and wait for their answer.
    dropExpiredCharges()
    if findPending('customerSrc', invoice.customerSrc) then
        TriggerClientEvent('QBCore:Notify', src, 'That customer already has a bill waiting', 'error')
        return
    end
    if findPending('mechSrc', src) then
        TriggerClientEvent('QBCore:Notify', src, 'Wait for your last bill to be answered', 'error')
        return
    end
    nextInvoiceId = nextInvoiceId + 1
    local invoiceId = ('%d-%d'):format(os.time(), nextInvoiceId)
    invoice.id = invoiceId
    invoice.expiresAt = os.time() + confirmSeconds()
    PendingCharges[invoiceId] = invoice

    local ci = mech.PlayerData.charinfo or {}
    TriggerClientEvent('mechanic:client:confirmCharge', invoice.customerSrc, {
        id = invoiceId,
        shopName = GetBusinessDisplayName(business),
        mechanicName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
        items = billedItems,
        subtotal = subtotal,
        tax = taxAmount,
        total = total,
        paymentType = invoice.payType == 'bank' and 'card' or 'cash',
        expiresIn = confirmSeconds(),
    })
    TriggerClientEvent('QBCore:Notify', src, ('Bill of €%s sent; waiting for the customer to accept'):format(total), 'primary')
end)

-- Event: the customer answers a bill. Only the billed customer can answer, once, before it expires.
RegisterNetEvent('mechanic:server:answerCharge', function(invoiceId, accept)
    local src = source
    local inv = invoiceId and PendingCharges[tostring(invoiceId)] or nil
    if not inv or inv.customerSrc ~= src then return end
    PendingCharges[inv.id] = nil -- single use, whatever the answer

    if os.time() > inv.expiresAt then
        TriggerClientEvent('QBCore:Notify', src, 'That bill has expired', 'error')
        TriggerClientEvent('QBCore:Notify', inv.mechSrc, 'The customer did not answer the bill', 'error')
        return
    end
    if accept ~= true then
        TriggerClientEvent('QBCore:Notify', inv.mechSrc, 'The customer declined the bill', 'error')
        TriggerClientEvent('QBCore:Notify', src, 'Bill declined', 'primary')
        return
    end

    -- the situation may have changed while the customer read the bill
    local mech = QBCore.Functions.GetPlayer(inv.mechSrc)
    local customer = QBCore.Functions.GetPlayer(src)
    if not mech or not customer or mech.PlayerData.citizenid ~= inv.mechCid or customer.PlayerData.citizenid ~= inv.customerCid then
        TriggerClientEvent('QBCore:Notify', src, 'The mechanic is no longer here', 'error')
        return
    end
    local job = mech.PlayerData.job and mech.PlayerData.job.name or nil
    if not job or Config.GetBusinessKey(job) ~= inv.business then
        TriggerClientEvent('QBCore:Notify', src, 'The mechanic can no longer charge for this shop', 'error')
        return
    end
    if posDistance(inv.mechSrc, src) > ((Config.POS and Config.POS.MaxChargeDistance) or 10.0) then
        TriggerClientEvent('QBCore:Notify', src, 'You are too far from the mechanic', 'error')
        TriggerClientEvent('QBCore:Notify', inv.mechSrc, 'Customer not found nearby', 'error')
        return
    end
    executeCharge(inv)
end)

CreateThread(function()
    while true do
        Wait(10000)
        dropExpiredCharges()
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for id, inv in pairs(PendingCharges) do
        if inv.customerSrc == src or inv.mechSrc == src then PendingCharges[id] = nil end
    end
end)

-- ── pf-government business registry ──────────────────────────────────────────
-- Each shop is registered as mechanic:<business> (owned by its job), so government closures, utilities
-- and business tax apply. Registered once per server run, on its first sale.
local govRegistered = {}
local function govStarted() return GetResourceState('pf-government') == 'started' end
local function shopMayTrade(business)
    if not govStarted() then return true end
    if not govRegistered[business] then
        govRegistered[business] = pcall(function()
            exports['pf-government']:RegisterBusinessWithGovernment('mechanic:' .. business, business, 'mechanic', 'job:' .. business, nil)
        end)
    end
    local ok, allowed, why = pcall(function() return exports['pf-government']:CanBusinessTrade('mechanic:' .. business) end)
    if ok and allowed == false then return false, why end
    return true
end

-- Moves the money for an accepted bill and records the sale.
executeCharge = function(inv)
    local src = inv.mechSrc
    local business = inv.business
    local subtotal, taxAmount, total, payType = inv.subtotal, inv.tax, inv.total, inv.payType
    local billedItems = inv.items
    local isChargingSelf = inv.isChargingSelf
    local mech = QBCore.Functions.GetPlayer(inv.mechSrc)
    local customer = QBCore.Functions.GetPlayer(inv.customerSrc)
    if not mech or not customer then return false end

    local mayTrade, why = shopMayTrade(business)
    if not mayTrade then
        local msg = why == 'no_power' and 'The shop has no power' or 'This shop has been closed by the government'
        TriggerClientEvent('QBCore:Notify', src, msg, 'error')
        TriggerClientEvent('QBCore:Notify', customer.PlayerData.source, msg, 'error')
        return false
    end

    local transactionId = 'TX-' .. os.time() .. '-' .. math.random(10000, 99999)
    local keyBase = 'mechpos:' .. transactionId .. ':' .. tostring(GetGameTimer())
    local customerCid = inv.customerCid
    local mechCid = inv.mechCid

    -- 1. The customer pays the full total.
    local charge = posTransfer({
        from = ('player:%s:%s'):format(customerCid, payType), to = POS_ACCOUNT, amount = total,
        key = keyBase .. ':charge', kind = 'purchase', reason = 'Mechanic: ' .. business, actor = mechCid,
        metadata = { business = business, subtotal = subtotal, tax = taxAmount, invoice = inv.id },
    })
    if not charge.ok then
        if charge.error == 'insufficient_funds' then
            TriggerClientEvent('QBCore:Notify', src, 'Customer lacks funds', 'error')
            TriggerClientEvent('QBCore:Notify', customer.PlayerData.source, 'Not enough funds for this payment', 'error')
        else
            TriggerClientEvent('QBCore:Notify', src, 'Payment failed', 'error')
            TriggerClientEvent('QBCore:Notify', customer.PlayerData.source, 'Payment failed', 'error')
        end
        return false
    end

    -- 2. Tax: when forwarded, the treasury gets exactly the tax the customer paid.
    local collectedTax = 0
    if Config.UseGovernmentTax and taxAmount > 0 and GetResourceState('pf-government') == 'started' then
        local ok, value = pcall(function()
            return exports['pf-government']:CollectTaxAmount(taxAmount, 'sales', 'business', business, 'mechanic_pos', keyBase .. ':tax', subtotal)
        end)
        collectedTax = ok and (tonumber(value) or 0) or 0
    end

    -- 3. The shop's bank account receives the rest (the tax too, when it was not forwarded).
    local societyName = business
    local societyAmount = total - collectedTax
    local takings = posTransfer({
        from = POS_ACCOUNT, to = 'society:' .. business, amount = societyAmount,
        key = keyBase .. ':takings', kind = 'sale', reason = 'POS sale', actor = mechCid,
        metadata = { sale = charge.txId },
    })
    if not takings.ok then
        print(('^1[pf-mechanicjob]^7 POS takings %.2f for %s not credited (%s), key %s'):format(societyAmount, business, tostring(takings.error), keyBase .. ':takings'))
    elseif govStarted() then
        -- the sale is recorded once with the government; the business tax comes out of the shop account
        pcall(function() exports['pf-government']:AddBusinessRevenue('mechanic:' .. business, subtotal, keyBase .. ':gov', 'society:' .. business) end)
    end

    -- Sale history for the pf-computer Business Manager (records only; the money moved above)
    if GetResourceState('pf-computer') == 'started' then
        pcall(function()
            exports['pf-computer']:DepositSale(business, societyAmount, 'POS Sale - Amount: $' .. societyAmount)
        end)
    end

    -- 4. Commission for the charging mechanic, paid out of the shop's takings (it used to be created
    --    on top of the sale). None when charging yourself.
    local mechanicCut = 0
    if not isChargingSelf and takings.ok then
        mechanicCut = math.floor(math.min(total * ((Config.POS and Config.POS.CommissionRate) or 0.2), societyAmount))
        if mechanicCut > 0 then
            local cut = posTransfer({
                from = 'society:' .. business, to = ('player:%s:bank'):format(mechCid), amount = mechanicCut,
                key = keyBase .. ':commission', kind = 'wage', reason = 'Mechanic commission', actor = mechCid,
            })
            if not cut.ok then mechanicCut = 0 end
        end
    end

    -- Save transaction to database
    local itemsJson = json.encode(billedItems)

    MySQL.insert.await([[
        INSERT INTO pf_pos_transactions (business, transaction_id, customer_id, mechanic_id, mechanic_name, items, subtotal, tax, total, payment_type, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        business,
        transactionId,
        customerCid,
        mechCid,
        mech.PlayerData.charinfo.firstname .. ' ' .. mech.PlayerData.charinfo.lastname,
        itemsJson,
        subtotal,
        taxAmount,
        total,
        payType,
        'completed'
    })

    -- Mirror into management transactions table for cross-feature stats
    MySQL.insert.await('INSERT INTO pf_mechanic_transactions (business, employee, amount, `timestamp`) VALUES (?, ?, ?, NOW())', {
        business,
        mechCid,
        total
    })

    -- Give customer a receipt item with hoverable metadata + full detail payload
    local receiptItem = ResolveReceiptItemName()
    if receiptItem then
        local mechName = (mech.PlayerData.charinfo.firstname or 'Unknown') .. ' ' .. (mech.PlayerData.charinfo.lastname or '')
        local customerName = (customer.PlayerData.charinfo and (customer.PlayerData.charinfo.firstname .. ' ' .. customer.PlayerData.charinfo.lastname)) or 'Customer'
        local receiptInfo = BuildReceiptMetadata({
            receiptId = transactionId,
            business = business,
            shopName = GetBusinessDisplayName(business),
            chargedBy = mechName,
            customerName = customerName,
            customerCitizenId = customerCid,
            paymentType = payType,
            subtotal = subtotal,
            tax = taxAmount,
            total = total,
            timestamp = os.time(),
            items = billedItems,
        })

        if customer.Functions.AddItem(receiptItem, 1, false, receiptInfo) then
            TriggerClientEvent('inventory:client:ItemBox', customer.PlayerData.source, QBCore.Shared.Items[receiptItem], 'add')
        end
    else
        print('[pf-mechanicjob] No valid receipt item found (expected mech_receipt or Config.ReceiptItems entry)')
    end

    -- Clear cart on client
    TriggerClientEvent('mechanic:client:clearPosCart', src)

    -- Refresh management statistics for all mechanics in this business
    TriggerEvent('pf_mechanic:refreshManagementData', business)

    local cutMsg = isChargingSelf and 'Charged self (no cut)' or ('Charged €%s successfully (cut: €%s)'):format(total, mechanicCut)
    TriggerClientEvent('QBCore:Notify', src, cutMsg, 'success')
    TriggerClientEvent('QBCore:Notify', customer.PlayerData.source, ('Paid €%s to %s'):format(total, societyName), 'success')
    return true
end

-- Callback: fetch transaction history
QBCore.Functions.CreateCallback('mechanic:server:getTransactionHistory', function(source, cb, business, limit)
    local limit_val = tonumber(limit) or 50
    local rows = MySQL.query.await(
        'SELECT * FROM pf_pos_transactions WHERE business = ? ORDER BY created_at DESC LIMIT ?',
        { business, limit_val }
    ) or {}
    
    for _, row in ipairs(rows) do
        if row.items then
            row.items = json.decode(row.items) or {}
        end
    end
    
    cb(rows)
end)

-- Callback: get player name by citizenid or player ID
QBCore.Functions.CreateCallback('mechanic:server:getPlayerName', function(source, cb, customerId)
    local customerId = tostring(customerId)
    
    -- Try to get online player first
    local targetPlayer = QBCore.Functions.GetPlayer(tonumber(customerId))
    if targetPlayer then
        local charInfo = targetPlayer.PlayerData.charinfo
        return cb(charInfo.firstname .. ' ' .. charInfo.lastname)
    end
    
    -- Try citizenid lookup in database
    local result = MySQL.query.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { customerId })
    if result and result[1] then
        local charInfo = json.decode(result[1].charinfo)
        return cb(charInfo.firstname .. ' ' .. charInfo.lastname)
    end
    
    -- Fallback
    return cb('Unknown')
end)

return {
    GetMechanicTaxRate = GetMechanicTaxRate,
    GetBusinessPriceList = GetBusinessPriceList,
}
