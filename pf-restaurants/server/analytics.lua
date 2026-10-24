-- Analytics and reporting

-- Get sales data
QBCore.Functions.CreateCallback('pf-restaurants:server:getSalesData', function(source, cb, businessId, timeRange)
    if not HasPermission(source, businessId, 'analytics.view') then
        cb(nil)
        return
    end
    
    local now = os.time()
    local startTime = now
    
    if timeRange == 'today' then
        startTime = now - 86400 -- 24 hours
    elseif timeRange == 'week' then
        startTime = now - 604800 -- 7 days
    elseif timeRange == 'month' then
        startTime = now - 2592000 -- 30 days
    end
    
    local sales = {
        totalRevenue = 0,
        totalOrders = 0,
        avgOrderValue = 0,
        topItems = {},
        hourlyBreakdown = {},
        paymentMethods = {cash = 0, card = 0}
    }
    
    local itemCounts = {}
    
    for orderId, order in pairs(RestaurantData.orders) do
        if order.businessId == businessId and order.placedAt >= startTime and order.status == 'completed' then
            sales.totalRevenue = sales.totalRevenue + order.total
            sales.totalOrders = sales.totalOrders + 1
            
            -- Payment method breakdown
            if order.paymentMethod == 'cash' then
                sales.paymentMethods.cash = sales.paymentMethods.cash + order.total
            else
                sales.paymentMethods.card = sales.paymentMethods.card + order.total
            end
            
            -- Item counts
            for _, item in ipairs(order.items) do
                itemCounts[item.recipeId] = (itemCounts[item.recipeId] or 0) + item.qty
            end
        end
    end
    
    -- Calculate averages
    if sales.totalOrders > 0 then
        sales.avgOrderValue = sales.totalRevenue / sales.totalOrders
    end
    
    -- Top items
    local itemList = {}
    for recipeId, count in pairs(itemCounts) do
        table.insert(itemList, {recipeId = recipeId, count = count})
    end
    table.sort(itemList, function(a, b) return a.count > b.count end)
    
    for i = 1, math.min(10, #itemList) do
        sales.topItems[i] = itemList[i]
    end
    
    cb(sales)
end)

-- Get employee performance
QBCore.Functions.CreateCallback('pf-restaurants:server:getEmployeePerformance', function(source, cb, businessId)
    if not HasPermission(source, businessId, 'analytics.view') then
        cb(nil)
        return
    end
    
    local employees = RestaurantData.employees[businessId] or {}
    local performance = {}
    
    for cid, employee in pairs(employees) do
        performance[cid] = {
            cid = cid,
            role = employee.role,
            shifts = employee.shifts or 0,
            orders = employee.orders or 0,
            performance = employee.performance or 100,
            hiredDate = employee.hiredDate
        }
    end
    
    cb(performance)
end)

-- Get equipment health summary
QBCore.Functions.CreateCallback('pf-restaurants:server:getEquipmentHealth', function(source, cb, businessId)
    if not HasPermission(source, businessId, 'equipment.view') then
        cb(nil)
        return
    end
    
    local equipment = RestaurantData.equipment[businessId] or {}
    local summary = {
        total = 0,
        needsCleaning = 0,
        needsRepair = 0,
        critical = 0
    }
    
    for stationId, eq in pairs(equipment) do
        summary.total = summary.total + 1
        
        if eq.cleanliness < 50 then
            summary.needsCleaning = summary.needsCleaning + 1
        end
        
        if eq.condition < 50 then
            summary.needsRepair = summary.needsRepair + 1
        end
        
        if eq.cleanliness < 30 or eq.condition < 30 then
            summary.critical = summary.critical + 1
        end
    end
    
    cb(summary)
end)

-- Get business dashboard
QBCore.Functions.CreateCallback('pf-restaurants:server:getDashboard', function(source, cb, businessId)
    if not HasPermission(source, businessId, 'analytics.view') then
        cb(nil)
        return
    end
    
    local business = RestaurantData.businesses[businessId]
    if not business then
        cb(nil)
        return
    end
    
    -- Build dashboard data
    local dashboard = {
        business = {
            businessId = businessId,
            label = business.label,
            healthRating = business.hygiene.healthRating
        },
        hygiene = business.hygiene,
        activeOrders = 0,
        employeesOnDuty = 0
    }
    
    -- Count active orders
    for _, order in pairs(RestaurantData.orders) do
        if order.businessId == businessId and order.status ~= 'completed' and order.status ~= 'cancelled' then
            dashboard.activeOrders = dashboard.activeOrders + 1
        end
    end
    
    -- Count clocked in employees
    if RestaurantData.employees[businessId] then
        for _, employee in pairs(RestaurantData.employees[businessId]) do
            if employee.clockedIn then
                dashboard.employeesOnDuty = dashboard.employeesOnDuty + 1
            end
        end
    end
    
    cb(dashboard)
end)
