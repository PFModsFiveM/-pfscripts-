local QBCore = PFMdt.GetCore()

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end

-- If the new Auto Calls system is enabled, skip legacy callouts to avoid duplicates.
if Config and Config.DispatchAutoCalls and Config.DispatchAutoCalls.Enabled == true then
    dprint('^3[PF MDT]^7 DispatchAutoCalls enabled; skipping legacy dispatch_callouts.lua')
    return
end

local function cfgFor(calloutType)
    local t = tostring(calloutType or ''):lower()
    local c = Config and Config.DispatchCallouts and Config.DispatchCallouts[t] or nil
    if not c or c.enabled == false then return nil end
    return c
end

dprint('[MDT DISPATCH] Client loaded. Gunshot config: ' .. tostring(cfgFor('gunshot') ~= nil))

local function getLocationLabel(coords)
    if not coords then return 'Unknown' end
    local x, y, z = coords.x, coords.y, coords.z
    if x == nil or y == nil or z == nil then return 'Unknown' end

    local streetHash, crossHash = GetStreetNameAtCoord(x, y, z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or nil
    local cross = crossHash and crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or nil
    local zone = GetLabelText(GetNameOfZone(x, y, z))

    if street and cross and cross ~= '' and cross ~= street then
        return (street .. ' / ' .. cross)
    end
    if street and street ~= '' then
        return street
    end
    if zone and zone ~= '' and zone ~= 'NULL' then
        return zone
    end
    return 'Unknown'
end

local function sendCallout(calloutType, coords)
    if not cfgFor(calloutType) then return end
    coords = coords or GetEntityCoords(PlayerPedId())
    local c = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
    dprint('[MDT DISPATCH] sendCallout: ' .. calloutType .. ' at ' .. c.x .. ', ' .. c.y .. ', ' .. c.z)
    TriggerServerEvent('pf_emsmdt_dispatch:server:CreateCallout', tostring(calloutType), c, getLocationLabel(c))
end

-- Gunshots
CreateThread(function()
    local last = 0
    while true do
        Wait(200)
        if not cfgFor('gunshot') then
            Wait(1500)
        else
            local ped = PlayerPedId()
            if ped ~= 0 and IsPedShooting(ped) then
                local now = GetGameTimer()
                local cd = (cfgFor('gunshot').cooldownSeconds or Config.DispatchCalloutsDefaultCooldownSeconds or 30) * 1000
                if (now - last) >= cd then
                    last = now
                    dprint('[MDT DISPATCH] Gunshot detected, sending callout')
                    sendCallout('gunshot', GetEntityCoords(ped))
                end
            end
        end
    end
end)

-- Murder / fatal damage
CreateThread(function()
    local last = 0
    AddEventHandler('gameEventTriggered', function(name, args)
        if name ~= 'CEventNetworkEntityDamage' then return end
        if not cfgFor('murder') then return end

        local victim = args[1]
        local attacker = args[2]
        if not victim or not attacker then return end

        local ped = PlayerPedId()
        if attacker ~= ped then return end
        if victim == ped then return end

        -- Only trigger once the victim is dead.
        if not IsEntityDead(victim) then return end

        local now = GetGameTimer()
        local cd = (cfgFor('murder').cooldownSeconds or Config.DispatchCalloutsDefaultCooldownSeconds or 30) * 1000
        if (now - last) < cd then return end
        last = now

        sendCallout('murder', GetEntityCoords(victim))
    end)
end)

-- Grand Theft Auto (best-effort): triggers when player becomes driver of a vehicle flagged as stolen by GTA.
CreateThread(function()
    local last = 0
    local lastVeh = 0

    while true do
        Wait(500)
        if not cfgFor('gta') then
            Wait(2000)
        else
            local ped = PlayerPedId()
            if ped ~= 0 and IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                    if veh ~= lastVeh then
                        lastVeh = veh
                        if IsVehicleStolen(veh) then
                            local now = GetGameTimer()
                            local cd = (cfgFor('gta').cooldownSeconds or Config.DispatchCalloutsDefaultCooldownSeconds or 30) * 1000
                            if (now - last) >= cd then
                                last = now
                                sendCallout('gta', GetEntityCoords(veh))
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

-- Robbery callouts are usually triggered by other scripts.
-- Any script (client or server) can trigger:
--   TriggerServerEvent('pf_emsmdt_dispatch:server:CreateCallout', 'robbery', coords, locationLabel)
