local QBCore = exports['pfm-core']:GetCoreObject()
PFMech = PFMech or {}

local FULL_ITEM  = (Config.NOS and Config.NOS.items.full)  or 'nos'
local EMPTY_ITEM = (Config.NOS and Config.NOS.items.empty) or 'emptynos'
local CAPACITY   = (Config.NOS and Config.NOS.capacity) or 100

-- The 'nos' vehicle state (has, level, levelSel...) is written by the server only
-- (sv_stateBagStrictMode). Clients ask: fit a bottle, pick a boost level, start and stop boosting,
-- collect the empty bottle. The bottle drains on the server while its driver boosts (the client used
-- to report the level, so a modified client never emptied it and a passenger could empty anyone's).
-- Every request is checked against the car the sender is really in (or beside, for fitting) and
-- the bottle the server took.
local INSTALL_REACH = 8.0        -- metres from the car when fitting from outside
local INSTALL_MIN_SECONDS = 3    -- the fitting progress bar runs 4.5 s after the bottle is used
local INSTALL_WINDOW = 120       -- seconds after using the bottle in which it can be fitted
local LEVELSEL_WINDOW, LEVELSEL_MAX = 5, 15
local PendingInstall = {}        -- [src] = os.time() the bottle was used
local LevelSelRate = {}          -- [src] = { start, count }

local function nosState(has, level, levelSel, color)
    return {
        has = has == true,
        level = level,
        color = color or (Config.NOS and Config.NOS.defaultColor) or '#55CCFF',
        style = 1,
        levelSel = levelSel or 1,
        cooldownAt = 0,
        lastBoostEnd = 0,
    }
end

-- Useable NOS bottle -> client install
QBCore.Functions.CreateUseableItem(FULL_ITEM, function(src)
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end
    local itm = Player.Functions.GetItemByName(FULL_ITEM)
    if not itm or (itm.amount or 0) < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'No NOS bottle found', 'error')
        return
    end
    PendingInstall[src] = os.time()
    TriggerClientEvent('pf_mech:nos:install', src)
end)

AddEventHandler('playerDropped', function()
    PendingInstall[source], LevelSelRate[source] = nil, nil
    if PFMech and PFMech.NosStopBoostsOf then PFMech.NosStopBoostsOf(source) end
end)

-- Empty bottles owed per character: one for each full bottle the server took. The empty used to
-- be handed out on request, as often as a client asked.
local EmptyOwed = {}

local function takeOwedEmpty(Player)
    local cid = Player.PlayerData.citizenid
    if (EmptyOwed[cid] or 0) < 1 then return false end
    EmptyOwed[cid] = EmptyOwed[cid] - 1
    return true
end

-- The car the player is sitting in (if plate is given, only when its plate matches).
local function occupiedVehicle(src, plate)
    local ped = GetPlayerPed(src)
    local veh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    if plate and (tostring(GetVehicleNumberPlateText(veh) or ''):gsub('%s+', ''):upper()) ~= plate then return nil end
    return veh
end

local NOS_WEAR_PARTS = { engine_part = true, sparkplugs = true, fuel_injector = true, oil = true, axle = true }

-- Most wear per second NOS use can cause, per part: the highest boost level's rate (the engine part
-- with the overheating penalty), with the client's own defaults. Doubled: the client adds its wear
-- per frame (a fixed 1/60 s), so a fast frame rate reports more than the configured rate.
local WEAR_SLACK = 2.0
local WEAR_BURST_SECONDS = 4     -- the client reports every 2 s; what was left over goes with the next boost
local WearRate = {}
do
    local function up(part, v)
        v = (tonumber(v) or 0) * WEAR_SLACK
        if v > (WearRate[part] or 0) then WearRate[part] = v end
    end
    local levels = (Config.NOS and type(Config.NOS.levels) == 'table') and Config.NOS.levels or {}
    if next(levels) == nil then levels = { {} } end
    for _, lvl in pairs(levels) do
        local d = type(lvl) == 'table' and type(lvl.damagePerSec) == 'table' and lvl.damagePerSec or {}
        up('engine_part', (tonumber(d.engine_part) or 0.20) + (tonumber(d.heatPenalty) or 0.10))
        up('sparkplugs', tonumber(d.sparkplugs) or 0.30)
        up('fuel_injector', tonumber(d.fuel_injector) or 0.15)
        up('oil', tonumber(d.engine_oil) or 0.05)
        up('axle', tonumber(d.axle) or 0.05)
    end
end

-- [vehicle] = { at = os.time() of the last report, left = { [part] = wear it may still take } }:
-- refills at WearRate, holds at most WEAR_BURST_SECONDS of it.
local WearBudget = {}
local wearPruneAt = 0

local function wearBudget(veh, now)
    if now >= wearPruneAt then
        wearPruneAt = now + 60
        -- an entry this old is full again: the same as none
        for v, b in pairs(WearBudget) do
            if now - b.at >= WEAR_BURST_SECONDS then WearBudget[v] = nil end
        end
    end
    local b = WearBudget[veh]
    if not b then
        b = { at = now, left = {} }
        for part, rate in pairs(WearRate) do b.left[part] = rate * WEAR_BURST_SECONDS end
        WearBudget[veh] = b
        return b
    end
    local dt = math.max(0, now - b.at)
    b.at = now
    for part, rate in pairs(WearRate) do
        b.left[part] = math.min(rate * WEAR_BURST_SECONDS, (b.left[part] or 0) + rate * dt)
    end
    return b
end

local function cleanPlate(plate)
    return (tostring(plate or ''):gsub('%s+', ''):upper())
end

-- ── Saving a car's NOS ──────────────────────────────────────────────────────────────────────────
-- The NOS state is stored in vehicle_diagnostics (nos_has, nos_level, nos_color) the moment it
-- changes: fitted, emptied, removed, and every NOS_SAVE_STEP the level falls. It used to reach the
-- database only with the next driving sync or garage save, so a car lost before that (destroyed,
-- cleaned up, a restart) came back with the bottle full. The writes go through garage_sync's
-- ordered NOS writer (PFMech.SaveNos), the same one the garage store uses, so no save can land after
-- a newer one; only a car carrying its plate's saved state writes it.
local NOS_SAVE_STEP = 10

local function ensureRestored(veh)
    if not (PFMech and PFMech.EnsureVehicleRestored) then return false end
    local ok, res = pcall(PFMech.EnsureVehicleRestored, veh)
    return ok and res == true
end

local function persistNos(veh)
    if not (PFMech and PFMech.SaveNos) then return end
    local ok, err = pcall(PFMech.SaveNos, veh)
    if not ok then print('^1[pf-mechanicjob]^7 NOS not saved: ' .. tostring(err)) end
end

local function vehicleFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    return veh
end

-- The car a bottle may be fitted to: the one the player sits in or stands beside, engine off,
-- without NOS yet, shortly after the player used the bottle (the progress bar has to run).
local function installTarget(src, netId)
    local veh = vehicleFromNet(netId)
    if not veh then return nil, 'Vehicle not found' end
    if occupiedVehicle(src) ~= veh and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > INSTALL_REACH then
        return nil, 'No vehicle nearby'
    end
    if GetIsVehicleEngineRunning(veh) then return nil, 'Turn engine off first' end
    -- the car's saved NOS first, so a bottle already fitted is not fitted again
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local st = Entity(veh).state.nos
    if st and st.has and (tonumber(st.level) or 0) > 0 then return nil, 'NOS already installed' end
    local usedAt = PendingInstall[src]
    local elapsed = usedAt and (os.time() - usedAt) or -1
    if elapsed < INSTALL_MIN_SECONDS or elapsed > INSTALL_WINDOW then return nil, 'Use a NOS bottle first' end
    return veh
end

-- Fitting a bottle: the server takes it and sets the car's NOS state. A call without a car (older
-- clients) only takes the bottle, as before.
RegisterNetEvent('pf_mech:nos:consumeBottle', function(netId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end
    local veh
    if netId ~= nil then
        local why
        veh, why = installTarget(src, netId)
        if not veh then
            TriggerClientEvent('QBCore:Notify', src, why, 'error')
            return
        end
    end
    if Player.Functions.RemoveItem(FULL_ITEM, 1) then
        local cid = Player.PlayerData.citizenid
        EmptyOwed[cid] = (EmptyOwed[cid] or 0) + 1
        local itm = QBCore.Shared.Items[FULL_ITEM]
        if itm then TriggerClientEvent('inventory:client:ItemBox', src, itm, 'remove', 1) end
        if veh then
            PendingInstall[src] = nil
            Entity(veh).state:set('nos', nosState(true, CAPACITY, 1), true)
            TriggerClientEvent('QBCore:Notify', src, 'NOS installed', 'success')
            persistNos(veh)
        end
    elseif veh then
        TriggerClientEvent('QBCore:Notify', src, 'No NOS bottle found', 'error')
    end
end)

-- Boost level 1-3, picked by the driver.
RegisterNetEvent('pf_mech:nos:setLevelSel', function(netId, levelSel)
    local src = source
    levelSel = tonumber(levelSel)
    if not levelSel or levelSel ~= math.floor(levelSel) or levelSel < 1 or levelSel > 3 then return end
    local veh = vehicleFromNet(netId)
    if not veh or occupiedVehicle(src) ~= veh or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return end
    local now = os.time()
    local rate = LevelSelRate[src]
    if not rate or now - rate.start >= LEVELSEL_WINDOW then
        rate = { start = now, count = 0 }
        LevelSelRate[src] = rate
    end
    rate.count = rate.count + 1
    if rate.count > LEVELSEL_MAX then return end
    local st = Entity(veh).state.nos
    if not (st and st.has) then return end
    st.levelSel = levelSel
    Entity(veh).state:set('nos', st, true)
end)

-- The empty bottle, once the server has drained the car's bottle to 0 (the drain clears the NOS
-- state itself). A bottle with gas left is never emptied on a client's word any more. The empty
-- goes to whoever fitted the full one (EmptyOwed).
RegisterNetEvent('pf_mech:nos:giveEmpty', function(netId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if netId ~= nil then
        local veh = vehicleFromNet(netId)
        if not veh or occupiedVehicle(src) ~= veh or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return end
        local st = Entity(veh).state.nos
        if st and st.has and (tonumber(st.level) or 0) > 0 then return end
    end
    
    -- Check if emptynos item exists
    if not QBCore.Shared.Items[EMPTY_ITEM] then
        if Config.Debug then
            print(string.format('[NOS SERVER] ERROR: Item "%s" not found in QBCore.Shared.Items', EMPTY_ITEM))
        end
        TriggerClientEvent('QBCore:Notify', src, 'Empty bottle item not configured', 'error')
        return
    end
    
    if not takeOwedEmpty(Player) then return end

    -- Give empty bottle
    local success = Player.Functions.AddItem(EMPTY_ITEM, 1)

    if success then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[EMPTY_ITEM], 'add', 1)
        TriggerClientEvent('QBCore:Notify', src, 'Received empty NOS bottle', 'success', 3000)
        
        if Config.Debug then
            print(string.format('[NOS SERVER] ✅ Gave empty bottle to player %d', src))
        end
    else
        if Config.Debug then
            print(string.format('[NOS SERVER] ❌ Failed to give empty bottle to player %d (inventory full?)', src))
        end
        EmptyOwed[Player.PlayerData.citizenid] = (EmptyOwed[Player.PlayerData.citizenid] or 0) + 1
        TriggerClientEvent('QBCore:Notify', src, 'Could not receive empty bottle (inventory full?)', 'error')
    end
end)

-- ── Boosting: the server drains the bottle ──────────────────────────────────────────────────────
-- The driver says when boosting starts and stops; every second the server lowers the level of each
-- boosting car by its boost level's drainPerSec (Config.NOS.levels). At 0 the NOS state is cleared
-- and saved. A boost ends when the driver says so, leaves the seat, or the car is gone. (The client
-- still predicts the level for its HUD; the server's level is the one that counts.)
local BOOST_WINDOW, BOOST_MAX = 5, 12        -- start/stop messages per window per player
local Boosting = {}                          -- [vehicle] = { src, last = os.time() of the last drain }
local BoostRate = {}

local function drainPerSec(levelSel)
    local levels = Config.NOS and Config.NOS.levels or {}
    local lvl = levels[tonumber(levelSel) or 1] or levels[1] or {}
    return math.max(0, tonumber(lvl.drainPerSec) or 12)
end

-- Lowers one car's level for `seconds` of boosting; true while there is gas left.
local function drain(veh, seconds)
    local st = Entity(veh).state.nos
    if not (st and st.has) then return false end
    local before = math.max(0, math.min(tonumber(st.level) or 0, CAPACITY))
    local level = math.max(0, before - drainPerSec(st.levelSel) * seconds)
    if level <= 0 then
        Entity(veh).state:set('nos', nosState(false, 0, 1, st.color), true)
        persistNos(veh)
        return false
    end
    st.level = level
    Entity(veh).state:set('nos', st, true)
    -- saved each time the level falls past a NOS_SAVE_STEP mark
    if math.floor(level / NOS_SAVE_STEP) < math.floor(before / NOS_SAVE_STEP) then persistNos(veh) end
    return true
end

--- One drain step for every boosting car (the thread below runs it every second). A car that is
--- gone, or whose driver left the seat, stops boosting here.
function PFMech.NosDrainTick(now)
    now = now or os.time()
    for veh, b in pairs(Boosting) do
        if not DoesEntityExist(veh) or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(b.src) then
            Boosting[veh] = nil
        else
            local dt = math.max(0, now - b.last)
            b.last = now
            if dt > 0 and not drain(veh, math.min(dt, 5)) then Boosting[veh] = nil end
        end
    end
end

function PFMech.NosStopBoostsOf(src)
    for veh, b in pairs(Boosting) do
        if b.src == src then Boosting[veh] = nil end
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        PFMech.NosDrainTick()
    end
end)

RegisterNetEvent('pf_mech:nos:boost', function(netId, on)
    local src = source
    local veh = vehicleFromNet(netId)
    if not veh or occupiedVehicle(src) ~= veh or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return end
    local now = os.time()
    local rate = BoostRate[src]
    if not rate or now - rate.start >= BOOST_WINDOW then
        rate = { start = now, count = 0 }
        BoostRate[src] = rate
    end
    rate.count = rate.count + 1
    if rate.count > BOOST_MAX then return end
    local current = Boosting[veh]
    if on == true then
        if current then return end
        -- the car's saved state first, so a later load cannot put a drained bottle back
        ensureRestored(veh)
        local st = Entity(veh).state.nos
        if not (st and st.has and (tonumber(st.level) or 0) > 0) then return end
        Boosting[veh] = { src = src, last = now }
    elseif current and current.src == src then
        -- the part of a second since the last tick still counts
        Boosting[veh] = nil
        local dt = now - current.last
        if dt > 0 then drain(veh, math.min(dt, 5)) end
    end
end)

-- (The 'pf_mech:nos:updateLevel' report is gone: the level is the server's.)

-- Wear from boosting, reported by the driver every 2 s while boosting.
-- Only the driver, onto the car they are driving (found from their ped, its plate must match), only
-- added wear on the parts NOS wears out, and no more than NOS use can cause in the time since the
-- last report (WearRate, WearBudget). Any occupant used to be heard, the car was found by plate text
-- among all cars (a copied plate reached another car), and each report could add up to 100.
RegisterNetEvent('pf_mech:nos:applyDamage', function(plate, damage)
    local src = source
    if type(plate) ~= 'string' or type(damage) ~= 'table' then return end
    plate = cleanPlate(plate)
    if plate == '' or #plate > 8 then return end
    local veh = occupiedVehicle(src, plate)
    if not veh or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return end

    local budget = wearBudget(veh, os.time())
    local state = Entity(veh).state
    local partDamage = {}
    if type(state.partDamage) == 'table' then
        for k, v in pairs(state.partDamage) do partDamage[k] = v end
    end
    local changed = false
    for part in pairs(NOS_WEAR_PARTS) do
        local dmg = damage[part]
        -- numbers only, finite, positive, at most a whole part: anything else is ignored
        if type(dmg) == 'number' and dmg == dmg and dmg > 0 and dmg <= 100 then
            local take = math.min(dmg, budget.left[part] or 0)
            if take > 0 then
                budget.left[part] = budget.left[part] - take
                partDamage[part] = math.min(100, (tonumber(partDamage[part]) or 0) + take)
                changed = true
            end
        end
    end
    if not changed then return end
    state:set('partDamage', partDamage, true)

    if Config.Debug then
        print(string.format('[NOS SERVER] Applied damage to %s: engine=%.2f%% spark=%.2f%%',
            plate, partDamage.engine_part or 0, partDamage.sparkplugs or 0))
    end
end)

-- Remove an empty bottle from a car: hands back the empty the server owes and clears the car's NOS.
-- (This handler used to be registered inside applyDamage, and only with Config.Debug on.) The player
-- must sit in or stand beside that car.
RegisterNetEvent('pf_mech:nos:removeEmpty', function(netId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local veh = vehicleFromNet(netId)
    if not veh then
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle not found', 'error')
        return
    end
    if occupiedVehicle(src) ~= veh and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > INSTALL_REACH then
        TriggerClientEvent('QBCore:Notify', src, 'No vehicle nearby', 'error')
        return
    end

    local nosState = Entity(veh).state.nos
    if not nosState or not nosState.has then
        TriggerClientEvent('QBCore:Notify', src, 'No NOS installed', 'error')
        return
    end

    local nosLevel = tonumber(nosState.level) or 0
    if nosLevel > 0 then
        TriggerClientEvent('QBCore:Notify', src, 'NOS bottle is not empty yet', 'error')
        return
    end

    if not QBCore.Shared.Items[EMPTY_ITEM] then
        TriggerClientEvent('QBCore:Notify', src, 'Empty bottle item not configured', 'error')
        return
    end

    if not takeOwedEmpty(Player) then return end

    local success = Player.Functions.AddItem(EMPTY_ITEM, 1)
    if not success then
        EmptyOwed[Player.PlayerData.citizenid] = (EmptyOwed[Player.PlayerData.citizenid] or 0) + 1
        TriggerClientEvent('QBCore:Notify', src, 'Could not receive empty bottle (inventory full?)', 'error')
        return
    end

    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[EMPTY_ITEM], 'add', 1)
    Entity(veh).state:set('nos', nil, true)
    TriggerClientEvent('QBCore:Notify', src, 'Empty NOS bottle removed', 'success', 3000)
    persistNos(veh)
end)
