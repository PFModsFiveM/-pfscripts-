QBCore = exports['pfm-core']:GetCoreObject()

local doctorCount = 0
local CurrentDamageList = {}
local playerArmor = nil
-- the hospital bed, reception and check-in live in client/hospital.lua (batch 17E); it sets this
-- global, which the death screen and the old bleed loop read
inBedDict = 'anim@gangops@morgue@table@'
inBedAnim = 'body_search'
isInHospitalBed = false
isBleeding = 0
bleedTickTimer, advanceBleedTimer = 0, 0
fadeOutTimer, blackoutTimer = 0, 0
legCount = 0
armcount = 0
headCount = 0
playerHealth = nil
isDead = false
isStatusChecking = false
statusChecks = {}
statusCheckTime = 0
healAnimDict = 'mini@cpr@char_a@cpr_str'
healAnim = 'cpr_pumpchest'
injured = {}

BodyParts = {
    ['HEAD'] = { label = Lang:t('body.head'), causeLimp = false, isDamaged = false, severity = 0 },
    ['NECK'] = { label = Lang:t('body.neck'), causeLimp = false, isDamaged = false, severity = 0 },
    ['SPINE'] = { label = Lang:t('body.spine'), causeLimp = true, isDamaged = false, severity = 0 },
    ['UPPER_BODY'] = { label = Lang:t('body.upper_body'), causeLimp = false, isDamaged = false, severity = 0 },
    ['LOWER_BODY'] = { label = Lang:t('body.lower_body'), causeLimp = true, isDamaged = false, severity = 0 },
    ['LARM'] = { label = Lang:t('body.left_arm'), causeLimp = false, isDamaged = false, severity = 0 },
    ['LHAND'] = { label = Lang:t('body.left_hand'), causeLimp = false, isDamaged = false, severity = 0 },
    ['LFINGER'] = { label = Lang:t('body.left_fingers'), causeLimp = false, isDamaged = false, severity = 0 },
    ['LLEG'] = { label = Lang:t('body.left_leg'), causeLimp = true, isDamaged = false, severity = 0 },
    ['LFOOT'] = { label = Lang:t('body.left_foot'), causeLimp = true, isDamaged = false, severity = 0 },
    ['RARM'] = { label = Lang:t('body.right_arm'), causeLimp = false, isDamaged = false, severity = 0 },
    ['RHAND'] = { label = Lang:t('body.right_hand'), causeLimp = false, isDamaged = false, severity = 0 },
    ['RFINGER'] = { label = Lang:t('body.right_fingers'), causeLimp = false, isDamaged = false, severity = 0 },
    ['RLEG'] = { label = Lang:t('body.right_leg'), causeLimp = true, isDamaged = false, severity = 0 },
    ['RFOOT'] = { label = Lang:t('body.right_foot'), causeLimp = true, isDamaged = false, severity = 0 },
}

-- Functions

local function GetDamagingWeapon(ped)
    for k, v in pairs(Config.Weapons) do
        if HasPedBeenDamagedByWeapon(ped, k, 0) then
            return v
        end
    end

    return nil
end

local function IsDamagingEvent(damageDone, weapon)
    local luck = math.random(100)
    local multi = damageDone / Config.HealthDamage

    return luck < (Config.HealthDamage * multi) or (damageDone >= Config.ForceInjury or multi > Config.MaxInjuryChanceMulti or Config.ForceInjuryWeapons[weapon])
end

local function DoLimbAlert()
    if not isDead and not InLaststand then
        if #injured > 0 then
            local limbDamageMsg = ''
            if #injured <= Config.AlertShowInfo then
                for k, v in pairs(injured) do
                    limbDamageMsg = limbDamageMsg .. Lang:t('info.pain_message', { limb = v.label, severity = Config.WoundStates[v.severity] })
                    if k < #injured then
                        limbDamageMsg = limbDamageMsg .. ' | '
                    end
                end
            else
                limbDamageMsg = Lang:t('info.many_places')
            end
            QBCore.Functions.Notify(limbDamageMsg, 'primary')
        end
    end
end

local function DoBleedAlert()
    if not isDead and tonumber(isBleeding) > 0 then
        QBCore.Functions.Notify(Lang:t('info.bleed_alert', { bleedstate = Config.BleedingStates[tonumber(isBleeding)].label }), 'error')
    end
end

local function ApplyBleed(level)
    if isBleeding ~= 4 then
        if isBleeding + level > 4 then
            isBleeding = 4
        else
            isBleeding = isBleeding + level
        end
        DoBleedAlert()
    end
end

local function IsInjuryCausingLimp()
    for _, v in pairs(BodyParts) do
        if v.causeLimp and v.isDamaged then
            return true
        end
    end
    return false
end

local function ProcessRunStuff(ped)
    if IsInjuryCausingLimp() then
        RequestAnimSet('move_m@injured')
        while not HasAnimSetLoaded('move_m@injured') do
            Wait(0)
        end
        SetPedMovementClipset(ped, 'move_m@injured', 1)
        SetPlayerSprint(PlayerId(), false)
    end
end

function ResetPartial()
    for _, v in pairs(BodyParts) do
        if v.isDamaged and v.severity <= 2 then
            v.isDamaged = false
            v.severity = 0
        end
    end

    for k, v in pairs(injured) do
        if v.severity <= 2 then
            v.severity = 0
            table.remove(injured, k)
        end
    end

    if isBleeding <= 2 then
        isBleeding = 0
        bleedTickTimer = 0
        advanceBleedTimer = 0
        fadeOutTimer = 0
        blackoutTimer = 0
    end

    ProcessRunStuff(PlayerPedId())
    DoLimbAlert()
    DoBleedAlert()
end

local function ResetAll()
    isBleeding = 0
    bleedTickTimer = 0
    advanceBleedTimer = 0
    fadeOutTimer = 0
    blackoutTimer = 0
    onDrugs = 0
    wasOnDrugs = false
    onPainKiller = 0
    wasOnPainKillers = false
    injured = {}

    for _, v in pairs(BodyParts) do
        v.isDamaged = false
        v.severity = 0
    end

    CurrentDamageList = {}

    ProcessRunStuff(PlayerPedId())
    DoLimbAlert()
    DoBleedAlert()
end

local function IsInDamageList(damage)
    local retval = false
    if CurrentDamageList then
        for k, _ in pairs(CurrentDamageList) do
            if CurrentDamageList[k] == damage then
                retval = true
            end
        end
    end
    return retval
end

local function CheckWeaponDamage(ped)
    local detected = false
    for k, v in pairs(QBCore.Shared.Weapons) do
        if HasPedBeenDamagedByWeapon(ped, k, 0) then
            detected = true
            if not IsInDamageList(k) then
                TriggerEvent('chat:addMessage', {
                    color = { 255, 0, 0 },
                    multiline = false,
                    args = { Lang:t('info.status'), v.damagereason }
                })
                CurrentDamageList[#CurrentDamageList + 1] = k
            end
        end
    end
    ClearEntityLastDamageEntity(ped)
end

local function ApplyImmediateEffects(ped, bone, weapon, damageDone)
    local armor = GetPedArmour(ped)
    if Config.MinorInjurWeapons[weapon] and damageDone < Config.DamageMinorToMajor then
        if Config.CriticalAreas[Config.Bones[bone]] then
            if armor <= 0 then
                ApplyBleed(1)
            end
        end

        if Config.StaggerAreas[Config.Bones[bone]] and (Config.StaggerAreas[Config.Bones[bone]].armored or armor <= 0) then
            if math.random(100) <= math.ceil(Config.StaggerAreas[Config.Bones[bone]].minor) then
                SetPedToRagdoll(ped, 1500, 2000, 3, true, true, false)
            end
        end
    elseif Config.MajorInjurWeapons[weapon] or (Config.MinorInjurWeapons[weapon] and damageDone >= Config.DamageMinorToMajor) then
        if Config.CriticalAreas[Config.Bones[bone]] then
            if armor > 0 and Config.CriticalAreas[Config.Bones[bone]].armored then
                if math.random(100) <= math.ceil(Config.MajorArmoredBleedChance) then
                    ApplyBleed(1)
                end
            else
                ApplyBleed(1)
            end
        else
            if armor > 0 then
                if math.random(100) < (Config.MajorArmoredBleedChance) then
                    ApplyBleed(1)
                end
            else
                if math.random(100) < (Config.MajorArmoredBleedChance * 2) then
                    ApplyBleed(1)
                end
            end
        end

        if Config.StaggerAreas[Config.Bones[bone]] and (Config.StaggerAreas[Config.Bones[bone]].armored or armor <= 0) then
            if math.random(100) <= math.ceil(Config.StaggerAreas[Config.Bones[bone]].major) then
                SetPedToRagdoll(ped, 1500, 2000, 3, true, true, false)
            end
        end
    end
end

local function CheckDamage(ped, bone, weapon, damageDone)
    if weapon == nil then return end

    if Config.Bones[bone] and not isDead and not InLaststand then
        ApplyImmediateEffects(ped, bone, weapon, damageDone)

        if not BodyParts[Config.Bones[bone]].isDamaged then
            BodyParts[Config.Bones[bone]].isDamaged = true
            BodyParts[Config.Bones[bone]].severity = math.random(1, 3)
            injured[#injured + 1] = {
                part = Config.Bones[bone],
                label = BodyParts[Config.Bones[bone]].label,
                severity = BodyParts[Config.Bones[bone]].severity
            }
        else
            if BodyParts[Config.Bones[bone]].severity < 4 then
                BodyParts[Config.Bones[bone]].severity = BodyParts[Config.Bones[bone]].severity + 1

                for _, v in pairs(injured) do
                    if v.part == Config.Bones[bone] then
                        v.severity = BodyParts[Config.Bones[bone]].severity
                    end
                end
            end
        end

        ProcessRunStuff(ped)
    end
end

local function ProcessDamage(ped)
    if not isDead and not InLaststand and not onPainKillers then
        for _, v in pairs(injured) do
            if (v.part == 'LLEG' and v.severity > 1) or (v.part == 'RLEG' and v.severity > 1) or (v.part == 'LFOOT' and v.severity > 2) or (v.part == 'RFOOT' and v.severity > 2) then
                if legCount >= Config.LegInjuryTimer then
                    if not IsPedRagdoll(ped) and IsPedOnFoot(ped) then
                        local chance = math.random(100)
                        if (IsPedRunning(ped) or IsPedSprinting(ped)) then
                            if chance <= Config.LegInjuryChance.Running then
                                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08) -- change this float to increase/decrease camera shake
                                SetPedToRagdollWithFall(ped, 1500, 2000, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                            end
                        else
                            if chance <= Config.LegInjuryChance.Walking then
                                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08) -- change this float to increase/decrease camera shake
                                SetPedToRagdollWithFall(ped, 1500, 2000, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                            end
                        end
                    end
                    legCount = 0
                else
                    legCount = legCount + 1
                end
            elseif (v.part == 'LARM' and v.severity > 1) or (v.part == 'LHAND' and v.severity > 1) or (v.part == 'LFINGER' and v.severity > 2) or (v.part == 'RARM' and v.severity > 1) or (v.part == 'RHAND' and v.severity > 1) or (v.part == 'RFINGER' and v.severity > 2) then
                if armcount >= Config.ArmInjuryTimer then
                    if (v.part == 'LARM' and v.severity > 1) or (v.part == 'LHAND' and v.severity > 1) or (v.part == 'LFINGER' and v.severity > 2) then
                        local isDisabled = 15
                        CreateThread(function()
                            while isDisabled > 0 do
                                if IsPedInAnyVehicle(ped, true) then
                                    DisableControlAction(0, 63, true) -- veh turn left
                                end

                                if IsPlayerFreeAiming(PlayerId()) then
                                    DisablePlayerFiring(PlayerId(), true) -- Disable weapon firing
                                end

                                isDisabled = isDisabled - 1
                                Wait(1)
                            end
                        end)
                    else
                        local isDisabled = 15
                        CreateThread(function()
                            while isDisabled > 0 do
                                if IsPedInAnyVehicle(ped, true) then
                                    DisableControlAction(0, 63, true) -- veh turn left
                                end

                                if IsPlayerFreeAiming(PlayerId()) then
                                    DisableControlAction(0, 25, true) -- Disable weapon firing
                                end

                                isDisabled = isDisabled - 1
                                Wait(1)
                            end
                        end)
                    end

                    armcount = 0
                else
                    armcount = armcount + 1
                end
            elseif (v.part == 'HEAD' and v.severity > 2) then
                if headCount >= Config.HeadInjuryTimer then
                    local chance = math.random(100)

                    if chance <= Config.HeadInjuryChance then
                        SetFlash(0, 0, 100, 10000, 100)

                        DoScreenFadeOut(100)
                        while not IsScreenFadedOut() do
                            Wait(0)
                        end

                        if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
                            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08) -- change this float to increase/decrease camera shake
                            SetPedToRagdoll(ped, 5000, 1, 2)
                        end

                        Wait(5000)
                        DoScreenFadeIn(250)
                    end
                    headCount = 0
                else
                    headCount = headCount + 1
                end
            end
        end
    end
end

-- Events

RegisterNetEvent('hospital:client:ambulanceAlert', function(coords, text)
    local street1, street2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street1name = GetStreetNameFromHashKey(street1)
    local street2name = GetStreetNameFromHashKey(street2)
    QBCore.Functions.Notify({ text = text, caption = street1name .. ' ' .. street2name }, 'ambulance')
    PlaySound(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', 0, 0, 1)
    local transG = 250
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    local blip2 = AddBlipForCoord(coords.x, coords.y, coords.z)
    local blipText = Lang:t('info.ems_alert', { text = text })
    SetBlipSprite(blip, 153)
    SetBlipSprite(blip2, 161)
    SetBlipColour(blip, 1)
    SetBlipColour(blip2, 1)
    SetBlipDisplay(blip, 4)
    SetBlipDisplay(blip2, 8)
    SetBlipAlpha(blip, transG)
    SetBlipAlpha(blip2, transG)
    SetBlipScale(blip, 0.8)
    SetBlipScale(blip2, 2.0)
    SetBlipAsShortRange(blip, false)
    SetBlipAsShortRange(blip2, false)
    PulseBlip(blip2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(blipText)
    EndTextCommandSetBlipName(blip)
    while transG ~= 0 do
        Wait(180 * 4)
        transG = transG - 1
        SetBlipAlpha(blip, transG)
        SetBlipAlpha(blip2, transG)
        if transG == 0 then
            RemoveBlip(blip)
            return
        end
    end
end)

-- Comes back up locally (the server's revive, or getting up when the server says so).
local function StandUp()
    local player = PlayerPedId()
    if isDead or InLaststand or IsEntityDead(player) then
        local pos = GetEntityCoords(player, true)
        NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, GetEntityHeading(player), true, false)
        player = PlayerPedId()
    end
    isDead = false
    SetEntityInvincible(player, false)
    SetLaststand(false)
    emsNotified = false
end

local pendingRevive = nil
--- Applies a revive the server started (token): heal, then tell the server, which re-reads the
--- ped and only then marks us up. Asked again a few times while the server has not answered.
local function ApplyRevive(token, opts)
    opts = opts or {}
    local player = PlayerPedId()
    StandUp()
    player = PlayerPedId()
    -- lying in a hospital bed: client/hospital.lua keeps the bed pose and lets the patient get up
    if PFHospitalClient and PFHospitalClient.OnRevived then PFHospitalClient.OnRevived() end
    SetEntityMaxHealth(player, 200)
    SetEntityHealth(player, tonumber(opts.health) or 200)
    ClearPedBloodDamage(player)
    SetPlayerSprint(PlayerId(), true)
    ResetAll()
    ResetPedMovementClipset(player, 0.0)
    TriggerServerEvent('hud:server:RelieveStress', 100)
    pendingRevive = token
    CreateThread(function()
        for _ = 1, 3 do
            TriggerServerEvent('pf-ambulancejob:server:ReviveApplied', token)
            Wait(2500)
            if pendingRevive ~= token then return end
        end
    end)
end

-- client/hospital.lua applies the revive a respawn bed carries once its delay has passed
PFApplyRevive = ApplyRevive

RegisterNetEvent('pf-ambulancejob:client:Revive', function(token, _, opts)
    if type(token) ~= 'string' then return end
    ApplyRevive(token, opts)
end)

-- The server's down state: false (up), 'unconscious' / 'arrest' (last stand) or 'dead'.
RegisterNetEvent('pf-ambulancejob:client:SetDown', function(state, info)
    info = type(info) == 'table' and info or {}
    ServerDownState = state
    if not state then
        pendingRevive = nil
        if isDead or InLaststand then
            StandUp()
            QBCore.Functions.Notify(Lang:t('info.healthy'))
        end
    elseif state == 'dead' then
        if InLaststand then SetLaststand(false) end
        CreateThread(function() OnDeath(info) end)
        deathTime = tonumber(info.respawnIn) or deathTime
    else
        if isDead then isDead = false end
        CreateThread(function() SetLaststand(true, info) end)
    end
end)

-- Legacy local revive (other scripts): only heals a player who is up; a down player is revived by the server.
RegisterNetEvent('hospital:client:Revive', function()
    if isDead or InLaststand or ServerDownState then return end
    local player = PlayerPedId()
    SetEntityHealth(player, 200)
    ClearPedBloodDamage(player)
    ResetAll()
end)

RegisterNetEvent('hospital:client:SetPain', function()
    ApplyBleed(math.random(1, 4))
    if not BodyParts[Config.Bones[24816]].isDamaged then
        BodyParts[Config.Bones[24816]].isDamaged = true
        BodyParts[Config.Bones[24816]].severity = math.random(1, 4)
        injured[#injured + 1] = {
            part = Config.Bones[24816],
            label = BodyParts[Config.Bones[24816]].label,
            severity = BodyParts[Config.Bones[24816]].severity
        }
    end

    if not BodyParts[Config.Bones[40269]].isDamaged then
        BodyParts[Config.Bones[40269]].isDamaged = true
        BodyParts[Config.Bones[40269]].severity = math.random(1, 4)
        injured[#injured + 1] = {
            part = Config.Bones[40269],
            label = BodyParts[Config.Bones[40269]].label,
            severity = BodyParts[Config.Bones[40269]].severity
        }
    end
end)

RegisterNetEvent('hospital:client:KillPlayer', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('hospital:client:HealInjuries', function(type)
    if type == 'full' then
        ResetAll()
    else
        ResetPartial()
    end
    QBCore.Functions.Notify(Lang:t('success.wounds_healed'), 'success')
end)

-- Legacy name: the server picks the hospital and checks that we are dead and the time has passed
-- (handcuffs come off on the server, from its 'respawned' event).
RegisterNetEvent('hospital:client:RespawnAtHospital', function()
    TriggerServerEvent('pf-ambulancejob:server:RequestRespawn')
end)

RegisterNetEvent('hospital:client:SetDoctorCount', function(amount)
    doctorCount = amount
end)

RegisterNetEvent('hospital:client:adminHeal', function()
    if isDead or InLaststand or ServerDownState then return end
    SetEntityHealth(PlayerPedId(), 200)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    local ped = PlayerPedId()
    -- the down state and armour stay with the character on the server
    ServerDownState = false
    InLaststand = false
    isDead = false
    deathTime = 0
    SetEntityInvincible(ped, false)
    SetPedArmour(ped, 0)
    ResetAll()
end)

-- Threads

CreateThread(function()
    for i = 1, #Config.Locations['stations'] do
        local station = Config.Locations['stations'][i]
        local blip = AddBlipForCoord(station.coords.x, station.coords.y, station.coords.z)
        SetBlipSprite(blip, 61)
        SetBlipAsShortRange(blip, true)
        SetBlipScale(blip, 0.8)
        SetBlipColour(blip, 25)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(station.label)
        EndTextCommandSetBlipName(blip)
    end
end)

CreateThread(function()
    while true do
        Wait((1000 * Config.MessageTimer))
        DoLimbAlert()
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if isStatusChecking then
            statusCheckTime = statusCheckTime - 1
            if statusCheckTime <= 0 then
                statusChecks = {}
                isStatusChecking = false
            end
        end
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local health = GetEntityHealth(ped)
        local armor = GetPedArmour(ped)

        if not playerHealth then
            playerHealth = health
        end

        if not playerArmor then
            playerArmor = armor
        end

        local armorDamaged = (playerArmor ~= armor and armor < (playerArmor - Config.ArmorDamage) and armor > 0) -- Players armor was damaged
        local healthDamaged = (playerHealth ~= health)                                                           -- Players health was damaged

        local damageDone = (playerHealth - health)

        if armorDamaged or healthDamaged then
            local hit, bone = GetPedLastDamageBone(ped)
            local bodypart = Config.Bones[bone]
            local weapon = GetDamagingWeapon(ped)

            if hit and bodypart ~= 'NONE' then
                local checkDamage = true
                if damageDone >= Config.HealthDamage then
                    if weapon then
                        if armorDamaged and (bodypart == 'SPINE' or bodypart == 'UPPER_BODY') or weapon == Config.WeaponClasses['NOTHING'] then
                            checkDamage = false -- Don't check damage if the it was a body shot and the weapon class isn't that strong
                        end

                        if checkDamage then
                            if IsDamagingEvent(damageDone, weapon) then
                                CheckDamage(ped, bone, weapon, damageDone)
                            end
                        end
                    end
                elseif Config.AlwaysBleedChanceWeapons[weapon] then
                    if armorDamaged and (bodypart == 'SPINE' or bodypart == 'UPPER_BODY') or weapon == Config.WeaponClasses['NOTHING'] then
                        checkDamage = false -- Don't check damage if the it was a body shot and the weapon class isn't that strong
                    end
                    if math.random(100) < Config.AlwaysBleedChance and checkDamage then
                        ApplyBleed(1)
                    end
                end
            end

            CheckWeaponDamage(ped)
        end

        playerHealth = health
        playerArmor = armor

        if not isInHospitalBed then
            ProcessDamage(ped)
        end
        Wait(100)
    end
end)
