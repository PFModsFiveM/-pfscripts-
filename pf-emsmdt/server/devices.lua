-- The MDT as an app on the tablet and the computer (pf-devices): this resource's own page in a
-- device window, 1:1 the full-screen MDT (client/device_mode.lua, html/device_embed.js).
-- Every action still goes through this resource's callbacks and server checks .

local function allowedJobs()
    local jobs = {}
    for name, ok in pairs(Config.AllowedJobs or { ambulance = true }) do
        if ok then jobs[name] = 0 end
    end
    return jobs
end

local function register()
    if GetResourceState('pf-devices') ~= 'started' then return end
    exports['pf-devices']:RegisterApp({
        id = 'emsmdt', name = Config.TabletTitle or 'EMS MDT', icon = '🚑', kind = 'iframe',
        url = ('https://cfx-nui-%s/html/index.html?embed=1&device={device}'):format(GetCurrentResourceName()),
        devices = { 'tablet', 'computer' }, category = 'jobs', order = 9,
        access = { jobs = allowedJobs() },
        description = 'Patients, reports and dispatch',
        window = { width = 1280, height = 800 },
    })
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pf-devices' then register() end
end)
AddEventHandler('pf-devices:server:ready', register)
