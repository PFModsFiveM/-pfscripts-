-- pf-justice legacy import (PF_DATABASE_MIGRATIONS 7, v2 function step; PF_ARCHITECTURE 9).
--
-- Turns the two old jails into pf-justice rows, once (INSERT IGNORE on legacy_ref):
--   1. pf_mdt_active_jails rows -> jail orders at bolingbroke (online clock; 'completed' when the MDT
--      already released them, released_why), their items JSON -> a property receipt, an open bail
--      amount -> an 'offered' bail, a held bail_key -> 'payment_pending' with that key.
--   2. offline players with metadata.injail > 0 -> prison orders, legacy_ref
--      'meta_injail:<cid>:<jailid|none>'; metadata.jailitems -> a property receipt.
--   3. metadata.criminalrecord.hasRecord -> one 'legacy_flag' record entry per citizen.
--   4. online players: the same at QBCore:Server:PlayerLoaded (LegacyImport.ForPlayer).
-- The import never deletes or edits the legacy rows or metadata while the legacy runtime runs.
--
-- Batch 15 coexistence: the MDT jail and pfm-prison still run their own jails until 16C/16D set
-- Config.Compat.LegacyRuntimes.mdt / .prison to false. Until then an imported order is a shadow:
--   * its receipt stays in state 'legacy' (the old runtime still holds and returns the items, so
--     filling a locker as well would double them);
--   * SyncTick closes the shadow order (vacated, 'legacy_released') once the old runtime released
--     the prisoner, so IsIncarcerated stays true only while they really are jailed;
--   * MDT bails are paid through the MDT (bail.lua refuses them; the sweep skips them).
-- When a runtime is handed over, Reconcile / ForPlayer fill the lockers from the receipt rows (the
-- runtime no longer returns them) or close what the old runtime already finished.

PFJustice = PFJustice or {}
PFJustice.LegacyImport = PFJustice.LegacyImport or {}
local LI = PFJustice.LegacyImport
PFJustice.CustodyKit = PFJustice.CustodyKit or {} -- filled by custody.lua; looked up when called
local K = PFJustice.CustodyKit

LI.SQL = {
    tableExists = 'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
    columnExists = 'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
    mdtJails = 'SELECT * FROM pf_mdt_active_jails WHERE id > ? ORDER BY id ASC LIMIT 200',
    mdtJail = 'SELECT id, released_why FROM pf_mdt_active_jails WHERE id = ? LIMIT 1',
    insertOrder = [[INSERT IGNORE INTO pf_justice_orders (citizenid, kind, state, facility, clock, required_seconds, served_seconds,
        charges, source_type, source_id, parent_order_id, starts_at, ends_at, last_tick_at, legacy_ref, created_by, created_at, updated_at)
        VALUES (?, ?, ?, ?, 'online', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    orderByLegacy = 'SELECT id, citizenid, state, kind FROM pf_justice_orders WHERE legacy_ref = ? LIMIT 1',
    activeOf = [[SELECT id FROM pf_justice_orders WHERE citizenid = ? AND kind IN ('jail', 'prison', 'remand') AND state = 'active'
        ORDER BY id ASC LIMIT 1]],
    orderEvent = [[INSERT INTO pf_justice_order_events (order_id, action, detail, actor_cid, actor_kind, actor_resource, at)
        VALUES (?, 'imported', ?, NULL, 'system', ?, ?)]],
    insertProperty = [[INSERT IGNORE INTO pf_justice_property (citizenid, custody_id, order_id, stash_id, state, reason, seized_by,
        seized_at, legacy_ref) VALUES (?, NULL, ?, ?, 'legacy', ?, ?, ?, ?)]],
    insertBail = [[INSERT IGNORE INTO pf_justice_bail (citizenid, order_id, amount, state, payer_cid, payer_name, pay_key, offered_by,
        offered_at, expires_at, legacy_ref) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    metaJailed = [[SELECT citizenid, metadata FROM players WHERE citizenid > ? AND JSON_VALID(metadata)
        AND CAST(JSON_VALUE(metadata, '$.injail') AS DECIMAL(12,2)) > 0 ORDER BY citizenid ASC LIMIT 200]],
    metaFlagged = [[SELECT citizenid, metadata FROM players WHERE citizenid > ? AND JSON_VALID(metadata)
        AND JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.criminalrecord.hasRecord')) IN ('true', '1') ORDER BY citizenid ASC LIMIT 200]],
    metaInjailOf = [[SELECT CAST(JSON_VALUE(metadata, '$.injail') AS DECIMAL(12,2)) AS injail FROM players WHERE citizenid = ? LIMIT 1]],
    insertFlag = [[INSERT INTO pf_justice_records (citizenid, kind, ref_type, ref_id, summary, at)
        SELECT ?, 'legacy_flag', 'metadata', 'criminalrecord', ?, ? FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM pf_justice_records WHERE citizenid = ? AND kind = 'legacy_flag')]],
    shadows = [[SELECT id, citizenid, state, legacy_ref FROM pf_justice_orders WHERE legacy_ref IS NOT NULL
        AND state IN ('active', 'pending', 'suspended') AND id > ? ORDER BY id ASC LIMIT 200]],
    shadowsOf = [[SELECT id, citizenid, state, legacy_ref FROM pf_justice_orders WHERE citizenid = ? AND legacy_ref IS NOT NULL
        AND state IN ('active', 'pending', 'suspended')]],
    legacyReceipts = "SELECT * FROM pf_justice_property WHERE state = 'legacy' AND id > ? ORDER BY id ASC LIMIT 200",
    legacyReceiptsOf = "SELECT * FROM pf_justice_property WHERE citizenid = ? AND state = 'legacy'",
    receiptsOfOrder = "SELECT * FROM pf_justice_property WHERE order_id = ? AND state = 'legacy'",
    legacyBails = "SELECT * FROM pf_justice_bail WHERE legacy_ref LIKE 'mdt_bail:%' AND state IN ('offered', 'payment_pending') AND id > ? ORDER BY id ASC LIMIT 200",
    orderState = 'SELECT state FROM pf_justice_orders WHERE id = ? LIMIT 1',
    settleReceipt = "UPDATE pf_justice_property SET state = ?, reason = ?, returned_at = ? WHERE id = ? AND state = 'legacy'",
    settleItems = "UPDATE pf_justice_property_items SET state = ? WHERE property_id = ? AND state = 'held'",
    expireBail = "UPDATE pf_justice_bail SET state = 'expired', closed_at = ? WHERE id = ? AND state = 'offered'",
}

-- Queries that must work: an error aborts the run (the v2 step is then retried at the next start).
local function must(kind, sql, params)
    local res, ok = K.db(kind, sql, params)
    if not ok then error('legacy import: database error', 0) end
    return res
end

local function scalar(sql, params) return tonumber(must('scalar', sql, params)) or 0 end

-- djb2 kept below 2^24 so it stays an integer on every Lua build (fengari integers are 32-bit)
local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
    return ('%06x'):format(h)
end

--- A legacy_ref within 64 characters (a long jail id is shortened to a hash, never cut).
function LI.Ref(prefix, cid, jailId)
    local tail = jailId ~= nil and tostring(jailId) ~= '' and tostring(jailId) or 'none'
    local ref = ('%s:%s:%s'):format(prefix, cid, tail)
    if #ref > 64 then ref = ('%s:%s:h%s'):format(prefix, cid, hash(tail)) end
    return ref:sub(1, 64)
end

--- Items as the old jails stored them ({ name, amount, info, slot? } lists or maps) -> a clean list.
function LI.Items(v)
    if type(v) == 'string' then v = K.decode(v) end
    local out = {}
    if type(v) ~= 'table' then return out end
    for _, it in pairs(v) do
        local amount = type(it) == 'table' and K.int(it.amount, 1)
        if amount and type(it.name) == 'string' and #it.name <= 64 then
            out[#out + 1] = { name = it.name, amount = amount, info = type(it.info) == 'table' and it.info or nil }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function counts() return { orders = 0, receipts = 0, bails = 0, records = 0, closed = 0, filled = 0 } end

-- One order row (INSERT IGNORE). Returns orderId, inserted.
local function importOrder(o, now)
    local parent, startsAt, state = nil, nil, o.state
    if state == 'active' then
        local active = K.db('single', LI.SQL.activeOf, { o.cid })
        if type(active) == 'table' and tonumber(active.id) then
            -- one active incarceration per citizen: a second one runs alongside (15B chain model)
            state, parent = 'pending', tonumber(active.id)
        end
        startsAt = now
    end
    local insertId = must('insert', LI.SQL.insertOrder, { o.cid, o.kind, state, o.facility, o.required, o.served, o.charges,
        o.sourceType, o.sourceId, parent, startsAt, state == 'completed' and now or nil, (state == 'active' or state == 'pending') and now or nil,
        o.ref, o.createdBy, now, now })
    local row = must('single', LI.SQL.orderByLegacy, { o.ref })
    local id = type(row) == 'table' and tonumber(row.id) or nil
    local inserted = (tonumber(insertId) or 0) > 0
    if id and inserted then
        must('insert', LI.SQL.orderEvent, { id, K.encode(o.detail), K.RES, now })
    end
    return id, inserted
end

-- One receipt (state 'legacy') with its item rows. Returns receiptId, inserted.
local function importReceipt(cid, orderId, items, ref, reason, by, now)
    if #items == 0 then return nil, false end
    local temp = ('%slegacy_%s'):format(K.cfg('Property', 'StashPrefix', 'pf_justice_property_'), hash(ref))
    local insertId = must('insert', LI.SQL.insertProperty, { cid, orderId, temp, reason, by, now, ref })
    local r = PFJustice.Property.Store.byLegacy(ref)
    if not r then error('legacy import: receipt not stored', 0) end
    local id = tonumber(r.id)
    local inserted = (tonumber(insertId) or 0) > 0
    if inserted then PFJustice.Property.Store.setStash(id, PFJustice.Property.StashId(id)) end
    -- items are (re)written only while the receipt has none (an interrupted run finishes them)
    if #PFJustice.Property.Store.items(id) == 0 then
        for _, it in ipairs(items) do
            if not PFJustice.Property.Store.addItem(id, it.name, it.amount, it.info, 'held') then error('legacy import: receipt items', 0) end
        end
    end
    return id, inserted
end

--- One pf_mdt_active_jails row.
function LI.ImportMdtRow(row, now, c)
    local cid = row.citizenid
    if not K.validCid(cid) then return end
    local total = K.int(row.total_seconds, 1)
    if not total then return end
    local remaining = math.max(0, math.min(total, K.int(row.remaining_seconds) or 0))
    local released = type(row.released_why) == 'string' and row.released_why ~= ''
    local reason = K.text(row.reason, 96)
    local orderId, inserted = importOrder({
        cid = cid, kind = 'jail', state = released and 'completed' or 'active', facility = 'bolingbroke',
        required = total, served = total - remaining,
        charges = reason and K.encode({ { code = 'MDT', label = reason, count = 1 } }) or nil,
        sourceType = 'mdt_sentence', sourceId = row.sentence_id and tostring(row.sentence_id) or nil,
        ref = 'mdt_jail:' .. tostring(row.id), createdBy = K.validCid(row.officer_citizenid) and row.officer_citizenid or 'legacy',
        detail = { from = 'pf_mdt_active_jails', id = tonumber(row.id), releasedWhy = row.released_why, remaining = remaining },
    }, now)
    if not orderId then return end
    if inserted then c.orders = c.orders + 1 end
    local items = row.provider ~= 'rcore' and LI.Items(row.items) or {}
    local _, rIns = importReceipt(cid, orderId, items, 'mdt_jail_items:' .. tostring(row.id), 'MDT jail (imported)',
        K.validCid(row.officer_citizenid) and row.officer_citizenid or nil, now)
    if rIns then c.receipts = c.receipts + 1 end
    local bail = K.int(row.bail_amount, 1)
    if bail and not released then
        local key = type(row.bail_key) == 'string' and row.bail_key ~= '' and row.bail_key or nil
        local n = must('insert', LI.SQL.insertBail, { cid, orderId, bail, key and 'payment_pending' or 'offered',
            key and row.bail_payer_cid or nil, key and K.text(row.bail_payer_name, 128) or nil, key,
            K.validCid(row.officer_citizenid) and row.officer_citizenid or nil, now,
            now + (tonumber(K.cfg('Bail', 'LegacyOfferSeconds', 7 * 86400)) or 604800), 'mdt_bail:' .. tostring(row.id) })
        if (tonumber(n) or 0) > 0 then c.bails = c.bails + 1 end
    end
end

--- One citizen's metadata (offline from players.metadata, online from the live player).
function LI.ImportMeta(cid, meta, now, c)
    if not K.validCid(cid) or type(meta) ~= 'table' then return {} end
    local made = {}
    local minutes = tonumber(meta.injail) or 0
    local jailId = meta.jailid
    local orderId
    -- once pf-justice owns prison sentences, metadata.injail is only pf-justice's own mirror (no jailid):
    -- importing it again would start a second order beside the real one. A real legacy pfm-prison
    -- sentence always carries the jailid that pfm-prison set.
    if minutes > 0 and not K.legacyLive('prison') and (jailId == nil or jailId == '') then minutes = 0 end
    if minutes > 0 then
        local cap = (tonumber(Config and Config.MaxMinutes) or 1440) * 60
        local id, inserted = importOrder({
            cid = cid, kind = 'prison', state = 'active', facility = 'bolingbroke',
            required = math.max(60, math.min(cap, math.ceil(minutes) * 60)), served = 0, charges = nil,
            sourceType = 'legacy', sourceId = jailId ~= nil and tostring(jailId):sub(1, 64) or nil,
            ref = LI.Ref('meta_injail', cid, jailId), createdBy = 'legacy',
            detail = { from = 'metadata.injail', minutes = minutes, jailid = jailId },
        }, now)
        orderId = id
        if inserted then c.orders = c.orders + 1 made[#made + 1] = id end
    end
    local items = LI.Items(meta.jailitems)
    if #items > 0 then
        local _, rIns = importReceipt(cid, orderId, items, LI.Ref('meta_jailitems', cid, jailId), 'pfm-prison jail (imported)', nil, now)
        if rIns then c.receipts = c.receipts + 1 end
    end
    local rec = meta.criminalrecord
    if type(rec) == 'table' and rec.hasRecord == true then
        local at = now
        if type(rec.date) == 'table' and tonumber(rec.date.year) then
            local ok, t = pcall(os.time, { year = rec.date.year, month = rec.date.month or 1, day = rec.date.day or 1,
                hour = rec.date.hour or 12, min = rec.date.min or 0, sec = rec.date.sec or 0 })
            if ok and tonumber(t) then at = t end
        end
        local n = must('update', LI.SQL.insertFlag, { cid, 'Criminal record flag from before pf-justice', at, cid })
        if K.affected(n) > 0 then c.records = c.records + 1 end
    end
    return made
end

local function paged(sql, firstCursor, cursorOf, fn)
    local cursor = firstCursor
    for _ = 1, 10000 do
        local rows = must('query', sql, { cursor }) or {}
        if #rows == 0 then return end
        for _, row in ipairs(rows) do fn(row) end
        cursor = cursorOf(rows[#rows])
        if #rows < 200 then return end
    end
end

--- The v2 step (and safe to call again any time: everything is keyed by legacy_ref).
--- Returns { ok = true, counts } or raises on a database error.
function LI.Run(now)
    now = now or K.now()
    local c = counts()
    if scalar(LI.SQL.tableExists, { 'pf_mdt_active_jails' }) > 0 then
        paged(LI.SQL.mdtJails, 0, function(r) return tonumber(r.id) end, function(row) LI.ImportMdtRow(row, now, c) end)
    end
    if scalar(LI.SQL.tableExists, { 'players' }) > 0 and scalar(LI.SQL.columnExists, { 'players', 'metadata' }) > 0 then
        local function offline(row)
            -- online players are imported at load from their live metadata (the stored copy can be older)
            if K.playerByCid(row.citizenid) then return end
            LI.ImportMeta(row.citizenid, K.decode(row.metadata) or {}, now, c)
        end
        paged(LI.SQL.metaJailed, '', function(r) return r.citizenid end, offline)
        paged(LI.SQL.metaFlagged, '', function(r) return r.citizenid end, offline)
    end
    LI.Reconcile(now, c)
    print(('^2[pf-justice]^7 legacy import: %d orders, %d receipts, %d bails, %d record flags, %d closed, %d lockers filled')
        :format(c.orders, c.receipts, c.bails, c.records, c.closed, c.filled))
    LI.lastCounts = c
    return { ok = true, counts = c }
end

-- ── shadow orders and hand-over ──────────────────────────────────────────────────────────────────

local function setOrderState(orderId, to, reason)
    local fn = PFJustice.Orders and PFJustice.Orders.SetState
    local res
    if K.callable(fn) then res = fn(orderId, to, { reason = reason, actor = { kind = 'system', label = 'legacy import' } })
    else res = K.callApi('SetOrderState', orderId, to, { reason = reason, actor = { kind = 'system', label = 'legacy import' } }) end
    return type(res) == 'table' and res.ok == true
end

local function settleReceipts(orderId, state, why, now)
    for _, r in ipairs(K.db('query', LI.SQL.receiptsOfOrder, { orderId }) or {}) do
        if K.affected(K.db('update', LI.SQL.settleReceipt, { state, why, now, r.id })) == 1 then
            K.db('update', LI.SQL.settleItems, { state, r.id })
        end
    end
end

--- The old runtime released the prisoner: the shadow order ends and its receipt is settled (the
--- old runtime gave the items back, or forfeited them on an escape).
function LI.CloseShadow(order, why, now, c)
    if setOrderState(tonumber(order.id), 'vacated', 'legacy_released' .. (why and (': ' .. why) or '')) then
        settleReceipts(tonumber(order.id), 'returned', 'settled by the legacy jail', now)
        if c then c.closed = c.closed + 1 end
        return true
    end
    return false
end

--- Fills a 'legacy' receipt's locker from its rows (the old runtime no longer holds the items).
--- All or nothing; true when the receipt became 'held'.
function LI.Fill(r)
    local P = PFJustice.Property
    if not K.started('pfm-inventory') then return false end
    local stash = r.stash_id
    local _, ok = K.inv('CreateInventory', stash, { label = ('Property locker #%s'):format(tostring(r.id)),
        maxweight = tonumber(K.cfg('Property', 'LegacyStashWeight', 10000000)) or 10000000,
        slots = math.max(tonumber(K.cfg('Property', 'StashSlots', 60)) or 60, 100) })
    if not ok then return false end
    local existing = P.LockerItems(stash)
    if #existing > 0 then
        -- an earlier fill got this far: the rows are the receipt, the locker already holds them
        return P.Store.cas(r.id, { 'legacy' }, { state = 'held' })
    end
    local added = {}
    for _, row in ipairs(P.Store.items(r.id)) do
        if row.state == 'held' then
            if K.inv('AddItem', stash, row.item, tonumber(row.amount), nil, K.decode(row.info), 'pf-justice:legacy') ~= true then
                for _, a in ipairs(added) do K.inv('RemoveItem', stash, a.item, tonumber(a.amount), nil, 'pf-justice:legacy:rollback') end
                return false
            end
            added[#added + 1] = row
        end
    end
    K.inv('SaveStash', stash)
    return P.Store.cas(r.id, { 'legacy' }, { state = 'held' })
end

local function orderOpen(orderId)
    if not orderId then return false end
    local row = K.db('single', LI.SQL.orderState, { orderId })
    local s = type(row) == 'table' and row.state
    return s == 'active' or s == 'pending' or s == 'suspended'
end

--- Takes over a 'legacy' receipt: fill the locker; if its order is already over, start the return.
local function takeOver(r, c)
    if LI.Fill(r) then
        c.filled = c.filled + 1
        if not orderOpen(tonumber(r.order_id)) then PFJustice.Property.Return(tonumber(r.id), {}) end
    end
end

--- Batch 15 (old runtimes live): close shadow orders the old runtime already released.
function LI.SyncTick(now)
    now = now or K.now()
    if not K.ready() then return 0 end
    local c = counts()
    local mdtTable = K.legacyLive('mdt') and (tonumber(K.dbv('scalar', LI.SQL.tableExists, { 'pf_mdt_active_jails' })) or 0) > 0
    local cursor = 0
    for _ = 1, 50 do
        local rows = K.db('query', LI.SQL.shadows, { cursor }) or {}
        for _, o in ipairs(rows) do
            cursor = tonumber(o.id)
            local ref = o.legacy_ref
            local mdtId = ref:match('^mdt_jail:(%d+)$')
            if mdtId and mdtTable then
                local live = K.db('single', LI.SQL.mdtJail, { tonumber(mdtId) })
                if not (type(live) == 'table' and tonumber(live.id)) then LI.CloseShadow(o, 'mdt', now, c) end
            elseif ref:sub(1, 12) == 'meta_injail:' and K.legacyLive('prison') then
                local P = K.playerByCid(o.citizenid)
                local minutes
                if P then minutes = tonumber((P.PlayerData.metadata or {}).injail) or 0
                else
                    local row = K.db('single', LI.SQL.metaInjailOf, { o.citizenid })
                    minutes = type(row) == 'table' and tonumber(row.injail) or nil
                end
                if minutes ~= nil and minutes <= 0 then LI.CloseShadow(o, 'pfm-prison', now, c) end
            end
        end
        if #rows < 200 then break end
    end
    return c.closed
end

--- After a hand-over (LegacyRuntimes.mdt = false): MDT shadows become real (lockers filled) or
--- close when the MDT already released them; open MDT bail offers of released prisoners expire.
function LI.Reconcile(now, c)
    now = now or K.now()
    c = c or counts()
    if K.legacyLive('mdt') then return c end
    local hasTable = scalar(LI.SQL.tableExists, { 'pf_mdt_active_jails' }) > 0
    local function mdtRow(id)
        if not hasTable then return nil end
        local r = K.db('single', LI.SQL.mdtJail, { id })
        return type(r) == 'table' and tonumber(r.id) and r or nil
    end
    local cursor = 0
    for _ = 1, 50 do
        local rows = K.db('query', LI.SQL.shadows, { cursor }) or {}
        for _, o in ipairs(rows) do
            cursor = tonumber(o.id)
            local mdtId = tostring(o.legacy_ref):match('^mdt_jail:(%d+)$')
            if mdtId then
                local live = mdtRow(tonumber(mdtId))
                if not live then LI.CloseShadow(o, 'mdt', now, c)
                elseif type(live.released_why) == 'string' and live.released_why ~= '' then
                    -- released while offline after the import: the release (and the items) are ours now
                    for _, r in ipairs(K.db('query', LI.SQL.receiptsOfOrder, { tonumber(o.id) }) or {}) do takeOver(r, c) end
                    setOrderState(tonumber(o.id), 'vacated', 'legacy_released: ' .. live.released_why)
                end
            end
        end
        if #rows < 200 then break end
    end
    cursor = 0
    for _ = 1, 50 do
        local rows = K.db('query', LI.SQL.legacyReceipts, { cursor }) or {}
        for _, r in ipairs(rows) do
            cursor = tonumber(r.id)
            local mdtId = tostring(r.legacy_ref):match('^mdt_jail_items:(%d+)$')
            if mdtId then
                if mdtRow(tonumber(mdtId)) then takeOver(r, c)
                elseif K.affected(K.db('update', LI.SQL.settleReceipt, { 'returned', 'settled by the legacy jail', now, r.id })) == 1 then
                    K.db('update', LI.SQL.settleItems, { 'returned', r.id })
                end
            end
        end
        if #rows < 200 then break end
    end
    cursor = 0
    for _ = 1, 50 do
        local rows = K.db('query', LI.SQL.legacyBails, { cursor }) or {}
        for _, b in ipairs(rows) do
            cursor = tonumber(b.id)
            local mdtId = tostring(b.legacy_ref):match('^mdt_bail:(%d+)$')
            if b.state == 'offered' and mdtId and not mdtRow(tonumber(mdtId)) then K.db('update', LI.SQL.expireBail, { now, b.id }) end
        end
        if #rows < 200 then break end
    end
    return c
end

--- A player loaded in: import their live metadata; after the pfm-prison hand-over also take over
--- or close what pfm-prison held for them (jailitems are then cleared, the locker holds them).
function LI.ForPlayer(src, now)
    now = now or K.now()
    local P = K.player(src)
    if not P or not K.ready() then return nil end
    local cid = P.PlayerData.citizenid
    local c = counts()
    local ok, made = pcall(LI.ImportMeta, cid, P.PlayerData.metadata or {}, now, c)
    if not ok then
        print(('^1[pf-justice]^7 legacy import for %s: %s'):format(cid, tostring(made)))
        return nil
    end
    if not K.legacyLive('prison') then
        local meta = P.PlayerData.metadata or {}
        if (tonumber(meta.injail) or 0) <= 0 then
            for _, o in ipairs(K.db('query', LI.SQL.shadowsOf, { cid }) or {}) do
                if tostring(o.legacy_ref):sub(1, 12) == 'meta_injail:' then LI.CloseShadow(o, 'pfm-prison', now, c) end
            end
        end
        local stillStored = #LI.Items(meta.jailitems) > 0
        local tookAny = false
        for _, r in ipairs(K.db('query', LI.SQL.legacyReceiptsOf, { cid }) or {}) do
            if tostring(r.legacy_ref):sub(1, 15) == 'meta_jailitems:' then
                if stillStored then
                    if LI.Fill(r) then
                        c.filled, tookAny = c.filled + 1, true
                        if not orderOpen(tonumber(r.order_id)) then PFJustice.Property.Return(tonumber(r.id), { toSrc = src }) end
                    end
                elseif K.affected(K.db('update', LI.SQL.settleReceipt, { 'returned', 'settled by the legacy jail', now, r.id })) == 1 then
                    K.db('update', LI.SQL.settleItems, { 'returned', r.id })
                end
            end
        end
        -- the locker holds them now: the metadata copy goes, so nothing is given twice
        if tookAny then K.setMeta(P, 'jailitems', {}) end
    end
    if #made > 0 then TriggerEvent('pf-justice:server:legacyImported', cid, made) end
    return c
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source or player
    if tonumber(src) then
        CreateThread(function()
            Wait(1000)
            LI.ForPlayer(tonumber(src))
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        if K.ready() then
            local ok, err = pcall(LI.SyncTick)
            if not ok then print(('^1[pf-justice]^7 legacy sync: %s'):format(tostring(err))) end
        end
    end
end)
