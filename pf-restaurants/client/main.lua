QBCore = exports['pfm-core']:GetCoreObject()

local PlayerData = {}
local currentBusiness = nil
local isEmployee = false
local employeeData = nil

-- Initialize
CreateThread(function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
    currentBusiness = nil
    isEmployee = false
    employeeData = nil
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    PlayerData = data
end)

-- Receive business data
RegisterNetEvent('pf-restaurants:client:receiveBusinessData', function(data)
    -- Store business data
    if Config.Debug then
        print('[pf-restaurants] Received business data:', json.encode(data, {indent = true}))
    end
end)

-- Check if player is close to restaurant
CreateThread(function()
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for businessId, restaurant in pairs(Config.Restaurants) do
            if restaurant.zones and restaurant.zones.kitchen then
                local distance = #(playerCoords - restaurant.zones.kitchen.center)
                
                if distance <= restaurant.zones.kitchen.radius then
                    currentBusiness = businessId
                    
                    -- Check if employee
                    QBCore.Functions.TriggerCallback('pf-restaurants:server:isEmployee', function(isEmp, empData)
                        isEmployee = isEmp
                        employeeData = empData
                    end, businessId)
                    
                    sleep = 500
                    break
                else
                    if currentBusiness == businessId then
                        currentBusiness = nil
                        isEmployee = false
                        employeeData = nil
                    end
                end
            end
        end
        
        Wait(sleep)
    end
end)

-- Helper: Show notification
function ShowNotification(message, type)
    if Config.Notifications.Type == 'qb' then
        QBCore.Functions.Notify(message, type, Config.Notifications.Duration)
    elseif Config.Notifications.Type == 'ox' then
        lib.notify({
            description = message,
            type = type,
            duration = Config.Notifications.Duration
        })
    end
end

-- Helper: Draw 3D text
function Draw3DText(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    local camCoords = GetGameplayCamCoords()
    local distance = #(camCoords - coords)
    
    local scale = (1 / distance) * 2
    local fov = (1 / GetGameplayCamFov()) * 100
    scale = scale * fov
    
    if onScreen then
        SetTextScale(0.0 * scale, 0.35 * scale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry('STRING')
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(x, y)
    end
end

-- Export current business
exports('GetCurrentBusiness', function()
    return currentBusiness
end)

exports('IsEmployee', function(businessId)
    if businessId then
        return currentBusiness == businessId and isEmployee
    else
        return isEmployee
    end
end)

exports('GetEmployeeData', function()
    return employeeData
end)

print('^2[pf-restaurants] Client loaded successfully^0')
