local QBCore = exports['pfm-core']:GetCoreObject()

local lastAdminVehicleNet = 0
local adminMenuOpen = false
local adminCamUnlockActive = false

local CAM_UNLOCK_KEY = 36 -- Left Ctrl
local LOOK_CONTROLS = { 1, 2, 3, 4, 5, 6 }
local driftHandlingCache = {}

local PERFORMANCE_MODS = {
    { label = 'Engine', modType = 11 },
    { label = 'Brakes', modType = 12 },
    { label = 'Transmission', modType = 13 },
    { label = 'Suspension', modType = 15 },
    { label = 'Armor', modType = 16 },
}

local COSMETIC_LABELS = {
    [0] = 'Spoilers',
    [1] = 'Front Bumper',
    [2] = 'Rear Bumper',
    [3] = 'Side Skirts',
    [4] = 'Exhaust',
    [5] = 'Chassis / Roll Cage',
    [6] = 'Grille',
    [7] = 'Hood',
    [8] = 'Left Fender',
    [9] = 'Right Fender',
    [10] = 'Roof',
    [14] = 'Horns',
    [22] = 'Xenon Headlights',
    [23] = 'Front Wheels',
    [24] = 'Back Wheels',
    [25] = 'Plate Holder',
    [26] = 'Vanity Plate / Trim Design',
    [27] = 'Ornaments',
    [28] = 'Dashboard',
    [29] = 'Dial Design',
    [30] = 'Door Speakers',
    [31] = 'Seats',
    [32] = 'Steering Wheel',
    [33] = 'Shifter Levers',
    [34] = 'Plaques',
    [35] = 'Speakers',
    [36] = 'Trunk',
    [37] = 'Hydraulics',
    [38] = 'Engine Block',
    [39] = 'Air Filter',
    [40] = 'Struts',
    [41] = 'Arch Cover',
    [42] = 'Aerials',
    [43] = 'Trim',
    [44] = 'Tank',
    [45] = 'Windows',
    [46] = 'Livery',
    [48] = 'Vanity Plates',
}

local COSMETIC_EXCLUDES = {
    [11] = true,
    [12] = true,
    [13] = true,
    [15] = true,
    [16] = true,
    [18] = true,
    [23] = true,
    [24] = true,
    [49] = true,
    [50] = true,
}

local WHEEL_MOD_TYPES = {
    [23] = 'Front Wheels',
    [24] = 'Back Wheels',
}

local function notify(msg, msgType)
    QBCore.Functions.Notify(msg, msgType or 'primary')
end

local function runIfAdmin(action)
    if type(action) ~= 'function' then return end

    QBCore.Functions.TriggerCallback('pf-mechanicjob:server:adminCustoms:hasAccess', function(allowed)
        if not allowed then
            notify('You are not allowed to use admin customs', 'error')
            return
        end

        action()
    end)
end

local function getVehicleTitle(veh)
    local plate = GetVehicleNumberPlateText(veh)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then plate = 'UNKNOWN' end

    local modelHash = GetEntityModel(veh)
    local modelName = GetDisplayNameFromVehicleModel(modelHash)
    local modelLabel = GetLabelText(modelName)
    if not modelLabel or modelLabel == 'NULL' then
        modelLabel = modelName
    end

    return modelLabel, plate
end

local function findNearbyVehicle(radius)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local veh = GetClosestVehicle(pos.x, pos.y, pos.z, radius or 8.0, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then
        return veh
    end
    return 0
end

local function resolveVehicle(data)
    local netId = data and tonumber(data.vehicle) or nil
    if not netId and lastAdminVehicleNet and lastAdminVehicleNet ~= 0 then
        netId = lastAdminVehicleNet
    end

    if netId and netId ~= 0 then
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh ~= 0 and DoesEntityExist(veh) then
            lastAdminVehicleNet = netId
            return veh
        end
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and DoesEntityExist(veh) then
            lastAdminVehicleNet = NetworkGetNetworkIdFromEntity(veh)
            return veh
        end
    end

    local nearby = findNearbyVehicle(8.0)
    if nearby ~= 0 then
        lastAdminVehicleNet = NetworkGetNetworkIdFromEntity(nearby)
        return nearby
    end

    return 0
end

local function closeAdminMenu()
    adminMenuOpen = false
    adminCamUnlockActive = false

    if Config.MenuSystem == 'ox_lib' and lib and lib.hideContext then
        lib.hideContext(true)
    elseif exports['pfm-menu'] and exports['pfm-menu'].closeMenu then
        exports['pfm-menu']:closeMenu()
    else
        TriggerEvent('qb-menu:client:closeMenu')
    end
end

local function openAdminMenu(id, title, rows)
    local useOx = Config.MenuSystem == 'ox_lib' and lib and lib.registerContext
    adminMenuOpen = true

    if useOx then
        local options = {}
        for _, row in ipairs(rows) do
            options[#options + 1] = {
                title = row.header or '',
                description = row.txt or '',
                disabled = row.isMenuHeader or not row.event,
                onSelect = function()
                    if row.event then
                        TriggerEvent(row.event, row.args)
                    end
                end,
            }
        end

        lib.registerContext({
            id = id,
            title = title,
            options = options,
        })
        lib.showContext(id)
        return
    end

    local menu = {}
    for _, row in ipairs(rows) do
        local shouldClose = row.shouldClose
        if shouldClose == nil and row.event then
            shouldClose = false
        end

        local item = {
            header = row.header or '',
            txt = row.txt or '',
            isMenuHeader = row.isMenuHeader and true or false,
            shouldClose = shouldClose,
            params = {},
        }

        if row.event then
            item.params = { event = row.event, args = row.args }
        end

        menu[#menu + 1] = item
    end

    if exports['pfm-menu'] and exports['pfm-menu'].openMenu then
        exports['pfm-menu']:openMenu(menu)
    else
        notify('qb-menu is not available', 'error')
    end
end

local function isCtrlHeld()
    -- Menu resources can disable controls; this still detects Left Ctrl in that state.
    return IsControlPressed(0, CAM_UNLOCK_KEY) or IsDisabledControlPressed(0, CAM_UNLOCK_KEY)
end

RegisterNetEvent('qb-menu:client:closeMenu', function()
    if adminMenuOpen then
        adminMenuOpen = false
        adminCamUnlockActive = false
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
end)

CreateThread(function()
    while true do
        if adminMenuOpen and Config.MenuSystem ~= 'ox_lib' then
            Wait(0)

            local ctrlHeld = isCtrlHeld()

            if ctrlHeld then
                for _, control in ipairs(LOOK_CONTROLS) do
                    EnableControlAction(0, control, true)
                end

                SetNuiFocus(false, false)
                SetNuiFocusKeepInput(false)

                if not adminCamUnlockActive then
                    adminCamUnlockActive = true
                end
            else
                for _, control in ipairs(LOOK_CONTROLS) do
                    DisableControlAction(0, control, true)
                end

                if adminCamUnlockActive then
                    adminCamUnlockActive = false
                    SetNuiFocus(true, true)
                    SetNuiFocusKeepInput(false)
                end
            end
        else
            Wait(200)
        end
    end
end)

local function syncVehicleState(veh)
    if veh == 0 or not DoesEntityExist(veh) then return end

    pcall(function()
        if exports['pf-mechanicjob'] and exports['pf-mechanicjob'].SyncVehicleDiagnostics then
            exports['pf-mechanicjob']:SyncVehicleDiagnostics(veh)
        end
    end)
end

local function getModOptionLabel(veh, modType, index)
    local textLabel = GetModTextLabel(veh, modType, index)
    if textLabel then
        local label = GetLabelText(textLabel)
        if label and label ~= 'NULL' then
            return label
        end
    end
    return ('Option %d'):format(index + 1)
end

local function getCurrentModDescription(veh, modType)
    if modType == 22 then
        return IsToggleModOn(veh, 22) and 'Enabled' or 'Disabled'
    end

    local current = GetVehicleMod(veh, modType)
    if current < 0 then
        return 'Stock'
    end

    return getModOptionLabel(veh, modType, current)
end

-- Vehicle state bags are set by the server (sv_stateBagStrictMode): ask it, then wait briefly until
-- the change has arrived, so the diagnostics saved next (syncVehicleState) and a reopened menu see it.
local function requestVehicleState(veh, action, value, applied)
    if veh == 0 or not DoesEntityExist(veh) then return false end
    TriggerServerEvent('pf-mechanicjob:server:adminCustoms:vehicleState', NetworkGetNetworkIdFromEntity(veh), action, value)
    if not applied then return true end
    local untilAt = GetGameTimer() + 1500
    while GetGameTimer() < untilAt do
        if not DoesEntityExist(veh) then return false end
        if applied(Entity(veh).state) then return true end
        Wait(50)
    end
    return false
end

local function getDriftCacheKey(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    if netId and netId > 0 then
        return ('net:%s'):format(netId)
    end
    return ('ent:%s'):format(veh)
end

local function isDriftEnabled(veh)
    local state = Entity(veh).state
    if state and state.pfDriftTires ~= nil then
        return state.pfDriftTires == true
    end

    local key = getDriftCacheKey(veh)
    return driftHandlingCache[key] and driftHandlingCache[key].enabled == true or false
end

local function setDriftTireProfile(veh, enabled)
    if veh == 0 or not DoesEntityExist(veh) then return end

    local key = getDriftCacheKey(veh)
    local cached = driftHandlingCache[key]

    if enabled then
        if not cached then
            cached = {
                tractionMin = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin'),
                tractionMax = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax'),
                lowSpeedTractionLoss = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fLowSpeedTractionLossMult'),
                driveForce = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce'),
                driveInertia = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia'),
                enabled = false,
            }
            driftHandlingCache[key] = cached
        end

        -- Use native drift tires when available; always avoid raw reduce-grip "ice" behavior.
        if type(SetDriftTyresEnabled) == 'function' then
            SetDriftTyresEnabled(veh, true)
        end
        if type(SetReduceDriftVehicleSuspension) == 'function' then
            SetReduceDriftVehicleSuspension(veh, true)
        end
        SetVehicleReduceGrip(veh, false)

        -- Controlled drift profile: enough slide, but still drivable from a stop.
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin', cached.tractionMin * 0.92)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax', cached.tractionMax * 0.95)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fLowSpeedTractionLossMult', cached.lowSpeedTractionLoss * 0.45)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce', cached.driveForce * 0.82)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia', cached.driveInertia * 0.92)

        cached.enabled = true
        requestVehicleState(veh, 'drift', true, function(st) return st.pfDriftTires == true end)
        return
    end

    if type(SetDriftTyresEnabled) == 'function' then
        SetDriftTyresEnabled(veh, false)
    end
    if type(SetReduceDriftVehicleSuspension) == 'function' then
        SetReduceDriftVehicleSuspension(veh, false)
    end
    SetVehicleReduceGrip(veh, false)

    if cached then
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin', cached.tractionMin)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax', cached.tractionMax)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fLowSpeedTractionLossMult', cached.lowSpeedTractionLoss)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce', cached.driveForce)
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia', cached.driveInertia)
        cached.enabled = false
    end

    requestVehicleState(veh, 'drift', false, function(st) return st.pfDriftTires == false end)
end

local function getCosmeticCategoryCount(veh)
    local count = 0
    for modType = 0, 49 do
        if not COSMETIC_EXCLUDES[modType] then
            local modCount = GetNumVehicleMods(veh, modType)
            local isToggle = (modType == 22)
            if modCount > 0 or isToggle then
                count = count + 1
            end
        end
    end
    return count
end

local function getExtrasCount(veh)
    local count = 0
    for extraId = 1, 20 do
        if DoesExtraExist(veh, extraId) then
            count = count + 1
        end
    end
    return count
end

local function getPerformanceCategoryCount(veh)
    local count = 0

    for _, entry in ipairs(PERFORMANCE_MODS) do
        if GetNumVehicleMods(veh, entry.modType) > 0 then
            count = count + 1
        end
    end

    if GetNumVehicleMods(veh, 18) > 0 then
        count = count + 1
    end

    -- These are always available actions in the performance menu.
    count = count + 2

    return count
end

local function getWheelCategoryCount(veh)
    local count = 0
    for modType, _ in pairs(WHEEL_MOD_TYPES) do
        if GetNumVehicleMods(veh, modType) > 0 then
            count = count + 1
        end
    end
    return count
end

-- the server sets every part to 0 (the same clean set this function used to write itself)
local function resetPartDamage(veh)
    requestVehicleState(veh, 'resetPartDamage', nil, function(st)
        local pd = st.partDamage
        if type(pd) ~= 'table' then return false end
        for _, v in pairs(pd) do
            if type(v) == 'number' and v ~= 0 then return false end
        end
        return true
    end)
end

local function performFullRepair(veh)
    local wasEngineRunning = GetIsVehicleEngineRunning(veh)

    SetVehicleModKit(veh, 0)
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleUndriveable(veh, false)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleDirtLevel(veh, 0.0)
    WashDecalsFromVehicle(veh, 1.0)

    for i = 0, 7 do
        SetVehicleTyreFixed(veh, i)
        FixVehicleWindow(veh, i)
    end

    for door = 0, 5 do
        SetVehicleDoorShut(veh, door, false)
    end

    resetPartDamage(veh)

    TriggerEvent('pf_mech:client:resetBrakeCache', NetworkGetNetworkIdFromEntity(veh))

    if wasEngineRunning then
        SetVehicleEngineOn(veh, true, true, false)
    end

    SetVehicleOnGroundProperly(veh)
    syncVehicleState(veh)
end

local function reopenMenu(menuName, vehicleNet, modType, label)
    CreateThread(function()
        Wait(0)

        if menuName == 'repairs' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openRepairs', { vehicle = vehicleNet })
        elseif menuName == 'performance' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openPerformance', { vehicle = vehicleNet })
        elseif menuName == 'performance-options' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openPerformanceOptions', {
                vehicle = vehicleNet,
                modType = modType,
                label = label,
            })
        elseif menuName == 'wheels' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openWheels', { vehicle = vehicleNet })
        elseif menuName == 'wheel-variants' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openWheelVariants', {
                vehicle = vehicleNet,
                modType = modType,
            })
        elseif menuName == 'cosmetics' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openCosmetics', { vehicle = vehicleNet })
        elseif menuName == 'cosmetic-variants' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openCosmeticVariants', {
                vehicle = vehicleNet,
                modType = modType,
            })
        elseif menuName == 'extras' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openExtras', { vehicle = vehicleNet })
        elseif menuName == 'nos' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openNos', { vehicle = vehicleNet })
        elseif menuName == 'nos-level' then
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openNosLevel', { vehicle = vehicleNet })
        else
            TriggerEvent('pf-mechanicjob:client:adminCustoms:openRoot', { vehicle = vehicleNet })
        end
    end)
end

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:close', function()
    closeAdminMenu()
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openRoot', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then
            notify('No vehicle found. Sit in one or move closer to a vehicle.', 'error')
            return
        end

        local model, plate = getVehicleTitle(veh)
        local mileage = tonumber((Entity(veh).state or {}).mileage) or 0
        local netId = NetworkGetNetworkIdFromEntity(veh)
        local perfCount = getPerformanceCategoryCount(veh)
        local wheelCount = getWheelCategoryCount(veh)
        local cosmeticCount = getCosmeticCategoryCount(veh)
        local extrasCount = getExtrasCount(veh)

        local rows = {
            { header = ('Admin Customs: %s'):format(plate), txt = ('%s | Mileage: %.1f mi'):format(model, mileage), isMenuHeader = true },
            { header = 'Repairs / Resets', txt = 'Full repair, part-damage reset, mileage reset', event = 'pf-mechanicjob:client:adminCustoms:openRepairs', args = { vehicle = netId } },
        }

        if perfCount > 0 then
            rows[#rows + 1] = { header = 'Performance', txt = 'Engine, brakes, transmission, suspension, armor, turbo', event = 'pf-mechanicjob:client:adminCustoms:openPerformance', args = { vehicle = netId } }
        end

        if wheelCount > 0 then
            rows[#rows + 1] = { header = 'Wheels', txt = 'Front/back wheel categories and variants', event = 'pf-mechanicjob:client:adminCustoms:openWheels', args = { vehicle = netId } }
        end

        if cosmeticCount > 0 then
            rows[#rows + 1] = { header = 'Cosmetics', txt = 'All available body and interior mods', event = 'pf-mechanicjob:client:adminCustoms:openCosmetics', args = { vehicle = netId } }
        end

        if extrasCount > 0 then
            rows[#rows + 1] = { header = 'Extras', txt = 'Toggle vehicle extras instantly', event = 'pf-mechanicjob:client:adminCustoms:openExtras', args = { vehicle = netId } }
        end

        rows[#rows + 1] = { header = 'NOS', txt = 'Install/refill/remove NOS and set boost level', event = 'pf-mechanicjob:client:adminCustoms:openNos', args = { vehicle = netId } }
        rows[#rows + 1] = { header = 'Close', txt = '', event = 'pf-mechanicjob:client:adminCustoms:close', shouldClose = true }

        openAdminMenu('pf_admincustom_root', 'Admin Customs', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openRepairs', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then
            notify('Vehicle not found', 'error')
            return
        end

        local netId = NetworkGetNetworkIdFromEntity(veh)

        local rows = {
            { header = 'Repairs / Resets', txt = 'All actions apply instantly', isMenuHeader = true },
            { header = 'Full Repair', txt = 'Mechanical, cosmetic, tires, fluids, damage state', event = 'pf-mechanicjob:client:adminCustoms:doFullRepair', args = { vehicle = netId, reopen = 'repairs' } },
            { header = 'Reset Part Damage', txt = 'Oil, brakes, coolant, suspension, battery, etc.', event = 'pf-mechanicjob:client:adminCustoms:doResetPartDamage', args = { vehicle = netId, reopen = 'repairs' } },
            { header = 'Reset Mileage to 0', txt = 'Sets entity mileage state to 0 and syncs', event = 'pf-mechanicjob:client:adminCustoms:doResetMileage', args = { vehicle = netId, reopen = 'repairs' } },
            { header = 'Clean Vehicle', txt = 'Wash and remove dirt', event = 'pf-mechanicjob:client:adminCustoms:doCleanVehicle', args = { vehicle = netId, reopen = 'repairs' } },
            { header = 'Back', txt = '', event = 'pf-mechanicjob:client:adminCustoms:openRoot', args = { vehicle = netId } },
            { header = 'Close', txt = '', event = 'pf-mechanicjob:client:adminCustoms:close', shouldClose = true },
        }

        openAdminMenu('pf_admincustom_repairs', 'Repairs / Resets', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:doFullRepair', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        performFullRepair(veh)
        notify('Full repair completed', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu(data and data.reopen or 'repairs', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:doResetPartDamage', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        resetPartDamage(veh)
        TriggerEvent('pf_mech:client:resetBrakeCache', NetworkGetNetworkIdFromEntity(veh))
        syncVehicleState(veh)

        notify('Part damage reset to 0', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu(data and data.reopen or 'repairs', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:doResetMileage', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        requestVehicleState(veh, 'resetMileage', nil, function(st) return tonumber(st.mileage) == 0 end)

        syncVehicleState(veh)
        notify('Mileage reset to 0', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu(data and data.reopen or 'repairs', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:doCleanVehicle', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        SetVehicleDirtLevel(veh, 0.0)
        WashDecalsFromVehicle(veh, 1.0)
        syncVehicleState(veh)

        notify('Vehicle cleaned', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu(data and data.reopen or 'repairs', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openPerformance', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        SetVehicleModKit(veh, 0)
        local netId = NetworkGetNetworkIdFromEntity(veh)

        local rows = {
            { header = 'Performance', txt = 'Select a category to edit', isMenuHeader = true },
            {
                header = 'Max Performance',
                txt = 'Apply max engine/brakes/transmission/suspension/armor + turbo',
                event = 'pf-mechanicjob:client:adminCustoms:applyMaxPerformance',
                args = { vehicle = netId },
            },
        }

        for _, entry in ipairs(PERFORMANCE_MODS) do
            local count = GetNumVehicleMods(veh, entry.modType)
            if count > 0 then
                rows[#rows + 1] = {
                    header = entry.label,
                    txt = getCurrentModDescription(veh, entry.modType),
                    event = 'pf-mechanicjob:client:adminCustoms:openPerformanceOptions',
                    args = {
                        vehicle = netId,
                        modType = entry.modType,
                        label = entry.label,
                    },
                }
            end
        end

        if GetNumVehicleMods(veh, 18) > 0 then
            local turboOn = IsToggleModOn(veh, 18)
            rows[#rows + 1] = {
                header = 'Turbo',
                txt = turboOn and 'Enabled' or 'Disabled',
                event = 'pf-mechanicjob:client:adminCustoms:toggleTurbo',
                args = { vehicle = netId, enable = not turboOn },
            }
        end

        local driftOn = isDriftEnabled(veh)
        rows[#rows + 1] = {
            header = 'Drift Tires (Controlled)',
            txt = driftOn and 'Enabled' or 'Disabled',
            event = 'pf-mechanicjob:client:adminCustoms:toggleDriftTires',
            args = { vehicle = netId, enable = not driftOn },
        }

        local bulletproof = not GetVehicleTyresCanBurst(veh)
        rows[#rows + 1] = {
            header = 'Bulletproof Tires',
            txt = bulletproof and 'Enabled' or 'Disabled',
            event = 'pf-mechanicjob:client:adminCustoms:toggleBulletproofTires',
            args = { vehicle = netId, enable = not bulletproof },
        }

        rows[#rows + 1] = { header = 'Back', txt = '', event = 'pf-mechanicjob:client:adminCustoms:openRoot', args = { vehicle = netId } }
        rows[#rows + 1] = { header = 'Close', txt = '', event = 'pf-mechanicjob:client:adminCustoms:close', shouldClose = true }

        openAdminMenu('pf_admincustom_performance', 'Performance', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openPerformanceOptions', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local modType = tonumber(data and data.modType)
        if not modType then
            notify('Invalid performance category', 'error')
            return
        end

        SetVehicleModKit(veh, 0)

        local count = GetNumVehicleMods(veh, modType)
        if count <= 0 then
            notify('No options for this category on this vehicle', 'error')
            return
        end

        local label = tostring((data and data.label) or ('Mod ' .. modType))
        local netId = NetworkGetNetworkIdFromEntity(veh)

        local rows = {
            { header = label, txt = 'Choose a level', isMenuHeader = true },
            {
                header = 'Stock',
                txt = 'Remove upgrade (set stock)',
                event = 'pf-mechanicjob:client:adminCustoms:applyPerformanceOption',
                args = {
                    vehicle = netId,
                    modType = modType,
                    index = -1,
                    label = label,
                },
            },
        }

        for idx = 0, count - 1 do
            rows[#rows + 1] = {
                header = ('Level %d'):format(idx + 1),
                txt = getModOptionLabel(veh, modType, idx),
                event = 'pf-mechanicjob:client:adminCustoms:applyPerformanceOption',
                args = {
                    vehicle = netId,
                    modType = modType,
                    index = idx,
                    label = label,
                },
            }
        end

        rows[#rows + 1] = {
            header = 'Back',
            txt = '',
            event = 'pf-mechanicjob:client:adminCustoms:openPerformance',
            args = { vehicle = netId },
        }

        openAdminMenu('pf_admincustom_performance_options', label, rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:applyPerformanceOption', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local modType = tonumber(data and data.modType)
        local index = tonumber(data and data.index)
        if not modType or not index then
            notify('Invalid performance option', 'error')
            return
        end

        SetVehicleModKit(veh, 0)
        SetVehicleMod(veh, modType, index, false)
        syncVehicleState(veh)

        notify('Performance option applied', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('performance-options', netId, modType, data and data.label)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:applyMaxPerformance', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        SetVehicleModKit(veh, 0)

        local appliedCount = 0
        for _, entry in ipairs(PERFORMANCE_MODS) do
            local count = GetNumVehicleMods(veh, entry.modType)
            if count > 0 then
                SetVehicleMod(veh, entry.modType, count - 1, false)
                appliedCount = appliedCount + 1
            end
        end

        if GetNumVehicleMods(veh, 18) > 0 then
            ToggleVehicleMod(veh, 18, true)
            appliedCount = appliedCount + 1
        end

        syncVehicleState(veh)

        if appliedCount > 0 then
            notify('Max performance applied', 'success')
        else
            notify('No performance upgrades available for this vehicle', 'error')
        end

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('performance', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:toggleTurbo', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        SetVehicleModKit(veh, 0)
        ToggleVehicleMod(veh, 18, data and data.enable and true or false)
        syncVehicleState(veh)

        notify((data and data.enable) and 'Turbo enabled' or 'Turbo disabled', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('performance', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:toggleDriftTires', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        setDriftTireProfile(veh, data and data.enable and true or false)
        syncVehicleState(veh)

        notify((data and data.enable) and 'Drift tires enabled' or 'Drift tires disabled', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('performance', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:toggleBulletproofTires', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        SetVehicleTyresCanBurst(veh, not (data and data.enable))
        syncVehicleState(veh)

        notify((data and data.enable) and 'Bulletproof tires enabled' or 'Bulletproof tires disabled', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('performance', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openWheels', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        SetVehicleModKit(veh, 0)
        local netId = NetworkGetNetworkIdFromEntity(veh)

        local entries = {}
        for modType, label in pairs(WHEEL_MOD_TYPES) do
            local count = GetNumVehicleMods(veh, modType)
            if count > 0 then
                entries[#entries + 1] = {
                    modType = modType,
                    label = label,
                    count = count,
                }
            end
        end

        table.sort(entries, function(a, b)
            return a.label < b.label
        end)

        if #entries == 0 then
            notify('No wheel options on this vehicle', 'error')
            reopenMenu('root', netId)
            return
        end

        local rows = {
            { header = 'Wheels', txt = 'Pick a wheel category', isMenuHeader = true }
        }

        for _, entry in ipairs(entries) do
            rows[#rows + 1] = {
                header = entry.label,
                txt = getCurrentModDescription(veh, entry.modType),
                event = 'pf-mechanicjob:client:adminCustoms:openWheelVariants',
                args = {
                    vehicle = netId,
                    modType = entry.modType,
                },
            }
        end

        rows[#rows + 1] = { header = 'Back', txt = '', event = 'pf-mechanicjob:client:adminCustoms:openRoot', args = { vehicle = netId } }
        rows[#rows + 1] = { header = 'Close', txt = '', event = 'pf-mechanicjob:client:adminCustoms:close', shouldClose = true }

        openAdminMenu('pf_admincustom_wheels', 'Wheels', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openWheelVariants', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local modType = tonumber(data and data.modType)
        if not modType or not WHEEL_MOD_TYPES[modType] then
            notify('Invalid wheel category', 'error')
            return
        end

        SetVehicleModKit(veh, 0)
        local count = GetNumVehicleMods(veh, modType)
        if count <= 0 then
            notify('No wheel variants available for this vehicle', 'error')
            return
        end

        local label = WHEEL_MOD_TYPES[modType]
        local netId = NetworkGetNetworkIdFromEntity(veh)

        local rows = {
            { header = label, txt = 'Select a wheel variant', isMenuHeader = true },
            {
                header = 'Stock',
                txt = 'Remove installed wheel mod',
                event = 'pf-mechanicjob:client:adminCustoms:applyCosmeticVariant',
                args = {
                    vehicle = netId,
                    modType = modType,
                    index = -1,
                },
            },
        }

        for idx = 0, count - 1 do
            rows[#rows + 1] = {
                header = getModOptionLabel(veh, modType, idx),
                txt = ('Variant %d'):format(idx + 1),
                event = 'pf-mechanicjob:client:adminCustoms:applyCosmeticVariant',
                args = {
                    vehicle = netId,
                    modType = modType,
                    index = idx,
                },
            }
        end

        rows[#rows + 1] = {
            header = 'Back',
            txt = '',
            event = 'pf-mechanicjob:client:adminCustoms:openWheels',
            args = { vehicle = netId },
        }

        openAdminMenu('pf_admincustom_wheel_variants', label, rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openCosmetics', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        SetVehicleModKit(veh, 0)
        local netId = NetworkGetNetworkIdFromEntity(veh)

        local entries = {}
        for modType = 0, 49 do
            if not COSMETIC_EXCLUDES[modType] then
                local count = GetNumVehicleMods(veh, modType)
                local isToggle = (modType == 22)
                if count > 0 or isToggle then
                    entries[#entries + 1] = {
                        modType = modType,
                        label = COSMETIC_LABELS[modType] or ('Mod Type ' .. modType),
                        count = count,
                        isToggle = isToggle,
                    }
                end
            end
        end

        table.sort(entries, function(a, b)
            return a.label < b.label
        end)

        local rows = {
            { header = 'Cosmetics', txt = 'Pick a category', isMenuHeader = true }
        }

        if #entries == 0 then
            notify('No cosmetic options on this vehicle', 'error')
            reopenMenu('root', netId)
            return
        else
            for _, entry in ipairs(entries) do
                if entry.isToggle then
                    rows[#rows + 1] = {
                        header = entry.label,
                        txt = IsToggleModOn(veh, entry.modType) and 'Enabled' or 'Disabled',
                        event = 'pf-mechanicjob:client:adminCustoms:toggleCosmetic',
                        args = {
                            vehicle = netId,
                            modType = entry.modType,
                            enable = not IsToggleModOn(veh, entry.modType),
                        },
                    }
                else
                    rows[#rows + 1] = {
                        header = entry.label,
                        txt = getCurrentModDescription(veh, entry.modType),
                        event = 'pf-mechanicjob:client:adminCustoms:openCosmeticVariants',
                        args = {
                            vehicle = netId,
                            modType = entry.modType,
                        },
                    }
                end
            end
        end

        rows[#rows + 1] = { header = 'Back', txt = '', event = 'pf-mechanicjob:client:adminCustoms:openRoot', args = { vehicle = netId } }
        rows[#rows + 1] = { header = 'Close', txt = '', event = 'pf-mechanicjob:client:adminCustoms:close', shouldClose = true }

        openAdminMenu('pf_admincustom_cosmetics', 'Cosmetics', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openCosmeticVariants', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local modType = tonumber(data and data.modType)
        if modType == nil or COSMETIC_EXCLUDES[modType] then
            notify('Invalid cosmetic category', 'error')
            return
        end

        SetVehicleModKit(veh, 0)
        local count = GetNumVehicleMods(veh, modType)
        if count <= 0 then
            notify('No variants available for this cosmetic type', 'error')
            return
        end

        local label = COSMETIC_LABELS[modType] or ('Mod Type ' .. modType)
        local netId = NetworkGetNetworkIdFromEntity(veh)

        local rows = {
            { header = label, txt = 'Select a variant', isMenuHeader = true },
            {
                header = 'Stock',
                txt = 'Remove installed mod',
                event = 'pf-mechanicjob:client:adminCustoms:applyCosmeticVariant',
                args = {
                    vehicle = netId,
                    modType = modType,
                    index = -1,
                },
            },
        }

        for idx = 0, count - 1 do
            rows[#rows + 1] = {
                header = getModOptionLabel(veh, modType, idx),
                txt = ('Variant %d'):format(idx + 1),
                event = 'pf-mechanicjob:client:adminCustoms:applyCosmeticVariant',
                args = {
                    vehicle = netId,
                    modType = modType,
                    index = idx,
                },
            }
        end

        rows[#rows + 1] = {
            header = 'Back',
            txt = '',
            event = 'pf-mechanicjob:client:adminCustoms:openCosmetics',
            args = { vehicle = netId },
        }

        openAdminMenu('pf_admincustom_cosmetic_variants', label, rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:applyCosmeticVariant', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local modType = tonumber(data and data.modType)
        local index = tonumber(data and data.index)
        if modType == nil or index == nil then
            notify('Invalid cosmetic variant', 'error')
            return
        end

        SetVehicleModKit(veh, 0)
        SetVehicleMod(veh, modType, index, false)
        syncVehicleState(veh)

        notify('Cosmetic applied', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('cosmetic-variants', netId, modType)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:toggleCosmetic', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local modType = tonumber(data and data.modType)
        if modType == nil then
            notify('Invalid cosmetic toggle', 'error')
            return
        end

        ToggleVehicleMod(veh, modType, data and data.enable and true or false)
        syncVehicleState(veh)

        notify((data and data.enable) and 'Enabled' or 'Disabled', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('cosmetics', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openExtras', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local netId = NetworkGetNetworkIdFromEntity(veh)

        local rows = {
            { header = 'Vehicle Extras', txt = 'Toggle extras instantly', isMenuHeader = true }
        }

        local count = 0
        for extraId = 1, 20 do
            if DoesExtraExist(veh, extraId) then
                count = count + 1
                local on = IsVehicleExtraTurnedOn(veh, extraId)
                rows[#rows + 1] = {
                    header = ('Extra %d'):format(extraId),
                    txt = on and 'Enabled' or 'Disabled',
                    event = 'pf-mechanicjob:client:adminCustoms:toggleExtra',
                    args = {
                        vehicle = netId,
                        extraId = extraId,
                        enable = not on,
                    },
                }
            end
        end

        if count == 0 then
            notify('No extras found on this vehicle', 'error')
            reopenMenu('root', netId)
            return
        end

        rows[#rows + 1] = { header = 'Back', txt = '', event = 'pf-mechanicjob:client:adminCustoms:openRoot', args = { vehicle = netId } }
        rows[#rows + 1] = { header = 'Close', txt = '', event = 'pf-mechanicjob:client:adminCustoms:close', shouldClose = true }

        openAdminMenu('pf_admincustom_extras', 'Extras', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:toggleExtra', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local extraId = tonumber(data and data.extraId)
        if not extraId then
            notify('Invalid extra', 'error')
            return
        end

        SetVehicleExtra(veh, extraId, (data and data.enable) and 0 or 1)
        syncVehicleState(veh)

        notify(('Extra %d %s'):format(extraId, (data and data.enable) and 'enabled' or 'disabled'), 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('extras', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openNos', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local nos = Entity(veh).state.nos
        local hasNos = nos and nos.has == true
        local level = hasNos and (tonumber(nos.level) or 0) or 0
        local levelSel = hasNos and (tonumber(nos.levelSel) or 1) or 1

        local netId = NetworkGetNetworkIdFromEntity(veh)
        local rows = {
            { header = 'NOS System', txt = 'Manage NOS instantly', isMenuHeader = true },
            { header = 'Install / Refill NOS', txt = hasNos and ('Current: %d%%'):format(math.floor(level)) or 'Install NOS with full bottle', event = 'pf-mechanicjob:client:adminCustoms:nosInstallOrRefill', args = { vehicle = netId } },
            { header = 'Set NOS Boost Level', txt = ('Current level: %d'):format(levelSel), event = 'pf-mechanicjob:client:adminCustoms:openNosLevel', args = { vehicle = netId } },
            { header = 'Remove NOS', txt = hasNos and 'Remove NOS system from vehicle' or 'No NOS installed', event = 'pf-mechanicjob:client:adminCustoms:nosRemove', args = { vehicle = netId }, isMenuHeader = not hasNos },
            { header = 'Back', txt = '', event = 'pf-mechanicjob:client:adminCustoms:openRoot', args = { vehicle = netId } },
            { header = 'Close', txt = '', event = 'pf-mechanicjob:client:adminCustoms:close', shouldClose = true },
        }

        openAdminMenu('pf_admincustom_nos', 'NOS', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:openNosLevel', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local nos = Entity(veh).state.nos
        if not (nos and nos.has) then
            notify('Install NOS first', 'error')
            return
        end

        local current = tonumber(nos.levelSel) or 1
        local netId = NetworkGetNetworkIdFromEntity(veh)

        local rows = {
            { header = 'NOS Boost Level', txt = ('Current: %d'):format(current), isMenuHeader = true },
            { header = 'Level 1', txt = 'Mild boost', event = 'pf-mechanicjob:client:adminCustoms:setNosLevel', args = { vehicle = netId, levelSel = 1 } },
            { header = 'Level 2', txt = 'Balanced boost', event = 'pf-mechanicjob:client:adminCustoms:setNosLevel', args = { vehicle = netId, levelSel = 2 } },
            { header = 'Level 3', txt = 'Maximum boost', event = 'pf-mechanicjob:client:adminCustoms:setNosLevel', args = { vehicle = netId, levelSel = 3 } },
            { header = 'Back', txt = '', event = 'pf-mechanicjob:client:adminCustoms:openNos', args = { vehicle = netId } },
        }

        openAdminMenu('pf_admincustom_nos_level', 'NOS Boost Level', rows)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:nosInstallOrRefill', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local cap = (Config.NOS and Config.NOS.capacity) or 100

        requestVehicleState(veh, 'nosInstall', nil, function(st)
            return type(st.nos) == 'table' and st.nos.has == true and (tonumber(st.nos.level) or 0) >= cap
        end)
        syncVehicleState(veh)

        notify('NOS installed/refilled', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('nos', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:setNosLevel', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local levelSel = tonumber(data and data.levelSel)
        if not levelSel or levelSel < 1 or levelSel > 3 then
            notify('Invalid NOS level', 'error')
            return
        end

        local nos = Entity(veh).state.nos
        if not (nos and nos.has) then
            notify('No NOS installed', 'error')
            return
        end

        requestVehicleState(veh, 'nosLevel', levelSel, function(st)
            return type(st.nos) == 'table' and tonumber(st.nos.levelSel) == levelSel
        end)
        syncVehicleState(veh)

        notify(('NOS boost level set to %d'):format(levelSel), 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('nos-level', netId)
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:adminCustoms:nosRemove', function(data)
    runIfAdmin(function()
        local veh = resolveVehicle(data)
        if veh == 0 then notify('Vehicle not found', 'error'); return end

        local nos = Entity(veh).state.nos
        if not (nos and nos.has) then
            notify('No NOS installed', 'error')
            return
        end

        requestVehicleState(veh, 'nosRemove', nil, function(st) return st.nos == nil end)
        syncVehicleState(veh)

        notify('NOS removed', 'success')

        local netId = NetworkGetNetworkIdFromEntity(veh)
        reopenMenu('nos', netId)
    end)
end)
