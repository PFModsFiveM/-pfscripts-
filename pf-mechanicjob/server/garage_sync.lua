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
    local plate = tostring(payload.plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
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
        plate = tostring(plate or ''):gsub('%s+', ''):upper()
        if plate == '' then return end
        
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
        plate = tostring(plate or ''):gsub('%s+', ''):upper()
        if plate == '' then return end
        
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
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
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
        props.engineHealth or engineHealth or 1000.0,
        props.bodyHealth or bodyHealth or 1000.0,
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
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' or type(props) ~= 'table' then return end
    
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
