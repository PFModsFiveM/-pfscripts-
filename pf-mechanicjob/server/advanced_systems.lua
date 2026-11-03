local QBCore = exports['pfm-core']:GetCoreObject()

local Advanced = Config.AdvancedSystems or {}
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

-- ============================================================================
-- Floor jack (lift state)
-- ============================================================================
-- A car is lifted by a mechanic with a floor jack standing at it; the server keeps it per car with
-- who lifted it, and forgets it when the car is gone. (Any plate string used to be marked lifted,
-- from anywhere and without a job or a jack.)
local LIFT_REACH = 6.0      -- the jack is used on a car within 5 m (client), plus slack
local WORK_REACH = 7.0      -- clutch and scans: the client picks a car within 5.5 m
local Lifted = {}              -- [vehicle] = { by = src, at = os.time() }

local function isMechanicPlayer(Player)
    local job = Player and Player.PlayerData and Player.PlayerData.job
    return job ~= nil and Config.IsMechanicJob ~= nil and Config.IsMechanicJob(job.name) == true
end

-- The car behind a client net id, within reach of the player (both positions on the server).
local function carNear(src, netId, reach)
    netId = tonumber(netId)
    if not netId or netId <= 0 or netId ~= math.floor(netId) then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > reach then return nil end
    return veh
end

QBCore.Functions.CreateCallback('pf-mechanicjob:server:advanced:getLiftState', function(source, cb, netId)
    local veh = carNear(source, netId, 15.0)
    cb(veh ~= nil and Lifted[veh] ~= nil)
end)

RegisterNetEvent('pf-mechanicjob:server:advanced:setLiftState', function(netId, state)
    local src = source
    local Player = getPlayer(src)
    if not isMechanicPlayer(Player) or not hasItem(Player, 'floor_jack', 1) then return end
    local veh = carNear(src, netId, LIFT_REACH)
    if not veh then return end
    if state == true then
        Lifted[veh] = { by = src, at = os.time() }
    else
        Lifted[veh] = nil
    end
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
-- (shared/tow_check.lua PFMechTow.WearParts lists the same parts for the client)
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

-- Repairs against in-flight wear reports. The driver's game computes a report from the wear it
-- last saw; a report sent before a repair reached the driver carries the old, higher values, and the
-- merge (wear only goes up) used to put them back: the repair was undone. The server keeps a wear
-- epoch per car ('wearEpoch', a state bag only the server sets): it goes up whenever any part's wear
-- goes down on the server (a repair, the alignment rack, an admin reset), and a report counts only
-- when it carries the epoch it was computed against.
-- Every repair on the server calls PFMech.MarkWearRepaired(veh) right after it lowers the wear, so
-- the new epoch reaches clients after the new wear (a client never pairs the new epoch with the old
-- wear). A lowering made anywhere else is caught by the next report: the car's wear is below what
-- the server last saw (KnownWear), so the epoch goes up and that report is dropped.
PFMech = PFMech or {}
local KnownWear = {}                  -- [vehicle] = the part wear the server last saw on the car

local function wearSnapshot(pd)
    local out = {}
    if type(pd) ~= 'table' then return out end
    for part in pairs(WEAR_PARTS) do
        local v = tonumber(pd[part])
        if v then out[part] = v end
    end
    if type(pd.tires) == 'table' then
        local tires = {}
        for tk, tv in pairs(pd.tires) do
            local v = tonumber(tv)
            if v then tires[tostring(tk)] = v end
        end
        out.tires = tires
    end
    return out
end

-- true when some part (or tyre) of `pd` is less worn than in the snapshot `known`
local function wearLowered(known, pd)
    if not known then return false end
    pd = type(pd) == 'table' and pd or {}
    for part, v in pairs(known) do
        if part == 'tires' then
            local now = type(pd.tires) == 'table' and pd.tires or {}
            for tk, tv in pairs(v) do
                if (tonumber(now[tk]) or 0) < tv - 0.001 then return true end
            end
        elseif (tonumber(pd[part]) or 0) < v - 0.001 then
            return true
        end
    end
    return false
end

local function currentWearEpoch(veh)
    return math.floor(tonumber(Entity(veh).state.wearEpoch) or 0)
end

local function bumpWearEpoch(veh)
    local st = Entity(veh).state
    st:set('wearEpoch', currentWearEpoch(veh) + 1, true)
end

-- Records the car's wear as the server sees it now; a part that went down starts a new epoch.
local function observeWear(veh, pd)
    if wearLowered(KnownWear[veh], pd) then bumpWearEpoch(veh) end
    KnownWear[veh] = wearSnapshot(pd)
end

--- For server code that has just lowered a car's partDamage: reports computed before it are refused.
function PFMech.MarkWearRepaired(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    bumpWearEpoch(veh)
    KnownWear[veh] = wearSnapshot(Entity(veh).state.partDamage)
    -- a wear save in flight holds the wear from before this repair: the saver snaps the car again now
    -- (server/garage_sync.lua), while it is still here
    if PFMech.WearRepaired then PFMech.WearRepaired(veh) end
end

-- Keeps KnownWear current as the server changes a car's wear (a restore, NOS wear, a report). A
-- lowering is not taken in here: this handler runs before the new value is stored, so a new epoch
-- set now would reach clients ahead of the lowered wear. KnownWear keeps the higher values instead,
-- and MarkWearRepaired or the next report raises the epoch after the wear is stored.
if type(AddStateBagChangeHandler) == 'function' and type(GetEntityFromStateBagName) == 'function' then
    AddStateBagChangeHandler('partDamage', nil, function(bagName, _, value)
        local veh = GetEntityFromStateBagName(bagName)
        if not veh or veh == 0 or not DoesEntityExist(veh) then return end
        if not wearLowered(KnownWear[veh], value) then KnownWear[veh] = wearSnapshot(value) end
    end)
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

RegisterNetEvent('pf_mech:server:setState', function(netId, key, value, wearEpoch)
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
        -- computed before the last repair reached this client: it would put the old wear back
        observeWear(veh, st.partDamage)
        if math.floor(tonumber(wearEpoch) or 0) ~= currentWearEpoch(veh) then return end
        local merged = mergeWear(st.partDamage, value)
        st:set('partDamage', merged, true)
        KnownWear[veh] = wearSnapshot(merged)
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
    KnownWear[entity] = nil
    Lifted[entity] = nil
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
    PFMech.MarkWearRepaired(veh)
    TriggerClientEvent('QBCore:Notify', src, ('Alignment complete for %s'):format(normPlate(GetVehicleNumberPlateText(veh))), 'success')
end)

-- ============================================================================
-- Clutch workflow (full multi-step)
-- ============================================================================
-- The mechanic starts the job at a lifted car (the server records when and which car), works
-- through the client's steps (about 70 s), and the server completes it only for that car, still
-- beside the mechanic and lifted by them, after the steps' minimum time. The plate, the cost and
-- the pilot bearing consumable are the server's (the client used to name any plate from anywhere,
-- skip the steps, and pick which items were taken).
local CLUTCH_MIN_SECONDS = 60
local CLUTCH_MAX_SECONDS = 900
local CLUTCH_COST = 4000
local ClutchJobs = {}          -- [src] = { veh, at }

-- The pilot bearing step: a puller, or the bread trick (hammer + socket + one slice, consumed).
local PILOT_METHODS = {
    pulley_puller = { needs = { pulley_puller = 1 }, consume = {} },
    bread_method = { needs = { mechanic_hammer = 1, mechanic_socket = 1, sliced_bread = 1 }, consume = { sliced_bread = 1 } },
}

local function clutchCfg() return Advanced.ClutchWorkflow or {} end

-- Shared checks of start and completion. Returns the car or nil with a message.
local function clutchCar(src, Player, netId)
    if not isMechanicPlayer(Player) then return nil, 'Only mechanics can replace a clutch' end
    local veh = carNear(src, netId, WORK_REACH)
    if not veh then return nil, 'The car must be right next to you' end
    local cfg = clutchCfg()
    if cfg.Enabled and cfg.RequireLiftedVehicle and not (Lifted[veh] and Lifted[veh].by == src) then
        return nil, 'Vehicle must be lifted/secured first'
    end
    if not hasItem(Player, 'service_clutch_replacement', 1) then return nil, 'Missing clutch replacement service item' end
    if cfg.Enabled and cfg.RequireTransmissionJack and not hasItem(Player, 'transmission_jack', 1) then return nil, 'Transmission jack is required' end
    if cfg.Enabled and cfg.RequireFlywheelServiceKit and not hasItem(Player, 'flywheel_service_kit', 1) then return nil, 'Flywheel service kit is required' end
    return veh
end

QBCore.Functions.CreateCallback('pf-mechanicjob:server:advanced:startClutch', function(source, cb, netId)
    local src = source
    local Player = getPlayer(src)
    local veh, why = clutchCar(src, Player, netId)
    if not veh then cb(false, why) return end
    ClutchJobs[src] = { veh = veh, at = os.time() }
    cb(true)
end)

RegisterNetEvent('pf-mechanicjob:server:advanced:completeClutchWorkflow', function(payload)
    local src = source
    local Player = getPlayer(src)
    if not Player or type(payload) ~= 'table' then return end
    local job = ClutchJobs[src]
    if not job then
        TriggerClientEvent('QBCore:Notify', src, 'Start the clutch job at the car first', 'error')
        return
    end
    local elapsed = os.time() - job.at
    if elapsed > CLUTCH_MAX_SECONDS then ClutchJobs[src] = nil return end
    if elapsed < CLUTCH_MIN_SECONDS then
        TriggerClientEvent('QBCore:Notify', src, 'The clutch job is not finished yet', 'error')
        return
    end
    local veh, why = clutchCar(src, Player, payload.netId)
    if not veh or veh ~= job.veh then
        TriggerClientEvent('QBCore:Notify', src, why or 'That is not the car you started on', 'error')
        return
    end
    local methodName = payload.pilotBearingMethod
    local method = type(methodName) == 'string' and PILOT_METHODS[methodName] or nil
    if not method then
        TriggerClientEvent('QBCore:Notify', src, 'Need pulley puller OR hammer + socket + sliced bread for pilot bearing step', 'error')
        return
    end
    for itemName, amount in pairs(method.needs) do
        if not hasItem(Player, itemName, amount) then
            TriggerClientEvent('QBCore:Notify', src, ('Missing %s'):format(itemName), 'error')
            return
        end
    end

    local plate = normPlate(GetVehicleNumberPlateText(veh))
    if plate == '' or #plate > 8 then return end
    ClutchJobs[src] = nil
    local Engineering = require('server.engineering.sv_engineering')
    local ok = Engineering:ReplaceClutch(plate, CLUTCH_COST, tostring(src))
    if not ok then
        TriggerClientEvent('QBCore:Notify', src, 'Clutch workflow failed server-side', 'error')
        return
    end

    removeItem(Player, src, 'service_clutch_replacement', 1)
    for itemName, amount in pairs(method.consume) do removeItem(Player, src, itemName, amount) end

    TriggerClientEvent('QBCore:Notify', src, 'Clutch service complete', 'success')

    local insuranceEvents = (((Advanced.Integrations or {}).Insurance or {}).EventNames or {})
    integrationEmit(insuranceEvents, {
        source = src,
        citizenid = Player.PlayerData.citizenid,
        plate = plate,
        service = 'clutch_replacement',
        cost = CLUTCH_COST,
        metadata = { pilotBearingMethod = methodName }
    })
end)

-- ============================================================================
-- Diagnostics/tow/insurance integration events
-- ============================================================================
-- A scan report for insurance resources: built from server data only (the scan's cost from the
-- config, the plate of the car beside the mechanic, the tool they hold), at most one per player per
-- DIAG_RATE_SECONDS. The client's cost and its whole payload used to be passed on.
local DIAG_RATE_SECONDS = 30
local DiagLast = {}            -- [src] = os.time()

RegisterNetEvent('pf-mechanicjob:server:advanced:diagnosticReport', function(payload)
    local src = source
    local Player = getPlayer(src)
    if not Player or type(payload) ~= 'table' or not isMechanicPlayer(Player) then return end
    local diag = Advanced.Diagnostics or {}
    local tool = payload.tool
    local cost = type(tool) == 'string' and (diag.Tools or {})[tool] and tonumber((diag.ScanCosts or {})[tool]) or nil
    if not cost or not hasItem(Player, tool, 1) then return end
    local veh = carNear(src, payload.netId, WORK_REACH)
    if not veh then return end
    local now = os.time()
    if DiagLast[src] and now - DiagLast[src] < DIAG_RATE_SECONDS then return end
    DiagLast[src] = now

    local insuranceEvents = (((Advanced.Integrations or {}).Insurance or {}).EventNames or {})
    integrationEmit(insuranceEvents, {
        source = src,
        citizenid = Player.PlayerData.citizenid,
        plate = normPlate(GetVehicleNumberPlateText(veh)),
        service = 'diagnostic_scan',
        tool = tool,
        cost = cost,
    })
end)

-- A shop's boss who finds a car that cannot be driven orders a tow to their shop (pf-services
-- 'tow.recovery', worked by the tow job in the Dispatch app). The shop's account pays the call-out
-- fee (the shop bills the customer at the register), so:
--   * only the shop's boss may order one (any on-duty mechanic used to be able to spend the shop's
--     money, e.g. for a friend in the tow job to collect the fees);
--   * only for a car the server itself reads as broken (Integrations.Tow): engine or body health
--     below the thresholds, a ruptured tank, or a part worn out completely; a drivable car is refused;
--   * the car is found by the server next to the boss (server positions, never the client's).
-- One order per plate at a time (the checks and CreateRequest wait; the plate and the boss are
-- locked before the first wait), and pf-services keeps one open request per car. The cooldown
-- starts only once pf-services has made a new request (a refused or failed order costs nothing),
-- and every refusal says why.
local TOW_COOLDOWN = 60
local TowRequestCooldown = {} -- [citizenid] = os.time() of the last tow ordered
local TowBusy = {}            -- [citizenid] = true while their order is being checked and made
local TowPending = {}         -- [plate] = true while an order for that car is being checked and made

local function towCfg() return ((Advanced.Integrations or {}).Tow) or {} end

-- The car with this plate within reach of the player (both positions read on the server).
local function towCarNear(src, plate)
    local reach = tonumber(towCfg().Reach) or 8.0
    local pos = GetEntityCoords(GetPlayerPed(src))
    for _, v in ipairs(GetAllVehicles()) do
        if DoesEntityExist(v) and normPlate(GetVehicleNumberPlateText(v)) == plate and #(GetEntityCoords(v) - pos) <= reach then
            return v
        end
    end
    return nil
end

-- The server's own reading of the car: broken enough to need a tow? (The rule is shared with the
-- client's offer: shared/tow_check.lua.)
local function vehicleNeedsTow(veh)
    local tank = type(GetVehiclePetrolTankHealth) == 'function' and GetVehiclePetrolTankHealth(veh) or nil
    return PFMechTow.Reason(GetVehicleEngineHealth(veh), GetVehicleBodyHealth(veh), tank,
        Entity(veh).state.partDamage, WEAR_PARTS) ~= nil
end

-- What the boss is told about a request pf-services made. A shop account that cannot cover the fee
-- does not stop the tow: pf-services posts it unpaid (escrow 'failed').
local function towOrderedMessage(res)
    if res.existing then return 'A tow is already on its way for this car' end
    local req = type(res.request) == 'table' and res.request or {}
    if req.escrow == 'failed' then return 'Tow requested to your shop. The shop account could not cover the fee, so it is posted unpaid' end
    return 'Tow requested to your shop'
end

-- Why pf-services made no request (res nil: the call itself failed).
local function towRefusedMessage(res)
    local code = type(res) == 'table' and res.error or nil
    if code == 'superseded' then
        local by = type(res.byKind) == 'string' and res.byKind or ''
        if by:find('impound', 1, true) then return 'The police already have this car on an impound order' end
        return 'Another service is already handling this car'
    end
    if code == 'insufficient_funds' then return 'The shop account cannot pay for a tow' end
    if code == 'bank_unavailable' then return 'The bank did not respond. No tow was ordered' end
    if code == 'db_error' then return 'The tow order could not be saved. Try again' end
    return 'No tow service is available'
end

-- Runs with the boss and the plate locked. Returns nothing; tells the boss the outcome.
local function orderShopTow(src, Player, job, veh, plate, reason)
    -- the car's saved wear first (a fresh spawn has none yet), then the checks again after that wait
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local now = getPlayer(src)
    local nowJob = now and now.PlayerData.job
    if not nowJob or nowJob.name ~= job.name or nowJob.isboss ~= true or not nowJob.onduty then
        if now then TriggerClientEvent('QBCore:Notify', src, 'Only the shop boss on duty can order a tow on the shop account', 'error') end
        return
    end
    if not DoesEntityExist(veh) or towCarNear(src, plate) ~= veh then
        TriggerClientEvent('QBCore:Notify', src, 'The car must be right next to you', 'error')
        return
    end
    if not vehicleNeedsTow(veh) then
        TriggerClientEvent('QBCore:Notify', src, 'This car can still be driven: no tow needed', 'error')
        return
    end
    local coords = GetEntityCoords(veh)

    if GetResourceState('pf-services') ~= 'started' then
        TriggerClientEvent('QBCore:Notify', src, 'No tow service is available', 'error')
    else
        local ci = Player.PlayerData.charinfo or {}
        local ok, res = pcall(function()
            return exports['pf-services']:CreateRequest({
                kind = 'tow.recovery',
                title = ('Tow %s to %s'):format(plate, job.label or job.name),
                details = ('Ordered by the shop (%s)'):format((reason:gsub('_', ' '))),
                coords = coords,
                plate = plate,
                ref = { type = 'vehicle', id = plate },
                from = { type = 'job', id = job.name, name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', '') },
                payer = 'society:' .. job.name,
                -- delivered to a mechanic shop (the tow job's list of shops); the scan happens at the roadside
                meta = { shop = job.name, reason = reason },
            })
        end)
        if ok and type(res) == 'table' and res.ok then
            -- only a new request spends the shop's money, so only that starts the cooldown
            if not res.existing then TowRequestCooldown[Player.PlayerData.citizenid] = os.time() end
            TriggerClientEvent('QBCore:Notify', src, towOrderedMessage(res), 'success')
        else
            if not ok then print('^1[pf-mechanicjob]^7 tow request failed: ' .. tostring(res)) end
            TriggerClientEvent('QBCore:Notify', src, towRefusedMessage(ok and res or nil), 'error')
        end
    end
    -- other tow resources may still listen (server-built payload, no client values)
    integrationEmit(towCfg().EventNames, { source = src, plate = plate, reason = reason, coords = coords })
end

RegisterNetEvent('pf-mechanicjob:server:advanced:requestTow', function(payload)
    local src = source
    local Player = getPlayer(src)
    local job = Player and Player.PlayerData.job
    if not job or not Config.IsMechanicJob or not Config.IsMechanicJob(job.name) or not job.onduty then return end
    if type(payload) ~= 'table' then return end
    local plate = normPlate(payload.plate)
    if plate == '' or #plate > 16 then return end
    if job.isboss ~= true then
        TriggerClientEvent('QBCore:Notify', src, 'Only the shop boss can order a tow on the shop account', 'error')
        return
    end
    local cid = Player.PlayerData.citizenid
    if TowBusy[cid] then
        TriggerClientEvent('QBCore:Notify', src, 'Your last tow order is still being made', 'error')
        return
    end
    local since = TowRequestCooldown[cid] and os.time() - TowRequestCooldown[cid]
    if since and since < TOW_COOLDOWN then
        TriggerClientEvent('QBCore:Notify', src, ('You can order another tow in %d s'):format(TOW_COOLDOWN - since), 'error')
        return
    end
    local veh = towCarNear(src, plate)
    if not veh then
        TriggerClientEvent('QBCore:Notify', src, 'The car must be right next to you', 'error')
        return
    end
    if TowPending[plate] then
        TriggerClientEvent('QBCore:Notify', src, 'A tow for this car is already being ordered', 'error')
        return
    end
    -- a short label from a fixed set of characters (it is shown in the Dispatch app)
    local reason = type(payload.reason) == 'string' and payload.reason:match('^[%w_]+$') and payload.reason:sub(1, 40) or 'service_request'

    TowBusy[cid], TowPending[plate] = true, true
    local ok, err = pcall(orderShopTow, src, Player, job, veh, plate, reason)
    TowBusy[cid], TowPending[plate] = nil, nil
    if not ok then print('^1[pf-mechanicjob]^7 tow order failed: ' .. tostring(err)) end
end)

-- ============================================================================
-- Roadside service
-- ============================================================================
-- The server makes the broken car itself: it spawns a car on the road spot the mechanic's game
-- picked (the server cannot read road nodes or ground height; it checks the spot is 50-150 m from
-- the mechanic) and marks its engine and body worn out (partDamage, set only by the server). It pays
-- for that car only, once this mechanic repaired both with parts (attemptRepair records every
-- item-consuming repair per car, PFMech.RepairLog), stands beside it and the minimum time has
-- passed; then it removes the car. A car the client named used to be accepted and was judged by
-- the health its owning client reports, so a mechanic's own healthy car paid every few minutes.
-- A call the mechanic gives up (/roadside cancel) or leaves too long (TimeoutSeconds) is closed and
-- its car removed, so it never blocks the next call. The cooldown still counts from its start.
-- Payment keys are numbered per attempt: a key the ledger clearly failed stays failed, so the next
-- try uses the next number; an unclear result keeps its key (and the call) until it settles.
local ROADSIDE_MIN_DIST, ROADSIDE_MAX_DIST = 50.0, 150.0
local ROADSIDE_MAX_DZ = 40.0
local ROADSIDE_PAY_REACH = 15.0
local ROADSIDE_PARTS = { 'engine_part', 'body_part' }
local RoadsideJobs = {}        -- [src] = { id, veh, netId, plate, startedAt, reward, attempt, paying, unclear, retryAt }
local ROADSIDE_RETRY_SECONDS = 30   -- wait after a clearly failed payment before the next key
local RoadsideLastStart = {}   -- [citizenid] = os.time() of the last call made
local RoadsideBusy = {}        -- [src] = true while their car is being made

local function roadsideCfg() return Advanced.RoadsideService or {} end

local function roadsideModel()
    local list = roadsideCfg().Models or (Config.WorkOrderSystem and Config.WorkOrderSystem.vehicles) or {}
    if #list == 0 then return 'sultan' end
    return list[math.random(#list)]
end

local function clearRoadside(src, deleteCar)
    local job = RoadsideJobs[src]
    RoadsideJobs[src] = nil
    if job and deleteCar and job.veh and DoesEntityExist(job.veh) then DeleteEntity(job.veh) end
end

-- The road spot the client picked, if it lies 50-150 m from the mechanic (server position).
local function roadsideSpot(src, spot)
    if type(spot) ~= 'table' then return nil end
    local x, y, z, h = tonumber(spot.x), tonumber(spot.y), tonumber(spot.z), tonumber(spot.h) or 0.0
    if not x or not y or not z or x ~= x or y ~= y or z ~= z or h ~= h then return nil end
    local me = GetEntityCoords(GetPlayerPed(src))
    local flat = #(vector3(x, y, 0.0) - vector3(me.x, me.y, 0.0))
    if flat < ROADSIDE_MIN_DIST or flat > ROADSIDE_MAX_DIST or math.abs(z - me.z) > ROADSIDE_MAX_DZ then return nil end
    return { x = x, y = y, z = z, h = h % 360.0 }
end

-- Runs with the mechanic marked busy. Spawns the car and records the call.
local function makeRoadsideCall(src, cid, at, now)
    local cfg = roadsideCfg()
    local veh = CreateVehicleServerSetter(GetHashKey(roadsideModel()), 'automobile', at.x, at.y, at.z, at.h)
    local tries = 0
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and tries < 40 do
        Wait(50)
        tries = tries + 1
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        TriggerClientEvent('QBCore:Notify', src, 'The roadside call could not be set up. Try again.', 'error')
        return
    end
    local id = PFPayout.NewId()
    local plate = ('RS%06d'):format(math.random(0, 999999))
    SetVehicleNumberPlateText(veh, plate)
    local st = Entity(veh).state
    st:set('partDamage', { engine_part = 100, body_part = 100 }, true)
    st:set('pfRoadside', { id = id, mechanic = src }, true)
    local minPay = math.floor(tonumber(cfg.RewardMin) or 350)
    local maxPay = math.max(minPay, math.floor(tonumber(cfg.RewardMax) or 850))
    RoadsideLastStart[cid] = now
    RoadsideJobs[src] = {
        id = id, veh = veh, netId = NetworkGetNetworkIdFromEntity(veh), plate = plate,
        startedAt = now, reward = math.random(minPay, maxPay), attempt = 1, cid = cid,
    }
    TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideStarted', src, {
        netId = RoadsideJobs[src].netId, x = at.x, y = at.y, z = at.z,
    })
end

RegisterNetEvent('pf-mechanicjob:server:advanced:startRoadside', function(spot)
    local src = source
    local Player = getPlayer(src)
    if not Player or not isMechanicPlayer(Player) then return end
    local cfg = roadsideCfg()
    if not (Advanced.Enabled and cfg.Enabled) then return end
    if Player.PlayerData.job.onduty ~= true then
        TriggerClientEvent('QBCore:Notify', src, 'Go on duty to take roadside calls', 'error')
        return
    end
    if RoadsideBusy[src] then return end
    local current = RoadsideJobs[src]
    if current and PFMech.RoadsideExpired(current, os.time()) then
        clearRoadside(src, true)
        current = nil
    end
    if current then
        -- a call whose car is gone can be replaced; a live one can't
        if current.veh and DoesEntityExist(current.veh) then
            TriggerClientEvent('QBCore:Notify', src, 'Finish your current roadside call first (/roadside cancel gives it up)', 'error')
            return
        end
        RoadsideJobs[src] = nil
    end
    local cid = Player.PlayerData.citizenid
    local now = os.time()
    local cooldown = tonumber(cfg.CooldownSeconds) or 180
    if RoadsideLastStart[cid] and now - RoadsideLastStart[cid] < cooldown then
        TriggerClientEvent('QBCore:Notify', src, 'No roadside calls right now. Try again shortly.', 'error')
        return
    end
    local at = roadsideSpot(src, spot)
    if not at then
        TriggerClientEvent('QBCore:Notify', src, 'No road found for a call around here', 'error')
        return
    end
    RoadsideBusy[src] = true
    local ok, err = pcall(makeRoadsideCall, src, cid, at, now)
    RoadsideBusy[src] = nil
    if not ok then print('^1[pf-mechanicjob]^7 roadside call failed: ' .. tostring(err)) end
end)

local function roadsideTimeout()
    return math.max(120, math.floor(tonumber(roadsideCfg().TimeoutSeconds) or 1200))
end

--- Whether a call is past its time and may be closed: not while its payment is running or unclear
--- (the same key must be asked again until the ledger settles it).
function PFMech.RoadsideExpired(job, now)
    if job.paying or job.unclear then return false end
    return now - job.startedAt >= roadsideTimeout()
end

--- Closes every call past its time and removes its car (the thread below runs it every 30 s).
function PFMech.RoadsideSweep(now)
    now = now or os.time()
    for src, job in pairs(RoadsideJobs) do
        if PFMech.RoadsideExpired(job, now) then
            clearRoadside(src, true)
            TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
            TriggerClientEvent('QBCore:Notify', src, 'The roadside call timed out', 'error')
        end
    end
end

CreateThread(function()
    while true do
        Wait(30000)
        PFMech.RoadsideSweep()
    end
end)

-- The mechanic gives the call up: its car is removed. Not while its payment is running or unclear.
RegisterNetEvent('pf-mechanicjob:server:advanced:cancelRoadside', function()
    local src = source
    local job = RoadsideJobs[src]
    if not job then
        TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
        return
    end
    if job.paying or job.unclear then
        TriggerClientEvent('QBCore:Notify', src, 'The payment for this call is still being processed', 'error')
        return
    end
    clearRoadside(src, true)
    TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
    TriggerClientEvent('QBCore:Notify', src, 'Roadside call cancelled', 'primary')
end)

AddEventHandler('playerDropped', function()
    local src = source
    clearRoadside(src, true)
    RoadsideBusy[src] = nil
    AlignmentStarted[src] = nil
    VehicleStateRate[src] = nil
    ClutchJobs[src] = nil
    DiagLast[src] = nil
    for veh, lift in pairs(Lifted) do
        if lift.by == src then Lifted[veh] = nil end
    end
end)

-- Both worn parts repaired with parts by this mechanic since the call started.
local function repairedBy(veh, src, since)
    local log = PFMech and PFMech.RepairLog and PFMech.RepairLog[veh] or {}
    for _, part in ipairs(ROADSIDE_PARTS) do
        local found = false
        for _, r in ipairs(log) do
            if r.src == src and r.part == part and r.at >= since then found = true break end
        end
        if not found then return false end
    end
    return true
end

RegisterNetEvent('pf-mechanicjob:server:advanced:completeRoadside', function()
    local src = source
    local Player = getPlayer(src)
    if not Player then return end

    local job = RoadsideJobs[src]
    if not job then
        -- no call the server started (refused or already paid): stop the client reporting
        TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
        return
    end
    if job.paying then return end
    -- the call belongs to the character who took it (a character switch keeps the server id)
    if job.cid and job.cid ~= Player.PlayerData.citizenid then return end
    local roadside = roadsideCfg()
    local now = os.time()
    if now - job.startedAt < (tonumber(roadside.MinRepairSeconds) or 20) then return end
    if job.retryAt and now < job.retryAt then return end
    local vehicle = job.veh
    if not vehicle or not DoesEntityExist(vehicle) then
        clearRoadside(src)
        TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
        return
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(vehicle)) > ROADSIDE_PAY_REACH then return end
    -- the server's own state of the car: both parts repaired, by this mechanic, with parts
    local pd = Entity(vehicle).state.partDamage
    pd = type(pd) == 'table' and pd or {}
    for _, part in ipairs(ROADSIDE_PARTS) do
        if (tonumber(pd[part]) or 0) > 0 then return end
    end
    if not repairedBy(vehicle, src, job.startedAt) then return end

    -- keyed by the server-side job id and attempt: one payment per roadside call. A retry after an
    -- unclear result uses the same key and amount, so it is never paid twice; only a key the ledger
    -- clearly failed moves on to the next number. (bank_unavailable stored nothing under the key.)
    job.paying = true
    local paid, res = PFPayout.Pay(Player, 'bank', job.reward, {
        key = ('pf-mechanicjob:roadside:%s:%s:%d'):format(job.id, job.cid or Player.PlayerData.citizenid, job.attempt),
        reason = 'roadside-service-complete',
    })
    job.paying = nil
    if not paid then
        res = type(res) == 'table' and res or {}
        if res.error == 'bank_unavailable' or res.error == 'ledger_unavailable' then
            -- nothing reached the ledger this time: the same key later (an unclear key stays unclear)
            job.retryAt = os.time() + ROADSIDE_RETRY_SECONDS
        elseif PFPayout.IsClearFailure(res) then
            -- this key failed for certain (and stays failed): the next try uses the next number
            job.attempt, job.unclear = job.attempt + 1, nil
            job.retryAt = os.time() + ROADSIDE_RETRY_SECONDS
        else
            -- not known yet: the same key is asked again until the ledger settles it
            job.unclear = true
            job.retryAt = os.time() + 10
        end
        return
    end
    if RoadsideJobs[src] ~= job then return end
    clearRoadside(src, true)
    TriggerClientEvent('pf-mechanicjob:client:advanced:roadsideDone', src)
    -- a stored key that pays now settles an earlier unclear try: its XP was never given
    if res.duplicate and not job.unclear then return end
    TriggerClientEvent('QBCore:Notify', src, ('Roadside service complete: $%d'):format(job.reward), 'success')

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
        cost = job.reward,
        metadata = { callId = job.id },
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
