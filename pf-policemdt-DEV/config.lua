-- ═══════════════════════════════════════════════════════════════════════════════
--                       PF-POLICEMDT CONFIGURATION GUIDE
--                              v1.0
-- ═══════════════════════════════════════════════════════════════════════════════

Config = {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 1. CORE CONFIGURATION                                                     ║
-- ║    Start here for basic setup options                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════════
-- IMPORTANT: All compatibility settings are defined in shared/framework.lua
--            but MUST be configured here in config.lua
--            
--            Available settings to configure:
--            - Config.Framework  (QBCore/ESX)
--            - Config.Phone      (qb-phone, lb-phone, tgg-phone)
--            - Config.Housing    (qb, nolag-properties)
--            - Config.Garage     (qb-garages, cd-garages)
--            - Config.Banking    (qb-banking, tgg-banking, wasabi_banking)
--            - Config.Billing    (qb-billing, okok-billing, renewed-billing, vivum-billing, wasabi_banking)
--            - Config.Prison     (default, rcore_prison)
--            
--            See shared/framework.lua for all available options and documentation.
-- ═══════════════════════════════════════════════════════════════════════════════

-- FRAMEWORK & INTEGRATIONS (See shared/framework.lua for all options)
Config.Framework = 'qb-core'         -- 'qb-core' or 'esx'
Config.Phone = 'qb-phone'            -- 'qb-phone', 'lb-phone', 'tgg-phone', 'none'
Config.Housing = 'qb'                -- 'qb', 'nolag-properties', 'none'
Config.Garage = 'qb-garages'         -- 'qb-garages', 'cd-garages', 'none'
Config.Banking = 'qb-banking'        -- 'qb-banking', 'tgg-banking', 'wasabi_banking', 'none'
Config.Billing = 'none'              -- 'qb-billing', 'okok-billing', 'renewed-billing', 'vivum-billing', 'wasabi_banking', 'none'
Config.Prison = 'default'            -- 'default', 'rcore_prison'

Config.Debug = true                  -- Enable debug console output
Config.Locale = 'en'                  -- Language: 'en', 'es', 'pl', 'fr', 'de', 'pt'

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 2. ACCESS & PERMISSIONS                                                    ║
-- ║    Control who can access the MDT and what they can do                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Which jobs can access the MDT
Config.AllowedJobs = {
    ["police"] = true,
    ["sheriff"] = true,
    ["bcso"] = true
}

-- Supervisor grades (minimum grade to access supervisor features)
Config.SupervisorGrades = {
    ["police"] = { [3] = true, [4] = true, [5] = true, [6] = true },
    ["sheriff"] = { [3] = true, [4] = true, [5] = true, [6] = true },
    ["bcso"] = { [3] = true, [4] = true, [5] = true, [6] = true }
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 3. HOW TO OPEN THE MDT                                                    ║
-- ║    Configure access methods (item/command/keybind)                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Via MDT Item (in inventory)
Config.Item = {
    Enabled = true,
    Name = 'mdt',
    Description = 'Police MDT Tablet'
}

-- Via /mdt command
Config.Command = {
    Enabled = true,
    Name = 'mdt',
    Description = 'Opens the Police MDT'
}

-- Via F6 keybind (or custom key)
Config.Keybind = {
    Enabled = true,
    Description = 'Open Police MDT',
    Key = 'F6',
    InputType = 'keyboard',
    CommandName = 'pfmdt_open'
}

-- MDT tablet visuals (prop + animation when opening)
Config.TabletVisuals = {
    Enabled = true,
    Item = true,
    Command = true,
    Keybind = true,
    Attach = {
        bone = 57005,                              -- SKEL_R_Hand (right hand)
        pos = { x = 0.03, y = 0.002, z = 0.0 },
        rot = { x = 10.0, y = 160.0, z = 0.0 }
    }
}

Config.TabletTitle = 'Police MDT'

-- Manual entry creation in Citizens/Vehicles/Weapons sections.
-- When enabled, automatic records still work and officers can add extra records manually.
Config.ManualEntries = {
    Enabled = false
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      MAP & LOCATION SYSTEM                                ║
-- ║                      Map rendering & location fallbacks                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

Config.Map = {
    -- Simple map selection:
    --   "tiles" -> uses stitched tiles from html/tiles (default) (More Optimized)
    --   "map"   -> uses one full-map image from html/map/full_map.png (Roxwood) (Laggy due to bigger image)
    mode = 'tiles',

    -- Advanced/legacy options (you can ignore these if you use Config.Map.mode)
    -- "tiles" = use stitched tiles from html/tiles
    -- "image" = use a single full-map image
    renderMode = 'image',
    image = {
        set = 'map',
        file = 'full_map.png',
        -- Optional: low-res preview image used while zooming (massively reduces zoom lag in CEF).
        -- Put it in the same folder as `file` (e.g. html/map/full_map_preview.png).
        previewFile = 'full_map_preview.png',
        -- How long after zooming stops to swap back to full-res (ms)
        fullSwapDelayMs = 350,
        -- IMPORTANT: full_map.png actual pixel size (prevents squashing + aligns marker scaling)
        width = 7661,
        height = 9464,

        -- Image-mode calibration (separate from Config.Map.affine used for tiles).
        -- If enabled, homography is used for world->pixel on the full_map image.
        -- This can reduce global drift when the map isn't perfectly affine.
        homography = {
            enabled = true,
            -- Best-fit calibration from 7 points
            -- px = (h11*x + h12*y + h13) / (h31*x + h32*y + h33)
            -- py = (h21*x + h22*y + h23) / (h31*x + h32*y + h33)
            h11 = 0.6780354222543525,
            h12 = -0.001206473104755546,
            h13 = 4332.445222023915,
            h21 = -0.0028859915292250293,
            h22 = 0.6794243038803937,
            h23 = 2881.064211963792,
            h31 = -0.0000008071948063965127,
            h32 = -0.00000042250394211647453,
            h33 = 1
        },

        -- If homography is disabled, affine can be used.
        -- If enabled, this affine is used directly for world->pixel on the full_map image.
        -- If disabled, the tile affine is scaled into image space (works only if the image is a perfect scale).
        affine = {
            enabled = true,
            -- Best-fit calibration from 4 points (Legion, Sandy Airfield, Paleto Gas, LSIA)
            -- px = a*x + b*y + c
            -- py = d*x + e*y + f
            a = 0.683273129278323,
            b = -0.000454757814475404,
            c = 4332.25050650733,
            d = -0.0000784054101153064,
            e = 0.682916393309817,
            f = 2888.51985123617
        },

        -- Optional extra pixel offsets applied after mapping (useful for fine-tuning).
        -- Calibrated using Legion Square:
        -- world: vector3(195.68, -928.83, 30.69)
        -- click: x=4466.51 y=2252.00
        offsetX = 0,
        offsetY = 0,

        -- Optional overrides for simple mapping when affine is disabled.
        -- worldBounds = { minX=..., maxX=..., minY=..., maxY=... },
        -- flipY = false,
        -- path = 'map/full_map.png'
    },

    -- Tile canvas size (px)
    width = 512,
    height = 768,
    
    -- Zoom limits
    minZoom = 0,
    maxZoom = 4,
    
    -- Debug calibration UI | DONT TOUCH IF YOU DONT KNOW WHAT IT DOES
    debugCalibration = true,
    
    -- Simple bounds fallback (used if affine is disabled)
    worldBounds = {
        minX = -4400.0,
        maxX = 3600.0,
        minY = -5400.0,
        maxY = 8200.0
    },
    
    -- Flip Y in simple mode
    flipY = false,
    
    -- Affine transform (recommended for accurate positioning)
    affine = {
        enabled = true,
        a = 0.057224749984624,
        b = -5.19174615369e-05,
        c = 235.7312970498,
        d = -0.00086656148521447,
        e = 0.057021922171885,
        f = 289.75743737554
    }
}

-- Fallback area names (used when street/zone are unavailable)
Config.LocationAreas = {
    { label = "Cayo Perico", minX = -2500.0, maxX = 2500.0, minY = 5500.0, maxY = 9000.0 },
    { label = "North Sea",   minX = -8000.0, maxX = 8000.0, minY = 4500.0, maxY = 9000.0 },
    { label = "Pacific Ocean", minX = -8000.0, maxX = -3000.0, minY = -8000.0, maxY = 3000.0 },
    { label = "San Andreas", minX = -4400.0, maxX = 3600.0, minY = -5400.0, maxY = 8200.0 },
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                       DISPATCH SYSTEM                                     ║
-- ║                 Emergency calls & 911 integration                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- IMPORTANT: Dispatch system integration
-- Choose where 911 calls are dispatched to:
Config.Dispatch = {
    -- Use external lb-dispatches system instead of built-in dispatch
    -- Set to true if you have mfp_lb-dispatches installed
    -- 911 calls will be routed to lb-dispatches (via lb-tablet) instead of MDT's built-in system
    UseLBDispatches = false,
    
    -- Sound notifications for dispatch calls
    Notifications = {
        Enabled = true,
        Mode = 'native',                         -- 'native' or 'nui'
        NUI = {
            enabled = true,
            volume = 5.0,
            waveform = 'triangle',
            tone1Hz = 988,                       -- B5
            tone2Hz = 784,                       -- G5
            tone2AtMs = 80,
            durationMs = 220
        },
        Sound = {
            enabled = true,
            name = 'SELECT',
            soundset = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
        },
        NativeRepeat = {
            count = 2,
            intervalMs = 60
        },
        InitialDingWindowSeconds = 15
    },
    
    -- Call expiry time (seconds)
    CallExpirySeconds = 300,                     -- 5 minutes
}

-- Call priority levels
Config.CallPriorities = {
    [1] = { label = "LOW", color = "#4CAF50" },
    [2] = { label = "MEDIUM", color = "#FF9800" },
    [3] = { label = "HIGH", color = "#F44336" }
}

Config.CallStatuses = {
    ["pending"] = { label = "PENDING", color = "#F44336" },
    ["accepted"] = { label = "ACCEPTED", color = "#2196F3" },
    ["completed"] = { label = "COMPLETED", color = "#757575" }
}

-- 911 CIVILIAN CALL SYSTEM
-- When Config.Dispatch.UseLBDispatches = false: Uses built-in MDT dispatch system
-- When Config.Dispatch.UseLBDispatches = true: Routes 911 calls to mfp_lb-dispatches
Config.Dispatch911 = {
    Enabled = true,
    CooldownSeconds = 20,
    MaxDescriptionLength = 200,
    MultiMatch = {
        enabled = true,
        maxCalls = 2
    },
    Default = {
        callType = '911',
        code = '911',
        title = '911 Call',
        priority = 2
    },
    Types = {
        shooting = {
            keywords = {
                'shots fired', 'shot fired', 'gunshots', 'gun shots', 'gun shot',
                'shooting', 'shoot', 'shots', 'shot',
                'gunfire', 'gun fire', 'firearm', 'gun',
                'pistol', 'handgun', 'rifle',
                'drive by', 'drive-by', 'driveby'
            },
            callType = '911_shooting',
            code = '10-71',
            title = 'Shots Fired',
            priority = 3
        },

        vehicle_theft = {
            keywords = {
                'vehicle theft', 'stolen vehicle', 'stole my car', 'stole my vehicle',
                'car theft', 'stolen car', 'stole my car',
                'motorcycle theft', 'stolen motorcycle', 'bike theft', 'stolen bike',
                'truck stolen', 'van stolen', 'suv stolen',
                'carjacking', 'carjacked', 'carjack',
                'gta', 'grand theft auto', 'joyriding', 'joyriding'
            },
            callType = '911_vehicle_theft',
            code = '10-60',
            title = 'Vehicle Theft',
            priority = 3
        },

        homicide = {
            keywords = {
                'murder', 'homicide',
                'dead body', 'body found', 'found a body',
                'someone is dead', 'person is dead',
                'killed', 'killing', 'killed someone',
                'stabbed', 'stabbing', 'knife attack',
                'shot dead', 'executed',
                'person down', 'man down', 'woman down',
                'unresponsive', 'not breathing'
            },
            callType = '911_homicide',
            code = '187',
            title = 'Murder / Homicide',
            priority = 3
        },

        robbery = {
            keywords = {
                'robbery', 'robbed', 'rob',
                'armed robbery', 'store robbery', 'bank robbery', 'gas station robbery',
                'hold up', 'hold-up', 'holdup',
                'stick up', 'stick-up', 'stickup',
                'mugging', 'mugged', 'heist'
            },
            callType = '911_robbery',
            code = '211',
            title = 'Robbery',
            priority = 3
        },

        fight = {
            keywords = {
                'fight', 'fighting', 'brawl', 'beating',
                'assault', 'attacked', 'attack',
                'punching', 'punched', 'punch',
                'kicking', 'kicked',
                'melee', 'jumped', 'jumping',
                'domestic', 'disturbance'
            },
            callType = '911_fight',
            code = '10-10',
            title = 'Fight In Progress',
            priority = 2
        },

        accident = {
            keywords = {
                'traffic accident', 'car accident', 'vehicle accident',
                'accident', 'crash', 'car crash',
                'wreck', 'collision', 'pile up', 'pile-up', 'pileup',
                'rollover', 't-bone', 'rear ended', 'rear-ended',
                'hit and run', 'hit-and-run'
            },
            callType = '911_accident',
            code = '10-50',
            title = 'Traffic Accident',
            priority = 2
        },

        theft = {
            keywords = {
                'theft', 'stolen', 'steal', 'stole',
                'shoplifting', 'shoplift',
                'pickpocket', 'pick pocket',
                'burglary', 'break in', 'break-in', 'broke into',
                'larceny', 'vandalism', 'property stolen'
            },
            callType = '911_theft',
            code = '10-60',
            title = 'Theft',
            priority = 2
        }
    }
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 7. TEST CALL TEMPLATES                                                     ║
-- ║    /mdt_testcall command examples                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.TestCallTemplates = {
    "10-10 - Fight in Progress",
    "10-31 - Burglary in Progress",
    "10-32 - Person with Gun",
    "10-50 - Traffic Accident",
    "10-60 - Suspicious Vehicle",
    "10-66 - Suspicious Person",
    "10-90 - Alarm",
    "211 - Robbery",
    "245 - Assault with Deadly Weapon",
    "459 - Burglary",
    "487 - Grand Theft Auto",
    "594 - Vandalism"
}

-- Call expiry time
Config.CallExpirySeconds = 300 -- 5 minutes

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 8. AUTO DISPATCH CALLS                                                       ║
-- ║ Triggered by player actions (shots fired, vehicle theft, homicide)            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.DispatchAutoCalls = {
    Enabled = true,
    
    -- Global chance multiplier (1.0 = always, 0.5 = 50% chance, 0.0 = disabled)
    GlobalChance = 1.0,

    -- Ignore events triggered by police jobs (set to false for testing)
    IgnorePolice = false,

    -- Global cooldown between any auto calls (seconds)
    GlobalCooldown = 10,

    -- Per-call configuration
    -- Format: [call_type] = { enabled = bool, chance = 0-100, cooldown = seconds, code = "XX-XX", title = "...", priority = 1-3 }
    Calls = {
        Speeding = {
            enabled = true,
            chance = 40,     -- 40% chance to dispatch
            cooldown = 30,
            code = "10-80",
            title = "Speeding Vehicle",
            priority = 1
        },
        Shooting = {
            enabled = true,
            chance = 100,    -- 100% chance to dispatch
            cooldown = 20,
            code = "10-71",
            title = "Shots Fired",
            priority = 3
        },
        CarJack = {
            enabled = true,
            chance = 90,     -- 90% chance to dispatch
            cooldown = 60,
            code = "10-60",
            title = "Vehicle Theft",
            priority = 3
        },
        PlayerDead = {
            enabled = true,
            chance = 100,    -- 100% chance to dispatch
            cooldown = 30,
            code = "10-55",
            title = "Person Down",
            priority = 3
        },
        Combat = {
            enabled = true,
            chance = 70,     -- 70% chance to dispatch
            cooldown = 25,
            code = "10-04",
            title = "Combat In Progress",
            priority = 3
        },
        DriveBy = {
            enabled = true,
            chance = 95,     -- 95% chance to dispatch
            cooldown = 45,
            code = "10-100",
            title = "Drive By Shooting",
            priority = 3
        },
        Explosion = {
            enabled = true,
            chance = 100,    -- 100% chance to dispatch
            cooldown = 50,
            code = "10-92",
            title = "Explosion Reported",
            priority = 3
        }
    }
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 9. DASHBOARD                                                                 ║
-- ║ Seed data for bulletins, reports, warrants on startup                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.Dashboard = {
    bulletins = {},
    reports = {},
    warrants = {}
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 10. REPORT & CHARGE TYPES                                                    ║
-- ║ Available report and charge classification options                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.ReportTypes = {
    'Incident Report',
    'Arrest Report',
    'Traffic Stop',
    'Use of Force',
}

Config.ChargeTypes = {
    'Disorderly Conduct',
    'Assault',
    'Robbery',
    'Grand Theft Auto',
    'Possession of Controlled Substance',
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 11. PERMISSIONS                                                              ║
-- ║ Required minimum grade per job for various MDT features                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.Permissions = {
    createWarrant = { police = 0, sheriff = 0, bcso = 0 },
    deleteWarrant = { police = 3, sheriff = 3, bcso = 3 },
    viewIncidents = { police = 0, sheriff = 0, bcso = 0 },
    deleteIncidents = { police = 4, sheriff = 4, bcso = 4 },
    viewReports = { police = 0, sheriff = 0, bcso = 0 },
    deleteReports = { police = 4, sheriff = 4, bcso = 4 },
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 12. EVIDENCE SYSTEM                                                          ║
-- ║ Grade requirements for evidence creation and deletion                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.Evidence = {
    MinGradeCreate = 0,  -- Minimum grade to create evidence
    MinGradeDelete = 4   -- Minimum grade to delete evidence (supervisor/admin)
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 13. WEBHOOKS                                                                 ║
-- ║ Discord webhook integrations for evidence and system notifications           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.Webhooks = {
    Evidence = GetConvar('pf_mdt_evidence_webhook', '') -- set in server.cfg: setr pf_mdt_evidence_webhook "<webhook url>"
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 14. FTO (FIELD TRAINING OFFICER) REPORTS                                     ║
-- ║ Configuration for field training officer report system                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.FTOReports = {
    MinGradeCreate = 2,
    MaxPhase = 4,
    TraineePoliceOnly = false
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 15. INTEGRATIONS                                                             ║
-- ║ Third-party script integrations (phone, housing, garage, banking, etc.)      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Phone number format
-- Set to nil to use default format. Example: '({3}) {3}-{4}' = (123) 456-7890
Config.PhoneNumberFormat = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 16. SENTENCING & PRISON                                                      ║
-- ║ Prison system configuration, fine handling, jail-time reductions             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.Sentencing = {
    -- Which prison system to use.
    -- Supported: 'default' (built-in) or 'rcore' (rcore_prison)
    -- Backward-compat: if Config.Prison is set to 'rcore_prison', we normalize to 'rcore'.
    PrisonScript = (Config.Prison == 'rcore_prison' and 'rcore' or (Config.Prison or 'default')),

    -- Deposit paid fines into society
    FinesToSociety = true,
    FinesSocietyJob = 'police',

    -- Jail-time reductions (percentages)
    Reductions = {
        { key = 'cooperation', label = 'Cooperation', percent = 20 },
        { key = 'good_behavior', label = 'Good Behavior', percent = 10 },
        { key = 'first_time', label = 'First Time Offender', percent = 15 },
        { key = 'plea_deal', label = 'Plea Deal', percent = 25 },
    },

    -- Default prison spawn locations and release point
    Prison = {
        Spawns = {
            vector4(1761.52, 2480.86, 45.74, 210.0),
            vector4(1763.72, 2482.84, 45.74, 210.0),
            vector4(1765.72, 2484.86, 45.74, 210.0),
            vector4(1767.84, 2486.88, 45.74, 210.0),
        },
        Release = vector4(1848.34, 2586.10, 45.67, 90.0),
    },

    -- Built-in prison clothing (applied for the default MDT jail flow only)
    -- Components:
    --  jacket = component 11, shirt = component 8, hands = component 3, legs = component 4, shoes = component 6
    PrisonOutfit = {
        jacket = { drawable = 56, texture = 0 },
        shirt  = { drawable = 15, texture = 0 },
        hands  = { drawable = 0,  texture = 0 },
        legs   = { drawable = 5,  texture = 7 },
        shoes  = { drawable = 42, texture = 0 },
    }
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 17. CCTV SYSTEM                                                              ║
-- ║ CCTV camera auto-discovery, recording, and footage management                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.CCTV = {
    Enabled = true,
    AutoDiscover = true,              -- Client automatically scans world props for cameras
    PersistDiscoveredToDb = true,     -- Discovered cameras are automatically saved to database
    Debug = Config.Debug,              -- Console logging for debugging
    DiscoveryInterval = 5000,          -- Check for new cameras every 5 seconds
    RecordingDistance = 100.0,         -- Distance for recording footage
    RecordingInterval = 500,           -- Record every 500ms
    RecordingBatchSize = 50,           -- Batch recording inserts
    DamageOverlayDuration = 3000,      -- Show damage effect for 3 seconds
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 18. CITATION PRINTING                                                      ║
-- ║ Controls where and how officers can print citation papers                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.Citations = {
    -- Allow printing citations directly from the MDT tablet UI
    -- Set to false to require officers to be at a physical printer location
    PrintFromMDT = true,

    -- Optional: physical printer location. If set, officers must stand within
    -- PrinterDistance metres of these coords to print a citation.
    -- Set to nil (or comment out) to skip the proximity check.
    -- Example: PrinterCoords = { x = 441.0, y = -978.0, z = 30.7 },
    PrinterCoords = nil,

    -- Max distance from the printer coords (metres)
    PrinterDistance = 3.0,

    -- Label shown in the error message when the officer is too far away
    PrinterLabel = 'Station Printer',
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ 19. DISPATCH OVERLAY                                                       ║
-- ║ Live on-screen dispatch popup (no MDT open required)                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
Config.DispatchOverlay = {
    -- Show the live dispatch popup on screen for allowed jobs
    Enabled = true,

    -- Key to respond to the currently displayed call (GTA key name)
    RespondKey     = 'G',
    RespondKeyDesc = 'Respond to dispatch call',

    -- Keys to cycle between active calls (leave blank '' to disable)
    PrevCallKey     = 'PRIOR',   -- Page Up
    PrevCallKeyDesc = 'Dispatch: previous call',
    NextCallKey     = 'NEXT',    -- Page Down
    NextCallKeyDesc = 'Dispatch: next call',
}

-- All GTA5 CCTV camera props - auto-discovers from game world
Config.CCTVModels = {
    `prop_cctv_cam_01a`,
    `prop_cctv_cam_02a`,
    `prop_cctv_cam_03a`,
    `prop_cctv_cam_04a`,
    `prop_cctv_cam_05a`,
    `prop_cctv_cam_06a`,
    `prop_cctv_cam_07a`,
    `prop_cctv_cam_08a`,
    `prop_bullet_cam`,
    `prop_bullet_cam_02`,
    `prop_sec_camera_01`,
    `prop_sec_camera_02`,
    `prop_armour_cam_01`,
    `prop_cinema_cam`,
    `prop_traffic_cam_01`,
    `prop_traffic_cam_02`,
    `prop_traffic_cam_03`,
    `prop_traffic_cam_04`,
    `prop_building_camera`,
    `prop_building_camera_01`,
    `prop_building_camera_02`,
    `prop_tracking_camera_01`,
    `prop_store_cam_01`,
    `prop_store_camera_01`,
    `prop_nightclub_cam`,
    `prop_nightclub_camera`,
    `prop_atm_cam`,
    `prop_atm_camera`,
    `v_serv_securitycam_01`,
    `v_serv_securitycam_02`,
    `v_serv_securitycam_03`,
}
