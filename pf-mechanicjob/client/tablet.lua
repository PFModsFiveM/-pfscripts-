-- client/tablet.lua
-- PF Mechanic Job - Tablet Integration Client
-- Sends data to pf-tablet for direct app rendering

local QBCore = exports['pfm-core']:GetCoreObject()
local tabletOpen = false
local currentPosBusiness = nil
local lastChargeTime = 0  -- Debounce: prevent duplicate charges
local CHARGE_DEBOUNCE_MS = 500  -- 500ms cooldown between charge attempts

local function isPfTabletAvailable()
    return GetResourceState('pf-tablet') == 'started'
        and exports
        and exports['pf-tablet']
        and exports['pf-tablet'].SendNuiMessage
end

local function sendPfTabletMessage(payload)
    if not isPfTabletAvailable() then return false end
    local ok = pcall(function()
        PFMechShell(payload)
    end)
    return ok
end

-- Helper: Check if player is mechanic
local function isPlayerMechanic()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    
    for _, jobName in ipairs(Config.AllowedJobs or {'mechanic'}) do
        if PlayerData.job.name == jobName then
            return true
        end
    end
    return false
end

-- Helper: Format game time
local function getGameTime()
    local hour = GetClockHours()
    local minute = GetClockMinutes()
    return string.format('%02d:%02d', hour, minute)
end

-- Helper: Format game date
local function getGameDate()
    local day = GetClockDayOfMonth()
    local month = GetClockMonth()
    local year = GetClockYear()
    return string.format('%02d/%02d/%d', month, day, year)
end

-- Open the tablet (opens pf-tablet directly)
local function openTablet()
    if not isPfTabletAvailable() then
        QBCore.Functions.Notify('PF Tablet is not available', 'error')
        return
    end

    tabletOpen = true
    TriggerEvent('pf-tablet:client:openTablet')
end

-- Send work orders update
local function sendWorkOrdersUpdate(workOrderData)
    if not isPfTabletAvailable() then return end
    
    sendPfTabletMessage({
        action = 'updateWorkOrders',
        workOrderData = workOrderData
    })
end

-- Send management data update
local function sendManagementUpdate(mgmtData)
    if not isPfTabletAvailable() then return end
    
    sendPfTabletMessage({
        action = 'management:update',
        payload = mgmtData
    })
end

-- Keep global table for compatibility
_G.sendPfTabletMessage = sendPfTabletMessage
_G.sendWorkOrdersUpdate = sendWorkOrdersUpdate
_G.sendManagementUpdate = sendManagementUpdate

-- Close tablet
local function closeTablet()
    if not tabletOpen then return end
    tabletOpen = false
end

-- Events
RegisterNetEvent('pf-mechanicjob:client:useMechTablet', function()
    if not isPlayerMechanic() then
        QBCore.Functions.Notify('You must be a mechanic to use this!', 'error')
        return
    end
    
    if tabletOpen then
        closeTablet()
    else
        openTablet()
    end
end)

RegisterNetEvent('pf-mechanicjob:client:openTablet', function()
    if not isPlayerMechanic() then return end
    openTablet()
end)

RegisterNetEvent('pf-mechanicjob:client:closeTablet', function()
    closeTablet()
end)

RegisterNetEvent('pf-tablet:client:closeTablet', function()
    tabletOpen = false
end)

RegisterNetEvent('pf-mechanicjob:client:workOrdersReady', function(_payload)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:getData', function(workOrderData)
        if workOrderData then
            sendWorkOrdersUpdate(workOrderData)
        end
    end)
end)

-- Work Order NUI Callbacks (from mechanic.js $.post calls)
RegisterNUICallback('workorders/getData', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:getData', function(workOrderData)
        if workOrderData then
            sendWorkOrdersUpdate(workOrderData)
        end
        cb(workOrderData)
    end)
end)

RegisterNUICallback('workorders/refresh', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:workorders: refresh', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('workorders/accept', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:accept', function(result)
        if result and result.success then
            -- Refresh work orders after accept
            QBCore.Functions.TriggerCallback('pf_mech:workorders:getData', function(workOrderData)
                if isPlayerMechanic() then
                    sendWorkOrdersUpdate(workOrderData)
                end
            end)
        end
        cb(result)
    end, data.orderId)
end)

RegisterNUICallback('workorders/cancel', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:workorders:cancel', function(result)
        cb(result)
    end, data.orderId)
end)

RegisterNUICallback('workorders/startSearch', function(data, cb)
    print('[Client Tablet] NUI Callback: workorders/startSearch received')
    QBCore.Functions.TriggerCallback('pf_mech:workorders:startSearch', function(result)
        print('[Client Tablet] Server callback result:', json.encode(result or {}))
        if result and result.success then
            sendWorkOrdersUpdate(result)
        end
        cb(result)
    end)
end)

RegisterNUICallback('workorders/stopSearch', function(data, cb)
    print('[Client Tablet] NUI Callback: workorders/stopSearch received')
    QBCore.Functions.TriggerCallback('pf_mech:workorders:stopSearch', function(result)
        print('[Client Tablet] Server callback result:', json.encode(result or {}))
        if result and result.success then
            sendWorkOrdersUpdate(result)
        end
        cb(result)
    end)
end)

-- Management NUI Callbacks (from mechanic.js)
RegisterNUICallback('management:getOverview', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:overview', function(result)
        cb(result or {})
    end)
end)

RegisterNUICallback('management:getGraph', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:graph', function(rows)
        cb(rows or {})
    end)
end)

RegisterNUICallback('management:getEmployees', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:employees', function(list)
        cb(list or {})
    end)
end)

RegisterNUICallback('management:requestPricing', function(data, cb)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local business = (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
    QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
        cb(resp or { business = business, prices = {}, taxRate = 0.0 })
    end, business)
end)

RegisterNUICallback('management:getSettings', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getSettings', function(settings)
        cb(settings or {})
    end)
end)

RegisterNUICallback('hireEmployee', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:hire', function(success, message)
        cb({ success = success, message = message })
    end, data.citizenid or data.id)
end)

RegisterNUICallback('fireEmployee', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:fire', function(success)
        cb({ success = success })
    end, data.citizenid)
end)

RegisterNUICallback('promoteEmployee', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:promote', function(success)
        cb({ success = success })
    end, data.citizenid)
end)

RegisterNUICallback('demoteEmployee', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:demote', function(success)
        cb({ success = success })
    end, data.citizenid)
end)

RegisterNUICallback('getEmployeeStats', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:getStats', function(stats)
        cb(stats)
    end, data.citizenid)
end)

RegisterNUICallback('management:getEmployeeStats', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:getStats', function(stats)
        cb(stats)
    end, data.citizenid)
end)

-- POS NUI Callbacks
RegisterNUICallback('pos/open', function(data, cb)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local business = (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
    currentPosBusiness = business
    QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
        local payload = resp or { business = business, prices = {}, taxRate = 0.0, canEdit = false }

        local items = payload.prices or {}
        sendPfTabletMessage({
            action = 'pos:open',
            data = {
                business = payload.business or business,
                items = items,
                mandatoryCharges = payload.mandatoryCharges or {},
                taxRate = payload.taxRate or 0.0,
                canEdit = payload.canEdit == true,
            }
        })

        cb({
            success = true,
            business = payload.business or business,
            items = items,
            mandatoryCharges = payload.mandatoryCharges or {},
            taxRate = payload.taxRate or 0.0,
            canEdit = payload.canEdit == true,
        })
    end, business)
end)

RegisterNUICallback('pos/close', function(data, cb)
    sendPfTabletMessage({ action = 'pos:close' })
    cb(true)
end)

RegisterNetEvent('mechanic:client:clearPosCart', function()
    sendPfTabletMessage({ action = 'pos:clearCart' })
end)

RegisterNetEvent('pf-mechanicjob:client:posPricingRefresh', function(business)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local playerBusiness = (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
    if business and business ~= playerBusiness then
        return
    end

    currentPosBusiness = playerBusiness
    QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
        local payload = resp or { business = playerBusiness, prices = {}, taxRate = 0.0, canEdit = false }
        sendPfTabletMessage({
            action = 'pos:open',
            data = {
                business = payload.business or playerBusiness,
                items = payload.prices or {},
                mandatoryCharges = payload.mandatoryCharges or {},
                taxRate = payload.taxRate or 0.0,
                canEdit = payload.canEdit == true,
            }
        })
    end, playerBusiness)
end)

RegisterNUICallback('pos/manage/get', function(data, cb)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local business = (data and data.business) or (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
    QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
        cb(resp or { business = business, prices = {}, taxRate = 0.0, canEdit = false })
    end, business)
end)

RegisterNUICallback('pos/manage/save', function(data, cb)
    QBCore.Functions.TriggerCallback('mechanic:server:savePriceEntry', function(ok, err)
        cb({ success = ok and true or false, error = err })
    end, data)
end)

RegisterNUICallback('pos/manage/delete', function(data, cb)
    QBCore.Functions.TriggerCallback('mechanic:server:deleteCustomEntry', function(ok, err)
        cb({ success = ok and true or false, error = err })
    end, data)
end)

RegisterNUICallback('pos/manage/deleteEntry', function(data, cb)
    QBCore.Functions.TriggerCallback('mechanic:server:deletePriceEntry', function(ok, err)
        cb({ success = ok and true or false, error = err })
    end, data)
end)

RegisterNUICallback('pos/manage/reset', function(data, cb)
    QBCore.Functions.TriggerCallback('mechanic:server:resetBusinessPricing', function(ok, err)
        cb({ success = ok and true or false, error = err })
    end, data)
end)

RegisterNUICallback('pos/manage/mandatoryAdd', function(data, cb)
    QBCore.Functions.TriggerCallback('mechanic:server:setMandatoryCharge', function(ok, err)
        cb({ success = ok and true or false, error = err })
    end, data)
end)

RegisterNUICallback('pos/manage/mandatoryRemove', function(data, cb)
    QBCore.Functions.TriggerCallback('mechanic:server:removeMandatoryCharge', function(ok, err)
        cb({ success = ok and true or false, error = err })
    end, data)
end)

local function getNearbyPlayers(radius)
    local players = {}
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    radius = radius or 5.0

    for _, pid in ipairs(GetActivePlayers()) do
        local target = GetPlayerPed(pid)
        if target ~= ped then
            local dist = #(GetEntityCoords(target) - pcoords)
            if dist <= radius then
                local sid = GetPlayerServerId(pid)
                players[#players + 1] = { serverId = sid, dist = dist }
            end
        end
    end
    table.sort(players, function(a, b) return a.dist < b.dist end)
    return players
end

RegisterNetEvent('pf-mechanicjob:client:tabletPosChargeTarget', function(payload)
    if not payload or not payload.target then return end
    
    -- Debounce: prevent duplicate charges from menu selection
    local now = GetGameTimer()
    if (now - lastChargeTime) < CHARGE_DEBOUNCE_MS then
        QBCore.Functions.Notify('Processing previous charge... please wait', 'info')
        return
    end
    lastChargeTime = now
    
    TriggerServerEvent('mechanic:server:chargeCustomer', {
        business = payload.business or currentPosBusiness or 'mechanic',
        customerId = payload.target,
        items = payload.cart or {},
        subtotal = payload.subtotal or 0,
        tax = payload.tax or 0,
        total = payload.total or 0,
        paymentType = payload.paymentType or 'cash'
    })
end)

RegisterNUICallback('pos/chargeRequest', function(data, cb)
    -- Debounce: prevent duplicate charge requests within 500ms
    local now = GetGameTimer()
    if (now - lastChargeTime) < CHARGE_DEBOUNCE_MS then
        cb(false)  -- Reject the duplicate request
        QBCore.Functions.Notify('Processing previous charge... please wait', 'info')
        return
    end
    lastChargeTime = now
    
    cb(true)

    local PlayerData = QBCore.Functions.GetPlayerData()
    local business = currentPosBusiness or (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'

    local cart = data and data.cart or {}
    local subtotal = tonumber(data and data.subtotal or 0) or 0
    local tax = tonumber(data and data.tax or 0) or 0
    local total = tonumber(data and data.total or 0) or 0
    local payType = (data and data.paymentType == 'card') and 'card' or 'cash'

    if data and data.chargeSelf then
        TriggerServerEvent('mechanic:server:chargeCustomer', {
            business = business,
            customerId = GetPlayerServerId(PlayerId()),
            items = cart,
            subtotal = subtotal,
            tax = tax,
            total = total,
            paymentType = payType
        })
        return
    end

    local nearby = getNearbyPlayers(5.0)
    if #nearby == 0 then
        QBCore.Functions.Notify('No players nearby to charge', 'error')
        return
    end

    local menu = {}
    for _, entry in ipairs(nearby) do
        menu[#menu + 1] = {
            header = ('ID %s | %.1fm'):format(entry.serverId, entry.dist),
            txt = 'Charge this player',
            params = {
                event = 'pf-mechanicjob:client:tabletPosChargeTarget',
                args = {
                    target = entry.serverId,
                    business = business,
                    cart = cart,
                    subtotal = subtotal,
                    tax = tax,
                    total = total,
                    paymentType = payType
                }
            }
        }
    end

    exports['pfm-menu']:openMenu(menu)
end)

RegisterNUICallback('pos/history/get', function(data, cb)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local business = (data and data.business) or currentPosBusiness or (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
    local limit = (data and data.limit) or 50
    QBCore.Functions.TriggerCallback('mechanic:server:getTransactionHistory', function(transactions)
        cb(transactions or {})
    end, business, limit)
end)

-- Settings
RegisterNUICallback('saveBusinessSettings', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:saveSettings', function(success)
        cb({ success = success })
    end, data)
end)

RegisterNUICallback('startPlacement', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mech:management:startPlacement', function(success)
        cb({ success = success })
    end, data.type, data.mode)
end)

-- Register command for testing
RegisterCommand('mechtablet', function()
    if isPlayerMechanic() then
        if tabletOpen then
            closeTablet()
        else
            openTablet()
        end
    else
        QBCore.Functions.Notify('You must be a mechanic to use this!', 'error')
    end
end)

-- Cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if tabletOpen then
        closeTablet()
    end
end)

if Config.Debug then
    print('[PF Mechanic] Tablet system loaded')
end

-- ============================================================================
-- Customer side of a register charge: the bill appears on the customer's screen and nothing is
-- charged until they press Pay (the server checks the answer and the charge again).
-- ============================================================================
local openBillId = nil

local function money(n)
    n = tonumber(n) or 0
    if n == math.floor(n) then return ('€%d'):format(n) end
    return ('€%.2f'):format(n)
end

RegisterNetEvent('mechanic:client:confirmCharge', function(bill)
    if type(bill) ~= 'table' or not bill.id then return end
    openBillId = bill.id

    local menu = {
        {
            header = ('Bill from %s'):format(tostring(bill.shopName or 'Mechanic')),
            txt = ('Charged by %s · pay within %ss'):format(tostring(bill.mechanicName or 'a mechanic'), tostring(bill.expiresIn or 60)),
            isMenuHeader = true,
        },
    }
    for _, line in ipairs(bill.items or {}) do
        menu[#menu + 1] = {
            header = ('%s x%s'):format(tostring(line.label or line.item), tostring(line.qty or 1)),
            txt = money(line.lineTotal),
            isMenuHeader = true,
        }
    end
    menu[#menu + 1] = {
        header = ('Total %s'):format(money(bill.total)),
        txt = ('Subtotal %s · tax %s · paid by %s'):format(money(bill.subtotal), money(bill.tax), bill.paymentType == 'card' and 'card' or 'cash'),
        isMenuHeader = true,
    }
    menu[#menu + 1] = {
        header = ('Pay %s'):format(money(bill.total)),
        params = { event = 'mechanic:client:answerCharge', args = { id = bill.id, accept = true } },
    }
    menu[#menu + 1] = {
        header = 'Decline',
        params = { event = 'mechanic:client:answerCharge', args = { id = bill.id, accept = false } },
    }

    exports['pfm-menu']:openMenu(menu)
end)

RegisterNetEvent('mechanic:client:answerCharge', function(args)
    if type(args) ~= 'table' or not args.id or args.id ~= openBillId then return end
    openBillId = nil
    TriggerServerEvent('mechanic:server:answerCharge', args.id, args.accept == true)
end)

-- the bill expired or was withdrawn: close it if it is still on screen
RegisterNetEvent('mechanic:client:chargeClosed', function(id)
    if id ~= openBillId then return end
    openBillId = nil
    pcall(function() exports['pfm-menu']:closeMenu() end)
    QBCore.Functions.Notify('The bill expired', 'error')
end)