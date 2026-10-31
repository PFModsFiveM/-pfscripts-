-- Server → app push channel. An app's server code sends events to the app instance running in
-- whichever shell the player has open; the runtime routes them to the module's ctx.on(event).
--
--   exports['pf-devices']:Push(src, 'taxi', 'callsData', calls)
--   exports['pf-devices']:PushToJob('police', 'policemdt', 'newCall', call, true)   -- on duty only
--   exports['pf-devices']:Broadcast('news', 'published', { id = 12 })

PFDevices = PFDevices or {}

local function players()
    local QBCore = exports['pfm-core']:GetCoreObject()
    return QBCore.Functions.GetQBPlayers()
end

function PFDevices.Push(src, appId, event, payload)
    if type(appId) ~= 'string' or type(event) ~= 'string' then return false end
    src = tonumber(src)
    if not src then return false end
    TriggerClientEvent('pf-devices:client:appEvent', src, appId, event, payload)
    return true
end

function PFDevices.PushToCitizen(citizenid, appId, event, payload)
    local QBCore = exports['pfm-core']:GetCoreObject()
    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if not Player then return false end
    return PFDevices.Push(Player.PlayerData.source, appId, event, payload)
end

function PFDevices.PushToJob(job, appId, event, payload, ondutyOnly)
    if type(job) ~= 'string' then return 0 end
    local n = 0
    for src, Player in pairs(players()) do
        local j = Player.PlayerData and Player.PlayerData.job
        if j and j.name == job and (not ondutyOnly or j.onduty) then
            if PFDevices.Push(Player.PlayerData.source or src, appId, event, payload) then n = n + 1 end
        end
    end
    return n
end

function PFDevices.Broadcast(appId, event, payload)
    if type(appId) ~= 'string' or type(event) ~= 'string' then return false end
    TriggerClientEvent('pf-devices:client:appEvent', -1, appId, event, payload)
    return true
end

--- Tells shells to re-fetch their app list (a job change, an install, a resource start).
--- Broadcasts are coalesced: at server start dozens of apps register within a second, and every
--- open device would re-fetch for each one. The first change goes out at once, later ones within
--- the next second become one trailing broadcast.
local lastBroadcast, trailingQueued = -10000, false
function PFDevices.NotifyAppsChanged(target)
    target = tonumber(target) or -1
    if target ~= -1 then
        TriggerClientEvent('pf-devices:client:appsChanged', target)
        return
    end
    local now = GetGameTimer()
    if now - lastBroadcast >= 1000 then
        lastBroadcast = now
        TriggerClientEvent('pf-devices:client:appsChanged', -1)
        return
    end
    if trailingQueued then return end
    trailingQueued = true
    SetTimeout(1000, function()
        trailingQueued = false
        lastBroadcast = GetGameTimer()
        TriggerClientEvent('pf-devices:client:appsChanged', -1)
    end)
end

function PFDevices.__resetPush()
    lastBroadcast, trailingQueued = -10000, false
end
