-- server.lua - Server-side elevator management

Config = Config or {}
local cfg = Config.Elevators

if not cfg then
    print("^1[Elevator Server] Config.Elevators missing; server elevator disabled.^7")
    return
end

local elevatorEntity = nil
local currentFloor = 1
local isMoving = false
local queuedFloor = nil
local arrivedTime = 0
local currentZ = 0.0

-- Get spawn position from config
local spawnPos = cfg.spawnPos or vector4(3772.080078, 7956.943359, 91.163055, 270.00)
local floors = cfg.floors or {}
local spawnHeading = (cfg.heading or (spawnPos.w or 270.0)) + (cfg.headingOffset or 0.0)
currentZ = spawnPos.z

local function BroadcastElevatorSync(target)
    if not elevatorEntity or not DoesEntityExist(elevatorEntity) then return end
    local netId = NetworkGetNetworkIdFromEntity(elevatorEntity)
    if not netId or netId == 0 then return end
    TriggerClientEvent('pf-elevator:setElevator', target or -1, netId)
end

local function SpawnServerElevator()
    if elevatorEntity and elevatorEntity ~= 0 and DoesEntityExist(elevatorEntity) then
        return true
    end

    local model = cfg.model or `pf_elevatormo`

    local attempts = 0

    while attempts < 20 do
        attempts = attempts + 1
        elevatorEntity = CreateObjectNoOffset(model, spawnPos.x, spawnPos.y, spawnPos.z, true, true, false)

        if elevatorEntity and elevatorEntity ~= 0 and DoesEntityExist(elevatorEntity) then
            SetEntityCoords(elevatorEntity, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, false)
            SetEntityHeading(elevatorEntity, spawnHeading)
            -- SetEntityDynamic / SetEntityCollision / SetNetworkId* are client natives: on the server they
            -- are nil and stopped the spawn ("attempt to call a nil value", seen on staging). The client
            -- sets collision and dynamics itself when it receives the elevator (pf-elevator:setElevator).
            if SetEntityDynamic then SetEntityDynamic(elevatorEntity, true) end
            if SetEntityCollision then SetEntityCollision(elevatorEntity, true, true) end
            FreezeEntityPosition(elevatorEntity, true)

            local netId = NetworkGetNetworkIdFromEntity(elevatorEntity)
            if netId and netId ~= 0 then
                if SetNetworkIdExistsOnAllMachines then SetNetworkIdExistsOnAllMachines(netId, true) end
                if SetNetworkIdCanMigrate then SetNetworkIdCanMigrate(netId, true) end
                print(string.format("^2[Elevator Server] Spawned elevator entity %d (NetID: %d)^7", elevatorEntity, netId))
                BroadcastElevatorSync(-1)
                return true
            end

            DeleteEntity(elevatorEntity)
            elevatorEntity = nil
        end

        Wait(500)
    end

    print("^1[Elevator Server] Failed to spawn elevator after multiple attempts.^7")
    return false
end

-- Spawn elevator on server start
CreateThread(function()
    Wait(1000) -- Wait for resources to load
    SpawnServerElevator()

    while true do
        Wait(2000)
        if not elevatorEntity or elevatorEntity == 0 or not DoesEntityExist(elevatorEntity) then
            SpawnServerElevator()
        end
    end
end)

RegisterNetEvent('pf-elevator:requestSync', function()
    local src = source
    if elevatorEntity and DoesEntityExist(elevatorEntity) then
        BroadcastElevatorSync(src)
    else
        if SpawnServerElevator() then
            BroadcastElevatorSync(src)
        end
    end
end)

-- Handle floor requests from clients
-- the elevator panels are inside the shaft and at its call buttons
local REQUEST_RANGE = 25.0

RegisterNetEvent('pf-elevator:requestFloor', function(floorIndex)
    local source = source
    
    floorIndex = tonumber(floorIndex)
    if not floorIndex or not floors[floorIndex] then
        print(string.format("^1[Elevator] Invalid floor index: %s^7", tostring(floorIndex)))
        return
    end

    -- horizontal distance to the shaft: the floors stack above it
    local coords = GetEntityCoords(GetPlayerPed(source))
    if #(vector2(coords.x, coords.y) - vector2(spawnPos.x, spawnPos.y)) > REQUEST_RANGE then
        return
    end

    print(string.format("^3[Elevator] Floor request from %d -> floor %d (z=%.3f)^7", source, floorIndex, floors[floorIndex].z))
    
    if isMoving then
        -- Queue the request
        queuedFloor = floorIndex
        TriggerClientEvent('pf-elevator:notify', source, "Floor queued")
        return
    end

    -- Move immediately
    MoveToFloor(floorIndex)
    TriggerClientEvent('pf-elevator:notify', source, "Floor requested")
end)

-- Process queued floor requests even when no movement has started yet
CreateThread(function()
    while true do
        Wait(250)

        if queuedFloor and not isMoving then
            local nextFloor = queuedFloor
            queuedFloor = nil
            MoveToFloor(nextFloor)
        end
    end
end)

function MoveToFloor(floorIndex)
    local floor = floors[floorIndex]
    if not floor then return end

    print(string.format("^2[Elevator] Moving to floor %d (z=%.3f)^7", floorIndex, floor.z))
    
    isMoving = true
    currentFloor = floorIndex

    local startZ = currentZ
    local targetZ = floor.z
    local distance = math.abs(targetZ - startZ)
    local speed = cfg.speed or 1.0
    local duration = math.max(distance / speed, 0.01) * 1000 -- milliseconds
    
    -- Wait for doors to close before moving (door animation takes ~1 second)
    local doorCloseDelay = 1200  -- milliseconds to allow doors to fully close

    -- Notify all clients with explicit movement timeline/state
    TriggerClientEvent('pf-elevator:startMoving', -1, startZ, targetZ, duration, speed, spawnHeading)
    
    -- Server authoritative state/timing, clients render movement locally.
    CreateThread(function()
        Wait(doorCloseDelay)  -- Wait for doors to close
        
        Wait(math.floor(duration))

        currentZ = targetZ
        print(string.format("^2[Elevator] Arrived z=%.3f (target %.3f)^7", currentZ, targetZ))
        
        isMoving = false
        arrivedTime = GetGameTimer()
        
        -- Notify clients movement complete
        TriggerClientEvent('pf-elevator:arrivedAt', -1, targetZ, spawnHeading)
    end)
end

-- Debug command
RegisterCommand('elevatorinfo', function(source)
    local pos = DoesEntityExist(elevatorEntity) and GetEntityCoords(elevatorEntity) or vector3(0,0,0)
    local netId = DoesEntityExist(elevatorEntity) and NetworkGetNetworkIdFromEntity(elevatorEntity) or 0
    
    print(string.format("^3=== Elevator Server Info ===^7"))
    print(string.format("Entity: %d | NetID: %d", elevatorEntity or 0, netId))
    print(string.format("Position: %.2f, %.2f, %.2f", pos.x, pos.y, pos.z))
    print(string.format("Current Floor: %d | Moving: %s", currentFloor, isMoving and "Yes" or "No"))
    print(string.format("Queued Floor: %s", queuedFloor and tostring(queuedFloor) or "None"))
    
    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, {
            args = {"Elevator", string.format("Floor %d | Moving: %s", currentFloor, isMoving and "Yes" or "No")}
        })
    end
end, true)
