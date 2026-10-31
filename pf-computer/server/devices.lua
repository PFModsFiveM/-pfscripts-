-- pf-government's management screens (City Hall, Business Oversight) as computer apps on pf-devices.
-- They used to appear only on 'mayor' computers (one prop model); now any computer shows them to staff
-- with the pf-government permission, which pf-devices checks on the server before it launches.
-- Launching closes the computer (pf-devices does that for launch apps) and the client event
-- pf-computer:client:openGovernmentProgram reopens it with pf-government's own page in a window.
-- The in-shell City Hall copy with made-up laws, budgets and businesses was removed.

local APPS = {
    {
        id = 'cityhall-admin', name = 'City Hall', icon = '🏛️', category = 'government', order = 5,
        program = 'pf-government-city-hall', access = { gov = 'audit' },
        description = 'Laws, taxes, budgets, utilities and staff (pf-government)',
    },
    {
        id = 'cityhall-businesses', name = 'Business Oversight', icon = '🏢', category = 'government', order = 6,
        program = 'pf-government-businesses', access = { gov = 'businesses' },
        description = 'Business registry, licences and inspections (pf-government)',
    },
}

local function register()
    if GetResourceState('pf-devices') ~= 'started' or GetResourceState('pf-government') ~= 'started' then return false end
    local all = true
    for _, a in ipairs(APPS) do
        local ok = pcall(function()
            exports['pf-devices']:RegisterApp({
                id = a.id, name = a.name, icon = a.icon, category = a.category, order = a.order,
                devices = { 'computer' }, kind = 'launch',
                launch = { event = 'pf-computer:client:openGovernmentProgram', args = { a.program } },
                access = a.access, description = a.description,
            })
        end)
        all = all and ok
    end
    return all
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pf-devices' or resource == 'pf-government' then
        SetTimeout(1000, register)
    end
end)
AddEventHandler('pf-devices:server:ready', register)
