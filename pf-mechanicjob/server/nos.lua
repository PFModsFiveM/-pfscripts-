local QBCore = exports['pfm-core']:GetCoreObject()

local FULL_ITEM  = (Config.NOS and Config.NOS.items.full)  or 'nos'
local EMPTY_ITEM = (Config.NOS and Config.NOS.items.empty) or 'emptynos'
local CAPACITY   = (Config.NOS and Config.NOS.capacity) or 100

-- Useable NOS bottle -> client install
QBCore.Functions.CreateUseableItem(FULL_ITEM, function(src)
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end
    local itm = Player.Functions.GetItemByName(FULL_ITEM)
    if not itm or (itm.amount or 0) < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'No NOS bottle found', 'error')
        return
    end
    TriggerClientEvent('pf_mech:nos:install', src)
end)

-- Empty bottles owed per character: one for each full bottle the server took. The empty used to
-- be handed out on request, as often as a client asked.
local EmptyOwed = {}

local function takeOwedEmpty(Player)
    local cid = Player.PlayerData.citizenid
    if (EmptyOwed[cid] or 0) < 1 then return false end
    EmptyOwed[cid] = EmptyOwed[cid] - 1
    return true
end

-- The car the player is sitting in (if plate is given, only when its plate matches).
local function occupiedVehicle(src, plate)
    local ped = GetPlayerPed(src)
    local veh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    if plate and (tostring(GetVehicleNumberPlateText(veh) or ''):gsub('%s+', ''):upper()) ~= plate then return nil end
    return veh
end

local NOS_WEAR_PARTS = { engine_part = true, sparkplugs = true, fuel_injector = true, oil = true, axle = true }

-- Consume after successful install
RegisterNetEvent('pf_mech:nos:consumeBottle', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end
    if Player.Functions.RemoveItem(FULL_ITEM, 1) then
        local cid = Player.PlayerData.citizenid
        EmptyOwed[cid] = (EmptyOwed[cid] or 0) + 1
        local itm = QBCore.Shared.Items[FULL_ITEM]
        if itm then TriggerClientEvent('inventory:client:ItemBox', src, itm, 'remove', 1) end
    end
end)

-- SIMPLIFIED: Give empty when depleted (no debounce)
RegisterNetEvent('pf_mech:nos:giveEmpty', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        if Config.Debug then
            print(string.format('[NOS SERVER] ERROR: Player %d not found', src))
        end
        return
    end
    
    -- Check if emptynos item exists
    if not QBCore.Shared.Items[EMPTY_ITEM] then
        if Config.Debug then
            print(string.format('[NOS SERVER] ERROR: Item "%s" not found in QBCore.Shared.Items', EMPTY_ITEM))
        end
        TriggerClientEvent('QBCore:Notify', src, 'Empty bottle item not configured', 'error')
        return
    end
    
    if not takeOwedEmpty(Player) then return end

    -- Give empty bottle
    local success = Player.Functions.AddItem(EMPTY_ITEM, 1)

    if success then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[EMPTY_ITEM], 'add', 1)
        TriggerClientEvent('QBCore:Notify', src, 'Received empty NOS bottle', 'success', 3000)
        
        if Config.Debug then
            print(string.format('[NOS SERVER] ✅ Gave empty bottle to player %d', src))
        end
    else
        if Config.Debug then
            print(string.format('[NOS SERVER] ❌ Failed to give empty bottle to player %d (inventory full?)', src))
        end
        EmptyOwed[Player.PlayerData.citizenid] = (EmptyOwed[Player.PlayerData.citizenid] or 0) + 1
        TriggerClientEvent('QBCore:Notify', src, 'Could not receive empty bottle (inventory full?)', 'error')
    end
end)

-- Update level (sync from client)
-- Only from someone in that car, and only down: the level falls as the bottle is used.
RegisterNetEvent('pf_mech:nos:updateLevel', function(netId, level)
    local src = source
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if occupiedVehicle(src) ~= veh then return end

    local st = Entity(veh).state.nos
    if not st then return end

    level = tonumber(level)
    if not level or level ~= level then return end
    st.level = math.max(0, math.min(tonumber(st.level) or 0, CAPACITY, level))
    Entity(veh).state:set('nos', st, true)
end)

-- NEW: Apply accumulated damage from client
RegisterNetEvent('pf_mech:nos:applyDamage', function(plate, damage)
    local src = source
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' or type(damage) ~= 'table' then return end
    -- Only the car the sender sits in, and only added wear on the parts NOS wears out. Any plate
    -- and any (negative) number used to be taken: a free repair, or damage to anyone's car.
    if not occupiedVehicle(src, plate) then return end

    -- Find vehicle by plate
    local vehicles = GetAllVehicles()
    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            local vehPlate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
            if vehPlate == plate then
                -- Apply accumulated damage to state
                local state = Entity(veh).state
                local partDamage = state.partDamage or {}
                
                for key, dmg in pairs(damage) do
                    dmg = tonumber(dmg)
                    if NOS_WEAR_PARTS[key] and dmg and dmg == dmg and dmg > 0 then
                        partDamage[key] = math.min(100, (tonumber(partDamage[key]) or 0) + math.min(dmg, 100))
                    end
                end
                
                state:set('partDamage', partDamage, true)
                
                if Config.Debug then
                    print(string.format('[NOS SERVER] Applied damage to %s: engine=%.2f%% spark=%.2f%%', 
                        plate, 
                        partDamage.engine_part or 0,
                        partDamage.sparkplugs or 0))

                -- NEW: Remove empty NOS bottle (give emptynos item, clear state)
                RegisterNetEvent('pf_mech:nos:removeEmpty', function(netId)
                    local src = source
                    local Player = QBCore.Functions.GetPlayer(src)
                    if not Player then return end
    
                    local veh = NetworkGetEntityFromNetworkId(netId or 0)
                    if veh == 0 or not DoesEntityExist(veh) then
                        TriggerClientEvent('QBCore:Notify', src, 'Vehicle not found', 'error')
                        return
                    end
    
                    local nosState = Entity(veh).state.nos
                    if not nosState or not nosState.has then
                        TriggerClientEvent('QBCore:Notify', src, 'No NOS installed', 'error')
                        return
                    end
    
                    local nosLevel = tonumber(nosState.level) or 0
                    if nosLevel > 0 then
                        TriggerClientEvent('QBCore:Notify', src, 'NOS bottle is not empty yet', 'error')
                        return
                    end
    
                    -- Check if emptynos item exists
                    if not QBCore.Shared.Items[EMPTY_ITEM] then
                        TriggerClientEvent('QBCore:Notify', src, 'Empty bottle item not configured', 'error')
                        return
                    end
    
                    if not takeOwedEmpty(Player) then return end

                    -- Give empty bottle
                    local success = Player.Functions.AddItem(EMPTY_ITEM, 1)
                    if not success then
                        TriggerClientEvent('QBCore:Notify', src, 'Could not receive empty bottle (inventory full?)', 'error')
                        return
                    end
    
                    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[EMPTY_ITEM], 'add', 1)
    
                    -- Clear NOS state
                    Entity(veh).state:set('nos', nil, true)
    
                    TriggerClientEvent('QBCore:Notify', src, 'Empty NOS bottle removed', 'success', 3000)
    
                    if Config.Debug then
                        local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
                        print(string.format('[NOS SERVER] ✅ Removed empty bottle from %s (player %d)', plate, src))
                    end
                end)
                end
                
                return
            end
        end
    end
end)
