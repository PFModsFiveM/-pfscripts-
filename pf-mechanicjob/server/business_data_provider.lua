-- server/business_data_provider.lua
-- Exports business data to external systems like pf-computer
-- This allows pf-computer to display mechanic shop data in its Business Manager

local QBCore = exports['pfm-core']:GetCoreObject()local function GetBusinessTransactions(business, limit)
    limit = tonumber(limit) or 50
    
    local rows = MySQL.query.await([[
        SELECT 
            transaction_id,
            business,
            customer_id,
            mechanic_id,
            mechanic_name,
            items,
            subtotal,
            tax,
            total,
            payment_type,
            status,
            created_at
        FROM pf_pos_transactions
        WHERE business = ?
        ORDER BY created_at DESC
        LIMIT ?
    ]], { business, limit }) or {}
    
    -- Parse items JSON
    for _, tx in ipairs(rows) do
        if tx.items and type(tx.items) == 'string' then
            tx.items = json.decode(tx.items) or {}
        end
    end
    
    return rows
end

local function BuildAnalyticsSeries(business)
    local series = {
        day = { labels = {}, values = {} },
        week = { labels = {}, values = {} },
        month = { labels = {}, values = {} }
    }

    for hour = 0, 23 do
        series.day.labels[#series.day.labels + 1] = string.format('%02d:00', hour)
        series.day.values[#series.day.values + 1] = 0
    end

    local dayRows = MySQL.query.await([[
        SELECT HOUR(created_at) AS hour, COALESCE(SUM(total), 0) AS revenue
        FROM pf_pos_transactions
        WHERE business = ?
        AND DATE(created_at) = CURDATE()
        AND (status = 'completed' OR status IS NULL OR status = '')
        GROUP BY HOUR(created_at)
        ORDER BY hour
    ]], { business }) or {}

    for _, row in ipairs(dayRows) do
        local hour = tonumber(row.hour) or 0
        local idx = hour + 1
        if series.day.values[idx] ~= nil then
            series.day.values[idx] = tonumber(row.revenue) or 0
        end
    end

    local weekMap = {}
    local weekRows = MySQL.query.await([[
        SELECT DATE(created_at) AS day, COALESCE(SUM(total), 0) AS revenue
        FROM pf_pos_transactions
        WHERE business = ?
        AND created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
        AND (status = 'completed' OR status IS NULL OR status = '')
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at)
    ]], { business }) or {}

    for _, row in ipairs(weekRows) do
        if row.day then
            weekMap[tostring(row.day)] = tonumber(row.revenue) or 0
        end
    end

    for i = 6, 0, -1 do
        local ts = os.time() - (i * 86400)
        local dayKey = os.date('%Y-%m-%d', ts)
        local label = os.date('%a', ts)
        series.week.labels[#series.week.labels + 1] = label
        series.week.values[#series.week.values + 1] = weekMap[dayKey] or 0
    end

    local monthMap = {}
    local monthRows = MySQL.query.await([[
        SELECT DATE(created_at) AS day, COALESCE(SUM(total), 0) AS revenue
        FROM pf_pos_transactions
        WHERE business = ?
        AND created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY)
        AND (status = 'completed' OR status IS NULL OR status = '')
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at)
    ]], { business }) or {}

    for _, row in ipairs(monthRows) do
        if row.day then
            monthMap[tostring(row.day)] = tonumber(row.revenue) or 0
        end
    end

    for i = 29, 0, -1 do
        local ts = os.time() - (i * 86400)
        local dayKey = os.date('%Y-%m-%d', ts)
        local label = os.date('%m/%d', ts)
        series.month.labels[#series.month.labels + 1] = label
        series.month.values[#series.month.values + 1] = monthMap[dayKey] or 0
    end

    return series
end

local function BuildCategoryRevenue(business)
    local rows = MySQL.query.await([[
        SELECT items
        FROM pf_pos_transactions
        WHERE business = ?
        AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        AND (status = 'completed' OR status IS NULL OR status = '')
    ]], { business }) or {}

    local totals = {}
    for _, tx in ipairs(rows) do
        local items = tx.items
        if items and type(items) == 'string' then
            items = json.decode(items) or {}
        end

        for _, item in ipairs(items or {}) do
            local category = item.category or 'General'
            local qty = tonumber(item.qty or item.quantity or 1) or 1
            local unit = tonumber(item.unitPrice or item.price or 0) or 0
            local lineTotal = tonumber(item.lineTotal) or (unit * qty)
            totals[category] = (totals[category] or 0) + lineTotal
        end
    end

    local out = {}
    for category, revenue in pairs(totals) do
        out[#out + 1] = { category = category, revenue = revenue }
    end
    table.sort(out, function(a, b) return (a.revenue or 0) > (b.revenue or 0) end)

    return out
end

local function GetBusinessAnalytics(business)
    -- Get today's stats
    local todayStats = MySQL.query.await([[
        SELECT 
            COUNT(*) as transaction_count,
            COALESCE(SUM(total), 0) as total_revenue,
            COALESCE(SUM(subtotal), 0) as subtotal,
            COALESCE(SUM(tax), 0) as tax_collected
        FROM pf_pos_transactions
        WHERE business = ?
        AND DATE(created_at) = CURDATE()
        AND (status = 'completed' OR status IS NULL OR status = '')
    ]], { business })
    
    -- Get week stats
    local weekStats = MySQL.query.await([[
        SELECT 
            COUNT(*) as transaction_count,
            COALESCE(SUM(total), 0) as total_revenue,
            COALESCE(SUM(subtotal), 0) as subtotal,
            COALESCE(SUM(tax), 0) as tax_collected
        FROM pf_pos_transactions
        WHERE business = ?
        AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        AND (status = 'completed' OR status IS NULL OR status = '')
    ]], { business })
    
    -- Get month stats
    local monthStats = MySQL.query.await([[
        SELECT 
            COUNT(*) as transaction_count,
            COALESCE(SUM(total), 0) as total_revenue,
            COALESCE(SUM(subtotal), 0) as subtotal,
            COALESCE(SUM(tax), 0) as tax_collected
        FROM pf_pos_transactions
        WHERE business = ?
        AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        AND (status = 'completed' OR status IS NULL OR status = '')
    ]], { business })
    
    -- Get all-time stats
    local allTimeStats = MySQL.query.await([[
        SELECT 
            COUNT(*) as transaction_count,
            COALESCE(SUM(total), 0) as total_revenue,
            COALESCE(SUM(subtotal), 0) as subtotal,
            COALESCE(SUM(tax), 0) as tax_collected
        FROM pf_pos_transactions
        WHERE business = ?
        AND (status = 'completed' OR status IS NULL OR status = '')
    ]], { business })
    
    -- Get top selling items
    local topItems = MySQL.query.await([[
        SELECT 
            items
        FROM pf_pos_transactions
        WHERE business = ?
        AND (status = 'completed' OR status IS NULL OR status = '')
        ORDER BY created_at DESC
        LIMIT 100
    ]], { business }) or {}
    
    -- Parse and aggregate top items
    local itemCounts = {}
    for _, tx in ipairs(topItems) do
        if tx.items and type(tx.items) == 'string' then
            local items = json.decode(tx.items) or {}
            for _, item in ipairs(items) do
                local label = item.label or item.item or 'Unknown'
                itemCounts[label] = (itemCounts[label] or 0) + (item.qty or 1)
            end
        end
    end
    
    -- Convert to sorted array
    local topItemsArray = {}
    for label, count in pairs(itemCounts) do
        table.insert(topItemsArray, { label = label, count = count })
    end
    table.sort(topItemsArray, function(a, b) return a.count > b.count end)
    
    -- Limit to top 5
    local top5 = {}
    for i = 1, math.min(5, #topItemsArray) do
        top5[i] = topItemsArray[i]
    end
    
    local series = BuildAnalyticsSeries(business)
    local categoryRevenue = BuildCategoryRevenue(business)

    return {
        today = {
            sales = (todayStats[1] and todayStats[1].transaction_count) or 0,
            transactions = (todayStats[1] and todayStats[1].transaction_count) or 0,
            revenue = (todayStats[1] and todayStats[1].total_revenue) or 0,
            subtotal = (todayStats[1] and todayStats[1].subtotal) or 0,
            tax = (todayStats[1] and todayStats[1].tax_collected) or 0
        },
        week = {
            sales = (weekStats[1] and weekStats[1].transaction_count) or 0,
            transactions = (weekStats[1] and weekStats[1].transaction_count) or 0,
            revenue = (weekStats[1] and weekStats[1].total_revenue) or 0,
            subtotal = (weekStats[1] and weekStats[1].subtotal) or 0,
            tax = (weekStats[1] and weekStats[1].tax_collected) or 0
        },
        month = {
            sales = (monthStats[1] and monthStats[1].transaction_count) or 0,
            transactions = (monthStats[1] and monthStats[1].transaction_count) or 0,
            revenue = (monthStats[1] and monthStats[1].total_revenue) or 0,
            subtotal = (monthStats[1] and monthStats[1].subtotal) or 0,
            tax = (monthStats[1] and monthStats[1].tax_collected) or 0
        },
        allTime = {
            sales = (allTimeStats[1] and allTimeStats[1].transaction_count) or 0,
            transactions = (allTimeStats[1] and allTimeStats[1].transaction_count) or 0,
            revenue = (allTimeStats[1] and allTimeStats[1].total_revenue) or 0,
            subtotal = (allTimeStats[1] and allTimeStats[1].subtotal) or 0,
            tax = (allTimeStats[1] and allTimeStats[1].tax_collected) or 0
        },
        topItems = top5,
        series = series,
        categoryRevenue = categoryRevenue
    }
end

local function GetBusinessEmployees(business)
    -- Get employees from QBCore job system
    local employees = {}
    local players = MySQL.query.await([[
        SELECT citizenid, charinfo, job
        FROM players
        WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?
    ]], { business }) or {}
    
    for _, player in ipairs(players) do
        local charinfo = type(player.charinfo) == 'string' and json.decode(player.charinfo) or player.charinfo
        local jobData = type(player.job) == 'string' and json.decode(player.job) or player.job
        
        local name = 'Unknown'
        if charinfo then
            name = (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')
        end
        
        local grade = jobData and jobData.grade or 0
        local gradeName = jobData and jobData.grade and jobData.grade.name or 'Employee'
        local isBoss = jobData and jobData.isboss or false
        
        table.insert(employees, {
            citizenid = player.citizenid,
            name = name,
            grade = grade,
            gradeName = gradeName,
            role = isBoss and 'owner' or 'employee'
        })
    end
    
    return employees
end

local function BuildSuppliesCatalog()
    local catalogConfig = Config.SuppliesCatalog or {}
    local overrides = catalogConfig.overrides or {}
    local imageBase = catalogConfig.imageBase or 'https://cfx-nui-qb-inventory/html/images/'

    local items = {}
    local categories = {}
    local categorySet = {}

    local function addCategory(category)
        if category and not categorySet[category] then
            categorySet[category] = true
            categories[#categories + 1] = { id = category, label = category }
        end
    end

    local function addItem(itemId, itemData)
        local override = overrides[itemId] or {}
        local label = override.label or itemData.label or itemId
        local category = override.category or itemData.category or 'General'
        local caseSize = override.caseSize or catalogConfig.defaultCaseSize or 10
        local caseContents = override.caseContents or (tostring(caseSize) .. 'x ' .. label)
        local pricePerCase = override.casePrice or override.pricePerCase or itemData.basePrice or 0

        addCategory(category)

        items[#items + 1] = {
            item = itemId,
            label = label,
            category = category,
            caseSize = caseSize,
            caseContents = caseContents,
            pricePerCase = pricePerCase,
            image = override.image
        }
    end

    if catalogConfig.items and #catalogConfig.items > 0 then
        for _, entry in ipairs(catalogConfig.items) do
            local itemId = entry.item or entry.id
            if itemId then
                local itemData = (Config.RegisterItems and Config.RegisterItems[itemId]) or {}
                overrides[itemId] = {
                    caseSize = entry.caseSize or overrides[itemId] and overrides[itemId].caseSize,
                    caseContents = entry.caseContents or overrides[itemId] and overrides[itemId].caseContents,
                    casePrice = entry.casePrice or overrides[itemId] and overrides[itemId].casePrice,
                    category = entry.category or overrides[itemId] and overrides[itemId].category,
                    label = entry.label or overrides[itemId] and overrides[itemId].label,
                    image = entry.image or overrides[itemId] and overrides[itemId].image
                }
                addItem(itemId, itemData)
            end
        end
    else
        for itemId, itemData in pairs(Config.RegisterItems or {}) do
            addItem(itemId, itemData)
        end
    end

    -- scrap materials (recycling plant, scrapyard), one unit per case; a part of the same name wins
    local listed = {}
    for _, it in ipairs(items) do listed[it.item] = true end
    for _, m in ipairs(catalogConfig.materials or {}) do
        local price = tonumber(m.casePrice)
        if type(m.item) == 'string' and not listed[m.item] and price and price > 0 then
            local category = m.category or catalogConfig.materialsCategory or 'Materials'
            local label = m.label or m.item
            addCategory(category)
            items[#items + 1] = {
                item = m.item, label = label, category = category, caseSize = 1,
                caseContents = '1x ' .. label, pricePerCase = price, image = m.image,
            }
            listed[m.item] = true
        end
    end

    return {
        items = items,
        categories = categories,
        imageBase = imageBase
    }
end

local function GetBusinessConfig(business, source)
    -- Get business branding from Config
    local branding = Config.BusinessBranding and Config.BusinessBranding[business] or {}
    
    -- Get business info from database if it exists
    local dbBusiness = MySQL.single.await('SELECT * FROM pf_business WHERE business = ? LIMIT 1', { business })
    
    -- Try to get player's job data
    local Player = source and QBCore.Functions.GetPlayer(source) or nil
    local playerJob = Player and Player.PlayerData.job or nil
    
    return {
        businessId = business,
        businessName = (dbBusiness and dbBusiness.name) or branding.name or business,
        businessType = 'mechanic',
        blipColor = (dbBusiness and dbBusiness.primary_color) or branding.blipColor or 5,
        blipCoords = branding.blipCoords or { x = 0, y = 0, z = 0 },
        primaryColor = (dbBusiness and dbBusiness.primary_color) or branding.primaryColor or '#3498db',
        secondaryColor = (dbBusiness and dbBusiness.secondary_color) or branding.secondaryColor or '#2c3e50',
        logo = (dbBusiness and dbBusiness.logo) or branding.logo or '',
        taxRate = (dbBusiness and dbBusiness.tax) or Config.DefaultTax or 0.05,
        isOpen = (dbBusiness and dbBusiness.open == 1) or true,
        currency = '$',
        businessGrades = QBCore.Shared.Jobs[business] and QBCore.Shared.Jobs[business].grades or {},
        playerGrade = playerJob and playerJob.grade or 0,
        playerIsBoss = playerJob and playerJob.isboss or false,
        suppliesCatalog = BuildSuppliesCatalog()
    }
end

local function GetBusinessInventory(business)
    -- Check if parts inventory exists, otherwise return empty
    local inventory = MySQL.query.await([[
        SELECT 
            ps.part_id as item,
            pc.label as name,
            ps.qty as stock,
            'Parts' as category,
            pc.base_cost as cost
        FROM pf_parts_stock ps
        LEFT JOIN pf_parts_catalog pc ON ps.part_id = pc.part_id
        WHERE ps.society = ?
        ORDER BY pc.label
    ]], { business }) or {}
    
    return inventory
end

local function SeedDefaultMenuItems(business)
    local existingCount = MySQL.scalar.await(
        'SELECT COUNT(1) FROM pf_pos_items WHERE business = ?',
        { business }
    )

    if existingCount and tonumber(existingCount) > 0 then
        return
    end

    -- Seed items from Config.RegisterItems
    if Config and Config.RegisterItems then
        for itemId, itemData in pairs(Config.RegisterItems) do
            pcall(function()
                MySQL.insert.await([[
                    INSERT INTO pf_pos_items (business, item_id, category, label, price, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, NOW(), NOW())
                ]], {
                    business,
                    itemId,  -- Use the config key (e.g., 'engine_oil', 'brake_pads')
                    itemData.category,
                    itemData.label,
                    itemData.basePrice  -- Map basePrice to price field
                })
            end)
        end
    end
end

local function GetMenuItems(business)
    -- Seed defaults if this is the first time
    SeedDefaultMenuItems(business)
    
    -- Get cash register items from pf_pos_items table
    local items = MySQL.query.await([[
        SELECT 
            id,
            item_id,
            category,
            label as name,
            price,
            created_at,
            updated_at
        FROM pf_pos_items
        WHERE business = ?
        ORDER BY category, label
    ]], { business }) or {}
    
    return items
end

local function GetMenuCategories(business)
    -- Seed defaults if this is the first time
    SeedDefaultMenuItems(business)
    
    -- Get distinct categories from pf_pos_items table
    local categories = MySQL.query.await([[
        SELECT DISTINCT category
        FROM pf_pos_items
        WHERE business = ?
        ORDER BY category
    ]], { business }) or {}
    
    -- Extract just the category strings
    local categoryList = {}
    for _, cat in ipairs(categories) do
        table.insert(categoryList, cat.category)
    end
    
    return categoryList
end

-- Export functions for external resources
exports('GetBusinessTransactions', GetBusinessTransactions)
exports('GetBusinessAnalytics', GetBusinessAnalytics)
exports('GetBusinessEmployees', GetBusinessEmployees)
exports('GetBusinessConfig', GetBusinessConfig)
exports('GetBusinessInventory', GetBusinessInventory)
exports('GetMenuItems', GetMenuItems)
exports('GetMenuCategories', GetMenuCategories)
exports('GetBusinessInventory', GetBusinessInventory)

-- Update a menu item
local function NotifyPosPricingRefresh(business)
    TriggerClientEvent('pf-mechanicjob:client:posPricingRefresh', -1, business)
end

local function UpdateMenuItem(business, itemId, itemData)
    if not business or not itemId or not itemData then
        return false, 'missing_parameters'
    end
    
    local success, err = pcall(function()
        MySQL.query.await([[
            UPDATE pf_pos_items 
            SET label = ?, price = ?, category = ?, updated_at = NOW()
            WHERE business = ? AND id = ?
        ]], {
            itemData.name or 'Item',
            tonumber(itemData.price) or 0,
            itemData.category or 'General',
            business,
            tonumber(itemId) or 0
        })
    end)
    
    if success then
        NotifyPosPricingRefresh(business)
        return true, 'updated'
    else
        print(string.format('[ERROR] Failed to update menu item: %s', tostring(err)))
        return false, tostring(err)
    end
end

-- Delete a menu item
local function DeleteMenuItem(business, itemId)
    if not business or not itemId then
        return false, 'missing_parameters'
    end
    
    local success, err = pcall(function()
        MySQL.query.await('DELETE FROM pf_pos_items WHERE business = ? AND id = ?', 
            { business, tonumber(itemId) or 0 })
    end)
    
    if success then
        NotifyPosPricingRefresh(business)
        return true, 'deleted'
    else
        print(string.format('[ERROR] Failed to delete menu item: %s', tostring(err)))
        return false, tostring(err)
    end
end

-- Add a menu item
local function AddMenuItem(business, itemData)
    if not business or not itemData then
        return false, 'missing_parameters'
    end
    
    local success, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO pf_pos_items (business, item_id, category, label, price, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, NOW(), NOW())
        ]], {
            business,
            itemData.id or itemData.name or 'item_' .. os.time(),
            itemData.category or 'General',
            itemData.name or 'New Item',
            tonumber(itemData.price) or 0
        })
    end)
    
    if success then
        NotifyPosPricingRefresh(business)
        return true, 'added'
    else
        print(string.format('[ERROR] Failed to add menu item: %s', tostring(err)))
        return false, tostring(err)
    end
end

-- Update category name (rename)
local function UpdateCategory(business, oldName, newName)
    if not business or not oldName or not newName then
        return false, 'missing_parameters'
    end
    
    local success, err = pcall(function()
        MySQL.query.await([[
            UPDATE pf_pos_items 
            SET category = ?
            WHERE business = ? AND category = ?
        ]], {
            newName,
            business,
            oldName
        })
    end)
    
    if success then
        NotifyPosPricingRefresh(business)
        return true, 'updated'
    else
        print(string.format('[ERROR] Failed to update category: %s', tostring(err)))
        return false, tostring(err)
    end
end

-- Delete category (removes all items in that category)
local function DeleteCategory(business, categoryName)
    if not business or not categoryName then
        return false, 'missing_parameters'
    end
    
    local success, err = pcall(function()
        MySQL.query.await('DELETE FROM pf_pos_items WHERE business = ? AND category = ?', 
            { business, categoryName })
    end)
    
    if success then
        NotifyPosPricingRefresh(business)
        return true, 'deleted'
    else
        print(string.format('[ERROR] Failed to delete category: %s', tostring(err)))
        return false, tostring(err)
    end
end

exports('UpdateMenuItem', UpdateMenuItem)
exports('DeleteMenuItem', DeleteMenuItem)
exports('AddMenuItem', AddMenuItem)
exports('UpdateCategory', UpdateCategory)
exports('DeleteCategory', DeleteCategory)

-- Export GetBusinessConfig for pf-computer integration
exports('GetBusinessConfig', function()
    return {
        suppliesCatalog = BuildSuppliesCatalog(),
        suppliesOrder = Config.SuppliesOrder,
        businessName = 'Mechanic Shop',
        businessType = 'mechanic'
    }
end)

print('[pf-mechanicjob] Business data provider exports initialized')
