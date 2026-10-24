-- Cash register interactions (POS)

local registerModels = {
    ['prop_till_01'] = true,
    ['prop_till_02'] = true,
    ['prop_till_03'] = true,
}

-- Setup register interactions
CreateThread(function()
    if Config.UseTarget then
        SetupRegisterTargets()
    end
end)

-- Setup qb-target/ox_target zones
function SetupRegisterTargets()
    for businessId, registers in pairs(Config.Registers) do
        for _, register in ipairs(registers) do
            if Config.TargetScript == 'qb-target' then
                exports['pfm-target']:AddBoxZone('restaurant_register_' .. register.registerId, register.coords, 0.6, 0.6, {
                    name = 'restaurant_register_' .. register.registerId,
                    heading = register.heading,
                    debugPoly = Config.Debug,
                    minZ = register.coords.z - 0.5,
                    maxZ = register.coords.z + 0.5,
                }, {
                    options = {
                        {
                            type = 'client',
                            event = 'pf-restaurants:client:openPOS',
                            icon = 'fas fa-cash-register',
                            label = 'Open Register',
                            businessId = businessId,
                            registerId = register.registerId,
                        },
                    },
                    distance = 1.5
                })
            elseif Config.TargetScript == 'ox_target' then
                exports.ox_target:addBoxZone({
                    coords = register.coords,
                    size = vec3(0.6, 0.6, 0.6),
                    rotation = register.heading,
                    debug = Config.Debug,
                    options = {
                        {
                            name = 'restaurant_register_' .. register.registerId,
                            event = 'pf-restaurants:client:openPOS',
                            icon = 'fas fa-cash-register',
                            label = 'Open Register',
                            businessId = businessId,
                            registerId = register.registerId,
                        }
                    }
                })
            end
        end
    end
end

-- Open POS NUI
RegisterNetEvent('pf-restaurants:client:openPOS', function(data)
    local businessId = data.businessId
    
    -- Check if employee
    QBCore.Functions.TriggerCallback('pf-restaurants:server:isEmployee', function(isEmp, empData)
        if not isEmp then
            ShowNotification('You are not an employee here', 'error')
            return
        end
        
        -- Get menu
        QBCore.Functions.TriggerCallback('pf-restaurants:server:getMenu', function(menu)
            QBCore.Functions.TriggerCallback('pf-restaurants:server:getSalesTaxRate', function(taxRate)
                -- Open POS UI
                SetNuiFocus(true, true)
                SendNUIMessage({
                    action = 'openPOS',
                    businessId = businessId,
                    menu = menu,
                    employee = empData,
                    taxRate = taxRate or 0.0
                })
            end, businessId)
        end, businessId)
    end, businessId)
end)

-- Close POS NUI
RegisterNUICallback('closePOS', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Create order from POS
RegisterNUICallback('createOrder', function(data, cb)
    local businessId = data.businessId
    local orderData = {
        customerCid = data.customerCid,
        items = data.items,
        channel = data.channel or 'dine-in',
        subtotal = data.subtotal,
        tax = data.tax,
        total = data.total,
        paymentMethod = data.paymentMethod or 'cash'
    }
    
    TriggerServerEvent('pf-restaurants:server:createOrder', businessId, orderData)
    
    cb({success = true})
end)

-- Get menu items
RegisterNUICallback('getMenu', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-restaurants:server:getMenu', function(menu)
        cb(menu)
    end, data.businessId)
end)
