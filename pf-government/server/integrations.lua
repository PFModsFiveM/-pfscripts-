-- =====================================================
-- INTEGRATIONS WITH OTHER SCRIPTS
-- =====================================================

-- =====================================================
-- RESTAURANTS INTEGRATION
-- =====================================================

if Config.Integrations.Restaurants.enabled then
    -- Hook into restaurant revenue events. Server-only: pf-restaurants raises it with TriggerEvent
    -- (as a net event any client could add revenue to any business).
    AddEventHandler('pf-restaurants:server:addRevenue', function(restaurantId, amount, key)
        if type(restaurantId) ~= 'string' then return end
        -- registered as restaurant:<id>; the tax comes out of the restaurant's own bank account
        UpdateBusinessRevenue('restaurant:' .. restaurantId, amount, { key = key, account = 'society:restaurant_' .. restaurantId })
    end)

    -- Server-only as well (a client could register any business under any owner)
    AddEventHandler('pf-restaurants:server:registerBusiness', function(restaurantId, restaurantName, ownerCid, ownerName)
        if type(restaurantId) ~= 'string' then return end
        RegisterBusiness('restaurant:' .. restaurantId, tostring(restaurantName or restaurantId), 'restaurant', tostring(ownerCid or 'unowned'), ownerName, 'society:restaurant_' .. restaurantId)
    end)
    
    print('^2[PF-GOVERNMENT]^7 Restaurant integration enabled')
end

-- =====================================================
-- MDT LAWS SYNC INTEGRATION
-- =====================================================

if Config.Integrations.MDT.enabled then
    -- Provide export for MDT to get laws
    exports('GetLawsForMDT', function()
        return GetActiveLaws()
    end)

    -- Public-facing law feed used by browser portals and external services.
    exports('GetPublicLaws', function()
        return GetPortalLawFeed()
    end)

    exports('GetPublicTaxes', function()
        local taxes = {}
        for taxType, tax in pairs(GetTaxRates() or {}) do
            taxes[#taxes + 1] = {
                tax_type = taxType,
                rate = tonumber(tax.rate) or 0,
                min_rate = tonumber(tax.min_rate) or 0,
                max_rate = tonumber(tax.max_rate) or 100,
                enabled = tax.enabled == true,
                description = tax.description
            }
        end
        table.sort(taxes, function(a, b)
            return tostring(a.tax_type or '') < tostring(b.tax_type or '')
        end)
        return taxes
    end)

    exports('GetBusinessLicenses', function(businessId)
        if not businessId or businessId == '' then
            return {}
        end
        local rows = MySQL.query.await(
            'SELECT license_key, license_label, active, notes, issued_at FROM pf_gov_business_licenses WHERE business_id = ? ORDER BY issued_at DESC',
            { businessId }
        ) or {}
        return rows
    end)

    
    print('^2[PF-GOVERNMENT]^7 MDT integration enabled')
end

-- =====================================================
-- QBCORE PAYCHECK TAX INTEGRATION
-- =====================================================

if Config.Integrations.PaycheckTax.enabled then
    print('^2[PF-GOVERNMENT]^7 Paycheck tax integration enabled (handled via QBCore paycheck flow)')
end

-- =====================================================
-- HOUSING/PROPERTY INTEGRATION
-- =====================================================

if Config.Utilities.HousingIntegration.enabled then
    -- Export for housing scripts to register properties
    exports('RegisterProperty', function(propertyId, propertyName, ownerId, ownerName)
        return RegisterUtilityAccount('property', propertyId, propertyName, ownerId, ownerName)
    end)
    
    -- Export to check if property has power
    exports('PropertyHasPower', function(propertyId)
        return HasPower('property', propertyId)
    end)
    
    -- Export to check if property has water
    exports('PropertyHasWater', function(propertyId)
        return HasWater('property', propertyId)
    end)
    
    print('^2[PF-GOVERNMENT]^7 Housing integration enabled')
end

-- =====================================================
-- BUSINESS SCRIPTS INTEGRATION
-- =====================================================

-- Generic business registration export
exports('RegisterBusinessWithGovernment', function(businessId, businessName, businessType, ownerId, ownerName, accountRef)
    return RegisterBusiness(businessId, businessName, businessType, ownerId, ownerName, accountRef)
end)

-- Generic business revenue tracking export
exports('AddBusinessRevenue', function(businessId, amount, key, account)
    return UpdateBusinessRevenue(businessId, amount, { key = key, account = account })
end)

-- Closed by the government, or no power: the business may not sell
exports('CanBusinessTrade', function(businessId)
    return CanBusinessTrade(businessId)
end)

-- server-only: an inspection done by a business resource, into the government record
exports('RecordBusinessInspection', function(businessId, resultStatus, findings, inspectorCid, inspectorName)
    return RecordBusinessInspection(businessId, resultStatus, findings, inspectorCid, inspectorName)
end)

exports('IsBusinessOperational', function(businessId)
    return (CanBusinessTrade(businessId))
end)

-- Generic employee count update export
exports('UpdateBusinessEmployees', function(businessId, employeeCount)
    return UpdateBusinessEmployeeCount(businessId, employeeCount)
end)

-- Check business license status export
exports('CheckBusinessLicense', function(businessId)
    return GetBusinessLicenseStatus(businessId)
end)

-- Check business power export
exports('CheckBusinessPower', function(businessId)
    return HasPower('business', businessId)
end)

-- =====================================================
-- VEHICLE REGISTRATION INTEGRATION
-- =====================================================

-- Export for vehicle shops to charge registration fee
exports('ChargeVehicleRegistration', function(citizenid, vehicleData)
    local fee = GetTaxRate('vehicle_registration')
    
    if fee > 0 then
        -- Create bill for vehicle registration
        local dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + 604800) -- 7 days
        local description = 'Vehicle registration: ' .. (vehicleData.model or 'Unknown')
        
        CreateBill('citizen', citizenid, fee, 'license', dueDate, description, 'system', 'DMV')
        
        return true, fee
    end
    
    return true, 0
end)

-- =====================================================
-- ANNOUNCEMENT SYSTEM
-- =====================================================

-- Export: Get all active announcements (for external scripts like pf-computer)
exports('GetActiveAnnouncements', function()
    local result = MySQL.query.await('SELECT * FROM pf_gov_announcements WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY created_at DESC', {})
    return result or {}
end)

-- Export: Get single announcement by ID
exports('GetAnnouncement', function(announcementId)
    local result = MySQL.query.await('SELECT * FROM pf_gov_announcements WHERE id = ? AND active = 1', {announcementId})
    return result and #result > 0 and result[1] or nil
end)

RegisterNetEvent('pf-government:server:createAnnouncement', function(title, content, priority, category)
    local src = source
    
    if not IsGovernmentEmployee(src) then
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    -- Calculate expiration (7 days default)
    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + Config.Announcements.DefaultDuration)
    
    MySQL.insert('INSERT INTO pf_gov_announcements (title, content, priority, category, created_by, created_by_name, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {title, content, priority or 'normal', category or 'general', citizenid, name, expiresAt})
    
    -- Log audit
    LogAudit('announcement_create', citizenid, name, 'announcement', nil, {
        title = title,
        priority = priority
    })
    
    -- Notify all players if urgent
    if priority == 'urgent' or priority == 'high' then
        TriggerClientEvent('QBCore:Notify', -1, '📢 Government Announcement: ' .. title, 'primary', 5000)
    end
end)

-- =====================================================
-- UTILITIES EXPORTS FOR INTEGRATION
-- =====================================================

-- Allow other scripts to disconnect power
exports('DisconnectPower', function(propertyType, propertyId, reason)
    return DisconnectService(propertyType, propertyId, 'power', 'system', 'System', reason)
end)

-- Allow other scripts to restore power
exports('RestorePower', function(propertyType, propertyId)
    return RestoreService(propertyType, propertyId, 'power', 'system', 'System')
end)

-- =====================================================
-- COMPATIBILITY EVENTS
-- =====================================================

-- Allow other scripts to check permissions
RegisterNetEvent('pf-government:server:checkPermission', function(permission, callback)
    local src = source
    local hasPermission = HasPermission(src, permission)
    callback(hasPermission)
end)

-- Allow other scripts to get treasury balance
RegisterNetEvent('pf-government:server:getTreasury', function(callback)
    callback(GetTreasuryBalance())
end)

print('^2[PF-GOVERNMENT]^7 Integration hooks loaded')
