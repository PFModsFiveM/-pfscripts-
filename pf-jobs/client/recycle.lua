-- Recycling plant world script (moved here from [qb]/pfm-recyclejob/client.lua): the blip, the door,
-- the shelves, the duty desk, the sorting table and the buyer. Positions and timings come from the
-- server (pf-jobs:recycle:getConfig) and the server decides everything: which package to take,
-- whether it was carried, what it sorts into and what the shift pays (server/apps/recycle.lua).

local QBCore = exports['pfm-core']:GetCoreObject()

local cfg = nil
local state = { onShift = false, target = nil, carrying = false }
local props = {}
local carryObject = nil
local busy = false
local built = false
local blip = nil

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 200 do Wait(10) tries = tries + 1 end
    return hash
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 200 do Wait(10) tries = tries + 1 end
end

local function outline(index, on)
    local obj = index and props[index]
    if not obj or not DoesEntityExist(obj) then return end
    SetEntityDrawOutline(obj, on and cfg.outline == true)
    if on then SetEntityDrawOutlineColor(15, 20, 60, 255) end
end

local function holdBox()
    if carryObject then return end
    local ped = PlayerPedId()
    loadDict('anim@heists@box_carry@')
    TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 5.0, -1, -1, 50, 0, false, false, false)
    local pos = GetEntityCoords(ped)
    local obj = CreateObject(loadModel(cfg.boxModel), pos.x, pos.y, pos.z, true, true, true)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, 57005), 0.05, 0.1, -0.3, 300.0, 250.0, 20.0, true, true, false, true, 1, true)
    carryObject = obj
end

local function dropBox()
    if not carryObject then return end
    ClearPedTasks(PlayerPedId())
    DetachEntity(carryObject, true, true)
    DeleteObject(carryObject)
    carryObject = nil
end

-- the server's view of the shift: outline the package it chose, show or drop the box
local function applyState(s)
    s = type(s) == 'table' and s or {}
    if state.target and state.target ~= s.target then outline(state.target, false) end
    state.onShift, state.target, state.carrying = s.onShift == true, s.target, s.carrying == true
    if state.target then outline(state.target, true) end
    if state.carrying then holdBox() else dropBox() end
end

RegisterNetEvent('pf-jobs:recycle:state', function(s) if cfg then applyState(s) end end)

local function fade(to)
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(10) end
    SetEntityCoords(PlayerPedId(), to.x, to.y, to.z)
    SetEntityHeading(PlayerPedId(), to.w or 0.0)
    DoScreenFadeIn(500)
end

local function enter() fade(cfg.inside) end

local function exit()
    -- leaving the plant ends the shift (and pays it)
    if state.onShift then TriggerServerEvent('pf-jobs:recycle:clockOut', true) end
    dropBox()
    fade(vector4(cfg.outside.x, cfg.outside.y, cfg.outside.z + 1.0, cfg.outside.w))
end

local function progress(name, label, ms, done)
    busy = true
    QBCore.Functions.Progressbar(name, label, ms, false, true, {
        disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
    }, { animDict = 'mp_car_bomb', anim = 'car_bomb_mechanic', flags = 16 }, {}, {}, function()
        busy = false
        ClearPedTasks(PlayerPedId())
        done()
    end, function()
        busy = false
        ClearPedTasks(PlayerPedId())
    end)
end

local function pickUp()
    if busy or state.carrying then return end
    local ms = math.random(cfg.pickupSeconds[1] * 1000, cfg.pickupSeconds[2] * 1000)
    progress('pfj_recycle_pickup', 'Picking up the package', ms, function()
        TriggerServerEvent('pf-jobs:recycle:pickup')
    end)
end

local function sort()
    if busy or not state.carrying then return end
    dropBox()
    progress('pfj_recycle_sort', 'Sorting the package', cfg.sortSeconds * 1000, function()
        TriggerServerEvent('pf-jobs:recycle:handIn')
    end)
end

local function sellMenu()
    QBCore.Functions.TriggerCallback('pf-jobs:recycle:getPriceList', function(prices)
        local items = exports['pfm-core']:GetShared('Items') or {}
        local menu = { { header = 'Materials buyer', isMenuHeader = true } }
        for name, price in pairs(prices or {}) do
            if QBCore.Functions.HasItem(name) then
                local def = items[name] or { label = name }
                menu[#menu + 1] = {
                    header = def.label, txt = ('$%s each'):format(price),
                    icon = 'nui://pfm-inventory/html/images/' .. name .. '.png',
                    action = function()
                        local input = exports['pfm-input']:ShowInput({
                            header = 'Sell ' .. def.label, submitText = 'Sell',
                            inputs = { { text = 'Amount', name = 'amount', type = 'number', isRequired = true } },
                        })
                        local amount = input and tonumber(input.amount)
                        if amount and amount > 0 then TriggerServerEvent('pf-jobs:recycle:sell', name, math.floor(amount)) end
                    end,
                }
            end
        end
        if #menu == 1 then
            QBCore.Functions.Notify('You have nothing to sell', 'error')
            return
        end
        exports['pfm-menu']:openMenu(menu)
    end)
end

local function boxZone(name, at, label, action, canInteract, distance)
    exports['pfm-target']:AddBoxZone(name, vector3(at.x, at.y, at.z), 4.0, 1.5, {
        name = name, heading = 44.0, minZ = at.z - 1.0, maxZ = at.z + 2.0, debugPoly = false,
    }, { options = { { type = 'client', label = label, action = action, canInteract = canInteract } }, distance = distance or 1.5 })
end

local function build()
    if built or not cfg then return end
    built = true
    blip = AddBlipForCoord(cfg.outside.x, cfg.outside.y, cfg.outside.z)
    SetBlipSprite(blip, 365)
    SetBlipColour(blip, 2)
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Recycle Center')
    EndTextCommandSetBlipName(blip)

    for i, shelf in ipairs(cfg.shelves) do
        local model = cfg.shelfModels[((i - 1) % #cfg.shelfModels) + 1]
        local obj = CreateObject(loadModel(model), shelf.x, shelf.y, shelf.z, false, true, true)
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
        props[i] = obj
        exports['pfm-target']:AddTargetEntity(obj, {
            options = { {
                type = 'client', label = 'Get package', icon = 'fas fa-box', action = pickUp,
                canInteract = function() return state.onShift and state.target == i and not state.carrying and not busy end,
            } },
            distance = 1.5,
        })
    end

    boxZone('pfj_recycle_enter', cfg.outside, 'Enter warehouse', enter, nil, 1.0)
    boxZone('pfj_recycle_exit', cfg.inside, 'Exit warehouse', exit, nil, 1.0)
    exports['pfm-target']:AddBoxZone('pfj_recycle_desk', vector3(cfg.desk.x, cfg.desk.y, cfg.desk.z), 4.0, 1.5, {
        name = 'pfj_recycle_desk', heading = 44.0, minZ = cfg.desk.z - 1.0, maxZ = cfg.desk.z + 2.0, debugPoly = false,
    }, { options = {
        { type = 'client', label = 'Clock in', action = function() TriggerServerEvent('pf-jobs:recycle:clockIn') end, canInteract = function() return not state.onShift end },
        { type = 'client', label = 'Clock out', action = function() TriggerServerEvent('pf-jobs:recycle:clockOut', false) end, canInteract = function() return state.onShift end },
    }, distance = 1.0 })
    boxZone('pfj_recycle_sort', cfg.drop, 'Sort the package', sort, function() return state.carrying and not busy end, 1.5)

    if cfg.sellPed then
        local loc = cfg.sellPed
        local ped = CreatePed(4, loadModel('s_m_m_dockwork_01'), loc.x, loc.y, loc.z, loc.w, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        props.buyer = ped
        exports['pfm-target']:AddTargetEntity(ped, {
            options = { { icon = 'fas fa-dollar-sign', label = 'Sell materials', action = sellMenu } },
            distance = 1.5,
        })
    end
end

local function load()
    QBCore.Functions.TriggerCallback('pf-jobs:recycle:getConfig', function(c)
        if type(c) ~= 'table' or not c.outside then return end
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
    if resource ~= GetCurrentResourceName() then return end
    for _, obj in pairs(props) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    dropBox()
    if blip then RemoveBlip(blip) end
end)
