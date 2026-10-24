-- server/supplies.lua
-- Server-side supplies pickup mission system (Phantom + trailer flow).

local QBCore = exports['pfm-core']:GetCoreObject()
local activePickupMissions = {}

local function toVector4(value)
    if type(value) ~= 'table' then return nil end
    if value.x and value.y and value.z then
        return {
            x = tonumber(value.x) or 0.0,
            y = tonumber(value.y) or 0.0,
            z = tonumber(value.z) or 0.0,
            w = tonumber(value.w) or 0.0,
        }
    end
    return nil
end

local function giveVehicleKeys(playerSrc, plate)
    if not playerSrc or not plate or plate == '' then return end

    TriggerClientEvent('vehiclekeys:client:SetOwner', playerSrc, plate)
    if GetResourceState('pfm-vehiclekeys') == 'started' then
        TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', playerSrc, plate)
    end

    SetTimeout(300, function()
        TriggerClientEvent('vehiclekeys:client:SetOwner', playerSrc, plate)
        if GetResourceState('pfm-vehiclekeys') == 'started' then
            TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', playerSrc, plate)
        end
    end)
end

local function spawnVehicle(modelName, vehType, coords)
    local modelHash = GetHashKey(modelName)
    local vehicle

    if type(CreateVehicleServerSetter) == 'function' then
        vehicle = CreateVehicleServerSetter(modelHash, vehType, coords.x, coords.y, coords.z, coords.w)
    elseif type(CreateVehicle) == 'function' then
        vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w, true, true)
    else
        return 0
    end

    local timeout = 0
    while (not vehicle or vehicle == 0 or (type(DoesEntityExist) == 'function' and not DoesEntityExist(vehicle))) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if not vehicle or vehicle == 0 or (type(DoesEntityExist) == 'function' and not DoesEntityExist(vehicle)) then
        return 0
    end

    if type(SetVehicleOnGroundProperly) == 'function' then
        SetVehicleOnGroundProperly(vehicle)
    end
    if type(SetVehicleEngineHealth) == 'function' then
        SetVehicleEngineHealth(vehicle, 1000.0)
    end
    if type(SetVehicleBodyHealth) == 'function' then
        SetVehicleBodyHealth(vehicle, 1000.0)
    end
    if type(SetVehicleDirtLevel) == 'function' then
        SetVehicleDirtLevel(vehicle, 0.0)
    end
    if type(SetVehicleEngineOn) == 'function' then
        SetVehicleEngineOn(vehicle, false, false, true)
    end

    return vehicle
end

local function getNetId(entity)
    if entity == 0 then return 0 end
    if type(NetworkGetNetworkIdFromEntity) ~= 'function' then return 0 end

    local netId = 0
    local timeout = 0
    while timeout < 100 do
        netId = NetworkGetNetworkIdFromEntity(entity)
        if netId and netId > 0 then
            break
        end
        Wait(10)
        timeout = timeout + 1
    end

    if netId and netId > 0 then
        if type(SetNetworkIdExistsOnAllMachines) == 'function' then
            SetNetworkIdExistsOnAllMachines(netId, true)
        end
        if type(SetNetworkIdCanMigrate) == 'function' then
            SetNetworkIdCanMigrate(netId, true)
        end
        return netId
    end

    return 0
end

local function deleteByNetId(netId)
    if not netId or netId <= 0 then return end
    if type(NetworkDoesEntityExistWithNetworkId) == 'function' and not NetworkDoesEntityExistWithNetworkId(netId) then
        return
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

local function completeMission(src, requireHooked)
    local mission = activePickupMissions[src]
    if not mission then
        TriggerClientEvent('pf-mechanicjob:client:supplies:deliveryComplete', src, false, 'No active mission')
        return false, 'no_active_mission'
    end

    if requireHooked and not mission.trailerHooked then
        TriggerClientEvent('pf-mechanicjob:client:supplies:deliveryComplete', src, false, 'Trailer not hooked')
        return false, 'trailer_not_hooked'
    end

    deleteByNetId(mission.phantomNetId)
    deleteByNetId(mission.trailerNetId)

    local orderId = mission.orderId
    activePickupMissions[src] = nil

    if GetResourceState('pf-computer') == 'started' then
        if orderId then
            TriggerEvent('pf-computer:server:supplies:orderDelivered', orderId, src)
            TriggerEvent('pf-computer:server:supplies:completeOrder', src, orderId)
        end
    end

    TriggerClientEvent('pf-mechanicjob:client:supplies:deliveryComplete', src, true, 'Delivery completed! Payment processed.')
    TriggerClientEvent('pf-mechanicjob:client:supplies:cleanup', src)

    if Config.Debug then
        print(('^2[pf-mechanicjob]^7 Player %s completed supplies delivery for order %s'):format(src, tostring(orderId)))
    end

    return true
end

local function startPickupMission(targetSrc, order)
    if not QBCore or not QBCore.Functions or not QBCore.Functions.GetPlayer then
        return false, 'qbcore_unavailable'
    end

    if not Config or type(Config.IsMechanicJob) ~= 'function' then
        return false, 'mechanic_config_unavailable'
    end

    local playerSrc = tonumber(targetSrc)
    if not playerSrc then return false, 'invalid_player' end

    if activePickupMissions[playerSrc] then
        return false, 'mission_already_active'
    end

    local player = QBCore.Functions.GetPlayer(playerSrc)
    if not player then
        return false, 'player_not_found'
    end

    local jobName = player.PlayerData.job and player.PlayerData.job.name or nil
    if not jobName or not Config.IsMechanicJob(jobName) then
        return false, 'not_mechanic'
    end

    if type(order) ~= 'table' then
        return false, 'invalid_order'
    end

    local suppliesCfg = Config.SuppliesOrder
    if not suppliesCfg then
        return false, 'missing_supplies_config'
    end

    local ped = GetPlayerPed(playerSrc)
    local pedCoords = GetEntityCoords(ped)

    local phantomSpawn = {
        x = pedCoords.x + 5.0,
        y = pedCoords.y + 5.0,
        z = pedCoords.z,
        w = 0.0,
    }

    local trailerSpawn = {
        x = 1201.02,
        y = -3237.56,
        z = 6.06,
        w = 359.64,
    }

    local deliveryLoc = toVector4(order.deliveryLocation) or toVector4(suppliesCfg.defaultDropoffLocation)

    local phantom = spawnVehicle('phantom', 'automobile', phantomSpawn)
    if phantom == 0 then
        return false, 'phantom_spawn_failed'
    end

    local trailer = spawnVehicle('trailers', 'trailer', trailerSpawn)
    if trailer == 0 then
        DeleteEntity(phantom)
        return false, 'trailer_spawn_failed'
    end

    local phantomNetId = getNetId(phantom)
    local trailerNetId = getNetId(trailer)

    if phantomNetId <= 0 or trailerNetId <= 0 then
        DeleteEntity(phantom)
        DeleteEntity(trailer)
        return false, 'network_id_failed'
    end

    local phantomPlate = ('SUP%04d'):format(math.random(1000, 9999))
    local trailerPlate = ('TRL%04d'):format(math.random(1000, 9999))

    if type(SetVehicleNumberPlateText) == 'function' then
        SetVehicleNumberPlateText(phantom, phantomPlate)
        SetVehicleNumberPlateText(trailer, trailerPlate)
    end

    giveVehicleKeys(playerSrc, phantomPlate)
    giveVehicleKeys(playerSrc, trailerPlate)

    order.deliveryLocation = deliveryLoc

    local missionConfig = {
        phantomModel = 'phantom',
        phantomSpawn = phantomSpawn,
        trailerModel = 'trailers',
        trailerSpawn = trailerSpawn,
        defaultDropoffLocation = deliveryLoc,
    }

    activePickupMissions[playerSrc] = {
        phantomNetId = phantomNetId,
        trailerNetId = trailerNetId,
        phantomPlate = phantomPlate,
        trailerPlate = trailerPlate,
        orderId = tonumber(order.id),
        trailerHooked = false,
        startTime = os.time(),
    }

    TriggerClientEvent('pf-mechanicjob:client:supplies:pickupStart', playerSrc, order, missionConfig, phantomNetId, trailerNetId)
    return true
end

RegisterNetEvent('pf-mechanicjob:server:supplies:startPickup', function(targetSrc, order)
    local ok, reason = startPickupMission(targetSrc, order)
    if ok then return end

    local playerSrc = tonumber(targetSrc)
    if playerSrc then
        local msg = 'Unable to start pickup mission'
        if reason == 'mission_already_active' then
            msg = 'You already have an active pickup mission'
        elseif reason == 'not_mechanic' then
            msg = 'You must be a mechanic to start pickup missions'
        elseif reason == 'phantom_spawn_failed' then
            msg = 'Failed to spawn mission truck'
        elseif reason == 'trailer_spawn_failed' then
            msg = 'Failed to spawn trailer'
        elseif reason == 'network_id_failed' then
            msg = 'Network sync failed while creating vehicles'
        elseif reason == 'vehicle_spawn_native_unavailable' then
            msg = 'Server vehicle spawn native is unavailable'
        end
        TriggerClientEvent('QBCore:Notify', playerSrc, msg, 'error')
    end

    print('^1[pf-mechanicjob]^7 ERROR: Pickup mission failed (' .. tostring(reason) .. ')')
end)

RegisterNetEvent('pf-mechanicjob:server:trailerHooked', function()
    local src = source
    if activePickupMissions[src] then
        activePickupMissions[src].trailerHooked = true
        if Config.Debug then
            print('^2[pf-mechanicjob]^7 Player ' .. src .. ' hooked the trailer')
        end
    end
end)

RegisterNetEvent('pf-mechanicjob:server:completeSuppliesDelivery', function()
    local src = source
    completeMission(src, true)
end)

-- Legacy compatibility events
RegisterNetEvent('pf-mechanicjob:server:completeDelivery', function()
    local src = source
    completeMission(src, false)
end)

RegisterNetEvent('pf-mechanicjob:server:pickupPallet', function()
    local src = source
    if activePickupMissions[src] then
        TriggerClientEvent('QBCore:Notify', src, 'Pallet loading flow is deprecated for this mission.', 'info')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if activePickupMissions[src] then
        deleteByNetId(activePickupMissions[src].phantomNetId)
        deleteByNetId(activePickupMissions[src].trailerNetId)
        activePickupMissions[src] = nil
    end
end)

exports('StartSuppliesPickup', function(targetSrc, order)
    local ok, missionOk, missionReason = pcall(startPickupMission, targetSrc, order)
    if not ok then
        local errText = tostring(missionOk)
        print('^1[pf-mechanicjob]^7 StartSuppliesPickup exception: ' .. errText)
        return false, 'pickup_exception:' .. errText
    end
    return missionOk, missionReason
end)
