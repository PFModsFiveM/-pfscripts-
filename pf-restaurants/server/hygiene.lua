-- Hygiene system management

-- Clean up trash
RegisterNetEvent('pf-restaurants:server:removeTrash', function(businessId, trashId)
    local src = source
    
    if not HasPermission(src, businessId, 'station.use') then
        return
    end
    
    local business = RestaurantData.businesses[businessId]
    if not business then return end
    -- only trash that is there (repeating this reset the hygiene without cleaning anything)
    if (tonumber(business.hygiene.trashCount) or 0) < 1 then return end

    -- Reduce dirt level
    business.hygiene.dirtLevel = math.max(0, business.hygiene.dirtLevel - Config.Hygiene.TrashRemovalDirtReduction)
    business.hygiene.trashCount = math.max(0, business.hygiene.trashCount - 1)
    
    NotifyPlayer(src, 'Trash removed', 'success')
    TriggerClientEvent('pf-restaurants:client:removeTrash', -1, businessId, trashId)
    
    UpdateHealthRating(businessId)
end)

-- Mop floor
RegisterNetEvent('pf-restaurants:server:mopFloor', function(businessId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'station.use') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    -- Check for cleaning supplies
    local hasSupplies = Player.Functions.GetItemByName('cleaning_supplies')
    if not hasSupplies or hasSupplies.amount < 1 then
        NotifyPlayer(src, 'Need cleaning supplies', 'error')
        return
    end
    
    Player.Functions.RemoveItem('cleaning_supplies', 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['cleaning_supplies'], 'remove', 1)
    
    local business = RestaurantData.businesses[businessId]
    if not business then return end
    
    business.hygiene.dirtLevel = math.max(0, business.hygiene.dirtLevel - Config.Hygiene.MopDirtReduction)
    
    NotifyPlayer(src, 'Floor mopped', 'success')
    UpdateHealthRating(businessId)
end)

-- Pest control
RegisterNetEvent('pf-restaurants:server:sprayPest', function(businessId, roachId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'station.use') then
        return
    end
    
    -- Check for pest spray
    local hasSpray = Player.Functions.GetItemByName('pest_spray')
    if not hasSpray or hasSpray.amount < 1 then
        NotifyPlayer(src, 'Need pest spray', 'error')
        return
    end
    
    Player.Functions.RemoveItem('pest_spray', 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['pest_spray'], 'remove', 1)
    
    local business = RestaurantData.businesses[businessId]
    if not business then return end
    
    business.hygiene.roachCount = math.max(0, business.hygiene.roachCount - 1)
    business.hygiene.dirtLevel = math.max(0, business.hygiene.dirtLevel - 5)
    
    NotifyPlayer(src, 'Pest eliminated', 'success')
    TriggerClientEvent('pf-restaurants:client:removeRoach', -1, businessId, roachId)
    
    UpdateHealthRating(businessId)
end)

-- Get hygiene status
QBCore.Functions.CreateCallback('pf-restaurants:server:getHygieneStatus', function(source, cb, businessId)
    local business = RestaurantData.businesses[businessId]
    if not business then
        cb(nil)
        return
    end
    
    cb(business.hygiene)
end)

-- Manual hygiene inspection (government integration placeholder)
RegisterNetEvent('pf-restaurants:server:conductInspection', function(businessId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- government staff with the 'licenses' permission inspect (pf-government roles)
    local isInspector = false
    if GetResourceState('pf-government') == 'started' then
        local ok, allowed = pcall(function() return exports['pf-government']:HasPermission(src, 'licenses') end)
        isInspector = ok and allowed == true
    end
    
    if not isInspector then
        NotifyPlayer(src, 'Only health inspectors can conduct inspections', 'error')
        return
    end
    
    local business = RestaurantData.businesses[businessId]
    if not business then return end
    
    UpdateHealthRating(businessId)
    
    local report = {
        businessId = businessId,
        timestamp = os.time(),
        dirtLevel = business.hygiene.dirtLevel,
        trashCount = business.hygiene.trashCount,
        roachCount = business.hygiene.roachCount,
        healthRating = business.hygiene.healthRating,
        inspector = Player.PlayerData.citizenid
    }
    
    NotifyPlayer(src, 'Inspection complete. Rating: ' .. business.hygiene.healthRating, 'info')
    
    -- Log inspection
    LogAction('health_inspection', report)
    RestaurantDB.LogInspection(businessId, Player.PlayerData.citizenid, business.hygiene.healthRating, ('dirt %d, trash %d, roaches %d'):format(business.hygiene.dirtLevel or 0, business.hygiene.trashCount or 0, business.hygiene.roachCount or 0))
    RestaurantDB.SaveState(businessId)

    -- the inspection goes on the restaurant's government record and sets its compliance
    if GetResourceState('pf-government') == 'started' then
        local status = ({ A = 'compliant', B = 'compliant', C = 'warning', D = 'non_compliant', F = 'flagged' })[tostring(business.hygiene.healthRating)] or 'warning'
        local name = ('%s %s'):format(Player.PlayerData.charinfo and Player.PlayerData.charinfo.firstname or '', Player.PlayerData.charinfo and Player.PlayerData.charinfo.lastname or '')
        pcall(function()
            exports['pf-government']:RecordBusinessInspection('restaurant:' .. businessId, status,
                ('Health rating %s (dirt %d, trash %d, roaches %d)'):format(tostring(business.hygiene.healthRating), business.hygiene.dirtLevel or 0, business.hygiene.trashCount or 0, business.hygiene.roachCount or 0),
                Player.PlayerData.citizenid, name)
        end)
    end
    
    -- Could trigger fines or closures based on rating
    if business.hygiene.healthRating == 'F' then
        NotifyPlayer(src, 'CRITICAL: This establishment should be closed!', 'error')
    end
end)
