local QBCore = exports['pfm-core']:GetCoreObject()

local Advanced = Config.AdvancedSystems or {}
local LiftStateByPlate = {}
local AlignmentStarted = {}   -- [src] = os.time() the alignment rack tool was used

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
        -- the alignment is finished on the server, which needs to know the rack really ran
        if itemName == 'alignment_rack_tool' then AlignmentStarted[source] = os.time() end
        TriggerClientEvent('pf-mechanicjob:client:advanced:useTool', source, itemName, item)
    end)
end

-- ============================================================================
-- Driver wear and mileage reports ('pf_mech:server:setState')
-- ============================================================================
-- partDamage and mileage are vehicle state bags only the server writes (sv_stateBagStrictMode).
-- Wear and distance are simulated in the driver's game (client/damage.lua, client/mileage_hud.lua),
-- which reports them here. A report can only add: no part gets better through it (repairs go
-- through the item-checked repair events) and mileage grows by at most what the car could have
-- driven since the last report. Only the driver reports, except for the job wear of a work-order
-- car, which its mechanic sets up from wherever he is (the car spawns across the map).
local WEAR_PARTS = {
    alternator = true, sparkplugs = true, carbattery = true, oil = true, oil_filter = true,
    brakes = true, suspension = true, axle = true, fuel_injector = true, powersteeringpump = true,
    radiator = true, power_steering_fluid = true, transmissionfluid = true, brakefluid = true,
    coolant = true, engine_part = true, body_part = true,
}
local MAX_MILES_PER_SECOND = 0.12     -- about 430 mph
local MILEAGE_SLACK = 0.5
local VEHICLE_STATE_WINDOW, VEHICLE_STATE_MAX = 10, 40
local VehicleStateRate = {}           -- [src] = { start, count }
local LastMileage = {}                -- [vehicle] = { at, value } of the last accepted mileage

local function wearValue(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.floor(math.max(0, math.min(100, v)) * 100 + 0.5) / 100
end

-- `current` with every reported part raised to the reported value when that is higher.
local function mergeWear(current, reported)
    local merged = {}
    for k, v in pairs(type(current) == 'table' and current or {}) do merged[k] = v end
    for key, value in pairs(reported) do
        if WEAR_PARTS[key] then
            local v = wearValue(value)
            if v and v > (tonumber(merged[key]) or 0) then merged[key] = v end
        elseif key == 'tires' and type(value) == 'table' then
            local tires = {}
            for tk, tv in pairs(type(merged.tires) == 'table' and merged.tires or {}) do tires[tk] = tv end
            for tk, tv in pairs(value) do
                tk = tostring(tk)
                local v = wearValue(tv)
                if v and #tk <= 3 and tk:match('^%w+$') and v > (tonumber(tires[tk]) or 0) then tires[tk] = v end
            end
            merged.tires = tires
        end
    end
    return merged
end

local function vehicleStateRateOk(src)
    local now = os.time()
    local rate = VehicleStateRate[src]
    if not rate or now - rate.start >= VEHICLE_STATE_WINDOW then
        rate = { start = now, count = 0 }
        VehicleStateRate[src] = rate
    end
    rate.count = rate.count + 1
    return rate.count <= VEHICLE_STATE_MAX
end

RegisterNetEvent('pf_mech:server:setState', function(netId, key, value)
    local src = source
    if key ~= 'partDamage' and key ~= 'mileage' then return end
    if not getPlayer(src) or not vehicleStateRateOk(src) then return end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local ped = GetPlayerPed(src)
    local driver = GetPedInVehicleSeat(veh, -1)
    local isDriver = ped and ped ~= 0 and driver == ped
    local st = Entity(veh).state

    if key == 'partDamage' then
        if type(value) ~= 'table' then return end
        -- the driver's own wear; or the job wear of the empty work-order car the server knows this
        -- on-duty mechanic spawned for his accepted order (any player near any empty car used to pass)
        if not isDriver then
            if driver and driver ~= 0 then return end
            if not (PFMech and PFMech.IsWorkOrderCar and PFMech.IsWorkOrderCar(src, veh)) then return end
        end
        if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
        st:set('partDamage', mergeWear(st.partDamage, value), true)
        return
    end

    -- mileage: the driver only, never down, never faster than a car can go
    value = tonumber(value)
    if not isDriver or not value or value ~= value or value == math.huge then return end
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local now = os.time()
    local current = tonumber(st.mileage) or 0
    local last = LastMileage[veh]
    local allowed = MILEAGE_SLACK + (last and math.min(60, math.max(0, now - last.at)) * MAX_MILES_PER_SECOND or 0)
    if value < current or value - current > allowed then
        if not last then LastMileage[veh] = { at = now, value = current } end
        return
    end
    LastMileage[veh] = { at = now, value = value }
    st:set('mileage', value, true)
end)

AddEventHandler('entityRemoved', function(entity)
    LastMileage[entity] = nil
end)

-- ============================================================================
-- Alignment rack
-- ============================================================================
-- partDamage is a vehicle state bag only the server writes (sv_stateBagStrictMode); the client used
-- to lower the wear itself. The server applies the configured reduction once per use of the tool,
-- after the rack's run time, to a car beside the player who still has the tool.
local ALIGN_REACH = 7.0
local ALIGN_MAX_SECONDS = 600

local function inPitBay(coords)
    for _, zone in ipairs(((Advanced.PitBays or {}).Zones) or {}) do
        if zone.coords and #(coords - zone.coords) <= (zone.radius or 6.0) then return true end
    end
    return false
end

RegisterNetEvent('pf-mechanicjob:server:advanced:completeAlignment', function(netId)
    local src = source
    local Player = getPlayer(src)
    if not Player then return end
    local alignCfg = Advanced.Alignment or {}
    if Advanced.Enabled ~= true or alignCfg.Enabled == false then return end
    local startedAt = AlignmentStarted[src]
    AlignmentStarted[src] = nil
    if not startedAt then return end

    local pit = Advanced.PitBays or {}
    local mult = pit.Enabled and (tonumber(pit.ServiceSpeedMultiplier) or 1.0) or 1.0
    local minSeconds = math.floor((tonumber(alignCfg.BaseDurationMs) or 20000) * math.min(1.0, mult) / 1000) - 1
    local elapsed = os.time() - startedAt
    if elapsed < minSeconds or elapsed > ALIGN_MAX_SECONDS then return end
    if not hasItem(Player, 'alignment_rack_tool', 1) then return end

    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local pcoords = GetEntityCoords(GetPlayerPed(src))
    if #(pcoords - GetEntityCoords(veh)) > ALIGN_REACH then return end
    if pit.Enabled and pit.RequireForAlignmentRack and not inPitBay(pcoords) then
        TriggerClientEvent('QBCore:Notify', src, 'The alignment rack needs a pit bay', 'error')
        return
    end

    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local st = Entity(veh).state
    local partDamage = type(st.partDamage) == 'table' and st.partDamage or {}
    local reduction = tonumber(alignCfg.WearReduction) or 12
    partDamage.suspension = math.max(0, (tonumber(partDamage.suspension) or 0) - reduction)
    partDamage.axle = math.max(0, (tonumber(partDamage.axle) or 0) - math.floor(reduction * 0.8))
    st:set('partDamage', partDamage, true)
    TriggerClientEvent('QBCore:Notify', src, ('Alignment complete for %s'):format(normPlate(GetVehicleNumberPlateText(veh))), 'success')
end)

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
    AlignmentStarted[source] = nil
    VehicleStateRate[source] = nil
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
