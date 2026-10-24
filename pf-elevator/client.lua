-- client/elevator_any_prop.lua

-- ===== Config compatibility =====
-- Works with either:
-- 1) Your old vehicle-style list (we only use floors from [1] and the model name)
-- 2) A simplified { model=..., floors=..., speed=... }

Config = Config or {}
local cfg = Config.Elevators
local MODEL_NAME
local FLOORS
local SPEED = 1.5
local ALT_MODELS = {}
local SPAWN_COORDS = vector3(3779.08, 7941.04, 91.02)
local SPAWN_HEADING = 93.37
local TARGET_HEADING = 93.37

-- ===== qb-doorlock compatibility =====
local hasQBDoorlock = pcall(function() IsDoorRegisteredWithSystem end)

local function SafeAddDoorToSystem(doorHash, objModel, x, y, z, isNetwork, scriptNetwork, hardlock)
    if hasQBDoorlock then
        return AddDoorToSystem(doorHash, objModel, x, y, z, isNetwork or false, scriptNetwork or false, hardlock or false)
    end
end

local function SafeRemoveDoorFromSystem(doorHash)
    if hasQBDoorlock then
        return RemoveDoorFromSystem(doorHash)
    end
end

local function SafeIsDoorRegisteredWithSystem(doorHash)
    if hasQBDoorlock then
        return IsDoorRegisteredWithSystem(doorHash)
    end
    return false
end

local function SafeDoorSystemSetDoorState(doorHash, state, isNetwork, isNaked)
    if hasQBDoorlock then
        return DoorSystemSetDoorState(doorHash, state, isNetwork or false, isNaked or false)
    end
end

if cfg then
    if cfg.model and cfg.floors then
        -- Simplified single block
        MODEL_NAME = cfg.model
        FLOORS = cfg.floors
        SPEED = cfg.speed or SPEED
        ALT_MODELS = cfg.altModels or {}
        if cfg.spawnPos then
            SPAWN_COORDS = vector3(cfg.spawnPos.x, cfg.spawnPos.y, cfg.spawnPos.z)
            SPAWN_HEADING = cfg.spawnPos.w or SPAWN_HEADING
        end
        TARGET_HEADING = (cfg.heading or SPAWN_HEADING) + (cfg.headingOffset or 0.0)
    elseif type(cfg) == "table" and cfg[1] then
        -- Your posted format: use entry[1]
        MODEL_NAME = cfg[1].model
        FLOORS = cfg[1].floors
        SPEED = 1.5
        ALT_MODELS = cfg[1].altModels or {}
        if cfg[1].spawnPos then
            SPAWN_COORDS = vector3(cfg[1].spawnPos.x, cfg[1].spawnPos.y, cfg[1].spawnPos.z)
            SPAWN_HEADING = cfg[1].spawnPos.w or SPAWN_HEADING
        end
        TARGET_HEADING = (cfg[1].heading or SPAWN_HEADING) + (cfg[1].headingOffset or 0.0)
    end
end

-- Safety
if not MODEL_NAME then
    MODEL_NAME = 'yft_test'
end
if not FLOORS or #FLOORS == 0 then
    FLOORS = {
        { label = "Ground Floor", z = 90.11471 },
        { label = "First Floor",  z = 120.0 },
        { label = "Rooftop",      z = 150.0 },
    }
end

-- ===== Settings =====
local INTERACT_KEY = 38      -- E
local INTERACT_RANGE = 3.0
local TEXT_OFFSET_Z = 1.4
local MOVE_TICK_MS = 16
local RESCAN_MS = 8000
local CONTROL_TIMEOUT_MS = 1500

-- ===== State =====
local elevators = {}   -- [entity] = { ent=entity, baseZ=number, heading=number, moving=bool, arrivedAt=number, arrivedTime=number, queuedFloor=number }
local lastScan = 0
local spawnedElevator = nil
local headingAdjustment = 0.0

-- ===== Utils =====
local function toHash(model)
    if type(model) == "number" then return model end
    if type(model) == "string" then return GetHashKey(model) end
    return model
end

local TARGET_HASH = toHash(MODEL_NAME)
local TARGET_IS_VEHICLE = IsModelAVehicle(TARGET_HASH)

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function DrawText3D(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    local cam = GetGameplayCamCoords()
    local dist = #(cam - coords)
    local scale = clamp(0.35 / dist, 0.3, 0.7)

    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(_x, _y)
end

local function Notify(msg)
    if lib and lib.notify then
        lib.notify({ title = 'Elevator', description = msg, type = 'info' })
    else
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function RequestEntityControl(ent, timeoutMs)
    local start = GetGameTimer()
    if NetworkHasControlOfEntity(ent) then return true end
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) do
        Wait(0)
        NetworkRequestControlOfEntity(ent)
        if GetGameTimer() - start > (timeoutMs or CONTROL_TIMEOUT_MS) then
            return false
        end
    end
    return true
end

-- Enumerator for ALL objects, reliable for YMAP props
local function EnumerateObjects()
    return coroutine.wrap(function()
        local handle, obj = FindFirstObject()
        if handle == -1 then
            EndFindObject(handle)
            return
        end
        local ok = true
        repeat
            coroutine.yield(obj)
            ok, obj = FindNextObject(handle)
        until not ok
        EndFindObject(handle)
    end)
end

local function EnumerateVehicles()
    return coroutine.wrap(function()
        local handle, veh = FindFirstVehicle()
        if handle == -1 then
            EndFindVehicle(handle)
            return
        end
        local ok = true
        repeat
            coroutine.yield(veh)
            ok, veh = FindNextVehicle(handle)
        until not ok
        EndFindVehicle(handle)
    end)
end
local AddElevator
local GetActiveElevatorEntity
local serverElevatorNetId = nil
local syncRequestedAt = 0
local localFallbackElevator = nil

local function EnsureLocalFallbackElevator()
    if localFallbackElevator and DoesEntityExist(localFallbackElevator) then
        return localFallbackElevator
    end

    local mdl = TARGET_HASH
    if not IsModelInCdimage(mdl) then return nil end

    RequestModel(mdl)
    local waitStart = GetGameTimer()
    while not HasModelLoaded(mdl) do
        Wait(0)
        if GetGameTimer() - waitStart > 8000 then
            return nil
        end
    end

    local ent = CreateObjectNoOffset(mdl, SPAWN_COORDS.x, SPAWN_COORDS.y, SPAWN_COORDS.z, false, false, false)
    SetModelAsNoLongerNeeded(mdl)
    if not ent or ent == 0 or not DoesEntityExist(ent) then
        return nil
    end

    SetEntityHeading(ent, TARGET_HEADING + headingAdjustment)
    SetEntityVisible(ent, true, false)
    SetEntityAlpha(ent, 255, false)
    SetEntityCollision(ent, true, true)
    SetEntityAsMissionEntity(ent, true, true)
    SetEntityLodDist(ent, 10000)
    SetEntityDynamic(ent, false)
    FreezeEntityPosition(ent, true)

    localFallbackElevator = ent
    if not spawnedElevator or not DoesEntityExist(spawnedElevator) then
        spawnedElevator = ent
    end
    if AddElevator then AddElevator(ent) end
    print(string.format("^2[Elevator Client] Spawned local fallback elevator %d^7", ent))
    return ent
end

local function IsTargetElevatorModel(model)
    if model == TARGET_HASH then return true end
    for _, altModel in ipairs(ALT_MODELS) do
        if model == toHash(altModel) then return true end
    end
    return false
end

local function TryAdoptNearbyElevator()
    local bestEnt, bestDist = nil, 9999.0

    for obj in EnumerateObjects() do
        if DoesEntityExist(obj) and IsTargetElevatorModel(GetEntityModel(obj)) then
            local opos = GetEntityCoords(obj)
            local d = #(opos - SPAWN_COORDS)
            if d < bestDist then
                bestDist = d
                bestEnt = obj
            end
        end
    end

    if bestEnt and bestDist < 50.0 then
        spawnedElevator = bestEnt
        if AddElevator then AddElevator(bestEnt) end
        print(("^2[Elevator Client] Adopted nearby elevator entity %d (dist %.2f)^7"):format(bestEnt, bestDist))
        return true
    end

    return false
end

-- ===== DOOR MANAGEMENT =====
local doorState = {
    elevatorLeftDoor = nil,
    elevatorRightDoor = nil,
    floorDoors = {},  -- [floor_index] = { left = ent, right = ent }
    doorsOpen = true,
    currentFloor = 1,  -- Track which floor elevator is on
}

local function GetDoorModelHash(side)
    if not cfg or not cfg.doors then
        print("^1[Doors] Configuration not found! cfg.doors is nil^7")
        return nil
    end
    if side == "left" then
        return GetHashKey(cfg.doors.leftModel or "v_ilev_fib_doore_l")
    else
        return GetHashKey(cfg.doors.rightModel or "v_ilev_fib_doore_r")
    end
end

local function LoadDoorModel(side)
    local mdl = GetDoorModelHash(side)
    if not mdl then
        print(string.format("^1[Doors] Could not get hash for %s door^7", side))
        return false
    end
    print(string.format("^3[Doors] Checking %s model (hash: %d)^7", side, mdl))
    if IsModelInCdimage(mdl) then
        print(string.format("^2[Doors] Model %s is in CD image, loading...^7", side))
        RequestModel(mdl)
        local waitStart = GetGameTimer()
        while not HasModelLoaded(mdl) do
            Wait(0)
            if GetGameTimer() - waitStart > 5000 then
                print(string.format("^1[Doors] Failed to load %s door model (timeout)^7", side))
                return false
            end
        end
        print(string.format("^2[Doors] Loaded %s door model successfully^7", side))
        return true
    else
        print(string.format("^1[Doors] %s model NOT in CD image (hash: %d), trying to load anyway...^7", side, mdl))
        -- Try to load anyway as fallback
        RequestModel(mdl)
        local waitStart = GetGameTimer()
        while not HasModelLoaded(mdl) do
            Wait(0)
            if GetGameTimer() - waitStart > 5000 then
                print(string.format("^1[Doors] Failed to load %s door model (fallback timeout)^7", side))
                return false
            end
        end
        return true
    end
end

local function SpawnElevatorDoors()
    if not spawnedElevator or not DoesEntityExist(spawnedElevator) then
        print("^1[Doors] No spawned elevator entity found^7")
        return
    end

    local basePos = GetEntityCoords(spawnedElevator)
    print(string.format("^3[Doors] Spawning elevator doors at pos: %.2f, %.2f, %.2f^7", basePos.x, basePos.y, basePos.z))

    -- Spawn left door
    if LoadDoorModel("left") then
        local leftPos = basePos + cfg.doors.elevatorDoorLeftClosedOffset
        print(string.format("^3[Doors] Creating left door at: %.2f, %.2f, %.2f^7", leftPos.x, leftPos.y, leftPos.z))
        local leftDoor = CreateObjectNoOffset(GetDoorModelHash("left"), leftPos.x, leftPos.y, leftPos.z, false, false, false)
        if leftDoor and DoesEntityExist(leftDoor) then
            print(string.format("^2[Doors] Left door created (entity %d)^7", leftDoor))
            SetEntityAsMissionEntity(leftDoor, true, true)
            SetEntityCollision(leftDoor, true, true)
            SetEntityVisible(leftDoor, true, false)
            SetEntityAlpha(leftDoor, 255, false)
            SetEntityLodDist(leftDoor, 10000)
            FreezeEntityPosition(leftDoor, true)
            doorState.elevatorLeftDoor = leftDoor
            
            -- Register with qb-doorlock
            if hasQBDoorlock then
                local doorHash = "pf_elevator_left_car"
                if not SafeIsDoorRegisteredWithSystem(doorHash) then
                    SafeAddDoorToSystem(doorHash, GetDoorModelHash("left"), leftPos.x, leftPos.y, leftPos.z, false, false, false)
                end
                SafeDoorSystemSetDoorState(doorHash, 0, false, false)  -- Unlocked
                print(string.format("^2[Doors] Left door registered with qb-doorlock^7"))
            end
        else
            print("^1[Doors] Failed to create left door entity^7")
        end
        SetModelAsNoLongerNeeded(GetDoorModelHash("left"))
    end

    -- Spawn right door
    if LoadDoorModel("right") then
        local rightPos = basePos + cfg.doors.elevatorDoorRightClosedOffset
        print(string.format("^3[Doors] Creating right door at: %.2f, %.2f, %.2f^7", rightPos.x, rightPos.y, rightPos.z))
        local rightDoor = CreateObjectNoOffset(GetDoorModelHash("right"), rightPos.x, rightPos.y, rightPos.z, false, false, false)
        if rightDoor and DoesEntityExist(rightDoor) then
            print(string.format("^2[Doors] Right door created (entity %d)^7", rightDoor))
            SetEntityAsMissionEntity(rightDoor, true, true)
            SetEntityCollision(rightDoor, true, true)
            SetEntityVisible(rightDoor, true, false)
            SetEntityAlpha(rightDoor, 255, false)
            SetEntityLodDist(rightDoor, 10000)
            FreezeEntityPosition(rightDoor, true)
            doorState.elevatorRightDoor = rightDoor
            
            -- Register with qb-doorlock
            if hasQBDoorlock then
                local doorHash = "pf_elevator_right_car"
                if not SafeIsDoorRegisteredWithSystem(doorHash) then
                    SafeAddDoorToSystem(doorHash, GetDoorModelHash("right"), rightPos.x, rightPos.y, rightPos.z, false, false, false)
                end
                SafeDoorSystemSetDoorState(doorHash, 0, false, false)  -- Unlocked
                print(string.format("^2[Doors] Right door registered with qb-doorlock^7"))
            end
        else
            print("^1[Doors] Failed to create right door entity^7")
        end
        SetModelAsNoLongerNeeded(GetDoorModelHash("right"))
    end

    print("^2[Doors] Spawned elevator doors^7")
    print(string.format("^3[Doors] qb-doorlock available: %s^7", hasQBDoorlock and "Yes" or "No"))
end

local function SpawnFloorDoors()
    print("^3[Doors] Starting to spawn floor doors for all floors^7")
    for i, floor in ipairs(FLOORS) do
        -- Position doors on each side of the floor entrance
        local basePos = vector3(floor.callButton.x, floor.callButton.y, floor.z)
        local doorOffset = floor.doorOffset or vector3(0.0, 0.0, 0.0)

        -- Spawn left door
        if LoadDoorModel("left") then
            local leftPos = basePos + vector3(-0.5, doorOffset.y, doorOffset.z)
            print(string.format("^3[Doors] Creating floor %d left door at: %.2f, %.2f, %.2f^7", i, leftPos.x, leftPos.y, leftPos.z))
            local leftDoor = CreateObjectNoOffset(GetDoorModelHash("left"), leftPos.x, leftPos.y, leftPos.z, false, false, false)
            if leftDoor and DoesEntityExist(leftDoor) then
                print(string.format("^2[Doors] Floor %d left door created (entity %d)^7", i, leftDoor))
                SetEntityAsMissionEntity(leftDoor, true, true)
                SetEntityCollision(leftDoor, true, true)
                SetEntityVisible(leftDoor, true, false)
                SetEntityAlpha(leftDoor, 255, false)
                SetEntityLodDist(leftDoor, 10000)
                FreezeEntityPosition(leftDoor, true)
                doorState.floorDoors[i] = doorState.floorDoors[i] or {}
                doorState.floorDoors[i].left = leftDoor
                
                -- Register with qb-doorlock
                RegisterDoorWithQBDoorlock(leftDoor, "pf_elevatorfloor_" .. i .. "_left")
            else
                print(string.format("^1[Doors] Failed to create floor %d left door^7", i))
            end
            SetModelAsNoLongerNeeded(GetDoorModelHash("left"))
        end

        -- Spawn right door
        if LoadDoorModel("right") then
            local rightPos = basePos + vector3(0.5, doorOffset.y, doorOffset.z)
            print(string.format("^3[Doors] Creating floor %d right door at: %.2f, %.2f, %.2f^7", i, rightPos.x, rightPos.y, rightPos.z))
            local rightDoor = CreateObjectNoOffset(GetDoorModelHash("right"), rightPos.x, rightPos.y, rightPos.z, false, false, false)
            if rightDoor and DoesEntityExist(rightDoor) then
                print(string.format("^2[Doors] Floor %d right door created (entity %d)^7", i, rightDoor))
                SetEntityAsMissionEntity(rightDoor, true, true)
                SetEntityCollision(rightDoor, true, true)
                SetEntityVisible(rightDoor, true, false)
                SetEntityAlpha(rightDoor, 255, false)
                SetEntityLodDist(rightDoor, 10000)
                FreezeEntityPosition(rightDoor, true)
                doorState.floorDoors[i] = doorState.floorDoors[i] or {}
                doorState.floorDoors[i].right = rightDoor
                
                -- Register with qb-doorlock
                RegisterDoorWithQBDoorlock(rightDoor, "pf_elevatorfloor_" .. i .. "_right")
            else
                print(string.format("^1[Doors] Failed to create floor %d right door^7", i))
            end
            SetModelAsNoLongerNeeded(GetDoorModelHash("right"))
        end
    end

    print("^2[Doors] Spawned floor doors^7")
end

local function InitializeFloorDoorsAsClosed()
    print("^3[Doors] Initializing all floor doors as CLOSED and LOCKED^7")
    for i, floorDoors in pairs(doorState.floorDoors) do
        -- Lock floor doors
        if floorDoors.left then
            SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_left", 1, false, false)  -- Locked
            print(string.format("^2[Doors] Floor %d left door locked^7", i))
        end
        if floorDoors.right then
            SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_right", 1, false, false)  -- Locked
            print(string.format("^2[Doors] Floor %d right door locked^7", i))
        end
    end
    doorState.doorsOpen = false  -- Mark doors as closed initially
    print("^2[Doors] All floor doors initialized as closed^7")
end

local function RegisterDoorWithQBDoorlock(doorEnt, doorHash)
    if not doorEnt or not DoesEntityExist(doorEnt) then return end
    if not hasQBDoorlock then return end
    
    local doorCoords = GetEntityCoords(doorEnt)
    local doorModel = GetEntityModel(doorEnt)
    
    -- Register door with qb-doorlock system
    if SafeIsDoorRegisteredWithSystem(doorHash) then
        SafeDoorSystemSetDoorState(doorHash, 0, false, false)  -- Unlocked
    else
        SafeAddDoorToSystem(doorHash, doorModel, doorCoords.x, doorCoords.y, doorCoords.z, false, false, false)
        SafeDoorSystemSetDoorState(doorHash, 0, false, false)  -- Unlocked by default
    end
end

local function LockElevatorDoors()
    if not hasQBDoorlock then return end
    
    -- Lock all elevator doors
    if doorState.elevatorLeftDoor and DoesEntityExist(doorState.elevatorLeftDoor) then
        local doorHash = "pf_elevator_left_car"
        local coords = GetEntityCoords(doorState.elevatorLeftDoor)
        if not SafeIsDoorRegisteredWithSystem(doorHash) then
            SafeAddDoorToSystem(doorHash, GetEntityModel(doorState.elevatorLeftDoor), coords.x, coords.y, coords.z, false, false, false)
        end
        SafeDoorSystemSetDoorState(doorHash, 1, false, false)  -- Locked
    end
    
    if doorState.elevatorRightDoor and DoesEntityExist(doorState.elevatorRightDoor) then
        local doorHash = "pf_elevator_right_car"
        local coords = GetEntityCoords(doorState.elevatorRightDoor)
        if not SafeIsDoorRegisteredWithSystem(doorHash) then
            SafeAddDoorToSystem(doorHash, GetEntityModel(doorState.elevatorRightDoor), coords.x, coords.y, coords.z, false, false, false)
        end
        SafeDoorSystemSetDoorState(doorHash, 1, false, false)  -- Locked
    end
    
    -- Lock floor doors
    for i, floorDoors in pairs(doorState.floorDoors) do
        if floorDoors.left and DoesEntityExist(floorDoors.left) then
            SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_left", 1, false, false)  -- Locked
        end
        if floorDoors.right and DoesEntityExist(floorDoors.right) then
            SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_right", 1, false, false)  -- Locked
        end
    end
end

local function UnlockElevatorDoors(floorIndex)
    if not hasQBDoorlock then return end
    
    -- Unlock only the doors at the current floor
    if floorIndex then
        -- Unlock floor doors
        if doorState.floorDoors[floorIndex] then
            if doorState.floorDoors[floorIndex].left then
                SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. floorIndex .. "_left", 0, false, false)  -- Unlocked
            end
            if doorState.floorDoors[floorIndex].right then
                SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. floorIndex .. "_right", 0, false, false)  -- Unlocked
            end
        end
    end
    
    -- Always unlock elevator car doors
    if doorState.elevatorLeftDoor then
        SafeDoorSystemSetDoorState("pf_elevator_left_car", 0, false, false)  -- Unlocked
    end
    if doorState.elevatorRightDoor then
        SafeDoorSystemSetDoorState("pf_elevator_right_car", 0, false, false)  -- Unlocked
    end
end

local function AnimateDoor(doorEnt, isOpening, side, callback)
    if not doorEnt or not DoesEntityExist(doorEnt) then 
        if callback then callback() end
        return 
    end

    CreateThread(function()
        FreezeEntityPosition(doorEnt, false)
        
        local startPos = GetEntityCoords(doorEnt)
        local slideDistance = cfg.doors.doorSlideDistance or 0.6
        local animSpeed = cfg.doors.doorAnimationSpeed or 1.0
        local duration = slideDistance / animSpeed
        
        local targetX = startPos.x
        if side == "left" then
            targetX = isOpening and (startPos.x - slideDistance) or (startPos.x + slideDistance)
        else
            targetX = isOpening and (startPos.x + slideDistance) or (startPos.x - slideDistance)
        end

        local startTime = GetGameTimer()
        local completed = false

        while not completed do
            if not DoesEntityExist(doorEnt) then break end
            
            local elapsed = (GetGameTimer() - startTime) / 1000.0
            local t = clamp(elapsed / duration, 0.0, 1.0)
            local currentX = startPos.x + (targetX - startPos.x) * t

            SetEntityCoords(doorEnt, currentX, startPos.y, startPos.z, false, false, false, false)

            if t >= 1.0 then
                SetEntityCoords(doorEnt, targetX, startPos.y, startPos.z, false, false, false, false)
                completed = true
            end

            Wait(0)
        end

        FreezeEntityPosition(doorEnt, true)
        if callback then callback() end
    end)
end

local doorsClosing = false
local doorsOpening = false

local function CloseDoors()
    if doorState.doorsOpen and not doorsClosing then
        doorsClosing = true
        doorState.doorsOpen = false
        
        -- Lock doors before closing
        LockElevatorDoors()
        
        AnimateDoor(doorState.elevatorLeftDoor, false, "left")
        AnimateDoor(doorState.elevatorRightDoor, false, "right")
        
        -- Close current floor doors
        if spawnedElevator and DoesEntityExist(spawnedElevator) then
            local elevPos = GetEntityCoords(spawnedElevator)
            local closestFloor = 1
            local closestDist = 9999.0

            for i, floor in ipairs(FLOORS) do
                local dist = math.abs(floor.z - elevPos.z)
                if dist < closestDist then
                    closestDist = dist
                    closestFloor = i
                end
            end

            if doorState.floorDoors[closestFloor] then
                AnimateDoor(doorState.floorDoors[closestFloor].left, false, "left")
                AnimateDoor(doorState.floorDoors[closestFloor].right, false, "right", function()
                    doorsClosing = false
                end)
            else
                doorsClosing = false
            end
        else
            doorsClosing = false
        end
    end
end

local function OpenDoors(floorIndex)
    if not doorState.doorsOpen and not doorsOpening then
        doorsOpening = true
        doorState.doorsOpen = true
        doorState.currentFloor = floorIndex
        
        -- Close and lock all OTHER floor doors
        for i, floorDoors in pairs(doorState.floorDoors) do
            if i ~= floorIndex then
                -- Close doors for other floors
                if floorDoors.left and DoesEntityExist(floorDoors.left) then
                    AnimateDoor(floorDoors.left, false, "left")
                    SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_left", 1, false, false)  -- Lock
                end
                if floorDoors.right and DoesEntityExist(floorDoors.right) then
                    AnimateDoor(floorDoors.right, false, "right")
                    SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_right", 1, false, false)  -- Lock
                end
            end
        end
        
        -- Open elevator car doors
        AnimateDoor(doorState.elevatorLeftDoor, true, "left")
        AnimateDoor(doorState.elevatorRightDoor, true, "right")

        -- Open doors for current floor
        if floorIndex and doorState.floorDoors[floorIndex] then
            AnimateDoor(doorState.floorDoors[floorIndex].left, true, "left")
            AnimateDoor(doorState.floorDoors[floorIndex].right, true, "right", function()
                doorsOpening = false
                -- Unlock doors after fully opened
                UnlockElevatorDoors(floorIndex)
            end)
        else
            doorsOpening = false
            UnlockElevatorDoors(floorIndex)
        end
    end
end

-- Keep elevator doors synchronized with elevator movement
CreateThread(function()
    while true do
        Wait(0)
        
        if spawnedElevator and DoesEntityExist(spawnedElevator) then
            local elevPos = GetEntityCoords(spawnedElevator)
            
            if doorState.elevatorLeftDoor and DoesEntityExist(doorState.elevatorLeftDoor) then
                local doorPos = GetEntityCoords(doorState.elevatorLeftDoor)
                local leftTarget = vector3(
                    elevPos.x + cfg.doors.elevatorDoorLeftClosedOffset.x,
                    elevPos.y + cfg.doors.elevatorDoorLeftClosedOffset.y,
                    elevPos.z + cfg.doors.elevatorDoorLeftClosedOffset.z
                )
                -- Only update Z axis (elevator moving up/down), preserve X,Y for sliding animation
                if math.abs(doorPos.z - elevPos.z) > 0.01 then
                    SetEntityCoords(doorState.elevatorLeftDoor, doorPos.x, doorPos.y, elevPos.z + cfg.doors.elevatorDoorLeftClosedOffset.z, false, false, false, false)
                end
            end
            
            if doorState.elevatorRightDoor and DoesEntityExist(doorState.elevatorRightDoor) then
                local doorPos = GetEntityCoords(doorState.elevatorRightDoor)
                local rightTarget = vector3(
                    elevPos.x + cfg.doors.elevatorDoorRightClosedOffset.x,
                    elevPos.y + cfg.doors.elevatorDoorRightClosedOffset.y,
                    elevPos.z + cfg.doors.elevatorDoorRightClosedOffset.z
                )
                -- Only update Z axis (elevator moving up/down), preserve X,Y for sliding animation
                if math.abs(doorPos.z - elevPos.z) > 0.01 then
                    SetEntityCoords(doorState.elevatorRightDoor, doorPos.x, doorPos.y, elevPos.z + cfg.doors.elevatorDoorRightClosedOffset.z, false, false, false, false)
                end
            end
        end
    end
end)

-- Receive elevator entity from server
RegisterNetEvent('pf-elevator:setElevator', function(netId)
    if serverElevatorNetId == netId and spawnedElevator and DoesEntityExist(spawnedElevator) then
        return
    end

    serverElevatorNetId = netId
    
    CreateThread(function()
        local attempts = 0
        while not NetworkDoesEntityExistWithNetworkId(netId) and attempts < 100 do
            Wait(100)
            attempts = attempts + 1
        end
        
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local ent = NetworkGetEntityFromNetworkId(netId)
            if not spawnedElevator or not DoesEntityExist(spawnedElevator) then
                spawnedElevator = ent
            end
            if AddElevator then AddElevator(ent) end
            print(string.format("^2[Elevator Client] Received elevator entity %d from server^7", ent))
        else
            print("^1[Elevator Client] Failed to get elevator entity from server^7")
            TryAdoptNearbyElevator()
        end
    end)
end)

-- Server movement notifications
RegisterNetEvent('pf-elevator:startMoving', function(a, b, c, d, e)
    local fromZ, targetZ, durationMs, speed, serverHeading
    if c ~= nil then
        fromZ = a
        targetZ = b
        durationMs = c
        speed = d
        serverHeading = e
    else
        targetZ = a
        speed = b
        serverHeading = nil
    end

    local movingEnt = GetActiveElevatorEntity()
    if movingEnt and elevators[movingEnt] then
        elevators[movingEnt].moving = true
    end

    -- Close doors before movement
    CloseDoors()

    if movingEnt and DoesEntityExist(movingEnt) then
        CreateThread(function()
            local ent = movingEnt
            if not RequestEntityControl(ent, 3000) then
                print("^1[Elevator Client] No network control for movement^7")
            end

            local pos = GetEntityCoords(ent)
            local startZ = fromZ or pos.z
            local moveSpeed = (speed and speed > 0.0) and speed or SPEED
            local dist = math.abs(targetZ - startZ)
            local duration = durationMs and (durationMs / 1000.0) or math.max(dist / moveSpeed, 0.01)
            local heading = serverHeading or (TARGET_HEADING + headingAdjustment)
            local startTime = GetGameTimer()

            -- Keep entity frozen during entire movement to prevent jittering
            FreezeEntityPosition(ent, true)
            SetEntityDynamic(ent, false)
            SetEntityLodDist(ent, 10000)
            SetEntityVisible(ent, true, false)
            SetEntityAlpha(ent, 255, false)

            while true do
                if not DoesEntityExist(ent) then break end
                local elapsed = (GetGameTimer() - startTime) / 1000.0
                local t = clamp(elapsed / duration, 0.0, 1.0)
                local currentZ = startZ + ((targetZ - startZ) * t)

                -- Move frozen entity without physics simulation
                SetEntityCoordsNoOffset(ent, pos.x, pos.y, currentZ, false, false, false)
                SetEntityHeading(ent, heading)
                
                -- Force visibility every frame
                SetEntityVisible(ent, true, false)
                SetEntityAlpha(ent, 255, false)

                if t >= 1.0 then break end
                Wait(0)
            end

            -- Ensure final position is exact
            SetEntityCoordsNoOffset(ent, pos.x, pos.y, targetZ, false, false, false)
            SetEntityHeading(ent, heading)
            SetEntityVisible(ent, true, false)
            SetEntityAlpha(ent, 255, false)
            FreezeEntityPosition(ent, true)
        end)
    end
end)

RegisterNetEvent('pf-elevator:arrivedAt', function(z, serverHeading)
    local movingEnt = GetActiveElevatorEntity()
    if movingEnt and elevators[movingEnt] then
        elevators[movingEnt].moving = false
        elevators[movingEnt].arrivedAt = z
        elevators[movingEnt].arrivedTime = GetGameTimer()
    end

    if movingEnt and DoesEntityExist(movingEnt) then
        local pos = GetEntityCoords(movingEnt)
        SetEntityCoordsNoOffset(movingEnt, pos.x, pos.y, z, false, false, false)
        SetEntityHeading(movingEnt, serverHeading or (TARGET_HEADING + headingAdjustment))
        SetEntityVisible(movingEnt, true, false)
        SetEntityAlpha(movingEnt, 255, false)

        -- Open doors at arrived floor
        local closestFloor = 1
        local closestDist = 9999.0
        for i, floor in ipairs(FLOORS) do
            local dist = math.abs(floor.z - z)
            if dist < closestDist then
                closestDist = dist
                closestFloor = i
            end
        end
        OpenDoors(closestFloor)
    end
end)

RegisterNetEvent('pf-elevator:notify', function(msg)
    Notify(msg)
end)

local function IsValidElevatorEnt(ent)
    if not DoesEntityExist(ent) then return false end
    local model = GetEntityModel(ent)
    if model == TARGET_HASH then return true end
    
    -- Check alt models
    for _, altModel in ipairs(ALT_MODELS) do
        if model == toHash(altModel) then return true end
    end
    
    return false
end

GetActiveElevatorEntity = function()
    if localFallbackElevator and DoesEntityExist(localFallbackElevator) then
        return localFallbackElevator
    end
    if spawnedElevator and DoesEntityExist(spawnedElevator) then
        return spawnedElevator
    end
    for ent, _ in pairs(elevators) do
        if DoesEntityExist(ent) then
            return ent
        end
    end
    return nil
end

AddElevator = function(ent)
    if elevators[ent] then return end
    if not IsValidElevatorEnt(ent) then return end

    if not spawnedElevator or not DoesEntityExist(spawnedElevator) then
        spawnedElevator = ent
        -- Spawn doors for elevator when first detected
        if not doorState.elevatorLeftDoor or not DoesEntityExist(doorState.elevatorLeftDoor) then
            SpawnElevatorDoors()
        end
        if not doorState.floorDoors or #doorState.floorDoors == 0 then
            SpawnFloorDoors()
            -- Initialize all floor doors as closed
            InitializeFloorDoorsAsClosed()
        end
    end

    RequestEntityControl(ent)
    SetEntityAsMissionEntity(ent, true, true)
    SetEntityCanBeDamaged(ent, false)
    SetEntityProofs(ent, true, true, true, true, true, true, true, true)
    FreezeEntityPosition(ent, true)

    local pos = GetEntityCoords(ent)
    elevators[ent] = {
        ent = ent,
        baseZ = pos.z,
        heading = GetEntityHeading(ent),
        moving = false,
        arrivedAt = pos.z,
        arrivedTime = GetGameTimer(),
        queuedFloor = nil,
    }
end

local function CleanElevators()
    for ent, _ in pairs(elevators) do
        if not DoesEntityExist(ent) then
            elevators[ent] = nil
        end
    end
end

local function SpawnElevator()
    -- Server spawns the elevator, client just waits for it
    return spawnedElevator
end

local function ScanForElevators()
    local ent = SpawnElevator()
    if ent then
        AddElevator(ent)
        return 1
    end
    TryAdoptNearbyElevator()
    if not spawnedElevator then
        local now = GetGameTimer()
        if now - syncRequestedAt > 2000 then
            syncRequestedAt = now
            TriggerServerEvent('pf-elevator:requestSync')
        end
    end
    return 0
end

local function EnsureElevatorScanned()
    -- Just scan for existing interior-spawned elevators
    ScanForElevators()
end

local function MoveElevator(entData, toZ, speedMps)
    local ent = entData.ent
    if not DoesEntityExist(ent) then return end
    if not RequestEntityControl(ent) then return end

    entData.moving = true

    local pos = GetEntityCoords(ent)
    local fromZ = pos.z
    if math.abs(toZ - fromZ) < 0.001 then 
        entData.moving = false
        return 
    end

    local dist = math.abs(toZ - fromZ)
    local speed = speedMps > 0.0 and speedMps or SPEED
    local duration = math.max(dist / speed, 0.01)

    FreezeEntityPosition(ent, true)

    local heading = TARGET_HEADING
    local startTime = GetGameTimer()

    while true do
        local elapsed = (GetGameTimer() - startTime) / 1000.0
        local t = clamp(elapsed / duration, 0.0, 1.0)
        local currentZ = fromZ + ((toZ - fromZ) * t)

        SetEntityCoordsNoOffset(ent, pos.x, pos.y, currentZ, false, false, false)
        SetEntityHeading(ent, heading)
        
        -- Maintain visibility during movement (interior fix) - aggressive approach
        SetEntityVisible(ent, true, false)
        SetEntityAlpha(ent, 255, false)
        SetEntityLodDist(ent, 10000)

        if t >= 1.0 then
            break
        end

        Wait(0)
    end

    SetEntityCoordsNoOffset(ent, pos.x, pos.y, toZ, false, false, false)
    SetEntityHeading(ent, heading)
    FreezeEntityPosition(ent, true)
    
    -- Fix visibility issues in interiors - aggressive approach
    SetEntityVisible(ent, true, false)
    SetEntityAlpha(ent, 255, false)
    SetEntityCollision(ent, true, true)
    SetEntityLodDist(ent, 10000)
    SetEntityCompletelyDisableCollision(ent, false, false)

    entData.moving = false
    entData.arrivedAt = toZ
    entData.arrivedTime = GetGameTimer()
    entData.queuedFloor = nil
end

local function RequestFloor(floorIndex)
    if not floorIndex or not FLOORS[floorIndex] then
        Notify("Invalid floor")
        return
    end
    TriggerServerEvent('pf-elevator:requestFloor', floorIndex)
end

local function OpenElevatorMenu(entData)
    local options = {}
    for index, floor in ipairs(FLOORS) do
        table.insert(options, {
            title = floor.label or "Floor",
            description = floor.z and string.format("Z: %.2f", floor.z) or nil,
            onSelect = function()
                RequestFloor(index)
            end
        })
    end

    if lib and lib.registerContext and lib.showContext then
        lib.registerContext({
            id = 'elevator_any_prop_menu',
            title = 'Select Floor',
            options = options
        })
        lib.showContext('elevator_any_prop_menu')
    else
        -- Fallback if ox_lib is not running
        Notify("ox_lib not detected.")
    end
end

-- Elevator state machine: handles queue, dwell time, and prevents interruption
CreateThread(function()
    while true do
        Wait(1000)
        CleanElevators()
    end
end)

-- Spawn elevator at startup
CreateThread(function()
    print("^3[Elevator Client] Waiting for server to spawn elevator...^7")
    headingAdjustment = 0.0

    -- Guaranteed movable client-side fallback for interior reliability
    EnsureLocalFallbackElevator()

    while true do
        if spawnedElevator and DoesEntityExist(spawnedElevator) then
            break
        end
        local now = GetGameTimer()
        if now - syncRequestedAt > 2000 then
            syncRequestedAt = now
            TriggerServerEvent('pf-elevator:requestSync')
        end
        ScanForElevators()
        Wait(2000)
    end
end)

-- Interaction loop for elevator car (menu)
CreateThread(function()
    while true do
        Wait(0)
        local now = GetGameTimer()
        if now - lastScan >= RESCAN_MS then
            lastScan = now
            ScanForElevators()
        end

        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)

        local nearest, ndist, npos = nil, 9999.0, nil
        for ent, _ in pairs(elevators) do
            if DoesEntityExist(ent) then
                local epos = GetEntityCoords(ent)
                local d = #(pcoords - epos)
                if d < ndist then
                    ndist = d
                    nearest = ent
                    npos = epos
                end
            end
        end

        if nearest and ndist <= INTERACT_RANGE then
            DrawText3D(npos + vector3(0.0, 0.0, TEXT_OFFSET_Z), "[E] Request Elevator")
            if IsControlJustPressed(0, INTERACT_KEY) then
                OpenElevatorMenu(elevators[nearest])
            end
        else
            -- optional marker to prove detection at a distance
             if nearest and DoesEntityExist(nearest) then
                 DrawMarker(1, npos.x, npos.y, npos.z - 1.0, 0.0,0.0,0.0, 0.0,0.0,0.0, 0.4,0.4,0.2, 255,255,255,80, false,false,2,false,nil,nil,false)
             end
        end
    end
end)

-- Interaction loop for floor call buttons
CreateThread(function()
    while true do
        Wait(0)
        
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)

        for index, floor in ipairs(FLOORS) do
            if floor.callButton then
                local dist = #(pcoords - floor.callButton)
                
                if dist <= INTERACT_RANGE then
                    DrawText3D(floor.callButton + vector3(0.0, 0.0, 0.5), "[E] Call Elevator")
                    if IsControlJustPressed(0, INTERACT_KEY) then
                        -- Find nearest elevator and request this floor
                        local elevEnt = nil
                        local nearestDist = 9999.0
                        for ent, _ in pairs(elevators) do
                            if DoesEntityExist(ent) then
                                local epos = GetEntityCoords(ent)
                                local d = #(pcoords - epos)
                                if d < nearestDist then
                                    nearestDist = d
                                    elevEnt = ent
                                end
                            end
                        end
                        
                        if elevEnt then
                            RequestFloor(index)
                        else
                            RequestFloor(index)
                            Notify("Request sent")
                        end
                    end
                end
            end
        end
    end
end)

-- Ensure non-current floor doors stay locked
CreateThread(function()
    while true do
        Wait(1000)  -- Check every second
        
        if doorState.currentFloor and doorState.floorDoors then
            -- Lock all floor doors except current floor
            for i, floorDoors in pairs(doorState.floorDoors) do
                if i ~= doorState.currentFloor then
                    if floorDoors.left then
                        SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_left", 1, false, false)  -- Locked
                    end
                    if floorDoors.right then
                        SafeDoorSystemSetDoorState("pf_elevatorfloor_" .. i .. "_right", 1, false, false)  -- Locked
                    end
                end
            end
        end
    end
end)

-- Continuous visibility maintenance for interior entities
CreateThread(function()
    while true do
        Wait(500) -- Check every 500ms
        
        local ent = GetActiveElevatorEntity()
        if ent and DoesEntityExist(ent) then
            -- Maintain visibility properties without constantly refreshing interior
            SetEntityVisible(ent, true, false)
            SetEntityAlpha(ent, 255, false)
            SetEntityLodDist(ent, 10000)
            SetEntityCollision(ent, true, true)
        end
    end
end)

-- Continuous heading lock to prevent any runtime yaw drift
CreateThread(function()
    while true do
        Wait(100)
        local ent = GetActiveElevatorEntity()
        if ent and DoesEntityExist(ent) then
            SetEntityHeading(ent, TARGET_HEADING + headingAdjustment)
        end
    end
end)

-- Hide/suppress duplicate nearby elevator visuals (keeps server-controlled one usable)
CreateThread(function()
    while true do
        Wait(1000)

        local anchor = spawnedElevator and DoesEntityExist(spawnedElevator) and GetEntityCoords(spawnedElevator) or SPAWN_COORDS
        for obj in EnumerateObjects() do
            if DoesEntityExist(obj) and IsTargetElevatorModel(GetEntityModel(obj)) then
                local d = #(GetEntityCoords(obj) - anchor)
                if d < 6.0 and (not spawnedElevator or obj ~= spawnedElevator) then
                    SetEntityVisible(obj, false, false)
                    SetEntityCollision(obj, false, false)
                end
            end
        end
    end
end)

-- Debug command: /elevscan to force a rescan
RegisterCommand('elevscan', function()
    local c = ScanForElevators()
    Notify(("Rescanned. Found %d elevator(s)."):format(c))
    
    local count = 0
    for ent, data in pairs(elevators) do
        count = count + 1
        local pos = GetEntityCoords(ent)
        print(("^2[Elevator %d]^7 Entity: %d | Model: 0x%X | Pos: %.2f, %.2f, %.2f"):format(count, ent, GetEntityModel(ent), pos.x, pos.y, pos.z))
    end
end, false)

-- Add a locate command to show nearest elevator
RegisterCommand('elevnearest', function()
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    
    local nearest, ndist = nil, 9999.0
    for ent, _ in pairs(elevators) do
        if DoesEntityExist(ent) then
            local epos = GetEntityCoords(ent)
            local d = #(pcoords - epos)
            if d < ndist then
                ndist = d
                nearest = ent
            end
        end
    end
    
    if nearest then
        Notify(("Nearest elevator: %.1f meters away"):format(ndist))
        print(("^2Distance to nearest elevator: %.2f m^7"):format(ndist))
    else
        Notify("No elevators detected")
        print("^1No elevators in the elevators table^7")
    end
end, false)

-- Diagnostic: scan all objects/vehicles near player
RegisterCommand('elevdiag', function()
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    
    print("^3=== ELEVATOR DIAGNOSTIC ===^7")
    print(("^2Target Model Hash: 0x%X (%s)^7"):format(TARGET_HASH, MODEL_NAME))
    print(("^2Scanning from player at: %.2f, %.2f, %.2f^7"):format(pcoords.x, pcoords.y, pcoords.z))
    
    local objCount = 0
    print("^3--- Objects Found ---^7")
    for obj in EnumerateObjects() do
        objCount = objCount + 1
        if objCount <= 20 then
            local opos = GetEntityCoords(obj)
            local mdl = GetEntityModel(obj)
            local dist = #(pcoords - opos)
            print(("  Object %d: 0x%X | Pos: %.2f, %.2f, %.2f | Dist: %.1f m"):format(objCount, mdl, opos.x, opos.y, opos.z, dist))
        end
    end
    print(("^2Total objects scanned: %d^7"):format(objCount))
    
    local vehCount = 0
    print("^3--- Vehicles Found ---^7")
    for veh in EnumerateVehicles() do
        vehCount = vehCount + 1
        if vehCount <= 20 then
            local vpos = GetEntityCoords(veh)
            local mdl = GetEntityModel(veh)
            local dist = #(pcoords - vpos)
            print(("  Vehicle %d: 0x%X | Pos: %.2f, %.2f, %.2f | Dist: %.1f m"):format(vehCount, mdl, vpos.x, vpos.y, vpos.z, dist))
        end
    end
    print(("^2Total vehicles scanned: %d^7"):format(vehCount))
end, false)

-- Search entire world for elevator model
RegisterCommand('eleworldscan', function()
    print("^3=== WORLD-WIDE ELEVATOR SEARCH ===^7")
    print(("^2Looking for model: 0x%X (%s)^7"):format(TARGET_HASH, MODEL_NAME))
    
    local foundCount = 0
    
    print("^3--- Searching Objects ---^7")
    for obj in EnumerateObjects() do
        local mdl = GetEntityModel(obj)
        if mdl == TARGET_HASH then
            foundCount = foundCount + 1
            local opos = GetEntityCoords(obj)
            print(("  ^2Object #%d: Pos: %.2f, %.2f, %.2f | Entity ID: %d^7"):format(foundCount, opos.x, opos.y, opos.z, obj))
        end
    end
    
    print("^3--- Searching Vehicles ---^7")
    for veh in EnumerateVehicles() do
        local mdl = GetEntityModel(veh)
        if mdl == TARGET_HASH then
            foundCount = foundCount + 1
            local vpos = GetEntityCoords(veh)
            print(("  ^2Vehicle #%d: Pos: %.2f, %.2f, %.2f | Entity ID: %d^7"):format(foundCount, vpos.x, vpos.y, vpos.z, veh))
        end
    end
    
    if foundCount == 0 then
        print("^1NO ELEVATORS FOUND ANYWHERE IN WORLD^7")
        print("^3The interior may not be loading the elevator entity.^7")
    else
        print(("^2Found %d elevator(s) total^7"):format(foundCount))
    end
end, false)

-- ===== DEBUG TOOLS FOR FLOOR ALIGNMENT =====

local showFloorMarkers = false
local heightAdjustment = 0.0
local nudgeMode = false
local nudgeSpeed = 0.01 -- units per frame (arrow keys)
local fineNudgeSpeed = 0.001 -- units per scroll (fine tuning)

-- Command: Show current player Z coordinate
RegisterCommand('getz', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    print(string.format("^2Your Z coordinate: %.6f^7", coords.z))
    Notify(string.format("Z: %.6f", coords.z))
end, false)

-- Command: Toggle floor markers
RegisterCommand('elevmarkers', function(source, args)
    showFloorMarkers = not showFloorMarkers
    if showFloorMarkers then
        print("^2Floor markers enabled^7")
        Notify("Floor markers enabled")
    else
        print("^3Floor markers disabled^7")
        Notify("Floor markers disabled")
    end
end, false)

-- Command: Toggle nudge mode (arrow key controls)
RegisterCommand('elevnudge', function()
    nudgeMode = not nudgeMode
    if nudgeMode then
        print("^2Nudge mode enabled^7")
        print("^3Arrow Up/Down: Move Z | Arrow Left/Right: Move Y | PgUp/PgDn: Move X^7")
        print("^3Scroll Wheel: Fine-tune Z | K: Print coords^7")
        Notify("Nudge mode ON - Use arrow keys")
    else
        print("^3Nudge mode disabled^7")
        Notify("Nudge mode OFF")
    end
end, false)

-- Command: Adjust elevator height (usage: /elevadjust 0.5 or /elevadjust -0.2)
RegisterCommand('elevadjust', function(source, args)
    if not args[1] then
        print("^3Usage: /elevadjust <offset>^7")
        print(string.format("^3Current adjustment: %.3f^7", heightAdjustment))
        return
    end
    
    local offset = tonumber(args[1])
    if not offset then
        print("^1Invalid number^7")
        return
    end
    
    heightAdjustment = heightAdjustment + offset
    
    -- Apply to spawned elevator if exists
    if spawnedElevator and DoesEntityExist(spawnedElevator) then
        local pos = GetEntityCoords(spawnedElevator)
        SetEntityCoords(spawnedElevator, pos.x, pos.y, pos.z + offset, false, false, false, false)
    end
    
    print(string.format("^2Elevator adjusted by %.3f (total: %.3f)^7", offset, heightAdjustment))
    Notify(string.format("Height adjustment: %.3f", heightAdjustment))
end, false)

-- Command: Reset elevator to config position
RegisterCommand('elevreset', function()
    heightAdjustment = 0.0
    headingAdjustment = 0.0
    if spawnedElevator and DoesEntityExist(spawnedElevator) then
        SetEntityCoords(spawnedElevator, SPAWN_COORDS.x, SPAWN_COORDS.y, SPAWN_COORDS.z, false, false, false, false)
        SetEntityHeading(spawnedElevator, TARGET_HEADING + headingAdjustment)
        print("^2Elevator reset to config position^7")
        Notify("Elevator reset")
    end
end, false)

-- Command: Adjust heading live (usage: /elevrot 5 or /elevrot -10)
RegisterCommand('elevrot', function(source, args)
    if not args[1] then
        local currentHeading = TARGET_HEADING + headingAdjustment
        print(string.format("^3Usage: /elevrot <degrees> | current heading: %.2f^7", currentHeading))
        return
    end

    local delta = tonumber(args[1])
    if not delta then
        print("^1Invalid degrees value^7")
        return
    end

    headingAdjustment = headingAdjustment + delta
    local currentHeading = TARGET_HEADING + headingAdjustment

    if spawnedElevator and DoesEntityExist(spawnedElevator) then
        SetEntityHeading(spawnedElevator, currentHeading)
    end

    print(string.format("^2[Elevator] Heading now: %.2f (base %.2f + adj %.2f)^7", currentHeading, TARGET_HEADING, headingAdjustment))
    print(string.format("^5Config target: spawnPos = vector4(%.6f, %.6f, %.6f, %.2f)^7", SPAWN_COORDS.x, SPAWN_COORDS.y, SPAWN_COORDS.z, currentHeading))
    Notify(string.format("Heading: %.2f", currentHeading))
end, false)

-- Nudge mode controls
CreateThread(function()
    while true do
        Wait(0)
        
        if nudgeMode and spawnedElevator and DoesEntityExist(spawnedElevator) then
            local pos = GetEntityCoords(spawnedElevator)
            local moved = false
            local newX, newY, newZ = pos.x, pos.y, pos.z
            
            -- Arrow Up/Down - Z axis
            if IsControlPressed(0, 172) then -- Arrow Up
                newZ = newZ + nudgeSpeed
                moved = true
            end
            if IsControlPressed(0, 173) then -- Arrow Down
                newZ = newZ - nudgeSpeed
                moved = true
            end
            
            -- Arrow Left/Right - Y axis
            if IsControlPressed(0, 174) then -- Arrow Left
                newY = newY - nudgeSpeed
                moved = true
            end
            if IsControlPressed(0, 175) then -- Arrow Right
                newY = newY + nudgeSpeed
                moved = true
            end
            
            -- Page Up/Down - X axis
            if IsControlPressed(0, 10) then -- Page Up (might need to check key code)
                newX = newX + nudgeSpeed
                moved = true
            end
            if IsControlPressed(0, 11) then -- Page Down
                newX = newX - nudgeSpeed
                moved = true
            end
            
            -- Scroll Wheel - Fine-tune Z axis
            if IsControlJustPressed(0, 241) then -- Scroll Up
                newZ = newZ + fineNudgeSpeed
                moved = true
            end
            if IsControlJustPressed(0, 242) then -- Scroll Down
                newZ = newZ - fineNudgeSpeed
                moved = true
            end
            
            -- K key - Print coordinates
            if IsControlJustPressed(0, 311) then -- K key
                print(string.format("^2=== Elevator Position ===^7"))
                print(string.format("^3X: %.6f^7", pos.x))
                print(string.format("^3Y: %.6f^7", pos.y))
                print(string.format("^3Z: %.6f^7", pos.z))
                print(string.format("^3Heading: %.2f^7", GetEntityHeading(spawnedElevator)))
                print(string.format("^2vector4(%.6f, %.6f, %.6f, %.2f)^7", pos.x, pos.y, pos.z, GetEntityHeading(spawnedElevator)))
                
                -- Copy to clipboard friendly format
                local clipFormat = string.format("spawnPos = vector4(%.6f, %.6f, %.6f, %.2f)", pos.x, pos.y, pos.z, GetEntityHeading(spawnedElevator))
                print("^5Copy this to config:^7")
                print(clipFormat)
                Notify("Coords printed to F8")
            end
            
            if moved then
                SetEntityCoords(spawnedElevator, newX, newY, newZ, false, false, false, false)
            end
            
            -- Display HUD
            DrawText3D(pos + vector3(0, 0, 2.5), string.format("~g~NUDGE MODE~w~\nZ: %.3f | X: %.3f | Y: %.3f\nPress ~y~K~w~ for coords", newZ, newX, newY))
        else
            Wait(500)
        end
    end
end)

-- Draw floor markers
CreateThread(function()
    while true do
        Wait(0)
        
        if showFloorMarkers then
            for i, floor in ipairs(FLOORS) do
                local x, y = SPAWN_COORDS.x, SPAWN_COORDS.y
                local z = floor.z + heightAdjustment
                
                -- Draw a cylinder marker at floor level
                DrawMarker(
                    1, -- Cylinder
                    x, y, z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    2.0, 2.0, 0.1,
                    0, 255, 0, 150,
                    false, false, 2, false, nil, nil, false
                )
                
                -- Draw 3D text with floor label
                DrawText3D(vector3(x, y, z + 0.5), string.format("%s (Z: %.2f)", floor.label, z))
            end
        end
    end
end)
-- Door adjustment command
RegisterCommand('adjustdoor', function(source, args, rawCommand)
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    
    -- Find nearest door
    local nearestDoor = nil
    local nearestDist = 9999.0
    local doorType = nil
    local floorIndex = nil

    -- Check elevator doors
    if doorState.elevatorLeftDoor and DoesEntityExist(doorState.elevatorLeftDoor) then
        local d = #(pcoords - GetEntityCoords(doorState.elevatorLeftDoor))
        if d < nearestDist then
            nearestDist = d
            nearestDoor = doorState.elevatorLeftDoor
            doorType = "elevator-left"
        end
    end

    if doorState.elevatorRightDoor and DoesEntityExist(doorState.elevatorRightDoor) then
        local d = #(pcoords - GetEntityCoords(doorState.elevatorRightDoor))
        if d < nearestDist then
            nearestDist = d
            nearestDoor = doorState.elevatorRightDoor
            doorType = "elevator-right"
        end
    end

    -- Check floor doors
    for i, doors in pairs(doorState.floorDoors) do
        if doors.left and DoesEntityExist(doors.left) then
            local d = #(pcoords - GetEntityCoords(doors.left))
            if d < nearestDist then
                nearestDist = d
                nearestDoor = doors.left
                doorType = "floor-left"
                floorIndex = i
            end
        end
        if doors.right and DoesEntityExist(doors.right) then
            local d = #(pcoords - GetEntityCoords(doors.right))
            if d < nearestDist then
                nearestDist = d
                nearestDoor = doors.right
                doorType = "floor-right"
                floorIndex = i
            end
        end
    end

    if not nearestDoor or nearestDist > 2.0 then
        Notify("No doors nearby")
        return
    end

    -- Highlight the door
    CreateThread(function()
        for i = 0, 30 do  -- 30 frames at 60fps = 0.5 seconds
            SetEntityDrawOutline(nearestDoor, true)
            if i % 2 == 0 then
                SetEntityOutlineColor(255, 0, 0, 255)
            else
                SetEntityOutlineColor(0, 255, 0, 255)
            end
            Wait(0)
        end
        SetEntityDrawOutline(nearestDoor, false)
    end)

    local adjustMode = true
    local startPos = GetEntityCoords(nearestDoor)
    local function UpdateDoorPosition()
        if not adjustMode then return end
        
        local pos = GetEntityCoords(nearestDoor)
        local moved = false
        local nudgeSpeed = 0.01
        local fineNudgeSpeed = 0.001

        -- Arrow keys for X/Y
        if IsControlJustPressed(0, 34) then -- LEFT
            pos = pos - vector3(nudgeSpeed, 0, 0)
            moved = true
        end
        if IsControlJustPressed(0, 35) then -- RIGHT
            pos = pos + vector3(nudgeSpeed, 0, 0)
            moved = true
        end
        if IsControlJustPressed(0, 27) then -- UP
            pos = pos + vector3(0, nudgeSpeed, 0)
            moved = true
        end
        if IsControlJustPressed(0, 33) then -- DOWN
            pos = pos - vector3(0, nudgeSpeed, 0)
            moved = true
        end

        -- Scroll wheel for Z
        if IsControlJustPressed(0, 241) then -- Scroll Up
            pos = pos + vector3(0, 0, fineNudgeSpeed)
            moved = true
        end
        if IsControlJustPressed(0, 242) then -- Scroll Down
            pos = pos - vector3(0, 0, fineNudgeSpeed)
            moved = true
        end

        if moved then
            SetEntityCoords(nearestDoor, pos.x, pos.y, pos.z, false, false, false, false)
        end

        -- R to reset, ENTER to confirm
        if IsControlJustPressed(0, 38) then -- R key
            SetEntityCoords(nearestDoor, startPos.x, startPos.y, startPos.z, false, false, false, false)
            Notify("Door reset")
        end

        if IsControlJustPressed(0, 18) then -- ENTER
            local finalPos = GetEntityCoords(nearestDoor)
            print(string.format("^2[Door] Final position: vector3(%.6f, %.6f, %.6f)^7", finalPos.x, finalPos.y, finalPos.z))
            adjustMode = false
            Notify("Door adjustment saved")
        end

        DrawText3D(pos + vector3(0, 0, 0.5), string.format("~g~ADJUSTING %s~w~\nArrows: Move | Scroll: Z-Axis\n~y~R~w~: Reset | ~y~ENTER~w~: Confirm", string.upper(doorType)))
    end

    CreateThread(function()
        while adjustMode do
            Wait(0)
            UpdateDoorPosition()
        end
    end)

    Notify(string.format("Adjusting ~ %s ~ (Dist: %.1fm)", doorType, nearestDist))
end, false)

-- Initialize doors after elevator spawns
CreateThread(function()
    Wait(2000)
    print("^3[Doors] Initialization thread started, checking for elevator^7")
    if spawnedElevator then
        if DoesEntityExist(spawnedElevator) then
            print(string.format("^2[Doors] Elevator found (entity %d), spawning doors...^7", spawnedElevator))
            SpawnElevatorDoors()
            SpawnFloorDoors()
            HookMovementEvents()
        else
            print("^1[Doors] Elevator entity does not exist^7")
        end
    else
        print("^1[Doors] spawnedElevator is nil^7")
    end
end)