-- Business management functions

-- Get business details
RegisterNetEvent('pf-restaurants:server:getBusiness', function(businessId)
    local src = source
    local business = RestaurantData.businesses[businessId]
    
    if not business then
        NotifyPlayer(src, 'Business not found', 'error')
        return
    end
    
    TriggerClientEvent('pf-restaurants:client:receiveBusiness', src, business)
end)

-- Get all businesses
QBCore.Functions.CreateCallback('pf-restaurants:server:getBusinesses', function(source, cb)
    cb(RestaurantData.businesses)
end)

-- Check if player is employee
QBCore.Functions.CreateCallback('pf-restaurants:server:isEmployee', function(source, cb, businessId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end
    
    local cid = Player.PlayerData.citizenid
    
    local role = RoleOf(source, businessId)
    if role then
        local stored = RestaurantData.employees[businessId] and RestaurantData.employees[businessId][cid]
        cb(true, stored or { cid = cid, role = role })
    else
        cb(false, nil)
    end
end)

-- Add employee
RegisterNetEvent('pf-restaurants:server:addEmployee', function(businessId, targetCid, role)
    local src = source
    
    if not HasPermission(src, businessId, 'employee.manage') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    -- only real roles, and only the owner hands out the owner role
    if type(targetCid) ~= 'string' or #targetCid > 64 or not Config.Permissions.Roles[role] then
        NotifyPlayer(src, 'Invalid employee or role', 'error')
        return
    end
    if role == 'owner' and RoleOf(src, businessId) ~= 'owner' then
        NotifyPlayer(src, 'Only the owner can add an owner', 'error')
        return
    end
    if not RestaurantData.employees[businessId] then
        RestaurantData.employees[businessId] = {}
    end
    RestaurantDB.SaveEmployee(businessId, targetCid, role)

    RestaurantData.employees[businessId][targetCid] = {
        cid = targetCid,
        role = role,
        hiredDate = os.time(),
        shifts = 0,
        orders = 0,
        performance = 100
    }
    
    LogAction('employee_change', {
        businessId = businessId,
        action = 'hired',
        targetCid = targetCid,
        role = role,
        by = GetPlayerIdentifier(src, 0)
    })
    
    NotifyPlayer(src, 'Employee added successfully', 'success')
end)

-- Remove employee
RegisterNetEvent('pf-restaurants:server:removeEmployee', function(businessId, targetCid)
    local src = source
    
    if not HasPermission(src, businessId, 'employee.manage') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    if RestaurantData.employees[businessId] and RestaurantData.employees[businessId][targetCid] then
        RestaurantData.employees[businessId][targetCid] = nil
        RestaurantDB.DeleteEmployee(businessId, targetCid)
        
        LogAction('employee_change', {
            businessId = businessId,
            action = 'fired',
            targetCid = targetCid,
            by = GetPlayerIdentifier(src, 0)
        })
        
        NotifyPlayer(src, 'Employee removed successfully', 'success')
    else
        NotifyPlayer(src, 'Employee not found', 'error')
    end
end)

-- Update employee role
RegisterNetEvent('pf-restaurants:server:updateEmployeeRole', function(businessId, targetCid, newRole)
    local src = source
    
    if not HasPermission(src, businessId, 'employee.manage') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    if not Config.Permissions.Roles[newRole] or (newRole == 'owner' and RoleOf(src, businessId) ~= 'owner') then
        NotifyPlayer(src, 'Invalid role', 'error')
        return
    end
    if RestaurantData.employees[businessId] and RestaurantData.employees[businessId][targetCid] then
        local oldRole = RestaurantData.employees[businessId][targetCid].role
        RestaurantData.employees[businessId][targetCid].role = newRole
        RestaurantDB.SaveEmployee(businessId, targetCid, newRole)
        
        LogAction('employee_change', {
            businessId = businessId,
            action = 'role_change',
            targetCid = targetCid,
            oldRole = oldRole,
            newRole = newRole,
            by = GetPlayerIdentifier(src, 0)
        })
        
        NotifyPlayer(src, 'Employee role updated', 'success')
    else
        NotifyPlayer(src, 'Employee not found', 'error')
    end
end)

-- Clock in/out (for shift tracking)
RegisterNetEvent('pf-restaurants:server:clockIn', function(businessId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local cid = Player.PlayerData.citizenid
    
    if not RestaurantData.employees[businessId] or not RestaurantData.employees[businessId][cid] then
        NotifyPlayer(src, 'You are not an employee here', 'error')
        return
    end
    
    RestaurantData.employees[businessId][cid].clockedIn = os.time()
    NotifyPlayer(src, 'Clocked in successfully', 'success')
end)

RegisterNetEvent('pf-restaurants:server:clockOut', function(businessId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local cid = Player.PlayerData.citizenid
    
    if not RestaurantData.employees[businessId] or not RestaurantData.employees[businessId][cid] then
        NotifyPlayer(src, 'You are not an employee here', 'error')
        return
    end
    
    local clockedIn = RestaurantData.employees[businessId][cid].clockedIn
    if clockedIn then
        local duration = os.time() - clockedIn
        RestaurantData.employees[businessId][cid].shifts = (RestaurantData.employees[businessId][cid].shifts or 0) + 1
        RestaurantData.employees[businessId][cid].clockedIn = nil
        
        NotifyPlayer(src, 'Clocked out. Shift duration: ' .. math.floor(duration / 60) .. ' minutes', 'success')
    else
        NotifyPlayer(src, 'You are not clocked in', 'error')
    end
end)

-- Get employees list
QBCore.Functions.CreateCallback('pf-restaurants:server:getEmployees', function(source, cb, businessId)
    if not HasPermission(source, businessId, 'employee.view') then
        cb(nil)
        return
    end
    
    cb(RestaurantData.employees[businessId] or {})
end)
