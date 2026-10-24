local QBCore = exports['pfm-core']:GetCoreObject()

-- NOTE: Tablet UI is now managed by pf-tablet only
-- pf-jobs provides job-specific external modules and logic
-- See pf-tablet/client/main.lua for tablet management

-- NOTE: All NUI callbacks are now in pf-tablet (the main UI provider)
-- pf-jobs provides server-side logic and external modules only

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Tablet cleanup handled by pf-tablet
    end
end)

-- NUI callback that queries the server for business status
RegisterNUICallback('app/business/getStatus', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-jobs:server:getJobOnlineCounts', function(result)
        cb(result or {})
    end, Config.BusinessJobs)
end)

-- Server push -> tell UI to force refresh if window is open
RegisterNetEvent('pf-jobs:client:businessPushRefresh', function()
    SendNUIMessage({ action = 'businessForceRefresh' })
end)

-- Allow updating name explicitly
RegisterNetEvent('pf-jobs:client:setPlayerName', function(name)
    SendNUIMessage({ action = 'setPlayerName', value = name })
end)
