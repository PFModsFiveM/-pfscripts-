-- Physiology model (architecture 11.3, 5.1): pure, deterministic functions. Given a patient's state
-- (blood volume, airway, toxins, drugs...) and their open injuries, it derives vitals and decides the
-- consciousness transitions. Nothing here touches the game, the database or the clock: callers pass
-- `now` and `dt`. Vitals are never stored as facts; they are recomputed from the state.

PFMed = PFMed or {}
PFMed.Physiology = PFMed.Physiology or {}
local P = PFMed.Physiology

P.Defaults = {
    Physiology = {
        BloodMl = 5000,
        HrBase = 75, HrByClass = { 0, 25, 45, 65 }, HrPain = 2, HrMin = 30, HrMax = 190,
        SbpBase = 120, SbpByClass = { 0, 0, 30, 60 }, DbpRatio = 0.65,
        TensionSbp = 30, TamponadeSbp = 25, SpinalShockSbp = 20, SpinalShockHr = 20,
        RrBase = 14, RrPerClass = 3, RrMax = 40,
        Spo2Base = 98, Spo2Min = 50, Spo2Max = 100,
        AirwayFactor = { clear = 1.0, partial = 0.8, obstructed = 0.3, secured = 1.0 },
        UnconsciousAirway = 'partial',  -- an unprotected airway of an unconscious patient (nil: off)
        ClotPerTick = 0.01, ClotTickSeconds = 5, StopBelowMlPerMin = 0.05,
        RegenMlPerMin = 0.5,
        NormalTemp = 37.0, TempDriftPerMin = 0.05, FeverHrPerDegree = 10,
        HeadPenaltyMax = 12,
    },
    Consciousness = {
        RecoverSeconds = 10,          -- GCS above the threshold this long before waking up a level
        HypoxiaSpo2 = 60, HypoxiaSeconds = 30,
        ArrestSbp = 50, ArrestLossFraction = 0.5,
        ArrestToDeathSeconds = 300,
        CprWindowSeconds = 10,        -- a CPR tick this recent pauses the arrest-to-death timer
        RespawnAfterSeconds = 300,
    },
    -- Toxins: `severe` is the level that counts as 1.0 intensity; elimination is linear (perHour) or
    -- by half-life (minutes). Effects scale with intensity x: hr/rr/temp/pain add x * value,
    -- breathing loses x * value, hgb loses x * value of carrying capacity, gcs from thresholds.
    Toxins = {
        ethanol         = { unit = 'bac', severe = 0.30, max = 0.60, perHour = 0.015, hr = 5, breathing = 0.15, gcs = { { 0.5, 1 }, { 0.8, 3 }, { 1.1, 6 }, { 1.3, 9 } } },
        opioid          = { unit = 'mg', severe = 60, max = 400, halfLife = 180, hr = -10, rr = -8, breathing = 0.45, gcs = { { 0.5, 2 }, { 1.0, 5 }, { 1.5, 8 } } },
        stimulant       = { unit = 'mg', severe = 200, max = 1000, halfLife = 90, hr = 20, temp = 0.4, gcs = { { 2.0, 2 } } },
        sedative        = { unit = 'mg', severe = 60, max = 400, halfLife = 360, hr = -5, rr = -4, breathing = 0.25, gcs = { { 0.5, 2 }, { 1.0, 5 }, { 1.5, 8 } } },
        cannabis        = { unit = 'mg', severe = 50, max = 300, halfLife = 120, hr = 10, gcs = { { 1.5, 1 } } },
        poison          = { unit = 'units', severe = 1, max = 5, halfLife = 240, hr = 15, pain = 3, breathing = 0.2, gcs = { { 0.7, 2 }, { 1.2, 5 }, { 1.8, 9 } } },
        carbon_monoxide = { unit = 'cohb_pct', severe = 40, max = 80, halfLife = 300, oxygenHalfLife = 75, hgb = 0.4, gcs = { { 0.5, 2 }, { 1.0, 5 }, { 1.5, 9 } } },
        food_poisoning  = { unit = 'units', severe = 1, max = 3, halfLife = 360, hr = 15, pain = 4, temp = 1.5 },
    },
    -- Drugs given by treatment (17B): state.drugs[name] = { mg, at }; active for `duration` seconds.
    Drugs = {
        morphine    = { duration = 14400, analgesia = 3 },
        fentanyl    = { duration = 3600, analgesia = 4 },
        naloxone    = { duration = 3600, antagonist = { opioid = 2.0 } },
        epinephrine = { duration = 600, sbp = 15, hr = 20 },
        txa         = { duration = 10800, bleedFactor = 0.7 },
        oxygen      = { duration = 600, spo2 = 4 },
        ventilation = { duration = 120, breathingFloor = 0.9 },
    },
    -- Multipliers on a wound's bleeding from treatments (injury.treatments, set by 17B).
    BleedTreatment = { tourniquet = 0, pressure = 0.3, hemostatic = 0.2, binder = 0.5 },
}

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function round(v, d)
    if not d or d == 0 then return math.floor(v + 0.5) end
    local m = 10 ^ d
    return math.floor(v * m + 0.5) / m
end
P.Clamp, P.Round = clamp, round

local function merged(cfg, key)
    local d, c = P.Defaults[key], cfg and cfg[key]
    if type(c) ~= 'table' then return d end
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    for k, v in pairs(c) do out[k] = v end
    return out
end

--- Model configuration: the defaults above with Config.Medical's blocks on top.
function P.Cfg(cfg)
    if type(cfg) == 'table' and cfg.__resolved then return cfg end
    local src = cfg or (Config and Config.Medical) or {}
    return {
        __resolved = true,
        Physiology = merged(src, 'Physiology'), Consciousness = merged(src, 'Consciousness'),
        Toxins = merged(src, 'Toxins'), Drugs = merged(src, 'Drugs'), BleedTreatment = merged(src, 'BleedTreatment'),
    }
end

--- A healthy patient's state.
function P.NewState(cfg)
    cfg = P.Cfg(cfg)
    return {
        blood_ml = cfg.Physiology.BloodMl, hgb_factor = 1.0, airway = 'clear', breathing = 1.0, pain = 0,
        temp_c = cfg.Physiology.NormalTemp, toxins = {}, drugs = {},
    }
end

function P.CopyState(s)
    local out = {}
    for k, v in pairs(s or {}) do out[k] = v end
    out.toxins, out.drugs = {}, {}
    for k, v in pairs((s and s.toxins) or {}) do out.toxins[k] = v end
    for k, v in pairs((s and s.drugs) or {}) do out.drugs[k] = type(v) == 'table' and { mg = v.mg, at = v.at } or v end
    return out
end

function P.LossFraction(blood_ml, cfg)
    cfg = P.Cfg(cfg)
    local full = cfg.Physiology.BloodMl
    return clamp((full - (tonumber(blood_ml) or full)) / full, 0, 1)
end

--- Haemorrhage class 1..4 (I: <15 %, II: 15-30 %, III: 30-40 %, IV: >40 %).
function P.LossClass(blood_ml, cfg)
    local loss = P.LossFraction(blood_ml, cfg)
    if loss < 0.15 then return 1 elseif loss < 0.30 then return 2 elseif loss <= 0.40 then return 3 end
    return 4
end

--- The drug entry when it is active at `now`.
function P.DrugActive(state, name, now, cfg)
    cfg = P.Cfg(cfg)
    local d = state and state.drugs and state.drugs[name]
    local def = cfg.Drugs[name]
    if type(d) ~= 'table' or not def then return nil end
    local at = tonumber(d.at)
    if not at or now < at or now >= at + (def.duration or 0) then return nil end
    return d, def
end

--- Toxin intensity (level / severe), reduced by an active antagonist (naloxone for opioids).
function P.ToxinIntensity(state, name, now, cfg)
    cfg = P.Cfg(cfg)
    local def = cfg.Toxins[name]
    local level = state and state.toxins and tonumber(state.toxins[name]) or 0
    if not def or level <= 0 then return 0 end
    local x = level / def.severe
    for drug, ddef in pairs(cfg.Drugs) do
        if ddef.antagonist and ddef.antagonist[name] and P.DrugActive(state, drug, now, cfg) then
            x = math.max(0, x - ddef.antagonist[name])
        end
    end
    return x
end

local function isOpen(inj)
    local st = inj and inj.stage
    return st ~= 'recovered' and st ~= nil
end
P.IsOpen = isOpen

--- A wound's bleeding right now in ml/min, after treatments and TXA. Wounds that reached definitive
--- care (treated, recovering, recovered) no longer bleed.
function P.WoundBleed(inj, state, now, cfg)
    cfg = P.Cfg(cfg)
    if not isOpen(inj) or inj.stage == 'treated' or inj.stage == 'recovering' then return 0 end
    local b = tonumber(inj.bleed_ml_min) or 0
    if b <= 0 then return 0 end
    local tr = type(inj.treatments) == 'table' and inj.treatments or {}
    for key, mult in pairs(cfg.BleedTreatment) do
        if tr[key] then b = b * mult end
    end
    for name, def in pairs(cfg.Drugs) do
        if def.bleedFactor and P.DrugActive(state, name, now, cfg) then b = b * def.bleedFactor end
    end
    return b
end

local AIRWAY_RANK = { clear = 0, secured = 0, partial = 1, obstructed = 2 }

--- Everything the open injuries contribute (breathing loss, head penalty, threats, fever, pain).
function P.Conditions(injuries, cfg)
    cfg = P.Cfg(cfg)
    local I = PFMed.Injuries
    local c = { breathingLoss = 0, headPenalty = 0, fever = 0, sbpDrop = 0, hrAdd = 0, tension = 0, airway = 'clear', pains = {} }
    for _, inj in pairs(injuries or {}) do
        if isOpen(inj) then
            local f = I.Physiology(inj)
            c.breathingLoss = c.breathingLoss + f.breathing
            c.headPenalty = c.headPenalty + f.headPenalty
            c.fever = c.fever + f.fever
            c.sbpDrop = c.sbpDrop + f.sbpDrop
            c.hrAdd = c.hrAdd + f.hrAdd
            if f.tension then c.tension = 1 end
            if f.tamponade then c.tamponade = true end
            if f.spinalShock then c.spinalShock = true end
            if f.lethal then c.lethal = true; c.lethalCause = f.cause end
            if f.arrest then c.arrest = true; c.arrestCause = f.cause end
            if f.arrhythmia then c.arrhythmia = true end
            if f.airway and AIRWAY_RANK[f.airway] > AIRWAY_RANK[c.airway] then c.airway = f.airway end
            local pain = tonumber(inj.pain) or 0
            local tr = type(inj.treatments) == 'table' and inj.treatments or {}
            if tr.cast then pain = pain - 3 elseif tr.splinted then pain = pain - 2 end
            if pain > 0 then c.pains[#c.pains + 1] = pain end
        end
    end
    c.breathingLoss = clamp(c.breathingLoss, 0, 0.9)
    c.headPenalty = clamp(c.headPenalty, 0, cfg.Physiology.HeadPenaltyMax)
    return c
end

local function toxinSum(state, now, cfg, field)
    local total = 0
    for name, def in pairs(cfg.Toxins) do
        if def[field] then total = total + def[field] * P.ToxinIntensity(state, name, now, cfg) end
    end
    return total
end

local function toxinGcs(state, now, cfg)
    local total = 0
    for name, def in pairs(cfg.Toxins) do
        local x = P.ToxinIntensity(state, name, now, cfg)
        local pen = 0
        for _, th in ipairs(def.gcs or {}) do if x >= th[1] then pen = th[2] end end
        total = total + pen
    end
    return total
end

local function drugSum(state, now, cfg, field)
    local total = 0
    for name, def in pairs(cfg.Drugs) do
        if def[field] and P.DrugActive(state, name, now, cfg) then total = total + def[field] end
    end
    return total
end

--- Pain 0..10: the worst wound plus half of the rest, plus toxin pain, minus active analgesia.
function P.Pain(state, conds, now, cfg)
    cfg = P.Cfg(cfg)
    local list = {}
    for i, v in ipairs(conds.pains) do list[i] = v end
    table.sort(list, function(a, b) return a > b end)
    local total = list[1] or 0
    for i = 2, #list do total = total + 0.5 * list[i] end
    total = total + toxinSum(state, now, cfg, 'pain')
    total = math.min(10, total) - drugSum(state, now, cfg, 'analgesia')
    return clamp(round(total, 1), 0, 10)
end

--- Vitals derived from state + injuries. `consciousness` 'arrest' or 'dead' gives no output.
--- Returns { hr, sbp, dbp, rr, spo2, temp, gcs, pain, lossFraction, lossClass, shock, airway, breathing, conditions }.
function P.Vitals(state, injuries, now, cfg, consciousness)
    cfg = P.Cfg(cfg)
    local ph = cfg.Physiology
    local conds = P.Conditions(injuries, cfg)
    local loss = P.LossFraction(state.blood_ml, cfg)
    local class = P.LossClass(state.blood_ml, cfg)
    local pain = P.Pain(state, conds, now, cfg)

    local airway = state.airway or 'clear'
    if airway ~= 'secured' then
        if AIRWAY_RANK[conds.airway] > (AIRWAY_RANK[airway] or 0) then airway = conds.airway end
        if consciousness == 'unconscious' and ph.UnconsciousAirway and (AIRWAY_RANK[airway] or 0) < AIRWAY_RANK[ph.UnconsciousAirway] then
            airway = ph.UnconsciousAirway
        end
    end

    local mech = 1 - conds.breathingLoss
    local depress = clamp(1 - toxinSum(state, now, cfg, 'breathing'), 0, 1)
    local breathing = (tonumber(state.breathing) or 1) * mech * depress
    for name, def in pairs(cfg.Drugs) do
        if def.breathingFloor and P.DrugActive(state, name, now, cfg) then breathing = math.max(breathing, def.breathingFloor) end
    end
    breathing = clamp(breathing, 0, 1)

    local hgb = clamp((tonumber(state.hgb_factor) or 1) * (1 - toxinSum(state, now, cfg, 'hgb')), 0.05, 1)
    local airwayFactor = ph.AirwayFactor[airway] or 1
    local spo2 = clamp(ph.Spo2Base * breathing * airwayFactor * hgb ^ 0.3 + drugSum(state, now, cfg, 'spo2'), ph.Spo2Min, ph.Spo2Max)

    local tension = conds.tension
    local sbp = ph.SbpBase - ph.SbpByClass[class] - ph.TensionSbp * tension - (conds.tamponade and ph.TamponadeSbp or 0)
        - (conds.spinalShock and ph.SpinalShockSbp or 0) + drugSum(state, now, cfg, 'sbp') - conds.sbpDrop

    local temp = tonumber(state.temp_c) or ph.NormalTemp
    -- toxins carry the 11.3 terms (stimulant +20x, opioid -10x) in their `hr` values
    local hr = ph.HrBase + ph.HrByClass[class] + ph.HrPain * pain + toxinSum(state, now, cfg, 'hr')
        + drugSum(state, now, cfg, 'hr') + conds.hrAdd - (conds.spinalShock and ph.SpinalShockHr or 0)
        + math.max(0, temp - 37.5) * ph.FeverHrPerDegree

    local hypoxiaDrive = (spo2 < 90 and 4 or 0) + (spo2 < 80 and 4 or 0)
    local rr = ph.RrBase + ph.RrPerClass * (class - 1) + hypoxiaDrive + toxinSum(state, now, cfg, 'rr')
    if airway == 'obstructed' then rr = 0 end

    local gcs = 15 - conds.headPenalty - (spo2 < 85 and 3 or 0) - (spo2 < 75 and 3 or 0)
        - (sbp < 80 and 3 or 0) - (sbp < 60 and 3 or 0) - toxinGcs(state, now, cfg)

    local shock = class
    if conds.tension > 0 or conds.tamponade or conds.spinalShock then shock = math.min(4, shock + 1) end

    local v = {
        hr = round(clamp(hr, ph.HrMin, ph.HrMax)), sbp = round(math.max(0, sbp)), rr = round(clamp(rr, 0, ph.RrMax)),
        spo2 = round(spo2), temp = round(temp, 1), gcs = round(clamp(gcs, 3, 15)), pain = pain,
        lossFraction = round(loss, 3), lossClass = class, shock = shock, airway = airway, breathing = round(breathing, 3),
        conditions = conds,
    }
    v.dbp = round(v.sbp * ph.DbpRatio)
    if consciousness == 'arrest' or consciousness == 'dead' then
        v.hr, v.sbp, v.dbp, v.rr, v.spo2, v.gcs = 0, 0, 0, 0, 0, 3
    end
    v.rhythm = P.Rhythm(v, conds, consciousness)
    return v
end

--- Heart rhythm a monitor would show (the defibrillator in 17B reads it).
function P.Rhythm(v, conds, consciousness, cause)
    if consciousness == 'dead' then return 'asystole' end
    if consciousness == 'arrest' then
        cause = cause or (conds and (conds.arrestCause or conds.lethalCause))
        if cause == 'arrhythmia' then return 'vf' end
        if cause == 'head_trauma' or cause == 'hypoxia' then return 'asystole' end
        return 'pea'
    end
    if conds and conds.arrhythmia then return 'irregular' end
    if v.hr > 100 then return 'sinus_tachycardia' end
    if v.hr < 60 then return 'sinus_bradycardia' end
    return 'sinus'
end

local function clotFactor(cfg, seconds)
    local ph = cfg.Physiology
    return (1 - ph.ClotPerTick) ^ (seconds / ph.ClotTickSeconds)
end

-- Blood lost over `seconds` from a wound bleeding `rate` ml/min that clots with factor r per tick.
local function lostWhileClotting(rate, seconds, cfg)
    local ph = cfg.Physiology
    local r = 1 - ph.ClotPerTick
    local k = math.log(r) / ph.ClotTickSeconds
    if k == 0 then return rate * seconds / 60 end
    return rate / 60 * (math.exp(k * seconds) - 1) / k
end

local function eliminate(level, def, seconds, oxygen)
    if def.perHour then return math.max(0, level - def.perHour * seconds / 3600) end
    local hl = (oxygen and def.oxygenHalfLife) or def.halfLife
    if not hl or hl <= 0 then return level end
    return level * 0.5 ^ (seconds / 60 / hl)
end

--- Advances the state by `dt` seconds. Pure: returns a new state, the new stored bleed of each wound
--- (by injury id, after clotting) and totals { bleed (ml/min now), external, internal, lost (ml) }.
--- opts.noLoss: wounds still clot and toxins clear, but no blood is lost (offline time past the cap).
function P.Step(state, injuries, dt, now, cfg, opts)
    cfg = P.Cfg(cfg)
    opts = opts or {}
    local ph = cfg.Physiology
    local s = P.CopyState(state)
    dt = math.max(0, tonumber(dt) or 0)
    local bleeds, totals = {}, { bleed = 0, external = 0, internal = 0, lost = 0 }
    local clot = clotFactor(cfg, dt)
    for id, inj in pairs(injuries or {}) do
        if isOpen(inj) then
            local stored = tonumber(inj.bleed_ml_min) or 0
            local rate = P.WoundBleed(inj, state, now, cfg)
            local attrs = type(inj.attrs) == 'table' and inj.attrs or {}
            local clots = not attrs.noclot
            if rate > 0 and not opts.noLoss then
                totals.lost = totals.lost + (clots and lostWhileClotting(rate, dt, cfg) or rate * dt / 60)
            end
            if stored > 0 and clots then
                local nxt = stored * clot
                if nxt < ph.StopBelowMlPerMin then nxt = 0 end
                bleeds[inj.id or id] = round(nxt, 3)
            end
        end
    end
    -- what is still bleeding after this step (for display and for the regeneration rule)
    for id, inj in pairs(injuries or {}) do
        if isOpen(inj) then
            local copy = inj
            local nb = bleeds[inj.id or id]
            if nb then copy = { stage = inj.stage, bleed_ml_min = nb, treatments = inj.treatments } end
            local r = P.WoundBleed(copy, state, now, cfg)
            totals.bleed = totals.bleed + r
            local attrs = type(inj.attrs) == 'table' and inj.attrs or {}
            if attrs.internal or attrs.fluid then totals.internal = totals.internal + r else totals.external = totals.external + r end
        end
    end
    s.blood_ml = math.max(0, (tonumber(s.blood_ml) or ph.BloodMl) - totals.lost)
    if totals.bleed <= 0 and not opts.arrest then
        s.blood_ml = math.min(ph.BloodMl, s.blood_ml + ph.RegenMlPerMin * dt / 60)
    end
    s.blood_ml = round(s.blood_ml, 1)

    local oxygen = P.DrugActive(state, 'oxygen', now, cfg) ~= nil
    for name, level in pairs(s.toxins) do
        local def = cfg.Toxins[name]
        local v = def and eliminate(tonumber(level) or 0, def, dt, oxygen) or 0
        if not def or v < def.severe * 0.01 then s.toxins[name] = nil else s.toxins[name] = round(v, 4) end
    end
    local later = now + dt
    for name, d in pairs(s.drugs) do
        local def = cfg.Drugs[name]
        if not def or type(d) ~= 'table' or (tonumber(d.at) or 0) + (def.duration or 0) <= later then s.drugs[name] = nil end
    end

    local conds = P.Conditions(injuries, cfg)
    local target = ph.NormalTemp + conds.fever + toxinSum(state, now, cfg, 'temp')
    local temp = tonumber(s.temp_c) or ph.NormalTemp
    local maxMove = ph.TempDriftPerMin * dt / 60
    if math.abs(target - temp) <= maxMove then temp = target elseif target > temp then temp = temp + maxMove else temp = temp - maxMove end
    s.temp_c = round(temp, 2)
    return s, bleeds, totals
end

--- Offline catch-up: bleeding counts for at most `maxBleedSeconds` of the gap (a crash should not
--- kill, a log-out should not heal a wound), the rest only clots wounds, clears toxins and drugs.
function P.Rest(state, injuries, seconds, now, cfg, maxBleedSeconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    local first = math.min(seconds, math.max(0, tonumber(maxBleedSeconds) or 0))
    local s, bleeds, totals = P.Step(state, injuries, first, now, cfg)
    local rest = seconds - first
    if rest <= 0 then return s, bleeds, totals end
    local after = {}
    for id, inj in pairs(injuries or {}) do
        local copy = {}
        for k, v in pairs(inj) do copy[k] = v end
        if bleeds[inj.id or id] then copy.bleed_ml_min = bleeds[inj.id or id] end
        after[id] = copy
    end
    local s2, bleeds2, totals2 = P.Step(s, after, rest, now + first, cfg, { noLoss = true })
    for k, v in pairs(bleeds2) do bleeds[k] = v end
    totals2.lost = totals.lost
    return s2, bleeds, totals2
end

--- Volume given by treatment (17B): saline adds volume only and dilutes the carrying capacity,
--- blood adds volume at full capacity.
function P.AddVolume(state, kind, ml, cfg)
    cfg = P.Cfg(cfg)
    local s = P.CopyState(state)
    ml = math.max(0, tonumber(ml) or 0)
    local blood = tonumber(s.blood_ml) or cfg.Physiology.BloodMl
    local hgb = tonumber(s.hgb_factor) or 1
    local cap = cfg.Physiology.BloodMl * 1.1
    local add = math.min(ml, math.max(0, cap - blood))
    if add <= 0 then return s end
    local quality = (kind == 'blood') and 1 or 0
    s.hgb_factor = round((hgb * blood + quality * add) / (blood + add), 3)
    s.blood_ml = round(blood + add, 1)
    return s
end

-- Consciousness transitions (architecture 5.1). 'auto' ones are decided by P.NextConsciousness;
-- the others need an outside trigger: 'report' (ReportDown, 16A), 'rosc' (CPR/defib, 17B),
-- 'revive' (admin / script revive, 16A), 'respawn' (hospital respawn, 16A).
P.Transitions = {
    alert       = { altered = { auto = true }, unconscious = { auto = true, report = true } },
    altered     = { alert = { auto = true }, unconscious = { auto = true, report = true } },
    unconscious = { altered = { auto = true }, arrest = { auto = true }, alert = { revive = true } },
    arrest      = { unconscious = { rosc = true }, dead = { auto = true }, alert = { revive = true } },
    dead        = { alert = { revive = true, respawn = true } },
}
P.Levels = { alert = true, altered = true, unconscious = true, arrest = true, dead = true }

--- Whether `from -> to` is allowed for the trigger kind ('auto', 'report', 'rosc', 'revive', 'respawn').
function P.CanTransition(from, to, kind)
    local t = P.Transitions[from]
    local e = t and t[to]
    return e ~= nil and e[kind or 'auto'] == true
end

--- Whether the arrest criteria hold (SBP, sustained hypoxia, loss > 50 %, lethal trauma).
function P.ArrestCause(v, ctx, now, cfg)
    cfg = P.Cfg(cfg)
    local cc = cfg.Consciousness
    local conds = v.conditions or {}
    if conds.lethal then return conds.lethalCause or 'head_trauma' end
    if conds.arrest then return conds.arrestCause or 'arrhythmia' end
    if v.lossFraction > cc.ArrestLossFraction then return 'hemorrhage' end
    if v.sbp < cc.ArrestSbp then return 'hypotension' end
    if ctx.hypoxSince and now - ctx.hypoxSince >= cc.HypoxiaSeconds then return 'hypoxia' end
    return nil
end

--- One evaluation of the automatic consciousness machine. Pure: `ctx` is copied, never changed.
--- ctx = { hypoxSince, okSince, holdUntil, arrestSince }. Returns nextLevel, cause, newCtx.
--- Arrest criteria met by a conscious patient make them unconscious first (one level per call).
function P.NextConsciousness(cur, v, ctx, now, cfg)
    cfg = P.Cfg(cfg)
    local cc = cfg.Consciousness
    local c = {}
    for k, val in pairs(ctx or {}) do c[k] = val end

    if v.spo2 > 0 and v.spo2 < cc.HypoxiaSpo2 then c.hypoxSince = c.hypoxSince or now else c.hypoxSince = nil end

    if cur == 'dead' then return 'dead', nil, c end
    if cur == 'arrest' then
        if c.arrestSince and now - c.arrestSince >= cc.ArrestToDeathSeconds then return 'dead', 'arrest_timeout', c end
        return 'arrest', nil, c
    end

    local held = c.holdUntil and now < c.holdUntil
    local cause = P.ArrestCause(v, c, now, cfg)
    if cur == 'unconscious' then
        if cause then c.okSince = nil; return 'arrest', cause, c end
        if v.gcs >= 9 and not held then
            c.okSince = c.okSince or now
            if now - c.okSince >= cc.RecoverSeconds then c.okSince = nil; return 'altered', 'recovered', c end
        else
            c.okSince = nil
        end
        return 'unconscious', nil, c
    end

    -- alert / altered
    if cause or v.gcs <= 8 then c.okSince = nil; return 'unconscious', cause or 'gcs', c end
    if cur == 'alert' then
        if v.gcs <= 13 then return 'altered', 'gcs', c end
        return 'alert', nil, c
    end
    if v.gcs >= 14 then
        c.okSince = c.okSince or now
        if now - c.okSince >= cc.RecoverSeconds then c.okSince = nil; return 'alert', 'recovered', c end
    else
        c.okSince = nil
    end
    return 'altered', nil, c
end
