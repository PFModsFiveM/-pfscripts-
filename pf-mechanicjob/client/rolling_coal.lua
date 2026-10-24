-- REMOVE legacy coal (Smoke:* section & duplicate thread)
-- DELETE from: local time = 2 ... down to the second Citizen.CreateThread that used Smoke:SyncStartParticles
-- REPLACE with streamlined controller:

local KEY_ACCEL = 71
local ActiveCoal = {}
local isEmittingLocal = false
local currentNetId = nil

local QBCore = exports['pfm-core']:GetCoreObject()

-- Local debug toggle to reduce spam even when Config.Debug=true
local RC_DEBUG = (Config.RollingCoal and Config.RollingCoal.debug) or false

local EXHAUST_BONES = {
  "exhaust","exhaust_2","exhaust_3","exhaust_4","exhaust_5","exhaust_6","exhaust_7","exhaust_8",
  "exhaust_9","exhaust_10","exhaust_11","exhaust_12","exhaust_13","exhaust_14","exhaust_15","exhaust_16"
}

-- Track coal state per vehicle (synced from server)
local CoalVehicles = {} -- [plate] = true if DPF removed

-- Helper: Get normalized plate
local function _GetPlate(veh)
  if not veh or not DoesEntityExist(veh) then return nil end
  return GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
end

-- NEW: Export for checking if coal is active for vehicle
exports('IsCoalActiveForVehicle', function(veh)
  if not Config.RollingCoal.enabled then return false end
  if not Config.IsDieselCandidate(veh) then return false end
  local plate = _GetPlate(veh)
  if not plate then return false end
  return CoalVehicles[plate] == true
end)

-- Sync coal state from server
RegisterNetEvent('pf_mech:syncCoalDelete', function(plate, enabled)
  plate = tostring(plate or ''):gsub('%s+', ''):upper()
  if plate == '' then return end
  CoalVehicles[plate] = enabled
  if Config.Debug and RC_DEBUG then
    print(string.format('[COAL SYNC] %s -> %s', plate, tostring(enabled)))
  end
end)

-- Load coal state when entering vehicle
CreateThread(function()
  local lastVehicle = 0
  while true do
    Wait(1000)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
      local veh = GetVehiclePedIsIn(ped, false)
      if veh ~= 0 and veh ~= lastVehicle then
        lastVehicle = veh
        local plate = _GetPlate(veh)
        if plate and CoalVehicles[plate] == nil then
          QBCore.Functions.TriggerCallback('pf_mech:getCoalState', function(enabled)
            CoalVehicles[plate] = enabled
            if Config.Debug and RC_DEBUG then
              print(string.format('[COAL] Loaded state for %s: %s', plate, tostring(enabled)))
            end
          end, plate)
        end
      end
    else
      lastVehicle = 0
    end
  end
end)

local function getExhaustBoneIndices(veh)
  local out = {}
  for _, n in ipairs(EXHAUST_BONES) do
    local i = GetEntityBoneIndexByName(veh, n)
    if i ~= -1 then out[#out+1] = i end
  end
  return out
end

local function coalEligible(veh)
  if not Config.RollingCoal.enabled then return false end
  if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
  if not Config.IsDieselCandidate(veh) then return false end
  
  -- Check DPF status
  local plate = _GetPlate(veh)
  if not plate then return false end
  
  local removed = CoalVehicles[plate] == true
  
  if Config.Debug then
    print(string.format('[COAL CHECK] plate=%s diesel=%s dpfRemoved=%s', 
      plate, 
      tostring(Config.IsDieselCandidate(veh)), 
      tostring(removed)))
  end
  
  return removed
end

local function startParticlesFor(netId)
  local veh = NetToVeh(netId)
  if veh == 0 or not DoesEntityExist(veh) or ActiveCoal[netId] then return end
  local dict = Config.RollingCoal.effectDict
  local name = Config.RollingCoal.effectName
  local scale = Config.RollingCoal.effectScale
  RequestNamedPtfxAsset(dict)
  while not HasNamedPtfxAssetLoaded(dict) do Wait(10) end
  local bones = getExhaustBoneIndices(veh)
  local particles = {}
  
  -- Get particle counts from config
  local particlesPerBone = math.min(250, math.max(1, Config.RollingCoal.particlesPerBone or 10))
  local particlesNoBone = math.min(250, math.max(1, Config.RollingCoal.particlesNoBone or 15))
  local maxParticles = Config.RollingCoal.maxParticles or 250
  
  if #bones == 0 then
    -- No bones: spawn config amount at default exhaust location
    local count = math.min(particlesNoBone, maxParticles)
    for i = 1, count do
      UseParticleFxAssetNextCall(dict)
      local offsetY = -2.0 + (i * 0.05) -- Stagger more densely
      local offsetX = (i % 3 - 1) * 0.08 -- Spread horizontally
      particles[#particles+1] = StartParticleFxLoopedOnEntity(name, veh, offsetX, offsetY, 0.3, 0.0,0.0,0.0, scale, false,false,false)
    end
  else
    -- With bones: spawn config amount per bone
    local totalAllowed = math.floor(maxParticles / #bones)
    local perBone = math.min(particlesPerBone, totalAllowed)
    
    for _, b in ipairs(bones) do
      for i = 1, perBone do
        if #particles >= maxParticles then break end
        UseParticleFxAssetNextCall(dict)
        -- Create 3D spread pattern
        local offsetX = (i % 3 - 1) * 0.06
        local offsetY = math.floor(i / 3) * 0.05
        local offsetZ = (i % 2) * 0.04
        particles[#particles+1] = StartParticleFxLoopedOnEntityBone(name, veh, offsetX,offsetY,offsetZ, 0,0,0, b, scale, false,false,false)
      end
      if #particles >= maxParticles then break end
    end
  end
  
  ActiveCoal[netId] = { particles = particles }
  
  if Config.Debug and RC_DEBUG then
    print(string.format('[COAL] Started %d particles for netId: %s', #particles, tostring(netId)))
  end
end

local function stopParticlesFor(netId)
  local data = ActiveCoal[netId]
  if not data then return end
  for _, p in ipairs(data.particles) do
    if p then StopParticleFxLooped(p, true) end
  end
  ActiveCoal[netId] = nil
end

RegisterNetEvent('pf_mech:coal:startParticles', function(netId) startParticlesFor(netId) end)
RegisterNetEvent('pf_mech:coal:stopParticles',  function(netId) stopParticlesFor(netId)  end)

CreateThread(function()
  while true do
    Wait(0)
    if not Config.RollingCoal.enabled then
      if isEmittingLocal and currentNetId then
        TriggerServerEvent('pf_mech:coal:syncStop', currentNetId)
      end
      isEmittingLocal = false
      currentNetId = nil
      goto continue
    end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped,false) then
      if isEmittingLocal and currentNetId then
        TriggerServerEvent('pf_mech:coal:syncStop', currentNetId)
      end
      isEmittingLocal = false
      currentNetId = nil
      goto continue
    end
    local veh = GetVehiclePedIsIn(ped,false)
    if veh==0 or GetPedInVehicleSeat(veh,-1)~=ped then
      if isEmittingLocal and currentNetId then
        TriggerServerEvent('pf_mech:coal:syncStop', currentNetId)
      end
      isEmittingLocal=false
      currentNetId=nil
      goto continue
    end
    local mph = GetEntitySpeed(veh)*2.236936
    local accelHeld = IsControlPressed(1, KEY_ACCEL)
    local eligible = coalEligible(veh)
    
    -- Debug output (keep for troubleshooting)
    if Config.Debug and accelHeld then
      local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
      if GetGameTimer() % 2000 < 50 then
        print(string.format('[COAL DEBUG] plate=%s eligible=%s mph=%.1f dpfRemoved=%s', 
          plate, tostring(eligible), mph, tostring(CoalVehicles[plate] == true)))
      end
    end
    
    if accelHeld and eligible and mph <= (Config.RollingCoal.maxMph or 40.0) then
      if not isEmittingLocal then
        currentNetId = VehToNet(veh)
        isEmittingLocal = true
        TriggerServerEvent('pf_mech:coal:syncStart', currentNetId)
        
        if Config.Debug then
          print('[COAL] Started emitting for netId: '..tostring(currentNetId))
        end
      end
    else
      -- REMOVED: No notification when DPF is installed
      if isEmittingLocal and currentNetId then
        TriggerServerEvent('pf_mech:coal:syncStop', currentNetId)
        
        if Config.Debug then
          print('[COAL] Stopped emitting')
        end
      end
      isEmittingLocal=false
      currentNetId=nil
    end
    ::continue::
  end
end)

-- Debug command
if Config.Debug then
  RegisterCommand('coalstatus', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
      local veh = GetVehiclePedIsIn(ped, false)
      local plate = _GetPlate(veh)
      print('=== COAL STATUS ===')
      print('Enabled:', Config.RollingCoal.enabled)
      print('Plate:', plate)
      print('Diesel:', Config.IsDieselCandidate(veh))
      print('DPF Removed:', CoalVehicles[plate])
      print('Eligible:', coalEligible(veh))
      print('==================')
    else
      print('Not in vehicle')
    end
  end, false)
end