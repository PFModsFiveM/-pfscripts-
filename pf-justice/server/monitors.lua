-- pf-justice electronic monitors (PF_ARCHITECTURE 4.7.8, unit 19B): a server-side geofence at 0.2 Hz for
-- monitored supervisions whose citizen is online. Positions come only from GetEntityCoords on the server.
--
-- What a monitor checks (stored on pf_justice_supervision.monitor by supervision.lua):
--   mode 'home'    house arrest: outside the home zone at any time        -> 'home_zone'
--   mode 'curfew'  outside the home zone between from and to (real time) -> 'curfew'
--   mode 'track'   position only
--   every mode     inside a no_go zone of the order's conditions          -> 'no_go'
-- A breach needs Monitor.BreachSamples consecutive samples (one sample can be a teleport or a bad read) and
-- opens one episode; the episode closes after Monitor.ClearSamples compliant samples. Each episode writes one
-- violation REPORT for the supervising officer through PFJustice.Supervision.Violation (repeat-guarded in the
-- database, so a restart in the middle of a breach does not report it again). A breach never changes custody
-- or the order: the officer and the court decide (owner rule).

PFJustice = PFJustice or {}
PFJustice.Monitors = PFJustice.Monitors or {}
local J = PFJustice
local Mon = J.Monitors
local U = J.Util

Mon.index = Mon.index or {}   -- [cid] = { supId, cid, monitor, noGo = { zones }, homeLabel }
Mon.breach = Mon.breach or {} -- [cid] = { [type] = { count, open, clear } }

local function M(key, default)
    local Sup = J.Supervision
    local m = Sup and Sup.C('Monitor', {}) or {}
    local v = m[key]
    if v == nil then return default end
    return v
end

--- Puts (or replaces) a monitored supervision row in the index. conditions = the order's conditions.
function Mon.Put(row, conditions)
    if type(row) ~= 'table' or not U.ValidCid(row.citizenid) then return false end
    local monitor = type(row.monitor) == 'table' and row.monitor or U.Decode(row.monitor)
    if type(monitor) ~= 'table' or row.state ~= 'active' then
        Mon.Remove(row.citizenid, row.id)
        return false
    end
    local Sup = J.Supervision
    local noGo = {}
    for _, c in ipairs(conditions or {}) do
        if type(c) == 'table' and c.kind == 'no_go' then
            local z = Sup.ResolveZone(c.zone)
            if z then noGo[#noGo + 1] = z end
        end
    end
    Mon.index[row.citizenid] = { supId = row.id, cid = row.citizenid, monitor = monitor, noGo = noGo }
    return true
end

--- Removes a citizen from the index (only the entry of supId when given).
function Mon.Remove(cid, supId)
    local e = cid and Mon.index[cid]
    if not e then return end
    if supId and e.supId ~= supId then return end
    Mon.index[cid] = nil
    Mon.breach[cid] = nil
end

--- Loads every active monitored supervision (at start).
function Mon.LoadIndex()
    local Sup = J.Supervision
    if not (Sup and Sup.Usable()) then return false end
    local rows = Sup.Many(J.SQL.supMonitored, {})
    if not rows then return false end
    Mon.index, Mon.breach = {}, {}
    for _, r in ipairs(rows) do Mon.Put(r, U.Decode(r.order_conditions) or {}) end
    return true
end

local function inside(pos, z)
    return U.Dist2D(pos, z) <= (tonumber(z.radius) or 50.0)
end

local function inWindow(minute, from, to)
    if from == nil or to == nil or from == to then return false end
    if from < to then return minute >= from and minute < to end
    return minute >= from or minute < to -- over midnight
end
Mon.InWindow = inWindow

--- The breaches of one sample: a list of { type, zone } (empty when compliant).
function Mon.Evaluate(entry, pos, now)
    local out = {}
    local m = entry.monitor or {}
    local home = m.home
    if m.mode == 'home' and home and not inside(pos, home) then
        out[#out + 1] = { type = 'home_zone', zone = home.label or home.house }
    elseif m.mode == 'curfew' and home then
        local t = os.date('*t', now)
        if inWindow(t.hour * 60 + t.min, m.from, m.to) and not inside(pos, home) then
            out[#out + 1] = { type = 'curfew', zone = home.label or home.house }
        end
    end
    for _, z in ipairs(entry.noGo or {}) do
        if inside(pos, z) then out[#out + 1] = { type = 'no_go', zone = z.label or z.name } break end
    end
    return out
end

local function report(entry, b, now)
    local Sup = J.Supervision
    local label = Sup.VIOLATION_TYPES[b.type] or b.type
    return Sup.Violation(entry.supId, { kind = b.type, note = ('Electronic monitor: %s%s'):format(label, b.zone and (' (' .. b.zone .. ')') or '') },
        { key = ('pf-justice:sup:%d:mon:%s:%d'):format(entry.supId, b.type, now), source = 'monitor', zone = b.zone,
          repeatSeconds = tonumber(M('RepeatSeconds', 1800)) or 1800 }, {})
end

--- One geofence pass over the online monitored citizens. Returns the number of reports written.
function Mon.Tick(now)
    now = now or os.time()
    local Sup = J.Supervision
    if not (Sup and Sup.Usable()) then return 0 end
    local need = tonumber(M('BreachSamples', 2)) or 2
    local clearNeed = tonumber(M('ClearSamples', 3)) or 3
    local reports = 0
    local list = {}
    for cid, e in pairs(Mon.index) do list[#list + 1] = { cid = cid, e = e } end
    for _, it in ipairs(list) do
        local cid, entry = it.cid, it.e
        local src = Sup.SrcOf(cid)
        local pos = src and U.Coords(src)
        if not pos then
            Mon.breach[cid] = nil -- offline: nothing is sampled, a new episode starts at the next login
        else
            local st = Mon.breach[cid] or {}
            Mon.breach[cid] = st
            local seen = {}
            for _, b in ipairs(Mon.Evaluate(entry, pos, now)) do
                seen[b.type] = true
                local s = st[b.type] or { count = 0, clear = 0 }
                st[b.type] = s
                s.count, s.clear = s.count + 1, 0
                if not s.open and s.count >= need then
                    s.open = true -- set before the write: the next tick never reports the same episode twice
                    local res = report(entry, b, now)
                    if type(res) == 'table' and res.ok then
                        if not res.existing then
                            reports = reports + 1
                            J.Notify(src, 'Your electronic monitor reported a breach to your officer', 'error')
                        end
                    else
                        s.open = false -- busy or database down: try again next sample
                    end
                end
            end
            for t, s in pairs(st) do
                if not seen[t] then
                    s.count = 0
                    if s.open then
                        s.clear = s.clear + 1
                        if s.clear >= clearNeed then st[t] = nil end
                    else
                        st[t] = nil
                    end
                end
            end
        end
    end
    return reports
end

CreateThread(function()
    local waited = 0
    while not (J.Supervision and J.Supervision.Usable()) and waited < 240 do Wait(500) waited = waited + 1 end
    pcall(Mon.LoadIndex)
    while true do
        -- 0.2 Hz (architecture 4.7.8 and the performance budget in section 8)
        Wait(math.max(1, tonumber(M('TickSeconds', 5)) or 5) * 1000)
        local ok, err = pcall(Mon.Tick, os.time())
        if not ok then print(('^1[pf-justice]^7 monitor tick failed: %s'):format(tostring(err))) end
    end
end)
