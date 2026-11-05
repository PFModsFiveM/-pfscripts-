-- pf-justice core: shared helpers for every server module of the resource (orders, clock, records,
-- custody, booking, property, bail). Nothing here touches the database except the audit writer.
--
--   PFJustice.Util     validation helpers (architecture 3.6), json, results
--   PFJustice.Callers  caller allowlist (GetInvokingResource against Config.Callers, architecture 3.4)
--   PFJustice.Actor    who acts: a player (re-read from pfm-core), an admin (ACE) or a server process
--   PFJustice.Audit    the generic audit table pf_justice_audit (order history is in pf_justice_order_events)
--   PFJustice.Locks    per-entity locks taken before the first database wait
--   PFJustice.Emit     server-only events 'pf-justice:server:<name>' (AddEventHandler only, never net)
--
-- The allowlist is checked at the export boundary only (server/api.lua and the 15C export files):
-- inside an event handler GetInvokingResource() names the resource that raised the event, so an
-- internal call must never check it again.

PFJustice = PFJustice or {}
local J = PFJustice

J.RESOURCE = GetCurrentResourceName()

do
    local ok, core = pcall(function() return exports['pfm-core']:GetCoreObject() end)
    J.QBCore = ok and core or nil
end

-- ── results ─────────────────────────────────────────────────────────────────────────────────────

J.Result = {}
function J.Result.Err(code, message)
    return { ok = false, error = code, message = message or code }
end
local Err = J.Result.Err

-- ── validation helpers (copied per architecture 3.6, not imported) ──────────────────────────────

J.Util = {}
local U = J.Util

--- A callable value (functions, FiveM function references, tables with __call). Never type(x) == 'function'.
function U.Callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

--- An integer in [min, max], or nil (NaN, infinity, fractions and out-of-range values are refused).
function U.Int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    if n % 1 ~= 0 then return nil end
    n = math.floor(n)
    if (min and n < min) or (max and n > max) then return nil end
    return n
end

--- A trimmed string without control characters, clipped to max; nil when empty (or not a string).
function U.Str(v, max)
    if type(v) == 'number' then v = tostring(v) end
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):match('^%s*(.-)%s*$')
    if v == '' then return nil end
    if max and #v > max then v = v:sub(1, max) end
    return v
end

function U.ValidCid(cid)
    return type(cid) == 'string' and #cid >= 1 and #cid <= 64 and cid:match('^[%w_%-]+$') ~= nil
end

--- Idempotency keys: 1..128 characters of [%w-_:.] (architecture 3.3).
function U.ValidKey(key)
    return type(key) == 'string' and #key >= 1 and #key <= 128 and key:match('^[%w%-_:%.]+$') ~= nil
end

--- A server id of a connected player, or nil.
function U.Src(v)
    local src = U.Int(v, 1, 65535)
    if not src then return nil end
    local ok, ped = pcall(GetPlayerPed, src)
    if not ok or not ped or ped == 0 then return nil end
    return src
end

function U.Encode(v)
    if v == nil then return nil end
    local ok, s = pcall(json.encode, v)
    return ok and s or nil
end

function U.Decode(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

--- Rows changed by an UPDATE (oxmysql returns a number; some drivers a table).
function U.Affected(res)
    if type(res) == 'number' then return res end
    if type(res) == 'table' then return tonumber(res.affectedRows) or 0 end
    return 0
end

--- Server-side position of a player (never a client value).
function U.Coords(src)
    local ok, c = pcall(function() return GetEntityCoords(GetPlayerPed(src)) end)
    if ok and c then return c end
    return nil
end

function U.Dist2D(a, b)
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function U.Now() return os.time() end

-- ── players ─────────────────────────────────────────────────────────────────────────────────────

--- The pfm-core player for a server id (a fresh snapshot each call).
function J.GetPlayer(src)
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(P) == 'table' and P.PlayerData then return P end
    return nil
end

function J.GetPlayerByCid(cid)
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayerByCitizenId(cid) end)
    if ok and type(P) == 'table' and P.PlayerData then return P end
    return nil
end

--- Resolves `who` (server id or citizenid) to cid, src (when online).
function J.Who(who)
    if type(who) == 'number' then
        local P = J.GetPlayer(who)
        if not P then return nil end
        return P.PlayerData.citizenid, P.PlayerData.source or who
    end
    if U.ValidCid(who) then
        local P = J.GetPlayerByCid(who)
        return who, P and P.PlayerData.source or nil
    end
    return nil
end

function J.Notify(src, text, kind)
    if src then TriggerClientEvent('QBCore:Notify', src, text, kind or 'primary') end
end

-- ── caller allowlist ────────────────────────────────────────────────────────────────────────────

J.Callers = {}
local warnedAt = {}

--- Whether `invoker` may call export `name`. nil (or this resource) always may.
function J.Callers.Allowed(name, invoker)
    if invoker == nil or invoker == '' or invoker == J.RESOURCE then return true end
    local rule = Config.Callers and Config.Callers[name]
    if rule == '*' then return true end
    return type(rule) == 'table' and rule[invoker] == true
end

--- The export-boundary check. Returns true, invoker; or false, { ok = false, error = 'not_allowed' }.
--- One console line per minute per refused resource.
function J.Callers.Check(name, invoker)
    if invoker == nil then invoker = GetInvokingResource() end
    if J.Callers.Allowed(name, invoker) then return true, invoker end
    local now = os.time()
    local tag = tostring(invoker) .. ':' .. tostring(name)
    if not warnedAt[tag] or now - warnedAt[tag] >= 60 then
        warnedAt[tag] = now
        print(('^3[pf-justice]^7 %s is not allowed to call %s (Config.Callers)'):format(tostring(invoker), tostring(name)))
    end
    return false, Err('not_allowed', 'This resource may not call ' .. tostring(name))
end

--- Keeps only the listed fields of `t` (rule = 'all' or a list of names).
function J.Callers.Filter(t, rule)
    if type(t) ~= 'table' or rule == 'all' then return t end
    local out = {}
    for _, k in ipairs(type(rule) == 'table' and rule or {}) do out[k] = t[k] end
    return out
end

--- The field rule of a config map ({ default = ..., [resource] = ... }) for an invoker.
function J.Callers.FieldRule(map, invoker)
    if invoker == nil or invoker == J.RESOURCE then return 'all' end
    map = map or {}
    return map[invoker] or map.default or {}
end

-- ── actor (architecture 3.5) ────────────────────────────────────────────────────────────────────

J.Actor = {}

function J.Actor.IsAdmin(src)
    for _, ace in ipairs(Config.AdminAces or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end

--- Resolves opts.actor. Never trusts job, grade, name or position from the caller: with a src they
--- are read from pfm-core. Returns actor = { kind = 'player'|'admin'|'system', src, cid, job,
--- jobType, grade, onduty, name, label, resource } or nil, err.
function J.Actor.Resolve(actor, invoker)
    local resource = invoker ~= nil and invoker ~= '' and invoker or J.RESOURCE
    if actor == nil then return { kind = 'system', label = resource, resource = resource } end
    if type(actor) ~= 'table' then return nil, Err('bad_args', 'actor must be a table') end
    if actor.src ~= nil then
        local src = U.Src(actor.src)
        local P = src and J.GetPlayer(src)
        if not P then return nil, Err('offline', 'The acting player is not online') end
        local pd = P.PlayerData
        local job = pd.job or {}
        local ci = pd.charinfo or {}
        local out = {
            kind = 'player', src = src, cid = pd.citizenid, job = job.name, jobType = job.type,
            grade = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade) or 0,
            onduty = job.onduty == true, resource = resource,
            name = U.Str(('%s %s'):format(tostring(ci.firstname or ''), tostring(ci.lastname or '')), 64),
        }
        if actor.kind == 'admin' then
            if not J.Actor.IsAdmin(src) then return nil, Err('no_permission', 'Admin permission required') end
            out.kind = 'admin'
        end
        out.label = out.cid
        return out
    end
    if actor.kind == 'admin' then return nil, Err('bad_args', 'an admin actor needs src') end
    return { kind = 'system', label = U.Str(actor.label, 48) or resource, resource = resource }
end

--- What is stored as created_by / actor_cid: the citizenid of a player, or the system label.
function J.Actor.Tag(a)
    if not a then return nil end
    return (a.cid or a.label or a.resource or 'system'):sub(1, 64)
end

-- ── locks ───────────────────────────────────────────────────────────────────────────────────────

J.Locks = {}
local held = {}

--- Takes lock `name`; false when someone holds it.
function J.Locks.Take(name)
    if held[name] then return false end
    held[name] = true
    return true
end

function J.Locks.Free(name) held[name] = nil end
function J.Locks.Held(name) return held[name] == true end

--- Runs fn while holding `name`; returns busy when it is held. fn's results are returned.
function J.Locks.With(name, fn)
    if not J.Locks.Take(name) then return Err('busy', 'Another action on this record is running; try again') end
    local results = table.pack(pcall(fn))
    J.Locks.Free(name)
    if not results[1] then
        print(('^1[pf-justice]^7 %s failed: %s'):format(tostring(name), tostring(results[2])))
        return Err('db_unavailable', 'The justice database did not answer; nothing was changed')
    end
    return table.unpack(results, 2, results.n)
end

-- ── rate limits (os.time based, per key) ────────────────────────────────────────────────────────

J.Rate = {}
local lastHit = {}

--- True when `key` may act now (at most once per `seconds`).
function J.Rate.Allow(key, seconds)
    local now = os.time()
    local last = lastHit[key]
    if last and now - last < seconds then return false end
    lastHit[key] = now
    return true
end

function J.Rate.Forget(prefix)
    for k in pairs(lastHit) do
        if k:sub(1, #prefix) == prefix then lastHit[k] = nil end
    end
end

-- ── server-only events ──────────────────────────────────────────────────────────────────────────

--- Raises 'pf-justice:server:<name>' for other resources (and 15C compat.lua) to AddEventHandler.
function J.Emit(name, ...)
    TriggerEvent('pf-justice:server:' .. name, ...)
end

-- ── audit (architecture 3.8) ────────────────────────────────────────────────────────────────────

J.Audit = {}
J.SQL = J.SQL or {}
J.SQL.insertAudit = [[INSERT INTO pf_justice_audit (entity, entity_id, action, actor_cid, actor_kind, actor_resource, detail, at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)]]
J.SQL.sweepAudit = 'DELETE FROM pf_justice_audit WHERE at < ? LIMIT 500'
J.SQL.sweepOrderEvents = 'DELETE FROM pf_justice_order_events WHERE at < ? LIMIT 500'

local function clipDetail(detail)
    local s = U.Encode(detail)
    if s and #s > 4096 then s = U.Encode({ truncated = true }) end
    return s
end
J.Audit.Detail = clipDetail

--- One audit row for a non-order entity (records, characters, custody helpers of 15C may use it too).
function J.Audit.Write(entity, entityId, action, detail, actor)
    local ok, err = pcall(MySQL.insert.await, J.SQL.insertAudit, {
        tostring(entity):sub(1, 24), tostring(entityId or ''):sub(1, 64), tostring(action):sub(1, 24),
        actor and J.Actor.Tag(actor) or nil, actor and actor.kind or nil, actor and actor.resource or nil,
        clipDetail(detail), os.time(),
    })
    if not ok then print(('^1[pf-justice]^7 audit %s %s failed: %s'):format(tostring(entity), tostring(action), tostring(err))) end
    return ok
end

--- Deletes audit and order-event rows older than the retention, at most 500 per table per pass.
function J.Audit.Sweep(now)
    local cutoff = (now or os.time()) - (Config.Audit.RetentionDays or 180) * 86400
    local n = 0
    for _, sql in ipairs({ J.SQL.sweepAudit, J.SQL.sweepOrderEvents }) do
        local ok, res = pcall(MySQL.update.await, sql, { cutoff })
        if ok then n = n + U.Affected(res) end
    end
    return n
end

-- ── lifecycle ───────────────────────────────────────────────────────────────────────────────────

J.ready = false

--- Runs the schema, warms the memory indexes and loads online players. Called once on start (and
--- by specs, since CreateThread does nothing there). Returns true when the database is usable.
function J.Boot()
    if not (J.Schema and J.Schema.Run()) then return false end
    if J.Orders and J.Orders.LoadIndex then J.Orders.LoadIndex() end
    if J.Orders and J.Orders.EnsureAccounts then J.Orders.EnsureAccounts() end
    if J.Records and J.Records.LoadQueue then J.Records.LoadQueue() end
    if J.Orders and J.Orders.LoadQueues then J.Orders.LoadQueues() end
    if J.Clock and J.Clock.LoadOnline then J.Clock.LoadOnline() end
    -- once a legacy jail runtime is handed over, import again at every start (idempotent): jails the old
    -- MDT/prison made after the v2 import step ran are taken over, and the hand-over reconcile runs
    J.ready = true
    -- (after ready: the reconcile's state changes go through Orders.SetState, which refuses until then)
    local live = (Config.Compat and Config.Compat.LegacyRuntimes) or {}
    if (live.mdt == false or live.prison == false) and J.LegacyImport and J.LegacyImport.Run then
        local ok, err = pcall(J.LegacyImport.Run)
        if not ok then print(('^1[pf-justice]^7 legacy import at start failed: %s'):format(tostring(err))) end
    end
    return true
end

function J.Ready() return J.ready == true end

CreateThread(function()
    Wait(1000) -- let pfm-core and the bank start their own migrations first
    -- orders are refused (db_unavailable) until the schema is applied; try again every 30 s
    while not J.Boot() do
        print('^1[pf-justice]^7 the database is not ready: orders are refused; retrying in 30 s')
        Wait(30000)
    end
    local tick = (Config.Clock.TickSeconds or 15) * 1000
    local sweepEvery = math.max(1, math.floor((Config.Clock.SweepSeconds or 60) / (Config.Clock.TickSeconds or 15)))
    local auditEvery = math.max(1, math.floor((Config.Audit.SweepSeconds or 86400) / (Config.Clock.TickSeconds or 15)))
    local n = 0
    while true do
        Wait(tick)
        n = n + 1
        local ok, err = pcall(J.Clock.Tick, os.time())
        if not ok then print(('^1[pf-justice]^7 clock tick failed: %s'):format(tostring(err))) end
        if next(J.Records.queue) ~= nil then pcall(J.Records.RetryQueued) end
        if J.Orders.HasQueued() then pcall(J.Orders.RetryQueued) end -- settlements / deletions that found a lock held
        if n % sweepEvery == 0 then
            ok, err = pcall(J.Orders.Sweep, os.time())
            if not ok then print(('^1[pf-justice]^7 order sweep failed: %s'):format(tostring(err))) end
        end
        if n % auditEvery == 0 then pcall(J.Audit.Sweep, os.time()) end
    end
end)
