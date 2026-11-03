-- Menu management

-- Menu text is shown to every client (menu boards, the POS, kitchen tickets, the customer's bill):
-- plain text of bounded length only (PlainText in server/main.lua). Text with markup characters is
-- refused with a message, not changed silently, so the manager sees why it was not saved.
local MARKUP_MESSAGE = 'Menu text cannot contain < > " or `'

-- Reads the text fields of menuData: { displayName, description, category, image }, each nil when
-- not given (or not a string); nil + false when any of them has markup.
local function readMenuText(menuData)
    local out = {}
    for field, maxLen in pairs({ displayName = 60, description = 300, category = 40, image = 200 }) do
        local text, bad = PlainText(menuData[field], maxLen)
        if bad then return nil, false end
        out[field] = text
    end
    return out, true
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
    local recipe = type(menuData.recipeId) == 'string' and (RestaurantData.recipes[menuData.recipeId] or Config.Recipes[menuData.recipeId]) or nil
    -- another restaurant's own recipe is not on offer here
    if recipe and recipe.businessId ~= nil and recipe.businessId ~= businessId then recipe = nil end
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
    local text = readMenuText(menuData)
    if not text then
        NotifyPlayer(src, MARKUP_MESSAGE, 'error')
        return
    end
    local menuItemId = ('menu_%s_%d_%d'):format(businessId, os.time(), math.random(100, 999))

    RestaurantData.menus[businessId][menuItemId] = {
        menuItemId = menuItemId,
        recipeId = menuData.recipeId,
        -- a recipe's own label and category are cleaned too (a custom recipe's are typed by a manager)
        displayName = text.displayName or PlainText(recipe.label, 60, true) or 'Menu item',
        description = text.description or '',
        price = math.floor(price * 100 + 0.5) / 100,
        category = text.category or PlainText(recipe.category, 40, true),
        image = text.image or '',
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
    local text = readMenuText(menuData)
    if not text then
        NotifyPlayer(src, MARKUP_MESSAGE, 'error')
        return
    end

    if menuData.price ~= nil then
        local price = tonumber(menuData.price)
        local maxPrice = (Config.POS and Config.POS.MaxMenuPrice) or 10000
        if not price or price ~= price or price <= 0 or price > maxPrice then
            NotifyPlayer(src, 'Set a price between $0.01 and $' .. maxPrice, 'error')
            return
        end
        item.price = math.floor(price * 100 + 0.5) / 100
    end
    item.displayName = text.displayName or item.displayName
    item.description = text.description or item.description
    item.category = text.category or item.category
    item.image = text.image or item.image
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
