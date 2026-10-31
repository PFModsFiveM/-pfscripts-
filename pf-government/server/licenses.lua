-- =====================================================
-- LICENSES AND PERMITS SYSTEM
-- =====================================================

function InitializeLicenses()
    print('^2[PF-GOVERNMENT]^7 Licenses system initialized')
end

function HasLicense(citizenid, licenseType)
    local result = MySQL.query.await('SELECT * FROM pf_gov_licenses WHERE owner_id = ? AND license_type = ? AND owner_type = ? AND status = ?',
        {citizenid, licenseType, 'citizen', 'active'})
    
    if result and #result > 0 then
        local license = result[1]
        
        -- Check expiration
        if license.expires_at then
            local expiryTime = os.time(license.expires_at)
            if os.time() > expiryTime then
                -- License expired
                SetLicenseStatus(license.id, 'expired')
                return false
            end
        end
        
        return true
    end
    
    return false
end

function GetBusinessLicenseStatus(businessId)
    local result = MySQL.query.await('SELECT * FROM pf_gov_licenses WHERE owner_id = ? AND owner_type = ?',
        {businessId, 'business'})
    
    if result and #result > 0 then
        return result[1].status
    end
    
    return 'none'
end

function IssueLicense(licenseType, ownerType, ownerId, ownerName, issuedBy, issuedByName, duration, notes)
    -- Check if license already exists
    local existing = MySQL.query.await('SELECT * FROM pf_gov_licenses WHERE license_type = ? AND owner_id = ? AND owner_type = ? AND status = ?',
        {licenseType, ownerId, ownerType, 'active'})
    
    if existing and #existing > 0 then
        return false, 'License already exists and is active'
    end
    
    -- Calculate expiration date
    local expiresAt = nil
    if duration and duration > 0 then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + duration)
    end
    
    -- Insert license
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_licenses (license_type, owner_type, owner_id, owner_name, status, issued_by, issued_by_name, expires_at, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {licenseType, ownerType, ownerId, ownerName, 'active', issuedBy, issuedByName, expiresAt, notes})
    
    if insertId then
        -- Get license fee from config
        local fee = GetLicenseFee(licenseType, ownerType)
        
        -- Create bill for license fee
        if fee > 0 then
            CreateBill(ownerType, ownerId, fee, 'license', os.date('%Y-%m-%d %H:%M:%S', os.time() + 604800), 
                'License fee: ' .. licenseType, issuedBy, issuedByName)
        end
        
        -- Log audit
        LogAudit('license_issue', issuedBy, issuedByName, 'license', insertId, {
            license_id = insertId,
            license_type = licenseType,
            owner_type = ownerType,
            owner_id = ownerId,
            owner_name = ownerName
        })
        
        DebugPrint('License issued: ' .. licenseType .. ' to ' .. ownerType .. ' ' .. ownerId)
        return true, 'License issued successfully', insertId
    end
    
    return false, 'Database error'
end

function RenewLicense(licenseId, renewedBy, renewedByName, duration)
    licenseId = tonumber(licenseId)
    
    local license = MySQL.query.await('SELECT * FROM pf_gov_licenses WHERE id = ?', {licenseId})
    
    if not license or #license == 0 then
        return false, 'License not found'
    end
    
    license = license[1]
    
    -- Calculate new expiration
    local currentExpiry = license.expires_at and os.time(license.expires_at) or os.time()
    local newExpiry = currentExpiry + (duration or 2592000) -- Default 30 days
    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', newExpiry)
    
    -- Update license
    MySQL.update('UPDATE pf_gov_licenses SET status = ?, expires_at = ? WHERE id = ?',
        {'active', expiresAt, licenseId})
    
    -- Get license fee
    local fee = GetLicenseFee(license.license_type, license.owner_type)
    
    -- Create renewal bill
    if fee > 0 then
        CreateBill(license.owner_type, license.owner_id, fee, 'license', 
            os.date('%Y-%m-%d %H:%M:%S', os.time() + 604800),
            'License renewal: ' .. license.license_type, renewedBy, renewedByName)
    end
    
    -- Log audit
    LogAudit('license_renew', renewedBy, renewedByName, 'license', licenseId, {
        license_id = licenseId,
        license_type = license.license_type,
        new_expiry = expiresAt
    })
    
    DebugPrint('License renewed: ID ' .. licenseId)
    return true, 'License renewed successfully'
end

function SetLicenseStatus(licenseId, status, performedBy, performedByName, notes)
    licenseId = tonumber(licenseId)
    
    local validStatuses = {active = true, suspended = true, revoked = true, expired = true}
    if not validStatuses[status] then
        return false, 'Invalid status'
    end

    -- a revocation is public (a news lead); read the license first so a repeat is not news again
    local before = nil
    if status == 'revoked' and GovEventsOn() then
        before = GovSafe(function()
            return MySQL.single.await('SELECT id, license_type, owner_type, owner_id, owner_name, status FROM pf_gov_licenses WHERE id = ? LIMIT 1', { licenseId })
        end)
    end

    local affected = MySQL.update.await('UPDATE pf_gov_licenses SET status = ?, notes = ? WHERE id = ?',
        {status, notes, licenseId})

    if type(before) == 'table' and before.id and before.status ~= 'revoked' and (tonumber(affected) or 0) > 0 then
        GovEmit('gov.license.revoked', function()
            local label = before.license_type
            for _, list in ipairs({ Config.Licenses.BusinessTypes or {}, Config.Licenses.CitizenTypes or {} }) do
                for _, lic in ipairs(list) do if lic.type == before.license_type then label = lic.label end end
            end
            local facts = before.owner_type == 'business' and GovBusinessFacts(before.owner_id) or {}
            return {
                licenseType = before.license_type, label = label, holderType = before.owner_type,
                holder = before.owner_name or facts.business, business = facts.business, reason = GovExcerpt(notes, 160),
            }, { title = ('%s revoked'):format(tostring(label)), district = facts.district, actor = performedBy ~= 'system' and performedBy or nil }
        end)
    end
    
    -- Log audit
    local actionType = 'license_' .. status
    LogAudit(actionType, performedBy, performedByName, 'license', licenseId, {
        license_id = licenseId,
        new_status = status,
        notes = notes
    })
    
    DebugPrint('License status changed: ID ' .. licenseId .. ' -> ' .. status)
    return true, 'License status updated'
end

function SuspendLicense(licenseId, suspendedBy, suspendedByName, reason)
    return SetLicenseStatus(licenseId, 'suspended', suspendedBy, suspendedByName, reason)
end

function RevokeLicense(licenseId, revokedBy, revokedByName, reason)
    return SetLicenseStatus(licenseId, 'revoked', revokedBy, revokedByName, reason)
end

function GetLicenseFee(licenseType, ownerType)
    local licenseList = ownerType == 'business' and Config.Licenses.BusinessTypes or Config.Licenses.CitizenTypes
    
    for _, lic in ipairs(licenseList) do
        if lic.type == licenseType then
            return lic.fee or 0
        end
    end
    
    return 0
end

function GetLicenseDuration(licenseType, ownerType)
    local licenseList = ownerType == 'business' and Config.Licenses.BusinessTypes or Config.Licenses.CitizenTypes
    
    for _, lic in ipairs(licenseList) do
        if lic.type == licenseType then
            return lic.duration or 0
        end
    end
    
    return 0
end

function CheckLicenseExpiration()
    MySQL.query('SELECT * FROM pf_gov_licenses WHERE status = ? AND expires_at IS NOT NULL AND expires_at < NOW()',
        {'active'}, function(result)
            if result and #result > 0 then
                for _, license in ipairs(result) do
                    SetLicenseStatus(license.id, 'expired', 'system', 'System', 'License expired')
                end
                DebugPrint('Expired ' .. #result .. ' licenses')
            end
        end)
end

-- =====================================================
-- NUI CALLBACKS - LICENSES
-- =====================================================

RegisterNUICallback('license:getAll', function(data, cb)
    local src = data.source or source
    local ownerType = data.ownerType
    local ownerId = data.ownerId
    -- everyone's licenses are for government staff; anyone else sees only their own
    if not IsGovernmentEmployee(src) then
        local citizenid = GetPlayerIdentifier(src)
        if not citizenid then
            cb({ ok = false, error = 'no_player' })
            return
        end
        ownerType, ownerId = 'citizen', citizenid
    end
    
    local query = 'SELECT * FROM pf_gov_licenses WHERE 1=1'
    local params = {}
    
    if ownerType then
        query = query .. ' AND owner_type = ?'
        table.insert(params, ownerType)
    end
    
    if ownerId then
        query = query .. ' AND owner_id = ?'
        table.insert(params, ownerId)
    end
    
    query = query .. ' ORDER BY issued_at DESC'
    
    MySQL.query(query, params, function(result)
        cb({
            ok = true,
            licenses = result or {}
        })
    end)
end)

RegisterNUICallback('license:issue', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'licenses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local duration = GetLicenseDuration(data.licenseType, data.ownerType)
    
    local success, message, licenseId = IssueLicense(
        data.licenseType,
        data.ownerType,
        data.ownerId,
        data.ownerName,
        citizenid,
        name,
        duration,
        data.notes
    )
    
    if success then
        NotifyPlayer(src, 'License issued: ' .. data.licenseType, 'success')
    end
    
    cb({
        ok = success,
        message = message,
        licenseId = licenseId
    })
end)

RegisterNUICallback('license:renew', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'licenses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = RenewLicense(data.licenseId, citizenid, name, data.duration)
    
    if success then
        NotifyPlayer(src, 'License renewed', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('license:suspend', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'licenses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = SuspendLicense(data.licenseId, citizenid, name, data.reason)
    
    if success then
        NotifyPlayer(src, 'License suspended', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('license:revoke', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'licenses') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = RevokeLicense(data.licenseId, citizenid, name, data.reason)
    
    if success then
        NotifyPlayer(src, 'License revoked', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('license:getTypes', function(data, cb)
    cb({
        ok = true,
        citizenTypes = Config.Licenses.CitizenTypes,
        businessTypes = Config.Licenses.BusinessTypes
    })
end)

print('^2[PF-GOVERNMENT]^7 Licenses system loaded')
