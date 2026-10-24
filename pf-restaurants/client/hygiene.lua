-- Hygiene system client-side (trash, roaches, visuals)

local trashProps = {}
local roachPeds = {}

-- Spawn trash prop
RegisterNetEvent('pf-restaurants:client:spawnTrash', function(businessId)
    local restaurant = Config.Restaurants[businessId]
    if not restaurant or not restaurant.hygieneSpawns or not restaurant.hygieneSpawns.trash then
        return
    end
    
    local trashSpawns = restaurant.hygieneSpawns.trash
    local spawnPoint = trashSpawns[math.random(#trashSpawns)]
    
    local trashModel = 'prop_cs_rub_binbag_01'
    RequestModel(trashModel)
    while not HasModelLoaded(trashModel) do
        Wait(10)
    end
    
    local trashId = 'trash_' .. businessId .. '_' .. GetGameTimer()
    local prop = CreateObject(GetHashKey(trashModel), spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false)
    PlaceObjectOnGroundProperly(prop)
    
    trashProps[trashId] = {
        prop = prop,
        businessId = businessId,
        coords = spawnPoint
    }
    
    -- Add interaction
    if Config.UseTarget then
        if Config.TargetScript == 'qb-target' then
            exports['pfm-target']:AddTargetEntity(prop, {
                options = {
                    {
                        type = 'client',
                        event = 'pf-restaurants:client:pickupTrash',
                        icon = 'fas fa-trash',
                        label = 'Pick Up Trash',
                        trashId = trashId,
                        businessId = businessId,
                    },
                },
                distance = 2.0
            })
        end
    end
end)

-- Remove trash prop
RegisterNetEvent('pf-restaurants:client:removeTrash', function(businessId, trashId)
    if trashProps[trashId] then
        if DoesEntityExist(trashProps[trashId].prop) then
            if Config.UseTarget and Config.TargetScript == 'qb-target' then
                exports['pfm-target']:RemoveTargetEntity(trashProps[trashId].prop)
            end
            DeleteEntity(trashProps[trashId].prop)
        end
        trashProps[trashId] = nil
    end
end)

-- Pick up trash
RegisterNetEvent('pf-restaurants:client:pickupTrash', function(data)
    local trashId = data.trashId
    local businessId = data.businessId
    
    -- Play animation
    local playerPed = PlayerPedId()
    RequestAnimDict('anim@amb@clubhouse@tutorial@bkr_tut_ig3@')
    while not HasAnimDictLoaded('anim@amb@clubhouse@tutorial@bkr_tut_ig3@') do
        Wait(10)
    end
    
    TaskPlayAnim(playerPed, 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer', 8.0, -8.0, -1, 1, 0, false, false, false)
    
    QBCore.Functions.Progressbar('pickup_trash', 'Picking up trash...', 3000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function() -- Done
        ClearPedTasks(playerPed)
        TriggerServerEvent('pf-restaurants:server:removeTrash', businessId, trashId)
    end, function() -- Cancel
        ClearPedTasks(playerPed)
    end)
end)

-- Spawn roach
RegisterNetEvent('pf-restaurants:client:spawnRoach', function(businessId)
    local restaurant = Config.Restaurants[businessId]
    if not restaurant or not restaurant.hygieneSpawns or not restaurant.hygieneSpawns.roaches then
        return
    end
    
    local roachArea = restaurant.hygieneSpawns.roaches.area
    local roachRadius = restaurant.hygieneSpawns.roaches.radius
    
    -- Spawn random roach in area
    local randomOffset = vector3(
        math.random(-roachRadius, roachRadius),
        math.random(-roachRadius, roachRadius),
        0.0
    )
    local spawnCoords = roachArea + randomOffset
    
    local roachModel = 'a_c_rat'
    RequestModel(roachModel)
    while not HasModelLoaded(roachModel) do
        Wait(10)
    end
    
    local roachId = 'roach_' .. businessId .. '_' .. GetGameTimer()
    local ped = CreatePed(28, GetHashKey(roachModel), spawnCoords.x, spawnCoords.y, spawnCoords.z, 0.0, false, false)
    
    SetEntityHealth(ped, 100)
    SetPedCanRagdoll(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskWanderInArea(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z, roachRadius, 1.0, 1.0)
    
    roachPeds[roachId] = {
        ped = ped,
        businessId = businessId,
        coords = spawnCoords
    }
end)

-- Remove roach
RegisterNetEvent('pf-restaurants:client:removeRoach', function(businessId, roachId)
    if roachPeds[roachId] then
        if DoesEntityExist(roachPeds[roachId].ped) then
            DeleteEntity(roachPeds[roachId].ped)
        end
        roachPeds[roachId] = nil
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, trashData in pairs(trashProps) do
            if DoesEntityExist(trashData.prop) then
                DeleteEntity(trashData.prop)
            end
        end
        
        for _, roachData in pairs(roachPeds) do
            if DoesEntityExist(roachData.ped) then
                DeleteEntity(roachData.ped)
            end
        end
    end
end)
