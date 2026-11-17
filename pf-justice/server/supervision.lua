-- pf-justice supervision: probation and parole (PF_ARCHITECTURE 4.7.8, unit 19B).
--
-- A probation or parole order (orders.lua) gets one supervision row (pf_justice_supervision, unique per
-- order) when it is created; the row follows the order's state (orderChanged), so the order stays the
-- truth for the term and the end date. Everything that happens under supervision is one row of
-- pf_justice_supervision_events:
--   appointment  scheduled by a probation officer (state scheduled -> attended | missed | cancelled), with a
--                pf-citizen calendar entry and mail for the citizen
--   checkin      the citizen reported in person inside a probation office zone (server position), or an
--                officer recorded a field visit standing next to them
--   violation    a REPORT for the supervising officer (state 'open'). It never changes custody or the order:
--                the configured legal process (an officer, then a court) decides what follows (owner rule)
--   note         monitor fitted / removed and other audit notes
-- Missed appointments and overdue check-ins are found by the sweep and become violation reports too.
--
-- Exports (Config.Callers at the boundary, then an actor check: probation officers are on-duty `doj` grade
-- 3+ or on-duty judges; on-duty police may report a violation they witnessed; admins by ACE):
--   GetSupervision(who)                         -> { ok, supervision?, list }
--   ScheduleAppointment(supId, spec, opts)      -> { ok, appointmentId, calendarId? }
--   RecordCheckIn(supId, opts)                  -> { ok, eventId, nextCheckinAt, appointmentId? }
--   RecordViolation(supId, spec, opts)          -> { ok, violationId, existing? }
--   SetMonitor(who, monitor, opts)              -> { ok, monitor }   (geofence in server/monitors.lua)
-- Server-only event: pf-justice:server:supervisionViolation(supervision, violation).
-- Player path: the /checkin command (Config.Supervision.CheckInCommand) checks the caller in at an office.
--
-- Keys: external writes need opts.key; it is stored in the event's detail and a repeat returns the first row
-- (looked up under the supervision lock, taken before the first database wait).

PFJustice = PFJustice or {}
PFJustice.Supervision = PFJustice.Supervision or {}
local J = PFJustice
local Sup = J.Supervision
local U = J.Util
local Err = J.Result.Err

-- ── config (Config.Supervision is 19A's block; every value has a default here) ──────────────────

local function cfg() return (Config and Config.Supervision) or {} end
local function C(key, default)
    local v = cfg()[key]
    if v == nil then return default end
    return v
end
Sup.C = C

local DEFAULT_OFFICER_JOBS = { doj = 3, judge = 0 }   -- doj grade 3 = probation officer, 4 = chief
local DEFAULT_REPORT_TYPES = { leo = true }
local DEFAULT_OFFICES = {
    { label = 'City Hall probation office', coords = vector3(-544.67, -204.25, 38.22), radius = 30.0 },
    { label = 'Sandy Shores probation desk', coords = vector3(1853.0, 3689.0, 34.3), radius = 25.0 },
    { label = 'Paleto Bay probation desk', coords = vector3(-448.0, 6012.0, 31.7), radius = 25.0 },
}
local VIOLATION_TYPES = {
    curfew = 'Curfew breach', no_go = 'Entered an exclusion zone', home_zone = 'Left the home zone',
    missed_checkin = 'Missed check-in', missed_appointment = 'Missed appointment', weapons = 'Weapon possession',
    alcohol = 'Alcohol use', new_offense = 'New offence', contact = 'Prohibited contact', monitor_tamper = 'Monitor tampering',
    other = 'Other',
}
Sup.VIOLATION_TYPES = VIOLATION_TYPES

-- Callers of the new exports; 19A's config may list its own (a listed entry wins).
local DEFAULT_CALLERS = {
    GetSupervision = '*',
    ScheduleAppointment = { ['pf-policemdt-DEV'] = true, ['pfm-adminmenu'] = true },
    RecordCheckIn = { ['pf-policemdt-DEV'] = true, ['pfm-adminmenu'] = true },
    RecordViolation = { ['pf-policemdt-DEV'] = true, ['pfm-policejob'] = true, ['pfm-adminmenu'] = true },
    SetMonitor = { ['pf-policemdt-DEV'] = true, ['pfm-adminmenu'] = true },
}
Config = Config or {}
Config.Callers = Config.Callers or {}
for name, rule in pairs(DEFAULT_CALLERS) do
    if Config.Callers[name] == nil then Config.Callers[name] = rule end
end

-- ── SQL ─────────────────────────────────────────────────────────────────────────────────────────

local SQL = J.SQL
SQL.supInsert = [[INSERT IGNORE INTO pf_justice_supervision (order_id, citizenid, officer_cid, state, monitor, next_checkin_at, created_at)
    VALUES (?, ?, NULL, ?, ?, ?, ?)]]
SQL.supById = 'SELECT * FROM pf_justice_supervision WHERE id = ?'
SQL.supByOrder = 'SELECT * FROM pf_justice_supervision WHERE order_id = ?'
SQL.supByCid = 'SELECT * FROM pf_justice_supervision WHERE citizenid = ? ORDER BY id DESC LIMIT 20'
SQL.supSetState = 'UPDATE pf_justice_supervision SET state = ?, ended_at = ? WHERE id = ? AND state = ?'
SQL.supSetOfficer = 'UPDATE pf_justice_supervision SET officer_cid = ? WHERE id = ? AND officer_cid IS NULL'
SQL.supSetMonitor = 'UPDATE pf_justice_supervision SET monitor = ? WHERE id = ?'
SQL.supSetNextCheckin = 'UPDATE pf_justice_supervision SET next_checkin_at = ? WHERE id = ? AND next_checkin_at <=> ?'
SQL.supDueCheckins = [[SELECT * FROM pf_justice_supervision WHERE state = 'active' AND next_checkin_at IS NOT NULL
    AND next_checkin_at <= ? ORDER BY id LIMIT 100]]
SQL.supMonitored = [[SELECT s.*, o.conditions AS order_conditions FROM pf_justice_supervision s
    JOIN pf_justice_orders o ON o.id = s.order_id WHERE s.state = 'active' AND s.monitor IS NOT NULL]]
SQL.supMissing = [[SELECT o.* FROM pf_justice_orders o LEFT JOIN pf_justice_supervision s ON s.order_id = o.id
    WHERE o.kind IN ('probation', 'parole') AND o.state IN ('pending', 'active', 'suspended') AND s.id IS NULL ORDER BY o.id LIMIT 200]]
SQL.supStale = [[SELECT s.id, s.order_id, s.state, o.state AS order_state FROM pf_justice_supervision s
    JOIN pf_justice_orders o ON o.id = s.order_id
    WHERE s.state IN ('pending', 'active', 'suspended') AND o.state <> s.state ORDER BY s.id LIMIT 200]]
SQL.supAnon = 'UPDATE pf_justice_supervision SET citizenid = ? WHERE citizenid = ?'
SQL.supHouseCoords = 'SELECT coords FROM houselocations WHERE name = ? LIMIT 1'
SQL.supEvInsert = [[INSERT INTO pf_justice_supervision_events (supervision_id, kind, due_at, done_at, state, detail, by_cid, at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)]]
SQL.supEvBySup = 'SELECT * FROM pf_justice_supervision_events WHERE supervision_id = ? ORDER BY id DESC LIMIT ?'
SQL.supEvByKey = [[SELECT * FROM pf_justice_supervision_events WHERE supervision_id = ? AND kind = ?
    AND JSON_VALUE(detail, '$.key') = ? ORDER BY id LIMIT 1]]
SQL.supEvRecent = [[SELECT id FROM pf_justice_supervision_events WHERE supervision_id = ? AND kind = 'violation'
    AND JSON_VALUE(detail, '$.type') = ? AND at >= ? ORDER BY id DESC LIMIT 1]]
SQL.supEvOpenAppts = [[SELECT * FROM pf_justice_supervision_events WHERE supervision_id = ? AND kind = 'appointment'
    AND state = 'scheduled' ORDER BY due_at, id]]
SQL.supEvDueAppts = [[SELECT * FROM pf_justice_supervision_events WHERE kind = 'appointment' AND state = 'scheduled'
    AND due_at <= ? ORDER BY id LIMIT 100]]
SQL.supEvSetState = 'UPDATE pf_justice_supervision_events SET state = ?, done_at = ? WHERE id = ? AND state = ?'
SQL.supEvSetDetail = 'UPDATE pf_justice_supervision_events SET detail = ? WHERE id = ?'
SQL.supEvCancelAppts = [[UPDATE pf_justice_supervision_events SET state = 'cancelled', done_at = ?
    WHERE supervision_id = ? AND kind = 'appointment' AND state = 'scheduled']]
SQL.supEvAnon = 'UPDATE pf_justice_supervision_events SET by_cid = ? WHERE by_cid = ?'

local NUMERIC = { 'id', 'order_id', 'next_checkin_at', 'created_at', 'ended_at', 'supervision_id', 'due_at', 'done_at', 'at' }

local function norm(row)
    if type(row) ~= 'table' then return nil end
    if row[1] ~= nil and row.id == nil then row = row[1] end
    if type(row) ~= 'table' or row.id == nil then return nil end
    local r = {}
    for k, v in pairs(row) do r[k] = v end
    for _, k in ipairs(NUMERIC) do r[k] = tonumber(row[k]) end
    return r
end

local function one(sql, params)
    local ok, row = pcall(MySQL.single.await, sql, params)
    if not ok then return nil, false end
    return norm(row), true
end

local function many(sql, params)
    local ok, rows = pcall(MySQL.query.await, sql, params)
    if not ok or type(rows) ~= 'table' then return nil end
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = norm(r) end
    return out
end

local function update(sql, params)
    local ok, res = pcall(MySQL.update.await, sql, params)
    return ok and U.Affected(res) or 0
end

local function insert(sql, params)
    local ok, id = pcall(MySQL.insert.await, sql, params)
    id = ok and tonumber(id) or nil
    if id and id > 0 then return id end
    return nil
end

Sup.One, Sup.Many = one, many

-- ── helpers ─────────────────────────────────────────────────────────────────────────────────────

local OPEN = { pending = true, active = true, suspended = true }
local TERMINAL = { completed = true, revoked = true, vacated = true }
Sup.OPEN = OPEN

function Sup.Usable()
    if not J.Ready() then return false end
    local S = J.Schema
    if S and U.Callable(S.Has) then return S.Has(4) == true end
    return true
end

local function notReady() return Err('db_unavailable', 'Supervision is not available yet (database)') end

local function internalCtx(ctx)
    local invoker = ctx and ctx.invoker
    return invoker == nil or invoker == J.RESOURCE
end

function Sup.IsOfficer(actor)
    if type(actor) ~= 'table' then return false end
    if actor.kind == 'admin' then return true end
    if actor.kind ~= 'player' or not actor.onduty then return false end
    local min = C('OfficerJobs', DEFAULT_OFFICER_JOBS)[actor.job or '']
    return min ~= nil and (actor.grade or 0) >= min
end

local function isReporter(actor)
    if Sup.IsOfficer(actor) then return true end
    return type(actor) == 'table' and actor.kind == 'player' and actor.onduty
        and C('ReportJobTypes', DEFAULT_REPORT_TYPES)[actor.jobType or ''] == true
end

--- The acting party of an export call: a resolved actor, or nil, err. Another resource must name a player
--- (or admin) actor; only pf-justice itself acts as the system.
local function resolveActor(opts, ctx)
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx and ctx.invoker)
    if not actor then return nil, aerr end
    if actor.kind == 'system' and not internalCtx(ctx) then
        return nil, Err('no_permission', 'A player actor is required')
    end
    if ctx and ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then
        return nil, Err('no_permission', 'An admin actor is required')
    end
    return actor
end

local function keyFor(opts, ctx)
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return nil, Err('bad_args', 'opts.key is invalid') end
    if key == nil and not internalCtx(ctx) then return nil, Err('bad_args', 'opts.key is required') end
    return key or false
end

local function supId(v) return U.Int(v, 1, 2147483647) end

function Sup.Row(id) return (one(SQL.supById, { id })) end

local function withSup(id, fn)
    return J.Locks.With('sup:' .. id, function()
        local row, okq = one(SQL.supById, { id })
        if not okq then return Err('db_unavailable', 'The justice database did not answer') end
        if not row then return Err('not_found', 'No such supervision') end
        return fn(row)
    end)
end
Sup.WithSup = withSup

local function encode(detail)
    local s = U.Encode(detail)
    if s and #s > 8000 then s = U.Encode({ truncated = true, key = detail.key, type = detail.type }) end
    return s
end

--- One supervision event row; returns its id or nil.
function Sup.AddEvent(id, kind, fields, actor)
    fields = fields or {}
    return insert(SQL.supEvInsert, { id, kind, fields.due_at, fields.done_at, fields.state, encode(fields.detail or {}),
        actor and actor.cid or nil, os.time() })
end

local function eventPublic(e)
    local d = U.Decode(e.detail) or {}
    d.key = nil
    return { id = e.id, kind = e.kind, state = e.state, dueAt = e.due_at, doneAt = e.done_at, at = e.at, byCid = e.by_cid, detail = d }
end
Sup.EventPublic = eventPublic

local function conditionsOf(order)
    if type(order) ~= 'table' then return {} end
    local c = order.conditions
    if type(c) == 'string' then c = U.Decode(c) end
    return type(c) == 'table' and c or {}
end
Sup.ConditionsOf = conditionsOf

local function findCondition(conditions, kind)
    for _, c in ipairs(conditions or {}) do
        if type(c) == 'table' and c.kind == kind then return c end
    end
    return nil
end
Sup.FindCondition = findCondition

local function checkinDays(conditions)
    local c = findCondition(conditions, 'checkin')
    local days = c and tonumber(c.everyDays)
    if not days or days ~= days or days <= 0 then return nil end
    return math.min(days, 90)
end

local function offices() return C('Offices', DEFAULT_OFFICES) end

--- The office zone a server position is in, or nil.
function Sup.OfficeAt(coords)
    if not coords then return nil end
    for i, o in ipairs(offices()) do
        local c = o.coords
        if c and U.Dist2D(coords, c) <= (tonumber(o.radius) or 25.0) then return i, o end
    end
    return nil
end

local function mailTo(cid, opts)
    if not cid or GetResourceState('pf-citizen') ~= 'started' then return nil end
    opts.sender = opts.sender or C('MailSender', 'Department of Justice - Probation')
    opts.senderType = opts.senderType or 'government'
    local ok, id = pcall(function() return exports['pf-citizen']:SendMail(cid, opts) end)
    return ok and id or nil
end
Sup.Mail = mailTo

local function srcOf(cid)
    local P = cid and J.GetPlayerByCid(cid)
    return P and P.PlayerData.source or nil
end
Sup.SrcOf = srcOf

-- ── zones, houses and monitor specs ─────────────────────────────────────────────────────────────

local function clampRadius(r)
    local maxR = tonumber((C('Monitor', {})).MaxRadius) or 500.0
    r = tonumber(r) or tonumber((C('Monitor', {})).DefaultRadius) or 50.0
    if r ~= r then r = 50.0 end
    return math.max(5.0, math.min(maxR, r))
end

--- A zone from a config name (Config.Supervision.Zones) or a { x, y, z?, radius? } table.
function Sup.ResolveZone(z)
    if type(z) == 'string' then
        local def = (C('Zones', {}))[z]
        local c = def and (def.center or def.coords)
        if not c then return nil end
        return { x = c.x, y = c.y, z = c.z, radius = clampRadius(def.radius), label = def.label or z, name = z }
    end
    if type(z) == 'table' then
        local x, y, zz = tonumber(z.x), tonumber(z.y), tonumber(z.z)
        if not x or not y or x ~= x or y ~= y or math.abs(x) > 20000 or math.abs(y) > 20000 then return nil end
        return { x = x, y = y, z = zz, radius = clampRadius(z.radius), label = U.Str(z.label, 64) }
    end
    return nil
end

--- A house the citizen owns (pfm-houses GetOwnedHouses), placed at its entrance (houselocations, read only;
--- the shell interior sits under the entrance, so a 2D radius covers both).
function Sup.ResolveHouse(cid, house)
    house = U.Str(house, 64)
    if not house then return nil, Err('bad_args', 'house is invalid') end
    local res = (C('Monitor', {})).HousesResource or 'pfm-houses'
    if GetResourceState(res) ~= 'started' then return nil, Err('unavailable', 'The housing resource is not running') end
    local ok, list = pcall(function() return exports[res]:GetOwnedHouses() end)
    if not ok or type(list) ~= 'table' then return nil, Err('unavailable', 'The housing resource is not ready') end
    local owned
    for _, h in ipairs(list) do
        if type(h) == 'table' and h.house == house and h.citizenid == cid then owned = h break end
    end
    if not owned then return nil, Err('bad_args', 'The citizen does not own that house') end
    local okq, row = pcall(MySQL.single.await, SQL.supHouseCoords, { house })
    if type(row) == 'table' and row[1] ~= nil and row.coords == nil then row = row[1] end
    local coords = okq and type(row) == 'table' and U.Decode(row.coords)
    local e = type(coords) == 'table' and coords.enter
    if type(e) ~= 'table' or not tonumber(e.x) or not tonumber(e.y) then
        return nil, Err('not_found', 'The house has no known location')
    end
    return { x = tonumber(e.x), y = tonumber(e.y), z = tonumber(e.z), house = house,
        radius = clampRadius((C('Monitor', {})).HouseRadius or 40.0), label = U.Str(owned.label, 64) or house }
end

--- Minutes since midnight from a number of hours (22, 6.5) or 'HH:MM'; nil when invalid.
function Sup.MinuteOfDay(v)
    if type(v) == 'number' then
        if v ~= v or v < 0 or v >= 24 then return nil end
        return math.floor(v * 60 + 0.5) % 1440
    end
    if type(v) == 'string' then
        local h, m = v:match('^(%d%d?):(%d%d)$')
        h, m = tonumber(h), tonumber(m)
        if h and m and h < 24 and m < 60 then return h * 60 + m end
    end
    return nil
end

local MODES = { home = true, curfew = true, track = true }

--- Validates and resolves a monitor spec { mode = 'home'|'curfew'|'track', house? | zone?, from?, to? } for a
--- citizen. The curfew window and home zone may come from the order's curfew condition. Returns the stored
--- monitor or nil, err.
function Sup.ResolveMonitor(cid, spec, conditions)
    if type(spec) ~= 'table' then return nil, Err('bad_args', 'monitor must be a table') end
    local mode = spec.mode or 'track'
    if not MODES[mode] then return nil, Err('bad_args', 'monitor.mode must be home, curfew or track') end
    local curfew = findCondition(conditions, 'curfew')
    local home, herr
    if spec.house ~= nil then
        home, herr = Sup.ResolveHouse(cid, spec.house)
        if not home then return nil, herr end
    elseif spec.zone ~= nil then
        home = Sup.ResolveZone(spec.zone)
        if not home then return nil, Err('bad_args', 'monitor.zone is unknown or invalid') end
    elseif curfew and curfew.zone ~= nil then
        home = Sup.ResolveZone(curfew.zone)
    end
    local out = { mode = mode, home = home }
    if mode == 'curfew' then
        local from = Sup.MinuteOfDay(spec.from ~= nil and spec.from or (curfew and curfew.from))
        local to = Sup.MinuteOfDay(spec.to ~= nil and spec.to or (curfew and curfew.to))
        if not from or not to or from == to then return nil, Err('bad_args', 'a curfew monitor needs from and to times') end
        out.from, out.to = from, to
    end
    if (mode == 'home' or mode == 'curfew') and not home then
        return nil, Err('bad_args', 'this monitor mode needs a home (house or zone)')
    end
    return out
end

-- ── public shape ────────────────────────────────────────────────────────────────────────────────

local function supPublic(row, order, full)
    local monitor = U.Decode(row.monitor)
    local out = {
        id = row.id, orderId = row.order_id, cid = row.citizenid, state = row.state, officerCid = row.officer_cid,
        nextCheckinAt = row.next_checkin_at, createdAt = row.created_at, endedAt = row.ended_at,
        monitored = monitor ~= nil, kind = order and order.kind or nil, endsAt = order and order.ends_at or nil,
        conditions = order and conditionsOf(order) or nil,
    }
    if monitor then
        out.monitor = full and monitor or { mode = monitor.mode }
    end
    return out
end
Sup.Public = supPublic

-- ── lifecycle: rows follow their orders ─────────────────────────────────────────────────────────

--- Creates the supervision row of a probation / parole order (idempotent: one row per order). `order` is the
--- public order (orderCreated) or a database row. Returns the row or nil.
function Sup.Ensure(order)
    if type(order) ~= 'table' or not Sup.Usable() then return nil end
    local orderId = tonumber(order.id)
    local cid = order.cid or order.citizenid
    local S = J.States
    if not orderId or not U.ValidCid(cid) or not (S.SupervisionKinds or {})[order.kind] then return nil end
    if not OPEN[order.state] then return nil end
    local existing = one(SQL.supByOrder, { orderId })
    if existing then return existing end
    local conditions = conditionsOf(order)
    local now = os.time()
    local every = checkinDays(conditions)
    local monitor, note
    local mc = findCondition(conditions, 'monitor')
    if mc then
        local m, merr = Sup.ResolveMonitor(cid, { mode = mc.mode or (findCondition(conditions, 'curfew') and 'curfew') or 'track',
            house = mc.house, zone = mc.zone }, conditions)
        if not m then
            -- the court ordered a monitor but its home could not be placed: track (no-go zones) until an
            -- officer sets the home with SetMonitor
            m, note = { mode = 'track' }, merr and merr.message
        end
        m.setAt, m.setBy = now, 'order'
        monitor = U.Encode(m)
    end
    insert(SQL.supInsert, { orderId, cid, order.state, monitor, every and (now + every * 86400) or nil, now })
    local row = one(SQL.supByOrder, { orderId })
    if not row then return nil end
    if row.created_at == now then
        if note then Sup.AddEvent(row.id, 'note', { detail = { action = 'monitor_home_unresolved', reason = note } }) end
        local label = order.kind == 'parole' and 'parole' or 'probation'
        local lines = { ('You are on %s (order #%d) until %s.'):format(label, orderId,
            os.date('%Y-%m-%d', tonumber(order.endsAt or order.ends_at) or now)) }
        if every then lines[#lines + 1] = ('Report in person at a probation office every %d day(s); first check-in due by %s.')
            :format(every, os.date('%Y-%m-%d %H:%M', now + every * 86400)) end
        if monitor then lines[#lines + 1] = 'You are fitted with an electronic monitor.' end
        mailTo(cid, { subject = ('Terms of your %s'):format(label), message = table.concat(lines, '\n'),
            ref = ('pf-justice:sup:%d:start'):format(row.id) })
        if monitor and J.Monitors then J.Monitors.Put(row, conditions) end
    end
    return row
end

--- Mirrors an order state on its supervision row. Ending cancels scheduled appointments and the monitor.
function Sup.Follow(row, to)
    if not row or row.state == to or not OPEN[row.state] then return false end
    local now = os.time()
    if update(SQL.supSetState, { to, TERMINAL[to] and now or nil, row.id, row.state }) ~= 1 then return false end
    row.state = to
    if TERMINAL[to] then
        update(SQL.supEvCancelAppts, { now, row.id })
        row.ended_at = now
    end
    if J.Monitors then
        if to == 'active' and row.monitor then
            local order = J.Orders and J.Orders.Row(row.order_id)
            J.Monitors.Put(row, conditionsOf(order))
        else
            J.Monitors.Remove(row.citizenid, row.id)
        end
    end
    return true
end

function Sup.OnOrderCreated(order)
    if type(order) ~= 'table' or not (J.States.SupervisionKinds or {})[order.kind] then return end
    Sup.Ensure(order)
end

function Sup.OnOrderChanged(order, change)
    if type(order) ~= 'table' or not (J.States.SupervisionKinds or {})[order.kind] then return end
    if type(change) == 'table' and change.action ~= nil and change.action ~= 'state' then return end
    if not Sup.Usable() then return end
    local orderId = tonumber(order.id)
    if not orderId then return end
    J.Locks.With('suporder:' .. orderId, function()
        local row = one(SQL.supByOrder, { orderId })
        if not row then
            Sup.Ensure(order)
            return { ok = true }
        end
        Sup.Follow(row, order.state)
        return { ok = true }
    end)
end

--- At start: rows for supervision orders that have none (created while this code was missing or the
--- database failed) and rows whose order changed state meanwhile.
function Sup.Reconcile()
    if not Sup.Usable() then return { created = 0, followed = 0 } end
    local out = { created = 0, followed = 0 }
    for _, o in ipairs(many(SQL.supMissing, {}) or {}) do
        local pub = J.Orders and J.Orders.Public and J.Orders.Public(J.Orders.Norm(o)) or o
        pub.cid = pub.cid or o.citizenid
        if Sup.Ensure(pub) then out.created = out.created + 1 end
    end
    for _, s in ipairs(many(SQL.supStale, {}) or {}) do
        local row = Sup.Row(s.id)
        if row and Sup.Follow(row, s.order_state) then out.followed = out.followed + 1 end
    end
    return out
end

-- ── reads ───────────────────────────────────────────────────────────────────────────────────────

local function fullReader(ctx)
    if internalCtx(ctx) then return true end
    local list = C('FullReaders', { ['pf-policemdt-DEV'] = true, ['pfm-adminmenu'] = true, ['pf-government'] = true })
    return list[ctx.invoker] == true
end

--- GetSupervision(who): the current (open, newest) supervision with its appointments, recent check-ins and,
--- for full readers, violation reports; plus a summary list of every supervision of the citizen.
function Sup.Get(who, ctx)
    if not Sup.Usable() then return notReady() end
    local cid = type(who) == 'number' and J.Who(who) or (U.ValidCid(who) and who) or nil
    if not cid then return Err('bad_args', 'Unknown player or citizen id') end
    local rows = many(SQL.supByCid, { cid })
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local full = fullReader(ctx or {})
    local list, current = {}, nil
    for _, r in ipairs(rows) do
        list[#list + 1] = { id = r.id, orderId = r.order_id, state = r.state, createdAt = r.created_at, endedAt = r.ended_at }
        if not current and OPEN[r.state] then current = r end
    end
    if not current then return { ok = true, list = list } end
    local order = J.Orders and J.Orders.Row(current.order_id)
    local pub = supPublic(current, order, full)
    pub.appointments, pub.checkins = {}, {}
    if full then pub.violations, pub.notes = {}, {} end
    for _, e in ipairs(many(SQL.supEvBySup, { current.id, 100 }) or {}) do
        local ev = eventPublic(e)
        if e.kind == 'appointment' then pub.appointments[#pub.appointments + 1] = ev
        elseif e.kind == 'checkin' then if #pub.checkins < 10 then pub.checkins[#pub.checkins + 1] = ev end
        elseif full and e.kind == 'violation' then pub.violations[#pub.violations + 1] = ev
        elseif full and e.kind == 'note' then pub.notes[#pub.notes + 1] = ev end
    end
    return { ok = true, supervision = pub, list = list }
end

-- ── appointments ────────────────────────────────────────────────────────────────────────────────

--- ScheduleAppointment(supId, spec, opts): spec = { at = unix seconds, office? = index of Config.Supervision.Offices,
--- minutes? = 15..240, note? }; opts = { actor = { src } (probation officer / judge / admin), key }.
function Sup.Schedule(id, spec, opts, ctx)
    if not Sup.Usable() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    id = supId(id)
    if not id or type(spec) ~= 'table' then return Err('bad_args', 'supId and spec are required') end
    local now = os.time()
    local lead = (tonumber(C('AppointmentMinLeadMinutes', 10)) or 10) * 60
    local ahead = (tonumber(C('AppointmentMaxDaysAhead', 60)) or 60) * 86400
    local at = U.Int(spec.at, now + lead, now + ahead)
    if not at then return Err('bad_args', 'at must be a time between the minimum lead and the maximum days ahead') end
    local minutes = spec.minutes ~= nil and U.Int(spec.minutes, 15, 240) or 30
    if not minutes then return Err('bad_args', 'minutes must be 15..240') end
    local officeIdx = spec.office ~= nil and U.Int(spec.office, 1, #offices()) or 1
    local office = officeIdx and offices()[officeIdx]
    if not office then return Err('bad_args', 'unknown office') end
    local note = U.Str(spec.note, C('MaxNoteLength', 500))
    local key, kerr = keyFor(opts, ctx)
    if key == nil then return kerr end
    local actor, aerr = resolveActor(opts, ctx)
    if not actor then return aerr end
    if actor.kind ~= 'system' and not Sup.IsOfficer(actor) then
        return Err('no_permission', 'Only an on-duty probation officer or judge can schedule appointments')
    end

    return withSup(id, function(row)
        if key then
            local prev, okq = one(SQL.supEvByKey, { id, 'appointment', key })
            if not okq then return Err('db_unavailable', 'The justice database did not answer') end
            if prev then return { ok = true, duplicate = true, appointmentId = prev.id } end
        end
        if row.state ~= 'active' then return Err('invalid_state', 'This supervision is not active') end
        local detail = { key = key or nil, office = officeIdx, location = office.label, minutes = minutes, note = note,
            by = J.Actor.Tag(actor) }
        local evId = Sup.AddEvent(id, 'appointment', { due_at = at, state = 'scheduled', detail = detail }, actor)
        if not evId then return Err('db_unavailable', 'The appointment could not be stored; nothing was changed') end
        -- the first probation officer who acts on an unassigned case becomes its supervising officer
        if actor.kind == 'player' and actor.job == 'doj' and not row.officer_cid then
            update(SQL.supSetOfficer, { actor.cid, id })
        end
        local calendarId
        if GetResourceState('pf-citizen') == 'started' then
            local ok, cal = pcall(function()
                return exports['pf-citizen']:AddCalendarEvent('personal', row.citizenid, {
                    title = 'Probation appointment', location = office.label, starts = at, ends = at + minutes * 60,
                    description = note or 'Report in person to your probation officer.',
                    remind = tonumber(C('CalendarRemindMinutes', 60)) or 60,
                }, 'Department of Justice')
            end)
            calendarId = ok and tonumber(cal) or nil
            if calendarId then
                detail.calendarId = calendarId
                update(SQL.supEvSetDetail, { encode(detail), evId })
            end
        end
        mailTo(row.citizenid, { subject = 'Probation appointment scheduled',
            message = ('You must report in person to %s on %s (%d minutes).%s'):format(office.label,
                os.date('%Y-%m-%d %H:%M', at), minutes, note and ('\n' .. note) or ''),
            ref = ('pf-justice:supappt:%d'):format(evId) })
        J.Audit.Write('supervision', id, 'appointment', { eventId = evId, at = at, office = officeIdx }, actor)
        return { ok = true, appointmentId = evId, calendarId = calendarId }
    end)
end

-- ── check-ins ───────────────────────────────────────────────────────────────────────────────────

--- RecordCheckIn(supId, opts): opts = { actor = { src } }. The actor is the supervised citizen standing in a
--- probation office zone, or a probation officer within OfficerDistance of the online citizen (a field visit)
--- or with the citizen in an office zone. Positions are read on the server.
function Sup.CheckIn(id, opts, ctx)
    if not Sup.Usable() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    id = supId(id)
    if not id then return Err('bad_args', 'supId is required') end
    local actor, aerr = resolveActor(opts, ctx)
    if not actor then return aerr end
    if actor.kind == 'system' then return Err('no_permission', 'A check-in needs a person') end
    if not J.Rate.Allow('supcheckin:' .. id .. ':' .. tostring(actor.cid), tonumber(C('CheckInCooldownSeconds', 300)) or 300) then
        return Err('rate_limited', 'You already checked in a moment ago')
    end

    return withSup(id, function(row)
        if row.state ~= 'active' then return Err('invalid_state', 'This supervision is not active') end
        local subjectSrc = srcOf(row.citizenid)
        if not subjectSrc then return Err('offline', 'The supervised citizen must be present') end
        local subjectPos = U.Coords(subjectSrc)
        local officeIdx, office = Sup.OfficeAt(subjectPos)
        local where
        if actor.cid == row.citizenid then
            if not office then return Err('too_far', 'Check in at a probation office') end
            where = 'office'
        elseif Sup.IsOfficer(actor) then
            if office then
                where = 'office'
            else
                local officerPos = actor.src and U.Coords(actor.src)
                local maxD = tonumber(C('OfficerDistance', 5.0)) or 5.0
                if not officerPos or not subjectPos or #(vector3(officerPos.x, officerPos.y, officerPos.z or 0)
                    - vector3(subjectPos.x, subjectPos.y, subjectPos.z or 0)) > maxD then
                    return Err('too_far', 'Stand next to the citizen or meet them at a probation office')
                end
                where = 'field'
            end
        else
            return Err('no_permission', 'Only the citizen or a probation officer can record a check-in')
        end
        local now = os.time()
        -- an appointment within its window counts as attended
        local window = (tonumber(C('AppointmentWindowMinutes', 60)) or 60) * 60
        local attended
        for _, a in ipairs(many(SQL.supEvOpenAppts, { id }) or {}) do
            if a.due_at and now >= a.due_at - window and now <= a.due_at + window then
                if update(SQL.supEvSetState, { 'attended', now, a.id, 'scheduled' }) == 1 then attended = a.id break end
            end
        end
        local evId = Sup.AddEvent(id, 'checkin', { done_at = now, state = 'ok', detail = { where = where,
            office = officeIdx, location = office and office.label or nil, appointment = attended, by = J.Actor.Tag(actor),
            x = subjectPos and math.floor(subjectPos.x) or nil, y = subjectPos and math.floor(subjectPos.y) or nil } }, actor)
        if not evId then return Err('db_unavailable', 'The check-in could not be stored') end
        local order = J.Orders and J.Orders.Row(row.order_id)
        local every = checkinDays(conditionsOf(order))
        local nextAt = row.next_checkin_at
        if every then
            nextAt = now + every * 86400
            update(SQL.supSetNextCheckin, { nextAt, id, row.next_checkin_at })
        end
        J.Notify(subjectSrc, nextAt and ('Check-in recorded. Next check-in due by %s'):format(os.date('%Y-%m-%d %H:%M', nextAt))
            or 'Check-in recorded', 'success')
        return { ok = true, eventId = evId, nextCheckinAt = nextAt, appointmentId = attended }
    end)
end

-- ── violations (reports, never custody) ─────────────────────────────────────────────────────────

local function notifyViolation(row, evId, vtype, note, source)
    local label = VIOLATION_TYPES[vtype] or vtype
    local msg = ('Supervision #%d (order #%d, citizen %s): %s reported by %s at %s.%s\nReview it and decide on the next step;'
        .. ' nothing has been done to the citizen automatically.'):format(row.id, row.order_id, row.citizenid, label, source,
        os.date('%Y-%m-%d %H:%M', os.time()), note and ('\n' .. note) or '')
    local mail = { subject = ('Violation report: %s'):format(label), message = msg, ref = ('pf-justice:supviol:%d'):format(evId) }
    if row.officer_cid then
        mailTo(row.officer_cid, mail)
        local src = srcOf(row.officer_cid)
        if src then J.Notify(src, ('Violation report for supervision #%d: %s'):format(row.id, label), 'error') end
    elseif GetResourceState('pf-citizen') == 'started' then
        -- no supervising officer yet: every DOJ member gets the report (also offline ones)
        mail.sender, mail.senderType = C('MailSender', 'Department of Justice - Probation'), 'government'
        pcall(function() return exports['pf-citizen']:SendMailToJob(C('ReportJob', 'doj'), mail, false) end)
    end
end

--- RecordViolation(supId, spec, opts): spec = { kind (VIOLATION_TYPES), note?, evidenceIds? }; opts = { actor, key }.
--- Internal callers (monitors, the sweep) pass opts.source and opts.repeatSeconds (skip when a report of the same
--- kind was written that recently, so a restart or a long breach does not flood the officer).
function Sup.Violation(id, spec, opts, ctx)
    if not Sup.Usable() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    id = supId(id)
    if not id or type(spec) ~= 'table' or not VIOLATION_TYPES[spec.kind] then return Err('bad_args', 'supId and a known spec.kind are required') end
    local note = U.Str(spec.note, C('MaxNoteLength', 500))
    local evidence
    if spec.evidenceIds ~= nil then
        if type(spec.evidenceIds) ~= 'table' or #spec.evidenceIds > 20 then return Err('bad_args', 'evidenceIds is invalid') end
        evidence = {}
        for i, v in ipairs(spec.evidenceIds) do
            evidence[i] = U.Int(v, 1, 2147483647)
            if not evidence[i] then return Err('bad_args', 'evidenceIds is invalid') end
        end
    end
    local key, kerr = keyFor(opts, ctx)
    if key == nil then return kerr end
    local actor, aerr = resolveActor(opts, ctx)
    if not actor then return aerr end
    if actor.kind ~= 'system' and not isReporter(actor) then
        return Err('no_permission', 'Only an on-duty officer can report a violation')
    end
    local internal = internalCtx(ctx)
    local source = internal and U.Str(opts.source, 16) or (actor.kind == 'system' and 'system' or 'officer')
    local repeatSeconds = internal and U.Int(opts.repeatSeconds, 1, 7 * 86400) or nil

    return withSup(id, function(row)
        if key then
            local prev, okq = one(SQL.supEvByKey, { id, 'violation', key })
            if not okq then return Err('db_unavailable', 'The justice database did not answer') end
            if prev then return { ok = true, duplicate = true, violationId = prev.id } end
        end
        if row.state ~= 'active' and row.state ~= 'suspended' then return Err('invalid_state', 'This supervision has ended') end
        local now = os.time()
        if repeatSeconds then
            local recent, okq = one(SQL.supEvRecent, { id, spec.kind, now - repeatSeconds })
            if not okq then return Err('db_unavailable', 'The justice database did not answer') end
            if recent then return { ok = true, existing = true, violationId = recent.id } end
        end
        local subjectSrc = srcOf(row.citizenid)
        local pos = subjectSrc and U.Coords(subjectSrc)
        local detail = { key = key or nil, type = spec.kind, label = VIOLATION_TYPES[spec.kind], note = note, evidenceIds = evidence,
            source = source, by = J.Actor.Tag(actor), zone = internal and U.Str(opts.zone, 64) or nil,
            x = pos and math.floor(pos.x) or nil, y = pos and math.floor(pos.y) or nil, z = pos and math.floor(pos.z or 0) or nil }
        local evId = Sup.AddEvent(id, 'violation', { state = 'open', detail = detail }, actor.kind ~= 'system' and actor or nil)
        if not evId then return Err('db_unavailable', 'The report could not be stored; nothing was changed') end
        J.Audit.Write('supervision', id, 'violation', { eventId = evId, type = spec.kind, source = source }, actor)
        notifyViolation(row, evId, spec.kind, note, source)
        local violation = { id = evId, kind = 'violation', state = 'open', at = now, type = spec.kind, source = source, note = note }
        J.Emit('supervisionViolation', supPublic(row, nil, true), violation)
        return { ok = true, violationId = evId }
    end)
end

-- ── monitors ────────────────────────────────────────────────────────────────────────────────────

--- SetMonitor(who, monitor, opts): fits (or with monitor = false / nil removes) the electronic monitor on the
--- citizen's active supervision. monitor = { mode = 'home' | 'curfew' | 'track', house? | zone?, from?, to? }.
function Sup.SetMonitor(who, monitor, opts, ctx)
    if not Sup.Usable() then return notReady() end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local cid = type(who) == 'number' and J.Who(who) or (U.ValidCid(who) and who) or nil
    if not cid then return Err('bad_args', 'Unknown player or citizen id') end
    if monitor ~= nil and monitor ~= false and type(monitor) ~= 'table' then return Err('bad_args', 'monitor must be a table or false') end
    local actor, aerr = resolveActor(opts, ctx)
    if not actor then return aerr end
    if actor.kind ~= 'system' and not Sup.IsOfficer(actor) then
        return Err('no_permission', 'Only an on-duty probation officer or judge can set a monitor')
    end
    local rows = many(SQL.supByCid, { cid })
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local target
    for _, r in ipairs(rows) do if r.state == 'active' then target = r break end end
    if not target then return Err('not_found', 'The citizen has no active supervision') end

    return withSup(target.id, function(row)
        if row.state ~= 'active' then return Err('invalid_state', 'This supervision is not active') end
        local order = J.Orders and J.Orders.Row(row.order_id)
        local conditions = conditionsOf(order)
        local stored
        if monitor then
            local m, merr = Sup.ResolveMonitor(cid, monitor, conditions)
            if not m then return merr end
            m.setAt, m.setBy = os.time(), J.Actor.Tag(actor)
            stored = m
        end
        local enc = stored and U.Encode(stored) or nil
        local okUpd = pcall(MySQL.update.await, SQL.supSetMonitor, { enc, row.id })
        if not okUpd then return Err('db_unavailable', 'The monitor could not be stored; nothing was changed') end
        row.monitor = enc
        Sup.AddEvent(row.id, 'note', { detail = { action = stored and 'monitor_set' or 'monitor_removed', mode = stored and stored.mode,
            home = stored and stored.home and (stored.home.label or stored.home.house) or nil, by = J.Actor.Tag(actor) } }, actor)
        if J.Monitors then
            if stored then J.Monitors.Put(row, conditions) else J.Monitors.Remove(row.citizenid, row.id) end
        end
        local src = srcOf(cid)
        if src then J.Notify(src, stored and 'An electronic monitor is now tracking you' or 'Your electronic monitor was removed', 'primary') end
        return { ok = true, monitor = stored or false }
    end)
end

-- ── sweep: missed appointments and overdue check-ins ────────────────────────────────────────────

--- Due appointments past their grace become 'missed' and a violation report; an overdue check-in becomes one
--- report per missed period and the next due date moves on. Returns counts.
function Sup.Sweep(now)
    now = now or os.time()
    local out = { missed = 0, checkins = 0 }
    if not Sup.Usable() then return out end
    local grace = (tonumber(C('AppointmentGraceMinutes', 30)) or 30) * 60
    for _, a in ipairs(many(SQL.supEvDueAppts, { now - grace }) or {}) do
        local row = Sup.Row(a.supervision_id)
        if row and row.state ~= 'active' then
            update(SQL.supEvSetState, { 'cancelled', now, a.id, 'scheduled' })
        elseif row and update(SQL.supEvSetState, { 'missed', now, a.id, 'scheduled' }) == 1 then
            out.missed = out.missed + 1
            Sup.Violation(row.id, { kind = 'missed_appointment', note = ('Did not attend the appointment of %s')
                :format(os.date('%Y-%m-%d %H:%M', a.due_at or now)) },
                { key = ('pf-justice:sup:%d:appt:%d:missed'):format(row.id, a.id), source = 'sweep' }, {})
        end
    end
    local ciGrace = (tonumber(C('CheckInGraceHours', 24)) or 24) * 3600
    for _, s in ipairs(many(SQL.supDueCheckins, { now - ciGrace }) or {}) do
        local order = J.Orders and J.Orders.Row(s.order_id)
        local every = checkinDays(conditionsOf(order))
        local due = s.next_checkin_at
        local nextAt
        if every then
            nextAt = due
            while nextAt + ciGrace <= now do nextAt = nextAt + every * 86400 end
        end
        -- move the due date first (compare-and-set), so a second server pass cannot report the same period
        if update(SQL.supSetNextCheckin, { nextAt, s.id, due }) == 1 then
            out.checkins = out.checkins + 1
            Sup.Violation(s.id, { kind = 'missed_checkin', note = ('No check-in by %s'):format(os.date('%Y-%m-%d %H:%M', due)) },
                { key = ('pf-justice:sup:%d:checkin:%d:missed'):format(s.id, due), source = 'sweep' }, {})
            local src = srcOf(s.citizenid)
            if src then J.Notify(src, 'You missed a probation check-in; your officer has been told', 'error') end
        end
    end
    return out
end

-- ── citizen path: /checkin ──────────────────────────────────────────────────────────────────────

--- The citizen checks in on every active supervision of theirs (normally one). Returns the results.
function Sup.SelfCheckIn(src)
    local P = J.GetPlayer(src)
    if not P then return {} end
    local res = Sup.Get(P.PlayerData.citizenid, {})
    local out = {}
    for _, s in ipairs(res.ok and res.list or {}) do
        if s.state == 'active' then out[#out + 1] = Sup.CheckIn(s.id, { actor = { src = src } }, {}) end
    end
    if #out == 0 then J.Notify(src, 'You are not under probation or parole supervision', 'error') end
    for _, r in ipairs(out) do
        if not r.ok then J.Notify(src, r.message or r.error, 'error') end
    end
    return out
end

do
    local name = C('CheckInCommand', 'checkin')
    if type(name) == 'string' and name ~= '' then
        RegisterCommand(name, function(src)
            src = tonumber(src)
            if not src or src <= 0 then return end
            Sup.SelfCheckIn(src)
        end, false)
    end
end

-- ── deleted characters ──────────────────────────────────────────────────────────────────────────

--- The character's orders end through orders.lua (and the rows follow them); the citizen id on supervision rows
--- and on events they wrote is replaced by a random token, like the order history.
function Sup.OnCharacterDeleted(cid)
    if not U.ValidCid(cid) or not Sup.Usable() then return end
    local token = ('anon-%08x%04x'):format(math.random(0, 0x7fffffff), math.random(0, 0xffff))
    for _, r in ipairs(many(SQL.supByCid, { cid }) or {}) do
        if J.Monitors then J.Monitors.Remove(cid, r.id) end
    end
    update(SQL.supAnon, { token, cid })
    update(SQL.supEvAnon, { token, cid })
end

-- ── events and threads ──────────────────────────────────────────────────────────────────────────

AddEventHandler('pf-justice:server:orderCreated', function(order)
    local ok, err = pcall(Sup.OnOrderCreated, order)
    if not ok then print(('^1[pf-justice]^7 supervision orderCreated: %s'):format(tostring(err))) end
end)

AddEventHandler('pf-justice:server:orderChanged', function(order, change)
    local ok, err = pcall(Sup.OnOrderChanged, order, change)
    if not ok then print(('^1[pf-justice]^7 supervision orderChanged: %s'):format(tostring(err))) end
end)

AddEventHandler('pfm-core:server:characterDeleted', function(cid)
    local src = tonumber(source)
    if src and src > 0 then return end
    pcall(Sup.OnCharacterDeleted, cid)
end)

CreateThread(function()
    local waited = 0
    while not Sup.Usable() and waited < 240 do Wait(500) waited = waited + 1 end
    local ok, err = pcall(Sup.Reconcile)
    if not ok then print(('^1[pf-justice]^7 supervision reconcile: %s'):format(tostring(err))) end
    while true do
        Wait((tonumber(C('SweepSeconds', 60)) or 60) * 1000)
        ok, err = pcall(Sup.Sweep, os.time())
        if not ok then print(('^1[pf-justice]^7 supervision sweep: %s'):format(tostring(err))) end
    end
end)

-- ── exports ─────────────────────────────────────────────────────────────────────────────────────

local function export(name, fn)
    exports(name, function(...)
        local allowed, res = J.Callers.Check(name, GetInvokingResource())
        if not allowed then return res end
        return fn({ invoker = res }, ...)
    end)
end

export('GetSupervision', function(ctx, who) return Sup.Get(who, ctx) end)
export('ScheduleAppointment', function(ctx, id, spec, opts) return Sup.Schedule(id, spec, opts, ctx) end)
export('RecordCheckIn', function(ctx, id, opts) return Sup.CheckIn(id, opts, ctx) end)
export('RecordViolation', function(ctx, id, spec, opts) return Sup.Violation(id, spec, opts, ctx) end)
export('SetMonitor', function(ctx, who, monitor, opts) return Sup.SetMonitor(who, monitor, opts, ctx) end)
