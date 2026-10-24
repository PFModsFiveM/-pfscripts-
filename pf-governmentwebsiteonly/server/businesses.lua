-- =====================================================
-- BUSINESSES OVERSIGHT SYSTEM
-- =====================================================

function InitializeBusinesses()
    print('^2[PF-GOVERNMENT]^7 Businesses system initialized')
end

function RegisterBusiness(businessId, businessName, businessType, ownerId, ownerName)
    -- Check if business already exists
    local existing = MySQL.query.await('SELECT * FROM pf_gov_businesses WHERE business_id = ?', {businessId})
    
    if existing and #existing > 0 then
        -- Update existing business
        MySQL.update('UPDATE pf_gov_businesses SET business_name = ?, business_type = ?, owner_id = ?, owner_name = ?, updated_at = NOW() WHERE business_id = ?',
            {businessName, businessType, ownerId, ownerName, businessId})
        return true, 'Business updated'
    end
    
    -- Register new business
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_businesses (business_id, business_name, business_type, owner_id, owner_name) VALUES (?, ?, ?, ?, ?)',
        {businessId, businessName, businessType, ownerId, ownerName})
    
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

function UpdateBusinessRevenue(businessId, amount)
    amount = tonumber(amount)
    
    if not amount or amount <= 0 then
        return false, 'Invalid amount'
    end
    
    -- Get current business data
    local business = MySQL.query.await('SELECT * FROM pf_gov_businesses WHERE business_id = ?', {businessId})
    
    if not business or #business == 0 then
        return false, 'Business not found'
    end
    
    business = business[1]
    local currentRevenue = tonumber(business.total_revenue) or 0
    local newRevenue = currentRevenue + amount
    
    -- Check for suspicious revenue spike
    if Config.Businesses.SpikeDetection.enabled then
        if amount >= Config.Businesses.SpikeDetection.threshold then
            -- Flag for review
            MySQL.update('UPDATE pf_gov_businesses SET compliance_status = ? WHERE business_id = ?',
                {'flagged', businessId})
            
            if Config.Businesses.SpikeDetection.notifyAdmins then
                NotifyGovernment('⚠️ Suspicious revenue spike detected: ' .. business.business_name .. ' +$' .. amount, 'warning')
            end
            
            LogAudit('business_revenue_spike', 'system', 'System', 'business', businessId, {
                business_id = businessId,
                business_name = business.business_name,
                amount = amount
            })
        end
    end
    
    -- Update revenue
    MySQL.update('UPDATE pf_gov_businesses SET total_revenue = ?, updated_at = NOW() WHERE business_id = ?',
        {newRevenue, businessId})
    
    -- Collect business tax if enabled
    if Config.Taxes.AutoCollection.enabled then
        local taxAmount = CollectTax(amount, 'business', 'business', businessId, 'system')
        
        if taxAmount > 0 then
            -- Update taxes paid
            local totalTaxes = tonumber(business.total_taxes_paid) or 0
            MySQL.update('UPDATE pf_gov_businesses SET total_taxes_paid = ? WHERE business_id = ?',
                {totalTaxes + taxAmount, businessId})

            -- Charge business society account when configured
            local businessTaxConfig = Config.Taxes.BusinessTax or {}
            if businessTaxConfig.UseSocietyAccount and GetResourceState('pfm-banking') == 'started' then
                local ok = exports['pfm-banking']:RemoveMoney(businessId, taxAmount, 'Business tax')
                if not ok and businessTaxConfig.BillOnInsufficientFunds then
                    local dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + ((businessTaxConfig.BillDueDays or 7) * 86400))
                    CreateBill('business', businessId, taxAmount, 'tax', dueDate, 'Business tax for revenue period', 'system', 'Government')
                end
            end
        end
    end
    
    DebugPrint('Business revenue updated: ' .. businessId .. ' +$' .. amount)
    return true, 'Revenue updated'
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
