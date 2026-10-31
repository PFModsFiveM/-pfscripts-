-- Framework Detection
local QBCore = nil
local ESX = nil

if Config.Framework == 'qbcore' then
    QBCore = exports['pfm-core']:GetCoreObject()
elseif Config.Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
end

-- Helper function to get player from source
local function GetPlayer(source)
    if Config.Framework == 'qbcore' and QBCore then
        return QBCore.Functions.GetPlayer(source)
    elseif Config.Framework == 'esx' and ESX then
        return ESX.GetPlayerFromId(source)
    end
    return nil
end

-- Helper function to get player job
local function GetPlayerJob(source)
    local Player = GetPlayer(source)
    if not Player then return nil, 0 end
    
    if Config.Framework == 'qbcore' then
        return Player.PlayerData.job.name, Player.PlayerData.job.grade.level
    elseif Config.Framework == 'esx' then
        return Player.job.name, Player.job.grade
    end
    return nil, 0
end

-- Helper function to get player identifier
local function GetPlayerIdentifier(source)
    local Player = GetPlayer(source)
    if not Player then return nil end
    
    if Config.Framework == 'qbcore' then
        return Player.PlayerData.citizenid
    elseif Config.Framework == 'esx' then
        return Player.identifier
    end
    return nil
end

--- Sends a pf-devices push to an open app (live refresh): kind 'player' (src), 'citizen' (citizenid),
--- 'job' (everyone in that job) or 'all'. Never fails the caller.
local function devicePush(kind, target, appId, event, payload)
    if GetResourceState('pf-devices') ~= 'started' then return false end
    local ok = pcall(function()
        local d = exports['pf-devices']
        if kind == 'citizen' then d:PushToCitizen(target, appId, event, payload or {})
        elseif kind == 'job' then d:PushToJob(target, appId, event, payload or {}, false)
        elseif kind == 'all' then d:Broadcast(appId, event, payload or {})
        else d:Push(target, appId, event, payload or {}) end
    end)
    return ok
end

local function GetPlayerHasItem(source, itemName)
    if not source or not itemName or itemName == '' then return false, 0 end

    if GetResourceState('ox_inventory') == 'started' then
        local ok, amount = pcall(function()
            return exports.ox_inventory:Search(source, 'count', itemName)
        end)
        if ok and tonumber(amount) and tonumber(amount) > 0 then
            return true, tonumber(amount)
        end
    end

    local Player = GetPlayer(source)
    if not Player then return false, 0 end

    if Config.Framework == 'qbcore' then
        local item = Player.Functions.GetItemByName(itemName)
        local amount = (item and item.amount) or 0
        return amount > 0, amount
    end

    if Config.Framework == 'esx' then
        local item = Player.getInventoryItem(itemName)
        local amount = (item and item.count) or 0
        return amount > 0, amount
    end

    return false, 0
end

local function HasSecurityRecoveryAccess(source)
    if not source then return false end
    if IsPlayerAceAllowed(source, (Config.Security and Config.Security.AdminAce) or 'pf-computer.admin') then
        return true
    end

    local jobName = GetPlayerJob(source)
    local allowedJobs = (Config.Security and Config.Security.AdminRecoveryJobs) or {}
    for _, name in ipairs(allowedJobs) do
        if name == jobName then
            return true
        end
    end

    return false
end

local function NormalizePhoneImages(rawImages)
    local images = {}
    if type(rawImages) ~= 'table' then
        return images
    end

    for idx, item in ipairs(rawImages) do
        local url = ''
        local name = ''
        local created = ''

        if type(item) == 'string' then
            url = item
            name = ('phone-image-%s.jpg'):format(idx)
        elseif type(item) == 'table' then
            url = item.image or item.url or item.src or item.link or ''
            name = item.name or item.label or ('phone-image-%s.jpg'):format(idx)
            created = item.created_at or item.createdAt or item.date or ''
        end

        if type(url) == 'string' and url ~= '' then
            images[#images + 1] = {
                url = url,
                name = tostring(name or ('phone-image-%s.jpg'):format(idx)),
                createdAt = tostring(created or '')
            }
        end
    end

    return images
end

local function GetPlayerPhoneImages(source)
    local citizenId = GetPlayerIdentifier(source)
    if not citizenId or citizenId == '' then
        return {}
    end

    if GetResourceState('pfm-phone') ~= 'started' then
        return {}
    end

    -- the phone's own gallery (phone_gallery), read by pfm-phone for this character only
    local ok, result = pcall(function() return exports['pfm-phone']:GetGallery(citizenId, 60) end)
    if ok and type(result) == 'table' then return NormalizePhoneImages(result) end
    return {}
end

local RESOURCE = GetCurrentResourceName()

local computerProps = {} -- Store spawned computer props

-- ============================================================================
-- World computers (props). The server owns the list: it makes each prop's id, checks the model,
-- position and heading against the staff member's real position, refuses duplicates, and only
-- lets the person who placed a computer (or a senior admin) remove it. Clients only preview.
-- ============================================================================
local MAX_COMPUTER_PROPS = 500
local PLACE_REACH = 5.0       -- how far from the staff member a computer can be placed or removed
local DUPLICATE_RADIUS = 0.75 -- two computers can't occupy the same spot
local nextPropId = 0

local function newPropId()
    nextPropId = nextPropId + 1
    return ('pc-%d-%d'):format(os.time(), nextPropId)
end

-- Load computer props from file; entries saved before ids existed get one
local function LoadComputerProps()
    local file = LoadResourceFile(RESOURCE, 'data/computer_props.json')
    computerProps = (file and json.decode(file)) or {}
    local changed = false
    for _, propData in ipairs(computerProps) do
        if not propData.id then
            propData.id = newPropId()
            changed = true
        end
    end
    print('^2[pf-computer]^7 Loaded ' .. #computerProps .. ' saved computer props')
    return changed
end

-- Save computer props to file
local function SaveComputerProps()
    SaveResourceFile(RESOURCE, 'data/computer_props.json', json.encode(computerProps, { indent = true }), -1)
end

local function publicProp(propData)
    return { id = propData.id, model = propData.model, x = propData.x, y = propData.y, z = propData.z, heading = propData.heading }
end

-- Load props on resource start and send them to everyone online
CreateThread(function()
    Wait(1000)
    if LoadComputerProps() then SaveComputerProps() end
    for _, propData in ipairs(computerProps) do
        TriggerClientEvent('pf-computer:client:spawnProp', -1, publicProp(propData))
    end
end)

-- Players who join later ask for the list (it used to be sent only once, at resource start)
local propRequests = {}
RegisterNetEvent('pf-computer:server:requestProps', function()
    local src = source
    local now = os.time()
    if propRequests[src] and now - propRequests[src] < 10 then return end
    propRequests[src] = now
    for _, propData in ipairs(computerProps) do
        TriggerClientEvent('pf-computer:client:spawnProp', src, publicProp(propData))
    end
end)
AddEventHandler('playerDropped', function() propRequests[source] = nil end)

local function adminAce()
    return (Config.Security and Config.Security.AdminAce) or 'pf-computer.admin'
end

local function canManageComputerProps(src)
    if not src or src <= 0 then return false end
    return IsPlayerAceAllowed(src, adminAce()) or IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'god')
end

-- Removing a computer someone else placed needs the senior permission
local function canRemoveAnyComputer(src)
    return IsPlayerAceAllowed(src, (Config.Security and Config.Security.SeniorAdminAce) or 'pf-computer.admin.all')
        or IsPlayerAceAllowed(src, 'god')
end

local function placerId(src)
    local Player = QBCore and QBCore.Functions.GetPlayer(src)
    return (Player and Player.PlayerData.citizenid) or GetPlayerIdentifier(src, 0) or ('src:' .. tostring(src))
end

local function isComputerModel(model)
    if type(model) ~= 'string' or #model > 64 then return false end
    local hash = GetHashKey(model)
    for _, allowed in ipairs(Config.ComputerProps or {}) do
        if allowed == hash or allowed == model then return true end
    end
    return false
end

local function finiteNumber(v)
    v = tonumber(v)
    return v ~= nil and v == v and v ~= math.huge and v ~= -math.huge and math.abs(v) < 100000 and v or nil
end

-- Server event to save a placed computer
RegisterNetEvent('pf-computer:server:saveProp', function(propData)
    local src = source
    if not canManageComputerProps(src) then return end
    if type(propData) ~= 'table' or not isComputerModel(propData.model) then return end
    local x, y, z, h = finiteNumber(propData.x), finiteNumber(propData.y), finiteNumber(propData.z), finiteNumber(propData.heading or 0)
    if not (x and y and z and h) then return end
    if #computerProps >= MAX_COMPUTER_PROPS then return end
    local at = vector3(x, y, z)
    -- placed where the staff member is, not at a coordinate sent from anywhere on the map
    if #(GetEntityCoords(GetPlayerPed(src)) - at) > PLACE_REACH then
        TriggerClientEvent('QBCore:Notify', src, 'Place the computer next to you', 'error')
        return
    end
    for _, existing in ipairs(computerProps) do
        if #(vector3(existing.x, existing.y, existing.z) - at) < DUPLICATE_RADIUS then
            TriggerClientEvent('QBCore:Notify', src, 'There is already a computer here', 'error')
            return
        end
    end

    local clean = {
        id = newPropId(), model = propData.model, x = x, y = y, z = z,
        heading = h % 360, placedBy = placerId(src), placedAt = os.time(),
    }
    table.insert(computerProps, clean)
    SaveComputerProps()
    TriggerClientEvent('pf-computer:client:spawnProp', -1, publicProp(clean))
end)

-- Server event to delete a computer: the nearest saved computer to the staff member (the client's
-- coordinates only pick which one when several are close), placed by them unless they are senior.
RegisterNetEvent('pf-computer:server:deleteProp', function(target)
    local src = source
    if not canManageComputerProps(src) then return end
    local me = GetEntityCoords(GetPlayerPed(src))
    local hint = me
    if type(target) == 'table' or type(target) == 'vector3' then
        local cx, cy, cz = finiteNumber(target.x), finiteNumber(target.y), finiteNumber(target.z)
        if cx and cy and cz then hint = vector3(cx, cy, cz) end
    end

    local bestIndex, bestDist
    for i, propData in ipairs(computerProps) do
        local pos = vector3(propData.x, propData.y, propData.z)
        local matchesId = type(target) == 'string' and propData.id == target
        local d = #(pos - hint)
        if #(pos - me) <= PLACE_REACH and (matchesId or d < 2.0) and (not bestDist or d < bestDist) then
            bestIndex, bestDist = i, d
        end
    end
    if not bestIndex then
        TriggerClientEvent('QBCore:Notify', src, 'No saved computer next to you', 'error')
        return
    end
    local propData = computerProps[bestIndex]
    if propData.placedBy ~= placerId(src) and not canRemoveAnyComputer(src) then
        TriggerClientEvent('QBCore:Notify', src, 'Only the person who placed this computer can remove it', 'error')
        return
    end
    table.remove(computerProps, bestIndex)
    SaveComputerProps()
    TriggerClientEvent('pf-computer:client:deleteProp', -1, vector3(propData.x, propData.y, propData.z), propData.id)
end)

-- ISO-8601 UTC timestamp. It was called throughout this resource (and by gov_announcements_sync.lua)
-- but never defined, so every caller errored: company deposits took the player's money and then
-- failed before recording it.
function nowIso()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

-- ============================================================================
-- Storage (MySQL)
-- ============================================================================
-- What players make in the computer apps lives in MySQL: business profiles (name, logo, blip,
-- delivery point, stash points, menu, meals, wages), wage caps, domains and websites, dark-web chat,
-- running pickup runs and the job board (server/jobboard.lua). The handlers work on a copy in memory
-- that is loaded once the migrations have run; every change is written to the database straight
-- away, and a write the database refused stays queued and is retried every 30 s.
-- data/pc_data.json (the old store) is imported once: migration 2 marks the import as due and Init
-- runs it and marks it done; the file is kept as a backup and never written again.
-- Writes are refused while the tables are still loading at start ('storage_starting'), so nothing
-- typed in the first seconds can be overwritten by the load.

local LEGACY_FILE = 'data/pc_data.json'

local dataStore = {
    counters = {},
    businesses = {},                -- [job] = { id, settings = {}, stashLocations = {} }
    businessMenus = {},             -- [job] = { items }
    businessMeals = {},             -- [job] = { meals }
    businessWages = {},             -- [job] = { [grade] = wage }
    businessBlips = {},             -- [job] = blip
    businessDeliveryLocations = {}, -- [job] = { x, y, z, w }
    wageCaps = {},                  -- [grade] = cap
    browserDomains = {},            -- { domain, ownerIdentifier, ownerName, templateId, purchasedAt, price }
    browserWebsites = {},           -- [domain] = website state
    chatRooms = {},                 -- [room] = { messages = { id, author, message, time } }
    pickupRuns = {},                -- [citizenid] = { orderId, businessId, startedAt }
    meta = {},                      -- [key] = value
    -- not stored: this session's Business Manager actions (the ledger is the full record) and the
    -- copies of pf-government's lists (pf-government is the source)
    businessAccounts = {},
    laws = {}, announcements = {},
    browserGuideStats = { queries = 0 },
}

-- mode: 'memory' when pfm-core has no migrations (a stand-alone test harness), 'starting' until
-- the tables are loaded, then 'ready'; 'failed' when the database could not be used.
local DB = { mode = 'starting', dirty = {}, writers = {} }
do
    local core = exports['pfm-core']
    local ok, fn = pcall(function() return core and core.RunMigrations end)
    if not ok or not fn then DB.mode = 'memory' end
end

local function loadData() return dataStore end

local function nextId(key)
    dataStore.counters[key] = (dataStore.counters[key] or 0) + 1
    return dataStore.counters[key]
end

local function storageWritable()
    return DB.mode == 'ready' or DB.mode == 'memory'
end

local function decodeJson(raw, default)
    if type(raw) ~= 'string' or raw == '' then return default end
    local ok, v = pcall(json.decode, raw)
    if ok and type(v) == 'table' then return v end
    return default
end

--- Queues a record for the database and writes it now when the database is up. Returns true when
--- the record is in the database (or there is no database in this environment).
local function persist(kind, key, value)
    if DB.mode == 'memory' then return true end
    local id = kind .. ':' .. tostring(key)
    DB.dirty[id] = { kind = kind, key = key, value = value }
    if DB.mode ~= 'ready' then return false end
    local ok, err = pcall(DB.writers[kind], key, value)
    if ok then DB.dirty[id] = nil return true end
    print(('^1[pf-computer]^7 could not save %s (will retry): %s'):format(id, tostring(err)))
    return false
end

local function flushPending()
    if DB.mode ~= 'ready' then return end
    for id, item in pairs(DB.dirty) do
        local ok, err = pcall(DB.writers[item.kind], item.key, item.value)
        if ok then DB.dirty[id] = nil else print(('^1[pf-computer]^7 retry of %s failed: %s'):format(id, tostring(err))) end
    end
end

local function persistBusiness(job) return persist('business', job) end

DB.writers.business = function(job)
    local b = dataStore.businesses[job] or {}
    local profile = {
        settings = b.settings or {}, stashLocations = b.stashLocations or {},
        blip = dataStore.businessBlips[job], delivery = dataStore.businessDeliveryLocations[job],
    }
    MySQL.query.await([[INSERT INTO pf_computer_businesses (business_id, profile, menu, meals, wages) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE profile = VALUES(profile), menu = VALUES(menu), meals = VALUES(meals), wages = VALUES(wages)]],
        { job, json.encode(profile), json.encode(dataStore.businessMenus[job] or {}),
          json.encode(dataStore.businessMeals[job] or {}), json.encode(dataStore.businessWages[job] or {}) })
end

DB.writers.wagecap = function(grade)
    local cap = dataStore.wageCaps[grade]
    if cap == nil then
        MySQL.query.await('DELETE FROM pf_computer_wage_caps WHERE grade = ?', { grade })
    else
        MySQL.query.await('INSERT INTO pf_computer_wage_caps (grade, cap) VALUES (?, ?) ON DUPLICATE KEY UPDATE cap = VALUES(cap)', { grade, cap })
    end
end

DB.writers.domain = function(domain)
    local rec
    for _, d in ipairs(dataStore.browserDomains) do if d.domain == domain then rec = d break end end
    if not rec then
        MySQL.query.await('DELETE FROM pf_computer_domains WHERE domain = ?', { domain })
        return
    end
    MySQL.query.await([[INSERT INTO pf_computer_domains (domain, owner_cid, owner_name, template_id, price, purchased_at, website)
        VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner_cid = VALUES(owner_cid), owner_name = VALUES(owner_name),
        template_id = VALUES(template_id), website = VALUES(website)]],
        { domain, rec.ownerIdentifier, rec.ownerName, rec.templateId, math.floor(tonumber(rec.price) or 0), rec.purchasedAt,
          dataStore.browserWebsites[domain] and json.encode(dataStore.browserWebsites[domain]) or nil })
end

DB.writers.chat = function(_, entry)
    MySQL.query.await([[INSERT INTO pf_computer_chat (id, room, handle, citizenid, message, hidden, hidden_by, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE hidden = VALUES(hidden), hidden_by = VALUES(hidden_by)]],
        { entry.id, entry.room, entry.author, entry.cid, entry.message, entry.hidden and 1 or 0, entry.hiddenBy, entry.time })
end

DB.writers.pickup = function(cid)
    local run = dataStore.pickupRuns[cid]
    if not run then
        MySQL.query.await('DELETE FROM pf_computer_pickup_runs WHERE citizenid = ?', { cid })
    else
        MySQL.query.await([[INSERT INTO pf_computer_pickup_runs (citizenid, order_id, business_id, started_at) VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE order_id = VALUES(order_id), business_id = VALUES(business_id), started_at = VALUES(started_at)]],
            { cid, run.orderId, run.businessId, run.startedAt })
    end
end

DB.writers.meta = function(key)
    MySQL.query.await('INSERT INTO pf_computer_meta (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { key, json.encode({ v = dataStore.meta[key] }) })
end

-- ── the one-time import of data/pc_data.json ──────────────────────────────────
-- Only what still matters is imported. Not imported (left in the backup): mail and the calendar
-- (they belong to pf-citizen's Mail and Calendar now), the dark-web market (removed), cached copies of
-- pf-government's laws/announcements, legacy supply orders (paid from the old file balance, never
-- stocked) and the old company balances (MigrateBusinessAccountsToBank moved them to the bank).
local function importLegacyJson()
    local raw = LoadResourceFile(RESOURCE, LEGACY_FILE)
    local old = decodeJson(raw, nil)
    if not old then return end
    local jobs = {}
    for job in pairs(type(old.businesses) == 'table' and old.businesses or {}) do jobs[job] = true end
    for _, key in ipairs({ 'businessMenus', 'businessMeals', 'businessWages', 'businessBlips', 'businessDeliveryLocations' }) do
        if type(old[key]) == 'table' then for job in pairs(old[key]) do if type(job) == 'string' then jobs[job] = true end end end
    end
    for job in pairs(jobs) do
        local b = type(old.businesses) == 'table' and old.businesses[job] or {}
        local profile = {
            settings = type(b.settings) == 'table' and b.settings or {},
            stashLocations = type(b.stashLocations) == 'table' and b.stashLocations or {},
            blip = type(old.businessBlips) == 'table' and old.businessBlips[job] or nil,
            delivery = type(old.businessDeliveryLocations) == 'table' and old.businessDeliveryLocations[job] or nil,
        }
        local pick = function(key) return json.encode(type(old[key]) == 'table' and old[key][job] or {}) end
        MySQL.query.await('INSERT IGNORE INTO pf_computer_businesses (business_id, profile, menu, meals, wages) VALUES (?, ?, ?, ?, ?)',
            { tostring(job):sub(1, 64), json.encode(profile), pick('businessMenus'), pick('businessMeals'), pick('businessWages') })
    end
    for grade, cap in pairs(type(old.wageCaps) == 'table' and old.wageCaps or {}) do
        if tonumber(cap) then MySQL.query.await('INSERT IGNORE INTO pf_computer_wage_caps (grade, cap) VALUES (?, ?)', { tostring(grade):sub(1, 8), math.floor(tonumber(cap)) }) end
    end
    for _, d in ipairs(type(old.browserDomains) == 'table' and old.browserDomains or {}) do
        if type(d) == 'table' and type(d.domain) == 'string' and type(d.ownerIdentifier) == 'string' then
            local site = type(old.browserWebsites) == 'table' and old.browserWebsites[d.domain] or nil
            MySQL.query.await([[INSERT IGNORE INTO pf_computer_domains (domain, owner_cid, owner_name, template_id, price, purchased_at, website)
                VALUES (?, ?, ?, ?, ?, ?, ?)]], { d.domain:sub(1, 64), d.ownerIdentifier:sub(1, 50), tostring(d.ownerName or ''):sub(1, 100),
                tostring(d.templateId or 'services'):sub(1, 32), math.floor(tonumber(d.price) or 0), tostring(d.purchasedAt or ''),
                site and json.encode(site) or nil })
        end
    end
    local chatId = 0
    for room, r in pairs(type(old.chatRooms) == 'table' and old.chatRooms or {}) do
        for _, m in ipairs(type(r) == 'table' and r.messages or {}) do
            chatId = chatId + 1
            MySQL.query.await('INSERT IGNORE INTO pf_computer_chat (id, room, handle, citizenid, message, created_at) VALUES (?, ?, ?, NULL, ?, ?)',
                { chatId, tostring(room):sub(1, 24), tostring(m.author or 'anon'):sub(1, 24), tostring(m.message or ''):sub(1, 500), tostring(m.time or '') })
        end
    end
    -- old job posts had a free-text company and anonymous applicants: kept for the record, closed
    local postIds = {}
    for _, p in ipairs(type(old.jobPosts) == 'table' and old.jobPosts or {}) do
        if type(p) == 'table' and tonumber(p.id) then
            MySQL.query.await([[INSERT IGNORE INTO pf_computer_job_posts (id, business_kind, business_id, business_name, title, location, salary,
                employment, category, description, poster_cid, poster_name, status, created_at, closed_at)
                VALUES (?, 'legacy', '', ?, ?, ?, ?, ?, ?, ?, ?, 'Imported post', 'closed', ?, ?)]],
                { math.floor(tonumber(p.id)), tostring(p.company or ''):sub(1, 100), tostring(p.title or 'Job'):sub(1, 80),
                  tostring(p.location or ''):sub(1, 80), tostring(p.salary or ''):sub(1, 40), tostring(p.type or ''):sub(1, 30),
                  tostring(p.category or ''):sub(1, 30), tostring(p.description or ''):sub(1, 2000),
                  tostring(p.creatorIdentifier or 'legacy'):sub(1, 50), os.time(), os.time() })
            postIds[math.floor(tonumber(p.id))] = true
        end
    end
    for _, a in ipairs(type(old.jobApplications) == 'table' and old.jobApplications or {}) do
        if type(a) == 'table' and tonumber(a.id) and postIds[math.floor(tonumber(a.jobId) or -1)] then
            MySQL.query.await([[INSERT IGNORE INTO pf_computer_job_applications (id, post_id, applicant_cid, applicant_name, experience, message, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, 'closed', ?)]], { math.floor(tonumber(a.id)), math.floor(tonumber(a.jobId)), 'legacy:' .. math.floor(tonumber(a.id)),
                tostring(a.name or 'Applicant'):sub(1, 100), tostring(a.experience or ''):sub(1, 1000), tostring(a.message or ''):sub(1, 1000), os.time() })
        end
    end
    -- the old company balances were moved to the bank by MigrateBusinessAccountsToBank; remember which
    for job, acc in pairs(type(old.businessAccounts) == 'table' and old.businessAccounts or {}) do
        if type(acc) == 'table' and type(acc.bankMigration) == 'table' then
            MySQL.query.await('INSERT IGNORE INTO pf_computer_meta (k, v) VALUES (?, ?)', { ('bankMigration:%s'):format(job):sub(1, 64), json.encode({ v = acc.bankMigration }) })
        end
    end
    print(('[pf-computer] imported %s into the database (the file is kept as a backup)'):format(LEGACY_FILE))
end

PFComputerMigrations = {
    {
        version = 1,
        name = 'computer apps storage',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_computer_businesses` (
                `business_id` VARCHAR(64) NOT NULL,
                `profile` LONGTEXT NULL,
                `menu` LONGTEXT NULL,
                `meals` LONGTEXT NULL,
                `wages` LONGTEXT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`business_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_computer_wage_caps` (
                `grade` VARCHAR(8) NOT NULL,
                `cap` INT NOT NULL,
                PRIMARY KEY (`grade`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_computer_domains` (
                `domain` VARCHAR(64) NOT NULL,
                `owner_cid` VARCHAR(50) NOT NULL,
                `owner_name` VARCHAR(100) NULL,
                `template_id` VARCHAR(32) NULL,
                `price` INT NOT NULL DEFAULT 0,
                `purchased_at` VARCHAR(32) NULL,
                `website` LONGTEXT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`domain`),
                KEY `idx_owner` (`owner_cid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_computer_chat` (
                `id` INT NOT NULL,
                `room` VARCHAR(24) NOT NULL,
                `handle` VARCHAR(24) NOT NULL,
                `citizenid` VARCHAR(50) NULL,
                `message` VARCHAR(500) NOT NULL,
                `hidden` TINYINT(1) NOT NULL DEFAULT 0,
                `hidden_by` VARCHAR(50) NULL,
                `created_at` VARCHAR(32) NOT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_room` (`room`, `id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_computer_pickup_runs` (
                `citizenid` VARCHAR(50) NOT NULL,
                `order_id` INT NOT NULL,
                `business_id` VARCHAR(64) NOT NULL,
                `started_at` INT NOT NULL,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_computer_meta` (
                `k` VARCHAR(64) NOT NULL,
                `v` LONGTEXT NULL,
                PRIMARY KEY (`k`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_computer_job_posts` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `business_kind` VARCHAR(8) NOT NULL,
                `business_id` VARCHAR(100) NOT NULL,
                `business_name` VARCHAR(100) NOT NULL,
                `hire_job` VARCHAR(50) NULL,
                `title` VARCHAR(80) NOT NULL,
                `location` VARCHAR(80) NULL,
                `salary` VARCHAR(40) NULL,
                `employment` VARCHAR(30) NULL,
                `category` VARCHAR(30) NULL,
                `description` TEXT NULL,
                `tags` VARCHAR(255) NULL,
                `poster_cid` VARCHAR(50) NOT NULL,
                `poster_name` VARCHAR(100) NOT NULL,
                `status` VARCHAR(12) NOT NULL DEFAULT 'open',
                `created_at` INT NOT NULL,
                `closed_at` INT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_status` (`status`, `created_at`),
                KEY `idx_business` (`business_id`),
                KEY `idx_poster` (`poster_cid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_computer_job_applications` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `post_id` INT NOT NULL,
                `applicant_cid` VARCHAR(50) NOT NULL,
                `applicant_name` VARCHAR(100) NOT NULL,
                `applicant_phone` VARCHAR(20) NULL,
                `experience` TEXT NULL,
                `message` TEXT NULL,
                `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
                `offer_grade` INT NULL,
                `decided_by` VARCHAR(50) NULL,
                `decided_at` INT NULL,
                `created_at` INT NOT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_post_applicant` (`post_id`, `applicant_cid`),
                KEY `idx_applicant` (`applicant_cid`, `status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- marks the import as due; PFComputerStorage.Init runs it and marks it done (a migration step
        -- passed through an export arrives as a function reference, which pfm-core cannot run)
        version = 2,
        name = 'import data/pc_data.json once',
        up = { [[INSERT IGNORE INTO pf_computer_meta (k, v) VALUES ('legacy_import', '{"v":"pending"}')]] },
    },
    {
        -- each character's desktop layout and lock screen on each computer (server/profiles.lua);
        -- they used to live only in the browser cache of the player's game client
        version = 3,
        name = 'per-character desktop layout and lock screen',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_computer_profiles` (
                `citizenid` VARCHAR(50) NOT NULL,
                `scope` VARCHAR(160) NOT NULL,
                `layout` LONGTEXT NULL,
                `security` LONGTEXT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`, `scope`),
                KEY `idx_updated` (`citizenid`, `updated_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

local function loadFromDb()
    local maxMenu, maxMeal = 0, 0
    for _, r in ipairs(MySQL.query.await('SELECT business_id, profile, menu, meals, wages FROM pf_computer_businesses') or {}) do
        local job = r.business_id
        local p = decodeJson(r.profile, {})
        dataStore.businesses[job] = { id = job, settings = type(p.settings) == 'table' and p.settings or {}, stashLocations = type(p.stashLocations) == 'table' and p.stashLocations or {} }
        dataStore.businessBlips[job] = type(p.blip) == 'table' and p.blip or nil
        dataStore.businessDeliveryLocations[job] = type(p.delivery) == 'table' and p.delivery or nil
        dataStore.businessMenus[job] = decodeJson(r.menu, {})
        dataStore.businessMeals[job] = decodeJson(r.meals, {})
        local wages = {}
        for g, w in pairs(decodeJson(r.wages, {})) do wages[tostring(g)] = tonumber(w) end
        dataStore.businessWages[job] = wages
        for _, it in ipairs(dataStore.businessMenus[job]) do maxMenu = math.max(maxMenu, tonumber(it.id) or 0) end
        for _, m in ipairs(dataStore.businessMeals[job]) do maxMeal = math.max(maxMeal, tonumber(m.id) or 0) end
    end
    dataStore.counters.menuItems, dataStore.counters.meals = maxMenu, maxMeal
    for _, r in ipairs(MySQL.query.await('SELECT grade, cap FROM pf_computer_wage_caps') or {}) do
        dataStore.wageCaps[tostring(r.grade)] = tonumber(r.cap)
    end
    for _, r in ipairs(MySQL.query.await('SELECT domain, owner_cid, owner_name, template_id, price, purchased_at, website FROM pf_computer_domains') or {}) do
        dataStore.browserDomains[#dataStore.browserDomains + 1] = { domain = r.domain, ownerIdentifier = r.owner_cid, ownerName = r.owner_name,
            templateId = r.template_id, purchasedAt = r.purchased_at, price = tonumber(r.price) or 0 }
        dataStore.browserWebsites[r.domain] = decodeJson(r.website, nil)
    end
    -- the last 50 visible messages of each room
    local maxChat = tonumber(MySQL.scalar.await('SELECT MAX(id) FROM pf_computer_chat')) or 0
    local rows = MySQL.query.await('SELECT id, room, handle, message, created_at FROM pf_computer_chat WHERE hidden = 0 ORDER BY id DESC LIMIT 2500') or {}
    for i = #rows, 1, -1 do
        local r = rows[i]
        local room = dataStore.chatRooms[r.room] or { messages = {} }
        dataStore.chatRooms[r.room] = room
        room.messages[#room.messages + 1] = { id = tonumber(r.id), author = r.handle, message = r.message, time = r.created_at }
        if #room.messages > 50 then table.remove(room.messages, 1) end
    end
    dataStore.counters.chat = maxChat
    for _, r in ipairs(MySQL.query.await('SELECT citizenid, order_id, business_id, started_at FROM pf_computer_pickup_runs') or {}) do
        dataStore.pickupRuns[r.citizenid] = { orderId = tonumber(r.order_id), businessId = r.business_id, startedAt = tonumber(r.started_at) }
    end
    for _, r in ipairs(MySQL.query.await('SELECT k, v FROM pf_computer_meta') or {}) do
        local v = decodeJson(r.v, {})
        dataStore.meta[r.k] = v.v
    end
end

local onStorageReady = {}

PFComputerStorage = {}

--- Runs the migrations (the first start also imports data/pc_data.json once) and loads the tables.
function PFComputerStorage.Init()
    if DB.mode == 'ready' then return true end
    if DB.mode == 'memory' then return false end
    local ok, res, err = pcall(function() return exports['pfm-core']:RunMigrations(RESOURCE, PFComputerMigrations) end)
    if not ok or res ~= true then
        print(('^1[pf-computer]^7 database migrations failed: %s'):format(tostring(ok and err or res)))
        return false
    end
    local due = decodeJson(MySQL.scalar.await("SELECT v FROM pf_computer_meta WHERE k = 'legacy_import'"), {})
    if due.v == 'pending' then
        local imported, ierr = pcall(importLegacyJson)
        if not imported then
            print(('^1[pf-computer]^7 importing %s failed (retried next start): %s'):format(LEGACY_FILE, tostring(ierr)))
            return false
        end
        MySQL.query.await([[UPDATE pf_computer_meta SET v = '{"v":"done"}' WHERE k = 'legacy_import']])
    end
    local loaded, lerr = pcall(loadFromDb)
    if not loaded then
        print(('^1[pf-computer]^7 could not load the computer tables: %s'):format(tostring(lerr)))
        return false
    end
    DB.mode = 'ready'
    flushPending()
    for _, fn in ipairs(onStorageReady) do pcall(fn) end
    return true
end

function PFComputerStorage.Mode() return DB.mode end

CreateThread(function()
    if DB.mode == 'memory' then
        print('^3[pf-computer]^7 pfm-core has no migrations here: computer data is kept in memory only')
        return
    end
    for _ = 1, 30 do
        if PFComputerStorage.Init() then break end
        Wait(2000)
    end
    if DB.mode ~= 'ready' then
        DB.mode = 'failed'
        print('^1[pf-computer]^7 the database is unavailable: computer apps are read-only until the resource restarts')
        return
    end
    while true do
        Wait(30000)
        flushPending()
    end
end)

-- ── mail through pf-citizen ────────────────────────────────────────────────────
-- Mail belongs to pf-citizen (the Mail app on the tablet and computer, with offline delivery). The
-- computer no longer keeps a mailbox of its own: without pf-citizen there is nowhere players could
-- read mail, so nothing is sent.
local function citizenMailUp()
    return GetResourceState('pf-citizen') == 'started'
end

--- SendMail returns the new mail's id, or nil and why.
local function sendCitizenMail(citizenid, mail)
    if not citizenMailUp() or type(citizenid) ~= 'string' or citizenid == '' then return false end
    local ok, id, err = pcall(function() return exports['pf-citizen']:SendMail(citizenid, mail) end)
    if not ok or id == nil or id == false then
        print(('^1[pf-computer]^7 SendMail to %s failed: %s'):format(citizenid, tostring(ok and err or id)))
        return false
    end
    return true
end

local function sendJobMail(job, mail, ondutyOnly)
    if not citizenMailUp() or type(job) ~= 'string' then return false end
    local ok, res = pcall(function() return exports['pf-citizen']:SendMailToJob(job, mail, ondutyOnly == true) end)
    return ok and res ~= false
end

-- City Hall notices (laws, announcements) are mailed by pf-citizen itself: it listens to
-- pf-computer:gov:laws:sync and pf-computer:gov:announcements:sync and delivers once per citizen,
-- offline included. This resource no longer mails them (it would arrive twice).


local function safeString(value)
    if value == nil then return '' end
    return tostring(value)
end

local function normalizeDomain(domain)
    local raw = string.lower(safeString(domain)):gsub('^https?://', ''):gsub('/.*$', ''):gsub('%s+', '')
    raw = raw:gsub('^www%.', '')
    if raw == '' then return nil end
    if not raw:find('%.') then
        raw = raw .. '.ls'
    end
    if not raw:match('^[a-z0-9][a-z0-9%-%.]+[a-z0-9]$') then
        return nil
    end
    return raw
end

local function getReservedDomainInfo(domain)
    local cfg = Config.Browser and Config.Browser.Domains and Config.Browser.Domains.Reserved or {}
    return cfg[domain]
end

local function getDomainOwnerRecord(data, domain)
    for _, entry in ipairs(data.browserDomains or {}) do
        if entry.domain == domain then
            return entry
        end
    end
    return nil
end

local function createDefaultWebsiteState(domain, ownerIdentifier, ownerName, templateId)
    local templates = Config.Browser and Config.Browser.WebsiteTemplates or {}
    local template = templates[templateId] or templates.services
    local pageDefs = (template and template.pages) or {
        { slug = 'home', label = 'Home' },
        { slug = 'about', label = 'About' }
    }

    local pages = {}
    for _, page in ipairs(pageDefs) do
        local slug = tostring(page.slug or 'home')
        pages[slug] = {
            title = page.label or slug,
            modules = {
                {
                    id = ('hero_%s'):format(slug),
                    type = 'hero',
                    title = slug == 'home' and (domain or 'Website') or (page.label or slug),
                    body = slug == 'home' and 'Welcome to your website. Use the editor to customize sections, branding, pages, and content modules.' or 'Add details for this page.',
                    buttonLabel = 'Learn More',
                    buttonUrl = slug == 'home' and '#about' or ''
                },
                {
                    id = ('text_%s'):format(slug),
                    type = 'text',
                    title = page.label or slug,
                    body = 'Click Edit Site to update this content.'
                }
            }
        }
    end

    return {
        domain = domain,
        owner = { name = ownerName or 'Unknown' },   -- shown to every visitor: a name, never a citizen id
        theme = {
            accent = '#143d6b',
            background = '#f5f7fb',
            surface = '#ffffff',
            text = '#10233a'
        },
        branding = {
            siteName = domain,
            tagline = 'Player-owned website',
            logoUrl = '',
            headerLinks = pageDefs
        },
        pages = pages,
        updatedAt = nowIso()
    }
end

local function ensureWebsiteForDomain(data, record)
    if not record or not record.domain then return nil end
    data.browserWebsites = data.browserWebsites or {}
    if not data.browserWebsites[record.domain] then
        data.browserWebsites[record.domain] = createDefaultWebsiteState(record.domain, record.ownerIdentifier, record.ownerName, record.templateId)
    end
    local site = data.browserWebsites[record.domain]
    site.owner = { name = record.ownerName }   -- sites saved before kept the owner's citizen id here
    return site
end

local function getPlayerName(source)
    local Player = GetPlayer(source)
    if not Player then return 'Unknown Citizen' end
    if Config.Framework == 'qbcore' then
        local char = Player.PlayerData and Player.PlayerData.charinfo or {}
        return ((char.firstname or '') .. ' ' .. (char.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    elseif Config.Framework == 'esx' then
        return Player.getName and Player.getName() or (Player.name or 'Unknown Citizen')
    end
    return 'Unknown Citizen'
end

local function getBrowserConfigPayload(src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local ownedDomains = {}
    for _, entry in ipairs(data.browserDomains or {}) do
        if entry.ownerIdentifier == identifier then
            ownedDomains[#ownedDomains + 1] = entry
        end
    end

    return {
        homeUrl = (Config.Browser and Config.Browser.HomeUrl) or 'https://start.ls',
        featuredSites = (Config.Browser and Config.Browser.FeaturedSites) or {},
        shortcuts = (Config.Browser and Config.Browser.Shortcuts) or {},
        defaultBookmarks = (Config.Browser and Config.Browser.DefaultBookmarks) or {},
        domainPrice = (Config.Browser and Config.Browser.DefaultDomainPrice) or 2500,
        ownedDomains = ownedDomains,
        templates = (Config.Browser and Config.Browser.WebsiteTemplates) or {},
        assistant = (Config.Browser and Config.Browser.Assistant) or {}
    }
end

local function splitKeywords(value)
    local out = {}
    for token in string.gmatch(string.lower(safeString(value)), '[^%s,]+') do
        out[#out + 1] = token
    end
    return out
end

local function containsKeyword(haystack, needle)
    haystack = string.lower(safeString(haystack))
    needle = string.lower(safeString(needle))
    return haystack:find(needle, 1, true) ~= nil
end

local function findAssistantResponse(query)
    local lowered = string.lower(safeString(query))
    local assistant = Config.Browser and Config.Browser.Assistant or {}
    local best = nil
    local bestScore = 0

    for _, intent in ipairs(assistant.Intents or {}) do
        local score = 0
        for _, keyword in ipairs(intent.keywords or {}) do
            if containsKeyword(lowered, keyword) then
                score = score + 2
            else
                for _, token in ipairs(splitKeywords(keyword)) do
                    if containsKeyword(lowered, token) then
                        score = score + 1
                    end
                end
            end
        end
        if score > bestScore then
            bestScore = score
            best = {
                type = 'intent',
                title = intent.title,
                body = intent.body,
                url = intent.url,
                score = score
            }
        end
    end

    for _, location in ipairs(assistant.Locations or {}) do
        local score = 0
        for _, keyword in ipairs(location.keywords or {}) do
            if containsKeyword(lowered, keyword) then
                score = score + 3
            end
        end
        if score > bestScore then
            bestScore = score
            best = {
                type = 'location',
                title = location.name,
                body = ('%s Located on %s.'):format(location.description or location.name, location.street or 'city streets'),
                waypoint = location.coords,
                score = score
            }
        end
    end

    if best then return best end

    return {
        type = 'fallback',
        title = 'Guide',
        body = assistant.DefaultReply or 'No match found.'
    }
end

local handlers = {}

-- City government actions use pf-government's own roles (government job + a grade permission such as
-- 'fines', 'taxes' or 'budgets'). They used to accept any job in Config.GovJobs at any grade, so a
-- grade-0 police officer, medic or lawyer could fine players, change taxes or cut utilities.
-- Fails closed when pf-government is not running.
local function govCan(src, permission)
    if not src or GetResourceState('pf-government') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['pf-government']:HasPermission(src, permission) end)
    return ok and allowed == true
end

-- Any government role (every role has 'audit'); the dispatcher checks each action's own permission.
local function isGovAuthorized(src)
    return govCan(src, 'audit')
end

-- Mail is pf-citizen's. The one send left here goes through SendMailAs: pf-citizen takes the
-- sender from the player, checks the recipient, rate limits and keeps the sent copy.
local MAX_SUBJECT, MAX_BODY = 120, 4000

local function cleanText(value, maxLen, default)
    if type(value) ~= 'string' then return default end
    value = value:gsub('%c', ' ')
    if #value > maxLen then value = value:sub(1, maxLen) end
    return value
end

handlers['emails:send'] = function(payload, src)
    if not citizenMailUp() then return { ok = false, error = 'mail_unavailable' } end
    local to = cleanText(payload.to, 80, nil)
    if not to or to == '' then return { ok = false, error = 'invalid_recipient' } end
    local ok, res = pcall(function()
        return exports['pf-citizen']:SendMailAs(src, {
            to = to, subject = cleanText(payload.subject, MAX_SUBJECT, '(no subject)'), message = cleanText(payload.body or payload.message, MAX_BODY, ''),
        })
    end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'mail_unavailable' } end
    return res
end

-- ── Dark web chat ──────────────────────────────────────────────────────────────
-- Anonymous rooms: other players only see a handle, but the server picks it (the same one for a
-- character every time, derived from the citizen id and a secret salt), so nobody can post as
-- someone else. Messages are kept with the author's citizen id for staff, who can remove them.
-- The old market (free-text 'BTC' prices, a Buy that always failed) is gone.
local MAX_CHAT_ROOMS = 50
local CHAT_COOLDOWN = 2
local lastChatPost = {}

local function chatRoomName(value)
    if value == nil then return 'market' end
    if type(value) ~= 'string' or #value > 24 or not value:match('^[%w_%-]+$') then return nil end
    return value:lower()
end
local function chatRoomCount(rooms)
    local n = 0
    for _ in pairs(rooms) do n = n + 1 end
    return n
end

local function darkSalt()
    local salt = dataStore.meta.darkweb_salt
    if type(salt) ~= 'string' or #salt < 16 then
        local parts = {}
        for i = 1, 4 do parts[i] = ('%08x'):format(math.random(0, 0x7fffffff)) end
        salt = table.concat(parts)
        dataStore.meta.darkweb_salt = salt
        persist('meta', 'darkweb_salt')
    end
    return salt
end

local function chatHandle(cid)
    -- a small polynomial hash kept below 2^24 (no bit operations: works the same on every Lua)
    local text = darkSalt() .. cid
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + string.byte(text, i)) % 16777216
    end
    return ('anon-%06x'):format(math.floor(h))
end

local function isChatModerator(src)
    return IsPlayerAceAllowed(src, adminAce()) or IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'god')
end

handlers['darkweb:chat:rooms'] = function(_)
    local rooms = {}
    for name, room in pairs(dataStore.chatRooms) do
        rooms[#rooms + 1] = { name = name, count = #(room.messages or {}) }
    end
    table.sort(rooms, function(a, b) return a.name < b.name end)
    return { ok = true, data = rooms }
end

handlers['darkweb:chat:join'] = function(payload, src)
    local name = chatRoomName(payload.room)
    if not name then return { ok = false, error = 'invalid_room' } end
    if not dataStore.chatRooms[name] and chatRoomCount(dataStore.chatRooms) >= MAX_CHAT_ROOMS then
        return { ok = false, error = 'too_many_rooms' }
    end
    dataStore.chatRooms[name] = dataStore.chatRooms[name] or { messages = {} }
    local cid = GetPlayerIdentifier(src)
    return { ok = true, data = { room = name, messages = dataStore.chatRooms[name].messages, handle = cid and chatHandle(cid) or nil, moderator = isChatModerator(src) } }
end

handlers['darkweb:chat:post'] = function(payload, src)
    local cid = GetPlayerIdentifier(src)
    if not cid then return { ok = false, error = 'no_identifier' } end
    local room = chatRoomName(payload.room)
    local message = cleanText(payload.message, 500, '')
    if not room then return { ok = false, error = 'invalid_room' } end
    if message == '' then return { ok = false, error = 'empty_message' } end
    if not dataStore.chatRooms[room] and chatRoomCount(dataStore.chatRooms) >= MAX_CHAT_ROOMS then
        return { ok = false, error = 'too_many_rooms' }
    end
    local now = os.time()
    if lastChatPost[cid] and now - lastChatPost[cid] < CHAT_COOLDOWN then return { ok = false, error = 'slow_down' } end
    lastChatPost[cid] = now

    dataStore.chatRooms[room] = dataStore.chatRooms[room] or { messages = {} }
    local entry = { id = nextId('chat'), author = chatHandle(cid), message = message, time = nowIso() }
    local messages = dataStore.chatRooms[room].messages
    messages[#messages + 1] = entry
    if #messages > 50 then table.remove(messages, 1) end
    persist('chat', entry.id, { id = entry.id, room = room, author = entry.author, cid = cid, message = message, time = entry.time })
    return { ok = true, data = entry }
end

-- staff remove a message; it stays in the table (hidden) with who removed it
handlers['darkweb:chat:delete'] = function(payload, src)
    if not isChatModerator(src) then return { ok = false, error = 'not_authorized' } end
    local room = chatRoomName(payload.room)
    local id = tonumber(payload.messageId)
    local r = room and dataStore.chatRooms[room]
    if not r or not id then return { ok = false, error = 'message_not_found' } end
    for i, m in ipairs(r.messages) do
        if m.id == id then
            table.remove(r.messages, i)
            local pending = DB.dirty['chat:' .. id]
            if pending then pending.value.hidden, pending.value.hiddenBy = true, GetPlayerIdentifier(src) end
            if DB.mode == 'ready' then
                pcall(function() MySQL.update.await('UPDATE pf_computer_chat SET hidden = 1, hidden_by = ? WHERE id = ?', { GetPlayerIdentifier(src), id }) end)
            end
            return { ok = true }
        end
    end
    return { ok = false, error = 'message_not_found' }
end

handlers['security:config:get'] = function(_, src)
    local securityConfig = Config.Security or {}
    local hackingConfig = Config.Hacking or {}

    return {
        ok = true,
        data = {
            security = securityConfig,
            hacking = hackingConfig,
            adminRecoveryAllowed = HasSecurityRecoveryAccess(src)
        }
    }
end

handlers['security:hack:checkTool'] = function(payload, src)
    local tier = tostring(payload.tier or 'basic')
    local hackCfg = Config.Hacking or {}
    local toolCfg = hackCfg.Tools and hackCfg.Tools[tier] or nil

    if not toolCfg then
        return { ok = false, error = 'invalid_tier' }
    end

    local hasItem, count = GetPlayerHasItem(src, toolCfg.item)
    if not hasItem then
        return { ok = false, error = 'missing_tool', data = { requiredItem = toolCfg.item, label = toolCfg.label or tier, count = 0 } }
    end

    return {
        ok = true,
        data = {
            tier = tier,
            item = toolCfg.item,
            label = toolCfg.label or tier,
            count = count
        }
    }
end

handlers['security:hack:detectTool'] = function(_, src)
    local hackCfg = Config.Hacking or {}
    local tools = hackCfg.Tools or {}
    local priority = { 'master', 'advanced', 'basic' }

    for _, tier in ipairs(priority) do
        local toolCfg = tools[tier]
        if toolCfg and toolCfg.item and toolCfg.item ~= '' then
            local hasItem, count = GetPlayerHasItem(src, toolCfg.item)
            if hasItem then
                return {
                    ok = true,
                    data = {
                        tier = tier,
                        item = toolCfg.item,
                        label = toolCfg.label or tier,
                        count = count,
                        config = toolCfg
                    }
                }
            end
        end
    end

    return { ok = false, error = 'no_hack_tool' }
end

handlers['security:admin:recovery'] = function(_, src)
    if not HasSecurityRecoveryAccess(src) then
        return { ok = false, error = 'not_authorized' }
    end

    return { ok = true, data = { authorized = true } }
end

handlers['devices:phoneImages'] = function(_, src)
    local images = GetPlayerPhoneImages(src)
    return {
        ok = true,
        data = {
            source = (GetResourceState('pfm-phone') == 'started') and 'qb-phone' or 'none',
            images = images
        }
    }
end

handlers['gov:announcements:list'] = function(_)
    local data = loadData()

    if GetResourceState('pf-government') == 'started' then
        local ok, announcements = pcall(function()
            return exports['pf-government']:GetActiveAnnouncements()
        end)

        if ok and type(announcements) == 'table' then
            data.announcements = announcements
            return { ok = true, data = announcements }
        end
    end

    return { ok = true, data = data.announcements or {} }
end

handlers['gov:laws:list'] = function(_)
    local data = loadData()

    if GetResourceState('pf-government') == 'started' then
        local ok, laws = pcall(function()
            return exports['pf-government']:GetPublicLaws()
        end)

        if ok and type(laws) == 'table' then
            data.laws = laws
            return { ok = true, data = laws }
        end
    end

    return { ok = true, data = data.laws or {} }
end

handlers['gov:taxes:list'] = function(_)
    if GetResourceState('pf-government') == 'started' then
        local ok, taxes = pcall(function()
            return exports['pf-government']:GetTaxSchedule()
        end)
        if ok and type(taxes) == 'table' then
            return { ok = true, data = taxes }
        end
    end
    return { ok = true, data = {} }
end

handlers['gov:website:get'] = function(_)
    if GetResourceState('pf-government') == 'started' then
        local ok, siteState = pcall(function()
            return exports['pf-government']:GetWebsiteState()
        end)
        if ok and type(siteState) == 'table' then
            return { ok = true, data = siteState }
        end
    end
    return { ok = true, data = {} }
end

handlers['browser:config:get'] = function(_, src)
    return { ok = true, data = getBrowserConfigPayload(src) }
end

handlers['browser:assistant:query'] = function(payload, _)
    dataStore.browserGuideStats.queries = (tonumber(dataStore.browserGuideStats.queries) or 0) + 1
    return { ok = true, data = findAssistantResponse(cleanText(payload.query, 200, '')) }
end

-- Owners are shown by name; citizen ids are never sent to other players.
handlers['browser:domains:list'] = function(_, src)
    local identifier = GetPlayerIdentifier(src)
    local out = {}
    for _, entry in ipairs(dataStore.browserDomains) do
        out[#out + 1] = {
            domain = entry.domain,
            ownerName = entry.ownerName,
            templateId = entry.templateId,
            purchasedAt = entry.purchasedAt,
            isOwner = identifier ~= nil and entry.ownerIdentifier == identifier
        }
    end
    table.sort(out, function(a, b) return tostring(a.domain) < tostring(b.domain) end)
    return { ok = true, data = out }
end

local function cleanTemplateId(value)
    local templates = Config.Browser and Config.Browser.WebsiteTemplates or {}
    if type(value) == 'string' and templates[value] then return value end
    return 'services'
end

handlers['browser:domain:buy'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    if not identifier then
        return { ok = false, error = 'no_identifier' }
    end

    local domain = normalizeDomain(payload.domain)
    if not domain or #domain > 64 then
        return { ok = false, error = 'invalid_domain' }
    end
    if getReservedDomainInfo(domain) then
        return { ok = false, error = 'reserved_domain' }
    end
    if getDomainOwnerRecord(data, domain) then
        return { ok = false, error = 'domain_taken' }
    end

    -- the price is the server's (the client's payload.price used to be charged, so 0 was free), and
    -- it is paid through the bank ledger
    local price = tonumber((Config.Browser and Config.Browser.DefaultDomainPrice) or 2500) or 2500
    local Player = GetPlayer(src)
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if not cid or GetResourceState('pfm-banking') ~= 'started' then
        return { ok = false, error = 'bank_unavailable' }
    end
    local okCall, res = pcall(function()
        return exports['pfm-banking']:Transfer({
            from = ('player:%s:bank'):format(cid), to = 'system:pf-computer-domains', amount = price,
            key = ('pf-computer:domain:%s:%s'):format(domain, cid), kind = 'purchase',
            reason = 'Domain ' .. domain, actor = cid,
        })
    end)
    if not okCall or type(res) ~= 'table' or not res.ok then
        return { ok = false, error = 'insufficient_funds' }
    end

    local record = {
        domain = domain,
        ownerIdentifier = identifier,
        ownerName = getPlayerName(src),
        templateId = cleanTemplateId(payload.templateId),
        purchasedAt = nowIso(),
        price = price
    }
    data.browserDomains[#data.browserDomains + 1] = record
    ensureWebsiteForDomain(data, record)
    persist('domain', domain)

    return { ok = true, data = { domain = domain, website = data.browserWebsites[domain] } }
end

handlers['browser:website:get'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local domain = normalizeDomain(payload.domain)
    if not domain then
        return { ok = false, error = 'invalid_domain' }
    end

    local reserved = getReservedDomainInfo(domain)
    if reserved and reserved.type == 'government' then
        local siteState = {}
        if GetResourceState('pf-government') == 'started' then
            local ok, exported = pcall(function() return exports['pf-government']:GetWebsiteState() end)
            if ok and type(exported) == 'table' then
                siteState = exported
            end
        end
        return { ok = true, data = { domain = domain, kind = 'government', editable = false, state = siteState } }
    end

    local record = getDomainOwnerRecord(data, domain)
    if not record then
        return { ok = false, error = 'domain_not_found' }
    end

    local state = ensureWebsiteForDomain(data, record)
    return {
        ok = true,
        data = {
            domain = domain,
            kind = 'player',
            editable = identifier ~= nil and record.ownerIdentifier == identifier,
            ownerName = record.ownerName,
            state = state
        }
    }
end

-- A website is plain data the editor made: nested tables of short strings, numbers and booleans,
-- bounded in depth, keys, items and total size (it used to store whatever object the client sent).
local SITE_MAX_BYTES, SITE_MAX_DEPTH, SITE_MAX_ITEMS, SITE_MAX_STRING = 65536, 6, 60, 4000

local function cleanSiteValue(v, depth, budget)
    local t = type(v)
    if t == 'string' then
        budget.n = budget.n + #v
        return v:sub(1, SITE_MAX_STRING)
    elseif t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return v
    elseif t == 'boolean' then
        return v
    elseif t == 'table' then
        if depth >= SITE_MAX_DEPTH then return nil end
        local out, count = {}, 0
        for k, child in pairs(v) do
            count = count + 1
            if count > SITE_MAX_ITEMS then return nil end
            if type(k) ~= 'string' and type(k) ~= 'number' then return nil end
            if type(k) == 'string' and (#k > 40 or not k:match('^[%w_%-]+$')) then return nil end
            local c = cleanSiteValue(child, depth + 1, budget)
            if c == nil and child ~= nil then return nil end
            out[k] = c
        end
        return out
    end
    return nil
end

handlers['browser:website:save'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local domain = normalizeDomain(payload.domain)
    if not domain or type(payload.state) ~= 'table' then
        return { ok = false, error = 'invalid_payload' }
    end

    local record = getDomainOwnerRecord(data, domain)
    if not record then
        return { ok = false, error = 'domain_not_found' }
    end
    if record.ownerIdentifier ~= identifier then
        return { ok = false, error = 'not_owner' }
    end

    local budget = { n = 0 }
    local state = cleanSiteValue(payload.state, 0, budget)
    if type(state) ~= 'table' or budget.n > SITE_MAX_BYTES then
        return { ok = false, error = 'website_too_large' }
    end
    local encoded = json.encode(state)
    if not encoded or #encoded > SITE_MAX_BYTES then
        return { ok = false, error = 'website_too_large' }
    end

    state.domain = domain
    state.owner = { name = record.ownerName }
    state.updatedAt = nowIso()

    data.browserWebsites[domain] = state
    persist('domain', domain)
    return { ok = true, data = state }
end

--- A real character to hand a domain to: an online player (server id or citizen id) or, when the
--- database is up, a character in the players table. Returns citizenid, name.
local function findCitizen(target)
    if type(target) ~= 'string' and type(target) ~= 'number' then return nil end
    local asSrc = tonumber(target)
    if asSrc and asSrc >= 1 and asSrc <= 4096 and asSrc == math.floor(asSrc) then
        local P = GetPlayer(asSrc)
        if P and P.PlayerData then return P.PlayerData.citizenid, getPlayerName(asSrc) end
    end
    local cid = tostring(target):upper()
    if #cid < 3 or #cid > 20 or not cid:match('^[%w]+$') then return nil end
    local online = QBCore and QBCore.Functions.GetPlayerByCitizenId and QBCore.Functions.GetPlayerByCitizenId(cid)
    if online and online.PlayerData then
        local ci = online.PlayerData.charinfo or {}
        return cid, ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    end
    if DB.mode ~= 'ready' then return nil end
    local ok, row = pcall(function() return MySQL.single.await('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid }) end)
    if not ok or type(row) ~= 'table' or row.citizenid ~= cid then return nil end
    local ci = decodeJson(row.charinfo, {})
    return cid, ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
end

handlers['browser:domain:transfer'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local domain = normalizeDomain(payload.domain)
    if not domain then
        return { ok = false, error = 'invalid_payload' }
    end

    local record = getDomainOwnerRecord(data, domain)
    if not record then
        return { ok = false, error = 'domain_not_found' }
    end
    if record.ownerIdentifier ~= identifier then
        return { ok = false, error = 'not_owner' }
    end

    -- the new owner must be a real character; the name is theirs, not one typed by the sender
    local targetCid, targetName = findCitizen(payload.targetIdentifier)
    if not targetCid then
        return { ok = false, error = 'target_not_found' }
    end
    if targetCid == identifier then
        return { ok = false, error = 'already_owner' }
    end

    record.ownerIdentifier = targetCid
    record.ownerName = (targetName and targetName ~= '') and targetName or 'Citizen'

    local site = ensureWebsiteForDomain(data, record)
    if site then
        site.owner = { name = record.ownerName }
        site.updatedAt = nowIso()
    end

    persist('domain', domain)
    return { ok = true, data = { domain = record.domain, ownerName = record.ownerName } }
end

-- City Hall announcements go through pf-government, which checks the permission again, stores them
-- (pf_gov_announcements), audits, emits the city event for the news and mails citizens. This used to
-- write them only into the computer's data file, where nobody else ever saw them.
handlers['gov:announcements:create'] = function(payload, src)
    if GetResourceState('pf-government') ~= 'started' then return { ok = false, error = 'government_offline' } end
    local priority = payload.priority
    if priority ~= 'low' and priority ~= 'normal' and priority ~= 'high' and priority ~= 'urgent' then priority = 'normal' end
    local ok, res = pcall(function()
        return exports['pf-government']:CreateAnnouncementAs(src, {
            title = cleanText(payload.title, MAX_SUBJECT, 'Announcement'),
            content = cleanText(payload.body or payload.content, MAX_BODY, ''),
            priority = priority,
            category = cleanText(payload.category, 30, nil),
            duration = tonumber(payload.duration) and math.max(1, math.min(90, math.floor(tonumber(payload.duration)))) or nil,
        })
    end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'government_unavailable' } end
    return res
end

handlers['gov:cityhall:bootstrap'] = function(_, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    local payload = {
        announcements = {},
        laws = {},
        taxes = {},
        budgets = {},
        utilities = { power = { active = 0, delinquent = 0, disconnected = 0 }, water = { active = 0, delinquent = 0, disconnected = 0 }, totalAccounts = 0 },
        delinquentUtilities = {},
        infrastructure = nil
    }

    if GetResourceState('pf-government') == 'started' then
        local okAnnouncements, announcements = pcall(function()
            return exports['pf-government']:GetActiveAnnouncements()
        end)
        if okAnnouncements and type(announcements) == 'table' then
            payload.announcements = announcements
        end

        local okLaws, laws = pcall(function()
            return exports['pf-government']:GetPublicLaws()
        end)
        if okLaws and type(laws) == 'table' then
            payload.laws = laws
        end

        local okTaxes, taxes = pcall(function()
            return exports['pf-government']:GetTaxSchedule()
        end)
        if okTaxes and type(taxes) == 'table' then
            payload.taxes = taxes
        end

        local okBudgets, budgets = pcall(function()
            return exports['pf-government']:GetAllBudgetDetails()
        end)
        if okBudgets and type(budgets) == 'table' then
            payload.budgets = budgets
        end

        local okUtilities, utilities = pcall(function()
            return exports['pf-government']:GetUtilityOverview()
        end)
        if okUtilities and type(utilities) == 'table' then
            payload.utilities = utilities
        end

        local okDelinquent, delinquent = pcall(function()
            return exports['pf-government']:GetUtilityDelinquentAccounts()
        end)
        if okDelinquent and type(delinquent) == 'table' then
            payload.delinquentUtilities = delinquent
        end

        local okInfra, infra = pcall(function()
            return exports['pf-government']:GetWeeklyUpkeepSummary()
        end)
        if okInfra and type(infra) == 'table' then
            payload.infrastructure = infra
        end
    end

    return { ok = true, data = payload }
end

handlers['gov:laws:setDisplay'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, result = pcall(function()
        return exports['pf-government']:SetLawDisplayEnabled(payload.lawId, payload.sourceType or payload.source, payload.enabled == true, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'law_visibility_failed' }
    end

    return { ok = result == true or type(result) == 'table' }
end

handlers['gov:taxes:update'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:SetTaxRate(payload.taxType, payload.rate, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'tax_update_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:taxes:toggle'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:SetTaxEnabled(payload.taxType, payload.enabled == true, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'tax_toggle_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:budgets:update'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:SetDepartmentBudget(payload.department, payload.weeklyBudget, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'budget_update_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:budgets:upgrade'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, result = pcall(function()
        return exports['pf-government']:PurchaseDepartmentUpgrade(payload.department, payload.upgradeKey, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'upgrade_failed' }
    end

    return { ok = success == true, data = result }
end

handlers['gov:budgets:uninstallUpgrade'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, result = pcall(function()
        return exports['pf-government']:UninstallDepartmentUpgrade(payload.department, payload.upgradeKey, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'uninstall_failed' }
    end

    return { ok = success == true, data = result }
end

handlers['gov:utilities:disconnect'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:DisconnectService(payload.propertyType, payload.propertyId, payload.serviceType, actorId, actorName, payload.reason or 'City Hall action')
    end)

    if not ok then
        return { ok = false, error = 'disconnect_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:utilities:restore'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:RestoreService(payload.propertyType, payload.propertyId, payload.serviceType, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'restore_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:fines:issue'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local amount = tonumber(payload.amount)
    local maxFine = tonumber(Config.Government and Config.Government.MaxFine) or 50000
    if not amount or amount ~= amount or amount < 1 or amount > maxFine then
        return { ok = false, error = 'invalid_amount' }
    end
    if type(payload.targetCitizenId) ~= 'string' or #payload.targetCitizenId > 20 then
        return { ok = false, error = 'invalid_target' }
    end
    amount = math.floor(amount)
    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, result = pcall(function()
        return exports['pf-government']:IssueFineImmediate(payload.targetCitizenId, amount, cleanText(payload.description, 200, 'City fine'), actorId, actorName, payload.dueDate)
    end)

    if not ok then
        return { ok = false, error = 'fine_issue_failed' }
    end

    return { ok = success == true, data = result }
end

-- Server-only: pf-government raises it with TriggerEvent (as a net event any client could fake it).
-- pf-citizen mails the notice to every citizen; here it only refreshes the copy of the law list.
AddEventHandler('pf-computer:gov:laws:sync', function(payload)
    if type(payload) ~= 'table' or type(payload.law) ~= 'table' or not payload.law.id then
        return
    end
    local law = payload.law

    -- the copy gov:laws:list falls back to while pf-government is not answering
    local lawId = tonumber(law.id) or law.id
    local cached
    for _, row in ipairs(dataStore.laws) do if row.id == lawId then cached = row break end end
    if not cached then
        cached = { id = lawId }
        dataStore.laws[#dataStore.laws + 1] = cached
    end
    for _, k in ipairs({ 'title', 'category', 'content', 'status', 'effective_date', 'fine_min', 'fine_max', 'penalty_min', 'penalty_max' }) do
        if law[k] ~= nil then cached[k] = law[k] end
    end

end)

-- =====================================================
-- BUSINESS MANAGER HANDLERS
-- =====================================================

-- Defined below; declared here because getAuthorizedBusiness calls it (it used to resolve to a
-- missing global and error for every non-boss player whose job is not configured).
local isGovJob

local function getAuthorizedBusiness(src, payload)
    local Player = GetPlayer(src)
    local job, grade = GetPlayerJob(src)
    if not job then
        return nil, nil, nil, { ok = false, error = 'missing_job' }
    end

    -- Check if player is boss or government employee
    local isBoss = Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.isboss or false
    
    -- Check for configured job with specific rules
    local jobConfig = Config.BusinessManager.AllowedJobs[job]
    if jobConfig then
        -- Job is configured - check grade requirement
        if grade < jobConfig.minGrade then
            return nil, nil, nil, { ok = false, error = 'insufficient_grade' }
        end
    else
        -- Job not in configured list: bosses only (government jobs used to get in at grade 0)
        if not isBoss then
            return nil, nil, nil, { ok = false, error = 'job_not_allowed' }
        end
        
        -- Create dynamic config for boss/government jobs
        local label = Player.PlayerData.job.label or job
        local blipColor = isGovJob(job) and 1 or 5
        jobConfig = {
            minGrade = 0,
            businessType = isGovJob(job) and 'government' or 'business',
            businessName = label,
            blipColor = blipColor
        }
    end

    if payload and payload.businessId and payload.businessId ~= job then
        return nil, nil, nil, { ok = false, error = 'job_mismatch' }
    end

    return job, grade, jobConfig
end

-- =====================================================
-- BUSINESS MONEY (pfm-banking society accounts)
-- =====================================================
-- A job business's money is its bank society account (the same account paychecks, the boss menu and
-- the bank use), moved only through the pfm-banking ledger. data.businessAccounts[job].transactions is
-- kept as the Business Manager's history/analytics log; its old `balance` field is no longer used
-- (MigrateBusinessAccountsToBank moves the player-funded part of it into the bank once).

local function bizBankReady()
    if GetResourceState('pfm-banking') ~= 'started' then return false end
    local ok, ready = pcall(function() return exports['pfm-banking']:IsLedgerReady() end)
    return ok and ready == true
end

local function bizTransfer(opts)
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

local function bizKey(prefix)
    local ok, key = pcall(function() return exports['pfm-banking']:LedgerAutoKey(prefix) end)
    if ok and type(key) == 'string' then return key end
    return ('%s:%d:%d'):format(prefix, os.time(), math.random(1, 1000000000))
end

local function ensureBusinessBankAccount(job)
    local ok, exists = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(job) end)
    return ok and exists == true
end

--- The business's bank balance, or nil when the bank cannot be read.
local function businessBalance(job)
    if GetResourceState('pfm-banking') ~= 'started' then return nil end
    local ok, balance = pcall(function() return exports['pfm-banking']:GetAccountBalance(job) end)
    if not ok then return nil end
    return tonumber(balance) or 0
end

-- This session's Business Manager actions (deposits, withdrawals, supply orders, recorded POS sales),
-- shown only when the ledger cannot be read; the ledger is the full record.
local function businessHistory(job)
    local account = dataStore.businessAccounts[job] or { transactions = {} }
    dataStore.businessAccounts[job] = account
    return account
end

local function logBusinessTx(job, entry)
    local account = businessHistory(job)
    entry.date = entry.date or nowIso()
    entry.balanceAfter = businessBalance(job)
    table.insert(account.transactions, 1, entry)
    while #account.transactions > 100 do table.remove(account.transactions) end
end


local function getWageCap(level)
    local data = loadData()
    if data.wageCaps[tostring(level)] then
        return data.wageCaps[tostring(level)]
    end
    return Config.BusinessManager.WageCaps[tostring(level)] or 0
end

function isGovJob(job)
    if job == 'mayor' then
        return true
    end
    for _, name in ipairs(Config.GovJobs or {}) do
        if name == job then
            return true
        end
    end
    return false
end

local govBusinessIdFor   -- defined with the premises handlers below

-- ── business figures from real records ─────────────────────────────────────────
-- Money: the bank ledger (pf_transactions, completed rows touching society:<job>).
-- Sales: pf-government's revenue reports for the business (pf_gov_business_revenue), which every
-- register and checkout files per sale. Nothing here is estimated; without the database the
-- figures are simply not shown.
local DAY = 86400
-- ledger kinds that are the owner moving their own money, not trade
local OWNER_KINDS = { deposit = true, withdraw = true, migration = true }

local function ledgerRows(job, sinceSeconds, limit)
    if DB.mode ~= 'ready' or type(job) ~= 'string' then return nil end
    local account = 'society:' .. job
    local ok, rows = pcall(function()
        return MySQL.query.await([[SELECT tx_id, kind, from_account, to_account, amount, reason, actor,
            UNIX_TIMESTAMP(created_at) AS at FROM pf_transactions
            WHERE state = 'completed' AND (to_account = ? OR from_account = ?) AND created_at >= FROM_UNIXTIME(?)
            ORDER BY id DESC LIMIT ?]], { account, account, os.time() - sinceSeconds, limit or 500 })
    end)
    if not ok or type(rows) ~= 'table' then return nil end
    for _, r in ipairs(rows) do
        r.amount = tonumber(r.amount) or 0
        r.at = tonumber(r.at) or 0
        r.incoming = r.to_account == account
    end
    return rows
end

local function revenueRows(job, sinceSeconds)
    if DB.mode ~= 'ready' or type(job) ~= 'string' then return nil end
    local ok, rows = pcall(function()
        return MySQL.query.await([[SELECT amount, tax, UNIX_TIMESTAMP(created_at) AS at FROM pf_gov_business_revenue
            WHERE business_id = ? AND created_at >= FROM_UNIXTIME(?) ORDER BY id DESC LIMIT 2000]],
            { govBusinessIdFor(job), os.time() - sinceSeconds })
    end)
    if not ok or type(rows) ~= 'table' then return {} end   -- pf-government not installed: no sale reports
    for _, r in ipairs(rows) do r.amount, r.tax, r.at = tonumber(r.amount) or 0, tonumber(r.tax) or 0, tonumber(r.at) or 0 end
    return rows
end

--- today / week / month figures: sales (count and value) from the revenue reports, money in and out
--- of the account from the ledger.
local function businessStats(job)
    local ledger = ledgerRows(job, 30 * DAY, 2000)
    if not ledger then return nil end
    local sales = revenueRows(job, 30 * DAY) or {}
    local now = os.time()
    local stats = {}
    for name, span in pairs({ today = DAY, week = 7 * DAY, month = 30 * DAY }) do
        local s = { sales = 0, revenue = 0, transactions = 0, moneyIn = 0, moneyOut = 0 }
        for _, r in ipairs(sales) do
            if now - r.at <= span then s.sales, s.revenue = s.sales + 1, s.revenue + r.amount end
        end
        for _, r in ipairs(ledger) do
            if now - r.at <= span and not OWNER_KINDS[r.kind] then
                s.transactions = s.transactions + 1
                if r.incoming then s.moneyIn = s.moneyIn + r.amount else s.moneyOut = s.moneyOut + r.amount end
            end
        end
        s.revenue = math.floor(s.revenue * 100 + 0.5) / 100
        stats[name] = s
    end
    return stats
end

local function businessAnalytics(job, period)
    local span = ({ day = DAY, week = 7 * DAY, month = 30 * DAY })[period] or 7 * DAY
    local ledger = ledgerRows(job, span, 2000)
    if not ledger then return nil end
    local sales = revenueRows(job, span) or {}
    local out = {
        period = period, totalRevenue = 0, totalSales = #sales, averageTicket = 0, taxPaid = 0,
        moneyIn = 0, moneyOut = 0, transactionCount = 0, byKind = {}, byDay = {},
    }
    local days, kinds = {}, {}
    local function day(at)
        local key = os.date('!%Y-%m-%d', at)
        days[key] = days[key] or { day = key, revenue = 0, sales = 0, moneyIn = 0, moneyOut = 0 }
        return days[key]
    end
    for _, r in ipairs(sales) do
        out.totalRevenue, out.taxPaid = out.totalRevenue + r.amount, out.taxPaid + r.tax
        local d = day(r.at)
        d.revenue, d.sales = d.revenue + r.amount, d.sales + 1
    end
    for _, r in ipairs(ledger) do
        out.transactionCount = out.transactionCount + 1
        local k = kinds[r.kind] or { kind = r.kind, moneyIn = 0, moneyOut = 0, count = 0 }
        kinds[r.kind] = k
        k.count = k.count + 1
        local d = day(r.at)
        if r.incoming then
            k.moneyIn, d.moneyIn = k.moneyIn + r.amount, d.moneyIn + r.amount
            if not OWNER_KINDS[r.kind] then out.moneyIn = out.moneyIn + r.amount end
        else
            k.moneyOut, d.moneyOut = k.moneyOut + r.amount, d.moneyOut + r.amount
            if not OWNER_KINDS[r.kind] then out.moneyOut = out.moneyOut + r.amount end
        end
    end
    if out.totalSales > 0 then out.averageTicket = math.floor(out.totalRevenue / out.totalSales * 100 + 0.5) / 100 end
    for _, k in pairs(kinds) do out.byKind[#out.byKind + 1] = k end
    table.sort(out.byKind, function(a, b) return (a.moneyIn + a.moneyOut) > (b.moneyIn + b.moneyOut) end)
    for _, d in pairs(days) do out.byDay[#out.byDay + 1] = d end
    table.sort(out.byDay, function(a, b) return a.day < b.day end)
    return out
end

--- The company account history: the ledger's rows (every payment in or out of the account, from
--- any resource), newest first.
local function ledgerHistory(job, limit)
    local rows = ledgerRows(job, 90 * DAY, limit or 100)
    if not rows then return nil end
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.tx_id, type = r.kind, amount = r.amount, incoming = r.incoming,
            description = r.reason or r.kind, processedBy = r.actor, date = os.date('!%Y-%m-%dT%H:%M:%SZ', r.at),
        }
    end
    return out
end


--- What the Business Manager shows as the company account: the bank balance and the ledger's rows.
local function businessAccountView(job)
    return { balance = businessBalance(job) or 0, transactions = ledgerHistory(job, 100) or businessHistory(job).transactions }
end

-- =====================================================
-- EXTERNAL DATA PROVIDER SYSTEM
-- =====================================================

-- Map of job names to their data provider resources
local JobDataProviders = {
    mechanic = 'pf-mechanicjob',
    mechanic2 = 'pf-mechanicjob',
    mechanic3 = 'pf-mechanicjob',
    bennys = 'pf-mechanicjob',
    beeker = 'pf-mechanicjob',
    -- Add more mappings as needed:
    -- burgershot = 'pf-restaurant',
    -- uwu = 'pf-restaurant',
}

-- Helper: Check if job has an external data provider
local function GetDataProvider(job)
    local resource = JobDataProviders[job]
    if not resource then
        return nil
    end
    
    if GetResourceState(resource) ~= 'started' then
        return nil
    end
    
    -- Check if resource exports the required functions
    local hasExports = pcall(function()
        return exports[resource].GetBusinessConfig
    end)
    
    if not hasExports then
        return nil
    end
    return resource
end

-- Helper: Get data from external provider or fallback to internal
local function GetExternalOrInternal(job, dataType, ...)
    local provider = GetDataProvider(job)
    local args = { ... }
    
    if not provider then
        return nil, false -- No external provider
    end
    
    local success, result = pcall(function()
        if dataType == 'config' then
            return exports[provider]:GetBusinessConfig(job, table.unpack(args))
        elseif dataType == 'transactions' then
            return exports[provider]:GetBusinessTransactions(job, table.unpack(args))
        elseif dataType == 'analytics' then
            return exports[provider]:GetBusinessAnalytics(job, table.unpack(args))
        elseif dataType == 'employees' then
            return exports[provider]:GetBusinessEmployees(job, table.unpack(args))
        elseif dataType == 'inventory' then
            return exports[provider]:GetBusinessInventory(job, table.unpack(args))
        elseif dataType == 'menuItems' then
            return exports[provider]:GetMenuItems(job, table.unpack(args))
        elseif dataType == 'menuCategories' then
            return exports[provider]:GetMenuCategories(job, table.unpack(args))
        end
    end)
    
    if success and result then
        return result, true -- External data available
    else
        local errMsg = result or 'Unknown error'
    end
    
    return nil, false -- External call failed, use internal
end

-- Get business config for player's job
handlers['business:getConfig'] = function(payload, src)
    local job, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not job then
        return errorResult
    end

    -- Try to get config from external data provider
    local externalConfig, hasExternal = GetExternalOrInternal(job, 'config', src)
    if hasExternal and externalConfig then
        return {
            ok = true,
            data = externalConfig,
            source = 'external'
        }
    end

    -- Fallback to internal data
    local data = loadData()
    local businessType = Config.BusinessManager.BusinessTypes[jobConfig.businessType]
    local settings = data.businesses[job] and data.businesses[job].settings or {}

    return {
        ok = true,
        data = {
            job = job,
            businessName = settings.name or jobConfig.businessName,
            logoUrl = settings.logoUrl or nil,
            businessType = jobConfig.businessType,
            businessTypeConfig = businessType,
            blipColor = settings.blipColor or jobConfig.blipColor,
            blipCoords = settings.blipCoords or nil
        },
        source = 'internal'
    }
end

-- Get business data (overview, stats, etc.)
handlers['business:getData'] = function(payload, src)
    local businessId, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try to get analytics from external data provider
    local externalAnalytics, hasExternal = GetExternalOrInternal(businessId, 'analytics', payload.period)
    if hasExternal and externalAnalytics then
        return {
            ok = true,
            data = {
                id = businessId,
                stats = externalAnalytics,
                totalRevenue = externalAnalytics.allTime and externalAnalytics.allTime.revenue or 0,
                totalTransactions = externalAnalytics.allTime and externalAnalytics.allTime.sales or 0
            },
            source = 'external'
        }
    end

    local business = dataStore.businesses[businessId] or {}
    local stats = businessStats(businessId)
    return {
        ok = true,
        data = {
            id = businessId,
            settings = business.settings or { name = jobConfig and jobConfig.businessName or businessId },
            stats = stats,                       -- nil when the records cannot be read
            totalRevenue = stats and stats.month.revenue or nil,
            totalTransactions = stats and stats.month.transactions or nil,
            balance = businessBalance(businessId),
        },
        source = 'ledger'
    }
end

-- Get analytics data
handlers['business:analytics'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try to get analytics from external data provider
    local externalAnalytics, hasExternal = GetExternalOrInternal(businessId, 'analytics', payload.period)
    if hasExternal and externalAnalytics then
        return {
            ok = true,
            data = externalAnalytics,
            source = 'external'
        }
    end

    local period = (payload.period == 'day' or payload.period == 'month') and payload.period or 'week'
    local analytics = businessAnalytics(businessId, period)
    if not analytics then return { ok = false, error = 'records_unavailable' } end
    return { ok = true, data = analytics, source = 'ledger' }
end

-- Company Account Handlers
handlers['business:account:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    return { ok = true, data = businessAccountView(businessId) }
end

-- A valid amount: finite, positive, at most 2 decimals; nil otherwise.
local function moneyAmount(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n <= 0 or n > 1000000000 then return nil end
    n = math.floor(n * 100 + 0.5) / 100
    if n <= 0 then return nil end
    return n
end

local function bizMoneyError(res)
    if res.error == 'insufficient_funds' then return 'insufficient_funds' end
    if res.error == 'ledger_unavailable' or res.error == 'bank_unavailable' then return 'bank_unavailable' end
    return 'payment_failed'
end

handlers['business:account:deposit'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local amount = moneyAmount(payload.amount)
    if not amount then
        return { ok = false, error = 'invalid_amount' }
    end
    local description = tostring(payload.description or 'Deposit'):sub(1, 100)

    local citizenid = GetPlayerIdentifier(src)
    if not citizenid then
        return { ok = false, error = 'player_not_found' }
    end
    if not bizBankReady() or not ensureBusinessBankAccount(businessId) then
        return { ok = false, error = 'bank_unavailable' }
    end

    -- one ledger transfer: the player's bank -> the business's bank society account
    local res = bizTransfer({
        from = ('player:%s:bank'):format(citizenid), to = 'society:' .. businessId, amount = amount,
        key = bizKey('bizdep'), kind = 'deposit', reason = 'Company account deposit', actor = citizenid,
    })
    if not res.ok then
        return { ok = false, error = bizMoneyError(res) }
    end

    logBusinessTx(businessId, { type = 'deposit', amount = amount, description = description, processedBy = citizenid, txId = res.txId })
    return { ok = true, data = businessAccountView(businessId) }
end

handlers['business:account:withdraw'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- The company account is the job's bank account (wages, sales); like the bank and the boss menu,
    -- only the boss may take money out of it.
    local Player = GetPlayer(src)
    if not (Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.isboss == true) then
        return { ok = false, error = 'not_boss' }
    end

    local amount = moneyAmount(payload.amount)
    if not amount then
        return { ok = false, error = 'invalid_amount' }
    end
    local description = tostring(payload.description or 'Withdrawal'):sub(1, 100)

    local citizenid = GetPlayerIdentifier(src)
    if not citizenid then
        return { ok = false, error = 'player_not_found' }
    end
    if not bizBankReady() then
        return { ok = false, error = 'bank_unavailable' }
    end

    local res = bizTransfer({
        from = 'society:' .. businessId, to = ('player:%s:bank'):format(citizenid), amount = amount,
        key = bizKey('bizwd'), kind = 'withdraw', reason = 'Company account withdrawal', actor = citizenid,
    })
    if not res.ok then
        return { ok = false, error = bizMoneyError(res) }
    end

    logBusinessTx(businessId, { type = 'withdrawal', amount = amount, description = description, processedBy = citizenid, txId = res.txId })
    return { ok = true, data = businessAccountView(businessId) }
end

-- Supplies Ordering Handlers
local function normalizeSuppliesItem(raw)
    local label = raw.label or raw.name or raw.item or raw.id or 'Item'
    local itemId = raw.item or raw.id or (label:gsub('%s+', '_'):lower())
    local category = raw.category or 'General'
    local caseSize = tonumber(raw.caseSize or raw.case_size) or 10
    local pricePerCase = tonumber(raw.pricePerCase or raw.casePrice or raw.cost or raw.price) or 0
    local caseContents = raw.caseContents or (tostring(caseSize) .. 'x ' .. label)

    return {
        item = itemId,
        label = label,
        category = category,
        caseSize = caseSize,
        caseContents = caseContents,
        pricePerCase = pricePerCase,
        image = raw.image
    }
end

local function buildSuppliesCatalog(businessId, src)
    local catalog = {
        items = {},
        categories = {},
        imageBase = 'https://cfx-nui-pfm-inventory/html/images/'
    }

    local configResult, hasExternal = GetExternalOrInternal(businessId, 'config', src)
    local sourceCatalog = configResult and (configResult.suppliesCatalog or (configResult.businessTypeConfig and configResult.businessTypeConfig.suppliesCatalog))

    if sourceCatalog and sourceCatalog.items then
        catalog.imageBase = sourceCatalog.imageBase or catalog.imageBase
        for _, raw in ipairs(sourceCatalog.items) do
            catalog.items[#catalog.items + 1] = normalizeSuppliesItem(raw)
        end
        if sourceCatalog.categories then
            catalog.categories = sourceCatalog.categories
        end
    else
        local businessTypeConfig = configResult and configResult.businessTypeConfig or nil
        local fallbackItems = (businessTypeConfig and (businessTypeConfig.parts or businessTypeConfig.ingredients)) or {}
        for _, raw in ipairs(fallbackItems) do
            catalog.items[#catalog.items + 1] = normalizeSuppliesItem(raw)
        end
    end

    if #catalog.categories == 0 then
        local seen = {}
        for _, item in ipairs(catalog.items) do
            if item.category and not seen[item.category] then
                seen[item.category] = true
                catalog.categories[#catalog.categories + 1] = { id = item.category, label = item.category }
            end
        end
    end

    -- Apply government business license gates when available (ex: tuning).
    if GetResourceState('pf-government') == 'started' then
        local success, licenses = pcall(function()
            return exports['pf-government']:GetBusinessLicenses(businessId)
        end)

        local licenseFlags = {}
        if success and type(licenses) == 'table' then
            for _, license in ipairs(licenses) do
                if tonumber(license.active or 0) == 1 or license.active == true then
                    licenseFlags[tostring(license.license_key or ''):lower()] = true
                end
            end
        end

        if not licenseFlags['tuning_license'] then
            catalog.items = (catalog.items or {})
            local filtered = {}
            for _, item in ipairs(catalog.items) do
                if tostring(item.category or ''):lower() ~= 'tuning' then
                    filtered[#filtered + 1] = item
                end
            end
            catalog.items = filtered

            local catFiltered = {}
            for _, category in ipairs(catalog.categories or {}) do
                local catId = tostring(category.id or category.label or ''):lower()
                if catId ~= 'tuning' then
                    catFiltered[#catFiltered + 1] = category
                end
            end
            catalog.categories = catFiltered
        end
    end

    return catalog
end


-- =====================================================
-- STORE SUPPLIES (pf-stores)
-- =====================================================
-- Player-owned stores are owned by a citizen, not a job. Their supply orders go through pf-stores'
-- exports, which charge the store's bank account (pfm-banking ledger); the JSON business accounts in
-- this resource's data file are never used for stores.
-- payload.mode: 'store' or 'job' picks the business when a player has both; without it a player with
-- an authorised job business gets that, otherwise their store.

local function storeCall(fnName, src, payload)
    if GetResourceState('pf-stores') ~= 'started' then return { ok = false, error = 'stores_offline' } end
    local ok, res = pcall(function() return exports['pf-stores'][fnName](exports['pf-stores'], src, payload) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'stores_unavailable' } end
    return res
end

-- Returns the store this request is about (owned by the player) and the list of their stores.
local function resolveStoreContext(src, payload)
    if GetResourceState('pf-stores') ~= 'started' then return nil, {} end
    local res = storeCall('ListOwnedStores', src, {})
    local stores = (res.ok and res.data and res.data.stores) or {}
    if #stores == 0 then return nil, stores end
    local wanted = payload and payload.storeId and tostring(payload.storeId) or nil
    for _, s in ipairs(stores) do
        if wanted and s.storeId == wanted then return s, stores end
    end
    return stores[1], stores
end

-- Decides which business the Order Supplies request is for. Returns 'store', store, stores or
-- 'job', businessId, nil (or nil, errorResult).
local function resolveSuppliesBusiness(src, payload)
    local mode = payload and payload.mode or nil
    local store, stores = resolveStoreContext(src, payload)
    if mode == 'store' then
        if not store then return nil, { ok = false, error = 'no_store' } end
        return 'store', store, stores
    end
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if businessId then return 'job', businessId, stores end
    if mode ~= 'job' and store then return 'store', store, stores end
    return nil, errorResult
end

-- ── job businesses on the shared supply-order service (pf-stores) ───────────────
-- Job businesses (mechanic shops and the like) kept their own order list in this resource's data
-- file: the business paid, and the goods were never added anywhere. They now order through the same
-- service as stores and restaurants: priced from their catalog, paid from the business bank account,
-- collected by the pickup run or delivered by a trucker on a pallet, and unpacked into the business
-- stock stash bizstash-<job>, which staff open at the business's stash points.
local JOB_KIND = 'jobbiz'

-- A restaurant job orders as its restaurant: pf-restaurants' ingredient catalog and prices, its
-- buyer adapter, and its dry/fridge/freezer stock. (The job-business catalog for a restaurant job was
-- empty, and nothing else in any UI could place a restaurant supply order.)
local function restaurantFor(job)
    if GetResourceState('pf-restaurants') ~= 'started' then return nil end
    local ok, id = pcall(function() return exports['pf-restaurants']:GetRestaurantForJob(job) end)
    return ok and type(id) == 'string' and id or nil
end
local function buyerFor(job)
    local restaurantId = restaurantFor(job)
    if restaurantId then return 'restaurant', restaurantId end
    return JOB_KIND, job
end

local function jobStashId(job) return 'bizstash-' .. tostring(job) end

local function ensureJobStash(job)
    pcall(function()
        exports['pfm-inventory']:CreateInventory(jobStashId(job), { label = tostring(job) .. ' stock', maxweight = 1000000, slots = 80 })
    end)
end

local function knownItem(name)
    local core = QBCore or (GetResourceState('pfm-core') == 'started' and exports['pfm-core']:GetCoreObject()) or nil
    local items = core and core.Shared and core.Shared.Items
    return items == nil or items[name] ~= nil   -- unknown items cannot be stocked, so they cannot be bought
end

local function jobRoute(job)
    local data = loadData()
    local drop = data.businessDeliveryLocations and data.businessDeliveryLocations[job]
    if type(drop) ~= 'table' or not drop.x then return nil end
    local bm = Config.BusinessManager or {}
    local wh = bm.SupplyWarehouse or { label = 'Port Supply Warehouse', coords = { x = 1201.02, y = -3237.56, z = 6.06, w = 0.0 } }
    local d = { x = drop.x, y = drop.y, z = drop.z }
    return {
        pickup = { label = wh.label, coords = wh.coords },
        dropoff = { label = tostring(job), coords = d },
        unload = { label = 'Delivery point', coords = { x = drop.x, y = drop.y, z = drop.z, w = drop.w or 0.0 } },
        trucking = bm.SupplyTrucking or { title = 'Business Supplies', cargoType = 'Business Supplies', payoutRate = 0.12, payoutMin = 150 },
    }
end

-- A trucker can deliver when pf-stores can route the order: the business's own drop-off point, or
-- the default delivery zone City Hall set for the area.
local function deliveryRouteFor(job)
    if GetResourceState('pf-stores') == 'started' then
        local ok, route = pcall(function() return exports['pf-stores']:GetDeliveryRoute(JOB_KIND, job) end)
        if ok then return route ~= nil end
    end
    return jobRoute(job) ~= nil
end

local jobAdapter = {
    canManage = function(src, job)
        local P = GetPlayer(src)
        local j = P and P.PlayerData and P.PlayerData.job
        return j ~= nil and j.name == job and j.isboss == true
    end,
    account = function(job) return 'society:' .. tostring(job) end,
    ensureAccount = function(job) return ensureBusinessBankAccount(job) end,
    price = function(job, cart)
        if type(cart) ~= 'table' or #cart == 0 or #cart > 50 then return nil, 0 end
        local map = {}
        for _, item in ipairs(buildSuppliesCatalog(job, nil).items or {}) do map[item.item] = item end
        local lines, subtotal = {}, 0
        for _, c in ipairs(cart) do
            local it = type(c) == 'table' and map[tostring(c.name or '')] or nil
            local qty = type(c) == 'table' and tonumber(c.quantity) or nil
            if not it or not knownItem(it.item) or not qty or qty ~= math.floor(qty) or qty < 1 or qty > 1000 or (it.pricePerCase or 0) < 0 then
                return nil, 0
            end
            lines[#lines + 1] = { name = it.item, label = it.label, quantity = qty, cost = it.pricePerCase, category = it.category, caseSize = it.caseSize }
            subtotal = subtotal + it.pricePerCase * qty
        end
        return lines, subtotal
    end,
    route = jobRoute,
    -- all of it or none; perishables keep the age of the delivery's wait
    unpack = function(job, lines, _, deliveredAt)
        ensureJobStash(job)
        local inv = exports['pfm-inventory']
        local added = {}
        for _, l in ipairs(lines or {}) do
            local units = math.floor((tonumber(l.quantity) or 0) * (tonumber(l.caseSize) or 1))
            local info = nil
            if deliveredAt then
                local okI, value = pcall(function() return inv:DeliveredInfo(l.name, deliveredAt) end)
                if okI then info = value end
            end
            if units < 1 or not inv:AddItem(jobStashId(job), l.name, units, nil, info, 'pf-computer:job-supplies') then
                for _, a in ipairs(added) do inv:RemoveItem(jobStashId(job), a.name, a.units, nil, 'pf-computer:job-supplies-undo') end
                return false
            end
            added[#added + 1] = { name = l.name, units = units }
        end
        pcall(function() inv:SaveStash(jobStashId(job)) end)
        devicePush('job', job, 'ordersupplies', 'orders', { businessId = job })
        devicePush('job', job, 'businessmanager', 'stock', { businessId = job })
        return true
    end,
}

local jobBuyerRegistered = false
local function registerJobBuyer()
    if GetResourceState('pf-stores') ~= 'started' then return false end
    jobBuyerRegistered = pcall(function() exports['pf-stores']:RegisterBuyerKind(JOB_KIND, jobAdapter) end)
    return jobBuyerRegistered
end
-- the job handlers make sure the buyer is registered (pf-stores may have restarted since)
local function ensureJobBuyer()
    if not jobBuyerRegistered then registerJobBuyer() end
end
CreateThread(function()
    for _ = 1, 60 do
        if registerJobBuyer() then return end
        Wait(1000)
    end
end)
AddEventHandler('onResourceStart', function(name) if name == 'pf-stores' then SetTimeout(1000, registerJobBuyer) end end)

-- Staff open the business stock at one of the business's stash points (checked here: the job and
-- being at that point). The client used to send an event nothing handled, so these never opened.
RegisterNetEvent('pf-computer:server:openBusinessStash', function(businessId, index)
    local src = source
    local P = GetPlayer(src)
    local job = P and P.PlayerData and P.PlayerData.job
    if type(businessId) ~= 'string' or not job or job.name ~= businessId then return end
    index = tonumber(index)
    local data = loadData()
    local locs = data.businesses and data.businesses[businessId] and data.businesses[businessId].stashLocations or {}
    local loc = index and locs[index]
    if not loc or #(GetEntityCoords(GetPlayerPed(src)) - vector3(loc.x, loc.y, loc.z)) > 3.0 then return end
    ensureJobStash(businessId)
    exports['pfm-inventory']:OpenInventory(src, jobStashId(businessId), { label = tostring(businessId) .. ' stock', maxweight = 1000000, slots = 80 })
end)

local function jobOrders(src, job)
    if GetResourceState('pf-stores') ~= 'started' then return {} end
    ensureJobBuyer()
    local kind, buyerId = buyerFor(job)
    local ok, res = pcall(function() return exports['pf-stores']:ListOrdersFor(src, kind, buyerId, 50) end)
    if not ok or type(res) ~= 'table' or not res.ok then return {} end
    return res.data or {}
end

-- supply order statuses (pf-stores order service) -> the app's statuses. The app keeps its labels;
-- the order's own status is sent along as `orderStatus` for anything that wants the detail.
local STORE_ORDER_STATUS = {
    created = 'pending', paid = 'pending',
    ready = 'ready',                         -- paid, waiting for the owner to collect
    awaiting_supplier = 'pending', awaiting_delivery = 'pending',
    assigned = 'in_transit', in_transit = 'in_transit',
    delivered = 'delivered',                 -- on the pallet at the store, not unpacked yet
    unpacked = 'picked_up',
    cancelled = 'cancelled', failed = 'failed',
}
local CANCELLABLE = { awaiting_supplier = true, awaiting_delivery = true }

local function storeCatalog(src, store)
    local res = storeCall('GetOrderSuppliesConfig', src, { storeId = store.storeId })
    if not res.ok then return nil, res end
    local data = res.data or {}
    local catalog = { items = {}, categories = {}, imageBase = 'https://cfx-nui-pfm-inventory/html/images/' }
    local seen = {}
    for _, ing in ipairs((data.businessTypeConfig and data.businessTypeConfig.ingredients) or {}) do
        local category = ing.category or 'Supplies'
        catalog.items[#catalog.items + 1] = {
            item = ing.name, label = ing.label or ing.name, category = category,
            caseSize = 1, caseContents = '1 case', pricePerCase = tonumber(ing.cost) or 0,
            stock = tonumber(ing.stock) or 0,
        }
        if not seen[category] then
            seen[category] = true
            catalog.categories[#catalog.categories + 1] = { id = category, label = category }
        end
    end
    local trucking = data.delivery and data.delivery.trucking or {}
    return catalog, nil, { businessName = data.businessName or store.label, deliveryAvailable = trucking.available == true }
end

local function storeBalance(src, store)
    local res = storeCall('GetStoreBalance', src, { storeId = store.storeId })
    return res.ok and res.data and tonumber(res.data.balance) or nil
end

local function storeOrders(src, store)
    local res = storeCall('ListSupplyOrders', src, { storeId = store.storeId })
    if not res.ok then return nil, res end
    local formatted = {}
    for _, o in ipairs((res.data and res.data.orders) or {}) do
        formatted[#formatted + 1] = {
            id = o.id,
            createdAt = o.createdAt,
            status = STORE_ORDER_STATUS[o.status] or o.status,
            orderStatus = o.status,
            fulfillment = o.method == 'trucking' and 'delivery' or 'pickup',
            total = tonumber(o.total) or 0,
            totalCases = o.totalCases or 0,
            items = o.items or {},
            cancellable = o.method == 'trucking' and CANCELLABLE[o.status] == true,
        }
    end
    return formatted
end

handlers['business:supplies:catalog'] = function(payload, src)
    local mode, business, stores = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end

    if mode == 'store' then
        local catalog, err, meta = storeCatalog(src, business)
        if not catalog then return err end
        return {
            ok = true,
            data = {
                mode = 'store',
                storeId = business.storeId,
                stores = stores,
                businessId = business.storeId,
                businessName = meta.businessName,
                businessType = 'store',
                balance = storeBalance(src, business),
                deliveryAvailable = meta.deliveryAvailable,
                canSwitch = getAuthorizedBusiness(src, {}) ~= nil,
                catalog = catalog,
            }
        }
    end

    local businessId = business

    local restaurantId = restaurantFor(businessId)
    if restaurantId then
        local okR, res = pcall(function() return exports['pf-restaurants']:GetSupplyCatalog(restaurantId) end)
        res = okR and type(res) == 'table' and res or { items = {} }
        local categories, seen = {}, {}
        for _, item in ipairs(res.items or {}) do
            if not seen[item.category] then seen[item.category] = true categories[#categories + 1] = { id = item.category, label = item.category } end
        end
        return {
            ok = true,
            data = {
                mode = 'job',
                businessId = businessId,
                restaurantId = restaurantId,
                deliveryAvailable = res.deliveryAvailable == true,
                businessName = res.label or businessId,
                businessType = 'restaurant',
                canSwitch = stores ~= nil and #stores > 0,
                catalog = { items = res.items or {}, categories = categories, imageBase = 'https://cfx-nui-pfm-inventory/html/images/' },
            }
        }
    end

    local catalog = buildSuppliesCatalog(businessId, src)
    local configResult = GetExternalOrInternal(businessId, 'config', src)

    return {
        ok = true,
        data = {
            mode = 'job',
            businessId = businessId,
            deliveryAvailable = deliveryRouteFor(businessId),
            businessName = configResult and configResult.businessName or businessId,
            businessType = configResult and configResult.businessType or 'business',
            canSwitch = stores ~= nil and #stores > 0,
            catalog = catalog
        }
    }
end

handlers['business:supplies:orders:list'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end
    if mode == 'store' then
        local orders, err = storeOrders(src, business)
        if not orders then return err end
        return { ok = true, data = orders, balance = storeBalance(src, business) }
    end
    local businessId = business
    local formatted = {}
    for _, o in ipairs(jobOrders(src, businessId)) do
        local totalCases = 0
        for _, it in ipairs(o.items or {}) do totalCases = totalCases + (tonumber(it.quantity) or 0) end
        formatted[#formatted + 1] = {
            id = tonumber(o.id),
            createdAt = tonumber(o.created_at) or 0,
            status = STORE_ORDER_STATUS[o.status] or o.status,
            orderStatus = o.status,
            fulfillment = o.method == 'trucking' and 'delivery' or 'pickup',
            total = tonumber(o.total) or 0,
            totalCases = totalCases,
            items = o.items or {},
            cancellable = o.method == 'trucking' and CANCELLABLE[o.status] == true,
        }
    end

    return { ok = true, data = formatted }
end

handlers['business:supplies:orders:create'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end

    if mode == 'store' then
        -- pf-stores prices the cart from its own catalog and charges the store's bank account
        local cart = {}
        for _, req in ipairs(type(payload.items) == 'table' and payload.items or {}) do
            if type(req) == 'table' and req.item then
                cart[#cart + 1] = { name = tostring(req.item), quantity = tonumber(req.quantity) or 0 }
            end
        end
        if #cart == 0 then return { ok = false, error = 'empty_cart' } end
        local method = payload.fulfillment == 'delivery' and 'trucking' or 'pickup'
        local res = storeCall('CheckoutSupplies', src, { storeId = business.storeId, method = method, cart = cart })
        if not res.ok then return res end
        return { ok = true, data = res.data, message = res.message, balance = storeBalance(src, business) }
    end

    local businessId = business
    -- spending a job business's bank account is for its boss
    local orderer = GetPlayer(src)
    if not (orderer and orderer.PlayerData and orderer.PlayerData.job and orderer.PlayerData.job.isboss == true) then
        return { ok = false, error = 'not_authorized' }
    end
    local cart = {}
    for _, req in ipairs(type(payload.items) == 'table' and payload.items or {}) do
        if type(req) == 'table' and req.item then
            cart[#cart + 1] = { name = tostring(req.item), quantity = tonumber(req.quantity) or 0 }
        end
    end
    if #cart == 0 then return { ok = false, error = 'empty_cart' } end
    if GetResourceState('pf-stores') ~= 'started' then return { ok = false, error = 'stores_offline' } end
    local method = payload.fulfillment == 'delivery' and 'trucking' or 'pickup'
    ensureJobBuyer()
    -- pickup orders wait at the supplier until collected (the mechanic pickup run, or Collect)
    local ok, res = pcall(function()
        local kind, buyerId = buyerFor(businessId)
        return exports['pf-stores']:CreateOrder(src, { kind = kind, buyerId = buyerId, method = method, cart = cart, deferDelivery = true })
    end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'stores_unavailable' } end
    if not res.ok then return res end
    logBusinessTx(businessId, { type = 'supplies', amount = res.data and res.data.total or 0, description = 'Supplies Order #' .. tostring(res.data and res.data.orderId) })
    return { ok = true, data = res.data }
end

handlers['business:supplies:orders:cancel'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end
    if mode ~= 'store' then
        local orderId = tonumber(payload.orderId)
        if not orderId or GetResourceState('pf-stores') ~= 'started' then return { ok = false, error = 'not_cancellable' } end
        ensureJobBuyer()
        local kind, buyerId = buyerFor(business)
        local ok, res = pcall(function() return exports['pf-stores']:CancelOrder(src, kind, buyerId, orderId) end)
        if not ok or type(res) ~= 'table' then return { ok = false, error = 'stores_unavailable' } end
        return res
    end
    local res = storeCall('CancelSupplyOrder', src, { storeId = business.storeId, orderId = tonumber(payload.orderId) })
    if not res.ok then return res end
    return { ok = true, data = res.data, balance = storeBalance(src, business) }
end

handlers['business:supplies:orders:pickup'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end
    if mode == 'store' then
        -- a paid order waiting at the supplier goes straight into the store's stock
        return storeCall('DeliverSupplyOrder', src, { storeId = business.storeId, orderId = tonumber(payload.orderId) })
    end
    local businessId = business

    local orderId = tonumber(payload.orderId)
    if not orderId then
        return { ok = false, error = 'invalid_order' }
    end

    if not payload.legacy and GetResourceState('pf-stores') == 'started' then
        ensureJobBuyer()
        local okO, shared = pcall(function() return exports['pf-stores']:GetOrder(orderId) end)
        local kind, buyerId = buyerFor(businessId)
        if okO and type(shared) == 'table' and shared.buyer_kind == kind and shared.store_id == buyerId then
            if shared.status ~= 'ready' then return { ok = false, error = 'order_not_ready' } end
            if kind == JOB_KIND and GetResourceState('pf-mechanicjob') == 'started' then
                -- mechanics drive the parts back: the order is collected when the run is finished
                local called, missionOk, missionReason = pcall(function()
                    return exports['pf-mechanicjob']:StartSuppliesPickup(src, { id = orderId, items = shared.items_json and json.decode(shared.items_json) or {} })
                end)
                if called and missionOk == true then
                    -- remembered per character (and in the database) until the run ends
                    local cid = GetPlayerIdentifier(src)
                    dataStore.pickupRuns[cid] = { orderId = orderId, businessId = businessId, startedAt = os.time() }
                    persist('pickup', cid)
                    return { ok = true, data = { id = orderId } }
                end
                if called and missionReason ~= 'not_mechanic' then
                    return { ok = false, error = missionReason or 'pickup_start_failed' }
                end
            end
            local okC, res = pcall(function() return exports['pf-stores']:CollectOrder(src, kind, buyerId, orderId) end)
            if not okC or type(res) ~= 'table' then return { ok = false, error = 'stores_unavailable' } end
            return res
        end
    end

    -- (orders kept in the old data file are not collectable: they were paid from the old file
    -- balance, and their 'pickup' only ever marked them picked up without stocking anything)
    return { ok = false, error = 'order_not_found' }
end

-- Server-only (pf-mechanicjob raises both when the pickup mission ends at the drop-off: first
-- orderDelivered(orderId, src), then completeOrder(src, orderId)). The run is remembered per
-- character in pf_computer_pickup_runs, so a restart of this resource during the drive does not
-- strand the shared order; whichever event arrives first collects it into the business stock, the
-- other finds nothing left to do. (completeOrder used to be a network event: any client could mark
-- any business's orders as picked up.)
local function finishPickupRun(playerSrc, orderId)
    local src = tonumber(playerSrc)
    local targetOrderId = tonumber(orderId)
    if not src or not targetOrderId then return end
    local cid = GetPlayerIdentifier(src)
    local run = cid and dataStore.pickupRuns[cid]
    if not run or run.orderId ~= targetOrderId then return end
    dataStore.pickupRuns[cid] = nil
    persist('pickup', cid)
    ensureJobBuyer()
    local kind, buyerId = buyerFor(run.businessId)
    local okC, res = pcall(function() return exports['pf-stores']:CollectOrder(src, kind, buyerId, targetOrderId) end)
    if okC and type(res) == 'table' and res.ok then
        TriggerClientEvent('QBCore:Notify', src, 'Supplies unpacked into the business stock', 'success')
        devicePush('player', src, 'ordersupplies', 'orders', { orderId = targetOrderId })
    else
        -- still waiting at the supplier: the run can be started again from Order Supplies
        TriggerClientEvent('QBCore:Notify', src, 'Supplies could not be unpacked: ' .. tostring(okC and res and res.error or 'error'), 'error')
    end
end

AddEventHandler('pf-computer:server:supplies:orderDelivered', function(orderId, playerSrc)
    finishPickupRun(playerSrc, orderId)
end)

AddEventHandler('pf-computer:server:supplies:completeOrder', function(playerSrc, orderId)
    finishPickupRun(playerSrc, orderId)
end)

-- Menu and meals kept by this resource (jobs without a provider resource). Plain bounded values:
-- these prices feed the business's own registers, so they are checked numbers, not whatever the app sent.
local MAX_MENU_ITEMS, MAX_MEALS = 200, 100

local function priceOf(v, default)
    local n = tonumber(v)
    if not n or n ~= n or n < 0 or n > 100000 then return default end
    return math.floor(n * 100 + 0.5) / 100
end

local function cleanMealItems(list)
    local out = {}
    for _, it in ipairs(type(list) == 'table' and list or {}) do
        if #out >= 20 then break end
        local id, qty = tonumber(type(it) == 'table' and it.itemId), tonumber(type(it) == 'table' and it.quantity)
        if id and qty and qty >= 1 and qty <= 20 then out[#out + 1] = { itemId = math.floor(id), quantity = math.floor(qty) } end
    end
    return out
end

-- List menu items
handlers['business:menu:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try external data provider first (for mechanic jobs)
    local externalMenu, hasExternal = GetExternalOrInternal(businessId, 'menuItems')
    if hasExternal and externalMenu then
        return { ok = true, data = externalMenu }
    end

    -- Fallback to internal data
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    return { ok = true, data = menu }
end

-- Add menu item
handlers['business:menu:add'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local item = payload.item or {}
    
    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database insert
        local success, addResult = pcall(function()
            return exports[provider]:AddMenuItem(businessId, item)
        end)
        
        if success and addResult then
            local resultItem = {
                business = businessId,
                item_id = item.id or item.name or 'item_' .. os.time(),
                category = item.category or 'General',
                name = item.name or 'New Item',
                label = item.name or 'New Item',
                price = tonumber(item.price) or 0
            }
            return { ok = true, data = resultItem }
        else
            local errorMsg = success and tostring(addResult) or tostring(success)
            print(string.format('[ERROR] Failed to add menu item via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_add_item', message = errorMsg }
        end
    end

    -- this resource's own menu
    local data = loadData()
    data.businessMenus[businessId] = data.businessMenus[businessId] or {}
    if #data.businessMenus[businessId] >= MAX_MENU_ITEMS then return { ok = false, error = 'menu_full' } end
    local price = priceOf(item.price, nil)
    if not price then return { ok = false, error = 'invalid_price' } end

    local menuItem = {
        id = nextId('menuItems'),
        name = cleanText(item.name, 60, 'New Item'),
        description = cleanText(item.description, 300, ''),
        category = cleanText(item.category, 40, 'General'),
        price = price,
        cost = priceOf(item.cost, 0),
        image = cleanText(item.image, 300, ''),
        available = item.available ~= false,
        onSale = item.onSale == true,
        salePrice = priceOf(item.salePrice, nil),
        createdAt = nowIso()
    }

    data.businessMenus[businessId][#data.businessMenus[businessId] + 1] = menuItem
    persistBusiness(businessId)

    return { ok = true, data = menuItem }
end

-- Update menu item
handlers['business:menu:update'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local itemId = payload.itemId

    if not itemId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    local menu = data.businessMenus[businessId] or {}
    for i, item in ipairs(menu) do
        if item.id == itemId then
            if payload.price ~= nil and not priceOf(payload.price, nil) then return { ok = false, error = 'invalid_price' } end
            item.name = cleanText(payload.name, 60, item.name)
            item.description = cleanText(payload.description, 300, item.description)
            item.category = cleanText(payload.category, 40, item.category)
            item.price = priceOf(payload.price, item.price)
            item.cost = priceOf(payload.cost, item.cost)
            if payload.available ~= nil then item.available = payload.available == true end
            if payload.onSale ~= nil then item.onSale = payload.onSale == true end
            item.salePrice = priceOf(payload.salePrice, item.salePrice)
            item.updatedAt = nowIso()
            persistBusiness(businessId)
            
            return { ok = true, data = item }
        end
    end
    
    return { ok = false, error = 'item_not_found' }
end

-- Delete menu item
handlers['business:menu:delete'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local itemId = payload.itemId

    if not itemId then
        return { ok = false, error = 'missing_parameters' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database delete
        local success, deleteResult = pcall(function()
            return exports[provider]:DeleteMenuItem(businessId, itemId)
        end)
        
        if success and deleteResult then
            return { ok = true }
        else
            local errorMsg = success and tostring(deleteResult) or tostring(success)
            print(string.format('[ERROR] Failed to delete menu item via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_delete_item', message = errorMsg }
        end
    end

    -- Fallback to internal data storage
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    for i, item in ipairs(menu) do
        if item.id == itemId then
            table.remove(menu, i)
            persistBusiness(businessId)
            return { ok = true }
        end
    end
    
    return { ok = false, error = 'item_not_found' }
end

-- =====================================================
-- MEAL ITEMS MANAGEMENT (composite dishes)
-- =====================================================

-- List meal items
handlers['business:meals:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    data.businessMeals = data.businessMeals or {}
    
    local meals = data.businessMeals[businessId] or {}
    return { ok = true, data = meals }
end

-- Add meal item
handlers['business:meals:add'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    data.businessMeals = data.businessMeals or {}
    
    if not data.businessMeals[businessId] then
        data.businessMeals[businessId] = {}
    end
    
    if #data.businessMeals[businessId] >= MAX_MEALS then return { ok = false, error = 'too_many_meals' } end
    local price = priceOf(payload.price, nil)
    if not price then return { ok = false, error = 'invalid_price' } end
    local meal = {
        id = nextId('meals'),
        name = cleanText(payload.name, 60, 'New Meal'),
        description = cleanText(payload.description, 300, ''),
        items = cleanMealItems(payload.items),
        price = price,
        available = payload.available ~= false,
        createdAt = nowIso()
    }

    data.businessMeals[businessId][#data.businessMeals[businessId] + 1] = meal
    persistBusiness(businessId)
    
    return { ok = true, data = meal }
end

-- Update meal item
handlers['business:meals:update'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local mealId = payload.mealId

    if not mealId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    data.businessMeals = data.businessMeals or {}
    local meals = data.businessMeals[businessId] or {}
    for i, meal in ipairs(meals) do
        if meal.id == mealId then
            if payload.price ~= nil and not priceOf(payload.price, nil) then return { ok = false, error = 'invalid_price' } end
            meal.name = cleanText(payload.name, 60, meal.name)
            meal.description = cleanText(payload.description, 300, meal.description)
            if payload.items ~= nil then meal.items = cleanMealItems(payload.items) end
            meal.price = priceOf(payload.price, meal.price)
            if payload.available ~= nil then meal.available = payload.available == true end
            meal.updatedAt = nowIso()
            persistBusiness(businessId)
            
            return { ok = true, data = meal }
        end
    end
    
    return { ok = false, error = 'meal_not_found' }
end

-- Delete meal item
handlers['business:meals:delete'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local mealId = payload.mealId

    if not mealId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    data.businessMeals = data.businessMeals or {}
    local meals = data.businessMeals[businessId] or {}
    for i, meal in ipairs(meals) do
        if meal.id == mealId then
            table.remove(meals, i)
            persistBusiness(businessId)
            return { ok = true }
        end
    end
    
    return { ok = false, error = 'meal_not_found' }
end

-- List transactions
handlers['business:transactions:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local limit = math.max(1, math.min(200, math.floor(tonumber(payload.limit) or 50)))

    -- Try to get transactions from external data provider
    local externalTransactions, hasExternal = GetExternalOrInternal(businessId, 'transactions', limit)
    if hasExternal and externalTransactions then
        local normalized = {}
        for _, tx in ipairs(externalTransactions) do
            local items = {}
            if tx.items and type(tx.items) == 'table' then
                for _, item in ipairs(tx.items) do
                    items[#items + 1] = {
                        name = item.label or item.item or 'Item',
                        quantity = item.qty or item.quantity or 1,
                        price = item.unitPrice or item.price or 0
                    }
                end
            end

            normalized[#normalized + 1] = {
                id = tx.transaction_id or tx.id,
                date = tx.created_at or tx.createdAt,
                type = tx.type or 'sale',
                items = items,
                itemsCount = #items,
                employee = tx.mechanic_name or tx.employee or tx.processedBy,
                paymentMethod = tx.payment_type or tx.paymentMethod,
                amount = tx.total or tx.amount or 0
            }
        end

        return {
            ok = true,
            data = normalized,
            source = 'external'
        }
    end

    -- the business account's ledger rows (money in and out, from any resource)
    local history = ledgerHistory(businessId, limit)
    if not history then return { ok = false, error = 'records_unavailable' } end
    return { ok = true, data = history, source = 'ledger' }
end

-- ── Employees ──────────────────────────────────────────────────────────────────
-- The business's staff are the characters whose job is the business's job (the players table, and
-- the live data of those online), with their pfm-core grade. Promote, demote and fire work like
-- pfm-management's boss menu: the boss's own job only, never someone ranked above the boss, never a
-- grade above the boss's own, never the boss themselves; the change is saved on the character.
local function jobGrades(job)
    local shared = QBCore and QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[job]
    return shared and shared.grades or {}
end

local function gradeLabel(job, level)
    local g = jobGrades(job)[tostring(level)]
    return g and g.name or ('Grade ' .. tostring(level))
end

local function employeeRow(cid, name, job, online)
    local level = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade) or 0
    local g = jobGrades(job.name)[tostring(level)] or {}
    return {
        id = cid, citizenid = cid, name = name, grade = level, rank = g.name or gradeLabel(job.name, level),
        isBoss = job.isboss == true or g.isboss == true, isActive = online, online = online,
        onDuty = online and job.onduty == true or false, salary = tonumber(g.payment) or 0,
    }
end

local function listEmployees(job)
    local byCid = {}
    if DB.mode == 'ready' then
        local ok, rows = pcall(function()
            return MySQL.query.await([[SELECT citizenid, charinfo, job FROM players
                WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ? LIMIT 300]], { job })
        end)
        for _, r in ipairs(ok and type(rows) == 'table' and rows or {}) do
            local j, ci = decodeJson(r.job, {}), decodeJson(r.charinfo, {})
            if j.name == job then
                local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
                byCid[r.citizenid] = employeeRow(r.citizenid, name ~= '' and name or r.citizenid, j, false)
            end
        end
    end
    local onlinePlayers = QBCore.Functions.GetQBPlayers and QBCore.Functions.GetQBPlayers() or {}
    for _, P in pairs(onlinePlayers) do
        local pd = P and P.PlayerData
        if pd and pd.job and pd.job.name == job then
            local ci = pd.charinfo or {}
            byCid[pd.citizenid] = employeeRow(pd.citizenid, ((ci.firstname or '') .. ' ' .. (ci.lastname or '')), pd.job, true)
        end
    end
    local list = {}
    for _, e in pairs(byCid) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if a.isBoss ~= b.isBoss then return a.isBoss end
        if a.grade ~= b.grade then return a.grade > b.grade end
        return a.name < b.name
    end)
    return list
end

handlers['business:employees:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local externalEmployees, hasExternal = GetExternalOrInternal(businessId, 'employees')
    if hasExternal and externalEmployees then
        return { ok = true, data = externalEmployees, source = 'external' }
    end

    local grades = {}
    for level, g in pairs(jobGrades(businessId)) do
        grades[#grades + 1] = { level = tonumber(level) or 0, label = g.name or ('Grade ' .. level), isBoss = g.isboss == true }
    end
    table.sort(grades, function(a, b) return a.level < b.level end)
    return { ok = true, data = listEmployees(businessId), grades = grades, source = 'roster' }
end

local function bossAndEmployee(src, targetCid)
    local Boss = GetPlayer(src)
    local bossJob = Boss and Boss.PlayerData and Boss.PlayerData.job
    if not bossJob or bossJob.isboss ~= true then return nil, nil, 'not_boss' end
    if type(targetCid) ~= 'string' or #targetCid > 20 then return nil, nil, 'invalid_employee' end
    local Employee = QBCore.Functions.GetPlayerByCitizenId(targetCid)
        or (QBCore.Functions.GetOfflinePlayerByCitizenId and QBCore.Functions.GetOfflinePlayerByCitizenId(targetCid))
    local ej = Employee and Employee.PlayerData and Employee.PlayerData.job
    if not ej or ej.name ~= bossJob.name then return nil, nil, 'employee_not_found' end
    if (tonumber(ej.grade and ej.grade.level) or 0) > (tonumber(bossJob.grade and bossJob.grade.level) or 0) then
        return nil, nil, 'outranks_you'
    end
    return Boss, Employee
end

local function notifyOnline(Player, message, kind)
    local s = Player and Player.PlayerData and Player.PlayerData.source
    if s then TriggerClientEvent('QBCore:Notify', s, message, kind or 'primary') end
end

-- Rank changes and firing in a job business use pfm-management's staff rules (the boss menu's and
-- the Boss app's: real ranks only, never yourself, never above your own rank, never someone ranked
-- above you). Only when pfm-management is not running does the computer apply the same checks itself.
local MANAGEMENT_ERRORS = {
    not_boss = 'not_boss', not_member = 'employee_not_found', outranks_you = 'outranks_you', bad_grade = 'invalid_grade',
    unknown_grade = 'invalid_grade', cannot_change_self = 'cannot_change_self', grade_above_yours = 'grade_above_yours',
    cannot_fire_self = 'cannot_fire_self', bad_request = 'invalid_employee', failed = 'fire_failed',
}
local function managementCall(fnName, ...)
    if GetResourceState('pfm-management') ~= 'started' then return false end
    local args = { ... }
    local called, ok, res = pcall(function() return exports['pfm-management'][fnName](exports['pfm-management'], table.unpack(args)) end)
    if not called then return false end   -- an older pfm-management without the export
    if ok == true then return true, true, res end
    return true, false, MANAGEMENT_ERRORS[res] or 'not_authorized'
end

-- promote / demote: payload.employeeId (citizen id), payload.grade (the new grade)
handlers['business:employees:update'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then return errorResult end
    local grade = tonumber(payload.grade)
    local handled, done, res = managementCall('SetEmployeeGrade', src, payload.employeeId, grade, 'job')
    if handled then
        if not done then return { ok = false, error = res } end
        devicePush('job', businessId, 'businessmanager', 'staff', { businessId = businessId })
        return { ok = true, data = { citizenid = payload.employeeId, grade = grade, rank = gradeLabel(businessId, grade) } }
    end
    local Boss, Employee, err = bossAndEmployee(src, payload.employeeId)
    if not Boss then return { ok = false, error = err } end
    if Employee.PlayerData.citizenid == Boss.PlayerData.citizenid then return { ok = false, error = 'cannot_change_self' } end
    local bossLevel = tonumber(Boss.PlayerData.job.grade.level) or 0
    if not grade or grade < 0 or grade % 1 ~= 0 or not jobGrades(businessId)[tostring(grade)] then
        return { ok = false, error = 'invalid_grade' }
    end
    if grade > bossLevel then return { ok = false, error = 'grade_above_yours' } end
    if not Employee.Functions.SetJob(businessId, grade) then return { ok = false, error = 'invalid_grade' } end
    if Employee.Functions.Save then Employee.Functions.Save() end
    notifyOnline(Employee, ('Your rank is now %s.'):format(gradeLabel(businessId, grade)), 'success')
    devicePush('job', businessId, 'businessmanager', 'staff', { businessId = businessId })
    return { ok = true, data = { citizenid = Employee.PlayerData.citizenid, grade = grade, rank = gradeLabel(businessId, grade) } }
end

handlers['business:employees:fire'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then return errorResult end
    -- pfm-management also tells them and mails them that the job ended
    local handled, done, res = managementCall('FireEmployee', src, payload.employeeId, 'job')
    if handled then
        if not done then return { ok = false, error = res } end
        devicePush('job', businessId, 'businessmanager', 'staff', { businessId = businessId })
        return { ok = true }
    end
    local Boss, Employee, err = bossAndEmployee(src, payload.employeeId)
    if not Boss then return { ok = false, error = err } end
    if Employee.PlayerData.citizenid == Boss.PlayerData.citizenid then return { ok = false, error = 'cannot_fire_self' } end
    if not Employee.Functions.SetJob('unemployed', '0') then return { ok = false, error = 'fire_failed' } end
    if Employee.Functions.Save then Employee.Functions.Save() end
    notifyOnline(Employee, 'You have been let go from your job.', 'error')
    sendCitizenMail(Employee.PlayerData.citizenid, {
        sender = (dataStore.businesses[businessId] and dataStore.businesses[businessId].settings.name) or businessId,
        senderType = 'business', subject = 'Employment ended',
        message = ('Your employment at %s has ended.'):format(Boss.PlayerData.job.label or businessId),
    })
    devicePush('job', businessId, 'businessmanager', 'staff', { businessId = businessId })
    return { ok = true }
end

-- ── Stock ──────────────────────────────────────────────────────────────────────
-- What is physically in the business's stock stashes (see business:stock:get).
local function stockItems(businessId)
    local inv = exports['pfm-inventory']
    local areas = {}
    local restaurantId = restaurantFor(businessId)
    if restaurantId then
        local ok, list = pcall(function() return exports['pf-restaurants']:GetStockStashes(restaurantId) end)
        areas = ok and type(list) == 'table' and list or {}
    else
        ensureJobStash(businessId)
        areas = { { area = 'stock', stashId = jobStashId(businessId) } }
    end
    local items = {}
    for _, a in ipairs(areas) do
        local okI, stash = pcall(function() return inv:GetInventory(a.stashId) end)
        for _, it in pairs(okI and type(stash) == 'table' and stash.items or {}) do
            if type(it) == 'table' and it.name then
                local okF, fresh = pcall(function() return inv:GetFreshness(it.name, it.info) end)
                items[#items + 1] = {
                    name = it.name, label = it.label or it.name, amount = tonumber(it.amount) or 0, area = a.area,
                    freshness = okF and type(fresh) == 'table' and { label = fresh.label, pct = fresh.pct } or nil,
                }
            end
        end
    end
    table.sort(items, function(x, y) if x.area ~= y.area then return x.area < y.area end return tostring(x.label) < tostring(y.label) end)
    return items
end

handlers['business:inventory:get'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end
    local itemName = type(payload.item) == 'string' and payload.item:sub(1, 64) or nil
    if not itemName then return { ok = false, error = 'invalid_item' } end
    local stock = 0
    for _, it in ipairs(stockItems(businessId)) do
        if it.name == itemName then stock = stock + it.amount end
    end
    return { ok = true, stock = stock, item = itemName, source = 'stash' }
end

handlers['business:inventory:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end
    return { ok = true, items = stockItems(businessId), source = 'stash' }
end

local function ensureBusinessRecord(businessId)
    dataStore.businesses[businessId] = dataStore.businesses[businessId] or { id = businessId }
    local b = dataStore.businesses[businessId]
    b.settings = b.settings or {}
    b.stashLocations = b.stashLocations or {}
    return b
end

-- Name, logo and blip of the business. The blip goes where the boss stands, like business:blips:save
-- (any coordinates on the map used to be accepted here); colours are GTA blip colour ids.
handlers['business:update:settings'] = function(payload, src)
    local businessId, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local name = cleanText(payload.name, 50, nil)
    local logoUrl = payload.logoUrl
    if logoUrl ~= nil then
        logoUrl = cleanText(logoUrl, 300, nil)
        if logoUrl == nil or (logoUrl ~= '' and not logoUrl:match('^https://[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=%%]+$')) then
            return { ok = false, error = 'invalid_logo' }
        end
    end
    local blipColor = payload.blipColor
    if blipColor ~= nil then
        blipColor = tonumber(blipColor)
        if not blipColor or blipColor % 1 ~= 0 or blipColor < 0 or blipColor > 85 then return { ok = false, error = 'invalid_color' } end
    end
    local coords
    if payload.blipCoords ~= nil then
        local c = payload.blipCoords
        local bx, by, bz = type(c) == 'table' and finiteNumber(c.x), type(c) == 'table' and finiteNumber(c.y), type(c) == 'table' and finiteNumber(c.z)
        if not (bx and by and bz) or #(GetEntityCoords(GetPlayerPed(src)) - vector3(bx, by, bz)) > 10.0 then
            return { ok = false, error = 'invalid_coords' }
        end
        coords = { x = bx, y = by, z = bz }
    end

    local business = ensureBusinessRecord(businessId)
    if name and name ~= '' then business.settings.name = name end
    if logoUrl ~= nil then business.settings.logoUrl = logoUrl end   -- '' removes the logo
    if blipColor then business.settings.blipColor = blipColor end
    if coords then business.settings.blipCoords = coords end
    persistBusiness(businessId)

    TriggerClientEvent('pf-computer:client:updateBusinessBlip', -1, {
        businessId = businessId,
        name = business.settings.name or jobConfig.businessName,
        color = business.settings.blipColor or jobConfig.blipColor,
        coords = business.settings.blipCoords,
        businessType = jobConfig.businessType,
        sprite = jobConfig.blipIcon
    })
    devicePush('job', businessId, 'businessmanager', 'settings', { businessId = businessId })

    return { ok = true }
end

-- Wages a boss sets are what pfm-core's paycheck pays: they are written into the job's grades
-- through pfm-core's UpdateJob (the paycheck reads the grade payment), capped by the city's wage
-- caps, and applied again at every start. (They used to be stored and shown, and paid by nothing.)
local baseWages = {}   -- [job][grade] = the job's own payment before any boss change

local function applyWages(job)
    local shared = QBCore and QBCore.Shared.Jobs[job]
    if not shared then return false end
    baseWages[job] = baseWages[job] or {}
    local copy = {}
    for k, v in pairs(shared) do copy[k] = v end
    copy.grades = {}
    for g, info in pairs(shared.grades or {}) do
        local gi = {}
        for k, v in pairs(info) do gi[k] = v end
        local key = tostring(g)
        if baseWages[job][key] == nil then baseWages[job][key] = tonumber(info.payment) or 0 end
        local wage = dataStore.businessWages[job] and dataStore.businessWages[job][key] or baseWages[job][key]
        local cap = getWageCap(key)
        if cap > 0 and wage > cap then wage = cap end
        gi.payment = wage
        copy.grades[g] = gi
    end
    local ok, res = pcall(function() return exports['pfm-core']:UpdateJob(job, copy) end)
    if not ok or res ~= true then return false end
    QBCore.Shared.Jobs[job] = copy
    return true
end

onStorageReady[#onStorageReady + 1] = function()
    for job in pairs(dataStore.businessWages) do applyWages(job) end
end

handlers['business:wages:get'] = function(payload, src)
    local Player = GetPlayer(src)
    if not Player or not Player.PlayerData.job.isboss then
        return { ok = false, error = 'not_boss' }
    end

    local job = Player.PlayerData.job.name
    local jobData = QBCore.Shared.Jobs[job]
    if not jobData then
        return { ok = false, error = 'job_not_found' }
    end

    local data = loadData()
    data.businessWages[job] = data.businessWages[job] or {}

    local grades = {}
    for grade, gradeInfo in pairs(jobData.grades or {}) do
        local level = tostring(grade)
        local defaultPay = gradeInfo.payment or 0
        local wage = data.businessWages[job][level] or defaultPay
        grades[#grades + 1] = {
            level = tonumber(level) or 0,
            label = gradeInfo.name or ('Grade ' .. level),
            wage = wage,
            cap = getWageCap(level)
        }
    end

    table.sort(grades, function(a, b)
        return a.level < b.level
    end)

    return { ok = true, data = { job = job, grades = grades } }
end

handlers['business:wages:set'] = function(payload, src)
    local Player = GetPlayer(src)
    if not Player or not Player.PlayerData.job.isboss then
        return { ok = false, error = 'not_boss' }
    end

    local job = Player.PlayerData.job.name
    local jobData = QBCore.Shared.Jobs[job]
    if not jobData then
        return { ok = false, error = 'job_not_found' }
    end

    local wages = type(payload.wages) == 'table' and payload.wages or {}
    local data = loadData()
    local before = data.businessWages[job] or {}
    local nextWages = {}
    for k, v in pairs(before) do nextWages[k] = v end

    local errors = {}
    for level, amount in pairs(wages) do
        local levelKey = tostring(level)
        local numeric = tonumber(amount)
        if not (jobData.grades and jobData.grades[levelKey]) or not numeric or numeric ~= numeric or numeric < 0 or numeric > 100000 then
            return { ok = false, error = 'invalid_wage' }
        else
            local cap = getWageCap(levelKey)
            if cap > 0 and numeric > cap then
                errors[#errors + 1] = { level = tonumber(levelKey) or levelKey, cap = cap }
            else
                nextWages[levelKey] = math.floor(numeric)
            end
        end
    end
    if #errors > 0 then
        return { ok = false, error = 'cap_exceeded', data = { errors = errors } }
    end

    data.businessWages[job] = nextWages
    if not applyWages(job) then
        data.businessWages[job] = before
        return { ok = false, error = 'payroll_unavailable' }
    end
    persistBusiness(job)

    return handlers['business:wages:get']({}, src)
end

-- Stash/Storage placement handler
handlers['business:stash:place'] = function(payload, src)
    local businessId, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local coords = payload.coords
    if type(coords) ~= 'table' or not coords.x or not coords.y or not coords.z then
        return { ok = false, error = 'invalid_coords' }
    end
    -- placed where the boss stands (the UI sends the player's position), and a limited number
    local cx, cy, cz = finiteNumber(coords.x), finiteNumber(coords.y), finiteNumber(coords.z)
    if not (cx and cy and cz) or #(GetEntityCoords(GetPlayerPed(src)) - vector3(cx, cy, cz)) > 10.0 then
        return { ok = false, error = 'invalid_coords' }
    end
    coords = { x = cx, y = cy, z = cz }

    local data = loadData()
    data.businesses = data.businesses or {}
    data.businesses[businessId] = data.businesses[businessId] or {
        id = businessId,
        settings = {}
    }
    data.businesses[businessId].stashLocations = data.businesses[businessId].stashLocations or {}
    if #data.businesses[businessId].stashLocations >= ((Config.BusinessManager and Config.BusinessManager.MaxStashes) or 10) then
        return { ok = false, error = 'too_many_stashes' }
    end

    -- Add new stash location
    table.insert(data.businesses[businessId].stashLocations, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        createdAt = nowIso(),
        createdBy = GetPlayer(src).PlayerData.citizenid
    })

    persistBusiness(businessId)

    -- Notify all clients to update stash targets
    TriggerClientEvent('pf-computer:client:updateStashes', -1, {
        businessId = businessId,
        stashLocations = data.businesses[businessId].stashLocations
    })

    return { ok = true, data = { count = #data.businesses[businessId].stashLocations } }
end

-- Get all business stashes (for resource start initialization)
handlers['business:stashes:getAll'] = function(payload, src)
    local data = loadData()
    local stashes = {}
    
    for businessId, businessData in pairs(data.businesses or {}) do
        if businessData.stashLocations and #businessData.stashLocations > 0 then
            stashes[businessId] = businessData.stashLocations
        end
    end
    
    return { ok = true, data = stashes }
end

-- Wage caps for mayor
handlers['gov:wagecaps:get'] = function(_, src)
    local job, _ = GetPlayerJob(src)
    if not job or not isGovJob(job) then
        return { ok = false, error = 'not_authorized' }
    end

    local data = loadData()
    local caps = {}
    for level, cap in pairs(Config.BusinessManager.WageCaps) do
        caps[level] = data.wageCaps[level] or cap
    end
    for level, cap in pairs(data.wageCaps) do
        if caps[level] == nil then
            caps[level] = cap
        end
    end

    return { ok = true, data = { caps = caps } }
end

handlers['gov:wagecaps:set'] = function(payload, src)
    local job, _ = GetPlayerJob(src)
    if not job or not isGovJob(job) then
        return { ok = false, error = 'not_authorized' }
    end

    local data = loadData()
    local caps = type(payload.caps) == 'table' and payload.caps or {}
    for level, cap in pairs(caps) do
        local numeric = tonumber(cap)
        local key = tostring(level)
        if numeric and numeric == numeric and numeric >= 0 and numeric <= 100000 and #key <= 8 then
            data.wageCaps[key] = math.floor(numeric)
            persist('wagecap', key)
        end
    end
    -- lower caps apply to wages already set
    for wageJob in pairs(data.businessWages) do applyWages(wageJob) end

    return handlers['gov:wagecaps:get']({}, src)
end

-- Clients ask for stash points and blips when they load; those that asked before the tables were
-- loaded got none, so everyone is sent them once the tables are in.
onStorageReady[#onStorageReady + 1] = function()
    for businessId, b in pairs(dataStore.businesses) do
        if b.stashLocations and #b.stashLocations > 0 then
            TriggerClientEvent('pf-computer:client:updateStashes', -1, { businessId = businessId, stashLocations = b.stashLocations })
        end
    end
    for _, blip in pairs(dataStore.businessBlips) do
        TriggerClientEvent('pf-computer:client:updateBusinessBlip', -1, blip)
    end
end

-- Get persisted business blips on startup
handlers['business:blips:get'] = function(payload, src)
    local data = loadData()
    data.businessBlips = data.businessBlips or {}
    
    local blips = {}
    for businessId, blipData in pairs(data.businessBlips) do
        blips[#blips + 1] = blipData
    end
    
    return { ok = true, data = blips }
end

-- Save business blip
handlers['business:blips:save'] = function(payload, src)
    if not payload.businessId or not payload.coords then
        return { ok = false, error = 'missing_parameters' }
    end

    local businessId, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end
    -- the blip goes where the boss stands (the UI sends the player's position)
    local bx, by, bz = finiteNumber(payload.coords.x), finiteNumber(payload.coords.y), finiteNumber(payload.coords.z)
    if not (bx and by and bz) or #(GetEntityCoords(GetPlayerPed(src)) - vector3(bx, by, bz)) > 10.0 then
        return { ok = false, error = 'invalid_coords' }
    end
    payload.coords = { x = bx, y = by, z = bz }
    payload.name = cleanText(payload.name, 50, nil)
    payload.icon = tonumber(payload.icon) and math.floor(tonumber(payload.icon)) or nil
    payload.color = tonumber(payload.color) and math.floor(tonumber(payload.color)) or nil

    local data = loadData()
    data.businessBlips = data.businessBlips or {}
    
    -- Determine blip icon based on business type
    local blipIcon = payload.icon or 1
    if jobConfig.businessType == 'restaurant' then
        blipIcon = 889  -- Restaurant/food icon
    elseif jobConfig.businessType == 'mechanic' then
        blipIcon = 446  -- Wrench icon
    end
    
    data.businessBlips[businessId] = {
        businessId = businessId,
        businessType = jobConfig.businessType,
        name = payload.name or jobConfig.businessName,
        coords = {
            x = payload.coords.x,
            y = payload.coords.y,
            z = payload.coords.z
        },
        sprite = blipIcon,
        color = payload.color or jobConfig.blipColor,
        scale = 0.6,
        shortRange = true
    }
    
    persistBusiness(businessId)
    
    -- Notify all clients to update their blips
    TriggerClientEvent('pf-computer:client:updateBusinessBlip', -1, data.businessBlips[businessId])
    
    return { ok = true, data = data.businessBlips[businessId] }
end

-- Update menu item
handlers['business:menu:editItem'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local itemId = payload.itemId
    local item = payload.item

    if not itemId or not item then
        return { ok = false, error = 'missing_item_data' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database update
        local success, updateResult = pcall(function()
            return exports[provider]:UpdateMenuItem(businessId, itemId, item)
        end)
        
        if success and updateResult then
            print(string.format('[pf-computer] Menu item %s updated successfully via %s', itemId, provider))
            return { ok = true, data = {
                id = itemId,
                item_id = itemId,
                name = item.name,
                label = item.name,
                price = tonumber(item.price) or 0,
                category = item.category or 'General'
            }}
        else
            local errorMsg = success and tostring(updateResult) or tostring(success)
            print(string.format('[ERROR] Failed to update menu item via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_update_item', message = errorMsg }
        end
    end

    -- Fallback to internal data storage
    local data = loadData()
    data.businessMenus = data.businessMenus or {}
    
    local menu = data.businessMenus[businessId] or {}
    for i, menuItem in ipairs(menu) do
        if menuItem.id == tonumber(itemId) then
            if type(item) ~= 'table' or (item.price ~= nil and not priceOf(item.price, nil)) then return { ok = false, error = 'invalid_price' } end
            menuItem.name = cleanText(item.name, 60, menuItem.name)
            menuItem.description = cleanText(item.description, 300, menuItem.description)
            menuItem.price = priceOf(item.price, menuItem.price)
            menuItem.category = cleanText(item.category, 40, menuItem.category)
            if item.available ~= nil then menuItem.available = item.available == true end
            persistBusiness(businessId)
            return { ok = true, data = menuItem }
        end
    end

    return { ok = false, error = 'item_not_found' }
end

-- Get menu categories
handlers['business:menu:categories:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try external data provider first (for mechanic jobs)
    local externalCategories, hasExternal = GetExternalOrInternal(businessId, 'menuCategories')
    if hasExternal and externalCategories then
        return { ok = true, data = externalCategories }
    end

    -- Fallback to internal data - build list from menu items
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    local categories = {}
    local seen = {}
    
    for _, item in ipairs(menu) do
        local cat = item.category or 'General'
        if not seen[cat] then
            table.insert(categories, cat)
            seen[cat] = true
        end
    end
    
    -- Ensure General is always present
    if not seen['General'] then
        table.insert(categories, 'General')
    end
    
    table.sort(categories)
    return { ok = true, data = categories }
end

-- Add menu category
handlers['business:menu:categories:add'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local categoryName = payload.category or 'New Category'

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- For mechanic jobs, just return success
        -- The category will be created when the first item with that category is added
        return { ok = true, data = { category = categoryName } }
    end

    -- For internal data, just return success
    -- Categories are dynamically created from items
    return { ok = true, data = { category = categoryName } }
end

-- Delete menu category (removes all items in that category)
handlers['business:menu:categories:delete'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local categoryName = payload.category

    if not categoryName then
        return { ok = false, error = 'missing_category_name' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database delete
        local success, deleteResult = pcall(function()
            return exports[provider]:DeleteCategory(businessId, categoryName)
        end)
        
        if success and deleteResult then
            return { ok = true }
        else
            local errorMsg = success and tostring(deleteResult) or tostring(success)
            print(string.format('[ERROR] Failed to delete category via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_delete_category', message = errorMsg }
        end
    end

    -- Fallback to internal data
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    
    -- Remove all items in this category
    local newMenu = {}
    for _, item in ipairs(menu) do
        if item.category ~= categoryName then
            table.insert(newMenu, item)
        end
    end
    
    data.businessMenus[businessId] = newMenu
    persistBusiness(businessId)
    
    return { ok = true }
end

-- Rename menu category
handlers['business:menu:categories:rename'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local oldCategory = payload.oldCategory
    local newCategory = payload.newCategory

    if not oldCategory or not newCategory then
        return { ok = false, error = 'missing_parameters' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database update
        local success, updateResult = pcall(function()
            return exports[provider]:UpdateCategory(businessId, oldCategory, newCategory)
        end)
        
        if success and updateResult then
            return { ok = true }
        else
            local errorMsg = success and tostring(updateResult) or tostring(success)
            print(string.format('[ERROR] Failed to rename category via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_rename_category', message = errorMsg }
        end
    end

    -- Fallback to internal data
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    
    -- Rename category for all items
    for _, item in ipairs(menu) do
        if item.category == oldCategory then
            item.category = newCategory
        end
    end
    
    persistBusiness(businessId)
    return { ok = true }
end

-- Update ingredient quantity
-- Stock is what is physically in the business's stock stashes (deliveries add it, use takes it).
-- This used to store a number typed in the app in the data file, which nothing else used.
handlers['business:inventory:updateQuantity'] = function()
    return { ok = false, error = 'stock_is_physical' }
end

--- The business's real stock: the restaurant's dry/fridge/freezer stashes, or the job business's stock
--- stash, with each item's freshness where it has one.
handlers['business:stock:get'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then return errorResult end
    return { ok = true, data = { items = stockItems(businessId) } }
end

--- The business's approved premises and what it can buy for them (pf-government decides who may).
govBusinessIdFor = function(job)
    local restaurantId = restaurantFor(job)
    if restaurantId then return 'restaurant:' .. restaurantId end
    return 'mechanic:' .. job
end

handlers['business:premises:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then return errorResult end
    if GetResourceState('pf-government') ~= 'started' then return { ok = false, error = 'government_offline' } end
    local ok, res = pcall(function() return exports['pf-government']:ListPremisesFor(src, govBusinessIdFor(businessId)) end)
    return ok and type(res) == 'table' and res or { ok = false, error = 'government_unavailable' }
end

handlers['business:premises:buy'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then return errorResult end
    if GetResourceState('pf-government') ~= 'started' then return { ok = false, error = 'government_offline' } end
    local ok, res = pcall(function()
        return exports['pf-government']:BuyPremisesEquipment(src, tonumber(payload.slotId), tostring(payload.equipmentType or ''))
    end)
    return ok and type(res) == 'table' and res or { ok = false, error = 'government_unavailable' }
end

-- Actions that change a business need the business boss (several only needed the job before, so any
-- employee could spend the society account on supplies, change POS prices, move the public blip, ...).
local BOSS_ACTIONS = {
    -- (supply orders check the boss inside the handler: player-owned stores authorize by ownership)
    ['business:menu:add'] = true, ['business:menu:update'] = true, ['business:menu:editItem'] = true,
    ['business:menu:delete'] = true, ['business:menu:categories:add'] = true,
    ['business:menu:categories:delete'] = true, ['business:menu:categories:rename'] = true,
    ['business:meals:add'] = true, ['business:meals:update'] = true, ['business:meals:delete'] = true,
    ['business:update:settings'] = true, ['business:blips:save'] = true, ['business:stash:place'] = true,
    ['business:employees:update'] = true, ['business:employees:fire'] = true,
    ['business:inventory:updateQuantity'] = true, ['business:wages:set'] = true,
}

-- Actions that write the computer's tables: refused while the tables are still loading at start, or
-- when the database is down (they would be lost, or overwritten by the load).
local WRITE_ACTIONS = {
    ['business:menu:add'] = true, ['business:menu:update'] = true, ['business:menu:editItem'] = true,
    ['business:menu:delete'] = true, ['business:menu:categories:delete'] = true, ['business:menu:categories:rename'] = true,
    ['business:meals:add'] = true, ['business:meals:update'] = true, ['business:meals:delete'] = true,
    ['business:update:settings'] = true, ['business:blips:save'] = true, ['business:stash:place'] = true,
    ['business:wages:set'] = true, ['gov:wagecaps:set'] = true, ['business:supplies:orders:pickup'] = true,
    ['browser:domain:buy'] = true, ['browser:website:save'] = true, ['browser:domain:transfer'] = true,
    ['darkweb:chat:post'] = true,
}

-- What the Store and the business apps may offer this player, decided by the same checks the
-- business handlers make (the Store used to require the government or mayor job, so real business
-- bosses could not install the Business Manager).
handlers['business:access'] = function(_, src)
    local job, _, cfg = getAuthorizedBusiness(src, {})
    local P = GetPlayer(src)
    local isBoss = job ~= nil and P ~= nil and P.PlayerData.job ~= nil and P.PlayerData.job.isboss == true
    local _, stores = resolveStoreContext(src, {})
    return { ok = true, data = {
        business = job ~= nil, businessId = job, businessName = cfg and cfg.businessName or nil,
        isBoss = isBoss, stores = #(stores or {}) > 0,
    } }
end

-- City government actions and the pf-government permission each needs
local GOV_ACTIONS = {
    ['gov:cityhall:bootstrap'] = 'audit', ['gov:laws:setDisplay'] = 'laws',
    ['gov:taxes:update'] = 'taxes', ['gov:taxes:toggle'] = 'taxes',
    ['gov:budgets:update'] = 'budgets', ['gov:budgets:upgrade'] = 'budgets', ['gov:budgets:uninstallUpgrade'] = 'budgets',
    ['gov:utilities:disconnect'] = 'utilities', ['gov:utilities:restore'] = 'utilities',
    ['gov:fines:issue'] = 'fines', ['gov:announcements:create'] = 'laws',
    ['gov:wagecaps:set'] = 'budgets',
}

-- Calls are rate limited per player
local CALLBACK_BURST, CALLBACK_REFILL_PER_SEC = 20, 5
local callbackBudget = {}

local function takeCallbackToken(src)
    local now = GetGameTimer()
    local b = callbackBudget[src]
    if not b then b = { tokens = CALLBACK_BURST, at = now }; callbackBudget[src] = b end
    b.tokens = math.min(CALLBACK_BURST, b.tokens + (now - b.at) / 1000 * CALLBACK_REFILL_PER_SEC)
    b.at = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end
AddEventHandler('playerDropped', function() callbackBudget[source] = nil end)

local function isBusinessBoss(src)
    local Player = GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.isboss == true
end

--- Runs one action for `src` with every check the action needs (boss, government permission,
--- writable storage). The computer's own callback event and the pf-devices apps (server/devices.lua)
--- both come through here, so an app on the tablet is checked exactly like the computer window was.
local function dispatch(action, payload, src)
    if type(action) ~= 'string' or (payload ~= nil and type(payload) ~= 'table') then
        return { ok = false, error = 'bad_request' }
    end
    if not handlers[action] then return { ok = false, error = 'unknown_action' } end
    if BOSS_ACTIONS[action] and not isBusinessBoss(src) then return { ok = false, error = 'not_authorized' } end
    if GOV_ACTIONS[action] and not govCan(src, GOV_ACTIONS[action]) then return { ok = false, error = 'not_authorized' } end
    if WRITE_ACTIONS[action] and not storageWritable() then
        return { ok = false, error = DB.mode == 'starting' and 'storage_starting' or 'storage_unavailable' }
    end
    local ok, res = pcall(handlers[action], payload or {}, src)
    if not ok then
        print(('^1[pf-computer]^7 %s failed: %s'):format(action, tostring(res)))
        return { ok = false, error = 'server_error' }
    end
    return res
end

RegisterNetEvent('pf-computer:server:callback', function(id, action, payload)
    local src = source
    local result
    if type(action) ~= 'string' or (payload ~= nil and type(payload) ~= 'table') then
        result = { ok = false, error = 'bad_request' }
    elseif not takeCallbackToken(src) then
        result = { ok = false, error = 'rate_limited' }
    else
        result = dispatch(action, payload, src)
    end
    TriggerClientEvent('pf-computer:client:callback', src, id, result)
end)

-- shared with the other server files of this resource (server/jobboard.lua, server/devices.lua, ...)
PFComputer = {
    handlers = handlers, WRITE_ACTIONS = WRITE_ACTIONS, BOSS_ACTIONS = BOSS_ACTIONS, GOV_ACTIONS = GOV_ACTIONS,
    DB = DB, GetPlayer = GetPlayer, citizenId = GetPlayerIdentifier,
    playerName = getPlayerName, cleanText = cleanText, decodeJson = decodeJson, sendMail = sendCitizenMail,
    sendJobMail = sendJobMail, onStorageReady = onStorageReady, govCan = govCan, QBCore = QBCore,
    dispatch = dispatch, storageWritable = storageWritable, persist = persist, dataStore = dataStore,
    getAuthorizedBusiness = getAuthorizedBusiness, resolveSuppliesBusiness = resolveSuppliesBusiness,
    isBusinessBoss = isBusinessBoss, hasItem = GetPlayerHasItem, finiteNumber = finiteNumber,
    push = devicePush, nowIso = nowIso, chatHandle = chatHandle,
}

-- 'pf-computer:announcements:create' was a net event with no checks at all (anyone could post City
-- Hall announcements); nothing used it, so it is gone. Use the 'gov:announcements:create' action.

-- Set delivery location for supplies
RegisterNetEvent('pf-computer:server:setDeliveryLocation', function(location)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    -- a business boss sets their own business's delivery point, to real coordinates where they stand
    local authJob, _, _, authErr = getAuthorizedBusiness(src, {})
    if not authJob or not (Player.PlayerData.job and Player.PlayerData.job.isboss) then
        TriggerClientEvent('QBCore:Notify', src, 'Only the business boss can set the delivery point', 'error')
        return
    end
    if type(location) ~= 'table' and type(location) ~= 'vector3' and type(location) ~= 'vector4' then return end
    local lx, ly, lz = finiteNumber(location.x), finiteNumber(location.y), finiteNumber(location.z)
    if not (lx and ly and lz) then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - vector3(lx, ly, lz)) > 25.0 then
        TriggerClientEvent('QBCore:Notify', src, 'Stand at the delivery point to set it', 'error')
        return
    end
    location = { x = lx, y = ly, z = lz, w = finiteNumber(location.w) or 0.0 }
    if not storageWritable() then
        TriggerClientEvent('QBCore:Notify', src, 'The business records are not available right now', 'error')
        return
    end

    local job = authJob
    local data = loadData()
    
    -- Initialize business delivery locations if not exists
    if not data.businessDeliveryLocations then
        data.businessDeliveryLocations = {}
    end
    
    -- Save the delivery location for this business
    data.businessDeliveryLocations[job] = location
    
    persistBusiness(job)
    
    if Config.Debug then
        print(string.format('[pf-computer] Delivery location set for %s: %.2f, %.2f, %.2f', 
            job, location.x, location.y, location.z))
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'Delivery location updated!', 'success')
end)

local function GetJobGradeWage(job, grade)
    if not job then return nil end
    local data = loadData()
    local level = tostring(grade or '0')
    if data.businessWages[job] and data.businessWages[job][level] then
        return data.businessWages[job][level]
    end
    local jobData = QBCore.Shared.Jobs[job]
    if jobData and jobData.grades and jobData.grades[level] then
        return jobData.grades[level].payment
    end
    return nil
end

exports('GetJobGradeWage', GetJobGradeWage)

-- Startup: Log external data providers
CreateThread(function()
    Wait(2000) -- Wait for other resources to load
    
    print('[pf-computer] Business Manager Integration System Loaded')
    print('[pf-computer] Checking for external data providers...')
    
    local foundProviders = 0
    for job, resource in pairs(JobDataProviders) do
        if GetResourceState(resource) == 'started' then
            local hasExports = pcall(function()
                return exports[resource].GetBusinessConfig
            end)
            if hasExports then
                foundProviders = foundProviders + 1
                print(string.format('  ✓ %s → %s', job, resource))
            else
                print(string.format('  ✗ %s → %s (no exports)', job, resource))
            end
        else
            print(string.format('  ✗ %s → %s (not started)', job, resource))
        end
    end
    
    if foundProviders > 0 then
        print(string.format('[pf-computer] Found %d external data provider(s)', foundProviders))
    else
        print('[pf-computer] No external data providers found, using internal data only')
    end
end)

RegisterCommand('pc_setwagecap', function(source, args)
    local src = source
    if src == 0 then return end
    -- the same permission as the app's 'gov:wagecaps:set' (any job in Config.GovJobs, e.g. police, could)
    if not govCan(src, GOV_ACTIONS['gov:wagecaps:set']) then
        TriggerClientEvent('QBCore:Notify', src, 'Not authorized.', 'error')
        return
    end

    local grade = args[1]
    local amount = args[2]
    if not grade or not amount then
        TriggerClientEvent('QBCore:Notify', src, 'Usage: /pc_setwagecap <grade> <amount>', 'error')
        return
    end

    local numeric = tonumber(amount)
    if not numeric or numeric < 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Amount must be >= 0.', 'error')
        return
    end

    handlers['gov:wagecaps:set']({ caps = { [grade] = math.floor(numeric) } }, src)
    TriggerClientEvent('QBCore:Notify', src, ('Wage cap set: grade %s -> %s'):format(grade, math.floor(numeric)), 'success')
end, false)

-- ============================================================================
-- EXPORTS FOR OTHER RESOURCES
-- ============================================================================

-- Records a sale in the Business Manager's history and analytics.
-- Usage: exports['pf-computer']:DepositSale(businessName, amount, description)
-- It no longer adds money: the company account is the job's bank account, and the money of a sale
-- must be moved by the resource that took it from the customer (e.g. pf-mechanicjob's register pays
-- the society through the bank). Callers pass amounts their clients chose, so crediting here would
-- create money from nothing.
function DepositSale(businessName, amount, description)
    amount = tonumber(amount)
    if type(businessName) ~= 'string' or businessName == '' or #businessName > 50 or not amount or amount ~= amount or amount <= 0 or amount > 1000000000 then
        return { ok = false, error = 'invalid_parameters' }
    end

    logBusinessTx(businessName, {
        type = 'sale',
        amount = math.floor(amount * 100 + 0.5) / 100,
        description = tostring(description or 'POS Sale'):sub(1, 100),
        recordOnly = true,
    })

    return { ok = true, balance = businessBalance(businessName) }
end
exports('DepositSale', DepositSale)

-- One-time move of the old data-file balances into the bank. Only the player-funded part moves:
-- deposits minus withdrawals minus supply spending (the history is complete, it was never trimmed),
-- capped at the old balance. Sale entries are not moved: the register already paid the bank for those,
-- and the tablet sales were never paid by anyone. Config.BusinessManager.MigrateSalesBalance = true
-- moves the whole old balance instead. Safe to re-run: keyed per business, and each business is
-- marked done in pf_computer_meta. The balances are read from the old data file, which is not written.
function MigrateBusinessAccountsToBank()
    local old = decodeJson(LoadResourceFile(RESOURCE, LEGACY_FILE), {})
    local moved, skipped = 0, 0
    for job, account in pairs(type(old.businessAccounts) == 'table' and old.businessAccounts or {}) do
        local markKey = ('bankMigration:%s'):format(job):sub(1, 64)
        local balance = type(account) == 'table' and tonumber(account.balance) or 0
        if type(account) == 'table' and not account.bankMigration and not dataStore.meta[markKey] and balance > 0 then
            local funded = 0
            for _, tx in ipairs(account.transactions or {}) do
                local amount = tonumber(tx.amount) or 0
                if tx.type == 'deposit' then funded = funded + amount
                elseif tx.type == 'withdrawal' or tx.type == 'supplies' then funded = funded - amount end
            end
            local toMove = (Config.BusinessManager and Config.BusinessManager.MigrateSalesBalance) and balance or math.max(0, math.min(funded, balance))
            toMove = math.floor(toMove * 100 + 0.5) / 100
            local ok = true
            if toMove > 0 then
                ok = ensureBusinessBankAccount(job)
                if ok then
                    local res = bizTransfer({
                        from = 'system:pf-computer-migration', to = 'society:' .. job, amount = toMove,
                        key = ('pf-computer:account-to-bank:%s:%.2f'):format(job, toMove),
                        kind = 'migration', reason = 'Company account moved to bank',
                    })
                    ok = res.ok
                end
            end
            if ok then
                dataStore.meta[markKey] = { at = nowIso(), oldBalance = balance, moved = toMove, notMoved = math.floor((balance - toMove) * 100 + 0.5) / 100 }
                persist('meta', markKey)
                moved = moved + 1
            else
                skipped = skipped + 1
                print(('^1[pf-computer]^7 could not move the company balance of %s to the bank; will retry next start'):format(job))
            end
        end
    end
    if moved > 0 then print(('[pf-computer] moved %d company account balance(s) into the bank'):format(moved)) end
    return moved, skipped
end

-- after the tables are loaded (the done-markers live there), once the ledger is up
onStorageReady[#onStorageReady + 1] = function()
    CreateThread(function()
        local waited = 0
        while not bizBankReady() and waited < 120 do
            Wait(1000)
            waited = waited + 1
        end
        if bizBankReady() then
            MigrateBusinessAccountsToBank()
        else
            print('^1[pf-computer]^7 pfm-banking ledger not available: company accounts are read-only until it is')
        end
    end)
end
