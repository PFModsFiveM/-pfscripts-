-- pf-farming server: persistent plots, growth from timestamps, server-decided positions, yields and
-- prices, money through the pfm-banking ledger (PFPayout).
--
-- Growth is never ticked. A plot stores how many watered seconds it has grown (`grown`) up to
-- `settled_at`, and until when its last watering lasts (`water_until`). At any time t:
--   grown(t)  = grown + max(0, min(t, water_until) - settled_at)     growth pauses while dry
--   dead      = t - water_until > DieAfterDry   (while unripe), or ripe for longer than RotAfterReady
-- So plots keep growing while their owner is offline and survive restarts unchanged.

PFFarm = PFFarm or {}
local F = PFFarm

local RESOURCE = GetCurrentResourceName()
local SYSTEM = 'system:' .. RESOURCE

local function cfg() return Config.Farming end
local function now() return os.time() end

F.Migrations = {
    {
        version = 1,
        name = 'farm plots',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_farm_plots` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(50) NOT NULL,
                `field` VARCHAR(50) NOT NULL,
                `crop` VARCHAR(50) NOT NULL,
                `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
                `planted_at` INT NOT NULL,
                `settled_at` INT NOT NULL,
                `grown` INT NOT NULL DEFAULT 0,
                `water_until` INT NOT NULL,
                `state` VARCHAR(16) NOT NULL DEFAULT 'growing',
                `yield` INT NOT NULL,
                `harvested_at` INT NULL DEFAULT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_field_state` (`field`, `state`),
                KEY `idx_owner_state` (`citizenid`, `state`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

-- ── growth ───────────────────────────────────────────────────────────────────

function F.GrowSeconds(crop) return math.floor((tonumber(crop.growMinutes) or 60) * 60) end

function F.Grown(plot, t)
    local extra = math.min(t, plot.water_until) - plot.settled_at
    return (tonumber(plot.grown) or 0) + math.max(0, extra)
end

--- When the plot became (or becomes) ripe, or nil if it is not on course to ripen in its current water.
function F.RipeAt(plot, crop)
    local need = F.GrowSeconds(crop) - (tonumber(plot.grown) or 0)
    if need <= 0 then return plot.settled_at end
    local at = plot.settled_at + need
    if at <= plot.water_until then return at end
    return nil
end

--- 'growing' | 'ripe' | 'dead' | 'harvested' | 'removed', plus progress 0..1
function F.Status(plot, t)
    if plot.state ~= 'growing' then return plot.state, 1 end
    local crop = cfg().Crops[plot.crop]
    if not crop then return 'dead', 0 end
    local ripeAt = F.RipeAt(plot, crop)
    if ripeAt and ripeAt <= t then
        if t - ripeAt > (cfg().RotAfterReadyMinutes or 240) * 60 then return 'dead', 1 end
        return 'ripe', 1
    end
    if t - plot.water_until > (cfg().DieAfterDryMinutes or 120) * 60 then return 'dead', 0 end
    return 'growing', math.min(1, F.Grown(plot, t) / F.GrowSeconds(crop))
end

-- ── helpers ──────────────────────────────────────────────────────────────────

local lastAction = {}
local function allow(src)
    local t = GetGameTimer()
    local last = lastAction[src]
    if last and t - last < (cfg().ActionCooldownMs or 750) then return false end
    lastAction[src] = t
    return true
end
AddEventHandler('playerDropped', function() lastAction[source] = nil end)

local function playerOf(src) return exports['pfm-core']:GetPlayer(src) end
local function inv() return exports['pfm-inventory'] end
local function notify(src, msg, kind) TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary') end
local function posOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end
local function dist(a, b) return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) end

local function fieldAt(pos)
    for name, field in pairs(cfg().Fields) do
        if dist(pos, field.coords) <= field.radius then return name, field end
    end
end

local function getPlot(id)
    id = tonumber(id)
    if not id or id ~= math.floor(id) or id < 1 then return nil end
    return MySQL.single.await('SELECT * FROM pf_farm_plots WHERE id = ?', { id })
end

-- ── actions ──────────────────────────────────────────────────────────────────

--- Plants a seed where the player stands (the server's view of their position).
function F.Plant(src, cropName)
    if not allow(src) then return { ok = false, error = 'too_fast' } end
    local Player = playerOf(src)
    local crop = type(cropName) == 'string' and cfg().Crops[cropName]
    if not Player or not crop then return { ok = false, error = 'invalid_crop' } end
    local pos = posOf(src)
    local fieldName = pos and fieldAt(pos)
    if not fieldName then return { ok = false, error = 'not_in_field' } end
    local cid = Player.PlayerData.citizenid

    local owned = MySQL.scalar.await("SELECT COUNT(*) FROM pf_farm_plots WHERE citizenid = ? AND state = 'growing'", { cid })
    if (tonumber(owned) or 0) >= (cfg().MaxPlotsPerPlayer or 12) then return { ok = false, error = 'too_many_plots' } end
    local spacing = cfg().MinPlotSpacing or 1.5
    local near = MySQL.query.await([[SELECT x, y, z FROM pf_farm_plots WHERE field = ? AND state = 'growing'
        AND x BETWEEN ? AND ? AND y BETWEEN ? AND ?]], { fieldName, pos.x - spacing, pos.x + spacing, pos.y - spacing, pos.y + spacing }) or {}
    for _, p in ipairs(near) do
        if dist(p, pos) < spacing then return { ok = false, error = 'too_close' } end
    end

    if not inv():RemoveItem(src, crop.seed, 1, false, 'pf-farming:plant') then return { ok = false, error = 'no_seed' } end
    local t = now()
    local yield = math.random(crop.yield[1], crop.yield[2])
    -- planting waters the seed once
    local id = MySQL.insert.await([[INSERT INTO pf_farm_plots (citizenid, field, crop, x, y, z, planted_at, settled_at, grown, water_until, state, yield)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 'growing', ?)]],
        { cid, fieldName, cropName, pos.x, pos.y, pos.z - 1.0, t, t, t + math.floor(crop.waterMinutes * 60), yield })
    if not id then
        inv():AddItem(src, crop.seed, 1, false, nil, 'pf-farming:plant-refund')
        return { ok = false, error = 'db_error' }
    end
    F.BroadcastField(fieldName)
    return { ok = true, data = { id = id } }
end

local function ownPlotInReach(src, plotId)
    local Player = playerOf(src)
    local plot = getPlot(plotId)
    if not Player or not plot or plot.citizenid ~= Player.PlayerData.citizenid then return nil, 'not_your_plot' end
    local pos = posOf(src)
    if not pos or dist(pos, plot) > (cfg().PlantRange or 2.5) + 1.0 then return nil, 'too_far' end
    return plot, nil, Player
end

function F.Water(src, plotId)
    if not allow(src) then return { ok = false, error = 'too_fast' } end
    local plot, err = ownPlotInReach(src, plotId)
    if not plot then return { ok = false, error = err } end
    local t = now()
    local status = F.Status(plot, t)
    if status ~= 'growing' then return { ok = false, error = 'not_growing' } end
    local crop = cfg().Crops[plot.crop]
    if not inv():RemoveItem(src, cfg().WaterItem, 1, false, 'pf-farming:water') then return { ok = false, error = 'no_water' } end
    -- settle the growth so far, then start the new watering; guarded on the values read
    local changed = MySQL.update.await([[UPDATE pf_farm_plots SET grown = ?, settled_at = ?, water_until = ?
        WHERE id = ? AND state = 'growing' AND settled_at = ? AND water_until = ?]],
        { F.Grown(plot, t), t, t + math.floor(crop.waterMinutes * 60), plot.id, plot.settled_at, plot.water_until })
    if not changed or changed < 1 then
        inv():AddItem(src, cfg().WaterItem, 1, false, nil, 'pf-farming:water-refund')
        return { ok = false, error = 'busy' }
    end
    return { ok = true }
end

--- Harvest: the plot is claimed first (one harvest per plot), then the crop is given; if the
--- inventory refuses it the claim is undone.
function F.Harvest(src, plotId)
    if not allow(src) then return { ok = false, error = 'too_fast' } end
    local plot, err, Player = ownPlotInReach(src, plotId)
    if not plot then return { ok = false, error = err } end
    local t = now()
    local status = F.Status(plot, t)
    if status ~= 'ripe' then return { ok = false, error = status == 'dead' and 'dead' or 'not_ripe' } end
    local crop = cfg().Crops[plot.crop]
    if not inv():CanAddItem(src, crop.item, plot.yield) then return { ok = false, error = 'inventory_full' } end
    local claimed = MySQL.update.await("UPDATE pf_farm_plots SET state = 'harvested', harvested_at = ? WHERE id = ? AND citizenid = ? AND state = 'growing'",
        { t, plot.id, Player.PlayerData.citizenid })
    if not claimed or claimed < 1 then return { ok = false, error = 'already_harvested' } end
    if not inv():AddItem(src, crop.item, plot.yield, false, nil, 'pf-farming:harvest') then
        MySQL.update.await("UPDATE pf_farm_plots SET state = 'growing', harvested_at = NULL WHERE id = ? AND state = 'harvested'", { plot.id })
        return { ok = false, error = 'inventory_full' }
    end
    F.BroadcastField(plot.field)
    return { ok = true, data = { item = crop.item, amount = plot.yield } }
end

--- The owner clears a plot (a dead one, or one they no longer want).
function F.Clear(src, plotId)
    if not allow(src) then return { ok = false, error = 'too_fast' } end
    local plot, err, Player = ownPlotInReach(src, plotId)
    if not plot then return { ok = false, error = err } end
    local changed = MySQL.update.await("UPDATE pf_farm_plots SET state = 'removed' WHERE id = ? AND citizenid = ? AND state = 'growing'",
        { plot.id, Player.PlayerData.citizenid })
    if not changed or changed < 1 then return { ok = false, error = 'not_growing' } end
    F.BroadcastField(plot.field)
    return { ok = true }
end

-- ── market ───────────────────────────────────────────────────────────────────

local function atMarket(src)
    local pos = posOf(src)
    return pos and dist(pos, cfg().Market.coords) <= (cfg().MarketRange or 4.0)
end

--- Sells produce to the market. Price per item = market price x freshness share; spoiled produce is
--- refused. Items are taken slot by slot first, then paid once under a fresh ledger key; if the
--- payment fails they are given back with their original freshness.
function F.Sell(src, itemName, amount)
    if not allow(src) then return { ok = false, error = 'too_fast' } end
    local market = cfg().Market
    local price = type(itemName) == 'string' and market.Buys[itemName]
    amount = tonumber(amount)
    if not price then return { ok = false, error = 'not_bought_here' } end
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > (market.MaxPerSale or 500) then return { ok = false, error = 'invalid_amount' } end
    if not atMarket(src) then return { ok = false, error = 'not_at_market' } end

    local slots = inv():GetItemsByName(src, itemName) or {}
    local plan, left, total = {}, amount, 0
    for _, item in ipairs(slots) do
        if left <= 0 then break end
        local fresh = inv():GetFreshness(item.name, item.info)
        local share = fresh and (market.FreshnessPrice or {})[fresh.state] or (fresh == nil and 1.0 or nil)
        if share then
            local n = math.min(left, tonumber(item.amount) or 0)
            if n > 0 then
                -- a private copy of the item's info, to give it back unchanged if the sale fails
                local info = type(item.info) == 'table' and json.decode(json.encode(item.info)) or item.info
                plan[#plan + 1] = { slot = item.slot, amount = n, info = info }
                total = total + n * price * share
                left = left - n
            end
        end
    end
    if left > 0 then return { ok = false, error = 'not_enough_sellable' } end
    total = math.floor(total * 100 + 0.5) / 100
    if total <= 0 then return { ok = false, error = 'worthless' } end

    local taken = {}
    for _, p in ipairs(plan) do
        if not inv():RemoveItem(src, itemName, p.amount, p.slot, 'pf-farming:sell') then
            for _, back in ipairs(taken) do inv():AddItem(src, itemName, back.amount, false, back.info, 'pf-farming:sell-undo') end
            return { ok = false, error = 'items_changed' }
        end
        taken[#taken + 1] = p
    end
    local ok = PFPayout.Pay(src, 'cash', total, { key = 'pf-farming:sale:' .. PFPayout.NewId(), kind = 'sale', reason = 'Produce market: ' .. itemName })
    if not ok then
        for _, back in ipairs(taken) do inv():AddItem(src, itemName, back.amount, false, back.info, 'pf-farming:sell-undo') end
        return { ok = false, error = 'payment_failed' }
    end
    return { ok = true, data = { amount = amount, total = total } }
end

--- Buys seeds at the market: charged first (cash, then bank), refunded under its own key if the
--- seeds do not fit.
function F.BuySeeds(src, cropName, amount)
    if not allow(src) then return { ok = false, error = 'too_fast' } end
    local crop = type(cropName) == 'string' and cfg().Crops[cropName]
    amount = tonumber(amount)
    if not crop then return { ok = false, error = 'invalid_crop' } end
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > 100 then return { ok = false, error = 'invalid_amount' } end
    if not atMarket(src) then return { ok = false, error = 'not_at_market' } end
    if not inv():CanAddItem(src, crop.seed, amount) then return { ok = false, error = 'inventory_full' } end
    local total = crop.seedPrice * amount
    local key = 'pf-farming:seeds:' .. PFPayout.NewId()
    local paidFrom = PFPayout.Charge(src, { 'cash', 'bank' }, total, { key = key, to = SYSTEM, kind = 'purchase', reason = 'Seeds: ' .. crop.label })
    if not paidFrom then return { ok = false, error = 'cannot_afford' } end
    if not inv():AddItem(src, crop.seed, amount, false, nil, 'pf-farming:buy-seeds') then
        PFPayout.Pay(src, paidFrom, total, { key = key .. ':refund', kind = 'refund', reason = 'Seeds not delivered' })
        return { ok = false, error = 'inventory_full' }
    end
    return { ok = true, data = { amount = amount, total = total } }
end

-- ── what clients see ─────────────────────────────────────────────────────────

--- The plots of a field as clients need them: position, crop, stage, and whether it is theirs.
--- Owners' citizen ids are not sent.
function F.FieldView(fieldName, viewerCid, t)
    local rows = MySQL.query.await("SELECT * FROM pf_farm_plots WHERE field = ? AND state = 'growing'", { fieldName }) or {}
    local out = {}
    for _, plot in ipairs(rows) do
        local status, progress = F.Status(plot, t or now())
        out[#out + 1] = {
            id = plot.id, crop = plot.crop, x = plot.x, y = plot.y, z = plot.z,
            status = status, progress = progress, mine = viewerCid ~= nil and plot.citizenid == viewerCid or nil,
        }
    end
    return out
end

function F.BroadcastField(fieldName)
    TriggerClientEvent('pf-farming:client:fieldChanged', -1, fieldName)
end

QBCore = QBCore or exports['pfm-core']:GetCoreObject()

QBCore.Functions.CreateCallback('pf-farming:server:getField', function(src, cb, fieldName)
    local Player = playerOf(src)
    local field = type(fieldName) == 'string' and cfg().Fields[fieldName]
    local pos = posOf(src)
    -- only the field the player is near (no map-wide scraping)
    if not Player or not field or not pos or dist(pos, field.coords) > field.radius + 150.0 then return cb({}) end
    cb(F.FieldView(fieldName, Player.PlayerData.citizenid))
end)

local function reply(src, res, okText)
    if res.ok then notify(src, okText, 'success') else notify(src, 'Farming: ' .. tostring(res.error):gsub('_', ' '), 'error') end
end

RegisterNetEvent('pf-farming:server:water', function(plotId)
    local src = source
    reply(src, F.Water(src, plotId), 'Watered')
end)
RegisterNetEvent('pf-farming:server:harvest', function(plotId)
    local src = source
    local res = F.Harvest(src, plotId)
    reply(src, res, res.ok and ('Harvested %d'):format(res.data.amount) or '')
end)
RegisterNetEvent('pf-farming:server:clear', function(plotId)
    local src = source
    reply(src, F.Clear(src, plotId), 'Plot cleared')
end)

-- commands: everything the server needs comes from its own state, never from the client's position
CreateThread(function()
    while not QBCore.Commands do Wait(100) end
    QBCore.Commands.Add('plant', 'Plant a seed where you stand', { { name = 'crop', help = 'tomato, lettuce, potato, onion, bell_pepper, garlic' } }, true, function(src, args)
        reply(src, F.Plant(src, args[1]), 'Planted')
    end)
    QBCore.Commands.Add('buyseeds', 'Buy seeds at the produce market', { { name = 'crop', help = 'Crop' }, { name = 'amount', help = 'Amount' } }, true, function(src, args)
        local res = F.BuySeeds(src, args[1], args[2])
        reply(src, res, res.ok and ('Bought %d seeds for $%s'):format(res.data.amount, res.data.total) or '')
    end)
    QBCore.Commands.Add('sellproduce', 'Sell produce at the market', { { name = 'item', help = 'Item' }, { name = 'amount', help = 'Amount' } }, true, function(src, args)
        local res = F.Sell(src, args[1], args[2])
        reply(src, res, res.ok and ('Sold %d for $%s'):format(res.data.amount, res.data.total) or '')
    end)
end)

-- ── start ────────────────────────────────────────────────────────────────────

local function registerItems()
    local items = QBCore.Shared and QBCore.Shared.Items or {}
    local missing = {}
    for name, def in pairs(Config.FarmingItems) do
        if not items[name] then
            missing[name] = {
                name = name, label = def.label, weight = def.weight, type = 'item', image = name .. '.png',
                unique = false, useable = false, shouldClose = true, description = def.label,
            }
        end
    end
    if next(missing) then pcall(function() return exports['pfm-core']:AddItems(missing) end) end
    local perishables = {}
    for _, crop in pairs(cfg().Crops) do perishables[crop.item] = 'produce' end
    pcall(function() return inv():RegisterPerishables(perishables) end)
end

function F.Start()
    local ok, err = RunMigrations(RESOURCE, F.Migrations)
    if not ok then
        print('^1[pf-farming]^7 migrations failed: ' .. tostring(err))
        return false
    end
    registerItems()
    F.ready = true
    return true
end

CreateThread(function()
    Wait(1000)
    F.Start()
end)
