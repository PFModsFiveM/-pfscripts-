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
    RespawnAfterSeconds = 300,
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
