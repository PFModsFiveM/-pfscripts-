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

-- Eating and drinking what the restaurants make. Every consumable dish and drink in Config.Items is
-- registered with pfm-smallresources' consumables, which remove the item on the server and grant
-- hunger or thirst only after that (scaled by the dish's freshness, its cooked quality, and its
-- poison risk from undercooked parts). The old handler covered one burger and relieved stress
-- instead of hunger.
local function registerConsumables()
    if GetResourceState('pfm-smallresources') ~= 'started' then return 0 end
    local consumables = exports['pfm-smallresources']
    local added = 0
    for name, def in pairs(Config.Items or {}) do
        if type(def) == 'table' and def.isConsumable then
            local hunger, thirst = tonumber(def.hungerValue) or 0, tonumber(def.thirstValue) or 0
            local ok, done = false, false
            if def.isAlcohol then
                ok, done = pcall(function() return consumables:AddAlcohol(name, thirst) end)
            elseif hunger >= thirst and hunger > 0 then
                ok, done = pcall(function() return consumables:AddFood(name, hunger) end)
            elseif thirst > 0 then
                ok, done = pcall(function() return consumables:AddDrink(name, thirst) end)
            end
            if ok and done then added = added + 1 end
        end
    end
    return added
end
PFRestaurantsRegisterConsumables = registerConsumables

CreateThread(function() registerConsumables() end)
-- pfm-core drops a resource's usable items when it stops, so register again when it comes back
AddEventHandler('onResourceStart', function(resource)
    if resource == 'pfm-smallresources' then SetTimeout(500, registerConsumables) end
end)

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

--- Staff of a restaurant for the government registry: { { citizenid, role } }.
exports('GetStaffList', function(businessId)
    local out = {}
    for cid, e in pairs((RestaurantData.employees or {})[businessId] or {}) do
        out[#out + 1] = { citizenid = cid, role = e.role }
    end
    table.sort(out, function(a, b) return a.citizenid < b.citizenid end)
    return out
end)
