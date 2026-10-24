Config = Config or {}

-- ============================================================================
-- LOCALE SYSTEM
-- ============================================================================
Config.Locale = 'en' -- Available: en, pl, es, fr, de (add more in locales folder)

-- ============================================================================
-- DEBUG (ALWAYS ON TOP)
-- ============================================================================
Config.Debug = false -- Set to true to see all debug notifications and console logs

-- ============================================================================
-- SQL AUTO-INJECTION
-- ============================================================================
Config.AutoInjectSQL = true -- Set to true to automatically import database tables on resource start

-- Tax settings for POS (additive, non-breaking)
Config.UseGovernmentTax = false -- Set true to pull tax from pf-government if available

-- POS charges (server/register_pos.lua). Money moves through the pfm-banking ledger: the customer pays,
-- the shop's bank account (society) receives the sale, and the mechanic's commission is paid out of it.
Config.POS = {
    MaxChargeDistance = 10.0,   -- metres between mechanic and customer (server-checked; needs OneSync)
    CommissionRate = 0.20,      -- share of the total paid to the charging mechanic from the shop's takings
    ConfirmSeconds = 60,        -- how long the customer has to accept the bill on their screen
}
Config.DefaultTax = 0.08        -- Fallback/default tax rate (8%)

-- ============================================================================
-- GARAGE SYSTEM COMPATIBILITY & GENERAL SETTINGS
-- ============================================================================
-- Supported values:
--   'qb-garages'  = QBCore's default garage system (default)
--   'cd_garages'  = Codesign's cd_garages (https://docs.codesign.pro/paid-scripts/garage)
-- Add more supported garage scripts here as needed.
Config.GarageSystem = 'qb-garages' -- or 'cd_garages'
Config.MenuSystem   = 'qb-menu'          -- 'qb-menu' or 'ox_lib'

-- Jobs allowed to use mechanic items (in addition to 'mechanic')
Config.AllowedJobs = {
    'mechanic',
    'mechanic2',
    'mechanic3',
    'bennys',
    'beeker',
    -- Add more jobs here as needed
}

-- Items that ANYONE can use (no job requirement)
Config.PublicItems = {
    'repair_kit',
    'tint_supplies', -- renamed from tint
}

-- Items that DON'T require a toolbox
Config.NoToolboxRequired = {
    -- Only UI/tablet items remain exempt
    'mechanic_tablet',
}

-- ============================================================================
-- WEAR RATE TUNING
-- ============================================================================
Config.WearRates = {
    -- Brake wear multipliers
    brakes = {
        baselineRandomMin = 0.01,      -- Minimum random wear per tick when moving
        baselineRandomMax = 0.05,      -- Maximum random wear per tick when moving
        speedExtraStartMPH = 40,       -- Speed threshold where extra wear begins
        speedExtraScale = 0.004,       -- Wear per MPH above threshold
        sustainedBrakeInterval = 5000, -- MS holding brake for bonus wear
        sustainedBonus = 0.40,         -- Extra wear for sustained braking
        steeringAngleWearStart = 12.0, -- Degrees where cornering wear begins
        steeringAngleScale = 0.02,     -- Wear per degree above threshold
        handbrakePerTick = 0.35,       -- Wear per tick when handbrake is held
        burnoutExtra = 2.50,           -- Extra wear during burnouts (W+S)
        heatIncreasePerWear = 14,      -- Heat units gained per 1% wear
        heatDecayPerTick = 18,         -- Heat units lost per tick when not braking
        heatWearScale = 0.0009,        -- Extra wear = heat * scale
        downhillDecelThreshold = -0.65, -- Forward deceleration threshold
        downhillBonus = 0.30,          -- Extra wear on steep downhills
    },
    
    -- Radiator wear
    radiator = {
        bodyDamageScale = 0.08,        -- Wear per tick when body < 80%
        collisionDamage = 1.2,         -- Damage per collision at speed
        waterIngestionRate = 0.6,      -- Damage per tick in water
    },
    
    -- Coolant consumption
    coolant = {
        speedThreshold = 80.0,         -- MPH where loss begins
        speedLossBase = 0.05,          -- Base loss above threshold
        speedLossScale = 0.008,        -- Extra loss per MPH
        tempThreshold = 110.0,         -- Engine temp where loss accelerates
        tempLossScale = 0.04,          -- Loss per degree above threshold
        radiatorDamageThreshold = 40,  -- Radiator % where loss accelerates
        radiatorLossScale = 0.02,      -- Loss based on radiator damage
        waterContamination = 0.30,     -- Loss per tick in water
    },
    
    -- Suspension & Axle
    suspension = {
        airtimeSpeedThreshold = 15.0,  -- Speed when airborne causes damage
        airtimeScale = 0.80,           -- Damage per tick airborne (scaled by speed)
        suspensionAirtimeScale = 0.60, -- Suspension-specific airtime damage
        highSpeedWear = 0.08,          -- Wear per tick above 60 MPH
        mudWear = 0.35,                -- Wear per tick in mud
    },
    
    axle = {
        mudWear = 0.25,                -- Wear per tick in mud
    },
    
    -- Spark plugs
    sparkplugs = {
        mileagePerPercent = 250.0,     -- Miles needed for 1% damage
        overheatingTempThreshold = 120.0, -- Temp where damage begins
        overheatingScale = 0.03,       -- Damage per degree above threshold
        fireDamage = 3.5,              -- Damage per tick when on fire
        misfireThreshold = 50,         -- Damage % where misfires cause extra wear
        misfireChance = 8,             -- % chance per tick to misfire
        misfireDamage = 0.50,          -- Extra damage per misfire
        oilLeakThreshold = 30,         -- Oil health % where plugs suffer
        oilLeakScale = 0.02,           -- Damage based on low oil
    },
}

-- ============================================================================
-- JOB / SOCIETY (DYNAMIC)
-- ============================================================================
-- Helper function to check if a job is a mechanic job
function Config.IsMechanicJob(jobName)
    for _, j in ipairs(Config.AllowedJobs) do if j == jobName then return true end end
    return false
end
-- Get business key for a specific job (used for database lookups)
function Config.GetBusinessKey(jobName)
    local map = { mechanic='mechanic', mechanic2='mechanic2', mechanic3='mechanic3', bennys='bennys', beeker='beeker' }
    return map[jobName] or jobName
end

-- Default branding per business (used for initial seed)
Config.BusinessBranding = {
  mechanic = { business='mechanic', name='LS Customs', primary_color='#0BA378', secondary_color='#0B2E44', logo='', tax=0.05, open=1 },
  mechanic2= { business='mechanic2', name='LS Customs #2', primary_color='#0BA378', secondary_color='#0B2E44', logo='', tax=0.05, open=1 },
  mechanic3= { business='mechanic3', name='LS Customs #3', primary_color='#0BA378', secondary_color='#0B2E44', logo='', tax=0.05, open=1 },
  bennys   = { business='bennys',   name="Benny's Original Motor Works", primary_color='#8B0000', secondary_color='#2E0000', logo='', tax=0.05, open=1 },
  beeker   = { business='beeker',   name="Beeker's Garage", primary_color='#FF8C00', secondary_color='#3D2000', logo='', tax=0.05, open=1 },
}
Config.JobName = 'mechanic'
Config.Society = 'mechanic'
Config.DEFAULT_BRANDING = Config.BusinessBranding.mechanic

-- Tablet item(s) - no longer used, tablets integrated into pf-tablet
Config.TabletItems = {}

-- ============================================================================
-- WORK ORDER LEVEL SYSTEM
-- ============================================================================
Config.WorkOrderSystem = {
    -- Job Offer Expiration Settings
    offerExpirationTime = 60,       -- Time in seconds before job offers expire (set to 0 to disable expiration)
    expirationXPPenalty = 10,       -- XP penalty when a job offer expires (only applies if expiration enabled)
    
    -- XP rewards for completing work orders
    xpPerJob = {
        easy = 25,
        medium = 50,
        hard = 100,
        expert = 150,
    },
    
    -- Level requirements and benefits
    levels = {
        {
            level = 1,
            name = "Apprentice",
            minXP = 0,
            maxOffers = 3,              -- Max simultaneous offers available
            payMultiplier = 1.0,        -- Base payout multiplier
            offerRefreshTime = 6,     -- Seconds between new offers (10 min)
            jobTypes = {"easy"},        -- Available job difficulties
        },
        {
            level = 2,
            name = "Mechanic",
            minXP = 1000,
            maxOffers = 3,
            payMultiplier = 1.15,
            offerRefreshTime = 480,     -- 8 minutes
            jobTypes = {"easy", "medium"},
        },
        {
            level = 3,
            name = "Senior Mechanic",
            minXP = 2000,
            maxOffers = 3,
            payMultiplier = 1.30,
            offerRefreshTime = 360,     -- 6 minutes
            jobTypes = {"easy", "medium", "hard"},
        },
        {
            level = 4,
            name = "Master Mechanic",
            minXP = 3000,
            maxOffers = 3,
            payMultiplier = 1.45,
            offerRefreshTime = 300,     -- 5 minutes
            jobTypes = {"easy", "medium", "hard", "expert"},
        },
        {
            level = 5,
            name = "Expert Mechanic",
            minXP = 4000,
            maxOffers = 3,
            payMultiplier = 1.5,
            offerRefreshTime = 240,     -- 4 minutes
            jobTypes = {"easy", "medium", "hard", "expert"},
        },
    },
    
    -- Vehicle spawn locations for work orders
    vehicleSpawnLocations = {
        vector4(-370.36, -21.88, 46.71, 238.65),
        vector4(-197.99, -165.9, 43.62, 175.02),
        vector4(69.99, -310.86, 46.83, 247.12),
        vector4(851.82, 73.85, 67.92, 330.07),
        vector4(1364.93, 631.55, 80.32, 313.27),
        vector4(-484.4, 269.28, 83.17, 268.7),
        vector4(153.88, 199.12, 106.3, 249.11),
        vector4(905.37, -110.84, 77.52, 242.38),
        vector4(969.96, -366.66, 45.42, 140.06),
        vector4(704.15, -547.96, 25.84, 139.47),
        vector4(19.12, -1747.02, 29.3, 170.13),
        vector4(-589.16, -1797.64, 23.02, 98.98),
        vector4(-796.19, -2427.48, 14.57, 151.82),
        vector4(-331.6, -2571.84, 6.01, 175.31),
        vector4(-229.59, -2655.15, 5.99, 184.85),
        vector4(1016.44, -3106.43, 5.9, 273.06),
        vector4(82.99, -1914.31, 20.88, 40.89),
        vector4(1041.51, -531.93, 61.32, 308.23),
        vector4(2191.61, 2205.86, 113.94, 311.1),
        vector4(2454.28, 2245.13, 48.02, 202.25),
        vector4(2198.32, 3156.59, 50.57, 343.11),
        vector4(2162.0, 3893.9, 31.89, 306.18),
        vector4(1606.73, 3869.62, 32.05, 126.12),
        vector4(1589.03, 3683.55, 34.37, 200.96),
        vector4(1129.54, 3530.19, 34.68, 94.03),
        vector4(-401.08, 4684.85, 258.59, 69.23),
        vector4(510.26, 5530.97, 776.76, 331.84),
        vector4(1527.79, 6495.04, 22.15, 252.27),
        vector4(1848.58, 4593.52, 30.98, 158.29),
        vector4(-1814.84, 2631.84, 2.9, 84.86),
        vector4(-1898.98, 2593.82, 1.11, 106.04),
        vector4(-2013.47, 2669.89, 1.07, 314.35),
        vector4(-2384.56, 1929.25, 181.8, 242.81),
        vector4(-681.91, -513.8, 25.03, 267.32),
    },
    
    -- Job type definitions
    jobDifficulties = {
        easy = {
            name = "Basic Service",
            color = "#10b981",          -- Green
            basePay = 250,
            tasks = {
                { type = "tire_repair", name = "Tire Repair", duration = 15, item = "tire_new", repairType = "tire" },
                { type = "battery_replace", name = "Battery Replacement", duration = 20, item = "carbattery", repairType = "battery" },
                { type = "oil_change", name = "Oil Change", duration = 20, item = "engine_oil", repairType = "oil" },
            }
        },
        medium = {
            name = "Standard Repair",
            color = "#3b82f6",          -- Blue
            basePay = 500,
            tasks = {
                -- Easy tasks
                { type = "tire_repair", name = "Tire Repair", duration = 15, item = "tire_new", repairType = "tire" },
                { type = "battery_replace", name = "Battery Replacement", duration = 20, item = "carbattery", repairType = "battery" },
                { type = "oil_change", name = "Oil Change", duration = 20, item = "engine_oil", repairType = "oil" },
                -- Medium tasks
                { type = "brake_pads", name = "Brake Pad Replacement", duration = 30, item = "brake_pads", repairType = "brakes" },
                { type = "air_filter", name = "Air Filter Service", duration = 25, repairType = "engine" },
                { type = "spark_plugs", name = "Spark Plug Replacement", duration = 30, item = "sparkplugs", repairType = "sparkplugs" },
                { type = "coolant_flush", name = "Coolant System Flush", duration = 40, item = "coolant", repairType = "coolant" },
                { type = "suspension", name = "Suspension Service", duration = 35, repairType = "suspension" },
            }
        },
        hard = {
            name = "Advanced Repair",
            color = "#a855f7",          -- Purple
            basePay = 900,
            tasks = {
                -- Easy tasks
                { type = "tire_repair", name = "Tire Repair", duration = 15, item = "tire_new", repairType = "tire" },
                { type = "battery_replace", name = "Battery Replacement", duration = 20, item = "carbattery", repairType = "battery" },
                { type = "oil_change", name = "Oil Change", duration = 20, item = "engine_oil", repairType = "oil" },
                -- Medium tasks
                { type = "brake_pads", name = "Brake Pad Replacement", duration = 30, item = "brake_pads", repairType = "brakes" },
                { type = "air_filter", name = "Air Filter Service", duration = 25, repairType = "engine" },
                { type = "spark_plugs", name = "Spark Plug Replacement", duration = 30, item = "sparkplugs", repairType = "sparkplugs" },
                { type = "coolant_flush", name = "Coolant System Flush", duration = 40, item = "coolant", repairType = "coolant" },
                { type = "suspension", name = "Suspension Service", duration = 35, repairType = "suspension" },
                -- Hard tasks
                { type = "transmission", name = "Transmission Service", duration = 50, item = "transmissionfluid", repairType = "transmission" },
                { type = "engine_repair", name = "Engine Repair", duration = 60, item = "engine_part", repairType = "engine" },
                { type = "exhaust_system", name = "Exhaust System Repair", duration = 45, repairType = "body" },
            }
        },
        expert = {
            name = "Expert Service",
            color = "#f59e0b",          -- Orange/Gold
            basePay = 1500,
            tasks = {
                -- Easy tasks
                { type = "tire_repair", name = "Tire Repair", duration = 15, item = "tire_new", repairType = "tire" },
                { type = "battery_replace", name = "Battery Replacement", duration = 20, item = "carbattery", repairType = "battery" },
                { type = "oil_change", name = "Oil Change", duration = 20, item = "engine_oil", repairType = "oil" },
                -- Medium tasks
                { type = "brake_pads", name = "Brake Pad Replacement", duration = 30, item = "brake_pads", repairType = "brakes" },
                { type = "air_filter", name = "Air Filter Service", duration = 25, repairType = "engine" },
                { type = "spark_plugs", name = "Spark Plug Replacement", duration = 30, item = "sparkplugs", repairType = "sparkplugs" },
                { type = "coolant_flush", name = "Coolant System Flush", duration = 40, item = "coolant", repairType = "coolant" },
                { type = "suspension", name = "Suspension Service", duration = 35, repairType = "suspension" },
                -- Hard tasks
                { type = "transmission", name = "Transmission Service", duration = 50, item = "transmissionfluid", repairType = "transmission" },
                { type = "engine_repair", name = "Engine Repair", duration = 60, item = "engine_part", repairType = "engine" },
                { type = "exhaust_system", name = "Exhaust System Repair", duration = 45, repairType = "body" },
                -- Expert tasks
                { type = "engine_rebuild", name = "Engine Rebuild", duration = 90, item = "engine_part", repairType = "engine" },
                { type = "full_restoration", name = "Full Restoration", duration = 120, item = "body_part", repairType = "body" },
                { type = "diagnostic_full", name = "Complete Diagnostic", duration = 60, repairType = "diagnostics" },
            }
        }
    },
    
    -- Vehicle types for work orders
    vehicles = {
        "futo", "sultan", "elegy", "dominator", "buffalo", "banshee", "comet",
        "kuruma", "jester", "massacro", "t20", "zentorno", "infernus", "adder",
        "carbonizzare", "coquette", "exemplar", "feltzer", "rapidgt", "schwartzer",
        "tailgater", "zion", "felon", "oracle", "sentinel", "f620", "alpha",
        "blista", "penumbra", "sentinelxs", "windsor", "baller", "cavalcade",
        "dubsta", "gresley", "huntley", "mesa", "patriot", "seminole", "serrano"
    },
    
    -- Customer names
    customerNames = {
        "John Smith", "Jane Doe", "Michael Johnson", "Sarah Williams", "Robert Brown",
        "Emily Davis", "David Miller", "Ashley Wilson", "James Moore", "Jennifer Taylor",
        "Daniel Anderson", "Jessica Thomas", "Christopher Jackson", "Amanda White", "Matthew Harris",
        "Melissa Martin", "Joshua Thompson", "Stephanie Garcia", "Andrew Martinez", "Nicole Robinson",
        "Ryan Clark", "Heather Rodriguez", "Nicholas Lewis", "Rebecca Lee", "Brandon Walker",
        "Laura Hall", "Tyler Allen", "Samantha Young", "Kevin King", "Kimberly Wright"
    },
    
    -- Work order vehicle settings
    spawnVehicleOnAccept = true,           -- Spawn vehicle when job is accepted
    deleteVehicleOnComplete = true,        -- Delete vehicle when job is completed
    useDiagnosticsForWorkOrders = true,    -- Require using diagnostics menu instead of 3D text prompt
    vehicleGodMode = true,                 -- Make vehicle invincible
    lockVehicle = true,                    -- Lock vehicle to prevent theft
    blipSprite = 446,                      -- Blip sprite (446 = repair icon)
    blipColor = 3,                         -- Blip color (3 = cyan)
    blipScale = 0.8,                       -- Blip scale
    waypointEnabled = true,                -- Show waypoint to vehicle
    requiredItems = true,                  -- Require specific items to complete job
}

-- Base pay by job type
Config.JobTypes = {
  engine     = { basePay = 450 },
  cosmetic   = { basePay = 520 },
  suspension = { basePay = 550 },
  service    = { basePay = 480 },
}

-- NPC spawns/models
Config.NPCModels = { 'sultan', 'buffalo', 'tailgater2' }
Config.NPCSpawns = {
  { coords = vector3(-372.9257, -111.5709, 38.6816), h = 69.1205 }
}

-- Receipt item(s)
Config.ReceiptItems = { 'receipt', 'paper_receipt' }

-- Paint colors
Config.PaintPalette = {
  red   = { r=200, g=20,  b=20  },
  blue  = { r=20,  g=60,  b=200 },
  green = { r=20,  g=150, b=80  },
}

-- Minimal Item->mod mapping used by client/main.lua
Config.ItemModMap = {
  bumper={1,2}, vehicle_bumper={1,2}, exhaust={4}, hood={7}, roof={10}, skirts={3}, spoiler={0},
  rims={23}, -- NEW: wheel rims use modType 23
}

-- Deduped PartRules (unique keys only)
Config.PartRules = {
  -- Repairs
  engine_part = { action='repair', type='engine',      zone='front',  max_items=5 },
  carbattery  = { action='repair', type='battery',     zone='front',  max_items=1 },
  sparkplugs  = { action='repair', type='sparkplugs',  zone='front',  max_items=8 },
  engine_oil  = { action='repair', type='oil',         zone='front',  radius=4.0, max_items=1 },
  oil_filter  = { action='repair', type='oil_filter',  zone='front',  radius=4.0, max_items=1 },
  brake_pads  = { action='repair', type='brakes',      zone='wheel',  max_items=4 },
  susp_arm    = { action='repair', type='suspension',  zone='wheel',  max_items=4 },
  axleparts   = { action='repair', type='axle',        zone='under',  max_items=4 },
  -- Cosmetics/perf
  bumper={ action='setMod', zone='exterior' }, vehicle_bumper={ action='setMod', zone='exterior' },
  exhaust={ action='setMod', zone='exterior' }, hood={ action='setMod', zone='exterior' },
  roof={ action='setMod', zone='exterior' }, skirts={ action='setMod', zone='exterior' },
  spoiler={ action='setMod', zone='exterior' },
  -- Upgrades
  engine1={ action='upgrade', modType=11, modIndex=0, zone='front' },
  engine2={ action='upgrade', modType=11, modIndex=1, zone='front' },
  engine3={ action='upgrade', modType=11, modIndex=2, zone='front' },
  engine4={ action='upgrade', modType=11, modIndex=3, zone='front' },
  engine5={ action='upgrade', modType=11, modIndex=4, zone='front' },
  brakes1={ action='upgrade', modType=12, modIndex=0, zone='wheel' },
  brakes2={ action='upgrade', modType=12, modIndex=1, zone='wheel' },
  brakes3={ action='upgrade', modType=12, modIndex=2, zone='wheel' },
  transmission1={ action='upgrade', modType=13, modIndex=0, zone='under' },
  transmission2={ action='upgrade', modType=13, modIndex=1, zone='under' },
  transmission3={ action='upgrade', modType=13, modIndex=2, zone='under' },
  suspension1={ action='upgrade', modType=15, modIndex=0, zone='under' },
  suspension2={ action='upgrade', modType=15, modIndex=1, zone='under' },
  suspension3={ action='upgrade', modType=15, modIndex=2, zone='under' },
  suspension4={ action='upgrade', modType=15, modIndex=3, zone='under' },
  armor1={ action='upgrade', modType=16, modIndex=0, zone='exterior' },
  armor2={ action='upgrade', modType=16, modIndex=1, zone='exterior' },
  armor3={ action='upgrade', modType=16, modIndex=2, zone='exterior' },
  armor4={ action='upgrade', modType=16, modIndex=3, zone='exterior' },
  armor5={ action='upgrade', modType=16, modIndex=4, zone='exterior' },
  turbo={ action='turbo', modType=18, zone='front' },
}

-- Action timing used by client/main.lua
Config.ActionTimes = {
  inspection=10000, setMod=4500, oil=5500, engine=5500, body=5000, brake=6500, susp=8000, tire=7000, paint=9000,
}

-- ============================================================================
-- WEAR TRIGGER THRESHOLDS (USED BY damage.lua ADVANCED WEAR)
-- Added to prevent nil table access and allow easy tuning.
-- ============================================================================
if not Config.WearTriggers then
    Config.WearTriggers = {
        FrontalBodyDropPct = 3.0,      -- % body health drop (per check) treated as frontal impact
        OverheatTemp        = 115.0,   -- Temp where mild overheating wear begins
        SevereOverheatTemp  = 130.0,   -- Temp causing severe engine wear
        OilStarvationHealth = 25,      -- Oil % (health) below which starvation damage applies
        CoolantCritical     = 30,      -- Coolant % (health) below which engine takes damage
        HighRPM             = 0.92,    -- Normalized RPM considered abusive at (mph < 4)
        DriftLateralSpeed   = 4.5,     -- Lateral velocity threshold for drift wear
        JumpMinSpeed        = 25.0,    -- Min MPH while airborne to apply suspension/axle hit
        HardBrakeMPH        = 55.0,    -- MPH threshold for extra brake wear when braking
    }
end

-- ============================================================================
-- PREVIEW RECEIPT SYSTEM
-- ============================================================================
Config.PreviewReceipt = {
    enabled = true,                     -- Enable/disable receipt generation
    itemName = 'preview_receipt',       -- Item to give (must exist in qb-core/shared/items.lua)
    webhookURL = '',                    -- Discord webhook URL (leave empty to disable)
    webhookColor = 3447003,             -- Embed color (decimal, default blue)
    webhookTitle = '🔧 Vehicle Preview Receipt',
    webhookFooter = 'Preview System',
    renderMenu = true,                  -- NEW: when using the item, open qb-menu showing changes
    menuTitle = 'Preview Receipt'       -- NEW: qb-menu title
}

-- ============================================================================
-- ROLLING COAL SYSTEM
-- ============================================================================
Config.RollingCoal = {
    enabled = true,
    DieselClasses = { 10, 11, 12, 17, 19, 20 },
    
    -- Always diesel (even if class doesn't match)
    ForceDieselModels = {
        -- Trucks
        [`bison`] = true,
        [`bison2`] = true,
        [`bison3`] = true,
        [`bobcatxl`] = true,
        [`bobcat`] = true,
        [`sadler`] = true,
        [`sadler2`] = true,
        [`sandking`] = true,
        [`sandking2`] = true,
        [`rebel`] = true,
        [`rebel2`] = true,
        [`riata`] = true,
        [`caracara`] = true,
        [`caracara2`] = true,
        [`dloader`] = true,
        [`guardian`] = true,
        [`kamacho`] = true,
        [`dubsta`] = true,
        [`dubsta2`] = true,
        [`dubsta3`] = true,
        [`granger`] = true,
        [`granger2`] = true,
        
        -- Vans & Commercial
        [`boxville`] = true,
        [`boxville2`] = true,
        [`boxville3`] = true,
        [`boxville4`] = true,
        [`boxville5`] = true,
        [`burrito`] = true,
        [`burrito2`] = true,
        [`burrito3`] = true,
        [`burrito4`] = true,
        [`burrito5`] = true,
        [`camper`] = true,
        [`journey`] = true,
        [`minivan`] = true,
        [`minivan2`] = true,
        [`rumpo`] = true,
        [`rumpo2`] = true,
        [`rumpo3`] = true,
        [`youga`] = true,
        [`youga2`] = true,
        [`youga3`] = true,
        [`gburrito`] = true,
        [`gburrito2`] = true,
        [`paradise`] = true,
        [`speedo`] = true,
        [`speedo2`] = true,
        [`speedo4`] = true,
        [`surfer`] = true,
        [`surfer2`] = true,
        
        -- Heavy Trucks
        [`mule`] = true,
        [`mule2`] = true,
        [`mule3`] = true,
        [`mule4`] = true,
        [`pounder`] = true,
        [`pounder2`] = true,
        [`stockade`] = true,
        [`stockade3`] = true,
        [`benson`] = true,
        
        -- Utility
        [`tiptruck`] = true,
        [`tiptruck2`] = true,
        [`rubble`] = true,
        [`mixer`] = true,
        [`mixer2`] = true,
        [`flatbed`] = true,
        [`towtruck`] = true,
        [`towtruck2`] = true,
        [`utillitruck`] = true,
        [`utillitruck2`] = true,
        [`utillitruck3`] = true,
        
        -- Semi Trucks / Big Rigs
        [`packer`] = true,
        [`phantom`] = true,
        [`phantom2`] = true,
        [`phantom3`] = true,
        [`hauler`] = true,
        [`hauler2`] = true,
        
        -- Military
        [`barracks`] = true,
        [`barracks2`] = true,
        [`barracks3`] = true,
        [`crusader`] = true,
        [`insurgent`] = true,
        [`insurgent2`] = true,
        [`insurgent3`] = true,
        [`technical`] = true,
        [`technical2`] = true,
        [`technical3`] = true,
        
        -- SUVs (some are diesel in real life)
        [`patriot`] = true,
        [`patriot2`] = true,
        [`mesa`] = true,
        [`mesa2`] = true,
        [`mesa3`] = true,
        [`seminole`] = true,
        [`seminole2`] = true,
        
        -- Service Vehicles
        [`biff`] = true,
        [`trash`] = true,
        [`trash2`] = true,
        [`bulldozer`] = true,
        [`cutter`] = true,
        [`dump`] = true,
        [`flatbed`] = true,
        [`mixer`] = true,
        [`mixer2`] = true,
        [`tractor`] = true,
        [`tractor2`] = true,
        [`tractor3`] = true,
        
        -- Buses
        [`bus`] = true,
        [`coach`] = true,
        [`airbus`] = true,
        [`rentalbus`] = true,
        [`tourbus`] = true,
    },
    
    -- Never diesel
    BlacklistModels = {
        [`police`] = true,
        [`police2`] = true,
        [`police3`] = true,
        [`police4`] = true,
        [`ambulance`] = true,
        [`firetruk`] = true,
    },
    
    -- Particle effect settings (from RollCoal reference)
    effectDict = "core",
    effectName = "ent_amb_generator_smoke",
    effectScale = 2.5,  -- NEW: Increased from 2.0 to 2.5 for even bigger particles
    emissionInterval = 50,
    rpmThreshold = 0.65,
    maxMph = 40.0,
    particlesPerBone = 10,  -- NEW: Number of particles per exhaust bone (1-250 recommended)
    particlesNoBone = 15,   -- NEW: Number of particles when no bones found (1-250 recommended)
    maxParticles = 250,     -- NEW: Maximum total particles allowed (safety limit)
    blackEffect = "ent_amb_generator_smoke",
    fallbackEffect = "veh_exhaust_truck_rig"
}

-- Helper: Check if vehicle is a diesel candidate
function Config.IsDieselCandidate(veh)
    if not veh or not DoesEntityExist(veh) then return false end
    
    local model = GetEntityModel(veh)
    
    -- Check blacklist first
    if Config.RollingCoal.BlacklistModels[model] then return false end
    
    -- Check force list
    if Config.RollingCoal.ForceDieselModels[model] then return true end
    
    -- Check vehicle class
    local class = GetVehicleClass(veh)
    for _, dieselClass in ipairs(Config.RollingCoal.DieselClasses) do
        if class == dieselClass then return true end
    end
    
    return false
end

-- ============================================================================
-- DPF SYSTEM
-- ============================================================================
Config.DPFItem = 'dpf'            -- Item name (must exist in shared/items.lua)
Config.DPFRemoveTime = 6000       -- Progress time (ms) to remove DPF
Config.DPFInstallTime = 6000      -- Progress time (ms) to install DPF back

-- ============================================================================
-- NOS SYSTEM
-- ============================================================================
Config.NOS = {
  enabled = true,
  items = { full = 'nos', empty = 'emptynos' },
  capacity = 100,
  requireTurbo = false,
  defaultColor = '#55CCFF',
  cooldownSec = 6,
  cooldownMs = 10000,
  purgeCooldownBonusSec = 2,
  saveIntervalSec = 5,

  keys = {
    boost = 21,
    purge = 36,
    pageUp = 10,
    pageDown = 11,
    levelUp = 172,
    levelDown = 173,
  },

  -- CHANGED: Updated with damage per second from image
  levels = {
    [1] = { 
      torqueMult = 1.015, 
      powerMult = 1.1, 
      drainPerSec = 12,
      -- Damage per second while boosting (from image)
      damagePerSec = {
        engine_part = 0.20,      -- Engine Part: 0.20%
        sparkplugs = 0.30,       -- Spark Plugs: 0.30%
        fuel_injector = 0.15,    -- Fuel Injector: 0.15%
        engine_oil = 0.05,       -- Engine Oil: 0.05%
        axle = 0.05,             -- Axle Parts: 0.05% (only if spraying in 1st/2nd gear)
        heatPenalty = 0.10       -- Heat Penalty: Add 0.10% Engine Part per second when temp high
      }
    },
    [2] = { 
      torqueMult = 1.025, 
      powerMult = 1.25, 
      drainPerSec = 18,
      damagePerSec = {
        engine_part = 0.45,
        sparkplugs = 0.60,
        fuel_injector = 0.35,
        engine_oil = 0.10,
        axle = 0.15,
        heatPenalty = 0.25
      }
    },
    [3] = { 
      torqueMult = 1.04, 
      powerMult = 1.4, 
      drainPerSec = 25,
      damagePerSec = {
        engine_part = 0.90,
        sparkplugs = 1.20,
        fuel_injector = 0.80,
        engine_oil = 0.20,
        axle = 0.30,
        heatPenalty = 0.50
      }
    },
  },

  purge = {
    dict = 'core',
    name = 'ent_amb_generator_smoke',
    scale = 1.1,                           -- Purge particle scale
    styles = { 'both', 'left', 'right', 'wide' },  -- Purge styles (unused)
  },

  sfx = {
    purge = { bank = 'CARWASH_SOUNDS', name = 'SPRAY' },
    cooldownEnd = { bank = 'dlc_xm_heists_fm_uc_sounds', name = 'download_complete' }
  }
}

-- Helper for turbo requirement (robust; avoids false negatives)
function Config.HasTurbo(veh)
  if not veh or not DoesEntityExist(veh) then return false end
  SetVehicleModKit(veh, 0)

  -- 1) Native toggle check (most reliable when set by ToggleVehicleMod)
  local ok, on = pcall(IsToggleModOn, veh, 18)
  if ok and on then return true end

  -- 2) qb-core vehicle properties (some scripts only set props)
  if QBCore and QBCore.Functions and QBCore.Functions.GetVehicleProperties then
    local props = QBCore.Functions.GetVehicleProperties(veh)
    if props then
      if props.modTurbo == true or props.modTurbo == 1 or props['mod_turbo'] == true then
        return true
      end
    end
  end

  -- 3) Custom state flags (if your upgrade system sets an entity state flag)
  local st = Entity(veh).state
  if st and (st.turboInstalled == true or st.turbo == true) then
    return true
  end

  -- 4) Fallback: if we can't confirm, do not block NOS to avoid false negatives

  return true
end

-- ============================================================================
-- POS REGISTER ITEMS
-- ============================================================================
Config.RegisterItems = {
    -- Diagnostics & Service
    mechanic_tools      = { label = 'Mechanic Tools',      basePrice = 500,   category = 'Diagnostics & Service' },
    diagnosticstool     = { label = 'Diagnostics Tool',     basePrice = 1200,  category = 'Diagnostics & Service' },
    service_book        = { label = 'Service Book',         basePrice = 250,   category = 'Diagnostics & Service' },
    repair_kit          = { label = 'Repair Kit',           basePrice = 800,   category = 'Diagnostics & Service' },

    -- Repair Parts
    alternator          = { label = 'Alternator',           basePrice = 900,   category = 'Repair Parts' },
    carbattery          = { label = 'Car Battery',          basePrice = 700,   category = 'Repair Parts' },
    sparkplugs          = { label = 'Spark Plugs',          basePrice = 120,   category = 'Repair Parts' },
    oil_filter          = { label = 'Oil Filter',           basePrice = 90,    category = 'Repair Parts' },
    brake_pads          = { label = 'Brake Pads',           basePrice = 200,   category = 'Repair Parts' },
    susp_arm            = { label = 'Suspension Arm',       basePrice = 350,   category = 'Repair Parts' },
    axleparts           = { label = 'Axle Parts',           basePrice = 400,   category = 'Repair Parts' },
    radiator            = { label = 'Radiator',             basePrice = 600,   category = 'Repair Parts' },
    fuel_injector       = { label = 'Fuel Injector',        basePrice = 300,   category = 'Repair Parts' },
    powersteeringpump   = { label = 'Power Steering Pump',  basePrice = 450,   category = 'Repair Parts' },
    dpf                 = { label = 'DPF',                  basePrice = 350,   category = 'Repair Parts' },
    engine_part         = { label = 'Engine Part',          basePrice = 1000,  category = 'Repair Parts' },
    body_part           = { label = 'Body Part',            basePrice = 800,   category = 'Repair Parts' },
    tire_new            = { label = 'New Tire',             basePrice = 250,   category = 'Repair Parts' },

    -- Fluids
    power_steering_fluid= { label = 'Power Steering Fluid', basePrice = 60,    category = 'Fluids' },
    transmissionfluid   = { label = 'Transmission Fluid',   basePrice = 80,    category = 'Fluids' },
    brakefluid          = { label = 'Brake Fluid',          basePrice = 50,    category = 'Fluids' },
    coolant             = { label = 'Coolant',              basePrice = 70,    category = 'Fluids' },
    engine_oil          = { label = 'Engine Oil',           basePrice = 100,   category = 'Fluids' },
    newoil              = { label = 'New Oil',              basePrice = 110,   category = 'Fluids' },

    -- Heavy Repairs
    item_bench          = { label = 'Item Bench',           basePrice = 2000,  category = 'Heavy Repairs' },
    attachment_bench    = { label = 'Attachment Bench',     basePrice = 1800,  category = 'Heavy Repairs' },
    toolbox             = { label = 'Toolbox',              basePrice = 900,   category = 'Heavy Repairs' },
    mech_wrench         = { label = 'Mechanic Wrench',      basePrice = 350,   category = 'Heavy Repairs' },
    floor_jack          = { label = 'Floor Jack',           basePrice = 900,   category = 'Heavy Repairs' },
    jack_stands         = { label = 'Jack Stands',          basePrice = 850,   category = 'Heavy Repairs' },
    transmission_jack   = { label = 'Transmission Jack',    basePrice = 1600,  category = 'Heavy Repairs' },
    flywheel_service_kit= { label = 'Flywheel Service Kit', basePrice = 1200,  category = 'Heavy Repairs' },
    pulley_puller       = { label = 'Pulley Puller',        basePrice = 700,   category = 'Heavy Repairs' },
    mechanic_hammer     = { label = 'Mechanic Hammer',      basePrice = 250,   category = 'Heavy Repairs' },
    mechanic_socket     = { label = 'Mechanic Socket',      basePrice = 120,   category = 'Heavy Repairs' },
    sliced_bread        = { label = 'Sliced Bread',         basePrice = 15,    category = 'Heavy Repairs' },

    -- Advanced Diagnostics
    alignment_rack_tool     = { label = 'Alignment Rack Controller', basePrice = 2400, category = 'Advanced Diagnostics' },
    obd_scanner             = { label = 'OBD-II Scanner',            basePrice = 950,  category = 'Advanced Diagnostics' },
    multimeter              = { label = 'Automotive Multimeter',     basePrice = 650,  category = 'Advanced Diagnostics' },
    coolant_pressure_tester = { label = 'Coolant Pressure Tester',   basePrice = 1100, category = 'Advanced Diagnostics' },
    evap_smoke_machine      = { label = 'EVAP Smoke Machine',        basePrice = 2200, category = 'Advanced Diagnostics' },
    chop_kit                = { label = 'Chop Shop Kit',             basePrice = 1800, category = 'Advanced Diagnostics' },

    -- Cosmetics
    paintcan            = { label = 'Paint Can',            basePrice = 200,   category = 'Cosmetics' },
    bumper              = { label = 'Bumper',               basePrice = 400,   category = 'Cosmetics' },
    exhaust             = { label = 'Exhaust',              basePrice = 350,   category = 'Cosmetics' },
    externals           = { label = 'Externals',            basePrice = 300,   category = 'Cosmetics' },
    hood                = { label = 'Hood',                 basePrice = 350,   category = 'Cosmetics' },
    horn                = { label = 'Horn',                 basePrice = 100,   category = 'Cosmetics' },
    internals           = { label = 'Internals',            basePrice = 300,   category = 'Cosmetics' },
    livery              = { label = 'Livery',               basePrice = 250,   category = 'Cosmetics' },
    customplate         = { label = 'Custom Plate',         basePrice = 150,   category = 'Cosmetics' },
    rims                = { label = 'Rims',                 basePrice = 400,   category = 'Cosmetics' },
    roof                = { label = 'Roof',                 basePrice = 300,   category = 'Cosmetics' },
    rollcage            = { label = 'Roll Cage',            basePrice = 500,   category = 'Cosmetics' },
    seat                = { label = 'Seat',                 basePrice = 200,   category = 'Cosmetics' },
    skirts              = { label = 'Skirts',               basePrice = 250,   category = 'Cosmetics' },
    spoiler             = { label = 'Spoiler',              basePrice = 350,   category = 'Cosmetics' },
    tint_supplies       = { label = 'Tint Supplies',        basePrice = 120,   category = 'Cosmetics' },

    -- Performance
    car_armor           = { label = 'Car Armor',            basePrice = 1200,  category = 'Performance' },
    brakes1             = { label = 'Brakes Level 1',       basePrice = 300,   category = 'Performance' },
    brakes2             = { label = 'Brakes Level 2',       basePrice = 500,   category = 'Performance' },
    brakes3             = { label = 'Brakes Level 3',       basePrice = 700,   category = 'Performance' },
    engine1             = { label = 'Engine Level 1',       basePrice = 800,   category = 'Performance' },
    engine2             = { label = 'Engine Level 2',       basePrice = 1200,  category = 'Performance' },
    engine3             = { label = 'Engine Level 3',       basePrice = 1800,  category = 'Performance' },
    engine4             = { label = 'Engine Level 4',       basePrice = 2500,  category = 'Performance' },
    engine5             = { label = 'Engine Level 5',       basePrice = 3500,  category = 'Performance' },
    suspension1         = { label = 'Suspension Level 1',   basePrice = 300,   category = 'Performance' },
    suspension2         = { label = 'Suspension Level 2',   basePrice = 500,   category = 'Performance' },
    suspension3         = { label = 'Suspension Level 3',   basePrice = 700,   category = 'Performance' },
    suspension4         = { label = 'Suspension Level 4',   basePrice = 900,   category = 'Performance' },
    suspension5         = { label = 'Suspension Level 5',   basePrice = 1200,  category = 'Performance' },
    transmission1       = { label = 'Transmission Level 1', basePrice = 400,   category = 'Performance' },
    transmission2       = { label = 'Transmission Level 2', basePrice = 700,   category = 'Performance' },
    transmission3       = { label = 'Transmission Level 3', basePrice = 1000,  category = 'Performance' },
    transmission4       = { label = 'Transmission Level 4', basePrice = 1400,  category = 'Performance' },
    drifttires          = { label = 'Drift Tires',          basePrice = 600,   category = 'Performance' },
    bprooftires         = { label = 'Bulletproof Tires',    basePrice = 900,   category = 'Performance' },
    turbo               = { label = 'Turbo',                basePrice = 2000,  category = 'Performance' },
    headlights          = { label = 'Headlights',           basePrice = 250,   category = 'Performance' },
    nos                 = { label = 'NOS',                  basePrice = 1200,  category = 'Performance' },
    emptynos            = { label = 'Empty NOS',            basePrice = 100,   category = 'Performance' },
    antilag             = { label = 'Antilag',              basePrice = 800,   category = 'Performance' },

    -- Documents
    mech_receipt        = { label = 'Mechanic Receipt',     basePrice = 0,     category = 'Documents' },
    preview_receipt     = { label = 'Preview Receipt',      basePrice = 0,     category = 'Documents' },
}

  -- ============================================================================
  -- SUPPLIES ORDERING (ORDER SUPPLIES APP)
  -- ============================================================================
  Config.SuppliesCatalog = {
    -- If items list is empty, all Config.RegisterItems are used.
    items = {},
    -- Optional per-item overrides keyed by item id
    overrides = {
      -- engine_part = { caseSize = 5, casePrice = 4500, caseContents = '5x Engine Part' },
      -- engine_oil = { caseSize = 12, casePrice = 1200, caseContents = '12x Engine Oil' },
    },
    defaultCaseSize = 10,
    imageBase = 'https://cfx-nui-qb-inventory/html/images/'
  }

  Config.SuppliesOrder = {
    -- Time per order stage in seconds
    timing = {
      baseSorting = 60,
      basePacking = 60,
      baseReady = 60,
      perCase = 0
    },
    -- Cases per pallet used to determine how many pallets spawn
    casesPerPallet = 10,
    
    -- Pallet spawn locations (specific coordinates)
    palletSpawns = {
      vector3(1184.02, -3251.22, 6.03),
      vector3(1184.02, -3248.93, 6.03),
      vector3(1184.02, -3246.64, 6.03),
      vector3(1184.02, -3244.35, 6.03),
      vector3(1185.56, -3251.22, 6.03),
      vector3(1185.56, -3248.93, 6.03),
      vector3(1185.56, -3246.64, 6.03),
      vector3(1185.56, -3244.23, 6.03)
    },
    
    -- Forklift spawn location
    forkliftSpawn = vector4(1191.24, -3236.42, 6.03, 89.04),
    
    -- Truck spawn location (server will spawn, client will position)
    truckSpawn = vector4(1187.60, -3248.50, 5.50, 90.0),
    
    -- Default drop-off location (can be changed via computer)
    defaultDropoffLocation = vector4(-350.18, -133.84, 39.01, 0.0),
    
    -- Truck model (using mule for now)
    truckModel = 'mule',
    
    palletModels = {
      'prop_pallet_02a',
      'prop_boxpile_07a'
    },
    forkliftModel = 'forklift'
  }

-- ============================================================================
-- MANAGEMENT APP SETTINGS
-- ============================================================================
Config.ManagementApp = {
    Enabled = true,
    OpenKey = "F6",
    DefaultBusinessName = "Los Santos Customs",
    DefaultBlipName = "Customs Shop",
    DefaultBlipColor = 3
}

-- ============================================================================
-- ADVANCED WORKSHOP SYSTEMS
-- ============================================================================
Config.AdvancedSystems = {
  Enabled = true,

  -- Mobile mechanics remain supported. If true, pit bays improve speed but
  -- are not required for core operations.
  MobileMechanics = true,

  PitBays = {
    Enabled = true,
    ServiceSpeedMultiplier = 0.75,
    RequireForAlignmentRack = false,
    -- Add your actual bay centers/radius here.
    Zones = {
      -- { coords = vector3(-335.75, -137.12, 39.01), radius = 6.0, label = 'LS Customs Bay 1' },
    }
  },

  Alignment = {
    Enabled = true,
    BaseDurationMs = 20000,
    WearReduction = 12,
    Uses = {
      alignment_rack_tool = true
    }
  },

  LiftSystem = {
    Enabled = true,
    JackLiftHeight = 0.42,
    HoistLiftHeight = 0.60,
    RequireJackStandsForHeavyWork = true
  },

  ClutchWorkflow = {
    Enabled = true,
    RequireLiftedVehicle = true,
    RequireTransmissionJack = true,
    RequireFlywheelServiceKit = true,
    RequirePilotBearingToolChoice = true,
    Consumables = {
      sliced_bread = 1
    }
  },

  Diagnostics = {
    Enabled = true,
    Tools = {
      obd_scanner = true,
      multimeter = true,
      evap_smoke_machine = true,
      coolant_pressure_tester = true
    }
  },

  HeavyDuty = {
    Enabled = true,
    Classes = {
      [10] = true, -- Industrial
      [11] = true, -- Utility
      [12] = true, -- Vans
      [18] = true, -- Emergency
      [20] = true  -- Commercial
    },
    ServiceTimeMultiplier = 1.25
  },

  RoadsideService = {
    Enabled = true,
    Command = 'roadside',
    RewardMin = 350,
    RewardMax = 850,
    XPReward = 40,
    MinRepairSeconds = 20,   -- the server pays no sooner than this after the call starts
    CooldownSeconds = 180    -- time between roadside calls per mechanic
  },

  ChopShop = {
    Enabled = true,
    Command = 'chopshop',
    Zones = {
      -- Add real locations as needed.
      { coords = vector3(2350.69, 3133.31, 48.21), radius = 18.0, label = 'Sandy Chop Yard' }
    },
    RewardItems = {
      { item = 'axleparts', min = 1, max = 2 },
      { item = 'brake_pads', min = 1, max = 2 },
      { item = 'engine_part', min = 1, max = 1 }
    }
  },

  Integrations = {
    Enabled = true,
    Tow = {
      -- Uses TriggerEvent for local server resources. Events are optional.
      EventNames = {
        'pf-towing:server:mechanicServiceRequest',
        'qb-towjob:server:mechanicServiceRequest'
      }
    },
    Insurance = {
      EventNames = {
        'pf-insurance:server:recordRepairInvoice',
        'qb-insurance:server:recordRepairInvoice'
      }
    }
  },

  SkillTree = {
    Enabled = true,
    PointsPerLevel = 1,
    Nodes = {
      quick_diagnostics = {
        label = 'Quick Diagnostics',
        description = 'Diagnostic tool actions are faster.',
        cost = 1,
        requires = {}
      },
      clutch_master = {
        label = 'Clutch Master',
        description = 'Clutch jobs complete faster and safer.',
        cost = 1,
        requires = { 'quick_diagnostics' }
      },
      heavy_duty_cert = {
        label = 'Heavy Duty Certified',
        description = 'Reduced penalty on heavy-duty repairs.',
        cost = 1,
        requires = { 'clutch_master' }
      },
      roadside_specialist = {
        label = 'Roadside Specialist',
        description = 'Higher roadside payouts and XP.',
        cost = 1,
        requires = {}
      },
      insurance_handler = {
        label = 'Insurance Handler',
        description = 'Insurance/tow integration records are enriched.',
        cost = 1,
        requires = { 'roadside_specialist' }
      }
    }
  }
}
