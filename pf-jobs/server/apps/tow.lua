-- Tow job (server), moved here from pfm-towjob.
--
--   * Flatbed rental at the tow yard: the deposit is charged through the bank ledger and comes back
--     when the truck is returned to the bay (less a share for damage). The rental is kept in
--     pf_tow_rentals, so a deposit survives a restart or a disconnect (the truck does not); on a
--     disconnect the truck's state is stored with it and settles the deposit.
--   * The flatbed hook works on any car (pfm-towjob's attach, done by the client once the server
--     has checked the truck, the car and the driver).
--   * NPC tow contracts when no tow request is waiting in dispatch: a broken-down car is placed at a
--     spot within reach of the driver's level; delivering it to the drop-off pays once (ledger key
--     per contract) and gives XP.
--   * pf-services tow requests (police impounds, recoveries) are listed, accepted and completed in
--     the Tow app through pf-services; server/apps/tow_requests.lua checks they are really done.

local QBCore = exports['pfm-core']:GetCoreObject()

PFJobsTow = PFJobsTow or {}
local T = PFJobsTow

local Rentals = {}        -- [citizenid] = { id, model, label, plate, deposit, vehicle, netId, src, orphaned, truckLost, truckHealth }
local RentalChecked = {}  -- [citizenid] = true once the database row was looked up
local Hooks = {}          -- [src] = { truck, target, targetNet, truckNet, plate, at }
local HookedBy = {}       -- [car entity] = src
local Contracts = {}      -- [src] = contract
local Owed = {}           -- [citizenid] = a delivered contract whose pay the bank did not take yet
local PendingDeposit = {} -- [citizenid] = { id, model } of a rental whose deposit charge the bank has not settled
local Stats = {}          -- [citizenid] = { xp, contracts, requests, towed, earned }
local LastSpot, LastContractAt, ContractTimes, SpotsInUse = {}, {}, {}, {}
-- In-flight locks, set before the first yield (database, bank, spawn) so two requests at once
-- cannot both pass the checks: [citizenid] for renting / returning a flatbed, [src] for contracts.
local RentalBusy, ContractBusy = {}, {}
local ClaimBusy = {}      -- [citizenid] while an owed contract pay is being claimed

local function cfg() return Config.Tow or {} end
local function v3(c) return vector3(c.x, c.y, c.z or 0.0) end

local MESSAGES = {
    no_player = 'Not logged in',
    disabled = 'The tow job is closed',
    not_tow = 'You do not work for the tow company',
    off_duty = 'Clock in first',
    bad_request = 'That request was not valid',
    not_at_depot = 'Go to the flatbed bay at the tow yard',
    rental_active = 'You already have a flatbed out. Return it first.',
    no_rental = 'You have no flatbed out',
    unknown_vehicle = 'Unknown truck',
    level_too_low = 'Your tow level is too low for this truck',
    insufficient_funds = 'You cannot pay the deposit',
    bank_unavailable = 'The bank did not respond. Nothing was moved.',
    deposit_pending = 'The bank is still settling your deposit. Try again in a moment: it will not be taken twice.',
    payment_failed = 'The deposit did not go through. Nothing was charged.',
    pay_pending = 'The bank has not paid this yet. Try again in a moment: it is paid only once.',
    spawn_failed = 'The truck could not be brought out',
    bay_blocked = 'The flatbed bay is blocked',
    truck_far = 'Bring the flatbed back to the bay',
    truck_loaded = 'Take the car off the flatbed first',
    truck_lost = 'Your flatbed is gone. Report it lost to settle the rental.',
    truck_exists = 'Your flatbed is still out there. Bring it back to the bay.',
    contract_active = 'Finish or cancel your current contract first',
    requests_waiting = 'Tow requests are waiting in dispatch. Take one of those first.',
    no_spot = 'No breakdowns in your area right now',
    cooldown = 'Dispatch has nothing yet. Try again in a few seconds.',
    hourly_limit = 'That is enough contracts for this hour',
    no_truck = 'You need a flatbed for tow contracts',
    no_contract = 'You have no contract',
    payment_due = 'Collect the pay for your last contract first',
    nothing_owed = 'Nothing is owed to you',
    not_a_hook_job = 'You cannot use the flatbed hook',
    not_on_foot = 'Get out of the truck first',
    not_flatbed = 'Your last vehicle is not a flatbed',
    too_far_truck = 'Stand next to your flatbed',
    too_far_car = 'The car is too far from the flatbed',
    truck_busy = 'The flatbed already carries a car',
    car_hooked = 'That car is already on a flatbed',
    occupied = 'Someone is in that car',
    bad_target = 'You cannot tow that',
    nothing_hooked = 'Nothing is on your flatbed',
    services_offline = 'Dispatch is offline',
    busy = 'One moment, the last request is still being handled',
    deposit_held = 'The truck could not be brought out. Your deposit is held: collect it at the bay.',
}
T.Messages = MESSAGES

local function notify(src, msg, kind) TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary') end

local function fail(src, code, quiet)
    local message = MESSAGES[code] or code
    if not quiet and src then notify(src, message, 'error') end
    return { ok = false, error = code, message = message }
end

local function trimPlate(p) return (tostring(p or ''):gsub('^%s+', ''):gsub('%s+$', '')):upper() end

local function modelIs(entity, names)
    local hash = (tonumber(GetEntityModel(entity)) or 0) & 0xFFFFFFFF
    for _, m in ipairs(names or {}) do
        if hash == (GetHashKey(m) & 0xFFFFFFFF) then return true end
    end
    return false
end

local function exists(e) return e ~= nil and e ~= 0 and DoesEntityExist(e) end

-- Runs fn while holding locks[key]; a second call while it runs is refused with 'busy'. The lock is
-- released on every exit, an error included.
local function withLock(locks, key, src, quiet, fn)
    if locks[key] then return fail(src, 'busy', quiet) end
    locks[key] = true
    local ok, res = pcall(fn)
    locks[key] = nil
    if not ok then error(res, 0) end
    return res
end

-- Whether src is still the same character (a disconnect can happen during a yield).
local function stillHere(src, cid)
    local P = QBCore.Functions.GetPlayer(src)
    return P ~= nil and P.PlayerData ~= nil and P.PlayerData.citizenid == cid
end

local function spawnVehicle(model, at)
    local veh = CreateVehicleServerSetter(GetHashKey(model), 'automobile', at.x, at.y, at.z, at.w or 0.0)
    local timeout = 0
    while not DoesEntityExist(veh) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    if not DoesEntityExist(veh) then return nil end
    return veh
end

-- ── players, levels and stats ───────────────────────────────────────

local function towPlayer(src, needDuty)
    if not cfg().Enabled then return nil, 'disabled' end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil, 'no_player' end
    local job = Player.PlayerData.job or {}
    if job.name ~= cfg().Job then return nil, 'not_tow' end
    if needDuty ~= false and cfg().RequireOnDuty and not job.onduty then return nil, 'off_duty' end
    return Player
end

local function stats(cid)
    if Stats[cid] then return Stats[cid] end
    local st = { xp = 0, contracts = 0, requests = 0, towed = 0, earned = 0 }
    if cfg().UseDatabase then
        local ok, row = pcall(MySQL.single.await, 'SELECT xp, contracts, requests, towed, earned FROM pf_tow_stats WHERE citizenid = ?', { cid })
        if not ok then return st end -- not cached: read again next time
        if type(row) == 'table' and row.xp ~= nil then
            for k in pairs(st) do st[k] = tonumber(row[k]) or 0 end
        end
    end
    Stats[cid] = st
    return st
end

local function saveStats(cid)
    local st = Stats[cid]
    if not st or not cfg().UseDatabase then return end
    pcall(MySQL.query.await, [[INSERT INTO pf_tow_stats (citizenid, xp, contracts, requests, towed, earned) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = VALUES(xp), contracts = VALUES(contracts), requests = VALUES(requests),
            towed = VALUES(towed), earned = VALUES(earned)]], { cid, st.xp, st.contracts, st.requests, st.towed, st.earned })
end

local function levelOf(xp)
    local levels = cfg().Levels or {}
    local current, nextLevel = levels[1] or { level = 1, xp = 0, maxKm = 99, payMultiplier = 1 }, nil
    for i, l in ipairs(levels) do
        if (tonumber(xp) or 0) >= (tonumber(l.xp) or 0) then current, nextLevel = l, levels[i + 1] end
    end
    return current, nextLevel
end

-- Adds a finished job to the character's record; tells the player about a new level.
local function credit(cid, field, xp, earned)
    local st = stats(cid)
    local before = levelOf(st.xp).level
    st[field] = (st[field] or 0) + 1
    st.xp = st.xp + math.max(0, math.floor(xp or 0))
    st.earned = st.earned + math.max(0, math.floor(earned or 0))
    saveStats(cid)
    local now = levelOf(st.xp)
    if now.level > before then
        local P = QBCore.Functions.GetPlayerByCitizenId(cid)
        if P then notify(P.PlayerData.source, ('Tow level %d: %s'):format(now.level, now.title or ''), 'success') end
    end
end

-- ── the yard ────────────────────────────────────────────────────────

local function bay() return cfg().FlatbedSpawn end

local function nearBay(src)
    local b = bay()
    return b ~= nil and #(GetEntityCoords(GetPlayerPed(src)) - v3(b)) <= (tonumber(cfg().ReturnRadius) or 25.0)
end

local function bayBlocked()
    if not GetAllVehicles then return false end
    local b = v3(bay())
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - b) < 4.0 then return true end
    end
    return false
end

local function vehicleDef(model)
    for _, v in ipairs(cfg().Vehicles or {}) do
        if v.model == model then return v end
    end
    return nil
end

-- A new rental starts with no recorded truck state, also over a row whose delete failed.
local function saveRental(cid, r)
    if not cfg().UseDatabase then return true end
    return (pcall(MySQL.query.await, 'INSERT INTO pf_tow_rentals (citizenid, rental_id, model, plate, deposit) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE rental_id = VALUES(rental_id), model = VALUES(model), plate = VALUES(plate), deposit = VALUES(deposit), truck_lost = NULL, truck_health = NULL',
        { cid, r.id, r.model, r.plate, r.deposit }))
end

-- The truck's state when its driver left, kept with the rental so a restart does not forget it.
local function saveTruckState(cid, r)
    if not cfg().UseDatabase then return true end
    return (pcall(MySQL.update.await, 'UPDATE pf_tow_rentals SET truck_lost = ?, truck_health = ? WHERE citizenid = ? AND rental_id = ?',
        { r.truckLost and 1 or 0, r.truckHealth or 0, cid, r.id }))
end

-- A rental read back from the database: it has no truck any more. truck_lost / truck_health are
-- NULL when the truck went with a restart rather than with its driver.
local function rentalFromRow(row)
    local def = vehicleDef(row.model) or {}
    local r = { id = row.rental_id, model = row.model, label = def.label or row.model, plate = row.plate,
        deposit = tonumber(row.deposit) or 0, orphaned = true }
    if row.truck_lost ~= nil then
        r.truckLost = tonumber(row.truck_lost) == 1
        r.truckHealth = math.max(0, math.min(1, tonumber(row.truck_health) or 0))
    end
    return r
end

local function deleteRental(cid)
    if cfg().UseDatabase then pcall(MySQL.query.await, 'DELETE FROM pf_tow_rentals WHERE citizenid = ?', { cid }) end
end

-- The open rental of a character. One found only in the database (after a restart) has no truck
-- any more: it is "orphaned" and is settled at the bay.
local function rentalOf(cid)
    if Rentals[cid] then return Rentals[cid] end
    if cfg().UseDatabase and not RentalChecked[cid] then
        local ok, row = pcall(MySQL.single.await, 'SELECT rental_id, model, plate, deposit, truck_lost, truck_health FROM pf_tow_rentals WHERE citizenid = ?', { cid })
        if not ok then return nil end
        RentalChecked[cid] = true
        if type(row) == 'table' and row.rental_id then Rentals[cid] = rentalFromRow(row) end
    end
    return Rentals[cid]
end

local function hookOnTruck(truck)
    for src, h in pairs(Hooks) do
        if h.truck == truck then return src, h end
    end
    return nil
end

local function truckHealth(veh)
    local ok, engine, body = pcall(function() return GetVehicleEngineHealth(veh), GetVehicleBodyHealth(veh) end)
    if not ok then return 1.0 end
    local worst = math.min(tonumber(engine) or 1000, tonumber(body) or 1000)
    return math.max(0, math.min(1, worst / 1000))
end

local function refundKey(r) return ('pf-jobs:tow:rent:%s:refund'):format(r.id) end

-- The key for one payment, given its base key. The ledger keeps a failed transfer under its key and
-- returns that failure for every later call, so a payment that failed for good (failed / compensated)
-- moves on to the next numbered key; a completed, pending or debited one is reused, so the money never
-- moves twice. Nil once ten attempts failed for good.
local function attemptKey(base)
    for n = 0, 9 do
        local key = n == 0 and base or ('%s:%d'):format(base, n)
        local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
        if not ok or type(tx) ~= 'table' then return key end
        local final = tx.state == 'compensated' or (tx.state == 'failed' and tx.error ~= 'interrupted_unverified')
        if not final then return key end
    end
    return nil
end

local function refundKeyFor(r) return attemptKey(refundKey(r)) end

local function payRefund(cid, r, amount, quiet)
    local key = refundKeyFor(r)
    if not key then return false end
    return (PFPayout.Pay(cid, 'bank', amount, { key = key, reason = 'tow-flatbed-deposit-refund', kind = 'refund', quiet = quiet }))
end

-- A damaged truck keeps part of the deposit (health 0..1).
local function refundFor(deposit, health)
    return deposit - math.floor(deposit * (1 - health) * (tonumber(cfg().DamageDeduction) or 0))
end

-- What an orphaned rental pays back: nothing for a truck that was lost when its driver left, the
-- damage deduction for one left at the bay, all of it when a restart took the truck.
local function orphanRefund(r)
    if r.truckLost then return 0 end
    if r.truckHealth then return refundFor(r.deposit, r.truckHealth) end
    return r.deposit
end

-- Why a deposit charge did not go through. An unclear result (pending, debited, an interrupted
-- transfer) is not a refusal: the money may already have left, so it is never told as "you cannot
-- pay", and the retry uses the same key (PendingDeposit) until the ledger settles it.
local function chargeError(res)
    res = type(res) == 'table' and res or {}
    if res.error == 'bank_unavailable' or res.error == 'ledger_unavailable' then return 'bank_unavailable' end
    if res.unclear then return 'deposit_pending' end
    if res.error == 'insufficient_funds' then return 'insufficient_funds' end
    return 'payment_failed'
end

-- Runs under RentalBusy[cid]: the checks, the deposit and the truck cannot interleave with a second
-- rent (or a return) of the same character.
local function rent(src, Player, cid, model, quiet)
    -- a deposit the bank is still settling is asked for again under its own key (same rental id and
    -- truck), so it can never be taken twice
    local pending = PendingDeposit[cid]
    if pending then model = pending.model end
    local def = vehicleDef(model or ((cfg().Vehicles or {})[1] or {}).model)
    if not def then return fail(src, 'unknown_vehicle', quiet) end
    if rentalOf(cid) then return fail(src, 'rental_active', quiet) end
    if not nearBay(src) then return fail(src, 'not_at_depot', quiet) end
    if levelOf(stats(cid).xp).level < (tonumber(def.minLevel) or 1) then return fail(src, 'level_too_low', quiet) end
    if bayBlocked() then return fail(src, 'bay_blocked', quiet) end
    if not stillHere(src, cid) then return fail(src, 'no_player', true) end

    -- orphaned (no truck) until the truck is out: if anything stops it, the deposit is refundable at the bay
    local rental = { id = pending and pending.id or PFPayout.NewId(), model = def.model, label = def.label or def.model,
        deposit = math.max(0, math.floor(tonumber(def.deposit) or 0)), src = src, orphaned = true }
    rental.plate = ((cfg().PlatePrefix or 'TOWR') .. math.random(1000, 9999)):sub(1, 8)
    if rental.deposit > 0 then
        -- quiet: the one message is the rental's own (fail below), not a second one from PFPayout
        local paidFrom, res = PFPayout.Charge(Player, { 'cash', 'bank' }, rental.deposit, {
            key = ('pf-jobs:tow:rent:%s'):format(rental.id), reason = 'tow-flatbed-deposit', kind = 'deposit', quiet = true,
        })
        if not paidFrom then
            local code = chargeError(res)
            if code == 'deposit_pending' then
                PendingDeposit[cid] = { id = rental.id, model = def.model }
            elseif code ~= 'bank_unavailable' then
                -- settled (refused, or reversed): this key is spent and nothing was taken
                PendingDeposit[cid] = nil
            end
            -- a bank that did not answer says nothing about an earlier unclear charge: that one
            -- keeps its key, or it could settle as taken while the next try charges again under a new one
            return fail(src, code, quiet)
        end
    end
    PendingDeposit[cid] = nil
    -- the deposit is taken: the rental is recorded before the next yield, so it can never be lost
    Rentals[cid] = rental
    RentalChecked[cid] = true
    saveRental(cid, rental)

    local veh = spawnVehicle(def.model, bay())
    if veh and (not stillHere(src, cid) or Rentals[cid] ~= rental) then
        -- the driver left (or the character was deleted) while the truck came out: it goes, and
        -- the deposit stays refundable at the bay
        DeleteEntity(veh)
        if rental.deposit <= 0 and Rentals[cid] == rental then
            Rentals[cid] = nil
            deleteRental(cid)
        end
        return fail(src, 'no_player', true)
    end
    if not veh then
        if rental.deposit > 0 and not payRefund(cid, rental, rental.deposit, quiet) then
            return fail(src, 'deposit_held', quiet) -- kept as an orphaned rental: full refund at the bay
        end
        Rentals[cid] = nil
        deleteRental(cid)
        return fail(src, 'spawn_failed', quiet)
    end
    SetVehicleNumberPlateText(veh, rental.plate)
    rental.vehicle, rental.netId, rental.orphaned = veh, NetworkGetNetworkIdFromEntity(veh), nil
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, rental.plate)
    TriggerEvent('qb-vehiclekeys:server:GiveVehicleKeys', src, rental.plate)
    TriggerClientEvent('pf-jobs:tow:client:flatbed', src, rental.netId, rental.plate)
    if not quiet then notify(src, ('%s ready, plate %s. Deposit $%d'):format(rental.label, rental.plate, rental.deposit), 'success') end
    T.Push(src)
    return { ok = true }
end

function T.Rent(src, model, quiet)
    local Player, err = towPlayer(src)
    if not Player then return fail(src, err, quiet) end
    local cid = Player.PlayerData.citizenid
    return withLock(RentalBusy, cid, src, quiet, function() return rent(src, Player, cid, model, quiet) end)
end

-- Returning or reporting a flatbed needs a rental, not the tow job: a driver who was fired or
-- changed jobs still settles the deposit.
local function rentalPlayer(src)
    if not cfg().Enabled then return nil, 'disabled' end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil, 'no_player' end
    return Player
end

local function noRental(Player)
    return ((Player.PlayerData.job or {}).name == cfg().Job) and 'no_rental' or 'not_tow'
end

-- A player outside the tow job sees the Tow app only while a rental is open or a contract's pay is
-- owed to them (server/devices.lua); once that is settled their device drops the app.
local function formerDriverSettled(src, Player)
    if (Player.PlayerData.job or {}).name == cfg().Job then return end
    if GetResourceState('pf-devices') ~= 'started' then return end
    pcall(function() exports['pf-devices']:NotifyAppsChanged(src) end)
end

local function returnRental(src, Player, cid, quiet)
    local r = rentalOf(cid)
    if not r then return fail(src, noRental(Player), quiet) end
    if not nearBay(src) then return fail(src, 'not_at_depot', quiet) end
    local refund
    if r.orphaned then
        refund = orphanRefund(r)
    else
        if not exists(r.vehicle) then return fail(src, 'truck_lost', quiet) end
        if #(GetEntityCoords(r.vehicle) - v3(bay())) > (tonumber(cfg().ReturnRadius) or 25.0) then return fail(src, 'truck_far', quiet) end
        if hookOnTruck(r.vehicle) then return fail(src, 'truck_loaded', quiet) end
        refund = refundFor(r.deposit, truckHealth(r.vehicle))
    end
    if refund > 0 and not payRefund(cid, r, refund, quiet) then return fail(src, 'bank_unavailable', quiet) end
    if exists(r.vehicle) then DeleteEntity(r.vehicle) end
    if Rentals[cid] == r then Rentals[cid] = nil end
    deleteRental(cid)
    TriggerClientEvent('pf-jobs:tow:client:flatbedReturned', src)
    if not quiet then
        if refund > 0 then notify(src, ('Flatbed returned. $%d deposit back to your bank'):format(refund), 'success')
        elseif r.truckLost then notify(src, 'Your flatbed was lost when you left. The deposit covers it.', 'primary')
        else notify(src, 'Flatbed returned. The damage used up the deposit.', 'primary') end
    end
    T.Push(src)
    formerDriverSettled(src, Player)
    return { ok = true, refund = refund }
end

function T.Return(src, quiet)
    local Player, err = rentalPlayer(src)
    if not Player then return fail(src, err, quiet) end
    local cid = Player.PlayerData.citizenid
    return withLock(RentalBusy, cid, src, quiet, function() return returnRental(src, Player, cid, quiet) end)
end

-- The truck is gone (destroyed or lost): the deposit is kept and the rental is closed.
function T.ReportLost(src, quiet)
    local Player, err = rentalPlayer(src)
    if not Player then return fail(src, err, quiet) end
    local cid = Player.PlayerData.citizenid
    return withLock(RentalBusy, cid, src, quiet, function()
        local r = rentalOf(cid)
        if not r then return fail(src, noRental(Player), quiet) end
        if r.orphaned then return fail(src, 'not_at_depot', quiet) end -- an orphaned rental is refunded at the bay
        if exists(r.vehicle) then return fail(src, 'truck_exists', quiet) end
        if Rentals[cid] == r then Rentals[cid] = nil end
        deleteRental(cid)
        if not quiet then notify(src, 'Flatbed reported lost. The deposit covers it.', 'primary') end
        T.Push(src)
        formerDriverSettled(src, Player)
        return { ok = true }
    end)
end

-- ── the hook ────────────────────────────────────────────────────────

local function hookPlayer(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil, 'no_player' end
    local job = Player.PlayerData.job or {}
    if not (cfg().HookJobs or {})[job.name] then return nil, 'not_a_hook_job' end
    return Player
end

function T.Hook(src, targetNet, quiet)
    local Player, err = hookPlayer(src)
    if not Player then return fail(src, err, quiet) end
    targetNet = tonumber(targetNet)
    if not targetNet or targetNet % 1 ~= 0 or targetNet <= 0 then return fail(src, 'bad_request', quiet) end
    if Hooks[src] then return fail(src, 'truck_busy', quiet) end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= 0 then return fail(src, 'not_on_foot', quiet) end
    local truck = GetVehiclePedIsIn(ped, true)
    if not exists(truck) or not modelIs(truck, cfg().HookModels) then return fail(src, 'not_flatbed', quiet) end
    if #(GetEntityCoords(ped) - GetEntityCoords(truck)) > (tonumber(cfg().DriverRange) or 15.0) then return fail(src, 'too_far_truck', quiet) end
    local target = NetworkGetEntityFromNetworkId(targetNet)
    if not exists(target) or target == truck or modelIs(target, cfg().HookModels) then return fail(src, 'bad_target', quiet) end
    if GetEntityType and GetEntityType(target) ~= 2 then return fail(src, 'bad_target', quiet) end
    if HookedBy[target] then return fail(src, 'car_hooked', quiet) end
    if hookOnTruck(truck) then return fail(src, 'truck_busy', quiet) end
    if GetPedInVehicleSeat(target, -1) ~= 0 then return fail(src, 'occupied', quiet) end
    if #(GetEntityCoords(truck) - GetEntityCoords(target)) > (tonumber(cfg().HookRange) or 11.0) then return fail(src, 'too_far_car', quiet) end

    local now = os.time()
    Hooks[src] = { truck = truck, target = target, targetNet = targetNet, truckNet = NetworkGetNetworkIdFromEntity(truck),
        plate = trimPlate(GetVehicleNumberPlateText(target)), at = now }
    HookedBy[target] = src
    local c = Contracts[src]
    if c and c.vehicle == target and c.stage == 'pickup' then
        c.stage, c.hookedAt = 'deliver', now
        if not quiet then notify(src, ('Car on the flatbed. Take it to %s.'):format(cfg().DropOff.label or 'the depot'), 'success') end
    end
    if (Player.PlayerData.job or {}).name == cfg().Job then
        local st = stats(Player.PlayerData.citizenid)
        st.towed = st.towed + 1
        saveStats(Player.PlayerData.citizenid)
    end
    TriggerClientEvent('pf-jobs:tow:client:attach', src, targetNet, Hooks[src].truckNet)
    T.Push(src)
    return { ok = true, plate = Hooks[src].plate }
end

local function payContract(src, cid, c, quiet)
    -- a pay the bank refused for good (failed / compensated: nothing reached the player) is claimed
    -- again under the next numbered key; the first key used to return that refusal forever
    local key = attemptKey(('pf-jobs:tow:contract:%s'):format(c.id))
    local ok, res = false, nil
    if key then ok, res = PFPayout.Pay(cid, 'bank', c.pay, { key = key, reason = 'tow-contract', quiet = quiet }) end
    if not ok then
        c.stage = 'payment_due'
        Owed[cid] = c
        return false, res
    end
    Owed[cid] = nil
    if Contracts[src] == c then Contracts[src] = nil end
    if SpotsInUse[c.spot] == src then SpotsInUse[c.spot] = nil end
    -- the XP and the earnings count once, whichever call saw the pay go through
    if c.credited then return true end
    c.credited = true
    credit(cid, 'contracts', c.xp, c.pay)
    LastContractAt[src] = os.time()
    if src and not quiet then notify(src, ('Delivered. $%d to your bank, +%d XP'):format(c.pay, c.xp), 'success') end
    return true
end

-- The contract car has just been set down: it counts when it is at the drop-off with the driver,
-- a real tow after it was hooked.
local function deliver(src, cid, c, quiet)
    if not exists(c.vehicle) then return false end
    local pos = GetEntityCoords(c.vehicle)
    local drop = cfg().DropOff
    local now = os.time()
    local function back(code)
        c.stage, c.hookedAt = 'pickup', nil
        if code and not quiet then notify(src, code, 'error') end
        return false
    end
    if #(pos - v3(drop.coords)) > (tonumber(drop.radius) or 30.0) then return back(('Set it down at %s'):format(drop.label or 'the drop-off')) end
    if #(GetEntityCoords(GetPlayerPed(src)) - pos) > (tonumber(cfg().DriverRange) or 15.0) then return back() end
    if now - (c.hookedAt or now) < (tonumber(cfg().MinDeliverySeconds) or 15) then return back('That was too quick') end
    if now - c.startedAt < (c.km * 1000) / (tonumber(cfg().MaxTowSpeed) or 40.0) then return back('That was too quick') end
    c.stage = 'delivered'
    local car = c.vehicle
    -- the client sets the car down first; then the server removes it
    SetTimeout(4000, function() if exists(car) then DeleteEntity(car) end end)
    return payContract(src, cid, c, quiet)
end

local function myAcceptedRequests(cid)
    if GetResourceState('pf-services') ~= 'started' then return {} end
    local ok, list = pcall(function() return exports['pf-services']:ListForJob(cfg().Job) end)
    local out = {}
    for _, r in ipairs(ok and type(list) == 'table' and list or {}) do
        if r.status == 'accepted' and r.assignee == cid then out[#out + 1] = r end
    end
    return out
end

-- Setting a requested car down at its destination completes the request (pf-services checks it).
local function tryCompleteRequests(src, cid, plate, quiet)
    if plate == '' then return nil end
    for _, r in ipairs(myAcceptedRequests(cid)) do
        if trimPlate(r.plate) == plate then
            local ok, res = pcall(function() return exports['pf-services']:CompleteRequest(src, r.id, {}) end)
            if ok and type(res) == 'table' and res.ok then
                if not quiet then notify(src, ('Request #%d complete'):format(r.id), 'success') end
                return r.id
            end
        end
    end
    return nil
end

function T.Unhook(src, quiet)
    local h = Hooks[src]
    if not h then return fail(src, 'nothing_hooked', quiet) end
    Hooks[src] = nil
    HookedBy[h.target] = nil
    TriggerClientEvent('pf-jobs:tow:client:detach', src, h.targetNet, h.truckNet)
    local res = { ok = true }
    local Player = QBCore.Functions.GetPlayer(src)
    local cid = Player and Player.PlayerData.citizenid
    local c = Contracts[src]
    if cid and c and c.vehicle == h.target and c.stage == 'deliver' then
        res.delivered = deliver(src, cid, c, quiet)
    elseif cid then
        res.completedRequest = tryCompleteRequests(src, cid, h.plate, quiet)
    end
    T.Push(src)
    return res
end

-- ── NPC contracts ───────────────────────────────────────────────────

local function openRequestCount()
    if GetResourceState('pf-services') ~= 'started' then return 0 end
    local ok, list = pcall(function() return exports['pf-services']:ListForJob(cfg().Job) end)
    local n = 0
    for _, r in ipairs(ok and type(list) == 'table' and list or {}) do
        if r.status == 'open' then n = n + 1 end
    end
    return n
end

local function hasTruck(src, cid)
    local r = Rentals[cid]
    if r and not r.orphaned and exists(r.vehicle) then return true end
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end
    return exists(veh) and modelIs(veh, cfg().HookModels) and #(GetEntityCoords(ped) - GetEntityCoords(veh)) <= 30.0
end

local function spotKm(spot) return #(v3(spot.coords) - v3(cfg().DropOff.coords)) / 1000 end

-- Why this driver cannot take an NPC contract now (nil when they can).
local function contractBlocker(src, cid)
    if Contracts[src] then return Contracts[src].stage == 'payment_due' and 'payment_due' or 'contract_active' end
    if Owed[cid] then return 'payment_due' end
    if not hasTruck(src, cid) then return 'no_truck' end
    local cc = cfg().Contracts or {}
    if cc.OnlyWhenNoRequests ~= false and openRequestCount() > 0 then return 'requests_waiting' end
    local now = os.time()
    if LastContractAt[src] and now - LastContractAt[src] < (tonumber(cc.Cooldown) or 10) then return 'cooldown' end
    local recent = {}
    for _, t in ipairs(ContractTimes[src] or {}) do if now - t < 3600 then recent[#recent + 1] = t end end
    ContractTimes[src] = recent
    if #recent >= (tonumber(cc.MaxPerHour) or 20) then return 'hourly_limit' end
    return nil
end

-- Runs under ContractBusy[src]: a second request cannot pass the checks while the first one's car
-- is being spawned.
local function startContract(src, cid, quiet)
    local blocker = contractBlocker(src, cid)
    if blocker then return fail(src, blocker, quiet) end
    local level = levelOf(stats(cid).xp)
    local spots = {}
    for i, spot in ipairs(cfg().Spots or {}) do
        if not SpotsInUse[i] and i ~= LastSpot[src] and spotKm(spot) <= (tonumber(level.maxKm) or 99) then spots[#spots + 1] = i end
    end
    if #spots == 0 then return fail(src, 'no_spot', quiet) end
    local index = spots[math.random(#spots)]
    local spot = cfg().Spots[index]
    SpotsInUse[index] = src -- held while the car spawns, so no other driver gets the same spot
    local car = spawnVehicle(spot.model, spot.coords)
    if car and (not stillHere(src, cid) or Contracts[src]) then
        -- the driver left while the car spawned: it goes, with its spot
        DeleteEntity(car)
        car = nil
    end
    if not car then
        if SpotsInUse[index] == src then SpotsInUse[index] = nil end
        return fail(src, 'spawn_failed', quiet)
    end
    local plate = ('BRK%05d'):format(math.random(0, 99999))
    SetVehicleNumberPlateText(car, plate)
    SetVehicleDoorsLocked(car, 2)
    local cc = cfg().Contracts or {}
    local km = spotKm(spot)
    local pay = math.floor(((tonumber(cc.PayBase) or 140) + (tonumber(cc.PayPerKm) or 30) * km) * (tonumber(level.payMultiplier) or 1))
    pay = math.max(1, math.min(pay, tonumber(cc.MaxPay) or pay))
    local c = {
        id = PFPayout.NewId(), cid = cid, spot = index, model = spot.model, plate = plate, vehicle = car,
        netId = NetworkGetNetworkIdFromEntity(car), coords = v3(spot.coords), km = km, pay = pay,
        xp = math.floor((tonumber(cc.XPBase) or 40) + (tonumber(cc.XPPerKm) or 10) * km),
        startedAt = os.time(), stage = 'pickup',
    }
    Contracts[src] = c
    SpotsInUse[index] = src
    LastSpot[src] = index
    ContractTimes[src] = ContractTimes[src] or {}
    table.insert(ContractTimes[src], c.startedAt)
    if not quiet then notify(src, ('Breakdown: a %s, %.1f km out. $%d on delivery.'):format(spot.model, km, pay), 'success') end
    T.Push(src)
    return { ok = true }
end

function T.StartContract(src, quiet)
    local Player, err = towPlayer(src)
    if not Player then return fail(src, err, quiet) end
    local cid = Player.PlayerData.citizenid
    return withLock(ContractBusy, src, src, quiet, function() return startContract(src, cid, quiet) end)
end

local function dropContract(src, c)
    if exists(c.vehicle) then
        local by = HookedBy[c.vehicle]
        if by then
            local h = Hooks[by]
            Hooks[by], HookedBy[c.vehicle] = nil, nil
            if h then TriggerClientEvent('pf-jobs:tow:client:detach', by, h.targetNet, h.truckNet) end
        end
        DeleteEntity(c.vehicle)
    end
    if SpotsInUse[c.spot] == src then SpotsInUse[c.spot] = nil end
    if Contracts[src] == c then Contracts[src] = nil end
end

function T.CancelContract(src, quiet)
    local c = Contracts[src]
    if not c then return fail(src, 'no_contract', quiet) end
    if c.stage == 'payment_due' or c.stage == 'delivered' then return fail(src, 'payment_due', quiet) end
    dropContract(src, c)
    LastContractAt[src] = os.time()
    if not quiet then notify(src, 'Contract cancelled', 'primary') end
    T.Push(src)
    return { ok = true }
end

-- A delivered contract the bank did not pay: the same key pays it now. It was earned, so no tow job
-- is needed: a driver who has left the job collects it from the Tow app's return-only view.
-- Locked per character before the bank wait: two claims at once both found the pay owed.
function T.ClaimPay(src, quiet)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return fail(src, 'no_player', quiet) end
    local cid = Player.PlayerData.citizenid
    return withLock(ClaimBusy, cid, src, quiet, function()
        local c = Owed[cid]
        if not c then return fail(src, 'nothing_owed', quiet) end
        Contracts[src] = Contracts[src] or c
        local paid, res = payContract(src, cid, c, quiet)
        if not paid then
            -- only a bank that did not answer moved nothing for sure; any other result may still settle
            local down = type(res) == 'table' and (res.error == 'bank_unavailable' or res.error == 'ledger_unavailable')
            return fail(src, down and 'bank_unavailable' or 'pay_pending', quiet)
        end
        if Contracts[src] == c then Contracts[src] = nil end
        T.Push(src)
        formerDriverSettled(src, Player)
        return { ok = true, paid = c.pay }
    end)
end

-- ── pf-services tow requests ────────────────────────────────────────

local function impoundLots()
    if GetResourceState('pfm-policejob') ~= 'started' then return {} end
    local ok, lots = pcall(function() return exports['pfm-policejob']:GetImpoundLots() end)
    return ok and type(lots) == 'table' and lots or {}
end

local function destinationsFor(req)
    local out = {}
    if req.kind == 'tow.impound' then
        for i, lot in ipairs(impoundLots()) do
            local c = lot.coords or lot
            if tonumber(c.x) then out[#out + 1] = { label = lot.label or ('Impound lot ' .. i), x = c.x, y = c.y } end
        end
    else
        local dest = req.meta and req.meta.destination
        if type(dest) == 'table' and tonumber(dest.x) then
            out[1] = { label = dest.label or 'Destination', x = tonumber(dest.x), y = tonumber(dest.y) }
        else
            for _, d in ipairs((PFJobsTowRequests or {}).Destinations or {}) do out[#out + 1] = { label = d.label, x = d.coords.x, y = d.coords.y } end
        end
    end
    return out
end

local function requestList(cid)
    if GetResourceState('pf-services') ~= 'started' then return nil end
    local ok, list = pcall(function() return exports['pf-services']:ListForJob(cfg().Job) end)
    if not ok or type(list) ~= 'table' then return nil end
    local out = {}
    for _, req in ipairs(list) do
        local okV, view = pcall(function() return exports['pf-services']:PublicView(req, cid, cfg().Job) end)
        if okV and type(view) == 'table' and (view.status == 'open' or view.mine) then
            view.destinations = destinationsFor(req)
            out[#out + 1] = view
        end
    end
    return out
end

local function servicesCall(src, fnName, id, quiet)
    local Player, err = towPlayer(src)
    if not Player then return fail(src, err, quiet) end
    id = tonumber(id)
    if not id or id % 1 ~= 0 or id <= 0 then return fail(src, 'bad_request', quiet) end
    if GetResourceState('pf-services') ~= 'started' then return fail(src, 'services_offline', quiet) end
    local ok, res = pcall(function()
        if fnName == 'AcceptRequest' then return exports['pf-services']:AcceptRequest(src, id) end
        if fnName == 'ReleaseRequest' then return exports['pf-services']:ReleaseRequest(src, id) end
        return exports['pf-services']:CompleteRequest(src, id, {})
    end)
    if not ok or type(res) ~= 'table' then return fail(src, 'services_offline', quiet) end
    T.Push(src)
    if not res.ok then return { ok = false, error = res.error or 'refused' } end
    return { ok = true }
end

function T.AcceptRequest(src, id, quiet) return servicesCall(src, 'AcceptRequest', id, quiet) end
function T.CompleteRequest(src, id, quiet) return servicesCall(src, 'CompleteRequest', id, quiet) end
--- Gives an accepted request back to the queue (pf-services checks it is this driver's).
function T.ReleaseRequest(src, id, quiet) return servicesCall(src, 'ReleaseRequest', id, quiet) end

--- A pf-services tow request was completed (server/apps/tow_requests.lua): XP and the record.
function T.CreditRequest(req)
    if type(req) ~= 'table' or type(req.assignee) ~= 'string' then return false end
    credit(req.assignee, 'requests', tonumber(cfg().RequestXP) or 80, tonumber(req.reward) or 0)
    return true
end

-- Tow drivers' apps refresh when a tow request changes.
AddEventHandler('pf-services:requestChanged', function(req)
    if type(req) ~= 'table' or type(req.kind) ~= 'string' or req.kind:sub(1, 4) ~= 'tow.' then return end
    pcall(function() exports['pf-devices']:PushToJob(cfg().Job, 'tow', 'requests', { id = req.id, status = req.status }, false) end)
end)

-- ── view and pushes ─────────────────────────────────────────────────

local function publicContract(c)
    if not c then return nil end
    return { id = c.id, model = c.model, plate = c.plate, stage = c.stage, pay = c.pay, xp = c.xp,
        km = math.floor(c.km * 10 + 0.5) / 10, x = c.coords.x, y = c.coords.y, z = c.coords.z, startedAt = c.startedAt }
end

local function publicRental(r)
    if not r then return nil end
    return { model = r.model, label = r.label, plate = r.plate, deposit = r.deposit, orphaned = r.orphaned == true,
        present = not r.orphaned and exists(r.vehicle), lost = r.orphaned == true and r.truckLost == true,
        refund = r.orphaned and orphanRefund(r) or nil }
end

--- Whether src works for the tow company (on duty or not): the whole Tow app.
function T.IsDriver(src)
    return towPlayer(src, false) ~= nil
end

--- Whether src's character has a flatbed rental open (a truck out, or a deposit to settle at the bay).
function T.HasRental(src)
    if not cfg().Enabled then return false end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData then return false end
    return rentalOf(Player.PlayerData.citizenid) ~= nil
end

--- Whether a delivered contract's pay is still owed to src's character (the bank missed it).
function T.HasOwed(src)
    if not cfg().Enabled then return false end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData then return false end
    return Owed[Player.PlayerData.citizenid] ~= nil
end

--- What the Tow app shows a player outside the tow job: only their rental (and a car still on its
--- bed, which has to come off before the return) and pay still owed to them, never the dispatch
--- requests, the offers, levels or anything else of the job.
function T.ReturnView(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    local h = Hooks[src]
    local b = bay()
    local owed = Owed[Player.PlayerData.citizenid]
    return {
        playerId = src,
        returnOnly = true,
        rental = publicRental(rentalOf(Player.PlayerData.citizenid)),
        owed = owed and { plate = owed.plate, model = owed.model, pay = owed.pay } or nil,
        hook = h and { plate = h.plate } or nil,
        atBay = nearBay(src),
        depot = b and { label = (cfg().Depot or {}).label, x = b.x, y = b.y } or nil,
    }
end

--- Everything the Tow app shows for this player.
function T.View(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    local cid = Player.PlayerData.citizenid
    local job = Player.PlayerData.job or {}
    local st = stats(cid)
    local level, nextLevel = levelOf(st.xp)
    local r = rentalOf(cid)
    local h = Hooks[src]
    local c = Contracts[src] or Owed[cid]
    local drop = cfg().DropOff
    local b = bay()
    local vehicles = {}
    for _, v in ipairs(cfg().Vehicles or {}) do
        vehicles[#vehicles + 1] = { model = v.model, label = v.label, deposit = v.deposit, minLevel = v.minLevel or 1, unlocked = level.level >= (v.minLevel or 1) }
    end
    local levels = {}
    for i, l in ipairs(cfg().Levels or {}) do levels[i] = { level = l.level, xp = l.xp, title = l.title, maxKm = l.maxKm, payMultiplier = l.payMultiplier } end
    local requests = requestList(cid)
    return {
        playerId = src,
        onDuty = job.onduty == true,
        stats = { xp = st.xp, contracts = st.contracts, requests = st.requests, towed = st.towed, earned = st.earned },
        level = { level = level.level, title = level.title, xp = level.xp, nextXp = nextLevel and nextLevel.xp or nil,
            maxKm = level.maxKm, payMultiplier = level.payMultiplier },
        levels = levels,
        vehicles = vehicles,
        rental = publicRental(r),
        hook = h and { plate = h.plate, contract = c ~= nil and c.vehicle == h.target } or nil,
        contract = publicContract(c),
        requests = requests or {},
        servicesOnline = requests ~= nil,
        contractBlocker = contractBlocker(src, cid),
        atBay = nearBay(src),
        depot = b and { label = (cfg().Depot or {}).label, x = b.x, y = b.y } or nil,
        dropOff = drop and { label = drop.label, x = drop.coords.x, y = drop.coords.y } or nil,
    }
end

--- Tells the player's client (map blips) and open Tow app that something changed.
function T.Push(src)
    if not src then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local c = Contracts[src]
    local h = Hooks[src]
    local drop = cfg().DropOff
    TriggerClientEvent('pf-jobs:tow:client:state', src, {
        contract = c and { x = c.coords.x, y = c.coords.y, z = c.coords.z, stage = c.stage, plate = c.plate, netId = c.netId } or nil,
        hooked = h ~= nil,
        -- a player who left the tow job keeps a return-only yard target while a rental is open
        rental = rentalOf(Player.PlayerData.citizenid) ~= nil,
        dropOff = drop and { x = drop.coords.x, y = drop.coords.y, z = drop.coords.z } or nil,
    })
end

-- ── world events ────────────────────────────────────────────────────

RegisterNetEvent('pf-jobs:tow:server:rent', function(model) T.Rent(source, type(model) == 'string' and model or nil) end)
RegisterNetEvent('pf-jobs:tow:server:return', function() T.Return(source) end)
RegisterNetEvent('pf-jobs:tow:server:reportLost', function() T.ReportLost(source) end)
RegisterNetEvent('pf-jobs:tow:server:hook', function(netId) T.Hook(source, netId) end)
RegisterNetEvent('pf-jobs:tow:server:unhook', function() T.Unhook(source) end)
RegisterNetEvent('pf-jobs:tow:server:nextContract', function() T.StartContract(source) end)
RegisterNetEvent('pf-jobs:tow:server:cancelContract', function() T.CancelContract(source) end)
RegisterNetEvent('pf-jobs:tow:server:sync', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local r = Rentals[Player.PlayerData.citizenid]
    if r and not r.orphaned and exists(r.vehicle) and r.src == src then TriggerClientEvent('pf-jobs:tow:client:flatbed', src, r.netId, r.plate, true) end
    T.Push(src)
end)

-- A disconnect: the hook and contract end, the truck is removed and the rental is "orphaned",
-- settled at the bay later. The truck's state is recorded first, so leaving does not turn a lost or
-- wrecked truck into a full refund: gone or away from the bay counts as lost, otherwise its health
-- sets the deduction. A delivered contract the bank missed stays claimable.
function T.Dropped(src)
    local h = Hooks[src]
    if h then HookedBy[h.target] = nil end
    Hooks[src] = nil
    local c = Contracts[src]
    if c and c.stage ~= 'payment_due' and c.stage ~= 'delivered' then dropContract(src, c) end
    Contracts[src] = nil
    -- collected first: saving waits on the database, and Rentals must not change under pairs()
    local mine = {}
    for cid, r in pairs(Rentals) do
        if r.src == src and not r.orphaned then mine[#mine + 1] = { cid = cid, r = r } end
    end
    for _, m in ipairs(mine) do
        local r = m.r
        -- a server shutdown drops every player: their trucks vanish with the server, not through
        -- them, so the state stays unknown and the deposit comes back in full after the restart
        if not T.shuttingDown then
            local here = exists(r.vehicle) and bay() ~= nil
                and #(GetEntityCoords(r.vehicle) - v3(bay())) <= (tonumber(cfg().ReturnRadius) or 25.0)
            r.truckLost = not here
            r.truckHealth = here and truckHealth(r.vehicle) or 0
            saveTruckState(m.cid, r)
        end
        if exists(r.vehicle) then DeleteEntity(r.vehicle) end
        r.vehicle, r.netId, r.orphaned = nil, nil, true
    end
    LastSpot[src], LastContractAt[src], ContractTimes[src] = nil, nil, nil
end

AddEventHandler('playerDropped', function() T.Dropped(source) end)

-- A job change while the Tow app is open: the state push makes the app fetch its view again
-- (client/devices_bridge.lua forwards it), so a player who just left the tow job and keeps the app
-- for a rental or owed pay sees the return-only view at once, not the driver's layout.
AddEventHandler('QBCore:Server:OnJobUpdate', function(src)
    src = tonumber(src)
    if not src or not cfg().Enabled then return end
    if Hooks[src] or T.HasRental(src) or T.HasOwed(src) then T.Push(src) end
end)

-- txAdmin announces a restart, then drops every player while the server still runs. Only txAdmin
-- itself (the 'monitor' resource) can raise this; a client never can (it is not a net event).
AddEventHandler('txAdmin:events:serverShuttingDown', function()
    local invoker = GetInvokingResource and GetInvokingResource() or nil
    if invoker ~= nil and invoker ~= 'monitor' then return end
    T.shuttingDown = true
end)

-- The open rentals of every character are loaded once the tables exist: none has a truck now.
AddEventHandler('pf-jobs:server:schemaReady', function()
    if not cfg().UseDatabase then return end
    local ok, rows = pcall(MySQL.query.await, 'SELECT citizenid, rental_id, model, plate, deposit, truck_lost, truck_health FROM pf_tow_rentals', {})
    if not ok or type(rows) ~= 'table' then return end
    for _, row in ipairs(rows) do
        if row.citizenid and not Rentals[row.citizenid] then Rentals[row.citizenid] = rentalFromRow(row) end
        RentalChecked[row.citizenid] = true
    end
end)

-- Contract cars and rented trucks do not outlive the resource.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src, c in pairs(Contracts) do if exists(c.vehicle) then DeleteEntity(c.vehicle) end end
    for _, r in pairs(Rentals) do if exists(r.vehicle) then DeleteEntity(r.vehicle) end end
end)

--- A deleted character: its truck, contract and cached record go (its rows by server/schema.lua).
function T.ForgetCitizen(cid)
    local r = Rentals[cid]
    if r and exists(r.vehicle) then DeleteEntity(r.vehicle) end
    Rentals[cid], RentalChecked[cid], Stats[cid], Owed[cid], PendingDeposit[cid] = nil, nil, nil, nil, nil
    for src, c in pairs(Contracts) do
        if c.cid == cid then dropContract(src, c) end
    end
end

-- The flatbed may be spawned through pfm-core by the job too (job garages, pfm-core rules)
CreateThread(function()
    pcall(function() exports['pfm-core']:RegisterJobVehicles(cfg().Job or 'tow', cfg().HookModels or { 'flatbed' }) end)
end)

T.LevelOf = levelOf
