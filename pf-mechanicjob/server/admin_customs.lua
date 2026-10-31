local QBCore = exports['pfm-core']:GetCoreObject()

local function hasQbPermission(src, permission)
    if not QBCore or not QBCore.Functions or type(QBCore.Functions.HasPermission) ~= 'function' then
        return false
    end

    local ok, allowed = pcall(function()
        return QBCore.Functions.HasPermission(src, permission)
    end)

    return ok and allowed == true
end

local function isAdminAllowed(src)
    if src == 0 then
        return true
    end

    -- Custom ace support if you want explicit control:
    -- add_ace group.admin pf.mechanic.admincustoms allow
    local aceChecks = {
        'pf.mechanic.admincustoms',
        'group.admin',
        'txadmin.menu',
        'txadmin',
    }

    for _, ace in ipairs(aceChecks) do
        local ok, allowed = pcall(function()
            return IsPlayerAceAllowed(src, ace)
        end)
        if ok and allowed then
            return true
        end
    end

    if hasQbPermission(src, 'admin') or hasQbPermission(src, 'god') then
        return true
    end

    return false
end

local function openAdminCustoms(src)
    if not isAdminAllowed(src) then
        TriggerClientEvent('QBCore:Notify', src, 'You are not allowed to use /admincustoms', 'error')
        return
    end

    TriggerClientEvent('pf-mechanicjob:client:adminCustoms:openRoot', src)
end

QBCore.Functions.CreateCallback('pf-mechanicjob:server:adminCustoms:hasAccess', function(source, cb)
    cb(isAdminAllowed(source))
end)

RegisterCommand('admincustoms', function(source)
    openAdminCustoms(source)
end, false)

RegisterCommand('admincustom', function(source)
    openAdminCustoms(source)
end, false)

-- ── Vehicle state set from /admincustoms ──────────────────────────
-- The admin's client used to write these vehicle state bags itself. They are now set here, for an
-- admin who is in or near that car (sv_stateBagStrictMode: clients cannot write replicated state).
local ADMIN_REACH = 30.0
local PART_KEYS = {
    'alternator', 'sparkplugs', 'carbattery', 'oil', 'oil_filter', 'brakes', 'suspension', 'axle',
    'fuel_injector', 'powersteeringpump', 'radiator', 'power_steering_fluid', 'transmissionfluid',
    'brakefluid', 'coolant', 'engine_part', 'body_part',
}

local function cleanPartDamage()
    local clean = { tires = {} }
    for _, key in ipairs(PART_KEYS) do clean[key] = 0 end
    return clean
end

local function adminVehicle(src, netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= veh and #(GetEntityCoords(ped) - GetEntityCoords(veh)) > ADMIN_REACH then
        return nil
    end
    return veh
end

RegisterNetEvent('pf-mechanicjob:server:adminCustoms:vehicleState', function(netId, action, value)
    local src = source
    if type(action) ~= 'string' or not isAdminAllowed(src) then return end
    local veh = adminVehicle(src, netId)
    if not veh then
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle not found nearby', 'error')
        return
    end
    -- the car's saved state first, so a reset is not undone by a later load
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local st = Entity(veh).state
    local cap = (Config.NOS and Config.NOS.capacity) or 100

    if action == 'drift' then
        if type(value) ~= 'boolean' then return end
        st:set('pfDriftTires', value, true)
    elseif action == 'resetPartDamage' then
        st:set('partDamage', cleanPartDamage(), true)
    elseif action == 'resetMileage' then
        st:set('mileage', 0, true)
    elseif action == 'nosInstall' then
        local nos = type(st.nos) == 'table' and st.nos or {}
        st:set('nos', {
            has = true,
            level = cap,
            levelSel = math.max(1, math.min(3, math.floor(tonumber(nos.levelSel) or 1))),
            style = tonumber(nos.style) or 1,
            color = type(nos.color) == 'string' and nos.color or (Config.NOS and Config.NOS.defaultColor) or '#55CCFF',
            cooldownAt = 0,
            lastBoostEnd = 0,
        }, true)
    elseif action == 'nosLevel' then
        local levelSel = tonumber(value)
        local nos = st.nos
        if not levelSel or levelSel ~= math.floor(levelSel) or levelSel < 1 or levelSel > 3 then return end
        if not (type(nos) == 'table' and nos.has) then return end
        nos.levelSel = levelSel
        st:set('nos', nos, true)
    elseif action == 'nosRemove' then
        st:set('nos', nil, true)
    end
end)
