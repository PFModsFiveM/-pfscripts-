-- Exam actions (architecture 4.2, 6.2-6.4): callback pf-ambulancejob:server:exam(target, modality)
-- and the read-only pf-ambulancejob:server:examOptions(target) the client menu is built from.
--
-- Order of checks (stop at the first failure): source and rate limit -> arguments -> provider and
-- patient online -> provider tier for the modality -> server distance -> location (hospital, or an
-- imaging room with the patient in a server-held bed) -> instrument (item held, rig within 10 m or
-- the hospital) -> the same exam within 60 s returns the stored result -> per-exam lock (before any
-- database wait) -> the exam takes its time on the server -> everything re-checked -> findings
-- rolled, stored, audited.
--
-- The client's progress bar is only a picture: the server waits the modality's seconds itself and
-- re-checks distance and duty afterwards, so a shortened bar or a teleport gains nothing.

PFMed = PFMed or {}
PFMed.Exam = PFMed.Exam or {}
local Exam = PFMed.Exam
local F = PFMed.Findings

local function Dx() return PFMed.Diagnosis end
local function Store() return PFMed.Store end
local function now() return os.time() end
local function fail(code, message) return Dx().Fail(code, message) end

-- ── waits (specs replace Exam.WaitFor; CreateThread/Wait do nothing in the harness) ───────────

function Exam.WaitFor(seconds)
    if seconds and seconds > 0 then Wait(math.floor(seconds * 1000)) end
end

-- ── places and instruments ─────────────────────────────────────────────────────────────────────

local function hospitalApi()
    local H = PFHospital
    return type(H) == 'table' and H or nil
end

--- Hospitals as { id, coords, radius }: 17E's facility zones (Config.Hospital.Facilities) when
--- present, else the legacy Config.Locations hospital points.
function Exam.Hospitals()
    local out = {}
    local H = Config.Hospital
    if type(H) == 'table' and type(H.Facilities) == 'table' then
        for id, f in pairs(H.Facilities) do
            local z = type(f) == 'table' and f.zone or nil
            local c = z and (z.center or z.coords) or (type(f) == 'table' and (f.coords or f.location)) or nil
            if c and c.x then out[#out + 1] = { id = id, coords = c, radius = tonumber(z and z.radius) or F.HospitalRadius } end
        end
        if #out > 0 then return out end
    end
    local list = Config.Locations and Config.Locations['hospital'] or {}
    for i, h in ipairs(list) do
        local c = h['location']
        if c and c.x then out[#out + 1] = { id = i, coords = c, radius = F.HospitalRadius } end
    end
    return out
end

--- The hospital a position is in (17E PFHospital.Facility.At when loaded), or nil.
function Exam.InHospital(pos)
    if not pos then return nil end
    local H = hospitalApi()
    if H and type(H.Facility) == 'table' and Dx().Callable(H.Facility.At) then return H.Facility.At(pos) end
    for _, h in ipairs(Exam.Hospitals()) do
        if Dx().Dist(pos, h.coords) <= h.radius then return h.id end
    end
    return nil
end

function Exam.ImagingZones()
    local H = Config.Hospital
    if type(H) == 'table' and type(H.ImagingZones) == 'table' and #H.ImagingZones > 0 then return H.ImagingZones end
    return F.ImagingZones
end

function Exam.InImagingZone(pos)
    if not pos then return nil end
    for _, z in ipairs(Exam.ImagingZones()) do
        if z.coords and Dx().Dist(pos, z.coords) <= (tonumber(z.radius) or 4.0) then return z end
    end
    return nil
end

--- Whether the patient lies in a server-held bed of an imaging department. With 17E loaded its
--- PFHospital.Beds.PatientInBed decides (bed held, patient within reach of it, department
--- `imaging = true`); otherwise an imaging zone plus an admission that holds a bed.
--- Returns ok, message.
function Exam.InImagingBed(patientSrc, cid, pos)
    local H = hospitalApi()
    if H and type(H.Beds) == 'table' and Dx().Callable(H.Beds.PatientInBed) then
        local bed = H.Beds.PatientInBed(patientSrc)
        if not bed then return false, 'The patient must lie in a hospital bed.' end
        if not bed.imaging then return false, 'The patient must be in the imaging room.' end
        return true
    end
    if not Exam.InImagingZone(pos) then return false, 'The patient must be in the imaging room.' end
    local a = Dx().Admission(cid)
    if not a or not Dx().BedAdmission[a.state] or not (a.bedId or a.bed_id) then
        return false, 'The patient must lie in a hospital bed.'
    end
    return true
end

local rigHashes
local function rigModels()
    if rigHashes then return rigHashes end
    rigHashes = {}
    for _, m in ipairs(F.RigModels) do rigHashes[GetHashKey(m)] = true end
    for _, grade in pairs(Config.AuthorizedVehicles or {}) do
        if type(grade) == 'table' then for model in pairs(grade) do rigHashes[GetHashKey(model)] = true end end
    end
    return rigHashes
end

--- An ambulance (by model) within `radius` of pos (server entities only).
function Exam.RigNear(pos, radius)
    if not pos or type(GetAllVehicles) ~= 'function' then return false end
    local models = rigModels()
    for _, veh in ipairs(GetAllVehicles() or {}) do
        if models[GetEntityModel(veh)] and Dx().Dist(GetEntityCoords(veh), pos) <= radius then return true end
    end
    return false
end

local function holds(src, items)
    for _, name in ipairs(items or {}) do
        local ok, has = pcall(function() return exports['pfm-inventory']:HasItem(src, name, 1) end)
        if ok and has == true then return true end
    end
    return false
end

-- ── checks ─────────────────────────────────────────────────────────────────────────────────────

local function tierLabel(t) return (F.Tiers[t] and F.Tiers[t].label) or ('tier ' .. tostring(t)) end

--- Every requirement of a modality for provider -> patient now. Returns ctx or nil, code, message.
--- ctx = { provider, cid, patientSrc, def }.
function Exam.Check(src, target, modality)
    local def = F.Modalities[modality]
    if not def then return nil, 'bad_args' end
    if target == src then return nil, 'bad_args', 'You cannot examine yourself.' end
    local provider, perr = Dx().Provider(src)
    if not provider then return nil, perr end
    local cid, psrc = Dx().Patient(target)
    if not cid then return nil, psrc end
    if not psrc then return nil, 'offline' end
    if provider.tier < def.tier then
        return nil, 'no_permission', ('Needs %s or higher.'):format(tierLabel(def.tier))
    end
    local ppos, tpos = Dx().Coords(src), Dx().Coords(psrc)
    if not ppos or not tpos then return nil, 'not_found' end
    if Dx().Dist(ppos, tpos) > def.distance then return nil, 'too_far' end
    -- another routing bucket is another world, whatever the coordinates say
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(psrc) then return nil, 'too_far' end
    local hospital = Exam.InHospital(tpos)
    if def.location == 'hospital' and not hospital then
        return nil, 'invalid_state', 'The patient must be in a hospital.'
    end
    if def.location == 'imaging' then
        local okBed, why = Exam.InImagingBed(psrc, cid, tpos)
        if not okBed then return nil, 'invalid_state', why end
    end
    if def.equip then
        local okEquip = (def.items and not def.requireRigOrHospital and holds(src, def.items))
            or (def.equip.hospital and hospital ~= nil)
            or (def.equip.rig and Exam.RigNear(ppos, F.RigDistance))
        if not okEquip then
            local what = def.requireRigOrHospital and 'an ambulance nearby or a hospital' or ('a ' .. tostring(def.items and def.items[1] or 'instrument') .. ', an ambulance nearby or a hospital')
            return nil, 'invalid_state', 'Needs ' .. what .. '.'
        end
    end
    return { provider = provider, cid = cid, patientSrc = psrc, def = def }
end

-- ── stored results (60 s) and locks ────────────────────────────────────────────────────────────

local results = {}    -- [cid|modality|tier] = { at, findings, vitals }
local inflight = {}   -- [cid|modality|tier] = true while an exam rolls
local busy = {}       -- [src] = true while this provider examines

local function keyOf(cid, modality, tier) return cid .. '|' .. modality .. '|' .. tostring(tier) end

local function stored(key, at)
    local r = results[key]
    if r and at - r.at < F.CacheSeconds then return r end
    results[key] = nil
    return nil
end

local function prune(at)
    for k, r in pairs(results) do if at - r.at >= F.CacheSeconds then results[k] = nil end end
end

function Exam.Forget(src) busy[src] = nil end
function Exam.ClearResults() results = {} end

local function publicList(list)
    local out = {}
    for _, f in ipairs(list) do out[#out + 1] = Dx().PublicFinding(f) end
    return out
end

-- ── the exam ───────────────────────────────────────────────────────────────────────────────────

function Exam.Run(src, target, modality)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return fail('bad_args') end
    if Dx().Limited(src) then return fail('rate_limited') end
    modality = F.Modality(modality)
    target = math.tointeger(tonumber(target))
    if not modality or not target or target <= 0 then return fail('bad_args') end
    local ctx, code, msg = Exam.Check(src, target, modality)
    if not ctx then return fail(code, msg) end
    local provider, cid = ctx.provider, ctx.cid
    local at = now()
    local key = keyOf(cid, modality, provider.tier)

    local prior = stored(key, at)
    if prior then
        Dx().NoteCare(cid, provider.cid, at)
        Dx().Audit(cid, 'exam', provider, { modality = modality, tier = provider.tier, reused = true, n = #prior.findings })
        return { ok = true, modality = modality, findings = publicList(prior.findings), vitals = prior.vitals, at = prior.at, reused = true }
    end
    if busy[src] then return fail('busy', 'You are already examining someone.') end
    if inflight[key] then return fail('busy', 'This exam is already being done.') end
    -- locks first: everything below may wait on the database or the exam's time
    busy[src], inflight[key] = true, true
    local ok, res = pcall(function()
        if not Store().Ready() then return fail('db_unavailable') end
        local p, err = Store().Get(cid)
        if not p then return fail(err or 'db_unavailable') end
        Exam.WaitFor(ctx.def.seconds)
        -- the provider must still be there, on duty and allowed after the exam's time
        local again, code2, msg2 = Exam.Check(src, target, modality)
        if not again then return fail(code2, msg2) end
        if again.provider.tier ~= provider.tier or again.cid ~= cid then return fail('invalid_state') end
        local t = now()
        p = Store().Peek(cid) or p
        local list, vitals = Dx().Generate(p, modality, provider.tier, t)
        local saved, rerr = Dx().Record(cid, list, provider, t)
        if not saved then return fail(rerr or 'db_unavailable') end
        prune(t)
        results[key] = { at = t, findings = saved, vitals = vitals }
        Dx().NoteCare(cid, provider.cid, t)
        Dx().Audit(cid, 'exam', provider, { modality = modality, tier = provider.tier, n = #saved })
        return { ok = true, modality = modality, findings = publicList(saved), vitals = vitals, at = t }
    end)
    busy[src], inflight[key] = nil, nil
    if not ok then
        print('^1[pf-ambulancejob]^7 exam failed: ' .. tostring(res))
        return fail('db_unavailable')
    end
    return res
end

--- What the provider could do on this patient now: { ok, tier, modalities = { { id, label,
--- seconds, available, reason? } } }. Read-only: nothing is rolled or stored.
function Exam.Options(src, target)
    src = math.tointeger(tonumber(src))
    target = math.tointeger(tonumber(target))
    if not src or src <= 0 or not target or target <= 0 then return fail('bad_args') end
    if Dx().Limited(src) then return fail('rate_limited') end
    local provider, perr = Dx().Provider(src)
    if not provider then return fail(perr) end
    local out = {}
    for _, id in ipairs(F.Ordered()) do
        local def = F.Modalities[id]
        local ctx, code, msg = Exam.Check(src, target, id)
        out[#out + 1] = { id = id, label = def.label, seconds = def.seconds, tier = def.tier, available = ctx ~= nil,
            reason = ctx == nil and (msg or code) or nil }
        if not ctx and (code == 'not_found' or code == 'offline' or code == 'bad_args') then return fail(code, msg) end
    end
    return { ok = true, tier = provider.tier, tierLabel = tierLabel(provider.tier), modalities = out }
end

PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:exam', function(source, cb, target, modality)
    cb(Exam.Run(source, target, modality))
end)

PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:examOptions', function(source, cb, target)
    cb(Exam.Options(source, target))
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
end)
