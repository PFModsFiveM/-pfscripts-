local QBCore = exports['pfm-core']:GetCoreObject()

local TaxiProfiles = {}
local TaxiSessions = {}
local ActiveRides = {}
local RentedVehicles = {}

local function getPlayer(src)
    return QBCore.Functions.GetPlayer(src)
end

local function getTaxiCfg()
    return Config.Taxi or {}
end

local function getLevels()
    return (getTaxiCfg().Levels or {})
end

local function getLevelFromXP(xp)
    local levels = getLevels()
    local level = 1
    for i = #levels, 1, -1 do
        if (xp or 0) >= (levels[i].xp or 0) then
            level = levels[i].level or i
            break
        end
    end
    return level
end

local function getLevelInfo(level)
    for _, info in ipairs(getLevels()) do
        if (info.level or 1) == level then
            return info
        end
    end
    return { level = level, xp = 0, title = 'Driver', unlocks = '' }
end

local function getNextLevelInfo(level)
    local target = (level or 1) + 1
    for _, info in ipairs(getLevels()) do
        if (info.level or 1) == target then
            return info
        end
    end
    return nil
end

local function getDistanceMiles(fromCoords, toCoords)
    if not fromCoords or not toCoords then return 0.0 end
    local a = vector3(fromCoords.x or 0.0, fromCoords.y or 0.0, fromCoords.z or 0.0)
    local b = vector3(toCoords.x or 0.0, toCoords.y or 0.0, toCoords.z or 0.0)
    return #(a - b) / 1609.34
end

local function ensureSession(src)
    if not TaxiSessions[src] then
        TaxiSessions[src] = {
            accepting = false,
            ridesThisRun = 0,
            earningsThisRun = 0,
            activeRideId = nil,
            generatedCalls = {},
            completedSinceRun = 0,
            lastCallTime = 0,
            collisionsThisRide = 0,
            rideStartHealth = 0,
        }
    end
    return TaxiSessions[src]
end

local function loadProfile(src)
    local player = getPlayer(src)
    if not player then return nil end

    local cid = player.PlayerData and player.PlayerData.citizenid
    if not cid then return nil end

    if TaxiProfiles[src] then
        return TaxiProfiles[src]
    end

    local profile = {
        citizenId = cid,
        xp = 0,
        level = 1,
        totalRides = 0,
        totalEarnings = 0,
        averageRating = 5.0,
        totalMiles = 0,
    }

    local cfg = getTaxiCfg()
    if cfg.UseDatabase then
        local row = MySQL.Sync.fetchAll('SELECT * FROM taxi_stats WHERE citizen_id = ?', { cid })
        if row and row[1] then
            local data = row[1]
            profile.totalMiles = tonumber(data.total_miles) or 0
            profile.totalEarnings = tonumber(data.total_earnings) or 0
            profile.totalRides = tonumber(data.total_rides) or 0
            profile.averageRating = tonumber(data.average_rating) or 5.0
            profile.level = tonumber(data.current_level) or 1
            profile.xp = math.max(profile.totalRides * 120, profile.totalMiles * 25)
            profile.level = getLevelFromXP(profile.xp)
        else
            MySQL.Async.execute(
                'INSERT INTO taxi_stats (citizen_id, total_miles, total_earnings, total_rides, total_time, average_rating, streak_count, best_streak, current_level) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                { cid, 0, 0, 0, 0, 5.0, 0, 0, 1 }
            )
        end
    else
        profile.xp = tonumber(player.PlayerData.metadata and player.PlayerData.metadata.taxi_xp) or 0
        profile.level = getLevelFromXP(profile.xp)
    end

    TaxiProfiles[src] = profile
    return profile
end

local function saveProfile(src)
    local player = getPlayer(src)
    local profile = TaxiProfiles[src]
    if not player or not profile then return end

    local cfg = getTaxiCfg()
    profile.level = getLevelFromXP(profile.xp)

    if cfg.UseDatabase then
        MySQL.Async.execute(
            'UPDATE taxi_stats SET total_miles = ?, total_earnings = ?, total_rides = ?, average_rating = ?, current_level = ?, updated_at = CURRENT_TIMESTAMP WHERE citizen_id = ?',
            {
                profile.totalMiles,
                profile.totalEarnings,
                profile.totalRides,
                profile.averageRating,
                profile.level,
                profile.citizenId
            }
        )
    else
        player.Functions.SetMetaData('taxi_xp', profile.xp)
    end
end

local function buildDashboardData(src)
    local session = ensureSession(src)
    local profile = loadProfile(src)
    if not profile then return nil end

    local levelInfo = getLevelInfo(profile.level)
    local nextLevel = getNextLevelInfo(profile.level)

    return {
        accepting = session.accepting,
        level = profile.level,
        levelTitle = levelInfo.title or 'Driver',
        xp = math.floor(profile.xp),
        rating = tonumber(profile.averageRating) or 5.0,
        ridesCompletedRun = session.completedSinceRun or 0,
        earningsRun = session.earningsThisRun or 0,
        totalRides = profile.totalRides,
        totalEarnings = profile.totalEarnings,
        totalMiles = profile.totalMiles,
        nextLevel = nextLevel and {
            level = nextLevel.level,
            xpRequired = nextLevel.xp,
            unlocks = nextLevel.unlocks or ''
        } or nil,
        levels = getLevels(),
        unlocks = {
            privateVehicleLevel = ((getTaxiCfg().LevelUnlocks or {}).privateVehicle or 4),
            luxuryVehicleLevel = ((getTaxiCfg().LevelUnlocks or {}).luxuryVehicle or 5),
            premiumClientLevel = ((getTaxiCfg().LevelUnlocks or {}).premiumClients or 3),
        },
        rentalVehicles = (getTaxiCfg().RentalVehicles or {}),
        activeRide = session.activeRideId and ActiveRides[session.activeRideId] or nil,
    }
end

local function randomFrom(list)
    if type(list) ~= 'table' or #list == 0 then return nil end
    return list[math.random(1, #list)]
end

local function generateClient(level)
    local cfg = getTaxiCfg()
    local templates = cfg.PreconfiguredClients or {}
    
    -- 10% chance for Michael De Santa (VIP)
    if math.random(100) <= 10 then
        for _, template in ipairs(templates) do
            if template.vip then
                return {
                    name = template.name or 'Customer',
                    premium = true,
                    playerClient = false,
                    vip = true,
                    pedModel = template.pedModel,
                }
            end
        end
    end
    
    local template = randomFrom(templates) or { name = 'Unknown Rider', premium = false, playerClient = false }

    local playerChance = tonumber(cfg.PlayerClientChance or 0.08) or 0.08
    local premiumChance = tonumber(cfg.RarePremiumChance or 0.12) or 0.12
    local vipChance = tonumber(cfg.VIPChance or 0.10) or 0.10
    local premiumUnlock = ((cfg.LevelUnlocks or {}).premiumClients or 3)

    local isPlayerClient = (math.random() < playerChance)
    local isPremium = false

    if not isPlayerClient and level >= premiumUnlock and math.random() < premiumChance then
        isPremium = true
    end
    if template.premium and level >= premiumUnlock then
        isPremium = true
    end

    return {
        name = template.name or 'Customer',
        premium = isPremium,
        playerClient = isPlayerClient,
        vip = false,
    }
end

local function generateCall(src)
    local profile = loadProfile(src)
    if not profile then return nil end

    local cfg = getTaxiCfg()
    local pickup = randomFrom(cfg.PickupPoints or {})
    local destination = randomFrom(cfg.Destinations or {})
    if not pickup or not destination then return nil end

    local client = generateClient(profile.level)
    local distance = getDistanceMiles(pickup, destination.coords)

    local baseFare = math.max(50, math.floor(distance * (cfg.Pricing and cfg.Pricing.basePricePerMile or 60)))
    if client.premium then
        baseFare = math.floor(baseFare * (cfg.Pricing and cfg.Pricing.premiumMultiplier or 1.5))
    end
    if client.playerClient then
        baseFare = math.floor(baseFare * (cfg.Pricing and cfg.Pricing.playerClientMultiplier or 2.0))
    end

    local callId = ('TAXI_%s_%04d'):format(os.time(), math.random(1000, 9999))

    local levelUnlocks = (cfg.LevelUnlocks or {})
    local premiumLevel = levelUnlocks.premiumClients or 3
    local vipLevel = levelUnlocks.vipClients or levelUnlocks.luxuryVehicle or 5

    local requiredLevel = 1
    if client.vip then
        requiredLevel = vipLevel
    elseif client.premium then
        requiredLevel = premiumLevel
    end

    return {
        id = callId,
        clientName = client.name,
        pickup = { x = pickup.x, y = pickup.y, z = pickup.z },
        destination = {
            label = destination.label or 'Destination',
            x = destination.coords.x,
            y = destination.coords.y,
            z = destination.coords.z,
        },
        premium = client.premium,
        vip = client.vip == true,
        pedModel = client.pedModel,
        playerClient = client.playerClient,
        payPreview = client.playerClient and nil or baseFare,
        distanceMiles = distance,
        requiredLevel = requiredLevel,
    }
end

local function filterCallsForLevel(calls, level)
    local filtered = {}
    local playerLevel = tonumber(level) or 1
    for _, call in ipairs(calls or {}) do
        local requiredLevel = tonumber(call.requiredLevel) or 1
        if playerLevel >= requiredLevel then
            filtered[#filtered + 1] = call
        end
    end
    return filtered
end

local function generateCallsForPlayer(src, count)
    local session = ensureSession(src)
    local profile = loadProfile(src)
    local calls = {}
    for i = 1, (count or 5) do
        local call = generateCall(src)
        if call then
            calls[#calls + 1] = call
        end
    end
    calls = filterCallsForLevel(calls, profile and profile.level or 1)
    session.generatedCalls = calls
    return calls
end

local function getLevelFareMultiplier(level)
    local multiplier = 1.0
    if level and level > 1 then
        multiplier = 1.0 + ((level - 1) * 0.05)
    end
    return multiplier
end

local function calculateFareForRide(profile, ride, actualDistanceMiles, collisionsCount, collisionPenaltyPct)
    local cfg = getTaxiCfg()
    local pricing = cfg.Pricing or {}
    local distance = tonumber(actualDistanceMiles) or tonumber(ride.distanceMiles) or 0
    if distance <= 0 then distance = 0.4 end

    local fare = distance * (pricing.basePricePerMile or 60)
    if ride.premium then
        fare = fare * (pricing.premiumMultiplier or 1.5)
    end
    if ride.playerClient then
        fare = fare * (pricing.playerClientMultiplier or 2.0)
    end

    if ride.vip then
        fare = fare * (pricing.vipMultiplier or 0.9)
    end

    fare = fare * getLevelFareMultiplier(profile.level)

    local typedPenalty = tonumber(collisionPenaltyPct) or 0.0
    if typedPenalty > 0.0 then
        local minFareFactor = tonumber(((cfg.CollisionPenalties or {}).minFareFactor)) or 0.10
        local factor = 1.0 - typedPenalty
        if factor < minFareFactor then
            factor = minFareFactor
        end
        fare = fare * factor
    elseif collisionsCount and collisionsCount > 0 then
        local penalty = (pricing.collisionPenalty or 0.05) * collisionsCount
        fare = fare * (1.0 - penalty)
    end

    return math.max(pricing.minimumFare or 50, math.floor(fare))
end

local function computeXP(ride, actualDistanceMiles)
    local dist = tonumber(actualDistanceMiles) or tonumber(ride.distanceMiles) or 0.0
    local xp = math.floor(math.max(1.0, dist) * 55)
    if ride.premium then xp = xp + 40 end
    if ride.playerClient then xp = xp + 70 end
    return xp
end

local function pushTaxiStats(src)
    local payload = buildDashboardData(src)
    if payload then
        TriggerClientEvent('pf-taxi:client:updateStats', src, payload)
    end
end

QBCore.Functions.CreateCallback('pf-taxi:server:getInit', function(source, cb)
    local payload = buildDashboardData(source)
    cb(payload or {})
end)

QBCore.Functions.CreateCallback('pf-taxi:server:getCalls', function(source, cb)
    local session = ensureSession(source)
    local profile = loadProfile(source)
    if not profile then
        cb({})
        return
    end

    if not session.accepting then
        session.generatedCalls = {}
        cb({})
        return
    end

    local cfg = getTaxiCfg()
    local callSystem = cfg.CallSystem or {}
    local minDelay = callSystem.minCallDelay or 30000
    local maxDelay = callSystem.maxCallDelay or 900000
    local currentTime = GetGameTimer()
    
    -- Check if enough time has passed since last call generation
    local timeSinceLastCall = currentTime - (session.lastCallTime or 0)
    local requiredDelay = math.random(minDelay, maxDelay)
    
    if timeSinceLastCall < requiredDelay then
        -- Not enough time passed, return existing calls filtered by current level
        local existingCalls = filterCallsForLevel(session.generatedCalls or {}, profile.level)
        session.generatedCalls = existingCalls
        cb(existingCalls)
        return
    end
    
    -- Apply rating-based call frequency
    local ratingThreshold = 3.0
    if profile.averageRating and profile.averageRating < ratingThreshold then
        -- Low rating = longer wait times
        local ratingPenalty = 1.0 + ((ratingThreshold - profile.averageRating) * 2.0)
        requiredDelay = math.floor(requiredDelay * ratingPenalty)
    end
    
    -- Call generation success chance
    local callGenRate = callSystem.callGenerationRate or 0.8
    if math.random() > callGenRate then
        -- Call generation failed this cycle
        local existingCalls = filterCallsForLevel(session.generatedCalls or {}, profile.level)
        session.generatedCalls = existingCalls
        cb(existingCalls)
        return
    end
    
    -- Generate new calls
    local calls = {}
    local maxCalls = callSystem.maxConcurrentCalls or 8
    for i = 1, math.min(5, maxCalls) do
        local call = generateCall(source)
        if call then
            calls[#calls + 1] = call
        end
    end
    
    calls = filterCallsForLevel(calls, profile.level)
    session.generatedCalls = calls
    session.lastCallTime = currentTime
    cb(calls)
    TriggerClientEvent('pf-taxi:client:callsData', source, calls)
end)

QBCore.Functions.CreateCallback('pf-taxi:server:getPhotos', function(source, cb)
    local src = source
    local player = getPlayer(src)
    if not player then
        cb({})
        return
    end

    local cid = player.PlayerData and player.PlayerData.citizenid
    if not cid then
        cb({})
        return
    end

    local cfg = getTaxiCfg()
    if not cfg.UseDatabase then
        cb({})
        return
    end

    MySQL.Async.fetchAll('SELECT filename, model, plate, timestamp, created_at FROM taxi_vehicle_photos WHERE citizen_id = ? ORDER BY created_at DESC LIMIT 50', {cid}, 
        function(photos)
            local photoList = {}
            if photos and #photos > 0 then
                for _, photo in ipairs(photos) do
                    table.insert(photoList, {
                        filename = photo.filename,
                        model = photo.model or 'Unknown',
                        plate = photo.plate or 'N/A',
                        timestamp = photo.timestamp or photo.created_at or os.date('%Y-%m-%d %H:%M:%S')
                    })
                end
            end
            cb({ photos = photoList })
        end
    )
end)

RegisterNetEvent('pf-taxi:server:toggleAccepting', function(data)
    local src = source
    local session = ensureSession(src)
    session.accepting = data and data.accepting == true or false

    if not session.accepting then
        session.generatedCalls = {}
        TriggerClientEvent('pf-taxi:client:callsData', src, {})
    else
        -- Generate calls immediately when accepting
        local calls = generateCallsForPlayer(src, 5)
        TriggerClientEvent('pf-taxi:client:callsData', src, calls)
    end

    pushTaxiStats(src)
end)

RegisterNetEvent('pf-taxi:server:acceptCall', function(callData)
    local src = source
    local player = getPlayer(src)
    if not player then return end

    local session = ensureSession(src)
    local profile = loadProfile(src)
    if not profile then return end

    if not session.accepting then
        TriggerClientEvent('QBCore:Notify', src, 'Enable accepting rides first', 'error')
        return
    end

    if session.activeRideId then
        TriggerClientEvent('QBCore:Notify', src, 'You already have an active ride', 'error')
        return
    end

    local selected = nil
    for _, call in ipairs(session.generatedCalls or {}) do
        if call.id == (callData and callData.id) then
            selected = call
            break
        end
    end

    if not selected then
        selected = generateCall(src)
    end

    if not selected then
        TriggerClientEvent('QBCore:Notify', src, 'No valid ride call found', 'error')
        return
    end

    local requiredLevel = tonumber(selected.requiredLevel) or 1
    if profile.level < requiredLevel then
        TriggerClientEvent('QBCore:Notify', src, ('This call unlocks at level %d'):format(requiredLevel), 'error')
        return
    end

    local rideId = ('RIDE_%s_%04d'):format(os.time(), math.random(1000, 9999))
    
    -- Use VIP ped model if available, otherwise use random ped
    local pedModel = 'a_m_y_business_01'
    if selected.vip and selected.pedModel then
        pedModel = selected.pedModel
    else
        pedModel = randomFrom(getTaxiCfg().PedModels or { 'a_m_y_business_01' })
    end

    local ride = {
        id = rideId,
        src = src,
        clientName = selected.clientName,
        premium = selected.premium,
        playerClient = selected.playerClient,
        vip = selected.vip,
        pickup = selected.pickup,
        destination = selected.destination,
        distanceMiles = selected.distanceMiles,
        stage = 'pickup',
        startTime = os.time(),
        pedModel = pedModel,
    }

    ActiveRides[rideId] = ride
    session.activeRideId = rideId
    session.collisionsThisRide = 0

    TriggerClientEvent('pf-taxi:client:startCall', src, ride)
    TriggerClientEvent('pf-taxi:client:rideStarted', src, rideId, ride)
    TriggerClientEvent('QBCore:Notify', src, ('Ride accepted: %s'):format(selected.clientName), 'success')
    pushTaxiStats(src)
end)

RegisterNetEvent('pf-taxi:server:ridePickedUp', function(rideId)
    local src = source
    local ride = ActiveRides[rideId]
    if not ride or ride.src ~= src then return end
    ride.stage = 'destination'
end)

RegisterNetEvent('pf-taxi:server:completeRide', function(rideId, completionData)
    local src = source
    local player = getPlayer(src)
    if not player then return end

    local session = ensureSession(src)
    local profile = loadProfile(src)
    if not profile then return end

    local ride = ActiveRides[rideId]
    if not ride or ride.src ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'No active ride found', 'error')
        return
    end

    local actualDistance = completionData and completionData.distanceMiles or nil
    local collisions = completionData and tonumber(completionData.collisions) or 0
    local collisionPenaltyPct = completionData and tonumber(completionData.collisionPenaltyPct) or 0.0
    local collisionTypeCounts = (completionData and type(completionData.collisionTypeCounts) == 'table') and completionData.collisionTypeCounts or {}

    local typedCollisionCount = 0
    for _, value in pairs(collisionTypeCounts) do
        typedCollisionCount = typedCollisionCount + (tonumber(value) or 0)
    end
    if typedCollisionCount > collisions then
        collisions = typedCollisionCount
    end

    local fare = calculateFareForRide(profile, ride, actualDistance, collisions, collisionPenaltyPct)
    local xpGain = computeXP(ride, actualDistance)

    local rating = completionData and tonumber(completionData.rating) or 5.0
    
    -- Apply collision penalties to rating
    local cfg = getTaxiCfg()
    local ratingSystem = cfg.RatingSystem or {}
    if collisions > 0 then
        local collisionPenalty = (ratingSystem.collisionRatingPenalty or 0.2) * collisions
        rating = rating - collisionPenalty
        
        xpGain = math.floor(xpGain * 0.75)  -- 25% XP penalty for collisions
    else
        -- Perfect ride bonus
        rating = rating + (ratingSystem.perfectRideBoost or 0.3)
    end
    
    -- Add completion boost if no perfect
    if collisions == 0 then
        xpGain = math.floor(xpGain * 1.25)  -- 25% XP bonus for perfect ride
    end
    
    rating = math.max(0.0, math.min(5.0, rating))  -- Clamp rating 0-5

    player.Functions.AddMoney('bank', fare, 'taxi-ride-complete')

    profile.totalRides = (profile.totalRides or 0) + 1
    profile.totalEarnings = (profile.totalEarnings or 0) + fare
    profile.totalMiles = (profile.totalMiles or 0) + (tonumber(actualDistance) or tonumber(ride.distanceMiles) or 0)
    profile.xp = (profile.xp or 0) + xpGain

    local priorRides = math.max(1, profile.totalRides)
    profile.averageRating = (((profile.averageRating or 5.0) * (priorRides - 1)) + rating) / priorRides
    profile.level = getLevelFromXP(profile.xp)

    session.earningsThisRun = (session.earningsThisRun or 0) + fare
    session.completedSinceRun = (session.completedSinceRun or 0) + 1
    session.ridesThisRun = (session.ridesThisRun or 0) + 1
    session.activeRideId = nil

    ActiveRides[rideId] = nil
    saveProfile(src)

    TriggerClientEvent('pf-taxi:client:rideCompleted', src, {
        fare = fare,
        xp = xpGain,
        level = profile.level,
        rating = rating,
        collisions = collisions,
        collisionPenaltyPct = collisionPenaltyPct,
        collisionTypeCounts = collisionTypeCounts,
        clientName = ride.clientName,
        premium = ride.premium,
        playerClient = ride.playerClient,
        vip = ride.vip,
    })
    
    local ratingMsg = string.format('%.1f★', rating)
    TriggerClientEvent('QBCore:Notify', src, ('Ride complete! +$%d, +%d XP, Rating: %s'):format(fare, xpGain, ratingMsg), 'success')

    pushTaxiStats(src)
end)

RegisterNetEvent('pf-taxi:server:cancelRide', function(rideId)
    local src = source
    local session = ensureSession(src)
    if not rideId then rideId = session.activeRideId end
    if rideId and ActiveRides[rideId] and ActiveRides[rideId].src == src then
        ActiveRides[rideId] = nil
    end
    session.activeRideId = nil
    TriggerClientEvent('pf-taxi:client:rideCancelled', src)
    TriggerClientEvent('QBCore:Notify', src, 'Ride cancelled', 'error')
    pushTaxiStats(src)
end)

RegisterNetEvent('pf-taxi:server:getStats', function()
    local src = source
    pushTaxiStats(src)
end)

RegisterNetEvent('pf-taxi:server:rentVehicle', function(data)
    local src = source
    local player = getPlayer(src)
    if not player then return end

    local profile = loadProfile(src)
    local cfg = getTaxiCfg()
    local rentalVehicles = cfg.RentalVehicles or {}

    if RentedVehicles[src] then
        TriggerClientEvent('QBCore:Notify', src, 'Return your current rental first', 'error')
        return
    end

    local spawnCode = data and data.spawnCode or nil
    local vehicleCfg = nil
    for _, v in ipairs(rentalVehicles) do
        if v.spawnCode == spawnCode then
            vehicleCfg = v
            break
        end
    end

    if not vehicleCfg then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid rental selection', 'error')
        return
    end

    if profile.level < (vehicleCfg.unlockLevel or 1) then
        TriggerClientEvent('QBCore:Notify', src, ('Unlocks at level %d'):format(vehicleCfg.unlockLevel or 1), 'error')
        return
    end

    local totalCost = (vehicleCfg.rental or 0) + (vehicleCfg.deposit or 0)
    local cash = player.PlayerData.money.cash or 0
    local bank = player.PlayerData.money.bank or 0
    if (cash + bank) < totalCost then
        TriggerClientEvent('QBCore:Notify', src, ('Need $%d to rent this vehicle'):format(totalCost), 'error')
        return
    end

    if cash >= totalCost then
        player.Functions.RemoveMoney('cash', totalCost, 'taxi-rental')
    else
        player.Functions.RemoveMoney('bank', totalCost, 'taxi-rental')
    end

    local spawn = randomFrom(cfg.VehicleSpawns or {})
    if not spawn then
        TriggerClientEvent('QBCore:Notify', src, 'No taxi spawn configured', 'error')
        player.Functions.AddMoney('bank', totalCost, 'taxi-rental-refund')
        return
    end

    local plate = ((cfg.PlatePrefix or 'TAXI') .. math.random(1000, 9999))
    local modelHash = GetHashKey(vehicleCfg.spawnCode)
    local vehicle = CreateVehicleServerSetter(modelHash, 'automobile', spawn.x, spawn.y, spawn.z, spawn.w)

    local timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if not DoesEntityExist(vehicle) then
        player.Functions.AddMoney('bank', totalCost, 'taxi-rental-refund')
        TriggerClientEvent('QBCore:Notify', src, 'Failed to spawn rental vehicle', 'error')
        return
    end

    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleDoorsLocked(vehicle, 1)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', src, plate)

    RentedVehicles[src] = {
        entity = vehicle,
        netId = netId,
        plate = plate,
        spawnCode = vehicleCfg.spawnCode,
        rental = vehicleCfg.rental or 0,
        deposit = vehicleCfg.deposit or 0,
    }

    TriggerClientEvent('pf-taxi:client:vehicleSpawned', src, netId, plate, spawn)
    TriggerClientEvent('QBCore:Notify', src, ('Rented %s for $%d + $%d deposit'):format(vehicleCfg.name or vehicleCfg.spawnCode, vehicleCfg.rental or 0, vehicleCfg.deposit or 0), 'success')
end)

RegisterNetEvent('pf-taxi:server:returnVehicle', function()
    local src = source
    local player = getPlayer(src)
    if not player then return end

    local rental = RentedVehicles[src]
    if not rental then
        TriggerClientEvent('QBCore:Notify', src, 'You do not have an active rental', 'error')
        return
    end

    local damaged = false
    if rental.entity and DoesEntityExist(rental.entity) then
        local engine = GetVehicleEngineHealth(rental.entity)
        local body = GetVehicleBodyHealth(rental.entity)
        if engine < 950.0 or body < 950.0 then
            damaged = true
        end
        DeleteEntity(rental.entity)
    end

    local refund = damaged and 0 or (rental.deposit or 0)
    if refund > 0 then
        player.Functions.AddMoney('bank', refund, 'taxi-deposit-refund')
        TriggerClientEvent('QBCore:Notify', src, ('Vehicle returned. Deposit refunded: $%d'):format(refund), 'success')
    else
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle returned damaged. Deposit forfeited.', 'error')
    end

    RentedVehicles[src] = nil
end)

-- Backward-compatible legacy event hooks
RegisterServerEvent('pf-taxi:server:startRide', function(data)
    local src = source
    local fakeCall = {
        id = ('LEGACY_%s_%d'):format(os.time(), math.random(1000, 9999)),
        clientName = 'Legacy Dispatch',
        pickup = data and data.startCoords or { x = 0.0, y = 0.0, z = 0.0 },
        destination = {
            label = 'Legacy Destination',
            x = data and data.endCoords and data.endCoords.x or 0.0,
            y = data and data.endCoords and data.endCoords.y or 0.0,
            z = data and data.endCoords and data.endCoords.z or 0.0,
        },
        premium = false,
        playerClient = false,
        distanceMiles = tonumber(data and data.distance) or 1.0,
    }
    ensureSession(src).generatedCalls = { fakeCall }
    TriggerEvent('pf-taxi:server:acceptCall', fakeCall)
end)

RegisterServerEvent('pf-taxi:server:completeRideLegacy', function(rideId, completionData)
    TriggerEvent('pf-taxi:server:completeRide', rideId, completionData)
end)

AddEventHandler('playerDropped', function()
    local src = source

    local session = TaxiSessions[src]
    if session and session.activeRideId then
        ActiveRides[session.activeRideId] = nil
    end

    TaxiSessions[src] = nil
    TaxiProfiles[src] = nil

    local rental = RentedVehicles[src]
    if rental and rental.entity and DoesEntityExist(rental.entity) then
        DeleteEntity(rental.entity)
    end
    RentedVehicles[src] = nil
end)

-- Handle collision tracking
RegisterNetEvent('pf-taxi:server:recordCollision', function(rideId, collisionData)
    local src = source
    local session = ensureSession(src)
    local ride = ActiveRides[rideId]
    
    if not ride or ride.src ~= src then return end
    
    session.collisionsThisRide = (session.collisionsThisRide or 0) + 1
end)

-- Handle NPC dialogue trigger
RegisterNetEvent('pf-taxi:server:triggerNPCDialogue', function(rideId, dialogueType)
    local src = source
    local ride = ActiveRides[rideId]
    
    if not ride or ride.src ~= src then return end
    
    local cfg = getTaxiCfg()
    local dialogues = cfg.NPCDialogues or {}
    local typeDialogues = dialogues[dialogueType or 'greeting'] or {}
    
    if #typeDialogues > 0 then
        local selectedDialogue = typeDialogues[math.random(1, #typeDialogues)]
        TriggerClientEvent('pf-taxi:client:npcSay', src, selectedDialogue)
    end
end)

-- Provide fare information to client
RegisterNetEvent('pf-taxi:server:getFareBreakdown', function(rideId)
    local src = source
    local profile = loadProfile(src)
    local ride = ActiveRides[rideId]
    
    if not profile or not ride or ride.src ~= src then return end
    
    local cfg = getTaxiCfg()
    local pricing = cfg.Pricing or {}
    local baseFare = ride.distanceMiles * (pricing.basePricePerMile or 60)
    
    local breakdown = {
        baseFare = math.floor(baseFare),
        distance = ride.distanceMiles,
        premiumMultiplier = ride.premium and (pricing.premiumMultiplier or 1.5) or 1.0,
        playerClientMultiplier = ride.playerClient and (pricing.playerClientMultiplier or 2.0) or 1.0,
        vipDiscount = ride.vip and (0.9) or 1.0,
        levelMultiplier = getLevelFareMultiplier(profile.level),
        estimatedFare = math.floor(baseFare * (ride.premium and (pricing.premiumMultiplier or 1.5) or 1.0) * (ride.playerClient and (pricing.playerClientMultiplier or 2.0) or 1.0) * (ride.vip and (pricing.vipMultiplier or 0.9) or 1.0) * getLevelFareMultiplier(profile.level)),
    }
    
    TriggerClientEvent('pf-taxi:client:fareBreakdown', src, breakdown)
end)
-- Rental vehicle system
RegisterNetEvent('pf-taxi:server:rentVehicle', function(vehicleData)
    local src = source
    local player = getPlayer(src)
    if not player then return end
    
    local moneyType = 'cash'
    local rentalCost = tonumber(vehicleData.rental) or 120
    
    if player.Functions.GetMoney(moneyType) < rentalCost then
        TriggerClientEvent('QBCore:Notify', src, 'You cannot afford this vehicle rental.', 'error')
        return
    end
    
    player.Functions.RemoveMoney(moneyType, rentalCost, 'Taxi Rental Vehicle')
    
    RentedVehicles[src] = {
        data = vehicleData,
        rentedAt = GetGameTimer(),
    }
    
    TriggerClientEvent('pf-taxi:client:vehicleRented', src, vehicleData)
end)

RegisterNetEvent('pf-taxi:server:returnRentalVehicle', function()
    local src = source
    
    RentedVehicles[src] = nil
    TriggerClientEvent('pf-taxi:client:rentalReturned', src)
end)

-- Vehicle photo capture
RegisterNetEvent('pf-taxi:server:capturePhoto', function(photoData)
    local src = source
    local player = getPlayer(src)
    if not player then return end
    
    local cid = player.PlayerData and player.PlayerData.citizenid
    if not cid then return end
    
    local filename = photoData.filename or 'photo_unknown'
    local model = photoData.model or 'unknown'
    local plate = photoData.plate or 'UNKNOWN'
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    
    -- Store photo metadata in database
    local cfg = getTaxiCfg()
    if cfg.UseDatabase then
        -- Create table if it doesn't exist
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS taxi_vehicle_photos (
                id INT AUTO_INCREMENT PRIMARY KEY,
                citizen_id VARCHAR(50) NOT NULL,
                filename VARCHAR(255) NOT NULL,
                model VARCHAR(100),
                plate VARCHAR(20),
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ]], {})
        
        -- Insert photo record
        MySQL.Async.insert('INSERT INTO taxi_vehicle_photos (citizen_id, filename, model, plate, timestamp) VALUES (?, ?, ?, ?, ?)', 
            {cid, filename, model, plate, timestamp},
            function(rowsChanged)
                TriggerClientEvent('QBCore:Notify', src, ('📸 Photo saved: %s'):format(filename), 'success')
                print(('^3[Taxi Photos] ^7New photo: %s | Player: %s | Plate: %s^7'):format(filename, cid, plate))
            end
        )
    else
        TriggerClientEvent('QBCore:Notify', src, ('📸 Photo: %s'):format(filename), 'inform')
    end
end)

-- Get player's captured photos
RegisterNetEvent('pf-taxi:server:getPhotos', function()
    local src = source
    local player = getPlayer(src)
    if not player then return end
    
    local cid = player.PlayerData and player.PlayerData.citizenid
    if not cid then return end
    
    local cfg = getTaxiCfg()
    if cfg.UseDatabase then
        MySQL.Async.fetchAll('SELECT * FROM taxi_vehicle_photos WHERE citizen_id = ? ORDER BY created_at DESC LIMIT 50', {cid}, 
            function(photos)
                if photos and #photos > 0 then
                    local photoList = 'Your captured photos:\n'
                    for i, photo in ipairs(photos) do
                        photoList = photoList .. ('%d. %s - %s (%s)\n'):format(i, photo.filename, photo.model, photo.plate)
                    end
                    TriggerClientEvent('QBCore:Notify', src, photoList, 'success')
                else
                    TriggerClientEvent('QBCore:Notify', src, 'No photos captured yet', 'inform')
                end
            end
        )
    else
        TriggerClientEvent('QBCore:Notify', src, 'Database not enabled for photos', 'error')
    end
end)