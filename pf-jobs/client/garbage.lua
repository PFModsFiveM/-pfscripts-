-- Garbage Job Client Logic
-- Isolated from Gruppe6

local QBCore = exports['pfm-core']:GetCoreObject()
local garbageTruckModel = Config.Garbage.VehicleModel
local garbageSpawn = Config.Garbage.VehicleSpawn
local carrying = false
local truckNetId = nil
local carryProp = 0
local carryPropNet = 0
local garbageVehicle = nil
local garbageVehicleBlip = nil
local GarbageDebug = Config.Garbage.Debug or false
local GarbageJobActive = false
local GarbageObjective = 0
local GarbageObjectiveTarget = Config.Garbage.ObjectiveTarget
local DepositWatcherActive = false
local DepotZoneAdded = false
-- Forward declarations
local AddTruckDepositTarget

-- Scoreboard helper function
local function HideScoreboard()
    if GetResourceState('pf-tablet') == 'started' then
        exports['pf-tablet']:SendNuiMessage({
            action = 'scoreboard_close'
        })
    else
        SendNUIMessage({
            action = 'scoreboard_close'
        })
    end
end

-- Interactable props (from config)
local dumpsterProps = Config.Garbage.DumpsterProps
local binbagProps = Config.Garbage.BinbagProps

-- Dumpster highlighting state
local DumpsterRemaining = {}   -- key -> remaining count
local HighlightedDumpsters = {} -- entity -> true while highlighted
local pickedUpBags = {} -- Track picked up bags to prevent re-pickup
local ActiveZone = nil -- { name, center=vector3, radius, target }
local EntityKeyCache = {} -- entity -> stable fallback key (prevents reloot by moving dumpster)

local function GetEntityKeyForDumpster(entity)
    if not entity or entity == 0 then return nil end

    -- Always prefer a cached key so moving the same dumpster never changes identity
    if EntityKeyCache[entity] then
        return EntityKeyCache[entity]
    end

    -- Use network ID if this is already networked, but cache it so it remains stable
    if NetworkGetEntityIsNetworked and NetworkGetEntityIsNetworked(entity) then
        local netId = NetworkGetNetworkIdFromEntity(entity)
        if netId and netId ~= 0 then
            local netKey = ('net:%s'):format(tostring(netId))
            EntityKeyCache[entity] = netKey
            return netKey
        end
    end

    -- Fallback to model:coords (quantized + cached)
    local model = GetEntityModel(entity)
    local c = GetEntityCoords(entity)
    local qx = math.floor((c.x * 2.0) + 0.5) / 2.0
    local qy = math.floor((c.y * 2.0) + 0.5) / 2.0
    local qz = math.floor((c.z * 2.0) + 0.5) / 2.0
    local key = ("%s:%.1f:%.1f:%.1f"):format(model, qx, qy, qz)
    EntityKeyCache[entity] = key
    return key
end

local function GetNetKey(entity)
    if not entity or entity == 0 then return nil end
    if NetworkGetEntityIsNetworked and NetworkGetEntityIsNetworked(entity) then
        local nid = NetworkGetNetworkIdFromEntity(entity)
        if nid and nid ~= 0 then return tostring(nid) end
    end
    return nil
end

local function SetDumpsterOutline(entity, enabled)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if enabled then
        local color = Config.Garbage.HighlightColor
        SetEntityDrawOutlineColor(color[1], color[2], color[3], color[4])
        SetEntityDrawOutline(entity, true)
        HighlightedDumpsters[entity] = true
    else
        SetEntityDrawOutline(entity, false)
        HighlightedDumpsters[entity] = nil
    end
end

-- Periodically highlight dumpsters and binbags near player
CreateThread(function()
    while true do
        Wait(400)
        if not GarbageJobActive or not Config.Garbage.EnableHighlights then
            -- clear any leftovers
            for ent, _ in pairs(HighlightedDumpsters) do
                SetDumpsterOutline(ent, false)
            end
        else
            local ped = PlayerPedId()
            local pcoords = GetEntityCoords(ped)
            -- Enumerate world objects and check for dumpsters and binbags in short range
            local handle, obj = FindFirstObject()
            local success
            repeat
                if DoesEntityExist(obj) then
                    local model = GetEntityModel(obj)
                    local isDumpster = false
                    local isBinbag = false
                    
                    for _, m in ipairs(dumpsterProps) do
                        if model == GetHashKey(m) then isDumpster = true break end
                    end
                    
                    if not isDumpster then
                        for _, m in ipairs(binbagProps) do
                            if model == GetHashKey(m) then isBinbag = true break end
                        end
                    end
                    
                    if isDumpster or isBinbag then
                        local coords = GetEntityCoords(obj)
                        local dist = #(coords - pcoords)
                        local near = dist <= Config.Garbage.HighlightRange
                        -- Restrict highlights to active zone if defined
                        if ActiveZone and ActiveZone.center and ActiveZone.radius then
                            local inZone = (#(coords - ActiveZone.center) <= ActiveZone.radius)
                            if not inZone then near = false end
                        end
                        local key = GetEntityKeyForDumpster(obj)
                        
                        local hasBags = true
                        if isDumpster then
                            -- Check if this dumpster is depleted (from server sync)
                            local remaining = DumpsterRemaining[key]
                            hasBags = (remaining == nil) or (remaining and remaining > 0)
                            -- Also check if dumpster was already fully depleted (set as null)
                            if remaining == 0 then hasBags = false end
                        else
                            -- Binbag: check if already picked up
                            hasBags = not pickedUpBags[key]
                        end
                        
                        if near and hasBags then
                            if not HighlightedDumpsters[obj] then
                                SetDumpsterOutline(obj, true)
                            end
                        else
                            if HighlightedDumpsters[obj] then
                                SetDumpsterOutline(obj, false)
                            end
                        end
                    end
                end
                success, obj = FindNextObject(handle)
            until not success
            EndFindObject(handle)
        end
    end
end)

-- Removed complex vehicle deletion - using QBCore.Functions.DeleteVehicle instead

-- Early definition so events can safely call it
function StartDepositWatcher(truck)
    if not truck or truck == 0 then return end
    if DepositWatcherActive then return end
    DepositWatcherActive = true
    local rearOffset = Config.Garbage.TruckDepositOffset
    CreateThread(function()
        local startTime = GetGameTimer()
        while DepositWatcherActive and truck and DoesEntityExist(truck) do
            Wait(0)
            if carrying then
                local rear = GetOffsetFromEntityInWorldCoords(truck, rearOffset.x, rearOffset.y, rearOffset.z)
                local ped = PlayerPedId()
                local dist = #(GetEntityCoords(ped) - rear)
                if dist <= Config.Garbage.TruckDepositRadius then
                    if IsControlJustReleased(0, 38) then
                        if not carrying then break end
                        -- Stop carrying animation first
                        ClearPedTasks(ped)
                        ClearPedSecondaryTask(ped)
                        ResetPedMovementClipset(ped, 0.0)
                        EnableControlAction(0, 21, true)
                        Wait(250)
                        -- Now play throwing animation
                        local depositAnim = Config.Garbage.Animations.Deposit
                        RequestAnimDict(depositAnim.dict); while not HasAnimDictLoaded(depositAnim.dict) do Wait(10) end
                        TaskPlayAnim(ped, depositAnim.dict, depositAnim.anim, 8.0, -8.0, depositAnim.duration, 0, 0, false, false, false)
                        -- Throw the prop physically
                        Wait(600) -- Wait for throw animation to start
                        if carryProp ~= 0 and DoesEntityExist(carryProp) then
                            local throwVel = vector3(math.random(-5, 5), math.random(5, 15), math.random(2, 8))
                            SetEntityVelocity(carryProp, throwVel.x, throwVel.y, throwVel.z)
                            -- Let it fall for a bit then delete
                            Wait(500)
                            DeleteObject(carryProp)
                            carryProp = 0
                        end
                        carrying = false
                        TriggerServerEvent('pf-jobs:garbage:depositBag')
                        -- Allow multiple deposits; do not break so watcher can continue for next bag
                        Wait(500)
                    end
                end
            end
            if GetGameTimer() - startTime > 120000 then DepositWatcherActive = false end
        end
        DepositWatcherActive = false
    end)
end

RegisterNUICallback('garbage:getInit', function(_, cb)
    QBCore.Functions.TriggerCallback('pf-jobs:garbage:getInit', function(state)
        SendNUIMessage({ action = 'garbage:init', state = state })
        cb({ ok = true })
    end)
end)

-- =========================
-- Group UI: Client <-> Server bridge (all UI, no commands)
-- =========================

-- Receive server-pushed group updates and forward to NUI (single consistent handler)
RegisterNetEvent('pf-jobs:garbage:groupUpdate', function(groupData)
    print('[Garbage Client] Received groupUpdate from server:', json.encode(groupData or {}))
    SendNUIMessage({ action = 'garbage_group_update', group = groupData })
    print('[Garbage Client] Sent NUI message: garbage_group_update')
end)

-- Receive invites and show in UI
RegisterNetEvent('pf-jobs:garbage:receiveInvite', function(leaderName, leaderId)
    SendNUIMessage({ action = 'garbage_group_invite', invite = { leaderName = leaderName, leaderId = leaderId } })
end)

-- NUI -> Server: Create group
RegisterNUICallback('garbage/group/create', function(_, cb)
    TriggerServerEvent('pf-jobs:garbage:createGroup')
    cb(true)
end)

-- NUI -> Server: Invite by player ID
RegisterNUICallback('garbage/group/invite', function(data, cb)
    local target = tonumber(data and data.target)
    if target then TriggerServerEvent('pf-jobs:garbage:invitePlayer', target) end
    cb(true)
end)

-- NUI -> Server: Accept invite (given leaderId)
RegisterNUICallback('garbage/group/accept', function(data, cb)
    local leaderId = tonumber(data and data.leaderId)
    if leaderId then TriggerServerEvent('pf-jobs:garbage:acceptInvite', leaderId) end
    cb(true)
end)

-- NUI -> Server: Decline invite
RegisterNUICallback('garbage/group/decline', function(data, cb)
    local leaderId = tonumber(data and data.leaderId)
    if leaderId then TriggerServerEvent('pf-jobs:garbage:declineInvite', leaderId) end
    cb(true)
end)

-- NUI -> Server: Leave group
RegisterNUICallback('garbage/group/leave', function(_, cb)
    TriggerServerEvent('pf-jobs:garbage:leaveGroup')
    cb(true)
end)

-- NUI -> Server: Kick member
RegisterNUICallback('garbage/group/kick', function(data, cb)
    local target = tonumber(data and data.target)
    if target then TriggerServerEvent('pf-jobs:garbage:kickMember', target) end
    cb(true)
end)

-- NUI -> Server: Update split (precise total=100 logic handled server-side)
RegisterNUICallback('garbage/group/split', function(data, cb)
    local target = tonumber(data and data.target)
    local percent = tonumber(data and data.percent)
    if target and percent then TriggerServerEvent('pf-jobs:garbage:updateSplit', target, percent) end
    cb(true)
end)

-- NUI -> Server: Disband (leader only)
RegisterNUICallback('garbage/group/disband', function(_, cb)
    TriggerServerEvent('pf-jobs:garbage:disbandGroup')
    cb(true)
end)

-- NUI -> Server: Get current group state
RegisterNUICallback('garbage/group/getState', function(_, cb)
    QBCore.Functions.TriggerCallback('pf-jobs:garbage:getGroupState', function(state)
        cb(state)
    end)
end)

-- Duplicate handlers removed; unified above
RegisterNUICallback('garbage:startJob', function(_, cb)
    print('[Garbage Client] Start Job button clicked - sending server event')
    TriggerServerEvent('pf-jobs:garbage:startJob')
    -- Job state will be initialized when server confirms via vehicleSpawned event
    print('[Garbage Client] Start Job callback complete')
    cb({ ok = true })
end)

-- Group management NUI callbacks
RegisterNUICallback('garbage:createGroup', function(_, cb)
    TriggerServerEvent('pf-jobs:garbage:createGroup')
    cb({ ok = true })
end)

RegisterNUICallback('garbage:invitePlayer', function(data, cb)
    TriggerServerEvent('pf-jobs:garbage:invitePlayer', data.targetId)
    cb({ ok = true })
end)

RegisterNUICallback('garbage:acceptInvite', function(data, cb)
    TriggerServerEvent('pf-jobs:garbage:acceptInvite', data.leaderId)
    cb({ ok = true })
end)

RegisterNUICallback('garbage:declineInvite', function(data, cb)
    TriggerServerEvent('pf-jobs:garbage:declineInvite', data.leaderId)
    cb({ ok = true })
end)

RegisterNUICallback('garbage:leaveGroup', function(_, cb)
    TriggerServerEvent('pf-jobs:garbage:leaveGroup')
    cb({ ok = true })
end)

RegisterNUICallback('garbage:kickMember', function(data, cb)
    TriggerServerEvent('pf-jobs:garbage:kickMember', data.targetId)
    cb({ ok = true })
end)

RegisterNUICallback('garbage:updateSplit', function(data, cb)
    TriggerServerEvent('pf-jobs:garbage:updateSplit', data.targetId, data.percentage)
    cb({ ok = true })
end)

-- New server-side spawn event (mirrors Gruppe6 vehicleSpawned)
RegisterNetEvent('pf-jobs:garbage:vehicleSpawned', function(netId, plate, spawnCoords)
    print('[Garbage] Received vehicleSpawned event - netId: '..tostring(netId)..', plate: '..tostring(plate))
    
    -- Set job as active when server confirms spawn
    GarbageJobActive = true
    GarbageObjective = 0
    DepotZoneAdded = false
    
    -- Clear old state
    DumpsterRemaining = {}
    pickedUpBags = {}
    for ent, _ in pairs(HighlightedDumpsters) do
        SetDumpsterOutline(ent, false)
    end
    if depotReturnBlip and DoesBlipExist(depotReturnBlip) then
        RemoveBlip(depotReturnBlip)
        depotReturnBlip = nil
    end
    
    print('[Garbage] Job activated - GarbageJobActive set to true')
    
    local timeout = 0
    while not NetworkDoesNetworkIdExist(netId) and timeout < 200 do
        Wait(10)
        timeout = timeout + 1
    end
    local veh = NetToVeh(netId)
    local entTimeout = 0
    while (not veh or not DoesEntityExist(veh)) and entTimeout < 200 do
        Wait(10)
        veh = NetToVeh(netId)
        entTimeout = entTimeout + 1
    end
    if not veh or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Trashmaster failed to spawn (network timeout)', 'error')
        return
    end
    truckNetId = netId
    garbageVehicle = veh
    
    -- Set vehicle keys (client-side trigger + backup exports call)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    -- Backup: direct exports call if event doesn't fire
    local hasKeys = false
    pcall(function()
        exports['pfm-vehiclekeys']:SetVehicleKey(plate, true)
        hasKeys = true
    end)
    if hasKeys then
        print('[Garbage] Vehicle keys set via exports')
    else
        print('[Garbage] Vehicle keys set via event')
    end
    
    -- Create/replace vehicle blip (tracked globally for cleanup)
    if garbageVehicleBlip and DoesBlipExist(garbageVehicleBlip) then
        RemoveBlip(garbageVehicleBlip)
        garbageVehicleBlip = nil
    end
    local blipCfg = Config.Garbage.TruckBlip
    garbageVehicleBlip = AddBlipForEntity(veh)
    SetBlipSprite(garbageVehicleBlip, blipCfg.sprite)
    SetBlipDisplay(garbageVehicleBlip, 4)
    SetBlipScale(garbageVehicleBlip, blipCfg.scale)
    SetBlipColour(garbageVehicleBlip, blipCfg.color)
    SetBlipAsShortRange(garbageVehicleBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipCfg.label)
    EndTextCommandSetBlipName(garbageVehicleBlip)
    
    -- Update blip position continuously
    CreateThread(function()
        while garbageVehicle and DoesEntityExist(garbageVehicle) do
            if garbageVehicleBlip and DoesBlipExist(garbageVehicleBlip) then
                local coords = GetEntityCoords(garbageVehicle)
                SetBlipCoords(garbageVehicleBlip, coords.x, coords.y, coords.z)
            end
            Wait(1000)
        end
        if garbageVehicleBlip and DoesBlipExist(garbageVehicleBlip) then
            RemoveBlip(garbageVehicleBlip)
            garbageVehicleBlip = nil
        end
    end)
    
    -- Scoreboard update
    SendNUIMessage({ action='garbage:carrying', carrying=carrying })
    AddTruckDepositTarget(veh)
    QBCore.Functions.Notify('Trashmaster ready! Collect trash bags', 'success')
end)

-- Receive active zone from server and render blip/marker
local zoneBlip = nil
RegisterNetEvent('pf-jobs:garbage:setActiveZone', function(z)
    ActiveZone = {
        name = z.name or 'Search Zone',
        center = z.center or vector3(0.0,0.0,0.0),
        radius = z.radius or Config.Garbage.ZoneRadius,
        target = z.target or Config.Garbage.DumpstersPerZone
    }
    -- Create/replace zone blip
    if zoneBlip and DoesBlipExist(zoneBlip) then RemoveBlip(zoneBlip) end
    zoneBlip = AddBlipForRadius(ActiveZone.center.x, ActiveZone.center.y, ActiveZone.center.z, ActiveZone.radius)
    SetBlipColour(zoneBlip, 3)
    SetBlipAlpha(zoneBlip, 128)
    local name = ActiveZone.name .. ' (Garbage)'
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(name); EndTextCommandSetBlipName(zoneBlip)
    -- Objective text
    TriggerEvent('pf-jobs:client:updateScoreboard', 'Garbage Crew', ('Search zone: %s'):format(ActiveZone.name))
end)

-- Removed complex client deletion handlers - using QBCore.Functions.DeleteVehicle instead

-- Carry state updates from server
RegisterNetEvent('pf-jobs:garbage:carrying', function(flag)
    carrying = flag and true or false
    SendNUIMessage({ action='garbage:carrying', carrying=carrying })
    if carrying then
        if garbageVehicle and DoesEntityExist(garbageVehicle) then
            StartDepositWatcher(garbageVehicle)
        end
    else
        StopCarryBag()
        DepositWatcherActive = false
    end
end)

-- XP updates
RegisterNetEvent('pf-jobs:garbage:updateXP', function(xp, level)
    SendNUIMessage({ action='garbage:updateXP', xp=xp, level=level })
end)

-- Deposited counter updates (server-enforced cap)
RegisterNetEvent('pf-jobs:garbage:updateDeposited', function(count, cap)
    SendNUIMessage({ action='garbage:updateDeposited', count=count or 0, cap=cap or 20 })
    
    -- Increment objective progress on successful deposit
    GarbageObjective = GarbageObjective + 1
    if GarbageObjective >= GarbageObjectiveTarget then
        QBCore.Functions.Notify('Objective complete! Return the truck to the depot.', 'success')
        print('[Garbage] Objective complete -> activating return zone')
        TriggerEvent('pf-jobs:client:updateScoreboard', 'Garbage Crew', 'Return truck to depot')
        -- Clear active search zone
        if zoneBlip and DoesBlipExist(zoneBlip) then
            RemoveBlip(zoneBlip)
            zoneBlip = nil
        end
        ActiveZone = nil
        if not DepotZoneAdded then
            AddDepotReturnZone()
            DepotZoneAdded = true
        end
    else
        TriggerEvent('pf-jobs:client:updateScoreboard', 'Garbage Crew', ('Deposited %d/%d bags'):format(GarbageObjective, GarbageObjectiveTarget))
    end
end)

-- TODO: qb-target setup for dumpsters/binbags (2–6 from dumpsters, 1 from loose bags), attach prop to hand while carrying, deposit at truck rear via target, play animations, enforce single-bag rule, and award XP on deposit.

-- ==== Interaction: qb-target for dumpsters and loose bags ====
local function AddDumpsterTargets()
    print('[Garbage] AddDumpsterTargets() called')
    
    if not exports['pfm-target'] then 
        print('[Garbage] ERROR: qb-target export not available')
        return 
    end
    
    print('[Garbage] Adding targets for ' .. #dumpsterProps .. ' dumpster models')
    for _, model in ipairs(dumpsterProps) do
        print('[Garbage] Adding target for dumpster model: ' .. model)
        exports['pfm-target']:AddTargetModel(model, {
            options = {
                {
                    label = 'Collect Trash Bags',
                    icon = 'fas fa-trash',
                    canInteract = function(entity)
                        if not GarbageJobActive then 
                            if GarbageDebug then print('[Garbage] canInteract: Job not active') end
                            return false 
                        end
                        if carrying then
                            if GarbageDebug then print('[Garbage] canInteract: Already carrying') end
                            return false
                        end
                        if GarbageObjective >= GarbageObjectiveTarget then
                            if GarbageDebug then print('[Garbage] canInteract: Objective reached') end
                            return false
                        end
                        local key = GetEntityKeyForDumpster(entity)
                        if not key then 
                            if GarbageDebug then print('[Garbage] canInteract: No key for entity') end
                            return false 
                        end
                        -- Enforce active zone: dumpster must be within the zone
                        if ActiveZone and ActiveZone.center and ActiveZone.radius then
                            local coords = GetEntityCoords(entity)
                            local dist = #(coords - ActiveZone.center)
                            if dist > ActiveZone.radius then 
                                if GarbageDebug then print('[Garbage] canInteract: Outside zone (dist: ' .. dist .. ')') end
                                return false 
                            end
                        end
                        local rem = DumpsterRemaining[key]
                        if GarbageDebug then print('[Garbage] canInteract: PASS (key: ' .. key .. ', remaining: ' .. tostring(rem or 'unlimited') .. ')') end
                        return rem == nil or rem > 0
                    end,
                    action = function(entity)
                        if carrying then QBCore.Functions.Notify('You can only carry one bag at a time', 'error'); return end
                        local key = GetEntityKeyForDumpster(entity)
                        if not key then return end

                        -- Freeze dumpster to stop move-and-reloot exploits
                        if DoesEntityExist(entity) then
                            FreezeEntityPosition(entity, true)
                        end

                        -- Block if outside zone
                        if ActiveZone and ActiveZone.center and ActiveZone.radius then
                            local coords = GetEntityCoords(entity)
                            if #(coords - ActiveZone.center) > ActiveZone.radius then
                                QBCore.Functions.Notify('This dumpster is outside the active zone', 'error')
                                return
                            end
                        end
                        print('[Garbage] Requesting bag from server (key: ' .. key .. ')')
                        TriggerServerEvent('pf-jobs:garbage:requestBag', key, false)
                    end
                }
            },
            distance = 2.5
        })
    end
    
    print('[Garbage] Adding targets for ' .. #binbagProps .. ' binbag models')
    for _, model in ipairs(binbagProps) do
        print('[Garbage] Adding target for binbag model: ' .. model)
        exports['pfm-target']:AddTargetModel(model, {
            options = {
                {
                    label = 'Pick Up Bag',
                    icon = 'fas fa-trash',
                    canInteract = function(entity)
                        if not GarbageJobActive then 
                            if GarbageDebug then print('[Garbage] binbag canInteract: Job not active') end
                            return false 
                        end
                        if GarbageObjective >= GarbageObjectiveTarget then
                            if GarbageDebug then print('[Garbage] binbag canInteract: Objective reached') end
                            return false
                        end
                        if carrying then
                            if GarbageDebug then print('[Garbage] binbag canInteract: Already carrying') end
                            return false
                        end
                        local key = GetEntityKeyForDumpster(entity)
                        if not key then 
                            if GarbageDebug then print('[Garbage] binbag canInteract: No key') end
                            return false 
                        end
                        -- Enforce zone for loose bags
                        if ActiveZone and ActiveZone.center and ActiveZone.radius then
                            local coords = GetEntityCoords(entity)
                            local dist = #(coords - ActiveZone.center)
                            if dist > ActiveZone.radius then 
                                if GarbageDebug then print('[Garbage] binbag canInteract: Outside zone (dist: ' .. dist .. ')') end
                                return false 
                            end
                        end
                        local alreadyPicked = pickedUpBags[key]
                        if GarbageDebug then print('[Garbage] binbag canInteract: ' .. (alreadyPicked and 'DENY (already picked)' or 'PASS') .. ' (key: ' .. key .. ')') end
                        return not alreadyPicked
                    end,
                    action = function(entity)
                        if carrying then QBCore.Functions.Notify('You can only carry one bag at a time', 'error'); return end
                        local key = GetEntityKeyForDumpster(entity)
                        if not key then return end
                        -- Block if outside zone
                        if ActiveZone and ActiveZone.center and ActiveZone.radius then
                            local coords = GetEntityCoords(entity)
                            if #(coords - ActiveZone.center) > ActiveZone.radius then
                                QBCore.Functions.Notify('This bag is outside the active zone', 'error')
                                return
                            end
                        end
                        if pickedUpBags[key] then QBCore.Functions.Notify('This bag has already been picked up.', 'error'); return end
                        pickedUpBags[key] = true
                        print('[Garbage] Requesting loose bag from server (key: ' .. key .. ')')
                        TriggerServerEvent('pf-jobs:garbage:requestBag', key, true)
                    end
                }
            },
            distance = 2.0
        })
    end
    
    print('[Garbage] Target registration complete')
end

CreateThread(function()
    -- Wait for player loaded then add targets
    while not LocalPlayer or not LocalPlayer.state.isLoggedIn do Wait(500) end
    AddDumpsterTargets()
end)

-- ==== Carry bag: attach prop and set movement ====
function StartCarryBag(fromEntity, isLoose)
    carrying = true
    TriggerServerEvent('pf-jobs:garbage:setCarrying', true)
    local ped = PlayerPedId()
    local model = GetHashKey(Config.Garbage.CarryBagProp)
    RequestModel(model); while not HasModelLoaded(model) do Wait(10) end
    carryProp = CreateObject(model, GetEntityCoords(ped), true, true, true)
    carryPropNet = NetworkGetNetworkIdFromEntity(carryProp)
    local bone = GetPedBoneIndex(ped, 57005) -- right hand
    -- Refined grip: bring handle closer to palm, tilt downward
    -- Fine tune: X forward, Y sideways, Z vertical relative to hand
    -- Minor tweak: move slightly back & down, rotate to align handle horizontally in palm
    -- Align handle to palm; adjust for better natural grip
    AttachEntityToEntity(carryProp, ped, bone, 0.15, 0.02, -0.12, -10.0, 85.0, 95.0, false, false, false, false, 2, true)
    local carryAnim = Config.Garbage.Animations.Carry
    RequestAnimDict(carryAnim.dict); while not HasAnimDictLoaded(carryAnim.dict) do Wait(10) end
    TaskPlayAnim(ped, carryAnim.dict, carryAnim.anim, 4.0, -4.0, -1, 49, 0, false, false, false)
    RequestAnimSet(carryAnim.clipset); while not HasAnimSetLoaded(carryAnim.clipset) do Wait(10) end
    SetPedMovementClipset(ped, carryAnim.clipset, 1.0)
    DisableControlAction(0, 21, true)
    QBCore.Functions.Notify('Carrying trash bag. Deposit at truck rear.', 'primary')
end

function StopCarryBag()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    ResetPedMovementClipset(ped, 0.0)
    EnableControlAction(0, 21, true)
    if carryProp ~= 0 and DoesEntityExist(carryProp) then
        DeleteObject(carryProp)
        carryProp = 0
    end
    carrying = false
end

-- ==== Deposit: qb-target on truck rear ====
local truckDepositZone = nil

AddTruckDepositTarget = function(truck)
    if not exports['pfm-target'] then return end
    local rearOffset = Config.Garbage.TruckDepositOffset
    local function RearWorld()
        return GetOffsetFromEntityInWorldCoords(truck, rearOffset.x, rearOffset.y, rearOffset.z)
    end
    local function NearRear()
        local ped = PlayerPedId()
        return #(GetEntityCoords(ped) - RearWorld()) <= Config.Garbage.TruckDepositRadius
    end
    -- Optional debug marker thread
    if GarbageDebug then
        CreateThread(function()
            while truck and DoesEntityExist(truck) do
                local rear = RearWorld()
                DrawMarker(1, rear.x, rear.y, rear.z - 0.95, 0.0,0.0,0.0, 0.0,0.0,0.0, 1.6,1.6,0.6, 1,255,158,120, 50, false,false,2,false,nil,nil,false)
                Wait(0)
            end
        end)
    end
    exports['pfm-target']:AddTargetEntity(truck, {
        options = {
            {
                label = 'Deposit Bag', icon = 'fas fa-dumpster', canInteract = function(ent)
                    -- Only allow deposit when job active and player is carrying a bag
                    return GarbageJobActive and ent == truck and carrying and NearRear()
                end,
                action = function()
                    if not carrying then return end
                    local ped = PlayerPedId()
                    -- Stop carrying animation first
                    ClearPedTasks(ped)
                    ClearPedSecondaryTask(ped)
                    ResetPedMovementClipset(ped, 0.0)
                    EnableControlAction(0, 21, true)
                    Wait(250)
                    -- Now play deposit animation
                    local depositAnim = Config.Garbage.Animations.Deposit
                    RequestAnimDict(depositAnim.dict)
                    while not HasAnimDictLoaded(depositAnim.dict) do Wait(10) end
                    TaskPlayAnim(ped, depositAnim.dict, depositAnim.anim, 8.0, -8.0, depositAnim.duration, 0, 0, false, false, false)
                    Wait(1100)
                    -- Delete prop and notify server
                    if carryProp ~= 0 and DoesEntityExist(carryProp) then
                        DeleteObject(carryProp)
                        carryProp = 0
                    end
                    carrying = false
                    TriggerServerEvent('pf-jobs:garbage:depositBag')
                end
            }
        },
        distance = 4.0
    })
end

-- (Fallback watcher now defined early above)

AddEventHandler('pf-jobs:garbage:vehicleSpawned', function(netId, plate, spawnCoords)
    -- vehicleSpawned handler exists above; we append fallback start here
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and veh ~= 0 then
        -- Delay a bit to allow qb-target registration
        CreateThread(function()
            Wait(3000)
            if carrying and not DepositWatcherActive then
                StartDepositWatcher(veh)
            else
                -- Start watcher anyway to guarantee deposit interaction
                StartDepositWatcher(veh)
            end
        end)
    end
end)

AddEventHandler('pf-jobs:garbage:spawnTruck', function(model, spawn)
    -- Already handled above to spawn vehicle and blip; add deposit target
    local veh = NetworkGetEntityFromNetworkId(truckNetId)
    if veh and veh ~= 0 then AddTruckDepositTarget(veh) end
end)

-- Server grants bag; for loose bag, delete source entity
RegisterNetEvent('pf-jobs:garbage:grantBag', function(key, isLoose, remaining)
    -- key may be netId string or model:coords signature
    local entity = 0
    local num = tonumber(key)
    if num and NetworkDoesNetworkIdExist(num) then
        entity = NetToEnt(num)
    end
    -- Play pickup animation for both loose and dumpster pulls
    local pickupAnim = Config.Garbage.Animations.Pickup
    RequestAnimDict(pickupAnim.dict); while not HasAnimDictLoaded(pickupAnim.dict) do Wait(10) end
    TaskPlayAnim(PlayerPedId(), pickupAnim.dict, pickupAnim.anim, 4.0, -4.0, pickupAnim.duration, 0, 0, false, false, false)
    Wait(600)
    -- Delete the loose bag entity
    if isLoose then
        local deleted = false
        -- Try entity first if we have it
        if entity ~= 0 and DoesEntityExist(entity) then
            DeleteEntity(entity)
            deleted = true
        end
        
        -- Fallback: search for nearby bags to delete
        if not deleted then
            local target = GetEntityCoords(PlayerPedId())
            local models = {
                GetHashKey('hei_prop_heist_binbag'), GetHashKey('p_binbag_01_s'), GetHashKey('prop_cs_street_binbag_01'),
                GetHashKey('prop_rub_binbag_sd_01'), GetHashKey('prop_cs_rub_binbag_01'), GetHashKey('prop_rub_binbag_04'),
                GetHashKey('prop_rub_binbag_sd_02'), GetHashKey('ng_proc_binbag_01a'), GetHashKey('prop_rub_binbag_05'),
                GetHashKey('prop_rub_binbag_01'), GetHashKey('prop_ld_rub_binbag_01')
            }
            local handle, obj = FindFirstObject()
            repeat
                if DoesEntityExist(obj) then
                    local mh = GetEntityModel(obj)
                    for _, allowed in ipairs(models) do
                        if mh == allowed then
                            local ec = GetEntityCoords(obj)
                            if #(ec - target) < 1.5 then
                                DeleteEntity(obj)
                                deleted = true
                                break
                            end
                        end
                    end
                    if deleted then break end
                end
                local success, nextObj = FindNextObject(handle)
                obj = nextObj
            until not success
            EndFindObject(handle)
        end
    end
    -- Mark bag as picked up so it can't be picked again
    pickedUpBags[key] = true
    StartCarryBag(entity, isLoose)
    if GarbageDebug then
        print('[Garbage][DEBUG] grantBag -> carrying true; isLoose='..tostring(isLoose)..' entity='..tostring(entity))
        if garbageVehicle and DoesEntityExist(garbageVehicle) and not DepositWatcherActive then
            print('[Garbage][DEBUG] Starting deposit watcher after grantBag')
            StartDepositWatcher(garbageVehicle)
        end
    end
    if remaining ~= nil then
        QBCore.Functions.Notify(('Dumpster remaining: %d bags'):format(remaining), remaining>0 and 'primary' or 'error')
        DumpsterRemaining[key] = remaining
    end
end)

-- Add depot return zone with visible marker and E-prompt (Gruppe6 style)
local depotReturnBlip = nil
local depotReturnActive = false
local returnPromptNotified = false
function AddDepotReturnZone()
    local returnLoc = Config.Garbage.DepotLocation
    returnPromptNotified = false
    -- No GPS waypoint; objective blip only
    -- Create objective blip AT the depot (not on the truck)
    if depotReturnBlip and DoesBlipExist(depotReturnBlip) then
        RemoveBlip(depotReturnBlip)
    end
    local returnBlipCfg = Config.Garbage.ReturnBlip
    depotReturnBlip = AddBlipForCoord(returnLoc.x, returnLoc.y, returnLoc.z)
    SetBlipSprite(depotReturnBlip, returnBlipCfg.sprite)
    SetBlipColour(depotReturnBlip, returnBlipCfg.color)
    SetBlipScale(depotReturnBlip, returnBlipCfg.scale)
    SetBlipDisplay(depotReturnBlip, 4)
    SetBlipAsShortRange(depotReturnBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(returnBlipCfg.label)
    EndTextCommandSetBlipName(depotReturnBlip)
    SetBlipRoute(depotReturnBlip, true)
    SetBlipRouteColour(depotReturnBlip, 3)
    
    -- Start return area watcher (Gruppe6 style)
    if depotReturnActive then return end
    depotReturnActive = true
    
    print('[Garbage] Return zone activated at', returnLoc)
    
    -- Display notice when player completes objective
    QBCore.Functions.Notify('Objective complete! Return to the depot to complete the job', 'success')
    
    local radius = Config.Garbage.DepotRadius
    local markerSize = vector3(6.0, 6.0, 1.0)
    
    CreateThread(function()
        while GarbageJobActive and GarbageObjective >= GarbageObjectiveTarget do
            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)
            local dist = #(pedCoords - returnLoc)
            
            -- Draw cyan marker so players see the zone
            DrawMarker(1, returnLoc.x, returnLoc.y, returnLoc.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                markerSize.x, markerSize.y, markerSize.z, 0, 255, 255, 120, false, false, 2, false, nil, nil, false)
            
            if dist <= radius then
                local veh = GetVehiclePedIsIn(ped, false)
                -- Check if in ANY garbage truck (not just the spawned one)
                if veh ~= 0 and GetEntityModel(veh) == GetHashKey(garbageTruckModel) then
                    if not returnPromptNotified then
                        QBCore.Functions.Notify('Press [E] to return the truck', 'primary')
                        returnPromptNotified = true
                    end

                    if IsControlJustReleased(0, 38) then -- E key
                        -- Trigger return event
                        TriggerEvent('pf-jobs:garbage:returnVehicle')
                        break
                    end
                else
                    returnPromptNotified = false
                end
            else
                returnPromptNotified = false
            end

            Wait(0)
        end

        returnPromptNotified = false
        depotReturnActive = false
    end)
end

-- Return vehicle handler (matches Gruppe6 pattern)
RegisterNetEvent('pf-jobs:garbage:returnVehicle', function()
    if not garbageVehicle then
        QBCore.Functions.Notify('You are not in a garbage truck!', 'error')
        return
    end
    
    QBCore.Functions.Progressbar('return_truck', 'Returning truck to depot...', 3000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function() -- Done
        -- Delete vehicle using QBCore function (same as Gruppe6)
        QBCore.Functions.DeleteVehicle(garbageVehicle)
        
        -- Remove blips
        if garbageVehicleBlip and DoesBlipExist(garbageVehicleBlip) then
            RemoveBlip(garbageVehicleBlip)
            garbageVehicleBlip = nil
        end
        if depotReturnBlip and DoesBlipExist(depotReturnBlip) then
            RemoveBlip(depotReturnBlip)
            depotReturnBlip = nil
        end
        
        -- Cleanup
        garbageVehicle = nil
        truckNetId = nil
        GarbageJobActive = false
        GarbageObjective = 0
        DepotZoneAdded = false
        depotReturnActive = false
        DepositWatcherActive = false
        ActiveZone = nil  -- Clear active zone on job end
        
        -- Clear highlights
        for ent, _ in pairs(HighlightedDumpsters) do
            SetDumpsterOutline(ent, false)
        end
        DumpsterRemaining = {}
        
        HideScoreboard()
        
        -- Notify server
        TriggerServerEvent('pf-jobs:garbage:vehicleReturned')
        QBCore.Functions.Notify('Truck returned successfully!', 'success')
    end, function() -- Cancel
        QBCore.Functions.Notify('Truck return cancelled', 'error')
    end)
end)

-- Toggle garbage debug drawing and logging
RegisterCommand('garbdebug', function()
    GarbageDebug = not GarbageDebug
    QBCore.Functions.Notify('[Garbage] Debug '..(GarbageDebug and 'enabled' or 'disabled'), 'primary')
    print('[Garbage][DEBUG] Debug toggled -> '..tostring(GarbageDebug))
end)

-- Debug command to check targeting status
RegisterCommand('garbcheck', function()
    print('========== GARBAGE JOB DEBUG ==========')
    print('GarbageJobActive:', GarbageJobActive)
    print('Carrying:', carrying)
    print('ActiveZone:', json.encode(ActiveZone))
    print('qb-target resource state:', GetResourceState('pfm-target'))
    print('Player logged in:', LocalPlayer.state.isLoggedIn)
    
    -- Test qb-target export
    local targetExport = exports['pfm-target']
    if targetExport then
        print('qb-target export: AVAILABLE')
    else
        print('qb-target export: NOT AVAILABLE')
    end
    
    -- Count dumpsters
    local count = 0
    for _ in pairs(DumpsterRemaining) do count = count + 1 end
    print('DumpsterRemaining count:', count)
    print('======================================')
    
    QBCore.Functions.Notify('[Garbage] Check results in F8 console', 'primary')
end)

-- Shared depletion updates from other players
RegisterNetEvent('pf-jobs:garbage:dumpsterRemaining', function(netId, remaining)
    if remaining and remaining >= 0 then
        local key = tostring(netId)
        DumpsterRemaining[key] = remaining
        if remaining <= 0 then
            local eid = tonumber(key) and NetToEnt(tonumber(key)) or 0
            if eid and eid ~= 0 and DoesEntityExist(eid) then
                SetDumpsterOutline(eid, false)
            end
        end
        if remaining > 0 then
            QBCore.Functions.Notify(('Dumpster updated: %d bags left'):format(remaining), 'primary')
        else
            QBCore.Functions.Notify('Dumpster depleted', 'error')
        end
    end
end)

-- Session ended: clear client flags
RegisterNetEvent('pf-jobs:garbage:sessionEnded', function()
    GarbageJobActive = false
    GarbageObjective = 0
    DepotZoneAdded = false
    depotReturnActive = false
    if depotReturnBlip and DoesBlipExist(depotReturnBlip) then
        RemoveBlip(depotReturnBlip)
        depotReturnBlip = nil
    end
    if garbageVehicleBlip and DoesBlipExist(garbageVehicleBlip) then
        RemoveBlip(garbageVehicleBlip)
        garbageVehicleBlip = nil
    end
    -- Clear highlights
    for ent, _ in pairs(HighlightedDumpsters) do
        SetDumpsterOutline(ent, false)
    end
    DumpsterRemaining = {}
end)

-- Group system events
RegisterNetEvent('pf-jobs:garbage:groupUpdate', function(group)
    SendNUIMessage({ action = 'garbage:groupUpdate', group = group })
end)

RegisterNetEvent('pf-jobs:garbage:receiveInvite', function(leaderName, leaderId)
    SendNUIMessage({ action = 'garbage:receiveInvite', leaderName = leaderName, leaderId = leaderId })
end)
