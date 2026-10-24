-- Station session management and cooking mechanics

local sessionIdCounter = 1

-- Start a station action
RegisterNetEvent('pf-restaurants:server:startStationAction', function(businessId, stationId, slotId, actionData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'station.use') then
        NotifyPlayer(src, 'No permission to use stations', 'error')
        return
    end
    
    -- Get station
    if not RestaurantData.stations[businessId] or not RestaurantData.stations[businessId][stationId] then
        NotifyPlayer(src, 'Station not found', 'error')
        return
    end
    
    local station = RestaurantData.stations[businessId][stationId]
    local slot = station.slots[slotId]
    
    if not slot then
        NotifyPlayer(src, 'Invalid slot', 'error')
        return
    end
    
    if slot.occupied then
        NotifyPlayer(src, 'Slot is occupied', 'error')
        return
    end
    
    -- Find matching component rule
    local rule = FindComponentRule(actionData.action, station.type, actionData.inputItems)
    if not rule then
        NotifyPlayer(src, 'Invalid recipe for this station', 'error')
        return
    end
    
    -- Validate player has items
    for _, input in ipairs(rule.input) do
        local hasItem = Player.Functions.GetItemByName(input.item)
        if not hasItem or hasItem.amount < input.qty then
            NotifyPlayer(src, 'Missing required items', 'error')
            return
        end
    end
    
    -- Remove input items
    for _, input in ipairs(rule.input) do
        Player.Functions.RemoveItem(input.item, input.qty)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[input.item], 'remove', input.qty)
    end
    
    -- Create session
    sessionIdCounter = sessionIdCounter + 1
    local sessionId = 'session_' .. sessionIdCounter
    
    local equipment = RestaurantData.equipment[businessId][stationId]
    
    local session = {
        sessionId = sessionId,
        businessId = businessId,
        stationId = stationId,
        slotId = slotId,
        playerSrc = src,
        playerCid = Player.PlayerData.citizenid,
        action = actionData.action,
        inputItems = rule.input,
        outputItem = rule.output[1].item,
        outputQty = rule.output[1].qty,
        startTime = os.time(),
        duration = rule.duration,
        requiresDoneness = rule.requiresDoneness or false,
        donenessTarget = actionData.donenessTarget or 'medium',
        qualitySnapshot = {
            cleanliness = equipment.cleanliness,
            condition = equipment.condition,
            oilQuality = equipment.oilQuality,
            hygieneRating = RestaurantData.businesses[businessId].hygiene.healthRating
        }
    }
    
    slot.occupied = true
    slot.session = sessionId
    station.sessions[sessionId] = session
    
    -- Broadcast to all players for visual sync
    TriggerClientEvent('pf-restaurants:client:stationSessionStart', -1, businessId, stationId, slotId, session)
    
    -- Degrade equipment cleanliness
    local degradation = Config.Equipment.DegradationPerUse[station.type] or 1
    equipment.cleanliness = math.max(0, equipment.cleanliness - degradation)
    
    if station.type == 'fryer' then
        equipment.oilQuality = math.max(0, equipment.oilQuality - Config.Equipment.FryerOilDegradationPerUse)
    elseif station.type == 'drink' then
        equipment.iceLevel = math.max(0, equipment.iceLevel - Config.Equipment.IceDepletionPerUse)
    end
end)

-- Complete station action (remove item from station)
RegisterNetEvent('pf-restaurants:server:completeStationAction', function(sessionId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Find session
    local session, businessId, stationId, slotId = FindSession(sessionId)
    if not session then
        NotifyPlayer(src, 'Session not found', 'error')
        return
    end
    
    if session.playerSrc ~= src then
        NotifyPlayer(src, 'Not your session', 'error')
        return
    end
    
    -- Calculate doneness and quality
    local elapsed = os.time() - session.startTime
    local progress = elapsed / (session.duration / 1000) -- Convert to seconds
    
    local doneness = 'perfect'
    local quality = 100
    local poisonRisk = 0
    local isBurnt = false
    
    if session.requiresDoneness then
        doneness, quality, isBurnt = CalculateDoneness(progress, session.donenessTarget)
        
        if isBurnt then
            -- Increase fire risk
            local equipment = RestaurantData.equipment[businessId][stationId]
            equipment.burntCount = equipment.burntCount + 1
            
            -- Check for fire
            CheckForFire(businessId, stationId)
            
            -- Output becomes burnt food
            session.outputItem = 'burnt_food'
            session.outputQty = 1
        end
    else
        -- Non-doneness items just check if overcooked
        if progress > 1.2 then
            isBurnt = true
            session.outputItem = 'burnt_food'
            session.outputQty = 1
        end
    end
    
    -- Apply quality penalties from equipment and hygiene
    quality = ApplyQualityPenalties(quality, session.qualitySnapshot)
    
    -- Calculate poison risk
    poisonRisk = CalculatePoisonRisk(session.qualitySnapshot, doneness)
    
    -- Create output item with metadata
    local metadata = {
        quality = quality,
        doneness = session.requiresDoneness and doneness or nil,
        madeBy = session.playerCid,
        businessId = businessId,
        timestamp = os.time(),
        poisonRisk = poisonRisk
    }
    
    Player.Functions.AddItem(session.outputItem, session.outputQty, false, metadata)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[session.outputItem], 'add', session.outputQty)
    
    -- Clear session
    local station = RestaurantData.stations[businessId][stationId]
    local slot = station.slots[slotId]
    slot.occupied = false
    slot.session = nil
    station.sessions[sessionId] = nil
    
    -- Broadcast completion
    TriggerClientEvent('pf-restaurants:client:stationSessionEnd', -1, businessId, stationId, slotId, sessionId)
    
    if isBurnt then
        NotifyPlayer(src, 'Item burnt!', 'error')
    else
        NotifyPlayer(src, 'Item completed - Quality: ' .. math.floor(quality) .. '%', 'success')
    end
end)

-- Get current station sessions (for client sync)
QBCore.Functions.CreateCallback('pf-restaurants:server:getStationSessions', function(source, cb, businessId)
    local sessions = {}
    
    if RestaurantData.stations[businessId] then
        for stationId, station in pairs(RestaurantData.stations[businessId]) do
            for sessionId, session in pairs(station.sessions) do
                sessions[sessionId] = session
            end
        end
    end
    
    cb(sessions)
end)

-- Helper: Find component rule
function FindComponentRule(action, stationType, inputItems)
    for _, rule in ipairs(Config.ComponentRules) do
        if rule.action == action and rule.stationType == stationType then
            -- Validate inputs match
            local matches = true
            for _, ruleInput in ipairs(rule.input) do
                local found = false
                for _, input in ipairs(inputItems or {}) do
                    if input.item == ruleInput.item and input.qty == ruleInput.qty then
                        found = true
                        break
                    end
                end
                if not found then
                    matches = false
                    break
                end
            end
            
            if matches then
                return rule
            end
        end
    end
    return nil
end

-- Helper: Find session by ID
function FindSession(sessionId)
    for businessId, stations in pairs(RestaurantData.stations) do
        for stationId, station in pairs(stations) do
            if station.sessions[sessionId] then
                for slotId, slot in ipairs(station.slots) do
                    if slot.session == sessionId then
                        return station.sessions[sessionId], businessId, stationId, slotId
                    end
                end
            end
        end
    end
    return nil
end

-- Helper: Calculate doneness
function CalculateDoneness(progress, targetDoneness)
    local doneness = 'perfect'
    local quality = 100
    local isBurnt = false
    
    if progress < Config.Quality.Undercooked.max then
        doneness = 'undercooked'
        quality = 50
    elseif progress >= Config.Quality.Burnt.min then
        doneness = 'burnt'
        quality = 0
        isBurnt = true
    elseif progress >= Config.Quality.Rare.min and progress <= Config.Quality.Rare.max then
        doneness = 'rare'
        quality = targetDoneness == 'rare' and 100 or 80
    elseif progress >= Config.Quality.MediumRare.min and progress <= Config.Quality.MediumRare.max then
        doneness = 'medium-rare'
        quality = targetDoneness == 'medium-rare' and 100 or 85
    elseif progress >= Config.Quality.Medium.min and progress <= Config.Quality.Medium.max then
        doneness = 'medium'
        quality = targetDoneness == 'medium' and 100 or 90
    elseif progress >= Config.Quality.WellDone.min and progress <= Config.Quality.WellDone.max then
        doneness = 'well-done'
        quality = targetDoneness == 'well-done' and 100 or 85
    else
        doneness = 'overcooked'
        quality = 60
    end
    
    return doneness, quality, isBurnt
end

-- Helper: Apply quality penalties
function ApplyQualityPenalties(baseQuality, qualitySnapshot)
    local quality = baseQuality
    
    -- Cleanliness penalty
    if qualitySnapshot.cleanliness < 100 then
        local cleanlinessLoss = (100 - qualitySnapshot.cleanliness) * Config.Quality.CleanlinessPerPoint
        quality = quality - cleanlinessLoss
    end
    
    -- Condition penalty
    if qualitySnapshot.condition < 100 then
        local conditionLoss = (100 - qualitySnapshot.condition) * Config.Quality.ConditionPerPoint
        quality = quality - conditionLoss
    end
    
    -- Hygiene rating penalty
    local hygieneScore = 100
    if qualitySnapshot.hygieneRating == 'B' then hygieneScore = 80
    elseif qualitySnapshot.hygieneRating == 'C' then hygieneScore = 60
    elseif qualitySnapshot.hygieneRating == 'D' then hygieneScore = 40
    elseif qualitySnapshot.hygieneRating == 'F' then hygieneScore = 20
    end
    
    quality = quality * (hygieneScore / 100)
    
    return math.max(0, math.min(100, quality))
end

-- Helper: Calculate poison risk
function CalculatePoisonRisk(qualitySnapshot, doneness)
    local risk = 0
    
    if doneness == 'undercooked' then
        risk = risk + Config.Quality.UndercookedRisk
    end
    
    if qualitySnapshot.cleanliness < 50 then
        risk = risk + Config.Quality.DirtyEquipmentRisk
    end
    
    if qualitySnapshot.hygieneRating == 'F' or qualitySnapshot.hygieneRating == 'D' then
        risk = risk + Config.Quality.RoachesRisk
    end
    
    return math.min(1, risk)
end

-- Helper: Check for fire
function CheckForFire(businessId, stationId)
    local equipment = RestaurantData.equipment[businessId][stationId]
    
    if equipment.burntCount < Config.Fire.BurntCountForRisk then
        return
    end
    
    local probability = Config.Fire.BurntFoodBaseProbability
    
    if equipment.cleanliness < Config.Fire.CleanlinessThreshold then
        probability = probability * Config.Fire.LowCleanlinessMultiplier
    end
    
    if equipment.oilQuality and equipment.oilQuality < Config.Fire.OilQualityThreshold then
        probability = probability * Config.Fire.LowOilQualityMultiplier
    end
    
    probability = probability * (equipment.burntCount / Config.Fire.BurntCountForRisk) * Config.Fire.ConsecutiveBurnsMultiplier
    
    if math.random() < probability then
        -- Trigger fire!
        TriggerEvent('pf-restaurants:server:startFire', businessId, stationId)
    end
end
