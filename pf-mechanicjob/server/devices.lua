-- Registers the mechanic apps (Work Orders, Cash Register, Management) with pf-devices, so the
-- same modules run on the tablet and the computer. Every action they take still goes through this
-- resource's own NUI callbacks and server checks (job, shop, boss permissions, ledger).

local function mechanicJobs()
    local jobs = {}
    for _, j in ipairs(Config.AllowedJobs or { 'mechanic' }) do jobs[j] = 0 end
    return jobs
end

local function registerApps()
    if GetResourceState('pf-devices') ~= 'started' then return end
    local devices = exports['pf-devices']
    local common = {
        entry = 'html/apps/mechanic.js',
        styles = { 'html/apps.css' },
        devices = { 'tablet', 'computer' },
        category = 'jobs',
        access = { jobs = mechanicJobs() },
    }
    local apps = {
        { id = 'mechanic-workorders', name = 'Work Orders', icon = '🔧', order = 30, description = 'Find, accept and finish repair jobs' },
        { id = 'mechanic-register', name = 'Cash Register', icon = '💰', order = 31, description = 'Charge customers at the shop' },
        { id = 'mechanic-management', name = 'Management', icon = '📋', order = 32, description = 'Staff, prices, sales and settings' },
    }
    for _, app in ipairs(apps) do
        local def = {}
        for k, v in pairs(common) do def[k] = v end
        for k, v in pairs(app) do def[k] = v end
        exports['pf-devices']:RegisterApp(def)
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pf-devices' then registerApps() end
end)
AddEventHandler('pf-devices:server:ready', registerApps)
