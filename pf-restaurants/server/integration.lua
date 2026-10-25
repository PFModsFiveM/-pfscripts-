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

--- Server-only (pf-government): a business transfer by government staff. Whoever held the owner
--- role loses it (and leaves the staff); newCid becomes the owner. newCid nil/'' leaves it ownerless.
exports('SetOwnerFromGovernment', function(businessId, newCid)
    local invoker = GetInvokingResource and GetInvokingResource() or nil
    if invoker and invoker ~= 'pf-government' then return false, 'not_allowed' end
    if type(businessId) ~= 'string' or not RestaurantData.businesses[businessId] then return false, 'unknown_restaurant' end
    if newCid ~= nil and newCid ~= '' then
        if type(newCid) ~= 'string' or not MySQL.scalar.await('SELECT 1 FROM players WHERE citizenid = ? LIMIT 1', { newCid }) then
            return false, 'unknown_citizen'
        end
    end
    RestaurantData.employees[businessId] = RestaurantData.employees[businessId] or {}
    for cid, emp in pairs(RestaurantData.employees[businessId]) do
        if emp.role == 'owner' and cid ~= newCid then
            RestaurantData.employees[businessId][cid] = nil
            MySQL.query.await('DELETE FROM pf_restaurant_employees WHERE business_id = ? AND citizenid = ?', { businessId, cid })
        end
    end
    if newCid ~= nil and newCid ~= '' then
        RestaurantData.employees[businessId][newCid] = { citizenid = newCid, cid = newCid, role = 'owner', hiredDate = os.time(), shifts = 0 }
        MySQL.query.await('INSERT INTO pf_restaurant_employees (business_id, citizenid, role) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE role = VALUES(role)', { businessId, newCid, 'owner' })
    end
    return true
end)

exports('IsEmployeeOf', function(citizenId, businessId)
    if RestaurantData.employees[businessId] and RestaurantData.employees[businessId][citizenId] then
        return true, RestaurantData.employees[businessId][citizenId]
    end
    return false, nil
end)
