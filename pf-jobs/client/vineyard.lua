-- Vineyard world script (moved here from [qb]/pfm-vineyard/client.lua): the office, the vine the
-- server sends you to, the juice press, the wine barrels and the wholesale buyer. Positions and
-- timings come from the server (pf-jobs:vineyard:getConfig); the server checks the job, the place,
-- the vine and every timer (server/apps/vineyard.lua).

local QBCore = exports['pfm-core']:GetCoreObject()

local cfg = nil
local state = { onShift = false, vine = nil, pressing = false, barrel = nil }
local vineZone, vineBlip = nil, nil
local busy = false
local built = false

local function isWorker()
    local data = QBCore.Functions.GetPlayerData()
    return data and data.job and data.job.name == (cfg and cfg.job or 'vineyard')
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 200 do Wait(10) tries = tries + 1 end
end

local function clearVine()
    if vineZone then exports['pfm-target']:RemoveZone(vineZone) vineZone = nil end
    if vineBlip and DoesBlipExist(vineBlip) then RemoveBlip(vineBlip) end
    vineBlip = nil
end

local function progress(name, label, ms, anim, done, cancelled)
    busy = true
    QBCore.Functions.Progressbar(name, label, ms, false, true, {
        disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
    }, anim or {}, {}, {}, function()
        busy = false
        ClearPedTasks(PlayerPedId())
        done()
    end, function()
        busy = false
        ClearPedTasks(PlayerPedId())
        QBCore.Functions.Notify('You stopped', 'error')
        if cancelled then cancelled() end
    end)
end

local function pick()
    if busy or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local ms = math.random(cfg.pickSeconds[1] * 1000, cfg.pickSeconds[2] * 1000)
    progress('pfj_vine_pick', 'Picking grapes', ms, { animDict = 'amb@prop_human_bum_bin@idle_a', anim = 'idle_a', flags = 47 }, function()
        TriggerServerEvent('pf-jobs:vineyard:pick')
    end)
end

local function showVine(index)
    clearVine()
    local v = index and cfg.vines[index]
    if not v then return end
    vineBlip = AddBlipForCoord(v.x, v.y, v.z)
    SetBlipSprite(vineBlip, 465)
    SetBlipScale(vineBlip, 1.0)
    SetBlipAsShortRange(vineBlip, false)
    SetBlipRoute(vineBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Vine to pick')
    EndTextCommandSetBlipName(vineBlip)
    vineZone = 'pfj_vine_' .. index
    exports['pfm-target']:AddBoxZone(vineZone, vector3(v.x, v.y, v.z), 1.75, 3.0, {
        name = vineZone, heading = 0.0, minZ = v.z - 1.0, maxZ = v.z + 1.5, debugPoly = false,
    }, { options = { { type = 'client', icon = 'fas fa-seedling', label = 'Pick grapes', action = pick, canInteract = function() return not busy end } }, distance = 2.0 })
end

local function applyState(s)
    s = type(s) == 'table' and s or {}
    local vineChanged = s.vine ~= state.vine
    state.onShift, state.vine, state.pressing, state.barrel = s.onShift == true, s.vine, s.pressing == true, s.barrel
    if vineChanged then showVine(state.vine) end
end

RegisterNetEvent('pf-jobs:vineyard:state', function(s) if cfg then applyState(s) end end)

local function press()
    if busy then return end
    QBCore.Functions.TriggerCallback('pf-jobs:vineyard:startJuice', function(ok)
        if not ok then return end
        loadDict('amb@code_human_wander_rain@male_a@base')
        local ms = math.random(cfg.juiceSeconds[1] * 1000, cfg.juiceSeconds[2] * 1000)
        progress('pfj_vine_press', 'Pressing grapes', ms, { animDict = 'amb@code_human_wander_rain@male_a@base', anim = 'static', flags = 47 }, function()
            TriggerServerEvent('pf-jobs:vineyard:collectJuice')
        end)
    end)
end

-- asks the server: it keeps the barrel's time
local function checkBarrel()
    QBCore.Functions.TriggerCallback('pf-jobs:vineyard:getConfig', function(c)
        local b = type(c) == 'table' and c.state and c.state.barrel or nil
        state.barrel = b
        if not b then QBCore.Functions.Notify('Your barrel is empty', 'primary')
        elseif b.ready then QBCore.Functions.Notify('Your wine is ready to bottle', 'success')
        else QBCore.Functions.Notify(('Your wine is fermenting: ready in %d s'):format(tonumber(b.readyIn) or 0), 'primary') end
    end)
end

local function zone(name, place, options)
    local c = place.coords
    local size = place.size or { 4.0, 4.0 }
    exports['pfm-target']:AddBoxZone(name, vector3(c.x, c.y, c.z), size[1], size[2], {
        name = name, heading = place.heading or 0.0, minZ = c.z - 1.0, maxZ = c.z + 2.0, debugPoly = false,
    }, { options = options, distance = 2.5 })
end

local function build()
    if built or not cfg then return end
    built = true
    zone('pfj_vine_office', cfg.start, {
        { type = 'client', icon = 'fas fa-play', label = 'Start picking shift', action = function() TriggerServerEvent('pf-jobs:vineyard:startShift') end,
            canInteract = function() return isWorker() and not state.onShift end },
        { type = 'client', icon = 'fas fa-stop', label = 'End picking shift', action = function() TriggerServerEvent('pf-jobs:vineyard:endShift') end,
            canInteract = function() return isWorker() and state.onShift end },
    })
    zone('pfj_vine_press', cfg.press, {
        { type = 'client', icon = 'fas fa-wine-bottle', label = 'Press grape juice', action = press,
            canInteract = function() return isWorker() and not busy and not state.pressing end },
        { type = 'client', icon = 'fas fa-hand-holding', label = 'Collect the juice', action = function() TriggerServerEvent('pf-jobs:vineyard:collectJuice') end,
            canInteract = function() return isWorker() and not busy and state.pressing end },
    })
    zone('pfj_vine_winery', cfg.winery, {
        { type = 'client', icon = 'fas fa-wine-glass', label = 'Fill a barrel with grape juice', action = function()
            QBCore.Functions.TriggerCallback('pf-jobs:vineyard:loadWine', function() end)
        end, canInteract = function() return isWorker() and state.barrel == nil end },
        { type = 'client', icon = 'fas fa-clock', label = 'Check the barrel', action = checkBarrel,
            canInteract = function() return isWorker() and state.barrel ~= nil end },
        { type = 'client', icon = 'fas fa-wine-bottle', label = 'Bottle the wine', action = function() TriggerServerEvent('pf-jobs:vineyard:collectWine') end,
            canInteract = function() return isWorker() and state.barrel ~= nil end },
    })
    if cfg.sell then
        zone('pfj_vine_sell', cfg.sell, {
            { type = 'client', icon = 'fas fa-dollar-sign', label = 'Sell wine and grape juice', action = function() TriggerServerEvent('pf-jobs:vineyard:sell') end },
        })
    end
end

local function load()
    QBCore.Functions.TriggerCallback('pf-jobs:vineyard:getConfig', function(c)
        if type(c) ~= 'table' or not c.start then return end
        cfg = c
        build()
        applyState(c.state)
    end)
end

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    load()
end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() load() end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() applyState({}) end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearVine() end
end)
