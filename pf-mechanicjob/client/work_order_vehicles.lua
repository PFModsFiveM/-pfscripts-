-- client/work_order_vehicles.lua
-- Handles vehicle spawning, tracking, and objective markers for work orders

local QBCore = exports['pfm-core']:GetCoreObject()

-- Active work order vehicle data
local ActiveWorkOrderVehicle = nil

local function sendTabletMessage(payload)
    if GetResourceState('pf-tablet') ~= 'started' then return false end
    if not exports or not exports['pf-tablet'] or not exports['pf-tablet'].SendNuiMessage then return false end
    PFMechShell({
        action = 'externalAppMessage',
        resource = 'pf-mechanicjob',
        app = 'mechanic',
        payload = payload
    })
    return true
end
local VehicleBlip = nil
local VehicleObjective = nil

-- Helper: Clean up any attached props from player
local function cleanupPlayerProps()
    local ped = PlayerPedId()
    
    -- Clear any animations
    ClearPedTasks(ped)
    
    -- Delete any attached props (welder, tablet, clipboard, etc.)
    local propHashes = {
        GetHashKey('prop_weld_torch'),
        GetHashKey('prop_cs_tablet'),
        GetHashKey('p_amb_clipboard_01'),
        GetHashKey('prop_notepad_01'),
        GetHashKey('prop_phone_proto'),
    }
    
    for _, propHash in ipairs(propHashes) do
        local prop = GetClosestObjectOfType(GetEntityCoords(ped), 2.0, propHash, false, false, false)
        if prop ~= 0 and DoesEntityExist(prop) then
            DeleteObject(prop)
            DeleteEntity(prop)
        end
    end
    
    -- Also clean up any props attached to player bones
    if IsEntityAttachedToEntity(ped, ped) then
        DetachEntity(ped, true, true)
    end
end

-- Apply the work-order repair effect so the vehicle is visibly fixed. Part wear is not reset here:
-- partDamage is server-set (sv_stateBagStrictMode) and the server removes the car when the order
-- completes.
local function applyRepairCompletionEffect(repairType)
    if not ActiveWorkOrderVehicle then return end
    local veh = ActiveWorkOrderVehicle.vehicle
    if not veh or not DoesEntityExist(veh) then return end

    if repairType == 'tire' then
        -- Fix all wheels that might have been burst for the job
        for i = 0, 7 do
            if IsVehicleTyreBurst(veh, i, false) or IsVehicleTyreBurst(veh, i, true) or IsWheelDamaged(veh, i) then
                SetVehicleTyreFixed(veh, i)
            end
        end
    elseif repairType == 'battery' then
        -- Restore engine/tank health to a healthy state
        SetVehicleEngineHealth(veh, 900.0)
        SetVehiclePetrolTankHealth(veh, 1000.0)
    elseif repairType == 'oil' then
        -- Top-off oil and improve engine condition
        SetVehicleEngineHealth(veh, 850.0)
        SetVehicleOilLevel(veh, 1.0)
    elseif repairType == 'brakes' then
        -- Restore brakes (via state bag)
    elseif repairType == 'sparkplugs' then
        -- Restore spark plugs
        SetVehicleEngineHealth(veh, 900.0)
    elseif repairType == 'coolant' then
        -- Restore coolant
    elseif repairType == 'transmission' then
        -- Restore transmission
    elseif repairType == 'engine' then
        -- General engine repair
        SetVehicleEngineHealth(veh, 950.0)
    elseif repairType == 'suspension' then
        -- Restore suspension
    elseif repairType == 'body' then
        -- Body repair
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleDeformationFixed(veh)
    elseif repairType == 'turbo' then
        -- Install turbo
        ToggleVehicleMod(veh, 18, true)
    elseif repairType == 'diagnostics' then
        -- Full diagnostic - restore everything
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehiclePetrolTankHealth(veh, 1000.0)
        SetVehicleFixed(veh)
    end
end

-- ============================================================================
-- HELPER FUNCTIONS (Defined first so they can be called by main functions)
-- ============================================================================

-- Apply damage to vehicle based on job type
local function applyJobDamage(vehicle, orderData)
    if not DoesEntityExist(vehicle) then return end

    local function setPartDamage(updates)
        local state = Entity(vehicle).state
        local current = state.partDamage or {}
        local merged = {}

        for key, value in pairs(current) do
            merged[key] = value
        end
        for key, value in pairs(updates or {}) do
            merged[key] = value
        end

        -- the server only adds wear through this report (sv_stateBagStrictMode)
        TriggerServerEvent('pf_mech:server:setState', NetworkGetNetworkIdFromEntity(vehicle), 'partDamage', merged)
    end
    
    local repairType = orderData.repairType
    
    if repairType == 'tire' then
        -- Burst random tires
        local tiresToBurst = math.random(1, 2)
        for i = 1, tiresToBurst do
            local tire = math.random(0, 7)
            SetVehicleTyreBurst(vehicle, tire, true, 1000.0)
        end
        
    elseif repairType == 'battery' then
        SetVehicleEngineHealth(vehicle, 300.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        setPartDamage({ carbattery = math.random(55, 80) })
        
    elseif repairType == 'oil' then
        SetVehicleEngineHealth(vehicle, 500.0)
        SetVehicleOilLevel(vehicle, 0.2)
        setPartDamage({ oil = math.random(45, 75) })
        
    elseif repairType == 'brakes' then
        setPartDamage({ brakes = math.random(40, 70) })
        
    elseif repairType == 'sparkplugs' then
        setPartDamage({ sparkplugs = math.random(50, 80) })
        SetVehicleEngineHealth(vehicle, math.random(400, 600))
        
    elseif repairType == 'coolant' then
        setPartDamage({ coolant = math.random(40, 70) })
        
    elseif repairType == 'transmission' then
        setPartDamage({ transmissionfluid = math.random(45, 75) })
        
    elseif repairType == 'engine' then
        SetVehicleEngineHealth(vehicle, math.random(300, 500))
        setPartDamage({ engine_part = math.random(40, 70) })
        
    elseif repairType == 'suspension' then
        setPartDamage({ suspension = math.random(50, 80) })
        
    elseif repairType == 'body' then
        SetVehicleBodyHealth(vehicle, math.random(400, 600))
        SmashVehicleWindow(vehicle, math.random(0, 3))
        setPartDamage({ body_part = math.random(40, 70) })
        
    elseif repairType == 'turbo' then
        -- Remove turbo if installed
        ToggleVehicleMod(vehicle, 18, false)
        
    elseif repairType == 'diagnostics' then
        SetVehicleEngineHealth(vehicle, math.random(500, 700))
        setPartDamage({
            engine_part = math.random(20, 40),
            brakes = math.random(20, 40),
            suspension = math.random(20, 40),
            carbattery = math.random(20, 45)
        }, true)
    end
    
    if Config.Debug then
        print(string.format('[Work Orders] Applied %s damage to vehicle', repairType))
    end
end

-- Create blip for work order vehicle
local function createVehicleBlip(vehicle, orderData)
    if VehicleBlip then
        RemoveBlip(VehicleBlip)
    end
    
    if Config.Debug then
        print('[Work Orders] Creating blip for vehicle: ' .. tostring(vehicle))
        print('[Work Orders] Vehicle exists: ' .. tostring(DoesEntityExist(vehicle)))
        print('[Work Orders] Blip sprite: ' .. Config.WorkOrderSystem.blipSprite)
        print('[Work Orders] Blip color: ' .. Config.WorkOrderSystem.blipColor)
    end
    
    VehicleBlip = AddBlipForEntity(vehicle)
    if VehicleBlip == 0 then
        if Config.Debug then
            print('[Work Orders] Failed to create blip (returned 0)')
        end
        return
    end
    
    SetBlipSprite(VehicleBlip, Config.WorkOrderSystem.blipSprite)
    SetBlipColour(VehicleBlip, Config.WorkOrderSystem.blipColor)
    SetBlipScale(VehicleBlip, Config.WorkOrderSystem.blipScale)
    SetBlipAsShortRange(VehicleBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Work Order: ' .. orderData.title)
    EndTextCommandSetBlipName(VehicleBlip)
    
    if Config.Debug then
        print('[Work Orders] Blip created successfully: ' .. tostring(VehicleBlip))
    end
end

-- ============================================================================
-- VEHICLE SPAWNING
-- ============================================================================

-- Spawn a vehicle for a work order
local function spawnWorkOrderVehicle(orderData)
    if ActiveWorkOrderVehicle then
        if Config.Debug then
            print('[Work Orders] Vehicle already spawned for active order')
        end
        return
    end
    
    -- Get random spawn location from available locations
    local locations = Config.WorkOrderSystem.vehicleSpawnLocations
    if not locations or #locations == 0 then
        QBCore.Functions.Notify('No spawn location available', 'error')
        return
    end
    local spawnLoc = locations[math.random(1, #locations)]
    
    -- Use a reliable vehicle model (fallback if orderData.vehicle doesn't exist)
    local vehicleModel = orderData.vehicle or 'oracle'
    local coords = vector3(spawnLoc.x, spawnLoc.y, spawnLoc.z)
    local heading = spawnLoc.w
    
    if Config.Debug then
        print('[Work Orders] Attempting to spawn vehicle: ' .. vehicleModel)
    end
    
    -- Load model with longer timeout
    local modelHash = GetHashKey(vehicleModel)
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 10000 do
        Wait(50)
        timeout = timeout + 50
    end
    
    if not HasModelLoaded(modelHash) then
        if Config.Debug then
            print('[Work Orders] Failed to load model: ' .. vehicleModel .. ' (hash: ' .. modelHash .. ')')
        end
        -- Try fallback vehicle
        vehicleModel = 'oracle'
        modelHash = GetHashKey(vehicleModel)
        RequestModel(modelHash)
        timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 10000 do
            Wait(50)
            timeout = timeout + 50
        end
        
        if not HasModelLoaded(modelHash) then
            QBCore.Functions.Notify('Failed to load vehicle model', 'error')
            return
        end
    end
    
    if Config.Debug then
        print('[Work Orders] Model loaded successfully: ' .. vehicleModel)
    end
    
    -- Spawn vehicle
    local vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, heading, true, false)
    SetModelAsNoLongerNeeded(modelHash)
    
    if Config.Debug then
        print('[Work Orders] Vehicle entity handle: ' .. tostring(vehicle))
        Wait(100) -- Wait a bit for entity to fully initialize
        print('[Work Orders] Vehicle exists after creation: ' .. tostring(DoesEntityExist(vehicle)))
        print('[Work Orders] Vehicle coords: ' .. tostring(GetEntityCoords(vehicle)))
    end
    
    if not DoesEntityExist(vehicle) then
        if Config.Debug then
            print('[Work Orders] Failed to create vehicle entity')
        end
        QBCore.Functions.Notify('Failed to spawn vehicle', 'error')
        return
    end
    
    -- Configure vehicle
    SetVehicleOnGroundProperly(vehicle)
    SmashVehicleWindow(vehicle, 0)
    SmashVehicleWindow(vehicle, 1)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    
    -- Apply vehicle settings from config
    if Config.WorkOrderSystem.vehicleGodMode then
        SetEntityInvincible(vehicle, true)
    end
    
    if Config.WorkOrderSystem.lockVehicle then
        SetVehicleDoorsLocked(vehicle, 2) -- Locked
    end
    
    -- Set vehicle damage based on job type
    applyJobDamage(vehicle, orderData)
    
    -- Store vehicle data
    ActiveWorkOrderVehicle = {
        vehicle = vehicle,
        orderId = orderData.id,
        coords = coords,
        taskType = orderData.taskType,
        repairType = orderData.repairType,
        requiredItem = orderData.requiredItem,
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    }
    
    -- Create blip
    createVehicleBlip(vehicle, orderData)
    
    -- Set waypoint
    if Config.WorkOrderSystem.waypointEnabled then
        SetNewWaypoint(coords.x, coords.y)
    end
    
    if Config.Debug then
        print(string.format('[Work Orders] Spawned vehicle %s at %s for order #%d', 
            vehicleModel, coords, orderData.id))
    end
    
    QBCore.Functions.Notify('Vehicle location marked on GPS', 'success')
end

-- ============================================================================
-- VEHICLE CLEANUP
-- ============================================================================

-- Delete work order vehicle
local function deleteWorkOrderVehicle()
    if ActiveWorkOrderVehicle then
        local vehicle = ActiveWorkOrderVehicle.vehicle

        if DoesEntityExist(vehicle) then
            if Config.Debug then
                print('[DEBUG] deleteWorkOrderVehicle: entity exists, requesting control')
            end
            -- Ensure we own the entity before deleting (prevents stuck vehicles)
            local attempts = 0
            while not NetworkHasControlOfEntity(vehicle) and attempts < 20 do
                NetworkRequestControlOfEntity(vehicle)
                Wait(50)
                attempts = attempts + 1
            end

            if Config.Debug then
                print('[DEBUG] deleteWorkOrderVehicle: has control?', NetworkHasControlOfEntity(vehicle), 'attempts:', attempts)
            end

            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteVehicle(vehicle)

            -- Fallback delete if the network delete fails
            if DoesEntityExist(vehicle) then
                if Config.Debug then
                    print('[DEBUG] deleteWorkOrderVehicle: DeleteVehicle failed, trying DeleteEntity')
                end
                DeleteEntity(vehicle)
            end
        end

        ActiveWorkOrderVehicle = nil

        if Config.Debug then
            print('[Work Orders] Deleted work order vehicle')
        end
    end

    -- Remove blip even if ActiveWorkOrderVehicle is already nil
    if VehicleBlip then
        RemoveBlip(VehicleBlip)
        VehicleBlip = nil
    end
end

-- ============================================================================
-- JOB COMPLETION CHECK
-- ============================================================================

-- Check if player is near the work order vehicle
local function isNearWorkOrderVehicle()
    if not ActiveWorkOrderVehicle then return false end
    
    local vehicle = ActiveWorkOrderVehicle.vehicle
    if not DoesEntityExist(vehicle) then
        return false
    end
    
    local playerCoords = GetEntityCoords(PlayerPedId())
    local vehicleCoords = GetEntityCoords(vehicle)
    local distance = #(playerCoords - vehicleCoords)
    
    return distance < 5.0 -- Within 5 meters
end

-- Check if player has required item for the job
local function hasRequiredItem(itemName)
    return QBCore.Functions.HasItem(itemName)
end

-- Thread to monitor vehicle and show interaction prompt
CreateThread(function()
    while true do
        Wait(0)
        
        if ActiveWorkOrderVehicle then
            local vehicle = ActiveWorkOrderVehicle.vehicle
            
            -- Check if vehicle still exists
            if not DoesEntityExist(vehicle) then
                if Config.Debug then
                    print('[Work Orders] Work order vehicle was deleted unexpectedly')
                end
                deleteWorkOrderVehicle()
            else
                -- If diagnostics flow is enabled, skip 3D prompt and let tools menu handle it
                if not Config.WorkOrderSystem.useDiagnosticsForWorkOrders then
                    -- Check if player is near vehicle
                    if isNearWorkOrderVehicle() then
                        -- Show interaction prompt
                        local taskType = ActiveWorkOrderVehicle.taskType
                        DrawText3D(GetEntityCoords(vehicle), string.format('[E] Complete %s', taskType))
                        
                        -- Check for interaction key
                        if IsControlJustPressed(0, 38) then -- E key
                            -- Trigger repair attempt
                            TriggerEvent('pf_mech:workorder:attemptRepair')
                        end
                    else
                        Wait(500) -- Reduce load when not near
                    end
                else
                    -- Diagnostics-driven flow: no prompt, check less frequently to save resources
                    Wait(500)
                end
            end
        else
            Wait(1000) -- No active vehicle, check less frequently
        end
    end
end)

-- ============================================================================
-- REPAIR HANDLING
-- ============================================================================

-- Attempt to repair the work order vehicle
RegisterNetEvent('pf_mech:workorder:attemptRepair', function()
    if not ActiveWorkOrderVehicle then
        QBCore.Functions.Notify('No active work order vehicle', 'error')
        return
    end
    
    -- Clean up any existing animations/props from diagnostics menu (notepad, clipboard, etc.)
    cleanupPlayerProps()
    
    -- Check if player has required item
    local requiredItem = nil
    local orderData = ActiveWorkOrderVehicle

    print('[DEBUG] pf_mech:workorder:attemptRepair triggered for orderId:', orderData.orderId)
    
    -- Get required item from server
    QBCore.Functions.TriggerCallback('pf_mech:workorders:getOrderData', function(data)
        if not data then
            QBCore.Functions.Notify('Failed to get order data', 'error')
            return
        end
        
        requiredItem = data.requiredItem
        
        if Config.WorkOrderSystem.requiredItems and requiredItem and not hasRequiredItem(requiredItem) then
            QBCore.Functions.Notify(string.format('You need a %s to complete this job', requiredItem), 'error')
            return
        end
        
        -- Get localized repair text
        local repairText = L('work_order_' .. data.taskType) or ('Performing ' .. data.title)
        
        -- Start welding animation
        local ped = PlayerPedId()
        RequestAnimDict('amb@world_human_welding@male@base')
        while not HasAnimDictLoaded('amb@world_human_welding@male@base') do
            Wait(10)
        end
        TaskPlayAnim(ped, 'amb@world_human_welding@male@base', 'base', 8.0, -8.0, -1, 1, 0, false, false, false)
        
        -- Start repair progress bar
        QBCore.Functions.Progressbar('work_order_repair', repairText, data.duration * 1000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function() -- Success
            -- Clean up animation and props
            cleanupPlayerProps()
            
            -- Repair completed: apply the visual/mechanical fix, then notify server
            print('[DEBUG] Repair progressbar success, calling applyRepairCompletionEffect and server completion')
            applyRepairCompletionEffect(orderData.repairType or data.repairType)
            TriggerServerEvent('pf_mech:workorders:completeRepair', orderData.orderId, requiredItem)
        end, function() -- Cancel
            -- Clean up animation and props
            cleanupPlayerProps()
            QBCore.Functions.Notify('Repair cancelled', 'error')
        end)
        
    end, orderData.orderId)
end)

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Spawn vehicle when order is accepted
RegisterNetEvent('pf_mech:workorder:spawnVehicle', function(orderData)
    spawnWorkOrderVehicle(orderData)
    
    -- Notify tablet to refresh work orders after vehicle spawns
    Wait(500) -- Small delay to ensure server state is updated
    sendTabletMessage({ action = 'refreshWorkOrders' })
end)

-- Delete vehicle when order is completed/cancelled
RegisterNetEvent('pf_mech:workorder:removeVehicle', function()
    if Config.Debug then
        print('[DEBUG] pf_mech:workorder:removeVehicle event received, attempting deleteWorkOrderVehicle()')
    end
    deleteWorkOrderVehicle()

    -- Optimistic UI cleanup: tell tablet to refresh accepted/available lists
    sendTabletMessage({ action = 'refreshWorkOrders' })
end)

-- Export active work order vehicle info for other client scripts (e.g., diagnostics menu)
function GetActiveWorkOrder()
    return ActiveWorkOrderVehicle
end
exports('GetActiveWorkOrder', GetActiveWorkOrder)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        deleteWorkOrderVehicle()
    end
end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

-- Test vehicle spawn for debugging
RegisterNetEvent('pf-mechanicjob:client:spawnTestVehicle', function(modelName)
    if Config.Debug then
        print('[Work Orders Test] Spawning test vehicle: ' .. modelName)
    end
    
    spawnWorkOrderVehicle({
        id = 999,
        title = 'Test Vehicle - ' .. modelName,
        vehicle = modelName,
        repairType = 'tire',
        requiredItem = 'tire'
    })
end)

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Draw 3D text
function DrawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z + 1.0)
    local camCoords = GetGameplayCamCoords()
    local distance = #(coords - camCoords)
    
    if onScreen then
        local scale = (1 / distance) * 2
        local fov = (1 / GetGameplayCamFov()) * 100
        scale = scale * fov
        
        SetTextScale(0.0 * scale, 0.55 * scale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry('STRING')
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(x, y)
    end
end
