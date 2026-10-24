Config.Stations = {
    -- Burger Shot Vespucci
    ['burgershot_vespucci'] = {
        -- Grills
        {
            stationId = 'bs_grill_1',
            type = 'grill',
            label = 'Grill #1',
            coords = vector3(-1200.5, -891.2, 13.98),
            heading = 35.0,
            slots = 4,
            propModel = 'prop_cs_burger_01',
            propOffsets = {
                {x = -0.2, y = 0.0, z = 1.0},
                {x = 0.0, y = 0.0, z = 1.0},
                {x = 0.2, y = 0.0, z = 1.0},
                {x = 0.4, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Grill Patty', action = 'grill_patty'},
                    {label = 'Grill Bacon', action = 'grill_bacon'},
                    {label = 'Clean Grill', action = 'clean_grill', permission = 'equipment.clean'},
                }
            }
        },
        {
            stationId = 'bs_grill_2',
            type = 'grill',
            label = 'Grill #2',
            coords = vector3(-1201.2, -890.5, 13.98),
            heading = 35.0,
            slots = 4,
            propModel = 'prop_cs_burger_01',
            propOffsets = {
                {x = -0.2, y = 0.0, z = 1.0},
                {x = 0.0, y = 0.0, z = 1.0},
                {x = 0.2, y = 0.0, z = 1.0},
                {x = 0.4, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Grill Patty', action = 'grill_patty'},
                    {label = 'Grill Bacon', action = 'grill_bacon'},
                    {label = 'Clean Grill', action = 'clean_grill', permission = 'equipment.clean'},
                }
            }
        },
        
        -- Fryers
        {
            stationId = 'bs_fryer_1',
            type = 'fryer',
            label = 'Deep Fryer',
            coords = vector3(-1199.8, -892.0, 13.98),
            heading = 35.0,
            slots = 2,
            propModel = 'prop_cs_fries',
            propOffsets = {
                {x = -0.15, y = 0.0, z = 1.0},
                {x = 0.15, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Fry Items', action = 'fry'},
                    {label = 'Change Oil', action = 'change_oil', permission = 'equipment.clean'},
                }
            }
        },
        
        -- Prep Stations
        {
            stationId = 'bs_chop_1',
            type = 'chop',
            label = 'Chopping Board',
            coords = vector3(-1198.5, -893.2, 13.98),
            heading = 125.0,
            slots = 2,
            propModel = 'prop_veg_crop_03_cab',
            propOffsets = {
                {x = -0.1, y = 0.0, z = 1.0},
                {x = 0.1, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Chop Vegetables', action = 'chop'},
                }
            }
        },
        {
            stationId = 'bs_slice_1',
            type = 'slice',
            label = 'Slicing Station',
            coords = vector3(-1197.8, -893.8, 13.98),
            heading = 125.0,
            slots = 2,
            propModel = 'prop_veg_crop_03_cab',
            propOffsets = {
                {x = -0.1, y = 0.0, z = 1.0},
                {x = 0.1, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Slice Ingredients', action = 'slice'},
                }
            }
        },
        
        -- Assembly Counter
        {
            stationId = 'bs_assembly_1',
            type = 'assembly',
            label = 'Assembly Counter',
            coords = vector3(-1196.2, -894.8, 13.98),
            heading = 125.0,
            slots = 3,
            propModel = 'prop_food_bs_tray_01',
            propOffsets = {
                {x = -0.2, y = 0.0, z = 1.0},
                {x = 0.0, y = 0.0, z = 1.0},
                {x = 0.2, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Assemble Order', action = 'assemble'},
                }
            }
        },
        
        -- Drink Station
        {
            stationId = 'bs_drink_1',
            type = 'drink',
            label = 'Soda Fountain',
            coords = vector3(-1195.0, -895.5, 13.98),
            heading = 125.0,
            slots = 2,
            propModel = 'prop_food_bs_juice01',
            propOffsets = {
                {x = -0.1, y = 0.0, z = 1.0},
                {x = 0.1, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Fill Drink', action = 'fill_drink'},
                    {label = 'Refill Ice', action = 'refill_ice', permission = 'equipment.clean'},
                }
            }
        },
        
        -- Coffee/Shake Station
        {
            stationId = 'bs_coffee_1',
            type = 'coffee',
            label = 'Coffee & Shake Machine',
            coords = vector3(-1194.2, -896.2, 13.98),
            heading = 125.0,
            slots = 2,
            propModel = 'prop_food_bs_coffee',
            propOffsets = {
                {x = -0.1, y = 0.0, z = 1.0},
                {x = 0.1, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Make Coffee', action = 'make_coffee'},
                    {label = 'Make Shake', action = 'make_shake'},
                }
            }
        },
    },
    
    -- Pizza This
    ['pizzathis'] = {
        -- Pizza Ovens
        {
            stationId = 'pz_oven_1',
            type = 'oven',
            label = 'Pizza Oven #1',
            coords = vector3(811.5, -751.2, 26.78),
            heading = 0.0,
            slots = 2,
            propModel = 'v_res_fa_bread04',
            propOffsets = {
                {x = -0.2, y = 0.0, z = 1.0},
                {x = 0.2, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Bake Pizza', action = 'bake_pizza'},
                    {label = 'Clean Oven', action = 'clean_oven', permission = 'equipment.clean'},
                }
            }
        },
        
        -- Prep Counter
        {
            stationId = 'pz_prep_1',
            type = 'prep',
            label = 'Prep Counter',
            coords = vector3(810.2, -750.5, 26.78),
            heading = 90.0,
            slots = 3,
            propModel = 'prop_veg_crop_03_cab',
            propOffsets = {
                {x = -0.2, y = 0.0, z = 1.0},
                {x = 0.0, y = 0.0, z = 1.0},
                {x = 0.2, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Prepare Dough', action = 'prep_dough'},
                    {label = 'Prep Toppings', action = 'prep_toppings'},
                }
            }
        },
        
        -- Assembly
        {
            stationId = 'pz_assembly_1',
            type = 'assembly',
            label = 'Assembly Station',
            coords = vector3(809.5, -749.8, 26.78),
            heading = 90.0,
            slots = 2,
            propModel = 'prop_food_bs_tray_01',
            propOffsets = {
                {x = -0.15, y = 0.0, z = 1.0},
                {x = 0.15, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Assemble Pizza', action = 'assemble_pizza'},
                    {label = 'Box Pizza', action = 'box_pizza'},
                }
            }
        },
        
        -- Drink Station
        {
            stationId = 'pz_drink_1',
            type = 'drink',
            label = 'Drink Station',
            coords = vector3(808.2, -749.2, 26.78),
            heading = 90.0,
            slots = 2,
            propModel = 'prop_food_bs_juice01',
            propOffsets = {
                {x = -0.1, y = 0.0, z = 1.0},
                {x = 0.1, y = 0.0, z = 1.0},
            },
            interaction = {
                distance = 1.5,
                options = {
                    {label = 'Fill Drink', action = 'fill_drink'},
                }
            }
        },
    }
}

-- Registers (POS terminals)
Config.Registers = {
    ['burgershot_vespucci'] = {
        {
            registerId = 'bs_register_1',
            coords = vector3(-1195.5, -892.0, 13.98),
            heading = 215.0,
            model = 'prop_till_01',
        },
        {
            registerId = 'bs_register_2',
            coords = vector3(-1194.8, -893.2, 13.98),
            heading = 215.0,
            model = 'prop_till_01',
        },
    },
    ['pizzathis'] = {
        {
            registerId = 'pz_register_1',
            coords = vector3(808.9, -751.3, 26.78),
            heading = 0.0,
            model = 'prop_till_01',
        },
    }
}

-- DUI Screens
Config.Screens = {
    ['burgershot_vespucci'] = {
        -- KDS Screens
        {
            screenId = 'bs_kds_1',
            type = 'kds',
            coords = vector3(-1198.0, -890.5, 14.5),
            heading = 215.0,
            model = 'prop_tv_flat_03',
            scale = 0.5,
            route = 'kds'
        },
        {
            screenId = 'bs_kds_2',
            type = 'kds',
            coords = vector3(-1196.5, -891.8, 14.5),
            heading = 215.0,
            model = 'prop_tv_flat_03',
            scale = 0.5,
            route = 'kds'
        },
        -- Menu Board
        {
            screenId = 'bs_menu_1',
            type = 'menu',
            coords = vector3(-1193.2, -894.8, 15.0),
            heading = 35.0,
            model = 'prop_tv_flat_03b',
            scale = 0.8,
            route = 'menu'
        },
    },
    ['pizzathis'] = {
        -- KDS Screen
        {
            screenId = 'pz_kds_1',
            type = 'kds',
            coords = vector3(810.5, -748.2, 27.5),
            heading = 270.0,
            model = 'prop_tv_flat_03',
            scale = 0.5,
            route = 'kds'
        },
        -- Menu Board
        {
            screenId = 'pz_menu_1',
            type = 'menu',
            coords = vector3(809.2, -762.5, 27.8),
            heading = 180.0,
            model = 'prop_tv_flat_03b',
            scale = 0.8,
            route = 'menu'
        },
    }
}
