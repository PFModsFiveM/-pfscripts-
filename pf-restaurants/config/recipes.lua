-- Component Production Rules (Prep Steps)
Config.ComponentRules = {
    -- Grilling
    {
        input = {
            {item = 'raw_beef_patty', qty = 1}
        },
        stationType = 'grill',
        duration = 30000, -- 30 seconds
        output = {
            {item = 'patty_cooked', qty = 1}
        },
        requiresDoneness = true,
        action = 'grill_patty'
    },
    {
        input = {
            {item = 'raw_bacon', qty = 2}
        },
        stationType = 'grill',
        duration = 25000,
        output = {
            {item = 'bacon_cooked', qty = 2}
        },
        action = 'grill_bacon'
    },
    {
        input = {
            {item = 'raw_chicken_breast', qty = 1}
        },
        stationType = 'grill',
        duration = 35000,
        output = {
            {item = 'chicken_cooked', qty = 1}
        },
        requiresDoneness = true,
        action = 'grill_chicken'
    },
    {
        input = {
            {item = 'raw_sausage', qty = 1}
        },
        stationType = 'grill',
        duration = 28000,
        output = {
            {item = 'sausage_cooked', qty = 1}
        },
        action = 'grill_sausage'
    },
    
    -- Frying
    {
        input = {
            {item = 'fries_raw', qty = 1}
        },
        stationType = 'fryer',
        duration = 45000,
        output = {
            {item = 'fries_cooked', qty = 1}
        },
        action = 'fry'
    },
    {
        input = {
            {item = 'onion', qty = 2},
            {item = 'breadcrumbs', qty = 1}
        },
        stationType = 'fryer',
        duration = 40000,
        output = {
            {item = 'onion_rings_cooked', qty = 1}
        },
        action = 'fry'
    },
    {
        input = {
            {item = 'raw_chicken_breast', qty = 1},
            {item = 'breadcrumbs', qty = 1}
        },
        stationType = 'fryer',
        duration = 50000,
        output = {
            {item = 'chicken_tenders_cooked', qty = 3}
        },
        action = 'fry'
    },
    {
        input = {
            {item = 'mozzarella_cheese', qty = 1},
            {item = 'breadcrumbs', qty = 1}
        },
        stationType = 'fryer',
        duration = 35000,
        output = {
            {item = 'mozzarella_sticks_cooked', qty = 6}
        },
        action = 'fry'
    },
    
    -- Chopping
    {
        input = {
            {item = 'onion', qty = 1}
        },
        stationType = 'chop',
        duration = 10000,
        output = {
            {item = 'onions_chopped', qty = 1}
        },
        action = 'chop'
    },
    {
        input = {
            {item = 'lettuce', qty = 1}
        },
        stationType = 'chop',
        duration = 8000,
        output = {
            {item = 'lettuce_shredded', qty = 1}
        },
        action = 'chop'
    },
    {
        input = {
            {item = 'potato', qty = 2}
        },
        stationType = 'chop',
        duration = 15000,
        output = {
            {item = 'fries_raw', qty = 1}
        },
        action = 'chop'
    },
    {
        input = {
            {item = 'mushrooms', qty = 1}
        },
        stationType = 'chop',
        duration = 8000,
        output = {
            {item = 'mushrooms_sliced', qty = 1}
        },
        action = 'chop'
    },
    
    -- Slicing
    {
        input = {
            {item = 'tomato', qty = 1}
        },
        stationType = 'slice',
        duration = 8000,
        output = {
            {item = 'tomato_sliced', qty = 1}
        },
        action = 'slice'
    },
    {
        input = {
            {item = 'pickles_jar', qty = 1}
        },
        stationType = 'slice',
        duration = 12000,
        output = {
            {item = 'pickles_sliced', qty = 4}
        },
        action = 'slice'
    },
    {
        input = {
            {item = 'onion', qty = 1}
        },
        stationType = 'slice',
        duration = 8000,
        output = {
            {item = 'onions_sliced', qty = 1}
        },
        action = 'slice'
    },
    {
        input = {
            {item = 'bell_pepper', qty = 1}
        },
        stationType = 'slice',
        duration = 10000,
        output = {
            {item = 'bell_pepper_sliced', qty = 1}
        },
        action = 'slice'
    },
    {
        input = {
            {item = 'jalapeno', qty = 1}
        },
        stationType = 'slice',
        duration = 8000,
        output = {
            {item = 'jalapeno_sliced', qty = 1}
        },
        action = 'slice'
    },
    
    -- Pizza Prep
    {
        input = {
            {item = 'pizza_dough', qty = 1}
        },
        stationType = 'prep',
        duration = 20000,
        output = {
            {item = 'pizza_dough_stretched', qty = 1}
        },
        action = 'prep_dough'
    },
    
    -- Baking
    {
        input = {
            {item = 'pizza_dough_stretched', qty = 1},
            {item = 'marinara_sauce', qty = 1},
            {item = 'mozzarella_cheese', qty = 1}
        },
        stationType = 'oven',
        duration = 60000,
        output = {
            {item = 'pizza_margherita', qty = 1}
        },
        action = 'bake_pizza'
    },
    {
        input = {
            {item = 'brownie_mix', qty = 1},
            {item = 'butter', qty = 1}
        },
        stationType = 'oven',
        duration = 45000,
        output = {
            {item = 'brownie', qty = 4}
        },
        action = 'bake'
    },
    
    -- Drinks
    {
        input = {
            {item = 'soda_syrup_cola', qty = 1}
        },
        stationType = 'drink',
        duration = 5000,
        output = {
            {item = 'soda_medium', qty = 1}
        },
        action = 'fill_drink'
    },
    -- wine and grape juice from the vineyard, poured at the drink station (Fill Drink) from the
    -- restaurant's stock: a bottle of wine gives four glasses, a grape juice two
    {
        input = {
            {item = 'wine', qty = 1}
        },
        stationType = 'drink',
        duration = 8000,
        output = {
            {item = 'wine_glass', qty = 4}
        },
        action = 'fill_drink'
    },
    {
        input = {
            {item = 'grapejuice', qty = 1}
        },
        stationType = 'drink',
        duration = 5000,
        output = {
            {item = 'grape_juice_glass', qty = 2}
        },
        action = 'fill_drink'
    },
    {
        input = {
            {item = 'coffee_beans', qty = 1}
        },
        stationType = 'coffee',
        duration = 15000,
        output = {
            {item = 'coffee_black', qty = 1}
        },
        action = 'make_coffee'
    },
    {
        input = {
            {item = 'ice_cream_vanilla', qty = 1},
            {item = 'milk', qty = 1}
        },
        stationType = 'coffee',
        duration = 20000,
        output = {
            {item = 'milkshake_vanilla', qty = 1}
        },
        action = 'make_shake'
    },
}

-- Recipe Definitions (Final Products via Assembly)
Config.Recipes = {
    -- Drinks poured at the drink station (see the 'fill_drink' rules above); put them on the menu
    -- like any dish. The glass is the drink served.
    wine_glass = {
        recipeId = 'wine_glass',
        label = 'Glass of Wine',
        category = 'drinks',
        components = {
            {item = 'wine_glass', qty = 1, optional = false},
        },
        output = {
            item = 'wine_glass',
            qty = 1
        },
        baseThirst = 15
    },

    grape_juice_glass = {
        recipeId = 'grape_juice_glass',
        label = 'Grape Juice',
        category = 'drinks',
        components = {
            {item = 'grape_juice_glass', qty = 1, optional = false},
        },
        output = {
            item = 'grape_juice_glass',
            qty = 1
        },
        baseThirst = 30
    },

    -- Classic Burger
    burger_classic = {
        recipeId = 'burger_classic',
        label = 'Classic Burger',
        category = 'burgers',
        components = {
            {item = 'burger_bun', qty = 1, optional = false},
            {item = 'patty_cooked', qty = 1, optional = false, requiresDoneness = true},
            {item = 'lettuce_shredded', qty = 1, optional = true},
            {item = 'tomato_sliced', qty = 1, optional = true},
            {item = 'pickles_sliced', qty = 2, optional = true},
            {item = 'onions_sliced', qty = 1, optional = true},
            {item = 'ketchup', qty = 1, optional = true},
            {item = 'mustard', qty = 1, optional = true},
        },
        output = {
            item = 'burger_classic',
            qty = 1
        },
        baseHunger = 45,
        allowedMods = {
            'remove_lettuce',
            'remove_tomato',
            'remove_pickles',
            'remove_onions',
            'remove_ketchup',
            'remove_mustard',
            'doneness_choice'
        }
    },
    
    -- Cheeseburger
    burger_cheese = {
        recipeId = 'burger_cheese',
        label = 'Cheeseburger',
        category = 'burgers',
        components = {
            {item = 'burger_bun', qty = 1, optional = false},
            {item = 'patty_cooked', qty = 1, optional = false, requiresDoneness = true},
            {item = 'cheese_slice', qty = 1, optional = false},
            {item = 'lettuce_shredded', qty = 1, optional = true},
            {item = 'tomato_sliced', qty = 1, optional = true},
            {item = 'pickles_sliced', qty = 2, optional = true},
            {item = 'onions_sliced', qty = 1, optional = true},
            {item = 'ketchup', qty = 1, optional = true},
            {item = 'mustard', qty = 1, optional = true},
        },
        output = {
            item = 'burger_cheese',
            qty = 1
        },
        baseHunger = 50,
        allowedMods = {
            'remove_lettuce',
            'remove_tomato',
            'remove_pickles',
            'remove_onions',
            'extra_cheese',
            'doneness_choice'
        }
    },
    
    -- Double Cheeseburger
    burger_double = {
        recipeId = 'burger_double',
        label = 'Double Cheeseburger',
        category = 'burgers',
        components = {
            {item = 'burger_bun', qty = 1, optional = false},
            {item = 'patty_cooked', qty = 2, optional = false, requiresDoneness = true},
            {item = 'cheese_slice', qty = 2, optional = false},
            {item = 'lettuce_shredded', qty = 1, optional = true},
            {item = 'tomato_sliced', qty = 1, optional = true},
            {item = 'pickles_sliced', qty = 2, optional = true},
            {item = 'onions_chopped', qty = 1, optional = true},
            {item = 'ketchup', qty = 1, optional = true},
        },
        output = {
            item = 'burger_double',
            qty = 1
        },
        baseHunger = 65,
        allowedMods = {
            'remove_lettuce',
            'remove_tomato',
            'remove_pickles',
            'remove_onions',
            'extra_cheese',
            'doneness_choice'
        }
    },
    
    -- Triple Cheeseburger
    burger_triple = {
        recipeId = 'burger_triple',
        label = 'Triple Cheeseburger',
        category = 'burgers',
        components = {
            {item = 'burger_bun', qty = 1, optional = false},
            {item = 'patty_cooked', qty = 3, optional = false, requiresDoneness = true},
            {item = 'cheese_slice', qty = 3, optional = false},
            {item = 'lettuce_shredded', qty = 1, optional = true},
            {item = 'pickles_sliced', qty = 2, optional = true},
            {item = 'onions_chopped', qty = 1, optional = true},
        },
        output = {
            item = 'burger_triple',
            qty = 1
        },
        baseHunger = 80,
        allowedMods = {
            'remove_pickles',
            'remove_onions',
            'extra_cheese',
            'doneness_choice'
        }
    },
    
    -- Bacon Burger
    burger_bacon = {
        recipeId = 'burger_bacon',
        label = 'Bacon Burger',
        category = 'burgers',
        components = {
            {item = 'burger_bun', qty = 1, optional = false},
            {item = 'patty_cooked', qty = 1, optional = false, requiresDoneness = true},
            {item = 'cheese_slice', qty = 1, optional = false},
            {item = 'bacon_cooked', qty = 2, optional = false},
            {item = 'lettuce_shredded', qty = 1, optional = true},
            {item = 'tomato_sliced', qty = 1, optional = true},
            {item = 'mayonnaise', qty = 1, optional = true},
        },
        output = {
            item = 'burger_bacon',
            qty = 1
        },
        baseHunger = 55,
        allowedMods = {
            'remove_lettuce',
            'remove_tomato',
            'extra_bacon',
            'doneness_choice'
        }
    },
    
    -- Fries
    fries_small = {
        recipeId = 'fries_small',
        label = 'Small Fries',
        category = 'sides',
        components = {
            {item = 'fries_cooked', qty = 1, optional = false},
            {item = 'salt', qty = 1, optional = true},
        },
        output = {
            item = 'fries_small',
            qty = 1
        },
        baseHunger = 15
    },
    
    fries_medium = {
        recipeId = 'fries_medium',
        label = 'Medium Fries',
        category = 'sides',
        components = {
            {item = 'fries_cooked', qty = 2, optional = false},
            {item = 'salt', qty = 1, optional = true},
        },
        output = {
            item = 'fries_medium',
            qty = 1
        },
        baseHunger = 22
    },
    
    fries_large = {
        recipeId = 'fries_large',
        label = 'Large Fries',
        category = 'sides',
        components = {
            {item = 'fries_cooked', qty = 3, optional = false},
            {item = 'salt', qty = 1, optional = true},
        },
        output = {
            item = 'fries_large',
            qty = 1
        },
        baseHunger = 30
    },
    
    -- Onion Rings
    onion_rings = {
        recipeId = 'onion_rings',
        label = 'Onion Rings',
        category = 'sides',
        components = {
            {item = 'onion_rings_cooked', qty = 1, optional = false},
            {item = 'salt', qty = 1, optional = true},
        },
        output = {
            item = 'onion_rings',
            qty = 1
        },
        baseHunger = 25
    },
    
    -- Chicken Tenders
    chicken_tenders = {
        recipeId = 'chicken_tenders',
        label = 'Chicken Tenders',
        category = 'sides',
        components = {
            {item = 'chicken_tenders_cooked', qty = 1, optional = false},
            {item = 'bbq_sauce', qty = 1, optional = true},
            {item = 'ranch_dressing', qty = 1, optional = true},
        },
        output = {
            item = 'chicken_tenders',
            qty = 1
        },
        baseHunger = 35
    },
    
    -- Pepperoni Pizza
    pizza_pepperoni = {
        recipeId = 'pizza_pepperoni',
        label = 'Pepperoni Pizza',
        category = 'pizza',
        components = {
            {item = 'pizza_dough_stretched', qty = 1, optional = false},
            {item = 'marinara_sauce', qty = 1, optional = false},
            {item = 'mozzarella_cheese', qty = 2, optional = false},
            {item = 'pepperoni', qty = 3, optional = false},
            {item = 'oregano', qty = 1, optional = true},
        },
        output = {
            item = 'pizza_pepperoni',
            qty = 1
        },
        baseHunger = 65,
        requiresOven = true
    },
    
    -- Supreme Pizza
    pizza_supreme = {
        recipeId = 'pizza_supreme',
        label = 'Supreme Pizza',
        category = 'pizza',
        components = {
            {item = 'pizza_dough_stretched', qty = 1, optional = false},
            {item = 'marinara_sauce', qty = 1, optional = false},
            {item = 'mozzarella_cheese', qty = 2, optional = false},
            {item = 'pepperoni', qty = 2, optional = false},
            {item = 'italian_sausage', qty = 1, optional = false},
            {item = 'bell_pepper_sliced', qty = 1, optional = false},
            {item = 'mushrooms_sliced', qty = 1, optional = false},
            {item = 'onions_sliced', qty = 1, optional = false},
        },
        output = {
            item = 'pizza_supreme',
            qty = 1
        },
        baseHunger = 75,
        requiresOven = true
    },
}
