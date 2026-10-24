local vehicles = {
  'rox_dandy_fuzion',
  'rox_dandy_xse50',
  'rox_dandy_zrg60',
  'rcfdtruk',
  'roxbus',
  'roxbus2',
  'roxcpd_modrn_scout',
  'roxpdconada3',
  'ambfdtower',
  'roxbuffalo4',
  'unbuffalo4',
  'cghelir',
  'cgpredator',
  'cgdinghyr',
  'roxlguardcara',
  'gststn1r',
  'roxtaxi3',
  'roxterl300',
  'roxvivantaxi',
  'roxtaxi',
  'roxtaxi2',
  'roxissimedic',
  'roxgrang2fdcom',
  'roxyosfdbrush',
  'prangerbison',
  'roxv450ambu',
  'roxe109lguard',
  'roxrumpofirdep',
  'roxsherifrumpv',
  'roxcpdbufs',
  'raidcoprx',
  'roadkillerrt',
  'gstl3001',
  'gstl3002',
  'raidenz',
  'caracaranr',
  'marbella',
  'marbcoprx',
  'marbsheriffrx',
  'marbtaxirx',
  'roxelecscoot',
  'roxcoach3',
  'roxsheriffgres',
  'AMBROXFIREENG1',
  'ambroxcguardv',
  'roxseasharklg',
  'amb_rox_sheriff',
  'amb_rox_ambu',
  'amb_rox_towtruck',
  'amb_rox_trash',
  'amb_rox_sheriffb',
  'roxpolmav',
  'amb_rox_sheriff2',
  'amb_rox_swat',
  'roxduneprfir',
  'roxsandkparkr'
}

local captureEndpoint = 'http://127.0.0.1:3217/capture'
local vehicleHeading = 35.0
local cameraSide = -1.0
local isCapturing = false

local function notify(message)
  TriggerEvent('chat:addMessage', {
    color = { 34, 219, 191 },
    args = { 'Roxwood Shots', message }
  })
end

local function requestModel(modelHash)
  RequestModel(modelHash)
  local deadline = GetGameTimer() + 10000
  while not HasModelLoaded(modelHash) and GetGameTimer() < deadline do
    Wait(50)
  end
  return HasModelLoaded(modelHash)
end

local function focusVehicle(vehicle)
  SetVehicleOnGroundProperly(vehicle)
  FreezeEntityPosition(vehicle, true)
  SetEntityHeading(vehicle, vehicleHeading)
  SetVehicleDirtLevel(vehicle, 0.0)
  SetVehicleDoorsLocked(vehicle, 2)
  SetVehicleLights(vehicle, 2)
end

local function createCamera(vehicle)
  local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
  local length = math.max(1.0, maxDim.y - minDim.y)
  local width = math.max(1.0, maxDim.x - minDim.x)
  local height = math.max(1.0, maxDim.z - minDim.z)
  local sideOffset = cameraSide * (width * 1.35 + 1.4)
  local frontOffset = length * 1.35 + 2.8
  local cameraHeight = height * 0.72
  local target = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, length * 0.12, height * 0.34)
  local cameraCoords = GetOffsetFromEntityInWorldCoords(vehicle, sideOffset, frontOffset, cameraHeight)
  local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

  SetCamCoord(cam, cameraCoords.x, cameraCoords.y, cameraCoords.z)
  PointCamAtCoord(cam, target.x, target.y, target.z)
  SetCamFov(cam, 34.0)
  SetCamActive(cam, true)
  RenderScriptCams(true, true, 350, true, true)
  return cam
end

local function destroyCamera(cam)
  RenderScriptCams(false, true, 250, true, true)
  DestroyCam(cam, false)
end

local function captureVehicle(modelName, index, total)
  local modelHash = joaat(modelName)
  if not IsModelInCdimage(modelHash) or not IsModelAVehicle(modelHash) then
    notify(('Skipping %s; model is not available.'):format(modelName))
    return
  end

  if not requestModel(modelHash) then
    notify(('Skipping %s; model did not load.'):format(modelName))
    return
  end

  local playerPed = PlayerPedId()
  local playerCoords = GetEntityCoords(playerPed)
  local spawnCoords = vector3(playerCoords.x, playerCoords.y + 8.0, playerCoords.z)
  local vehicle = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, vehicleHeading, false, false)
  focusVehicle(vehicle)
  Wait(700)

  local cam = createCamera(vehicle)
  Wait(650)

  notify(('Capturing %s (%d/%d)'):format(modelName, index, total))
  exports['screenshot-basic']:requestScreenshotUpload(captureEndpoint .. '?model=' .. modelName, 'file', {
    encoding = 'jpg',
    quality = 0.92
  }, function(response)
    if response and response ~= '' then
      print(('[Roxwood Shots] %s: %s'):format(modelName, response))
    end
  end)

  Wait(1200)
  destroyCamera(cam)
  DeleteEntity(vehicle)
  SetModelAsNoLongerNeeded(modelHash)
end

RegisterCommand('roxvehshots', function()
  if isCapturing then
    notify('Already capturing vehicle snapshots.')
    return
  end

  if GetResourceState('screenshot-basic') ~= 'started' then
    notify('screenshot-basic must be installed and started first.')
    return
  end

  isCapturing = true
  notify(('Starting %d vehicle snapshots. Keep the client focused.'):format(#vehicles))

  CreateThread(function()
    for index, modelName in ipairs(vehicles) do
      captureVehicle(modelName, index, #vehicles)
      Wait(350)
    end
    isCapturing = false
    notify('Finished vehicle snapshot loop.')
  end)
end, false)

RegisterCommand('roxvehshot', function(_, args)
  if isCapturing then
    notify('Already capturing vehicle snapshots.')
    return
  end

  if GetResourceState('screenshot-basic') ~= 'started' then
    notify('screenshot-basic must be installed and started first.')
    return
  end

  local modelName = args[1] or vehicles[1]
  isCapturing = true
  CreateThread(function()
    captureVehicle(modelName, 1, 1)
    isCapturing = false
    notify(('Finished test snapshot for %s.'):format(modelName))
  end)
end, false)
