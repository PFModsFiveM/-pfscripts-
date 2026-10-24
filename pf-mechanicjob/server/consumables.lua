local QBCore = exports['pfm-core']:GetCoreObject()

QBCore.Functions.CreateCallback('pf-mechanicjob:server:consumeBrakePad', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end

    local item = Player.Functions.GetItemByName('brake_pads')
    if not item or (item.amount or 0) < 1 then
        cb(false)
        return
    end

    local removed = Player.Functions.RemoveItem('brake_pads', 1)
    if removed then
        -- show UI box on client
        if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items['brake_pads'] then
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items['brake_pads'], 'remove', 1)
        end
        cb(true)
    else
        cb(false)
    end
end)

-- Generic item consumption callback
QBCore.Functions.CreateCallback('pf-mechanicjob:server:consumeItem', function(source, cb, itemName)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end

    local item = Player.Functions.GetItemByName(itemName)
    if not item or (item.amount or 0) < 1 then
        cb(false)
        return
    end

    local removed = Player.Functions.RemoveItem(itemName, 1)
    if removed then
        if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[itemName], 'remove', 1)
        end
        cb(true)
    else
        cb(false)
    end
end)
