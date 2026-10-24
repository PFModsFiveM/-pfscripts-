-- server/tablet.lua
-- PF Mechanic Job - Tablet System Server
-- Handles work orders, cash register, and management data

local QBCore = exports['pfm-core']:GetCoreObject()

-- In-memory storage for work orders (you can later migrate to database)
local WorkOrders = {}
local OrderIdCounter = 1

-- Sample catalog items (customize these based on your needs)
local Catalog = {
    -- Parts
    { name = 'Engine Oil', price = 50, icon = '🛢️', category = 'fluids' },
    { name = 'Brake Fluid', price = 40, icon = '🚰', category = 'fluids' },
    { name = 'Coolant', price = 45, icon = '❄️', category = 'fluids' },
    { name = 'Transmission Fluid', price = 60, icon = '⚙️', category = 'fluids' },
    
    { name = 'Brake Pads', price = 150, icon = '🔧', category = 'parts' },
    { name = 'Air Filter', price = 80, icon = '💨', category = 'parts' },
    { name = 'Spark Plugs', price = 120, icon = '⚡', category = 'parts' },
    { name = 'Battery', price = 200, icon = '🔋', category = 'parts' },
    { name = 'Alternator', price = 350, icon = '⚙️', category = 'parts' },
    { name = 'Starter Motor', price = 300, icon = '🔌', category = 'parts' },
    
    -- Tires
    { name = 'Standard Tire', price = 100, icon = '⭕', category = 'tires' },
    { name = 'Performance Tire', price = 180, icon = '🏁', category = 'tires' },
    { name = 'Off-Road Tire', price = 200, icon = '🏔️', category = 'tires' },
    
    -- Services
    { name = 'Oil Change', price = 100, icon = '🛠️', category = 'service' },
    { name = 'Brake Service', price = 250, icon = '🛑', category = 'service' },
    { name = 'Tune-Up', price = 300, icon = '🔧', category = 'service' },
    { name = 'Diagnostic Scan', price = 150, icon = '📊', category = 'service' },
    { name = 'Full Inspection', price = 200, icon = '🔍', category = 'service' },
    
    -- Cosmetics
    { name = 'Window Tint', price = 500, icon = '🪟', category = 'cosmetic' },
    { name = 'Custom Paint', price = 1000, icon = '🎨', category = 'cosmetic' },
    { name = 'Vinyl Wrap', price = 1500, icon = '📐', category = 'cosmetic' },
    { name = 'Neon Kit', price = 800, icon = '💡', category = 'cosmetic' },
}

-- Helper: Check if player is mechanic
local function isPlayerMechanic(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    
    for _, jobName in ipairs(Config.AllowedJobs or {'mechanic'}) do
        if Player.PlayerData.job.name == jobName then
            return true
        end
    end
    return false
end

-- Helper: Get all online mechanic employees
local function getOnlineEmployees()
    local employees = {}
    local Players = QBCore.Functions.GetQBPlayers()
    
    for _, Player in pairs(Players) do
        if Player and Player.PlayerData and Player.PlayerData.job then
            for _, jobName in ipairs(Config.AllowedJobs or {'mechanic'}) do
                if Player.PlayerData.job.name == jobName then
                    table.insert(employees, {
                        name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
                        citizenid = Player.PlayerData.citizenid,
                        role = Player.PlayerData.job.grade.name or 'Mechanic',
                        online = true
                    })
                    break
                end
            end
        end
    end
    
    return employees
end

-- Helper: Calculate today's stats
local function getTodaysStats()
    -- This is a simplified version - you can expand this with database queries
    local completedToday = 0
    local revenueToday = 0
    
    for _, order in pairs(WorkOrders) do
        if order.status == 'completed' then
            completedToday = completedToday + 1
            revenueToday = revenueToday + (order.price or 0)
        end
    end
    
    local employees = getOnlineEmployees()
    
    return {
        revenue = revenueToday,
        completedJobs = completedToday,
        activeEmployees = #employees,
        avgJobTime = '45m' -- You can calculate this from actual data
    }
end

-- Callback: Get all tablet data
QBCore.Functions.CreateCallback('pf_mech:tablet:getData', function(source, cb)
    if not isPlayerMechanic(source) then
        cb({ workOrders = {}, catalog = {}, stats = {}, employees = {} })
        return
    end
    
    -- Get work orders
    local workOrders = {}
    for id, order in pairs(WorkOrders) do
        table.insert(workOrders, {
            id = id,
            title = order.title or 'Repair Job',
            vehicle = order.vehicle or 'Unknown Vehicle',
            customer = order.customer or 'Walk-in Customer',
            price = order.price or 0,
            status = order.status or 'pending',
            time = order.time or os.date('%H:%M')
        })
    end
    
    -- Get stats and employees
    local stats = getTodaysStats()
    local employees = getOnlineEmployees()
    
    cb({
        workOrders = workOrders,
        catalog = Catalog,
        stats = stats,
        employees = employees
    })
end)

-- Callback: Get work orders only
QBCore.Functions.CreateCallback('pf_mech:tablet:getWorkOrders', function(source, cb)
    if not isPlayerMechanic(source) then
        cb({})
        return
    end
    
    local workOrders = {}
    for id, order in pairs(WorkOrders) do
        table.insert(workOrders, {
            id = id,
            title = order.title or 'Repair Job',
            vehicle = order.vehicle or 'Unknown Vehicle',
            customer = order.customer or 'Walk-in Customer',
            price = order.price or 0,
            status = order.status or 'pending',
            time = order.time or os.date('%H:%M')
        })
    end
    
    cb(workOrders)
end)

-- Callback: Process checkout
QBCore.Functions.CreateCallback('pf_mech:tablet:checkout', function(source, cb, cart, total)
    if not isPlayerMechanic(source) then
        cb(false, 'You must be a mechanic to process transactions')
        return
    end
    
    -- This placeholder charged nobody but paid the mechanic a 20% "commission" in real bank money on a
    -- `total` the client sent, so any mechanic could create money. No UI calls it (the tablet's POS uses
    -- mechanic:server:chargeCustomer, which charges a nearby customer through the bank ledger), so it now
    -- moves no money and points callers at the register.
    cb(false, 'Use the register (POS) to charge a customer')
end)

-- Event: Create new work order
RegisterNetEvent('pf_mech:tablet:createWorkOrder', function(orderData)
    local src = source
    if not isPlayerMechanic(src) then return end
    
    local orderId = OrderIdCounter
    OrderIdCounter = OrderIdCounter + 1
    
    WorkOrders[orderId] = {
        id = orderId,
        title = orderData.title or 'Repair Job',
        vehicle = orderData.vehicle or 'Unknown Vehicle',
        customer = orderData.customer or 'Walk-in Customer',
        price = orderData.price or 0,
        status = 'pending',
        time = os.date('%H:%M'),
        createdBy = src
    }
    
    -- Notify all online mechanics
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        if Player and isPlayerMechanic(Player.PlayerData.source) then
            TriggerClientEvent('pf-mechanicjob:client:updateTabletData', Player.PlayerData.source, {
                workOrders = WorkOrders
            })
        end
    end
    
    if Config.Debug then
        print(string.format('[Tablet] Work order #%d created: %s', orderId, orderData.title or 'Repair Job'))
    end
end)

-- Event: Update work order status
RegisterNetEvent('pf_mech:tablet:updateWorkOrder', function(orderId, status)
    local src = source
    if not isPlayerMechanic(src) then return end
    
    if WorkOrders[orderId] then
        WorkOrders[orderId].status = status
        
        -- Notify all online mechanics
        local Players = QBCore.Functions.GetQBPlayers()
        for _, Player in pairs(Players) do
            if Player and isPlayerMechanic(Player.PlayerData.source) then
                TriggerClientEvent('pf-mechanicjob:client:updateTabletData', Player.PlayerData.source, {
                    workOrders = WorkOrders
                })
            end
        end
        
        if Config.Debug then
            print(string.format('[Tablet] Work order #%d status updated to: %s', orderId, status))
        end
    end
end)

-- Event: Delete work order
RegisterNetEvent('pf_mech:tablet:deleteWorkOrder', function(orderId)
    local src = source
    if not isPlayerMechanic(src) then return end
    
    if WorkOrders[orderId] then
        WorkOrders[orderId] = nil
        
        -- Notify all online mechanics
        local Players = QBCore.Functions.GetQBPlayers()
        for _, Player in pairs(Players) do
            if Player and isPlayerMechanic(Player.PlayerData.source) then
                TriggerClientEvent('pf-mechanicjob:client:updateTabletData', Player.PlayerData.source, {
                    workOrders = WorkOrders
                })
            end
        end
        
        if Config.Debug then
            print(string.format('[Tablet] Work order #%d deleted', orderId))
        end
    end
end)

-- Command to add test work orders (for development)
if Config.Debug then
    RegisterCommand('addtestorder', function(source, args)
        local src = source
        if not isPlayerMechanic(src) then return end
        
        local vehicles = {'Futo', 'Sultan', 'Elegy', 'Dominator', 'Buffalo'}
        local customers = {'John Doe', 'Jane Smith', 'Mike Johnson', 'Sarah Williams', 'Chris Brown'}
        local titles = {'Engine Repair', 'Brake Service', 'Oil Change', 'Tire Replacement', 'Full Inspection'}
        
        local orderId = OrderIdCounter
        OrderIdCounter = OrderIdCounter + 1
        
        WorkOrders[orderId] = {
            id = orderId,
            title = titles[math.random(#titles)],
            vehicle = vehicles[math.random(#vehicles)],
            customer = customers[math.random(#customers)],
            price = math.random(500, 2000),
            status = 'pending',
            time = os.date('%H:%M'),
            createdBy = src
        }
        
        TriggerClientEvent('QBCore:Notify', src, 'Test work order created!', 'success')
        
        -- Notify all online mechanics
        local Players = QBCore.Functions.GetQBPlayers()
        for _, Player in pairs(Players) do
            if Player and isPlayerMechanic(Player.PlayerData.source) then
                TriggerClientEvent('pf-mechanicjob:client:updateTabletData', Player.PlayerData.source, {
                    workOrders = WorkOrders
                })
            end
        end
    end, false)
end

-- Debug
if Config.Debug then
    print('[PF Mechanic] Tablet server system loaded')
end
