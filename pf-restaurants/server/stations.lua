-- Station session management and cooking mechanics

local sessionIdCounter = 1

-- Cooking uses the restaurant's stock (server/inventory.lua), not the cook's pockets: the inputs of
-- the chosen prep rule are taken all-or-nothing when cooking starts. The cook must be at the station,
-- the server keeps the time, a dish without a doneness level cannot be taken off before it is done,
-- and the output goes to the cook (if their inventory is full the session stays open, nothing is lost).

local function atStation(src, station)
    local coords = station.coords
    if not coords then return false end
    local range = (Config.Cooking and Config.Cooking.StationRange) or 3.0
    return #(GetEntityCoords(GetPlayerPed(src)) - vector3(coords.x, coords.y, coords.z)) <= range
end

-- Start a station action
RegisterNetEvent('pf-restaurants:server:startStationAction', function(businessId, stationId, slotId, actionData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if type(businessId) ~= 'string' or type(actionData) ~= 'table' then return end

    if not HasPermission(src, businessId, 'station.use') then
        NotifyPlayer(src, 'No permission to use stations', 'error')
        return
    end

    local station = RestaurantData.stations[businessId] and RestaurantData.stations[businessId][stationId]
    if not station then
        NotifyPlayer(src, 'Station not found', 'error')
        return
    end
    if not atStation(src, station) then
        NotifyPlayer(src, 'You are not at the station', 'error')
        return
    end

    local slot = station.slots[tonumber(slotId) or 0]
    if not slot then
        NotifyPlayer(src, 'Invalid slot', 'error')
        return
    end
    if slot.occupied then
        NotifyPlayer(src, 'Slot is occupied', 'error')
        return
    end

    local rule = FindComponentRule(actionData.action, station.type, actionData.inputItems)
    if not rule then
        NotifyPlayer(src, 'Invalid recipe for this station', 'error')
        return
    end

    -- every ingredient from the restaurant's stock, or none
    local ok, consumed = ConsumeIngredients(businessId, rule.input)
    if not ok then
        NotifyPlayer(src, 'Not enough ' .. tostring(consumed) .. ' in stock', 'error')
        return
    end

    -- the worst ingredient decides how good the result can be
    local ingredientQuality = 100
    for _, c in ipairs(consumed) do ingredientQuality = math.min(ingredientQuality, tonumber(c.pct) or 100) end

    sessionIdCounter = sessionIdCounter + 1
    local sessionId = ('session_%d_%d'):format(os.time(), sessionIdCounter)
    local equipment = RestaurantData.equipment[businessId][stationId]

    local session = {
        sessionId = sessionId,
        businessId = businessId,
        stationId = stationId,
        slotId = tonumber(slotId),
        playerSrc = src,
        playerCid = Player.PlayerData.citizenid,
        action = rule.action,
        inputItems = rule.input,
        consumed = consumed,
        ingredientQuality = ingredientQuality,
        outputItem = rule.output[1].item,
        outputQty = rule.output[1].qty,
        startTime = os.time(),
        duration = rule.duration,
        requiresDoneness = rule.requiresDoneness or false,
        donenessTarget = type(actionData.donenessTarget) == 'string' and actionData.donenessTarget or 'medium',
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

    TriggerClientEvent('pf-restaurants:client:stationSessionStart', -1, businessId, stationId, session.slotId, session)

    local degradation = Config.Equipment.DegradationPerUse[station.type] or 1
    equipment.cleanliness = math.max(0, equipment.cleanliness - degradation)
    if station.type == 'fryer' then
        equipment.oilQuality = math.max(0, equipment.oilQuality - Config.Equipment.FryerOilDegradationPerUse)
    elseif station.type == 'drink' then
        equipment.iceLevel = math.max(0, equipment.iceLevel - Config.Equipment.IceDepletionPerUse)
    end
end)

local function closeSession(businessId, stationId, slotId, sessionId)
    local station = RestaurantData.stations[businessId][stationId]
    local slot = station.slots[slotId]
    if slot then
        slot.occupied = false
        slot.session = nil
    end
    station.sessions[sessionId] = nil
    TriggerClientEvent('pf-restaurants:client:stationSessionEnd', -1, businessId, stationId, slotId, sessionId)
end

-- Complete station action (take the item off the station)
RegisterNetEvent('pf-restaurants:server:completeStationAction', function(sessionId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local session, businessId, stationId, slotId = FindSession(sessionId)
    if not session then
        NotifyPlayer(src, 'Session not found', 'error')
        return
    end
    if session.playerSrc ~= src then
        NotifyPlayer(src, 'Not your session', 'error')
        return
    end
    if not atStation(src, RestaurantData.stations[businessId][stationId]) then
        NotifyPlayer(src, 'You are not at the station', 'error')
        return
    end

    local elapsed = os.time() - session.startTime
    local progress = elapsed / (session.duration / 1000)

    -- without a doneness level, a dish is only ready when its time is up
    if not session.requiresDoneness and progress < ((Config.Cooking and Config.Cooking.MinProgressPlain) or 1.0) then
        NotifyPlayer(src, 'Not ready yet', 'error')
        return
    end

    local doneness = 'perfect'
    local quality = 100
    local isBurnt = false
    local outputItem, outputQty = session.outputItem, session.outputQty

    if session.requiresDoneness then
        doneness, quality, isBurnt = CalculateDoneness(progress, session.donenessTarget)
    elseif progress > 1.2 then
        isBurnt = true
    end
    if isBurnt then
        outputItem, outputQty = 'burnt_food', 1
    end

    quality = ApplyQualityPenalties(quality, session.qualitySnapshot)
    quality = quality * ((tonumber(session.ingredientQuality) or 100) / 100)
    local poisonRisk = CalculatePoisonRisk(session.qualitySnapshot, doneness)
    if (tonumber(session.ingredientQuality) or 100) < 25 then poisonRisk = math.min(1, poisonRisk + 0.25) end

    local metadata = {
        quality = math.floor(quality),
        doneness = session.requiresDoneness and doneness or nil,
        madeBy = session.playerCid,
        businessId = businessId,
        timestamp = os.time(),
        poisonRisk = poisonRisk
    }

    -- the output first; if it cannot be given the session stays, so the dish is not lost
    if not exports['pfm-inventory']:AddItem(src, outputItem, outputQty, false, metadata, 'pf-restaurants:cook') then
        NotifyPlayer(src, 'Your inventory is full', 'error')
        return
    end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[outputItem], 'add', outputQty)

    if isBurnt then
        local equipment = RestaurantData.equipment[businessId][stationId]
        equipment.burntCount = equipment.burntCount + 1
        CheckForFire(businessId, stationId)
    end

    closeSession(businessId, stationId, slotId, sessionId)

    if isBurnt then
        NotifyPlayer(src, 'Item burnt!', 'error')
    else
        NotifyPlayer(src, 'Item completed - Quality: ' .. math.floor(quality) .. '%', 'success')
    end
end)

-- A cook who leaves mid-session: the ingredients go back to stock and the slot is freed
AddEventHandler('playerDropped', function()
    local src = source
    for businessId, stations in pairs(RestaurantData.stations) do
        for stationId, station in pairs(stations) do
            for sessionId, session in pairs(station.sessions) do
                if session.playerSrc == src then
                    ReturnIngredients(businessId, session.consumed)
                    closeSession(businessId, stationId, session.slotId, sessionId)
                end
            end
        end
    end
end)

-- Get current station sessions (for client sync)
QBCore.Functions.CreateCallback('pf-restaurants:server:getStationSessions', function(source, cb, businessId)
    local sessions = {}
    if type(businessId) ~= 'string' or not RoleOf(source, businessId) then cb(sessions) return end
    
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
