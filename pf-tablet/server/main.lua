local QBCore = exports['pfm-core']:GetCoreObject()

-- Register usable item
QBCore.Functions.CreateUseableItem(Config.TabletItem, function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    TriggerClientEvent('pf-tablet:client:openTablet', source)
end)

-- You can add server-side events here for future app functionality
RegisterNetEvent('pf-tablet:server:appAction', function(appName, action, data)
    local src = source
    -- Handle app-specific actions here in the future
end)
