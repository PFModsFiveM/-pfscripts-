-- Medical engine settings (server/medical/*, shared/medical/*). The anatomy, injury catalogue and
-- model constants live in shared/medical/*.lua; the blocks below override them where noted.
Config = Config or {}
Config.Medical = Config.Medical or {}
local M = Config.Medical

M.TickSeconds = 5             -- engine pass over active patients (bleeding, down, toxins, drugs)
M.MaxTickGap = 60             -- a longer gap between two ticks (server hitch) is clamped to this
M.WriteBehindSeconds = 10     -- dirty patients are written in one statement this often
M.SweepHours = 24             -- retention sweep interval
M.SweepBatch = 500            -- rows per sweep statement
M.MaxOpenInjuries = 40        -- open injuries per citizen; more are merged into a matching one
M.HistoryDays = 60            -- recovered injuries older than this are deleted
M.EventRetentionDays = 180    -- pf_med_events rows older than this are deleted
M.Offline = {
    MaxBleedSeconds = 120,    -- at load, offline time bleeds for at most this long (a crash should
                              -- not kill; logging out should not stop a wound either)
}
M.AdminAce = 'admin'          -- ACE an opts.actor = { kind = 'admin', src } must hold
M.AdminAces = { 'admin', 'command' } -- Revive/Kill with opts.by: any of these (pfm-adminmenu's own admin check)

-- Overrides for the physiology model (shared/medical/physiology_model.lua P.Defaults). Leave a block
-- empty to keep the model's values. Toxin amounts passed to AddToxin are in each toxin's unit:
--   ethanol: BAC (%), opioid/stimulant/sedative/cannabis: mg, poison/food_poisoning: units,
--   carbon_monoxide: COHb %. `max` caps the level, `severe` is intensity 1.0.
M.Physiology = M.Physiology or {}
M.Consciousness = M.Consciousness or {
    RecoverSeconds = 10,
    HypoxiaSpo2 = 60, HypoxiaSeconds = 30,
    ArrestSbp = 50, ArrestLossFraction = 0.5,
    ArrestToDeathSeconds = 300,
    CprWindowSeconds = 10,
    -- dead -> hospital respawn allowed after this long (the legacy Config.DeathTime)
    RespawnAfterSeconds = tonumber(Config.DeathTime) or 300,
}
M.Toxins = M.Toxins or {}
M.Drugs = M.Drugs or {}

-- Consumables (pfm-smallresources:server:consumed): ethanol per alcoholic item (BAC added per drink)
-- and the food-poisoning dose of a dish the server marked as poisoned.
M.Consumables = {
    Alcohol = { beer = 0.02, whiskey = 0.04, vodka = 0.04 },
    AlcoholDefault = 0.03,
    FoodPoisoningDose = 0.6,
}

-- Resources allowed to call each export (architecture 3.4). '*' = open. The resource itself (no
-- invoker) always passes. Unknown invokers get { ok = false, error = 'not_allowed' }.
M.Callers = {
    GetPatientSummary = { ['pf-emsmdt'] = true, ['pf-justice'] = true, ['pfm-prison'] = true, ['pf-policemdt-DEV'] = true },
    IsDown = '*',
    ApplyInjury = { ['pfm-prison'] = true, ['pfm-adminmenu'] = true, ['pf-jobs'] = true },
    AddToxin = { ['pfm-drugs'] = true, ['pf-restaurants'] = true, ['pfm-adminmenu'] = true },
    -- batch 16A: admin / script revive and admin kill (medical revives go through EMS, never these)
    Revive = { ['pfm-adminmenu'] = true },
    Kill = { ['pfm-adminmenu'] = true },
    -- batch 17 (architecture 4.1, 4.5): 17A medical record, 17C restrictions, 17E hospital exports
    GetMedicalRecord = { ['pf-emsmdt'] = true, ['pf-justice'] = true, ['pf-policemdt-DEV'] = true },
    GetRestrictions = '*',
    IsInCare = '*',
    GetAdmission = { ['pf-emsmdt'] = true, ['pf-justice'] = true, ['pfm-prison'] = true },
    ListAdmissions = { ['pf-emsmdt'] = true },
    AdmitPatient = { ['pf-justice'] = true, ['pfm-prison'] = true },
    DischargePatient = { ['pf-justice'] = true, ['pf-emsmdt'] = true },
    GetHospitalStatus = { ['pf-emsmdt'] = true, ['pf-justice'] = true },
}

-- Which summary fields each caller receives ('all', or a list). Callers not listed get the
-- non-medical set. ok, cid and online are always included.
M.NonMedicalSummaryFields = { 'down', 'consciousness', 'stage', 'restrictions' }
M.SummaryFields = {
    ['pf-emsmdt'] = 'all',
    -- booking screening (architecture 4.7.4) refuses a red or orange triage, so the court system
    -- also receives the triage colour (set by the hospital module, batch 17)
    ['pf-justice'] = { 'down', 'consciousness', 'stage', 'restrictions', 'triage' },
    ['pfm-prison'] = M.NonMedicalSummaryFields,
    ['pf-policemdt-DEV'] = M.NonMedicalSummaryFields,
}

-- Server-owned down state (server/medical/downstate.lua, batch 16A). The server decides who is down
-- (an accepted ReportDown, or the engine's consciousness); clients only ask. Times in seconds.
M.Down = {
    DownHealth = tonumber(Config.DownHealth) or 150, -- a ReportDown needs the server-read ped health at or below this
    DeadHealth = 100,           -- a 'dead' report from a patient already down needs health at or below this
    HoldHealth = 150,           -- health the client keeps its ped at while down (the legacy last-stand health)
    ReportChecks = 6,           -- the server looks at the ped up to this many times for a report ...
    ReportCheckMs = 500,        -- ... this far apart (state sync lags behind the event)
    -- the legacy last stand: an unconscious patient nobody revived dies after this long
    LaststandSeconds = tonumber(Config.ReviveInterval) or 360,
    LaststandEndsInDeath = true, -- false: the patient stays unconscious until the engine wakes them
    ReportHoldSeconds = tonumber(Config.ReviveInterval) or 360, -- a reported down does not wake up earlier
    -- civilian first aid (a firstaid kit) only on an unconscious patient down at least this long
    -- (the legacy Config.MinimumRevive window), and it takes FirstAidSeconds on the helper's side
    FirstAidAfterSeconds = math.max(0, (tonumber(Config.ReviveInterval) or 360) - (tonumber(Config.MinimumRevive) or 300)),
    FirstAidSeconds = { 30, 60 },
    ReviveItem = 'firstaid',    -- consumed on the server by an EMS revive and by civilian first aid (false: none for EMS)
    ReviveDistance = 2.5,       -- touch distance (architecture 6.4)
    EmsReviveDead = true,       -- on-duty EMS may still revive a dead patient (legacy); 17B moves this to treatments
    -- what a revive does to the patient record until the 17B treatment engine replaces it:
    --   'full'      injuries healed, blood/airway/toxins back to normal (hospital, admin)
    --   'stabilize' bleeding stopped, blood topped up to ReviveBloodFraction, airway cleared (EMS)
    --   'first_aid' bleeding stopped, airway cleared (civilian first aid)
    EmsReviveReset = 'stabilize',
    ReviveBloodFraction = 0.8,
    ReviveHealth = 200,         -- health the client sets on a revive (the server re-reads it)
    ReviveTokenSeconds = 20,    -- a revive token is valid this long (plus the AI heal time for hospital beds)
    ReviveVerifyMs = 1500,      -- the server re-reads the ped health this long after ReviveApplied
    ReviveResetsNeeds = { admin = true, script = true, respawn = true, checkin = true, ems = true, first_aid = true },
    StatusDistance = 5.0,       -- hospital:GetPlayerStatus: on-duty EMS within this of the patient
    StashDistance = 3.0,        -- the EMS stash: job + duty + within this of a stash point
    ReceptionDistance = 4.0,    -- hospital check-in: within this of the hospital's reception point
    BedDistance = 3.0,          -- lying in a bed: within this of the bed
    EscortSpeed = 3.0,          -- m/s: a down player moving faster, not attached and not in a vehicle, is an anomaly
    AnomalyLogSeconds = 30,     -- at most one anomaly row per player this often
    ResendSeconds = 5,          -- the down state is sent again to a moving down player at most this often
    ArmourSaveSeconds = 60,     -- server-read armour saved to metadata this often (and on leave)
    AlertSeconds = 30,          -- hospital:server:ambulanceAlert: one per player this often
    HelpSeconds = 60,           -- RequestHelp: one per player this often
}

-- Recovery stages, restrictions and functional effects (server/medical/recovery.lua, effects.lua,
-- client/effects.lua; batch 17C, architecture 5.2, 11.4, 11.8). Times in seconds.
M.Recovery = {
    LoopSeconds = 60,              -- stage machine pass over online patients that are not healthy
    SyncSeconds = 5,               -- effect profiles of changed or ticking online patients are re-checked this often
    SampleSeconds = 1,             -- no_drive / exertion sampler; it visits only watched patients
    ControlledBleedMlPerMin = 1.0, -- a wound bleeding less than this (after treatment) counts as controlled
    HealMultiplier = 1.0,          -- on the catalogue's healSeconds (shared/medical/injuries.lua)
    -- minor injuries heal without care once stable: the highest severity per type that does, and how
    -- much slower than with care
    SelfHeal = { bruising = 3, sprain = 1, laceration = 1, burn = 1, electrical = 1, head_trauma = 1,
        respiratory = 2, drowning = 2, poisoning = 3, illness = 2 },
    SelfHealMultiplier = 1.5,
    -- types that stay 'injured' until one of their stabilizeBy treatments was done (a broken leg is
    -- not stable just because it does not bleed)
    NeedsStabilizer = { fracture = true, dislocation = true, spinal = true, infection = true, internal_bleeding = true,
        organ_trauma = true },
    -- treatment action -> the flag the engine model reads (shared/medical/injuries.lua and
    -- physiology_model.lua); either name on injury.treatments counts. Any surgery_* sets 'surgery'.
    TreatmentFlags = { splint = 'splinted', traction_splint = 'splinted', pelvic_binder = 'binder', pressure_dressing = 'pressure',
        hemostatic_gauze = 'hemostatic', needle_decompression = 'decompressed', cast = 'cast' },
    Infection = {
        AfterSeconds = 7200,       -- an open wound with no wound care this old becomes infected (offline time counts)
        MinSeverity = 2,           -- smaller wounds do not
        WorsenSeconds = 3600,      -- an untreated infection gets one severity worse this often ...
        MaxSeverity = 3,           -- ... up to this
        CareFlags = { 'basic_wound_care', 'sutures', 'antibiotics', 'burn_dressing', 'surgery' },
    },
    ReBleed = {                    -- exertion while a wound is only held by a dressing (architecture 5.2)
        Chance = 0.1,              -- per exertion episode
        ExertionSpeed = 5.5,       -- m/s on foot (sprinting), server-read
        ExertionSamples = 3,       -- consecutive sampler hits that make one episode
        CooldownSeconds = 120,     -- at most one roll per patient this often
        Fraction = 0.5,            -- the wound bleeds again at this share of its first bleed
    },
    ViolationLogSeconds = 60,      -- one no_drive anomaly row per patient this often
    MaxOpenRestrictions = 30,      -- open restriction rows per citizen (AddRestriction refuses more)
    -- restrictions a wound sets when it enters 'recovering'; they end with the wound (until = recover_at).
    -- groups: anatomy group kind (leg, arm, pelvis, torso, neck, head); '<side>' becomes l or r.
    InjuryRestrictions = {
        { types = { fracture = true, dislocation = true }, groups = { leg = true, pelvis = true }, kinds = { 'crutches' }, reason = 'Leg injury' },
        { types = { fracture = true, dislocation = true }, groups = { arm = true }, kinds = { 'cast_arm_<side>' }, reason = 'Arm injury' },
        { types = { head_trauma = true }, kinds = { 'concussion', 'no_drive' }, reason = 'Head injury' },
        { types = { spinal = true }, kinds = { 'no_heavy_work', 'no_drive' }, reason = 'Spinal injury' },
        { types = { gunshot = true, stab = true, internal_bleeding = true, organ_trauma = true, crush = true, burn = true },
            minSeverity = 3, kinds = { 'no_heavy_work' }, reason = 'Serious injury' },
    },
    -- the least each restriction leaves on the effect profile (after painkillers, so a cast keeps
    -- its effect). 'crutches' is a model modifier (walk 2, no sprint), not a floor.
    RestrictionEffects = {
        no_drive = { drive = 2 },
        no_sprint = { sprint = 2 },
        concussion = { drive = 2 },
        cast_arm_l = { aim = 1, reload = 2, climb = 2 },
        cast_arm_r = { aim = 1, reload = 2, climb = 2 },
    },
}
