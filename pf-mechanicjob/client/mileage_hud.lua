local QBCore = exports['pfm-core']:GetCoreObject()

-- State
local mileageHudEnabled = true -- Can be toggled by player
local lastPosition = nil
local currentMileage = 0
local currentVehicle = 0

-- Helper: Get mileage from vehicle state
local function getVehicleMileage(veh)
    if not veh or not DoesEntityExist(veh) then return 0 end
    local state = Entity(veh).state
    return tonumber(state.mileage) or 0
end

-- Helper: Update mileage in vehicle state
local function updateVehicleMileage(veh, miles)
    if not veh or not DoesEntityExist(veh) then return end
    local state = Entity(veh).state
    local current = tonumber(state.mileage) or 0
    state:set('mileage', current + miles, true)
end

-- Helper: Send mileage to NUI
local function updateMileageUI(visible, mileage)
    SendNUIMessage({
        action = 'updateMileage',
        visible = visible,
        mileage = mileage or 0,
        unit = 'MI' -- Can be changed to KM if needed
    })
    
    if Config.Debug then
        print(string.format('[MILEAGE HUD] Sent NUI: visible=%s mileage=%.1f', tostring(visible), mileage or 0))
    end
end

-- Main mileage tracking thread
CreateThread(function()
    Wait(2000) -- Wait for game to fully load
    
    if Config.Debug then
        print('[MILEAGE HUD] System started')
    end
    
    while true do
        Wait(1000) -- Update every second
        
        local ped = PlayerPedId()
        
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            
            if veh ~= 0 and DoesEntityExist(veh) then
                -- Check if player is driver
                if GetPedInVehicleSeat(veh, -1) == ped then
                    -- New vehicle entered
                    if veh ~= currentVehicle then
                        currentVehicle = veh
                        currentMileage = getVehicleMileage(veh)
                        lastPosition = GetEntityCoords(veh)
                        
                        if mileageHudEnabled then
                            updateMileageUI(true, currentMileage)
                        end
                        
                        if Config.Debug then
                            print(string.format('[MILEAGE HUD] Entered vehicle, current mileage: %.1f', currentMileage))
                        end
                    end
                    
                    -- Calculate distance traveled
                    local currentPosition = GetEntityCoords(veh)
                    
                    if lastPosition then
                        local distance = #(currentPosition - lastPosition)
                        
                        -- Only count if vehicle moved (prevents stationary accumulation)
                        if distance > 0.5 then -- Minimum 0.5m movement
                            -- Convert meters to miles (1 mile = 1609.34 meters)
                            local miles = distance / 1609.34
                            
                            currentMileage = currentMileage + miles
                            updateVehicleMileage(veh, miles)
                            
                            -- Update UI
                            if mileageHudEnabled then
                                updateMileageUI(true, currentMileage)
                            end
                        end
                    end
                    
                    lastPosition = currentPosition
                else
                    -- Not driver anymore
                    if currentVehicle ~= 0 then
                        updateMileageUI(false)
                        currentVehicle = 0
                        lastPosition = nil
                    end
                end
            end
        else
            -- Not in vehicle
            if currentVehicle ~= 0 then
                updateMileageUI(false)
                currentVehicle = 0
                lastPosition = nil
                
                if Config.Debug then
                    print('[MILEAGE HUD] Exited vehicle')
                end
            end
        end
    end
end)

-- Test command (debug)
if Config.Debug then
    RegisterCommand('testmileage', function()
        print('[MILEAGE HUD] Testing UI...')
        updateMileageUI(true, 12345)
        Wait(5000)
        updateMileageUI(false)
    end, false)
    
    RegisterCommand('showmileage', function()
        print('[MILEAGE HUD] Forcing show...')
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            local mileage = getVehicleMileage(veh)
            updateMileageUI(true, mileage)
        else
            updateMileageUI(true, 0)
        end
    end, false)
end

-- Commands to toggle HUD (optional)
RegisterCommand('mileagehud', function()
    mileageHudEnabled = not mileageHudEnabled
    
    if mileageHudEnabled then
        QBCore.Functions.Notify('Mileage HUD enabled', 'success')
        
        -- Re-show if in vehicle
        if currentVehicle ~= 0 then
            updateMileageUI(true, currentMileage)
        end
    else
        QBCore.Functions.Notify('Mileage HUD disabled', 'primary')
        updateMileageUI(false)
    end
end, false)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    SendNUIMessage({ action = 'hideMileage' })
end)
