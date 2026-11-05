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

Config.CommunityService = {
    MaxUnits = 500,
    DefaultDays = 14,
}

Config.Supervision = {
    MaxDays = 365,
    ConditionKinds = { checkin = true, curfew = true, no_go = true, no_weapons = true, no_alcohol = true,
        community_service = true, monitor = true },
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
