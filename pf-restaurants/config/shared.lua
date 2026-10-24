Config = {}

-- Core Settings
Config.Debug = false
Config.UseTarget = true -- qb-target/ox_target
Config.TargetScript = 'qb-target' -- 'qb-target' or 'ox_target'
Config.Inventory = 'qb-inventory' -- 'qb-inventory' or 'ox_inventory'

-- Timings (milliseconds)
Config.Timings = {
    StationUpdateInterval = 500, -- How often to update station progress
    RenderDistance = 50.0, -- Max distance to render 3D timers
    DUIActivationRange = 30.0, -- Range to activate DUI screens
    HygieneUpdateInterval = 60000, -- 1 minute
    SpoilageCheckInterval = 300000, -- 5 minutes
    EquipmentDegradationInterval = 600000, -- 10 minutes
}

-- Quality System
Config.Quality = {
    -- Doneness windows (as percentage of cook time)
    Rare = {min = 0.60, max = 0.75},
    MediumRare = {min = 0.75, max = 0.85},
    Medium = {min = 0.85, max = 0.95},
    WellDone = {min = 0.95, max = 1.10},
    Undercooked = {max = 0.60},
    Burnt = {min = 1.10},
    
    -- Quality penalties (0-100 scale)
    CleanlinessBase = 100, -- Base quality when clean
    CleanlinessPerPoint = 0.5, -- Quality loss per cleanliness point below 100
    ConditionPerPoint = 0.3, -- Quality loss per condition point below 100
    HygienePerPoint = 0.4, -- Quality loss per hygiene rating point
    
    -- Poison risk (0-1 scale)
    UndercookedRisk = 0.3,
    ExpiredLotRisk = 0.5,
    DirtyEquipmentRisk = 0.2,
    RoachesRisk = 0.4,
}

-- Hunger & Thirst System
Config.Hunger = {
    -- Base hunger fill per component type
    ComponentValues = {
        protein = 15, -- patties, bacon, etc
        carb = 12, -- buns, fries, pizza base
        vegetable = 5, -- lettuce, tomato, etc
        dairy = 8, -- cheese, milk
        fat = 10, -- oil, butter
        sugar = 6, -- for desserts
    },
    
    -- Modification multipliers
    RemoveIngredientPenalty = 0.05, -- 5% reduction per removed ingredient
    ExtraIngredientBonus = 1.0, -- Full value for added ingredients
    
    -- Quality affects hunger fill
    QualityMultiplier = true, -- High quality = more satisfying
    MaxQualityBonus = 1.2, -- Up to 20% more hunger fill at perfect quality
}

Config.Thirst = {
    ComponentValues = {
        water = 20,
        soda = 15,
        juice = 18,
        coffee = 12,
        milk = 10,
    },
}

-- Equipment Degradation
Config.Equipment = {
    -- Cleanliness degradation per use
    DegradationPerUse = {
        grill = 2,
        fryer = 3,
        chop = 1,
        slice = 1,
        assembly = 0.5,
        drink = 0.5,
        coffee = 1,
    },
    
    -- Condition degradation over time (per interval)
    ConditionDegradation = {
        grill = 0.5,
        fryer = 0.8,
        chop = 0.2,
        slice = 0.2,
        assembly = 0.1,
        drink = 0.3,
        coffee = 0.4,
    },
    
    -- Fryer specific
    FryerOilDegradationPerUse = 5,
    FryerOilChangeThreshold = 30, -- Below this, quality suffers significantly
    
    -- Ice machine specific
    IceDepletionPerUse = 10,
    IceRefillAmount = 100,
    
    -- Cleaning supplies consumption
    CleaningSupplyPerUse = 1,
    OilChangeQuantity = 1,
    IceRefillQuantity = 1,
}

-- Hygiene System
Config.Hygiene = {
    -- Dirt accumulation rate (per minute base)
    DirtAccumulationRate = 0.5,
    DirtPerOrder = 0.1,
    DirtPerCustomer = 0.05,
    
    -- Thresholds for spawning problems
    TrashSpawnThreshold = 30, -- Dirt level
    RoachSpawnThreshold = 50,
    MaxTrashProps = 10,
    MaxRoaches = 5,
    
    -- Health rating calculation (based on total hygiene score)
    HealthRatings = {
        {min = 90, rating = 'A', label = 'Excellent'},
        {min = 80, rating = 'B', label = 'Good'},
        {min = 70, rating = 'C', label = 'Acceptable'},
        {min = 60, rating = 'D', label = 'Poor'},
        {min = 0, rating = 'F', label = 'Failing'},
    },
    
    -- Cleaning effectiveness
    TrashRemovalDirtReduction = 5,
    MopDirtReduction = 10,
    PestControlRoachRemoval = true,
}

-- Fire System
Config.Fire = {
    -- Fire probability factors (0-1 scale)
    BurntFoodBaseProbability = 0.05,
    LowCleanlinessMultiplier = 2.0,
    LowOilQualityMultiplier = 3.0,
    ConsecutiveBurnsMultiplier = 1.5,
    
    -- Fire thresholds
    BurntCountForRisk = 3, -- Number of burns before risk increases
    CleanlinessThreshold = 30, -- Below this, fire risk increases
    OilQualityThreshold = 20, -- Below this, fire risk increases
    
    -- Fire effects
    EquipmentConditionLoss = 30,
    HygienePenalty = 20,
    SpreadChance = 0.1, -- Chance to spread to nearby stations
    SpreadRadius = 5.0,
}

-- Spoilage System
Config.Spoilage = {
    -- Storage type multipliers (hours until expiry)
    StorageTypes = {
        dry = 168, -- 7 days
        fridge = 72, -- 3 days
        freezer = 720, -- 30 days
    },
    
    -- Item categories and their base spoilage rates
    ItemCategories = {
        meat_raw = {storage = 'fridge', hoursUntilExpiry = 48},
        meat_cooked = {storage = 'fridge', hoursUntilExpiry = 24},
        dairy = {storage = 'fridge', hoursUntilExpiry = 72},
        produce = {storage = 'fridge', hoursUntilExpiry = 120},
        dry_goods = {storage = 'dry', hoursUntilExpiry = 720},
        frozen = {storage = 'freezer', hoursUntilExpiry = 2160},
        beverages = {storage = 'dry', hoursUntilExpiry = 1440},
    },
    
    -- Allow using expired items (with high poison risk)?
    AllowExpiredUse = false,
}

-- Order System
Config.Orders = {
    -- Order lifecycle
    OrderStatuses = {
        'placed',
        'accepted',
        'prepping',
        'ready',
        'served',
        'completed',
        'cancelled',
        'refunded'
    },
    
    -- Timing warnings for KDS
    WarningTime = 300000, -- 5 minutes (yellow)
    CriticalTime = 600000, -- 10 minutes (red)
    
    -- Transaction settings
    TaxRate = 0.0, -- Placeholder for government integration
    AcceptCash = true,
    AcceptCard = true,
    
    -- Order channels
    Channels = {
        'dine-in',
        'takeout',
        'delivery' -- Placeholder for future
    },
}

-- Permissions
Config.Permissions = {
    Roles = {
        owner = {
            label = 'Owner',
            permissions = {
                'all' -- Full access
            }
        },
        manager = {
            label = 'Manager',
            permissions = {
                'menu.view', 'menu.create', 'menu.edit', 'menu.delete',
                'recipe.view', 'recipe.create', 'recipe.edit', 'recipe.delete',
                'employee.view', 'employee.manage',
                'analytics.view',
                'orders.void', 'orders.refund', 'orders.comp',
                'supplies.order',
                'equipment.view',
                'hygiene.view',
                '86.toggle'
            }
        },
        supervisor = {
            label = 'Supervisor',
            permissions = {
                'pos.use',
                'kds.use',
                'station.use',
                'orders.void',
                'employee.view',
                '86.toggle'
            }
        },
        kitchen_staff = {
            label = 'Kitchen Staff',
            permissions = {
                'kds.use',
                'station.use',
                'equipment.clean'
            }
        },
        cashier = {
            label = 'Cashier',
            permissions = {
                'pos.use',
                'orders.view'
            }
        },
        employee = {
            label = 'Employee',
            permissions = {
                'pos.use',
                'kds.use',
                'station.use'
            }
        }
    }
}

-- Notifications
Config.Notifications = {
    Type = 'qb', -- 'qb' or 'ox'
    Duration = 5000,
}

-- Logging
Config.Logging = {
    Enabled = true,
    LogActions = {
        'recipe_create',
        'recipe_edit',
        'recipe_delete',
        'menu_edit',
        'order_void',
        'order_refund',
        'order_comp',
        'inventory_adjust',
        'fire_incident',
        'poison_incident',
        'employee_change'
    }
}

-- Integration
Config.Integration = {
    Computer = 'pf-computer', -- For business manager UI
    Target = 'qb-target',
    Core = 'qb-core',
}
