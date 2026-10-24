Config = {}

-- Framework (QBCore by default)
Config.Framework = 'qbcore' -- 'qbcore' or 'esx'

-- Computer Props (all computer and monitor props for testing)
Config.ComputerProps = {
    -- Desktop Computers
    `prop_pc_01a`,
    `prop_pc_02a`,
    `prop_pc_03a`,
    `prop_pc_04a`,
    
    -- Laptops
    `prop_laptop_01a`,
    `prop_laptop_02a`,
    `prop_laptop_lester`,
    `prop_laptop_lester2`,
    `prop_laptop_jimmy`,
    `hei_prop_hst_laptop`,
    `p_laptop_02_s`,
    `prop_cs_laptop_01`,
    
    -- Monitors
    `prop_monitor_01a`,
    `prop_monitor_01b`,
    `prop_monitor_02a`,
    `prop_cs_monitor`,
    `prop_monitor_w_14`,
    `prop_monitor_w_large`,
    
    -- Office Computers
    `v_serv_ct_monitor01`,
    `v_serv_ct_monitor02`,
    `v_serv_ct_monitor03`,
    `v_serv_ct_monitor05`,
    `p_cs_monitor_03`,
    `prop_trev_tv_01`,
}

-- Target System
Config.TargetSystem = 'qb-target' -- 'ox_target' or 'qb-target'

-- Interaction Settings
Config.UseThirdEye = true -- Set to false to use keybind instead (fallback if target fails)
Config.InteractionKey = 38 -- E key (only used if UseThirdEye is false)
Config.InteractionDistance = 2.5 -- Distance in meters

-- Computer profile routing.
-- `default` profile = standard pf-computer apps only.
-- `mayor` profile = standard apps + government external apps.
Config.MayorComputer = {
    Enabled = true,

    -- `prop` = detect mayor terminal by interacted prop model
    -- `coords` = detect mayor terminal by world position
    DetectionMode = 'prop',

    -- Testing default: use dedicated mayor prop model.
    PropModels = {
        `prop_pc_02a`
    },

    -- Optional coords mode support.
    Coords = {
        -- vector3(-76.94, -804.99, 243.4)
    },
    CoordRadius = 2.0,

    -- If mode is `prop`, allow coords check as a fallback.
    UseCoordsFallback = false
}

-- Jobs that have access to certain features
Config.GovJobs = {
    'police',
    'sheriff',
    'ambulance',
    'government',
    'lawyer',
    'judge',
    'mayor'
}

-- Business Manager Configuration
Config.BusinessManager = {
    -- Enable/disable business manager app
    Enabled = true,

    -- Company accounts are the job's bank account. On first start after the update, old company
    -- balances from data/pc_data.json are moved into the bank once. By default only the part players
    -- paid in moves (deposits - withdrawals - supply orders); the "sale" part was already paid to the
    -- bank by the register, or never paid by anyone. Set true to move the whole old balance instead.
    MigrateSalesBalance = false,

    -- Allow any job boss to access Business Manager
    AllowAllBosses = true,

    -- Global wage caps per grade (mayor can adjust)
    WageCaps = {
        ['0'] = 100,
        ['1'] = 150,
        ['2'] = 200,
        ['3'] = 250,
        ['4'] = 300
    },
    
    -- Jobs that can access business manager (job name and minimum grade)
    AllowedJobs = {
        ['burgershot'] = {
            minGrade = 3, -- Manager and above
            businessType = 'restaurant',
            businessName = 'Burger Shot',
            blipIcon = 52,  -- Food/Burger icon
            blipColor = 60  -- Orange/Yellow food color
        },
        ['pf-burgetshot'] = {
            minGrade = 3,
            businessType = 'restaurant',
            businessName = 'Burger Shot',
            blipIcon = 52,
            blipColor = 60  -- Orange/Yellow food color
        },
        ['pizzathis'] = {
            minGrade = 3,
            businessType = 'restaurant',
            businessName = 'Pizza This',
            blipIcon = 52,
            blipColor = 60  -- Orange/Yellow food color
        },
        ['popsdiner'] = {
            minGrade = 3,
            businessType = 'restaurant',
            businessName = 'Pops Diner',
            blipIcon = 52,
            blipColor = 60  -- Orange/Yellow food color
        },
        ['uwu'] = {
            minGrade = 3,
            businessType = 'restaurant',
            businessName = 'UwU Cafe',
            blipIcon = 52,
            blipColor = 60  -- Orange/Yellow food color
        },
        ['mechanic'] = {
            minGrade = 2, -- Senior mechanic and above
            businessType = 'mechanic',
            businessName = 'LS Customs',
            blipIcon = 227,  -- Wrench icon
            blipColor = 4    -- Blue for mechanics
        },
        ['mechanic2'] = {
            minGrade = 2,
            businessType = 'mechanic',
            businessName = 'Harmony Customs',
            blipIcon = 227,
            blipColor = 4    -- Blue for mechanics
        },
        ['mechanic3'] = {
            minGrade = 2,
            businessType = 'mechanic',
            businessName = 'Airport Customs',
            blipIcon = 227,
            blipColor = 4    -- Blue for mechanics
        },
        ['bennys'] = {
            minGrade = 2,
            businessType = 'mechanic',
            businessName = "Benny's Original Motor Works",
            blipIcon = 227,
            blipColor = 4    -- Blue for mechanics
        },
        ['beeker'] = {
            minGrade = 2,
            businessType = 'mechanic',
            businessName = "Beeker's Garage",
            blipIcon = 227,
            blipColor = 4    -- Blue for mechanics
        },
        ['cardealer'] = {
            minGrade = 2,
            businessType = 'dealership',
            businessName = 'Premium Deluxe Motorsport',
            blipColor = 5    -- Purple for dealership
        },
        ['realestate'] = {
            minGrade = 1,
            businessType = 'realestate',
            businessName = 'Dynasty 8 Real Estate',
            blipColor = 5    -- Purple for realestate
        },
        ['bar'] = {
            minGrade = 2,
            businessType = 'bar',
            businessName = 'Yellow Jack Inn',
            blipColor = 60   -- Yellow/Gold for bar
        },
        ['nightclub'] = {
            minGrade = 3,
            businessType = 'nightclub',
            businessName = 'Galaxy Nightclub',
            blipColor = 27   -- Purple for nightclub
        }
    },

    DefaultBlip = {
        sprite = 1,
        scale = 0.6,
        shortRange = true
    },
    
    -- Business type configurations
    BusinessTypes = {
        business = {
            name = 'Business',
            icon = '🏢',
            features = {
                'analytics',
                'employee_management',
                'transactions',
                'inventory',
                'settings'
            }
        },
        restaurant = {
            name = 'Restaurant',
            icon = '🍔',
            features = {
                'analytics',
                'menu_management',
                'employee_management',
                'inventory',
                'transactions',
                'promotions',
                'customer_reviews'
            },
            menuCategories = {
                'Burgers', 'Sides', 'Drinks', 'Desserts', 'Specials', 'Combos'
            },
            ingredients = {
                -- Proteins
                { name = 'Beef Patty', category = 'protein', cost = 2.50 },
                { name = 'Chicken Breast', category = 'protein', cost = 2.00 },
                { name = 'Veggie Patty', category = 'protein', cost = 1.50 },
                { name = 'Bacon', category = 'protein', cost = 1.00 },
                
                -- Vegetables
                { name = 'Lettuce', category = 'vegetable', cost = 0.25 },
                { name = 'Tomato', category = 'vegetable', cost = 0.30 },
                { name = 'Onion', category = 'vegetable', cost = 0.20 },
                { name = 'Pickles', category = 'vegetable', cost = 0.25 },
                { name = 'Jalapeños', category = 'vegetable', cost = 0.35 },
                
                -- Cheese & Sauces
                { name = 'Cheddar Cheese', category = 'cheese', cost = 0.50 },
                { name = 'Swiss Cheese', category = 'cheese', cost = 0.60 },
                { name = 'Ketchup', category = 'sauce', cost = 0.10 },
                { name = 'Mustard', category = 'sauce', cost = 0.10 },
                { name = 'Mayo', category = 'sauce', cost = 0.10 },
                { name = 'BBQ Sauce', category = 'sauce', cost = 0.15 },
                
                -- Buns & Extras
                { name = 'Regular Bun', category = 'bun', cost = 0.50 },
                { name = 'Sesame Bun', category = 'bun', cost = 0.60 },
                { name = 'Brioche Bun', category = 'bun', cost = 0.75 }
            }
        },
        
        mechanic = {
            name = 'Auto Repair Shop',
            icon = '🔧',
            features = {
                'analytics',
                'service_management',
                'employee_management',
                'inventory',
                'transactions',
                'vehicle_queue'
            },
            serviceCategories = {
                'Repairs', 'Upgrades', 'Customization', 'Maintenance', 'Towing'
            },
            parts = {
                { name = 'Engine Oil', category = 'fluids', cost = 25.00 },
                { name = 'Brake Pads', category = 'brakes', cost = 75.00 },
                { name = 'Air Filter', category = 'engine', cost = 35.00 },
                { name = 'Spark Plugs', category = 'engine', cost = 50.00 },
                { name = 'Battery', category = 'electrical', cost = 150.00 },
                { name = 'Tire Set', category = 'tires', cost = 400.00 },
                { name = 'Turbo Kit', category = 'performance', cost = 2500.00 }
            }
        },
        
        dealership = {
            name = 'Car Dealership',
            icon = '🚗',
            features = {
                'analytics',
                'inventory_management',
                'employee_management',
                'transactions',
                'commission_tracking',
                'test_drives'
            }
        },
        
        realestate = {
            name = 'Real Estate',
            icon = '🏠',
            features = {
                'analytics',
                'property_listings',
                'employee_management',
                'transactions',
                'commission_tracking',
                'showings'
            }
        },
        
        bar = {
            name = 'Bar',
            icon = '🍺',
            features = {
                'analytics',
                'menu_management',
                'employee_management',
                'inventory',
                'transactions',
                'events'
            },
            menuCategories = {
                'Beer', 'Wine', 'Cocktails', 'Shots', 'Non-Alcoholic', 'Food'
            }
        },
        
        nightclub = {
            name = 'Nightclub',
            icon = '🎵',
            features = {
                'analytics',
                'menu_management',
                'employee_management',
                'inventory',
                'transactions',
                'events',
                'vip_management'
            },
            menuCategories = {
                'VIP Bottles', 'Cocktails', 'Beer', 'Shots', 'Energy Drinks'
            }
        }
    }
}

Config.Browser = {
    HomeUrl = 'https://start.ls',
    DefaultDomainPrice = 2500,
    FeaturedSites = {
        { name = 'Government Portal', url = 'los-santos.gov', description = 'Official city portal for laws, taxes, notices, and departments.' },
        { name = 'Domains', url = 'domains.ls', description = 'Purchase domains, manage ownership, and launch your websites.' },
        { name = 'Business Services', url = 'services.ls', description = 'Guides, permits, deliveries, and public service information.' },
        { name = 'Marketplace', url = 'market.ls', description = 'Find commerce, services, and player-run storefronts.' }
    },
    DefaultBookmarks = {
        { name = 'Start', url = 'start.ls' },
        { name = 'Government Portal', url = 'los-santos.gov' },
        { name = 'Domains', url = 'domains.ls' },
        { name = 'Services', url = 'services.ls' }
    },
    Domains = {
        Reserved = {
            ['los-santos.gov'] = { type = 'government' },
            ['gov.ls'] = { type = 'government' },
            ['cityhall.ls'] = { type = 'government' },
            ['start.ls'] = { type = 'system' },
            ['search.ls'] = { type = 'system' },
            ['domains.ls'] = { type = 'system' },
            ['services.ls'] = { type = 'system' },
            ['market.ls'] = { type = 'system' }
        }
    },
    Shortcuts = {
        { name = 'Government Portal', url = 'los-santos.gov' },
        { name = 'Domains', url = 'domains.ls' },
        { name = 'Services', url = 'services.ls' },
        { name = 'Marketplace', url = 'market.ls' },
        { name = 'News', url = 'news.ls' },
        { name = 'Business', url = 'business.ls' }
    },
    Assistant = {
        DefaultReply = 'I could not match that request exactly. Try a website address, a department name, or a place like police station, hospital, city hall, deliveries, taxes, or laws.',
        Intents = {
            {
                id = 'delivery_help',
                keywords = { 'delivery', 'deliveries', 'supplies', 'ordering supplies', 'business supplies', 'stock order' },
                title = 'Deliveries and supply ordering',
                body = 'Open your business tools and use the supplies section to review the catalog, create an order, and assign a delivery location for pickup.',
                url = 'services.ls#deliveries'
            },
            {
                id = 'laws_help',
                keywords = { 'law', 'laws', 'fine', 'fines', 'ordinance', 'municipal code', 'taxes' },
                title = 'Government records',
                body = 'Open the Government Portal to review current laws, public notices, and active tax schedules.',
                url = 'los-santos.gov'
            },
            {
                id = 'domain_help',
                keywords = { 'domain', 'website', 'site', 'build website', 'buy domain', 'transfer domain' },
                title = 'Domains and websites',
                body = 'Open Domains to purchase a domain, transfer ownership, and edit your website pages and modules.',
                url = 'domains.ls'
            }
        },
        Locations = {
            { id = 'city_hall', name = 'City Hall', description = 'Alta Street civic center.', street = 'Alta Street', keywords = { 'city hall', 'government', 'mayor office', 'hall' }, coords = { x = -545.0, y = -204.0, z = 38.2 } },
            { id = 'mrpd', name = 'Mission Row Police Department', description = 'Main city police station.', street = 'Sinner Street', keywords = { 'police station', 'police', 'mrpd', 'cop shop' }, coords = { x = 425.1, y = -979.5, z = 30.7 } },
            { id = 'pillbox', name = 'Pillbox Hospital', description = 'Primary hospital in the city.', street = 'Elgin Avenue', keywords = { 'hospital', 'ems', 'medical', 'pillbox' }, coords = { x = 307.4, y = -595.2, z = 43.3 } }
        }
    },
    WebsiteTemplates = {
        restaurant = {
            name = 'Restaurant',
            pages = {
                { slug = 'home', label = 'Home' },
                { slug = 'menu', label = 'Menu' },
                { slug = 'about', label = 'About' }
            },
            modules = { 'hero', 'text', 'cards', 'links', 'image' }
        },
        services = {
            name = 'Services',
            pages = {
                { slug = 'home', label = 'Home' },
                { slug = 'services', label = 'Services' },
                { slug = 'contact', label = 'Contact' }
            },
            modules = { 'hero', 'text', 'cards', 'links', 'image', 'callout' }
        }
    }
}

return Config
