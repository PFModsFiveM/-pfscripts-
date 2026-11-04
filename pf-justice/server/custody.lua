-- pf-justice custody: the arrest-to-release record (PF_ARCHITECTURE 4.7.3, state machine 5.4).
--
-- Detention (this record) and sentence (an order) are separate. One open custody per citizen. The
-- row in pf_justice_custody is the truth; the memory cache only maps online players to their open
-- record so the clock's IsInHoldingCell and reconnect handling need no query.
--
-- A player who reconnects while arrested, in transport, at booking or held is put back at the
-- facility by the server and re-cuffed where the state needs it (this also ends combat-logging out
-- of an arrest). Every change writes one pf_justice_custody_log row.
--
-- This file also holds PFJustice.CustodyKit, the small helper set that booking.lua, property.lua,
-- bail.lua, legacy_import.lua and compat.lua share (validation, actors, allowlist, locks, ledger).

PFJustice = PFJustice or {}
PFJustice.CustodyKit = PFJustice.CustodyKit or {}
PFJustice.Custody = PFJustice.Custody or {}
local K = PFJustice.CustodyKit
local Custody = PFJustice.Custody

K.RES = GetCurrentResourceName()

-- ── helper kit ───────────────────────────────────────────────────────────────────────────────────

--- A function, a FiveM funcref (a table) or a table with __call: what another resource hands us.
function K.callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

function K.now() return os.time() end

--- Config[block][key] or the default (the config file may be older than this code).
function K.cfg(block, key, default)
    local b = Config and Config[block]
    if type(b) ~= 'table' then return default end
    local v = b[key]
    if v == nil then return default end
    return v
end

function K.err(code, message) return { ok = false, error = code, message = message } end

--- Integer in [min, max] or nil (rejects NaN, infinities and fractions).
function K.int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n)
    if not n then return nil end
    if (min and n < min) or (max and n > max) then return nil end
    return n
end

--- Control characters stripped, trimmed, clipped to max; nil when empty.
function K.text(v, max)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    if max and #s > max then s = s:sub(1, max) end
    return s
end

function K.validCid(v)
    return type(v) == 'string' and #v >= 1 and #v <= 64 and v:match('^[%w_%-]+$') ~= nil
end

function K.validKey(v)
    return type(v) == 'string' and #v >= 1 and #v <= 128 and v:match('^[%w%-_:%.]+$') ~= nil
end

function K.encode(v)
    if v == nil then return nil end
    local ok, s = pcall(json.encode, v)
    if not ok or type(s) ~= 'string' then return nil end
    if #s > 4096 then return json.encode({ truncated = true }) end
    return s
end

function K.decode(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    if ok then return v end
    return nil
end

-- Database: nil plus false on an error (the caller answers db_unavailable; nothing is assumed).
function K.db(kind, sql, params)
    local ok, res = pcall(MySQL[kind].await, sql, params or {})
    if not ok then
        print(('^1[pf-justice]^7 database error: %s'):format(tostring(res)))
        return nil, false
    end
    return res, true
end

--- K.db's value only (safe inside tonumber(), which would take the second result as a base).
function K.dbv(kind, sql, params)
    local res = K.db(kind, sql, params)
    return res
end

function K.affected(n)
    if type(n) == 'table' then n = n.affectedRows or n.changedRows end
    return tonumber(n) or 0
end

--- Whether the schema is applied (15B's schema file exposes Ready; without it the tables are
--- assumed to exist, as in a spec that created them).
function K.ready()
    local schema = PFJustice.Schema
    if type(schema) == 'table' and K.callable(schema.Ready) then return schema.Ready() == true end
    return true
end

-- Players. A player object is a snapshot: re-read it after any mutating call.
function K.player(src)
    src = tonumber(src)
    if not src then return nil end
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(P) == 'table' and P.PlayerData then return P end
    return nil
end

function K.playerByCid(cid)
    if not K.validCid(cid) then return nil end
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayerByCitizenId(cid) end)
    if ok and type(P) == 'table' and P.PlayerData then return P end
    return nil
end

function K.srcOf(cid)
    local P = K.playerByCid(cid)
    return P and tonumber(P.PlayerData.source) or nil
end

function K.cidOf(src)
    local P = K.player(src)
    return P and P.PlayerData.citizenid or nil
end

--- A citizen id from a server id (number) or a citizen id (string), like 15B's PFJustice.Who.
function K.resolveCid(who)
    if type(who) == 'number' then return K.cidOf(who) end
    if K.validCid(who) then return who end
    return nil
end

--- A stable text form of a value (table keys sorted), for comparing two reads of an inventory.
function K.canon(v)
    if type(v) ~= 'table' then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. '=' .. K.canon(v[k]) end
    return '{' .. table.concat(parts, ',') .. '}'
end

function K.name(P)
    local ci = P and P.PlayerData and P.PlayerData.charinfo or {}
    local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if n == '' then return P and P.PlayerData and P.PlayerData.citizenid or 'Unknown' end
    return n:sub(1, 128)
end

function K.setMeta(P, key, value)
    local fn = P.Functions and P.Functions.SetMetaData
    if not K.callable(fn) then fn = P.SetMetaData end
    if K.callable(fn) then fn(key, value) return true end
    return false
end

-- Positions come from the server only.
function K.coords(src)
    src = tonumber(src)
    if not src then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if not c then return nil end
    return vector3(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
end

function K.dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- zone = { coords | center = vector3, radius }
function K.inZone(pos, zone)
    if not pos or type(zone) ~= 'table' then return false end
    local c = zone.coords or zone.center
    if not c then return false end
    return K.dist(pos, c) <= (tonumber(zone.radius) or 0)
end

function K.notify(src, msg, kind)
    if tonumber(src) then TriggerClientEvent('QBCore:Notify', tonumber(src), msg, kind or 'primary') end
end

function K.started(res) return GetResourceState(res) == 'started' end

-- Caller allowlist, actor and locks are 15B's (server/main.lua: PFJustice.Callers, PFJustice.Actor,
-- PFJustice.Locks); they are looked up when called, so the load order of the files does not matter.

--- Registers an export behind the allowlist (checked at the export boundary only). A boolean
--- export answers `refused` when the caller is not allowed.
function K.export(name, fn, refused)
    exports(name, function(...)
        local ok, err = PFJustice.Callers.Check(name, GetInvokingResource())
        if not ok then
            if refused ~= nil then return refused end
            return err
        end
        return fn(...)
    end)
end

--- The actor of opts.actor (architecture 3.5): job, grade, duty and position are read by the server.
--- Without an actor the invoking resource acts as a system process. Returns actor or nil, err.
function K.actor(opts)
    local a = type(opts) == 'table' and opts.actor or nil
    return PFJustice.Actor.Resolve(a, GetInvokingResource())
end

function K.isAdminSrc(src) return PFJustice.Actor.IsAdmin(src) end

function K.actorCid(actor) return actor and PFJustice.Actor.Tag(actor) or nil end

local function jobAllowed(actor, jobs, types, ignoreDuty)
    if not actor or actor.kind ~= 'player' then return false end
    if not actor.onduty and not ignoreDuty then return false end
    if type(types) == 'table' and actor.jobType and types[actor.jobType] then return true end
    local min = type(jobs) == 'table' and jobs[actor.job]
    if min == nil then return false end
    return actor.grade >= (tonumber(min) or 0)
end

--- An on-duty officer (job type leo or a listed job), or a system / admin actor.
function K.isOfficer(actor)
    if not actor then return false end
    if actor.kind == 'system' or actor.kind == 'admin' then return true end
    return jobAllowed(actor, K.cfg('Custody', 'OfficerJobs', { police = 0, corrections = 0 }),
        K.cfg('Custody', 'OfficerJobTypes', { leo = true, corrections = true }))
end

function K.isMedic(actor)
    if not actor then return false end
    if actor.kind == 'system' or actor.kind == 'admin' then return true end
    return jobAllowed(actor, K.cfg('Custody', 'MedicalJobs', { ambulance = 0 }), K.cfg('Custody', 'MedicalJobTypes', { ems = true }))
end

function K.isCourt(actor)
    if not actor then return false end
    if actor.kind == 'system' or actor.kind == 'admin' then return true end
    return jobAllowed(actor, K.cfg('Custody', 'CourtJobs', { judge = 0 }), nil)
end

--- Refused for the role: not_on_duty when the job would qualify on duty, else no_permission.
function K.roleError(actor)
    if actor and actor.kind == 'player' and not actor.onduty then
        local C = 'Custody'
        if jobAllowed(actor, K.cfg(C, 'OfficerJobs', { police = 0, corrections = 0 }), K.cfg(C, 'OfficerJobTypes', { leo = true, corrections = true }), true)
            or jobAllowed(actor, K.cfg(C, 'MedicalJobs', { ambulance = 0 }), K.cfg(C, 'MedicalJobTypes', { ems = true }), true)
            or jobAllowed(actor, K.cfg(C, 'CourtJobs', { judge = 0 }), nil, true) then
            return K.err('not_on_duty', 'You are off duty')
        end
    end
    return K.err('no_permission', 'You may not do that')
end

-- Per-entity locks (taken before the first database wait) and rate limits: 15B's PFJustice.Locks
-- and PFJustice.Rate.
function K.withLock(name, fn) return PFJustice.Locks.With(name, fn) end
function K.locked(name) return PFJustice.Locks.Held(name) end
function K.rate(key, seconds) return PFJustice.Rate.Allow(key, seconds) end
function K.forgetRate(prefix) PFJustice.Rate.Forget(prefix) end

--- 15B's exports as Lua functions: PFJustice.API.<Name> when api.lua exposes it, else the export.
function K.api(name)
    local api = PFJustice.API
    if type(api) == 'table' and K.callable(api[name]) then return api[name] end
    return function(...)
        local e = exports[K.RES]
        if not e then return nil end
        return e[name](e, ...)
    end
end

function K.callApi(name, ...)
    local fn = K.api(name)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        print(('^3[pf-justice]^7 %s failed: %s'):format(name, tostring(a)))
        return nil
    end
    return a, b, c
end

--- Checks a transition against shared/states.lua (15B) and returns the refusal shape.
function K.can(machine, from, to)
    local S = PFJustice.States
    if type(S) == 'table' and K.callable(S.Check) then
        local ok, err = S.Check(machine, from, to)
        if ok then return true end
        return false, err or K.err('invalid_state', ('Cannot go from %s to %s'):format(tostring(from), tostring(to)))
    end
    return false, K.err('invalid_state', 'State machines are not loaded')
end

-- Ledger. A call that broke off is unclear (the bank may have moved the money first); only a clear
-- failure (PFPayout.IsClearFailure) lets a caller undo its side or try a new numbered key.
function K.transfer(opts)
    if not K.started('pfm-banking') then return { ok = false, error = 'bank_unavailable' } end
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable', unclear = true } end
    return res
end

local REFUSED_BEFORE_WRITE = {
    insufficient_funds = true, invalid_request = true, invalid_account = true, same_account = true,
    invalid_amount = true, invalid_key = true, ledger_unavailable = true, bank_unavailable = true,
}
local function clearFailure(res)
    if PFPayout and K.callable(PFPayout.IsClearFailure) then return PFPayout.IsClearFailure(res) == true end
    if type(res) ~= 'table' or res.ok or res.unclear then return false end
    if res.state == 'compensated' then return true end
    if res.state == 'failed' then return res.error ~= 'interrupted_unverified' end
    return res.state == nil and res.txId == nil and REFUSED_BEFORE_WRITE[res.error] == true
end

--- 'paid' | 'failed' | 'unclear'
function K.outcome(res)
    if type(res) ~= 'table' then return 'unclear' end
    if res.ok then return 'paid' end
    if clearFailure(res) then return 'failed' end
    return 'unclear'
end

--- What the ledger holds under a key: 'paid' | 'failed' | 'none' | 'unclear'.
function K.keyOutcome(key)
    if not K.started('pfm-banking') then return 'unclear' end
    local ok, tx = pcall(function() return exports['pfm-banking']:GetTransaction(key) end)
    if not ok then return 'unclear' end
    if tx == nil then return 'none' end
    if type(tx) ~= 'table' then return 'unclear' end
    if tx.state == 'completed' then return 'paid' end
    if tx.state == 'compensated' or (tx.state == 'failed' and tx.error ~= 'interrupted_unverified') then return 'failed' end
    return 'unclear'
end

-- Inventory (pfm-inventory exports). Each call is guarded: a throwing export counts as a failure.
function K.inv(fnName, ...)
    if not K.started('pfm-inventory') then return nil, false end
    local args = table.pack(...)
    local ok, res = pcall(function() return exports['pfm-inventory'][fnName](exports['pfm-inventory'], table.unpack(args, 1, args.n)) end)
    if not ok then
        print(('^3[pf-justice]^7 pfm-inventory %s failed: %s'):format(fnName, tostring(res)))
        return nil, false
    end
    return res, true
end

--- Whether the legacy runtime still owns its jails (batch 15): 'mdt' (pf-policemdt-DEV built-in
--- jail), 'prison' (pfm-prison metadata jail), 'policejob' (PJ /jail writing criminalrecord).
--- 16C/16D set Config.Compat.LegacyRuntimes.<name> = false when they hand the runtime to pf-justice.
function K.legacyLive(name)
    local list = K.cfg('Compat', 'LegacyRuntimes', nil)
    if type(list) ~= 'table' then return true end
    return list[name] ~= false
end

--- Whether a legacy_ref belongs to an old jail that still runs (the record is only a shadow).
function K.legacyRefLive(ref)
    if type(ref) ~= 'string' then return false end
    if ref:sub(1, 4) == 'mdt_' then return K.legacyLive('mdt') end
    if ref:sub(1, 5) == 'meta_' then return K.legacyLive('prison') end
    return false
end

-- ── custody store (SQL; specs replace Custody.Store with an in-memory one) ───────────────────────

local CUSTODY_COLUMNS = {
    state = true, prev_state = true, facility = true, cell_id = true, officer_cid = true, reason = true,
    charges = true, incident_id = true, booking_no = true, hold_until = true, release_reason = true,
    updated_at = true, closed_at = true,
}

local function setClause(fields, allowed)
    local parts, params = {}, {}
    local names = {}
    for k in pairs(fields) do
        if not allowed[k] then error('column not allowed: ' .. tostring(k)) end
        names[#names + 1] = k
    end
    table.sort(names)
    for _, k in ipairs(names) do
        local v = fields[k]
        if v == K.NULL then
            parts[#parts + 1] = ('`%s` = NULL'):format(k)
        else
            parts[#parts + 1] = ('`%s` = ?'):format(k)
            params[#params + 1] = v
        end
    end
    return table.concat(parts, ', '), params
end
K.setClause = setClause
K.NULL = setmetatable({}, { __tostring = function() return 'NULL' end })

Custody.SQL = {
    openOf = 'SELECT * FROM pf_justice_custody WHERE citizenid = ? AND closed_at IS NULL ORDER BY id DESC LIMIT 1',
    byId = 'SELECT * FROM pf_justice_custody WHERE id = ? LIMIT 1',
    byKey = 'SELECT * FROM pf_justice_custody WHERE idem_key = ? LIMIT 1',
    latestOf = 'SELECT * FROM pf_justice_custody WHERE citizenid = ? ORDER BY id DESC LIMIT 1',
    insert = [[INSERT INTO pf_justice_custody (citizenid, state, facility, officer_cid, reason, charges, incident_id,
        opened_at, updated_at, idem_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    log = 'INSERT INTO pf_justice_custody_log (custody_id, kind, data, actor_cid, at) VALUES (?, ?, ?, ?, ?)',
    listLog = 'SELECT * FROM pf_justice_custody_log WHERE custody_id = ? ORDER BY id DESC LIMIT ?',
    lastLogOf = 'SELECT * FROM pf_justice_custody_log WHERE custody_id = ? AND kind = ? ORDER BY id DESC LIMIT 1',
    dueHolds = [[SELECT * FROM pf_justice_custody WHERE closed_at IS NULL AND hold_until IS NOT NULL AND hold_until < ?
        AND state IN ('booked', 'held') ORDER BY hold_until ASC LIMIT ?]],
    openOfCitizenAll = 'SELECT * FROM pf_justice_custody WHERE citizenid = ? AND closed_at IS NULL',
}

Custody.Store = {
    openOf = function(cid) local r = K.db('single', Custody.SQL.openOf, { cid }) return type(r) == 'table' and r.id and r or nil end,
    get = function(id) local r = K.db('single', Custody.SQL.byId, { id }) return type(r) == 'table' and r.id and r or nil end,
    byKey = function(key) local r = K.db('single', Custody.SQL.byKey, { key }) return type(r) == 'table' and r.id and r or nil end,
    latestOf = function(cid) local r = K.db('single', Custody.SQL.latestOf, { cid }) return type(r) == 'table' and r.id and r or nil end,
    insert = function(row)
        local id = K.db('insert', Custody.SQL.insert, { row.citizenid, row.state, row.facility, row.officer_cid, row.reason,
            row.charges, row.incident_id, row.opened_at, row.updated_at, row.idem_key })
        return tonumber(id)
    end,
    --- Compare-and-set: only an open row still in `fromState` changes. True when it did.
    cas = function(id, fromState, fields)
        local set, params = setClause(fields, CUSTODY_COLUMNS)
        params[#params + 1] = id
        params[#params + 1] = fromState
        local n = K.db('update', ('UPDATE pf_justice_custody SET %s WHERE id = ? AND state = ? AND closed_at IS NULL'):format(set), params)
        return K.affected(n) == 1
    end,
    log = function(custodyId, kind, data, actorCid, at)
        local id = K.db('insert', Custody.SQL.log, { custodyId, kind, data, actorCid, at })
        return tonumber(id)
    end,
    listLog = function(custodyId, limit) return K.db('query', Custody.SQL.listLog, { custodyId, limit }) or {} end,
    lastLogOf = function(custodyId, kind)
        local r = K.db('single', Custody.SQL.lastLogOf, { custodyId, kind })
        return type(r) == 'table' and r.id and r or nil
    end,
    dueHolds = function(now, limit) return K.db('query', Custody.SQL.dueHolds, { now, limit }) or {} end,
    openAllOf = function(cid) return K.db('query', Custody.SQL.openOfCitizenAll, { cid }) or {} end,
}

-- ── memory (online players only) ─────────────────────────────────────────────────────────────────

Custody.bySrc = {}      -- src -> custody row (open)
Custody.srcByCid = {}   -- cid -> src
Custody.flagged = {}    -- custody id -> true once an over-long hold was reported

local OPEN_STATES = { detained = true, arrested = true, in_transport = true, booking = true, booked = true,
    held = true, remanded = true, hospital = true }
Custody.OPEN_STATES = OPEN_STATES

local function remember(row)
    if not row or not row.citizenid then return end
    local src = K.srcOf(row.citizenid)
    if not src then return end
    if row.closed_at or not OPEN_STATES[row.state] then
        Custody.bySrc[src], Custody.srcByCid[row.citizenid] = nil, nil
        return
    end
    Custody.bySrc[src], Custody.srcByCid[row.citizenid] = row, src
end
Custody.Remember = remember

local function forget(cid)
    local src = Custody.srcByCid[cid]
    if src then Custody.bySrc[src] = nil end
    Custody.srcByCid[cid] = nil
end

--- The public shape of a custody row (GetCustody).
function Custody.Public(row)
    if not row then return nil end
    return {
        id = tonumber(row.id), cid = row.citizenid, state = row.state, prevState = row.prev_state, facility = row.facility,
        cellId = row.cell_id, since = tonumber(row.opened_at), bookingNo = row.booking_no, holdUntil = tonumber(row.hold_until),
        officerCid = row.officer_cid, reason = row.reason, charges = K.decode(row.charges), incidentId = row.incident_id,
        releaseReason = row.release_reason, closedAt = tonumber(row.closed_at),
    }
end

function Custody.Log(custodyId, kind, data, actor)
    return Custody.Store.log(custodyId, kind, K.encode(data), K.actorCid(actor), K.now())
end

local function changed(row, change)
    remember(row)
    -- the clock counts hospital custody as time inside (15B Clock.SetHospitalCustody)
    local clock = PFJustice.Clock
    if clock and K.callable(clock.SetHospitalCustody) then clock.SetHospitalCustody(row.citizenid, row.state == 'hospital' and not row.closed_at) end
    TriggerEvent('pf-justice:server:custodyChanged', Custody.Public(row), change)
end

--- Moves an open custody from its current state to `to` (checked against the machine and written
--- with a compare-and-set). extra = more columns. Returns the new row or nil, err.
function Custody.Move(row, to, extra, actor, logKind, logData)
    local okMove, err = K.can('custody', row.state, to)
    if not okMove then return nil, err end
    local fields = { state = to, updated_at = K.now() }
    for k, v in pairs(extra or {}) do fields[k] = v end
    if to == 'released' or to == 'transferred' then fields.closed_at = fields.closed_at or K.now() end
    if not Custody.Store.cas(row.id, row.state, fields) then
        return nil, K.err('invalid_state', 'The custody changed meanwhile; read it again')
    end
    local from = row.state
    local new = Custody.Store.get(row.id) or row
    Custody.Log(row.id, logKind or 'state', logData or { from = from, to = to }, actor)
    if new.closed_at then forget(new.citizenid) end
    changed(new, { from = from, to = to })
    return new
end

-- ── facility helpers ─────────────────────────────────────────────────────────────────────────────

--- The booking zone the position is in (zone table) or nil.
function Custody.BookingZoneAt(pos)
    for _, z in ipairs(K.cfg('Custody', 'BookingZones', {}) or {}) do
        if K.inZone(pos, z) then return z end
    end
    return nil
end

function Custody.Cell(facility, cellId)
    local cells = (K.cfg('Custody', 'HoldingCells', {}) or {})[facility or '']
    for _, c in ipairs(cells or {}) do
        if c.id == cellId then return c end
    end
    return nil
end

local function facilityKnown(f)
    return type(f) == 'string' and Config and Config.Facilities and Config.Facilities[f] ~= nil
end

--- Officer presence: within 5 m of the target, or both inside one booking zone (PMDT rule).
function Custody.OfficerPresent(actor, targetSrc)
    if not actor or actor.kind ~= 'player' then return true end
    local a, t = K.coords(actor.src), K.coords(targetSrc)
    if not a or not t then return false end
    if K.dist(a, t) <= (tonumber(K.cfg('Custody', 'OfficerDistance', 5.0)) or 5.0) then return true end
    local za, zt = Custody.BookingZoneAt(a), Custody.BookingZoneAt(t)
    return za ~= nil and za == zt
end

-- ── API ──────────────────────────────────────────────────────────────────────────────────────────

local function loadById(custodyId)
    local id = K.int(custodyId, 1)
    if not id then return nil, K.err('bad_args', 'custodyId must be a positive integer') end
    local row = Custody.Store.get(id)
    if not row then return nil, K.err('not_found', 'No such custody') end
    return row
end
Custody.LoadById = loadById

local function sameOpenArgs(row, cid, reason)
    return row.citizenid == cid and (row.reason or '') == (reason or '')
end

--- OpenCustody(target, opts): target = server id. opts = { reason, charges?, incidentId?, key,
--- state = 'arrested' | 'detained', facility?, actor = { src } }.
function Custody.Open(target, opts)
    opts = type(opts) == 'table' and opts or {}
    local src = K.int(target, 1)
    if not src then return K.err('bad_args', 'target must be a server id') end
    local P = K.player(src)
    if not P then return K.err('offline', 'The citizen is not online') end
    local cid = P.PlayerData.citizenid
    local key = opts.key
    if key ~= nil and not K.validKey(key) then return K.err('bad_args', 'key must be 1-128 characters of [A-Za-z0-9-_:.]') end
    local state = opts.state or 'arrested'
    local okInit, initErr = K.can('custody', nil, state)
    if not okInit then return initErr end
    local reason = K.text(opts.reason, 255)
    local charges
    if opts.charges ~= nil then
        if type(opts.charges) ~= 'table' or #opts.charges > 50 then return K.err('bad_args', 'charges must be a list (at most 50)') end
        charges = {}
        for _, c in ipairs(opts.charges) do
            if type(c) == 'table' then
                charges[#charges + 1] = { code = K.text(c.code, 16), label = K.text(c.label, 96), count = K.int(c.count, 1, 99) or 1 }
            end
        end
    end
    local incidentId = opts.incidentId ~= nil and K.text(opts.incidentId, 32) or nil
    local facility = opts.facility
    if facility ~= nil and not facilityKnown(facility) then return K.err('bad_args', 'Unknown facility') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isOfficer(actor) then return K.roleError(actor) end
    if actor.kind == 'player' then
        if actor.src == src then return K.err('no_permission', 'You cannot arrest yourself') end
        local d = K.dist(K.coords(actor.src), K.coords(src))
        if d > (tonumber(K.cfg('Custody', 'TouchDistance', 2.5)) or 2.5) and not Custody.OfficerPresent(actor, src) then
            return K.err('too_far', 'The citizen must be with you')
        end
    end
    if not K.ready() then return K.err('db_unavailable', 'The justice database is not ready') end

    return K.withLock('custody:cid:' .. cid, function()
        if key then
            local existing = Custody.Store.byKey(key)
            if existing then
                if sameOpenArgs(existing, cid, reason) then
                    return { ok = true, duplicate = true, custodyId = tonumber(existing.id), existing = true, state = existing.state }
                end
                return K.err('key_reused', 'This key was used for another custody')
            end
        end
        local open = Custody.Store.openOf(cid)
        if open then
            return { ok = false, error = 'conflict', message = 'The citizen is already in custody', custodyId = tonumber(open.id), existing = true }
        end
        local t = K.now()
        if not facility then
            local zone = Custody.BookingZoneAt(K.coords(src))
            facility = zone and zone.facility or K.cfg('Custody', 'DefaultFacility', 'mrpd_holding')
        end
        local id = Custody.Store.insert({
            citizenid = cid, state = state, facility = facility, officer_cid = actor.cid, reason = reason,
            charges = K.encode(charges), incident_id = incidentId, opened_at = t, updated_at = t, idem_key = key,
        })
        if not id then return K.err('db_unavailable', 'The custody could not be saved') end
        Custody.Log(id, 'opened', { state = state, facility = facility, reason = reason }, actor)
        local row = Custody.Store.get(id)
        changed(row, { from = nil, to = state })
        return { ok = true, custodyId = id, state = state }
    end)
end

--- GetCustody(who): id or cid -> the open custody (or the latest closed one with opts.latest).
function Custody.Get(who, opts)
    local cid = K.resolveCid(who)
    if not cid then return K.err('bad_args', 'who must be a server id or a citizen id') end
    local row
    local src = Custody.srcByCid[cid]
    if src and Custody.bySrc[src] then row = Custody.bySrc[src] else row = Custody.Store.openOf(cid) end
    if not row and type(opts) == 'table' and opts.latest then row = Custody.Store.latestOf(cid) end
    return { ok = true, custody = Custody.Public(row) }
end

-- Targets SetCustodyState may reach; the others have their own export (they need more than a state).
local GENERIC_TARGETS = { arrested = true, in_transport = true, booking = true, remanded = true }

--- SetCustodyState(custodyId, to, opts)
function Custody.SetState(custodyId, to, opts)
    opts = type(opts) == 'table' and opts or {}
    if type(to) ~= 'string' then return K.err('bad_args', 'to must be a state name') end
    if not GENERIC_TARGETS[to] then
        return K.err('invalid_state', ('Use the matching export for %s (BookCustody, AssignHoldingCell, TransferCustody, ReleaseFromCustody)'):format(to))
    end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if to == 'remanded' then
        if not K.isCourt(actor) then return K.err('no_permission', 'Only a court decides remand') end
    elseif not K.isOfficer(actor) then
        return K.roleError(actor)
    end
    local row, err = loadById(custodyId)
    if not row then return err end
    return K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if row.closed_at then return K.err('invalid_state', 'The custody is closed') end
        local okMove, moveErr = K.can('custody', row.state, to)
        if not okMove then return moveErr end
        local targetSrc = K.srcOf(row.citizenid)
        local extra = {}
        if to == 'booking' then
            -- booking needs the citizen inside a booking zone, with the officer
            if not targetSrc then return K.err('offline', 'The citizen is not online') end
            local zone = Custody.BookingZoneAt(K.coords(targetSrc))
            if not zone then return K.err('too_far', 'The citizen must be inside a booking area') end
            if not Custody.OfficerPresent(actor, targetSrc) then return K.err('too_far', 'You must be with the citizen') end
            extra.facility = zone.facility or row.facility
        elseif (to == 'in_transport' or to == 'arrested') and actor.kind == 'player' then
            if not targetSrc then return K.err('offline', 'The citizen is not online') end
            if K.dist(K.coords(actor.src), K.coords(targetSrc)) > 10.0 then return K.err('too_far', 'You must be with the citizen') end
        end
        local new, moveErr2 = Custody.Move(row, to, extra, actor, to == 'remanded' and 'remanded' or 'state',
            { from = row.state, to = to, note = K.text(opts.note, 200) })
        if not new then return moveErr2 end
        -- remand means no bail: offers made before it end (a court may offer again afterwards)
        if to == 'remanded' and PFJustice.Bail and K.callable(PFJustice.Bail.ExpireFor) then
            PFJustice.Bail.ExpireFor('custody_id', tonumber(new.id), 'remanded')
        end
        return { ok = true, custody = Custody.Public(new) }
    end)
end

--- Medical screening (4.7.4): a down / red / orange patient goes to hospital before a cell.
--- Returns 'clear' | 'hospital_required' | 'unavailable'.
function Custody.Screen(cid, src)
    local block = K.cfg('Custody', 'BlockScreening', { down = true, red = true, orange = true })
    if K.started('pf-ambulancejob') then
        local ok, s = pcall(function() return exports['pf-ambulancejob']:GetPatientSummary(cid) end)
        if ok and type(s) == 'table' and s.ok ~= false then
            local down = s.down == true or s.consciousness == 'down' or s.consciousness == 'unconscious' or s.consciousness == 'dead'
            if down and block.down then return 'hospital_required' end
            local tri = type(s.triage) == 'string' and s.triage:lower() or nil
            if tri and block[tri] then return 'hospital_required' end
            return 'clear'
        end
    end
    -- Without the medical engine: the death / last-stand flags (conservative: they only block).
    local P = src and K.player(src)
    local meta = P and P.PlayerData.metadata or {}
    if block.down and (meta.isdead == true or meta.inlaststand == true) then return 'hospital_required' end
    return 'unavailable'
end

--- AssignHoldingCell(custodyId, cellId, opts)
function Custody.AssignCell(custodyId, cellId, opts)
    opts = type(opts) == 'table' and opts or {}
    if type(cellId) ~= 'string' or #cellId > 32 then return K.err('bad_args', 'cellId must be a cell id') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isOfficer(actor) then return K.roleError(actor) end
    local row, err = loadById(custodyId)
    if not row then return err end
    return K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if row.closed_at then return K.err('invalid_state', 'The custody is closed') end
        local cell = Custody.Cell(row.facility, cellId)
        if not cell then return K.err('not_found', 'No such holding cell at ' .. tostring(row.facility)) end
        if row.state == 'held' then
            -- moving between cells keeps the state
            if row.cell_id == cellId then return { ok = true, duplicate = true } end
            if not Custody.Store.cas(row.id, 'held', { cell_id = cellId, updated_at = K.now() }) then
                return K.err('invalid_state', 'The custody changed meanwhile')
            end
            Custody.Log(row.id, 'cell', { from = row.cell_id, to = cellId }, actor)
            changed(Custody.Store.get(row.id), { from = 'held', to = 'held' })
            return { ok = true }
        end
        local okMove, moveErr = K.can('custody', row.state, 'held')
        if not okMove then return moveErr end
        local targetSrc = K.srcOf(row.citizenid)
        if actor.kind == 'player' and targetSrc and not Custody.OfficerPresent(actor, targetSrc) then
            return K.err('too_far', 'You must be with the citizen')
        end
        local screening = Custody.Screen(row.citizenid, targetSrc)
        if screening == 'hospital_required' then
            Custody.Log(row.id, 'medical_check', { result = screening, at = 'holding_cell' }, actor)
            return K.err('invalid_state', 'Medical screening: the citizen must go to hospital before a holding cell')
        end
        local holdUntil = K.now() + (tonumber(K.cfg('Custody', 'MaxHoldSeconds', 4 * 3600)) or 14400)
        local new, moveErr2 = Custody.Move(row, 'held', { cell_id = cellId, hold_until = holdUntil }, actor, 'cell',
            { from = row.state, to = 'held', cell = cellId, screening = screening })
        if not new then return moveErr2 end
        return { ok = true, custody = Custody.Public(new) }
    end)
end

local LOG_KINDS = { rights_read = true, phone_call = true, attorney_visit = true, interview_start = true, interview_end = true,
    meal = true, medical_check = true, use_of_force = true, note = true }
local MEDICAL_LOG = { medical_check = true }

--- AddCustodyLog(custodyId, kind, data, opts)
function Custody.AddLog(custodyId, kind, data, opts)
    opts = type(opts) == 'table' and opts or {}
    if not LOG_KINDS[kind] then return K.err('bad_args', 'Unknown log kind') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if MEDICAL_LOG[kind] then
        if not K.isMedic(actor) and not K.isOfficer(actor) then return K.roleError(actor) end
    elseif not K.isOfficer(actor) then
        return K.roleError(actor)
    end
    local clean = {}
    if type(data) == 'table' then
        for k, v in pairs(data) do
            if type(k) == 'string' and #k <= 32 then
                if type(v) == 'string' then clean[k] = K.text(v, 500)
                elseif type(v) == 'number' or type(v) == 'boolean' then clean[k] = v end
            end
        end
    elseif data ~= nil then
        clean.text = K.text(data, 500)
    end
    local row, err = loadById(custodyId)
    if not row then return err end
    if row.closed_at then return K.err('invalid_state', 'The custody is closed') end
    local id = Custody.Log(row.id, kind, clean, actor)
    if not id then return K.err('db_unavailable', 'The log entry could not be saved') end
    return { ok = true, logId = id }
end

local TRANSFER_KINDS = { hospital = true, prison = true, court = true, station = true }

--- TransferCustody(custodyId, to, opts): to = { kind = 'hospital' | 'prison' | 'court' | 'station', id }.
function Custody.Transfer(custodyId, to, opts)
    opts = type(opts) == 'table' and opts or {}
    if type(to) ~= 'table' or not TRANSFER_KINDS[to.kind] then return K.err('bad_args', 'to.kind must be hospital, prison, court or station') end
    local dest = K.text(to.id, 32)
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if to.kind == 'hospital' then
        if not K.isMedic(actor) and not K.isOfficer(actor) then return K.roleError(actor) end
    elseif not K.isOfficer(actor) then
        return K.roleError(actor)
    end
    local row, err = loadById(custodyId)
    if not row then return err end
    return K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if row.closed_at then return K.err('invalid_state', 'The custody is closed') end
        if to.kind == 'hospital' then
            local new, e = Custody.Move(row, 'hospital', { prev_state = row.state }, actor, 'transfer',
                { kind = 'hospital', to = dest, from = row.state })
            if not new then return e end
            return { ok = true, custody = Custody.Public(new) }
        elseif to.kind == 'prison' then
            if dest and not facilityKnown(dest) then return K.err('bad_args', 'Unknown facility') end
            local new, e = Custody.Close(row, 'transferred', actor, { kind = 'prison', to = dest })
            if not new then return e end
            return { ok = true, custody = Custody.Public(new) }
        end
        -- station or court: the citizen moves, the state does not
        if to.kind == 'station' then
            if not dest or not facilityKnown(dest) then return K.err('bad_args', 'Unknown facility') end
        elseif not dest then
            return K.err('bad_args', 'to.id must name the court')
        end
        local facility = to.kind == 'court' and ('court:' .. dest):sub(1, 32) or dest
        if not Custody.Store.cas(row.id, row.state, { facility = facility, updated_at = K.now() }) then
            return K.err('invalid_state', 'The custody changed meanwhile')
        end
        Custody.Log(row.id, 'transfer', { kind = to.kind, to = facility, from = row.facility }, actor)
        local new = Custody.Store.get(row.id)
        changed(new, { from = row.state, to = row.state, facility = facility })
        return { ok = true, custody = Custody.Public(new) }
    end)
end

--- ReturnCustody(custodyId, opts): back from a hospital (to the state before it) or a court (to the
--- facility before it).
function Custody.Return(custodyId, opts)
    opts = type(opts) == 'table' and opts or {}
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if not K.isMedic(actor) and not K.isOfficer(actor) then return K.roleError(actor) end
    local row, err = loadById(custodyId)
    if not row then return err end
    return K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if row.closed_at then return K.err('invalid_state', 'The custody is closed') end
        if row.state == 'hospital' then
            local back = row.prev_state
            if not back or not OPEN_STATES[back] or back == 'hospital' then return K.err('invalid_state', 'No state to return to') end
            local new, e = Custody.Move(row, back, { prev_state = K.NULL }, actor, 'return', { from = 'hospital', to = back })
            if not new then return e end
            return { ok = true, custody = Custody.Public(new) }
        end
        if type(row.facility) == 'string' and row.facility:sub(1, 6) == 'court:' then
            local back
            for _, l in ipairs(Custody.Store.listLog(row.id, 50)) do
                local d = K.decode(l.data)
                if l.kind == 'transfer' and type(d) == 'table' and d.kind == 'court' then back = d.from break end
            end
            back = back or K.cfg('Custody', 'DefaultFacility', 'mrpd_holding')
            if not Custody.Store.cas(row.id, row.state, { facility = back, updated_at = K.now() }) then
                return K.err('invalid_state', 'The custody changed meanwhile')
            end
            Custody.Log(row.id, 'return', { from = row.facility, to = back }, actor)
            local new = Custody.Store.get(row.id)
            changed(new, { from = row.state, to = row.state, facility = back })
            return { ok = true, custody = Custody.Public(new) }
        end
        return K.err('invalid_state', 'The custody is not on a transfer')
    end)
end

local RELEASE_REASONS = { no_charges = true, cited = true, bailed = true, court_order = true, sentence_complete = true,
    transferred = true }
Custody.RELEASE_REASONS = RELEASE_REASONS

--- Closes an open custody (the caller holds its lock).
---   'transferred' follows the machine: only booked / held / remanded have that edge; from any other
---   state it is refused (invalid_state), never turned into a release. The property stays (prison).
---   opts.orderTakesOver: an incarceration order already took the citizen (orderCreated) while the
---   custody sits in a state without that edge (a field jail from 'arrested'): it closes on the
---   machine's 'released' edge with reason 'transferred' and none of a release's effects (cuffs
---   stay with the jail owner, no notice, the property is linked to the order).
---   Any other reason releases: cuffs off, a notice, the property comes back.
--- Every close ends the open bail offers of the custody.
function Custody.Close(row, reason, actor, data, opts)
    local to, releaseEffects = 'released', true
    if reason == 'transferred' then
        releaseEffects = false
        if K.can('custody', row.state, 'transferred') then
            to = 'transferred'
        elseif not (type(opts) == 'table' and opts.orderTakesOver) then
            return nil, K.err('invalid_state', ('A custody in %s cannot be transferred; book it or release it'):format(tostring(row.state)))
        end
    end
    local new, e = Custody.Move(row, to, { release_reason = reason, cell_id = K.NULL, hold_until = K.NULL }, actor,
        to == 'transferred' and 'transferred' or 'released', { reason = reason, from = row.state, detail = data })
    if not new then return nil, e end
    Custody.flagged[tonumber(row.id)] = nil
    if PFJustice.Bail and K.callable(PFJustice.Bail.ExpireFor) then PFJustice.Bail.ExpireFor('custody_id', tonumber(new.id), reason) end
    local src = K.srcOf(row.citizenid)
    if releaseEffects then
        if src and K.started('pfm-policejob') then
            pcall(function()
                if exports['pfm-policejob']:IsCuffed(src) then exports['pfm-policejob']:SetCuffed(src, false, 'custody_released') end
            end)
        end
        if PFJustice.Property and K.callable(PFJustice.Property.ReleaseForCustody) then
            PFJustice.Property.ReleaseForCustody(new.id, new.citizenid)
        end
        if src then K.notify(src, 'You were released from custody', 'success') end
    end
    return new
end

--- ReleaseFromCustody(custodyId, reason, opts)
function Custody.Release(custodyId, reason, opts)
    opts = type(opts) == 'table' and opts or {}
    if not RELEASE_REASONS[reason] then return K.err('bad_args', 'Unknown release reason') end
    local actor, actorErr = K.actor(opts)
    if not actor then return actorErr end
    if reason == 'court_order' then
        if not K.isCourt(actor) then return K.err('no_permission', 'Only a court orders this release') end
    elseif not K.isOfficer(actor) then
        -- medical staff only move a prisoner to and from hospital (TransferCustody / ReturnCustody)
        return K.roleError(actor)
    end
    local row, err = loadById(custodyId)
    if not row then return err end
    return K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if row.closed_at then
            if row.release_reason == reason then return { ok = true, duplicate = true } end
            return K.err('invalid_state', 'The custody is already closed')
        end
        if row.state == 'remanded' and reason ~= 'court_order' and reason ~= 'transferred' and reason ~= 'bailed'
            and actor.kind ~= 'system' and actor.kind ~= 'admin' then
            return K.err('invalid_state', 'A remanded citizen is released by the court')
        end
        local new, e = Custody.Close(row, reason, actor, { note = K.text(opts.note, 200) })
        if not new then return e end
        return { ok = true, custody = Custody.Public(new) }
    end)
end

--- IsInHoldingCell(src): held in a cell and standing in it (server position). The clock asks this
--- for orders served in holding (Config.Facilities.mrpd_holding.presence).
function Custody.IsInHoldingCell(src)
    src = tonumber(src)
    if not src then return false end
    local row = Custody.bySrc[src]
    if not row or row.state ~= 'held' or not row.cell_id then return false end
    local cell = Custody.Cell(row.facility, row.cell_id)
    if not cell then return false end
    return K.inZone(K.coords(src), cell)
end

-- ── reconnect, restart, events ───────────────────────────────────────────────────────────────────

local RETURN_STATES = { arrested = true, in_transport = true, booking = true, booked = true, held = true, remanded = true }

local function placeBack(src, row)
    local point
    if row.state == 'held' and row.cell_id then
        local cell = Custody.Cell(row.facility, row.cell_id)
        point = cell and cell.center
    end
    point = point or (K.cfg('Custody', 'ReturnPoint', {}) or {})[row.facility or '']
    if not point then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not K.callable(SetEntityCoords) then return false end
    return pcall(SetEntityCoords, ped, point.x + 0.0, point.y + 0.0, point.z + 0.0, false, false, false, false)
end

--- A player loaded in: an open custody puts them back at the facility and re-cuffs where needed.
function Custody.OnPlayerLoaded(src)
    src = tonumber(src)
    local P = src and K.player(src)
    if not P or not K.ready() then return nil end
    local cid = P.PlayerData.citizenid
    local row = Custody.Store.openOf(cid)
    if not row then forget(cid) return nil end
    Custody.bySrc[src], Custody.srcByCid[cid] = row, src
    if RETURN_STATES[row.state] then
        local placed = placeBack(src, row)
        local recuff = (K.cfg('Custody', 'ReCuffStates', { arrested = true, in_transport = true }) or {})[row.state] == true
        local cuffed = false
        if recuff and K.started('pfm-policejob') then
            local okc, res = pcall(function() return exports['pfm-policejob']:SetCuffed(src, true, 'custody') end)
            cuffed = okc and res == true
        end
        Custody.Log(row.id, 'reconnect', { state = row.state, placed = placed == true, cuffed = cuffed == true })
        K.notify(src, 'You are still in custody', 'error')
    end
    return row
end

function Custody.OnPlayerDropped(src)
    src = tonumber(src)
    local row = src and Custody.bySrc[src]
    if row then
        Custody.Log(row.id, 'disconnect', { state = row.state })
        Custody.srcByCid[row.citizenid] = nil
    end
    if src then Custody.bySrc[src] = nil end
end

--- Resource start: rebuild the memory map for everyone online (no teleport; they never left).
function Custody.LoadOnline()
    local ok, list = pcall(function() return exports['pfm-core']:GetCoreObject().Functions.GetPlayers() end)
    for _, src in ipairs(ok and type(list) == 'table' and list or {}) do
        local P = K.player(src)
        if P then
            local row = Custody.Store.openOf(P.PlayerData.citizenid)
            if row then Custody.bySrc[tonumber(src)], Custody.srcByCid[row.citizenid] = row, tonumber(src) end
        end
    end
end

--- Holds that ran past Config.Custody.MaxHoldSeconds are flagged once (log + officers told); a
--- person decides (release, bail, remand or a sentence). Nobody is released automatically.
function Custody.Tick(now)
    now = now or K.now()
    if not K.ready() then return 0 end
    local n = 0
    for _, row in ipairs(Custody.Store.dueHolds(now, 50)) do
        local id = tonumber(row.id)
        if not Custody.flagged[id] then
            Custody.flagged[id] = true
            Custody.Log(id, 'hold_expired', { since = tonumber(row.opened_at), holdUntil = tonumber(row.hold_until) })
            TriggerEvent('pf-justice:server:custodyHoldExpired', Custody.Public(row))
            local officer = row.officer_cid and K.srcOf(row.officer_cid)
            if officer then K.notify(officer, ('Custody #%d has been held past its limit: release, bail or charge'):format(id), 'error') end
            n = n + 1
        end
    end
    return n
end

--- An incarceration order started: a custody at another facility closes as transferred (its
--- property follows the order); one served at the same facility (a holding-cell jail) stays open.
function Custody.OnOrderCreated(order)
    if type(order) ~= 'table' then return end
    local kind = order.kind
    local S = PFJustice.States
    local incarceration = type(S) == 'table' and S.IncarcerationKinds and S.IncarcerationKinds[kind]
    if not incarceration then return end
    if order.state ~= 'active' and order.state ~= 'pending' then return end
    local cid = order.cid or order.citizenid
    if not K.validCid(cid) then return end
    if order.legacyRef or order.legacy_ref then return end
    local row = Custody.Store.openOf(cid)
    if not row then return end
    local orderId = tonumber(order.id or order.orderId)
    K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if not row or row.closed_at then return end
        if PFJustice.Property and K.callable(PFJustice.Property.LinkOrder) and orderId then
            PFJustice.Property.LinkOrder(row.id, orderId)
        end
        if order.facility and order.facility == row.facility then
            Custody.Log(row.id, 'order_started', { orderId = orderId, kind = kind, facility = order.facility })
            -- the sentence holds the citizen now: bail on the custody is over (bail on the order is a court's)
            if PFJustice.Bail and K.callable(PFJustice.Bail.ExpireFor) then PFJustice.Bail.ExpireFor('custody_id', tonumber(row.id), 'sentence started') end
            return
        end
        Custody.Close(row, 'transferred', { kind = 'system', label = 'order' }, { orderId = orderId, facility = order.facility },
            { orderTakesOver = true })
    end)
end

--- The newest log row of a kind (a dedicated query; the list scan is the fallback for older stores).
function Custody.LastLog(custodyId, kind)
    if K.callable(Custody.Store.lastLogOf) then return Custody.Store.lastLogOf(custodyId, kind) end
    for _, l in ipairs(Custody.Store.listLog(custodyId, 200)) do if l.kind == kind then return l end end
    return nil
end

--- The incarceration order an open custody is kept open for (a holding-cell jail), or nil.
function Custody.LinkedOrder(custodyId)
    local l = Custody.LastLog(custodyId, 'order_started')
    local d = l and K.decode(l.data)
    return type(d) == 'table' and tonumber(d.orderId) or nil
end

--- When the custody was remanded (unix seconds), or nil.
function Custody.RemandedAt(custodyId)
    local l = Custody.LastLog(custodyId, 'remanded')
    return l and tonumber(l.at) or nil
end

--- An order ended: a custody kept open for it (holding-cell jail) is released, sentence complete.
function Custody.OnReleaseOrdered(cid, orderId, reason)
    if not K.validCid(cid) then return end
    local row = Custody.Store.openOf(cid)
    if not row then return end
    local linked = Custody.LinkedOrder(row.id)
    if not linked or linked ~= tonumber(orderId) then return end
    K.withLock('custody:' .. row.id, function()
        row = Custody.Store.get(row.id)
        if row and not row.closed_at then
            Custody.Close(row, 'sentence_complete', { kind = 'system', label = 'order' }, { orderId = tonumber(orderId), why = reason })
        end
    end)
end

--- Character deleted: open custody closed (history kept for courts).
function Custody.OnCharacterDeleted(cid)
    if not K.validCid(cid) then return end
    for _, row in ipairs(Custody.Store.openAllOf(cid)) do
        Custody.Store.cas(row.id, row.state, { state = 'released', release_reason = 'char_deleted', closed_at = K.now(), updated_at = K.now() })
        Custody.Log(row.id, 'released', { reason = 'char_deleted' })
    end
    forget(cid)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = tonumber(type(player) == 'table' and player.PlayerData and player.PlayerData.source or player)
    if not src then return end
    local row = Custody.OnPlayerLoaded(src)
    if PFJustice.Property and K.callable(PFJustice.Property.OnPlayerLoaded) then PFJustice.Property.OnPlayerLoaded(src) end
    -- the spawn selector may move the ped after the load: place them again once it is done
    if row and RETURN_STATES[row.state] then
        SetTimeout(5000, function()
            local again = Custody.bySrc[src]
            if again and again.id == row.id and RETURN_STATES[again.state] then placeBack(src, again) end
        end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    Custody.OnPlayerDropped(src)
    K.forgetRate('bail:' .. tostring(src) .. ':')
end)

AddEventHandler('pf-justice:server:orderCreated', function(order)
    local ok, err = pcall(Custody.OnOrderCreated, order)
    if not ok then print(('^1[pf-justice]^7 custody orderCreated: %s'):format(tostring(err))) end
end)

AddEventHandler('pf-justice:server:releaseOrdered', function(cid, orderId, reason)
    local ok, err = pcall(Custody.OnReleaseOrdered, cid, orderId, reason)
    if not ok then print(('^1[pf-justice]^7 custody releaseOrdered: %s'):format(tostring(err))) end
    if PFJustice.Property and K.callable(PFJustice.Property.OnReleaseOrdered) then
        local ok2, err2 = pcall(PFJustice.Property.OnReleaseOrdered, cid, orderId, reason)
        if not ok2 then print(('^1[pf-justice]^7 property releaseOrdered: %s'):format(tostring(err2))) end
    end
end)

AddEventHandler('pfm-core:server:characterDeleted', function(cid)
    local src = tonumber(source)
    if src and src > 0 then return end
    pcall(Custody.OnCharacterDeleted, cid)
    if PFJustice.Property and K.callable(PFJustice.Property.OnCharacterDeleted) then pcall(PFJustice.Property.OnCharacterDeleted, cid) end
    if PFJustice.Bail and K.callable(PFJustice.Bail.OnCharacterDeleted) then pcall(PFJustice.Bail.OnCharacterDeleted, cid) end
    if PFJustice.Booking and K.callable(PFJustice.Booking.OnCharacterDeleted) then pcall(PFJustice.Booking.OnCharacterDeleted, cid) end
end)

CreateThread(function()
    local waited = 0
    while not K.ready() and waited < 120 do Wait(500) waited = waited + 1 end
    Custody.LoadOnline()
    while true do
        Wait(60000)
        local ok, err = pcall(Custody.Tick)
        if not ok then print(('^1[pf-justice]^7 custody tick: %s'):format(tostring(err))) end
    end
end)

-- ── exports ──────────────────────────────────────────────────────────────────────────────────────

K.export('OpenCustody', function(target, opts) return Custody.Open(target, opts) end)
K.export('GetCustody', function(who, opts) return Custody.Get(who, opts) end)
K.export('SetCustodyState', function(id, to, opts) return Custody.SetState(id, to, opts) end)
K.export('AssignHoldingCell', function(id, cellId, opts) return Custody.AssignCell(id, cellId, opts) end)
K.export('AddCustodyLog', function(id, kind, data, opts) return Custody.AddLog(id, kind, data, opts) end)
K.export('TransferCustody', function(id, to, opts) return Custody.Transfer(id, to, opts) end)
K.export('ReturnCustody', function(id, opts) return Custody.Return(id, opts) end)
K.export('ReleaseFromCustody', function(id, reason, opts) return Custody.Release(id, reason, opts) end)
K.export('IsInHoldingCell', function(src) return Custody.IsInHoldingCell(src) end, false)
