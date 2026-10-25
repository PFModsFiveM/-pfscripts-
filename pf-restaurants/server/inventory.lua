-- Restaurant stock: real items in the restaurant's stashes (server/persistence.lua), consumed
-- all-or-nothing by cooking, filled by supply deliveries through the shared supply order service.
--
-- (The old version kept "lots" in memory, so a restart reset the stock; any manager could create stock
-- from nothing with a net event; a client could choose the expiry; and expired food was deleted.)

local function inv() return exports['pfm-inventory'] end

local function stashesFor(businessId, item)
    local first = StorageFor(item)
    local order = { first }
    for _, s in ipairs({ 'fridge', 'freezer', 'dry' }) do
        if s ~= first then order[#order + 1] = s end
    end
    local out = {}
    for _, s in ipairs(order) do out[#out + 1] = StockStashId(businessId, s) end
    return out
end

local function freshnessPct(item, info)
    local ok, f = pcall(function() return inv():GetFreshness(item, info) end)
    return (ok and type(f) == 'table' and tonumber(f.pct)) or 100
end

--- Takes every input from the restaurant's stock, oldest first, or nothing at all.
--- inputs = {{ item = name, qty = n }}. Returns ok, consumed (or ok=false, missing item name).
--- consumed = {{ stash, item, qty, slot, info, pct }} (pass it to ReturnIngredients to undo).
function ConsumeIngredients(businessId, inputs)
    if not RestaurantData.businesses[businessId] then return false, 'unknown_business' end
    -- plan: find enough in the stashes for every input before removing anything
    local plan = {}
    for _, input in ipairs(inputs or {}) do
        local need = math.floor(tonumber(input.qty) or 0)
        if need < 1 then return false, input.item end
        local candidates = {}
        for _, stashId in ipairs(stashesFor(businessId, input.item)) do
            local stash = inv():GetInventory(stashId)
            for slot, it in pairs(stash and stash.items or {}) do
                if type(it) == 'table' and it.name == input.item and (tonumber(it.amount) or 0) > 0 then
                    candidates[#candidates + 1] = { stash = stashId, slot = tonumber(it.slot) or slot, amount = tonumber(it.amount), info = it.info, pct = freshnessPct(it.name, it.info) }
                end
            end
        end
        table.sort(candidates, function(a, b) return a.pct < b.pct end) -- use what spoils first
        for _, c in ipairs(candidates) do
            if need <= 0 then break end
            local take = math.min(need, c.amount)
            plan[#plan + 1] = { stash = c.stash, item = input.item, qty = take, slot = c.slot, info = c.info, pct = c.pct }
            need = need - take
        end
        if need > 0 then return false, input.item end
    end
    -- take it; if any removal fails, put back what was taken
    local done = {}
    for _, step in ipairs(plan) do
        if not inv():RemoveItem(step.stash, step.item, step.qty, step.slot, 'pf-restaurants:cook') then
            ReturnIngredients(businessId, done)
            return false, step.item
        end
        done[#done + 1] = step
    end
    for _, s in ipairs({ 'dry', 'fridge', 'freezer' }) do inv():SaveStash(StockStashId(businessId, s)) end
    return true, done
end

--- Puts consumed ingredients back where they came from (failed or abandoned cooking).
function ReturnIngredients(businessId, consumed)
    for _, step in ipairs(consumed or {}) do
        if not inv():AddItem(step.stash, step.item, step.qty, step.slot, step.info, 'pf-restaurants:return') then
            inv():AddItem(step.stash, step.item, step.qty, nil, step.info, 'pf-restaurants:return')
        end
    end
    for _, s in ipairs({ 'dry', 'fridge', 'freezer' }) do inv():SaveStash(StockStashId(businessId, s)) end
end

exports('ConsumeIngredients', ConsumeIngredients)

-- Staff can look at the stock (amounts and freshness per storage area)
QBCore.Functions.CreateCallback('pf-restaurants:server:getInventory', function(source, cb, businessId)
    if type(businessId) ~= 'string' or not RoleOf(source, businessId) then cb({}) return end
    local out = {}
    for _, storage in ipairs({ 'dry', 'fridge', 'freezer' }) do
        local stash = inv():GetInventory(StockStashId(businessId, storage))
        local list = {}
        for _, it in pairs(stash and stash.items or {}) do
            if type(it) == 'table' then
                list[#list + 1] = { item = it.name, quantity = it.amount, quality = math.floor(freshnessPct(it.name, it.info)) }
            end
        end
        out[storage] = list
    end
    cb(out)
end)

-- Staff open a storage area (fridge, freezer, dry store) while standing at it
RegisterNetEvent('pf-restaurants:server:openStorage', function(businessId, storage)
    local src = source
    local restaurant = type(businessId) == 'string' and Config.Restaurants[businessId]
    local area = restaurant and restaurant.storage and restaurant.storage[storage]
    if not area or not RoleOf(src, businessId) then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - area.coords) > 3.0 then return end
    inv():OpenInventory(src, StockStashId(businessId, storage))
end)

-- ── supplies through the shared supply order service (pf-stores) ────────────

local function supplyAccount(businessId) return 'society:restaurant_' .. businessId end

local adapter = {
    canManage = function(src, businessId) return HasPermission(src, businessId, 'supplies.order') end,
    account = function(businessId) return supplyAccount(businessId) end,
    ensureAccount = function(businessId)
        local ok, exists = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount('restaurant_' .. businessId, 'business') end)
        return ok and exists == true
    end,
    -- server prices per unit by item category; only restaurant ingredients can be ordered
    price = function(businessId, cart)
        local lines, total = {}, 0
        local maxQty = tonumber(Config.Supplies.MaxUnitsPerLine) or 200
        for _, entry in ipairs(type(cart) == 'table' and cart or {}) do
            local name = type(entry) == 'table' and type(entry.name) == 'string' and entry.name:lower() or nil
            local def = name and Config.Items[name]
            local unit = def and (Config.Supplies.PricePerUnit or {})[def.category]
            local qty = type(entry) == 'table' and math.floor(tonumber(entry.quantity) or 0) or 0
            if unit and qty >= 1 then
                qty = math.min(qty, maxQty)
                lines[#lines + 1] = { name = name, label = name, quantity = qty, cost = unit, category = def.category }
                total = total + unit * qty
            end
        end
        return lines, math.floor(total * 100 + 0.5) / 100
    end,
    route = function(businessId)
        local restaurant = Config.Restaurants[businessId]
        local receiving = restaurant and restaurant.zones and restaurant.zones.receiving
        local spot = receiving and (receiving.deliverySpawn or receiving.center)
        if not spot or not Config.Supplies.Warehouse then return nil end
        local drop = { x = spot.x, y = spot.y, z = spot.z, w = tonumber(receiving.deliveryHeading) or 0.0 }
        return {
            pickup = { label = Config.Supplies.Warehouse.label, coords = Config.Supplies.Warehouse.coords },
            dropoff = { label = restaurant.label, coords = drop },
            unload = { label = 'Receiving', coords = drop },
            trucking = Config.Supplies.Trucking,
        }
    end,
    -- the delivered goods go into the right storage area, all of it or none
    unpack = function(businessId, lines, _, deliveredAt)
        local added = {}
        for _, l in ipairs(lines or {}) do
            local stashId = StockStashId(businessId, StorageFor(l.name))
            -- perishables come in aged by the time the delivery waited packed (30-minute grace)
            local info = nil
            if deliveredAt then
                local okI, value = pcall(function() return exports['pfm-inventory']:DeliveredInfo(l.name, deliveredAt) end)
                if okI then info = value end
            end
            if not exports['pfm-inventory']:AddItem(stashId, l.name, l.quantity, nil, info, 'pf-restaurants:delivery') then
                for _, a in ipairs(added) do exports['pfm-inventory']:RemoveItem(a.stash, a.item, a.qty, nil, 'pf-restaurants:delivery-undo') end
                return false
            end
            added[#added + 1] = { stash = stashId, item = l.name, qty = l.quantity }
        end
        for _, s in ipairs({ 'dry', 'fridge', 'freezer' }) do exports['pfm-inventory']:SaveStash(StockStashId(businessId, s)) end
        return true
    end,
}
RestaurantSupplyAdapter = adapter

-- for the business computer's Order Supplies: which restaurant a job runs, and what it can order
exports('GetRestaurantForJob', function(job)
    for id, restaurant in pairs(Config.Restaurants or {}) do
        if restaurant.job == job then return id end
    end
    return nil
end)

exports('GetStockStashes', function(businessId)
    if not (Config.Restaurants and Config.Restaurants[businessId]) then return {} end
    return { { area = 'dry', stashId = StockStashId(businessId, 'dry') }, { area = 'fridge', stashId = StockStashId(businessId, 'fridge') },
        { area = 'freezer', stashId = StockStashId(businessId, 'freezer') } }
end)

exports('GetSupplyCatalog', function(businessId)
    local restaurant = Config.Restaurants and Config.Restaurants[businessId]
    if not restaurant then return { items = {} } end
    local shared = QBCore and QBCore.Shared and QBCore.Shared.Items or {}
    local items = {}
    for name, def in pairs(Config.Items or {}) do
        local unit = (Config.Supplies.PricePerUnit or {})[def.category]
        if unit then
            local label = shared[name] and shared[name].label or name:gsub('_', ' ')
            items[#items + 1] = {
                item = name, label = label, category = def.category, caseSize = 1,
                caseContents = '1x ' .. label, pricePerCase = unit, storage = StorageFor(name),
            }
        end
    end
    table.sort(items, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.label < b.label
    end)
    return { items = items, label = restaurant.label, deliveryAvailable = adapter.route(businessId) ~= nil }
end)

function RegisterRestaurantSupplies()
    if GetResourceState('pf-stores') ~= 'started' then return false end
    local ok = pcall(function() exports['pf-stores']:RegisterBuyerKind('restaurant', adapter) end)
    return ok
end

-- pf-stores restarted: register again
AddEventHandler('onResourceStart', function(name)
    if name == 'pf-stores' then
        SetTimeout(2000, function() RegisterRestaurantSupplies() end)
    end
end)

-- Order supplies from the business's bank account (delivered by truckers to the receiving area)
RegisterNetEvent('pf-restaurants:server:orderSupplies', function(businessId, supplyOrder)
    local src = source
    if type(businessId) ~= 'string' or type(supplyOrder) ~= 'table' then return end
    if not HasPermission(src, businessId, 'supplies.order') then
        NotifyPlayer(src, 'No permission to order supplies', 'error')
        return
    end
    if GetResourceState('pf-stores') ~= 'started' then
        NotifyPlayer(src, 'Supply ordering is unavailable right now', 'error')
        return
    end
    local cart = {}
    for _, it in ipairs(type(supplyOrder.items) == 'table' and supplyOrder.items or {}) do
        if type(it) == 'table' then cart[#cart + 1] = { name = it.item, quantity = it.quantity } end
    end
    local ok, res = pcall(function()
        return exports['pf-stores']:CreateOrder(src, { kind = 'restaurant', buyerId = businessId, method = supplyOrder.method == 'pickup' and 'pickup' or 'trucking', cart = cart })
    end)
    res = ok and res or { ok = false, error = 'unavailable' }
    if res.ok then
        NotifyPlayer(src, ('Supply order #%d placed: $%.2f from the business account'):format(res.data.orderId, res.data.total), 'success')
    else
        NotifyPlayer(src, 'Supply order failed: ' .. tostring(res.error), 'error')
    end
end)
