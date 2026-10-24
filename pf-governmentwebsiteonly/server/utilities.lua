-- =====================================================
-- UTILITIES AND SERVICES SYSTEM
-- =====================================================

function InitializeUtilities()
    print('^2[PF-GOVERNMENT]^7 Utilities system initialized')
end

function HasPower(propertyType, propertyId)
    local result = MySQL.query.await('SELECT power_status FROM pf_gov_utilities WHERE property_type = ? AND property_id = ?',
        {propertyType, propertyId})
    
    if result and #result > 0 then
        return result[1].power_status == 'active'
    end
    
    -- No utility record = assume active (for backwards compatibility)
    return true
end

function HasWater(propertyType, propertyId)
    local result = MySQL.query.await('SELECT water_status FROM pf_gov_utilities WHERE property_type = ? AND property_id = ?',
        {propertyType, propertyId})
    
    if result and #result > 0 then
        return result[1].water_status == 'active'
    end
    
    -- No utility record = assume active
    return true
end

function RegisterUtilityAccount(propertyType, propertyId, propertyName, ownerId, ownerName)
    -- Check if already exists
    local existing = MySQL.query.await('SELECT * FROM pf_gov_utilities WHERE property_type = ? AND property_id = ?',
        {propertyType, propertyId})
    
    if existing and #existing > 0 then
        -- Update owner info
        MySQL.update('UPDATE pf_gov_utilities SET owner_id = ?, owner_name = ?, property_name = ? WHERE property_type = ? AND property_id = ?',
            {ownerId, ownerName, propertyName, propertyType, propertyId})
        return true, 'Utility account updated'
    end
    
    -- Create new utility account
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_utilities (property_type, property_id, property_name, owner_id, owner_name) VALUES (?, ?, ?, ?, ?)',
        {propertyType, propertyId, propertyName, ownerId, ownerName})
    
    if insertId then
        DebugPrint('Utility account created: ' .. propertyType .. ' ' .. propertyId)
        return true, 'Utility account created', insertId
    end
    
    return false, 'Database error'
end

function DisconnectService(propertyType, propertyId, serviceType, disconnectedBy, disconnectedByName, reason)
    local statusField = serviceType == 'power' and 'power_status' or 'water_status'
    
    MySQL.update('UPDATE pf_gov_utilities SET ' .. statusField .. ' = ?, disconnected_by = ?, disconnected_at = NOW() WHERE property_type = ? AND property_id = ?',
        {'disconnected', disconnectedBy, propertyType, propertyId})
    
    -- Log audit
    LogAudit('utility_disconnect', disconnectedBy, disconnectedByName, 'utility', propertyType .. '_' .. propertyId, {
        property_type = propertyType,
        property_id = propertyId,
        service_type = serviceType,
        reason = reason
    })
    
    DebugPrint('Service disconnected: ' .. serviceType .. ' for ' .. propertyType .. ' ' .. propertyId)
    return true, 'Service disconnected'
end

function RestoreService(propertyType, propertyId, serviceType, restoredBy, restoredByName)
    local statusField = serviceType == 'power' and 'power_status' or 'water_status'
    
    MySQL.update('UPDATE pf_gov_utilities SET ' .. statusField .. ' = ?, disconnected_by = NULL, disconnected_at = NULL WHERE property_type = ? AND property_id = ?',
        {'active', propertyType, propertyId})
    
    -- Log audit
    LogAudit('utility_restore', restoredBy, restoredByName, 'utility', propertyType .. '_' .. propertyId, {
        property_type = propertyType,
        property_id = propertyId,
        service_type = serviceType
    })
    
    DebugPrint('Service restored: ' .. serviceType .. ' for ' .. propertyType .. ' ' .. propertyId)
    return true, 'Service restored'
end

function ProcessUtilityBilling()
    if not Config.Utilities.EnablePower and not Config.Utilities.EnableWater then
        return
    end
    
    MySQL.query('SELECT * FROM pf_gov_utilities WHERE power_status = ? OR water_status = ?',
        {'active', 'active'}, function(result)
            if result and #result > 0 then
                local totalBilled = 0
                
                for _, utility in ipairs(result) do
                    local billAmount = 0
                    local description = 'Utility bill: '
                    
                    if utility.power_status == 'active' and Config.Utilities.EnablePower then
                        billAmount = billAmount + Config.Utilities.PowerBillAmount
                        description = description .. 'Power '
                    end
                    
                    if utility.water_status == 'active' and Config.Utilities.EnableWater then
                        billAmount = billAmount + Config.Utilities.WaterBillAmount
                        if Config.Utilities.EnablePower and utility.power_status == 'active' then
                            description = description .. '+ Water'
                        else
                            description = description .. 'Water'
                        end
                    end
                    
                    if billAmount > 0 then
                        -- Create bill
                        local dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + 604800) -- 7 days
                        CreateBill(utility.property_type, utility.property_id, billAmount, 'utility', 
                            dueDate, description, 'system', 'Utilities Department')
                        
                        -- Update last bill date
                        MySQL.update('UPDATE pf_gov_utilities SET last_bill_date = NOW() WHERE id = ?', {utility.id})
                        
                        totalBilled = totalBilled + billAmount
                    end
                end
                
                DebugPrint('Utility billing complete: ' .. #result .. ' accounts, $' .. totalBilled .. ' billed')
            end
        end)
end

function GetUtilityOverview()
    local rows = MySQL.query.await('SELECT power_status, water_status FROM pf_gov_utilities', {}) or {}

    local power = { active = 0, delinquent = 0, disconnected = 0 }
    local water = { active = 0, delinquent = 0, disconnected = 0 }

    for _, row in ipairs(rows) do
        local p = tostring(row.power_status or 'active')
        local w = tostring(row.water_status or 'active')

        power[p] = (power[p] or 0) + 1
        water[w] = (water[w] or 0) + 1
    end

    return {
        power = power,
        water = water,
        totalAccounts = #rows
    }
end

function GetUtilityDelinquentAccounts()
    local rows = MySQL.query.await([[ 
        SELECT
            u.property_type,
            u.property_id,
            u.property_name,
            u.owner_id,
            u.owner_name,
            u.power_status,
            u.water_status,
            COALESCE(SUM(CASE WHEN b.bill_type = 'utility' AND b.status IN ('unpaid', 'partial', 'delinquent') THEN (b.amount - b.amount_paid) ELSE 0 END), 0) as amount_owed,
            COALESCE(MAX(TIMESTAMPDIFF(DAY, b.due_date, NOW())), 0) as days_overdue
        FROM pf_gov_utilities u
        LEFT JOIN pf_gov_bills b ON b.target_type = u.property_type AND b.target_id = u.property_id
        GROUP BY u.property_type, u.property_id, u.property_name, u.owner_id, u.owner_name, u.power_status, u.water_status
        HAVING amount_owed > 0 OR u.power_status = 'delinquent' OR u.water_status = 'delinquent'
        ORDER BY amount_owed DESC, days_overdue DESC
    ]], {}) or {}

    return rows
end

-- =====================================================
-- NUI CALLBACKS - UTILITIES
-- =====================================================

RegisterNUICallback('utility:getAll', function(data, cb)
    MySQL.query('SELECT * FROM pf_gov_utilities ORDER BY property_type, property_id', {}, function(result)
        cb({
            ok = true,
            utilities = result or {}
        })
    end)
end)

RegisterNUICallback('utility:disconnect', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'utilities') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = DisconnectService(
        data.propertyType,
        data.propertyId,
        data.serviceType,
        citizenid,
        name,
        data.reason
    )
    
    if success then
        NotifyPlayer(src, 'Service disconnected', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('utility:restore', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'utilities') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = RestoreService(
        data.propertyType,
        data.propertyId,
        data.serviceType,
        citizenid,
        name
    )
    
    if success then
        NotifyPlayer(src, 'Service restored', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

print('^2[PF-GOVERNMENT]^7 Utilities system loaded')

exports('GetUtilityOverview', function()
    return GetUtilityOverview()
end)

exports('GetUtilityDelinquentAccounts', function()
    return GetUtilityDelinquentAccounts()
end)

exports('DisconnectService', function(propertyType, propertyId, serviceType, disconnectedBy, disconnectedByName, reason)
    return DisconnectService(propertyType, propertyId, serviceType, disconnectedBy, disconnectedByName, reason)
end)

exports('RestoreService', function(propertyType, propertyId, serviceType, restoredBy, restoredByName)
    return RestoreService(propertyType, propertyId, serviceType, restoredBy, restoredByName)
end)
