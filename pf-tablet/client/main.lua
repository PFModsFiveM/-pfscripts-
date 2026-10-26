local QBCore = exports['pfm-core']:GetCoreObject()
local tabletOpen = false
local tabletProp = nil
local tabletDict = "amb@code_human_in_bus_passenger_idles@female@tablet@base"
local tabletAnim = "base"

-- Allow other resources (e.g. pf-jobs) to send messages to this tablet's NUI
exports('SendNuiMessage', function(payload)
    if payload ~= nil then
        SendNUIMessage(payload)
    end
end)

exports('IsTabletOpen', function()
    return tabletOpen
end)


local function SafeGetPfJobsApps()
    if GetResourceState('pf-jobs') ~= 'started' then return nil end

    local ok, result = pcall(function()
        if exports and exports['pf-jobs'] and exports['pf-jobs'].GetTabletApps then
            return exports['pf-jobs']:GetTabletApps()
        end
        return nil
    end)

    if not ok or type(result) ~= 'table' then return nil end

    -- Normalize returned app definitions to pf-tablet format
    -- Supported inputs:
    --  - pf-tablet style: { name, icon, enabled, external = { resource, app } }
    --  - legacy style:    { id, label, icon, enabled, external=true, resource='pf-jobs' }
    local normalized = {}
    for _, a in ipairs(result) do
        if type(a) == 'table' then
            -- Determine app id
            local rawId = a.id or a.app or a.name or a.label
            local id = rawId and tostring(rawId):lower() or nil

            -- Determine display name
            local displayName = a.name or a.label or (id and (id:sub(1, 1):upper() .. id:sub(2))) or 'App'

            local entry = {
                name = displayName,
                icon = a.icon or '📦',
                enabled = (a.enabled ~= false)
            }

            if type(a.external) == 'table' then
                entry.external = { resource = a.external.resource, app = a.external.app }
            elseif a.external == true and (a.resource or a.res) then
                entry.external = { resource = a.resource or a.res, app = id }
            elseif a.resource == 'pf-jobs' and id then
                -- treat it as external if it's clearly a pf-jobs app
                entry.external = { resource = 'pf-jobs', app = id }
            end

            normalized[#normalized + 1] = entry
        end
    end

    return normalized
end

local function SafeGetPfMechanicApps()
    if GetResourceState('pf-mechanicjob') ~= 'started' then return nil end

    local ok, result = pcall(function()
        if exports and exports['pf-mechanicjob'] and exports['pf-mechanicjob'].GetTabletApps then
            return exports['pf-mechanicjob']:GetTabletApps()
        end
        return nil
    end)

    if not ok or type(result) ~= 'table' then return nil end

    local normalized = {}
    for _, a in ipairs(result) do
        if type(a) == 'table' then
            local rawId = a.id or a.app or a.name or a.label
            local id = rawId and tostring(rawId):lower() or nil
            local displayName = a.name or a.label or (id and (id:sub(1, 1):upper() .. id:sub(2))) or 'App'

            local entry = {
                name = displayName,
                icon = a.icon or '🧰',
                enabled = (a.enabled ~= false)
            }

            if type(a.external) == 'table' then
                entry.external = { resource = a.external.resource, app = a.external.app }
            elseif a.external == true and (a.resource or a.res) then
                entry.external = { resource = a.resource or a.res, app = id }
            elseif a.resource == 'pf-mechanicjob' and id then
                entry.external = { resource = 'pf-mechanicjob', app = id }
            end

            normalized[#normalized + 1] = entry
        end
    end

    return normalized
end

local function GetTabletApps()
    local apps = {}
    for _, app in ipairs(Config.Apps or {}) do
        apps[#apps + 1] = app
    end

    -- Optional integration: show pf-jobs apps only if the resource is running
    if GetResourceState('pf-jobs') == 'started' then
        local pfJobsApps = SafeGetPfJobsApps()
        if pfJobsApps then
            for _, a in ipairs(pfJobsApps) do
                apps[#apps + 1] = a
            end
        else
            apps[#apps + 1] = { name = 'Gruppe6', icon = '🛡️', enabled = true, external = { resource = 'pf-jobs', app = 'gruppe6' } }
            apps[#apps + 1] = { name = 'Garbage', icon = '🗑️', enabled = true, external = { resource = 'pf-jobs', app = 'garbage' } }
            apps[#apps + 1] = { name = 'Taxi', icon = '🚕', enabled = true, external = { resource = 'pf-jobs', app = 'taxi' } }
        end
    end

    -- Optional integration: show pf-policemdt app if the resource is running
    if GetResourceState('pf-policemdt') == 'started' then
        local ok, pfMdtApps = pcall(function()
            if exports and exports['pf-policemdt'] and exports['pf-policemdt'].GetTabletApps then
                return exports['pf-policemdt']:GetTabletApps()
            end
            return nil
        end)

        if ok and type(pfMdtApps) == 'table' then
            for _, a in ipairs(pfMdtApps) do
                apps[#apps + 1] = a
            end
        end
    end

    -- Optional integration: show pf-mechanicjob apps only if the resource is running
    if GetResourceState('pf-mechanicjob') == 'started' then
        local pfMechApps = SafeGetPfMechanicApps()
        if pfMechApps then
            for _, a in ipairs(pfMechApps) do
                apps[#apps + 1] = a
            end
        end
    end

    return apps
end

local function PushAppsIfOpen()
    if not tabletOpen then return end
    SendNUIMessage({
        action = 'updateApps',
        apps = GetTabletApps()
    })
end

local function PushPfJobsNuiModuleIfOpen()
    if not tabletOpen then return end
    if GetResourceState('pf-jobs') ~= 'started' then return end
    -- Ask NUI to load external module script from pf-jobs.
    SendNUIMessage({
        action = 'loadExternalModules',
        scripts = {
            {
                key = 'pf-jobs:tablet_module',
                url = 'https://cfx-nui-pf-jobs/html/tablet_module.js'
            }
        },
        styles = {
            {
                key = 'pf-jobs:css:core',
                url = 'https://cfx-nui-pf-jobs/html/css/core.css'
            },
            {
                key = 'pf-jobs:css:gruppe6',
                url = 'https://cfx-nui-pf-jobs/html/css/gruppe6.css'
            },
            {
                key = 'pf-jobs:css:business',
                url = 'https://cfx-nui-pf-jobs/html/css/business.css'
            },
            {
                key = 'pf-jobs:css:garbage',
                url = 'https://cfx-nui-pf-jobs/html/css/garbage.css'
            },
            {
                key = 'pf-jobs:css:bus',
                url = 'https://cfx-nui-pf-jobs/html/css/bus.css'
            }
        }
    })
end

function PushPoliceMDTNuiModuleIfOpen()
    if not tabletOpen then return end
    if GetResourceState('pf-policemdt') ~= 'started' then return end
    -- Load pf-policemdt tablet module
    SendNUIMessage({
        action = 'loadExternalModules',
        scripts = {
            {
                key = 'pf-policemdt:tablet_module',
                url = 'https://cfx-nui-pf-policemdt/html/tablet_module.js'
            }
        }
    })
end

local function PushPfMechanicNuiModuleIfOpen()
    if not tabletOpen then return end
    if GetResourceState('pf-mechanicjob') ~= 'started' then return end
    -- Load pf-mechanicjob tablet module with app-specific styles
    SendNUIMessage({
        action = 'loadExternalModules',
        scripts = {
            {
                key = 'pf-mechanicjob:tablet_module',
                url = 'https://cfx-nui-pf-mechanicjob/html/tablet_module.js?v=2'
            }
        },
        styles = {
            {
                key = 'pf-mechanicjob:apps:v8',
                url = 'https://cfx-nui-pf-mechanicjob/html/apps.css?v=8'
            }
        }
    })
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'pf-jobs' then
        PushAppsIfOpen()
        PushPfJobsNuiModuleIfOpen()
    elseif resourceName == 'pf-policemdt' then
        PushAppsIfOpen()
        PushPoliceMDTNuiModuleIfOpen()
    elseif resourceName == 'pf-mechanicjob' then
        PushAppsIfOpen()
        PushPfMechanicNuiModuleIfOpen()
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == 'pf-jobs' then
        PushAppsIfOpen()
    elseif resourceName == 'pf-mechanicjob' then
        PushAppsIfOpen()
    end
end)

-- Load animation dictionary
local function loadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Wait(10)
        end
    end
end

-- Load prop model
local function loadPropModel(model)
    local modelHash = GetHashKey(model)
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) do
            Wait(10)
        end
    end
    return modelHash
end

-- Start tablet animation and attach prop
local function startTabletAnimation()
    local ped = PlayerPedId()
    
    -- Load animation
    loadAnimDict(tabletDict)
    
    -- Play animation (looped: -1 means infinite)
    TaskPlayAnim(ped, tabletDict, tabletAnim, 8.0, -8.0, -1, 50, 0, false, false, false)
    
    -- Create and attach prop
    local propModel = loadPropModel("prop_cs_tablet")
    tabletProp = CreateObject(propModel, 0.0, 0.0, 0.0, true, true, false)
    
    local boneIndex = GetPedBoneIndex(ped, 60309) -- IK_R_Hand
    AttachEntityToEntity(tabletProp, ped, boneIndex, 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, true, false, true, 1, true)
    
    SetModelAsNoLongerNeeded(propModel)
end

-- Stop tablet animation and remove prop
local function stopTabletAnimation()
    local ped = PlayerPedId()
    
    -- Stop animation
    ClearPedTasks(ped)
    
    -- Remove prop
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteObject(tabletProp)
        tabletProp = nil
    end
end

-- Also kill any lingering animation threads
local tabletAnimThread = nil

-- Open tablet from item use
local function openTabletUI()
    if tabletOpen then return end
    
    tabletOpen = true
    startTabletAnimation()
    
    -- Set NUI focus - allow mouse but with keyboard input still working via RegisterKeyMapping
    SetNuiFocus(true, true)
    
    -- Send initial data to NUI
    SendNUIMessage({
        action = 'openTablet',
        apps = GetTabletApps()
    })

    PushAppsIfOpen()
    PushPfJobsNuiModuleIfOpen()
    PushPoliceMDTNuiModuleIfOpen()
    PushPfMechanicNuiModuleIfOpen()
    
    -- Keep animation playing while tablet is open
    tabletAnimThread = CreateThread(function()
        while tabletOpen do
            Wait(0)

            if not tabletOpen then
                break
            end
            
            local ped = PlayerPedId()
            -- Restart animation if it stopped
            if not IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
                loadAnimDict(tabletDict)
                TaskPlayAnim(ped, tabletDict, tabletAnim, 8.0, -8.0, -1, 50, 0, false, false, false)
            end
        end

        tabletAnimThread = nil
    end)
end

-- Close tablet
local function closeTablet()
    if not tabletOpen then return end
    
    tabletOpen = false
    
    -- Release NUI focus
    SetNuiFocus(false, false)
    
    -- Kill animation thread immediately
    if tabletAnimThread then
        tabletAnimThread = nil
    end
    
    -- Stop animation
    stopTabletAnimation()
    
    -- Send close message to NUI
    SendNUIMessage({
        action = 'closeTablet'
    })
end

-- Listen for tablet item use event from server
RegisterNetEvent('pf-tablet:client:openTablet', function()
    openTabletUI()
end)

-- Get character name
local function GetCharacterName()
    local QBCore = exports['pfm-core']:GetCoreObject()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local ci = PlayerData and PlayerData.charinfo or {}
    local first = ci.firstname or ci.first or ''
    local last  = ci.lastname  or ci.last  or ''
    local name = (first ~= '' or last ~= '') and (first .. ' ' .. last) or (ci.name or '')
    return name
end

-- Handle tablet UI updates and events (from NUI)
RegisterNUICallback('closeTablet', function(data, cb)
    closeTablet()
    cb('ok')
end)

-- ===== pf-jobs NUI callbacks (served by the tablet resource) =====
-- These allow the pf-jobs UI module (loaded into pf-tablet NUI) to call into the job system.

RegisterNUICallback('gruppe6:getInit', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb(false) return end
    QBCore.Functions.TriggerCallback('pf-jobs:gruppe6:getState', function(state)
        SendNUIMessage({ action = 'gruppe6:init', state = state })
        cb(true)
    end)
end)

RegisterNUICallback('gruppe6:startSearch', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb(false) return end
    if GetResourceState('pf-scoreboard') == 'started' then
        local ok = pcall(function()
            exports['pf-scoreboard']:ShowScoreboard('Gruppe6 Contractor', 'Waiting for job offer')
        end)
        if not ok then
            TriggerEvent('pf-scoreboard:client:show', 'Gruppe6 Contractor', 'Waiting for job offer')
        end
    else
        TriggerEvent('pf-scoreboard:client:show', 'Gruppe6 Contractor', 'Waiting for job offer')
    end
    TriggerServerEvent('pf-jobs:gruppe6:startSearch')
    cb(true)
end)

RegisterNUICallback('gruppe6:stopSearch', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb(false) return end
    if GetResourceState('pf-scoreboard') == 'started' then
        local ok = pcall(function()
            exports['pf-scoreboard']:HideScoreboard()
        end)
        if not ok then
            TriggerEvent('pf-scoreboard:client:hide')
        end
    else
        TriggerEvent('pf-scoreboard:client:hide')
    end
    TriggerServerEvent('pf-jobs:gruppe6:stopSearch')
    cb(true)
end)

RegisterNUICallback('gruppe6:acceptContract', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb(false) return end
    TriggerServerEvent('pf-jobs:gruppe6:acceptContract', data)
    cb(true)
end)

RegisterNUICallback('gruppe6:createGroup', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    TriggerServerEvent('pf-jobs:gruppe6:createGroup')
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:invitePlayer', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    if not data or not data.targetId then cb({ success = false, error = 'No target ID provided' }) return end
    TriggerServerEvent('pf-jobs:gruppe6:invitePlayer', tonumber(data.targetId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:joinByCode', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    local code = data and data.code and tostring(data.code):upper() or nil
    if not code or code == '' then cb({ success = false, error = 'missing_code' }) return end
    TriggerServerEvent('pf-jobs:gruppe6:joinByCode', code)
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:kickMember', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    if not data or not data.targetId then cb({ success = false, error = 'No target ID provided' }) return end
    TriggerServerEvent('pf-jobs:gruppe6:kickMember', tonumber(data.targetId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:updateSplit', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    if not data or not data.targetId or not data.percentage then cb({ success = false, error = 'Missing parameters' }) return end
    TriggerServerEvent('pf-jobs:gruppe6:updateSplit', tonumber(data.targetId), tonumber(data.percentage))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:leaveGroup', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    TriggerServerEvent('pf-jobs:gruppe6:leaveGroup')
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:disbandGroup', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    TriggerServerEvent('pf-jobs:gruppe6:disbandGroup')
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:acceptInvite', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    if not data or not data.leaderId then cb({ success = false, error = 'No leader ID provided' }) return end
    TriggerServerEvent('pf-jobs:gruppe6:acceptInvite', tonumber(data.leaderId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:declineInvite', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ success = false }) return end
    if not data or not data.leaderId then cb({ success = false, error = 'No leader ID provided' }) return end
    TriggerServerEvent('pf-jobs:gruppe6:declineInvite', tonumber(data.leaderId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:endContract', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb(false) return end
    TriggerServerEvent('pf-jobs:gruppe6:endContract')
    cb(true)
end)

RegisterNUICallback('gruppe6:purchaseUpgrade', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb(false) return end
    if not data or not data.upgradeId then cb(false) return end
    TriggerServerEvent('pf-jobs:gruppe6:purchaseUpgrade', data.upgradeId)
    cb(true)
end)

RegisterNUICallback('garbage:getInit', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    QBCore.Functions.TriggerCallback('pf-jobs:garbage:getInit', function(state)
        SendNUIMessage({ action = 'garbage:init', state = state })
        cb({ ok = true })
    end)
end)

RegisterNUICallback('garbage:startJob', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-jobs:garbage:startJob')
    cb({ ok = true })
end)

RegisterNUICallback('garbage/group/create', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-jobs:garbage:createGroup')
    cb({ ok = true })
end)

RegisterNUICallback('garbage/group/accept', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-jobs:garbage:acceptInvite', tonumber(data and data.leaderId))
    cb({ ok = true })
end)

RegisterNUICallback('garbage/group/decline', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-jobs:garbage:declineInvite', tonumber(data and data.leaderId))
    cb({ ok = true })
end)

RegisterNUICallback('garbage/group/leave', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-jobs:garbage:leaveGroup')
    cb({ ok = true })
end)

RegisterNUICallback('garbage/group/disband', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-jobs:garbage:disbandGroup')
    cb({ ok = true })
end)

RegisterNUICallback('garbage/group/joinByCode', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    local code = data and data.code and tostring(data.code):upper() or nil
    if not code or code == '' then cb({ ok = false, error = 'missing_code' }) return end
    TriggerServerEvent('pf-jobs:garbage:joinGroupByCode', code)
    cb({ ok = true })
end)

RegisterNUICallback('taxi:getInit', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    QBCore.Functions.TriggerCallback('pf-taxi:server:getInit', function(payload)
        SendNUIMessage({ action = 'taxi:init', state = payload or {} })
        cb({ ok = true, state = payload or {} })
    end)
end)

RegisterNUICallback('taxi:getCalls', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    QBCore.Functions.TriggerCallback('pf-taxi:server:getCalls', function(calls)
        SendNUIMessage({ action = 'taxi:callsData', calls = calls or {} })
        cb({ ok = true, calls = calls or {} })
    end)
end)

RegisterNUICallback('taxi:toggleAccepting', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-taxi:server:toggleAccepting', { accepting = data and data.accepting == true })
    cb({ ok = true })
end)

RegisterNUICallback('taxi:acceptCall', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-taxi:server:acceptCall', data)
    cb({ ok = true })
end)

RegisterNUICallback('taxi:completeRide', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-taxi:server:completeRide', data and data.rideId, data or {})
    cb({ ok = true })
end)

RegisterNUICallback('taxi:cancelRide', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-taxi:server:cancelRide', data and data.rideId)
    cb({ ok = true })
end)

RegisterNUICallback('taxi:rentVehicle', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-taxi:server:rentVehicle', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('taxi:returnVehicle', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('pf-taxi:server:returnVehicle')
    cb({ ok = true })
end)

RegisterNUICallback('taxi:getPhotos', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false, photos = {} }) return end
    QBCore.Functions.TriggerCallback('pf-taxi:server:getPhotos', function(result)
        cb({ ok = true, photos = (result and result.photos) or {} })
    end)
end)

RegisterNUICallback('bus:getInit', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('bus:server:getStats')
    TriggerServerEvent('bus:server:getRoutes')
    cb({ ok = true })
end)

RegisterNUICallback('bus:startRoute', function(data, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    local routeId = data and (data.routeId or (type(data.route) == 'table' and data.route.id) or data.route)
    if not routeId then cb({ ok = false, error = 'missing_route_id' }) return end
    TriggerServerEvent('bus:server:startRoute', tonumber(routeId))
    cb({ ok = true })
end)

RegisterNUICallback('bus:cancelRoute', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    TriggerServerEvent('bus:server:cancelRoute')
    cb({ ok = true })
end)

RegisterNUICallback('bus:completeStop', function(_, cb)
    if GetResourceState('pf-jobs') ~= 'started' then cb({ ok = false }) return end
    ExecuteCommand('busstop')
    cb({ ok = true })
end)

RegisterNetEvent('pf-taxi:client:updateStats', function(stats)
    SendNUIMessage({ action = 'taxi:updateStats', stats = stats })
end)

RegisterNetEvent('pf-taxi:client:callsData', function(calls)
    SendNUIMessage({ action = 'taxi:callsData', calls = calls or {} })
end)

RegisterNetEvent('pf-taxi:client:startCall', function(ride)
    SendNUIMessage({ action = 'taxi:startCall', ride = ride })
end)

RegisterNetEvent('pf-taxi:client:rideCancelled', function()
    SendNUIMessage({ action = 'taxi:rideCancelled' })
end)

RegisterNetEvent('pf-jobs:gruppe6:contracts', function(contracts)
    SendNUIMessage({ action = 'gruppe6:contracts', contracts = contracts or {} })
end)

RegisterNetEvent('pf-jobs:gruppe6:activeContract', function(contract)
    SendNUIMessage({ action = 'gruppe6:activeContract', contract = contract })
end)

RegisterNetEvent('pf-jobs:gruppe6:updateXP', function(xp, level)
    SendNUIMessage({ action = 'gruppe6:updateXP', xp = xp, level = level })
end)

RegisterNetEvent('pf-jobs:gruppe6:groupUpdate', function(groupData)
    SendNUIMessage({ action = 'gruppe6:groupUpdate', group = groupData })
end)

RegisterNetEvent('pf-jobs:gruppe6:receiveInvite', function(leaderName, leaderId)
    SendNUIMessage({ action = 'gruppe6:addInvite', invite = { leaderName = leaderName, leaderId = leaderId } })
end)

RegisterNetEvent('pf-jobs:garbage:groupUpdate', function(groupData)
    SendNUIMessage({ action = 'garbage:groupUpdate', group = groupData })
end)

RegisterNetEvent('pf-jobs:garbage:receiveInvite', function(leaderName, leaderId)
    SendNUIMessage({ action = 'garbage:addInvite', invite = { leaderName = leaderName, leaderId = leaderId } })
end)

RegisterNetEvent('pf-jobs:garbage:updateXP', function(xp, level)
    SendNUIMessage({ action = 'garbage:updateXP', xp = xp, level = level })
end)

RegisterNetEvent('pf-jobs:garbage:carrying', function(carrying)
    SendNUIMessage({ action = 'garbage:carrying', carrying = carrying })
end)

RegisterNetEvent('pf-taxi:client:rideStarted', function(rideId, rideData)
    SendNUIMessage({ action = 'taxi:rideStarted', rideId = rideId, ride = rideData })
end)

RegisterNetEvent('pf-taxi:client:rideCompleted', function(data)
    SendNUIMessage({ action = 'taxi:rideCompleted', data = data })
end)

RegisterNetEvent('bus:client:statsData', function(stats)
    SendNUIMessage({ action = 'bus:statsData', stats = stats })
end)

RegisterNetEvent('bus:client:updateStats', function(stats)
    SendNUIMessage({ action = 'bus:updateStats', stats = stats })
end)

RegisterNetEvent('bus:client:routesData', function(routes)
    SendNUIMessage({ action = 'bus:routesData', routes = routes })
end)

RegisterNetEvent('bus:client:loadRoute', function(route)
    SendNUIMessage({ action = 'bus:loadRoute', route = route })
end)

-- Push in-game time updates while tablet is open
CreateThread(function()
    while true do
        Wait(1000)
        if tabletOpen then
            SendNUIMessage({
                action = 'updateGameTime',
                hour = GetClockHours(),
                minute = GetClockMinutes(),
                day = GetClockDayOfMonth(),
                month = GetClockMonth() + 1,
                year = GetClockYear()
            })
        end
    end
end)

RegisterNUICallback('openApp', function(data, cb)
    -- Future functionality for opening specific apps
    QBCore.Functions.Notify('App "' .. data.appName .. '" coming soon!', 'info')
    cb('ok')
end)

-- External apps bridge: used by NUI to invoke other resource callbacks or events
RegisterNUICallback('external/open', function(data, cb)
    local res = data and data.resource
    local app = data and data.app

    if res == 'pf-jobs' then
        if GetResourceState('pf-jobs') ~= 'started' then
            cb({ ok = false, error = 'pf-jobs is not started' })
            return
        end

        -- These events/callbacks live in pf-jobs (legacy namespace kept there)
        if app == 'gruppe6' then
            -- No direct open event required; NUI will call pf-jobs NUI callbacks.
            cb({ ok = true })
            return
        end

        if app == 'garbage' then
            cb({ ok = true })
            return
        end

        if app == 'taxi' then
            cb({ ok = true })
            return
        end

        if app == 'bus' then
            cb({ ok = true })
            return
        end

        cb({ ok = false, error = 'Unknown pf-jobs app' })
        return
    end

    if res == 'pf-policemdt' then
        if GetResourceState('pf-policemdt') ~= 'started' then
            cb({ ok = false, error = 'pf-policemdt is not started' })
            return
        end

        if app == 'policemdt' then
            -- pf-tablet will load the embedded iframe, no event trigger needed
            cb({ ok = true })
            return
        end

        cb({ ok = false, error = 'Unknown pf-policemdt app' })
        return
    end

    if res == 'pf-mechanicjob' then
        if GetResourceState('pf-mechanicjob') ~= 'started' then
            cb({ ok = false, error = 'pf-mechanicjob is not started' })
            return
        end

        if app == 'mechanic' then
            cb({ ok = true })
            return
        end

        cb({ ok = false, error = 'Unknown pf-mechanicjob app' })
        return
    end

    cb({ ok = false, error = 'Unknown external resource' })
end)

-- Removed job app open callback (Gruppe6)

-- Handle requestGameTime callback for polling
RegisterNUICallback('requestGameTime', function(data, cb)
    SendNUIMessage({
        action = 'updateGameTime',
        hour = GetClockHours(),
        minute = GetClockMinutes(),
        day = GetClockDayOfMonth(),
        month = GetClockMonth() + 1,
        year = GetClockYear()
    })
    cb('ok')
end)

-- Close tablet with ESC key
RegisterCommand('closeTablet', function()
    if tabletOpen then
        TriggerEvent('pf-tablet:client:closeTablet')
    end
end)

-- FiveM key mapping names use 'ESCAPE' (not 'ESC')
RegisterKeyMapping('closeTablet', 'Close Tablet', 'keyboard', 'ESCAPE')

RegisterNetEvent('pf-tablet:client:closeTablet', function()
    closeTablet()
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if tabletOpen then
            stopTabletAnimation()
        end
    end
end)

-- Business app: query server for online job counts
RegisterNUICallback('app/business/getStatus', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-tablet:server:getJobOnlineCounts', function(result)
        cb(result or {})
    end, Config.BusinessJobs)
end)

-- Businesses app: query server for all businesses with proper names from pf-computer
RegisterNUICallback('app/businesses/list', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-tablet:server:getBusinesses', function(result)
        cb(result or {})
    end)
end)

-- Business Manager app: government registry, ownership transfers, own supply orders
RegisterNUICallback('app/bm/registry', function(_, cb)
    QBCore.Functions.TriggerCallback('pf-tablet:server:bm:registry', function(result) cb(result or { ok = false }) end)
end)
RegisterNUICallback('app/bm/transfer', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-tablet:server:bm:transfer', function(result) cb(result or { ok = false }) end,
        { businessId = data and data.businessId, ownerId = data and data.ownerId })
end)
RegisterNUICallback('app/bm/employees', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-tablet:server:bm:employees', function(result) cb(result or { ok = false }) end,
        { businessId = data and data.businessId })
end)
RegisterNUICallback('app/bm/supplies', function(_, cb)
    QBCore.Functions.TriggerCallback('pf-tablet:server:bm:supplies', function(result) cb(result or { ok = false }) end)
end)

-- Server push -> tell UI to refresh if window is open
RegisterNetEvent('pf-tablet:client:businessPushRefresh', function()
    SendNUIMessage({ action = 'businessPushRefresh' })
end)
-- Backward compat alias
RegisterNetEvent('pf-jobs:client:businessPushRefresh', function()
    SendNUIMessage({ action = 'businessPushRefresh' })
end)

-- Allow updating name explicitly
local function PushPlayerName(name)
    SendNUIMessage({ action = 'setPlayerName', value = name })
end

RegisterNetEvent('pf-tablet:client:setPlayerName', PushPlayerName)
-- Backward compat alias
RegisterNetEvent('pf-jobs:client:setPlayerName', PushPlayerName)

-- ========================================
-- JOB DETECTION AND APP VISIBILITY
-- ========================================

-- Track current job for change detection
local currentJob = nil

-- Send player data to NUI
local function sendPlayerDataToNUI()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if PlayerData and PlayerData.job then
        local payload = {
            type = 'jobUpdate',
            playerData = {
                job = PlayerData.job.name,
                label = PlayerData.job.label,
                grade = PlayerData.job.grade.name
            }
        }
        SendNUIMessage(payload)
    end
end

-- Update job when it changes
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    if currentJob ~= JobInfo.name then
        currentJob = JobInfo.name
        sendPlayerDataToNUI()
    end
end)

-- Check job on resource start
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Wait(500)
        sendPlayerDataToNUI()
    end
end)

-- Listen for NUI requests for player data
RegisterNUICallback('getPlayerData', function(data, cb)
    sendPlayerDataToNUI()
    cb('ok')
end)

-- Periodic job check thread
CreateThread(function()
    local checkInterval = 0
    while true do
        Wait(1000)
        checkInterval = checkInterval + 1
        
        -- Send job data every 5 seconds on startup, then less frequently
        if checkInterval == 5 or checkInterval % 30 == 0 then
            local PlayerData = QBCore.Functions.GetPlayerData()
            if PlayerData and PlayerData.job then
                if currentJob ~= PlayerData.job.name then
                    currentJob = PlayerData.job.name
                    sendPlayerDataToNUI()
                end
            end
        end
    end
end)

-- ========================================
-- WORK ORDERS CALLBACKS
-- ========================================

-- Get work orders data
local function getWorkOrdersData()
    QBCore.Functions.TriggerCallback('pf_mech:workorders:getData', function(data)
        SendNUIMessage({
            type = 'workOrdersDataUpdate',
            data = data
        })
    end)
end

-- Start searching for work orders
local function startWorkOrdersSearch()
    QBCore.Functions.TriggerCallback('pf_mech:workorders:startSearch', function(data)
        if data and data.success then
            SendNUIMessage({
                type = 'workOrdersDataUpdate',
                data = data
            })
        end
    end)
end

-- Stop searching for work orders
local function stopWorkOrdersSearch()
    QBCore.Functions.TriggerCallback('pf_mech:workorders:stopSearch', function(data)
        if data and data.success then
            SendNUIMessage({
                type = 'workOrdersDataUpdate',
                data = data
            })
        end
    end)
end

-- Accept a work order
local function acceptWorkOrder(orderId)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:accept', function(data)
        if data and data.success then
            QBCore.Functions.Notify(data.message or 'Work order accepted', 'success', 3000)
            -- Refresh work orders data
            getWorkOrdersData()
        else
            QBCore.Functions.Notify(data and data.message or 'Failed to accept work order', 'error', 3000)
        end
    end, orderId)
end

-- Complete a work order
local function completeWorkOrder(orderId)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:complete', function(data)
        if data and data.success then
            QBCore.Functions.Notify(
                string.format('Job completed! +$%d, +%d XP', data.payout or 0, data.xpGained or 0), 
                'success', 4000)
            -- Refresh work orders data
            getWorkOrdersData()
        else
            QBCore.Functions.Notify(data and data.message or 'Failed to complete work order', 'error', 3000)
        end
    end, orderId)
end

-- Cancel a work order
local function cancelWorkOrder(orderId)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:cancel', function(data)
        if data and data.success then
            QBCore.Functions.Notify(data.message or 'Work order cancelled', 'error', 3000)
            -- Refresh work orders data
            getWorkOrdersData()
        else
            QBCore.Functions.Notify(data and data.message or 'Failed to cancel work order', 'error', 3000)
        end
    end, orderId)
end

-- Listen for NUI callback messages
RegisterNUICallback('workOrdersGetData', function(data, cb)
    getWorkOrdersData()
    cb('ok')
end)

RegisterNUICallback('workOrdersStartSearch', function(data, cb)
    startWorkOrdersSearch()
    cb('ok')
end)

RegisterNUICallback('workOrdersStopSearch', function(data, cb)
    stopWorkOrdersSearch()
    cb('ok')
end)

RegisterNUICallback('workOrdersAccept', function(data, cb)
    if data.orderId then
        acceptWorkOrder(data.orderId)
    end
    cb('ok')
end)

RegisterNUICallback('workOrdersComplete', function(data, cb)
    if data.orderId then
        completeWorkOrder(data.orderId)
    end
    cb('ok')
end)

RegisterNUICallback('workOrdersCancel', function(data, cb)
    if data.orderId then
        cancelWorkOrder(data.orderId)
    end
    cb('ok')
end)

-- ========================================
-- CASH REGISTER CALLBACKS
-- ========================================

RegisterNUICallback('getCashRegisterItems', function(data, cb)
    -- Trigger server callback to get items from pf-mechanicjob
    QBCore.Functions.TriggerCallback('pf-tablet:getCashRegisterItems', function(result)
        cb(result or {
            items = {},
            taxRate = 0.08
        })
    end)
end)

RegisterNUICallback('processCashRegister', function(data, cb)
    local result = { success = false, message = 'Transaction failed' }
    
    if not data or not data.items then
        cb(result)
        return
    end
    
    -- Trigger server event to process transaction
    TriggerServerEvent('pf-tablet:processCashRegisterTransaction', {
        items = data.items,
        subtotal = data.subtotal,
        tax = data.tax,
        total = data.total,
        taxRate = data.taxRate
    })
    
    result.success = true
    result.message = 'Transaction processed'
    cb(result)
end)
