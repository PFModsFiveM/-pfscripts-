Config = {}

-- ============================================================================
-- FRAMEWORK
-- ============================================================================
-- Supported: 'qbcore' or 'esx'
-- Note: ESX support is implemented via a compatibility layer; your server must
-- have either `qb-core` or `es_extended` started.
Config.Framework = 'qb-core'

-- ============================================================================
-- DEBUG & GENERAL
-- ============================================================================
-- Global debug toggle.
-- When enabled, developer commands and debug console prints are allowed.
-- Keep this false on production servers.
Config.Debug = false

-- ============================================================================
-- LOCALE & LOCALIZATION
-- ============================================================================
-- Available languages: 'en', 'es', 'pl', 'fr', 'de', 'pt'
Config.Locale = 'en'

-- ============================================================================
-- JOBS & PERMISSIONS
-- ============================================================================
-- Jobs that can access the EMS MDT
-- Copy staff, discipline, audit, roster and SOP rows from the old pf_mdt_* tables into this MDT's
-- pf_emsmdt_* tables when those are empty. Leave false while pf-policemdt runs: pf_mdt_* are its tables.
Config.MigrateLegacyPoliceTables = false

Config.AllowedJobs = {
    ["ambulance"] = true,
    ["ems"] = true,
    ["fire"] = true
}

-- Supervisor grades (per job)
Config.SupervisorGrades = {
    ["ambulance"] = { [3] = true, [4] = true, [5] = true, [6] = true },
    ["ems"] = { [3] = true, [4] = true, [5] = true, [6] = true },
    ["fire"] = { [2] = true, [3] = true, [4] = true, [5] = true }
}

-- ============================================================================
-- ACCESS METHODS (Item, Command, Keybind)
-- ============================================================================
-- Enable/disable different ways to open the MDT

Config.Item = {
    Enabled = true,
    Name = 'ems_mdt',
    Description = 'EMS MDT Tablet'
}

Config.Command = {
    Enabled = true,
    Name = 'emsmdt',
    Description = 'Opens the EMS MDT'
}

Config.Keybind = {
    Enabled = true,
    Description = 'Open EMS MDT',
    Key = 'F6',
    -- Input device type for RegisterKeyMapping: "keyboard", "pad", or "mouse"
    InputType = 'keyboard',
    -- Dedicated internal command used by the keybind.
    -- Keeps the keybind working even if you change/disable Config.Command.Name.
    CommandName = 'pfemsmdt_open'
}

-- ============================================================================
-- UI CUSTOMIZATION
-- ============================================================================
-- Tablet top bar title
Config.TabletTitle = 'EMS MDT'

-- =========================================================================
-- SOP
-- =========================================================================
-- If you previously ran a police MDT that created legacy SOP tables, this
-- resource can auto-reset SOPs back to EMS defaults on start.
Config.SOP = {
    ForceSeed = true
}

-- Tablet visuals (prop + animation) per open method.
-- Note: this only controls the tablet prop/animation, not whether the MDT can open.
Config.TabletVisuals = {
    Enabled = true,
    Item = true,
    Command = true,
    Keybind = true,

    -- Prop attachment tuning (fixes tablet sitting in the wrong place while anim plays)
    -- These defaults are a good baseline for:
    --   anim dict: amb@code_human_in_bus_passenger_idles@female@tablet@base
    --   anim name: base
    Attach = {
        -- 57005 = SKEL_R_Hand (right hand)
        bone = 57005,
        pos = { x = 0.03, y = 0.002, z = 0.0 },
        rot = { x = 10.0, y = 160.0, z = 0.0 }
    }
}

-- ============================================================================
-- MAP CONFIGURATION
-- ============================================================================
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

-- ============================================================================
-- LOCATION & AREA FALLBACKS
-- ============================================================================
-- Fallback area names (used when street/zone are unavailable)
Config.LocationAreas = {
    { label = "Cayo Perico", minX = -2500.0, maxX = 2500.0, minY = 5500.0, maxY = 9000.0 },
    { label = "North Sea",   minX = -8000.0, maxX = 8000.0, minY = 4500.0, maxY = 9000.0 },
    { label = "Pacific Ocean", minX = -8000.0, maxX = -3000.0, minY = -8000.0, maxY = 3000.0 },
    { label = "San Andreas", minX = -4400.0, maxX = 3600.0, minY = -5400.0, maxY = 8200.0 },
}

-- ============================================================================
-- DISPATCH & CALLS
-- ============================================================================
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

-- Dispatch notifications (client-side)
-- Plays a small "ding" when a new dispatch call is received.
Config.DispatchNotifications = {
    Enabled = true,
    -- "nui" allows volume control (recommended). "native" uses PlaySoundFrontend.
    -- NOTE: Many clients block WebAudio until a user gesture; native is the most reliable.
    Mode = 'native',
    NUI = {
        enabled = true,
        -- 1.0 = normal, 5.0 = 5x louder
        volume = 5.0,
        -- Sound shape (WebAudio)
        waveform = 'triangle', -- sine | triangle | square | sawtooth
        -- One or two tones. If tone2Hz is set, a two-tone "ding" is played.
        tone1Hz = 988,   -- B5
        tone2Hz = 784,   -- G5
        tone2AtMs = 80,  -- when to switch to tone2
        durationMs = 220
    },
    Sound = {
        enabled = true,
        -- Native frontend sound
        -- More noticeable than ATM_WINDOW on most clients.
        name = 'SELECT',
        soundset = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
    },
    -- Extra emphasis for native sounds (approx "louder")
    NativeRepeat = {
        count = 2,
        intervalMs = 60
    },
    -- If the client receives CallsUpdated for the first time, it won't know what's "new".
    -- This window treats very recent calls as "new" and plays the ding.
    InitialDingWindowSeconds = 15
}

-- =========================================================================
-- /911 CIVILIAN CALLS
-- =========================================================================
-- Players can use /911 <description> to create a dispatch call.
-- The description is classified into a call type based on keywords.
Config.Dispatch911 = {
    Enabled = true,
    CooldownSeconds = 20,
    MaxDescriptionLength = 200,

    -- If enabled, one /911 can create multiple dispatch calls when the description
    -- matches multiple categories (e.g. "gta and murder").
    -- Calls are created in best-match order (priority desc, then keyword hits).
    MultiMatch = {
        enabled = true,
        maxCalls = 2
    },

    -- Default call when no keywords match
    Default = {
        callType = '911',
        code = '911',
        title = '911 Call',
        priority = 2
    },

    -- Best match wins:
    -- - If multiple types match the description, the server picks the highest priority.
    -- - If priorities tie, it picks the type with the most keyword hits.
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

-- Test call templates for /mdt_testcall command
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

-- ============================================================================
-- AUTO DISPATCH CALLS (Triggered by player actions)
-- ============================================================================
-- Auto Calls are created when players commit certain actions (shots fired, vehicle theft, homicide)
-- Each call type has its own chance and cooldown
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

-- ============================================================================
-- DASHBOARD
-- ============================================================================
-- Optional dashboard seed data (bulletins, reports, PCRs to display on startup)
Config.Dashboard = {
    bulletins = {},
    reports = {},
    pcrs = {}
}

-- ============================================================================
-- REPORT & TREATMENT TYPES
-- ============================================================================
Config.ReportTypes = {
    'Patient Care Report (PCR)',
    'Mass Casualty Incident',
    'DOA Report',
    'Refusal of Care',
    'Inter-Facility Transfer'
}

Config.TreatmentTypes = {
    'Trauma Assessment',
    'Cardiac Protocol',
    'Respiratory Support',
    'Neurological Assessment',
    'Overdose Protocol',
    'Burn Treatment',
    'Psychiatric Assessment',
    'Pediatric Assessment'
}

-- ============================================================================
-- PERMISSIONS (job => min grade required)
-- ============================================================================
Config.Permissions = {
    createPCR = { ambulance = 0, ems = 0, fire = 0 },
    deletePCR = { ambulance = 3, ems = 3, fire = 2 },
    viewPatients = { ambulance = 0, ems = 0, fire = 0 },
    treatPatient = { ambulance = 0, ems = 0, fire = 0 },
    pronounceDOA = { ambulance = 2, ems = 2, fire = 1 }
}

-- ============================================================================
-- INJURY DOCUMENTATION SYSTEM
-- ============================================================================
Config.InjuryDocumentation = {
    MinGradeCreate = 0,  -- Minimum grade to document injuries
    MinGradeDelete = 3   -- Minimum grade to delete injury records (supervisor)
}

-- ============================================================================
-- WEBHOOKS (Discord integrations)
-- ============================================================================
Config.Webhooks = {
    Evidence = GetConvar('pf_emsmdt_evidence_webhook', '') -- set in server.cfg: setr pf_emsmdt_evidence_webhook "<webhook url>"
}

-- ============================================================================
-- FTO (Field Training Officer) REPORTS
-- ============================================================================
Config.FTOReports = {
    MinGradeCreate = 2,
    MaxPhase = 4,
    TraineePoliceOnly = false
}

-- ============================================================================
-- INTEGRATIONS (System providers for various scripts)
-- ============================================================================
-- These settings specify which third-party scripts are integrated with the MDT.
-- Make sure the corresponding scripts are installed and started on your server.

-- Phone number format
-- Set to nil to use default format. Example: '({3}) {3}-{4}' = (123) 456-7890
Config.PhoneNumberFormat = nil

-- Phone integration
-- Supported scripts: 'qb-phone'
-- Make sure you have qb-phone or equivalent installed
Config.Phone = 'qb-phone'

-- Properties/Housing integration (Optional)
-- Supported scripts: 'qb', 'nolag-properties'
-- Enable by setting to the script name, or 'none' to disable
Config.Housing = 'qb'

-- Garage integration (Optional)
-- Supported scripts: 'qb-garages'
-- Enable by setting to the script name, or 'none' to disable
Config.Garage = 'qb-garages'

-- Banking/Society backend for fines (Required)
-- Supported scripts: 'qb-banking', 'tgg-banking'
-- Choose which banking script your server uses for fine deposits
Config.Banking = 'tgg-banking'

-- Prison/Jail integration (Required)
-- Supported scripts: 'default' (built-in MDT jail flow), 'rcore_prison'
-- Choose which prison system your server uses
Config.Prison = 'default'

-- Evidence management (Coming Soon)
-- Status: Not yet implemented
-- Config.Evidence = 'coming_soon'

-- ============================================================================
-- SENTENCING & PRISON
-- ============================================================================
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

-- ============================================================================
-- CCTV SYSTEM CONFIG
-- ============================================================================
-- The CCTV system automatically discovers cameras in the world and stores them in the database.
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
