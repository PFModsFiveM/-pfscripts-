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

-- The server keeps cooking time in epoch seconds (startTime) and sends its clock (serverNow) with
-- every session. GetGameTimer counts from this client's start, so the start is placed on that clock
-- once: localStart = now - (serverNow - startTime). (Progress used to compare GetGameTimer with
-- startTime * 1000, so it was always far below zero and the doneness windows never showed.)
function PlaceOnLocalClock(session, now)
    local started = tonumber(session.startTime) or 0
    local serverNow = tonumber(session.serverNow) or started
    session.localStart = (now or GetGameTimer()) - math.max(0, serverNow - started) * 1000
    return session.localStart
end

--- Share of the cooking time done (1.0 = the dish's time), as the server will judge it.
function CookProgress(session, now)
    local elapsed = (now or GetGameTimer()) - (session.localStart or now or GetGameTimer())
    return elapsed / math.max(1, tonumber(session.duration) or 1), elapsed
end

--- The label and colour over a dish: its doneness window (Config.Quality, the same windows the
--- server judges by) or, for a dish without one, cooking / ready / burning.
function CookStatus(session, progress)
    local Q = Config.Quality
    if session.requiresDoneness then
        if progress < Q.Undercooked.max then
            return 'Raw', { r = 255, g = 100, b = 100 }
        elseif progress >= Q.Rare.min and progress <= Q.Rare.max then
            return 'Rare Window', { r = 255, g = 200, b = 100 }
        elseif progress >= Q.MediumRare.min and progress <= Q.MediumRare.max then
            return 'Medium-Rare Window', { r = 255, g = 220, b = 100 }
        elseif progress >= Q.Medium.min and progress <= Q.Medium.max then
            return 'Medium Window', { r = 100, g = 255, b = 100 }
        elseif progress >= Q.WellDone.min and progress <= Q.WellDone.max then
            return 'Well-Done Window', { r = 255, g = 180, b = 100 }
        elseif progress > Q.WellDone.max and progress < Q.Burnt.min then
            return 'Overcooking!', { r = 255, g = 100, b = 0 }
        end
        return 'BURNING!', { r = 255, g = 0, b = 0 }
    end
    if progress > 1.2 then
        return 'BURNING!', { r = 255, g = 0, b = 0 }
    elseif progress > 1.0 then
        return 'Ready', { r = 100, g = 255, b = 100 }
    end
    return 'Cooking', { r = 255, g = 255, b = 255 }
end

local function addSession(businessId, stationId, slotId, session)
    if type(session) ~= 'table' or type(session.sessionId) ~= 'string' then return end
    if activeSessions[session.sessionId] then return end
    PlaceOnLocalClock(session)
    activeSessions[session.sessionId] = session
    SpawnStationProp(businessId, stationId, slotId, session)
end

-- Session started
RegisterNetEvent('pf-restaurants:client:stationSessionStart', function(businessId, stationId, slotId, session)
    addSession(businessId, stationId, slotId, session)
end)

-- Session ended
RegisterNetEvent('pf-restaurants:client:stationSessionEnd', function(businessId, stationId, slotId, sessionId)
    if activeSessions[sessionId] then
        activeSessions[sessionId] = nil
    end
    
    -- Remove prop
    RemoveStationProp(sessionId)
end)

-- Started working here: show what is already cooking. Stopped: the server no longer sends this
-- kitchen's timers, so take its props down instead of leaving stale ones.
AddEventHandler('pf-restaurants:client:staffChanged', function(businessId, working)
    if working then
        QBCore.Functions.TriggerCallback('pf-restaurants:server:getStationSessions', function(sessions)
            for _, session in pairs(type(sessions) == 'table' and sessions or {}) do
                if type(session) == 'table' and session.businessId == businessId then
                    addSession(businessId, session.stationId, session.slotId, session)
                end
            end
        end, businessId)
        return
    end
    for sessionId, session in pairs(activeSessions) do
        if session.businessId == businessId then
            activeSessions[sessionId] = nil
            RemoveStationProp(sessionId)
        end
    end
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
                    
                    -- Calculate progress (ms on this client's clock, see PlaceOnLocalClock)
                    local progress, elapsed = CookProgress(session)
                    
                    local status, color = CookStatus(session, progress)

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

-- Start station action (player initiated). slotId 0 or nil: the server takes the first free slot.
function StartStationAction(businessId, stationId, slotId, action, inputItems, donenessTarget)
    TriggerServerEvent('pf-restaurants:server:startStationAction', businessId, stationId, slotId or 0, {
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
