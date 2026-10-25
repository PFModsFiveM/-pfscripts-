-- Server-side integration for pf-rentals
local QBCore = exports['pfm-core']:GetCoreObject()

-- Rental Vehicles Table
local rentalVehicles = {}
local activeRentals = {} -- Track active rentals per player

-- ============================================================================
-- CALLBACKS
-- ============================================================================

QBCore.Functions.CreateCallback('pf-rentals:getAvailableVehicles', function(source, cb)
    cb(Config.RentalVehicles)
end)

-- ============================================================================
-- EVENTS
-- ============================================================================

RegisterNetEvent('pf-rentals:confirmRental', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then
        TriggerClientEvent('pf-rentals:rentalError', src, 'Player data not found')
        return
    end
    
    -- The vehicle, the duration and the price come from the server's config (the client sent the total
    -- price, so a rental could cost nothing); the renter must be at a rental desk, one rental at a time.
    if type(data) ~= 'table' then return end
    local rental
    for _, v in ipairs(Config.RentalVehicles or {}) do
        if v.id == tonumber(data.vehicleId) then rental = v break end
    end
    local duration = math.floor(tonumber(data.duration) or 0)
    if not rental or duration < (Config.MinRentalDuration or 1) or duration > (Config.MaxRentalDuration or 30) then
        TriggerClientEvent('pf-rentals:rentalError', src, 'Invalid rental')
        return
    end
    local atDesk = false
    local pos = GetEntityCoords(GetPlayerPed(src))
    for _, loc in ipairs(Config.RentalLocations or {}) do
        if loc.coords and #(pos - loc.coords) <= 30.0 then atDesk = true break end
    end
    if not atDesk then return end
    if activeRentals[src] and not activeRentals[src].netId then
        TriggerClientEvent('pf-rentals:rentalError', src, 'Collect your current rental first')
        return
    end
    data.modelName, data.brand, data.vehicleName, data.dailyRate = rental.model, rental.brand, rental.displayName, rental.price
    data.duration = duration -- the whole days that are paid for (a client "1.9" got almost two days for one)
    local totalPrice = rental.price * duration
    local playerId = Player.PlayerData.citizenid
    local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname

    -- cash first, then bank (as allowed by Config.PaymentMethods), through the pfm-banking ledger
    local accounts = {}
    if Config.PaymentMethods.cash then accounts[#accounts + 1] = 'cash' end
    if Config.PaymentMethods.bank then accounts[#accounts + 1] = 'bank' end
    local paymentMethod = #accounts > 0 and PFPayout.Charge(Player, accounts, totalPrice, {
        key = ('pf-rentals:%s:%s'):format(playerId, PFPayout.NewId()), kind = 'purchase', reason = 'Vehicle rental: ' .. rental.model, quiet = true,
    })
    if not paymentMethod then
        TriggerClientEvent('pf-rentals:rentalError', src, 'You do not have enough money ($' .. totalPrice .. ')')
        return
    end

    -- Create rental record
    local rentalId = 'RENTAL_' .. playerId .. '_' .. os.time()
    local expirationTime = os.time() + (data.duration * 86400) -- 86400 seconds in a day
    
    -- Store rental info
    activeRentals[src] = {
        rentalId = rentalId,
        playerId = playerId,
        playerName = playerName,
        vehicleId = data.vehicleId,
        modelName = data.modelName,
        brand = data.brand,
        displayName = data.vehicleName,
        duration = data.duration,
        dailyRate = data.dailyRate,
        totalPrice = totalPrice,
        paymentMethod = paymentMethod,
        startTime = os.time(),
        expirationTime = expirationTime,
        plate = nil, -- Will be set when vehicle is spawned
        netId = nil
    }
    
    -- Save to database if using a database
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute('INSERT INTO player_rentals (citizenid, rental_id, vehicle_model, brand, duration, daily_rate, total_price, payment_method, start_time, expiration_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            playerId,
            rentalId,
            data.modelName,
            data.brand,
            data.duration,
            data.dailyRate,
            totalPrice,
            paymentMethod,
            os.time(),
            expirationTime
        })
    end
    
    -- Notify client with rental data
    TriggerClientEvent('pf-rentals:rentedVehicle', src, {
        vehicleId = data.vehicleId,
        modelName = data.modelName,
        brand = data.brand,
        displayName = data.vehicleName,
        duration = data.duration,
        totalPrice = totalPrice,
        dailyRate = data.dailyRate,
        expirationTime = expirationTime
    })
    
    if Config.Debug then
        print('^2[pf-rentals]^7 Player ' .. playerName .. ' rented a ' .. data.vehicleName .. ' for ' .. data.duration .. ' day(s)')
    end
end)

-- Server-side vehicle spawning (like Gruppe6)
RegisterNetEvent('pf-rentals:spawnVehicle', function(vehicleModel, spawnPoint, vehicleData)
    local src = source
    
    if Config.Debug then
        print('^2[pf-rentals]^7 Spawning vehicle for player ' .. src .. ' | Model: ' .. vehicleModel)
    end
    
    -- only the car this player rented, once, next to them (any client could spawn any model anywhere)
    local rental = activeRentals[src]
    if not rental or rental.netId or rental.spawning or vehicleModel ~= rental.modelName then return end
    if type(spawnPoint) ~= 'table' and type(spawnPoint) ~= 'vector4' then return end
    local sx, sy, sz, sw = tonumber(spawnPoint.x), tonumber(spawnPoint.y), tonumber(spawnPoint.z), tonumber(spawnPoint.w) or 0.0
    if not (sx and sy and sz) or #(GetEntityCoords(GetPlayerPed(src)) - vector3(sx, sy, sz)) > 50.0 then return end
    spawnPoint = vector4(sx, sy, sz, sw)
    rental.spawning = true
    vehicleData = { modelName = rental.modelName, brand = rental.brand }

    local modelHash = GetHashKey(vehicleModel)
    
    if not IsModelInCdimage(modelHash) or not IsModelAVehicle(modelHash) then
        if Config.Debug then
            print('^1[pf-rentals]^7 Invalid vehicle model: ' .. tostring(vehicleModel))
        end
        TriggerClientEvent('pf-rentals:rentalError', src, 'Invalid vehicle model')
        return
    end
    
    -- Create the vehicle server-side (networked)
    local vehicle = CreateVehicleServerSetter(modelHash, 'automobile', spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w)
    
    -- Wait for the vehicle to be created
    local timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if not DoesEntityExist(vehicle) then
        if Config.Debug then
            print('^1[pf-rentals]^7 Failed to create vehicle on server (timeout)')
        end
        TriggerClientEvent('pf-rentals:rentalError', src, 'Failed to spawn vehicle')
        return
    end
    
    -- Set vehicle properties
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleEngineOn(vehicle, false, false, true)
    
    -- Get the network ID
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local plate = GetVehicleNumberPlateText(vehicle)
    
    if Config.Debug then
        print('^2[pf-rentals]^7 Vehicle created with netId: ' .. netId .. ' | Plate: ' .. plate)
    end
    
    -- Store rental info
    if activeRentals[src] then
        activeRentals[src].plate = plate
        activeRentals[src].netId = netId
        
        -- Store in rental vehicles table
        rentalVehicles[plate] = {
            renterId = src,
            playerName = activeRentals[src].playerName,
            expirationTime = activeRentals[src].expirationTime,
            vehicleModel = vehicleData.modelName,
            brand = vehicleData.brand,
            netId = netId
        }
        
        -- Give vehicle keys
        if Config.UseQBVehicleKeys then
            if GetResourceState('pfm-vehiclekeys') == 'started' then
                exports['pfm-vehiclekeys']:GiveKeys(src, plate)
            elseif GetResourceState('vehiclekeys') == 'started' then
                TriggerEvent('vehiclekeys:server:GiveVehicleKeys', src, plate)
            else
                TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
            end
        end
        
        if Config.Debug then
            print('^2[pf-rentals]^7 Keys given to player ' .. src .. ' for plate: ' .. plate)
        end
    end
    
    -- Send netId back to client
    TriggerClientEvent('pf-rentals:vehicleSpawned', src, netId, plate)
end)

-- ============================================================================
-- RENTAL EXPIRATION CHECK
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(Config.CheckInterval)
        
        local currentTime = os.time()
        
        -- Check expired rentals
        for src, rental in pairs(activeRentals) do
            local player = QBCore.Functions.GetPlayer(src)
            
            if not player then
                activeRentals[src] = nil
            else
                if currentTime >= rental.expirationTime then
                    -- Rental expired
                    TriggerClientEvent('pf-rentals:rentalExpired', src, {
                        rentalId = rental.rentalId,
                        vehicleModel = rental.modelName,
                        plate = rental.plate
                    })
                    
                    -- Delete the vehicle on server side
                    if rental.netId then
                        local vehicle = NetworkGetEntityFromNetworkId(rental.netId)
                        if DoesEntityExist(vehicle) then
                            DeleteEntity(vehicle)
                        end
                    end
                    
                    -- Remove from rental vehicles table
                    if rental.plate then
                        rentalVehicles[rental.plate] = nil
                    end
                    
                    -- Remove from active rentals
                    activeRentals[src] = nil
                    
                    if Config.Debug then
                        print('^2[pf-rentals]^7 Rental expired for ' .. rental.playerName)
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- PLAYER DISCONNECT
-- ============================================================================

AddEventHandler('playerDropped', function(reason)
    local src = source
    
    -- Clean up rental data
    if activeRentals[src] then
        local rental = activeRentals[src]
        if rental.plate then
            rentalVehicles[rental.plate] = nil
        end
        activeRentals[src] = nil
    end
end)

-- ============================================================================
-- COMMANDS (Admin)
-- ============================================================================

RegisterCommand('expirerentals', function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, {
            args = {'Error', 'You do not have permission to use this command'},
            color = {255, 0, 0}
        })
        return
    end
    
    -- Expire all rentals immediately (debug command)
    local currentTime = os.time()
    for src, rental in pairs(activeRentals) do
        activeRentals[src].expirationTime = currentTime - 1
    end
    
    TriggerClientEvent('chat:addMessage', source, {
        args = {'Admin', 'All rentals have been expired'},
        color = {0, 255, 0}
    })
end, false)

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Server admins only (the boss or a grade-3 member of any job could expire everyone's rentals)
function IsPlayerAdmin(src)
    if not src or src == 0 then return false end
    if QBCore.Functions.HasPermission and QBCore.Functions.HasPermission(src, 'admin') == true then return true end
    return IsPlayerAceAllowed(src, 'command') == true
end

-- ============================================================================
-- DATABASE SETUP
-- ============================================================================

if GetResourceState('oxmysql') == 'started' then
    Citizen.CreateThread(function()
        Wait(1000)
        
        -- Create table if it doesn't exist
        exports.oxmysql:execute([[
            CREATE TABLE IF NOT EXISTS `player_rentals` (
                `id` INT(11) NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(50) NOT NULL,
                `rental_id` VARCHAR(100) NOT NULL,
                `vehicle_model` VARCHAR(50) NOT NULL,
                `brand` VARCHAR(50),
                `duration` INT(11),
                `daily_rate` INT(11),
                `total_price` INT(11),
                `payment_method` VARCHAR(20) DEFAULT 'cash',
                `start_time` INT(11),
                `expiration_time` INT(11),
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
        
        if Config.Debug then
            print('^2[pf-rentals]^7 Database table initialized!')
        end
    end)
end

print('^2[pf-rentals]^7 Server integration loaded!')
