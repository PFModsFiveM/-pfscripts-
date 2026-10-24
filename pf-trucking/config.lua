Config = Config or {}

-- Enable to print server-side debug logs for contract generation and depot work trucks.
Config.Debug = false

-- NPC job generation tuning
Config.NpcJobs = {
    Enabled = true,
    TargetAvailable = 18,      -- keep this many available jobs in the pool
    MaxAvailable = 30,         -- hard cap
    RefreshSeconds = 90,       -- replenish interval
    PayoutBase = 250,
    PayoutPerMile = 85,
    PayoutVariance = 220,
    RoadFactor = 1.25,         -- multiplier applied to straight-line distance
}

-- Minimal location list (label + coords). Used for distance and optional GPS.
Config.NpcLocations = {
    { label = 'Docks (Elysian Island)', coords = vector3(-186.7, -2435.5, 6.0) },
    { label = 'Vespucci', coords = vector3(-1218.5, -1439.2, 4.3) },
    { label = 'Downtown', coords = vector3(235.5, -873.2, 30.5) },
    { label = 'Sandy Shores', coords = vector3(1700.4, 3290.2, 41.1) },
    { label = 'Paleto Bay', coords = vector3(-128.7, 6458.4, 31.5) },
    { label = 'Oil Refinery', coords = vector3(595.2, 2725.5, 41.3) },
    { label = 'Quarry', coords = vector3(2950.5, 2789.9, 40.5) },
    { label = 'Grapeseed', coords = vector3(2564.6, 4680.8, 34.1) },
    { label = 'LSIA Cargo', coords = vector3(-1037.9, -2757.4, 13.8) },
    { label = 'Mirror Park', coords = vector3(1152.7, -483.2, 66.2) },
}

Config.NpcTrailerTypes = {
    'Box Trailer',
    'Flatbed',
    'Tanker',
}

-- Map the requiredTrailer label to an actual GTA trailer model.
-- These are the vehicles that will be spawned at the pickup.
Config.Trailers = {
    ['Box Trailer'] = 'trailers',
    ['Flatbed'] = 'trflat',
    ['Tanker'] = 'tanker',
}

-- Spawn/UX settings for the job trailer at pickup.
Config.JobTrailer = {
    SpawnClearRadius = 6.0,
    NodeSearchRadius = 80.0,
    MaxNodeAttempts = 20,
    OutlineColor = { 1, 255, 158, 255 },

    -- Outline is not reliable on some builds for vehicles.
    -- These settings drive the in-world marker + optional map blip used to identify the correct trailer.
    Highlight = {
        Enabled = true,
        MarkerColor = { 1, 255, 158, 220 },
        MarkerRange = 250.0,
        ShowBlip = true,
        BlipSprite = 479,
        BlipColor = 2,
        BlipScale = 0.75,
    },
}

Config.NpcCargoTypes = {
    { title = 'Food Freight', cargo = 'Refrigerated goods', minQty = 10, maxQty = 28 },
    { title = 'Construction Supply', cargo = 'Cement pallets', minQty = 12, maxQty = 34 },
    { title = 'Retail Restock', cargo = 'Mixed consumer goods', minQty = 8, maxQty = 22 },
    { title = 'Fuel Transfer', cargo = 'Diesel (regulated)', minQty = 18, maxQty = 36 },
    { title = 'Medical Run', cargo = 'Medical supplies', minQty = 6, maxQty = 18 },
}

-- Server-side delivery checks. The server only pays when the driver is really at the drop-off
-- (or the depot return point for work trucks) and enough time has passed since the contract was
-- claimed. Positions are read server-side, which needs OneSync (on by default on current servers).
Config.Delivery = {
    DropoffRadius = 80.0,       -- metres from the final stop for "delivered"
    ReturnRadius = 35.0,        -- metres from a depot returnCoords to hand back a work truck
    MinSeconds = 45,            -- never faster than this after claiming
    MaxAverageSpeed = 45.0,     -- m/s (~100 mph): pickup->drop distance / this = minimum trip time
}

-- Work-truck rental (for non-owners using the depot computer)
Config.WorkTruck = {
    Enabled = true,
    WarpDriverOnSpawn = true,
    SpawnClearRadius = 6.0,

    -- When a driver rents/sources a depot work truck, we deduct this amount from the contract payout.
    -- This makes renting part of the job economics rather than an upfront cash charge.
    RentalFee = 100,

    -- Keep prefix short; plates are limited to 8 chars.
    PlatePrefix = 'WK',

    -- Vehicle spawncodes for the company work trucks.
    Models = {
        'phantom',
        'packer',
        'hauler',
    },

    -- Depot spawn points (vector4: x, y, z, heading)
    -- Default uses the same industrial area as pf-jobgarages 'East Customs Fleet'.
    Depots = {
        {
            id = 'east_customs',
            label = 'East Customs Depot',

            -- Where the work truck is spawned/pawned.
            spawnCoords = vector4(859.77, -2127.05, 30.54, 350.35),

            -- Depot computer position (a prop is spawned here).
            -- Interact to open pf-computer, then open Trucking.
            computerCoords = vector4(857.95, -2124.60, 30.54, 170.0),
            computerProp = 'prop_laptop_01a',

            -- Dropoff/return point for the work truck.
            returnCoords = vector4(863.20, -2128.10, 30.54, 350.0),
        },
    },
}

-- License system configuration
Config.Licenses = {
    {
        id = 'fragile',
        name = 'Fragile Cargo License',
        requiredLevel = 3,
        cost = 5000,
        payoutMultiplier = 1.25
    },
    {
        id = 'explosive',
        name = 'Explosive Materials License',
        requiredLevel = 5,
        cost = 15000,
        payoutMultiplier = 1.50
    },
    {
        id = 'radioactive',
        name = 'Radioactive Materials License',
        requiredLevel = 8,
        cost = 25000,
        payoutMultiplier = 1.75
    },
    {
        id = 'hazmat',
        name = 'Hazmat License',
        requiredLevel = 10,
        cost = 30000,
        payoutMultiplier = 2.0
    }
}

-- Player-owned business job generation
Config.PlayerOwnedBusinesses = {
    Enabled = true,
    PayoutBonus = 0.15,  -- 15% extra payment
    Businesses = {
        ['burgershot'] = {
            locations = {
                vector3(-1193.13, -892.97, 13.98),  -- Vespucci
            },
            cargoTypes = {
                { title = 'Food Supply Run', cargo = 'Burger ingredients', minQty = 15, maxQty = 30 },
                { title = 'Beverage Delivery', cargo = 'Soft drinks', minQty = 20, maxQty = 40 },
            }
        },
        ['247'] = {
            locations = {
                vector3(25.74, -1347.32, 29.5),  -- Mirror Park 24/7
                vector3(1961.0, 3740.0, 32.34),  -- Sandy Shores 24/7
            },
            cargoTypes = {
                { title = 'Store Stock', cargo = 'Mixed retail goods', minQty = 10, maxQty = 25 },
                { title = 'Electronics Shipment', cargo = 'Electronics', minQty = 8, maxQty = 20 },
            }
        },
        ['smoking'] = {
            locations = {
                vector3(-503.46, 278.0, 83.32),  -- SmoKing
            },
            cargoTypes = {
                { title = 'Vape Supply', cargo = 'Vape products', minQty = 12, maxQty = 24 },
            }
        }
    }
}

-- XP and leveling configuration
Config.Experience = {
    XPPerJob = 50,      -- Base XP per completed job
    XPPerMile = 5,      -- XP per mile driven
    XPPerLevel = 1000,  -- XP required per level
    MaxLevel = 20
}

-- Special cargo types requiring licenses
Config.SpecialCargo = {
    {
        title = 'Fragile Glassware',
        cargo = 'Crystal glassware',
        requiredLicense = 'fragile',
        minQty = 5,
        maxQty = 15,
        payoutMultiplier = 1.25
    },
    {
        title = 'Explosive Transport',
        cargo = 'Mining explosives',
        requiredLicense = 'explosive',
        minQty = 8,
        maxQty = 20,
        payoutMultiplier = 1.50
    },
    {
        title = 'Medical Isotopes',
        cargo = 'Radioactive medical supplies',
        requiredLicense = 'radioactive',
        minQty = 3,
        maxQty = 10,
        payoutMultiplier = 1.75
    },
    {
        title = 'Hazardous Chemicals',
        cargo = 'Industrial chemicals',
        requiredLicense = 'hazmat',
        minQty = 10,
        maxQty = 25,
        payoutMultiplier = 2.0
    }
}
