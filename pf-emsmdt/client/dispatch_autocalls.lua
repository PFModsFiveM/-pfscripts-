local QBCore = PFMdt.GetCore()

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end

-- ============================================================================
-- MDT Dispatch Auto Calls (Client)
-- Detect: Shots Fired, Vehicle Theft, Homicide
-- Sends authoritative-ish events to server for validation + call creation.
-- ============================================================================

local function isEnabled()
    return Config and Config.DispatchAutoCalls and Config.DispatchAutoCalls.Enabled == true
end

local function getCooldownSeconds(key, fallback)
    if not Config or not Config.DispatchAutoCalls then
        return fallback
    end

    -- Current schema: DispatchAutoCalls.Calls[mappedKey].cooldown
    if type(Config.DispatchAutoCalls.Calls) == 'table' then
        local mappedKey = key
        if key == 'ShotsFired' then mappedKey = 'Shooting'
        elseif key == 'VehicleTheft' then mappedKey = 'CarJack'
        elseif key == 'Homicide' then mappedKey = 'PlayerDead'
        end

        local meta = Config.DispatchAutoCalls.Calls[mappedKey] or Config.DispatchAutoCalls.Calls[key]
        if type(meta) == 'table' then
            local v = tonumber(meta.cooldown or meta.cooldownSeconds)
            return v or fallback
        end
    end

    -- Legacy schema: DispatchAutoCalls.Cooldowns[key]
    if type(Config.DispatchAutoCalls.Cooldowns) == 'table' then
        local v = tonumber(Config.DispatchAutoCalls.Cooldowns[key])
        return v or fallback
    end

    return fallback
end

local function getLocationLabel(coords)
    if not coords then return 'Unknown' end
    local x, y, z = coords.x, coords.y, coords.z
    if x == nil or y == nil or z == nil then return 'Unknown' end

    local streetHash, crossHash = GetStreetNameAtCoord(x, y, z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or nil
    local cross = crossHash and crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or nil
    local zone = GetLabelText(GetNameOfZone(x, y, z))

    -- Prefer "Street / Cross", otherwise "Street, Zone"
    if street and cross and cross ~= '' and cross ~= street then
        return (street .. ' / ' .. cross)
    end
    if street and zone and zone ~= '' and zone ~= 'NULL' then
        return (street .. ', ' .. zone)
    end
    if street and street ~= '' then
        return street
    end
    if zone and zone ~= '' and zone ~= 'NULL' then
        return zone
    end
    return 'Unknown'
end

local function resolveWeaponLabel(weaponHash)
    if not weaponHash or weaponHash == 0 then return nil end

    local shared = QBCore and QBCore.Shared and QBCore.Shared.Weapons or nil
    if type(shared) == 'table' then
        for _, w in pairs(shared) do
            if type(w) == 'table' then
                if w.hash and tonumber(w.hash) == tonumber(weaponHash) then
                    return w.label or w.name
                end
                if w.name and GetHashKey(w.name) == weaponHash then
                    return w.label or w.name
                end
            end
        end
    end

    -- Fallback: just return the hash
    return nil
end

local function getVehicleModelLabel(veh)
    if not veh or veh == 0 then return nil end
    local model = GetEntityModel(veh)
    if not model or model == 0 then return nil end
    local display = GetDisplayNameFromVehicleModel(model)
    if display and display ~= '' then
        local label = GetLabelText(display)
        if label and label ~= '' and label ~= 'NULL' then
            return label
        end
        return display
    end
    return nil
end

local function safeHasKeys(plate)
    if not plate or plate == '' then return nil end
    if GetResourceState('pfm-vehiclekeys') ~= 'started' then
        return nil
    end

    local ok, res = pcall(function()
        return exports['pfm-vehiclekeys']:HasKeys(plate)
    end)

    if not ok then
        return nil
    end

    return res == true
end

-- Client-side cooldowns (extra safety; server also enforces cooldowns)
local lastClientTrigger = {
    ShotsFired = 0,
    VehicleTheft = 0,
    Homicide = 0,
}

local function canTriggerClient(key, cdSeconds)
    local now = GetGameTimer()
    local last = lastClientTrigger[key] or 0
    if (now - last) < (cdSeconds * 1000) then
        return false
    end
    lastClientTrigger[key] = now
    return true
end

-- ============================================================================
-- SHOTS FIRED (10-71)
-- ============================================================================

CreateThread(function()
    if not isEnabled() then return end

    local wasShooting = false
    while true do
        Wait(150)

        if not isEnabled() then
            Wait(1000)
        else
            local ped = PlayerPedId()
            if ped ~= 0 then
                local shooting = IsPedShooting(ped)
                if shooting and not wasShooting then
                    wasShooting = true

                    local cd = getCooldownSeconds('ShotsFired', 30)
                    if canTriggerClient('ShotsFired', cd) then
                        local coords = GetEntityCoords(ped)
                        local weaponHash = GetSelectedPedWeapon(ped)
                        local weaponLabel = resolveWeaponLabel(weaponHash)
                        TriggerServerEvent('pf_emsmdt:dispatch:shotsFired', {
                            coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
                            weaponHash = weaponHash,
                            weaponLabel = weaponLabel,
                            locationLabel = getLocationLabel({ x = coords.x, y = coords.y, z = coords.z })
                        })
                    end
                elseif not shooting and wasShooting then
                    -- reset once the burst stops
                    wasShooting = false
                end
            end
        end
    end
end)

-- ============================================================================
-- VEHICLE THEFT (10-60)
-- ============================================================================

CreateThread(function()
    if not isEnabled() then return end

    local lastVeh = 0

    while true do
        Wait(500)

        if not isEnabled() then
            Wait(1500)
        else
            local ped = PlayerPedId()
            if ped ~= 0 and IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                    if veh ~= lastVeh then
                        lastVeh = veh

                        local cd = getCooldownSeconds('VehicleTheft', 60)
                        if canTriggerClient('VehicleTheft', cd) then
                            local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s*(.-)%s*$', '%1')
                            local hasKeys = safeHasKeys(plate)

                            -- If qb-vehiclekeys is present, require no-keys. Otherwise best-effort using GTA stolen flag.
                            local theftLikely = false
                            if hasKeys == false then
                                theftLikely = true
                            elseif hasKeys == nil and IsVehicleStolen(veh) then
                                theftLikely = true
                            end

                            if theftLikely then
                                local coords = GetEntityCoords(veh)
                                local model = GetEntityModel(veh)
                                local modelLabel = getVehicleModelLabel(veh)

                                TriggerServerEvent('pf_emsmdt:dispatch:vehicleTheft', {
                                    coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
                                    plate = plate,
                                    model = model,
                                    modelLabel = modelLabel,
                                    locationLabel = getLocationLabel({ x = coords.x, y = coords.y, z = coords.z })
                                })
                            end
                        end
                    end
                end
            else
                lastVeh = 0
            end
        end
    end
end)

-- ============================================================================
-- HOMICIDE / MURDER (10-55)
-- Client-side detection using gameEventTriggered; forwarded to server.
-- ============================================================================

CreateThread(function()
    if not isEnabled() then return end

    AddEventHandler('gameEventTriggered', function(name, args)
        if not isEnabled() then return end
        if name ~= 'CEventNetworkEntityDamage' then return end

        local victim = args[1]
        local attacker = args[2]
        if not victim or not attacker then return end

        local ped = PlayerPedId()
        if attacker ~= ped then return end
        if victim == ped then return end

        -- Only trigger once victim is dead.
        if not IsEntityDead(victim) then return end

        local cd = getCooldownSeconds('Homicide', 30)
        if not canTriggerClient('Homicide', cd) then return end

        local vCoords = GetEntityCoords(victim)
        local victimType = IsPedAPlayer(victim) and 'player' or 'civilian'

        TriggerServerEvent('pf_emsmdt:dispatch:homicide', {
            coords = { x = vCoords.x + 0.0, y = vCoords.y + 0.0, z = vCoords.z + 0.0 },
            victimType = victimType,
            locationLabel = getLocationLabel({ x = vCoords.x, y = vCoords.y, z = vCoords.z })
        })
    end)
end)

dprint('^2[PF MDT]^7 Dispatch Auto Calls client loaded')
