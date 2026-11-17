-- Exam catalogue (architecture 4.2 / 11.6): the exam modalities with what each needs (minimum
-- provider tier, instruments, rig or hospital, imaging room, time, distance) and, per injury type,
-- the signs each modality can find with a sensitivity per provider tier.
--
-- Rules every entry follows:
--   * a sign is only ever produced from a real injury or the real physiology (no false findings);
--   * a miss produces nothing: an exam that finds nothing says "nothing found", never "normal";
--   * internal bleeding has no sign outside fast_us and ct (only indirect vitals: pulse, pressure);
--   * only xray, ct and labs give 'confirmed' findings (and confirmed diagnoses).
-- Pure data plus small helpers; shared so the client builds its menus from the same table. The
-- server decides everything again (server/medical/exam.lua, diagnosis.lua).

PFMed = PFMed or {}
PFMed.Findings = PFMed.Findings or {}
local F = PFMed.Findings

-- Provider tiers (11.6). A tier comes from the highest medical qualification the provider holds
-- (pf-government HasQualification: granted, or implied by grade) while on duty in a medical job.
F.Tiers = {
    [0] = { label = 'Bystander' },
    [1] = { label = 'EMR', qual = 'emr' },
    [2] = { label = 'EMT', qual = 'emt' },
    [3] = { label = 'Paramedic', qual = 'paramedic' },
    [4] = { label = 'Nurse', qual = 'nurse' },
    [5] = { label = 'Physician', qual = 'physician' },
}
-- Checked from the highest tier down; the first held qualification decides.
F.TierQuals = { { 5, 'surgeon' }, { 5, 'physician' }, { 4, 'nurse' }, { 3, 'paramedic' }, { 2, 'emt' }, { 1, 'emr' } }
-- Used only when pf-government is not running: tier by ambulance grade (matches its Implied table).
F.GradeTier = { [0] = 1, [1] = 3, [2] = 5, [3] = 5, [4] = 5 }

-- Sensitivity per tier 0..5 (probability that a present sign is found). 0 = cannot find it.
local function S(t0, t1, t2, t3, t4, t5) return { [0] = t0, [1] = t1, [2] = t2, [3] = t3, [4] = t4, [5] = t5 } end
F.S = S

local INSTRUMENT = { rig = true, hospital = true }
-- Modalities. order = menu order. items: any one of them held is enough; rig = an ambulance within
-- RigDistance of the provider counts as the instrument; hospital = a patient inside a hospital has
-- the hospital's instruments; requireRigOrHospital: no handheld version. location 'imaging' needs
-- the patient in a bed inside an imaging zone, 'hospital' needs the patient inside a hospital.
-- seconds = how long the exam takes (the server waits it out); distance = provider to patient.
F.Modalities = {
    look        = { order = 1,  label = 'Look (inspect)', tier = 0, seconds = 3, distance = 2.5 },
    pain_scale  = { order = 2,  label = 'Ask about pain', tier = 0, seconds = 2, distance = 2.5, vital = true },
    pulse       = { order = 3,  label = 'Check pulse', tier = 1, seconds = 4, distance = 2.5, vital = true },
    palpate     = { order = 4,  label = 'Palpate', tier = 1, seconds = 6, distance = 2.5 },
    bp_cuff     = { order = 5,  label = 'Blood pressure', tier = 2, seconds = 6, distance = 2.5, vital = true, items = { 'bp_cuff' }, equip = INSTRUMENT },
    spo2_probe  = { order = 6,  label = 'Pulse oximetry', tier = 2, seconds = 4, distance = 2.5, vital = true, items = { 'pulse_oximeter' }, equip = INSTRUMENT },
    pupils      = { order = 7,  label = 'Pupils', tier = 2, seconds = 3, distance = 2.5, items = { 'penlight' }, equip = INSTRUMENT },
    glucose     = { order = 8,  label = 'Blood glucose', tier = 2, seconds = 5, distance = 2.5, vital = true, items = { 'glucometer' }, equip = INSTRUMENT },
    temperature = { order = 9,  label = 'Temperature', tier = 2, seconds = 4, distance = 2.5, vital = true, items = { 'thermometer' }, equip = INSTRUMENT },
    auscultate  = { order = 10, label = 'Auscultate', tier = 3, seconds = 6, distance = 2.5, items = { 'stethoscope' }, equip = INSTRUMENT },
    ecg         = { order = 11, label = 'ECG (monitor)', tier = 3, seconds = 8, distance = 2.5, vital = true, items = { 'aed' }, equip = INSTRUMENT },
    fast_us     = { order = 12, label = 'FAST ultrasound', tier = 3, seconds = 12, distance = 2.5, equip = INSTRUMENT, requireRigOrHospital = true },
    labs        = { order = 13, label = 'Lab panel', tier = 4, seconds = 30, distance = 2.5, location = 'hospital', source = 'lab' },
    xray        = { order = 14, label = 'X-ray', tier = 5, seconds = 20, distance = 10.0, location = 'imaging', source = 'imaging' },
    ct          = { order = 15, label = 'CT scan', tier = 5, seconds = 30, distance = 10.0, location = 'imaging', source = 'imaging' },
}
F.Aliases = { ask = 'pain_scale' }
F.RigDistance = 10.0        -- an ambulance this close to the provider carries the instruments
F.HospitalRadius = 60.0     -- a patient this close to a hospital's location is inside it
F.CacheSeconds = 60         -- the same exam (patient, modality, tier) within this returns the stored result
F.MaxFindings = 40          -- findings one exam can return
F.RigModels = { 'ambulance' } -- plus every model in Config.AuthorizedVehicles

-- Imaging rooms (x-ray / CT). The patient must lie in a server-held bed inside one. 17E's
-- Config.Hospital.ImagingZones replaces this list when it exists. Check the coordinates in game
-- against the hospital interior in use.
F.ImagingZones = {
    { id = 'pillbox_imaging', hospital = 'pillbox', coords = vector3(326.98, -576.17, 43.02), radius = 4.0 },
}

-- Signs per injury type. Each rule: modality = { sign, certainty, sens, subtypes?, structures?,
-- kinds?, minSeverity?, visibleOnly?, revealStructure? }. A list of rules per modality is allowed.
--   subtypes / structures / kinds: the rule applies only to those (by injury subtype, structure id
--   or anatomy kind); visibleOnly: only when the injury can be seen (injuries.lua I.Visible);
--   revealStructure: the finding names the structure (imaging), otherwise only the region.
local LOOK_HIGH = S(0.8, 0.85, 0.9, 0.92, 0.95, 0.97)
local LOOK_MID = S(0.5, 0.6, 0.7, 0.8, 0.85, 0.9)
local PALP = S(0, 0.55, 0.65, 0.75, 0.8, 0.85)
local AUSC = S(0, 0, 0, 0.75, 0.8, 0.9)
local FAST = S(0, 0, 0, 0.75, 0.8, 0.9)
local XRAY = S(0, 0, 0, 0, 0, 0.92)
local CT = S(0, 0, 0, 0, 0, 0.98)
local LABS = S(0, 0, 0, 0, 0.95, 0.97)
local PUPIL = S(0, 0, 0.7, 0.8, 0.85, 0.9)
local LUNG = { lung_l = true, lung_r = true }
local AXIAL = { skull = true, face_jaw = true, spine_cervical = true, spine_thoracic = true, spine_lumbar = true, pelvis = true, sternum = true }

F.Signs = {
    fracture = {
        look = { sign = 'deformity', certainty = 'observed', sens = LOOK_HIGH, visibleOnly = true },
        palpate = { sign = 'bony_tenderness', certainty = 'suspected', sens = PALP },
        xray = { sign = 'fracture_line', certainty = 'confirmed', sens = XRAY, revealStructure = true },
        ct = { sign = 'fracture_line', certainty = 'confirmed', sens = CT, revealStructure = true, structures = AXIAL },
    },
    dislocation = {
        look = { sign = 'joint_deformity', certainty = 'observed', sens = LOOK_HIGH },
        palpate = { sign = 'joint_instability', certainty = 'suspected', sens = PALP },
        xray = { sign = 'dislocated_joint', certainty = 'confirmed', sens = XRAY, revealStructure = true },
    },
    sprain = {
        look = { sign = 'swelling', certainty = 'observed', sens = LOOK_MID, minSeverity = 2 },
        palpate = { sign = 'joint_tenderness', certainty = 'suspected', sens = PALP },
    },
    bruising = {
        look = { sign = 'bruise', certainty = 'observed', sens = LOOK_HIGH },
        palpate = { sign = 'tenderness', certainty = 'observed', sens = PALP },
    },
    laceration = {
        look = {
            { sign = 'open_wound', certainty = 'observed', sens = S(0.95, 0.97, 0.98, 0.98, 0.99, 0.99) },
            { sign = 'spurting_bleeding', certainty = 'observed', sens = S(0.9, 0.95, 0.97, 0.98, 0.98, 0.99), subtypes = { arterial = true } },
        },
    },
    gunshot = {
        look = {
            { sign = 'entry_wound', certainty = 'observed', sens = S(0.9, 0.93, 0.95, 0.97, 0.98, 0.99) },
            { sign = 'exit_wound', certainty = 'observed', sens = S(0.7, 0.8, 0.85, 0.9, 0.92, 0.95), subtypes = { perforating = true } },
        },
        auscultate = { sign = 'decreased_breath_sounds', certainty = 'suspected', sens = AUSC, structures = LUNG },
        fast_us = { sign = 'free_fluid', certainty = 'suspected', sens = FAST, kinds = { organ = true, vessel = true } },
        xray = {
            { sign = 'retained_projectile', certainty = 'confirmed', sens = XRAY, subtypes = { retained = true }, revealStructure = true },
            { sign = 'pneumothorax', certainty = 'confirmed', sens = XRAY, structures = LUNG, revealStructure = true },
        },
        ct = { sign = 'organ_injury', certainty = 'confirmed', sens = CT, kinds = { organ = true, vessel = true }, revealStructure = true },
    },
    stab = {
        look = { sign = 'stab_wound', certainty = 'observed', sens = S(0.9, 0.93, 0.95, 0.97, 0.98, 0.99) },
        auscultate = { sign = 'decreased_breath_sounds', certainty = 'suspected', sens = AUSC, structures = LUNG },
        fast_us = { sign = 'free_fluid', certainty = 'suspected', sens = FAST, kinds = { organ = true, vessel = true } },
        ct = { sign = 'organ_injury', certainty = 'confirmed', sens = CT, kinds = { organ = true, vessel = true }, revealStructure = true },
    },
    burn = {
        look = { sign = 'burn', certainty = 'observed', sens = S(0.95, 0.97, 0.98, 0.99, 0.99, 0.99), valueFromSubtype = true },
    },
    crush = {
        look = { sign = 'swelling', certainty = 'observed', sens = LOOK_HIGH },
        palpate = { sign = 'tense_compartment', certainty = 'suspected', sens = PALP, minSeverity = 3 },
    },
    electrical = {
        look = { sign = 'entry_exit_marks', certainty = 'observed', sens = LOOK_MID },
    },
    head_trauma = {
        look = { sign = 'scalp_deformity', certainty = 'observed', sens = LOOK_MID, visibleOnly = true },
        pupils = {
            { sign = 'unequal_pupils', certainty = 'suspected', sens = PUPIL, subtypes = { epidural = true, subdural = true, skull_fracture = true, diffuse = true }, minSeverity = 3 },
            { sign = 'sluggish_pupils', certainty = 'suspected', sens = PUPIL, subtypes = { concussion = true }, minSeverity = 2 },
        },
        ct = {
            { sign = 'intracranial_bleed', certainty = 'confirmed', sens = CT, subtypes = { epidural = true, subdural = true, diffuse = true }, revealStructure = true },
            { sign = 'skull_fracture', certainty = 'confirmed', sens = CT, subtypes = { skull_fracture = true }, revealStructure = true },
        },
    },
    spinal = {
        palpate = { sign = 'spinal_tenderness', certainty = 'suspected', sens = PALP },
        look = { sign = 'limb_weakness', certainty = 'observed', sens = S(0, 0.6, 0.7, 0.8, 0.85, 0.9), cordOnly = true },
        xray = { sign = 'vertebral_fracture', certainty = 'confirmed', sens = S(0, 0, 0, 0, 0, 0.7), revealStructure = true },
        ct = { sign = 'vertebral_fracture', certainty = 'confirmed', sens = CT, revealStructure = true },
    },
    -- hidden: nothing but FAST and CT finds it (pulse and pressure still show what it does)
    internal_bleeding = {
        fast_us = { sign = 'free_fluid', certainty = 'suspected', sens = FAST },
        ct = { sign = 'organ_laceration', certainty = 'confirmed', sens = CT, revealStructure = true },
    },
    organ_trauma = {
        auscultate = {
            { sign = 'absent_breath_sounds', certainty = 'suspected', sens = AUSC, subtypes = { pneumothorax = true, tension = true, hemothorax = true } },
            { sign = 'muffled_heart_sounds', certainty = 'suspected', sens = S(0, 0, 0, 0.5, 0.6, 0.7), subtypes = { tamponade = true } },
        },
        look = { sign = 'tracheal_deviation', certainty = 'suspected', sens = S(0, 0, 0, 0.6, 0.7, 0.8), subtypes = { tension = true }, minSeverity = 2 },
        palpate = { sign = 'abdominal_guarding', certainty = 'suspected', sens = PALP, subtypes = { bowel = true } },
        fast_us = {
            { sign = 'absent_lung_sliding', certainty = 'suspected', sens = FAST, subtypes = { pneumothorax = true, tension = true } },
            { sign = 'free_fluid', certainty = 'suspected', sens = FAST, subtypes = { hemothorax = true } },
            { sign = 'pericardial_fluid', certainty = 'suspected', sens = S(0, 0, 0, 0.85, 0.9, 0.95), subtypes = { tamponade = true } },
        },
        xray = { sign = 'collapsed_lung', certainty = 'confirmed', sens = XRAY, subtypes = { pneumothorax = true, tension = true, hemothorax = true }, revealStructure = true },
        ct = { sign = 'organ_injury', certainty = 'confirmed', sens = CT, revealStructure = true },
    },
    respiratory = {
        look = {
            { sign = 'cyanosis', certainty = 'observed', sens = LOOK_MID, minSeverity = 3 },
            { sign = 'soot_in_airway', certainty = 'observed', sens = LOOK_HIGH, subtypes = { smoke_inhalation = true } },
        },
        auscultate = {
            { sign = 'stridor', certainty = 'suspected', sens = AUSC, subtypes = { airway_obstruction = true, smoke_inhalation = true } },
            { sign = 'crackles', certainty = 'suspected', sens = AUSC, subtypes = { aspiration = true } },
        },
        xray = { sign = 'lung_infiltrate', certainty = 'confirmed', sens = XRAY, subtypes = { aspiration = true, smoke_inhalation = true } },
    },
    drowning = {
        look = { sign = 'cyanosis', certainty = 'observed', sens = LOOK_MID, minSeverity = 3 },
        auscultate = { sign = 'crackles', certainty = 'suspected', sens = AUSC },
        xray = { sign = 'pulmonary_edema', certainty = 'confirmed', sens = XRAY, minSeverity = 2 },
    },
    poisoning = {
        pupils = {
            { sign = 'pinpoint_pupils', certainty = 'suspected', sens = PUPIL, subtypes = { opioid = true } },
            { sign = 'dilated_pupils', certainty = 'suspected', sens = PUPIL, subtypes = { stimulant = true } },
        },
        labs = { sign = 'tox_screen', certainty = 'confirmed', sens = LABS, valueFromSubtype = true },
    },
    illness = {
        labs = {
            { sign = 'infection_markers', certainty = 'confirmed', sens = LABS, subtypes = { infection_sepsis = true } },
            { sign = 'gi_pathogen', certainty = 'confirmed', sens = LABS, subtypes = { food_poisoning = true } },
        },
    },
    infection = {
        look = { sign = 'redness_pus', certainty = 'observed', sens = LOOK_MID, subtypes = { wound_infection = true } },
        labs = { sign = 'infection_markers', certainty = 'confirmed', sens = LABS },
    },
}

-- Toxins the patient carries (physiology state, not an injury row) that a modality can show:
-- toxin = { modality = { sign, threshold (intensity 0..1) } }.
F.ToxinSigns = {
    opioid = { pupils = { sign = 'pinpoint_pupils', threshold = 0.25 } },
    stimulant = { pupils = { sign = 'dilated_pupils', threshold = 0.25 } },
}
F.ToxinLabThreshold = 0.05  -- a lab panel lists every toxin at or above this intensity

-- Labels for the menus (the client shows these; unknown signs show their id).
F.SignLabels = {
    deformity = 'Deformity', bony_tenderness = 'Bony tenderness', fracture_line = 'Fracture', joint_deformity = 'Joint deformity',
    joint_instability = 'Joint instability', dislocated_joint = 'Dislocated joint', swelling = 'Swelling', joint_tenderness = 'Joint tenderness',
    bruise = 'Bruise', tenderness = 'Tenderness', open_wound = 'Open wound', spurting_bleeding = 'Spurting bleeding',
    entry_wound = 'Entry wound', exit_wound = 'Exit wound', decreased_breath_sounds = 'Decreased breath sounds', free_fluid = 'Free fluid',
    retained_projectile = 'Retained projectile', pneumothorax = 'Pneumothorax', organ_injury = 'Organ injury', stab_wound = 'Stab wound',
    burn = 'Burn', tense_compartment = 'Tense compartment', entry_exit_marks = 'Entry/exit marks', scalp_deformity = 'Scalp deformity',
    unequal_pupils = 'Unequal pupils', sluggish_pupils = 'Sluggish pupils', intracranial_bleed = 'Intracranial bleed',
    skull_fracture = 'Skull fracture', spinal_tenderness = 'Spinal tenderness', limb_weakness = 'Limb weakness',
    vertebral_fracture = 'Vertebral fracture', organ_laceration = 'Organ laceration', absent_breath_sounds = 'Absent breath sounds',
    muffled_heart_sounds = 'Muffled heart sounds', tracheal_deviation = 'Tracheal deviation', abdominal_guarding = 'Abdominal guarding',
    absent_lung_sliding = 'No lung sliding', pericardial_fluid = 'Pericardial fluid', collapsed_lung = 'Collapsed lung',
    cyanosis = 'Cyanosis', soot_in_airway = 'Soot in the airway', stridor = 'Stridor', crackles = 'Crackles',
    lung_infiltrate = 'Lung infiltrate', pulmonary_edema = 'Pulmonary edema', pinpoint_pupils = 'Pinpoint pupils',
    dilated_pupils = 'Dilated pupils', tox_screen = 'Tox screen positive', infection_markers = 'Infection markers raised',
    gi_pathogen = 'GI pathogen', redness_pus = 'Redness and pus', hemoglobin = 'Hemoglobin',
    -- general observations and measurements
    responsiveness = 'Responsiveness', not_breathing = 'Not breathing', external_bleeding = 'External bleeding',
    pulse = 'Pulse', blood_pressure = 'Blood pressure', spo2 = 'SpO2', temperature = 'Temperature', glucose = 'Glucose',
    pain_score = 'Pain score', unresponsive = 'Unresponsive', rhythm = 'Rhythm', respiratory_rate = 'Respiratory rate',
}

--- Canonical modality id (aliases resolved) or nil.
function F.Modality(id)
    if type(id) ~= 'string' then return nil end
    id = F.Aliases[id] or id
    if F.Modalities[id] then return id end
    return nil
end

--- Modality ids in menu order.
function F.Ordered()
    local list = {}
    for id in pairs(F.Modalities) do list[#list + 1] = id end
    table.sort(list, function(a, b) return F.Modalities[a].order < F.Modalities[b].order end)
    return list
end

--- Sensitivity of a rule for a tier (0 when the tier cannot find it).
function F.Sensitivity(rule, tier)
    local s = rule and rule.sens
    if type(s) ~= 'table' then return 0 end
    return tonumber(s[tier]) or 0
end

--- The rules of an injury type for a modality, always as a list.
function F.RulesFor(injuryType, modality)
    local byType = F.Signs[injuryType]
    local r = byType and byType[modality]
    if not r then return {} end
    if r.sign then return { r } end
    return r
end

--- Whether a rule applies to this injury (subtype, structure, kind, severity, visibility, cord).
--- `kindOf(structure)` and `visible(type, subtype)` are passed in so the catalogue stays pure.
function F.Applies(rule, inj, kindOf, visible)
    if type(rule) ~= 'table' or type(inj) ~= 'table' then return false end
    if rule.subtypes and not rule.subtypes[inj.subtype or ''] then return false end
    if rule.structures and not rule.structures[inj.structure or ''] then return false end
    if rule.kinds then
        local k = inj.structure and kindOf and kindOf(inj.structure) or nil
        if not k or not rule.kinds[k] then return false end
    end
    if rule.minSeverity and (tonumber(inj.severity) or 0) < rule.minSeverity then return false end
    if rule.visibleOnly and not (visible and visible(inj.type, inj.subtype)) then return false end
    if rule.cordOnly and not (type(inj.attrs) == 'table' and inj.attrs.cord) then return false end
    return true
end

function F.Label(sign) return F.SignLabels[sign] or tostring(sign) end
