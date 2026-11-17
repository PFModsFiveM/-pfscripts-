-- Treatment catalogue (architecture 11.7, 4.3): every action a provider can perform, with the tier
-- and qualification it needs (scope of practice, 11.6), where it may be done, the items it uses up
-- and the equipment it needs (held, or in an ambulance within reach), which levels of consciousness
-- allow it, and the handler the server runs. Pure data plus small helpers; shared with the client,
-- which uses it only to build menus (the server decides everything again).
--
-- Fields of an action:
--   label, tier (0 anyone .. 5 physician), qual (a pf-government qualification on top of the tier),
--   self (may be done on yourself; selfTier is then the tier needed, default 0), location = { field, rig, hospital } (any one is enough),
--   items = { name = count } used up, alt = { { name = count }, ... } accepted instead of items,
--   equipment = { names } held or carried by an ambulance within Rig.Distance (never used up),
--   duration (ms on the client; the server spaces a provider's treatments by it),
--   states = { level = true } (default: anyone not dead), target = 'wound' | 'region' | 'patient',
--   regions = { region = true } a regional action is limited to, hidden = true (the item is used
--   even when nothing is found: hidden injuries must not be probed for), needsIv, redose (seconds
--   before the same drug again), healing (ped health the patient's client adds), apply (handler key).

PFMed = PFMed or {}
PFMed.Treatments = PFMed.Treatments or {}
local T = PFMed.Treatments

-- ── tunables (Config.Medical.Treatment overrides any key) ─────────────────────────────────────

T.Defaults = {
    TouchDistance = 2.5,          -- provider to patient (architecture 6.4)
    CprDistance = 1.5,            -- CPR ticks count only this close ...
    CprMaxMove = 1.0,             -- ... and when the provider moved no more than this since the last tick
    CprTickSeconds = 5,           -- client tick period; a ROSC roll at most once per this
    CprMinTickSeconds = 3,        -- faster ticks are accepted but count nothing
    CprRoscChance = 0.06,         -- per counted tick, non-shockable arrest whose causes are corrected
    CprVfChance = 0.02,           -- per counted tick in VF (needs a shock)
    EpiRoscBonus = 0.08,          -- epinephrine active
    VentRoscBonus = 0.04,         -- ventilated (BVM active or airway secured)
    DefibRoscChance = 0.5,        -- per shock in VF with no other uncorrected cause
    DefibCooldownSeconds = 10,    -- per patient between shocks (the AED charges and analyses)
    StableBleed = 1.0,            -- ml/min at or below which a wound's bleeding counts as controlled
    TourniquetLimitSeconds = 7200, -- a tourniquet on longer than this damages the limb (once)
    TourniquetDamageSeverity = 3,
    DedupeSeconds = 30,           -- a repeated (provider, req) returns the first result
    RateBurst = 4, RatePerSecond = 2,  -- treat calls per provider (architecture 6.3)
    BusyFactor = 0.8,             -- a provider's next treatment needs this share of its duration since the last
    TierCacheSeconds = 15,        -- provider tier cache
    HospitalRadius = 60.0,        -- fallback hospital zone around Config.Locations.hospital points
    Rig = { Distance = 6.0 },     -- ambulance stock and rig actions within this of the provider
    FindingSeconds = 3600,        -- findings this recent count for a treatment's precondition
    -- signs (17A findings) or a diagnosis that justify a needle decompression
    TensionSigns = { absent_breath_sounds = true, tracheal_deviation = true, absent_lung_sliding = true, collapsed_lung = true },
    -- the civilian self-care items (server/items.lua)
    SelfItems = { bandage = 'bandage', ifaks = 'ifaks', painkillers = 'painkillers', tourniquet = 'tourniquet',
        pressure_dressing = 'pressure_dressing', hemostatic_gauze = 'hemostatic_gauze', chest_seal = 'chest_seal',
        splint = 'splint', burn_dressing = 'burn_dressing' },
}

function T.Cfg()
    local over = Config and Config.Medical and Config.Medical.Treatment
    if type(over) ~= 'table' then return T.Defaults end
    local out = {}
    for k, v in pairs(T.Defaults) do out[k] = v end
    for k, v in pairs(over) do out[k] = v end
    return out
end

-- Interventions kept with the patient's drugs (pf_med_patients.drugs: { mg, at }); the engine keeps
-- an entry while `duration` lasts. iv_line has no effect of its own: it is the access other actions
-- need. analgesic_oral is the painkiller pill and the IFAK's tablets.
T.ExtraDrugs = {
    iv_line = { duration = 3600 },
    analgesic_oral = { duration = 1800, analgesia = 1.5 },
}

--- Adds the extra drug definitions to the physiology defaults (kept when a config already has them).
function T.EnsureDrugs()
    local P = PFMed.Physiology
    if not P or not P.Defaults or not P.Defaults.Drugs then return false end
    for name, def in pairs(T.ExtraDrugs) do
        if P.Defaults.Drugs[name] == nil then P.Defaults.Drugs[name] = def end
    end
    return true
end
T.EnsureDrugs()

-- ── scope of practice ─────────────────────────────────────────────────────────────────────────

-- Highest tier first: the provider's tier is the first qualification they hold.
T.TierQuals = { { 5, 'physician' }, { 5, 'surgeon' }, { 4, 'nurse' }, { 3, 'paramedic' }, { 2, 'emt' }, { 1, 'emr' } }
T.TierLabels = { [0] = 'Anyone', 'EMR', 'EMT', 'Paramedic', 'Nurse', 'Physician' }

-- Used only when pf-government is not running (its Config.Departments.Implied is the source of truth).
T.ImpliedQuals = {
    ambulance = {
        [0] = { 'emr' },
        [1] = { 'emr', 'emt', 'paramedic' },
        [2] = { 'emr', 'emt', 'paramedic', 'nurse', 'physician' },
        [3] = { 'emr', 'emt', 'paramedic', 'nurse', 'physician', 'surgeon' },
        [4] = { 'emr', 'emt', 'paramedic', 'nurse', 'physician', 'surgeon' },
    },
}

-- ── regions ───────────────────────────────────────────────────────────────────────────────────

local function set(list) local s = {} for _, k in ipairs(list) do s[k] = true end return s end
T.Set = set

T.LimbRegions = set({ 'upper_arm_l', 'upper_arm_r', 'forearm_l', 'forearm_r', 'hand_l', 'hand_r', 'thigh_l', 'thigh_r',
    'knee_l', 'knee_r', 'lower_leg_l', 'lower_leg_r', 'foot_l', 'foot_r' })
T.SplintRegions = set({ 'shoulder_l', 'shoulder_r', 'upper_arm_l', 'upper_arm_r', 'forearm_l', 'forearm_r', 'hand_l', 'hand_r',
    'thigh_l', 'thigh_r', 'knee_l', 'knee_r', 'lower_leg_l', 'lower_leg_r', 'foot_l', 'foot_r' })
T.ChestRegions = set({ 'chest_l', 'chest_r', 'back_upper' })
T.ThighRegions = set({ 'thigh_l', 'thigh_r' })

local FIELD = { field = true, rig = true, hospital = true }
local RIG = { rig = true, hospital = true }
local HOSPITAL = { hospital = true }
local DOWN = set({ 'unconscious', 'arrest' })
local ALIVE = set({ 'alert', 'altered', 'unconscious', 'arrest' })
local AWAKE_OR_DOWN = ALIVE

-- ── the catalogue ─────────────────────────────────────────────────────────────────────────────

T.Actions = {
    -- bleeding control
    pressure_dressing = { label = 'Pressure dressing', tier = 0, self = true, location = FIELD, items = { pressure_dressing = 1 },
        alt = { { bandage = 1 } }, duration = 4000, target = 'wound', apply = 'bleed', key = 'pressure', healing = 5 },
    hemostatic_gauze = { label = 'Hemostatic gauze', tier = 1, self = true, location = FIELD, items = { hemostatic_gauze = 1 },
        duration = 6000, target = 'wound', apply = 'bleed', key = 'hemostatic', healing = 5 },
    tourniquet = { label = 'Tourniquet', tier = 0, self = true, location = FIELD, items = { tourniquet = 1 }, duration = 4000,
        target = 'wound', regions = T.LimbRegions, apply = 'tourniquet' },
    tourniquet_remove = { label = 'Remove tourniquet', tier = 3, location = FIELD, duration = 3000, target = 'region',
        regions = T.LimbRegions, apply = 'tourniquet_remove' },
    chest_seal = { label = 'Chest seal', tier = 1, self = true, location = FIELD, items = { chest_seal = 1 }, duration = 4000,
        target = 'wound', regions = T.ChestRegions, apply = 'chest_seal' },
    -- breathing and airway
    needle_decompression = { label = 'Needle decompression', tier = 3, location = FIELD, items = { decompression_needle = 1 },
        duration = 6000, target = 'patient', hidden = true, apply = 'decompress' },
    opa = { label = 'Oral airway (OPA)', tier = 1, location = FIELD, items = { opa = 1 }, duration = 3000, target = 'patient',
        states = DOWN, apply = 'airway', device = 'opa' },
    npa = { label = 'Nasal airway (NPA)', tier = 1, location = FIELD, items = { npa = 1 }, duration = 3000, target = 'patient',
        states = set({ 'altered', 'unconscious', 'arrest' }), apply = 'airway', device = 'npa' },
    bvm = { label = 'Bag-valve-mask ventilation', tier = 1, location = FIELD, equipment = { 'bvm' }, duration = 5000,
        target = 'patient', states = DOWN, apply = 'drug', drug = 'ventilation' },
    intubation = { label = 'Intubation', tier = 3, qual = 'paramedic', location = FIELD, items = { et_tube = 1 }, equipment = { 'bvm' },
        duration = 10000, target = 'patient', states = DOWN, apply = 'airway', device = 'et_tube', secure = true },
    oxygen = { label = 'Oxygen', tier = 1, location = FIELD, equipment = { 'oxygen_tank' }, duration = 4000, target = 'patient',
        states = AWAKE_OR_DOWN, apply = 'drug', drug = 'oxygen', healing = 5 },
    -- immobilisation
    c_collar = { label = 'Cervical collar', tier = 1, location = FIELD, items = { c_collar = 1 }, duration = 4000, target = 'patient',
        hidden = true, apply = 'collar' },
    backboard = { label = 'Backboard', tier = 1, location = FIELD, equipment = { 'backboard' }, duration = 6000, target = 'patient',
        hidden = true, apply = 'backboard' },
    splint = { label = 'Splint', tier = 1, self = true, location = FIELD, items = { splint = 1 }, duration = 6000, target = 'region',
        regions = T.SplintRegions, hidden = true, apply = 'splint', healing = 5 },
    traction_splint = { label = 'Traction splint', tier = 2, location = FIELD, items = { traction_splint = 1 }, duration = 8000,
        target = 'region', regions = T.ThighRegions, hidden = true, apply = 'splint', traction = true },
    pelvic_binder = { label = 'Pelvic binder', tier = 2, location = FIELD, items = { pelvic_binder = 1 }, duration = 6000,
        target = 'patient', hidden = true, apply = 'binder' },
    -- circulation and drugs
    iv_access = { label = 'IV access', tier = 3, location = FIELD, items = { iv_kit = 1 }, duration = 6000, target = 'patient',
        apply = 'iv' },
    fluids = { label = 'IV fluids (saline)', tier = 3, location = FIELD, items = { saline_bag = 1 }, duration = 5000,
        target = 'patient', needsIv = true, apply = 'volume', volume = { kind = 'saline', ml = 500 } },
    blood_onegative = { label = 'Blood transfusion (O-)', tier = 3, location = RIG, items = { blood_onegative = 1 }, duration = 8000,
        target = 'patient', needsIv = true, apply = 'volume', volume = { kind = 'blood', ml = 450 } },
    txa = { label = 'Tranexamic acid', tier = 3, location = FIELD, items = { txa = 1 }, duration = 3000, target = 'patient',
        needsIv = true, apply = 'drug', drug = 'txa', redose = 10800 },
    morphine = { label = 'Morphine 10 mg', tier = 3, location = FIELD, items = { morphine = 1 }, duration = 3000, target = 'patient',
        states = set({ 'alert', 'altered' }), needsIv = true, apply = 'drug', drug = 'morphine', opioid = 10, redose = 600 },
    fentanyl = { label = 'Fentanyl 100 mcg', tier = 3, location = FIELD, items = { fentanyl = 1 }, duration = 3000, target = 'patient',
        states = set({ 'alert', 'altered' }), needsIv = true, apply = 'drug', drug = 'fentanyl', opioid = 10, redose = 600 },
    naloxone = { label = 'Naloxone', tier = 0, location = FIELD, items = { naloxone = 1 }, duration = 3000, target = 'patient',
        states = set({ 'altered', 'unconscious', 'arrest' }), apply = 'drug', drug = 'naloxone', redose = 120 },
    epinephrine = { label = 'Epinephrine', tier = 3, location = FIELD, items = { epinephrine = 1 }, duration = 3000, target = 'patient',
        apply = 'drug', drug = 'epinephrine', redose = 180 },
    cpr = { label = 'CPR', tier = 0, location = FIELD, duration = 5000, target = 'patient', states = set({ 'arrest' }), apply = 'cpr' },
    defibrillate = { label = 'Defibrillate (AED)', tier = 0, location = FIELD, equipment = { 'aed' }, duration = 4000,
        target = 'patient', states = set({ 'arrest' }), apply = 'defib' },
    first_aid_revive = { label = 'Revive', tier = 0, location = FIELD, items = { firstaid = 1 }, duration = 8000, target = 'patient',
        states = set({ 'unconscious' }), apply = 'revive' },
    -- wounds, burns, bones
    burn_dressing = { label = 'Burn dressing', tier = 1, self = true, location = FIELD, items = { burn_dressing = 1 }, duration = 5000,
        target = 'region', hidden = false, apply = 'burn', healing = 5 },
    cooling = { label = 'Cool with water', tier = 0, self = true, location = FIELD, items = { water_bottle = 1 }, duration = 5000,
        target = 'patient', apply = 'cooling' },
    basic_wound_care = { label = 'Clean and dress wound', tier = 1, location = FIELD, items = { bandage = 1 },
        alt = { { pressure_dressing = 1 } }, duration = 5000, target = 'wound', apply = 'wound_care', healing = 10 },
    sutures = { label = 'Sutures', tier = 4, location = HOSPITAL, items = { suture_kit = 1 }, duration = 10000, target = 'wound',
        apply = 'sutures', healing = 10 },
    reduction = { label = 'Reduce dislocation / fracture', tier = 3, location = FIELD, duration = 8000, target = 'region',
        regions = T.SplintRegions, apply = 'reduction' },
    cast = { label = 'Cast', tier = 4, location = HOSPITAL, items = { cast_kit = 1 }, duration = 12000, target = 'region',
        regions = T.SplintRegions, apply = 'cast' },
    antibiotics = { label = 'Antibiotics', tier = 4, location = RIG, items = { antibiotics = 1 }, duration = 3000, target = 'patient',
        apply = 'antibiotics' },
}
for name, a in pairs(T.Actions) do
    a.name = name
    a.states = a.states or ALIVE
end

-- Legacy treatment keys (pf-ambulancejob:server:applyTreatment from the EMS MDT panel, /treat).
T.LegacyKeys = { bandage = 'pressure_dressing', splint = 'splint', burn_dressing = 'burn_dressing', oxygen = 'oxygen' }
-- The item each legacy key used before batch 17, still accepted through that key only (the EMS MDT
-- 'Apply Splint' used a first-aid kit, 'Burn Dressing' an IFAK; the bandage is already an alternative).
T.LegacyItems = { splint = { firstaid = 1 }, burn_dressing = { ifaks = 1 } }

-- Self-care items used from the inventory: the action they perform on the user.
T.SelfUse = {
    bandage = { action = 'pressure_dressing', items = { bandage = 1 } },
    ifaks = { action = 'ifak', items = { ifaks = 1 } },
    painkillers = { action = 'painkiller', items = { painkillers = 1 } },
    tourniquet = { action = 'tourniquet' },
    pressure_dressing = { action = 'pressure_dressing' },
    hemostatic_gauze = { action = 'hemostatic_gauze' },
    chest_seal = { action = 'chest_seal' },
    splint = { action = 'splint' },
    burn_dressing = { action = 'burn_dressing' },
}
-- Self-only actions behind the civilian items.
T.Actions.ifak = { name = 'ifak', label = 'Individual first aid kit', tier = 0, self = true, selfOnly = true, location = FIELD,
    items = { ifaks = 1 }, duration = 6000, target = 'wound', states = set({ 'alert', 'altered' }), apply = 'ifak', healing = 10 }
T.Actions.painkiller = { name = 'painkiller', label = 'Painkillers', tier = 0, self = true, selfOnly = true, location = FIELD,
    items = { painkillers = 1 }, duration = 3000, target = 'patient', states = set({ 'alert', 'altered' }), apply = 'drug',
    drug = 'analgesic_oral', redose = 1800 }

--- The action definition by name (nil when unknown).
function T.Get(name)
    if type(name) ~= 'string' or #name > 32 then return nil end
    return T.Actions[name]
end

--- Every item a treatment can use up or needs as equipment (for pfm-core shared items and specs).
function T.ItemNames()
    local out = {}
    for _, a in pairs(T.Actions) do
        for name in pairs(a.items or {}) do out[name] = true end
        for _, alt in ipairs(a.alt or {}) do for name in pairs(alt) do out[name] = true end end
        for _, name in ipairs(a.equipment or {}) do out[name] = true end
    end
    return out
end

--- Actions a provider of `tier` may perform, sorted by label (client menus; the server re-checks).
function T.ListFor(tier, selfOnly)
    local out = {}
    for name, a in pairs(T.Actions) do
        if (a.tier or 0) <= (tier or 0) and (not selfOnly or a.self) and (selfOnly or not a.selfOnly) then out[#out + 1] = name end
    end
    table.sort(out, function(x, y) return T.Actions[x].label < T.Actions[y].label end)
    return out
end
