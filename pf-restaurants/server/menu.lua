-- Menu management

-- Get menu for business
QBCore.Functions.CreateCallback('pf-restaurants:server:getMenu', function(source, cb, businessId)
    local menu = RestaurantData.menus[businessId] or {}
    cb(menu)
end)

-- Create menu item
RegisterNetEvent('pf-restaurants:server:createMenuItem', function(businessId, menuData)
    local src = source
    
    if not HasPermission(src, businessId, 'menu.create') then
        NotifyPlayer(src, 'No permission to create menu items', 'error')
        return
    end
    
    -- Validate recipe exists
    local recipe = RestaurantData.recipes[menuData.recipeId] or Config.Recipes[menuData.recipeId]
    if not recipe then
        NotifyPlayer(src, 'Recipe not found', 'error')
        return
    end
    
    if not RestaurantData.menus[businessId] then
        RestaurantData.menus[businessId] = {}
    end
    
    local menuItemId = 'menu_' .. businessId .. '_' .. os.time()
    
    RestaurantData.menus[businessId][menuItemId] = {
        menuItemId = menuItemId,
        recipeId = menuData.recipeId,
        displayName = menuData.displayName or recipe.label,
        description = menuData.description or '',
        price = menuData.price or 10,
        category = menuData.category or recipe.category,
        image = menuData.image or '',
        enabled = true,
        sortOrder = menuData.sortOrder or 999,
        createdAt = os.time()
    }
    
    NotifyPlayer(src, 'Menu item created', 'success')
    TriggerClientEvent('pf-restaurants:client:menuUpdate', -1, businessId, RestaurantData.menus[businessId])
end)

-- Update menu item
RegisterNetEvent('pf-restaurants:server:updateMenuItem', function(businessId, menuItemId, menuData)
    local src = source
    
    if not HasPermission(src, businessId, 'menu.edit') then
        NotifyPlayer(src, 'No permission to edit menu items', 'error')
        return
    end
    
    if not RestaurantData.menus[businessId] or not RestaurantData.menus[businessId][menuItemId] then
        NotifyPlayer(src, 'Menu item not found', 'error')
        return
    end
    
    local item = RestaurantData.menus[businessId][menuItemId]
    
    item.displayName = menuData.displayName or item.displayName
    item.description = menuData.description or item.description
    item.price = menuData.price or item.price
    item.category = menuData.category or item.category
    item.image = menuData.image or item.image
    item.sortOrder = menuData.sortOrder or item.sortOrder
    item.updatedAt = os.time()
    
    NotifyPlayer(src, 'Menu item updated', 'success')
    TriggerClientEvent('pf-restaurants:client:menuUpdate', -1, businessId, RestaurantData.menus[businessId])
end)

-- Toggle menu item (86)
RegisterNetEvent('pf-restaurants:server:toggleMenuItem', function(businessId, menuItemId, enabled)
    local src = source
    
    if not HasPermission(src, businessId, '86.toggle') then
        NotifyPlayer(src, 'No permission to toggle menu items', 'error')
        return
    end
    
    if not RestaurantData.menus[businessId] or not RestaurantData.menus[businessId][menuItemId] then
        NotifyPlayer(src, 'Menu item not found', 'error')
        return
    end
    
    RestaurantData.menus[businessId][menuItemId].enabled = enabled
    
    local status = enabled and 'enabled' or 'disabled (86)'
    NotifyPlayer(src, 'Menu item ' .. status, 'success')
    TriggerClientEvent('pf-restaurants:client:menuUpdate', -1, businessId, RestaurantData.menus[businessId])
end)

-- Delete menu item
RegisterNetEvent('pf-restaurants:server:deleteMenuItem', function(businessId, menuItemId)
    local src = source
    
    if not HasPermission(src, businessId, 'menu.delete') then
        NotifyPlayer(src, 'No permission to delete menu items', 'error')
        return
    end
    
    if RestaurantData.menus[businessId] and RestaurantData.menus[businessId][menuItemId] then
        RestaurantData.menus[businessId][menuItemId] = nil
        NotifyPlayer(src, 'Menu item deleted', 'success')
        TriggerClientEvent('pf-restaurants:client:menuUpdate', -1, businessId, RestaurantData.menus[businessId])
    else
        NotifyPlayer(src, 'Menu item not found', 'error')
    end
end)

-- Get menu categories
QBCore.Functions.CreateCallback('pf-restaurants:server:getMenuCategories', function(source, cb, businessId)
    local categories = {}
    local menu = RestaurantData.menus[businessId] or {}
    
    for _, item in pairs(menu) do
        if item.category and not categories[item.category] then
            categories[item.category] = true
        end
    end
    
    local categoryList = {}
    for cat, _ in pairs(categories) do
        table.insert(categoryList, cat)
    end
    
    cb(categoryList)
end)
