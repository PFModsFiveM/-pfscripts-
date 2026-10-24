-- =====================================================
-- PF GOVERNMENT - CLIENT MAIN
-- =====================================================

QBCore = exports[Config.FrameworkResourceName]:GetCoreObject()

local isUIOpen = false
local playerData = nil

-- =====================================================
-- PLAYER DATA
-- =====================================================

CreateThread(function()
    while true do
        if LocalPlayer.state.isLoggedIn then
            playerData = QBCore.Functions.GetPlayerData()
            break
        end
        Wait(1000)
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    playerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    playerData = nil
    CloseUI()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    playerData.job = JobInfo
end)

-- =====================================================
-- UI CONTROL
-- =====================================================

function OpenUI()
    if isUIOpen then
        return
    end
    
    -- Check if player is government employee
    if not playerData or not playerData.job or playerData.job.name ~= Config.GovernmentJob then
        QBCore.Functions.Notify('You do not have access to the government system', 'error')
        return
    end
    
    -- Check location requirement
    if Config.AccessControl.RequireLocation then
        local playerCoords = GetEntityCoords(PlayerPedId())
        local hasAccess = false
        
        for _, location in ipairs(Config.AccessControl.AllowedLocations) do
            local dist = #(playerCoords - location.coords)
            if dist <= location.radius then
                hasAccess = true
                break
            end
        end
        
        if not hasAccess then
            QBCore.Functions.Notify('You must be at a government facility to access this system', 'error')
            return
        end
    end
    
    isUIOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openUI'
    })
end

function CloseUI()
    if not isUIOpen then
        return
    end
    
    isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeUI'
    })
end

function ToggleUI()
    if isUIOpen then
        CloseUI()
    else
        OpenUI()
    end
end

-- =====================================================
-- EVENTS
-- =====================================================

RegisterNetEvent('pf-government:client:openUI', function()
    OpenUI()
end)

RegisterNetEvent('pf-government:client:closeUI', function()
    CloseUI()
end)

RegisterNetEvent('pf-government:client:toggleUI', function()
    ToggleUI()
end)

-- =====================================================
-- COMMANDS
-- =====================================================

RegisterCommand('gov', function()
    ToggleUI()
end, false)

RegisterCommand('government', function()
    ToggleUI()
end, false)

RegisterCommand('cityhall', function()
    ToggleUI()
end, false)

-- =====================================================
-- KEY MAPPING (Optional)
-- =====================================================

RegisterKeyMapping('gov', 'Open Government System', 'keyboard', '')

-- =====================================================
-- TEMP GOVERNMENT COMPUTER PROP
-- =====================================================

local govComputer = {
    model = `prop_pc_02a`,
    coords = vector4(-76.94, -804.99, 243.4, 73.28)
}

CreateThread(function()
    RequestModel(govComputer.model)
    while not HasModelLoaded(govComputer.model) do
        Wait(0)
    end

    local obj = CreateObject(
        govComputer.model,
        govComputer.coords.x,
        govComputer.coords.y,
        govComputer.coords.z,
        false,
        false,
        false
    )

    SetEntityHeading(obj, govComputer.coords.w)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetModelAsNoLongerNeeded(govComputer.model)

    if GetResourceState('pfm-target') == 'started' then
        exports['pfm-target']:AddTargetEntity(obj, {
            options = {
                {
                    icon = 'fas fa-desktop',
                    label = 'Use Government Computer',
                    action = function()
                        OpenUI()
                    end
                }
            },
            distance = 2.0
        })
    end
end)

-- =====================================================
-- NUI CALLBACKS
-- =====================================================

RegisterNUICallback('closeUI', function(data, cb)
    CloseUI()
    cb({ ok = true })
end)

RegisterNUICallback('hideUI', function(data, cb)
    CloseUI()
    cb({ ok = true })
end)

-- =====================================================
-- ITEM USAGE (If Required)
-- =====================================================

if Config.AccessControl.RequireItem then
    RegisterNetEvent('pf-government:client:useItem', function()
        OpenUI()
    end)
    
    -- Register usable item
    CreateThread(function()
        Wait(1000)
        QBCore.Functions.CreateUseableItem(Config.AccessControl.ItemName, function(source, item)
            TriggerEvent('pf-government:client:useItem')
        end)
    end)
end

-- =====================================================
-- MARKER/BLIP SYSTEM (Optional)
-- =====================================================

if Config.AccessControl.RequireLocation then
    CreateThread(function()
        -- Create blips for government locations
        for _, location in ipairs(Config.AccessControl.AllowedLocations) do
            local blip = AddBlipForCoord(location.coords.x, location.coords.y, location.coords.z)
            SetBlipSprite(blip, 419) -- Government building icon
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, 0.8)
            SetBlipColour(blip, 3)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(location.label)
            EndTextCommandSetBlipName(blip)
        end
        
        -- Marker loop
        while true do
            local sleep = 1000
            local playerCoords = GetEntityCoords(PlayerPedId())
            
            for _, location in ipairs(Config.AccessControl.AllowedLocations) do
                local dist = #(playerCoords - location.coords)
                
                if dist < 50.0 then
                    sleep = 0
                    
                    -- Draw marker
                    DrawMarker(
                        1, -- Cylinder marker
                        location.coords.x, location.coords.y, location.coords.z - 1.0,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        2.0, 2.0, 1.0,
                        0, 120, 212, 100,
                        false, false, 2, false, nil, nil, false
                    )
                    
                    if dist < 2.0 then
                        -- Show help text
                        SetTextComponentFormat('STRING')
                        AddTextComponentString('Press ~INPUT_CONTEXT~ to open Government System')
                        DisplayHelpTextFromStringLabel(0, 0, 1, -1)
                        
                        -- Check for key press
                        if IsControlJustReleased(0, 38) then -- E key
                            OpenUI()
                        end
                    end
                end
            end
            
            Wait(sleep)
        end
    end)
end

print('^2[PF-GOVERNMENT]^7 Client main loaded')
