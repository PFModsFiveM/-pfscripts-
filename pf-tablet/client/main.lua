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


local function GetTabletApps()
    -- The tablet's own apps. Job, mechanic, government, news and other apps are platform apps
    -- served by pf-devices (the same modules run on the computer).
    local apps = {}
    for _, app in ipairs(Config.Apps or {}) do
        apps[#apps + 1] = app
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

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'pf-jobs' then
        PushAppsIfOpen()
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
    TriggerEvent('pf-devices:client:shellState', 'tablet', true)
    
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
    TriggerEvent('pf-devices:client:shellState', 'tablet', false)
end

-- a launcher app (e.g. the MDT) opens its own screen: put the tablet away first
RegisterNetEvent('pf-devices:client:closeShells', function()
    closeTablet()
end)

-- pf-devices messages (app pushes, app list changes, open requests) reach the page while it is open
AddEventHandler('pf-devices:client:forward', function(msg)
    if tabletOpen and type(msg) == 'table' then
        SendNUIMessage(msg)
    end
end)

RegisterNUICallback('notify', function(data, cb)
    if type(data) == 'table' and type(data.message) == 'string' then
        QBCore.Functions.Notify(data.message:sub(1, 200), data.type or 'primary')
    end
    cb('ok')
end)

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

-- The Gruppe 6, Garbage, Taxi and Bus apps are pf-devices platform apps served by pf-jobs (the same
-- modules run on the computer); their callbacks and pushes no longer pass through the tablet.

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

-- External apps bridge (legacy tablet modules). Job, mechanic and MDT apps are platform apps now.
RegisterNUICallback('external/open', function(data, cb)
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

-- (the tablet's own Business, Businesses and Business Manager apps are gone: the Business Manager,
-- Order Supplies and the Job Board are pf-computer's platform apps, the business list is the Directory)

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
