-- server/work_orders.lua
-- PF Mechanic Job - Work Order Level System
-- Handles player progression, work order generation, and rewards

PFMech = PFMech or {}
PFMech.Debug('[Work Orders] Server script starting...')

local QBCore = exports['pfm-core']:GetCoreObject()

PFMech.Debug('[Work Orders] QBCore loaded')

-- Player progress data (in-memory, will be saved to database)
local PlayerProgress = {}

-- Active work orders (available for acceptance)
local AvailableOrders = {}

-- Accepted work orders (in-progress)
local AcceptedOrders = {}

local OrderIdCounter = 1

PFMech.Debug('[Work Orders] Tables initialized')

-- Track player search states (declare EARLY so callbacks can use them)
local playerSearchStates = {}
local playerSearchThreads = {}

-- Job generation constants
local MIN_JOB_SPAWN_TIME = 10000  -- 10 seconds
local MAX_JOB_SPAWN_TIME = 60000  -- 60 seconds (1 minute max)
local MAX_VISIBLE_JOBS = 3

PFMech.Debug('[Work Orders] Search state tables initialized')

-- Initialize player progress
local function initPlayerProgress(citizenid)
    if PlayerProgress[citizenid] then
        return PlayerProgress[citizenid]
    end

    -- Try primary table
    local result = MySQL.Sync.fetchAll('SELECT * FROM pf_mechanic_progress WHERE citizenid = ?', { citizenid })

    -- Fallback: migrate legacy pf_mech_profiles row if present
    if (not result or not result[1]) then
        local legacy = MySQL.Sync.fetchAll('SELECT * FROM pf_mech_profiles WHERE citizenid = ? LIMIT 1', { citizenid })
        if legacy and legacy[1] then
            result = { {
                citizenid = citizenid,
                level = legacy[1].rank or 1,
                xp = legacy[1].xp or 0,
                total_jobs = legacy[1].jobs_done or 0,
                last_refresh = 0,
            } }

            -- Persist migrated row so we stop hitting the legacy table
            MySQL.Async.insert('INSERT INTO pf_mechanic_progress (citizenid, level, xp, total_jobs, last_refresh) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE level = VALUES(level), xp = VALUES(xp), total_jobs = VALUES(total_jobs), last_refresh = VALUES(last_refresh)',
                { citizenid, result[1].level, result[1].xp, result[1].total_jobs, result[1].last_refresh })

            if Config.Debug then
                print(string.format('[Work Orders] Migrated legacy profile for %s: Level %d, XP %d', citizenid, result[1].level, result[1].xp))
            end
        end
    end

    if result and result[1] then
        PlayerProgress[citizenid] = {
            citizenid = citizenid,
            level = result[1].level or 1,
            xp = result[1].xp or 0,
            totalJobs = result[1].total_jobs or 0,
            lastRefresh = result[1].last_refresh or 0,
        }

        if Config.Debug then
            print(string.format('[Work Orders] Loaded progress for %s: Level %d, XP %d, Jobs %d',
                citizenid, PlayerProgress[citizenid].level, PlayerProgress[citizenid].xp, PlayerProgress[citizenid].totalJobs))
        end
    else
        -- Create new progress entry
        PlayerProgress[citizenid] = {
            citizenid = citizenid,
            level = 1,
            xp = 0,
            totalJobs = 0,
            lastRefresh = 0,
        }

        if Config.Debug then
            print(string.format('[Work Orders] Created new progress for %s', citizenid))
        end

        -- Insert into database
        MySQL.Async.insert('INSERT INTO pf_mechanic_progress (citizenid, level, xp, total_jobs, last_refresh) VALUES (?, ?, ?, ?, ?)',
            { citizenid, 1, 0, 0, 0 })
    end

    return PlayerProgress[citizenid]
end

-- Save player progress to database
local function savePlayerProgress(citizenid)
    local progress = PlayerProgress[citizenid]
    if not progress then return end
    
    MySQL.Async.execute('UPDATE pf_mechanic_progress SET level = ?, xp = ?, total_jobs = ?, last_refresh = ? WHERE citizenid = ?',
        {progress.level, progress.xp, progress.totalJobs, progress.lastRefresh, citizenid})
end

-- Get player's current level data
local function getPlayerLevelData(level)
    for _, levelData in ipairs(Config.WorkOrderSystem.levels) do
        if levelData.level == level then
            return levelData
        end
    end
    return Config.WorkOrderSystem.levels[1] -- Default to level 1
end

-- Calculate level from XP
local function calculateLevel(xp)
    local level = 1
    for i = #Config.WorkOrderSystem.levels, 1, -1 do
        if xp >= Config.WorkOrderSystem.levels[i].minXP then
            level = Config.WorkOrderSystem.levels[i].level
            break
        end
    end
    return level
end

-- Get next level XP requirement
local function getNextLevelXP(currentLevel)
    for i, levelData in ipairs(Config.WorkOrderSystem.levels) do
        if levelData.level == currentLevel + 1 then
            return levelData.minXP
        end
    end
    return nil -- Max level reached
end

-- ============================================================================
-- WORK ORDER GENERATION
-- ============================================================================

-- Generate a random work order based on difficulty
local function generateWorkOrder(difficulty, orderId)
    local difficultyData = Config.WorkOrderSystem.jobDifficulties[difficulty]
    if not difficultyData then return nil end
    
    -- Pick random vehicle and customer
    local vehicle = Config.WorkOrderSystem.vehicles[math.random(#Config.WorkOrderSystem.vehicles)]
    local customer = Config.WorkOrderSystem.customerNames[math.random(#Config.WorkOrderSystem.customerNames)]
    
    -- Pick random task from difficulty
    local task = difficultyData.tasks[math.random(#difficultyData.tasks)]
    
    local currentTime = os.time()
    local expirationTime = Config.WorkOrderSystem.offerExpirationTime or 0
    
    return {
        id = orderId,
        -- OrderIdCounter restarts with the resource, so payouts are keyed by this unique id instead
        payoutId = PFPayout.NewId(),
        difficulty = difficulty,
        difficultyName = difficultyData.name,
        color = difficultyData.color,
        title = task.name,
        taskType = task.type,
        repairType = task.repairType or task.type,
        requiredItem = task.item or nil,
        vehicle = vehicle,
        customer = customer,
        basePay = difficultyData.basePay,
        duration = task.duration,
        xpReward = Config.WorkOrderSystem.xpPerJob[difficulty],
        status = "available",
        createdAt = currentTime,
        expiresAt = expirationTime > 0 and (currentTime + expirationTime) or nil, -- nil if expiration disabled
    }
end

-- Generate a SINGLE work order for a player (called from the search thread)
local function generateSingleWorkOrderForPlayer(citizenid)
    local progress = initPlayerProgress(citizenid)
    local levelData = getPlayerLevelData(progress.level)

    -- Check current count
    AvailableOrders[citizenid] = AvailableOrders[citizenid] or {}
    local currentCount = #AvailableOrders[citizenid]
    
    -- Only generate if under the max
    if currentCount >= levelData.maxOffers then
        return false
    end

    local availableJobTypes = levelData.jobTypes
    print(string.format('[Work Orders] generateSingleWorkOrderForPlayer: citizenid=%s, level=%d, jobTypes count=%d', 
        citizenid, levelData.level, #availableJobTypes))
    
    local jobType = availableJobTypes[math.random(#availableJobTypes)]
    print(string.format('[Work Orders] Selected jobType: %s', tostring(jobType)))
    
    local order = generateWorkOrder(jobType, OrderIdCounter)
    OrderIdCounter = OrderIdCounter + 1

    if order then
        table.insert(AvailableOrders[citizenid], order)
        
        local expirationTime = Config.WorkOrderSystem.offerExpirationTime or 0
        if expirationTime > 0 then
            print(string.format('[Work Orders] Generated ONE order #%d: %s (%s) for %s (total now: %d/%d, expires in %ds)',
                order.id, order.title, jobType, order.vehicle, #AvailableOrders[citizenid], levelData.maxOffers, expirationTime))
        else
            print(string.format('[Work Orders] Generated ONE order #%d: %s (%s) for %s (total now: %d/%d, no expiration)',
                order.id, order.title, jobType, order.vehicle, #AvailableOrders[citizenid], levelData.maxOffers))
        end
        
        -- Start expiration thread for this order (only if expiration is enabled)
        if expirationTime > 0 and order.expiresAt then
            CreateThread(function()
                local orderId = order.id
                local expiresAt = order.expiresAt
                
                -- Wait until expiration
                local waitTime = (expiresAt - os.time()) * 1000
                if waitTime > 0 then
                    Wait(waitTime)
                end
                
                -- Check if order still exists and hasn't been accepted
                local available = getAvailableOrders(citizenid)
                for i, o in ipairs(available) do
                    if o.id == orderId then
                        -- Order expired, remove it and apply XP penalty
                        table.remove(AvailableOrders[citizenid], i)
                        
                        print(string.format('[Work Orders] Order #%d EXPIRED for %s (not accepted in time)', orderId, citizenid))
                        
                        -- Apply XP penalty from config
                        local xpPenalty = Config.WorkOrderSystem.expirationXPPenalty or 10
                        local progress = PlayerProgress[citizenid]
                        if progress then
                            progress.xp = math.max(0, progress.xp - xpPenalty)
                            savePlayerProgress(citizenid)
                            print(string.format('[Work Orders] Applied -%d XP penalty to %s (now: %d XP)', xpPenalty, citizenid, progress.xp))
                        end
                        
                        -- Notify client to update UI and show penalty
                        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
                        if Player then
                            TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 
                                string.format('Job offer expired! -%d XP penalty', xpPenalty), 'error', 3000)
                            TriggerClientEvent('pf-mechanicjob:client:workOrdersReady', Player.PlayerData.source, {
                                availableOrders = getAvailableOrders(citizenid)
                            })
                        end
                        break
                    end
                end
            end)
        end
        
        return true
    else
        print(string.format('[Work Orders] ERROR: generateWorkOrder returned nil for jobType=%s', tostring(jobType)))
    end
    
    return false
end

-- Generate work orders for a player based on their level (for manual refresh/first load)
-- DEPRECATED: Use generateSingleWorkOrderForPlayer for job generation during search
local function generateWorkOrdersForPlayer(citizenid)
    local progress = initPlayerProgress(citizenid)
    local levelData = getPlayerLevelData(progress.level)

    -- Always top off available offers up to maxOffers (no timer gating)
    AvailableOrders[citizenid] = AvailableOrders[citizenid] or {}
    local currentCount = #AvailableOrders[citizenid]
    local missing = levelData.maxOffers - currentCount
    if missing <= 0 then
        return false -- Already have enough offers
    end

    local availableJobTypes = levelData.jobTypes

    for i = 1, missing do
        local jobType = availableJobTypes[math.random(#availableJobTypes)]
        local order = generateWorkOrder(jobType, OrderIdCounter)
        OrderIdCounter = OrderIdCounter + 1

        if order then
            table.insert(AvailableOrders[citizenid], order)
            if Config.Debug then
                print(string.format('[Work Orders] Generated order #%d: %s (%s) for %s',
                    order.id, order.title, jobType, order.vehicle))
            end
        end
    end

    progress.lastRefresh = os.time()
    savePlayerProgress(citizenid)
    return true
end

-- Get available orders for a player
local function getAvailableOrders(citizenid)
    if not AvailableOrders[citizenid] then
        AvailableOrders[citizenid] = {}
    end
    return AvailableOrders[citizenid]
end

-- Get accepted orders for a player
local function getAcceptedOrders(citizenid)
    if not AcceptedOrders[citizenid] then
        AcceptedOrders[citizenid] = {}
    end
    return AcceptedOrders[citizenid]
end

-- Persist a completed work order into pf_work_orders for stats/history
local function recordCompletedWorkOrder(citizenid, order, payout)
    if not citizenid or not order then return end

    local validTypes = { engine = true, suspension = true, cosmetic = true, service = true }
    local otype = (order.taskType or order.repairType or 'service'):lower()
    if not validTypes[otype] then otype = 'service' end

    local plate = order.plate or (type(order.vehicle) == 'string' and string.sub(order.vehicle, 1, 16)) or 'UNKNOWN'
    local vehModel = order.veh_model or order.vehicle or 'Unknown'
    local notes = order.title or 'Repair Job'
    local reqParts = order.requiredParts or {}

    local ok, err = pcall(function()
        MySQL.insert.await([[INSERT INTO pf_work_orders
            (type, source, requester_name, requester_identifier, plate, veh_model, notes, required_parts, deadline_at, status, quality, payout, assigned_to)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
        ]], {
            otype,
            'player',
            order.customer or 'Customer',
            nil,
            plate,
            vehModel,
            notes,
            json.encode(reqParts),
            'complete',
            order.quality or 0,
            payout or 0,
            citizenid
        })
    end)

    if not ok then
        print('[Work Orders] Failed to record completed work order for ' .. tostring(citizenid) .. ': ' .. tostring(err))
    end
end

-- ============================================================================
-- XP AND LEVEL UP
-- ============================================================================

-- Award XP to player
local function awardXP(citizenid, amount, source)
    local progress = initPlayerProgress(citizenid)
    local oldLevel = progress.level
    
    progress.xp = progress.xp + amount
    progress.level = calculateLevel(progress.xp)
    
    savePlayerProgress(citizenid)
    
    -- Check for level up
    if progress.level > oldLevel then
        local levelData = getPlayerLevelData(progress.level)
        if source then
            TriggerClientEvent('QBCore:Notify', source, 
                string.format('Level Up! You are now %s (Level %d)', levelData.name, progress.level), 
                'success', 5000)
        end
        
        if Config.Debug then
            print(string.format('[Work Orders] Player %s leveled up to %d (%s)', citizenid, progress.level, levelData.name))
        end
    end
    
    return progress
end

-- Checks before a work order pays. Completing used to pay any player (mechanic or not) straight
-- after accepting, with no repair done. Now: a mechanic, at least half the job's listed duration
-- since accepting, and the part the job needs used up (taken now, or spent on a repair through the
-- diagnostics menu in the last two minutes). A part taken once is not taken again on a retry.
local MIN_WORK_SECONDS = 10
local function workOrderDone(src, Player, order)
    local job = Player.PlayerData.job
    if not (job and Config.IsMechanicJob(job.name)) then return false, 'You are not a mechanic' end
    local minTime = math.max(MIN_WORK_SECONDS, math.floor((tonumber(order.duration) or 0) * 0.5))
    if os.time() - (order.acceptedAt or os.time()) < minTime then return false, 'The job is not finished yet' end
    if order.partUsed then return true end
    local need = Config.WorkOrderSystem.requiredItems and order.requiredItem
    if not need then return true end
    local recent = PFMech.RecentRepairs and PFMech.RecentRepairs[src]
    if recent and recent.item == need and os.time() - recent.at <= 120 then
        PFMech.RecentRepairs[src] = nil
        order.partUsed = true
        return true
    end
    if Player.Functions.RemoveItem(need, 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[need], 'remove')
        order.partUsed = true
        return true
    end
    return false, ('You need a %s to complete this job'):format(need)
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

-- Get player's work order data
QBCore.Functions.CreateCallback('pf_mech:workorders:getData', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        if Config.Debug then
            print('[Work Orders] getData failed: Player not found for source ' .. tostring(source))
        end
        cb(nil)
        return
    end

    if Config.Debug then
        print(string.format('[Work Orders] getData called for src=%s', tostring(source)))
    end
    
    local citizenid = Player.PlayerData.citizenid
    local progress = initPlayerProgress(citizenid)
    local levelData = getPlayerLevelData(progress.level)
    local nextLevelXP = getNextLevelXP(progress.level)
    
    if Config.Debug then
        print(string.format('[Work Orders] getData for %s: Level %d, XP %d', citizenid, progress.level, progress.xp))
    end
    
    -- Get search state
    local isSearching = playerSearchStates[citizenid] or false
    
    -- If not searching, clear available orders
    if not isSearching then
        AvailableOrders[citizenid] = {}
    end
    -- If searching, the thread handles job generation - don't generate here

    local available = getAvailableOrders(citizenid)
    local accepted = getAcceptedOrders(citizenid)

    if Config.Debug then
        print(string.format('[Work Orders] getData for %s: %d available, %d accepted, searching: %s', citizenid, #available, #accepted, tostring(isSearching)))
        if #accepted > 0 then
            for i, order in ipairs(accepted) do
                print(string.format('[Work Orders] - Accepted order #%d: %s (status: %s)', order.id, order.title, order.status))
            end
        end
    end
    
    -- Calculate time until next refresh
    local currentTime = os.time()
    local timeUntilRefresh = math.max(0, levelData.offerRefreshTime - (currentTime - progress.lastRefresh))
    
    -- Get current level's starting XP
    local currentLevelXP = levelData.minXP
    
    -- Get search state
    local isSearching = playerSearchStates[citizenid] or false
    
    if Config.Debug then
        print(string.format('[Work Orders] Sending data: Level %d, XP %d, Searching: %s', 
            progress.level, progress.xp, tostring(isSearching)))
    end
    
    cb({
        level = progress.level,
        levelName = levelData.name,
        xp = progress.xp,
        currentLevelXP = currentLevelXP,
        nextLevelXP = nextLevelXP,
        totalJobs = progress.totalJobs,
        payMultiplier = levelData.payMultiplier,
        maxOffers = levelData.maxOffers,
        timeUntilRefresh = timeUntilRefresh,
        availableOrders = available,
        acceptedOrders = accepted,
        isSearching = isSearching,
    })
end)

-- Helper: debug current player's progress rows
if Config.Debug then
    RegisterCommand('mechxptest', function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then
            print('[Work Orders] mechxptest failed: no player for source', source)
            return
        end

        local cid = Player.PlayerData.citizenid
        local prog = MySQL.Sync.fetchAll('SELECT * FROM pf_mechanic_progress WHERE citizenid = ? LIMIT 1', { cid })
        local legacy = MySQL.Sync.fetchAll('SELECT * FROM pf_mech_profiles WHERE citizenid = ? LIMIT 1', { cid })

        print(string.format('[Work Orders] mechxptest for %s: progress row? %s, legacy row? %s',
            cid,
            prog and prog[1] and ('yes xp=' .. tostring(prog[1].xp) .. ' level=' .. tostring(prog[1].level)) or 'no',
            legacy and legacy[1] and ('yes xp=' .. tostring(legacy[1].xp) .. ' rank=' .. tostring(legacy[1].rank)) or 'no'))

        TriggerClientEvent('QBCore:Notify', source, 'Check server console for mechxptest output', 'primary', 5000)
    end, false)
end

-- Accept a work order
QBCore.Functions.CreateCallback('pf_mech:workorders:accept', function(source, cb, orderId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        cb({success = false, message = "Player not found"})
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    local available = getAvailableOrders(citizenid)
    local accepted = getAcceptedOrders(citizenid)
    
    if Config.Debug then
        print(string.format('[Work Orders] Accept request - citizenid: %s, orderId: %s (type: %s)', citizenid, tostring(orderId), type(orderId)))
        print(string.format('[Work Orders] Before accept - Available: %d, Accepted: %d', #available, #accepted))
        for i, order in ipairs(available) do
            print(string.format('[Work Orders] - Available order #%s: %s', tostring(order.id), order.title))
        end
    end
    
    -- Find the order in available orders
    local orderIndex = nil
    local order = nil
    for i, o in ipairs(available) do
        if o.id == orderId then
            orderIndex = i
            order = o
            break
        end
    end
    
    if not order then
        cb({success = false, message = "Work order not found"})
        return
    end
    
    -- Check if player already has an active job (max 1 at a time)
    if #accepted >= 1 then
        cb({success = false, message = "You can only have 1 active job at a time"})
        return
    end
    
    -- Move order from available to accepted
    table.remove(available, orderIndex)
    order.status = "accepted"
    order.acceptedAt = os.time()
    table.insert(accepted, order)
    
    if Config.Debug then
        print(string.format('[Work Orders] Player %s accepted order #%d: %s', citizenid, orderId, order.title))
        print(string.format('[Work Orders] After accept - Available: %d, Accepted: %d', #available, #accepted))
    end
    
    -- Trigger vehicle spawn on client
    if Config.WorkOrderSystem.spawnVehicleOnAccept then
        TriggerClientEvent('pf_mech:workorder:spawnVehicle', source, order)
    end
    
    cb({success = true, message = "Work order accepted!", order = order})
end)

-- Complete a work order
QBCore.Functions.CreateCallback('pf_mech:workorders:complete', function(source, cb, orderId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        cb({success = false, message = "Player not found"})
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    local accepted = getAcceptedOrders(citizenid)
    local progress = initPlayerProgress(citizenid)
    local levelData = getPlayerLevelData(progress.level)
    
    -- Find the order in accepted orders
    local orderIndex = nil
    local order = nil
    for i, o in ipairs(accepted) do
        if o.id == orderId then
            orderIndex = i
            order = o
            break
        end
    end
    
    if not order then
        cb({success = false, message = "Work order not found"})
        return
    end

        if Config.Debug then
            PFMech.Debug('[DEBUG] pf_mech:workorders:complete called for orderId:', orderId, 'orderIndex:', orderIndex, 'citizenid:', citizenid)
        end
    
    local done, why = workOrderDone(source, Player, order)
    if not done then
        cb({success = false, message = why})
        return
    end

    -- Calculate payout with level multiplier
    local payout = math.floor(order.basePay * levelData.payMultiplier)

    -- Award money and XP; on failure the order stays accepted so completing again retries with the same key
    order.payoutId = order.payoutId or PFPayout.NewId()
    local paid, res = PFPayout.Pay(Player, 'bank', payout, {
        key = ('pf-mechanicjob:workorder:%s:%s'):format(order.payoutId, citizenid),
        reason = 'mechanic-work-order',
    })
    if not paid then
        cb({success = false, message = "Payment failed, try again"})
        return
    end
    local newProgress = progress
    -- A key that was already paid means this order was rewarded before: no XP or stats again
    if not res.duplicate then
        newProgress = awardXP(citizenid, order.xpReward, source)

        -- Update stats
        newProgress.totalJobs = newProgress.totalJobs + 1
        recordCompletedWorkOrder(citizenid, order, payout)
        savePlayerProgress(citizenid)
    end

    -- Remove from accepted orders (the list may have changed while the bank call ran)
    for i, o in ipairs(accepted) do
        if o == order then table.remove(accepted, i) break end
    end
        if Config.Debug then
            PFMech.Debug('[DEBUG] Removed order from accepted orders. Remaining:', #accepted)
        end

    -- If player is still searching, trigger new job on random timer (don't add immediately)
    if playerSearchStates[citizenid] then
        if Config.Debug then
            print(string.format('[Work Orders] Completion: %s still searching, next job will appear on timer', citizenid))
        end
        -- The existing thread will handle generating the next job after its random wait
    end
    
    if Config.Debug then
        print(string.format('[Work Orders] Player %s completed order #%d: $%d, +%d XP', 
            citizenid, orderId, payout, order.xpReward))
    end
    
    TriggerClientEvent('QBCore:Notify', source, 
        string.format('Job completed! Earned $%d and %d XP', payout, order.xpReward), 
        'success', 5000)

    TriggerClientEvent('pf-mechanicjob:client:workOrdersReady', source, {
        availableOrders = getAvailableOrders(citizenid),
        acceptedOrders = accepted,
        isSearching = playerSearchStates[citizenid] or false
    })
    
    -- Remove vehicle on client
    if Config.WorkOrderSystem.deleteVehicleOnComplete then
        TriggerClientEvent('pf_mech:workorder:removeVehicle', source)
    end
    
    cb({
        success = true, 
        message = "Work order completed!",
        payout = payout,
        xpGained = order.xpReward,
        newLevel = newProgress.level,
        newXP = newProgress.xp
    })
end)

-- Cancel a work order
QBCore.Functions.CreateCallback('pf_mech:workorders:cancel', function(source, cb, orderId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        cb({success = false, message = "Player not found"})
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    local accepted = getAcceptedOrders(citizenid)

    -- Find and remove the order
    local orderIndex = nil
    local order = nil
    for i, o in ipairs(accepted) do
        if o.id == orderId then
            orderIndex = i
            order = o
            break
        end
    end

    if not orderIndex or not order then
        cb({success = false, message = "Work order not found"})
        return
    end

    table.remove(accepted, orderIndex)

    -- Apply XP penalty (50% of would-be reward)
    local xpPenalty = math.floor((order.xpReward or 0) * 0.5)
    local progress = initPlayerProgress(citizenid)
    if xpPenalty > 0 then
        progress.xp = math.max(0, progress.xp - xpPenalty)
        progress.level = calculateLevel(progress.xp)
        savePlayerProgress(citizenid)
    end
    
    -- Remove vehicle on client
    if Config.WorkOrderSystem.deleteVehicleOnComplete then
        TriggerClientEvent('pf_mech:workorder:removeVehicle', source)
    end
    
    if Config.Debug then
        print(string.format('[Work Orders] Player %s cancelled order #%d (-%d XP)', citizenid, orderId, xpPenalty))
    end

    -- Notify player of penalty
    if xpPenalty > 0 then
        TriggerClientEvent('QBCore:Notify', source, string.format('Order cancelled. Lost %d XP.', xpPenalty), 'error', 4000)
    else
        TriggerClientEvent('QBCore:Notify', source, 'Order cancelled.', 'error', 3000)
    end

    cb({
        success = true,
        message = "Work order cancelled",
        xpLost = xpPenalty,
        newXP = progress and progress.xp or nil,
        newLevel = progress and progress.level or nil
    })
end)

-- Force refresh work orders
QBCore.Functions.CreateCallback('pf_mech:workorders:refresh', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        cb({success = false})
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
        if Config.Debug then
            PFMech.Debug('[DEBUG] Server completeRepair triggered for orderId:', orderId, 'citizenid:', citizenid)
        end
    
    -- Only refresh/generate if actively searching
    local isSearching = playerSearchStates[citizenid] or false
    if isSearching then
        local progress = initPlayerProgress(citizenid)
        progress.lastRefresh = 0
        generateWorkOrdersForPlayer(citizenid)
    else
        -- Not searching, clear available orders
        AvailableOrders[citizenid] = {}
    end
    
    local available = getAvailableOrders(citizenid)
    
    cb({
        success = true,
        availableOrders = available
    })
end)

-- Start searching for work orders (gradual generation over time)
QBCore.Functions.CreateCallback('pf_mech:workorders:startSearch', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        print('[Work Orders] Start search failed: Player not found')
        cb({success = false})
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    playerSearchStates[citizenid] = true
    
    -- Initialize progress
    local progress = initPlayerProgress(citizenid)
    local levelData = getPlayerLevelData(progress.level)
    local nextLevelXP = getNextLevelXP(progress.level)
    local currentLevelXP = levelData.minXP
    
    print(string.format('[Work Orders] Player %s started searching (Level %d: %s)', 
        citizenid, progress.level, levelData.name))
    
    -- Stop any existing thread for this player
    if playerSearchThreads[citizenid] then
        playerSearchThreads[citizenid] = false
        Wait(100) -- Let old thread finish
    end
    
    local available = getAvailableOrders(citizenid)
    local accepted = getAcceptedOrders(citizenid)
    
    print(string.format('[Work Orders] Returning callback with %d available orders, %d accepted orders', #available, #accepted))
    
    -- Return complete data structure matching getData
    cb({
        success = true,
        level = progress.level,
        levelName = levelData.name,
        xp = progress.xp,
        currentLevelXP = currentLevelXP,
        nextLevelXP = nextLevelXP,
        totalJobs = progress.totalJobs,
        payMultiplier = levelData.payMultiplier,
        maxOffers = levelData.maxOffers,
        availableOrders = available,
        acceptedOrders = accepted,
        isSearching = true
    })
    
    print(string.format('[Work Orders] Player %s started search, jobs will appear on timer', citizenid))
    
    -- Start gradual job generation thread
    playerSearchThreads[citizenid] = true
    
    print(string.format('[Work Orders] Starting job generation thread for %s', citizenid))
    
    CreateThread(function()
        print(string.format('[Work Orders] Thread CREATED and RUNNING for %s', citizenid))
        print(string.format('[Work Orders] playerSearchStates[%s] = %s', citizenid, tostring(playerSearchStates[citizenid])))
        print(string.format('[Work Orders] playerSearchThreads[%s] = %s', citizenid, tostring(playerSearchThreads[citizenid])))
        print(string.format('[Work Orders] MIN_JOB_SPAWN_TIME = %d, MAX_JOB_SPAWN_TIME = %d', MIN_JOB_SPAWN_TIME, MAX_JOB_SPAWN_TIME))
        
        local loopCount = 0
        -- Generate jobs over time with random delays
        while playerSearchStates[citizenid] and playerSearchThreads[citizenid] do
            loopCount = loopCount + 1
            
            -- Wait random time between 10-60 seconds before next job
            local waitTime = math.random(MIN_JOB_SPAWN_TIME, MAX_JOB_SPAWN_TIME)
            print(string.format('[Work Orders] Loop %d for %s: waiting %.1f seconds for next job (available: %d)', 
                loopCount, citizenid, waitTime/1000, #getAvailableOrders(citizenid)))
            
            Wait(waitTime)
            
            if not playerSearchStates[citizenid] or not playerSearchThreads[citizenid] then 
                print(string.format('[Work Orders] Thread stopped for %s (searchState: %s, threadState: %s)', 
                    citizenid, tostring(playerSearchStates[citizenid]), tostring(playerSearchThreads[citizenid])))
                break 
            end
            
            local available = getAvailableOrders(citizenid)
            local progress = PlayerProgress[citizenid] or initPlayerProgress(citizenid)
            local levelData = getPlayerLevelData(progress.level)
            
            print(string.format('[Work Orders] Loop %d: After wait, %s has %d available jobs (max: %d)', 
                loopCount, citizenid, #available, levelData.maxOffers))
            
            -- Only generate if under max visible jobs
            if #available < levelData.maxOffers then
                -- Generate EXACTLY ONE job
                local wasGenerated = generateSingleWorkOrderForPlayer(citizenid)
                
                if wasGenerated then
                    -- Notify player of new job
                    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
                    if Player then
                        TriggerClientEvent('pf-mechanicjob:client:workOrdersReady', Player.PlayerData.source, {
                            availableOrders = getAvailableOrders(citizenid)
                        })
                        print(string.format('[Work Orders] Loop %d: Sent job to %s (now has %d/%d)', 
                            loopCount, citizenid, #getAvailableOrders(citizenid), levelData.maxOffers))
                    end
                else
                    print(string.format('[Work Orders] Loop %d: Failed to generate job for %s', loopCount, citizenid))
                end
            else
                print(string.format('[Work Orders] Loop %d: %s already has max offers (%d), skipping generation', 
                    loopCount, citizenid, #available))
            end
        end
        
        playerSearchThreads[citizenid] = nil
        if Config.Debug then
            print(string.format('[Work Orders] Stopped job generation thread for %s', citizenid))
        end
    end)
end)

-- Stop searching for work orders (clear available orders and stop thread)
QBCore.Functions.CreateCallback('pf_mech:workorders:stopSearch', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        if Config.Debug then
            print('[Work Orders] Stop search failed: Player not found')
        end
        cb({ success = false })
        return
    end

    local citizenid = Player.PlayerData.citizenid
    playerSearchStates[citizenid] = false

    -- Stop the generation thread and wait for it to terminate
    if playerSearchThreads[citizenid] then
        playerSearchThreads[citizenid] = false
        -- Wait up to 200ms for thread to terminate
        local waited = 0
        while playerSearchThreads[citizenid] and waited < 200 do
            Wait(10)
            waited = waited + 10
        end
        playerSearchThreads[citizenid] = nil
    end

    -- Preserve accepted orders, drop available orders WITHOUT penalty when stopping search
    local accepted = getAcceptedOrders(citizenid)
    AcceptedOrders[citizenid] = accepted
    AvailableOrders[citizenid] = {}
    
    print(string.format('[Work Orders] Player %s stopped searching - cleared available orders WITHOUT XP penalty', citizenid))

    -- Get complete data for response
    local progress = initPlayerProgress(citizenid)
    local levelData = getPlayerLevelData(progress.level)
    local nextLevelXP = getNextLevelXP(progress.level)
    local currentLevelXP = levelData.minXP

    -- Notify client to update UI state
    local src = Player.PlayerData.source
    TriggerClientEvent('pf-mechanicjob:client:workOrdersReady', src, {
        availableOrders = {},
        acceptedOrders = accepted,
        isSearching = false
    })

    if Config.Debug then
        print(string.format('[Work Orders] Player %s (ID: %s) stopped searching - Cleared available jobs',
            citizenid, source))
    end

    -- Return complete data structure matching getData
    cb({
        success = true,
        level = progress.level,
        levelName = levelData.name,
        xp = progress.xp,
        currentLevelXP = currentLevelXP,
        nextLevelXP = nextLevelXP,
        totalJobs = progress.totalJobs,
        payMultiplier = levelData.payMultiplier,
        maxOffers = levelData.maxOffers,
        availableOrders = {},
        acceptedOrders = accepted,
        isSearching = false
    })
end)

-- ============================================================================
-- REPAIR COMPLETION
-- ============================================================================

-- Get order data for client
QBCore.Functions.CreateCallback('pf_mech:workorders:getOrderData', function(source, cb, orderId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        cb(nil)
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    local accepted = getAcceptedOrders(citizenid)
    
    -- Find the order
    for _, order in ipairs(accepted) do
        if order.id == orderId then
            cb(order)
            return
        end
    end
    
    cb(nil)
end)

-- Handle repair completion from client
RegisterNetEvent('pf_mech:workorders:completeRepair', function(orderId, usedItem)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    local accepted = getAcceptedOrders(citizenid)
    local progress = initPlayerProgress(citizenid)
    local levelData = getPlayerLevelData(progress.level)
    
    -- Find the order
    local orderIndex = nil
    local order = nil
    for i, o in ipairs(accepted) do
        if o.id == orderId then
            orderIndex = i
            order = o
            break
        end
    end
    
    if not order or not orderIndex then
        TriggerClientEvent('QBCore:Notify', source, 'Work order not found', 'error')
        return
    end

    print('[DEBUG] Server completeRepair triggered for orderId:', orderId, 'citizenid:', citizenid)

    -- The required part comes from the server's order, not the item name the client sends
    local done, why = workOrderDone(source, Player, order)
    if not done then
        TriggerClientEvent('QBCore:Notify', source, why, 'error')
        return
    end

    -- Calculate payout with level multiplier
    local payout = math.floor(order.basePay * levelData.payMultiplier)
    
    -- Award money and XP; on failure the order stays accepted so completing again retries with the same key
    order.payoutId = order.payoutId or PFPayout.NewId()
    local paid, res = PFPayout.Pay(Player, 'bank', payout, {
        key = ('pf-mechanicjob:workorder:%s:%s'):format(order.payoutId, citizenid),
        reason = 'mechanic-work-order',
    })
    if not paid then return end
    -- A key that was already paid means this order was rewarded before: no XP or stats again
    if not res.duplicate then
        local newProgress = awardXP(citizenid, order.xpReward, source)

        -- Update stats
        newProgress.totalJobs = newProgress.totalJobs + 1
        recordCompletedWorkOrder(citizenid, order, payout)
        savePlayerProgress(citizenid)
    end

    -- Remove from accepted orders (the list may have changed while the bank call ran)
    for i, o in ipairs(accepted) do
        if o == order then table.remove(accepted, i) break end
    end
    print('[DEBUG] Removed order from accepted orders. Remaining:', #accepted)
    
    if Config.Debug then
        print(string.format('[Work Orders] Player %s completed order #%d: $%d, +%d XP', 
            citizenid, orderId, payout, order.xpReward))
    end
    
    TriggerClientEvent('QBCore:Notify', source, 
        string.format('Job completed! Earned $%d and %d XP', payout, order.xpReward), 
        'success', 5000)
    
    -- Update UI
    TriggerClientEvent('pf_mech:tablet:updateWorkOrders', source)
    TriggerClientEvent('pf_mech:workorders:client:completed', source, orderId)
    TriggerClientEvent('pf-mechanicjob:client:workOrdersReady', source, {
        availableOrders = getAvailableOrders(citizenid),
        acceptedOrders = accepted,
        isSearching = playerSearchStates[citizenid] or false
    })
    
    -- Remove vehicle on client
    if Config.WorkOrderSystem.deleteVehicleOnComplete then
        if Config.Debug then
            PFMech.Debug('[DEBUG] Triggering client vehicle removal for orderId:', orderId)
        end
        TriggerClientEvent('pf_mech:workorder:removeVehicle', source)
    end
end)

-- ============================================================================
-- ADMIN COMMANDS (Debug)
-- ============================================================================

if Config.Debug then
    RegisterCommand('setmechlevel', function(source, args)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        
        local level = tonumber(args[1])
        if not level or level < 1 or level > #Config.WorkOrderSystem.levels then
            TriggerClientEvent('QBCore:Notify', source, 'Invalid level (1-' .. #Config.WorkOrderSystem.levels .. ')', 'error')
            return
        end
        
        local citizenid = Player.PlayerData.citizenid
        local progress = initPlayerProgress(citizenid)
        
        local levelData = Config.WorkOrderSystem.levels[level]
        progress.level = level
        progress.xp = levelData.minXP
        
        savePlayerProgress(citizenid)
        
        TriggerClientEvent('QBCore:Notify', source, 
            string.format('Level set to %d (%s)', level, levelData.name), 'success')
    end, false)
    
    RegisterCommand('addmechxp', function(source, args)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        
        local amount = tonumber(args[1]) or 100
        local citizenid = Player.PlayerData.citizenid
        
        awardXP(citizenid, amount, source)
        
        TriggerClientEvent('QBCore:Notify', source, string.format('Added %d XP', amount), 'success')
    end, false)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Create database table if it doesn't exist
MySQL.ready(function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `pf_mechanic_progress` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `level` int(11) DEFAULT 1,
            `xp` int(11) DEFAULT 0,
            `total_jobs` int(11) DEFAULT 0,
            `last_refresh` int(11) DEFAULT 0,
            PRIMARY KEY (`id`),
            UNIQUE KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- One-time migration: copy any legacy pf_mech_profiles rows into pf_mechanic_progress
    MySQL.Async.execute([[
        INSERT INTO pf_mechanic_progress (citizenid, level, xp, total_jobs, last_refresh)
        SELECT citizenid, COALESCE(rank, 1) as level, COALESCE(xp, 0) as xp, COALESCE(jobs_done, 0) as total_jobs, 0 as last_refresh
        FROM pf_mech_profiles
        ON DUPLICATE KEY UPDATE
            level = VALUES(level),
            xp = VALUES(xp),
            total_jobs = VALUES(total_jobs)
    ]], {}, function(rows)
        if Config.Debug then
            print(string.format('[PF Mechanic] Legacy migration completed: %s row(s) merged from pf_mech_profiles', rows or 0))
        end
    end)
    
    if Config.Debug then
        print('[PF Mechanic] Work order system database initialized')
    end
end)

if Config.Debug then
    print('[PF Mechanic] Work order level system loaded (debug on)')
end
