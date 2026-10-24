local QBCore = exports['pfm-core']:GetCoreObject()

-- State storage
local ActiveContracts = {} -- [src] = { contract data, vehicle, pickups, etc }
local SearchingPlayers = {}
local AvailableContracts = {}
local ContractTimers = {} -- Track when each contract was generated
local SpawnedVehicles = {} -- Track occupied spawn points
local Groups = {} -- [groupId] = { leader, members, open }
local PlayerXP = {} -- [citizenid] = xp
local nextGroupId = 1

-- NEW: Accept cooldown (prevents duplicate spawns)
local AcceptCooldowns = {}

print('^2[Gruppe6]^7 Loading server script...')

-- Config
local CONTRACT_EXPIRY_TIME = 5 * 60 * 1000 -- 5 minutes in ms
local XP_PENALTY_EXPIRED = 10

-- XP Functions
local function GetPlayerXP(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return 0 end
    local cid = Player.PlayerData.citizenid
    
    if Config.Gruppe6.UseDatabase then
        if not PlayerXP[cid] then
            -- Load from database
            local result = MySQL.Sync.fetchScalar('SELECT xp FROM pf_gruppe6_xp WHERE citizenid = ?', {cid})
            PlayerXP[cid] = result or 0
        end
        return PlayerXP[cid]
    else
        return Player.PlayerData.metadata.gruppe6xp or 0
    end
end

local function SetPlayerXP(src, xp)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    
    if Config.Gruppe6.UseDatabase then
        PlayerXP[cid] = xp
        MySQL.Async.execute('INSERT INTO pf_gruppe6_xp (citizenid, xp) VALUES (?, ?) ON DUPLICATE KEY UPDATE xp = ?', {cid, xp, xp})
    else
        Player.Functions.SetMetaData('gruppe6xp', xp)
    end
end

local function CalculateLevel(xp)
    local thresholds = Config.Gruppe6.LevelThresholds
    for level = #thresholds, 1, -1 do
        if xp >= thresholds[level] then
            return level
        end
    end
    return 1
end

-- Contract Generation (filter by player level)
local function GenerateContractForLevel(level)
    local validTiers = {}
    for _, tier in pairs(Config.Gruppe6.Tiers) do
        if level >= tier.minLevel then
            table.insert(validTiers, tier)
        end
    end
    
    if #validTiers == 0 then
        validTiers = {Config.Gruppe6.Tiers[1]}
    end
    
    local tier = validTiers[math.random(1, #validTiers)]
    local bags = math.random(tier.bags[1], tier.bags[2])
    local payout = math.random(tier.payout[1], tier.payout[2])
    local vehicle = tier.vehicles[math.random(1, #tier.vehicles)]
    
    return {
        tier = tier.minLevel,
        bags = bags,
        payout = payout,
        vehicle = vehicle,
        contractType = 'Bank Delivery',
        maxGroup = 4,
        generatedAt = os.time() * 1000, -- Track generation time
    }
end

local function BroadcastContracts()
    for src, _ in pairs(SearchingPlayers) do
        TriggerClientEvent('pf-jobs:gruppe6:contracts', src, AvailableContracts)
    end
end

local function GeneratePickupSequence(numPickups)
    local locations = Config.Gruppe6.PickupLocations
    local sequence = {}
    for i = 1, numPickups do
        local randomIdx = math.random(1, #locations)
        table.insert(sequence, randomIdx)
    end
    return sequence
end

local function GetAvailableSpawn()
    for i, spawn in ipairs(Config.Gruppe6.VehicleSpawns) do
        if not SpawnedVehicles[i] then
            return i, spawn
        end
    end
    return nil, nil
end

local function GenerateG6Plate()
    local prefix = Config.Gruppe6.PlatePrefix
    local num = math.random(1000, 9999)
    return prefix .. num
end

-- Check and remove expired contracts
local function CheckExpiredContracts()
    local currentTime = os.time() * 1000
    local expiredIndices = {}
    
    for i, contract in ipairs(AvailableContracts) do
        if contract.generatedAt and (currentTime - contract.generatedAt) > CONTRACT_EXPIRY_TIME then
            table.insert(expiredIndices, i)
            print('[Gruppe6] Contract', i, 'expired after 5 minutes')
        end
    end
    
    -- Remove from back to front to maintain indices
    for i = #expiredIndices, 1, -1 do
        table.remove(AvailableContracts, expiredIndices[i])
    end
    
    if #expiredIndices > 0 then
        -- Penalize all searching players
        for src, _ in pairs(SearchingPlayers) do
            local currentXP = GetPlayerXP(src)
            local newXP = math.max(0, currentXP - XP_PENALTY_EXPIRED)
            SetPlayerXP(src, newXP)
            
            local level = CalculateLevel(newXP)
            TriggerClientEvent('pf-jobs:gruppe6:updateXP', src, newXP, level)
            TriggerClientEvent('QBCore:Notify', src, string.format('Contract expired! -%d XP', XP_PENALTY_EXPIRED), 'error')
        end
        
        BroadcastContracts()
    end
end

-- Start Search (GUARANTEE 3 immediate contracts)
RegisterNetEvent('pf-jobs:gruppe6:startSearch', function()
    local src = source
    local level = CalculateLevel(GetPlayerXP(src))
    
    SearchingPlayers[src] = true
    
    print('[Gruppe6] Player', src, 'started searching (Level', level, ')')
    
    -- ALWAYS generate 3 contracts immediately if none exist
    if #AvailableContracts == 0 then
        for i = 1, 3 do
            table.insert(AvailableContracts, GenerateContractForLevel(level))
        end
        print('[Gruppe6] Generated 3 IMMEDIATE contracts for level', level)
    end
    
    -- Send contracts to player immediately
    TriggerClientEvent('pf-jobs:gruppe6:contracts', src, AvailableContracts)
    TriggerClientEvent('QBCore:Notify', src, string.format('Found %d contracts!', #AvailableContracts), 'success')
    
    -- Also send current XP/level state
    local xp = GetPlayerXP(src)
    TriggerClientEvent('pf-jobs:gruppe6:updateXP', src, xp, level)
    
    print('[Gruppe6] Sent', #AvailableContracts, 'contracts to player', src, 'XP:', xp, 'Level:', level)
end)

RegisterNetEvent('pf-jobs:gruppe6:stopSearch', function()
    local src = source
    SearchingPlayers[src] = nil
    TriggerClientEvent('QBCore:Notify', src, 'Stopped searching', 'info')
end)

RegisterNetEvent('pf-jobs:gruppe6:acceptContract', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- FIXED: Check accept cooldown (3 seconds)
    local now = os.time()
    if AcceptCooldowns[src] and (now - AcceptCooldowns[src]) < 3 then
        print('[Gruppe6] ❌ Accept cooldown active for player', src)
        TriggerClientEvent('QBCore:Notify', src, 'Please wait before accepting another contract', 'error')
        return
    end
    
    -- FIXED: Check if player already has active contract
    if ActiveContracts[src] then
        print('[Gruppe6] ❌ Player already has active contract')
        TriggerClientEvent('QBCore:Notify', src, 'You already have an active contract', 'error')
        return
    end
    
    -- Set cooldown
    AcceptCooldowns[src] = now
    
    print('[Gruppe6] Accept contract from', src, 'data:', json.encode(data or {}))
    
    local contractId = type(data) == 'table' and data.contractId or data
    if not contractId then
        print('[Gruppe6] ERROR: No contractId')
        TriggerClientEvent('QBCore:Notify', src, 'Invalid contract', 'error')
        return
    end
    
    local luaIndex = tonumber(contractId) + 1
    local contract = AvailableContracts[luaIndex]
    
    if not contract then
        print('[Gruppe6] ERROR: Contract not found at index', luaIndex)
        TriggerClientEvent('QBCore:Notify', src, 'Contract unavailable', 'error')
        return
    end
    
    local spawnIdx, spawnCoords = GetAvailableSpawn()
    if not spawnCoords then
        TriggerClientEvent('QBCore:Notify', src, 'No spawn points available', 'error')
        return
    end
    
    local pickupSequence = GeneratePickupSequence(contract.bags)
    local locationBags = {}
    local totalBagsAvailable = 0
    
    for i = 1, contract.bags do
        local bagCount = math.random(Config.Gruppe6.MoneyBagsPerLocationMin, Config.Gruppe6.MoneyBagsPerLocationMax)
        locationBags[i] = bagCount
        totalBagsAvailable = totalBagsAvailable + bagCount
    end
    
    local plate = GenerateG6Plate()
    
    ActiveContracts[src] = {
        contract = contract,
        spawnIdx = spawnIdx,
        spawnCoords = spawnCoords,
        plate = plate,
        pickupSequence = pickupSequence,
        locationBags = locationBags,
        currentPickup = 1,
        bagsCollected = 0,
        totalBagsAvailable = totalBagsAvailable,
        vehicleNetId = nil,
        startTime = os.time(),
        payoutId = PFPayout.NewId(), -- server-side contract id; the payout key uses it
    }

    SpawnedVehicles[spawnIdx] = src
    table.remove(AvailableContracts, luaIndex)
    
    print('[Gruppe6] ✅ Contract accepted:', contract.vehicle, contract.bags, 'bags')
    
    TriggerClientEvent('pf-jobs:gruppe6:startContract', src, {
        vehicle = contract.vehicle,
        spawnCoords = spawnCoords,
        plate = plate,
        pickupSequence = pickupSequence,
        bags = contract.bags,
        locationBags = locationBags,
    })
    
    TriggerClientEvent('QBCore:Notify', src, 'Contract accepted!', 'success')
    BroadcastContracts()
    TriggerClientEvent('pf-jobs:gruppe6:activeContract', src, contract)
end)

-- Server-side vehicle spawning (so all players can see the vehicle)
RegisterNetEvent('pf-jobs:gruppe6:spawnVehicle', function(contractData)
    local src = source
    print('[Gruppe6] Spawn vehicle requested by player', src)
    local contract = ActiveContracts[src]
    if not contract then 
        print('[Gruppe6] ERROR: No active contract for player', src)
        return 
    end
    
    local coords = vector4(contractData.spawnCoords.x, contractData.spawnCoords.y, contractData.spawnCoords.z, contractData.spawnCoords.w)
    
    -- Create vehicle on server side
    print('[Gruppe6] Creating vehicle', contractData.vehicle, 'at', coords)
    local veh = CreateVehicle(GetHashKey(contractData.vehicle), coords.x, coords.y, coords.z, coords.w, true, true)
    
    while not DoesEntityExist(veh) do
        Wait(10)
    end
    
    SetVehicleNumberPlateText(veh, contractData.plate)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleEngineOn(veh, false, false, false)
    
    local netId = NetworkGetNetworkIdFromEntity(veh)
    contract.vehicleNetId = netId
    
    print('[Gruppe6] Vehicle created successfully, netId:', netId)
    
    -- Send vehicle netId back to client
    TriggerClientEvent('pf-jobs:gruppe6:vehicleSpawned', src, netId)
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, contractData.plate)
end)

RegisterNetEvent('pf-jobs:gruppe6:vehicleSpawned', function(netId)
    local src = source
    local contract = ActiveContracts[src]
    if not contract then return end
    
    contract.vehicleNetId = netId
end)

-- Request Pickup Inventory (SIMPLIFIED - Direct give with progressbar)
RegisterNetEvent('pf-jobs:gruppe6:requestPickupInventory', function(locationIdx, pickupNum)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local contract = ActiveContracts[src]
    if not contract then 
        print('[Gruppe6] ERROR: No active contract for player', src)
        return 
    end
    
    local bagCount = contract.locationBags[pickupNum] or 0
    
    print('[Gruppe6] Player', src, 'collecting pickup #', pickupNum, 'with', bagCount, 'bags')
    print('[Gruppe6] Current pickup before update:', contract.currentPickup)
    print('[Gruppe6] Total pickups in sequence:', #contract.pickupSequence)
    
    -- Give bags directly
    Player.Functions.AddItem(Config.Gruppe6.MoneyBagItem, bagCount)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.Gruppe6.MoneyBagItem], 'add', bagCount)
    
    -- Update contract tracking
    contract.bagsCollected = contract.bagsCollected + bagCount
    contract.currentPickup = contract.currentPickup + 1
    
    print('[Gruppe6] Updated: bagsCollected =', contract.bagsCollected, ', currentPickup =', contract.currentPickup)
    
    -- Check if more pickups remain
    if contract.currentPickup <= #contract.pickupSequence then
        -- More pickups remaining
        local nextIdx = contract.pickupSequence[contract.currentPickup]
        local nextLoc = Config.Gruppe6.PickupLocations[nextIdx]
        local nextBagCount = contract.locationBags[contract.currentPickup] or 0
        
        print('[Gruppe6] Sending player to next pickup #', contract.currentPickup, 'at location index', nextIdx, 'with', nextBagCount, 'bags')
        
        TriggerClientEvent('pf-jobs:gruppe6:nextPickup', src, nextLoc, nextIdx, nextBagCount)
        TriggerClientEvent('QBCore:Notify', src, string.format('Pickup %d/%d complete. Collected %d bags. Head to next location.', contract.currentPickup - 1, #contract.pickupSequence, bagCount), 'success')
    else
        -- All pickups done, go to deposit
        print('[Gruppe6] All pickups complete. Sending player to deposit with', contract.bagsCollected, 'total bags')
        
        TriggerClientEvent('pf-jobs:gruppe6:goToDeposit', src, Config.Gruppe6.DepositLocation)
        TriggerClientEvent('QBCore:Notify', src, string.format('All %d pickups complete! Deliver %d bags to deposit.', #contract.pickupSequence, contract.bagsCollected), 'info')
    end
end)

QBCore.Functions.CreateCallback('pf-jobs:gruppe6:checkBags', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false, 0); return end
    
    local item = Player.Functions.GetItemByName(Config.Gruppe6.MoneyBagItem)
    cb(item and item.amount > 0, item and item.amount or 0)
end)

RegisterNetEvent('pf-jobs:gruppe6:depositComplete', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local contract = ActiveContracts[src]
    if not contract then return end
    
    local item = Player.Functions.GetItemByName(Config.Gruppe6.MoneyBagItem)
    local bagsDeposited = item and item.amount or 0
    
    if bagsDeposited == 0 then
        TriggerClientEvent('QBCore:Notify', src, 'No bags to deposit!', 'error')
        return
    end
    
    Player.Functions.RemoveItem(Config.Gruppe6.MoneyBagItem, bagsDeposited)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.Gruppe6.MoneyBagItem], 'remove', bagsDeposited)
    
    local percentage = bagsDeposited / contract.totalBagsAvailable
    local actualPayout = math.floor(contract.contract.payout * percentage)
    local xpGained = bagsDeposited * Config.Gruppe6.XPPerBag
    
    if actualPayout > 0 then
        local paid = PFPayout.Pay(Player, 'bank', actualPayout, {
            key = ('pf-jobs:gruppe6:contract:%s:%s'):format(contract.payoutId, Player.PlayerData.citizenid),
            reason = 'Gruppe6 Contract',
        })
        if not paid then
            -- Give the bags back and keep the contract so the player can deposit again
            Player.Functions.AddItem(Config.Gruppe6.MoneyBagItem, bagsDeposited)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.Gruppe6.MoneyBagItem], 'add', bagsDeposited)
            return
        end
    end

    local currentXP = GetPlayerXP(src)
    local newXP = currentXP + xpGained
    SetPlayerXP(src, newXP)
    
    local level = CalculateLevel(newXP)
    TriggerClientEvent('pf-jobs:gruppe6:updateXP', src, newXP, level)
    
    if contract.spawnIdx then
        SpawnedVehicles[contract.spawnIdx] = nil
    end
    
    if contract.vehicleNetId then
        TriggerClientEvent('pf-jobs:gruppe6:deleteVehicle', src, contract.vehicleNetId)
    end
    
    ActiveContracts[src] = nil
    
    TriggerClientEvent('QBCore:Notify', src, string.format('Complete! $%s + %d XP', actualPayout, xpGained), 'success')
    TriggerClientEvent('pf-jobs:gruppe6:activeContract', src, nil)
    BroadcastContracts()
end)

RegisterNetEvent('pf-jobs:gruppe6:endContract', function()
    local src = source
    local contract = ActiveContracts[src]
    if not contract then return end
    
    if contract.spawnIdx then
        SpawnedVehicles[contract.spawnIdx] = nil
    end
    
    if contract.vehicleNetId then
        TriggerClientEvent('pf-jobs:gruppe6:deleteVehicle', src, contract.vehicleNetId)
    end
    
    ActiveContracts[src] = nil
    TriggerClientEvent('QBCore:Notify', src, 'Contract ended', 'error')
    TriggerClientEvent('pf-jobs:gruppe6:activeContract', src, nil)
end)

QBCore.Functions.CreateCallback('pf-jobs:gruppe6:getState', function(source, cb)
    local xp = GetPlayerXP(source)
    local level = CalculateLevel(xp)
    local activeContract = ActiveContracts[source] and ActiveContracts[source].contract or nil
    local searching = SearchingPlayers[source] ~= nil
    
    print('[Gruppe6] GetState for player', source, '- XP:', xp, 'Level:', level, 'Contracts:', #AvailableContracts, 'Searching:', searching)
    
    cb({
        xp = xp,
        level = level,
        contracts = AvailableContracts,
        activeContract = activeContract,
        searching = searching,
        playerId = source
    })
end)

-- Group stubs
QBCore.Functions.CreateCallback('pf-jobs:gruppe6:createGroup', function(source, cb, open)
    local gid = nextGroupId
    nextGroupId = nextGroupId + 1
    Groups[gid] = { leader = source, members = {}, open = open or false }
    cb({ id = gid })
end)

QBCore.Functions.CreateCallback('pf-jobs:gruppe6:getGroups', function(source, cb)
    cb(Groups)
end)

QBCore.Functions.CreateCallback('pf-jobs:gruppe6:invite', function(source, cb, groupId, cid)
    cb(true)
end)

QBCore.Functions.CreateCallback('pf-jobs:gruppe6:setSplit', function(source, cb, groupId, cid, cut)
    cb(true)
end)

QBCore.Functions.CreateCallback('pf-jobs:gruppe6:leave', function(source, cb, groupId)
    cb(true)
end)

-- Auto-generate contracts (random timing if debug mode)
CreateThread(function()
    while true do
        local waitTime
        if Config.Gruppe6.Debug then
            -- Debug: Random between 5-10 seconds
            waitTime = math.random(5000, 10000)
        else
            -- Production: Random between 5-10 minutes
            waitTime = math.random(Config.Gruppe6.MinSpawnTime, Config.Gruppe6.MaxSpawnTime)
        end
        
        Wait(waitTime)
        
        -- Check for expired contracts every cycle
        CheckExpiredContracts()
        
        -- Generate new contracts if players are searching and < 3 contracts
        if next(SearchingPlayers) and #AvailableContracts < 3 then
            local avgLevel = 1
            local count = 0
            for src, _ in pairs(SearchingPlayers) do
                avgLevel = avgLevel + CalculateLevel(GetPlayerXP(src))
                count = count + 1
            end
            if count > 0 then avgLevel = math.floor(avgLevel / count) end
            
            table.insert(AvailableContracts, GenerateContractForLevel(avgLevel))
            print('[Gruppe6] Auto-generated contract for level', avgLevel, '. Total:', #AvailableContracts, 'Wait was:', waitTime, 'ms')
            BroadcastContracts()
        end
    end
end)

-- Separate thread for contract expiration checks (every 30 seconds)
CreateThread(function()
    while true do
        Wait(30000) -- Check every 30 seconds
        CheckExpiredContracts()
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    SearchingPlayers[src] = nil
    AcceptCooldowns[src] = nil -- NEW: Clear cooldown
    
    if ActiveContracts[src] then
        if ActiveContracts[src].spawnIdx then
            SpawnedVehicles[ActiveContracts[src].spawnIdx] = nil
        end
        ActiveContracts[src] = nil
    end
end)

print('^2[Gruppe6]^7 Server loaded successfully')

RegisterNetEvent('pf-jobs:gruppe6:vehicleReturned', function()
    local src = source
    local contract = ActiveContracts[src]
    if not contract then return end
    
    -- Cleanup spawn point
    if contract.spawnIdx then
        SpawnedVehicles[contract.spawnIdx] = nil
    end
    
    ActiveContracts[src] = nil
    
    TriggerClientEvent('QBCore:Notify', src, 'Contract completed successfully!', 'success')
    TriggerClientEvent('pf-jobs:gruppe6:activeContract', src, nil)
end)
