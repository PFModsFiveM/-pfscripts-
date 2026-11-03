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

-- Management actions work off shift (Config.Permissions.OffDuty); their role checks use this
local OFF_SHIFT = { offDuty = true }

-- Is the player working here now? true + { role, onShift } on shift; false + { role, offShift }
-- for staff who must clock in first; false for everyone else.
QBCore.Functions.CreateCallback('pf-restaurants:server:isEmployee', function(source, cb, businessId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player or type(businessId) ~= 'string' then cb(false) return end
    local role = RoleOf(source, businessId)
    if role then
        cb(true, { cid = Player.PlayerData.citizenid, role = role, onShift = true })
        return
    end
    local offRole = RoleOf(source, businessId, OFF_SHIFT)
    cb(false, offRole and { role = offRole, offShift = true } or nil)
end)

-- Only the owner may replace, demote or remove someone who holds the owner role (a manager could)
local function protectedOwner(src, businessId, targetCid)
    local stored = RestaurantData.employees[businessId] and RestaurantData.employees[businessId][targetCid]
    return stored ~= nil and stored.role == 'owner' and RoleOf(src, businessId, OFF_SHIFT) ~= 'owner'
end

local function roleAllows(role, permission)
    local def = role and Config.Permissions.Roles[role]
    if not def then return false end
    for _, perm in ipairs(def.permissions or {}) do
        if perm == 'all' or perm == permission then return true end
    end
    return false
end

--- The role a citizen holds at a restaurant, for staff changes another resource makes in their name
--- (the Job Board): their live role when online (RoleOf off shift: hiring is management, done from
--- PF Computer too), otherwise the role saved on the staff list.
local function roleOfCitizen(businessId, cid)
    local P = QBCore.Functions.GetPlayerByCitizenId(cid)
    local src = P and P.PlayerData and P.PlayerData.source
    if src then return RoleOf(src, businessId, OFF_SHIFT) end
    local stored = RestaurantData.employees[businessId] and RestaurantData.employees[businessId][cid]
    return stored and Config.Permissions.Roles[stored.role] and stored.role or nil
end

--- Adds (or re-roles) a member of staff. actorRole is the role of whoever does it; actorId is logged.
--- The restaurant UI and the AddStaff export both go through here, with the same rules: the actor needs
--- employee.manage, only real roles, and only an owner gives the owner role or changes an owner.
local function addStaff(businessId, targetCid, role, actorRole, actorId)
    if not roleAllows(actorRole, 'employee.manage') then return false, 'no_permission' end
    if type(targetCid) ~= 'string' or targetCid == '' or #targetCid > 64 or type(role) ~= 'string' or not Config.Permissions.Roles[role] then
        return false, 'invalid_role'
    end
    local stored = RestaurantData.employees[businessId] and RestaurantData.employees[businessId][targetCid]
    if (role == 'owner' or (stored and stored.role == 'owner')) and actorRole ~= 'owner' then return false, 'owner_only' end
    RestaurantData.employees[businessId] = RestaurantData.employees[businessId] or {}
    RestaurantDB.SaveEmployee(businessId, targetCid, role)
    RestaurantData.employees[businessId][targetCid] = {
        cid = targetCid,
        citizenid = targetCid,
        role = role,
        hiredDate = os.time(),
        shifts = 0,
        orders = 0,
        performance = 100
    }
    LogAction('employee_change', { businessId = businessId, action = 'hired', targetCid = targetCid, role = role, by = actorId })
    return true
end

--- Removes a member of staff with the same rules (employee.manage; only an owner removes an owner).
local function removeStaff(businessId, targetCid, actorRole, actorId)
    if not roleAllows(actorRole, 'employee.manage') then return false, 'no_permission' end
    local list = RestaurantData.employees[businessId]
    local stored = type(targetCid) == 'string' and list and list[targetCid]
    if not stored then return false, 'not_staff' end
    if stored.role == 'owner' and actorRole ~= 'owner' then return false, 'owner_only' end
    list[targetCid] = nil
    RestaurantDB.DeleteEmployee(businessId, targetCid)
    LogAction('employee_change', { businessId = businessId, action = 'fired', targetCid = targetCid, by = actorId })
    return true
end

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
    if (role == 'owner' and RoleOf(src, businessId, OFF_SHIFT) ~= 'owner') or protectedOwner(src, businessId, targetCid) then
        NotifyPlayer(src, 'Only the owner can add or change an owner', 'error')
        return
    end
    addStaff(businessId, targetCid, role, RoleOf(src, businessId, OFF_SHIFT), GetPlayerIdentifier(src, 0))
    NotifyPlayer(src, 'Employee added successfully', 'success')
end)

-- Remove employee
RegisterNetEvent('pf-restaurants:server:removeEmployee', function(businessId, targetCid)
    local src = source
    
    if not HasPermission(src, businessId, 'employee.manage') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    if protectedOwner(src, businessId, targetCid) then
        NotifyPlayer(src, 'Only the owner can remove an owner', 'error')
        return
    end

    if removeStaff(businessId, targetCid, RoleOf(src, businessId, OFF_SHIFT), GetPlayerIdentifier(src, 0)) then
        NotifyPlayer(src, 'Employee removed successfully', 'success')
    else
        NotifyPlayer(src, 'Employee not found', 'error')
    end
end)

-- Server-only staff changes for other resources (the Job Board in pf-computer hires into a restaurant
-- through these). byCitizenid is the character making the change; their role at this restaurant must
-- allow it, exactly as in the restaurant's own staff screen. Returns true, or false and a reason.
--   exports['pf-restaurants']:AddStaff('burgershot_vespucci', 'ABC12345', 'cashier', 'OWN12345')
exports('AddStaff', function(businessId, citizenid, role, byCitizenid)
    if type(businessId) ~= 'string' or not RestaurantData.businesses[businessId] then return false, 'unknown_restaurant' end
    if type(byCitizenid) ~= 'string' or byCitizenid == '' or #byCitizenid > 64 then return false, 'no_permission' end
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 then return false, 'unknown_citizen' end
    if citizenid == byCitizenid then return false, 'invalid_role' end
    if not MySQL.scalar.await('SELECT 1 FROM players WHERE citizenid = ? LIMIT 1', { citizenid }) then return false, 'unknown_citizen' end
    return addStaff(businessId, citizenid, role, roleOfCitizen(businessId, byCitizenid), byCitizenid)
end)

exports('RemoveStaff', function(businessId, citizenid, byCitizenid)
    if type(businessId) ~= 'string' or not RestaurantData.businesses[businessId] then return false, 'unknown_restaurant' end
    if type(byCitizenid) ~= 'string' or byCitizenid == '' or #byCitizenid > 64 then return false, 'no_permission' end
    if citizenid == byCitizenid then return false, 'not_staff' end
    return removeStaff(businessId, citizenid, roleOfCitizen(businessId, byCitizenid), byCitizenid)
end)

--- The staff roles a restaurant can give: { { id, label } }, lowest first by permission count.
exports('GetStaffRoles', function()
    local out = {}
    for id, def in pairs(Config.Permissions.Roles or {}) do
        out[#out + 1] = { id = id, label = def.label or id, size = #(def.permissions or {}) }
    end
    table.sort(out, function(a, b)
        if (a.id == 'owner') ~= (b.id == 'owner') then return b.id == 'owner' end
        if a.size ~= b.size then return a.size < b.size end
        return a.id < b.id
    end)
    for _, r in ipairs(out) do r.size = nil end
    return out
end)

-- Update employee role
RegisterNetEvent('pf-restaurants:server:updateEmployeeRole', function(businessId, targetCid, newRole)
    local src = source
    
    if not HasPermission(src, businessId, 'employee.manage') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    if not Config.Permissions.Roles[newRole] or ((newRole == 'owner' or protectedOwner(src, businessId, targetCid)) and RoleOf(src, businessId, OFF_SHIFT) ~= 'owner') then
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

-- ── shifts: clock in and out at a register ──────────────────────────────────
-- Staff hired onto the restaurant (the staff screen, the Job Board) have no job duty toggle: they work
-- only while clocked in. The server checks they stand at a register, and clocks them out when they
-- leave the restaurant for Config.Shifts.LeaveMinutes, log out, disconnect or change character.
-- One shift at a time: clocking in somewhere else ends the other one.

RegisterNetEvent('pf-restaurants:server:clockIn', function(businessId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(businessId) ~= 'string' or not Config.Restaurants[businessId] then return end
    local cid = Player.PlayerData.citizenid
    local role = RoleOf(src, businessId, OFF_SHIFT)
    if not role then
        NotifyPlayer(src, 'You are not an employee here', 'error')
        return
    end
    if ClockedIn(src, businessId, cid) then
        NotifyPlayer(src, 'You are already clocked in', 'error')
        return
    end
    if not RestaurantAtRegister(src, businessId) then
        NotifyPlayer(src, 'Clock in at one of the registers', 'error')
        return
    end
    for otherId in pairs(RestaurantData.shifts) do
        if otherId ~= businessId and EndShift(otherId, cid) then
            NotifyPlayer(src, 'Clocked out at ' .. tostring((Config.Restaurants[otherId] or {}).label or otherId), 'primary')
        end
    end
    StartShift(businessId, cid, src)
    LogAction('shift', { businessId = businessId, citizenid = cid, role = role, action = 'in' })
    NotifyPlayer(src, 'Clocked in as ' .. tostring((Config.Permissions.Roles[role] or {}).label or role), 'success')
end)

RegisterNetEvent('pf-restaurants:server:clockOut', function(businessId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(businessId) ~= 'string' or not Config.Restaurants[businessId] then return end
    local cid = Player.PlayerData.citizenid
    if not ClockedIn(src, businessId, cid) then
        NotifyPlayer(src, 'You are not clocked in', 'error')
        return
    end
    local duration = EndShift(businessId, cid) or 0
    LogAction('shift', { businessId = businessId, citizenid = cid, action = 'out', seconds = duration })
    NotifyPlayer(src, 'Clocked out. Shift duration: ' .. math.floor(duration / 60) .. ' minutes', 'success')
end)

-- logout, disconnect (pfm-core raises this for both) and character change end the shift
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    src = tonumber(src)
    if src then EndShiftsOf(src) end
end)

--- Clocks out staff who are gone or have been away from the restaurant too long. Runs every
--- Config.Shifts.CheckSeconds.
function SweepShifts()
    local now = os.time()
    local limit = ((Config.Shifts and tonumber(Config.Shifts.LeaveMinutes)) or 10) * 60
    for businessId, list in pairs(RestaurantData.shifts) do
        for cid, s in pairs(list) do
            local P = QBCore.Functions.GetPlayer(s.src)
            if not P or P.PlayerData.citizenid ~= cid then
                EndShift(businessId, cid)
            elseif InsideRestaurant(s.src, businessId) then
                s.outsideSince = nil
            else
                s.outsideSince = s.outsideSince or now
                if now - s.outsideSince >= limit then
                    EndShift(businessId, cid)
                    LogAction('shift', { businessId = businessId, citizenid = cid, action = 'left' })
                    NotifyPlayer(s.src, 'You left ' .. tostring((Config.Restaurants[businessId] or {}).label or businessId) .. ': clocked out', 'primary')
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(((Config.Shifts and tonumber(Config.Shifts.CheckSeconds)) or 30) * 1000)
        local ok, err = pcall(SweepShifts)
        if not ok then print('^1[pf-restaurants]^7 shift check failed: ' .. tostring(err)) end
    end
end)

-- Get employees list (with who is clocked in right now)
QBCore.Functions.CreateCallback('pf-restaurants:server:getEmployees', function(source, cb, businessId)
    if not HasPermission(source, businessId, 'employee.view') then
        cb(nil)
        return
    end
    local out = {}
    for cid, emp in pairs(RestaurantData.employees[businessId] or {}) do
        local row = {}
        for k, v in pairs(emp) do row[k] = v end
        local shift = RestaurantData.shifts[businessId] and RestaurantData.shifts[businessId][cid]
        row.onShift = shift ~= nil
        row.clockedIn = shift and shift.since or nil
        out[cid] = row
    end
    cb(out)
end)
