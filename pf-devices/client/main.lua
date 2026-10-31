-- PF Devices client: the bridge between the shells' NUI pages and the server.
--
-- The runtime (html/runtime.js) posts to this resource's NUI callbacks whatever shell it runs in,
-- so an app module needs no client code of its own. Shells listen to 'pf-devices:client:forward'
-- and pass the message on to their NUI page while they are open.

local QBCore = exports['pfm-core']:GetCoreObject()

local pending = {}
local nextId = 0

local function forward(msg)
    TriggerEvent('pf-devices:client:forward', msg)
end

--- Calls an app's server handler and waits for the result (must run in a coroutine, which
--- NUI callbacks and threads do).
local function Rpc(appId, method, payload)
    nextId = nextId + 1
    local id = nextId
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('pf-devices:server:rpc', id, appId, method, payload or {})
    SetTimeout(10000, function()
        if pending[id] then
            pending[id] = nil
            p:resolve({ ok = false, error = 'timeout' })
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('pf-devices:client:rpc', function(id, result)
    local p = pending[id]
    if not p then return end
    pending[id] = nil
    p:resolve(result)
end)

RegisterNetEvent('pf-devices:client:appEvent', function(appId, event, payload)
    forward({ action = 'pfapp:event', app = appId, event = event, payload = payload })
end)

RegisterNetEvent('pf-devices:client:appsChanged', function()
    forward({ action = 'pfapp:appsChanged' })
end)

-- ── NUI callbacks used by the runtime from any shell ───────────────
RegisterNUICallback('rpc', function(data, cb)
    if type(data) ~= 'table' or type(data.app) ~= 'string' or type(data.method) ~= 'string' then
        cb({ ok = false, error = 'bad_request' })
        return
    end
    cb(Rpc(data.app, data.method, type(data.payload) == 'table' and data.payload or {}))
end)

RegisterNUICallback('launch', function(data, cb)
    if type(data) == 'table' and type(data.app) == 'string' then
        TriggerServerEvent('pf-devices:server:launch', data.app)
    end
    cb({ ok = true })
end)

RegisterNUICallback('apps', function(data, cb)
    local device = type(data) == 'table' and data.device or nil
    QBCore.Functions.TriggerCallback('pf-devices:apps', function(result)
        cb(result or { apps = {}, store = {} })
    end, device)
end)

RegisterNUICallback('sites', function(_, cb)
    QBCore.Functions.TriggerCallback('pf-devices:sites', function(result)
        cb(result or { ok = false, sites = {} })
    end)
end)

RegisterNUICallback('notify', function(data, cb)
    if type(data) == 'table' and type(data.message) == 'string' then
        QBCore.Functions.Notify(data.message:sub(1, 200), data.type or 'primary', tonumber(data.duration) or 4000)
    end
    cb({ ok = true })
end)

RegisterNUICallback('player', function(_, cb)
    local PlayerData = QBCore.Functions.GetPlayerData() or {}
    local ci = PlayerData.charinfo or {}
    local job = PlayerData.job or {}
    cb({
        ok = true,
        citizenid = PlayerData.citizenid,
        name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
        job = job.name,
        jobLabel = job.label,
        grade = type(job.grade) == 'table' and job.grade.level or job.grade,
        gradeLabel = type(job.grade) == 'table' and job.grade.name or nil,
        onduty = job.onduty == true,
    })
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb({ ok = x ~= nil and y ~= nil })
end)

-- ── exports for other client scripts ───────────────────────────────
exports('Rpc', function(appId, method, payload) return Rpc(appId, method, payload) end)
-- A client-side push into the app running in the open shell (for resources whose client already
-- receives the server event, e.g. pf-jobs taxi calls).
exports('AppEvent', function(appId, event, payload)
    forward({ action = 'pfapp:event', app = appId, event = event, payload = payload })
end)
exports('OpenApp', function(appId, params)
    forward({ action = 'pfapp:open', app = appId, params = params })
end)
exports('CloseApp', function(appId)
    forward({ action = 'pfapp:close', app = appId })
end)
exports('OpenSite', function(host)
    forward({ action = 'pfapp:openSite', host = host })
end)
exports('RefreshApps', function()
    forward({ action = 'pfapp:appsChanged' })
end)

-- Any NUI message for the open shell's page (legacy app modules that listen to window messages).
exports('SendToShell', function(payload)
    if type(payload) == 'table' then forward(payload) end
end)

-- Shells report when they open and close, so other resources know whether a device is on screen.
local openShells = {}
AddEventHandler('pf-devices:client:shellState', function(device, isOpen)
    if type(device) == 'string' then openShells[device] = isOpen == true or nil end
end)
exports('IsShellOpen', function(device)
    if device then return openShells[device] == true end
    return next(openShells) ~= nil
end)
exports('GetOpenShell', function()
    return (next(openShells))
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    forward({ action = 'pfapp:appsChanged' })
end)
