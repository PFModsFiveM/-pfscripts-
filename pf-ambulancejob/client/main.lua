QBCore = exports['pfm-core']:GetCoreObject()

local doctorCount = 0
-- the hospital bed, reception and check-in live in client/hospital.lua (batch 17E); it sets this
-- global, which the death screen reads
inBedDict = 'anim@gangops@morgue@table@'
inBedAnim = 'body_search'
isInHospitalBed = false
isDead = false
isStatusChecking = false
statusChecks = {}
statusCheckTime = 0
healAnimDict = 'mini@cpr@char_a@cpr_str'
healAnim = 'cpr_pumpchest'
-- The old client limb/bleed model (BodyParts, the 100 ms damage watcher, bleed ticks, limp and arm
-- effects, the limb alert loop) is gone: injuries are the server's (server/medical/*) and their
-- effects come from client/effects.lua (17C), which pushes them only while a channel is non-zero.

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
end)

RegisterNetEvent('hospital:client:KillPlayer', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

-- the wounds themselves are healed on the server; this only tells the player
RegisterNetEvent('hospital:client:HealInjuries', function()
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
