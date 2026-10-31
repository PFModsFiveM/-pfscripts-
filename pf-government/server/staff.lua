-- =====================================================
-- GOVERNMENT STAFF MANAGEMENT
-- =====================================================

function InitializeStaff()
    print('^2[PF-GOVERNMENT]^7 Staff management system initialized')
end

function AddStaffMember(citizenid, name, role, appointedBy, appointedByName)
    -- Check if already exists
    local existing = MySQL.query.await('SELECT * FROM pf_gov_staff WHERE citizenid = ?', {citizenid})
    
    if existing and #existing > 0 then
        return false, 'Staff member already exists'
    end
    
    -- Get permissions for role
    local permissions = {}
    for grade, roleConfig in pairs(Config.Roles) do
        if roleConfig.name == role then
            permissions = roleConfig.permissions
            break
        end
    end
    
    local permissionsJson = json.encode(permissions)
    
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_staff (citizenid, name, role, permissions, appointed_by) VALUES (?, ?, ?, ?, ?)',
        {citizenid, name, role, permissionsJson, appointedBy})
    
    if insertId then
        -- Log audit
        LogAudit('staff_add', appointedBy, appointedByName, 'staff', citizenid, {
            citizenid = citizenid,
            name = name,
            role = role
        })

        GovEmit('gov.staff.appointed', { name = name, role = role, appointedBy = appointedByName, department = 'City Hall' },
            { title = ('%s appointed %s'):format(tostring(name), tostring(role)), actor = appointedBy })
        
        DebugPrint('Staff member added: ' .. name .. ' (' .. role .. ')')
        return true, 'Staff member added successfully', insertId
    end
    
    return false, 'Database error'
end

function RemoveStaffMember(citizenid, removedBy, removedByName)
    MySQL.update('UPDATE pf_gov_staff SET active = 0 WHERE citizenid = ?', {citizenid})
    
    -- Log audit
    LogAudit('staff_remove', removedBy, removedByName, 'staff', citizenid, {
        citizenid = citizenid
    })
    
    DebugPrint('Staff member removed: ' .. citizenid)
    return true, 'Staff member removed'
end

function UpdateStaffRole(citizenid, newRole, updatedBy, updatedByName)
    -- Get permissions for new role
    local permissions = {}
    for grade, roleConfig in pairs(Config.Roles) do
        if roleConfig.name == newRole then
            permissions = roleConfig.permissions
            break
        end
    end
    
    local permissionsJson = json.encode(permissions)

    local before = GovEventsOn() and GovSafe(function()
        return MySQL.single.await('SELECT name, role FROM pf_gov_staff WHERE citizenid = ? LIMIT 1', { citizenid })
    end) or nil

    local affected = MySQL.update.await('UPDATE pf_gov_staff SET role = ?, permissions = ? WHERE citizenid = ?',
        {newRole, permissionsJson, citizenid})

    if type(before) == 'table' and before.role and before.role ~= newRole and (tonumber(affected) or 0) > 0 then
        GovEmit('gov.staff.appointed', { name = before.name, role = newRole, previousRole = before.role, appointedBy = updatedByName, department = 'City Hall' },
            { title = ('%s appointed %s'):format(tostring(before.name), tostring(newRole)), actor = updatedBy })
    end
    
    -- Log audit
    LogAudit('staff_role_update', updatedBy, updatedByName, 'staff', citizenid, {
        citizenid = citizenid,
        new_role = newRole
    })
    
    DebugPrint('Staff role updated: ' .. citizenid .. ' -> ' .. newRole)
    return true, 'Staff role updated'
end

function GetActiveStaff()
    local result = MySQL.query.await('SELECT * FROM pf_gov_staff WHERE active = 1 ORDER BY appointed_at DESC', {})
    return result or {}
end

-- =====================================================
-- NUI CALLBACKS - STAFF
-- =====================================================

RegisterNUICallback('staff:getAll', function(data, cb)
    MySQL.query('SELECT * FROM pf_gov_staff WHERE active = 1 ORDER BY appointed_at DESC', {}, function(result)
        cb({
            ok = true,
            staff = result or {}
        })
    end)
end)

RegisterNUICallback('staff:add', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'staff') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local appointedByCitizenid = GetPlayerIdentifier(src)
    local appointedByName = GetPlayerName(src)
    
    local success, message, staffId = AddStaffMember(
        data.citizenid,
        data.name,
        data.role,
        appointedByCitizenid,
        appointedByName
    )
    
    if success then
        NotifyPlayer(src, 'Staff member added: ' .. data.name, 'success')
    end
    
    cb({
        ok = success,
        message = message,
        staffId = staffId
    })
end)

RegisterNUICallback('staff:remove', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'staff') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = RemoveStaffMember(data.citizenid, citizenid, name)
    
    if success then
        NotifyPlayer(src, 'Staff member removed', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('staff:updateRole', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'staff') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = UpdateStaffRole(data.citizenid, data.role, citizenid, name)
    
    if success then
        NotifyPlayer(src, 'Staff role updated', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('staff:getRoles', function(data, cb)
    local roles = {}
    for grade, roleConfig in pairs(Config.Roles) do
        table.insert(roles, {
            name = roleConfig.name,
            grade = grade,
            permissions = roleConfig.permissions
        })
    end
    
    cb({
        ok = true,
        roles = roles
    })
end)

print('^2[PF-GOVERNMENT]^7 Staff management system loaded')
