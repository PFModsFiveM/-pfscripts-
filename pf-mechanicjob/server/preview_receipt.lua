local QBCore = exports['pfm-core']:GetCoreObject()

-- Build and give the receipt
-- One receipt per player every few seconds, with bounded text: the receipt is built from client data
-- and stored in the inventory, so it used to be an unlimited item spawner with unbounded strings.
local lastReceipt = {}
local RECEIPT_COOLDOWN = 10

local function str(v, max) return tostring(v or ''):sub(1, max) end

RegisterNetEvent('pf_mech:givePreviewReceipt', function(receiptData)
    local src = source
    if type(receiptData) ~= 'table' then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local now = os.time()
    if lastReceipt[src] and now - lastReceipt[src] < RECEIPT_COOLDOWN then return end
    lastReceipt[src] = now

    local ts = os.time()
    local vehicleName, plate = str(receiptData.vehicle, 40), str(receiptData.plate, 8)
    local header = string.format('Preview Session - %s (%s)\n', vehicleName ~= '' and vehicleName or 'Unknown', plate ~= '' and plate or 'N/A')
    local desc = header ..
        string.format('Date: %s\n', os.date('%Y-%m-%d %H:%M:%S', ts)) ..
        string.format('Changes Made: %d\n\n', math.floor(math.max(0, math.min(tonumber(receiptData.changeCount or 0) or 0, 999))))

    if type(receiptData.changes) == 'table' then
        for i, ch in ipairs(receiptData.changes) do
            if i > 50 then break end
            if type(ch) == 'table' then
                desc = desc .. string.format('%d. %s\n', i, str(ch.name or 'Change', 60))
                desc = desc .. string.format('   From: %s\n', str(ch.from or '—', 60))
                desc = desc .. string.format('   To: %s\n', str(ch.to or '—', 60))
            end
        end
    end

    local info = {
        description = desc,
        vehicle = vehicleName,
        plate = plate,
        timestamp = ts,
        changes = math.floor(math.max(0, math.min(tonumber(receiptData.changeCount or 0) or 0, 999)))
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
