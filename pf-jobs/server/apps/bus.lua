-- Bus job (server): depot buses, city routes, NPC passengers and pay.
--
-- A route is a list of stops (Config.Bus.Routes, stops from Config.Bus.Stops). The driver checks
-- each stop in, in order, at the stop; the server then lets NPC passengers off whose stop it is and
-- lets new ones on, but only into a bus the driver is driving (passengers board buses, not cars).
-- The route pays once at the end, through the bank ledger: passengers delivered, the route's
-- distance and the server's clock (rush hour, on time), the bus's condition and a rating the server
-- works out itself. Nothing the client reports changes the pay.

-- No other pf-jobs server file sets a global QBCore, so every bus event used to fail on it
local QBCore = QBCore or exports['pfm-core']:GetCoreObject()
-- Callbacks go through PFJobsCallback (server/devices_capture.lua) so the tablet and computer apps
-- (server/devices.lua) reuse them; loaded on its own, this file registers them directly.
local CreateCallback = PFJobsCallback or QBCore.Functions.CreateCallback

PFJobsBus = PFJobsBus or {}

local BusJobs = {}     -- [src] = the route in progress
local PlayerStats = {} -- [citizenid] = stats (loaded from bus_stats once)
local rentedBuses = {} -- [src] = { vehicle, netId, plate, model, label, capacity }

local function cfg() return Config.Bus or {} end
local function pricing() return cfg().Pricing or {} end

local function notify(src, msg, kind) TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary') end

local function clampNumber(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(lo, math.min(hi, v))
end

local function v3(c) return vector3(c.x, c.y, c.z or 0.0) end

local function stopRange() return tonumber(cfg().StopRange) or 25.0 end
local function maxSpeed() return tonumber(cfg().MaxBusSpeed) or 30.0 end
local MIN_ROUTE_SECONDS = 60

-- ── routes ──────────────────────────────────────────────────────────

-- Routes come from config as written there (stops by key or inline); they are expanded once and
-- rebuilt only when the config tables are replaced.
local routeCache = { source = nil, stops = nil, list = {}, byId = {} }

local function normalizeStop(entry, index)
    if type(entry) == 'string' then entry = (cfg().Stops or {})[entry] end
    if type(entry) ~= 'table' or type(entry.coords) ~= 'table' then return nil end
    local waiting = entry.waiting
    if type(waiting) ~= 'table' then
        -- older format: isPickup stops with a fixed passenger count
        local n = entry.isPickup and math.max(0, math.floor(tonumber(entry.passengerCount) or 0)) or 0
        waiting = { n, n }
    end
    local lo = math.max(0, math.floor(tonumber(waiting[1]) or 0))
    local hi = math.max(lo, math.floor(tonumber(waiting[2]) or lo))
    return { index = index, name = entry.name or ('Stop ' .. index), coords = v3(entry.coords), waiting = { lo, hi } }
end

local function minLevelFor(route)
    local map = cfg().DifficultyLevels or { easy = 1, medium = 2, hard = 3 }
    return tonumber(route.minLevel) or tonumber(map[route.difficulty or 'easy']) or 1
end

local function routes()
    local source = cfg().Routes or {}
    if routeCache.source == source and routeCache.stops == cfg().Stops then return routeCache.list, routeCache.byId end
    local list, byId = {}, {}
    for _, r in ipairs(source) do
        local id = tonumber(r.id)
        local stops = {}
        for i, s in ipairs(r.stops or {}) do
            local stop = normalizeStop(s, i)
            if stop then stops[#stops + 1] = stop end
        end
        if id and #stops > 0 and #stops == #(r.stops or {}) then
            local route = {
                id = id, name = r.name or ('Route ' .. id), description = r.description,
                difficulty = r.difficulty or 'easy', baseDistance = tonumber(r.baseDistance) or 0,
                estimatedTime = tonumber(r.estimatedTime), stops = stops,
            }
            route.minLevel = minLevelFor(route)
            list[#list + 1] = route
            byId[id] = route
        else
            print(('^3[pf-jobs]^7 bus route %s skipped: unknown stop in its list'):format(tostring(r.id)))
        end
    end
    routeCache = { source = source, stops = cfg().Stops, list = list, byId = byId }
    return list, byId
end

local function getRouteById(routeId)
    local _, byId = routes()
    return byId[tonumber(routeId)]
end

local function expectedPassengers(route)
    local n = 0
    for i = 1, #route.stops - 1 do
        local w = route.stops[i].waiting
        n = n + (w[1] + w[2]) / 2
    end
    return math.floor(n + 0.5)
end

-- the pay before the time-of-day, level, on-time, condition and rating multipliers
local function basePay(passengers, route)
    local p = pricing()
    return math.floor(passengers * (tonumber(p.BasePayPerPassenger) or 0) + route.baseDistance * (tonumber(p.PayPerMile) or 0))
end

-- ── levels and stats ────────────────────────────────────────────────

local function getPlayerLevel(routesCompleted)
    routesCompleted = tonumber(routesCompleted) or 0
    local best = 1
    for _, info in ipairs(cfg().Levels or {}) do
        local minR = tonumber(info.minRoutes) or 0
        local maxR = tonumber(info.maxRoutes) or math.huge
        if routesCompleted >= minR and routesCompleted <= maxR then return tonumber(info.level) or 1 end
        if routesCompleted >= minR then best = math.max(best, tonumber(info.level) or 1) end
    end
    return best
end

local function defaultStats(cid)
    return { citizen_id = cid, totalPassengers = 0, totalEarnings = 0, routesCompleted = 0, totalTime = 0,
        averageRating = 5.0, bestRating = 0, onTimeCount = 0, level = 1 }
end

local function getPlayerStats(cid)
    if PlayerStats[cid] then return PlayerStats[cid] end
    local stats = defaultStats(cid)
    if cfg().UseDatabase then
        local ok, row = pcall(MySQL.single.await, [[SELECT total_passengers, total_earnings, routes_completed, total_time,
            average_rating, best_rating, on_time_count, current_level FROM bus_stats WHERE citizen_id = ?]], { cid })
        if not ok then return stats end -- not cached: read again next time
        if type(row) == 'table' and row.routes_completed ~= nil then
            stats.totalPassengers = tonumber(row.total_passengers) or 0
            stats.totalEarnings = tonumber(row.total_earnings) or 0
            stats.routesCompleted = tonumber(row.routes_completed) or 0
            stats.totalTime = tonumber(row.total_time) or 0
            stats.averageRating = tonumber(row.average_rating) or 5.0
            stats.bestRating = tonumber(row.best_rating) or 0
            stats.onTimeCount = tonumber(row.on_time_count) or 0
        end
    end
    stats.level = getPlayerLevel(stats.routesCompleted)
    PlayerStats[cid] = stats
    return stats
end

local function savePlayerStats(cid, stats)
    PlayerStats[cid] = stats
    if not cfg().UseDatabase then return end
    pcall(MySQL.query.await, [[INSERT INTO bus_stats (citizen_id, total_passengers, total_earnings, routes_completed, total_time,
            average_rating, best_rating, on_time_count, current_level) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE total_passengers = VALUES(total_passengers), total_earnings = VALUES(total_earnings),
            routes_completed = VALUES(routes_completed), total_time = VALUES(total_time), average_rating = VALUES(average_rating),
            best_rating = VALUES(best_rating), on_time_count = VALUES(on_time_count), current_level = VALUES(current_level)]],
        { cid, stats.totalPassengers, stats.totalEarnings, stats.routesCompleted, stats.totalTime,
          stats.averageRating, stats.bestRating, stats.onTimeCount, stats.level })
end

local function canDrive(route, level) return level >= (route.minLevel or 1) end

local function getAvailableRoutes(level)
    local out = {}
    for _, route in ipairs((routes())) do
        if canDrive(route, level) then out[#out + 1] = route end
    end
    return out
end

-- Plain tables only (no vectors): this is what the apps and the route menu show.
local function publicRoute(route, level)
    local stops = {}
    for i, s in ipairs(route.stops) do stops[i] = { name = s.name, x = s.coords.x, y = s.coords.y, z = s.coords.z, waiting = { s.waiting[1], s.waiting[2] } } end
    local passengers = expectedPassengers(route)
    return {
        id = route.id, name = route.name, description = route.description, difficulty = route.difficulty,
        minLevel = route.minLevel, unlocked = level == nil or canDrive(route, level),
        baseDistance = route.baseDistance, estimatedTime = route.estimatedTime, stopCount = #route.stops,
        stops = stops, expectedPassengers = passengers, estimatedPay = basePay(passengers, route),
    }
end

-- ── who may drive ───────────────────────────────────────────────────

local function playerOf(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    local job = cfg().Job
    if type(job) == 'string' and job ~= '' and (Player.PlayerData.job or {}).name ~= job then
        notify(src, 'You need to work for the bus company', 'error')
        return nil
    end
    return Player
end

local function vehicleDef(model)
    for _, v in ipairs(cfg().Vehicles or {}) do
        if v.model == model then return v end
    end
    for _, m in ipairs(cfg().AllowedVehicles or {}) do
        if m == model then return { model = m, label = m, capacity = 15, minLevel = 1 } end
    end
    return nil
end

local function isBusModel(hash)
    hash = (tonumber(hash) or 0) & 0xFFFFFFFF
    for _, m in ipairs(cfg().AllowedVehicles or {}) do
        if hash == (GetHashKey(m) & 0xFFFFFFFF) then return vehicleDef(m) or { capacity = 15 } end
    end
    return nil
end

-- The bus the driver is driving right now, if any: an allowed model, in the driver seat, and their
-- depot bus when they have one.
local function drivenBus(src)
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if GetPedInVehicleSeat and GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    local rental = rentedBuses[src]
    if rental and rental.vehicle ~= veh then return nil end
    local def = isBusModel(GetEntityModel(veh))
    if not def then return nil end
    return veh, (rental and rental.capacity) or def.capacity or 15
end

local function busHealth(veh)
    local ok, engine, body = pcall(function() return GetVehicleEngineHealth(veh), GetVehicleBodyHealth(veh) end)
    if not ok then return 100 end
    local worst = math.min(tonumber(engine) or 1000, tonumber(body) or 1000)
    return clampNumber(worst / 10, 0, 100, 100)
end

-- ── fare ────────────────────────────────────────────────────────────

local function timeOfDayMultiplier()
    local p = pricing()
    local hour = tonumber(os.date('%H')) or 12
    if (hour >= 7 and hour < 10) or (hour >= 17 and hour < 20) then return tonumber(p.RushHourMultiplier) or 1.0 end
    if hour >= 22 or hour < 4 then return tonumber(p.NightBonus) or 1.0 end
    return 1.0
end

local function ratingModifier(rating)
    local mods = pricing().PassengerRatingModifier or {}
    local thresholds = {}
    for t in pairs(mods) do if tonumber(t) then thresholds[#thresholds + 1] = tonumber(t) end end
    table.sort(thresholds, function(a, b) return a > b end)
    for _, t in ipairs(thresholds) do
        if rating >= t then return tonumber(mods[t]) or 0 end
    end
    return 0
end

-- The server's own rating: late, a battered bus and passengers left behind cost stars.
local function routeRating(job, elapsed)
    local rating = 5.0
    local est = (tonumber(job.route.estimatedTime) or 0) / 1000
    if est > 0 and elapsed > est then rating = rating - math.min(2.0, (elapsed - est) / est * 2.0) end
    rating = rating - math.min(2.0, (100 - job.minHealth) / 25)
    rating = rating - math.min(1.5, job.missed * 0.25)
    return math.floor(clampNumber(rating, 1.0, 5.0, 5.0) * 10 + 0.5) / 10
end

local function calculateFare(job, level, onTime, rating)
    local p = pricing()
    local multiplier = timeOfDayMultiplier()
    local levelMult = (p.LevelMultiplier or {})[level]
    multiplier = multiplier * (tonumber(levelMult) or 1.0)
    if onTime then multiplier = multiplier * (1 + (tonumber(p.OnTimeBonus) or 0)) end
    local health = job.minHealth / 100
    if health < 1.0 then multiplier = multiplier * (1.0 - (1.0 - health) * (tonumber(p.VehicleHealthPenalty) or 0)) end
    multiplier = multiplier * (1.0 + ratingModifier(rating))
    local fare = math.floor(basePay(job.passengersDelivered, job.route) * multiplier)
    local cap = tonumber(p.MaxRoutePay)
    if cap and fare > cap then fare = cap end
    return math.max(0, fare)
end

-- ── routes in progress ─────────────────────────────────────────────

local function stopNameOf(job, i) local s = job.route.stops[i]; return s and s.name or nil end

RegisterNetEvent('bus:server:startRoute', function(routeId)
    local src = source
    if not cfg().Enabled then return end
    local Player = playerOf(src)
    if not Player then return end
    if BusJobs[src] then
        notify(src, 'Finish or cancel your current route first', 'error')
        return
    end
    local route = getRouteById(routeId)
    if not route then
        notify(src, 'Route not found', 'error')
        return
    end
    local cid = Player.PlayerData.citizenid
    local stats = getPlayerStats(cid)
    local level = getPlayerLevel(stats.routesCompleted)
    if not canDrive(route, level) then
        notify(src, ('This route needs driver level %d'):format(route.minLevel), 'error')
        return
    end

    BusJobs[src] = {
        routeId = route.id,
        route = route,
        playerId = src,
        citizenId = cid,
        startTime = GetGameTimer(),
        startedAt = os.time(),
        currentStop = 1,
        riders = {},             -- [stop index] = passengers riding to that stop
        onBoard = 0,
        passengersPickedUp = 0,
        passengersDelivered = 0,
        missed = 0,              -- passengers left behind (stop checked in without the bus)
        stopsCompleted = 0,
        minHealth = 100,
        -- Server-side id for this run; the payout key is built from it
        payoutId = PFPayout.NewId(),
    }

    TriggerClientEvent('bus:client:loadRoute', src, route, level)
    notify(src, ('Route started: %s. First stop: %s'):format(route.name, route.stops[1].name), 'success')
end)

-- A stop counts once, in order, with the driver at it, and a real drive after the previous stop.
-- In a bus, riders for this stop get off and waiting passengers get on.
RegisterNetEvent('bus:server:completeStop', function(stopNumber)
    local src = source
    local job = BusJobs[src]
    if not job then
        notify(src, 'No active route', 'error')
        return
    end
    stopNumber = tonumber(stopNumber)
    if stopNumber ~= job.currentStop then return end
    local stop = job.route.stops[stopNumber]
    if not stop then return end
    local now = os.time()
    local pos = GetEntityCoords(GetPlayerPed(src))
    if #(pos - stop.coords) > stopRange() then
        notify(src, 'You are too far from the stop', 'error')
        return
    end
    if job.lastStopPos and now - job.lastStopAt < #(stop.coords - job.lastStopPos) / maxSpeed() then
        notify(src, 'That was too quick. Drive the route.', 'error')
        return
    end

    local last = stopNumber == #job.route.stops
    local bus, capacity = drivenBus(src)
    local alighted, boarded = 0, 0
    local due = job.riders[stopNumber] or 0
    if last then
        -- everyone still aboard gets off at the terminus
        due = job.onBoard
    end
    if bus then
        job.minHealth = math.min(job.minHealth, busHealth(bus))
        alighted = due
        job.passengersDelivered = job.passengersDelivered + alighted
        job.onBoard = job.onBoard - alighted
        job.riders[stopNumber] = nil
        if not last then
            local w = stop.waiting
            local waiting = math.random(w[1], w[2])
            boarded = math.max(0, math.min(waiting, capacity - job.onBoard))
            for _ = 1, boarded do
                local dest = math.random(stopNumber + 1, #job.route.stops)
                job.riders[dest] = (job.riders[dest] or 0) + 1
            end
            job.onBoard = job.onBoard + boarded
            job.passengersPickedUp = job.passengersPickedUp + boarded
        end
    else
        -- checked in without the bus: nobody gets off or on, and riders for this stop are lost
        job.missed = job.missed + due
        job.onBoard = job.onBoard - due
        job.riders[stopNumber] = nil
        if last then job.onBoard = 0 end
    end

    job.currentStop = stopNumber + 1
    job.stopsCompleted = job.stopsCompleted + 1
    job.lastStopAt, job.lastStopPos = now, stop.coords

    if not bus then
        notify(src, 'No passengers: they only ride in your bus', 'error')
    elseif alighted > 0 or boarded > 0 then
        notify(src, ('%s: %d off, %d on'):format(stop.name, alighted, boarded), 'success')
    else
        notify(src, ('%s: nobody waiting'):format(stop.name), 'primary')
    end
    -- the client shows passengers boarding and the apps follow the route from this
    TriggerClientEvent('bus:client:stopCompleted', src, stopNumber, #job.route.stops, {
        alighted = alighted, boarded = boarded, onBoard = job.onBoard, inBus = bus ~= nil,
        nextStop = stopNameOf(job, stopNumber + 1),
    })
end)

RegisterNetEvent('bus:server:completeRoute', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local job = BusJobs[src]
    if not job then
        notify(src, 'No active route', 'error')
        return
    end
    local cid = Player.PlayerData.citizenid
    if job.citizenId ~= cid then BusJobs[src] = nil return end

    -- every stop must have been visited, after time to drive the route
    if job.currentStop <= #job.route.stops then
        notify(src, 'You have not visited every stop', 'error')
        return
    end
    local elapsed = os.time() - job.startedAt
    local routeMetres = job.route.baseDistance * 1609.34
    if elapsed < math.max(MIN_ROUTE_SECONDS, routeMetres / maxSpeed()) then
        notify(src, 'The route is not done yet. Keep to the timetable.', 'error')
        return
    end

    local stats = getPlayerStats(cid)
    local level = getPlayerLevel(stats.routesCompleted)
    local onTime = job.route.estimatedTime ~= nil and elapsed <= (tonumber(job.route.estimatedTime) or 0) / 1000
    local rating = routeRating(job, elapsed)
    local finalFare = calculateFare(job, level, onTime, rating)

    -- Pay through the ledger; on failure keep the route so a retry reuses the same key
    if finalFare > 0 then
        local paid = PFPayout.Pay(Player, 'cash', finalFare, {
            key = ('pf-jobs:bus:%s:%s'):format(job.payoutId, cid),
            reason = 'bus-route-complete',
        })
        if not paid then return end
    end
    BusJobs[src] = nil
    notify(src, ('Route complete: %d passengers, rating %.1f. Earned $%s'):format(job.passengersDelivered, rating, finalFare), 'success')

    if cfg().UseDatabase then
        pcall(MySQL.insert.await, [[INSERT INTO bus_routes_log (citizen_id, route_id, distance, fare_earned, passengers_delivered,
            complete_time, rating, on_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
            { cid, job.routeId, job.route.baseDistance, finalFare, job.passengersDelivered, elapsed, rating, onTime and 1 or 0 })
    end

    stats.totalPassengers = stats.totalPassengers + job.passengersDelivered
    stats.totalEarnings = stats.totalEarnings + finalFare
    stats.routesCompleted = stats.routesCompleted + 1
    stats.totalTime = stats.totalTime + math.floor(elapsed / 60)
    stats.averageRating = math.floor((((stats.averageRating * (stats.routesCompleted - 1)) + rating) / stats.routesCompleted) * 100 + 0.5) / 100
    stats.bestRating = math.max(tonumber(stats.bestRating) or 0, rating)
    if onTime then stats.onTimeCount = stats.onTimeCount + 1 end
    local before = level
    stats.level = getPlayerLevel(stats.routesCompleted)
    savePlayerStats(cid, stats)
    if stats.level > before then notify(src, ('Promoted to bus driver level %d'):format(stats.level), 'success') end

    TriggerClientEvent('bus:client:updateStats', src, stats)
end)

RegisterNetEvent('bus:server:cancelRoute', function()
    local src = source
    if BusJobs[src] then
        BusJobs[src] = nil
        notify(src, 'Route cancelled', 'primary')
        -- clears the route on the client too when it was cancelled from an app
        TriggerClientEvent('bus:client:routeCancelled', src)
    end
end)

RegisterNetEvent('bus:server:getStats', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local stats = {}
    for k, v in pairs(getPlayerStats(Player.PlayerData.citizenid)) do stats[k] = v end
    TriggerClientEvent('bus:client:statsData', src, stats)
end)

RegisterNetEvent('bus:server:getRoutes', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local level = getPlayerLevel(getPlayerStats(Player.PlayerData.citizenid).routesCompleted)
    local out = {}
    for _, r in ipairs(getAvailableRoutes(level)) do out[#out + 1] = publicRoute(r, level) end
    TriggerClientEvent('bus:client:routesData', src, out)
end)

-- ── depot buses ─────────────────────────────────────────────────────

local function nearDepot(src)
    local depot = cfg().Depot
    if not depot or not depot.coords then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - v3(depot.coords)) <= (tonumber(depot.radius) or 30.0)
end

-- A spawn bay with no vehicle on it (GetAllVehicles is a server native).
local function freeSpawn()
    local spawns = cfg().VehicleSpawns or {}
    for _, s in ipairs(spawns) do
        local blocked = false
        if GetAllVehicles then
            for _, veh in ipairs(GetAllVehicles()) do
                if DoesEntityExist(veh) and #(GetEntityCoords(veh) - v3(s)) < 4.0 then blocked = true break end
            end
        end
        if not blocked then return s end
    end
    return nil
end

RegisterNetEvent('bus:server:spawnBus', function(vehicleModel)
    local src = source
    if not cfg().Enabled then return end
    local Player = playerOf(src)
    if not Player then return end
    if rentedBuses[src] then
        notify(src, 'You already have a bus out', 'error')
        return
    end
    if not nearDepot(src) then
        notify(src, 'Buses are handed out at the bus depot', 'error')
        return
    end
    local def = vehicleDef(type(vehicleModel) == 'string' and vehicleModel or 'bus') or vehicleDef('bus')
    if not def then return end
    local level = getPlayerLevel(getPlayerStats(Player.PlayerData.citizenid).routesCompleted)
    if level < (tonumber(def.minLevel) or 1) then
        notify(src, ('The %s needs driver level %d'):format(def.label or def.model, def.minLevel), 'error')
        return
    end
    local spawn = freeSpawn()
    if not spawn then
        notify(src, 'The bus bay is blocked. Clear it first.', 'error')
        return
    end

    local plate = (cfg().PlatePrefix or 'BUS') .. math.random(1000, 9999)
    local vehicle = CreateVehicleServerSetter(GetHashKey(def.model), 'automobile', spawn.x, spawn.y, spawn.z, spawn.w or 0.0)
    local timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    if not DoesEntityExist(vehicle) then
        notify(src, 'The bus could not be brought out', 'error')
        return
    end
    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleDoorsLocked(vehicle, 1)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', src, plate)
    rentedBuses[src] = { vehicle = vehicle, netId = netId, plate = plate, model = def.model, label = def.label or def.model,
        capacity = tonumber(def.capacity) or 15 }
    TriggerClientEvent('bus:client:vehicleSpawned', src, netId, plate, { x = spawn.x, y = spawn.y, z = spawn.z, w = spawn.w })
    notify(src, ('%s ready, plate %s'):format(def.label or def.model, plate), 'success')
end)

RegisterNetEvent('bus:server:returnBus', function()
    local src = source
    local rental = rentedBuses[src]
    if not rental then
        notify(src, 'You have no bus out', 'error')
        return
    end
    local exists = DoesEntityExist(rental.vehicle)
    local depot = cfg().Depot
    if exists and depot and depot.coords and #(GetEntityCoords(rental.vehicle) - v3(depot.coords)) > (tonumber(depot.radius) or 30.0) then
        notify(src, 'Bring the bus back to the depot', 'error')
        return
    end
    if not nearDepot(src) then
        notify(src, 'Return the bus at the depot', 'error')
        return
    end
    if exists then DeleteEntity(rental.vehicle) end
    rentedBuses[src] = nil
    TriggerClientEvent('bus:client:busReturned', src)
    notify(src, 'Bus returned', 'success')
end)

AddEventHandler('playerDropped', function()
    local src = source
    local rental = rentedBuses[src]
    if rental and DoesEntityExist(rental.vehicle) then DeleteEntity(rental.vehicle) end
    rentedBuses[src] = nil
    BusJobs[src] = nil
end)

-- ── the apps' view ──────────────────────────────────────────────────

--- Everything the tablet and computer apps show, in one answer: stats, the routes (with the ones
--- this level may drive marked), the depot bus and the route in progress.
function PFJobsBus.View(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    local cid = Player.PlayerData.citizenid
    local stats = {}
    for k, v in pairs(getPlayerStats(cid)) do stats[k] = v end
    stats.level = getPlayerLevel(stats.routesCompleted or 0)
    local list = {}
    for _, r in ipairs((routes())) do
        if canDrive(r, stats.level) then list[#list + 1] = publicRoute(r, stats.level) end
    end
    local locked = {}
    for _, r in ipairs((routes())) do
        if not canDrive(r, stats.level) then locked[#locked + 1] = { id = r.id, name = r.name, difficulty = r.difficulty, minLevel = r.minLevel } end
    end
    local vehicles = {}
    for _, v in ipairs(cfg().Vehicles or {}) do
        vehicles[#vehicles + 1] = { model = v.model, label = v.label, capacity = v.capacity, minLevel = v.minLevel or 1,
            unlocked = stats.level >= (v.minLevel or 1) }
    end
    local job = BusJobs[src]
    local rental = rentedBuses[src]
    local nextStop = job and job.route.stops[job.currentStop]
    local depot = cfg().Depot
    return {
        enabled = cfg().Enabled == true,
        stats = stats,
        routes = list,
        lockedRoutes = locked,
        vehicles = vehicles,
        depot = depot and depot.coords and { label = depot.label, x = depot.coords.x, y = depot.coords.y } or nil,
        atDepot = nearDepot(src),
        bus = rental and { plate = rental.plate, model = rental.model, label = rental.label, capacity = rental.capacity,
            present = DoesEntityExist(rental.vehicle) } or nil,
        activeRoute = job and {
            routeId = job.routeId,
            name = job.route.name,
            currentStop = job.currentStop,
            totalStops = #job.route.stops,
            nextStop = nextStop and nextStop.name or nil,
            nextStopAt = nextStop and { x = nextStop.coords.x, y = nextStop.coords.y } or nil,
            onBoard = job.onBoard,
            missed = job.missed,
            passengersPickedUp = job.passengersPickedUp,
            passengersDelivered = job.passengersDelivered,
            startedAt = job.startedAt,
            estimatedTime = job.route.estimatedTime,
            estimatedPay = basePay(job.passengersDelivered + job.onBoard, job.route),
        } or nil,
    }
end

CreateCallback('pf-jobs:bus:getAppView', function(source, cb)
    cb(PFJobsBus.View(source))
end)

--- A deleted character: drop its cached stats and any route of a player still using it.
function PFJobsBus.ForgetCitizen(cid)
    PlayerStats[cid] = nil
    for src, job in pairs(BusJobs) do
        if job.citizenId == cid then BusJobs[src] = nil end
    end
end

PFJobsBus.Routes = routes
PFJobsBus.GetLevel = getPlayerLevel
