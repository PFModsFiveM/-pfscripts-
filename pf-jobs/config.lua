Config = {}
Config.TabletItem = 'tablet' -- Changed from 'job_tablet' to 'tablet' -- Item name in your items.lua

Config.Apps = Config.Apps or {
    {name = 'Business', icon = '📊', enabled = true},
    {name = 'Contacts', icon = '📇', enabled = true},
    {name = 'Gruppe6', icon = '🔒', enabled = true},
    {name = 'Real Estate', icon = '🏠', enabled = true},
    {name = 'Trucking', icon = '🚚', enabled = true}
}

Config.BusinessJobs = Config.BusinessJobs or {
    { label = 'Police',      role = 'police',     icon = '👮', description = 'Law enforcement and public safety' },
    { label = 'Ambulance',   role = 'ambulance',  icon = '🚑', description = 'Emergency medical services' },
    { label = 'Mechanic',    role = 'mechanic',   icon = '🔧', description = 'Vehicle repairs and maintenance' },
    { label = 'Beeker\'s',   role = 'beeker',     icon = '🏁', description = 'Custom garage and modifications' },
    { label = 'Benny\'s',    role = 'bennys',     icon = '🛠️', description = 'Premium auto customization' },
    { label = 'Real Estate', role = 'realestate', icon = '🏠', description = 'Property sales and management' },
    { label = 'Taxi',        role = 'taxi',       icon = '🚕', description = 'Passenger transportation services' },
    { label = 'Car Dealer',  role = 'cardealer',  icon = '🚗', description = 'New and used vehicle sales' },
    { label = 'Trucker',     role = 'trucker',    icon = '🚚', description = 'Commercial freight delivery' },
    { label = 'Gruppe 6',    role = 'gruppe6',    icon = '🛡️', description = 'Secure cash transport operations' },
    { label = 'Government',  role = 'government', icon = '🏛️', description = 'City administration and services' },
}

Config.RefreshInterval = 5 -- seconds

Config.UI = {
    AppGap = 6,          -- grid gap between app icons
    AppIconSize = 88,     -- px (width/height)
    DockIconSize = 50,    -- px
    WindowW = 760,        -- business & generic window width
    WindowH = 640         -- business & generic window height (increase to avoid cut off on 1080p)
}

Config.Gruppe6 = {
    Debug = false, -- true: contract offers every 5-10 seconds (testing only; Priority Dispatch means nothing then)
    MinSpawnTime = 5 * 60 * 1000, -- 5 minutes in ms (production)
    MaxSpawnTime = 10 * 60 * 1000, -- 10 minutes in ms (production)
    DebugSpawnTime = 10 * 1000, -- Not used anymore - using random 5-10 sec in debug
    
    -- Server-side stash handling toggle
    -- false = use shared qb-inventory stash UI at pickups (original behavior)
    -- true  = no UI stash, collect bags directly via target (server-tracked counts)
    ServerSideStash = false,
    
    -- XP System
    XPPerContract = 100,
    XPPerBag = 10,
    LevelThresholds = {
        [1] = 0,      -- Level 1: 0 XP
        [2] = 1000,   -- Level 2: 1000 XP
        [3] = 5000,   -- Level 3: 5000 XP
        [4] = 10000,  -- Level 4: 10000 XP
        [5] = 15000,  -- Level 5: 15000 XP
    },
    
    -- Contract Tiers (adjust vehicles per tier)
    -- Note: With min 10 locations and 20-100 bags per location, total bags per contract: 200-1000+
    Tiers = {
        [1] = { label = 'Tier 1', minLevel = 1, bags = {200, 400}, payout = {500, 1000}, vehicles = {'stockade'} },  -- Only stockade for tier 1
        [2] = { label = 'Tier 2', minLevel = 2, bags = {400, 700}, payout = {1500, 2500}, vehicles = {'stockade'} }, -- Use stockade until you add others
        [3] = { label = 'Tier 3', minLevel = 3, bags = {700, 1000}, payout = {2500, 4000}, vehicles = {'stockade'} }, -- Use stockade until you add others
    },
    
    UseDatabase = true, -- Already set to true - correct
    
    -- Vehicle spawn locations (random selection)
    VehicleSpawns = {
        vector4(-19.69, -670.54, 32.34, 182.89),
        vector4(-34.65, -672.55, 32.34, 183.88),
        vector4(-5.19, -670.37, 32.34, 184.0),
    },
    
    -- Plate prefix for Gruppe6 vehicles
    PlatePrefix = 'G6',
    
    -- Minimum pickup locations per job
    MinPickupLocations = 10,       -- Minimum 10 locations per job
    
    -- Enable Roxwood locations (if true, uses Roxwood coordinates)
    UseRoxwood = false,
    
    -- Remove Los Santos locations (if true and UseRoxwood is true, only uses Roxwood coords)
    RemoveLosSantos = false,
    
    -- Pickup locations - Los Santos (bags spawn here sequentially)
    PickupLocations = {
        vector3(149.24, -1048.6, 29.35),
        vector3(313.31, -286.94, 54.14),
        vector3(28.84, -1339.35, 29.5),
        vector3(92.56, -1291.77, 29.27),
        vector3(72.03, -1391.93, 29.38),
        vector3(1126.63, -980.18, 45.42),
        vector3(-823.31, -1070.0, 11.33),
        vector3(-1207.48, -336.75, 37.76),
        vector3(-1102.97, 2713.72, 19.11),
        vector3(546.5, 2662.85, 42.16),
        vector3(1197.65, 2713.78, 38.22),
        vector3(1172.88, 2714.47, 38.07),
        vector3(1169.23, 2717.82, 37.16),
        vector3(1959.21, 3748.83, 32.34),
        vector3(1697.55, 4822.31, 42.06),
        vector3(1734.74, 6420.84, 35.04),
        vector3(-104.81, 6476.53, 31.63),
        vector3(-3047.79, 584.91, 7.91),
        vector3(-2954.87, 484.48, 15.68),
    },
    
    -- Pickup locations - Roxwood (only used if UseRoxwood = true)
    RoxwoodPickupLocations = {
        vector3(-628.77, 6930.61, 24.32),
        vector3(-605.96, 7007.74, 17.9),
        vector3(-374.8, 7203.78, 18.22),
        vector3(-546.99, 7395.53, 12.84),
        vector3(-490.82, 7428.12, 5.27),
        vector3(-2839.23, 6234.65, 9.78),
        vector3(-1320.33, 6973.22, 20.52),
    },
    
    -- Final deposit location
    DepositLocation = vector3(265.97, 213.38, 101.68),
    
    -- Vault Doors Configuration
    VaultDoors = {
        -- Pacific Standard Bank (main deposit location)
        {
            name = 'Pacific Standard Vault',
            vaultDoorModels = { 'v_ilev_bk_vaultdoor' },
            vaultDoorCoords = vector3(255.23, 217.39, 101.68), -- Door location
            vaultDoorHeading = 160.0,
            securityPanelCoord = vector3(262.11, 222.62, 106.28), -- Security panel location
            securityPanelHeading = 250.0,
            depositZoneCoords = vector3(265.97, 213.38, 101.68), -- Where to deposit bags
            searchRadius = 6.0,
            openHeadingOffset = -90.0,
            isMainVault = true,
            requireActiveContract = true,
        },
        -- Fleeca / Blaine County bank vault doors
        {
            name = 'Fleeca Bank - Legion Square',
            vaultDoorModels = { 'v_ilev_gb_vaultdor', 'v_ilev_gb_vaultdr', 'v_ilev_gb_vaultdoor' },
            vaultDoorCoords = vector3(147.35, -1046.06, 29.37),
            vaultDoorHeading = 250.0,
            securityPanelCoord = vector3(146.92, -1046.11, 29.37),
            securityPanelHeading = 340.0,
            depositZoneCoords = vector3(148.73, -1044.75, 29.37),
            searchRadius = 5.0,
            openHeadingOffset = -90.0,
            isMainVault = false,
            requireActiveContract = false,
        },
        {
            name = 'Fleeca Bank - Hawick Ave',
            vaultDoorModels = { 'v_ilev_gb_vaultdor', 'v_ilev_gb_vaultdr', 'v_ilev_gb_vaultdoor' },
            vaultDoorCoords = vector3(-350.83, -55.45, 49.04),
            vaultDoorHeading = 250.0,
            securityPanelCoord = vector3(-348.37, -55.78, 49.04),
            securityPanelHeading = 340.0,
            depositZoneCoords = vector3(-349.51, -54.33, 49.04),
            searchRadius = 5.0,
            openHeadingOffset = -90.0,
            isMainVault = false,
            requireActiveContract = false,
        },
        {
            name = 'Fleeca Bank - Del Perro Blvd',
            vaultDoorModels = { 'v_ilev_gb_vaultdor', 'v_ilev_gb_vaultdr', 'v_ilev_gb_vaultdoor' },
            vaultDoorCoords = vector3(-1211.48, -336.46, 37.78),
            vaultDoorHeading = 297.0,
            securityPanelCoord = vector3(-1209.75, -335.03, 37.78),
            securityPanelHeading = 27.0,
            depositZoneCoords = vector3(-1210.77, -336.28, 37.78),
            searchRadius = 5.0,
            openHeadingOffset = -90.0,
            isMainVault = false,
            requireActiveContract = false,
        },
        {
            name = 'Fleeca Bank - Great Ocean Hwy',
            vaultDoorModels = { 'v_ilev_gb_vaultdor', 'v_ilev_gb_vaultdr', 'v_ilev_gb_vaultdoor' },
            vaultDoorCoords = vector3(-2956.56, 481.74, 15.70),
            vaultDoorHeading = 357.0,
            securityPanelCoord = vector3(-2957.32, 483.24, 15.70),
            securityPanelHeading = 268.0,
            depositZoneCoords = vector3(-2955.90, 482.44, 15.70),
            searchRadius = 5.0,
            openHeadingOffset = -90.0,
            isMainVault = false,
            requireActiveContract = false,
        },
        {
            name = 'Blaine County Bank - Route 68',
            vaultDoorModels = { 'v_ilev_gb_vaultdor', 'v_ilev_gb_vaultdr', 'v_ilev_gb_vaultdoor' },
            vaultDoorCoords = vector3(1175.48, 2712.93, 38.09),
            vaultDoorHeading = 359.0,
            securityPanelCoord = vector3(1175.90, 2710.84, 38.09),
            securityPanelHeading = 179.0,
            depositZoneCoords = vector3(1175.52, 2711.92, 38.09),
            searchRadius = 5.0,
            openHeadingOffset = -90.0,
            isMainVault = false,
            requireActiveContract = false,
        },
        {
            name = 'Blaine County Bank - Paleto Bay',
            vaultDoorModels = { 'v_ilev_gb_vaultdor', 'v_ilev_gb_vaultdr', 'v_ilev_gb_vaultdoor' },
            vaultDoorCoords = vector3(-105.79, 6472.17, 31.63),
            vaultDoorHeading = 46.0,
            securityPanelCoord = vector3(-107.47, 6473.89, 31.63),
            securityPanelHeading = 226.0,
            depositZoneCoords = vector3(-106.44, 6472.65, 31.63),
            searchRadius = 5.0,
            openHeadingOffset = -90.0,
            isMainVault = false,
            requireActiveContract = false,
        },
    },
    
    -- Money bag item key (must exist in QBCore.Shared.Items)
    MoneyBagItem = 'moneybag',
    MoneyBagsPerLocationMin = 20,   -- Minimum 20 bags per location
    MoneyBagsPerLocationMax = 100,  -- Maximum 100 bags per location
    
    -- Group System
    Groups = {
        MaxMembers = 4,              -- Maximum party size
        DefaultPayoutSplit = 25,     -- Default % for each member (leader can adjust)
        LeaderCanKick = true,        -- Allow leader to kick members
        RequireAccept = true,        -- Members must accept invite
        -- A party contract pays a pool of 1.5x the payout per member, shared by the leader's splits.
        CrewBonus = 1.5,
        MinSplitPercent = 10,        -- the least share a member can be given
    },

    -- Upgrades: bought once per player from the bank (ledger), kept in pf_gruppe6_upgrades, applied
    -- by the server to the contracts of the player who accepts them.
    --   unlocksTier: contract tier N also needs this upgrade (besides its minLevel)
    --   bagBonus:    more bags per pickup, and the payout grows with them
    --   searchSpeed: contract offers arrive this much faster while searching
    Upgrades = {
        tier_2 = {
            label = 'Tier 2 Licence',
            description = 'Unlocks Tier 2 contracts (bigger payouts) from level 2',
            cost = 10000,
            requiredLevel = 2,
            requiredTier = nil,
            unlocksTier = 2,
            icon = '🚚'
        },
        tier_3 = {
            label = 'Tier 3 Licence',
            description = 'Unlocks Tier 3 contracts (the biggest payouts) from level 3',
            cost = 25000,
            requiredLevel = 3,
            requiredTier = 2,        -- needs tier_2 first
            unlocksTier = 3,
            icon = '🛡️'
        },
        bag_capacity = {
            label = 'High-Capacity Contracts',
            description = '25% more money bags at every pickup, and 25% more pay for them',
            cost = 15000,
            requiredLevel = 2,
            requiredTier = nil,
            bagBonus = 0.25,
            icon = '💰'
        },
        priority_dispatch = {
            label = 'Priority Dispatch',
            description = 'Contract offers reach you twice as fast while you search',
            cost = 8000,
            requiredLevel = 1,
            requiredTier = nil,
            searchSpeed = 2.0,
            icon = '📡'
        },
    },

    -- Armoured truck robberies (pf-services 'crime.robbery.truck'): crews on a contract are warned and
    -- pickups near the attack are held by the police for a while.
    RobberyAlert = {
        Enabled = true,
        Radius = 600.0,              -- pickups this close to the attack are held
        HoldMinutes = 10,
    },
}

Config.Garbage = {
    -- Vehicle spawn location
    VehicleSpawn = vector4(-598.11, 8309.98, 6.03, 87.29),
    VehicleModel = 'trash',
    
    -- Depot return location
    DepotLocation = vector3(-635.82, 8302.51, 6.31),
    ReturnLocation = vector4(-622.07, 8302.81, 6.31, 2.28),
    DepotRadius = 7.5,
    
    -- XP System
    XPPerBag = 25,
    LevelThresholds = {
        [1] = 0,      -- Level 1: 0 XP
        [2] = 1000,   -- Level 2: 1000 XP
        [3] = 3000,   -- Level 3: 3000 XP
        [4] = 7000,   -- Level 4: 7000 XP
        [5] = 12000,  -- Level 5: 12000 XP
        [6] = 20000,  -- Level 6: 20000 XP
    },
    
    -- Payout System (per bag deposited)
    PayoutPerBag = {
        [1] = 20,  -- Level 1: $20 per bag
        [2] = 40,  -- Level 2: $40 per bag
        [3] = 60,  -- Level 3: $60 per bag
        [4] = 60,  -- Level 4: $60 per bag
        [5] = 60,  -- Level 5: $60 per bag
        [6] = 60,  -- Level 6: $60 per bag
    },
    
    -- Objective settings
    ObjectiveTarget = 10, -- Number of bags to deposit before returning truck (legacy)
    
    -- Level-based deposit cap
    DepositCap = {
        [1] = 20,   -- Level 1: max 20 bags
        [2] = 9999, -- Level 2+: unlimited
    },
    
    -- Dumpster settings
    DumpsterBagsMin = 2,  -- Minimum bags per dumpster
    DumpsterBagsMax = 6,  -- Maximum bags per dumpster
    
    -- Interactable props (add more as needed)
    DumpsterProps = {
        'prop_dumpster_01a',
        'prop_dumpster_4a',
        'prop_dumpster_02a',
        'prop_dumpster_02b',
        'm23_2_prop_m32_dumpster_01a',
        'prop_dumpster_4b',
        'amb_hc_bin',
        'amb_rox_bin_1',
        'amb_rox_bin_2',
        'amb_rox_bin_3',
        'amb_pine_garbin_s',
        'amb_rox_prop_acab_bin',
        'amb_rox_benef_bin',
    },
    
    BinbagProps = {
        'hei_prop_heist_binbag',
        'p_binbag_01_s',
        'prop_cs_street_binbag_01',
        'prop_rub_binbag_sd_01',
        'prop_cs_rub_binbag_01',
        'prop_rub_binbag_04',
        'prop_rub_binbag_sd_02',
        'ng_proc_binbag_01a',
        'prop_rub_binbag_05',
        'prop_rub_binbag_01',
        'prop_ld_rub_binbag_01',
    },
    
    -- Carry bag prop (what player holds)
    CarryBagProp = 'prop_cs_rub_binbag_01',
    
    -- Animations
    Animations = {
        Pickup = { dict = 'anim@heists@narcotics@trash', anim = 'pickup', duration = 900 },
        Carry = { dict = 'anim@heists@narcotics@trash', anim = 'walk', clipset = 'move_m@trash' },
        Deposit = { dict = 'anim@heists@narcotics@trash', anim = 'throw_bag', duration = 1200 },
    },
    
    -- Truck deposit offset (relative to vehicle)
    TruckDepositOffset = vector3(0.0, -4.6, 0.25),
    TruckDepositRadius = 3.0,
    
    -- Visual settings
    EnableHighlights = true,     -- Highlight dumpsters/bags with outline
    HighlightRange = 6.0,        -- Range to highlight props
    HighlightColor = {0, 255, 255, 255}, -- RGBA for outline (cyan)

    -- Zone gameplay (level-unlocked area sets)
    ZoneRadius = 550.0,
    DumpstersPerZone = 8,
    LevelAreaUnlocks = {
        [1] = { 'roxwood' },
        [2] = { 'roxwood', 'paleto', 'grapeseed' },
        [3] = { 'roxwood', 'paleto', 'grapeseed', 'sandy' },
        [4] = { 'roxwood', 'paleto', 'grapeseed', 'sandy', 'city' },
    },
    AreaZones = {
        city = {
            level = 4,
            points = {
                vector3(-3.95, -1460.14, 183.54),
                vector3(436.21, -1812.39, 135.67),
                vector3(-254.98, -1452.79, 125.03),
                vector3(-686.03, -1102.29, 174.59),
                vector3(-1446.44, -299.46, 200.71),
                vector3(1127.87, -404.15, 120.43),
            }
        },
        sandy = {
            level = 3,
            points = {
                vector3(1917.28, 3771.26, 134.64),
                vector3(1096.0, 2720.42, 156.25),
            }
        },
        grapeseed = {
            level = 2,
            points = {
                vector3(1673.23, 4854.39, 101.21),
            }
        },
        paleto = {
            level = 2,
            points = {
                vector3(-116.12, 6299.44, 227.28),
            }
        },
        roxwood = {
            level = 1,
            points = {
                vector3(-442.76, 7121.32, 233.83),
                vector3(-2202.97, 4268.83, 97.14),
            }
        },
    },
    
    -- Blip settings
    TruckBlip = {
        sprite = 318,
        color = 3,
        scale = 0.9,
        label = 'Garbage Truck'
    },
    
    ReturnBlip = {
        sprite = 318,
        color = 3,
        scale = 1.0,
        label = 'Return Garbage Truck'
    },
    
    -- Database
    UseDatabase = true,
    
    -- Group System (party mechanics)
    Groups = {
        MaxMembers = 4,              -- Maximum party size
        DefaultPayoutSplit = 25,     -- Default % for each member (auto-rebalances)
        LeaderCanKick = true,        -- Allow leader to kick members
        RequireAccept = true,        -- Members must accept invite
        SharePayouts = true,         -- Split payouts among group members
        -- A crew run pays a pool of 1.5x the run's pay per member, shared by the leader's splits.
        CrewBonus = 1.5,
        MinSplitPercent = 10,        -- the least share a member can be given
    },
    
    -- Debug mode (toggle with /garbdebug command)
    Debug = false,
}

-- City bus routes (server/apps/bus.lua, client/bus.lua, the Bus app). Pay is worked out on the
-- server from what it saw: stops checked in in order at the stop, NPC passengers who boarded the bus
-- there and rode to their stop, the route's distance and the server's clock.
Config.Bus = {
    Enabled = true,
    UseDatabase = true,            -- bus_stats / bus_routes_log (server/schema.lua migration)
    -- nil: a side job open to every citizen through the App Store. Set a job name (e.g. 'bus') to make
    -- the Bus app and routes need that job instead.
    Job = nil,
    PlatePrefix = 'BUS',

    -- The depot (pfm-busjob's): buses are taken out and returned here.
    Depot = { label = 'Dashound Bus Depot', coords = vector3(462.22, -641.15, 28.45), radius = 30.0 },
    VehicleSpawns = {
        vector4(462.22, -641.15, 28.45, 175.0),
    },
    -- Buses by driver level. capacity = seated passengers the server lets board.
    Vehicles = {
        { model = 'bus', label = 'City Bus', capacity = 15, minLevel = 1 },
        { model = 'airbus', label = 'Airport Bus', capacity = 15, minLevel = 2 },
        { model = 'coach', label = 'Dashound Coach', capacity = 9, minLevel = 3 },
    },
    AllowedVehicles = { 'bus', 'airbus', 'coach' },

    -- The route's distance pay is only for the stops served from the depot bus (passenger fares
    -- always need it). false: a route checked in with any vehicle still pays its distance.
    MileageNeedsBus = true,
    StopRange = 25.0,              -- server range for a stop check-in (the bus checks in at 10 m)
    MaxBusSpeed = 30.0,            -- m/s: a stop or a route faster than this is refused
    PassengerPeds = 4,             -- most passenger peds shown boarding at one stop (visual only)
    PedModels = {
        'a_f_m_tourist_01', 'a_f_y_business_01', 'a_f_y_hipster_02', 'a_f_m_soucent_01', 'a_f_y_bevhills_02',
        'a_m_m_business_01', 'a_m_y_business_02', 'a_m_m_bevhills_01', 'a_m_y_hipster_01', 'a_m_m_eastsa_01',
        'a_m_y_genstreet_01', 'a_m_m_ktown_01',
    },

    -- Difficulty -> driver level needed
    DifficultyLevels = { easy = 1, medium = 2, hard = 3 },

    Pricing = {
        BasePayPerPassenger = 12,  -- per NPC passenger delivered to their stop
        PayPerMile = 40,           -- route distance (baseDistance)
        RushHourMultiplier = 1.25, -- 07-10 and 17-20 server time
        NightBonus = 1.15,         -- 22-04
        OnTimeBonus = 0.15,        -- +15% when the route is driven within its estimated time
        VehicleHealthPenalty = 0.5,-- a wrecked bus loses up to half the fare
        -- rating >= threshold -> modifier (the highest matching threshold applies)
        PassengerRatingModifier = { [4.5] = 0.10, [4.0] = 0.05, [3.0] = 0.0, [0.0] = -0.10 },
        LevelMultiplier = { 1.0, 1.1, 1.2, 1.3, 1.45 },
        MaxRoutePay = 2500,
    },

    Levels = {
        { level = 1, name = 'Trainee', minRoutes = 0, maxRoutes = 9 },
        { level = 2, name = 'Driver', minRoutes = 10, maxRoutes = 29 },
        { level = 3, name = 'Senior Driver', minRoutes = 30, maxRoutes = 74 },
        { level = 4, name = 'Route Captain', minRoutes = 75, maxRoutes = 149 },
        { level = 5, name = 'Transit Legend', minRoutes = 150, maxRoutes = 99999 },
    },

    -- Stops: pfm-busjob's five stops plus kerbside points across the city. waiting = how many NPC
    -- passengers may be waiting there (the server picks a number each visit).
    Stops = {
        depot = { name = 'Dashound Bus Depot', coords = vector3(462.22, -641.15, 28.45), waiting = { 0, 2 } },
        strawberry = { name = 'Strawberry Avenue', coords = vector3(304.36, -764.56, 29.31), waiting = { 1, 4 } },
        forum = { name = 'Forum Drive', coords = vector3(-110.31, -1686.29, 29.31), waiting = { 1, 4 } },
        ginger = { name = 'Ginger Street', coords = vector3(-712.83, -824.56, 23.54), waiting = { 2, 5 } },
        sanandreas = { name = 'San Andreas Avenue', coords = vector3(-692.63, -670.44, 30.86), waiting = { 1, 4 } },
        vespucciblvd = { name = 'Vespucci Boulevard', coords = vector3(-250.14, -886.78, 30.63), waiting = { 2, 5 } },
        legion = { name = 'Legion Square', coords = vector3(240.06, -862.77, 29.73), waiting = { 3, 7 } },
        missionrow = { name = 'Mission Row', coords = vector3(220.64, -1010.81, 29.22), waiting = { 2, 6 } },
        mrpd = { name = 'Mission Row Police Station', coords = vector3(425.45, -979.53, 29.44), waiting = { 1, 4 } },
        pillbox = { name = 'Pillbox Hill', coords = vector3(-9.55, -544.0, 38.63), waiting = { 2, 5 } },
        pillboxmedical = { name = 'Pillbox Medical Center', coords = vector3(305.58, -595.39, 43.28), waiting = { 2, 5 } },
        alta = { name = 'Alta Street', coords = vector3(257.61, -380.57, 44.71), waiting = { 1, 4 } },
        hawick = { name = 'Hawick Avenue', coords = vector3(-7.86, -258.22, 46.9), waiting = { 1, 4 } },
        cityhall = { name = 'City Hall', coords = vector3(-515.19, -260.29, 35.53), waiting = { 3, 6 } },
        mountzonah = { name = 'Mount Zonah Medical', coords = vector3(-456.53, -346.87, 36.73), waiting = { 2, 5 } },
        rockford = { name = 'Rockford Hills', coords = vector3(-760.84, -34.35, 37.83), waiting = { 1, 4 } },
        lifeinvader = { name = 'Lifeinvader', coords = vector3(-1074.39, -266.64, 37.75), waiting = { 1, 4 } },
        morningwood = { name = 'Morningwood', coords = vector3(-1392.74, -584.91, 30.24), waiting = { 1, 4 } },
        delperro = { name = 'Del Perro', coords = vector3(-1321.28, -833.8, 16.95), waiting = { 2, 5 } },
        pier = { name = 'Del Perro Pier', coords = vector3(-1613.99, -1015.82, 13.12), waiting = { 2, 6 } },
        canals = { name = 'Vespucci Canals', coords = vector3(-1184.3, -1304.16, 5.24), waiting = { 1, 4 } },
        lapuerta = { name = 'La Puerta', coords = vector3(-774.04, -1277.25, 5.15), waiting = { 1, 4 } },
        palomino = { name = 'Palomino Avenue', coords = vector3(-548.64, -895.21, 29.3), waiting = { 1, 4 } },
        adamsapple = { name = "Adam's Apple Boulevard", coords = vector3(-75.68, -1102.94, 26.42), waiting = { 1, 4 } },
        chamberlain = { name = 'Chamberlain Hills', coords = vector3(-158.05, -1565.3, 35.06), waiting = { 1, 4 } },
        grove = { name = 'Grove Street', coords = vector3(111.18, -1938.54, 20.81), waiting = { 1, 4 } },
        rancho = { name = 'Rancho', coords = vector3(350.84, -1974.13, 24.52), waiting = { 1, 4 } },
        davis = { name = 'Davis', coords = vector3(442.09, -1684.33, 29.25), waiting = { 1, 5 } },
        arena = { name = 'Maze Bank Arena', coords = vector3(-229.11, -2043.16, 27.75), waiting = { 1, 5 } },
        cypress = { name = 'Cypress Flats', coords = vector3(826.0, -1885.26, 29.32), waiting = { 0, 3 } },
        elysian = { name = 'Elysian Fields Freeway', coords = vector3(922.24, -2224.03, 30.39), waiting = { 0, 3 } },
        murrieta = { name = 'Murrieta Heights', coords = vector3(1120.73, -957.31, 47.43), waiting = { 1, 4 } },
        mirrorpark = { name = 'Mirror Park', coords = vector3(1163.68, -800.25, 57.63), waiting = { 2, 5 } },
        mirrorblvd = { name = 'Mirror Park Boulevard', coords = vector3(1238.85, -377.73, 69.03), waiting = { 1, 3 } },
        vinewood = { name = 'Downtown Vinewood', coords = vector3(550.3, 172.55, 100.11), waiting = { 2, 6 } },
        westvinewood = { name = 'West Vinewood', coords = vector3(23.66, -60.23, 63.62), waiting = { 1, 4 } },
        richman = { name = 'Richman', coords = vector3(-1284.06, 297.52, 64.93), waiting = { 0, 3 } },
        pacificbluffs = { name = 'Pacific Bluffs', coords = vector3(-1604.09, -401.66, 42.35), waiting = { 1, 3 } },
        lsia = { name = 'LSIA Terminal', coords = vector3(-1053.23, -2716.2, 13.75), waiting = { 3, 7 } },
        lsiacargo = { name = 'LSIA Cargo Gate', coords = vector3(-1048.55, -2540.58, 13.69), waiting = { 1, 3 } },
    },

    -- A stop is a key of Stops or a table { name, coords, waiting }. baseDistance in miles (road
    -- distance), estimatedTime in ms (the on-time target). Every route starts and ends at the depot.
    Routes = {
        { id = 1, name = 'Downtown Loop', description = 'Pillbox Hill, Legion Square and Mission Row', difficulty = 'easy',
            baseDistance = 1.6, estimatedTime = 7 * 60000,
            stops = { 'depot', 'strawberry', 'legion', 'missionrow', 'vespucciblvd', 'pillbox', 'pillboxmedical', 'depot' } },
        { id = 2, name = 'Little Seoul Line', description = 'Legion Square to the heart of Little Seoul', difficulty = 'easy',
            baseDistance = 2.2, estimatedTime = 9 * 60000,
            stops = { 'depot', 'legion', 'vespucciblvd', 'palomino', 'ginger', 'sanandreas', 'pillbox', 'depot' } },
        { id = 3, name = 'South Side Line', description = 'Mission Row, Strawberry, Davis and Rancho', difficulty = 'easy',
            baseDistance = 3.2, estimatedTime = 11 * 60000,
            stops = { 'depot', 'mrpd', 'adamsapple', 'forum', 'grove', 'davis', 'rancho', 'depot' } },
        { id = 4, name = 'Rockford Express', description = 'Alta, Hawick, City Hall and Rockford Hills', difficulty = 'medium',
            baseDistance = 2.9, estimatedTime = 10 * 60000,
            stops = { 'depot', 'alta', 'hawick', 'mountzonah', 'cityhall', 'rockford', 'lifeinvader', 'depot' } },
        { id = 5, name = 'Beach Cities Line', description = 'Del Perro, the pier and the Vespucci canals', difficulty = 'medium',
            baseDistance = 3.8, estimatedTime = 13 * 60000,
            stops = { 'depot', 'vespucciblvd', 'sanandreas', 'delperro', 'pier', 'canals', 'lapuerta', 'depot' } },
        { id = 6, name = 'Airport Shuttle', description = 'Downtown to Los Santos International', difficulty = 'medium',
            baseDistance = 4.7, estimatedTime = 14 * 60000,
            stops = { 'depot', 'missionrow', 'arena', 'lsiacargo', 'lsia', 'lapuerta', 'depot' } },
        { id = 7, name = 'East Side Line', description = 'Mirror Park, Vinewood and Alta', difficulty = 'hard',
            baseDistance = 2.9, estimatedTime = 11 * 60000,
            stops = { 'depot', 'murrieta', 'mirrorpark', 'mirrorblvd', 'vinewood', 'westvinewood', 'alta', 'depot' } },
        { id = 8, name = 'Westside Express', description = 'Rockford Hills, Richman and the west coast', difficulty = 'hard',
            baseDistance = 4.3, estimatedTime = 14 * 60000,
            stops = { 'depot', 'hawick', 'rockford', 'richman', 'pacificbluffs', 'morningwood', 'delperro', 'ginger', 'depot' } },
        { id = 9, name = 'Industrial Line', description = 'Davis, Cypress Flats and the port road', difficulty = 'hard',
            baseDistance = 3.7, estimatedTime = 12 * 60000,
            stops = { 'depot', 'davis', 'cypress', 'elysian', 'rancho', 'chamberlain', 'forum', 'depot' } },
    },
}

-- Tow job (server/apps/tow.lua, client/tow.lua, the Tow app), moved here from pfm-towjob: flatbed
-- rental with a deposit, the flatbed hook (any car), NPC tow contracts when no one has asked for a
-- tow, and the pf-services tow requests (police impounds, recoveries to mechanic shops).
Config.Tow = {
    Enabled = true,
    Job = 'tow',                       -- the Tow app, rentals and contracts
    RequireOnDuty = true,
    HookJobs = { tow = true, mechanic = true }, -- who may use the flatbed hook (/tow, radial menu)
    HookModels = { 'flatbed' },        -- trucks the hook works on
    UseDatabase = true,                -- pf_tow_stats / pf_tow_rentals (server/schema.lua)
    PlatePrefix = 'TOWR',

    Depot = { label = 'Hayes Towing', coords = vector3(471.39, -1311.03, 29.21) },
    FlatbedSpawn = vector4(489.65, -1331.82, 29.33, 306.5),
    ReturnRadius = 25.0,               -- the truck and the driver must be this close to the spawn bay
    DropOff = { label = 'Hayes Depot', coords = vector3(491.00, -1314.69, 29.25), radius = 30.0 },

    Vehicles = {
        { model = 'flatbed', label = 'Flatbed', deposit = 250, minLevel = 1 },
    },
    DamageDeduction = 0.5,             -- a wrecked truck keeps up to half the deposit

    HookRange = 11.0,                  -- truck to car (pfm-towjob's range)
    DriverRange = 15.0,                -- the driver must stand by the truck to hook or unhook
    MinDeliverySeconds = 15,           -- between hooking a contract car and delivering it
    MaxTowSpeed = 40.0,                -- m/s: a delivery faster than this from the spot is refused

    Contracts = {
        OnlyWhenNoRequests = true,     -- NPC contracts only while no tow request waits in dispatch
        Cooldown = 10,                 -- seconds between contracts
        MaxPerHour = 20,
        PayBase = 140,
        PayPerKm = 30,
        MaxPay = 650,
        XPBase = 40,
        XPPerKm = 10,
    },
    RequestXP = 80,                    -- a completed pf-services tow request

    Levels = {
        { level = 1, xp = 0,    title = 'Rookie Driver',  maxKm = 3.0,  payMultiplier = 1.0 },
        { level = 2, xp = 500,  title = 'Tow Operator',   maxKm = 4.5,  payMultiplier = 1.1 },
        { level = 3, xp = 1500, title = 'Recovery Pro',   maxKm = 99.0, payMultiplier = 1.2 },
        { level = 4, xp = 3500, title = 'Heavy Hauler',   maxKm = 99.0, payMultiplier = 1.3 },
        { level = 5, xp = 7000, title = 'Road Legend',    maxKm = 99.0, payMultiplier = 1.4 },
    },

    -- Broken-down cars for NPC contracts (pfm-towjob's tow spots)
    Spots = {
        { model = 'sultanrs', coords = vector4(-2480.87, -211.96, 17.40, 0.0) },
        { model = 'zion', coords = vector4(-2723.39, 13.21, 15.13, 0.0) },
        { model = 'oracle', coords = vector4(-3169.62, 976.18, 15.04, 0.0) },
        { model = 'chino', coords = vector4(-3139.76, 1078.72, 20.19, 0.0) },
        { model = 'baller2', coords = vector4(-1656.94, -246.16, 54.51, 0.0) },
        { model = 'stanier', coords = vector4(-1586.66, -647.56, 29.44, 0.0) },
        { model = 'washington', coords = vector4(-1036.15, -491.06, 36.21, 0.0) },
        { model = 'buffalo', coords = vector4(-1029.19, -475.53, 36.42, 0.0) },
        { model = 'feltzer2', coords = vector4(75.21, 164.85, 104.69, 0.0) },
        { model = 'asea', coords = vector4(-534.60, -756.72, 31.60, 0.0) },
        { model = 'fq2', coords = vector4(487.24, -30.83, 88.86, 0.0) },
        { model = 'jackal', coords = vector4(-772.20, -1281.81, 4.56, 0.0) },
        { model = 'sultanrs', coords = vector4(-663.84, -1206.99, 10.17, 0.0) },
        { model = 'zion', coords = vector4(719.12, -767.78, 24.89, 0.0) },
        { model = 'oracle', coords = vector4(-970.95, -2410.45, 13.34, 0.0) },
        { model = 'chino', coords = vector4(-1067.52, -2571.41, 13.21, 0.0) },
        { model = 'baller2', coords = vector4(-619.24, -2207.29, 5.57, 0.0) },
        { model = 'stanier', coords = vector4(1192.08, -1336.91, 35.11, 0.0) },
        { model = 'washington', coords = vector4(-432.81, -2166.05, 9.89, 0.0) },
        { model = 'buffalo', coords = vector4(-451.82, -2269.35, 7.17, 0.0) },
        { model = 'asea', coords = vector4(939.27, -2197.54, 30.55, 0.0) },
        { model = 'fq2', coords = vector4(-556.11, -1794.73, 22.04, 0.0) },
        { model = 'jackal', coords = vector4(591.74, -2628.22, 5.57, 0.0) },
        { model = 'sultanrs', coords = vector4(1654.52, -2535.83, 74.49, 0.0) },
        { model = 'oracle', coords = vector4(1642.61, -2413.32, 93.14, 0.0) },
        { model = 'chino', coords = vector4(1371.32, -2549.53, 47.58, 0.0) },
        { model = 'baller2', coords = vector4(383.84, -1652.87, 37.28, 0.0) },
        { model = 'stanier', coords = vector4(27.22, -1030.88, 29.41, 0.0) },
        { model = 'washington', coords = vector4(229.26, -365.91, 43.75, 0.0) },
        { model = 'asea', coords = vector4(-85.81, -51.67, 61.11, 0.0) },
        { model = 'fq2', coords = vector4(-4.60, -670.27, 31.86, 0.0) },
        { model = 'oracle', coords = vector4(-111.90, 91.97, 71.08, 0.0) },
        { model = 'zion', coords = vector4(-314.26, -698.23, 32.55, 0.0) },
        { model = 'buffalo', coords = vector4(-366.91, 115.54, 65.58, 0.0) },
        { model = 'fq2', coords = vector4(-592.07, 138.21, 60.07, 0.0) },
        { model = 'zion', coords = vector4(-1613.86, 18.76, 61.80, 0.0) },
        { model = 'baller2', coords = vector4(-1709.80, 55.11, 65.71, 0.0) },
        { model = 'chino', coords = vector4(-521.89, -266.78, 34.94, 0.0) },
        { model = 'washington', coords = vector4(-451.09, -333.52, 34.02, 0.0) },
        { model = 'baller2', coords = vector4(322.36, -1900.50, 25.77, 0.0) },
    },
}

Config.Taxi = {
    Enabled = true,
    Job = 'taxi',
    UseDatabase = true,
    PlatePrefix = 'TAXI',

    -- Pricing System (distance-based)
    Pricing = {
        basePricePerMile = 60,
        premiumMultiplier = 1.5,
        playerClientMultiplier = 2.0,
        vipMultiplier = 0.9,  -- VIP gets 10% discount
        minimumFare = 50,     -- Minimum charge
        collisionPenalty = 0.05,  -- 5% penalty per collision
    },

    -- Rating System
    RatingSystem = {
        startingRating = 0,  -- Players start at 0 stars (calculated as 3.0 internally)
        maxRating = 5.0,
        collisionRatingPenalty = 0.2,  -- -0.2 per collision
        completionRatingBoost = 0.1,   -- +0.1 per successful ride
        perfectRideBoost = 0.3,        -- +0.3 if no collisions/crashes
        ratingImpactsCallFrequency = true,
    },

    -- Call System
    CallSystem = {
        minCallDelay = 30000,   -- 30 seconds minimum between calls
        maxCallDelay = 900000,  -- 15 minutes maximum between calls
        callGenerationRate = 0.8,  -- 80% chance a call generates after delay
        instantCallsOnToggle = false,  -- Calls don't appear instantly when accepting rides
        maxConcurrentCalls = 8,  -- Maximum calls to display at once
    },

    -- Collision Detection
    CollisionSystem = {
        enabled = true,
        vehicleCollisionThreshold = 15.0,  -- Damage threshold
        structureCollisionPenalty = 0.025,  -- Extra penalty for structure damage
        trackPlayerDamage = true,
    },

    -- Collision penalty tiers (applied to fare)
    CollisionPenalties = {
        pedestrian = 0.18,   -- big penalty
        vehicle = 0.14,      -- big penalty
        sign_lamp = 0.08,    -- medium penalty
        wall = 0.04,         -- small penalty
        minFareFactor = 0.10,
        cooldownMs = 1200,
        damageThreshold = 8.0,
    },

    -- Manual taxi meter for rides outside dispatch/job calls
    ManualMeter = {
        enabled = true,
        command = 'taximeter',
        defaultRate = 60,
    },

    -- NPC Behavior
    NPCBehavior = {
        dialogueChance = 0.7,  -- 70% chance NPC talks during ride
        phoneDialogueChance = 0.4,  -- 40% chance to talk on phone
        walkAwayAtDest = true,  -- NPC walks away instead of disappearing
        walkAwayDistance = 50.0,  -- Distance NPC walks from dropoff
        animationVariety = true,  -- Use varied animations
    },

    LevelUnlocks = {
        privateVehicle = 4,
        luxuryVehicle = 5,
        premiumClients = 3,
    },

    Levels = {
        { level = 1, xp = 0,    title = 'Rookie Driver', unlocks = 'Basic calls and compact rental vehicles' },
        { level = 2, xp = 800,  title = 'City Cab Driver', unlocks = 'Medium capacity rental vehicles' },
        { level = 3, xp = 2200, title = 'Trusted Dispatcher', unlocks = 'Premium client calls' },
        { level = 4, xp = 5000, title = 'Fleet Specialist', unlocks = 'Use private vehicle for taxi jobs' },
        { level = 5, xp = 9000, title = 'Luxury Chauffeur', unlocks = 'Luxury taxi vehicles and top-tier calls' },
    },

    VehicleSpawns = {
        vector4(913.82, -159.86, 74.38, 194.09),
        vector4(913.82, -159.86, 74.38, 194.09),
    },

    -- Rental vehicle depot for returns
    RentalDepot = vector3(912.45, -165.32, 74.38),

    RentalVehicles = {
        { name = 'Taxi Stanier', spawnCode = 'taxi', unlockLevel = 1, maxCapacity = 2, rental = 120, deposit = 300, image = 'images/taxi/taxi_stanier.png' },
        { name = 'Vapid Minivan', spawnCode = 'minivan', unlockLevel = 2, maxCapacity = 4, rental = 180, deposit = 500, image = 'images/taxi/taxi_minivan.png' },
        { name = 'Benefactor Schafter', spawnCode = 'schafter2', unlockLevel = 3, maxCapacity = 3, rental = 250, deposit = 750, image = 'images/taxi/taxi_schafter.png' },
        { name = 'Enus Cognoscenti', spawnCode = 'cognoscenti', unlockLevel = 5, maxCapacity = 3, rental = 450, deposit = 1400, image = 'images/taxi/taxi_luxury.png' },
    },

    PedModels = {
        'a_m_y_business_01',
        'a_m_y_business_02',
        'a_f_y_business_01',
        'a_m_m_bevhills_01',
        'a_f_y_tourist_01',
    },

    PreconfiguredClients = {
        { name = 'Ethan Brooks', premium = false, playerClient = false },
        { name = 'Mia Carter', premium = false, playerClient = false },
        { name = 'Noah Price', premium = false, playerClient = false },
        { name = 'Olivia Reed', premium = false, playerClient = false },
        { name = 'Victor DeLuca', premium = true,  playerClient = false },
        { name = 'Charlotte Sinclair', premium = true, playerClient = false },
        { name = 'Michael De Santa', premium = true, playerClient = false, vip = true, pedModel = 'a_m_m_business_01' },
    },

    Destinations = {
        { label = 'Legion Square', coords = vector3(188.14, -892.16, 30.71) },
        { label = 'Vespucci Beach', coords = vector3(-1197.62, -1495.43, 4.38) },
        { label = 'Pillbox Hill', coords = vector3(305.58, -595.39, 43.28) },
        { label = 'Rockford Hills', coords = vector3(-687.29, -885.71, 24.50) },
        { label = 'Mirror Park', coords = vector3(1097.05, -776.56, 58.25) },
        { label = 'LSIA Terminal', coords = vector3(-1037.31, -2737.58, 20.17) },
        { label = 'Sandy Shores Airfield', coords = vector3(1740.95, 3277.11, 41.09) },
    },

    PickupPoints = {
        vector3(425.45, -979.53, 29.44),   -- Pillbox Medical
        vector3(-75.68, -1102.94, 26.42),  -- MRPD
        vector3(195.83, -933.71, 24.15),   -- Downtown
        vector3(457.06, -968.28, 29.44),   -- Pillbox East
        vector3(-548.64, -895.21, 29.30),  -- Arcade
        vector3(111.18, -1938.54, 20.81),  -- South LS
        vector3(-456.53, -346.87, 36.73),  -- Rockford Hills
        vector3(1163.68, -800.25, 57.63),  -- Mirror Park
    },

    NPCLocations = {
        TakeLocations = {
            [1] = vector4(257.61, -380.57, 44.71, 340.5),
            [2] = vector4(-48.58, -790.12, 44.22, 340.5),
            [3] = vector4(240.06, -862.77, 29.73, 341.5),
            [4] = vector4(826.0, -1885.26, 29.32, 81.5),
            [5] = vector4(350.84, -1974.13, 24.52, 318.5),
            [6] = vector4(-229.11, -2043.16, 27.75, 233.5),
            [7] = vector4(-1053.23, -2716.2, 13.75, 329.5),
            [8] = vector4(-774.04, -1277.25, 5.15, 171.5),
            [9] = vector4(-1184.3, -1304.16, 5.24, 293.5),
            [10] = vector4(-1321.28, -833.8, 16.95, 140.5),
            [11] = vector4(-1613.99, -1015.82, 13.12, 342.5),
            [12] = vector4(-1392.74, -584.91, 30.24, 32.5),
            [13] = vector4(-515.19, -260.29, 35.53, 201.5),
            [14] = vector4(-760.84, -34.35, 37.83, 208.5),
            [15] = vector4(-1284.06, 297.52, 64.93, 148.5),
            [16] = vector4(-808.29, 828.88, 202.89, 200.5),
        },

        DeliverLocations = {
            [1] = vector4(-1074.39, -266.64, 37.75, 117.5),
            [2] = vector4(-1412.07, -591.75, 30.38, 298.5),
            [3] = vector4(-679.9, -845.01, 23.98, 269.5),
            [4] = vector4(-158.05, -1565.3, 35.06, 139.5),
            [5] = vector4(442.09, -1684.33, 29.25, 320.5),
            [6] = vector4(1120.73, -957.31, 47.43, 289.5),
            [7] = vector4(1238.85, -377.73, 69.03, 70.5),
            [8] = vector4(922.24, -2224.03, 30.39, 354.5),
            [9] = vector4(1920.93, 3703.85, 32.63, 120.5),
            [10] = vector4(1662.55, 4876.71, 42.05, 185.5),
            [11] = vector4(-9.51, 6529.67, 31.37, 136.5),
            [12] = vector4(-3232.7, 1013.16, 12.09, 177.5),
            [13] = vector4(-1604.09, -401.66, 42.35, 321.5),
            [14] = vector4(-586.48, -255.96, 35.91, 210.5),
            [15] = vector4(23.66, -60.23, 63.62, 341.5),
            [16] = vector4(550.3, 172.55, 100.11, 339.5),
            [17] = vector4(-1048.55, -2540.58, 13.69, 148.5),
            [18] = vector4(-9.55, -544.0, 38.63, 87.5),
            [19] = vector4(-7.86, -258.22, 46.9, 68.5),
            [20] = vector4(-743.34, 817.81, 213.6, 219.5),
            [21] = vector4(218.34, 677.47, 189.26, 359.5),
            [22] = vector4(263.2, 1138.81, 221.75, 203.5),
            [23] = vector4(220.64, -1010.81, 29.22, 160.5),
        },
    },

    PZLocations = {
        TakeLocations = {
            [1] = { coord = vector3(258.98, -377.9, 44.7), height = 17.6, width = 4.2, heading = 69, minZ = 43.75, maxZ = 45.55 },
            [2] = { coord = vector3(-50.06, -784.57, 44.16), height = 17.6, width = 4.2, heading = 62, minZ = 43.21, maxZ = 45.01 },
            [3] = { coord = vector3(238.93, -858.91, 29.67), height = 17.6, width = 4.2, heading = 71, minZ = 28.72, maxZ = 30.52 },
            [4] = { coord = vector3(823.4, -1882.96, 29.29), height = 17.6, width = 4.2, heading = 167, minZ = 28.34, maxZ = 30.14 },
            [5] = { coord = vector3(354.05, -1971.57, 24.43), height = 17.6, width = 4.2, heading = 236, minZ = 23.48, maxZ = 25.28 },
            [6] = { coord = vector3(-225.61, -2043.63, 27.62), height = 17.6, width = 4.2, heading = 143, minZ = 26.67, maxZ = 28.47 },
            [7] = { coord = vector3(-1048.72, -2714.2, 13.76), height = 17.6, width = 4.2, heading = 240, minZ = 12.81, maxZ = 14.61 },
            [8] = { coord = vector3(-776.15, -1280.37, 5.0), height = 17.6, width = 4.2, heading = 261, minZ = 4.05, maxZ = 5.85 },
            [9] = { coord = vector3(-1180.3, -1304.22, 5.15), height = 17.6, width = 4.2, heading = 205, minZ = 4.2, maxZ = 6.0 },
            [10] = { coord = vector3(-1326.52, -833.32, 16.85), height = 17.6, width = 4.2, heading = 225, minZ = 15.9, maxZ = 17.7 },
            [11] = { coord = vector3(-1610.24, -1015.33, 13.07), height = 17.6, width = 4.2, heading = 227, minZ = 12.12, maxZ = 13.92 },
            [12] = { coord = vector3(-1396.85, -583.72, 30.08), height = 17.6, width = 4.2, heading = 299, minZ = 29.13, maxZ = 30.93 },
            [13] = { coord = vector3(-513.06, -263.2, 35.43), height = 17.6, width = 4.2, heading = 293, minZ = 34.48, maxZ = 36.28 },
            [14] = { coord = vector3(-756.46, -35.84, 37.69), height = 17.6, width = 4.2, heading = 297, minZ = 36.74, maxZ = 38.54 },
            [15] = { coord = vector3(-1285.33, 293.67, 64.83), height = 17.6, width = 4.2, heading = 241, minZ = 63.88, maxZ = 65.68 },
            [16] = { coord = vector3(-806.68, 825.2, 202.81), height = 21.2, width = 4.2, heading = 276, minZ = 200.46, maxZ = 204.66 },
        },

        DropLocations = {
            [1] = { coord = vector3(-1073.21, -265.35, 37.35), height = 21.2, width = 4.2, heading = 296, minZ = 35.0, maxZ = 39.2 },
            [2] = { coord = vector3(-1411.45, -590.98, 29.99), height = 21.2, width = 4.2, heading = 299, minZ = 27.64, maxZ = 31.84 },
            [3] = { coord = vector3(-678.68, -845.54, 23.53), height = 21.2, width = 4.2, heading = 269, minZ = 21.18, maxZ = 25.38 },
            [4] = { coord = vector3(-159.11, -1565.46, 34.69), height = 21.2, width = 4.2, heading = 321, minZ = 32.34, maxZ = 36.54 },
            [5] = { coord = vector3(442.12, -1685.31, 28.85), height = 21.2, width = 4.2, heading = 321, minZ = 26.5, maxZ = 30.7 },
            [6] = { coord = vector3(1120.51, -958.97, 46.83), height = 21.2, width = 4.2, heading = 286, minZ = 44.48, maxZ = 48.68 },
            [7] = { coord = vector3(1240.79, -377.77, 68.61), height = 21.2, width = 4.2, heading = 249, minZ = 66.26, maxZ = 70.46 },
            [8] = { coord = vector3(923.66, -2226.07, 29.98), height = 21.2, width = 4.2, heading = 354, minZ = 27.63, maxZ = 31.83 },
            [9] = { coord = vector3(1920.15, 3701.6, 32.26), height = 21.2, width = 4.2, heading = 299, minZ = 29.91, maxZ = 34.11 },
            [10] = { coord = vector3(1661.91, 4875.87, 41.66), height = 21.2, width = 4.2, heading = 8, minZ = 39.31, maxZ = 43.51 },
            [11] = { coord = vector3(-9.46, 6529.92, 30.95), height = 21.2, width = 4.2, heading = 314, minZ = 28.6, maxZ = 32.8 },
            [12] = { coord = vector3(-3233.12, 1010.33, 11.72), height = 21.2, width = 4.2, heading = 357, minZ = 9.37, maxZ = 13.57 },
            [13] = { coord = vector3(-1604.11, -401.71, 41.95), height = 21.2, width = 4.2, heading = 322, minZ = 39.6, maxZ = 43.8 },
            [14] = { coord = vector3(-586.48, -255.96, 36.53), height = 21.2, width = 4.2, heading = 31, minZ = 34.68, maxZ = 37.48 },
            [15] = { coord = vector3(23.51, -60.47, 63.2), height = 21.2, width = 4.2, heading = 156, minZ = 60.55, maxZ = 65.75 },
            [16] = { coord = vector3(550.26, 172.54, 99.71), height = 21.2, width = 4.2, heading = 161, minZ = 98.51, maxZ = 100.91 },
            [17] = { coord = vector3(-1048.62, -2540.53, 13.3), height = 21.2, width = 4.2, heading = 151, minZ = 12.9, maxZ = 14.9 },
            [18] = { coord = vector3(-10.06, -544.39, 38.28), height = 21.2, width = 4.2, heading = 91, minZ = 36.28, maxZ = 39.88 },
            [19] = { coord = vector3(-7.91, -258.19, 46.49), height = 21.2, width = 4.2, heading = 71, minZ = 45.29, maxZ = 47.69 },
            [20] = { coord = vector3(-743.03, 818.9, 213.16), height = 21.2, width = 4.2, heading = 38, minZ = 211.96, maxZ = 214.36 },
            [21] = { coord = vector3(218.25, 677.55, 188.87), height = 21.2, width = 4.2, heading = 163, minZ = 187.67, maxZ = 190.07 },
            [22] = { coord = vector3(264.47, 1138.41, 221.36), height = 21.2, width = 4.2, heading = 203, minZ = 220.16, maxZ = 222.56 },
            [23] = { coord = vector3(220.47, -1010.7, 28.82), height = 21.2, width = 4.2, heading = 158, minZ = 28.02, maxZ = 30.42 },
        },
    },

    NpcSkins = {
        [1] = {
            'a_f_m_skidrow_01', 'a_f_m_soucentmc_01', 'a_f_m_soucent_01', 'a_f_m_soucent_02', 'a_f_m_tourist_01',
            'a_f_m_trampbeac_01', 'a_f_m_tramp_01', 'a_f_o_genstreet_01', 'a_f_o_indian_01', 'a_f_o_ktown_01',
            'a_f_o_salton_01', 'a_f_o_soucent_01', 'a_f_o_soucent_02', 'a_f_y_beach_01', 'a_f_y_bevhills_01',
            'a_f_y_bevhills_02', 'a_f_y_bevhills_03', 'a_f_y_bevhills_04', 'a_f_y_business_01', 'a_f_y_business_02',
        },
        [2] = {
            'ig_barry', 'ig_bestmen', 'ig_beverly', 'ig_car3guy1', 'ig_car3guy2', 'ig_casey', 'ig_chef', 'ig_chengsr',
            'ig_chrisformage', 'ig_clay', 'ig_claypain', 'ig_cletus', 'ig_dale', 'ig_dreyfuss', 'ig_fbisuit_01',
            'ig_floyd', 'ig_groom', 'ig_hao', 'ig_hunter', 'csb_prolsec', 'a_m_y_business_01', 'a_m_y_business_02',
            'a_m_m_business_01', 'a_m_m_bevhills_01', 'a_m_m_beach_01', 'a_m_m_beach_02',
        },
    },

    RarePremiumChance = 0.12,
    PlayerClientChance = 0.08,
    VIPChance = 0.10,  -- 10% chance for Michael De Santa

    -- NPC Dialogues
    NPCDialogues = {
        greeting = {
            'Thanks for stopping!',
            'Finally, a taxi!',
            'Oh, there you are!',
            'I appreciate it!',
            'Nice ride.',
        },
        inTrip = {
            'How\'s your day going?',
            'This is a nice route.',
            'The weather is great today.',
            'Do you know this area well?',
            'I love this city.',
        },
        phoneCall = {
            'Yeah, I\'ll be there soon...',
            'Just give me a minute.',
            'No, I\'m on my way now.',
            'I\'ll call you back.',
            'Can you hold on a second?',
        },
        destination = {
            'This is perfect, thanks!',
            'Right here is great!',
            'This works, thank you.',
            'Perfect drop-off point.',
            'Thanks for the ride!',
        },
    },
}
