local PlayerJob = {}
local onDuty = false
local currentGarage = 0
local currentHospital

-- Functions

local function GetClosestPlayer()
    local closestPlayers = QBCore.Functions.GetPlayersFromCoords()
    local closestDistance = -1
    local closestPlayer = -1
    local coords = GetEntityCoords(PlayerPedId())

    for i = 1, #closestPlayers, 1 do
        if closestPlayers[i] ~= PlayerId() then
            local pos = GetEntityCoords(GetPlayerPed(closestPlayers[i]))
            local distance = #(pos - coords)

            if closestDistance == -1 or closestDistance > distance then
                closestPlayer = closestPlayers[i]
                closestDistance = distance
            end
        end
    end
    return closestPlayer, closestDistance
end

function TakeOutVehicle(vehicleInfo)
    local coords = Config.Locations['vehicle'][currentGarage]
    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        SetVehicleNumberPlateText(veh, Lang:t('info.amb_plate') .. tostring(math.random(1000, 9999)))
        SetEntityHeading(veh, coords.w)
        exports['LegacyFuel']:SetFuel(veh, 100.0)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        if Config.VehicleSettings[vehicleInfo] ~= nil then
            QBCore.Shared.SetDefaultVehicleExtras(veh, Config.VehicleSettings[vehicleInfo].extras)
        end
        TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
        SetVehicleEngineOn(veh, true, true)
    end, vehicleInfo, coords, true)
end

local function getAuthorizedVehicles(grade)
    local accessibleVehicles = {}
    for availableGrade, vehicles in pairs(Config.AuthorizedVehicles) do
        if grade >= availableGrade then
            for vehicleName, vehicleLabel in pairs(vehicles) do
                accessibleVehicles[vehicleName] = vehicleLabel
            end
        end
    end
    return accessibleVehicles
end

function MenuGarage()
    local vehicleMenu = {
        {
            header = Lang:t('menu.amb_vehicles'),
            isMenuHeader = true
        }
    }

    local authorizedVehicles = getAuthorizedVehicles(QBCore.Functions.GetPlayerData().job.grade.level)
    for veh, label in pairs(authorizedVehicles) do
        vehicleMenu[#vehicleMenu + 1] = {
            header = label,
            txt = '',
            params = {
                event = 'ambulance:client:TakeOutVehicle',
                args = {
                    vehicle = veh
                }
            }
        }
    end
    vehicleMenu[#vehicleMenu + 1] = {
        header = Lang:t('menu.close'),
        txt = '',
        params = {
            event = 'qb-menu:client:closeMenu'
        }

    }
    exports['pfm-menu']:openMenu(vehicleMenu)
end

-- Events

RegisterNetEvent('ambulance:client:TakeOutVehicle', function(data)
    local vehicle = data.vehicle
    TakeOutVehicle(vehicle)
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerJob = JobInfo
    if PlayerJob.name == 'ambulance' then onDuty = PlayerJob.onduty end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    exports.spawnmanager:setAutoSpawn(false)
    local ped = PlayerPedId()
    local player = PlayerId()
    CreateThread(function()
        Wait(5000)
        SetEntityMaxHealth(ped, 200)
        -- a player the server has down keeps the down state's health
        if not ServerDownState and not isDead and not InLaststand then SetEntityHealth(ped, 200) end
        SetPlayerHealthRechargeMultiplier(player, 0.0)
        SetPlayerHealthRechargeLimit(player, 0.0)
    end)
    CreateThread(function()
        Wait(1000)
        QBCore.Functions.GetPlayerData(function(PlayerData)
            PlayerJob = PlayerData.job
            onDuty = PlayerData.job.onduty
            SetPedArmour(PlayerPedId(), PlayerData.metadata['armor'])
        end)
        -- the server owns the down state: ask for it (its first push may have come before this script was ready)
        QBCore.Functions.TriggerCallback('pf-ambulancejob:server:getDownState', function(state, info)
            if state then TriggerEvent('pf-ambulancejob:client:SetDown', state, info) end
        end)
    end)
end)

-- the doctor count is kept on the server from duty changes
RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    onDuty = duty
end)

function Status()
    if isStatusChecking then
        local statusMenu = {
            {
                header = Lang:t('menu.status'),
                isMenuHeader = true
            }
        }
        for _, v in pairs(statusChecks) do
            statusMenu[#statusMenu + 1] = {
                header = v.label,
                txt = '',
                params = {
                    event = 'hospital:client:TreatWounds',
                }
            }
        end
        statusMenu[#statusMenu + 1] = {
            header = Lang:t('menu.close'),
            txt = '',
            params = {
                event = 'qb-menu:client:closeMenu'
            }
        }
        exports['pfm-menu']:openMenu(statusMenu)
    end
end

RegisterNetEvent('hospital:client:CheckStatus', function()
    local player, distance = GetClosestPlayer()
    if player ~= -1 and distance < 5.0 then
        local playerId = GetPlayerServerId(player)
        QBCore.Functions.TriggerCallback('hospital:GetPlayerStatus', function(result)
            if result then
                statusChecks = {}
                for k, v in pairs(result) do
                    if k ~= 'BLEED' and k ~= 'WEAPONWOUNDS' and type(v) == 'table' then
                        statusChecks[#statusChecks + 1] = {
                            bone = Config.BoneIndexes[k],
                            label = tostring(v.label) .. ' (' .. tostring(Config.WoundStates[v.severity] or '') .. ')'
                        }
                    end
                end
                local bleed = tonumber(result['BLEED'])
                if bleed and bleed > 0 and Config.BleedingStates[math.min(4, bleed)] then
                    TriggerEvent('chat:addMessage', {
                        color = { 255, 0, 0 },
                        multiline = false,
                        args = { Lang:t('info.status'), Lang:t('info.is_status', { status = Config.BleedingStates[math.min(4, bleed)].label }) }
                    })
                end
                if #statusChecks == 0 and not (bleed and bleed > 0) then
                    QBCore.Functions.Notify(Lang:t('success.healthy_player'), 'success')
                end
                isStatusChecking = true
                Status()
            end
        end, playerId)
    else
        QBCore.Functions.Notify(Lang:t('error.no_player'), 'error')
    end
end)

RegisterNetEvent('hospital:client:RevivePlayer', function()
    local hasItem = QBCore.Functions.HasItem('firstaid')
    if hasItem then
        local player, distance = GetClosestPlayer()
        if player ~= -1 and distance < 2.5 then
            local playerId = GetPlayerServerId(player)
            QBCore.Functions.Progressbar('hospital_revive', Lang:t('progress.revive'), 5000, false, true, {
                disableMovement = false,
                disableCarMovement = false,
                disableMouse = false,
                disableCombat = true,
            }, {
                animDict = healAnimDict,
                anim = healAnim,
                flags = 33,
            }, {}, {}, function() -- Done
                StopAnimTask(PlayerPedId(), healAnimDict, 'exit', 1.0)
                QBCore.Functions.Notify(Lang:t('success.revived'), 'success')
                TriggerServerEvent('hospital:server:RevivePlayer', playerId)
            end, function() -- Cancel
                StopAnimTask(PlayerPedId(), healAnimDict, 'exit', 1.0)
                QBCore.Functions.Notify(Lang:t('error.canceled'), 'error')
            end)
        else
            QBCore.Functions.Notify(Lang:t('error.no_player'), 'error')
        end
    else
        QBCore.Functions.Notify(Lang:t('error.no_firstaid'), 'error')
    end
end)

RegisterNetEvent('hospital:client:TreatWounds', function()
    local hasItem = QBCore.Functions.HasItem('bandage')
    if hasItem then
        local player, distance = GetClosestPlayer()
        if player ~= -1 and distance < 5.0 then
            local playerId = GetPlayerServerId(player)
            QBCore.Functions.Progressbar('hospital_healwounds', Lang:t('progress.healing'), 5000, false, true, {
                disableMovement = false,
                disableCarMovement = false,
                disableMouse = false,
                disableCombat = true,
            }, {
                animDict = healAnimDict,
                anim = healAnim,
                flags = 33,
            }, {}, {}, function() -- Done
                StopAnimTask(PlayerPedId(), healAnimDict, 'exit', 1.0)
                QBCore.Functions.Notify(Lang:t('success.helped_player'), 'success')
                TriggerServerEvent('hospital:server:TreatWounds', playerId)
            end, function() -- Cancel
                StopAnimTask(PlayerPedId(), healAnimDict, 'exit', 1.0)
                QBCore.Functions.Notify(Lang:t('error.canceled'), 'error')
            end)
        else
            QBCore.Functions.Notify(Lang:t('error.no_player'), 'error')
        end
    else
        QBCore.Functions.Notify(Lang:t('error.no_bandage'), 'error')
    end
end)

local check = false
local function EMSControls(variable)
    CreateThread(function()
        check = true
        while check do
            if IsControlJustPressed(0, 38) then
                exports['pfm-core']:KeyPressed(38)
                if variable == 'sign' then
                    TriggerEvent('EMSToggle:Duty')
                elseif variable == 'stash' then
                    TriggerServerEvent('qb-ambulancejob:server:stash')
                elseif variable == 'storeheli' then
                    TriggerEvent('qb-ambulancejob:storeheli')
                elseif variable == 'takeheli' then
                    TriggerEvent('qb-ambulancejob:pullheli')
                elseif variable == 'roof' then
                    TriggerEvent('qb-ambulancejob:elevator_main')
                elseif variable == 'main' then
                    TriggerEvent('qb-ambulancejob:elevator_roof')
                end
            end
            Wait(1)
        end
    end)
end

local CheckVehicle = false
local function EMSVehicle(k)
    CheckVehicle = true
    CreateThread(function()
        while CheckVehicle do
            if IsControlJustPressed(0, 38) then
                exports['pfm-core']:KeyPressed(38)
                CheckVehicle = false
                local ped = PlayerPedId()
                if IsPedInAnyVehicle(ped, false) then
                    QBCore.Functions.DeleteVehicle(GetVehiclePedIsIn(ped))
                else
                    local currentVehicle = k
                    MenuGarage(currentVehicle)
                    currentGarage = currentVehicle
                end
            end
            Wait(1)
        end
    end)
end

local CheckHeli = false
local function EMSHelicopter(k)
    CheckHeli = true
    CreateThread(function()
        while CheckHeli do
            if IsControlJustPressed(0, 38) then
                exports['pfm-core']:KeyPressed(38)
                CheckHeli = false
                local ped = PlayerPedId()
                if IsPedInAnyVehicle(ped, false) then
                    QBCore.Functions.DeleteVehicle(GetVehiclePedIsIn(ped))
                else
                    local currentHelictoper = k
                    local coords = Config.Locations['helicopter'][currentHelictoper]
                    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
                        local veh = NetToVeh(netId)
                        SetVehicleNumberPlateText(veh, Lang:t('info.heli_plate') .. tostring(math.random(1000, 9999)))
                        SetEntityHeading(veh, coords.w)
                        SetVehicleLivery(veh, 1) -- Ambulance Livery
                        exports['LegacyFuel']:SetFuel(veh, 100.0)
                        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
                        TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
                        SetVehicleEngineOn(veh, true, true, false)
                    end, Config.Helicopter, coords, true)
                end
            end
            Wait(1)
        end
    end)
end

RegisterNetEvent('qb-ambulancejob:elevator_roof', function()
    local ped = PlayerPedId()
    for i = 1, #Config.Locations['roof'] do
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(10) end
        currentHospital = i
        local coords = Config.Locations['main'][currentHospital]
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
        SetEntityHeading(ped, coords.w)
        Wait(100)
        DoScreenFadeIn(1000)
    end
end)

RegisterNetEvent('qb-ambulancejob:elevator_main', function()
    local ped = PlayerPedId()
    for i = 1, #Config.Locations['main'] do
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(10) end
        currentHospital = i
        local coords = Config.Locations['roof'][currentHospital]
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
        SetEntityHeading(ped, coords.w)
        Wait(100)
        DoScreenFadeIn(1000)
    end
end)

RegisterNetEvent('EMSToggle:Duty', function()
    onDuty = not onDuty
    TriggerServerEvent('QBCore:ToggleDuty')
    TriggerServerEvent('police:server:UpdateBlips')
end)

CreateThread(function()
    for i = 1, #Config.Locations['vehicle'] do
        local v = Config.Locations['vehicle'][i]
        local boxZone = BoxZone:Create(vector3(v.x, v.y, v.z), 5, 5, {
            name = 'vehicle' .. i,
            debugPoly = false,
            heading = 70,
            minZ = v.z - 2,
            maxZ = v.z + 2,
        })
        boxZone:onPlayerInOut(function(isPointInside)
            if isPointInside and PlayerJob.name == 'ambulance' and onDuty then
                exports['pfm-core']:DrawText(Lang:t('text.veh_button'), 'left')
                EMSVehicle(i)
            else
                CheckVehicle = false
                exports['pfm-core']:HideText()
            end
        end)
    end

    for i = 1, #Config.Locations['helicopter'] do
        local v = Config.Locations['helicopter'][i]
        local boxZone = BoxZone:Create(vector3(v.x, v.y, v.z), 5, 5, {
            name = 'helicopter' .. i,
            debugPoly = false,
            heading = 70,
            minZ = v.z - 2,
            maxZ = v.z + 2,
        })
        boxZone:onPlayerInOut(function(isPointInside)
            if isPointInside and PlayerJob.name == 'ambulance' and onDuty then
                exports['pfm-core']:DrawText(Lang:t('text.heli_button'), 'left')
                EMSHelicopter(i)
            else
                CheckHeli = false
                exports['pfm-core']:HideText()
            end
        end)
    end
end)

-- Convar turns into a boolean
if Config.UseTarget then
    CreateThread(function()
        for i = 1, #Config.Locations['duty'] do
            local v = Config.Locations['duty'][i]
            exports['pfm-target']:AddBoxZone('duty' .. i, vector3(v.x, v.y, v.z), 1.5, 1, {
                name = 'duty' .. i,
                debugPoly = false,
                heading = -20,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            }, {
                options = {
                    {
                        type = 'client',
                        event = 'EMSToggle:Duty',
                        icon = 'fa fa-clipboard',
                        label = 'Sign In/Off duty',
                        job = 'ambulance'
                    }
                },
                distance = 1.5
            })
        end
        for i = 1, #Config.Locations['stash'] do
            local v = Config.Locations['stash'][i]
            exports['pfm-target']:AddBoxZone('stash' .. i, vector3(v.x, v.y, v.z), 1, 1, {
                name = 'stash' .. i,
                debugPoly = false,
                heading = -20,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            }, {
                options = {
                    {
                        type = 'server',
                        event = 'qb-ambulancejob:server:stash',
                        icon = 'fa fa-hand',
                        label = 'Open Stash',
                        job = 'ambulance'
                    }
                },
                distance = 1.5
            })
        end
        for i = 1, #Config.Locations['roof'] do
            local v = Config.Locations['roof'][i]
            exports['pfm-target']:AddBoxZone('roof' .. i, vector3(v.x, v.y, v.z), 2, 2, {
                name = 'roof' .. i,
                debugPoly = false,
                heading = -20,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            }, {
                options = {
                    {
                        type = 'client',
                        event = 'qb-ambulancejob:elevator_roof',
                        icon = 'fas fa-hand-point-up',
                        label = 'Take Elevator',
                        job = 'ambulance'
                    },
                },
                distance = 8
            })
        end
        for i = 1, #Config.Locations['main'] do
            local v = Config.Locations['main'][i]
            exports['pfm-target']:AddBoxZone('main' .. i, vector3(v.x, v.y, v.z), 1.5, 1.5, {
                name = 'main' .. i,
                debugPoly = false,
                heading = -20,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            }, {
                options = {
                    {
                        type = 'client',
                        event = 'qb-ambulancejob:elevator_main',
                        icon = 'fas fa-hand-point-up',
                        label = 'Take Elevator',
                        job = 'ambulance'
                    },
                },
                distance = 8
            })
        end
    end)
else
    CreateThread(function()
        local signPoly = {}
        for i = 1, #Config.Locations['duty'] do
            local v = Config.Locations['duty'][i]
            signPoly[#signPoly + 1] = BoxZone:Create(vector3(v.x, v.y, v.z), 1.5, 1, {
                name = 'sign' .. i,
                debugPoly = false,
                heading = -20,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            })
        end

        local signCombo = ComboZone:Create(signPoly, { name = 'signcombo', debugPoly = false })
        signCombo:onPlayerInOut(function(isPointInside)
            if isPointInside and PlayerJob.name == 'ambulance' then
                if not onDuty then
                    exports['pfm-core']:DrawText(Lang:t('text.onduty_button'), 'left')
                    EMSControls('sign')
                else
                    exports['pfm-core']:DrawText(Lang:t('text.offduty_button'), 'left')
                    EMSControls('sign')
                end
            else
                check = false
                exports['pfm-core']:HideText()
            end
        end)

        local stashPoly = {}
        for i = 1, #Config.Locations['stash'] do
            local v = Config.Locations['stash'][i]
            stashPoly[#stashPoly + 1] = BoxZone:Create(vector3(v.x, v.y, v.z), 1, 1, {
                name = 'stash' .. i,
                debugPoly = false,
                heading = -20,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            })
        end

        local stashCombo = ComboZone:Create(stashPoly, { name = 'stashCombo', debugPoly = false })
        stashCombo:onPlayerInOut(function(isPointInside)
            if isPointInside and PlayerJob.name == 'ambulance' then
                if onDuty then
                    exports['pfm-core']:DrawText(Lang:t('text.pstash_button'), 'left')
                    EMSControls('stash')
                end
            else
                check = false
                exports['pfm-core']:HideText()
            end
        end)

        local roofPoly = {}
        for i = 1, #Config.Locations['roof'] do
            local v = Config.Locations['roof'][i]
            roofPoly[#roofPoly + 1] = BoxZone:Create(vector3(v.x, v.y, v.z), 2, 2, {
                name = 'roof' .. i,
                debugPoly = false,
                heading = 70,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            })
        end

        local roofCombo = ComboZone:Create(roofPoly, { name = 'roofCombo', debugPoly = false })
        roofCombo:onPlayerInOut(function(isPointInside)
            if isPointInside and PlayerJob.name == 'ambulance' then
                if onDuty then
                    exports['pfm-core']:DrawText(Lang:t('text.elevator_main'), 'left')
                    EMSControls('main')
                else
                    exports['pfm-core']:DrawText(Lang:t('error.not_ems'), 'left')
                end
            else
                check = false
                exports['pfm-core']:HideText()
            end
        end)

        local mainPoly = {}
        for i = 1, #Config.Locations['main'] do
            local v = Config.Locations['main'][i]
            mainPoly[#mainPoly + 1] = BoxZone:Create(vector3(v.x, v.y, v.z), 1.5, 1.5, {
                name = 'main' .. i,
                debugPoly = false,
                heading = 70,
                minZ = v.z - 2,
                maxZ = v.z + 2,
            })
        end

        local mainCombo = ComboZone:Create(mainPoly, { name = 'mainPoly', debugPoly = false })
        mainCombo:onPlayerInOut(function(isPointInside)
            if isPointInside and PlayerJob.name == 'ambulance' then
                if onDuty then
                    exports['pfm-core']:DrawText(Lang:t('text.elevator_roof'), 'left')
                    EMSControls('roof')
                else
                    exports['pfm-core']:DrawText(Lang:t('error.not_ems'), 'left')
                end
            else
                check = false
                exports['pfm-core']:HideText()
            end
        end)
    end)
end
