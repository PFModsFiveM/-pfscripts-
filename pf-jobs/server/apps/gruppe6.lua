local QBCore = exports['pfm-core']:GetCoreObject()

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

-- Helper: Get player XP, level, and upgrades
local function GetPlayerXP(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 0, 1, {} end
    
    local xp = 0
    local level = 1
    local upgrades = {}
    
    if Config.Gruppe6.UseDatabase then
        -- Use Async.fetchSingle instead of Sync (more reliable)
        local success = false
        MySQL.Async.fetchSingle('SELECT xp, level, upgrades FROM pf_gruppe6_xp WHERE citizenid = ?', { Player.PlayerData.citizenid }, function(result)
            if result then
                xp = tonumber(result.xp) or 0
                level = tonumber(result.level) or 1
                upgrades = json.decode(result.upgrades or '{}') or {}
                success = true
                print('[Gruppe6 GetPlayerXP] ✅ Database read - XP:', xp, 'Level:', level, 'Upgrades:', json.encode(upgrades))
            else
                print('[Gruppe6 GetPlayerXP] ❌ No entry found for citizenid:', Player.PlayerData.citizenid)
            end
        end)
        
        -- Wait for database query (synchronous behavior)
        local timeout = 0
        while not success and timeout < 50 do
            Wait(10)
            timeout = timeout + 1
        end
        
        if not success then
            print('[Gruppe6 GetPlayerXP] ⚠️ Database timeout, using metadata fallback')
            xp = tonumber(Player.PlayerData.metadata.gruppe6_xp) or 0
            level = tonumber(Player.PlayerData.metadata.gruppe6_level) or 1
            upgrades = Player.PlayerData.metadata.gruppe6_upgrades or {}
        end
    else
        xp = tonumber(Player.PlayerData.metadata.gruppe6_xp) or 0
        level = tonumber(Player.PlayerData.metadata.gruppe6_level) or 1
        upgrades = Player.PlayerData.metadata.gruppe6_upgrades or {}
        print('[Gruppe6 GetPlayerXP] Using metadata - XP:', xp, 'Level:', level)
    end
    
    return xp, level, upgrades
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
        MySQL.Async.execute('INSERT INTO pf_gruppe6_xp (citizenid, xp, level) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE xp = ?, level = ?', {
            Player.PlayerData.citizenid, xp, level, xp, level
        })
    else
        Player.Functions.SetMetaData('gruppe6_xp', xp)
        Player.Functions.SetMetaData('gruppe6_level', level)
    end
    
    TriggerClientEvent('pf-jobs:gruppe6:updateXP', source, xp, level)
end

-- Helper: Generate random contract
local function GenerateContract(level)
    local tier = 1
    for t = #Config.Gruppe6.Tiers, 1, -1 do
        if level >= Config.Gruppe6.Tiers[t].minLevel then
            tier = t
            break
        end
    end
    
    local tierData = Config.Gruppe6.Tiers[tier]
    local bags = math.random(tierData.bags[1], tierData.bags[2])
    local payout = math.random(tierData.payout[1], tierData.payout[2])
    local vehicle = tierData.vehicles[math.random(#tierData.vehicles)]
    
    return {
        tier = tier,
        bags = bags,
        payout = payout,
        vehicle = vehicle,
        maxGroup = 4,
        contractType = 'Bank Delivery'
    }
end

-- SERVER CALLBACK: Get player state
QBCore.Functions.CreateCallback('pf-jobs:gruppe6:getState', function(source, cb)
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
        
        local _, level = GetPlayerXP(src)
        local contract = GenerateContract(level)
        
        -- FIXED: Only keep max 1 contract (not 3)
        activeContracts[src] = { contract }
        
        print('[Gruppe6 Server] Spawned 1 contract for player', src)
        
        TriggerClientEvent('pf-jobs:gruppe6:contracts', src, activeContracts[src])
        
        -- Schedule next
        local spawnTime = Config.Gruppe6.Debug and math.random(5000, 10000) or math.random(Config.Gruppe6.MinSpawnTime, Config.Gruppe6.MaxSpawnTime)
        contractTimers[src] = Citizen.SetTimeout(spawnTime, SpawnContract)
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
    
    local contractId = data.contractId
    local contract = activeContracts[src][contractId + 1]
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
        table.insert(locationBags, math.random(Config.Gruppe6.MoneyBagsPerLocationMin, Config.Gruppe6.MoneyBagsPerLocationMax))
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
RegisterNetEvent('pf-jobs:gruppe6:spawnVehicle', function(vehicleModel, plate, coords)
    local src = source
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
    
    local stashId = string.format('pf_gruppe6_pickup_%d_%d', locationIdx, pickupNum)
    
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
AddEventHandler('qb-inventory:server:SetInventoryData', function(src, fromInv, toInv)
    if Config.Gruppe6.ServerSideStash then return end
    -- fromInv/toInv are tables; we need identifiers
    local function getId(inv)
        if type(inv) == 'table' then
            return inv.name or inv.identifier or inv.stash or inv.id
        end
        return inv
    end
    local fromId = getId(fromInv)
    local toId = getId(toInv)
    local function isG6(id)
        return type(id) == 'string' and id:find('pf_gruppe6_pickup_') == 1
    end
    local targetId = nil
    if isG6(fromId) then targetId = fromId end
    if not targetId and isG6(toId) then targetId = toId end
    if not targetId then return end

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
end)

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
QBCore.Functions.CreateCallback('pf-jobs:gruppe6:checkBags', function(source, cb)
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
    if not contract then return end
    -- Chunked deposit: total to deposit equals collected bags (or proportional when early end)
    local totalCollected = contract.bagsTaken or 0
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

    -- Use bagsTaken ratio if available, fallback to pickups ratio
    local completed = contract.completedPickups or 0
    local total = contract.totalPickups or completed
    local percentage = 1.0
    if contract.totalBags and contract.totalBags > 0 then
        local taken = contract.bagsTaken or 0
        percentage = taken / contract.totalBags
    else
        if total > 0 then percentage = completed / total end
    end
    if percentage > 1 then percentage = 1 end
    if percentage < 0 then percentage = 0 end

    local maxCap = tierMax[tier] or fullPayout
    local payout = contract.earlyEnd and math.floor(maxCap * percentage) or fullPayout
    local xpAmount = math.floor(fullXpBase * percentage)
    if xpAmount < 1 then xpAmount = 0 end
    contract.payoutId = contract.payoutId or PFPayout.NewId()

    -- Get group info
    local leaderId = playerGroups[src]
    if not leaderId and groupSessions[src] then leaderId = src end
    local group = leaderId and groupSessions[leaderId]
    
    if group then
        local participants = { leaderId }
        for _, memberId in ipairs(group.members) do
            participants[#participants + 1] = memberId
        end

        local groupPayoutEach = math.floor(payout * 1.5)
        local groupXpEach = xpAmount

        -- Pay everyone first (one key per member); if any payment fails keep the contract
        -- so depositing again retries, and the keys stop anyone being paid twice
        local payFailed = false
        for _, participantId in ipairs(participants) do
            local participant = QBCore.Functions.GetPlayer(participantId)
            if participant then
                local paid, res = true, {}
                if groupPayoutEach > 0 then
                    paid, res = PFPayout.Pay(participant, 'bank', groupPayoutEach, {
                        key = ('pf-jobs:gruppe6:%s:%s'):format(contract.payoutId, participant.PlayerData.citizenid),
                        reason = 'gruppe6-group-contract',
                    })
                end
                if not paid then
                    payFailed = true
                elseif not res.duplicate then
                    AddXP(participantId, groupXpEach)
                    TriggerClientEvent('QBCore:Notify', participantId, string.format('Group contract complete! Earned $%d + %d XP', groupPayoutEach, groupXpEach), 'success')
                end
            end
        end
        if payFailed then return end

        for _, participantId in ipairs(participants) do
            playerActiveContract[participantId] = nil
            TriggerClientEvent('pf-jobs:gruppe6:activeContract', participantId, nil)
            TriggerClientEvent('pf-jobs:gruppe6:contracts', participantId, {})
        end

        print('[Gruppe6 Server] ✅ Group payout applied: 1.5x, equal rewards for all members')
    else
        -- Solo payout; on failure keep the contract so depositing again retries with the same key
        if payout > 0 then
            local paid = PFPayout.Pay(Player, 'bank', payout, {
                key = ('pf-jobs:gruppe6:%s:%s'):format(contract.payoutId, Player.PlayerData.citizenid),
                reason = 'gruppe6-contract',
            })
            if not paid then return end
        end
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
    local spawnTime = Config.Gruppe6.Debug and math.random(5000, 10000) or math.random(Config.Gruppe6.MinSpawnTime, Config.Gruppe6.MaxSpawnTime)
    if contractTimers[src] then
        Citizen.ClearTimeout(contractTimers[src])
    end
    contractTimers[src] = Citizen.SetTimeout(spawnTime, function()
        local _, level = GetPlayerXP(src)
        local newContract = GenerateContract(level)
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
    spawnLocks[src] = nil
    acceptCooldowns[src] = nil
    
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
                groupSessions[leaderId].payoutSplits[src] = nil
                break
            end
        end
    end
    playerGroups[src] = nil
end)

-- ===== GROUP MANAGEMENT SYSTEM =====

-- Helper: Format group data for client with player names
local function GetFormattedGroupData(leaderId)
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
    
    groupSessions[src] = {
        leader = src,
        members = {},
        payoutSplits = {
            [src] = 100  -- Leader starts with 100%, auto-rebalances when members join
        }
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
                    oldGroup.payoutSplits[src] = nil
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
    local totalMembers = #group.members + 1
    local splitPerPerson = math.floor(100 / totalMembers)
    local leftover = 100 - (splitPerPerson * totalMembers)
    group.payoutSplits[leaderId] = splitPerPerson + leftover
    for _, memberId in ipairs(group.members) do
        group.payoutSplits[memberId] = splitPerPerson
    end
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
    
    -- If already in a party, leave it first
    if playerGroups[src] then
        local oldLeaderId = playerGroups[src]
        local oldGroup = groupSessions[oldLeaderId]
        
        if oldGroup then
            -- Remove from old group
            for i, memberId in ipairs(oldGroup.members) do
                if memberId == src then
                    table.remove(oldGroup.members, i)
                    oldGroup.payoutSplits[src] = nil
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
    
    -- Auto-rebalance splits when new member joins
    local totalMembers = #group.members + 1  -- +1 for leader
    local splitPerPerson = math.floor(100 / totalMembers)
    local leftover = 100 - (splitPerPerson * totalMembers)
    
    -- Set leader split
    group.payoutSplits[leaderId] = splitPerPerson + leftover
    
    -- Set all member splits
    for _, memberId in ipairs(group.members) do
        group.payoutSplits[memberId] = splitPerPerson
    end
    
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
                group.payoutSplits[src] = nil
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
            group.payoutSplits[targetId] = nil
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

-- Update payout split with auto-rebalancing
RegisterNetEvent('pf-jobs:gruppe6:updateSplit', function(targetId, percentage)
    local src = source
    local group = groupSessions[src]
    
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the party leader can adjust splits', 'error')
        return
    end
    
    percentage = tonumber(percentage)
    if not percentage or percentage < 0 or percentage > 100 then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid percentage (0-100)', 'error')
        return
    end
    
    -- Verify target is leader or a member
    local isLeader = (targetId == src)
    local found = isLeader
    
    if not isLeader then
        for _, memberId in ipairs(group.members) do
            if memberId == targetId then
                found = true
                break
            end
        end
    end
    
    if not found then
        TriggerClientEvent('QBCore:Notify', src, 'Player not in your party', 'error')
        return
    end
    
    -- Normalize others proportionally so total remains 100
    -- 1) Clamp requested percentage between 0 and 100
    if percentage < 0 then percentage = 0 end
    if percentage > 100 then percentage = 100 end

    -- 2) Set target split
    group.payoutSplits[targetId] = percentage

    -- 3) Compute current sum of other splits
    local otherSum = 0
    for pid, split in pairs(group.payoutSplits) do
        if pid ~= targetId then otherSum = otherSum + (split or 0) end
    end

    local remaining = 100 - percentage
    if remaining < 0 then remaining = 0 end

    -- 4) If there are others, scale them proportionally to fit remaining
    if otherSum > 0 then
        local distributed = 0
        local lastPid = nil
        for pid, split in pairs(group.payoutSplits) do
            if pid ~= targetId then
                lastPid = pid
                local newSplit = math.floor((split or 0) * remaining / otherSum)
                group.payoutSplits[pid] = newSplit
                distributed = distributed + newSplit
            end
        end
        -- Distribute any rounding leftover to the last processed pid
        local leftover = remaining - distributed
        if leftover > 0 and lastPid ~= nil then
            group.payoutSplits[lastPid] = (group.payoutSplits[lastPid] or 0) + leftover
        end
    else
        -- No others yet: remaining is unused; keep target as requested
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'Splits updated and rebalanced to 100%', 'success')
    
    -- Update all group members
    local formattedData = GetFormattedGroupData(src)
    TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', src, formattedData)
    for _, memberId in ipairs(group.members) do
        TriggerClientEvent('pf-jobs:gruppe6:groupUpdate', memberId, formattedData)
    end
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
QBCore.Functions.CreateCallback('pf-jobs:gruppe6:getGroup', function(source, cb)
    local leaderId = playerGroups[source]
    if leaderId then
        cb(groupSessions[leaderId])
    elseif groupSessions[source] then
        cb(groupSessions[source])
    else
        cb(nil)
    end
end)

print('[Gruppe6] ✅ Server loaded successfully')

-- Removed: Storage now uses native vehicle trunk (qb-inventory handles automatically)