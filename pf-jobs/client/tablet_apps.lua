-- pf-jobs -> pf-tablet external app registration
-- pf-tablet can optionally call exports['pf-jobs']:GetTabletApps() (client-side)

local function GetTabletApps()
    return {
        {
            id = 'gruppe6',
            label = 'Gruppe6',
            icon = '🛡️',
            external = true,
            resource = 'pf-jobs'
        },
        {
            id = 'garbage',
            label = 'Garbage',
            icon = '🗑️',
            external = true,
            resource = 'pf-jobs'
        },
        {
            id = 'taxi',
            label = 'Taxi',
            icon = '🚕',
            external = true,
            resource = 'pf-jobs'
        }
    }
end

exports('GetTabletApps', GetTabletApps)
