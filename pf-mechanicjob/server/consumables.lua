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

-- A tyre taken by consumeItem may be fitted once, to a wheel of a car beside the player, after the
-- 4 s replacement bar (partDamage is server-set, sv_stateBagStrictMode).
local TireUsedAt = {}   -- [src] = os.time() a tire_new was taken
local TIRE_KEYS = { [0] = 'lf', [1] = 'rf', [2] = 'lr', [3] = 'rr', [4] = 'lm', [5] = 'rm' }

RegisterNetEvent('pf_mech:server:tireReplaced', function(netId, wheel)
    local src = source
    wheel = tonumber(wheel)
    local usedAt = TireUsedAt[src]
    if not usedAt or not wheel or wheel ~= math.floor(wheel) or wheel < 0 or wheel > 7 then return end
    local elapsed = os.time() - usedAt
    if elapsed < 3 or elapsed > 120 then return end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 6.0 then return end
    TireUsedAt[src] = nil
    -- the car's saved wear first, or a later load would undo the new tyre
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local st = Entity(veh).state
    local pd = type(st.partDamage) == 'table' and st.partDamage or {}
    pd.tires = type(pd.tires) == 'table' and pd.tires or {}
    pd.tires[TIRE_KEYS[wheel] or tostring(wheel)] = 0
    st:set('partDamage', pd, true)
end)

AddEventHandler('playerDropped', function() TireUsedAt[source] = nil end)

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
        if itemName == 'tire_new' then TireUsedAt[source] = os.time() end
        if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[itemName], 'remove', 1)
        end
        cb(true)
    else
        cb(false)
    end
end)
