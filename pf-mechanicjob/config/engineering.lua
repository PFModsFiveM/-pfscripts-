-- ============================================================================
-- PF MECHANIC JOB - ADVANCED VEHICLE ENGINEERING AND TUNING SYSTEM CONFIG
-- ============================================================================

EngineConfig = EngineConfig or {}

-- ============================================================================
-- GLOBAL SETTINGS
-- ============================================================================

EngineConfig.Enabled = true                    -- Master toggle for engineering system
EngineConfig.RealisticMode = 'balanced'        -- 'casual', 'balanced', 'hardcore'
EngineConfig.CacheFlushInterval = 30000        -- Server-side cache flush (ms)
EngineConfig.WearSyncInterval = 60000          -- How often to sync wear to client (ms)
EngineConfig.HeatSyncInterval = 5000           -- How often to sync heat to client (ms)

-- ============================================================================
-- ENGINE PARTS SPECIFICATIONS
-- ============================================================================

EngineConfig.Engine = {
    stock = {
        hp_modifier = 1.0,
        torque_modifier = 1.0,
        heat_tolerance = 80,
        max_safe_boost_psi = 0,
        cost = 0,
        label = 'Stock Engine'
    },
    strengthened = {
        hp_modifier = 1.05,
        torque_modifier = 1.08,
        heat_tolerance = 85,
        max_safe_boost_psi = 6,
        cost = 8000,
        label = 'Strengthened Engine Block'
    },
    forged = {
        hp_modifier = 1.15,
        torque_modifier = 1.20,
        heat_tolerance = 95,
        max_safe_boost_psi = 15,
        cost = 25000,
        label = 'Forged Engine Block'
    }
}

EngineConfig.Internals = {
    stock = {
        hp_modifier = 1.0,
        torque_modifier = 1.0,
        max_safe_boost_psi = 0,
        cost = 0,
        label = 'Stock Internals',
        reliability = 1.0
    },
    forged = {
        hp_modifier = 1.10,
        torque_modifier = 1.15,
        max_safe_boost_psi = 20,
        cost = 35000,
        label = 'Forged Internals',
        reliability = 0.95
    }
}

EngineConfig.ForcedInduction = {
    none = {
        hp_modifier = 1.0,
        torque_modifier = 1.0,
        heat_generation = 0,
        cost = 0,
        label = 'None',
        max_boost_safe = 0
    },
    turbo_stage1 = {
        hp_modifier = 1.25,
        torque_modifier = 1.35,
        heat_generation = 15,
        cost = 12000,
        label = 'Turbo Stage 1',
        max_boost_safe = 8,
        requires_intercooler = false
    },
    turbo_stage2 = {
        hp_modifier = 1.50,
        torque_modifier = 1.60,
        heat_generation = 25,
        cost = 22000,
        label = 'Turbo Stage 2',
        max_boost_safe = 12,
        requires_intercooler = true,
        requires_fuel_upgrade = true
    },
    turbo_stage3 = {
        hp_modifier = 1.80,
        torque_modifier = 1.95,
        heat_generation = 35,
        cost = 40000,
        label = 'Turbo Stage 3',
        max_boost_safe = 18,
        requires_intercooler = true,
        requires_fuel_upgrade = true,
        requires_forged_internals = true
    },
    supercharger_stage1 = {
        hp_modifier = 1.35,
        torque_modifier = 1.50,
        heat_generation = 12,
        cost = 18000,
        label = 'Supercharger Stage 1',
        max_boost_safe = 10,
        low_rpm_boost = true
    },
    supercharger_stage2 = {
        hp_modifier = 1.60,
        torque_modifier = 1.75,
        heat_generation = 20,
        cost = 35000,
        label = 'Supercharger Stage 2',
        max_boost_safe = 14,
        requires_fuel_upgrade = true,
        low_rpm_boost = true
    }
}

EngineConfig.Intercooler = {
    none = {
        heat_reduction = 0,
        cost = 0,
        label = 'None'
    },
    street = {
        heat_reduction = 8,
        cost = 3000,
        label = 'Street Intercooler'
    },
    race = {
        heat_reduction = 15,
        cost = 8000,
        label = 'Race Intercooler'
    }
}

EngineConfig.Intake = {
    stock = {
        hp_modifier = 1.0,
        airflow_efficiency = 0.85,
        cost = 0,
        label = 'Stock Intake'
    },
    street = {
        hp_modifier = 1.03,
        airflow_efficiency = 0.92,
        cost = 1500,
        label = 'Street Intake'
    },
    race = {
        hp_modifier = 1.06,
        airflow_efficiency = 0.98,
        cost = 4000,
        label = 'Race Intake'
    }
}

EngineConfig.Exhaust = {
    stock = {
        hp_modifier = 1.0,
        backpressure = 1.0,
        sound_multiplier = 1.0,
        cost = 0,
        label = 'Stock Exhaust'
    },
    street = {
        hp_modifier = 1.04,
        backpressure = 0.80,
        sound_multiplier = 1.5,
        cost = 2000,
        label = 'Street Exhaust'
    },
    race = {
        hp_modifier = 1.08,
        backpressure = 0.60,
        sound_multiplier = 2.0,
        cost = 6000,
        label = 'Race Exhaust'
    }
}

EngineConfig.FuelInjectors = {
    stock = {
        max_fuel_flow = 1.0,
        efficiency = 0.95,
        cost = 0,
        label = 'Stock Injectors',
        cc = 280
    },
    ['550cc'] = {
        max_fuel_flow = 1.30,
        efficiency = 0.92,
        cost = 3000,
        label = '550cc Injectors',
        cc = 550
    },
    ['1000cc'] = {
        max_fuel_flow = 2.0,
        efficiency = 0.88,
        cost = 7000,
        label = '1000cc Injectors',
        cc = 1000
    },
    ['2000cc'] = {
        max_fuel_flow = 3.5,
        efficiency = 0.82,
        cost = 15000,
        label = '2000cc Injectors',
        cc = 2000
    }
}

EngineConfig.FuelPump = {
    stock = {
        flow_rate = 1.0,
        pressure_psi = 43.5,
        cost = 0,
        label = 'Stock Fuel Pump'
    },
    street = {
        flow_rate = 1.5,
        pressure_psi = 50,
        cost = 2500,
        label = 'Street Fuel Pump'
    },
    race = {
        flow_rate = 2.5,
        pressure_psi = 60,
        cost = 7500,
        label = 'Race Fuel Pump'
    }
}

EngineConfig.ECUMaps = {
    stock = {
        hp_modifier = 1.0,
        torque_modifier = 1.0,
        fuel_consumption = 1.0,
        heat_generation = 1.0,
        reliability = 1.0,
        cost = 0,
        label = 'Stock Map'
    },
    eco = {
        hp_modifier = 0.95,
        torque_modifier = 0.95,
        fuel_consumption = 0.80,
        heat_generation = 0.85,
        reliability = 1.05,
        cost = 2500,
        label = 'Eco Map'
    },
    street = {
        hp_modifier = 1.08,
        torque_modifier = 1.10,
        fuel_consumption = 1.15,
        heat_generation = 1.10,
        reliability = 0.95,
        cost = 4000,
        label = 'Street Map'
    },
    performance = {
        hp_modifier = 1.18,
        torque_modifier = 1.22,
        fuel_consumption = 1.35,
        heat_generation = 1.25,
        reliability = 0.90,
        cost = 8000,
        label = 'Performance Map'
    },
    race = {
        hp_modifier = 1.28,
        torque_modifier = 1.35,
        fuel_consumption = 1.60,
        heat_generation = 1.45,
        reliability = 0.80,
        cost = 15000,
        label = 'Race Map'
    },
    valet = {
        hp_modifier = 0.85,
        torque_modifier = 0.85,
        fuel_consumption = 0.75,
        heat_generation = 0.70,
        reliability = 1.10,
        cost = 3000,
        label = 'Valet Mode'
    }
}

EngineConfig.Ignition = {
    stock = {
        misfire_chance = 0.02,
        efficiency = 0.98,
        cost = 0,
        label = 'Stock Ignition'
    },
    upgraded = {
        misfire_chance = 0.005,
        efficiency = 1.02,
        cost = 2000,
        label = 'Upgraded Ignition'
    }
}

EngineConfig.Cooling = {
    stock = {
        cooling_efficiency = 1.0,
        heat_dissipation = 100,
        cost = 0,
        label = 'Stock Cooling'
    },
    street = {
        cooling_efficiency = 1.35,
        heat_dissipation = 135,
        cost = 4000,
        label = 'Street Cooling'
    },
    race = {
        cooling_efficiency = 1.60,
        heat_dissipation = 160,
        cost = 10000,
        label = 'Race Cooling'
    }
}

EngineConfig.OilSystem = {
    stock = {
        oil_capacity = 5.5,
        flow_rate = 1.0,
        protection = 0.85,
        cost = 0,
        label = 'Stock Oil System'
    },
    upgraded = {
        oil_capacity = 8.0,
        flow_rate = 1.3,
        protection = 0.95,
        cost = 3500,
        label = 'Upgraded Oil System'
    }
}

-- ============================================================================
-- DRIVETRAIN SPECIFICATIONS
-- ============================================================================

EngineConfig.Clutch = {
    stock = {
        torque_rating_nm = 300,
        grip = 0.7,
        wear_rate_multiplier = 1.0,
        cost = 0,
        label = 'Stock Clutch'
    },
    street = {
        torque_rating_nm = 500,
        grip = 0.85,
        wear_rate_multiplier = 1.3,
        cost = 2000,
        label = 'Street Clutch'
    },
    race = {
        torque_rating_nm = 800,
        grip = 0.95,
        wear_rate_multiplier = 1.8,
        cost = 6000,
        label = 'Race Clutch'
    }
}

EngineConfig.Gearbox = {
    stock = {
        torque_rating_nm = 300,
        efficiency = 0.92,
        wear_rate_multiplier = 1.0,
        cost = 0,
        label = 'Stock Gearbox'
    },
    strengthened = {
        torque_rating_nm = 500,
        efficiency = 0.91,
        wear_rate_multiplier = 1.2,
        cost = 4000,
        label = 'Strengthened Gearbox'
    },
    race = {
        torque_rating_nm = 800,
        efficiency = 0.90,
        wear_rate_multiplier = 1.5,
        cost = 10000,
        label = 'Race Gearbox'
    }
}

EngineConfig.Differential = {
    stock = {
        grip_coefficient = 1.0,
        traction_multiplier = 1.0,
        wear_rate_multiplier = 1.0,
        cost = 0,
        label = 'Stock Differential'
    },
    lsd = {
        grip_coefficient = 1.4,
        traction_multiplier = 1.3,
        wear_rate_multiplier = 1.2,
        cost = 3000,
        label = 'LSD Differential'
    },
    race = {
        grip_coefficient = 1.7,
        traction_multiplier = 1.6,
        wear_rate_multiplier = 1.5,
        cost = 8000,
        label = 'Race Differential'
    }
}

-- ============================================================================
-- TIRE SPECIFICATIONS
-- ============================================================================

EngineConfig.Tires = {
    street = {
        grip_coefficient = 0.85,
        wear_rate = 0.60,
        temperature_sensitivity = 1.1,
        cost = 500,
        label = 'Street Tires'
    },
    sport = {
        grip_coefficient = 1.0,
        wear_rate = 0.75,
        temperature_sensitivity = 1.05,
        cost = 1200,
        label = 'Sport Tires'
    },
    semi_slick = {
        grip_coefficient = 1.25,
        wear_rate = 1.0,
        temperature_sensitivity = 1.15,
        cost = 2000,
        label = 'Semi-Slick Tires'
    },
    slick = {
        grip_coefficient = 1.50,
        wear_rate = 1.3,
        temperature_sensitivity = 1.35,
        wet_performance_penalty = 0.6,
        cost = 3500,
        label = 'Slick Tires'
    }
}

-- ============================================================================
-- FUEL TYPES
-- ============================================================================

EngineConfig.FuelTypes = {
    pump = {
        octane = 87,
        knock_resistance = 0.85,
        max_safe_boost = 6,
        consumption_multiplier = 1.0,
        cost_per_unit = 1.0,
        label = 'Pump Fuel'
    },
    premium = {
        octane = 93,
        knock_resistance = 0.95,
        max_safe_boost = 10,
        consumption_multiplier = 1.02,
        cost_per_unit = 1.15,
        label = 'Premium Fuel'
    },
    e85 = {
        octane = 105,
        knock_resistance = 1.0,
        max_safe_boost = 16,
        consumption_multiplier = 1.35,
        cost_per_unit = 1.25,
        label = 'E85 Ethanol'
    },
    race = {
        octane = 110,
        knock_resistance = 1.05,
        max_safe_boost = 20,
        consumption_multiplier = 1.50,
        cost_per_unit = 2.0,
        label = 'Race Fuel'
    }
}

-- ============================================================================
-- WEAR AND HEAT DYNAMICS
-- ============================================================================

EngineConfig.Wear = {
    baseEngineWearRate = 0.0001,      -- Base wear per tick
    baseTurboWearRate = 0.00015,
    baseClutchWearRate = 0.0001,
    baseGearboxWearRate = 0.00008,
    baseDiffWearRate = 0.00007,
    
    stressMultiplier = 2.0,           -- How much stress multiplies wear
    rpmMaxWear = 7500,               -- RPM where max wear is applied
    boostWearMultiplier = 3.0,        -- Boost increases wear significantly
    temperatureWearMultiplier = 2.5,
    lowOilQualityWearMultiplier = 1.8,
    
    launchWearMultiplier = 5.0,       -- Hard launches increase wear 5x
    wheelSpinWearMultiplier = 3.0,    -- Wheelspin increases diff/tire wear
    burnoutWearMultiplier = 8.0       -- Burnouts increase wear significantly
}

EngineConfig.Heat = {
    engineHeatGeneration = 0.8,       -- Heat generation per tick at load
    turboHeatGeneration = 2.0,        -- Turbo generates lots of heat
    boostHeatMultiplier = 2.5,        -- Boost level affects heat
    rpmHeatMultiplier = 1.5,
    
    engineHeatDissipation = 15,       -- Heat lost per tick at idle
    airflowCooling = 0.5,             -- Additional cooling from speed
    coolantQualityCooling = 0.3,      -- Coolant quality affects cooling
    
    heatThresholds = {
        warning = 75,                 -- UI warning
        performance_reduction = 80,   -- Power starts reducing
        limp_mode = 90,               -- Severe power reduction
        damage_chance_start = 92,     -- Engine damage chance begins
        shutdown = 100                -- Forced shutdown
    }
}

EngineConfig.Limp = {
    power_reduction = 0.4,            -- Reduce to 40% power in limp mode
    torque_reduction = 0.35,
    max_rpm = 4000,
    duration = 15000                  -- 15 seconds in limp mode minimum
}

-- ============================================================================
-- FAILURE SYSTEM
-- ============================================================================

EngineConfig.Failures = {
    misfire_chance_base = 0.01,       -- 1% base misfire chance
    misfire_wear_scale = 0.008,       -- Increases with wear
    misfire_oil_scale = 0.006,        -- Increases as oil degrades
    misfire_heat_scale = 0.005,       -- Increases with heat
    
    catastrophic_failure_threshold = {
        casual = 100,                 -- Never happens in casual
        balanced = 0.02,              -- 2% chance with extreme stress
        hardcore = 0.10               -- 10% chance with extreme stress
    },
    
    gearbox_slip_torque_threshold = 1.3,  -- Slip at 130% rating
    clutch_burn_threshold = 1.5,          -- Burn at 150% rating
    differential_damage_threshold = 1.4
}

-- ============================================================================
-- FUEL CONSUMPTION SCALING
-- ============================================================================

EngineConfig.FuelConsumption = {
    baseMultiplier = 1.0,             -- Base fuel consumption
    
    -- HP ratio affects consumption exponentially
    hpRatioExponent = 1.3,
    
    -- Throttle and RPM factors
    throttleScale = 1.0,
    rpmScale = 1.2,
    
    -- Eco map reduces consumption
    ecoModeReduction = 0.25,
    
    -- Fuel type affects consumption
    e85Penalty = 0.35,
    
    -- Conditions that increase consumption
    poorOilQualityPenalty = 0.15,
    lowCoolingEfficiency = 0.12,
    highWearPenalty = 0.20
}

-- ============================================================================
-- TORQUE CURVE SIMULATION
-- ============================================================================

EngineConfig.TorqueCurves = {
    -- Stock engines: flat torque across RPM band
    stock = {
        points = {
            {rpm = 1000, multiplier = 0.65},
            {rpm = 3000, multiplier = 0.95},
            {rpm = 5000, multiplier = 1.0},
            {rpm = 7000, multiplier = 0.85}
        }
    },
    
    -- Naturally aspirated with cam: weak low end, strong high
    high_cam = {
        points = {
            {rpm = 1000, multiplier = 0.50},
            {rpm = 3000, multiplier = 0.80},
            {rpm = 5500, multiplier = 1.05},
            {rpm = 7000, multiplier = 1.0}
        }
    },
    
    -- Supercharger: strong low end, flatter curve
    supercharger = {
        points = {
            {rpm = 1000, multiplier = 1.0},
            {rpm = 3000, multiplier = 1.05},
            {rpm = 5000, multiplier = 1.0},
            {rpm = 7000, multiplier = 0.85}
        }
    },
    
    -- Turbo: weak low, peaks mid-high
    turbo = {
        points = {
            {rpm = 1000, multiplier = 0.45},
            {rpm = 2500, multiplier = 0.80},
            {rpm = 4500, multiplier = 1.10},
            {rpm = 6000, multiplier = 1.0},
            {rpm = 7000, multiplier = 0.75}
        }
    },
    
    -- Extreme turbo: massive peak
    turbo_extreme = {
        points = {
            {rpm = 1000, multiplier = 0.30},
            {rpm = 2000, multiplier = 0.60},
            {rpm = 4000, multiplier = 1.20},
            {rpm = 5500, multiplier = 1.15},
            {rpm = 6500, multiplier = 0.80}
        }
    }
}

-- ============================================================================
-- SIMPLE MODE UPGRADES (Backwards Compatibility)
-- ============================================================================

EngineConfig.SimpleUpgrades = {
    intake_filter = {
        intake = 'street',
        hp_gain_percent = 2,
        cost = 500,
        label = 'Air Filter Upgrade'
    },
    
    exhaust_catback = {
        exhaust = 'street',
        hp_gain_percent = 3,
        cost = 1800,
        label = 'Cat-Back Exhaust'
    },
    
    spark_plugs = {
        ignition = 'upgraded',
        hp_gain_percent = 1,
        misfire_reduction = 0.5,
        cost = 400,
        label = 'Upgraded Spark Plugs'
    },
    
    ecu_tune_basic = {
        ecu_map = 'street',
        hp_gain_percent = 5,
        fuel_penalty_percent = 15,
        cost = 3500,
        label = 'Basic ECU Tune'
    },
    
    oil_change = {
        oil_quality = 100,
        wear_reduction = 0.3,
        cost = 250,
        label = 'Premium Oil Change'
    },
    
    coolant_flush = {
        coolant_quality = 100,
        heat_reduction = 5,
        cost = 400,
        label = 'Cooling System Flush'
    },
    
    tire_upgrade = {
        tire_compound = 'sport',
        grip_improvement = 0.2,
        wear_increase = 0.1,
        cost = 1000,
        label = 'Sport Tire Set'
    }
}

-- ============================================================================
-- REALISM PRESETS
-- ============================================================================

EngineConfig.RealisticPresets = {
    casual = {
        wearMultiplier = 0.3,
        failureChance = 0.0,
        heatSensitivity = 0.5,
        fuelConsumption = 0.7,
        gripLimitations = false,
        limp_mode_enabled = false,
        max_power_allowed = 2.0  -- 2x stock HP allowed
    },
    
    balanced = {
        wearMultiplier = 1.0,
        failureChance = 0.02,
        heatSensitivity = 1.0,
        fuelConsumption = 1.0,
        gripLimitations = true,
        limp_mode_enabled = true,
        max_power_allowed = 3.5  -- 3.5x stock HP
    },
    
    hardcore = {
        wearMultiplier = 2.0,
        failureChance = 0.15,
        heatSensitivity = 1.5,
        fuelConsumption = 1.3,
        gripLimitations = true,
        limp_mode_enabled = true,
        torque_overload_damage = true,
        max_power_allowed = 5.0  -- 5x stock HP with extreme consequences
    }
}

-- ============================================================================
-- SERVICE COSTS
-- ============================================================================

EngineConfig.ServiceCosts = {
    oil_change = 250,
    coolant_flush = 400,
    spark_plugs = 400,
    air_filter = 300,
    fuel_filter = 350,
    
    -- Major services
    engine_rebuild = 15000,
    gearbox_rebuild = 12000,
    turbo_replacement = 8000,
    clutch_replacement = 4000,
    differential_service = 5000,
    
    -- Per wear point
    wear_repair_per_point = 100
}

-- ============================================================================
-- VALIDATION RULES
-- ============================================================================

EngineConfig.ValidationRules = {
    -- Turbo stage 2+ requires intercooler
    turbo_stage2_requires_intercooler = true,
    turbo_stage3_requires_intercooler = true,
    
    -- High boost requires forged internals
    high_boost_requires_forged = true,
    high_boost_threshold_psi = 12,
    
    -- Fuel system upgrades enable turbo stages
    turbo_stage2_requires_fuel_upgrade = true,
    turbo_stage3_requires_fuel_upgrade = true,
    
    -- Drivetrain must match estimated torque
    enforce_drivetrain_limits = true,
    
    -- Cooling must match power output
    enforce_cooling_limits = true,
    
    -- Tires must have adequate grip
    enforce_tire_limits = true,
    tire_grip_ratio_minimum = 0.85  -- Grip must be at least 85% of power demand
}

-- ============================================================================
-- STOCK VEHICLE STATS (FOR COMPARISON)
-- ============================================================================

EngineConfig.StockStats = {
    default_hp = 150,
    default_torque_nm = 200,
    default_max_rpm = 7500,
    default_drivetrain_rating = 300
}

return EngineConfig
