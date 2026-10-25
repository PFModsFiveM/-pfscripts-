local QBCore = exports['pfm-core']:GetCoreObject()

-- Upgrade labels
local UpgradeLabels = {
    engine = "Engine",
    brakes = "Brakes",
    transmission = "Transmission",
    suspension = "Suspension",
    turbo = "Turbo"
}

-- Cosmetic mod labels (EXPANDED to include ALL mod types)
local CosmeticLabels = {
    [0] = "Spoilers",
    [1] = "Front Bumpers",
    [2] = "Rear Bumpers",
    [3] = "Side Skirts",
    [4] = "Exhausts",
    [5] = "Roll Cages",
    [6] = "Grilles",
    [7] = "Hoods",
    [8] = "Fenders",
    [9] = "Right Fenders",
    [10] = "Roof",
    [14] = "Horns",
    [22] = "Xenon Lights",
    [23] = "Front Wheels",
    [24] = "Back Wheels",
    [25] = "Plate Holders",
    [26] = "Trim Design",
    [27] = "Ornaments",
    [28] = "Dashboard",
    [29] = "Dial Design",
    [30] = "Door Speakers",
    [31] = "Seats",
    [32] = "Steering Wheel",
    [33] = "Shifter Leavers",
    [34] = "Plaques",
    [35] = "Speakers",
    [36] = "Trunk",
    [37] = "Hydraulics",
    [38] = "Engine Block",
    [39] = "Air Filter",
    [40] = "Struts",
    [41] = "Arch Cover",
    [42] = "Aerials",
    [43] = "Trim",
    [44] = "Tank",
    [45] = "Windows",
    [46] = "Livery",
    [48] = "Vanity Plates"
}

-- Helper: Get nearby vehicle
local function nearbyVeh(radius)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local veh = GetClosestVehicle(pos.x, pos.y, pos.z, radius or 6.0, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
    return 0
end

-- Helper: Get upgrade level name with max
local function getUpgradeLevelName(modType, current, max)
    if modType == 18 then -- Turbo
        return current >= 0 and "Installed" or "Not Installed"
    end
    
    if current == -1 then
        return string.format("Level (0/%d)", max)
    end
    
    return string.format("Level (%d/%d)", current + 1, max)
end

-- Helper: Get all vehicle upgrades
local function getVehicleUpgrades(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    SetVehicleModKit(veh, 0)
    
    local upgrades = {}
    
    -- Engine (modType 11)
    local engineMod = GetVehicleMod(veh, 11)
    local engineMax = GetNumVehicleMods(veh, 11)
    upgrades.engine = {
        current = engineMod,
        max = engineMax,
        label = UpgradeLabels.engine,
        levelName = getUpgradeLevelName(11, engineMod, engineMax)
    }
    
    -- Brakes (modType 12)
    local brakesMod = GetVehicleMod(veh, 12)
    local brakesMax = GetNumVehicleMods(veh, 12)
    upgrades.brakes = {
        current = brakesMod,
        max = brakesMax,
        label = UpgradeLabels.brakes,
        levelName = getUpgradeLevelName(12, brakesMod, brakesMax)
    }
    
    -- Transmission (modType 13)
    local transMod = GetVehicleMod(veh, 13)
    local transMax = GetNumVehicleMods(veh, 13)
    upgrades.transmission = {
        current = transMod,
        max = transMax,
        label = UpgradeLabels.transmission,
        levelName = getUpgradeLevelName(13, transMod, transMax)
    }
    
    -- Suspension (modType 15)
    local suspMod = GetVehicleMod(veh, 15)
    local suspMax = GetNumVehicleMods(veh, 15)
    upgrades.suspension = {
        current = suspMod,
        max = suspMax,
        label = UpgradeLabels.suspension,
        levelName = getUpgradeLevelName(15, suspMod, suspMax)
    }
    
    -- Turbo (modType 18)
    local turboInstalled = IsToggleModOn(veh, 18)
    upgrades.turbo = {
        current = turboInstalled and 0 or -1,
        max = 1,
        label = UpgradeLabels.turbo,
        levelName = getUpgradeLevelName(18, turboInstalled and 0 or -1, 1)
    }
    
    return upgrades
end

-- Helper: Get all cosmetic mod counts for vehicle (UPDATED to check ALL mod types)
local function getVehicleCosmetics(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    SetVehicleModKit(veh, 0)
    
    local cosmetics = {}
    
    -- Check cosmetic mod types while excluding performance, wheels, and Imani tech entries.
    for modType = 0, 49 do
        local excluded = (
            modType == 11 or modType == 12 or modType == 13 or modType == 15 or modType == 16 or modType == 18 or
            modType == 23 or modType == 24 or -- wheels are handled in their own section
            modType == 49 or modType == 50    -- remove remote control / missile jammer from customizations
        )

        if not excluded then
            local count = GetNumVehicleMods(veh, modType)

            -- Also check if it's a toggle mod (like xenon lights)
            local isToggleMod = (modType == 22) -- Xenon lights

            if count > 0 or isToggleMod then
                local label = CosmeticLabels[modType] or ("Mod Type " .. modType)

                cosmetics[#cosmetics + 1] = {
                    modType = modType,
                    label = label,
                    count = count,
                    isToggle = isToggleMod
                }
            end
        end
    end
    
    return cosmetics
end

-- Open cosmetics list menu
local function openCosmeticsMenu(veh)
    local cosmetics = getVehicleCosmetics(veh)
    
    if not cosmetics or #cosmetics == 0 then
        QBCore.Functions.Notify('No cosmetic options available for this vehicle', 'error')
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local displayName = GetLabelText(modelName); if displayName == 'NULL' then displayName = modelName end

    local menu = {
        { header = 'Available Cosmetics', txt = string.format('%s | Plate: %s', displayName, plate), isMenuHeader = true }
    }

    table.sort(cosmetics, function(a, b) return a.label < b.label end)

    for _, cosmetic in ipairs(cosmetics) do
        local bracket = cosmetic.isToggle and '[ On/Off ]' or ('[ %d Options ]'):format(cosmetic.count)
        local headerText = ('%s - %s'):format(cosmetic.label, bracket)
        menu[#menu+1] = {
            header = headerText,
            txt = 'Options available',  -- CHANGED: display only
            params = {}                 -- CHANGED: non-clickable
        }
    end

    menu[#menu+1] = { header = 'Back',  params = { event = 'pf-mechanicjob:client:openMechanicTools' } }
    if Config.MenuSystem ~= 'ox_lib' then
        menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    end

    OpenMenu(menu)
end

-- Helper: progress bar (import from main.lua or define locally)
local function DoProgress(label, ms, dict, anim)
    ms = tonumber(ms) or 3000
    label = label or 'Working...'
    local ped = PlayerPedId()

    -- anim (optional)
    if dict and anim then
        if not HasAnimDictLoaded(dict) then
            RequestAnimDict(dict)
            while not HasAnimDictLoaded(dict) do Wait(0) end
        end
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end

    -- Try multiple progress bar systems
    -- 1) ox_lib
    local function resourceActive(name)
        local st = GetResourceState(name)
        return st == 'started' or st == 'starting'
    end

    if resourceActive('ox_lib') and lib and lib.progressCircle then
        local ok = lib.progressCircle({
            duration = ms,
            position = 'bottom',
            label = label,
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true, mouse = false }
        })
        ClearPedTasks(ped)
        return ok and true or false
    end

    -- 2) QBCore.Functions.Progressbar
    if QBCore and QBCore.Functions and type(QBCore.Functions.Progressbar) == 'function' then
        local finished, cancelled = false, true
        QBCore.Functions.Progressbar(
            'pf_mech_prog',
            label,
            ms,
            false,
            true,
            { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
            dict and { animDict = dict, anim = anim, flags = 49 } or {},
            {},
            function() cancelled=false; finished=true end,
            function() cancelled=true;  finished=true end
        )
        while not finished do Wait(25) end
        ClearPedTasksImmediately(ped)
        return not cancelled
    end

    -- 3) Fallback: simple wait
    local untilAt = GetGameTimer() + ms
    while GetGameTimer() < untilAt do
        DisableControlAction(0, 21, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 22, true)
        Wait(0)
    end
    ClearPedTasks(ped)
    return true
end

-- Helper: Get normalized plate
local function _GetPlate(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
end

-- Helper: Check if DPF is removed (FIX: Access CoalVehicles from rolling_coal.lua properly)
local function IsDPFRemoved(veh)
    local plate = _GetPlate(veh)
    if not plate then return false end
    
    -- Wait for state to sync
    Wait(100)
    
    -- Try to get state from exports (more reliable)
    local removed = false
    pcall(function()
        removed = exports['pf-mechanicjob']:IsCoalActiveForVehicle(veh)
    end)
    
    if Config.Debug then
        print(string.format('[DPF CHECK] plate=%s removed=%s', plate, tostring(removed)))
    end
    
    return removed
end

-- CHANGE: make OpenMenu global (remove 'local') so other earlier functions can call it
function OpenMenu(menu)
    local useOx = (Config and Config.MenuSystem == 'ox_lib')
    if useOx then
        local function resourceStarted(name)
            local st = GetResourceState(name)
            return st == 'started' or st == 'starting'
        end
        if resourceStarted('ox_lib') and lib and lib.registerContext then
            local contextId = 'pf_mech_tools_' .. GetGameTimer()
            local title, options = 'Mechanic Tools', {}
            for _, item in ipairs(menu) do
                if item.isMenuHeader then
                    if item.header then title = item.header end
                else
                    local hasEvent = (item.params and item.params.event)
                    options[#options+1] = {
                        title = item.header or '',
                        description = item.txt or '',
                        disabled = not hasEvent,
                        onSelect = function()
                            if hasEvent then
                                TriggerEvent(item.params.event, item.params.args)
                            end
                        end
                    }
                end
            end
            lib.registerContext({ id = contextId, title = title, options = options })
            lib.showContext(contextId)
            return
        end
    end
    if exports['pfm-menu'] and exports['pfm-menu'].openMenu then
        exports['pfm-menu']:openMenu(menu)
    else
        QBCore.Functions.Notify('Menu system not found', 'error')
    end
end

-- Open upgrade display menu
RegisterNetEvent('pf-mechanicjob:client:openUpgradeMenu', function()
    local veh = nearbyVeh(6.0)
    
    if veh == 0 then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local displayName = GetLabelText(modelName); if displayName == 'NULL' then displayName = modelName end
    
    local upgrades = getVehicleUpgrades(veh)
    
    if not upgrades then
        QBCore.Functions.Notify('Unable to read vehicle upgrades', 'error')
        return
    end
    
    -- Build menu
    local menu = {
        { header = 'Vehicle Performance Upgrades', txt = string.format('%s | Plate: %s', displayName, plate), isMenuHeader = true }
    }
    
    -- Add upgrade entries (removed armor)
    local upgradeOrder = {'engine', 'brakes', 'transmission', 'suspension', 'turbo'}
    
    for _, key in ipairs(upgradeOrder) do
        local upgrade = upgrades[key]
        if upgrade and upgrade.max > 0 then
            -- CHANGED: allow removal from any installed level (>=0)
            local canDowngrade = (key == 'turbo' and upgrade.current >= 0) or (key ~= 'turbo' and upgrade.current >= 0)
            local header = upgrade.label
            local txt = upgrade.levelName
            
            -- Determine if upgrade can be downgraded
            local downgradeParams = canDowngrade and {
                event = 'pf-mechanicjob:client:downgradeUpgrade',
                args = { 
                    vehicle = veh, 
                    upgradeType = key,
                    modType = key == 'engine' and 11 or 
                             key == 'brakes' and 12 or 
                             key == 'transmission' and 13 or 
                             key == 'suspension' and 15 or 
                             key == 'turbo' and 18 or 11,
                    currentLevel = upgrade.current
                }
            } or {}
            
            menu[#menu+1] = {
                header = header,
                txt = txt,
                params = downgradeParams
            }
        else
            -- Upgrade not available for this vehicle
            menu[#menu+1] = {
                header = upgrade.label,
                txt = 'Not available for this vehicle',
                params = {}
            }
        end
    end
    
    -- NEW: Add DPF section for diesel vehicles
    if Config.IsDieselCandidate(veh) then
        menu[#menu+1] = { header = '--- Diesel Systems ---', isMenuHeader = true }
        
        local dpfRemoved = IsDPFRemoved(veh)
        
        menu[#menu+1] = {
            header = 'Diesel Particulate Filter (DPF)',
            txt = dpfRemoved and '❌ Removed - Click to reinstall' or '✅ Installed - Click to remove',
            params = {
                event = dpfRemoved and 'pf-mechanicjob:client:installDPF' or 'pf-mechanicjob:client:removeDPF',
                args = { vehicle = veh, plate = plate }
            }
        }
    end
    
    -- Add cosmetics button
    menu[#menu+1] = {
        header = 'List of Possible Cosmetics',
        txt = 'View all available cosmetic modifications',
        params = { event = 'pf-mechanicjob:client:openCosmeticsMenu', args = { vehicle = veh } }
    }
    
    menu[#menu+1] = {
        header = 'Close',
        params = { event = 'qb-menu:client:closeMenu' }
    }
    
    -- Open menu (CHANGED: use new helper)
    OpenMenu(menu)
end)

-- Open cosmetics menu
RegisterNetEvent('pf-mechanicjob:client:openCosmeticsMenu', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    openCosmeticsMenu(veh)
end)

-- NEW: Handler for downgrading upgrades
RegisterNetEvent('pf-mechanicjob:client:downgradeUpgrade', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    -- Check if player is outside vehicle
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('You must be outside the vehicle', 'error')
        return
    end
    
    -- Check if engine is off
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn the engine off first', 'error')
        return
    end
    
    local upgradeType = data.upgradeType
    local modType = data.modType
    local currentLevel = data.currentLevel

    -- CHANGED: always revert to stock (-1) for non-turbo
    local newLevel = -1
    local itemToReturn = nil

    if upgradeType == 'turbo' then
        newLevel = -1
        itemToReturn = 'turbo'
    else
        -- Return the exact item for the level being removed
        -- currentLevel (0-based) + 1 gives item suffix
        if upgradeType == 'engine' then
            itemToReturn = 'engine' .. (currentLevel + 1)
        elseif upgradeType == 'brakes' then
            itemToReturn = 'brakes' .. (currentLevel + 1)
        elseif upgradeType == 'transmission' then
            itemToReturn = 'transmission' .. (currentLevel + 1)
        elseif upgradeType == 'suspension' then
            itemToReturn = 'suspension' .. (currentLevel + 1)
        end
    end
    
    local animDict = 'mini@repair'
    local animName = 'fixing_a_ped'
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    
    local progressTime = 6000
    local progressLabel = string.format('Removing %s upgrade...', upgradeType)
    
    if not DoProgress(progressLabel, progressTime, animDict, animName) then
        ClearPedTasks(ped)
        QBCore.Functions.Notify('Downgrade cancelled', 'error')
        return
    end
    
    ClearPedTasks(ped)
    
    SetVehicleModKit(veh, 0)
    
    if upgradeType == 'turbo' then
        ToggleVehicleMod(veh, 18, false)
        QBCore.Functions.Notify('Turbo removed', 'success', 3000)
    else
        SetVehicleMod(veh, modType, newLevel, false)  -- CHANGED: directly to stock
        QBCore.Functions.Notify(string.format('%s removed (reverted to stock)', upgradeType:gsub("^%l", string.upper)), 'success', 3000)
    end
    
    if itemToReturn then
        TriggerServerEvent('pf-mechanicjob:server:returnUpgradeItem', itemToReturn, NetworkGetNetworkIdFromEntity(veh))
    end
    
    TriggerServerEvent('pf-mechanicjob:server:syncUpgrade', {
        vehicle = NetworkGetNetworkIdFromEntity(veh),
        modType = modType,
        modIndex = newLevel,
        isTurbo = upgradeType == 'turbo'
    })
    
    Wait(200)
    TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
end)

-- NEW: Handler for removing DPF from menu
RegisterNetEvent('pf-mechanicjob:client:removeDPF', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    local plate = data and data.plate or _GetPlate(veh)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    if not Config.IsDieselCandidate(veh) then
        QBCore.Functions.Notify('Not a diesel vehicle', 'error')
        return
    end
    
    if IsDPFRemoved(veh) then
        QBCore.Functions.Notify('DPF already removed', 'error')
        return
    end
    
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('You must be outside the vehicle', 'error')
        return
    end
    
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn the engine off first', 'error')
        return
    end
    
    local animDict = 'mini@repair'
    local animName = 'fixing_a_ped'
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    
    if not DoProgress('Removing DPF...', Config.DPFRemoveTime or 6000, animDict, animName) then
        ClearPedTasks(ped)
        QBCore.Functions.Notify('DPF removal cancelled', 'error')
        return
    end
    
    ClearPedTasks(ped)
    TriggerServerEvent('pf_mech:dpf:remove', plate)
    QBCore.Functions.Notify('🚛 DPF removed! You received the DPF item', 'success', 5000)
    
    Wait(1000)
    TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
end)

-- NEW: Handler for using DPF item directly
RegisterNetEvent('pf-mechanicjob:client:useDPFItem', function()
    local veh = nearbyVeh(6.0)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    if not Config.IsDieselCandidate(veh) then
        QBCore.Functions.Notify('Not a diesel vehicle', 'error')
        return
    end
    
    local plate = _GetPlate(veh)
    
    if not IsDPFRemoved(veh) then
        QBCore.Functions.Notify('DPF already installed', 'error')
        return
    end
    
    TriggerEvent('pf-mechanicjob:client:installDPF', {
        vehicle = veh,
        plate = plate
    })
end)

-- FIXED: Handler for installing DPF from menu
RegisterNetEvent('pf-mechanicjob:client:installDPF', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    local plate = data and data.plate or _GetPlate(veh)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    if not Config.IsDieselCandidate(veh) then
        QBCore.Functions.Notify('Not a diesel vehicle', 'error')
        return
    end
    
    if not IsDPFRemoved(veh) then
        QBCore.Functions.Notify('DPF already installed', 'error')
        Wait(200)
        TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
        return
    end
    
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('You must be outside the vehicle', 'error')
        return
    end
    
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn the engine off first', 'error')
        return
    end
    
    QBCore.Functions.TriggerCallback('pf_mech:hasDPFItem', function(hasDPF)
        if not hasDPF then
            QBCore.Functions.Notify('You need a DPF filter to install it!', 'error')
            Wait(200)
            TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
            return
        end
        
        local animDict = 'mini@repair'
        local animName = 'fixing_a_ped'
        
        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do Wait(0) end
        
        TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0.0, false, false, false)
        
        if not DoProgress('Installing DPF...', Config.DPFInstallTime or 6000, animDict, animName) then
            ClearPedTasks(ped)
            QBCore.Functions.Notify('DPF installation cancelled', 'error')
            Wait(200)
            TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
            return
        end
        
        ClearPedTasks(ped)
        TriggerServerEvent('pf_mech:dpf:install', plate)
        QBCore.Functions.Notify('🚛 DPF installed! Rolling coal disabled', 'success', 5000)
        
        Wait(1000)
        TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
    end)
end)

-- NEW: Build unified mechanic tools menu
local function buildMechanicToolsMenu(veh)
    SetVehicleModKit(veh, 0)
    local plate = _GetPlate(veh) or 'UNKNOWN'
    local modelHash = GetEntityModel(veh)
    local modelDisp = GetLabelText(GetDisplayNameFromVehicleModel(modelHash))
    if modelDisp == 'NULL' then modelDisp = GetDisplayNameFromVehicleModel(modelHash) end

    local upgrades = getVehicleUpgrades(veh)

    local rows = {
        { header = ('Mechanic Tools • %s'):format(plate), txt = modelDisp, isMenuHeader = true },
        { header = '--- Performance Upgrades ---', isMenuHeader = true }
    }

    local perfOrder = {'engine','brakes','transmission','suspension','turbo'}
    for _, key in ipairs(perfOrder) do
        local up = upgrades[key]
        if up then
            -- CHANGED: allow removal from any installed level (>=0)
            local canDown = (key == 'turbo' and up.current >= 0) or (key ~= 'turbo' and up.current >= 0)
            
            local header = up.label
            local txt
            
            if key == 'turbo' then
                txt = up.current >= 0 and 'Installed' or 'Not Installed'
            else
                local levelPrefix = up.current == -1 and 'Stock:' or ('Level %d:'):format(up.current + 1)
                txt = ('%s [LVL %d/%d]'):format(levelPrefix, up.current == -1 and 0 or (up.current + 1), up.max)
            end
            
            rows[#rows+1] = {
                header = header,
                txt = txt,
                params = canDown and {
                    event = 'pf-mechanicjob:client:downgradeUpgrade',
                    args = {
                        vehicle = veh,
                        upgradeType = key,
                        modType = key == 'engine' and 11 or key == 'brakes' and 12 or key == 'transmission' and 13 or key == 'suspension' and 15 or 18,
                        currentLevel = up.current
                    }
                } or {}
            }
        end
    end

    -- NOS section (placed after performance list)
    local nosState = Entity(veh).state.nos
    if nosState and nosState.has then
        local nosLevel = math.floor(tonumber(nosState.level) or 0)
        local nosLevelSel = tonumber(nosState.levelSel) or 1

        rows[#rows+1] = { header = '--- NOS System ---', isMenuHeader = true }

        if nosLevel > 0 then
            rows[#rows+1] = {
                header = 'NOS',
                txt = string.format('Level: %d/3 | Remaining: %d%%', nosLevelSel, nosLevel),
                params = {}
            }
        else
            rows[#rows+1] = {
                header = 'NOS',
                txt = 'Empty - Click to remove bottle',
                params = {
                    event = 'pf-mechanicjob:client:removeEmptyNOS',
                    args = { vehicle = veh, plate = plate }
                }
            }
        end
    end

    -- DPF section
    if Config.IsDieselCandidate(veh) then
        local removed = IsDPFRemoved and IsDPFRemoved(veh)
        rows[#rows+1] = { header = '--- Diesel System ---', isMenuHeader = true }
        if removed then
            rows[#rows+1] = {
                header = 'DPF: Removed',
                txt = 'Install to disable coal',
                params = { event='pf-mechanicjob:client:installDPF', args={ vehicle=veh, plate=plate } }
            }
        else
            rows[#rows+1] = {
                header = 'DPF: Installed',
                txt = 'Remove to enable coal',
                params = { event='pf-mechanicjob:client:removeDPF', args={ vehicle=veh, plate=plate } }
            }
        end
    end

    -- Cosmetics button
    rows[#rows+1] = {
        header = 'List of Possible Cosmetics',
        txt = '',
        params = {
            event = 'pf-mechanicjob:client:openCosmeticsMenu',
            args = { vehicle = veh }
        }
    }

    rows[#rows+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }

    return rows
end

-- NEW: Unified mechanic tools menu event
RegisterNetEvent('pf-mechanicjob:client:openMechanicTools', function()
    local veh = nearbyVeh(6.0)
    if veh == 0 then QBCore.Functions.Notify('No vehicle nearby', 'error'); return end
    local menu = buildMechanicToolsMenu(veh)
    OpenMenu(menu)  -- CHANGED: use new helper
end)

-- NEW: Cosmetic detail viewer
RegisterNetEvent('pf-mechanicjob:client:viewCosmeticMod', function(data)
    local veh = data.vehicle
    if not veh or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error'); return
    end
    SetVehicleModKit(veh, 0)

    local modType = data.modType
    local count = tonumber(data.count) or 0
    local isToggle = data.isToggle
    local label = data.label or ('Mod '..modType)

    local menu = {
        { header = label, txt = ('Mod Type %d'):format(modType), isMenuHeader = true }
    }

    if isToggle then
        local on = IsToggleModOn(veh, modType)
        menu[#menu+1] = {
            header = on and 'Disable' or 'Enable',
            -- keep toggle without subtext
            params = {
                event = 'pf-mechanicjob:client:applyCosmeticToggle',
                args = { vehicle = veh, modType = modType, enable = not on }
            }
        }
    else
        for i=0,count-1 do
            menu[#menu+1] = {
                header = ('Option #%d'):format(i),
                -- removed: txt = 'Apply',
                params = {
                    event = 'pf-mechanicjob:client:applyCosmeticMod',
                    args = { vehicle = veh, modType = modType, index = i }
                }
            }
        end
    end

    menu[#menu+1] = { header='Back', params = { event='pf-mechanicjob:client:openMechanicTools' } }
    menu[#menu+1] = { header='Close', params = { event='qb-menu:client:closeMenu' } }
    OpenMenu(menu)  -- CHANGED: use new helper
end)

-- NEW: Apply cosmetic mod
RegisterNetEvent('pf-mechanicjob:client:applyCosmeticMod', function(data)
    local veh = data.vehicle
    if not veh or not DoesEntityExist(veh) then return end
    local idx = tonumber(data.index) or -1
    local modType = tonumber(data.modType) or 0
    SetVehicleModKit(veh, 0)
    if idx >= 0 then
        SetVehicleMod(veh, modType, idx, false)
        QBCore.Functions.Notify('Cosmetic applied', 'success')
    end
    Wait(300)
    TriggerEvent('pf-mechanicjob:client:openMechanicTools')

-- NEW: Handler for removing empty NOS bottle
RegisterNetEvent('pf-mechanicjob:client:removeEmptyNOS', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    local nosState = Entity(veh).state.nos
    if not nosState or not nosState.has then
        QBCore.Functions.Notify('No NOS installed', 'error')
        return
    end
    
    local nosLevel = math.floor(tonumber(nosState.level) or 0)
    if nosLevel > 0 then
        QBCore.Functions.Notify('NOS bottle is not empty yet', 'error')
        return
    end
    
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('You must be outside the vehicle', 'error')
        return
    end
    
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn the engine off first', 'error')
        return
    end
    
    local animDict = 'mini@repair'
    local animName = 'fixing_a_ped'
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    
    if not DoProgress('Removing empty NOS bottle...', 5000, animDict, animName) then
        ClearPedTasks(ped)
        QBCore.Functions.Notify('Removal cancelled', 'error')
        return
    end
    
    ClearPedTasks(ped)
    
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('pf_mech:nos:removeEmpty', netId)
    
    Wait(1000)
    TriggerEvent('pf-mechanicjob:client:openMechanicTools')
end)
end)

-- NEW: Toggle cosmetic mod
RegisterNetEvent('pf-mechanicjob:client:applyCosmeticToggle', function(data)
    local veh = data.vehicle
    if not veh or not DoesEntityExist(veh) then return end
    local modType = tonumber(data.modType) or 0
    ToggleVehicleMod(veh, modType, data.enable and true or false)
    QBCore.Functions.Notify(data.enable and 'Enabled' or 'Disabled', 'success')
    Wait(300)
    TriggerEvent('pf-mechanicjob:client:openMechanicTools')
end)

-- Map a performance item to (modType, modIndex, isToggle)
local function resolvePerformanceItem(item, veh)
    item = tostring(item or '')
    if item:match('^engine%d+$') then
        local lvl = tonumber(item:match('^engine(%d+)$')) or 1
        return 11, math.max(0, lvl - 1), false
    elseif item:match('^brakes%d+$') then
        local lvl = tonumber(item:match('^brakes(%d+)$')) or 1
        return 12, math.max(0, lvl - 1), false
    elseif item:match('^transmission%d+$') then
        local lvl = tonumber(item:match('^transmission(%d+)$')) or 1
        return 13, math.max(0, lvl - 1), false
    elseif item:match('^suspension%d+$') then
        local lvl = tonumber(item:match('^suspension(%d+)$')) or 1
        local cnt = GetNumVehicleMods(veh, 15)
        return 15, math.min(math.max(0, lvl - 1), math.max(0, cnt - 1)), false
    elseif item:match('^armor%d+$') then
        local lvl = tonumber(item:match('^armor(%d+)$')) or 1
        local cnt = GetNumVehicleMods(veh, 16)
        return 16, math.min(math.max(0, lvl - 1), math.max(0, cnt - 1)), false
    elseif item == 'car_armor' then
        local cnt = GetNumVehicleMods(veh, 16)
        if cnt > 0 then
            return 16, cnt - 1, false  -- max available armor
        else
            return 16, -1, false
        end
    elseif item == 'turbo' then
        return 18, 0, true           -- toggle turbo on
    elseif item == 'headlights' then
        return 22, 0, true           -- toggle xenon lights on
    elseif item == 'drifttires' then
        return -101, 0, true         -- custom toggle (reduce grip)
    elseif item == 'bprooftires' then
        return -102, 0, true         -- custom toggle (bulletproof tires)
    end
    return nil, nil, nil
end

-- Use performance item -> apply upgrade via server
RegisterNetEvent('pf-mechanicjob:client:usePerformanceItem', function(item)
    local veh = nearbyVeh and nearbyVeh(6.0) or 0
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error'); return
    end
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn engine off first', 'error'); return
    end
    SetVehicleModKit(veh, 0)

    local modType, modIndex, isToggle = resolvePerformanceItem(item, veh)
    if not modType then
        QBCore.Functions.Notify('Unsupported performance item', 'error'); return
    end

    -- Clamp index to available options (for non-toggle)
    if not isToggle and modIndex and modType >= 0 then
        local count = GetNumVehicleMods(veh, modType)
        if count <= 0 then
            QBCore.Functions.Notify('No variants for this vehicle', 'error'); return
        end
        modIndex = math.min(modIndex, count - 1)
    end

    local pretty = (item:gsub('_',' ')):gsub('^%l', string.upper)
    if not DoProgress('Installing '..pretty..'...', (Config.ActionTimes.setMod or 4500), 'mini@repair', 'fixing_a_ped') then
        QBCore.Functions.Notify('Installation cancelled', 'error'); return
    end

    TriggerServerEvent('pf_mech:server:applyPerformanceUpgrade', {
        vehicle = NetworkGetNetworkIdFromEntity(veh),
        item = item,
        modType = modType,
        modIndex = modIndex,
        isToggle = isToggle
    })
end)

-- Apply upgrade broadcast from server (all clients)
local function applyUpgrade(payload)
    if type(payload) ~= 'table' then return end
    local veh = NetworkGetEntityFromNetworkId(payload.vehicle or 0)
    if veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)

    local function getDriftCacheKey(vehicle)
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId and netId > 0 then
            return ('net:%s'):format(netId)
        end
        return ('ent:%s'):format(vehicle)
    end

    -- Reuseable local cache (stored on function object to avoid extra globals).
    applyUpgrade._driftCache = applyUpgrade._driftCache or {}

    local function setDriftTireProfile(vehicle, enabled)
        local key = getDriftCacheKey(vehicle)
        local cached = applyUpgrade._driftCache[key]

        if enabled then
            if not cached then
                cached = {
                    tractionMin = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveMin'),
                    tractionMax = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveMax'),
                    lowSpeedTractionLoss = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fLowSpeedTractionLossMult'),
                    driveForce = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce'),
                    driveInertia = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fDriveInertia'),
                }
                applyUpgrade._driftCache[key] = cached
            end

            if type(SetDriftTyresEnabled) == 'function' then
                SetDriftTyresEnabled(vehicle, true)
            end
            if type(SetReduceDriftVehicleSuspension) == 'function' then
                SetReduceDriftVehicleSuspension(vehicle, true)
            end
            SetVehicleReduceGrip(vehicle, false)

            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveMin', cached.tractionMin * 0.92)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveMax', cached.tractionMax * 0.95)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fLowSpeedTractionLossMult', cached.lowSpeedTractionLoss * 0.45)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', cached.driveForce * 0.82)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fDriveInertia', cached.driveInertia * 0.92)

            Entity(vehicle).state:set('pfDriftTires', true, true)
            return
        end

        if type(SetDriftTyresEnabled) == 'function' then
            SetDriftTyresEnabled(vehicle, false)
        end
        if type(SetReduceDriftVehicleSuspension) == 'function' then
            SetReduceDriftVehicleSuspension(vehicle, false)
        end
        SetVehicleReduceGrip(vehicle, false)

        if cached then
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveMin', cached.tractionMin)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveMax', cached.tractionMax)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fLowSpeedTractionLossMult', cached.lowSpeedTractionLoss)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', cached.driveForce)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fDriveInertia', cached.driveInertia)
        end

        Entity(vehicle).state:set('pfDriftTires', false, true)
    end

    if payload.isToggle then
        if payload.modType == 18 then
            ToggleVehicleMod(veh, 18, true)                 -- turbo on
        elseif payload.modType == 22 then
            ToggleVehicleMod(veh, 22, true)                 -- xenon on
        elseif payload.modType == -101 then
            setDriftTireProfile(veh, true)                  -- drift tires
        elseif payload.modType == -102 then
            SetVehicleTyresCanBurst(veh, false)             -- bulletproof tires
        end
    else
        local idx = tonumber(payload.modIndex) or -1
        local mtype = tonumber(payload.modType) or -1
        if idx >= 0 and mtype >= 0 then
            local cnt = GetNumVehicleMods(veh, mtype)
            if cnt > 0 then
                SetVehicleMod(veh, mtype, math.min(idx, cnt - 1), false)
            end
        end
    end
end

RegisterNetEvent('pf-mechanicjob:client:upgradeApplied', applyUpgrade)
RegisterNetEvent('pf_mech:client:upgradeApplied', applyUpgrade)

-- ================== NOS PURGE FX (bonnet offsets) ==================
local PurgeFX = { active = {} }
local PURGE_DICT, PURGE_NAME = 'core', 'ent_sht_steam'
local SOUND_BANK, SOUND_NAME = 'CARWASH_SOUNDS', 'SPRAY'

local function _vehHasNOS(veh)
  local st = Entity(veh).state
  local nos = st and st.nos
  return nos and nos.has == true and (tonumber(nos.level) or 0) > 0
end

local function _loadPurgePtfx()
  RequestNamedPtfxAsset(PURGE_DICT)
  local untilAt = GetGameTimer() + 1500
  while not HasNamedPtfxAssetLoaded(PURGE_DICT) do
    if GetGameTimer() > untilAt then break end
    Wait(0)
  end
  return HasNamedPtfxAssetLoaded(PURGE_DICT)
end

local function _bonnetLocalOffset(veh)
  local idx = GetEntityBoneIndexByName(veh, 'bonnet')
  if idx == -1 then
    -- fallback: slight forward from vehicle origin
    return vector3(0.0, 0.65, 0.0)
  end
  local world = GetWorldPositionOfEntityBone(veh, idx)
  local off = GetOffsetFromEntityGivenWorldCoords(veh, world)
  if #(off) < 0.001 then off = vec3(0.0, 0.65, 0.0) end
  return off
end

local function _startPurge(veh, size)
  if not DoesEntityExist(veh) or PurgeFX.active[veh] then return end
  if not _loadPurgePtfx() then return end

  -- Optional sfx
  pcall(function()
    RequestAmbientAudioBank(SOUND_BANK, 0)
    PlaySoundFromEntity(-1, SOUND_NAME, veh, SOUND_BANK, false, 0)
  end)

  local base = _bonnetLocalOffset(veh)
  local scale = tonumber(size) or ((Config.NOS and Config.NOS.purge and Config.NOS.purge.scale) or 1.0)

  UseParticleFxAssetNextCall(PURGE_DICT)
  local left = StartParticleFxLoopedOnEntity(PURGE_NAME, veh, base.x - 0.2, base.y + 0.5, base.z, 40.0, -20.0, 0.0, scale, false, false, false)

  UseParticleFxAssetNextCall(PURGE_DICT)
  local right = StartParticleFxLoopedOnEntity(PURGE_NAME, veh, base.x + 0.2, base.y + 0.5, base.z, 40.0,  20.0, 0.0, scale, false, false, false)

  PurgeFX.active[veh] = { left = left, right = right }
end

local function _stopPurge(veh)
  local h = PurgeFX.active[veh]; if not h then return end
  pcall(function() if h.left  then StopParticleFxLooped(h.left,  true) end end)
  pcall(function() if h.right then StopParticleFxLooped(h.right, true) end end)
  PurgeFX.active[veh] = nil
end

-- Public events (optional external control)
RegisterNetEvent('pf_mech:nos:purge:start', function(size)
  local ped = PlayerPedId()
  if not IsPedInAnyVehicle(ped, false) then return end
  local veh = GetVehiclePedIsIn(ped, false)
  if _vehHasNOS(veh) then _startPurge(veh, size) end
end)
RegisterNetEvent('pf_mech:nos:purge:stop', function()
  local ped = PlayerPedId()
  if not IsPedInAnyVehicle(ped, false) then return end
  local veh = GetVehiclePedIsIn(ped, false)
  _stopPurge(veh)
end)

-- Key watcher: hold purge key to spray
CreateThread(function()
  local keyPurge = (Config.NOS and Config.NOS.keys and Config.NOS.keys.purge) or 36 -- Left Ctrl
  local wasHeld = false
  while true do
    Wait(0)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
      wasHeld = false
      goto cont
    end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
      if wasHeld then _stopPurge(veh) end
      wasHeld = false
      goto cont
    end

    local held = IsControlPressed(0, keyPurge)
    if held and _vehHasNOS(veh) then
      if not wasHeld then _startPurge(veh, nil) end
      wasHeld = true
    else
      if wasHeld then _stopPurge(veh) end
      wasHeld = false
    end
    ::cont::
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for veh,_ in pairs(PurgeFX.active) do _stopPurge(veh) end
end)
