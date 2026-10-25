-- Item Use Handler for Outfit Bag
-- Supports both QBCore and ESX frameworks

-- Framework detection
local Framework = Config.Framework:lower()
local QBCore, ESX = nil, nil

if Framework == 'qbcore' then
    QBCore = exports['pfm-core']:GetCoreObject()
elseif Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
else
    print("^1[Outfit Bag] Invalid framework in config: " .. Config.Framework .. "^7")
    return
end

-- Generate unique UUID for bag
local function GenerateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

if Framework == 'qbcore' then
    -- QBCore item registration
    QBCore.Functions.CreateUseableItem(Config.ItemName, function(source, item)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        
        -- Generate or use existing bag ID from metadata
        local bagId = nil
        local info = item.info
        if type(info) == 'string' then
            local decoded = json.decode(info)
            if type(decoded) == 'table' then
                info = decoded
            end
        end
        if type(info) ~= 'table' then
            info = {}
        end
        bagId = info.bag_id
        if not bagId then
            bagId = GenerateUUID()
            info.bag_id = bagId
        end

        -- Remove the item from inventory on use
        if item.slot then
            Player.Functions.RemoveItem(Config.ItemName, 1, item.slot)
        else
            Player.Functions.RemoveItem(Config.ItemName, 1)
        end
        
        -- Send bag ID to client
        PlacedOutfitBags[source] = PlacedOutfitBags[source] or {}
        PlacedOutfitBags[source][bagId] = true
        TriggerClientEvent('pf-outfitbag:placeBag', source, bagId)
    end)

    CreateThread(function()
        Wait(500)
        if not QBCore.Shared.Items[Config.ItemName] then
            print("^1[Outfit Bag] Item '" .. Config.ItemName .. "' not found in QBCore.Shared.Items^7")
        else
            print("^2[Outfit Bag] QBCore - Useable item registered: " .. Config.ItemName .. "^7")
        end
    end)

elseif Framework == 'esx' then
    -- ESX item registration
    ESX.RegisterUsableItem(Config.ItemName, function(source)
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return end
        
        -- Generate or use existing bag ID from metadata
        local item = xPlayer.getInventoryItem(Config.ItemName)
        if not item or item.count < 1 then return end
        
        -- For ESX with ox_inventory, try to get metadata
        local bagId = nil
        if Config.Inventory == 'ox_inventory' and item.metadata and item.metadata.bag_id then
            bagId = item.metadata.bag_id
        else
            bagId = GenerateUUID()
        end
        
        -- Remove the item from inventory on use
        xPlayer.removeInventoryItem(Config.ItemName, 1)
        
        -- Send bag ID to client
        PlacedOutfitBags[source] = PlacedOutfitBags[source] or {}
        PlacedOutfitBags[source][bagId] = true
        TriggerClientEvent('pf-outfitbag:placeBag', source, bagId)
    end)
    
    print("^2[Outfit Bag] ESX - Useable item registered: " .. Config.ItemName .. "^7")
end
