-- DUI screen management for KDS and Menu displays

local activeScreens = {}
local duiObjects = {}

-- Initialize screens
CreateThread(function()
    Wait(5000) -- Wait for resources to load
    
    for businessId, screens in pairs(Config.Screens) do
        for _, screen in ipairs(screens) do
            CreateDUIScreen(businessId, screen)
        end
    end
end)

-- Create DUI screen
function CreateDUIScreen(businessId, screenConfig)
    local screenId = screenConfig.screenId
    
    -- Generate DUI URL
    local baseUrl = string.format('nui://pf-restaurants/web/%s.html', screenConfig.type)
    local url = string.format('%s?businessId=%s', baseUrl, businessId)
    
    -- Create DUI
    local dui = CreateDui(url, 1920, 1080)
    local duiHandle = GetDuiHandle(dui)
    
    -- Create runtime texture
    local txd = CreateRuntimeTxd('dui_' .. screenId)
    local tx = CreateRuntimeTextureFromDuiHandle(txd, 'dui_tex_' .. screenId, duiHandle)
    
    duiObjects[screenId] = {
        dui = dui,
        duiHandle = duiHandle,
        txd = txd,
        screenConfig = screenConfig,
        businessId = businessId,
        active = false
    }
    
    if Config.Debug then
        print('[pf-restaurants] Created DUI screen: ' .. screenId)
    end
end

-- Activate/deactivate screens based on player distance
CreateThread(function()
    while true do
        local sleep = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        
        for screenId, duiData in pairs(duiObjects) do
            local distance = #(playerCoords - duiData.screenConfig.coords)
            
            if distance <= Config.Timings.DUIActivationRange then
                if not duiData.active then
                    duiData.active = true
                    -- Could trigger DUI update here
                end
                sleep = 500
            else
                if duiData.active then
                    duiData.active = false
                end
            end
        end
        
        Wait(sleep)
    end
end)

-- Update KDS screen with new orders
RegisterNetEvent('pf-restaurants:client:newOrder', function(businessId, order)
    -- Send to all KDS screens for this business
    for screenId, duiData in pairs(duiObjects) do
        if duiData.businessId == businessId and duiData.screenConfig.type == 'kds' then
            SendDuiMessage(duiData.dui, json.encode({
                action = 'newOrder',
                order = order
            }))
        end
    end
end)

-- Update order status on KDS
RegisterNetEvent('pf-restaurants:client:orderStatusUpdate', function(orderId, newStatus)
    -- Update all active KDS screens
    for screenId, duiData in pairs(duiObjects) do
        if duiData.screenConfig.type == 'kds' and duiData.active then
            SendDuiMessage(duiData.dui, json.encode({
                action = 'updateOrderStatus',
                orderId = orderId,
                status = newStatus
            }))
        end
    end
end)

-- Update menu boards
RegisterNetEvent('pf-restaurants:client:menuUpdate', function(businessId, menu)
    for screenId, duiData in pairs(duiObjects) do
        if duiData.businessId == businessId and duiData.screenConfig.type == 'menu' then
            SendDuiMessage(duiData.dui, json.encode({
                action = 'updateMenu',
                menu = menu
            }))
        end
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for screenId, duiData in pairs(duiObjects) do
            if duiData.dui then
                DestroyDui(duiData.dui)
            end
        end
    end
end)
