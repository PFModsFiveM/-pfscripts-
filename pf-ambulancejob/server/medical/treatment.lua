-- Treatment engine (architecture 4.3, 11.7; batch 17B). Every treatment, by a medic, a citizen or on
-- yourself, goes through TX.Treat, which checks in this order and stops at the first failure:
--   rate limit -> patient online -> distance (server positions) -> provider (job, duty, not down) ->
--   tier / qualification (pf-government HasQualification, implied by grade when it is not running) ->
--   location (field, ambulance, hospital) -> equipment -> pace -> patient lock -> level of
--   consciousness and the action's own preconditions (procedure order, findings) -> items used up on
--   the server (RemoveItem must return true) -> effect on the engine record -> log, events, push.
-- Effects only ever change what the engine models (wound treatments, drugs, airway, volume, stage):
-- stabilising controls a threat, definitive care moves a wound to 'treated' (17C's recovery then
-- heals it over time). Nothing here heals an injury outright or restores blood that was not given.
-- CPR is a stream of ticks (TX.CprTick) that pauses the arrest-to-death timer only while they come
-- from within CprDistance; a defibrillator works only on a shockable rhythm.

PFMed = PFMed or {}
PFMed.Treat = PFMed.Treat or {}
PFMed.SQL = PFMed.SQL or {}
local TX = PFMed.Treat
local T = PFMed.Treatments

T.EnsureDrugs()

local function cfg() return T.Cfg() end
local function now() return os.time() end
local function num(v, default)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return default end
    return v
end
local function mcfg() return PFMed.Physiology.Cfg(Config.Medical) end

local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

local function fail(code, message) return { ok = false, error = code, message = message } end
TX.Fail = fail

TX.Random = function() return math.random() end   -- specs replace this for determinism

local rate = {}        -- [src] = { tokens, at }
local seen = {}        -- ['src|req'] = { at, result }
local lastDone = {}    -- [src] = os.time() of the provider's last treatment
local tierCache = {}   -- [src] = { key, at, tier, quals }
local cprRec = {}      -- [src] = { target, pos, at, rollAt, sessionAt }
local defibAt = {}     -- [cid] = os.time() of the last shock
local airwayDevice = {} -- [cid] = 'opa' | 'npa' | 'et_tube'
TX.stats = { treatments = 0, refused = 0, rosc = 0 }

-- ── helpers ────────────────────────────────────────────────────────────────────────────────────

local function getPlayer(src)
    if not src then return nil end
    local ok, Player = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(Player) == 'table' and type(Player.PlayerData) == 'table' then return Player end
    return nil
end

local function pedOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return ped
end

local function posOf(src)
    local ped = pedOf(src)
    return ped and GetEntityCoords(ped) or nil
end

local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function stateOf(p)
    return { blood_ml = p.blood_ml, hgb_factor = p.hgb_factor, airway = p.airway, breathing = p.breathing, pain = p.pain,
        temp_c = p.temp_c, toxins = p.toxins, drugs = p.drugs }
end

local function core() return PFAmbulance.GetCore() end

local function hasItem(src, item, count)
    local ok, has = pcall(function() return core().Functions.HasItem(src, item, count or 1) end)
    return ok and has == true
end

local function validReq(req)
    return type(req) == 'string' and #req >= 1 and #req <= 64 and req:match('^[%w%-_:%.]+$') ~= nil
end

--- false when the provider may call now (token bucket: RateBurst, refilled RatePerSecond).
local function limited(src)
    local c, t = cfg(), now()
    local r = rate[src]
    if not r then r = { tokens = c.RateBurst, at = t }; rate[src] = r end
    r.tokens = math.min(c.RateBurst, r.tokens + (t - r.at) * c.RatePerSecond)
    r.at = t
    if r.tokens < 1 then return true end
    r.tokens = r.tokens - 1
    return false
end

-- ── provider: job, duty, tier ──────────────────────────────────────────────────────────────────

local function gradeOf(job)
    local g = job and job.grade
    if type(g) == 'table' then return math.tointeger(num(g.level, 0)) or 0 end
    return math.tointeger(num(g, 0)) or 0
end

local function impliedHas(job, grade, qual)
    local byJob = T.ImpliedQuals[job or '']
    local list = byJob and byJob[grade]
    for _, q in ipairs(list or {}) do if q == qual then return true end end
    return false
end

--- Whether a provider holds a qualification: pf-government decides; its grade-implied fallback is
--- used here only when pf-government is not running (or its export cannot be called).
function TX.HasQual(cid, job, grade, qual)
    if GetResourceState('pf-government') == 'started' then
        local ok, has = pcall(function() return exports['pf-government']:HasQualification(cid, qual) end)
        if ok then return has == true end
    end
    return impliedHas(job, grade, qual)
end

--- Highest medical tier of an on-duty medic (0 when none of the tier qualifications is held).
function TX.TierOf(src, cid, job, grade)
    local key = table.concat({ tostring(cid), tostring(job), tostring(grade) }, '|')
    local hit = tierCache[src]
    if hit and hit.key == key and now() - hit.at < cfg().TierCacheSeconds then return hit.tier, hit.quals end
    local tier, quals = 0, {}
    for _, tq in ipairs(T.TierQuals) do
        if TX.HasQual(cid, job, grade, tq[2]) then
            quals[tq[2]] = true
            if tq[1] > tier then tier = tq[1] end
        end
    end
    tierCache[src] = { key = key, at = now(), tier = tier, quals = quals }
    return tier, quals
end

--- The acting player: { src, cid, job, grade, medical (on-duty EMS), offDutyMedic, tier, quals }.
function TX.Provider(src)
    local Player = getPlayer(src)
    if not Player then return nil end
    local pd = Player.PlayerData
    local job = type(pd.job) == 'table' and pd.job or {}
    local allowed = (Config.AllowedJobs or { ambulance = true })[job.name] == true
    local prov = { src = src, cid = pd.citizenid, job = job.name, grade = gradeOf(job), medical = allowed and job.onduty == true,
        offDutyMedic = allowed and job.onduty ~= true, tier = 0, quals = {} }
    if prov.medical then prov.tier, prov.quals = TX.TierOf(src, prov.cid, prov.job, prov.grade) end
    return prov, Player
end

-- ── location: field, ambulance (rig), hospital ─────────────────────────────────────────────────

local rigModels
local function rigModelSet()
    if rigModels then return rigModels end
    rigModels = {}
    local function add(model)
        if type(model) == 'string' then rigModels[GetHashKey(model)] = true; rigModels[GetHashKey(model) & 0xFFFFFFFF] = true end
    end
    for _, list in pairs(Config.AuthorizedVehicles or {}) do
        for model in pairs(list) do add(model) end
    end
    add(Config.Helicopter)
    for _, model in ipairs(cfg().Rig.Models or {}) do add(model) end
    return rigModels
end
function TX.ResetRigModels() rigModels = nil end

local function isRig(veh, from, maxDist)
    if not veh or veh == 0 then return false end
    local ok, model = pcall(GetEntityModel, veh)
    if not ok or not rigModelSet()[model] then return false end
    return dist(GetEntityCoords(veh), from) <= maxDist
end

--- Whether an ambulance is within Rig.Distance of the provider (the patient's or provider's vehicle
--- first, then every vehicle the server knows).
function TX.NearRig(src, patientSrc, from)
    from = from or posOf(src)
    if not from then return false end
    local maxDist = num(cfg().Rig.Distance, 6.0)
    for _, s in ipairs({ patientSrc, src }) do
        local ped = s and pedOf(s)
        if ped and isRig(GetVehiclePedIsIn(ped, false), from, maxDist) then return true end
    end
    if GetAllVehicles then
        local ok, list = pcall(GetAllVehicles)
        if ok and type(list) == 'table' then
            for _, veh in ipairs(list) do if isRig(veh, from, maxDist) then return true end end
        end
    end
    return false
end

--- Whether a position is inside a hospital: a PFMed.LocationAt(src, pos) hook when one is set
--- ('hospital' | 'or' | nil), else the hospital module's facility zones (PFHospital.Facility.At,
--- config_hospital.lua), else a radius around the legacy hospital points.
function TX.InHospital(src, from)
    from = from or posOf(src)
    if not from then return false end
    if callable(PFMed.LocationAt) then
        local ok, kind = pcall(PFMed.LocationAt, src, from)
        if ok then return kind == 'hospital' or kind == 'or' end
    end
    local F = PFHospital and PFHospital.Facility
    if F and callable(F.At) then
        local ok, id = pcall(F.At, from)
        if ok then return id ~= nil end
    end
    local facilities = Config.Hospital and Config.Hospital.Facilities
    if type(facilities) == 'table' and next(facilities) then
        for _, f in pairs(facilities) do
            local z = type(f) == 'table' and (f.zone or f)
            local c = type(z) == 'table' and (z.center or z.coords)
            if c and dist(c, from) <= num(z.radius, cfg().HospitalRadius) then return true end
        end
        return false
    end
    for _, h in ipairs((Config.Locations and Config.Locations['hospital']) or {}) do
        if h['location'] and dist(h['location'], from) <= num(cfg().HospitalRadius, 60) then return true end
    end
    return false
end

function TX.Where(src, patientSrc)
    local from = posOf(src)
    local w = { field = true, hospital = TX.InHospital(src, from), rig = TX.NearRig(src, patientSrc, from) }
    w.name = w.hospital and 'hospital' or (w.rig and 'rig' or 'field')
    return w
end

local function locationAllowed(action, where)
    local loc = action.location or { field = true }
    return loc.field or (loc.rig and where.rig) or (loc.hospital and where.hospital) or false
end

local function locationMessage(action)
    local loc = action.location or {}
    if loc.rig then return 'This needs an ambulance or a hospital' end
    return 'This needs a hospital'
end

-- ── items ──────────────────────────────────────────────────────────────────────────────────────

local function hasSet(src, set)
    for name, count in pairs(set) do if not hasItem(src, name, count) then return false end end
    return true
end

--- The item set the provider will use: the hinted one when it is one of the action's sets and held,
--- else the first held set. Returns set | nil (nothing to use up: {}).
local function pickItems(src, action, hint)
    if not action.items then return {} end
    local sets = { action.items }
    for _, alt in ipairs(action.alt or {}) do sets[#sets + 1] = alt end
    if type(hint) == 'string' then
        for _, s in ipairs(sets) do
            if s[hint] and hasSet(src, s) then return s end
        end
    end
    for _, s in ipairs(sets) do if hasSet(src, s) then return s end end
    return nil
end

--- Uses up the items on the server; every RemoveItem must return true, else what was taken goes back.
local function consume(src, set, reason)
    local taken = {}
    for name, count in pairs(set) do
        local ok, removed = pcall(function() return exports['pfm-inventory']:RemoveItem(src, name, count, false, reason) end)
        if not ok or removed ~= true then
            for _, t in ipairs(taken) do
                pcall(function() exports['pfm-inventory']:AddItem(src, t[1], t[2], false, nil, reason .. ':refund') end)
            end
            return false, name
        end
        taken[#taken + 1] = { name, count }
    end
    local shared = core().Shared and core().Shared.Items or {}
    for _, t in ipairs(taken) do TriggerClientEvent('qb-inventory:client:ItemBox', src, shared[t[1]], 'remove') end
    return true
end

local function hasEquipment(src, action, where)
    for _, name in ipairs(action.equipment or {}) do
        if not hasItem(src, name, 1) and not where.rig then return false, name end
    end
    return true
end

-- ── engine record helpers ──────────────────────────────────────────────────────────────────────

local function openInjuries(p)
    local list = {}
    for _, inj in pairs(p.injuries or {}) do
        if inj.stage ~= 'recovered' and inj.stage ~= nil then list[#list + 1] = inj end
    end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return list
end

local function trOf(inj) return type(inj.treatments) == 'table' and inj.treatments or {} end
local function attrsOf(inj) return type(inj.attrs) == 'table' and inj.attrs or {} end

local function effBleed(p, inj, at)
    return PFMed.Physiology.WoundBleed(inj, stateOf(p), at, mcfg())
end

local function external(inj)
    local a = attrsOf(inj)
    return not a.internal and not a.fluid
end

local function inRegion(inj, region)
    if not region then return true end
    if inj.region == region then return true end
    return inj.structure ~= nil and PFMed.Anatomy.StructureInRegion(inj.structure, region)
end

local function drugActive(p, name, at)
    return PFMed.Physiology.DrugActive(p, name, at, mcfg()) ~= nil
end

function TX.HasIv(p, at) return drugActive(p, 'iv_line', at or now()) end

local LIMB_KINDS = { arm = true, leg = true }
local function limbKind(inj) return LIMB_KINDS[PFMed.Anatomy.GroupKindOf(inj.region, inj.structure) or ''] == true end

--- Whether every threat of an injury is controlled (architecture 5.2 injured -> stabilized).
function TX.Controlled(p, inj, at)
    at = at or now()
    local tr, a = trOf(inj), attrsOf(inj)
    -- a closed fracture bleeds into the tissue: holding it still is its field stabilisation
    local closedFracture = inj.type == 'fracture' and inj.subtype ~= 'open'
    if not closedFracture and (tonumber(inj.bleed_ml_min) or 0) > 0 and not tr.tourniquet and effBleed(p, inj, at) > num(cfg().StableBleed, 1.0) then
        return false
    end
    local t, s, sub = inj.type, inj.structure, inj.subtype
    local oxygen = drugActive(p, 'oxygen', at)
    local vent = drugActive(p, 'ventilation', at) or p.airway == 'secured'
    if t == 'fracture' then
        if s == 'pelvis' or s == 'hip_l' or s == 'hip_r' then return (tr.binder or tr.splinted or tr.cast or tr.backboard) and true or false end
        if s == 'spine_cervical' then return tr.collar == true end
        if s == 'spine_thoracic' or s == 'spine_lumbar' then return tr.backboard == true end
        if limbKind(inj) then return (tr.splinted or tr.cast) and true or false end
        return true -- ribs, skull, face: nothing to immobilise in the field
    elseif t == 'dislocation' then return (tr.splinted or tr.reduced) and true or false
    elseif t == 'sprain' then
        if s == 'neck' then return tr.collar == true end
        return (tr.splinted or (num(inj.severity, 1) <= 1)) and true or false
    elseif t == 'spinal' then
        if s == 'spine_cervical' then return tr.collar == true and (not a.cord or tr.backboard == true) end
        return tr.backboard == true
    elseif t == 'organ_trauma' then
        if sub == 'tension' then return tr.decompressed == true end
        if sub == 'pneumothorax' then return (tr.chest_seal or oxygen) and true or false end
        if sub == 'hemothorax' then return oxygen or vent end
        return false -- tamponade, bowel: surgery
    elseif t == 'burn' or t == 'electrical' then return (tr.dressed or tr.cooled) and true or false
    elseif t == 'head_trauma' then return (tr.collar or oxygen) and true or false
    elseif t == 'respiratory' then return oxygen or vent
    elseif t == 'drowning' then return oxygen or vent
    elseif t == 'infection' then return tr.antibiotics == true
    elseif t == 'illness' then
        if sub == 'infection_sepsis' then return tr.antibiotics == true end
        if sub == 'heat_stroke' then return tr.cooled == true end
        if sub == 'hypothermia' then return false end
        return true
    elseif t == 'poisoning' then
        if sub == 'opioid' then return drugActive(p, 'naloxone', at) end
        if sub == 'co' then return oxygen end
        return false
    elseif t == 'crush' then return (tr.splinted or tr.binder) and true or false
    elseif t == 'gunshot' or t == 'stab' then
        if s == 'lung_l' or s == 'lung_r' then return tr.chest_seal == true end
        return true
    end
    return true -- laceration (bleeding checked above), bruising, internal bleeding once controlled
end

local function actorOf(prov) return { cid = prov.cid, src = prov.src, job = prov.job } end

-- The action's own name goes on the wound's treatments as well as the flag the engine model reads,
-- so the recovery machine (17C, which matches the catalogue's stabilizeBy/treatBy names) sees it.
local function update(ctx, inj, patch)
    if patch.treatments and ctx.action and not patch.treatments[ctx.action.name] then
        local t, adds = {}, false
        for k, v in pairs(patch.treatments) do t[k] = v; if v ~= false then adds = true end end
        if adds then t[ctx.action.name] = true end
        patch = { stage = patch.stage, severity = patch.severity, attrs = patch.attrs, treatments = t }
    end
    local r, err = PFMed.Engine.UpdateInjury(ctx.cid, inj.id, patch, { actor = actorOf(ctx.prov), source = 'treatment' })
    if r then ctx.touched[inj.id] = true end
    return r, err
end

--- Moves controlled injuries from injured/complicated to stabilized (all open ones when list is nil).
local function restabilize(ctx, list)
    for _, inj in ipairs(list or openInjuries(ctx.p)) do
        if (inj.stage == 'injured' or inj.stage == 'complicated') and TX.Controlled(ctx.p, inj, ctx.at) then
            if update(ctx, inj, { stage = 'stabilized' }) then ctx.stabilized = ctx.stabilized + 1 end
        end
    end
end

--- Definitive care done: stabilized (when needed) then treated; 17C's recovery takes it from there.
local function definitive(ctx, inj, patch)
    if patch then update(ctx, inj, patch) end
    if inj.stage == 'injured' or inj.stage == 'complicated' then
        if not update(ctx, inj, { stage = 'stabilized' }) then return false end
    end
    if inj.stage ~= 'stabilized' then return false end
    if not update(ctx, inj, { stage = 'treated' }) then return false end
    ctx.treated = ctx.treated + 1
    return true
end

local function settle(p, at)
    p.updated_at = at
    PFMed.Store.MarkDirty(p.cid)
    PFMed.Engine.Evaluate(p, at)
    PFMed.Engine.ActivateIfOnline(p, at)
end

-- ── findings (17A) as preconditions ────────────────────────────────────────────────────────────

--- Whether the chart supports a tension pneumothorax on `side` ('l', 'r' or nil): a diagnosis of organ
--- trauma (suspected or confirmed), or a recent finding with one of TensionSigns, suspected or
--- confirmed. Returns ok, side (from the finding when none was asked).
function TX.TensionFinding(cid, side, at)
    at = at or now()
    local c = cfg()
    local function sideOf(structure, region)
        local s = (structure or region or ''):match('_([lr])$')
        return s
    end
    for _, d in ipairs(PFMed.Store.ListDiagnoses(cid, { limit = 50 }) or {}) do
        if d.injury_type == 'organ_trauma' and (d.status == 'suspected' or d.status == 'confirmed') then
            local s = sideOf(d.structure)
            if not side or not s or s == side then return true, side or s end
        end
    end
    for _, f in ipairs(PFMed.Store.ListFindings(cid, { since = at - num(c.FindingSeconds, 3600), limit = 100 }) or {}) do
        if c.TensionSigns[f.sign] and (f.certainty == 'suspected' or f.certainty == 'confirmed') then
            local s = sideOf(f.structure, f.region)
            if not side or not s or s == side then return true, side or s end
        end
    end
    return false
end

-- ── CPR and defibrillation ─────────────────────────────────────────────────────────────────────

--- An arrest cause that is still uncorrected (nil when CPR or a shock could restore circulation).
function TX.UncorrectedCause(p, at)
    local P, c = PFMed.Physiology, mcfg()
    local v = P.Vitals(stateOf(p), p.injuries, at, c, 'unconscious')
    return P.ArrestCause(v, {}, at, c)
end

function TX.Rhythm(p, at)
    local v = PFMed.Engine.Vitals(p, at)
    return v and v.rhythm
end

--- A shock (or CPR luck) converted the arrhythmia: the injury that sustains it drops below arrest.
local function convertArrhythmia(ctx)
    for _, inj in ipairs(openInjuries(ctx.p)) do
        local f = PFMed.Injuries.Physiology(inj)
        if f.arrest and num(inj.severity, 1) > 1 then
            update(ctx, inj, { severity = num(inj.severity, 1) - 1 })
        end
    end
end

--- Chance of ROSC for one counted CPR tick ('cpr') or one shock ('defib').
function TX.RoscChance(p, at, mode)
    local c = cfg()
    local cause = TX.UncorrectedCause(p, at)
    local rhythm = TX.Rhythm(p, at)
    local bonus = (drugActive(p, 'epinephrine', at) and c.EpiRoscBonus or 0)
    if mode == 'defib' then
        if rhythm ~= 'vf' then return 0 end
        if cause and cause ~= 'arrhythmia' then return 0 end
        return math.min(0.95, c.DefibRoscChance + bonus)
    end
    if rhythm == 'vf' then
        if cause and cause ~= 'arrhythmia' then return 0 end
        return c.CprVfChance
    end
    if cause then return 0 end
    if drugActive(p, 'ventilation', at) or p.airway == 'secured' then bonus = bonus + c.VentRoscBonus end
    return math.min(0.9, c.CprRoscChance + bonus)
end

--- Return of spontaneous circulation: arrest -> unconscious. The last-stand window starts again
--- (the patient now has to be woken or treated before it runs out).
local function rosc(ctx, how)
    if TX.Rhythm(ctx.p, ctx.at) == 'vf' then convertArrhythmia(ctx) end
    local ok = PFMed.Engine.SetConsciousness(ctx.cid, 'unconscious', 'rosc', how, { actor = actorOf(ctx.prov) })
    if not ok then return false end
    ctx.p.cpr_last_at = nil
    ctx.p.down_since = ctx.at
    PFMed.Store.MarkDirty(ctx.cid)
    TX.stats.rosc = TX.stats.rosc + 1
    return true
end

-- ── handlers: plan(ctx) -> apply function | nil, error, message ────────────────────────────────
-- A plan only reads; the apply function runs after the items were used up.

local H = {}
TX.Handlers = H

local function pickWound(ctx, filter)
    local p, region, id = ctx.p, ctx.params.region, ctx.params.injuryId
    if id then
        local inj = p.injuries[id]
        if not inj or inj.stage == 'recovered' or not filter(inj) then return nil end
        return inj
    end
    local best, bestBleed, bestSev
    for _, inj in ipairs(openInjuries(p)) do
        if inRegion(inj, region) and filter(inj) then
            local b, s = effBleed(p, inj, ctx.at), num(inj.severity, 1)
            if not best or b > bestBleed or (b == bestBleed and s > bestSev) then best, bestBleed, bestSev = inj, b, s end
        end
    end
    return best
end

local function bleedingWound(ctx, inj)
    return external(inj) and effBleed(ctx.p, inj, ctx.at) > 0 and (not ctx.action.regions or ctx.action.regions[inj.region] == true)
end

function H.bleed(ctx)
    local key = ctx.action.key
    local inj = pickWound(ctx, function(i) return bleedingWound(ctx, i) and not trOf(i)[key] end)
    if not inj then return nil, 'invalid_state', 'No bleeding wound this can help with' end
    return function()
        update(ctx, inj, { treatments = { [key] = true } })
        restabilize(ctx, { inj })
        ctx.injuryId = inj.id
        return true, ctx.stabilized > 0 and 'Bleeding controlled' or 'Dressing applied: the wound still bleeds'
    end
end

function H.tourniquet(ctx)
    local inj = pickWound(ctx, function(i) return bleedingWound(ctx, i) and T.LimbRegions[i.region] and not trOf(i).tourniquet end)
    if not inj then return nil, 'invalid_state', 'No bleeding limb wound for a tourniquet' end
    return function()
        update(ctx, inj, { treatments = { tourniquet = ctx.at } })
        restabilize(ctx, { inj })
        ctx.injuryId = inj.id
        return true, 'Tourniquet on: note the time (limb damage after ' .. math.floor(cfg().TourniquetLimitSeconds / 60) .. ' min)'
    end
end

function H.tourniquet_remove(ctx)
    local list = {}
    for _, inj in ipairs(openInjuries(ctx.p)) do
        if trOf(inj).tourniquet and inRegion(inj, ctx.params.region) then list[#list + 1] = inj end
    end
    if #list == 0 then return nil, 'invalid_state', 'No tourniquet there' end
    return function()
        for _, inj in ipairs(list) do update(ctx, inj, { treatments = { tourniquet = false } }) end
        ctx.injuryId = list[1].id
        return true, 'Tourniquet removed'
    end
end

function H.chest_seal(ctx)
    local inj = pickWound(ctx, function(i)
        return (i.type == 'gunshot' or i.type == 'stab') and T.ChestRegions[i.region] and not trOf(i).chest_seal
    end)
    if not inj then return nil, 'invalid_state', 'No open chest wound to seal' end
    return function()
        update(ctx, inj, { treatments = { chest_seal = true } })
        local side = (inj.region or ''):match('_([lr])$')
        for _, o in ipairs(openInjuries(ctx.p)) do
            if o.type == 'organ_trauma' and o.subtype == 'pneumothorax' and (not side or o.structure == 'lung_' .. side) then
                update(ctx, o, { treatments = { chest_seal = true } })
            end
        end
        restabilize(ctx)
        ctx.injuryId = inj.id
        return true, 'Chest seal applied'
    end
end

function H.decompress(ctx)
    if not ctx.tension then
        return nil, 'invalid_state', 'Nothing on the chart supports a decompression: examine the chest first'
    end
    local side = ctx.tensionSide
    return function()
        for _, inj in ipairs(openInjuries(ctx.p)) do
            if inj.type == 'organ_trauma' and inj.subtype == 'tension' and (not side or inj.structure == 'lung_' .. side) and not trOf(inj).decompressed then
                update(ctx, inj, { treatments = { decompressed = true } })
                ctx.injuryId = ctx.injuryId or inj.id
            end
        end
        restabilize(ctx)
        return true, 'Needle decompression done'
    end
end

function H.airway(ctx)
    local p = ctx.p
    if p.airway == 'secured' and (airwayDevice[ctx.cid] == 'et_tube' or not ctx.action.secure) then
        return nil, 'invalid_state', 'The airway is already secured'
    end
    return function()
        PFMed.Engine.Touch(p, ctx.at)
        local conds = PFMed.Physiology.Conditions(p.injuries, mcfg())
        local blocked = conds.airway == 'obstructed' and not ctx.action.secure
        if not blocked then
            p.airway = 'secured'
            airwayDevice[ctx.cid] = ctx.action.device
        end
        settle(p, ctx.at)
        restabilize(ctx)
        return not blocked, blocked and 'The airway is still blocked: it needs intubation' or 'Airway secured'
    end
end

function H.drug(ctx)
    local a, p = ctx.action, ctx.p
    if a.needsIv and not TX.HasIv(p, ctx.at) then return nil, 'invalid_state', 'Needs IV access first' end
    local prev = p.drugs and p.drugs[a.drug]
    if a.redose and type(prev) == 'table' and ctx.at - num(prev.at, 0) < a.redose then
        return nil, 'invalid_state', ('Too soon for another dose (%d s)'):format(a.redose - (ctx.at - num(prev.at, 0)))
    end
    return function()
        PFMed.Engine.Touch(p, ctx.at)
        p.drugs = type(p.drugs) == 'table' and p.drugs or {}
        p.drugs[a.drug] = { mg = a.opioid or 0, at = ctx.at }
        settle(p, ctx.at)
        if a.opioid then PFMed.Engine.AddToxin(ctx.cid, 'opioid', a.opioid, { actor = actorOf(ctx.prov), source = 'treatment' }) end
        restabilize(ctx)
        return true, a.label .. ' given'
    end
end

local function matching(ctx, pred)
    local list = {}
    for _, inj in ipairs(openInjuries(ctx.p)) do if pred(inj) then list[#list + 1] = inj end end
    return list
end

local function applyKey(ctx, list, patch, message)
    for _, inj in ipairs(list) do update(ctx, inj, { treatments = patch }) end
    if list[1] then ctx.injuryId = list[1].id end
    restabilize(ctx)
    return #list > 0, message
end

function H.collar(ctx)
    local list = matching(ctx, function(i)
        return i.structure == 'spine_cervical' or i.structure == 'neck' or i.type == 'head_trauma'
    end)
    return function() return applyKey(ctx, list, { collar = true }, 'Cervical collar on') end
end

function H.backboard(ctx)
    local list = matching(ctx, function(i)
        return i.structure == 'spine_thoracic' or i.structure == 'spine_lumbar' or i.structure == 'spine_cervical'
            or i.structure == 'pelvis'
    end)
    return function() return applyKey(ctx, list, { backboard = true }, 'Patient on a backboard') end
end

function H.binder(ctx)
    local list = matching(ctx, function(i)
        return i.structure == 'pelvis' or i.structure == 'hip_l' or i.structure == 'hip_r' or (i.type == 'internal_bleeding' and i.subtype == 'pelvic')
            or (i.type == 'crush' and i.subtype == 'pelvis')
    end)
    return function() return applyKey(ctx, list, { binder = true }, 'Pelvic binder on') end
end

local SPLINTABLE = { fracture = true, dislocation = true, sprain = true, crush = true }

function H.splint(ctx)
    local region = ctx.params.region
    local list = matching(ctx, function(i)
        return SPLINTABLE[i.type] and (region and inRegion(i, region) or (not region and limbKind(i))) and not trOf(i).splinted
            and (not ctx.action.traction or i.structure == 'femur_l' or i.structure == 'femur_r')
    end)
    if not region then
        -- on yourself the worst painful limb is chosen (you know where it hurts)
        table.sort(list, function(a, b) return num(a.severity, 1) > num(b.severity, 1) end)
        if not list[1] then return nil, 'invalid_state', 'No injured limb to splint' end
        local r = list[1].region
        local keep = {}
        for _, i in ipairs(list) do if i.region == r then keep[#keep + 1] = i end end
        list = keep
    end
    return function()
        local patch = { splinted = true }
        if ctx.action.traction then patch.traction = true end
        local any = false
        for _, inj in ipairs(list) do
            update(ctx, inj, { treatments = patch })
            any = true
            ctx.injuryId = ctx.injuryId or inj.id
            if inj.type == 'sprain' then definitive(ctx, inj) end
        end
        restabilize(ctx, list)
        return any, 'Splint applied'
    end
end

function H.iv(ctx)
    if TX.HasIv(ctx.p, ctx.at) then return nil, 'invalid_state', 'IV access is already in place' end
    return function()
        PFMed.Engine.Touch(ctx.p, ctx.at)
        ctx.p.drugs = type(ctx.p.drugs) == 'table' and ctx.p.drugs or {}
        ctx.p.drugs.iv_line = { mg = 0, at = ctx.at }
        settle(ctx.p, ctx.at)
        return true, 'IV access in place'
    end
end

function H.volume(ctx)
    if not TX.HasIv(ctx.p, ctx.at) then return nil, 'invalid_state', 'Needs IV access first' end
    local vol = ctx.action.volume
    return function()
        local p = ctx.p
        PFMed.Engine.Touch(p, ctx.at)
        local before = num(p.blood_ml, 0)
        local s = PFMed.Physiology.AddVolume(stateOf(p), vol.kind, vol.ml, mcfg())
        p.blood_ml, p.hgb_factor = s.blood_ml, s.hgb_factor
        settle(p, ctx.at)
        local added = math.floor(num(p.blood_ml, 0) - before + 0.5)
        return added > 0, ('%s: %d ml given'):format(ctx.action.label, math.max(0, added))
    end
end

function H.defib(ctx)
    local last = defibAt[ctx.cid]
    if last and ctx.at - last < cfg().DefibCooldownSeconds then return nil, 'busy', 'The defibrillator is charging' end
    if TX.Rhythm(ctx.p, ctx.at) ~= 'vf' then
        return nil, 'invalid_state', 'No shock advised: the rhythm is not shockable. Continue CPR'
    end
    return function()
        defibAt[ctx.cid] = ctx.at
        local chance = TX.RoscChance(ctx.p, ctx.at, 'defib')
        local back = chance > 0 and TX.Random() < chance and rosc(ctx, 'defibrillation')
        ctx.result = back and 'rosc' or 'applied'
        return true, back and 'Shock delivered: pulse is back' or 'Shock delivered: no pulse. Continue CPR'
    end
end

function H.revive(ctx)
    local D = PFMed.Down
    if D.PendingRevive(ctx.target) then return nil, 'busy', 'They are already being revived' end
    local viable, why = D.Viable(ctx.p, 'none', ctx.at)
    if not viable then
        return nil, 'invalid_state', ('They do not respond (%s): treat the cause first'):format(tostring(why):gsub('_', ' '))
    end
    return function()
        local token = D.IssueReviveToken(ctx.target, 'ems', { by = { src = ctx.src, cid = ctx.prov.cid, kind = 'ems' }, reset = 'none' })
        return token ~= nil, token and 'They are coming round' or 'Revive failed'
    end
end

local function burnLike(i) return i.type == 'burn' or (i.type == 'electrical' and external(i)) end

function H.burn(ctx)
    local inj = pickWound(ctx, function(i) return burnLike(i) and not trOf(i).dressed end)
    if not inj then return nil, 'invalid_state', 'No burn to dress there' end
    return function()
        update(ctx, inj, { treatments = { dressed = true } })
        ctx.injuryId = inj.id
        local minor = num(inj.severity, 1) <= 2 and inj.subtype ~= 'third' and inj.subtype ~= 'high_voltage'
        if minor then definitive(ctx, inj) else restabilize(ctx, { inj }) end
        return true, minor and 'Burn dressed' or 'Burn dressed: it needs hospital care'
    end
end

function H.cooling(ctx)
    local list = matching(ctx, function(i)
        return (i.type == 'burn' and not trOf(i).cooled) or (i.type == 'bruising' and i.stage ~= 'treated' and i.stage ~= 'recovering')
            or (i.type == 'illness' and i.subtype == 'heat_stroke' and not trOf(i).cooled)
    end)
    if #list == 0 then return nil, 'invalid_state', 'Nothing to cool' end
    return function()
        local p = ctx.p
        for _, inj in ipairs(list) do
            update(ctx, inj, { treatments = { cooled = true } })
            if inj.type == 'bruising' then definitive(ctx, inj) end
            if inj.type == 'illness' then
                PFMed.Engine.Touch(p, ctx.at)
                p.temp_c = math.max(mcfg().Physiology.NormalTemp, num(p.temp_c, 37) - 0.5)
                settle(p, ctx.at)
            end
        end
        ctx.injuryId = list[1].id
        restabilize(ctx, list)
        return true, 'Cooled with water'
    end
end

local MINOR_WOUND = { laceration = { superficial = true, deep = true }, gunshot = { graze = true }, stab = { superficial = true },
    infection = { wound_infection = true } }

local function minorWound(inj)
    local subs = MINOR_WOUND[inj.type]
    return subs ~= nil and subs[inj.subtype or ''] == true and num(inj.severity, 1) <= 2
end

local function openWound(inj)
    return external(inj) and (inj.type == 'laceration' or inj.type == 'gunshot' or inj.type == 'stab'
        or (inj.type == 'infection' and inj.subtype == 'wound_infection') or (inj.type == 'fracture' and inj.subtype == 'open'))
end

function H.wound_care(ctx)
    local inj = pickWound(ctx, function(i) return openWound(i) and not trOf(i).dressed end)
    if not inj then return nil, 'invalid_state', 'No open wound to dress' end
    return function()
        update(ctx, inj, { treatments = { dressed = true, pressure = true } })
        ctx.injuryId = inj.id
        local done = minorWound(inj) and TX.Controlled(ctx.p, inj, ctx.at) and definitive(ctx, inj)
        if not done then restabilize(ctx, { inj }) end
        return true, done and 'Wound cleaned and dressed' or 'Wound dressed: it needs sutures or surgery at a hospital'
    end
end

local SUTURABLE = { laceration = true, stab = { superficial = true }, gunshot = { graze = true } }

function H.sutures(ctx)
    local inj = pickWound(ctx, function(i) return openWound(i) and i.type ~= 'infection' and i.type ~= 'fracture' and not trOf(i).sutured end)
    if not inj then return nil, 'invalid_state', 'No open wound to close' end
    local rule = SUTURABLE[inj.type]
    if rule ~= true and not (type(rule) == 'table' and rule[inj.subtype or '']) then
        return nil, 'invalid_state', 'This wound needs surgical exploration, not sutures'
    end
    if not trOf(inj).tourniquet and effBleed(ctx.p, inj, ctx.at) > num(cfg().StableBleed, 1.0) then
        return nil, 'invalid_state', 'Control the bleeding before closing the wound'
    end
    return function()
        ctx.injuryId = inj.id
        local done = definitive(ctx, inj, { treatments = { sutured = true, tourniquet = false } })
        return done, done and 'Wound closed' or 'The wound could not be closed yet'
    end
end

local FIELD_REDUCTION = { shoulder = true, finger = true }

function H.reduction(ctx)
    local region = ctx.params.region
    local list = matching(ctx, function(i)
        return inRegion(i, region) and not trOf(i).reduced
            and (i.type == 'dislocation' or (i.type == 'fracture' and (i.subtype == 'displaced' or i.subtype == 'comminuted')))
    end)
    if #list == 0 then return nil, 'invalid_state', 'Nothing to reduce there' end
    for _, inj in ipairs(list) do
        local field = inj.type == 'dislocation' and FIELD_REDUCTION[inj.subtype or '']
        if not field and not (ctx.where.hospital and ctx.prov.tier >= 5) then
            return nil, 'no_permission', 'This reduction needs a physician at a hospital'
        end
    end
    return function()
        for _, inj in ipairs(list) do
            if inj.type == 'dislocation' then definitive(ctx, inj, { treatments = { reduced = true } })
            else update(ctx, inj, { treatments = { reduced = true } }) end
            ctx.injuryId = ctx.injuryId or inj.id
        end
        restabilize(ctx, list)
        return true, 'Reduced'
    end
end

function H.cast(ctx)
    local region = ctx.params.region
    local list = matching(ctx, function(i) return i.type == 'fracture' and limbKind(i) and inRegion(i, region) and not trOf(i).cast end)
    for _, inj in ipairs(list) do
        if inj.subtype == 'open' then return nil, 'invalid_state', 'An open fracture needs surgery before a cast' end
        if (inj.subtype == 'displaced' or inj.subtype == 'comminuted') and not trOf(inj).reduced then
            return nil, 'invalid_state', 'Reduce the fracture before casting it'
        end
    end
    return function()
        for _, inj in ipairs(list) do
            definitive(ctx, inj, { treatments = { cast = true } })
            ctx.injuryId = ctx.injuryId or inj.id
        end
        return #list > 0, 'Cast applied'
    end
end

function H.antibiotics(ctx)
    local list = matching(ctx, function(i)
        return i.type == 'infection' or (i.type == 'illness' and i.subtype == 'infection_sepsis') or (openWound(i) and not trOf(i).antibiotics)
    end)
    return function()
        for _, inj in ipairs(list) do
            update(ctx, inj, { treatments = { antibiotics = true } })
            if inj.type == 'infection' or inj.type == 'illness' then definitive(ctx, inj) end
            ctx.injuryId = ctx.injuryId or inj.id
        end
        restabilize(ctx, list)
        return #list > 0, 'Antibiotics given'
    end
end

function H.ifak(ctx)
    local inj = pickWound(ctx, function(i) return bleedingWound(ctx, i) end)
    local painful = num(ctx.p.pain, 0) >= 1 and not drugActive(ctx.p, 'analgesic_oral', ctx.at)
    if not inj and not painful then return nil, 'invalid_state', 'Nothing the kit can help with' end
    return function()
        if inj then
            update(ctx, inj, { treatments = { pressure = true, hemostatic = true } })
            ctx.injuryId = inj.id
            restabilize(ctx, { inj })
        end
        if painful then
            PFMed.Engine.Touch(ctx.p, ctx.at)
            ctx.p.drugs = type(ctx.p.drugs) == 'table' and ctx.p.drugs or {}
            ctx.p.drugs.analgesic_oral = { mg = 0, at = ctx.at }
            settle(ctx.p, ctx.at)
        end
        return true, inj and 'Wound packed and dressed' or 'Painkillers taken'
    end
end

-- ── logging ────────────────────────────────────────────────────────────────────────────────────

function PFMed.SQL.InsertTreatment(r)
    return MySQL.insert.await('INSERT INTO `pf_med_treatments` (`citizenid`, `injury_id`, `action`, `params`, `items`, `by_cid`, `by_job`, '
        .. '`location`, `admission_id`, `call_ref`, `req`, `result`, `at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { r.citizenid, r.injury_id, r.action, r.params, r.items, r.by_cid, r.by_job, r.location, r.admission_id, r.call_ref,
            r.req, r.result, r.at })
end

local function admissionOf(cid)
    local ok, res = pcall(function() return exports[GetCurrentResourceName()]:GetAdmission(cid) end)
    if ok and type(res) == 'table' and res.ok and type(res.admission) == 'table' then return math.tointeger(tonumber(res.admission.id)) end
    return nil
end

--- One treatment log row (pf_med_treatments, 17C's v5), one audit row, the server event.
--- Returns the row id (nil when the table is not there yet: the audit row still records it).
function TX.Log(ctx, result, items)
    local enc = function(t) if type(t) ~= 'table' or next(t) == nil then return nil end return json.encode(t) end
    local params = {}
    if ctx.params.region then params.region = ctx.params.region end
    if ctx.params.side then params.side = ctx.params.side end
    local row = {
        citizenid = ctx.cid, injury_id = ctx.injuryId, action = ctx.action.name, params = enc(params), items = enc(items),
        by_cid = ctx.prov.cid, by_job = ctx.prov.job and tostring(ctx.prov.job):sub(1, 32) or nil, location = ctx.where.name,
        admission_id = ctx.where.hospital and admissionOf(ctx.cid) or nil, call_ref = nil, req = ctx.req, result = result, at = ctx.at,
    }
    local id
    if PFMed.Store.Ready() then
        local ok, res = pcall(PFMed.SQL.InsertTreatment, row)
        if ok then id = math.tointeger(tonumber(res)) else print('^3[pf-ambulancejob]^7 treatment log not written: ' .. tostring(res)) end
    end
    PFMed.Store.Audit(ctx.cid, 'treatment', actorOf(ctx.prov), {
        id = id, action = ctx.action.name, result = result, location = ctx.where.name, params = params, items = items,
        injury = ctx.injuryId, req = ctx.req, self = ctx.src == ctx.target or nil,
    })
    TriggerEvent('pf-ambulancejob:server:treatmentApplied', ctx.cid, {
        id = id, action = ctx.action.name, byCid = ctx.prov.cid, at = ctx.at, injuryId = ctx.injuryId, result = result,
    })
    return id
end

-- ── the pipeline ───────────────────────────────────────────────────────────────────────────────

local function cleanParams(action, data, isSelf)
    local params = {}
    local region = data.region
    if type(data.params) == 'table' then region = region or data.params.region end
    if region ~= nil then
        if not PFMed.Anatomy.IsRegion(region) then return nil, 'unknown region' end
        if action.regions and not action.regions[region] then return nil, 'not possible on that part of the body' end
        params.region = region
    elseif action.target == 'region' and action.regions and not isSelf and action.apply ~= 'tourniquet_remove' then
        return nil, 'choose where'
    end
    local side = type(data.params) == 'table' and data.params.side or data.side
    if side ~= nil then
        if side ~= 'l' and side ~= 'r' then return nil, 'side must be l or r' end
        params.side = side
    elseif region then
        params.side = region:match('^chest_([lr])$')
    end
    local id = data.injuryId
    if id ~= nil then
        id = math.tointeger(tonumber(id))
        if not id or id <= 0 then return nil, 'bad injury id' end
        params.injuryId = id
    end
    return params
end

-- Patient-level actions (drugs, airway, volume): the wounds whose catalogue entry names the action
-- in stabilizeBy/treatBy carry its name, so the recovery machine counts it for them.
local PATIENT_LEVEL = { drug = true, airway = true, volume = true }
local function markCatalogue(ctx)
    local name = ctx.action.name
    for _, inj in ipairs(openInjuries(ctx.p)) do
        local def = PFMed.Injuries.Types[inj.type]
        local listed = false
        for _, list in ipairs({ def and def.stabilizeBy or {}, def and def.treatBy or {} }) do
            for _, a in ipairs(list) do if a == name then listed = true end end
        end
        if listed and not trOf(inj)[name] then
            PFMed.Engine.UpdateInjury(ctx.cid, inj.id, { treatments = { [name] = true } }, { actor = actorOf(ctx.prov), source = 'treatment' })
        end
    end
end

local function notReady(level, action)
    if level == 'dead' then return 'They are beyond help' end
    if action.states == nil then return nil end
    if level == 'arrest' then return 'No pulse: start CPR' end
    return 'Not possible in their state (' .. tostring(level) .. ')'
end

--- The checks and the effect. data = { target, action, injuryId?, region?, params?, req?, item? }.
--- opts.dry: stop before the patient lock (a usable item asks whether the action can start).
local function treatCore(src, data, opts)
    opts = opts or {}
    local action = T.Get(data.action)
    if not action then return fail('bad_args', 'Unknown treatment') end
    local target = math.tointeger(tonumber(data.target))
    if not target or target <= 0 then return fail('bad_args', 'No patient') end
    local isSelf = target == src
    if isSelf and not action.self then return fail('bad_args', 'You cannot do that on yourself') end
    if action.selfOnly and not isSelf then return fail('bad_args', 'Only on yourself') end
    local Patient = getPlayer(target)
    if not Patient or not pedOf(target) then return fail('offline', 'Patient not found') end
    if not isSelf and dist(posOf(src), posOf(target)) > num(cfg().TouchDistance, 2.5) then return fail('too_far', 'You are too far away') end

    local prov = TX.Provider(src)
    if not prov then return fail('offline', 'Not loaded') end
    local D = PFMed.Down
    if D.IsDown(src) then return fail('invalid_state', 'You are down') end
    if action.apply == 'cpr' then return TX.CprTick(src, target) end
    if action.apply == 'revive' and not prov.medical then
        -- civilian first aid keeps the server-timed flow (UseFirstAid then RevivePlayer)
        if prov.offDutyMedic then return fail('not_on_duty', 'You are off duty') end
        if opts.dry then return { ok = true } end
        local ok = D.RequestRevive(src, target)
        return ok and { ok = true, result = { changed = { revive = true }, message = 'They are coming round' } }
            or fail('invalid_state', 'First aid could not be given')
    end
    -- self-care: anyone may use a self-care item on themselves (selfTier, default 0)
    local needTier = isSelf and (action.selfTier or 0) or (action.tier or 0)
    if needTier > prov.tier then
        if prov.offDutyMedic then return fail('not_on_duty', 'You are off duty') end
        return fail('no_permission', ('Needs %s level (%s)'):format(T.TierLabels[needTier] or tostring(needTier), action.label))
    end
    if action.qual and not prov.quals[action.qual] and not TX.HasQual(prov.cid, prov.job, prov.grade, action.qual) then
        return fail('no_permission', 'Needs the ' .. action.qual .. ' qualification')
    end
    local where = TX.Where(src, target)
    if not locationAllowed(action, where) then return fail('invalid_state', locationMessage(action)) end
    local okEq, missingEq = hasEquipment(src, action, where)
    if not okEq then return fail('missing_item', 'You need a ' .. tostring(missingEq)) end
    if not opts.dry then
        local last = lastDone[src]
        if last and now() - last < math.floor((action.duration or 0) / 1000 * cfg().BusyFactor) then
            return fail('busy', 'You are still busy with the last treatment')
        end
    end
    local params, perr = cleanParams(action, data, isSelf)
    if not params then return fail('bad_args', perr) end
    if action.items and not pickItems(src, action, data.item) then
        return fail('missing_item', 'You do not have what this needs')
    end

    local cid = Patient.PlayerData.citizenid
    local Store = PFMed.Store
    local p = Store.Peek(cid)
    if not p or p.src ~= target then return fail('db_unavailable', 'Their medical record is not loaded yet') end
    local at = now()
    local ctx = { src = src, target = target, prov = prov, action = action, p = p, cid = cid, at = at, params = params,
        where = where, req = data.req, touched = {}, stabilized = 0, treated = 0 }
    -- findings are read before the lock (a database wait); they never change the injuries
    if action.apply == 'decompress' then
        ctx.tension, ctx.tensionSide = TX.TensionFinding(cid, params.side, at)
    end

    if not Store.Lock(cid) then return fail('busy', 'Someone else is treating them right now') end
    local okRun, res = pcall(function()
        local level = p.consciousness
        if level == 'dead' or not action.states[level] then return fail('invalid_state', notReady(level, action)) end
        local handler = H[action.apply]
        if not handler then return fail('bad_args', 'Unknown treatment') end
        local apply, code, msg = handler(ctx)
        if not apply then return fail(code or 'invalid_state', msg) end
        if opts.dry then return { ok = true, dry = true } end
        local set = pickItems(src, action, data.item)
        if not set then return fail('missing_item', 'You do not have what this needs') end
        local used, missing = consume(src, set, 'pf-ambulancejob:treat:' .. action.name)
        if not used then return fail('missing_item', 'You do not have a ' .. tostring(missing)) end
        ctx.items = set
        local changed, message = apply()
        if changed and PATIENT_LEVEL[action.apply] then markCatalogue(ctx) end
        return { ok = true, changed = changed, message = message }
    end)
    Store.Unlock(cid)
    if not okRun then
        print('^1[pf-ambulancejob]^7 treatment failed: ' .. tostring(res))
        return fail('db_unavailable', 'The treatment could not be recorded')
    end
    if not res.ok or res.dry then return res end

    lastDone[src] = at
    TX.stats.treatments = TX.stats.treatments + 1
    local result = ctx.result or (res.changed and 'applied' or 'no_effect')
    local id = TX.Log(ctx, result, ctx.items)
    if action.healing and res.changed then
        TriggerClientEvent('pf-ambulancejob:client:applyTreatmentEffects', target, action.name, action.healing)
    end
    if PFMed.Effects and callable(PFMed.Effects.Push) then pcall(PFMed.Effects.Push, target) end
    -- the recovery machine (17C) takes treated wounds into recovery and sets their restrictions
    if PFMed.Recovery and callable(PFMed.Recovery.Advance) then pcall(PFMed.Recovery.Advance, cid, at) end
    if prov.medical and not isSelf and GetResourceState('pf-services') == 'started' then
        -- a medic call the patient made (Services app or /911e) has been seen to
        pcall(function() exports['pf-services']:CloseByRef('citizen:ems.patient', cid, 'completed', 'treated') end)
    end
    -- hidden injuries stay hidden: the provider learns only what the action did in general
    return { ok = true, id = id, result = { changed = { action = action.name, result = result, stabilized = ctx.stabilized > 0 or nil,
        treated = ctx.treated > 0 or nil }, message = res.message } }
end
TX.Core = treatCore

--- callback pf-ambulancejob:server:treat. Rate limited; a repeated (provider, req) within
--- DedupeSeconds returns the first result (busy and rate-limited answers are not remembered).
function TX.Treat(src, data)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return fail('bad_args') end
    if type(data) ~= 'table' then return fail('bad_args', 'Bad request') end
    local req = data.req
    if req ~= nil and not validReq(req) then return fail('bad_args', 'Bad request id') end
    local key = req and (src .. '|' .. req)
    if key then
        local hit = seen[key]
        if hit and now() - hit.at <= cfg().DedupeSeconds then
            local copy = {}
            for k, v in pairs(hit.result) do copy[k] = v end
            copy.duplicate = true
            return copy
        end
    end
    if limited(src) then return fail('rate_limited', 'Slow down') end
    local clean = { target = data.target, action = data.action, injuryId = data.injuryId, region = data.region, params = data.params,
        side = data.side, req = req, item = type(data.item) == 'string' and #data.item <= 32 and data.item or nil }
    local res = treatCore(src, clean)
    if not res.ok then TX.stats.refused = TX.stats.refused + 1 end
    if key and res.error ~= 'busy' and res.error ~= 'rate_limited' then seen[key] = { at = now(), result = res } end
    return res
end

--- Whether an action could start now (no items used, nothing changed): usable items ask first.
function TX.Precheck(src, action, target, data)
    data = type(data) == 'table' and data or {}
    data.action, data.target = action, target or src
    return treatCore(src, data, { dry = true })
end

-- ── CPR ────────────────────────────────────────────────────────────────────────────────────────

--- callback pf-ambulancejob:server:cprTick(target), sent every CprTickSeconds while compressing.
--- A tick from within CprDistance, with the provider not having moved more than CprMaxMove since
--- the last tick, marks CPR (the engine pauses the arrest-to-death timer while it is recent) and
--- rolls for ROSC at most once per CprTickSeconds.
function TX.CprTick(src, target)
    src = math.tointeger(tonumber(src))
    target = math.tointeger(tonumber(target))
    if not src or src <= 0 or not target or target <= 0 or target == src then return fail('bad_args', 'No patient') end
    local c, at = cfg(), now()
    local Patient = getPlayer(target)
    if not Patient or not pedOf(target) then return fail('offline', 'Patient not found') end
    local prov = TX.Provider(src)
    if not prov then return fail('offline', 'Not loaded') end
    if PFMed.Down.IsDown(src) then return fail('invalid_state', 'You are down') end
    local here = posOf(src)
    local rec = cprRec[src]
    if dist(here, posOf(target)) > num(c.CprDistance, 1.5) then
        cprRec[src] = nil
        return fail('too_far', 'Get closer to do CPR')
    end
    if rec and rec.target == target and at - rec.at <= c.CprTickSeconds * 3 and dist(rec.pos, here) > num(c.CprMaxMove, 1.0) then
        rec.pos, rec.at = here, at
        return fail('invalid_state', 'Stay in place while doing CPR')
    end
    local cid = Patient.PlayerData.citizenid
    local p = PFMed.Store.Peek(cid)
    if not p or p.src ~= target then return fail('db_unavailable', 'Their medical record is not loaded yet') end
    if p.consciousness ~= 'arrest' then
        cprRec[src] = nil
        return fail('invalid_state', p.consciousness == 'dead' and 'They are beyond help' or 'They have a pulse')
    end
    local fresh = not rec or rec.target ~= target or at - rec.at > c.CprTickSeconds * 3
    if fresh then rec = { target = target, sessionAt = at, rollAt = at } end
    rec.pos, rec.at = here, at
    cprRec[src] = rec
    p.cpr_last_at = at
    local where = TX.Where(src, target)
    local ctx = { src = src, target = target, prov = prov, action = T.Actions.cpr, p = p, cid = cid, at = at, params = {},
        where = where, touched = {}, stabilized = 0, treated = 0 }
    if fresh then TX.Log(ctx, 'started') end
    local back = false
    if not fresh and at - (rec.rollAt or 0) >= c.CprTickSeconds and PFMed.Store.Lock(cid) then
        rec.rollAt = at
        local ok, res = pcall(function()
            local chance = TX.RoscChance(p, at, 'cpr')
            return chance > 0 and TX.Random() < chance and rosc(ctx, 'cpr')
        end)
        PFMed.Store.Unlock(cid)
        back = ok and res == true
        if back then
            cprRec[src] = nil
            TX.Log(ctx, 'rosc')
            if PFMed.Effects and callable(PFMed.Effects.Push) then pcall(PFMed.Effects.Push, target) end
        end
    end
    return { ok = true, result = { changed = { action = 'cpr', rosc = back or nil }, message = back and 'Pulse is back' or 'CPR in progress' } }
end

-- ── legacy entry points ────────────────────────────────────────────────────────────────────────

local function notify(src, res)
    if not res then return end
    local msg = res.ok and (res.result and res.result.message) or res.message
    if msg then TriggerClientEvent('QBCore:Notify', src, msg, res.ok and 'success' or 'error') end
end
TX.Notify = notify

--- pf-ambulancejob:server:applyTreatment(targetId, treatmentType) (EMS MDT panel, old /treat).
function TX.Legacy(src, targetId, key)
    local action = type(key) == 'string' and (T.LegacyKeys[key] or (T.Actions[key] and key)) or nil
    if not action then
        local res = fail('bad_args', 'Invalid treatment type')
        notify(src, res)
        return res
    end
    local res = TX.Treat(src, { target = targetId, action = action })
    notify(src, res)
    return res
end

--- hospital:server:RevivePlayer from an on-duty medic: the treatment for the patient's state
--- (unconscious: revive; arrest: a shock when an AED is at hand and the rhythm allows it, else CPR;
--- dead: nothing, a dead patient goes to the hospital).
function TX.LegacyRevive(src, targetId)
    local target = math.tointeger(tonumber(targetId))
    if not target then return fail('bad_args') end
    local _, st = PFMed.Down.IsDown(target)
    local action = 'first_aid_revive'
    if st == 'arrest' then
        local where = TX.Where(src, target)
        action = (hasItem(src, 'aed', 1) or where.rig) and 'defibrillate' or 'cpr'
    elseif st == 'dead' then
        local res = fail('invalid_state', 'They are beyond help: they need the hospital')
        notify(src, res)
        return res
    end
    local res = TX.Treat(src, { target = target, action = action })
    if not res.ok and action == 'defibrillate' and res.error == 'invalid_state' then res = TX.Treat(src, { target = target, action = 'cpr' }) end
    notify(src, res)
    return res
end

-- ── tick: tourniquet time, memory bounds ───────────────────────────────────────────────────────

--- One pass (every 60 s): a tourniquet left on past TourniquetLimitSeconds damages the limb once
--- (a keyed injury, so a retry never adds a second); old dedupe and rate entries are dropped.
function TX.Tick(at)
    at = at or now()
    local c = cfg()
    local due = {}
    PFMed.Store.Each(function(cid, p)
        for id, inj in pairs(p.injuries or {}) do
            local tr = trOf(inj)
            local on = tonumber(tr.tourniquet)
            if on and inj.stage ~= 'recovered' and not tr.tq_damage and at - on >= c.TourniquetLimitSeconds then
                due[#due + 1] = { cid = cid, id = id, region = inj.region }
            end
        end
    end)
    for _, d in ipairs(due) do
        local actor = { kind = 'system', label = 'tourniquet' }
        local spec = { type = 'crush', subtype = 'limb', region = d.region, severity = c.TourniquetDamageSeverity, mechanism = 'crush',
            note = 'Tourniquet left on too long' }
        local inj, err = PFMed.Engine.AddInjury(d.cid, spec, { key = 'pf-ambulancejob:tourniquet:' .. d.id, source = 'treatment', actor = actor })
        if inj or err == 'bad_args' or err == 'conflict' or err == 'key_reused' then
            PFMed.Engine.UpdateInjury(d.cid, d.id, { treatments = { tq_damage = true } }, { actor = actor, source = 'treatment' })
            local src = PFMed.Store.SourceOf(d.cid)
            if src and PFMed.Effects and callable(PFMed.Effects.Push) then pcall(PFMed.Effects.Push, src) end
        end
    end
    for k, v in pairs(seen) do if at - v.at > c.DedupeSeconds then seen[k] = nil end end
    for s, r in pairs(rate) do if at - r.at > 60 then rate[s] = nil end end
    for s, r in pairs(cprRec) do if at - r.at > 60 then cprRec[s] = nil end end
    for cid, t in pairs(defibAt) do if at - t > 600 then defibAt[cid] = nil end end
    return #due
end

function TX.Forget(src)
    rate[src], lastDone[src], tierCache[src], cprRec[src] = nil, nil, nil, nil
end

-- An airway adjunct comes out when the patient wakes up (a conscious patient does not keep an OPA).
if PFMed.Engine and PFMed.Engine.OnConsciousness then
    PFMed.Engine.OnConsciousness(function(cid, _, to)
        if to ~= 'alert' or not airwayDevice[cid] then return end
        airwayDevice[cid] = nil
        local p = PFMed.Store.Peek(cid)
        if p and p.airway == 'secured' then p.airway = 'clear'; PFMed.Store.MarkDirty(cid) end
    end)
end

-- ── callbacks and events ───────────────────────────────────────────────────────────────────────

local Core = PFAmbulance.GetCore()
Core.Functions.CreateCallback('pf-ambulancejob:server:treat', function(source, cb, data)
    cb(TX.Treat(tonumber(source), data))
end)

Core.Functions.CreateCallback('pf-ambulancejob:server:cprTick', function(source, cb, target)
    local src = math.tointeger(tonumber(source))
    if not src or src <= 0 then return cb(fail('bad_args')) end
    if limited(src) then return cb(fail('rate_limited', 'Slow down')) end
    cb(TX.CprTick(src, target))
end)

-- What the caller may do (menus only; every action is checked again when it is asked for).
Core.Functions.CreateCallback('pf-ambulancejob:server:treatOptions', function(source, cb)
    local src = math.tointeger(tonumber(source))
    local prov = src and TX.Provider(src)
    if not prov then return cb({ ok = false, error = 'offline' }) end
    cb({ ok = true, tier = prov.tier, medical = prov.medical, actions = T.ListFor(prov.tier) })
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then TX.Forget(src) end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    src = tonumber(src)
    if src then TX.Forget(src) end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local ok, err = pcall(TX.Tick, os.time())
        if not ok then print('^1[pf-ambulancejob]^7 treatment tick failed: ' .. tostring(err)) end
    end
end)
