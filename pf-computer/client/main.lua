-- Framework Detection
local QBCore = nil
local ESX = nil

if Config.Framework == 'qbcore' then
    QBCore = exports['pfm-core']:GetCoreObject()
elseif Config.Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
end

-- Variables
local isComputerOpen = false
local currentComputer = nil
local currentComputerProfile = 'default'
local businessBlips = {}

local WEATHER_HASH_TO_KEY = {
    [GetHashKey('EXTRASUNNY')] = 'sunny',
    [GetHashKey('CLEAR')] = 'clear',
    [GetHashKey('CLEARING')] = 'partly_cloudy',
    [GetHashKey('CLOUDS')] = 'cloudy',
    [GetHashKey('OVERCAST')] = 'cloudy',
    [GetHashKey('SMOG')] = 'cloudy',
    [GetHashKey('FOGGY')] = 'cloudy',
    [GetHashKey('RAIN')] = 'light_rain',
    [GetHashKey('THUNDER')] = 'storm',
    [GetHashKey('XMAS')] = 'snow',
    [GetHashKey('SNOW')] = 'snow',
    [GetHashKey('SNOWLIGHT')] = 'snow',
    [GetHashKey('BLIZZARD')] = 'snow'
}

local function GetCurrentWeatherKey()
    local weatherA, weatherB, blend = GetWeatherTypeTransition()
    local chosenHash = weatherA
    if weatherB and blend and blend >= 0.5 then
        chosenHash = weatherB
    end

    return WEATHER_HASH_TO_KEY[chosenHash] or 'partly_cloudy'
end

local function SendEnvironmentSync()
    SendNUIMessage({
        action = 'environmentSync',
        weather = GetCurrentWeatherKey(),
        gameHour = GetClockHours(),
        gameMinute = GetClockMinutes()
    })
end

local function IsHashInList(hash, list)
    if type(list) ~= 'table' then return false end
    for _, value in ipairs(list) do
        if tonumber(value) == tonumber(hash) then
            return true
        end
    end
    return false
end

local function IsNearMayorCoords(coords)
    local mayorCfg = Config.MayorComputer
    if not mayorCfg or type(mayorCfg.Coords) ~= 'table' then
        return false
    end

    local radius = tonumber(mayorCfg.CoordRadius) or 2.0
    for _, point in ipairs(mayorCfg.Coords) do
        if point and point.x and point.y and point.z then
            local dist = #(coords - vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0))
            if dist <= radius then
                return true
            end
        end
    end

    return false
end

local function ResolveComputerProfile(entity)
    local mayorCfg = Config.MayorComputer
    if not mayorCfg or mayorCfg.Enabled ~= true then
        return 'default'
    end

    local mode = tostring(mayorCfg.DetectionMode or 'prop'):lower()
    local pedCoords = GetEntityCoords(PlayerPedId())

    if mode == 'prop' and entity and DoesEntityExist(entity) then
        local model = GetEntityModel(entity)
        if IsHashInList(model, mayorCfg.PropModels) then
            return 'mayor'
        end
    end

    if mode == 'coords' then
        local probeCoords = pedCoords
        if entity and DoesEntityExist(entity) then
            probeCoords = GetEntityCoords(entity)
        end

        if IsNearMayorCoords(probeCoords) then
            return 'mayor'
        end
    elseif mayorCfg.UseCoordsFallback == true then
        local fallbackCoords = pedCoords
        if entity and DoesEntityExist(entity) then
            fallbackCoords = GetEntityCoords(entity)
        end

        if IsNearMayorCoords(fallbackCoords) then
            return 'mayor'
        end
    end

    return 'default'
end

local function BuildComputerStateKey(entity, profile)
    local baseProfile = tostring(profile or 'default')
    if not entity or not DoesEntityExist(entity) then
        return ('profile:%s:fallback'):format(baseProfile)
    end

    local coords = GetEntityCoords(entity)
    local model = GetEntityModel(entity)
    if not coords then
        return ('profile:%s:model:%s'):format(baseProfile, tostring(model))
    end

    local x = math.floor((coords.x + 0.0) * 10 + 0.5) / 10
    local y = math.floor((coords.y + 0.0) * 10 + 0.5) / 10
    local z = math.floor((coords.z + 0.0) * 10 + 0.5) / 10

    return ('profile:%s:model:%s:pos:%s,%s,%s'):format(baseProfile, tostring(model), tostring(x), tostring(y), tostring(z))
end

-- Promise-based server callbacks
local pending = {}
local requestId = 0

local function requestServer(action, payload)
    requestId = requestId + 1
    local id = requestId
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('pf-computer:server:callback', id, action, payload or {})
    return Citizen.Await(p)
end

RegisterNetEvent('pf-computer:client:callback', function(id, result)
    local p = pending[id]
    if not p then
        return
    end
    pending[id] = nil
    p:resolve(result)
end)

-- NUI Callbacks
local function handleCallback(action)
    return function(data, cb)
        local result = requestServer(action, data or {})
        cb(result or { ok = false, error = 'no_response' })
    end
end

-- (mail, calendar, bills and documents are pf-citizen's platform apps now; the dark-web market is gone)
RegisterNUICallback('pc:sendEmail', handleCallback('emails:send'))
RegisterNUICallback('pc:getChatRooms', handleCallback('darkweb:chat:rooms'))
RegisterNUICallback('pc:joinChatRoom', handleCallback('darkweb:chat:join'))
RegisterNUICallback('pc:postChatMessage', handleCallback('darkweb:chat:post'))
RegisterNUICallback('pc:deleteChatMessage', handleCallback('darkweb:chat:delete'))
RegisterNUICallback('pc:security:getConfig', handleCallback('security:config:get'))
RegisterNUICallback('pc:security:checkHackTool', handleCallback('security:hack:checkTool'))
RegisterNUICallback('pc:security:detectHackTool', handleCallback('security:hack:detectTool'))
RegisterNUICallback('pc:security:adminRecovery', handleCallback('security:admin:recovery'))
RegisterNUICallback('pc:devices:getPhoneImages', handleCallback('devices:phoneImages'))
RegisterNUICallback('pc:getAnnouncements', handleCallback('gov:announcements:list'))
RegisterNUICallback('pc:createAnnouncement', handleCallback('gov:announcements:create'))
RegisterNUICallback('pc:getGovLaws', handleCallback('gov:laws:list'))
RegisterNUICallback('pc:getGovTaxes', handleCallback('gov:taxes:list'))
RegisterNUICallback('pc:getGovWebsiteState', handleCallback('gov:website:get'))
RegisterNUICallback('pc:browser:getConfig', handleCallback('browser:config:get'))
RegisterNUICallback('pc:browser:ask', handleCallback('browser:assistant:query'))
RegisterNUICallback('pc:browser:getDomains', handleCallback('browser:domains:list'))
RegisterNUICallback('pc:browser:buyDomain', handleCallback('browser:domain:buy'))
RegisterNUICallback('pc:browser:getWebsite', handleCallback('browser:website:get'))
RegisterNUICallback('pc:browser:saveWebsite', handleCallback('browser:website:save'))
RegisterNUICallback('pc:browser:transferDomain', handleCallback('browser:domain:transfer'))
RegisterNUICallback('pc:gov:bootstrap', handleCallback('gov:cityhall:bootstrap'))
RegisterNUICallback('pc:gov:law:setDisplay', handleCallback('gov:laws:setDisplay'))
RegisterNUICallback('pc:gov:tax:update', handleCallback('gov:taxes:update'))
RegisterNUICallback('pc:gov:tax:toggle', handleCallback('gov:taxes:toggle'))
RegisterNUICallback('pc:gov:budget:update', handleCallback('gov:budgets:update'))
RegisterNUICallback('pc:gov:budget:upgrade', handleCallback('gov:budgets:upgrade'))
RegisterNUICallback('pc:gov:budget:uninstallUpgrade', handleCallback('gov:budgets:uninstallUpgrade'))
RegisterNUICallback('pc:gov:utility:disconnect', handleCallback('gov:utilities:disconnect'))
RegisterNUICallback('pc:gov:utility:restore', handleCallback('gov:utilities:restore'))
RegisterNUICallback('pc:gov:fine:issue', handleCallback('gov:fines:issue'))

-- Business Manager, Order Supplies and the Job Board are pf-devices apps now (html/apps/*.js): their
-- calls go through pf-devices to server/devices.lua, so the computer has no callbacks of its own for them.

-- The character's desktop layout and lock screen on this computer, kept on the server (server/profiles.lua)
RegisterNUICallback('pc:profile:get', handleCallback('profile:get'))
RegisterNUICallback('pc:profile:saveLayout', handleCallback('profile:layout:save'))
RegisterNUICallback('pc:profile:resetLayout', handleCallback('profile:layout:reset'))
RegisterNUICallback('pc:lock:state', handleCallback('security:lock:state'))
RegisterNUICallback('pc:lock:settings', handleCallback('security:lock:settings'))
RegisterNUICallback('pc:lock:lock', handleCallback('security:lock:lock'))
RegisterNUICallback('pc:lock:unlock', handleCallback('security:lock:unlock'))
RegisterNUICallback('pc:lock:breach', handleCallback('security:lock:breach'))
RegisterNUICallback('pc:lock:exitLockdown', handleCallback('security:lock:exitLockdown'))
RegisterNUICallback('pc:lock:reset', handleCallback('security:lock:reset'))

-- The boss places the business's delivery point with a preview truck. Started by the server from the
-- Business Manager / Order Supplies apps (server/devices.lua checks the boss first; the device is put
-- away before this runs); the position is checked again when it is saved (setDeliveryLocation).
local placingDelivery = false
RegisterNetEvent('pf-computer:client:placeDeliveryPoint', function()
    if placingDelivery then return end
    placingDelivery = true
    Wait(300)   -- the tablet or computer closes first
    SetNuiFocus(false, false)
    if QBCore then QBCore.Functions.Notify('Move the truck to the delivery point: [E] confirm, [X] cancel', 'primary') end
    local ok, err = pcall(SetDeliveryLocationClient)
    if not ok then print(('^1[pf-computer]^7 delivery point placement failed: %s'):format(tostring(err))) end
    placingDelivery = false
end)

function SetDeliveryLocationClient()
    local QBCore = exports['pfm-core']:GetCoreObject()
    
    -- Spawn phantom truck
    local truckModel = 'mule'
    local hash = GetHashKey(truckModel)
    
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(10)
    end
    
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    local phantomTruck = CreateVehicle(hash, coords.x, coords.y + 5.0, coords.z, heading, false, false)
    SetEntityAlpha(phantomTruck, 150, false) -- Semi-transparent
    SetEntityCollision(phantomTruck, false, false)
    FreezeEntityPosition(phantomTruck, true)
    
    local textShown = false
    local confirmed = false
    local cancelled = false
    
    -- Movement thread
    CreateThread(function()
        while not confirmed and not cancelled do
            Wait(0)
            
            -- Get player rotation and move truck with player
            local pedPos = GetEntityCoords(ped)
            local pedHeading = GetEntityHeading(ped)
            
            -- Position truck in front of player
            local forward = GetEntityForwardVector(ped)
            local truckPos = vector3(
                pedPos.x + forward.x * 5.0,
                pedPos.y + forward.y * 5.0,
                pedPos.z
            )
            
            SetEntityCoords(phantomTruck, truckPos.x, truckPos.y, truckPos.z, false, false, false, false)
            SetEntityHeading(phantomTruck, pedHeading)
            
            -- Draw help text
            if not textShown then
                textShown = true
                exports['pfm-core']:DrawText('[E] Confirm Location | [X] Cancel', 'left')
            end
            
            -- Check for E key to confirm
            if IsControlJustPressed(0, 38) then -- E
                confirmed = true
                local finalCoords = GetEntityCoords(phantomTruck)
                local finalHeading = GetEntityHeading(phantomTruck)
                
                -- Save to server
                TriggerServerEvent('pf-computer:server:setDeliveryLocation', {
                    x = finalCoords.x,
                    y = finalCoords.y,
                    z = finalCoords.z,
                    w = finalHeading
                })
                
                QBCore.Functions.Notify('Delivery location set!', 'success')
            end
            
            -- Check for X key to cancel
            if IsControlJustPressed(0, 73) then -- X
                cancelled = true
                QBCore.Functions.Notify('Cancelled', 'error')
            end
        end
    end)
    
    -- Wait for confirmation or cancellation
    while not confirmed and not cancelled do
        Wait(100)
    end
    
    -- Cleanup
    DeleteEntity(phantomTruck)
    SetModelAsNoLongerNeeded(hash)
    exports['pfm-core']:HideText()
    
    return confirmed
end

RegisterNUICallback('pc:ping', function(_, cb)
    cb({ ok = true })
end)

-- Get Player Data
-- Collect external programs from other resources
local function ProgramAllowedForProfile(program, profile)
    if type(program) ~= 'table' then
        return false
    end

    local requiredProfile = program.computerProfile or program.requiredComputerProfile
    if type(requiredProfile) == 'string' and requiredProfile ~= '' then
        return requiredProfile == profile
    end

    if type(program.computerProfiles) == 'table' then
        for _, p in ipairs(program.computerProfiles) do
            if tostring(p) == tostring(profile) then
                return true
            end
        end
        return false
    end

    return true
end

local function GetExternalPrograms(profile)
    local activeProfile = tostring(profile or currentComputerProfile or 'default')
    local programs = {}
    local numResources = GetNumResources()
    
    for i = 0, numResources - 1 do
        local resName = GetResourceByFindIndex(i)
        if GetResourceState(resName) == 'started' then
            -- Check if resource exports GetComputerPrograms
            local success, result = pcall(function()
                return exports[resName]:GetComputerPrograms()
            end)
            
            if success and result and type(result) == 'table' then
                for _, program in ipairs(result) do
                    if ProgramAllowedForProfile(program, activeProfile) then
                        program.resource = resName
                        table.insert(programs, program)
                    end
                end
            end
        end
    end
    
    return programs
end

RegisterNUICallback('pc:getExternalPrograms', function(data, cb)
    local profile = type(data) == 'table' and data.profile or currentComputerProfile
    local programs = GetExternalPrograms(profile)
    cb({ ok = true, data = programs })
end)

RegisterNUICallback('pc:getPlayerData', function(_, cb)
    if Config.Framework == 'qbcore' and QBCore then
        local PlayerData = QBCore.Functions.GetPlayerData()
        cb({
            ok = true,
            data = {
                citizenid = PlayerData.citizenid,
                name = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname,
                job = PlayerData.job.name,
                jobLabel = PlayerData.job.label,
                grade = PlayerData.job.grade.level,
                gradeLabel = PlayerData.job.grade.name,
                phone = PlayerData.charinfo.phone,
                cash = PlayerData.money.cash,
                bank = PlayerData.money.bank
            }
        })
    elseif Config.Framework == 'esx' and ESX then
        local PlayerData = ESX.GetPlayerData()
        cb({
            ok = true,
            data = {
                citizenid = PlayerData.identifier,
                name = PlayerData.name or (PlayerData.firstName .. ' ' .. PlayerData.lastName),
                job = PlayerData.job.name,
                jobLabel = PlayerData.job.label,
                grade = PlayerData.job.grade,
                gradeLabel = PlayerData.job.grade_label,
                phone = PlayerData.phone or 'Unknown',
                cash = PlayerData.money or 0,
                bank = PlayerData.accounts and PlayerData.accounts.bank or 0
            }
        })
    else
        cb({ ok = false, error = 'Framework not initialized' })
    end
end)

RegisterNUICallback('pc:getPlayerCoords', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    cb({
        ok = true,
        data = { x = coords.x, y = coords.y, z = coords.z }
    })
end)

RegisterNUICallback('pc:setWaypoint', function(data, cb)
    local x = tonumber(data and data.x)
    local y = tonumber(data and data.y)
    if not x or not y then
        cb({ ok = false, error = 'invalid_coords' })
        return
    end

    SetNewWaypoint(x + 0.0, y + 0.0)
    cb({ ok = true })
end)

-- Close NUI
RegisterNUICallback('pc:close', function(_, cb)
    CloseComputer()
    cb({ ok = true })
end)

RegisterNetEvent('pf-computer:client:updateBusinessBlip', function(payload)
    if type(payload) ~= 'table' then return end

    local businessId = payload.businessId
    if not businessId then return end

    if not payload.coords then return end

    local existing = businessBlips[businessId]
    if existing and DoesBlipExist(existing) then
        RemoveBlip(existing)
    end

    local blip = AddBlipForCoord(payload.coords.x, payload.coords.y, payload.coords.z)
    local sprite = payload.sprite or (Config.BusinessManager.DefaultBlip and Config.BusinessManager.DefaultBlip.sprite) or 1
    local scale = (Config.BusinessManager.DefaultBlip and Config.BusinessManager.DefaultBlip.scale) or 0.6
    local shortRange = (Config.BusinessManager.DefaultBlip and Config.BusinessManager.DefaultBlip.shortRange) ~= false

    SetBlipSprite(blip, sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, scale)
    SetBlipColour(blip, payload.color or 5)
    SetBlipAsShortRange(blip, shortRange)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(payload.name or businessId)
    EndTextCommandSetBlipName(blip)

    businessBlips[businessId] = blip
end)

-- Functions
function OpenComputer(entityOrData)
    if isComputerOpen then return end

    local entity = nil
    if type(entityOrData) == 'number' then
        entity = entityOrData
    elseif type(entityOrData) == 'table' then
        entity = entityOrData.entity or entityOrData.target
    end

    currentComputer = entity
    currentComputerProfile = ResolveComputerProfile(entity)
    local computerStateKey = BuildComputerStateKey(entity, currentComputerProfile)
    
    isComputerOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openComputer',
        computerProfile = currentComputerProfile,
        computerStateKey = computerStateKey
    })

    -- Push current game environment immediately when opening.
    SendEnvironmentSync()
    TriggerEvent('pf-devices:client:shellState', 'computer', true)
    
    -- Disable controls while computer is open
    CreateThread(function()
        while isComputerOpen do
            DisableControlAction(0, 1, true) -- LookLeftRight
            DisableControlAction(0, 2, true) -- LookUpDown
            DisableControlAction(0, 24, true) -- Attack
            DisableControlAction(0, 25, true) -- Aim
            DisableControlAction(0, 142, true) -- MeleeAttackAlternate
            DisableControlAction(0, 106, true) -- VehicleMouseControlOverride
            Wait(0)
        end
    end)
end

CreateThread(function()
    while true do
        if isComputerOpen then
            SendEnvironmentSync()
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

function CloseComputer()
    if not isComputerOpen then return end
    
    isComputerOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeComputer'
    })

    currentComputer = nil
    currentComputerProfile = 'default'
    TriggerEvent('pf-devices:client:shellState', 'computer', false)
end

-- other resources open and close the computer (pf-trucking closes it after a contract is accepted)
exports('OpenComputer', function(entityOrData) OpenComputer(entityOrData) end)
exports('CloseComputer', function() CloseComputer() end)
exports('IsComputerOpen', function() return isComputerOpen end)

-- pf-trucking's depot computer (E at the desk)
AddEventHandler('pf-computer:client:useComputer', function(data)
    OpenComputer(type(data) == 'table' and data or nil)
end)

-- pf-devices launch apps 'cityhall-admin' / 'cityhall-businesses' (server/devices.lua): the server
-- checked the pf-government permission, closed the computer, and asks for pf-government's screen in a
-- computer window, on any computer (it used to be offered on 'mayor' computers only).
RegisterNetEvent('pf-computer:client:openGovernmentProgram', function(programId)
    if type(programId) ~= 'string' or not programId:match('^[%w%-_]+$') then return end
    if GetResourceState('pf-government') ~= 'started' then return end
    local ok, list = pcall(function() return exports['pf-government']:GetComputerPrograms() end)
    local program
    for _, p in ipairs(ok and type(list) == 'table' and list or {}) do
        if type(p) == 'table' and p.id == programId then program = p break end
    end
    if not program or type(program.url) ~= 'string' or not program.url:find('^https://cfx%-nui%-pf%-government/') then return end
    program.resource = 'pf-government'
    Wait(300)   -- pf-devices closed the computer first
    if not isComputerOpen then OpenComputer() end
    Wait(600)   -- the page loads its own external programs on open
    SendNUIMessage({ action = 'openExternalProgram', programId = programId, program = program })
end)

-- a launcher app (e.g. the MDT) opens its own screen: close the computer first
RegisterNetEvent('pf-devices:client:closeShells', function()
    CloseComputer()
end)

-- pf-devices messages (app pushes, app list changes, open requests) reach the page while it is open
AddEventHandler('pf-devices:client:forward', function(msg)
    if isComputerOpen and type(msg) == 'table' then
        SendNUIMessage(msg)
    end
end)

RegisterNetEvent('pf-computer:client:openExternalProgram', function(programId)
    if type(programId) ~= 'string' or programId == '' then
        return
    end

    if not isComputerOpen then
        OpenComputer()
        Wait(100)
    end

    SendNUIMessage({
        action = 'openExternalProgram',
        programId = programId
    })
end)

RegisterNetEvent('pf-computer:client:closeExternalProgram', function(programId)
    if not isComputerOpen then return end
    if type(programId) ~= 'string' or programId == '' then return end

    SendNUIMessage({
        action = 'closeExternalProgram',
        programId = programId
    })
end)

-- Target System Integration
function SetupTargets()
    print('^2[pf-computer]^7 Setting up targets for ' .. #Config.ComputerProps .. ' computer props')
    
    if Config.TargetSystem == 'ox_target' then
        -- ox_target integration
        local options = {
            {
                name = 'use_computer',
                icon = 'fas fa-desktop',
                label = 'Use Computer',
                onSelect = function(data)
                    OpenComputer(data)
                end,
                distance = Config.InteractionDistance
            }
        }
        
        exports.ox_target:addModel(Config.ComputerProps, options)
        print('^2[pf-computer]^7 Registered with ox_target')
        
    elseif Config.TargetSystem == 'qb-target' then
        -- qb-target integration
        local success, err = pcall(function()
            exports['pfm-target']:AddTargetModel(Config.ComputerProps, {
                options = {
                    {
                        icon = 'fas fa-desktop',
                        label = 'Use Computer',
                        action = function(entity)
                            OpenComputer(entity)
                        end,
                    }
                },
                distance = Config.InteractionDistance
            })
        end)
        
        if success then
            print('^2[pf-computer]^7 Successfully registered with qb-target')
        else
            print('^1[pf-computer]^7 Failed to register with qb-target: ' .. tostring(err))
            print('^3[pf-computer]^7 Switching to key-based interaction')
            SetupKeyInteraction()
        end
    end
end

-- Alternative: Key-based interaction (if not using target system)
function SetupKeyInteraction()
    CreateThread(function()
        while true do
            local wait = 1000
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            
            for _, propModel in ipairs(Config.ComputerProps) do
                local prop = GetClosestObjectOfType(coords.x, coords.y, coords.z, Config.InteractionDistance, propModel, false, false, false)
                
                if prop ~= 0 then
                    wait = 0
                    local propCoords = GetEntityCoords(prop)
                    local distance = #(coords - propCoords)
                    
                    if distance <= Config.InteractionDistance then
                        -- Draw text
                        DrawText3D(propCoords.x, propCoords.y, propCoords.z + 0.5, '[E] Use Computer')
                        
                        if IsControlJustReleased(0, Config.InteractionKey) then
                            OpenComputer(prop)
                        end
                    end
                end
            end
            
            Wait(wait)
        end
    end)
end

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

-- Commands
RegisterCommand('computer', function()
    OpenComputer()
end, false)

RegisterCommand('closecomputer', function()
    CloseComputer()
end, false)

-- Spawn a computer prop at player location
RegisterCommand('spawncomputer', function(source, args)
    local model = args[1] or 'prop_laptop_01a' -- Default laptop model
    local hash = GetHashKey(model)
    
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(10)
    end
    
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    -- Spawn in front of player
    local forward = GetEntityForwardVector(ped)
    local spawnCoords = vector3(
        coords.x + forward.x * 1.0,
        coords.y + forward.y * 1.0,
        coords.z - 0.9  -- Ground level
    )
    
    local prop = CreateObject(hash, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false)
    SetEntityHeading(prop, heading)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)
    SetEntityAsMissionEntity(prop, true, true)
    
    SetModelAsNoLongerNeeded(hash)
    
    -- Save to server for persistence
    local finalCoords = GetEntityCoords(prop)
    local finalHeading = GetEntityHeading(prop)
    TriggerServerEvent('pf-computer:server:saveProp', {
        model = model,
        x = finalCoords.x,
        y = finalCoords.y,
        z = finalCoords.z,
        heading = finalHeading
    })
    -- this local object was only a preview: the server sends the saved computer to everyone
    DeleteEntity(prop)
    
    QBCore.Functions.Notify('Computer prop spawned! Models: prop_laptop_01a, prop_pc_01a, prop_monitor_01a', 'success', 5000)
    print('^2[pf-computer]^7 Spawned computer prop: ' .. model .. ' at ' .. spawnCoords)
end, false)

-- Delete nearest computer prop
RegisterCommand('deletecomputer', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    for _, propModel in ipairs(Config.ComputerProps) do
        local prop = GetClosestObjectOfType(coords.x, coords.y, coords.z, 2.0, propModel, false, false, false)
        if prop ~= 0 then
            -- the server decides whether this can be removed and tells every client to delete it
            TriggerServerEvent('pf-computer:server:deleteProp', GetEntityCoords(prop))
            return
        end
    end
    
    QBCore.Functions.Notify('No computer prop found nearby', 'error')
end, false)

-- Saved computers spawned on this client, by server id (so a resend never spawns a second copy)
local SpawnedComputerProps = {}

-- Ask the server for the saved computers when this player spawns (and after a resource restart)
local function requestSavedComputers()
    TriggerServerEvent('pf-computer:server:requestProps')
end
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', requestSavedComputers)
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() and LocalPlayer.state.isLoggedIn then requestSavedComputers() end
end)

-- Client event to spawn a prop sent from server
RegisterNetEvent('pf-computer:client:spawnProp', function(propData)
    if type(propData) ~= 'table' or type(propData.model) ~= 'string' then return end
    if propData.id and SpawnedComputerProps[propData.id] and DoesEntityExist(SpawnedComputerProps[propData.id]) then return end
    local hash = GetHashKey(propData.model)
    
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(10)
    end
    
    local prop = CreateObject(hash, propData.x, propData.y, propData.z, false, false, false)
    SetEntityHeading(prop, propData.heading or 0.0)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)
    SetEntityAsMissionEntity(prop, true, true)
    SetModelAsNoLongerNeeded(hash)
    if propData.id then SpawnedComputerProps[propData.id] = prop end
end)

-- Client event to delete a prop
RegisterNetEvent('pf-computer:client:deleteProp', function(coords, propId)
    if propId and SpawnedComputerProps[propId] then
        if DoesEntityExist(SpawnedComputerProps[propId]) then DeleteEntity(SpawnedComputerProps[propId]) end
        SpawnedComputerProps[propId] = nil
        return
    end
    for _, propModel in ipairs(Config.ComputerProps) do
        local prop = GetClosestObjectOfType(coords.x, coords.y, coords.z, 2.0, propModel, false, false, false)
        if prop ~= 0 then
            DeleteEntity(prop)
        end
    end
end)

-- Debug command to check computer setup
RegisterCommand('computertest', function()
    print('^2[pf-computer]^7 === Computer System Status ===')
    print('^2[pf-computer]^7 Target System: ' .. Config.TargetSystem)
    print('^2[pf-computer]^7 Use Third Eye: ' .. tostring(Config.UseThirdEye))
    print('^2[pf-computer]^7 Computer Props Count: ' .. #Config.ComputerProps)
    print('^2[pf-computer]^7 Interaction Distance: ' .. Config.InteractionDistance)
    
    -- Check for nearest computer prop
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local foundAny = false
    
    for i, propModel in ipairs(Config.ComputerProps) do
        local prop = GetClosestObjectOfType(coords.x, coords.y, coords.z, 50.0, propModel, false, false, false)
        if prop ~= 0 then
            local propCoords = GetEntityCoords(prop)
            local distance = #(coords - propCoords)
            print(string.format('^2[pf-computer]^7 Found prop #%d: model=%s, distance=%.2fm', i, propModel, distance))
            foundAny = true
        end
    end
    
    if not foundAny then
        print('^3[pf-computer]^7 No computer props found within 50m')
        print('^3[pf-computer]^7 Use /spawncomputer to place one')
        print('^3[pf-computer]^7 Available models: prop_laptop_01a, prop_pc_01a, prop_monitor_01a')
    end
end, false)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if isComputerOpen then
            CloseComputer()
        end
    end
end)

-- Initialize
CreateThread(function()
    -- Wait for framework to be ready
    Wait(1000)
    
    print('^2[pf-computer]^7 Initializing...')
    
    if Config.UseThirdEye then
        print('^2[pf-computer]^7 Setting up target system: ' .. Config.TargetSystem)
        SetupTargets()
    else
        print('^2[pf-computer]^7 Using key-based interaction (E key)')
        SetupKeyInteraction()
    end
    
    print('^2[pf-computer]^7 Successfully loaded with ^3' .. Config.Framework .. '^7 framework')
    print('^2[pf-computer]^7 Commands: /spawncomputer, /deletecomputer, /computertest')
    
    -- Load persistent business blips
    LoadBusinessBlips()
    
    -- Load business stashes
    LoadBusinessStashes()
end)

function LoadBusinessBlips()
    local blipsResult = requestServer('business:blips:get', {})
    if not blipsResult or not blipsResult.ok then
        print('^1[pf-computer]^7 Failed to load business blips')
        return
    end
    
    local blips = blipsResult.data or {}
    for _,blipData in ipairs(blips) do
        CreateBusinessBlip(blipData)
    end
    
    print('^2[pf-computer]^7 Loaded ' .. #blips .. ' business blips')
end

function CreateBusinessBlip(blipData)
    if not blipData or not blipData.coords then return end
    
    local blip = AddBlipForCoord(blipData.coords.x, blipData.coords.y, blipData.coords.z)
    SetBlipSprite(blip, blipData.sprite or 52)
    SetBlipColour(blip, blipData.color or 58)
    SetBlipScale(blip, blipData.scale or 0.6)
    SetBlipAsShortRange(blip, blipData.shortRange ~= false)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentString(blipData.name or 'Business')
    EndTextCommandDisplayHelp(blip, false, true, -1)
    
    -- Store blip reference for later cleanup if needed
    businessBlips[blipData.businessId] = blip
end

-- ============================================================================
-- STASH MANAGEMENT
-- ============================================================================
local businessStashes = {}

function LoadBusinessStashes()
    local stashResult = requestServer('business:stashes:getAll', {})
    if not stashResult or not stashResult.ok then
        print('^1[pf-computer]^7 Failed to load business stashes')
        return
    end
    
    local stashes = stashResult.data or {}
    for businessId, locations in pairs(stashes) do
        TriggerEvent('pf-computer:client:updateStashes', {
            businessId = businessId,
            stashLocations = locations
        })
    end
    
    print('^2[pf-computer]^7 Loaded stashes for ' .. #stashes .. ' businesses')
end

RegisterNetEvent('pf-computer:client:updateStashes', function(payload)
    if not payload or not payload.businessId then return end
    
    local businessId = payload.businessId
    local locations = payload.stashLocations or {}
    
    -- Remove old stash targets
    if businessStashes[businessId] then
        for _, zoneId in ipairs(businessStashes[businessId]) do
            if Config.TargetSystem == 'qb-target' and GetResourceState('pfm-target') == 'started' then
                exports['pfm-target']:RemoveZone(zoneId)
            elseif Config.TargetSystem == 'ox_target' and GetResourceState('ox_target') == 'started' then
                exports.ox_target:removeZone(zoneId)
            end
        end
    end
    
    businessStashes[businessId] = {}
    
    -- Create new stash targets
    for i, loc in ipairs(locations) do
        local zoneId = 'business_stash_' .. businessId .. '_' .. i
        local coords = vector3(loc.x, loc.y, loc.z)
        
        if Config.TargetSystem == 'qb-target' and GetResourceState('pfm-target') == 'started' then
            exports['pfm-target']:AddCircleZone(zoneId, coords, 1.5, {
                name = zoneId,
                debugPoly = false,
                useZ = true
            }, {
                options = {
                    {
                        type = 'client',
                        icon = 'fas fa-box',
                        label = 'Open Storage',
                        action = function()
                            OpenBusinessStash(businessId, i)
                        end,
                        job = businessId
                    }
                },
                distance = 2.0
            })
            table.insert(businessStashes[businessId], zoneId)
        elseif Config.TargetSystem == 'ox_target' and GetResourceState('ox_target') == 'started' then
            exports.ox_target:addSphereZone({
                coords = coords,
                radius = 1.5,
                debug = false,
                options = {
                    {
                        name = zoneId,
                        icon = 'fa-solid fa-box',
                        label = 'Open Storage',
                        onSelect = function()
                            OpenBusinessStash(businessId, i)
                        end,
                        groups = businessId
                    }
                }
            })
            table.insert(businessStashes[businessId], zoneId)
        end
    end
    
    print('^2[pf-computer]^7 Updated ' .. #locations .. ' stash locations for ' .. businessId)
end)

function OpenBusinessStash(businessId, stashId)
    -- the server checks the job and the stash point, and opens the business stock
    TriggerServerEvent('pf-computer:server:openBusinessStash', businessId, stashId)
end
