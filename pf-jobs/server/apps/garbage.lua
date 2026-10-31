-- Garbage Job Server Logic
-- Isolated from Gruppe6

local QBCore = exports['pfm-core']:GetCoreObject()
-- Callbacks go through PFJobsCallback (server/devices_capture.lua) so the tablet and computer apps
-- (server/devices.lua) reuse them; loaded on its own, this file registers them directly.
local CreateCallback = PFJobsCallback or QBCore.Functions.CreateCallback
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
local pendingInvites = {} -- [targetSrc] = { [leaderSrc] = true }
local LooseBagsTaken = {}  -- [key] = os.time() a loose bag there was picked up
local PayoutPlans = {}     -- [routeId] = the crew's shares, fixed at the first payout attempt

PFJobsGarbage = PFJobsGarbage or {}

-- Where things must be for the server to accept them. The client pulls a bag within 2.5 m of the
-- dumpster and throws it in within 3 m of the truck's rear.
local BAG_RANGE = 8.0
local TRUCK_RANGE = 12.0
local DEPOT_RANGE = 30.0
local LOOSE_BAG_RESPAWN = 30 * 60

local function playerCoords(src) return GetEntityCoords(GetPlayerPed(src)) end

-- Bag keys are 'net:<netId>' or '<model>:<x>:<y>:<z>' (see GetEntityKeyForDumpster); the bag must be
-- next to the player either way.
local function bagKeyNear(src, key)
    if type(key) ~= 'string' or #key > 100 then return false end
    local pos
    local netId = key:match('^net:(%d+)$')
    if netId then
        local ent = NetworkGetEntityFromNetworkId(tonumber(netId))
        if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
        pos = GetEntityCoords(ent)
    else
        local x, y, z = key:match('^[%d%-]+:([%d%.%-]+):([%d%.%-]+):([%d%.%-]+)$')
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        if not (x and y and z) then return false end
        pos = vector3(x, y, z)
    end
    return #(playerCoords(src) - pos) <= BAG_RANGE
end

local function nearTruck(src)
    local netId = ActiveVehicle[src]
    if not netId then return false end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    return #(playerCoords(src) - GetEntityCoords(veh)) <= TRUCK_RANGE
end

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

-- ── crew pay splits ─────────────────────────────────────────────────
-- A crew run pays a pool (CrewBonus x the run's pay per member); the leader's percentages share it.
-- Whole numbers, every member at least MinSplitPercent, adding up to 100. A change to the crew
-- resets them to equal shares (the leader gets the rounding).

local function SplitFloor() return math.max(0, math.floor(tonumber((Config.Garbage.Groups or {}).MinSplitPercent) or 10)) end
local function CrewBonus() return tonumber((Config.Garbage.Groups or {}).CrewBonus) or 1.5 end

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

PFJobsGarbage.SplitsValid, PFJobsGarbage.BuildPayPlan = SplitsValid, BuildPayPlan

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
        -- the same shares as a list (a table keyed by server id does not survive JSON)
        splits = (function()
            local out = {}
            for _, id in ipairs(CrewList(group)) do out[#out + 1] = { id = id, pct = (group.payoutSplits or {})[id] or 0 } end
            return out
        end)(),
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
    -- one run (and one truck) at a time; return the truck to start again
    if ActiveGarbagePlayers[src] then
        TriggerClientEvent('QBCore:Notify', src, 'You already have a garbage run going', 'error')
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

-- Server-side only: as a net event any client could add any amount of XP (and so a higher pay
-- tier). No client sends it; XP comes from depositBag.
AddEventHandler('pf-jobs:garbage:updateXP', function(delta)
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
    if not ActiveGarbagePlayers[src] then return end
    if PlayerCarrying[src] then return end
    if not bagKeyNear(src, key) then return end

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
        -- Loose bag: single use (for everyone, until a new bag could lie there)
        local takenAt = LooseBagsTaken[key]
        if takenAt and os.time() - takenAt < LOOSE_BAG_RESPAWN then
            TriggerClientEvent('QBCore:Notify', src, 'This bag has already been picked up.', 'error')
            return
        end
        LooseBagsTaken[key] = os.time()
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
    -- the client may only drop its bag; carrying one is granted by requestBag
    if flag then return end
    PlayerCarrying[src] = false
    TriggerClientEvent('pf-jobs:garbage:carrying', src, PlayerCarrying[src])
end)

-- Deposit carried bag into truck
RegisterNetEvent('pf-jobs:garbage:depositBag', function()
    local src = source
    if not ActiveGarbagePlayers[src] then return end
    if not nearTruck(src) then
        TriggerClientEvent('QBCore:Notify', src, 'Throw the bag into your truck', 'error')
        return
    end
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
    local depot = Config.Garbage.ReturnLocation or Config.Garbage.DepotLocation or depotCoords
    if #(playerCoords(src) - vector3(depot.x, depot.y, depot.z)) > DEPOT_RANGE then
        TriggerClientEvent('QBCore:Notify', src, 'Bring the truck back to the depot', 'error')
        return
    end
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
            local participants = CrewList(group)
            -- The crew's pool is what the flat crew bonus paid in total; the leader's splits share
            -- it. Fixed at the first attempt: a retry pays each member the same share once.
            PayoutPlans[routeId] = PayoutPlans[routeId] or BuildPayPlan(group, participants, totalPayout * CrewBonus())
            for _, share in ipairs(PayoutPlans[routeId]) do
                local paid, res = true, {}
                if share.amount > 0 then
                    -- One key per crew member, so a retry only pays whoever was missed
                    paid, res = PFPayout.Pay(share.cid, 'cash', share.amount, {
                        key = ('pf-jobs:garbage:%s:%s'):format(routeId, share.cid),
                        reason = 'garbage-group-job-payout',
                    })
                end
                if not paid then
                    payFailed = true
                elseif not (res and res.duplicate) then
                    local member = QBCore.Functions.GetPlayerByCitizenId(share.cid)
                    local memberSrc = member and member.PlayerData.source
                    if memberSrc then
                        TriggerClientEvent('QBCore:Notify', memberSrc, ('Crew run complete. Your %d%% share: $%d for %d bags.'):format(share.pct, share.amount, totalBags), 'success')
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
        PayoutPlans[routeId] = nil
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

--- What each crew member would get if the run ended now, from the current splits (or the plan
--- already fixed for payment).
function PFJobsGarbage.Shares(src)
    local leaderId = playerGroups[src]
    if not leaderId and groupSessions[src] then leaderId = src end
    local group = leaderId and groupSessions[leaderId]
    if not group then return nil end
    local routeId = GarbageRouteId[leaderId] or GarbageRouteId[src]
    local plan = routeId and PayoutPlans[routeId]
    if not plan then
        local level = CalculateLevel(GarbageXP[leaderId] or 0)
        local tierPay = Config.Garbage.PayoutPerBag[level] or Config.Garbage.PayoutPerBag[1] or 20
        local bags = math.min(SessionObjective[leaderId] or 0, ObjectiveTarget)
        plan = BuildPayPlan(group, CrewList(group), tierPay * bags * CrewBonus())
    end
    local out = {}
    for _, e in ipairs(plan) do out[#out + 1] = { id = e.src, pct = e.pct, amount = e.amount } end
    return out
end

CreateCallback('pf-jobs:garbage:getInit', function(source, cb)
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
    
    -- invites still open (the party must still exist), so a reopened app can show them
    local invites = {}
    for inviter in pairs(pendingInvites[src] or {}) do
        if groupSessions[inviter] then
            invites[#invites + 1] = { leaderId = inviter, leaderName = GetPlayerName(inviter) }
        end
    end
    local zoneIdx = ActiveZoneIndex[src]
    local zone = zoneIdx and SessionZones[src] and SessionZones[src][zoneIdx]
    local cleared = 0
    for _ in pairs(ZoneDumpsterProgress[src] or {}) do cleared = cleared + 1 end

    cb({ 
        playerId = src,
        xp = xp, 
        level = level, 
        carrying = PlayerCarrying[src] or false, 
        deposited = DepositedCount[src] or 0, 
        cap = cap,
        currentGroup = currentGroup,
        pendingInvites = invites,
        active = ActiveGarbagePlayers[src] == true,
        plate = ActiveVehiclePlate[src],
        collected = SessionObjective[src] or 0,
        objectiveTarget = ObjectiveTarget,
        zone = zone and { name = zone.name, cleared = cleared, target = Config.Garbage.DumpstersPerZone, index = zoneIdx, total = #SessionZones[src] } or nil,
        payShares = PFJobsGarbage.Shares(src),
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    pendingInvites[src] = nil
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
                RebalanceGroup(groupSessions[leaderId])
                
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
        },
        cids = { [src] = GetCitizenId(src) },
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
                    RebalanceGroup(oldGroup)
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
    group.cids = group.cids or {}
    group.cids[src] = GetCitizenId(src)
    RebalanceGroup(group)
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
    pendingInvites[targetId] = pendingInvites[targetId] or {}
    pendingInvites[targetId][src] = true
    TriggerClientEvent('pf-jobs:garbage:receiveInvite', targetId, leaderName, src)
    TriggerClientEvent('QBCore:Notify', src, string.format('Invite sent to %s (ID: %d)', TargetPlayer.PlayerData.charinfo.firstname .. ' ' .. TargetPlayer.PlayerData.charinfo.lastname, targetId), 'success')
end)

-- Accept invite
RegisterNetEvent('pf-jobs:garbage:acceptInvite', function(leaderId)
    local src = source
    -- only an invite the leader actually sent (anyone could join any crew, and share its payout)
    leaderId = tonumber(leaderId)
    if not leaderId or not (pendingInvites[src] and pendingInvites[src][leaderId]) then
        TriggerClientEvent('QBCore:Notify', src, 'No invite from that party', 'error')
        return
    end
    pendingInvites[src][leaderId] = nil
    
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
    group.cids = group.cids or {}
    group.cids[src] = GetCitizenId(src)
    -- equal shares again whenever the crew changes
    RebalanceGroup(group)
    
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
    leaderId = tonumber(leaderId)
    if not leaderId or not (pendingInvites[src] and pendingInvites[src][leaderId]) then return end
    pendingInvites[src][leaderId] = nil
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
                RebalanceGroup(group)
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
            RebalanceGroup(group)
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

local function pushGroup(leaderId)
    local formattedData = GetFormattedGroupData(leaderId)
    TriggerClientEvent('pf-jobs:garbage:groupUpdate', leaderId, formattedData)
    for _, memberId in ipairs((groupSessions[leaderId] or {}).members or {}) do
        TriggerClientEvent('pf-jobs:garbage:groupUpdate', memberId, formattedData)
    end
end

-- Saves the crew's shares to pf_garbage_group_members (shown again if the group is reloaded).
local function persistSplits(leaderId)
    local group = groupSessions[leaderId]
    local gid = groupDbIds[leaderId]
    if not (group and gid and GROUPS_PERSIST and DB_READY and Config.Garbage.UseDatabase) then return end
    for _, id in ipairs(CrewList(group)) do
        local cid = GetCitizenId(id)
        if cid then
            pcall(MySQL.query.await, 'INSERT INTO pf_garbage_group_members (group_id, citizenid, display_name, cut_percent) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE cut_percent = VALUES(cut_percent), display_name = VALUES(display_name)', {
                gid, cid, GetPlayerName(id), group.payoutSplits[id] or 0
            })
        end
    end
end

-- The leader sets every share at once: { [memberSrc] = percent, ... } (string keys accepted).
RegisterNetEvent('pf-jobs:garbage:setSplits', function(splits)
    local src = source
    local group = groupSessions[src]
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the crew leader can set the shares', 'error')
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
    persistSplits(src)
    TriggerClientEvent('QBCore:Notify', src, 'Crew shares updated', 'success')
    pushGroup(src)
end)

-- Older UI: one member's share; the others share the rest equally (the leader gets the rounding).
RegisterNetEvent('pf-jobs:garbage:updateSplit', function(targetId, percentage)
    local src = source
    local group = groupSessions[src]
    if not group or group.leader ~= src then
        TriggerClientEvent('QBCore:Notify', src, 'Only the party leader can adjust splits', 'error')
        return
    end
    targetId, percentage = tonumber(targetId), tonumber(percentage)
    local list = CrewList(group)
    local inCrew = false
    for _, id in ipairs(list) do if id == targetId then inCrew = true end end
    local floor = SplitFloor()
    if not inCrew or not percentage or percentage % 1 ~= 0 or percentage < floor or percentage > 100 - floor * (#list - 1) then
        TriggerClientEvent('QBCore:Notify', src, ('Each member needs at least %d%%'):format(floor), 'error')
        return
    end
    local splits = { [targetId] = percentage }
    local rest = {}
    for _, id in ipairs(list) do if id ~= targetId then rest[#rest + 1] = id end end
    if #rest > 0 then
        local each = math.floor((100 - percentage) / #rest)
        for _, id in ipairs(rest) do splits[id] = each end
        local lead = targetId ~= src and src or rest[1]
        splits[lead] = splits[lead] + (100 - percentage - each * #rest)
    elseif percentage ~= 100 then
        return
    end
    if not SplitsValid(splits, list) then return end
    group.payoutSplits = splits
    persistSplits(src)
    TriggerClientEvent('QBCore:Notify', src, string.format('Updated %s split to %d%%', GetPlayerName(targetId), percentage), 'success')
    pushGroup(src)
end)

--- Removes a deleted character from any live crew (a leader's crew is closed).
function PFJobsGarbage.ForgetCitizen(cid)
    for leaderId, group in pairs(groupSessions) do
        for memberSrc, memberCid in pairs(group.cids or {}) do
            if memberCid == cid then
                if memberSrc == leaderId then
                    for _, m in ipairs(group.members) do
                        playerGroups[m] = nil
                        TriggerClientEvent('pf-jobs:garbage:groupUpdate', m, nil)
                        TriggerClientEvent('QBCore:Notify', m, 'Crew closed', 'error')
                    end
                    local code = groupCodes[leaderId]
                    if code then codeToLeader[code] = nil; groupCodes[leaderId] = nil end
                    groupSessions[leaderId] = nil
                    groupDbIds[leaderId] = nil
                else
                    for i, m in ipairs(group.members) do
                        if m == memberSrc then table.remove(group.members, i) break end
                    end
                    RebalanceGroup(group)
                    pushGroup(leaderId)
                end
                playerGroups[memberSrc] = nil
            end
        end
    end
end

-- Get group state callback
CreateCallback('pf-jobs:garbage:getGroupState', function(source, cb)
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
