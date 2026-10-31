-- Recycling plant job (moved here from [qb]/pfm-recyclejob), and its Recycling app for the tablet
-- and the computer (pf-devices, installed from the App Store).
--
-- The shift: clock in at the desk inside the warehouse, take the package the server points you to,
-- carry it to the sorting table and sort it into materials (inventory), clock out. Every step is
-- checked here: the shift exists, the player stands at the shelf, table, desk or buyer
-- (GetEntityCoords on the server), a package was really picked up and carried for a few seconds,
-- and the shelf is the one the server chose. A request from too far away is refused and logged,
-- never a ban (a lagging player used to be banned).
--
-- Pay: every sorted package adds the level's wage to the shift. The shift is stored in
-- pf_recycle_shifts and paid once on the bank ledger when it ends (clock out, leaving the plant,
-- logging out), with the key pf-jobs:recycle:shift:<shift id>; a shift the bank could not pay is paid
-- at the next clock in or restart under the same key. Materials sold to the buyer inside the plant
-- are paid in cash on the ledger, one key per sale, and handed back if the bank is down.
-- Levels: XP per package (pf_recycle_stats); higher levels earn more per package and sort more
-- materials out of each one.

PFRecycle = PFRecycle or {}
local R = PFRecycle

local QBCore = exports['pfm-core']:GetCoreObject()
-- callbacks recorded for the device apps when server/devices_capture.lua is loaded (as in pf-jobs)
local CreateCallback = PFJobsCallback or QBCore.Functions.CreateCallback
local APP = 'recycle'
-- migration history key of its own: other pf-jobs features keep their own versions
local MIGRATIONS = 'pf-jobs:recycle'

R.Config = {
    OutsideLocation = vector4(55.55, 6472.18, 31.43, 44.0),     -- the door in Paleto Bay
    InsideLocation  = vector4(1073.0, -3102.49, -39.0, 266.61), -- inside the warehouse
    DutyLocation    = vector4(1048.7, -3100.62, -38.2, 88.02),   -- clock in / out desk
    DropLocation    = vector4(1048.224, -3097.071, -38.999, 274.810), -- sorting table
    SellPed         = vector4(1049.84, -3094.08, -40.0, 178.84), -- materials buyer
    SellMaterials = true,          -- the buyer inside the plant pays for materials
    LimitedMaterials = true,       -- the plant has a stock of materials that sorting draws from and sales refill
    StartingStock = 3000,          -- per material, at every restart
    DrawPackageOutline = true,
    PickupSeconds = { 4, 6 },      -- the pick-up bar on the client
    SortSeconds = 5,               -- the sorting bar on the client
    CarrySeconds = { 4, 600 },     -- a package is sorted at least this long and at most this long after pick-up
    PickupBoxModel = 'prop_cs_cardbox_01',
    UseTarget = true,
    ShelfModels = { 'prop_boxpile_05a', 'prop_boxpile_04a', 'prop_boxpile_06b', 'prop_boxpile_02c', 'prop_boxpile_02b', 'prop_boxpile_01a', 'prop_boxpile_08a' },
    Shelves = {
        vector4(1067.68, -3095.57, -39.9, 342.39), vector4(1065.20, -3095.57, -39.9, 342.39), vector4(1062.73, -3095.57, -39.9, 342.39),
        vector4(1060.37, -3095.57, -39.9, 342.39), vector4(1057.95, -3095.57, -39.9, 342.39), vector4(1055.58, -3095.57, -39.9, 342.39),
        vector4(1053.09, -3095.57, -39.9, 342.39), vector4(1053.07, -3102.62, -39.9, 342.39), vector4(1055.49, -3102.62, -39.9, 342.39),
        vector4(1057.93, -3102.62, -39.9, 342.39), vector4(1060.19, -3102.62, -39.9, 342.39), vector4(1062.71, -3102.62, -39.9, 342.39),
        vector4(1065.19, -3102.62, -39.9, 342.39), vector4(1067.46, -3102.62, -39.9, 342.39), vector4(1067.69, -3109.71, -39.9, 342.39),
        vector4(1065.13, -3109.71, -39.9, 342.39), vector4(1062.70, -3109.71, -39.9, 342.39), vector4(1060.24, -3109.71, -39.9, 342.39),
        vector4(1057.76, -3109.71, -39.9, 342.39), vector4(1055.52, -3109.71, -39.9, 342.39), vector4(1053.16, -3109.71, -39.9, 342.39),
    },
    -- what a package sorts into: DrawsPerPackage picks (plus the level bonus), each a random material
    Materials = {
        { item = 'metalscrap', min = 1, max = 5 }, { item = 'plastic', min = 1, max = 5 },
        { item = 'copper', min = 1, max = 5 },     { item = 'rubber', min = 1, max = 5 },
        { item = 'iron', min = 1, max = 5 },       { item = 'aluminum', min = 1, max = 5 },
        { item = 'steel', min = 1, max = 5 },      { item = 'glass', min = 1, max = 5 },
    },
    DrawsPerPackage = { 1, 5 },
    LuckyItem = 'cryptostick', LuckyChance = 20, -- percent per package
    SellPrices = { metalscrap = 2, plastic = 2, copper = 2, rubber = 2, iron = 2, aluminum = 2, steel = 2, glass = 2 },
    MaxSellAmount = 1000,
    WageAccount = 'bank',
    XPPerPackage = 10,
    Levels = {
        { level = 1, xp = 0,    wage = 5,  bonusDraws = 0, label = 'Sorter' },
        { level = 2, xp = 300,  wage = 6,  bonusDraws = 0, label = 'Packer' },
        { level = 3, xp = 1000, wage = 8,  bonusDraws = 1, label = 'Line Hand' },
        { level = 4, xp = 2500, wage = 10, bonusDraws = 1, label = 'Floor Lead' },
        { level = 5, xp = 5000, wage = 12, bonusDraws = 2, label = 'Plant Foreman' },
    },
    Ranges = { desk = 3.0, shelf = 4.0, drop = 5.0, sell = 5.0 },
    StrikesBeforeReport = 3,
}
local cfg = R.Config

R.dbReady = false
local shifts = {}      -- [src] = { id, cid, startedAt, packages, materials = {item = n}, materialCount, wage, xp, target, lastShelf, carrying }
local stats = {}       -- [citizenid] = { xp, packages, materials, wages, sales, shifts }
local strikes = {}     -- [citizenid] = requests from too far away
local cooldowns = {}   -- [src] = { [key] = game timer }
local stock = {}       -- [item] = units in the plant

for _, m in ipairs(cfg.Materials) do stock[m.item] = cfg.StartingStock end

-- ── database ────────────────────────────────────────────────────────────────

R.Migrations = {
    {
        version = 1,
        name = 'recycling plant levels and shifts',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_recycle_stats` (
                `citizenid` VARCHAR(50) NOT NULL,
                `xp` INT NOT NULL DEFAULT 0,
                `packages` INT NOT NULL DEFAULT 0,
                `materials` INT NOT NULL DEFAULT 0,
                `wages` DECIMAL(12,2) NOT NULL DEFAULT 0,
                `sales` DECIMAL(12,2) NOT NULL DEFAULT 0,
                `shifts` INT NOT NULL DEFAULT 0,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_recycle_shifts` (
                `id` VARCHAR(80) NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `started_at` BIGINT NOT NULL,
                `ended_at` BIGINT NULL,
                `packages` INT NOT NULL DEFAULT 0,
                `materials` INT NOT NULL DEFAULT 0,
                `wage` DECIMAL(12,2) NOT NULL DEFAULT 0,
                `status` VARCHAR(12) NOT NULL DEFAULT 'open',
                PRIMARY KEY (`id`),
                INDEX `idx_citizen` (`citizenid`, `started_at`),
                INDEX `idx_status` (`status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

-- Shift status: open (working) -> unpaid (ended, wage not paid yet) -> paid.
R.DB = {
    loadStats = function(cid)
        return MySQL.single.await('SELECT xp, packages, materials, wages, sales, shifts FROM pf_recycle_stats WHERE citizenid = ?', { cid })
    end,
    addStats = function(cid, d)
        MySQL.query.await([[INSERT INTO pf_recycle_stats (citizenid, xp, packages, materials, wages, sales, shifts) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), packages = packages + VALUES(packages), materials = materials + VALUES(materials),
            wages = wages + VALUES(wages), sales = sales + VALUES(sales), shifts = shifts + VALUES(shifts)]],
            { cid, d.xp or 0, d.packages or 0, d.materials or 0, d.wages or 0, d.sales or 0, d.shifts or 0 })
    end,
    openShift = function(id, cid, startedAt)
        MySQL.insert.await("INSERT INTO pf_recycle_shifts (id, citizenid, started_at, status) VALUES (?, ?, ?, 'open')", { id, cid, startedAt })
    end,
    updateShift = function(id, packages, materials, wage)
        MySQL.update.await("UPDATE pf_recycle_shifts SET packages = ?, materials = ?, wage = ? WHERE id = ? AND status = 'open'", { packages, materials, wage, id })
    end,
    endShift = function(id, endedAt)
        return tonumber(MySQL.update.await("UPDATE pf_recycle_shifts SET status = 'unpaid', ended_at = ? WHERE id = ? AND status = 'open'", { endedAt, id })) or 0
    end,
    markPaid = function(id)
        return tonumber(MySQL.update.await("UPDATE pf_recycle_shifts SET status = 'paid' WHERE id = ? AND status = 'unpaid'", { id })) or 0
    end,
    unpaid = function(cid)
        if cid then
            return MySQL.query.await("SELECT id, citizenid, wage FROM pf_recycle_shifts WHERE status = 'unpaid' AND citizenid = ?", { cid }) or {}
        end
        return MySQL.query.await("SELECT id, citizenid, wage FROM pf_recycle_shifts WHERE status = 'unpaid'") or {}
    end,
    closeOpen = function(endedAt)
        MySQL.update.await("UPDATE pf_recycle_shifts SET status = 'unpaid', ended_at = ? WHERE status = 'open'", { endedAt })
    end,
    history = function(cid, limit)
        return MySQL.query.await('SELECT id, started_at, ended_at, packages, materials, wage, status FROM pf_recycle_shifts WHERE citizenid = ? ORDER BY started_at DESC LIMIT ?', { cid, limit }) or {}
    end,
    deleteCharacter = function(cid)
        MySQL.query.await('DELETE FROM pf_recycle_shifts WHERE citizenid = ?', { cid })
        MySQL.query.await('DELETE FROM pf_recycle_stats WHERE citizenid = ?', { cid })
    end,
}

-- ── helpers ─────────────────────────────────────────────────────────────────

local function inv() return exports['pfm-inventory'] end
local function playerOf(src) return exports['pfm-core']:GetPlayer(src) end
local function citizenOf(src)
    local Player = playerOf(src)
    return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end
local function round2(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end
local function notify(src, msg, kind) TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary') end
local function itemDef(name) return (QBCore.Shared and QBCore.Shared.Items or {})[name] end
local function itemLabel(name) local d = itemDef(name) return d and d.label or name end

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

-- Too far from where the request belongs: refused, counted, and logged for staff every few times.
local function strike(src, what)
    local cid = citizenOf(src) or tostring(src)
    strikes[cid] = (strikes[cid] or 0) + 1
    if strikes[cid] % cfg.StrikesBeforeReport == 0 then
        TriggerEvent('qb-log:server:CreateLog', 'recyclejob', 'Request refused', 'orange',
            ('%s (%s) %s from too far away (%d times)'):format(GetPlayerName(src) or '?', QBCore.Functions.GetIdentifier(src, 'license') or '?', what, strikes[cid]), false)
        print(('^3[pf-jobs:recycle]^7 %s refused: %s from too far away'):format(tostring(GetPlayerName(src)), what))
    end
end

function R.LevelFor(xp)
    xp = tonumber(xp) or 0
    local cur, nxt = cfg.Levels[1], nil
    for i, l in ipairs(cfg.Levels) do
        if xp >= l.xp then cur, nxt = l, cfg.Levels[i + 1] end
    end
    return cur, nxt
end

local function getStats(cid)
    if stats[cid] then return stats[cid] end
    local row = R.dbReady and R.DB.loadStats(cid) or nil
    local s = {
        xp = tonumber(row and row.xp) or 0, packages = tonumber(row and row.packages) or 0,
        materials = tonumber(row and row.materials) or 0, wages = tonumber(row and row.wages) or 0,
        sales = tonumber(row and row.sales) or 0, shifts = tonumber(row and row.shifts) or 0,
    }
    stats[cid] = s
    return s
end

local function addStats(cid, d)
    local s = getStats(cid)
    for k, v in pairs(d) do s[k] = round2((s[k] or 0) + v) end
    if R.dbReady then
        local ok, err = pcall(R.DB.addStats, cid, d)
        if not ok then print(('^1[pf-jobs:recycle]^7 stats not saved for %s: %s'):format(cid, tostring(err))) end
    end
end

-- A shelf other than the last one, chosen here (the client used to pick it).
local function assignShelf(s)
    local n = #cfg.Shelves
    local pick
    repeat pick = math.random(1, n) until n < 2 or pick ~= s.lastShelf
    s.target = pick
end

local function countItem(src, item)
    local ok, n = pcall(function() return inv():GetItemCount(src, item) end)
    return ok and tonumber(n) or 0
end

-- Takes `amount` of `item` from every slot it is in (items of different batches do not stack),
-- all of it or none.
local function takeItems(src, item, amount, reason)
    local ok, list = pcall(function() return inv():GetItemsByName(src, item) end)
    local plan, left = {}, amount
    for _, it in ipairs(ok and type(list) == 'table' and list or {}) do
        if left <= 0 then break end
        local n = math.min(left, tonumber(it.amount) or 0)
        if n > 0 then
            plan[#plan + 1] = { slot = it.slot, amount = n, info = type(it.info) == 'table' and json.decode(json.encode(it.info)) or nil }
            left = left - n
        end
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
    return true
end

local function shiftView(s)
    if not s then return nil end
    local list = {}
    for item, n in pairs(s.materials) do list[#list + 1] = { item = item, label = itemLabel(item), amount = n } end
    table.sort(list, function(a, b) return a.amount > b.amount end)
    return {
        active = true, startedAt = s.startedAt, packages = s.packages, materials = list, materialCount = s.materialCount,
        wage = round2(s.wage), xp = s.xp, carrying = s.carrying ~= nil, hasTarget = s.target ~= nil,
    }
end

local function statsView(cid)
    local st = getStats(cid)
    local cur, nxt = R.LevelFor(st.xp)
    return {
        xp = st.xp, level = cur.level, title = cur.label, levelXp = cur.xp, nextXp = nxt and nxt.xp or nil,
        wagePerPackage = cur.wage, bonusDraws = cur.bonusDraws,
        packages = st.packages, materials = st.materials, wages = round2(st.wages), sales = round2(st.sales),
        earned = round2(st.wages + st.sales), shifts = st.shifts,
    }
end

-- The world script (client/recycle.lua) and the open app follow the shift.
local function sendState(src)
    local s = shifts[src]
    TriggerClientEvent('pf-jobs:recycle:state', src, { onShift = s ~= nil, target = s and s.target or nil, carrying = s ~= nil and s.carrying ~= nil })
    if GetResourceState('pf-devices') == 'started' then
        local cid = citizenOf(src)
        pcall(function() exports['pf-devices']:Push(src, APP, 'state', { shift = shiftView(s), stats = cid and statsView(cid) or nil }) end)
    end
end

-- Pays one ended shift (key per shift: a retry or a second caller never pays twice).
local function settle(id, cid, wage, src)
    wage = round2(wage)
    if wage > 0 then
        local ok = PFPayout.Pay(cid, cfg.WageAccount, wage, { key = 'pf-jobs:recycle:shift:' .. id, reason = 'Recycling plant shift', kind = 'wage', quiet = src == nil })
        if not ok then return false end
    end
    local changed = 0
    local okDb, n = pcall(R.DB.markPaid, id)
    if okDb then changed = n end
    if changed > 0 and wage > 0 then addStats(cid, { wages = wage }) end
    return true
end

-- Shifts that ended while the bank was down (or before a restart) are paid now.
local function settleUnpaid(cid, src)
    if not R.dbReady then return 0 end
    local paid = 0
    local ok, rows = pcall(R.DB.unpaid, cid)
    for _, row in ipairs(ok and rows or {}) do
        if settle(row.id, row.citizenid, row.wage, src) then paid = paid + 1 end
    end
    return paid
end

-- ── the shift ───────────────────────────────────────────────────────────────

function R.ClockIn(src)
    local cid = citizenOf(src)
    if not cid then return false, 'no_player' end
    if shifts[src] then return false, 'on_shift' end
    if not R.dbReady then return false, 'unavailable' end
    if not near(src, cfg.DutyLocation, cfg.Ranges.desk) then strike(src, 'clock in') return false, 'too_far' end
    settleUnpaid(cid, src)
    local id = ('%s-%s'):format(cid, PFPayout.NewId())
    local ok = pcall(R.DB.openShift, id, cid, os.time())
    if not ok then return false, 'unavailable' end
    local s = { id = id, cid = cid, startedAt = os.time(), packages = 0, materials = {}, materialCount = 0, wage = 0, xp = 0 }
    assignShelf(s)
    shifts[src] = s
    sendState(src)
    return true
end

--- Ends the shift and pays it. reason: 'desk' | 'left' | 'app' | 'logout'.
function R.ClockOut(src, reason)
    local s = shifts[src]
    if not s then return false, 'off_shift' end
    shifts[src] = nil
    local ended = 0
    local okEnd, n = pcall(R.DB.endShift, s.id, os.time())
    if okEnd then ended = n end
    if ended > 0 then addStats(s.cid, { shifts = 1 }) end
    local paid = settle(s.id, s.cid, s.wage, reason ~= 'logout' and src or nil)
    if reason ~= 'logout' then sendState(src) end
    return true, { packages = s.packages, materials = s.materialCount, wage = round2(s.wage), paid = paid }
end

function R.Pickup(src)
    local s = shifts[src]
    if not s then return false, 'off_shift' end
    if s.carrying then return false, 'carrying' end
    local shelf = s.target and cfg.Shelves[s.target]
    if not shelf then return false, 'no_package' end
    if not near(src, shelf, cfg.Ranges.shelf) then strike(src, 'package pick-up') return false, 'too_far' end
    s.carrying = os.time()
    s.lastShelf, s.target = s.target, nil
    sendState(src)
    return true
end

--- Sorts the carried package into materials at the table. Returns true, { materials, lucky, wage }.
function R.HandIn(src)
    local Player = playerOf(src)
    if not Player then return false, 'no_player' end
    -- carrying a package takes well over 5 s; a repeated request is not looked at
    if onCooldown(src, 'handIn', 5000) then return false, 'cooldown' end
    local s = shifts[src]
    if not s then return false, 'off_shift' end
    if not near(src, cfg.DropLocation, cfg.Ranges.drop) then strike(src, 'package hand-in') return false, 'too_far' end
    local held = s.carrying and (os.time() - s.carrying) or -1
    if held > cfg.CarrySeconds[2] then
        -- dropped somewhere long ago: a new package instead
        s.carrying = nil
        assignShelf(s)
        sendState(src)
        return false, 'no_package'
    end
    if held < cfg.CarrySeconds[1] then return false, 'no_package' end
    s.carrying = nil -- one sorting per package

    local level = R.LevelFor(getStats(s.cid).xp)
    local draws = math.random(cfg.DrawsPerPackage[1], cfg.DrawsPerPackage[2]) + (level.bonusDraws or 0)
    local got, total, outOfStock, full = {}, 0, {}, false
    for _ = 1, draws do
        local m = cfg.Materials[math.random(1, #cfg.Materials)]
        local n = math.random(m.min, m.max)
        if cfg.LimitedMaterials and (stock[m.item] or 0) < n then
            outOfStock[m.item] = true
        elseif inv():AddItem(src, m.item, n, false, false, 'pf-jobs:recycle:sort') then
            if cfg.LimitedMaterials then stock[m.item] = stock[m.item] - n end
            got[m.item] = (got[m.item] or 0) + n
            total = total + n
            TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef(m.item), 'add', n)
        else
            full = true
            break
        end
    end
    local lucky = false
    if cfg.LuckyItem and math.random(1, 100) <= (cfg.LuckyChance or 0) and inv():AddItem(src, cfg.LuckyItem, 1, false, false, 'pf-jobs:recycle:lucky') then
        lucky = true
        TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef(cfg.LuckyItem), 'add', 1)
    end
    for item in pairs(outOfStock) do notify(src, ('%s is out of stock at the plant'):format(itemLabel(item)), 'error') end
    if full then notify(src, 'Your pockets are full: the rest of the package went back on the line', 'error') end

    s.packages = s.packages + 1
    s.wage = round2(s.wage + level.wage)
    s.xp = s.xp + cfg.XPPerPackage
    s.materialCount = s.materialCount + total
    for item, n in pairs(got) do s.materials[item] = (s.materials[item] or 0) + n end
    pcall(R.DB.updateShift, s.id, s.packages, s.materialCount, s.wage)
    local before = R.LevelFor(getStats(s.cid).xp).level
    addStats(s.cid, { xp = cfg.XPPerPackage, packages = 1, materials = total })
    local after = R.LevelFor(getStats(s.cid).xp)
    if after.level > before then notify(src, ('Recycling level %d: %s. Now $%d per package.'):format(after.level, after.label, after.wage), 'success') end
    assignShelf(s)
    sendState(src)
    return true, { materials = got, count = total, lucky = lucky, wage = level.wage }
end

--- Sells materials to the buyer inside the plant, paid in cash on the ledger.
function R.Sell(src, item, amount)
    local Player = playerOf(src)
    if not Player then return false, 'no_player' end
    if not cfg.SellMaterials then return false, 'disabled' end
    if onCooldown(src, 'sell', 2000) then return false, 'cooldown' end
    if not near(src, cfg.SellPed, cfg.Ranges.sell) then strike(src, 'material sale') return false, 'too_far' end
    local price = type(item) == 'string' and cfg.SellPrices[item] or nil
    if not price then return false, 'not_bought' end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > cfg.MaxSellAmount then return false, 'invalid_amount' end
    amount = math.min(amount, countItem(src, item))
    if amount < 1 or not takeItems(src, item, amount, 'pf-jobs:recycle:sell') then return false, 'nothing_to_sell' end
    local total = round2(price * amount)
    local cid = Player.PlayerData.citizenid
    -- one key per sale; if the bank is down the materials are handed back
    local key = ('pf-jobs:recycle:sell:%s:%s'):format(cid, PFPayout.NewId())
    if not PFPayout.Pay(Player, 'cash', total, { key = key, reason = 'Recycled materials sold', kind = 'sale' }) then
        inv():AddItem(src, item, amount, false, false, 'pf-jobs:recycle:sale-refund')
        return false, 'bank_unavailable'
    end
    if cfg.LimitedMaterials then stock[item] = (stock[item] or 0) + amount end
    addStats(cid, { sales = total })
    TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef(item), 'remove', amount)
    return true, { amount = amount, total = total }
end

-- ── what the world script calls ─────────────────────────────────────────────

local MESSAGES = {
    too_far = 'You are too far away', on_shift = 'You are already clocked in', off_shift = 'You are not clocked in',
    unavailable = 'The plant office is closed right now', carrying = 'You are already carrying a package',
    no_package = 'You have no package to sort', not_bought = 'The buyer does not want that', invalid_amount = 'Enter a valid amount',
    nothing_to_sell = 'You have nothing to sell', bank_unavailable = 'The bank did not respond; your materials were handed back',
}

RegisterNetEvent('pf-jobs:recycle:clockIn', function()
    local src = source
    local ok, err = R.ClockIn(src)
    if ok then notify(src, 'You clocked in. Your first package is marked on the shelves.', 'success')
    elseif MESSAGES[err] then notify(src, MESSAGES[err], 'error') end
end)

RegisterNetEvent('pf-jobs:recycle:clockOut', function(left)
    local src = source
    local ok, res = R.ClockOut(src, left == true and 'left' or 'desk')
    if not ok then return end
    if res.wage > 0 and res.paid then
        notify(src, ('You clocked out: %d packages, $%s paid to your bank'):format(res.packages, res.wage), 'success')
    elseif res.wage > 0 then
        notify(src, ('You clocked out: $%s will be paid once the bank answers'):format(res.wage), 'error')
    else
        notify(src, 'You clocked out', 'primary')
    end
end)

RegisterNetEvent('pf-jobs:recycle:pickup', function()
    local src = source
    local ok, err = R.Pickup(src)
    if not ok and MESSAGES[err] then notify(src, MESSAGES[err], 'error') end
end)

RegisterNetEvent('pf-jobs:recycle:handIn', function()
    local src = source
    local ok, res = R.HandIn(src)
    if ok then
        notify(src, ('Package sorted: %d materials (+$%d)'):format(res.count, res.wage), 'success')
    elseif res ~= 'cooldown' and MESSAGES[res] then
        notify(src, MESSAGES[res], 'error')
    end
end)

RegisterNetEvent('pf-jobs:recycle:sell', function(item, amount)
    local src = source
    local ok, res = R.Sell(src, item, amount)
    if ok then
        notify(src, ('You sold %d %s for $%s'):format(res.amount, itemLabel(item), res.total), 'success')
    elseif res ~= 'cooldown' and MESSAGES[res] then
        notify(src, MESSAGES[res], 'error')
    end
end)

-- The buyer's prices, only next to the buyer.
CreateCallback('pf-jobs:recycle:getPriceList', function(source, cb)
    if not playerOf(source) or not cfg.SellMaterials then return cb({}) end
    if not near(source, cfg.SellPed, cfg.Ranges.sell) then strike(source, 'price list') return cb({}) end
    cb(cfg.SellPrices)
end)

-- What the world script needs to build the plant (positions and timings are the server's).
CreateCallback('pf-jobs:recycle:getConfig', function(source, cb)
    local s = shifts[source]
    cb({
        outside = cfg.OutsideLocation, inside = cfg.InsideLocation, desk = cfg.DutyLocation, drop = cfg.DropLocation,
        sellPed = cfg.SellMaterials and cfg.SellPed or nil, shelves = cfg.Shelves, shelfModels = cfg.ShelfModels,
        boxModel = cfg.PickupBoxModel, pickupSeconds = cfg.PickupSeconds, sortSeconds = cfg.SortSeconds,
        outline = cfg.DrawPackageOutline,
        state = { onShift = s ~= nil, target = s and s.target or nil, carrying = s ~= nil and s.carrying ~= nil },
    })
end)

-- ── the Recycling app (pf-devices) ──────────────────────────────────────────

function R.View(src)
    local cid = citizenOf(src)
    if not cid then return { ok = false, error = 'no_player' } end
    local prices = {}
    for _, m in ipairs(cfg.Materials) do
        prices[#prices + 1] = { item = m.item, label = itemLabel(m.item), price = cfg.SellPrices[m.item], stock = cfg.LimitedMaterials and stock[m.item] or nil, have = countItem(src, m.item) }
    end
    local history, owed = {}, 0
    if R.dbReady then
        local ok, rows = pcall(R.DB.history, cid, 6)
        for _, r in ipairs(ok and rows or {}) do
            history[#history + 1] = { startedAt = tonumber(r.started_at), endedAt = tonumber(r.ended_at), packages = tonumber(r.packages) or 0,
                materials = tonumber(r.materials) or 0, wage = tonumber(r.wage) or 0, status = r.status }
            if r.status == 'unpaid' then owed = owed + (tonumber(r.wage) or 0) end
        end
    end
    local levels = {}
    for i, l in ipairs(cfg.Levels) do levels[i] = { level = l.level, xp = l.xp, wage = l.wage, bonusDraws = l.bonusDraws, title = l.label } end
    return {
        ok = true, available = R.dbReady,
        shift = shiftView(shifts[src]),
        stats = statsView(cid),
        levels = levels, xpPerPackage = cfg.XPPerPackage, draws = cfg.DrawsPerPackage,
        prices = prices, sellEnabled = cfg.SellMaterials, limitedStock = cfg.LimitedMaterials,
        history = history, owed = round2(owed),
        plant = { label = 'Recycling plant, Paleto Bay', x = cfg.OutsideLocation.x, y = cfg.OutsideLocation.y },
    }
end

R.Handlers = {
    getInit = function(src) return R.View(src) end,
    -- ending a shift from the device pays what was earned; clocking in needs the desk
    clockOut = function(src)
        local ok, res = R.ClockOut(src, 'app')
        if not ok then return { ok = false, error = res } end
        local view = R.View(src)
        view.summary = res
        return view
    end,
}

function R.RegisterApp()
    if GetResourceState('pf-devices') ~= 'started' then return false end
    local devices = exports['pf-devices']
    local ok, err = devices:RegisterApp({
        id = APP, name = 'Recycling', icon = '♻️', devices = { 'tablet', 'computer' },
        entry = 'html/apps/recycle.js', styles = { 'html/apps/recycle.css' },
        category = 'jobs', order = 34,
        access = { installable = true },
        store = { description = 'The Paleto Bay recycling plant: your shift, the materials you sorted, your pay and level, and the buyer\'s prices.', publisher = 'PF Jobs' },
        window = { width = 900, height = 640 },
        description = 'Recycling plant shifts, materials and levels',
    })
    if ok then ok, err = devices:RegisterAppHandlers(APP, R.Handlers) end
    if not ok then print(('^1[pf-jobs]^7 device app %s not registered: %s'):format(APP, tostring(err))) end
    return ok == true
end

-- ── lifecycle ───────────────────────────────────────────────────────────────

--- Creates the tables, closes shifts a restart interrupted and pays every unpaid shift.
function R.Start()
    local ok, err = exports['pfm-core']:RunMigrations(MIGRATIONS, R.Migrations)
    if not ok then
        print(('^1[pf-jobs:recycle]^7 database not ready (%s): clocking in is off'):format(tostring(err)))
        return false
    end
    R.dbReady = true
    R.Recover()
    return true
end

function R.Recover()
    if not R.dbReady then return 0 end
    pcall(R.DB.closeOpen, os.time())
    return settleUnpaid(nil, nil)
end

CreateThread(function() R.Start() end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then R.RegisterApp() end
end)
AddEventHandler('pf-devices:server:ready', function() R.RegisterApp() end)

-- logging out or leaving ends the shift and pays it
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    if shifts[src] then R.ClockOut(src, 'logout') end
end)
AddEventHandler('playerDropped', function()
    local src = source
    if shifts[src] then R.ClockOut(src, 'logout') end
    cooldowns[src] = nil
end)

-- A deleted character's levels and shift history go with it.
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 then return end
    stats[citizenid], strikes[citizenid] = nil, nil
    for src, s in pairs(shifts) do
        if s.cid == citizenid then shifts[src] = nil end
    end
    local ok, err = pcall(R.DB.deleteCharacter, citizenid)
    if not ok then print(('^1[pf-jobs:recycle]^7 rows of deleted character %s not removed: %s'):format(citizenid, tostring(err))) end
end)

-- test hooks
function R.__reset()
    shifts, stats, strikes, cooldowns = {}, {}, {}, {}
    for _, m in ipairs(cfg.Materials) do stock[m.item] = cfg.StartingStock end
end
function R.__shift(src) return shifts[src] end
function R.__stock() return stock end
