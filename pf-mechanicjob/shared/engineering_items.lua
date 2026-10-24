-- ============================================================================
-- PF MECHANIC JOB - ENGINEERING ITEMS DEFINITIONS
-- Upgrade items for the Advanced Vehicle Tuning System
-- ============================================================================

local EngineConfig = require('config.engineering')

if not EngineConfig.Enabled then return end

-- Register all tuning/upgrade items with QBCore
local QBCore = exports['pfm-core']:GetCoreObject()

-- Define item metadata and descriptions
local EngineeringItems = {
    -- SIMPLE UPGRADES (Minor parts, easy installation)
    
    ['intake_filter'] = {
        label = 'High-Flow Air Filter',
        weight = 500,
        type = 'item',
        image = 'intake_filter.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Premium air intake filter~n~+2% HP~n~Cost: $500'
    },
    
    ['exhaust_catback'] = {
        label = 'Cat-Back Exhaust System',
        weight = 5000,
        type = 'item',
        image = 'exhaust.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Cat-back exhaust system~n~+3% HP, +Better sound~n~Cost: $1,800'
    },
    
    ['spark_plugs'] = {
        label = 'Upgraded Spark Plugs',
        weight = 200,
        type = 'item',
        image = 'spark_plugs.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Premium spark plugs~n~+1% HP, -50% Misfire chance~n~Cost: $400'
    },
    
    ['ecu_tune_basic'] = {
        label = 'Basic ECU Tune',
        weight = 50,
        type = 'item',
        image = 'ecu_tune.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Street-level ECU reprogramming~n~+5% HP, +15% Fuel consumption~n~Cost: $3,500'
    },
    
    ['premium_oil'] = {
        label = 'Premium Oil Change Service',
        weight = 2000,
        type = 'item',
        image = 'oil_change.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Premium synthetic oil~n~Reset engine wear, +15% efficiency~n~Cost: $250'
    },
    
    ['coolant_flush'] = {
        label = 'Cooling System Service',
        weight = 1500,
        type = 'item',
        image = 'coolant.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Complete coolant flush and replacement~n~Reset overheat risk, +20°C capacity~n~Cost: $400'
    },
    
    ['sport_tires'] = {
        label = 'Sport Tire Set',
        weight = 8000,
        type = 'item',
        image = 'sport_tires.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Sport compound tires~n~+20% grip, better handling~n~Cost: $1,000'
    },
    
    -- MAJOR UPGRADES (Engines, turbos, transmissions)
    
    ['engine_block_strengthened'] = {
        label = 'Strengthened Engine Block',
        weight = 20000,
        type = 'item',
        image = 'engine_block.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Reinforced pistons and block~n~+5% HP, +8% Torque~n~Max boost: 6 PSI~n~Cost: $8,000'
    },
    
    ['internals_forged'] = {
        label = 'Forged Internals Kit',
        weight = 15000,
        type = 'item',
        image = 'forged_internals.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Forged pistons and connecting rods~n~+10% HP, +15% Torque~n~Max boost: 20 PSI~n~Cost: $35,000'
    },
    
    ['turbo_stage1'] = {
        label = 'Turbo Stage 1 Kit',
        weight = 10000,
        type = 'item',
        image = 'turbo.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Entry-level turbocharger~n~+25% HP, +35% Torque~n~8 PSI boost~n~Cost: $12,000'
    },
    
    ['turbo_stage2'] = {
        label = 'Turbo Stage 2 Kit',
        weight = 10000,
        type = 'item',
        image = 'turbo_stage2.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Upgraded turbocharger~n~+50% HP, +60% Torque~n~12 PSI boost~n~*Requires intercooler & forged internals*~n~Cost: $22,000'
    },
    
    ['turbo_stage3'] = {
        label = 'Turbo Stage 3 Kit',
        weight = 10000,
        type = 'item',
        image = 'turbo_stage3.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Extreme turbocharger~n~+80% HP, +95% Torque~n~18 PSI boost~n~*Requires intercooler & extreme cooling*~n~Cost: $40,000'
    },
    
    ['supercharger_s1'] = {
        label = 'Supercharger Stage 1',
        weight = 12000,
        type = 'item',
        image = 'supercharger.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Roots-type supercharger~n~+35% HP, +50% Torque~n~10 PSI boost (low RPM)~n~Cost: $18,000'
    },
    
    ['supercharger_s2'] = {
        label = 'Supercharger Stage 2',
        weight = 12000,
        type = 'item',
        image = 'supercharger_s2.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Twin-screw supercharger~n~+60% HP, +75% Torque~n~14 PSI boost (low RPM)~n~*Requires fuel upgrade*~n~Cost: $35,000'
    },
    
    ['intercooler_street'] = {
        label = 'Street Intercooler',
        weight = 8000,
        type = 'item',
        image = 'intercooler.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Air-to-air intercooler~n~-8°C turbo temperature~n~Cost: $3,000'
    },
    
    ['intercooler_race'] = {
        label = 'Race Intercooler',
        weight = 8000,
        type = 'item',
        image = 'intercooler_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'High-flow race intercooler~n~-15°C turbo temperature~n~Cost: $8,000'
    },
    
    ['fuel_injectors_550'] = {
        label = '550cc Fuel Injectors',
        weight = 500,
        type = 'item',
        image = 'fuel_injectors.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Upgraded fuel injectors~n~+30% flow rate~n~Cost: $3,000'
    },
    
    ['fuel_injectors_1000'] = {
        label = '1000cc Fuel Injectors',
        weight = 500,
        type = 'item',
        image = 'fuel_injectors_1000.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'High-flow fuel injectors~n~+100% flow rate~n~Cost: $7,000'
    },
    
    ['fuel_injectors_2000'] = {
        label = '2000cc Fuel Injectors',
        weight = 500,
        type = 'item',
        image = 'fuel_injectors_2000.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Extreme flow fuel injectors~n~+250% flow rate~n~Cost: $15,000'
    },
    
    ['fuel_pump_street'] = {
        label = 'Street Fuel Pump',
        weight = 3000,
        type = 'item',
        image = 'fuel_pump.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Upgraded fuel pump~n~+50% flow rate~n~Cost: $2,500'
    },
    
    ['fuel_pump_race'] = {
        label = 'Race Fuel Pump',
        weight = 3000,
        type = 'item',
        image = 'fuel_pump_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'High-pressure race fuel pump~n~+150% flow rate~n~Cost: $7,500'
    },
    
    ['intake_race'] = {
        label = 'Race Intake Manifold',
        weight = 4000,
        type = 'item',
        image = 'race_intake.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Ported and polished intake~n~+6% HP, Better airflow~n~Cost: $4,000'
    },
    
    ['exhaust_race'] = {
        label = 'Competition Exhaust',
        weight = 6000,
        type = 'item',
        image = 'race_exhaust.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Full race exhaust system~n~+8% HP, Maximum flow~n~Cost: $6,000'
    },
    
    ['cooling_race'] = {
        label = 'Race Cooling Kit',
        weight = 12000,
        type = 'item',
        image = 'cooling_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Large capacity radiator + fans~n~+60% cooling capacity~n~Cost: $10,000'
    },
    
    ['oil_system_upgraded'] = {
        label = 'Upgraded Oil System',
        weight = 8000,
        type = 'item',
        image = 'oil_system.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Enhanced oil circulation system~n~+25% oil capacity, better protection~n~Cost: $3,500'
    },
    
    -- DRIVETRAIN UPGRADES
    
    ['clutch_street'] = {
        label = 'Street Performance Clutch',
        weight = 5000,
        type = 'item',
        image = 'clutch.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'High-grip street clutch~n~500 Nm rating~n~Cost: $2,000'
    },
    
    ['clutch_race'] = {
        label = 'Race Clutch Kit',
        weight = 5000,
        type = 'item',
        image = 'clutch_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Carbon fiber competition clutch~n~800 Nm rating~n~Cost: $6,000'
    },
    
    ['gearbox_strengthened'] = {
        label = 'Strengthened Gearbox',
        weight = 15000,
        type = 'item',
        image = 'gearbox.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Reinforced internal gears~n~500 Nm rating, Reduced wear~n~Cost: $4,000'
    },
    
    ['gearbox_race'] = {
        label = 'Race Transmission Kit',
        weight = 15000,
        type = 'item',
        image = 'gearbox_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Competition-grade transmission~n~800 Nm rating~n~Cost: $10,000'
    },
    
    ['differential_lsd'] = {
        label = 'LSD Differential',
        weight = 8000,
        type = 'item',
        image = 'differential_lsd.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Limited-slip differential~n~+40% grip, +30% traction~n~Cost: $3,000'
    },
    
    ['differential_race'] = {
        label = 'Race Differential',
        weight = 8000,
        type = 'item',
        image = 'differential_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Locking race differential~n~+70% grip, +60% traction~n~Cost: $8,000'
    },
    
    -- SERVICE ITEMS
    
    ['service_engine_rebuild'] = {
        label = 'Engine Rebuild Service',
        weight = 100,
        type = 'item',
        image = 'engine_rebuild.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Complete engine overhaul~n~Reset wear, restore performance~n~Cost: $15,000'
    },
    
    ['service_transmission_rebuild'] = {
        label = 'Transmission Rebuild',
        weight = 100,
        type = 'item',
        image = 'trans_rebuild.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Transmission complete overhaul~n~Reset gearbox wear~n~Cost: $12,000'
    },
    
    ['service_clutch_replacement'] = {
        label = 'Clutch Replacement',
        weight = 100,
        type = 'item',
        image = 'clutch_service.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Full clutch replacement~n~Reset clutch wear~n~Cost: $4,000'
    },
    
    ['service_differential_repair'] = {
        label = 'Differential Service',
        weight = 100,
        type = 'item',
        image = 'diff_service.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Differential fluid flush & repair~n~Reset differential wear~n~Cost: $5,000'
    },
    
    -- ECU TUNES
    
    ['ecu_tune_eco'] = {
        label = 'Eco ECU Tune',
        weight = 50,
        type = 'item',
        image = 'ecu_eco.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Fuel-saving ECU map~n~-5% HP, -25% Fuel usage~n~Cost: $2,500'
    },
    
    ['ecu_tune_street'] = {
        label = 'Street ECU Tune',
        weight = 50,
        type = 'item',
        image = 'ecu_street.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Street performance map~n~+8% HP, +15% Fuel~n~Cost: $4,000'
    },
    
    ['ecu_tune_performance'] = {
        label = 'Performance ECU Tune',
        weight = 50,
        type = 'item',
        image = 'ecu_performance.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Track-focused map~n~+18% HP, +35% Fuel~n~Cost: $8,000'
    },
    
    ['ecu_tune_race'] = {
        label = 'Race ECU Tune',
        weight = 50,
        type = 'item',
        image = 'ecu_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Maximum output race tune~n~+28% HP, +60% Fuel~n~Cost: $15,000'
    },
    
    ['ecu_tune_valet'] = {
        label = 'Valet Mode ECU',
        weight = 50,
        type = 'item',
        image = 'ecu_valet.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Limiter ECU map~n~-15% HP, -25% Fuel~n~Cost: $3,000'
    },
    
    -- TIRE SETS
    
    ['tire_semi_slick'] = {
        label = 'Semi-Slick Tire Set',
        weight = 8000,
        type = 'item',
        image = 'semi_slick_tires.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Track-oriented tires~n~+25% grip, higher temps~n~Cost: $2,000'
    },
    
    ['tire_slick'] = {
        label = 'Slick Tire Set',
        weight = 8000,
        type = 'item',
        image = 'slick_tires.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Competition drag slicks~n~+50% grip, max performance~n~Cost: $3,500'
    },
    
    -- FUEL TYPES (Consumables)
    
    ['fuel_e85'] = {
        label = 'E85 Ethanol Fuel',
        weight = 500,
        type = 'item',
        image = 'fuel_e85.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'High-octane E85 ethanol blend~n~Max boost: 16 PSI, +35% consumption~n~Cost: Varies'
    },
    
    ['fuel_race'] = {
        label = 'Race Fuel',
        weight = 500,
        type = 'item',
        image = 'fuel_race.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = '110-octane race fuel~n~Max boost: 20 PSI, +50% consumption~n~Cost: Premium'
    },

    -- ADVANCED SHOP SYSTEM ITEMS

    ['alignment_rack_tool'] = {
        label = 'Alignment Rack Controller',
        weight = 2500,
        type = 'item',
        image = 'alignment_rack_tool.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Calibrates camber, toe, and steering angle'
    },

    ['floor_jack'] = {
        label = 'Floor Jack',
        weight = 6000,
        type = 'item',
        image = 'floor_jack.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Lift a vehicle for underbody service'
    },

    ['jack_stands'] = {
        label = 'Jack Stands',
        weight = 5000,
        type = 'item',
        image = 'jack_stands.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Secure a lifted vehicle safely'
    },

    ['transmission_jack'] = {
        label = 'Transmission Jack',
        weight = 8000,
        type = 'item',
        image = 'transmission_jack.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Required for transmission and clutch removal'
    },

    ['flywheel_service_kit'] = {
        label = 'Flywheel Service Kit',
        weight = 3000,
        type = 'item',
        image = 'flywheel_service_kit.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Inspect/resurface flywheel during clutch service'
    },

    ['pulley_puller'] = {
        label = 'Pulley Puller',
        weight = 2000,
        type = 'item',
        image = 'pulley_puller.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Preferred tool for pilot bearing removal'
    },

    ['mechanic_hammer'] = {
        label = 'Mechanic Hammer',
        weight = 1500,
        type = 'item',
        image = 'mechanic_hammer.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Fallback tool for bearing extraction'
    },

    ['mechanic_socket'] = {
        label = 'Bearing Socket',
        weight = 300,
        type = 'item',
        image = 'mechanic_socket.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Used with hammer method for pilot bearing'
    },

    ['sliced_bread'] = {
        label = 'Sliced Bread',
        weight = 100,
        type = 'item',
        image = 'sliced_bread.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Hydraulic hack for pilot bearing extraction'
    },

    ['obd_scanner'] = {
        label = 'OBD-II Scanner',
        weight = 1200,
        type = 'item',
        image = 'obd_scanner.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Read ECU faults and live parameters'
    },

    ['multimeter'] = {
        label = 'Automotive Multimeter',
        weight = 900,
        type = 'item',
        image = 'multimeter.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Measure voltage and charging system performance'
    },

    ['coolant_pressure_tester'] = {
        label = 'Coolant Pressure Tester',
        weight = 1800,
        type = 'item',
        image = 'coolant_pressure_tester.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Find coolant leaks and weak caps'
    },

    ['evap_smoke_machine'] = {
        label = 'EVAP Smoke Machine',
        weight = 3500,
        type = 'item',
        image = 'evap_smoke_machine.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Trace vacuum and EVAP leaks'
    },

    ['chop_kit'] = {
        label = 'Chop Shop Kit',
        weight = 2000,
        type = 'item',
        image = 'chop_kit.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'Dismantle a vehicle into salvage parts'
    }
}

-- Register items with QBCore
for itemName, itemData in pairs(EngineeringItems) do
    if QBCore.Shared.Items[itemName] == nil then
        QBCore.Shared.Items[itemName] = itemData
    end
end

if Config.Debug then
    local count = 0
    for _ in pairs(EngineeringItems) do count = count + 1 end
    print(string.format('[Engineering] Registered %d upgrade items', count))
end

return EngineeringItems
