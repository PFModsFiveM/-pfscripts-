-- Vineyard job (moved here from [qb]/pfm-vineyard), and its Vineyard app for the tablet and the
-- computer (pf-devices, for the vineyard job).
--
-- The work: start a picking shift at the vineyard office, pick the vine the server points you to
-- (one vine at a time, never the same one twice in a row, at least 6 s each), press 16 grapes into
-- grape juice at the press (at least 14 s), and ferment 23 grape juice into wine in a barrel at the
-- winery (ready after WineSeconds). Every step needs the vineyard job and the player at the right
-- place (GetEntityCoords on the server); the server keeps every timer.
--
-- Selling: the wholesale buyer pays cash on the ledger (one key per sale, goods handed back if the
-- bank is down). Wine and grape juice are also restaurant supplies (pf-restaurants), so a vineyard
-- worker can sell them to restaurants through the Supplier app (pf-stores player suppliers).
-- Levels: XP per vine, juice batch and barrel (pf_vineyard_stats); higher levels pick more grapes
-- and get more out of each batch. A barrel's ready time is stored too, so it survives a relog or a
-- restart.

PFVineyard = PFVineyard or {}
local V = PFVineyard

local QBCore = exports['pfm-core']:GetCoreObject()
local CreateCallback = PFJobsCallback or QBCore.Functions.CreateCallback
local APP = 'vineyard'
local MIGRATIONS = 'pf-jobs:vineyard'

V.Config = {
    Job = 'vineyard',
    Start  = { coords = vector3(-1928.81, 2059.53, 140.84), size = { 5.5, 3.5 }, heading = 15.0 },  -- vineyard office
    Press  = { coords = vector3(828.76, 2191.16, 52.37), size = { 6.0, 4.0 }, heading = 25.0 },     -- juice press
    Winery = { coords = vector3(-1879.54, 2062.55, 135.92), size = { 9.0, 5.0 }, heading = 20.0 },  -- wine barrels
    Sell   = { enabled = true, coords = vector3(-1487.32, -379.02, 40.16), size = { 3.0, 3.0 }, heading = 35.0,
               prices = { wine = 15, grapejuice = 10 } },
    Vines = {
        vector3(-1875.41, 2100.37, 138.86), vector3(-1908.69, 2107.48, 131.31), vector3(-1866.04, 2112.64, 134.41),
        vector3(-1907.76, 2125.35, 124.03), vector3(-1850.31, 2142.95, 122.30), vector3(-1888.22, 2164.51, 114.81),
        vector3(-1835.52, 2180.59, 104.88), vector3(-1891.98, 2208.35, 94.56),  vector3(-1720.37, 2182.03, 106.18),
        vector3(-1808.52, 2173.14, 107.63), vector3(-1784.22, 2222.80, 92.86),  vector3(-1889.13, 2250.05, 79.63),
        vector3(-1861.16, 2254.32, 81.04),  vector3(-1886.75, 2272.45, 70.81),  vector3(-1845.49, 2274.63, 73.33),
        vector3(-1687.28, 2195.76, 97.87),  vector3(-1741.18, 2173.22, 114.39), vector3(-1743.17, 2141.11, 121.18),
        vector3(-1813.84, 2089.57, 134.21), vector3(-1698.71, 2150.65, 110.41),
    },
    VinesPerShift = { 8, 12 },
    GrapesPerVine = { 8, 12 },
    PickSeconds = { 6, 8 },       -- the picking bar; the server needs at least the first value per vine
    GrapesPerJuice = 16, JuicePerBatch = { 6, 10 },
    JuiceSeconds = { 15, 20 },    -- the pressing bar; the server needs at least JuiceMinSeconds
    JuiceMinSeconds = 14,
    JuicePerWine = 23, WinePerBarrel = { 6, 10 },
    WineSeconds = 180,
    XP = { vine = 5, juice = 10, wine = 25 },
    Levels = {
        { level = 1, xp = 0,    grapeBonus = 0, batchBonus = 0, label = 'Picker' },
        { level = 2, xp = 250,  grapeBonus = 1, batchBonus = 0, label = 'Harvester' },
        { level = 3, xp = 800,  grapeBonus = 2, batchBonus = 1, label = 'Cellar Hand' },
        { level = 4, xp = 2000, grapeBonus = 3, batchBonus = 1, label = 'Vintner' },
        { level = 5, xp = 4500, grapeBonus = 4, batchBonus = 2, label = 'Winemaker' },
    },
    Ranges = { start = 10.0, vine = 5.0, press = 10.0, winery = 10.0, sell = 10.0 },
}
local cfg = V.Config

V.dbReady = false
local shifts = {}     -- [src] = { goal, picked, grapes, target, last, assignedAt (game timer ms), startedAt }
local pressing = {}   -- [src] = os.time() the press was loaded
local barrels = {}    -- [citizenid] = os.time() the wine is ready (also in the database)
local stats = {}      -- [citizenid] = { xp, vines, grapes, juice, wine, sold, shifts }
local cooldowns = {}  -- [src] = { [key] = game timer }

-- ── database ────────────────────────────────────────────────────────────────

V.Migrations = {
    {
        version = 1,
        name = 'vineyard levels, totals and barrels',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_vineyard_stats` (
                `citizenid` VARCHAR(50) NOT NULL,
                `xp` INT NOT NULL DEFAULT 0,
                `vines` INT NOT NULL DEFAULT 0,
                `grapes` INT NOT NULL DEFAULT 0,
                `juice` INT NOT NULL DEFAULT 0,
                `wine` INT NOT NULL DEFAULT 0,
                `sold` DECIMAL(12,2) NOT NULL DEFAULT 0,
                `shifts` INT NOT NULL DEFAULT 0,
                `barrel_ready_at` BIGINT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

V.DB = {
    loadStats = function(cid)
        return MySQL.single.await('SELECT xp, vines, grapes, juice, wine, sold, shifts, barrel_ready_at FROM pf_vineyard_stats WHERE citizenid = ?', { cid })
    end,
    addStats = function(cid, d)
        MySQL.query.await([[INSERT INTO pf_vineyard_stats (citizenid, xp, vines, grapes, juice, wine, sold, shifts) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), vines = vines + VALUES(vines), grapes = grapes + VALUES(grapes),
            juice = juice + VALUES(juice), wine = wine + VALUES(wine), sold = sold + VALUES(sold), shifts = shifts + VALUES(shifts)]],
            { cid, d.xp or 0, d.vines or 0, d.grapes or 0, d.juice or 0, d.wine or 0, d.sold or 0, d.shifts or 0 })
    end,
    -- a barrel is claimed only while none is in it (one caller wins)
    fillBarrel = function(cid, readyAt)
        MySQL.query.await('INSERT IGNORE INTO pf_vineyard_stats (citizenid) VALUES (?)', { cid })
        return tonumber(MySQL.update.await('UPDATE pf_vineyard_stats SET barrel_ready_at = ? WHERE citizenid = ? AND barrel_ready_at IS NULL', { readyAt, cid })) or 0
    end,
    emptyBarrel = function(cid, readyAt)
        return tonumber(MySQL.update.await('UPDATE pf_vineyard_stats SET barrel_ready_at = NULL WHERE citizenid = ? AND barrel_ready_at = ?', { cid, readyAt })) or 0
    end,
    deleteCharacter = function(cid)
        MySQL.query.await('DELETE FROM pf_vineyard_stats WHERE citizenid = ?', { cid })
    end,
}

-- ── helpers ─────────────────────────────────────────────────────────────────

local function inv() return exports['pfm-inventory'] end
local function playerOf(src) return exports['pfm-core']:GetPlayer(src) end
local function round2(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end
local function notify(src, msg, kind) TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary') end
local function itemDef(name) return (QBCore.Shared and QBCore.Shared.Items or {})[name] end
local function itemLabel(name) local d = itemDef(name) return d and d.label or name end

local function worker(src)
    local Player = playerOf(src)
    local job = Player and Player.PlayerData and Player.PlayerData.job
    if not (job and job.name == cfg.Job) then return nil end
    return Player
end

local function near(src, point, range)
    local p = GetEntityCoords(GetPlayerPed(src))
    return #(p - vector3(point.x, point.y, point.z)) <= range
end

local function onCooldown(src, key, ms)
    local now = GetGameTimer()
    local t = cooldowns[src] or {}
    cooldowns[src] = t
    if t[key] and now - t[key] < ms then return true end
    t[key] = now
    return false
end

function V.LevelFor(xp)
    xp = tonumber(xp) or 0
    local cur, nxt = cfg.Levels[1], nil
    for i, l in ipairs(cfg.Levels) do
        if xp >= l.xp then cur, nxt = l, cfg.Levels[i + 1] end
    end
    return cur, nxt
end

local function getStats(cid)
    if stats[cid] then return stats[cid] end
    local row = V.dbReady and V.DB.loadStats(cid) or nil
    local s = {}
    for _, k in ipairs({ 'xp', 'vines', 'grapes', 'juice', 'wine', 'sold', 'shifts' }) do s[k] = tonumber(row and row[k]) or 0 end
    stats[cid] = s
    if row and tonumber(row.barrel_ready_at) then barrels[cid] = tonumber(row.barrel_ready_at) end
    return s
end

local function addStats(cid, d)
    local s = getStats(cid)
    for k, v in pairs(d) do s[k] = round2((s[k] or 0) + v) end
    if V.dbReady then
        local ok, err = pcall(V.DB.addStats, cid, d)
        if not ok then print(('^1[pf-jobs:vineyard]^7 stats not saved for %s: %s'):format(cid, tostring(err))) end
    end
end

local function countItem(src, item)
    local ok, n = pcall(function() return inv():GetItemCount(src, item) end)
    return ok and tonumber(n) or 0
end

-- Takes `amount` of `item` from every slot it is in (juice and wine of different batches do not
-- stack), the least fresh first; all of it or none.
local function takeItems(src, item, amount, reason)
    local ok, list = pcall(function() return inv():GetItemsByName(src, item) end)
    local slots = {}
    for _, it in ipairs(ok and type(list) == 'table' and list or {}) do
        if (tonumber(it.amount) or 0) > 0 then
            local okF, f = pcall(function() return inv():GetFreshness(it.name or item, it.info) end)
            slots[#slots + 1] = { slot = it.slot, amount = tonumber(it.amount), info = type(it.info) == 'table' and json.decode(json.encode(it.info)) or nil,
                pct = okF and type(f) == 'table' and tonumber(f.pct) or 100 }
        end
    end
    table.sort(slots, function(a, b) return a.pct < b.pct end)
    local plan, left = {}, amount
    for _, it in ipairs(slots) do
        if left <= 0 then break end
        local n = math.min(left, it.amount)
        plan[#plan + 1] = { slot = it.slot, amount = n, info = it.info }
        left = left - n
    end
    if left > 0 then return false end
    local taken = {}
    for _, p in ipairs(plan) do
        if not inv():RemoveItem(src, item, p.amount, p.slot, reason) then
            for _, back in ipairs(taken) do inv():AddItem(src, item, back.amount, false, back.info, reason .. '-undo') end
            return false
        end
        taken[#taken + 1] = p
    end
    return true, taken
end

local function giveBack(src, item, taken, reason)
    for _, p in ipairs(taken or {}) do inv():AddItem(src, item, p.amount, false, p.info, reason) end
end

local function nextVine(s)
    local n = #cfg.Vines
    local pick
    repeat pick = math.random(1, n) until n < 2 or pick ~= s.last
    s.target = pick
    s.assignedAt = GetGameTimer()
end

local function shiftView(s)
    if not s then return nil end
    local vine = s.target and cfg.Vines[s.target]
    return { active = true, picked = s.picked, goal = s.goal, grapes = s.grapes, startedAt = s.startedAt,
        vine = vine and { x = vine.x, y = vine.y, z = vine.z } or nil }
end

local function pressView(src)
    local at = pressing[src]
    if not at then return nil end
    return { active = true, startedAt = at, readyIn = math.max(0, cfg.JuiceMinSeconds - (os.time() - at)) }
end

local function barrelView(cid)
    local readyAt = barrels[cid]
    if not readyAt then return nil end
    return { active = true, readyAt = readyAt, readyIn = math.max(0, readyAt - os.time()), ready = os.time() >= readyAt }
end

local function statsView(cid)
    local st = getStats(cid)
    local cur, nxt = V.LevelFor(st.xp)
    return { xp = st.xp, level = cur.level, title = cur.label, levelXp = cur.xp, nextXp = nxt and nxt.xp or nil,
        grapeBonus = cur.grapeBonus, batchBonus = cur.batchBonus,
        vines = st.vines, grapes = st.grapes, juice = st.juice, wine = st.wine, sold = round2(st.sold), shifts = st.shifts }
end

local function sendState(src)
    local Player = playerOf(src)
    local cid = Player and Player.PlayerData.citizenid
    local s = shifts[src]
    TriggerClientEvent('pf-jobs:vineyard:state', src, { onShift = s ~= nil, vine = s and s.target or nil, picked = s and s.picked or 0, goal = s and s.goal or 0,
        pressing = pressing[src] ~= nil, barrel = cid and barrelView(cid) or nil })
    if cid and GetResourceState('pf-devices') == 'started' then
        pcall(function()
            exports['pf-devices']:Push(src, APP, 'state', { shift = shiftView(s), press = pressView(src), barrel = barrelView(cid), stats = statsView(cid) })
        end)
    end
end

-- ── picking ─────────────────────────────────────────────────────────────────

function V.StartShift(src)
    if not worker(src) then return false, 'not_vineyard' end
    if shifts[src] then return false, 'on_shift' end
    if not near(src, cfg.Start.coords, cfg.Ranges.start) then return false, 'too_far' end
    local s = { goal = math.random(cfg.VinesPerShift[1], cfg.VinesPerShift[2]), picked = 0, grapes = 0, startedAt = os.time() }
    nextVine(s)
    shifts[src] = s
    sendState(src)
    return true
end

-- tell = false when the player is leaving (nothing to update on their side)
local function endShift(src, tell)
    local s = shifts[src]
    if not s then return false end
    shifts[src] = nil
    local Player = playerOf(src)
    if Player and s.picked > 0 then addStats(Player.PlayerData.citizenid, { shifts = 1 }) end
    if tell then sendState(src) end
    return true, s
end

function V.EndShift(src) return endShift(src, true) end

--- Picks the vine the server chose. Returns true, { grapes, done }.
function V.Pick(src)
    local Player = worker(src)
    if not Player then return false, 'not_vineyard' end
    local s = shifts[src]
    if not s then return false, 'off_shift' end
    local vine = s.target and cfg.Vines[s.target]
    if not vine then return false, 'off_shift' end
    -- the vine the server pointed to, not any vine nearby (one vine could be picked every 3 s forever)
    if not near(src, vine, cfg.Ranges.vine) then return false, 'wrong_vine' end
    if GetGameTimer() - (s.assignedAt or 0) < cfg.PickSeconds[1] * 1000 then return false, 'too_fast' end
    local cid = Player.PlayerData.citizenid
    local level = V.LevelFor(getStats(cid).xp)
    local amount = math.random(cfg.GrapesPerVine[1], cfg.GrapesPerVine[2]) + (level.grapeBonus or 0)
    if not inv():AddItem(src, 'grape', amount, false, false, 'pf-jobs:vineyard:pick') then
        return false, 'pockets_full' -- the vine stays, nothing is lost
    end
    TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef('grape'), 'add', amount)
    s.picked = s.picked + 1
    s.grapes = s.grapes + amount
    s.last = s.target
    addStats(cid, { xp = cfg.XP.vine, vines = 1, grapes = amount })
    local done = s.picked >= s.goal
    if done then
        endShift(src, true)
    else
        nextVine(s)
        sendState(src)
    end
    return true, { grapes = amount, done = done, picked = s.picked, goal = s.goal }
end

-- ── pressing and fermenting ─────────────────────────────────────────────────

function V.StartJuice(src)
    if not worker(src) then return false, 'not_vineyard' end
    if not near(src, cfg.Press.coords, cfg.Ranges.press) then return false, 'too_far' end
    if pressing[src] then return false, 'busy' end
    if countItem(src, 'grape') < cfg.GrapesPerJuice then return false, 'missing_items' end
    if not takeItems(src, 'grape', cfg.GrapesPerJuice, 'pf-jobs:vineyard:press') then return false, 'missing_items' end
    TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef('grape'), 'remove', cfg.GrapesPerJuice)
    pressing[src] = os.time()
    sendState(src)
    return true
end

function V.CollectJuice(src)
    local Player = worker(src)
    if not Player then return false, 'not_vineyard' end
    local at = pressing[src]
    if not at then return false, 'nothing_pressed' end
    if os.time() - at < cfg.JuiceMinSeconds then return false, 'not_ready' end
    if not near(src, cfg.Press.coords, cfg.Ranges.press) then return false, 'too_far' end
    local cid = Player.PlayerData.citizenid
    local level = V.LevelFor(getStats(cid).xp)
    local amount = math.random(cfg.JuicePerBatch[1], cfg.JuicePerBatch[2]) + (level.batchBonus or 0)
    if not inv():AddItem(src, 'grapejuice', amount, false, false, 'pf-jobs:vineyard:juice') then
        return false, 'pockets_full' -- the juice waits in the press
    end
    pressing[src] = nil
    TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef('grapejuice'), 'add', amount)
    addStats(cid, { xp = cfg.XP.juice, juice = amount })
    sendState(src)
    return true, { juice = amount }
end

function V.LoadWine(src)
    local Player = worker(src)
    if not Player then return false, 'not_vineyard' end
    if not V.dbReady then return false, 'unavailable' end
    if not near(src, cfg.Winery.coords, cfg.Ranges.winery) then return false, 'too_far' end
    local cid = Player.PlayerData.citizenid
    getStats(cid)
    if barrels[cid] then return false, 'busy' end
    if countItem(src, 'grapejuice') < cfg.JuicePerWine then return false, 'missing_items' end
    local ok, taken = takeItems(src, 'grapejuice', cfg.JuicePerWine, 'pf-jobs:vineyard:barrel')
    if not ok then return false, 'missing_items' end
    local readyAt = os.time() + cfg.WineSeconds
    local okDb, changed = pcall(V.DB.fillBarrel, cid, readyAt)
    if not okDb or changed < 1 then
        giveBack(src, 'grapejuice', taken, 'pf-jobs:vineyard:barrel-undo')
        return false, okDb and 'busy' or 'unavailable'
    end
    barrels[cid] = readyAt
    TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef('grapejuice'), 'remove', cfg.JuicePerWine)
    sendState(src)
    return true, { readyAt = readyAt }
end

function V.CollectWine(src)
    local Player = worker(src)
    if not Player then return false, 'not_vineyard' end
    local cid = Player.PlayerData.citizenid
    getStats(cid)
    local readyAt = barrels[cid]
    if not readyAt then return false, 'nothing_pressed' end
    if os.time() < readyAt then return false, 'not_ready' end
    if not near(src, cfg.Winery.coords, cfg.Ranges.winery) then return false, 'too_far' end
    -- emptied once: a second request (or a second session) finds it empty
    local okDb, changed = pcall(V.DB.emptyBarrel, cid, readyAt)
    if not okDb or changed < 1 then return false, okDb and 'nothing_pressed' or 'unavailable' end
    barrels[cid] = nil
    local level = V.LevelFor(getStats(cid).xp)
    local amount = math.random(cfg.WinePerBarrel[1], cfg.WinePerBarrel[2]) + (level.batchBonus or 0)
    if not inv():AddItem(src, 'wine', amount, false, false, 'pf-jobs:vineyard:wine') then
        -- the barrel keeps the wine
        pcall(V.DB.fillBarrel, cid, readyAt)
        barrels[cid] = readyAt
        return false, 'pockets_full'
    end
    TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef('wine'), 'add', amount)
    addStats(cid, { xp = cfg.XP.wine, wine = amount })
    sendState(src)
    return true, { wine = amount }
end

-- ── the wholesale buyer ─────────────────────────────────────────────────────

--- Sells all wine and grape juice the player carries at the buyer, in cash on the ledger.
function V.Sell(src)
    local Player = playerOf(src)
    if not Player then return false, 'no_player' end
    if not (cfg.Sell and cfg.Sell.enabled) then return false, 'disabled' end
    if onCooldown(src, 'sell', 2000) then return false, 'cooldown' end
    if not near(src, cfg.Sell.coords, cfg.Ranges.sell) then return false, 'too_far' end
    local total, removed = 0, {}
    for item, price in pairs(cfg.Sell.prices or {}) do
        local n = countItem(src, item)
        if n > 0 then
            local ok, taken = takeItems(src, item, n, 'pf-jobs:vineyard:sell')
            if ok then
                removed[#removed + 1] = { item = item, amount = n, taken = taken }
                total = total + n * price
                TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef(item), 'remove', n)
            end
        end
    end
    if #removed == 0 then return false, 'nothing_to_sell' end
    total = round2(total)
    local cid = Player.PlayerData.citizenid
    -- one key per sale; if the bank is down the goods are handed back
    local key = ('pf-jobs:vineyard:sell:%s:%s'):format(cid, PFPayout.NewId())
    if not PFPayout.Pay(Player, 'cash', total, { key = key, reason = 'Wine and grape juice sold', kind = 'sale' }) then
        for _, r in ipairs(removed) do giveBack(src, r.item, r.taken, 'pf-jobs:vineyard:sale-refund') end
        return false, 'bank_unavailable'
    end
    addStats(cid, { sold = total })
    return true, { total = total, items = removed }
end

-- ── what the world script calls ─────────────────────────────────────────────

local MESSAGES = {
    not_vineyard = 'I don\'t think I work here...', on_shift = 'You are already picking', off_shift = 'Start a shift at the office first',
    too_far = 'You are too far away', wrong_vine = 'That is not the vine you were sent to', too_fast = 'Take your time picking',
    pockets_full = 'Your pockets are full', missing_items = 'You do not have the right items', busy = 'That is already in use',
    nothing_pressed = 'There is nothing to collect', not_ready = 'It is not ready yet', unavailable = 'The winery is closed right now',
    nothing_to_sell = 'You have nothing to sell', bank_unavailable = 'The bank did not respond; your goods were handed back',
}
local function refuse(src, err) if MESSAGES[err] then notify(src, MESSAGES[err], 'error') end end

RegisterNetEvent('pf-jobs:vineyard:startShift', function()
    local src = source
    local ok, err = V.StartShift(src)
    if ok then notify(src, ('You started your shift: %d vines today. The first one is marked.'):format(shifts[src].goal), 'success') else refuse(src, err) end
end)

RegisterNetEvent('pf-jobs:vineyard:endShift', function()
    local src = source
    if V.EndShift(src) then notify(src, 'Your shift at the vineyard has ended', 'primary') end
end)

RegisterNetEvent('pf-jobs:vineyard:pick', function()
    local src = source
    local ok, res = V.Pick(src)
    if not ok then refuse(src, res) return end
    if res.done then notify(src, ('Shift done: %d vines picked. Press the grapes into juice next.'):format(res.picked), 'success') end
end)

RegisterNetEvent('pf-jobs:vineyard:collectJuice', function()
    local src = source
    local ok, res = V.CollectJuice(src)
    if ok then notify(src, ('You pressed %d grape juice'):format(res.juice), 'success') else refuse(src, res) end
end)

RegisterNetEvent('pf-jobs:vineyard:collectWine', function()
    local src = source
    local ok, res = V.CollectWine(src)
    if ok then notify(src, ('You bottled %d wine'):format(res.wine), 'success') else refuse(src, res) end
end)

RegisterNetEvent('pf-jobs:vineyard:sell', function()
    local src = source
    local ok, res = V.Sell(src)
    if ok then notify(src, ('Sold for $%s'):format(res.total), 'success') elseif res ~= 'cooldown' then refuse(src, res) end
end)

-- The press and the barrel answer the client (it starts its bar only when the grapes are in).
CreateCallback('pf-jobs:vineyard:startJuice', function(source, cb)
    local ok, err = V.StartJuice(source)
    if not ok then refuse(source, err) end
    cb(ok == true)
end)

CreateCallback('pf-jobs:vineyard:loadWine', function(source, cb)
    local ok, res = V.LoadWine(source)
    if ok then notify(source, ('The barrel is fermenting: ready in %d minutes'):format(math.ceil(cfg.WineSeconds / 60)), 'success') else refuse(source, res) end
    cb(ok == true)
end)

CreateCallback('pf-jobs:vineyard:getConfig', function(source, cb)
    local Player = playerOf(source)
    local cid = Player and Player.PlayerData.citizenid
    local s = shifts[source]
    cb({
        job = cfg.Job, start = cfg.Start, press = cfg.Press, winery = cfg.Winery, sell = cfg.Sell.enabled and cfg.Sell or nil,
        vines = cfg.Vines, pickSeconds = cfg.PickSeconds, juiceSeconds = cfg.JuiceSeconds,
        state = { onShift = s ~= nil, vine = s and s.target or nil, picked = s and s.picked or 0, goal = s and s.goal or 0,
            pressing = pressing[source] ~= nil, barrel = cid and barrelView(cid) or nil },
    })
end)

-- ── the Vineyard app (pf-devices) ───────────────────────────────────────────

local function restaurantPrice(item)
    if GetResourceState('pf-restaurants') ~= 'started' then return nil end
    local ok, price = pcall(function() return exports['pf-restaurants']:GetSupplyUnitPrice(item) end)
    return ok and tonumber(price) or nil
end

local function place(label, p) return { label = label, x = p.x, y = p.y } end

function V.View(src)
    local Player = playerOf(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local cid = Player.PlayerData.citizenid
    local st = statsView(cid)
    local prices = {}
    for _, item in ipairs({ 'wine', 'grapejuice' }) do
        prices[#prices + 1] = { item = item, label = itemLabel(item), buyer = cfg.Sell.enabled and cfg.Sell.prices[item] or nil, restaurants = restaurantPrice(item) }
    end
    local levels = {}
    for i, l in ipairs(cfg.Levels) do levels[i] = { level = l.level, xp = l.xp, grapeBonus = l.grapeBonus, batchBonus = l.batchBonus, title = l.label } end
    local places = { place('Vineyard office', cfg.Start.coords), place('Juice press', cfg.Press.coords), place('Winery barrels', cfg.Winery.coords) }
    if cfg.Sell.enabled then places[#places + 1] = place('Wholesale buyer', cfg.Sell.coords) end
    return {
        ok = true, available = V.dbReady,
        shift = shiftView(shifts[src]), press = pressView(src), barrel = barrelView(cid), stats = st, levels = levels,
        carrying = { grape = countItem(src, 'grape'), grapejuice = countItem(src, 'grapejuice'), wine = countItem(src, 'wine') },
        recipe = { grapesPerJuice = cfg.GrapesPerJuice, juicePerWine = cfg.JuicePerWine, wineMinutes = math.ceil(cfg.WineSeconds / 60),
            vinesPerShift = cfg.VinesPerShift, xp = cfg.XP },
        prices = prices, places = places,
        supplierApp = GetResourceState('pf-stores') == 'started',
    }
end

V.Handlers = {
    getInit = function(src) return V.View(src) end,
    -- stopping a shift early from the device; starting one needs the office
    endShift = function(src)
        if not V.EndShift(src) then return { ok = false, error = 'off_shift' } end
        return V.View(src)
    end,
}

function V.RegisterApp()
    if GetResourceState('pf-devices') ~= 'started' then return false end
    local devices = exports['pf-devices']
    local ok, err = devices:RegisterApp({
        id = APP, name = 'Vineyard', icon = '🍇', devices = { 'tablet', 'computer' },
        entry = 'html/apps/vineyard.js', styles = { 'html/apps/vineyard.css' },
        category = 'jobs', order = 35,
        access = { jobs = { [cfg.Job] = 0 } },
        window = { width = 900, height = 640 },
        description = 'Picking shifts, the press, the barrels and where to sell',
    })
    if ok then ok, err = devices:RegisterAppHandlers(APP, V.Handlers) end
    if not ok then print(('^1[pf-jobs]^7 device app %s not registered: %s'):format(APP, tostring(err))) end
    return ok == true
end

-- ── lifecycle ───────────────────────────────────────────────────────────────

function V.Start()
    local ok, err = exports['pfm-core']:RunMigrations(MIGRATIONS, V.Migrations)
    if not ok then
        print(('^1[pf-jobs:vineyard]^7 database not ready (%s): the barrels are closed'):format(tostring(err)))
        return false
    end
    V.dbReady = true
    return true
end

CreateThread(function() V.Start() end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then V.RegisterApp() end
end)
AddEventHandler('pf-devices:server:ready', function() V.RegisterApp() end)

local function forget(src)
    endShift(src, false)
    pressing[src], cooldowns[src] = nil, nil
end
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) forget(src) end)
AddEventHandler('playerDropped', function() forget(source) end)

-- A deleted character's levels, totals and barrel go with it.
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 then return end
    stats[citizenid], barrels[citizenid] = nil, nil
    local ok, err = pcall(V.DB.deleteCharacter, citizenid)
    if not ok then print(('^1[pf-jobs:vineyard]^7 rows of deleted character %s not removed: %s'):format(citizenid, tostring(err))) end
end)

-- test hooks
function V.__reset() shifts, pressing, barrels, stats, cooldowns = {}, {}, {}, {}, {} end
function V.__shift(src) return shifts[src] end
