-- Low-population AI care (batch 17E, architecture 4.5.2, owner decision D17).
--
-- The hospital AI takes a waiting patient only when BOTH hold: fewer than AI.MinStaff staff are on
-- duty, and no medic accepted the patient (Dispatch request, triage or admit) within
-- AI.WaitSeconds of arrival. While two or more medics are on duty a patient waits for them. The AI
-- then works at TimeMultiplier speed and PriceMultiplier price (the bill marks AI mode), only while
-- the patient lies in their bed, never revives anyone (a down patient needs a medic or the respawn
-- rule), and leaves the injuries 'stabilized' with restrictions: bleeding stopped and fractures
-- splinted, but the definitive care (sutures, casts, reductions) is a medic's job, so EMS stays
-- worth calling. Surgery-required injuries wait for a player surgeon while one is on duty; after
-- AI.SurgeryWaitSeconds with none on duty the AI operates, with a complication chance.
--
-- Every step is a named function (AI.Tick) so specs drive it; the thread only calls it.

PFHospital = PFHospital or {}
local H = PFHospital
H.AI = H.AI or {}
local AI = H.AI
H.SQL = H.SQL or {}
local Q = H.SQL

local function cfg() return Config.Hospital end
local function aiCfg() return Config.Hospital.AI end
local now = function() return H.Now() end
local SYSTEM = { kind = 'system', label = 'ai_care' }

AI.Random = function() return math.random() end

function Q.InsertTreatment(r)
    return MySQL.insert.await([[INSERT INTO pf_med_treatments (citizenid, injury_id, action, params, items, by_cid, by_job, location,
        admission_id, call_ref, req, result, at) VALUES (?, ?, ?, ?, NULL, NULL, 'ai_care', 'hospital', ?, NULL, NULL, ?, ?)]],
        { r.citizenid, r.injury_id, r.action, r.params and json.encode(r.params) or nil, r.admission_id, r.result or 'ok', r.at })
end

-- ── which injuries the AI may treat ───────────────────────────────────────────────────────────

local function typeDef(inj)
    local I = PFMed and PFMed.Injuries
    return I and I.Types and I.Types[inj.type] or nil
end

--- Needs surgery: every listed care is surgery, or a surgery option exists and the injury is bad.
function AI.NeedsSurgery(inj)
    local def = typeDef(inj)
    local list = def and def.treatBy or {}
    local any, all = false, #list > 0
    for _, t in ipairs(list) do
        if tostring(t):find('^surgery') then any = true else all = false end
    end
    if inj.treatments and inj.treatments.surgery then return false end
    return all or (any and (tonumber(inj.severity) or 0) >= (aiCfg().SurgerySeverityMin or 4))
end

local function openInjuries(p)
    local out = {}
    for id, inj in pairs(p and p.injuries or {}) do
        if inj.stage ~= 'recovered' then out[#out + 1] = inj end
    end
    table.sort(out, function(x, y) return (tonumber(x.id) or 0) < (tonumber(y.id) or 0) end)
    return out
end

local function needsCare(inj)
    return inj.stage == 'injured' or inj.stage == 'complicated' or (tonumber(inj.bleed_ml_min) or 0) > 0
end

--- Seconds the AI needs for this patient (TimeMultiplier included).
function AI.Duration(cid)
    local c = aiCfg()
    local p = PFMed.Store.Peek(cid)
    local n = 0
    for _, inj in ipairs(openInjuries(p)) do
        if needsCare(inj) and not AI.NeedsSurgery(inj) then n = n + 1 end
    end
    return math.floor(((c.BaseSeconds or 30) + (c.PerInjurySeconds or 20) * n) * (c.TimeMultiplier or 2))
end

-- ── decisions ─────────────────────────────────────────────────────────────────────────────────

--- Whether the AI may take this admission now (the D17 rule). Returns ok, why.
function AI.MayTake(a, at, staff)
    if a.mode == 'ai' then return false, 'already' end
    if a.staffActed then return false, 'staff' end
    if staff >= (aiCfg().MinStaff or 2) then return false, 'staffed' end
    if at - (a.arrived_at or at) < (aiCfg().WaitSeconds or 180) then return false, 'waiting' end
    if H.Admissions.RequestAccepted(a) then return false, 'accepted' end
    return true
end

local function patientReady(a)
    local src = H.SourceOfCid(a.citizenid)
    if not src then return nil, 'offline' end
    if not H.Facility.InFacility(src, a.hospital_id) then return nil, 'away' end
    if PFMed.Down.IsDown(src) then return nil, 'down' end
    return src
end

--- The AI takes the patient: a bed in the respawn department (the ED), mode 'ai'.
function AI.Take(a, at)
    local src, why = patientReady(a)
    if not src then return false, why end
    return H.Admissions.WithAdmission(a.id, function(adm)
        local f = H.Facility.Get(adm.hospital_id)
        local dept = adm.dept and f.departments[adm.dept] and adm.dept or f.respawnDept
        local bed = adm.bed_id or H.Beds.FindFree(adm.hospital_id, dept)
        if not bed then
            if not adm.toldNoBed then
                adm.toldNoBed = true
                H.Notify(src, 'Every bed is taken; the hospital AI sees you as soon as one is free.', 'error')
            end
            return { ok = false, error = 'conflict' }
        end
        local _, bedDept = H.Beds.Def(adm.hospital_id, bed)
        H.Beds.Claim(adm.hospital_id, bed, adm.citizenid, adm.id)
        local triage = adm.triage or H.Admissions.AutoTriage(adm.citizenid)
        local moved = H.Admissions.Move(adm, 'in_treatment', { mode = 'ai', bed_id = bed, dept = bedDept, triage = triage,
            triaged_at = adm.triaged_at or at, admitted_at = at }, SYSTEM, { ai = true })
        if not moved then
            if bed ~= adm.bed_id then H.Beds.Release(adm.hospital_id, bed, adm.id) end
            return { ok = false, error = 'invalid_state' }
        end
        adm.aiDoneAt, adm.aiLast, adm.aiStabilized, adm.noSurgeonSince = at + AI.Duration(adm.citizenid), at, nil, nil
        H.Admissions.CloseRequest(adm, 'cancelled', 'ai_care')
        H.Beds.SendEnter(src, adm.hospital_id, bed)
        H.Notify(src, ('No medic is available: the hospital AI treats you (about %d s, at the AI rate). Stay in bed.'):format(adm.aiDoneAt - at), 'primary')
        return { ok = true }
    end).ok == true
end

local function inBed(src, a)
    local b = H.Beds.Def(a.hospital_id, a.bed_id or '')
    return b ~= nil and H.Dist(H.Pos(src), b.coords) <= (aiCfg().BedDistance or 3.0)
end

local function logTreatment(a, injuryId, action, at, params)
    pcall(Q.InsertTreatment, { citizenid = a.citizenid, injury_id = injuryId, action = action, admission_id = a.id, result = 'ok', at = at, params = params })
end

--- Flags a stabilised injury carries so the engine and the recovery module see it as stable.
local function stabilizeFlags(inj, at)
    local flags = { ai_care = at }
    local def = typeDef(inj)
    local map = Config.Medical and Config.Medical.Recovery and Config.Medical.Recovery.TreatmentFlags or {}
    for _, t in ipairs(def and def.stabilizeBy or {}) do
        flags[t] = at
        if map[t] then flags[map[t]] = at end
    end
    return flags
end

--- Non-surgical care: bleeding stopped, stabilisers applied, stage 'stabilized'. Returns count.
function AI.Stabilize(a, at)
    local p = PFMed.Store.Get(a.citizenid)
    if not p then return 0 end
    local n = 0
    for _, inj in ipairs(openInjuries(p)) do
        if needsCare(inj) and not AI.NeedsSurgery(inj) then
            local patch = { bleed_ml_min = 0, treatments = stabilizeFlags(inj, at) }
            if inj.stage == 'injured' or inj.stage == 'complicated' then patch.stage = 'stabilized' end
            if PFMed.Engine.UpdateInjury(a.citizenid, inj.id, patch, { actor = SYSTEM, source = 'ai_care' }) then
                logTreatment(a, inj.id, 'ai_stabilize', at)
                n = n + 1
            end
        end
    end
    return n
end

--- Surgery by the AI (no surgeon on duty for SurgeryWaitSeconds), with a complication chance.
function AI.Surgery(a, at)
    local p = PFMed.Store.Get(a.citizenid)
    if not p then return 0 end
    local n = 0
    for _, inj in ipairs(openInjuries(p)) do
        if AI.NeedsSurgery(inj) then
            local complication = AI.Random() < (aiCfg().SurgeryComplicationChance or 0.15)
            local flags = stabilizeFlags(inj, at)
            flags.surgery, flags.ai_surgery = at, at
            if complication then flags.ai_complication = at end
            local patch = { bleed_ml_min = 0, treatments = flags }
            if inj.stage == 'injured' or inj.stage == 'complicated' then patch.stage = 'stabilized' end
            if complication then patch.severity = math.min(5, (tonumber(inj.severity) or 1) + 1) end
            if PFMed.Engine.UpdateInjury(a.citizenid, inj.id, patch, { actor = SYSTEM, source = 'ai_care' }) then
                logTreatment(a, inj.id, 'ai_surgery', at, complication and { complication = true } or nil)
                n = n + 1
            end
        end
    end
    return n
end

--- Discharge restrictions for what the AI left stabilised: the recovery module's injury rules
--- (Config.Medical.Recovery.InjuryRestrictions), lasting the injury's heal time.
function AI.Restrictions(cid, at)
    local p = PFMed.Store.Peek(cid)
    local rules = Config.Medical and Config.Medical.Recovery and Config.Medical.Recovery.InjuryRestrictions or {}
    local A = PFMed.Anatomy
    local byKind = {}
    for _, inj in ipairs(openInjuries(p)) do
        local def = typeDef(inj)
        local heal = def and def.healSeconds and def.healSeconds[tonumber(inj.severity) or 1] or 3600
        local untilAt = at + math.floor(heal * (aiCfg().RestrictionHealFactor or 1))
        local region = A and A.Regions and A.Regions[inj.region or '']
        local group = region and region.group or nil
        local groupKind = group and A.GroupKind[group] or nil
        local side = group and group:match('_([lr])$') or 'l'
        for _, rule in ipairs(rules) do
            if rule.types[inj.type] and (not rule.groups or (groupKind and rule.groups[groupKind]))
                and (tonumber(inj.severity) or 0) >= (rule.minSeverity or 1) then
                for _, kind in ipairs(rule.kinds) do
                    kind = kind:gsub('<side>', side)
                    if cfg().Discharge.RestrictionKinds[kind] and (not byKind[kind] or byKind[kind].untilAt < untilAt) then
                        byKind[kind] = { kind = kind, untilAt = untilAt, reason = rule.reason or 'Injury', injuryId = inj.id }
                    end
                end
            end
        end
    end
    local list = {}
    for _, r in pairs(byKind) do list[#list + 1] = r end
    table.sort(list, function(x, y) return x.kind < y.kind end)
    return list
end

function AI.Discharge(a, at)
    return H.Admissions.WithAdmission(a.id, function(adm)
        local orders = { restrictions = AI.Restrictions(adm.citizenid, at), followUpAt = at + (aiCfg().FollowUpSeconds or 86400),
            note = 'Follow-up after AI care: see a medic for the definitive treatment of your injuries.' }
        local done, err = H.Admissions.Close(adm, 'discharged', { actor = SYSTEM, orders = orders, reason = 'ai_care' })
        return { ok = done ~= nil, error = err }
    end).ok == true
end

--- One AI step for an admission in AI care.
function AI.Step(a, at)
    local src = patientReady(a)
    local dt = math.max(0, at - (a.aiLast or at))
    a.aiLast = at
    if not a.aiDoneAt then a.aiDoneAt = math.max(at, (a.admitted_at or at) + AI.Duration(a.citizenid)) end
    if not src or not inBed(src, a) then
        -- the clock only runs while the patient lies in their bed
        a.aiDoneAt = a.aiDoneAt + dt
        return 'paused'
    end
    if at < a.aiDoneAt then return 'working' end
    if not a.aiStabilized then
        local ok = H.Admissions.WithAdmission(a.id, function(adm)
            if adm.mode ~= 'ai' then return { ok = false } end
            AI.Stabilize(adm, at)
            adm.aiStabilized = true
            return { ok = true }
        end)
        if not ok.ok then return 'skip' end
    end
    local p = PFMed.Store.Peek(a.citizenid)
    local surgical = false
    for _, inj in ipairs(openInjuries(p)) do if AI.NeedsSurgery(inj) then surgical = true break end end
    if not surgical then
        return AI.Discharge(a, at) and 'discharged' or 'skip'
    end
    if H.SurgeonOnDuty() then
        -- a player surgeon is on duty: the patient waits for them (and the Dispatch app shows it)
        a.noSurgeonSince = nil
        if not a.surgeryCalled then
            a.surgeryCalled = true
            H.Admissions.OpenRequest(a)
            H.Notify(src, 'You need surgery: a surgeon has been called.', 'primary')
        end
        return 'awaiting_surgeon'
    end
    a.noSurgeonSince = a.noSurgeonSince or at
    if at - a.noSurgeonSince < (aiCfg().SurgeryWaitSeconds or 900) then return 'awaiting_surgeon' end
    local done = H.Admissions.WithAdmission(a.id, function(adm)
        if adm.mode ~= 'ai' then return { ok = false } end
        AI.Surgery(adm, at)
        return { ok = true }
    end)
    if not done.ok then return 'skip' end
    return AI.Discharge(a, at) and 'discharged' or 'skip'
end

--- One pass over open admissions (named for specs).
function AI.Tick(at)
    at = at or now()
    local staff = H.StaffOnDuty()
    local out = {}
    H.Admissions.Each(function(a)
        if a.mode == 'ai' then
            out[a.id] = AI.Step(a, at)
        elseif AI.MayTake(a, at, staff) then
            out[a.id] = AI.Take(a, at) and 'taken' or 'not_taken'
        end
    end)
    return out
end

CreateThread(function()
    while true do
        Wait((aiCfg().TickSeconds or 10) * 1000)
        if H.Admissions and H.Admissions.Ready() then
            local ok, err = pcall(AI.Tick, now())
            if not ok then print('^1[pf-ambulancejob]^7 hospital AI tick failed: ' .. tostring(err)) end
        end
    end
end)
