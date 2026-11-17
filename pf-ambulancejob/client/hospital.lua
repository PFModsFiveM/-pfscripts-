-- Hospital on the client (batch 17E): reception check-in, the bed the server gives, getting up and
-- lying down again; the pharmacy counter (20A). Every decision is the server's (server/hospital/*): the client asks to check
-- in (callback checkIn), shows the bed it is told about ('pf-ambulancejob:client:Bed') and asks to
-- lie down in its own bed again. No loop runs every frame unless a prompt is being drawn.

PFHospitalClient = PFHospitalClient or {}
local HC = PFHospitalClient
local QBCore = exports['pfm-core']:GetCoreObject()

local getOutDict, getOutAnim = 'switch@franklin@bed', 'sleep_getup_rubeyes'
local bed = nil          -- { hospitalId, bedId, coords, model, label } while in a bed
local canLeave = false
local cam = nil
local admission = nil    -- the server's view of our open admission (pf-ambulancejob:client:Admission)

local function cfg() return Config.Hospital end

local function loadDict(dict)
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 200 do Wait(10) tries = tries + 1 end
end

local function bedPose(ped)
    loadDict(inBedDict)
    TaskPlayAnim(ped, inBedDict, inBedAnim, 8.0, 1.0, -1, 1, 0, 0, 0, 0)
end

local function stopCam()
    if cam then
        RenderScriptCams(false, true, 200, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
end

local function startCam(ped)
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', 1)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 1, true, true)
    AttachCamToPedBone(cam, ped, 31085, 0, 1.0, 1.0, true)
    SetCamFov(cam, 90.0)
    local heading = GetEntityHeading(ped)
    heading = (heading > 180) and heading - 180 or heading + 180
    SetCamRot(cam, -45.0, 0.0, heading, 2)
end

--- Lies the player down in the bed the server gave (also while dead: the respawn bed).
local function enterBed(data)
    local ped = PlayerPedId()
    DoScreenFadeOut(500)
    local t = 0
    while not IsScreenFadedOut() and t < 100 do Wait(10) t = t + 1 end
    TriggerEvent('police:client:DeEscort')
    if IsPedDeadOrDying(ped) then
        local pos = GetEntityCoords(ped, true)
        NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
    end
    local c = data.coords
    local obj = GetClosestObjectOfType(c.x, c.y, c.z, 1.0, data.model or 0, false, false, false)
    if obj and obj ~= 0 then FreezeEntityPosition(obj, true) end
    SetEntityCoords(ped, c.x, c.y, c.z + 0.02)
    SetEntityHeading(ped, c.w or 0.0)
    Wait(300)
    FreezeEntityPosition(ped, true)
    bedPose(ped)
    stopCam()
    startCam(ped)
    bed, isInHospitalBed = data, true
    DoScreenFadeIn(500)
end

local function getUp()
    if not bed then return end
    local ped = PlayerPedId()
    loadDict(getOutDict)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityHeading(ped, (bed.coords.w or 0.0) + 90)
    TaskPlayAnim(ped, getOutDict, getOutAnim, 100.0, 1.0, -1, 8, -1, 0, 0, 0)
    Wait(4000)
    ClearPedTasks(ped)
    stopCam()
    bed, isInHospitalBed, canLeave = nil, false, false
    QBCore.Functions.GetPlayerData(function(PlayerData)
        local jail = tonumber(PlayerData.metadata and PlayerData.metadata['injail']) or 0
        if jail > 0 then TriggerEvent('prison:client:Enter', jail) end
    end)
end

--- The bed shows "get up" while the player is in it and may leave (a thread only while that holds).
local function leavePrompt()
    CreateThread(function()
        local shown = false
        while bed and canLeave do
            if not shown then exports['pfm-core']:DrawText(Lang:t('text.bed_out')) shown = true end
            if IsControlJustReleased(0, 38) then
                exports['pfm-core']:KeyPressed(38)
                exports['pfm-core']:HideText()
                shown = false
                getUp()
                return
            end
            Wait(0)
        end
        if shown then exports['pfm-core']:HideText() end
    end)
end

--- client/main.lua calls this after a revive was applied: keep the bed pose, allow getting up.
function HC.OnRevived()
    if not bed then return end
    local ped = PlayerPedId()
    bedPose(ped)
    SetEntityInvincible(ped, true)
    canLeave = true
    leavePrompt()
end

--- A respawn revive carried by the bed: applied once its delay passed (the server re-reads the ped).
local function reviveLater(token, seconds)
    if type(token) ~= 'string' then return end
    CreateThread(function()
        QBCore.Functions.Notify(Lang:t('success.being_helped'), 'success')
        Wait(math.max(0, tonumber(seconds) or 0) * 1000)
        if PFApplyRevive then PFApplyRevive(token, { health = 200 }) end
    end)
end

RegisterNetEvent('pf-ambulancejob:client:Bed', function(action, data)
    data = type(data) == 'table' and data or {}
    if action == 'enter' and type(data.coords) == 'table' then
        canLeave = false
        CreateThread(function()
            enterBed(data)
            if data.token then reviveLater(data.token, data.reviveIn) else canLeave = true leavePrompt() end
        end)
    elseif action == 'spawn' and type(data.coords) == 'table' then
        -- every bed was taken: the respawn wakes the patient at the facility instead
        CreateThread(function()
            local ped = PlayerPedId()
            DoScreenFadeOut(500)
            Wait(600)
            SetEntityCoords(ped, data.coords.x, data.coords.y, data.coords.z)
            DoScreenFadeIn(500)
            reviveLater(data.token, data.reviveIn)
        end)
    elseif action == 'leave' then
        if bed and not canLeave then canLeave = true leavePrompt() end
    end
end)

RegisterNetEvent('pf-ambulancejob:client:Admission', function(view)
    admission = (type(view) == 'table' and view.open) and view or nil
end)

-- ── reception check-in ────────────────────────────────────────────────────────────────────────

function HC.CheckIn(hospitalId)
    TriggerEvent('animations:client:EmoteCommandStart', { 'notepad' })
    QBCore.Functions.Progressbar('hospital_checkin', Lang:t('progress.checking_in'), 2000, false, true, {
        disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
    }, { animDict = 'missheistdockssetup1clipboard@base', anim = 'base', flags = 33 }, {}, {}, function()
        TriggerEvent('animations:client:EmoteCommandStart', { 'c' })
        QBCore.Functions.TriggerCallback('pf-ambulancejob:server:checkIn', function(res)
            if type(res) == 'table' and not res.ok then QBCore.Functions.Notify(tostring(res.message or 'Check-in refused'), 'error') end
        end, hospitalId)
    end, function()
        TriggerEvent('animations:client:EmoteCommandStart', { 'c' })
    end)
end

RegisterNetEvent('pf-ambulancejob:client:CheckIn', function(data)
    local id = type(data) == 'table' and data.hospitalId or data
    if type(id) == 'string' then HC.CheckIn(id) end
end)

local function receptionZones()
    for id, f in pairs(cfg().Facilities) do
        if f.checkIn and f.reception then
            local c = f.reception.coords
            if Config.UseTarget then
                -- one zone per facility, named by facility id (the old names clashed between hospitals)
                exports['pfm-target']:AddBoxZone('pf_hosp_checkin_' .. id, vector3(c.x, c.y, c.z), 3.5, 2, {
                    name = 'pf_hosp_checkin_' .. id, heading = -72, debugPoly = false, minZ = c.z - 2, maxZ = c.z + 2,
                }, {
                    options = { { type = 'client', icon = 'fa fa-clipboard', event = 'pf-ambulancejob:client:CheckIn', label = 'Check in', hospitalId = id } },
                    distance = 1.5,
                })
            else
                local zone = BoxZone:Create(vector3(c.x, c.y, c.z), 3.5, 2, { heading = -72, name = 'pf_hosp_checkin_' .. id, debugPoly = false,
                    minZ = c.z - 2, maxZ = c.z + 2 })
                local inside = false
                zone:onPlayerInOut(function(isInside)
                    inside = isInside
                    if not isInside then exports['pfm-core']:HideText() return end
                    exports['pfm-core']:DrawText(Lang:t('text.check_in'), 'left')
                    CreateThread(function()
                        while inside do
                            if IsControlJustPressed(0, 38) then
                                exports['pfm-core']:KeyPressed(38)
                                exports['pfm-core']:HideText()
                                HC.CheckIn(id)
                                return
                            end
                            Wait(0)
                        end
                    end)
                end)
            end
        end
    end
end

-- ── pharmacy counter (20A): collect a prescription fill; staff open the stock ─────────────────
-- The server decides everything (counter by server position, due fill, stock, items moved); the
-- client only asks and shows the answer.

function HC.CollectPrescription()
    QBCore.Functions.TriggerCallback('pf-ambulancejob:server:pharmacyCollect', function(res)
        if type(res) ~= 'table' then return end
        if res.ok then
            QBCore.Functions.Notify(('Collected %dx %s.'):format(tonumber(res.units) or 1, tostring(res.label or res.item or '')), 'success')
        else
            QBCore.Functions.Notify(tostring(res.message or 'Nothing to collect.'), 'error')
        end
    end)
end

RegisterNetEvent('pf-ambulancejob:client:PharmacyCollect', function() HC.CollectPrescription() end)
RegisterNetEvent('pf-ambulancejob:client:PharmacyStock', function()
    QBCore.Functions.TriggerCallback('pf-ambulancejob:server:pharmacyStock', function(res)
        if type(res) == 'table' and not res.ok then QBCore.Functions.Notify(tostring(res.message or 'Refused.'), 'error') end
    end)
end)

local function pharmacyZones()
    local ph = cfg().Pharmacy
    if type(ph) ~= 'table' or type(ph.Counters) ~= 'table' then return end
    for id, c in pairs(ph.Counters) do
        local p = c.coords
        if Config.UseTarget then
            exports['pfm-target']:AddCircleZone('pf_hosp_pharmacy_' .. id, vector3(p.x, p.y, p.z), 1.2, {
                name = 'pf_hosp_pharmacy_' .. id, debugPoly = false, useZ = true,
            }, {
                options = {
                    { type = 'client', icon = 'fa fa-prescription-bottle', event = 'pf-ambulancejob:client:PharmacyCollect', label = 'Collect prescription' },
                    { type = 'client', icon = 'fa fa-box', event = 'pf-ambulancejob:client:PharmacyStock', label = 'Pharmacy stock', job = 'ambulance' },
                },
                distance = 2.0,
            })
        else
            local zone = BoxZone:Create(vector3(p.x, p.y, p.z), 2.0, 2.0, { heading = 0, name = 'pf_hosp_pharmacy_' .. id, debugPoly = false,
                minZ = p.z - 2, maxZ = p.z + 2 })
            local inside = false
            zone:onPlayerInOut(function(isInside)
                inside = isInside
                if not isInside then exports['pfm-core']:HideText() return end
                exports['pfm-core']:DrawText('[G] Collect prescription', 'left')
                CreateThread(function()
                    while inside do
                        if IsControlJustPressed(0, 47) then
                            exports['pfm-core']:KeyPressed(47)
                            HC.CollectPrescription()
                            Wait(1500)
                        end
                        Wait(0)
                    end
                end)
            end)
        end
    end
end

-- ── lying down in one's own bed again ─────────────────────────────────────────────────────────

local function ownBed()
    if not admission or not admission.bedId then return nil end
    local f = cfg().Facilities[admission.hospitalId]
    if not f then return nil end
    for _, d in pairs(f.departments) do
        for _, b in ipairs(d.beds) do if b.id == admission.bedId then return b end end
    end
    return nil
end

CreateThread(function()
    receptionZones()
    pharmacyZones()
    -- once a second: near our own bed and not in it -> a prompt (per-frame only while it is shown)
    local shown = false
    while true do
        local b = not bed and ownBed()
        local near = b and #(GetEntityCoords(PlayerPedId()) - vector3(b.coords.x, b.coords.y, b.coords.z)) < 2.0
        if near then
            if not shown then exports['pfm-core']:DrawText(Lang:t('text.lie_bed'), 'left') shown = true end
            if IsControlJustPressed(0, 38) then
                exports['pfm-core']:KeyPressed(38)
                TriggerServerEvent('pf-ambulancejob:server:EnterBed')
                exports['pfm-core']:HideText()
                shown = false
                Wait(2000)
            end
            Wait(0)
        else
            if shown then exports['pfm-core']:HideText() shown = false end
            Wait(1000)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    stopCam()
    bed, isInHospitalBed, canLeave, admission = nil, false, false, nil
    FreezeEntityPosition(PlayerPedId(), false)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopCam()
    if bed then FreezeEntityPosition(PlayerPedId(), false) end
end)
