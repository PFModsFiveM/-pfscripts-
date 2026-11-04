-- =====================================================
-- DEPARTMENTS: SHIFTS
-- =====================================================
-- One pf_gov_dept_shifts row per stretch a department employee spends on duty, kept in step with
-- pfm-core's duty flag. Nothing here trusts an event argument: every event only says "look at this
-- player again", and the live job (name, grade, onduty) decides.
--   * QBCore:Server:SetDuty (the duty toggle), QBCore:Server:OnJobUpdate (any job or duty change,
--     also on load), QBCore:Server:PlayerLoaded -> S.Sync(src);
--   * playerDropped / QBCore:Server:OnPlayerUnload -> the open shift closes as 'dropped';
--   * a job or grade change closes the shift as 'job_change' (and opens a new one when still on
--     duty in a department), going off duty closes it as 'duty_off';
--   * at start every shift left open closes as 'restart' (capped at MaxShiftHours after its start,
--     since the real end of a crashed session is unknown), then online employees are synced;
--   * owner decision D1: an incarcerated employee keeps the job but cannot be on duty. Going on
--     duty while pf-justice IsIncarcerated(cid) is true, or while an incarceration order is
--     'suspended' (escaped; GetActiveIncarceration), is undone at once (duty back off, shift closed
--     as 'incarcerated'); an order becoming active or suspended does the same (pf-justice events),
--     and S.Tick re-checks open shifts every minute (in memory) in case an event was missed.
-- The open shifts live in memory by server id (bounded by online players).

GovDept = GovDept or {}
local D = GovDept
local U = D.U
D.S = D.S or {}
local S = D.S

local function cfg() return D.Cfg() end

S.open = S.open or {}       -- [src] = { id, cid, dept, job, grade, startedAt }
S.closing = S.closing or {} -- [shiftId] = { reason, at }: closes the database did not take yet
local open, closing = S.open, S.closing
local syncing, pending, forcing = {}, {}, {}
S.syncing, S.pending = syncing, pending

local INCARCERATION = { jail = true, prison = true, remand = true }
local REASONS = { duty_off = true, dropped = true, job_change = true, incarcerated = true, restart = true }

function S.MaxShiftSeconds() return (U.int(cfg().MaxShiftHours or 16, 1, 168) or 16) * 3600 end

local function enabled() return cfg().Enabled ~= false end

-- an escaped inmate's order is 'suspended' (owner decision: escape suspends the order), which
-- IsIncarcerated does not count; for the duty refusal it counts like an active one
local HELD = { active = true, suspended = true }

--- True while `cid` serves or has escaped from an incarceration order. The in-memory
--- IsIncarcerated answers first; with `deep` (a shift is about to open) GetActiveIncarceration also
--- finds a suspended order (a pf-justice database read). False when pf-justice is not running or
--- does not answer, so honest employees are never locked out by a justice outage.
function S.Incarcerated(cid, deep)
    if not U.validCid(cid) or not U.started('pf-justice') then return false end
    local ok, res = pcall(function() return exports['pf-justice']:IsIncarcerated(cid) end)
    if ok and res == true then return true end
    if not deep then return false end
    local ok2, r = pcall(function() return exports['pf-justice']:GetActiveIncarceration(cid) end)
    if not ok2 or type(r) ~= 'table' or r.ok ~= true or type(r.order) ~= 'table' then return false end
    return INCARCERATION[r.order.kind] == true and HELD[r.order.state] == true
end

-- ── rows ────────────────────────────────────────────────────────────────

--- Ends the open shift of `src` in memory at once and in the database (retried by S.Tick on error).
function S.Close(src, reason)
    local cur = open[src]
    if not cur then return true end
    open[src] = nil
    reason = REASONS[reason] and reason or 'duty_off'
    local t = U.now()
    local ok, err = pcall(MySQL.update.await,
        'UPDATE pf_gov_dept_shifts SET ended_at = ?, end_reason = ? WHERE id = ? AND ended_at IS NULL', { t, reason, cur.id })
    if not ok then
        closing[cur.id] = { reason = reason, at = t }
        print('^1[PF-GOVERNMENT]^7 shift ' .. tostring(cur.id) .. ' not closed yet: ' .. tostring(err))
    end
    TriggerEvent('pf-government:server:shiftChanged', { id = cur.id, cid = cur.cid, dept = cur.dept, startedAt = cur.startedAt, endedAt = t, endReason = reason })
    return ok
end

function S.Open(src, m)
    if not U.dbReady() then return false end
    local t = U.now()
    for s, cur in pairs(open) do
        if cur.cid == m.cid and s ~= src then S.Close(s, 'dropped') end
    end
    -- a row a crashed session left open must not stay open beside the new one
    pcall(MySQL.update.await,
        "UPDATE pf_gov_dept_shifts SET ended_at = LEAST(?, started_at + ?), end_reason = 'restart' WHERE citizenid = ? AND ended_at IS NULL",
        { t, S.MaxShiftSeconds(), m.cid })
    local grade = math.max(0, math.min(127, m.grade or 0))
    local ok, id = pcall(MySQL.insert.await,
        'INSERT INTO pf_gov_dept_shifts (citizenid, dept, job, grade, started_at) VALUES (?, ?, ?, ?, ?)',
        { m.cid, m.dept, tostring(m.job):sub(1, 32), grade, t })
    id = ok and tonumber(id) or nil
    if not id then
        print('^1[PF-GOVERNMENT]^7 shift of ' .. tostring(m.cid) .. ' not opened: ' .. tostring(ok and 'no id' or id))
        return false
    end
    open[src] = { id = id, cid = m.cid, dept = m.dept, job = m.job, grade = grade, startedAt = t }
    TriggerEvent('pf-government:server:shiftChanged', { id = id, cid = m.cid, dept = m.dept, startedAt = t })
    return true
end

--- Brings the shift of `src` in line with the live job. `reason` forces the close reason.
function S.Reconcile(src, reason)
    local m = reason ~= 'dropped' and D.Member(src) or nil
    local want = m ~= nil and m.dept ~= nil and m.onDuty
    local cur = open[src]
    if cur then
        local same = m ~= nil and m.cid == cur.cid
        if not want or not same or m.job ~= cur.job or math.min(127, m.grade) ~= cur.grade then
            local why = reason
            if not why then
                if not same then why = 'dropped'
                elseif m.job ~= cur.job or math.min(127, m.grade) ~= cur.grade then why = 'job_change'
                else why = 'duty_off' end
            end
            S.Close(src, why)
            cur = nil
        end
    end
    if want and not cur then S.Open(src, m) end
end

-- ── duty enforcement (owner decision D1) ────────────────────────────────

local function forceOffDuty(src, m)
    local P = U.getPlayer(src)
    if not P or not P.Functions or not U.callable(P.Functions.SetJobDuty) then return false end
    P.Functions.SetJobDuty(false)
    TriggerClientEvent('QBCore:Client:SetDuty', src, false)
    TriggerClientEvent('QBCore:Notify', src, 'You cannot be on duty while incarcerated.', 'error')
    -- duty counts, MDT rosters and dispatch listen to this event
    TriggerEvent('QBCore:Server:SetDuty', src, false)
    return true
end

--- Re-reads `src` and records its shift. hint 'incarcerated': the caller knows an incarceration
--- order is active (pf-justice event); 'dropped': the player left.
function S.Sync(src, hint)
    src = U.int(src, 1, 65535)
    if not src or not enabled() then return end
    -- the duty events raised while forcing duty off come back here; this call records them below
    if forcing[src] then return end
    local forced = false
    if hint ~= 'dropped' and cfg().ForceOffDutyWhenIncarcerated ~= false then
        -- no database wait before this: duty is refused in the same tick it was taken
        local m = D.Member(src)
        local held = false
        if m and m.dept and m.onDuty then
            -- the database check (escaped, order suspended) only when duty is being taken, not on
            -- every tick of a running shift; pf-justice's order events cover changes after that
            held = hint == 'incarcerated' or S.Incarcerated(m.cid, open[src] == nil)
            -- that check may have waited on the database: look at the live duty again
            if held then m = D.Member(src) end
        end
        if held and m and m.dept and m.onDuty then
            forcing[src] = true
            local ok, res = pcall(forceOffDuty, src, m)
            forcing[src] = nil
            forced = ok and res == true
            if forced then
                D.Audit(m.dept, 'duty_forced_off', nil, m.cid, { reason = 'incarcerated', job = m.job, grade = m.grade })
            end
        end
    end
    local reason = (hint == 'dropped' and 'dropped') or (forced and 'incarcerated') or nil
    if syncing[src] then
        -- the running sync looks again when its database wait is over
        if reason or not pending[src] then pending[src] = reason or true end
        return
    end
    syncing[src] = true
    local ok, err = pcall(function()
        for _ = 1, 5 do
            pending[src] = nil
            S.Reconcile(src, reason)
            local again = pending[src]
            if not again then break end
            reason = again ~= true and again or nil
        end
    end)
    syncing[src], pending[src] = nil, nil
    if not ok then print('^1[PF-GOVERNMENT]^7 shift sync of ' .. tostring(src) .. ' failed: ' .. tostring(err)) end
end

function S.Drop(src)
    src = U.int(src, 1, 65535)
    if not src then return end
    local cur = open[src]
    if cur and D.Q then D.Q.Forget(cur.cid) end
    S.Sync(src, 'dropped')
end

--- A pf-justice order event: an active incarceration takes its citizen off duty.
function S.OnOrder(order)
    if type(order) ~= 'table' or not INCARCERATION[order.kind] or not U.validCid(order.cid) then return end
    local P = U.getPlayerByCid(order.cid)
    local src = P and P.PlayerData and P.PlayerData.source
    if not src then return end
    S.Sync(src, HELD[order.state] and 'incarcerated' or nil)
end

-- ── start and the minute tick ───────────────────────────────────────────

--- Closes every shift a previous run left open, then records online employees on duty.
function S.Start()
    if not enabled() then return false end
    if not U.dbReady() then return false end
    local ok, err = pcall(MySQL.update.await,
        "UPDATE pf_gov_dept_shifts SET ended_at = LEAST(?, started_at + ?), end_reason = 'restart' WHERE ended_at IS NULL",
        { U.now(), S.MaxShiftSeconds() })
    if not ok then
        print('^1[PF-GOVERNMENT]^7 open shifts not closed at start: ' .. tostring(err))
        return false
    end
    for k in pairs(open) do open[k] = nil end
    S.Tick()
    return true
end

local function onDutyEmployees()
    local out = {}
    if not QBCore or not QBCore.Functions or not U.callable(QBCore.Functions.GetPlayersByJob) then return out end
    local seen = {}
    for job in pairs(cfg().Jobs or {}) do
        local list = QBCore.Functions.GetPlayersByJob(job, true)
        for _, src in ipairs(type(list) == 'table' and list or {}) do
            if not seen[src] then seen[src] = true; out[#out + 1] = src end
        end
    end
    return out
end

--- Every minute: retries closes, re-checks every open shift (left, changed, incarcerated) and
--- opens shifts an event did not (an employee on duty with no row).
function S.Tick()
    if not enabled() then return end
    for id, c in pairs(closing) do
        local ok = pcall(MySQL.update.await,
            'UPDATE pf_gov_dept_shifts SET ended_at = ?, end_reason = ? WHERE id = ? AND ended_at IS NULL', { c.at, c.reason, id })
        if ok then closing[id] = nil end
    end
    local srcs = {}
    for src in pairs(open) do srcs[#srcs + 1] = src end
    for _, src in ipairs(onDutyEmployees()) do
        if not open[src] then srcs[#srcs + 1] = src end
    end
    for _, src in ipairs(srcs) do S.Sync(src) end
end

-- ── reads ───────────────────────────────────────────────────────────────

local function publicOpen(cur)
    return { id = cur.id, cid = cur.cid, dept = cur.dept, job = cur.job, grade = cur.grade, startedAt = cur.startedAt,
        seconds = math.max(0, U.now() - cur.startedAt) }
end

--- { ok, shift? = { id, dept, job, grade, startedAt, seconds } } for an online player.
function S.Get(src)
    src = U.int(src, 1, 65535)
    if not src then return U.fail('bad_args', 'Invalid player.') end
    local cur = open[src]
    return { ok = true, shift = cur and publicOpen(cur) or nil }
end

--- ListShifts(dept, filter): filter = { cid?, open?, since?, beforeId?, limit 1..100, viewer? }.
--- With `viewer` (a server id) the viewer must work for `dept`; a non-manager sees only their own.
function S.List(dept, filter)
    if not D.IsDept(dept) then return U.fail('bad_args', 'Unknown department.') end
    filter = type(filter) == 'table' and filter or {}
    local where, params = { 'dept = ?' }, { dept }
    local cid = filter.cid
    if cid ~= nil and not U.validCid(cid) then return U.fail('bad_args', 'Invalid citizen id.') end
    if filter.viewer ~= nil then
        local m = D.Member(filter.viewer)
        if not m then return U.fail('bad_args', 'Invalid viewer.') end
        if m.dept ~= dept then return U.fail('no_permission', 'You do not work for this department.') end
        if not m.manager then
            if cid ~= nil and cid ~= m.cid then return U.fail('no_permission', 'Only managers can see the shifts of others.') end
            cid = m.cid
        end
    end
    if cid then where[#where + 1] = 'citizenid = ?'; params[#params + 1] = cid end
    if filter.open == true then where[#where + 1] = 'ended_at IS NULL' end
    if filter.since ~= nil then
        local since = U.int(filter.since, 0, 4102444800)
        if not since then return U.fail('bad_args', 'Invalid since.') end
        where[#where + 1] = 'started_at >= ?'; params[#params + 1] = since
    end
    if filter.beforeId ~= nil then
        local before = U.int(filter.beforeId, 1, 2147483647)
        if not before then return U.fail('bad_args', 'Invalid cursor.') end
        where[#where + 1] = 'id < ?'; params[#params + 1] = before
    end
    local limit = 50
    if filter.limit ~= nil then
        limit = U.int(filter.limit, 1, 100)
        if not limit then return U.fail('bad_args', 'The limit must be 1 to 100.') end
    end
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local ok, rows = pcall(MySQL.query.await,
        'SELECT id, citizenid, dept, job, grade, started_at, ended_at, end_reason FROM pf_gov_dept_shifts WHERE '
            .. table.concat(where, ' AND ') .. ' ORDER BY id DESC LIMIT ' .. limit, params)
    if not ok or type(rows) ~= 'table' then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local t, list = U.now(), {}
    for _, r in ipairs(rows) do
        local started, ended = tonumber(r.started_at) or 0, tonumber(r.ended_at)
        list[#list + 1] = {
            id = tonumber(r.id), cid = r.citizenid, dept = r.dept, job = r.job, grade = tonumber(r.grade), startedAt = started,
            endedAt = ended, endReason = r.end_reason, seconds = math.max(0, (ended or t) - started),
        }
    end
    return { ok = true, list = list, nextCursor = (#list == limit and list[#list]) and list[#list].id or nil }
end

-- ── events ──────────────────────────────────────────────────────────────

-- Server-only events (AddEventHandler, never RegisterNetEvent); the arguments are only a hint.
AddEventHandler('QBCore:Server:SetDuty', function(src) S.Sync(src) end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src) S.Sync(src) end)
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src = type(Player) == 'table' and type(Player.PlayerData) == 'table' and Player.PlayerData.source
    if src then S.Sync(src) end
end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) S.Drop(src) end)
AddEventHandler('playerDropped', function() S.Drop(source) end)
AddEventHandler('pf-justice:server:orderCreated', function(order) S.OnOrder(order) end)
AddEventHandler('pf-justice:server:orderChanged', function(order) S.OnOrder(order) end)

CreateThread(function()
    Wait(5000)
    for _ = 1, 30 do
        if S.Start() or not enabled() then break end
        Wait(10000)
    end
    while true do
        Wait(60000)
        pcall(S.Tick)
    end
end)

-- ── exports ─────────────────────────────────────────────────────────────

exports('GetShift', function(src) return S.Get(src) end)

exports('ListShifts', function(dept, filter)
    local allowed = U.callerAllowed('ListShifts')
    if not allowed then return U.notAllowed() end
    return S.List(dept, filter)
end)
