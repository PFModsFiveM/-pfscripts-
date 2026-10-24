local QBCore = exports['pfm-core']:GetCoreObject()

local TaxiState = {
    rideId = nil,
    rideData = nil,
    stage = nil,
    ped = nil,
    pickupBlip = nil,
    pickupMarker = nil,
    destinationBlip = nil,
    destinationMarker = nil,
    startedAt = nil,
    pickupAttempted = false,
    vehicleHealthOnPickup = 1000.0,
    collisionCount = 0,
    npcDialogueIntervals = {
        greeting = false,
        inTrip = false,
        phoneCall = false,
        destination = false,
    },
    pickupCoords = nil,
    currentFare = 0,
    currentRawFare = 0,
    currentPenaltyAmount = 0,
    collisionPenaltyPct = 0.0,
    collisionTypeCounts = {
        pedestrian = 0,
        vehicle = 0,
        sign_lamp = 0,
        wall = 0,
    },
    lastCollisionType = nil,
    lastCollisionAt = 0,
    lastVehicleHealth = 1000.0,
    currentDistance = 0,
    baseRate = 60,
    meterVisible = false,
    manualMeterActive = false,
    manualLastCoords = nil,
    dropoffInProgress = false,
    -- Rental system
    rentalVehicle = nil,
    rentalNetId = nil,
    returnMarker = nil,
}

local function sendTaxiTabletMessage(payload)
    if not payload then return end
    if GetResourceState('pf-tablet') == 'started' then
        pcall(function()
            exports['pf-tablet']:SendNuiMessage(payload)
        end)
    end
end

local function getMeterMeta(overrides)
    local meta = {
        onJob = TaxiState.rideId ~= nil,
        inTaxi = TaxiState.meterVisible == true,
        passengerName = TaxiState.rideData and TaxiState.rideData.clientName or 'Customer',
        passengerType = TaxiState.rideData and (TaxiState.rideData.vip and 'vip' or (TaxiState.rideData.premium and 'premium' or 'standard')) or 'standard',
    }

    if TaxiState.manualMeterActive and not TaxiState.rideId then
        meta.onJob = false
        meta.passengerName = 'Manual Fare'
        meta.passengerType = 'standard'
    end

    if overrides then
        if overrides.onJob ~= nil then meta.onJob = overrides.onJob end
        if overrides.inTaxi ~= nil then meta.inTaxi = overrides.inTaxi end
        if overrides.passengerName then meta.passengerName = overrides.passengerName end
        if overrides.passengerType then meta.passengerType = overrides.passengerType end
    end

    return meta
end

-- Taxi Meter NUI Functions
local function showTaxiMeter(rideData, overrides)
    local passengerType = 'standard'
    if rideData.vip then
        passengerType = 'vip'
    elseif rideData.premium then
        passengerType = 'premium'
    end

    TaxiState.meterVisible = true

    local meterMeta = getMeterMeta(overrides)
    meterMeta.passengerName = rideData.clientName or meterMeta.passengerName
    meterMeta.passengerType = passengerType or meterMeta.passengerType

    SendNUIMessage({
        action = 'showTaxiMeter',
        baseFare = 0,
        currentFare = TaxiState.currentFare or 0,
        rawFare = TaxiState.currentRawFare or 0,
        penaltyAmount = TaxiState.currentPenaltyAmount or 0,
        penaltyPct = TaxiState.collisionPenaltyPct or 0.0,
        collisions = TaxiState.collisionCount or 0,
        collisionTypeCounts = TaxiState.collisionTypeCounts or {},
        lastCollisionType = TaxiState.lastCollisionType,
        distance = TaxiState.currentDistance or 0.0,
        rate = TaxiState.baseRate,
        onJob = meterMeta.onJob,
        inTaxi = meterMeta.inTaxi,
        passengerName = meterMeta.passengerName,
        passengerType = meterMeta.passengerType,
        pickupCoords = rideData.pickup,
    })

    sendTaxiTabletMessage({
        action = 'taxi:meterUpdate',
        meter = {
            visible = true,
            onJob = meterMeta.onJob,
            inTaxi = meterMeta.inTaxi,
            currentFare = TaxiState.currentFare or 0,
            rawFare = TaxiState.currentRawFare or 0,
            penaltyAmount = TaxiState.currentPenaltyAmount or 0,
            penaltyPct = TaxiState.collisionPenaltyPct or 0.0,
            distance = TaxiState.currentDistance or 0.0,
            rate = TaxiState.baseRate,
            collisions = TaxiState.collisionCount or 0,
            collisionTypeCounts = TaxiState.collisionTypeCounts or {},
            lastCollisionType = TaxiState.lastCollisionType,
            passengerName = meterMeta.passengerName,
            passengerType = meterMeta.passengerType,
        }
    })
end

local function hideTaxiMeter(overrides)
    TaxiState.meterVisible = false

    local meterMeta = getMeterMeta(overrides)

    SendNUIMessage({
        action = 'hideTaxiMeter',
    })

    sendTaxiTabletMessage({
        action = 'taxi:meterHide',
        meter = {
            visible = false,
            onJob = meterMeta.onJob,
            inTaxi = false,
            currentFare = TaxiState.currentFare or 0,
            rawFare = TaxiState.currentRawFare or 0,
            penaltyAmount = TaxiState.currentPenaltyAmount or 0,
            penaltyPct = TaxiState.collisionPenaltyPct or 0.0,
            distance = TaxiState.currentDistance or 0.0,
            rate = TaxiState.baseRate,
            collisions = TaxiState.collisionCount or 0,
            collisionTypeCounts = TaxiState.collisionTypeCounts or {},
            lastCollisionType = TaxiState.lastCollisionType,
        }
    })
end

local function updateTaxiMeter(distance, fare, rate, extra)
    local finalDistance = distance or TaxiState.currentDistance
    local finalFare = fare or TaxiState.currentFare
    local finalRate = rate or TaxiState.baseRate
    local details = extra or {}
    local meterMeta = getMeterMeta(details)

    SendNUIMessage({
        action = 'updateTaxiMeter',
        distance = finalDistance,
        currentFare = finalFare,
        rate = finalRate,
        rawFare = details.rawFare or TaxiState.currentRawFare or finalFare,
        penaltyAmount = details.penaltyAmount or TaxiState.currentPenaltyAmount or 0,
        penaltyPct = details.penaltyPct or TaxiState.collisionPenaltyPct or 0.0,
        collisions = details.collisions or TaxiState.collisionCount or 0,
        collisionTypeCounts = details.collisionTypeCounts or TaxiState.collisionTypeCounts or {},
        lastCollisionType = details.lastCollisionType or TaxiState.lastCollisionType,
        onJob = meterMeta.onJob,
        inTaxi = meterMeta.inTaxi,
        passengerName = meterMeta.passengerName,
        passengerType = meterMeta.passengerType,
    })

    sendTaxiTabletMessage({
        action = 'taxi:meterUpdate',
        meter = {
            visible = TaxiState.meterVisible == true,
            onJob = meterMeta.onJob,
            inTaxi = meterMeta.inTaxi,
            currentFare = finalFare,
            rawFare = details.rawFare or TaxiState.currentRawFare or finalFare,
            penaltyAmount = details.penaltyAmount or TaxiState.currentPenaltyAmount or 0,
            penaltyPct = details.penaltyPct or TaxiState.collisionPenaltyPct or 0.0,
            distance = finalDistance,
            rate = finalRate,
            collisions = details.collisions or TaxiState.collisionCount or 0,
            collisionTypeCounts = details.collisionTypeCounts or TaxiState.collisionTypeCounts or {},
            lastCollisionType = details.lastCollisionType or TaxiState.lastCollisionType,
            passengerName = meterMeta.passengerName,
            passengerType = meterMeta.passengerType,
        }
    })
end

local function recordMeterCollision(collisionType, penaltyPct)
    SendNUIMessage({
        action = 'recordCollision',
        collisionType = collisionType,
        penaltyPct = penaltyPct,
    })

    local meterMeta = getMeterMeta()

    sendTaxiTabletMessage({
        action = 'taxi:meterUpdate',
        meter = {
            visible = TaxiState.meterVisible == true,
            onJob = meterMeta.onJob,
            inTaxi = meterMeta.inTaxi,
            currentFare = TaxiState.currentFare or 0,
            rawFare = TaxiState.currentRawFare or 0,
            penaltyAmount = TaxiState.currentPenaltyAmount or 0,
            penaltyPct = TaxiState.collisionPenaltyPct or 0.0,
            distance = TaxiState.currentDistance or 0.0,
            rate = TaxiState.baseRate,
            collisions = TaxiState.collisionCount or 0,
            collisionTypeCounts = TaxiState.collisionTypeCounts or {},
            lastCollisionType = TaxiState.lastCollisionType,
            passengerName = meterMeta.passengerName,
            passengerType = meterMeta.passengerType,
        }
    })
end

local function notify(msg, nType)
    QBCore.Functions.Notify(msg, nType or 'primary')
end

local function showPassengerSubtitle(text)
    if not text or text == '' then return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('~y~Passenger~s~: %s'):format(text))
    EndTextCommandThefeedPostTicker(false, false)
end

local function getCollisionPenaltyConfig()
    local cfg = (((Config or {}).Taxi or {}).CollisionPenalties) or {}
    return {
        pedestrian = tonumber(cfg.pedestrian) or 0.18,
        vehicle = tonumber(cfg.vehicle) or 0.14,
        sign_lamp = tonumber(cfg.sign_lamp) or 0.08,
        wall = tonumber(cfg.wall) or 0.04,
        minFareFactor = tonumber(cfg.minFareFactor) or 0.10,
        cooldownMs = tonumber(cfg.cooldownMs) or 1200,
        damageThreshold = tonumber(cfg.damageThreshold) or 8.0,
    }
end

local CollisionTypeLabels = {
    pedestrian = 'pedestrian',
    vehicle = 'vehicle',
    sign_lamp = 'sign/lamp',
    wall = 'wall/barrier',
}

local SignLampHashes = {}
do
    local models = {
        'prop_sign_road_01a',
        'prop_sign_road_02a',
        'prop_sign_road_03e',
        'prop_sign_road_04a',
        'prop_sign_road_05a',
        'prop_sign_road_06a',
        'prop_sign_road_06q',
        'prop_sign_road_restriction_10',
        'prop_traffic_01a',
        'prop_traffic_01d',
        'prop_traffic_02a',
        'prop_traffic_03a',
        'prop_streetlight_01',
        'prop_streetlight_01b',
        'prop_streetlight_03b',
        'prop_streetlight_04',
        'prop_streetlight_05',
    }

    for _, model in ipairs(models) do
        SignLampHashes[GetHashKey(model)] = true
    end
end

local function classifyCollisionType(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return 'wall'
    end

    local front = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 2.5, 0.6)
    local ahead = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 5.0, 0.9)
    local ray = StartShapeTestRay(front.x, front.y, front.z, ahead.x, ahead.y, ahead.z, 10, vehicle, 7)
    local _, hit, _, _, entityHit = GetShapeTestResult(ray)

    if hit == 1 and entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) then
        if IsEntityAPed(entityHit) then
            return 'pedestrian'
        end

        if IsEntityAVehicle(entityHit) then
            return 'vehicle'
        end

        if IsEntityAnObject(entityHit) then
            local model = GetEntityModel(entityHit)
            if SignLampHashes[model] then
                return 'sign_lamp'
            end
            return 'wall'
        end
    end

    local closestVehicle = GetClosestVehicle(front.x, front.y, front.z, 3.0, 0, 70)
    if closestVehicle and closestVehicle ~= 0 and closestVehicle ~= vehicle then
        return 'vehicle'
    end

    return 'wall'
end

local function resetMeterRuntimeState()
    TaxiState.collisionCount = 0
    TaxiState.collisionPenaltyPct = 0.0
    TaxiState.currentRawFare = 0
    TaxiState.currentPenaltyAmount = 0
    TaxiState.lastCollisionType = nil
    TaxiState.lastCollisionAt = 0
    TaxiState.currentFare = 0
    TaxiState.currentDistance = 0
    TaxiState.collisionTypeCounts = {
        pedestrian = 0,
        vehicle = 0,
        sign_lamp = 0,
        wall = 0,
    }
end

local function recomputeFareFromDistance(distanceMiles)
    TaxiState.currentDistance = tonumber(distanceMiles) or 0.0

    local rawFare = TaxiState.currentDistance * (TaxiState.baseRate or 60)
    TaxiState.currentRawFare = math.floor(rawFare)

    local penaltyCfg = getCollisionPenaltyConfig()
    local collisionFactor = 1.0 - (TaxiState.collisionPenaltyPct or 0.0)
    if collisionFactor < penaltyCfg.minFareFactor then
        collisionFactor = penaltyCfg.minFareFactor
    end

    TaxiState.currentFare = math.floor(rawFare * collisionFactor)
    TaxiState.currentPenaltyAmount = math.max(0, TaxiState.currentRawFare - TaxiState.currentFare)

    return TaxiState.currentFare
end

local function processCollisionPenalty(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end

    local cfg = getCollisionPenaltyConfig()
    local now = GetGameTimer()

    if TaxiState.lastCollisionAt and TaxiState.lastCollisionAt > 0 and (now - TaxiState.lastCollisionAt) < cfg.cooldownMs then
        TaxiState.lastVehicleHealth = GetEntityHealth(vehicle)
        return false
    end

    local currentHealth = GetEntityHealth(vehicle)
    local previousHealth = TaxiState.lastVehicleHealth or currentHealth

    if previousHealth <= 0 then
        TaxiState.lastVehicleHealth = currentHealth
        return false
    end

    local damageDelta = previousHealth - currentHealth
    TaxiState.lastVehicleHealth = currentHealth

    if damageDelta < cfg.damageThreshold then
        return false
    end

    local collisionType = classifyCollisionType(vehicle)
    local penaltyPct = cfg[collisionType] or cfg.wall

    TaxiState.collisionCount = (TaxiState.collisionCount or 0) + 1
    TaxiState.collisionTypeCounts[collisionType] = (TaxiState.collisionTypeCounts[collisionType] or 0) + 1

    local maxPenalty = math.max(0.0, 1.0 - cfg.minFareFactor)
    TaxiState.collisionPenaltyPct = math.min(maxPenalty, (TaxiState.collisionPenaltyPct or 0.0) + penaltyPct)
    TaxiState.lastCollisionType = collisionType
    TaxiState.lastCollisionAt = now

    recordMeterCollision(CollisionTypeLabels[collisionType] or collisionType, penaltyPct)

    if TaxiState.rideId then
        TriggerServerEvent('pf-taxi:server:recordCollision', TaxiState.rideId, {
            type = collisionType,
            penaltyPct = penaltyPct,
            damage = damageDelta,
        })
    end

    return true
end

local function removeBlip(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    return nil
end

local function createObjectiveBlip(coords, sprite, color, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 1)
    SetBlipColour(blip, color or 5)
    SetBlipScale(blip, 0.95)
    -- DO NOT SET WAYPOINT - only show blip marker
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Taxi Objective')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function cleanupRideState(deletePed)
    if deletePed ~= false and TaxiState.ped and DoesEntityExist(TaxiState.ped) then
        DeleteEntity(TaxiState.ped)
    end

    TaxiState.pickupBlip = removeBlip(TaxiState.pickupBlip)
    TaxiState.destinationBlip = removeBlip(TaxiState.destinationBlip)

    hideTaxiMeter()

    TaxiState.rideId = nil
    TaxiState.rideData = nil
    TaxiState.stage = nil
    TaxiState.ped = nil
    TaxiState.startedAt = nil
    TaxiState.pickupAttempted = false
    TaxiState.vehicleHealthOnPickup = 1000.0
    TaxiState.lastVehicleHealth = 1000.0
    TaxiState.collisionCount = 0
    TaxiState.collisionPenaltyPct = 0.0
    TaxiState.currentRawFare = 0
    TaxiState.currentPenaltyAmount = 0
    TaxiState.lastCollisionType = nil
    TaxiState.lastCollisionAt = 0
    TaxiState.collisionTypeCounts = {
        pedestrian = 0,
        vehicle = 0,
        sign_lamp = 0,
        wall = 0,
    }
    TaxiState.pickupCoords = nil
    TaxiState.currentFare = 0
    TaxiState.currentDistance = 0
    TaxiState.baseRate = 60
    TaxiState.meterVisible = false
    TaxiState.manualMeterActive = false
    TaxiState.manualLastCoords = nil
    TaxiState.dropoffInProgress = false
    TaxiState.npcDialogueIntervals = {
        greeting = false,
        inTrip = false,
        phoneCall = false,
        destination = false,
    }

    sendTaxiTabletMessage({
        action = 'taxi:meterHide',
        meter = {
            visible = false,
            onJob = false,
            inTaxi = false,
            currentFare = 0,
            rawFare = 0,
            penaltyAmount = 0,
            penaltyPct = 0.0,
            distance = 0.0,
            rate = 60,
            collisions = 0,
            collisionTypeCounts = {
                pedestrian = 0,
                vehicle = 0,
                sign_lamp = 0,
                wall = 0,
            },
            lastCollisionType = nil,
        }
    })
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 200 do
        Wait(10)
        timeout = timeout + 1
    end

    if not HasModelLoaded(hash) then return nil end
    return hash
end

local NPCAnimations = {
    phoneCall = {
        dict = 'cellphone@',
        anim = 'cellphone_call_listen_a',
    },
    talking = {
        dict = 'anim@mp_player_intmenu@fs_poster',
        anim = 'anim@mp_player_intmenu@fs_poster',
    },
    sitting = {
        dict = 'veh@ride@generic@ds@passenger@base',
        anim = 'ds_passenger_idle',
    },
    sitting_idles = {
        { dict = 'veh@ride@generic@ds@passenger@base', anim = 'ds_passenger_idle' },
        { dict = 'veh@ride@generic@ds@passenger@base', anim = 'ds_passenger_idles_01' },
        { dict = 'veh@ride@generic@ds@passenger@base', anim = 'ds_passenger_idles_02' },
    },
    lookingAround = {
        dict = 'veh@ride@generic@ds@passenger@base',
        anim = 'ds_passenger_idles_02',
    },
    relaxed = {
        dict = 'veh@ride@generic@ds@passenger@base',
        anim = 'ds_passenger_idles_01',
    },
}

local function playNPCAnimation(ped, animType)
    if not ped or not DoesEntityExist(ped) then return end
    
    local anim
    if type(animType) == 'table' then
        anim = animType
    else
        anim = NPCAnimations[animType or 'sitting']
    end
    
    if not anim or not anim.dict or not anim.anim then return end
    
    RequestAnimDict(anim.dict)
    local timeout = 0
    while not HasAnimDictLoaded(anim.dict) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if HasAnimDictLoaded(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.anim, 8.0, -8.0, -1, 1, 0, false, false, false)
    end
end

local function triggerNPCDialogue(dialogueType)
    if TaxiState.rideId then
        TriggerServerEvent('pf-taxi:server:triggerNPCDialogue', TaxiState.rideId, dialogueType or 'greeting')
    end
end

local function npcWalkAwayFromCar(ped, vehicle, destination)
    if not ped or not DoesEntityExist(ped) or not vehicle or not DoesEntityExist(vehicle) then return end
    
    -- Get vehicle backdoor
    SetPedFleeAttributes(ped, 0, false)
    
    -- Walk away from vehicle
    local vehCoord = GetEntityCoords(vehicle)
    local walkToCoord = vector3(
        vehCoord.x + math.random(-40, 40),
        vehCoord.y + math.random(-40, 40),
        vehCoord.z
    )
    
    TaskGoStraightToCoord(ped, walkToCoord.x, walkToCoord.y, walkToCoord.z, 1.0, -1, 0.0, 0.0)
    
    -- Wait for ped to start walking
    local timeoutTimer = GetGameTimer() + 15000
    while GetGameTimer() < timeoutTimer and DoesEntityExist(ped) do
        if GetEntitySpeed(ped) > 0.1 then
            break
        end
        Wait(100)
    end
end

local function spawnPassenger(ride)
    local pedModel = ride.pedModel or 'a_m_y_business_01'
    local hash = loadModel(pedModel)
    if not hash then
        hash = loadModel('a_m_y_business_01')
        if not hash then return nil end
    end

    local pickup = ride.pickup
    local ped = CreatePed(4, hash, pickup.x, pickup.y, pickup.z - 1.0, 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    FreezeEntityPosition(ped, false)

    SetModelAsNoLongerNeeded(hash)
    return ped
end

RegisterNetEvent('pf-taxi:client:startCall', function(ride)
    cleanupRideState()

    TaxiState.rideId = ride.id
    TaxiState.rideData = ride
    TaxiState.stage = 'pickup'
    TaxiState.startedAt = GetGameTimer()

    TaxiState.ped = spawnPassenger(ride)

    -- Create objective blip WITHOUT waypoint
    TaxiState.pickupBlip = createObjectiveBlip(ride.pickup, 280, 46, ('Pickup: %s'):format(ride.clientName or 'Client'))

    local clientType = ride.playerClient and 'Player Client' or (ride.premium and 'Premium Client' or 'Standard Client')
    notify(('Ride accepted (%s). Pick up %s'):format(clientType, ride.clientName or 'client'), 'success')
end)

RegisterNetEvent('pf-taxi:client:rideStarted', function(rideId, rideData)
    if TaxiState.rideId ~= rideId and rideData then
        TaxiState.rideId = rideId
        TaxiState.rideData = rideData
    end
end)

RegisterNetEvent('pf-taxi:client:npcSay', function(dialogue)
    notify(dialogue, 'primary')
    showPassengerSubtitle(dialogue)
end)

RegisterNetEvent('pf-taxi:client:fareBreakdown', function(breakdown)
    notify(('Est. Fare: $%d (%.1f miles)'):format(breakdown.estimatedFare, breakdown.distance), 'primary')
end)

RegisterNetEvent('pf-taxi:client:rideCompleted', function(data)
    local fare = tonumber(data and data.fare) or 0
    local xp = tonumber(data and data.xp) or 0
    local level = tonumber(data and data.level) or 1
    local collisions = tonumber(data and data.collisions) or 0
    local ratingMsg = string.format('%.1f★', data.rating or 5.0)
    
    local msg = ('Ride complete: +$%d, +%d XP (Level %d, Rating: %s)'):format(fare, xp, level, ratingMsg)
    if collisions > 0 then
        msg = msg .. (' | %d collision penalty'):format(collisions)
    end
    
    notify(msg, 'success')

    local departingPed = TaxiState.ped
    if departingPed and DoesEntityExist(departingPed) then
        SetPedKeepTask(departingPed, true)
        CreateThread(function()
            local timeoutAt = GetGameTimer() + 12000
            while GetGameTimer() < timeoutAt and DoesEntityExist(departingPed) do
                Wait(250)
            end

            if DoesEntityExist(departingPed) then
                DeleteEntity(departingPed)
            end
        end)
    end

    cleanupRideState(false)
end)

RegisterNetEvent('pf-taxi:client:rideCancelled', function()
    notify('Ride cancelled', 'error')
    cleanupRideState()
end)

RegisterNetEvent('pf-taxi:client:vehicleSpawned', function(netId, plate, spawn)
    local veh = NetToVeh(netId)
    if veh and DoesEntityExist(veh) then
        SetVehicleNumberPlateText(veh, plate)
    end
    -- lets the depot return prompt find this rental
    TaxiState.rentalVehicle = { plate = plate }
    TaxiState.rentalNetId = netId

    notify('Rental vehicle is ready', 'success')
end)

CreateThread(function()
    while true do
        Wait(250)

        if not TaxiState.rideId or not TaxiState.rideData then
            goto continue
        end

        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local ride = TaxiState.rideData

        if TaxiState.stage == 'pickup' then
            local pickupCoords = vector3(ride.pickup.x, ride.pickup.y, ride.pickup.z)
            local distToPickup = #(playerCoords - pickupCoords)

            if TaxiState.ped and DoesEntityExist(TaxiState.ped) and IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if GetPedInVehicleSeat(vehicle, -1) == ped then
                    if distToPickup <= 12.0 and not TaxiState.pickupAttempted then
                        TaxiState.pickupAttempted = true
                        TaskEnterVehicle(TaxiState.ped, vehicle, 10000, 2, 1.0, 1, 0)
                    end

                    if IsPedInVehicle(TaxiState.ped, vehicle, false) then
                        TaxiState.stage = 'destination'
                        TaxiState.pickupBlip = removeBlip(TaxiState.pickupBlip)
                        resetMeterRuntimeState()
                        TaxiState.vehicleHealthOnPickup = GetEntityHealth(vehicle)
                        TaxiState.lastVehicleHealth = TaxiState.vehicleHealthOnPickup
                        TaxiState.pickupCoords = GetEntityCoords(PlayerPedId())

                        local destinationCoords = { x = ride.destination.x, y = ride.destination.y, z = ride.destination.z }
                        TaxiState.destinationBlip = createObjectiveBlip(destinationCoords, 38, 5, ('Dropoff: %s'):format(ride.destination.label or 'Destination'))

                        TriggerServerEvent('pf-taxi:server:ridePickedUp', TaxiState.rideId)
                        TriggerServerEvent('pf-taxi:server:getFareBreakdown', TaxiState.rideId)
                        
                        -- Calculate base rate
                        TaxiState.baseRate = 60
                        if ride.premium then
                            TaxiState.baseRate = math.floor(60 * 1.5)
                        end
                        if ride.vip then
                            TaxiState.baseRate = math.floor(TaxiState.baseRate * 0.9)
                        end
                        
                        -- Show taxi meter
                        showTaxiMeter(ride)
                        
                        -- Play greeting animation
                        playNPCAnimation(TaxiState.ped, 'sitting')
                        triggerNPCDialogue('greeting')
                        
                        notify('Passenger picked up. Head to destination.', 'success')
                    end
                end
            end
        elseif TaxiState.stage == 'destination' then
            local destination = vector3(ride.destination.x, ride.destination.y, ride.destination.z)
            local distToDestination = #(playerCoords - destination)

            if IsPedInAnyVehicle(ped, false) and TaxiState.ped and DoesEntityExist(TaxiState.ped) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if GetPedInVehicleSeat(vehicle, -1) == ped and IsPedInVehicle(TaxiState.ped, vehicle, false) then
                    if not TaxiState.meterVisible then
                        showTaxiMeter(ride)
                    end

                    -- Update fare meter in real-time with collision penalties
                    if TaxiState.pickupCoords then
                        local traveledDistance = #(playerCoords - TaxiState.pickupCoords) / 1609.34 -- Convert to miles
                        recomputeFareFromDistance(traveledDistance)

                        -- Update meter display
                        updateTaxiMeter(traveledDistance, TaxiState.currentFare, TaxiState.baseRate, {
                            rawFare = TaxiState.currentRawFare,
                            penaltyAmount = TaxiState.currentPenaltyAmount,
                            penaltyPct = TaxiState.collisionPenaltyPct,
                            collisions = TaxiState.collisionCount,
                            collisionTypeCounts = TaxiState.collisionTypeCounts,
                            lastCollisionType = TaxiState.lastCollisionType,
                        })
                    end

                    -- Random in-trip dialogue - more frequent
                    if math.random(100) <= 8 and not TaxiState.npcDialogueIntervals.inTrip then
                        TaxiState.npcDialogueIntervals.inTrip = true
                        triggerNPCDialogue('inTrip')
                        -- Vary animations
                        if math.random(100) <= 50 then
                            playNPCAnimation(TaxiState.ped, 'lookingAround')
                        end
                    end

                    -- Random phone call animation - more frequent
                    if math.random(100) <= 6 and not TaxiState.npcDialogueIntervals.phoneCall then
                        TaxiState.npcDialogueIntervals.phoneCall = true
                        playNPCAnimation(TaxiState.ped, 'phoneCall')
                        triggerNPCDialogue('phoneCall')
                    end

                    -- Random idle animations
                    if math.random(100) <= 4 then
                        local idleAnims = NPCAnimations.sitting_idles
                        playNPCAnimation(TaxiState.ped, idleAnims[math.random(#idleAnims)])
                    end

                    if distToDestination <= 14.0 and GetEntitySpeed(vehicle) <= 2.0 then
                        if not TaxiState.dropoffInProgress then
                            TaxiState.dropoffInProgress = true

                            -- NPC exits and walks away
                            TaskLeaveVehicle(TaxiState.ped, vehicle, 0)
                            npcWalkAwayFromCar(TaxiState.ped, vehicle, destination)

                            triggerNPCDialogue('destination')

                            local miles = getDistanceMiles(vector3(ride.pickup.x, ride.pickup.y, ride.pickup.z), destination)
                            local rating = math.random(40, 50) / 10.0

                            TriggerServerEvent('pf-taxi:server:completeRide', TaxiState.rideId, {
                                distanceMiles = miles,
                                rating = rating,
                                collisions = TaxiState.collisionCount,
                                collisionPenaltyPct = TaxiState.collisionPenaltyPct,
                                collisionTypeCounts = TaxiState.collisionTypeCounts,
                            })
                        end
                    end
                else
                    TaxiState.dropoffInProgress = false
                    if TaxiState.meterVisible then
                        hideTaxiMeter()
                    end
                end
            else
                TaxiState.dropoffInProgress = false
                if TaxiState.meterVisible then
                    hideTaxiMeter()
                end
            end
        end

        ::continue::
    end
end)

-- Monitor collisions and manual fare updates
CreateThread(function()
    while true do
        Wait(250)

        local trackingRide = TaxiState.rideId and TaxiState.stage == 'destination'
        local trackingManual = TaxiState.manualMeterActive and not TaxiState.rideId

        if not trackingRide and not trackingManual then
            goto skipCollisionCheck
        end

        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            goto skipCollisionCheck
        end

        local vehicle = GetVehiclePedIsIn(ped, false)
        if not vehicle or vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
            goto skipCollisionCheck
        end

        if TaxiState.lastVehicleHealth <= 0 then
            TaxiState.lastVehicleHealth = GetEntityHealth(vehicle)
        end

        processCollisionPenalty(vehicle)

        if trackingManual then
            local playerCoords = GetEntityCoords(ped)
            if not TaxiState.pickupCoords then
                TaxiState.pickupCoords = playerCoords
            end

            local traveledDistance = #(playerCoords - TaxiState.pickupCoords) / 1609.34
            recomputeFareFromDistance(traveledDistance)

            if not TaxiState.meterVisible then
                showTaxiMeter({
                    clientName = 'Manual Fare',
                    premium = false,
                    vip = false,
                    pickup = { x = playerCoords.x, y = playerCoords.y, z = playerCoords.z },
                }, {
                    onJob = false,
                    inTaxi = true,
                    passengerName = 'Manual Fare',
                    passengerType = 'standard',
                })
            end

            updateTaxiMeter(traveledDistance, TaxiState.currentFare, TaxiState.baseRate, {
                rawFare = TaxiState.currentRawFare,
                penaltyAmount = TaxiState.currentPenaltyAmount,
                penaltyPct = TaxiState.collisionPenaltyPct,
                collisions = TaxiState.collisionCount,
                collisionTypeCounts = TaxiState.collisionTypeCounts,
                lastCollisionType = TaxiState.lastCollisionType,
                onJob = false,
                inTaxi = true,
                passengerName = 'Manual Fare',
                passengerType = 'standard',
            })
        end

        ::skipCollisionCheck::
    end
end)

function getDistanceMiles(fromCoords, toCoords)
    return #(fromCoords - toCoords) / 1609.34
end

local function stopManualMeter()
    local finalFare = TaxiState.currentFare or 0

    TaxiState.manualMeterActive = false
    TaxiState.manualLastCoords = nil
    TaxiState.pickupCoords = nil

    if TaxiState.meterVisible then
        hideTaxiMeter({
            onJob = false,
            inTaxi = false,
            passengerName = 'Manual Fare',
            passengerType = 'standard',
        })
    end

    notify(('Manual meter stopped. Final fare: $%d'):format(finalFare), 'success')
    resetMeterRuntimeState()
end

local function startManualMeter(rateArg)
    if TaxiState.rideId then
        notify('Finish your active dispatch ride before using manual meter', 'error')
        return
    end

    local manualCfg = (((Config or {}).Taxi or {}).ManualMeter) or {}
    if manualCfg.enabled == false then
        notify('Manual meter is disabled in config', 'error')
        return
    end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        notify('Enter a vehicle to start the manual meter', 'error')
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('You must be the driver to use the manual meter', 'error')
        return
    end

    local pricingRate = tonumber(((((Config or {}).Taxi or {}).Pricing or {}).basePricePerMile)) or 60
    local defaultRate = tonumber(manualCfg.defaultRate) or pricingRate
    local requestedRate = tonumber(rateArg)
    TaxiState.baseRate = math.floor((requestedRate and requestedRate > 0) and requestedRate or defaultRate)

    resetMeterRuntimeState()

    local playerCoords = GetEntityCoords(ped)
    TaxiState.manualMeterActive = true
    TaxiState.pickupCoords = playerCoords
    TaxiState.manualLastCoords = playerCoords
    TaxiState.vehicleHealthOnPickup = GetEntityHealth(vehicle)
    TaxiState.lastVehicleHealth = TaxiState.vehicleHealthOnPickup

    showTaxiMeter({
        clientName = 'Manual Fare',
        premium = false,
        vip = false,
        pickup = { x = playerCoords.x, y = playerCoords.y, z = playerCoords.z },
    }, {
        onJob = false,
        inTaxi = true,
        passengerName = 'Manual Fare',
        passengerType = 'standard',
    })

    updateTaxiMeter(0.0, 0, TaxiState.baseRate, {
        rawFare = 0,
        penaltyAmount = 0,
        penaltyPct = 0.0,
        collisions = 0,
        collisionTypeCounts = TaxiState.collisionTypeCounts,
        lastCollisionType = nil,
        onJob = false,
        inTaxi = true,
        passengerName = 'Manual Fare',
        passengerType = 'standard',
    })

    notify(('Manual meter started at $%d/mi'):format(TaxiState.baseRate), 'success')
end

local manualMeterCommand = tostring((((Config or {}).Taxi or {}).ManualMeter or {}).command or 'taximeter')
RegisterCommand(manualMeterCommand, function(_, args)
    if TaxiState.manualMeterActive then
        stopManualMeter()
        return
    end

    startManualMeter(args and args[1])
end, false)

RegisterCommand('taxicancel', function()
    if TaxiState.rideId then
        TriggerServerEvent('pf-taxi:server:cancelRide', TaxiState.rideId)
    end
end, false)

RegisterCommand('taxistart', function()
    QBCore.Functions.TriggerCallback('pf-taxi:server:getCalls', function(calls)
        if type(calls) ~= 'table' or #calls == 0 then
            notify('No ride calls available right now', 'error')
            return
        end
        TriggerServerEvent('pf-taxi:server:acceptCall', calls[1])
    end)
end, false)

RegisterCommand('taxicomplete', function()
    if TaxiState.rideId then
        local ride = TaxiState.rideData
        TriggerServerEvent('pf-taxi:server:completeRide', TaxiState.rideId, {
            distanceMiles = ride and ride.distanceMiles or 1.0,
            rating = 5.0,
            collisions = TaxiState.collisionCount,
            collisionPenaltyPct = TaxiState.collisionPenaltyPct,
            collisionTypeCounts = TaxiState.collisionTypeCounts,
        })
    end
end, false)

-- Rental vehicle system
RegisterNetEvent('pf-taxi:client:vehicleRented', function(netId, vehicleData)
    TaxiState.rentalVehicle = vehicleData
    TaxiState.rentalNetId = netId
    notify('Rental vehicle active. Return to depot when done.', 'success')
end)

RegisterNetEvent('pf-taxi:client:rentalReturned', function()
    TaxiState.rentalVehicle = nil
    TaxiState.rentalNetId = nil
    notify('Vehicle returned successfully.', 'success')
end)

-- Monitor for rental return
CreateThread(function()
    while true do
        Wait(500)
        
        if TaxiState.rentalVehicle and TaxiState.rentalNetId then
            local ped = PlayerPedId()
            local depotCoord = vector3(912.45, -165.32, 74.38)
            local distToDepot = #(GetEntityCoords(ped) - depotCoord)
            
            if distToDepot <= 15.0 then
                if IsPedInAnyVehicle(ped, false) then
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    if GetVehicleNumberPlateText(vehicle) == GetVehicleNumberPlateText(NetToVeh(TaxiState.rentalNetId)) then
                        notify('Press E to return rental vehicle', 'primary')
                        
                        if IsControlJustPressed(0, 38) then -- E key
                            TriggerServerEvent('pf-taxi:server:returnRentalVehicle', TaxiState.rentalNetId)
                            TaxiState.rentalVehicle = nil
                            TaxiState.rentalNetId = nil
                        end
                    end
                end
            end
        end
    end
end)

-- Vehicle photo capture with Lua-based screenshot
local photoMode = {
    active = false,
    camera = nil,
    vehicleData = nil,
}

local function setupPhotoMode(vehicle)
    local vehicleCoords = GetEntityCoords(vehicle)
    local vehicleHeading = GetEntityHeading(vehicle)
    
    -- Position camera to see front and side of vehicle (45 degree angle)
    -- Positioned high enough to avoid character model
    local cameraDistance = 12.0
    local cameraHeight = 4.0
    local angle = math.rad(vehicleHeading - 45)
    local cameraX = vehicleCoords.x + math.cos(angle) * cameraDistance
    local cameraY = vehicleCoords.y + math.sin(angle) * cameraDistance
    local cameraZ = vehicleCoords.z + cameraHeight
    
    if photoMode.camera and DoesCamExist(photoMode.camera) then
        DestroyCam(photoMode.camera, false)
    end
    
    photoMode.camera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(photoMode.camera, cameraX, cameraY, cameraZ)
    SetCamRot(photoMode.camera, -20.0, 0.0, vehicleHeading - 45, 2)
    PointCamAtEntity(photoMode.camera, vehicle, 0.0, 0.0, 0.0, true)
    SetCamActive(photoMode.camera, true)
    RenderScriptCams(true, true, 1000, true, true)
    
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local plate = GetVehicleNumberPlateText(vehicle)
    
    photoMode.active = true
    photoMode.vehicleData = {
        model = modelName,
        plate = plate,
        coords = vehicleCoords,
    }
    
    notify(('📸 Photo mode active: %s (%s) - Press E/G to capture, ESC to exit'):format(modelName, plate), 'success')
end

local function exitPhotoMode()
    if photoMode.camera and DoesCamExist(photoMode.camera) then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(photoMode.camera, false)
        photoMode.camera = nil
    end
    photoMode.active = false
    photoMode.vehicleData = nil
    notify('Photo mode exited', 'primary')
end

local function captureVehiclePhoto()
    if not photoMode.active or not photoMode.vehicleData then
        notify('Not in photo mode', 'error')
        return
    end
    
    local model = photoMode.vehicleData.model or 'unknown'
    local plate = photoMode.vehicleData.plate or 'UNKNOWN'
    local gameTime = GetGameTimer()
    local filename = ('vehicle_photo_%s_%s_%d'):format(model, plate:gsub(' ', '_'), gameTime)
    
    -- Record photo server-side with metadata
    TriggerServerEvent('pf-taxi:server:capturePhoto', {
        model = model,
        plate = plate,
        filename = filename,
        coords = photoMode.vehicleData.coords,
    })
    
    notify(('📸 Photo recorded: %s'):format(filename), 'success')
    
    -- Brief delay then exit photo mode
    Wait(800)
    exitPhotoMode()
end

RegisterCommand('vehiclephoto', function()
    local ped = PlayerPedId()
    local nearbyVehicle = GetClosestVehicle(GetEntityCoords(ped), 30.0, 0, 70)
    
    if nearbyVehicle == 0 then
        notify('No vehicle found nearby', 'error')
        return
    end
    
    if photoMode.active then
        exitPhotoMode()
    else
        setupPhotoMode(nearbyVehicle)
    end
end, false)

RegisterCommand('vphoto', function()
    local ped = PlayerPedId()
    local nearbyVehicle = GetClosestVehicle(GetEntityCoords(ped), 30.0, 0, 70)
    
    if nearbyVehicle == 0 then
        notify('No vehicle found nearby', 'error')
        return
    end
    
    if photoMode.active then
        exitPhotoMode()
    else
        setupPhotoMode(nearbyVehicle)
    end
end, false)

RegisterCommand('exitphoto', function()
    exitPhotoMode()
end, false)

-- Simple capture command
RegisterCommand('photo', function()
    captureVehiclePhoto()
end, false)

RegisterCommand('cap', function()
    captureVehiclePhoto()
end, false)

-- Key press monitoring for photo mode
CreateThread(function()
    while true do
        Wait(0)
        if photoMode.active then
            -- Check multiple keys for capture
            -- SPACE (32), E (38), G (47), F (36)
            if IsControlJustPressed(0, 38) then -- E key
                captureVehiclePhoto()
            elseif IsControlJustPressed(0, 47) then -- G key
                captureVehiclePhoto()
            elseif IsControlJustPressed(0, 177) then -- ESC key
                exitPhotoMode()
            end
        end
    end
end)

-- View captured photos list
RegisterCommand('photos', function()
    TriggerServerEvent('pf-taxi:server:getPhotos')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupRideState()
end)
