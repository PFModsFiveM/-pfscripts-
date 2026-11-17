-- pf-justice community service runtime (PF_ARCHITECTURE 4.7.9, state machine 5.8).
--
-- The order (kind 'community_service', units, due_at) is 15B's row in pf_justice_orders. This file runs
-- the work: shifts (pf_justice_cs_shifts) and tasks (pf_justice_cs_tasks, v5).
--
--   sign in    the citizen stands in a sign-in zone (Config.CommunityService.SignIn, server position)
--              and opens a shift for their earliest-due open order (assigned -> active on the first);
--   list       eligible GOV work orders near the citizen (pf-government ListWorkOrders csEligible);
--   claim      one unit (GOV ClaimWorkOrder, claimant kind 'cs') becomes one task;
--   steps      pf-justice:server:CsTaskStep(taskId, step): at the server-chosen point of the site
--              (shared/cs_tasks.lua Points), MinStepSeconds apart, on foot, with the kind's item rule;
--   report     every step done and on site without a break for the kind's minimum time (sampled at
--              1 Hz from server positions) -> GOV ReportWorkUnit(claimId, { src }, { key =
--              'pf-justice:cs:<taskId>' }); ONLY its { ok = true } marks the task done, and the
--              order's units_done is recomputed from the done tasks (a supervised shift's tasks count
--              Config.CommunityService.SupervisorBonus each);
--   supervise  an on-duty supervisor (SupervisorJobs + the GOV 'cs_supervisor' qualification) near the
--              citizen verifies their open shift (supervisor_cid); without one tasks still count;
--   overdue    15B's sweep moves an order past due_at to 'overdue'; CS.CourtTick files one court item
--              (FileCase kind 'violation', key 'pf-justice:cs:order:<id>:court'). Nothing here ever
--              creates an incarceration order: the court decides (state machine 5.8). An overdue order
--              can still be finished (overdue -> completed); the court item stays.
--
-- Persistence: shifts, tasks, steps and units are rows. A disconnect or restart keeps them: at the
-- next load the task is resumed (GOV ClaimWorkOrder returns the same claim, or a new one for the same
-- work order when the old one lapsed, and the task keeps its steps). Only the on-site stretch is
-- memory (it restarts on site, like GOV's own unit timer).
--
-- Net events (client -> server): CsSync, CsStartShift, CsEndShift, CsListWork, CsClaimTask,
-- CsTaskStep, CsCompleteTask, CsAbandonTask, CsVerifyShift (all 'pf-justice:server:<name>').
-- Client events: pf-justice:client:CsState(state | nil), pf-justice:client:CsWorkList(list).
-- Export: GetCommunityService(cid) -> { ok, orders = { { orderId, units, unitsDone, dueAt, state } } }.

PFJustice = PFJustice or {}
PFJustice.CS = PFJustice.CS or {}
local J = PFJustice
local CS = J.CS
local T = J.CSTasks
local U = J.Util
local Err = J.Result.Err

local SQL = J.SQL
SQL.csOpenOrders = [[SELECT * FROM pf_justice_orders WHERE citizenid = ? AND kind = 'community_service'
    AND state IN ('assigned', 'active', 'overdue') AND units_done < units ORDER BY due_at, id LIMIT 20]]
SQL.csOrdersOf = [[SELECT id, units, units_done, due_at, state FROM pf_justice_orders WHERE citizenid = ?
    AND kind = 'community_service' ORDER BY id DESC LIMIT 50]]
SQL.csOpenShift = 'SELECT * FROM pf_justice_cs_shifts WHERE citizenid = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1'
SQL.csShiftById = 'SELECT * FROM pf_justice_cs_shifts WHERE id = ?'
SQL.csInsertShift = 'INSERT INTO pf_justice_cs_shifts (order_id, citizenid, site, started_at) VALUES (?, ?, ?, ?)'
SQL.csEndShift = 'UPDATE pf_justice_cs_shifts SET ended_at = ? WHERE id = ? AND ended_at IS NULL'
SQL.csSupervise = 'UPDATE pf_justice_cs_shifts SET supervisor_cid = ? WHERE id = ? AND ended_at IS NULL AND supervisor_cid IS NULL'
SQL.csShiftUnits = 'UPDATE pf_justice_cs_shifts SET units = ? WHERE id = ?'
SQL.csStaleShifts = 'SELECT * FROM pf_justice_cs_shifts WHERE ended_at IS NULL AND started_at <= ? ORDER BY id LIMIT 50'
SQL.csActiveTask = [[SELECT * FROM pf_justice_cs_tasks WHERE shift_id = ? AND state = 'active' ORDER BY id DESC LIMIT 1]]
SQL.csTaskById = 'SELECT * FROM pf_justice_cs_tasks WHERE id = ?'
SQL.csInsertTask = [[INSERT INTO pf_justice_cs_tasks (shift_id, order_id, work_order_id, claim_id, kind, steps_done, steps_needed, state, started_at)
    VALUES (?, ?, ?, ?, ?, 0, ?, 'active', ?)]]
SQL.csStep = [[UPDATE pf_justice_cs_tasks SET steps_done = steps_done + 1 WHERE id = ? AND state = 'active' AND steps_done = ?
    AND steps_done < steps_needed]]
SQL.csTaskClaim = [[UPDATE pf_justice_cs_tasks SET claim_id = ? WHERE id = ? AND state = 'active']]
SQL.csTaskDone = [[UPDATE pf_justice_cs_tasks SET state = 'done', done_at = ? WHERE id = ? AND state = 'active']]
SQL.csTaskEnd = [[UPDATE pf_justice_cs_tasks SET state = ?, done_at = ?, reject_reason = ? WHERE id = ? AND state = 'active']]
SQL.csDoneWeights = [[SELECT t.shift_id, s.supervisor_cid FROM pf_justice_cs_tasks t JOIN pf_justice_cs_shifts s ON s.id = t.shift_id
    WHERE t.order_id = ? AND t.state = 'done']]
SQL.csSetUnitsDone = [[UPDATE pf_justice_orders SET units_done = ?, updated_at = ? WHERE id = ? AND kind = 'community_service'
    AND units_done = ?]]
-- overdue orders with no court item yet (the marker is the keyed 'cs_court' order event)
SQL.csOverdue = [[SELECT o.id FROM pf_justice_orders o WHERE o.kind = 'community_service' AND o.state = 'overdue'
    AND NOT EXISTS (SELECT 1 FROM pf_justice_order_events e WHERE e.idem_key = CONCAT('pf-justice:cs:order:', o.id, ':court'))
    ORDER BY o.id LIMIT 20]]

local OPEN = { assigned = true, active = true, overdue = true }

-- tasks being worked by an online player: [taskId] = { src, cid, taskId, shiftId, orderId, workOrderId,
-- claimId, kind, site = { x, y, z, r }, points, stepsDone, stepsNeeded, minSeconds, since, lastStepAt }
CS.live = CS.live or {}
CS.bySrc = CS.bySrc or {}   -- [src] = taskId
local warned = {}

-- ── helpers ─────────────────────────────────────────────────────────────────────────────────────

local NUM = { 'id', 'order_id', 'shift_id', 'work_order_id', 'claim_id', 'steps_done', 'steps_needed', 'started_at', 'ended_at',
    'done_at', 'units', 'units_done', 'due_at' }

local function norm(row)
    if type(row) ~= 'table' then return nil end
    if row[1] ~= nil and row.id == nil then row = row[1] end
    if type(row) ~= 'table' or row.id == nil then return nil end
    local r = {}
    for k, v in pairs(row) do r[k] = v end
    for _, k in ipairs(NUM) do if r[k] ~= nil then r[k] = tonumber(r[k]) end end
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
    for _, r in ipairs(rows) do out[#out + 1] = r end
    return out
end

local function update(sql, params)
    local ok, res = pcall(MySQL.update.await, sql, params)
    return ok and U.Affected(res) or 0
end

local function insert(sql, params)
    local ok, id = pcall(MySQL.insert.await, sql, params)
    id = ok and tonumber(id) or nil
    if id and id >= 1 then return id end
    return nil
end

local function cfg(key, default, min, max) return T.Num(key, default, min, max) end

--- The v5 tables are usable (19A's schema; a schema without Has() counts as ready once Boot ran).
function CS.Ready()
    if not J.Ready() then return false end
    if J.Schema and U.Callable(J.Schema.Has) then return J.Schema.Has(5) == true end
    return true
end

local function notReady() return Err('db_unavailable', 'Community service is not available right now') end

local function govStarted() return GetResourceState('pf-government') == 'started' end

--- A pf-government export call; never throws. Returns its result table or an error result.
local function gov(name, ...)
    if not govStarted() then return Err('not_found', 'City work orders are not available right now') end
    local args = table.pack(...)
    local ok, res = pcall(function() return exports['pf-government'][name](exports['pf-government'], table.unpack(args, 1, args.n)) end)
    if not ok or type(res) ~= 'table' then
        print(('^1[pf-justice]^7 pf-government %s failed: %s'):format(name, tostring(res)))
        return Err('db_unavailable', 'City work orders did not answer; nothing was changed')
    end
    return res
end

local function playerOf(src)
    local P = J.GetPlayer(src)
    return P, P and P.PlayerData.citizenid
end

local function inVehicle(src)
    local ok, veh = pcall(function() return GetVehiclePedIsIn(GetPlayerPed(src), false) end)
    return ok and veh ~= nil and veh ~= 0
end

local function dist2(a, b)
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function onSite(src, site)
    local pos = U.Coords(src)
    if not pos then return false, 'offline' end
    if inVehicle(src) then return false, 'vehicle' end
    if dist2(pos, site) > site.r + cfg('SiteTolerance', 2.0, 0, 10) or math.abs((pos.z or 0) - (site.z or 0)) > 15.0 then
        return false, 'too_far'
    end
    return true
end

local function actorOf(src)
    local a = J.Actor.Resolve({ src = src })
    return a or { kind = 'system', label = 'community service', resource = J.RESOURCE }
end
local SYSTEM = { kind = 'system', label = 'community service', resource = J.RESOURCE }

local function bonus() return cfg('SupervisorBonus', 1.0, 1.0, 2.0) end

-- ── rows ────────────────────────────────────────────────────────────────────────────────────────

function CS.OpenShift(cid) return one(SQL.csOpenShift, { cid }) end
function CS.OpenOrders(cid)
    local rows = many(SQL.csOpenOrders, { cid })
    if not rows then return nil end
    for i, r in ipairs(rows) do rows[i] = J.Orders.Norm(r) end
    return rows
end
function CS.Task(id) return (one(SQL.csTaskById, { id })) end

local function endShiftRow(shiftId, now)
    return update(SQL.csEndShift, { now, shiftId }) == 1
end

local function forgetLive(taskId)
    local e = CS.live[taskId]
    if e then
        if CS.bySrc[e.src] == taskId then CS.bySrc[e.src] = nil end
        CS.live[taskId] = nil
    end
end

--- Ends an active task row (released | expired | rejected) and gives its GOV claim back.
local function endTask(task, state, reason, now, release)
    local n = update(SQL.csTaskEnd, { state, now, tostring(reason or state):sub(1, 64), task.id })
    if release ~= false and task.claim_id then gov('ReleaseWorkClaim', task.claim_id, 'pf-justice ' .. state) end
    forgetLive(task.id)
    return n == 1
end

--- The live (memory) view of a task: points from the GOV site, step timing. order = GOV public order.
local function makeLive(src, cid, task, site, govMin)
    local kind = T.Kind(task.kind) or {}
    local e = CS.live[task.id] or {}
    e.src, e.cid, e.taskId, e.shiftId, e.orderId = src, cid, task.id, task.shift_id, task.order_id
    e.workOrderId, e.claimId, e.kind = task.work_order_id, task.claim_id, task.kind
    e.site = { x = tonumber(site.x) or 0, y = tonumber(site.y) or 0, z = tonumber(site.z) or 0, r = tonumber(site.r) or 10 }
    e.points = T.Points(task.id, e.site, task.steps_needed, kind.spread == true, cfg('MinStepDistance', 3.0, 0, 20))
    e.stepsDone, e.stepsNeeded = task.steps_done or 0, task.steps_needed
    e.minSeconds = math.max(tonumber(kind.minSeconds) or 60, tonumber(govMin) or 0)
    CS.live[task.id] = e
    CS.bySrc[src] = task.id
    return e
end

-- ── units ───────────────────────────────────────────────────────────────────────────────────────

--- Recomputes the shifts' units and the order's units_done from its done tasks (each one a GOV
--- ReportWorkUnit success). Called only right after such a success, so no unit is ever counted
--- without one. Caller holds the order's cid lock. Returns the new units_done.
function CS.RecomputeLocked(row, now)
    local rows = many(SQL.csDoneWeights, { row.id })
    if not rows then return row.units_done end
    local b, perShift, total = bonus(), {}, 0
    for _, r in ipairs(rows) do
        local w = (r.supervisor_cid ~= nil and r.supervisor_cid ~= '') and b or 1
        local sid = tonumber(r.shift_id)
        perShift[sid] = (perShift[sid] or 0) + w
        total = total + w
    end
    for sid, units in pairs(perShift) do update(SQL.csShiftUnits, { math.floor(units * 100 + 0.5) / 100, sid }) end
    local done = math.min(row.units or 0, math.floor(total + 1e-6))
    if done > (row.units_done or 0) then
        if update(SQL.csSetUnitsDone, { done, now, row.id, row.units_done or 0 }) == 1 then
            local before = row.units_done
            row.units_done, row.updated_at = done, now
            J.Emit('orderChanged', J.Orders.Public(row), { action = 'cs_units', from = before, to = done })
        end
    end
    return row.units_done
end

--- Opens a shift for the earliest-due open order of cid. Caller holds the cid lock.
local function openShiftLocked(cid, site, actor, now)
    local orders = CS.OpenOrders(cid)
    if not orders then return nil, Err('db_unavailable', 'The justice database did not answer') end
    local row = orders[1]
    if not row then return nil, Err('not_found', 'You have no open community service order') end
    local shiftId = insert(SQL.csInsertShift, { row.id, cid, site, now })
    if not shiftId then return nil, Err('db_unavailable', 'The shift could not be stored; nothing was changed') end
    if row.state == 'assigned' then J.Orders.MoveLocked(row, 'active', 'first shift', actor) end
    J.Orders.Event(row.id, 'cs_shift', { shiftId = shiftId, site = site }, actor)
    return { id = shiftId, order_id = row.id, citizenid = cid, site = site, started_at = now }, row
end

--- The order reached its units: completed (assigned/active/overdue -> completed), open shifts end, and
--- a citizen with another open order keeps working on it (a new shift, same sign-in).
local function completeLocked(row, shift, actor, now)
    if row.state == 'assigned' then J.Orders.MoveLocked(row, 'active', 'first shift', actor) end
    local ok = J.Orders.MoveLocked(row, 'completed', 'units done', actor)
    if shift then endShiftRow(shift.id, now) end
    if ok and shift then openShiftLocked(row.citizenid, shift.site, actor, now) end
    return ok
end

-- ── actions (each returns a result table; the net handlers below call them) ─────────────────────

--- Signs in at a sign-in zone (server position). A citizen with an open shift gets it back.
function CS.StartShift(src, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local P, cid = playerOf(src)
    if not P then return Err('offline', 'Player not found') end
    local pos = U.Coords(src)
    local point
    for _, p in ipairs(T.SignIns()) do
        local c = p.coords
        if pos and c and dist2(pos, c) <= (tonumber(p.radius) or 10.0) and math.abs((pos.z or 0) - (c.z or 0)) <= 10.0 then point = p break end
    end
    if not point then return Err('too_far', 'Sign in at a community service desk') end
    if J.Orders.IsIncarcerated and J.Orders.IsIncarcerated(cid) then return Err('invalid_state', 'You are in custody') end
    local actor = actorOf(src)
    return J.Orders.WithCid(cid, function()
        local shift, okq = CS.OpenShift(cid)
        if not okq then return Err('db_unavailable', 'The justice database did not answer') end
        if shift then return { ok = true, duplicate = true, shiftId = shift.id, orderId = shift.order_id } end
        local s, err = openShiftLocked(cid, tostring(point.id or 'desk'):sub(1, 32), actor, now)
        if not s then return err end
        return { ok = true, shiftId = s.id, orderId = s.order_id }
    end)
end

--- Signs out (anywhere). An active task gives its claim back; units already done stay.
function CS.EndShift(src, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local P, cid = playerOf(src)
    if not P then return Err('offline', 'Player not found') end
    return J.Orders.WithCid(cid, function()
        local shift = CS.OpenShift(cid)
        if not shift then return Err('not_found', 'You are not signed in') end
        local task = one(SQL.csActiveTask, { shift.id })
        if task then endTask(task, 'released', 'signed_out', now) end
        endShiftRow(shift.id, now)
        return { ok = true, shiftId = shift.id }
    end)
end

--- Eligible GOV work orders near the citizen's server position (needs an open shift).
function CS.ListWork(src)
    if not CS.Ready() then return notReady() end
    local P, cid = playerOf(src)
    if not P then return Err('offline', 'Player not found') end
    local shift, okq = CS.OpenShift(cid)
    if not okq then return Err('db_unavailable', 'The justice database did not answer') end
    if not shift then return Err('invalid_state', 'Sign in at a community service desk first') end
    local pos = U.Coords(src)
    if not pos then return Err('offline', 'Player not found') end
    local res = gov('ListWorkOrders', { csEligible = true, status = 'open', limit = 20,
        near = { x = pos.x, y = pos.y, z = pos.z, r = cfg('NearRadius', 1500.0, 50, 2000) } })
    if not res.ok then return res end
    local out = {}
    for _, o in ipairs(res.list or {}) do
        local kind = T.Kind(o.kind)
        if kind and (tonumber(o.unitsOpen) or 0) > 0 and o.csEligible ~= false then
            out[#out + 1] = {
                id = tonumber(o.id), kind = o.kind, label = kind.label, district = U.Str(o.districtLabel or o.district, 60),
                site = U.Str(o.site and o.site.label, 60), distance = math.floor((tonumber(o.distance) or 0) + 0.5),
                unitsOpen = tonumber(o.unitsOpen) or 0, steps = kind.steps,
            }
        end
    end
    return { ok = true, list = out }
end

--- Claims one unit of a GOV work order as a task of the open shift.
function CS.Claim(src, workOrderId, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local woId = U.Int(workOrderId, 1, 2147483647)
    if not woId then return Err('bad_args', 'Invalid work order') end
    local P, cid = playerOf(src)
    if not P then return Err('offline', 'Player not found') end
    return J.Orders.WithCid(cid, function()
        local shift, okq = CS.OpenShift(cid)
        if not okq then return Err('db_unavailable', 'The justice database did not answer') end
        if not shift then return Err('invalid_state', 'Sign in at a community service desk first') end
        local row = J.Orders.Row(shift.order_id)
        if not row or not OPEN[row.state] or (row.units_done or 0) >= (row.units or 0) then
            endShiftRow(shift.id, now)
            return Err('invalid_state', 'This community service order is closed')
        end
        local open = one(SQL.csActiveTask, { shift.id })
        if open then return Err('conflict', 'Finish or abandon your current task first') end
        local wo = gov('GetWorkOrder', woId)
        if not wo.ok then return wo end
        local order = wo.order or {}
        local kind = T.Kind(order.kind)
        if not kind or order.csEligible == false then return Err('invalid_state', 'This work is not open to community service') end
        local claim = gov('ClaimWorkOrder', woId, { kind = 'cs', cid = cid, ref = ('pf-justice:cs:shift:%d'):format(shift.id) })
        if not claim.ok then return claim end
        local claimId = U.Int(claim.claimId, 1, 2147483647)
        if not claimId then return Err('db_unavailable', 'City work orders did not answer; nothing was changed') end
        local taskId = insert(SQL.csInsertTask, { shift.id, row.id, woId, claimId, order.kind, kind.steps, now })
        if not taskId then
            gov('ReleaseWorkClaim', claimId, 'pf-justice could not store the task')
            return Err('db_unavailable', 'The task could not be stored; nothing was changed')
        end
        local task = { id = taskId, shift_id = shift.id, order_id = row.id, work_order_id = woId, claim_id = claimId,
            kind = order.kind, steps_done = 0, steps_needed = kind.steps }
        makeLive(src, cid, task, claim.site or order.site or {}, claim.minSeconds or order.minSeconds)
        J.Orders.Event(row.id, 'cs_task', { taskId = taskId, workOrderId = woId, claimId = claimId, kind = order.kind }, actorOf(src))
        return { ok = true, taskId = taskId }
    end)
end

--- Resumes the citizen's open shift and task after a load, reconnect or restart. The task keeps its
--- steps: GOV gives the same claim back, or a new claim on the same work order when the old one
--- lapsed. A task whose work order is gone ends 'expired' (nothing counted).
function CS.Resume(src, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local P, cid = playerOf(src)
    if not P then return Err('offline', 'Player not found') end
    return J.Orders.WithCid(cid, function()
        local shift, okq = CS.OpenShift(cid)
        if not okq then return Err('db_unavailable', 'The justice database did not answer') end
        if not shift then return { ok = true } end
        local row = J.Orders.Row(shift.order_id)
        local task = one(SQL.csActiveTask, { shift.id })
        local stale = now - (shift.started_at or now) > cfg('ShiftMaxHours', 4, 0.25, 48) * 3600
        if stale or not row or not OPEN[row.state] then
            if task then endTask(task, 'released', stale and 'shift_ended' or 'order_closed', now) end
            endShiftRow(shift.id, now)
            return { ok = true, ended = true }
        end
        if not task then return { ok = true, shiftId = shift.id } end
        local live = CS.live[task.id]
        if live and live.src == src and live.claimId == task.claim_id then return { ok = true, shiftId = shift.id, taskId = task.id } end
        local claim = gov('ClaimWorkOrder', task.work_order_id, { kind = 'cs', cid = cid, ref = ('pf-justice:cs:shift:%d'):format(shift.id) })
        if not claim.ok then
            if claim.error == 'db_unavailable' or claim.error == 'busy' or claim.error == 'not_found' and not govStarted() then
                return claim -- try again later; the task and its steps stay
            end
            endTask(task, 'expired', claim.error or 'claim_lost', now, false)
            return { ok = true, shiftId = shift.id, expired = task.id }
        end
        local claimId = U.Int(claim.claimId, 1, 2147483647)
        if claimId and claimId ~= task.claim_id then
            update(SQL.csTaskClaim, { claimId, task.id })
            task.claim_id = claimId
        end
        makeLive(src, cid, task, claim.site or {}, claim.minSeconds)
        return { ok = true, shiftId = shift.id, taskId = task.id }
    end)
end

--- The live entry of the player's task, resuming it from the database when memory lost it.
local function liveFor(src, taskId, now)
    local id = U.Int(taskId, 1, 2147483647)
    if not id then return nil, Err('bad_args', 'Invalid task') end
    local e = CS.live[id]
    if not e or e.src ~= src then
        CS.Resume(src, now)
        e = CS.live[id]
    end
    local _, cid = playerOf(src)
    if not e or e.src ~= src or e.cid ~= cid then return nil, Err('not_found', 'No such task') end
    return e
end

--- One interaction step of a task (validated on the server).
function CS.Step(src, taskId, step, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local e, err = liveFor(src, taskId, now)
    if not e then return err end
    return J.Locks.With('cstask:' .. e.taskId, function()
        local n = U.Int(step, 1, 50)
        if not n or n ~= e.stepsDone + 1 then
            return Err('invalid_state', 'That step is not the next one', nil)
        end
        if e.stepsDone >= e.stepsNeeded then return Err('invalid_state', 'Every step is done; finish the task') end
        local wait = cfg('MinStepSeconds', 20, 1, 600)
        if e.lastStepAt and now - e.lastStepAt < wait then
            local r = Err('rate_limited', ('Keep working: %d seconds'):format(wait - (now - e.lastStepAt)))
            r.remaining = wait - (now - e.lastStepAt)
            return r
        end
        if inVehicle(src) then return Err('invalid_state', 'Get out of the vehicle to work') end
        local pos = U.Coords(src)
        local point = e.points[n]
        if not pos or not point or dist2(pos, point) > cfg('StepReach', 3.0, 1.0, 10.0)
            or math.abs((pos.z or 0) - (point.z or 0)) > 15.0 then
            return Err('too_far', 'Go to the marked spot')
        end
        local items = T.Items(e.kind)
        if items.tool then
            local ok, has = pcall(function() return exports['pfm-inventory']:HasItem(src, items.tool, 1) end)
            if not ok or not has then return Err('no_permission', 'You need the right tool for this work') end
        end
        if items.consume then
            local ok, removed = pcall(function() return exports['pfm-inventory']:RemoveItem(src, items.consume, 1, nil, 'community service') end)
            if not ok or not removed then return Err('no_permission', 'You need supplies for this work') end
        end
        if update(SQL.csStep, { e.taskId, e.stepsDone }) ~= 1 then
            -- the row moved on (a stale memory copy): read it again
            local t = CS.Task(e.taskId)
            if t then e.stepsDone = t.steps_done or e.stepsDone end
            return Err('busy', 'The task changed meanwhile; try again')
        end
        e.stepsDone, e.lastStepAt = e.stepsDone + 1, now
        return { ok = true, stepsDone = e.stepsDone, stepsNeeded = e.stepsNeeded }
    end)
end

--- Reports the task's unit to GOV and counts it on the order only when GOV says ok.
function CS.Complete(src, taskId, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local e, err = liveFor(src, taskId, now)
    if not e then return err end
    return J.Locks.With('cstask:' .. e.taskId, function()
        return J.Orders.WithOrder(e.orderId, function(row)
            local task = CS.Task(e.taskId)
            if not task then return Err('not_found', 'No such task') end
            if task.state == 'done' then return { ok = true, duplicate = true, unitsDone = row.units_done, units = row.units } end
            if task.state ~= 'active' then forgetLive(task.id) return Err('invalid_state', 'This task is ' .. tostring(task.state)) end
            local shift = one(SQL.csShiftById, { task.shift_id })
            if not OPEN[row.state] then
                endTask(task, 'rejected', 'order_closed', now)
                if shift then endShiftRow(shift.id, now) end
                return Err('invalid_state', 'This community service order is closed')
            end
            if (task.steps_done or 0) < (task.steps_needed or 0) then return Err('invalid_state', 'Finish every step first') end
            local okSite, why = onSite(src, e.site)
            if not okSite then
                if why == 'vehicle' then return Err('invalid_state', 'Get out of the vehicle to work') end
                return Err('too_far', 'You are not at the work site')
            end
            local worked = e.since and (now - e.since) or 0
            if worked < e.minSeconds then
                local r = Err('too_soon', ('Keep working: %d seconds left'):format(e.minSeconds - worked))
                r.remaining = e.minSeconds - worked
                return r
            end
            local res = gov('ReportWorkUnit', task.claim_id, { src = src }, { key = ('pf-justice:cs:%d'):format(task.id) })
            if res.ok ~= true then
                if res.error == 'invalid_state' or (res.error == 'not_found' and govStarted()) then
                    -- the claim lapsed or was settled: ask for the same work again, keep the steps
                    local claim = gov('ClaimWorkOrder', task.work_order_id, { kind = 'cs', cid = e.cid, ref = ('pf-justice:cs:shift:%d'):format(task.shift_id) })
                    local claimId = claim.ok and U.Int(claim.claimId, 1, 2147483647)
                    -- the same claim is still ours: GOV refused this report for another reason (kept)
                    if claimId == task.claim_id then return res end
                    if claimId then
                        update(SQL.csTaskClaim, { claimId, task.id })
                        e.claimId = claimId
                        local r = Err('invalid_state', 'Your work claim lapsed and was renewed: keep working on site')
                        r.renewed = true
                        return r
                    end
                    if claim.error == 'db_unavailable' or claim.error == 'busy' then return claim end
                    endTask(task, 'expired', res.error, now, false)
                    return Err('invalid_state', 'This work is no longer available; nothing was counted')
                end
                return res -- too_soon, too_far, busy, db_unavailable...: the task stays, nothing counted
            end
            -- GOV counted the unit (or had counted it under this key): the task is done
            if update(SQL.csTaskDone, { now, task.id }) ~= 1 then
                return { ok = true, duplicate = true, unitsDone = row.units_done, units = row.units }
            end
            forgetLive(task.id)
            local actor = actorOf(src)
            J.Orders.Event(row.id, 'cs_unit', { taskId = task.id, workOrderId = task.work_order_id, claimId = task.claim_id,
                supervised = shift and shift.supervisor_cid ~= nil or false }, actor, ('pf-justice:cs:%d:unit'):format(task.id))
            local done = CS.RecomputeLocked(row, now)
            local completed = false
            if done >= (row.units or 0) then completed = completeLocked(row, shift, actor, now) end
            return { ok = true, unitsDone = done, units = row.units, completed = completed, govCompleted = res.completed == true }
        end)
    end)
end

--- Gives the claim back; the steps of this task are dropped, units stay.
function CS.Abandon(src, taskId, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local e, err = liveFor(src, taskId, now)
    if not e then return err end
    return J.Locks.With('cstask:' .. e.taskId, function()
        local task = CS.Task(e.taskId)
        if not task or task.state ~= 'active' then forgetLive(e.taskId) return Err('not_found', 'No such task') end
        endTask(task, 'released', 'abandoned', now)
        return { ok = true }
    end)
end

--- Whether src may supervise: on duty in Config.CommunityService.SupervisorJobs (job -> min grade)
--- and holding the GOV 'cs_supervisor' qualification (granted or implied by grade).
function CS.IsSupervisor(src)
    local P, cid = playerOf(src)
    if not P then return false end
    local job = P.PlayerData.job or {}
    local jobs = T.Cfg().SupervisorJobs or { doj = 3, government = 0 }
    local min = jobs[job.name]
    if min == nil or job.onduty ~= true then return false end
    local grade = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade) or 0
    if grade < (tonumber(min) or 0) then return false end
    if not govStarted() then return false end
    local ok, has = pcall(function() return exports['pf-government']:HasQualification(cid, 'cs_supervisor') end)
    return ok and has == true
end

--- A supervisor verifies the open shift of the citizen standing near them.
function CS.Verify(supSrc, targetSrc, now)
    now = now or os.time()
    if not CS.Ready() then return notReady() end
    local target = U.Src(targetSrc)
    if not target then return Err('bad_args', 'Invalid player') end
    if target == supSrc then return Err('no_permission', 'You cannot supervise yourself') end
    if not CS.IsSupervisor(supSrc) then return Err('no_permission', 'Only an on-duty community service supervisor can verify a shift') end
    local _, supCid = playerOf(supSrc)
    local TP, cid = playerOf(target)
    if not TP then return Err('offline', 'Player not found') end
    local a, b = U.Coords(supSrc), U.Coords(target)
    if not a or not b or dist2(a, b) > cfg('SupervisorDistance', 30.0, 2.0, 200.0) then return Err('too_far', 'Stand near the worker') end
    return J.Orders.WithCid(cid, function()
        local shift = CS.OpenShift(cid)
        if not shift then return Err('not_found', 'That citizen is not signed in for community service') end
        if shift.supervisor_cid then return { ok = true, duplicate = true, shiftId = shift.id } end
        if update(SQL.csSupervise, { supCid, shift.id }) ~= 1 then return Err('busy', 'The shift changed meanwhile; try again') end
        J.Orders.Event(shift.order_id, 'cs_supervised', { shiftId = shift.id }, actorOf(supSrc))
        return { ok = true, shiftId = shift.id }
    end)
end

-- ── state for the client ────────────────────────────────────────────────────────────────────────

--- What the citizen's client shows (all values from the server).
function CS.State(src)
    local P, cid = playerOf(src)
    if not P or not CS.Ready() then return nil end
    local orders = CS.OpenOrders(cid) or {}
    local shift = CS.OpenShift(cid)
    local state = { orders = {}, signIns = {} }
    for _, r in ipairs(orders) do
        state.orders[#state.orders + 1] = { id = r.id, units = r.units, unitsDone = r.units_done, dueAt = r.due_at, state = r.state,
            dueIn = r.due_at and (r.due_at - os.time()) or nil }
    end
    if #state.orders == 0 and not shift then return nil end
    for _, p in ipairs(T.SignIns()) do
        local c = p.coords
        if c then state.signIns[#state.signIns + 1] = { id = p.id, label = p.label, x = c.x, y = c.y, z = c.z } end
    end
    if shift then
        state.shift = { id = shift.id, orderId = shift.order_id, supervised = shift.supervisor_cid ~= nil, startedAt = shift.started_at }
        local e = CS.live[CS.bySrc[src] or 0]
        if e and e.cid == cid then
            local kind = T.Kind(e.kind) or {}
            state.task = {
                id = e.taskId, kind = e.kind, label = kind.label, stepLabel = kind.stepLabel, scenario = kind.scenario,
                site = e.site, points = e.points, stepsDone = e.stepsDone, stepsNeeded = e.stepsNeeded,
                minSeconds = e.minSeconds, onSiteSeconds = e.since and (os.time() - e.since) or 0,
            }
        end
    end
    return state
end

function CS.Push(src)
    TriggerClientEvent('pf-justice:client:CsState', src, CS.State(src))
end

-- ── ticks (named, so specs can call them) ───────────────────────────────────────────────────────

--- 1 Hz presence sample of every live task: the on-site stretch starts at the first sample inside the
--- site (on foot) and breaks at any sample outside it.
function CS.Sample(now)
    now = now or os.time()
    local n = 0
    for _, e in pairs(CS.live) do
        local P = J.GetPlayer(e.src)
        if P and P.PlayerData.citizenid == e.cid and onSite(e.src, e.site) then
            e.since = e.since or now
        else
            e.since = nil
        end
        n = n + 1
    end
    return n
end

--- Files one court item per overdue order (never prison; the court decides).
function CS.CourtTick(now)
    now = now or os.time()
    if not CS.Ready() or T.Cfg().OverdueFilesCase == false then return 0 end
    local filed = 0
    for _, r in ipairs(many(SQL.csOverdue, {}) or {}) do
        local id = tonumber(r.id)
        local key = ('pf-justice:cs:order:%d:court'):format(id)
        local res = J.Orders.WithOrder(id, function(row)
            if row.kind ~= 'community_service' or row.state ~= 'overdue' then return { ok = true } end
            local ev, okq = one(SQL.eventByKey, { key })
            if not okq then return Err('db_unavailable', 'no answer') end
            if ev then return { ok = true } end
            local spec = { cid = row.citizenid, kind = 'violation', orderId = row.id,
                charges = { { code = 'CS-DEADLINE', label = ('Community service order #%d not completed by its deadline (%d of %d units)')
                    :format(row.id, row.units_done or 0, row.units or 0), count = 1 } } }
            local opts = { key = key, actor = { kind = 'system', label = 'community service' }, filedBy = 'system' }
            local ok, case = pcall(function()
                local fn = J.API and J.API.FileCase
                if U.Callable(fn) then return fn(spec, opts) end
                return exports[J.RESOURCE]:FileCase(spec, opts)
            end)
            if not ok or type(case) ~= 'table' or case.ok ~= true then
                if not warned[id] or now - warned[id] >= 3600 then
                    warned[id] = now
                    print(('^3[pf-justice]^7 community service order %d: court item not filed yet (%s); retrying'):format(id,
                        tostring(ok and type(case) == 'table' and case.error or case)))
                end
                return Err('db_unavailable', 'not filed')
            end
            J.Orders.Event(row.id, 'cs_court', { caseId = case.caseId }, SYSTEM, key)
            if GetResourceState('pf-citizen') == 'started' then
                pcall(function()
                    return exports['pf-citizen']:SendMail(row.citizenid, { sender = 'San Andreas Superior Court', senderType = 'government',
                        subject = ('Community service order #%d is overdue'):format(row.id),
                        message = ('Your community service order #%d passed its deadline with %d of %d units done. The matter has been referred to the court (case %s). You can still finish the remaining units.')
                            :format(row.id, row.units_done or 0, row.units or 0, tostring(case.caseNo or case.caseId)),
                        ref = key })
                end)
            end
            local P = J.GetPlayerByCid(row.citizenid)
            if P then J.Notify(P.PlayerData.source, ('Community service order #%d was referred to the court'):format(row.id), 'error') end
            return { ok = true, filed = true }
        end)
        if type(res) == 'table' and res.filed then filed = filed + 1 end
    end
    return filed
end

--- Ends shifts open longer than ShiftMaxHours (their task's claim is given back; units stay).
function CS.StaleTick(now)
    now = now or os.time()
    if not CS.Ready() then return 0 end
    local n = 0
    for _, r in ipairs(many(SQL.csStaleShifts, { now - cfg('ShiftMaxHours', 4, 0.25, 48) * 3600 }) or {}) do
        local shift = norm(r)
        local res = shift and J.Orders.WithCid(shift.citizenid, function()
            local task = one(SQL.csActiveTask, { shift.id })
            if task then endTask(task, 'released', 'shift_ended', now) end
            return { ok = endShiftRow(shift.id, now) }
        end)
        if type(res) == 'table' and res.ok then
            n = n + 1
            local P = J.GetPlayerByCid(shift.citizenid)
            if P then CS.Push(P.PlayerData.source) end
        end
    end
    return n
end

function CS.Tick(now)
    now = now or os.time()
    local a = CS.StaleTick(now)
    local b = CS.CourtTick(now)
    return a, b
end

-- ── net events (architecture 6.2 checklist) ─────────────────────────────────────────────────────

local function handler(name, seconds, fn)
    RegisterNetEvent('pf-justice:server:' .. name, function(...)
        local src = tonumber(source)
        if not src or src <= 0 then return end
        if not J.Rate.Allow(('cs:%d:%s'):format(src, name), seconds) then return end
        local ok, res = pcall(fn, src, ...)
        if not ok then
            print(('^1[pf-justice]^7 %s failed: %s'):format(name, tostring(res)))
            res = Err('db_unavailable', 'Something went wrong; nothing was changed')
        end
        if type(res) == 'table' and res.ok == false and res.message then J.Notify(src, res.message, 'error') end
        if res ~= false then CS.Push(src) end
    end)
end

handler('CsSync', 5, function(src) CS.Resume(src) return true end)
handler('CsStartShift', 2, function(src)
    local res = CS.StartShift(src)
    if res.ok and not res.duplicate then J.Notify(src, 'Signed in for community service', 'success') end
    return res
end)
handler('CsEndShift', 2, function(src)
    local res = CS.EndShift(src)
    if res.ok then J.Notify(src, 'Signed out of community service', 'primary') end
    return res
end)
handler('CsListWork', 2, function(src)
    local res = CS.ListWork(src)
    if res.ok then
        TriggerClientEvent('pf-justice:client:CsWorkList', src, res.list)
        if #res.list == 0 then J.Notify(src, 'No community service work nearby right now', 'primary') end
    end
    return res
end)
handler('CsClaimTask', 1, function(src, workOrderId)
    local res = CS.Claim(src, workOrderId)
    if res.ok then J.Notify(src, 'Task assigned: go to the marked site', 'success') end
    return res
end)
handler('CsTaskStep', 1, function(src, taskId, step) return CS.Step(src, taskId, step) end)
handler('CsCompleteTask', 1, function(src, taskId)
    local res = CS.Complete(src, taskId)
    if res.ok and not res.duplicate then
        J.Notify(src, res.completed and 'Community service order completed' or ('Unit done: %d of %d'):format(res.unitsDone or 0, res.units or 0), 'success')
    end
    return res
end)
handler('CsAbandonTask', 1, function(src, taskId) return CS.Abandon(src, taskId) end)
handler('CsVerifyShift', 2, function(src, target)
    local res = CS.Verify(src, target)
    if res.ok then
        J.Notify(src, 'Shift verified', 'success')
        local t = U.Src(target)
        if t then J.Notify(t, 'A supervisor verified your community service shift', 'success') CS.Push(t) end
    end
    return res
end)

-- ── player lifecycle ────────────────────────────────────────────────────────────────────────────

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src = type(Player) == 'table' and Player.PlayerData and tonumber(Player.PlayerData.source)
    if not src or not CS.Ready() then return end
    CS.Resume(src)
    CS.Push(src)
end)

-- a disconnect keeps the shift, the task and its steps (rows); only the memory of the stretch goes
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    local id = CS.bySrc[src]
    if id then forgetLive(id) end
    J.Rate.Forget(('cs:%d:'):format(src))
end)

-- ── export ──────────────────────────────────────────────────────────────────────────────────────

--- GetCommunityService(cid) -> { ok, orders = { { orderId, units, unitsDone, dueAt, state } } }.
function CS.Get(cid)
    if not U.ValidCid(cid) then return Err('bad_args', 'cid is invalid') end
    if not J.Ready() then return notReady() end
    local rows = many(SQL.csOrdersOf, { cid })
    if not rows then return Err('db_unavailable', 'The justice database did not answer') end
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { orderId = tonumber(r.id), units = tonumber(r.units), unitsDone = tonumber(r.units_done) or 0,
            dueAt = tonumber(r.due_at), state = r.state }
    end
    return { ok = true, orders = out }
end

exports('GetCommunityService', function(cid)
    local allowed, res = J.Callers.Check('GetCommunityService', GetInvokingResource())
    if not allowed then return res end
    return CS.Get(cid)
end)

-- ── loops ───────────────────────────────────────────────────────────────────────────────────────

--- After a resource restart: resume every online player's shift (CreateThread does nothing in specs).
function CS.LoadOnline()
    local n = 0
    for _, id in ipairs(GetPlayers and GetPlayers() or {}) do
        local src = tonumber(id)
        if src and J.GetPlayer(src) then
            CS.Resume(src)
            CS.Push(src)
            n = n + 1
        end
    end
    return n
end

CreateThread(function()
    while not CS.Ready() do Wait(5000) end
    pcall(CS.LoadOnline)
    local sample = math.max(1, math.floor(cfg('SampleSeconds', 1, 1, 10)))
    local every = math.max(1, math.floor(60 / sample))
    local n = 0
    while true do
        Wait(sample * 1000)
        n = n + 1
        if next(CS.live) ~= nil then
            local ok, err = pcall(CS.Sample, os.time())
            if not ok then print(('^1[pf-justice]^7 community service sample failed: %s'):format(tostring(err))) end
        end
        if n % every == 0 then
            local ok, err = pcall(CS.Tick, os.time())
            if not ok then print(('^1[pf-justice]^7 community service tick failed: %s'):format(tostring(err))) end
        end
    end
end)
