-- Diagnosis layer (architecture 4.2, 6.6, 11.6): turns the true patient state into what an exam
-- finds, records findings and diagnoses, and serves the chart and the medical record.
--
--   * Findings come only from real injuries and the real physiology (shared/medical/findings.lua):
--     a sign is found with the tier's sensitivity; a miss leaves nothing (never a false finding).
--   * Only xray, ct and labs confirm; a confirmed finding on an injury writes a confirmed diagnosis
--     (source imaging/lab). Providers may only suspect or rule out (setDiagnosis, tier >= 2).
--   * Charts and records never hand out pf_med_injuries rows as they are: the chart shows findings,
--     diagnoses, the treatment log and measured vitals; the record lists injuries a provider
--     documented (found, confirmed or treated), without attacker or weapon details.
--   * Privacy (6.6): the patient sees their own record; on-duty medical staff see a patient they
--     are with (attending distance), examined or treated in the last 24 h, or who is admitted;
--     physicians (tier 5) see every record; anyone else needs a valid court order. Every read
--     through getChart and GetMedicalRecord writes a pf_med_events 'record_read' row.
--
-- Provides: callbacks pf-ambulancejob:server:setDiagnosis, pf-ambulancejob:server:getChart; export
-- GetMedicalRecord; internal PFMed.Diagnosis.ProviderTier / Generate / Record / HasFinding /
-- HasDiagnosis / CanSeeChart (17B treatment preconditions read HasFinding).

PFMed = PFMed or {}
PFMed.Diagnosis = PFMed.Diagnosis or {}
PFMed.SQL = PFMed.SQL or {}
local Dx, Q = PFMed.Diagnosis, PFMed.SQL
local F = PFMed.Findings

local DAY = 86400
Dx.AttendDistance = 10.0     -- a provider this close to the patient is with them (on the call)
Dx.CareSeconds = DAY          -- examined/treated within this long keeps chart access
Dx.TierCacheSeconds = 30
Dx.Random = math.random       -- specs replace it to make rolls deterministic

-- Who may call GetMedicalRecord (architecture 4.1). config_medical.lua may set its own list.
Config.Medical = Config.Medical or {}
Config.Medical.Callers = Config.Medical.Callers or {}
if Config.Medical.Callers.GetMedicalRecord == nil then
    Config.Medical.Callers.GetMedicalRecord = { ['pf-emsmdt'] = true, ['pf-justice'] = true, ['pf-policemdt-DEV'] = true }
end

local MESSAGES = {
    bad_args = 'Invalid request.',
    not_allowed = 'This resource may not read medical records.',
    no_permission = 'You may not do that for this patient.',
    not_on_duty = 'You are not on duty.',
    too_far = 'You are too far from the patient.',
    not_found = 'Patient not found.',
    offline = 'The patient is not here.',
    invalid_state = 'Not possible right now.',
    busy = 'Already in progress.',
    rate_limited = 'Slow down.',
    db_unavailable = 'Medical records are unavailable right now.',
}
local function fail(code, message) return { ok = false, error = code, message = message or MESSAGES[code] or code } end
Dx.Fail = fail

local function now() return os.time() end
local function Store() return PFMed.Store end
local function Engine() return PFMed.Engine end

local function callable(v)
    if type(v) == 'function' then return true end
    local mt = type(v) == 'table' and getmetatable(v)
    return type(v) == 'table' and (rawget(v, '__cfx_functionReference') ~= nil or (type(mt) == 'table' and mt.__call ~= nil))
end
Dx.Callable = callable

local function cleanText(v, max)
    if v == nil then return nil end
    if type(v) ~= 'string' then return false end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

-- ── players, positions ─────────────────────────────────────────────────────────────────────────

function Dx.GetPlayer(src)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return nil end
    local ok, Player = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(Player) == 'table' and type(Player.PlayerData) == 'table' then return Player end
    return nil
end

function Dx.Coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function Dx.Dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Dx.IsOnDutyMedic(Player)
    local job = Player and Player.PlayerData and Player.PlayerData.job
    return type(job) == 'table' and (Config.AllowedJobs or { ambulance = true })[job.name] == true and job.onduty == true
end

-- ── rate limit (exam / diagnosis / chart: 2 per second, burst 4, per source) ──────────────────

local buckets = {}
function Dx.Limited(src)
    local t = GetGameTimer() / 1000
    local b = buckets[src]
    if not b then b = { tokens = 4, at = t }; buckets[src] = b end
    b.tokens = math.min(4, b.tokens + (t - b.at) * 2)
    b.at = t
    if b.tokens < 1 then return true end
    b.tokens = b.tokens - 1
    return false
end

-- ── provider tier (11.6) ───────────────────────────────────────────────────────────────────────

local tierCache = {}   -- [src] = { tier, at, cid, job, grade, duty }

-- One tier table for the whole resource: the hospital's (config_hospital.lua Tiers, used by
-- triage/admit) when present, else the catalogue's. Returns { { tier, qual } }, { [grade] = tier }.
local function tierTables()
    local T = type(Config.Hospital) == 'table' and Config.Hospital.Tiers or nil
    if type(T) == 'table' and type(T.Quals) == 'table' and #T.Quals > 0 then
        local list = {}
        for _, e in ipairs(T.Quals) do list[#list + 1] = { tonumber(e[2]) or 0, e[1] } end
        return list, type(T.GradeFallback) == 'table' and T.GradeFallback or F.GradeTier
    end
    return F.TierQuals, F.GradeTier
end

--- Tier 0..5 of a player now (0 = not an on-duty medic), and the player. Qualifications come from
--- pf-government (granted or implied by grade); without it the grade decides (F.GradeTier).
function Dx.ProviderTier(src, Player)
    Player = Player or Dx.GetPlayer(src)
    if not Player then return nil end
    if not Dx.IsOnDutyMedic(Player) then return 0, Player end
    local pd = Player.PlayerData
    local job = pd.job
    local grade = math.tointeger(tonumber(type(job.grade) == 'table' and job.grade.level or job.grade)) or 0
    local c = tierCache[src]
    local t = now()
    if c and c.cid == pd.citizenid and c.job == job.name and c.grade == grade and t - c.at < Dx.TierCacheSeconds then
        return c.tier, Player
    end
    local tier, answered = 0, false
    local quals, byGrade = tierTables()
    if GetResourceState('pf-government') == 'started' then
        for _, e in ipairs(quals) do
            local ok, has = pcall(function() return exports['pf-government']:HasQualification(pd.citizenid, e[2]) end)
            if ok then answered = true end
            if ok and has == true then tier = e[1] break end
        end
    end
    if not answered then tier = byGrade[grade] or (grade > 4 and 5 or 1) end
    tierCache[src] = { tier = tier, at = t, cid = pd.citizenid, job = job.name, grade = grade }
    return tier, Player
end

function Dx.ForgetTier(src) tierCache[src] = nil end

-- ── hospital context (17E owns admissions; read by contract through its export) ──────────────

local OPEN_ADMISSION = { arrived = true, checked_in = true, triaged = true, waiting = true, in_treatment = true, admitted = true }
local BED_ADMISSION = { in_treatment = true, admitted = true }
Dx.OpenAdmission, Dx.BedAdmission = OPEN_ADMISSION, BED_ADMISSION

--- The patient's open admission or nil: 17E's in-memory PFHospital.Admissions.OpenOf when loaded
--- (same resource), else its GetAdmission export.
function Dx.Admission(cid)
    local a
    local H = PFHospital
    if type(H) == 'table' and type(H.Admissions) == 'table' and callable(H.Admissions.OpenOf) then
        local ok, row = pcall(H.Admissions.OpenOf, cid)
        a = ok and type(row) == 'table' and row or nil
    else
        local ok, res = pcall(function() return exports[GetCurrentResourceName()]:GetAdmission(cid) end)
        if ok and type(res) == 'table' and res.ok == true and type(res.admission) == 'table' then a = res.admission end
    end
    if not a or not OPEN_ADMISSION[a.state] then return nil end
    return a
end

-- ── care relation and chart access (6.6) ───────────────────────────────────────────────────────

local recentCare = {}   -- [patientCid] = { [providerCid] = at } (memory; SQL answers after a restart)

function Dx.NoteCare(patientCid, providerCid, at)
    if not patientCid or not providerCid then return end
    at = at or now()
    local m = recentCare[patientCid]
    if not m then m = {}; recentCare[patientCid] = m end
    m[providerCid] = at
    for who, t in pairs(m) do if at - t > Dx.CareSeconds then m[who] = nil end end
end

function Q.DxCareFinding(cid, byCid, since)
    return MySQL.scalar.await('SELECT 1 FROM `pf_med_findings` WHERE `citizenid` = ? AND `by_cid` = ? AND `at` >= ? LIMIT 1', { cid, byCid, since })
end
function Q.DxCareTreatment(cid, byCid, since)
    return MySQL.scalar.await('SELECT 1 FROM `pf_med_treatments` WHERE `citizenid` = ? AND `by_cid` = ? AND `at` >= ? LIMIT 1', { cid, byCid, since })
end

--- Whether the provider examined or treated the patient within Dx.CareSeconds.
function Dx.HadCare(patientCid, providerCid, at)
    at = at or now()
    local since = at - Dx.CareSeconds
    local m = recentCare[patientCid]
    if m and m[providerCid] and m[providerCid] >= since then return true end
    if not Store().Ready() then return false end
    local ok, hit = pcall(Q.DxCareFinding, patientCid, providerCid, since)
    if ok and hit then return true end
    -- pf_med_treatments arrives with the batch-17 schema (v5); before that this simply finds nothing
    ok, hit = pcall(Q.DxCareTreatment, patientCid, providerCid, since)
    return ok and hit ~= nil and hit ~= false
end

--- Whether provider (src, cid, tier) may see the chart of patientCid (patientSrc when online).
--- Returns ok, reason ('physician' | 'attending' | 'admitted' | 'recent_care') or nil, error code.
function Dx.CanSeeChart(provider, patientCid, patientSrc)
    if not provider or (provider.tier or 0) < 1 then return nil, 'no_permission' end
    if provider.tier >= 5 then return true, 'physician' end
    if patientSrc and Dx.Dist(Dx.Coords(provider.src), Dx.Coords(patientSrc)) <= Dx.AttendDistance then return true, 'attending' end
    if Dx.Admission(patientCid) then return true, 'admitted' end
    if Dx.HadCare(patientCid, provider.cid) then return true, 'recent_care' end
    return nil, 'no_permission'
end

-- ── finding generation (pure on the patient object; rolls through Dx.Random) ────────────────

local RESPONSE = { alert = 'alert', altered = 'confused', unconscious = 'unresponsive', arrest = 'unresponsive', dead = 'unresponsive' }
local BLEED = { 'minor', 'moderate', 'severe', 'massive' }
local TOXIN_SENS = F.S(0, 0, 0.8, 0.85, 0.9, 0.95)

local function sortedInjuries(p)
    local list = {}
    for _, inj in pairs(p.injuries or {}) do
        if inj.stage ~= 'recovered' then list[#list + 1] = inj end
    end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return list
end

local function kindOf(structure)
    local s = PFMed.Anatomy.Structures[structure]
    return s and s.kind or nil
end

local function regionOf(inj)
    if inj.region and PFMed.Anatomy.IsRegion(inj.region) then return inj.region end
    if inj.structure then return PFMed.Anatomy.DefaultRegion(inj.structure) end
    return nil
end

local function roll(sens) return sens > 0 and Dx.Random() < sens end

--- Sensitivity after severity: worse injuries are easier to find (not for confirming tests).
local function adjusted(rule, tier, sev)
    local s = F.Sensitivity(rule, tier)
    if s <= 0 then return 0 end
    if rule.certainty == 'confirmed' then return s end
    s = s + ((tonumber(sev) or 3) - 3) * 0.03
    if s < 0.05 then s = 0.05 elseif s > 0.99 then s = 0.99 end
    return s
end

local function glucoseOf(p, v, at, c)
    local P = PFMed.Physiology
    local g = 95 - 25 * math.min(2, P.ToxinIntensity(p, 'ethanol', at, c))
    for _, inj in pairs(p.injuries or {}) do
        if inj.stage ~= 'recovered' and ((inj.type == 'illness' and inj.subtype == 'infection_sepsis') or (inj.type == 'infection' and inj.subtype == 'sepsis')) then
            g = g + 15 * (tonumber(inj.severity) or 1)
        end
    end
    if (v.shock or 0) >= 3 then g = g + 20 end
    return math.floor(math.max(30, math.min(400, g)) + 0.5)
end

--- What an exam of `modality` by a provider of `tier` finds on patient object p at time `at`.
--- Returns findings (list of { injuryId?, modality, region?, structure?, sign, certainty, value? })
--- and vitals (the measured values, for vital-sign modalities) or nil.
function Dx.Generate(p, modality, tier, at)
    at = at or now()
    local E = Engine()
    local c = PFMed.Physiology.Cfg(Config.Medical)
    local v = E.Vitals(p, at)
    local level = p.consciousness or 'alert'
    local down = level == 'arrest' or level == 'dead'
    local out, vitals = {}, nil
    local function add(f)
        if #out >= F.MaxFindings then return end
        f.modality = modality
        out[#out + 1] = f
    end

    -- measurements and gross observations: always true values, never rolled
    if modality == 'look' then
        add({ sign = 'responsiveness', certainty = 'observed', value = RESPONSE[level] or 'alert' })
        if down or v.rr == 0 then add({ sign = 'not_breathing', certainty = 'observed' }) end
        local lvl = E.BleedLevel(E.Bleeding(p, at, c).external)
        if lvl > 0 then add({ sign = 'external_bleeding', certainty = 'observed', value = BLEED[lvl] }) end
    elseif modality == 'pain_scale' then
        if level == 'alert' or level == 'altered' then
            local pain = math.floor((tonumber(v.pain) or 0) + 0.5)
            add({ sign = 'pain_score', certainty = 'observed', value = tostring(pain) })
            vitals = { pain = pain }
        else
            add({ sign = 'unresponsive', certainty = 'observed' })
        end
    elseif modality == 'pulse' then
        add({ sign = 'pulse', certainty = 'observed', value = down and 'absent' or tostring(v.hr) })
        add({ sign = 'respiratory_rate', certainty = 'observed', value = tostring(down and 0 or v.rr) })
        vitals = { hr = down and 0 or v.hr, rr = down and 0 or v.rr }
    elseif modality == 'bp_cuff' then
        local sbp, dbp = down and 0 or v.sbp, down and 0 or v.dbp
        add({ sign = 'blood_pressure', certainty = 'observed', value = sbp > 0 and (sbp .. '/' .. dbp) or 'unrecordable' })
        vitals = { sbp = sbp, dbp = dbp }
    elseif modality == 'spo2_probe' then
        add({ sign = 'spo2', certainty = 'observed', value = down and 'no_reading' or tostring(v.spo2) })
        vitals = { spo2 = down and 0 or v.spo2 }
    elseif modality == 'temperature' then
        add({ sign = 'temperature', certainty = 'observed', value = tostring(v.temp) })
        vitals = { temp = v.temp }
    elseif modality == 'glucose' then
        local g = glucoseOf(p, v, at, c)
        add({ sign = 'glucose', certainty = 'observed', value = tostring(g) })
        vitals = { glucose = g }
    elseif modality == 'ecg' then
        local rhythm = v.rhythm or 'sinus'
        add({ sign = 'rhythm', certainty = 'observed', value = rhythm })
        vitals = { hr = down and 0 or v.hr, rhythm = rhythm }
    elseif modality == 'labs' then
        local hb = 14.5 * (tonumber(p.hgb_factor) or 1) * (1 - 0.5 * (tonumber(v.lossFraction) or 0))
        add({ sign = 'hemoglobin', certainty = 'observed', value = tostring(math.floor(hb * 10 + 0.5) / 10) })
    end

    -- signs of the open injuries
    local foundToxin = {}
    for _, inj in ipairs(sortedInjuries(p)) do
        for _, rule in ipairs(F.RulesFor(inj.type, modality)) do
            if F.Applies(rule, inj, kindOf, PFMed.Injuries.Visible) and roll(adjusted(rule, tier, inj.severity)) then
                local value = rule.valueFromSubtype and inj.subtype or nil
                if inj.type == 'poisoning' then
                    local tox = PFMed.Injuries.ToxinOf(inj.subtype)
                    if tox then foundToxin[tox] = true end
                end
                add({ injuryId = inj.id, region = regionOf(inj), structure = rule.revealStructure and inj.structure or nil,
                    sign = rule.sign, certainty = rule.certainty, value = value })
            end
        end
    end

    -- signs of toxins in the blood (state, not an injury row)
    local P = PFMed.Physiology
    if modality == 'pupils' then
        local seen = {}
        for _, f in ipairs(out) do seen[f.sign] = true end
        local names = {}
        for name in pairs(F.ToxinSigns) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local rule = F.ToxinSigns[name].pupils
            if rule and not seen[rule.sign] and P.ToxinIntensity(p, name, at, c) >= rule.threshold and roll(F.Sensitivity({ sens = TOXIN_SENS }, tier)) then
                seen[rule.sign] = true
                add({ sign = rule.sign, certainty = 'suspected' })
            end
        end
    elseif modality == 'labs' then
        local names = {}
        for name in pairs(p.toxins or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            if not foundToxin[name] and P.ToxinIntensity(p, name, at, c) >= F.ToxinLabThreshold
                and roll(F.Sensitivity(F.Signs.poisoning.labs, tier)) then
                add({ sign = 'tox_screen', certainty = 'confirmed', value = name })
            end
        end
    end
    return out, vitals
end

-- ── recording ──────────────────────────────────────────────────────────────────────────────────

--- Public shape of a stored finding (never the injury itself).
function Dx.PublicFinding(f)
    return {
        id = tonumber(f.id), injuryId = tonumber(f.injuryId or f.injury_id), modality = f.modality, region = f.region,
        structure = f.structure, sign = f.sign, label = F.Label(f.sign), certainty = f.certainty, value = f.value,
        byTier = tonumber(f.byTier or f.by_tier), at = tonumber(f.at),
    }
end

--- Writes generated findings for patient cid by provider { cid, tier }; a confirmed finding on an
--- injury also writes a confirmed diagnosis (once per injury). Returns the stored list or nil, code.
function Dx.Record(cid, list, provider, at)
    local S = Store()
    at = at or now()
    local stored = {}
    local confirmedBefore
    for _, f in ipairs(list) do
        local id, err = S.AddFinding(cid, { injuryId = f.injuryId, modality = f.modality, region = f.region, structure = f.structure,
            sign = f.sign, certainty = f.certainty, value = f.value, byCid = provider.cid, byTier = provider.tier })
        if not id then
            if err == 'db_unavailable' then return nil, 'db_unavailable' end
        else
            f.id, f.at, f.byTier = id, at, provider.tier
            stored[#stored + 1] = f
            local modality = F.Modalities[f.modality]
            if f.certainty == 'confirmed' and f.injuryId and modality and modality.source then
                if not confirmedBefore then
                    confirmedBefore = {}
                    for _, d in ipairs(S.ListDiagnoses(cid, { status = 'confirmed', limit = 100 })) do
                        if d.injury_id then confirmedBefore[tonumber(d.injury_id)] = true end
                    end
                end
                if not confirmedBefore[f.injuryId] then
                    local inj = S.Peek(cid) and S.Peek(cid).injuries[f.injuryId]
                    if inj then
                        local dxId = S.SetDiagnosis(cid, { injuryId = f.injuryId, structure = inj.structure, injuryType = inj.type,
                            status = 'confirmed', source = modality.source, byCid = provider.cid })
                        if dxId then confirmedBefore[f.injuryId] = true end
                    end
                end
            end
        end
    end
    return stored
end

-- ── reads used by other modules (17B preconditions) ───────────────────────────────────────────

local ORDER = { observed = 1, suspected = 2, confirmed = 3 }

--- Whether the patient has a stored finding that matches filter = { signs = { [sign] = true } |
--- sign, injuryId?, minCertainty? ('suspected' default 'observed'), since? (default 24 h) }.
function Dx.HasFinding(cid, filter)
    filter = type(filter) == 'table' and filter or {}
    local since = math.tointeger(tonumber(filter.since)) or (now() - DAY)
    local minRank = ORDER[filter.minCertainty or 'observed'] or 1
    for _, r in ipairs(Store().ListFindings(cid, { since = since, limit = 100 })) do
        local signOk = (filter.sign == nil and filter.signs == nil) or r.sign == filter.sign or (type(filter.signs) == 'table' and filter.signs[r.sign])
        local injOk = filter.injuryId == nil or tonumber(r.injury_id) == tonumber(filter.injuryId)
        if signOk and injOk and (ORDER[r.certainty] or 0) >= minRank then return true end
    end
    return false
end

--- Latest diagnoses per (injury, type, structure); a confirmed diagnosis outranks provider rows.
function Dx.CurrentDiagnoses(cid)
    local rows = Store().ListDiagnoses(cid, { limit = 100 })
    local byKey, order = {}, {}
    for _, d in ipairs(rows) do   -- newest first
        local key = table.concat({ tostring(d.injury_id or ''), tostring(d.injury_type), tostring(d.structure or '') }, '|')
        local cur = byKey[key]
        if not cur then
            byKey[key] = d
            order[#order + 1] = key
        elseif d.status == 'confirmed' and cur.status ~= 'confirmed' then
            byKey[key] = d
        end
    end
    local out = {}
    for _, key in ipairs(order) do
        local d = byKey[key]
        local t = PFMed.Injuries.Types[d.injury_type]
        out[#out + 1] = { id = tonumber(d.id), injuryId = tonumber(d.injury_id), structure = d.structure, injuryType = d.injury_type,
            label = t and t.label or d.injury_type, status = d.status, source = d.source, byCid = d.by_cid, note = d.note, at = tonumber(d.at) }
    end
    return out
end

--- Whether the current diagnosis list holds filter = { injuryType?, structure?, injuryId?, statuses = { [status] = true } }.
function Dx.HasDiagnosis(cid, filter)
    filter = type(filter) == 'table' and filter or {}
    local statuses = filter.statuses or { suspected = true, confirmed = true }
    for _, d in ipairs(Dx.CurrentDiagnoses(cid)) do
        if statuses[d.status] and (filter.injuryType == nil or d.injuryType == filter.injuryType)
            and (filter.structure == nil or d.structure == filter.structure)
            and (filter.injuryId == nil or d.injuryId == tonumber(filter.injuryId)) then
            return true
        end
    end
    return false
end

-- ── who is asking (callbacks) ──────────────────────────────────────────────────────────────────

--- The provider record for a source: { src, cid, tier, job, name } or nil, error code.
function Dx.Provider(src)
    local tier, Player = Dx.ProviderTier(src)
    if not Player then return nil, 'offline' end
    local pd = Player.PlayerData
    return { src = src, cid = pd.citizenid, tier = tier, job = type(pd.job) == 'table' and pd.job.name or nil }
end

--- Patient by server id (online) or citizen id. Returns cid, src (nil when offline) or nil, code.
function Dx.Patient(target)
    if type(target) == 'number' then
        local src = math.tointeger(target)
        if not src or src <= 0 then return nil, 'bad_args' end
        local Player = Dx.GetPlayer(src)
        if not Player then return nil, 'not_found' end
        local cid = Player.PlayerData.citizenid
        if not Store().ValidCitizenId(cid) then return nil, 'not_found' end
        return cid, src, Player
    elseif type(target) == 'string' then
        if not Store().ValidCitizenId(target) then return nil, 'bad_args' end
        local src = Store().SourceOf(target)
        return target, src, src and Dx.GetPlayer(src) or nil
    end
    return nil, 'bad_args'
end

local function audit(cid, action, provider, detail)
    Store().Audit(cid, action, provider and { cid = provider.cid, src = provider.src, job = provider.job } or nil, detail)
end
Dx.Audit = audit

-- ── setDiagnosis ───────────────────────────────────────────────────────────────────────────────

function Q.DxFindingForInjury(cid, injuryId)
    return MySQL.scalar.await('SELECT 1 FROM `pf_med_findings` WHERE `citizenid` = ? AND `injury_id` = ? LIMIT 1', { cid, injuryId })
end

--- data = { injuryType, structure?, status = 'suspected' | 'ruled_out', note?, injuryId? }.
function Dx.SetDiagnosis(src, target, data)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return fail('bad_args') end
    if Dx.Limited(src) then return fail('rate_limited') end
    if type(data) ~= 'table' then return fail('bad_args') end
    if type(data.injuryType) ~= 'string' or not PFMed.Injuries.Types[data.injuryType] then return fail('bad_args', 'Unknown injury type.') end
    if data.status == 'confirmed' then return fail('invalid_state', 'Only imaging, labs or surgery confirm a diagnosis.') end
    if data.status ~= 'suspected' and data.status ~= 'ruled_out' then return fail('bad_args') end
    if data.structure ~= nil and not PFMed.Anatomy.IsStructure(data.structure) then return fail('bad_args', 'Unknown structure.') end
    local note = cleanText(data.note, 255)
    if note == false then return fail('bad_args') end
    local injuryId
    if data.injuryId ~= nil then
        injuryId = math.tointeger(tonumber(data.injuryId))
        if not injuryId or injuryId <= 0 then return fail('bad_args') end
    end
    local provider, perr = Dx.Provider(src)
    if not provider then return fail(perr) end
    if provider.tier < 2 then return fail('no_permission', 'An EMT or higher sets diagnoses.') end
    local cid, psrc = Dx.Patient(target)
    if not cid then return fail(psrc) end
    if not Store().Ready() then return fail('db_unavailable') end
    local okSee, why = Dx.CanSeeChart(provider, cid, psrc)
    if not okSee then return fail(why) end
    -- an injury id only from a finding (never a way to probe for hidden injuries)
    if injuryId then
        local ok, hit = pcall(Q.DxFindingForInjury, cid, injuryId)
        if not ok then return fail('db_unavailable') end
        if not hit then return fail('not_found', 'No finding for that injury.') end
    end
    if data.status == 'ruled_out' then
        for _, d in ipairs(Dx.CurrentDiagnoses(cid)) do
            if d.status == 'confirmed' and d.injuryType == data.injuryType and (data.structure == nil or d.structure == data.structure)
                and (injuryId == nil or d.injuryId == injuryId) then
                return fail('invalid_state', 'A confirmed diagnosis cannot be ruled out by examination.')
            end
        end
    end
    local id, err = Store().SetDiagnosis(cid, { injuryId = injuryId, structure = data.structure, injuryType = data.injuryType,
        status = data.status, source = 'provider', byCid = provider.cid, note = note })
    if not id then return fail(err or 'db_unavailable') end
    Dx.NoteCare(cid, provider.cid)
    audit(cid, 'diagnosis', provider, { id = id, type = data.injuryType, structure = data.structure, status = data.status, tier = provider.tier })
    return { ok = true, id = id, diagnosis = { id = id, injuryId = injuryId, structure = data.structure, injuryType = data.injuryType,
        status = data.status, source = 'provider', byCid = provider.cid, note = note, at = now() } }
end

-- ── getChart ───────────────────────────────────────────────────────────────────────────────────

local VITAL_MODALITIES = "('pulse','bp_cuff','spo2_probe','temperature','glucose','pain_scale','ecg')"

function Q.DxVitals(cid, since, limit)
    return MySQL.query.await('SELECT `modality`, `sign`, `value`, `at` FROM `pf_med_findings` WHERE `citizenid` = ? AND `at` >= ? AND `modality` IN '
        .. VITAL_MODALITIES .. ' ORDER BY `id` DESC LIMIT ?', { cid, since, limit }) or {}
end
function Q.DxTreatments(cid, since, limit)
    return MySQL.query.await('SELECT `id`, `injury_id`, `action`, `by_cid`, `by_job`, `location`, `result`, `at` FROM `pf_med_treatments` WHERE `citizenid` = ? AND `at` >= ? ORDER BY `id` DESC LIMIT ?', { cid, since, limit }) or {}
end

local function treatmentRows(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        out[#out + 1] = { id = tonumber(r.id), injuryId = tonumber(r.injury_id), action = r.action, byCid = r.by_cid, byJob = r.by_job,
            location = r.location, result = r.result, at = tonumber(r.at) }
    end
    return out
end

function Dx.GetChart(src, target)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return fail('bad_args') end
    if Dx.Limited(src) then return fail('rate_limited') end
    local provider, perr = Dx.Provider(src)
    if not provider then return fail(perr) end
    if provider.tier < 1 then return fail('no_permission', 'Only on-duty medical staff see charts.') end
    local cid, psrc, Patient = Dx.Patient(target)
    if not cid then return fail(psrc) end
    if not Store().Ready() then return fail('db_unavailable') end
    local okSee, why = Dx.CanSeeChart(provider, cid, psrc)
    if not okSee then
        audit(cid, 'record_read', provider, { via = 'chart', denied = why })
        return fail(why)
    end
    local at = now()
    local since = at - DAY
    local findings = {}
    for _, r in ipairs(Store().ListFindings(cid, { since = since, limit = 100 })) do findings[#findings + 1] = Dx.PublicFinding(r) end
    local vitals = {}
    local okV, vrows = pcall(Q.DxVitals, cid, since, 200)
    if okV then
        for _, r in ipairs(vrows or {}) do vitals[#vitals + 1] = { modality = r.modality, sign = r.sign, value = r.value, at = tonumber(r.at) } end
    end
    local okT, trows = pcall(Q.DxTreatments, cid, since, 100)
    local name
    if Patient and type(Patient.PlayerData.charinfo) == 'table' then
        name = ('%s %s'):format(tostring(Patient.PlayerData.charinfo.firstname or ''), tostring(Patient.PlayerData.charinfo.lastname or ''))
    end
    audit(cid, 'record_read', provider, { via = 'chart', reason = why })
    return {
        ok = true, tier = provider.tier, access = why,
        patient = { cid = cid, online = psrc ~= nil, name = name },
        findings = findings, diagnoses = Dx.CurrentDiagnoses(cid), vitals = vitals,
        treatments = okT and treatmentRows(trows) or {},
    }
end

-- ── GetMedicalRecord (export, 6.6) ─────────────────────────────────────────────────────────────

-- documented injuries only: found by an exam, confirmed, or treated (treatments from schema v5)
local RECORD_INJURY_COLS = 'i.`id`, i.`type`, i.`subtype`, i.`region`, i.`structure`, i.`severity`, i.`stage`, i.`mechanism`, i.`created_at`, i.`treated_at`, i.`recover_at`, i.`recovered_at`'
function Q.DxRecordInjuries(cid, limit, withTreatments)
    local sql = 'SELECT ' .. RECORD_INJURY_COLS .. ' FROM `pf_med_injuries` i WHERE i.`citizenid` = ? AND ('
        .. 'EXISTS (SELECT 1 FROM `pf_med_findings` f WHERE f.`citizenid` = i.`citizenid` AND f.`injury_id` = i.`id`)'
        .. " OR EXISTS (SELECT 1 FROM `pf_med_diagnoses` d WHERE d.`citizenid` = i.`citizenid` AND d.`injury_id` = i.`id` AND d.`status` = 'confirmed')"
    if withTreatments then
        sql = sql .. ' OR EXISTS (SELECT 1 FROM `pf_med_treatments` t WHERE t.`citizenid` = i.`citizenid` AND t.`injury_id` = i.`id`)'
    end
    sql = sql .. ') ORDER BY i.`id` DESC LIMIT ?'
    return MySQL.query.await(sql, { cid, limit }) or {}
end
function Q.DxRecordTreatments(cid, limit)
    return MySQL.query.await('SELECT `id`, `injury_id`, `action`, `by_cid`, `by_job`, `location`, `result`, `at` FROM `pf_med_treatments` WHERE `citizenid` = ? ORDER BY `id` DESC LIMIT ?', { cid, limit }) or {}
end
function Q.DxRecordAdmissions(cid, limit)
    return MySQL.query.await('SELECT `id`, `hospital_id`, `state`, `triage`, `dept`, `reason`, `arrived_at`, `admitted_at`, `discharged_at` FROM `pf_hosp_admissions` WHERE `citizenid` = ? ORDER BY `id` DESC LIMIT ?', { cid, limit }) or {}
end

local PURPOSES = { treatment = true, self = true, court_order = true }

local function courtOrderValid(ref, cid)
    if GetResourceState('pf-justice') ~= 'started' then return false end
    local ok, valid = pcall(function() return exports['pf-justice']:IsCourtOrderValid(ref, 'medical_records', cid) end)
    return ok and valid == true
end

--- Who may read: returns viewer info or nil, error code.
local function recordAccess(cid, opts)
    local purpose = opts.purpose
    local viewer
    if opts.viewer ~= nil then
        local vsrc = math.tointeger(tonumber(opts.viewer))
        if not vsrc or vsrc <= 0 then return nil, 'bad_args' end
        viewer = Dx.Provider(vsrc)
        if not viewer then return nil, 'offline' end
    end
    if purpose == 'self' then
        if not viewer then return nil, 'bad_args' end
        if viewer.cid ~= cid then return nil, 'no_permission' end
        return viewer
    elseif purpose == 'treatment' then
        if not viewer then return nil, 'bad_args' end
        if viewer.tier < 1 then return nil, 'no_permission' end
        local ok, why = Dx.CanSeeChart(viewer, cid, Store().SourceOf(cid))
        if not ok then return nil, why end
        return viewer
    elseif purpose == 'court_order' then
        local ref = opts.courtOrderId
        if (type(ref) ~= 'string' and type(ref) ~= 'number') or (type(ref) == 'string' and (ref == '' or #ref > 64)) then return nil, 'bad_args' end
        if not courtOrderValid(ref, cid) then return nil, 'no_permission' end
        return viewer or { kind = 'court' }
    end
    return nil, 'bad_args'
end

--- cid, opts = { viewer = src, purpose = 'treatment' | 'self' | 'court_order', courtOrderId? }.
-- Death records of a citizen from the morgue module (batch 20B), or an empty list.
local function deathRecordsOf(cid)
    local M = PFHospital and PFHospital.Morgue
    if not (M and M.ListForCitizen) then return {} end
    local ok, list = pcall(M.ListForCitizen, cid)
    return (ok and type(list) == 'table') and list or {}
end

function Dx.GetMedicalRecord(cid, opts)
    local api = PFMed.Api
    local allowed, invoker = true, nil
    if api and api.Allowed then allowed, invoker = api.Allowed('GetMedicalRecord') end
    if not allowed then return fail('not_allowed') end
    if not Store().ValidCitizenId(cid) then return fail('bad_args') end
    if type(opts) ~= 'table' or not PURPOSES[opts.purpose] then return fail('bad_args', 'opts.purpose is required.') end
    if not Store().Ready() then return fail('db_unavailable') end
    local viewer, err = recordAccess(cid, opts)
    local detail = { via = 'record', purpose = opts.purpose, invoker = invoker, courtOrderId = opts.courtOrderId and tostring(opts.courtOrderId):sub(1, 64) or nil }
    if not viewer then
        detail.denied = err
        audit(cid, 'record_read', nil, detail)
        return fail(err)
    end
    local injuries = {}
    local ok, rows = pcall(Q.DxRecordInjuries, cid, 200, true)
    if not ok then ok, rows = pcall(Q.DxRecordInjuries, cid, 200, false) end
    if not ok then return fail('db_unavailable') end
    for _, r in ipairs(rows or {}) do
        local t = PFMed.Injuries.Types[r.type]
        injuries[#injuries + 1] = { id = tonumber(r.id), type = r.type, label = t and t.label or r.type, subtype = r.subtype, region = r.region,
            structure = r.structure, severity = tonumber(r.severity), stage = r.stage, mechanism = r.mechanism, createdAt = tonumber(r.created_at),
            treatedAt = tonumber(r.treated_at), recoverAt = tonumber(r.recover_at), recoveredAt = tonumber(r.recovered_at) }
    end
    local okT, trows = pcall(Q.DxRecordTreatments, cid, 200)
    local admissions = {}
    local okA, arows = pcall(Q.DxRecordAdmissions, cid, 50)
    if okA then
        for _, r in ipairs(arows or {}) do
            admissions[#admissions + 1] = { id = tonumber(r.id), hospitalId = r.hospital_id, state = r.state, triage = r.triage, dept = r.dept,
                reason = r.reason, arrivedAt = tonumber(r.arrived_at), admittedAt = tonumber(r.admitted_at), dischargedAt = tonumber(r.discharged_at) }
        end
    end
    local diagnoses = {}
    for _, d in ipairs(Dx.CurrentDiagnoses(cid)) do if d.status == 'confirmed' then diagnoses[#diagnoses + 1] = d end end
    audit(cid, 'record_read', viewer.src and viewer or nil, detail)
    return { ok = true, record = {
        cid = cid, injuries = injuries, treatments = okT and treatmentRows(trows) or {}, admissions = admissions, diagnoses = diagnoses,
        -- pharmacy (20A) prescriptions are filled below when that module offers a list; death records come
        -- from the morgue (20B)
        prescriptions = {}, deathRecords = deathRecordsOf(cid),
    } }
end

exports('GetMedicalRecord', function(cid, opts) return Dx.GetMedicalRecord(cid, opts) end)

-- ── callbacks ──────────────────────────────────────────────────────────────────────────────────

PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:setDiagnosis', function(source, cb, target, data)
    local ok, res = pcall(Dx.SetDiagnosis, source, target, data)
    cb(ok and res or fail('db_unavailable'))
end)

PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:getChart', function(source, cb, target)
    local ok, res = pcall(Dx.GetChart, source, target)
    cb(ok and res or fail('db_unavailable'))
end)

AddEventHandler('playerDropped', function()
    local src = source
    buckets[src] = nil
    tierCache[src] = nil
end)
