-- Server-side integration with pf-mechanicjob and pf-policemdt
local QBCore = exports['pfm-core']:GetCoreObject()

-- Configuration
local Config = {
    Debug = false,
    MechanicJobResource = 'pf-mechanicjob',
    MDTResource = 'pf-policemdt-DEV',
}

-- ============================================================================
-- VEHICLE DATA RETRIEVAL
-- ============================================================================

-- Get comprehensive vehicle data for a single vehicle
local function GetVehicleDataByPlate(plate)
    if not plate then return nil end
    
    plate = plate:gsub('%s+', ''):upper()
    
    -- Get base vehicle data
    local vehicle = MySQL.single.await([[
        SELECT * FROM player_vehicles 
        WHERE plate = ? LIMIT 1
    ]], { plate })
    
    if not vehicle then return nil end
    
    -- Get diagnostic data from mechanic job
    local diagnostics = MySQL.single.await([[
        SELECT * FROM vehicle_diagnostics 
        WHERE plate = ? LIMIT 1
    ]], { plate })
    
    -- Get repair history
    local repairHistory = MySQL.query.await([[
        SELECT * FROM pf_job_history 
        WHERE plate = ? 
        ORDER BY created_at DESC 
        LIMIT 50
    ]], { plate })
    
    -- Get service log
    local serviceLog = MySQL.query.await([[
        SELECT * FROM pf_service_log 
        WHERE plate = ? 
        ORDER BY created_at DESC 
        LIMIT 50
    ]], { plate })
    
    -- Get MDT incidents involving this vehicle
    local incidents = nil
    if GetResourceState(Config.MDTResource) == 'started' then
        incidents = MySQL.query.await([[
            SELECT incidentId, title, priority, status, dateTime, location, narrative
            FROM pf_mdt_incidents 
            WHERE involvedVehicleIds LIKE ? 
            ORDER BY dateTime DESC 
            LIMIT 25
        ]], { '%' .. plate .. '%' })
    end
    
    -- Build comprehensive data object
    local data = {
        -- Base vehicle info
        id = vehicle.id,
        owner = vehicle.citizenid or vehicle.owner,
        plate = vehicle.plate,
        vehicle = vehicle.vehicle,
        model = vehicle.vehicle,
        category = vehicle.type or 'Car',
        garage = vehicle.garage,
        state = vehicle.state,
        
        -- Title/Salvage status (you may need to add this column)
        titleStatus = 'clean', -- Default, can be enhanced
        
        -- Location
        location = vehicle.garage or 'Unknown',
        
        -- Stats from diagnostics
        mileage = diagnostics and diagnostics.mileage or vehicle.mileage or 0,
        fuel = diagnostics and diagnostics.tankHealth or 100,
        engine = diagnostics and diagnostics.engineHealth or 1000,
        body = diagnostics and diagnostics.bodyHealth or 1000,
        cleanliness = diagnostics and (100 - (diagnostics.dirtLevel or 0)) or 100,
        
        -- Convert to percentage for UI
        fuelPercent = math.floor(((diagnostics and diagnostics.tankHealth or 100) / 100) * 100),
        enginePercent = math.floor(((diagnostics and diagnostics.engineHealth or 1000) / 1000) * 100),
        bodyPercent = math.floor(((diagnostics and diagnostics.bodyHealth or 1000) / 1000) * 100),
        
        -- Insurance & Police Heat
        insurance = 'Basic', -- Can be enhanced with actual data
        policeHeat = (incidents and #incidents > 5) and 'high' or 
                     (incidents and #incidents > 2) and 'medium' or 
                     (incidents and #incidents > 0) and 'low' or 'none',
        
        -- Organization
        favorite = vehicle.is_favorite or false,
        folderId = vehicle.folder_id or nil,
        isJobVehicle = vehicle.is_job_vehicle or false,
        
        -- Timestamps
        purchaseDate = vehicle.purchase_date or vehicle.created_at,
        lastUsed = vehicle.last_used or vehicle.updated_at,
        
        -- NOS/Upgrades
        hasNOS = vehicle.hasnitrom == 1 or false,
        nosLevel = vehicle.noslevel or 0,
        nosColor = vehicle.noscolor or nil,
        
        -- Detailed part damage from diagnostics
        damage = diagnostics and {
            panels = {
                { name = 'Engine', severity = GetDamageSeverity(diagnostics.engine_part) },
                { name = 'Body', severity = GetDamageSeverity(diagnostics.body_part) },
            },
            parts = {
                alternator = diagnostics.alternator or 0,
                sparkplugs = diagnostics.sparkplugs or 0,
                carbattery = diagnostics.carbattery or 0,
                oil = diagnostics.oil or 0,
                oil_filter = diagnostics.oil_filter or 0,
                brakes = diagnostics.brakes or 0,
                suspension = diagnostics.suspension or 0,
                axle = diagnostics.axle or 0,
                fuel_injector = diagnostics.fuel_injector or 0,
                powersteeringpump = diagnostics.powersteeringpump or 0,
                radiator = diagnostics.radiator or 0,
                power_steering_fluid = diagnostics.power_steering_fluid or 0,
                transmissionfluid = diagnostics.transmissionfluid or 0,
                brakefluid = diagnostics.brakefluid or 0,
                coolant = diagnostics.coolant or 0,
            },
            lights = {}, -- Can be enhanced
            windows = {}, -- Can be enhanced
            tires = {'good', 'good', 'good', 'good'} -- Can be enhanced
        } or nil,
        
        -- History timeline
        history = {}
    }
    
    -- Build timeline from multiple sources
    local timeline = {}
    
    -- Add purchase event
    if vehicle.created_at then
        table.insert(timeline, {
            type = 'purchase',
            date = vehicle.created_at,
            title = 'Vehicle Purchased',
            description = 'Vehicle registered to owner'
        })
    end
    
    -- Add repair history from mechanic job
    if repairHistory then
        for _, repair in ipairs(repairHistory) do
            table.insert(timeline, {
                type = 'repair',
                date = repair.created_at,
                title = repair.type and ('Repair: ' .. repair.type) or 'Vehicle Repair',
                description = string.format('Quality: %d%% | Payout: $%d', repair.quality or 0, repair.payout or 0)
            })
        end
    end
    
    -- Add service log entries
    if serviceLog then
        for _, service in ipairs(serviceLog) do
            table.insert(timeline, {
                type = 'service',
                date = service.created_at,
                title = 'Service Entry',
                description = service.note or 'Service performed',
                author = service.author
            })
        end
    end
    
    -- Add MDT incidents
    if incidents then
        for _, incident in ipairs(incidents) do
            table.insert(timeline, {
                type = 'crime',
                date = incident.dateTime or incident.createdAt,
                title = incident.title or 'Police Incident',
                description = string.format('%s | Priority: %s | Location: %s', 
                    incident.status or 'Unknown',
                    incident.priority or 'Unknown',
                    incident.location or 'Unknown'
                ),
                incidentId = incident.incidentId
            })
        end
    end
    
    -- Sort timeline by date (most recent first)
    table.sort(timeline, function(a, b)
        return (a.date or '') > (b.date or '')
    end)
    
    data.history = timeline
    
    return data
end

-- Helper function to get damage severity
function GetDamageSeverity(damage)
    if not damage then return 'none' end
    damage = tonumber(damage) or 0
    
    if damage >= 75 then return 'severe'
    elseif damage >= 50 then return 'moderate'
    elseif damage >= 25 then return 'minor'
    else return 'none'
    end
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

-- Get single vehicle data
QBCore.Functions.CreateCallback('pf-garage:getVehicleData', function(source, cb, plate)
    local data = GetVehicleDataByPlate(plate)
    cb(data)
end)

-- Get all player vehicles
QBCore.Functions.CreateCallback('pf-garage:getAllVehicles', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(nil) return end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Get all vehicles owned by player
    local vehicles = MySQL.query.await([[
        SELECT plate FROM player_vehicles 
        WHERE citizenid = ? OR owner = ?
    ]], { citizenid, citizenid })
    
    if not vehicles or #vehicles == 0 then
        cb({})
        return
    end
    
    -- Get full data for each vehicle
    local allVehicleData = {}
    for _, veh in ipairs(vehicles) do
        local data = GetVehicleDataByPlate(veh.plate)
        if data then
            table.insert(allVehicleData, data)
        end
    end
    
    cb(allVehicleData)
end)

-- Check if vehicle can be spawned
QBCore.Functions.CreateCallback('pf-garage:canSpawnVehicle', function(source, cb, plate)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end
    
    local vehicle = MySQL.single.await([[
        SELECT * FROM player_vehicles 
        WHERE plate = ? AND (citizenid = ? OR owner = ?)
        LIMIT 1
    ]], { plate, Player.PlayerData.citizenid, Player.PlayerData.citizenid })
    
    if not vehicle then
        cb(false, nil)
        return
    end
    
    -- Check if vehicle is in garage (state = 1 or 'in')
    local canSpawn = vehicle.state == 1 or vehicle.state == 'in'
    
    cb(canSpawn, vehicle)
end)

-- ============================================================================
-- FOLDER MANAGEMENT
-- ============================================================================

RegisterNetEvent('pf-garage:createFolder', function(name, icon)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    MySQL.insert.await([[
        INSERT INTO vehicle_folders (owner, folder_name, folder_icon)
        VALUES (?, ?, ?)
    ]], { Player.PlayerData.citizenid, name, icon or 'folder' })
    
    if Config.Debug then
        print(string.format('[GARAGE] Created folder "%s" for %s', name, Player.PlayerData.citizenid))
    end
end)

RegisterNetEvent('pf-garage:addVehicleToFolder', function(vehicleId, folderId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    MySQL.update.await([[
        UPDATE player_vehicles 
        SET folder_id = ? 
        WHERE id = ? AND (citizenid = ? OR owner = ?)
    ]], { folderId, vehicleId, Player.PlayerData.citizenid, Player.PlayerData.citizenid })
end)

RegisterNetEvent('pf-garage:removeVehicleFromFolder', function(vehicleId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    MySQL.update.await([[
        UPDATE player_vehicles 
        SET folder_id = NULL 
        WHERE id = ? AND (citizenid = ? OR owner = ?)
    ]], { vehicleId, Player.PlayerData.citizenid, Player.PlayerData.citizenid })
end)

-- ============================================================================
-- FAVORITES
-- ============================================================================

RegisterNetEvent('pf-garage:toggleFavorite', function(plate)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Toggle favorite status
    MySQL.query.await([[
        UPDATE player_vehicles 
        SET is_favorite = NOT is_favorite 
        WHERE plate = ? AND (citizenid = ? OR owner = ?)
    ]], { plate, Player.PlayerData.citizenid, Player.PlayerData.citizenid })
    
    -- Get updated status and notify client
    local vehicle = GetVehicleDataByPlate(plate)
    if vehicle then
        TriggerClientEvent('pf-garage:client:updateVehicle', src, plate, vehicle)
    end
end)

-- ============================================================================
-- VEHICLE STATE SYNC
-- ============================================================================

RegisterNetEvent('pf-garage:syncVehicleState', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local plate = data.plate
    if not plate then return end
    
    -- Update vehicle state in player_vehicles
    MySQL.update.await([[
        UPDATE player_vehicles 
        SET 
            last_used = NOW(),
            mileage = ?
        WHERE plate = ? AND (citizenid = ? OR owner = ?)
    ]], { 
        data.mileage or 0,
        plate,
        Player.PlayerData.citizenid,
        Player.PlayerData.citizenid
    })
    
    -- Update diagnostics if mechanic job is enabled
    if GetResourceState(Config.MechanicJobResource) == 'started' and data.partDamage then
        local pd = data.partDamage
        
        MySQL.insert.await([[
            INSERT INTO vehicle_diagnostics (
                plate, citizenid, mileage, engineHealth, bodyHealth, tankHealth, dirtLevel,
                oil, brakes, suspension, engine_part, body_part
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                mileage = VALUES(mileage),
                engineHealth = VALUES(engineHealth),
                bodyHealth = VALUES(bodyHealth),
                tankHealth = VALUES(tankHealth),
                dirtLevel = VALUES(dirtLevel),
                oil = VALUES(oil),
                brakes = VALUES(brakes),
                suspension = VALUES(suspension),
                engine_part = VALUES(engine_part),
                body_part = VALUES(body_part)
        ]], {
            plate,
            Player.PlayerData.citizenid,
            data.mileage or 0,
            data.engineHealth or 1000,
            data.bodyHealth or 1000,
            data.tankHealth or 1000,
            data.dirtLevel or 0,
            pd.oil or 0,
            pd.brakes or 0,
            pd.suspension or 0,
            pd.engine_part or 0,
            pd.body_part or 0
        })
    end
    
    if Config.Debug then
        print(string.format('[GARAGE SYNC] Updated %s: mileage=%.1f, engine=%.1f%%', 
            plate, data.mileage or 0, (data.engineHealth or 1000) / 10))
    end
end)

-- ============================================================================
-- EXPORTS FOR OTHER RESOURCES
-- ============================================================================

-- Export: Get vehicle data by plate (for other scripts)
exports('GetVehicleData', GetVehicleDataByPlate)

-- Export: Get all vehicles for a player
exports('GetPlayerVehicles', function(citizenid)
    local vehicles = MySQL.query.await([[
        SELECT plate FROM player_vehicles 
        WHERE citizenid = ? OR owner = ?
    ]], { citizenid, citizenid })
    
    if not vehicles then return {} end
    
    local allVehicleData = {}
    for _, veh in ipairs(vehicles) do
        local data = GetVehicleDataByPlate(veh.plate)
        if data then
            table.insert(allVehicleData, data)
        end
    end
    
    return allVehicleData
end)

-- Export: Update vehicle damage from external source
exports('UpdateVehicleDamage', function(plate, damageData)
    if not plate or not damageData then return false end
    
    -- This allows other scripts (like mechanic job) to update damage
    MySQL.insert.await([[
        INSERT INTO vehicle_diagnostics (plate, engineHealth, bodyHealth, tankHealth, dirtLevel)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            engineHealth = VALUES(engineHealth),
            bodyHealth = VALUES(bodyHealth),
            tankHealth = VALUES(tankHealth),
            dirtLevel = VALUES(dirtLevel)
    ]], {
        plate,
        damageData.engineHealth or 1000,
        damageData.bodyHealth or 1000,
        damageData.tankHealth or 1000,
        damageData.dirtLevel or 0
    })
    
    return true
end)

-- Export: Add history event to vehicle timeline
exports('AddVehicleHistoryEvent', function(plate, eventData)
    if not plate or not eventData then return false end
    
    -- Add to service log (which feeds into timeline)
    MySQL.insert.await([[
        INSERT INTO pf_service_log (plate, citizenid, author, note)
        VALUES (?, ?, ?, ?)
    ]], {
        plate,
        eventData.citizenid or 'SYSTEM',
        eventData.author or 'System',
        eventData.description or 'Event logged'
    })
    
    return true
end)

if Config.Debug then
    print('[PF-GARAGE] Integration server script loaded')
end
