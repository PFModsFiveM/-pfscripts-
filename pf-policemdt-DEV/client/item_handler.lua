-- ============================================================================
-- PF Police MDT - Item Handler
-- ============================================================================
-- Handles the mdt item usage: plays tablet animation, opens UI, cleans up on close

local isUsingMDT = false
local tabletProp = nil
local enableTabletVisuals = true -- enable tablet prop/animation

local tabletData = {
    active = false,
    prop = nil,
    dict = "amb@world_human_seat_wall_tablet@female@base",
    anim = "base",
    model = `prop_cs_tablet`,
    bone = 28422, -- PH_R_Hand
    pos = vector3(0.03, 0.002, -0.0),
    rot = vector3(10.0, 160.0, 0.0),
    animFlag = 49,
}

local function IsMainMDTOpen()
    local ok, isOpen = pcall(function()
        return exports[GetCurrentResourceName()]:IsMDTOpen()
    end)
    return ok and isOpen == true
end

-- ============================================================================
-- Resource Initialization - Pre-cache Assets
-- ============================================================================

-- Pre-load animation dict and model on resource start (non-blocking)
if enableTabletVisuals then
    CreateThread(function()
        local animDict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'
        local propModel = `prop_tablet`
        
        -- Request anim dict
        RequestAnimDict(animDict)
        
        -- Request model
        RequestModel(propModel)
        
        -- Wait a bit for them to load in background
        local startTime = GetGameTimer()
        while (not HasAnimDictLoaded(animDict) or not HasModelLoaded(propModel)) do
            if GetGameTimer() - startTime > 10000 then
                break -- Timeout after 10 seconds
            end
            Wait(100)
        end
        
        print('[MDT ITEM] Assets pre-cached on resource start')
    end)
end

-- ============================================================================
-- Animation Dictionary and Prop Setup
-- ============================================================================

local function LoadModel(model, timeout)
    local modelHash = model
    if type(model) == 'string' then
        modelHash = joaat(model)
    end

    if not IsModelInCdimage(modelHash) then
        return false
    end

    RequestModel(modelHash)
    local startTime = GetGameTimer()
    
    while not HasModelLoaded(modelHash) do
        Wait(10)
        if GetGameTimer() - startTime > (timeout or 5000) then
            return false
        end
    end
    
    return true
end

local function LoadAnimDict(dict, timeout)
    RequestAnimDict(dict)
    local startTime = GetGameTimer()
    
    while not HasAnimDictLoaded(dict) do
        Wait(10)
        if GetGameTimer() - startTime > (timeout or 5000) then
            return false
        end
    end
    
    return true
end

local function DeleteTabletEntity(ent)
    if ent and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
end

-- ============================================================================
-- Tablet Prop Management
-- ============================================================================

local function AttachTabletProp()
    if not enableTabletVisuals then
        return nil
    end
    
    if tabletProp and DoesEntityExist(tabletProp) then
        return tabletProp
    end
    
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return nil
    end

    -- Load assets
    if not LoadAnimDict(tabletData.dict, 5000) then
        print('[MDT] Failed to load anim dict: ' .. tabletData.dict)
        return nil
    end
    if not LoadModel(tabletData.model, 5000) then
        print('[MDT] Failed to load model')
        return nil
    end

    -- Create and attach prop
    local coords = GetEntityCoords(ped)
    local tablet = CreateObject(tabletData.model, coords.x, coords.y, coords.z, true, true, false)
    SetEntityCollision(tablet, false, false)
    SetEntityCompletelyDisableCollision(tablet, true, true)
    SetModelAsNoLongerNeeded(tabletData.model)

    AttachEntityToEntity(
        tablet,
        ped,
        GetPedBoneIndex(ped, tabletData.bone),
        tabletData.pos.x, tabletData.pos.y, tabletData.pos.z,
        tabletData.rot.x, tabletData.rot.y, tabletData.rot.z,
        true, true, false, true, 1, true
    )

    tabletProp = tablet
    print('[MDT] Tablet prop attached to player')
    return tablet
end

local function RemoveTabletProp()
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteTabletEntity(tabletProp)
        tabletProp = nil
    end
end

-- ============================================================================
-- Animation Playback
-- ============================================================================

local function PlayTabletAnimation()
    if not enableTabletVisuals then
        return false
    end
    
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return false
    end
    
    -- Play the animation
    TaskPlayAnim(ped, tabletData.dict, tabletData.anim, 8.0, -8.0, -1, tabletData.animFlag, 0.0, false, false, false)
    print('[MDT] Tablet animation playing')
    return true
end

-- Keep animation/prop active while MDT is open
CreateThread(function()
    while true do
        if enableTabletVisuals and isUsingMDT and IsMainMDTOpen() then
            local ped = PlayerPedId()
            if tabletProp == nil or not DoesEntityExist(tabletProp) then
                AttachTabletProp(function(_) end)
            end

            if not IsEntityPlayingAnim(ped, tabletData.dict, tabletData.anim, 3) then
                PlayTabletAnimation(function(_) end)
            end
            Wait(750)
        else
            Wait(500)
        end
    end
end)

local function StopTabletAnimation()
    local ped = PlayerPedId()
    if enableTabletVisuals and DoesEntityExist(ped) then
        StopAnimTask(ped, tabletData.dict, tabletData.anim, 1.0)
        ClearPedSecondaryTask(ped)
    end
end

local function CleanupTablet()
    StopTabletAnimation()
    RemoveTabletProp()
    isUsingMDT = false
end

local function AreTabletVisualsEnabledForSource(source)
    if enableTabletVisuals ~= true then
        return false
    end

    if type(Config) ~= 'table' then
        return true
    end

    local tv = Config.TabletVisuals
    if type(tv) ~= 'table' then
        return true
    end

    if tv.Enabled == false then
        return false
    end

    local src = string.lower(tostring(source or 'unknown'))
    if src == 'item' then return tv.Item ~= false end
    if src == 'command' then return tv.Command ~= false end
    if src == 'keybind' then return tv.Keybind ~= false end

    -- default: enabled
    return true
end

local function StartTabletVisuals(source)
    if not AreTabletVisualsEnabledForSource(source) then
        return
    end
    if isUsingMDT then return end

    -- Mark as using MDT (visual lifecycle managed here)
    isUsingMDT = true

    -- Run animation and prop setup in a thread to avoid blocking
    CreateThread(function()
        print('[MDT] Starting tablet visuals for source: ' .. (source or 'unknown'))
        
        -- Play animation
        PlayTabletAnimation()
        
        -- Attach prop
        AttachTabletProp()
    end)

    -- If the main MDT fails to open (e.g., server callback failure), recover visuals
    CreateThread(function()
        local startTime = GetGameTimer()
        while isUsingMDT and not IsMainMDTOpen() do
            if GetGameTimer() - startTime > 8000 then
                print('[MDT ITEM] Main MDT did not open in time, cleaning up')
                CleanupTablet()
                break
            end
            Wait(100)
        end
    end)
end

local function StopTabletVisuals()
    if not isUsingMDT then return end
    CleanupTablet()
end

RegisterNetEvent('pf-policemdt:client:TabletVisualsStart', function(source)
    StartTabletVisuals(source)
end)

RegisterNetEvent('pf-policemdt:client:TabletVisualsStop', function()
    StopTabletVisuals()
end)

-- ============================================================================
-- Item Usage
-- ============================================================================

-- Listen for server event when item is used
RegisterNetEvent('pf-policemdt:client:openMDT', function()
    TriggerEvent('pf-policemdt:client:TabletVisualsStart', 'item')

    -- Trigger the main MDT open event (which will open the UI, fetch data, and set NUI focus)
    TriggerEvent('pf-policemdt:client:TriggerMainOpen')
end)

-- When the main MDT closes, clean up tablet animation/prop and restore controls.
AddEventHandler('pf_mdt:client:UIOpenState', function(isOpen)
    if isOpen == false and isUsingMDT then
        CleanupTablet()
    end
end)

-- ============================================================================
-- Cleanup on Resource Stop
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() and isUsingMDT then
        CleanupTablet()
    end
end)

-- ============================================================================
-- Exports
-- ============================================================================

exports('IsUsingMDT', function()
    return isUsingMDT
end)
