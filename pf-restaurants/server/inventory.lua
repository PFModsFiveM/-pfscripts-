-- Inventory and supply management

-- Get business inventory
QBCore.Functions.CreateCallback('pf-restaurants:server:getInventory', function(source, cb, businessId)
    if not RestaurantData.inventory[businessId] then
        RestaurantData.inventory[businessId] = {
            dry = {},
            fridge = {},
            freezer = {}
        }
    end
    
    cb(RestaurantData.inventory[businessId])
end)

-- Add inventory lot (from supply delivery)
RegisterNetEvent('pf-restaurants:server:addInventoryLot', function(businessId, storageType, item, quantity, expiryHours)
    local src = source
    
    if not HasPermission(src, businessId, 'supplies.order') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    if not RestaurantData.inventory[businessId] then
        RestaurantData.inventory[businessId] = {dry = {}, fridge = {}, freezer = {}}
    end
    
    local itemConfig = Config.Items[item]
    if not itemConfig then
        NotifyPlayer(src, 'Invalid item', 'error')
        return
    end
    
    -- Determine expiry
    local hoursUntilExpiry = expiryHours or Config.Spoilage.StorageTypes[storageType] or 168
    local expiryTimestamp = os.time() + (hoursUntilExpiry * 3600)
    
    local lot = {
        lotId = 'lot_' .. os.time() .. '_' .. math.random(1000, 9999),
        item = item,
        quantity = quantity,
        expiryTimestamp = expiryTimestamp,
        quality = 100,
        addedAt = os.time()
    }
    
    table.insert(RestaurantData.inventory[businessId][storageType], lot)
    
    NotifyPlayer(src, 'Added ' .. quantity .. 'x ' .. item .. ' to ' .. storageType, 'success')
    TriggerClientEvent('pf-restaurants:client:inventoryUpdate', -1, businessId, RestaurantData.inventory[businessId])
end)

-- Consume inventory (when using items from storage)
function ConsumeInventory(businessId, item, quantity, preferFreshest)
    if not RestaurantData.inventory[businessId] then
        return false, 'No inventory data'
    end
    
    local itemConfig = Config.Items[item]
    if not itemConfig then
        return false, 'Invalid item'
    end
    
    local storageType = itemConfig.storage or 'dry'
    local storage = RestaurantData.inventory[businessId][storageType]
    
    -- Find lots with this item
    local lots = {}
    for _, lot in ipairs(storage) do
        if lot.item == item and lot.quantity > 0 then
            table.insert(lots, lot)
        end
    end
    
    -- Sort by expiry (use oldest first, or freshest if preferred)
    table.sort(lots, function(a, b)
        if preferFreshest then
            return a.expiryTimestamp > b.expiryTimestamp
        else
            return a.expiryTimestamp < b.expiryTimestamp
        end
    end)
    
    -- Consume from lots
    local remaining = quantity
    local consumedLots = {}
    
    for _, lot in ipairs(lots) do
        if remaining <= 0 then break end
        
        -- Check if expired
        if lot.expiryTimestamp < os.time() and not Config.Spoilage.AllowExpiredUse then
            -- Skip expired lot
        else
            local toConsume = math.min(lot.quantity, remaining)
            lot.quantity = lot.quantity - toConsume
            remaining = remaining - toConsume
            
            table.insert(consumedLots, {
                lotId = lot.lotId,
                qty = toConsume,
                quality = lot.quality,
                expired = lot.expiryTimestamp < os.time()
            })
        end
    end
    
    if remaining > 0 then
        return false, 'Insufficient inventory'
    end
    
    return true, consumedLots
end

exports('ConsumeInventory', ConsumeInventory)

-- Spoilage check loop
CreateThread(function()
    while true do
        Wait(Config.Timings.SpoilageCheckInterval)
        
        for businessId, inventory in pairs(RestaurantData.inventory) do
            for storageType, storage in pairs(inventory) do
                for i = #storage, 1, -1 do
                    local lot = storage[i]
                    
                    -- Check expiry
                    if lot.expiryTimestamp < os.time() then
                        -- Expired
                        if Config.Spoilage.AllowExpiredUse then
                            lot.quality = 0
                        else
                            -- Remove lot
                            table.remove(storage, i)
                            print(string.format('[pf-restaurants] Lot %s expired and removed from %s', lot.lotId, businessId))
                        end
                    else
                        -- Degrade quality over time
                        local timeToExpiry = lot.expiryTimestamp - os.time()
                        local totalTime = (lot.expiryTimestamp - lot.addedAt)
                        local freshness = timeToExpiry / totalTime
                        lot.quality = math.floor(freshness * 100)
                    end
                end
            end
        end
    end
end)

-- Order supplies (placeholder for delivery system)
RegisterNetEvent('pf-restaurants:server:orderSupplies', function(businessId, supplyOrder)
    local src = source
    
    if not HasPermission(src, businessId, 'supplies.order') then
        NotifyPlayer(src, 'No permission to order supplies', 'error')
        return
    end
    
    -- Calculate cost
    local subtotal = 0
    for _, item in ipairs(supplyOrder.items) do
        -- Placeholder pricing - could come from config
        local itemCost = item.quantity * 5
        subtotal = subtotal + itemCost
    end

    local taxAmount = 0
    if subtotal > 0 and GetResourceState('pf-government') == 'started' then
        local okTax, calcTax = pcall(function()
            return exports['pf-government']:CalculateTax(subtotal, 'supplies')
        end)
        if okTax then
            taxAmount = tonumber(calcTax) or 0
        end
    end

    local totalCost = math.floor(((subtotal + taxAmount) * 100) + 0.5) / 100
    
    -- Charge business account (placeholder - would integrate with business banking)
    -- For now, charge the player
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local canPay = Player.Functions.RemoveMoney('bank', totalCost, 'restaurant-supplies')
    if not canPay then
        NotifyPlayer(src, ('Insufficient funds. Subtotal: $%.2f | Tax: $%.2f | Total: $%.2f'):format(subtotal, taxAmount, totalCost), 'error')
        return
    end

    if taxAmount > 0 and GetResourceState('pf-government') == 'started' then
        pcall(function()
            exports['pf-government']:CollectTax(subtotal, 'supplies', 'business', businessId, 'restaurant_supplies')
        end)
    end
    
    -- Deliver supplies after delay
    local deliveryTime = supplyOrder.deliveryTime or 60000 -- 1 minute default
    
    NotifyPlayer(src, ('Supplies ordered. Subtotal: $%.2f | Tax: $%.2f | Total: $%.2f | Delivery in %d minutes'):format(
        subtotal,
        taxAmount,
        totalCost,
        math.floor(deliveryTime / 60000)
    ), 'success')
    
    SetTimeout(deliveryTime, function()
        -- Add supplies to inventory
        for _, item in ipairs(supplyOrder.items) do
            local itemConfig = Config.Items[item.item]
            local storageType = itemConfig and itemConfig.storage or 'dry'
            local category = itemConfig and itemConfig.category or 'dry_goods'
            
            local categoryConfig = Config.Spoilage.ItemCategories[category]
            local expiryHours = categoryConfig and categoryConfig.hoursUntilExpiry or Config.Spoilage.StorageTypes[storageType]
            
            -- Add lot
            if not RestaurantData.inventory[businessId] then
                RestaurantData.inventory[businessId] = {dry = {}, fridge = {}, freezer = {}}
            end
            
            local lot = {
                lotId = 'lot_' .. os.time() .. '_' .. math.random(1000, 9999),
                item = item.item,
                quantity = item.quantity,
                expiryTimestamp = os.time() + (expiryHours * 3600),
                quality = 100,
                addedAt = os.time()
            }
            
            table.insert(RestaurantData.inventory[businessId][storageType], lot)
        end
        
        -- Notify player if online
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            NotifyPlayer(src, 'Supply delivery arrived!', 'success')
        end
        
        TriggerClientEvent('pf-restaurants:client:inventoryUpdate', -1, businessId, RestaurantData.inventory[businessId])
    end)
end)
