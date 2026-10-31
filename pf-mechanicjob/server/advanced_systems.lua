local QBCore = exports['pfm-core']:GetCoreObject()

local Advanced = Config.AdvancedSystems or {}
local LiftStateByPlate = {}

local function normPlate(plate)
    return tostring(plate or ''):gsub('%s+', ''):upper()
end

local function getPlayer(src)
    return QBCore.Functions.GetPlayer(src)
end

local function hasItem(Player, itemName, amount)
    if not Player then return false end
    local itm = Player.Functions.GetItemByName(itemName)
    return itm and (itm.amount or 0) >= (amount or 1)
end

local function removeItem(Player, src, itemName, amount)
    if not Player then return false end
    amount = amount or 1
    local ok = Player.Functions.RemoveItem(itemName, amount)
    if ok then
        local shared = QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName]
        if shared then
            TriggerClientEvent('inventory:client:ItemBox', src, shared, 'remove', amount)
        end
    end
    return ok
end

local function addItem(Player, src, itemName, amount)
    if not Player then return false end
    amount = amount or 1
    local ok = Player.Functions.AddItem(itemName, amount)
    if ok then
        local shared = QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName]
        if shared then
            TriggerClientEvent('inventory:client:ItemBox', src, shared, 'add', amount)
        end
    end
    return ok
end

local function integrationEmit(eventNames, payload)
    for _, eventName in ipairs(eventNames or {}) do
        TriggerEvent(eventName, payload)
    end
end

-- ============================================================================
-- SQL bootstrap (skill tree persistence)
-- ============================================================================

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pf_mechanic_skills (
            citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
            unlocked_json LONGTEXT NULL,
            spent_points INT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

-- ============================================================================
-- Utility callbacks for client workflows
-- ============================================================================

QBCore.Functions.CreateCallback('pf-mechanicjob:server:advanced:hasItems', function(source, cb, needed)
    local Player = getPlayer(source)
    if not Player then cb(false) return end

    for itemName, amount in pairs(needed or {}) do
        if not hasItem(Player, itemName, amount) then
            cb(false)
            return
        end
    end

    cb(true)
end)

QBCore.Functions.CreateCallback('pf-mechanicjob:server:advanced:hasAnyItems', function(source, cb, options)
    local Player = getPlayer(source)
    if not Player then cb(nil) return end

    for _, option in ipairs(options or {}) do
        local valid = true
        for itemName, amount in pairs(option.items or {}) do
            if not hasItem(Player, itemName, amount) then
                valid = false
                break
            end
        end
        if valid then
            cb(option.id)
            return
        end
    end

    cb(nil)
end)

QBCore.Functions.CreateCallback('pf-mechanicjob:server:advanced:getLiftState', function(_, cb, plate)
    cb(LiftStateByPlate[normPlate(plate)] == true)
end)

RegisterNetEvent('pf-mechanicjob:server:advanced:setLiftState', function(plate, state)
    plate = normPlate(plate)
    if plate == '' then return end
    LiftStateByPlate[plate] = state == true
end)

-- ============================================================================
-- Useable tools
-- ============================================================================

local toolItems = {
    'alignment_rack_tool',
    'floor_jack',
    'jack_stands',
    'transmission_jack',
    'obd_scanner',
    'multimeter',
    'coolant_pressure_tester',
    'evap_smoke_machine',
    'chop_kit'
}

for _, itemName in ipairs(toolItems) do
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        TriggerClientEvent('pf-mechanicjob:client:advanced:useTool', source, itemName, item)
    end)
end

-- ============================================================================
-- Clutch workflow completion (full multi-step)
-- ============================================================================

RegisterNetEvent('pf-mechanicjob:server:advanced:completeClutchWorkflow', function(payload)
    local src = source
    local Player = getPlayer(src)
    if not Player then return end

    local plate = normPlate(payload and payload.plate)
    if plate == '' then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid vehicle plate', 'error')
        return
    end

    local clutchCfg = (Advanced.ClutchWorkflow or {})
    if clutchCfg.Enabled and clutchCfg.RequireLiftedVehicle and LiftStateByPlate[plate] ~= true then
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle must be lifted/secured first', 'error')
        return
    end

    if not hasItem(Player, 'service_clutch_replacement', 1) then
        TriggerClientEvent('QBCore:Notify', src, 'Missing clutch replacement service item', 'error')
        return
    end

    if clutchCfg.Enabled and clutchCfg.RequireTransmissionJack and not hasItem(Player, 'transmission_jack', 1) then
        TriggerClientEvent('QBCore:Notify', src, 'Transmission jack is required', 'error')
        return
    end

    if clutchCfg.Enabled and clutchCfg.RequireFlywheelServiceKit and not hasItem(Player, 'flywheel_service_kit', 1) then
        TriggerClientEvent('QBCore:Notify', src, 'Flywheel service kit is required', 'error')
        return
    end

    -- Optional consumables from workflow choices (bread trick path, etc.)
    for itemName, amount in pairs((payload and payload.consume) or {}) do
        if amount > 0 and not hasItem(Player, itemName, amount) then
            TriggerClientEvent('QBCore:Notify', src, ('Missing %s'):format(itemName), 'error')
            return
        end
    end

    local Engineering = require('server.engineering.sv_engineering')
    local ok = Engineering:ReplaceClutch(plate, 4000, tostring(src))
    if not ok then
        TriggerClientEvent('QBCore:Notify', src, 'Clutch workflow failed server-side', 'error')
        return
    end

    removeItem(Player, src, 'service_clutch_replacement', 1)
    for itemName, amount in pairs((payload and payload.consume) or {}) do
        if amount > 0 then
            removeItem(Player, src, itemName, amount)
        end
    end

    TriggerClientEvent('QBCore:Notify', src, 'Clutch service complete', 'success')

    local insuranceEvents = (((Advanced.Integrations or {}).Insurance or {}).EventNames or {})
    integrationEmit(insuranceEvents, {
        source = src,
        citizenid = Player.PlayerData.citizenid,
        plate = plate,
        service = 'clutch_replacement',
        cost = 4000,
        metadata = payload or {}
    })
end)

RegisterNetEvent('pf-mechanicjob:server:advanced:startClutchWorkflow', function()
    TriggerClientEvent('pf-mechanicjob:client:advanced:beginClutchWorkflow', source)
end)

-- ============================================================================
-- Diagnostics/tow/insurance integration events
-- ============================================================================

RegisterNetEvent('pf-mechanicjob:server:advanced:diagnosticReport', function(payload)
    local src = source
    local Player = getPlayer(src)
    if not Player then return end

    local insuranceEvents = (((Advanced.Integrations or {}).Insurance or {}).EventNames or {})
    integrationEmit(insuranceEvents, {
        source = src,
        citizenid = Player.PlayerData.citizenid,
        plate = normPlate(payload and payload.plate),
        service = 'diagnostic_scan',
        cost = tonumber(payload and payload.cost) or 0,
        metadata = payload
    })
end)

-- A mechanic who finds a car that cannot be driven orders a tow to their shop (pf-services
-- 'tow.recovery', worked by the tow job in the Dispatch app). The car must be right next to the
-- mechanic; its position comes from the server, and the shop's account pays the call-out fee (the
-- shop bills the customer at the register). It used to pass client-sent plate/coords to events
-- nothing handled.
local TowRequestCooldown = {} -- [citizenid] = os.time()
RegisterNetEvent('pf-mechanicjob:server:advanced:requestTow', function(payload)
    local src = source
    local Player = getPlayer(src)
    local job = Player and Player.PlayerData.job
    if not job or not Config.IsMechanicJob or not Config.IsMechanicJob(job.name) or not job.onduty then return end
    if type(payload) ~= 'table' then return end
    local plate = normPlate(payload.plate)
    if not plate or plate == '' or #plate > 16 then return end
    local cid = Player.PlayerData.citizenid
    if TowRequestCooldown[cid] and os.time() - TowRequestCooldown[cid] < 60 then return end

    local pos = GetEntityCoords(GetPlayerPed(src))
    local veh
    for _, v in ipairs(GetAllVehicles()) do
        if normPlate(GetVehicleNumberPlateText(v)) == plate and #(GetEntityCoords(v) - pos) <= 8.0 then veh = v break end
    end
    if not veh then return end
    TowRequestCooldown[cid] = os.time()

    local reason = type(payload.reason) == 'string' and payload.reason:sub(1, 40) or 'service_request'
    if GetResourceState('pf-services') == 'started' then
        local ci = Player.PlayerData.charinfo or {}
        local ok, res = pcall(function()
            return exports['pf-services']:CreateRequest({
                kind = 'tow.recovery',
                title = ('Tow %s to %s'):format(plate, job.label or job.name),
                details = ('Ordered by the mechanic (%s)'):format(reason:gsub('_', ' ')),
                coords = GetEntityCoords(veh),
                plate = plate,
                ref = { type = 'vehicle', id = plate },
                from = { type = 'job', id = job.name, name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', '') },
                payer = 'society:' .. job.name,
                -- delivered to a mechanic shop (the tow job's list of shops); the scan happens at the roadside
                meta = { shop = job.name, reason = reason },
            })
        end)
        if ok and res and res.ok then
            TriggerClientEvent('QBCore:Notify', src, res.existing and 'A tow is already on its way for this car' or 'Tow requested to your shop', 'success')
        else
            TriggerClientEvent('QBCore:Notify', src, 'No tow service is available', 'error')
        end
    end
    -- other tow resources may still listen (server-built payload, no client values)
    local towEvents = (((Advanced.Integrations or {}).Tow or {}).EventNames or {})
    integrationEmit(towEvents, { source = src, plate = plate, reason = reason, coords = GetEntityCoords(veh) })
end)

-- ============================================================================
-- Roadside + chop rewards
-- ============================================================================

-- Roadside jobs are tracked here: the client spawns the broken car and reports it, the server
-- records it, and pays only for that car once the server itself reads it as repaired, with the
-- mechanic next to it after a minimum repair time. (The job used to be started and finished by the
-- client alone, so a modified client could claim it with any plate, as often as it liked.)
-- [src] = { id, netId, plate, startedAt }
local RoadsideJobs = {}
local RoadsideLastStart = {} -- [citizenid] = os.time()

local function roadsideCfg() return Advanced.RoadsideService or {} end

local function isMechanicPlayer(Player)
    local job = Player and Player.PlayerData and Player.PlayerData.job
    return job ~= nil and Config.IsMechanicJob ~= nil and Config.IsMechanicJob(job.name) == true
end

RegisterNetEvent('pf-mechanicjob:server:advanced:startRoadside', function(netId)
    local src = source
    local Player = getPlayer(src)
    if not Player or not isMechanicPlayer(Player) then return end
    local cfg = roadsideCfg()
    if not (Advanced.Enabled and cfg.Enabled) then return end
    local current = RoadsideJobs[src]
    if current then
        -- a job whose car is gone can be replaced; a live one can't
        local old = NetworkGetEntityFromNetworkId(current.netId)
        if old and old ~= 0 and DoesEntityExist(old) then return end
        RoadsideJobs[src] = nil
    end
    local cid = Player.PlayerData.citizenid
    local now = os.time()
    local cooldown = tonumber(cfg.CooldownSeconds) or 180
    if RoadsideLastStart[cid] and now - RoadsideLastStart[cid] < cooldown then
        TriggerClientEvent('QBCore:Notify', src, 'No roadside calls right now. Try again shortly.', 'error')
        return
    end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(vehicle)) > 80.0 then return end
    RoadsideLastStart[cid] = now
    RoadsideJobs[src] = {
        id = PFPayout.NewId(),
        netId = tonumber(netId),
        plate = normPlate(GetVehicleNumberPlateText(vehicle)),
        startedAt = now,
    }
end)

AddEventHandler('playerDropped', function()
    RoadsideJobs[source] = nil
end)

RegisterNetEvent('pf-mechanicjob:server:advanced:completeRoadside', function(payload)
    local src = source
    local Player = getPlayer(src)
    if not Player then return end

    local job = RoadsideJobs[src]
    if not job then
        -- no call the server started (refused or already paid): stop the client reporting
        TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
        return
    end
    local roadside = roadsideCfg()
    if os.time() - job.startedAt < (tonumber(roadside.MinRepairSeconds) or 20) then return end
    local vehicle = NetworkGetEntityFromNetworkId(job.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        RoadsideJobs[src] = nil
        TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
        return
    end
    -- the server's own reading of the car, not the client's
    if GetVehicleEngineHealth(vehicle) < 900.0 or GetVehicleBodyHealth(vehicle) < 900.0 then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(vehicle)) > 15.0 then return end

    local minPay = tonumber(roadside.RewardMin) or 350
    local maxPay = tonumber(roadside.RewardMax) or 850
    local reward = math.random(minPay, maxPay)

    -- keyed by the server-side job id: one payment per roadside job
    local paid, res = PFPayout.Pay(Player, 'bank', reward, {
        key = ('pf-mechanicjob:roadside:%s:%s'):format(job.id, Player.PlayerData.citizenid),
        reason = 'roadside-service-complete',
    })
    if not paid then return end
    RoadsideJobs[src] = nil
    TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
    if res.duplicate then return end
    TriggerClientEvent('QBCore:Notify', src, ('Roadside service complete: $%d'):format(reward), 'success')

    MySQL.update.await('UPDATE pf_mechanic_progress SET xp = xp + ? WHERE citizenid = ?', {
        tonumber(roadside.XPReward) or 40,
        Player.PlayerData.citizenid
    })

    local insuranceEvents = (((Advanced.Integrations or {}).Insurance or {}).EventNames or {})
    integrationEmit(insuranceEvents, {
        source = src,
        citizenid = Player.PlayerData.citizenid,
        plate = job.plate,
        service = 'roadside_service',
        cost = reward,
        metadata = payload
    })
end)

-- Chopping pays salvage for a car the player is sitting in, inside a chop zone (checked here), and
-- the server removes the car. It used to pay anyone who sent the event, as often as they liked.
local ChopLast = {} -- [citizenid] = os.time()
local CHOP_MIN_SECONDS = 27 -- the three client progress bars

RegisterNetEvent('pf-mechanicjob:server:advanced:completeChop', function(payload)
    local src = source
    local Player = getPlayer(src)
    if not Player then return end
    local chopCfg = Advanced.ChopShop or {}
    if not (Advanced.Enabled and chopCfg.Enabled) then return end
    if type(payload) ~= 'table' then return end

    local vehicle = NetworkGetEntityFromNetworkId(tonumber(payload.netId) or 0)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= vehicle then return end
    local coords = GetEntityCoords(vehicle)
    local inZone = false
    for _, zone in ipairs(chopCfg.Zones or {}) do
        if zone.coords and #(coords - zone.coords) <= (zone.radius or 15.0) then inZone = true break end
    end
    if not inZone then return end
    local cid = Player.PlayerData.citizenid
    local now = os.time()
    if ChopLast[cid] and now - ChopLast[cid] < CHOP_MIN_SECONDS then return end
    ChopLast[cid] = now
    DeleteEntity(vehicle)

    local rewards = (chopCfg.RewardItems or {})
    for _, def in ipairs(rewards) do
        local amount = math.random(tonumber(def.min) or 1, tonumber(def.max) or 1)
        addItem(Player, src, def.item, amount)
    end

    TriggerClientEvent('QBCore:Notify', src, 'Chop complete, salvage collected', 'success')
end)

-- ============================================================================
-- Skill tree callbacks/events
-- ============================================================================

local function getProgress(citizenid)
    return MySQL.single.await('SELECT level, xp FROM pf_mechanic_progress WHERE citizenid = ? LIMIT 1', { citizenid }) or { level = 1, xp = 0 }
end

local function getSkillRow(citizenid)
    local row = MySQL.single.await('SELECT unlocked_json, spent_points FROM pf_mechanic_skills WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row then
        MySQL.insert.await('INSERT INTO pf_mechanic_skills (citizenid, unlocked_json, spent_points) VALUES (?, ?, 0)', { citizenid, json.encode({}) })
        return { unlocked_json = json.encode({}), spent_points = 0 }
    end
    return row
end

local function decodeUnlocked(raw)
    local ok, data = pcall(function() return json.decode(raw or '{}') end)
    if not ok or type(data) ~= 'table' then return {} end
    return data
end

QBCore.Functions.CreateCallback('pf-mechanicjob:server:advanced:getSkillTree', function(source, cb)
    local Player = getPlayer(source)
    if not Player then cb(nil) return end

    local citizenid = Player.PlayerData.citizenid
    local progress = getProgress(citizenid)
    local row = getSkillRow(citizenid)
    local unlocked = decodeUnlocked(row.unlocked_json)

    local pointsPerLevel = (((Advanced.SkillTree or {}).PointsPerLevel) or 1)
    local totalPoints = (tonumber(progress.level) or 1) * pointsPerLevel
    local spent = tonumber(row.spent_points) or 0

    cb({
        nodes = ((Advanced.SkillTree or {}).Nodes or {}),
        unlocked = unlocked,
        availablePoints = math.max(0, totalPoints - spent),
        level = tonumber(progress.level) or 1,
        xp = tonumber(progress.xp) or 0,
        spent = spent,
        totalPoints = totalPoints
    })
end)

RegisterNetEvent('pf-mechanicjob:server:advanced:unlockSkill', function(skillId)
    local src = source
    local Player = getPlayer(src)
    if not Player then return end

    local tree = (Advanced.SkillTree or {})
    local node = (tree.Nodes or {})[skillId]
    if not node then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid skill node', 'error')
        return
    end

    local citizenid = Player.PlayerData.citizenid
    local progress = getProgress(citizenid)
    local row = getSkillRow(citizenid)
    local unlocked = decodeUnlocked(row.unlocked_json)

    if unlocked[skillId] == true then
        TriggerClientEvent('QBCore:Notify', src, 'Skill already unlocked', 'error')
        return
    end

    for _, req in ipairs(node.requires or {}) do
        if unlocked[req] ~= true then
            TriggerClientEvent('QBCore:Notify', src, 'Missing prerequisite skill', 'error')
            return
        end
    end

    local pointsPerLevel = (tree.PointsPerLevel or 1)
    local totalPoints = (tonumber(progress.level) or 1) * pointsPerLevel
    local spent = tonumber(row.spent_points) or 0
    local cost = tonumber(node.cost) or 1
    local available = math.max(0, totalPoints - spent)

    if available < cost then
        TriggerClientEvent('QBCore:Notify', src, 'Not enough skill points', 'error')
        return
    end

    unlocked[skillId] = true
    MySQL.update.await('UPDATE pf_mechanic_skills SET unlocked_json = ?, spent_points = ? WHERE citizenid = ?', {
        json.encode(unlocked),
        spent + cost,
        citizenid
    })

    TriggerClientEvent('QBCore:Notify', src, ('Unlocked skill: %s'):format(node.label or skillId), 'success')
end)
