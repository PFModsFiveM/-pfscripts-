-- Integration with pf-computer business manager

-- Register callbacks for pf-computer integration
if GetResourceState('pf-computer') == 'started' then
    print('[pf-restaurants] Integrating with pf-computer...')
    
    -- These would be called from pf-computer's business manager UI
    
    -- Get restaurant data for business manager
    exports('GetRestaurantData', function(businessId)
        return {
            business = RestaurantData.businesses[businessId],
            menu = RestaurantData.menus[businessId],
            recipes = RestaurantData.recipes,
            equipment = RestaurantData.equipment[businessId],
            hygiene = RestaurantData.businesses[businessId] and RestaurantData.businesses[businessId].hygiene,
            inventory = RestaurantData.inventory[businessId],
            employees = RestaurantData.employees[businessId]
        }
    end)
    
    -- Get menu for business manager
    exports('GetMenu', function(businessId)
        return RestaurantData.menus[businessId] or {}
    end)
    
    -- Get recipes for business manager
    exports('GetRecipes', function(businessId)
        local recipes = {}
        
        -- Include config recipes
        for recipeId, recipe in pairs(Config.Recipes) do
            recipes[recipeId] = recipe
        end
        
        -- Include custom recipes
        for recipeId, recipe in pairs(RestaurantData.recipes) do
            if recipe.businessId == businessId or not recipe.businessId then
                recipes[recipeId] = recipe
            end
        end
        
        return recipes
    end)
    
    -- Get analytics for business manager
    exports('GetAnalytics', function(businessId, timeRange)
        -- Reuse analytics callback logic
        local sales = {
            totalRevenue = 0,
            totalOrders = 0,
            topItems = {}
        }
        
        local now = os.time()
        local startTime = now - 86400 -- Default 24h
        
        if timeRange == 'week' then
            startTime = now - 604800
        elseif timeRange == 'month' then
            startTime = now - 2592000
        end
        
        for orderId, order in pairs(RestaurantData.orders) do
            if order.businessId == businessId and order.placedAt >= startTime and order.status == 'completed' then
                sales.totalRevenue = sales.totalRevenue + order.total
                sales.totalOrders = sales.totalOrders + 1
            end
        end
        
        return sales
    end)
    
    -- Permission check for business manager
    exports('HasRestaurantPermission', function(source, businessId, permission)
        return HasPermission(source, businessId, permission)
    end)
else
    print('[pf-restaurants] pf-computer not found, integration disabled')
end

-- Inventory integration (qb-inventory or ox_inventory)
if Config.Inventory == 'qb-inventory' then
    -- QB Inventory hooks
    
    -- When consuming a food item
    QBCore.Functions.CreateUseableItem('burger_classic', function(source, item)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        
        local metadata = item.info or {}
        local hunger = metadata.hunger or 45
        local poisonRisk = metadata.poisonRisk or 0
        
        -- Remove item
        Player.Functions.RemoveItem('burger_classic', 1)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items['burger_classic'], 'remove', 1)
        
        -- Apply effects
        TriggerClientEvent('pf-restaurants:client:consumeFood', source, hunger, 0, poisonRisk)
        
        -- Notify
        NotifyPlayer(source, 'You ate a burger', 'success')
    end)
    
    -- Similar for other consumable items - would be auto-generated from Config.Items
end

-- Export core functions for other resources
exports('GetBusinessData', function(businessId)
    return RestaurantData.businesses[businessId]
end)

exports('GetOrders', function(businessId)
    local orders = {}
    for orderId, order in pairs(RestaurantData.orders) do
        if order.businessId == businessId then
            table.insert(orders, order)
        end
    end
    return orders
end)

exports('IsEmployeeOf', function(citizenId, businessId)
    if RestaurantData.employees[businessId] and RestaurantData.employees[businessId][citizenId] then
        return true, RestaurantData.employees[businessId][citizenId]
    end
    return false, nil
end)
