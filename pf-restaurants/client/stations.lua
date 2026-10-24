-- Client-side station management and visual cooking

local activeSessions = {}
local stationProps = {}

-- Sync station sessions from server
RegisterNetEvent('pf-restaurants:client:syncStations', function(stations)
    -- Sync active sessions
    if Config.Debug then
        print('[pf-restaurants] Syncing stations')
    end
end)

-- Session started
RegisterNetEvent('pf-restaurants:client:stationSessionStart', function(businessId, stationId, slotId, session)
    local sessionId = session.sessionId
    activeSessions[sessionId] = session
    
    -- Spawn visual prop
    SpawnStationProp(businessId, stationId, slotId, session)
end)

-- Session ended
RegisterNetEvent('pf-restaurants:client:stationSessionEnd', function(businessId, stationId, slotId, sessionId)
    if activeSessions[sessionId] then
        activeSessions[sessionId] = nil
    end
    
    -- Remove prop
    RemoveStationProp(sessionId)
end)

-- Spawn prop on station
function SpawnStationProp(businessId, stationId, slotId, session)
    local stationConfig = nil
    
    -- Find station config
    for _, station in ipairs(Config.Stations[businessId] or {}) do
        if station.stationId == stationId then
            stationConfig = station
            break
        end
    end
    
    if not stationConfig then return end
    
    local propModel = stationConfig.propModel
    local propOffset = stationConfig.propOffsets[slotId]
    
    if not propModel or not propOffset then return end
    
    local propCoords = stationConfig.coords + vector3(propOffset.x, propOffset.y, propOffset.z)
    
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do
        Wait(10)
    end
    
    local prop = CreateObject(GetHashKey(propModel), propCoords.x, propCoords.y, propCoords.z, false, false, false)
    SetEntityHeading(prop, stationConfig.heading)
    FreezeEntityPosition(prop, true)
    
    stationProps[session.sessionId] = {
        prop = prop,
        coords = propCoords,
        stationId = stationId,
        slotId = slotId
    }
end

-- Remove prop from station
function RemoveStationProp(sessionId)
    if stationProps[sessionId] then
        if DoesEntityExist(stationProps[sessionId].prop) then
            DeleteObject(stationProps[sessionId].prop)
        end
        stationProps[sessionId] = nil
    end
end

-- Render 3D progress bars and timers
CreateThread(function()
    while true do
        local sleep = 500
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for sessionId, propData in pairs(stationProps) do
            local session = activeSessions[sessionId]
            if session then
                local distance = #(playerCoords - propData.coords)
                
                if distance <= Config.Timings.RenderDistance then
                    sleep = 0
                    
                    -- Calculate progress
                    local elapsed = (GetGameTimer() - (session.startTime * 1000))
                    local progress = elapsed / session.duration
                    
                    -- Determine status
                    local status = 'Cooking'
                    local color = {r = 255, g = 255, b = 255}
                    
                    if session.requiresDoneness then
                        if progress < Config.Quality.Undercooked.max then
                            status = 'Raw'
                            color = {r = 255, g = 100, b = 100}
                        elseif progress >= Config.Quality.Rare.min and progress <= Config.Quality.Rare.max then
                            status = 'Rare Window'
                            color = {r = 255, g = 200, b = 100}
                        elseif progress >= Config.Quality.MediumRare.min and progress <= Config.Quality.MediumRare.max then
                            status = 'Medium-Rare Window'
                            color = {r = 255, g = 220, b = 100}
                        elseif progress >= Config.Quality.Medium.min and progress <= Config.Quality.Medium.max then
                            status = 'Medium Window'
                            color = {r = 100, g = 255, b = 100}
                        elseif progress >= Config.Quality.WellDone.min and progress <= Config.Quality.WellDone.max then
                            status = 'Well-Done Window'
                            color = {r = 255, g = 180, b = 100}
                        elseif progress > Config.Quality.WellDone.max and progress < Config.Quality.Burnt.min then
                            status = 'Overcooking!'
                            color = {r = 255, g = 100, b = 0}
                        elseif progress >= Config.Quality.Burnt.min then
                            status = 'BURNING!'
                            color = {r = 255, g = 0, b = 0}
                        end
                    else
                        if progress > 1.2 then
                            status = 'BURNING!'
                            color = {r = 255, g = 0, b = 0}
                        elseif progress > 1.0 then
                            status = 'Ready'
                            color = {r = 100, g = 255, b = 100}
                        end
                    end
                    
                    -- Draw 3D timer
                    local timerCoords = propData.coords + vector3(0.0, 0.0, 0.3)
                    local timeRemaining = math.max(0, session.duration - elapsed)
                    local timeText = string.format('%ds - %s', math.floor(timeRemaining / 1000), status)
                    
                    Draw3DText(timerCoords, timeText)
                    
                    -- Draw progress bar (simple version)
                    local barCoords = propData.coords + vector3(0.0, 0.0, 0.4)
                    local progressPercent = math.min(100, math.floor(progress * 100))
                    Draw3DText(barCoords, string.format('[%d%%]', progressPercent))
                end
            end
        end
        
        Wait(sleep)
    end
end)

-- Start station action (player initiated)
function StartStationAction(businessId, stationId, slotId, action, inputItems, donenessTarget)
    TriggerServerEvent('pf-restaurants:server:startStationAction', businessId, stationId, slotId, {
        action = action,
        inputItems = inputItems,
        donenessTarget = donenessTarget or 'medium'
    })
end

-- Complete station action (remove item)
function CompleteStationAction(sessionId)
    TriggerServerEvent('pf-restaurants:server:completeStationAction', sessionId)
end

-- Export functions
exports('StartStationAction', StartStationAction)
exports('CompleteStationAction', CompleteStationAction)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for sessionId, propData in pairs(stationProps) do
            if DoesEntityExist(propData.prop) then
                DeleteObject(propData.prop)
            end
        end
    end
end)
