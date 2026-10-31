local QBCore = exports['pfm-core']:GetCoreObject()
-- Callbacks go through PFJobsCallback (server/devices_capture.lua) so the tablet and computer apps
-- (server/devices.lua) reuse them; loaded on its own, this file registers them directly.
local CreateCallback = PFJobsCallback or QBCore.Functions.CreateCallback

-- State tables
local searchingPlayers = {}
local activeContracts = {}
local playerActiveContract = {}
local groupSessions = {} -- [leaderId] = { leader = src, members = {src1, src2}, payoutSplits = {[src1] = 25, [src2] = 25} }
local playerGroups = {} -- [src] = leaderId (quick lookup)
local groupCodes = {} -- [leaderId] = code
local codeToLeader = {} -- [code] = leaderId
local contractTimers = {}

-- Track which spawn locations are occupied
local occupiedSpawns = {}
local spawnLocks = {} -- Prevent duplicate spawns
local acceptCooldowns = {} -- NEW: Per-player cooldown
local pendingInvites = {} -- [targetSrc] = { [leaderSrc] = true }

local DEPOSIT_RANGE = 25.0 -- the vault deposit target is used from 2.5 m

PFJobsG6 = PFJobsG6 or {}
local GetFormattedGroupData -- defined with the party code below
local UpgradeCache = {} -- [citizenid] = { [upgradeId] = true }
local AreaHolds = {}    -- police holds after an armoured truck attack: { coords, radius, untilTime, label }

local function isInt(n) return type(n) == 'number' and n == math.floor(n) end

-- A pickup the client names must be the next stop of this contract, by both numbers, and one
-- not already emptied (an emptied stash used to be re-seeded with full bags on reopening).
local function validPickup(contract, locationIdx, pickupNum)
    locationIdx, pickupNum = tonumber(locationIdx), tonumber(pickupNum)
    if not isInt(locationIdx) or not isInt(pickupNum) then return nil end
    if not contract.pickupSequence or contract.pickupSequence[pickupNum] ~= locationIdx then return nil end
    if contract.pickupsDone and contract.pickupsDone[pickupNum] then return nil end
    return locationIdx, pickupNum
end

local function markPickupDone(contract, pickupNum)
    contract.pickupsDone = contract.pickupsDone or {}
    contract.pickupsDone[pickupNum] = true
end

local function GetPlayerName(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.charinfo then
        return ('Player %s'):format(tostring(src))
    end
    return (Player.PlayerData.charinfo.firstname or 'Unknown') .. ' ' .. (Player.PlayerData.charinfo.lastname or 'Player')
end

local function GenerateGroupCode()
    local charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local code = ''
    repeat
        code = ''
        for i = 1, 6 do
            local idx = math.random(1, #charset)
            code = code .. charset:sub(idx, idx)
        end
    until not codeToLeader[code]
    return code
end

-- ── crew pay splits ─────────────────────────────────────────────────
-- A party contract pays a pool (CrewBonus x payout per member); the leader's percentages share it.
-- Percentages are whole numbers, every member gets at least MinSplitPercent and they add up to 100.
-- Any change to the party resets them to equal shares (the leader gets the rounding).

local function SplitFloor() return math.max(0, math.floor(tonumber((Config.Gruppe6.Groups or {}).MinSplitPercent) or 10)) end
local function CrewBonus() return tonumber((Config.Gruppe6.Groups or {}).CrewBonus) or 1.5 end

local function CrewList(group)
    local list = { group.leader }
    for _, m in ipairs(group.members or {}) do list[#list + 1] = m end
    return list
end

local function EqualSplits(list)
    local n = #list
    local out = {}
    if n == 0 then return out end
    local each = math.floor(100 / n)
    for _, id in ipairs(list) do out[id] = each end
    out[list[1]] = each + (100 - each * n)
    return out
end

-- True when splits give every one of `list` a whole share >= the floor, adding up to 100.
local function SplitsValid(splits, list)
    if type(splits) ~= 'table' then return false end
    local sum, floor = 0, SplitFloor()
    for _, id in ipairs(list) do
        local pct = splits[id]
        if type(pct) ~= 'number' or pct % 1 ~= 0 or pct < floor or pct > 100 then return false end
        sum = sum + pct
    end
    local count = 0
    for _ in pairs(splits) do count = count + 1 end
    return sum == 100 and count == #list
end

local function RebalanceGroup(group)
    if not group then return end
    local list = CrewList(group)
    group.payoutSplits = EqualSplits(list)
    local keep = {}
    for _, id in ipairs(list) do keep[id] = (group.cids or {})[id] end
    group.cids = keep
end

-- Who gets what of `pool`: the leader's splits when they still fit the people being paid, equal
-- shares otherwise. Members whose character is unknown are left out before the shares are made.
local function BuildPayPlan(group, participants, perHead)
    local list = {}
    for _, id in ipairs(participants) do
        local P = QBCore.Functions.GetPlayer(id)
        local cid = (P and P.PlayerData.citizenid) or (group.cids or {})[id]
        if cid then list[#list + 1] = { src = id, cid = cid } end
    end
    local ids = {}
    for i, e in ipairs(list) do ids[i] = e.src end
    local splits = SplitsValid(group.payoutSplits, ids) and group.payoutSplits or EqualSplits(ids)
    local pool = math.floor(perHead) * #list
    local given = 0
    for _, e in ipairs(list) do
        e.pct = splits[e.src]
        e.amount = math.floor(pool * e.pct / 100)
        given = given + e.amount
    end
    if list[1] then list[1].amount = list[1].amount + (pool - given) end
    return list, pool
end

PFJobsG6.SplitsValid, PFJobsG6.BuildPayPlan = SplitsValid, BuildPayPlan

-- Bought upgrades: one row each in pf_gruppe6_upgrades (metadata when the database is off).
local function GetUpgrades(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end
    local cid = Player.PlayerData.citizenid
    if UpgradeCache[cid] then return UpgradeCache[cid] end
    local owned = {}
    if Config.Gruppe6.UseDatabase then
        local ok, rows = pcall(MySQL.query.await, 'SELECT upgrade_id FROM pf_gruppe6_upgrades WHERE citizenid = ?', { cid })
        if not ok or type(rows) ~= 'table' then return {} end -- not cached: read again next time
        for _, r in ipairs(rows) do if r.upgrade_id then owned[r.upgrade_id] = true end end
    else
        for id, v in pairs(Player.PlayerData.metadata.gruppe6_upgrades or {}) do
            if v and (Config.Gruppe6.Upgrades or {})[id] then owned[id] = true end
        end
    end
    UpgradeCache[cid] = owned
    return owned
end

-- Helper: Get player XP, level, and upgrades
local function GetPlayerXP(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 0, 1, {} end
    local xp, level = 0, 1
    local fromDb = false
    if Config.Gruppe6.UseDatabase then
        local ok, row = pcall(MySQL.single.await, 'SELECT xp, level FROM pf_gruppe6_xp WHERE citizenid = ?', { Player.PlayerData.citizenid })
        if ok then
            fromDb = true
            if type(row) == 'table' and row.xp ~= nil then
                xp = tonumber(row.xp) or 0
                level = tonumber(row.level) or 1
            end
        end
    end
    if not fromDb then
        xp = tonumber(Player.PlayerData.metadata.gruppe6_xp) or 0
        level = tonumber(Player.PlayerData.metadata.gruppe6_level) or 1
    end
    return xp, level, GetUpgrades(source)
end

-- Helper: Calculate level from XP
local function CalculateLevel(xp)
    local thresholds = Config.Gruppe6.LevelThresholds
    for lvl = #thresholds, 1, -1 do
        if xp >= thresholds[lvl] then
            return lvl
        end
    end
    return 1
end

-- Helper: Add XP to player
local function AddXP(source, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    local xp, level = GetPlayerXP(source)
    xp = xp + amount
    level = CalculateLevel(xp)
    
    if Config.Gruppe6.UseDatabase then
        pcall(MySQL.query.await, 'INSERT INTO pf_gruppe6_xp (citizenid, xp, level) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE xp = VALUES(xp), level = VALUES(level)', {
            Player.PlayerData.citizenid, xp, level
        })
    else
        Player.Functions.SetMetaData('gruppe6_xp', xp)
        Player.Functions.SetMetaData('gruppe6_level', level)
    end
    
    TriggerClientEvent('pf-jobs:gruppe6:updateXP', source, xp, level)
end

-- The upgrade that unlocks contract tier t, if one does
local function tierUpgrade(t)
    for id, u in pairs(Config.Gruppe6.Upgrades or {}) do
        if tonumber(u.unlocksTier) == t then return id end
    end
    return nil
end

local function bagBonus(upgrades)
    local bonus = 0
    for id in pairs(upgrades or {}) do
        local u = (Config.Gruppe6.Upgrades or {})[id]
        if u and tonumber(u.bagBonus) then bonus = bonus + tonumber(u.bagBonus) end
    end
    return bonus
end

local function searchSpeed(upgrades)
    local speed = 1.0
    for id in pairs(upgrades or {}) do
        local u = (Config.Gruppe6.Upgrades or {})[id]
        if u and tonumber(u.searchSpeed) and tonumber(u.searchSpeed) > speed then speed = tonumber(u.searchSpeed) end
    end
    return speed
end

-- Highest tier the level reaches and, where a tier needs a licence, the player owns it
local function contractTier(level, upgrades)
    for t = #Config.Gruppe6.Tiers, 1, -1 do
        local needs = tierUpgrade(t)
        if level >= (Config.Gruppe6.Tiers[t].minLevel or 1) and (not needs or (upgrades or {})[needs]) then return t end
    end
    return 1
end

-- Helper: Generate random contract
local function GenerateContract(level, upgrades)
    local tier = contractTier(level, upgrades)
    local tierData = Config.Gruppe6.Tiers[tier]
    local bonus = bagBonus(upgrades)
    local bags = math.floor(math.random(tierData.bags[1], tierData.bags[2]) * (1 + bonus))
    local payout = math.floor(math.random(tierData.payout[1], tierData.payout[2]) * (1 + bonus))
    local vehicle = tierData.vehicles[math.random(#tierData.vehicles)]

    return {
        tier = tier,
        bags = bags,
        payout = payout,
        bagBonus = bonus,
        vehicle = vehicle,
        maxGroup = Config.Gruppe6.Groups.MaxMembers or 4,
        contractType = 'Bank Delivery'
    }
end

local function nextSearchDelay(src)
    local base = Config.Gruppe6.Debug and math.random(5000, 10000) or math.random(Config.Gruppe6.MinSpawnTime, Config.Gruppe6.MaxSpawnTime)
    local _, _, upgrades = GetPlayerXP(src)
    return math.floor(base / searchSpeed(upgrades))
end

-- SERVER CALLBACK: Get player state
CreateCallback('pf-jobs:gruppe6:getState', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    
    if not Player then 
        cb({ playerId = source, xp = 0, level = 1, contracts = {}, groups = {}, searching = false, activeContract = nil })
        return 
    end
    
    local xp, level = GetPlayerXP(source)
    
    TriggerClientEvent('pf-jobs:gruppe6:updateXP', source, xp, level)
    
    cb({
        playerId = source,
        xp = xp,
        level = level,
        contracts = activeContracts[source] or {},
        groups = groupSessions,
        searching = searchingPlayers[source] or false,
        activeContract = playerActiveContract[source] or nil
    })
end)

-- Start searching (FIXED: Only spawn 1 contract at a time)
RegisterNetEvent('pf-jobs:gruppe6:startSearch', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- FIXED: Clear old timer if exists
    if contractTimers[src] then
        Citizen.ClearTimeout(contractTimers[src])
        contractTimers[src] = nil
    end
    
    searchingPlayers[src] = true
    activeContracts[src] = {}
    
    local function SpawnContract()
        if not searchingPlayers[src] then return end
        
        local _, level, upgrades = GetPlayerXP(src)
        local contract = GenerateContract(level, upgrades)
        
        -- FIXED: Only keep max 1 contract (not 3)
        activeContracts[src] = { contract }
        
        print('[Gruppe6 Server] Spawned 1 contract for player', src)
        
        TriggerClientEvent('pf-jobs:gruppe6:contracts', src, activeContracts[src])
        
        -- Schedule next (Priority Dispatch makes offers come sooner)
        contractTimers[src] = Citizen.SetTimeout(nextSearchDelay(src), SpawnContract)
    end
    
    SpawnContract()
end)

-- Stop searching
RegisterNetEvent('pf-jobs:gruppe6:stopSearch', function()
    local src = source
    searchingPlayers[src] = false
    activeContracts[src] = {}
    
    -- FIXED: Use Citizen.ClearTimeout instead of RemoveTimeout
    if contractTimers[src] then
        Citizen.ClearTimeout(contractTimers[src])
        contractTimers[src] = nil
    end
end)

-- Accept contract (FIXED: Add stronger lock + cooldown)
RegisterNetEvent('pf-jobs:gruppe6:acceptContract', function(data)
    local src = source
    
    -- FIXED: Check if player already has active contract
    if playerActiveContract[src] then
        print('[Gruppe6 Server] ❌ Player already has active contract')
        return
    end
    
    -- FIXED: Check cooldown (prevent spam within 3 seconds)
    local now = os.time()
    if acceptCooldowns[src] and (now - acceptCooldowns[src]) < 3 then
        print('[Gruppe6 Server] ❌ Accept cooldown active for player', src)
        return
    end
    acceptCooldowns[src] = now
    
    -- FIXED: Check spawn lock
    if spawnLocks[src] then
        print('[Gruppe6 Server] ❌ Spawn already in progress for player', src)
        return
    end
    
    spawnLocks[src] = true -- Lock spawning
    
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not activeContracts[src] then 
        spawnLocks[src] = nil
        return 
    end
    
    local contractId = type(data) == 'table' and tonumber(data.contractId)
    local contract = contractId and isInt(contractId) and activeContracts[src][contractId + 1]
    if not contract then 
        spawnLocks[src] = nil
        return 
    end
    
    print('[Gruppe6 Server] ✅ Accepting contract for player', src)
    
    -- Server-side id for this contract (shared with the group); payout keys use it
    contract.payoutId = contract.payoutId or PFPayout.NewId()
    playerActiveContract[src] = contract
    searchingPlayers[src] = false
    activeContracts[src] = {}
    
    if contractTimers[src] then
        Citizen.ClearTimeout(contractTimers[src])
        contractTimers[src] = nil
    end
    
    -- Check if player is in a group; repair missing leader mapping if needed
    local leaderId = playerGroups[src]
    local group = nil
    if leaderId and groupSessions[leaderId] then
        group = groupSessions[leaderId]
    elseif groupSessions[src] then
        leaderId = src
        group = groupSessions[src]
        playerGroups[src] = src
        print('[Gruppe6 Server] 🔧 Repaired leader mapping during accept for', src)
    end
    if group and leaderId == src then
        -- Leader accepted contract - share with all members
        TriggerClientEvent('pf-jobs:gruppe6:activeContract', src, contract)
        
        for _, memberId in ipairs(group.members) do
            playerActiveContract[memberId] = contract
            searchingPlayers[memberId] = false
            activeContracts[memberId] = {}
            
            if contractTimers[memberId] then
                Citizen.ClearTimeout(contractTimers[memberId])
                contractTimers[memberId] = nil
            end
            
            TriggerClientEvent('pf-jobs:gruppe6:activeContract', memberId, contract)
            TriggerClientEvent('QBCore:Notify', memberId, 'Party leader accepted a contract!', 'success')
        end
    else
        -- Solo or non-leader
        TriggerClientEvent('pf-jobs:gruppe6:activeContract', src, contract)
    end
    
    -- Find available spawn location
    local spawnCoords = nil
    for i, coords in ipairs(Config.Gruppe6.VehicleSpawns) do
        if not occupiedSpawns[i] then
            spawnCoords = coords
            occupiedSpawns[i] = src
            break
        end
    end
    
    if not spawnCoords then
        spawnCoords = Config.Gruppe6.VehicleSpawns[math.random(#Config.Gruppe6.VehicleSpawns)]
    end
    
    -- Determine which location pool to use
    local locationPool = Config.Gruppe6.PickupLocations
    if Config.Gruppe6.UseRoxwood then
        if Config.Gruppe6.RemoveLosSantos then
            -- Only use Roxwood locations
            locationPool = Config.Gruppe6.RoxwoodPickupLocations
        else
            -- Merge both Los Santos and Roxwood locations
            locationPool = {}
            for _, loc in ipairs(Config.Gruppe6.PickupLocations) do
                table.insert(locationPool, loc)
            end
            for _, loc in ipairs(Config.Gruppe6.RoxwoodPickupLocations) do
                table.insert(locationPool, loc)
            end
        end
    end
    
    -- Minimum 10 pickup locations per job
    local pickupCount = math.max(Config.Gruppe6.MinPickupLocations or 10, math.random(10, math.min(15, #locationPool)))
    local pickupSequence = {}
    local locationBags = {}
    local usedIndices = {}
    
    -- Select unique random locations
    for i = 1, pickupCount do
        local idx
        repeat
            idx = math.random(#locationPool)
        until not usedIndices[idx]
        
        usedIndices[idx] = true
        table.insert(pickupSequence, idx)
        table.insert(locationBags, math.floor(math.random(Config.Gruppe6.MoneyBagsPerLocationMin, Config.Gruppe6.MoneyBagsPerLocationMax) * (1 + (tonumber(contract.bagBonus) or 0))))
    end
    
    local contractData = {
        vehicle = contract.vehicle,
        plate = Config.Gruppe6.PlatePrefix .. math.random(1000, 9999),
        spawnCoords = spawnCoords,
        pickupSequence = pickupSequence,
        locationBags = locationBags,
        depositLocation = Config.Gruppe6.DepositLocation,
        payout = contract.payout,
        locationPool = locationPool, -- Pass the actual location coordinates to client
        spawnOwner = src -- Only this player (leader) should trigger vehicle spawn
    }
    
    print('[Gruppe6 Server] 🚗 Sending contract to client')
    TriggerClientEvent('pf-jobs:gruppe6:startContract', src, contractData)

    -- If leader accepted and has a group, start contract for party members too (with mapping repair)
    local leaderIdForStart = playerGroups[src]
    local groupForStart = nil
    if leaderIdForStart and groupSessions[leaderIdForStart] then
        groupForStart = groupSessions[leaderIdForStart]
    elseif groupSessions[src] then
        leaderIdForStart = src
        groupForStart = groupSessions[src]
        playerGroups[src] = src
        print('[Gruppe6 Server] 🔧 Repaired leader mapping during vehicle spawn for', src)
    end
    if groupForStart and leaderIdForStart == src then
        for _, memberId in ipairs(groupForStart.members) do
            print('[Gruppe6 Server] 🚗 Sharing contract vehicle spawn to member', memberId)
            TriggerClientEvent('pf-jobs:gruppe6:startContract', memberId, contractData)
        end
    end
    
    -- FIXED: Store contract data for later use
    -- the truck is spawned from these (spawnVehicle used to take model, plate and coords from the client)
    playerActiveContract[src].vehiclePlate = contractData.plate
    playerActiveContract[src].vehicleCoords = spawnCoords
    playerActiveContract[src].spawnOwner = src
    playerActiveContract[src].vehicleSpawned = false
    local totalBags = 0
    for _, c in ipairs(locationBags) do totalBags = totalBags + c end
    playerActiveContract[src].totalBags = totalBags
    playerActiveContract[src].pickupsDone = {}
    playerActiveContract[src].pickupSequence = pickupSequence
    playerActiveContract[src].locationBags = locationBags
    playerActiveContract[src].depositLocation = Config.Gruppe6.DepositLocation
    playerActiveContract[src].completedPickups = 0
    playerActiveContract[src].totalPickups = #pickupSequence
    playerActiveContract[src].locationPool = locationPool -- Store for server-side lookups
    
    -- FIXED: Clear spawn lock after 5 seconds (longer timeout)
    Citizen.SetTimeout(5000, function()
        spawnLocks[src] = nil
        print('[Gruppe6 Server] 🔓 Cleared spawn lock for player', src)
    end)
end)

-- Server-side vehicle spawning (visible to all players)
RegisterNetEvent('pf-jobs:gruppe6:spawnVehicle', function()
    local src = source
    -- one truck per contract, for whoever accepted it, with the contract's own model, plate and spot
    local contract = playerActiveContract[src]
    if not contract or contract.spawnOwner ~= src or contract.vehicleSpawned or not contract.vehicleCoords then return end
    contract.vehicleSpawned = true
    local vehicleModel, plate, coords = contract.vehicle, contract.vehiclePlate, contract.vehicleCoords
    print('[Gruppe6 Apps] Spawning vehicle for player', src, 'model:', vehicleModel, 'plate:', plate)
    
    -- Load vehicle model
    local modelHash = GetHashKey(vehicleModel)
    
    -- Create vehicle server-side with proper networking
    local vehicle = CreateVehicleServerSetter(modelHash, 'automobile', coords.x, coords.y, coords.z, coords.w)
    
    -- Wait for vehicle to exist
    local timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if not DoesEntityExist(vehicle) then
        print('[Gruppe6 Apps] ERROR: Vehicle failed to spawn')
        return
    end
    
    -- Set vehicle properties
    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleDoorsLocked(vehicle, 1)
    
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    print('[Gruppe6 Apps] Vehicle created with netId:', netId)
    
    -- Give vehicle keys
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', src, plate)
    
    -- Send netId to leader and party members (so they get waypoint/blip) including spawn coords for fallback blip
    local spawnCoordData = { x = coords.x, y = coords.y, z = coords.z }
    TriggerClientEvent('pf-jobs:gruppe6:vehicleSpawned', src, netId, plate, src, spawnCoordData)
    local leaderId = playerGroups[src]
    local group = leaderId and groupSessions[leaderId]
    if group and leaderId == src then
        for _, memberId in ipairs(group.members) do
            TriggerClientEvent('pf-jobs:gruppe6:vehicleSpawned', memberId, netId, plate, src, spawnCoordData)
            print('[Gruppe6 Apps] Broadcast vehicle spawn to member', memberId)
        end
    end
end)

-- Create and open pickup stash inventory (qb-inventory v2 API)
local g6ActiveStashes = {} -- [src] = { id = string, pickupNum = number, locationIdx = number }
local g6PickupRemaining = {} -- [stashId] = remaining bag count

local function BroadcastPickupRemaining(stashId, pickupNum, remaining)
    for srcKey, data in pairs(g6ActiveStashes) do
        if data.id == stashId then
            TriggerClientEvent('pf-jobs:gruppe6:updatePickupRemaining', srcKey, pickupNum, remaining)
        end
    end
end

RegisterNetEvent('pf-jobs:gruppe6:openPickupStash', function(locationIdx, pickupNum)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local contract = playerActiveContract[src]
    if not contract then return end
    locationIdx, pickupNum = validPickup(contract, locationIdx, pickupNum)
    if not locationIdx then return end
    if PFJobsG6.HoldAt(contract, locationIdx, src) then return end

    local stashId = ('pf_gruppe6_pickup_%s_%s'):format(locationIdx, pickupNum)
    local initialCount = contract.locationBags[pickupNum] or 0

    if Config.Gruppe6.ServerSideStash then
        if g6PickupRemaining[stashId] == nil then
            g6PickupRemaining[stashId] = initialCount
            if not contract.totalBags then
                local total = 0
                for _, c in ipairs(contract.locationBags) do total = total + (c or 0) end
                contract.totalBags = total
            end
            print('[Gruppe6 Server] 🟢 Init server stash', stashId, 'bags:', initialCount)
        end
        g6ActiveStashes[src] = { id = stashId, pickupNum = pickupNum, locationIdx = locationIdx }
        BroadcastPickupRemaining(stashId, pickupNum, g6PickupRemaining[stashId])
        return
    end

    -- qb-inventory shared stash path
    local itemName = Config.Gruppe6.MoneyBagItem
    local sharedItem = QBCore.Shared.Items[itemName]
    if not sharedItem then
        TriggerClientEvent('QBCore:Notify', src, 'Money bag item not configured', 'error')
        return
    end
    local stashData = { label = ('Pickup #%d Bags'):format(pickupNum), maxweight = 100000, slots = 10 }
    local existing = exports['pfm-inventory']:GetInventory(stashId)
    local currentInStash = 0
    if existing and existing.items then
        for _, itm in pairs(existing.items) do
            if itm and itm.name == itemName then currentInStash = currentInStash + (itm.amount or 0) end
        end
    end
    if g6PickupRemaining[stashId] == nil then
        g6PickupRemaining[stashId] = initialCount
        if not contract.totalBags then
            local total = 0
            for _, c in ipairs(contract.locationBags) do total = total + (c or 0) end
            contract.totalBags = total
        end
    else
        g6PickupRemaining[stashId] = currentInStash
    end
    local remaining = g6PickupRemaining[stashId]
    if not existing then
        exports['pfm-inventory']:CreateInventory(stashId, stashData)
    end
    if currentInStash == 0 and remaining > 0 then
        local items = {
            [1] = { name = itemName, amount = remaining, info = {}, slot = 1, label = sharedItem.label, weight = sharedItem.weight or 0 }
        }
        exports['pfm-inventory']:SetInventory(stashId, items, 'gruppe6-pickup')
    end
    g6ActiveStashes[src] = { id = stashId, pickupNum = pickupNum, locationIdx = locationIdx }
    exports['pfm-inventory']:OpenInventory(src, stashId, stashData)
    BroadcastPickupRemaining(stashId, pickupNum, remaining)
end)

-- Server-side bag collection (no shared qb-inventory container)
RegisterNetEvent('pf-jobs:gruppe6:takePickupBag', function(locationIdx, pickupNum)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local contract = playerActiveContract[src]
    if not contract then return end
    locationIdx, pickupNum = validPickup(contract, locationIdx, pickupNum)
    if not locationIdx then return end
    if PFJobsG6.HoldAt(contract, locationIdx, src) then return end

    local stashId = ('pf_gruppe6_pickup_%s_%s'):format(locationIdx, pickupNum)
    local remaining = g6PickupRemaining[stashId]
    if Config.Gruppe6.ServerSideStash then
        if not remaining then
            g6PickupRemaining[stashId] = contract.locationBags[pickupNum] or 0
            remaining = g6PickupRemaining[stashId]
            g6ActiveStashes[src] = { id = stashId, pickupNum = pickupNum, locationIdx = locationIdx }
        end
        if remaining <= 0 then
            TriggerClientEvent('QBCore:Notify', src, 'No bags remaining here', 'error')
            return
        end
        g6PickupRemaining[stashId] = remaining - 1
        local itemName = Config.Gruppe6.MoneyBagItem
        Player.Functions.AddItem(itemName, 1)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add', 1)
        contract.bagsTaken = (contract.bagsTaken or 0) + 1
        BroadcastPickupRemaining(stashId, pickupNum, g6PickupRemaining[stashId])
        if g6PickupRemaining[stashId] <= 0 then
            g6PickupRemaining[stashId] = nil
            for srcKey, data in pairs(g6ActiveStashes) do
                if data.id == stashId then
                    local keyContract = playerActiveContract[srcKey]
                    if keyContract then
                        markPickupDone(keyContract, pickupNum)
                        keyContract.completedPickups = (keyContract.completedPickups or 0) + 1
                        local nextPickup = pickupNum + 1
                        if nextPickup <= #keyContract.pickupSequence then
                            local nextLocIdx = keyContract.pickupSequence[nextPickup]
                            local locationPool = keyContract.locationPool or Config.Gruppe6.PickupLocations
                            local nextLoc = locationPool[nextLocIdx]
                            local nextBagCount = keyContract.locationBags[nextPickup] or 0
                            TriggerClientEvent('pf-jobs:gruppe6:nextPickup', srcKey, nextLoc, nextLocIdx, nextBagCount)
                        else
                            TriggerClientEvent('pf-jobs:gruppe6:goToDeposit', srcKey, keyContract.depositLocation)
                        end
                    end
                    g6ActiveStashes[srcKey] = nil
                end
            end
        end
        return
    end
    -- In shared stash mode, collection is handled via qb-inventory UI, not this event
end)

-- Client requests check after closing inventory
RegisterNetEvent('pf-jobs:gruppe6:checkStashAfterClose', function(locationIdx, pickupNum)
    local src = source
    local contract = playerActiveContract[src]
    if not contract then return end
    locationIdx, pickupNum = validPickup(contract, locationIdx, pickupNum)
    if not locationIdx then return end
    
    local stashId = string.format('pf_gruppe6_pickup_%d_%d', locationIdx, pickupNum)
    -- only the pickup this player has open; a made-up stash id is empty and used to credit a
    -- whole stop's bags on every call
    if not (g6ActiveStashes[src] and g6ActiveStashes[src].id == stashId) then return end
    
    -- Get actual inventory contents
    local stashItems = exports['pfm-inventory']:GetInventory(stashId)
    local currentInStash = 0
    if stashItems and stashItems.items then
        for _, item in pairs(stashItems.items) do
            if item and item.name == Config.Gruppe6.MoneyBagItem then
                currentInStash = currentInStash + (item.amount or 0)
            end
        end
    end
    
    print('[Gruppe6 Server] Stash check:', stashId, 'Remaining:', currentInStash)
    
    if currentInStash > 0 then
        -- Still bags remaining
        TriggerClientEvent('QBCore:Notify', src, string.format('%d bag(s) remaining', currentInStash), 'primary')
        return
    end
    
    -- All bags taken - calculate and advance
    local initialBags = contract.locationBags[pickupNum] or 0
    local bagsTaken = initialBags - currentInStash
    
    if not contract.bagsTaken then contract.bagsTaken = 0 end
    contract.bagsTaken = contract.bagsTaken + bagsTaken
    if contract.totalBags and contract.bagsTaken > contract.totalBags then contract.bagsTaken = contract.totalBags end
    markPickupDone(contract, pickupNum)
    
    -- Clean up stash
    exports['pfm-inventory']:RemoveInventory(stashId)
    g6PickupRemaining[stashId] = nil
    g6ActiveStashes[src] = nil
    
    TriggerClientEvent('QBCore:Notify', src, string.format('Collected %d bags - Total: %d/%d', bagsTaken, contract.bagsTaken, contract.totalBags or 0), 'success')
    
    -- Advance to next pickup or deposit
    local nextPickup = pickupNum + 1
    local totalPickups = #contract.pickupSequence
    
    if nextPickup <= totalPickups then
        local nextLocIdx = contract.pickupSequence[nextPickup]
        local locationPool = contract.locationPool or Config.Gruppe6.PickupLocations
        local nextLoc = locationPool[nextLocIdx]
        local nextBagCount = contract.locationBags[nextPickup] or 0
        
        print('[Gruppe6 Server] 📍 Next pickup:', nextPickup, '/', totalPickups, 'Bags:', nextBagCount)
        TriggerClientEvent('pf-jobs:gruppe6:nextPickup', src, nextLoc, nextLocIdx, nextBagCount)
    else
        print('[Gruppe6 Server] ✅ All pickups complete, sending to deposit')
        TriggerClientEvent('pf-jobs:gruppe6:goToDeposit', src, contract.depositLocation)
    end
end)

-- Live update: track when items are moved out of the pickup stash
-- LEGACY INVENTORY HANDLER (disabled by ServerSideStash)
-- Listens to pfm-inventory's own net event, which sends (fromInventory, toInventory, fromSlot,
-- toSlot, fromAmount, toAmount) with the mover as `source`. This handler used to read the arguments
-- as (src, fromInv, toInv), so a bag taken OUT of a pickup stash (stash id in the first argument)
-- was never seen and never counted.
local function isG6Stash(id)
    return type(id) == 'string' and id:find('pf_gruppe6_pickup_') == 1
end

local G6RecountPickup

AddEventHandler('qb-inventory:server:SetInventoryData', function(fromInventory, toInventory)
    if Config.Gruppe6.ServerSideStash then return end
    local src = source
    local targetId = nil
    if isG6Stash(fromInventory) then targetId = fromInventory end
    if not targetId and isG6Stash(toInventory) then targetId = toInventory end
    if not targetId then return end
    -- recount once pfm-inventory has finished the move (its handler can wait on the database)
    SetTimeout(250, function() G6RecountPickup(targetId, src) end)
end)

G6RecountPickup = function(targetId, src)
    -- bags are credited only to the player whose open pickup this stash is (anyone can fire the
    -- event by hand; the count itself always comes from the stash's real contents)
    if not (g6ActiveStashes[src] and g6ActiveStashes[src].id == targetId) then src = nil end

    -- Recompute remaining in the affected stash
    local inv = exports['pfm-inventory']:GetInventory(targetId)
    local remaining = 0
    if inv and inv.items then
        for _, itm in pairs(inv.items) do
            if itm and itm.name == Config.Gruppe6.MoneyBagItem then
                remaining = remaining + (itm.amount or 0)
            end
        end
    end
    local prev = g6PickupRemaining[targetId] or remaining
    g6PickupRemaining[targetId] = remaining
    local takenNow = math.max(0, prev - remaining)
    -- Attribute taken bags to the player who caused the move (if has a contract)
    if src and takenNow > 0 then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local contract = playerActiveContract[src]
            if contract then
                contract.bagsTaken = (contract.bagsTaken or 0) + takenNow
                -- Clamp not to exceed total planned
                if contract.totalBags and contract.bagsTaken > contract.totalBags then
                    contract.bagsTaken = contract.totalBags
                end
                TriggerClientEvent('QBCore:Notify', src, ('You took %d bag(s). %d remaining.'):format(takenNow, remaining), 'primary')
            end
        end
    end
    -- If empty, find player contexts to progress
    if remaining == 0 then
        -- Close and remove stash and progress for any players currently tracked
        for srcKey, data in pairs(g6ActiveStashes) do
            if data.id == targetId then
                local Player = QBCore.Functions.GetPlayer(srcKey)
                if Player then
                    local contract = playerActiveContract[srcKey]
                    if contract then
                        exports['pfm-inventory']:RemoveInventory(targetId)
                        g6PickupRemaining[targetId] = nil
                        contract.completedPickups = (contract.completedPickups or 0) + 1
                        local pickupNum = data.pickupNum
                        markPickupDone(contract, pickupNum)
                        g6ActiveStashes[srcKey] = nil
                        local totalPickups = #contract.pickupSequence
                        if pickupNum < totalPickups then
                            local nextIdx = pickupNum + 1
                            local nextLocIdx = contract.pickupSequence[nextIdx]
                            local locationPool = contract.locationPool or Config.Gruppe6.PickupLocations
                            local nextLoc = locationPool[nextLocIdx]
                            local nextBagCount = contract.locationBags[nextIdx] or 0
                            TriggerClientEvent('pf-jobs:gruppe6:nextPickup', srcKey, nextLoc, nextLocIdx, nextBagCount)
                        else
                            TriggerClientEvent('pf-jobs:gruppe6:goToDeposit', srcKey, contract.depositLocation)
                        end
                    end
                end
            end
        end
    else
        -- Notify the player who triggered the move (if any) of remaining count
        if src then
            TriggerClientEvent('QBCore:Notify', src, ('%d bag(s) remaining in stash'):format(remaining), 'primary')
        end
        -- Also broadcast remaining to all players at this pickup so their UI updates
        local pickupNumBroadcast = nil
        for srcKey, data in pairs(g6ActiveStashes) do
            if data.id == targetId then
                pickupNumBroadcast = data.pickupNum
                break
            end
        end
        if pickupNumBroadcast then
            BroadcastPickupRemaining(targetId, pickupNumBroadcast, remaining)
        end
    end
end

-- EARLY END CONTRACT: Skip remaining pickups, go straight to deposit with partial rewards
RegisterNetEvent('pf-jobs:gruppe6:endContract', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local contract = playerActiveContract[src]
    if not contract then
        TriggerClientEvent('QBCore:Notify', src, 'No active contract to end.', 'error')
        return
    end
    if contract.earlyEnd then
        TriggerClientEvent('QBCore:Notify', src, 'Already ending this contract.', 'error')
        return
    end
    contract.earlyEnd = true
    print('[Gruppe6 Server] 🔚 Early termination requested for player', src)
    -- Immediately send player to deposit with current collected bags
    TriggerClientEvent('pf-jobs:gruppe6:goToDeposit', src, Config.Gruppe6.DepositLocation)
    TriggerClientEvent('QBCore:Notify', src, 'Proceed to vault for partial payout.', 'info')
end)

-- FIXED: Add missing callback for checking bags
CreateCallback('pf-jobs:gruppe6:checkBags', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        cb(false, 0)
        return 
    end
    
    local bagCount = Player.Functions.GetItemByName(Config.Gruppe6.MoneyBagItem)
    if bagCount and bagCount.amount > 0 then
        print('[Gruppe6 Server] Player has', bagCount.amount, 'bags')
        cb(true, bagCount.amount)
    else
        print('[Gruppe6 Server] Player has no bags')
        cb(false, 0)
    end
end)

-- FIXED: Add deposit complete handler
RegisterNetEvent('pf-jobs:gruppe6:depositComplete', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local contract = playerActiveContract[src]
    if not contract or contract.finished then return end
    local depositAt = contract.depositLocation or Config.Gruppe6.DepositLocation
    local pcoords = GetEntityCoords(GetPlayerPed(src))
    if not depositAt or #(pcoords - vector3(depositAt.x, depositAt.y, depositAt.z)) > DEPOSIT_RANGE then
        TriggerClientEvent('QBCore:Notify', src, 'Deposit the bags at the vault.', 'error')
        return
    end
    -- Chunked deposit: total to deposit equals collected bags (or proportional when early end)
    local totalCollected = contract.bagsTaken or 0
    if contract.totalBags and totalCollected > contract.totalBags then totalCollected = contract.totalBags end
    contract.depositedBags = contract.depositedBags or 0
    local remainingToDeposit = math.max(0, totalCollected - contract.depositedBags)
    if remainingToDeposit <= 0 then
        TriggerClientEvent('QBCore:Notify', src, 'All collected bags already deposited.', 'success')
    else
        -- Take as many as the player currently carries, up to remainingToDeposit
        local carried = Player.Functions.GetItemByName(Config.Gruppe6.MoneyBagItem)
        local carryCount = carried and carried.amount or 0
        if carryCount <= 0 then
            TriggerClientEvent('QBCore:Notify', src, 'You have no bags on you. Grab more from the truck.', 'error')
            return
        end
        local toRemove = math.min(carryCount, remainingToDeposit)
        Player.Functions.RemoveItem(Config.Gruppe6.MoneyBagItem, toRemove)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.Gruppe6.MoneyBagItem], 'remove', toRemove)
        contract.depositedBags = contract.depositedBags + toRemove
        remainingToDeposit = totalCollected - contract.depositedBags
        TriggerClientEvent('QBCore:Notify', src, string.format('Deposited %d bag(s). %d remaining.', toRemove, math.max(0, remainingToDeposit)), 'primary')
        -- Inform client to keep depositing until remaining is 0
        TriggerClientEvent('pf-jobs:gruppe6:depositProgress', src, contract.depositedBags, totalCollected)
        if remainingToDeposit > 0 then
            return -- More to deposit; do not finalize yet
        end
    end
    
    -- Give payout (updated tier maxes)
    local tierMax = { [1] = 1000, [2] = 2500, [3] = 4000 }
    local tier = contract.tier or 1
    local fullPayout = contract.payout or tierMax[tier] or 500
    local fullXpBase = math.floor(fullPayout / 20)
    fullXpBase = math.max(25, math.min(fullXpBase, 200))

    -- Pay for the bags actually handed in at the vault. A contract used to pay in full with no bags
    -- at all (accept, then deposit at once), and the share counted bags the client reported.
    local deposited = contract.depositedBags or 0
    if deposited <= 0 then
        TriggerClientEvent('QBCore:Notify', src, 'No bags deposited yet.', 'error')
        return
    end
    local percentage = 0
    if contract.totalBags and contract.totalBags > 0 then
        percentage = deposited / contract.totalBags
    end
    if percentage > 1 then percentage = 1 end
    if percentage < 0 then percentage = 0 end

    local maxCap = math.floor((tierMax[tier] or fullPayout) * (1 + (tonumber(contract.bagBonus) or 0)))
    local payout = math.floor((contract.earlyEnd and maxCap or fullPayout) * percentage)
    local xpAmount = math.floor(fullXpBase * percentage)
    if xpAmount < 1 then xpAmount = 0 end
    contract.payoutId = contract.payoutId or PFPayout.NewId()

    -- Get group info
    local leaderId = playerGroups[src]
    if not leaderId and groupSessions[src] then leaderId = src end
    local group = leaderId and groupSessions[leaderId]
    
    if group then
        local participants = CrewList(group)
        local groupXpEach = xpAmount

        -- The crew's pool is what the flat crew bonus paid in total; the leader's splits share it.
        -- The plan is fixed at the first attempt, so a retry pays each member the same share once
        -- (one ledger key per member) even if the party or the splits changed in between.
        if not contract.payPlan then contract.payPlan = BuildPayPlan(group, participants, payout * CrewBonus()) end
        local payFailed = false
        for _, share in ipairs(contract.payPlan) do
            local paid, res = true, {}
            if share.amount > 0 then
                paid, res = PFPayout.Pay(share.cid, 'bank', share.amount, {
                    key = ('pf-jobs:gruppe6:%s:%s'):format(contract.payoutId, share.cid),
                    reason = 'gruppe6-group-contract',
                })
            end
            if not paid then
                payFailed = true
            elseif not share.done then
                share.done = true
                local member = QBCore.Functions.GetPlayerByCitizenId(share.cid)
                local memberSrc = member and member.PlayerData.source
                if memberSrc and not (res and res.duplicate) then
                    AddXP(memberSrc, groupXpEach)
                    TriggerClientEvent('QBCore:Notify', memberSrc, string.format('Party contract complete! Your %d%% share: $%d + %d XP', share.pct, share.amount, groupXpEach), 'success')
                end
            end
        end
        if payFailed then return end

        contract.finished = true
        for _, participantId in ipairs(participants) do
            playerActiveContract[participantId] = nil
            TriggerClientEvent('pf-jobs:gruppe6:activeContract', participantId, nil)
            TriggerClientEvent('pf-jobs:gruppe6:contracts', participantId, {})
        end

    else
        -- Solo payout; on failure keep the contract so depositing again retries with the same key
        if payout > 0 then
            local paid = PFPayout.Pay(Player, 'bank', payout, {
                key = ('pf-jobs:gruppe6:%s:%s'):format(contract.payoutId, Player.PlayerData.citizenid),
                reason = 'gruppe6-contract',
            })
            if not paid then return end
        end
        -- the contract is over: depositing again used to add the XP again
        contract.finished = true
        playerActiveContract[src] = nil
        AddXP(src, xpAmount)
        
        if contract.earlyEnd then
            TriggerClientEvent('QBCore:Notify', src, ('Early contract end: $%d (%d%%) + %d XP'):format(payout, math.floor(percentage*100), xpAmount), 'success')
            print('[Gruppe6 Server] ✅ Early deposit complete - Payout:', payout, 'Pct:', percentage, 'XP:', xpAmount)
        else
            TriggerClientEvent('QBCore:Notify', src, 'Contract complete! Earned $' .. payout, 'success')
            print('[Gruppe6 Server] ✅ Deposit complete - Payout:', payout, 'XP:', xpAmount)
        end
    end

    -- Tell client UI contract is no longer active and clear contracts list
    TriggerClientEvent('pf-jobs:gruppe6:activeContract', src, nil)
    TriggerClientEvent('pf-jobs:gruppe6:contracts', src, {})

    -- Optionally auto-start searching for next contract
    searchingPlayers[src] = true
    activeContracts[src] = {}
    if contractTimers[src] then
        Citizen.ClearTimeout(contractTimers[src])
    end
    contractTimers[src] = Citizen.SetTimeout(nextSearchDelay(src), function()
        local _, level, upgrades = GetPlayerXP(src)
        local newContract = GenerateContract(level, upgrades)
        activeContracts[src] = { newContract }
        TriggerClientEvent('pf-jobs:gruppe6:contracts', src, activeContracts[src])
    end)
end)

-- FIXED: Free spawn location when vehicle returned
RegisterNetEvent('pf-jobs:gruppe6:vehicleReturned', function()
    local src = source
    
    -- Free occupied spawn
    for i, playerId in pairs(occupiedSpawns) do
        if playerId == src then
            occupiedSpawns[i] = nil
            break
        end
    end
    
    -- Clear active contract
    playerActiveContract[src] = nil
    -- Also clear any search locks
    spawnLocks[src] = nil
    acceptCooldowns[src] = nil
end)

-- FIXED: Clear locks on player drop
AddEventHandler('playerDropped', function()
    local src = source
    pendingInvites[src] = nil
    spawnLocks[src] = nil
    acceptCooldowns[src] = nil
    -- the next player to get this server id must not inherit the contract or the search
    playerActiveContract[src] = nil
    searchingPlayers[src] = nil
    activeContracts[src] = nil
    if contractTimers[src] then
        Citizen.ClearTimeout(contractTimers[src])
        contractTimers[src] = nil
    end
    
    -- Free occupied spawn
    for i, playerId in pairs(occupiedSpawns) do
        if playerId == src then
            occupiedSpawns[i] = nil
            break
        end
    end
    
    -- Clean up group if leader leaves
    if groupSessions[src] then
        for _, memberId in ipairs(groupSessions[src].members) do
            playerGroups[memberId] = nil
            TriggerClientEvent('QBCore:Notify', memberId, 'Party disbanded - leader left', 'error')
        end
        local code = groupCodes[src]
        if code then
            codeToLeader[code] = nil
            groupCodes[src] = nil
        end
        groupSessions[src] = nil
    end
    
    -- Remove from group if member
    local leaderId = playerGroups[src]
    if leaderId and groupSessions[leaderId] then
        for i, memberId in ipairs(groupSessions[leaderId].members) do
            if memberId == src then
                table.remove(groupSessions[leaderId].members, i)
                RebalanceGroup(groupSessions[leaderId])
                local formatted = GetFormattedGroupData(leaderId)
                TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', leaderId, formatted)
                for _, mid in ipairs(groupSessions[leaderId].members) do TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', mid, formatted) end
                break
            end
        end
    end
    playerGroups[src] = nil
end)

-- ===== GROUP MANAGEMENT SYSTEM =====

-- Helper: Format group data for client with player names
GetFormattedGroupData = function(leaderId)
    local group = groupSessions[leaderId]
    if not group then return nil end
    
    local formattedMembers = {}
    for _, memberId in ipairs(group.members) do
        local Player = QBCore.Functions.GetPlayer(memberId)
        if Player then
            table.insert(formattedMembers, {
                id = memberId,
                name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
            })
        end
    end
    
    return {
        leader = leaderId,
        leaderName = GetPlayerName(leaderId),
        members = formattedMembers,
        payoutSplits = group.payoutSplits,
        -- the same shares as a list (a table keyed by server id does not survive JSON)
        splits = (function()
            local out = {}
            for _, id in ipairs(CrewList(group)) do out[#out + 1] = { id = id, pct = (group.payoutSplits or {})[id] or 0 } end
            return out
        end)(),
        groupCode = groupCodes[leaderId]
    }
end

-- Create/get group
RegisterNetEvent('pf-jobs:gruppe6:createGroup', function()
    local src = source
    if groupSessions[src] then
        TriggerClientEvent('QBCore:Notify', src, 'You already have a party', 'error')
        return
    end
    
    local LeaderPlayer = QBCore.Functions.GetPlayer(src)
    groupSessions[src] = {
        leader = src,
        members = {},
        payoutSplits = {
            [src] = 100  -- Leader starts with 100%, auto-rebalances when members join
        },
        cids = { [src] = LeaderPlayer and LeaderPlayer.PlayerData.citizenid or nil },
    }
    local code = GenerateGroupCode()
    groupCodes[src] = code
    codeToLeader[code] = src
    
    -- Map leader to themselves so contract sharing works
    if not playerGroups[src] then
        playerGroups[src] = src
        print('[Gruppe6 Server] 🟢 Leader self-mapped playerGroups['..src..']='..src)
    end

    TriggerClientEvent('QBCore:Notify', src, ('Party created! Group code: %s'):format(code), 'success')
    TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', src, GetFormattedGroupData(src))
end)

-- Invite player by server ID
RegisterNetEvent('pf-jobs:gruppe6:invitePlayer', function(targetId)
    local src = source
    local group = groupSessions[src]
    
    if not group then
        TriggerClientEvent('QBCore:Notify', src, 'You need to create a party first', 'error')
        return
    end
    
    if group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the party leader can invite', 'error')
        return
    end
    
    targetId = tonumber(targetId)
    if not targetId then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid player ID', 'error')
        return
    end
    
    local TargetPlayer = QBCore.Functions.GetPlayer(targetId)
    if not TargetPlayer then
        TriggerClientEvent('QBCore:Notify', src, 'Player not found', 'error')
        return
    end
    
    if playerGroups[targetId] then
        TriggerClientEvent('QBCore:Notify', src, 'Player is already in a party', 'error')
        return
    end
    
    if #group.members >= Config.Gruppe6.Groups.MaxMembers - 1 then
        TriggerClientEvent('QBCore:Notify', src, 'Party is full', 'error')
        return
    end
    
    -- Send invite to target player
    local LeaderPlayer = QBCore.Functions.GetPlayer(src)
    local leaderName = LeaderPlayer.PlayerData.charinfo.firstname .. ' ' .. LeaderPlayer.PlayerData.charinfo.lastname
    pendingInvites[targetId] = pendingInvites[targetId] or {}
    pendingInvites[targetId][src] = true
    TriggerClientEvent('pf-jobs:gruppe6:receiveInvite', targetId, leaderName, src)
    TriggerClientEvent('QBCore:Notify', src, string.format('Invite sent to %s (ID: %d)', TargetPlayer.PlayerData.charinfo.firstname .. ' ' .. TargetPlayer.PlayerData.charinfo.lastname, targetId), 'success')
end)

RegisterNetEvent('pf-jobs:gruppe6:joinByCode', function(code)
    local src = source
    local normalized = tostring(code or ''):upper()
    local leaderId = codeToLeader[normalized]

    if not leaderId or not groupSessions[leaderId] then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid or expired group code', 'error')
        return
    end

    if leaderId == src then
        TriggerClientEvent('QBCore:Notify', src, 'You are already the party leader', 'error')
        return
    end

    if playerGroups[src] then
        local oldLeaderId = playerGroups[src]
        local oldGroup = groupSessions[oldLeaderId]
        if oldGroup then
            for i, memberId in ipairs(oldGroup.members) do
                if memberId == src then
                    table.remove(oldGroup.members, i)
                    RebalanceGroup(oldGroup)
                    break
                end
            end
            local oldFormattedData = GetFormattedGroupData(oldLeaderId)
            TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', oldLeaderId, oldFormattedData)
            for _, memberId in ipairs(oldGroup.members) do
                TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, oldFormattedData)
            end
        end
        playerGroups[src] = nil
    end

    local group = groupSessions[leaderId]
    if not group then
        TriggerClientEvent('QBCore:Notify', src, 'Party no longer exists', 'error')
        return
    end

    if #group.members >= Config.Gruppe6.Groups.MaxMembers - 1 then
        TriggerClientEvent('QBCore:Notify', src, 'Party is full', 'error')
        return
    end

    table.insert(group.members, src)
    group.cids = group.cids or {}
    group.cids[src] = (QBCore.Functions.GetPlayer(src) or { PlayerData = {} }).PlayerData.citizenid
    RebalanceGroup(group)
    playerGroups[src] = leaderId

    TriggerClientEvent('QBCore:Notify', src, ('Joined group %s'):format(normalized), 'success')
    TriggerClientEvent('QBCore:Notify', leaderId, string.format('%s joined your group', GetPlayerName(src)), 'success')

    local formattedData = GetFormattedGroupData(leaderId)
    TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', leaderId, formattedData)
    for _, memberId in ipairs(group.members) do
        TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, formattedData)
    end
end)

-- Accept invite
RegisterNetEvent('pf-jobs:gruppe6:acceptInvite', function(leaderId)
    local src = source
    -- only an invite the leader actually sent (anyone could join any party, and share its payout)
    leaderId = tonumber(leaderId)
    if not leaderId or not (pendingInvites[src] and pendingInvites[src][leaderId]) then
        TriggerClientEvent('QBCore:Notify', src, 'No invite from that party', 'error')
        return
    end
    pendingInvites[src][leaderId] = nil
    
    -- If already in a party, leave it first
    if playerGroups[src] then
        local oldLeaderId = playerGroups[src]
        local oldGroup = groupSessions[oldLeaderId]
        
        if oldGroup then
            -- Remove from old group
            for i, memberId in ipairs(oldGroup.members) do
                if memberId == src then
                    table.remove(oldGroup.members, i)
                    RebalanceGroup(oldGroup)
                    break
                end
            end
            
            local Player = QBCore.Functions.GetPlayer(src)
            local memberName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
            
            TriggerClientEvent('QBCore:Notify', oldLeaderId, string.format('%s left to join another party', memberName), 'error')
            
            -- Update old group members
            local oldFormattedData = GetFormattedGroupData(oldLeaderId)
            TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', oldLeaderId, oldFormattedData)
            for _, memberId in ipairs(oldGroup.members) do
                TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, oldFormattedData)
            end
        end
        
        playerGroups[src] = nil
    end
    
    local group = groupSessions[leaderId]
    if not group then
        TriggerClientEvent('QBCore:Notify', src, 'Party no longer exists', 'error')
        return
    end
    
    if #group.members >= Config.Gruppe6.Groups.MaxMembers - 1 then
        TriggerClientEvent('QBCore:Notify', src, 'Party is full', 'error')
        return
    end
    
    table.insert(group.members, src)
    group.cids = group.cids or {}
    group.cids[src] = (QBCore.Functions.GetPlayer(src) or { PlayerData = {} }).PlayerData.citizenid
    -- equal shares again whenever the party changes
    RebalanceGroup(group)
    
    playerGroups[src] = leaderId
    
    local Player = QBCore.Functions.GetPlayer(src)
    local memberName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    
    TriggerClientEvent('QBCore:Notify', src, 'Joined party!', 'success')
    TriggerClientEvent('QBCore:Notify', leaderId, string.format('%s joined the party', memberName), 'success')
    
    -- Update all group members
    local formattedData = GetFormattedGroupData(leaderId)
    TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', leaderId, formattedData)
    for _, memberId in ipairs(group.members) do
        TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, formattedData)
    end
end)

-- Decline invite
RegisterNetEvent('pf-jobs:gruppe6:declineInvite', function(leaderId)
    local src = source
    leaderId = tonumber(leaderId)
    if not leaderId or not (pendingInvites[src] and pendingInvites[src][leaderId]) then return end
    pendingInvites[src][leaderId] = nil
    TriggerClientEvent('QBCore:Notify', leaderId, GetPlayerName(src) .. ' declined the invite', 'error')
end)

-- Leave group
RegisterNetEvent('pf-jobs:gruppe6:leaveGroup', function()
    local src = source
    local leaderId = playerGroups[src]
    
    if not leaderId then
        TriggerClientEvent('QBCore:Notify', src, 'You are not in a party', 'error')
        return
    end
    
    local group = groupSessions[leaderId]
    if group then
        for i, memberId in ipairs(group.members) do
            if memberId == src then
                table.remove(group.members, i)
                RebalanceGroup(group)
                break
            end
        end
        
        local Player = QBCore.Functions.GetPlayer(src)
        local memberName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        
        TriggerClientEvent('QBCore:Notify', leaderId, string.format('%s left the party', memberName), 'error')
        
        -- Update remaining members
        local formattedData = GetFormattedGroupData(leaderId)
        TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', leaderId, formattedData)
        for _, memberId in ipairs(group.members) do
            TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, formattedData)
        end
    end
    
    playerGroups[src] = nil
    TriggerClientEvent('QBCore:Notify', src, 'Left the party', 'success')
    TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', src, nil)
end)

-- Kick member
RegisterNetEvent('pf-jobs:gruppe6:kickMember', function(targetId)
    local src = source
    local group = groupSessions[src]
    
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the party leader can kick members', 'error')
        return
    end
    
    for i, memberId in ipairs(group.members) do
        if memberId == targetId then
            table.remove(group.members, i)
            RebalanceGroup(group)
            playerGroups[targetId] = nil
            
            local TargetPlayer = QBCore.Functions.GetPlayer(targetId)
            local memberName = TargetPlayer and (TargetPlayer.PlayerData.charinfo.firstname .. ' ' .. TargetPlayer.PlayerData.charinfo.lastname) or 'Player'
            
            TriggerClientEvent('QBCore:Notify', targetId, 'You were kicked from the party', 'error')
            TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', targetId, nil)
            TriggerClientEvent('QBCore:Notify', src, string.format('Kicked %s from the party', memberName), 'success')
            
            -- Update remaining members
            local formattedData = GetFormattedGroupData(src)
            TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', src, formattedData)
            for _, memberId in ipairs(group.members) do
                TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, formattedData)
            end
            return
        end
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'Player not in your party', 'error')
end)

local function pushGroup(leaderId)
    local formattedData = GetFormattedGroupData(leaderId)
    TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', leaderId, formattedData)
    for _, memberId in ipairs((groupSessions[leaderId] or {}).members or {}) do
        TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, formattedData)
    end
end

-- The leader sets every share at once: { [memberSrc] = percent, ... } (string keys accepted).
-- Whole numbers, each at least the floor, exactly the party's members, adding up to 100.
RegisterNetEvent('pf-jobs:gruppe6:setSplits', function(splits)
    local src = source
    local group = groupSessions[src]
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the party leader can set the shares', 'error')
        return
    end
    if type(splits) ~= 'table' then return end
    local clean, count = {}, 0
    for k, v in pairs(splits) do
        count = count + 1
        if count > 8 then return end
        local id, pct = tonumber(k), tonumber(v)
        if not id or not pct then return end
        clean[id] = pct
    end
    if not SplitsValid(clean, CrewList(group)) then
        TriggerClientEvent('QBCore:Notify', src, ('Shares must be whole numbers of at least %d%% each, adding up to 100%%'):format(SplitFloor()), 'error')
        return
    end
    group.payoutSplits = clean
    TriggerClientEvent('QBCore:Notify', src, 'Party shares updated', 'success')
    pushGroup(src)
end)

-- Older UI: one member's share; the others share the rest equally (the leader gets the rounding).
RegisterNetEvent('pf-jobs:gruppe6:updateSplit', function(targetId, percentage)
    local src = source
    local group = groupSessions[src]
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the party leader can adjust splits', 'error')
        return
    end
    targetId, percentage = tonumber(targetId), tonumber(percentage)
    local list = CrewList(group)
    local inParty = false
    for _, id in ipairs(list) do if id == targetId then inParty = true end end
    if not inParty or not percentage or percentage % 1 ~= 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid share', 'error')
        return
    end
    local floor = SplitFloor()
    local others = #list - 1
    if percentage < floor or percentage > 100 - floor * others then
        TriggerClientEvent('QBCore:Notify', src, ('Each member needs at least %d%%'):format(floor), 'error')
        return
    end
    local splits = { [targetId] = percentage }
    local rest = {}
    for _, id in ipairs(list) do if id ~= targetId then rest[#rest + 1] = id end end
    if #rest > 0 then
        local each = math.floor((100 - percentage) / #rest)
        for _, id in ipairs(rest) do splits[id] = each end
        local lead = splits[src] ~= nil and targetId ~= src and src or rest[1]
        splits[lead] = splits[lead] + (100 - percentage - each * #rest)
    elseif percentage ~= 100 then
        TriggerClientEvent('QBCore:Notify', src, 'A party of one keeps 100%', 'error')
        return
    end
    if not SplitsValid(splits, list) then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid share', 'error')
        return
    end
    group.payoutSplits = splits
    TriggerClientEvent('QBCore:Notify', src, 'Party shares updated', 'success')
    pushGroup(src)
end)

-- Disband group
RegisterNetEvent('pf-jobs:gruppe6:disbandGroup', function()
    local src = source
    local group = groupSessions[src]
    
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the party leader can disband', 'error')
        return
    end
    
    for _, memberId in ipairs(group.members) do
        playerGroups[memberId] = nil
        TriggerClientEvent('QBCore:Notify', memberId, 'Party disbanded by leader', 'error')
        TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, nil)
    end
    
    local code = groupCodes[src]
    if code then
        codeToLeader[code] = nil
        groupCodes[src] = nil
    end

    groupSessions[src] = nil
    -- Clear leader mapping so future solo contracts don't treat old empty group
    playerGroups[src] = nil
    TriggerClientEvent('QBCore:Notify', src, 'Party disbanded', 'success')
    TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', src, nil)
end)

-- Get group info
CreateCallback('pf-jobs:gruppe6:getGroup', function(source, cb)
    local leaderId = playerGroups[source]
    if leaderId then
        cb(groupSessions[leaderId])
    elseif groupSessions[source] then
        cb(groupSessions[source])
    else
        cb(nil)
    end
end)

-- What the tablet and computer apps show: the offers, this player's contract without its coordinates
-- or payout id, the party with names and code, and the invites still open. XP only when asked
-- (it may wait on the database).
local function publicContract(c)
    if type(c) ~= 'table' then return nil end
    return {
        tier = c.tier,
        bags = c.bags,
        payout = c.payout,
        vehicle = c.vehicle,
        maxGroup = c.maxGroup,
        contractType = c.contractType,
        plate = c.vehiclePlate,
        totalBags = c.totalBags,
        bagsTaken = c.bagsTaken or 0,
        depositedBags = c.depositedBags or 0,
        completedPickups = c.completedPickups or 0,
        totalPickups = c.totalPickups,
        earlyEnd = c.earlyEnd == true,
    }
end

CreateCallback('pf-jobs:gruppe6:getAppView', function(source, cb, withXp)
    local leaderId = playerGroups[source]
    if not (leaderId and groupSessions[leaderId]) and groupSessions[source] then leaderId = source end
    local invites = {}
    for inviter in pairs(pendingInvites[source] or {}) do
        if groupSessions[inviter] then
            invites[#invites + 1] = { leaderId = inviter, leaderName = GetPlayerName(inviter) }
        end
    end
    local view = {
        playerId = source,
        searching = searchingPlayers[source] == true,
        offers = activeContracts[source] or {},
        contract = publicContract(playerActiveContract[source]),
        group = leaderId and GetFormattedGroupData(leaderId) or nil,
        invites = invites,
    }
    if withXp == true then
        local upgrades
        view.xp, view.level, upgrades = GetPlayerXP(source)
        view.upgrades = PFJobsG6.UpgradeList(view.level, upgrades)
    end
    view.holds = PFJobsG6.ActiveHolds()
    local c = playerActiveContract[source]
    if c and view.group then
        -- each member's share if every bag is handed in, from the current splits (or the plan
        -- already fixed for payment)
        local plan = c.payPlan
        if not plan then
            local g = groupSessions[view.group.leader]
            plan = BuildPayPlan(g, CrewList(g), (c.payout or 0) * CrewBonus())
        end
        local shares = {}
        for _, e in ipairs(plan) do shares[#shares + 1] = { id = e.src, pct = e.pct, amount = e.amount } end
        view.payShares = shares
    end
    cb(view)
end)

-- ── upgrades ────────────────────────────────────────────────────────

local function upgradeBlocker(id, def, level, owned)
    if owned[id] then return 'owned' end
    if level < (tonumber(def.requiredLevel) or 1) then return 'level' end
    local req = tonumber(def.requiredTier)
    if req then
        local needs = tierUpgrade(req)
        if needs and not owned[needs] then return 'requires:' .. needs end
    end
    return nil
end

--- Every upgrade with its price and whether this player owns it or can buy it now.
function PFJobsG6.UpgradeList(level, owned)
    owned = owned or {}
    local out = {}
    for id, def in pairs(Config.Gruppe6.Upgrades or {}) do
        local blocker = upgradeBlocker(id, def, tonumber(level) or 1, owned)
        out[#out + 1] = {
            id = id, label = def.label, description = def.description, icon = def.icon, cost = tonumber(def.cost) or 0,
            requiredLevel = tonumber(def.requiredLevel) or 1, owned = owned[id] == true,
            canBuy = blocker == nil, blocker = blocker,
        }
    end
    table.sort(out, function(a, b) if a.cost ~= b.cost then return a.cost < b.cost end return a.id < b.id end)
    return out
end

local function recordUpgrade(Player, id, price)
    local cid = Player.PlayerData.citizenid
    if Config.Gruppe6.UseDatabase then
        local ok = pcall(MySQL.query.await, 'INSERT IGNORE INTO pf_gruppe6_upgrades (citizenid, upgrade_id, price) VALUES (?, ?, ?)', { cid, id, price })
        if not ok then return false end
    else
        local owned = Player.PlayerData.metadata.gruppe6_upgrades or {}
        owned[id] = true
        Player.Functions.SetMetaData('gruppe6_upgrades', owned)
    end
    UpgradeCache[cid] = nil
    return true
end

-- Ledger key of one purchase attempt (PFPayout.Charge adds ':bank'). Attempt 1 is the key older
-- versions used for every attempt, so a charge they completed still counts as paid.
local MAX_UPGRADE_ATTEMPTS = 50
local function upgradeKey(cid, id, attempt)
    local base = ('pf-jobs:gruppe6:upgrade:%s:%s'):format(cid, id)
    return attempt == 1 and base or ('%s:%d'):format(base, attempt)
end

-- The key to charge this purchase under. The ledger never retries a key it closed without moving
-- money (failed, compensated), so those are skipped; a completed key means the upgrade is already
-- paid (its record was lost); a key still in flight stops the purchase.
-- @return string|nil key, string 'free'|'paid'|error, table|nil paid transaction
local function upgradeLedgerKey(cid, id)
    if GetResourceState('pfm-banking') ~= 'started' then return nil, 'bank_unavailable' end
    for attempt = 1, MAX_UPGRADE_ATTEMPTS do
        local key = upgradeKey(cid, id, attempt)
        local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key .. ':bank') end)
        if not ok then return nil, 'bank_unavailable' end
        if type(tx) ~= 'table' then return key, 'free' end
        if tx.state == 'completed' then return key, 'paid', tx end
        if tx.state ~= 'failed' and tx.state ~= 'compensated' then return nil, 'in_progress' end
    end
    return nil, 'too_many_attempts'
end

local UPGRADE_MESSAGES = {
    bank_unavailable = 'The bank did not respond. Nothing was charged.',
    in_progress = 'That purchase is already being processed',
    too_many_attempts = 'This purchase cannot be made right now. Contact staff.',
    db_error = 'Paid, but the upgrade was not saved. Buy it again: you will not be charged twice.',
}

local upgradeBuying = {} -- [citizenid] = true while a purchase runs (double clicks, two windows)

local function buyUpgrade(src, Player, id, def)
    local cid = Player.PlayerData.citizenid
    local _, level, owned = GetPlayerXP(src)
    local blocker = upgradeBlocker(id, def, level, owned)
    if blocker then
        TriggerClientEvent('QBCore:Notify', src, blocker == 'owned' and 'You already own this upgrade'
            or blocker == 'level' and ('Reach level %d first'):format(tonumber(def.requiredLevel) or 1)
            or 'Buy the previous licence first', 'error')
        return false, blocker
    end
    local cost = math.floor(tonumber(def.cost) or 0)
    local price = cost
    if cost > 0 then
        local key, state, paidTx = upgradeLedgerKey(cid, id)
        if not key then
            TriggerClientEvent('QBCore:Notify', src, UPGRADE_MESSAGES[state] or 'Purchase failed', 'error')
            return false, state
        end
        if state == 'paid' then
            price = math.floor(tonumber(paidTx.amount) or cost)
        else
            -- checked first so a click without the money does not close a key as failed
            if (tonumber((Player.PlayerData.money or {}).bank) or 0) < cost then
                TriggerClientEvent('QBCore:Notify', src, ('You need $%d in the bank'):format(cost), 'error')
                return false, 'insufficient_funds'
            end
            local paidFrom, res = PFPayout.Charge(Player, { 'bank' }, cost, {
                key = key, reason = 'gruppe6-upgrade', kind = 'purchase', quiet = true,
            })
            if not paidFrom then
                local err = res and res.error
                local code = (err == 'bank_unavailable' or err == 'ledger_unavailable') and 'bank_unavailable'
                    or err == 'in_progress' and 'in_progress' or 'insufficient_funds'
                TriggerClientEvent('QBCore:Notify', src, UPGRADE_MESSAGES[code] or ('You need $%d in the bank'):format(cost), 'error')
                return false, code
            end
        end
    end
    -- INSERT IGNORE: a purchase recorded twice is still one row
    if not recordUpgrade(Player, id, price) then
        TriggerClientEvent('QBCore:Notify', src, UPGRADE_MESSAGES.db_error, 'error')
        return false, 'db_error'
    end
    TriggerClientEvent('QBCore:Notify', src, ('%s bought'):format(def.label or id), 'success')
    TriggerClientEvent('pf-jobs:gruppe6:upgradesPurchased', src, GetUpgrades(src))
    return true
end

--- Buys an upgrade from the bank account. Each attempt has its own stable ledger key, an owned
--- upgrade is refused, and a paid one is recorded without a second charge.
--- Returns true or false plus a reason.
function PFJobsG6.BuyUpgrade(src, id)
    local def = type(id) == 'string' and (Config.Gruppe6.Upgrades or {})[id] or nil
    if not def then return false, 'unknown_upgrade' end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false, 'no_player' end
    local cid = Player.PlayerData.citizenid
    if upgradeBuying[cid] then return false, 'in_progress' end
    upgradeBuying[cid] = true
    local ok, done, why = pcall(buyUpgrade, src, Player, id, def)
    upgradeBuying[cid] = nil
    if not ok then
        print('^1[pf-jobs]^7 Gruppe 6 upgrade purchase failed: ' .. tostring(done))
        return false, 'error'
    end
    return done, why
end

RegisterNetEvent('pf-jobs:gruppe6:purchaseUpgrade', function(id)
    PFJobsG6.BuyUpgrade(source, id)
end)

-- ── armoured truck robberies (pf-services city event) ───────────────

local function holdMinutesLeft(h) return math.max(0, math.ceil((h.untilTime - os.time()) / 60)) end

function PFJobsG6.ActiveHolds()
    local out, now = {}, os.time()
    for i = #AreaHolds, 1, -1 do
        if AreaHolds[i].untilTime <= now then table.remove(AreaHolds, i) end
    end
    for _, h in ipairs(AreaHolds) do
        out[#out + 1] = { label = h.label, x = h.coords.x, y = h.coords.y, radius = h.radius, minutes = holdMinutesLeft(h) }
    end
    return out
end

local function heldHere(pos)
    for _, h in ipairs(AreaHolds) do
        if h.untilTime > os.time() and #(vector3(pos.x, pos.y, pos.z or 0.0) - h.coords) <= h.radius then return h end
    end
    return nil
end

--- True (and tells the player) when this pickup is inside a police hold.
function PFJobsG6.HoldAt(contract, locationIdx, src)
    local pool = contract.locationPool or Config.Gruppe6.PickupLocations
    local pos = pool[locationIdx]
    local h = pos and heldHere(pos)
    if not h then return false end
    if src then
        TriggerClientEvent('QBCore:Notify', src, ('Police hold at this pickup after an armoured truck attack: %d more minute(s). Wait, or end the contract early.'):format(holdMinutesLeft(h)), 'error')
    end
    return true
end

local function nextPickupPos(contract)
    if not contract or not contract.pickupSequence then return nil end
    for n, idx in ipairs(contract.pickupSequence) do
        if not (contract.pickupsDone and contract.pickupsDone[n]) then
            return (contract.locationPool or Config.Gruppe6.PickupLocations)[idx]
        end
    end
    return nil
end

--- A truck was attacked: hold pickups near it and warn every crew on a contract or searching.
--- Returns how many players were warned.
function PFJobsG6.OnTruckRobbery(event)
    local cfgA = Config.Gruppe6.RobberyAlert or {}
    if cfgA.Enabled == false or type(event) ~= 'table' then return 0 end
    local okC, x, y, z = pcall(function() return tonumber(event.coords.x), tonumber(event.coords.y), tonumber(event.coords.z) end)
    if not okC or not x or not y then return 0 end
    local radius = tonumber(cfgA.Radius) or 600.0
    local hold = { coords = vector3(x, y, z or 0.0), radius = radius, untilTime = os.time() + (tonumber(cfgA.HoldMinutes) or 10) * 60,
        label = event.district or event.title or 'Armoured truck attack' }
    PFJobsG6.ActiveHolds() -- drops expired holds
    AreaHolds[#AreaHolds + 1] = hold
    local warned, seen = 0, {}
    local function warn(src)
        if seen[src] then return end
        seen[src] = true
        local c = playerActiveContract[src]
        local nextPos = nextPickupPos(c)
        local affected = nextPos and #(vector3(nextPos.x, nextPos.y, nextPos.z or 0.0) - hold.coords) <= radius
        local msg = affected
            and ('Armoured truck attack near your next pickup. Police hold for %d minutes: wait or end the contract early.'):format(holdMinutesLeft(hold))
            or 'Armoured truck attack reported in the city. Stay alert and avoid the area.'
        TriggerClientEvent('QBCore:Notify', src, msg, 'error', 10000)
        pcall(function() exports['pf-devices']:Push(src, 'gruppe6', 'alert', { message = msg, affected = affected == true, x = x, y = y, minutes = holdMinutesLeft(hold) }) end)
        warned = warned + 1
    end
    for src in pairs(playerActiveContract) do warn(src) end
    for src, on in pairs(searchingPlayers) do if on then warn(src) end end
    return warned
end

AddEventHandler('pf-services:cityEvent', function(event)
    if type(event) == 'table' and event.kind == 'crime.robbery.truck' then PFJobsG6.OnTruckRobbery(event) end
end)

-- ── deleted characters ──────────────────────────────────────────────

--- Removes a deleted character from any live party (a leader's party is closed) and forgets its
--- cached upgrades. Its rows are deleted by server/schema.lua.
function PFJobsG6.ForgetCitizen(cid)
    UpgradeCache[cid] = nil
    for leaderId, group in pairs(groupSessions) do
        for memberSrc, memberCid in pairs(group.cids or {}) do
            if memberCid == cid then
                if memberSrc == leaderId then
                    for _, m in ipairs(group.members) do
                        playerGroups[m] = nil
                        TriggerClientEvent('QBCore:Notify', m, 'Party disbanded', 'error')
                        TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', m, nil)
                    end
                    local code = groupCodes[leaderId]
                    if code then codeToLeader[code] = nil; groupCodes[leaderId] = nil end
                    groupSessions[leaderId] = nil
                else
                    for i, m in ipairs(group.members) do
                        if m == memberSrc then table.remove(group.members, i) break end
                    end
                    RebalanceGroup(group)
                    pushGroup(leaderId)
                end
                playerGroups[memberSrc] = nil
                playerActiveContract[memberSrc] = nil
                searchingPlayers[memberSrc] = false
            end
        end
    end
end

print('[Gruppe6] ✅ Server loaded successfully')

-- Removed: Storage now uses native vehicle trunk (qb-inventory handles automatically)