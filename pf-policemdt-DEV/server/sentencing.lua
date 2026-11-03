-- ============================================================================
-- PF Police MDT - sentencing, the built-in jail and bail
-- ============================================================================
-- A sentence needs the citizen with the officer (server positions), jail time needs them in
-- handcuffs or at a booking desk, and the totals are capped (Config.Sentencing). The fine is one
-- keyed transfer on the bank ledger (key = the sentence row id), so a double click or a retry never
-- charges twice, and a result the bank could not confirm is checked again until it settles.
--
-- The built-in jail belongs to the server: pf_mdt_active_jails holds the time left and the
-- confiscated items. The time counts down here, only while the prisoner is online and inside the
-- prison; a prisoner found outside is taken back to a cell; a reconnect resumes the sentence; the
-- items come back once, when the server releases the prisoner (time served, bail or unjail).
--
-- Bail is offered by an officer and accepted by the payer (/bailaccept), who pays from their own bank.

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtSentencing = PFMdtSentencing or {}
local S = PFMdtSentencing
local RES = GetCurrentResourceName()
local SYSTEM_ACCOUNT = 'system:pf-policemdt'

S.dbReady = false
local lastTick = {}    -- citizenid -> os.time() of the last countdown (online prisoners)
local sentAt = {}      -- citizenid -> os.time() the prisoner was last sent to a cell
local escapeSeen = {}  -- jail id -> true once an escape was reported
local sentenceLock = {} -- citizenid -> true while a sentence for them is being processed
local officerLock = {}  -- officer source -> true while they are sentencing someone
local bailLock = {}     -- jail id -> true while a bail payment for it runs
local offers = {}       -- payer citizenid -> open bail offer
local printedAt = {}    -- officer source -> { [sentenceId] = os.time() }
local lastSentence = {} -- 'officer:citizenid' -> os.time() of the last carried-out sentence
local offerCounter = 0

local function cfg() return (Config and Config.Sentencing) or {} end
local function prisonCfg() return cfg().Prison or {} end
local function bailCfg() return cfg().Bail or {} end
local function tickSeconds() return math.max(5, tonumber(prisonCfg().TickSeconds) or 15) end
local function trim(s) return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1')) end
local function notify(src, msg, kind) if src then TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary') end end

local function getPlayer(src) return QBCore.Functions.GetPlayer(tonumber(src) or src) end
local function online(cid)
    if type(cid) ~= 'string' or cid == '' then return nil end
    local get = QBCore.Functions.GetPlayerByCitizenId
    if PFMdtAccess.Callable(get) then
        local ok, P = pcall(get, cid)
        if ok and type(P) == 'table' and P.PlayerData then return P end
        return nil
    end
    for _, P in pairs(QBCore.Functions.GetQBPlayers() or {}) do
        if P and P.PlayerData and P.PlayerData.citizenid == cid then return P end
    end
    return nil
end
local function fullName(P)
    local ci = P and P.PlayerData and P.PlayerData.charinfo or {}
    local n = trim((ci.firstname or '') .. ' ' .. (ci.lastname or ''))
    return n ~= '' and n or (P and P.PlayerData and P.PlayerData.citizenid) or 'Unknown'
end

local function prisonScript()
    local script = tostring(cfg().PrisonScript or (Config and Config.Prison) or 'default'):lower()
    if script == 'rcore_prison' then script = 'rcore' end
    return script == 'rcore' and 'rcore' or 'default'
end

local function db(kind, sql, params)
    local ok, res = pcall(MySQL[kind].await, sql, params or {})
    if not ok then
        print(('^1[pf-policemdt]^7 database error: %s'):format(tostring(res)))
        return nil, false
    end
    return res, true
end

local function affected(n)
    if type(n) == 'table' then n = n.affectedRows or n.changedRows end
    return tonumber(n) or 0
end

-- ── database ────────────────────────────────────────────────────────────────

S.Migrations = {
    {
        version = 1,
        name = 'server-owned MDT jail',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_active_jails` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `sentence_id` INT NULL,
                `remaining_seconds` INT NOT NULL,
                `total_seconds` INT NOT NULL,
                `bail_amount` INT NOT NULL DEFAULT 0,
                `bail_key` VARCHAR(128) NULL,
                `bail_payer_cid` VARCHAR(64) NULL,
                `bail_payer_name` VARCHAR(128) NULL,
                `bail_started_at` INT NULL,
                `reason` VARCHAR(255) NULL,
                `items` LONGTEXT NULL,
                `provider` VARCHAR(32) NULL,
                `officer_citizenid` VARCHAR(64) NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_mdt_jail_citizen` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- the sentence row is written before any money moves; its id is the fine's ledger key
        version = 2,
        name = 'sentence payment state',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_sentences` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenId` VARCHAR(64) NOT NULL,
                `citizenName` VARCHAR(128) NULL,
                `officerCitizenId` VARCHAR(64) NULL,
                `officerName` VARCHAR(128) NULL,
                `title` VARCHAR(255) NOT NULL,
                `description` LONGTEXT NULL,
                `sentenceType` VARCHAR(24) NOT NULL,
                `charges` LONGTEXT NULL,
                `reductions` LONGTEXT NULL,
                `fineAmount` INT NOT NULL DEFAULT 0,
                `prisonTime` INT NOT NULL DEFAULT 0,
                `prisonTimeBeforeReduction` INT NOT NULL DEFAULT 0,
                `prisonTimeAfterReduction` INT NOT NULL DEFAULT 0,
                `reductionPercent` INT NOT NULL DEFAULT 0,
                `executed` TINYINT(1) NOT NULL DEFAULT 0,
                `fineSuccess` TINYINT(1) NOT NULL DEFAULT 0,
                `jailSuccess` TINYINT(1) NOT NULL DEFAULT 0,
                `error` TEXT NULL,
                `bailAmount` INT NOT NULL DEFAULT 0,
                `bailed` TINYINT(1) NOT NULL DEFAULT 0,
                `bailPaidByCitizenId` VARCHAR(64) NULL,
                `bailPaidByName` VARCHAR(128) NULL,
                `bailPaidAt` DATETIME NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_citizen` (`citizenId`),
                KEY `idx_createdAt` (`createdAt`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailAmount` INT NOT NULL DEFAULT 0',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailed` TINYINT(1) NOT NULL DEFAULT 0',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailPaidByCitizenId` VARCHAR(64) NULL',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailPaidByName` VARCHAR(128) NULL',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailPaidAt` DATETIME NULL',
            "ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `status` VARCHAR(24) NOT NULL DEFAULT 'done'",
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `fine_key` VARCHAR(128) NULL',
            'CREATE INDEX IF NOT EXISTS `idx_mdt_sentence_status` ON `pf_mdt_sentences` (`status`)',
        },
    },
    {
        version = 3,
        name = 'licence actions audit',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_license_actions` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `license_type` VARCHAR(32) NOT NULL,
                `action` VARCHAR(16) NOT NULL,
                `days` DECIMAL(10,2) NULL,
                `reason` VARCHAR(300) NULL,
                `by_citizenid` VARCHAR(64) NULL,
                `by_name` VARCHAR(128) NULL,
                `by_job` VARCHAR(32) NULL,
                `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_mdt_license_actions_cid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 4,
        name = 'charge changes audit',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_charge_audit` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `charge_id` INT NULL,
                `code` VARCHAR(16) NULL,
                `action` VARCHAR(16) NOT NULL,
                `before_json` LONGTEXT NULL,
                `after_json` LONGTEXT NULL,
                `by_citizenid` VARCHAR(64) NULL,
                `by_name` VARCHAR(128) NULL,
                `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_mdt_charge_audit_charge` (`charge_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- a roster reset copies every row here first (one batch per reset)
        version = 5,
        name = 'roster reset backups',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_roster_backup` (
                `backup_id` INT NOT NULL AUTO_INCREMENT,
                `batch` VARCHAR(40) NOT NULL,
                `roster_id` INT NULL,
                `callsign` VARCHAR(32) NOT NULL,
                `rank` VARCHAR(64) NOT NULL DEFAULT '',
                `officer_name` VARCHAR(128) NOT NULL DEFAULT '',
                `citizenid` VARCHAR(64) NULL,
                `unit_type` VARCHAR(64) NOT NULL DEFAULT '',
                `training_status` VARCHAR(16) NOT NULL DEFAULT 'NONE',
                `notes` TEXT NULL,
                `by_citizenid` VARCHAR(64) NULL,
                `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`backup_id`),
                KEY `idx_mdt_roster_backup_batch` (`batch`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- a prisoner released while offline (bail, unjail) keeps the row until they load in, so the
        -- items come back then; this marks it as released so no second bail can be taken for it
        version = 6,
        name = 'jail released while offline',
        up = {
            'ALTER TABLE `pf_mdt_active_jails` ADD COLUMN IF NOT EXISTS `released_why` VARCHAR(16) NULL',
        },
    },
}

S.SQL = {
    jailOf = 'SELECT * FROM pf_mdt_active_jails WHERE citizenid = ? LIMIT 1',
    allJails = 'SELECT * FROM pf_mdt_active_jails',
    insertJail = [[INSERT INTO pf_mdt_active_jails (citizenid, sentence_id, remaining_seconds, total_seconds, bail_amount, reason, items, provider, officer_citizenid)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    setItems = 'UPDATE pf_mdt_active_jails SET items = ? WHERE id = ?',
    countDown = 'UPDATE pf_mdt_active_jails SET remaining_seconds = GREATEST(remaining_seconds - ?, 0) WHERE id = ?',
    releaseOffline = 'UPDATE pf_mdt_active_jails SET remaining_seconds = 0, released_why = ? WHERE id = ? AND released_why IS NULL',
    deleteJail = 'DELETE FROM pf_mdt_active_jails WHERE id = ?',
    setBailKey = 'UPDATE pf_mdt_active_jails SET bail_key = ?, bail_payer_cid = ?, bail_payer_name = ?, bail_started_at = ? WHERE id = ? AND bail_key IS NULL',
    clearBailKey = 'UPDATE pf_mdt_active_jails SET bail_key = NULL, bail_payer_cid = NULL, bail_payer_name = NULL, bail_started_at = NULL WHERE id = ? AND bail_key = ?',
    insertSentence = [[INSERT INTO pf_mdt_sentences
        (citizenId, citizenName, officerCitizenId, officerName, title, description, sentenceType, charges, reductions,
         fineAmount, prisonTime, prisonTimeBeforeReduction, prisonTimeAfterReduction, reductionPercent,
         executed, fineSuccess, jailSuccess, error, bailAmount, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, NULL, ?, 'pending')]],
    finishSentence = 'UPDATE pf_mdt_sentences SET status = ?, executed = ?, fineSuccess = ?, jailSuccess = ?, error = ?, fine_key = ? WHERE id = ?',
    pendingFines = "SELECT * FROM pf_mdt_sentences WHERE status = 'payment_pending' ORDER BY id ASC LIMIT 50",
    pendingFineOf = "SELECT id FROM pf_mdt_sentences WHERE citizenId = ? AND (status = 'payment_pending' OR (status = 'pending' AND fineAmount > 0)) LIMIT 1",
    stalePending = "SELECT * FROM pf_mdt_sentences WHERE status = 'pending' AND createdAt < NOW() - INTERVAL 10 MINUTE ORDER BY id ASC LIMIT 20",
    jailOfSentence = 'SELECT id FROM pf_mdt_active_jails WHERE sentence_id = ? LIMIT 1',
    recoverSentence = "UPDATE pf_mdt_sentences SET status = ?, executed = 1, fineSuccess = ?, jailSuccess = ?, error = ?, fine_key = ? WHERE id = ? AND status = 'pending'",
    settleFine = "UPDATE pf_mdt_sentences SET status = ?, fineSuccess = ?, error = ? WHERE id = ? AND status = 'payment_pending'",
    setJailResult = 'UPDATE pf_mdt_sentences SET executed = 1, jailSuccess = ?, error = ? WHERE id = ?',
    markBailed = 'UPDATE pf_mdt_sentences SET bailed = 1, bailPaidByCitizenId = ?, bailPaidByName = ?, bailPaidAt = NOW() WHERE id = ?',
    sentenceBailed = 'SELECT bailed FROM pf_mdt_sentences WHERE id = ? LIMIT 1',
}

function S.Start()
    if cfg().AllowNegativeBank then
        -- the old branch took fines with SetMoney, outside the ledger; it is gone
        print('^3[pf-policemdt]^7 Config.Sentencing.AllowNegativeBank is ignored: fines are ledger transfers and never take a balance below zero')
    end
    local ok, res = pcall(function() return exports['pfm-core']:RunMigrations(RES, S.Migrations) end)
    S.dbReady = ok and res == true
    if not S.dbReady then
        print(('^1[pf-policemdt]^7 database migrations failed (%s): sentencing and the jail are off'):format(tostring(res)))
    end
    return S.dbReady
end

function S.JailOf(cid)
    if not S.dbReady then return nil end
    local row = db('single', S.SQL.jailOf, { cid })
    return type(row) == 'table' and row.id and row or nil
end

-- ── ledger ──────────────────────────────────────────────────────────────────

local function ledgerStarted() return GetResourceState('pfm-banking') == 'started' end

local function transfer(opts)
    if not ledgerStarted() then return { ok = false, error = 'bank_unavailable' } end
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then
        -- the call broke off: the bank may have moved the money before it did
        return { ok = false, error = 'bank_unavailable', unclear = true }
    end
    return res
end

-- Errors the ledger returns before it writes anything (no transaction row): nothing moved.
local REFUSED_BEFORE_WRITE = {
    insufficient_funds = true, invalid_request = true, invalid_account = true, same_account = true,
    invalid_amount = true, invalid_key = true, ledger_unavailable = true, bank_unavailable = true,
}

--- 'paid', 'failed' (nothing was taken, a new attempt needs a new key) or 'unclear' (the bank may
--- have taken it: never charge again, check the key later).
function S.Outcome(res)
    if type(res) ~= 'table' then return 'unclear' end
    if res.ok then return 'paid' end
    if res.unclear then return 'unclear' end
    if res.state == 'compensated' then return 'failed' end
    if res.state == 'failed' then return res.error == 'interrupted_unverified' and 'unclear' or 'failed' end
    if res.state == nil and res.txId == nil and REFUSED_BEFORE_WRITE[res.error] then return 'failed' end
    return 'unclear'
end

--- What the ledger holds under a key now: 'paid', 'failed', 'none' (nothing was written) or 'unclear'.
function S.KeyOutcome(key)
    if not ledgerStarted() then return 'unclear' end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
    if not ok then return 'unclear' end
    if tx == nil then return 'none' end
    if type(tx) ~= 'table' then return 'unclear' end
    if tx.state == 'completed' then return 'paid' end
    if tx.state == 'compensated' or (tx.state == 'failed' and tx.error ~= 'interrupted_unverified') then return 'failed' end
    return 'unclear'
end

local function finesAccount()
    if cfg().FinesToSociety == false then return SYSTEM_ACCOUNT end
    local job = trim(cfg().FinesSocietyJob or 'police')
    return 'society:' .. (job ~= '' and job or 'police')
end

local FAIL_TEXT = {
    insufficient_funds = 'Insufficient bank funds',
    bank_unavailable = 'Bank unavailable: nothing was charged',
    ledger_unavailable = 'Bank unavailable: nothing was charged',
}

-- ── inventory (built-in jail) ───────────────────────────────────────────────
-- The confiscated items are read from the server's inventory only (a client used to send the list).

local function inventoryProvider()
    for _, pair in ipairs({ { 'ox_inventory', 'ox_inventory' }, { 'pfm-inventory', 'qb-inventory' }, { 'lj-inventory', 'lj-inventory' },
        { 'ps-inventory', 'ps-inventory' }, { 'qs-inventory', 'qs-inventory' } }) do
        if GetResourceState(pair[1]) == 'started' then return pair[2] end
    end
    return 'qbcore'
end

local function readItems(src, provider)
    local items = {}
    if provider == 'ox_inventory' then
        local ok, list = pcall(function()
            if exports.ox_inventory.GetInventoryItems then return exports.ox_inventory:GetInventoryItems(src) end
            local inv = exports.ox_inventory:GetInventory(src)
            return inv and inv.items or {}
        end)
        for slot, it in pairs(ok and type(list) == 'table' and list or {}) do
            local count = tonumber(it.count or it.amount) or 0
            if it.name and count > 0 then
                items[#items + 1] = { name = it.name, amount = count, slot = tonumber(it.slot) or tonumber(slot), info = it.metadata }
            end
        end
        return items
    end
    local P = getPlayer(src)
    for slot, it in pairs(P and P.PlayerData and P.PlayerData.items or {}) do
        if type(it) == 'table' and it.name and (tonumber(it.amount) or 0) > 0 then
            items[#items + 1] = { name = it.name, amount = tonumber(it.amount), slot = tonumber(it.slot) or tonumber(slot), info = it.info }
        end
    end
    return items
end

local INVENTORY_EXPORT = { ['qb-inventory'] = 'pfm-inventory', ['lj-inventory'] = 'lj-inventory', ['ps-inventory'] = 'ps-inventory', ['qs-inventory'] = 'qs-inventory' }

local function clearItems(src, provider, items)
    if provider == 'ox_inventory' then
        local ok = pcall(function() exports.ox_inventory:ClearInventory(src) end)
        if not ok then
            for _, it in ipairs(items) do pcall(function() exports.ox_inventory:RemoveItem(src, it.name, it.amount, it.info, it.slot) end) end
        end
        return
    end
    local res = INVENTORY_EXPORT[provider]
    if res then pcall(function() exports[res]:ClearInventory(src) end) end
    -- the player came from pfm-core: its methods are function references (callable tables)
    local P = getPlayer(src)
    local fns = P and P.Functions
    if fns and PFMdtAccess.Callable(fns.ClearInventory) then pcall(fns.ClearInventory) end
    -- items a one-call clear leaves (some inventories keep the hotbar) are removed one by one
    if fns and PFMdtAccess.Callable(fns.RemoveItem) then
        for _, it in ipairs(items) do
            pcall(function()
                if fns.RemoveItem(it.name, it.amount, it.slot) == false then fns.RemoveItem(it.name, it.amount) end
            end)
        end
    end
end

local function giveItems(src, provider, items)
    clearItems(src, provider, readItems(src, provider)) -- prison items go; nothing is doubled
    local given = 0
    local P = getPlayer(src)
    local fns = P and P.Functions
    for _, it in ipairs(items or {}) do
        if type(it) == 'table' and it.name and (tonumber(it.amount) or 0) > 0 then
            pcall(function()
                local done = false
                if provider == 'ox_inventory' then
                    done = exports.ox_inventory:AddItem(src, it.name, it.amount, it.info, it.slot) ~= false
                    if not done then done = exports.ox_inventory:AddItem(src, it.name, it.amount, it.info) ~= false end
                elseif INVENTORY_EXPORT[provider] and exports[INVENTORY_EXPORT[provider]] then
                    local inv = exports[INVENTORY_EXPORT[provider]]
                    done = inv:AddItem(src, it.name, it.amount, it.slot, it.info, 'pf_mdt:jail_release') == true
                    if not done then done = inv:AddItem(src, it.name, it.amount, false, it.info, 'pf_mdt:jail_release') == true end
                end
                if not done and fns and PFMdtAccess.Callable(fns.AddItem) then
                    if fns.AddItem(it.name, it.amount, it.slot, it.info) == false then fns.AddItem(it.name, it.amount, nil, it.info) end
                end
            end)
            given = given + 1
        end
    end
    return given
end

-- ── the jail ────────────────────────────────────────────────────────────────

local function sendToCell(src, seconds, reason)
    TriggerClientEvent('pf_mdt:client:StartMdtSentence', src, { minutes = seconds / 60, seconds = seconds, reason = reason })
end

-- The server moves the prisoner's ped itself (OneSync) when the client did not go back after
-- being told to: a modified client cannot stay outside by ignoring the event.
local function forceToCell(src)
    local spawns = prisonCfg().Spawns
    if type(spawns) ~= 'table' or #spawns == 0 or not PFMdtAccess.Callable(SetEntityCoords) then return false end
    local pick = spawns[math.random(#spawns)]
    local ped = GetPlayerPed(src)
    if not pick or not ped or ped == 0 then return false end
    return pcall(SetEntityCoords, ped, pick.x + 0.0, pick.y + 0.0, pick.z + 0.0, false, false, false, false)
end

--- Jails an online player: the row (time and items) is written first, the inventory is cleared only
--- after that write succeeded. opts = { seconds, reason, sentenceId, bail, officerCid }.
function S.Jail(src, opts)
    src = tonumber(src)
    local P = src and getPlayer(src)
    if not P then return false, 'Citizen is not online' end
    if not S.dbReady then return false, 'Database unavailable' end
    local cid = P.PlayerData.citizenid
    local seconds = math.floor(tonumber(opts.seconds) or 0)
    if seconds <= 0 then return false, 'invalid_minutes' end
    if S.JailOf(cid) then return false, 'Citizen is already serving a sentence' end

    local script = prisonScript()
    local provider = script == 'rcore' and 'rcore' or inventoryProvider()
    local items = script == 'rcore' and {} or readItems(src, provider)
    local reason = PFMdtAccess.Text(opts.reason or 'MDT Sentence', 255)
    local id = db('insert', S.SQL.insertJail, {
        cid, tonumber(opts.sentenceId), seconds, seconds, math.max(0, math.floor(tonumber(opts.bail) or 0)), reason,
        json.encode(items), provider, opts.officerCid,
    })
    if not tonumber(id) then return false, 'Database unavailable' end

    if script == 'rcore' then
        local ok, err = PFMdt.Prison.Jail(src, math.ceil(seconds / 60), reason, opts.officerSource)
        if not ok then
            db('update', S.SQL.deleteJail, { id })
            return false, err or 'Failed to jail'
        end
        return true, nil, id
    end

    -- The inventory may have changed during the insert wait. What is cleared must be what is
    -- stored: store the current list first, read again, and clear only once the two match (there is
    -- no wait between the last read and the clear).
    local stored, now = json.encode(items), readItems(src, provider)
    for _ = 1, 3 do
        if json.encode(now) == stored then break end
        local _, okSet = db('update', S.SQL.setItems, { json.encode(now), id })
        if not okSet then
            db('update', S.SQL.deleteJail, { id })
            return false, 'Database unavailable'
        end
        stored = json.encode(now)
        now = readItems(src, provider)
    end
    if json.encode(now) ~= stored then
        db('update', S.SQL.deleteJail, { id })
        return false, 'The inventory kept changing; try again'
    end
    clearItems(src, provider, now)
    notify(src, ('MDT: Items confiscated (%d)'):format(#now), 'error')

    local t = os.time()
    lastTick[cid], sentAt[cid] = t, t
    sendToCell(src, seconds, reason)
    return true, nil, id
end

--- Releases a prisoner once: the row is deleted, and only the call that deleted it gives the items
--- back. An offline prisoner's row is marked released (time zero, no bail open any more) and they
--- are released, with the items, when they next load in.
function S.Release(cid, why)
    local row = S.JailOf(cid)
    if not row then return false, 'not_jailed' end
    local P = online(cid)
    if not P then
        if row.released_why then return false, 'already_released' end
        local n = affected(db('update', S.SQL.releaseOffline, { tostring(why or 'served'):sub(1, 16), row.id }))
        if n ~= 1 then return false, 'already_released' end
        return true, 'on_login'
    end
    why = row.released_why or why
    local n = affected(db('update', S.SQL.deleteJail, { row.id }))
    if n ~= 1 then return false, 'already_released' end
    local src = P.PlayerData.source
    lastTick[cid], sentAt[cid], escapeSeen[row.id] = nil, nil, nil

    if row.provider == 'rcore' then
        if why ~= 'served' then PFMdt.Prison.Unjail(src, false) end
        return true
    end
    local ok, items = pcall(json.decode, row.items or '[]')
    local given = giveItems(src, row.provider or inventoryProvider(), ok and type(items) == 'table' and items or {})
    TriggerClientEvent('pf_mdt:client:ReleaseMdtSentence', src)
    notify(src, ('MDT: You were released (%s). Items returned: %d'):format(why or 'served', given), 'success')
    return true
end

local function insidePrison(src)
    local c = PFMdtAccess.Coords(src)
    local center = prisonCfg().Center
    if not c or not center then return true end
    return #(c - vector3(center.x, center.y, center.z)) <= (tonumber(prisonCfg().Radius) or 200.0)
end

local function cityEvent(kind, data, opts)
    if GetResourceState('pf-services') ~= 'started' then return end
    pcall(function() exports['pf-services']:Emit(kind, data, opts) end)
end

local BAIL_HOLD_SECONDS = 600

-- One prisoner on one tick: count the time served, release, or bring an escapee back.
local function tickJail(row, now)
    local cid = row.citizenid
    local P = online(cid)
    if not P then lastTick[cid], sentAt[cid] = nil, nil return end
    local src = P.PlayerData.source
    if row.released_why then S.Release(cid, row.released_why) return end
    if row.bail_key then
        S.CheckBail(row)
        row = S.JailOf(cid)
        if not row then return end
    end

    -- Right after being sent to a cell the prisoner gets a short grace (the teleport, a spawn
    -- screen) before being sent again; time counts only while they really are inside.
    local inGrace = sentAt[cid] and now - sentAt[cid] < 20
    local inside = row.provider == 'rcore' or insidePrison(src)
    local last = lastTick[cid]
    lastTick[cid] = now
    local served = 0
    if last and inside then served = math.min(math.max(now - last, 0), 2 * tickSeconds()) end
    local remaining = (tonumber(row.remaining_seconds) or 0) - served
    if served > 0 then db('update', S.SQL.countDown, { served, row.id }) end

    if remaining <= 0 then
        -- a bail payment the bank has not confirmed yet holds the release for a while, so it is
        -- either applied or settled first
        if row.bail_key and now - (tonumber(row.bail_started_at) or now) < BAIL_HOLD_SECONDS then return end
        if row.bail_key then
            print(('^3[pf-policemdt]^7 prisoner %s served their time while bail %s was still unconfirmed; check that ledger key'):format(cid, row.bail_key))
        end
        S.Release(cid, 'served')
        return
    end
    if not inside and not inGrace then
        sentAt[cid] = now
        sendToCell(src, remaining, row.reason or 'MDT Sentence')
        -- outside again after an earlier send-back: the client did not go, so the server moves them
        if escapeSeen[row.id] then forceToCell(src) end
        notify(src, 'You were taken back to your cell', 'error')
        if not escapeSeen[row.id] then
            escapeSeen[row.id] = true
            local c = PFMdtAccess.Coords(src)
            print(('^3[pf-policemdt]^7 MDT prisoner %s was outside the prison and was sent back'):format(cid))
            -- off by default: the prisoner is already back in a cell, and a respawn at a hospital
            -- looks the same as a walk out (an automatic news story would be wrong)
            local meta = P.PlayerData.metadata or {}
            if prisonCfg().ReportEscapes == true and not meta.isdead and not meta.inlaststand then
                cityEvent('crime.prison.escape', { name = fullName(P), count = 1, location = 'Bolingbroke Penitentiary', place = 'Bolingbroke Penitentiary',
                    ref = 'mdtjail:' .. tostring(row.id), details = fullName(P) .. ' tried to leave Bolingbroke Penitentiary' },
                    { title = fullName(P) .. ' tried to escape Bolingbroke Penitentiary', coords = c, actor = cid, dedupe = 'mdtjail:' .. tostring(row.id) })
            end
        end
    end
end

function S.Tick()
    if not S.dbReady then return end
    local now = os.time()
    for _, row in ipairs(db('query', S.SQL.allJails) or {}) do
        local ok, err = pcall(tickJail, row, now)
        if not ok then print(('^1[pf-policemdt]^7 jail tick %s: %s'):format(tostring(row.citizenid), tostring(err))) end
    end
    S.CheckPendingFines()
    for cid, offer in pairs(offers) do
        if offer.expires < now then offers[cid] = nil end
    end
end

--- A player who loads in with a sentence on record goes back to a cell (or is released when it is over).
function S.Resume(src)
    src = tonumber(src)
    local P = src and getPlayer(src)
    if not P or not S.dbReady then return end
    local cid = P.PlayerData.citizenid
    local row = S.JailOf(cid)
    if not row then return end
    if row.released_why or ((tonumber(row.remaining_seconds) or 0) <= 0 and not row.bail_key) then
        S.Release(cid, row.released_why or 'served')
        return
    end
    if row.provider ~= 'rcore' then
        -- an inventory saved before the confiscation (a crash) must not be used in jail
        local provider = row.provider or inventoryProvider()
        clearItems(src, provider, readItems(src, provider))
        local t = os.time()
        lastTick[cid], sentAt[cid] = t, t
        sendToCell(src, math.max(1, tonumber(row.remaining_seconds) or 1), row.reason or 'MDT Sentence')
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source or player
    if tonumber(src) then CreateThread(function() Wait(2000) S.Resume(tonumber(src)) end) end
end)
-- the ESX compatibility layer (PFMdt.GetCore) raises this one instead
AddEventHandler('esx:playerLoaded', function(playerId)
    if tonumber(playerId) then CreateThread(function() Wait(2000) S.Resume(tonumber(playerId)) end) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for cid, offer in pairs(offers) do
        if offer.payerSrc == src or offer.officerSrc == src then offers[cid] = nil end
    end
    printedAt[src], officerLock[src] = nil, nil
end)

-- The jailed client says its timer ran out. Before the server's own count says so (30 s grace),
-- it is ignored: the release, and the items, come from the server.
RegisterNetEvent('pf_mdt:server:mdtSentenceReleased', function()
    local src = source
    local P = getPlayer(src)
    if not P then return end
    local cid = P.PlayerData.citizenid
    local row = S.JailOf(cid)
    if not row or row.bail_key then return end
    local now = os.time()
    local left = (tonumber(row.remaining_seconds) or 0) - (lastTick[cid] and now - lastTick[cid] or 0)
    if left > 30 then return end
    S.Release(cid, 'served')
end)

-- ── fines ───────────────────────────────────────────────────────────────────

local function chargeFine(sentenceId, cid, amount, title, officerCid)
    local key = ('pf-policemdt:fine:%d'):format(sentenceId)
    local res = transfer({
        from = ('player:%s:bank'):format(cid), to = finesAccount(), amount = amount, key = key,
        kind = 'fine', reason = ('MDT fine: %s'):format(title):sub(1, 120), actor = officerCid,
        metadata = { sentenceId = sentenceId },
    })
    return S.Outcome(res), key, res
end

-- Jail part of a sentence whose fine the bank confirmed later.
local function jailAfterLatePayment(row)
    local minutes = tonumber(row.prisonTime) or 0
    if minutes <= 0 then
        db('update', S.SQL.setJailResult, { 1, nil, row.id })
        return
    end
    local P = online(row.citizenId)
    if not P then
        db('update', S.SQL.setJailResult, { 0, 'Fine paid; the citizen left before the bank confirmed it, so the jail time was not applied', row.id })
        return
    end
    local ok, err = S.Jail(P.PlayerData.source, { seconds = minutes * 60, reason = row.title, sentenceId = row.id, bail = row.bailAmount, officerCid = row.officerCitizenId })
    db('update', S.SQL.setJailResult, { ok and 1 or 0, (not ok) and ('Fine paid; jail failed: ' .. tostring(err)) or nil, row.id })
end

--- A sentence still 'pending' long after it started was cut off (a crash or restart between the
--- row and its result). Its fine key is known, so the ledger says whether it was paid; the jail
--- time is not added afterwards (the officer is not there to check custody) unless it was applied.
function S.RecoverStaleSentences()
    for _, row in ipairs(db('query', S.SQL.stalePending) or {}) do
        if not sentenceLock[row.citizenId] then
            local fine = tonumber(row.fineAmount) or 0
            local key = fine > 0 and ('pf-policemdt:fine:%d'):format(row.id) or nil
            local outcome = key and S.KeyOutcome(key) or 'none'
            local jailed = (tonumber(row.prisonTime) or 0) <= 0 or type(db('single', S.SQL.jailOfSentence, { row.id })) == 'table'
            if outcome == 'unclear' then
                db('update', S.SQL.recoverSentence, { 'payment_pending', 0, 0, 'The bank is still confirming the fine', key, row.id })
            elseif outcome == 'paid' then
                db('update', S.SQL.recoverSentence, { 'done', 1, jailed and 1 or 0,
                    (not jailed) and 'Fine paid; the sentence was cut off before the jail time, issue it alone' or nil, key, row.id })
            elseif fine > 0 or not jailed then
                db('update', S.SQL.recoverSentence, { 'failed', 0, 0, 'The sentence was cut off before it finished', key, row.id })
            else
                db('update', S.SQL.recoverSentence, { 'done', 0, 1, nil, nil, row.id })
            end
        end
    end
end

--- Fines the bank could not confirm at once: settled from the ledger's record under the same key.
function S.CheckPendingFines()
    S.RecoverStaleSentences()
    for _, row in ipairs(db('query', S.SQL.pendingFines) or {}) do
        local outcome = row.fine_key and S.KeyOutcome(row.fine_key) or 'none'
        if outcome == 'paid' then
            if affected(db('update', S.SQL.settleFine, { 'done', 1, nil, row.id })) == 1 then jailAfterLatePayment(row) end
        elseif outcome == 'failed' or outcome == 'none' then
            db('update', S.SQL.settleFine, { 'failed', 0, 'Payment was declined', row.id })
        end
    end
end

-- ── sentencing ──────────────────────────────────────────────────────────────

local function reductionPercent(key)
    for _, r in ipairs(cfg().Reductions or {}) do
        if r and r.key == key then return tonumber(r.percent) or 0 end
    end
    return 0
end

local function normalizeType(t)
    t = string.lower(tostring(t or ''))
    if t == 'fine' then return 'fine' end
    if t == 'fine+sentence' or t == 'fine_sentence' or t == 'fineandsentence' or t == 'both' then return 'fine+sentence' end
    return 'sentence'
end

local function loadCharges(codes)
    local marks = string.rep('?,', #codes):sub(1, -2)
    local ok, rows = pcall(MySQL.query.await, ('SELECT code, name, fineAmount, bailAmount, prisonTime FROM pf_mdt_charges WHERE code IN (%s)'):format(marks), codes)
    if ok and type(rows) == 'table' then return rows end
    -- installs with the old column names
    ok, rows = pcall(MySQL.query.await, ('SELECT code, name, fine_amount AS fineAmount, bail_amount AS bailAmount, jail_time AS prisonTime FROM pf_mdt_charges WHERE code IN (%s)'):format(marks), codes)
    if ok and type(rows) == 'table' then return rows end
    return nil
end

local function cap(v, max)
    v = math.max(0, math.floor(tonumber(v) or 0))
    max = tonumber(max)
    if max and v > max then return max, true end
    return v, false
end

-- Index of the first zone the player stands in, or nil.
local function zoneOf(src, zones)
    local c = PFMdtAccess.Coords(src)
    if not c then return nil end
    for i, z in ipairs(zones or {}) do
        if z.coords and #(c - vector3(z.coords.x, z.coords.y, z.coords.z)) <= (tonumber(z.radius) or 0) then return i end
    end
    return nil
end
local function inZone(src, zones) return zoneOf(src, zones) ~= nil end

-- In custody: handcuffed, or inside a booking area (station, sheriff office, prison).
function S.InCustody(P)
    local meta = P and P.PlayerData and P.PlayerData.metadata or {}
    if meta.ishandcuffed == true then return true end
    return inZone(P.PlayerData.source, cfg().BookingZones)
end

--- The citizen must be online, not the officer, and with the officer: within MaxDistance, or
--- handcuffed and inside the same booking area as the officer (an officer at a station computer
--- books a cuffed suspect in the cells; a free visitor in the lobby is not "with" them).
function S.CheckPresence(src, cid)
    local Officer = getPlayer(src)
    if not Officer then return nil, 'Player not found' end
    if cid == Officer.PlayerData.citizenid then return nil, 'You cannot sentence yourself' end
    local Target = online(cid)
    if not Target then return nil, 'The citizen must be online and with you' end
    local tsrc = Target.PlayerData.source
    if PFMdtAccess.Distance(src, tsrc) > (tonumber(cfg().MaxDistance) or 5.0) then
        local cuffed = (Target.PlayerData.metadata or {}).ishandcuffed == true
        local zone = cuffed and zoneOf(src, cfg().BookingZones) or nil
        if not zone or zone ~= zoneOf(tsrc, cfg().BookingZones) then return nil, 'The suspect must be with you' end
    end
    return Target, nil, Officer
end

local function computeSentence(data, rows)
    local fine, bail, minutes, saved = 0, 0, 0, {}
    for _, row in ipairs(rows) do
        -- a charge stored above the per-charge limits (before they existed) counts at the limit
        local f = cap(row.fineAmount, cfg().MaxChargeFine)
        local b = cap(row.bailAmount, cfg().MaxChargeBail)
        local t = cap(row.prisonTime, cfg().MaxChargeMinutes)
        fine, bail, minutes = fine + f, bail + b, minutes + t
        saved[#saved + 1] = { code = row.code, name = row.name, fineAmount = f, bailAmount = b, prisonTime = t }
    end
    local pct, reductions, seen = 0, {}, {}
    for _, k in ipairs(type(data.reductions) == 'table' and data.reductions or {}) do
        local key = PFMdtAccess.Text(k, 32)
        if key ~= '' and not seen[key] then
            seen[key] = true
            local p = reductionPercent(key)
            if p > 0 then pct = pct + p; reductions[#reductions + 1] = { key = key, percent = p } end
        end
    end
    if pct > 100 then pct = 100 end
    local after = math.max(0, math.floor(minutes * (1.0 - pct / 100.0)))
    local kind = normalizeType(data.sentenceType)
    local out = { kind = kind, charges = saved, reductions = reductions, pct = pct, before = minutes, after = after, fine = 0, minutes = 0, bail = 0 }
    if kind ~= 'sentence' then out.fine = fine end
    if kind ~= 'fine' then out.minutes, out.bail = after, bail end
    local c1, c2
    out.fine, c1 = cap(out.fine, cfg().MaxFine)
    out.minutes, c2 = cap(out.minutes, cfg().MaxMinutes)
    out.capped = c1 or c2
    return out
end

local function shared() return PFMdtShared or {} end

local function announce(sentenceId, Target, citizenName, officerCid, s)
    local sh = shared()
    if not (sh.CityEvent and sh.PublicText and sh.PublicCharges) then return end
    local name = sh.PublicText(fullName(Target), 60) or sh.PublicText(citizenName, 60) or 'A defendant'
    local summary = s.minutes > 0 and ('%s sentenced to %d months'):format(name, s.minutes) or ('%s fined $%d'):format(name, s.fine)
    sh.CityEvent('police.sentenced', {
        name = name, months = s.minutes, fine = s.fine, sentenceType = s.kind,
        charges = sh.PublicCharges(s.charges), place = s.minutes > 0 and 'Bolingbroke Penitentiary' or nil, by = 'mdt',
    }, { title = summary, actor = officerCid, dedupe = 'sentence:' .. tostring(sentenceId) })
end

local function sentenceBody(src, data, cid)
    local title = PFMdtAccess.Text(data.title, 255)
    if trim(title) == '' then return { success = false, error = 'Title is required' } end
    local description = PFMdtAccess.Text(data.description, 4000)
    local codes, seen = {}, {}
    for _, c in ipairs(type(data.charges) == 'table' and data.charges or {}) do
        local code = trim(PFMdtAccess.Text(c, 16))
        if code ~= '' and not seen[code] and #codes < 60 then seen[code] = true; codes[#codes + 1] = code end
    end
    if #codes == 0 then return { success = false, error = 'At least one charge must be selected' } end

    local rows = loadCharges(codes)
    if not rows then return { success = false, error = 'Database unavailable' } end
    if #rows == 0 then return { success = false, error = 'Unknown charges' } end
    local s = computeSentence(data, rows)
    if s.fine <= 0 and s.minutes <= 0 then return { success = false, error = 'These charges carry no fine or jail time' } end

    -- the database waits are over: the citizen must still be here, and in custody for jail time
    local Target, perr, Officer = S.CheckPresence(src, cid)
    if not Target then return { success = false, error = perr } end
    if s.minutes > 0 then
        if not S.InCustody(Target) then return { success = false, error = 'The suspect must be handcuffed or at a booking desk' } end
        if S.JailOf(cid) then return { success = false, error = 'Citizen is already serving a sentence' } end
    end
    if s.fine > 0 and not ledgerStarted() then return { success = false, error = 'Bank unavailable: nothing was charged' } end
    -- a fine the bank has not confirmed yet may still be taken: no new fine for this citizen until
    -- it settles (a second key would charge them twice)
    local pending = db('single', S.SQL.pendingFineOf, { cid })
    if type(pending) == 'table' and pending.id then
        return { success = false, error = 'A fine for this citizen is still being confirmed by the bank; wait for it to settle' }
    end

    local officerCid, officerName = Officer.PlayerData.citizenid, fullName(Officer)
    local citizenName = fullName(Target)
    local insertId = db('insert', S.SQL.insertSentence, {
        cid, citizenName, officerCid, officerName, title, description, s.kind, json.encode(s.charges), json.encode(s.reductions),
        s.fine, s.minutes, s.before, s.after, s.pct, s.bail,
    })
    local sentenceId = tonumber(insertId)
    if not sentenceId then return { success = false, error = 'Database unavailable' } end

    local fineKey, fineSuccess = nil, 0
    if s.fine > 0 then
        local outcome, key, res = chargeFine(sentenceId, cid, s.fine, title, officerCid)
        fineKey = key
        if outcome == 'failed' then
            local msg = FAIL_TEXT[res.error] or 'Payment was declined'
            db('update', S.SQL.finishSentence, { 'failed', 0, 0, 0, msg, key, sentenceId })
            notify(src, msg, 'error')
            return { success = false, error = msg, id = sentenceId }
        elseif outcome == 'unclear' then
            db('update', S.SQL.finishSentence, { 'payment_pending', 0, 0, 0, 'The bank is still confirming the fine', key, sentenceId })
            notify(src, 'The bank is still confirming the fine. The sentence finishes when it does; do not sentence again.', 'error')
            return { success = false, pending = true, error = 'The bank is still confirming the fine; the sentence finishes when it does', id = sentenceId }
        end
        fineSuccess = 1
    end

    local jailSuccess, err = 1, nil
    if s.minutes > 0 then
        -- the insert and the ledger waited: the suspect must still be with the officer and in custody
        local Now, nerr = S.CheckPresence(src, cid)
        local ok, jerr = false, nerr
        if Now and not S.InCustody(Now) then
            jerr = 'The suspect must be handcuffed or at a booking desk'
        elseif Now then
            ok, jerr = S.Jail(Now.PlayerData.source, {
                seconds = s.minutes * 60, reason = title, sentenceId = sentenceId, bail = s.bail, officerCid = officerCid, officerSource = src,
            })
        end
        if not ok then
            jailSuccess = 0
            err = fineSuccess == 1 and ('Fine paid; jail failed: ' .. tostring(jerr)) or tostring(jerr)
        end
    end
    -- a paid fine stays paid ('done'): a retry of the whole sentence would charge it again, so the
    -- officer is told to add the jail time alone
    local status = (err and fineSuccess ~= 1) and 'failed' or 'done'
    db('update', S.SQL.finishSentence, { status, 1, fineSuccess, jailSuccess, err, fineKey, sentenceId })
    if err then
        if fineSuccess == 1 then
            err = err .. '. The fine is paid: do not sentence it again, issue the jail time alone (type Sentence)'
        end
        return { success = false, error = err, id = sentenceId, finePaid = fineSuccess == 1 or nil }
    end

    announce(sentenceId, Target, citizenName, officerCid, s)
    return { success = true, id = sentenceId, fineAmount = s.fine, prisonTime = s.minutes, capped = s.capped or nil }
end

QBCore.Functions.CreateCallback('pf_mdt:createSentence', function(source, cb, data)
    local src = source
    if type(data) ~= 'table' then cb({ success = false, error = 'Invalid data' }) return end
    if not S.dbReady then cb({ success = false, error = 'Database unavailable' }) return end
    local cid = trim(PFMdtAccess.Text(data.citizenId, 64))
    if cid == '' then cb({ success = false, error = 'Invalid citizenId' }) return end
    local Target, perr = S.CheckPresence(src, cid)
    if not Target then cb({ success = false, error = perr }) return end

    -- one sentence per citizen and per officer at a time, taken before the first database wait; a
    -- second click right after a sentence went through is not a new sentence
    if sentenceLock[cid] or officerLock[src] then cb({ success = false, error = 'A sentence for this citizen is already being processed' }) return end
    local pair = tostring(src) .. ':' .. cid
    if lastSentence[pair] and os.time() - lastSentence[pair] < 5 then cb({ success = false, error = 'This citizen was just sentenced' }) return end
    sentenceLock[cid], officerLock[src] = true, true
    local ok, res = pcall(sentenceBody, src, data, cid)
    sentenceLock[cid], officerLock[src] = nil, nil
    if ok and type(res) == 'table' and (res.success or res.pending) then lastSentence[pair] = os.time() end
    if not ok then
        print(('^1[pf-policemdt]^7 createSentence: %s'):format(tostring(res)))
        res = { success = false, error = 'Sentencing failed' }
    end
    cb(res)
end)

QBCore.Functions.CreateCallback('pf_mdt:getCitizenSentences', function(source, cb, data)
    local cid = trim(PFMdtAccess.Text(type(data) == 'table' and data.citizenId or nil, 64))
    if cid == '' then cb({ success = false, sentences = {}, error = 'Invalid citizenId' }) return end
    if not S.dbReady then cb({ success = false, sentences = {}, error = 'Database unavailable' }) return end
    local rows = db('query', 'SELECT * FROM pf_mdt_sentences WHERE citizenId = ? ORDER BY id DESC LIMIT 200', { cid }) or {}
    local jail = S.JailOf(cid)
    local active = { active = false }
    if jail and jail.released_why then
        active = { active = false, releasedOnLogin = true }
    elseif jail then
        local rem = math.max(0, tonumber(jail.remaining_seconds) or 0)
        active = {
            active = true, endsAt = os.time() + rem, remainingMinutes = math.ceil(rem / 60),
            bailAmount = tonumber(jail.bail_amount) or 0, sentenceId = jail.sentence_id, bailPending = jail.bail_key ~= nil or nil,
        }
    end
    cb({ success = true, sentences = rows, activeJail = active })
end)

-- ── bail ────────────────────────────────────────────────────────────────────

local function payerPlaceOk(offer, payerSrc)
    if offer.payerCid == offer.prisonerCid then return true end
    if offer.officerSrc and getPlayer(offer.officerSrc) and PFMdtAccess.Distance(offer.officerSrc, payerSrc) <= (tonumber(bailCfg().PayerDistance) or 10.0) then return true end
    return inZone(payerSrc, bailCfg().Desks)
end

--- Whether bail can still be taken for a jail row: not released, time left, an amount, no payment
--- waiting on the bank, and the sentence not bailed already. Returns ok, error.
local function bailOpen(row)
    if not row or row.released_why then return false, 'The prisoner was already released' end
    if (tonumber(row.remaining_seconds) or 0) <= 0 then return false, 'The prisoner has served the sentence' end
    if (tonumber(row.bail_amount) or 0) <= 0 then return false, 'No bail amount for this sentence' end
    if row.bail_key then return false, 'A bail payment for this prisoner is still being confirmed by the bank' end
    if tonumber(row.sentence_id) then
        local s = db('single', S.SQL.sentenceBailed, { tonumber(row.sentence_id) })
        if type(s) == 'table' and tonumber(s.bailed) == 1 then return false, 'Bail for this sentence was already paid' end
    end
    return true
end

QBCore.Functions.CreateCallback('pf_mdt:postBail', function(source, cb, data)
    local src = source
    if type(data) ~= 'table' then cb({ success = false, error = 'Invalid data' }) return end
    if not S.dbReady then cb({ success = false, error = 'Database unavailable' }) return end
    local prisonerCid = trim(PFMdtAccess.Text(data.prisonerCitizenId, 64))
    local payerCid = trim(PFMdtAccess.Text(data.payerCitizenId, 64))
    if prisonerCid == '' then cb({ success = false, error = 'Invalid prisonerCitizenId' }) return end
    if payerCid == '' then cb({ success = false, error = 'Select a payer' }) return end
    if not PFMdtAccess.AllowRate(src, 'bailOffer', 3000) then cb({ success = false, error = 'Please wait a moment' }) return end

    local row = S.JailOf(prisonerCid)
    if not row then cb({ success = false, error = 'Citizen is not currently sentenced' }) return end
    local open, why = bailOpen(row)
    if not open then cb({ success = false, error = why }) return end
    local amount = tonumber(row.bail_amount) or 0
    local Payer = online(payerCid)
    if not Payer then cb({ success = false, error = 'Selected payer must be online' }) return end
    local Officer = getPlayer(src)

    offerCounter = offerCounter + 1
    local offer = {
        token = ('%d-%d'):format(os.time(), offerCounter), jailId = row.id, sentenceId = tonumber(row.sentence_id),
        prisonerCid = prisonerCid, prisonerName = (online(prisonerCid) and fullName(online(prisonerCid))) or prisonerCid,
        payerCid = payerCid, payerSrc = Payer.PlayerData.source, amount = amount,
        officerSrc = src, officerCid = Officer and Officer.PlayerData.citizenid, expires = os.time() + (tonumber(bailCfg().OfferSeconds) or 120),
    }
    if not payerPlaceOk(offer, offer.payerSrc) then cb({ success = false, error = 'The payer must be with you or at a bail desk' }) return end
    offers[payerCid] = offer
    notify(offer.payerSrc, ('Bail offer: $%d for %s. Type /bailaccept to pay it from your bank, or /baildecline.'):format(amount, offer.prisonerName), 'primary')
    TriggerClientEvent('pf_mdt:client:BailOffer', offer.payerSrc, { amount = amount, prisoner = offer.prisonerName, expiresIn = offer.expires - os.time() })
    notify(src, ('Bail offer sent to %s: they must type /bailaccept within %d seconds'):format(fullName(Payer), offer.expires - os.time()), 'success')
    cb({ success = true, pending = true, message = 'Bail offer sent: the payer must accept it' })
end)

local function bailPaid(row, payerCid, payerName, officerSrc)
    if row.sentence_id then db('update', S.SQL.markBailed, { payerCid, payerName, row.sentence_id }) end
    S.Release(row.citizenid, 'bail')
    if officerSrc then notify(officerSrc, 'Bail paid: the prisoner was released', 'success') end
end

--- The payer accepts their open offer. Returns ok, message.
function S.AcceptBail(src)
    local P = getPlayer(src)
    if not P then return false, 'Player not found' end
    local cid = P.PlayerData.citizenid
    local offer = offers[cid]
    if not offer or offer.expires < os.time() then offers[cid] = nil return false, 'You have no bail offer' end
    if not payerPlaceOk(offer, src) then return false, 'You must be with the officer or at a bail desk' end
    if bailLock[offer.jailId] then return false, 'This bail is already being paid' end
    bailLock[offer.jailId] = true
    offers[cid] = nil
    local ok, okRes, msg = pcall(function()
        -- read again under the lock: an earlier bail (this payer or another) may have released them
        local row = S.JailOf(offer.prisonerCid)
        if not row or row.id ~= offer.jailId then return false, 'The prisoner is no longer held' end
        local open, why = bailOpen(row)
        if not open then return false, why end
        if (tonumber(row.bail_amount) or 0) ~= offer.amount then return false, 'The bail amount changed; ask for a new offer' end
        local key = ('pf-policemdt:bail:%d:%s'):format(row.id, offer.token)
        local res = transfer({
            from = ('player:%s:bank'):format(cid), to = finesAccount(), amount = offer.amount, key = key, kind = 'bail',
            reason = ('Bail for %s'):format(offer.prisonerName):sub(1, 120), actor = cid, metadata = { jailId = row.id, sentenceId = row.sentence_id },
        })
        local outcome = S.Outcome(res)
        if outcome == 'paid' then
            bailPaid(row, cid, fullName(P), offer.officerSrc)
            return true, 'Bail paid'
        elseif outcome == 'failed' then
            if offer.officerSrc then notify(offer.officerSrc, 'The bail payment was declined', 'error') end
            return false, FAIL_TEXT[res.error] or 'The payment was declined'
        end
        db('update', S.SQL.setBailKey, { key, cid, fullName(P), os.time(), row.id })
        return false, 'The bank is still confirming the payment; the prisoner is released when it does'
    end)
    bailLock[offer.jailId] = nil
    if not ok then print(('^1[pf-policemdt]^7 bail: %s'):format(tostring(okRes))) return false, 'Bail failed' end
    return okRes, msg
end

--- A bail payment the bank could not confirm at once, settled from its ledger record.
function S.CheckBail(row)
    if not row.bail_key or bailLock[row.id] then return end
    local outcome = S.KeyOutcome(row.bail_key)
    if outcome == 'paid' then
        bailLock[row.id] = true
        local ok, err = pcall(bailPaid, row, row.bail_payer_cid, row.bail_payer_name, nil)
        bailLock[row.id] = nil
        if not ok then print(('^1[pf-policemdt]^7 bail release: %s'):format(tostring(err))) end
    elseif outcome == 'failed' or outcome == 'none' then
        db('update', S.SQL.clearBailKey, { row.id, row.bail_key })
    end
end

function S.DeclineBail(src)
    local P = getPlayer(src)
    if not P then return end
    local offer = offers[P.PlayerData.citizenid]
    offers[P.PlayerData.citizenid] = nil
    if offer and offer.officerSrc then notify(offer.officerSrc, 'The payer declined the bail offer', 'error') end
end

RegisterNetEvent('pf_mdt:server:acceptBail', function()
    local src = source
    if not PFMdtAccess.AllowRate(src, 'bailAccept', 2000) then return end
    local ok, msg = S.AcceptBail(src)
    notify(src, msg, ok and 'success' or 'error')
end)
RegisterNetEvent('pf_mdt:server:declineBail', function()
    S.DeclineBail(source)
end)

if QBCore.Commands and QBCore.Commands.Add then
    QBCore.Commands.Add('bailaccept', 'Pay the bail you were offered', {}, false, function(source)
        if not PFMdtAccess.AllowRate(source, 'bailAccept', 2000) then return end
        local ok, msg = S.AcceptBail(source)
        notify(source, msg, ok and 'success' or 'error')
    end)
    QBCore.Commands.Add('baildecline', 'Refuse the bail you were offered', {}, false, function(source)
        S.DeclineBail(source)
    end)
    QBCore.Commands.Add('unjail', 'Release a player from MDT jail (Admin)', { { name = 'id', help = 'Server ID' } }, false, function(source, args)
        local targetId = tonumber(args and args[1])
        local Target = targetId and getPlayer(targetId)
        if not Target then notify(source, 'Usage: /unjail <id> (player not found)', 'error') return end
        local ok, err = S.Release(Target.PlayerData.citizenid, 'admin')
        if not ok then
            -- not in the MDT jail: an rcore prisoner is released through rcore
            local uok, uerr = PFMdt.Prison.Unjail(targetId, false)
            if not uok then notify(source, ('Unjail failed: %s'):format(tostring(err or uerr)), 'error') return end
        end
        notify(source, ('Unjailed player %s'):format(targetId), 'success')
    end, 'admin')
end

-- ── citation printing ───────────────────────────────────────────────────────

local function printerCheck(src)
    local c = Config.Citations or {}
    local printer = c.PrinterCoords
    if printer then
        local pos = PFMdtAccess.Coords(src)
        local dist = pos and #(pos - vector3(printer.x or 0.0, printer.y or 0.0, printer.z or 0.0)) or math.huge
        if dist > (tonumber(c.PrinterDistance) or 3.0) then
            return false, ('You must be near the %s to print a citation.'):format(tostring(c.PrinterLabel or 'Station Printer'))
        end
        return true
    end
    if c.PrintFromMDT == false then return false, 'Citation printing from the MDT is disabled. Use the station printer.' end
    return true
end

QBCore.Functions.CreateCallback('pf_mdt:printCitationPaper', function(source, cb, data)
    local src = source
    local Officer = getPlayer(src)
    if not Officer then cb({ success = false, error = 'Player not found' }) return end
    local sentenceId = math.floor(tonumber(type(data) == 'table' and data.sentenceId or 0) or 0)
    if sentenceId <= 0 then cb({ success = false, error = 'Invalid sentence id' }) return end
    local okPlace, perr = printerCheck(src)
    if not okPlace then cb({ success = false, error = perr }) return end
    if not PFMdtAccess.AllowRate(src, 'printCitation', 5000) then cb({ success = false, error = 'Please wait a moment' }) return end
    printedAt[src] = printedAt[src] or {}
    local cooldown = tonumber((Config.Citations or {}).PrintCooldownSeconds) or 30
    local last = printedAt[src][sentenceId]
    if last and os.time() - last < cooldown then cb({ success = false, error = 'This citation was just printed' }) return end
    printedAt[src][sentenceId] = os.time()

    local row = db('single', 'SELECT id, citizenId, citizenName, officerName, title, description, fineAmount, fineSuccess, createdAt FROM pf_mdt_sentences WHERE id = ? LIMIT 1', { sentenceId })
    if type(row) ~= 'table' or not row.id then printedAt[src][sentenceId] = nil cb({ success = false, error = 'Sentence record not found' }) return end
    local fineAmount = tonumber(row.fineAmount) or 0
    if fineAmount <= 0 then cb({ success = false, error = 'This sentence has no payable citation to print' }) return end
    local citationUid = ('CT-%s-%06d-%04d'):format(os.date('%y%m%d'), sentenceId, math.random(1000, 9999))
    local info = {
        citationUid = citationUid, sentenceId = sentenceId, citizenId = tostring(row.citizenId or ''),
        citizenName = tostring(row.citizenName or 'Unknown Citizen'), officerName = tostring(row.officerName or 'Unknown Officer'),
        title = tostring(row.title or 'Citation'), description = tostring(row.description or ''), fineAmount = fineAmount,
        finePaid = tonumber(row.fineSuccess) == 1 or tostring(row.fineSuccess) == 'true',
        issuedAt = tostring(row.createdAt or os.date('%Y-%m-%d %H:%M:%S')),
    }
    local fns = Officer.Functions
    if not (fns and PFMdtAccess.Callable(fns.AddItem)) or not fns.AddItem('citation_paper', 1, false, info, 'pf_mdt:printCitationPaper') then
        printedAt[src][sentenceId] = nil
        cb({ success = false, error = 'Inventory full or citation item missing' })
        return
    end
    local item = QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items['citation_paper']
    if item then TriggerClientEvent('inventory:client:ItemBox', src, item, 'add') end
    cb({ success = true, citationUid = citationUid })
end)

-- ── rcore_prison (Config.Prison = 'rcore_prison') ───────────────────────────
-- Supervisor tools; the same presence, custody and caps as a sentence. A citizen who is not online
-- is no longer jailed "pending" from the MDT.

local function rcoreOnly(cb)
    if prisonScript() ~= 'rcore' then cb({ success = false, error = 'Prison system is not set to rcore' }) return false end
    return true
end

QBCore.Functions.CreateCallback('pf_mdt:prison:Jail', function(source, cb, data)
    if not rcoreOnly(cb) then return end
    if type(data) ~= 'table' then cb({ success = false, error = 'Invalid data' }) return end
    local cid = trim(PFMdtAccess.Text(data.citizenid or data.citizenId, 64))
    local minutes = cap(data.minutes, cfg().MaxMinutes)
    if cid == '' or minutes <= 0 then cb({ success = false, error = 'Invalid data' }) return end
    local Target, perr, Officer = S.CheckPresence(source, cid)
    if not Target then cb({ success = false, error = perr }) return end
    if not S.InCustody(Target) then cb({ success = false, error = 'The suspect must be handcuffed or at a booking desk' }) return end
    local ok, err = S.Jail(Target.PlayerData.source, { seconds = minutes * 60, reason = PFMdtAccess.Text(data.reason or 'MDT Sentence', 255),
        officerCid = Officer.PlayerData.citizenid, officerSource = source })
    if not ok then cb({ success = false, error = err or 'Failed to jail' }) return end
    cb({ success = true, applied = 'online' })
end)

QBCore.Functions.CreateCallback('pf_mdt:prison:Unjail', function(source, cb, data)
    if not rcoreOnly(cb) then return end
    local cid = trim(PFMdtAccess.Text(type(data) == 'table' and (data.citizenid or data.citizenId) or nil, 64))
    if cid == '' then cb({ success = false, error = 'Invalid citizenid' }) return end
    local Target = online(cid)
    if not Target then cb({ success = false, error = 'Citizen must be online' }) return end
    local okUnjail, err = PFMdt.Prison.Unjail(Target.PlayerData.source, type(data) == 'table' and data.skipTeleport == true)
    if not okUnjail then cb({ success = false, error = err or 'Failed to unjail' }) return end
    local row = S.JailOf(cid)
    if row then db('update', S.SQL.deleteJail, { row.id }) end
    db('update', 'DELETE FROM pf_mdt_pending_sentences WHERE citizenid = ?', { cid })
    cb({ success = true, applied = 'online' })
end)

QBCore.Functions.CreateCallback('pf_mdt:prison:EditSentence', function(source, cb, data)
    if not rcoreOnly(cb) then return end
    if type(data) ~= 'table' then cb({ success = false, error = 'Invalid data' }) return end
    local cid = trim(PFMdtAccess.Text(data.citizenid or data.citizenId, 64))
    local minutes = tonumber(data.minutes)
    if cid == '' or not minutes or minutes < 0 then cb({ success = false, error = 'Invalid data' }) return end
    minutes = cap(minutes, cfg().MaxMinutes)
    local Target = online(cid)
    if not Target then cb({ success = false, error = 'Citizen must be online to edit sentence' }) return end
    -- a longer sentence needs the prisoner in front of the supervisor; shortening one does not
    local row = S.JailOf(cid)
    local current = row and math.ceil((tonumber(row.remaining_seconds) or 0) / 60) or 0
    if minutes > current and PFMdtAccess.Distance(source, Target.PlayerData.source) > (tonumber(cfg().MaxDistance) or 5.0) then
        cb({ success = false, error = 'To lengthen a sentence the prisoner must be with you' })
        return
    end
    local ok, err = PFMdt.Prison.EditSentence(Target.PlayerData.source, minutes)
    if not ok then cb({ success = false, error = err or 'Failed to edit sentence' }) return end
    if row then db('update', 'UPDATE pf_mdt_active_jails SET remaining_seconds = ? WHERE id = ?', { minutes * 60, row.id }) end
    cb({ success = true })
end)

QBCore.Functions.CreateCallback('pf_mdt:prison:IsPrisoner', function(source, cb, data)
    if not rcoreOnly(cb) then return end
    local cid = trim(PFMdtAccess.Text(type(data) == 'table' and (data.citizenid or data.citizenId) or nil, 64))
    if cid == '' then cb({ success = false, error = 'Invalid citizenid' }) return end
    local Target = online(cid)
    if Target then
        cb({ success = true, isPrisoner = PFMdt.Prison.IsPrisoner(Target.PlayerData.source) == true })
        return
    end
    local rows = db('query', 'SELECT id FROM pf_mdt_pending_sentences WHERE citizenid = ? LIMIT 1', { cid }) or {}
    cb({ success = true, isPrisoner = rows[1] ~= nil })
end)

-- Sentences queued for offline citizens by older versions are applied when they load in (rcore).
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if prisonScript() ~= 'rcore' then return end
    local src = tonumber(type(player) == 'table' and player.PlayerData and player.PlayerData.source or player)
    local P = src and getPlayer(src)
    if not P or not S.dbReady then return end
    local cid = P.PlayerData.citizenid
    local rows = db('query', 'SELECT id, minutes, reason FROM pf_mdt_pending_sentences WHERE citizenid = ? ORDER BY id ASC', { cid }) or {}
    local row = rows[#rows]
    if not row then return end
    db('update', 'DELETE FROM pf_mdt_pending_sentences WHERE citizenid = ?', { cid })
    local minutes = cap(row.minutes, cfg().MaxMinutes)
    if minutes > 0 then S.Jail(src, { seconds = minutes * 60, reason = row.reason }) end
end)

-- ── start ───────────────────────────────────────────────────────────────────

CreateThread(function()
    Wait(1000)
    S.Start()
    while true do
        Wait(tickSeconds() * 1000)
        local ok, err = pcall(S.Tick)
        if not ok then print(('^1[pf-policemdt]^7 sentencing tick: %s'):format(tostring(err))) end
    end
end)
