-- Management App - Server Side Handler
-- Handles database operations, callbacks, events, and business logic

local QBCore = exports['pfm-core']:GetCoreObject()

-- Business resolution
local AllowedJobs = {
    mechanic = true,
    mechanic2 = true,
    mechanic3 = true
}

local function GetBusinessForSource(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not job or not AllowedJobs[job] then return nil end

    return job
end

-- Helper: Get job grades from QBCore
local function GetJobGrades(jobName)
    if not QBCore.Shared.Jobs[jobName] then return {} end
    return QBCore.Shared.Jobs[jobName].grades or {}
end

-- Helper: Get role from QBCore job grade
local function GetRoleFromGrade(jobName, gradeLevel)
    local grades = GetJobGrades(jobName)
    if grades[gradeLevel] then
        local grade = grades[gradeLevel]
        if grade.isboss then
            return 'owner'
        elseif grade.name and (grade.name:lower():find('manager') or grade.name:lower():find('boss')) then
            return 'manager'
        end
    end
    return 'employee'
end

-- Helper: Check if a grade level is a boss grade
local function IsBossGrade(jobName, gradeLevel)
    local grades = GetJobGrades(jobName)
    if grades[gradeLevel] then
        return grades[gradeLevel].isboss == true
    end
    return false
end

-- Helper: Get player's current grade level
local function GetPlayerGrade(citizenid)
    local player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if player then
        return player.PlayerData.job.grade or 0
    else
        -- Offline: fetch from database
        local result = MySQL.query.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', {citizenid})
        if result and result[1] then
            local jobData = json.decode(result[1].job)
            return jobData.grade or 0
        end
    end
    return 0
end

-- Helper: Get highest boss grade for a job
local function GetHighestBossGrade(jobName)
    local grades = GetJobGrades(jobName)
    local highestBoss = -1
    for gradeLevel, grade in pairs(grades) do
        if grade.isboss then
            highestBoss = math.max(highestBoss, tonumber(gradeLevel) or 0)
        end
    end
    return highestBoss >= 0 and highestBoss or nil
end

-- Helper: Get next lower grade for demotion
local function GetLowerGrade(jobName, currentGrade)
    local grades = GetJobGrades(jobName)
    currentGrade = tonumber(currentGrade) or 0
    
    local lowerGrades = {}
    for gradeLevel, _ in pairs(grades) do
        local level = tonumber(gradeLevel) or 0
        if level < currentGrade then
            table.insert(lowerGrades, level)
        end
    end
    
    if #lowerGrades > 0 then
        table.sort(lowerGrades, function(a, b) return a > b end)
        return lowerGrades[1]
    end
    return 0
end

-- Helper: Get next higher grade for promotion
local function GetHigherGrade(jobName, currentGrade)
    local grades = GetJobGrades(jobName)
    currentGrade = tonumber(currentGrade) or 0
    
    local higherGrades = {}
    for gradeLevel, _ in pairs(grades) do
        local level = tonumber(gradeLevel) or 0
        if level > currentGrade then
            table.insert(higherGrades, level)
        end
    end
    
    if #higherGrades > 0 then
        table.sort(higherGrades)
        return higherGrades[1]
    end
    return currentGrade
end

-- ============================================================================
-- STAFF CHANGES: who may act on whom
-- ============================================================================
-- These handlers used to take any citizen id: a shop manager could fire a police officer, pull any
-- player into the shop at any grade, or set their own grade. Now the caller must be a manager of their
-- own shop, the target must work at that shop (and not be the caller), and both the target's grade
-- and any new grade must be below the caller's (a boss may also act up to their own grade).

local function gradeOf(job)
    local g = job and job.grade
    if type(g) == 'table' then return tonumber(g.level or g.grade) or 0 end
    return tonumber(g) or 0
end

local function jobOfCitizen(citizenid)
    local online = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if online then return online.PlayerData.job end
    local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row or not row.job then return nil end
    local ok, job = pcall(json.decode, row.job)
    return ok and type(job) == 'table' and job or nil
end

local function staffContext(src, targetCid)
    local Player = QBCore.Functions.GetPlayer(src)
    local business = GetBusinessForSource(src)
    if not Player or not business then return nil, 'invalid_manager' end
    if type(targetCid) ~= 'string' or targetCid == '' or #targetCid > 64 then return nil, 'invalid_target' end
    if targetCid == Player.PlayerData.citizenid then return nil, 'self' end
    if not IsEmployeeManager(Player.PlayerData.citizenid) then return nil, 'not_authorized' end
    local targetJob = jobOfCitizen(targetCid)
    if not targetJob or targetJob.name ~= business then return nil, 'not_employee' end
    local ctx = {
        business = business,
        player = Player,
        myGrade = gradeOf(Player.PlayerData.job),
        isBoss = Player.PlayerData.job.isboss == true,
        targetGrade = gradeOf(targetJob),
    }
    if not (ctx.targetGrade < ctx.myGrade or (ctx.isBoss and ctx.targetGrade <= ctx.myGrade)) then
        return nil, 'rank'
    end
    return ctx
end

local function gradeAllowed(ctx, grade)
    grade = tonumber(grade)
    if not grade or grade ~= math.floor(grade) or grade < 0 then return false end
    return grade < ctx.myGrade or (ctx.isBoss and grade <= ctx.myGrade)
end

local function staffDenied(src, reason)
    TriggerClientEvent('chat:addMessage', src, {
        color = {255, 0, 0},
        multiline = true,
        args = {"Management", "You can't do that (" .. tostring(reason) .. ")"}
    })
end

-- ============================================================================
-- INITIALIZATION ON RESOURCE START
-- ============================================================================

-- (Not a network event: it was registered as one, so a client could trigger it.)
AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        InitializeBusinessSettings()
        TriggerEvent('chat:addMessage', {
            color = {0, 255, 0},
            multiline = true,
            args = {"Management", "Initialized business settings"}
        })
    end
end)

function InitializeBusinessSettings()
    -- Check if business settings exists
    local result = MySQL.query.await('SELECT COUNT(*) as count FROM pf_business_settings')
    
    if result[1].count == 0 then
        -- Insert default settings
        MySQL.insert.await(
            'INSERT INTO pf_business_settings (business_name, blip_name, blip_color) VALUES (?, ?, ?)',
            {
                Config.ManagementApp.DefaultBusinessName,
                Config.ManagementApp.DefaultBlipName,
                Config.ManagementApp.DefaultBlipColor
            }
        )
        if Config.Debug then
            PFMech.Debug('^2[Management]^7 Default business settings created')
        end
    end
end

-- ============================================================================
-- CALLBACKS - FETCH MANAGEMENT DATA
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mechanic:getManagementData', function(source, cb)
    local business = GetBusinessForSource(source)
    if not business then
        if Config.Debug then
            PFMech.Debug('^3[Management]^7 Player not allowed for management app: ' .. tostring(source))
        end
        cb(nil)
        return
    end

    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then
        if Config.Debug then
            PFMech.Debug('^1[Management Error]^7 Player not found for source: ' .. source)
        end
        cb(nil)
        return
    end

    local citizenid = xPlayer.PlayerData.citizenid
    local permissionLevel = GetEmployeeRole(citizenid, business) -- 'owner', 'manager', 'employee'

    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Fetching data for: ' .. citizenid .. ' (Role: ' .. (permissionLevel or 'none') .. ')')
    end

    -- Fetch sales data
    local last7Total = GetSalesTotal(7, business)
    local last30Total = GetSalesTotal(30, business)
    local todayTotal = GetSalesTotal(0, business)
    local salesChartData = GetSalesChartData(30, business)

    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Sales - Last7: $' .. last7Total .. ', Last30: $' .. last30Total .. ', Today: $' .. todayTotal)
    end

    -- Fetch employees with stats
    local employees = GetEmployeesWithStats(business)
    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Employees found: ' .. #employees)
    end

    -- Fetch products
    local products = GetAllProducts()
    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Products found: ' .. #products)
    end

    -- Fetch inventory
    local inventory = GetInventory()
    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Inventory items found: ' .. #inventory)
    end

    -- Fetch business settings
    local businessSettings = GetBusinessSettings()

    local data = {
        businessName = businessSettings.business_name,
        last7Total = last7Total,
        last30Total = last30Total,
        todayTotal = todayTotal,
        salesChartData = salesChartData,
        employees = employees,
        products = products,
        inventory = inventory,
        businessSettings = businessSettings,
        permissionLevel = permissionLevel
    }

    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Data sent to client for: ' .. citizenid)
    end
    cb(data)
end)

-- ============================================================================
-- SALES DATA FUNCTIONS
-- ============================================================================

function GetSalesTotal(daysAgo, business)
    local b = business or 'mechanic'
    local result

    if daysAgo == 0 then
        result = MySQL.query.await(
            'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE business = ? AND DATE(created_at) = CURDATE()',
            {b}
        )
    else
        result = MySQL.query.await(
            'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE business = ? AND created_at >= NOW() - INTERVAL ? DAY',
            {b, daysAgo}
        )
    end

    local total = (result and result[1] and result[1].total) or 0
    print('^2[Sales Query]^7 Days: ' .. daysAgo .. ' Total: $' .. total .. ' (Business: ' .. b .. ')')
    return total
end

function GetSalesChartData(days, business)
    local b = business or 'mechanic'
    days = days or 30
    
    -- First, check if table has data at all
    local countResult = MySQL.query.await('SELECT COUNT(*) as cnt FROM pf_pos_transactions WHERE business = ?', {b}) or {}
    local totalRecords = 0
    if countResult and countResult[1] then
        totalRecords = tonumber(countResult[1].cnt) or 0
    end
    print('^2[Chart Init]^7 Total transactions for business "' .. b .. '": ' .. totalRecords)
    
    -- Query sales for the last N days, grouped by day
    -- Use DATE_SUB with INTERVAL (days-1) to get full N-day range
    local result = MySQL.query.await(
        'SELECT DATE_FORMAT(created_at, "%Y-%m-%d") as day, COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE business = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL ? DAY) GROUP BY DATE(created_at) ORDER BY day ASC',
        {b, days - 1}
    ) or {}

    print('^2[Chart Query]^7 Days: ' .. days .. ' | Rows returned: ' .. #result .. ' (Business: ' .. b .. ')')

    -- Build a map of existing data by day string
    local dataByDay = {}
    local totalSum = 0
    for _, row in ipairs(result) do
        local total = tonumber(row.total) or 0
        local dayStr = tostring(row.day)
        -- Some MySQL drivers return DATE as a datetime-ish string; force YYYY-MM-DD
        if #dayStr >= 10 then dayStr = dayStr:sub(1, 10) end
        dataByDay[dayStr] = total
        totalSum = totalSum + total
        print('^3[Chart Data Row]^7 ' .. dayStr .. ' = ' .. total)
    end
    print('^2[Chart Total]^7 Sum of all sales: ' .. totalSum)

    -- Generate EXACTLY N days (fill gaps with 0) from oldest to newest
    local chartData = {}
    for i = days - 1, 0, -1 do
        local timestamp = os.time() - (i * 86400)
        local dateTable = os.date('*t', timestamp)
        local dayStr = string.format('%04d-%02d-%02d', dateTable.year, dateTable.month, dateTable.day)
        local total = tonumber(dataByDay[dayStr]) or 0
        total = tonumber(total) or 0
        table.insert(chartData, {
            day = dayStr,
            total = total
        })
    end

    print('^2[Chart Generated]^7 ' .. #chartData .. ' days in chart data')
    return chartData
end

-- ============================================================================
-- NEW: BUSINESS-KEYED MANAGEMENT CALLBACKS
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mechanic:getSalesOverview', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb(nil) return end

    local result7 = MySQL.single.await('SELECT SUM(amount) AS total FROM pf_mechanic_transactions WHERE business = ? AND `timestamp` >= DATE_SUB(NOW(), INTERVAL 7 DAY)', {business}) or {}
    local result30 = MySQL.single.await('SELECT SUM(amount) AS total FROM pf_mechanic_transactions WHERE business = ? AND `timestamp` >= DATE_SUB(NOW(), INTERVAL 30 DAY)', {business}) or {}
    local resultToday = MySQL.single.await('SELECT SUM(amount) AS total FROM pf_mechanic_transactions WHERE business = ? AND DATE(`timestamp`) = CURDATE()', {business}) or {}

    cb({
        last7 = result7.total or 0,
        last30 = result30.total or 0,
        today = resultToday.total or 0
    })
end)

QBCore.Functions.CreateCallback('pf_mechanic:getSalesGraph', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb({}) return end

    local rows = MySQL.query.await([[ 
        SELECT DATE(`timestamp`) AS day, SUM(amount) AS total
        FROM pf_mechanic_transactions
        WHERE business = ? AND `timestamp` >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY DATE(`timestamp`)
        ORDER BY day ASC
    ]], {business})

    cb(rows or {})
end)

QBCore.Functions.CreateCallback('pf_mechanic:getEmployeesForBusiness', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb({}) return end

    local employees = MySQL.query.await([[ 
        SELECT 
            p.citizenid, 
            CONCAT(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))) AS name,
            COALESCE(JSON_EXTRACT(p.job, '$.grade.level'), JSON_EXTRACT(p.job, '$.grade')) AS job_grade,
            e.role AS persisted_role,
            e.hired_at AS hired_at
        FROM players p
        LEFT JOIN pf_business_employees e ON e.citizenid = p.citizenid
        WHERE JSON_EXTRACT(p.job, '$.name') = ?
    ]], {business}) or {}

    local salesAll = MySQL.query.await([[ 
        SELECT employee, 
            SUM(amount) AS total,
            SUM(CASE WHEN `timestamp` >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN amount ELSE 0 END) AS sales7,
            SUM(CASE WHEN `timestamp` >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN amount ELSE 0 END) AS sales30
        FROM pf_mechanic_transactions
        WHERE business = ?
        GROUP BY employee
    ]], {business}) or {}

    local salesMap = {}
    for _, row in ipairs(salesAll) do
        salesMap[row.employee] = {
            total = row.total or 0,
            sales7 = row.sales7 or 0,
            sales30 = row.sales30 or 0
        }
    end

    local onlineList = {}
    for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do
        if Player.PlayerData.job and Player.PlayerData.job.name == business then
            onlineList[Player.PlayerData.citizenid] = true
        end
    end

    local result = {}
    for _, emp in ipairs(employees) do
        local s = salesMap[emp.citizenid] or { total = 0, sales7 = 0, sales30 = 0 }
        result[#result + 1] = {
            citizenid = emp.citizenid,
            name = emp.name,
            grade = emp.job_grade,
            online = onlineList[emp.citizenid] == true,
            sales7 = s.sales7,
            sales30 = s.sales30,
            totalSales = s.total,
            role = emp.persisted_role or GetEmployeeRole(emp.citizenid, business),
            hired_at = emp.hired_at
        }
    end

    cb(result)
end)

QBCore.Functions.CreateCallback('pf_mechanic:getPricing', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb({}) return end

    local products = MySQL.query.await('SELECT * FROM pf_mechanic_products WHERE business = ?', {business}) or {}
    cb(products)
end)

-- Prices and settings are for managers (any employee could change them), and prices can't be negative.
local function managerBusiness(src)
    local business = GetBusinessForSource(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not business or not Player or not IsEmployeeManager(Player.PlayerData.citizenid) then return nil end
    return business
end

local function validPrice(v)
    v = tonumber(v)
    if not v or v ~= v or v < 0 or v > 10000000 then return nil end
    return v
end

RegisterNetEvent('pf_mechanic:updatePrice', function(productId, newPrice)
    local src = source
    local business = managerBusiness(src)
    if not business then return end
    newPrice = validPrice(newPrice)
    if not newPrice or not tonumber(productId) then return end

    MySQL.update.await('UPDATE pf_mechanic_products SET price = ? WHERE id = ? AND business = ?', {newPrice, tonumber(productId), business})
end)

RegisterNetEvent('pf_mechanic:addProduct', function(data)
    local src = source
    local business = managerBusiness(src)
    if not business then return end

    if type(data) ~= 'table' or type(data.name) ~= 'string' or type(data.category) ~= 'string' then return end
    local price = validPrice(data.price)
    if not price then return end

    MySQL.insert.await('INSERT INTO pf_mechanic_products (business, category, name, price) VALUES (?, ?, ?, ?)', {
        business, data.category:sub(1, 50), data.name:sub(1, 80), price
    })
end)

RegisterNetEvent('pf_mechanic:deleteProduct', function(productId)
    local src = source
    local business = managerBusiness(src)
    if not business then return end

    MySQL.update.await('DELETE FROM pf_mechanic_products WHERE id = ? AND business = ?', {productId, business})
end)

RegisterNetEvent('pf_mechanic:addCategory', function(categoryName)
    -- Categories are implicit via pf_mechanic_products.category; no-op besides guard
    local business = GetBusinessForSource(source)
    if not business then return end
    -- Nothing to persist; category exists once a product uses it
end)

QBCore.Functions.CreateCallback('pf_mechanic:getSettings', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb(nil) return end

    local row = MySQL.single.await('SELECT * FROM pf_mechanic_settings WHERE business = ?', {business})
    if not row then
        row = { business = business, markup = 0 }
        MySQL.insert.await('INSERT INTO pf_mechanic_settings (business, markup) VALUES (?, ?)', {business, 0})
    end

    cb(row)
end)

RegisterNetEvent('pf_mechanic:updateSettings', function(settings)
    local src = source
    local business = managerBusiness(src)
    if not business then return end

    local markup = type(settings) == 'table' and tonumber(settings.markup) or 0
    if not markup or markup ~= markup or markup < 0 then markup = 0 end
    if markup > 1000 then markup = 1000 end
    MySQL.update.await('UPDATE pf_mechanic_settings SET markup = ? WHERE business = ?', {markup, business})
end)

-- ============================================================================
-- EMPLOYEE FUNCTIONS
-- ============================================================================

function GetEmployeesWithStats(business)
    local b = business or 'mechanic'
    local result = MySQL.query.await(
        'SELECT citizenid, CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.firstname")), " ", JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.lastname"))) as name FROM players WHERE JSON_EXTRACT(job, "$.name") = ? LIMIT 50',
        {b}
    )

    local employees = {}
    if result and #result > 0 then
        for i, emp in ipairs(result) do
            local existingEmp = MySQL.query.await(
                'SELECT id, role, hired_at FROM pf_business_employees WHERE citizenid = ?',
                {emp.citizenid}
            )
            
            local role = 'employee'
            local hired_at = os.date('%Y-%m-%d %H:%M:%S')
            
            if existingEmp and existingEmp[1] then
                role = existingEmp[1].role
                hired_at = existingEmp[1].hired_at
            else
                MySQL.insert.await(
                    'INSERT IGNORE INTO pf_business_employees (citizenid, name, role, hired_at) VALUES (?, ?, ?, ?)',
                    {emp.citizenid, emp.name, role, hired_at}
                )
            end
            
            local totalSalesResult = MySQL.query.await(
                'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ?',
                {emp.citizenid, b}
            )
            local last7SalesResult = MySQL.query.await(
                'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ? AND created_at >= NOW() - INTERVAL 7 DAY',
                {emp.citizenid, b}
            )
            local last30SalesResult = MySQL.query.await(
                'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ? AND created_at >= NOW() - INTERVAL 30 DAY',
                {emp.citizenid, b}
            )

            table.insert(employees, {
                id = i,
                citizenid = emp.citizenid,
                name = emp.name,
                role = role,
                hired_at = hired_at,
                totalSales = (totalSalesResult and totalSalesResult[1] and totalSalesResult[1].total) or 0,
                last7Sales = (last7SalesResult and last7SalesResult[1] and last7SalesResult[1].total) or 0,
                last30Sales = (last30SalesResult and last30SalesResult[1] and last30SalesResult[1].total) or 0
            })
        end
    end

    return employees
end

function GetEmployeeRole(citizenid, jobName)
    -- Prefer persistent role from pf_business_employees if available
    local empRow = MySQL.query.await('SELECT role FROM pf_business_employees WHERE citizenid = ? LIMIT 1', {citizenid})
    if empRow and empRow[1] and empRow[1].role then
        return empRow[1].role
    end

    -- Fallback: derive role from current QBCore job grade
    local playerResult = MySQL.query.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', {citizenid})
    if playerResult and playerResult[1] then
        local jobData = json.decode(playerResult[1].job)
        if jobData and jobData.name and AllowedJobs[jobData.name] then
            jobName = jobName or jobData.name
            local gradeLevel = jobData.grade or 0
            return GetRoleFromGrade(jobName, gradeLevel)
        end
    end

    return 'employee'
end

function IsEmployeeManager(citizenid)
    local role = GetEmployeeRole(citizenid)
    return role == 'owner' or role == 'manager'
end

-- ============================================================================
-- PRODUCT & INVENTORY FUNCTIONS
-- ============================================================================

function GetAllProducts()
    -- Fetch from mechanic_prices table (actual cash register items)
    local businessName = GetBusinessSettings().business_name or 'mechanic'
    
    local result = MySQL.query.await(
        'SELECT id, item as id2, label as product_name, price as current_price, price as base_price, category FROM mechanic_prices WHERE business = ?',
        {businessName}
    )
    
    if not result or #result == 0 then
        -- Fallback: if no prices set, return from pf_business_products
        result = MySQL.query.await('SELECT id, product_name, base_price, current_price, created_at, updated_at FROM pf_business_products')
    end
    
    return result or {}
end

function GetInventory()
    local result = MySQL.query.await(
        'SELECT inv.id, inv.product_id, prod.product_name, inv.quantity FROM pf_business_inventory inv LEFT JOIN pf_business_products prod ON inv.product_id = prod.id'
    )
    return result or {}
end

-- ============================================================================
-- BUSINESS SETTINGS
-- ============================================================================

function GetBusinessSettings()
    local result = MySQL.query.await('SELECT * FROM pf_business_settings LIMIT 1')
    
    if result and result[1] then
        return result[1]
    end

    -- Fallback defaults
    return {
        id = 1,
        business_name = Config.ManagementApp.DefaultBusinessName,
        blip_name = Config.ManagementApp.DefaultBlipName,
        blip_color = Config.ManagementApp.DefaultBlipColor
    }
end

-- ============================================================================
-- EMPLOYEE MANAGEMENT EVENTS
-- ============================================================================

-- Hire Employee
RegisterNetEvent('pf_mechanic:hireEmployee', function(playerId)
    local business = GetBusinessForSource(source)
    if not business then return end

    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then return end

    -- Check permission
    if not IsEmployeeManager(xPlayer.PlayerData.citizenid) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "You don't have permission to hire employees"}
        })
        return
    end

    -- Get target player
    local targetPlayer = QBCore.Functions.GetPlayer(playerId)
    if not targetPlayer then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "Player not found"}
        })
        return
    end

    if targetPlayer.PlayerData.job.name ~= business then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "Target is not part of this business"}
        })
        return
    end

    local targetCitizenid = targetPlayer.PlayerData.citizenid
    local targetName = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname

    -- Check if already employed
    local existing = MySQL.query.await('SELECT id FROM pf_business_employees WHERE citizenid = ? LIMIT 1', {targetCitizenid})
    
    if existing and existing[1] then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "This player is already employed"}
        })
        return
    end

    -- Hire employee
    MySQL.insert.await(
        'INSERT INTO pf_business_employees (citizenid, name, role) VALUES (?, ?, ?)',
        {targetCitizenid, targetName, 'employee'}
    )

    -- Set target job to mechanic if not already
    targetPlayer.Functions.SetJob(business, 0)

    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", targetName .. " has been hired"}
    })

    TriggerClientEvent('chat:addMessage', playerId, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "You have been hired as a mechanic"}
    })
end)

-- Promote Employee
RegisterNetEvent('pf_mechanic:promoteEmployee', function(targetCitizenid)
    local src = source
    local ctx, why = staffContext(src, targetCitizenid)
    if not ctx then return staffDenied(src, why) end

    -- Get next higher grade
    local currentGrade = ctx.targetGrade
    local newGrade = GetHigherGrade(ctx.business, currentGrade)

    if newGrade == currentGrade then
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "Employee is already at max rank"}
        })
        return
    end
    if not gradeAllowed(ctx, newGrade) then return staffDenied(src, 'rank') end

    -- Update QBCore job grade
    local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if targetPlayer then
        targetPlayer.Functions.SetJob(ctx.business, newGrade)
    else
        -- Offline: update players table
        MySQL.update.await(
            'UPDATE players SET job = JSON_SET(job, "$.grade", ?) WHERE citizenid = ?',
            {newGrade, targetCitizenid}
        )
    end

    -- Update promotion timestamp
    MySQL.update.await(
        'UPDATE pf_business_employees SET last_promoted_at = NOW() WHERE citizenid = ?',
        {targetCitizenid}
    )

    local newRole = GetRoleFromGrade(ctx.business, newGrade)
    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Employee promoted to " .. newRole}
    })
end)

-- Demote Employee
RegisterNetEvent('pf_mechanic:demoteEmployee', function(targetCitizenid)
    local src = source
    local ctx, why = staffContext(src, targetCitizenid)
    if not ctx then return staffDenied(src, why) end

    -- Get next lower grade
    local currentGrade = ctx.targetGrade
    local newGrade = GetLowerGrade(ctx.business, currentGrade)

    if newGrade == currentGrade then
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "Employee is already at min rank"}
        })
        return
    end

    -- Update QBCore job grade
    local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if targetPlayer then
        targetPlayer.Functions.SetJob(ctx.business, newGrade)
    else
        -- Offline: update players table
        MySQL.update.await(
            'UPDATE players SET job = JSON_SET(job, "$.grade", ?) WHERE citizenid = ?',
            {newGrade, targetCitizenid}
        )
    end

    -- Update promotion timestamp
    MySQL.update.await(
        'UPDATE pf_business_employees SET last_promoted_at = NOW() WHERE citizenid = ?',
        {targetCitizenid}
    )

    local newRole = GetRoleFromGrade(ctx.business, newGrade)
    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Employee demoted to " .. newRole}
    })
end)

-- Fire Employee
RegisterNetEvent('pf_mechanic:fireEmployee', function(targetCitizenid)
    local src = source
    local ctx, why = staffContext(src, targetCitizenid)
    if not ctx then return staffDenied(src, why) end

    MySQL.delete.await('DELETE FROM pf_business_employees WHERE citizenid = ?', {targetCitizenid})

    -- Set target job to unemployed if online
    local target = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if target then
        target.Functions.SetJob('unemployed', 0)
    else
        -- Offline: update players table
        MySQL.update.await(
            'UPDATE players SET job = JSON_SET(job, "$.name", "unemployed", "$.grade", 0) WHERE citizenid = ?',
            {targetCitizenid}
        )
    end

    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Employee fired"}
    })
end)

-- Set employee to specific role/grade via dropdown
local AssignableRoles = { employee = true, manager = true, owner = true }

RegisterNetEvent('pf_mechanic:setEmployeeRole', function(targetCitizenid, role, grade)
    local src = source
    local ctx, why = staffContext(src, targetCitizenid)
    if not ctx then return staffDenied(src, why) end

    grade = tonumber(grade) or 0
    if type(role) ~= 'string' or not AssignableRoles[role] then return staffDenied(src, 'role') end
    -- only an owner can make another owner
    if role == 'owner' and GetEmployeeRole(ctx.player.PlayerData.citizenid) ~= 'owner' then return staffDenied(src, 'role') end
    if not gradeAllowed(ctx, grade) then return staffDenied(src, 'rank') end

    -- Update QBCore job for target
    local target = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if target then
        target.Functions.SetJob(ctx.business, grade)
    else
        -- Offline: update players table
        MySQL.update.await(
            'UPDATE players SET job = JSON_SET(job, "$.name", ?, "$.grade", ?) WHERE citizenid = ?',
            {ctx.business, grade, targetCitizenid}
        )
    end

    -- Update management role with promotion timestamp
    MySQL.update.await(
        'UPDATE pf_business_employees SET role = ?, last_promoted_at = NOW() WHERE citizenid = ?',
        {role, targetCitizenid}
    )

    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Employee role updated to " .. role}
    })
end)

-- ============================================================================
-- EMPLOYEE STATS CALLBACK
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mechanic:getEmployeeStats', function(source, cb, citizenid)
    local business = GetBusinessForSource(source)
    if not business then cb(nil) return end

    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then cb(nil) return end
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 then cb(nil) return end
    local targetJob = jobOfCitizen(citizenid)
    if not targetJob or targetJob.name ~= business then cb(nil) return end

    local employee = MySQL.query.await('SELECT * FROM pf_business_employees WHERE citizenid = ? LIMIT 1', {citizenid})
    
    if not employee or not employee[1] then
        cb(nil)
        return
    end

    local emp = employee[1]
    
    -- Get live role from QBCore job grade
    local liveRole = GetEmployeeRole(citizenid, business)
    
    -- Calculate sales from POS transactions
    local totalSalesResult = MySQL.query.await(
        'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ?',
        {citizenid, business}
    )
    local last7SalesResult = MySQL.query.await(
        'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ? AND created_at >= NOW() - INTERVAL 7 DAY',
        {citizenid, business}
    )
    local last30SalesResult = MySQL.query.await(
        'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ? AND created_at >= NOW() - INTERVAL 30 DAY',
        {citizenid, business}
    )

    -- Get actual POS transactions
    local transactions = MySQL.query.await(
        'SELECT transaction_id, created_at, items, total, payment_type FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ? ORDER BY created_at DESC LIMIT 50',
        {citizenid, business}
    )

    -- Get today's sales
    local todaySalesResult = MySQL.query.await(
        'SELECT COALESCE(SUM(total), 0) as total FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ? AND DATE(created_at) = CURDATE()',
        {citizenid, business}
    )

    -- Get completed work order count
    local completedCountResult = MySQL.query.await(
        'SELECT COUNT(*) AS cnt FROM pf_work_orders WHERE assigned_to = ? AND status = "complete"',
        {citizenid}
    )
    local completedCount = (completedCountResult and completedCountResult[1] and completedCountResult[1].cnt) or 0

    -- Fallback to progression table if no historical rows exist yet
    if completedCount == 0 then
        local progressRow = MySQL.query.await('SELECT total_jobs FROM pf_mechanic_progress WHERE citizenid = ? LIMIT 1', {citizenid})
        if progressRow and progressRow[1] and progressRow[1].total_jobs then
            completedCount = progressRow[1].total_jobs
        end
    end

    -- Get completed work orders
    local workOrders = MySQL.query.await(
        'SELECT id, type, plate, veh_model, payout, quality, created_at, updated_at FROM pf_work_orders WHERE assigned_to = ? AND status = ? ORDER BY updated_at DESC LIMIT 50',
        {citizenid, 'complete'}
    )

    cb({
        currentPlayerCid = xPlayer.PlayerData.citizenid,
        employee = {
            citizenid = emp.citizenid,
            name = emp.name,
            role = liveRole,
            hiredAt = emp.hired_at,
            lastPromotedAt = emp.last_promoted_at,
            totalSales = (totalSalesResult and totalSalesResult[1] and totalSalesResult[1].total) or 0,
            last7Sales = (last7SalesResult and last7SalesResult[1] and last7SalesResult[1].total) or 0,
            last30Sales = (last30SalesResult and last30SalesResult[1] and last30SalesResult[1].total) or 0,
            todaySales = (todaySalesResult and todaySalesResult[1] and todaySalesResult[1].total) or 0,
            completedWorkOrders = completedCount
        },
        transactions = transactions or {},
        workOrders = workOrders or {}
    })
end)

-- ============================================================================
-- TRANSFER OWNERSHIP
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mechanic:getNearbyPlayersAndEmployees', function(source, cb)
    local business = GetBusinessForSource(source)
    if not business then cb({}) return end

    -- Get all employees for this business
    local employees = MySQL.query.await([[
        SELECT citizenid, name FROM pf_business_employees WHERE role IN ('employee', 'manager')
    ]]) or {}

    -- Get nearby players (within 50 units)
    local nearbyPlayers = {}
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if player then
        local coords = GetEntityCoords(GetPlayerPed(src))
        for _, otherPlayer in pairs(QBCore.Functions.GetQBPlayers()) do
            if otherPlayer.PlayerData.source ~= src then
                local otherCoords = GetEntityCoords(GetPlayerPed(otherPlayer.PlayerData.source))
                if #(coords - otherCoords) < 50 then
                    table.insert(nearbyPlayers, {
                        citizenid = otherPlayer.PlayerData.citizenid,
                        player_name = otherPlayer.PlayerData.charinfo.firstname .. ' ' .. otherPlayer.PlayerData.charinfo.lastname
                    })
                end
            end
        end
    end

    cb({
        employees = employees,
        nearbyPlayers = nearbyPlayers
    })
end)

RegisterNetEvent('pf_mechanic:transferOwnership', function(newOwnerCid)
    local src = source
    local business = GetBusinessForSource(src)
    if not business then return end

    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end

    -- Check if current player is owner
    local currentRole = GetEmployeeRole(xPlayer.PlayerData.citizenid)
    if currentRole ~= 'owner' then
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "You must be the owner to transfer ownership"}
        })
        return
    end

    -- The new owner must already work here, or be standing next to the owner (the UI offers employees
    -- and nearby players). Any citizen id used to be accepted and moved into the shop.
    if type(newOwnerCid) ~= 'string' or newOwnerCid == '' or #newOwnerCid > 64
        or newOwnerCid == xPlayer.PlayerData.citizenid then return end
    local newOwnerJob = jobOfCitizen(newOwnerCid)
    local works = newOwnerJob and newOwnerJob.name == business
    if not works then
        local online = QBCore.Functions.GetPlayerByCitizenId(newOwnerCid)
        local near = online and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(online.PlayerData.source))) <= 10.0
        if not near then return staffDenied(src, 'not_employee') end
    end

    -- Make new owner
    MySQL.update.await(
        'UPDATE pf_business_employees SET role = ? WHERE citizenid = ?',
        {'owner', newOwnerCid}
    )

    -- Set current owner to unemployed
    local currentOwnerCid = xPlayer.PlayerData.citizenid
    xPlayer.Functions.SetJob('unemployed', 0)
    MySQL.update.await(
        'UPDATE pf_business_employees SET role = ? WHERE citizenid = ?',
        {'employee', currentOwnerCid}
    )

    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Ownership transferred. You are now unemployed."}
    })

    -- Notify new owner if online
    local newOwner = QBCore.Functions.GetPlayerByCitizenId(newOwnerCid)
    if newOwner then
        TriggerClientEvent('chat:addMessage', newOwner.PlayerData.source, {
            color = {0, 255, 0},
            multiline = true,
            args = {"Management", "You are now the owner of " .. business}
        })
        newOwner.Functions.SetJob(business, 0)
    else
        -- Set offline player's job
        MySQL.update.await(
            'UPDATE players SET job = JSON_SET(job, "$.name", ?, "$.grade", 0) WHERE citizenid = ?',
            {business, newOwnerCid}
        )
    end
end)

-- ============================================================================
-- PRODUCT MANAGEMENT
-- ============================================================================

RegisterNetEvent('pf_mechanic:updateProductPrice', function(productItem, newPrice)
    local business = GetBusinessForSource(source)
    if not business then return end

    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then return end

    if not IsEmployeeManager(xPlayer.PlayerData.citizenid) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "You don't have permission"}
        })
        return
    end

    -- the register bills from this table: no negative or junk prices
    newPrice = validPrice(newPrice)
    if not newPrice or type(productItem) ~= 'string' or #productItem > 64 then return end

    -- Update price in mechanic_prices table (business-specific)
    MySQL.update.await(
        'UPDATE mechanic_prices SET price = ? WHERE business = ? AND item = ?',
        {newPrice, business, productItem}
    )

    print('^2[Management]^7 Price updated - Business: ' .. business .. ', Item: ' .. productItem .. ', Price: $' .. newPrice)

    -- Notify
    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Product price updated to $" .. newPrice}
    })
end)

-- ============================================================================
-- BUSINESS SETTINGS
-- ============================================================================

RegisterNetEvent('pf_mechanic:saveBusinessSettings', function(data)
    local business = GetBusinessForSource(source)
    if not business then return end

    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then return end

    if not IsEmployeeManager(xPlayer.PlayerData.citizenid) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "You don't have permission"}
        })
        return
    end

    if type(data) ~= 'table' then return end
    MySQL.update.await(
        'UPDATE pf_business_settings SET business_name = ?, blip_name = ?, blip_color = ? WHERE id = 1',
        {tostring(data.business_name or ''):sub(1, 64), tostring(data.blip_name or ''):sub(1, 64), tonumber(data.blip_color) or 3}
    )

    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Business settings saved"}
    })
end)

-- ============================================================================
-- LOCATION PLACEMENT
-- ============================================================================

RegisterNetEvent('pf_mechanic:setLocation', function(locData)
    local business = GetBusinessForSource(source)
    if not business then return end

    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then return end

    if not IsEmployeeManager(xPlayer.PlayerData.citizenid) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "You don't have permission"}
        })
        return
    end

    if type(locData) ~= 'table' or type(locData.type) ~= 'string' or #locData.type > 32
        or not tonumber(locData.x) or not tonumber(locData.y) or not tonumber(locData.z) then return end
    local locationType = locData.type

    -- For stash_shared and duty, delete existing locations of that type
    if locationType == 'stash_shared' or locationType == 'duty' then
        MySQL.delete.await('DELETE FROM pf_business_locations WHERE type = ?', {locationType})
    end

    -- Insert new location
    MySQL.insert.await(
        'INSERT INTO pf_business_locations (type, x, y, z, heading, is_prop, prop_model, citizenid) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        {
            locationType,
            locData.x,
            locData.y,
            locData.z,
            locData.heading or 0,
            locData.is_prop or 0,
            locData.prop_model or nil,
            xPlayer.PlayerData.citizenid
        }
    )

    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Location saved: " .. locationType}
    })

    -- Reload locations on all clients
    TriggerEvent('pf_mechanic:reloadLocations')
end)

-- ============================================================================
-- SALES LOGGING
-- ============================================================================
-- This is called from your existing sale completion logic
-- Example: After a successful cash register transaction
function LogBusinessSale(citizenid, employeeName, productId, productName, quantity, totalPrice)
    MySQL.insert.await(
        'INSERT INTO pf_business_sales (citizenid, employee_name, product_id, product_name, quantity, total_price) VALUES (?, ?, ?, ?, ?, ?)',
        {citizenid, employeeName, productId, productName, quantity, totalPrice}
    )
end

-- Export for use in other scripts
exports('LogBusinessSale', LogBusinessSale)

-- ============================================================================
-- LOAD LOCATIONS ON STARTUP
-- ============================================================================

-- Server-only (raised by setLocation and on start); as a network event any client could make the
-- server re-read the table and broadcast it to everyone, as often as it liked.
AddEventHandler('pf_mechanic:reloadLocations', function()
    local locations = MySQL.query.await('SELECT * FROM pf_business_locations')
    
    if locations then
        -- Send to all clients to create zones/targets
        TriggerClientEvent('pf_mechanic:syncLocations', -1, locations)
    end
end)

-- ============================================================================
-- MANAGEMENT DATA REFRESH FUNCTION (Called after charges, etc.)
-- ============================================================================

function RefreshManagementDataForBusiness(business)
    if not business then return end
    
    -- Get all online players in this business
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        if Player and Player.PlayerData and Player.PlayerData.job then
            -- only that shop's staff (the old `or AllowedJobs[business]` sent it to every player)
            if Player.PlayerData.job.name == business then
                -- Get updated sales data
                local last7Total = GetSalesTotal(7, business)
                local last30Total = GetSalesTotal(30, business)
                local todayTotal = GetSalesTotal(0, business)
                local salesChartData = GetSalesChartData(30, business)
                
                -- Send updated overview data to this player
                TriggerClientEvent('pf_mechanic:refreshManagementOverview', Player.PlayerData.source, {
                    last7 = last7Total,
                    last30 = last30Total,
                    today = todayTotal,
                    chartData = salesChartData
                })
            end
        end
    end
end

-- Event: Refresh management data (server-only: register_pos.lua raises it after a sale). As a network
-- event any client could name a shop and have its sales figures sent to every online player.
AddEventHandler('pf_mechanic:refreshManagementData', function(business)
    RefreshManagementDataForBusiness(business)
end)

-- Initial load
TriggerEvent('pf_mechanic:reloadLocations')

-- ============================================================================
-- ENHANCED MANAGEMENT API (PF TABLET MODULE)
-- ============================================================================

local function ensureManagementSchema()
    pcall(function()
        MySQL.query.await('ALTER TABLE pf_business_employees ADD COLUMN IF NOT EXISTS business VARCHAR(50) NULL')
        MySQL.query.await('ALTER TABLE pf_business_employees ADD COLUMN IF NOT EXISTS grade INT NOT NULL DEFAULT 0')
        MySQL.query.await('ALTER TABLE pf_business_employees ADD COLUMN IF NOT EXISTS salary INT NOT NULL DEFAULT 0')
        MySQL.query.await('ALTER TABLE pf_business_employees ADD COLUMN IF NOT EXISTS avatar VARCHAR(512) NULL')
        MySQL.query.await('ALTER TABLE pf_business_employees ADD COLUMN IF NOT EXISTS last_online TIMESTAMP NULL DEFAULT NULL')
        MySQL.query.await('ALTER TABLE pf_business_employees ADD INDEX IF NOT EXISTS idx_business (business)')

        MySQL.query.await('ALTER TABLE pf_pos_transactions ADD COLUMN IF NOT EXISTS vehicle_plate VARCHAR(20) NULL')
        MySQL.query.await('ALTER TABLE pf_pos_transactions ADD COLUMN IF NOT EXISTS vehicle_model VARCHAR(80) NULL')
        MySQL.query.await('ALTER TABLE pf_pos_transactions ADD COLUMN IF NOT EXISTS service_location VARCHAR(120) NULL')
    end)
end

CreateThread(function()
    Wait(500)
    ensureManagementSchema()
end)

local function getBusinessNameByKey(business)
    local row = MySQL.single.await('SELECT name FROM pf_business WHERE business = ? LIMIT 1', { business })
    if row and row.name and row.name ~= '' then return row.name end
    local branding = Config.BusinessBranding and Config.BusinessBranding[business]
    if branding and branding.name then return branding.name end
    return business
end

local function getMostPopularService(business)
    local mandatoryRows = MySQL.query.await(
        'SELECT item FROM mechanic_mandatory_charges WHERE business = ?',
        { business }
    ) or {}

    local mandatoryItems = {}
    for _, row in ipairs(mandatoryRows) do
        if row.item and row.item ~= '' then
            mandatoryItems[row.item] = true
        end
    end

    local rows = MySQL.query.await(
        'SELECT items FROM pf_pos_transactions WHERE business = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)',
        { business }
    ) or {}

    local counts = {}
    for _, row in ipairs(rows) do
        local decoded = {}
        if row.items and row.items ~= '' then
            local ok, parsed = pcall(json.decode, row.items)
            if ok and type(parsed) == 'table' then
                decoded = parsed
            end
        end

        for _, line in ipairs(decoded) do
            local itemKey = line.item
            if itemKey and mandatoryItems[itemKey] then
                goto continue_line
            end

            local configEntry = itemKey and Config.RegisterItems and Config.RegisterItems[itemKey] or nil
            local rawLabel = (configEntry and configEntry.label) or line.label or itemKey or 'Unknown'
            local label = tostring(rawLabel or '')
            if label == '' then
                label = itemKey or 'Unknown'
            end
            if itemKey and (not configEntry or not configEntry.label or configEntry.label == '') then
                label = label:gsub('_', ' '):gsub('%f[%a](%a)', string.upper)
            end
            counts[label] = (counts[label] or 0) + (tonumber(line.qty or 1) or 1)
            ::continue_line::
        end
    end

    local topLabel, topCount = 'No services yet', 0
    for label, count in pairs(counts) do
        if count > topCount then
            topLabel = label
            topCount = count
        end
    end

    return { label = topLabel, count = topCount }
end

local function getAvatarForEmployee(citizenid, fullName)
    local row = MySQL.single.await('SELECT avatar FROM pf_business_employees WHERE citizenid = ? LIMIT 1', { citizenid })
    if row and row.avatar and row.avatar ~= '' then
        return row.avatar
    end

    local initials = 'ME'
    if fullName and fullName ~= '' then
        local first = fullName:match('^(%S+)') or ''
        local second = fullName:match('%s+(%S+)') or ''
        initials = (first:sub(1, 1) .. second:sub(1, 1)):upper()
        if initials == '' then initials = 'ME' end
    end

    return ('https://ui-avatars.com/api/?name=%s&background=0B2E44&color=ffffff&size=256'):format(initials)
end

local function upsertEmployeeRecord(citizenid, business, fullName, grade)
    MySQL.query.await([[
        INSERT INTO pf_business_employees (citizenid, name, role, hired_at, business, grade, last_online)
        VALUES (?, ?, 'employee', NOW(), ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            business = VALUES(business),
            grade = VALUES(grade),
            last_online = NOW()
    ]], { citizenid, fullName, business, tonumber(grade) or 0 })
end

local function setOfflineJobByCitizenId(citizenid, business, grade)
    local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row then
        return false, 'citizen_not_found'
    end

    local jobData = {}
    if row.job and row.job ~= '' then
        local ok, parsed = pcall(json.decode, row.job)
        if ok and type(parsed) == 'table' then
            jobData = parsed
        end
    end

    jobData.name = business
    jobData.onduty = true
    local gradeNum = tonumber(grade) or 0
    if type(jobData.grade) == 'table' then
        jobData.grade.level = gradeNum
    else
        jobData.grade = gradeNum
    end

    MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(jobData), citizenid })
    return true
end

local function getGradeFromPlayerJob(player)
    local g = player.PlayerData.job and player.PlayerData.job.grade
    if type(g) == 'table' then
        return tonumber(g.level or g.grade or 0) or 0
    end
    return tonumber(g or 0) or 0
end

local function getGradeByCitizenId(citizenid)
    local online = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if online then return getGradeFromPlayerJob(online) end

    local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row then return 0 end

    local job = {}
    local ok, parsed = pcall(json.decode, row.job or '{}')
    if ok and type(parsed) == 'table' then job = parsed end
    if type(job.grade) == 'table' then
        return tonumber(job.grade.level or job.grade.grade or 0) or 0
    end
    return tonumber(job.grade or 0) or 0
end

local function setEmployeeGrade(citizenid, business, grade)
    local online = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if online then
        online.Functions.SetJob(business, grade)
    else
        local ok = setOfflineJobByCitizenId(citizenid, business, grade)
        if not ok then return false end
    end

    MySQL.update.await(
        'UPDATE pf_business_employees SET grade = ?, role = ?, last_promoted_at = NOW() WHERE citizenid = ?',
        { grade, (grade >= 4 and 'owner' or (grade >= 2 and 'manager' or 'employee')), citizenid }
    )
    return true
end

local function getEmployeeTransactions(citizenid, business)
    local rows = MySQL.query.await([[
        SELECT transaction_id, customer_id, mechanic_name, items, subtotal, tax, total, payment_type, created_at,
               vehicle_plate, vehicle_model, service_location
        FROM pf_pos_transactions
        WHERE mechanic_id = ? AND business = ?
        ORDER BY created_at DESC
        LIMIT 200
    ]], { citizenid, business }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local customerName = 'Unknown Customer'
        if row.customer_id and row.customer_id ~= '' then
            local p = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { row.customer_id })
            if p and p.charinfo then
                local ok, ci = pcall(json.decode, p.charinfo)
                if ok and ci then
                    customerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
                    if customerName == '' then customerName = 'Unknown Customer' end
                end
            end
        end

        local decodedItems = {}
        if row.items and row.items ~= '' then
            local ok, parsed = pcall(json.decode, row.items)
            if ok and type(parsed) == 'table' then
                decodedItems = parsed
            end
        end

        out[#out + 1] = {
            id = row.transaction_id,
            customer = customerName,
            customerCitizenId = row.customer_id,
            chargedBy = row.mechanic_name,
            items = decodedItems,
            subtotal = tonumber(row.subtotal or 0) or 0,
            tax = tonumber(row.tax or 0) or 0,
            total = tonumber(row.total or 0) or 0,
            paymentType = row.payment_type,
            when = row.created_at,
            where = row.service_location or 'Not captured',
            vehicle = {
                plate = row.vehicle_plate or 'N/A',
                model = row.vehicle_model or 'N/A'
            }
        }
    end

    return out
end

QBCore.Functions.CreateCallback('pf_mech:management:overview', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb({}) return end

    local totals = {
        last7 = MySQL.single.await('SELECT COALESCE(SUM(total),0) AS total FROM pf_pos_transactions WHERE business = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)', { business }) or {},
        last30 = MySQL.single.await('SELECT COALESCE(SUM(total),0) AS total FROM pf_pos_transactions WHERE business = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)', { business }) or {},
        today = MySQL.single.await('SELECT COALESCE(SUM(total),0) AS total FROM pf_pos_transactions WHERE business = ? AND DATE(created_at) = CURDATE()', { business }) or {},
    }

    local employees = MySQL.query.await('SELECT citizenid FROM players WHERE JSON_EXTRACT(job, "$.name") = ?', { business }) or {}
    local totalEmployees = #employees
    local onDuty = 0
    for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do
        if Player.PlayerData.job and Player.PlayerData.job.name == business and Player.PlayerData.job.onduty == true then
            onDuty = onDuty + 1
        end
    end

    local popular = getMostPopularService(business)

    cb({
        business = business,
        businessName = getBusinessNameByKey(business),
        last7Total = tonumber(totals.last7.total or 0) or 0,
        last30Total = tonumber(totals.last30.total or 0) or 0,
        todayTotal = tonumber(totals.today.total or 0) or 0,
        onDutyEmployees = onDuty,
        totalEmployees = totalEmployees,
        popularWork = popular,
    })
end)

QBCore.Functions.CreateCallback('pf_mech:management:graph', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb({}) return end

    local rows = MySQL.query.await([[ 
        SELECT DATE(created_at) AS day, SUM(total) AS total
        FROM pf_pos_transactions
        WHERE business = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY DATE(created_at)
        ORDER BY day ASC
    ]], { business }) or {}

    cb(rows)
end)

QBCore.Functions.CreateCallback('pf_mech:management:employees', function(src, cb)
    local business = GetBusinessForSource(src)
    if not business then cb({}) return end

    local employees = MySQL.query.await([[ 
        SELECT 
            p.citizenid,
            CONCAT(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))) AS name,
            e.hired_at,
            e.last_promoted_at,
            e.last_online,
            e.avatar,
            e.grade,
            e.role
        FROM players p
        LEFT JOIN pf_business_employees e ON e.citizenid = p.citizenid
        WHERE JSON_EXTRACT(p.job, '$.name') = ?
        ORDER BY COALESCE(e.grade, 0) DESC, name ASC
    ]], { business }) or {}

    local out = {}
    for _, emp in ipairs(employees) do
        local grade = tonumber(emp.grade)
        if grade == nil then
            grade = getGradeByCitizenId(emp.citizenid)
        end

        local txStats = MySQL.single.await(
            'SELECT COUNT(*) AS charges, COALESCE(SUM(total),0) AS amount FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ?',
            { emp.citizenid, business }
        ) or { charges = 0, amount = 0 }

        local woStats = MySQL.single.await(
            'SELECT COUNT(*) AS done FROM pf_work_orders WHERE assigned_to = ? AND status = "complete"',
            { emp.citizenid }
        ) or { done = 0 }

        local online = QBCore.Functions.GetPlayerByCitizenId(emp.citizenid)
        local onduty = online and online.PlayerData and online.PlayerData.job and online.PlayerData.job.onduty == true or false

        out[#out + 1] = {
            citizenid = emp.citizenid,
            name = emp.name,
            grade = grade,
            rank = grade,
            role = emp.role or (grade >= 4 and 'owner' or (grade >= 2 and 'manager' or 'employee')),
            avatar = getAvatarForEmployee(emp.citizenid, emp.name),
            hiredAt = emp.hired_at,
            lastPromotedAt = emp.last_promoted_at,
            lastOnline = emp.last_online,
            online = online ~= nil,
            onDuty = onduty,
            completedWorkOrders = tonumber(woStats.done or 0) or 0,
            customerCharges = tonumber(txStats.charges or 0) or 0,
            totalSales = tonumber(txStats.amount or 0) or 0,
        }
    end

    cb(out)
end)

QBCore.Functions.CreateCallback('pf_mech:management:getStats', function(src, cb, citizenid)
    local business = GetBusinessForSource(src)
    if not business then cb(nil) return end
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 then cb(nil) return end
    -- only this shop's staff (it returned any citizen's name and record)
    local targetJob = jobOfCitizen(citizenid)
    if not targetJob or targetJob.name ~= business then cb(nil) return end

    local base = MySQL.single.await([[ 
        SELECT 
            p.citizenid,
            CONCAT(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))) AS name,
            e.hired_at,
            e.last_promoted_at,
            e.last_online,
            e.avatar,
            e.grade,
            e.role
        FROM players p
        LEFT JOIN pf_business_employees e ON e.citizenid = p.citizenid
        WHERE p.citizenid = ?
        LIMIT 1
    ]], { citizenid })

    if not base then cb(nil) return end

    local grade = tonumber(base.grade)
    if grade == nil then grade = getGradeByCitizenId(citizenid) end

    local txStats = MySQL.single.await(
        'SELECT COUNT(*) AS charges, COALESCE(SUM(total),0) AS amount FROM pf_pos_transactions WHERE mechanic_id = ? AND business = ?',
        { citizenid, business }
    ) or { charges = 0, amount = 0 }

    local woStats = MySQL.single.await(
        'SELECT COUNT(*) AS done FROM pf_work_orders WHERE assigned_to = ? AND status = "complete"',
        { citizenid }
    ) or { done = 0 }

    local transactions = getEmployeeTransactions(citizenid, business)

    cb({
        employee = {
            citizenid = citizenid,
            name = base.name,
            grade = grade,
            rank = grade,
            role = base.role or (grade >= 4 and 'owner' or (grade >= 2 and 'manager' or 'employee')),
            avatar = getAvatarForEmployee(citizenid, base.name),
            hiredAt = base.hired_at,
            lastPromotedAt = base.last_promoted_at,
            lastOnline = base.last_online,
            completedWorkOrders = tonumber(woStats.done or 0) or 0,
            customerCharges = tonumber(txStats.charges or 0) or 0,
            totalSales = tonumber(txStats.amount or 0) or 0,
        },
        transactions = transactions,
    })
end)

QBCore.Functions.CreateCallback('pf_mech:management:hire', function(src, cb, citizenInput)
    local business = GetBusinessForSource(src)
    local manager = QBCore.Functions.GetPlayer(src)
    if not business or not manager then cb(false, 'invalid_manager') return end

    if not IsEmployeeManager(manager.PlayerData.citizenid) then
        cb(false, 'not_authorized')
        return
    end

    local citizenid = tostring(citizenInput or ''):gsub('^%s+', ''):gsub('%s+$', '')

    if citizenid:match('^%d+$') then
        local onlineTarget = QBCore.Functions.GetPlayer(tonumber(citizenid))
        if onlineTarget then
            citizenid = onlineTarget.PlayerData.citizenid
        end
    end

    if citizenid == '' or #citizenid > 64 then
        cb(false, 'missing_citizenid')
        return
    end

    -- Hiring changes the target's job, so they must be online and standing with the manager (as with
    -- the boss menu). Any citizen id, online or not, used to be pulled into the shop, which also
    -- stripped police or EMS players of their job.
    local hireTarget = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if not hireTarget or hireTarget.PlayerData.citizenid == manager.PlayerData.citizenid then
        cb(false, 'citizen_not_found')
        return
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(hireTarget.PlayerData.source))) > 10.0 then
        cb(false, 'not_nearby')
        return
    end
    if hireTarget.PlayerData.job and hireTarget.PlayerData.job.name == business then
        cb(false, 'already_employed')
        return
    end

    local playerRow = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not playerRow then
        cb(false, 'citizen_not_found')
        return
    end

    local charinfo = {}
    local ok, parsed = pcall(json.decode, playerRow.charinfo or '{}')
    if ok and type(parsed) == 'table' then charinfo = parsed end
    local fullName = ((charinfo.firstname or 'Unknown') .. ' ' .. (charinfo.lastname or 'Citizen')):gsub('^%s+', ''):gsub('%s+$', '')

    local setOk = setOfflineJobByCitizenId(citizenid, business, 0)
    if not setOk then
        cb(false, 'failed_job_update')
        return
    end

    upsertEmployeeRecord(citizenid, business, fullName, 0)

    local onlineTarget = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if onlineTarget then
        onlineTarget.Functions.SetJob(business, 0)
    end

    cb(true, 'hired')
end)

QBCore.Functions.CreateCallback('pf_mech:management:promote', function(src, cb, citizenid)
    local ctx, why = staffContext(src, citizenid)
    if not ctx then cb(false, why) return end

    local current = ctx.targetGrade
    if current >= 4 then
        cb(false, 'max_rank')
        return
    end
    if not gradeAllowed(ctx, current + 1) then cb(false, 'rank') return end

    local ok = setEmployeeGrade(citizenid, ctx.business, current + 1)
    if not ok then
        cb(false, 'update_failed')
        return
    end

    cb(true)
end)

QBCore.Functions.CreateCallback('pf_mech:management:demote', function(src, cb, citizenid)
    local ctx, why = staffContext(src, citizenid)
    if not ctx then cb(false, why) return end

    local current = ctx.targetGrade
    if current <= 0 then
        cb(false, 'min_rank')
        return
    end

    local ok = setEmployeeGrade(citizenid, ctx.business, current - 1)
    if not ok then
        cb(false, 'update_failed')
        return
    end

    cb(true)
end)

QBCore.Functions.CreateCallback('pf_mech:management:fire', function(src, cb, citizenid)
    local ctx, why = staffContext(src, citizenid)
    if not ctx then cb(false, why) return end

    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        target.Functions.SetJob('unemployed', 0)
    else
        local _ = setOfflineJobByCitizenId(citizenid, 'unemployed', 0)
    end

    MySQL.delete.await('DELETE FROM pf_business_employees WHERE citizenid = ?', { citizenid })
    cb(true)
end)

QBCore.Functions.CreateCallback('pf_mech:management:saveSettings', function(src, cb, data)
    local manager = QBCore.Functions.GetPlayer(src)
    local business = GetBusinessForSource(src)
    if not manager or not business then cb(false) return end

    if not IsEmployeeManager(manager.PlayerData.citizenid) then
        cb(false)
        return
    end

    local businessName = (data and data.business_name) or getBusinessNameByKey(business)
    local blipName = (data and data.blip_name) or businessName
    local blipColor = tonumber(data and data.blip_color) or 3

    MySQL.update.await('UPDATE pf_business SET name = ? WHERE business = ?', { businessName, business })
    MySQL.update.await('UPDATE pf_business_settings SET business_name = ?, blip_name = ?, blip_color = ? WHERE id = 1', {
        businessName,
        blipName,
        blipColor,
    })

    cb(true)
end)

local function updateLastOnlineBySource(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return end
    local job = Player.PlayerData.job.name
    if not AllowedJobs[job] then return end

    local citizenid = Player.PlayerData.citizenid
    local fullName = (Player.PlayerData.charinfo.firstname or 'Unknown') .. ' ' .. (Player.PlayerData.charinfo.lastname or 'Citizen')
    local grade = getGradeFromPlayerJob(Player)
    upsertEmployeeRecord(citizenid, job, fullName, grade)
end

AddEventHandler('playerDropped', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.citizenid then return end
    MySQL.update.await('UPDATE pf_business_employees SET last_online = NOW() WHERE citizenid = ?', { Player.PlayerData.citizenid })
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    updateLastOnlineBySource(source)
end)
