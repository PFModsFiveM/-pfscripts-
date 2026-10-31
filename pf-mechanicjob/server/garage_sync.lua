-- This file is compatible with both qb-garages and cd_garages (codesign).
-- It listens for vehicle state sync events from the client, regardless of garage system.

local QBCore = exports['pfm-core']:GetCoreObject()

-- In-memory cache: [plate] = { props (full vehicle properties), lastUpdate }
local vehicleStateCache = {}

-- Helper: Get citizenid from plate
local function getCitizenIdFromPlate(plate)
    local row = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    return row and row.citizenid or nil
end

local function cleanPlate(plate)
    return (tostring(plate or ''):gsub('%s+', ''):upper())
end

-- Who may write a car's saved state: its owner, or whoever is in that car right now (checked on the
-- server). These events used to accept any plate from any client, so a player could overwrite the
-- saved mods and damage of anyone's car. Returns the owner's citizenid when allowed.
local MAX_PROPS_JSON = 65535
local function mayWrite(src, plate)
    if not src or plate == '' or #plate > 8 then return nil end
    local Player = exports['pfm-core']:GetPlayer(src)
    if not Player then return nil end
    local owner = getCitizenIdFromPlate(plate)
    if not owner then return nil end
    if owner == Player.PlayerData.citizenid then return owner end
    local ped = GetPlayerPed(src)
    local veh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if veh ~= 0 and cleanPlate(GetVehicleNumberPlateText(veh)) == plate then return owner end
    return nil
end

local function propsOk(props)
    if type(props) ~= 'table' then return false end
    local ok, encoded = pcall(json.encode, props)
    return ok and type(encoded) == 'string' and #encoded <= MAX_PROPS_JSON
end

-- Helper: Centralized diagnostic UPSERT
local function upsertDiagnostics(plate, citizenid, pd, mileage, engineHealth, bodyHealth, tankHealth, dirtLevel)
    local sql = [[
        INSERT INTO vehicle_diagnostics (
            plate,citizenid,alternator,sparkplugs,carbattery,oil,oil_filter,brakes,suspension,axle,
            fuel_injector,powersteeringpump,radiator,power_steering_fluid,transmissionfluid,brakefluid,coolant,
            engine_part,body_part,mileage,engineHealth,bodyHealth,tankHealth,dirtLevel
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
            alternator=VALUES(alternator),sparkplugs=VALUES(sparkplugs),carbattery=VALUES(carbattery),
            oil=VALUES(oil),oil_filter=VALUES(oil_filter),brakes=VALUES(brakes),suspension=VALUES(suspension),
            axle=VALUES(axle),fuel_injector=VALUES(fuel_injector),powersteeringpump=VALUES(powersteeringpump),
            radiator=VALUES(radiator),power_steering_fluid=VALUES(power_steering_fluid),transmissionfluid=VALUES(transmissionfluid),
            brakefluid=VALUES(brakefluid),coolant=VALUES(coolant),engine_part=VALUES(engine_part),body_part=VALUES(body_part),
            mileage=VALUES(mileage),engineHealth=VALUES(engineHealth),bodyHealth=VALUES(bodyHealth),
            tankHealth=VALUES(tankHealth),dirtLevel=VALUES(dirtLevel)
    ]]
    MySQL.insert.await(sql, {
        plate,citizenid,
        tonumber(pd.alternator) or 0, tonumber(pd.sparkplugs) or 0, tonumber(pd.carbattery) or 0,
        tonumber(pd.oil) or 0, tonumber(pd.oil_filter) or 0, tonumber(pd.brakes) or 0,
        tonumber(pd.suspension) or 0, tonumber(pd.axle) or 0, tonumber(pd.fuel_injector) or 0,
        tonumber(pd.powersteeringpump) or 0, tonumber(pd.radiator) or 0,
        tonumber(pd.power_steering_fluid) or 0, tonumber(pd.transmissionfluid) or 0,
        tonumber(pd.brakefluid) or 0, tonumber(pd.coolant) or 0,
        tonumber(pd.engine_part) or 0, tonumber(pd.body_part) or 0,
        tonumber(mileage) or 0, tonumber(engineHealth) or 1000.0,
        tonumber(bodyHealth) or 1000.0, tonumber(tankHealth) or 1000.0,
        tonumber(dirtLevel) or 0.0
    })
    
    if Config.Debug then
        print(string.format('[DIAG UPSERT] plate=%s oil=%.1f brakes=%.1f', plate, tonumber(pd.oil) or 0, tonumber(pd.brakes) or 0))
    end
end

local PART_COLUMNS = {
    'alternator', 'sparkplugs', 'carbattery', 'oil', 'oil_filter', 'brakes', 'suspension', 'axle',
    'fuel_injector', 'powersteeringpump', 'radiator', 'power_steering_fluid', 'transmissionfluid',
    'brakefluid', 'coolant', 'engine_part', 'body_part',
}

local function rowToPartDamage(row)
    local pd = {}
    for _, col in ipairs(PART_COLUMNS) do pd[col] = tonumber(row[col]) or 0 end
    return pd
end

-- partDamage, mileage and NOS are vehicle state bags only the server writes (sv_stateBagStrictMode).
-- A spawned car gets its saved values here: once per car, by the plate the server reads off the
-- car, for a player in or near it (the client used to write them from the callback below, which
-- let a car be "restored" to its stored wear as often as a client liked).
local RESTORE_REACH = 50.0
local restoredVehicles = {}   -- [vehicle] = true once its saved state was applied

RegisterNetEvent('pf_mech:server:restoreVehicleState', function(netId)
    local src = source
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) or restoredVehicles[veh] then return end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= veh and #(GetEntityCoords(ped) - GetEntityCoords(veh)) > RESTORE_REACH then return end
    local plate = cleanPlate(GetVehicleNumberPlateText(veh))
    if plate == '' or #plate > 8 then return end
    restoredVehicles[veh] = true
    local st = Entity(veh).state
    local row = MySQL.single.await('SELECT * FROM vehicle_diagnostics WHERE plate = ? LIMIT 1', { plate })
    if row then
        st:set('partDamage', rowToPartDamage(row), true)
        st:set('mileage', tonumber(row.mileage) or 0, true)
    end
    local saved = MySQL.single.await('SELECT mods FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    local mods = saved and type(saved.mods) == 'string' and json.decode(saved.mods) or nil
    local nos = type(mods) == 'table' and type(mods.nos) == 'table' and mods.nos or nil
    if nos and nos.has then
        local cap = (Config.NOS and Config.NOS.capacity) or 100
        st:set('nos', {
            has = true,
            level = math.max(0, math.min(cap, tonumber(nos.level) or 0)),
            color = type(nos.color) == 'string' and nos.color:sub(1, 16) or ((Config.NOS and Config.NOS.defaultColor) or '#55CCFF'),
            style = 1, cooldownAt = 0, levelSel = 1, lastBoostEnd = 0,
        }, true)
    end
end)

AddEventHandler('entityRemoved', function(entity)
    restoredVehicles[entity] = nil
end)

-- Callback: Load vehicle state
QBCore.Functions.CreateCallback('pf_mech:loadVehicleState', function(source, cb, plate)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then cb(nil); return end
    
    -- Load diagnostics
    local diagRow = MySQL.single.await('SELECT * FROM vehicle_diagnostics WHERE plate = ? LIMIT 1', { plate })
    
    local data = {}
    
    if diagRow then
        data.partDamage = {
            alternator = tonumber(diagRow.alternator) or 0,
            sparkplugs = tonumber(diagRow.sparkplugs) or 0,
            carbattery = tonumber(diagRow.carbattery) or 0,
            oil = tonumber(diagRow.oil) or 0,
            oil_filter = tonumber(diagRow.oil_filter) or 0,
            brakes = tonumber(diagRow.brakes) or 0,
            suspension = tonumber(diagRow.suspension) or 0,
            axle = tonumber(diagRow.axle) or 0,
            fuel_injector = tonumber(diagRow.fuel_injector) or 0,
            powersteeringpump = tonumber(diagRow.powersteeringpump) or 0,
            radiator = tonumber(diagRow.radiator) or 0,
            power_steering_fluid = tonumber(diagRow.power_steering_fluid) or 0,
            transmissionfluid = tonumber(diagRow.transmissionfluid) or 0,
            brakefluid = tonumber(diagRow.brakefluid) or 0,
            coolant = tonumber(diagRow.coolant) or 0,
            engine_part = tonumber(diagRow.engine_part) or 0,
            body_part = tonumber(diagRow.body_part) or 0,
        }
        data.mileage = tonumber(diagRow.mileage) or 0
        data.engineHealth = tonumber(diagRow.engineHealth) or 1000.0
        data.bodyHealth = tonumber(diagRow.bodyHealth) or 1000.0
        data.tankHealth = tonumber(diagRow.tankHealth) or 1000.0
        data.dirtLevel = tonumber(diagRow.dirtLevel) or 0.0
    end
    
    cb(data)
end)

-- Cache vehicle state (every 10s from client)
RegisterNetEvent('pf_mech:sync:cacheVehicleState', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local plate = cleanPlate(payload.plate)
    if not mayWrite(src, plate) then return end
    if payload.props ~= nil and not propsOk(payload.props) then return end
    
    vehicleStateCache[plate] = {
        props = payload.props or {},  -- Full vehicle properties from GetVehicleProperties
        lastUpdate = os.time()
    }
    
    if Config.Debug then
        local pd = (payload.props or {}).partDamage or {}
        print(string.format('[GARAGE SYNC] Cached: %s (oil: %.1f%%)', plate, tonumber(pd.oil) or 0))
    end
end)

-- Force save (manual /savedamage command) - ONLY REGISTER IF DEBUG
if Config.Debug then
    RegisterNetEvent('pf_mech:sync:forceSave', function(plate)
        local src = source
        plate = cleanPlate(plate)
        if not mayWrite(src, plate) then return end
        
        local cached = vehicleStateCache[plate]
        if not cached then
            if Config.Debug then print('[GARAGE SYNC] No cached state for '..plate..', checking for live vehicle...') end
            
            -- NEW: If no cache, try to get live vehicle data from client
            TriggerClientEvent('pf_mech:client:requestLiveState', src, plate)
            return
        end
        
        local citizenid = getCitizenIdFromPlate(plate)
        if not citizenid then
            if Config.Debug then print('[GARAGE SYNC] No citizenid for '..plate) end
            return
        end
        
        local props = cached.props or {}
        local pd = props.partDamage or {}
        
        -- Save diagnostics
        upsertDiagnostics(
            plate, citizenid, pd,
            props.mileage or 0,
            props.engineHealth or 1000.0,
            props.bodyHealth or 1000.0,
            props.tankHealth or 1000.0,
            props.dirtLevel or 0.0
        )
        
        -- Save full props to player_vehicles.mods
        MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ?', { json.encode(props), plate })
        
        if Config.Debug then
            print(string.format('[GARAGE SYNC] Force saved: %s (oil: %.1f%%, brakes: %.1f%%)', 
                plate,
                tonumber(pd.oil) or 0,
                tonumber(pd.brakes) or 0
            ))
        end
    end)
else
    -- Production: Force save still works but no debug output
    RegisterNetEvent('pf_mech:sync:forceSave', function(plate)
        local src = source
        plate = cleanPlate(plate)
        if not mayWrite(src, plate) then return end
        
        local cached = vehicleStateCache[plate]
        if not cached then return end
        
        local citizenid = getCitizenIdFromPlate(plate)
        if not citizenid then return end
        
        local props = cached.props or {}
        local pd = props.partDamage or {}
        
        upsertDiagnostics(
            plate, citizenid, pd,
            props.mileage or 0,
            props.engineHealth or 1000.0,
            props.bodyHealth or 1000.0,
            props.tankHealth or 1000.0,
            props.dirtLevel or 0.0
        )
        
        MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ?', { json.encode(props), plate })
    end)
end

-- Hook into qb-garages vehicle storage
RegisterNetEvent('qb-garages:server:updateVehicleStats', function(plate, fuel, engineHealth, bodyHealth)
    local src = source
    plate = cleanPlate(plate)
    if not mayWrite(src, plate) then return end
    
    local cached = vehicleStateCache[plate]
    if not cached then
        if Config.Debug then print('[GARAGE SYNC][QB] No cached state on store: '..plate) end
        return
    end
    
    local citizenid = getCitizenIdFromPlate(plate)
    if not citizenid then return end
    
    local props = cached.props or {}
    local pd = props.partDamage or {}
    
    upsertDiagnostics(
        plate, citizenid, pd,
        props.mileage or 0,
        props.engineHealth or math.max(0, math.min(1000, tonumber(engineHealth) or 1000.0)),
        props.bodyHealth or math.max(0, math.min(1000, tonumber(bodyHealth) or 1000.0)),
        props.tankHealth or 1000.0,
        props.dirtLevel or 0.0
    )
    
    MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ?', { json.encode(props), plate })
    
    if Config.Debug then
        print(string.format('[GARAGE SYNC][QB] Saved on store: %s', plate))
    end
    
    vehicleStateCache[plate] = nil
end)

-- Direct save handler (called from qb-garages deposit)
RegisterNetEvent('pf_mech:saveFullDiagnostics', function(plate, props)
    local src = source
    plate = cleanPlate(plate)
    if not propsOk(props) or not mayWrite(src, plate) then return end
    
    local citizenid = getCitizenIdFromPlate(plate)
    if not citizenid then return end
    
    local pd = props.partDamage or {}
    
    -- Save diagnostics
    upsertDiagnostics(
        plate, citizenid, pd,
        props.mileage or 0,
        props.engineHealth or 1000.0,
        props.bodyHealth or 1000.0,
        props.tankHealth or 1000.0,
        props.dirtLevel or 0.0
    )
    
    -- Save full props
    MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ?', { json.encode(props), plate })
    
    if Config.Debug then
        print(string.format('[DIAG SAVE] %s (eng: %.0f body: %.0f oil: %.1f)', 
            plate, 
            tonumber(props.engineHealth) or 0,
            tonumber(props.bodyHealth) or 0,
            tonumber(pd.oil) or 0
        ))
    end
end)

-- Debug command (ONLY REGISTER IF DEBUG)
if Config.Debug then
    QBCore.Commands.Add('diagrow', 'Show diagnostics DB row', {{name='plate', help='Plate'}}, false, function(src, args)
        local plate = tostring(args[1] or ''):gsub('%s+',''):upper()
        if plate == '' then TriggerClientEvent('QBCore:Notify', src, 'Plate required', 'error'); return end
        local row = MySQL.single.await('SELECT * FROM vehicle_diagnostics WHERE plate=?',{plate})
        if row then
            print('[DIAG ROW] '..plate..' -> '..json.encode(row))
            TriggerClientEvent('QBCore:Notify', src, 'Row printed to server console', 'success')
        else
            TriggerClientEvent('QBCore:Notify', src, 'No row', 'error')
        end
    end)
end

-- Cleanup stale cache
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        local now = os.time()
        for plate, cache in pairs(vehicleStateCache) do
            if (now - cache.lastUpdate) > 600 then
                vehicleStateCache[plate] = nil
                if Config.Debug then print('[GARAGE SYNC] Cleaned stale: '..plate) end
            end
        end
    end
end)
