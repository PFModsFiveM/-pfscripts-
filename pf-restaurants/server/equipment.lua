-- Equipment maintenance and cleaning

-- Get equipment status
QBCore.Functions.CreateCallback('pf-restaurants:server:getEquipment', function(source, cb, businessId)
    cb(RestaurantData.equipment[businessId] or {})
end)

-- Clean equipment
RegisterNetEvent('pf-restaurants:server:cleanEquipment', function(businessId, stationId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'equipment.clean') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    local equipment = RestaurantData.equipment[businessId] and RestaurantData.equipment[businessId][stationId]
    if not equipment then
        NotifyPlayer(src, 'Equipment not found', 'error')
        return
    end
    
    -- Check for cleaning supplies
    local hasSupplies = Player.Functions.GetItemByName('cleaning_supplies')
    if not hasSupplies or hasSupplies.amount < Config.Equipment.CleaningSupplyPerUse then
        NotifyPlayer(src, 'Need cleaning supplies', 'error')
        return
    end
    
    -- Remove supplies
    Player.Functions.RemoveItem('cleaning_supplies', Config.Equipment.CleaningSupplyPerUse)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['cleaning_supplies'], 'remove', Config.Equipment.CleaningSupplyPerUse)
    
    -- Clean equipment
    equipment.cleanliness = 100
    equipment.lastCleaned = os.time()
    equipment.burntCount = 0
    
    NotifyPlayer(src, 'Equipment cleaned successfully', 'success')
    TriggerClientEvent('pf-restaurants:client:equipmentUpdate', -1, businessId, stationId, equipment)
end)

-- Change fryer oil
RegisterNetEvent('pf-restaurants:server:changeOil', function(businessId, stationId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'equipment.clean') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    local equipment = RestaurantData.equipment[businessId] and RestaurantData.equipment[businessId][stationId]
    if not equipment then
        NotifyPlayer(src, 'Equipment not found', 'error')
        return
    end
    
    -- Check for new oil
    local hasOil = Player.Functions.GetItemByName('fryer_oil_new')
    if not hasOil or hasOil.amount < Config.Equipment.OilChangeQuantity then
        NotifyPlayer(src, 'Need fryer oil', 'error')
        return
    end
    
    -- Remove oil
    Player.Functions.RemoveItem('fryer_oil_new', Config.Equipment.OilChangeQuantity)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['fryer_oil_new'], 'remove', Config.Equipment.OilChangeQuantity)
    
    -- Change oil
    equipment.oilQuality = 100
    
    NotifyPlayer(src, 'Fryer oil changed', 'success')
    TriggerClientEvent('pf-restaurants:client:equipmentUpdate', -1, businessId, stationId, equipment)
end)

-- Refill ice
RegisterNetEvent('pf-restaurants:server:refillIce', function(businessId, stationId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'equipment.clean') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    local equipment = RestaurantData.equipment[businessId] and RestaurantData.equipment[businessId][stationId]
    if not equipment then
        NotifyPlayer(src, 'Equipment not found', 'error')
        return
    end
    
    -- Check for ice
    local hasIce = Player.Functions.GetItemByName('ice_bag')
    if not hasIce or hasIce.amount < Config.Equipment.IceRefillQuantity then
        NotifyPlayer(src, 'Need ice bag', 'error')
        return
    end
    
    -- Remove ice
    Player.Functions.RemoveItem('ice_bag', Config.Equipment.IceRefillQuantity)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['ice_bag'], 'remove', Config.Equipment.IceRefillQuantity)
    
    -- Refill ice
    equipment.iceLevel = 100
    
    NotifyPlayer(src, 'Ice refilled', 'success')
    TriggerClientEvent('pf-restaurants:client:equipmentUpdate', -1, businessId, stationId, equipment)
end)

-- Repair equipment (condition)
RegisterNetEvent('pf-restaurants:server:repairEquipment', function(businessId, stationId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not HasPermission(src, businessId, 'equipment.clean') then
        NotifyPlayer(src, 'No permission', 'error')
        return
    end
    
    local equipment = RestaurantData.equipment[businessId] and RestaurantData.equipment[businessId][stationId]
    if not equipment then
        NotifyPlayer(src, 'Equipment not found', 'error')
        return
    end
    
    -- nothing to repair: no charge (staff could drain the business account by repeating this)
    if (tonumber(equipment.condition) or 0) >= 100 then
        NotifyPlayer(src, 'This equipment does not need repairs', 'error')
        return
    end

    -- the restaurant's bank account pays (it used to take $500 cash from whoever clicked)
    local repairCost = 500
    local ok, res = pcall(function()
        return exports['pfm-banking']:Transfer({
            from = 'society:restaurant_' .. businessId, to = 'system:pf-restaurants-repairs', amount = repairCost,
            key = exports['pfm-banking']:LedgerAutoKey('restaurant-repair'), kind = 'expense',
            reason = 'Equipment repair', actor = Player.PlayerData.citizenid,
        })
    end)
    if not ok or type(res) ~= 'table' or not res.ok then
        NotifyPlayer(src, 'The business account cannot pay the $' .. repairCost .. ' repair', 'error')
        return
    end
    
    equipment.condition = 100
    
    NotifyPlayer(src, 'Equipment repaired', 'success')
    TriggerClientEvent('pf-restaurants:client:equipmentUpdate', -1, businessId, stationId, equipment)
end)
