Config = {}

-- =====================================================
-- CORE SETTINGS
-- =====================================================

Config.Framework = 'qbcore' -- qbcore or esx
Config.FrameworkResourceName = 'pfm-core' -- name of your framework resource

-- =====================================================
-- GOVERNMENT JOB SETTINGS
-- =====================================================

Config.GovernmentJob = 'government'

-- Role-based permissions (grade => role name)
Config.Roles = {
    [4] = { name = 'Mayor', permissions = { 'all' } },
    -- 'events': post public city events in the citizen Calendar (pf-citizen)
    [3] = { name = 'Deputy Mayor', permissions = { 'laws', 'taxes', 'budgets', 'licenses', 'utilities', 'fines', 'staff', 'businesses', 'audit', 'events',
        'website', 'civilians', 'records' } },
    [2] = { name = 'Treasurer', permissions = { 'budgets', 'taxes', 'fines', 'audit', 'businesses' } },
    [1] = { name = 'Clerk', permissions = { 'licenses', 'fines', 'audit' } },
    [0] = { name = 'Utility Manager', permissions = { 'utilities', 'audit' } }
}

-- Permission definitions
-- Available permissions: laws, taxes, budgets, licenses, utilities, fines, staff, businesses, audit, dashboard, settings,
-- website  (edit the official government website everyone sees in the browsers),
-- civilians (correct a citizen's identity and job, move a vehicle to the government lockup),
-- records  (delete criminal records and clear convictions; give it to a justice role if you add one)
-- 'all' grants all permissions

-- =====================================================
-- UI SETTINGS
-- =====================================================

Config.UI = {
    DefaultPassword = '', -- Empty = no password required, set a default password for lockscreen
    RequireAuth = false, -- Require login on government terminal
    Theme = 'windows11', -- windows11 (future: dark, custom)
}

-- =====================================================
-- TAX SYSTEM
-- =====================================================

Config.Taxes = {
    -- Tax rate enforcement (min/max caps)
    -- Change these values to control what the mayor can set in the government computer.
    Enforcement = {
        income = { min = 0.00, max = 50.00 },
        business = { min = 0.00, max = 30.00 },
        vehicle_registration = { min = 0.00, max = 5000.00 },
        sales = { min = 0.00, max = 50.00 },
        vehicle_purchase = { min = 0.00, max = 20.00 },
        property_transfer = { min = 0.00, max = 20.00 },
        supplies = { min = 0.00, max = 20.00 },
        property = { min = 0.00, max = 5.00 } -- weekly property tax, % of the house value
    },

    -- Default tax types (auto-seeded on startup)
    Defaults = {
        { type = 'income', rate = 15.00, min = 0.00, max = 50.00, description = 'Income tax on paychecks and job payments' },
        { type = 'business', rate = 10.00, min = 0.00, max = 30.00, description = 'Business revenue tax' },
        { type = 'property_transfer', rate = 5.00, min = 0.00, max = 20.00, description = 'Property purchase/transfer tax' },
        { type = 'vehicle_registration', rate = 500.00, min = 0.00, max = 5000.00, description = 'Vehicle registration fee (flat)' },
        { type = 'vehicle_purchase', rate = 8.00, min = 0.00, max = 20.00, description = 'Vehicle purchase tax' },
        { type = 'sales', rate = 8.50, min = 0.00, max = 50.00, description = 'Sales tax on transactions' },
        { type = 'supplies', rate = 6.00, min = 0.00, max = 20.00, description = 'Business supplies purchase tax' },
        { type = 'property', rate = 0.50, min = 0.00, max = 5.00, description = 'Weekly property tax on owned houses (% of the house value)' }
    },

    -- Disable taxes not in Defaults
    DisableUnknown = true,

    -- Business tax handling
    BusinessTax = {
        UseSocietyAccount = true,
        BillOnInsufficientFunds = true,
        BillDueDays = 7
    },

    -- Auto tax collection settings
    AutoCollection = {
        enabled = true,
        interval = 30, -- minutes between auto collection runs (the property tax below runs in it)
        business_tax_frequency = 86400, -- seconds (1 day)
    },

    -- Weekly property tax on every owned house (pfm-houses), billed to the owner as a 'tax' bill that
    -- shows in the citizen Bills app. The rate is the 'property' tax above: seeded from Defaults once,
    -- then changed in game by the mayor (the database row is the live rate; disabling the tax stops
    -- the billing). Weeks start Monday 00:00 UTC. Each house gets at most one bill per week, to the
    -- owner the first run that week sees (a house sold mid-week: the seller's bill stands and the buyer
    -- pays from the next week). Weeks the server was down are not billed later.
    -- Unpaid bills go delinquent like any other bill (Config.Bills); houses are never repossessed.
    PropertyTax = {
        Enabled = true,
        Minimum = 50,          -- dollars per house per week, however low the value
        DueDays = 7,           -- days to pay before the bill is overdue
        Resource = 'pfm-houses', -- exports GetOwnedHouses() -> { { house, citizenid, value, label } } (false, 'not_ready' while starting)
        IssuerName = 'Tax Office',
        RetrySeconds = 120,    -- pfm-houses still starting (or its export failed): try again this soon
    }
}

-- =====================================================
-- BUDGET SYSTEM
-- =====================================================

Config.Budgets = {
    AutoReset = true,
    PaychecksPerMonth = 30,
    -- keyed society moves (SpendFromDepartmentSociety / AddFundsToDepartmentSociety with a key): a
    -- pending move whose ledger attempt never reached the bank is failed after this grace, so the
    -- same key can move it under the next attempt; unknown moves are looked at again every ReconcileSeconds
    KeyedMoveGraceSeconds = 300,
    ReconcileSeconds = 60,

    Defaults = {
        police = 200000,
        ems = 160000,
        dot = 120000,
        power = 150000,
        water = 100000,
        government = 90000,
        corrections = 140000,
        doj = 90000
    },

    -- corrections and doj (batch 15): the prison staff and the courts. Court fines and bail are held
    -- in society:doj (owner decision D4); corrections pays prison operations.
    LinkedSocietyAccounts = {
        police = 'police',
        ems = 'ambulance',
        dot = 'dot',
        power = 'power',
        water = 'water',
        government = 'government',
        corrections = 'corrections',
        doj = 'doj'
    },

    SalaryTrackedJobs = {
        police = 'police',
        ems = 'ambulance',
        corrections = 'corrections',
        doj = 'doj'
    },

    Planning = {
        EmergencyBufferPercent = 0.10,
        EquipmentPerEmployee = {
            police = 900,
            ems = 700,
            corrections = 600,
            doj = 200
        },
        FleetPerEmployee = {
            police = 550,
            ems = 500,
            corrections = 300
        },
        FacilityBase = {
            police = 12000,
            ems = 10000,
            dot = 9000,
            power = 18000,
            water = 12000,
            government = 7000,
            corrections = 15000,
            doj = 6000
        }
    },

    DepartmentNames = {
        police = 'Police Department',
        ems = 'Emergency Medical Services',
        dot = 'Department of Transportation',
        power = 'Power Department',
        water = 'Water Department',
        government = 'Government Operations',
        corrections = 'Department of Corrections',
        doj = 'Department of Justice'
    }
}

Config.AssistantRecentLawWindowDays = 7

Config.AssistantWeather = {
    Provider = 'qb_weathersync',
    FallbackProviders = { 'vSync', 'weather' },
    UnavailableText = 'Weather data is unavailable right now. Check local in-city conditions.'
}

Config.AssistantServicePoints = {
    {
        name = 'City Hall Front Desk',
        description = 'Permits, tax guidance, and civil filings.',
        category = 'cityhall',
        x = -544.67,
        y = -204.25,
        z = 38.22,
        url = 'https://los-santos.gov#home'
    },
    {
        name = 'Municipal Court',
        description = 'Court scheduling and legal records support.',
        category = 'cityhall',
        x = -543.17,
        y = -198.53,
        z = 38.22,
        url = 'https://los-santos.gov#laws'
    }
}

-- =====================================================
-- LAWS SYSTEM
-- =====================================================

Config.Laws = {
    -- Law categories
    Categories = {
        'Traffic',
        'Criminal',
        'Business',
        'Property',
        'Public Order',
        'Environmental',
        'Administrative',
        'Other'
    },

    -- MDT Integration
    MDTIntegration = {
        enabled = true,
        resource = 'pf-policemdt', -- your MDT resource name
        syncOnPublish = true,
        syncOnUpdate = true,
        syncOnRepeal = true
    }
}

-- =====================================================
-- CIVILIANS / IDENTITY MANAGEMENT
-- =====================================================

Config.Civilians = {
    -- When true, the civilian profile will pull records/photos from pf-policemdt tables.
    PfPoliceMdt = true,
    -- Use your active MDT resource name. Default points at your DEV resource.
    PoliceMdtResource = 'pf-policemdt-DEV'
}

-- =====================================================
-- LICENSES AND PERMITS
-- =====================================================

Config.Licenses = {
    -- Citizen licenses
    CitizenTypes = {
        { type = 'drivers_license', label = 'Drivers License', fee = 500, duration = 0 },
        { type = 'firearms_license', label = 'Firearms License', fee = 2000, duration = 2592000 }, -- 30 days
        { type = 'hunting_license', label = 'Hunting License', fee = 750, duration = 2592000 },
        { type = 'fishing_license', label = 'Fishing License', fee = 300, duration = 2592000 },
        { type = 'work_permit', label = 'Work Permit', fee = 1000, duration = 7776000 }, -- 90 days
        { type = 'concealed_carry', label = 'Concealed Carry Permit', fee = 3500, duration = 5184000 }, -- 60 days
        { type = 'pilots_license', label = 'Pilots License', fee = 5000, duration = 0 }
    },

    -- Business licenses
    BusinessTypes = {
        { type = 'general_business', label = 'General Business License', fee = 2500, duration = 0 },
        { type = 'restaurant', label = 'Restaurant License', fee = 5000, duration = 15552000 }, -- 180 days
        { type = 'mechanic', label = 'Mechanic Shop License', fee = 7500, duration = 15552000 },
        { type = 'dealership', label = 'Vehicle Dealership License', fee = 10000, duration = 15552000 },
        { type = 'towing', label = 'Towing License', fee = 4000, duration = 7776000 },
        { type = 'taxi', label = 'Taxi Service License', fee = 3000, duration = 7776000 },
        { type = 'bar_liquor', label = 'Bar & Liquor License', fee = 8000, duration = 15552000 },
        { type = 'nightclub', label = 'Nightclub License', fee = 12000, duration = 15552000 },
        { type = 'gun_shop', label = 'Firearms Dealer License', fee = 15000, duration = 15552000 }
    },

    -- Auto-expire checking
    CheckExpiration = true,
    ExpirationCheckInterval = 3600 -- seconds (1 hour)
}

-- =====================================================
-- UTILITIES AND SERVICES
-- =====================================================

Config.Utilities = {
    -- Utility types enabled
    EnablePower = true,
    EnableWater = true,

    -- Billing
    PowerBillAmount = 150, -- per billing cycle
    WaterBillAmount = 75, -- per billing cycle
    BillingInterval = 86400, -- seconds (1 day)

    -- Delinquency
    DelinquencyGracePeriod = 172800, -- seconds (2 days)
    AutoDisconnect = true,

    -- Houses (pfm-houses registers them through the RegisterProperty export) are billed to the house's
    -- current owner as a citizen bill (pfm-houses' GetOwnedHouses says who owns it), at most once per
    -- house and billing cycle; houses nobody owns are not billed. An unpaid bill that goes delinquent
    -- cuts that house's power while the same citizen owns it, and paying it restores the power.

    -- Integration with other scripts
    HousingIntegration = {
        enabled = true,
        resource = 'qb-houses' -- or your housing script
    },

    BusinessIntegration = {
        enabled = true,
        resource = 'pf-restaurants' -- example
    }
}

-- =====================================================
-- FINES AND BILLS
-- =====================================================

Config.Bills = {
    MaxFine = 50000, -- largest single fine (city hall terminal, tablet, computer and IssueFineImmediate)
    -- Bills an official writes by hand (the tablet's business fines go through bill:create, which only the
    -- server can call): at most MaxBill (whole dollars), only of these types, due DueDays after issue.
    MaxBill = 50000,
    ManualTypes = { 'fine' },
    DueDays = 7, -- fines not collected in person, and manual bills, are due this many days after issue
    -- Limits on what officials issue (fines and manual bills), counted from the bills table so a
    -- restart does not reset them: per official per hour, and per citizen or business per day from all
    -- officials together. 0 turns a limit off.
    FinesPerHour = 10,
    FinesPerTargetPerDay = 3,
    -- A bill payment the bank could not settle at once (still pending in the ledger) is checked again
    -- this often, and the bill credited (or the attempt dropped) once the ledger knows the outcome.
    PaymentReconcileSeconds = 60,

    -- Late fees
    -- A bill still open LateFeeInterval seconds after its due date gets LateFeePercentage % of its
    -- original amount added, once. With LateFeeMaxCount above 1 it gets another fee after each further
    -- interval, up to that many; a fee is never a share of earlier fees (no compounding). Property tax
    -- and utility bills follow the same rule as fines.
    LateFeeEnabled = true,
    LateFeePercentage = 10.00, -- % of the original amount
    LateFeeInterval = 86400, -- seconds overdue before the (next) late fee
    LateFeeMaxCount = 1, -- late fees per bill at most (1 = once)

    -- Delinquency escalation
    EscalationEnabled = true,
    EscalationDays = 7, -- days before escalation
    EscalationActions = {
        license_suspension = true,
        utility_cutoff = true,
        business_flag = true
    },

    -- Payment plans
    PaymentPlansEnabled = true,
    MinimumPaymentPlanAmount = 1000
}

-- =====================================================
-- BUSINESS OVERSIGHT
-- =====================================================

Config.Businesses = {
    -- Tracking
    TrackRevenue = true,
    TrackEmployees = true,
    TrackCompliance = true,

    -- Revenue spike detection (anti-cheat/fraud detection)
    SpikeDetection = {
        enabled = true,
        threshold = 50000, -- flag if revenue increases by this much in one day
        notifyAdmins = true
    },

    -- Compliance checks
    ComplianceChecks = {
        license_expiry = true,
        tax_delinquency = true,
        utility_delinquency = true
    },

    -- Integration with business scripts
    Integrations = {
        { resource = 'pf-restaurants', enabled = true },
        { resource = 'qb-shops', enabled = false }, -- example
    }
}

-- =====================================================
-- BUSINESS PREMISES (approved equipment slots)
-- =====================================================
-- Staff approve slots (type + position where they stand) for a registered business; its owner buys
-- equipment for a slot of the matching type. Prices are paid from the business account. `storage`
-- tells business resources which stock area the equipment enlarges (pf-restaurants: dry/fridge/freezer).
Config.Premises = {
    SlotTypes = { 'cooking_station', 'register', 'office', 'locker', 'delivery_point', 'fridge', 'freezer', 'shelf' },
    MaxSlotsPerBusiness = 40,
    MinSlotSpacing = 1.0,
    InstallRange = 5.0,
    Equipment = {
        fridge_commercial = { label = 'Commercial Fridge', slotType = 'fridge', price = 2500, model = 'prop_bar_fridge_01', storage = { area = 'fridge', capacity = 150 } },
        freezer_chest = { label = 'Chest Freezer', slotType = 'freezer', price = 3000, model = 'prop_ice_box_01', storage = { area = 'freezer', capacity = 150 } },
        shelf_dry = { label = 'Dry Goods Shelving', slotType = 'shelf', price = 800, model = 'prop_ff_shelves_01', storage = { area = 'dry', capacity = 200 } },
        register_pos = { label = 'POS Register', slotType = 'register', price = 1200, model = 'prop_till_01' },
        grill_station = { label = 'Grill Station', slotType = 'cooking_station', price = 4500, model = 'prop_bbq_5', station = { type = 'grill' } },
        fryer_station = { label = 'Deep Fryer', slotType = 'cooking_station', price = 3800, model = 'prop_cooker_03', station = { type = 'fryer' } },
        office_desk = { label = 'Office Desk', slotType = 'office', price = 600, model = 'prop_office_desk_01' },
        staff_locker = { label = 'Staff Locker', slotType = 'locker', price = 400, model = 'p_cs_locker_01' },
        delivery_bay = { label = 'Delivery Bay', slotType = 'delivery_point', price = 1500, model = 'prop_pallet_02a' },
    },
}

-- =====================================================
-- FIELD APPS (tablet and computer, through pf-devices)
-- =====================================================
-- Distances are checked on the server against the official's real position.
Config.GovApps = {
    -- a fine is collected at once only from a citizen standing this close to the official (metres);
    -- anyone else gets an unpaid fine bill to pay in the Bills app (the tablet fines only people this close)
    FineRange = 5.0,
    BusinessRange = 60.0,         -- inspections and on-site setup: this close to the registry location
    RequestSpotRange = 6.0,       -- approving a slot / delivery zone request: this close to the spot the business recorded
    RequestCooldownSeconds = 15,  -- between two City Hall requests from one player
    MaxNoteLength = 300,
    Inspections = {
        IntervalDays = 14,        -- a business is due for inspection after this long
        OverdueDays = 28,         -- and overdue after this long
        FollowUpDays = 3,         -- a failed inspection asks for a follow-up visit this many days later
    },
    -- who may post and withdraw City Hall announcements from the apps (matches pf-computer)
    AnnouncementPermission = 'laws',
    -- 'urgent' announcements also raise a breaking alert to everyone; nil = AnnouncementPermission
    UrgentAnnouncementPermission = nil,
}

-- =====================================================
-- AUDIT LOG
-- =====================================================

Config.AuditLog = {
    Enabled = true,
    RetentionDays = 90, -- keep logs for 90 days (0 = forever)
    LogActions = {
        'tax_change',
        'law_create',
        'law_update',
        'law_publish',
        'law_repeal',
        'budget_change',
        'license_issue',
        'license_suspend',
        'license_revoke',
        'utility_disconnect',
        'utility_restore',
        'bill_create',
        'bill_waive',
        'bill_refund',
        'website_update',
        'civilian_identity',
        'civilian_job',
        'staff_add',
        'staff_remove',
        'treasury_withdrawal',
        'treasury_deposit',
        'department_treasury_funding',
        'department_society_spend',
        'work_order_create',
        'work_order_complete',
        'work_order_cancel',
        'work_order_payout'
    }
}

-- =====================================================
-- NOTIFICATIONS
-- =====================================================

Config.Notifications = {
    Type = 'qb', -- qb, ox, esx, custom
    
    -- Notify government on events
    NotifyGovernment = {
        newBusiness = true,
        businessClosed = true,
        largeFine = true,
        budgetExceeded = true,
        suspiciousRevenue = true
    }
}

-- =====================================================
-- TREASURY
-- =====================================================

Config.Treasury = {
    StartingBalance = 100000,
    AllowNegative = false, -- can treasury go negative?
    LowBalanceWarning = 10000, -- notify government if below this amount
    UseSocietyAccount = true, -- sync treasury with a qb-banking job account
    SocietyAccount = 'government' -- set to 'cityhall' if you use that job/account
}

-- =====================================================
-- ACCESS CONTROL
-- =====================================================

Config.AccessControl = {
    -- Item required to access government terminal
    RequireItem = false,
    ItemName = 'government_tablet',

    -- Location-based access
    RequireLocation = false,
    AllowedLocations = {
        { coords = vector3(-544.67, -204.25, 38.22), radius = 50.0, label = 'City Hall' },
    },

    -- Job requirement
    RequireJob = true,
    AllowedJobs = { 'government' }
}

-- =====================================================
-- ANNOUNCEMENTS
-- =====================================================

Config.Announcements = {
    Enabled = true,
    MaxActiveAnnouncements = 10,
    DefaultDuration = 604800, -- 7 days
}

-- =====================================================
-- INTEGRATION HOOKS
-- =====================================================

Config.Integrations = {
    -- QBCore paycheck integration
    PaycheckTax = {
        enabled = true,
        event = 'qb-core:paycheck' -- handled via QBCore paycheck flow
    },

   -- MDT Laws sync
    MDT = {
        enabled = true,
        resource = 'pf-policemdt',
        export = 'SyncLaws' -- export function name
    },

    -- Business scripts
    Restaurants = {
        enabled = true,
        resource = 'pf-restaurants'
    }
}

-- =====================================================
-- CITY INFRASTRUCTURE SIMULATION
-- =====================================================

Config.Infrastructure = {
    SimulationIntervalMinutes = 5,

    Departments = {
        power = {
            label = 'Power Department',
            monthly_operating_budget = 150000,
            monthly_maintenance_demand = 110000
        },
        water = {
            label = 'Water Department',
            monthly_operating_budget = 100000,
            monthly_maintenance_demand = 70000
        },
        dot = {
            label = 'DOT',
            monthly_operating_budget = 120000,
            monthly_maintenance_demand = 95000
        },
        police = {
            label = 'Police Department',
            monthly_operating_budget = 200000,
            monthly_maintenance_demand = 150000
        },
        ems = {
            label = 'EMS',
            monthly_operating_budget = 160000,
            monthly_maintenance_demand = 120000
        },
        government = {
            label = 'Government',
            monthly_operating_budget = 90000,
            monthly_maintenance_demand = 50000
        },
        corrections = {
            label = 'Corrections',
            monthly_operating_budget = 140000,
            monthly_maintenance_demand = 100000
        },
        doj = {
            label = 'Department of Justice',
            monthly_operating_budget = 90000,
            monthly_maintenance_demand = 45000
        }
    },

    -- label: the name city events and the tablet apps show
    Districts = {
        hospital = { priority = 1, label = 'Pillbox Hill' },
        police_mrpd = { priority = 2, label = 'Mission Row' },
        downtown = { priority = 3, label = 'Downtown' },
        businesses = { priority = 4, label = 'Business District' },
        residential = { priority = 5, label = 'Residential Districts' },
        industrial = { priority = 6, label = 'Industrial Zone' }
    },

    Upgrades = {
        dot = {
            {
                key = 'asphalt_reserve_expansion',
                name = 'Asphalt Reserve Expansion',
                description = 'Improves road repair supply reserves and slows pothole growth.',
                cost = 60000,
                modifiers = { maintenanceDemandDelta = -8000 }
            },
            {
                key = 'emergency_repair_fleet',
                name = 'Emergency Repair Fleet',
                description = 'Adds rapid patch teams for hazardous road failures.',
                cost = 85000,
                modifiers = { maintenanceDemandDelta = -12000 }
            },
            {
                key = 'smart_signal_controller_backup',
                name = 'Smart Signal Controller Backup',
                description = 'Improves traffic light survivability under DOT strain.',
                cost = 70000,
                modifiers = { maintenanceDemandDelta = -5000 }
            },
            {
                key = 'streetlight_maintenance_contract',
                name = 'Streetlight Maintenance Contract',
                description = 'Keeps district lights operational for longer periods.',
                cost = 50000,
                modifiers = { maintenanceDemandDelta = -4500 }
            },
            {
                key = 'drainage_rehabilitation_package',
                name = 'Drainage Rehabilitation Package',
                description = 'Reduces road slip risk in degraded weather conditions.',
                cost = 65000,
                modifiers = { maintenanceDemandDelta = -7000 }
            }
        },
        power = {
            {
                key = 'transformer_redundancy',
                name = 'Transformer Redundancy',
                description = 'Adds failover transformer capacity for critical districts.',
                cost = 90000,
                modifiers = { maintenanceDemandDelta = -9000 }
            },
            {
                key = 'backup_fuel_reserve',
                name = 'Backup Fuel Reserve',
                description = 'Improves uptime in late-stage funding collapses.',
                cost = 80000,
                modifiers = { maintenanceDemandDelta = -7000 }
            },
            {
                key = 'grid_monitoring_automation',
                name = 'Grid Monitoring Automation',
                description = 'Improves fault detection and balancing.',
                cost = 75000,
                modifiers = { maintenanceDemandDelta = -6500 }
            },
            {
                key = 'emergency_turbine_retrofit',
                name = 'Emergency Turbine Retrofit',
                description = 'Extends blackout cycling uptime in critical stages.',
                cost = 110000,
                modifiers = { maintenanceDemandDelta = -12000 }
            },
            {
                key = 'critical_district_failsafe_feed',
                name = 'Critical District Failsafe Feed',
                description = 'Prioritizes hospitals and emergency infrastructure.',
                cost = 120000,
                modifiers = { maintenanceDemandDelta = -10000 }
            }
        }
    }
}

-- =====================================================
-- CIVIL SERVICES (merged from pfm-cityhall)
-- =====================================================
-- Citizen-facing city hall desk: ID card / license issuance (physical items),
-- the job center, and the driving school hookup. These were previously
-- provided by the pfm-cityhall resource, which is now deprecated.

Config.CivilServices = {
    Enabled = true,

    -- Use pfm-target interactions. Controlled by the same `setr UseTarget true`
    -- convar the rest of the server uses; false = PolyZone + [E] DrawText.
    UseTarget = GetConvar('UseTarget', 'false') == 'true',

    -- Jobs offered at the city hall job center (civilian / whitelisted-off jobs)
    AvailableJobs = {
        ['trucker'] = { label = 'Trucker', isManaged = false },
        ['taxi'] = { label = 'Taxi', isManaged = false },
        ['tow'] = { label = 'Tow Truck', isManaged = false },
        ['reporter'] = { label = 'News Reporter', isManaged = false },
        ['garbage'] = { label = 'Garbage Collector', isManaged = false },
        ['bus'] = { label = 'Bus Driver', isManaged = false },
        ['hotdog'] = { label = 'Hot Dog Stand', isManaged = false }
    },

    -- City hall desks. `licenses` are the physical documents a citizen can buy.
    -- `metadata` (optional) is the QBCore licences metadata key that must be
    -- true before the document can be purchased (e.g. 'driver', 'weapon').
    Cityhalls = {
        { -- City Hall 1
            coords = vec3(-265.0, -963.6, 31.2),
            showBlip = true,
            blipData = {
                sprite = 487,
                display = 4,
                scale = 0.65,
                colour = 0,
                title = 'City Services'
            },
            licenses = {
                ['id_card'] = {
                    label = 'ID Card',
                    cost = 50,
                },
                ['driver_license'] = {
                    label = 'Driver License',
                    cost = 50,
                    metadata = 'driver'
                },
                ['weaponlicense'] = {
                    label = 'Weapon License',
                    cost = 50,
                    metadata = 'weapon'
                },
            }
        },
    },

    -- Driving schools. `instructors` are citizenids allowed to use /drivinglicense
    -- and who receive the lesson-request email.
    DrivingSchools = {
        { -- Driving School 1
            coords = vec3(240.3, -1379.89, 33.74),
            showBlip = true,
            blipData = {
                sprite = 225,
                display = 4,
                scale = 0.65,
                colour = 3,
                title = 'Driving School'
            },
            instructors = {
                'DJD56142',
                'DXT09752',
                'SRI85140',
            }
        },
    },

    -- Interaction peds. `cityhall = true` opens the civil services menu,
    -- `drivingschool = true` requests driving lessons.
    Peds = {
        { -- City Hall Ped
            model = 'a_m_m_hasjew_01',
            coords = vec4(-262.79, -964.18, 30.22, 181.71),
            scenario = 'WORLD_HUMAN_STAND_MOBILE',
            cityhall = true,
            zoneOptions = { -- Used for when UseTarget is false
                length = 3.0,
                width = 3.0,
                debugPoly = false
            }
        },
        { -- Driving School Ped
            model = 'a_m_m_eastsa_02',
            coords = vec4(240.91, -1379.2, 32.74, 138.96),
            scenario = 'WORLD_HUMAN_STAND_MOBILE',
            drivingschool = true,
            zoneOptions = { -- Used for when UseTarget is false
                length = 3.0,
                width = 3.0
            }
        }
    }
}

-- =====================================================
-- DEBUG
-- =====================================================

Config.Debug = false -- Enable debug prints

-- District power in the world. Each GTA zone code (GetNameOfZone) belongs to one
-- government district. When the simulation says that district has no power, players
-- standing in it see the street and building lights go out. Zones not listed (the
-- county) are never cut. Admin /blackout from pfm-weathersync still works on its own.
Config.InfrastructureWorld = {
    Enabled = true,
    PublishSeconds = 10,
    ZoneDistricts = {
        hospital = { 'PBOX' },
        police_mrpd = { 'SKID', 'LEGSQU' },
        downtown = { 'DOWNT', 'DTVINE', 'TEXTI', 'ALTA', 'BURTON', 'HAWICK' },
        businesses = { 'ROCKF', 'DELPE', 'VESP', 'KOREAT', 'MORN', 'VINE', 'WVINE', 'EAST_V' },
        residential = { 'DAVIS', 'RANCHO', 'STRAW', 'CHAMH', 'MIRR', 'RICHM', 'VCANA', 'BEACH', 'DELBE', 'LMESA', 'MURRI' },
        industrial = { 'CYPRE', 'ELYSIAN', 'TERMINA', 'BANNING', 'EBURO', 'AIRP', 'LOSPUER' }
    }
}

-- Business loans (server/loans.lua): each due date adds interest (interest_rate % of what is left)
-- and an installment; auto-pay loans pay it from the business account. Unpaid installments count
-- as missed payments; after DefaultAfterMissed the loan defaults and the business is marked
-- non-compliant (and closed, if CloseBusinessOnDefault).
Config.Loans = {
    Enabled = true,
    CheckMinutes = 5,
    InstallmentPercent = 10,   -- of the principal, per payment interval
    MinInstallment = 100,
    DefaultAfterMissed = 3,
    CloseBusinessOnDefault = false,
}

-- =====================================================
-- MUNICIPAL WORK ORDERS (server/workorders.lua, batch 15)
-- =====================================================
-- Real maintenance jobs made from the infrastructure state: a district whose potholes, lights or
-- backlog cross a threshold gets orders at a site of that district; some city events (storms,
-- store robberies, races) leave litter or graffiti where they happened. A worker claims one unit,
-- works it on site (server positions, sampled), reports it, and each unit moves the district's
-- saved state. Community service (pf-justice) claims units through the exports; staff and listed
-- jobs are paid per unit from the department's society account, community service is not.
Config.WorkOrders = {
    Enabled = true,
    ClaimSeconds = 600,              -- a claim not reported within this time expires (unit freed)
    SampleSeconds = 5,               -- how often claimants' server positions are sampled
    SweepSeconds = 60,               -- expiry of claims and orders, payouts the bank settles late
    MaxOpenPerDistrict = 3,          -- open orders per district, whatever made them
    MaxActiveClaimsPerCitizen = 1,
    DefaultLifetimeHours = 48,
    MaxLifetimeHours = 168,
    MaxUnits = 20,
    MaxRadius = 60.0,                -- metres; the site radius of one order
    SiteTolerance = 2.0,             -- metres added to the radius (server position jitter)
    MaxPayPerUnit = 2000,
    MaxPayAttempts = 10,             -- ledger attempts (numbered keys) before a payout is given up
    PayRetrySeconds = 300,
    StaffPermission = 'utilities',   -- government staff with this permission may claim units
    -- other jobs that may claim units of these kinds (on duty), paid like staff
    ClaimJobs = {
        garbage = { 'litter' },
    },
    -- seconds a worker must stay inside the site radius (out of a vehicle) for one unit
    MinUnitSeconds = {
        litter = 60, graffiti = 90, park = 90, landscaping = 120, public_building = 120,
        pothole = 150, streetlight = 120, sign = 90,
    },
    KindLabels = {
        litter = 'Litter pick-up', graffiti = 'Graffiti removal', park = 'Park upkeep',
        landscaping = 'Landscaping', public_building = 'Public building upkeep', pothole = 'Pothole repair',
        streetlight = 'Streetlight repair', sign = 'Signal and sign repair',
    },
    -- the largest effect one order may carry (whole order, not per unit)
    MaxEffect = {
        pothole_density = 30, street_light_health = 40, traffic_light_health = 40, road_condition = 30,
        maintenance_backlog = 5000,
    },
    -- district thresholds read every infrastructure tick; one open order per rule and district.
    -- delta is the whole order's effect, split over its units. pay = per unit, from that budget
    -- department's society account (Config.Budgets.LinkedSocietyAccounts).
    Thresholds = {
        { id = 'potholes', field = 'pothole_density', above = 20, kinds = { 'pothole' }, units = 3, delta = -6, pay = { amount = 120, from = 'dot' } },
        { id = 'roads', field = 'road_condition', below = 60, kinds = { 'pothole' }, units = 3, delta = 6, pay = { amount = 120, from = 'dot' } },
        { id = 'streetlights', field = 'street_light_health', below = 70, kinds = { 'streetlight' }, units = 2, delta = 10, pay = { amount = 110, from = 'dot' } },
        { id = 'signals', field = 'traffic_light_health', below = 70, kinds = { 'sign' }, units = 2, delta = 10, pay = { amount = 110, from = 'dot' } },
        { id = 'backlog', field = 'maintenance_backlog', above = 1000, kinds = { 'litter', 'park', 'landscaping', 'public_building' }, units = 3, delta = -600, pay = { amount = 90, from = 'government' } },
    },
    -- pf-services city events that leave work behind, at the event's own position
    FromEvents = {
        -- severe weather is city-wide (pfm-weathersync sends no position): storm debris goes to a
        -- district site (the event's district, else the district with the fewest open orders)
        ['weather.severe'] = { kind = 'litter', units = 3, field = 'maintenance_backlog', delta = -450, radius = 35.0, atDistrictSite = true, pay = { amount = 90, from = 'government' } },
        ['crime.robbery.store'] = { kind = 'graffiti', units = 2, field = 'maintenance_backlog', delta = -300, radius = 20.0, pay = { amount = 90, from = 'government' } },
        ['race.finished'] = { kind = 'litter', units = 2, field = 'maintenance_backlog', delta = -300, radius = 30.0, pay = { amount = 90, from = 'government' } },
    },
    EventMaxDistance = 1500.0,       -- an event without a district joins the district of the nearest site within this
    -- work sites per district (Config.Infrastructure.Districts). kinds: what can be done there.
    -- Positions are public places of each district; check each spot in game and move it if needed.
    Sites = {
        hospital = {
            { label = 'Pillbox Medical forecourt', x = 296.0, y = -590.0, z = 43.1, r = 30.0, kinds = { 'litter', 'public_building', 'streetlight', 'sign' } },
            { label = 'Pillbox Hill streets', x = 238.0, y = -700.0, z = 35.6, r = 40.0, kinds = { 'pothole', 'streetlight', 'sign', 'litter' } },
        },
        police_mrpd = {
            { label = 'Legion Square', x = 195.2, y = -933.9, z = 30.7, r = 40.0, kinds = { 'park', 'landscaping', 'litter', 'graffiti' } },
            { label = 'Mission Row', x = 407.0, y = -979.0, z = 29.3, r = 35.0, kinds = { 'pothole', 'streetlight', 'sign', 'public_building' } },
            { label = 'Skid Row', x = 440.0, y = -1050.0, z = 29.2, r = 35.0, kinds = { 'litter', 'graffiti', 'pothole' } },
        },
        downtown = {
            { label = 'Textile City', x = 425.6, y = -806.2, z = 29.5, r = 35.0, kinds = { 'litter', 'graffiti', 'pothole', 'sign' } },
            { label = 'Clinton Avenue', x = 373.9, y = 326.8, z = 103.6, r = 35.0, kinds = { 'litter', 'streetlight', 'sign', 'landscaping' } },
            { label = 'Burton', x = -362.0, y = -132.0, z = 38.7, r = 40.0, kinds = { 'pothole', 'streetlight', 'public_building' } },
        },
        businesses = {
            { label = 'Rockford Hills shops', x = -709.9, y = -153.1, z = 37.4, r = 40.0, kinds = { 'landscaping', 'litter', 'streetlight', 'sign' } },
            { label = 'Little Seoul', x = -707.4, y = -914.3, z = 19.2, r = 35.0, kinds = { 'litter', 'graffiti', 'pothole' } },
            { label = 'Vinewood Boulevard', x = 285.0, y = 185.0, z = 104.4, r = 40.0, kinds = { 'litter', 'public_building', 'sign', 'streetlight' } },
        },
        residential = {
            { label = 'Davis Avenue', x = -48.5, y = -1757.5, z = 29.4, r = 35.0, kinds = { 'litter', 'graffiti', 'pothole', 'streetlight' } },
            { label = 'Grove Street', x = 100.0, y = -1940.0, z = 20.8, r = 40.0, kinds = { 'litter', 'graffiti', 'landscaping', 'park' } },
            { label = 'Mirror Park', x = 1163.4, y = -323.8, z = 69.2, r = 40.0, kinds = { 'park', 'landscaping', 'sign', 'pothole' } },
        },
        industrial = {
            { label = 'Cypress Flats', x = 800.0, y = -2200.0, z = 29.4, r = 45.0, kinds = { 'pothole', 'litter', 'streetlight' } },
            { label = 'Elysian Island', x = 210.0, y = -3100.0, z = 5.8, r = 45.0, kinds = { 'pothole', 'sign', 'litter' } },
            { label = 'LSIA terminal', x = -1037.0, y = -2737.0, z = 20.2, r = 40.0, kinds = { 'public_building', 'landscaping', 'litter', 'sign' } },
        },
    },
    -- caller allowlists (architecture 3.4): GetInvokingResource() per export; pf-government itself
    -- always passes; '*' is an open read
    Callers = {
        CreateWorkOrder = { ['pf-services'] = true, ['pfm-adminmenu'] = true },
        ClaimWorkOrder = { ['pf-justice'] = true },
        ReportWorkUnit = { ['pf-justice'] = true },
        ReleaseWorkClaim = { ['pf-justice'] = true },
        CancelWorkOrder = { ['pfm-adminmenu'] = true },
        ListWorkOrders = '*',
        GetWorkOrder = '*',
    },
    -- only these resources may claim units for community service (the pf-justice order owner)
    CsCallers = { ['pf-justice'] = true },
}

-- =====================================================
-- DEPARTMENTS (server/departments/*, batch 15 unit 15I; read there)
-- =====================================================
-- Which department a job belongs to, the qualifications each grade has without a granted
-- certification (so every action works on a live server before anyone is certified), who may
-- grant them, and the callers of the department exports.
Config.Departments = {
    Enabled = true,
    -- job -> department id (GetDepartmentOf)
    Jobs = {
        police = 'police',
        ambulance = 'ems',
        corrections = 'corrections',
        doj = 'doj',
        judge = 'doj',
        government = 'government',
    },
    Labels = {
        police = 'Police Department', ems = 'Emergency Medical Services', corrections = 'Department of Corrections',
        doj = 'Department of Justice', government = 'City Government', dot = 'Department of Transportation',
    },
    -- every qualification a department may grant (label; dept that owns it)
    Qualifications = {
        patrol = { label = 'Patrol officer', dept = 'police' },
        traffic = { label = 'Traffic enforcement', dept = 'police' },
        fto = { label = 'Field training officer', dept = 'police' },
        detective = { label = 'Detective', dept = 'police' },
        evidence_tech = { label = 'Evidence technician', dept = 'police' },
        lab_tech = { label = 'Crime lab technician', dept = 'police' },
        k9 = { label = 'K9 handler', dept = 'police' },
        swat = { label = 'Tactical unit', dept = 'police' },
        emr = { label = 'Emergency medical responder', dept = 'ems' },
        emt = { label = 'EMT', dept = 'ems' },
        paramedic = { label = 'Paramedic', dept = 'ems' },
        nurse = { label = 'Nurse', dept = 'ems' },
        physician = { label = 'Physician', dept = 'ems' },
        surgeon = { label = 'Surgeon', dept = 'ems' },
        corrections_officer = { label = 'Corrections officer', dept = 'corrections' },
        transport = { label = 'Prisoner transport', dept = 'corrections' },
        intake = { label = 'Intake and booking', dept = 'corrections' },
        court_clerk = { label = 'Court clerk', dept = 'doj' },
        prosecutor = { label = 'Prosecutor', dept = 'doj' },
        public_defender = { label = 'Public defender', dept = 'doj' },
        probation_officer = { label = 'Probation officer', dept = 'doj' },
        magistrate = { label = 'Magistrate', dept = 'doj' },
        judge = { label = 'Judge', dept = 'doj' },
        cs_supervisor = { label = 'Community service supervisor', dept = 'government' },
    },
    -- Implied[job][grade] = the full list for that grade (no inheritance between grades). A grade
    -- missing here implies nothing. Grades must match pfm-core shared/jobs.lua.
    Implied = {
        police = {
            [0] = { 'patrol' },
            [1] = { 'patrol', 'traffic', 'evidence_tech' },
            [2] = { 'patrol', 'traffic', 'evidence_tech', 'fto' },
            [3] = { 'patrol', 'traffic', 'evidence_tech', 'fto', 'detective' },
            [4] = { 'patrol', 'traffic', 'evidence_tech', 'fto', 'detective' },
        },
        ambulance = {
            [0] = { 'emr' },
            [1] = { 'emr', 'emt' },
            [2] = { 'emr', 'emt', 'paramedic', 'nurse', 'physician' },
            [3] = { 'emr', 'emt', 'paramedic', 'nurse', 'physician', 'surgeon' },
            [4] = { 'emr', 'emt', 'paramedic', 'nurse', 'physician', 'surgeon' },
        },
        corrections = {
            [0] = { 'corrections_officer' },
            [1] = { 'corrections_officer', 'intake' },
            [2] = { 'corrections_officer', 'intake', 'transport' },
            [3] = { 'corrections_officer', 'intake', 'transport' },
            [4] = { 'corrections_officer', 'intake', 'transport' },
            [5] = { 'corrections_officer', 'intake', 'transport' },
        },
        -- doj grades (15H): 0 clerk, 1 prosecutor, 2 public defender, 3 probation officer, 4 chief
        doj = {
            [0] = { 'court_clerk' },
            [1] = { 'prosecutor' },
            [2] = { 'public_defender' },
            [3] = { 'probation_officer', 'cs_supervisor' },
            [4] = { 'court_clerk', 'prosecutor', 'probation_officer', 'cs_supervisor' },
        },
        -- judge grades (15H): 0 magistrate, 1 judge, 2 chief judge
        judge = {
            [0] = { 'magistrate' },
            [1] = { 'magistrate', 'judge' },
            [2] = { 'magistrate', 'judge' },
        },
        government = {
            [0] = { 'cs_supervisor' },
        },
    },
    -- the lowest grade of a department's jobs that may grant and revoke its qualifications
    ManagerGrade = { police = 3, ambulance = 3, corrections = 4, doj = 4, judge = 2, government = 3 },
    -- force an incarcerated employee off duty (pf-justice IsIncarcerated; owner decision D1)
    ForceOffDutyWhenIncarcerated = true,
    AuditRetentionDays = 180,
    ShiftRetentionDays = 180,
    -- caller allowlists (architecture 3.4); reads not listed are open
    Callers = {
        GrantQualification = { ['pf-policemdt-DEV'] = true, ['pf-emsmdt'] = true },
        RevokeQualification = { ['pf-policemdt-DEV'] = true, ['pf-emsmdt'] = true },
        ListShifts = { ['pf-policemdt-DEV'] = true, ['pf-emsmdt'] = true, ['pfm-prison'] = true, ['pf-justice'] = true },
        LogDepartmentAudit = {
            ['pf-policemdt-DEV'] = true, ['pf-emsmdt'] = true, ['pfm-policejob'] = true, ['pf-ambulancejob'] = true,
            ['pfm-prison'] = true, ['pf-justice'] = true,
        },
    },
}

return Config
