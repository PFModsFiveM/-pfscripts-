local QBCore = exports['pfm-core']:GetCoreObject()

-- Every client applies these changes to the car, so the sender must be at that car. Any net id used to
-- be accepted, so a client could restyle (or "restore" to anything) another player's car.
local function nearVehicle(src, netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return false end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) <= 30.0
end

-- Broadcast preview changes so everyone sees them, never persisted
RegisterNetEvent('pf_mech:preview:syncMod', function(netId, modType, index)
    if not netId or modType == nil or index == nil then return end
    if not nearVehicle(source, netId) then return end
    TriggerClientEvent('pf_mech:preview:applyModClient', -1, netId, modType, index)
end)

RegisterNetEvent('pf_mech:preview:syncTint', function(netId, tint)
    if not netId or tint == nil then return end
    if not nearVehicle(source, netId) then return end
    TriggerClientEvent('pf_mech:preview:applyTintClient', -1, netId, tint)
end)

-- which: 'primary' | 'secondary' | 'pearl' | 'wheel'
RegisterNetEvent('pf_mech:preview:syncPaint', function(netId, which, index)
    if not netId or not which or index == nil then return end
    if not nearVehicle(source, netId) then return end
    TriggerClientEvent('pf_mech:preview:applyPaintClient', -1, netId, which, index)
end)

-- Restore snapshot for all viewers when preview ends or vehicle moves
RegisterNetEvent('pf_mech:preview:restore', function(netId, snapshot)
    if not netId or type(snapshot) ~= 'table' then return end
    if not nearVehicle(source, netId) then return end
    TriggerClientEvent('pf_mech:preview:restoreSnapshotClient', -1, netId, snapshot)
end)
