-- EMS MDT client bridge for the field pages (batch 21): patient care (exam, treatment, chart,
-- vitals monitor), the unit board and patient care reports.
--
-- Nothing here decides anything. Every request goes to the server callback that owns it and the
-- page shows that callback's answer as it came back:
--   * exams and treatments: pf-ambulancejob (pf-ambulancejob:server:examOptions / exam / treatOptions /
--     treat / getChart); the server checks tier, distance, items, place and time and rolls the findings;
--   * the unit board and PCRs: this resource's server (pf_emsmdt:units:* and pf_emsmdt:pcr:*).
-- The treatment and exam catalogues (labels, which actions need a body region) come from
-- pf-ambulancejob's shared data files, loaded by the manifest; they only build the page's menus.
--
-- The vitals monitor shows measured values: an exam's vitals, the chart's vital-sign findings, and
-- pf-ambulancejob:client:Monitor (architecture 4.x: patientSrc, vitals, rhythm, every 5 s to the medic
-- attached to the patient's monitor) when pf-ambulancejob sends it.

local QBCore = PFMdt.GetCore()

PFEmsCare = PFEmsCare or {}
local C = PFEmsCare

C.target = nil      -- server id of the patient the care page works on
C.uiOpen = false
C.reqCount = 0

local function fail(code, message) return { ok = false, error = code, message = message } end

local function str(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

local function int(v, lo, hi)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.tointeger(n) or math.floor(n)
    if (lo and n < lo) or (hi and n > hi) then return nil end
    return n
end

-- pfm-core's client keeps ONE pending slot per callback name: a second TriggerCallback of the same
-- name before the first answer replaces it, and the first answer never arrives. So every server
-- callback this bridge makes runs one at a time per name (a queue per name). A request whose answer
-- does not come within CallTimeoutMs gives up, so a lost answer cannot block the queue.
C.CallTimeoutMs = 10000
C.queues = {}      -- [name] = { busy = bool, list = { { args, cb } } }

local function pump(name)
    local q = C.queues[name]
    if not q or q.busy or #q.list == 0 then return end
    local job = table.remove(q.list, 1)
    q.busy = true
    local done = false
    local function finish(res)
        if done then return end   -- a late answer after the timeout (or the reverse) is dropped
        done = true
        q.busy = false
        job.cb(res)
        pump(name)
    end
    SetTimeout(C.CallTimeoutMs, function() finish(nil) end)
    QBCore.Functions.TriggerCallback(name, finish, table.unpack(job.args, 1, job.args.n))
end

--- Raw answer (may be nil) of a server callback, after any earlier request of the same name.
local function callRaw(name, cb, ...)
    local q = C.queues[name]
    if not q then q = { busy = false, list = {} } C.queues[name] = q end
    q.list[#q.list + 1] = { args = table.pack(...), cb = cb }
    pump(name)
end
C.CallRaw = callRaw

local function call(name, cb, ...)
    callRaw(name, function(res)
        if type(res) ~= 'table' then res = fail('no_answer', 'No answer from the server.') end
        cb(res)
    end, ...)
end

AddEventHandler('pf_emsmdt:client:UIOpenState', function(open) C.uiOpen = open == true end)

-- ── catalogue for the page's menus (pf-ambulancejob shared data) ───────────────────────────────

local REGION_ORDER = { 'head', 'face', 'neck', 'chest_l', 'chest_r', 'abdomen', 'back_upper', 'back_lower', 'pelvis',
    'shoulder_l', 'shoulder_r', 'upper_arm_l', 'upper_arm_r', 'forearm_l', 'forearm_r', 'hand_l', 'hand_r',
    'thigh_l', 'thigh_r', 'knee_l', 'knee_r', 'lower_leg_l', 'lower_leg_r', 'foot_l', 'foot_r' }

local catalog
--- Labels and targeting of exams and treatments for the page. CPR is a stream of ticks that needs
--- the medic's hands on the patient (/cpr), and self-only actions are not for a patient: both left out.
function C.Catalog()
    if catalog then return catalog end
    local M = PFMed or {}
    local A, T = M.Anatomy or {}, M.Treatments or {}
    local regions, structures, actions = {}, {}, {}
    for _, id in ipairs(REGION_ORDER) do
        local r = A.Regions and A.Regions[id]
        if r then regions[#regions + 1] = { id = id, label = r.label } end
    end
    for id, s in pairs(A.Structures or {}) do structures[id] = s.label end
    for name, a in pairs(T.Actions or {}) do
        if a.apply ~= 'cpr' and not a.selfOnly then
            local allowed
            if a.regions then
                allowed = {}
                for _, id in ipairs(REGION_ORDER) do if a.regions[id] then allowed[#allowed + 1] = id end end
            end
            actions[name] = { label = a.label, target = a.target or 'patient', regions = allowed, tier = a.tier or 0,
                seconds = math.floor((a.duration or 4000) / 1000) }
        end
    end
    catalog = { regions = regions, structures = structures, actions = actions }
    return catalog
end

-- ── patients next to the medic ─────────────────────────────────────────────────────────────────

C.NearbyRadius = 3.0
C.NearbyMax = 6

--- Players within NearbyRadius (client positions: only a hint, the server checks distance on
--- every exam and treatment), nearest first.
function C.NearbyIds()
    local me = PlayerId()
    local here = GetEntityCoords(PlayerPedId())
    local list = {}
    for _, pl in ipairs(GetActivePlayers()) do
        if pl ~= me then
            local ped = GetPlayerPed(pl)
            if ped and ped ~= 0 then
                local d = #(GetEntityCoords(ped) - here)
                if d <= C.NearbyRadius then list[#list + 1] = { target = GetPlayerServerId(pl), distance = d } end
            end
        end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    while #list > C.NearbyMax do table.remove(list) end
    return list
end

--- Nearby patients with the name the server gives (pf-emsmdt:server:getCitizenData: an on-duty medic
--- within 5 m). A player the server does not name is left out.
function C.Nearby(cb)
    local ids = C.NearbyIds()
    if #ids == 0 then return cb({ ok = true, list = {} }) end
    local out, left = {}, #ids
    for i, p in ipairs(ids) do
        callRaw('pf-emsmdt:server:getCitizenData', function(cd)
            if type(cd) == 'table' and cd.citizenid then
                out[i] = { target = p.target, distance = math.floor(p.distance * 10 + 0.5) / 10, citizenid = cd.citizenid,
                    name = ((cd.firstname or '') .. ' ' .. (cd.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '') }
            end
            left = left - 1
            if left == 0 then
                local list = {}
                for j = 1, #ids do if out[j] then list[#list + 1] = out[j] end end
                cb({ ok = true, list = list })
            end
        end, p.target)
    end
end

--- Selects a patient: who it is (server), which exams this medic may do on them now and which
--- treatments their tier allows (pf-ambulancejob). The page gets every answer as it came.
function C.Select(target, cb)
    target = int(target, 1)
    if not target then return cb(fail('bad_args', 'No patient.')) end
    if target == GetPlayerServerId(PlayerId()) then return cb(fail('bad_args', 'You cannot examine yourself.')) end
    callRaw('pf-emsmdt:server:getCitizenData', function(cd)
        if type(cd) ~= 'table' or not cd.citizenid then
            return cb(fail('not_found', 'Patient not found: stand next to them while on duty.'))
        end
        C.target = target
        local patient = { target = target, citizenid = cd.citizenid,
            name = ((cd.firstname or '') .. ' ' .. (cd.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '') }
        call('pf-ambulancejob:server:examOptions', function(exam)
            call('pf-ambulancejob:server:treatOptions', function(treat)
                cb({ ok = true, patient = patient, exam = exam, treat = treat, catalog = C.Catalog() })
            end)
        end, target)
    end, target)
end

local EXAM_ANIM = { dict = 'amb@medic@standing@kneel@base', anim = 'base', flags = 49 }
local TREAT_ANIM = { dict = 'amb@medic@standing@tendtodead@idle_a', anim = 'idle_a', flags = 49 }

local function progress(name, label, ms, anim, canCancel, done)
    local Fn = QBCore.Functions.Progressbar
    if not Fn then return done(true) end
    Fn(name, label, ms, false, canCancel,
        { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
        { animDict = anim.dict, anim = anim.anim, flags = anim.flags }, {}, {},
        function() StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0) done(true) end,
        function() StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0) done(false) end)
end

--- One exam. The server waits the exam's time itself and re-checks everything afterwards; the bar
--- only shows that time. The answer is the server's: findings (a miss is no finding) and vitals.
function C.Exam(target, modality, cb)
    target = int(target, 1)
    modality = str(modality, 24)
    if not target or not modality then return cb(fail('bad_args', 'Choose an exam.')) end
    local def = PFMed and PFMed.Findings and PFMed.Findings.Modalities[modality]
    call('pf-ambulancejob:server:exam', cb, target, modality)
    progress('ems_mdt_exam', (def and def.label or 'Examining') .. '...', math.max(1, def and def.seconds or 1) * 1000, EXAM_ANIM, false, function() end)
end

function C.NextReq()
    C.reqCount = C.reqCount + 1
    return ('mdt%d_%d'):format(GetGameTimer(), C.reqCount)
end

--- One treatment: the action's time on a progress bar, then the server's treat callback with a
--- request id (a repeat of it returns the first answer). The page shows the server's result.
function C.Treat(data, cb)
    data = type(data) == 'table' and data or {}
    local target, action = int(data.target, 1), str(data.action, 32)
    local def = action and C.Catalog().actions[action]
    if not target or not def then return cb(fail('bad_args', 'Choose a treatment.')) end
    local req = { target = target, action = action, region = str(data.region, 24), injuryId = int(data.injuryId, 1), req = C.NextReq() }
    progress('ems_mdt_treat', def.label .. '...', math.max(1, def.seconds) * 1000, TREAT_ANIM, true, function(finished)
        if not finished then return cb(fail('cancelled', 'Cancelled.')) end
        call('pf-ambulancejob:server:treat', cb, req)
    end)
end

function C.Chart(target, cb)
    target = int(target, 1)
    if not target then return cb(fail('bad_args', 'No patient.')) end
    call('pf-ambulancejob:server:getChart', cb, target)
end

-- ── forwards to this resource's server (unit board, PCRs) ──────────────────────────────────────

--- Allowed server callbacks and the payload each one gets (clean types; the server checks again).
C.Server = {
    ['units:list'] = function() return nil end,
    ['units:join'] = function(d) return { unit = str(d.unit, 32) } end,
    ['units:leave'] = function() return nil end,
    ['units:setStatus'] = function(d) return { status = str(d.status, 32) } end,
    ['units:setRig'] = function(d) return { clear = d.clear == true } end,
    ['pcr:list'] = function(d)
        if d.scope == 'patient' then return { scope = 'patient', citizenId = str(d.citizenId, 64) } end
        return { scope = 'mine' }
    end,
    ['pcr:get'] = function(d) return { id = int(d.id, 1) } end,
    ['pcr:saveNarrative'] = function(d) return { id = int(d.id, 1), text = type(d.text) == 'string' and d.text:sub(1, 16000) or nil } end,
    ['pcr:close'] = function(d) return { id = int(d.id, 1), disposition = str(d.disposition, 32) } end,
    ['pcr:acknowledgeHandover'] = function(d) return { id = int(d.id, 1) } end,
    ['pcr:pendingHandovers'] = function() return nil end,
}

function C.Forward(op, data, cb)
    local shape = type(op) == 'string' and C.Server[op]
    if not shape then return cb(fail('bad_args', 'Unknown request.')) end
    call('pf_emsmdt:' .. op, cb, shape(type(data) == 'table' and data or {}))
end

--- What the field pages may show, from the server's own answers (units:list for the board,
--- pcr:list for reports). A page the server refuses is not offered; the server checks every request anyway.
function C.Access(cb)
    call('pf_emsmdt:units:list', function(units)
        call('pf_emsmdt:pcr:list', function(pcr)
            cb({ ok = true, units = units, pcr = pcr })
        end, { scope = 'mine' })
    end)
end

-- ── NUI ────────────────────────────────────────────────────────────────────────────────────────

RegisterNUICallback('emsAccess', function(_, cb) C.Access(cb) end)
RegisterNUICallback('emsServer', function(data, cb)
    data = type(data) == 'table' and data or {}
    C.Forward(data.op, data.data, cb)
end)
RegisterNUICallback('emsCareNearby', function(_, cb) C.Nearby(cb) end)
RegisterNUICallback('emsCareSelect', function(data, cb) C.Select(type(data) == 'table' and data.target, cb) end)
RegisterNUICallback('emsCareExam', function(data, cb)
    data = type(data) == 'table' and data or {}
    C.Exam(data.target, data.modality, cb)
end)
RegisterNUICallback('emsCareTreat', function(data, cb) C.Treat(data, cb) end)
RegisterNUICallback('emsCareChart', function(data, cb) C.Chart(type(data) == 'table' and data.target, cb) end)
RegisterNUICallback('emsCareClose', function(_, cb)
    C.target = nil
    cb({ ok = true })
end)

-- ── server pushes ──────────────────────────────────────────────────────────────────────────────

-- the unit board after every change (server/units.lua U.Push); only while the MDT is open
RegisterNetEvent('pf_emsmdt:client:UnitBoard', function(board)
    if not C.uiOpen or type(board) ~= 'table' then return end
    SendNUIMessage({ action = 'unitBoard', board = board })
end)

-- the patient's monitor (pf-ambulancejob, to the attached medic only): for the patient on the page
RegisterNetEvent('pf-ambulancejob:client:Monitor', function(patientSrc, vitals, rhythm)
    if not C.uiOpen or C.target == nil or tonumber(patientSrc) ~= C.target or type(vitals) ~= 'table' then return end
    SendNUIMessage({ action = 'careMonitor', target = C.target, vitals = vitals, rhythm = type(rhythm) == 'string' and rhythm or nil })
end)

--- Opens the MDT on the patient care page for a patient (other resources: the export, or the local
--- event). The page selects the patient through the server like any other selection.
function C.Open(target)
    target = int(target, 1)
    if not target then return false end
    if not C.uiOpen and type(PFMdtOpen) == 'function' then PFMdtOpen('care') end
    SendNUIMessage({ action = 'careOpen', target = target })
    return true
end

AddEventHandler('pf_emsmdt:client:OpenPatientCare', function(target) C.Open(target) end)
exports('OpenPatientCare', function(target) return C.Open(target) end)
