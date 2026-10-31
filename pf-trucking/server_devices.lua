-- Trucking app (pf-devices, tablet + computer, installed from the App Store): the trucking page
-- (html/index.html) embedded in either device; '{device}' tells it which layout to use. Contracts,
-- loading and delivery stay server-checked in server.lua.
local function register()
    if GetResourceState('pf-devices') ~= 'started' then return end
    exports['pf-devices']:RegisterApp({
        id = 'trucking', name = 'Trucking', icon = '🚚', kind = 'iframe',
        url = 'https://cfx-nui-pf-trucking/html/index.html?embed=1&device={device}',
        category = 'jobs', order = 15,
        access = { installable = true },
        store = { description = 'Haul supply orders for stores, restaurants and shops. Player truckers get the job before the AI.', publisher = 'PF Freight' },
        description = 'Supply contracts for truckers',
        window = { width = 1100, height = 720 },
    })
end
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pf-devices' then register() end
end)
AddEventHandler('pf-devices:server:ready', register)
