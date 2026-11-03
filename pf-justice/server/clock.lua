-- pf-justice: the one sentence clock (PF_ARCHITECTURE 4.7.2). Owner decision D2: jail, prison and
-- remand count online time inside the facility; community-service deadlines, probation and parole
-- run in real time (those are swept by PFJustice.Orders.Sweep, not here).
--
-- Every Config.Clock.TickSeconds the clock looks at each online player with an active incarceration
-- order (memory only, one entry per inmate). If the facility's presence provider says the player is
-- inside (pfm-prison IsInside for Bolingbroke, IsInHoldingCell for station holding), the active order
-- and every concurrent order running beside it gain the elapsed seconds (at most MaxGapSeconds per
-- tick, so a server hitch is not time served). When the provider's resource is not running, or its
-- export fails, the facility's fallback radius around a centre is used instead, so the clock never
-- stops for that reason. A patient in hospital custody counts as inside.
--
-- Policies per order (column `clock`): online counts nothing offline; hybrid counts OfflineRate of the
-- offline wall time at the next load; realtime counts all of it (and counts online time outside too).
-- An order whose time runs out while the player is offline completes at the next load, so the
-- release ('pf-justice:server:releaseOrdered') always reaches an online player, exactly once.
--
-- Clock values are absolute (served_seconds, last_tick_at in unix seconds) and written to the order
-- row whenever they change, so a restart resumes from the database.

PFJustice = PFJustice or {}
PFJustice.Clock = PFJustice.Clock or {}
local J = PFJustice
local C = J.Clock
local U = J.Util

C.inmates = C.inmates or {}      -- [src] = { cid, rows = { open incarceration rows }, lastTick, lastMinute }
C.srcOf = C.srcOf or {}          -- [cid] = src
C.pendingLoad = C.pendingLoad or {} -- [src] = true: a load found the citizen busy; the next tick retries
C.hospital = C.hospital or {}    -- [cid] = true while the custody record says 'hospital' (set by 15C custody)

--- Whether the citizen is online and tracked by the clock (or online at all).
function C.IsOnline(cid)
    if C.srcOf[cid] then return true end
    return J.GetPlayerByCid(cid) ~= nil
end

--- The open incarceration rows the clock holds for an online citizen (nil when not tracked).
function C.Rows(cid)
    local src = C.srcOf[cid]
    local st = src and C.inmates[src]
    return st and st.rows or nil
end

--- 15C custody marks hospital custody here (TransferCustody kind 'hospital' / ReturnCustody).
function C.SetHospitalCustody(cid, on)
    if U.ValidCid(cid) then C.hospital[cid] = on and true or nil end
end

--- Hospital custody: flagged here, or the open custody record (15C memory) is in state 'hospital'.
function C.InHospitalCustody(src, cid)
    if C.hospital[cid] then return true end
    local open = J.Custody and type(J.Custody.bySrc) == 'table' and J.Custody.bySrc[src]
    return type(open) == 'table' and open.state == 'hospital'
end

local function activeOf(rows)
    for _, r in ipairs(rows or {}) do if r.state == 'active' then return r end end
end

-- ── presence ────────────────────────────────────────────────────────────────────────────────────

local function callProvider(presence, src)
    if presence.resource == J.RESOURCE then
        -- our own provider (15C custody): a module function, so no export round trip
        local fn = (J.Presence and J.Presence[presence.export]) or (J.Custody and J.Custody[presence.export])
        if not U.Callable(fn) then return nil end
        local ok, v = pcall(fn, src)
        if not ok then return nil end
        return v == true
    end
    if GetResourceState(presence.resource) ~= 'started' then return nil end
    local ok, v = pcall(function()
        local e = exports[presence.resource]
        return e[presence.export](e, src)
    end)
    if not ok then return nil end
    return v == true
end

--- Whether `src` counts as inside the facility of `row` right now, and how it was decided
--- ('provider', 'fallback', 'hospital', 'unknown_facility', 'outside').
function C.IsInside(src, row)
    local fac = Config.Facilities[row.facility or '']
    if not fac then return true, 'unknown_facility' end
    local inside, how
    if fac.presence and fac.presence.resource and fac.presence.export then
        inside = callProvider(fac.presence, src)
        if inside ~= nil then how = 'provider' end
    end
    if inside == nil and fac.fallback and fac.fallback.center then
        local c = U.Coords(src)
        inside = c ~= nil and U.Dist2D(c, fac.fallback.center) <= (fac.fallback.radius or 200.0)
        how = 'fallback'
    end
    if inside == nil then return true, 'no_provider' end
    if inside then return true, how end
    if Config.Clock.HospitalCountsAsInside and C.InHospitalCustody(src, row.citizenid) and GetResourceState('pf-ambulancejob') == 'started' then
        local ok, inCare = pcall(function() return exports['pf-ambulancejob']:IsInCare(src) end)
        if ok and inCare == true then return true, 'hospital' end
    end
    return false, 'outside'
end

-- ── persistence ─────────────────────────────────────────────────────────────────────────────────

-- Orders that count time now: the active one and concurrent ones already running beside it.
local function accruing(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if r.required_seconds and (r.state == 'active' or (r.state == 'pending' and r.starts_at and r.parent_order_id)) then
            out[#out + 1] = r
        end
    end
    return out
end

local function save(r, now)
    local rem = J.Orders.Remaining(r)
    local releaseAt = (r.clock == 'realtime' or r.clock == 'hybrid') and rem and (now + rem) or nil
    local ok, res = pcall(MySQL.update.await, J.SQL.saveClock, { r.served_seconds, now, releaseAt, now, r.id })
    if ok and U.Affected(res) == 1 then
        r.last_tick_at, r.release_at, r.updated_at = now, releaseAt, now
        return true
    end
    return false
end

-- ── tracking ────────────────────────────────────────────────────────────────────────────────────

--- The summary the inmate's client receives on a whole-minute change (sync model: owner only).
local function push(src, st, force)
    local head = activeOf(st.rows)
    local seconds = J.Orders.TimeToRelease(st.rows)
    local minutes = math.ceil(seconds / 60)
    if not force and minutes == st.lastMinute then return end
    st.lastMinute = minutes
    TriggerClientEvent('pf-justice:client:Sentence', src, {
        orderId = head and head.id or nil, kind = head and head.kind or nil, facility = head and head.facility or nil,
        state = head and head.state or (st.rows[1] and st.rows[1].state) or nil,
        remainingSeconds = seconds, minutes = minutes,
    })
end

local function track(src, cid, rows, now)
    if not rows or #rows == 0 then
        if C.inmates[src] then
            C.inmates[src] = nil
            TriggerClientEvent('pf-justice:client:Sentence', src, nil)
        end
        if C.srcOf[cid] == src then C.srcOf[cid] = nil end
        return nil
    end
    local st = C.inmates[src] or { lastTick = now }
    st.cid, st.rows = cid, rows
    C.inmates[src], C.srcOf[cid] = st, src
    push(src, st)
    return st
end

--- Re-reads the open incarceration rows of an online citizen without counting any time (after an
--- order was created or changed). Callers hold the cid lock or are on the clock's own path.
function C.Refresh(cid)
    local P = J.GetPlayerByCid(cid)
    local src = P and P.PlayerData.source or C.srcOf[cid]
    if not src or not P then
        if C.srcOf[cid] then C.inmates[C.srcOf[cid]] = nil C.srcOf[cid] = nil end
        return nil
    end
    local rows = J.Orders.OpenIncarceration(cid)
    if not rows then return C.inmates[src] end
    return track(src, cid, rows, os.time())
end

--- Forgets a citizen (character deleted).
function C.Forget(cid)
    local src = C.srcOf[cid]
    if src then C.inmates[src] = nil end
    C.srcOf[cid] = nil
    C.hospital[cid] = nil
end

--- A player loaded (or the resource started with them online): counts the offline time their
--- policy allows, finishes what ran out while they were away and starts tracking them.
--- Returns 'busy' when another action on the citizen holds the lock (the next tick retries).
function C.Load(src, now)
    now = now or os.time()
    local P = J.GetPlayer(src)
    if not P then return 'offline' end
    local cid = P.PlayerData.citizenid
    if not U.ValidCid(cid) then return 'offline' end
    if not J.Locks.Take('cid:' .. cid) then
        C.pendingLoad[src] = true
        return 'busy'
    end
    C.pendingLoad[src] = nil
    local ok, res = pcall(function()
        local rows = J.Orders.OpenIncarceration(cid)
        if not rows then
            C.pendingLoad[src] = true
            return 'db'
        end
        for _, r in ipairs(accruing(rows)) do
            local off = math.max(0, now - (r.last_tick_at or now))
            local gain = 0
            if r.clock == 'realtime' then gain = off
            elseif r.clock == 'hybrid' then gain = math.floor(off * (Config.Clock.OfflineRate or 0)) end
            r.served_seconds = (r.served_seconds or 0) + gain
            save(r, now)
        end
        C.srcOf[cid] = src
        J.Orders.Reindex(cid, rows)
        local head = activeOf(rows)
        if head and (J.Orders.Remaining(head) or 1) <= 0 then
            J.Orders.SettleLocked(cid, head.id, 'served', { kind = 'system', label = 'clock', resource = J.RESOURCE })
        end
        local st = track(src, cid, J.Orders.OpenIncarceration(cid) or rows, now)
        if st then
            st.lastTick = now
            push(src, st, true)
        end
        return st and 'tracked' or 'none'
    end)
    J.Locks.Free('cid:' .. cid)
    if not ok then
        print(('^1[pf-justice]^7 clock load of %s failed: %s'):format(tostring(cid), tostring(res)))
        C.pendingLoad[src] = true
        return 'error'
    end
    return res
end

--- A player left: their served time is already on the row; forget the memory entry.
function C.Unload(src)
    local st = C.inmates[src]
    C.pendingLoad[src] = nil
    if not st then return end
    -- hybrid / realtime orders count offline time from here, not from the last tick spent inside
    local now = os.time()
    for _, r in ipairs(accruing(st.rows)) do
        if r.clock ~= 'online' then save(r, now) end
    end
    if C.srcOf[st.cid] == src then C.srcOf[st.cid] = nil end
    C.inmates[src] = nil
end

--- Loads every online player (resource start).
function C.LoadOnline()
    local players = {}
    local ok, list = pcall(function() return J.QBCore.Functions.GetQBPlayers() end)
    if ok and type(list) == 'table' then
        for src in pairs(list) do players[#players + 1] = tonumber(src) end
    end
    for _, src in ipairs(players) do if src then C.Load(src) end end
    return #players
end

-- ── the tick ────────────────────────────────────────────────────────────────────────────────────

--- One inmate (the caller holds the cid lock).
function C.TickOne(src, st, now)
    local dt = math.max(0, math.min(now - (st.lastTick or now), Config.Clock.MaxGapSeconds or 60))
    st.lastTick = now
    local head = activeOf(st.rows)
    if not head or dt <= 0 then return 'idle' end
    local inside = C.IsInside(src, head)
    local counted = false
    for _, r in ipairs(accruing(st.rows)) do
        if inside or r.clock == 'realtime' then
            r.served_seconds = (r.served_seconds or 0) + dt
            save(r, now)
            counted = true
        end
    end
    if (J.Orders.Remaining(head) or 1) <= 0 then
        J.Orders.SettleLocked(st.cid, head.id, 'served', { kind = 'system', label = 'clock', resource = J.RESOURCE })
        local fresh = C.inmates[src]
        if fresh then push(src, fresh) end
        return 'settled'
    end
    push(src, st)
    return counted and 'counted' or 'outside'
end

--- One pass over the online inmates (every Config.Clock.TickSeconds; specs call it directly).
function C.Tick(now)
    now = now or os.time()
    for src in pairs(C.pendingLoad) do C.Load(src, now) end
    local list = {}
    for src, st in pairs(C.inmates) do list[#list + 1] = { src = src, st = st } end
    local counted = 0
    for _, e in ipairs(list) do
        local cid = e.st.cid
        if C.inmates[e.src] == e.st and J.Locks.Take('cid:' .. cid) then
            local ok, res = pcall(C.TickOne, e.src, e.st, now)
            J.Locks.Free('cid:' .. cid)
            if not ok then print(('^1[pf-justice]^7 clock tick of %s failed: %s'):format(tostring(cid), tostring(res)))
            elseif res == 'counted' or res == 'settled' then counted = counted + 1 end
        end
    end
    return counted
end

-- ── player lifecycle ────────────────────────────────────────────────────────────────────────────

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src = type(Player) == 'table' and Player.PlayerData and tonumber(Player.PlayerData.source)
    if not src or not J.Ready() then return end
    C.Load(src)
end)

-- 15C's legacy import wrote orders straight into the table (at a player's load or by its sync):
-- index them and start counting for an online player.
AddEventHandler('pf-justice:server:legacyImported', function(cid)
    local src = tonumber(source)
    if (src and src > 0) or not U.ValidCid(cid) then return end
    local res = J.Orders.WithCid(cid, function()
        J.Orders.Reindex(cid, J.Orders.OpenIncarceration(cid))
        C.Refresh(cid)
        return { ok = true }
    end)
    if type(res) == 'table' and res.error == 'busy' then
        local P = J.GetPlayerByCid(cid)
        if P then C.pendingLoad[P.PlayerData.source] = true end
    end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    src = tonumber(src) or tonumber(source)
    if src then C.Unload(src) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then
        C.Unload(src)
        J.Rate.Forget('pay:' .. src)
    end
end)
