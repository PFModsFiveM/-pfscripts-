local QBCore = exports['pfm-core']:GetCoreObject()

local nuiOpen = false
local currentGarage = nil

-------------------------------------------------
-- Helper: 3D Text
-------------------------------------------------
local function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

-------------------------------------------------
-- Open / Close NUI
-------------------------------------------------
local function OpenGarageNUI(garageId)
    if nuiOpen then return end
    nuiOpen = true
    currentGarage = garageId
    SetNuiFocus(true, true)

    QBCore.Functions.TriggerCallback('jobgarages:getGarageData', function(data)
        SendNUIMessage({
            action = 'open',
            data = data
        })
    end, garageId)
end

local function CloseGarageNUI()
    nuiOpen = false
    currentGarage = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-------------------------------------------------
-- Interaction loop (no flicker)
-------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)

        for garageId, cfg in pairs(Config.JobGarages) do
            local dist = #(pos - cfg.coords)
            if dist < 2.0 then
                sleep = 0

                DrawText3D(
                    cfg.coords.x,
                    cfg.coords.y,
                    cfg.coords.z + 0.2,
                    "[E] " .. cfg.label
                )

                if IsControlJustPressed(0, 38) then -- E
                    OpenGarageNUI(garageId)
                end
            end
        end

        Wait(sleep)
    end
end)

-------------------------------------------------
-- NUI Callbacks
-------------------------------------------------

-- Close button / ESC
RegisterNUICallback('close', function(_, cb)
    CloseGarageNUI()
    cb('ok')
end)

-- Take vehicle from fleet
RegisterNUICallback('takeVehicle', function(data, cb)
    if not data or not data.id or not data.garageId then cb('ok') return end

    QBCore.Functions.TriggerCallback('jobgarages:takeVehicle', function(success, msg)
        if not success and msg then
            QBCore.Functions.Notify(msg, 'error')
        end
    end, data.garageId, data.id)

    cb('ok')
end)

-- Manager: add vehicle to fleet
RegisterNUICallback('addVehicle', function(data, cb)
    if not data or not data.garageId or not data.plate then cb('ok') return end
    TriggerServerEvent('jobgarages:addFleetVehicle', data.garageId, data)
    cb('ok')
end)

-- Manager: remove vehicle from fleet
RegisterNUICallback('removeVehicle', function(data, cb)
    if not data or not data.garageId or not data.id then cb('ok') return end
    TriggerServerEvent('jobgarages:removeFleetVehicle', data.garageId, data.id)
    cb('ok')
end)

-- Manager: get owned vehicles for "Load My Vehicles"
RegisterNUICallback('getOwnedVehicles', function(_, cb)
    QBCore.Functions.TriggerCallback('jobgarages:getOwnedVehicles', function(list)
        cb(list or {})
    end)
end)

-------------------------------------------------
-- Refresh from server (after add/remove)
-------------------------------------------------
RegisterNetEvent('jobgarages:refresh', function(garageId)
    if not nuiOpen or currentGarage ~= garageId then return end

    QBCore.Functions.TriggerCallback('jobgarages:getGarageData', function(data)
        SendNUIMessage({
            action = 'update',
            data = data
        })
    end, garageId)
end)

-------------------------------------------------
-- Spawn vehicle (from server)
-------------------------------------------------
RegisterNetEvent('jobgarages:spawnVehicle', function(row)
    if not row or not row.model then return end

    local model = row.model
    local plate = row.plate or 'JOBCAR'
    local hash = type(model) == 'number' and model or GetHashKey(model)

    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(10)
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    local veh = CreateVehicle(hash, pCoords.x, pCoords.y, pCoords.z, GetEntityHeading(ped), true, false)
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleOnGroundProperly(veh)
    SetPedIntoVehicle(ped, veh, -1)
    SetVehicleEngineOn(veh, true, true)

    SetModelAsNoLongerNeeded(hash)
end)
