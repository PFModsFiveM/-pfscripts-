-- Tow job (client): the flatbed hook (pfm-towjob's attach), the tow yard and the map markers.
-- The server checks every hook, delivery, rental and payment; this script asks and shows.

local QBCore = exports['pfm-core']:GetCoreObject()

local CurrentTow, CurrentTruck = nil, nil
local Busy = false
local ContractBlip, DropBlip, YardBlip = nil, nil, nil
local YardZone = false

local function cfg() return Config.Tow or {} end
local function notify(msg, kind) QBCore.Functions.Notify(msg, kind or 'primary') end

local function isHookModel(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local model = GetEntityModel(veh)
    for _, m in ipairs(cfg().HookModels or {}) do
        if GetHashKey(m) == model then return true end
    end
    return false
end

-- pfm-towjob: the car in front of the player
local function getVehicleInDirection(coordFrom, coordTo)
    local rayHandle = CastRayPointToPoint(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 10, PlayerPedId(), 0)
    local _, _, _, _, vehicle = GetRaycastResult(rayHandle)
    return vehicle
end

local function control(entity)
    if not entity or entity == 0 then return end
    local t = 0
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and t < 50 do
        Wait(20)
        NetworkRequestControlOfEntity(entity)
        t = t + 1
    end
end

local REPAIR_ANIM = { animDict = 'mini@repair', anim = 'fixing_a_ped', flags = 16 }
local LOCK = { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true }

local function hookToggle()
    if Busy then return end
    local ped = PlayerPedId()
    local truck = GetVehiclePedIsIn(ped, true)
    if not isHookModel(truck) then
        notify('You must be at your flatbed', 'error')
        return
    end
    if not CurrentTow then
        if IsPedInAnyVehicle(ped, false) then
            notify('Get out of the truck first', 'error')
            return
        end
        local target = getVehicleInDirection(GetEntityCoords(ped, true), GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.0, 0.0))
        if not target or target == 0 or target == truck or not DoesEntityExist(target) or not IsEntityAVehicle(target) then
            notify('Face the car you want to tow', 'error')
            return
        end
        if #(GetEntityCoords(truck) - GetEntityCoords(target)) >= (tonumber(cfg().HookRange) or 11.0) then
            notify('The car is too far from the flatbed', 'error')
            return
        end
        if not NetworkGetEntityIsNetworked(target) then NetworkRegisterEntityAsNetworked(target) end
        Busy = true
        QBCore.Functions.Progressbar('towing_vehicle', 'Hoisting the vehicle...', 5000, false, true, LOCK, REPAIR_ANIM, {}, {}, function()
            StopAnimTask(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 1.0)
            TriggerServerEvent('pf-jobs:tow:server:hook', NetworkGetNetworkIdFromEntity(target))
            SetTimeout(5000, function() Busy = false end)
        end, function()
            StopAnimTask(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 1.0)
            Busy = false
            notify('Cancelled', 'error')
        end)
    else
        Busy = true
        QBCore.Functions.Progressbar('untowing_vehicle', 'Taking the vehicle off...', 5000, false, true, LOCK, REPAIR_ANIM, {}, {}, function()
            StopAnimTask(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 1.0)
            TriggerServerEvent('pf-jobs:tow:server:unhook')
            SetTimeout(5000, function() Busy = false end)
        end, function()
            StopAnimTask(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 1.0)
            Busy = false
            notify('Cancelled', 'error')
        end)
    end
end

RegisterCommand('tow', hookToggle)
RegisterNetEvent('pf-jobs:tow:client:hookToggle', hookToggle)
RegisterNetEvent('pf-jobs:tow:client:nextContract', function() TriggerServerEvent('pf-jobs:tow:server:nextContract') end)
RegisterCommand('towcontract', function() TriggerServerEvent('pf-jobs:tow:server:nextContract') end)

-- The server checked the hook: put the car on the bed (pfm-towjob's offsets).
RegisterNetEvent('pf-jobs:tow:client:attach', function(targetNet, truckNet)
    local target, truck = NetToVeh(targetNet), NetToVeh(truckNet)
    if not DoesEntityExist(target) or not DoesEntityExist(truck) then Busy = false return end
    control(target)
    AttachEntityToEntity(target, truck, GetEntityBoneIndexByName(truck, 'bodyshell'), 0.0, -1.5 + -0.85, 0.0 + 1.15, 0, 0, 0, 1, 1, 0, 1, 0, 1)
    FreezeEntityPosition(target, true)
    CurrentTow, CurrentTruck = target, truck
    Busy = false
    notify('Vehicle towed', 'success')
end)

RegisterNetEvent('pf-jobs:tow:client:detach', function(targetNet, truckNet)
    local target = NetToVeh(targetNet)
    if not DoesEntityExist(target) then target = CurrentTow end
    local truck = NetToVeh(truckNet)
    if not DoesEntityExist(truck) then truck = CurrentTruck end
    if target and DoesEntityExist(target) then
        control(target)
        FreezeEntityPosition(target, false)
        Wait(250)
        if truck and DoesEntityExist(truck) then
            AttachEntityToEntity(target, truck, 20, -0.0, -15.0, 1.0, 0.0, 0.0, 0.0, false, false, false, false, 20, true)
        end
        DetachEntity(target, true, true)
    end
    CurrentTow, CurrentTruck = nil, nil
    Busy = false
    notify('Vehicle taken off', 'success')
end)

-- ── the rented flatbed ──────────────────────────────────────────────

RegisterNetEvent('pf-jobs:tow:client:flatbed', function(netId, plate, resync)
    local t = 0
    while not NetworkDoesNetworkIdExist(netId) and t < 300 do Wait(10) t = t + 1 end
    local veh = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
    t = 0
    while (veh == 0 or not DoesEntityExist(veh)) and t < 200 do Wait(10) veh = NetToVeh(netId) t = t + 1 end
    if veh == 0 or not DoesEntityExist(veh) then return end
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    if resync then return end
    pcall(function() exports['LegacyFuel']:SetFuel(veh, 100.0) end)
    for i = 1, 9 do SetVehicleExtra(veh, i, 0) end
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    SetVehicleEngineOn(veh, true, true, false)
end)

RegisterNetEvent('pf-jobs:tow:client:flatbedReturned', function()
    CurrentTow, CurrentTruck = nil, nil
end)

-- ── map: contract car and drop-off ──────────────────────────────────

local function clearBlip(b) if b and DoesBlipExist(b) then RemoveBlip(b) end return nil end

local function routeBlip(x, y, z, sprite, label)
    local b = AddBlipForCoord(x, y, z)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, 3)
    SetBlipRoute(b, true)
    SetBlipRouteColour(b, 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    return b
end

local DrawDrop = nil
RegisterNetEvent('pf-jobs:tow:client:state', function(state)
    state = type(state) == 'table' and state or {}
    ContractBlip = clearBlip(ContractBlip)
    DropBlip = clearBlip(DropBlip)
    DrawDrop = nil
    local c = state.contract
    if c and c.stage == 'pickup' then
        ContractBlip = routeBlip(c.x, c.y, c.z, 380, 'Breakdown: ' .. tostring(c.plate or ''))
    elseif c and c.stage == 'deliver' and state.dropOff then
        DropBlip = routeBlip(state.dropOff.x, state.dropOff.y, state.dropOff.z, 68, 'Tow drop-off')
        DrawDrop = state.dropOff
    end
end)

CreateThread(function()
    while true do
        if DrawDrop then
            DrawMarker(1, DrawDrop.x, DrawDrop.y, DrawDrop.z - 1.0, 0, 0, 0, 0, 0, 0, 8.0, 8.0, 1.0, 230, 120, 30, 120, false, false, 2, false, nil, nil, false)
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- ── the tow yard (tow job only) ─────────────────────────────────────

RegisterNetEvent('pf-jobs:tow:client:rent', function(data)
    TriggerServerEvent('pf-jobs:tow:server:rent', type(data) == 'table' and data.model or nil)
end)
RegisterNetEvent('pf-jobs:tow:client:return', function() TriggerServerEvent('pf-jobs:tow:server:return') end)

local function setupYard(job)
    local isTow = type(job) == 'table' and job.name == cfg().Job and cfg().Enabled
    if not isTow then
        YardBlip = clearBlip(YardBlip)
        if YardZone then pcall(function() exports['pfm-target']:RemoveZone('pf_tow_yard') end) YardZone = false end
        return
    end
    local depot, bay = cfg().Depot, cfg().FlatbedSpawn
    if depot and not YardBlip then
        YardBlip = AddBlipForCoord(depot.coords.x, depot.coords.y, depot.coords.z)
        SetBlipSprite(YardBlip, 477)
        SetBlipDisplay(YardBlip, 4)
        SetBlipScale(YardBlip, 0.6)
        SetBlipAsShortRange(YardBlip, true)
        SetBlipColour(YardBlip, 15)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(depot.label or 'Tow yard')
        EndTextCommandSetBlipName(YardBlip)
    end
    if bay and not YardZone then
        local options = {}
        for _, v in ipairs(cfg().Vehicles or {}) do
            options[#options + 1] = { type = 'client', event = 'pf-jobs:tow:client:rent', icon = 'fas fa-truck-pickup',
                label = ('Rent a %s ($%d deposit)'):format(v.label or v.model, v.deposit or 0), model = v.model }
        end
        options[#options + 1] = { type = 'client', event = 'pf-jobs:tow:client:return', icon = 'fas fa-warehouse', label = 'Return the flatbed' }
        options[#options + 1] = { type = 'client', event = 'pf-jobs:tow:client:nextContract', icon = 'fas fa-clipboard-list', label = 'Ask for a tow contract' }
        YardZone = pcall(function()
            exports['pfm-target']:AddBoxZone('pf_tow_yard', vector3(bay.x, bay.y, bay.z), 6.0, 6.0, {
                name = 'pf_tow_yard', heading = bay.w or 0, debugPoly = false, minZ = bay.z - 2.0, maxZ = bay.z + 3.0,
            }, { options = options, distance = 4.0 })
        end)
    end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    setupYard(QBCore.Functions.GetPlayerData().job)
    TriggerServerEvent('pf-jobs:tow:server:sync')
end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) setupYard(job) end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local data = QBCore.Functions.GetPlayerData()
    if data and data.job then
        setupYard(data.job)
        TriggerServerEvent('pf-jobs:tow:server:sync')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ContractBlip = clearBlip(ContractBlip)
    DropBlip = clearBlip(DropBlip)
    YardBlip = clearBlip(YardBlip)
end)
