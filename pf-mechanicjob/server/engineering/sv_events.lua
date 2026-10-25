-- ============================================================================
-- PF MECHANIC JOB - ENGINEERING EVENTS (Server)
-- ============================================================================

local QBCore = exports['pfm-core']:GetCoreObject()
local EngineConfig = require('config.engineering')
local Engineering = require('server.engineering.sv_engineering')

if not EngineConfig.Enabled then
    if Config.Debug then
        print('[Engineering] System disabled in config')
    end
    return
end

-- ============================================================================
-- Client Requests
-- ============================================================================

-- Plates are cleaned like the client does; anything longer than a GTA plate is refused, so a client
-- can't create tuning rows for made-up keys.
local function cleanPlate(plate)
    plate = (tostring(plate or ''):gsub('%s+', ''):upper())
    if plate == '' or #plate > 8 then return nil end
    return plate
end

-- Wear, heat and ECU/boost settings are written only by the driver of that car (checked on the
-- server). These events used to take any plate, so anyone could reset their own wear to zero (a
-- free rebuild) or change another player's car.
local function drivesPlate(src, plate)
    local ped = GetPlayerPed(src)
    local veh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return false end
    return cleanPlate(GetVehicleNumberPlateText(veh)) == plate
end

---Client requests current tuning data
RegisterNetEvent('engineering:requestTuning', function(plate)
    local src = source
    plate = cleanPlate(plate)
    if not plate then return end

    -- Get or create tuning
    local tuning = Engineering:GetOrCreateTuning(plate)
    
    if tuning then
        TriggerClientEvent('engineering:syncTuning', src, tuning)
    end
end)

---Client syncs wear and heat data
RegisterNetEvent('engineering:syncWearAndHeat', function(plate, engineWear, turboWear, engineHeat, turboHeat)
    local src = source
    plate = cleanPlate(plate)
    if not plate or not drivesPlate(src, plate) then return end
    local function num(v) v = tonumber(v); return (v and v == v) and v or nil end
    engineWear, turboWear, engineHeat, turboHeat = num(engineWear), num(turboWear), num(engineHeat), num(turboHeat)
    if not (engineWear and turboWear and engineHeat and turboHeat) then return end
    -- wear only builds up while driving; it goes down through a paid service
    local tuning = Engineering:GetTuning(plate)
    if tuning then
        engineWear = math.max(engineWear, tonumber(tuning.engine_wear) or 0)
        turboWear = math.max(turboWear, tonumber(tuning.turbo_wear) or 0)
    end

    -- Call server engineering to sync
    Engineering:SyncWearAndHeat(src, plate, engineWear, turboWear, engineHeat, turboHeat)
end)

---Client requests ECU map change
RegisterNetEvent('engineering:setECUMap', function(plate, mapName)
    local src = source
    plate = cleanPlate(plate)
    if not plate or type(mapName) ~= 'string' then return end
    if not drivesPlate(src, plate) then return end

    local success = Engineering:SetECUMap(plate, mapName)
    if success then
        TriggerClientEvent('engineering:ecuUpdated', src, plate, mapName)
    end
end)

---Client requests boost change
RegisterNetEvent('engineering:setBoost', function(plate, psi)
    local src = source
    plate = cleanPlate(plate)
    if not plate or not drivesPlate(src, plate) then return end

    local success, message = Engineering:SetBoost(plate, psi)
    if success then
        TriggerClientEvent('engineering:boostUpdated', src, plate, psi)
    else
        TriggerClientEvent('notification', src, message)
    end
end)

-- ============================================================================
-- Tablet/Menu Integration
-- ============================================================================

-- The upgrade and service events below are server-only (AddEventHandler). No client or tablet page
-- triggers them, and as network events they gave any client free upgrades, rebuilds and services
-- on any plate. Item use goes through sv_useables.lua.

---Apply a simple upgrade to a vehicle
AddEventHandler('engineering:applySimpleUpgrade', function(plate, upgradeId)
    local src = source
    if not plate or not upgradeId then return end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    
    local success, message = Engineering:ApplySimpleUpgrade(plate, upgradeId)
    
    if success then
        TriggerClientEvent('notification', src, message, 'success')
        TriggerClientEvent('engineering:syncTuning', src, Engineering:GetTuning(plate))
    else
        TriggerClientEvent('notification', src, message, 'error')
    end
end)

---Install a major component
AddEventHandler('engineering:installComponent', function(plate, componentType, componentValue)
    local src = source
    if not plate or not componentType or not componentValue then return end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    
    local success, message = Engineering:InstallComponent(plate, componentType, componentValue)
    
    if success then
        TriggerClientEvent('notification', src, message, 'success')
        TriggerClientEvent('engineering:syncTuning', src, Engineering:GetTuning(plate))
    else
        TriggerClientEvent('notification', src, message, 'error')
    end
end)

---Perform oil service
AddEventHandler('engineering:serviceOil', function(plate, cost, mechanicId)
    local src = source
    if not plate then return end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    mechanicId = mechanicId or tostring(src)
    cost = tonumber(cost) or 250
    
    local success = Engineering:ServiceOil(plate, cost, mechanicId)
    
    if success then
        TriggerClientEvent('notification', src, "Oil service completed", 'success')
        TriggerClientEvent('engineering:syncTuning', src, Engineering:GetTuning(plate))
    end
end)

---Perform cooling service
AddEventHandler('engineering:serviceCooling', function(plate, cost, mechanicId)
    local src = source
    if not plate then return end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    mechanicId = mechanicId or tostring(src)
    cost = tonumber(cost) or 400
    
    local success = Engineering:ServiceCooling(plate, cost, mechanicId)
    
    if success then
        TriggerClientEvent('notification', src, "Cooling service completed", 'success')
        TriggerClientEvent('engineering:syncTuning', src, Engineering:GetTuning(plate))
    end
end)

---Rebuild engine
AddEventHandler('engineering:rebuildEngine', function(plate, cost, mechanicId)
    local src = source
    if not plate then return end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    mechanicId = mechanicId or tostring(src)
    cost = tonumber(cost) or 15000
    
    local success = Engineering:RebuildEngine(plate, cost, mechanicId)
    
    if success then
        TriggerClientEvent('notification', src, "Engine rebuilt successfully", 'success')
        TriggerClientEvent('engineering:syncTuning', src, Engineering:GetTuning(plate))
    end
end)

---Replace clutch
AddEventHandler('engineering:replaceClutch', function(plate, cost, mechanicId)
    local src = source
    if not plate then return end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    mechanicId = mechanicId or tostring(src)
    cost = tonumber(cost) or 4000
    
    local success = Engineering:ReplaceClutch(plate, cost, mechanicId)
    
    if success then
        TriggerClientEvent('notification', src, "Clutch replaced", 'success')
        TriggerClientEvent('engineering:syncTuning', src, Engineering:GetTuning(plate))
    end
end)

---Rebuild gearbox
AddEventHandler('engineering:rebuildGearbox', function(plate, cost, mechanicId)
    local src = source
    if not plate then return end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    mechanicId = mechanicId or tostring(src)
    cost = tonumber(cost) or 12000
    
    local success = Engineering:RebuildGearbox(plate, cost, mechanicId)
    
    if success then
        TriggerClientEvent('notification', src, "Gearbox rebuilt", 'success')
        TriggerClientEvent('engineering:syncTuning', src, Engineering:GetTuning(plate))
    end
end)

---Get build summary for UI/receipts
QBCore.Functions.CreateCallback('engineering:getBuildSummary', function(source, cb, plate)
    if not plate then
        cb(nil)
        return
    end
    
    plate = tostring(plate):gsub('%s+', ''):upper()
    local summary = Engineering:GetBuildSummary(plate)
    cb(summary)
end)

-- ============================================================================
-- Exports for menus and tablets
-- ============================================================================

exports('GetTuning', function(plate)
    if not EngineConfig.Enabled then return nil end
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    return Engineering:GetTuning(plate)
end)

exports('GetOrCreateTuning', function(plate, model)
    if not EngineConfig.Enabled then return nil end
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    return Engineering:GetOrCreateTuning(plate, model)
end)

exports('GetBuildSummary', function(plate)
    if not EngineConfig.Enabled then return nil end
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    return Engineering:GetBuildSummary(plate)
end)

exports('ApplySimpleUpgrade', function(plate, upgradeId)
    if not EngineConfig.Enabled then return false end
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    local success, msg = Engineering:ApplySimpleUpgrade(plate, upgradeId)
    return success
end)

exports('InstallComponent', function(plate, componentType, componentValue)
    if not EngineConfig.Enabled then return false end
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    local success, msg = Engineering:InstallComponent(plate, componentType, componentValue)
    return success
end)

if Config.Debug then
    print('[Engineering] Events and exports registered')
end
