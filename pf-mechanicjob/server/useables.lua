local QBCore = exports['pfm-core']:GetCoreObject()

-- Helper: Check if player's job is allowed to use mechanic items
local function isAllowedJob(Player, itemName)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return false end
    
    -- Check if item is public (anyone can use)
    for _, publicItem in ipairs(Config.PublicItems or {}) do
        if publicItem == itemName then return true end
    end
    
    -- Check if player's job is in allowed list
    local playerJob = Player.PlayerData.job.name
    for _, allowedJob in ipairs(Config.AllowedJobs or {}) do
        if playerJob == allowedJob then return true end
    end
    
    return false
end

-- NEW: server-side toolbox gate
local function requireToolbox(Player, src)
    if not Player then return false end
    local tb = Player.Functions.GetItemByName('toolbox')
    if not tb then
        TriggerClientEvent('QBCore:Notify', src, 'You need a toolbox to do mechanic work', 'error')
        return false
    end
    return true
end

-- Make brake_pads usable and trigger client logic
QBCore.Functions.CreateUseableItem('brake_pads', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    if not isAllowedJob(Player, 'brake_pads') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    
    TriggerClientEvent('qb-core:client:use:brake_pads', source)
end)

-- Make mechanic_tools usable (FIXED - single registration with toolbox check)
QBCore.Functions.CreateUseableItem('mechanic_tools', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    if Config.Debug then
        print('[SERVER DEBUG] mechanic_tools used by player ' .. source)
    end
    
    if not isAllowedJob(Player, 'mechanic_tools') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:openMechanicTools', source)
end)

-- Make alternator usable
QBCore.Functions.CreateUseableItem('alternator', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    if not isAllowedJob(Player, 'alternator') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:alternator', source)
end)

-- Make engine_oil usable
QBCore.Functions.CreateUseableItem('engine_oil', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:engine_oil', source)
end)


-- Make oil_filter usable
QBCore.Functions.CreateUseableItem('oil_filter', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:oil_filter', source)
end)

-- diagnostics tool (requires toolbox)
QBCore.Functions.CreateUseableItem('diagnosticstool', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not isAllowedJob(Player, 'diagnosticstool') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:openToolsMenu', source)
end)

-- repair_kit (requires toolbox)
QBCore.Functions.CreateUseableItem('repair_kit', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:useRepairKit', source)
end)

-- fuel_injector
QBCore.Functions.CreateUseableItem('fuel_injector', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:fuel_injector', source)
end)

-- powersteeringpump
QBCore.Functions.CreateUseableItem('powersteeringpump', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:powersteeringpump', source)
end)

-- radiator
QBCore.Functions.CreateUseableItem('radiator', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:radiator', source)
end)

-- power_steering_fluid
QBCore.Functions.CreateUseableItem('power_steering_fluid', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:power_steering_fluid', source)
end)

-- transmissionfluid
QBCore.Functions.CreateUseableItem('transmissionfluid', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:transmissionfluid', source)
end)

-- brakefluid
QBCore.Functions.CreateUseableItem('brakefluid', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:brakefluid', source)
end)

-- coolant
QBCore.Functions.CreateUseableItem('coolant', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:coolant', source)
end)

-- service_book (with vehicle locking system)
QBCore.Functions.CreateUseableItem('service_book', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not item then
        TriggerClientEvent('QBCore:Notify', source, 'Service book not found', 'error')
        return
    end
    
    -- Get metadata to check if locked to a plate
    local metadata = item.info or {}
    local lockedPlate = metadata.lockedPlate
    
    -- Trigger client event with lock + slot
    TriggerClientEvent('pf-mechanicjob:client:use:service_book', source, lockedPlate, item.slot)
end)

-- Make tire_new usable (replace burst tires)
QBCore.Functions.CreateUseableItem('tire_new', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    if not isAllowedJob(Player, 'tire_new') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:use:tire_new', source)
end)

-- Window tint supplies -> open client tint picker (no toolbox needed - public item)
QBCore.Functions.CreateUseableItem('tint_supplies', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:usePart', src, item)
end)
QBCore.Functions.CreateUseableItem('tint', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:usePart', src, { name = 'tint_supplies', label = item.label })
end)
QBCore.Functions.CreateUseableItem('window_tint', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:usePart', src, { name = 'tint_supplies', label = item.label })
end)

-- Optional: cosmetics route to the same handler (requires toolbox)
QBCore.Functions.CreateUseableItem('spoiler', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'spoiler')
end)
QBCore.Functions.CreateUseableItem('bumper', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'bumper')
end)
QBCore.Functions.CreateUseableItem('vehicle_bumper', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'vehicle_bumper')
end)
QBCore.Functions.CreateUseableItem('skirts', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'skirts')
end)
QBCore.Functions.CreateUseableItem('exhaust', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'exhaust')
end)
QBCore.Functions.CreateUseableItem('rollcage', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'rollcage')
end)
QBCore.Functions.CreateUseableItem('hood', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'hood')
end)
QBCore.Functions.CreateUseableItem('roof', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'roof')
end)
QBCore.Functions.CreateUseableItem('externals', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'externals')
end)
QBCore.Functions.CreateUseableItem('internals', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'internals')
end)
QBCore.Functions.CreateUseableItem('livery', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'livery')
end)
QBCore.Functions.CreateUseableItem('customplate', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'customplate')
end)
QBCore.Functions.CreateUseableItem('seat', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'seat')
end)
QBCore.Functions.CreateUseableItem('horn', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'horn')
end)
QBCore.Functions.CreateUseableItem('rims', function(src, item)
    local Player = QBCore.Functions.GetPlayer(src); if not Player or not requireToolbox(Player, src) then return end
    TriggerClientEvent('pf-mechanicjob:client:openItemModMenu', src, 'rims')
end)

-- Callback for consuming brake pads atomically
QBCore.Functions.CreateCallback('pf-mechanicjob:server:consumeBrakePad', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end

    local item = Player.Functions.GetItemByName('brake_pads')
    if not item or (item.amount or 0) < 1 then
        cb(false)
        return
    end

    local removed = Player.Functions.RemoveItem('brake_pads', 1)
    if removed then
        -- show UI box on client
        if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items['brake_pads'] then
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items['brake_pads'], 'remove', 1)
        end
        cb(true)
    else
        cb(false)
    end
end)

-- Register all repair items as useable (enforce toolbox)
local repairItems = {
    'alternator',
    'engine_oil',
    'oil_filter',
    'fuel_injector',
    'powersteeringpump',
    'radiator',
    'power_steering_fluid',
    'transmissionfluid',
    'brakefluid',
    'coolant',
    'sparkplugs',
    'carbattery',
    'brake_pads',
    'susp_arm',
    'axleparts',
    'engine_part',
    'body_part',
    'tire_new'
}

for _, itemName in ipairs(repairItems) do
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        if not requireToolbox(Player, source) then return end
        TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, itemName)
    end)
end

-- CHANGED: diagnostics_tool opens inspection flow (requires toolbox)
QBCore.Functions.CreateUseableItem('diagnostics_tool', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not isAllowedJob(Player, 'diagnostics_tool') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:openToolsMenu', source)  -- Opens inspection → diagnostics health menu
end)

-- Paintcan item (no toolbox needed - public item)
QBCore.Functions.CreateUseableItem('paintcan', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:usePaintcan', source, {})
end)

-- Paint Kit (requires toolbox)
QBCore.Functions.CreateUseableItem('paint_kit', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not requireToolbox(Player, source) then return end
    TriggerClientEvent('pf-mechanicjob:client:usePaint', source, 'paint_kit')
end)

-- Receipt items (public - anyone can view)
QBCore.Functions.CreateUseableItem('mech_receipt', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf_mech:receipt:use', source, item.info or {})
end)

QBCore.Functions.CreateUseableItem('paper_receipt', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf_mech:receipt:use', source, item.info or {})
end)

QBCore.Functions.CreateUseableItem('receipt', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf_mech:receipt:use', source, item.info or {})
end)
