QBCore = exports['pfm-core']:GetCoreObject()

RestaurantData = {
    businesses = {},
    stations = {},
    equipment = {},
    orders = {},
    recipes = {},
    menus = {},
    inventory = {},
    employees = {},
}

-- Helper function for notifications
function NotifyPlayer(source, message, type, duration)
    if Config.Notifications.Type == 'qb' then
        TriggerClientEvent('QBCore:Notify', source, message, type, duration or Config.Notifications.Duration)
    elseif Config.Notifications.Type == 'ox' then
        TriggerClientEvent('ox_lib:notify', source, {
            description = message,
            type = type,
            duration = duration or Config.Notifications.Duration
        })
    end
end

-- Helper function for logging
function LogAction(action, data)
    if not Config.Logging.Enabled then return end
    if not Config.Logging.LogActions[action] then return end
    
    local logEntry = {
        action = action,
        timestamp = os.time(),
        data = data
    }
    
    -- You can extend this to write to database or file
    print(string.format('[RESTAURANT LOG] %s: %s', action, json.encode(data)))
end

-- Initialize the system
CreateThread(function()
    -- Load restaurants from config
    for businessId, restaurant in pairs(Config.Restaurants) do
        RestaurantData.businesses[businessId] = {
            businessId = businessId,
            label = restaurant.label,
            zones = restaurant.zones,
            storage = restaurant.storage,
            hygiene = {
                dirtLevel = 0,
                trashCount = 0,
                roachCount = 0,
                healthRating = 'A'
            },
            lastUpdate = os.time()
        }
    end
    
    -- Load stations
    for businessId, stations in pairs(Config.Stations) do
        RestaurantData.stations[businessId] = {}
        for _, station in ipairs(stations) do
            RestaurantData.stations[businessId][station.stationId] = {
                stationId = station.stationId,
                type = station.type,
                coords = station.coords,
                slots = {},
                sessions = {}
            }
            
            -- Initialize slots
            for i = 1, station.slots do
                table.insert(RestaurantData.stations[businessId][station.stationId].slots, {
                    slotId = i,
                    occupied = false,
                    session = nil
                })
            end
            
            -- Initialize equipment
            if not RestaurantData.equipment[businessId] then
                RestaurantData.equipment[businessId] = {}
            end
            RestaurantData.equipment[businessId][station.stationId] = {
                cleanliness = 100,
                condition = 100,
                oilQuality = 100, -- For fryers
                iceLevel = 100, -- For drink stations
                burntCount = 0,
                lastCleaned = os.time()
            }
        end
    end
    
    -- Load recipes from config
    for recipeId, recipe in pairs(Config.Recipes) do
        RestaurantData.recipes[recipeId] = recipe
    end
    
    print('^2[pf-restaurants] System initialized successfully^0')
end)

-- Hygiene update loop
CreateThread(function()
    while true do
        Wait(Config.Timings.HygieneUpdateInterval)
        
        for businessId, business in pairs(RestaurantData.businesses) do
            -- Accumulate dirt
            business.hygiene.dirtLevel = business.hygiene.dirtLevel + Config.Hygiene.DirtAccumulationRate
            
            -- Check thresholds
            if business.hygiene.dirtLevel >= Config.Hygiene.TrashSpawnThreshold and business.hygiene.trashCount < Config.Hygiene.MaxTrashProps then
                business.hygiene.trashCount = business.hygiene.trashCount + 1
                TriggerClientEvent('pf-restaurants:client:spawnTrash', -1, businessId)
            end
            
            if business.hygiene.dirtLevel >= Config.Hygiene.RoachSpawnThreshold and business.hygiene.roachCount < Config.Hygiene.MaxRoaches then
                business.hygiene.roachCount = business.hygiene.roachCount + 1
                TriggerClientEvent('pf-restaurants:client:spawnRoach', -1, businessId)
            end
            
            -- Update health rating
            UpdateHealthRating(businessId)
        end
    end
end)

-- Equipment degradation loop
CreateThread(function()
    while true do
        Wait(Config.Timings.EquipmentDegradationInterval)
        
        for businessId, equipment in pairs(RestaurantData.equipment) do
            for stationId, eq in pairs(equipment) do
                local stationType = RestaurantData.stations[businessId][stationId].type
                local degradation = Config.Equipment.ConditionDegradation[stationType] or 0.1
                eq.condition = math.max(0, eq.condition - degradation)
            end
        end
    end
end)

-- Calculate health rating
function UpdateHealthRating(businessId)
    local business = RestaurantData.businesses[businessId]
    if not business then return end
    
    -- Calculate hygiene score (0-100)
    local score = 100
    score = score - (business.hygiene.dirtLevel * 0.5)
    score = score - (business.hygiene.roachCount * 10)
    
    -- Factor in equipment cleanliness
    local totalCleanliness = 0
    local equipmentCount = 0
    if RestaurantData.equipment[businessId] then
        for _, eq in pairs(RestaurantData.equipment[businessId]) do
            totalCleanliness = totalCleanliness + eq.cleanliness
            equipmentCount = equipmentCount + 1
        end
    end
    
    if equipmentCount > 0 then
        local avgCleanliness = totalCleanliness / equipmentCount
        score = score * (avgCleanliness / 100)
    end
    
    score = math.max(0, math.min(100, score))
    
    -- Determine rating
    for _, ratingData in ipairs(Config.Hygiene.HealthRatings) do
        if score >= ratingData.min then
            business.hygiene.healthRating = ratingData.rating
            break
        end
    end
end

-- Get player business permissions
function HasPermission(source, businessId, permission)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local cid = Player.PlayerData.citizenid
    
    -- Check if player is an employee
    if not RestaurantData.employees[businessId] then return false end
    local employee = RestaurantData.employees[businessId][cid]
    if not employee then return false end
    
    -- Get role permissions
    local role = Config.Permissions.Roles[employee.role]
    if not role then return false end
    
    -- Check for 'all' permission (owner)
    if role.permissions['all'] or role.permissions == 'all' then return true end
    
    -- Check specific permission
    for _, perm in ipairs(role.permissions) do
        if perm == permission then return true end
    end
    
    return false
end

-- Export permission check
exports('HasPermission', HasPermission)

-- Callbacks for integrations
RegisterNetEvent('pf-restaurants:server:getBusinessData', function(businessId)
    local src = source
    local data = {
        business = RestaurantData.businesses[businessId],
        equipment = RestaurantData.equipment[businessId],
        hygiene = RestaurantData.businesses[businessId] and RestaurantData.businesses[businessId].hygiene or nil
    }
    TriggerClientEvent('pf-restaurants:client:receiveBusinessData', src, data)
end)

RegisterNetEvent('pf-restaurants:server:syncStations', function()
    local src = source
    TriggerClientEvent('pf-restaurants:client:syncStations', src, RestaurantData.stations)
end)

print('^2[pf-restaurants] Server loaded successfully^0')
