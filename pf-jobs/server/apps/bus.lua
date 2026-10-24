-- Bus Job Application - Server Side
-- Handles route management, passenger tracking, earnings, and progression

local BusJobs = {} -- Active bus routes for players
local PlayerStats = {} -- Cached player statistics

-- Initialize bus system
function InitBusApp()
    if not Config.Bus or not Config.Bus.Enabled then 
        print("^3[BUS JOB]^7 Bus system disabled in config")
        return 
    end
    
    print("^2[BUS JOB]^7 Initializing Bus Application...")
    
    -- Load player stats on startup (optional - can also load on-demand)
    if Config.Bus and Config.Bus.UseDatabase then
        TriggerEvent('bus:server:createTables')
    end
end

-- ============================================================================
-- ROUTE MANAGEMENT
-- ============================================================================

-- Get available routes for player (based on level)
local function getAvailableRoutes(citizen_id, level)
    local availableRoutes = {}
    
    for _, route in ipairs(Config.Bus.Routes) do
        -- Check difficulty level unlock
        local routeDifficulty = route.difficulty
        local canAccess = true
        
        -- Easy routes: always accessible
        -- Medium routes: level 2+
        -- Hard routes: level 3+
        if routeDifficulty == "medium" and level < 2 then
            canAccess = false
        elseif routeDifficulty == "hard" and level < 3 then
            canAccess = false
        end
        
        if canAccess then
            table.insert(availableRoutes, route)
        end
    end
    
    return availableRoutes
end

-- Get route by ID
local function getRouteById(routeId)
    for _, route in ipairs(Config.Bus.Routes) do
        if route.id == routeId then
            return route
        end
    end
    return nil
end

-- Calculate base earnings for route
local function calculateBaseEarnings(route)
    local baseFare = 0
    local totalPassengers = 0
    
    for _, stop in ipairs(route.stops) do
        if stop.isPickup then
            totalPassengers = totalPassengers + stop.passengerCount
        end
    end
    
    baseFare = (totalPassengers * Config.Bus.Pricing.BasePayPerPassenger) + 
               (route.baseDistance * Config.Bus.Pricing.PayPerMile)
    
    return baseFare, totalPassengers
end

-- ============================================================================
-- FARE CALCULATION
-- ============================================================================

-- Calculate final fare for completed route
local function calculateFare(routeId, completionData)
    local route = getRouteById(routeId)
    if not route then return 0 end
    
    local baseEarnings, totalPassengers = calculateBaseEarnings(route)
    local multiplier = 1.0
    
    -- Time of day multiplier
    local hour = tonumber(os.date('%H'))
    if (hour >= 7 and hour < 10) or (hour >= 17 and hour < 20) then
        multiplier = multiplier * Config.Bus.Pricing.RushHourMultiplier
    elseif hour >= 22 or hour < 4 then
        multiplier = multiplier * Config.Bus.Pricing.NightBonus
    end
    
    -- Level multiplier
    if completionData.playerLevel then
        local levelMult = Config.Bus.Pricing.LevelMultiplier[completionData.playerLevel] or 1.0
        multiplier = multiplier * levelMult
    end
    
    -- On-time bonus
    if completionData.isOnTime then
        multiplier = multiplier * (1 + Config.Bus.Pricing.OnTimeBonus)
    end
    
    -- Vehicle health penalty
    if completionData.vehicleHealth then
        local healthPercent = completionData.vehicleHealth / 100
        if healthPercent < 1.0 then
            local penaltyPercent = (1.0 - healthPercent) * Config.Bus.Pricing.VehicleHealthPenalty
            multiplier = multiplier * (1.0 - penaltyPercent)
        end
    end
    
    -- Passenger rating modifier
    if completionData.averageRating then
        local ratingMult = 0.0
        for ratingThreshold, modifier in pairs(Config.Bus.Pricing.PassengerRatingModifier) do
            if completionData.averageRating >= ratingThreshold then
                ratingMult = modifier
                break
            end
        end
        if ratingMult ~= 0 then
            multiplier = multiplier * (1.0 + ratingMult)
        end
    end
    
    local finalFare = math.floor(baseEarnings * multiplier)
    return finalFare, totalPassengers
end

-- ============================================================================
-- PLAYER LEVEL SYSTEM
-- ============================================================================

-- Get player level based on routes completed
local function getPlayerLevel(routesCompleted)
    for _, levelInfo in ipairs(Config.Bus.Levels) do
        if routesCompleted >= levelInfo.minRoutes and routesCompleted <= levelInfo.maxRoutes then
            return levelInfo.level
        end
    end
    return 1
end

-- Get level info
local function getLevelInfo(routesCompleted)
    return getPlayerLevel(routesCompleted)
end

-- ============================================================================
-- PLAYER STATS
-- ============================================================================

-- Get player stats
local function getPlayerStats(citizen_id)
    if PlayerStats[citizen_id] then
        return PlayerStats[citizen_id]
    end
    
    -- Default stats if not cached
    return {
        citizen_id = citizen_id,
        totalPassengers = 0,
        totalEarnings = 0,
        routesCompleted = 0,
        totalTime = 0,
        averageRating = 5.0,
        bestRating = 5.0,
        onTimeCount = 0,
        level = 1,
    }
end

-- Save player stats (database + cache)
local function savePlayerStats(citizen_id, stats)
    PlayerStats[citizen_id] = stats
    
    -- Save to database if enabled
    if Config.Bus.UseDatabase then
        MySQL.Async.execute('INSERT INTO bus_stats (citizen_id, total_passengers, total_earnings, routes_completed, total_time, average_rating, best_rating, on_time_count, current_level, last_updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE total_passengers=?, total_earnings=?, routes_completed=?, total_time=?, average_rating=?, best_rating=?, on_time_count=?, current_level=?, last_updated=NOW()',
            {citizen_id, stats.totalPassengers, stats.totalEarnings, stats.routesCompleted, stats.totalTime, stats.averageRating, stats.bestRating, stats.onTimeCount, stats.level,
             stats.totalPassengers, stats.totalEarnings, stats.routesCompleted, stats.totalTime, stats.averageRating, stats.bestRating, stats.onTimeCount, stats.level},
            function(rowsChanged)
                if Config.Bus.Debug then
                    print(string.format("^2[BUS]^7 Saved stats for citizen %s", citizen_id))
                end
            end)
    end
end

-- ============================================================================
-- ROUTE EVENTS
-- ============================================================================

-- Start bus route
RegisterNetEvent('bus:server:startRoute', function(routeId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizen_id = Player.PlayerData.citizenid
    local route = getRouteById(routeId)
    
    if not route then
        TriggerClientEvent('QBCore:Notify', src, 'Route not found', 'error')
        return
    end
    
    -- Create job entry
    BusJobs[src] = {
        routeId = routeId,
        route = route,
        playerId = src,
        citizenId = citizen_id,
        startTime = GetGameTimer(),
        currentStop = 1,
        passengersPickedUp = 0,
        passengersDelivered = 0,
        stopsCompleted = 0,
    }
    
    -- Get player stats
    local stats = getPlayerStats(citizen_id)
    local level = getLevelInfo(stats.routesCompleted)
    
    -- Send route info to client
    TriggerClientEvent('bus:client:loadRoute', src, route, level)
    TriggerClientEvent('QBCore:Notify', src, 'Route started! Head to the first stop.', 'success')
    
    if Config.Bus.Debug then
        print(string.format("^2[BUS]^7 Player %s started route %s", citizen_id, routeId))
    end
end)

-- Complete a stop
RegisterNetEvent('bus:server:completeStop', function(stopNumber)
    local src = source
    local job = BusJobs[src]
    
    if not job then
        TriggerClientEvent('QBCore:Notify', src, 'No active route', 'error')
        return
    end
    
    job.stopsCompleted = job.stopsCompleted + 1
    
    -- Get stop info
    local stop = job.route.stops[stopNumber]
    if not stop then return end
    
    if stop.isPickup then
        job.passengersPickedUp = job.passengersPickedUp + stop.passengerCount
        TriggerClientEvent('QBCore:Notify', src, string.format('Picked up %d passengers', stop.passengerCount), 'success')
    else
        job.passengersDelivered = job.passengersDelivered + stop.passengerCount
        TriggerClientEvent('QBCore:Notify', src, 'Passengers delivered', 'success')
    end
    
    if Config.Bus.Debug then
        print(string.format("^2[BUS]^7 Stop %d completed", stopNumber))
    end
end)

-- Complete route
RegisterNetEvent('bus:server:completeRoute', function(completionData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local job = BusJobs[src]
    if not job then
        TriggerClientEvent('QBCore:Notify', src, 'No active route', 'error')
        return
    end
    
    local citizen_id = Player.PlayerData.citizenid
    local stats = getPlayerStats(citizen_id)
    
    -- Calculate earnings
    local finalFare, totalPassengers = calculateFare(job.routeId, completionData)
    
    -- Add money
    Player.Functions.AddMoney('cash', finalFare)
    TriggerClientEvent('QBCore:Notify', src, string.format('Route completed! Earned ${:,}', finalFare), 'success')
    
    -- Log ride
    if Config.Bus.UseDatabase then
        MySQL.Async.execute('INSERT INTO bus_routes_log (citizen_id, route_id, distance, fare_earned, passengers_delivered, complete_time, rating, on_time, completed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())',
            {citizen_id, job.routeId, job.route.baseDistance, finalFare, job.passengersDelivered, GetGameTimer() - job.startTime, completionData.averageRating or 5.0, completionData.isOnTime and 1 or 0})
    end
    
    -- Update player stats
    stats.totalPassengers = stats.totalPassengers + totalPassengers
    stats.totalEarnings = stats.totalEarnings + finalFare
    stats.routesCompleted = stats.routesCompleted + 1
    stats.totalTime = stats.totalTime + math.floor((GetGameTimer() - job.startTime) / 1000 / 60) -- Convert to minutes
    
    -- Update rating
    if completionData.averageRating then
        local previousRating = stats.averageRating
        stats.averageRating = ((previousRating * (stats.routesCompleted - 1)) + completionData.averageRating) / stats.routesCompleted
    end
    
    if completionData.isOnTime then
        stats.onTimeCount = stats.onTimeCount + 1
    end
    
    -- Update level
    stats.level = getLevelInfo(stats.routesCompleted)
    
    -- Save stats
    savePlayerStats(citizen_id, stats)
    
    -- Send updated stats to client
    TriggerClientEvent('bus:client:updateStats', src, stats)
    
    -- Clean up
    BusJobs[src] = nil
    
    if Config.Bus.Debug then
        print(string.format("^2[BUS]^7 Route %d completed by %s. Earned $%d", job.routeId, citizen_id, finalFare))
    end
end)

-- Cancel route
RegisterNetEvent('bus:server:cancelRoute', function()
    local src = source
    local job = BusJobs[src]
    
    if job then
        BusJobs[src] = nil
        TriggerClientEvent('QBCore:Notify', src, 'Route cancelled', 'info')
        
        if Config.Bus.Debug then
            print(string.format("^2[BUS]^7 Route cancelled by player %d", src))
        end
    end
end)

-- Get player stats (for UI)
RegisterNetEvent('bus:server:getStats', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local stats = getPlayerStats(Player.PlayerData.citizenid)
    stats.level = getLevelInfo(stats.routesCompleted)
    stats.availableRoutes = getAvailableRoutes(Player.PlayerData.citizenid, stats.level)
    
    TriggerClientEvent('bus:client:statsData', src, stats)
end)

-- Get available routes
RegisterNetEvent('bus:server:getRoutes', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local stats = getPlayerStats(Player.PlayerData.citizenid)
    local level = getLevelInfo(stats.routesCompleted)
    local availableRoutes = getAvailableRoutes(Player.PlayerData.citizenid, level)
    
    TriggerClientEvent('bus:client:routesData', src, availableRoutes)
end)

-- ============================================================================
-- VEHICLE RENTAL SYSTEM
-- ============================================================================

local rentedBuses = {} -- [src] = { vehicle, plate, model }

-- Rent a bus vehicle (no deposit/rental, just vehicle assignment)
RegisterNetEvent('bus:server:spawnBus', function(vehicleModel)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Check if player already has a rented bus
    if rentedBuses[src] then
        TriggerClientEvent('QBCore:Notify', src, 'You already have an assigned bus', 'error')
        return
    end
    
    -- Validate vehicle model (must be in allowed vehicles)
    local isAllowed = false
    for _, allowedModel in ipairs(Config.Bus.AllowedVehicles) do
        if allowedModel == vehicleModel then
            isAllowed = true
            break
        end
    end
    
    if not isAllowed then
        vehicleModel = 'bus' -- Default to standard bus
    end
    
    -- Select random spawn location
    local spawnCoords = Config.Bus.VehicleSpawns[math.random(#Config.Bus.VehicleSpawns)]
    
    -- Generate plate
    local plate = Config.Bus.PlatePrefix .. math.random(1000, 9999)
    
    -- Spawn vehicle server-side (same logic as Gruppe6)
    local modelHash = GetHashKey(vehicleModel)
    local vehicle = CreateVehicleServerSetter(modelHash, 'automobile', spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w)
    
    -- Wait for vehicle to exist
    local timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if not DoesEntityExist(vehicle) then
        TriggerClientEvent('QBCore:Notify', src, 'Bus spawn failed', 'error')
        print('[BUS] ERROR: Vehicle failed to spawn for player ' .. src)
        return
    end
    
    -- Set vehicle properties
    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleDoorsLocked(vehicle, 1)
    
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    
    -- Give vehicle keys (same logic as Gruppe6 and Taxi)
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', src, plate)
    
    -- Store rental info
    rentedBuses[src] = {
        vehicle = vehicle,
        netId = netId,
        plate = plate,
        model = vehicleModel
    }
    
    -- Notify client
    TriggerClientEvent('bus:client:vehicleSpawned', src, netId, plate, spawnCoords)
    TriggerClientEvent('QBCore:Notify', src, 'Bus assigned - Plate: ' .. plate, 'success')
    
    print('[BUS] Vehicle spawned for player ' .. src .. ' | Model: ' .. vehicleModel .. ' | Plate: ' .. plate .. ' | NetID: ' .. netId)
end)

-- Return bus vehicle
RegisterNetEvent('bus:server:returnBus', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local rental = rentedBuses[src]
    if not rental then
        TriggerClientEvent('QBCore:Notify', src, 'You have no assigned bus', 'error')
        return
    end
    
    -- Delete vehicle
    if DoesEntityExist(rental.vehicle) then
        DeleteEntity(rental.vehicle)
    end
    
    -- Clear rental
    rentedBuses[src] = nil
    
    TriggerClientEvent('QBCore:Notify', src, 'Bus returned successfully', 'success')
    print('[BUS] Vehicle returned by player ' .. src)
end)

-- Cleanup rented buses when player disconnects
AddEventHandler('playerDropped', function()
    local src = source
    if rentedBuses[src] then
        if DoesEntityExist(rentedBuses[src].vehicle) then
            DeleteEntity(rentedBuses[src].vehicle)
        end
        rentedBuses[src] = nil
        print('[BUS] Cleaned up assigned bus for disconnected player ' .. src)
    end
    
    -- Also cleanup active job
    BusJobs[src] = nil
end)

-- ============================================================================
-- DATABASE INITIALIZATION
-- ============================================================================

RegisterNetEvent('bus:server:createTables', function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS bus_stats (
            id INT AUTO_INCREMENT PRIMARY KEY,
            citizen_id VARCHAR(50) UNIQUE NOT NULL,
            total_passengers INT DEFAULT 0,
            total_earnings INT DEFAULT 0,
            routes_completed INT DEFAULT 0,
            total_time INT DEFAULT 0,
            average_rating FLOAT DEFAULT 5.0,
            best_rating FLOAT DEFAULT 5.0,
            on_time_count INT DEFAULT 0,
            current_level INT DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])
    
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS bus_routes_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            citizen_id VARCHAR(50) NOT NULL,
            route_id INT NOT NULL,
            distance FLOAT DEFAULT 0,
            fare_earned INT DEFAULT 0,
            passengers_delivered INT DEFAULT 0,
            complete_time INT DEFAULT 0,
            rating FLOAT DEFAULT 5.0,
            on_time TINYINT DEFAULT 0,
            completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_citizen (citizen_id),
            INDEX idx_completed (completed_at)
        )
    ]])
    
    print("^2[BUS]^7 Database tables created/verified")
end)

-- Initialize on resource start
AddEventHandler('onServerResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        InitBusApp()
    end
end)

-- Cleanup on player leave (MOVED LOGIC TO playerDropped ABOVE)
-- AddEventHandler('playerDropped', function(reason)
--     local src = source
--     BusJobs[src] = nil
-- end)