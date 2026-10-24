local points = {}
local waitingSync = {}
local lastAckToken = nil
local syncCounter = 0
local resourceName = GetCurrentResourceName()

local function trim(value)
    return (value and value:gsub('^%s+', ''):gsub('%s+$', '')) or ''
end

local function hasAccess(src)
    if src == 0 then
        return true
    end

    if Config.RequiredAce and Config.RequiredAce ~= '' and IsPlayerAceAllowed(src, Config.RequiredAce) then
        return true
    end

    local allow = Config.IdentifierAllowlist or {}
    if next(allow) then
        for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
            if allow[identifier] then
                return true
            end
        end
    end

    return false
end

local function writeToDisk()
    local output = {
        exportedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        source = 'pf-mapcal-sync',
        points = points
    }

    local text = json.encode(output)
    if not text then
        return false, 'failed to encode json'
    end

    local file, err = io.open(Config.OutputFilePath, 'w')
    if not file then
        return false, err or 'failed to open output file'
    end

    file:write(text)
    file:close()

    return true, nil
end

local function notify(src, msg)
    if src == 0 then
        print(('[pf-mapcal-sync] %s'):format(msg))
        return
    end
    TriggerClientEvent('chat:addMessage', src, {
        color = { 72, 184, 255 },
        multiline = false,
        args = { 'MapCal', msg }
    })
end

local function safeReadJson(filePath)
    local file = io.open(filePath, 'r')
    if not file then
        return nil
    end

    local text = file:read('*a')
    file:close()

    if not text or text == '' then
        return nil
    end

    local parsed = json.decode(text)
    if type(parsed) ~= 'table' then
        return nil
    end
    return parsed
end

local function safeReadResourceJson(fileName)
    if not fileName or fileName == '' then
        return nil
    end

    local text = LoadResourceFile(resourceName, fileName)
    if not text or text == '' then
        return nil
    end

    local parsed = json.decode(text)
    if type(parsed) ~= 'table' then
        return nil
    end
    return parsed
end

local function tryMirrorToAbsolutePath(filePath, text)
    if not filePath or filePath == '' then
        return true
    end

    local file = io.open(filePath, 'w')
    if not file then
        return false
    end
    file:write(text)
    file:close()
    return true
end

local function writeSyncPending(entry)
    local current = safeReadResourceJson(Config.SyncResourceFile)
        or safeReadJson(Config.SyncFilePath)
        or {}
    current.updatedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
    current.pending = entry
    current.ack = current.ack or nil
    current.history = current.history or {}

    local text = json.encode(current)
    if not text then
        return false, 'failed to encode sync json'
    end

    local wroteResource = SaveResourceFile(resourceName, Config.SyncResourceFile or 'mapcal-sync.json', text, -1)
    if not wroteResource then
        return false, 'failed to write sync resource file'
    end

    -- Best-effort mirror for tools that read from an absolute website path.
    tryMirrorToAbsolutePath(Config.SyncFilePath, text)

    return true, nil
end

local function saveCurrentPosition(src, id)
    local ped = GetPlayerPed(src)
    if ped == 0 then
        notify(src, 'Could not find your player ped.')
        return
    end

    local coords = GetEntityCoords(ped)
    points[id] = {
        id = id,
        coords = {
            x = tonumber(('%0.4f'):format(coords.x)),
            y = tonumber(('%0.4f'):format(coords.y)),
            z = tonumber(('%0.4f'):format(coords.z))
        },
        capturedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        capturedBy = GetPlayerName(src) or ('source:' .. tostring(src))
    }

    notify(src, ('Saved %s at x=%.4f y=%.4f z=%.4f'):format(
        id,
        points[id].coords.x,
        points[id].coords.y,
        points[id].coords.z
    ))
end

RegisterCommand(Config.Commands.Add, function(src, args)
    if not hasAccess(src) then
        notify(src, 'No permission.')
        return
    end

    local id = trim(table.concat(args, ' '))
    if id == '' then
        notify(src, ('Usage: /%s <marker-id>'):format(Config.Commands.Add))
        return
    end

    if src == 0 then
        notify(src, 'Run this command in-game to capture your current coords.')
        return
    end

    saveCurrentPosition(src, id)
end, false)

local function runSyncCapture(src)
    if not hasAccess(src) then
        notify(src, 'No permission.')
        return
    end

    if src == 0 then
        notify(src, 'Run this command in-game to capture your current coords.')
        return
    end

    local ped = GetPlayerPed(src)
    if ped == 0 then
        notify(src, 'Could not find your player ped.')
        return
    end

    local coords = GetEntityCoords(ped)
    syncCounter = syncCounter + 1
    local id = ('sync-%d-%03d'):format(os.time(), syncCounter)
    local token = ('%s-%d-%03d'):format(GetPlayerName(src) or ('src' .. tostring(src)), os.time(), syncCounter)
    local pending = {
        token = token,
        id = id,
        coords = {
            x = tonumber(('%0.4f'):format(coords.x)),
            y = tonumber(('%0.4f'):format(coords.y)),
            z = tonumber(('%0.4f'):format(coords.z))
        },
        capturedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        capturedBy = GetPlayerName(src) or ('source:' .. tostring(src))
    }

    local ok, err = writeSyncPending(pending)
    if not ok then
        notify(src, ('Sync write failed: %s'):format(err or 'unknown error'))
        return
    end

    waitingSync[token] = {
        source = src,
        id = id,
        startedAt = os.time()
    }

    points[id] = {
        id = id,
        coords = pending.coords,
        capturedAt = pending.capturedAt,
        capturedBy = pending.capturedBy
    }

    notify(src, ('Captured location (%s). Click the matching point on website map to confirm.'):format(id))
end

RegisterCommand(Config.Commands.Sync, function(src)
    runSyncCapture(src)
end, false)

RegisterCommand(Config.Commands.SyncLocation, function(src)
    runSyncCapture(src)
end, false)

RegisterCommand(Config.Commands.Remove, function(src, args)
    if not hasAccess(src) then
        notify(src, 'No permission.')
        return
    end

    local id = trim(table.concat(args, ' '))
    if id == '' then
        notify(src, ('Usage: /%s <marker-id>'):format(Config.Commands.Remove))
        return
    end

    if points[id] then
        points[id] = nil
        notify(src, ('Removed %s'):format(id))
    else
        notify(src, ('No point found for %s'):format(id))
    end
end, false)

RegisterCommand(Config.Commands.Clear, function(src)
    if not hasAccess(src) then
        notify(src, 'No permission.')
        return
    end

    points = {}
    notify(src, 'Cleared all captured points.')
end, false)

RegisterCommand(Config.Commands.List, function(src)
    if not hasAccess(src) then
        notify(src, 'No permission.')
        return
    end

    local count = 0
    for _ in pairs(points) do
        count = count + 1
    end
    notify(src, ('Captured points: %d'):format(count))

    for id, entry in pairs(points) do
        notify(src, ('%s -> %.4f, %.4f, %.4f'):format(id, entry.coords.x, entry.coords.y, entry.coords.z))
    end
end, false)

RegisterCommand(Config.Commands.Export, function(src)
    if not hasAccess(src) then
        notify(src, 'No permission.')
        return
    end

    local ok, err = writeToDisk()
    if ok then
        notify(src, ('Exported %d points to %s'):format((function()
            local c = 0
            for _ in pairs(points) do c = c + 1 end
            return c
        end)(), Config.OutputFilePath))
    else
        notify(src, ('Export failed: %s'):format(err or 'unknown error'))
    end
end, false)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    print('[pf-mapcal-sync] Resource started. Use /' .. Config.Commands.Add .. ' and /' .. Config.Commands.Export)
end)

CreateThread(function()
    while true do
        Wait(1000)

        local syncState = safeReadResourceJson(Config.SyncResourceFile)
            or safeReadJson(Config.SyncFilePath)
        if syncState and syncState.ack and syncState.ack.token and syncState.ack.token ~= lastAckToken then
            lastAckToken = syncState.ack.token
            local waiting = waitingSync[syncState.ack.token]
            if waiting then
                local ackMapPos = syncState.ack.mapPos or {}
                local ackMapX = tonumber(ackMapPos.x or 0) or 0
                local ackMapY = tonumber(ackMapPos.y or 0) or 0
                notify(waiting.source, ('Sync confirmed for %s at map %.2f, %.2f'):format(
                    waiting.id,
                    ackMapX,
                    ackMapY
                ))
                waitingSync[syncState.ack.token] = nil
            end
        end

        local timeoutSeconds = tonumber(Config.SyncWaitSeconds or 180) or 180
        local nowTs = os.time()
        for token, waiting in pairs(waitingSync) do
            if nowTs - (waiting.startedAt or nowTs) > timeoutSeconds then
                local retryCommand = Config.Commands.SyncLocation or Config.Commands.Sync
                notify(waiting.source, ('Sync timeout for %s. Run /%s again.'):format(waiting.id, retryCommand))
                waitingSync[token] = nil
            end
        end
    end
end)
