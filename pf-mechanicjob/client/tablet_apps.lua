-- pf-mechanicjob -> pf-tablet external app registration

local function GetTabletApps()
    return {
        {
            id = 'work-orders',
            label = 'Work Orders',
            icon = '🔧',
            external = true,
            resource = 'pf-mechanicjob'
        },
        {
            id = 'cash-register',
            label = 'Cash Register',
            icon = '💰',
            external = true,
            resource = 'pf-mechanicjob'
        },
        {
            id = 'management',
            label = 'Management',
            icon = '📋',
            external = true,
            resource = 'pf-mechanicjob'
        }
    }
end

exports('GetTabletApps', GetTabletApps)
