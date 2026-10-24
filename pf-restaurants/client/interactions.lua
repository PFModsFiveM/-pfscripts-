-- Station interactions setup

CreateThread(function()
    if Config.UseTarget then
        SetupStationInteractions()
    end
end)

-- Setup all station interactions
function SetupStationInteractions()
    for businessId, stations in pairs(Config.Stations) do
        for _, station in ipairs(stations) do
            SetupStationTarget(businessId, station)
        end
    end
end

-- Setup individual station target
function SetupStationTarget(businessId, station)
    if Config.TargetScript == 'qb-target' then
        exports['pfm-target']:AddBoxZone('restaurant_station_' .. station.stationId, station.coords, 1.5, 1.5, {
            name = 'restaurant_station_' .. station.stationId,
            heading = station.heading,
            debugPoly = Config.Debug,
            minZ = station.coords.z - 1.0,
            maxZ = station.coords.z + 1.0,
        }, {
            options = BuildStationOptions(businessId, station),
            distance = station.interaction.distance or 2.0
        })
    elseif Config.TargetScript == 'ox_target' then
        exports.ox_target:addBoxZone({
            coords = station.coords,
            size = vec3(1.5, 1.5, 1.5),
            rotation = station.heading,
            debug = Config.Debug,
            options = BuildStationOptions(businessId, station)
        })
    end
end

-- Build station interaction options
function BuildStationOptions(businessId, station)
    local options = {}
    
    for _, option in ipairs(station.interaction.options) do
        table.insert(options, {
            type = 'client',
            event = 'pf-restaurants:client:stationAction',
            icon = 'fas fa-utensils',
            label = option.label,
            businessId = businessId,
            stationId = station.stationId,
            action = option.action,
            permission = option.permission,
        })
    end
    
    return options
end

-- Handle station action
RegisterNetEvent('pf-restaurants:client:stationAction', function(data)
    local businessId = data.businessId
    local stationId = data.stationId
    local action = data.action
    
    -- Check if employee
    QBCore.Functions.TriggerCallback('pf-restaurants:server:isEmployee', function(isEmp, empData)
        if not isEmp then
            ShowNotification('You are not an employee here', 'error')
            return
        end
        
        -- Handle different actions
        if action == 'clean_grill' or action == 'clean_oven' then
            TriggerServerEvent('pf-restaurants:server:cleanEquipment', businessId, stationId)
        elseif action == 'change_oil' then
            TriggerServerEvent('pf-restaurants:server:changeOil', businessId, stationId)
        elseif action == 'refill_ice' then
            TriggerServerEvent('pf-restaurants:server:refillIce', businessId, stationId)
        else
            -- Cooking/prep action - open menu to select what to cook
            OpenStationMenu(businessId, stationId, action)
        end
    end, businessId)
end)

-- Open station menu (select what to cook)
function OpenStationMenu(businessId, stationId, action)
    -- Get available recipes for this action
    local availableRecipes = {}
    
    for _, rule in ipairs(Config.ComponentRules) do
        if rule.action == action then
            table.insert(availableRecipes, rule)
        end
    end
    
    if #availableRecipes == 0 then
        ShowNotification('No recipes available for this station', 'error')
        return
    end
    
    -- Build menu
    local menuOptions = {}
    
    for _, rule in ipairs(availableRecipes) do
        local inputText = ''
        for i, input in ipairs(rule.input) do
            inputText = inputText .. input.qty .. 'x ' .. input.item
            if i < #rule.input then
                inputText = inputText .. ', '
            end
        end
        
        table.insert(menuOptions, {
            header = 'Cook ' .. rule.output[1].item,
            txt = 'Requires: ' .. inputText,
            params = {
                event = 'pf-restaurants:client:startCooking',
                args = {
                    businessId = businessId,
                    stationId = stationId,
                    action = action,
                    rule = rule
                }
            }
        })
    end
    
    table.insert(menuOptions, {
        header = 'Close',
        params = {
            event = 'qb-menu:client:closeMenu'
        }
    })
    
    exports['pfm-menu']:openMenu(menuOptions)
end

-- Start cooking
RegisterNetEvent('pf-restaurants:client:startCooking', function(data)
    local businessId = data.businessId
    local stationId = data.stationId
    local action = data.action
    local rule = data.rule
    
    -- Find available slot
    -- For now, use slot 1 (would need to check occupancy from server)
    local slotId = 1
    
    -- Ask for doneness if required
    if rule.requiresDoneness then
        local donenessMenu = {
            {
                header = 'Select Doneness',
                isMenuHeader = true
            },
            {
                header = 'Rare',
                params = {
                    event = 'pf-restaurants:client:confirmCooking',
                    args = {
                        businessId = businessId,
                        stationId = stationId,
                        slotId = slotId,
                        action = action,
                        inputItems = rule.input,
                        donenessTarget = 'rare'
                    }
                }
            },
            {
                header = 'Medium-Rare',
                params = {
                    event = 'pf-restaurants:client:confirmCooking',
                    args = {
                        businessId = businessId,
                        stationId = stationId,
                        slotId = slotId,
                        action = action,
                        inputItems = rule.input,
                        donenessTarget = 'medium-rare'
                    }
                }
            },
            {
                header = 'Medium',
                params = {
                    event = 'pf-restaurants:client:confirmCooking',
                    args = {
                        businessId = businessId,
                        stationId = stationId,
                        slotId = slotId,
                        action = action,
                        inputItems = rule.input,
                        donenessTarget = 'medium'
                    }
                }
            },
            {
                header = 'Well-Done',
                params = {
                    event = 'pf-restaurants:client:confirmCooking',
                    args = {
                        businessId = businessId,
                        stationId = stationId,
                        slotId = slotId,
                        action = action,
                        inputItems = rule.input,
                        donenessTarget = 'well-done'
                    }
                }
            },
        }
        
        exports['pfm-menu']:openMenu(donenessMenu)
    else
        -- Start cooking directly
        -- (this called exports(...), which registers an export instead of starting the cooking)
        StartStationAction(businessId, stationId, slotId, action, rule.input, 'medium')
    end
end)

-- Confirm cooking with doneness
RegisterNetEvent('pf-restaurants:client:confirmCooking', function(data)
    StartStationAction(data.businessId, data.stationId, data.slotId, data.action, data.inputItems, data.donenessTarget)
end)

-- Consume food (apply hunger/thirst/poison effects)
RegisterNetEvent('pf-restaurants:client:consumeFood', function(hunger, thirst, poisonRisk)
    -- Apply hunger
    if hunger > 0 then
        TriggerServerEvent('hud:server:RelieveStress', math.min(100, hunger))
    end
    
    -- Apply thirst
    if thirst > 0 then
        -- Thirst handling (depends on your hud/status system)
    end
    
    -- Apply poison risk
    if poisonRisk > 0 then
        if math.random() < poisonRisk then
            ShowNotification('You feel sick...', 'error')
            -- Could trigger vomiting animation, health damage, etc.
            SetEntityHealth(PlayerPedId(), GetEntityHealth(PlayerPedId()) - (poisonRisk * 50))
        end
    end
end)
