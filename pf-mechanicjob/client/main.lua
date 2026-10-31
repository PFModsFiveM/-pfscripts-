-- pf-mechanicjob • CLIENT (full file)
local QBCore = exports['pfm-core']:GetCoreObject()

-- Helper: check if player is a mechanic
local function isPlayerMechanic()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    return Config.IsMechanicJob(PlayerData.job.name)
end

-- Helper: Check if player has toolbox (required for all work)
local function hasToolbox(callback)
    QBCore.Functions.TriggerCallback('pf_mech:hasToolbox', function(has)
        if not has then
            QBCore.Functions.Notify(L('need_toolbox'), 'error')
        end
        callback(has)
    end)
end

-- ...existing code...

local UI_OPEN = false
local jobBlips, spawnedNPCVeh = {}

-- Tablet animation variables
local tabletDict = "amb@code_human_in_bus_passenger_idles@female@tablet@idle_a"
local tabletAnim = "idle_a"
local tabletProp = `prop_cs_tablet`
local tabletBone = 60309
local tabletObj = nil

-- NEW: Global clipboard tracker for cleanup
currentClipboard = nil

-- Register useable item
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    QBCore.Functions.TriggerCallback('QBCore:Server:GetObject', function(obj)
        QBCore = obj
        QBCore.Functions.GetPlayerData(function(PlayerData)
            PlayerJob = PlayerData.job
        end)
    end)
end)

-- ================== NUI helpers ==================
local function nui(a, p) SendNUIMessage({ action=a, payload=p }) end
local function setFocus(b) SetNuiFocus(b, b); SetNuiFocusKeepInput(false) end
local function sendMechanicAppMessage(payload)
    if not payload then return false end
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
local function openTablet(payload)
    RequestAnimDict(tabletDict)
    while not HasAnimDictLoaded(tabletDict) do Wait(100) end
    
    RequestModel(tabletProp)
    while not HasModelLoaded(tabletProp) do Wait(100) end

    local ped = PlayerPedId()
    tabletObj = CreateObject(tabletProp, 0.0, 0.0, 0.0, true, true, false)
    local bone = GetPedBoneIndex(ped, tabletBone)
    
    AttachEntityToEntity(tabletObj, ped, bone, 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, true, false, true, 1, true)
    TaskPlayAnim(ped, tabletDict, tabletAnim, 8.0, -8.0, -1, 50, 0, false, false, false)
    
    UI_OPEN = true
    setFocus(true)
    nui('openTablet', payload or {})
end
local function closeTablet()
    UI_OPEN = false
    setFocus(false)
    nui('close')
    
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    
    if tabletObj then
        DeleteEntity(tabletObj)
        tabletObj = nil
    end
end

-- ================== small helpers ==================
local function nearbyVeh(radius)
  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local veh = GetClosestVehicle(pos.x, pos.y, pos.z, radius or 6.0, 0, 70)
  if veh ~= 0 and DoesEntityExist(veh) then return veh end
  return 0
end
local function isNPCVeh(veh)
  local ent = Entity(veh)
  return ent and ent.state and ent.state.pf_jobId ~= nil
end

local function resourceActive(name)
  local st = GetResourceState(name)
  return st == 'started' or st == 'starting'
end

-- ================== progress bar (resilient) ==================
local function DoProgress(label, ms, dict, anim)
  ms = tonumber(ms) or 3000
  label = label or 'Working...'
  local ped = PlayerPedId()

  -- anim (optional)
  if dict and anim then
    if not HasAnimDictLoaded(dict) then
      RequestAnimDict(dict)
      while not HasAnimDictLoaded(dict) do Wait(0) end
    end
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0.0, false, false, false)
  end

  -- 1) ox_lib
  if resourceActive('ox_lib') and lib and lib.progressCircle then
    local ok = lib.progressCircle({
      duration = ms,
      position = 'bottom',
      label = label,
      useWhileDead = false,
      canCancel = true,
      disable = { move = true, car = true, combat = true, mouse = false }
    })
    ClearPedTasks(ped)
    return ok and true or false
  end

  -- 2) exports['progressbar']:Progress (qb-progressbar export flavor)
  if resourceActive('progressbar') then
    local exp = exports['progressbar']
    if exp and type(exp.Progress) == 'function' then
      local finished, cancelled = false, true
      exp:Progress({
        name = 'pf_mech_prog',
        duration = ms,
        label = label,
        useWhileDead = false,
        canCancel = true,
        controlDisables = { disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true },
        animation = dict and { animDict=dict, anim=anim, flags=49 } or nil,
      }, function(canc)
        cancelled = canc and true or false
        finished = true
      end)
      while not finished do Wait(25) end
      ClearPedTasks(ped)
      return not cancelled
    end
  end

  -- 3) QBCore.Functions.Progressbar (older qb-core flavor)
  if QBCore and QBCore.Functions and type(QBCore.Functions.Progressbar) == 'function' then
    local finished, cancelled = false, true
    QBCore.Functions.Progressbar(
      'pf_mech_prog',
      label,
      ms,
      false,
      true,
      { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
      dict and { animDict = dict, anim = anim, flags = 49 } or {},
      {},
      function() cancelled=false; finished=true end,
      function() cancelled=true;  finished=true end
    )
    while not finished do Wait(25) end
    ClearPedTasksImmediately(ped)
    return not cancelled
  end

  -- 4) last-resort fallback: simple wait with controls disabled
  local untilAt = GetGameTimer() + ms
  while GetGameTimer() < untilAt do
    DisableControlAction(0, 21, true)
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 22, true)
    Wait(0)
  end
  ClearPedTasks(ped)
  return true
end

local function timeForAction(action)
  local t = Config.ActionTimes or {}
  return t[action] or 4000
end

-- ================== open / commands ==================
RegisterCommand('mechtab', function() TriggerEvent('pf-mechanicjob:client:openTablet') end)
RegisterCommand('mechreset', function() TriggerEvent('pf-mechanicjob:client:closeTablet') end)

RegisterNetEvent('pf_mech:openTablet', function()
  if not isPlayerMechanic() then return end
    TriggerEvent('pf-mechanicjob:client:openTablet')
end)

-- ================== NUI Callbacks ==================
RegisterNUICallback('close', function(_, cb) closeTablet(); cb(true) end)
RegisterNUICallback('toggleNPC', function(data, cb) TriggerServerEvent('pf_mech:npc:toggle', data.enabled and true or false); cb(true) end)
RegisterNUICallback('acceptJob', function(data, cb) TriggerServerEvent('pf_mech:acceptJob', data.id); cb(true) end)
RegisterNUICallback('startJob',  function(data, cb) TriggerServerEvent('pf_mech:startJob', data.id); cb(true) end)
RegisterNUICallback('finishJob', function(data, cb) TriggerServerEvent('pf_mech:finishJob', data.id, data.quality or 80); cb(true) end)
RegisterNUICallback('orderParts',function(data, cb) TriggerServerEvent('pf_mech:orderParts', data.items or {}); cb(true) end)

-- Management callbacks
RegisterNUICallback('getManagementData', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getManagementData', function(result)
        cb(result)
    end)
end)

-- Overview data
RegisterNUICallback('management:getOverview', function(_, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getSalesOverview', function(result)
        sendMechanicAppMessage({ action = 'management:overview', data = result })
        cb(result or {})
    end)
end)

RegisterNUICallback('management:getGraph', function(_, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getSalesGraph', function(points)
        sendMechanicAppMessage({ action = 'management:graph', points = points or {} })
        cb(points or {})
    end)
end)

-- Employees list
RegisterNUICallback('management:getEmployees', function(_, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getEmployeesForBusiness', function(list)
        sendMechanicAppMessage({ action = 'management:employees', employees = list or {} })
        cb(list or {})
    end)
end)

-- Pricing
RegisterNUICallback('management:requestPricing', function(_, cb)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local business = (PlayerData and PlayerData.job and Config.GetBusinessKey(PlayerData.job.name)) or 'mechanic'
    QBCore.Functions.TriggerCallback('mechanic:server:getBusinessPrices', function(resp)
        local payload = resp or { business = business, prices = {}, taxRate = 0.0 }
        sendMechanicAppMessage({ action = 'management:pricing', prices = payload.prices or {}, business = payload.business, taxRate = payload.taxRate, canEdit = payload.canEdit })
        cb(payload)
    end, business)
end)

RegisterNUICallback('management:addProduct', function(data, cb)
    TriggerServerEvent('pf_mechanic:addProduct', data)
    cb(true)
end)

RegisterNUICallback('management:deleteProduct', function(data, cb)
    TriggerServerEvent('pf_mechanic:deleteProduct', data.productId)
    cb(true)
end)

RegisterNUICallback('management:updateSettings', function(data, cb)
    TriggerServerEvent('pf_mechanic:updateSettings', data)
    cb(true)
end)

-- Settings
RegisterNUICallback('management:getSettings', function(_, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getSettings', function(settings)
        sendMechanicAppMessage({ action = 'management:settings', settings = settings or {} })
        cb(settings or {})
    end)
end)

RegisterNUICallback('hireEmployee', function(data, cb)
    TriggerServerEvent('pf_mechanic:hireEmployee', data.id)
    cb(true)
end)

RegisterNUICallback('promoteEmployee', function(data, cb)
    TriggerServerEvent('pf_mechanic:promoteEmployee', data.citizenid, data.newRole)
    cb(true)
end)

RegisterNUICallback('demoteEmployee', function(data, cb)
    TriggerServerEvent('pf_mechanic:demoteEmployee', data.citizenid)
    cb(true)
end)

RegisterNUICallback('setEmployeeRole', function(data, cb)
    TriggerServerEvent('pf_mechanic:setEmployeeRole', data.citizenid, data.role, data.grade or 0)
    cb(true)
end)

RegisterNUICallback('fireEmployee', function(data, cb)
    TriggerServerEvent('pf_mechanic:fireEmployee', data.citizenid)
    cb(true)
end)

RegisterNUICallback('getEmployeeStats', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getEmployeeStats', function(result)
        cb(result)
    end, data.citizenid)
end)

RegisterNUICallback('getNearbyPlayersAndEmployees', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mechanic:getNearbyPlayersAndEmployees', function(result)
        cb(result or {})
    end)
end)

RegisterNUICallback('transferOwnership', function(data, cb)
    TriggerServerEvent('pf_mechanic:transferOwnership', data.newOwnerCid)
    cb(true)
end)

RegisterNUICallback('updateProductPrice', function(data, cb)
    TriggerServerEvent('pf_mechanic:updatePrice', data.productItem, data.newPrice)
    -- Backward compat: also update legacy table if handler exists
    TriggerServerEvent('pf_mechanic:updateProductPrice', data.productItem, data.newPrice)
    cb(true)
end)

RegisterNUICallback('saveBusinessSettings', function(data, cb)
    TriggerServerEvent('pf_mechanic:saveBusinessSettings', data.business_name, data.blip_name, data.blip_color)
    cb(true)
end)

RegisterNUICallback('startPlacement', function(data, cb)
    -- Location placement will be handled in the placement system
    TriggerServerEvent('pf_mechanic:startPlacement', data.type, data.mode)
    cb(true)
end)

-- NPC Jobs 

-- state
local npcOn = false
local onDuty = true  -- replace with your real on-duty flag if you have one

-- Called by NUI fetch(".../toggleNPC")
RegisterNUICallback('toggleNPC', function(data, cb)
    local want = data and data.enabled == true

    -- Optional: gate on duty
    if want and not onDuty then
        SendNUIMessage({ action = 'toast', payload = { text = 'You must be on duty to start Local Jobs.' } })
        cb('ok'); return
    end

    npcOn = want
    -- echo state back to UI immediately
    SendNUIMessage({ action = 'pf_mech:npcState', payload = { on = npcOn } })

    -- tell server
    TriggerServerEvent('pf_mech:npc:toggle', npcOn)

    cb('ok')
end)

-- ask server to (re)sync initial state when tablet opens
RegisterNUICallback('jobs:refresh', function(_, cb)
    TriggerServerEvent('pf_mech:npc:refresh')
    cb('ok')
end)

-- Server pushes job lists back
RegisterNetEvent('pf_mech:npc:updateJobs', function(payload)
    SendNUIMessage({ action = 'jobs:update', payload = payload })
end)

-- Optional simple debug hotkey
RegisterCommand('pf_npcdebug', function()
    print('npcOn=', npcOn)
end)

-- POS
RegisterNUICallback('pos:getNearby', function(_, cb)
  local ped = PlayerPedId()
  local my = GetEntityCoords(ped)
  local ids = {}
  for _, pid in ipairs(GetActivePlayers()) do
    local ped2 = GetPlayerPed(pid)
    if ped2 ~= ped then
      local d = #(GetEntityCoords(ped2) - my)
      if d <= 5.5 then ids[#ids+1] = GetPlayerServerId(pid) end
    end
  end
  QBCore.Functions.TriggerCallback('pf_mech:getPlayerNames', function(map)
    local out = {}
    for _, sid in ipairs(ids) do
      out[#out+1] = { src = sid, name = map[tostring(sid)] or ('ID '..sid) }
    end
    cb(out)
  end, ids)
end)
RegisterNUICallback('pos:requestCharge', function(data, cb)
  TriggerServerEvent('pf_mech:pos:chargePlayer', data.targetSrc or 0, data.cart or {})
  cb(true)
end)
RegisterNUICallback('pos:customerPay', function(data, cb)
  TriggerServerEvent('pf_mech:pos:customerPay', data.invoiceId, data.method, data.accept and true or false)
  cb(true)
  nui('pay:close')
end)
RegisterNetEvent('pf_mech:pos:openPayment', function(invoice)
  setFocus(true)
  SendNUIMessage({ action='pos:payPrompt', payload=invoice })
end)
RegisterNetEvent('pf_mech:pos:paid', function(selfCharge)
  if selfCharge then closeTablet() end
end)

-- Live refresh coming from server
RegisterNetEvent('pf_mech:jobsUpdate', function()
  if not UI_OPEN then return end
  QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(d)
    if not d then return end
    nui('jobs:update', {
      jobsNew    = d.jobsNew or {},
      jobsActive = d.jobsActive or {},
      profile    = d.profile or {},
      thresholds = d.thresholds or {}
    })
    nui('stock:update', { stock = d.stock or {} })
  end)
end)

-- Management statistics refresh (triggered after charges or other updates)
RegisterNetEvent('pf_mechanic:refreshManagementOverview', function(data)
    if not PFMechShellOpen() then
        return
    end
    sendMechanicAppMessage({ action = 'management:overview', data = data })
  -- Also update the chart if we have data
  if data and data.chartData then
        sendMechanicAppMessage({ action = 'management:graph', points = data.chartData })
  end
end)
RegisterNetEvent('pf_mech:stockUpdate', function()
  if not UI_OPEN then return end
  QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(d)
    if d then nui('stock:update', { stock = d.stock or {} }) end
  end)
end)

-- Only toast if it’s a job we can actually take
RegisterNetEvent('pf_mech:client:newJob', function(job)
  if UI_OPEN then
    SendNUIMessage({ action='toast', payload={ text=('NPC request: %s %s'):format(job.type or 'job', job.plate or '') }})
  end
end)

-- ================== NPC spawn/cleanup ==================
RegisterNetEvent('pf_mech:client:spawnNPCVeh', function(d)
  local model = joaat(d.model or 'sultan')
  RequestModel(model) while not HasModelLoaded(model) do Wait(0) end

  local x,y,z,h = d.coords.x, d.coords.y, d.coords.z, d.coords.h or 0.0
  local veh = CreateVehicle(model, x, y, z, h, true, true)
  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleOnGroundProperly(veh)
  SetVehicleNumberPlateText(veh, d.plate or ('NPC'..math.random(100,999)))
  SetVehicleEngineHealth(veh, 700.0)

  local ent = Entity(veh); if ent and ent.state then ent.state:set('pf_jobId', d.id, true) end

  local pop = tonumber(d.popTires or 0) or 0
  if pop > 0 then
    local popped = 0
    for i=0,5 do
      if popped >= pop then break end
      SetVehicleTyreBurst(veh, i, true, 1000.0)
      popped = popped + 1
    end
  end

  local blip = AddBlipForEntity(veh)
  SetBlipSprite(blip, 225); SetBlipScale(blip, .85); SetBlipColour(blip, 26)
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString(d.name or 'Work Order'); EndTextCommandSetBlipName(blip)
  jobBlips[d.id] = blip; spawnedNPCVeh[d.id] = veh

  local nx,ny,nz = table.unpack(GetEntityCoords(veh))
  TriggerServerEvent('pf_mech:npcVehSpawned', { id=d.id, netId=NetworkGetNetworkIdFromEntity(veh), x=nx, y=ny, z=nz, h=h })
end)
RegisterNetEvent('pf_mech:client:clearJobBlip', function(id)
  local blip = jobBlips[id]; if blip and DoesBlipExist(blip) then RemoveBlip(blip) end; jobBlips[id]=nil
  local veh = spawnedNPCVeh[id]; if veh and DoesEntityExist(veh) then DeleteVehicle(veh) end; spawnedNPCVeh[id]=nil
end)

-- ================== /scanveh ==================
local function vehModelName(veh)
  local hash = GetEntityModel(veh)
  local key = GetDisplayNameFromVehicleModel(hash)
  local txt = key and GetLabelText(key)
  if txt and txt ~= 'NULL' then return txt end
  return key or ('0x'..string.format('%X', hash))
end

-- Forward-declare helpers (move here so diagnostics handler can call them)
local function partsNeededForRepair(partKey, healthPercent)
    local rule = (Config.PartRules or {})[partKey] or {}
    local maxItems = tonumber(rule.max_items) or 0

    -- sensible defaults for known types if not declared in config
    if maxItems <= 0 then
        if partKey:match('engine') or rule.type == 'engine' then maxItems = 5 end
        if partKey == 'body_part' or rule.type == 'body' then maxItems = 5 end
        if partKey == 'sparkplugs' or rule.type == 'sparkplugs' then maxItems = 8 end
        if rule.type == 'battery' then maxItems = 1 end
        if rule.type == 'axle' then maxItems = 4 end
        if partKey == 'tire_new' then maxItems = 4 end
        if rule.type == 'oil' then maxItems = 1 end
    end

    -- clamp healthPercent
    healthPercent = math.max(0, math.min(100, tonumber(healthPercent) or 0))

    -- parts needed = ceil( missingPercent * maxItems )
    if maxItems <= 0 then return 0 end
    local missingPercent = 100 - healthPercent
    local needed = math.ceil((missingPercent / 100) * maxItems)
    if needed < 0 then needed = 0 end
    if needed > maxItems then needed = maxItems end
    return needed
end

-- ADD: label for DPF
local DiagnosticLabels = {
    alternator = "Alternator",
    sparkplugs = "Spark Plugs",
    carbattery = "Car Battery",
    engine_oil = "Engine Oil",
    oil_filter = "Oil Filter",
    brakes = "Brake Pads",      -- NEW
    susp_arm = "Suspension Arm",
    axleparts = "Axle Parts",
    engine_part = "Engine Part",
    body_part = "Body Panel",
    tire_new = "Tire",
    dpf = "Diesel Particulate Filter"  -- NEW
}

-- NEW: helper to build DPF menu row
local function buildDPFMenuRow(veh)
    if not Config.IsDieselCandidate(veh) then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    local removed = IsDPFRemoved(veh)
    if not removed then
        return {
            header = 'DPF (Installed)',
            txt = 'Remove to enable rolling coal',
            params = { event='pf_mech:dpf:clientRemove', args={ plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    else
        return {
            header = 'DPF (Removed)',
            txt = 'Install to disable rolling coal',
            params = { event='pf_mech:dpf:clientInstall', args={ plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    end
end

-- ================== diagnostics tool ==================
-- REPLACE diagnostics_tool use handling to show full menu + DPF option
-- REMOVE diagnostics_tool inline menu handler (now in diagnostic module)
AddEventHandler('QBCore:Client:UseItem', function(item)
    local name = item and item.name
    if not name then return end

    -- CHANGED: remove mechanic_tools from this branch (leave toolbox only)
    if name == 'toolbox' then
      local veh = nearbyVeh(6.0)
      if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
      
      local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
      
      -- FIX: Get diagnostics and convert damage to health
      local state = Entity(veh).state
      local damage = state.partDamage or {}
      
      local menu = {
          { header = ('Toolbox • %s'):format(plate), isMenuHeader = true },
          { header = '--- Component Health ---', txt = 'All parts shown as health %', isMenuHeader = true }
      }
      
      -- Show critical parts health
      local parts = {
          { key = 'oil', label = 'Engine Oil' },
          { key = 'brakes', label = 'Brake Pads' },
          { key = 'sparkplugs', label = 'Spark Plugs' },
          { key = 'carbattery', label = 'Battery' },
          { key = 'alternator', label = 'Alternator' },
          { key = 'suspension', label = 'Suspension' },
          { key = 'axle', label = 'Axle' },
          { key = 'radiator', label = 'Radiator' },
          { key = 'coolant', label = 'Coolant' }
      }
      
      for _, p in ipairs(parts) do
          local dmg = tonumber(damage[p.key]) or 0
          local health = math.max(0, math.min(100, 100 - dmg)) -- Convert damage to health
          local color = health > 70 and '🟢' or health > 40 and '🟡' or '🔴'
          menu[#menu+1] = {
              header = string.format('%s %s - %d%%', color, p.label, health),
              txt = health < 30 and 'CRITICAL' or health < 60 and 'Needs attention' or 'Good',
              params = {}
          }
      end
      
      menu[#menu+1] = { header = '--- Removable Parts ---', isMenuHeader = true }
      
      -- DPF removal option (only show for diesel)
      if Config.IsDieselCandidate(veh) then
          local dpfRemoved = IsDPFRemoved(veh)
          if not dpfRemoved then
              menu[#menu+1] = {
                  header = 'Remove DPF',
                  txt = 'Takes 6 seconds. Enables rolling coal',
                  params = { 
                      event = 'pf_mech:dpf:clientRemove', 
                      args = { plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) } 
                  }
              }
          else
              menu[#menu+1] = {
                  header = 'DPF Already Removed',
                  txt = 'Use DPF item to reinstall',
                  params = {}
              }
          end
      else
          menu[#menu+1] = {
              header = 'DPF - Not Applicable',
              txt = 'Vehicle is not diesel',
              params = {}
          }
      end
      
      menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
      exports['pfm-menu']:openMenu(menu)
      return
    end

    -- cosmetic items (mods)
    if name == "spoiler" or name == "bumper" or name == "exhaust"
       or name == "rollcage" or name == "hood" or name == "roof" then
        -- This will be caught by server CreateUseableItem instead
        return
    end
end)

-- ADD: wheel (rims) use handler
RegisterNetEvent('pf-mechanicjob:client:useWheels', function(itemName)
    local veh = nearbyVeh(6.0)
    if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error') return end
    if GetIsVehicleEngineRunning(veh) then QBCore.Functions.Notify('Turn engine off first','error') return end
    SetVehicleModKit(veh, 0)
    local count = GetNumVehicleMods(veh, 23)
    if count == 0 then QBCore.Functions.Notify('No wheel variants','error') return end
    local menu = { { header='Wheel Options', isMenuHeader=true } }
    for i=0,count-1 do
        local lbl = GetModTextLabel(veh, 23, i)
        local nice = (lbl and GetLabelText(lbl) ~= 'NULL') and GetLabelText(lbl) or ('Wheel %d'):format(i+1)
        menu[#menu+1] = {
            header = nice,
            txt = 'Install',
            params = {
                event = 'pf-mechanicjob:client:applyCosmeticModFallback',
                args = {
                    vehicle = NetworkGetNetworkIdFromEntity(veh),
                    item = 'rims',
                    modType = 23,
                    modIndex = i
                }
            }
          }
    end
    menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(menu)
end)

-- ================== cosmetic picker (multi-category support) ==================
local MultiCosmeticMap = {
    bumper      = { 1, 2 },
    vehicle_bumper = { 1, 2 },
    externals   = { 6, 8, 9, 10, 45 },
    internals   = { 28,29,30,31,32,33,34,35,36,37,38,39,40 },
    customplate = { 25, 48 },
}

local SingleCosmeticMap = {
    spoiler = 0, skirts = 3, exhaust = 4, rollcage = 5,
    hood = 7, roof = 10, rims = 23, livery = 46, seat = 31, horn = 14
}

local function readableModName(modType)
    local labels = {
        [0]='Spoiler',[1]='Front Bumper',[2]='Rear Bumper',[3]='Side Skirt',[4]='Exhaust',
        [5]='Roll Cage',
        [6]='Grille',[7]='Hood',[8]='Fender',[9]='Right Fender',[10]='Roof',[14]='Horn',[23]='Wheels',
        [25]='Plate Holder',[28]='Dashboard',[29]='Dial Design',[30]='Door Speakers',[31]='Seats',
        [32]='Steering Wheel',[33]='Shifter',[34]='Plaque',[35]='Speakers',[36]='Trunk',
        [37]='Hydraulics',[38]='Engine Block',[39]='Air Filter',[40]='Struts',[41]='Arch Cover',
        [42]='Aerials',[43]='Trim',[44]='Tank',[45]='Windows',[46]='Livery',[48]='Vanity Plate'
    }
    return labels[modType] or ('Mod '..modType)
end

-- CHANGED fallback picker (multi-category support)
if not _G.pf_mech_cosmetics_loaded then
    RegisterNetEvent('pf-mechanicjob:client:openCosmeticPicker', function(itemName, veh)
        if Config.Debug then
            print('[COSMETIC PICKER] item='..tostring(itemName))
        end
        if not veh or veh == 0 or not DoesEntityExist(veh) then
            QBCore.Functions.Notify('No vehicle nearby', 'error'); return
        end
        if GetIsVehicleEngineRunning(veh) then
            QBCore.Functions.Notify('Turn engine off first', 'error'); return
        end
        SetVehicleModKit(veh, 0)

        -- Tint direct
        if itemName == 'tint_supplies' then
            openTintPicker(veh)
            return
        end

        local multi = MultiCosmeticMap[itemName]
        local single = SingleCosmeticMap[itemName]

        -- If unknown
        if not multi and not single then
            QBCore.Functions.Notify('Unsupported cosmetic item', 'error')
            if Config.Debug then print('[COSMETIC PICKER] Unsupported: '..tostring(itemName)) end
            return
        end

        -- MULTI CATEGORY FIRST LEVEL
        if multi then
            local menu = {
                { header = (itemName:gsub('_',' '))..' Categories', isMenuHeader = true }
            }
            for _, modType in ipairs(multi) do
                local count = GetNumVehicleMods(veh, modType)
                local label = readableModName(modType)
                local suffix = count > 0 and ('['..count..' options]') or '[none]'
                menu[#menu+1] = {
                    header = label..' '..suffix,
                    txt = count > 0 and 'Select to view options' or 'No variants',
                    params = count > 0 and {
                        event = 'pf-mechanicjob:client:openCosmeticVariants',
                        args = { vehicle = NetworkGetNetworkIdFromEntity(veh), item = itemName, modType = modType }
                    } or {}
                }
            end
            menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
            exports['pfm-menu']:openMenu(menu)
            return
        end

        -- SINGLE CATEGORY
        local modType = single
        local count = GetNumVehicleMods(veh, modType)
        if count == 0 then
            QBCore.Functions.Notify('No variants for this vehicle', 'error')
            return
        end

        local title = readableModName(modType)..' Options'
        local menu = { { header = title, isMenuHeader = true } }
        for i = 0, count - 1 do
            local textLabel = GetModTextLabel(veh, modType, i)
            local nice = textLabel and GetLabelText(textLabel)
            if nice == 'NULL' or not nice then nice = ('Option %d'):format(i+1) end
            menu[#menu+1] = {
                header = nice,
                params = {
                    event = 'pf-mechanicjob:client:applyCosmeticModFallback',
                    args = {
                        vehicle = NetworkGetNetworkIdFromEntity(veh),
                        item = itemName,
                        modType = modType,
                        modIndex = i
                    }
                }
              }
        end
        menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
        exports['pfm-menu']:openMenu(menu)
    end)

    -- CHANGED: variants for multi category
    RegisterNetEvent('pf-mechanicjob:client:openCosmeticVariants', function(data)
        local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
        if not veh or veh == 0 or not DoesEntityExist(veh) then
            QBCore.Functions.Notify('Vehicle not found', 'error'); return
        end
        if GetIsVehicleEngineRunning(veh) then
            QBCore.Functions.Notify('Turn engine off first', 'error'); return
        end
        SetVehicleModKit(veh, 0)
        local modType = tonumber(data.modType)
        local itemName = data.item
        local count = GetNumVehicleMods(veh, modType)
        if count == 0 then
            QBCore.Functions.Notify('No variants', 'error'); return
        end
        local menu = {
            { header = readableModName(modType)..' Variants', isMenuHeader = true }
        }
        for i=0,count-1 do
            local textLabel = GetModTextLabel(veh, modType, i)
            local nice = textLabel and GetLabelText(textLabel)
            if nice == 'NULL' or not nice then nice = ('Option %d'):format(i+1) end
            menu[#menu+1] = {
                header = nice,
                params = {
                    event = 'pf-mechanicjob:client:applyCosmeticModFallback',
                    args = {
                        vehicle = NetworkGetNetworkIdFromEntity(veh),
                        item = itemName,
                        modType = modType,
                        modIndex = i
                    }
                }
            }
        end
        menu[#menu+1] = { header='Back', params={ event='pf-mechanicjob:client:openCosmeticPicker', args=itemName, } }
        menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
        exports['pfm-menu']:openMenu(menu)
    end)

    -- CHANGED: applyCosmeticModFallback (leave below, unchanged apart from comment)
    -- It consumes the item and calls server applyMod.
    RegisterNetEvent('pf-mechanicjob:client:applyCosmeticModFallback', function(data)
        local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
        if not veh or veh == 0 or not DoesEntityExist(veh) then
            QBCore.Functions.Notify('Vehicle not found', 'error'); return
        end
        if GetIsVehicleEngineRunning(veh) then
            QBCore.Functions.Notify('Turn engine off first', 'error'); return
        end
        SetVehicleModKit(veh, 0)

        -- Progress
        RequestAnimDict('mini@repair')
        while not HasAnimDictLoaded('mini@repair') do Wait(0) end
        TaskPlayAnim(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 8.0, -8.0, -1, 49, 0, false, false, false)

        if not DoProgress('Installing modification...', Config.ActionTimes.setMod or 4500, 'mini@repair', 'fixing_a_ped') then
            ClearPedTasks(PlayerPedId())
            QBCore.Functions.Notify('Installation cancelled', 'error')
            return
        end
        ClearPedTasks(PlayerPedId())

        -- Consume item server-side and broadcast sync
        TriggerServerEvent('pf_mech:server:applyMod', {
            vehicle  = NetworkGetNetworkIdFromEntity(veh),
            item     = data.item,
            modType  = data.modType,
            modIndex = data.modIndex
        })
        QBCore.Functions.Notify('Modification applied', 'success')
    end)
end

-- ============================================================================
-- ROLLING COAL SYSTEM
-- ============================================================================

-- Track coal delete state per vehicle
local CoalVehicles = {} -- [plate] = true/false

-- Helper: Get normalized plate
local function GetPlate(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
end

-- Helper: Check if coal is enabled for vehicle
local function IsCoalEnabled(veh)
    if not Config.RollingCoal.enabled then return false end
    if not Config.IsDieselCandidate(veh) then return false end
    
    local plate = GetPlate(veh)
    if not plate then return false end
    
    return CoalVehicles[plate] == true
end

-- Sync coal state from server
RegisterNetEvent('pf_mech:syncCoalDelete', function(plate, enabled)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    CoalVehicles[plate] = enabled
    
    if Config.Debug then
        print(string.format('[COAL] Synced %s: %s', plate, tostring(enabled)))
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
                local plate = GetPlate(veh)
                
                if plate and CoalVehicles[plate] == nil then
                    -- Load state from server
                    QBCore.Functions.TriggerCallback('pf_mech:getCoalState', function(enabled)
                        CoalVehicles[plate] = enabled
                    end, plate)
                end
            end
        else
            lastVehicle = 0
        end
    end
end)

-- REMOVE events: pf_mech:toggleCoalDelete and pf_mech:toggleCoalDeleteNearby (legacy coal delete)
-- REPLACE their handlers with a notice:

RegisterNetEvent('pf_mech:toggleCoalDelete', function()
  QBCore.Functions.Notify('Use diagnostics tool to remove DPF','primary')
end)
RegisterNetEvent('pf_mech:toggleCoalDeleteNearby', function()
  QBCore.Functions.Notify('Use diagnostics tool near diesel vehicle','primary')
end)

-- ADD simple command to open DPF menu directly (fallback if item not useable):
RegisterCommand('dpf', function()
  local veh = nearbyVeh(6.0)
  if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error') return end
  local plate = GetVehicleNumberPlateText(veh)
  if not Config.IsDieselCandidate(veh) then
    QBCore.Functions.Notify('Not a diesel vehicle','error'); return
  end
  -- reuse existing menu function
  local ok = pcall(function() openDPFMenu(veh) end)
  if not ok then QBCore.Functions.Notify('DPF menu unavailable','error') end
end, false)

-- DPF helper: get plate normalized
local function _GetPlate(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
end

-- DPF state check (CoalVehicles true means DPF removed)
function IsDPFRemoved(veh)
    local plate = _GetPlate(veh)
    if not plate then return false end
    -- FIX: Use correct global variable name
    return CoalVehicles[plate] == true
end

-- Open DPF menu (from diagnostics tool)
local function openDPFMenu(veh)
    if not veh or veh==0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby','error')
        return
    end
    if not Config.IsDieselCandidate(veh) then
        QBCore.Functions.Notify('Vehicle is not diesel','error')
        return
    end
    local plate = _GetPlate(veh)
    local removed = IsDPFRemoved(veh)
    local rows = {
        { header = ('DPF • %s'):format(plate or 'N/A'), isMenuHeader = true }
    }
    if not removed then
        rows[#rows+1] = {
            header = 'Remove DPF',
            txt = 'Removes the Diesel Particulate Filter (enables rolling coal)',
            params = { event='pf_mech:dpf:clientRemove', args={ plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    else
        rows[#rows+1] = {
            header = 'Install DPF',
            txt = 'Reinstall filter (disables rolling coal)',
            params = { event='pf_mech:dpf:clientInstall', args={ plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    end
    rows[#rows+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(rows)
end

RegisterNetEvent('pf_mech:dpf:clientRemove', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.veh or 0)
    if not DoesEntityExist(veh) then return end
    if IsDPFRemoved(veh) then
        QBCore.Functions.Notify('DPF already removed','error')
        return
    end
    hasToolbox(function(has)
        if not has then return end
        if not DoProgress('Removing DPF...', Config.DPFRemoveTime, 'amb@world_human_vehicle_mechanic@male@base', 'base') then
            QBCore.Functions.Notify('Cancelled','error'); return
        end
        TriggerServerEvent('pf_mech:dpf:remove', data.plate)
    end)
end)

RegisterNetEvent('pf_mech:dpf:clientInstall', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.veh or 0)
    if not DoesEntityExist(veh) then return end
    if not IsDPFRemoved(veh) then
        QBCore.Functions.Notify('DPF already installed','error')
        return
    end
    hasToolbox(function(has)
        if not has then return end
        if not DoProgress('Installing DPF...', Config.DPFInstallTime, 'amb@world_human_vehicle_mechanic@male@base', 'base') then
            QBCore.Functions.Notify('Cancelled','error'); return
        end
        TriggerServerEvent('pf_mech:dpf:install', data.plate)
    end)
end)

-- DPF item use (diagnostics_tool is handled by server/diagnostics.lua inspection flow)
AddEventHandler('QBCore:Client:UseItem', function(item)
    local name = item and item.name
    if name == Config.DPFItem then
        -- Allow installing DPF by using the item near the front of a diesel vehicle
        local veh = nearbyVeh(6.0)
        if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
        if not Config.IsDieselCandidate(veh) then QBCore.Functions.Notify('Not a diesel vehicle','error'); return end
        if not IsDPFRemoved(veh) then QBCore.Functions.Notify('DPF already installed','error'); return end
        local plate = _GetPlate(veh)
        TriggerEvent('pf_mech:dpf:clientInstall', { plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) })
    end
end)

-- Feedback from server
RegisterNetEvent('pf_mech:dpf:result', function(action, success, msg, plate, state)
    if msg then QBCore.Functions.Notify(msg, success and 'success' or 'error', 4000) end
    if plate then
        CoalVehicles[plate] = state and true or false
    end
end)

-- REMOVE: any AddEventHandler('QBCore:Client:UseItem') blocks that build a quick diagnostics menu
-- (kept toolbox/DPT handlers elsewhere; delete diagnostics_tool menu portions)
--[[
AddEventHandler('QBCore:Client:UseItem', function(item)
  if item and item.name == 'diagnostics_tool' then
     -- OLD instant menu (deleted)
  end
end)
]]

-- /scanveh: use inspection flow for player-owned (non-NPC) vehicles
RegisterCommand('scanveh', function()
  local veh = nearbyVeh(6.0)
  if veh == 0 then return TriggerEvent('QBCore:Notify',L('no_vehicle'),'error') end
  if isNPCVeh(veh) then
    -- NPC vehicle diagnostics
    local id = 0
    pcall(function() id = NetworkGetEntityOwner(veh) end)
    QBCore.Functions.TriggerCallback('pf_mech:job:getInfo', function(job)
      local rows = {
        { header = L('vehicle_info'), txt = '', isMenuHeader = true },
        { header = L('part_engine'), txt = ('%.1f%%'):format(GetVehicleEngineHealth(veh)), params = {} },
        { header = L('part_body'), txt = ('%.1f%%'):format(GetVehicleBodyHealth(veh)), params = {} },
        { header = L('diagnostics_plate'), txt = GetVehicleNumberPlateText(veh), params = {} },
        { header = L('diagnostics_owner'), txt = (GetPlayerName(id) or L('unknown')):gsub('^%s*(.-)%s*$','%1'), params = {} },
      }
      -- NEW: append DPF row for diesel vehicles
      if Config.IsDieselCandidate(veh) then
        local plate = GetVehicleNumberPlateText(veh)
        local dpfRemoved = false
        pcall(function() dpfRemoved = exports['pf-mechanicjob']:IsCoalActiveForVehicle(veh) end)
        rows[#rows+1] = {
          header = dpfRemoved and 'DPF (Removed)' or 'DPF (Installed)',
          txt = dpfRemoved and 'Rolling coal enabled' or 'Remove to enable rolling coal',
          params = { event = dpfRemoved and 'pf_mech:dpf:clientInstall' or 'pf_mech:dpf:clientRemove', args = { plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
      end
      exports['pfm-menu']:openMenu(rows)
    end, id)
  else
    -- NORMAL vehicle diagnostics
    local plate = GetVehicleNumberPlateText(veh)
    local name  = vehModelName(veh)
    local eng = math.max(0, math.min(100, math.floor(GetVehicleEngineHealth(veh)/10)))
    local body= math.max(0, math.min(100, math.floor(GetVehicleBodyHealth(veh)/10)))
    local menu = {
      { header = name, txt = (L('diagnostics_plate')..': %s'):format(plate or 'N/A'), isMenuHeader = true, params = {} },
      { header = (L('part_engine')..' - %d%%'):format(eng), txt = L('diagnostics_health'), params = {} },
      { header = (L('part_body')..' - %d%%'):format(body), txt = L('diagnostics_health'), params = {} },
    }
    -- NEW: DPF status row for diesel vehicles
    if Config.IsDieselCandidate(veh) then
      local dpfRemoved = false
      pcall(function() dpfRemoved = exports['pf-mechanicjob']:IsCoalActiveForVehicle(veh) end)
      menu[#menu+1] = {
        header = dpfRemoved and 'DPF - Removed' or 'DPF - Installed',
        txt = dpfRemoved and 'Rolling coal enabled' or 'Remove to enable rolling coal',
        params = { event = dpfRemoved and 'pf_mech:dpf:clientInstall' or 'pf_mech:dpf:clientRemove', args = { plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
      }
    end
    menu[#menu+1] = { header = L('menu_close'), params = { event='qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(menu)
  end
end)

-- Ensure single diagnostics hook (remove other AddEventHandler('QBCore:Client:UseItem') blocks above this)
local function _NormPlate(veh)
  return (veh and DoesEntityExist(veh)) and GetVehicleNumberPlateText(veh):gsub('%s+',''):upper() or nil
end
local function _DPFRemoved(veh) return veh and CoalVehicles[_NormPlate(veh)] == true end

AddEventHandler('QBCore:Client:UseItem', function(item)
    local name = item and item.name
    if not name then return end

    -- diagnostics_tool: handled by server/diagnostics.lua -> openDiagnosticsDirect -> full inspection flow

    if name == Config.DPFItem then
      local veh = nearbyVeh(6.0)
      if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
      if not _DPFRemoved(veh) then QBCore.Functions.Notify('DPF already installed','error'); return end
      TriggerEvent('pf_mech:dpf:clientInstall', { plate=_NormPlate(veh), veh=NetworkGetNetworkIdFromEntity(veh) })
      return
    end

    -- cosmetic items (mods)
    if name == "spoiler" or name == "bumper" or name == "exhaust"
       or name == "rollcage" or name == "hood" or name == "roof" then
        -- This will be caught by server CreateUseableItem instead
        return
    end
end)

-- ================== Tint Picker ==================
local function openTintPicker(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn engine off first', 'error')
        return
    end

    local tintNames = {
        [0] = 'None',
        [1] = 'Pure Black',
        [2] = 'Darksmoke',
        [3] = 'Lightsmoke',
        [4] = 'Limo',
        [5] = 'Green',
        [6] = 'Blue'
    }

    local menu = {
        { header = 'Window Tint Options', isMenuHeader = true }
    }

    for i = 0, 6 do
        menu[#menu+1] = {
            header = tintNames[i] or ('Tint '..i),
            txt = 'Apply this tint',
            params = {
                event = 'pf-mechanicjob:client:applyTint',
                args = {
                    vehicle = NetworkGetNetworkIdFromEntity(veh),
                    tintLevel = i
                }
            }
        }
    end

    menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(menu)
end

-- Apply tint (with progress bar and item consumption)
RegisterNetEvent('pf-mechanicjob:client:applyTint', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn engine off first', 'error')
        return
    end

    RequestAnimDict('mini@repair')
    while not HasAnimDictLoaded('mini@repair') do Wait(0) end
    local ped = PlayerPedId()
    TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 8.0, -8.0, -1, 49, 0, false, false, false)

    if not DoProgress('Applying window tint...', 6000, 'mini@repair', 'fixing_a_ped') then
        ClearPedTasks(ped)
        QBCore.Functions.Notify('Tint installation cancelled', 'error')
        return
    end
    ClearPedTasks(ped)

    -- Apply tint locally first for instant feedback
    local tintLevel = tonumber(data.tintLevel) or 0
    SetVehicleWindowTint(veh, tintLevel)
    
    if Config.Debug then
        print(string.format('[CLIENT TINT] Applied level %d to vehicle netId %d', tintLevel, data.vehicle))
    end

    -- Server-side: consume item and sync to other players
    TriggerServerEvent('pf_mech:server:applyTint', {
        vehicle = data.vehicle,
        tintLevel = tintLevel
    })

    QBCore.Functions.Notify('Window tint applied', 'success')
end)

-- ================== Paintcan (Full Color System with Spray Animation) ==================
-- Organized by finish type
local PaintColors = {
    classic = {
        {id=0,name='Black'},{id=1,name='Carbon Black'},{id=2,name='Graphite'},{id=3,name='Anthracite Black'},
        {id=4,name='Black Steel'},{id=5,name='Dark Steel'},{id=6,name='Silver'},{id=7,name='Bluish Silver'},
        {id=8,name='Rolled Steel'},{id=9,name='Shadow Silver'},{id=10,name='Stone Silver'},{id=11,name='Midnight Silver'},
        {id=12,name='Cast Iron Silver'},{id=27,name='Red'},{id=28,name='Torino Red'},{id=29,name='Formula Red'},
        {id=30,name='Lava Red'},{id=31,name='Blaze Red'},{id=32,name='Grace Red'},{id=33,name='Garnet Red'},
        {id=34,name='Sunset Red'},{id=35,name='Cabernet Red'},{id=36,name='Wine Red'},{id=37,name='Candy Red'},
        {id=38,name='Hot Pink'},{id=39,name='Pfsiter Pink'},{id=40,name='Salmon Pink'},{id=41,name='Sunrise Orange'},
        {id=42,name='Orange'},{id=43,name='Bright Orange'},{id=44,name='Gold'},{id=45,name='Bronze'},
        {id=46,name='Yellow'},{id=47,name='Race Yellow'},{id=48,name='Dew Yellow'},{id=49,name='Dark Green'},
        {id=50,name='Racing Green'},{id=51,name='Sea Green'},{id=52,name='Olive Green'},{id=53,name='Bright Green'},
        {id=54,name='Gasoline Green'},{id=55,name='Lime Green'},{id=56,name='Midnight Blue'},{id=57,name='Galaxy Blue'},
        {id=58,name='Dark Blue'},{id=59,name='Saxon Blue'},{id=60,name='Blue'},{id=61,name='Mariner Blue'},
        {id=62,name='Harbor Blue'},{id=63,name='Diamond Blue'},{id=64,name='Surf Blue'},{id=65,name='Nautical Blue'},
        {id=66,name='Racing Blue'},{id=67,name='Ultra Blue'},{id=68,name='Light Blue'},{id=69,name='Chocolate Brown'},
        {id=70,name='Bison Brown'},{id=71,name='Creeen Brown'},{id=72,name='Feltzer Brown'},{id=73,name='Maple Brown'},
        {id=74,name='Beechwood Brown'},{id=75,name='Sienna Brown'},{id=76,name='Saddle Brown'},{id=77,name='Moss Brown'},
        {id=78,name='Woodbeech Brown'},{id=79,name='Straw Brown'},{id=80,name='Sandy Brown'},{id=81,name='Bleached Brown'},
        {id=82,name='Schafter Purple'},{id=83,name='Spinnaker Purple'},{id=84,name='Midnight Purple'},{id=85,name='Bright Purple'},
        {id=86,name='Cream'},{id=87,name='Ice White'},{id=88,name='Frost White'}
    },
    metallic = {
        {id=0,name='Black'},{id=1,name='Carbon Black'},{id=2,name='Graphite'},{id=3,name='Anthracite Black'},
        {id=4,name='Black Steel'},{id=5,name='Dark Steel'},{id=6,name='Silver'},{id=7,name='Bluish Silver'},
        {id=8,name='Rolled Steel'},{id=9,name='Shadow Silver'},{id=10,name='Stone Silver'},{id=11,name='Midnight Silver'},
        {id=12,name='Cast Iron Silver'},{id=27,name='Red'},{id=28,name='Torino Red'},{id=29,name='Formula Red'},
        {id=30,name='Lava Red'},{id=31,name='Blaze Red'},{id=32,name='Grace Red'},{id=33,name='Garnet Red'},
        {id=34,name='Sunset Red'},{id=35,name='Cabernet Red'},{id=36,name='Wine Red'},{id=37,name='Candy Red'},
        {id=38,name='Hot Pink'},{id=39,name='Pfsiter Pink'},{id=40,name='Salmon Pink'},{id=41,name='Sunrise Orange'},
        {id=42,name='Orange'},{id=43,name='Bright Orange'},{id=44,name='Gold'},{id=45,name='Bronze'},
        {id=46,name='Yellow'},{id=47,name='Race Yellow'},{id=48,name='Dew Yellow'},{id=49,name='Dark Green'},
        {id=50,name='Racing Green'},{id=51,name='Sea Green'},{id=52,name='Olive Green'},{id=53,name='Bright Green'},
        {id=54,name='Gasoline Green'},{id=55,name='Lime Green'},{id=56,name='Midnight Blue'},{id=57,name='Galaxy Blue'},
        {id=58,name='Dark Blue'},{id=59,name='Saxon Blue'},{id=60,name='Blue'},{id=61,name='Mariner Blue'},
        {id=62,name='Harbor Blue'},{id=63,name='Diamond Blue'},{id=64,name='Surf Blue'},{id=65,name='Nautical Blue'},
        {id=66,name='Racing Blue'},{id=67,name='Ultra Blue'},{id=68,name='Light Blue'},{id=69,name='Chocolate Brown'},
        {id=70,name='Bison Brown'},{id=71,name='Creeen Brown'},{id=72,name='Feltzer Brown'},{id=73,name='Maple Brown'},
        {id=74,name='Beechwood Brown'},{id=75,name='Sienna Brown'},{id=76,name='Saddle Brown'},{id=77,name='Moss Brown'},
        {id=78,name='Woodbeech Brown'},{id=79,name='Straw Brown'},{id=80,name='Sandy Brown'},{id=81,name='Bleached Brown'},
        {id=82,name='Schafter Purple'},{id=83,name='Spinnaker Purple'},{id=84,name='Midnight Purple'},{id=85,name='Bright Purple'},
        {id=86,name='Cream'},{id=87,name='Ice White'},{id=88,name='Frost White'},{id=89,name='Honey Beige'},
        {id=90,name='Brown'},{id=91,name='Dark Brown'},{id=92,name='Straw Beige'},{id=93,name='Moss Brown'},
        {id=94,name='Biston Brown'}
    },
    matte = {
        {id=12,name='Black'},{id=13,name='Gray'},{id=14,name='Light Gray'},{id=15,name='Ice White'},
        {id=16,name='Blue'},{id=17,name='Dark Blue'},{id=18,name='Midnight Blue'},{id=19,name='Midnight Purple'},
        {id=20,name='Schafter Purple'},{id=21,name='Red'},{id=22,name='Dark Red'},{id=23,name='Orange'},
        {id=24,name='Yellow'},{id=25,name='Lime Green'},{id=26,name='Green'},{id=27,name='Forest Green'},
        {id=28,name='Foliage Green'},{id=29,name='Olive Drab'},{id=30,name='Dark Earth'},{id=31,name='Desert Tan'},
        {id=32,name='Foliage Tan'},{id=33,name='White'},{id=34,name='Worn Black'},{id=35,name='Worn Graphite'},
        {id=36,name='Worn Silver Gray'},{id=37,name='Worn Silver'},{id=38,name='Worn Blue Silver'},{id=39,name='Worn Shadow Silver'},
        {id=40,name='Worn Red'},{id=41,name='Worn Golden Red'},{id=42,name='Worn Dark Red'},{id=43,name='Worn Orange'},
        {id=44,name='Worn Light Orange'},{id=45,name='Worn Honey Beige'},{id=46,name='Worn Brown'},{id=47,name='Worn Dark Brown'},
        {id=48,name='Worn Straw Beige'},{id=131,name='Worn Taxi Yellow'}
    },
    metals = {
        {id=117,name='Brushed Steel'},{id=118,name='Brushed Black Steel'},{id=119,name='Brushed Aluminum'},
        {id=120,name='Pure Gold'},{id=158,name='Brushed Gold'},{id=120,name='Chrome'}
    },
    util = {
        {id=141,name='Police Car Blue'},{id=134,name='Taxi Yellow'},{id=143,name='Race Yellow'},
        {id=138,name='Military Green'},{id=137,name='Fire Engine Red'},{id=135,name='Orange'}
    }
}

-- Chameleon Colors (pearlescent overlay indices)
-- Applied via SetVehicleExtraColours as pearlescent layer
local ChameleonColors = {
    -- Released chameleon paints
    {name='Anodized Red Pearl',id=161},{name='Anodized Purple Pearl',id=163},{name='Anodized Blue Pearl',id=164},
    {name='Anodized Copper Pearl',id=167},{name='Anodized Gold Pearl',id=170},{name='Green/Blue Flip',id=171},
    {name='Blue/Pink Flip',id=180},{name='Purple/Green Flip',id=183},{name='Burgundy/Green Flip',id=186},
    {name='Red/Orange Flip',id=190},{name='Orange/Purple Flip',id=191},{name='Orange/Blue Flip',id=192},
    {name='Blue Rainbow Flip',id=195},{name='Dark Green Pearl',id=196},{name='Dark Blue Pearl',id=198},
    {name='Dark Purple Pearl',id=199},{name='Oil Slick Pearl',id=200},{name='Off White Pearl',id=205},
    {name='Soft Pink Pearl',id=206},{name='Pastel Yellow Pearl',id=207},{name='Pastel Green Pearl',id=208},
    {name='Baby Blue Pearl',id=209},{name='White Prismatic Pearl',id=211},{name='Purple Prismatic Pearl',id=214},
    {name='Pink Prismatic Pearl',id=215},{name='Red Prismatic Pearl',id=216},{name='Green Prismatic Pearl',id=217},
    {name='Black Prismatic Pearl',id=218},{name='Black Oil Spill Prismatic',id=219},{name='Black Rainbow Prismatic',id=220},
    {name='Dark Holographic',id=221},{name='Light Holographic',id=222}
}

-- Map classic colorId to correct paint finish type for natives SetVehicleModColor_1/2
-- Types (commonly used in FiveM): 0=Metallic, 1=Classic, 2=Pearl, 3=Matte, 4=Metal, 5=Chrome
local function colorIdToPaintType(id)
    id = tonumber(id) or 0
    if id >= 95 and id <= 131 then return 3 end      -- Matte range
    if id >= 132 and id <= 159 then return 4 end     -- Metal range
    return 0                                         -- Metallic for 0-94
end

-- Set finish type (classic/matte/metallic/metals/util) for primary/secondary
local function setFinishForCategory(veh, which, category)
    local map = { classic = 1, metallic = 0, matte = 3, metals = 4, util = 1 }
    local paintType = map[category] or 1
    if which == 'primary' then
        SetVehicleModColor_1(veh, paintType, 0)
    elseif which == 'secondary' then
        SetVehicleModColor_2(veh, paintType, 0)
    end
end

-- Paint helpers to keep channels separated
local function clearOverrides(veh, which)
    if which == 'primary' then
        ClearVehicleCustomPrimaryColour(veh)
    elseif which == 'secondary' then
        ClearVehicleCustomSecondaryColour(veh)
    end
end

local function applyBaseColor(veh, which, idx)
    local p, s = GetVehicleColours(veh)
    if which == 'primary' then
        SetVehicleColours(veh, idx, s or 0)
        -- Reset pearlescent to remove residual bronze sheen
        local _, wheel = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, 0, wheel or 0)
    elseif which == 'secondary' then
        SetVehicleColours(veh, p or 0, idx)
        -- Reset pearlescent to keep base colors accurate
        local _, wheel = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, 0, wheel or 0)
    elseif which == 'wheel' then
        -- Set wheel (rim) color only
        local pearl, wheel = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, pearl or 0, idx)
    end
end

local function applyPearl(veh, idx)
    local pearl, wheel = GetVehicleExtraColours(veh)
    SetVehicleExtraColours(veh, idx, wheel or 0)
end

local function openPaintMenu(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn engine off first', 'error')
        return
    end

    local menu = {
        { header = 'Vehicle Paint Options', isMenuHeader = true },
        {
            header = 'Primary Color',
            txt = 'Choose primary paint color',
            params = {
                event = 'pf-mechanicjob:client:paintTypeSelect',
                args = { vehicle = NetworkGetNetworkIdFromEntity(veh), paintType = 'primary' }
            }
        },
        {
            header = 'Secondary Color',
            txt = 'Choose secondary paint color',
            params = {
                event = 'pf-mechanicjob:client:paintTypeSelect',
                args = { vehicle = NetworkGetNetworkIdFromEntity(veh), paintType = 'secondary' }
            }
        },
        {
            header = 'Pearlescent',
            txt = 'Choose pearlescent color',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = NetworkGetNetworkIdFromEntity(veh), paintType = 'pearlescent', category = 'classic' }
            }
        },
        {
            header = 'Rim Color',
            txt = 'Paint the wheels/rims',
            params = {
                event = 'pf-mechanicjob:client:paintTypeSelect',
                args = { vehicle = NetworkGetNetworkIdFromEntity(veh), paintType = 'wheel' }
            }
        },
        {
            header = 'Chameleon',
            txt = 'Select where to apply chameleon paint',
            params = {
                event = 'pf-mechanicjob:client:chameleonLocationSelect',
                args = { vehicle = NetworkGetNetworkIdFromEntity(veh) }
            }
        },
        { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    }
    exports['pfm-menu']:openMenu(menu)
end

-- Select chameleon location
RegisterNetEvent('pf-mechanicjob:client:chameleonLocationSelect', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local menu = {
        { header = 'Chameleon - Select Location', isMenuHeader = true },
        {
            header = 'Primary',
            txt = 'Apply to primary color',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = 'primary', category = 'chameleon' }
            }
        },
        {
            header = 'Secondary',
            txt = 'Apply to secondary color',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = 'secondary', category = 'chameleon' }
            }
        },
        {
            header = 'Pearlescent',
            txt = 'Apply as pearlescent overlay',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = 'pearlescent', category = 'chameleon' }
            }
        },
        {
            header = 'Wheels',
            txt = 'Apply to rim color (fallback)',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = 'wheel', category = 'chameleon' }
            }
        },
        { header = 'Back', params = { event = 'pf-mechanicjob:client:usePaintcan', args = { vehicle = data.vehicle } } },
        { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    }
    exports['pfm-menu']:openMenu(menu)
end)

-- Select paint category
RegisterNetEvent('pf-mechanicjob:client:paintTypeSelect', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local menu = {
        { header = (data.paintType or 'paint'):gsub('^%l', string.upper) .. ' - Select Category', isMenuHeader = true },
        {
            header = 'Classic',
            txt = 'Standard solid colors',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = data.paintType, category = 'classic' }
            }
        },
        {
            header = 'Matte',
            txt = 'Matte finish colors',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = data.paintType, category = 'matte' }
            }
        },
        {
            header = 'Metallic',
            txt = 'Metallic finish colors',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = data.paintType, category = 'metallic' }
            }
        },
        {
            header = 'Metals',
            txt = 'Brushed metal finishes',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = data.paintType, category = 'metals' }
            }
        },
        {
            header = 'Util',
            txt = 'Utility vehicle colors',
            params = {
                event = 'pf-mechanicjob:client:paintColorPicker',
                args = { vehicle = data.vehicle, paintType = data.paintType, category = 'util' }
            }
        },
        { header = 'Back', params = { event = 'pf-mechanicjob:client:usePaintcan', args = { vehicle = data.vehicle } } },
        { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    }
    exports['pfm-menu']:openMenu(menu)
end)

-- Color picker
RegisterNetEvent('pf-mechanicjob:client:paintColorPicker', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local paintType = data.paintType or 'primary'
    local category = data.category or 'classic'
    
    local menu = {
        { header = paintType:gsub('^%l', string.upper) .. ' - ' .. category:gsub('^%l', string.upper), isMenuHeader = true }
    }

    if category == 'chameleon' then
        for _, color in ipairs(ChameleonColors) do
            menu[#menu+1] = {
                header = color.name,
                txt = 'Color-shifting paint',
                params = {
                    event = 'pf-mechanicjob:client:applyPaint',
                    args = {
                        vehicle = data.vehicle,
                        paintType = paintType,
                        colorType = 'chameleon',
                        colorId = color.id
                    }
                }
            }
        end
    else
        -- All other categories use the PaintColors table
        local colorList = PaintColors[category] or {}
        for _, color in ipairs(colorList) do
            menu[#menu+1] = {
                header = color.name,
                txt = 'Click to apply',
                params = {
                    event = 'pf-mechanicjob:client:applyPaint',
                    args = {
                        vehicle = data.vehicle,
                        paintType = paintType,
                        colorType = 'classic',
                        colorId = color.id,
                        finish = category
                    }
                }
            }
        end
    end

    menu[#menu+1] = { header = 'Back', params = { event = 'pf-mechanicjob:client:paintTypeSelect', args = { vehicle = data.vehicle, paintType = paintType } } }
    menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(menu)
end)

-- Spray animation with particle effects
local sprayCanObj = nil
local function startSprayAnimation(ped, duration)
    local dict = 'switch@franklin@lamar_tagging_wall'
    local anim = 'lamar_tagging_wall_loop_franklin'
    
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
    
    -- Create spray can prop
    local canModel = `prop_cs_spray_can`
    RequestModel(canModel)
    while not HasModelLoaded(canModel) do Wait(0) end
    
    sprayCanObj = CreateObject(canModel, 0, 0, 0, true, true, true)
    local boneIndex = GetPedBoneIndex(ped, 28422)
    AttachEntityToEntity(sprayCanObj, ped, boneIndex, 0.05, 0.02, -0.02, -90.0, 0.0, 0.0, true, true, false, true, 1, true)
    
    -- Play animation
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
    
    -- Particle effect
    local ptfxDict = 'core'
    local ptfxName = 'ent_amb_spray_paint'
    RequestNamedPtfxAsset(ptfxDict)
    while not HasNamedPtfxAssetLoaded(ptfxDict) do Wait(0) end
    
    UseParticleFxAssetNextCall(ptfxDict)
    local ptfx = StartParticleFxLoopedOnEntity(ptfxName, sprayCanObj, 0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 1.5, false, false, false)
    
    -- Wait for duration
    Wait(duration)
    
    -- Cleanup
    if ptfx then StopParticleFxLooped(ptfx, false) end
    if sprayCanObj then DeleteEntity(sprayCanObj) sprayCanObj = nil end
    ClearPedTasks(ped)
end

-- Apply paint with spray animation
RegisterNetEvent('pf-mechanicjob:client:applyPaint', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn engine off first', 'error')
        return
    end

    -- Ensure mod kit is set before applying any paint changes
    SetVehicleModKit(veh, 0)

    local ped = PlayerPedId()
    local paintDuration = 12000 -- 12 seconds spray animation
    
    -- Start spray animation in separate thread
    CreateThread(function()
        startSprayAnimation(ped, paintDuration)
    end)
    
    if not DoProgress('Spray painting vehicle...', paintDuration) then
        if sprayCanObj then DeleteEntity(sprayCanObj) sprayCanObj = nil end
        ClearPedTasks(ped)
        QBCore.Functions.Notify('Paint job cancelled', 'error')
        return
    end

    -- Apply paint locally (must be done before server event)
    local paintType = data.paintType or 'primary'
    if data.colorType == 'classic' then
        local colorId = tonumber(data.colorId) or 0
        if paintType == 'primary' or paintType == 'secondary' then
            -- Set finish (classic/matte/metallic/metals/util)
            if data.finish then setFinishForCategory(veh, paintType, data.finish) end
            clearOverrides(veh, paintType)
            applyBaseColor(veh, paintType, colorId)
            if Config.Debug then
                local p,s = GetVehicleColours(veh)
                print(string.format('[CLIENT PAINT] %s classic idx=%d applied (p=%d,s=%d)', paintType, colorId, p or -1, s or -1))
            end
        elseif paintType == 'pearlescent' then
            applyPearl(veh, colorId)
            if Config.Debug then
                local pearl,wheel = GetVehicleExtraColours(veh)
                print(string.format('[CLIENT PAINT] Pearl idx=%d applied (pearl=%d,wheel=%d)', colorId, pearl or -1, wheel or -1))
            end
        elseif paintType == 'wheel' then
            applyBaseColor(veh, 'wheel', colorId)
            if Config.Debug then
                local _, wheel = GetVehicleExtraColours(veh)
                print(string.format('[CLIENT PAINT] Wheel color idx=%d applied (wheel=%d)', colorId, wheel or -1))
            end
        end
    elseif data.colorType == 'chameleon' then
        -- Chameleon can be applied to primary, secondary, or pearlescent
        local colorId = tonumber(data.colorId) or 161
        if paintType == 'primary' or paintType == 'secondary' then
            if data.finish then setFinishForCategory(veh, paintType, data.finish) end
            clearOverrides(veh, paintType)
            applyBaseColor(veh, paintType, colorId)
            if Config.Debug then
                local p,s = GetVehicleColours(veh)
                print(string.format('[CLIENT PAINT] %s chameleon idx=%d applied (p=%d,s=%d)', paintType, colorId, p or -1, s or -1))
            end
        elseif paintType == 'pearlescent' then
            applyPearl(veh, colorId)
            if Config.Debug then
                local pearl,wheel = GetVehicleExtraColours(veh)
                print(string.format('[CLIENT PAINT] Chameleon pearl idx=%d applied (pearl=%d,wheel=%d)', colorId, pearl or -1, wheel or -1))
            end
        elseif paintType == 'wheel' then
            -- Wheels don't support chameleon; apply closest base index (use same id)
            applyBaseColor(veh, 'wheel', colorId)
            if Config.Debug then
                local _, wheel = GetVehicleExtraColours(veh)
                print(string.format('[CLIENT PAINT] Wheel(chameleon fallback) idx=%d applied (wheel=%d)', colorId, wheel or -1))
            end
        end
    end

    -- Server-side: consume item and sync to other players
    TriggerServerEvent('pf_mech:server:applyPaint', data)

    QBCore.Functions.Notify('Paint applied successfully', 'success')
end)

-- Event to open paintcan menu (for item use)
RegisterNetEvent('pf-mechanicjob:client:usePaintcan', function(data)
    local veh = data and data.vehicle and NetworkGetEntityFromNetworkId(data.vehicle) or nearbyVeh(6.0)
    if veh == 0 then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    openPaintMenu(veh)
end)

-- NEW: unified item -> modTypes mapping (single or multi)
local CosmeticItemMap = {
    spoiler       = {0},
    bumper        = {1,2},
    vehicle_bumper= {1,2},
    skirts        = {3},
    exhaust       = {4},
    rollcage      = {5},
    hood          = {7},
    roof          = {10},
    externals     = {6,8,9,10,45},
    internals     = {28,29,30,31,32,33,34,35,36,37,38,39,40},
    livery        = {46},
    customplate   = {25,48},
    seat          = {31},
    horn          = {14},
    rims          = {23},
}

-- NEW: open menu for a specific cosmetic item (direct variants)
RegisterNetEvent('pf-mechanicjob:client:openItemModMenu', function(itemName)
    itemName = tostring(itemName or '')
    if itemName == '' then return end
    local ped = PlayerPedId()
    local veh = nearbyVeh(6.0)
    if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error') return end
    if GetIsVehicleEngineRunning(veh) then QBCore.Functions.Notify('Turn engine off first','error') return end
    SetVehicleModKit(veh, 0)

    -- tint special case
    if itemName == 'tint_supplies' then
        openTintPicker(veh)
        return
    end

    local modTypes = CosmeticItemMap[itemName]
    if not modTypes then
        QBCore.Functions.Notify('Unsupported cosmetic item','error')
        return
    end

    local menu = {
        { header = (itemName:gsub('_',' ')):gsub('^%l', string.upper) .. ' Options', isMenuHeader = true }
    }

    for _, modType in ipairs(modTypes) do
        local count = GetNumVehicleMods(veh, modType)
        -- For toggle mods (none of these currently except horn maybe), still show status
        if count == 0 then
            -- Skip empty modType silently
        else
            -- Add category separator if multi-type
            if #modTypes > 1 then
                menu[#menu+1] = { header = '--- '..readableModName(modType)..' ---', isMenuHeader = true }
            end
            for i=0,count-1 do
                local textLabel = GetModTextLabel(veh, modType, i)
                local nice = textLabel and GetLabelText(textLabel)
                if not nice or nice == 'NULL' then
                    nice = ('Option %d'):format(i+1)
                end
                menu[#menu+1] = {
                    header = nice,
                    params = {
                        event = 'pf-mechanicjob:client:applyCosmeticModSingle',
                        args = {
                            vehicle = NetworkGetNetworkIdFromEntity(veh),
                            item = itemName,
                            modType = modType,
                            modIndex = i
                        }
                    }
                }
            end
        end
    end

    menu[#menu+1] = { header = 'Close', params = { event='qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(menu)
end)

-- NEW: apply selected cosmetic variant (consume item then apply)
RegisterNetEvent('pf-mechanicjob:client:applyCosmeticModSingle', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if veh == 0 or not DoesEntityExist(veh) then QBCore.Functions.Notify('Vehicle not found','error') return end
    if GetIsVehicleEngineRunning(veh) then QBCore.Functions.Notify('Turn engine off first','error') return end
    SetVehicleModKit(veh, 0)

    RequestAnimDict('mini@repair')
    while not HasAnimDictLoaded('mini@repair') do Wait(0) end
    TaskPlayAnim(PlayerPedId(), 'mini@repair', 'fixing_a_ped', 8.0, -8.0, -1, 49, 0, false, false, false)

    if not DoProgress('Installing '..(data.item or 'mod')..'...', Config.ActionTimes.setMod or 4500, 'mini@repair', 'fixing_a_ped') then
        ClearPedTasks(PlayerPedId())
        QBCore.Functions.Notify('Installation cancelled','error')
        return
    end
    ClearPedTasks(PlayerPedId())

    TriggerServerEvent('pf_mech:server:applyMod', {
        vehicle  = NetworkGetNetworkIdFromEntity(veh),
        item     = data.item,
        modType  = data.modType,
        modIndex = data.modIndex
    })
    QBCore.Functions.Notify('Modification applied','success')
end)

-- REPLACE cosmetic use dispatcher to call new menu (direct)
RegisterNetEvent('pf-mechanicjob:client:usePart', function(item)
    local name = type(item) == 'string' and item or (item and item.name)
    if not name then return end
    if name == 'tint_supplies' then
        local veh = nearbyVeh(6.0)
        if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error') return end
        if GetIsVehicleEngineRunning(veh) then QBCore.Functions.Notify('Turn engine off first','error') return end
        openTintPicker(veh); return
    end
    if CosmeticItemMap[name] then
        TriggerEvent('pf-mechanicjob:client:openItemModMenu', name)
    else
        if Config.Debug then print('[COSMETIC] Unknown cosmetic item used: '..tostring(name)) end
    end
end)

-- /preview should open the original preview menu provided by client/preview.lua
RegisterCommand('preview', function()
    TriggerEvent('pf_mech:preview:open')
end, false)

-- Optional external trigger to open the same original preview menu
RegisterNetEvent('pf_mech:preview:openMenu', function()
    TriggerEvent('pf_mech:preview:open')
end)

-- Help command: show NOS controls quickly
RegisterCommand('noshelp', function()
  QBCore.Functions.Notify('NOS: Hold Left Shift to boost, Left Ctrl to purge', 'primary', 5000)
  QBCore.Functions.Notify('Switch boost level with Arrow Up/Down', 'primary', 5000)
  QBCore.Functions.Notify('Switch purge style with Page Up/Page Down', 'primary', 5000)
end, false)

-- ================== Sync Events for Tint & Paint ==================
-- Sync tint application to all clients
RegisterNetEvent('pf_mech:client:syncVehicleTint', function(netId, tintLevel)
    local veh = NetworkGetEntityFromNetworkId(netId or 0)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        tintLevel = tonumber(tintLevel) or 0
        SetVehicleWindowTint(veh, tintLevel)
        if Config.Debug then
            print(string.format('[SYNC TINT] Applied level %d to vehicle netId %d', tintLevel, netId))
        end
    end
end)

-- Sync paint application to all clients
RegisterNetEvent('pf_mech:client:syncVehiclePaint', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)

    local paintType = data.paintType or 'primary'
    local colorType = data.colorType or 'classic'
    local primary, secondary = GetVehicleColours(veh)

    if colorType == 'classic' then
        local colorId = tonumber(data.colorId) or 0
        if paintType == 'primary' or paintType == 'secondary' then
            if data.finish then setFinishForCategory(veh, paintType, data.finish) end
            clearOverrides(veh, paintType)
            applyBaseColor(veh, paintType, colorId)
        elseif paintType == 'pearlescent' then
            applyPearl(veh, colorId)
        elseif paintType == 'wheel' then
            applyBaseColor(veh, 'wheel', colorId)
        end
        if Config.Debug then
            print(string.format('[SYNC PAINT] Applied %s classic color %d to vehicle netId %d', paintType, colorId, data.vehicle))
        end
    elseif colorType == 'chameleon' then
        -- Chameleon can be applied to primary, secondary, or pearlescent
        local colorId = tonumber(data.colorId) or 161
        if paintType == 'primary' or paintType == 'secondary' then
            if data.finish then setFinishForCategory(veh, paintType, data.finish) end
            clearOverrides(veh, paintType)
            applyBaseColor(veh, paintType, colorId)
            if Config.Debug then
                print(string.format('[SYNC PAINT] %s chameleon idx=%d applied to vehicle netId %d', paintType, colorId, data.vehicle))
            end
        elseif paintType == 'pearlescent' then
            applyPearl(veh, colorId)
            if Config.Debug then
                print(string.format('[SYNC PAINT] Chameleon pearl idx=%d applied to vehicle netId %d', colorId, data.vehicle))
            end
        elseif paintType == 'wheel' then
            applyBaseColor(veh, 'wheel', colorId)
            if Config.Debug then
                print(string.format('[SYNC PAINT] Wheel(chameleon fallback) idx=%d applied to vehicle netId %d', colorId, data.vehicle))
            end
        end
    end
end)

-- ============================================================================
-- REPAIR KIT HANDLER - Emergency repair kit for quick fixes
-- ============================================================================
RegisterNetEvent('pf-mechanicjob:client:useRepairKit', function()
    local ped = PlayerPedId()
    local veh
    
    -- Get vehicle: either the one player is in, or the closest one
    if IsPedInAnyVehicle(ped, false) then
        veh = GetVehiclePedIsIn(ped, false)
    else
        local pos = GetEntityCoords(ped)
        veh = GetClosestVehicle(pos.x, pos.y, pos.z, 6.0, 0, 70)
    end
    
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    -- Repair kit is an emergency item - fix one part quickly
    local state = Entity(veh).state
    local partDamage = state.partDamage or {}
    
    -- Find the most damaged part
    local worstPart = nil
    local worstDamage = 0
    
    for partKey, damage in pairs(partDamage) do
        if tonumber(damage) > worstDamage then
            worstDamage = tonumber(damage)
            worstPart = partKey
        end
    end
    
    if not worstPart or worstDamage < 1 then
        QBCore.Functions.Notify('Vehicle does not need repairs', 'error')
        return
    end
    
    -- Use repair kit to fix worst damaged part
    QBCore.Functions.TriggerCallback('pf_mech:server:attemptRepair', function(success, msg)
        if success then
            QBCore.Functions.Notify('Emergency repair completed', 'success')
        else
            QBCore.Functions.Notify(msg or 'Repair failed', 'error')
        end
    end, GetNetworkIdFromEntity(veh), worstPart, 1)
end)