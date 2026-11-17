-- pf-justice configuration (shared: the client side only reads labels; nothing here is a secret).
--
-- pf-justice owns every legal order (jail, prison, fines, citations, restitution, community service,
-- probation, parole, remand), the one sentence clock, the criminal record, custody, booking, property
-- lockers and bail. Other resources reach it through the exports in server/api.lua (and the custody,
-- property and bail files); each export checks the calling resource against Config.Callers.

Config = Config or {}

-- Longest single incarceration order, in minutes (the same cap pfm-prison and the MDT use today).
Config.MaxMinutes = 1440

-- ACE permissions that count as an admin for opts.actor = { kind = 'admin', src = n }.
Config.AdminAces = { 'command', 'pfjustice.admin', 'qbcore.admin', 'qbcore.god' }

-- Caller allowlists (PF_ARCHITECTURE 3.4). '*' = open (the result may still be filtered); a table
-- lists the resources allowed to call. pf-justice itself always passes.
Config.Callers = {
    -- orders (15B)
    CreateOrder            = { ['pf-policemdt-DEV'] = true, ['pfm-policejob'] = true, ['pfm-prison'] = true, ['pfm-adminmenu'] = true },
    GetOrder               = '*',
    GetOrders              = '*',
    GetActiveIncarceration = '*',
    IsIncarcerated         = '*',
    GetJailMinutes         = '*',
    AdjustOrder            = { ['pfm-prison'] = true, ['pfm-adminmenu'] = true },
    SetOrderState          = { ['pfm-prison'] = true, ['pfm-adminmenu'] = true },
    ReleaseNow             = { ['pfm-policejob'] = true, ['pfm-adminmenu'] = true, ['pfm-prison'] = true },
    IssueCitation          = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true },
    ContestCitation        = { ['pf-policemdt-DEV'] = true, ['pf-government'] = true },
    DecideCitation         = { ['pfm-adminmenu'] = true },
    PayOrder               = { ['pf-policemdt-DEV'] = true, ['pf-government'] = true },
    -- records (15B)
    GetRecord              = '*',
    AddRecordEntry         = { ['pf-policemdt-DEV'] = true },
    Expunge                = { ['pf-government'] = true, ['pfm-adminmenu'] = true },
    -- custody, booking, property, bail (15C)
    OpenCustody            = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true },
    GetCustody             = '*',
    SetCustodyState        = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true },
    BookCustody            = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true },
    AssignHoldingCell      = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true },
    AddCustodyLog          = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true, ['pf-ambulancejob'] = true },
    TransferCustody        = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true, ['pf-ambulancejob'] = true, ['pfm-prison'] = true },
    ReturnCustody          = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true, ['pf-ambulancejob'] = true, ['pfm-prison'] = true },
    ReleaseFromCustody     = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true, ['pf-ambulancejob'] = true, ['pfm-prison'] = true },
    IsInHoldingCell        = '*',
    SeizeProperty          = { ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true, ['pfm-prison'] = true },
    GetPropertyReceipt     = { ['pf-policemdt-DEV'] = true, ['pfm-policejob'] = true, ['pfm-prison'] = true, ['pf-citizen'] = true },
    GetBooking             = { ['pf-policemdt-DEV'] = true, ['pfm-policejob'] = true, ['pfm-prison'] = true },
    ReturnProperty         = { ['pfm-prison'] = true, ['pf-policemdt-DEV'] = true },
    ForfeitPropertyItems   = { ['pf-policemdt-DEV'] = true, ['pfm-prison'] = true },
    OfferBail              = { ['pf-policemdt-DEV'] = true },
    AcceptBail             = { ['pf-policemdt-DEV'] = true },
    DeclineBail            = { ['pf-policemdt-DEV'] = true },
    GetBail                = '*',
    ExonerateBail          = { ['pfm-adminmenu'] = true },
    ForfeitBail            = { ['pfm-adminmenu'] = true },
    -- courts and warrant reviews (19A); the judge app (b21) is pf-justice itself
    FileCase               = { ['pf-policemdt-DEV'] = true },
    ScheduleHearing        = { ['pfm-adminmenu'] = true },
    RecordDecision         = { ['pfm-adminmenu'] = true },
    IssueReleaseOrder      = { ['pfm-adminmenu'] = true },
    IssueCourtOrder        = { ['pfm-adminmenu'] = true },
    RevokeCourtOrder       = { ['pfm-adminmenu'] = true },
    IsCourtOrderValid      = { ['pf-ambulancejob'] = true, ['pfm-policejob'] = true, ['pf-policemdt-DEV'] = true },
    GetCase                = { ['pf-policemdt-DEV'] = true, ['pf-government'] = true, ['pfm-adminmenu'] = true },
    ListDocket             = '*',
    RequestWarrantReview   = { ['pf-policemdt-DEV'] = true },
    DecideWarrant          = { ['pfm-adminmenu'] = true },
    GetWarrantReview       = { ['pf-policemdt-DEV'] = true, ['pfm-adminmenu'] = true },
}

-- What AdjustOrder may do per calling resource (pf-justice itself and admins may do everything).
-- pfm-prison credits work time, forfeits those credits after a discipline hearing and suspends on an
-- escape (resumed on recapture); a court decides everything else.
Config.AdjustKinds = {
    ['pfm-prison'] = { credit = true, forfeit = true, suspend = true, resume = true },
    ['pfm-adminmenu'] = { credit = true, forfeit = true, modify = true, suspend = true, resume = true },
}

-- Target states SetOrderState accepts per calling resource. pfm-prison finishes intake ('active' from
-- 'pending' in transport mode) and completes; an escape is a suspension (AdjustOrder), never a completion.
Config.SetStateTargets = {
    ['pfm-prison'] = { active = true, completed = true },
    ['pfm-adminmenu'] = { active = true, completed = true, vacated = true, revoked = true, waived = true },
}

-- Fields of an order other resources receive (GetOrder / GetOrders / events carry all of them to
-- pf-justice itself). 'all' or a list of public field names.
Config.OrderFields = {
    default = { 'id', 'cid', 'kind', 'state', 'facility', 'clock', 'remainingSeconds', 'requiredSeconds', 'amount',
        'paidAmount', 'units', 'unitsDone', 'days', 'dueAt', 'endsAt', 'startsAt', 'createdAt' },
    ['pf-policemdt-DEV'] = 'all',
    ['pfm-prison'] = 'all',
    ['pfm-adminmenu'] = 'all',
    ['pf-government'] = 'all',
}

-- Fields of a criminal record entry per calling resource (GetRecord). Expunged entries are never
-- returned to other resources.
Config.RecordFields = {
    default = { 'id', 'kind', 'summary', 'at' },
    ['pf-policemdt-DEV'] = 'all',
    ['pf-government'] = 'all',
    ['pfm-adminmenu'] = 'all',
}

-- The one sentence clock (PF_ARCHITECTURE 4.7.2; owner decision D2: online time for jail and
-- prison, real time for community-service deadlines, probation and parole).
Config.Clock = {
    TickSeconds = 15,          -- incarceration tick for online inmates
    SweepSeconds = 60,         -- deadlines, supervision ends, payment sweep
    MaxGapSeconds = 60,        -- a tick never counts more than this (a server hitch is not time served)
    OfflineRate = 0.25,        -- 'hybrid': share of offline wall time that counts at the next load
    Policy = {
        jail = 'online', prison = 'online', remand = 'online',
        community_service = 'realtime', probation = 'realtime', parole = 'realtime',
    },
    -- Resources that may set spec.clock to something other than the policy (pf-justice itself always may).
    OverrideCallers = { ['pfm-adminmenu'] = true },
    -- In hospital custody (pf-ambulancejob IsInCare and the custody record says 'hospital') time counts.
    HospitalCountsAsInside = true,
}

-- Credits and forfeits pfm-prison may give through AdjustOrder (admins and courts are not capped).
Config.Credits = {
    MaxSecondsPerCall = 3600,  -- one work ticket, one hearing
    MaxShare = 0.5,            -- total credits at most this share of the required time
}

-- Incarceration intake: 'teleport' starts the order at once (today's behaviour); 'transport' keeps
-- it 'pending' until pfm-prison reports the intake (SetOrderState(orderId, 'active')).
Config.Prison = {
    Intake = 'teleport',
}

-- Facilities an incarceration order can name. presence = the resource and export that answer "is
-- this player inside right now" (server side); fallback = the radius the clock uses when that
-- resource is not running, so time never stops for that reason.
Config.Facilities = {
    bolingbroke = {
        label = 'Bolingbroke Penitentiary',
        kinds = { jail = true, prison = true, remand = true },
        presence = { resource = 'pfm-prison', export = 'IsInside' },
        fallback = { center = vector3(1693.33, 2569.51, 45.56), radius = 200.0 },
    },
    mrpd_holding = {
        label = 'Mission Row holding',
        kinds = { jail = true, remand = true },
        presence = { resource = 'pf-justice', export = 'IsInHoldingCell' },
        fallback = { center = vector3(467.0, -998.0, 24.9), radius = 20.0 },
    },
}
-- Facility an incarceration order uses when the caller names none.
Config.DefaultFacility = { jail = 'bolingbroke', prison = 'bolingbroke', remand = 'mrpd_holding' }

-- Fines, citations and restitution (owner decision D4: police-issued money to society:police, court
-- fines to society:doj).
Config.Fines = {
    MaxAmount = 1000000,
    DueDays = 14,              -- default due date of a fine or citation
    Accounts = {               -- society per order source type
        mdt_sentence = 'police', citation = 'police', field = 'police', admin = 'police', legacy = 'police',
        court_decision = 'doj',
    },
    DefaultAccount = 'police',
    PaymentHoldSeconds = 120,  -- an unclear payment is looked up again after this long
    InvoiceOnRefusal = true,   -- the citizen could not pay: the order becomes a pfm-phone invoice
    PayCooldownSeconds = 5,    -- one payment attempt per payer every 5 s (architecture 6.3)
    -- a phone invoice paid after its order stopped waiting for it is refunded; after this many
    -- clearly refused refund attempts (e.g. the society is empty) it is left to an admin
    RefundMaxAttempts = 10,
}

Config.Citations = {
    ContestDays = 7,           -- default window to contest a citation
    MaxContestDays = 30,
    OfficerJobTypes = { leo = true },
}

-- Community service (orders: 15B; runtime: 19C server/community_service.lua, PF_ARCHITECTURE 4.7.9).
-- 19C reads every other key with a safe default in its own file.
Config.CommunityService = {
    MaxUnits = 500,
    DefaultDays = 14,
    -- sign-in points (server zones) where a citizen opens a shift
    SignIn = {
        { id = 'cityhall', label = 'City Hall community service desk', coords = vector3(-544.67, -204.25, 38.22), radius = 15.0 },
        { id = 'sandy', label = 'Sandy Shores community service desk', coords = vector3(1853.0, 3689.0, 34.3), radius = 15.0 },
        { id = 'paleto', label = 'Paleto Bay community service desk', coords = vector3(-448.0, 6012.0, 31.7), radius = 15.0 },
    },
    NearRadius = 1500.0,          -- eligible GOV work orders listed within this distance of the citizen
    MinStepSeconds = 20,          -- one task step at most every 20 s (architecture 6.3)
    MinStepDistance = 3.0,        -- litter / graffiti steps at a different point of the site
    SampleSeconds = 1,            -- on-site presence sampled at 1 Hz from server positions
    ShiftMaxHours = 4,            -- an open shift ends after this long
    SupervisorBonus = 1.25,       -- a verified (supervised) shift counts units x this
    SupervisorJobs = { doj = 3, government = 0 },   -- on-duty doj probation officers (grade 3+) and government staff
    SupervisorDistance = 30.0,    -- the supervisor stands near the citizen to verify
    OverdueFilesCase = true,      -- a missed deadline files a court item (FileCase kind 'violation'); never prison
}

-- Probation and parole (orders: 15B; runtime: 19B server/supervision.lua and server/monitors.lua,
-- PF_ARCHITECTURE 4.7.8). 19B reads every other key with a safe default in its own file.
Config.Supervision = {
    MaxDays = 365,
    ConditionKinds = { checkin = true, curfew = true, no_go = true, no_weapons = true, no_alcohol = true,
        community_service = true, monitor = true },
    OfficerJobs = { doj = 3, judge = 0 },   -- probation officers (doj grade 3 = probation officer, 4 = chief) and judges
    ReportJobTypes = { leo = true },        -- on-duty police may report a violation they witnessed
    OfficerDistance = 5.0,                  -- a field visit: the officer stands next to the citizen
    CheckInCommand = 'checkin',
    CheckInCooldownSeconds = 60,
    CheckInGraceHours = 24,                 -- a check-in is overdue this long after it was due
    AppointmentGraceMinutes = 30,
    AppointmentWindowMinutes = 60,
    AppointmentMinLeadMinutes = 15,
    AppointmentMaxDaysAhead = 60,
    CalendarRemindMinutes = 60,
    SweepSeconds = 60,
    MailSender = 'San Andreas Probation Service',
    Offices = {
        { label = 'City Hall probation office', coords = vector3(-544.67, -204.25, 38.22), radius = 30.0 },
        { label = 'Sandy Shores probation desk', coords = vector3(1853.0, 3689.0, 34.3), radius = 25.0 },
        { label = 'Paleto Bay probation desk', coords = vector3(-448.0, 6012.0, 31.7), radius = 25.0 },
    },
    Monitor = {
        SampleSeconds = 5,                  -- geofence at 0.2 Hz for monitored online players
    },
    Zones = {},                             -- named no-go / curfew zones: [id] = { label, coords = vector3, radius }
}

-- Courts (19A server/courts.lua and server/warrants.lua, PF_ARCHITECTURE 4.7.7). Court roles come from
-- pfm-core jobs (on duty): judge = job judge (magistrate, judge, chief judge); doj grades 0 clerk,
-- 1 prosecutor, 2 public defender, 3 probation officer, 4 chief of justice (every doj role); private
-- lawyers (job lawyer) may defend. Admins (Config.AdminAces) act as every role.
Config.Courts = {
    Roles = {
        judge = { judge = 0 },
        clerk = { doj = { 0, 4 } },
        prosecutor = { doj = { 1, 4 } },
        defender = { doj = { 2, 4 }, lawyer = 'any' },
    },
    CaseNoPrefix = { criminal = 'CR', violation = 'VI', citation_contest = 'CT', appeal = 'AP' },
    Courtrooms = {
        { id = 'courtroom_1', label = 'Courtroom 1', coords = vector3(-544.85, -204.40, 38.22) },
        { id = 'courtroom_2', label = 'Courtroom 2', coords = vector3(-544.85, -204.40, 38.22) },
    },
    DefaultCourtroom = 'courtroom_1',
    -- a filed case gets an arraignment at once: soon when the defendant is in custody, later otherwise
    AutoArraignment = true,
    ArraignmentInCustodySeconds = 1800,
    ArraignmentAtLargeSeconds = 2 * 86400,
    MaxHearingDaysAhead = 60,
    -- low population (architecture 4.7.7): an arraignment or bail hearing that no on-duty judge has decided
    -- this long after its time falls back to the published schedule (not-guilty plea, bail by charge
    -- class), recorded with decided_by = 'schedule'. Trials, sentences and warrants never auto-decide.
    AutoAfterSeconds = 900,
    TickSeconds = 60,
    DefaultBail = { infraction = 0, misdemeanor = 5000, felony = 25000 },  -- 0 = released on own recognizance
    ScheduleBailFelony = true,             -- false: felony bail always waits for a judge
    DefaultChargeClass = 'misdemeanor',
    ChargeClasses = {                      -- penal code -> class (anything else: DefaultChargeClass)
        ['PC-187'] = 'felony', ['PC-191'] = 'felony', ['PC-245'] = 'felony', ['PC-261'] = 'felony', ['PC-262'] = 'felony',
        ['PC-207'] = 'felony', ['PC-208'] = 'felony', ['PC-219'] = 'felony', ['PC-273'] = 'felony', ['PC-459'] = 'felony',
        ['PC-487'] = 'felony', ['PC-211'] = 'felony', ['PC-215'] = 'felony',
        ['PC-415'] = 'infraction',
    },
    -- court orders (IsCourtOrderValid): purposes a judge may issue, default and longest validity
    OrderKinds = { medical_records = true, telemetry = true, search = true, property = true,
        evidence_destroy = true, evidence_release = true },
    OrderHours = 72,
    MaxOrderHours = 24 * 30,
    -- warrant reviews: with no judge on duty for FallbackSeconds after the request, an on-duty police
    -- officer of at least FallbackPoliceGrade (never the requester) may decide through pf-justice, so
    -- warrants are not stuck on a server without judges (false = judges only)
    WarrantFallback = { Enabled = true, AfterSeconds = 1800, PoliceJobs = { police = 4 } },
    MailSender = 'San Andreas Superior Court',
    Commands = true,                       -- /courtorder, /warrantreviews, /warrantdecide for judges (until the b21 app)
}

-- Criminal record. A conviction entry is written once when one of these orders reaches the state.
Config.Records = {
    ConvictionOn = {
        jail = 'completed', prison = 'completed', community_service = 'completed',
        probation = 'completed', parole = 'completed', fine = 'paid', restitution = 'paid',
    },
    CitationOn = { paid = true, upheld = true },  -- a citation entry when a citation is paid or upheld
    MaxEntries = 100,
    -- Who may expunge (besides admins): an on-duty judge, or pf-government staff with this permission.
    ExpungeJobs = { judge = true },
    ExpungeGovPermission = 'records',
}

-- Audit retention (architecture 3.8): rows older than this are swept daily in batches of 500.
Config.Audit = {
    RetentionDays = 180,
    SweepSeconds = 86400,
}

-- ── blocks read by unit 15C (custody, booking, property, bail) ──────────────────────────────────

Config.Custody = {
    BookingPrefix = 'BK',                 -- booking number BK-<yyyymmdd>-<seq>
    -- Where a reconnecting player in arrested / in_transport / booking / held custody is put back.
    ReturnPoint = {
        mrpd_holding = vector4(461.5, -996.0, 24.9, 90.0),
        bolingbroke = vector4(1761.52, 2480.86, 45.74, 210.0),
    },
    DefaultFacility = 'mrpd_holding',
    ReCuffStates = { arrested = true, in_transport = true },
    -- Holding cells per facility (door = a pfm-doorlock door id once 15H adds SetDoorState).
    HoldingCells = {
        mrpd_holding = {
            { id = 'mrpd_cell_1', label = 'Cell 1', center = vector3(459.6, -994.0, 24.9), radius = 2.6, door = nil },
            { id = 'mrpd_cell_2', label = 'Cell 2', center = vector3(459.6, -998.3, 24.9), radius = 2.6, door = nil },
            { id = 'mrpd_cell_3', label = 'Cell 3', center = vector3(459.6, -1001.9, 24.9), radius = 2.6, door = nil },
        },
    },
    -- Booking happens inside one of these zones with an officer (same zones as the MDT sentencing).
    BookingZones = {
        { label = 'Mission Row PD', facility = 'mrpd_holding', coords = vector3(441.0, -981.0, 30.7), radius = 60.0 },
        { label = 'Sandy Shores Sheriff', facility = 'mrpd_holding', coords = vector3(1853.0, 3689.0, 34.3), radius = 40.0 },
        { label = 'Paleto Bay Sheriff', facility = 'mrpd_holding', coords = vector3(-448.0, 6012.0, 31.7), radius = 40.0 },
        { label = 'Bolingbroke Penitentiary', facility = 'bolingbroke', coords = vector3(1690.0, 2600.0, 45.6), radius = 250.0 },
    },
    -- Medical screening: patients in these states go to hospital before a holding cell.
    BlockScreening = { down = true, red = true, orange = true },
    MaxHoldSeconds = 4 * 3600,            -- a held custody without a decision is flagged after this long
    -- Who acts on custody: on-duty jobs by minimum grade, or any on-duty job of these types.
    OfficerJobs = { police = 0, corrections = 0 },
    OfficerJobTypes = { leo = true, corrections = true },
    MedicalJobs = { ambulance = 0 },
    MedicalJobTypes = { ems = true },
    CourtJobs = { judge = 0 },
    OfficerDistance = 5.0,                -- officer near the arrested person (server positions)
    TouchDistance = 2.5,                  -- arrest / cuff reach (PJ batch-14 standard)
    MugshotHosts = nil,                   -- optional allowlist of mugshot upload hosts, e.g. { ['i.imgur.com'] = true }
}

-- Legacy runtimes that still run beside pf-justice in batch 15 (16C / 16D set them to false when they
-- hand the runtime over): while the MDT jail runs, its imported bail is still paid through the MDT.
Config.Compat = {
    -- the old jail runtimes still run until batch 16 hands them over (16C sets prison, 16D sets mdt and policejob
    -- to false); while true, imported items stay listed only and legacy rows are shadowed, not taken over
    LegacyRuntimes = { mdt = false, prison = false, policejob = false }, -- batch 16: handed over to pf-justice
    RecordExpiryDays = 30,
}

Config.Property = {
    StashPrefix = 'pf_justice_property_',  -- stash id = prefix .. receiptId
    StashSlots = 60,
    StashWeight = 250000,
    Keep = {},                             -- item names never seized (e.g. 'id_card')
    MaxItems = 200,
}

Config.Bail = {
    Account = 'doj',                       -- bail is held in society:doj (owner decision D4)
    OfferSeconds = 600,                    -- an offer expires after this long
    PayerDistance = 5.0,                   -- payer within this many metres of the officer (server positions)
    MaxAmount = 1000000,
    Desks = {
        { label = 'Bolingbroke visitor desk', coords = vector3(1848.3, 2586.1, 45.7), radius = 25.0 },
        { label = 'Mission Row front desk', coords = vector3(441.0, -981.0, 30.7), radius = 15.0 },
    },
    PaymentHoldSeconds = 120,
}
