local QBCore = exports['pfm-core']:GetCoreObject()

-- ── state ────────────────────────────────────────────────────────────
local PlayerData = {}
local loggedIn = LocalPlayer.state.isLoggedIn or false
local settings = {}

local hunger, thirst, stress = 100, 100, 0
local seatbeltOn, harnessOn, harnessHp = false, false, 0
local nitroActive, nitroLevel, nitroMax = false, 0, 0
local inVehicle = false
local menuOpen = false

-- ── settings persistence (per player, client side KVP) ───────────────
local function loadSettings()
    local merged = {}
    for k, v in pairs(Config.Defaults) do merged[k] = v end
    local saved = GetResourceKvpString('pf-hud:settings')
    if saved then
        local ok, data = pcall(json.decode, saved)
        if ok and type(data) == 'table' then
            for k, v in pairs(data) do
                if merged[k] ~= nil then merged[k] = v end
            end
        end
    end
    return merged
end

local function saveSettings()
    SetResourceKvp('pf-hud:settings', json.encode(settings))
end

-- ── minimap ──────────────────────────────────────────────────────────
local function getMinimapAnchor()
    local safezone = GetSafeZoneSize()
    local safezoneX, safezoneY = 1.0 / 20.0, 1.0 / 20.0
    local aspectRatio = GetAspectRatio(0)
    if aspectRatio > 2.0 then aspectRatio = 16 / 9 end -- triple-screen guard
    local resX, resY = GetActiveScreenResolution()
    local xscale, yscale = 1.0 / resX, 1.0 / resY
    local mm = {}
    mm.width = xscale * (resX / (4 * aspectRatio))
    mm.height = yscale * (resY / 5.674)
    mm.leftX = xscale * (resX * (safezoneX * ((math.abs(safezone - 1.0)) * 10)))
    mm.bottomY = 1.0 - yscale * (resY * (safezoneY * ((math.abs(safezone - 1.0)) * 10)))
    mm.topY = mm.bottomY - mm.height
    return mm
end

local function applyMinimap()
    local shape = settings.minimapShape
    RequestStreamedTextureDict('circlemap', false)
    RequestStreamedTextureDict('squaremap', false)
    local timeout = GetGameTimer() + 3000
    while (not HasStreamedTextureDictLoaded('circlemap') or not HasStreamedTextureDictLoaded('squaremap')) and GetGameTimer() < timeout do
        Wait(50)
    end
    if shape == 'circle' then
        SetMinimapClipType(1)
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'circlemap', 'radarmasksm')
        SetMinimapComponentPosition('minimap', 'L', 'B', -0.01, -0.025, 0.180, 0.258)
        SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.200, 0.0, 0.065, 0.20)
        SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.00, 0.015, 0.252, 0.338)
    else
        SetMinimapClipType(0)
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'squaremap', 'radarmasksm')
        SetMinimapComponentPosition('minimap', 'L', 'B', -0.0100, -0.030, 0.150, 0.188888)
        SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.0, 0.0, 0.128, 0.20)
        SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.01, 0.025, 0.262, 0.300)
    end
    SetBlipAlpha(GetNorthRadarBlip(), 0)
    SetBigmapActive(true, false)
    Wait(50)
    SetBigmapActive(false, false)
    local anchor = getMinimapAnchor()
    SendNUIMessage({
        action = 'minimap',
        shape = shape,
        anchor = { x = anchor.leftX, y = anchor.topY, w = anchor.width, h = anchor.height },
    })
end

local function setMinimapVisible(visible)
    DisplayRadar(visible)
end

-- ── push settings to UI ──────────────────────────────────────────────
local function pushSettings()
    SendNUIMessage({ action = 'settings', settings = settings, currency = Config.CurrencyText })
end

-- ── global UI theme (shared with every PF-themed interface) ──────────
exports('GetTheme', function()
    return settings.theme or Config.Defaults.theme
end)

local function broadcastTheme()
    TriggerEvent('pf-ui:themeUpdated', settings.theme or Config.Defaults.theme)
end

-- ── voice ────────────────────────────────────────────────────────────
local function isTalking()
    return NetworkIsPlayerTalking(PlayerId())
end

local function isOnRadio()
    local ok, radio = pcall(function() return LocalPlayer.state.radioActive end)
    return ok and radio or false
end

-- ── status loop ──────────────────────────────────────────────────────
local function startStatusLoop()
    CreateThread(function()
        while loggedIn do
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped) - 100
            if health < 0 then health = 0 end
            local oxygen = 100
            if IsEntityInWater(ped) then
                oxygen = (GetPlayerUnderwaterTimeRemaining(PlayerId()) * 10)
                if oxygen > 100 then oxygen = 100 end
                if oxygen < 0 then oxygen = 0 end
            else
                oxygen = -1 -- hidden when not diving
            end
            local armed = IsPedArmed(ped, 6)
            SendNUIMessage({
                action = 'status',
                show = not settings.cinematicMode,
                health = health,
                armor = GetPedArmour(ped),
                hunger = hunger,
                thirst = thirst,
                stress = stress,
                oxygen = oxygen,
                talking = isTalking(),
                radio = isOnRadio(),
                armed = armed,
                dead = IsEntityDead(ped),
            })
            Wait(Config.UpdateRates.status)
        end
        SendNUIMessage({ action = 'status', show = false })
    end)
end

-- ── vehicle loop ─────────────────────────────────────────────────────
local function getFuel(veh)
    if Config.FuelExport ~= '' and GetResourceState(Config.FuelExport) == 'started' then
        local ok, fuel = pcall(function() return exports[Config.FuelExport]:GetFuel(veh) end)
        if ok and fuel then return fuel end
    end
    return GetVehicleFuelLevel(veh)
end

local function startVehicleLoop()
    if Config.DisableCarHud then return end
    CreateThread(function()
        while loggedIn and inVehicle do
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and not IsThisModelABicycle(GetEntityModel(veh)) then
                local speedMult = settings.speedUnit == 'mph' and 2.236936 or 3.6
                SendNUIMessage({
                    action = 'vehicle',
                    show = not settings.cinematicMode,
                    speed = math.ceil(GetEntitySpeed(veh) * speedMult),
                    unit = settings.speedUnit,
                    rpm = GetVehicleCurrentRpm(veh),
                    fuel = getFuel(veh),
                    lowFuel = getFuel(veh) <= Config.LowFuelThreshold,
                    engine = GetVehicleEngineHealth(veh) / 10,
                    seatbelt = seatbeltOn or harnessOn,
                    harness = harnessOn,
                    nitroActive = nitroActive,
                    nitro = nitroMax > 0 and (nitroLevel / nitroMax * 100) or 0,
                })
            end
            Wait(Config.UpdateRates.vehicle)
        end
        SendNUIMessage({ action = 'vehicle', show = false })
    end)
end

-- ── compass loop ─────────────────────────────────────────────────────
local directions = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N' }
local function startCompassLoop()
    CreateThread(function()
        local lastStreet = ''
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
                lastStreet = street
                SendNUIMessage({
                    action = 'compass',
                    show = true,
                    heading = math.floor(heading % 360),
                    direction = dir,
                    street = street,
                })
                Wait(Config.UpdateRates.compass)
            else
                SendNUIMessage({ action = 'compass', show = false })
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
                seatbeltOn = false
                setMinimapVisible(true)
                startVehicleLoop()
            elseif not nowIn and inVehicle then
                inVehicle = false
                seatbeltOn = false
                setMinimapVisible(settings.minimapOnFoot)
            elseif not nowIn then
                setMinimapVisible(settings.minimapOnFoot and not settings.cinematicMode)
            end
            Wait(400)
        end
    end)
end

-- ── stress mechanics (shooting / speeding) ───────────────────────────
local function startStressLoops()
    if not Config.StressEnabled then return end
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
    DisplayRadar(not settings.cinematicMode and (inVehicle or settings.minimapOnFoot))
end

-- ── boot / teardown ──────────────────────────────────────────────────
local function startHud()
    settings = loadSettings()
    pushSettings()
    broadcastTheme()
    applyMinimap()
    setMinimapVisible(settings.minimapOnFoot)
    startStatusLoop()
    startVehicleWatcher()
    startCompassLoop()
    startStressLoops()
    applyCinematic()
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
    SendNUIMessage({ action = 'status', show = false })
    SendNUIMessage({ action = 'vehicle', show = false })
    SendNUIMessage({ action = 'compass', show = false })
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
RegisterNetEvent('hud:client:LoadMap', function() applyMinimap() end)
RegisterNetEvent('hud:client:UpdateUISettings', function() end)
RegisterNetEvent('hud:client:EngineHealth', function() end)
RegisterNetEvent('hud:client:ToggleAirHud', function() end)
RegisterNetEvent('hud:client:BuffEffect', function() end)
RegisterNetEvent('hud:client:EnhancementEffect', function() end)

-- ── settings menu ────────────────────────────────────────────────────
local function openMenu()
    if not loggedIn or menuOpen then return end
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openMenu', settings = settings })
end

RegisterNUICallback('closeMenu', function(_, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('saveSettings', function(data, cb)
    local oldShape = settings.minimapShape
    for k, v in pairs(data) do
        if settings[k] ~= nil then settings[k] = v end
    end
    saveSettings()
    pushSettings()
    broadcastTheme()
    if settings.minimapShape ~= oldShape then applyMinimap() end
    setMinimapVisible(not settings.cinematicMode and (inVehicle or settings.minimapOnFoot))
    applyCinematic()
    cb('ok')
end)

-- layout edit mode keeps NUI focus until the player clicks Done
RegisterNUICallback('editMode', function(_, cb)
    menuOpen = false
    SetNuiFocus(true, true)
    cb('ok')
end)

RegisterCommand('hud', openMenu, false)
RegisterKeyMapping('hud', 'Open HUD Settings', 'keyboard', Config.OpenMenu)

RegisterCommand('cinematic', function()
    settings.cinematicMode = not settings.cinematicMode
    saveSettings()
    pushSettings()
    applyCinematic()
end, false)
