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

local MySQL = MySQL

local function EnsureMySQL()
    if not MySQL or (not MySQL.query and not MySQL.insert and not MySQL.update) then
        print("^1[Outfit Bag] MySQL library not available. Ensure oxmysql is started before pf-outfitbag.^7")
        return false
    end
    return true
end

-- Get player object (framework agnostic)
local function GetPlayer(source)
    if Framework == 'qbcore' then
        return QBCore.Functions.GetPlayer(source)
    else -- ESX
        return ESX.GetPlayerFromId(source)
    end
end

-- =============================================
-- DATABASE FUNCTIONS
-- =============================================

-- Get all outfits for a specific bag
local function GetBagOutfits(bagId)
    if not EnsureMySQL() then return {} end
    local result = MySQL.query.await('SELECT * FROM outfitbag_outfits WHERE bag_id = ? ORDER BY id ASC', {bagId})
    return result or {}
end

-- Save outfit to database
local function SaveOutfit(bagId, outfitName, outfitData)
    if not EnsureMySQL() then return false end
    local success = MySQL.insert.await('INSERT INTO outfitbag_outfits (bag_id, outfit_name, outfit_data) VALUES (?, ?, ?)', {
        bagId,
        outfitName,
        json.encode(outfitData)
    })
    return success
end

-- Delete outfit from database
local function DeleteOutfit(outfitId)
    if not EnsureMySQL() then return false end
    local success = MySQL.query.await('DELETE FROM outfitbag_outfits WHERE id = ?', {outfitId})
    return success
end

-- Rename outfit in database
local function RenameOutfit(outfitId, newName)
    if not EnsureMySQL() then return false end
    local success = MySQL.update.await('UPDATE outfitbag_outfits SET outfit_name = ? WHERE id = ?', {newName, outfitId})
    return success
end

-- =============================================
-- SERVER CALLBACKS
-- =============================================

-- Get outfits for a bag (framework agnostic)
if Framework == 'qbcore' then
    QBCore.Functions.CreateCallback('pf-outfitbag:getOutfits', function(source, cb, bagId)
        local outfits = GetBagOutfits(bagId)
        local formattedOutfits = {}
        
        for i, outfit in ipairs(outfits) do
            table.insert(formattedOutfits, {
                id = outfit.id,
                name = outfit.outfit_name,
                data = json.decode(outfit.outfit_data)
            })
        end
        
        cb(formattedOutfits)
    end)
else -- ESX
    ESX.RegisterServerCallback('pf-outfitbag:getOutfits', function(source, cb, bagId)
        local outfits = GetBagOutfits(bagId)
        local formattedOutfits = {}
        
        for i, outfit in ipairs(outfits) do
            table.insert(formattedOutfits, {
                id = outfit.id,
                name = outfit.outfit_name,
                data = json.decode(outfit.outfit_data)
            })
        end
        
        cb(formattedOutfits)
    end)
end

-- Save outfit to bag
RegisterNetEvent('pf-outfitbag:saveOutfit')
AddEventHandler('pf-outfitbag:saveOutfit', function(bagId, outfitName, outfitData)
    local src = source
    
    if not bagId or not outfitName or not outfitData then
        return
    end
    
    local success = SaveOutfit(bagId, outfitName, outfitData)
    
    if success then
        -- Send updated outfit list back to client
        local outfits = GetBagOutfits(bagId)
        local formattedOutfits = {}
        for i, outfit in ipairs(outfits) do
            table.insert(formattedOutfits, {
                id = outfit.id,
                name = outfit.outfit_name,
                data = json.decode(outfit.outfit_data)
            })
        end
        TriggerClientEvent('pf-outfitbag:updateOutfits', src, formattedOutfits)
    end
end)

-- Delete outfit from bag
RegisterNetEvent('pf-outfitbag:deleteOutfit')
AddEventHandler('pf-outfitbag:deleteOutfit', function(bagId, outfitId)
    local src = source
    
    if not bagId or not outfitId then
        return
    end
    
    local success = DeleteOutfit(outfitId)
    
    if success then
        -- Send updated outfit list back to client
        local outfits = GetBagOutfits(bagId)
        local formattedOutfits = {}
        for i, outfit in ipairs(outfits) do
            table.insert(formattedOutfits, {
                id = outfit.id,
                name = outfit.outfit_name,
                data = json.decode(outfit.outfit_data)
            })
        end
        TriggerClientEvent('pf-outfitbag:updateOutfits', src, formattedOutfits)
    end
end)

-- Rename outfit in bag
RegisterNetEvent('pf-outfitbag:renameOutfit')
AddEventHandler('pf-outfitbag:renameOutfit', function(bagId, outfitId, newName)
    local src = source
    
    if not bagId or not outfitId or not newName then
        return
    end
    
    local success = RenameOutfit(outfitId, newName)
    
    if success then
        -- Send updated outfit list back to client
        local outfits = GetBagOutfits(bagId)
        local formattedOutfits = {}
        for i, outfit in ipairs(outfits) do
            table.insert(formattedOutfits, {
                id = outfit.id,
                name = outfit.outfit_name,
                data = json.decode(outfit.outfit_data)
            })
        end
        TriggerClientEvent('pf-outfitbag:updateOutfits', src, formattedOutfits)
    end
end)

-- =============================================
-- INVENTORY MANAGEMENT
-- =============================================

-- Remove item from inventory (with metadata preservation)
RegisterNetEvent('pf-outfitbag:removeItem')
AddEventHandler('pf-outfitbag:removeItem', function(bagId)
    local src = source
    local Player = GetPlayer(src)
    
    if not Player then return end
    
    if Framework == 'qbcore' then
        -- QBCore inventory handling
        local inventory = Player.PlayerData.items
        local itemSlot = nil
        
        for slot, item in pairs(inventory) do
            if item and item.name == Config.ItemName then
                if type(item.info) == 'table' and item.info.bag_id == bagId then
                    itemSlot = slot
                    break
                end
            end
        end
        
        if itemSlot then
            Player.Functions.RemoveItem(Config.ItemName, 1, itemSlot)
        else
            Player.Functions.RemoveItem(Config.ItemName, 1)
        end
    else -- ESX
        -- ESX inventory handling
        if Config.Inventory == 'ox_inventory' then
            -- ox_inventory with metadata
            local items = exports.ox_inventory:Search(src, 'slots', Config.ItemName)
            for _, item in pairs(items) do
                if item.metadata and item.metadata.bag_id == bagId then
                    exports.ox_inventory:RemoveItem(src, Config.ItemName, 1, item.metadata, item.slot)
                    break
                end
            end
        else
            Player.removeInventoryItem(Config.ItemName, 1)
        end
    end

end)

-- Add item back to inventory (with metadata)
RegisterNetEvent('pf-outfitbag:addItem')
AddEventHandler('pf-outfitbag:addItem', function(bagId)
    local src = source
    local Player = GetPlayer(src)
    
    if not Player then return end
    
    if Framework == 'qbcore' then
        local info = {
            bag_id = bagId
        }
        
        local item = Player.Functions.AddItem(Config.ItemName, 1, nil, info)
        
        if item then
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.ItemName], "add", 1)
        end
    else -- ESX
        if Config.Inventory == 'ox_inventory' then
            -- ox_inventory with metadata
            local metadata = {
                bag_id = bagId,
                description = 'Outfit Bag #' .. string.sub(bagId, 1, 8)
            }
            exports.ox_inventory:AddItem(src, Config.ItemName, 1, metadata)
        else
            Player.addInventoryItem(Config.ItemName, 1)
        end
    end
end)

