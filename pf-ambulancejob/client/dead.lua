local deadAnimDict = 'dead'
local deadAnim = 'dead_a'
local hold = 5
deathTime = 0

-- Functions

local function loadAnimDict(dict)
    while (not HasAnimDictLoaded(dict)) do
        RequestAnimDict(dict)
        Wait(5)
    end
end

-- The server owns the down state (batch 16A): this client reports its ped's death and plays the
-- state the server sends (pf-ambulancejob:client:SetDown). It never clears its own down state.

local function resurrectInPlace(ped)
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    if IsPedInAnyVehicle(ped) then
        local veh = GetVehiclePedIsIn(ped)
        local vehseats = GetVehicleModelNumberOfSeats(GetHashKey(GetEntityModel(veh)))
        for i = -1, vehseats do
            if GetPedInVehicleSeat(veh, i) == ped then
                NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z + 0.5, heading, true, false)
                SetPedIntoVehicle(PlayerPedId(), veh, i)
                return
            end
        end
    end
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z + 0.5, heading, true, false)
end
ResurrectInPlace = resurrectInPlace

--- The dead pose (called for the server's 'dead' state). info.respawnIn = seconds until respawn.
function OnDeath(info)
    info = info or {}
    deathTime = tonumber(info.respawnIn) or 0
    if isDead then return end
    isDead = true
    InLaststand = false
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'demo', 0.1)
    local player = PlayerPedId()
    local tries = 0
    while (GetEntitySpeed(player) > 0.5 or IsPedRagdoll(player)) and tries < 500 do tries = tries + 1 Wait(10) end
    if not isDead then return end
    if IsEntityDead(player) then resurrectInPlace(player) end
    player = PlayerPedId()
    SetEntityInvincible(player, true)
    SetEntityHealth(player, GetEntityMaxHealth(player))
    if IsPedInAnyVehicle(player, false) then
        loadAnimDict('veh@low@front_ps@idle_duck')
        TaskPlayAnim(player, 'veh@low@front_ps@idle_duck', 'sit', 1.0, 1.0, -1, 1, 0, 0, 0, 0)
    else
        loadAnimDict(deadAnimDict)
        TaskPlayAnim(player, deadAnimDict, deadAnim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
    end
    CreateThread(DeathTimer)
end

--- Respawn countdown; holding E afterwards asks the server (it checks the time and that we are dead).
function DeathTimer()
    hold = 5
    while isDead do
        Wait(1000)
        deathTime = deathTime - 1
        if deathTime <= 0 then
            if IsControlPressed(0, 38) and hold <= 0 and not isInHospitalBed then
                TriggerServerEvent('pf-ambulancejob:server:RequestRespawn')
                hold = 5
            end
            if IsControlPressed(0, 38) then
                hold = math.max(0, hold - 1)
            end
            if IsControlReleased(0, 38) then
                hold = 5
            end
        end
    end
end

-- Report a death to the server (again every 3 s while the ped lies dead and the server has not
-- answered: the server reads the ped's health itself and may see it a moment later).
local reporting = false
local function ReportDeath(kind, weapon, attacker)
    if reporting then return end
    reporting = true
    CreateThread(function()
        for _ = 1, 10 do
            TriggerServerEvent('pf-ambulancejob:server:ReportDown', {
                nonce = tostring(GetGameTimer()), kind = kind, hint = { weapon = weapon, attacker = attacker },
            })
            Wait(3000)
            if ServerDownState and (kind ~= 'dead' or ServerDownState == 'dead') then break end
            if not IsEntityDead(PlayerPedId()) then break end
        end
        reporting = false
    end)
end

local function DrawTxt(x, y, width, height, scale, text, r, g, b, a, _)
    if GetConvar('qb_locale', 'en') == 'en' then
        SetTextFont(4)
    else
        SetTextFont(1)
    end
    SetTextProportional(0)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x - width / 2, y - height / 2 + 0.005)
end

-- Damage Handler

AddEventHandler('gameEventTriggered', function(event, data)
    if event == 'CEventNetworkEntityDamage' then
        local victim, attacker, victimDied, weapon = data[1], data[2], data[4], data[7]
        if not IsEntityAPed(victim) then return end
        if victimDied and NetworkGetPlayerIndexFromPed(victim) == PlayerId() and IsEntityDead(PlayerPedId()) then
            local killerId = NetworkGetPlayerIndexFromPed(attacker)
            local attackerServerId = killerId ~= -1 and GetPlayerServerId(killerId) or nil
            -- dying while already down is the legacy "dead in last stand"; the server decides
            ReportDeath((InLaststand or ServerDownState) and 'dead' or 'laststand', weapon, attackerServerId)
        end
    end
end)

-- Threads

emsNotified = false

CreateThread(function()
    while true do
        local sleep = 1000
        if isDead or InLaststand then
            sleep = 5
            local ped = PlayerPedId()
            if IsPauseMenuActive() then
                SetFrontendActive(false)
            end
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 38, true)
            EnableControlAction(0, 0, true)
            EnableControlAction(0, 322, true)
            EnableControlAction(0, 288, true)
            EnableControlAction(0, 213, true)
            EnableControlAction(0, 249, true)
            EnableControlAction(0, 46, true)
            EnableControlAction(0, 47, true)

            if isDead then
                if not isInHospitalBed then
                    if deathTime > 0 then
                        DrawTxt(0.93, 1.44, 1.0, 1.0, 0.6, Lang:t('info.respawn_txt', { deathtime = math.ceil(deathTime) }), 255, 255, 255, 255)
                    else
                        DrawTxt(0.865, 1.44, 1.0, 1.0, 0.6, Lang:t('info.respawn_revive', { holdtime = hold, cost = Config.BillCost }), 255, 255, 255, 255)
                    end
                end

                if IsPedInAnyVehicle(ped, false) then
                    loadAnimDict('veh@low@front_ps@idle_duck')
                    if not IsEntityPlayingAnim(ped, 'veh@low@front_ps@idle_duck', 'sit', 3) then
                        TaskPlayAnim(ped, 'veh@low@front_ps@idle_duck', 'sit', 1.0, 1.0, -1, 1, 0, 0, 0, 0)
                    end
                else
                    if isInHospitalBed then
                        if not IsEntityPlayingAnim(ped, inBedDict, inBedAnim, 3) then
                            loadAnimDict(inBedDict)
                            TaskPlayAnim(ped, inBedDict, inBedAnim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
                        end
                    else
                        if not IsEntityPlayingAnim(ped, deadAnimDict, deadAnim, 3) then
                            loadAnimDict(deadAnimDict)
                            TaskPlayAnim(ped, deadAnimDict, deadAnim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
                        end
                    end
                end

                SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            elseif InLaststand then
                sleep = 5

                if (LaststandHelpIn or 0) > 0 then
                    DrawTxt(0.94, 1.44, 1.0, 1.0, 0.6, Lang:t('info.bleed_out', { time = math.ceil(LaststandTime) }), 255, 255, 255, 255)
                else
                    DrawTxt(0.845, 1.44, 1.0, 1.0, 0.6, Lang:t('info.bleed_out_help', { time = math.ceil(LaststandTime) }), 255, 255, 255, 255)
                    if not emsNotified then
                        DrawTxt(0.91, 1.40, 1.0, 1.0, 0.6, Lang:t('info.request_help'), 255, 255, 255, 255)
                    else
                        DrawTxt(0.90, 1.40, 1.0, 1.0, 0.6, Lang:t('info.help_requested'), 255, 255, 255, 255)
                    end

                    if IsControlJustPressed(0, 47) and not emsNotified then
                        TriggerServerEvent('pf-ambulancejob:server:RequestHelp')
                        emsNotified = true
                    end
                end

                if not isEscorted then
                    if IsPedInAnyVehicle(ped, false) then
                        loadAnimDict('veh@low@front_ps@idle_duck')
                        if not IsEntityPlayingAnim(ped, 'veh@low@front_ps@idle_duck', 'sit', 3) then
                            TaskPlayAnim(ped, 'veh@low@front_ps@idle_duck', 'sit', 1.0, 1.0, -1, 1, 0, 0, 0, 0)
                        end
                    else
                        loadAnimDict(lastStandDict)
                        if not IsEntityPlayingAnim(ped, lastStandDict, lastStandAnim, 3) then
                            TaskPlayAnim(ped, lastStandDict, lastStandAnim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
                        end
                    end
                else
                    if IsPedInAnyVehicle(ped, false) then
                        loadAnimDict('veh@low@front_ps@idle_duck')
                        if IsEntityPlayingAnim(ped, 'veh@low@front_ps@idle_duck', 'sit', 3) then
                            StopAnimTask(ped, 'veh@low@front_ps@idle_duck', 'sit', 3)
                        end
                    else
                        loadAnimDict(lastStandDict)
                        if IsEntityPlayingAnim(ped, lastStandDict, lastStandAnim, 3) then
                            StopAnimTask(ped, lastStandDict, lastStandAnim, 3)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
