Laststand = Laststand or {}
InLaststand = false
LaststandTime = 0
lastStandDict = 'combat@damage@writhe'
lastStandAnim = 'writhe_loop'
isEscorted = false
local isEscorting = false

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

local function LoadAnimation(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)
        Wait(100)
    end
end

LaststandHelpIn = 0
ServerDownState = false -- the state the server last sent (false, 'unconscious', 'arrest', 'dead')

--- Plays the last-stand pose for the server's 'unconscious' / 'arrest' state (info from SetDown).
--- The countdown is only shown here: the server ends the last stand.
function SetLaststand(bool, info)
    local ped = PlayerPedId()
    if bool then
        info = info or {}
        LaststandTime = tonumber(info.laststandIn or info.arrestIn) or 0
        LaststandHelpIn = tonumber(info.helpIn) or 0
        if InLaststand then return end
        isDead = false
        local tries = 0
        while (GetEntitySpeed(ped) > 0.5 or IsPedRagdoll(ped)) and tries < 300 do tries = tries + 1 Wait(10) end
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'demo', 0.1)
        if IsEntityDead(ped) then ResurrectInPlace(ped) end
        ped = PlayerPedId()
        SetEntityInvincible(ped, false)
        SetEntityHealth(ped, tonumber(info.holdHealth) or 150)
        if IsPedInAnyVehicle(ped, false) then
            LoadAnimation('veh@low@front_ps@idle_duck')
            TaskPlayAnim(ped, 'veh@low@front_ps@idle_duck', 'sit', 1.0, 8.0, -1, 1, -1, false, false, false)
        else
            LoadAnimation(lastStandDict)
            TaskPlayAnim(ped, lastStandDict, lastStandAnim, 1.0, 8.0, -1, 1, -1, false, false, false)
        end
        InLaststand = true
        CreateThread(function()
            while InLaststand do
                if LaststandTime > 0 then LaststandTime = LaststandTime - 1 end
                if LaststandHelpIn > 0 then LaststandHelpIn = LaststandHelpIn - 1 end
                Wait(1000)
            end
        end)
    else
        if InLaststand then TaskPlayAnim(ped, lastStandDict, 'exit', 1.0, 8.0, -1, 1, -1, false, false, false) end
        InLaststand = false
        LaststandTime = 0
    end
end

-- Events

RegisterNetEvent('hospital:client:SetEscortingState', function(bool)
    isEscorting = bool
end)

RegisterNetEvent('hospital:client:isEscorted', function(bool)
    isEscorted = bool
end)

RegisterNetEvent('hospital:client:UseFirstAid', function()
    if not isEscorting then
        local player, distance = GetClosestPlayer()
        if player ~= -1 and distance < 1.5 then
            local playerId = GetPlayerServerId(player)
            TriggerServerEvent('hospital:server:UseFirstAid', playerId)
        end
    else
        QBCore.Functions.Notify(Lang:t('error.impossible'), 'error')
    end
end)

-- The server started first aid on an unconscious person (it checked the kit, distance and state);
-- duration in ms is the server's. Finishing asks the server to revive them.
RegisterNetEvent('hospital:client:HelpPerson', function(targetId, duration)
    local ped = PlayerPedId()
    QBCore.Functions.Progressbar('hospital_revive', Lang:t('progress.revive'), tonumber(duration) or 45000, false, true, {
        disableMovement = false,
        disableCarMovement = false,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = healAnimDict,
        anim = healAnim,
        flags = 1,
    }, {}, {}, function() -- Done
        ClearPedTasks(ped)
        TriggerServerEvent('hospital:server:RevivePlayer', targetId)
    end, function() -- Cancel
        ClearPedTasks(ped)
        QBCore.Functions.Notify(Lang:t('error.canceled'), 'error')
    end)
end)
