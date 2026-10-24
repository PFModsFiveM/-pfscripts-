local QBCore = nil
local ESX = nil
local ActiveFramework = 'standalone'

local isOpen = false
local callbackNonce = 0
local pendingCallbacks = {}

math.randomseed(GetGameTimer())

local function detectFramework()
    local configured = string.lower(tostring(Config.Framework or 'auto'))

    if configured == 'qbcore' or configured == 'auto' then
        if GetResourceState('pfm-core') == 'started' then
            local ok, core = pcall(function()
                return exports['pfm-core']:GetCoreObject()
            end)

            if ok and core then
                QBCore = core
                ActiveFramework = 'qbcore'
                return
            end
        end
    end

    if configured == 'esx' or configured == 'auto' then
        if GetResourceState('es_extended') == 'started' then
            local ok, core = pcall(function()
                return exports['es_extended']:getSharedObject()
            end)

            if ok and core then
                ESX = core
                ActiveFramework = 'esx'
                return
            end

            TriggerEvent('esx:getSharedObject', function(obj)
                ESX = obj
            end)

            if ESX then
                ActiveFramework = 'esx'
                return
            end
        end
    end

    ActiveFramework = 'standalone'
end

local function notify(msg, msgType)
    if ActiveFramework == 'qbcore' then
        TriggerEvent('QBCore:Notify', msg, msgType or 'primary')
        return
    end

    if ActiveFramework == 'esx' then
        TriggerEvent('esx:showNotification', msg)
        return
    end

    local ok = pcall(function()
        TriggerEvent('chat:addMessage', {
            color = { 90, 180, 255 },
            args = { 'Guidebook', msg }
        })
    end)

    if not ok then
        print(('[pf-guidebook] %s'):format(msg))
    end
end

RegisterNetEvent('pf-guidebook:client:notify', function(msg, msgType)
    notify(msg, msgType)
end)

RegisterNetEvent('pf-guidebook:client:callbackResponse', function(requestId, result)
    local key = tostring(requestId or '')
    local waiter = pendingCallbacks[key]
    if not waiter then
        return
    end

    pendingCallbacks[key] = nil
    waiter:resolve(result)
end)

local function awaitServerCallback(name, ...)
    callbackNonce = callbackNonce + 1
    local requestId = string.format('%s_%d_%d', name, GetGameTimer(), callbackNonce)
    local args = { ... }
    local payload = args[1]
    local timeoutMs = math.max(2000, math.floor(tonumber(Config.CallbackTimeoutMs) or 12000))

    local p = promise.new()
    pendingCallbacks[requestId] = p

    TriggerServerEvent('pf-guidebook:server:callbackRequest', requestId, name, payload)

    CreateThread(function()
        Wait(timeoutMs)
        if pendingCallbacks[requestId] == p then
            pendingCallbacks[requestId] = nil
            p:resolve({
                ok = false,
                error = 'Request timed out'
            })
        end
    end)

    return Citizen.Await(p)
end

local function closeGuidebook(sendCloseMessage)
    if not isOpen then
        return
    end

    isOpen = false
    SetNuiFocus(false, false)

    if sendCloseMessage then
        SendNUIMessage({ action = 'close' })
    end
end

local function setWaypoint(point)
    if type(point) ~= 'table' then
        return
    end

    local x = tonumber(point.x)
    local y = tonumber(point.y)

    if not x or not y then
        notify('Invalid GPS coordinates.', 'error')
        return
    end

    SetNewWaypoint(x + 0.0, y + 0.0)

    local label = point.label or point.key or 'Guide point'
    notify(('Waypoint set: %s'):format(label), 'success')
end

RegisterNetEvent('pf-guidebook:client:open', function(options)
    CreateThread(function()
        local payload = awaitServerCallback('pf-guidebook:server:getOpenPayload', options or {})
        if not payload or not payload.ok then
            notify('Unable to open guidebook.', 'error')
            return
        end

        isOpen = true
        SetNuiFocus(true, true)

        SendNUIMessage({
            action = 'open',
            payload = payload
        })
    end)
end)

RegisterNetEvent('pf-guidebook:client:setWaypoint', function(point)
    setWaypoint(point)
end)

RegisterNUICallback('close', function(_, cb)
    closeGuidebook(false)
    cb({ ok = true })
end)

RegisterNUICallback('getVisibleData', function(data, cb)
    local options = {
        adminRequested = false,
        pageKey = data and data.pageKey or nil
    }

    local payload = awaitServerCallback('pf-guidebook:server:getOpenPayload', options)
    cb(payload or { ok = false, error = 'Unable to fetch data' })
end)

RegisterNUICallback('getAdminData', function(_, cb)
    local result = awaitServerCallback('pf-guidebook:server:getAdminDataset')
    cb(result or { ok = false, error = 'Unable to fetch admin data' })
end)

RegisterNUICallback('saveCategory', function(data, cb)
    local result = awaitServerCallback('pf-guidebook:server:saveCategory', data or {})
    cb(result or { ok = false, error = 'Unable to save category' })
end)

RegisterNUICallback('deleteCategory', function(data, cb)
    local categoryId = data and data.id or nil
    local result = awaitServerCallback('pf-guidebook:server:deleteCategory', categoryId)
    cb(result or { ok = false, error = 'Unable to delete category' })
end)

RegisterNUICallback('savePage', function(data, cb)
    local result = awaitServerCallback('pf-guidebook:server:savePage', data or {})
    cb(result or { ok = false, error = 'Unable to save page' })
end)

RegisterNUICallback('deletePage', function(data, cb)
    local pageId = data and data.id or nil
    local result = awaitServerCallback('pf-guidebook:server:deletePage', pageId)
    cb(result or { ok = false, error = 'Unable to delete page' })
end)

RegisterNUICallback('resolvePoint', function(data, cb)
    local pointKey = data and data.pointKey or nil
    local result = awaitServerCallback('pf-guidebook:server:resolvePointByKey', pointKey)
    cb(result or { ok = false, error = 'Unable to resolve point' })
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    if data and data.pointKey then
        local result = awaitServerCallback('pf-guidebook:server:resolvePointByKey', data.pointKey)
        if result and result.ok and result.point then
            setWaypoint(result.point)
            cb({ ok = true })
            return
        end

        cb(result or { ok = false, error = 'Point not found' })
        return
    end

    setWaypoint(data or {})
    cb({ ok = true })
end)

RegisterCommand('closeGuidebook', function()
    if isOpen then
        closeGuidebook(true)
    end
end, false)

RegisterKeyMapping('closeGuidebook', 'Close Guidebook', 'keyboard', 'ESCAPE')

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if isOpen then
        SetNuiFocus(false, false)
    end
end)

detectFramework()

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qb-core' or resourceName == 'es_extended' then
        detectFramework()
    end
end)
