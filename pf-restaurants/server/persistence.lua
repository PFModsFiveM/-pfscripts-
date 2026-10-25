-- pf-restaurants: persistence, staff permissions, items and stock storage.
--
-- Everything a restart used to wipe is kept in the database: staff (beyond the restaurant's job),
-- menus, custom recipes, orders, equipment condition, hygiene and inspections. Stock is real inventory:
-- one pfm-inventory stash per restaurant and storage area (restaurant-<id>-dry|fridge|freezer), so it
-- persists with the inventory, carries server-side freshness, and is what cooking consumes.

RestaurantDB = RestaurantDB or {}
local DB = RestaurantDB

DB.Migrations = {
    {
        version = 1,
        name = 'restaurant staff, menus, recipes, orders, state, inspections',
        up = {
            [[CREATE TABLE IF NOT EXISTS pf_restaurant_employees (
                business_id VARCHAR(64) NOT NULL, citizenid VARCHAR(64) NOT NULL, role VARCHAR(32) NOT NULL,
                PRIMARY KEY (business_id, citizenid)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS pf_restaurant_menu (
                business_id VARCHAR(64) NOT NULL, menu_item_id VARCHAR(96) NOT NULL, data LONGTEXT NOT NULL,
                PRIMARY KEY (business_id, menu_item_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS pf_restaurant_recipes (
                recipe_id VARCHAR(96) NOT NULL, business_id VARCHAR(64) NULL, data LONGTEXT NOT NULL,
                PRIMARY KEY (recipe_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS pf_restaurant_orders (
                order_id VARCHAR(64) NOT NULL, business_id VARCHAR(64) NOT NULL, status VARCHAR(24) NOT NULL,
                customer_cid VARCHAR(64) NULL, cashier_cid VARCHAR(64) NULL, payment_method VARCHAR(16) NOT NULL,
                subtotal DECIMAL(12,2) NOT NULL, tax DECIMAL(12,2) NOT NULL, total DECIMAL(12,2) NOT NULL,
                data LONGTEXT NOT NULL, placed_at BIGINT NOT NULL, updated_at BIGINT NOT NULL,
                PRIMARY KEY (order_id), INDEX idx_business_status (business_id, status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS pf_restaurant_state (
                business_id VARCHAR(64) NOT NULL, hygiene LONGTEXT NULL, equipment LONGTEXT NULL, updated_at BIGINT NOT NULL,
                PRIMARY KEY (business_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS pf_restaurant_inspections (
                id INT NOT NULL AUTO_INCREMENT, business_id VARCHAR(64) NOT NULL, inspector_cid VARCHAR(64) NULL,
                rating VARCHAR(4) NULL, notes VARCHAR(255) NULL, at BIGINT NOT NULL,
                PRIMARY KEY (id), INDEX idx_business (business_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

local function nowMs() return math.floor(os.time() * 1000) end

-- ── staff and permissions ───────────────────────────────────────────────────

--- The player's role at a restaurant: a role given with addEmployee, otherwise from the restaurant's
--- job (the boss is the owner, other grades by Config.Permissions.GradeRoles). Must be on duty.
function RoleOf(source, businessId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player or type(businessId) ~= 'string' then return nil end
    local restaurant = Config.Restaurants[businessId]
    if not restaurant then return nil end
    local cid = Player.PlayerData.citizenid
    local stored = RestaurantData.employees[businessId] and RestaurantData.employees[businessId][cid]
    if stored and Config.Permissions.Roles[stored.role] then return stored.role end
    local job = Player.PlayerData.job
    if restaurant.job and job and job.name == restaurant.job and job.onduty ~= false then
        if job.isboss then return 'owner' end
        local grade = job.grade and (job.grade.level or job.grade) or 0
        return (Config.Permissions.GradeRoles or {})[tonumber(grade) or 0] or 'employee'
    end
    return nil
end

function HasPermission(source, businessId, permission)
    local role = RoleOf(source, businessId)
    local def = role and Config.Permissions.Roles[role]
    if not def then return false end
    for _, perm in ipairs(def.permissions or {}) do
        if perm == 'all' or perm == permission then return true end
    end
    return false
end
exports('HasPermission', HasPermission)

function DB.SaveEmployee(businessId, citizenid, role)
    MySQL.query.await('INSERT INTO pf_restaurant_employees (business_id, citizenid, role) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE role = VALUES(role)', { businessId, citizenid, role })
    DB.RegisterWithGovernment(businessId)   -- the owner may have changed
end
function DB.DeleteEmployee(businessId, citizenid)
    MySQL.query.await('DELETE FROM pf_restaurant_employees WHERE business_id = ? AND citizenid = ?', { businessId, citizenid })
    DB.RegisterWithGovernment(businessId)
end

--- Registers the restaurant with pf-government as restaurant:<id> under its current owner, so its
--- licenses, inspections, closure and business tax apply. Called at start and when the owner changes.
function DB.RegisterWithGovernment(businessId)
    local business = RestaurantData.businesses[businessId]
    if not business then return end
    local ok, err = pcall(function()   -- never let the registry break hiring or start-up
        local owner = MySQL.scalar.await("SELECT citizenid FROM pf_restaurant_employees WHERE business_id = ? AND role = 'owner' ORDER BY citizenid LIMIT 1", { businessId }) or 'unowned'
        TriggerEvent('pf-restaurants:server:registerBusiness', businessId, business.label or businessId, owner, nil)
        if GetResourceState('pf-government') == 'started' then
            local staff = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM pf_restaurant_employees WHERE business_id = ?', { businessId })) or 0
            exports['pf-government']:UpdateBusinessEmployees('restaurant:' .. businessId, staff)
        end
    end)
    if not ok then print(('^3[pf-restaurants]^7 government registration of %s failed: %s'):format(businessId, tostring(err))) end
end


-- ── menus, recipes, orders, state ───────────────────────────────────────────

function DB.SaveMenuItem(businessId, item)
    MySQL.query.await('INSERT INTO pf_restaurant_menu (business_id, menu_item_id, data) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)', { businessId, item.menuItemId, json.encode(item) })
end
function DB.DeleteMenuItem(businessId, menuItemId)
    MySQL.query.await('DELETE FROM pf_restaurant_menu WHERE business_id = ? AND menu_item_id = ?', { businessId, menuItemId })
end
function DB.SaveRecipe(recipe)
    MySQL.query.await('INSERT INTO pf_restaurant_recipes (recipe_id, business_id, data) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)', { recipe.recipeId, recipe.businessId, json.encode(recipe) })
end
function DB.DeleteRecipe(recipeId)
    MySQL.query.await('DELETE FROM pf_restaurant_recipes WHERE recipe_id = ?', { recipeId })
end

function DB.InsertOrder(order)
    return MySQL.insert.await([[INSERT INTO pf_restaurant_orders (order_id, business_id, status, customer_cid, cashier_cid, payment_method, subtotal, tax, total, data, placed_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { order.orderId, order.businessId, order.status, order.customerCid, order.cashierCid, order.paymentMethod, order.subtotal, order.tax, order.total, json.encode(order), nowMs(), nowMs() })
end

--- Moves an order's status only if it is still `from` (one caller wins). Returns true when it did.
function DB.TransitionOrder(order, from, to)
    local changed = MySQL.update.await('UPDATE pf_restaurant_orders SET status = ?, updated_at = ? WHERE order_id = ? AND status = ?', { to, nowMs(), order.orderId, from })
    if not changed or changed < 1 then return false end
    order.status = to
    order.statusHistory = order.statusHistory or {}
    order.statusHistory[#order.statusHistory + 1] = { status = to, timestamp = os.time() }
    MySQL.update.await('UPDATE pf_restaurant_orders SET data = ? WHERE order_id = ?', { json.encode(order), order.orderId })
    return true
end

function DB.SaveState(businessId)
    local business = RestaurantData.businesses[businessId]
    if not business then return end
    MySQL.query.await('INSERT INTO pf_restaurant_state (business_id, hygiene, equipment, updated_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE hygiene = VALUES(hygiene), equipment = VALUES(equipment), updated_at = VALUES(updated_at)',
        { businessId, json.encode(business.hygiene), json.encode(RestaurantData.equipment[businessId] or {}), nowMs() })
end

function DB.LogInspection(businessId, inspectorCid, rating, notes)
    MySQL.insert.await('INSERT INTO pf_restaurant_inspections (business_id, inspector_cid, rating, notes, at) VALUES (?, ?, ?, ?, ?)',
        { businessId, inspectorCid, rating, notes and tostring(notes):sub(1, 255) or nil, nowMs() })
end

-- ── items, freshness and stock stashes ──────────────────────────────────────

local function itemLabel(name)
    return (name:gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

--- Registers every restaurant item the framework does not know yet (ingredients, prep components,
--- dishes, burnt food), and their freshness categories with pfm-inventory.
function DB.RegisterItems()
    local names = {}
    for name in pairs(Config.Items or {}) do names[name] = Config.Items[name] end
    for _, rule in ipairs(Config.ComponentRules or {}) do
        for _, out in ipairs(rule.output or {}) do names[out.item] = names[out.item] or { category = 'meat_cooked' } end
    end
    for _, recipe in pairs(Config.Recipes or {}) do
        if recipe.output and recipe.output.item then names[recipe.output.item] = names[recipe.output.item] or { category = 'final' } end
    end
    names.burnt_food = names.burnt_food or { category = 'waste' }

    local shared = QBCore.Shared.Items or {}
    local missing = {}
    for name, def in pairs(names) do
        if not shared[name] then
            missing[name] = {
                name = name, label = itemLabel(name), weight = 200, type = 'item', image = name .. '.png',
                unique = false, useable = def.isConsumable == true, shouldClose = true,
                description = 'Restaurant ' .. tostring(def.category or 'item'):gsub('_', ' '),
            }
        end
    end
    if next(missing) then
        local ok, err = pcall(function() return exports['pfm-core']:AddItems(missing) end)
        if not ok then print('^1[pf-restaurants]^7 could not register items: ' .. tostring(err)) end
    end

    local perishables = {}
    for name, def in pairs(names) do
        local category = (Config.FreshnessCategories or {})[def.category or '']
        if category then perishables[name] = category end
    end
    pcall(function() exports['pfm-inventory']:RegisterPerishables(perishables) end)
end

local STORAGE_CONDITION = { dry = 'stash', fridge = 'fridge', freezer = 'freezer' }

function StockStashId(businessId, storage)
    return ('restaurant-%s-%s'):format(businessId, storage)
end

--- The storage area an item belongs in.
function StorageFor(item)
    local def = Config.Items and Config.Items[item]
    local storage = def and def.storage or 'dry'
    if not STORAGE_CONDITION[storage] then storage = 'dry' end
    return storage
end

function DB.SetupStashes()
    for businessId, restaurant in pairs(Config.Restaurants) do
        for storage, condition in pairs(STORAGE_CONDITION) do
            local id = StockStashId(businessId, storage)
            local area = restaurant.storage and restaurant.storage[storage] or {}
            exports['pfm-inventory']:CreateInventory(id, {
                label = ('%s %s'):format(restaurant.label or businessId, storage),
                maxweight = (tonumber(area.capacity) or 300) * 1000, slots = 80,
            })
            pcall(function() exports['pfm-inventory']:SetStorageCondition(id, condition) end)
        end
    end
end

-- ── loading ─────────────────────────────────────────────────────────────────

function DB.Load()
    for _, row in ipairs(MySQL.query.await('SELECT business_id, citizenid, role FROM pf_restaurant_employees') or {}) do
        RestaurantData.employees[row.business_id] = RestaurantData.employees[row.business_id] or {}
        RestaurantData.employees[row.business_id][row.citizenid] = { citizenid = row.citizenid, role = row.role }
    end
    for _, row in ipairs(MySQL.query.await('SELECT business_id, data FROM pf_restaurant_menu') or {}) do
        local ok, item = pcall(json.decode, row.data)
        if ok and type(item) == 'table' then
            RestaurantData.menus[row.business_id] = RestaurantData.menus[row.business_id] or {}
            RestaurantData.menus[row.business_id][item.menuItemId] = item
        end
    end
    for _, row in ipairs(MySQL.query.await('SELECT recipe_id, data FROM pf_restaurant_recipes') or {}) do
        local ok, recipe = pcall(json.decode, row.data)
        if ok and type(recipe) == 'table' and not Config.Recipes[row.recipe_id] then RestaurantData.recipes[row.recipe_id] = recipe end
    end
    for _, row in ipairs(MySQL.query.await("SELECT data FROM pf_restaurant_orders WHERE status IN ('pending_payment', 'placed', 'preparing', 'ready')") or {}) do
        local ok, order = pcall(json.decode, row.data)
        if ok and type(order) == 'table' then RestaurantData.orders[order.orderId] = order end
    end
    for _, row in ipairs(MySQL.query.await('SELECT business_id, hygiene, equipment FROM pf_restaurant_state') or {}) do
        local business = RestaurantData.businesses[row.business_id]
        if business then
            local okH, hygiene = pcall(json.decode, row.hygiene or '')
            if okH and type(hygiene) == 'table' then business.hygiene = hygiene end
            local okE, equipment = pcall(json.decode, row.equipment or '')
            if okE and type(equipment) == 'table' and RestaurantData.equipment[row.business_id] then
                for stationId, eq in pairs(equipment) do
                    if RestaurantData.equipment[row.business_id][stationId] then RestaurantData.equipment[row.business_id][stationId] = eq end
                end
            end
        end
    end
end

--- Start: migrations, items, stashes, saved data, and the restaurant buyer for supply orders.
function DB.Boot()
    local ok, err = RunMigrations('pf-restaurants', DB.Migrations)
    if not ok then
        print('^1[pf-restaurants]^7 migrations failed: ' .. tostring(err))
        return false
    end
    DB.RegisterItems()
    DB.SetupStashes()
    DB.Load()
    for businessId in pairs(RestaurantData.businesses) do DB.RegisterWithGovernment(businessId) end
    if RegisterRestaurantSupplies then RegisterRestaurantSupplies() end
    DB.ready = true
    return true
end

--- Cold storage follows the power: when pf-government has cut a restaurant's power, its fridge and
--- freezer keep nothing cold (pfm-inventory 'broken_fridge' rate) until the power is back.
local powerOff = {}
function DB.CheckColdStorage(businessId)
    if GetResourceState('pf-government') ~= 'started' then return end
    local ok, allowed, why = pcall(function() return exports['pf-government']:CanBusinessTrade('restaurant:' .. businessId) end)
    if not ok then return end
    local off = allowed == false and why == 'no_power'
    if off == (powerOff[businessId] == true) then return end
    powerOff[businessId] = off
    for _, storage in ipairs({ 'fridge', 'freezer' }) do
        local condition = off and 'broken_fridge' or STORAGE_CONDITION[storage]
        pcall(function() exports['pfm-inventory']:SetStorageCondition(StockStashId(businessId, storage), condition) end)
    end
end

-- state is saved every minute (hygiene and equipment change continuously); cold storage follows the power
CreateThread(function()
    while true do
        Wait(60000)
        if DB.ready then
            for businessId in pairs(RestaurantData.businesses) do
                pcall(DB.SaveState, businessId)
                pcall(DB.CheckColdStorage, businessId)
            end
        end
    end
end)
