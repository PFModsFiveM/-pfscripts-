-- Surgery and ward/ICU stays (batch 20A, architecture 4.1 projectileRecovered, 4.5, 4.5.1, 11.7).
--
-- Surgery: a surgeon (H.IsSurgeon: qualification 'surgeon' from pf-government, or the grade
-- fallback) operates inside an operating room (Config.Hospital.Surgery.Rooms) on a patient who
-- lies in their server-held bed in that room, on an injury whose diagnosis is CONFIRMED (imaging,
-- labs: an injury id is only accepted through a confirmed diagnosis, so it cannot be used to probe
-- for hidden injuries), with a procedure the injury type lists in its care (injuries.lua treatBy).
-- The operation takes its time on the server and everything is checked again afterwards. The
-- injury gets the surgery flags (the recovery module then counts it as definitive care), the
-- procedure is written to the treatment log (location 'or', billed by 17E's bill) and to the order
-- table, and a retained projectile is recovered: the server event
-- `pf-ambulancejob:server:projectileRecovered(cid, { injuryId, caliber, weaponHash, attackerCid?,
-- byCid, at })` goes to pfm-policejob's evidence lab, which seals it with the key
-- pf-ambulancejob:projectile:<injuryId>. The injury keeps `projectileRecovered`, so a projectile is
-- raised once.
--
-- Stays: every span of a bed-holding admission in one department at one care level is a row in
-- pf_hosp_stays (opened and closed by 17E's own admission moves, which this file wraps). A
-- physician sets the ICU level. The bill (17E billing, one keyed charge per bill) prices each span
-- per started hour at Tariff.BedHour[level or dept], replacing 17E's single bed line.

PFHospital = PFHospital or {}
local H = PFHospital
H.Surgery = H.Surgery or {}
local Su = H.Surgery
H.Stays = H.Stays or {}
local St = H.Stays
local O = H.Orders
local Q = H.SQL
local A = H.Admissions

local function cfg() return Config.Hospital.Surgery end
local function now() return H.Now() end

-- ── SQL ───────────────────────────────────────────────────────────────────────────────────────

function Q.SuInsertTreatment(r)
    return MySQL.insert.await([[INSERT INTO pf_med_treatments (citizenid, injury_id, action, params, items, by_cid, by_job, location, admission_id,
        call_ref, req, result, at) VALUES (?, ?, ?, ?, NULL, ?, ?, 'or', ?, NULL, NULL, ?, ?)]],
        { r.citizenid, r.injury_id, r.action, r.params, r.by_cid, r.by_job, r.admission_id, r.result or 'ok', r.at })
end

local STAY_COLS = 'id, admission_id, citizenid, hospital_id, dept, level, bed_id, started_at, ended_at, set_by, bill_id, idem_key'

function Q.StayInsert(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_stays (admission_id, citizenid, hospital_id, dept, level, bed_id, started_at, set_by, idem_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], { r.admission_id, r.citizenid, r.hospital_id, r.dept, r.level, r.bed_id, r.started_at, r.set_by, r.idem_key })
end

function Q.StayByKey(key)
    return MySQL.single.await('SELECT ' .. STAY_COLS .. ' FROM pf_hosp_stays WHERE idem_key = ? LIMIT 1', { key })
end

function Q.StayEnd(id, at)
    return H.Affected(MySQL.update.await('UPDATE pf_hosp_stays SET ended_at = ? WHERE id = ? AND ended_at IS NULL', { at, id }))
end

function Q.StaysOpen(limit)
    return MySQL.query.await('SELECT ' .. STAY_COLS .. ' FROM pf_hosp_stays WHERE ended_at IS NULL ORDER BY id LIMIT ?', { limit or 2000 }) or {}
end

function Q.StaysFor(admissionId)
    return MySQL.query.await('SELECT ' .. STAY_COLS .. ' FROM pf_hosp_stays WHERE admission_id = ? ORDER BY id LIMIT 100', { admissionId }) or {}
end

function Q.StaySetBill(admissionId, billId)
    return MySQL.update.await('UPDATE pf_hosp_stays SET bill_id = ? WHERE admission_id = ? AND bill_id IS NULL', { billId, admissionId })
end

function Q.StayAdmissionEnd(admissionId)
    return MySQL.single.await('SELECT state, discharged_at FROM pf_hosp_admissions WHERE id = ? LIMIT 1', { admissionId })
end

function Q.StayDeleteCharacter(cid)
    return MySQL.update.await('DELETE FROM pf_hosp_stays WHERE citizenid = ?', { cid })
end

-- ── stays ─────────────────────────────────────────────────────────────────────────────────────

St.current = {}   -- [admissionId] = { id, dept, level, bed, started_at }

local function holdsBed(a) return a and A.HOLDS_BED[a.state] == true and a.dept ~= nil end

--- Opens a stay for admission a at `at` (level = a care level or the department). Returns stay | nil.
function St.Open(a, level, at, by)
    local key = ('pf-ambulancejob:stay:%d:%d:%s:%s'):format(a.id, at, a.dept, level)
    local ok, id = pcall(Q.StayInsert, { admission_id = a.id, citizenid = a.citizenid, hospital_id = a.hospital_id, dept = a.dept, level = level,
        bed_id = a.bed_id, started_at = at, set_by = by, idem_key = key })
    id = ok and tonumber(id) or nil
    if not id then
        local okK, row = pcall(Q.StayByKey, key)
        id = okK and row and tonumber(row.id) or nil
    end
    if not id then
        print(('^3[pf-ambulancejob]^7 stay of admission %d not recorded; the bill falls back to one bed line'):format(a.id))
        return nil
    end
    local s = { id = id, dept = a.dept, level = level, bed = a.bed_id, started_at = at }
    St.current[a.id] = s
    return s
end

function St.Close(admissionId, at)
    local s = St.current[admissionId]
    if not s then return end
    St.current[admissionId] = nil
    pcall(Q.StayEnd, s.id, math.max(at, s.started_at))
end

--- Brings the stay rows in line with the admission after a move: a new department (or a bed
--- given up / the admission closed) ends the current span; a bed-holding department starts one.
--- `level` forces a care level (SetCareLevel); otherwise the current level is kept within the same
--- department and resets to the department in a new one.
function St.Sync(a, at, level, by)
    at = at or now()
    local cur = St.current[a.id]
    if not holdsBed(a) or A.CLOSED[a.state] then
        if cur then St.Close(a.id, at) end
        return nil
    end
    local want = level or ((cur and cur.dept == a.dept) and cur.level) or a.dept
    if cur and cur.dept == a.dept and cur.level == want then
        cur.bed = a.bed_id
        return cur
    end
    if cur then St.Close(a.id, at) end
    return St.Open(a, want, at, by)
end

-- 17E's admission moves (looked up at call time inside admissions.lua, ai_care.lua and custody.lua)
local move = A.Move
A.Move = function(a, to, set, actor, detail)
    local res, err = move(a, to, set, actor, detail)
    if res then
        local ok, e = pcall(St.Sync, a, now(), nil, actor and actor.cid)
        if not ok then print('^1[pf-ambulancejob]^7 stay sync failed: ' .. tostring(e)) end
    end
    return res, err
end

local create = A.Create
A.Create = function(cid, spec)
    local a, err = create(cid, spec)
    if a then
        local ok, e = pcall(St.Sync, a, a.admitted_at or now(), nil, spec and spec.actor and spec.actor.cid)
        if not ok then print('^1[pf-ambulancejob]^7 stay sync failed: ' .. tostring(e)) end
    end
    return a, err
end

--- A physician sets the care level of a bed patient: 'icu' or 'standard' (the department's own).
function St.SetLevel(src, admissionId, level)
    if H.Limited(src, 'stay_level', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local c = Config.Hospital.Stays
    if level ~= 'standard' and not (type(level) == 'string' and c.Levels[level]) then return H.Fail('bad_args', 'Level: icu or standard.') end
    return A.WithAdmission(admissionId, function(a)
        local P, tierOrErr, msg = H.Provider(src, a.hospital_id, c.LevelTier)
        if not P then return H.Fail(tierOrErr, msg) end
        if not holdsBed(a) then return H.Fail('invalid_state', 'The patient has no bed.') end
        if level ~= 'standard' and not c.Levels[level].depts[a.dept] then return H.Fail('invalid_state', 'That care level is not given in this department.') end
        local want = level == 'standard' and a.dept or level
        local cur = St.current[a.id]
        if cur and cur.level == want then return { ok = true, unchanged = true, level = want } end
        local s = St.Sync(a, now(), want, P.PlayerData.citizenid)
        if not s then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        H.Audit(a.citizenid, 'care_level', H.ActorOf(src, P), { admission = a.id, level = want })
        return { ok = true, level = want, stayId = s.id }
    end)
end

--- Rebuilds the open stays after a restart; admissions from before schema v8 get their first stay
--- from admitted_at; stays of admissions that closed meanwhile end at their close.
function St.Start(at)
    at = at or now()
    local ok, rows = pcall(Q.StaysOpen, 2000)
    if not ok then return false end
    St.current = {}
    for _, r in ipairs(rows) do
        local id = tonumber(r.admission_id)
        local a = A.ById(id)
        if a and holdsBed(a) and not St.current[id] then
            St.current[id] = { id = tonumber(r.id), dept = r.dept, level = r.level, bed = r.bed_id, started_at = tonumber(r.started_at) }
        else
            local okA, adm = pcall(Q.StayAdmissionEnd, id)
            local ended = okA and adm and tonumber(adm.discharged_at) or at
            pcall(Q.StayEnd, tonumber(r.id), math.max(ended, tonumber(r.started_at) or ended))
        end
    end
    A.Each(function(a)
        if holdsBed(a) then
            local cur = St.current[a.id]
            if cur and cur.dept ~= a.dept then St.Close(a.id, at) cur = nil end
            if not cur then St.Open(a, a.dept, a.admitted_at or at, nil) end
        end
    end)
    return true
end

-- bill lines: one per stay, per started hour, replacing 17E's single "Bed, <dept>" line
if H.Billing and H.Billing.Lines then
    local lines = H.Billing.Lines
    H.Billing.Lines = function(a)
        local out, err = lines(a)
        if not out then return out, err end
        local ok, rows = pcall(Q.StaysFor, a.id)
        if not ok then return nil, 'db_unavailable' end
        if #rows == 0 then return out end
        local kept = {}
        for _, l in ipairs(out) do
            if not (l.kind == 'bed' and tonumber(l.ref_id) == tonumber(a.id)) then kept[#kept + 1] = l end
        end
        local tariff = Config.Hospital.Tariff
        local closedAt = tonumber(a.discharged_at) or now()
        local mult = H.ServiceMultiplier and H.ServiceMultiplier(a) or 1
        for _, r in ipairs(rows) do
            local level, dept = r.level, r.dept
            local perHour = tonumber(tariff.BedHour[level]) or tonumber(tariff.BedHour[dept]) or 0
            local from = tonumber(r.started_at) or closedAt
            local to = tonumber(r.ended_at) or closedAt
            if perHour > 0 and to >= from then
                local hours = math.max(1, math.ceil((to - from) / 3600))
                local lv = Config.Hospital.Stays.Levels[level]
                local label = lv and ('%s (%s)'):format(lv.label, dept) or ('Bed, %s'):format(dept)
                kept[#kept + 1] = { kind = 'bed', ref_id = tonumber(r.id), label = label:sub(1, 96), qty = hours,
                    unit_price = math.floor(perHour * mult + 0.5) }
            end
        end
        return kept
    end
end

if H.Billing and H.Billing.ForAdmission then
    local forAdmission = H.Billing.ForAdmission
    H.Billing.ForAdmission = function(a, ctx)
        local id = forAdmission(a, ctx)
        if id and a and a.id then pcall(Q.StaySetBill, a.id, id) end
        return id
    end
end

-- ── surgery ───────────────────────────────────────────────────────────────────────────────────

--- Waits on the server for the operation (specs replace it).
function Su.WaitFor(seconds)
    if seconds and seconds > 0 then Wait(math.floor(seconds * 1000)) end
end

--- The operating room a position is in, or nil.
function Su.RoomAt(pos)
    if not pos then return nil end
    for _, room in ipairs(cfg().Rooms or {}) do
        if H.Dist(pos, room.coords) <= (tonumber(room.radius) or 3.0) then return room end
    end
    return nil
end

local function treats(inj, procedure)
    local def = PFMed.Injuries.Types[inj.type]
    for _, t in ipairs(def and def.treatBy or {}) do if t == procedure then return true end end
    return false
end

--- Every requirement of the operation now. Returns ctx | nil, code, message.
function Su.Check(src, target, injuryId, procedure)
    local P, tierOrErr, msg = H.Provider(src, nil, 1)
    if not P then return nil, tierOrErr, msg end
    if not H.IsSurgeon(P) then return nil, 'no_permission', 'Only a surgeon operates.' end
    local room = Su.RoomAt(H.Pos(src))
    if not room then return nil, 'too_far', 'Operate in an operating room.' end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T then return nil, 'offline', 'Patient not found.' end
    if target == src then return nil, 'bad_args', 'Not on yourself.' end
    local cid = T.PlayerData.citizenid
    local a = A.OpenOf(cid)
    if not a or a.hospital_id ~= room.hospital then return nil, 'invalid_state', 'The patient is not admitted here.' end
    local bed = H.Beds.PatientInBed(target)
    if not bed or bed.admissionId ~= a.id then return nil, 'invalid_state', 'The patient must lie in their bed.' end
    local b = H.Beds.Def(a.hospital_id, a.bed_id)
    if not b or H.Dist(b.coords, room.coords) > (tonumber(room.radius) or 3.0) then return nil, 'invalid_state', 'The patient\'s bed is not in the operating room.' end
    local down, level = PFMed.Engine.IsDown(cid)
    if down and (level == 'arrest' or level == 'dead') then return nil, 'invalid_state', 'Resuscitate the patient first.' end
    local Dx = PFMed.Diagnosis
    if not Dx.HasDiagnosis(cid, { injuryId = injuryId, statuses = { confirmed = true } }) then
        return nil, 'invalid_state', 'Surgery needs a confirmed diagnosis of that injury (imaging or labs).'
    end
    local p = PFMed.Store.Get(cid)
    local inj = p and p.injuries[injuryId]
    if not inj or inj.stage == 'recovered' then return nil, 'invalid_state', 'That injury needs no operation any more.' end
    if type(inj.treatments) == 'table' and inj.treatments.surgery then return nil, 'invalid_state', 'That injury was already operated on.' end
    if not treats(inj, procedure) then return nil, 'bad_args', 'That operation does not treat this injury.' end
    return { P = P, room = room, psrc = target, cid = cid, a = a, inj = inj }
end

--- The payload for the retained projectile of a gunshot wound not recovered yet, or nil. The
--- shape is pfm-policejob lab.lua L.OnProjectileRecovered's (which also checks that this resource
--- raised the event): { injuryId, caliber, weaponHash, attackerCid?, weaponSerial?, byCid, at }.
--- The engine records no weapon serial, so weaponSerial is never sent.
function Su.ProjectileOf(inj, byCid, at)
    local attrs = type(inj.attrs) == 'table' and inj.attrs or {}
    if inj.type ~= 'gunshot' or not (inj.subtype == 'retained' or attrs.projectile) or attrs.projectileRecovered then return nil end
    return { injuryId = inj.id, caliber = attrs.caliber, weaponHash = attrs.weapon, attackerCid = inj.source_attacker_cid, byCid = byCid, at = at }
end

function Su.Operate(src, target, injuryId, procedure)
    if H.Limited(src, 'surgery', 2) then return H.Fail('rate_limited', 'Slow down.') end
    if type(procedure) ~= 'string' or not cfg().Procedures[procedure] then return H.Fail('bad_args', 'Unknown operation.') end
    injuryId = H.Int(injuryId, 1)
    if not injuryId then return H.Fail('bad_args', 'Name the injury (from its confirmed diagnosis).') end
    local ctx, code, msg = Su.Check(src, target, injuryId, procedure)
    if not ctx then return H.Fail(code, msg) end
    local def = cfg().Procedures[procedure]
    local surgeonCid = ctx.P.PlayerData.citizenid
    local res, err = H.WithLock('surg:' .. ctx.cid, function()
        local at = now()
        local okO, orderId = pcall(Q.OrdInsert, { citizenid = ctx.cid, admission_id = ctx.a.id, hospital_id = ctx.a.hospital_id, kind = 'procedure',
            test = procedure, state = 'in_progress', ordered_by = surgeonCid, done_by = surgeonCid, ordered_at = at, ready_at = at + def.seconds })
        orderId = okO and tonumber(orderId) or nil
        if not orderId then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        Su.WaitFor(def.seconds)
        local again, code2, msg2 = Su.Check(src, target, injuryId, procedure)
        if not again or again.cid ~= ctx.cid then
            pcall(Q.OrdCancel, orderId)
            return H.Fail(code2 or 'invalid_state', 'The operation was interrupted: ' .. tostring(msg2 or 'the patient changed'))
        end
        local t = now()
        local inj = again.inj
        local recovered = Su.ProjectileOf(inj, surgeonCid, t)
        local patch = { bleed_ml_min = 0, treatments = { surgery = t, [procedure] = t } }
        if inj.stage == 'injured' or inj.stage == 'complicated' then patch.stage = 'stabilized' end
        if recovered then patch.attrs = { projectileRecovered = t } end
        local actor = H.ActorOf(src, again.P)
        local updated, uerr = PFMed.Engine.UpdateInjury(ctx.cid, injuryId, patch, { actor = actor, source = 'surgery' })
        if not updated then
            pcall(Q.OrdCancel, orderId)
            return H.Fail(uerr or 'db_unavailable', 'The patient record could not be updated.')
        end
        -- raised once: the injury now carries projectileRecovered (PJ keys the evidence on the injury id too)
        if recovered then TriggerEvent('pf-ambulancejob:server:projectileRecovered', ctx.cid, recovered) end
        local job = again.P.PlayerData.job and again.P.PlayerData.job.name or nil
        local okT, txId = pcall(Q.SuInsertTreatment, { citizenid = ctx.cid, injury_id = injuryId, action = procedure, by_cid = surgeonCid,
            by_job = job and tostring(job):sub(1, 32) or nil, admission_id = ctx.a.id, at = t,
            params = recovered and json.encode({ projectile = true }) or nil })
        txId = okT and tonumber(txId) or nil
        local result = { procedure = procedure, injuryId = injuryId, projectileRecovered = recovered ~= nil, room = ctx.room.id }
        pcall(Q.OrdResult, orderId, json.encode(result), t)
        PFMed.Diagnosis.NoteCare(ctx.cid, surgeonCid, t)
        H.Audit(ctx.cid, 'surgery', actor, { order = orderId, procedure = procedure, injury = injuryId, projectile = recovered ~= nil or nil, tx = txId })
        TriggerEvent('pf-ambulancejob:server:treatmentApplied', ctx.cid, { id = txId, action = procedure, byCid = surgeonCid, at = t, injuryId = injuryId,
            result = 'ok' })
        local R = PFMed.Recovery
        if R and H.Callable(R.Advance) then pcall(R.Advance, ctx.cid, t) end
        if PFMed.Effects and H.Callable(PFMed.Effects.Push) then pcall(PFMed.Effects.Push, ctx.psrc) end
        H.Notify(ctx.psrc, 'The operation is done.', 'success')
        return { ok = true, orderId = orderId, treatmentId = txId, projectileRecovered = recovered ~= nil }
    end)
    if res == nil then return H.Fail(err or 'busy', 'The patient is already being operated on.') end
    return res
end

-- ── callbacks, commands, lifecycle ────────────────────────────────────────────────────────────

local callback = H.ServiceCallback
callback('surgery', function(src, target, injuryId, procedure) return Su.Operate(src, target, injuryId, procedure) end)
callback('careLevel', function(src, admissionId, level) return St.SetLevel(src, admissionId, level) end)

local function reply(src, res, okText)
    if res and res.ok then H.Notify(src, okText, 'success') else H.Notify(src, (res and res.message) or 'Refused.', 'error') end
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if type(citizenid) ~= 'string' or not (PFMed.Schema and PFMed.Schema.Ready()) then return end
    pcall(Q.StayDeleteCharacter, citizenid)
end)

CreateThread(function()
    local QB = PFAmbulance.GetCore()
    if QB.Commands and QB.Commands.Add then
        QB.Commands.Add('hsurgery', 'Hospital: operate (surgery_trauma, surgery_ortho, surgery_neuro, surgery_burn)', { { name = 'id', help = 'Player id' },
            { name = 'injury', help = 'Injury number (confirmed diagnosis)' }, { name = 'procedure', help = 'Operation' } }, true, function(source, args)
            local res = Su.Operate(source, args[1], args[2], tostring(args[3] or ''):lower())
            reply(source, res, res.ok and (res.projectileRecovered and 'Operation done; the projectile went to the evidence locker.' or 'Operation done.') or '')
        end)
        QB.Commands.Add('hcare', 'Hospital: care level of a bed patient (icu, standard)', { { name = 'id', help = 'Player id' }, { name = 'level', help = 'icu or standard' } }, true, function(source, args)
            local P = H.Player(H.Int(args[1], 1))
            local a = P and A.OpenOf(P.PlayerData.citizenid)
            if not a then return H.Notify(source, 'That patient has no open admission.', 'error') end
            reply(source, St.SetLevel(source, a.id, tostring(args[2] or ''):lower()), 'Care level set.')
        end)
    end
    if PFMed and PFMed.Schema and PFMed.Schema.OnReady then
        PFMed.Schema.OnReady(function()
            -- after 17E's own start (registered first); rebuilt from the open admissions
            if A.Ready() then St.Start(now()) end
        end)
    end
end)
