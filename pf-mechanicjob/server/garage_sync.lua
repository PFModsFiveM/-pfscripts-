-- This file is compatible with both qb-garages and cd_garages (codesign).
-- It listens for vehicle state sync events from the client, regardless of garage system.
--
-- partDamage, mileage and NOS are vehicle state bags only the server writes (sv_stateBagStrictMode).
-- They are saved to vehicle_diagnostics from the server's own state of the car the sender is in or
-- beside, and loaded back onto a spawned car from there. What a client sends (props.partDamage,
-- props.mileage, props.nos) and player_vehicles.mods (which the owner's client can write) never
-- become wear, mileage or NOS: a forged save used to hand the next spawn free NOS, new parts and a
-- lower odometer.

local QBCore = exports['pfm-core']:GetCoreObject()
PFMech = PFMech or {}

-- [plate] = { props (without wear, mileage and NOS), netId of the car, lastUpdate }
local vehicleStateCache = {}
local lastDiagWrite = {}      -- [plate] = os.time() of the last save from the driving sync

local SAVE_REACH = 10.0       -- metres: saving a car from beside it, just after getting out
local RESTORE_REACH = 50.0
local TAKEOUT_REACH = 60.0    -- metres: the car a garage just spawned for the player
local DIAG_WRITE_INTERVAL = 30
local NOS_CAP = (Config.NOS and Config.NOS.capacity) or 100
local NOS_COLOR = (Config.NOS and Config.NOS.defaultColor) or '#55CCFF'

local PART_COLUMNS = {
    'alternator', 'sparkplugs', 'carbattery', 'oil', 'oil_filter', 'brakes', 'suspension', 'axle',
    'fuel_injector', 'powersteeringpump', 'radiator', 'power_steering_fluid', 'transmissionfluid',
    'brakefluid', 'coolant', 'engine_part', 'body_part',
}

-- ============================================================================
-- Schema: NOS is kept by the server in vehicle_diagnostics (it used to be read from mods)
-- ============================================================================
local MIGRATION_KEY = 'pf-mechanicjob:garage_sync'
local Migrations = {
    {
        version = 1,
        name = 'NOS saved by the server in vehicle_diagnostics',
        up = {
            -- same table as pf_mechanic.sql, so this does not depend on the SQL auto-import running first
            [[CREATE TABLE IF NOT EXISTS `vehicle_diagnostics` (
                `plate` varchar(50) NOT NULL,
                `citizenid` varchar(50) DEFAULT NULL,
                `alternator` float DEFAULT 0, `sparkplugs` float DEFAULT 0, `carbattery` float DEFAULT 0,
                `oil` float DEFAULT 0, `oil_filter` float DEFAULT 0, `brakes` float DEFAULT 0,
                `suspension` float DEFAULT 0, `axle` float DEFAULT 0, `fuel_injector` float DEFAULT 0,
                `powersteeringpump` float DEFAULT 0, `radiator` float DEFAULT 0, `power_steering_fluid` float DEFAULT 0,
                `transmissionfluid` float DEFAULT 0, `brakefluid` float DEFAULT 0, `coolant` float DEFAULT 0,
                `engine_part` float DEFAULT 0, `body_part` float DEFAULT 0,
                `mileage` double DEFAULT 0, `engineHealth` float DEFAULT 1000, `bodyHealth` float DEFAULT 1000,
                `tankHealth` float DEFAULT 1000, `dirtLevel` float DEFAULT 0,
                PRIMARY KEY (`plate`),
                KEY `citizenid_idx` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            [[ALTER TABLE `vehicle_diagnostics`
                ADD COLUMN IF NOT EXISTS `nos_has` TINYINT(1) NOT NULL DEFAULT 0,
                ADD COLUMN IF NOT EXISTS `nos_level` FLOAT NOT NULL DEFAULT 0,
                ADD COLUMN IF NOT EXISTS `nos_color` VARCHAR(16) NULL]],
        },
    },
}
local schemaReady = false

function PFMech.GarageSyncSchema()
    local ok, res, err = pcall(function()
        if type(RunMigrations) == 'function' then return RunMigrations(MIGRATION_KEY, Migrations) end
        return exports['pfm-core']:RunMigrations(MIGRATION_KEY, Migrations)
    end)
    schemaReady = ok and res == true
    if not schemaReady then
        print('^1[pf-mechanicjob]^7 NOS columns not ready, NOS is not saved: ' .. tostring(ok and err or res))
    end
    return schemaReady
end

CreateThread(function() PFMech.GarageSyncSchema() end)

-- ============================================================================
-- Helpers
-- ============================================================================

local function getCitizenIdFromPlate(plate)
    local row = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    return row and row.citizenid or nil
end

local function cleanPlate(plate)
    return (tostring(plate or ''):gsub('%s+', ''):upper())
end

local function number(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return default end
    return math.max(lo, math.min(hi, v))
end

local function wear(v) return math.floor(number(v, 0, 100, 0) * 100 + 0.5) / 100 end

local function nosColor(c)
    if type(c) == 'string' and #c <= 16 and c:match('^#?%w+$') then return c end
    return nil
end

-- model hashes as unsigned numbers (natives can return them signed); a float modulus keeps it
-- exact on 32-bit integer builds too
local function u32(n)
    n = tonumber(n)
    return n and (math.floor(n) % 4294967296.0) or nil
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

-- The car with this plate that the sender is in, or stands beside (by its net id). Found on the
-- server, so a save is about a real car and not just a plate.
local function resolveCar(src, plate, netId)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local inside = GetVehiclePedIsIn(ped, false)
    if inside and inside ~= 0 and DoesEntityExist(inside) and cleanPlate(GetVehicleNumberPlateText(inside)) == plate then
        return inside
    end
    netId = tonumber(netId)
    if not netId or netId <= 0 or netId ~= math.floor(netId) then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if cleanPlate(GetVehicleNumberPlateText(veh)) ~= plate then return nil end
    if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > SAVE_REACH then return nil end
    return veh
end

-- The car with this plate the sender sits in, or the nearest one around them.
local function findNear(src, plate, reach)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local inside = GetVehiclePedIsIn(ped, false)
    if inside and inside ~= 0 and DoesEntityExist(inside) and cleanPlate(GetVehicleNumberPlateText(inside)) == plate then
        return inside
    end
    if type(GetAllVehicles) ~= 'function' then return nil end
    local here, best, bestDist = GetEntityCoords(ped), nil, reach
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) and cleanPlate(GetVehicleNumberPlateText(veh)) == plate then
            local d = #(here - GetEntityCoords(veh))
            if d <= bestDist then best, bestDist = veh, d end
        end
    end
    return best
end

-- ============================================================================
-- Loading a car's saved state (once per car)
-- ============================================================================
-- [vehicle] = { [plate] = true once that plate's saved state is on it, false when refused }
local restoredVehicles = {}
-- [plate] = the live car carrying that plate's saved state (a copy with the plate gets nothing)
local restoredPlates = {}
-- [vehicle] = the one plate whose saved state this car carries: changing the plate text later does
-- not let the same car load (or save over) another car's wear and NOS
local carIdentity = {}
local loading = {}   -- [vehicle] = true while its saved state is being read

-- Loads the plate's saved state onto the car, merged so nothing goes back: wear only up, mileage
-- never down, and NOS only onto a car without NOS. A player's car must be the model they own.
-- Returns true when the car carries this plate's saved state, so it may be saved under it.
local function restore(veh, plate)
    -- a second first touch (a repair while the driver's report loads the car) waits for the load,
    -- so the load cannot land after the repair and undo it
    local waited = 0
    while loading[veh] and waited < 100 do
        Wait(50)
        waited = waited + 1
    end
    local seen = restoredVehicles[veh]
    if seen and seen[plate] ~= nil then return seen[plate] end
    if carIdentity[veh] and carIdentity[veh] ~= plate then return false end
    local holder = restoredPlates[plate]
    if holder and holder ~= veh and DoesEntityExist(holder) then return false end

    -- the plate is claimed before the read, so two cars with the same plate restoring at the same
    -- moment cannot both get its saved state
    restoredPlates[plate] = veh
    local function release() if restoredPlates[plate] == veh then restoredPlates[plate] = nil end end
    loading[veh] = true
    local ok, owned, row = pcall(function()
        local o = MySQL.single.await('SELECT vehicle FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
        if not o then return nil, nil end
        return o, MySQL.single.await('SELECT * FROM vehicle_diagnostics WHERE plate = ? LIMIT 1', { plate })
    end)
    loading[veh] = nil
    -- not marked on a failed read: nothing is saved over the stored state until it was read
    if not ok then release() return false end

    seen = seen or {}
    restoredVehicles[veh] = seen
    if owned and type(owned.vehicle) == 'string' and owned.vehicle ~= ''
        and u32(GetEntityModel(veh)) ~= u32(GetHashKey(owned.vehicle)) then
        release()
        seen[plate] = false
        return false
    end
    seen[plate] = true
    carIdentity[veh] = plate
    if not owned then release() return true end
    if type(row) ~= 'table' then return true end

    local st = Entity(veh).state
    local current = type(st.partDamage) == 'table' and st.partDamage or {}
    local pd = {}
    for k, v in pairs(current) do pd[k] = v end
    for _, col in ipairs(PART_COLUMNS) do pd[col] = math.max(wear(row[col]), wear(current[col])) end
    st:set('partDamage', pd, true)
    st:set('mileage', math.max(number(row.mileage, 0, 1e9, 0), number(st.mileage, 0, 1e9, 0)), true)

    local hasNos = row.nos_has == true or tonumber(row.nos_has) == 1
    local nos = st.nos
    if hasNos and not (type(nos) == 'table' and nos.has) then
        st:set('nos', {
            has = true,
            level = number(row.nos_level, 0, NOS_CAP, 0),
            color = nosColor(row.nos_color) or NOS_COLOR,
            style = 1, cooldownAt = 0, levelSel = 1, lastBoostEnd = 0,
        }, true)
    end
    return true
end

--- Makes sure a car carries its saved state before the server changes it (used by the wear, repair,
--- mileage and NOS handlers), so a repair or report on a fresh spawn is not undone by a later load.
function PFMech.EnsureVehicleRestored(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local plate = cleanPlate(GetVehicleNumberPlateText(veh))
    if plate == '' or #plate > 8 then return false end
    return restore(veh, plate)
end

-- A spawned car asks for its saved state; only a player in or near it can ask.
RegisterNetEvent('pf_mech:server:restoreVehicleState', function(netId)
    local src = source
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= veh and #(GetEntityCoords(ped) - GetEntityCoords(veh)) > RESTORE_REACH then return end
    PFMech.EnsureVehicleRestored(veh)
end)

-- pfm-garages reports a car it just took out; the garage never asked for the saved state, so it is
-- loaded here, onto the car with that plate in or next to the player.
local TakeOutAt = {}
RegisterNetEvent('qb-garages:server:updateVehicleState', function(state, plate)
    local src = source
    if tonumber(state) ~= 0 or type(plate) ~= 'string' then return end
    plate = cleanPlate(plate)
    if plate == '' or #plate > 8 then return end
    local now = os.time()
    if TakeOutAt[src] and now - TakeOutAt[src] < 2 then return end
    TakeOutAt[src] = now
    local veh = findNear(src, plate, TAKEOUT_REACH)
    if veh then restore(veh, plate) end
end)

AddEventHandler('playerDropped', function() TakeOutAt[source] = nil end)

AddEventHandler('entityRemoved', function(entity)
    local seen = restoredVehicles[entity]
    if not seen then return end
    for plate in pairs(seen) do
        if restoredPlates[plate] == entity then restoredPlates[plate] = nil end
    end
    restoredVehicles[entity], carIdentity[entity] = nil, nil
end)

-- ============================================================================
-- Saving
-- ============================================================================

-- The car's own server state: what is stored as wear, mileage and NOS.
local function serverState(veh)
    local st = Entity(veh).state
    local pd = type(st.partDamage) == 'table' and st.partDamage or {}
    local out = {}
    for _, col in ipairs(PART_COLUMNS) do out[col] = wear(pd[col]) end
    local nos = type(st.nos) == 'table' and st.nos.has == true and st.nos or nil
    return {
        partDamage = out,
        mileage = number(st.mileage, 0, 1e9, 0),
        nosHas = nos and 1 or 0,
        nosLevel = nos and number(nos.level, 0, NOS_CAP, 0) or 0,
        nosColor = nos and nosColor(nos.color) or '',
    }
end

-- Engine, body and tank health and dirt are game values the client reports (as pfm-garages does).
local function healthFrom(props, engine, body)
    props = type(props) == 'table' and props or {}
    return {
        engine = number(engine or props.engineHealth, -4000, 1000, 1000.0),
        body = number(body or props.bodyHealth, 0, 1000, 1000.0),
        tank = number(props.tankHealth, -1000, 1000, 1000.0),
        dirt = number(props.dirtLevel, 0, 15, 0.0),
    }
end

local function writeDiagnostics(plate, citizenid, snap, health)
    local cols, params = { 'plate', 'citizenid' }, { plate, citizenid }
    local function add(col, value) cols[#cols + 1] = col; params[#params + 1] = value end
    for _, col in ipairs(PART_COLUMNS) do add(col, snap.partDamage[col]) end
    add('mileage', snap.mileage)
    add('engineHealth', health.engine)
    add('bodyHealth', health.body)
    add('tankHealth', health.tank)
    add('dirtLevel', health.dirt)
    if schemaReady then
        add('nos_has', snap.nosHas)
        add('nos_level', snap.nosLevel)
        add('nos_color', snap.nosColor)
    end
    local marks, updates = {}, {}
    for i, col in ipairs(cols) do
        marks[i] = '?'
        if i > 1 then updates[#updates + 1] = ('`%s`=VALUES(`%s`)'):format(col, col) end
    end
    MySQL.insert.await(('INSERT INTO vehicle_diagnostics (`%s`) VALUES (%s) ON DUPLICATE KEY UPDATE %s'):format(
        table.concat(cols, '`,`'), table.concat(marks, ','), table.concat(updates, ',')), params)
    if Config.Debug then
        print(string.format('[DIAG SAVE] plate=%s brakes=%.1f mileage=%.1f nos=%d', plate, snap.partDamage.brakes, snap.mileage, snap.nosHas))
    end
end

-- Stores the car's server state. Only a spawned car that carries this plate's saved state (loaded
-- now if it was not yet), so a fresh spawn never overwrites the stored wear. No car, no write.
local function saveDiagnostics(plate, owner, veh, health)
    if not veh or not restore(veh, plate) then return false end
    writeDiagnostics(plate, owner, serverState(veh), health)
    return true
end

-- player_vehicles.mods keeps the car's props without the state only the server sets.
local SERVER_KEYS = { partDamage = true, mileage = true, nos = true }
local function modsFrom(props)
    local out = {}
    for k, v in pairs(props) do
        if not SERVER_KEYS[k] then out[k] = v end
    end
    return out
end

local function saveMods(plate, props)
    if type(props) ~= 'table' then return end
    MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ?', { json.encode(modsFrom(props)), plate })
end

-- Callback: Load vehicle state
QBCore.Functions.CreateCallback('pf_mech:loadVehicleState', function(source, cb, plate)
    plate = cleanPlate(plate)
    if plate == '' then cb(nil); return end

    local diagRow = MySQL.single.await('SELECT * FROM vehicle_diagnostics WHERE plate = ? LIMIT 1', { plate })
    local data = {}
    if diagRow then
        data.partDamage = {}
        for _, col in ipairs(PART_COLUMNS) do data.partDamage[col] = tonumber(diagRow[col]) or 0 end
        data.mileage = tonumber(diagRow.mileage) or 0
        data.engineHealth = tonumber(diagRow.engineHealth) or 1000.0
        data.bodyHealth = tonumber(diagRow.bodyHealth) or 1000.0
        data.tankHealth = tonumber(diagRow.tankHealth) or 1000.0
        data.dirtLevel = tonumber(diagRow.dirtLevel) or 0.0
    end
    cb(data)
end)

-- Driving sync (every 10 s from the driver): keeps the props for the garage store and saves the
-- car's server state now and then, so wear also survives a car that is lost without being stored.
RegisterNetEvent('pf_mech:sync:cacheVehicleState', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local plate = cleanPlate(payload.plate)
    if payload.props ~= nil and not propsOk(payload.props) then return end
    local owner = mayWrite(src, plate)
    if not owner then return end
    local veh = resolveCar(src, plate, payload.netId)
    if not veh then return end

    local now = os.time()
    vehicleStateCache[plate] = {
        props = payload.props and modsFrom(payload.props) or nil,
        netId = NetworkGetNetworkIdFromEntity(veh),
        lastUpdate = now,
    }
    if not lastDiagWrite[plate] or now - lastDiagWrite[plate] >= DIAG_WRITE_INTERVAL then
        if saveDiagnostics(plate, owner, veh, healthFrom(payload.props)) then lastDiagWrite[plate] = now end
    end
end)

-- Save on demand (cd_garages: the client noticed the car was left or stored).
RegisterNetEvent('pf_mech:sync:forceSave', function(plate, netId)
    local src = source
    plate = cleanPlate(plate)
    local owner = mayWrite(src, plate)
    if not owner then return end
    local cached = vehicleStateCache[plate]
    local veh = resolveCar(src, plate, netId or (cached and cached.netId))
    if not veh and not cached then
        -- debug: ask the client for the car (it answers with the net id, so this is asked once)
        if Config.Debug and netId == nil then TriggerClientEvent('pf_mech:client:requestLiveState', src, plate) end
        return
    end
    saveDiagnostics(plate, owner, veh, healthFrom(cached and cached.props))
    if cached then saveMods(plate, cached.props) end
end)

-- Hook into qb-garages vehicle storage (the player is still in or at the car).
RegisterNetEvent('qb-garages:server:updateVehicleStats', function(plate, fuel, engineHealth, bodyHealth)
    local src = source
    plate = cleanPlate(plate)
    local owner = mayWrite(src, plate)
    if not owner then return end
    local cached = vehicleStateCache[plate]
    local veh = resolveCar(src, plate, cached and cached.netId)
    if not veh and not cached then
        if Config.Debug then print('[GARAGE SYNC][QB] No car or cached state on store: ' .. plate) end
        return
    end
    saveDiagnostics(plate, owner, veh, healthFrom(cached and cached.props, engineHealth, bodyHealth))
    if cached then saveMods(plate, cached.props) end
    vehicleStateCache[plate] = nil
    lastDiagWrite[plate] = nil
end)

-- Direct save (the SyncVehicleDiagnostics export, called by garages on deposit).
RegisterNetEvent('pf_mech:saveFullDiagnostics', function(plate, props, netId)
    local src = source
    plate = cleanPlate(plate)
    if not propsOk(props) then return end
    local owner = mayWrite(src, plate)
    if not owner then return end
    saveDiagnostics(plate, owner, resolveCar(src, plate, netId), healthFrom(props))
    saveMods(plate, props)
end)

-- Debug command (ONLY REGISTER IF DEBUG)
if Config.Debug then
    QBCore.Commands.Add('diagrow', 'Show diagnostics DB row', {{name='plate', help='Plate'}}, false, function(src, args)
        local plate = cleanPlate(args[1])
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
                lastDiagWrite[plate] = nil
                if Config.Debug then print('[GARAGE SYNC] Cleaned stale: '..plate) end
            end
        end
    end
end)
