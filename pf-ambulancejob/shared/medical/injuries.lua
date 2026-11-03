-- Injury catalogue: every injury type with its subtypes, which structures it can affect, bleeding,
-- pain, functional effects, the care that stabilises and treats it, healing time, and what it does
-- to physiology. Severity is 1..5 (minor, moderate, serious, severe, critical); every per-severity
-- list has five entries. Pure data plus small derivation helpers; shared with the client.

PFMed = PFMed or {}
PFMed.Injuries = PFMed.Injuries or {}
local I = PFMed.Injuries

I.Severity = { 'minor', 'moderate', 'serious', 'severe', 'critical' }

-- Where an injury came from (pf_med_injuries.mechanism).
I.Mechanisms = {
    firearm = true, edged = true, blunt = true, fall = true, vehicle = true, pedestrian = true, burn = true,
    electrical = true, explosion = true, drowning = true, poisoning = true, illness = true, infection = true,
    crush = true, animal = true, environment = true, work = true, admin = true, legacy = true, unknown = true,
}

-- Injury recovery stages (architecture 5.2). Rank: higher is worse; a patient's stage is the worst
-- of their open injuries ('healthy' when none is open).
I.Stages = { 'injured', 'stabilized', 'treated', 'recovering', 'recovered', 'complicated' }
I.StageRank = { healthy = 0, recovered = 0, recovering = 1, treated = 2, stabilized = 3, injured = 4, complicated = 5 }
I.StageTransitions = {
    injured     = { stabilized = true, complicated = true },
    stabilized  = { treated = true, complicated = true },
    treated     = { recovering = true, complicated = true },
    recovering  = { recovered = true, complicated = true },
    complicated = { stabilized = true },
    recovered   = {},
}
function I.CanTransition(from, to)
    local t = I.StageTransitions[from]
    return t ~= nil and t[to] == true
end

local ANY = { bone = true, joint = true, organ = true, vessel = true, soft = true }

-- Effects per body part kind (anatomy GroupKind) and per severity, channels 0..3 (architecture 11.4).
local LIMB_HEAVY = {
    leg = { walk = { 1, 2, 3, 3, 3 }, sprint = { 2, 3, 3, 3, 3 }, jump = { 2, 3, 3, 3, 3 }, climb = { 2, 3, 3, 3, 3 } },
    arm = { aim = { 1, 2, 3, 3, 3 }, reload = { 1, 2, 2, 3, 3 }, climb = { 1, 2, 3, 3, 3 } },
    pelvis = { walk = { 1, 2, 3, 3, 3 }, sprint = { 2, 3, 3, 3, 3 }, jump = { 2, 3, 3, 3, 3 }, climb = { 2, 3, 3, 3, 3 } },
    torso = { stamina = { 1, 1, 2, 2, 3 }, sprint = { 0, 1, 1, 2, 2 }, climb = { 0, 1, 1, 2, 2 } },
    neck = { drive = { 1, 2, 2, 2, 2 }, aim = { 0, 1, 1, 2, 2 } },
    head = { vision = { 0, 1, 1, 2, 2 }, drive = { 0, 1, 2, 2, 2 } },
}
local LIMB_WOUND = {
    leg = { walk = { 0, 1, 2, 2, 3 }, sprint = { 1, 2, 2, 3, 3 }, jump = { 1, 1, 2, 3, 3 }, climb = { 0, 1, 2, 3, 3 } },
    arm = { aim = { 0, 1, 2, 2, 3 }, reload = { 0, 1, 1, 2, 3 }, climb = { 0, 1, 1, 2, 3 } },
    pelvis = { walk = { 0, 1, 2, 3, 3 }, sprint = { 1, 2, 3, 3, 3 } },
    torso = { stamina = { 0, 1, 2, 2, 3 }, sprint = { 0, 1, 1, 2, 3 } },
    neck = { stamina = { 0, 1, 1, 2, 2 }, drive = { 0, 0, 1, 2, 2 } },
    head = { vision = { 0, 1, 1, 2, 3 }, drive = { 0, 1, 1, 2, 2 } },
}
local LIMB_LIGHT = {
    leg = { walk = { 0, 0, 1, 1, 2 }, sprint = { 0, 1, 1, 2, 2 }, jump = { 0, 0, 1, 1, 2 } },
    arm = { aim = { 0, 0, 1, 1, 2 }, reload = { 0, 0, 0, 1, 1 } },
    pelvis = { walk = { 0, 0, 1, 1, 2 }, sprint = { 0, 1, 1, 2, 2 } },
    torso = { stamina = { 0, 0, 1, 1, 2 } },
    neck = { drive = { 0, 0, 1, 1, 1 } },
    head = { vision = { 0, 0, 1, 1, 2 } },
}

-- Physiology contributions by the structure hit (penetrating trauma, crush): see I.Physiology.
local PENETRATING_BY_STRUCTURE = {
    lung_l = { breathing = 0.03, pneumo = true }, lung_r = { breathing = 0.03, pneumo = true },
    heart = { tamponadeAt = 3 },
    brain = { headPenalty = { 2, 4, 7, 10, 12 }, lethalAt = 4, cause = 'head_trauma' },
    skull = { headPenalty = { 0, 1, 2, 4, 6 } },
    spine_cervical = { spinalShockAt = 3, breathing = 0.04 },
    spine_thoracic = { spinalShockAt = 3 },
    airway = { airwayPartialAt = 2, airwayObstructedAt = 4 },
}

I.Types = {
    fracture = {
        label = 'Fracture',
        subtypes = {
            closed = { label = 'Closed' },
            open = { label = 'Open', bleedMult = 2.5, infection = true, visible = true, painAdd = 1 },
            displaced = { label = 'Displaced', painAdd = 1, visible = true },
            comminuted = { label = 'Comminuted', painAdd = 2, bleedMult = 1.5 },
            stress = { label = 'Stress', painAdd = -1, bleedMult = 0 },
        },
        defaultSubtype = 'closed',
        kinds = { bone = true },
        bleed = { class = 1, mlPerMin = { 0, 1, 3, 6, 10 } },
        pain = { 2, 4, 6, 7, 8 },
        effects = LIMB_HEAVY,
        stabilizeBy = { 'splint', 'traction_splint', 'pelvic_binder', 'c_collar', 'backboard' },
        treatBy = { 'reduction', 'cast', 'surgery_ortho' },
        healSeconds = { 7200, 21600, 43200, 86400, 172800 },
        infection = false, visible = false,
        signs = { look = 'deformity', palpate = 'crepitus', xray = 'fracture_line' },
        physiology = {
            byStructure = {
                ribs_l = { breathing = 0.02 }, ribs_r = { breathing = 0.02 }, sternum = { breathing = 0.01 },
                skull = { headPenalty = { 0, 1, 2, 4, 6 } },
                spine_cervical = { spinalShockAt = 4, breathing = 0.04 }, spine_thoracic = { spinalShockAt = 4 },
            },
        },
    },
    dislocation = {
        label = 'Dislocation',
        subtypes = {
            shoulder = { label = 'Shoulder', structures = { 'shoulder_l', 'shoulder_r' } },
            elbow = { label = 'Elbow', structures = { 'elbow_l', 'elbow_r' } },
            hip = { label = 'Hip', structures = { 'hip_l', 'hip_r' }, painAdd = 1 },
            knee = { label = 'Knee', structures = { 'knee_l', 'knee_r' } },
            finger = { label = 'Finger', structures = { 'hand_l', 'hand_r' }, painAdd = -1 },
        },
        kinds = { joint = true },
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 1, 2 } },
        pain = { 3, 5, 6, 7, 8 },
        effects = LIMB_HEAVY,
        stabilizeBy = { 'splint' },
        treatBy = { 'reduction' },
        healSeconds = { 3600, 7200, 14400, 28800, 43200 },
        infection = false, visible = true,
        signs = { look = 'deformity', palpate = 'joint_instability' },
    },
    sprain = {
        label = 'Sprain',
        subtypes = {
            ankle = { label = 'Ankle', structures = { 'ankle_l', 'ankle_r' } },
            wrist = { label = 'Wrist', structures = { 'wrist_l', 'wrist_r' } },
            knee = { label = 'Knee', structures = { 'knee_l', 'knee_r' } },
            neck = { label = 'Neck (whiplash)', structures = { 'neck' } },
        },
        kinds = { joint = true, soft = true },
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 1, 2, 4, 5, 6 },
        effects = {
            leg = { walk = { 1, 1, 2, 2, 3 }, sprint = { 1, 2, 3, 3, 3 }, jump = { 1, 2, 3, 3, 3 }, climb = { 1, 1, 2, 3, 3 } },
            arm = { aim = { 0, 1, 1, 2, 2 }, reload = { 1, 1, 2, 2, 2 }, climb = { 0, 1, 2, 2, 3 } },
            neck = { drive = { 0, 1, 1, 2, 2 }, aim = { 0, 0, 1, 1, 2 } },
        },
        stabilizeBy = { 'splint', 'c_collar' },
        treatBy = { 'splint' },
        healSeconds = { 1800, 3600, 7200, 14400, 28800 },
        infection = false, visible = false,
        signs = { look = 'swelling', palpate = 'tenderness' },
    },
    bruising = {
        label = 'Bruising',
        subtypes = {
            contusion = { label = 'Contusion' },
            hematoma = { label = 'Hematoma', painAdd = 1 },
        },
        defaultSubtype = 'contusion',
        kinds = ANY, surface = true,
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 1, 2, 3, 4, 5 },
        effects = LIMB_LIGHT,
        stabilizeBy = {},
        treatBy = { 'cooling' },
        healSeconds = { 900, 1800, 3600, 7200, 14400 },
        infection = false, visible = true,
        signs = { look = 'bruise', palpate = 'tenderness' },
        physiology = { byRegionGroup = { head = { subtype = 'hematoma', headPenalty = { 0, 0, 1, 2, 3 } } } },
    },
    laceration = {
        label = 'Laceration',
        subtypes = {
            superficial = { label = 'Superficial', bleedMult = 0.5 },
            deep = { label = 'Deep' },
            arterial = { label = 'Arterial', arterial = true, mlPerMin = { 40, 90, 160, 260, 400 } },
        },
        defaultSubtype = 'deep',
        kinds = { soft = true, vessel = true }, surface = true,
        bleed = { class = 1, mlPerMin = { 2, 5, 12, 25, 45 } },
        pain = { 1, 2, 4, 5, 7 },
        effects = LIMB_WOUND,
        stabilizeBy = { 'pressure_dressing', 'hemostatic_gauze', 'tourniquet' },
        treatBy = { 'sutures', 'basic_wound_care' },
        healSeconds = { 1800, 3600, 10800, 21600, 43200 },
        infection = true, visible = true,
        signs = { look = 'open_wound' },
    },
    gunshot = {
        label = 'Gunshot wound',
        subtypes = {
            graze = { label = 'Graze', bleedMult = 0.3, surfaceOnly = true, painAdd = -1 },
            penetrating = { label = 'Penetrating' },
            perforating = { label = 'Perforating (exit wound)', bleedMult = 1.3 },
            retained = { label = 'Retained projectile' },
        },
        defaultSubtype = 'penetrating',
        kinds = ANY, surface = true,
        bleed = { class = 2, mlPerMin = { 5, 12, 25, 45, 80 } },
        pain = { 3, 5, 6, 8, 9 },
        effects = LIMB_WOUND,
        stabilizeBy = { 'pressure_dressing', 'hemostatic_gauze', 'tourniquet', 'chest_seal' },
        treatBy = { 'surgery_trauma', 'sutures' },
        healSeconds = { 7200, 21600, 43200, 86400, 172800 },
        infection = true, visible = true,
        signs = { look = 'entry_wound', fast_us = 'free_fluid', xray = 'projectile' },
        physiology = { byStructure = PENETRATING_BY_STRUCTURE },
    },
    stab = {
        label = 'Stab wound',
        subtypes = {
            superficial = { label = 'Superficial', bleedMult = 0.5, surfaceOnly = true },
            penetrating = { label = 'Penetrating' },
        },
        defaultSubtype = 'penetrating',
        kinds = ANY, surface = true,
        bleed = { class = 2, mlPerMin = { 4, 10, 20, 35, 60 } },
        pain = { 2, 4, 6, 7, 8 },
        effects = LIMB_WOUND,
        stabilizeBy = { 'pressure_dressing', 'hemostatic_gauze', 'tourniquet', 'chest_seal' },
        treatBy = { 'surgery_trauma', 'sutures' },
        healSeconds = { 3600, 14400, 43200, 86400, 172800 },
        infection = true, visible = true,
        signs = { look = 'open_wound', fast_us = 'free_fluid' },
        physiology = { byStructure = PENETRATING_BY_STRUCTURE },
    },
    burn = {
        label = 'Burn',
        subtypes = {
            first = { label = 'First degree', fluidPerTbsa = 0, painAdd = -1 },
            second = { label = 'Second degree', fluidPerTbsa = 0.15 },
            third = { label = 'Third degree', fluidPerTbsa = 0.25, infection = true },
        },
        defaultSubtype = 'second',
        kinds = { soft = true }, surface = true,
        fluid = true, -- the loss is plasma, not whole blood: it does not clot and is not visible bleeding
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 2, 4, 6, 7, 8 },
        effects = LIMB_WOUND,
        stabilizeBy = { 'burn_dressing', 'cooling' },
        treatBy = { 'burn_dressing', 'surgery_burn' },
        healSeconds = { 3600, 14400, 43200, 86400, 172800 },
        infection = true, visible = true,
        signs = { look = 'burn' },
        physiology = { byRegionGroup = { head = { airwayPartialAt = 3, airwayObstructedAt = 5 }, neck = { airwayPartialAt = 3, airwayObstructedAt = 5 } } },
    },
    crush = {
        label = 'Crush injury',
        subtypes = {
            limb = { label = 'Limb' },
            chest = { label = 'Chest', breathing = 0.03 },
            pelvis = { label = 'Pelvis', bleedMult = 2 },
        },
        defaultSubtype = 'limb',
        kinds = { bone = true, soft = true, organ = true }, surface = true,
        bleed = { class = 1, mlPerMin = { 1, 3, 6, 12, 20 } },
        pain = { 2, 4, 6, 8, 9 },
        effects = LIMB_HEAVY,
        stabilizeBy = { 'splint', 'pelvic_binder' },
        treatBy = { 'surgery_trauma', 'fluids' },
        healSeconds = { 7200, 21600, 43200, 86400, 172800 },
        infection = false, visible = true,
        signs = { look = 'swelling', palpate = 'tense_compartment' },
    },
    electrical = {
        label = 'Electrical injury',
        subtypes = {
            taser = { label = 'Taser barbs', painAdd = -1 },
            low_voltage = { label = 'Low voltage' },
            high_voltage = { label = 'High voltage', arrhythmiaAt = 4, arrestAt = 5 },
        },
        defaultSubtype = 'low_voltage',
        kinds = { soft = true }, surface = true, systemic = true,
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 1, 3, 5, 6, 7 },
        effects = LIMB_LIGHT,
        stabilizeBy = { 'burn_dressing' },
        treatBy = { 'burn_dressing', 'ecg_monitoring' },
        healSeconds = { 600, 3600, 14400, 43200, 86400 },
        infection = false, visible = true,
        signs = { look = 'entry_exit_marks', ecg = 'arrhythmia' },
    },
    head_trauma = {
        label = 'Head trauma',
        subtypes = {
            concussion = { label = 'Concussion', headPenalty = { 0, 1, 2, 3, 4 }, visible = false },
            skull_fracture = { label = 'Skull fracture', headPenalty = { 0, 1, 2, 4, 6 }, visible = true },
            epidural = { label = 'Epidural hematoma', headPenalty = { 1, 2, 4, 7, 10 }, lethalAt = 5, visible = false },
            subdural = { label = 'Subdural hematoma', headPenalty = { 1, 2, 4, 7, 10 }, lethalAt = 5, visible = false },
            diffuse = { label = 'Diffuse axonal injury', headPenalty = { 2, 3, 5, 8, 11 }, lethalAt = 5, visible = false },
        },
        defaultSubtype = 'concussion',
        kinds = { bone = true, organ = true }, structures = { 'skull', 'brain' },
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 1, 2 } },
        pain = { 2, 3, 4, 5, 6 },
        effects = { any = { vision = { 1, 1, 2, 2, 3 }, drive = { 1, 2, 2, 2, 2 }, aim = { 0, 1, 1, 2, 2 }, walk = { 0, 0, 1, 2, 3 } } },
        stabilizeBy = { 'c_collar', 'oxygen' },
        treatBy = { 'surgery_neuro', 'observation' },
        healSeconds = { 3600, 7200, 43200, 86400, 172800 },
        infection = false, visible = false,
        signs = { pupils = 'unequal_pupils', ct = 'intracranial_bleed' },
    },
    spinal = {
        label = 'Spinal injury',
        subtypes = {
            cervical = { label = 'Cervical', structures = { 'spine_cervical' }, breathingCord = 0.08 },
            thoracic = { label = 'Thoracic', structures = { 'spine_thoracic' } },
            lumbar = { label = 'Lumbar', structures = { 'spine_lumbar' } },
        },
        kinds = { bone = true },
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 1, 2 } },
        pain = { 3, 5, 6, 7, 8 },
        -- attrs.cord = true: cord involvement (spinal shock from serious, legs cannot work)
        effects = { any = { walk = { 0, 1, 2, 3, 3 }, sprint = { 1, 2, 3, 3, 3 }, climb = { 1, 2, 3, 3, 3 }, jump = { 1, 2, 3, 3, 3 } } },
        stabilizeBy = { 'c_collar', 'backboard' },
        treatBy = { 'surgery_neuro' },
        healSeconds = { 7200, 43200, 86400, 172800, 345600 },
        infection = false, visible = false,
        signs = { palpate = 'spinal_tenderness', ct = 'vertebral_fracture' },
    },
    internal_bleeding = {
        label = 'Internal bleeding',
        subtypes = {
            liver = { label = 'Liver', structures = { 'liver' } },
            spleen = { label = 'Spleen', structures = { 'spleen' } },
            kidney = { label = 'Kidney', structures = { 'kidney_l', 'kidney_r' }, bleedMult = 0.7 },
            pelvic = { label = 'Pelvic', structures = { 'pelvis', 'bladder' } },
            thoracic = { label = 'Thoracic', structures = { 'lung_l', 'lung_r', 'aorta', 'heart' } },
        },
        kinds = { organ = true, vessel = true, bone = true },
        internal = true, noclotAt = 3, -- from serious it does not stop by itself (needs surgery)
        bleed = { class = 3, mlPerMin = { 5, 12, 25, 50, 90 } },
        pain = { 1, 2, 3, 4, 5 },
        effects = { any = { stamina = { 0, 1, 1, 2, 3 }, sprint = { 0, 1, 1, 2, 3 } } },
        stabilizeBy = { 'pelvic_binder', 'txa', 'blood_onegative' },
        treatBy = { 'surgery_trauma' },
        healSeconds = { 7200, 21600, 43200, 86400, 172800 },
        infection = false, visible = false,
        signs = { fast_us = 'free_fluid', ct = 'organ_laceration' },
    },
    organ_trauma = {
        label = 'Organ trauma',
        subtypes = {
            tamponade = { label = 'Cardiac tamponade', structures = { 'heart' }, tamponade = true },
            pneumothorax = { label = 'Pneumothorax', structures = { 'lung_l', 'lung_r' }, breathing = 0.03 },
            tension = { label = 'Tension pneumothorax', structures = { 'lung_l', 'lung_r' }, breathing = 0.06, tension = true },
            hemothorax = { label = 'Hemothorax', structures = { 'lung_l', 'lung_r' }, breathing = 0.05, mlPerMin = { 5, 10, 20, 35, 60 }, internalBleed = true },
            bowel = { label = 'Bowel perforation', structures = { 'bowel', 'stomach' }, infection = true, painAdd = 1 },
        },
        kinds = { organ = true },
        internal = true,
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 2, 4, 5, 6, 7 },
        effects = { any = { stamina = { 1, 2, 2, 3, 3 }, sprint = { 1, 2, 3, 3, 3 } } },
        stabilizeBy = { 'needle_decompression', 'chest_seal', 'oxygen' },
        treatBy = { 'surgery_trauma', 'chest_tube' },
        healSeconds = { 7200, 21600, 43200, 86400, 172800 },
        infection = false, visible = false,
        signs = { auscultate = 'absent_breath_sounds', fast_us = 'pericardial_fluid' },
    },
    respiratory = {
        label = 'Respiratory problem',
        subtypes = {
            airway_obstruction = { label = 'Airway obstruction', airwayPartialAt = 1, airwayObstructedAt = 4 },
            smoke_inhalation = { label = 'Smoke inhalation', breathing = 0.04, airwayPartialAt = 3 },
            aspiration = { label = 'Aspiration', breathing = 0.05 },
        },
        kinds = { organ = true }, structures = { 'airway', 'lung_l', 'lung_r' }, defaultStructure = 'airway', systemic = true,
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 0, 1, 2, 3, 3 },
        effects = { any = { stamina = { 1, 2, 2, 3, 3 }, sprint = { 1, 2, 3, 3, 3 } } },
        stabilizeBy = { 'opa', 'npa', 'bvm', 'intubation', 'oxygen' },
        treatBy = { 'oxygen', 'intubation' },
        healSeconds = { 600, 1800, 7200, 21600, 43200 },
        infection = false, visible = false,
        signs = { look = 'cyanosis', auscultate = 'stridor' },
    },
    drowning = {
        label = 'Drowning',
        subtypes = { near_drowning = { label = 'Near drowning', breathing = 0.08 } },
        defaultSubtype = 'near_drowning',
        kinds = { organ = true }, structures = { 'airway', 'lung_l', 'lung_r' }, defaultStructure = 'airway', systemic = true,
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 0, 1, 1, 2, 2 },
        effects = { any = { stamina = { 1, 2, 3, 3, 3 } } },
        stabilizeBy = { 'bvm', 'oxygen', 'cpr' },
        treatBy = { 'oxygen' },
        healSeconds = { 1800, 3600, 14400, 43200, 86400 },
        infection = false, visible = false,
        signs = { auscultate = 'crackles', look = 'cyanosis' },
    },
    poisoning = {
        label = 'Poisoning',
        -- the effect on the body comes from the toxin levels (physiology 11.3); the row is the record
        subtypes = {
            ethanol = { label = 'Alcohol', toxin = 'ethanol' }, opioid = { label = 'Opioid', toxin = 'opioid' },
            stimulant = { label = 'Stimulant', toxin = 'stimulant' }, sedative = { label = 'Sedative', toxin = 'sedative' },
            co = { label = 'Carbon monoxide', toxin = 'carbon_monoxide' }, food = { label = 'Food poisoning', toxin = 'food_poisoning' },
            chemical = { label = 'Chemical', toxin = 'poison' },
        },
        systemic = true, kinds = {},
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 0, 1, 2, 3, 4 },
        effects = { any = { vision = { 0, 1, 1, 2, 2 }, drive = { 1, 2, 2, 2, 2 } } },
        stabilizeBy = { 'naloxone', 'oxygen', 'antidote' },
        treatBy = { 'antidote', 'observation' },
        healSeconds = { 1800, 3600, 7200, 14400, 28800 },
        infection = false, visible = false,
        signs = { pupils = 'pinpoint_or_dilated', labs = 'tox_screen' },
    },
    illness = {
        label = 'Illness',
        subtypes = {
            food_poisoning = { label = 'Food poisoning', fever = { 0.3, 0.6, 1.0, 1.5, 2.0 }, hrAdd = { 5, 10, 15, 20, 30 } },
            infection_sepsis = { label = 'Sepsis', fever = { 0.5, 1.0, 1.5, 2.0, 2.5 }, hrAdd = { 10, 15, 25, 35, 45 }, sbpDrop = { 0, 0, 10, 25, 40 } },
            hypothermia = { label = 'Hypothermia', fever = { -0.8, -1.5, -2.5, -4.0, -6.0 }, hrAdd = { 0, -5, -15, -25, -35 } },
            heat_stroke = { label = 'Heat stroke', fever = { 0.8, 1.5, 2.2, 3.0, 4.0 }, hrAdd = { 10, 20, 30, 40, 50 }, headPenalty = { 0, 0, 1, 3, 6 } },
        },
        systemic = true, kinds = {},
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 1, 2, 3, 4, 5 },
        effects = { any = { stamina = { 1, 1, 2, 3, 3 }, vision = { 0, 0, 1, 1, 2 } } },
        stabilizeBy = { 'fluids', 'cooling', 'oxygen' },
        treatBy = { 'antibiotics', 'fluids', 'observation' },
        healSeconds = { 1800, 7200, 14400, 43200, 86400 },
        infection = false, visible = false,
        signs = { temperature = 'abnormal_temperature', labs = 'infection_markers' },
    },
    infection = {
        label = 'Infection',
        subtypes = {
            wound_infection = { label = 'Wound infection', fever = { 0.2, 0.4, 0.8, 1.2, 1.5 }, painAdd = 1 },
            sepsis = { label = 'Sepsis', fever = { 0.5, 1.0, 1.5, 2.0, 2.5 }, hrAdd = { 10, 15, 25, 35, 45 }, sbpDrop = { 0, 0, 10, 25, 40 } },
        },
        defaultSubtype = 'wound_infection',
        kinds = ANY, surface = true, systemic = true,
        bleed = { class = 0, mlPerMin = { 0, 0, 0, 0, 0 } },
        pain = { 1, 2, 3, 4, 5 },
        effects = { any = { stamina = { 0, 1, 1, 2, 3 } } },
        stabilizeBy = { 'antibiotics' },
        treatBy = { 'antibiotics', 'basic_wound_care' },
        healSeconds = { 3600, 14400, 43200, 86400, 172800 },
        infection = false, visible = true,
        signs = { look = 'redness_pus', temperature = 'fever', labs = 'infection_markers' },
    },
}

local function at(list, sev)
    if type(list) ~= 'table' then return 0 end
    return tonumber(list[sev]) or tonumber(list[#list]) or 0
end
I.At = at

--- Severity as an integer 1..5, or nil.
function I.CleanSeverity(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.floor(n)
    if n < 1 or n > 5 then return nil end
    return n
end

--- True when the type may sit on `structure` (nil structure: skin only or systemic).
function I.AllowsStructure(typeName, subtypeName, structure)
    local t = I.Types[typeName]
    if not t then return false end
    local sub = t.subtypes and subtypeName and t.subtypes[subtypeName] or nil
    if structure == nil then return t.surface == true or t.systemic == true end
    local A = PFMed.Anatomy
    local s = A and A.Structures[structure]
    if not s then return false end
    if sub and sub.surfaceOnly then return false end
    local list = (sub and sub.structures) or t.structures
    if list then
        for _, id in ipairs(list) do if id == structure then return true end end
        return false
    end
    return t.kinds ~= nil and t.kinds[s.kind] == true
end

-- How much a structure's blood supply multiplies a wound's bleeding.
I.StructureBleedFactor = { [0] = 0.5, [1] = 1.0, [2] = 2.5, [3] = 6.0 }

--- Starting bleed and flags for a new injury. Returns { mlPerMin, arterial, internal, noclot, fluid }.
function I.Bleed(typeName, subtypeName, structure, severity, attrs)
    local t = I.Types[typeName]
    if not t then return { mlPerMin = 0 } end
    local sub = t.subtypes and subtypeName and t.subtypes[subtypeName] or {}
    local A = PFMed.Anatomy
    local s = structure and A and A.Structures[structure] or nil
    local out = { arterial = false, internal = false, noclot = false, fluid = t.fluid == true }
    local ml
    if t.fluid then
        local tbsa = tonumber(attrs and attrs.tbsa) or (severity * 6)
        tbsa = math.max(0, math.min(100, tbsa))
        ml = tbsa * (sub.fluidPerTbsa or 0)
        out.noclot = true
    elseif sub.mlPerMin then
        ml = at(sub.mlPerMin, severity)
    else
        ml = at(t.bleed and t.bleed.mlPerMin, severity) * (sub.bleedMult or 1)
        if s and not t.internal then ml = ml * (I.StructureBleedFactor[s.bleedClass] or 1) end
    end
    if sub.arterial or (s and s.kind == 'vessel' and ml > 0) then out.arterial = true; out.noclot = true end
    local deep = s and (s.kind == 'organ' or s.kind == 'vessel' and typeName ~= 'laceration')
    if t.internal or sub.internalBleed or (deep and typeName ~= 'laceration' and ml > 0) or (typeName == 'fracture' and s and s.bleedClass >= 2 and subtypeName ~= 'open') then
        out.internal = true
    end
    if t.noclotAt and severity >= t.noclotAt then out.noclot = true end
    if out.internal and s and s.bleedClass >= 3 and severity >= 3 then out.noclot = true end
    out.mlPerMin = math.floor(ml * 100 + 0.5) / 100
    return out
end

--- Pain 0..10 for a new injury.
function I.Pain(typeName, subtypeName, severity)
    local t = I.Types[typeName]
    if not t then return 0 end
    local sub = t.subtypes and subtypeName and t.subtypes[subtypeName] or {}
    local p = at(t.pain, severity) + (sub.painAdd or 0)
    return math.max(0, math.min(10, p))
end

--- Whether the injury can be seen by looking (a provider still has to look: 17A).
function I.Visible(typeName, subtypeName)
    local t = I.Types[typeName]
    if not t then return false end
    local sub = t.subtypes and subtypeName and t.subtypes[subtypeName]
    if sub and sub.visible ~= nil then return sub.visible end
    return t.visible == true
end

--- Effect channels of one injury before treatment: { walk = n, ... }.
function I.Effects(inj)
    local t = inj and I.Types[inj.type]
    if not t or type(t.effects) ~= 'table' then return {} end
    local sev = I.CleanSeverity(inj.severity) or 1
    local A = PFMed.Anatomy
    local kind = A and A.GroupKindOf(inj.region, inj.structure) or nil
    local spec = (kind and t.effects[kind]) or t.effects.any
    local out = {}
    if spec then for ch, list in pairs(spec) do out[ch] = at(list, sev) end end
    if inj.type == 'spinal' and type(inj.attrs) == 'table' and inj.attrs.cord then out.walk = 3; out.sprint = 3; out.climb = 3; out.jump = 3 end
    return out
end

--- What one open injury does to physiology right now (treatments considered).
--- Returns { breathing, tension, tamponade, spinalShock, headPenalty, lethal, airway, fever, sbpDrop, hrAdd, arrest, cause }.
function I.Physiology(inj)
    local out = { breathing = 0, headPenalty = 0, fever = 0, sbpDrop = 0, hrAdd = 0 }
    local t = inj and I.Types[inj.type]
    if not t then return out end
    local sev = I.CleanSeverity(inj.severity) or 1
    local sub = t.subtypes and inj.subtype and t.subtypes[inj.subtype] or {}
    local tr = type(inj.treatments) == 'table' and inj.treatments or {}
    local attrs = type(inj.attrs) == 'table' and inj.attrs or {}

    local function apply(rule)
        if not rule then return end
        if rule.breathing then out.breathing = out.breathing + rule.breathing * sev end
        if rule.headPenalty then out.headPenalty = out.headPenalty + at(rule.headPenalty, sev) end
        if rule.lethalAt and sev >= rule.lethalAt then out.lethal = true; out.cause = rule.cause or 'head_trauma' end
        if rule.tamponadeAt and sev >= rule.tamponadeAt then out.tamponade = true end
        if rule.tamponade then out.tamponade = true end
        if rule.tension then out.tension = true end
        if rule.spinalShockAt and sev >= rule.spinalShockAt then out.spinalShock = true end
        if rule.airwayObstructedAt and sev >= rule.airwayObstructedAt then out.airway = 'obstructed'
        elseif rule.airwayPartialAt and sev >= rule.airwayPartialAt and out.airway ~= 'obstructed' then out.airway = 'partial' end
        if rule.fever then out.fever = out.fever + at(rule.fever, sev) end
        if rule.sbpDrop then out.sbpDrop = out.sbpDrop + at(rule.sbpDrop, sev) end
        if rule.hrAdd then out.hrAdd = out.hrAdd + at(rule.hrAdd, sev) end
        if rule.arrestAt and sev >= rule.arrestAt then out.arrest = true; out.cause = 'arrhythmia' end
        if rule.arrhythmiaAt and sev >= rule.arrhythmiaAt then out.arrhythmia = true end
    end

    apply(sub)
    local phys = t.physiology
    if phys and phys.byStructure and inj.structure then apply(phys.byStructure[inj.structure]) end
    if phys and phys.byRegionGroup then
        local A = PFMed.Anatomy
        local r = A and A.Regions[inj.region]
        local rule = r and phys.byRegionGroup[r.group]
        if rule and (not rule.subtype or rule.subtype == inj.subtype) then apply(rule) end
    end
    if inj.type == 'spinal' and attrs.cord then
        if sev >= 3 then out.spinalShock = true end
        if sub.breathingCord then out.breathing = out.breathing + sub.breathingCord * sev end
    end

    -- treatments set by the treatment engine (17B) neutralise the threat they address
    if out.tension and tr.decompressed then out.tension = false; out.breathing = out.breathing * 0.5 end
    if out.tamponade and tr.pericardiocentesis then out.tamponade = false end
    if tr.chest_seal and (inj.subtype == 'pneumothorax' or (phys and phys.byStructure == PENETRATING_BY_STRUCTURE)) then out.breathing = out.breathing * 0.6 end
    if tr.surgery then out.tension, out.tamponade, out.lethal, out.breathing = false, false, false, 0 end
    if out.breathing > 0.9 then out.breathing = 0.9 end
    return out
end

--- Toxin the poisoning subtype stands for (for records), or nil.
function I.ToxinOf(subtypeName)
    local sub = I.Types.poisoning.subtypes[subtypeName]
    return sub and sub.toxin or nil
end
