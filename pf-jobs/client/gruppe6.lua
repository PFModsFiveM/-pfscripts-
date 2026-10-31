local QBCore = exports['pfm-core']:GetCoreObject()
-- SAFEGUARD: Some cached/legacy client copy attempted to call CreateCallback causing nil error.
-- QBCore.Functions.CreateCallback is server-only; define a harmless stub client-side to avoid crashes
if QBCore and QBCore.Functions and QBCore.Functions.CreateCallback == nil then
    QBCore.Functions.CreateCallback = function(name, fn)
        print('[Gruppe6 Client] Ignored client-side CreateCallback for '..tostring(name))
        -- Immediately invoke provided function in a minimal way if passed (mirrors async pattern lightly)
        if type(fn) == 'function' then
            local ok, err = pcall(fn, -1, function() end)
            if not ok then
                print('[Gruppe6 Client] Stub callback error: '..tostring(err))
            end
        end
    end
end
-- Single-load guard: prevents duplicate handlers if script loaded twice
if _G.__PF_G6_CLIENT_LOADED then
    print('[Gruppe6 Client] Duplicate load detected; aborting second instance.')
    return
end
_G.__PF_G6_CLIENT_LOADED = true
local CurrentContract = nil
local CurrentVehicle = nil
local CurrentVehicleBlip = nil
local CurrentWaypointBlip = nil
local PickupZones = {}
local DepositZone = nil
local ReturnZone = nil -- legacy id (qb-target), no longer used
local ReturnWatcherActive = false
local StorageTargetAdded = false

-- DARK GREEN COLOR (850 for all Gruppe6 blips)
local G6_BLIP_COLOR = 26 -- Dark green

-- NEW: Global accept lock (prevents duplicate accepts)
local AcceptInProgress = false

-- NEW: Create custom blip (doesn't override default waypoint)
local function CreateCustomBlip(coords, sprite, color, text, scale)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, scale or 0.8)
    SetBlipColour(blip, color)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(text)
    EndTextCommandSetBlipName(blip)
    return blip
end

-- NEW: Remove custom blip
local function RemoveCustomBlip(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    return nil
end

local function SendScoreboardMessage(payload)
    if GetResourceState('pf-tablet') == 'started' then
        local ok = pcall(function()
            exports['pf-tablet']:SendNuiMessage(payload)
        end)
        if ok then return end
    end

    SendNUIMessage(payload)
end

local function SendGruppe6Message(payload)
    if GetResourceState('pf-tablet') == 'started' then
        pcall(function()
            exports['pf-tablet']:SendNuiMessage(payload)
        end)
    end

    SendNUIMessage(payload)
end

local function ShowScoreboard(title, subtitle, progress)
    SendScoreboardMessage({
        action = 'scoreboard_open',
        title = title or 'Gruppe6 Contractor',
        subtitle = subtitle or '',
        progress = progress or ''
    })
end

local function UpdateScoreboard(title, subtitle, progress)
    SendScoreboardMessage({
        action = 'scoreboard_update',
        title = title or '',
        subtitle = subtitle or '',
        progress = progress or ''
    })
end

local function HideScoreboard()
    SendScoreboardMessage({
        action = 'scoreboard_close'
    })
end

local function OpenGruppe6()
    SetNuiFocus(true, true)
    SendGruppe6Message({ action = 'openApp', app = 'gruppe6', label = 'Gruppe6', icon = '🛡️' })
    
    -- Request state from server
    print('[Gruppe6 Client] Requesting state from server...')
    QBCore.Functions.TriggerCallback('pf-jobs:gruppe6:getState', function(state)
        print('[Gruppe6 Client] Received state:', json.encode(state))
        SendGruppe6Message({ action = 'gruppe6:init', state = state })
    end)
end

RegisterNetEvent('pf-jobs:client:openGruppe6', OpenGruppe6)

RegisterNUICallback('gruppe6:getInit', function(_, cb)
    print('[Gruppe6 Client] ======= NUI REQUESTING INIT STATE =======')
    QBCore.Functions.TriggerCallback('pf-jobs:gruppe6:getState', function(state)
        print('[Gruppe6 Client] ======= RECEIVED STATE FROM SERVER =======')
        print('[Gruppe6 Client] State XP:', state.xp)
        print('[Gruppe6 Client] State Level:', state.level)
        print('[Gruppe6 Client] Full state:', json.encode(state))
        print('[Gruppe6 Client] ======= SENDING TO NUI =======')
        SendGruppe6Message({ action = 'gruppe6:init', state = state })
        cb(true)
    end)
end)

RegisterNUICallback('gruppe6:startSearch', function(_, cb)
    ShowScoreboard('Gruppe6 Contractor', 'Waiting for job offer', '')
    TriggerServerEvent('pf-jobs:gruppe6:startSearch')
    cb(true)
end)

RegisterNUICallback('gruppe6:stopSearch', function(_, cb)
    HideScoreboard()
    TriggerServerEvent('pf-jobs:gruppe6:stopSearch')
    cb(true)
end)

RegisterNUICallback('gruppe6:acceptContract', function(data, cb)
    print('[Gruppe6 Client] Accept contract callback received:', json.encode(data))
    
    -- FIXED: Check global accept lock
    if AcceptInProgress then
        print('[Gruppe6 Client] ❌ Accept already in progress, blocking duplicate')
        cb(false)
        return
    end
    
    -- Set lock
    AcceptInProgress = true
    
    -- Send to server
    TriggerServerEvent('pf-jobs:gruppe6:acceptContract', data)
    
    -- Clear lock after 5 seconds
    Citizen.SetTimeout(5000, function()
        AcceptInProgress = false
        print('[Gruppe6 Client] 🔓 Accept lock cleared')
    end)
    
    cb(true)
end)

RegisterNUICallback('gruppe6:createGroup', function(data, cb)
    TriggerServerEvent('pf-jobs:gruppe6:createGroup')
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:invitePlayer', function(data, cb)
    if not data.targetId then
        cb({ success = false, error = 'No target ID provided' })
        return
    end
    TriggerServerEvent('pf-jobs:gruppe6:invitePlayer', tonumber(data.targetId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:kickMember', function(data, cb)
    if not data.targetId then
        cb({ success = false, error = 'No target ID provided' })
        return
    end
    TriggerServerEvent('pf-jobs:gruppe6:kickMember', tonumber(data.targetId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:updateSplit', function(data, cb)
    if not data.targetId or not data.percentage then
        cb({ success = false, error = 'Missing parameters' })
        return
    end
    TriggerServerEvent('pf-jobs:gruppe6:updateSplit', tonumber(data.targetId), tonumber(data.percentage))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:leaveGroup', function(data, cb)
    TriggerServerEvent('pf-jobs:gruppe6:leaveGroup')
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:disbandGroup', function(data, cb)
    TriggerServerEvent('pf-jobs:gruppe6:disbandGroup')
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:acceptInvite', function(data, cb)
    if not data.leaderId then
        cb({ success = false, error = 'No leader ID provided' })
        return
    end
    TriggerServerEvent('pf-jobs:gruppe6:acceptInvite', tonumber(data.leaderId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:declineInvite', function(data, cb)
    if not data.leaderId then
        cb({ success = false, error = 'No leader ID provided' })
        return
    end
    TriggerServerEvent('pf-jobs:gruppe6:declineInvite', tonumber(data.leaderId))
    cb({ success = true })
end)

RegisterNUICallback('gruppe6:endContract', function(_, cb)
    -- Early end: clear pickup state, remove waypoint, send request to server
    if CurrentWaypointBlip and DoesBlipExist(CurrentWaypointBlip) then
        SetBlipRoute(CurrentWaypointBlip, false)
        RemoveBlip(CurrentWaypointBlip)
        CurrentWaypointBlip = nil
    end
    ClearPickupZones()
    if CurrentContract then
        local depositLoc = Config.Gruppe6.DepositLocation
        CurrentWaypointBlip = CreateCustomBlip(depositLoc, 500, G6_BLIP_COLOR, 'Central Vault (Partial)', 1.0)
        SetBlipRoute(CurrentWaypointBlip, true)
        SetBlipRouteColour(CurrentWaypointBlip, G6_BLIP_COLOR)
        UpdateScoreboard('Gruppe6 Contractor', 'Partial deposit - deliver collected bags')
    end
    TriggerServerEvent('pf-jobs:gruppe6:endContract')
    cb(true)
end)

RegisterNUICallback('gruppe6:purchaseUpgrade', function(data, cb)
    TriggerServerEvent('pf-jobs:gruppe6:purchaseUpgrade', data.upgradeId)
    cb(true)
end)

RegisterNetEvent('pf-jobs:gruppe6:upgradesPurchased', function(upgrades)
    SendGruppe6Message({
        action = 'gruppe6:upgradesPurchased',
        upgrades = upgrades
    })
end)

RegisterNetEvent('pf-jobs:gruppe6:contractFound', function(contract)
    SendGruppe6Message({ action = 'gruppe6:contract', contract = contract })
end)

RegisterNetEvent('pf-jobs:gruppe6:updateXP', function(xp, level)
    SendGruppe6Message({ action = 'gruppe6:updateXP', xp = xp, level = level })
end)

RegisterNetEvent('pf-jobs:gruppe6:contracts', function(contracts)
    SendGruppe6Message({ action = 'gruppe6:contracts', contracts = contracts })
end)

RegisterNetEvent('pf-jobs:gruppe6:activeContract', function(contract)
    SendGruppe6Message({ action = 'gruppe6:activeContract', contract = contract })
end)

-- Group system update events
RegisterNetEvent('pf-jobs:gruppe6:groupUpdate', function(groupData)
    SendGruppe6Message({
        action = 'gruppe6:groupUpdate',
        group = groupData
    })
end)

RegisterNetEvent('pf-jobs:gruppe6:receiveInvite', function(inviterName, inviterId)
    -- Show notification and allow accept/decline
    QBCore.Functions.Notify(string.format('%s invited you to their Gruppe6 party!', inviterName), 'info', 5000)
    
    -- Send invite to NUI for display
    SendGruppe6Message({
        action = 'gruppe6:addInvite',
        invite = {
            leaderName = inviterName,
            leaderId = inviterId
        }
    })
end)

RegisterNetEvent('pf-jobs:gruppe6:startContract', function(data)
    -- Handle stale vehicle state from previous/failed runs before starting new contract
    if CurrentVehicle and DoesEntityExist(CurrentVehicle) then
        print('[Gruppe6 Client] Cleaning up stale vehicle before starting new contract')
        QBCore.Functions.DeleteVehicle(CurrentVehicle)
        CurrentVehicle = nil
        CurrentVehicleBlip = RemoveCustomBlip(CurrentVehicleBlip)
    end

    if VehicleSpawnInProgress then
        print('[Gruppe6 Client] ⚠️ startContract received while spawn in progress. Ignoring.')
        return
    end
    VehicleSpawnInProgress = true
    -- Clear accept lock immediately when contract starts
    AcceptInProgress = false
    
    CurrentContract = data
    CurrentContract.currentPickup = 1
    CurrentContract.totalPickups = #data.pickupSequence
    CurrentContract.bagsCollected = 0
    
    -- Show scoreboard (different message for non-leader party members)
    local myServerId = GetPlayerServerId(PlayerId())
    if not data.spawnOwner or data.spawnOwner == myServerId then
        ShowScoreboard('Gruppe6 Contractor', 'Grab your delivery vehicle')
    else
        ShowScoreboard('Gruppe6 Contractor', 'Leader preparing delivery vehicle')
    end
    
    -- Only spawn vehicle if this client is the designated spawnOwner (party leader)
    if not data.spawnOwner or data.spawnOwner == myServerId then
        local spawnCoords = vector4(data.spawnCoords.x, data.spawnCoords.y, data.spawnCoords.z, data.spawnCoords.w)
        print('[Gruppe6 Client] Requesting server-side vehicle spawn (leader):', data.vehicle)
        TriggerServerEvent('pf-jobs:gruppe6:spawnVehicle', data.vehicle, data.plate, spawnCoords)
    else
        print('[Gruppe6 Client] Skipping vehicle spawn; spawnOwner is', data.spawnOwner, 'I am', myServerId)
    end
    
    -- Timeout failsafe
    Citizen.SetTimeout(8000, function()
        if VehicleSpawnInProgress then
            print('[Gruppe6 Client] ⚠️ Spawn timeout')
            VehicleSpawnInProgress = false
        end
    end)
end)

-- Handle server-spawned vehicle
RegisterNetEvent('pf-jobs:gruppe6:vehicleSpawned', function(netId, plate, spawnOwner, spawnCoords)
    if not CurrentContract then return end

    print('[Gruppe6 Client] Received vehicle spawn, netId:', netId)

    -- Extended wait for network entity (slow propagation on remote clients)
    local timeout = 0
    while not NetworkDoesNetworkIdExist(netId) and timeout < 300 do -- up to ~3s
        Wait(10)
        timeout = timeout + 1
    end
    if not NetworkDoesNetworkIdExist(netId) then
        print('[Gruppe6 Client] ERROR: Vehicle network entity not found after extended wait')
        VehicleSpawnInProgress = false
        return
    end

    local veh = NetToVeh(netId)
    local entityTimeout = 0
    while (not veh or not DoesEntityExist(veh)) and entityTimeout < 200 do -- additional wait for entity creation
        Wait(10)
        veh = NetToVeh(netId)
        entityTimeout = entityTimeout + 1
    end
    if not veh or not DoesEntityExist(veh) then
        print('[Gruppe6 Client] ERROR: Vehicle entity does not exist after extended wait')
        VehicleSpawnInProgress = false
        return
    end

    print('[Gruppe6 Client] Vehicle entity obtained:', veh)

    CurrentVehicle = veh
    VehicleSpawnInProgress = false

    -- Create / refresh vehicle blip
    local vehCoords = GetEntityCoords(veh)
    CurrentVehicleBlip = RemoveCustomBlip(CurrentVehicleBlip)
    CurrentVehicleBlip = CreateCustomBlip(vehCoords, 477, G6_BLIP_COLOR, 'Gruppe6 Vehicle', 0.9)
    print('[Gruppe6 Client] Vehicle blip created:', CurrentVehicleBlip)

    -- Continuous vehicle blip position updater
    CreateThread(function()
        while CurrentVehicle and DoesEntityExist(CurrentVehicle) do
            if CurrentVehicleBlip and DoesBlipExist(CurrentVehicleBlip) then
                local coords = GetEntityCoords(CurrentVehicle)
                SetBlipCoords(CurrentVehicleBlip, coords.x, coords.y, coords.z)
            end
            Wait(1000)
        end
    end)

    local myServerId = GetPlayerServerId(PlayerId())
    -- Prefer contract.spawnOwner to avoid param mismatch; fall back to event param
    local leaderId = (CurrentContract and CurrentContract.spawnOwner) or spawnOwner
    local isLeader = (leaderId == myServerId)

    if isLeader then
        print('[Gruppe6 Client] (Leader) Setting vehicle keys for plate:', plate)
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
        AddVehicleStorageTarget()
    else
        print('[Gruppe6 Client] (Member) Vehicle spawned by leader', leaderId)
    end

    -- First pickup setup
    local firstIdx = CurrentContract.pickupSequence[1]
    local locationPool = CurrentContract.locationPool or Config.Gruppe6.PickupLocations
    local firstLoc = locationPool[firstIdx]
    local firstBagCount = CurrentContract.locationBags[1] or 0
    CurrentContract.locationPool = locationPool

    Wait(150) -- slight delay to allow all clients to sync

    -- Waypoint to first pickup (ensure fresh blip)
    CurrentWaypointBlip = RemoveCustomBlip(CurrentWaypointBlip)
    CurrentWaypointBlip = CreateCustomBlip(firstLoc, 850, G6_BLIP_COLOR, string.format('Pickup 1 (%d bags)', firstBagCount), 1.0)
    SetBlipRoute(CurrentWaypointBlip, true)
    SetBlipRouteColour(CurrentWaypointBlip, G6_BLIP_COLOR)

    if isLeader then
        QBCore.Functions.Notify(string.format('GPS set to pickup #1 (%d bags)', firstBagCount), 'info')
    else
        QBCore.Functions.Notify(string.format('Follow leader to pickup #1 (%d bags)', firstBagCount), 'info')
    end

    CreatePickupZone(firstLoc, firstIdx, 1, firstBagCount)

    -- Immediate scoreboard update to override initial "Grab your delivery vehicle"
    if isLeader then
        UpdateScoreboard('Gruppe6 Contractor', string.format('Drive to pickup %d/%d', CurrentContract.currentPickup, CurrentContract.totalPickups))
    else
        UpdateScoreboard('Gruppe6 Contractor', string.format('Follow leader to pickup 1/%d', CurrentContract.totalPickups))
    end

    -- Scoreboard updates
    if isLeader then
        -- Leader: update once inside vehicle then show driving prompt
        CreateThread(function()
            local waited = 0
            while CurrentContract and DoesEntityExist(CurrentVehicle) and waited < 40 do -- up to 20s
                Wait(500)
                waited = waited + 1
                if IsPedInVehicle(PlayerPedId(), CurrentVehicle, false) then
                    UpdateScoreboard('Gruppe6 Contractor', string.format('Drive to pickup %d/%d', CurrentContract.currentPickup, CurrentContract.totalPickups))
                    return
                end
            end
            -- Fallback if never detected inside (e.g., already inside before loop)
            UpdateScoreboard('Gruppe6 Contractor', string.format('Drive to pickup %d/%d', CurrentContract.currentPickup, CurrentContract.totalPickups))
        end)
    else
            -- Member: immediate guidance (not dependent on being in vehicle)
            UpdateScoreboard('Gruppe6 Contractor', string.format('Follow leader to pickup 1/%d', CurrentContract.totalPickups))
        -- Optional periodic refresh in case route/blips cleared
        CreateThread(function()
            local cycles = 0
            while CurrentContract and cycles < 30 do
                Wait(2000)
                cycles = cycles + 1
                if not CurrentWaypointBlip or not DoesBlipExist(CurrentWaypointBlip) then
                    -- Recreate waypoint if missing
                        CurrentWaypointBlip = CreateCustomBlip(firstLoc, 850, G6_BLIP_COLOR, string.format('Pickup 1 (%d bags)', firstBagCount), 1.0)
                    SetBlipRoute(CurrentWaypointBlip, true)
                    SetBlipRouteColour(CurrentWaypointBlip, G6_BLIP_COLOR)
                end
            end
        end)
    end

        -- Fallback vehicle blip recreation for members if entity lost
        CreateThread(function()
            local checks = 0
            while checks < 15 and CurrentVehicleBlip and DoesBlipExist(CurrentVehicleBlip) do
                Wait(2000)
                checks = checks + 1
                if not CurrentVehicle or not DoesEntityExist(CurrentVehicle) then
                    -- Try reacquire entity
                    local v = NetToVeh(netId)
                    if v and DoesEntityExist(v) then
                        CurrentVehicle = v
                    else
                        -- Create coord blip at spawnCoords if provided
                        if spawnCoords then
                            CurrentVehicleBlip = RemoveCustomBlip(CurrentVehicleBlip)
                            CurrentVehicleBlip = CreateCustomBlip(vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z), 477, G6_BLIP_COLOR, 'Gruppe6 Vehicle', 0.9)
                            print('[Gruppe6 Client] Fallback vehicle blip recreated at spawn coords')
                            break
                        end
                    end
                end
            end
        end)
end)

-- Adds qb-target interaction on the rear of the vehicle to open storage (stash)
function AddVehicleStorageTarget()
    if not CurrentVehicle or StorageTargetAdded then return end
    StorageTargetAdded = true
    local ok = pcall(function()
        exports['pfm-target']:AddTargetEntity(CurrentVehicle, {
            options = {
                {
                    type = 'client',
                    event = 'pf-jobs:gruppe6:openStorage',
                    icon = 'fas fa-box-open',
                    label = 'Open Storage',
                    canInteract = function()
                        local ped = PlayerPedId()
                        local rear = GetOffsetFromEntityInWorldCoords(CurrentVehicle, 0.0, -3.0, 0.0)
                        local dist = #(GetEntityCoords(ped) - rear)
                        return dist <= 3.0 and IsPedOnFoot(ped)
                    end
                }
            },
            distance = 2.5
        })
    end)
    if not ok then
        print('[Gruppe6 Client] qb-target AddTargetEntity failed; storage interaction not added')
    end
end

RegisterNetEvent('pf-jobs:gruppe6:openStorage', function()
    if not CurrentVehicle then return end
    local plate = string.gsub(GetVehicleNumberPlateText(CurrentVehicle) or 'G6', '%s+', '')
    -- Open rear doors for visual feedback (door index 2 and 3)
    SetVehicleDoorOpen(CurrentVehicle, 2, false, false)
    SetVehicleDoorOpen(CurrentVehicle, 3, false, false)
    -- Open vehicle trunk inventory directly (native qb-inventory support)
    TriggerServerEvent('inventory:server:OpenInventory', 'trunk', plate)
end)

-- Debug helper command to test opening storage without qb-target
RegisterCommand('g6storage', function()
    TriggerEvent('pf-jobs:gruppe6:openStorage')
end)

function CreatePickupZone(coords, locationIdx, pickupNum, bagCount)
    ClearPickupZones()
    exports['pfm-target']:AddBoxZone('gruppe6_pickup_' .. pickupNum, coords, 2.0, 2.0, {
        name = 'gruppe6_pickup_' .. pickupNum,
        heading = 0,
        debugPoly = false,
        minZ = coords.z - 1,
        maxZ = coords.z + 2,
    }, {
        options = {
            {
                type = 'client',
                event = 'pf-jobs:gruppe6:openPickupInventory',
                icon = 'fas fa-box',
                label = string.format('Collect Money Bags (%d bags)', bagCount),
                locationIdx = locationIdx,
                pickupNum = pickupNum,
                bagCount = bagCount,
            },
        },
        distance = 2.5,
    })
    table.insert(PickupZones, 'gruppe6_pickup_' .. pickupNum)
end

function ClearPickupZones()
    for _, zone in ipairs(PickupZones) do
        exports['pfm-target']:RemoveZone(zone)
    end
    PickupZones = {}
end

RegisterNetEvent('pf-jobs:gruppe6:openPickupInventory', function(data)
    local totalBags = CurrentContract and CurrentContract.locationBags[data.pickupNum] or 0
    UpdateScoreboard('Gruppe6 Contractor', string.format('Pickup %d/%d - Take %d bags from inventory', data.pickupNum, CurrentContract and CurrentContract.totalPickups or 0, totalBags))
    TriggerServerEvent('pf-jobs:gruppe6:openPickupStash', data.locationIdx, data.pickupNum)
    CreateThread(function()
        Wait(1000)
        local checkCount = 0
        while checkCount < 120 do
            Wait(500)
            checkCount = checkCount + 1
            if not IsNuiFocused() then
                TriggerServerEvent('pf-jobs:gruppe6:checkStashAfterClose', data.locationIdx, data.pickupNum)
                break
            end
        end
    end)
end)

-- Live updates to pickup remaining count across party members
RegisterNetEvent('pf-jobs:gruppe6:updatePickupRemaining', function(pickupNum, remaining)
    if not CurrentContract then return end
    local totalPickups = CurrentContract.totalPickups or 0
    local subtitle = remaining > 0 and string.format('Pickup %d/%d - %d bag(s) left', pickupNum, totalPickups, remaining) or string.format('Pickup %d/%d complete', pickupNum, totalPickups)
    UpdateScoreboard('Gruppe6 Contractor', subtitle)
end)

RegisterNetEvent('pf-jobs:gruppe6:nextPickup', function(nextLoc, nextIdx, bagCount)
    print('[Gruppe6 Client] 📍 Received nextPickup event')
    print('[Gruppe6 Client] Location:', json.encode(nextLoc), 'Bags:', bagCount)
    
    if CurrentContract then
        CurrentContract.currentPickup = CurrentContract.currentPickup + 1
        print('[Gruppe6 Client] Updated pickup counter to:', CurrentContract.currentPickup)
        
        -- Update scoreboard
        UpdateScoreboard(
            'Gruppe6 Contractor',
            string.format('Pickup %d/%d - GPS set', CurrentContract.currentPickup, CurrentContract.totalPickups),
            ''
        )
    end
    
    -- Clear previous pickup zones to avoid duplication
    ClearPickupZones()
    local pickupNum = CurrentContract and CurrentContract.currentPickup or 1
    CreatePickupZone(nextLoc, nextIdx, pickupNum, bagCount)
    
    -- Remove old blip and create new objective marker
    CurrentWaypointBlip = RemoveCustomBlip(CurrentWaypointBlip)
    CurrentWaypointBlip = CreateCustomBlip(nextLoc, 850, G6_BLIP_COLOR, string.format('Pickup #%d (%d bags)', pickupNum, bagCount), 1.0)
    SetBlipRoute(CurrentWaypointBlip, true)
    SetBlipRouteColour(CurrentWaypointBlip, G6_BLIP_COLOR)
    
    QBCore.Functions.Notify(string.format('GPS set to pickup #%d (%d bags)', pickupNum, bagCount), 'primary')
    
    -- FIXED: Shorter text
    UpdateScoreboard(
        'Gruppe6 Contractor',
        string.format('Pickup %d/%d', pickupNum, CurrentContract.totalPickups),
        'Drive to waypoint'
    )
    
    print('[Gruppe6 Client] ✅ Waypoint and zone created')
end)

RegisterNetEvent('pf-jobs:gruppe6:returnVehicle', function()
    print('[Gruppe6 Client] 🚗 No bags - return vehicle')
    
    ClearPickupZones()
    exports['pfm-target']:RemoveZone('gruppe6_deposit')
    
    CurrentWaypointBlip = RemoveCustomBlip(CurrentWaypointBlip)
    if CurrentVehicle and DoesEntityExist(CurrentVehicle) then
        local vehCoords = GetEntityCoords(CurrentVehicle)
        CurrentWaypointBlip = CreateCustomBlip(vehCoords, 477, G6_BLIP_COLOR, 'Return Vehicle', 1.0)
        SetBlipRoute(CurrentWaypointBlip, true)
        SetBlipRouteColour(CurrentWaypointBlip, G6_BLIP_COLOR)
    end
    
    UpdateScoreboard(
        'Gruppe6 Contractor',
        'Return vehicle - No bags collected'
    )
    
    QBCore.Functions.Notify('No bags collected. Return the vehicle.', 'error')
end)

RegisterNetEvent('pf-jobs:gruppe6:goToDeposit', function(depositLoc)
    print('[Gruppe6 Client] 🏦 Received goToDeposit event')
    
    ClearPickupZones()
    
    CurrentWaypointBlip = RemoveCustomBlip(CurrentWaypointBlip)
    CurrentWaypointBlip = CreateCustomBlip(depositLoc, 500, G6_BLIP_COLOR, 'Central Vault', 1.0)
    SetBlipRoute(CurrentWaypointBlip, true)
    SetBlipRouteColour(CurrentWaypointBlip, G6_BLIP_COLOR)
    
    QBCore.Functions.Notify('All pickups complete! Head to vault', 'success')
    
    -- FIXED: Shorter text
    local totalBags = CurrentContract and CurrentContract.bagsCollected or 0
    UpdateScoreboard(
        'Gruppe6 Contractor',
        'Drive to vault',
        string.format('%d bags total', totalBags)
    )
    
    -- Create deposit zone
    exports['pfm-target']:AddBoxZone('gruppe6_deposit', depositLoc, 2.0, 2.0, {
        name = 'gruppe6_deposit',
        heading = 0,
        debugPoly = false,
        minZ = depositLoc.z - 1,
        maxZ = depositLoc.z + 2,
    }, {
        options = {
            {
                type = 'client',
                event = 'pf-jobs:gruppe6:depositBags',
                icon = 'fas fa-hand-holding-usd',
                label = 'Deposit Money Bags',
            },
        },
        distance = 2.5,
    })
    
    print('[Gruppe6 Client] ✅ Deposit zone created')
end)

RegisterNetEvent('pf-jobs:gruppe6:depositBags', function()
    -- Check if vault is open (for main vault - Pacific Standard)
    local mainVaultIndex = 1 -- Assuming first vault in config is the main one
    if Config.Gruppe6.VaultDoors and Config.Gruppe6.VaultDoors[mainVaultIndex] then
        if not VaultDoorStates[mainVaultIndex] then
            QBCore.Functions.Notify('Vault door is locked! Use the security panel to open it first.', 'error')
            return
        end
    end
    
    -- Remove deposit waypoint blip
    UpdateScoreboard('Gruppe6 Contractor', 'Deliver collected bags to the central vault', 'Use the deposit point')
    QBCore.Functions.Progressbar('deposit_bags', 'Depositing money bags...', 2500, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function()
        TriggerServerEvent('pf-jobs:gruppe6:depositComplete')
    end, function() end)
end)

-- Receive deposit progress and decide next prompt
RegisterNetEvent('pf-jobs:gruppe6:depositProgress', function(deposited, total)
    if not CurrentContract then return end
    if deposited < total then
        UpdateScoreboard('Gruppe6 Contractor', string.format('Deposited %d/%d bags. Keep depositing.', deposited, total))
    else
        -- All bags deposited - now require vault closure
        local mainVaultIndex = 1
        if VaultDoorStates[mainVaultIndex] then
            QBCore.Functions.Notify('All bags deposited! Close the vault door before returning.', 'success')
            UpdateScoreboard('Gruppe6 Contractor', 'All bags deposited - Close vault door via security panel', 'Then return vehicle to HQ')
        else
            -- Vault already closed, proceed to return
            ProceedToVehicleReturn()
        end
    end
end)

function ProceedToVehicleReturn()
    -- Remove any existing deposit blip
    CurrentWaypointBlip = RemoveCustomBlip(CurrentWaypointBlip)
    UpdateScoreboard('Gruppe6 Contractor', 'Return the delivery vehicle back to HQ', 'Drive back to Gruppe6 depot')
    local returnLoc = vector3(-20.0, -703.57, 32.34)
    SetNewWaypoint(returnLoc.x, returnLoc.y)
    StartReturnAreaWatcher(returnLoc)
    -- If vehicle exists, create a blip on it titled Return Vehicle
    if CurrentVehicle and DoesEntityExist(CurrentVehicle) then
        CurrentVehicleBlip = RemoveCustomBlip(CurrentVehicleBlip)
        local vehCoords = GetEntityCoords(CurrentVehicle)
        CurrentVehicleBlip = CreateCustomBlip(vehCoords, 477, G6_BLIP_COLOR, 'Return Vehicle', 0.9)
        SetBlipRoute(CurrentVehicleBlip, true)
        SetBlipRouteColour(CurrentVehicleBlip, G6_BLIP_COLOR)
    end
end

-- Draws a big return area and prompts E to return
function StartReturnAreaWatcher(returnLoc)
    if ReturnWatcherActive then return end
    ReturnWatcherActive = true

    local radius = 7.5

    CreateThread(function()
        while ReturnWatcherActive and CurrentVehicle and DoesEntityExist(CurrentVehicle) do
            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)
            local dist = #(pedCoords - returnLoc)

            if dist <= radius then
                -- Only allow if in the G6 vehicle
                if IsPedInVehicle(ped, CurrentVehicle, false) then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to return the delivery vehicle')
                    EndTextCommandDisplayHelp(0, false, false, -1)

                    if IsControlJustReleased(0, 38) then -- E key
                        TriggerEvent('pf-jobs:gruppe6:returnVehicle')
                        break
                    end
                end
            end

            Wait(0)
        end

        ReturnWatcherActive = false
    end)
end

RegisterNetEvent('pf-jobs:gruppe6:returnVehicle', function()
    if not CurrentVehicle then
        QBCore.Functions.Notify('You are not in a Gruppe6 vehicle!', 'error')
        return
    end
    
    QBCore.Functions.Progressbar('return_vehicle', 'Returning vehicle to HQ...', 3000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function() -- Done
        -- Delete vehicle and blips
        QBCore.Functions.DeleteVehicle(CurrentVehicle)
        
        -- NEW: Remove all blips
        CurrentVehicleBlip = RemoveCustomBlip(CurrentVehicleBlip)
        CurrentWaypointBlip = RemoveCustomBlip(CurrentWaypointBlip)
        
        -- Cleanup
        CurrentVehicle = nil
        CurrentContract = nil
        ClearPickupZones()
        exports['pfm-target']:RemoveZone('gruppe6_deposit')
        if ReturnZone then
            exports['pfm-target']:RemoveZone(ReturnZone)
            ReturnZone = nil
        end
        if StorageTargetAdded then
            StorageTargetAdded = false
            if exports['pfm-target'] and exports['pfm-target'].RemoveTargetEntity then
                pcall(function()
                    exports['pfm-target']:RemoveTargetEntity(CurrentVehicle)
                end)
            end
        end
        ReturnWatcherActive = false
        
        SetWaypointOff()
        HideScoreboard()
        
        TriggerServerEvent('pf-jobs:gruppe6:vehicleReturned')
        QBCore.Functions.Notify('Vehicle returned successfully!', 'success')

        -- Auto search for next contract
        TriggerServerEvent('pf-jobs:gruppe6:startSearch')
        ShowScoreboard('Gruppe6 Contractor', 'Waiting for job offer', '')
    end, function() -- Cancel
        QBCore.Functions.Notify('Vehicle return cancelled', 'error')
    end)
end)

RegisterNetEvent('pf-jobs:gruppe6:deleteVehicle', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(veh) then
        QBCore.Functions.DeleteVehicle(veh)
    end
    
    -- NEW: Remove all blips
    CurrentVehicleBlip = RemoveCustomBlip(CurrentVehicleBlip)
    CurrentWaypointBlip = RemoveCustomBlip(CurrentWaypointBlip)
    
    CurrentVehicle = nil
    CurrentContract = nil
    ClearPickupZones()
    exports['pfm-target']:RemoveZone('gruppe6_deposit')
    if ReturnZone then
        exports['pfm-target']:RemoveZone(ReturnZone)
        ReturnZone = nil
    end
    
    SetWaypointOff()
    HideScoreboard()
end)

-- =========================================
-- VAULT DOOR SYSTEM
-- =========================================

local VaultDoorStates = {} -- Track open/closed state of each vault
local VaultPanelTargets = {} -- Track created qb-target zones

-- Initialize vault door system on resource start
CreateThread(function()
    -- Wait for config to be available
    while not Config or not Config.Gruppe6 or not Config.Gruppe6.VaultDoors do
        Wait(100)
    end
    
    print('[Gruppe6] Initializing vault door system...')
    
    -- Setup all vault doors
    for i, vault in ipairs(Config.Gruppe6.VaultDoors) do
        local vaultCfg = vault
        VaultDoorStates[i] = false -- All vaults start closed
        
        -- Create security panel interaction point
        local panelZoneName = 'gruppe6_vault_panel_' .. i
        
        exports['pfm-target']:AddBoxZone(panelZoneName, vault.securityPanelCoord, 0.6, 0.6, {
            name = panelZoneName,
            heading = vault.securityPanelHeading or 0,
            debugPoly = false,
            minZ = vault.securityPanelCoord.z - 0.5,
            maxZ = vault.securityPanelCoord.z + 1.5,
        }, {
            options = {
                {
                    type = 'client',
                    event = 'pf-jobs:gruppe6:useSecurityPanel',
                    icon = 'fas fa-lock',
                    label = 'Use Security Panel',
                    vaultIndex = i,
                    canInteract = function()
                        local PlayerData = QBCore.Functions.GetPlayerData()
                        if not PlayerData or not PlayerData.job or PlayerData.job.name ~= 'gruppe6' then
                            return false
                        end

                        if PlayerData.job.onduty == false then
                            return false
                        end

                        if vaultCfg and vaultCfg.requireActiveContract and not CurrentContract then
                            return false
                        end

                        return true
                    end,
                },
            },
            distance = 1.5,
        })
        
        VaultPanelTargets[i] = panelZoneName
        print(string.format('[Gruppe6] Created security panel for: %s', vault.name))
    end
    
    print('[Gruppe6] Vault door system initialized')
end)

-- Handle security panel interaction
RegisterNetEvent('pf-jobs:gruppe6:useSecurityPanel', function(data)
    local vaultIndex = tonumber(data and data.vaultIndex)
    if not vaultIndex or not Config.Gruppe6.VaultDoors[vaultIndex] then return end
    
    local vault = Config.Gruppe6.VaultDoors[vaultIndex]
    local isOpen = VaultDoorStates[vaultIndex]
    
    if isOpen then
        -- Close vault door
        CloseVaultDoor(vaultIndex, vault)
    else
        -- Open vault door
        OpenVaultDoor(vaultIndex, vault)
    end
end)

function OpenVaultDoor(vaultIndex, vault)
    local ped = PlayerPedId()
    
    -- Load animation dictionary
    local animDict = 'anim@heists@ornate_bank@hack'
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
    end
    
    -- Play card swipe animation
    QBCore.Functions.Progressbar('vault_access', 'Swiping access card...', 10000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = animDict,
        anim = 'hack_loop',
        flags = 16,
    }, {}, {}, function() -- Success
        -- Stop animation
        StopAnimTask(ped, animDict, 'hack_loop', 1.0)
        
        -- Find and open the vault door
        local doorObject = GetClosestVaultDoorObject(vault)
        local openOffset = tonumber(vault.openHeadingOffset) or -90.0
        
        if doorObject and DoesEntityExist(doorObject) then
            -- Freeze door position before rotation
            FreezeEntityPosition(doorObject, true)
            
            -- Get current rotation
            local doorRot = GetEntityRotation(doorObject, 2)
            
            -- Open door by rotating it -90 degrees on Z axis
            SetEntityRotation(doorObject, doorRot.x, doorRot.y, doorRot.z + openOffset, 2, true)
            
            -- Play door opening sound
            PlaySoundFromCoord(-1, 'DOOR_OPEN', vault.vaultDoorCoords.x, vault.vaultDoorCoords.y, vault.vaultDoorCoords.z, 'GTAO_APT_DOOR_DOWNSTAIRS_GENERIC_SOUNDS', false, 15.0, false)
            
            VaultDoorStates[vaultIndex] = true
            QBCore.Functions.Notify(('Vault door opened: %s'):format(vault.name or 'Bank Vault'), 'success')
            
            print(string.format('[Gruppe6] Vault door opened: %s', vault.name))
        else
            -- If door object doesn't exist, just mark as open (door might be IPL-based)
            VaultDoorStates[vaultIndex] = true
            QBCore.Functions.Notify(('Access granted: %s'):format(vault.name or 'Bank Vault'), 'success')
            print(string.format('[Gruppe6] Vault access granted (no door object found): %s', vault.name))
        end
    end, function() -- Cancel
        StopAnimTask(ped, animDict, 'hack_loop', 1.0)
        QBCore.Functions.Notify('Access cancelled', 'error')
    end)
end

function CloseVaultDoor(vaultIndex, vault)
    local ped = PlayerPedId()
    
    -- Check if all bags have been deposited
    if CurrentContract and CurrentContract.bagsCollected and CurrentContract.bagsDeposited then
        if CurrentContract.bagsDeposited < CurrentContract.bagsCollected then
            QBCore.Functions.Notify('Cannot close vault - bags still need to be deposited!', 'error')
            return
        end
    end
    
    -- Load animation dictionary
    local animDict = 'anim@heists@ornate_bank@hack'
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
    end
    
    -- Play card swipe animation
    QBCore.Functions.Progressbar('vault_close', 'Securing vault...', 5000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = animDict,
        anim = 'hack_loop',
        flags = 16,
    }, {}, {}, function() -- Success
        -- Stop animation
        StopAnimTask(ped, animDict, 'hack_loop', 1.0)
        
        -- Find and close the vault door
        local doorObject = GetClosestVaultDoorObject(vault)
        local openOffset = tonumber(vault.openHeadingOffset) or -90.0
        
        if doorObject and DoesEntityExist(doorObject) then
            -- Get current rotation
            local doorRot = GetEntityRotation(doorObject, 2)
            
            -- Close door by rotating it back +90 degrees
            SetEntityRotation(doorObject, doorRot.x, doorRot.y, doorRot.z - openOffset, 2, true)
            
            -- Unfreeze after rotating
            Wait(100)
            FreezeEntityPosition(doorObject, true) -- Keep frozen in closed position
            
            -- Play door closing sound
            PlaySoundFromCoord(-1, 'DOOR_CLOSE', vault.vaultDoorCoords.x, vault.vaultDoorCoords.y, vault.vaultDoorCoords.z, 'GTAO_APT_DOOR_DOWNSTAIRS_GENERIC_SOUNDS', false, 15.0, false)
            
            VaultDoorStates[vaultIndex] = false
            QBCore.Functions.Notify(('Vault door secured: %s'):format(vault.name or 'Bank Vault'), 'success')
            
            print(string.format('[Gruppe6] Vault door closed: %s', vault.name))
        else
            VaultDoorStates[vaultIndex] = false
            QBCore.Functions.Notify('Vault secured', 'success')
        end
        
        -- If this is the main vault and all bags deposited, proceed to return
        if vault.isMainVault and CurrentContract then
            Wait(500)
            ProceedToVehicleReturn()
        end
    end, function() -- Cancel
        StopAnimTask(ped, animDict, 'hack_loop', 1.0)
        QBCore.Functions.Notify('Vault securing cancelled', 'error')
    end)
end

function GetClosestVaultDoorObject(vault)
    if not vault or not vault.vaultDoorCoords then return nil end

    local coords = vault.vaultDoorCoords
    local searchRadius = tonumber(vault.searchRadius) or 6.0

    local candidates = {}
    if type(vault.vaultDoorModels) == 'table' and #vault.vaultDoorModels > 0 then
        candidates = vault.vaultDoorModels
    elseif vault.vaultDoorModel then
        candidates = { vault.vaultDoorModel }
    else
        candidates = { 'v_ilev_gb_vaultdor', 'v_ilev_gb_vaultdr', 'v_ilev_gb_vaultdoor', 'v_ilev_bk_vaultdoor' }
    end

    for _, candidate in ipairs(candidates) do
        local modelHash = type(candidate) == 'number' and candidate or GetHashKey(candidate)
        local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, searchRadius, modelHash, false, false, false)
        if object and DoesEntityExist(object) then
            return object
        end
    end

    return nil
end

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Remove all vault panel targets
    for i, zoneName in ipairs(VaultPanelTargets) do
        pcall(function()
            exports['pfm-target']:RemoveZone(zoneName)
        end)
    end
    
    print('[Gruppe6] Vault door system cleaned up')
end)

-- =========================================
-- END VAULT DOOR SYSTEM
-- =========================================

