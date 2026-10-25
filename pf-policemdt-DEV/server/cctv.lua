-- ============================================================================
-- CCTV System - Server Side
-- ============================================================================

local function cctvDebugEnabled()
    return Config and Config.Debug == true and Config.CCTV and Config.CCTV.Debug == true
end

local function cctvLog(msg)
    if not cctvDebugEnabled() then return end
    print(msg)
end

local function cctvLogf(fmt, ...)
    if not cctvDebugEnabled() then return end
    print((fmt):format(...))
end

local QBCore = PFMdt.GetCore()

-- CCTV camera registry in memory
local CCTVRegistry = {}
local CCTVRecordings = {}

-- ============================================================================
-- Helpers
-- ============================================================================

local function hasCCTVEnabled()
    return Config and Config.CCTV and Config.CCTV.Enabled == true
end

local function shouldPersistDiscoveredCameras()
    return Config and Config.CCTV and Config.CCTV.PersistDiscoveredToDb ~= false
end

local function roundCoord(val, decimals)
    decimals = decimals or 2
    return math.floor(val * (10 ^ decimals)) / (10 ^ decimals)
end

local function generateCameraKey(modelHash, x, y, z)
    return modelHash .. ":" .. roundCoord(x, 2) .. ":" .. roundCoord(y, 2) .. ":" .. roundCoord(z, 2)
end

local function findCameraById(cameraId)
    local want = tonumber(cameraId)
    if not want then
        return nil
    end
    for _, cam in ipairs(CCTVRegistry) do
        if tonumber(cam.id) == want then
            return cam
        end
    end
    return nil
end

local function ensureStaticCamerasSeeded()
    if not Config or not Config.CCTVStaticCameras or type(Config.CCTVStaticCameras) ~= 'table' then
        return
    end

    local seeded = 0
    for _, entry in ipairs(Config.CCTVStaticCameras) do
        if entry and entry.x and entry.y and entry.z then
            local modelHash = entry.model_hash
            local modelName = entry.model_name

            if not modelHash and entry.model and type(entry.model) == 'string' then
                modelHash = joaat(entry.model)
                modelName = modelName or entry.model
            end

            if modelHash then
                local heading = tonumber(entry.heading) or 0.0
                local cameraKey = entry.camera_key or generateCameraKey(modelHash, entry.x, entry.y, entry.z)
                if not findCameraByKey(cameraKey) then
                    local cam = {
                        camera_key = cameraKey,
                        model_hash = modelHash,
                        model_name = modelName or 'CCTV Camera',
                        x = tonumber(entry.x) or 0.0,
                        y = tonumber(entry.y) or 0.0,
                        z = tonumber(entry.z) or 0.0,
                        heading = heading,
                        location_label = entry.label or entry.location_label or 'Static Camera',
                        status = entry.status or 'ONLINE'
                    }
                    table.insert(CCTVRegistry, cam)
                    saveCameraToDb(cam.model_hash, cam.x, cam.y, cam.z, cam.heading, cam.location_label)
                    seeded = seeded + 1
                end
            end
        end
    end

    if seeded > 0 then
        cctvLogf('[MDT CCTV] Seeded %d static cameras from config', seeded)
    end
end

-- ============================================================================
-- Database Functions
-- ============================================================================

local function loadCamerasFromDb()
    if not (exports.oxmysql) then return {} end
    
    local result = {}
    local success = false
    exports.oxmysql:execute('SELECT id, model_hash, x, y, z, heading, location_label, status, created_at FROM pf_mdt_cctv_cameras ORDER BY created_at DESC', {}, function(rows)
        if rows and #rows > 0 then
            cctvLogf('[MDT CCTV] loadCamerasFromDb: Loaded %d cameras from database', #rows)
            for i, row in ipairs(rows) do
                table.insert(result, {
                    id = row.id,
                    model_hash = row.model_hash,
                    x = row.x,
                    y = row.y,
                    z = row.z,
                    heading = row.heading,
                    location_label = row.location_label,
                    status = row.status,
                    created_at = row.created_at
                })
            end
        end
        success = true
    end)
    
    local waited = 0
    while not success and waited < 5000 do 
        Wait(10)
        waited = waited + 10
    end
    
    if waited >= 5000 then
        cctvLog('[MDT CCTV] ERROR: loadCamerasFromDb timed out after 5 seconds!')
    end
    
    return result
end

local function saveCameraToDb(modelHash, x, y, z, heading, label)
    if not exports.oxmysql then return false end
    
    -- Just insert the camera (will handle duplicates with INSERT IGNORE)
    exports.oxmysql:execute(
        'INSERT IGNORE INTO pf_mdt_cctv_cameras (model_hash, x, y, z, heading, location_label, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { modelHash, x, y, z, heading, label, 'ONLINE' }
    )
    
    return true
end

local function updateCameraStatus(cameraId, status)
    if not exports.oxmysql then return false end
    
    local updated = false
    exports.oxmysql:execute(
        'UPDATE pf_mdt_cctv_cameras SET status = ?, updated_at = NOW() WHERE id = ?',
        { status, cameraId },
        function()
            updated = true
        end
    )
    
    while not updated do Wait(10) end
    
    -- Update in-memory registry
    for _, camera in ipairs(CCTVRegistry) do
        if camera.id == cameraId then
            camera.status = status
            break
        end
    end
    
    -- Broadcast to all clients
    TriggerClientEvent('pf_mdt:cctv:updateStatus', -1, { id = cameraId, status = status })
    
    return true
end

-- ============================================================================
-- Server Events & Callbacks
-- ============================================================================

RegisterNetEvent('pf_mdt:cctv:registerDiscoveredCamera', function(modelHash, x, y, z, heading, label)
    local src = source
    if not hasCCTVEnabled() then 
        return 
    end

    if not shouldPersistDiscoveredCameras() then
        return
    end
    
    local player = QBCore.Functions.GetPlayer(src)
    if not player or not Config.AllowedJobs[player.PlayerData.job.name] then
        return
    end

    -- a camera prop of an allowed model, near the officer who saw it
    modelHash, x, y, z, heading = tonumber(modelHash), tonumber(x), tonumber(y), tonumber(z), tonumber(heading) or 0.0
    if not modelHash or not x or not y or not z then return end
    local knownModel = false
    for _, h in ipairs(Config.CCTVModels or {}) do
        if h == modelHash then knownModel = true break end
    end
    if not knownModel or not PFMdtAccess.NearCaller(src, { x = x, y = y, z = z }) then return end
    label = PFMdtAccess.Text(label, 128)
    
    -- Check for duplicate by proximity (0.5 unit radius)
    local isDuplicate = false
    for _, cam in ipairs(CCTVRegistry) do
        local dx, dy, dz = cam.x - x, cam.y - y, cam.z - z
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist < 0.5 then
            isDuplicate = true
            break
        end
    end
    
    if not isDuplicate then
        -- Insert into database
        local cameraKey = generateCameraKey(modelHash, x, y, z)
        exports.oxmysql:insert(
            'INSERT INTO pf_mdt_cctv_cameras (camera_key, model_hash, x, y, z, heading, location_label, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { cameraKey, modelHash, x, y, z, heading, label, 'ONLINE' },
            function(id)
                if id and id > 0 then
                    -- Add to in-memory registry
                    local newCamera = {
                        id = id,
                        model_hash = modelHash,
                        x = x,
                        y = y,
                        z = z,
                        heading = heading,
                        location_label = label,
                        status = 'ONLINE',
                        created_at = os.date('%Y-%m-%d %H:%M:%S')
                    }
                    table.insert(CCTVRegistry, newCamera)
                else
                    cctvLog('[MDT CCTV] ERROR: Failed to insert camera (insert returned: ' .. tostring(id) .. ')')
                end
            end)
    end
end)

RegisterNetEvent('pf_mdt:cctv:setCameraOffline', function(data)
    if not hasCCTVEnabled() then return end
    if type(data) ~= 'table' or not tonumber(data.id) then return end
    updateCameraStatus(tonumber(data.id), 'OFFLINE')
end)

QBCore.Functions.CreateCallback('pf_mdt:cctv:getCameraList', function(source, cb)
    local src = source
    if not hasCCTVEnabled() then
        cb({})
        return
    end
    
    local player = QBCore.Functions.GetPlayer(src)
    if not player or not Config.AllowedJobs[player.PlayerData.job.name] then
        cb({})
        return
    end
    cb(CCTVRegistry)
end)

QBCore.Functions.CreateCallback('pf_mdt:cctv:getCameraById', function(source, cb, cameraId)
    local src = source
    if not hasCCTVEnabled() then
        cb(nil)
        return
    end

    local player = QBCore.Functions.GetPlayer(src)
    if not player or not Config.AllowedJobs[player.PlayerData.job.name] then
        cb(nil)
        return
    end

    cameraId = tonumber(cameraId)
    if not cameraId then
        cb(nil)
        return
    end

    local cam = findCameraById(cameraId)
    cb(cam)
end)

QBCore.Functions.CreateCallback('pf_mdt:cctv:getCameraRecordings', function(source, cb, cameraKey)
    local src = source
    if not hasCCTVEnabled() then
        cb({})
        return
    end
    
    local player = QBCore.Functions.GetPlayer(src)
    if not player or not Config.AllowedJobs[player.PlayerData.job.name] then
        cb({})
        return
    end
    
    local recordings = CCTVRecordings[cameraKey] or {}
    cb(recordings)
end)

-- ============================================================================
-- Initialization
-- ============================================================================

CreateThread(function()
    if not hasCCTVEnabled() then 
        return 
    end

    Wait(1000)
    
    -- Reset all cameras to ONLINE on startup (they may have been marked OFFLINE if destroyed)
    if exports.oxmysql then
        exports.oxmysql:execute('UPDATE pf_mdt_cctv_cameras SET status = ?, updated_at = NOW() WHERE 1=1', { 'ONLINE' }, function() end)
    end
    
    CCTVRegistry = loadCamerasFromDb()
    cctvLog('[MDT CCTV] Server initialized. Loaded ' .. #CCTVRegistry .. ' cameras from database')
end)

-- ============================================================================
-- Export Camera Registry (for data dump)
-- ============================================================================

-- Export function: returns all cameras in a format ready for config paste
exports('getCCTVCameras', function()
    return CCTVRegistry
end)

-- Command to dump camera coords to console (debug-only)
if Config and Config.Debug == true and Config.CCTV and Config.CCTV.DumpCommandEnabled == true then
RegisterCommand('dumpcctvs', function(source, args, rawCommand)
    
    if source == 0 then
        -- Server console - allow
        print('^2[MDT CCTV DUMP]^7 Exporting ' .. #CCTVRegistry .. ' cameras...')
        print(json.encode(CCTVRegistry, { indent = true }))
        return
    end
    
    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        return
    end
    
    if not Config.AllowedJobs[player.PlayerData.job.name] then
        TriggerClientEvent('QBCore:Notify', source, 'You must be on duty as police', 'error')
        return
    end

    local output = {}
    for _, cam in ipairs(CCTVRegistry) do
        table.insert(output, {
            model = cam.model_name,
            model_hash = cam.model_hash,
            x = cam.x,
            y = cam.y,
            z = cam.z,
            heading = cam.heading,
            label = cam.location_label
        })
    end

    -- Write to server console
    print('^2[MDT CCTV DUMP]^7 Exporting ' .. #output .. ' cameras...')
    print(json.encode(output, { indent = true }))

    TriggerClientEvent('QBCore:Notify', source, 'Exported ' .. #output .. ' cameras to server console. Check server logs.', 'success')
end, false)
end
