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
    BedHour = { ed = 150, ward = 100, infirmary = 0 },
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
    BillableResults = { ok = true, success = true, applied = true, done = true },
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
