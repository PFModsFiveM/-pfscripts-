-- Hospital core settings (server/hospital/*, client/hospital.lua; batch 17E, architecture 4.5).
-- Facilities, departments and beds, staff roles, triage, AI care at low population, the tariff,
-- coverage discounts and billing. Times in seconds, money in whole dollars.
--
-- Every coordinate below was moved here from config.lua (Config.Locations 'hospital', 'beds',
-- 'jailbeds', 'checking'); ApplyLegacyLocations at the end rewrites those old lists from this file.
Config = Config or {}
Config.Hospital = Config.Hospital or {}
local H = Config.Hospital

-- Jobs whose on-duty members are hospital staff (the AI threshold counts them).
H.StaffJobs = { ambulance = true }

-- Facilities. Ids are stable (they are stored in pf_hosp_admissions.hospital_id); bed ids are unique
-- inside one facility. `zone` is the whole building (staff "in the hospital", leaving without a
-- discharge); `reception` is the check-in desk; a department `zone` (optional) limits actions that
-- the architecture ties to that department (tier-3 triage in the ED). `legacyIndex` is the number
-- the old client events used for this hospital. `respawnDept` receives respawned patients;
-- `checkIn = false` facilities take no walk-in patients (the prison infirmary).
H.Facilities = {
    pillbox = {
        label = 'Pillbox Medical Center',
        legacyIndex = 1,
        checkIn = true,
        reception = { coords = vector3(308.36, -595.25, 43.28), radius = 4.0 },
        zone = { center = vector3(330.0, -588.0, 43.3), radius = 55.0 },
        blip = vector3(304.27, -600.33, 43.28),
        respawnDept = 'ed',
        respawnPoint = vector4(308.6, -592.8, 43.28, 70.0), -- every bed taken: the patient wakes at the desk
        departments = {
            ed = {
                label = 'Emergency department',
                zone = { center = vector3(352.0, -588.0, 43.1), radius = 14.0 },
                beds = {
                    { id = 'ed1', coords = vector4(353.1, -584.6, 43.11, 152.08), model = 1631638868 },
                    { id = 'ed2', coords = vector4(356.79, -585.86, 43.11, 152.08), model = 1631638868 },
                    { id = 'ed3', coords = vector4(354.12, -593.12, 43.1, 336.32), model = 2117668672 },
                    { id = 'ed4', coords = vector4(350.79, -591.8, 43.1, 336.32), model = 2117668672 },
                    { id = 'ed5', coords = vector4(346.99, -590.48, 43.1, 336.32), model = 2117668672 },
                },
            },
            ward = {
                label = 'Ward',
                imaging = true, -- 17A: imaging needs the patient in a bed inside an imaging department
                beds = {
                    { id = 'w1', coords = vector4(360.32, -587.19, 43.02, 152.08), model = -1091386327 },
                    { id = 'w2', coords = vector4(349.82, -583.33, 43.02, 152.08), model = -1091386327 },
                    { id = 'w3', coords = vector4(326.98, -576.17, 43.02, 152.08), model = -1091386327 },
                },
            },
        },
    },
    paleto = {
        label = 'Paleto Bay Medical Center',
        legacyIndex = 2,
        checkIn = true,
        reception = { coords = vector3(-254.54, 6331.78, 32.43), radius = 4.0 },
        zone = { center = vector3(-252.0, 6321.0, 32.4), radius = 35.0 },
        respawnDept = 'ed',
        respawnPoint = vector4(-253.9, 6329.6, 32.43, 220.0),
        departments = {
            ed = {
                label = 'Emergency department',
                beds = {
                    { id = 'ed1', coords = vector4(-252.43, 6312.25, 32.34, 313.48), model = 2117668672 },
                    { id = 'ed2', coords = vector4(-247.04, 6317.95, 32.34, 134.64), model = 2117668672 },
                    { id = 'ed3', coords = vector4(-255.98, 6315.67, 32.34, 313.91), model = 2117668672 },
                },
            },
        },
    },
    -- The prison infirmary (the old 'jailbeds'): inmates respawn here; no walk-in check-in.
    bolingbroke = {
        label = 'Bolingbroke Infirmary',
        checkIn = false,
        custody = true,
        zone = { center = vector3(1766.9, 2594.8, 45.66), radius = 20.0 },
        respawnDept = 'infirmary',
        respawnPoint = vector4(1766.9, 2594.8, 45.66, 270.0),
        departments = {
            infirmary = {
                label = 'Infirmary',
                beds = {
                    { id = 'i1', coords = vector4(1761.96, 2597.74, 45.66, 270.14), model = 2117668672 },
                    { id = 'i2', coords = vector4(1761.96, 2591.51, 45.66, 269.8), model = 2117668672 },
                    { id = 'i3', coords = vector4(1771.8, 2598.02, 45.66, 89.05), model = 2117668672 },
                    { id = 'i4', coords = vector4(1771.85, 2591.85, 45.66, 91.51), model = 2117668672 },
                },
            },
        },
    },
}
-- Order used for "nearest hospital" ties and the legacy numeric index.
H.Order = { 'pillbox', 'paleto' }
H.CustodyFacility = 'bolingbroke' -- respawn of a jailed player (metadata injail > 0)
H.RespawnAtNearest = (Config.RespawnAtNearestHospital ~= false)

-- Medical tiers (architecture 11.6). With pf-government running the tier comes from the
-- qualifications (granted or implied by grade); without it from the grade.
H.Tiers = {
    Quals = { { 'surgeon', 5 }, { 'physician', 5 }, { 'nurse', 4 }, { 'paramedic', 3 }, { 'emt', 2 }, { 'emr', 1 } },
    GradeFallback = { [0] = 1, [1] = 3, [2] = 5, [3] = 5, [4] = 5 },
    SurgeonQual = 'surgeon',
    SurgeonGradeFallback = 3, -- without pf-government: this grade and above count as surgeons
}

-- Who may do what. Every action also needs on-duty staff inside the admission's facility.
H.Roles = {
    TriageTier = 4,      -- nurse, anywhere in the facility
    TriageTierED = 3,    -- paramedic, inside the ED zone (a department `zone`)
    AdmitTier = 3,
    DischargeTier = 4,
    TransferTier = 4,
    TouchDistance = 3.0, -- triage / admit need the provider this close to the patient (server positions)
}

-- Triage colours (ESI 1-5). The server also sets an automatic triage from the medical engine at
-- every intake, so pf-justice booking screening works without staff; staff triage replaces it.
H.Triage = {
    Levels = { red = 1, orange = 2, yellow = 3, green = 4, blue = 5 },
    Auto = {
        Red = { gcsMax = 8, sbpMin = 90, spo2Min = 88 },   -- any of these -> red
        Orange = { hrMax = 120, painMin = 8, severityMin = 4 }, -- any of these -> orange
        YellowSeverityMin = 2,                             -- an open injury this bad -> yellow
    },
}

-- Low-population AI care (architecture 4.5.2, owner decision D17). The AI takes a waiting patient
-- only while fewer than MinStaff staff are on duty AND nobody accepted the patient within
-- WaitSeconds. It works at TimeMultiplier speed and PriceMultiplier price, never revives a down
-- patient, and leaves injuries 'stabilized' with restrictions (a medic does the definitive care).
H.AI = {
    MinStaff = tonumber(Config.MinimalDoctors) or 2,
    WaitSeconds = 180,
    TimeMultiplier = 2.0,
    PriceMultiplier = 1.5,
    BaseSeconds = 30,            -- examination and paperwork, before the multiplier
    PerInjurySeconds = 20,       -- per open non-surgical injury, before the multiplier
    BedDistance = 3.0,           -- the AI only works while the patient lies in their bed (server position)
    SurgeryWaitSeconds = 900,    -- surgery-required injuries wait this long with no surgeon on duty ...
    SurgeryComplicationChance = 0.15, -- ... then the AI operates with this chance of a complication
    SurgerySeverityMin = 4,      -- an injury whose care list has a surgery_* option needs surgery from this severity
    FollowUpSeconds = 86400,     -- the follow-up appointment the AI books (calendar)
    RestrictionHealFactor = 1.0, -- AI discharge restrictions last healSeconds x this
    TickSeconds = 10,
}

-- Prices (whole dollars). A bill is built only from server records: the admission (reason, bed
-- times, mode), the treatment log (pf_med_treatments) and the AI care log.
H.Tariff = {
    Admission = {
        checkin = 250,
        respawn = tonumber(Config.BillCost) or 2000,
        transfer = 0,
        admit = 250,           -- AdmitPatient from another resource (infirmary transfer, court order)
        walkin = 250,          -- staff triage of a patient who did not check in
    },
    BedHour = { ed = 150, ward = 100, infirmary = 0, icu = 400 }, -- per started hour of each stay (20A: ward/ICU stays)
    Treatments = {             -- action -> price; anything not listed costs DefaultTreatment
        basic_wound_care = 50, pressure_dressing = 40, hemostatic_gauze = 80, tourniquet = 60, chest_seal = 120,
        needle_decompression = 300, splint = 80, traction_splint = 150, pelvic_binder = 150, c_collar = 60,
        backboard = 60, iv_access = 60, fluids = 120, blood_onegative = 600, oxygen = 40, opa = 30, npa = 30,
        bvm = 60, intubation = 400, cpr = 0, defibrillate = 250, burn_dressing = 90, cooling = 20, sutures = 200,
        reduction = 300, cast = 350, antibiotics = 120, antidote = 250,
        surgery_trauma = 4000, surgery_ortho = 3500, surgery_neuro = 6000, surgery_burn = 3000,
        ai_stabilize = 300, ai_surgery = 4500,
    },
    Drugs = { txa = 150, morphine = 100, fentanyl = 120, naloxone = 80, epinephrine = 90 },
    DefaultTreatment = 75,
    Lab = { blood_type = 40, cbc = 80, tox = 150, bac = 60 },   -- 20A: per resulted lab order
    Imaging = { xray = 250, ct = 900 },                          -- 20A: per resulted imaging order
    BillableResults = { ok = true, applied = true, rosc = true }, -- treatment log results that are billed ('no_effect' is not)
    BedMinHours = 1,
}

-- Coverage (owner decision D6: there is no insurer). A flat discount per job, read from the
-- patient's server job when the bill is made (an offline patient gets none). First match wins.
H.Coverage = {
    { jobs = { police = true, ambulance = true, corrections = true, doj = true, judge = true }, onDuty = true, percent = 50, label = 'On-duty public servant' },
}

H.Billing = {
    Account = 'ambulance',        -- society:ambulance (owner decision D5)
    SweepSeconds = 120,           -- unclear payments and failed invoices are looked at this often
    MaxChargeAttempts = 5,        -- bank charges per bill before it goes to an invoice anyway
    InvoiceSender = nil,          -- nil: the hospital label
    Mail = true,                  -- an itemised mail (pf-citizen) when the bill is made
}

-- Discharge orders. Restrictions use the kinds the effect applier knows (17C).
H.Discharge = {
    RestrictionKinds = { no_drive = true, no_sprint = true, crutches = true, concussion = true, cast_arm_l = true,
        cast_arm_r = true, no_heavy_work = true },
    MaxRestrictions = 8,
    MaxRestrictionHours = 168,
    MaxFollowUpDays = 30,
}

H.Intake = {
    LeaveGraceSeconds = 60,       -- outside the facility this long after being seen inside -> left AMA
    OfflineGraceSeconds = 600,    -- offline this long with an open admission -> closed as left AMA
    TransferArriveSeconds = 3600, -- a transfer nobody brings to the new facility closes after this long
    RespawnReviveDelay = tonumber(Config.AIHealTimer) or 20, -- the respawn revive applies after this in the bed
    TickSeconds = 15,
}

-- Requests in the Dispatch app: one per waiting patient (accepting it is "a medic took the patient").
H.Request = { Kind = 'hospital.patient', Expires = 3600 }

-- Medical care in custody (batch 19G, server/hospital/custody.lua; architecture 4.1 SetCustodyCare,
-- 4.5, 5.3, 6.6). A patient in custody (an open pf-justice custody record or an active incarceration
-- order) is a custody patient: they cannot leave as "left AMA" (leaving is reported, never punished),
-- an escorted transfer to a public hospital needs an on-duty officer within EscortDistance (server
-- positions), and a discharge returns the custody record. Corrections staff only ever see
-- fit_for_work, restrictions (kinds) and infirmary_needed.
H.Custody = {
    -- Exports of the custody module and who may call them (nil invoker = this resource; '*' = open).
    Callers = {
        SetCustodyCare = { ['pf-justice'] = true, ['pfm-prison'] = true },
        GetCustodyCare = { ['pf-justice'] = true, ['pfm-prison'] = true, ['pf-policemdt-DEV'] = true, ['pf-emsmdt'] = true },
        IsInCustodyCare = '*',
        GetInmateMedicalStatus = { ['pfm-prison'] = true, ['pf-justice'] = true, ['pf-policemdt-DEV'] = true },
        ScreenPatient = { ['pf-justice'] = true, ['pfm-prison'] = true },
    },
    -- On-duty members of these jobs (or job types) are officers: escorts, and the privacy-safe view.
    OfficerJobs = { police = true, corrections = true },
    OfficerJobTypes = { leo = true, corrections = true },
    EscortDistance = 15.0,       -- the escort officer must be this close to the patient (server positions)
    EscortGraceSeconds = 30,     -- an escort further away than that for this long is reported once per gap
    LeaveGraceSeconds = 20,      -- a patient outside the facility for this long is reported once per excursion
    ArriveSeconds = 1800,        -- a transfer that has not reached the hospital by then is reported (not closed)
    -- an inmate who walks out of the prison infirmary (still inside the walls) is reported, and after
    -- this long the infirmary admission closes as discharged (frees the bed; never left AMA)
    InfirmaryLeaveCloseSeconds = 600,
    -- low population: a discharged custody patient with no on-duty officer online at all is taken
    -- back to the custody facility's return point by the server (otherwise the escort drives them)
    AutoReturnWithoutOfficers = true,
    BillPatient = false,         -- care in custody is provided by the state: no hospital bill to the inmate
    ScreenTier = 3,              -- staff screening (paramedic and up)
    PrescribeTier = 5,           -- prescriptions for inmates (physician)
    ScreeningValidHours = 72,    -- a screening counts for fit_for_work / infirmary_needed this long
    -- Restrictions that make an inmate unfit for prison work (the kinds only; no reasons leave AJ).
    UnfitRestrictions = { no_heavy_work = true, crutches = true, cast_arm_l = true, cast_arm_r = true, concussion = true },
    -- Where a custody patient wakes up after a reconnect when the admission has no bed (server teleport).
    -- Facility ids are the pf-justice ones (Config.Facilities / Config.Custody.ReturnPoint).
    ReturnPoints = {
        mrpd_holding = vector4(461.5, -996.0, 24.9, 90.0),
        bolingbroke = vector4(1761.52, 2480.86, 45.74, 210.0),
    },
    -- Prescriptions for inmates until the 20A pharmacy: self-care items dispensed from the facility's
    -- stock stash (staff restock it). maxDoses caps one prescription; minInterval in hours.
    Formulary = {
        painkillers = { label = 'Painkillers', dose = '1 tablet', maxDoses = 12, minIntervalHours = 2, controlled = false },
        bandage = { label = 'Bandage', dose = '1 bandage', maxDoses = 10, minIntervalHours = 1, controlled = false },
        ifaks = { label = 'IFAK', dose = '1 kit', maxDoses = 3, minIntervalHours = 6, controlled = false },
    },
    RxValidDays = 14,
    Stashes = {
        bolingbroke = { id = 'pf_infirmary_bolingbroke', label = 'Infirmary stock', maxweight = 100000, slots = 30 },
    },
}

-- ── Batch 20A: pharmacy, lab, imaging, surgery, ward/ICU stays ────────────────────────────────
-- (server/hospital/pharmacy.lua, lab.lua, imaging.lua, surgery.lua). Every price is in H.Tariff;
-- every result comes from the medical engine's own state on the server.

-- Pharmacy. A physician prescribes for a patient with an open admission (also as discharge
-- orders); the patient collects each fill at a pharmacy counter (server position), where the
-- items move from the facility's stock stash. Staff withdraw ward drugs for an admitted patient
-- and return what they did not use. Every move of a controlled drug is one row of the
-- controlled-substance log (pf_hosp_dispense_log, written before the items move).
H.Pharmacy = {
    PrescribeTier = 5,           -- physicians write prescriptions
    LogTier = 4,                 -- nurses and up read the controlled-substance log and open the stock
    RxValidDays = 14,
    -- The counter where prescriptions are collected and ward drugs are drawn. The reception desk
    -- doubles as the pharmacy window until your interior has a counter: set it here and check in game.
    Counters = {
        pillbox = { coords = vector3(308.36, -595.25, 43.28), radius = 3.0, label = 'Pillbox pharmacy' },
        paleto = { coords = vector3(-254.54, 6331.78, 32.43), radius = 3.0, label = 'Paleto pharmacy' },
    },
    -- Stock stashes (20C's supply room restocks them; staff can also restock by hand).
    Stashes = {
        pillbox = { id = 'pf_pharmacy_pillbox', label = 'Pillbox pharmacy stock', maxweight = 200000, slots = 40 },
        paleto = { id = 'pf_pharmacy_paleto', label = 'Paleto pharmacy stock', maxweight = 100000, slots = 30 },
    },
    -- Take-home prescriptions: units per fill, fills (1 + refills), hours between fills, price per unit.
    Formulary = {
        painkillers = { label = 'Painkillers', dose = '1 tablet when needed, at most every 4 h', maxUnits = 12, maxFills = 3, refillHours = 24, price = 15 },
        antibiotics = { label = 'Antibiotics', dose = 'as directed by staff', maxUnits = 6, maxFills = 2, refillHours = 24, price = 60 },
        bandage = { label = 'Bandages', dose = 'change daily', maxUnits = 10, maxFills = 2, refillHours = 24, price = 5 },
        crutches = { label = 'Crutches', dose = 'walking aid', maxUnits = 1, maxFills = 1, refillHours = 0, price = 150 },
    },
    -- Ward drugs staff draw from the stock for an admitted patient (scope of practice by tier).
    -- controlled = true: every withdrawal and return is in the controlled-substance log.
    Ward = {
        morphine = { label = 'Morphine', tier = 3, max = 2, controlled = true },
        fentanyl = { label = 'Fentanyl', tier = 3, max = 2, controlled = true },
        naloxone = { label = 'Naloxone', tier = 2, max = 2, controlled = false },
        txa = { label = 'Tranexamic acid', tier = 3, max = 2, controlled = false },
        antibiotics = { label = 'Antibiotics', tier = 4, max = 2, controlled = false },
    },
    LogRows = 50,
}

-- Lab orders. A nurse orders, a paramedic or above draws the sample next to the patient; the
-- sample is read from the engine's state at the draw and the result is released when it is due.
H.Lab = {
    OrderTier = 4,
    DrawTier = 3,
    ReadTier = 4,                -- the lab's reading tier (findings.lua lab sensitivity)
    OrderValidHours = 24,        -- an order nobody draws within this is cancelled
    Tests = {
        blood_type = { label = 'Blood type', seconds = 120 },
        cbc = { label = 'Complete blood count', seconds = 300 },
        tox = { label = 'Toxicology screen', seconds = 600 },
        bac = { label = 'Blood alcohol', seconds = 180 },
    },
    TickSeconds = 15,
}

-- Imaging orders. A physician orders; staff run the scan with the patient lying in a bed of an
-- imaging department (17A); radiology reads it at ReadTier and confirmed findings confirm the
-- diagnosis through the 17A diagnosis layer.
H.Imaging = {
    OrderTier = 5,
    PerformTier = 3,
    ReadTier = 5,
    Distance = 10.0,             -- the operator stays this close to the patient during the scan
    Tests = {
        xray = { label = 'X-ray', seconds = 20 },
        ct = { label = 'CT scan', seconds = 30 },
    },
}

-- Surgery. A surgeon (qualification 'surgeon', or the grade fallback) operates on an injury with a
-- confirmed diagnosis, inside an operating room, with the patient lying in their server-held bed
-- in that room. The ED trauma bay (beds ed1/ed2) is the operating room by default: set your
-- interior's theatre here and check it in game. A facility without a room cannot operate.
H.Surgery = {
    Rooms = {
        { id = 'pillbox_or', hospital = 'pillbox', label = 'Pillbox trauma bay', coords = vector3(354.95, -585.23, 43.1), radius = 3.5 },
    },
    Procedures = {
        surgery_trauma = { label = 'Trauma surgery', seconds = 90 },
        surgery_ortho = { label = 'Orthopaedic surgery', seconds = 90 },
        surgery_neuro = { label = 'Neurosurgery', seconds = 120 },
        surgery_burn = { label = 'Burn surgery', seconds = 90 },
    },
}

-- Ward and ICU stays: a stay is one span of a bed-holding admission in one department at one care
-- level; the bill prices each span per started hour (Tariff.BedHour[level or dept]). A physician
-- sets the ICU level on a bed patient of the listed departments.
H.Stays = {
    LevelTier = 5,
    Levels = { icu = { label = 'Intensive care', depts = { ward = true, ed = true } } },
}

-- Read exports of the hospital services and who may call them (nil invoker = this resource).
H.Services = {
    Callers = {
        ListHospitalOrders = { ['pf-emsmdt'] = true },
        ListPrescriptions = { ['pf-emsmdt'] = true },
        GetControlledLog = { ['pf-emsmdt'] = true, ['pf-government'] = true },
    },
}

-- The old points in config.lua are rebuilt from the facilities: name/location only, and no bed
-- lists, so the legacy check-in handler in server/main.lua finds no bed and does nothing (the beds
-- are server-owned in server/hospital/beds.lua). Runs from whichever config file loads last.
function H.ApplyLegacyLocations()
    if type(Config.Locations) ~= 'table' then return end
    local hospitals, checking = {}, {}
    for _, id in ipairs(H.Order) do
        local f = H.Facilities[id]
        if f then
            hospitals[#hospitals + 1] = { name = f.label, location = f.reception and f.reception.coords or f.zone.center, id = id }
            if f.reception then checking[#checking + 1] = f.reception.coords end
        end
    end
    Config.Locations['hospital'] = hospitals
    Config.Locations['checking'] = checking
    Config.Locations['beds'] = nil
    Config.Locations['jailbeds'] = nil
end
H.ApplyLegacyLocations()
