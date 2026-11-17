-- Hospital imaging: x-ray and CT orders that confirm diagnoses (batch 20A, architecture 4.2, 11.6).
--
-- A physician (Imaging.OrderTier) orders a scan for a patient with an open admission. Staff
-- (Imaging.PerformTier) run it with the patient lying in their server-held bed in an imaging
-- department (17A's PFMed.Exam.InImagingBed) and the operator within Imaging.Distance. The scan
-- takes the modality's time on the server; patient and operator are checked again afterwards (a
-- patient who got up interrupts the scan and the order goes back to 'ordered'). Radiology reads
-- it at Imaging.ReadTier through 17A's own generator (Dx.Generate on the engine state: a miss
-- finds nothing, never a false finding), and Dx.Record stores the findings; a confirmed finding on
-- an injury confirms its diagnosis (source 'imaging'). That confirmation is what surgery needs.

PFHospital = PFHospital or {}
local H = PFHospital
H.Imaging = H.Imaging or {}
local I = H.Imaging
local O = H.Orders
local Q = H.SQL

local function cfg() return Config.Hospital.Imaging end
local function now() return H.Now() end

--- Waits on the server for the scan (specs replace it: Wait does nothing in the harness).
function I.WaitFor(seconds)
    if seconds and seconds > 0 then Wait(math.floor(seconds * 1000)) end
end

function I.Order(src, target, test)
    if H.Limited(src, 'img_order', 1) then return H.Fail('rate_limited', 'Slow down.') end
    if type(test) ~= 'string' or not cfg().Tests[test] then return H.Fail('bad_args', 'Imaging: xray or ct.') end
    local ctx, code, msg = O.Context(src, target, cfg().OrderTier, Config.Hospital.Roles.TouchDistance * 4)
    if not ctx then return H.Fail(code, msg) end
    return O.Create(ctx, 'imaging', test)
end

--- Everything the scan needs now. Returns P | nil, code, message.
local function check(src, r, psrc, a)
    local P, tierOrErr, msg = H.Provider(src, a.hospital_id, cfg().PerformTier)
    if not P then return nil, tierOrErr, msg end
    if psrc == src then return nil, 'bad_args', 'Not on yourself.' end
    if H.Dist(H.Pos(src), H.Pos(psrc)) > (cfg().Distance or 10.0) then return nil, 'too_far', 'Stay at the scanner with the patient.' end
    local Exam = PFMed.Exam
    local okBed, why = Exam.InImagingBed(psrc, r.citizenid, H.Pos(psrc))
    if not okBed then return nil, 'invalid_state', why end
    local down, level = PFMed.Engine.IsDown(r.citizenid)
    if down and level == 'dead' then return nil, 'invalid_state', 'The patient is dead.' end
    return P
end

function I.Perform(src, orderId)
    if H.Limited(src, 'img_run', 2) then return H.Fail('rate_limited', 'Slow down.') end
    local r, psrc, a = O.Load(orderId, 'imaging')
    if not r then return H.Fail(psrc, a) end
    if r.state ~= 'ordered' then return H.Fail('invalid_state', ('The order is %s.'):format(r.state)) end
    local P, code, msg = check(src, r, psrc, a)
    if not P then return H.Fail(code, msg) end
    local def = cfg().Tests[r.test]
    local res, err = H.WithLock('ordrun:' .. r.id, function()
        local at = now()
        local ok, n = pcall(Q.OrdStart, r.id, P.PlayerData.citizenid, at + def.seconds, nil)
        if not ok then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        if n ~= 1 then return H.Fail('invalid_state', 'The order changed; try again.') end
        I.WaitFor(def.seconds)
        -- operator and patient must still be in place after the scan's time
        local again, code2, msg2 = check(src, r, psrc, a)
        if not again or H.SourceOfCid(r.citizenid) ~= psrc then
            pcall(Q.OrdReset, r.id)
            return H.Fail(code2 or 'invalid_state', 'The scan was interrupted: ' .. tostring(msg2 or 'the patient left'))
        end
        local t = now()
        local p, perr = PFMed.Store.Get(r.citizenid)
        if not p then
            pcall(Q.OrdReset, r.id)
            return H.Fail(perr or 'db_unavailable', 'Medical records are unavailable.')
        end
        PFMed.Engine.Touch(p, t)
        local Dx = PFMed.Diagnosis
        local list = Dx.Generate(p, r.test, cfg().ReadTier, t)
        local saved = Dx.Record(r.citizenid, list, { cid = P.PlayerData.citizenid, tier = cfg().ReadTier }, t)
        if not saved then
            pcall(Q.OrdReset, r.id)
            return H.Fail('db_unavailable', 'Medical records are unavailable.')
        end
        local result = { findings = O.PublicFindings(saved) }
        local okR, nR = pcall(Q.OrdResult, r.id, json.encode(result), t)
        if not okR or nR ~= 1 then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        Dx.NoteCare(r.citizenid, P.PlayerData.citizenid, t)
        H.Audit(r.citizenid, 'result', H.ActorOf(src, P), { order = r.id, test = r.test, findings = #saved })
        if r.ordered_by ~= P.PlayerData.citizenid then
            O.NotifyCid(r.ordered_by, ('Imaging result ready: %s (order #%d).'):format(O.Label('imaging', r.test), r.id), 'success')
        end
        TriggerEvent('pf-ambulancejob:server:orderResulted', O.View({ id = r.id, citizenid = r.citizenid, admission_id = r.admission_id,
            hospital_id = r.hospital_id, kind = 'imaging', test = r.test, state = 'resulted', ordered_by = r.ordered_by,
            done_by = P.PlayerData.citizenid, ordered_at = r.ordered_at, ready_at = t, resulted_at = t, result = json.encode(result) }))
        return { ok = true, orderId = r.id, findings = result.findings }
    end)
    if res == nil then return H.Fail(err or 'busy', 'The scanner is busy.') end
    return res
end

local callback = H.ServiceCallback
callback('imagingOrder', function(src, target, test) return I.Order(src, target, test) end)
callback('imagingPerform', function(src, orderId) return I.Perform(src, orderId) end)

local function reply(src, res, okText)
    if res and res.ok then H.Notify(src, okText, 'success') else H.Notify(src, (res and res.message) or 'Refused.', 'error') end
end

CreateThread(function()
    local QB = PFAmbulance.GetCore()
    if not QB.Commands or not QB.Commands.Add then return end
    QB.Commands.Add('himaging', 'Hospital: order imaging (xray, ct)', { { name = 'id', help = 'Player id' }, { name = 'test', help = 'xray or ct' } }, true, function(source, args)
        local res = I.Order(source, args[1], tostring(args[2] or ''):lower())
        reply(source, res, res.ok and ('Imaging order #%d.'):format(res.orderId) or '')
    end)
    QB.Commands.Add('hscan', 'Hospital: run an imaging order (patient in the imaging bed)', { { name = 'order', help = 'Order number' } }, true, function(source, args)
        local res = I.Perform(source, args[1])
        if not res.ok then return H.Notify(source, res.message or 'Refused.', 'error') end
        local parts = {}
        for _, f in ipairs(res.findings) do parts[#parts + 1] = tostring(f.label) .. (f.structure and (' (' .. f.structure .. ')') or '') end
        H.Notify(source, #parts > 0 and ('Findings: ' .. table.concat(parts, ', ')) or 'No abnormal findings.', 'success')
    end)
end)
