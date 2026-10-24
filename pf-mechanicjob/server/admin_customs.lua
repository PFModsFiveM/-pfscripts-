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
