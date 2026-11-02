local QBCore = exports['pfm-core']:GetCoreObject()
PFMech = PFMech or {}

local function cleanPlate(plate)
    return (tostring(plate or ''):gsub('%s+', ''):upper())
end

-- A car with this plate within maxDist of the player, found on the server.
local function nearbyVehicleWithPlate(src, plate, maxDist)
    if plate == '' or #plate > 8 then return nil end
    local pcoords = GetEntityCoords(GetPlayerPed(src))
    for _, veh in ipairs(GetAllVehicles() or {}) do
        if DoesEntityExist(veh) and cleanPlate(GetVehicleNumberPlateText(veh)) == plate
            and #(pcoords - GetEntityCoords(veh)) <= maxDist then
            return veh
        end
    end
    return nil
end

-- The car behind a client-sent net id, if it exists and is within maxDist of the player.
local function vehicleNearPlayer(src, netId, maxDist)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > maxDist then return nil end
    return veh
end

local function isMechanic(src)
    local p = QBCore.Functions.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.job and Config.IsMechanicJob(p.PlayerData.job.name) or false
end

local function notify(src, text, kind)
    TriggerClientEvent('QBCore:Notify', src, text, kind or 'error')
end

-- ============================================================================
-- DPF (rolling coal)
-- ============================================================================
-- Whether a car's DPF is removed: changed here by a mechanic (dpf:remove / dpf:install) or by the
-- owner (setCoalDelete, saved in player_vehicles.mods), and read once from the database for a
-- plate not seen yet. (Three copies of the getCoalState callback used to disagree.)
local CoalState = {} -- [plate] = true removed / false fitted

local function dpfRemoved(plate)
    if plate == '' or #plate > 8 then return false end
    if CoalState[plate] ~= nil then return CoalState[plate] == true end
    local removed = false
    local ok, row = pcall(MySQL.single.await, 'SELECT mods FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    if ok and row and type(row.mods) == 'string' then
        local okj, mods = pcall(json.decode, row.mods)
        removed = okj and type(mods) == 'table' and mods.coalDelete == true
    end
    if CoalState[plate] == nil then CoalState[plate] = removed end
    return CoalState[plate] == true
end
PFMech.DpfRemoved = dpfRemoved

QBCore.Functions.CreateCallback('pf_mech:getCoalState', function(src, cb, plate)
    cb(dpfRemoved(cleanPlate(plate)))
end)

RegisterNetEvent('pf_mech:dpf:remove', function(plate)
    local src = source
    plate = cleanPlate(plate)
    if plate == '' then return end
    local ply = QBCore.Functions.GetPlayer(src); if not ply then return end
    -- Removing a DPF hands out a DPF item, so it needs a mechanic standing at that car. Any plate
    -- string used to be accepted, which gave one free item per made-up plate.
    if not (ply.PlayerData.job and Config.IsMechanicJob(ply.PlayerData.job.name)) then return end
    if not nearbyVehicleWithPlate(src, plate, 10.0) then
        TriggerClientEvent('pf_mech:dpf:result', src, 'remove', false, 'Vehicle not found', plate, false)
        return
    end
    if dpfRemoved(plate) then
        TriggerClientEvent('pf_mech:dpf:result', src, 'remove', false, 'DPF already removed', plate, true)
        return
    end
    CoalState[plate] = true
    ply.Functions.AddItem(Config.DPFItem, 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.DPFItem], 'add')
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, true)
    TriggerClientEvent('pf_mech:dpf:result', src, 'remove', true, 'DPF removed - rolling coal enabled', plate, true)
end)

RegisterNetEvent('pf_mech:dpf:install', function(plate)
    local src = source
    plate = cleanPlate(plate)
    if plate == '' then return end
    local ply = QBCore.Functions.GetPlayer(src); if not ply then return end
    -- the counterpart of removal: a mechanic at that car (any plate used to be switched off)
    if not (ply.PlayerData.job and Config.IsMechanicJob(ply.PlayerData.job.name)) then return end
    if not nearbyVehicleWithPlate(src, plate, 10.0) then
        TriggerClientEvent('pf_mech:dpf:result', src, 'install', false, 'Vehicle not found', plate, true)
        return
    end
    if not dpfRemoved(plate) then
        TriggerClientEvent('pf_mech:dpf:result', src, 'install', false, 'DPF already installed', plate, false)
        return
    end
    if not ply.Functions.GetItemByName('dpf') then
        TriggerClientEvent('pf_mech:dpf:result', src, 'install', false, 'Missing DPF item', plate, true)
        return
    end
    if not ply.Functions.RemoveItem('dpf', 1) then return end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['dpf'], 'remove')
    CoalState[plate] = false
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, false)
    TriggerClientEvent('pf_mech:dpf:result', src, 'install', true, 'DPF installed - rolling coal disabled', plate, false)
end)

-- Rolling coal smoke: the driver of a car with its DPF removed switches it on and off. The server
-- keeps it in the car's 'pfCoal' state bag, so only clients that have the car draw the smoke
-- (client/rolling_coal.lua). The client's net id used to be relayed to every player, three times
-- per request, for any car and as often as a client liked.
local COAL_MIN_INTERVAL = 1 -- seconds between two starts by one player
local CoalOn = {}           -- [vehicle] = src of the driver who started it
local CoalLastStart = {}    -- [src] = os.time()

local function setCoal(veh, on)
    if DoesEntityExist(veh) then Entity(veh).state:set('pfCoal', on == true, true) end
end

RegisterNetEvent('pf_mech:coal:syncStart', function(netId)
    local src = source
    if not (Config.RollingCoal and Config.RollingCoal.enabled) then return end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) or CoalOn[veh] then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    local now = os.time()
    if CoalLastStart[src] and now - CoalLastStart[src] < COAL_MIN_INTERVAL then return end
    if not dpfRemoved(cleanPlate(GetVehicleNumberPlateText(veh))) then return end
    CoalLastStart[src] = now
    CoalOn[veh] = src
    setCoal(veh, true)
end)

RegisterNetEvent('pf_mech:coal:syncStop', function(netId)
    local src = source
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or CoalOn[veh] ~= src then return end
    CoalOn[veh] = nil
    setCoal(veh, false)
end)

--- Ends smoke on cars that are gone or whose starting driver left the seat (run every 2 s).
function PFMech.CoalSweep()
    for veh, src in pairs(CoalOn) do
        if not DoesEntityExist(veh) then
            CoalOn[veh] = nil
        elseif GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then
            CoalOn[veh] = nil
            setCoal(veh, false)
        end
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        PFMech.CoalSweep()
    end
end)

local resource = GetCurrentResourceName()

---@type table<string, boolean>
local BossGrades = Config.BossGrades or {}

-- ============================================================================
-- Helpers
-- ============================================================================

local function json_ok(s)
    if not s or s == '' then return nil end
    local ok, t = pcall(function() return json.decode(s) end)
    if ok then return t end
    return nil
end

local function getNameFromPlayersTable(citizenid)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row then return ('%s'):format(citizenid:sub(1, 6)) end
    local ci = json_ok(row.charinfo) or {}
    local first, last = (ci.firstname or ''), (ci.lastname or '')
    local name = (first ~= '' or last ~= '') and (first .. ' ' .. last) or (ci.firstname or citizenid:sub(1, 6))
    return name
end

-- REPLACE isBoss to respect any allowed mechanic job
local function isBoss(Player)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return false end
    local jobData = Player.PlayerData.job
    local jobName = jobData.name
    if not Config.IsMechanicJob(jobName) then return false end
    if jobData.isboss then return true end
    local grade = tostring(jobData.grade and jobData.grade.level or jobData.grade or 0)
    return BossGrades[grade] == true
end

-- ADD: dynamic business key lookup (used throughout)
local function getPlayerBusiness(Player)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return nil end
    local jobName = Player.PlayerData.job.name
    if not Config.IsMechanicJob(jobName) then return nil end
    return Config.GetBusinessKey(jobName)
end

local function ensureBusiness()
    local bkey = (Config.DEFAULT_BRANDING and Config.DEFAULT_BRANDING.business) or (Config.Job or 'mechanic')
    local row = MySQL.single.await('SELECT business FROM pf_business WHERE business = ? LIMIT 1', { bkey })
    if not row then
        local d = Config.DEFAULT_BRANDING or {}
        MySQL.insert.await(
            'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { bkey, d.name or 'Mechanic Shop', d.primary_color or '#0BA378', d.secondary_color or '#0B2E44', d.logo or '', d.open or 1, d.tax or 0.05 }
        )
    end
end

-- Call this once on resource start (or before first read of pf_business)
local function ensureBusinessRow(business)
    local row = MySQL.single.await('SELECT * FROM pf_business WHERE business = ?', { business })
    if not row then
        MySQL.insert.await(
            'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, tax, open) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { business, DEFAULT_BRANDING.name, DEFAULT_BRANDING.primary_color, DEFAULT_BRANDING.secondary_color, DEFAULT_BRANDING.logo, DEFAULT_BRANDING.tax, DEFAULT_BRANDING.open }
        )
    end
end

-- REMOVE / COMMENT OUT old single-row seeding handler
--[[  (deprecated single business seed)
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    ensureBusinessRow('mechanic')
end)
]]

-- Transform flat pf_pos_items to { [category] = { {id,label,price}, ... } }
local function buildCatalog(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        local cat = r.category or 'General'
        out[cat] = out[cat] or {}
        out[cat][#out[cat] + 1] = { id = r.item_id, label = r.label, price = tonumber(r.price) or 0 }
    end
    return out
end

-- ============================================================================
-- Boot / Seed
-- ============================================================================
-- BUSINESS INITIALIZATION
-- ============================================================================

-- NEW: ensure all businesses (defined before onResourceStart so it can be called)
local function ensureAllBusinesses()
    for _, branding in pairs(Config.BusinessBranding or {}) do
        local row = MySQL.single.await(
            'SELECT business FROM pf_business WHERE business = ? LIMIT 1',
            { branding.business }
        )
        if not row then
            MySQL.insert.await(
                'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax) VALUES (?, ?, ?, ?, ?, ?, ?)',

                {
                    branding.business,
                    branding.name,
                    branding.primary_color,
                    branding.secondary_color,
                    branding.logo or '',
                    branding.open or 1,
                    branding.tax or 0.05
                }
            )
        end
    end
end

-- ============================================================================
-- RESOURCE INITIALIZATION
-- ============================================================================

AddEventHandler('onResourceStart', function(res)
    if res ~= resource then return end
    ensureAllBusinesses()                 -- now seeds all configured shops
    -- Seed POS items per business if empty
    -- ...existing code...
end)

-- ============================================================================
-- Management: GET payload
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:get', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    local businessKey = getPlayerBusiness(Player)
    if not businessKey then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not a mechanic.' })
        return
    end

    -- Branding
    local brand = MySQL.single.await(
        'SELECT name, primary_color, secondary_color, logo, open, tax FROM pf_business WHERE business = ? LIMIT 1',
        { businessKey }
    ) or {}

    -- POS Catalog
    local posRows = MySQL.query.await(
        'SELECT item_id, category, label, price FROM pf_pos_items WHERE business = ? ORDER BY category, label',
        { businessKey }
    ) or {}
    local catalog = buildCatalog(posRows)

    -- Employees list (pf_employees is the roster; online + onduty pulled from framework)
    local empRows = MySQL.query.await(
        'SELECT citizenid, grade, salary, avatar FROM pf_employees WHERE business = ? ORDER BY grade DESC',
        { businessKey }
    ) or {}

    local onlinePlayers = QBCore.Functions.GetQBPlayers()
    local onlineIndex = {}
    for _, p in pairs(onlinePlayers) do
        local pd = p.PlayerData
        if pd and pd.citizenid then onlineIndex[pd.citizenid] = p end
    end

    local employees, onDuty, total = {}, 0, 0
    for _, e in ipairs(empRows) do
        total = total + 1
        local name = getNameFromPlayersTable(e.citizenid)
        local p = onlineIndex[e.citizenid]
        local online = p ~= nil
        local duty = online and p.PlayerData.job and (p.PlayerData.job.onduty == true) or false
        if duty then onDuty = onDuty + 1 end

        employees[#employees + 1] = {
            cid = e.citizenid,
            name = name,
            grade = tonumber(e.grade) or 0,
            salary = tonumber(e.salary) or 0,
            avatar = e.avatar or '',
            online = online,
            duty = duty
        }
    end

    -- Metrics
    local today = MySQL.single.await(
        [[SELECT COALESCE(SUM(amount),0) AS amt, COUNT(*) AS cnt
          FROM pf_sales WHERE business = ? AND DATE(created_at) = CURDATE()]],
        { businessKey }
    ) or { amt = 0, cnt = 0 }

    local month = MySQL.single.await(
        [[SELECT COALESCE(SUM(amount),0) AS amt
          FROM pf_sales WHERE business = ? AND DATE_FORMAT(created_at, '%Y-%m') = DATE_FORMAT(CURDATE(), '%Y-%m')]],
        { businessKey }
    ) or { amt = 0 }

    local weekBars = MySQL.query.await(
        [[SELECT DATE(created_at) AS day, COALESCE(SUM(amount),0) AS total
            FROM pf_sales
            WHERE business = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
            GROUP BY DATE(created_at)
            ORDER BY day ASC]],
        { businessKey }
    ) or {}

    local canEdit = isBoss(Player)

    TriggerClientEvent('pf_mech:mgmt:get:resp', src, {
        canEdit   = canEdit,
        branding  = {},
        catalog   = catalog,
        employees = employees,
        headcount = { on = onDuty, total = total },
        npcOn     = false, -- client overrides with personal toggle
        metrics   = {
            todayTotal  = tonumber(today.amt) or 0,
            todayOrders = tonumber(today.cnt) or 0,
            monthTotal  = tonumber(month.amt) or 0,
            weeklyBars  = weekBars
        }
    })
end)


-- ── Safe defaults (in case Config.DEFAULT_BRANDING is missing) ────────────────
local DEFAULT_BRANDING = (Config and Config.DEFAULT_BRANDING) or {
    name = 'Mechanic Shop',
    primary_color   = '#0BA378',
    secondary_color = '#0B2E44',
    logo = '',
    tax  = 5,   -- percent
    open = 1
}

-- ============================================================================
-- Management: Save Branding
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:saveBranding', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not isBoss(Player) then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not allowed.' })
        return
    end

    local businessKey = getPlayerBusiness(Player)
    if not businessKey then return end

    local branding = Config.BusinessBranding[businessKey] or {}
    local name  = (data and data.name) or branding.name
    local prim  = (data and data.primary_color) or branding.primary_color
    local sec   = (data and data.secondary_color) or branding.secondary_color
    local logo  = (data and data.logo) or ''
    local open  = (data and data.open) and 1 or 0
    local tax   = tonumber(data and data.tax) or (branding.tax or 0.05)

    MySQL.execute.await(
        [[INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            name = VALUES(name), primary_color = VALUES(primary_color), secondary_color = VALUES(secondary_color),
            logo = VALUES(logo), open = VALUES(open), tax = VALUES(tax)]],
        { businessKey, name, prim, sec, logo, open, tax }
    )

    TriggerClientEvent('pf_mech:toast', src, { text = 'Branding saved.' })
    -- Re-send payload so UI updates
    TriggerClientEvent('pf_mech:mgmt:get', src)
end)

-- ============================================================================
-- Management: Update Catalog Price
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:updatePrice', function(payload)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not isBoss(Player) then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not allowed.' })
        return
    end

    local businessKey = getPlayerBusiness(Player)
    if not businessKey then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Invalid job.' })
        return
    end

    local itemId = payload and payload.item_id
    local label  = tostring(payload and payload.label or ''):sub(1, 80)
    local price  = tonumber(payload and payload.price) or 0
    if type(itemId) ~= 'string' or itemId == '' or #itemId > 64 then return end
    -- the register bills from this list: no negative prices
    if price ~= price or price < 0 or price > 10000000 then return end

    local row = MySQL.single.await(
        'SELECT item_id FROM pf_pos_items WHERE business = ? AND item_id = ? LIMIT 1',
        { businessKey, itemId }
    )

    if row then
        MySQL.update.await(
            'UPDATE pf_pos_items SET label = ?, price = ? WHERE business = ? AND item_id = ?',
            { label, price, businessKey, itemId }
        )
    else
        MySQL.insert.await(
            'INSERT INTO pf_pos_items (business, item_id, category, label, price) VALUES (?, ?, ?, ?, ?)',
            { businessKey, itemId, 'General', label, price }
        )
    end

    TriggerClientEvent('pf_mech:toast', src, { text = ('Price updated: %s'):format(label) })
    TriggerClientEvent('pf_mech:mgmt:get', src)
end)

-- ============================================================================
-- Management: Update Employee (grade/salary/avatar)
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:updateEmployee', function(p)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not isBoss(Player) then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not allowed.' })
        return
    end
    if not p or not p.cid then return end

    local businessKey = getPlayerBusiness(Player)
    if not businessKey then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Invalid job.' })
        return
    end

    -- Only someone already working at this shop, at a grade below the caller's own (a boss may
    -- give up to their own grade). Any citizen id used to be accepted, and a mechanic of another
    -- shop could be given any grade.
    if type(p.cid) ~= 'string' or #p.cid > 64 or p.cid == Player.PlayerData.citizenid then return end
    local targetJob
    local Online = QBCore.Functions.GetPlayerByCitizenId(p.cid)
    if Online then
        targetJob = Online.PlayerData.job
    else
        local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { p.cid })
        targetJob = row and json_ok(row.job)
    end
    if type(targetJob) ~= 'table' or targetJob.name ~= Player.PlayerData.job.name then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not an employee of this shop.' })
        return
    end
    local function gradeOf(job) return tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or 0 end
    local myGrade, iAmBoss = gradeOf(Player.PlayerData.job), Player.PlayerData.job.isboss == true
    local grade  = math.floor(tonumber(p.grade) or 0)
    local function below(g) return g < myGrade or (iAmBoss and g == myGrade) end
    if grade < 0 or not below(grade) or not below(gradeOf(targetJob)) then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not allowed.' })
        return
    end
    local salary = math.floor(tonumber(p.salary) or 0)
    if salary < 0 or salary > 100000 then return end
    local avatar = tostring(p.avatar or ''):sub(1, 512)

    MySQL.execute.await(
        [[INSERT INTO pf_employees (citizenid, business, grade, salary, avatar)
            VALUES (?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE grade = VALUES(grade), salary = VALUES(salary), avatar = VALUES(avatar)]],
        { p.cid, businessKey, grade, salary, avatar }
    )

    local Target = QBCore.Functions.GetPlayerByCitizenId(p.cid)
    if Target and Target.PlayerData and Target.PlayerData.job
        and Config.IsMechanicJob(Target.PlayerData.job.name) then
        Target.Functions.SetJob(Target.PlayerData.job.name, grade)
    end

    TriggerClientEvent('pf_mech:toast', src, { text = 'Employee saved.' })
    TriggerClientEvent('pf_mech:mgmt:get', src)
end)

-- ============================================================================
-- POS: request charge / pay
-- ============================================================================

-- The old 'pos:requestCharge' / 'pos:customerPay' handlers were removed. No client or tablet page
-- used them, but any modified client could: customerPay took the whole invoice from the client, so
-- it could name any payer, any seller and any total. Charging goes through register_pos.lua
-- (mechanic:server:chargeCustomer), which prices the bill from the shop's list and needs the
-- customer to accept it.

-- ============================================================================
-- Employee personal earnings (for the “Earnings” app)
-- ============================================================================

RegisterNetEvent('pf_mech:earnings:get', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local cid = Player.PlayerData.citizenid
    -- NPC/local jobs & player jobs should be written to pf_job_history by your job logic.
    -- We aggregate by created_at date.
    local rows = MySQL.query.await(
        [[SELECT DATE(created_at) AS day,
                 COALESCE(SUM(CASE WHEN type='npc' THEN amount ELSE 0 END),0)  AS npc_total,
                 COALESCE(SUM(CASE WHEN type='player' THEN amount ELSE 0 END),0) AS cust_total
            FROM pf_job_history
           WHERE citizenid = ?
           GROUP BY DATE(created_at)
           ORDER BY day ASC
           LIMIT 14]],
        { cid }
    ) or {}

    local today = 0
    local week  = 0
    local month = 0
    local bars  = {}

    for _, r in ipairs(rows) do
        local dayTotal = (tonumber(r.npc_total) or 0) + (tonumber(r.cust_total) or 0)
        bars[#bars+1] = { day = r.day, total = dayTotal }
        -- naive sums (you may want proper date ranges)
        today = dayTotal -- last row assumed latest day
        week  = week + dayTotal
        month = month + dayTotal
    end

    TriggerClientEvent('pf_mech:earnings:resp', src, {
        today = today or 0,
        week  = week  or 0,
        month = month or 0,
        bars  = bars
    })
end)

local function serverClock()
    local h = tonumber(os.date('%H'))
    local m = tonumber(os.date('%M'))
    return h, m
end

local npcEnabled = {}  -- [src] = true/false

RegisterNetEvent('pf_mech:npc:toggle', function(on)
    local src = source
    npcEnabled[src] = on and true or false
    if Config.Debug then
        PFMech.Debug(('[pf-mech] %d npcEnabled=%s'):format(src, tostring(npcEnabled[src])))
    end

    if npcEnabled[src] then
        -- kick a tick for this player
        startNpcFeedFor(src)
    else
        stopNpcFeedFor(src)
    end

    -- (optional) echo state to their UI
    TriggerClientEvent('pf_mech:npc:updateJobs', src, {
        jobsNew = {}, jobsActive = {}, profile = { xp = 0, rank = 1 }, thresholds = { 0, 200, 450, 800 }
    })
end)

RegisterNetEvent('pf_mech:npc:refresh', function()
    local src = source
    -- send current jobs/state
    TriggerClientEvent('pf_mech:npc:updateJobs', src, {
        jobsNew = {}, jobsActive = {}, profile = { xp = 0, rank = 1 }, thresholds = { 0, 200, 450, 800 }
    })
end)

-- Stubbed helpers (replace with your real job logic)
function startNpcFeedFor(src)
    -- TODO: create/assign jobs and push with pf_mech:npc:updateJobs
end
function stopNpcFeedFor(src)
    -- TODO: clear timers / pending jobs
end

AddEventHandler('playerDropped', function()
    local src = source
    npcEnabled[src] = nil
    stopNpcFeedFor(src)
    if PFMech.ForgetMechanicPlayer then PFMech.ForgetMechanicPlayer(src) end
end)

-- ============================================================================
-- Performance parts
-- ============================================================================
-- Which mod a part sets comes from shared/performance_parts.lua, never from the client (one cheap
-- part used to fit any upgrade). Fitted parts are stored per car and slot (pf_mech_fitted_parts),
-- so a part fitted before a restart still comes back out as an item. Parts fitted before that table
-- existed have no row: they can still be taken off, but no item comes back.
local Parts = PFMechParts
local PERF_REACH = 8.0       -- metres from the car to fit a part
local REMOVE_REACH = 7.0     -- metres from the car to take one off (the menu picks one within 6 m)
local PlateBusy = {}         -- [plate] = true while a part change on that car waits on the database

local function playerHasToolbox(src)
    local ply = QBCore.Functions.GetPlayer(src)
    if not ply then return false end
    return ply.Functions.GetItemByName('toolbox') ~= nil
end

for item in pairs(Parts.Items) do
    QBCore.Functions.CreateUseableItem(item, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        if not Config.IsMechanicJob(Player.PlayerData.job.name) then
            TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
            return
        end
        if not playerHasToolbox(source) then
            TriggerClientEvent('QBCore:Notify', source, 'You need a toolbox to do mechanic work', 'error')
            return
        end
        TriggerClientEvent('pf-mechanicjob:client:usePerformanceItem', source, item)
    end)
end

-- The saved props (player_vehicles.mods) follow the server's change, so a part taken off is not
-- back on the next spawn. Only for a car that has a saved row.
local function savePropSlot(plate, def, value)
    if not def.propKey or not tostring(def.propKey):match('^mod%a+$') then return end
    MySQL.update.await(("UPDATE player_vehicles SET mods = JSON_SET(mods, '$.%s', ?) WHERE plate = ? AND JSON_VALID(mods)"):format(def.propKey),
        { value, plate })
end

-- Every client applies the server's mod; the car's owner keeps it in the props it saves.
local function broadcastPart(veh, def, remove)
    local payload = {
        vehicle = NetworkGetNetworkIdFromEntity(veh),
        modType = def.modType,
        modIndex = remove and -1 or def.modIndex,
        isToggle = def.toggle == true,
        remove = remove == true,
    }
    TriggerClientEvent('pf_mech:client:upgradeApplied', -1, payload)
end

local function itemBox(src, item, kind)
    if QBCore.Shared.Items[item] then TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], kind, 1) end
end

-- Checks shared by fitting and removing: a mechanic with a toolbox, at that car, engine off.
local function partWorkCar(src, netId, reach)
    if not isMechanic(src) then notify(src, 'You are not a mechanic!') return nil end
    if not playerHasToolbox(src) then notify(src, 'You need a toolbox to do mechanic work') return nil end
    local veh = vehicleNearPlayer(src, netId, reach)
    if not veh then notify(src, 'No vehicle nearby') return nil end
    if GetIsVehicleEngineRunning(veh) then notify(src, 'Turn the engine off first') return nil end
    local plate = cleanPlate(GetVehicleNumberPlateText(veh))
    if plate == '' or #plate > 8 then return nil end
    if not PFMech.SchemaReady then notify(src, 'The workshop records are not ready yet, try again shortly') return nil end
    if PlateBusy[plate] then notify(src, 'Someone is already working on this car') return nil end
    return veh, plate
end

-- Runs with the plate locked. The part is taken first, then recorded; a failed record gives it back.
local function fitPart(src, veh, plate, itemName, def)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.Functions.GetItemByName(itemName) then
        notify(src, 'Missing required item: ' .. itemName)
        return
    end
    if not Player.Functions.RemoveItem(itemName, 1) then notify(src, 'Failed to remove item: ' .. itemName) return end
    itemBox(src, itemName, 'remove')
    local ok, old = pcall(function()
        local before = MySQL.scalar.await('SELECT item FROM pf_mech_fitted_parts WHERE plate = ? AND slot = ?', { plate, def.slot })
        MySQL.query.await('REPLACE INTO pf_mech_fitted_parts (plate, slot, item, fitted_by) VALUES (?, ?, ?, ?)',
            { plate, def.slot, itemName, Player.PlayerData.citizenid })
        return before
    end)
    if not ok then
        print('^1[pf-mechanicjob]^7 part not recorded: ' .. tostring(old))
        local again = QBCore.Functions.GetPlayer(src)
        if again then again.Functions.AddItem(itemName, 1) itemBox(src, itemName, 'add') end
        notify(src, 'The part could not be recorded; it was not fitted')
        return
    end
    -- the part this one replaces comes back out
    if type(old) == 'string' and old ~= '' then
        local again = QBCore.Functions.GetPlayer(src)
        if again and again.Functions.AddItem(old, 1) then itemBox(src, old, 'add') end
    end
    if def.modType == -101 then Entity(veh).state:set('pfDriftTires', true, true) end
    broadcastPart(veh, def, false)
    if def.propKey then savePropSlot(plate, def, def.toggle and true or def.modIndex) end
    notify(src, 'Upgrade installed', 'success')
end

-- Runs with the plate locked. The fitted part's record is removed first (one taker), then the
-- item is handed over, then the server sets the slot back to stock on every client.
local function removePart(src, veh, plate, slot)
    local def = Parts.Slots[slot]
    local item = MySQL.scalar.await('SELECT item FROM pf_mech_fitted_parts WHERE plate = ? AND slot = ?', { plate, slot })
    local returned
    if type(item) == 'string' and item ~= '' then
        local n = MySQL.update.await('DELETE FROM pf_mech_fitted_parts WHERE plate = ? AND slot = ? AND item = ?', { plate, slot, item })
        if n == 1 then returned = item end
    end
    if returned then
        local Player = QBCore.Functions.GetPlayer(src)
        if not (Player and Player.Functions.AddItem(returned, 1)) then
            -- no room for it: the part stays on the car
            MySQL.query.await('INSERT IGNORE INTO pf_mech_fitted_parts (plate, slot, item) VALUES (?, ?, ?)', { plate, slot, returned })
            notify(src, 'No room in your inventory for the part')
            return
        end
        itemBox(src, returned, 'add')
    end
    if def.modType == -101 then Entity(veh).state:set('pfDriftTires', false, true) end
    broadcastPart(veh, def, true)
    if def.propKey then savePropSlot(plate, def, def.stock) end
    notify(src, returned and ('Removed and returned %s'):format(returned) or 'Removed (no part on record to return)', 'success')
end

-- Fit a performance part: the item decides the mod.
RegisterNetEvent('pf_mech:server:applyPerformanceUpgrade', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local def = Parts.ForItem(data.item)
    if not def then return end
    local veh, plate = partWorkCar(src, data.vehicle, PERF_REACH)
    if not veh then return end
    PlateBusy[plate] = true
    local ok, err = pcall(fitPart, src, veh, plate, data.item, def)
    PlateBusy[plate] = nil
    if not ok then print('^1[pf-mechanicjob]^7 part fit failed: ' .. tostring(err)) end
end)

-- Take a part off (the slot, or the item name of the part in it). The client no longer changes
-- the mod itself: the server does, and only then hands the part over.
RegisterNetEvent('pf-mechanicjob:server:returnUpgradeItem', function(which, vehNetId)
    local src = source
    local slot = Parts.SlotOf(which)
    if not slot then return end
    local veh, plate = partWorkCar(src, vehNetId, REMOVE_REACH)
    if not veh then return end
    PlateBusy[plate] = true
    local ok, err = pcall(removePart, src, veh, plate, slot)
    PlateBusy[plate] = nil
    if not ok then print('^1[pf-mechanicjob]^7 part removal failed: ' .. tostring(err)) end
end)

-- ============================================================================
-- Repairs with parts
-- ============================================================================
-- map partKey -> item name used in inventory
local PartToItem = {
  engine_part = 'engine_part',
  body_part   = 'body_part',
  sparkplugs  = 'sparkplugs',
  carbattery  = 'carbattery',
  alternator  = 'alternator',
  engine_oil  = 'engine_oil',
  oil_filter  = 'oil_filter',
  susp_arm    = 'susp_arm',
  axleparts   = 'axleparts',
  tire_new    = 'tire_new',
  brakes      = 'brake_pads',       -- brakes uses the brake_pads item
  fuel_injector = 'fuel_injector',
  powersteeringpump = 'powersteeringpump',
  radiator    = 'radiator',
  power_steering_fluid = 'power_steering_fluid',
  transmissionfluid = 'transmissionfluid',
  brakefluid  = 'brakefluid',
  coolant     = 'coolant',
}

-- wear names (Entity.state.partDamage, used by the repair kit) -> the part that repairs them
local WearToPart = { oil = 'engine_oil', suspension = 'susp_arm', axle = 'axleparts', brake_pads = 'brakes' }

-- map partKey -> data used when applying repair to clients
local PartApplyInfo = {
  engine_part = { action = 'repair', type = 'engine' },
  body_part   = { action = 'repair', type = 'body' },
  sparkplugs  = { action = 'repair', type = 'sparkplugs' },
  carbattery  = { action = 'repair', type = 'battery' },
  alternator  = { action = 'repair', type = 'alternator' },
  engine_oil  = { action = 'repair', type = 'oil' },
  oil_filter  = { action = 'repair', type = 'oil_filter' },
  susp_arm    = { action = 'repair', type = 'suspension' },
  axleparts   = { action = 'repair', type = 'axle' },
  tire_new    = { action = 'tire',   type = 'tire' },
  brakes      = { action = 'repair', type = 'brakes' },
  fuel_injector = { action = 'repair', type = 'fuel_injector' },
  powersteeringpump = { action = 'repair', type = 'powersteeringpump' },
  radiator    = { action = 'repair', type = 'radiator' },
  power_steering_fluid = { action = 'repair', type = 'power_steering_fluid' },
  transmissionfluid = { action = 'repair', type = 'transmissionfluid' },
  brakefluid  = { action = 'repair', type = 'brakefluid' },
  coolant     = { action = 'repair', type = 'coolant' },
}

local REPAIR_REACH = 7.0     -- the client picks a car within 6 m; a little slack for position sync
local REPAIR_MAX_ITEMS = 10
local VALID_WHEEL = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [45] = true, [47] = true }
local REPAIR_LOG_MAX = 20

-- Item-consuming repairs per car: [vehicle] = { { src, part, item, count, at }, ... }. The roadside
-- job pays only for repairs recorded here on its own car (server/advanced_systems.lua).
PFMech.RepairLog = PFMech.RepairLog or {}

-- The repair kit is a public item (Config.PublicItems): with it and a toolbox anyone may fit their
-- own parts. Everything else is mechanic work.
local function mayRepair(Player)
    local job = Player.PlayerData.job
    if job and Config.IsMechanicJob(job.name) then return true end
    return Player.Functions.GetItemByName('repair_kit') ~= nil and Player.Functions.GetItemByName('toolbox') ~= nil
end

-- callback used by client to attempt a repair (consumes items and broadcasts apply). Only known
-- parts, a sane amount, a mechanic (or a repair kit holder) standing at the car; nothing is taken
-- before all of that is checked. Any item name, any car on the map and anyone used to pass.
QBCore.Functions.CreateCallback('pf_mech:server:attemptRepair', function(source, cb, vehNetId, partKey, needed, wheel)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb(false, 'Player not found'); return end

    if type(partKey) ~= 'string' then cb(false, 'Unknown part'); return end
    partKey = WearToPart[partKey] or partKey
    local itemName = PartToItem[partKey]
    if not itemName then cb(false, 'Unknown part'); return end
    local count = needed == nil and 1 or tonumber(needed)
    if not count or count ~= math.floor(count) or count < 1 or count > REPAIR_MAX_ITEMS then cb(false, 'Invalid amount'); return end
    if wheel ~= nil then
        wheel = tonumber(wheel)
        if not wheel or not VALID_WHEEL[wheel] then cb(false, 'Invalid wheel'); return end
    end
    if not mayRepair(Player) then cb(false, 'You are not a mechanic'); return end
    local veh = vehicleNearPlayer(src, vehNetId, REPAIR_REACH)
    if not veh then cb(false, 'The vehicle must be right next to you'); return end

    local item = Player.Functions.GetItemByName(itemName)
    if not item or (item.amount or 0) < count then
        cb(false, 'You do not have enough items')
        return
    end

    local removed = Player.Functions.RemoveItem(itemName, count)
    if not removed then
        cb(false, 'Failed to remove items')
        return
    end
    local now = os.time()
    -- work orders finished through the diagnostics menu use the part spent here (work_orders.lua)
    PFMech.RecentRepairs = PFMech.RecentRepairs or {}
    PFMech.RecentRepairs[src] = { item = itemName, at = now, veh = veh }
    local log = PFMech.RepairLog[veh] or {}
    log[#log + 1] = { src = src, part = partKey, item = itemName, count = count, at = now }
    if #log > REPAIR_LOG_MAX then table.remove(log, 1) end
    PFMech.RepairLog[veh] = log

    -- the car's saved wear first, or a later load would undo the repair
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local state = Entity(veh).state
    local damage = {}
    for k, v in pairs(type(state.partDamage) == 'table' and state.partDamage or {}) do damage[k] = v end

    -- Repair the specific part
    if partKey == 'alternator' then
        damage.alternator = 0
    elseif partKey == 'engine_oil' then
        damage.oil = 0
    elseif partKey == 'oil_filter' then
        damage.oil_filter = 0
    elseif partKey == 'carbattery' then
        damage.carbattery = 0
    elseif partKey == 'sparkplugs' then
        damage.sparkplugs = math.max(0, (damage.sparkplugs or 0) - (20 * count))
    elseif partKey == 'brakes' then
        damage.brakes = math.max(0, (damage.brakes or 0) - (25 * count))
    elseif partKey == 'susp_arm' then
        damage.suspension = math.max(0, (damage.suspension or 0) - (25 * count))
    elseif partKey == 'axleparts' then
        damage.axle = math.max(0, (damage.axle or 0) - (25 * count))
    elseif partKey == 'fuel_injector' then
        damage.fuel_injector = math.max(0, (damage.fuel_injector or 0) - (25 * count))
    elseif partKey == 'powersteeringpump' then
        damage.powersteeringpump = 0
    elseif partKey == 'radiator' then
        damage.radiator = 0
    elseif partKey == 'power_steering_fluid' then
        damage.power_steering_fluid = 0
    elseif partKey == 'transmissionfluid' then
        damage.transmissionfluid = 0
    elseif partKey == 'brakefluid' then
        damage.brakefluid = 0
    elseif partKey == 'coolant' then
        damage.coolant = 0
    elseif partKey == 'engine_part' then
        -- Engine part: fully restore (diagnostics calculated exact parts needed)
        damage.engine_part = 0
    elseif partKey == 'body_part' then
        -- Body part: fully restore (diagnostics calculated exact parts needed)
        damage.body_part = 0
    end

    state:set('partDamage', damage, true)
    -- the driver's wear reports computed before this repair are refused from now on
    if PFMech and PFMech.MarkWearRepaired then PFMech.MarkWearRepaired(veh) end

    local info = PartApplyInfo[partKey]
    local toast = ('%s x%d used'):format(item.label or itemName, count)
    local payload = { net = NetworkGetNetworkIdFromEntity(veh), action = info.action, type = info.type, toast = toast, wheel = wheel, qty = count }

    TriggerClientEvent('pf_mech:applyPart', -1, payload)

    cb(true, 'Repair completed')
end)

-- (The 'pf_mech:usePart' event was removed: no client sent it, and it repaired any car beside the
-- sender with a part item, without a job check.)

RegisterNetEvent('pf_mech:server:removeMod', function(item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(item) ~= 'string' then return end

    if Player.Functions.RemoveItem(item, 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], "remove")
    end
end)

-- ============================================================================
-- Cosmetic mods
-- ============================================================================
-- Each cosmetic item and the mod types it may set (the same lists as client/main.lua
-- CosmeticItemMap and client/cosmetics.lua). Any item and any mod type used to be accepted, so a
-- bottle of water could fit engine level 4, or strip another player's paid upgrades.
local CosmeticMods = {
    spoiler = { 0 }, bumper = { 1, 2 }, vehicle_bumper = { 1, 2 }, skirts = { 3 }, exhaust = { 4 },
    rollcage = { 5 }, grille = { 6 }, hood = { 7 }, fenders = { 8 }, roof = { 10 },
    externals = { 6, 8, 9, 10, 45 },
    internals = { 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40 },
    livery = { 46 }, customplate = { 25, 48 }, seat = { 31 }, horn = { 14 }, rims = { 23 },
}
-- never through a cosmetic item: engine, brakes, transmission, suspension, armour, turbo, xenon
local PERFORMANCE_MOD_TYPES = { [11] = true, [12] = true, [13] = true, [15] = true, [16] = true, [18] = true, [22] = true }
local MOD_INDEX_MAX = 255
local COSMETIC_REACH = 8.0

local function cosmeticAllowed(item, modType)
    if PERFORMANCE_MOD_TYPES[modType] then return false end
    for _, t in ipairs(CosmeticMods[item] or {}) do if t == modType then return true end end
    return false
end
PFMech.CosmeticAllowed = cosmeticAllowed

-- Server-side: apply cosmetic mod (called from client after progress completes)
RegisterNetEvent('pf_mech:server:applyMod', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' then return end
    local itemName = data.item
    local modType, modIndex = tonumber(data.modType), tonumber(data.modIndex)
    if type(itemName) ~= 'string' or not CosmeticMods[itemName] then return end
    if not modType or not modIndex or modType ~= math.floor(modType) or modIndex ~= math.floor(modIndex) then return end
    if modIndex < -1 or modIndex > MOD_INDEX_MAX or not cosmeticAllowed(itemName, modType) then return end
    if not isMechanic(src) then notify(src, 'You are not a mechanic!') return end
    -- every client applies this to the car, so it must be one the player is working on
    local veh = vehicleNearPlayer(src, data.vehicle, COSMETIC_REACH)
    if not veh then return end
    if GetIsVehicleEngineRunning(veh) then notify(src, 'Turn engine off first') return end

    if not Player.Functions.GetItemByName(itemName) then
        notify(src, 'Missing required item: ' .. itemName)
        return
    end
    if not Player.Functions.RemoveItem(itemName, 1) then
        notify(src, 'Failed to remove item: ' .. itemName)
        return
    end

    TriggerClientEvent('pf_mech:client:modApplied', -1, {
        vehicle = NetworkGetNetworkIdFromEntity(veh),
        modType = modType,
        modIndex = modIndex
    })
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
end)

-- (Paint and tint are server/cosmetics.lua. The 'pf_mech:server:applyPaint' copy that was here
-- needed a field no client sends, and 'pf_mech:server:applyWheels' had no client: both removed.)

-- ============================================================================
-- SERVICE BOOK
-- ============================================================================
-- One handler each (a first copy of the save handler called an undefined function and always
-- failed, so books were never locked; the history was readable for any plate). An entry is written
-- by a mechanic at that car with a service book, which the first entry locks to the car; who
-- serviced it, where and the mileage come from the server. The history is read by a mechanic at
-- the car, the car's owner, or whoever holds the book locked to it.
local SERVICE_REACH = 10.0
local SERVICE_RATE_SECONDS = 10
local ServiceLast = {}  -- [src] = os.time() of the last entry

local function text(v, max)
    if type(v) == 'number' then v = tostring(v) end
    if type(v) ~= 'string' then return '' end
    return (v:gsub('^%s+', ''):gsub('%s+$', '')):sub(1, max)
end

local function shopLabel(job)
    local key = Config.GetBusinessKey(job.name)
    local b = Config.BusinessBranding and Config.BusinessBranding[key]
    return (b and b.name) or job.label or job.name
end

local function charName(Player)
    local ci = Player.PlayerData.charinfo or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or Player.PlayerData.citizenid
end

local function bookLock(it)
    return type(it) == 'table' and type(it.info) == 'table' and it.info.lockedPlate or nil
end

-- The service book in that slot, or the first one that is free or locked to this plate.
-- Returns item, slot; or nil and the plate a chosen book is locked to.
local function serviceBookFor(Player, plate, slot)
    local items = Player.PlayerData.items or {}
    slot = tonumber(slot)
    local chosen = slot and items[slot]
    if type(chosen) == 'table' and chosen.name == 'service_book' then
        local locked = bookLock(chosen)
        if locked and locked ~= plate then return nil, locked end
        return chosen, slot
    end
    for s, it in pairs(items) do
        if type(it) == 'table' and it.name == 'service_book' then
            local locked = bookLock(it)
            if not locked or locked == plate then return it, tonumber(it.slot) or tonumber(s) end
        end
    end
    return nil
end

local function holdsBookFor(Player, plate)
    for _, it in pairs(Player.PlayerData.items or {}) do
        if type(it) == 'table' and it.name == 'service_book' and bookLock(it) == plate then return true end
    end
    return false
end

-- Locks the book to the car: its info gets lockedPlate.
local function lockBook(src, Player, slot, book, plate)
    local info = {}
    if type(book.info) == 'table' then for k, v in pairs(book.info) do info[k] = v end end
    info.lockedPlate = plate
    local ok, set = pcall(function() return exports['pfm-inventory']:SetItemData(src, 'service_book', 'info', info, slot) end)
    if ok and set then return end
    -- an inventory without SetItemData: the book is swapped for a locked copy in the same slot
    if Player.Functions.RemoveItem('service_book', 1, slot) then
        if not Player.Functions.AddItem('service_book', 1, slot, info) then Player.Functions.AddItem('service_book', 1, nil, info) end
    end
end

RegisterNetEvent('pf_mech:service:addEntry', function(plate, data, slot)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' then return end
    if not isMechanic(src) then notify(src, 'Not a mechanic') return end
    plate = cleanPlate(plate)
    local veh = nearbyVehicleWithPlate(src, plate, SERVICE_REACH)
    if not veh then notify(src, 'The car must be right here') return end
    local book, bookSlot = serviceBookFor(Player, plate, slot)
    if not book then
        notify(src, bookSlot and ('This service book is locked to %s'):format(bookSlot) or 'You need a service book')
        return
    end
    local now = os.time()
    if ServiceLast[src] and now - ServiceLast[src] < SERVICE_RATE_SECONDS then
        notify(src, 'Wait a moment before writing another entry')
        return
    end

    local title       = text(data.title, 80)
    local serviceText = text(data.service, 2000)
    local svcdesc     = text(data.service_description, 2000)
    local model       = text(data.model, 60)
    local paint       = text(data.paint, 120)
    if title == '' or serviceText == '' then
        notify(src, 'Required fields missing')
        return
    end
    ServiceLast[src] = now
    local shop = shopLabel(Player.PlayerData.job)
    local servicedBy = ('%s (%s)'):format(charName(Player), shop):sub(1, 80)
    local mileage = math.floor(math.max(0, math.min(2147483647, tonumber(Entity(veh).state.mileage) or 0)))

    MySQL.insert.await(
        'INSERT INTO pf_service_book (plate,model,color,paint,title,service,service_description,svc_date,mileage,serviced_by,location) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        { plate, model, '', paint, title, serviceText, svcdesc, os.date('%Y-%m-%d'), mileage, servicedBy, shop:sub(1, 80) }
    )
    if not bookLock(book) then lockBook(src, Player, bookSlot, book, plate) end

    notify(src, 'Service entry saved', 'success')
    TriggerClientEvent('pf_mech:service:refresh', src, plate)
end)

QBCore.Functions.CreateCallback('pf_mech:service:get', function(source, cb, plate)
    local src = source
    plate = cleanPlate(plate)
    if plate == '' or #plate > 8 then cb({}) return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb({}) return end
    local allowed = (isMechanic(src) and nearbyVehicleWithPlate(src, plate, SERVICE_REACH) ~= nil) or holdsBookFor(Player, plate)
    if not allowed then
        local owner = MySQL.scalar.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
        allowed = owner ~= nil and owner == Player.PlayerData.citizenid
    end
    if not allowed then cb({}) return end
    local rows = MySQL.query.await(
        'SELECT id, plate, model, paint, title, service, service_description, svc_date, mileage, serviced_by, location FROM pf_service_book WHERE plate = ? ORDER BY id DESC LIMIT 50',
        { plate }
    ) or {}
    cb(rows)
end)

-- ============================================================================
-- ROLLING COAL: the owner's DPF setting
-- ============================================================================
RegisterNetEvent('pf_mech:setCoalDelete', function(plate, enabled)
    local src = source
    plate = cleanPlate(plate)
    if plate == '' or #plate > 8 then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local result = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    if not result or result.citizenid ~= Player.PlayerData.citizenid then
        notify(src, 'You do not own this vehicle')
        return
    end
    enabled = enabled == true
    MySQL.update.await([[
        UPDATE player_vehicles
        SET mods = JSON_SET(COALESCE(mods, '{}'), '$.coalDelete', ?)
        WHERE plate = ?
    ]], { enabled, plate })
    CoalState[plate] = enabled
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, enabled)
end)

QBCore.Functions.CreateCallback('pf_mech:hasDPFItem', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end
    local item = Player.Functions.GetItemByName(Config.DPFItem)
    cb(item ~= nil)
end)

local function forgetPlayer(src)
    ServiceLast[src], CoalLastStart[src] = nil, nil
    if PFMech.RecentRepairs then PFMech.RecentRepairs[src] = nil end
    for veh, by in pairs(CoalOn) do
        if by == src then CoalOn[veh] = nil setCoal(veh, false) end
    end
end
PFMech.ForgetMechanicPlayer = forgetPlayer

-- repair records of cars that are gone (a roadside call only counts repairs made after it started)
CreateThread(function()
    while true do
        Wait(30000)
        for veh in pairs(PFMech.RepairLog) do
            if not DoesEntityExist(veh) then PFMech.RepairLog[veh] = nil end
        end
    end
end)

-- 'pf_mech:nos:updateLevel' is handled in server/nos.lua only (a second copy here took any level
-- for any car, with no cap).

-- Debug helper
QBCore.Commands.Add('nosstate','Print vehicle NOS state',{},false,function(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    TriggerClientEvent('pf_mech:nos:debugPrint', src)
end)
