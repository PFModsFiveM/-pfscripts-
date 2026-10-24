local QBCore = exports['pfm-core']:GetCoreObject()

local nuiOpen = false
local currentGarage = nil
local currentOutPlate = nil

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

local spawnedGarageProps = {}

local function CleanupGarageProps()
    for _, obj in ipairs(spawnedGarageProps) do
        if DoesEntityExist(obj) then
            DeleteObject(obj)
        end
    end
    spawnedGarageProps = {}
end

local function SpawnJobGarageTargets()
    CleanupGarageProps()

    if not Config or not Config.JobGarages then return end

    for garageId, garage in pairs(Config.JobGarages) do
        if garage.targetProp and garage.targetCoords then
            local model = type(garage.targetProp) == 'number' and garage.targetProp or GetHashKey(garage.targetProp)

            RequestModel(model)
            while not HasModelLoaded(model) do
                Wait(10)
            end

            local coords = garage.targetCoords
            local obj = CreateObject(model, coords.x, coords.y, coords.z - 1.0, false, false, false)
            SetEntityHeading(obj, coords.w or 0.0)
            SetEntityInvincible(obj, true)
            FreezeEntityPosition(obj, true)
            SetModelAsNoLongerNeeded(model)

            spawnedGarageProps[#spawnedGarageProps+1] = obj

            exports['pfm-target']:AddTargetEntity(obj, {
                options = {
                    {
                        icon = 'fas fa-warehouse',
                        label = garage.label or 'Job Garage',
                        garageId = garageId,
                        canInteract = function(entity, distance, data)
                            local ok, result = pcall(function()
                                local pdata = QBCore.Functions.GetPlayerData()
                                if not pdata or not pdata.job then return false end

                                if garage.job and pdata.job.name ~= garage.job then
                                    return false
                                end

                                local gradeField = pdata.job.grade
                                local grade = 0
                                if type(gradeField) == 'table' then
                                    grade = tonumber(gradeField.level) or 0
                                else
                                    grade = tonumber(gradeField) or 0
                                end

                                if garage.minGrade and grade < garage.minGrade then
                                    return false
                                end
                                return true
                            end)
                            if not ok then
                                print('[pf-jobgarages] canInteract error: ' .. tostring(result))
                                return false
                            end
                            return result and true or false
                        end,
                        action = function(entity)
                            TriggerEvent('pf-jobgarages:client:OpenGarage', { garageId = garageId })
                        end,
                    },
                    {
                        icon = 'fas fa-parking',
                        label = 'Store Job Vehicle',
                        garageId = garageId,
                        canInteract = function(entity, distance, data)
                            local ok, result = pcall(function()
                                local pdata = QBCore.Functions.GetPlayerData()
                                if not pdata or not pdata.job then return false end

                                if garage.job and pdata.job.name ~= garage.job then
                                    return false
                                end
                                local gradeField = pdata.job.grade
                                local grade = 0
                                if type(gradeField) == 'table' then
                                    grade = tonumber(gradeField.level) or 0
                                else
                                    grade = tonumber(gradeField) or 0
                                end
                                if garage.minGrade and grade < garage.minGrade then
                                    return false
                                end

                                if not currentOutPlate then
                                    return false
                                end
                                return true
                            end)
                            if not ok then
                                print('[pf-jobgarages] canInteract (store) error: ' .. tostring(result))
                                return false
                            end
                            return result and true or false
                        end,
                        action = function(entity)
                            TriggerEvent('pf-jobgarages:client:StoreVehicle', { garageId = garageId })
                        end,
                    }
                },
                distance = 2.5
            })
        end
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CleanupGarageProps()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(500)
        SpawnJobGarageTargets()
    end)
end)

CreateThread(function()
    local tries = 0
    while (Config == nil or Config.JobGarages == nil) and tries < 200 do
        Wait(50)
        tries = tries + 1
    end
    SpawnJobGarageTargets()
end)

RegisterNetEvent('pf-jobgarages:client:StoreVehicle', function(data)
    if not data or not data.garageId then return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh == 0 then
        local vehicles = GetGamePool('CVehicle')
        local pCoords = GetEntityCoords(ped)
        local closestVeh, closestDist = nil, 10  -- 10 units radius

        for _, v in ipairs(vehicles) do
            if DoesEntityExist(v) then
                local vCoords = GetEntityCoords(v)
                local dist = #(pCoords - vCoords)
                if dist < closestDist then
                    closestDist = dist
                    closestVeh = v
                end
            end
        end

        veh = closestVeh or 0
    end

    if veh == 0 then
        QBCore.Functions.Notify("No vehicle nearby to store.", "error")
        return
    end

    local plate = GetVehicleNumberPlateText(veh)
    if not plate or plate == '' then
        QBCore.Functions.Notify("Invalid plate.", "error")
        return
    end

    local normPlate = string.upper((plate:gsub('%s+', '')))
    if currentOutPlate and normPlate ~= currentOutPlate then
        QBCore.Functions.Notify("This is not your assigned job vehicle.", "error")
        return
    end

    TriggerServerEvent('jobgarages:storeVehicle', plate, data.garageId)
end)

RegisterNetEvent('pf-jobgarages:client:OpenGarage', function(data)
    if not data or not data.garageId then return end
    OpenGarageNUI(data.garageId)
end)

function OpenGarageNUI(garageId)
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

RegisterNUICallback('savePermissions', function(data, cb)
    if not currentGarage then
        cb('no_garage')
        return
    end

    TriggerServerEvent('jobgarages:savePermissions', currentGarage, {
        min_grade_use    = data.min_grade_use,
        min_grade_manage = data.min_grade_manage
    })

    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    CloseGarageNUI()
    cb('ok')
end)

RegisterNUICallback('takeVehicle', function(data, cb)
    if not data or not data.id or not data.garageId then cb('ok') return end

    QBCore.Functions.TriggerCallback('jobgarages:takeVehicle', function(success, msg)
        if not success and msg then
            QBCore.Functions.Notify(msg, 'error')
        elseif success then
            CloseGarageNUI()
        end
    end, data.garageId, data.id)

    cb('ok')
end)

RegisterNUICallback('forceReturn', function(data, cb)
    if not currentGarage then
        cb('no_garage')
        return
    end

    local id = tonumber(data.id)
    if not id then
        cb('invalid_id')
        return
    end

    TriggerServerEvent('jobgarages:forceReturn', currentGarage, id)
    cb('ok')
end)

RegisterNetEvent('jobgarages:forceDespawn', function(plate)
    if not plate or plate == '' then return end

    local targetPlate = string.upper((plate:gsub('%s+', '')))
    if targetPlate == '' then return end

    local vehicles = GetGamePool('CVehicle')

    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            local vplate = GetVehicleNumberPlateText(veh) or ''
            vplate = string.upper((vplate:gsub('%s+', '')))

            if vplate == targetPlate then
                if not NetworkHasControlOfEntity(veh) then
                    NetworkRequestControlOfEntity(veh)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                        Wait(0)
                        timeout = timeout + 1
                    end
                end

                SetEntityAsMissionEntity(veh, true, true)
                DeleteVehicle(veh)
            end
        end
    end

    if currentOutPlate and currentOutPlate == targetPlate then
        currentOutPlate = nil
    end
end)

RegisterNUICallback('addVehicle', function(data, cb)
    if not data or not data.garageId or not data.plate then cb('ok') return end
    TriggerServerEvent('jobgarages:addFleetVehicle', data.garageId, data)
    cb('ok')
end)

RegisterNUICallback('removeVehicle', function(data, cb)
    if not data or not data.garageId or not data.id then cb('ok') return end
    TriggerServerEvent('jobgarages:removeFleetVehicle', data.garageId, data.id)
    cb('ok')
end)

RegisterNUICallback('getOwnedVehicles', function(_, cb)
    print('[pf-jobgarages] NUI getOwnedVehicles called')
    QBCore.Functions.TriggerCallback('jobgarages:getOwnedVehicles', function(list)
        print(('[pf-jobgarages] NUI returning %d owned vehicles to UI'):format(#(list or {})))
        cb(list or {})
    end)
end)

RegisterNUICallback('saveAssignment', function(data, cb)
    if not currentGarage then
        cb('no_garage')
        return
    end

    TriggerServerEvent('jobgarages:setAssignment', currentGarage, {
        id     = data.id,
        type   = data.type,
        target = data.target
    })

    cb('ok')
end)

RegisterNetEvent('jobgarages:refresh', function(garageId)
    if not nuiOpen or currentGarage ~= garageId then return end

    QBCore.Functions.TriggerCallback('jobgarages:getGarageData', function(data)
        SendNUIMessage({
            action = 'update',
            data = data
        })
    end, garageId)
end)

RegisterNetEvent('jobgarages:storedVehicle', function(plate)
    local expectedPlate = nil
    if plate and plate ~= '' then
        expectedPlate = string.upper((plate:gsub('%s+', '')))
    elseif currentOutPlate then
        expectedPlate = currentOutPlate
    end

    if not expectedPlate then
        QBCore.Functions.Notify("Vehicle returned to garage.", "success")
        currentOutPlate = nil
        return
    end

    local ped = PlayerPedId()
    local vehicles = GetGamePool('CVehicle')
    local removedAny = false

    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            local vplate = GetVehicleNumberPlateText(veh) or ''
            vplate = string.upper((vplate:gsub('%s+', '')))

            if vplate == expectedPlate then
                if not NetworkHasControlOfEntity(veh) then
                    NetworkRequestControlOfEntity(veh)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                        Wait(0)
                        timeout = timeout + 1
                    end
                end

                if GetPedInVehicleSeat(veh, -1) == ped then
                    TaskLeaveVehicle(ped, veh, 16)
                    Wait(1000)
                end

                SetEntityAsMissionEntity(veh, true, true)
                DeleteVehicle(veh)
                removedAny = true
            end
        end
    end

    if removedAny then
        QBCore.Functions.Notify("Vehicle returned to garage.", "success")
    else
        QBCore.Functions.Notify("Garage updated, but no nearby vehicle found to remove.", "primary")
    end

    currentOutPlate = nil
end)

RegisterNetEvent('jobgarages:spawnVehicle', function(row)
    if not row or not row.model then
        QBCore.Functions.Notify("Garage config missing vehicle model.", "error")
        return
    end

    local model = row.model
    local plate = row.plate or 'JOBCAR'
    local hash = type(model) == 'number' and model or GetHashKey(model)

    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        QBCore.Functions.Notify("Invalid vehicle model: " .. tostring(model), "error")
        print("[pf-jobgarages] Invalid vehicle model '" .. tostring(model) .. "' for plate " .. plate)
        return
    end

    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(10)
    end

    local ped = PlayerPedId()

    local spawn = nil
    if Config.JobGarages and currentGarage and Config.JobGarages[currentGarage] then
        spawn = Config.JobGarages[currentGarage].spawnCoords
    end

    local x, y, z, heading
    if spawn then
        x, y, z, heading = spawn.x, spawn.y, spawn.z, spawn.w or 0.0
    else
        local pCoords = GetEntityCoords(ped)
        x, y, z = pCoords.x, pCoords.y, pCoords.z
        heading = GetEntityHeading(ped)
    end

    local veh = CreateVehicle(hash, x, y, z, heading, true, false)
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleOnGroundProperly(veh)
    SetPedIntoVehicle(ped, veh, -1)
    SetVehicleEngineOn(veh, true, true)

    currentOutPlate = string.upper((plate:gsub('%s+', '')))

    if row.mods and row.mods ~= '' then
        local ok, props = pcall(json.decode, row.mods)
        if ok and props then
            if QBCore.Functions and QBCore.Functions.SetVehicleProperties then
                QBCore.Functions.SetVehicleProperties(veh, props)
            else
                print("[pf-jobgarages] Warning: QBCore.Functions.SetVehicleProperties not found.")
            end
        end
    end

    if row.engine then
        SetVehicleEngineHealth(veh, row.engine + 0.0)
    end
    if row.body then
        SetVehicleBodyHealth(veh, row.body + 0.0)
    end

    TriggerEvent('vehiclekeys:client:SetOwner', plate)

    SetModelAsNoLongerNeeded(hash)
end)
