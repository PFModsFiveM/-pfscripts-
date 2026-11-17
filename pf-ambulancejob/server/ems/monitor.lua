-- Vitals monitor (architecture 4.1 client event pf-ambulancejob:client:Monitor, 6.4 "monitor attach").
--
-- A medic attaches a monitor to a patient with the callback pf-ambulancejob:server:monitorAttach
-- (target) and takes it off with pf-ambulancejob:server:monitorDetach. Attaching has the ECG's own
-- requirements (17A PFMed.Exam.Check(src, target, 'ecg'): on-duty medical staff of the ECG tier,
-- the patient online within touch distance and in the same routing bucket, the monitor (an AED, a
-- rig nearby or the hospital)). While attached, Monitor.Tick (a named step; the thread calls it every
-- PushSeconds) sends
--     TriggerClientEvent('pf-ambulancejob:client:Monitor', medicSrc, patientSrc, vitals, rhythm)
--     vitals = { hr, sbp, dbp, rr, spo2, temp }   rhythm = 'sinus' | 'sinus_tachycardia' | ... | 'vf' | 'pea' | 'asystole'
-- to that medic only (pf-emsmdt client/injury_integration.lua forwards it to the care page). The
-- values are the engine's derived vitals, the same ones an exam measures (no reading in arrest).
-- The monitor comes off by itself when the two are further apart than KeepDistance, either goes
-- offline, the medic goes off duty, or the patient's character changes on that server id.
-- One monitor per medic, at most MaxPerPatient medics per patient and MaxTotal monitors in all.

PFMed = PFMed or {}
PFMed.Monitor = PFMed.Monitor or {}
local M = PFMed.Monitor

M.Defaults = { KeepDistance = 6.0, PushSeconds = 5, MaxPerPatient = 4, MaxTotal = 64 }
local function cfg()
    local c = Config.EMS and Config.EMS.Monitor
    if type(c) ~= 'table' then return M.Defaults end
    return setmetatable(c, { __index = M.Defaults })
end

M.attached = {}   -- [medicSrc] = { patient = src, cid, medicCid, since }

local function Dx() return PFMed.Diagnosis end
local function now() return os.time() end
local function fail(code, message) return Dx().Fail(code, message) end

function M.Count()
    local n = 0
    for _ in pairs(M.attached) do n = n + 1 end
    return n
end

local function onPatient(patientSrc)
    local n = 0
    for _, m in pairs(M.attached) do if m.patient == patientSrc then n = n + 1 end end
    return n
end

--- The reading pushed to the medic: the engine's vitals now, nothing measurable in arrest.
function M.Reading(cid, at)
    local p = PFMed.Store.Peek(cid)
    if not p then return nil end
    local v = PFMed.Engine.Vitals(p, at or now())
    local level = p.consciousness or 'alert'
    local down = level == 'arrest' or level == 'dead'
    local vitals = {
        hr = down and 0 or v.hr, sbp = down and 0 or v.sbp, dbp = down and 0 or v.dbp,
        rr = down and 0 or v.rr, spo2 = down and 0 or v.spo2, temp = v.temp,
    }
    local rhythm = PFMed.Physiology.Rhythm(v, v.conditions, level, p.cause)
    return vitals, rhythm
end

local function push(medicSrc, m, at)
    local vitals, rhythm = M.Reading(m.cid, at)
    if not vitals then return false end
    TriggerClientEvent('pf-ambulancejob:client:Monitor', medicSrc, m.patient, vitals, rhythm)
    return true
end

function M.Detach(medicSrc, reason)
    local m = M.attached[medicSrc]
    if not m then return false end
    M.attached[medicSrc] = nil
    if reason and reason ~= 'medic' then
        TriggerClientEvent('QBCore:Notify', medicSrc, 'The monitor came off the patient.', 'error')
    end
    PFMed.Store.Audit(m.cid, 'monitor_detach', { cid = m.medicCid, src = medicSrc }, { reason = reason })
    return true
end

function M.Attach(src, target)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return fail('bad_args') end
    if Dx().Limited(src) then return fail('rate_limited') end
    target = math.tointeger(tonumber(target))
    if not target or target <= 0 then return fail('bad_args') end
    local ctx, code, msg = PFMed.Exam.Check(src, target, 'ecg')
    if not ctx then return fail(code, msg) end
    local cur = M.attached[src]
    if cur and cur.patient == target and cur.cid == ctx.cid then
        local vitals, rhythm = M.Reading(ctx.cid)
        return { ok = true, duplicate = true, patient = target, vitals = vitals, rhythm = rhythm }
    end
    local c = cfg()
    if onPatient(target) >= c.MaxPerPatient then return fail('busy', 'Enough monitors on this patient.') end
    if not cur and M.Count() >= c.MaxTotal then return fail('busy', 'No monitor free right now.') end
    if cur then M.Detach(src, 'medic') end
    local at = now()
    local m = { patient = target, cid = ctx.cid, medicCid = ctx.provider.cid, since = at }
    M.attached[src] = m
    Dx().NoteCare(ctx.cid, ctx.provider.cid, at)
    PFMed.Store.Audit(ctx.cid, 'monitor_attach', { cid = ctx.provider.cid, src = src, job = ctx.provider.job }, { tier = ctx.provider.tier })
    push(src, m, at)
    local vitals, rhythm = M.Reading(ctx.cid, at)
    return { ok = true, patient = target, vitals = vitals, rhythm = rhythm }
end

function M.DetachOwn(src)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return fail('bad_args') end
    if not M.Detach(src, 'medic') then return fail('not_found', 'No monitor attached.') end
    return { ok = true }
end

--- Why an attachment must end now, or nil.
function M.Broken(medicSrc, m)
    local medic = Dx().GetPlayer(medicSrc)
    if not medic then return 'medic_offline' end
    if not Dx().IsOnDutyMedic(medic) then return 'off_duty' end
    local patient = Dx().GetPlayer(m.patient)
    if not patient or patient.PlayerData.citizenid ~= m.cid then return 'patient_offline' end
    if GetPlayerRoutingBucket(medicSrc) ~= GetPlayerRoutingBucket(m.patient) then return 'apart' end
    if Dx().Dist(Dx().Coords(medicSrc), Dx().Coords(m.patient)) > cfg().KeepDistance then return 'apart' end
    return nil
end

--- One pass: every attachment is checked and, when still good, gets one reading. Returns pushes.
function M.Tick(at)
    at = at or now()
    local n, list = 0, {}
    for medicSrc, m in pairs(M.attached) do list[#list + 1] = { medicSrc, m } end
    for _, e in ipairs(list) do
        local why = M.Broken(e[1], e[2])
        if why then M.Detach(e[1], why)
        elseif push(e[1], e[2], at) then n = n + 1 end
    end
    return n
end

PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:monitorAttach', function(source, cb, target)
    local ok, res = pcall(M.Attach, source, target)
    cb(ok and res or fail('db_unavailable'))
end)

PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:monitorDetach', function(source, cb)
    local ok, res = pcall(M.DetachOwn, source)
    cb(ok and res or fail('db_unavailable'))
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    M.attached[src] = nil
    for medicSrc, m in pairs(M.attached) do
        if m.patient == src then M.Detach(medicSrc, 'patient_offline') end
    end
end)

CreateThread(function()
    while true do
        Wait((cfg().PushSeconds or 5) * 1000)
        if next(M.attached) then
            local ok, err = pcall(M.Tick, now())
            if not ok then print('^1[pf-ambulancejob]^7 monitor tick failed: ' .. tostring(err)) end
        end
    end
end)
