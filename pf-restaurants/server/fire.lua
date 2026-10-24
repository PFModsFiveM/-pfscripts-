-- Fire system management

local activeFires = {}

-- Start fire
-- Server-only: raised by the burnt-food check (any client could start fires when it was a net event)
AddEventHandler('pf-restaurants:server:startFire', function(businessId, stationId)
    local fireId = 'fire_' .. businessId .. '_' .. stationId .. '_' .. os.time()
    
    local station = RestaurantData.stations[businessId] and RestaurantData.stations[businessId][stationId]
    if not station then return end
    
    activeFires[fireId] = {
        fireId = fireId,
        businessId = businessId,
        stationId = stationId,
        coords = station.coords,
        startTime = os.time(),
        intensity = 1,
        spreading = false
    }
    
    -- Broadcast fire start
    TriggerClientEvent('pf-restaurants:client:startFire', -1, fireId, activeFires[fireId])
    
    -- Damage equipment
    local equipment = RestaurantData.equipment[businessId][stationId]
    equipment.condition = math.max(0, equipment.condition - Config.Fire.EquipmentConditionLoss)
    
    -- Damage hygiene
    local business = RestaurantData.businesses[businessId]
    business.hygiene.dirtLevel = business.hygiene.dirtLevel + Config.Fire.HygienePenalty
    
    UpdateHealthRating(businessId)
    
    -- Log incident
    LogAction('fire_incident', {
        fireId = fireId,
        businessId = businessId,
        stationId = stationId,
        timestamp = os.time()
    })
    
    -- Fire spread check
    SetTimeout(30000, function() -- Check for spread after 30 seconds
        if activeFires[fireId] and not activeFires[fireId].spreading then
            CheckFireSpread(fireId)
        end
    end)
end)

-- Extinguish fire
RegisterNetEvent('pf-restaurants:server:extinguishFire', function(fireId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local fire = activeFires[fireId]
    if not fire then
        NotifyPlayer(src, 'Fire not found', 'error')
        return
    end
    
    -- Check for fire extinguisher
    local hasExtinguisher = Player.Functions.GetItemByName('fire_extinguisher')
    if not hasExtinguisher then
        NotifyPlayer(src, 'Need fire extinguisher', 'error')
        return
    end
    
    -- Extinguish fire
    activeFires[fireId] = nil
    
    NotifyPlayer(src, 'Fire extinguished!', 'success')
    TriggerClientEvent('pf-restaurants:client:extinguishFire', -1, fireId)
    
    -- Reset equipment burnt count
    local equipment = RestaurantData.equipment[fire.businessId][fire.stationId]
    equipment.burntCount = 0
end)

-- Check for fire spread
function CheckFireSpread(fireId)
    local fire = activeFires[fireId]
    if not fire then return end
    
    if math.random() < Config.Fire.SpreadChance then
        -- Find nearby stations
        local businessId = fire.businessId
        local fireCoords = fire.coords
        
        for stationId, station in pairs(RestaurantData.stations[businessId]) do
            if stationId ~= fire.stationId then
                local distance = #(fireCoords - station.coords)
                if distance <= Config.Fire.SpreadRadius then
                    -- Spread fire!
                    fire.spreading = true
                    TriggerEvent('pf-restaurants:server:startFire', businessId, stationId)
                    break
                end
            end
        end
    end
end

-- Auto extinguish after time (fire department or sprinklers placeholder)
CreateThread(function()
    while true do
        Wait(60000) -- Check every minute
        
        for fireId, fire in pairs(activeFires) do
            local duration = os.time() - fire.startTime
            
            -- Auto extinguish after 10 minutes (or call fire dept)
            if duration > 600 then
                activeFires[fireId] = nil
                TriggerClientEvent('pf-restaurants:client:extinguishFire', -1, fireId)
                print('[pf-restaurants] Fire ' .. fireId .. ' auto-extinguished after timeout')
            end
        end
    end
end)

-- Get active fires
QBCore.Functions.CreateCallback('pf-restaurants:server:getActiveFires', function(source, cb, businessId)
    local fires = {}
    for fireId, fire in pairs(activeFires) do
        if fire.businessId == businessId then
            fires[fireId] = fire
        end
    end
    cb(fires)
end)
