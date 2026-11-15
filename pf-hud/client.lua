-- pf-hud client: the player's numbers, when the HUD shows, the settings menu and layout editor.
-- The look is ported from WHIP (see NOTICE.md): client/radar.lua and client/skin.lua dress GTA's radar,
-- client/dial.lua feeds the 3D rev dial, client/radar_tuner.lua is the admin radar tuner, client/prefs.lua keeps the
-- settings (pfm-ui prefs when it runs).
local QBCore = exports['pfm-core']:GetCoreObject()

-- ── state ────────────────────────────────────────────────────────────
local PlayerData = {}
local loggedIn = LocalPlayer.state.isLoggedIn or false
local settings = {}

local hunger, thirst, stress = 100, 100, 0
local seatbeltOn, harnessOn, harnessHp = false, false, 0
local cruiseOn = false
local nitroActive, nitroLevel, nitroMax = false, 0, 0
local inVehicle = false
local beltable = false   -- the vehicle has seatbelts (not a bike, boat, aircraft or train)
--- Vehicle classes with no seatbelt: motorcycles, cycles, boats, helicopters, planes, trains.
local NO_BELT = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }
local menuOpen = false
local editing = false
local voiceLevel = 50
local radioTalking = false

-- ── settings ─────────────────────────────────────────────────────────
local function loadSettings() return HudPrefs.load() end
local function saveSettings() HudPrefs.save(settings) end

local function pushSettings()
    SendNUIMessage({ action = 'settings', settings = settings, currency = Config.CurrencyText,
        prefsFromUi = HudPrefs.uiRunning() })
end

-- ── global UI theme (shared with every PF-themed interface) ──────────
exports('GetTheme', function()
    return settings.theme or Config.Defaults.theme
end)

local function broadcastTheme()
    TriggerEvent('pf-ui:themeUpdated', settings.theme or Config.Defaults.theme)
end

-- ── gauges: what the row shows (registered on the page, which draws them) ──
-- Icons are SVG paths in a 24x24 box. voice, health, armour, hunger, thirst and oxygen are WHIP's; stress, the seatbelt
-- and cruise control are PF's own.
local ICONS = {
    voice = 'M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.3-3c0 '
        .. '3-2.54 5.1-5.3 5.1S6.7 14 6.7 11H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c3.28-.49 6-3.31 6-6.72h-1.7z',
    radio = 'M8 6H16A2 2 0 0 1 18 8V21A2 2 0 0 1 16 23H8A2 2 0 0 1 6 21V8A2 2 0 0 1 8 6Z'
        .. 'M7 1.5H8.6V6H7Z' .. 'M8.5 8.5V12.5H15.5V8.5Z' .. 'M8.5 15V16.5H15.5V15Z' .. 'M8.5 18.5V20H15.5V18.5Z',
    health = 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 '
        .. '16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z',
    armour = 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z',
    armourCracked = 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z|M11 5 L10 8 L12.5 10 L10.5 14 L12 17|M10 8 L8 9.5'
        .. '|M12.5 10 L15 10.5|M12.5 10 L13.5 8|M10.5 14 L8.5 15|M10.5 14 L9 12.5|M12 17 L14 18',
    hunger = 'M11 9H9V2H7v7H5V2H3v7c0 2.12 1.66 3.84 3.75 3.97V22h2.5v-9.03C11.34 12.84 13 11.12 13 9V2h-2v7zm5-3v8h2.5v8H21'
        .. 'V2c-2.76 0-5 2.24-5 4z',
    thirst = 'M12 2c-5.33 4.55-8 8.48-8 11.8 0 4.98 3.8 8.2 8 8.2s8-3.22 8-8.2c0-3.32-2.67-7.25-8-11.8z',
    oxygen = 'M3.5 15a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0-11 0z M5.5 15a3.5 3.5 0 1 1 7 0a3.5 3.5 0 1 1-7 0z'
        .. ' M13.5 7.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0z M15 7.5a2 2 0 1 1 4 0a2 2 0 1 1-4 0z'
        .. ' M7 4a2 2 0 1 0 4 0a2 2 0 1 0-4 0z',
    -- PF: a lightning bolt
    stress = 'M13.5 2 4.5 13.5h6l-1.5 8.5 9-11.5h-6z',
    -- PF: a seatbelt buckle (the hole wound the other way, so it is cut out) and its tongue
    seatbelt = 'M2 7h13v10H2z M4 9v6h9V9z M15.5 10.5h6.5v3h-6.5z',
    -- PF: a speedometer with its needle
    cruise = 'M12 4C6.48 4 2 8.48 2 14c0 2.04.61 3.93 1.66 5.51l1.7-1.06A8 8 0 1 1 18.64 18.45l1.7 1.06A9.96 9.96 0 0 0 22 '
        .. '14C22 8.48 17.52 4 12 4z M10.6 15.4a2 2 0 0 0 2.83 0L17.6 9.2l-.8-.8-6.2 4.17a2 2 0 0 0 0 2.83z',
}

local function statDefs()
    return {
        { name = 'voice', type = 'custom', max = 100, color = '#a78bfa', icon = ICONS.voice, iconRadio = ICONS.radio,
          noCritical = true },
        { name = 'health', type = 'vital', max = 100, color = '#34d399', icon = ICONS.health, heartbeat = true,
          interruptDelta = 10 },
        { name = 'armour', type = 'vital', max = 100, color = '#818cf8', icon = ICONS.armour,
          iconCritical = ICONS.armourCracked, hideWhenEmpty = true, interruptDelta = 10 },
        { name = 'hunger', type = 'need', max = 100, color = '#fb923c', icon = ICONS.hunger, idleAbove = 95 },
        { name = 'thirst', type = 'need', max = 100, color = '#38bdf8', icon = ICONS.thirst, idleAbove = 95 },
        { name = 'stress', type = 'custom', max = 100, color = '#f472b6', icon = ICONS.stress, showAboveZero = true,
          noCritical = true, criticalAbove = 85 },
        { name = 'oxygen', type = 'custom', max = 100, color = '#22d3ee', icon = ICONS.oxygen, showBelowFull = true,
          heartbeat = true, glide = true },
        { name = 'seatbelt', type = 'flag', max = 1, color = '#ffffff', icon = ICONS.seatbelt, showWhenPresent = true,
          warnWhenOff = true, presentKey = 'beltable' },
        { name = 'cruise', type = 'flag', max = 1, color = '#ffffff', icon = ICONS.cruise, showWhenPresent = true,
          onlyWhenOn = true, accentWhenOn = true },
    }
end

-- ── voice (pma-voice: its talking modes and radio) ───────────────────
local VOICE_LEVELS = { 20, 50, 100 }

AddEventHandler('pma-voice:setTalkingMode', function(mode)
    mode = tonumber(mode) or 2
    voiceLevel = VOICE_LEVELS[mode] or math.min(100, mode * 33)
end)

AddEventHandler('pma-voice:radioActive', function(on)
    radioTalking = on == true
end)

local function isOnRadio()
    if radioTalking then return true end
    local ok, radio = pcall(function() return LocalPlayer.state.radioActive end)
    return ok and radio == true or false
end

-- ── HUD visibility ───────────────────────────────────────────────────
local hudHidden = nil

local function hudShouldHide()
    if not loggedIn or settings.cinematicMode then return true end
    if IsPauseMenuActive() then return true end
    if Config.HideWhenDead and IsEntityDead(PlayerPedId()) then return true end
    return false
end

local function refreshHudVisibility(force)
    local hide = hudShouldHide()
    if hide == hudHidden and not force then return end
    hudHidden = hide
    SendNUIMessage({ action = hide and 'hideStatusHud' or 'showStatusHud' })
end

local function radarWanted()
    if HudTuner and HudTuner.open then return true end
    if not loggedIn or settings.cinematicMode or IsPauseMenuActive() then return false end
    if inVehicle then return settings.minimapInVehicle ~= false end
    return settings.minimapOnFoot == true
end

local function refreshRadar()
    HudRadar.setVisible(radarWanted())
end

-- ── status loop: change-gated, one message table refilled ────────────
local _status = { action = 'updateStatusHud' }
local STATUS_KEYS = { 'voice', 'health', 'armour', 'hunger', 'thirst', 'stress', 'oxygen', 'inVehicle', 'beltable', 'seatbelt', 'cruise' }
local _statusSent = {}

local function statusChanged(key, value)
    if _statusSent[key] ~= value then
        _statusSent[key] = value
        return true
    end
    return false
end

local function startStatusLoop()
    CreateThread(function()
        local pid = PlayerId()
        while loggedIn do
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped) - 100
            if health < 0 then health = 0 end
            local oxygen = 100
            if IsPedSwimmingUnderWater(ped) or IsEntityInWater(ped) then
                oxygen = math.floor(GetPlayerUnderwaterTimeRemaining(pid) * 10 + 0.5)
                if oxygen > 100 then oxygen = 100 end
                if oxygen < 0 then oxygen = 0 end
            end
            local talking = NetworkIsPlayerTalking(pid) and true or false
            local radio = talking and isOnRadio() or false
            local s = _status
            s.voice, s.health, s.armour = voiceLevel, health, GetPedArmour(ped)
            s.hunger, s.thirst, s.stress, s.oxygen = math.floor(hunger + 0.5), math.floor(thirst + 0.5), math.floor(stress + 0.5), oxygen
            s.inVehicle, s.beltable, s.seatbelt, s.cruise = inVehicle, inVehicle and beltable, (seatbeltOn or harnessOn), cruiseOn
            local changed = false
            for i = 1, #STATUS_KEYS do
                local k = STATUS_KEYS[i]
                if statusChanged(k, s[k]) then changed = true end
            end
            if changed then SendNUIMessage(s) end
            if statusChanged('talking', talking) or statusChanged('radio', radio) then
                SendNUIMessage({ action = 'setVoiceTalking', talking = talking, mode = radio and 'radio' or nil })
            end
            refreshHudVisibility(false)
            refreshRadar()
            Wait(Config.UpdateRates.status)
        end
        SendNUIMessage({ action = 'hideStatusHud' })
        hudHidden = true
    end)
end

-- ── vehicle loop: the gauges round the dial and the row's seatbelt/cruise ──
local function getFuel(veh)
    if Config.FuelExport ~= '' and GetResourceState(Config.FuelExport) == 'started' then
        local ok, fuel = pcall(function() return exports[Config.FuelExport]:GetFuel(veh) end)
        if ok and fuel then return fuel end
    end
    return GetVehicleFuelLevel(veh)
end

local _veh = { action = 'vehicle', show = true }
local VEHICLE_KEYS = { 'show', 'unit', 'fuel', 'engine', 'seatbelt', 'harness', 'cruise', 'nitroActive', 'nitro' }
local _vehSent = {}

local function startVehicleLoop()
    if Config.DisableCarHud then return end
    CreateThread(function()
        _vehSent = {}
        SendNUIMessage({ action = 'showVehicleHud' })
        while loggedIn and inVehicle do
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and not IsThisModelABicycle(GetEntityModel(veh)) then
                local fuel = math.floor((getFuel(veh) or 0) + 0.5)
                local v = _veh
                v.show = not settings.cinematicMode
                v.unit = settings.speedUnit
                v.fuel = fuel
                v.lowFuel = fuel <= Config.LowFuelThreshold
                v.engine = math.floor(GetVehicleEngineHealth(veh) / 10 + 0.5)
                v.seatbelt = seatbeltOn or harnessOn
                v.harness = harnessOn
                v.cruise = cruiseOn
                v.nitroActive = nitroActive
                v.nitro = nitroMax > 0 and math.floor(nitroLevel / nitroMax * 100 + 0.5) or 0
                local changed = false
                for i = 1, #VEHICLE_KEYS do
                    local k = VEHICLE_KEYS[i]
                    if _vehSent[k] ~= v[k] then _vehSent[k] = v[k]; changed = true end
                end
                if changed then SendNUIMessage(v) end
            end
            Wait(Config.UpdateRates.vehicle)
        end
        SendNUIMessage({ action = 'vehicle', show = false })
        SendNUIMessage({ action = 'hideVehicleHud' })
    end)
end

-- ── compass loop ─────────────────────────────────────────────────────
local directions = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N' }
local _compass = { action = 'compass', show = true }
local compassResend = false   -- the page showed a sample (the layout editor): send the real one again
local function startCompassLoop()
    CreateThread(function()
        local lastKey = nil
        while loggedIn do
            local showCompass = settings.showCompass and not settings.cinematicMode and (inVehicle or settings.compassOnFoot)
            if showCompass then
                local ped = PlayerPedId()
                local heading = 360 - GetEntityHeading(ped) -- clockwise compass
                local dir = directions[math.floor(((heading % 360) + 22.5) / 45) + 1]
                local street = ''
                if settings.showStreets then
                    local coords = GetEntityCoords(ped)
                    local s1, s2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                    street = GetStreetNameFromHashKey(s1)
                    local cross = GetStreetNameFromHashKey(s2)
                    if cross and cross ~= '' then street = street .. ' / ' .. cross end
                end
                local deg = math.floor(heading % 360)
                local key = deg .. dir .. street
                if key ~= lastKey or compassResend then
                    lastKey, compassResend = key, false
                    _compass.heading, _compass.direction, _compass.street = deg, dir, street
                    SendNUIMessage(_compass)
                end
                Wait(Config.UpdateRates.compass)
            else
                if lastKey ~= false or compassResend then
                    compassResend = false
                    lastKey = false
                    SendNUIMessage({ action = 'compass', show = false })
                end
                Wait(750)
            end
        end
        SendNUIMessage({ action = 'compass', show = false })
    end)
end

-- ── vehicle enter/exit watcher ───────────────────────────────────────
local function startVehicleWatcher()
    CreateThread(function()
        while loggedIn do
            local ped = PlayerPedId()
            local nowIn = IsPedInAnyVehicle(ped, false)
            if nowIn and not inVehicle then
                inVehicle = true
                beltable = not NO_BELT[GetVehicleClass(GetVehiclePedIsIn(ped, false))]
                seatbeltOn = false
                cruiseOn = false
                refreshRadar()
                startVehicleLoop()
            elseif not nowIn and inVehicle then
                inVehicle = false
                seatbeltOn = false
                cruiseOn = false
                refreshRadar()
            end
            Wait(400)
        end
    end)
end

-- ── stress mechanics (shooting / speeding) ───────────────────────────
local stressStarted = false
local function startStressLoops()
    if not Config.StressEnabled or stressStarted then return end
    stressStarted = true
    -- shooting
    CreateThread(function()
        local whitelist = {}
        for i = 1, #Config.WhitelistedWeaponStress do whitelist[Config.WhitelistedWeaponStress[i]] = true end
        while loggedIn do
            local ped = PlayerPedId()
            if IsPedShooting(ped) then
                local weapon = GetSelectedPedWeapon(ped)
                if not whitelist[weapon] and math.random() <= Config.StressChance then
                    if not (Config.DisablePoliceStress and PlayerData.job and PlayerData.job.name == 'police') then
                        TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                    end
                end
                Wait(400)
            end
            Wait(100)
        end
        stressStarted = false
    end)
    -- speeding
    CreateThread(function()
        while loggedIn do
            if inVehicle then
                local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                local speed = GetEntitySpeed(veh) * (settings.speedUnit == 'mph' and 2.236936 or 3.6)
                local threshold = (seatbeltOn or harnessOn) and Config.MinimumSpeed or Config.MinimumSpeedUnbuckled
                if speed >= threshold then
                    TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                end
            end
            Wait(10000)
        end
    end)
    -- screen effects at high stress
    CreateThread(function()
        while loggedIn do
            if stress >= Config.MinimumStress then
                local intensity = math.min((stress - Config.MinimumStress) / (100 - Config.MinimumStress), 1.0)
                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', intensity * 0.18)
                Wait(math.random(4000, 9000))
            else
                Wait(5000)
            end
        end
    end)
end

-- ── cinematic mode ───────────────────────────────────────────────────
local function applyCinematic()
    SendNUIMessage({ action = 'cinematic', active = settings.cinematicMode })
    refreshHudVisibility(false)
    refreshRadar()
end

-- ── applying settings ────────────────────────────────────────────────
local MAP_KEYS = { minimapStyle = true, minimapShape = true, mapBackground = true }
local DIAL_KEYS = { dialStyle = true, dialHorizon = true, speedUnit = true }

local function applyMinimap(shapeChanged)
    CreateThread(function()
        if shapeChanged ~= false then HudRadar.applyMask(settings.minimapShape) end
        HudRadar.applyRects(true)
        HudSkin.apply(settings, loggedIn)
    end)
end

--- After settings changed: push them, and redo what the changed keys touch (nil: everything).
local function applySettings(old)
    pushSettings()
    broadcastTheme()
    local mapChanged, shapeChanged, dialChanged = old == nil, old == nil, old == nil
    if old then
        for k in pairs(MAP_KEYS) do if old[k] ~= settings[k] then mapChanged = true end end
        shapeChanged = old.minimapShape ~= settings.minimapShape
        for k in pairs(DIAL_KEYS) do if old[k] ~= settings[k] then dialChanged = true end end
    end
    if mapChanged then applyMinimap(shapeChanged) end
    if dialChanged then HudDial.configure(settings) end
    applyCinematic()
end

local function snapshot()
    local s = {}
    for k, v in pairs(settings) do s[k] = v end
    return s
end

-- a HUD pref changed in the pause menu (pfm-ui)
HudPrefs.onChange(function(name, value)
    if settings[name] == nil or settings[name] == value then return end
    local old = snapshot()
    settings[name] = value
    applySettings(old)
end)

-- pfm-ui (re)started after the HUD: declare the prefs again and read them
AddEventHandler('onClientResourceStart', function(res)
    if res == 'pfm-ui' then
        HudPrefs.define()
        if loggedIn then
            local old = snapshot()
            settings = loadSettings()
            applySettings(old)
        end
    elseif res == (Config.MediaMapResource or 'pfm-media-map') and loggedIn then
        HudSkin.apply(settings, loggedIn)
    end
end)

-- ── boot / teardown ──────────────────────────────────────────────────
HudDial.allowed = function()
    return loggedIn and not settings.cinematicMode
end

local function startHud()
    HudPrefs.define()
    settings = loadSettings()
    SendNUIMessage({ action = 'registerHudStats', stats = statDefs() })
    _statusSent = {}
    hudHidden = nil
    applySettings(nil)
    HudRadar.setActive(true)
    refreshRadar()
    startStatusLoop()
    startVehicleWatcher()
    startCompassLoop()
    startStressLoops()
    HudDial.start()
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    local md = PlayerData.metadata or {}
    hunger = md.hunger or 100
    thirst = md.thirst or 100
    stress = md.stress or 0
    loggedIn = true
    startHud()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    loggedIn = false
    SendNUIMessage({ action = 'hideStatusHud' })
    SendNUIMessage({ action = 'vehicle', show = false })
    SendNUIMessage({ action = 'hideVehicleHud' })
    SendNUIMessage({ action = 'compass', show = false })
    HudRadar.setActive(false)
    HudSkin.apply(settings, false)
    HudRadar.setVisible(false)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, val)
    if key == 'all' then
        PlayerData = val
        local md = val.metadata or {}
        hunger, thirst, stress = md.hunger or hunger, md.thirst or thirst, md.stress or stress
    else
        PlayerData[key] = val
        if key == 'metadata' then
            hunger, thirst, stress = val.hunger or hunger, val.thirst or thirst, val.stress or stress
        end
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then
        PlayerData = QBCore.Functions.GetPlayerData()
        loggedIn = true
        startHud()
    end
end)

-- the page reloaded (or loaded late): everything again
RegisterNUICallback('ready', function(_, cb)
    cb('ok')
    if not loggedIn then return end
    SendNUIMessage({ action = 'registerHudStats', stats = statDefs() })
    _statusSent = {}
    pushSettings()
    HudSkin.resend()
    HudDial.sendConfig()
    refreshHudVisibility(true)
end)

-- ── external events (API kept from the old HUD) ──────────────────────
RegisterNetEvent('hud:client:UpdateNeeds', function(newHunger, newThirst)
    hunger = newHunger or hunger
    thirst = newThirst or thirst
end)

RegisterNetEvent('hud:client:UpdateStress', function(newStress)
    stress = newStress or stress
end)

RegisterNetEvent('seatbelt:client:ToggleSeatbelt', function(state)
    seatbeltOn = state
end)

RegisterNetEvent('hud:client:ToggleShowSeatbelt', function(state)
    if state ~= nil then seatbeltOn = state end
end)

-- pfm-smallresources cruise control (client/cruise.lua) raises this locally when it turns on/off
AddEventHandler('seatbelt:client:ToggleCruise', function(state)
    cruiseOn = state == true
end)

RegisterNetEvent('hud:client:UpdateHarness', function(hp)
    harnessHp = hp or 0
    harnessOn = harnessHp > 0
end)

RegisterNetEvent('hud:client:UpdateNitrous', function(active, level, maxLevel)
    nitroActive = active or false
    nitroLevel = level or 0
    nitroMax = maxLevel or 0
end)

RegisterNetEvent('hud:client:ShowAccounts', function(account, amount)
    if not settings.showMoney then return end
    SendNUIMessage({ action = 'account', account = account, amount = amount })
end)

RegisterNetEvent('hud:client:OnMoneyChange', function(moneyType, amount, isMinus)
    if not settings.showMoney then return end
    local cash = PlayerData.money and PlayerData.money.cash
    local bank = PlayerData.money and PlayerData.money.bank
    SendNUIMessage({
        action = 'money',
        type = moneyType,
        amount = amount,
        minus = isMinus,
        cash = cash,
        bank = bank,
    })
end)

-- compat stubs so nothing that still fires old pf-hud events errors
RegisterNetEvent('hud:client:LoadMap', function() applyMinimap(true) end)
RegisterNetEvent('hud:client:UpdateUISettings', function() end)
RegisterNetEvent('hud:client:EngineHealth', function() end)
RegisterNetEvent('hud:client:ToggleAirHud', function() end)
RegisterNetEvent('hud:client:BuffEffect', function() end)
RegisterNetEvent('hud:client:EnhancementEffect', function() end)

-- ── settings menu and layout editor (controller: pfm-ui's pad bridge) ──
local function attachPad()
    if PadBridge then PadBridge.attach({ active = function() return menuOpen or editing end }) end
end

local function detachPad()
    if PadBridge then PadBridge.detach() end
end

local function openMenu()
    if not loggedIn or menuOpen or editing then return end
    menuOpen = true
    SetNuiFocus(true, true)
    attachPad()
    SendNUIMessage({ action = 'openMenu', settings = settings, prefsFromUi = HudPrefs.uiRunning() })
end

RegisterNUICallback('closeMenu', function(_, cb)
    local wasEditing = editing
    menuOpen = false
    editing = false
    SetNuiFocus(false, false)
    detachPad()
    cb('ok')
    if wasEditing then
        -- the editor showed sample values: the real ones again
        _statusSent = {}
        compassResend = true
        HudDial.resend()
        SendNUIMessage({ action = inVehicle and 'showVehicleHud' or 'hideVehicleHud' })
        refreshHudVisibility(true)
    end
end)

--- Values from the page, kept only where they belong (a known key, the same type as its default).
local function acceptSettings(data)
    if type(data) ~= 'table' then return end
    for k, v in pairs(data) do
        local def = Config.Defaults[k]
        if settings[k] ~= nil and (def == nil or type(v) == type(def)) then settings[k] = v end
    end
end

RegisterNUICallback('saveSettings', function(data, cb)
    local old = snapshot()
    acceptSettings(data)
    saveSettings()
    applySettings(old)
    cb('ok')
end)

-- layout edit mode keeps NUI focus until the player is done (mouse drag + wheel, or the pad: D-pad moves,
-- LB/RB picks the element, triggers resize, A done, B cancel)
RegisterNUICallback('editMode', function(_, cb)
    menuOpen = false
    editing = true
    SetNuiFocus(true, true)
    attachPad()
    cb('ok')
end)

RegisterCommand('hud', openMenu, false)
RegisterKeyMapping('hud', 'Open HUD Settings', 'keyboard', Config.OpenMenu)

RegisterCommand('cinematic', function()
    local old = snapshot()
    settings.cinematicMode = not settings.cinematicMode
    saveSettings()
    applySettings(old)
end, false)
