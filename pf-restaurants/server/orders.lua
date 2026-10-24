-- Order management (POS/KDS)

local orderIdCounter = 1000

-- Create new order from POS
RegisterNetEvent('pf-restaurants:server:createOrder', function(businessId, orderData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'pos.use') then
        NotifyPlayer(src, 'No permission to create orders', 'error')
        return
    end

    local subtotal = tonumber(orderData.subtotal) or 0
    if subtotal <= 0 then
        NotifyPlayer(src, 'Invalid order subtotal', 'error')
        return
    end

    local taxRate = Config.Orders.TaxRate or 0.0
    if GetResourceState('pf-government') == 'started' then
        local ok, rate = pcall(function()
            return exports['pf-government']:GetSalesTaxRate()
        end)
        if ok and type(rate) == 'number' then
            taxRate = rate
        end
    end
    local calculatedTax = subtotal * taxRate
    local tax = math.max(1, math.ceil(calculatedTax))
    local total = subtotal + tax
    
    orderIdCounter = orderIdCounter + 1
    local orderId = 'ORD-' .. businessId .. '-' .. orderIdCounter
    
    local order = {
        orderId = orderId,
        businessId = businessId,
        customerCid = orderData.customerCid or Player.PlayerData.citizenid,
        cashierCid = Player.PlayerData.citizenid,
        items = orderData.items or {}, -- {recipeId, qty, mods}
        status = 'placed',
        channel = orderData.channel or 'dine-in',
        subtotal = subtotal,
        tax = tax,
        total = total,
        paymentMethod = orderData.paymentMethod or 'cash',
        placedAt = os.time(),
        statusHistory = {
            {status = 'placed', timestamp = os.time()}
        }
    }
    
    RestaurantData.orders[orderId] = order
    
    -- Process payment
    if orderData.paymentMethod == 'cash' then
        local canPay = Player.Functions.RemoveMoney('cash', order.total, 'restaurant-order')
        if not canPay then
            NotifyPlayer(src, 'Insufficient cash', 'error')
            RestaurantData.orders[orderId] = nil
            return
        end
    elseif orderData.paymentMethod == 'card' then
        local canPay = Player.Functions.RemoveMoney('bank', order.total, 'restaurant-order')
        if not canPay then
            NotifyPlayer(src, 'Insufficient funds', 'error')
            RestaurantData.orders[orderId] = nil
            return
        end
    end

    if tax > 0 and GetResourceState('pf-government') == 'started' then
        pcall(function()
            exports['pf-government']:CollectTax(subtotal, 'sales', 'business', businessId, 'restaurant_pos')
        end)
    end

    TriggerEvent('pf-restaurants:server:addRevenue', businessId, subtotal)
    
    -- Broadcast to KDS
    TriggerClientEvent('pf-restaurants:client:newOrder', -1, businessId, order)
    
    NotifyPlayer(src, 'Order #' .. orderIdCounter .. ' created', 'success')
    
    -- Update employee stats
    local cashierCid = Player.PlayerData.citizenid
    if RestaurantData.employees[businessId] and RestaurantData.employees[businessId][cashierCid] then
        RestaurantData.employees[businessId][cashierCid].orders = (RestaurantData.employees[businessId][cashierCid].orders or 0) + 1
    end
    
    -- Add to business dirt (each order adds dirt)
    if RestaurantData.businesses[businessId] then
        RestaurantData.businesses[businessId].hygiene.dirtLevel = RestaurantData.businesses[businessId].hygiene.dirtLevel + Config.Hygiene.DirtPerOrder
    end
end)

-- Update order status
RegisterNetEvent('pf-restaurants:server:updateOrderStatus', function(orderId, newStatus)
    local src = source
    
    local order = RestaurantData.orders[orderId]
    if not order then
        NotifyPlayer(src, 'Order not found', 'error')
        return
    end
    
    if not HasPermission(src, order.businessId, 'kds.use') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    order.status = newStatus
    table.insert(order.statusHistory, {
        status = newStatus,
        timestamp = os.time()
    })
    
    if newStatus == 'ready' then
        order.readyAt = os.time()
    elseif newStatus == 'completed' then
        order.completedAt = os.time()
    end
    
    TriggerClientEvent('pf-restaurants:client:orderStatusUpdate', -1, orderId, newStatus)
end)

-- Void order (manager only)
RegisterNetEvent('pf-restaurants:server:voidOrder', function(orderId, reason)
    local src = source
    
    local order = RestaurantData.orders[orderId]
    if not order then
        NotifyPlayer(src, 'Order not found', 'error')
        return
    end
    
    if not HasPermission(src, order.businessId, 'orders.void') then
        NotifyPlayer(src, 'No permission to void orders', 'error')
        return
    end
    
    order.status = 'cancelled'
    order.voidReason = reason
    order.voidedBy = GetPlayerIdentifier(src, 0)
    order.voidedAt = os.time()
    
    LogAction('order_void', {
        orderId = orderId,
        businessId = order.businessId,
        reason = reason,
        by = GetPlayerIdentifier(src, 0)
    })
    
    NotifyPlayer(src, 'Order voided', 'success')
    TriggerClientEvent('pf-restaurants:client:orderStatusUpdate', -1, orderId, 'cancelled')
end)

-- Refund order
RegisterNetEvent('pf-restaurants:server:refundOrder', function(orderId, reason)
    local src = source
    
    local order = RestaurantData.orders[orderId]
    if not order then
        NotifyPlayer(src, 'Order not found', 'error')
        return
    end
    
    if not HasPermission(src, order.businessId, 'orders.refund') then
        NotifyPlayer(src, 'No permission to refund orders', 'error')
        return
    end
    
    -- Find customer and refund
    local Customer = QBCore.Functions.GetPlayerByCitizenId(order.customerCid)
    if Customer then
        if order.paymentMethod == 'cash' then
            Customer.Functions.AddMoney('cash', order.total, 'restaurant-refund')
        elseif order.paymentMethod == 'card' then
            Customer.Functions.AddMoney('bank', order.total, 'restaurant-refund')
        end
        
        local customerSrc = Customer.PlayerData.source
        NotifyPlayer(customerSrc, 'Order refunded: $' .. order.total, 'success')
    end
    
    order.status = 'refunded'
    order.refundReason = reason
    order.refundedBy = GetPlayerIdentifier(src, 0)
    order.refundedAt = os.time()
    
    LogAction('order_refund', {
        orderId = orderId,
        businessId = order.businessId,
        amount = order.total,
        reason = reason,
        by = GetPlayerIdentifier(src, 0)
    })
    
    NotifyPlayer(src, 'Order refunded', 'success')
    TriggerClientEvent('pf-restaurants:client:orderStatusUpdate', -1, orderId, 'refunded')
end)

-- Comp order (free)
RegisterNetEvent('pf-restaurants:server:compOrder', function(orderId, reason)
    local src = source
    
    local order = RestaurantData.orders[orderId]
    if not order then
        NotifyPlayer(src, 'Order not found', 'error')
        return
    end
    
    if not HasPermission(src, order.businessId, 'orders.comp') then
        NotifyPlayer(src, 'No permission to comp orders', 'error')
        return
    end
    
    order.comped = true
    order.compReason = reason
    order.compedBy = GetPlayerIdentifier(src, 0)
    
    LogAction('order_comp', {
        orderId = orderId,
        businessId = order.businessId,
        amount = order.total,
        reason = reason,
        by = GetPlayerIdentifier(src, 0)
    })
    
    NotifyPlayer(src, 'Order comped', 'success')
end)

-- Get active orders for KDS
QBCore.Functions.CreateCallback('pf-restaurants:server:getActiveOrders', function(source, cb, businessId)
    local orders = {}
    
    for orderId, order in pairs(RestaurantData.orders) do
        if order.businessId == businessId and order.status ~= 'completed' and order.status ~= 'cancelled' and order.status ~= 'refunded' then
            table.insert(orders, order)
        end
    end
    
    -- Sort by time
    table.sort(orders, function(a, b)
        return a.placedAt < b.placedAt
    end)
    
    cb(orders)
end)

-- Get order history
QBCore.Functions.CreateCallback('pf-restaurants:server:getOrderHistory', function(source, cb, businessId, filters)
    if not HasPermission(source, businessId, 'analytics.view') then
        cb(nil)
        return
    end
    
    local orders = {}
    
    for orderId, order in pairs(RestaurantData.orders) do
        if order.businessId == businessId then
            table.insert(orders, order)
        end
    end
    
    -- Sort by time (newest first)
    table.sort(orders, function(a, b)
        return a.placedAt > b.placedAt
    end)
    
    cb(orders)
end)
