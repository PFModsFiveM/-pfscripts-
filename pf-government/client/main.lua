-- =====================================================
-- PF GOVERNMENT - CLIENT MAIN
-- =====================================================

QBCore = exports[Config.FrameworkResourceName]:GetCoreObject()

local isUIOpen = false
local playerData = nil
local DEFAULT_PROGRAM_ID = 'pf-government-city-hall'
local BUSINESS_PROGRAM_ID = 'pf-government-businesses'

local function GetComputerPrograms()
    return {
        {
            id = 'pf-government-city-hall',
            label = 'City Hall',
            icon = '🏛️',
            external = true,
            resource = GetCurrentResourceName(),
            computerProfiles = { 'mayor' },
            jobRestricted = true,
            allowedJobs = { Config.GovernmentJob },
            url = 'https://cfx-nui-' .. GetCurrentResourceName() .. '/html/index.html?embedded=1&app=city-hall&programId=pf-government-city-hall',
            window = {
                width = 1320,
                height = 860
            }
        },
        {
            id = 'pf-government-businesses',
            label = 'Business Oversight',
            icon = '🏢',
            external = true,
            resource = GetCurrentResourceName(),
            computerProfiles = { 'mayor' },
            jobRestricted = true,
            allowedJobs = { Config.GovernmentJob },
            url = 'https://cfx-nui-' .. GetCurrentResourceName() .. '/html/index.html?embedded=1&app=businesses&programId=pf-government-businesses',
            window = {
                width = 1360,
                height = 900
            }
        }
    }
end

exports('GetComputerPrograms', GetComputerPrograms)

local function EnsureComputerRunning(showNotify)
    if GetResourceState('pf-computer') ~= 'started' then
        if showNotify then
            QBCore.Functions.Notify('Government apps require pf-computer to be running', 'error')
        end
        return false
    end

    return true
end

local function OpenInComputer(programId)
    if not EnsureComputerRunning(true) then
        return false
    end

    TriggerEvent('pf-computer:client:openExternalProgram', programId or DEFAULT_PROGRAM_ID)
    return true
end

local function CloseInComputer(programId)
    if not EnsureComputerRunning(false) then
        return false
    end

    TriggerEvent('pf-computer:client:closeExternalProgram', programId)
    return true
end

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

    if OpenInComputer(DEFAULT_PROGRAM_ID) then
        isUIOpen = true
        return
    end
end

function CloseUI()
    if not isUIOpen then
        return
    end

    CloseInComputer(DEFAULT_PROGRAM_ID)
    CloseInComputer(BUSINESS_PROGRAM_ID)
    isUIOpen = false
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

RegisterNetEvent('pf-government:client:refreshInfrastructureViews', function()
    if not EnsureComputerRunning(false) then return end
    SendNUIMessage({ action = 'refreshInfrastructureViews' })
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
-- NUI CALLBACKS
-- =====================================================

RegisterNUICallback('closeUI', function(data, cb)
    local programId = type(data) == 'table' and data.programId or DEFAULT_PROGRAM_ID
    CloseInComputer(programId)
    isUIOpen = false
    cb({ ok = true })
end)

RegisterNUICallback('hideUI', function(data, cb)
    local programId = type(data) == 'table' and data.programId or DEFAULT_PROGRAM_ID
    CloseInComputer(programId)
    isUIOpen = false
    cb({ ok = true })
end)

-- =====================================================
-- ITEM USAGE (If Required)
-- =====================================================

if Config.AccessControl.RequireItem then
    RegisterNetEvent('pf-government:client:useItem', function()
        OpenUI()
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

CreateThread(function()
    Wait(1500)
    if not EnsureComputerRunning(false) then
        print('^1[PF-GOVERNMENT]^7 pf-computer is not running. Government apps will be unavailable.')
    else
        print('^2[PF-GOVERNMENT]^7 External apps registered for pf-computer integration.')
    end
end)

print('^2[PF-GOVERNMENT]^7 Client main loaded')
