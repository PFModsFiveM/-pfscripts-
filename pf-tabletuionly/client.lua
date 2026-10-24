local QBCore = exports['pfm-core']:GetCoreObject()

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
        TriggerEvent('chat:addMessage', {
            args = {'Tablet', 'Job update sent: ' .. PlayerData.job.name},
            color = {0, 255, 0}
        })
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
            TriggerEvent('QBCore:Notify', data.message, 'success', 3000)
            -- Refresh work orders data
            getWorkOrdersData()
        else
            TriggerEvent('QBCore:Notify', data and data.message or 'Failed to accept work order', 'error', 3000)
        end
    end, orderId)
end

-- Complete a work order
local function completeWorkOrder(orderId)
    local PlayerData = QBCore.Functions.GetPlayerData()
    QBCore.Functions.TriggerCallback('pf_mech:workorders:complete', function(data)
        if data and data.success then
            TriggerEvent('QBCore:Notify', 
                string.format('Job completed! +$%d, +%d XP', data.payout, data.xpGained), 
                'success', 4000)
            -- Refresh work orders data
            getWorkOrdersData()
        else
            TriggerEvent('QBCore:Notify', data and data.message or 'Failed to complete work order', 'error', 3000)
        end
    end, orderId)
end

-- Cancel a work order
local function cancelWorkOrder(orderId)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:cancel', function(data)
        if data and data.success then
            TriggerEvent('QBCore:Notify', data.message or 'Work order cancelled', 'error', 3000)
            -- Refresh work orders data
            getWorkOrdersData()
        else
            TriggerEvent('QBCore:Notify', data and data.message or 'Failed to cancel work order', 'error', 3000)
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

-- Listen for NUI message events (postMessage from NUI)
RegisterNUICallback('tabletMessage', function(data, cb)
    if data.action == 'workOrdersGetData' then
        getWorkOrdersData()
    elseif data.action == 'workOrdersStartSearch' then
        startWorkOrdersSearch()
    elseif data.action == 'workOrdersStopSearch' then
        stopWorkOrdersSearch()
    elseif data.action == 'workOrdersAccept' then
        acceptWorkOrder(data.orderId)
    elseif data.action == 'workOrdersComplete' then
        completeWorkOrder(data.orderId)
    elseif data.action == 'workOrdersCancel' then
        cancelWorkOrder(data.orderId)
    end
    cb('ok')
end)

-- Handle generic postMessage from NUI for work orders
RegisterCommand('nuidebug', function(source, args, rawCommand)
    print('NUI Debug Command')
end, false)
-- ========================================
-- CASH REGISTER CALLBACKS
-- ========================================

RegisterNUICallback('getCashRegisterItems', function(data, cb)
    -- Trigger server callback to get items from pf-mechanicjob
    QBCore.Functions.TriggerCallback('pf-tabletuionly:getCashRegisterItems', function(result)
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
    TriggerServerEvent('pf-tabletuionly:processCashRegisterTransaction', {
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