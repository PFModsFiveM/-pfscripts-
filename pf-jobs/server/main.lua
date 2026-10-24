local QBCore = exports['pfm-core']:GetCoreObject()

-- NOTE: Tablet item is registered by pf-tablet only to avoid conflicts
-- This resource provides job logic and external modules for the tablet UI

-- You can add server-side events here for job-specific functionality
RegisterNetEvent('pf-jobs:server:appAction', function(appName, action, data)
    local src = source
    -- Handle app-specific actions here in the future
end)
