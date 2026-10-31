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
    [3] = { name = 'Deputy Mayor', permissions = { 'laws', 'taxes', 'budgets', 'licenses', 'utilities', 'fines', 'staff', 'businesses', 'audit', 'events' } },
    [2] = { name = 'Treasurer', permissions = { 'budgets', 'taxes', 'fines', 'audit', 'businesses' } },
    [1] = { name = 'Clerk', permissions = { 'licenses', 'fines', 'audit' } },
    [0] = { name = 'Utility Manager', permissions = { 'utilities', 'audit' } }
}

-- Permission definitions
-- Available permissions: laws, taxes, budgets, licenses, utilities, fines, staff, businesses, audit, dashboard, settings,
-- civilians (edit a citizen's identity, job, vehicles and criminal record; only 'all' has it by default)
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
        supplies = { min = 0.00, max = 20.00 }
    },

    -- Default tax types (auto-seeded on startup)
    Defaults = {
        { type = 'income', rate = 15.00, min = 0.00, max = 50.00, description = 'Income tax on paychecks and job payments' },
        { type = 'business', rate = 10.00, min = 0.00, max = 30.00, description = 'Business revenue tax' },
        { type = 'property_transfer', rate = 5.00, min = 0.00, max = 20.00, description = 'Property purchase/transfer tax' },
        { type = 'vehicle_registration', rate = 500.00, min = 0.00, max = 5000.00, description = 'Vehicle registration fee (flat)' },
        { type = 'vehicle_purchase', rate = 8.00, min = 0.00, max = 20.00, description = 'Vehicle purchase tax' },
        { type = 'sales', rate = 8.50, min = 0.00, max = 50.00, description = 'Sales tax on transactions' },
        { type = 'supplies', rate = 6.00, min = 0.00, max = 20.00, description = 'Business supplies purchase tax' }
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
        interval = 30, -- minutes between auto collection runs
        property_tax_frequency = 604800, -- seconds (7 days)
        business_tax_frequency = 86400, -- seconds (1 day)
    }
}

-- =====================================================
-- BUDGET SYSTEM
-- =====================================================

Config.Budgets = {
    AutoReset = true,
    PaychecksPerMonth = 30,

    Defaults = {
        police = 200000,
        ems = 160000,
        dot = 120000,
        power = 150000,
        water = 100000,
        government = 90000
    },

    LinkedSocietyAccounts = {
        police = 'police',
        ems = 'ambulance',
        dot = 'dot',
        power = 'power',
        water = 'water',
        government = 'government'
    },

    SalaryTrackedJobs = {
        police = 'police',
        ems = 'ambulance'
    },

    Planning = {
        EmergencyBufferPercent = 0.10,
        EquipmentPerEmployee = {
            police = 900,
            ems = 700
        },
        FleetPerEmployee = {
            police = 550,
            ems = 500
        },
        FacilityBase = {
            police = 12000,
            ems = 10000,
            dot = 9000,
            power = 18000,
            water = 12000,
            government = 7000
        }
    },

    DepartmentNames = {
        police = 'Police Department',
        ems = 'Emergency Medical Services',
        dot = 'Department of Transportation',
        power = 'Power Department',
        water = 'Water Department',
        government = 'Government Operations'
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
    -- Late fees
    MaxFine = 50000, -- largest single fine (city hall terminal and IssueFineImmediate)
    LateFeeEnabled = true,
    LateFeePercentage = 10.00, -- % added after due date
    LateFeeInterval = 86400, -- seconds between late fee applications

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
    FineRange = 5.0,              -- a citizen can only be fined by an official this close (metres)
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
        'staff_add',
        'staff_remove',
        'treasury_withdrawal',
        'treasury_deposit'
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

return Config
