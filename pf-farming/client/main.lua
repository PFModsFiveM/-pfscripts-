-- pf-farming client: shows the plots of the field you are in and sends water/harvest/clear requests.
-- The server decides everything (position, growth, yield); this file only draws and asks.

local QBCore = exports['pfm-core']:GetCoreObject()
local currentField, plots, props = nil, {}, {}
local REFRESH_MS = 20000

local function clearProps()
    for _, obj in pairs(props) do if DoesEntityExist(obj) then DeleteObject(obj) end end
    props = {}
end

local function modelFor(plot)
    local models = Config.Farming.StageModels
    if plot.status == 'ripe' then return models[#models] end
    local stage = math.min(#models - 1, math.floor((plot.progress or 0) * (#models - 1)) + 1)
    return models[stage]
end

local function spawnProps()
    clearProps()
    for _, plot in ipairs(plots) do
        local model = joaat(modelFor(plot))
        RequestModel(model)
        local tries = 0
        while not HasModelLoaded(model) and tries < 50 do Wait(20) tries = tries + 1 end
        if HasModelLoaded(model) then
            local obj = CreateObject(model, plot.x, plot.y, plot.z, false, false, false)
            FreezeEntityPosition(obj, true)
            PlaceObjectOnGroundProperly(obj)
            props[plot.id] = obj
            SetModelAsNoLongerNeeded(model)
        end
    end
end

local function refresh()
    if not currentField then return end
    QBCore.Functions.TriggerCallback('pf-farming:server:getField', function(list)
        plots = type(list) == 'table' and list or {}
        spawnProps()
    end, currentField)
end

RegisterNetEvent('pf-farming:client:fieldChanged', function(fieldName)
    if fieldName == currentField then refresh() end
end)

local function draw3d(x, y, z, text)
    SetTextScale(0.33, 0.33)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetDrawOrigin(x, y, z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- which field we are in
CreateThread(function()
    local lastRefresh = 0
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local found
        for name, field in pairs(Config.Farming.Fields) do
            if #(pos - field.coords) <= field.radius + 50.0 then found = name break end
        end
        if found ~= currentField then
            currentField = found
            plots = {}
            clearProps()
            if found then refresh() lastRefresh = GetGameTimer() end
        elseif found and GetGameTimer() - lastRefresh > REFRESH_MS then
            refresh()
            lastRefresh = GetGameTimer()
        end
        Wait(2000)
    end
end)

-- interaction with your own nearest plot
CreateThread(function()
    while true do
        local sleep = 1000
        if currentField and #plots > 0 then
            local pos = GetEntityCoords(PlayerPedId())
            local best, bestDist
            for _, plot in ipairs(plots) do
                local d = #(pos - vector3(plot.x, plot.y, plot.z))
                if plot.mine and d < Config.Farming.PlantRange and (not bestDist or d < bestDist) then best, bestDist = plot, d end
            end
            if best then
                sleep = 0
                local crop = Config.Farming.Crops[best.crop]
                local label = crop and crop.label or best.crop
                local text
                if best.status == 'ripe' then
                    text = ('%s: ripe  ~g~[E]~w~ harvest'):format(label)
                    if IsControlJustReleased(0, 38) then TriggerServerEvent('pf-farming:server:harvest', best.id) end
                elseif best.status == 'dead' then
                    text = ('%s: dead  ~r~[G]~w~ clear'):format(label)
                else
                    text = ('%s: %d%%  ~b~[E]~w~ water  [G] clear'):format(label, math.floor((best.progress or 0) * 100))
                    if IsControlJustReleased(0, 38) then TriggerServerEvent('pf-farming:server:water', best.id) end
                end
                if IsControlJustReleased(0, 47) then TriggerServerEvent('pf-farming:server:clear', best.id) end
                draw3d(best.x, best.y, best.z + 1.0, text)
            end
        end
        Wait(sleep)
    end
end)

-- market blip
CreateThread(function()
    local m = Config.Farming.Market
    local blip = AddBlipForCoord(m.coords.x, m.coords.y, m.coords.z)
    SetBlipSprite(blip, 52)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(m.label)
    EndTextCommandSetBlipName(blip)
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then clearProps() end
end)
