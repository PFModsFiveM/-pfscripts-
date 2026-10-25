-- =====================================================
-- BUSINESSES OVERSIGHT SYSTEM
-- =====================================================

-- One row per reported sale (event_key): a revenue report and its business tax happen once per key.
local REVENUE_TABLE = [[
CREATE TABLE IF NOT EXISTS `pf_gov_business_revenue` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `event_key` VARCHAR(100) NOT NULL,
    `business_id` VARCHAR(100) NOT NULL,
    `amount` DECIMAL(15,2) NOT NULL,
    `tax` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `tax_state` VARCHAR(16) NOT NULL DEFAULT 'none',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_event` (`event_key`),
    KEY `idx_business` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

local function columnExists(tableName, column)
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { tableName, column })
    return (tonumber(n) or 0) > 0
end

function InitializeBusinesses()
    MySQL.query.await(REVENUE_TABLE)
    -- the closure columns were only added when staff first opened the businesses page, so on a fresh
    -- install every closure check failed with an unknown column
    if not columnExists('pf_gov_businesses', 'business_status') then
        MySQL.query.await("ALTER TABLE `pf_gov_businesses` ADD COLUMN `business_status` ENUM('active', 'closed') NOT NULL DEFAULT 'active' AFTER `compliance_status`")
    end
    if not columnExists('pf_gov_businesses', 'closed_at') then
        MySQL.query.await('ALTER TABLE `pf_gov_businesses` ADD COLUMN `closed_at` TIMESTAMP NULL DEFAULT NULL AFTER `business_status`')
    end
    if not columnExists('pf_gov_businesses', 'account_ref') then
        MySQL.query.await('ALTER TABLE `pf_gov_businesses` ADD COLUMN `account_ref` VARCHAR(96) NULL DEFAULT NULL')
    end
    print('^2[PF-GOVERNMENT]^7 Businesses system initialized')
end

local function validAccountRef(ref)
    if type(ref) ~= 'string' or #ref > 96 then return nil end
    if ref:match('^society:[%w_%-%.]+$') or ref:match('^acct:%d+$') then return ref end
    return nil
end

--- accountRef: the business's own ledger account; utility bills are paid from it automatically
function RegisterBusiness(businessId, businessName, businessType, ownerId, ownerName, accountRef)
    accountRef = validAccountRef(accountRef)
    local existing = MySQL.query.await('SELECT * FROM pf_gov_businesses WHERE business_id = ?', {businessId})
    if existing and #existing > 0 then
        MySQL.update.await('UPDATE pf_gov_businesses SET business_name = ?, business_type = ?, owner_id = ?, owner_name = ?, account_ref = COALESCE(?, account_ref), updated_at = NOW() WHERE business_id = ?',
            {businessName, businessType, ownerId, ownerName, accountRef, businessId})
        return true, 'Business updated'
    end

    local insertId = MySQL.insert.await('INSERT INTO pf_gov_businesses (business_id, business_name, business_type, owner_id, owner_name, account_ref) VALUES (?, ?, ?, ?, ?, ?)',
        {businessId, businessName, businessType, ownerId, ownerName, accountRef})

    if insertId then
        -- Create utility account for business
        RegisterUtilityAccount('business', businessId, businessName, ownerId, ownerName)
        
        -- Log audit
        LogAudit('business_register', ownerId, ownerName, 'business', businessId, {
            business_id = businessId,
            business_name = businessName,
            business_type = businessType
        })
        
        -- Notify government
        if Config.Notifications.NotifyGovernment.newBusiness then
            NotifyGovernment('New business registered: ' .. businessName, 'primary')
        end
        
        DebugPrint('Business registered: ' .. businessName .. ' (' .. businessId .. ')')
        return true, 'Business registered successfully', insertId
    end
    
    return false, 'Database error'
end

--- Records a sale for a registered business and takes its business tax.
--- opts.key: a unique key for this sale (a repeat with the same key does nothing);
--- opts.account: the business's ledger account (e.g. 'society:restaurant_burgershot') the tax is
--- taken from. Tax moves from that account to the treasury in one keyed ledger transfer, so the
--- treasury only ever receives money that left the business. (It used to credit the treasury first and
--- then try RemoveMoney on a society named after the business id, billing on failure: tax was created
--- out of nothing whenever the charge failed, and the society name did not match the real account.)
--- Without an account the sale is recorded and no tax is taken.
function UpdateBusinessRevenue(businessId, amount, opts)
    opts = type(opts) == 'table' and opts or {}
    amount = tonumber(amount)
    if type(businessId) ~= 'string' or businessId == '' or not amount or amount ~= amount or amount <= 0 or amount > 1e9 then
        return false, 'Invalid amount'
    end
    amount = math.floor(amount * 100 + 0.5) / 100

    local business = MySQL.single.await('SELECT * FROM pf_gov_businesses WHERE business_id = ?', { businessId })
    if not business then
        return false, 'Business not found'
    end

    local key = type(opts.key) == 'string' and opts.key ~= '' and opts.key:sub(1, 100) or ('gov:rev:' .. PFPayout.NewId())
    local recorded = MySQL.update.await('INSERT IGNORE INTO pf_gov_business_revenue (event_key, business_id, amount) VALUES (?, ?, ?)',
        { key, businessId, amount })
    if not recorded or recorded < 1 then
        return true, 'duplicate'
    end
    MySQL.update.await('UPDATE pf_gov_businesses SET total_revenue = total_revenue + ?, updated_at = NOW() WHERE business_id = ?',
        { amount, businessId })

    -- Check for suspicious revenue spike
    if Config.Businesses.SpikeDetection.enabled and amount >= Config.Businesses.SpikeDetection.threshold then
        MySQL.update('UPDATE pf_gov_businesses SET compliance_status = ? WHERE business_id = ?', { 'flagged', businessId })
        if Config.Businesses.SpikeDetection.notifyAdmins then
            NotifyGovernment('⚠️ Suspicious revenue spike detected: ' .. business.business_name .. ' +$' .. amount, 'warning')
        end
        LogAudit('business_revenue_spike', 'system', 'System', 'business', businessId, {
            business_id = businessId, business_name = business.business_name, amount = amount,
        })
    end

    local account = type(opts.account) == 'string' and opts.account or nil
    local treasury = Config.Treasury and Config.Treasury.UseSocietyAccount and Config.Treasury.SocietyAccount
    if Config.Taxes.AutoCollection.enabled and account and treasury and treasury ~= '' then
        local tax = math.floor((tonumber(CalculateTax(amount, 'business')) or 0) * 100 + 0.5) / 100
        if tax > 0 then
            local res = PFPayout.Transfer({
                from = account, to = 'society:' .. treasury, amount = tax,
                key = 'gov:biztax:' .. key, kind = 'tax', reason = 'Business tax: ' .. businessId,
            })
            if res.ok then
                MySQL.update.await("UPDATE pf_gov_business_revenue SET tax = ?, tax_state = 'paid' WHERE event_key = ?", { tax, key })
                MySQL.update.await('UPDATE pf_gov_businesses SET total_taxes_paid = total_taxes_paid + ? WHERE business_id = ?', { tax, businessId })
            else
                local billed = false
                local businessTaxConfig = Config.Taxes.BusinessTax or {}
                if res.error == 'insufficient_funds' and businessTaxConfig.BillOnInsufficientFunds then
                    local dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + ((businessTaxConfig.BillDueDays or 7) * 86400))
                    billed = CreateBill('business', businessId, tax, 'tax', dueDate, 'Business tax for revenue period', 'system', 'Government') and true or false
                end
                MySQL.update.await('UPDATE pf_gov_business_revenue SET tax = ?, tax_state = ? WHERE event_key = ?',
                    { tax, billed and 'billed' or 'unpaid', key })
            end
        end
    end

    DebugPrint('Business revenue updated: ' .. businessId .. ' +$' .. amount)
    return true, 'Revenue updated'
end

--- Whether a business may trade: not closed by the government and with power. A business the
--- government does not know is not restricted.
function CanBusinessTrade(businessId)
    if type(businessId) ~= 'string' or businessId == '' then return true end
    local row = MySQL.single.await('SELECT COALESCE(business_status, "active") AS business_status FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })
    if row and tostring(row.business_status) == 'closed' then return false, 'closed' end
    if not HasPower('business', businessId) then return false, 'no_power' end
    return true
end

function UpdateBusinessEmployeeCount(businessId, employeeCount)
    employeeCount = tonumber(employeeCount) or 0
    
    MySQL.update('UPDATE pf_gov_businesses SET employee_count = ?, updated_at = NOW() WHERE business_id = ?',
        {employeeCount, businessId})
    
    return true, 'Employee count updated'
end

function SetBusinessCompliance(businessId, complianceStatus, updatedBy, updatedByName, notes)
    local validStatuses = {compliant = true, warning = true, non_compliant = true, flagged = true}
    
    if not validStatuses[complianceStatus] then
        return false, 'Invalid compliance status'
    end
    
    MySQL.update('UPDATE pf_gov_businesses SET compliance_status = ?, notes = ?, updated_at = NOW() WHERE business_id = ?',
        {complianceStatus, notes, businessId})
    
    -- Log audit
    LogAudit('business_compliance', updatedBy, updatedByName, 'business', businessId, {
        business_id = businessId,
        compliance_status = complianceStatus,
        notes = notes
    })
    
    DebugPrint('Business compliance updated: ' .. businessId .. ' -> ' .. complianceStatus)
    return true, 'Compliance status updated'
end

function GetBusinessStats()
    local stats = MySQL.query.await([[
        SELECT 
            COUNT(*) as total_businesses,
            SUM(total_revenue) as total_revenue,
            SUM(total_taxes_paid) as total_taxes,
            SUM(employee_count) as total_employees,
            SUM(CASE WHEN compliance_status = 'non_compliant' THEN 1 ELSE 0 END) as non_compliant_count,
            SUM(CASE WHEN compliance_status = 'flagged' THEN 1 ELSE 0 END) as flagged_count
        FROM pf_gov_businesses
    ]], {})
    
    if stats and #stats > 0 then
        return stats[1]
    end
    
    return {
        total_businesses = 0,
        total_revenue = 0,
        total_taxes = 0,
        total_employees = 0,
        non_compliant_count = 0,
        flagged_count = 0
    }
end

-- =====================================================
-- NUI CALLBACKS - BUSINESSES
-- =====================================================

RegisterNUICallback('business:getAll', function(data, cb)
    MySQL.query('SELECT * FROM pf_gov_businesses ORDER BY business_name', {}, function(result)
        cb({
            ok = true,
            businesses = result or {}
        })
    end)
end)

RegisterNUICallback('business:get', function(data, cb)
    local businessId = data.businessId
    
    MySQL.query('SELECT * FROM pf_gov_businesses WHERE business_id = ?', {businessId}, function(result)
        if result and #result > 0 then
            cb({ ok = true, business = result[1] })
        else
            cb({ ok = false, error = 'business_not_found' })
        end
    end)
end)

RegisterNUICallback('business:getStats', function(data, cb)
    local stats = GetBusinessStats()
    
    cb({
        ok = true,
        stats = stats
    })
end)

RegisterNUICallback('business:setCompliance', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = SetBusinessCompliance(
        data.businessId,
        data.complianceStatus,
        citizenid,
        name,
        data.notes
    )
    
    if success then
        NotifyPlayer(src, 'Compliance status updated', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('business:register', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'businesses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local success, message = RegisterBusiness(
        data.businessId,
        data.businessName,
        data.businessType,
        data.ownerId,
        data.ownerName
    )
    
    if success then
        NotifyPlayer(src, 'Business registered', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

print('^2[PF-GOVERNMENT]^7 Businesses system loaded')
