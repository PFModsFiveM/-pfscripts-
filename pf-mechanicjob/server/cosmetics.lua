local QBCore = exports['pfm-core']:GetCoreObject()

-- Paint and tint use public items (paintcan, tint_supplies): anyone may apply them, to a car they
-- stand at with the engine off. Every client applies the result, so only values from fixed ranges
-- are sent on (the whole client payload, any car, used to be relayed).
local REACH = 8.0
local PAINT_TYPES = { primary = true, secondary = true, pearlescent = true, wheel = true }
local COLOR_TYPES = { classic = true, chameleon = true }
local FINISHES = { classic = true, metallic = true, matte = true, metals = true, util = true, chameleon = true }
local COLOR_MAX = 242   -- highest GTA paint index, chameleon paints included
local TINT_MAX = 6

local function carAt(src, netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > REACH then return nil end
    if GetIsVehicleEngineRunning(veh) then return nil end
    return veh
end

local function int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

RegisterNetEvent('pf-mechanicjob:server:removeMod', function(itemName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(itemName) ~= 'string' then return end

    if Player.Functions.RemoveItem(itemName, 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
    end
end)

-- Apply window tint (consume item and sync to all clients)
RegisterNetEvent('pf_mech:server:applyTint', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' then return end
    local tint = int(data.tintLevel, 0, TINT_MAX)
    if not tint then return end
    local veh = carAt(src, data.vehicle)
    if not veh then
        TriggerClientEvent('QBCore:Notify', src, 'Stand at the car with its engine off', 'error')
        return
    end

    local item = Player.Functions.GetItemByName('tint_supplies')
    if not item or (item.amount or 0) < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'You need tint supplies', 'error')
        return
    end

    if Player.Functions.RemoveItem('tint_supplies', 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['tint_supplies'], "remove")
        TriggerClientEvent('pf_mech:client:syncVehicleTint', -1, NetworkGetNetworkIdFromEntity(veh), tint)
    else
        TriggerClientEvent('QBCore:Notify', src, 'Failed to consume item', 'error')
    end
end)

-- Apply paint (consume item and sync to all clients)
RegisterNetEvent('pf_mech:server:applyPaint', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' then return end
    local paintType = PAINT_TYPES[data.paintType] and data.paintType or nil
    local colorType = COLOR_TYPES[data.colorType] and data.colorType or nil
    local colorId = int(data.colorId, 0, COLOR_MAX)
    local finish = data.finish
    if finish ~= nil and not FINISHES[finish] then return end
    if not paintType or not colorType or not colorId then return end
    local veh = carAt(src, data.vehicle)
    if not veh then
        TriggerClientEvent('QBCore:Notify', src, 'Stand at the car with its engine off', 'error')
        return
    end

    local item = Player.Functions.GetItemByName('paintcan')
    if not item or (item.amount or 0) < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'You need a paintcan', 'error')
        return
    end

    if Player.Functions.RemoveItem('paintcan', 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['paintcan'], "remove")
        TriggerClientEvent('pf_mech:client:syncVehiclePaint', -1, {
            vehicle = NetworkGetNetworkIdFromEntity(veh),
            paintType = paintType,
            colorType = colorType,
            colorId = colorId,
            finish = finish,
        })
    else
        TriggerClientEvent('QBCore:Notify', src, 'Failed to consume item', 'error')
    end
end)
