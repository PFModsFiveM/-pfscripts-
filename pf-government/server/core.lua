-- =====================================================
-- PF GOVERNMENT - CORE INITIALIZATION
-- =====================================================

QBCore = exports[Config.FrameworkResourceName]:GetCoreObject()

-- Global state
Government = {
    Treasury = {},
    Taxes = {},
    Budgets = {},
    Laws = {},
    Licenses = {},
    Utilities = {},
    Bills = {},
    Businesses = {},
    Staff = {},
    Audit = {},
    NuiCallbacks = {}
}

-- Server-side NUI callback registry (client forwards NUI actions to server)
function RegisterNUICallback(action, handler)
    if type(action) ~= 'string' or type(handler) ~= 'function' then
        return
    end

    Government.NuiCallbacks[action] = handler
end

-- Utility Functions (used by all modules)
function GetPlayerIdentifier(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        return Player.PlayerData.citizenid
    end
    return nil
end

function GetPlayerName(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        return Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    end
    return 'Unknown'
end

function GetPlayerJob(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        return Player.PlayerData.job
    end
    return nil
end

function HasPermission(source, permission)
    local job = GetPlayerJob(source)
    if not job or job.name ~= Config.GovernmentJob then
        return false
    end
    
    local roleConfig = Config.Roles[job.grade.level]
    if not roleConfig then
        return false
    end
    
    -- Check if has 'all' permissions
    if roleConfig.permissions and #roleConfig.permissions > 0 then
        for _, perm in ipairs(roleConfig.permissions) do
            if perm == 'all' then
                return true
            end
            if perm == permission then
                return true
            end
        end
    end
    
    return false
end

-- Other resources (pf-computer's city hall apps) check the same roles instead of their own job lists
exports('HasPermission', function(source, permission)
    return HasPermission(source, permission) == true
end)

function NotifyPlayer(source, message, type)
    TriggerClientEvent('QBCore:Notify', source, message, type or 'primary')
end

function DebugPrint(message)
    if Config.Debug then
        print('^3[PF-GOVERNMENT DEBUG]^7 ' .. message)
    end
end

print('^2[PF-GOVERNMENT]^7 Core functions loaded')
