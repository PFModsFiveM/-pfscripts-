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
    -- the paying customer is the nearest player at the counter (the server checks the distance and asks
    -- them to accept); with nobody nearby the cashier pays. Prices come from the server's menu.
    local customerId = nil
    local closest, dist = QBCore.Functions.GetClosestPlayer()
    if closest and closest ~= -1 and dist and dist <= 3.0 then customerId = GetPlayerServerId(closest) end
    local orderData = {
        customerId = customerId,
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

-- A restaurant bill to accept or decline (the server only charges after the customer accepts)
RegisterNetEvent('pf-restaurants:client:confirmPayment', function(bill)
    if type(bill) ~= 'table' or not bill.orderId then return end
    local lines = {}
    for _, it in ipairs(bill.items or {}) do lines[#lines + 1] = ('%dx %s'):format(it.qty or 1, tostring(it.name or it.menuItemId)) end
    exports['pfm-menu']:openMenu({
        { header = ('%s: $%.2f'):format(bill.restaurant or 'Restaurant', bill.total or 0), txt = table.concat(lines, ', ') .. (' (tax $%.2f, %s)'):format(bill.tax or 0, bill.paymentMethod or 'cash'), isMenuHeader = true },
        { header = 'Pay', params = { event = 'pf-restaurants:client:answerPayment', args = { orderId = bill.orderId, accept = true } } },
        { header = 'Decline', params = { event = 'pf-restaurants:client:answerPayment', args = { orderId = bill.orderId, accept = false } } },
    })
end)

AddEventHandler('pf-restaurants:client:answerPayment', function(data)
    if type(data) ~= 'table' then return end
    TriggerServerEvent('pf-restaurants:server:answerPayment', data.orderId, data.accept == true)
end)
