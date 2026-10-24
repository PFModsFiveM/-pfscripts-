-- Fire system client-side

local activeFires = {}

-- Start fire effect
RegisterNetEvent('pf-restaurants:client:startFire', function(fireId, fireData)
    activeFires[fireId] = fireData
    
    -- Start particle effects
    RequestNamedPtfxAsset('core')
    while not HasNamedPtfxAssetLoaded('core') do
        Wait(10)
    end
    
    local coords = fireData.coords
    
    CreateThread(function()
        while activeFires[fireId] do
            UseParticleFxAssetNextCall('core')
            local particle = StartParticleFxLoopedAtCoord(
                'ent_ray_paleto_gas_flames',
                coords.x, coords.y, coords.z,
                0.0, 0.0, 0.0,
                1.0,
                false, false, false, false
            )
            
            activeFires[fireId].particle = particle
            
            Wait(1000)
        end
    end)
    
    ShowNotification('FIRE! Use a fire extinguisher!', 'error')
end)

-- Extinguish fire
RegisterNetEvent('pf-restaurants:client:extinguishFire', function(fireId)
    if activeFires[fireId] then
        if activeFires[fireId].particle then
            StopParticleFxLooped(activeFires[fireId].particle, false)
        end
        activeFires[fireId] = nil
    end
end)

-- Use fire extinguisher
RegisterNetEvent('pf-restaurants:client:useExtinguisher', function(fireId)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    local fire = activeFires[fireId]
    if not fire then
        ShowNotification('No fire nearby', 'error')
        return
    end
    
    local distance = #(playerCoords - fire.coords)
    if distance > 5.0 then
        ShowNotification('Too far from fire', 'error')
        return
    end
    
    -- Play extinguishing animation
    RequestAnimDict('weapon@w_sp_jerrycan')
    while not HasAnimDictLoaded('weapon@w_sp_jerrycan') do
        Wait(10)
    end
    
    TaskPlayAnim(playerPed, 'weapon@w_sp_jerrycan', 'fire', 8.0, -8.0, -1, 1, 0, false, false, false)
    
    QBCore.Functions.Progressbar('extinguish_fire', 'Extinguishing fire...', 10000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function() -- Done
        ClearPedTasks(playerPed)
        TriggerServerEvent('pf-restaurants:server:extinguishFire', fireId)
    end, function() -- Cancel
        ClearPedTasks(playerPed)
    end)
end)

-- Draw fire warnings
CreateThread(function()
    while true do
        local sleep = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        
        for fireId, fire in pairs(activeFires) do
            local distance = #(playerCoords - fire.coords)
            
            if distance <= 10.0 then
                sleep = 0
                DrawMarker(1, fire.coords.x, fire.coords.y, fire.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 1.0, 255, 0, 0, 100, false, true, 2, false, nil, nil, false)
                
                if distance <= 3.0 then
                    Draw3DText(fire.coords + vector3(0.0, 0.0, 1.0), '~r~FIRE! ~w~Press ~g~E ~w~to extinguish')
                    
                    if IsControlJustReleased(0, 38) then -- E
                        TriggerEvent('pf-restaurants:client:useExtinguisher', fireId)
                    end
                end
            end
        end
        
        Wait(sleep)
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for fireId, fire in pairs(activeFires) do
            if fire.particle then
                StopParticleFxLooped(fire.particle, false)
            end
        end
    end
end)
