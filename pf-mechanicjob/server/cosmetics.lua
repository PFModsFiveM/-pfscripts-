local QBCore = exports['pfm-core']:GetCoreObject()

RegisterNetEvent('pf-mechanicjob:server:removeMod', function(itemName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    Player.Functions.RemoveItem(itemName, 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
end)

-- Apply window tint (consume item and sync to all clients)
RegisterNetEvent('pf_mech:server:applyTint', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Check if player has tint_supplies
    local item = Player.Functions.GetItemByName('tint_supplies')
    if not item or (item.amount or 0) < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'You need tint supplies', 'error')
        return
    end

    -- Consume item
    if Player.Functions.RemoveItem('tint_supplies', 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['tint_supplies'], "remove")
        
        -- Broadcast to all players to apply tint
        TriggerClientEvent('pf_mech:client:syncVehicleTint', -1, data.vehicle, data.tintLevel)
        
        if Config.Debug then
            print(string.format('[TINT] Applied level %d to vehicle %d by player %d', data.tintLevel or 0, data.vehicle, src))
        end
    else
        TriggerClientEvent('QBCore:Notify', src, 'Failed to consume item', 'error')
    end
end)

-- Apply paint (consume item and sync to all clients)
RegisterNetEvent('pf_mech:server:applyPaint', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Check if player has paintcan
    local item = Player.Functions.GetItemByName('paintcan')
    if not item or (item.amount or 0) < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'You need a paintcan', 'error')
        return
    end

    -- Consume item
    if Player.Functions.RemoveItem('paintcan', 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['paintcan'], "remove")
        
        -- Broadcast to all players to apply paint (client-side only)
        TriggerClientEvent('pf_mech:client:syncVehiclePaint', -1, data)
        
        if Config.Debug then
            print(string.format('[PAINT] Applied %s %s paint to vehicle %d by player %d', data.colorType or 'classic', data.paintType or 'primary', data.vehicle, src))
        end
    else
        TriggerClientEvent('QBCore:Notify', src, 'Failed to consume item', 'error')
    end
end)
