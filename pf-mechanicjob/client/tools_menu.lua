local QBCore = exports['pfm-core']:GetCoreObject()
if Config and Config.Debug then print('[TOOLS_MENU] Client script loaded') end

-- SAFE FALLBACK: hasToolbox (accept toolbox OR mechanic_tools)
if type(hasToolbox) ~= 'function' then
    function hasToolbox(cb)
        local function ok()
            cb(true)
        end
        local function fail()
            QBCore.Functions.Notify(L and L('need_toolbox') or 'You need a toolbox to do mechanic work', 'error')
            cb(false)
        end
        if QBCore and QBCore.Functions and QBCore.Functions.TriggerCallback then
            -- First check toolbox
            QBCore.Functions.TriggerCallback('QBCore:HasItem', function(hasTool)
                if hasTool then ok(); return end
                -- Then check mechanic_tools as an alternative
                QBCore.Functions.TriggerCallback('QBCore:HasItem', function(hasAlt)
                    if hasAlt then ok() else fail() end
                end, 'mechanic_tools')
            end, 'toolbox')
        else
            ok()
        end
    end
end

-- ADD: door helpers (must be before usage)
local function OpenAllDoors(veh)
    if not veh or not DoesEntityExist(veh) then return end
    for i=0,5 do SetVehicleDoorOpen(veh, i, false, false) end
end
local function CloseAllDoors(veh)
    if not veh or not DoesEntityExist(veh) then return end
    for i=0,5 do SetVehicleDoorShut(veh, i, false) end
end

-- ADD: welding helpers and state (HOISTED so StartWeld exists before being called)
local MENU_OPEN = false
local currentWelderProp, currentWeldFx
local remoteWeldFx = {}

local function LoadModel(hash)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end
end
local function LoadPtfx(dict)
    RequestNamedPtfxAsset(dict)
    while not HasNamedPtfxAssetLoaded(dict) do Wait(0) end
end
local function NetWaitEntityFromNet(netId, tries, waitMs)
    local ent
    for i=1,(tries or 40) do
        ent = NetworkGetEntityFromNetworkId(netId or 0)
        if ent ~= 0 and DoesEntityExist(ent) then return ent end
        Wait(waitMs or 25)
    end
    return 0
end

-- Cleanup helper for clipboard/notepad animation + prop (hoisted)
local function CleanupClipboard()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    if currentClipboard and DoesEntityExist(currentClipboard) then
        DeleteEntity(currentClipboard)
        currentClipboard = nil
    end
end

local function StartWeld(ped)
    local model = `prop_weld_torch`
    LoadModel(model)

    -- Create a fully networked prop so other clients receive it
    local prop = CreateObject(model, 0.0, 0.0, 0.0, true, true, true)
    SetEntityAsMissionEntity(prop, true, true)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005), 0.12, 0.02, -0.02, -20.0, 180.0, 10.0, true, true, false, true, 1, true)

    local netId = NetworkGetNetworkIdFromEntity(prop)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)

    -- Local looped sparks
    LoadPtfx('core'); UseParticleFxAssetNextCall('core')
    local fx = StartParticleFxLoopedOnEntity('ent_sparks', prop, 0.02, 0.02, 0.0, 0.0, 0.0, 0.0, 1.2, false, false, false)

    currentWelderProp = prop
    currentWeldFx = fx

    -- Relay to everyone
    TriggerServerEvent('pf_mech:weld:start', netId)
end

local function StopWeld()
    -- Relay first (so remotes stop their fx even if delete lags)
    local netId = currentWelderProp and NetworkGetNetworkIdFromEntity(currentWelderProp) or 0
    if netId and netId ~= 0 then
        TriggerServerEvent('pf_mech:weld:stop', netId)
    end

    if currentWeldFx then
        pcall(function() StopParticleFxLooped(currentWeldFx, true) end)
        currentWeldFx = nil
    end
    if currentWelderProp and DoesEntityExist(currentWelderProp) then
        DeleteEntity(currentWelderProp)
    end
    currentWelderProp = nil
end

-- Sync welding sparks on other clients, if any
RegisterNetEvent('pf_mech:weld:start', function(netId)
    local ent = NetWaitEntityFromNet(netId, 60, 25)
    if ent == 0 then return end
    LoadPtfx('core'); UseParticleFxAssetNextCall('core')
    remoteWeldFx[netId] = StartParticleFxLoopedOnEntity('ent_sparks', ent, 0.02, 0.02, 0.0, 0.0, 0.0, 0.0, 1.2, false, false, false)
end)
RegisterNetEvent('pf_mech:weld:stop', function(netId)
    local fx = remoteWeldFx[netId]
    if fx then
        pcall(function() StopParticleFxLooped(fx, true) end)
        remoteWeldFx[netId] = nil
    end
end)

-- UNCONDITIONAL EARLY EXPORTS (avoid race / conditional export lookup)
-- Internal calls can just use GetCurrentDiagnostics() directly.
local function GetCurrentDiagnosticsInternal(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local st = Entity(veh).state or {}
    local partDamage = st.partDamage or {}
    return {
        partDamage = partDamage,
        mileage = tonumber(st.mileage) or 0,
        engineHealth = GetVehicleEngineHealth(veh),
        bodyHealth = GetVehicleBodyHealth(veh),
        tankHealth = GetVehiclePetrolTankHealth(veh),
        dirtLevel = GetVehicleDirtLevel(veh)
    }
end
function GetCurrentDiagnostics(veh) return GetCurrentDiagnosticsInternal(veh) end
exports('GetCurrentDiagnostics', GetCurrentDiagnosticsInternal)

-- Simple wheel steps mini-sequence (fix loop)
local function DoWheelStepsInternal()
    local ped = PlayerPedId()
    RequestAnimDict('mini@repair')
    while not HasAnimDictLoaded('mini@repair') do Wait(0) end
    local seq = {
        { 'Loosening lugs...', 1100 },
        { 'Removing wheel...', 1100 },
        { 'Fitting new wheel...', 1300 },
    }
    if QBCore.Functions.Progressbar then
        for i,s in ipairs(seq) do
            local done = false
            QBCore.Functions.Progressbar('pf_wheel_'..i, s[1], s[2], false, true, { disableMovement=true, disableCarMovement=true, disableCombat=true },
                { animDict='mini@repair', anim='fixing_a_ped', flags=49 }, {}, {},
                function() done=true end, function() done=true end)
            while not done do Wait(10) end
        end
    else
        for _,s in ipairs(seq) do Wait(s[2]) end
    end
    ClearPedTasks(ped)
    return true
end
exports('DoWheelSteps', DoWheelStepsInternal)

-- =========================================================
-- MISSING HELPER FUNCTIONS (moved from main.lua)
-- =========================================================
function getRepairVehicle()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and DoesEntityExist(veh) then return veh end
    end
    local coords = GetEntityCoords(ped)
    local veh = GetClosestVehicle(coords.x, coords.y, coords.z, 6.0, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
    return nil
end

function ensureControl(entity, timeoutMs)
    if not entity or entity == 0 then return false end
    local start = GetGameTimer()
    while not NetworkHasControlOfEntity(entity) and (GetGameTimer() - start) < (timeoutMs or 700) do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

function doMechanicAction(label, ms)
    if QBCore.Functions.Progressbar then
        QBCore.Functions.Progressbar('pf_mech_repair', label or 'Working...', ms or 2000, false, true, {
            disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
        }, {
            animDict = 'mini@repair', anim = 'fixing_a_ped', flags = 49,
        }, {}, {}, function() end, function() end)
    else
        Wait(ms or 2000)
    end
end

-- =========================================================
-- SIMPLE WHEEL DAMAGE DETECTION (VANILLA BURST ONLY)
-- =========================================================
-- REPLACE: robust probe-based wheel index detection (fix ok2 var)
local function GetWheelIndices(veh)
    if not veh or not DoesEntityExist(veh) then return {0,1,2,3} end
    local candidates = {0,1,2,3,4,5}
    local out = {}
    for _, idx in ipairs(candidates) do
        local exists = false
        local ok, val = pcall(function() return GetVehicleTyreHealth(veh, idx) end)
        if ok and val ~= nil then
            exists = true
        else
            local ok2 = pcall(function() return IsVehicleTyreBurst(veh, idx, false) end)
            if ok2 then exists = true end
        end
        if exists then out[#out+1] = idx end
    end
    if #out == 0 then out = {0,1,2,3} end
    return out
end

-- Simple burst check PLUS health fallback (rear wheels sometimes report health but not burst)
function IsWheelDamaged(veh, idx)
    if not veh or not DoesEntityExist(veh) then return false end
    local burst = false
    pcall(function()
        burst = IsVehicleTyreBurst(veh, idx, false) or IsVehicleTyreBurst(veh, idx, true)
    end)
    if burst then return true end
    -- Fallback: some tyres (often rear) keep health but are functionally "damaged"
    local health = 100.0
    pcall(function()
        health = GetVehicleTyreHealth(veh, idx) or 100.0
    end)
    return health < 50.0
end

PF_IsWheelDamaged = IsWheelDamaged
exports('IsWheelDamaged', function(veh, idx) return IsWheelDamaged(veh, idx) end)

-- Helper: Get vehicle damage
local function getVehicleDamage(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local state = Entity(veh)
    if not state or not state.state then return nil end
    local damage = state.state.partDamage or {}
    damage.brakes = damage.brakes or 0
    damage.fuel_injector = damage.fuel_injector or 0
    damage.powersteeringpump = damage.powersteeringpump or 0
    damage.radiator = damage.radiator or 0
    damage.power_steering_fluid = damage.power_steering_fluid or 0
    damage.transmissionfluid = damage.transmissionfluid or 0
    damage.brakefluid = damage.brakefluid or 0
    damage.coolant = damage.coolant or 0
    damage.alternator = damage.alternator or 0
    damage.sparkplugs = damage.sparkplugs or 0
    damage.carbattery = damage.carbattery or 0
    damage.oil = damage.oil or 0             -- make sure oil key always present
    damage.oil_filter = damage.oil_filter or 0
    damage.brakes = damage.brakes or 0
    damage.suspension = damage.suspension or 0
    damage.axle = damage.axle or 0
    return damage
end

-- Helper: request control before mutating entity state
function ensureControl(entity, timeoutMs)
    if not entity or entity == 0 then return false end
    local start = GetGameTimer()
    while not NetworkHasControlOfEntity(entity) and (GetGameTimer() - start) < (timeoutMs or 700) do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

-- Helper: progress bar helper
function doMechanicAction(label, ms)
    if QBCore.Functions.Progressbar then
        QBCore.Functions.Progressbar('pf_mech_repair', label or 'Working...', ms or 2000, false, true, {
            disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
        }, {
            animDict = 'mini@repair', anim = 'fixing_a_ped', flags = 49,
        }, {}, {}, function() end, function() end)
    else
        Wait(ms or 2000)
    end
end

-- Local blocking progress with success/cancel return
local function DoProgress(label, ms, dict, anim)
    local ok, canceled = false, false
    local ped = PlayerPedId()
    local ad = dict or 'mini@repair'
    local an = anim or 'fixing_a_ped'
    RequestAnimDict(ad) while not HasAnimDictLoaded(ad) do Wait(0) end
    if QBCore.Functions.Progressbar then
        QBCore.Functions.Progressbar('pf_mech_repair_block', label or 'Working...', ms or 2000, false, true, {
            disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
        }, {
            animDict = ad, anim = an, flags = 49,
        }, {}, {}, function() ok = true end, function() canceled = true end)
        while (not ok and not canceled) do Wait(10) end
    else
        TaskPlayAnim(ped, ad, an, 8.0, -8.0, ms or 2000, 49, 0, false, false, false)
        Wait(ms or 2000)
        ok = true
    end
    ClearPedTasks(ped)
    return ok and not canceled
end

-- Helper: Calculate parts needed for repair
local function partsNeededForRepair(partKey, healthPercent)
    local rule = (Config.PartRules or {})[partKey] or {}
    local maxItems = tonumber(rule.max_items) or 0

    if maxItems <= 0 then
        if partKey:match('engine') or rule.type == 'engine' then maxItems = 5 end
        if partKey == 'body_part' or rule.type == 'body' then maxItems = 5 end
        if partKey == 'sparkplugs' or rule.type == 'sparkplugs' then maxItems = 8 end
        if rule.type == 'battery' then maxItems = 1 end
        if rule.type == 'axle' then maxItems = 4 end
        if partKey == 'tire_new' then maxItems = 4 end
        if rule.type == 'oil' or partKey == 'engine_oil' then maxItems = 1 end
        if rule.type == 'oil_filter' or partKey == 'oil_filter' then maxItems = 1 end
        if partKey == 'brakes' then maxItems = 4 end
        if partKey == 'fuel_injector' then maxItems = 4 end
        if partKey == 'powersteeringpump' then maxItems = 1 end
        if partKey == 'radiator' then maxItems = 1 end
        if partKey == 'power_steering_fluid' then maxItems = 1 end
        if partKey == 'transmissionfluid' then maxItems = 1 end
        if partKey == 'brakefluid' then maxItems = 1 end
        if partKey == 'coolant' then maxItems = 1 end
    end

    healthPercent = math.max(0, math.min(100, tonumber(healthPercent) or 0))

    if maxItems <= 0 then return 0 end
    local missingPercent = 100 - healthPercent
    -- Use ceiling so any damage > 0 requires at least 1 item for single-item parts
    local needed = math.ceil((missingPercent / 100) * maxItems)
    return math.max(0, math.min(needed, maxItems))
end

local DiagnosticLabels = {
    alternator = "Alternator",
    sparkplugs = "Spark Plugs",
    carbattery = "Car Battery",
    engine_oil = "Engine Oil",
    oil_filter = "Oil Filter",
    brakes = "Brake Pads",
    susp_arm = "Suspension Arm",
    axleparts = "Axle Parts",
    engine_part = "Engine Part",
    body_part = "Body Panel",
    tire_new = "Tire",
    fuel_injector = "Fuel Injector",
    powersteeringpump = "Power Steering Pump",
    radiator = "Radiator",
    power_steering_fluid = "Power Steering Fluid",
    transmissionfluid = "Transmission Fluid",
    brakefluid = "Brake Fluid",
    coolant = "Coolant"
}

-- Action duration helper (mirror of client/main.lua)
local function timeForAction(action)
    local t = {
        engine = 5500,
        body = 4500,
        brakes = 3500,
        tire = 3000,
        oil = 2500,
        battery = 2500,
    }
    return t[action] or 4000
end

-- NEW: Map part keys to item image filenames (kept, but we will prefer inventory images)
local DiagnosticImages = {
    alternator = 'alternator.png',
    sparkplugs = 'sparkplugs.png',
    carbattery = 'carbattery.png',
    engine_oil = 'engine_oil.png',
    oil_filter = 'oil_filter.png',
    brakes = 'brake_pads.png',
    susp_arm = 'susp_arm.png',
    axleparts = 'axleparts.png',
    engine_part = 'engine_part.png',
    body_part = 'body_part.png',
    tire_new = 'tire_new.png',
    fuel_injector = 'fuel_injector.png',
    powersteeringpump = 'powersteeringpump.png',
    radiator = 'radiator.png',
    power_steering_fluid = 'power_steering_fluid.png',
    transmissionfluid = 'transmissionfluid.png',
    brakefluid = 'brakefluid.png',
    coolant = 'coolant.png'
}

-- NEW: Resolve images from the active inventory UI (qb-inventory / lj-inventory / ox_inventory)
local function resourceStarted(name)
    local st = GetResourceState(name)
    return st == 'started' or st == 'starting'
end
local function getInventoryImageBase()
    if resourceStarted('ox_inventory') then
        return 'nui://ox_inventory/web/images/'
    elseif resourceStarted('qb-inventory') then
        return 'nui://pfm-inventory/html/images/'
    elseif resourceStarted('lj-inventory') then
        return 'nui://lj-inventory/html/images/'
    else
        -- fallback to qb-inventory structure
        return 'nui://pfm-inventory/html/images/'
    end
end
local INVENTORY_IMAGE_BASE = getInventoryImageBase()
local FALLBACK_IMAGE_BASE = 'nui://pf-mechanicjob/html/img/'
local DEFAULT_PLACEHOLDER = FALLBACK_IMAGE_BASE .. 'placeholder.png'

-- Map partKey -> inventory item name (defaults to same key)
local PartToItemName = {
    alternator='alternator',
    sparkplugs='sparkplugs',
    carbattery='carbattery',
    engine_oil='engine_oil',
    oil_filter='oil_filter',
    brakes='brake_pads',
    susp_arm='susp_arm',
    axleparts='axleparts',
    engine_part='engine_part',
    body_part='body_part',
    tire_new='tire_new',
    fuel_injector='fuel_injector',
    powersteeringpump='powersteeringpump',
    radiator='radiator',
    power_steering_fluid='power_steering_fluid',
    transmissionfluid='transmissionfluid',
    brakefluid='brakefluid',
    coolant='coolant',
}

-- OPTIONAL: inject simple CSS once to enlarge qb-menu icons (only if qb-menu listens for custom action)
local qbMenuCssInjected = false
local function InjectQbMenuIconCSS()
    if qbMenuCssInjected then return end
    qbMenuCssInjected = true
    SendNUIMessage({
        action = 'pf_mech_inject_css',
        css = '.qb-menu-item img, .qb-menu-item-icon img { width:42px !important; height:42px !important; object-fit:contain }'
    })
end

-- FIX getMenuIcon (compute fname)
local function getMenuIcon(partKey)
    partKey = tostring(partKey or '')
    local itemName = (PartToItemName and PartToItemName[partKey]) or partKey
    if QBCore and QBCore.Shared and QBCore.Shared.Items then
        local itm = QBCore.Shared.Items[itemName]
        if itm and itm.image then
            local fname = itm.image:match('%.') and itm.image or (itm.image .. '.png')
            return INVENTORY_IMAGE_BASE .. fname
        end
    end
    local mapped = DiagnosticImages[partKey]
    if mapped then return INVENTORY_IMAGE_BASE .. mapped end
    if mapped then return FALLBACK_IMAGE_BASE .. mapped end
    return DEFAULT_PLACEHOLDER
end

-- FIX: OpenMenuGeneric (populate ox_lib options) + ESC cleanup guard for qb-menu
local function OpenMenuGeneric(menu)
    local useOx = (Config and Config.MenuSystem == 'ox_lib')
    if useOx and resourceStarted('ox_lib') and lib and lib.registerContext then
        local contextId = 'pf_mech_diag_' .. GetGameTimer()
        local title, options = 'Diagnostics', {}
        for _, item in ipairs(menu) do
            if item.isMenuHeader then
                if item.header then title = item.header end
            else
                local hasEvent = (item.params and item.params.event)
                options[#options+1] = {
                    title = item.header or '',
                    description = item.txt or '',
                    icon = item.icon,
                    disabled = not hasEvent,
                    onSelect = function()
                        if hasEvent then
                            TriggerEvent(item.params.event, item.params.args)
                        end
                    end
                }
            end
        end
        lib.registerContext({ id=contextId, title=title, options=options })
        lib.showContext(contextId)
    else
        if exports['pfm-menu'] and exports['pfm-menu'].openMenu then
            MENU_OPEN = true
            -- watch ESC to ensure cleanup if qb-menu doesn't emit close
            CreateThread(function()
                while MENU_OPEN do
                    Wait(0)
                    if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 200) then
                        TriggerEvent('qb-menu:client:closeMenu')
                        MENU_OPEN = false
                    end
                end
            end)
            exports['pfm-menu']:openMenu(menu)
        else
            QBCore.Functions.Notify('Menu system not found', 'error')
        end
    end
end

-- FIX: inspection progressbar handler (open/close doors + welder prop)
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu', function()
    if Config.Debug then print('[TOOLS_MENU] openToolsMenu event received') end
    local veh = getRepairVehicle()
    if not veh then
        QBCore.Functions.Notify('No vehicle nearby','error')
        if Config.Debug then print('[TOOLS_MENU] Abort: no vehicle') end
        return
    end
    
    local ped = PlayerPedId()

    local weldDict, weldAnim = "amb@world_human_welding@male@base", "base"
    RequestAnimDict(weldDict) while not HasAnimDictLoaded(weldDict) do Wait(0) end

    OpenAllDoors(veh)
    TaskPlayAnim(ped, weldDict, weldAnim, 8.0, -8.0, -1, 49, 0, false, false, false)
    StartWeld(ped)

    -- Fallback: if no progressbar, still open the menu
    if not QBCore.Functions.Progressbar then
        Wait(1500)
        ClearPedTasks(ped)
        StopWeld()
        CloseAllDoors(veh)
        -- CHANGED: Open diagnostics menu (not mechanic tools)
        TriggerEvent('pf-mechanicjob:client:openToolsMenu:showMenu', veh)
        return
    end

    QBCore.Functions.Progressbar('inspect_vehicle','Inspecting vehicle...',10000,false,true,
        { disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true },
        { animDict=weldDict, anim=weldAnim, flags=49 }, {}, {},
        function()
            ClearPedTasks(ped)
            StopWeld()
            CloseAllDoors(veh)
            local clipDict, clipAnim, clipProp = "missheistdockssetup1clipboard@base", "base", `prop_notepad_01`
            RequestAnimDict(clipDict) while not HasAnimDictLoaded(clipDict) do Wait(0) end
            RequestModel(clipProp) while not HasModelLoaded(clipProp) do Wait(0) end
            currentClipboard = CreateObject(clipProp, 0,0,0,true,true,false)
            AttachEntityToEntity(currentClipboard, ped, GetPedBoneIndex(ped,18905), 0.1,0.02,0.05, -50.0,90.0,0.0, true,true,false,true,1,true)
            TaskPlayAnim(ped, clipDict, clipAnim, 8.0, -8.0, -1, 50, 0, false, false, false)
            
            -- CHANGED: Open diagnostics health menu (not unified mechanic tools)
            TriggerEvent('pf-mechanicjob:client:openToolsMenu:showMenu', veh)
        end,
        function()
            ClearPedTasks(ped)
            StopWeld()
            CloseAllDoors(veh)
            if currentClipboard then DeleteEntity(currentClipboard) currentClipboard=nil end
            QBCore.Functions.Notify('Inspection cancelled','error')
        end
    )
end)

-- Direct fallback (manual menu open without inspection) for debugging
RegisterNetEvent('pf_mechanicjob:client:openToolsMenu:direct', function()
    local veh = getRepairVehicle()
    if not veh then QBCore.Functions.Notify('No vehicle nearby','error'); return end
    if Config.Debug then print('[TOOLS_MENU] Direct menu open fallback') end
    TriggerEvent('pf-mechanicjob:client:openToolsMenu:showMenu', veh)
end)

-- Allow server diagnostics useable to open our diagnostics directly
RegisterNetEvent('pf-mechanicjob:client:openDiagnosticsDirect', function()
    TriggerEvent('pf-mechanicjob:client:openToolsMenu')
end)

-- REPLACE: diagnostics menu build (fill placeholders)
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu:showMenu', function(veh)
    if not DoesEntityExist(veh) then QBCore.Functions.Notify('Vehicle not found', 'error'); return end

    local engineHealth = math.floor((GetVehicleEngineHealth(veh) or 0) / 10)
    local bodyHealth   = math.floor((GetVehicleBodyHealth(veh) or 0) / 10)
    local tankHealth   = math.floor((GetVehiclePetrolTankHealth(veh) or 0) / 10)

    local function formatMiles(mi)
        mi = tonumber(mi) or 0
        local s = string.format('%.1f', mi)
        local int, dec = s:match('^(%d+)%.(%d+)$')
        int = int:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,','')
        return int .. '.' .. dec
    end
    local st = Entity(veh).state
    local mileageMi = formatMiles(st and st.mileage or 0)

    local damage = (Entity(veh).state.partDamage or {})
    local plate = GetVehicleNumberPlateText(veh) or 'Unknown'
    local menu = {
        { header='Vehicle Diagnostics', txt=('%s • Mileage: %s mi'):format(plate, mileageMi), isMenuHeader=true },
        { header='Overall Condition', txt=('Engine %d%% • Body %d%% • Tank %d%%'):format(engineHealth, bodyHealth, tankHealth), isMenuHeader=true },
    }

    local activeWO = exports['pf-mechanicjob'] and exports['pf-mechanicjob']:GetActiveWorkOrder()

    local function getWorkOrderTargetPart(order)
        if not order then return nil end

        local itemMap = {
            tire_new = 'tire_new',
            carbattery = 'carbattery',
            engine_oil = 'engine_oil',
            brake_pads = 'brakes',
            sparkplugs = 'sparkplugs',
            coolant = 'coolant',
            transmissionfluid = 'transmissionfluid',
            engine_part = 'engine_part',
            body_part = 'body_part',
            susp_arm = 'susp_arm',
            axleparts = 'axleparts'
        }

        local typeMap = {
            tire = 'tire_new',
            battery = 'carbattery',
            oil = 'engine_oil',
            brakes = 'brakes',
            sparkplugs = 'sparkplugs',
            coolant = 'coolant',
            transmission = 'transmissionfluid',
            engine = 'engine_part',
            suspension = 'susp_arm',
            body = 'body_part',
            diagnostics = 'engine_part'
        }

        if order.requiredItem and itemMap[order.requiredItem] then
            return itemMap[order.requiredItem]
        end

        return typeMap[order.repairType]
    end

    local targetWorkOrderPart = nil
    if activeWO and DoesEntityExist(activeWO.vehicle) and activeWO.vehicle == veh then
        targetWorkOrderPart = getWorkOrderTargetPart(activeWO)
    end
    local function calcHealth(d) return math.max(0, 100 - (tonumber(d) or 0)) end
    local partMap = {
        { key='engine_part', label=DiagnosticLabels.engine_part or 'Engine', hp=engineHealth },
        { key='body_part', label=DiagnosticLabels.body_part or 'Body', hp=bodyHealth },
        { key='alternator', label=DiagnosticLabels.alternator, hp=calcHealth(damage.alternator) },
        { key='carbattery', label=DiagnosticLabels.carbattery, hp=calcHealth(damage.carbattery) },
        { key='sparkplugs', label=DiagnosticLabels.sparkplugs, hp=calcHealth(damage.sparkplugs) },
        { key='engine_oil', label=DiagnosticLabels.engine_oil, hp=calcHealth(damage.oil) },
        { key='oil_filter', label=DiagnosticLabels.oil_filter, hp=calcHealth(damage.oil_filter) },
        { key='brakes', label=DiagnosticLabels.brakes, hp=calcHealth(damage.brakes) },
        { key='susp_arm', label=DiagnosticLabels.susp_arm, hp=calcHealth(damage.suspension) },
        { key='axleparts', label=DiagnosticLabels.axleparts, hp=calcHealth(damage.axle) },
        { key='fuel_injector', label=DiagnosticLabels.fuel_injector, hp=calcHealth(damage.fuel_injector) },
        { key='powersteeringpump', label=DiagnosticLabels.powersteeringpump, hp=calcHealth(damage.powersteeringpump) },
        { key='radiator', label=DiagnosticLabels.radiator, hp=calcHealth(damage.radiator) },
        { key='power_steering_fluid', label=DiagnosticLabels.power_steering_fluid, hp=calcHealth(damage.power_steering_fluid) },
        { key='transmissionfluid', label=DiagnosticLabels.transmissionfluid, hp=calcHealth(damage.transmissionfluid) },
        { key='brakefluid', label=DiagnosticLabels.brakefluid, hp=calcHealth(damage.brakefluid) },
        { key='coolant', label=DiagnosticLabels.coolant, hp=calcHealth(damage.coolant) },
    }
    local function partsNeededForRepairLocal(partKey, healthPercent)
        return partsNeededForRepair(partKey, healthPercent)
    end
    local function addPartEntry(p)
        local hp = math.min(100, math.max(0, tonumber(p.hp) or 0))
        local hpInt = math.floor(hp + 0.5)
        -- Allow repair even at 99% health (1 item top-off)
        local needed = (hpInt >= 100) and 0 or math.max(1, partsNeededForRepairLocal(p.key, hpInt))
        local txt
        if hpInt >= 100 then
            txt = 'Perfect condition'
        elseif hpInt >= 99 then
            txt = 'Top-off: 1 part'
        else
            txt = ('Needs: %d parts'):format(needed)
        end

        if targetWorkOrderPart and p.key == targetWorkOrderPart then
            txt = ('Work order target • %s'):format(txt)
        end

        menu[#menu+1] = {
            header = ('%s — %d%%'):format(p.label or p.key, hpInt),
            txt = txt,
            icon = getMenuIcon(p.key),
            params = (hpInt < 100) and {
                event = 'pf-mechanicjob:client:openRepairSuggest',
                args = { vehicle = veh, part = p.key, needed = needed }
            } or {}
        }
    end
    for _,p in ipairs(partMap) do addPartEntry(p) end

    -- Tires
    local idxs = GetWheelIndices(veh)
    local function has(i) for _,v in ipairs(idxs) do if v == i then return true end end return false end
    local names = { [0]='Front Left',[1]='Front Right' }
    local has23 = has(2) or has(3)
    local has45 = has(4) or has(5)
    if has23 and has45 then
        names[2]='Middle Left'; names[3]='Middle Right'; names[4]='Rear Left'; names[5]='Rear Right'
    elseif has23 then
        names[2]='Rear Left'; names[3]='Rear Right'
    elseif has45 then
        names[4]='Rear Left'; names[5]='Rear Right'
    end
    local damagedCount, healthyCount = 0,0
    for _, i in ipairs(idxs) do
        local damaged = IsWheelDamaged(veh, i)
        if damaged then
            damagedCount = damagedCount + 1
            menu[#menu+1] = {
                header = ('Tire %s — Damaged'):format(names[i] or tostring(i)),
                txt = 'Replace (needs 1 tire)',
                icon = getMenuIcon('tire_new'),
                params = {
                    event = 'pf-mechanicjob:client:repairTireWheel',
                    args = { vehicle = veh, wheel = i }
                }
            }
        else
            healthyCount = healthyCount + 1
        end
    end
    if damagedCount == 0 then
        menu[#menu+1] = { header = 'Tires — 100%', txt = 'All tires OK', icon = getMenuIcon('tire_new'), params = {} }
    end

    if Config.MenuSystem ~= 'ox_lib' then
        menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
    end
    OpenMenuGeneric(menu)
end)

-- Helper: reopen diagnostics menu without inspection progressbar
local function ReopenDiagnosticsMenu(veh)
    if veh and DoesEntityExist(veh) then
        TriggerEvent('pf-mechanicjob:client:openToolsMenu:showMenu', veh)
    end
end

local function GetPartDamageValue(veh, partKey)
    local st = Entity(veh).state or {}
    local d = st.partDamage or {}
    if partKey == 'engine_oil' then return tonumber(d.oil) or 0 end
    if partKey == 'susp_arm' then return tonumber(d.suspension) or 0 end
    if partKey == 'axleparts' then return tonumber(d.axle) or 0 end
    return tonumber(d[partKey]) or 0
end

-- Suggest -> Confirm -> Perform repair (simplified: go straight to repair)
RegisterNetEvent('pf-mechanicjob:client:openRepairSuggest', function(data)
    if type(data) ~= 'table' then return end
    local veh = tonumber(data.vehicle) or data.vehicle or getRepairVehicle()
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        veh = getRepairVehicle()
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found','error')
        return
    end

    if not data.part or tostring(data.part) == '' then
        QBCore.Functions.Notify('Invalid repair target', 'error')
        return
    end

    -- Directly invoke the repair flow (you can replace with a confirm dialog if desired)
    TriggerEvent('pf-mechanicjob:client:doRepairWithItems', {
        vehicle = veh,
        part = data.part,
        needed = data.needed,
        wheel = data.wheel,
        progTime = data.progTime
    })
end)

-- Wheel repair (burst or detached) - NO TOOLBOX REQUIRED (diagnostics flow)
RegisterNetEvent('pf-mechanicjob:client:repairTireWheel', function(data)
    local veh   = data and data.vehicle or getRepairVehicle()
    local wheel = data and tonumber(data.wheel or -1) or -1
    if not veh or veh == 0 or not DoesEntityExist(veh) then QBCore.Functions.Notify('Vehicle not found','error'); return end

    local valid=false
    for _,idx in ipairs(GetWheelIndices(veh)) do if idx == wheel then valid=true break end end
    if not valid then QBCore.Functions.Notify('Invalid wheel index','error'); return end

    if not ensureControl(veh) then QBCore.Functions.Notify('Cannot get control','error'); return end
    if not IsWheelDamaged(veh, wheel) then
        QBCore.Functions.Notify('Wheel not damaged','error')
        return
    end

    -- Check for tire item and consume
    QBCore.Functions.TriggerCallback('pf-mechanicjob:server:consumeItem', function(ok)
        if not ok then QBCore.Functions.Notify('Missing tire','error'); return end

        if not DoProgress('Replacing tire...', 4000, 'mini@repair', 'fixing_a_ped') then
            QBCore.Functions.Notify('Repair cancelled', 'error')
            return
        end

        SetVehicleTyreFixed(veh, wheel)
        Wait(120)

        if IsWheelDamaged(veh, wheel) then
            Wait(150)
        end

        if IsWheelDamaged(veh, wheel) then
            Wait(200)
        end

        if IsWheelDamaged(veh, wheel) then
            return
        end

        -- the server marks the tyre new (partDamage is server-set, sv_stateBagStrictMode)
        TriggerServerEvent('pf_mech:server:tireReplaced', NetworkGetNetworkIdFromEntity(veh), wheel)

        QBCore.Functions.Notify('Tire replaced', 'success')
        ReopenDiagnosticsMenu(veh)
    end, 'tire_new')
end)

-- Apply part effects from server broadcast (visual/health side)
RegisterNetEvent('pf_mech:applyPart', function(payload)
    if type(payload) ~= 'table' then return end
    local netId = payload.net
    local veh = NetworkGetEntityFromNetworkId(netId or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local qty = tonumber(payload.qty or 1) or 1
    local actionType = tostring(payload.type or '')

    if actionType == 'engine' then
        -- Restore engine to full health (diagnostics calculated correct parts)
        SetVehicleEngineHealth(veh, 1000.0)
    elseif actionType == 'body' then
        -- Restore body to full health (diagnostics calculated correct parts)
        SetVehicleBodyHealth(veh, 1000.0)
        -- Capture engine health to restore it after SetVehicleFixed
        local engineHealth = GetVehicleEngineHealth(veh)
        -- Use SetVehicleFixed to fully repair body deformation visually
        SetVehicleFixed(veh)
        -- Restore original engine health (SetVehicleFixed repairs engine too)
        SetVehicleEngineHealth(veh, engineHealth)
    elseif actionType == 'brakes' then
        -- Ask damage system to reset brake cache so handling restores
        TriggerEvent('pf_mech:client:resetBrakeCache', netId)
    end

    if payload.toast then
        QBCore.Functions.Notify(payload.toast, 'success')
    end
end)

-- New handler: perform progress then call server to consume items & apply repair
RegisterNetEvent('pf-mechanicjob:client:doRepairWithItems', function(data)
    local vehicle = tonumber(data.vehicle) or data.vehicle
    local part = data.part
    local needed = tonumber(data.needed) or 1
    local wheel = data.wheel
    local progTime = tonumber(data.progTime) or timeForAction('engine')

    if not DoesEntityExist(vehicle) then
        QBCore.Functions.Notify('Vehicle not found', 'error'); return
    end

    -- No toolbox required for diagnostics-based repairs; proceed directly

    -- Resolve item label from DiagnosticLabels or QBCore.Shared.Items
    local partLabel = DiagnosticLabels[part] or part:gsub('_', ' ')
    if QBCore.Shared.Items[part] and QBCore.Shared.Items[part].label then
        partLabel = QBCore.Shared.Items[part].label
    end

    -- Run progress; if cancelled, abort
    if not DoProgress('Repairing '..partLabel..'...', progTime, 'mini@repair', 'fixing_a_ped') then
        QBCore.Functions.Notify('Repair cancelled', 'error'); return
    end

    -- Menu should be closed now; clean clipboard/notepad immediately
    CleanupClipboard()

    local oldDamage = GetPartDamageValue(vehicle, part)

    local function getWorkOrderTargetPart(order)
        if not order then return nil end

        local itemMap = {
            tire_new = 'tire_new',
            carbattery = 'carbattery',
            engine_oil = 'engine_oil',
            brake_pads = 'brakes',
            sparkplugs = 'sparkplugs',
            coolant = 'coolant',
            transmissionfluid = 'transmissionfluid',
            engine_part = 'engine_part',
            body_part = 'body_part',
            susp_arm = 'susp_arm',
            axleparts = 'axleparts'
        }

        local typeMap = {
            tire = 'tire_new',
            battery = 'carbattery',
            oil = 'engine_oil',
            brakes = 'brakes',
            sparkplugs = 'sparkplugs',
            coolant = 'coolant',
            transmission = 'transmissionfluid',
            engine = 'engine_part',
            suspension = 'susp_arm',
            body = 'body_part',
            diagnostics = 'engine_part'
        }

        if order.requiredItem and itemMap[order.requiredItem] then
            return itemMap[order.requiredItem]
        end

        return typeMap[order.repairType]
    end

    local function tryCompleteWorkOrderFromRepair()
        local activeWO = exports['pf-mechanicjob'] and exports['pf-mechanicjob']:GetActiveWorkOrder()
        if not activeWO then return end
        if not activeWO.orderId then return end
        if not DoesEntityExist(activeWO.vehicle) or activeWO.vehicle ~= vehicle then return end

        local targetPart = getWorkOrderTargetPart(activeWO)
        if not targetPart then return end
        if targetPart ~= part then return end

        TriggerServerEvent('pf_mech:workorders:completeRepair', activeWO.orderId)
    end

    -- Ask server to remove items and perform repair
    QBCore.Functions.TriggerCallback('pf_mech:server:attemptRepair', function(success, msg)
        if success then
            QBCore.Functions.Notify(msg or 'Repair successful', 'success')
            tryCompleteWorkOrderFromRepair()
        else
            QBCore.Functions.Notify(msg or 'Missing required parts or failed', 'error')
        end

        CreateThread(function()
            local start = GetGameTimer()
            while (GetGameTimer() - start) < 1200 do
                if GetPartDamageValue(vehicle, part) ~= oldDamage then break end
                Wait(100)
            end
            ReopenDiagnosticsMenu(vehicle)
        end)
    end, NetworkGetNetworkIdFromEntity(vehicle), part, needed, wheel)
end)

-- Generic one-shot VFX relay (entity or coord based)
RegisterNetEvent('pf_mech:vfx:oneshot', function(data)
    if type(data) ~= 'table' then return end
    local dict, name = tostring(data.dict or ''), tostring(data.name or '')
    if dict == '' or name == '' then return end

    RequestNamedPtfxAsset(dict)
    while not HasNamedPtfxAssetLoaded(dict) do Wait(0) end
    UseParticleFxAssetNextCall(dict)

    if data.type == 'entity' then
        local ent = NetWaitEntityFromNet(data.netId or 0, 60, 25)
        if ent == 0 then return end
        local p = data.pos or {0,0,0}
        local r = data.rot or {0,0,0}
        StartParticleFxNonLoopedOnEntity(
            name, ent,
            tonumber(p[1]) or 0.0, tonumber(p[2]) or 0.0, tonumber(p[3]) or 0.0,
            tonumber(r[1]) or 0.0, tonumber(r[2]) or 0.0, tonumber(r[3]) or 0.0,
            tonumber(data.scale) or 1.0, false, false, false
        )
    else
        local c = data.coords or {}
        if not (c.x and c.y and c.z) then return end
        StartParticleFxNonLoopedAtCoord(name, c.x, c.y, c.z, 0.0, 0.0, 0.0, tonumber(data.scale) or 1.0, false, false, false)
    end
end)

-- REMOVE duplicated welding helpers previously at bottom; they are now hoisted above.

-- FIX: Clean up clipboard/notepad when menu closes (Close button or ESC)
RegisterNetEvent('qb-menu:client:closeMenu', function()
    StopWeld()
    CleanupClipboard()  -- NEW
end)

-- ADDITIONAL: Monitor for ESC key or menu hide to cleanup clipboard
CreateThread(function()
    local lastClipboardState = false
    while true do
        Wait(100)
        local ped = PlayerPedId()
        local currentHasClipboard = currentClipboard and DoesEntityExist(currentClipboard) or false
        
        if lastClipboardState and not currentHasClipboard then
            -- Clipboard was deleted, cleanup anim
            ClearPedTasks(ped)
        end
        lastClipboardState = currentHasClipboard
    end
end)

-- NEW: Cleanup on resource stop to prevent stuck anim/prop if menu open
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    StopWeld()
    CleanupClipboard()
end)

-- NEW: Handler for server requesting brake cache reset
RegisterNetEvent('pf_mech:client:resetBrakeCache', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    
    pcall(function()
        exports['pf-mechanicjob']:ResetBrakeCache(veh)
    end)
end)

-- Helper: Check if vehicle is diesel (use config helper)
local function isDieselVehicle(veh)
    return Config.IsDieselCandidate(veh)
end

-- NEW: Toggle coal delete from toolbox menu
RegisterNetEvent('pf_mech:toggleCoalDeleteToolbox', function(data)
    local veh = data.vehicle
    local plate = data.plate
    
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end
    
    if not Config.IsDieselCandidate(veh) then
        QBCore.Functions.Notify('This vehicle is not a diesel', 'error')
        return
    end
    
    local currentState = _G.CoalVehicles[plate] or false
    local newState = not currentState
    
    -- Progress bar
    QBCore.Functions.Progressbar('installing_coal_delete', 
        newState and 'Installing coal delete...' or 'Removing coal delete...', 
        8000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {
            animDict = 'amb@world_human_vehicle_mechanic@male@base',
            anim = 'base',
            flags = 49,
        }, {}, {}, function() -- Success
            TriggerServerEvent('pf_mech:setCoalDelete', plate, newState)
            
            QBCore.Functions.Notify(
                newState and '🚛 Coal delete installed! Rolling coal enabled - floor it and accelerate!' or '🚛 Coal delete removed',
                newState and 'success' or 'primary',
                5000
            )
            
            -- Update local state immediately
            _G.CoalVehicles[plate] = newState
            
        end, function() -- Cancel
            QBCore.Functions.Notify('Installation cancelled', 'error')
        end)
end)

-- Diagnostics handler
RegisterNetEvent('pf_mech:client:runDiagnostics', function(data)
    local veh = data.vehicle
    
    if not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end
    
    -- Show progress bar
    QBCore.Functions.Progressbar('scanning_vehicle', 'Scanning vehicle...', 3000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = 'amb@world_human_vehicle_mechanic@male@base',
        anim = 'base',
        flags = 49,
    }, {}, {}, function() -- Success
        -- Get diagnostics from entity state
        local state = Entity(veh).state
        local partDamage = state.partDamage or {}
        
        local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
        local model = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
        
        -- Build diagnostics menu
        local diagMenu = {
            { 
                header = '📊 Diagnostics: ' .. model,
                txt = 'Plate: ' .. plate,
                isMenuHeader = true 
            }
        }
        
        -- Engine health
        local engineHealth = math.floor(GetVehicleEngineHealth(veh) / 10)
        diagMenu[#diagMenu+1] = {
            header = '🔧 Engine Health',
            txt = engineHealth .. '%',
            params = {}
        }
        
        -- Body health
        local bodyHealth = math.floor(GetVehicleBodyHealth(veh) / 10)
        diagMenu[#diagMenu+1] = {
            header = '🚗 Body Health',
            txt = bodyHealth .. '%',
            params = {}
        }
        
        -- Part damages
        local parts = {
            { key = 'oil', label = 'Engine Oil', icon = '🛢️' },
            { key = 'brakes', label = 'Brake Pads', icon = '🛑' },
            { key = 'carbattery', label = 'Battery', icon = '🔋' },
            { key = 'sparkplugs', label = 'Spark Plugs', icon = '⚡' },
            { key = 'alternator', label = 'Alternator', icon = '🔌' },
            { key = 'suspension', label = 'Suspension', icon = '🔩' },
            { key = 'axle', label = 'Axle', icon = '⚙️' }
        }
        
        for _, part in ipairs(parts) do
            local damage = tonumber(partDamage[part.key]) or 0
            local health = 100 - damage
            local status = 'Good'
            
            if health < 30 then
                status = 'CRITICAL'
            elseif health < 60 then
                status = 'Poor'
            elseif health < 80 then
                status = 'Fair'
            end
            
            diagMenu[#diagMenu+1] = {
                header = part.icon .. ' ' .. part.label,
                txt = string.format('%d%% - %s', health, status),
                params = {}
            }
        end
        
        diagMenu[#diagMenu+1] = { header = 'Back', params = { event = 'pf_mech:client:openTools' } }
        diagMenu[#diagMenu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }

        exports['pfm-menu']:openMenu(diagMenu)
        
    end, function() -- Cancel
        QBCore.Functions.Notify('Scan cancelled', 'error')
    end)
end)

-- ============================================================================
-- REPAIR ITEM HANDLER - Used when player uses repair items from inventory
-- ============================================================================
RegisterNetEvent('pf-mechanicjob:client:useRepairItem', function(itemName)
    local veh = getRepairVehicle()
    if not veh then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    -- Open diagnostics menu to select which part to repair with this item
    TriggerEvent('pf-mechanicjob:client:openToolsMenu:showMenu', veh)
end)

-- Export for other resources (define wrapper to avoid nil export)
local function OpenMechanicToolsMenu()
    TriggerEvent('pf-mechanicjob:client:openToolsMenu')
end
exports('OpenMechanicTools', OpenMechanicToolsMenu)