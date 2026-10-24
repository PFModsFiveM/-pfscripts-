Config = {}

-- =====================================================
-- CORE SETTINGS
-- =====================================================

Config.Framework = 'qbcore' -- qbcore or esx
Config.FrameworkResourceName = 'qb-core' -- name of your framework resource

-- =====================================================
-- GOVERNMENT JOB SETTINGS
-- =====================================================

Config.GovernmentJob = 'government'

-- Role-based permissions (grade => role name)
Config.Roles = {
    [4] = { name = 'Mayor', permissions = { 'all' } },
    [3] = { name = 'Deputy Mayor', permissions = { 'laws', 'taxes', 'budgets', 'licenses', 'utilities', 'fines', 'staff', 'businesses', 'audit' } },
    [2] = { name = 'Treasurer', permissions = { 'budgets', 'taxes', 'fines', 'audit', 'businesses' } },
    [1] = { name = 'Clerk', permissions = { 'licenses', 'fines', 'audit' } },
    [0] = { name = 'Utility Manager', permissions = { 'utilities', 'audit' } }
}

-- Permission definitions
-- Available permissions: laws, taxes, budgets, licenses, utilities, fines, staff, businesses, audit, dashboard, settings
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
    ResetInterval = 604800, -- seconds (7 days = weekly)
    AutoReset = true,
    
    -- Default budgets (can be changed in-game)
    Defaults = {
        police = 50000,
        ems = 40000,
        dot = 25000,
        utilities = 15000,
        government = 30000
    },

    -- Department names mapping
    DepartmentNames = {
        police = 'Police Department',
        ems = 'Emergency Medical Services',
        dot = 'Department of Transportation',
        utilities = 'Utilities & Public Works',
        government = 'Government Operations'
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
    SnapshotIntervalMinutes = 60,
    SimulationIntervalMinutes = 5,
    UpkeepIntervalSeconds = 604800,

    Support = {
        Enabled = true,
        MinAveragePlayers = 15,
        CushionPercent = 0.20,
        MaxCushionAmount = 30000,
        MaxCoveragePercent = 0.40,
        CoversUpgrades = false
    },

    DepartmentPriority = {
        'power',
        'water',
        'ems',
        'police',
        'dot',
        'fire',
        'government'
    },

    DepartmentJobMap = {
        police = 'police',
        ems = 'ambulance',
        fire = 'fire'
    },

    Departments = {
        power = {
            label = 'Power Department',
            baseline_upkeep = 10000,
            reserve_max = 50000,
            reserve_start = 25000,
            upgrade_upkeep_multiplier = 0.20,
            degrade_rate = 3.00,
            recover_rate = 1.50,
            supports_districts = true
        },
        water = {
            label = 'Water Department',
            baseline_upkeep = 8000,
            reserve_max = 30000,
            reserve_start = 15000,
            upgrade_upkeep_multiplier = 0.15,
            degrade_rate = 2.50,
            recover_rate = 1.50,
            supports_districts = true
        },
        dot = {
            label = 'DOT',
            baseline_upkeep = 12000,
            reserve_max = 25000,
            reserve_start = 10000,
            upgrade_upkeep_multiplier = 0.10,
            degrade_rate = 2.00,
            recover_rate = 1.25,
            supports_districts = true
        },
        police = {
            label = 'Police Department',
            baseline_upkeep = 0,
            reserve_max = 40000,
            reserve_start = 15000,
            degrade_rate = 2.50,
            recover_rate = 1.25
        },
        ems = {
            label = 'EMS',
            baseline_upkeep = 0,
            reserve_max = 30000,
            reserve_start = 10000,
            degrade_rate = 2.25,
            recover_rate = 1.25
        },
        fire = {
            label = 'Fire Department',
            baseline_upkeep = 0,
            reserve_max = 30000,
            reserve_start = 10000,
            degrade_rate = 2.25,
            recover_rate = 1.25
        },
        government = {
            label = 'Government',
            baseline_upkeep = 5000,
            reserve_max = 20000,
            reserve_start = 5000,
            degrade_rate = 1.50,
            recover_rate = 1.00
        }
    },

    Districts = {
        hospital = { priority = 1 },
        police_mrpd = { priority = 2 },
        downtown = { priority = 3 },
        businesses = { priority = 4 },
        residential = { priority = 5 },
        industrial = { priority = 6 }
    },

    Power = {
        FlickerIntervalSeconds = 120,
        FlickerChanceStage3 = 20,
        FlickerChanceStage4 = 45
    },

    Water = {
        PressureLossPerStage = 25,
        ContaminationChanceStage4 = 10
    },

    DOT = {
        PotholeChanceStage3 = 10,
        PotholeChanceStage4 = 25,
        TirePopChanceStage4 = 8,
        SlipMultiplierStage4 = 1.25
    },

    Payroll = {
        PaycheckMultiplierMin = 0.50,
        PaycheckMultiplierMax = 2.00,
        PaychecksPerWeek = 1,
        EquipmentOverheadPerEmployee = {
            police = 250,
            ems = 200,
            fire = 220
        },
        FleetOverheadPerEmployee = {
            police = 150,
            ems = 125,
            fire = 175
        },
        FacilityOverhead = {
            police = 2500,
            ems = 2500,
            fire = 2500
        }
    }
}

-- =====================================================
-- DEBUG
-- =====================================================

Config.Debug = false -- Enable debug prints

return Config
