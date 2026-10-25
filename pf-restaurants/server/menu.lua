-- Menu management

-- Menu text is shown to every client: plain strings of bounded length only
local function menuText(value, maxLen)
    if type(value) ~= 'string' then return nil end
    return value:gsub('%c', ' '):sub(1, maxLen)
end

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
    if type(menuData) ~= 'table' then return end

    -- Validate recipe exists
    local recipe = RestaurantData.recipes[menuData.recipeId] or Config.Recipes[menuData.recipeId]
    if not recipe then
        NotifyPlayer(src, 'Recipe not found', 'error')
        return
    end
    
    if not RestaurantData.menus[businessId] then
        RestaurantData.menus[businessId] = {}
    end
    
    local price = tonumber(menuData.price)
    local maxPrice = (Config.POS and Config.POS.MaxMenuPrice) or 10000
    if not price or price ~= price or price <= 0 or price > maxPrice then
        NotifyPlayer(src, 'Set a price between $0.01 and $' .. maxPrice, 'error')
        return
    end
    local menuItemId = ('menu_%s_%d_%d'):format(businessId, os.time(), math.random(100, 999))
    
    RestaurantData.menus[businessId][menuItemId] = {
        menuItemId = menuItemId,
        recipeId = menuData.recipeId,
        displayName = menuText(menuData.displayName, 60) or recipe.label,
        description = menuText(menuData.description, 300) or '',
        price = math.floor(price * 100 + 0.5) / 100,
        category = menuText(menuData.category, 40) or recipe.category,
        image = menuText(menuData.image, 200) or '',
        enabled = true,
        sortOrder = math.floor(tonumber(menuData.sortOrder) or 999),
        createdAt = os.time()
    }
    RestaurantDB.SaveMenuItem(businessId, RestaurantData.menus[businessId][menuItemId])

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
    if type(menuData) ~= 'table' then return end

    item.displayName = menuText(menuData.displayName, 60) or item.displayName
    item.description = menuText(menuData.description, 300) or item.description
    if menuData.price ~= nil then
        local price = tonumber(menuData.price)
        local maxPrice = (Config.POS and Config.POS.MaxMenuPrice) or 10000
        if not price or price ~= price or price <= 0 or price > maxPrice then
            NotifyPlayer(src, 'Set a price between $0.01 and $' .. maxPrice, 'error')
            return
        end
        item.price = math.floor(price * 100 + 0.5) / 100
    end
    item.category = menuText(menuData.category, 40) or item.category
    item.image = menuText(menuData.image, 200) or item.image
    item.sortOrder = tonumber(menuData.sortOrder) and math.floor(tonumber(menuData.sortOrder)) or item.sortOrder
    item.updatedAt = os.time()
    RestaurantDB.SaveMenuItem(businessId, item)

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
    
    RestaurantData.menus[businessId][menuItemId].enabled = enabled == true
    RestaurantDB.SaveMenuItem(businessId, RestaurantData.menus[businessId][menuItemId])
    
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
        RestaurantDB.DeleteMenuItem(businessId, menuItemId)
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
