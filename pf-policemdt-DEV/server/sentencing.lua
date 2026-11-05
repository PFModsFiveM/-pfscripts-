-- ============================================================================
-- PF Police MDT - sentencing, jail, bail
-- ============================================================================
-- A sentence needs the citizen with the officer (server positions), jail time needs them in
-- handcuffs or at a booking desk, and the totals are capped (Config.Sentencing). One sentence per
-- citizen and per officer runs at a time (the locks are taken before the first database wait), and
-- every sentence is written to pf_mdt_sentences (the legal record) before anything else happens.
--
-- Who runs the jail (batch 16) follows pf-justice's Config.Compat.LegacyRuntimes.mdt:
--   * handed over (false): the fine and the jail time are pf-justice orders (CreateOrder, keys
--     pf-policemdt:sentence:<id>:fine|jail); the fine is paid through PayOrder (a citizen who cannot
--     pay gets a phone invoice from pf-justice); pf-justice counts the time and pfm-prison holds the
--     cell; bail is pf-justice bail (postBail -> OfferBail, /bailaccept -> AcceptBail, /baildecline ->
--     DeclineBail). This file keeps the record, the relays, the client timer and the settling of
--     fines and bail that started before the hand-over. The built-in jail never runs.
--   * still the MDT's (true): the built-in jail below runs as before. pf_mdt_active_jails holds the
--     time and the confiscated items; the time counts here, only while the prisoner is online and
--     inside the prison; the items come back once, when the server releases the prisoner. The fine
--     is one keyed transfer on the bank ledger (key = the sentence row id), checked again until a
--     result the bank could not confirm settles. Bail is offered by an officer and accepted by the
--     payer (/bailaccept), who pays from their own bank.

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

-- ── who runs MDT jails ──────────────────────────────────────────────────────
-- pf-justice's config file holds the switch, so both resources follow one setting (it is read once,
-- in an empty table, and again when pf-justice restarts). Config.Sentencing.Justice.Runtime may
-- force 'justice' or 'legacy'; 'auto' follows pf-justice. Without a readable pf-justice config the
-- built-in jail keeps running (pf-justice's own default).

local justiceFile -- nil = not read yet; false = unreadable; table = { live, bailAccount }

local function justiceCfg() return cfg().Justice or {} end

--- What pf-justice's config.lua says (nil when it cannot be read).
function S.JusticeConfig()
    if justiceFile ~= nil then return justiceFile or nil end
    justiceFile = false
    if LoadResourceFile == nil or load == nil then return nil end
    local okRead, text = pcall(LoadResourceFile, 'pf-justice', 'config.lua')
    if not okRead or type(text) ~= 'string' or text == '' then return nil end
    -- the file only assigns Config.*; nothing else is reachable from it
    local env = { vector3 = vector3, vector4 = vector4, vector2 = vector2, vec3 = vec3 }
    local chunk = load(text, '@pf-justice/config.lua', 't', env)
    if not chunk or not pcall(chunk) or type(env.Config) ~= 'table' then return nil end
    local compat = type(env.Config.Compat) == 'table' and env.Config.Compat or {}
    local bail = type(env.Config.Bail) == 'table' and env.Config.Bail or {}
    justiceFile = {
        live = type(compat.LegacyRuntimes) == 'table' and compat.LegacyRuntimes or nil,
        bailAccount = type(bail.Account) == 'string' and bail.Account or nil,
    }
    return justiceFile
end

--- Forgets what was read (pf-justice restarted; specs).
function S.ResetJusticeConfig() justiceFile = nil end

--- True when pf-justice runs the MDT's jails (LegacyRuntimes.mdt == false), false while the
--- built-in jail does.
function S.HandedOver()
    local forced = tostring(justiceCfg().Runtime or 'auto'):lower()
    if forced == 'justice' then return true end
    if forced == 'legacy' then return false end
    local jc = S.JusticeConfig()
    -- pf-justice's rule (CustodyKit.legacyLive): a runtime is live unless its flag is exactly false
    return jc ~= nil and type(jc.live) == 'table' and jc.live.mdt == false
end

local function justiceUp() return GetResourceState('pf-justice') == 'started' end

--- One pf-justice export call. nil when pf-justice is not running or the call broke off.
local function ju(name, ...)
    if not justiceUp() then return nil end
    local res = exports['pf-justice']
    if not res then return nil end
    local n, args = select('#', ...), { ... }
    local ok, a, b, c = pcall(function() return res[name](res, table.unpack(args, 1, n)) end)
    if not ok then
        print(('^1[pf-policemdt]^7 pf-justice %s failed: %s'):format(name, tostring(a)))
        return nil
    end
    return a, b, c
end
S.Justice = ju

--- The text of a pf-justice refusal for an officer or a payer.
local function juText(res, fallback)
    if type(res) ~= 'table' then return fallback or 'The justice system did not answer; nothing was done' end
    local msg = res.message or res.error
    return type(msg) == 'string' and msg ~= '' and msg or (fallback or 'Refused')
end

--- A pf-justice order this MDT made (a sentence) or imported from its old jail.
local function mdtOrder(order)
    if type(order) ~= 'table' then return false end
    local ref = order.sourceRef
    if type(ref) == 'table' and ref.type == 'mdt_sentence' then return true end
    return type(order.legacyRef) == 'string' and order.legacyRef:match('^mdt_jail:%d+$') ~= nil
end

-- ── database ────────────────────────────────────────────────────────────────

-- The tables (v1-v6: active jails, sentence payment state, licence actions, charge audit, roster
-- backups, released_why) are created by server/schema.lua, the one owner of the migration key.

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
    -- pf-justice sentences: 'ju_pending' while the orders are being made (a cut-off one is
    -- settled from pf-justice's orders, not from a ledger key)
    insertSentenceJustice = [[INSERT INTO pf_mdt_sentences
        (citizenId, citizenName, officerCitizenId, officerName, title, description, sentenceType, charges, reductions,
         fineAmount, prisonTime, prisonTimeBeforeReduction, prisonTimeAfterReduction, reductionPercent,
         executed, fineSuccess, jailSuccess, error, bailAmount, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, NULL, ?, 'ju_pending')]],
    staleJustice = "SELECT * FROM pf_mdt_sentences WHERE status = 'ju_pending' AND createdAt < NOW() - INTERVAL 10 MINUTE ORDER BY id ASC LIMIT 20",
    recoverJustice = "UPDATE pf_mdt_sentences SET status = ?, executed = 1, fineSuccess = ?, jailSuccess = ?, error = ?, fine_key = ? WHERE id = ? AND status = 'ju_pending'",
    sentenceById = 'SELECT * FROM pf_mdt_sentences WHERE id = ? LIMIT 1',
    finePaidLater = 'UPDATE pf_mdt_sentences SET fineSuccess = ? WHERE id = ? AND fine_key = ?',
    -- legacy bail paid on the MDT's own key (society:police) that pf-justice took over
    legacyBailKeys = 'SELECT id, citizenid, bail_key FROM pf_mdt_active_jails WHERE bail_key IS NOT NULL AND released_why IS NULL ORDER BY id ASC LIMIT 100',
}

-- Waits for server/schema.lua. Without it (a load order that leaves the file out) sentencing runs
-- only if its tables already answer with the newest columns, never on a guess.
local function schemaReady()
    local schema = PFMdtSchema
    if type(schema) == 'table' and PFMdtAccess.Callable(schema.WaitReady) then
        return schema.WaitReady() == true
    end
    print('^1[pf-policemdt]^7 server/schema.lua is not loaded: checking the sentencing tables directly')
    local _, jails = db('query', 'SELECT id, released_why FROM pf_mdt_active_jails LIMIT 1')
    local _, sentences = db('query', "SELECT id, status, fine_key FROM pf_mdt_sentences WHERE status = 'payment_pending' LIMIT 1")
    return jails and sentences or false
end

function S.Start()
    if cfg().AllowNegativeBank then
        -- the old branch took fines with SetMoney, outside the ledger; it is gone
        print('^3[pf-policemdt]^7 Config.Sentencing.AllowNegativeBank is ignored: fines are ledger transfers and never take a balance below zero')
    end
    S.dbReady = schemaReady()
    if not S.dbReady then
        local why = PFMdtSchema and PFMdtSchema.lastError or 'tables missing'
        print(('^1[pf-policemdt]^7 database not ready (%s): sentencing and the jail are off'):format(tostring(why)))
    end
    if S.HandedOver() then
        print('^2[pf-policemdt]^7 MDT sentences are pf-justice orders (the built-in jail is off)')
        local jc = S.JusticeConfig()
        if not (jc and jc.live and jc.live.mdt == false) then
            -- forced by Config.Sentencing.Justice.Runtime: pf-justice still treats imported MDT jails as shadows
            print('^3[pf-policemdt]^7 Config.Sentencing.Justice.Runtime forces pf-justice, but pf-justice still lists the MDT jail as running (Config.Compat.LegacyRuntimes.mdt)')
        end
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
    -- once pf-justice runs the MDT's jails, nothing may jail outside a pf-justice order
    if S.HandedOver() then return false, 'MDT jails are pf-justice orders now' end
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
    local handedOver = S.HandedOver()
    -- after the hand-over pf_mdt_active_jails is pf-justice's import source: read only, never ticked
    if not handedOver then
        for _, row in ipairs(db('query', S.SQL.allJails) or {}) do
            local ok, err = pcall(tickJail, row, now)
            if not ok then print(('^1[pf-policemdt]^7 jail tick %s: %s'):format(tostring(row.citizenid), tostring(err))) end
        end
    end
    S.CheckPendingFines()
    if justiceUp() then S.RecoverJusticeSentences() end
    if handedOver then S.SettleLegacyBailMoves() end
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

--- A player loaded in: their sentence resumes (the built-in jail, or the timer of a pf-justice order
--- this MDT made), and a sentence older versions queued for them offline is applied (rcore).
function S.OnPlayerLoaded(src)
    src = tonumber(src)
    if not src then return end
    if S.HandedOver() then S.ResumeJustice(src) else S.Resume(src) end
    S.ApplyQueuedSentence(src)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source or player
    if tonumber(src) then CreateThread(function() Wait(2000) S.OnPlayerLoaded(tonumber(src)) end) end
end)
-- the ESX compatibility layer (PFMdt.GetCore) raises this one instead
AddEventHandler('esx:playerLoaded', function(playerId)
    if tonumber(playerId) then CreateThread(function() Wait(2000) S.OnPlayerLoaded(tonumber(playerId)) end) end
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
    -- pf-justice decides every release of its orders; the client is never asked
    if S.HandedOver() then return end
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
    local ok, err
    if S.HandedOver() then
        -- a fine from before the hand-over settled now: its jail time is a pf-justice order (keyed by
        -- the sentence, so a second settlement cannot make a second one)
        ok, err = S.JusticeJail(P, { minutes = minutes, title = row.title, sentenceId = row.id, charges = row.charges })
    else
        ok, err = S.Jail(P.PlayerData.source, { seconds = minutes * 60, reason = row.title, sentenceId = row.id, bail = row.bailAmount, officerCid = row.officerCitizenId })
    end
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

--- What both runtimes check first: the charges from the database (never the client's numbers),
--- the caps, then (after those waits) presence, and custody for jail time. Returns p or nil, refusal.
local function prepareSentence(src, data, cid)
    local title = PFMdtAccess.Text(data.title, 255)
    if trim(title) == '' then return nil, { success = false, error = 'Title is required' } end
    local description = PFMdtAccess.Text(data.description, 4000)
    local codes, seen = {}, {}
    for _, c in ipairs(type(data.charges) == 'table' and data.charges or {}) do
        local code = trim(PFMdtAccess.Text(c, 16))
        if code ~= '' and not seen[code] and #codes < 60 then seen[code] = true; codes[#codes + 1] = code end
    end
    if #codes == 0 then return nil, { success = false, error = 'At least one charge must be selected' } end

    local rows = loadCharges(codes)
    if not rows then return nil, { success = false, error = 'Database unavailable' } end
    if #rows == 0 then return nil, { success = false, error = 'Unknown charges' } end
    local s = computeSentence(data, rows)
    if s.fine <= 0 and s.minutes <= 0 then return nil, { success = false, error = 'These charges carry no fine or jail time' } end

    -- the database waits are over: the citizen must still be here, and in custody for jail time
    local Target, perr, Officer = S.CheckPresence(src, cid)
    if not Target then return nil, { success = false, error = perr } end
    if s.minutes > 0 and not S.InCustody(Target) then
        return nil, { success = false, error = 'The suspect must be handcuffed or at a booking desk' }
    end
    return { title = title, description = description, s = s, Target = Target, Officer = Officer }
end

local function sentenceBody(src, data, cid)
    local p, refusal = prepareSentence(src, data, cid)
    if not p then return refusal end
    local title, description, s, Target, Officer = p.title, p.description, p.s, p.Target, p.Officer
    if s.minutes > 0 and S.JailOf(cid) then return { success = false, error = 'Citizen is already serving a sentence' } end
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

-- ── sentencing through pf-justice ───────────────────────────────────────────
-- The same checks and locks as above; the fine and the jail time become pf-justice orders keyed by
-- the sentence row, so a retry of the same row never makes a second order or a second charge.

local function decodeCharges(v)
    if type(v) == 'string' then
        local ok, t = pcall(json.decode, v)
        v = ok and t or nil
    end
    return type(v) == 'table' and v or {}
end

-- pf-justice copies at most 50 charges onto an order (the MDT row keeps all of them)
local function justiceCharges(list)
    local out = {}
    for _, c in ipairs(decodeCharges(list)) do
        if #out >= 50 then break end
        if type(c) == 'table' then
            local code = PFMdtAccess.Text(c.code, 24)
            local label = PFMdtAccess.Text(c.name or c.label or c.code, 100)
            if code ~= '' or label ~= '' then out[#out + 1] = { code = code ~= '' and code or nil, label = label ~= '' and label or nil, count = 1 } end
        end
    end
    return out
end

local function openCustodyId(cid)
    local res = ju('GetCustody', cid)
    local c = type(res) == 'table' and res.ok and res.custody or nil
    return type(c) == 'table' and tonumber(c.id) or nil
end

local function uncuff(src)
    if GetResourceState('pfm-policejob') ~= 'started' then return end
    local ok, err = pcall(function()
        if exports['pfm-policejob']:IsCuffed(src) then exports['pfm-policejob']:SetCuffed(src, false, 'jail_order') end
    end)
    if not ok then print(('^3[pf-policemdt]^7 could not take the cuffs off: %s'):format(tostring(err))) end
end

-- The client only draws the time pf-justice reports (pfm-prison moves the player).
local function showJusticeTimer(src, seconds, reason)
    seconds = math.max(1, math.floor(tonumber(seconds) or 0))
    TriggerClientEvent('pf_mdt:client:StartMdtSentence', src, { justice = true, seconds = seconds, minutes = seconds / 60,
        reason = PFMdtAccess.Text(reason or 'MDT Sentence', 255) })
end

--- 'pending' while a pf-justice fine of this citizen waits for the bank, 'clear', or nil (no answer).
local function justiceFinePending(cid)
    local res = ju('GetOrders', cid, { kinds = { 'fine' }, states = { 'payment_pending' }, limit = 20 })
    if type(res) ~= 'table' or not res.ok then return nil end
    return #(res.list or {}) > 0 and 'pending' or 'clear'
end

--- A jail order for an online citizen; presence and custody are the caller's checks. opts =
--- { minutes, title, sentenceId, charges, officerSrc }. Returns ok, err, orderId.
function S.JusticeJail(P, opts)
    local cid, tsrc = P.PlayerData.citizenid, P.PlayerData.source
    local sentenceId = math.floor(tonumber(opts.sentenceId) or 0)
    if sentenceId <= 0 then return false, 'invalid sentence' end
    local minutes = math.floor(tonumber(opts.minutes) or 0)
    local spec = {
        cid = cid, kind = 'jail', minutes = minutes, facility = justiceCfg().Facility, charges = justiceCharges(opts.charges),
        sourceRef = { type = 'mdt_sentence', id = tostring(sentenceId) }, custodyId = openCustodyId(cid),
    }
    local res = ju('CreateOrder', spec, { key = ('pf-policemdt:sentence:%d:jail'):format(sentenceId),
        actor = tonumber(opts.officerSrc) and { src = tonumber(opts.officerSrc) } or nil })
    if type(res) ~= 'table' or not res.ok then return false, juText(res) end
    -- the order holds them now: the cuffs come off (pfm-prison takes them to a cell)
    uncuff(tsrc)
    local active = ju('GetActiveIncarceration', cid)
    local seconds = type(active) == 'table' and active.ok and tonumber(active.remainingSeconds) or minutes * 60
    showJusticeTimer(tsrc, seconds > 0 and seconds or minutes * 60, opts.title)
    if prisonScript() == 'rcore' then
        -- rcore_prison holds the cell; pf-justice still decides the release (releaseOrdered below)
        local okCall, okJail, jerr = pcall(PFMdt.Prison.Jail, tsrc, minutes, PFMdtAccess.Text(opts.title or 'MDT Sentence', 255), opts.officerSrc)
        if not okCall or not okJail then print(('^3[pf-policemdt]^7 rcore_prison refused %s: %s'):format(cid, tostring(jerr))) end
    end
    return true, nil, tonumber(res.orderId)
end

-- The fine as a pf-justice order, paid at once from the citizen's bank (as an MDT fine always was).
-- Returns { orderId, state, note } or nil, err. A refusal stays an open order: pf-justice sends a
-- citizen without the money a phone invoice; an unclear payment is settled by pf-justice's sweep.
local function justiceFine(Target, sentenceId, s, officerSrc)
    local res = ju('CreateOrder', {
        cid = Target.PlayerData.citizenid, kind = 'fine', amount = s.fine, charges = justiceCharges(s.charges),
        sourceRef = { type = 'mdt_sentence', id = tostring(sentenceId) },
    }, { key = ('pf-policemdt:sentence:%d:fine'):format(sentenceId), actor = { src = officerSrc } })
    if type(res) ~= 'table' or not res.ok then return nil, juText(res) end
    local orderId = tonumber(res.orderId)
    local pay = ju('PayOrder', orderId, { payerSrc = Target.PlayerData.source, account = 'bank',
        key = ('pf-policemdt:sentence:%d:pay'):format(sentenceId) })
    if type(pay) == 'table' and pay.ok then return { orderId = orderId, state = 'paid' } end
    if type(pay) == 'table' and pay.state == 'invoiced' then
        return { orderId = orderId, state = 'invoiced', note = ('Fine order #%d: not enough money in the bank; it was sent to the citizen\'s phone as an invoice'):format(orderId) }
    end
    if pay == nil or (type(pay) == 'table' and (pay.error == 'payment_unclear' or pay.state == 'payment_pending')) then
        -- the bank may have taken it: never charged again; pf-justice settles it from the ledger
        return { orderId = orderId, state = 'payment_pending', note = ('Fine order #%d: the bank is still confirming the payment'):format(orderId) }
    end
    return { orderId = orderId, state = 'issued', note = ('Fine order #%d is open: %s'):format(orderId, juText(pay)) }
end

function S.JusticeSentenceBody(src, data, cid)
    if not justiceUp() then return { success = false, error = 'The justice system is not available: nothing was done' } end
    local p, refusal = prepareSentence(src, data, cid)
    if not p then return refusal end
    local title, description, s, Target, Officer = p.title, p.description, p.s, p.Target, p.Officer
    local noAnswer = { success = false, error = 'The justice system did not answer; nothing was done' }
    if s.minutes > 0 then
        local jailed = ju('IsIncarcerated', cid)
        if jailed == nil then return noAnswer end
        if jailed == true then return { success = false, error = 'Citizen is already serving a sentence' } end
    end
    if s.fine > 0 then
        if not ledgerStarted() then return { success = false, error = 'Bank unavailable: nothing was charged' } end
        -- a fine the bank has not confirmed yet (from before the hand-over, or a pf-justice one):
        -- no new fine for this citizen until it settles
        local pending = db('single', S.SQL.pendingFineOf, { cid })
        local juPending = justiceFinePending(cid)
        if juPending == nil then return noAnswer end
        if (type(pending) == 'table' and pending.id) or juPending == 'pending' then
            return { success = false, error = 'A fine for this citizen is still being confirmed by the bank; wait for it to settle' }
        end
    end

    local officerCid, officerName = Officer.PlayerData.citizenid, fullName(Officer)
    local citizenName = fullName(Target)
    local sentenceId = tonumber((db('insert', S.SQL.insertSentenceJustice, {
        cid, citizenName, officerCid, officerName, title, description, s.kind, json.encode(s.charges), json.encode(s.reductions),
        s.fine, s.minutes, s.before, s.after, s.pct, s.bail,
    })))
    if not sentenceId then return { success = false, error = 'Database unavailable' } end

    local fine, fineKey
    if s.fine > 0 then
        local ferr
        fine, ferr = justiceFine(Target, sentenceId, s, src)
        if not fine then
            db('update', S.SQL.finishSentence, { 'failed', 0, 0, 0, ferr, nil, sentenceId })
            notify(src, ferr, 'error')
            return { success = false, error = ferr, id = sentenceId }
        end
        fineKey = ('pf-policemdt:sentence:%d:fine'):format(sentenceId)
    end

    local jailSuccess, err, jailOrderId = 1, nil, nil
    if s.minutes > 0 then
        jailSuccess = 0
        -- the insert and the orders waited: the suspect must still be with the officer and in custody
        local Now, nerr = S.CheckPresence(src, cid)
        if not Now then err = nerr
        elseif not S.InCustody(Now) then err = 'The suspect must be handcuffed or at a booking desk'
        else
            local ok, jerr, oid = S.JusticeJail(Now, { minutes = s.minutes, title = title, sentenceId = sentenceId, charges = s.charges, officerSrc = src })
            if ok then jailSuccess, jailOrderId = 1, oid else err = jerr end
        end
        if err and fine then err = 'Fine issued; jail failed: ' .. tostring(err) end
    end
    -- an issued fine stays an order ('done'): a retry of the whole sentence would fine twice
    local status = (err and not fine) and 'failed' or 'done'
    local note = fine and fine.note or nil
    db('update', S.SQL.finishSentence, { status, 1, (fine and fine.state == 'paid') and 1 or 0, jailSuccess, err or note, fineKey, sentenceId })
    if note then notify(src, note, fine.state == 'payment_pending' and 'error' or 'primary') end
    if err then
        if fine then err = err .. '. The fine order stays: do not sentence it again, issue the jail time alone (type Sentence)' end
        return { success = false, error = err, id = sentenceId, fineIssued = fine ~= nil or nil, fineOrderId = fine and fine.orderId or nil }
    end
    announce(sentenceId, Target, citizenName, officerCid, s)
    return { success = true, id = sentenceId, fineAmount = s.fine, prisonTime = s.minutes, capped = s.capped or nil,
        fineOrderId = fine and fine.orderId or nil, fineState = fine and fine.state or nil, jailOrderId = jailOrderId, message = note }
end

--- A pf-justice sentence still 'ju_pending' long after it started was cut off between its row and
--- its result: what pf-justice holds for the row decides it (the jail time is never added later).
function S.RecoverJusticeSentences()
    for _, row in ipairs(db('query', S.SQL.staleJustice) or {}) do
        if not sentenceLock[row.citizenId] then
            local res = ju('GetOrders', row.citizenId, { limit = 100 })
            if type(res) == 'table' and res.ok then
                local fine, jail
                for _, o in ipairs(res.list or {}) do
                    local ref = type(o.sourceRef) == 'table' and o.sourceRef or {}
                    if ref.type == 'mdt_sentence' and tostring(ref.id) == tostring(row.id) then
                        if o.kind == 'fine' then fine = o elseif o.kind == 'jail' then jail = o end
                    end
                end
                local wantFine, wantJail = (tonumber(row.fineAmount) or 0) > 0, (tonumber(row.prisonTime) or 0) > 0
                local missing = {}
                if wantFine and not fine then missing[#missing + 1] = 'the fine' end
                if wantJail and not jail then missing[#missing + 1] = 'the jail time' end
                local status = (fine or jail) and 'done' or 'failed'
                local why = #missing > 0 and ('The sentence was cut off before ' .. table.concat(missing, ' and ') .. ' was issued') or nil
                db('update', S.SQL.recoverJustice, { status, (fine and fine.state == 'paid') and 1 or 0, (jail or not wantJail) and 1 or 0,
                    why, fine and ('pf-policemdt:sentence:%d:fine'):format(row.id) or nil, row.id })
            end
        end
    end
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
    local ok, res = pcall(S.HandedOver() and S.JusticeSentenceBody or sentenceBody, src, data, cid)
    sentenceLock[cid], officerLock[src] = nil, nil
    if ok and type(res) == 'table' and (res.success or res.pending or res.fineIssued) then lastSentence[pair] = os.time() end
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
    if S.HandedOver() then
        cb({ success = true, sentences = rows, activeJail = S.JusticeActiveJail(cid, rows) })
        return
    end
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

--- The open pf-justice incarceration of a citizen as the MDT page shows it. The bail amount is
--- pf-justice's open offer for that order, else the sentence's own (never for an order imported from
--- the old jail: its offer was pf-justice's to keep or expire).
function S.JusticeActiveJail(cid, rows)
    local res = ju('GetActiveIncarceration', cid)
    if type(res) ~= 'table' or not res.ok then return { active = false, unknown = true } end
    local order = res.order
    if type(order) ~= 'table' then return { active = false } end
    local rem = math.max(0, tonumber(res.remainingSeconds) or 0)
    local ref = type(order.sourceRef) == 'table' and order.sourceRef or {}
    local sentenceId = ref.type == 'mdt_sentence' and tonumber(ref.id) or nil
    local bailAmount, bailPending = 0, nil
    local open = order.state == 'active' or order.state == 'pending'
    local b = ju('GetBail', cid)
    local bail = type(b) == 'table' and b.ok and b.bail or nil
    if type(bail) == 'table' and tonumber(bail.orderId) == tonumber(order.id) and (bail.state == 'offered' or bail.state == 'accepted' or bail.state == 'payment_pending') then
        if bail.state == 'offered' then bailAmount = tonumber(bail.amount) or 0 else bailPending = true end
    elseif sentenceId and open and not order.legacyRef then
        for _, r in ipairs(rows or {}) do
            if tonumber(r.id) == sentenceId and tonumber(r.bailed) ~= 1 then bailAmount = tonumber(r.bailAmount) or 0 end
        end
    end
    return {
        active = true, endsAt = os.time() + rem, remainingMinutes = math.ceil(rem / 60), state = order.state, facility = res.facility,
        bailAmount = open and bailAmount or 0, sentenceId = sentenceId, bailPending = bailPending, orderId = tonumber(order.id),
    }
end

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
    if S.HandedOver() then cb(S.JusticeOfferBail(src, prisonerCid, payerCid)) return end

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

-- ── bail through pf-justice ─────────────────────────────────────────────────
-- The officer's postBail becomes pf-justice OfferBail on the prisoner's open order (the amount comes
-- from the sentence row, never from the client), and the payer's /bailaccept / /baildecline go to
-- AcceptBail / DeclineBail, which check where the payer stands and move the money (society:doj).
-- An open pf-justice offer for the order (e.g. one imported from the old jail) is passed on to the
-- named payer as it is; an imported order without one gets no new offer from the MDT.

--- postBail after the hand-over. Returns the callback answer.
function S.JusticeOfferBail(src, prisonerCid, payerCid)
    if not justiceUp() then return { success = false, error = 'The justice system is not available' } end
    local Payer = online(payerCid)
    if not Payer then return { success = false, error = 'Selected payer must be online' } end
    local res = ju('GetActiveIncarceration', prisonerCid)
    if type(res) ~= 'table' or not res.ok then return { success = false, error = juText(res) } end
    local order = res.order
    if type(order) ~= 'table' or (order.state ~= 'active' and order.state ~= 'pending') then
        return { success = false, error = 'Citizen is not currently sentenced' }
    end
    local orderId = tonumber(order.id)
    local b = ju('GetBail', prisonerCid)
    local bail = type(b) == 'table' and b.ok and b.bail or nil
    local bailId, amount
    if type(bail) == 'table' and tonumber(bail.orderId) == orderId then
        if bail.state == 'accepted' or bail.state == 'payment_pending' then
            return { success = false, error = 'A bail payment for this prisoner is still being confirmed by the bank' }
        elseif bail.state == 'posted' then
            return { success = false, error = 'Bail for this sentence was already paid' }
        elseif bail.state == 'offered' then
            if bail.payerCid and bail.payerCid ~= payerCid then
                return { success = false, error = 'Bail for this prisoner was offered to someone else; that offer must end first' }
            end
            bailId, amount = tonumber(bail.id), tonumber(bail.amount) or 0
        end
    end
    if not bailId then
        if order.legacyRef then return { success = false, error = 'This sentence came from the old MDT jail and has no bail offer left' } end
        local ref = type(order.sourceRef) == 'table' and order.sourceRef or {}
        local row = ref.type == 'mdt_sentence' and db('single', S.SQL.sentenceById, { tonumber(ref.id) }) or nil
        if type(row) ~= 'table' or not row.id then return { success = false, error = 'This sentence was not given through the MDT' } end
        if tonumber(row.bailed) == 1 then return { success = false, error = 'Bail for this sentence was already paid' } end
        amount = math.floor(tonumber(row.bailAmount) or 0)
        if amount <= 0 then return { success = false, error = 'No bail amount for this sentence' } end
        local offer = ju('OfferBail', { orderId = orderId }, { amount = amount, payerCid = payerCid }, { actor = { src = src } })
        if type(offer) ~= 'table' or not offer.ok then return { success = false, error = juText(offer) } end
        bailId = tonumber(offer.bailId)
    end
    local now = os.time()
    local info = ju('GetBail', { bailId = bailId })
    local expiresAt = type(info) == 'table' and info.ok and type(info.bail) == 'table' and tonumber(info.bail.expiresAt) or (now + 600)
    local Prisoner = online(prisonerCid)
    offers[payerCid] = {
        bailId = bailId, prisonerCid = prisonerCid, prisonerName = Prisoner and fullName(Prisoner) or prisonerCid, amount = amount,
        payerCid = payerCid, payerSrc = Payer.PlayerData.source, officerSrc = src, expires = math.max(now + 1, expiresAt),
    }
    local offer = offers[payerCid]
    notify(offer.payerSrc, ('Bail offer: $%d for %s. Type /bailaccept to pay it from your bank, or /baildecline.'):format(amount, offer.prisonerName), 'primary')
    TriggerClientEvent('pf_mdt:client:BailOffer', offer.payerSrc, { amount = amount, prisoner = offer.prisonerName, expiresIn = offer.expires - now })
    notify(src, ('Bail offer sent to %s: they pay with /bailaccept, with you or at a bail desk'):format(fullName(Payer)), 'success')
    return { success = true, pending = true, bailId = bailId, message = 'Bail offer sent: the payer must accept it' }
end

-- AcceptBail refusals after which the same offer can still be paid (the payer moves or tops up)
local RETRYABLE_BAIL = { too_far = true, insufficient_funds = true, rate_limited = true, bank_unavailable = true }

function S.JusticeAcceptBail(src, cid, offer)
    if bailLock['ju:' .. offer.bailId] then return false, 'This bail is already being paid' end
    bailLock['ju:' .. offer.bailId] = true
    local res = ju('AcceptBail', offer.bailId, src, {})
    bailLock['ju:' .. offer.bailId] = nil
    if type(res) == 'table' and res.ok then
        offers[cid] = nil
        if offer.officerSrc then notify(offer.officerSrc, 'Bail paid: the prisoner is released', 'success') end
        return true, 'Bail paid'
    end
    if res == nil or (type(res) == 'table' and not RETRYABLE_BAIL[res.error]) then offers[cid] = nil end
    if type(res) == 'table' and res.error == 'payment_unclear' then
        return false, 'The bank is still confirming the payment; the prisoner is released when it does'
    end
    return false, juText(res)
end

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
    if offer.bailId then return S.JusticeAcceptBail(src, cid, offer) end
    -- an offer of the built-in jail is not paid after the hand-over (pf-justice took the jail over)
    if S.HandedOver() then offers[cid] = nil return false, 'This bail offer has ended; ask the officer for a new one' end
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
    if offer and offer.bailId then
        local res = ju('DeclineBail', offer.bailId, src)
        if type(res) == 'table' and res.ok then notify(src, 'You declined the bail offer', 'primary')
        else notify(src, juText(res), 'error') end
        return
    end
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
    -- after the hand-over pfm-policejob's /unjail is the only one (it ends pf-justice orders); this
    -- one would shadow it
    if not S.HandedOver() then QBCore.Commands.Add('unjail', 'Release a player from MDT jail (Admin)', { { name = 'id', help = 'Server ID' } }, false, function(source, args)
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
    end, 'admin') end
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

-- After the hand-over a supervisor's (or a queued) rcore jailing is a sentence row plus a pf-justice
-- order like any other sentence; pf-justice, not rcore, decides when it ends.
local function justiceToolJail(P, minutes, reason, officerSrc)
    if not justiceUp() then return false, 'The justice system is not available' end
    local cid = P.PlayerData.citizenid
    if ju('IsIncarcerated', cid) == true then return false, 'Citizen is already serving a sentence' end
    local Officer = officerSrc and getPlayer(officerSrc)
    local title = PFMdtAccess.Text(reason or 'MDT Sentence', 255)
    local id = tonumber((db('insert', S.SQL.insertSentenceJustice, {
        cid, fullName(P), Officer and Officer.PlayerData.citizenid or nil, Officer and fullName(Officer) or 'MDT', title, '', 'sentence',
        '[]', '[]', 0, minutes, minutes, minutes, 0, 0,
    })))
    if not id then return false, 'Database unavailable' end
    local ok, err = S.JusticeJail(P, { minutes = minutes, title = title, sentenceId = id, officerSrc = officerSrc })
    db('update', S.SQL.finishSentence, { ok and 'done' or 'failed', 1, 0, ok and 1 or 0, err, nil, id })
    return ok, err
end
local RELEASE_THROUGH_JUSTICE = 'Release and sentence changes go through pf-justice now (/unjail, a court or an admin)'

QBCore.Functions.CreateCallback('pf_mdt:prison:Jail', function(source, cb, data)
    if not rcoreOnly(cb) then return end
    if type(data) ~= 'table' then cb({ success = false, error = 'Invalid data' }) return end
    local cid = trim(PFMdtAccess.Text(data.citizenid or data.citizenId, 64))
    local minutes = cap(data.minutes, cfg().MaxMinutes)
    if cid == '' or minutes <= 0 then cb({ success = false, error = 'Invalid data' }) return end
    local Target, perr, Officer = S.CheckPresence(source, cid)
    if not Target then cb({ success = false, error = perr }) return end
    if not S.InCustody(Target) then cb({ success = false, error = 'The suspect must be handcuffed or at a booking desk' }) return end
    local ok, err
    if S.HandedOver() then
        ok, err = justiceToolJail(Target, minutes, data.reason, source)
    else
        ok, err = S.Jail(Target.PlayerData.source, { seconds = minutes * 60, reason = PFMdtAccess.Text(data.reason or 'MDT Sentence', 255),
            officerCid = Officer.PlayerData.citizenid, officerSource = source })
    end
    if not ok then cb({ success = false, error = err or 'Failed to jail' }) return end
    cb({ success = true, applied = 'online' })
end)

QBCore.Functions.CreateCallback('pf_mdt:prison:Unjail', function(source, cb, data)
    if not rcoreOnly(cb) then return end
    if S.HandedOver() then cb({ success = false, error = RELEASE_THROUGH_JUSTICE }) return end
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
    if S.HandedOver() then cb({ success = false, error = RELEASE_THROUGH_JUSTICE }) return end
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

--- Sentences queued for offline citizens by older versions are applied when they load in (rcore;
--- called from S.OnPlayerLoaded).
function S.ApplyQueuedSentence(src)
    if prisonScript() ~= 'rcore' then return end
    local P = src and getPlayer(src)
    if not P or not S.dbReady then return end
    local cid = P.PlayerData.citizenid
    local rows = db('query', 'SELECT id, minutes, reason FROM pf_mdt_pending_sentences WHERE citizenid = ? ORDER BY id ASC', { cid }) or {}
    local row = rows[#rows]
    if not row then return end
    db('update', 'DELETE FROM pf_mdt_pending_sentences WHERE citizenid = ?', { cid })
    local minutes = cap(row.minutes, cfg().MaxMinutes)
    if minutes <= 0 then return end
    if S.HandedOver() then justiceToolJail(P, minutes, row.reason, nil)
    else S.Jail(src, { seconds = minutes * 60, reason = row.reason }) end
end

-- ── pf-justice events (after the hand-over) ─────────────────────────────────

--- A player who loads in with a pf-justice order this MDT made sees its timer again.
function S.ResumeJustice(src)
    local res = ju('GetActiveIncarceration', src)
    if type(res) ~= 'table' or not res.ok or not mdtOrder(res.order) then return end
    local seconds = tonumber(res.remainingSeconds) or 0
    if seconds <= 0 then return end
    local charges = type(res.order.charges) == 'table' and res.order.charges or {}
    showJusticeTimer(src, seconds, type(charges[1]) == 'table' and charges[1].label or 'MDT Sentence')
end

-- The last incarceration of a citizen ended (time served, bail, /unjail, a court): the timer goes,
-- and an rcore cell opens. pfm-prison walks them out and pf-justice returns the property.
AddEventHandler('pf-justice:server:releaseOrdered', function(cid, orderId, reason)
    if not S.HandedOver() or type(cid) ~= 'string' then return end
    local P = online(cid)
    if not P then return end
    local src = P.PlayerData.source
    TriggerClientEvent('pf_mdt:client:ReleaseMdtSentence', src, { justice = true })
    if prisonScript() == 'rcore' then pcall(PFMdt.Prison.Unjail, src, false) end
end)

-- A fine order of an MDT sentence was paid later (sweep, phone invoice) or refunded.
AddEventHandler('pf-justice:server:paymentSettled', function(order, state)
    if type(order) ~= 'table' or order.kind ~= 'fine' or not S.dbReady then return end
    local ref = type(order.sourceRef) == 'table' and order.sourceRef or {}
    local id = ref.type == 'mdt_sentence' and math.floor(tonumber(ref.id) or 0) or 0
    if id <= 0 or (state ~= 'paid' and state ~= 'refunded') then return end
    db('update', S.SQL.finePaidLater, { state == 'paid' and 1 or 0, id, ('pf-policemdt:sentence:%d:fine'):format(id) })
end)

-- Bail on an MDT order was posted: the sentence row records who paid it.
AddEventHandler('pf-justice:server:bailChanged', function(bail, change)
    if type(bail) ~= 'table' or type(change) ~= 'table' or change.to ~= 'posted' or not S.dbReady then return end
    local res = ju('GetOrder', tonumber(bail.orderId))
    local order = type(res) == 'table' and res.ok and res.order or nil
    local ref = type(order) == 'table' and type(order.sourceRef) == 'table' and order.sourceRef or {}
    local id = ref.type == 'mdt_sentence' and math.floor(tonumber(ref.id) or 0) or 0
    if id > 0 then db('update', S.SQL.markBailed, { PFMdtAccess.Text(bail.payerCid, 64), PFMdtAccess.Text(bail.payerName, 128), id }) end
end)

AddEventHandler('onResourceStart', function(name)
    if name == 'pf-justice' then S.ResetJusticeConfig() end
end)

-- Legacy bail. A bail payment the old jail started with its own key (pf-policemdt:bail:...) and could
-- not confirm before the hand-over was taken over by pf-justice ('payment_pending' with that key);
-- once it settles, pf-justice treats it as bail held in society:<Config.Bail.Account> (doj) and
-- refunds an exoneration from there, but the old key paid it into the MDT's fines account
-- (society:police). The amount the ledger moved is passed on to the bail account once, under
-- pf-policemdt:bailmove:<jailId>:<n> (a clearly refused attempt goes to the next number, an
-- unclear one is waited for; never more than five keys). The legacy rows are only read.
local moveDone = {} -- jail id -> true once its bail key settled (moved, nothing to move, or given up)

local function bailAccount()
    local jc = S.JusticeConfig()
    local name = jc and jc.bailAccount or justiceCfg().BailAccount or 'doj'
    return 'society:' .. tostring(name)
end

local function ledgerTx(key)
    if not ledgerStarted() then return nil, false end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
    if not ok then return nil, false end
    return type(tx) == 'table' and tx or nil, true
end

function S.MoveLegacyBail(row)
    local id = tonumber(row.id)
    local outcome = S.KeyOutcome(row.bail_key)
    if outcome == 'unclear' then return 'wait' end
    if outcome ~= 'paid' then moveDone[id] = true return 'none' end
    local paid = ledgerTx(row.bail_key)
    if not paid then return 'wait' end
    local from, to, amount = paid.to_account, bailAccount(), math.floor(tonumber(paid.amount) or 0)
    if type(from) ~= 'string' or from == to or amount <= 0 then moveDone[id] = true return 'none' end
    for n = 1, 5 do
        local key = ('pf-policemdt:bailmove:%d:%d'):format(id, n)
        local o = S.KeyOutcome(key)
        if o == 'paid' then moveDone[id] = true return 'moved' end
        if o == 'unclear' then return 'wait' end
        if o == 'none' then
            local account = to:match('^society:(.+)$')
            if account then pcall(function() exports['pfm-banking']:EnsureSocietyAccount(account, 'job') end) end
            local res = transfer({ from = from, to = to, amount = amount, key = key, kind = 'bail_transfer',
                reason = ('MDT bail of jail #%d handed to pf-justice'):format(id), metadata = { jailId = id, bailKey = row.bail_key } })
            local r = S.Outcome(res)
            if r == 'paid' then moveDone[id] = true return 'moved' end
            if r == 'unclear' then return 'wait' end
            -- clearly refused: the next pass tries the next key
            print(('^3[pf-policemdt]^7 legacy bail of jail #%d could not be moved to %s yet (%s)'):format(id, to, tostring(res.error)))
            return 'retry'
        end
        -- 'failed': this key was refused before; the next number
    end
    moveDone[id] = true
    print(('^1[pf-policemdt]^7 legacy bail of jail #%d: five transfers to %s were refused; move it by hand'):format(id, to))
    return 'stuck'
end

function S.SettleLegacyBailMoves()
    if not ledgerStarted() then return end
    for _, row in ipairs(db('query', S.SQL.legacyBailKeys) or {}) do
        local id = tonumber(row.id)
        if id and not moveDone[id] then
            local ok, err = pcall(S.MoveLegacyBail, row)
            if not ok then print(('^1[pf-policemdt]^7 legacy bail move %s: %s'):format(tostring(id), tostring(err))) end
        end
    end
end

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
