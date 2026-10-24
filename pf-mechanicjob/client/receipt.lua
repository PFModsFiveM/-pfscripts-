local receiptOpen = false

local function openReceiptUi(info)
    if receiptOpen then
        SendNUIMessage({ action = 'showPosReceipt', payload = info or {} })
        return
    end

    receiptOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showPosReceipt', payload = info or {} })
end

local function closeReceiptUi()
    if not receiptOpen then return end

    receiptOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hidePosReceipt' })
end

RegisterNetEvent('pf_mech:receipt:use', function(info)
    openReceiptUi(info)
end)

RegisterNUICallback('receipt/close', function(_, cb)
    closeReceiptUi()
    cb(true)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if receiptOpen then
        SetNuiFocus(false, false)
    end
end)
