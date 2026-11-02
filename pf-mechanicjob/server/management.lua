-- Management App - Server Side Handler
-- Handles database operations, callbacks, events, and business logic

local QBCore = exports['pfm-core']:GetCoreObject()
PFMech = PFMech or {}

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
    -- shared jobs key their grades by string ('0', '1'...)
    local grade = grades[gradeLevel] or grades[tostring(gradeLevel)]
    if grade then
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
    if not IsEmployeeManager(Player.PlayerData.citizenid, business) then return nil, 'not_authorized' end
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

-- (The start-up seed of one global pf_business_settings row is gone: settings are per shop now, and
-- a shop without a row reads the defaults, GetBusinessSettings.)

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
    local products = GetAllProducts(business)
    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Products found: ' .. #products)
    end

    -- Fetch inventory
    local inventory = GetInventory()
    if Config.Debug then
        PFMech.Debug('^2[Management]^7 Inventory items found: ' .. #inventory)
    end

    -- Fetch business settings
    local businessSettings = GetBusinessSettings(business)

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
        LEFT JOIN pf_business_employees e ON e.citizenid = CONVERT(p.citizenid USING utf8mb4) COLLATE utf8mb4_unicode_ci AND e.business = ?
        WHERE JSON_EXTRACT(p.job, '$.name') = ?
    ]], {business, business}) or {}

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
    if not business or not Player or not IsEmployeeManager(Player.PlayerData.citizenid, business) then return nil end
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
    -- the shop's own name and blip (the settings tab shows and edits these)
    local bs = GetBusinessSettings(business)
    row.business_name, row.blip_name, row.blip_color = bs.business_name, bs.blip_name, bs.blip_color

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
                'SELECT id, role, hired_at, business FROM pf_business_employees WHERE citizenid = ?',
                {emp.citizenid}
            )
            
            local role = 'employee'
            local hired_at = os.date('%Y-%m-%d %H:%M:%S')
            
            if existingEmp and existingEmp[1] then
                -- a role kept from another shop does not count here
                if existingEmp[1].business == b then role = existingEmp[1].role end
                hired_at = existingEmp[1].hired_at
            else
                MySQL.insert.await(
                    'INSERT IGNORE INTO pf_business_employees (citizenid, name, role, hired_at, business) VALUES (?, ?, ?, ?, ?)',
                    {emp.citizenid, emp.name, role, hired_at, b}
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

-- A citizen's role at one shop: the higher of the role stored for that shop (pf_business_employees)
-- and the one their grade gives, the grade only while that shop is their current job. A stored
-- role from another shop never counts (one row per citizen used to carry a manager role to the next
-- shop at once); a boss by grade is never locked out by a plain 'employee' row.
local ROLE_RANK = { employee = 1, manager = 2, owner = 3 }

function GetEmployeeRole(citizenid, business)
    if type(citizenid) ~= 'string' or type(business) ~= 'string' then return 'employee' end
    local role = 'employee'
    local empRow = MySQL.single.await('SELECT role, business FROM pf_business_employees WHERE citizenid = ? LIMIT 1', {citizenid})
    if empRow and empRow.business == business and ROLE_RANK[empRow.role] then
        role = empRow.role
    end
    local job = jobOfCitizen(citizenid)
    if job and job.name == business and AllowedJobs[business] then
        local byGrade = GetRoleFromGrade(business, gradeOf(job))
        if ROLE_RANK[byGrade] > ROLE_RANK[role] then role = byGrade end
    end
    return role
end

function IsEmployeeManager(citizenid, business)
    local role = GetEmployeeRole(citizenid, business)
    return role == 'owner' or role == 'manager'
end

-- ============================================================================
-- PRODUCT & INVENTORY FUNCTIONS
-- ============================================================================

function GetAllProducts(business)
    -- the shop's register price list (mechanic_prices is keyed by the shop, not by its display name)
    local result = MySQL.query.await(
        'SELECT id, item as id2, label as product_name, price as current_price, price as base_price, category FROM mechanic_prices WHERE business = ?',
        {business or 'mechanic'}
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
-- BUSINESS SETTINGS (one row per shop)
-- ============================================================================

function GetBusinessSettings(business)
    local row = type(business) == 'string' and MySQL.single.await(
        'SELECT business_name, blip_name, blip_color FROM pf_business_settings WHERE business = ? LIMIT 1', { business }) or nil
    if row then return row end
    local branding = Config.BusinessBranding and Config.BusinessBranding[business]
    return {
        business_name = (branding and branding.name) or Config.ManagementApp.DefaultBusinessName,
        blip_name = Config.ManagementApp.DefaultBlipName,
        blip_color = Config.ManagementApp.DefaultBlipColor
    }
end

-- Validated settings from a client payload, or nil and the reason.
local function settingsFrom(data)
    if type(data) ~= 'table' then return nil, 'invalid' end
    local function name(v)
        if type(v) ~= 'string' then return nil end
        v = v:gsub('^%s+', ''):gsub('%s+$', '')
        if #v < 1 or #v > 64 then return nil end
        return v
    end
    local businessName, blipName = name(data.business_name), name(data.blip_name)
    local color = tonumber(data.blip_color)
    if not businessName then return nil, 'business_name' end
    if not blipName then return nil, 'blip_name' end
    if not color or color ~= math.floor(color) or color < 0 or color > 85 then return nil, 'blip_color' end
    return { business_name = businessName, blip_name = blipName, blip_color = color }
end

local function saveBusinessSettingsFor(business, settings)
    MySQL.update.await('UPDATE pf_business SET name = ? WHERE business = ?', { settings.business_name, business })
    MySQL.query.await([[INSERT INTO pf_business_settings (business, business_name, blip_name, blip_color) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE business_name = VALUES(business_name), blip_name = VALUES(blip_name), blip_color = VALUES(blip_color)]],
        { business, settings.business_name, settings.blip_name, settings.blip_color })
end

-- ============================================================================
-- EMPLOYEE MANAGEMENT EVENTS
-- ============================================================================

-- (The 'pf_mechanic:hireEmployee' event is gone: it took a server id at any distance and reset a
-- colleague to grade 0. Hiring is a job offer the citizen accepts: pf_mech:management:hire.)

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

    MySQL.update.await('DELETE FROM pf_business_employees WHERE citizenid = ?', {targetCitizenid})

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
    if role == 'owner' and GetEmployeeRole(ctx.player.PlayerData.citizenid, ctx.business) ~= 'owner' then return staffDenied(src, 'role') end
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
        'UPDATE pf_business_employees SET role = ?, business = ?, last_promoted_at = NOW() WHERE citizenid = ?',
        {role, ctx.business, targetCitizenid}
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
        SELECT citizenid, name FROM pf_business_employees WHERE business = ? AND role IN ('employee', 'manager')
    ]], { business }) or {}

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

    -- Check if current player is owner (of this shop)
    local currentRole = GetEmployeeRole(xPlayer.PlayerData.citizenid, business)
    if currentRole ~= 'owner' then
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "You must be the owner to transfer ownership"}
        })
        return
    end

    -- The new owner must already work here: someone else is hired through a job offer they accept
    -- first. (A nearby player used to be moved into the shop without being asked.)
    if type(newOwnerCid) ~= 'string' or newOwnerCid == '' or #newOwnerCid > 64
        or newOwnerCid == xPlayer.PlayerData.citizenid then return end
    local newOwnerJob = jobOfCitizen(newOwnerCid)
    if not (newOwnerJob and newOwnerJob.name == business) then return staffDenied(src, 'not_employee') end

    -- Make new owner
    MySQL.update.await(
        'UPDATE pf_business_employees SET role = ?, business = ? WHERE citizenid = ?',
        {'owner', business, newOwnerCid}
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

    local newOwner = QBCore.Functions.GetPlayerByCitizenId(newOwnerCid)
    if newOwner then
        TriggerClientEvent('chat:addMessage', newOwner.PlayerData.source, {
            color = {0, 255, 0},
            multiline = true,
            args = {"Management", "You are now the owner of " .. business}
        })
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

    if not IsEmployeeManager(xPlayer.PlayerData.citizenid, business) then
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
    local src = source
    local business = GetBusinessForSource(src)
    if not business then return end

    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end

    if not IsEmployeeManager(xPlayer.PlayerData.citizenid, business) then
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Management", "You don't have permission"}
        })
        return
    end

    local settings = settingsFrom(data)
    if not settings then return end
    -- this shop's row only (every shop used to share one row, id 1)
    saveBusinessSettingsFor(business, settings)

    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 255, 0},
        multiline = true,
        args = {"Management", "Business settings saved"}
    })
end)

-- (Location placement is retired: 'pf_mechanic:setLocation' wrote one global table from client
-- coordinates, and nothing in the game ever read those rows. Shop duty points, stashes and lockers
-- come from the shop's own config.)

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


-- ============================================================================
-- ENHANCED MANAGEMENT API (PF TABLET MODULE)
-- ============================================================================

local function ensureManagementSchema()
    pcall(function()
        -- (the pf_business_employees columns are in server/schema.lua, migration 3)
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

-- A row for someone working at `business`. A row kept from another shop starts again as an
-- ordinary employee: `role` is set before `business` (later assignments in ON DUPLICATE KEY UPDATE
-- already see the new value), so the comparison is against the old shop.
local function upsertEmployeeRecord(citizenid, business, fullName, grade)
    MySQL.query.await([[
        INSERT INTO pf_business_employees (citizenid, name, role, hired_at, business, grade, last_online)
        VALUES (?, ?, 'employee', NOW(), ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
            role = IF(business <=> VALUES(business), role, 'employee'),
            hired_at = IF(business <=> VALUES(business), hired_at, NOW()),
            name = VALUES(name),
            business = VALUES(business),
            grade = VALUES(grade),
            last_online = NOW()
    ]], { citizenid, fullName, business, tonumber(grade) or 0 })
end

-- A new hire: an ordinary employee of this shop from now on, whatever the row said before.
local function hireEmployeeRecord(citizenid, business, fullName)
    MySQL.query.await([[
        INSERT INTO pf_business_employees (citizenid, name, role, hired_at, business, grade, last_online)
        VALUES (?, ?, 'employee', NOW(), ?, 0, NOW())
        ON DUPLICATE KEY UPDATE
            role = 'employee', name = VALUES(name), business = VALUES(business), grade = 0,
            hired_at = NOW(), last_promoted_at = NULL, last_online = NOW()
    ]], { citizenid, fullName, business })
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
        'UPDATE pf_business_employees SET grade = ?, role = ?, business = ?, last_promoted_at = NOW() WHERE citizenid = ?',
        { grade, (grade >= 4 and 'owner' or (grade >= 2 and 'manager' or 'employee')), business, citizenid }
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
        LEFT JOIN pf_business_employees e ON e.citizenid = CONVERT(p.citizenid USING utf8mb4) COLLATE utf8mb4_unicode_ci AND e.business = ?
        WHERE JSON_EXTRACT(p.job, '$.name') = ?
        ORDER BY COALESCE(e.grade, 0) DESC, name ASC
    ]], { business, business }) or {}

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
        LEFT JOIN pf_business_employees e ON e.citizenid = CONVERT(p.citizenid USING utf8mb4) COLLATE utf8mb4_unicode_ci AND e.business = ?
        WHERE p.citizenid = ?
        LIMIT 1
    ]], { business, citizenid })

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

-- ============================================================================
-- JOB OFFERS
-- ============================================================================
-- Hiring is an offer the citizen accepts. A manager offers a job by citizen id (or the server id of
-- someone online); the citizen is told at once if online (a prompt to accept or decline), by mail,
-- and again each time they log in, until the offer is answered or expires. Only their own answer
-- changes their job. (Hiring used to set the job of anyone standing next to the manager, police and
-- EMS included, and the button promised offline hiring that did not work.)
local OFFER_HOURS = math.floor(tonumber(Config.ManagementApp and Config.ManagementApp.OfferHours) or 72)
local OFFER_MAX_PENDING = math.floor(tonumber(Config.ManagementApp and Config.ManagementApp.MaxPendingOffers) or 20)
local OFFER_RATE_SECONDS = 5
local OfferLast = {}   -- [manager citizenid] = os.time() of their last offer
local OfferBusy = {}   -- [citizenid] = true while their answer is being processed

local function citizenName(citizenid)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    local ci = {}
    if row and row.charinfo then
        local ok, parsed = pcall(json.decode, row.charinfo)
        if ok and type(parsed) == 'table' then ci = parsed end
    end
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or 'A manager'
end

-- The open offers made to a citizen, for the accept prompt.
local function openOffersFor(citizenid)
    local rows = MySQL.query.await([[SELECT id, business, offered_by, TIMESTAMPDIFF(MINUTE, NOW(), expires_at) AS minutes_left
        FROM pf_mech_job_offers WHERE citizenid = ? AND status = 'pending' AND expires_at > NOW() ORDER BY id]], { citizenid }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(r.id), shop = getBusinessNameByKey(r.business), from = citizenName(r.offered_by),
            hoursLeft = math.max(1, math.ceil((tonumber(r.minutes_left) or 60) / 60)),
        }
    end
    return out
end

local function showOffers(src, citizenid)
    if not PFMech.SchemaReady then return end
    local list = openOffersFor(citizenid)
    if #list > 0 then TriggerClientEvent('pf_mech:offers:show', src, list) end
end

local function mailOffer(citizenid, shop, fromName)
    if GetResourceState('pf-citizen') ~= 'started' then return end
    local ok, err = pcall(function()
        return exports['pf-citizen']:SendMail(citizenid, {
            sender = shop,
            senderType = 'business',
            subject = ('Job offer: %s'):format(shop),
            message = ('%s offers you a job at %s.\n\nYou are asked to accept or decline the next time you are in town (or type /joboffers). The offer stays open for %d hours.')
                :format(fromName, shop, OFFER_HOURS),
        })
    end)
    if not ok then print('^3[pf-mechanicjob]^7 job offer mail not sent: ' .. tostring(err)) end
end

local function tellOfferer(managerCid, text, kind)
    local m = QBCore.Functions.GetPlayerByCitizenId(managerCid)
    if m then TriggerClientEvent('QBCore:Notify', m.PlayerData.source, text, kind or 'primary') end
end

QBCore.Functions.CreateCallback('pf_mech:management:hire', function(src, cb, citizenInput)
    local business = GetBusinessForSource(src)
    local manager = QBCore.Functions.GetPlayer(src)
    if not business or not manager then cb(false, 'invalid_manager') return end

    if not IsEmployeeManager(manager.PlayerData.citizenid, business) then
        cb(false, 'not_authorized')
        return
    end
    if not PFMech.SchemaReady then cb(false, 'not_ready') return end

    local citizenid = tostring(citizenInput or ''):gsub('^%s+', ''):gsub('%s+$', '')
    -- the server id of someone online
    if citizenid:match('^%d+$') then
        local onlineTarget = QBCore.Functions.GetPlayer(tonumber(citizenid))
        if onlineTarget then citizenid = onlineTarget.PlayerData.citizenid end
    end
    if citizenid == '' or #citizenid > 50 or not citizenid:match('^[%w_%-]+$') then
        cb(false, 'missing_citizenid')
        return
    end
    local mcid = manager.PlayerData.citizenid
    if citizenid == mcid then cb(false, 'self') return end
    local now = os.time()
    if OfferLast[mcid] and now - OfferLast[mcid] < OFFER_RATE_SECONDS then cb(false, 'slow_down') return end
    OfferLast[mcid] = now

    local targetJob = jobOfCitizen(citizenid)
    if not targetJob then cb(false, 'citizen_not_found') return end
    if targetJob.name == business then cb(false, 'already_employed') return end
    local open = MySQL.scalar.await([[SELECT COUNT(*) FROM pf_mech_job_offers
        WHERE business = ? AND status = 'pending' AND expires_at > NOW() AND citizenid <> ?]], { business, citizenid })
    if (tonumber(open) or 0) >= OFFER_MAX_PENDING then cb(false, 'too_many_offers') return end

    MySQL.query.await([[INSERT INTO pf_mech_job_offers (business, citizenid, offered_by, status, expires_at)
        VALUES (?, ?, ?, 'pending', DATE_ADD(NOW(), INTERVAL ? HOUR))
        ON DUPLICATE KEY UPDATE offered_by = VALUES(offered_by), status = 'pending',
            expires_at = VALUES(expires_at), responded_at = NULL]], { business, citizenid, mcid, OFFER_HOURS })

    local shop = getBusinessNameByKey(business)
    local fromName = citizenName(mcid)
    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        TriggerClientEvent('QBCore:Notify', target.PlayerData.source, ('%s offers you a job at %s'):format(fromName, shop), 'primary')
        showOffers(target.PlayerData.source, citizenid)
    end
    mailOffer(citizenid, shop, fromName)
    cb(true, 'offer_sent')
end)

-- Runs with the citizen locked. Only an open, unexpired offer made to this citizen is taken, by a
-- single conditional update; only then does their job change.
local function answerOffer(src, citizenid, offerId, accept)
    local offer = MySQL.single.await('SELECT business, offered_by FROM pf_mech_job_offers WHERE id = ? AND citizenid = ?', { offerId, citizenid })
    if not offer then
        TriggerClientEvent('QBCore:Notify', src, 'That job offer is no longer open', 'error')
        return
    end
    local shop = getBusinessNameByKey(offer.business)
    if not accept then
        local n = MySQL.update.await([[UPDATE pf_mech_job_offers SET status = 'declined', responded_at = NOW()
            WHERE id = ? AND citizenid = ? AND status = 'pending']], { offerId, citizenid })
        if n == 1 then
            TriggerClientEvent('QBCore:Notify', src, ('You declined the job at %s'):format(shop), 'primary')
            tellOfferer(offer.offered_by, ('%s declined the job offer'):format(citizenName(citizenid)))
        end
        return
    end
    if not AllowedJobs[offer.business] then return end
    local n = MySQL.update.await([[UPDATE pf_mech_job_offers SET status = 'accepted', responded_at = NOW()
        WHERE id = ? AND citizenid = ? AND status = 'pending' AND expires_at > NOW()]], { offerId, citizenid })
    if n ~= 1 then
        TriggerClientEvent('QBCore:Notify', src, 'That job offer is no longer open', 'error')
        return
    end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= citizenid then return end
    if Player.Functions.SetJob(offer.business, 0) == false then
        -- the job does not exist on this server: the offer stays open
        MySQL.update.await("UPDATE pf_mech_job_offers SET status = 'pending', responded_at = NULL WHERE id = ?", { offerId })
        TriggerClientEvent('QBCore:Notify', src, 'This job is not available right now', 'error')
        return
    end
    local ci = Player.PlayerData.charinfo or {}
    local fullName = ((ci.firstname or 'Unknown') .. ' ' .. (ci.lastname or 'Citizen')):gsub('^%s+', ''):gsub('%s+$', '')
    hireEmployeeRecord(citizenid, offer.business, fullName)
    TriggerClientEvent('QBCore:Notify', src, ('You now work at %s'):format(shop), 'success')
    tellOfferer(offer.offered_by, ('%s accepted the job offer'):format(fullName), 'success')
end

RegisterNetEvent('pf_mech:management:respondOffer', function(offerId, accept)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not PFMech.SchemaReady then return end
    offerId = tonumber(offerId)
    if not offerId or offerId ~= math.floor(offerId) or offerId <= 0 then return end
    local cid = Player.PlayerData.citizenid
    -- locked before the first database wait: a double click cannot take the offer twice
    if OfferBusy[cid] then return end
    OfferBusy[cid] = true
    local ok, err = pcall(answerOffer, src, cid, offerId, accept == true)
    OfferBusy[cid] = nil
    if not ok then print('^1[pf-mechanicjob]^7 job offer answer failed: ' .. tostring(err)) end
end)

-- The caller's own open offers (the /joboffers command).
QBCore.Functions.CreateCallback('pf_mech:management:myOffers', function(src, cb)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not PFMech.SchemaReady then cb({}) return end
    cb(openOffersFor(Player.PlayerData.citizenid))
end)

-- The shop's offers for its managers: open ones and those answered in the last 3 days.
QBCore.Functions.CreateCallback('pf_mech:management:offers', function(src, cb)
    local business = GetBusinessForSource(src)
    local manager = QBCore.Functions.GetPlayer(src)
    if not business or not manager or not PFMech.SchemaReady
        or not IsEmployeeManager(manager.PlayerData.citizenid, business) then cb({}) return end
    local rows = MySQL.query.await([[SELECT id, citizenid, status, TIMESTAMPDIFF(MINUTE, NOW(), expires_at) AS minutes_left
        FROM pf_mech_job_offers
        WHERE business = ? AND ((status = 'pending' AND expires_at > NOW())
            OR (status <> 'pending' AND responded_at > DATE_SUB(NOW(), INTERVAL 3 DAY)))
        ORDER BY id DESC LIMIT 30]], { business }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(r.id), citizenid = r.citizenid, name = citizenName(r.citizenid), status = r.status,
            hoursLeft = r.status == 'pending' and math.max(1, math.ceil((tonumber(r.minutes_left) or 60) / 60)) or nil,
        }
    end
    cb(out)
end)

QBCore.Functions.CreateCallback('pf_mech:management:cancelOffer', function(src, cb, offerId)
    local business = GetBusinessForSource(src)
    local manager = QBCore.Functions.GetPlayer(src)
    offerId = tonumber(offerId)
    if not business or not manager or not offerId or not PFMech.SchemaReady
        or not IsEmployeeManager(manager.PlayerData.citizenid, business) then cb(false) return end
    local n = MySQL.update.await([[UPDATE pf_mech_job_offers SET status = 'cancelled', responded_at = NOW()
        WHERE id = ? AND business = ? AND status = 'pending']], { offerId, business })
    cb(n == 1)
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

    MySQL.update.await('DELETE FROM pf_business_employees WHERE citizenid = ?', { citizenid })
    cb(true)
end)

QBCore.Functions.CreateCallback('pf_mech:management:saveSettings', function(src, cb, data)
    local manager = QBCore.Functions.GetPlayer(src)
    local business = GetBusinessForSource(src)
    if not manager or not business then cb(false) return end

    if not IsEmployeeManager(manager.PlayerData.citizenid, business) then
        cb(false)
        return
    end
    local settings, why = settingsFrom(data)
    if not settings then cb(false, why) return end
    saveBusinessSettingsFor(business, settings)
    cb(true)
end)

local LastJobName = {}   -- [src] = the job name seen last (QBCore:Server:OnJobUpdate below)

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
    LastJobName[src] = nil
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.citizenid then return end
    MySQL.update.await('UPDATE pf_business_employees SET last_online = NOW() WHERE citizenid = ?', { Player.PlayerData.citizenid })
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    updateLastOnlineBySource(src)
    -- open job offers are asked again after each login
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then showOffers(src, Player.PlayerData.citizenid) end
end)

-- A role belongs to one shop: when someone's job changes to anything else, a manager or owner role
-- on their row ends (a later hire at the same shop starts as an employee again).
AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    if type(job) ~= 'table' or type(job.name) ~= 'string' then return end
    if LastJobName[src] == job.name then return end
    LastJobName[src] = job.name
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    MySQL.update.await([[UPDATE pf_business_employees SET role = 'employee'
        WHERE citizenid = ? AND role <> 'employee' AND NOT (business <=> ?)]], { Player.PlayerData.citizenid, job.name })
end)
