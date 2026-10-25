-- Restaurant orders (POS and kitchen display).
--
-- The server prices every order from its own menu (the POS only says which menu items and how many),
-- checks the cashier is at a register and the paying customer is next to them, and asks the customer
-- to accept the bill on their own screen (charging yourself needs no prompt). Money moves through the
-- pfm-banking ledger with keys per order: the customer pays system:pf-restaurants, the sales tax goes
-- to the government (pf-government CollectTaxAmount) and the rest to the restaurant's bank account,
-- society:restaurant_<id>. A void or refund pays the customer back once, from that account.
--
-- (The old version took the subtotal from the client, charged the cashier, paid no one, refunded by
-- creating money for any citizen id the client named, and allowed any status change at any time.)
--
-- Statuses: pending_payment -> placed -> preparing -> ready -> completed
--           pending_payment -> declined | expired;  placed | preparing -> cancelled (voided, refunded)
--           completed -> refunded

local SALES = 'system:pf-restaurants'
local TRANSITIONS = {
    placed = { preparing = true, cancelled = true },
    preparing = { ready = true, cancelled = true },
    ready = { completed = true },
    completed = { refunded = true },
}
local Pending = {} -- [orderId] = order waiting for the customer's answer

local function round2(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end

local function ledger(opts)
    if GetResourceState('pfm-banking') ~= 'started' then return { ok = false, error = 'bank_unavailable' } end
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

local function revenueAccount(businessId) return 'society:restaurant_' .. businessId end

local function salesTaxRate()
    if GetResourceState('pf-government') ~= 'started' then return tonumber(Config.Orders.TaxRate) or 0 end
    local ok, rate = pcall(function() return exports['pf-government']:GetSalesTaxRate() end)
    return (ok and tonumber(rate)) or tonumber(Config.Orders.TaxRate) or 0
end

local function distance(a, b)
    return #(GetEntityCoords(GetPlayerPed(a)) - GetEntityCoords(GetPlayerPed(b)))
end

local function atRegister(src, businessId)
    local range = (Config.POS and Config.POS.RegisterRange) or 3.0
    local pos = GetEntityCoords(GetPlayerPed(src))
    for _, reg in ipairs((Config.Registers or {})[businessId] or {}) do
        if #(pos - reg.coords) <= range then return true end
    end
    return false
end

local orderCounter = 0
local function newOrderId(businessId)
    orderCounter = orderCounter + 1
    return ('R%d%03d'):format(os.time(), orderCounter % 1000)
end

-- prices the cart from the restaurant's menu; nil + reason when anything is off
local function priceOrder(businessId, items)
    local menu = RestaurantData.menus[businessId] or {}
    local maxLines = (Config.POS and Config.POS.MaxLines) or 30
    local maxQty = (Config.POS and Config.POS.MaxQtyPerLine) or 20
    if type(items) ~= 'table' or #items == 0 or #items > maxLines then return nil, 'invalid_items' end
    local lines, subtotal = {}, 0
    for _, it in ipairs(items) do
        local entry = type(it) == 'table' and menu[it.menuItemId] or nil
        local qty = type(it) == 'table' and tonumber(it.qty) or nil
        if not entry or entry.enabled == false then return nil, 'item_unavailable' end
        if not qty or qty ~= math.floor(qty) or qty < 1 or qty > maxQty then return nil, 'invalid_quantity' end
        local price = round2(entry.price)
        lines[#lines + 1] = { menuItemId = entry.menuItemId, recipeId = entry.recipeId, name = entry.displayName, qty = qty, price = price }
        subtotal = subtotal + price * qty
    end
    return lines, round2(subtotal)
end

--- Charges the customer and pays tax and revenue. Every step has a fixed key, so a retry pays once.
local function settlePayment(order)
    local key = 'restaurant:' .. order.orderId
    local account = order.paymentMethod == 'card' and 'bank' or 'cash'
    local charge = ledger({
        from = ('player:%s:%s'):format(order.customerCid, account), to = SALES, amount = order.total,
        key = key .. ':charge', kind = 'purchase', reason = 'Restaurant order ' .. order.orderId, actor = order.cashierCid,
    })
    if not charge.ok then return false, charge.error == 'insufficient_funds' and 'insufficient_funds' or 'payment_failed' end

    local collectedTax = 0
    if order.tax > 0 and GetResourceState('pf-government') == 'started' then
        local ok, value = pcall(function()
            return exports['pf-government']:CollectTaxAmount(order.tax, 'sales', 'citizen', order.customerCid, 'restaurant:' .. order.businessId, key .. ':tax', order.subtotal)
        end)
        collectedTax = ok and round2(tonumber(value) or 0) or 0
    end
    -- tax the government did not take goes back to the customer
    local uncollected = round2(order.tax - collectedTax)
    if uncollected > 0 then
        ledger({ from = SALES, to = ('player:%s:%s'):format(order.customerCid, account), amount = uncollected, key = key .. ':tax-refund', kind = 'refund', reason = 'Uncollected sales tax' })
    end
    pcall(function() exports['pfm-banking']:EnsureSocietyAccount('restaurant_' .. order.businessId, 'business') end)
    local revenue = ledger({ from = SALES, to = revenueAccount(order.businessId), amount = order.subtotal, key = key .. ':revenue', kind = 'sale', reason = 'Restaurant sales' })
    if not revenue.ok then print(('^1[pf-restaurants]^7 revenue of %s not credited (%s)'):format(order.orderId, tostring(revenue.error))) end
    order.paidTax = collectedTax
    return true
end

local function placeOrder(order, src)
    local ok, err = settlePayment(order)
    if not ok then
        RestaurantDB.TransitionOrder(order, 'pending_payment', 'declined')
        RestaurantData.orders[order.orderId] = nil
        NotifyPlayer(src, 'Payment failed: ' .. tostring(err), 'error')
        return false
    end
    RestaurantDB.TransitionOrder(order, 'pending_payment', 'placed')
    order.placedAt = os.time()
    RestaurantData.orders[order.orderId] = order
    -- pf-government records the sale once per order and takes the business tax from the restaurant account
    TriggerEvent('pf-restaurants:server:addRevenue', order.businessId, order.subtotal, 'restaurant:' .. order.orderId)
    TriggerClientEvent('pf-restaurants:client:newOrder', -1, order.businessId, order)
    local business = RestaurantData.businesses[order.businessId]
    if business then business.hygiene.dirtLevel = business.hygiene.dirtLevel + Config.Hygiene.DirtPerOrder end
    return true
end

-- Create new order from POS
RegisterNetEvent('pf-restaurants:server:createOrder', function(businessId, orderData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(businessId) ~= 'string' or type(orderData) ~= 'table' then return end
    if not HasPermission(src, businessId, 'pos.use') then
        NotifyPlayer(src, 'No permission to create orders', 'error')
        return
    end
    if not atRegister(src, businessId) then
        NotifyPlayer(src, 'Use a register', 'error')
        return
    end
    -- closed by the government or without power: no sales
    if GetResourceState('pf-government') == 'started' then
        local okG, allowed, why = pcall(function() return exports['pf-government']:CanBusinessTrade('restaurant:' .. businessId) end)
        if okG and allowed == false then
            NotifyPlayer(src, why == 'no_power' and 'The power is off: pay the utility bill' or 'This business has been closed by the government', 'error')
            return
        end
    end
    local lines, subtotal = priceOrder(businessId, orderData.items)
    if not lines then
        NotifyPlayer(src, 'Order refused: ' .. tostring(subtotal), 'error')
        return
    end
    if subtotal <= 0 then
        NotifyPlayer(src, 'Nothing to charge', 'error')
        return
    end
    local method = orderData.paymentMethod
    if method ~= 'cash' and method ~= 'card' then
        NotifyPlayer(src, 'Choose cash or card', 'error')
        return
    end
    local channel = orderData.channel
    local validChannel = false
    for _, c in ipairs(Config.Orders.Channels or {}) do if c == channel then validChannel = true end end
    if not validChannel then channel = 'dine-in' end

    -- the customer is a player next to the cashier (or the cashier); never a citizen id from the client
    local customerSrc = tonumber(orderData.customerId) or src
    local Customer = QBCore.Functions.GetPlayer(customerSrc)
    if not Customer then
        NotifyPlayer(src, 'Customer not found', 'error')
        return
    end
    if customerSrc ~= src and distance(src, customerSrc) > ((Config.POS and Config.POS.CustomerRange) or 10.0) then
        NotifyPlayer(src, 'The customer is not here', 'error')
        return
    end

    local tax = round2(subtotal * salesTaxRate())
    local order = {
        orderId = newOrderId(businessId),
        businessId = businessId,
        customerCid = Customer.PlayerData.citizenid,
        customerSrc = customerSrc,
        cashierCid = Player.PlayerData.citizenid,
        cashierSrc = src,
        items = lines,
        status = 'pending_payment',
        channel = channel,
        subtotal = subtotal,
        tax = tax,
        total = round2(subtotal + tax),
        paymentMethod = method,
        createdAt = os.time(),
        statusHistory = { { status = 'pending_payment', timestamp = os.time() } },
    }
    RestaurantDB.InsertOrder(order)

    if customerSrc == src then
        if placeOrder(order, src) then NotifyPlayer(src, 'Order ' .. order.orderId .. ' placed', 'success') end
        return
    end
    order.expiresAt = os.time() + ((Config.POS and Config.POS.ConfirmSeconds) or 60)
    Pending[order.orderId] = order
    TriggerClientEvent('pf-restaurants:client:confirmPayment', customerSrc, {
        orderId = order.orderId, restaurant = (Config.Restaurants[businessId] or {}).label, items = lines,
        subtotal = order.subtotal, tax = order.tax, total = order.total, paymentMethod = method,
        expiresIn = order.expiresAt - os.time(),
    })
    NotifyPlayer(src, ('Bill of $%.2f sent to the customer'):format(order.total), 'primary')
end)

-- The customer accepts or declines the bill; only they can, once, before it expires, still nearby
RegisterNetEvent('pf-restaurants:server:answerPayment', function(orderId, accept)
    local src = source
    local order = type(orderId) == 'string' and Pending[orderId] or nil
    if not order or order.customerSrc ~= src then return end
    Pending[orderId] = nil
    if os.time() > order.expiresAt then
        RestaurantDB.TransitionOrder(order, 'pending_payment', 'expired')
        NotifyPlayer(src, 'That bill has expired', 'error')
        return
    end
    if accept ~= true then
        RestaurantDB.TransitionOrder(order, 'pending_payment', 'declined')
        NotifyPlayer(order.cashierSrc, 'The customer declined the bill', 'error')
        return
    end
    if distance(order.cashierSrc, src) > ((Config.POS and Config.POS.CustomerRange) or 10.0) then
        RestaurantDB.TransitionOrder(order, 'pending_payment', 'declined')
        NotifyPlayer(src, 'You are too far from the register', 'error')
        return
    end
    if placeOrder(order, src) then
        NotifyPlayer(src, ('Paid $%.2f'):format(order.total), 'success')
        NotifyPlayer(order.cashierSrc, 'Order ' .. order.orderId .. ' paid', 'success')
    end
end)

CreateThread(function()
    while true do
        Wait(10000)
        for id, order in pairs(Pending) do
            if os.time() > order.expiresAt then
                Pending[id] = nil
                RestaurantDB.TransitionOrder(order, 'pending_payment', 'expired')
            end
        end
    end
end)

local function findOrder(orderId)
    if type(orderId) ~= 'string' then return nil end
    local order = RestaurantData.orders[orderId]
    if order then return order end
    local data = MySQL.scalar.await('SELECT data FROM pf_restaurant_orders WHERE order_id = ?', { orderId })
    local ok, decoded = pcall(json.decode, data or '')
    return ok and type(decoded) == 'table' and decoded or nil
end

--- Gives the customer their money back from the restaurant's account, once per order.
local function refundCustomer(order, reason)
    local account = order.paymentMethod == 'card' and 'bank' or 'cash'
    local res = ledger({
        from = revenueAccount(order.businessId), to = ('player:%s:%s'):format(order.customerCid, account),
        amount = order.total, key = 'restaurant:' .. order.orderId .. ':refund', kind = 'refund', reason = reason or 'Restaurant refund',
    })
    return res.ok, res.error
end

-- Kitchen display status changes, only along the allowed path
RegisterNetEvent('pf-restaurants:server:updateOrderStatus', function(orderId, newStatus)
    local src = source
    local order = findOrder(orderId)
    if not order then return NotifyPlayer(src, 'Order not found', 'error') end
    if not HasPermission(src, order.businessId, 'kds.use') then return NotifyPlayer(src, 'No permission', 'error') end
    if newStatus == 'cancelled' or newStatus == 'refunded' or not (TRANSITIONS[order.status] or {})[newStatus] then
        return NotifyPlayer(src, 'That status change is not allowed', 'error')
    end
    if not RestaurantDB.TransitionOrder(order, order.status, newStatus) then return end
    if newStatus == 'ready' then order.readyAt = os.time() end
    if newStatus == 'completed' then
        order.completedAt = os.time()
        RestaurantData.orders[order.orderId] = nil
    end
    TriggerClientEvent('pf-restaurants:client:orderStatusUpdate', -1, order.orderId, newStatus)
end)

-- Void an order not served yet: the customer is refunded
RegisterNetEvent('pf-restaurants:server:voidOrder', function(orderId, reason)
    local src = source
    local order = findOrder(orderId)
    if not order then return NotifyPlayer(src, 'Order not found', 'error') end
    if not HasPermission(src, order.businessId, 'orders.void') then return NotifyPlayer(src, 'No permission to void orders', 'error') end
    local from = order.status
    if not (TRANSITIONS[from] or {}).cancelled or not RestaurantDB.TransitionOrder(order, from, 'cancelled') then
        return NotifyPlayer(src, 'This order cannot be voided', 'error')
    end
    local ok, err = refundCustomer(order, 'Order voided')
    if not ok then print(('^1[pf-restaurants]^7 refund of voided %s failed (%s)'):format(order.orderId, tostring(err))) end
    RestaurantData.orders[order.orderId] = nil
    LogAction('order_void', { orderId = order.orderId, businessId = order.businessId, reason = reason })
    NotifyPlayer(src, 'Order voided', 'success')
    TriggerClientEvent('pf-restaurants:client:orderStatusUpdate', -1, order.orderId, 'cancelled')
end)

-- Refund a completed order, once
RegisterNetEvent('pf-restaurants:server:refundOrder', function(orderId, reason)
    local src = source
    local order = findOrder(orderId)
    if not order then return NotifyPlayer(src, 'Order not found', 'error') end
    if not HasPermission(src, order.businessId, 'orders.refund') then return NotifyPlayer(src, 'No permission to refund orders', 'error') end
    if not RestaurantDB.TransitionOrder(order, 'completed', 'refunded') then
        return NotifyPlayer(src, 'Only a completed order can be refunded, once', 'error')
    end
    local ok, err = refundCustomer(order, 'Order refunded')
    if not ok then
        RestaurantDB.TransitionOrder(order, 'refunded', 'completed')
        return NotifyPlayer(src, 'Refund failed: ' .. tostring(err), 'error')
    end
    LogAction('order_refund', { orderId = order.orderId, businessId = order.businessId, amount = order.total, reason = reason })
    NotifyPlayer(src, 'Order refunded', 'success')
    TriggerClientEvent('pf-restaurants:client:orderStatusUpdate', -1, order.orderId, 'refunded')
end)

-- Comp (mark as on the house in the records; no money moves)
RegisterNetEvent('pf-restaurants:server:compOrder', function(orderId, reason)
    local src = source
    local order = findOrder(orderId)
    if not order then return NotifyPlayer(src, 'Order not found', 'error') end
    if not HasPermission(src, order.businessId, 'orders.comp') then return NotifyPlayer(src, 'No permission to comp orders', 'error') end
    order.comped = true
    order.compReason = type(reason) == 'string' and reason:sub(1, 100) or nil
    MySQL.update.await('UPDATE pf_restaurant_orders SET data = ? WHERE order_id = ?', { json.encode(order), order.orderId })
    NotifyPlayer(src, 'Order comped', 'success')
end)

-- Get active orders for KDS (staff only)
QBCore.Functions.CreateCallback('pf-restaurants:server:getActiveOrders', function(source, cb, businessId)
    if type(businessId) ~= 'string' or not RoleOf(source, businessId) then cb({}) return end
    local orders = {}
    for _, order in pairs(RestaurantData.orders) do
        if order.businessId == businessId and (order.status == 'placed' or order.status == 'preparing' or order.status == 'ready') then
            orders[#orders + 1] = order
        end
    end
    table.sort(orders, function(a, b) return (a.placedAt or 0) < (b.placedAt or 0) end)
    cb(orders)
end)

-- Get order history
QBCore.Functions.CreateCallback('pf-restaurants:server:getOrderHistory', function(source, cb, businessId)
    if type(businessId) ~= 'string' or not HasPermission(source, businessId, 'analytics.view') then
        cb(nil)
        return
    end
    local orders = {}
    for _, row in ipairs(MySQL.query.await('SELECT data FROM pf_restaurant_orders WHERE business_id = ? ORDER BY placed_at DESC LIMIT 200', { businessId }) or {}) do
        local ok, order = pcall(json.decode, row.data)
        if ok and type(order) == 'table' then orders[#orders + 1] = order end
    end
    cb(orders)
end)

exports('GetRestaurantOrder', findOrder)
