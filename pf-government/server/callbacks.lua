-- =====================================================
-- NUI CALLBACKS (General & Dashboard)
-- =====================================================

-- Reads that list other people's or the city's internal records; government staff only (any client
-- can send this event, the UI is not the gate)
local GOV_ONLY_ACTIONS = {
    ['staff:getAll'] = true, ['utility:getAll'] = true, ['business:get'] = true,
    ['budget:getAll'] = true, ['budget:getSnapshot'] = true,
}

-- NUI Callback Router (receives callbacks from client NUI bridge)
RegisterNetEvent('pf-government:server:nuiCallback', function(callbackId, action, data)
    local src = source
    if data ~= nil and type(data) ~= 'table' then return end
    data = data or {}
    data.source = src

    local handler = type(action) == 'string' and Government and Government.NuiCallbacks and Government.NuiCallbacks[action]
    if handler and GOV_ONLY_ACTIONS[action] and not IsGovernmentEmployee(src) then
        TriggerClientEvent('pf-government:client:nuiCallback', src, callbackId, { ok = false, error = 'no_permission' })
        return
    end
    if not handler then
        TriggerClientEvent('pf-government:client:nuiCallback', src, callbackId, {
            ok = false,
            error = 'unknown_callback'
        })
        return
    end

    local function reply(result)
        TriggerClientEvent('pf-government:client:nuiCallback', src, callbackId, result or {
            ok = false,
            error = 'empty_response'
        })
    end

    local ok, err = pcall(handler, data, reply)
    if not ok then
        DebugPrint('NUI callback error: ' .. tostring(action) .. ' - ' .. tostring(err))
        reply({ ok = false, error = 'server_error' })
    end
end)

local WEBSITE_STATE_KVP_KEY = 'pf_government_website_state_v1'

local function GetPersistedWebsiteState()
    local ok, encoded = pcall(GetResourceKvpString, WEBSITE_STATE_KVP_KEY)
    if not ok or type(encoded) ~= 'string' or encoded == '' then
        return nil
    end

    local decodeOk, decoded = pcall(json.decode, encoded)
    if decodeOk and type(decoded) == 'table' then
        return decoded
    end

    return nil
end

local function PersistWebsiteState(state)
    if type(state) ~= 'table' then
        return false
    end

    local encodeOk, encoded = pcall(json.encode, state)
    if not encodeOk or type(encoded) ~= 'string' then
        return false
    end

    local setOk = pcall(SetResourceKvp, WEBSITE_STATE_KVP_KEY, encoded)
    return setOk == true
end

exports('GetWebsiteState', function()
    return GetPersistedWebsiteState() or {}
end)

exports('SetWebsiteState', function(state)
    if type(state) ~= 'table' then
        return false
    end

    return PersistWebsiteState(state)
end)

RegisterNUICallback('website:getState', function(_, cb)
    cb({
        ok = true,
        state = GetPersistedWebsiteState() or {}
    })
end)

RegisterNUICallback('website:saveState', function(data, cb)
    local src = data.source or source
    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    if type(data.state) ~= 'table' then
        cb({ ok = false, error = 'invalid_state' })
        return
    end

    local saved = PersistWebsiteState(data.state)
    cb({ ok = saved })
end)

-- =====================================================
-- BROWSER ASSISTANT
-- =====================================================
-- Logic lives in server/assistant.lua (and its siblings).
-- This callback is intentionally thin.

RegisterNUICallback('assistant:query', function(data, cb)
    -- The city assistant is available to all players, no job restriction.
    local ok, result = pcall(AssistantHandleQuery, data)
    if not ok then
        DebugPrint('Assistant error: ' .. tostring(result))
        cb({ ok = false, error = 'assistant_error', message = tostring(result) })
        return
    end

    cb(result)
end)


-- =====================================================
-- DASHBOARD
-- =====================================================

RegisterNUICallback('dashboard:getData', function(data, cb)
    local src = data.source or source
    
    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end
    
    -- Get dashboard data
    local treasuryBalance = GetTreasuryBalance()
    local businessStats = GetBusinessStats()
    
    -- Get recent activity (audit logs)
    local recentActivity = GetAuditLogs({}, 10)
    
    -- Get active announcements
    local announcements = MySQL.query.await('SELECT * FROM pf_gov_announcements WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY created_at DESC LIMIT 5', {})
    
    -- Get pending bills count
    local pendingBills = MySQL.query.await('SELECT COUNT(*) as count FROM pf_gov_bills WHERE status IN (?, ?)', {'unpaid', 'partial'})
    local pendingBillsCount = (pendingBills and #pendingBills > 0) and pendingBills[1].count or 0
    
    -- Get active licenses count
    local activeLicenses = MySQL.query.await('SELECT COUNT(*) as count FROM pf_gov_licenses WHERE status = ?', {'active'})
    local activeLicensesCount = (activeLicenses and #activeLicenses > 0) and activeLicenses[1].count or 0
    
    -- Get staff info
    local staffInfo = GetActiveStaff()
    
    cb({
        ok = true,
        dashboard = {
            treasury = treasuryBalance,
            businesses = businessStats,
            recentActivity = recentActivity or {},
            announcements = announcements or {},
            pendingBills = pendingBillsCount,
            activeLicenses = activeLicensesCount,
            staffCount = #staffInfo
        }
    })
end)

-- =====================================================
-- USER INFO & PERMISSIONS
-- =====================================================

RegisterNUICallback('user:getInfo', function(data, cb)
    local src = data.source or source
    
    local job = GetPlayerJob(src)
    if not job or job.name ~= Config.GovernmentJob then
        cb({ ok = false, error = 'not_government' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    local role = GetPlayerRole(src)
    
    -- Get permissions
    local roleConfig = Config.Roles[job.grade.level]
    local permissions = roleConfig and roleConfig.permissions or {}
    
    cb({
        ok = true,
        user = {
            citizenid = citizenid,
            name = name,
            role = role,
            grade = job.grade.level,
            permissions = permissions
        }
    })
end)

-- =====================================================
-- CONFIG & SETTINGS
-- =====================================================

RegisterNUICallback('config:get', function(data, cb)
    local src = data.source or source
    
    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end
    
    -- Return relevant config data to UI
    cb({
        ok = true,
        config = {
            taxCategories = Config.Taxes.Enforcement,
            lawCategories = Config.Laws.Categories,
            departments = Config.Budgets.DepartmentNames,
            licenseTypes = {
                citizen = Config.Licenses.CitizenTypes,
                business = Config.Licenses.BusinessTypes
            },
            billTypes = {'fine', 'tax', 'utility', 'license', 'invoice', 'other'},
            utilities = {
                powerEnabled = Config.Utilities.EnablePower,
                waterEnabled = Config.Utilities.EnableWater
            }
        }
    })
end)

-- =====================================================
-- ANNOUNCEMENTS
-- =====================================================

local ANNOUNCEMENT_PRIORITIES = { low = true, normal = true, high = true, urgent = true }

--- A City Hall announcement on the city timeline (the news publishes it).
function GovAnnounceAnnouncement(id, title, body, priority, category, author, actorCid)
    GovEmit('gov.announcement', {
        announcementId = tonumber(id), title = GovExcerpt(title, 120), priority = ANNOUNCEMENT_PRIORITIES[priority] and priority or 'normal',
        category = category or 'general', excerpt = GovExcerpt(body, 280), author = author,
        content = tostring(body or ''):gsub('[%c]', ' '):sub(1, 2000),
    }, { title = GovExcerpt(title, 120), actor = actorCid })
end

RegisterNUICallback('announcement:getAll', function(data, cb)
    MySQL.query('SELECT * FROM pf_gov_announcements WHERE active = 1 ORDER BY created_at DESC LIMIT 50', {}, function(result)
        cb({
            ok = true,
            announcements = result or {}
        })
    end)
end)

RegisterNUICallback('gov:getAnnouncements', function(data, cb)
    MySQL.query('SELECT * FROM pf_gov_announcements WHERE active = 1 ORDER BY created_at DESC LIMIT 50', {}, function(result)
        local mapped = {}
        for _, row in ipairs(result or {}) do
            mapped[#mapped + 1] = {
                id = row.id,
                title = row.title,
                body = row.content,
                author = row.created_by_name,
                createdAt = row.created_at
            }
        end
        cb({
            ok = true,
            data = mapped
        })
    end)
end)

RegisterNUICallback('gov:createAnnouncement', function(data, cb)
    local src = data.source or source

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    local authorName = data.author or name
    local expiresAt = data.duration and os.date('%Y-%m-%d %H:%M:%S', os.time() + data.duration) or nil

    local insertId = MySQL.insert.await(
        'INSERT INTO pf_gov_announcements (title, content, priority, category, created_by, created_by_name, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {data.title, data.body, 'normal', 'general', citizenid, authorName, expiresAt}
    )

    if insertId then
        LogAudit('announcement_create', citizenid, authorName, 'announcement', insertId, {
            title = data.title,
            priority = 'normal'
        })
        GovAnnounceAnnouncement(insertId, data.title, data.body, 'normal', 'general', authorName, citizenid)

        -- Sync to pf-computer emails
        if GetResourceState('pf-computer') == 'started' then
            TriggerEvent('pf-computer:gov:announcements:sync', {
                action = 'create',
                announcement = {
                    id = insertId,
                    title = data.title,
                    body = data.body,
                    author = authorName,
                    priority = 'normal',
                    created_at = os.date('!%Y-%m-%dT%H:%M:%SZ')
                }
            })
        end

        NotifyPlayer(src, 'Announcement created', 'success')
        cb({ ok = true, announcementId = insertId })
    else
        cb({ ok = false, error = 'database_error' })
    end
end)

RegisterNUICallback('announcement:create', function(data, cb)
    local src = data.source or source
    
    -- posting is for staff with the announcement permission (it used to be any government grade)
    local perm = (Config.GovApps and Config.GovApps.AnnouncementPermission) or 'laws'
    if not IsGovernmentEmployee(src) or not HasPermission(src, perm) then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    if type(data.title) ~= 'string' or data.title == '' or #data.title > 120
        or type(data.content) ~= 'string' or data.content == '' or #data.content > 4000 then
        cb({ ok = false, error = 'invalid' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local expiresAt = data.duration and os.date('%Y-%m-%d %H:%M:%S', os.time() + data.duration) or nil
    
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_announcements (title, content, priority, category, created_by, created_by_name, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {data.title, data.content, data.priority or 'normal', data.category or 'general', citizenid, name, expiresAt})
    
    if insertId then
        -- Log audit
        LogAudit('announcement_create', citizenid, name, 'announcement', insertId, {
            title = data.title,
            priority = data.priority
        })
        GovAnnounceAnnouncement(insertId, data.title, data.content, data.priority, data.category, name, citizenid)

        -- Sync to pf-computer emails
        if GetResourceState('pf-computer') == 'started' then
            TriggerEvent('pf-computer:gov:announcements:sync', {
                action = 'create',
                announcement = {
                    id = insertId,
                    title = data.title,
                    body = data.content,
                    author = name,
                    priority = data.priority or 'normal',
                    created_at = os.date('!%Y-%m-%dT%H:%M:%SZ')
                }
            })
        end
        
        -- Notify if urgent
        if data.priority == 'urgent' or data.priority == 'high' then
            TriggerClientEvent('QBCore:Notify', -1, '📢 Government: ' .. data.title, 'primary', 5000)
        end
        
        NotifyPlayer(src, 'Announcement created', 'success')
        cb({ ok = true, announcementId = insertId })
    else
        cb({ ok = false, error = 'database_error' })
    end
end)

RegisterNUICallback('announcement:delete', function(data, cb)
    local src = data.source or source
    
    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    MySQL.update('UPDATE pf_gov_announcements SET active = 0 WHERE id = ?', {data.announcementId})
    
    -- Sync deletion to pf-computer emails
    if GetResourceState('pf-computer') == 'started' then
        TriggerEvent('pf-computer:gov:announcements:sync', {
            action = 'delete',
            announcementId = data.announcementId
        })
    end
    
    NotifyPlayer(src, 'Announcement deleted', 'success')
    cb({ ok = true })
end)

-- =====================================================
-- SEARCH & LOOKUP
-- =====================================================

RegisterNUICallback('search:citizen', function(data, cb)
    local src = data.source or source
    
    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local searchTerm = data.search
    
    if not searchTerm or searchTerm == '' then
        cb({ ok = false, error = 'no_search_term' })
        return
    end
    
    -- Search in QBCore players (this is a simplified example)
    local result = MySQL.query.await('SELECT citizenid, charinfo FROM players WHERE citizenid LIKE ? OR JSON_EXTRACT(charinfo, "$.firstname") LIKE ? OR JSON_EXTRACT(charinfo, "$.lastname") LIKE ? LIMIT 20',
        {'%' .. searchTerm .. '%', '%' .. searchTerm .. '%', '%' .. searchTerm .. '%'})
    
    local citizens = {}
    if result then
        for _, row in ipairs(result) do
            local charinfo = json.decode(row.charinfo)
            table.insert(citizens, {
                citizenid = row.citizenid,
                firstname = charinfo.firstname,
                lastname = charinfo.lastname,
                name = charinfo.firstname .. ' ' .. charinfo.lastname
            })
        end
    end
    
    cb({
        ok = true,
        citizens = citizens
    })
end)

RegisterNUICallback('search:business', function(data, cb)
    local src = data.source or source
    
    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local searchTerm = data.search
    
    local result = MySQL.query.await('SELECT * FROM pf_gov_businesses WHERE business_name LIKE ? OR business_id LIKE ? LIMIT 20',
        {'%' .. searchTerm .. '%', '%' .. searchTerm .. '%'})
    
    cb({
        ok = true,
        businesses = result or {}
    })
end)

-- =====================================================
-- STATISTICS & REPORTS
-- =====================================================

RegisterNUICallback('stats:getRevenue', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'dashboard') and not HasPermission(src, 'budgets') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    -- Get revenue statistics
    local stats = MySQL.query.await([[
        SELECT 
            DATE(created_at) as date,
            SUM(CASE WHEN transaction_type = 'deposit' THEN amount ELSE 0 END) as deposits,
            SUM(CASE WHEN transaction_type = 'withdrawal' THEN amount ELSE 0 END) as withdrawals,
            SUM(CASE WHEN transaction_type = 'tax_collection' THEN amount ELSE 0 END) as tax_revenue
        FROM pf_gov_transactions
        WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        GROUP BY DATE(created_at)
        ORDER BY date DESC
    ]], {})
    
    cb({
        ok = true,
        stats = stats or {}
    })
end)

-- =====================================================
-- CLOSE UI
-- =====================================================

RegisterNUICallback('closeUI', function(data, cb)
    local src = data.source or source
    TriggerClientEvent('pf-government:client:closeUI', src)
    cb({ ok = true })
end)

RegisterNUICallback('hideUI', function(data, cb)
    local src = data.source or source
    TriggerClientEvent('pf-government:client:closeUI', src)
    cb({ ok = true })
end)

-- =====================================================
-- BUSINESSES
-- =====================================================

local businessExtensionsReady = false

local function EnsureBusinessExtensions()
    if businessExtensionsReady then
        return
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_business_licenses` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `business_id` VARCHAR(100) NOT NULL,
            `license_key` VARCHAR(100) NOT NULL,
            `license_label` VARCHAR(255) NOT NULL,
            `granted_by` VARCHAR(50) DEFAULT NULL,
            `granted_by_name` VARCHAR(255) DEFAULT NULL,
            `notes` TEXT DEFAULT NULL,
            `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `active` TINYINT(1) NOT NULL DEFAULT 1,
            UNIQUE KEY `uk_business_license` (`business_id`, `license_key`),
            INDEX `idx_business_id` (`business_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_business_inspections` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `business_id` VARCHAR(100) NOT NULL,
            `result_status` ENUM('compliant', 'warning', 'non_compliant', 'flagged') NOT NULL DEFAULT 'compliant',
            `findings` TEXT DEFAULT NULL,
            `inspected_by` VARCHAR(50) DEFAULT NULL,
            `inspected_by_name` VARCHAR(255) DEFAULT NULL,
            `inspected_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_business_id` (`business_id`),
            INDEX `idx_inspected_at` (`inspected_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `pf_gov_business_loans` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `business_id` VARCHAR(100) NOT NULL,
            `principal_amount` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
            `remaining_amount` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
            `interest_rate` DECIMAL(6,2) NOT NULL DEFAULT 0.00,
            `auto_pay` TINYINT(1) NOT NULL DEFAULT 0,
            `payment_interval_days` INT NOT NULL DEFAULT 7,
            `next_due_at` TIMESTAMP NULL DEFAULT NULL,
            `status` ENUM('active', 'paid', 'defaulted') NOT NULL DEFAULT 'active',
            `granted_by` VARCHAR(50) DEFAULT NULL,
            `granted_by_name` VARCHAR(255) DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX `idx_business_id` (`business_id`),
            INDEX `idx_status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    local hasStatusCol = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        {'pf_gov_businesses', 'business_status'}
    )
    if tonumber(hasStatusCol or 0) == 0 then
        MySQL.query.await("ALTER TABLE `pf_gov_businesses` ADD COLUMN `business_status` ENUM('active', 'closed') NOT NULL DEFAULT 'active' AFTER `compliance_status`", {})
    end

    local hasClosedAt = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        {'pf_gov_businesses', 'closed_at'}
    )
    if tonumber(hasClosedAt or 0) == 0 then
        MySQL.query.await('ALTER TABLE `pf_gov_businesses` ADD COLUMN `closed_at` TIMESTAMP NULL DEFAULT NULL AFTER `business_status`', {})
    end

    local hasLocationX = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        {'pf_gov_businesses', 'location_x'}
    )
    if tonumber(hasLocationX or 0) == 0 then
        MySQL.query.await('ALTER TABLE `pf_gov_businesses` ADD COLUMN `location_x` DECIMAL(11,4) NULL DEFAULT NULL AFTER `notes`', {})
    end

    local hasLocationY = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        {'pf_gov_businesses', 'location_y'}
    )
    if tonumber(hasLocationY or 0) == 0 then
        MySQL.query.await('ALTER TABLE `pf_gov_businesses` ADD COLUMN `location_y` DECIMAL(11,4) NULL DEFAULT NULL AFTER `location_x`', {})
    end

    local hasLocationZ = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        {'pf_gov_businesses', 'location_z'}
    )
    if tonumber(hasLocationZ or 0) == 0 then
        MySQL.query.await('ALTER TABLE `pf_gov_businesses` ADD COLUMN `location_z` DECIMAL(11,4) NULL DEFAULT NULL AFTER `location_y`', {})
    end

    local hasLocationAddress = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        {'pf_gov_businesses', 'location_address'}
    )
    if tonumber(hasLocationAddress or 0) == 0 then
        MySQL.query.await('ALTER TABLE `pf_gov_businesses` ADD COLUMN `location_address` VARCHAR(255) NULL DEFAULT NULL AFTER `location_z`', {})
    end

    businessExtensionsReady = true
end

local function BuildJobOptions()
    local options = {}
    local jobs = (QBCore and QBCore.Shared and QBCore.Shared.Jobs) or {}

    local metrics = MySQL.query.await([[ 
        SELECT
            business_id,
            business_name,
            business_type,
            owner_name,
            COALESCE(employee_count, 0) as employee_count,
            COALESCE(total_revenue, 0) as total_revenue,
            COALESCE(total_taxes_paid, 0) as total_taxes_paid,
            COALESCE(business_status, 'active') as business_status
        FROM pf_gov_businesses
    ]], {}) or {}

    local byId = {}
    for _, row in ipairs(metrics) do
        byId[row.business_id] = row
    end

    for name, data in pairs(jobs) do
        local row = byId[name]
        options[#options + 1] = {
            job = name,
            label = data.label or name,
            businessId = name,
            businessName = (row and row.business_name) or (data.label or name),
            ownerName = row and row.owner_name or 'Unassigned',
            employeeCount = row and tonumber(row.employee_count or 0) or 0,
            totalRevenue = row and tonumber(row.total_revenue or 0) or 0,
            totalTaxesPaid = row and tonumber(row.total_taxes_paid or 0) or 0,
            unpaidTaxBills = 0,
            businessStatus = row and row.business_status or 'active'
        }
    end

    table.sort(options, function(a, b)
        return tostring(a.label or '') < tostring(b.label or '')
    end)

    return options
end

RegisterNUICallback('business:getAll', function(data, cb)
    local src = data.source or source

    EnsureBusinessExtensions()

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end

    local result = MySQL.query.await('SELECT * FROM pf_gov_businesses ORDER BY business_name ASC', {})

    cb({
        ok = true,
        businesses = result or {}
    })
end)

RegisterNUICallback('business:getStats', function(data, cb)
    local src = data.source or source

    EnsureBusinessExtensions()

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end

    local rows = MySQL.query.await([[
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN COALESCE(business_status, 'active') = 'active' THEN 1 ELSE 0 END) as active,
            SUM(COALESCE(employee_count, 0)) as employees,
            SUM(COALESCE(total_revenue, 0)) as total_revenue,
            SUM(COALESCE(total_taxes_paid, 0)) as total_taxes_paid,
            SUM(CASE WHEN license_status NOT IN ('active') THEN 1 ELSE 0 END) as unlicensed,
            SUM(CASE WHEN compliance_status IN ('warning', 'non_compliant', 'flagged') THEN 1 ELSE 0 END) as non_compliant
        FROM pf_gov_businesses
    ]], {})

    local row = (rows and #rows > 0) and rows[1] or {}

    local taxBills = MySQL.query.await(
        'SELECT COUNT(*) as unpaid FROM pf_gov_bills WHERE bill_type = ? AND status IN (?, ?)',
        {'tax', 'unpaid', 'delinquent'}
    )
    local unpaidTaxes = (taxBills and #taxBills > 0) and tonumber(taxBills[1].unpaid or 0) or 0

    cb({
        ok = true,
        stats = {
            totalBusinesses = tonumber(row.total or 0),
            activeBusinesses = tonumber(row.active or 0),
            totalEmployees = tonumber(row.employees or 0),
            totalRevenue = tonumber(row.total_revenue or 0),
            totalTaxesPaid = tonumber(row.total_taxes_paid or 0),
            alerts = {
                unpaidTaxes = unpaidTaxes,
                unlicensed = tonumber(row.unlicensed or 0),
                nonCompliant = tonumber(row.non_compliant or 0)
            }
        }
    })
end)

RegisterNUICallback('business:getJobOptions', function(data, cb)
    local src = data.source or source

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end

    EnsureBusinessExtensions()
    cb({ ok = true, jobs = BuildJobOptions() })
end)

RegisterNUICallback('business:save', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()

    local businessId = tostring(data.businessId or '')
    local businessName = tostring(data.businessName or '')
    local businessType = tostring(data.businessType or '')
    local ownerId = tostring(data.ownerId or '')
    local ownerName = tostring(data.ownerName or 'Unassigned')
    local notes = tostring(data.notes or '')
    local businessStatus = tostring(data.businessStatus or 'active')
    local locationX = tonumber(data.locationX or (data.location and data.location.x))
    local locationY = tonumber(data.locationY or (data.location and data.location.y))
    local locationZ = tonumber(data.locationZ or (data.location and data.location.z))
    local locationAddress = tostring(data.locationAddress or '')

    if locationAddress == '' then
        locationAddress = nil
    end

    if businessId == '' or businessName == '' then
        cb({ ok = false, error = 'missing_fields' })
        return
    end

    local existing = MySQL.query.await('SELECT id, business_status FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', {businessId})
    if existing and #existing > 0 then
        local wasStatus = tostring(existing[1].business_status or 'active')
        MySQL.update.await(
            'UPDATE pf_gov_businesses SET business_name = ?, business_type = ?, owner_id = ?, owner_name = ?, notes = ?, location_x = ?, location_y = ?, location_z = ?, location_address = ?, business_status = ?, updated_at = NOW() WHERE business_id = ?',
            {businessName, businessType, ownerId, ownerName, notes, locationX, locationY, locationZ, locationAddress, businessStatus, businessId}
        )
        if wasStatus ~= businessStatus and (businessStatus == 'closed' or businessStatus == 'active') then
            GovAnnounceBusiness(businessStatus == 'closed' and 'gov.business.closed' or 'gov.business.reopened', businessId, {}, GetPlayerIdentifier(src))
        end
    else
        local inserted = MySQL.insert.await(
            'INSERT INTO pf_gov_businesses (business_id, business_name, business_type, owner_id, owner_name, notes, location_x, location_y, location_z, location_address, business_status, license_status, compliance_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            {businessId, businessName, businessType, ownerId, ownerName, notes, locationX, locationY, locationZ, locationAddress, businessStatus, 'none', 'compliant'}
        )
        if inserted then
            GovAnnounceBusiness('gov.business.registered', businessId, { owner = ownerName ~= 'Unassigned' and ownerName or nil }, GetPlayerIdentifier(src))
        end
    end

    cb({ ok = true })
end)

RegisterNUICallback('business:delete', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    if businessId == '' then
        cb({ ok = false, error = 'invalid_business_id' })
        return
    end

    MySQL.update.await('DELETE FROM pf_gov_businesses WHERE business_id = ?', {businessId})
    MySQL.update.await('DELETE FROM pf_gov_business_licenses WHERE business_id = ?', {businessId})
    MySQL.update.await('DELETE FROM pf_gov_business_inspections WHERE business_id = ?', {businessId})
    cb({ ok = true })
end)

RegisterNUICallback('business:setStatus', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    local status = tostring(data.status or 'active')
    if businessId == '' or (status ~= 'active' and status ~= 'closed') then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end

    local wasStatus = MySQL.scalar.await('SELECT COALESCE(business_status, "active") FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', {businessId})
    MySQL.update.await(
        'UPDATE pf_gov_businesses SET business_status = ?, closed_at = ?, updated_at = NOW() WHERE business_id = ?',
        {status, status == 'closed' and os.date('%Y-%m-%d %H:%M:%S') or nil, businessId}
    )
    if wasStatus ~= nil and type(wasStatus) ~= 'table' and tostring(wasStatus) ~= status then
        local reason = data.reason ~= nil and GovExcerpt(data.reason, 160) or nil
        GovAnnounceBusiness(status == 'closed' and 'gov.business.closed' or 'gov.business.reopened', businessId,
            { reason = reason ~= '' and reason or nil }, GetPlayerIdentifier(src))
    end
    cb({ ok = true })
end)

RegisterNUICallback('business:licenses:list', function(data, cb)
    local src = data.source or source

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    if businessId == '' then
        cb({ ok = true, licenses = {} })
        return
    end

    local rows = MySQL.query.await(
        'SELECT * FROM pf_gov_business_licenses WHERE business_id = ? ORDER BY issued_at DESC',
        {businessId}
    ) or {}
    cb({ ok = true, licenses = rows })
end)

RegisterNUICallback('business:licenses:grant', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    local licenseKey = tostring(data.licenseKey or '')
    local licenseLabel = tostring(data.licenseLabel or licenseKey)
    local active = data.active == nil and true or data.active == true

    if businessId == '' or licenseKey == '' then
        cb({ ok = false, error = 'missing_fields' })
        return
    end

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)

    MySQL.insert.await(
        'INSERT INTO pf_gov_business_licenses (business_id, license_key, license_label, granted_by, granted_by_name, notes, active) VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE license_label = VALUES(license_label), granted_by = VALUES(granted_by), granted_by_name = VALUES(granted_by_name), notes = VALUES(notes), active = VALUES(active)',
        {businessId, licenseKey, licenseLabel, citizenid, name, tostring(data.notes or ''), active and 1 or 0}
    )

    cb({ ok = true })
end)

RegisterNUICallback('business:inspections:list', function(data, cb)
    local src = data.source or source

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    local rows = MySQL.query.await(
        'SELECT * FROM pf_gov_business_inspections WHERE business_id = ? ORDER BY inspected_at DESC',
        {businessId}
    ) or {}
    cb({ ok = true, inspections = rows })
end)

RegisterNUICallback('business:inspections:file', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    local resultStatus = tostring(data.resultStatus or 'compliant')
    local findings = tostring(data.findings or '')
    if businessId == '' then
        cb({ ok = false, error = 'invalid_business_id' })
        return
    end

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    local inspectionId = MySQL.insert.await(
        'INSERT INTO pf_gov_business_inspections (business_id, result_status, findings, inspected_by, inspected_by_name) VALUES (?, ?, ?, ?, ?)',
        {businessId, resultStatus, findings, citizenid, name}
    )
    MySQL.update.await('UPDATE pf_gov_businesses SET compliance_status = ?, notes = ?, updated_at = NOW() WHERE business_id = ?', {resultStatus, findings, businessId})
    if inspectionId then GovAnnounceInspection(businessId, resultStatus, findings, name, citizenid) end

    cb({ ok = true, inspectionId = tonumber(inspectionId) })
end)

RegisterNUICallback('business:loans:list', function(data, cb)
    local src = data.source or source

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'not_government' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    local rows = MySQL.query.await('SELECT * FROM pf_gov_business_loans WHERE business_id = ? ORDER BY created_at DESC', {businessId}) or {}
    cb({ ok = true, loans = rows })
end)

RegisterNUICallback('business:loans:grant', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()
    local businessId = tostring(data.businessId or '')
    local amount = tonumber(data.amount or 0) or 0
    local interestRate = tonumber(data.interestRate or 0) or 0
    local autoPay = data.autoPay == true
    local paymentIntervalDays = tonumber(data.paymentIntervalDays or 7) or 7
    if businessId == '' or amount <= 0 then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end

    amount = math.floor(amount * 100) / 100
    local maxLoan = tonumber(Config.Businesses and Config.Businesses.MaxLoan) or 1000000
    if amount ~= amount or amount <= 0 or amount > maxLoan or #businessId > 64 then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end
    local treasury = Config.Treasury and Config.Treasury.UseSocietyAccount and Config.Treasury.SocietyAccount
    if not treasury or treasury == '' or GetResourceState('pfm-banking') ~= 'started' then
        cb({ ok = false, error = 'treasury_unavailable' })
        return
    end

    local businessAccount = Loans.AccountFor(businessId)
    if not businessAccount then
        cb({ ok = false, error = 'business_has_no_account' })
        return
    end
    paymentIntervalDays = math.max(1, math.min(math.floor(paymentIntervalDays), 90))
    interestRate = math.max(0, math.min(interestRate, 50))
    Loans.EnsureColumns()

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    local nextDue = os.date('%Y-%m-%d %H:%M:%S', os.time() + (paymentIntervalDays * 86400))

    local loanId = MySQL.insert.await(
        'INSERT INTO pf_gov_business_loans (business_id, principal_amount, remaining_amount, interest_rate, auto_pay, payment_interval_days, next_due_at, granted_by, granted_by_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {businessId, amount, amount, interestRate, autoPay and 1 or 0, paymentIntervalDays, nextDue, citizenid, name}
    )
    if not loanId then
        cb({ ok = false, error = 'database_error' })
        return
    end

    -- the loan is paid out of the treasury (it used to be created from nothing with AddMoney)
    local okCall, res = pcall(function()
        return exports['pfm-banking']:Transfer({
            from = 'society:' .. treasury, to = businessAccount, amount = amount,
            key = ('pf-government:loan:%s:%s'):format(loanId, PFPayout.NewId()), kind = 'loan', reason = 'Government business loan', actor = citizenid,
        })
    end)
    if not okCall or type(res) ~= 'table' or not res.ok then
        MySQL.update.await('DELETE FROM pf_gov_business_loans WHERE id = ?', { loanId })
        cb({ ok = false, error = (type(res) == 'table' and res.error == 'insufficient_funds') and 'insufficient_treasury_funds' or 'payment_failed' })
        return
    end

    cb({ ok = true })
end)

RegisterNUICallback('business:loans:pay', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()
    local loanId = tonumber(data.loanId or 0) or 0
    local payment = tonumber(data.paymentAmount or 0) or 0
    if loanId <= 0 or payment <= 0 then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end

    local loan = MySQL.single.await('SELECT * FROM pf_gov_business_loans WHERE id = ? LIMIT 1', {loanId})
    if not loan then
        cb({ ok = false, error = 'loan_not_found' })
        return
    end

    -- the business pays the treasury (this used to mark the loan paid without moving any money)
    local take = math.floor(math.min(payment, tonumber(loan.remaining_amount) or 0) * 100) / 100
    local treasury = Config.Treasury and Config.Treasury.UseSocietyAccount and Config.Treasury.SocietyAccount
    if take <= 0 or loan.status == 'paid' then
        cb({ ok = false, error = 'nothing_owed' })
        return
    end
    if not treasury or treasury == '' or GetResourceState('pfm-banking') ~= 'started' then
        cb({ ok = false, error = 'treasury_unavailable' })
        return
    end
    local businessAccount = Loans.AccountFor(tostring(loan.business_id))
    if not businessAccount then
        cb({ ok = false, error = 'business_has_no_account' })
        return
    end
    Loans.EnsureColumns()
    local okCall, res = pcall(function()
        return exports['pfm-banking']:Transfer({
            from = businessAccount, to = 'society:' .. treasury, amount = take,
            key = ('pf-government:loanpay:%s:%s'):format(loanId, PFPayout.NewId()), kind = 'loan_repayment',
            reason = 'Government loan repayment', actor = GetPlayerIdentifier(src),
        })
    end)
    if not okCall or type(res) ~= 'table' or not res.ok then
        cb({ ok = false, error = (type(res) == 'table' and res.error == 'insufficient_funds') and 'insufficient_business_funds' or 'payment_failed' })
        return
    end

    loan = MySQL.single.await('SELECT * FROM pf_gov_business_loans WHERE id = ? LIMIT 1', {loanId}) or loan
    local remaining, status, due = Loans.ApplyPayment(loan, take)
    cb({ ok = true, remaining = remaining, status = status, amountDue = due })
end)

-- A transfer changes the business's real owner first (pf-stores store owner, pf-restaurants owner
-- role), then this record; if the business resource refuses, nothing changes. Mechanic shops
-- belong to their job's bosses and cannot be transferred here.
local TRANSFER_TARGETS = {
    store = { resource = 'pf-stores', export = 'SetStoreOwnerFromGovernment' },
    restaurant = { resource = 'pf-restaurants', export = 'SetOwnerFromGovernment' },
}

function TransferBusinessOwnership(businessId, newOwnerId, newOwnerName, actorCid)
    if type(businessId) ~= 'string' or businessId == '' then return false, 'invalid_business_id' end
    local current = MySQL.single.await('SELECT id, owner_id, owner_name FROM pf_gov_businesses WHERE business_id = ?', { businessId })
    if not current then return false, 'business_not_found' end
    newOwnerId = (type(newOwnerId) == 'string' and newOwnerId ~= '') and newOwnerId or nil
    local kind, localId = businessId:match('^(%a+):(.+)$')
    if kind == 'mechanic' then return false, 'job_business' end
    local target = kind and TRANSFER_TARGETS[kind]
    if target then
        if GetResourceState(target.resource) ~= 'started' then return false, target.resource .. '_offline' end
        local ok, done, err = pcall(function() return exports[target.resource][target.export](exports[target.resource], localId, newOwnerId) end)
        if not ok or done ~= true then return false, (ok and err) or 'transfer_failed' end
    elseif newOwnerId and not MySQL.scalar.await('SELECT 1 FROM players WHERE citizenid = ? LIMIT 1', { newOwnerId }) then
        return false, 'unknown_citizen'
    end
    MySQL.update.await('UPDATE pf_gov_businesses SET owner_id = ?, owner_name = ?, updated_at = NOW() WHERE business_id = ?',
        { newOwnerId or 'unowned', newOwnerName or (newOwnerId and newOwnerId or 'Unassigned'), businessId })
    if tostring(current.owner_id or 'unowned') ~= tostring(newOwnerId or 'unowned') then
        -- names only: the citizen ids stay out of the public event
        local previous = (current.owner_id and current.owner_id ~= 'unowned') and current.owner_name or nil
        GovAnnounceBusiness('gov.business.transferred', businessId, {
            newOwner = newOwnerId and (newOwnerName or 'a new owner') or nil, previousOwner = previous,
            forSale = newOwnerId == nil,
        }, actorCid)
    end
    return true
end

-- For other apps (PF Tablet): the same transfer, checked against the caller's government
-- permission here, and written to the audit log.
exports('TransferBusinessOwnershipAs', function(src, businessId, ownerId, ownerName)
    if not HasPermission(src, 'businesses') then return false, 'no_permission' end
    businessId = tostring(businessId or '')
    ownerId = ownerId ~= nil and tostring(ownerId):sub(1, 50) or nil
    ownerName = ownerName ~= nil and tostring(ownerName):sub(1, 255) or nil
    local ok, err = TransferBusinessOwnership(businessId, ownerId, ownerName, GetPlayerIdentifier(src))
    if not ok then return false, err end
    LogAudit('business_transfer', GetPlayerIdentifier(src), GetPlayerName(src), 'business', businessId, {
        newOwner = ownerName, newOwnerId = ownerId, via = 'tablet'
    })
    return true
end)

RegisterNUICallback('business:updateOwner', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then -- transfers need the businesses permission, not any grade
        cb({ ok = false, error = 'not_government' })
        return
    end

    local businessId = tostring(data.businessId or '')
    local ownerId = data.ownerId ~= nil and tostring(data.ownerId):sub(1, 50) or nil
    local ownerName = data.ownerName ~= nil and tostring(data.ownerName):sub(1, 255) or nil
    local ok, err = TransferBusinessOwnership(businessId, ownerId, ownerName, GetPlayerIdentifier(src))
    if not ok then
        cb({ ok = false, error = err })
        return
    end
    LogAudit('business_transfer', GetPlayerIdentifier(src), GetPlayerName(src), 'business', businessId, {
        newOwner = ownerName,
        newOwnerId = ownerId
    })
    cb({ ok = true })
end)

RegisterNUICallback('business:updateLocation', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    EnsureBusinessExtensions()

    local businessId = tostring(data.businessId or '')
    local locationX = tonumber(data.locationX)
    local locationY = tonumber(data.locationY)
    local locationZ = tonumber(data.locationZ)
    local locationAddress = tostring(data.locationAddress or '')

    if businessId == '' then
        cb({ ok = false, error = 'invalid_business_id' })
        return
    end

    if locationAddress == '' then
        locationAddress = nil
    end

    if (locationX and not locationY) or (locationY and not locationX) then
        cb({ ok = false, error = 'invalid_location_pair' })
        return
    end

    local existing = MySQL.single.await('SELECT business_id FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', {businessId})
    if not existing then
        cb({ ok = false, error = 'business_not_found' })
        return
    end

    MySQL.update.await(
        'UPDATE pf_gov_businesses SET location_x = ?, location_y = ?, location_z = ?, location_address = ?, updated_at = NOW() WHERE business_id = ?',
        {locationX, locationY, locationZ, locationAddress, businessId}
    )

    cb({ ok = true })
end)

-- =====================================================
-- CIVILIANS
-- =====================================================

local function GovDbTableExists(tableName)
    local rows = MySQL.query.await(
        'SELECT COUNT(*) as c FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? LIMIT 1',
        { tableName }
    )
    return rows and rows[1] and tonumber(rows[1].c or 0) > 0
end

local function GovDbHasColumn(tableName, columnName)
    local rows = MySQL.query.await(
        'SELECT COUNT(*) as c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? LIMIT 1',
        { tableName, columnName }
    )
    return rows and rows[1] and tonumber(rows[1].c or 0) > 0
end

local function ResolveCitizenStorage()
    -- Prefer `users` when available, per server owner preference.
    if GovDbTableExists('users') then
        if GovDbHasColumn('users', 'citizenid') and GovDbHasColumn('users', 'charinfo') then
            return { table = 'users', kind = 'qb', idCol = 'citizenid' }
        end
        if GovDbHasColumn('users', 'identifier') and GovDbHasColumn('users', 'firstname') and GovDbHasColumn('users', 'lastname') then
            return { table = 'users', kind = 'esx', idCol = 'identifier' }
        end
    end

    if GovDbTableExists('players') then
        return { table = 'players', kind = 'qb', idCol = 'citizenid' }
    end

    return nil
end

local function DecodeJsonSafely(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, parsed = pcall(json.decode, value)
    if ok and type(parsed) == 'table' then return parsed end
    return {}
end

local function BuildLicenseList(meta)
    local licenses = {}
    local lic = (meta.licences or meta.licenses) or {}
    if lic.driver == true or lic.drivers_license == true then licenses[#licenses + 1] = 'Driver License' end
    if lic.weapon == true or lic.firearms_license == true then licenses[#licenses + 1] = 'Weapon License' end
    if lic.business == true then licenses[#licenses + 1] = 'Business License' end
    return licenses, lic
end

local function NormalizeVehicleName(raw)
    if type(raw) == 'table' then
        return raw.model or raw.name or raw.vehicle or 'Unknown'
    end
    if type(raw) == 'string' then
        local decoded = DecodeJsonSafely(raw)
        if next(decoded) ~= nil then
            return decoded.model or decoded.name or decoded.vehicle or raw
        end
        return raw
    end
    return 'Unknown'
end

RegisterNUICallback('civilian:search', function(data, cb)
    local src = data.source or source

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local storage = ResolveCitizenStorage()
    if not storage then
        cb({ ok = false, error = 'no_citizen_storage_table' })
        return
    end

    local query    = data.query or ''
    local page     = tonumber(data.page) or 1
    local pageSize = tonumber(data.pageSize) or 12
    local offset   = (page - 1) * pageSize
    local like     = '%' .. query .. '%'

    local total = 0
    local rows = {}

    if storage.kind == 'qb' then
        local countRows = MySQL.query.await(
            ('SELECT COUNT(*) as c FROM %s WHERE %s LIKE ? OR JSON_EXTRACT(charinfo, "$.firstname") LIKE ? OR JSON_EXTRACT(charinfo, "$.lastname") LIKE ? OR JSON_EXTRACT(charinfo, "$.phone") LIKE ?')
                :format(storage.table, storage.idCol),
            { like, like, like, like }
        )
        total = (countRows and countRows[1] and countRows[1].c) or 0

        rows = MySQL.query.await(
            ('SELECT %s as citizenid, charinfo, job, gang, metadata FROM %s WHERE %s LIKE ? OR JSON_EXTRACT(charinfo, "$.firstname") LIKE ? OR JSON_EXTRACT(charinfo, "$.lastname") LIKE ? OR JSON_EXTRACT(charinfo, "$.phone") LIKE ? ORDER BY JSON_EXTRACT(charinfo, "$.lastname") ASC LIMIT ? OFFSET ?')
                :format(storage.idCol, storage.table, storage.idCol),
            { like, like, like, like, pageSize, offset }
        )
    else
        local hasPhone = GovDbHasColumn('users', 'phone')
        local phoneWhere = hasPhone and ' OR phone LIKE ?' or ''
        local phoneSel = hasPhone and ', phone' or ''
        local countRows = MySQL.query.await(
            ('SELECT COUNT(*) as c FROM users WHERE identifier LIKE ? OR firstname LIKE ? OR lastname LIKE ?%s')
                :format(phoneWhere),
            hasPhone and { like, like, like, like } or { like, like, like }
        )
        total = (countRows and countRows[1] and countRows[1].c) or 0

        rows = MySQL.query.await(
            ('SELECT identifier as citizenid, firstname, lastname, dateofbirth, sex, nationality, job%s FROM users WHERE identifier LIKE ? OR firstname LIKE ? OR lastname LIKE ?%s ORDER BY lastname ASC LIMIT ? OFFSET ?')
                :format(phoneSel, phoneWhere),
            hasPhone and { like, like, like, like, pageSize, offset } or { like, like, like, pageSize, offset }
        )
    end

    local citizens = {}
    for _, r in ipairs(rows or {}) do
        local name = 'Unknown'
        local dob = ''
        local phone = ''
        local nationality = ''
        local gender = ''
        local jobLabel = 'Unemployed'
        local licenses = {}

        if storage.kind == 'qb' then
            local ci = DecodeJsonSafely(r.charinfo)
            local meta = DecodeJsonSafely(r.metadata)
            local jobData = DecodeJsonSafely(r.job)
            name = (((ci.firstname or '') .. ' ' .. (ci.lastname or ''))):gsub('^%s*(.-)%s*$', '%1')
            dob = ci.birthdate or ''
            phone = ci.phone or ''
            nationality = ci.nationality or ''
            gender = ci.gender or ''
            jobLabel = (jobData and (jobData.label or jobData.name)) or 'Unemployed'
            licenses = BuildLicenseList(meta)
        else
            name = (((r.firstname or '') .. ' ' .. (r.lastname or ''))):gsub('^%s*(.-)%s*$', '%1')
            dob = r.dateofbirth or ''
            phone = r.phone or ''
            nationality = r.nationality or ''
            gender = r.sex or ''
            jobLabel = r.job or 'Unemployed'
            licenses = {}
        end

        table.insert(citizens, {
            citizenId   = r.citizenid,
            name        = name ~= '' and name or 'Unknown',
            dob         = dob,
            phone       = phone,
            nationality = nationality,
            gender      = gender,
            job         = jobLabel,
            licenses    = licenses,
        })
    end

    cb({ ok = true, civilians = citizens, total = total })
end)

RegisterNUICallback('civilian:getProfile', function(data, cb)
    local src = data.source or source

    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenId = data.citizenId or ''
    if citizenId == '' then
        cb({ ok = false, error = 'no_citizenid' })
        return
    end

    local storage = ResolveCitizenStorage()
    if not storage then
        cb({ ok = false, error = 'no_citizen_storage_table' })
        return
    end

    local rows = nil
    if storage.kind == 'qb' then
        rows = MySQL.query.await(
            ('SELECT %s as citizenid, charinfo, job, gang, metadata FROM %s WHERE %s = ? LIMIT 1'):format(storage.idCol, storage.table, storage.idCol),
            { citizenId }
        )
    else
        local hasPhone = GovDbHasColumn('users', 'phone')
        local phoneSel = hasPhone and ', phone' or ''
        rows = MySQL.query.await(
            ('SELECT identifier as citizenid, firstname, lastname, dateofbirth, sex, nationality, job%s FROM users WHERE identifier = ? LIMIT 1'):format(phoneSel),
            { citizenId }
        )
    end

    if not rows or #rows == 0 then
        cb({ ok = false, error = 'not_found' })
        return
    end

    local r = rows[1]
    local ci = {}
    local meta = {}
    local jobData = {}
    local gangData = {}
    local jobLabel = 'Unemployed'
    local gangLabel = 'None'
    local licenses = {}
    local licenseFlags = {}
    local name = 'Unknown'
    local dob = ''
    local phone = ''
    local nationality = ''
    local gender = ''

    if storage.kind == 'qb' then
        ci = DecodeJsonSafely(r.charinfo)
        meta = DecodeJsonSafely(r.metadata)
        jobData = DecodeJsonSafely(r.job)
        gangData = DecodeJsonSafely(r.gang)
        jobLabel = (jobData and (jobData.label or jobData.name)) or 'Unemployed'
        gangLabel = (gangData and gangData.name ~= 'none' and (gangData.label or gangData.name)) or 'None'
        local builtLicenses, flags = BuildLicenseList(meta)
        licenses = builtLicenses
        licenseFlags = flags or {}
        name = (((ci.firstname or '') .. ' ' .. (ci.lastname or ''))):gsub('^%s*(.-)%s*$', '%1')
        dob = ci.birthdate or ''
        phone = ci.phone or ''
        nationality = ci.nationality or ''
        gender = ci.gender or ''
    else
        name = (((r.firstname or '') .. ' ' .. (r.lastname or ''))):gsub('^%s*(.-)%s*$', '%1')
        dob = r.dateofbirth or ''
        phone = r.phone or ''
        nationality = r.nationality or ''
        gender = r.sex or ''
        jobLabel = r.job or 'Unemployed'
        licenses = {}
        licenseFlags = {}
    end

    -- Vehicles
    local vehicleRows = MySQL.query.await(
        'SELECT plate, vehicle FROM player_vehicles WHERE citizenid = ? ORDER BY plate LIMIT 50',
        { citizenId }
    )
    local vehicles = {}
    for _, v in ipairs(vehicleRows or {}) do
        table.insert(vehicles, {
            plate = v.plate,
            vehicle = NormalizeVehicleName(v.vehicle),
            garage = v.garage,
            state = v.state
        })
    end

    local properties = {}
    if GovDbTableExists('player_houses') and GovDbHasColumn('player_houses', 'citizenid') and GovDbHasColumn('player_houses', 'house') then
        local houseRows = MySQL.query.await('SELECT house FROM player_houses WHERE citizenid = ? ORDER BY house ASC', { citizenId })
        for _, h in ipairs(houseRows or {}) do
            properties[#properties + 1] = {
                source = 'qb-houses',
                name = tostring(h.house or ''),
                address = tostring(h.house or ''),
            }
        end
    end

    if GovDbTableExists('apartments') and GovDbHasColumn('apartments', 'citizenid') then
        local aptRows = MySQL.query.await('SELECT label, type FROM apartments WHERE citizenid = ? LIMIT 50', { citizenId })
        for _, a in ipairs(aptRows or {}) do
            local label = tostring(a.label or a.type or 'Apartment')
            properties[#properties + 1] = {
                source = 'apartments',
                name = label,
                address = label,
            }
        end
    end

    local usePoliceMdt = (Config.Civilians and Config.Civilians.PfPoliceMdt) ~= false
    local mdtResource = (Config.Civilians and Config.Civilians.PoliceMdtResource) or 'pf-policemdt-DEV'
    local mdtEnabled = usePoliceMdt and GetResourceState(mdtResource) == 'started'

    local profilePicture = nil
    local convictions = {}
    local incidents = {}
    local hasCriminalRecord = false

    if mdtEnabled then
        if GovDbTableExists('pf_mdt_citizen_profiles') then
            local photoRows = MySQL.query.await('SELECT profilePicture FROM pf_mdt_citizen_profiles WHERE citizenId = ? LIMIT 1', { citizenId })
            if photoRows and photoRows[1] then
                profilePicture = photoRows[1].profilePicture
            end
        end

        if GovDbTableExists('pf_mdt_sentences') then
            local sentenceRows = MySQL.query.await(
                'SELECT id, title, officerName, createdAt, prisonTime, prisonTimeAfterReduction FROM pf_mdt_sentences WHERE citizenId = ? ORDER BY id DESC LIMIT 100',
                { citizenId }
            )
            for _, s in ipairs(sentenceRows or {}) do
                convictions[#convictions + 1] = {
                    id = s.id,
                    title = s.title,
                    officer = s.officerName,
                    createdAt = s.createdAt,
                    prisonTime = s.prisonTimeAfterReduction or s.prisonTime or 0
                }
            end
        end

        if GovDbTableExists('pf_mdt_incidents') then
            local idLike = '%' .. citizenId .. '%'
            local nameLike = '%' .. (name or '') .. '%'
            local incidentRows = MySQL.query.await(
                'SELECT id, incidentId, title, status, location, createdAt FROM pf_mdt_incidents WHERE involvedCitizenIds LIKE ? OR involvedCitizens LIKE ? ORDER BY createdAt DESC LIMIT 50',
                { idLike, nameLike }
            )
            for _, i in ipairs(incidentRows or {}) do
                incidents[#incidents + 1] = {
                    id = i.id,
                    incidentId = i.incidentId,
                    title = i.title,
                    status = i.status,
                    location = i.location,
                    createdAt = i.createdAt,
                }
            end
        end

        hasCriminalRecord = (#convictions > 0 or #incidents > 0)
    end

    cb({
        ok = true,
        profile = {
            citizenId   = r.citizenid,
            name        = name ~= '' and name or 'Unknown',
            firstname   = ci.firstname or r.firstname or '',
            lastname    = ci.lastname or r.lastname or '',
            dob         = dob,
            phone       = phone,
            nationality = nationality,
            gender      = gender,
            job         = jobLabel,
            gang        = gangLabel,
            licenses    = licenses,
            licenseFlags = licenseFlags,
            vehicles    = vehicles,
            properties  = properties,
            profilePicture = profilePicture,
            mdtEnabled = mdtEnabled,
            hasCriminalRecord = hasCriminalRecord,
            convictions = convictions,
            incidents = incidents,
        }
    })
end)

RegisterNUICallback('civilian:getJobs', function(data, cb)
    local src = data.source or source
    if not IsGovernmentEmployee(src) then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local jobs = {}
    local coreObj = QBCore
    if coreObj and coreObj.Shared and coreObj.Shared.Jobs then
        for name, info in pairs(coreObj.Shared.Jobs) do
            jobs[#jobs + 1] = {
                name = name,
                label = info.label or name
            }
        end
        table.sort(jobs, function(a, b) return tostring(a.label) < tostring(b.label) end)
    end

    cb({ ok = true, jobs = jobs })
end)

-- Changing a citizen's identity, job, vehicles or criminal record needs the 'civilians' permission
-- (licenses need 'licenses'). Any government grade could do all of it before, e.g. a grade-0 utility
-- manager clearing convictions or giving out a weapon license.
RegisterNUICallback('civilian:updateIdentity', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'civilians') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenId = data.citizenId or ''
    if citizenId == '' then
        cb({ ok = false, error = 'no_citizenid' })
        return
    end

    local storage = ResolveCitizenStorage()
    if not storage then
        cb({ ok = false, error = 'no_citizen_storage_table' })
        return
    end

    if storage.kind == 'qb' then
        local rows = MySQL.query.await(
            ('SELECT charinfo FROM %s WHERE %s = ? LIMIT 1'):format(storage.table, storage.idCol),
            { citizenId }
        )
        if not rows or not rows[1] then
            cb({ ok = false, error = 'not_found' })
            return
        end

        local charinfo = DecodeJsonSafely(rows[1].charinfo)
        if data.firstname ~= nil then charinfo.firstname = tostring(data.firstname) end
        if data.lastname ~= nil then charinfo.lastname = tostring(data.lastname) end
        if data.dob ~= nil then charinfo.birthdate = tostring(data.dob) end
        if data.phone ~= nil then charinfo.phone = tostring(data.phone) end
        if data.nationality ~= nil then charinfo.nationality = tostring(data.nationality) end

        MySQL.update.await(
            ('UPDATE %s SET charinfo = ? WHERE %s = ?'):format(storage.table, storage.idCol),
            { json.encode(charinfo), citizenId }
        )
    else
        local hasPhone = GovDbHasColumn('users', 'phone')
        local hasNationality = GovDbHasColumn('users', 'nationality')
        local sql = 'UPDATE users SET firstname = ?, lastname = ?, dateofbirth = ?'
        local params = {
            tostring(data.firstname or ''),
            tostring(data.lastname or ''),
            tostring(data.dob or ''),
        }
        if hasPhone then
            sql = sql .. ', phone = ?'
            params[#params + 1] = tostring(data.phone or '')
        end
        if hasNationality then
            sql = sql .. ', nationality = ?'
            params[#params + 1] = tostring(data.nationality or '')
        end
        sql = sql .. ' WHERE identifier = ?'
        params[#params + 1] = citizenId
        MySQL.update.await(sql, params)
    end

    cb({ ok = true })
end)

RegisterNUICallback('civilian:updateJob', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'civilians') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenId = data.citizenId or ''
    local jobName = data.jobName or ''
    if citizenId == '' or jobName == '' then
        cb({ ok = false, error = 'invalid_input' })
        return
    end

    local storage = ResolveCitizenStorage()
    if not storage then
        cb({ ok = false, error = 'no_citizen_storage_table' })
        return
    end

    if storage.kind == 'qb' then
        local sharedJob = QBCore and QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[jobName]
        if not sharedJob then
            cb({ ok = false, error = 'invalid_job' })
            return
        end

        local newJob = {
            name = jobName,
            label = sharedJob.label or jobName,
            onduty = true,
            type = sharedJob.type or 'none',
            grade = {
                name = sharedJob.grades and sharedJob.grades['0'] and sharedJob.grades['0'].name or 'Recruit',
                level = 0,
            }
        }

        MySQL.update.await(
            ('UPDATE %s SET job = ? WHERE %s = ?'):format(storage.table, storage.idCol),
            { json.encode(newJob), citizenId }
        )
    else
        MySQL.update.await('UPDATE users SET job = ? WHERE identifier = ?', { jobName, citizenId })
    end

    cb({ ok = true })
end)

RegisterNUICallback('civilian:toggleLicense', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'licenses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenId = data.citizenId or ''
    local licenseKey = data.licenseKey or ''
    local enabled = data.enabled == true
    if citizenId == '' or licenseKey == '' then
        cb({ ok = false, error = 'invalid_input' })
        return
    end

    local storage = ResolveCitizenStorage()
    if not storage or storage.kind ~= 'qb' then
        cb({ ok = false, error = 'license_updates_supported_for_qb_storage_only' })
        return
    end

    local rows = MySQL.query.await(
        ('SELECT metadata FROM %s WHERE %s = ? LIMIT 1'):format(storage.table, storage.idCol),
        { citizenId }
    )
    if not rows or not rows[1] then
        cb({ ok = false, error = 'not_found' })
        return
    end

    local metadata = DecodeJsonSafely(rows[1].metadata)
    metadata.licences = metadata.licences or metadata.licenses or {}
    metadata.licenses = metadata.licences
    metadata.licences[licenseKey] = enabled

    MySQL.update.await(
        ('UPDATE %s SET metadata = ? WHERE %s = ?'):format(storage.table, storage.idCol),
        { json.encode(metadata), citizenId }
    )

    cb({ ok = true })
end)

RegisterNUICallback('civilian:seizeVehicle', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'civilians') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenId = data.citizenId or ''
    local plate = data.plate or ''
    if citizenId == '' or plate == '' then
        cb({ ok = false, error = 'invalid_input' })
        return
    end

    local hasGarage = GovDbHasColumn('player_vehicles', 'garage')
    local hasState = GovDbHasColumn('player_vehicles', 'state')
    local hasDepot = GovDbHasColumn('player_vehicles', 'depotprice')

    local sets = {}
    local params = {}
    if hasGarage then
        sets[#sets + 1] = 'garage = ?'
        params[#params + 1] = 'gov_lockup'
    end
    if hasState then
        sets[#sets + 1] = 'state = ?'
        params[#params + 1] = 2
    end
    if hasDepot then
        sets[#sets + 1] = 'depotprice = ?'
        params[#params + 1] = 0
    end
    if #sets == 0 then
        cb({ ok = false, error = 'no_supported_vehicle_columns' })
        return
    end

    params[#params + 1] = plate
    params[#params + 1] = citizenId

    local affected = MySQL.update.await(
        ('UPDATE player_vehicles SET %s WHERE plate = ? AND citizenid = ?'):format(table.concat(sets, ', ')),
        params
    )

    if (tonumber(affected) or 0) <= 0 then
        cb({ ok = false, error = 'vehicle_not_found' })
        return
    end

    cb({ ok = true })
end)

RegisterNUICallback('civilian:deleteRecord', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'civilians') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    if (Config.Civilians and Config.Civilians.PfPoliceMdt) == false then
        cb({ ok = false, error = 'mdt_integration_disabled' })
        return
    end

    local recordType = tostring(data.recordType or '')
    local recordId = tonumber(data.recordId)
    if recordType == '' or not recordId then
        cb({ ok = false, error = 'invalid_input' })
        return
    end

    if recordType == 'conviction' then
        if not GovDbTableExists('pf_mdt_sentences') then
            cb({ ok = false, error = 'sentences_table_missing' })
            return
        end
        MySQL.update.await('DELETE FROM pf_mdt_sentences WHERE id = ?', { recordId })
        cb({ ok = true })
        return
    end

    if recordType == 'incident' then
        if not GovDbTableExists('pf_mdt_incidents') then
            cb({ ok = false, error = 'incidents_table_missing' })
            return
        end
        MySQL.update.await('DELETE FROM pf_mdt_incidents WHERE id = ?', { recordId })
        cb({ ok = true })
        return
    end

    cb({ ok = false, error = 'unsupported_record_type' })
end)

RegisterNUICallback('civilian:clearConvictions', function(data, cb)
    local src = data.source or source
    if not HasPermission(src, 'civilians') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenId = data.citizenId or ''
    if citizenId == '' then
        cb({ ok = false, error = 'no_citizenid' })
        return
    end

    if not GovDbTableExists('pf_mdt_sentences') then
        cb({ ok = false, error = 'sentences_table_missing' })
        return
    end

    MySQL.update.await('DELETE FROM pf_mdt_sentences WHERE citizenId = ?', { citizenId })
    cb({ ok = true })
end)

print('^2[PF-GOVERNMENT]^7 NUI callbacks loaded')

-- server/loans.lua creates its columns after these tables exist
GovEnsureBusinessExtensions = EnsureBusinessExtensions

--- Lets another resource (pf-computer's City Hall app) post an announcement as the player `src`,
--- through the same checks and side effects as the government UI (table, audit, city event, mail sync).
exports('CreateAnnouncementAs', function(src, data)
    local handler = Government and Government.NuiCallbacks and Government.NuiCallbacks['announcement:create']
    if not handler or type(data) ~= 'table' then return { ok = false, error = 'unavailable' } end
    local result
    local payload = { source = src, title = data.title, content = data.content, priority = data.priority, category = data.category, duration = tonumber(data.duration) }
    local ok, err = pcall(handler, payload, function(r) result = r end)
    if not ok then return { ok = false, error = 'server_error', detail = tostring(err) } end
    return result or { ok = false, error = 'no_response' }
end)
