-- client/supplies.lua
-- Supplies pickup mission with Phantom + trailer hookup flow.

local QBCore = exports['pfm-core']:GetCoreObject()

local missionActive = false
local missionState = {
    phantomNetId = 0,
    trailerNetId = 0,
    phantomEntity = 0,
    trailerEntity = 0,
    trailerHooked = false,
    deliveryLocation = nil,
    currentOrder = nil,
    deliveryBlip = nil,
    promptShown = false,
}

local TRAILER_SPAWN = vector4(1201.02, -3237.56, 6.06, 359.64)

local function scoreboardShow(title, subtitle)
    if GetResourceState('pf-tablet') ~= 'started' then return end
    pcall(function()
        exports['pf-tablet']:SendNuiMessage({
            action = 'scoreboard_open',
            title = title or 'Supplies Pickup',
            subtitle = subtitle or ''
        })
    end)
end

local function scoreboardUpdate(title, subtitle)
    if GetResourceState('pf-tablet') ~= 'started' then return end
    pcall(function()
        exports['pf-tablet']:SendNuiMessage({
            action = 'scoreboard_update',
            title = title or 'Supplies Pickup',
            subtitle = subtitle or ''
        })
    end)
end

local function scoreboardHide()
    if GetResourceState('pf-tablet') ~= 'started' then return end
    pcall(function()
        exports['pf-tablet']:SendNuiMessage({ action = 'scoreboard_close' })
    end)
end

local function hidePrompt()
    if missionState.promptShown then
        missionState.promptShown = false
        exports['pfm-core']:HideText()
    end
end

local function resolveEntityByNet(netId)
    if not netId or netId <= 0 then return 0 end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity ~= 0 and DoesEntityExist(entity) then
        return entity
    end
    return 0
end

local function resolvePhantomEntity()
    if missionState.phantomEntity ~= 0 and DoesEntityExist(missionState.phantomEntity) then
        return missionState.phantomEntity
    end

    missionState.phantomEntity = resolveEntityByNet(missionState.phantomNetId)
    return missionState.phantomEntity
end

local function resolveTrailerEntity()
    if missionState.trailerEntity ~= 0 and DoesEntityExist(missionState.trailerEntity) then
        return missionState.trailerEntity
    end

    missionState.trailerEntity = resolveEntityByNet(missionState.trailerNetId)
    return missionState.trailerEntity
end

local function resetState()
    missionActive = false
    missionState.trailerHooked = false
    missionState.phantomNetId = 0
    missionState.trailerNetId = 0
    missionState.phantomEntity = 0
    missionState.trailerEntity = 0
    missionState.deliveryLocation = nil
    missionState.currentOrder = nil

    if missionState.deliveryBlip and DoesBlipExist(missionState.deliveryBlip) then
        RemoveBlip(missionState.deliveryBlip)
    end
    missionState.deliveryBlip = nil

    hidePrompt()
    scoreboardHide()
end

local function cleanupMission()
    resetState()
end

local function isPhantomHookedToTrailer()
    local phantom = resolvePhantomEntity()
    local trailer = resolveTrailerEntity()
    if phantom == 0 or trailer == 0 then
        return false
    end

    local hasTrailer, hookedTrailer = GetVehicleTrailerVehicle(phantom)
    return hasTrailer and hookedTrailer == trailer
end

local function startDeliveryPhase()
    CreateThread(function()
        while missionActive and missionState.trailerHooked do
            Wait(0)

            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)
            local delivery = missionState.deliveryLocation

            if delivery then
                local markerPos = vector3(delivery.x, delivery.y, delivery.z)
                local dist = #(pedCoords - markerPos)

                if dist < 100.0 then
                    DrawMarker(1, delivery.x, delivery.y, delivery.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        5.0, 5.0, 2.0,
                        255, 200, 50, 150,
                        false, false, 2, false, nil, nil, false)

                    DrawMarker(0, delivery.x, delivery.y, delivery.z + 2.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        1.5, 1.5, 1.5,
                        255, 200, 50, 200,
                        true, false, 2, false, nil, nil, false)
                end

                if dist < 7.0 and isPhantomHookedToTrailer() then
                    if not missionState.promptShown then
                        missionState.promptShown = true
                        exports['pfm-core']:DrawText('[E] Deliver Supplies', 'left')
                    end

                    if IsControlJustPressed(0, 38) then
                        hidePrompt()
                        QBCore.Functions.Notify('Delivery submitted. Waiting for confirmation...', 'info')
                        scoreboardUpdate('Supplies Delivery', 'Completing delivery...')
                        TriggerServerEvent('pf-mechanicjob:server:completeSuppliesDelivery')
                    end
                else
                    hidePrompt()
                end
            end
        end

        hidePrompt()
    end)
end

local function startTrailerMission()
    CreateThread(function()
        local trailerBlip = AddBlipForCoord(TRAILER_SPAWN.x, TRAILER_SPAWN.y, TRAILER_SPAWN.z)
        SetBlipSprite(trailerBlip, 479)
        SetBlipColour(trailerBlip, 5)
        SetBlipScale(trailerBlip, 0.9)
        SetBlipRoute(trailerBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Trailer Pickup')
        EndTextCommandSetBlipName(trailerBlip)

        while missionActive and not missionState.trailerHooked do
            Wait(0)

            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)
            local trailerSpawn = vector3(TRAILER_SPAWN.x, TRAILER_SPAWN.y, TRAILER_SPAWN.z)
            local distToSpawn = #(pedCoords - trailerSpawn)

            local trailer = resolveTrailerEntity()
            if distToSpawn < 60.0 and trailer ~= 0 then
                local tCoords = GetEntityCoords(trailer)
                DrawMarker(1, tCoords.x, tCoords.y, tCoords.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    4.0, 4.0, 2.0,
                    30, 200, 120, 150,
                    true, false, 2, false, nil, nil, false)
            end

            if isPhantomHookedToTrailer() then
                missionState.trailerHooked = true

                if trailerBlip and DoesBlipExist(trailerBlip) then
                    RemoveBlip(trailerBlip)
                end

                QBCore.Functions.Notify('Trailer hooked! Drive to delivery location', 'success')
                scoreboardUpdate('Supplies Delivery', 'Drive to delivery point')

                local delivery = missionState.deliveryLocation
                if delivery then
                    missionState.deliveryBlip = AddBlipForCoord(delivery.x, delivery.y, delivery.z)
                    SetBlipSprite(missionState.deliveryBlip, 478)
                    SetBlipColour(missionState.deliveryBlip, 2)
                    SetBlipRoute(missionState.deliveryBlip, true)
                    SetBlipScale(missionState.deliveryBlip, 0.9)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Delivery Location')
                    EndTextCommandSetBlipName(missionState.deliveryBlip)
                end

                TriggerServerEvent('pf-mechanicjob:server:trailerHooked')
                startDeliveryPhase()
                break
            end
        end

        if trailerBlip and DoesBlipExist(trailerBlip) then
            RemoveBlip(trailerBlip)
        end
    end)
end

RegisterNetEvent('pf-mechanicjob:client:supplies:pickupStart', function(order, config, phantomNetId, trailerNetId)
    if missionActive then
        QBCore.Functions.Notify('You already have an active pickup mission', 'error')
        return
    end

    missionActive = true
    missionState.phantomNetId = tonumber(phantomNetId) or 0
    missionState.trailerNetId = tonumber(trailerNetId) or 0
    missionState.trailerEntity = 0
    missionState.phantomEntity = 0
    missionState.trailerHooked = false
    missionState.currentOrder = order
    missionState.deliveryLocation = (order and order.deliveryLocation) or (config and config.defaultDropoffLocation) or nil

    SetNewWaypoint(TRAILER_SPAWN.x, TRAILER_SPAWN.y)
    QBCore.Functions.Notify('Waypoint set to trailer location', 'info')
    QBCore.Functions.Notify('Hook the trailer with your Phantom and deliver the goods', 'success')
    scoreboardShow('Supplies Pickup', 'Drive to the trailer location')

    startTrailerMission()
end)

RegisterNetEvent('pf-mechanicjob:client:supplies:deliveryComplete', function(success, message)
    if success then
        QBCore.Functions.Notify(message or 'Delivery completed successfully!', 'success')
        cleanupMission()
    else
        QBCore.Functions.Notify(message or 'Delivery failed', 'error')
    end
end)

RegisterNetEvent('pf-mechanicjob:client:supplies:cleanup', function()
    cleanupMission()
end)

RegisterNetEvent('pf-mechanicjob:client:supplies:abort', function()
    QBCore.Functions.Notify('Supplies mission cancelled', 'error')
    cleanupMission()
end)

-- Compatibility for old flow: do not break if some older server event still fires.
RegisterNetEvent('pf-mechanicjob:client:supplies:startDelivery', function()
    if missionActive and missionState.trailerHooked then
        startDeliveryPhase()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        cleanupMission()
    end
end)
