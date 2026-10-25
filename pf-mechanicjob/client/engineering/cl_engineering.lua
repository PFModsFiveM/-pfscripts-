-- ============================================================================
-- PF MECHANIC JOB - ADVANCED ENGINEERING (Client Main)
-- ============================================================================

local EngineConfig = require('config.engineering')
local QBCore = exports['pfm-core']:GetCoreObject()
local Physics = require('client.engineering.cl_physics')
local Effects = require('client.engineering.cl_effects')

-- ============================================================================
-- State Management
-- ============================================================================

local Engineering = {
    Enabled = EngineConfig.Enabled,
    CurrentPlate = nil,
    CurrentTuning = nil,
    Active = false,
    LastSyncTime = 0
}

-- ============================================================================
-- Initialization
-- ============================================================================

---Initialize client engineering system
function Engineering:Init()
    if not self.Enabled then return end
    
    if Config.Debug then
        print('[Engineering Client] Initializing...')
    end
    
    -- Set up event listeners
    self:SetupEvents()
    
    -- Start main loop
    self:StartMainLoop()
end

---Set up network events
function Engineering:SetupEvents()
    -- Receive tuning data from server
    RegisterNetEvent('engineering:syncTuning', function(tuning)
        if Config.Debug then
            print('[Engineering Client] Received tuning sync')
        end
        Engineering.CurrentTuning = tuning
    end)
    
    -- Receive wear/heat sync from server
    RegisterNetEvent('engineering:syncWearHeat', function(engineWear, turboWear, engineHeat, turboHeat)
        if Physics.RuntimeState then
            Physics.RuntimeState.engineWear = engineWear or 0
            Physics.RuntimeState.turboWear = turboWear or 0
            Physics.RuntimeState.engineHeat = engineHeat or 0
            Physics.RuntimeState.turboHeat = turboHeat or 0
        end
    end)
    
    -- Handle vehicle enter
    RegisterNetEvent('QBCore:Client:vehicleEnteredAsPilot', function(plate)
        Engineering:OnVehicleEnter(plate)
    end)
end

---Called when player enters a vehicle
---@param plate string Vehicle plate
function Engineering:OnVehicleEnter(plate)
    if not self.Enabled then return end
    
    local playerPed = PlayerPedId()
    if not IsPedInAnyVehicle(playerPed, false) then return end
    
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    
    if GetPedInVehicleSeat(vehicle, -1) ~= playerPed then return end  -- Not driver
    
    self.CurrentPlate = plate
    
    -- Request tuning from server
    TriggerServerEvent('engineering:requestTuning', plate)
    
    self.Active = true
    
    if Config.Debug then
        print(string.format('[Engineering Client] Entered vehicle with plate: %s', plate))
    end
end

---Called when player exits vehicle
function Engineering:OnVehicleExit()
    if not self.Enabled then return end
    
    -- Sync wear/heat one final time
    if self.CurrentPlate and Physics.RuntimeState then
        Physics:SyncToServer()
    end
    
    Physics:Cleanup()
    self.Active = false
    self.CurrentPlate = nil
end

-- ============================================================================
-- Main Update Loop
-- ============================================================================

---Start the main physics loop
function Engineering:StartMainLoop()
    SetInterval(function()
        if not self.Enabled or not self.Active then return end
        
        local playerPed = PlayerPedId()
        if not IsPedInAnyVehicle(playerPed, false) then
            self:OnVehicleExit()
            return
        end
        
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        if not vehicle or not DoesEntityExist(vehicle) then
            self:OnVehicleExit()
            return
        end
        
        -- Only process if player is driver
        if GetPedInVehicleSeat(vehicle, -1) ~= playerPed then
            Physics:Cleanup()
            return
        end
        
        -- Initialize physics if needed
        if not Physics.CurrentVehicle and self.CurrentTuning then
            Physics:Initialize(vehicle, self.CurrentTuning)
        end
        
        -- Update physics (30ms tick)
        if Physics.CurrentVehicle then
            Physics:Update(vehicle, 0.03)
        end
        
        -- Periodic sync to server (every 10 seconds)
        if (GetGameTimer() - self.LastSyncTime) > 10000 then
            Physics:SyncToServer()
            self.LastSyncTime = GetGameTimer()
        end
        
    end, 30)  -- 30ms = ~33 FPS
end

-- ============================================================================
-- Server Event Listeners
-- ============================================================================

---Request tuning data from server
AddEventHandler('playerSpawned', function()
    if Engineering.Enabled and Engineering.Active then
        local playerPed = PlayerPedId()
        if IsPedInAnyVehicle(playerPed, false) then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            local plate = GetVehicleNumberPlateText(vehicle):gsub('%s+', '')
            TriggerServerEvent('engineering:requestTuning', plate)
        end
    end
end)

-- Handle resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    if Engineering.Active then
        Engineering:OnVehicleExit()
    end
end)

-- ============================================================================
-- Exports for tablet/menu integration
-- ============================================================================

---Get current tuning data
---@return table tuning or nil
exports('GetTuning', function()
    if not Engineering.Enabled then return nil end
    return Engineering.CurrentTuning
end)

---Get current runtime state (wear, heat, etc)
---@return table runtime state
exports('GetRuntimeState', function()
    if not Engineering.Enabled then return {} end
    return Physics.RuntimeState or {}
end)

---Set ECU map (client requests server change)
---@param plate string Vehicle plate
---@param mapName string ECU map name
exports('SetECUMap', function(plate, mapName)
    if not Engineering.Enabled then return end
    TriggerServerEvent('engineering:setECUMap', plate, mapName)
end)

---Set boost PSI
---@param plate string Vehicle plate
---@param psi number Boost PSI
exports('SetBoost', function(plate, psi)
    if not Engineering.Enabled then return end
    TriggerServerEvent('engineering:setBoost', plate, psi)
end)

-- ============================================================================
-- Initialization
-- ============================================================================

-- Initialize on script start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Engineering:Init()
    end
end)

-- Cleanup on exit
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if Engineering.Active then
            Engineering:OnVehicleExit()
        end
    end
end)

return Engineering
