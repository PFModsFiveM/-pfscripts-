-- pf-jobs apps on the shared device platform (pf-devices): Taxi, Bus, Garbage and Gruppe 6, one
-- module each (html/apps/*.js) that runs unchanged in the tablet and the computer.
--
-- The handlers reuse the job code in server/apps/*.lua. Its net events and callbacks were recorded
-- by server/devices_capture.lua and run here with the player's real source, so every check in them
-- (job, distance, invites, ledger keys) still applies. What those handlers push to the client
-- (calls, contracts, party updates...) reaches the open app through client/devices_bridge.lua.
-- Every handler validates its payload before any job code runs, and reports success only when the
-- server state shows the action happened (the job code itself tells the player why it refused).

PFJobsDevices = PFJobsDevices or {}

local fire, call = PFJobsCapture.fire, PFJobsCapture.call

-- ── payload checks ──────────────────────────────────────────────────

local function refuse(message)
    return { ok = false, error = 'bad_request', message = message }
end

local function intIn(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v % 1 ~= 0 or v < lo or v > hi then return nil end
    return math.floor(v)
end

local function token(v, maxLen, pattern)
    if type(v) ~= 'string' or #v == 0 or #v > maxLen or not v:find(pattern) then return nil end
    return v
end

local function playerId(v) return intIn(v, 1, 65535) end

-- Party codes are 6 characters from GenerateGroupCode; accept a little either side, any case
local function groupCode(v)
    local code = token(v, 8, '^%w+$')
    if not code or #code < 4 then return nil end
    return code:upper()
end

-- Result of an action: ok when `done`, otherwise 'refused' (the job code already told the player why)
local function outcome(done, extra)
    local res = extra or {}
    res.ok = done == true
    if not res.ok then res.error = res.error or 'refused' end
    return res
end

-- ── Taxi ────────────────────────────────────────────────────────────

local function taxiDashboard(src)
    local answered, dashboard = call('pf-taxi:server:getInit', src)
    if not answered or type(dashboard) ~= 'table' then return nil end
    return dashboard
end

local function rideId(d) return d and d.activeRide and d.activeRide.id or nil end

local TaxiHandlers = {
    getInit = function(src)
        local dashboard = taxiDashboard(src)
        if not dashboard then return { ok = false, error = 'timeout' } end
        return { ok = true, dashboard = dashboard }
    end,

    getCalls = function(src)
        local answered, calls = call('pf-taxi:server:getCalls', src)
        if not answered then return { ok = false, error = 'timeout' } end
        return { ok = true, calls = type(calls) == 'table' and calls or {} }
    end,

    toggleAccepting = function(src, payload)
        if type(payload.accepting) ~= 'boolean' then return refuse('accepting must be true or false') end
        fire('pf-taxi:server:toggleAccepting', src, { accepting = payload.accepting })
        local dashboard = taxiDashboard(src)
        return outcome(dashboard ~= nil and dashboard.accepting == payload.accepting, { dashboard = dashboard })
    end,

    acceptCall = function(src, payload)
        local id = token(payload.id, 64, '^[%w_%-]+$')
        if not id then return refuse('unknown call') end
        local before = rideId(taxiDashboard(src))
        fire('pf-taxi:server:acceptCall', src, { id = id })
        local dashboard = taxiDashboard(src)
        local now = rideId(dashboard)
        return outcome(now ~= nil and now ~= before, { dashboard = dashboard })
    end,

    -- The world script completes a ride at the drop-off; this is the same request as /taxicomplete.
    -- The server checks the stage, the position and the time, and uses its own collision count.
    completeRide = function(src, payload)
        local id = token(payload.rideId, 64, '^[%w_%-]+$')
        if not id then return refuse('unknown ride') end
        if rideId(taxiDashboard(src)) ~= id then return { ok = false, error = 'no_active_ride' } end
        fire('pf-taxi:server:completeRide', src, id, {})
        local dashboard = taxiDashboard(src)
        return outcome(rideId(dashboard) ~= id, { dashboard = dashboard })
    end,

    cancelRide = function(src, payload)
        local id = payload.rideId ~= nil and token(payload.rideId, 64, '^[%w_%-]+$') or nil
        if payload.rideId ~= nil and not id then return refuse('unknown ride') end
        fire('pf-taxi:server:cancelRide', src, id)
        local dashboard = taxiDashboard(src)
        return outcome(id == nil or rideId(dashboard) ~= id, { dashboard = dashboard })
    end,

    rentVehicle = function(src, payload)
        local code = token(payload.spawnCode, 32, '^[%w_]+$')
        if not code then return refuse('unknown vehicle') end
        local before = taxiDashboard(src)
        if before and before.rental then return { ok = false, error = 'rental_active' } end
        fire('pf-taxi:server:rentVehicle', src, { spawnCode = code })
        local dashboard = taxiDashboard(src)
        return outcome(dashboard ~= nil and dashboard.rental ~= nil and dashboard.rental.spawnCode == code, { dashboard = dashboard })
    end,

    returnVehicle = function(src)
        local before = taxiDashboard(src)
        if not (before and before.rental) then return { ok = false, error = 'no_rental' } end
        fire('pf-taxi:server:returnVehicle', src)
        local dashboard = taxiDashboard(src)
        return outcome(dashboard ~= nil and dashboard.rental == nil, { dashboard = dashboard })
    end,

    getPhotos = function(src)
        local answered, result = call('pf-taxi:server:getPhotos', src)
        if not answered then return { ok = false, error = 'timeout' } end
        return { ok = true, photos = type(result) == 'table' and type(result.photos) == 'table' and result.photos or {} }
    end,
}

-- ── Gruppe 6 ────────────────────────────────────────────────────────

local function g6View(src, withXp)
    local answered, view = call('pf-jobs:gruppe6:getAppView', src, withXp == true)
    if not answered or type(view) ~= 'table' then return nil end
    return view
end

local function g6Config()
    local cfg = Config.Gruppe6 or {}
    local levels = {}
    for i, xp in ipairs(cfg.LevelThresholds or {}) do levels[i] = { level = i, xp = xp } end
    local tiers = {}
    for i, t in ipairs(cfg.Tiers or {}) do
        tiers[i] = { tier = i, label = t.label, minLevel = t.minLevel, bags = t.bags, payout = t.payout }
    end
    return {
        levels = levels,
        tiers = tiers,
        maxMembers = (cfg.Groups or {}).MaxMembers or 4,
        groupMultiplier = 1.5, -- server/apps/gruppe6.lua depositComplete: every member gets 1.5x
    }
end

local function g6Leader(view) return view and view.group and tonumber(view.group.leader) or nil end

local G6Handlers = {
    getInit = function(src)
        local view = g6View(src, true)
        if not view then return { ok = false, error = 'timeout' } end
        view.ok = true
        view.config = g6Config()
        return view
    end,

    refresh = function(src)
        local view = g6View(src, false)
        if not view then return { ok = false, error = 'timeout' } end
        view.ok = true
        return view
    end,

    startSearch = function(src)
        local before = g6View(src)
        if before and before.contract then return { ok = false, error = 'contract_active' } end
        fire('pf-jobs:gruppe6:startSearch', src)
        -- the tablet used to show this itself; the scoreboard belongs to the world UI
        TriggerClientEvent('pf-jobs:client:updateScoreboard', src, 'Gruppe6 Contractor', 'Waiting for job offer')
        local view = g6View(src)
        return outcome(view ~= nil and view.searching == true, { view = view })
    end,

    stopSearch = function(src)
        fire('pf-jobs:gruppe6:stopSearch', src)
        local view = g6View(src)
        if view and not view.contract then TriggerClientEvent('pf-jobs:client:hideScoreboard', src) end
        return outcome(view ~= nil and view.searching ~= true, { view = view })
    end,

    acceptContract = function(src, payload)
        local index = intIn(payload.index, 0, 9)
        if not index then return refuse('unknown contract') end
        local before = g6View(src)
        if before and before.contract then return { ok = false, error = 'contract_active' } end
        fire('pf-jobs:gruppe6:acceptContract', src, { contractId = index })
        local view = g6View(src)
        return outcome(view ~= nil and view.contract ~= nil, { view = view })
    end,

    endContract = function(src)
        fire('pf-jobs:gruppe6:endContract', src)
        local view = g6View(src)
        return outcome(view ~= nil and view.contract ~= nil and view.contract.earlyEnd == true, { view = view })
    end,

    createGroup = function(src)
        fire('pf-jobs:gruppe6:createGroup', src)
        local view = g6View(src)
        return outcome(g6Leader(view) == src, { view = view })
    end,

    invitePlayer = function(src, payload)
        local target = playerId(payload.targetId)
        if not target then return refuse('enter a player id') end
        if target == src then return refuse('you cannot invite yourself') end
        fire('pf-jobs:gruppe6:invitePlayer', src, target)
        return { ok = true, view = g6View(src) }
    end,

    joinByCode = function(src, payload)
        local code = groupCode(payload.code)
        if not code then return refuse('enter a party code') end
        fire('pf-jobs:gruppe6:joinByCode', src, code)
        local view = g6View(src)
        return outcome(view ~= nil and view.group ~= nil and view.group.groupCode == code, { view = view })
    end,

    acceptInvite = function(src, payload)
        local leader = playerId(payload.leaderId)
        if not leader then return refuse('unknown invite') end
        fire('pf-jobs:gruppe6:acceptInvite', src, leader)
        local view = g6View(src)
        return outcome(g6Leader(view) == leader, { view = view })
    end,

    declineInvite = function(src, payload)
        local leader = playerId(payload.leaderId)
        if not leader then return refuse('unknown invite') end
        fire('pf-jobs:gruppe6:declineInvite', src, leader)
        return { ok = true, view = g6View(src) }
    end,

    kickMember = function(src, payload)
        local target = playerId(payload.targetId)
        if not target or target == src then return refuse('unknown member') end
        fire('pf-jobs:gruppe6:kickMember', src, target)
        local view = g6View(src)
        local still = false
        for _, m in ipairs(view and view.group and view.group.members or {}) do
            if tonumber(m.id) == target then still = true end
        end
        return outcome(not still, { view = view })
    end,

    leaveGroup = function(src)
        fire('pf-jobs:gruppe6:leaveGroup', src)
        local view = g6View(src)
        return outcome(view ~= nil and view.group == nil, { view = view })
    end,

    disbandGroup = function(src)
        fire('pf-jobs:gruppe6:disbandGroup', src)
        local view = g6View(src)
        return outcome(view ~= nil and view.group == nil, { view = view })
    end,
}

-- ── Garbage ─────────────────────────────────────────────────────────

local function garbageState(src)
    local answered, state = call('pf-jobs:garbage:getInit', src)
    if not answered or type(state) ~= 'table' then return nil end
    return state
end

local function garbageConfig()
    local cfg = Config.Garbage or {}
    local levels = {}
    for i, xp in ipairs(cfg.LevelThresholds or {}) do
        local cap = (cfg.DepositCap or {})[i] or (cfg.DepositCap or {})[2]
        local areas = (cfg.LevelAreaUnlocks or {})[i]
        if not areas then
            -- levels above the last listed unlock keep its areas (BuildZonesForLevel falls back to all)
            for l = i, 1, -1 do if (cfg.LevelAreaUnlocks or {})[l] then areas = cfg.LevelAreaUnlocks[l] break end end
        end
        levels[i] = { level = i, xp = xp, payPerBag = (cfg.PayoutPerBag or {})[i], cap = cap, areas = areas or {} }
    end
    return {
        levels = levels,
        xpPerBag = cfg.XPPerBag,
        objectiveTarget = cfg.ObjectiveTarget,
        dumpstersPerZone = cfg.DumpstersPerZone,
        maxMembers = (cfg.Groups or {}).MaxMembers or 4,
        groupMultiplier = (cfg.Groups or {}).SharePayouts and 1.5 or nil, -- returnTruck pays every member 1.5x
    }
end

local function garbageLeader(state)
    local g = state and state.currentGroup
    return g and tonumber(g.leader) or nil
end

local GarbageHandlers = {
    getInit = function(src)
        local state = garbageState(src)
        if not state then return { ok = false, error = 'timeout' } end
        state.ok = true
        state.config = garbageConfig()
        return state
    end,

    startJob = function(src)
        local before = garbageState(src)
        if before and before.active then return { ok = false, error = 'run_active' } end
        fire('pf-jobs:garbage:startJob', src)
        local state = garbageState(src)
        return outcome(state ~= nil and state.active == true, { state = state })
    end,

    createGroup = function(src)
        fire('pf-jobs:garbage:createGroup', src)
        local state = garbageState(src)
        return outcome(garbageLeader(state) == src, { state = state })
    end,

    invitePlayer = function(src, payload)
        local target = playerId(payload.targetId)
        if not target then return refuse('enter a player id') end
        if target == src then return refuse('you cannot invite yourself') end
        fire('pf-jobs:garbage:invitePlayer', src, target)
        return { ok = true, state = garbageState(src) }
    end,

    joinByCode = function(src, payload)
        local code = groupCode(payload.code)
        if not code then return refuse('enter a crew code') end
        fire('pf-jobs:garbage:joinGroupByCode', src, code)
        local state = garbageState(src)
        return outcome(state ~= nil and state.currentGroup ~= nil and state.currentGroup.groupCode == code, { state = state })
    end,

    acceptInvite = function(src, payload)
        local leader = playerId(payload.leaderId)
        if not leader then return refuse('unknown invite') end
        fire('pf-jobs:garbage:acceptInvite', src, leader)
        local state = garbageState(src)
        return outcome(garbageLeader(state) == leader, { state = state })
    end,

    declineInvite = function(src, payload)
        local leader = playerId(payload.leaderId)
        if not leader then return refuse('unknown invite') end
        fire('pf-jobs:garbage:declineInvite', src, leader)
        return { ok = true, state = garbageState(src) }
    end,

    kickMember = function(src, payload)
        local target = playerId(payload.targetId)
        if not target or target == src then return refuse('unknown member') end
        fire('pf-jobs:garbage:kickMember', src, target)
        local state = garbageState(src)
        local still = false
        for _, m in ipairs(state and state.currentGroup and state.currentGroup.members or {}) do
            if tonumber(m.id) == target then still = true end
        end
        return outcome(not still, { state = state })
    end,

    leaveGroup = function(src)
        fire('pf-jobs:garbage:leaveGroup', src)
        local state = garbageState(src)
        return outcome(state ~= nil and state.currentGroup == nil, { state = state })
    end,

    disbandGroup = function(src)
        fire('pf-jobs:garbage:disbandGroup', src)
        local state = garbageState(src)
        return outcome(state ~= nil and state.currentGroup == nil, { state = state })
    end,
}

-- ── Bus ─────────────────────────────────────────────────────────────

local function busView(src)
    local answered, view = call('pf-jobs:bus:getAppView', src)
    if not answered or type(view) ~= 'table' then return nil end
    return view
end

local function busConfig()
    local cfg = Config.Bus or {}
    local pricing = cfg.Pricing or {}
    return {
        levels = cfg.Levels or {},
        payPerPassenger = pricing.BasePayPerPassenger,
        payPerMile = pricing.PayPerMile,
        onTimeBonus = pricing.OnTimeBonus,
        levelMultiplier = pricing.LevelMultiplier,
    }
end

local function activeRouteId(view) return view and view.activeRoute and view.activeRoute.routeId or nil end

local BusHandlers = {
    getInit = function(src)
        local view = busView(src)
        if not view then return { ok = false, error = 'timeout' } end
        view.ok = true
        view.config = busConfig()
        return view
    end,

    startRoute = function(src, payload)
        local route = intIn(payload.routeId, 1, 1000000)
        if not route then return refuse('unknown route') end
        if activeRouteId(busView(src)) then return { ok = false, error = 'route_active' } end
        fire('bus:server:startRoute', src, route)
        local view = busView(src)
        return outcome(activeRouteId(view) == route, { view = view })
    end,

    cancelRoute = function(src)
        if not activeRouteId(busView(src)) then return { ok = false, error = 'no_route' } end
        fire('bus:server:cancelRoute', src)
        local view = busView(src)
        return outcome(activeRouteId(view) == nil, { view = view })
    end,

    -- Stops and the route end are checked in by the bus itself (client/bus.lua: position, the bus
    -- and its health), exactly like /busstop and /buscomplete; the server then checks them again.
    checkInStop = function(src)
        if not activeRouteId(busView(src)) then return { ok = false, error = 'no_route' } end
        TriggerClientEvent('bus:client:completeStop', src)
        return { ok = true, pending = true }
    end,

    completeRoute = function(src)
        if not activeRouteId(busView(src)) then return { ok = false, error = 'no_route' } end
        TriggerClientEvent('bus:client:completeRoute', src)
        return { ok = true, pending = true }
    end,
}

-- ── registration ────────────────────────────────────────────────────

local DEVICES = { 'tablet', 'computer' }

--- The app definitions and their handlers. Taxi needs the taxi job when one is configured; the
--- side jobs are open to every citizen, so they come from the App Store.
function PFJobsDevices.Apps()
    local taxiJob = Config.Taxi and Config.Taxi.Job
    if type(taxiJob) ~= 'string' or taxiJob == '' then taxiJob = nil end
    local list = {
        {
            def = {
                id = 'taxi', name = 'Taxi', icon = '🚕', devices = DEVICES,
                entry = 'html/apps/taxi.js', styles = { 'html/apps/taxi.css' },
                category = 'jobs', order = 30,
                access = taxiJob and { jobs = { [taxiJob] = 0 } } or { installable = true },
                store = { description = 'Taxi dispatch: take calls, drive passengers, rent cabs and level up.', publisher = 'PF Jobs' },
                window = { width = 980, height = 660 },
                description = 'Dispatch calls, rides, rentals and your driver level',
            },
            handlers = TaxiHandlers,
        },
        {
            def = {
                id = 'gruppe6', name = 'Gruppe 6', icon = '🛡️', devices = DEVICES,
                entry = 'html/apps/gruppe6.js', styles = { 'html/apps/gruppe6.css' },
                category = 'jobs', order = 31,
                access = { installable = true },
                store = { description = 'Armored cash transport contracts: collect money bags around the city and deliver them to the vault, alone or with a party.', publisher = 'PF Jobs' },
                window = { width = 980, height = 660 },
                description = 'Cash transport contracts and parties',
            },
            handlers = G6Handlers,
        },
        {
            def = {
                id = 'garbage', name = 'Garbage', icon = '🗑️', devices = DEVICES,
                entry = 'html/apps/garbage.js', styles = { 'html/apps/gruppe6.css', 'html/apps/garbage.css' },
                category = 'jobs', order = 32,
                access = { installable = true },
                store = { description = 'Garbage collection runs: take a truck, clear dumpsters zone by zone and get paid per bag, alone or with a crew.', publisher = 'PF Jobs' },
                window = { width = 920, height = 640 },
                description = 'Garbage runs, crew and progression',
            },
            handlers = GarbageHandlers,
        },
    }
    -- the bus job is off in the shipped config (no routes); its app appears once it is enabled
    if Config.Bus and Config.Bus.Enabled then
        list[#list + 1] = {
            def = {
                id = 'bus', name = 'Bus', icon = '🚌', devices = DEVICES,
                entry = 'html/apps/bus.js', styles = { 'html/apps/bus.css' },
                category = 'jobs', order = 33,
                access = { installable = true },
                store = { description = 'City bus routes: pick a route for your level, serve every stop and earn per passenger and mile.', publisher = 'PF Jobs' },
                window = { width = 920, height = 640 },
                description = 'Bus routes, stats and levels',
            },
            handlers = BusHandlers,
        }
    end
    return list
end

PFJobsDevices.Handlers = { taxi = TaxiHandlers, gruppe6 = G6Handlers, garbage = GarbageHandlers, bus = BusHandlers }

function PFJobsDevices.Register()
    if GetResourceState('pf-devices') ~= 'started' then return false end
    local devices = exports['pf-devices']
    local all = true
    for _, app in ipairs(PFJobsDevices.Apps()) do
        local ok, err = devices:RegisterApp(app.def)
        if ok then
            ok, err = devices:RegisterAppHandlers(app.def.id, app.handlers)
        end
        if not ok then
            all = false
            print(('^1[pf-jobs]^7 device app %s not registered: %s'):format(app.def.id, tostring(err)))
        end
    end
    return all
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then PFJobsDevices.Register() end
end)

-- pf-devices raises this when it (re)starts and has an empty registry
AddEventHandler('pf-devices:server:ready', function()
    PFJobsDevices.Register()
end)
