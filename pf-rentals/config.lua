Config = {}

-- Debug Mode
Config.Debug = true

-- Rental Check Interval (in milliseconds)
Config.CheckInterval = 60000 -- Check every 60 seconds

-- Rental Locations
Config.RentalLocations = {
    {
        name = "Airport Rentals",
        coords = vector3(-1034.19, -2733.60, 13.76),
        heading = 328.90,
        blip = {
            enabled = true,
            sprite = 56,
            color = 3,
            scale = 0.8,
            label = "Vehicle Rentals"
        },
        ped = {
            model = "a_m_y_business_01",
            scenario = "WORLD_HUMAN_CLIPBOARD"
        },
        spawnPoint = vector4(-1028.22, -2725.72, 13.76, 240.0)
    },
    {
        name = "Downtown Rentals",
        coords = vector3(111.24, -1081.87, 29.19),
        heading = 0.0,
        blip = {
            enabled = true,
            sprite = 56,
            color = 3,
            scale = 0.8,
            label = "Vehicle Rentals"
        },
        ped = {
            model = "a_f_y_business_02",
            scenario = "WORLD_HUMAN_CLIPBOARD"
        },
        spawnPoint = vector4(106.87, -1089.61, 29.30, 340.0)
    },
    {
        name = "Sandy Shores Rentals",
        coords = vector3(1737.59, 3710.20, 34.14),
        heading = 20.0,
        blip = {
            enabled = true,
            sprite = 56,
            color = 3,
            scale = 0.8,
            label = "Vehicle Rentals"
        },
        ped = {
            model = "a_m_m_hillbilly_01",
            scenario = "WORLD_HUMAN_CLIPBOARD"
        },
        spawnPoint = vector4(1729.24, 3713.12, 34.18, 200.0)
    },
    {
        name = "Paleto Bay Rentals",
        coords = vector3(107.35, 6611.77, 31.87),
        heading = 45.0,
        blip = {
            enabled = true,
            sprite = 56,
            color = 3,
            scale = 0.8,
            label = "Vehicle Rentals"
        },
        ped = {
            model = "a_m_o_beach_01",
            scenario = "WORLD_HUMAN_CLIPBOARD"
        },
        spawnPoint = vector4(110.52, 6607.95, 31.87, 220.0)
    }
}

-- Available Rental Vehicles
Config.RentalVehicles = {
    {
        id = 1,
        brand = 'Grotti',
        model = 'turismor',
        displayName = 'Grotti Turismo R',
        category = 'sports',
        price = 500,
        image = 'screenshot' -- Will be handled by screenshot-basic
    },
    {
        id = 2,
        brand = 'Vapid',
        model = 'dominator3',
        displayName = 'Vapid Dominator GTX',
        category = 'muscle',
        price = 400,
        image = 'screenshot'
    },
    {
        id = 3,
        brand = 'Coil',
        model = 'voltic',
        displayName = 'Coil Voltic',
        category = 'sports',
        price = 600,
        image = 'screenshot'
    },
    {
        id = 4,
        brand = 'Declasse',
        model = 'granger',
        displayName = 'Declasse Granger',
        category = 'trucks',
        price = 300,
        image = 'screenshot'
    },
    {
        id = 5,
        brand = 'Benefactor',
        model = 'schafter2',
        displayName = 'Benefactor Schafter',
        category = 'sedan',
        price = 350,
        image = 'screenshot'
    },
    {
        id = 6,
        brand = 'BF',
        model = 'bfinjection',
        displayName = 'BF Injection Dune Buggy',
        category = 'offroad',
        price = 280,
        image = 'screenshot'
    },
    {
        id = 7,
        brand = 'Western',
        model = 'bagger',
        displayName = 'Western Bagger',
        category = 'motorcycles',
        price = 200,
        image = 'screenshot'
    },
    {
        id = 8,
        brand = 'Pfister',
        model = '811',
        displayName = 'Pfister 811',
        category = 'sports',
        price = 750,
        image = 'screenshot'
    },
    {
        id = 9,
        brand = 'Karin',
        model = 'sultan',
        displayName = 'Karin Sultan',
        category = 'sports',
        price = 400,
        image = 'screenshot'
    },
    {
        id = 10,
        brand = 'Vapid',
        model = 'minivan',
        displayName = 'Vapid Minivan',
        category = 'vans',
        price = 250,
        image = 'screenshot'
    },
    {
        id = 11,
        brand = 'Declasse',
        model = 'burrito3',
        displayName = 'Declasse Burrito',
        category = 'vans',
        price = 280,
        image = 'screenshot'
    },
    {
        id = 12,
        brand = 'Dinka',
        model = 'blista',
        displayName = 'Dinka Blista',
        category = 'compacts',
        price = 200,
        image = 'screenshot'
    }
}

-- Payment Methods Accepted
Config.PaymentMethods = {
    cash = true,
    bank = true
}

-- Maximum Rental Duration (in days)
Config.MaxRentalDuration = 30

-- Minimum Rental Duration (in days)
Config.MinRentalDuration = 1

-- Notification Settings
Config.UseQBNotifications = true -- Use QB-Core notifications

-- Vehicle Key System
Config.UseQBVehicleKeys = true -- Give keys using qb-vehiclekeys or qb-core

-- Screenshot Settings
Config.UseScreenshotBasic = true -- Use screenshot-basic for vehicle images
