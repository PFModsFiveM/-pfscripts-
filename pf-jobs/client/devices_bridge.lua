-- Forwards the job events the server already sends this client to the Taxi, Bus, Garbage,
-- Gruppe 6 and Tow apps (html/apps/*.js) in whichever device is open (pf-devices AppEvent). The world side
-- of each job (blips, vehicles, the taxi meter, the scoreboard) keeps its own handlers for the
-- same events; FiveM runs every handler of an event.

local function toApp(app, event, payload)
    if GetResourceState('pf-devices') ~= 'started' then return end
    pcall(function() exports['pf-devices']:AppEvent(app, event, payload) end)
end

local function forward(netEvent, app, event, shape)
    RegisterNetEvent(netEvent, function(...)
        toApp(app, event, shape and shape(...) or (...))
    end)
end

-- Taxi
forward('pf-taxi:client:updateStats', 'taxi', 'updateStats')
forward('pf-taxi:client:callsData', 'taxi', 'callsData', function(calls) return calls or {} end)
forward('pf-taxi:client:startCall', 'taxi', 'startCall')
forward('pf-taxi:client:rideStarted', 'taxi', 'rideStarted', function(rideId, ride) return { rideId = rideId, ride = ride } end)
forward('pf-taxi:client:rideCompleted', 'taxi', 'rideCompleted', function(data) return data or {} end)
forward('pf-taxi:client:rideCancelled', 'taxi', 'rideCancelled', function() return {} end)
forward('pf-taxi:client:vehicleSpawned', 'taxi', 'rental', function(_, plate) return { active = true, plate = plate } end)
forward('pf-taxi:client:rentalReturned', 'taxi', 'rental', function() return { active = false } end)
-- the meter is pushed from client/taxi.lua, which owns it

-- Gruppe 6
forward('pf-jobs:gruppe6:contracts', 'gruppe6', 'contracts', function(c) return c or {} end)
forward('pf-jobs:gruppe6:activeContract', 'gruppe6', 'activeContract', function(c) return { contract = c } end)
forward('pf-jobs:gruppe6:updateXP', 'gruppe6', 'xp', function(xp, level) return { xp = xp, level = level } end)
forward('pf-jobs:gruppe6:groupUpdate', 'gruppe6', 'group', function(g) return { group = g } end)
forward('pf-jobs:gruppe6:receiveInvite', 'gruppe6', 'invite', function(name, id) return { leaderName = name, leaderId = id } end)
forward('pf-jobs:gruppe6:nextPickup', 'gruppe6', 'progress', function(_, _, bags) return { stage = 'pickup', bags = bags } end)
forward('pf-jobs:gruppe6:goToDeposit', 'gruppe6', 'progress', function() return { stage = 'deposit' } end)
forward('pf-jobs:gruppe6:depositProgress', 'gruppe6', 'progress', function(deposited, total) return { stage = 'deposit', deposited = deposited, total = total } end)
forward('pf-jobs:gruppe6:upgradesPurchased', 'gruppe6', 'upgrades', function() return {} end)

-- Garbage
forward('pf-jobs:garbage:groupUpdate', 'garbage', 'group', function(g) return { group = g } end)
forward('pf-jobs:garbage:receiveInvite', 'garbage', 'invite', function(name, id) return { leaderName = name, leaderId = id } end)
forward('pf-jobs:garbage:updateXP', 'garbage', 'xp', function(xp, level) return { xp = xp, level = level } end)
forward('pf-jobs:garbage:carrying', 'garbage', 'carrying', function(flag) return { carrying = flag == true } end)
forward('pf-jobs:garbage:updateDeposited', 'garbage', 'deposited', function(count, cap) return { count = count, cap = cap } end)
forward('pf-jobs:garbage:setActiveZone', 'garbage', 'zone', function(z) return { name = z and z.name, target = z and z.target } end)
forward('pf-jobs:garbage:vehicleSpawned', 'garbage', 'started', function(_, plate) return { plate = plate } end)
forward('pf-jobs:garbage:sessionEnded', 'garbage', 'ended', function() return {} end)
RegisterNetEvent('pf-jobs:client:updateScoreboard', function(title, subtitle)
    if title == 'Garbage Crew' then toApp('garbage', 'status', { text = subtitle }) end
end)

-- Bus
forward('bus:client:statsData', 'bus', 'stats')
forward('bus:client:updateStats', 'bus', 'stats')
forward('bus:client:routesData', 'bus', 'routes', function(r) return r or {} end)
forward('bus:client:loadRoute', 'bus', 'route', function(route, level) return { route = route, level = level } end)
forward('bus:client:stopCompleted', 'bus', 'stop', function(stop, total, info) return { stop = stop, total = total, info = info } end)
forward('bus:client:routeCancelled', 'bus', 'routeEnded', function() return { cancelled = true } end)
forward('bus:client:vehicleSpawned', 'bus', 'bus', function(_, plate) return { plate = plate } end)
forward('bus:client:busReturned', 'bus', 'bus', function() return {} end)

-- Tow
forward('pf-jobs:tow:client:state', 'tow', 'state', function(state) return state or {} end)
forward('pf-jobs:tow:client:flatbed', 'tow', 'state', function() return {} end)
forward('pf-jobs:tow:client:flatbedReturned', 'tow', 'state', function() return {} end)
