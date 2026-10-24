-- Framework detection
local Framework = Config.Framework:lower()
local QBCore, ESX = nil, nil

if Framework == 'qbcore' then
    QBCore = exports['pfm-core']:GetCoreObject()
elseif Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
else
    print("^1[Outfit Bag] Invalid framework in config: " .. Config.Framework .. "^7")
    return
end

local OutfitBags = {}
local CurrentBagId = nil
local UIOpen = false

-- Framework callback helper (framework agnostic)
local function TriggerCallback(name, callback, ...)
    if Framework == 'qbcore' then
        QBCore.Functions.TriggerCallback(name, callback, ...)
    else -- ESX
        ESX.TriggerServerCallback(name, callback, ...)
    end
end

local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(0)
    end
end

local function PlayAnim(ped, dict, anim, duration)
    LoadAnimDict(dict)
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration or -1, 49, 0, false, false, false)
end

local function SetCrouch(ped, enabled)
    if enabled then
        RequestAnimSet("move_ped_crouched")
        while not HasAnimSetLoaded("move_ped_crouched") do
            Wait(0)
        end
        SetPedMovementClipset(ped, "move_ped_crouched", 0.25)
    else
        ResetPedMovementClipset(ped, 0.25)
        ResetPedStrafeClipset(ped)
        ResetPedWeaponMovementClipset(ped)
    end
end

-- Place the outfit bag prop
RegisterNetEvent('pf-outfitbag:placeBag')
AddEventHandler('pf-outfitbag:placeBag', function(bagId)
    if not bagId then return end
    
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)

    PlayAnim(playerPed, 'anim@heists@narcotics@trash', 'drop_front', 1000)
    Wait(600)
    
    local modelHash = GetHashKey(Config.PropModel)
    if not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then
        return
    end
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(0)
    end
    
    local propCoords = playerPos + GetEntityForwardVector(playerPed) * 0.5
    
    local prop = CreateObject(modelHash, propCoords.x, propCoords.y, propCoords.z, true, false, false)
    SetEntityHeading(prop, heading)
    PlaceObjectOnGroundProperly(prop)
    SetModelAsNoLongerNeeded(modelHash)

    if prop == 0 or not DoesEntityExist(prop) then
        return
    end
    
    OutfitBags[bagId] = {
        propId = prop,
        coords = GetEntityCoords(prop),
        bagId = bagId
    }
    
    -- Setup target
    SetupBagTarget(prop, bagId)
end)

-- Setup target on bag prop
function SetupBagTarget(prop, bagId)
    if Config.TargetSystem == 'ox_target' then
        exports['ox_target']:addLocalEntity(prop, Config.OXTargetOptions)
    elseif Config.TargetSystem == 'qb-target' then
        exports['pfm-target']:AddTargetEntity(prop, {
            options = Config.QBTargetOptions,
            distance = Config.InteractDistance
        })
    end
end

-- Pick up the bag
RegisterNetEvent('pf-outfitbag:pickupBag')
AddEventHandler('pf-outfitbag:pickupBag', function()
    local playerPed = PlayerPedId()
    local nearestBag = GetNearestBag()
    
    if nearestBag then
        local bagData = OutfitBags[nearestBag]
        if bagData then
            if Config.TargetSystem == 'ox_target' then
                exports['ox_target']:removeLocalEntity(bagData.propId, Config.OXTargetOptions)
            elseif Config.TargetSystem == 'qb-target' then
                exports['pfm-target']:RemoveTargetEntity(bagData.propId)
            end

            PlayAnim(playerPed, 'pickup_object', 'pickup_low', 800)
            Wait(500)
            
            DeleteEntity(bagData.propId)
            local bagId = bagData.bagId
            OutfitBags[nearestBag] = nil
            
            TriggerServerEvent('pf-outfitbag:addItem', bagId)
        end
    end
end)

-- Open the bag UI
RegisterNetEvent('pf-outfitbag:openBag')
AddEventHandler('pf-outfitbag:openBag', function()
    local nearestBag = GetNearestBag()
    
    if nearestBag then
        CurrentBagId = nearestBag
        local bagData = OutfitBags[nearestBag]
        
        if bagData then
            -- Fetch outfits from server
            TriggerCallback('pf-outfitbag:getOutfits', function(outfits)
                local ped = PlayerPedId()
                SetCrouch(ped, true)
                if Config.bagAnimation.enabled then
                    PlayAnim(ped, Config.bagAnimation.dict, Config.bagAnimation.anim, 2000)
                end

                SendNUIMessage({
                    action = 'show',
                    outfits = outfits
                })
                
                SetNuiFocus(true, true)
                UIOpen = true
                
            end, bagData.bagId)
        end
    end
end)

-- Save outfit
RegisterNUICallback('saveOutfit', function(data, cb)
    local outfitName = data.outfitName or 'Outfit ' .. math.random(1, 999)
    local bagData = OutfitBags[CurrentBagId]
    
    if bagData then
        local outfit = CaptureCurrentOutfit()
        
        -- Send to server to save in database
        TriggerServerEvent('pf-outfitbag:saveOutfit', bagData.bagId, outfitName, outfit)
    end
    cb('ok')
end)

-- Load outfit
RegisterNUICallback('loadOutfit', function(data, cb)
    local outfit = data.outfit
    
    if outfit and outfit.data then
        ApplyOutfit(outfit.data)
    end
    cb('ok')
end)

-- Rename outfit
RegisterNUICallback('renameOutfit', function(data, cb)
    local outfitId = data.outfitId
    local newName = data.newName
    local bagData = OutfitBags[CurrentBagId]
    
    if bagData and outfitId and newName then
        -- Send to server to update in database
        TriggerServerEvent('pf-outfitbag:renameOutfit', bagData.bagId, outfitId, newName)
    end
    cb('ok')
end)

-- Delete outfit
RegisterNUICallback('deleteOutfit', function(data, cb)
    local outfitId = data.outfitId
    local bagData = OutfitBags[CurrentBagId]
    
    if bagData and outfitId then
        -- Send to server to delete from database
        TriggerServerEvent('pf-outfitbag:deleteOutfit', bagData.bagId, outfitId)
    end
    cb('ok')
end)

-- Close UI
RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    UIOpen = false
    CurrentBagId = nil
    SetCrouch(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
    cb('ok')
end)

-- Update outfits in UI when server sends updates
RegisterNetEvent('pf-outfitbag:updateOutfits')
AddEventHandler('pf-outfitbag:updateOutfits', function(outfits)
    SendNUIMessage({
        action = 'updateOutfits',
        outfits = outfits
    })
end)

-- Capture current outfit
function CaptureCurrentOutfit()
    local playerPed = PlayerPedId()
    local outfit = {}
    
    if Config.ClothingSystem == 'qb-clothing' then
        outfit = CaptureQBClothing(playerPed)
    elseif Config.ClothingSystem == 'illenium_appearance' then
        outfit = CaptureIlleniumAppearance(playerPed)
    else
        outfit = CaptureQBClothing(playerPed)
    end
    
    return outfit
end

-- Capture QB-Clothing outfit
function CaptureQBClothing(ped)
    local outfit = {}
    
    for slot = 0, 11 do
        local drawable = GetPedDrawableVariation(ped, slot)
        local texture = GetPedTextureVariation(ped, slot)
        
        outfit['drawable_' .. slot] = drawable
        outfit['texture_' .. slot] = texture
    end
    
    return outfit
end

-- Capture Illenium Appearance outfit
function CaptureIlleniumAppearance(ped)
    if GetResourceState('illenium_appearance') ~= 'started' then
        return {}
    end
    
    local outfit = exports['illenium_appearance']:getPedAppearance(ped)
    return outfit or {}
end

-- Apply outfit
function ApplyOutfit(outfit)
    local playerPed = PlayerPedId()
    
    if Config.ClothingSystem == 'qb-clothing' then
        ApplyQBClothing(playerPed, outfit)
    elseif Config.ClothingSystem == 'illenium_appearance' then
        ApplyIlleniumAppearance(playerPed, outfit)
    else
        ApplyQBClothing(playerPed, outfit)
    end
end

-- Apply QB-Clothing outfit
function ApplyQBClothing(ped, outfit)
    for slot = 0, 11 do
        local drawable = outfit['drawable_' .. slot] or 0
        local texture = outfit['texture_' .. slot] or 0
        
        -- Play animation based on slot type
        if slot == 1 and Config.outfitChangeAnimation.top.enabled ~= false then
            PlayAnim(ped, Config.outfitChangeAnimation.top.dict, Config.outfitChangeAnimation.top.anim, Config.outfitChangeAnimation.top.duration)
            Wait(Config.outfitChangeAnimation.top.duration)
        elseif slot == 4 and Config.outfitChangeAnimation.bottom.enabled ~= false then
            PlayAnim(ped, Config.outfitChangeAnimation.bottom.dict, Config.outfitChangeAnimation.bottom.anim, Config.outfitChangeAnimation.bottom.duration)
            Wait(Config.outfitChangeAnimation.bottom.duration)
        elseif slot == 0 and Config.outfitChangeAnimation.head.enabled ~= false then
            PlayAnim(ped, Config.outfitChangeAnimation.head.dict, Config.outfitChangeAnimation.head.anim, Config.outfitChangeAnimation.head.duration)
            Wait(Config.outfitChangeAnimation.head.duration)
        end
        
        SetPedComponentVariation(ped, slot, drawable, texture, 2)
    end
    ClearPedTasks(ped)
end

-- Apply Illenium Appearance outfit
function ApplyIlleniumAppearance(ped, outfit)
    if outfit and type(outfit) == 'table' then
        TriggerEvent('illenium_appearance:setPedAppearance', ped, outfit)
    end
end

-- Get nearest bag
function GetNearestBag()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local nearestBag = nil
    local nearestDistance = Config.InteractDistance
    
    for bagId, bagData in pairs(OutfitBags) do
        if DoesEntityExist(bagData.propId) then
            local bagPos = GetEntityCoords(bagData.propId)
            local distance = #(playerPos - bagPos)
            
            if distance < nearestDistance then
                nearestDistance = distance
                nearestBag = bagId
            end
        end
    end
    
    return nearestBag
end

-- Close UI on ESC
RegisterKeyMapping('closeoutfitbag', 'Close Outfit Bag UI', 'keyboard', 'ESCAPE')
RegisterCommand('closeoutfitbag', function()
    if UIOpen then
        SendNUIMessage({ action = 'hide' })
        SetNuiFocus(false, false)
        UIOpen = false
        CurrentBagId = nil
    end
end, false)


-- Cleanup when resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        for bagId, bagData in pairs(OutfitBags) do
            if DoesEntityExist(bagData.propId) then
                DeleteEntity(bagData.propId)
            end
        end
        OutfitBags = {}
    end
end)
