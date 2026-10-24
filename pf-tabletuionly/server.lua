local QBCore = exports['pfm-core']:GetCoreObject()

-- ========================================
-- CASH REGISTER SERVER CALLBACKS
-- ========================================

QBCore.Functions.CreateCallback('pf-tabletuionly:getCashRegisterItems', function(source, cb)
    local items = {}
    local taxRate = 0.08
    
    -- Try to get items from pf-mechanicjob
    if Config and Config.RegisterItems then
        items = Config.RegisterItems
        
        -- Try to get tax rate from pf-mechanicjob
        if Config.DefaultTax then
            taxRate = Config.DefaultTax
        end
    else
        -- Fallback if pf-mechanicjob is not available
        -- You can add default items here if needed
        TriggerEvent('chat:addMessage', {
            args = {'Tablet UI', 'Warning: pf-mechanicjob config not found'},
            color = {255, 165, 0}
        })
    end
    
    cb({
        items = items,
        taxRate = taxRate
    })
end)

-- Handle cash register transactions
RegisterNetEvent('pf-tabletuionly:processCashRegisterTransaction', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then
        TriggerClientEvent('chat:addMessage', src, {
            args = {'Tablet UI', 'Error: Player not found'},
            color = {255, 0, 0}
        })
        return
    end
    
    -- Check if player has mechanic job
    if not (Player.PlayerData.job.name == 'mechanic' or 
            Player.PlayerData.job.name == 'mechanic2' or 
            Player.PlayerData.job.name == 'mechanic3' or
            Player.PlayerData.job.name == 'bennys' or
            Player.PlayerData.job.name == 'beeker') then
        TriggerClientEvent('chat:addMessage', src, {
            args = {'Tablet UI', 'You are not authorized to use the cash register'},
            color = {255, 0, 0}
        })
        return
    end
    
    -- Log the transaction (can be extended to save to database)
    local itemsLog = {}
    for i, item in ipairs(data.items or {}) do
        table.insert(itemsLog, string.format('%sx%d (%s)', item.label, item.quantity, item.item))
    end
    
    TriggerEvent('chat:addMessage', {
        args = {'Cash Register', string.format('Transaction: $%.2f (Tax: $%.2f)', data.total, data.tax)},
        color = {0, 255, 0}
    })
    
    -- Deposit to pf-computer company account if available
    local jobName = Player.PlayerData.job.name
    if GetResourceState('pf-computer') == 'started' then
        local ok = pcall(function()
            exports['pf-computer']:DepositSale(jobName, data.total, 'Tablet Cash Register - $' .. string.format('%.2f', data.total))
        end)
    end
    
    -- You can add additional logic here:
    -- - Save transaction to database
    -- - Issue items to inventory
    -- - Send money to business account
    -- - Log audit trail
    print('^2[pf-tabletuionly]^7 Cash Register Transaction by ' .. Player.PlayerData.name .. ' (Citizen ID: ' .. Player.PlayerData.citizenid .. ')')
    print('  Items: ' .. table.concat(itemsLog, ', '))
    print('  Subtotal: $' .. string.format('%.2f', data.subtotal))
    print('  Tax: $' .. string.format('%.2f', data.tax))
    print('  Total: $' .. string.format('%.2f', data.total))
end)
