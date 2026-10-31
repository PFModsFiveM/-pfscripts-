-- client/register_pos.lua
-- Additive POS client glue. Keeps existing tablet/work-order flows intact.

local QBCore = exports['pfm-core']:GetCoreObject()
local currentPosState = {
    business = nil,
    items = {},
    taxRate = 0.0,
}

local function sendPosMessage(payload)
    if not payload then return end

    if GetResourceState('pf-tablet') == 'started'
        and exports
        and exports['pf-tablet']
        and exports['pf-tablet'].SendNuiMessage then
        PFMechShell(payload)
        return
    end

    SendNUIMessage(payload)
end

-- Helper: open NUI with payload
local function openPos(payload)
    currentPosState = payload or currentPosState
    sendPosMessage({ action = 'pos:open', data = currentPosState })
end

-- Event: server asks client to open register
RegisterNetEvent('mechanic:client:openRegister', function(payload)
    if not payload then return end
    openPos(payload)
end)

local useStandalonePosNui = GetResourceState('pf-tablet') ~= 'started'
if useStandalonePosNui then
    -- NUI: request to open register (from app click)
    RegisterNUICallback('pos/open', function(data, cb)
        local PlayerData = QBCore.Functions.GetPlayerData()
        local business = (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
        QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
            local payload = resp or { business = business, prices = {}, taxRate = 0.0, canEdit = false }
            currentPosState.business = payload.business or business
            currentPosState.items = payload.prices or {}
            currentPosState.taxRate = payload.taxRate or 0.0

            sendPosMessage({
                action = 'pos:open',
                data = {
                    business = currentPosState.business,
                    items = currentPosState.items,
                    taxRate = currentPosState.taxRate,
                    canEdit = payload.canEdit == true,
                }
            })

            cb({
                success = true,
                business = currentPosState.business,
                items = currentPosState.items,
                taxRate = currentPosState.taxRate,
                canEdit = payload.canEdit == true,
            })
        end, business)
    end)

-- NUI: close register window
    RegisterNUICallback('pos/close', function(_, cb)
        -- Do not close tablet entirely; just clear POS state
        sendPosMessage({ action = 'pos:close' })
        cb(true)
    end)

-- Event: clear cart after successful charge
RegisterNetEvent('mechanic:client:clearPosCart', function()
    sendPosMessage({ action = 'pos:clearCart' })
end)

    RegisterNetEvent('pf-mechanicjob:client:posPricingRefresh', function(business)
        local PlayerData = QBCore.Functions.GetPlayerData()
        local playerBusiness = (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
        if business and business ~= playerBusiness then
            return
        end

        QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
            local payload = resp or { business = playerBusiness, prices = {}, taxRate = 0.0, canEdit = false }
            currentPosState.business = payload.business or playerBusiness
            currentPosState.items = payload.prices or {}
            currentPosState.taxRate = payload.taxRate or 0.0

            sendPosMessage({
                action = 'pos:open',
                data = {
                    business = currentPosState.business,
                    items = currentPosState.items,
                    taxRate = currentPosState.taxRate,
                    canEdit = payload.canEdit == true,
                }
            })
        end, playerBusiness)
    end)

-- Build nearby player list
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

-- NUI: charge request -> choose nearby player then send to server
    RegisterNUICallback('pos/chargeRequest', function(data, cb)
        cb(true)

    -- Check if charging self FIRST
    if data and data.chargeSelf then
        local cart = data.cart or {}
        local subtotal = tonumber(data.subtotal) or 0
        local tax = tonumber(data.tax) or 0
        local total = tonumber(data.total) or 0
        local payType = data.paymentType == 'card' and 'card' or 'cash'
        TriggerServerEvent('mechanic:server:chargeCustomer', {
            business = currentPosState.business or 'mechanic',
            customerId = GetPlayerServerId(PlayerId()),
            items = cart,
            subtotal = subtotal,
            tax = tax,
            total = total,
            paymentType = payType
        })
        return
    end

    local cart = data and data.cart or {}
    local subtotal = tonumber(data.subtotal) or 0
    local tax = tonumber(data.tax) or 0
    local total = tonumber(data.total) or 0
    local payType = data.paymentType == 'card' and 'card' or 'cash'

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
                event = 'mechanic:client:posConfirmCharge',
                args = {
                    target = entry.serverId,
                    cart = cart,
                    subtotal = subtotal,
                    tax = tax,
                    total = total,
                    paymentType = payType,
                    business = currentPosState.business or 'mechanic'
                }
            }
        }
    end

        exports['pfm-menu']:openMenu(menu)
    end)

-- Management: fetch price list
    RegisterNUICallback('pos/manage/get', function(data, cb)
        local PlayerData = QBCore.Functions.GetPlayerData()
        local business = data and data.business or (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
        QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
            cb(resp or {})
        end, business)
    end)

-- Management: save/override entry (base or custom)
    RegisterNUICallback('pos/manage/save', function(data, cb)
        QBCore.Functions.TriggerCallback('mechanic:server:savePriceEntry', function(ok, err)
            cb({ success = ok and true or false, error = err })
        end, data)
    end)

-- Management: delete custom entry
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

-- Transaction History: fetch transactions
    RegisterNUICallback('pos/history/get', function(data, cb)
        local PlayerData = QBCore.Functions.GetPlayerData()
        local business = data and data.business or (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
        local limit = data and data.limit or 50
        QBCore.Functions.TriggerCallback('mechanic:server:getTransactionHistory', function(transactions)
            cb(transactions or {})
        end, business, limit)
    end)

-- Get customer name by player ID
    RegisterNUICallback('pos/getCustomerName', function(data, cb)
        local customerId = data.customerId
        if not customerId then
            return cb({ name = 'Unknown' })
        end

        QBCore.Functions.TriggerCallback('mechanic:server:getPlayerName', function(playerName)
            cb({ name = playerName or 'Unknown' })
        end, customerId)
    end)

-- Handler invoked from menu selection
    RegisterNetEvent('mechanic:client:posConfirmCharge', function(payload)
        if not payload or not payload.target then return end

        TriggerServerEvent('mechanic:server:chargeCustomer', {
            business = payload.business or currentPosState.business or 'mechanic',
            customerId = payload.target,
            items = payload.cart or {},
            subtotal = payload.subtotal or 0,
            tax = payload.tax or 0,
            total = payload.total or 0,
            paymentType = payload.paymentType or 'cash'
        })
    end)
end
