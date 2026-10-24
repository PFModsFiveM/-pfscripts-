local QBCore = exports['pfm-core']:GetCoreObject()

-- Build and give the receipt
RegisterNetEvent('pf_mech:givePreviewReceipt', function(receiptData)
    local src = source
    if not receiptData then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local ts = tonumber(receiptData.timestamp) or os.time()
    local header = string.format('Preview Session - %s (%s)\n', receiptData.vehicle or 'Unknown', receiptData.plate or 'N/A')
    local desc = header ..
        string.format('Date: %s\n', os.date('%Y-%m-%d %H:%M:%S', ts)) ..
        string.format('Changes Made: %d\n\n', tonumber(receiptData.changeCount or 0) or 0)

    if type(receiptData.changes) == 'table' then
        for i, ch in ipairs(receiptData.changes) do
            desc = desc .. string.format('%d. %s\n', i, ch.name or 'Change')
            desc = desc .. string.format('   From: %s\n', ch.from or '—')
            desc = desc .. string.format('   To: %s\n', ch.to or '—')
        end
    end

    local info = {
        description = desc,
        vehicle = receiptData.vehicle,
        plate = receiptData.plate,
        timestamp = ts,
        changes = tonumber(receiptData.changeCount or 0) or 0
    }

    local itemName = Config.PreviewReceipt and Config.PreviewReceipt.itemName or 'preview_receipt'
    if not QBCore.Shared.Items[itemName] then
        print(('[pf-mechanicjob] Missing item in shared items: %s'):format(itemName))
        return
    end

    if Player.Functions.AddItem(itemName, 1, false, info) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add')
    end
end)

-- Make the item open the qb-menu viewer
QBCore.Functions.CreateUseableItem('preview_receipt', function(source, item)
    if not item or not item.info then return end
    TriggerClientEvent('pf_mech:previewReceipt:use', source, item.info)
end)
