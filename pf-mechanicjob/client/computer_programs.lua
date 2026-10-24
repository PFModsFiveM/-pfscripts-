-- pf-mechanicjob -> pf-computer external program registration
-- This file demonstrates how to add custom programs to pf-computer

local function GetComputerPrograms()
    -- Tablet apps are no longer registered as external programs
    -- All mechanic management features (cash register, inventory, etc.) are now part of Business Manager
    return {}
end

-- Export so pf-computer can detect it
exports('GetComputerPrograms', GetComputerPrograms)

-- Handle program launches
RegisterNUICallback('program:mechanic-work-orders:open', function(data, cb)
    -- Open work orders interface
    -- You can open the tablet, trigger an event, or open custom NUI here
    TriggerEvent('pf-mechanicjob:client:openWorkOrders', 'computer')
    cb({ ok = true })
end)

RegisterNUICallback('program:mechanic-parts-catalog:open', function(data, cb)
    -- Open parts catalog
    TriggerEvent('pf-mechanicjob:client:openPartsCatalog', 'computer')
    cb({ ok = true })
end)

RegisterNUICallback('program:mechanic-diagnostics:open', function(data, cb)
    -- Open diagnostic logs
    TriggerEvent('pf-mechanicjob:client:openDiagnostics', 'computer')
    cb({ ok = true })
end)

RegisterNUICallback('program:mechanic-tuning:open', function(data, cb)
    -- Open tuning workbench entrypoint for dyno/tuning workflows
    TriggerEvent('pf-mechanicjob:client:openTuningWorkbench', 'computer')
    cb({ ok = true })
end)

-- Alternative: Use existing tablet apps if you prefer
-- This would open the tablet with a specific app selected
--[[
RegisterNUICallback('program:mechanic-work-orders:open', function(data, cb)
    exports['pf-tabletuionly']:OpenTablet('work-orders')
    cb({ ok = true })
end)
]]--
