-- ============================================================================
-- CCTV System - Client Side (Discovery & Viewer)
-- ============================================================================

local QBCore = PFMdt.GetCore()

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end
local discoveredCameras = {}
local viewingCamera = nil
local scriptCam = nil
local damageFeedActive = false
local focusActive = false
local viewingCameraThread = nil
local mdtHiddenForViewer = false

-- POV offsets so the camera doesn't clip into the prop
local lensForwardOffset = 0.15
local lensUpOffset = -0.02

-- Viewer controls state
local viewerYaw = 0.0
local viewerPitch = -15.0
local viewerFov = 60.0
local viewerDistance = 25.0 -- legacy (was used for orbit cam); kept for backward compatibility

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function isScreenshotBasicAvailable()
    local state = GetResourceState('screenshot-basic')
    return state and tostring(state):find('start') ~= nil
end

local function buildDataUri(img)
    if type(img) ~= 'string' then return nil end
    if img:sub(1, 10) == 'data:image' then return img end
    return 'data:image/jpeg;base64,' .. img
end

local function requestScreenshotBase64(timeoutMs)
    timeoutMs = timeoutMs or 2000
    if not isScreenshotBasicAvailable() then return nil end

    local done = false
    local result = nil

    local ok = pcall(function()
        exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = 0.40 }, function(data)
            result = data
            done = true
        end)
    end)

    if not ok then
        -- Fallback to older screenshot-basic signature
        pcall(function()
            exports['screenshot-basic']:requestScreenshot(function(data)
                result = data
                done = true
            end)
        end)
    end

    local startedAt = GetGameTimer()
    while not done and (GetGameTimer() - startedAt) < timeoutMs do
        Wait(0)
    end

    return result
end

local function computePreviewPOV(cam)
    local x = tonumber(cam.x) or 0.0
    local y = tonumber(cam.y) or 0.0
    local z = tonumber(cam.z) or 0.0
    local heading = tonumber(cam.heading) or 0.0
    -- Flip heading by 180° so preview faces the expected direction
    heading = (heading + 180.0) % 360.0
    local yawRad = math.rad(heading)
    local cx = x + (math.cos(yawRad) * lensForwardOffset)
    local cy = y + (math.sin(yawRad) * lensForwardOffset)
    local cz = z + lensUpOffset

    return cx, cy, cz, 0.0, 0.0, heading
end

local function enqueuePreviewRequest(cam)
    if not cam or not cam.id then return end
    local id = tonumber(cam.id)
    if not id or id <= 0 then return end
    if previewCache[id] then
        SendNUIMessage({ action = 'cctvPreview', id = id, image = previewCache[id] })
        return
    end
    previewQueue[#previewQueue + 1] = cam
end

local function updateViewerCameraTransform()
    if not (viewingCamera and scriptCam) then return end

    -- True CCTV POV: the camera view originates at the CCTV unit,
    -- and uses the CCTV heading/rotation (not an orbit cam pointed at the unit).
    local baseX = viewingCamera.x
    local baseY = viewingCamera.y
    local baseZ = viewingCamera.z

    local baseYaw = tonumber(viewingCamera.heading) or 0.0
    local basePitch = 0.0
    local baseRoll = 0.0

    -- If the object entity is streamed, prefer its actual rotation and an offset
    -- slightly in front of the lens to avoid clipping into the prop.
    if viewingCamera.object and DoesEntityExist(viewingCamera.object) then
        local obj = viewingCamera.object
        local rot = GetEntityRotation(obj, 2)
        if rot then
            basePitch = rot.x or 0.0
            baseRoll = rot.y or 0.0
            baseYaw = rot.z or baseYaw
            
            -- Detect upside-down cameras (pitch around 180/-180) and flip them
            if basePitch > 90.0 or basePitch < -90.0 then
                basePitch = -basePitch
                baseYaw = (baseYaw + 180.0) % 360.0
                baseRoll = -baseRoll
            end
        end
        local off = GetOffsetFromEntityInWorldCoords(obj, 0.0, lensForwardOffset, lensUpOffset)
        if off then
            baseX, baseY, baseZ = off.x, off.y, off.z
        end
    else
        -- No entity streamed: approximate a lens offset using heading.
        local yawRad = math.rad(baseYaw)
        baseX = baseX + (math.cos(yawRad) * lensForwardOffset)
        baseY = baseY + (math.sin(yawRad) * lensForwardOffset)
        baseZ = baseZ + lensUpOffset
    end

    SetCamCoord(scriptCam, baseX, baseY, baseZ)

    -- Apply user look controls as absolute yaw/pitch values (initialized from base).
    -- Note: SetCamRot expects degrees.
    SetCamRot(scriptCam, viewerPitch, baseRoll, viewerYaw, 2)
    SetCamFov(scriptCam, viewerFov)
end

local function setCameraFocus(x, y, z)
    -- Stream the world around the camera so it renders even if the player is far away.
    -- This is the key to "view from anywhere".
    focusActive = true
    RequestCollisionAtCoord(x, y, z)
    SetFocusArea(x, y, z, 0.0, 0.0, 0.0)
    -- Larger than default to help thumbnails render with higher LOD.
    SetHdArea(x, y, z, 200.0)
    NewLoadSceneStart(x, y, z, 0.0, 0.0, 0.0, 250.0, 0)

    local startedAt = GetGameTimer()
    while focusActive and (GetGameTimer() - startedAt) < 5000 do
        if IsNewLoadSceneLoaded() then break end
        Wait(0)
    end
end

local function clearCameraFocus()
    focusActive = false
    ClearFocus()
    ClearHdArea()
end

local function dist2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return (dx * dx) + (dy * dy) + (dz * dz)
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function hasCCTVEnabled()
    return Config and Config.CCTV and Config.CCTV.Enabled == true
end

local function getModelNameFromHash(modelHash)
    -- Map hash back to model name from config
    if Config.CCTVModels then
        for _, hash in ipairs(Config.CCTVModels) do
            if hash == modelHash then
                -- Get the model name from the hash
                local modelName = GetHashKey and ('prop_cctv_cam') or 'CCTV Camera'
                -- Try common camera model names
                local names = {
                    [-1159421424] = 'prop_cctv_cam_01a',
                    [168901740] = 'prop_cctv_cam_02a',
                    [548760764] = 'prop_cctv_cam_03a',
                    [-1340405475] = 'prop_cctv_cam_04a',
                    [-173206916] = 'prop_cctv_cam_05a',
                    [1995527969] = 'prop_cctv_cam_06a',
                    [-1932022395] = 'prop_cctv_cam_07a',
                    [1449155105] = 'prop_sec_camera_01',
                }
                return names[modelHash] or 'CCTV Camera'
            end
        end
    end
    return 'CCTV Camera'
end

local function roundCoord(val, decimals)
    decimals = decimals or 2
    return math.floor(val * (10 ^ decimals)) / (10 ^ decimals)
end

local function generateCameraKey(modelHash, x, y, z)
    return modelHash .. ":" .. roundCoord(x, 2) .. ":" .. roundCoord(y, 2) .. ":" .. roundCoord(z, 2)
end

local function getLocationLabel(coords)
    if not coords then return 'Unknown' end
    
    local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or 'Unknown'
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    
    if zone and zone ~= '' and zone ~= 'NULL' then
        if street and street ~= '' then
            return street .. ', ' .. zone
        else
            return zone
        end
    end
    
    return street or 'Unknown Location'
end

-- ============================================================================
-- Camera Discovery Thread
-- ============================================================================

CreateThread(function()
    if not hasCCTVEnabled() then 
        return 
    end

    if Config and Config.CCTV and Config.CCTV.AutoDiscover == false then
        return
    end
    
    while true do
        Wait(Config.CCTV.DiscoveryInterval or 5000)
        
        if PFMdt and PFMdt.CanAccessMdt then
            if not PFMdt.CanAccessMdt() then
                goto skip_discovery
            end
        else
            if not QBCore.Functions.GetPlayerData().job or not Config.AllowedJobs[QBCore.Functions.GetPlayerData().job.name] then
            goto skip_discovery
            end
        end
        
        local objects = GetGamePool('CObject')
        
        for _, obj in ipairs(objects) do
            if DoesEntityExist(obj) then
                local modelHash = GetEntityModel(obj)
                
                -- Check if model is in CCTV allowlist
                local isCamera = false
                if Config.CCTVModels then
                    for _, allowedHash in ipairs(Config.CCTVModels) do
                        if modelHash == allowedHash then
                            isCamera = true
                            break
                        end
                    end
                end
                
                if isCamera then
                    local coords = GetEntityCoords(obj)
                    local heading = GetEntityHeading(obj)
                    local cameraKey = generateCameraKey(modelHash, coords.x, coords.y, coords.z)
                    
                    -- Only register if new
                    if not discoveredCameras[cameraKey] then
                        discoveredCameras[cameraKey] = {
                            id = nil, -- Will be assigned by server
                            camera_key = cameraKey,
                            model_hash = modelHash,
                            model_name = getModelNameFromHash(modelHash),
                            x = coords.x,
                            y = coords.y,
                            z = coords.z,
                            heading = heading,
                            location_label = getLocationLabel(coords),
                            status = 'ONLINE',
                            object = obj
                        }
                        
                        -- Send to server - pass individual parameters
                        TriggerServerEvent('pf_mdt:cctv:registerDiscoveredCamera', modelHash, coords.x, coords.y, coords.z, heading, getLocationLabel(coords))
                    else
                        -- Update object reference
                        discoveredCameras[cameraKey].object = obj
                    end
                end
            end
        end
        
        ::skip_discovery::
    end
end)

-- ============================================================================
-- Damage Detection Thread
-- ============================================================================

CreateThread(function()
    if not hasCCTVEnabled() then return end
    
    while true do
        Wait(1000)

        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local checkDist = (Config.CCTV and Config.CCTV.DamageCheckDistance) or 75.0
        local maxD2 = checkDist * checkDist
        
        for cameraKey, camera in pairs(discoveredCameras) do
            if camera.object and camera.status == 'ONLINE' then
                -- Only mark OFFLINE if player is close enough that the entity should be streamed.
                local camPos = vector3(camera.x, camera.y, camera.z)
                if dist2({ x = pcoords.x, y = pcoords.y, z = pcoords.z }, { x = camPos.x, y = camPos.y, z = camPos.z }) <= maxD2 then
                    if not DoesEntityExist(camera.object) then
                        camera.status = 'OFFLINE'
                        TriggerServerEvent('pf_mdt:cctv:setCameraOffline', { id = camera.id or 0, reason = 'DESTROYED' })
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- CCTV Viewer
-- ============================================================================

local function openCCTVViewer(camera)
    if camera.status == 'OFFLINE' then
        QBCore.Functions.Notify('Camera is offline', 'error')
        return
    end
    
    viewingCamera = camera

    -- Initialize control defaults
    -- Flip heading by 180° so viewer faces the expected direction
    viewerYaw = ((tonumber(camera.heading) or 0.0) + 180.0) % 360.0
    viewerPitch = 0.0
    viewerFov = 60.0
    viewerDistance = 25.0
    
    -- Ensure the area around the camera is streamed even if the player is far away.
    setCameraFocus(camera.x, camera.y, camera.z)

    -- Prevent any player movement while viewing.
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)

    scriptCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    -- Apply CCTV scanline look
    SetTimecycleModifier('scanline_cam')
    SetTimecycleModifierStrength(1.0)

    -- Position camera POV from the CCTV unit
    updateViewerCameraTransform()
    
    RenderScriptCams(true, false, 0, true, false)
    
    -- Hide HUD and MDT
    DisplayHud(false)
    DisplayRadar(false)

    -- Hide the MDT UI while viewing (keep it loaded so we can restore it)
    mdtHiddenForViewer = true
    SendNUIMessage({ action = 'setMDTVisible', visible = false })
    SendNUIMessage({
        action = 'cctvViewer',
        show = true,
        label = camera.location_label or (camera.id and ('Camera #' .. tostring(camera.id)) or 'Camera')
    })
    SetNuiFocus(false, false)
    
    -- Keep camera focus active while viewing
    viewingCameraThread = CreateThread(function()
        while viewingCamera and focusActive do
            SetFocusArea(viewingCamera.x, viewingCamera.y, viewingCamera.z, 0.0, 0.0, 0.0)
            Wait(250)
        end
    end)
end



local function closeCCTVViewer()
    -- Clear camera state FIRST so the input thread stops on next frame
    viewingCamera = nil
    viewingCameraThread = nil
    
    if scriptCam then
        DestroyCam(scriptCam, false)
        scriptCam = nil
    end
    
    RenderScriptCams(false, false, 0, true, false)
    DisplayHud(true)
    DisplayRadar(true)

    ClearTimecycleModifier()

    clearCameraFocus()

    -- Restore player movement
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)

    -- Restore MDT UI if we hid it for this viewer session
    if mdtHiddenForViewer then
        mdtHiddenForViewer = false
        
        -- Wait one frame to ensure the input thread has exited
        Wait(0)
        
        -- Now restore the MDT UI (this will remove body class and show both tablet and app)
        SendNUIMessage({ action = 'cctvViewer', show = false })
        
        -- Small delay to ensure UI is rendered before restoring focus
        Wait(50)
        
        -- Restore NUI focus so the user can interact with the MDT again
        SetNuiFocus(true, true)
    else
        -- Still ensure overlay is off
        SendNUIMessage({ action = 'cctvViewer', show = false })
    end
end

local function showDamageFeed()
    if not viewingCamera then return end
    
    damageFeedActive = true
    
    -- This would overlay a glitch effect - for now we just notify
    -- In full implementation, would show HTML overlay with static/glitch
    TriggerEvent('chat:addMessage', {
        args = { 'CCTV', 'Camera signal lost!' },
        color = { 255, 0, 0 }
    })
    
    Wait(Config.CCTV.DamageOverlayDuration or 3000)
    
    damageFeedActive = false
    closeCCTVViewer()
end

-- ============================================================================
-- NUI Callbacks
-- ============================================================================

RegisterNUICallback('openCCTVViewer', function(data, cb)
    dprint('[MDT CCTV] NUI callback openCCTVViewer received with data:', json.encode(data))
    local id = data and tonumber(data.id) or nil
    if id and id > 0 then
        local camera = nil
        
        -- Look for camera in discovered cameras by id
        for _, cam in pairs(discoveredCameras) do
            if cam.id and tonumber(cam.id) == id then
                camera = cam
                dprint('[MDT CCTV] Found camera locally: ' .. tostring(id))
                break
            end
        end

        -- If not locally discovered (not streamed), fetch from server and open by coords.
        if not camera then
            dprint('[MDT CCTV] Camera not found locally, fetching from server with id: ' .. tostring(id))
            QBCore.Functions.TriggerCallback('pf_mdt:cctv:getCameraById', function(serverCam)
                dprint('[MDT CCTV] Server callback received:', serverCam and json.encode(serverCam) or 'nil')
                if serverCam then
                    dprint('[MDT CCTV] Opening camera viewer from server data')
                    openCCTVViewer(serverCam)
                    cb({ success = true })
                else
                    dprint('[MDT CCTV] Server returned nil camera')
                    cb({ success = false, error = 'Camera not found' })
                end
            end, id)
            return
        end

        dprint('[MDT CCTV] Opening camera viewer from local data')
        openCCTVViewer(camera)
        cb({ success = true })
    else
        dprint('[MDT CCTV] Invalid camera id in callback data:', json.encode(data))
        cb({ success = false, error = 'Invalid camera id' })
    end
end)

RegisterNUICallback('closeCCTVViewer', function(data, cb)
    closeCCTVViewer()
    cb({ success = true })
end)

-- ============================================================================
-- Keyboard Input
-- ============================================================================

CreateThread(function()
    while true do
        Wait(0)

        if viewingCamera and scriptCam then
            -- Ensure ONLY the CCTV overlay is shown: hide HUD/radar every frame.
            HideHudAndRadarThisFrame()
            DisplayHud(false)
            DisplayRadar(false)
            -- Force NUI to relinquish keyboard focus while the camera is active
            SetNuiFocus(false, false)

            -- Disable all player controls while viewing, then selectively re-enable CCTV controls.
            DisableAllControlActions(0)
            -- Exit controls
            EnableControlAction(0, 177, true) -- Backspace
            EnableControlAction(0, 322, true) -- ESC
            -- CCTV look controls
            EnableControlAction(0, 174, true) -- Left Arrow
            EnableControlAction(0, 175, true) -- Right Arrow
            EnableControlAction(0, 172, true) -- Up Arrow
            EnableControlAction(0, 173, true) -- Down Arrow
            -- Zoom controls (mouse wheel)
            EnableControlAction(0, 241, true) -- Scroll Up
            EnableControlAction(0, 242, true) -- Scroll Down

            -- Rotate left/right with arrow keys
            local dt = GetFrameTime()
            local yawSpeed = 90.0 -- degrees per second
            -- Invert left/right controls: Left pans left, Right pans right
            if IsDisabledControlPressed(0, 175) then -- Right Arrow
                viewerYaw = viewerYaw - (yawSpeed * dt)
            end
            if IsDisabledControlPressed(0, 174) then -- Left Arrow
                viewerYaw = viewerYaw + (yawSpeed * dt)
            end

            -- Optional pitch with Up/Down arrows (kept subtle)
            local pitchSpeed = 60.0
            if IsDisabledControlPressed(0, 172) then -- Up Arrow
                viewerPitch = clamp(viewerPitch + (pitchSpeed * dt), -75.0, 20.0)
            end
            if IsDisabledControlPressed(0, 173) then -- Down Arrow
                viewerPitch = clamp(viewerPitch - (pitchSpeed * dt), -75.0, 20.0)
            end

            -- Zoom with scroll wheel (FOV)
            if IsDisabledControlJustPressed(0, 241) then -- Scroll Up
                viewerFov = clamp(viewerFov - 2.5, 20.0, 80.0)
            end
            if IsDisabledControlJustPressed(0, 242) then -- Scroll Down
                viewerFov = clamp(viewerFov + 2.5, 20.0, 80.0)
            end

            updateViewerCameraTransform()
        end
        
        -- Backspace (177) or ESC (322) to close camera viewer and return to MDT
        if viewingCamera and (IsControlJustReleased(0, 177) or IsControlJustReleased(0, 322)) then
            closeCCTVViewer()
        end
    end
end)

-- ============================================================================
-- Events
-- ============================================================================

RegisterNetEvent('pf_mdt:cctv:updateStatus', function(data)
    for _, cam in pairs(discoveredCameras) do
        if cam.id == data.id then
            cam.status = data.status
            
            -- Show damage feed if we're viewing this camera
            if viewingCamera and viewingCamera.id == data.id and data.status == 'OFFLINE' then
                showDamageFeed()
            end
            break
        end
    end
end)

-- ============================================================================
-- Close viewer on resource stop
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if viewingCamera then
        closeCCTVViewer()
    end
end)
