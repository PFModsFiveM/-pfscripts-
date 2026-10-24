Locale:Load('en', {
    -- General
    ['no_permission'] = 'You do not have permission',
    ['not_mechanic'] = 'You are not a mechanic',
    ['no_vehicle'] = 'No vehicle nearby',
    ['vehicle_occupied'] = 'Vehicle spawn point occupied',
    ['not_in_vehicle'] = 'You must be in a vehicle',
    ['driver_seat_required'] = 'You must be in the driver seat',
    ['engine_must_be_off'] = 'Engine must be off',
    ['need_toolbox'] = 'You need a toolbox to do mechanic work',
    
    -- Tablet
    ['tablet_opened'] = 'Mechanic tablet opened',
    ['tablet_requires_job'] = 'You need to be a mechanic to use this',
    
    -- Preview System
    ['preview_started'] = 'Preview started. Changes will not be saved',
    ['preview_ended'] = 'Preview ended. Vehicle restored',
    ['preview_requires_qbmenu'] = 'Preview requires qb-menu',
    ['preview_init_failed'] = 'Preview initialization failed',
    ['preview_receipt_given'] = 'Preview receipt given with all changes listed',
    
    -- Damage System
    ['battery_dead'] = '🔋 Battery is completely dead! Needs replacement',
    ['battery_struggling'] = '🔋 Battery struggling... Try again',
    ['battery_weak'] = '🔋 Engine started (battery weak)',
    ['engine_misfired'] = '⚡ Engine misfired',
    ['engine_started_weak'] = '🔋 Engine started (battery weak)',
    ['charging_fault'] = '⚡ Charging system fault detected',
    ['alternator_failing'] = '⚡ Alternator failing! Electrical issues!',
    ['power_cut'] = '⚠️ Power cut! Battery failing!',
    ['sparkplugs_failed'] = '⚡ Spark plugs failed - engine won\'t start!',
    ['battery_drained'] = '🔋 Battery drained from failed starts!',
    ['engine_smoking'] = '💨 Engine smoking - critical oil level!',
    ['fuel_injector_failing'] = '⚠️ Fuel injector failing!',
    ['power_steering_failing'] = '⚠️ Power steering pump failing!',
    ['radiator_failing'] = '⚠️ Radiator failing! Overheating!',
    ['coolant_low'] = '⚠️ Coolant low! Overheating!',
    ['engine_fire'] = '🔥 Engine fire! Coolant empty!',
    ['deep_water_warning'] = '⚠️ Deep water! Engine at risk without snorkel!',
    ['mud_water_warning'] = '⚠️ Mud/water causing accelerated wear!',
    
    -- Component Warnings
    ['alternator_critical'] = '🔧 Alternator critically low!',
    ['sparkplugs_critical'] = '🔧 Spark Plugs critically low!',
    ['battery_critical'] = '🔧 Battery critically low!',
    ['oil_critical'] = '🔧 Engine Oil critically low!',
    ['oil_filter_critical'] = '🔧 Oil Filter critically low!',
    ['brakes_critical'] = '🔧 Brake Pads critically low!',
    ['suspension_critical'] = '🔧 Suspension critically low!',
    ['axle_critical'] = '🔧 Axle critically low!',
    
    -- Repairs
    ['repair_successful'] = 'Repair successful',
    ['repair_cancelled'] = 'Repair cancelled',
    ['repair_failed'] = 'Repair failed',
    ['missing_parts'] = 'Missing required parts',
    ['installation_cancelled'] = 'Installation cancelled',
    ['part_installed'] = 'Part installed successfully',
    ['repairing'] = 'Repairing {part}...',
    ['installing'] = 'Installing {part}...',
    
    -- Work Order Repairs
    ['work_order_tire_repair'] = 'Repairing tire',
    ['work_order_battery_replace'] = 'Replacing battery',
    ['work_order_oil_change'] = 'Changing oil',
    ['work_order_brake_pads'] = 'Replacing brake pads',
    ['work_order_air_filter'] = 'Servicing air filter',
    ['work_order_spark_plugs'] = 'Replacing spark plugs',
    ['work_order_coolant_flush'] = 'Flushing coolant system',
    ['work_order_alignment'] = 'Aligning wheels',
    ['work_order_transmission'] = 'Servicing transmission',
    ['work_order_engine_repair'] = 'Repairing engine',
    ['work_order_suspension'] = 'Overhauling suspension',
    ['work_order_exhaust_system'] = 'Repairing exhaust system',
    ['work_order_turbo_install'] = 'Installing turbo',
    ['work_order_engine_rebuild'] = 'Rebuilding engine',
    ['work_order_custom_tuning'] = 'Tuning performance',
    ['work_order_full_restoration'] = 'Restoring vehicle',
    ['work_order_race_prep'] = 'Preparing for race',
    ['work_order_diagnostic_full'] = 'Performing complete diagnostic',
    
    -- Cosmetics
    ['mod_installed'] = 'Modification installed',
    ['mod_install_failed'] = 'Modification installation failed',
    ['invalid_mod'] = 'Invalid modification type',
    ['no_mods_available'] = 'No available mods for this vehicle',
    ['tint_applied'] = 'Window tint applied',
    ['paint_applied'] = 'Paint applied successfully',
    ['missing_supplies'] = 'Missing supplies',
    ['turn_engine_off'] = 'Turn engine off first',
    
    -- Zones
    ['move_to_front'] = 'Move to the front of the car to fit this part',
    ['move_to_back'] = 'Move to the back of the car to fit this part',
    ['move_to_wheel'] = 'Move closer to a wheel to fit this part',
    
    -- NPC Jobs
    ['npc_job_request'] = 'NPC request: {type} {plate}',
    ['npc_job_must_be_on_duty'] = 'You must be on duty to start Local Jobs',
    
    -- POS System
    ['payment_sent'] = 'Payment request sent to customer',
    ['payment_cancelled'] = 'Payment cancelled',
    ['payment_accepted'] = 'Payment accepted',
    ['payment_declined'] = 'Payment declined',
    ['insufficient_funds'] = 'Customer has insufficient funds',
    ['invoice_paid'] = 'Invoice paid successfully',
    
    -- Diagnostics
    ['diagnostics_complete'] = 'Vehicle diagnostics complete',
    ['no_diagnostics'] = 'No diagnostics data available',
    ['diagnostics_menu_title'] = 'Vehicle Diagnostics',
    ['diagnostics_scan'] = 'Scan Vehicle',
    ['diagnostics_health'] = 'Health',
    ['diagnostics_plate'] = 'Plate',
    ['diagnostics_repairs_needed'] = 'Repairs Needed',
    ['diagnostics_repair_all'] = 'Repair All',
    ['diagnostics_installed'] = 'Installed',
    ['diagnostics_need'] = 'Need',
    ['diagnostics_npc_job'] = 'NPC Job',
    
    -- Menu Headers
    ['menu_preview'] = 'Preview Cosmetics',
    ['menu_diagnostics'] = 'Vehicle Diagnostics',
    ['menu_repairs'] = 'Repair Options',
    ['menu_paint'] = 'Paint Jobs',
    ['menu_mods'] = 'Modifications',
    ['menu_close'] = 'Close',
    ['menu_back'] = 'Back',
    
    -- Part Names
    ['part_alternator'] = 'Alternator',
    ['part_sparkplugs'] = 'Spark Plugs',
    ['part_carbattery'] = 'Car Battery',
    ['part_oil'] = 'Engine Oil',
    ['part_oil_filter'] = 'Oil Filter',
    ['part_brakes'] = 'Brake Pads',
    ['part_suspension'] = 'Suspension',
    ['part_axle'] = 'Axle',
    ['part_engine'] = 'Engine',
    ['part_body'] = 'Body Panel',
    ['part_tire'] = 'Tire',
    ['part_radiator'] = 'Radiator',
    ['part_coolant'] = 'Coolant',
    ['part_fuel_injector'] = 'Fuel Injector',
    ['part_transmission'] = 'Transmission',
    ['part_turbo'] = 'Turbo',
    
    -- Mod Types
    ['mod_spoiler'] = 'Spoiler',
    ['mod_front_bumper'] = 'Front Bumper',
    ['mod_rear_bumper'] = 'Rear Bumper',
    ['mod_side_skirt'] = 'Side Skirt',
    ['mod_exhaust'] = 'Exhaust',
    ['mod_grille'] = 'Grille',
    ['mod_hood'] = 'Hood',
    ['mod_fenders'] = 'Fenders',
    ['mod_right_fender'] = 'Right Fender',
    ['mod_roof'] = 'Roof',
    ['mod_livery'] = 'Livery',
    ['mod_wheels'] = 'Wheels',
    ['mod_window_tint'] = 'Window Tint',
    
    -- Colors
    ['color_primary'] = 'Primary Color',
    ['color_secondary'] = 'Secondary Color',
    ['color_pearlescent'] = 'Pearlescent',
    ['color_wheel'] = 'Wheel Color',
    ['color_custom_rgb'] = 'Custom RGB',
    
    -- Paint Types
    ['paint_classic'] = 'Classic',
    ['paint_metallic'] = 'Metallic',
    ['paint_matte'] = 'Matte',
    ['paint_metals'] = 'Metals',
    ['paint_util'] = 'Util',
    ['paint_chameleon'] = 'Chameleon',
    
    -- Preview menu descriptions
    ['preview_desc'] = 'Preview modifications',
    ['preview_paint_desc'] = 'Preview paint colors',
    ['preview_tint_desc'] = 'Preview tint levels',
    ['preview_exit_desc'] = 'Exit without saving',
    ['preview_close_revert'] = 'Close & Revert',
    ['paint_type'] = 'Paint Type',
    
    -- DPF / Rolling Coal
    ['dpf_installed'] = 'DPF installed',
    ['dpf_removed'] = 'DPF removed',
    ['dpf_remove'] = 'Remove DPF',
    ['dpf_install'] = 'Install DPF',
    ['dpf_enable'] = 'DPF removed: rolling coal enabled',
    ['dpf_disable'] = 'DPF installed: rolling coal disabled',
})
