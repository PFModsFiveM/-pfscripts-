-- Garbage Job Server Logic
-- Isolated from Gruppe6

local QBCore = exports['pfm-core']:GetCoreObject()
local GarbageXP = {}
local PlayerCarrying = {}
local DumpsterCounts = {}
local ActiveGarbagePlayers = {}
local DepositedCount = {}
local SessionObjective = {}
local ObjectiveTarget = Config.Garbage.ObjectiveTarget
local ActiveVehicle = {} -- [src] = netId
local ActiveVehiclePlate = {} -- [src] = plate
-- Zone progression state
local SessionZones = {}       -- [src] = { {name,x,y,z}, ... } per-level unlocked zone points
local ActiveZoneIndex = {}     -- [src] = current zone index (1-based)
local ZoneDumpsterProgress = {} -- [src] = unique dumpsters cleared in current zone
local InteractedDumpsters = {} -- [src] = {canonicalKey = true} set of already-interacted dumpster keys
local GarbageRouteId = {}      -- [src] = id of the current run, shared by the whole crew; payout keys use it
local DB_READY = false
local GROUPS_PERSIST = true -- enable persistence to DB tables pf_garbage_groups + pf_garbage_group_members

-- Group system (same as Gruppe6)
local groupSessions = {} -- [leaderId] = { leader = src, members = {src1, src2}, payoutSplits = {[src1] = 25, [src2] = 25} }
local playerGroups = {} -- [src] = leaderId (quick lookup)
local groupDbIds = {} -- [leaderId] = db group id
local groupCodes = {} -- [leaderId] = code
local codeToLeader = {} -- [code] = leaderId

-- Vehicle spawn location (from config)
local garbageSpawn = Config.Garbage.VehicleSpawn
local garbageTruckModel = Config.Garbage.VehicleModel

-- Interactable props (from config)
local dumpsterProps = Config.Garbage.DumpsterProps
local binbagProps = Config.Garbage.BinbagProps

-- Forward declarations
local CalculateLevel, GetCitizenId, SaveXPToDB, LoadXPFromDB

-- Helper: Calculate level from XP (early definition)
CalculateLevel = function(xp)
    local level = 1
    for lvl = #Config.Garbage.LevelThresholds, 1, -1 do
        if xp >= Config.Garbage.LevelThresholds[lvl] then
            level = lvl
            break
        end
    end
    return level
end

local function BuildZonesForLevel(level)
    local zones = {}
    local cfg = Config.Garbage or {}
    local areaNames = (cfg.LevelAreaUnlocks and cfg.LevelAreaUnlocks[level]) or {}
    local areaMap = cfg.AreaZones or {}

    for _, areaName in ipairs(areaNames) do
        local area = areaMap[areaName]
        if area and area.points then
            for _, point in ipairs(area.points) do
                zones[#zones + 1] = {
                    name = areaName:gsub('^%l', string.upper),
                    x = point.x,
                    y = point.y,
                    z = point.z,
                }
            end
        end
    end

    if #zones == 0 then
        for areaName, area in pairs(areaMap) do
            if area and area.points then
                for _, point in ipairs(area.points) do
                    zones[#zones + 1] = {
                        name = areaName:gsub('^%l', string.upper),
                        x = point.x,
                        y = point.y,
                        z = point.z,
                    }
                end
            end
        end
    end

    return zones
end

-- Helper: Get citizen ID
GetCitizenId = function(src)
    local P = QBCore.Functions.GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

-- Helper: Get player name for notifications
local function GetPlayerName(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return 'Player' end
    return Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
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

-- Helper: Format group data for client
local function GetFormattedGroupData(leaderId)
    local group = groupSessions[leaderId]
    if not group then return nil end
    
    -- Format members with id + name for UI rendering
    local membersFormatted = {}
    for _, msrc in ipairs(group.members or {}) do
        membersFormatted[#membersFormatted+1] = {
            id = msrc,
            name = GetPlayerName(msrc)
        }
    end
    
    return {
        leader = leaderId,
        leaderName = GetPlayerName(leaderId),
        members = membersFormatted,
        payoutSplits = group.payoutSplits,
        groupId = groupDbIds[leaderId],
        groupCode = groupCodes[leaderId]
    }
end

RegisterNetEvent('pf-jobs:garbage:startJob', function()
    local src = source
    print('[pf-jobs][garbage] Server received startJob from source: '..tostring(src))
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        print('[pf-jobs][garbage] Failed to get player for src '..tostring(src))
        return
    end
    local leaderId = playerGroups[src]
    if not leaderId and groupSessions[src] then leaderId = src end
    if leaderId and leaderId ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the group leader can start the garbage job', 'error')
        return
    end

    local group = groupSessions[src]
    local participants = { src }
    if group then
        for _, memberId in ipairs(group.members) do
            participants[#participants + 1] = memberId
        end
    end

    print('[pf-jobs][garbage] Player found, starting job for: '..Player.PlayerData.citizenid)
    LoadXPFromDB(src)
    local level = CalculateLevel(GarbageXP[src] or 0)
    local routeId = PFPayout.NewId()

    for _, participantId in ipairs(participants) do
        ActiveGarbagePlayers[participantId] = true
        GarbageRouteId[participantId] = routeId
        PlayerCarrying[participantId] = false
        DepositedCount[participantId] = 0
        SessionObjective[participantId] = 0
        SessionZones[participantId] = BuildZonesForLevel(level)
        ActiveZoneIndex[participantId] = 1
        ZoneDumpsterProgress[participantId] = {}
        InteractedDumpsters[participantId] = {}
    end
    -- Server-side vehicle spawn (match Gruppe6 key logic)
    local model = garbageTruckModel
    local hash = GetHashKey(model)
    -- Server environment: skip client-only streaming checks (IsModelInCdimage/RequestModel)
    local veh = CreateVehicle(hash, garbageSpawn.x, garbageSpawn.y, garbageSpawn.z, garbageSpawn.w, true, true)
    while not DoesEntityExist(veh) do Wait(10) end
    -- Removed SetVehicleOnGroundProperly (client-only native in this environment)
    SetEntityHeading(veh, garbageSpawn.w)
    local plate = ('GARB%04d'):format(math.random(0,9999))
    SetVehicleNumberPlateText(veh, plate)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    for _, participantId in ipairs(participants) do
        ActiveVehicle[participantId] = netId
        ActiveVehiclePlate[participantId] = plate
    end
    -- Removed SetNetworkIdCanMigrate (nil on this server build); network ID will replicate by default
    -- Assign keys server-side (same as Gruppe6 logic)
    for _, participantId in ipairs(participants) do
        TriggerClientEvent('vehiclekeys:client:SetOwner', participantId, plate)
        TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', participantId, plate)
        TriggerClientEvent('pf-jobs:garbage:vehicleSpawned', participantId, netId, plate, garbageSpawn)
        TriggerClientEvent('pf-jobs:client:updateScoreboard', participantId, 'Garbage Crew', 'Truck ready - Proceed to search zone')

        local z = SessionZones[participantId] and SessionZones[participantId][ActiveZoneIndex[participantId]]
        if z then
            TriggerClientEvent('pf-jobs:garbage:setActiveZone', participantId, {
                name = z.name,
                center = vector3(z.x, z.y, z.z),
                radius = Config.Garbage.ZoneRadius,
                target = Config.Garbage.DumpstersPerZone
            })
        end
    end
end)

RegisterNetEvent('pf-jobs:garbage:updateXP', function(delta)
    local src = source
    GarbageXP[src] = (GarbageXP[src] or 0) + (tonumber(delta) or 0)
    local xp = GarbageXP[src]
    local level = CalculateLevel(xp)
    TriggerClientEvent('pf-jobs:garbage:updateXP', src, xp, level)
    SaveXPToDB(src)
end)

-- Request a bag from an entity (dumpster or loose bag)
RegisterNetEvent('pf-jobs:garbage:requestBag', function(key, isLoose)
    local src = source
    if PlayerCarrying[src] then return end

    -- Enforce zone: key must be within active zone
    local zoneIdx = ActiveZoneIndex[src]
    local zone = zoneIdx and SessionZones[src] and SessionZones[src][zoneIdx]
    local inZone = true
    if zone and type(key) == 'string' and string.find(key, ':') then
        local parts = {}
        for part in string.gmatch(key, "[^:]+") do parts[#parts + 1] = part end
        if #parts == 4 then
            local kx, ky, kz = tonumber(parts[2]) or 0.0, tonumber(parts[3]) or 0.0, tonumber(parts[4]) or 0.0
            local dist = #(vector3(kx, ky, kz) - vector3(zone.x, zone.y, zone.z))
            inZone = dist <= (Config.Garbage.ZoneRadius or 1609.34)
        end
    end
    if not inZone then
        TriggerClientEvent('QBCore:Notify', src, 'This dumpster is outside the active zone', 'error')
        return
    end

    if isLoose then
        -- Loose bag: single use
        PlayerCarrying[src] = true
        TriggerClientEvent('pf-jobs:garbage:grantBag', src, key, true)
        return
    end

    -- Dumpster: normalize key to avoid reset when moved (prefer existing nearby same-model key)
    local primaryKey = key
    if type(key) == 'string' and string.find(key, ':') then
        local function parseKey(k)
            local t = {}
            for part in string.gmatch(k, "[^:]+") do t[#t + 1] = part end
            if #t == 4 then
                return tonumber(t[1]), vector3(tonumber(t[2]) or 0.0, tonumber(t[3]) or 0.0, tonumber(t[4]) or 0.0)
            end
            return nil, nil
        end

        local kModel, kPos = parseKey(key)
        if kModel and kPos then
            for existingKey, _ in pairs(DumpsterCounts) do
                if type(existingKey) == 'string' and string.find(existingKey, ':') then
                    local eModel, ePos = parseKey(existingKey)
                    if eModel and ePos and eModel == kModel and #(ePos - kPos) < 8.0 then
                        primaryKey = existingKey
                        break
                    end
                end
            end
        end
    end

    -- Prevent re-looting from already-depleted dumpsters (canonical key)
    InteractedDumpsters[src] = InteractedDumpsters[src] or {}
    if InteractedDumpsters[src][primaryKey] then
        TriggerClientEvent('QBCore:Notify', src, 'This dumpster has already been emptied', 'error')
        return
    end

    -- Initialize count if unseen (from config)
    local remaining = DumpsterCounts[primaryKey]
    if not remaining then
        remaining = math.random(Config.Garbage.DumpsterBagsMin, Config.Garbage.DumpsterBagsMax)
        DumpsterCounts[primaryKey] = remaining
        remaining = DumpsterCounts[primaryKey]
    end

    if remaining <= 0 then
        InteractedDumpsters[src][primaryKey] = true
        TriggerClientEvent('QBCore:Notify', src, 'This dumpster is empty', 'error')
        return
    end

    DumpsterCounts[primaryKey] = remaining - 1
    local newRemaining = DumpsterCounts[primaryKey]
    PlayerCarrying[src] = true

    TriggerClientEvent('pf-jobs:garbage:grantBag', src, primaryKey, false, newRemaining)

    -- Broadcast remaining to ALL active players including requester
    for ply, _ in pairs(ActiveGarbagePlayers) do
        TriggerClientEvent('pf-jobs:garbage:dumpsterRemaining', ply, primaryKey, newRemaining)
    end

    -- Track unique dumpster clears towards zone objective
    if newRemaining == 0 then
        local leaderId = playerGroups[src]
        if not leaderId and groupSessions[src] then leaderId = src end
        local group = leaderId and groupSessions[leaderId]

        local participants = { src }
        if group then
            participants = { leaderId }
            for _, memberId in ipairs(group.members) do
                participants[#participants + 1] = memberId
            end
        end

        for _, participantId in ipairs(participants) do
            InteractedDumpsters[participantId] = InteractedDumpsters[participantId] or {}
            InteractedDumpsters[participantId][primaryKey] = true

            ZoneDumpsterProgress[participantId] = ZoneDumpsterProgress[participantId] or {}
            if not ZoneDumpsterProgress[participantId][primaryKey] then
                ZoneDumpsterProgress[participantId][primaryKey] = true
            end

            local totalCleared = 0
            for _k, _v in pairs(ZoneDumpsterProgress[participantId]) do totalCleared = totalCleared + 1 end
            local target = Config.Garbage.DumpstersPerZone or 20

            TriggerClientEvent('pf-jobs:client:updateScoreboard', participantId, 'Garbage Crew', ('Dumpsters cleared: %d/%d'):format(totalCleared, target))

            if totalCleared >= target then
                ActiveZoneIndex[participantId] = (ActiveZoneIndex[participantId] or 1) + 1
                ZoneDumpsterProgress[participantId] = {}
                local nextZone = SessionZones[participantId] and SessionZones[participantId][ActiveZoneIndex[participantId]]
                if nextZone then
                    TriggerClientEvent('QBCore:Notify', participantId, 'Zone objective complete! Moving to next zone.', 'success')
                    TriggerClientEvent('pf-jobs:garbage:setActiveZone', participantId, {
                        name = nextZone.name,
                        center = vector3(nextZone.x, nextZone.y, nextZone.z),
                        radius = Config.Garbage.ZoneRadius,
                        target = Config.Garbage.DumpstersPerZone
                    })
                    TriggerClientEvent('pf-jobs:client:updateScoreboard', participantId, 'Garbage Crew', ('Proceed to: %s'):format(nextZone.name))
                else
                    TriggerClientEvent('QBCore:Notify', participantId, 'All zones complete! Return the truck.', 'success')
                    TriggerClientEvent('pf-jobs:client:updateScoreboard', participantId, 'Garbage Crew', 'All zones complete - Return truck')
                end
            end
        end
    end
end)

RegisterNetEvent('pf-jobs:garbage:setCarrying', function(flag)
    local src = source
    PlayerCarrying[src] = flag and true or false
    TriggerClientEvent('pf-jobs:garbage:carrying', src, PlayerCarrying[src])
end)

-- Deposit carried bag into truck
RegisterNetEvent('pf-jobs:garbage:depositBag', function()
    local src = source
    if not PlayerCarrying[src] then
        TriggerClientEvent('QBCore:Notify', src, 'You are not carrying a bag', 'error')
        return
    end
    -- Level-based deposit cap (from config)
    local xpPre = GarbageXP[src] or 0
    local levelPre = CalculateLevel(xpPre)
    local cap = Config.Garbage.DepositCap[levelPre] or Config.Garbage.DepositCap[2] or 9999
    DepositedCount[src] = (DepositedCount[src] or 0)
    if DepositedCount[src] >= cap then
        TriggerClientEvent('QBCore:Notify', src, ('Deposit cap reached (%d/%d)'):format(DepositedCount[src], cap), 'error')
        return
    end
    local leaderId = playerGroups[src]
    if not leaderId and groupSessions[src] then leaderId = src end
    local group = leaderId and groupSessions[leaderId]

    local participants = { src }
    if group then
        participants = { leaderId }
        for _, memberId in ipairs(group.members) do
            participants[#participants + 1] = memberId
        end
    end

    local srcXp = 0
    local srcLevel = 1

    for _, participantId in ipairs(participants) do
        GarbageXP[participantId] = (GarbageXP[participantId] or 0) + Config.Garbage.XPPerBag
        local xp = GarbageXP[participantId]
        local level = CalculateLevel(xp)
        DepositedCount[participantId] = (DepositedCount[participantId] or 0) + 1
        SessionObjective[participantId] = (SessionObjective[participantId] or 0) + 1

        TriggerClientEvent('pf-jobs:garbage:updateXP', participantId, xp, level)
        TriggerClientEvent('pf-jobs:garbage:updateDeposited', participantId, DepositedCount[participantId], cap)
        SaveXPToDB(participantId)

        local objectiveText = ('Collected %d/%d bags'):format(SessionObjective[participantId], ObjectiveTarget)
        if SessionObjective[participantId] >= ObjectiveTarget then
            objectiveText = 'Objective complete! Return truck to depot'
        end
        TriggerClientEvent('pf-jobs:client:updateScoreboard', participantId, 'Garbage Crew', objectiveText)

        if participantId == src then
            srcXp = xp
            srcLevel = level
        end
    end
    
    -- Clear carrying state AFTER all calculations
    PlayerCarrying[src] = false
    
    -- Send all updates to source client
    TriggerClientEvent('pf-jobs:garbage:carrying', src, false)
    TriggerClientEvent('pf-jobs:garbage:updateXP', src, srcXp, srcLevel)
    TriggerClientEvent('QBCore:Notify', src, ('Bag deposited. +%d XP'):format(Config.Garbage.XPPerBag), 'success')
end)

-- Depot return: end job and award money by tier
local depotCoords = vector3(-327.06, -1524.36, 27.54)
RegisterNetEvent('pf-jobs:garbage:returnTruck', function()
    local src = source
    if not ActiveGarbagePlayers[src] then return end
    local xp = GarbageXP[src] or 0
    local level = CalculateLevel(xp)
    local tierPay = Config.Garbage.PayoutPerBag[level] or Config.Garbage.PayoutPerBag[1] or 20
    local totalBags = math.min(SessionObjective[src] or 0, ObjectiveTarget)
    local totalPayout = tierPay * totalBags
    local routeId = GarbageRouteId[src]
    if not routeId then return end
    local payFailed = false

    if totalPayout > 0 then
        -- Check if player is in a group
        local leaderId = playerGroups[src]
        if not leaderId and groupSessions[src] then leaderId = src end
        local group = leaderId and groupSessions[leaderId]
        
        if group and Config.Garbage.Groups.SharePayouts then
            local participants = { leaderId }
            for _, memberId in ipairs(group.members) do
                participants[#participants + 1] = memberId
            end

            local payoutEach = math.floor(totalPayout * 1.5)
            for _, participantId in ipairs(participants) do
                local participant = QBCore.Functions.GetPlayer(participantId)
                if participant then
                    -- One key per crew member, so a retry only pays whoever was missed
                    local paid = PFPayout.Pay(participant, 'cash', payoutEach, {
                        key = ('pf-jobs:garbage:%s:%s'):format(routeId, participant.PlayerData.citizenid),
                        reason = 'garbage-group-job-payout',
                    })
                    if paid then
                        TriggerClientEvent('QBCore:Notify', participantId, ('Group return complete. Earned $%d (1.5x) for %d bags.'):format(payoutEach, totalBags), 'success')
                    else
                        payFailed = true
                    end
                end
            end
        else
            -- Solo payout
            local Player = QBCore.Functions.GetPlayer(src)
            if Player then
                local paid = PFPayout.Pay(Player, 'cash', totalPayout, {
                    key = ('pf-jobs:garbage:%s:%s'):format(routeId, Player.PlayerData.citizenid),
                    reason = 'garbage-job-payout',
                })
                if paid then
                    TriggerClientEvent('QBCore:Notify', src, ('Returned truck. Earned $%d for %d bags.'):format(totalPayout, totalBags), 'success')
                else
                    payFailed = true
                end
            end
        end
        -- Keep the session (and its bag count) so returning again retries with the same keys
        if payFailed then return end
    else
        TriggerClientEvent('QBCore:Notify', src, 'Returned truck. No payout.', 'error')
    end
    
    -- Client handles vehicle deletion via QBCore.Functions.DeleteVehicle
    -- No server-side deletion needed
    
    local leaderId = playerGroups[src]
    if not leaderId and groupSessions[src] then leaderId = src end
    local group = leaderId and groupSessions[leaderId]

    local participants = { src }
    if group then
        participants = { leaderId }
        for _, memberId in ipairs(group.members) do
            participants[#participants + 1] = memberId
        end
    end

    for _, participantId in ipairs(participants) do
        ActiveGarbagePlayers[participantId] = nil
        GarbageRouteId[participantId] = nil
        PlayerCarrying[participantId] = nil
        DepositedCount[participantId] = nil
        SessionObjective[participantId] = nil
        SessionZones[participantId] = nil
        ActiveZoneIndex[participantId] = nil
        ZoneDumpsterProgress[participantId] = nil
        InteractedDumpsters[participantId] = nil
        ActiveVehicle[participantId] = nil
        ActiveVehiclePlate[participantId] = nil
        TriggerClientEvent('pf-jobs:garbage:sessionEnded', participantId)
    end
end)

-- Vehicle returned cleanup (matches Gruppe6 pattern)
RegisterNetEvent('pf-jobs:garbage:vehicleReturned', function()
    local src = source
    
    -- Clear active contract
    ActiveGarbagePlayers[src] = nil
    PlayerCarrying[src] = nil
    DepositedCount[src] = nil
    SessionObjective[src] = nil
    SessionZones[src] = nil
    ActiveZoneIndex[src] = nil
    ZoneDumpsterProgress[src] = nil
    InteractedDumpsters[src] = nil
    ActiveVehicle[src] = nil
    ActiveVehiclePlate[src] = nil
end)

QBCore.Functions.CreateCallback('pf-jobs:garbage:getInit', function(source, cb)
    local src = source
    LoadXPFromDB(src)
    local xp = GarbageXP[src] or 0
    local level = CalculateLevel(xp)
    local cap = Config.Garbage.DepositCap[level] or Config.Garbage.DepositCap[2] or 9999
    
    -- Get current group data
    local currentGroup = nil
    local leaderId = playerGroups[src]
    if leaderId and groupSessions[leaderId] then
        currentGroup = GetFormattedGroupData(leaderId)
    elseif groupSessions[src] then
        currentGroup = GetFormattedGroupData(src)
    end
    
    cb({ 
        playerId = src,
        xp = xp, 
        level = level, 
        carrying = PlayerCarrying[src] or false, 
        deposited = DepositedCount[src] or 0, 
        cap = cap,
        currentGroup = currentGroup
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    SaveXPToDB(src)
    ActiveGarbagePlayers[src] = nil
    PlayerCarrying[src] = nil
    GarbageXP[src] = nil
    DepositedCount[src] = nil
    SessionObjective[src] = nil
    SessionZones[src] = nil
    ActiveZoneIndex[src] = nil
    ZoneDumpsterProgress[src] = nil
    InteractedDumpsters[src] = nil
    ActiveVehicle[src] = nil
    ActiveVehiclePlate[src] = nil
    
    -- Clean up group if leader leaves
    if groupSessions[src] then
        for _, memberId in ipairs(groupSessions[src].members) do
            playerGroups[memberId] = nil
            TriggerClientEvent('QBCore:Notify', memberId, 'Party disbanded - leader left', 'error')
            TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, nil)
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
                
                TriggerClientEvent('QBCore:Notify', leaderId, GetPlayerName(src) .. ' disconnected', 'error')
                
                -- Update remaining members
                local formattedData = GetFormattedGroupData(leaderId)
                TriggerClientEvent('pf-jobs:garbage:groupUpdate', leaderId, formattedData)
                for _, mid in ipairs(groupSessions[leaderId].members) do
                    TriggerClientEvent('pf-jobs:garbage:groupUpdate', mid, formattedData)
                end
                break
            end
        end
        playerGroups[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ActiveGarbagePlayers = {}
    PlayerCarrying = {}
    DepositedCount = {}
    SessionObjective = {}
    SessionZones = {}
    ActiveZoneIndex = {}
    ZoneDumpsterProgress = {}
    InteractedDumpsters = {}
    ActiveVehicle = {}
    ActiveVehiclePlate = {}
end)

-- =========================
-- DB: XP Persistence (oxmysql)
-- =========================

LoadXPFromDB = function(src)
    if GarbageXP[src] ~= nil then return end
    local cid = GetCitizenId(src)
    if not cid then GarbageXP[src] = 0 return end
    if not DB_READY or not Config.Garbage.UseDatabase then GarbageXP[src] = 0 return end
    
    local success, rows = pcall(function()
        return MySQL.query.await('SELECT xp, level FROM pf_garbage_xp WHERE citizenid = ?', { cid })
    end)
    
    if success and rows and rows[1] then
        GarbageXP[src] = tonumber(rows[1].xp) or 0
    else
        pcall(function()
            MySQL.execute('INSERT INTO pf_garbage_xp (citizenid, xp, level) VALUES (?, ?, ?)', { cid, 0, 1 })
        end)
        GarbageXP[src] = 0
    end
end

SaveXPToDB = function(src)
    local cid = GetCitizenId(src)
    if not cid then return end
    if not DB_READY or not Config.Garbage.UseDatabase then return end
    local xp = tonumber(GarbageXP[src] or 0) or 0
    local level = CalculateLevel(xp)
    pcall(function()
        MySQL.execute('INSERT INTO pf_garbage_xp (citizenid, xp, level) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE xp = VALUES(xp), level = VALUES(level), updated_at = CURRENT_TIMESTAMP', { cid, xp, level })
    end)
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    
    -- Test DB connection first
    local success = pcall(function()
        MySQL.scalar.await('SELECT 1', {})
    end)
    
    if not success then
        print('^1[pf-jobs] WARNING: Database connection failed. Garbage groups will not persist. Check your MySQL connection.^0')
        DB_READY = false
        return
    end
    
    DB_READY = true
    print('^2[pf-jobs] Database connected. Creating garbage tables...^0')
    
    -- Create tables if missing, one after another: the members table references the groups
    -- table, so it must not be created first (async execute raced on a fresh database)
    pcall(function()
        MySQL.query.await([[ 
            CREATE TABLE IF NOT EXISTS pf_garbage_xp (
                citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
                xp INT NOT NULL DEFAULT 0,
                level INT NOT NULL DEFAULT 1,
                updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)
    
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pf_garbage_groups (
                id INT(11) NOT NULL AUTO_INCREMENT,
                host_citizenid VARCHAR(64) NOT NULL,
                open TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_host (host_citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)
    
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pf_garbage_group_members (
                group_id INT(11) NOT NULL,
                citizenid VARCHAR(64) NOT NULL,
                display_name VARCHAR(64) NOT NULL,
                cut_percent INT(11) NOT NULL DEFAULT 0,
                PRIMARY KEY (group_id, citizenid),
                KEY idx_member (citizenid),
                KEY idx_group (group_id),
                CONSTRAINT fk_garbage_group_members_group FOREIGN KEY (group_id) REFERENCES pf_garbage_groups(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)
    
    print('^2[pf-jobs] Garbage tables ready.^0')
end)

-- =========================
-- GROUP SYSTEM (Party Mechanics)
-- =========================

-- Create group
RegisterNetEvent('pf-jobs:garbage:createGroup', function()
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
    
    if not playerGroups[src] then
        playerGroups[src] = src
    end

    -- Persist to DB
    if GROUPS_PERSIST and DB_READY and Config.Garbage.UseDatabase then
        local cidLeader = GetCitizenId(src)
        if cidLeader then
            local success, insertId = pcall(function()
                return MySQL.insert.await('INSERT INTO pf_garbage_groups (host_citizenid, open) VALUES (?, ?)', { cidLeader, 0 })
            end)
            if success and insertId then
                groupDbIds[src] = insertId
                -- Add leader as member with current split
                pcall(function()
                    MySQL.execute('INSERT INTO pf_garbage_group_members (group_id, citizenid, display_name, cut_percent) VALUES (?, ?, ?, ?)', {
                        insertId, cidLeader, GetPlayerName(src), 100
                    })
                end)
            end
        end
    end

    TriggerClientEvent('QBCore:Notify', src, ('Party created! Group code: %s'):format(code), 'success')
    TriggerClientEvent('pf-jobs:garbage:groupUpdate', src, GetFormattedGroupData(src))
end)

RegisterNetEvent('pf-jobs:garbage:joinGroupByCode', function(code)
    local src = source
    local normalized = tostring(code or ''):upper()
    local leaderId = codeToLeader[normalized]

    if not leaderId or not groupSessions[leaderId] then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid or expired group code', 'error')
        return
    end

    if leaderId == src then
        TriggerClientEvent('QBCore:Notify', src, 'You are already this party leader', 'error')
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
            TriggerClientEvent('pf-jobs:garbage:groupUpdate', oldLeaderId, oldFormattedData)
            for _, memberId in ipairs(oldGroup.members) do
                TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, oldFormattedData)
            end
        end
        playerGroups[src] = nil
    end

    local group = groupSessions[leaderId]
    if not group then
        TriggerClientEvent('QBCore:Notify', src, 'Party no longer exists', 'error')
        return
    end

    if #group.members >= Config.Garbage.Groups.MaxMembers - 1 then
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
    TriggerClientEvent('pf-jobs:garbage:groupUpdate', leaderId, formattedData)
    for _, memberId in ipairs(group.members) do
        TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, formattedData)
    end
end)

-- Invite player
RegisterNetEvent('pf-jobs:garbage:invitePlayer', function(targetId)
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
    
    if #group.members >= Config.Garbage.Groups.MaxMembers - 1 then
        TriggerClientEvent('QBCore:Notify', src, 'Party is full', 'error')
        return
    end
    
    local LeaderPlayer = QBCore.Functions.GetPlayer(src)
    local leaderName = LeaderPlayer.PlayerData.charinfo.firstname .. ' ' .. LeaderPlayer.PlayerData.charinfo.lastname
    TriggerClientEvent('pf-jobs:garbage:receiveInvite', targetId, leaderName, src)
    TriggerClientEvent('QBCore:Notify', src, string.format('Invite sent to %s (ID: %d)', TargetPlayer.PlayerData.charinfo.firstname .. ' ' .. TargetPlayer.PlayerData.charinfo.lastname, targetId), 'success')
end)

-- Accept invite
RegisterNetEvent('pf-jobs:garbage:acceptInvite', function(leaderId)
    local src = source
    
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
            
            TriggerClientEvent('QBCore:Notify', oldLeaderId, string.format('%s left to join another party', GetPlayerName(src)), 'error')
            
            local oldFormattedData = GetFormattedGroupData(oldLeaderId)
            TriggerClientEvent('pf-jobs:garbage:groupUpdate', oldLeaderId, oldFormattedData)
            for _, memberId in ipairs(oldGroup.members) do
                TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, oldFormattedData)
            end
        end
        
        playerGroups[src] = nil
    end
    
    local group = groupSessions[leaderId]
    if not group then
        TriggerClientEvent('QBCore:Notify', src, 'Party no longer exists', 'error')
        return
    end
    
    if #group.members >= Config.Garbage.Groups.MaxMembers - 1 then
        TriggerClientEvent('QBCore:Notify', src, 'Party is full', 'error')
        return
    end
    
    table.insert(group.members, src)
    
    -- Auto-rebalance splits
    local totalMembers = #group.members + 1
    local splitPerPerson = math.floor(100 / totalMembers)
    local leftover = 100 - (splitPerPerson * totalMembers)
    
    group.payoutSplits[leaderId] = splitPerPerson + leftover
    for _, memberId in ipairs(group.members) do
        group.payoutSplits[memberId] = splitPerPerson
    end
    
    playerGroups[src] = leaderId

    -- Persist member add
    if GROUPS_PERSIST and DB_READY and Config.Garbage.UseDatabase then
        local gid = groupDbIds[leaderId]
        local cid = GetCitizenId(src)
        if gid and cid then
            -- Leader receives split already set above; compute member split
            local split = group.payoutSplits[src] or 0
            MySQL.execute('INSERT INTO pf_garbage_group_members (group_id, citizenid, display_name, cut_percent) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), cut_percent = VALUES(cut_percent)', {
                gid, cid, GetPlayerName(src), split
            })
        end
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'Joined party!', 'success')
    TriggerClientEvent('QBCore:Notify', leaderId, string.format('%s joined the party', GetPlayerName(src)), 'success')
    
    local formattedData = GetFormattedGroupData(leaderId)
    TriggerClientEvent('pf-jobs:garbage:groupUpdate', leaderId, formattedData)
    for _, memberId in ipairs(group.members) do
        TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, formattedData)
    end
end)

-- Decline invite
RegisterNetEvent('pf-jobs:garbage:declineInvite', function(leaderId)
    local src = source
    TriggerClientEvent('QBCore:Notify', leaderId, GetPlayerName(src) .. ' declined the invite', 'error')
end)

-- Leave group
RegisterNetEvent('pf-jobs:garbage:leaveGroup', function()
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
        -- Persist removal
        if GROUPS_PERSIST and DB_READY and Config.Garbage.UseDatabase then
            local gid = groupDbIds[leaderId]
            local cid = GetCitizenId(src)
            if gid and cid then
                MySQL.execute('DELETE FROM pf_garbage_group_members WHERE group_id = ? AND citizenid = ?', { gid, cid })
            end
        end
        
        TriggerClientEvent('QBCore:Notify', leaderId, string.format('%s left the party', GetPlayerName(src)), 'error')
        
        local formattedData = GetFormattedGroupData(leaderId)
        TriggerClientEvent('pf-jobs:garbage:groupUpdate', leaderId, formattedData)
        for _, memberId in ipairs(group.members) do
            TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, formattedData)
        end
    end
    
    playerGroups[src] = nil
    TriggerClientEvent('QBCore:Notify', src, 'Left the party', 'success')
    TriggerClientEvent('pf-jobs:garbage:groupUpdate', src, nil)
end)

-- Kick member
RegisterNetEvent('pf-jobs:garbage:kickMember', function(targetId)
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
            -- Persist removal
            if GROUPS_PERSIST and DB_READY and Config.Garbage.UseDatabase then
                local gid = groupDbIds[src]
                local cid = GetCitizenId(targetId)
                if gid and cid then
                    MySQL.execute('DELETE FROM pf_garbage_group_members WHERE group_id = ? AND citizenid = ?', { gid, cid })
                end
            end
            
            TriggerClientEvent('QBCore:Notify', targetId, 'You were kicked from the party', 'error')
            TriggerClientEvent('pf-jobs:garbage:groupUpdate', targetId, nil)
            TriggerClientEvent('QBCore:Notify', src, string.format('Kicked %s from the party', GetPlayerName(targetId)), 'success')
            
            local formattedData = GetFormattedGroupData(src)
            TriggerClientEvent('pf-jobs:garbage:groupUpdate', src, formattedData)
            for _, memberId in ipairs(group.members) do
                TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, formattedData)
            end
            return
        end
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'Player not in your party', 'error')
end)

-- Update payout split
RegisterNetEvent('pf-jobs:garbage:updateSplit', function(targetId, percentage)
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
        TriggerClientEvent('QBCore:Notify', src, 'Player not in party', 'error')
        return
    end
    
    -- Apply precise 100% logic: target gets `percentage`, leader gets remaining, others set to 0
    group.payoutSplits[targetId] = percentage
    for _, memberId in ipairs(group.members) do
        if memberId ~= targetId then
            group.payoutSplits[memberId] = 0
        end
    end
    group.payoutSplits[src] = math.max(0, 100 - percentage)

    -- Persist splits for all members
    if GROUPS_PERSIST and DB_READY and Config.Garbage.UseDatabase then
        local gid = groupDbIds[src]
        if gid then
            -- Leader
            local leaderCid = GetCitizenId(src)
            if leaderCid then
                MySQL.execute('INSERT INTO pf_garbage_group_members (group_id, citizenid, display_name, cut_percent) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE cut_percent = VALUES(cut_percent), display_name = VALUES(display_name)', {
                    gid, leaderCid, GetPlayerName(src), group.payoutSplits[src]
                })
            end
            -- Target
            local targetCid = GetCitizenId(targetId)
            if targetCid then
                MySQL.execute('INSERT INTO pf_garbage_group_members (group_id, citizenid, display_name, cut_percent) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE cut_percent = VALUES(cut_percent), display_name = VALUES(display_name)', {
                    gid, targetCid, GetPlayerName(targetId), group.payoutSplits[targetId]
                })
            end
            -- Others
            for _, memberId in ipairs(group.members) do
                local ocid = GetCitizenId(memberId)
                if ocid then
                    MySQL.execute('INSERT INTO pf_garbage_group_members (group_id, citizenid, display_name, cut_percent) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE cut_percent = VALUES(cut_percent), display_name = VALUES(display_name)', {
                        gid, ocid, GetPlayerName(memberId), group.payoutSplits[memberId]
                    })
                end
            end
        end
    end
    
    local formattedData = GetFormattedGroupData(src)
    TriggerClientEvent('pf-jobs:garbage:groupUpdate', src, formattedData)
    for _, memberId in ipairs(group.members) do
        TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, formattedData)
    end
    
    TriggerClientEvent('QBCore:Notify', src, string.format('Updated %s split to %d%%', GetPlayerName(targetId), percentage), 'success')
end)

-- Get group state callback
QBCore.Functions.CreateCallback('pf-jobs:garbage:getGroupState', function(source, cb)
    local leaderId = playerGroups[source]
    if leaderId then
        cb(GetFormattedGroupData(leaderId))
    elseif groupSessions[source] then
        cb(GetFormattedGroupData(source))
    else
        cb(nil)
    end
end)

-- Disband group (leader only)
RegisterNetEvent('pf-jobs:garbage:disbandGroup', function()
    local src = source
    local group = groupSessions[src]
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the leader can disband', 'error')
        return
    end
    -- Persist delete
    if GROUPS_PERSIST and DB_READY and Config.Garbage.UseDatabase then
        local gid = groupDbIds[src]
        if gid then
            MySQL.execute('DELETE FROM pf_garbage_group_members WHERE group_id = ?', { gid })
            MySQL.execute('DELETE FROM pf_garbage_groups WHERE id = ?', { gid })
        end
    end
    -- Notify and cleanup
    for _, memberId in ipairs(group.members) do
        playerGroups[memberId] = nil
        TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, nil)
        TriggerClientEvent('QBCore:Notify', memberId, 'Party disbanded', 'error')
    end
    local code = groupCodes[src]
    if code then
        codeToLeader[code] = nil
        groupCodes[src] = nil
    end
    groupSessions[src] = nil
    groupDbIds[src] = nil
    playerGroups[src] = nil
    TriggerClientEvent('pf-jobs:garbage:groupUpdate', src, nil)
    TriggerClientEvent('QBCore:Notify', src, 'Party disbanded', 'success')
end)

-- expose module values if required (not used directly)
return {
    GarbageXP = GarbageXP,
    groupSessions = groupSessions,
    SessionObjective = SessionObjective,
    ObjectiveTarget = ObjectiveTarget,
    garbageSpawn = garbageSpawn,
    garbageTruckModel = garbageTruckModel,
    dumpsterProps = dumpsterProps,
    binbagProps = binbagProps
}
