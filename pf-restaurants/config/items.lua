-- Item definitions and their properties for the restaurant system
Config.Items = {
    -- Raw Ingredients - Meats
    raw_beef_patty = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 15, storage = 'freezer'},
    raw_bacon = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 10, storage = 'fridge'},
    raw_chicken_breast = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 15, storage = 'fridge'},
    raw_sausage = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 12, storage = 'freezer'},
    pepperoni = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 8, storage = 'fridge'},
    italian_sausage = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 10, storage = 'fridge'},
    ground_beef = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 15, storage = 'freezer'},
    ham_sliced = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 8, storage = 'fridge'},
    
    -- Raw Ingredients - Produce
    lettuce = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 3, storage = 'fridge'},
    tomato = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 4, storage = 'fridge'},
    onion = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 4, storage = 'dry'},
    pickles_jar = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 2, storage = 'fridge'},
    potato = {category = 'produce', hungerComponent = 'carb', hungerValue = 8, storage = 'dry'},
    mushrooms = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 3, storage = 'fridge'},
    bell_pepper = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 4, storage = 'fridge'},
    jalapeno = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 2, storage = 'fridge'},
    basil_fresh = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 1, storage = 'fridge'},
    garlic = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 1, storage = 'dry'},
    spinach = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 3, storage = 'fridge'},
    arugula = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 3, storage = 'fridge'},
    
    -- Dairy
    cheese_slice = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 6, storage = 'fridge'},
    mozzarella_cheese = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 8, storage = 'fridge'},
    parmesan_cheese = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 7, storage = 'fridge'},
    cheddar_cheese = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 7, storage = 'fridge'},
    butter = {category = 'dairy', hungerComponent = 'fat', hungerValue = 10, storage = 'fridge'},
    milk = {category = 'dairy', thirstComponent = 'milk', thirstValue = 10, storage = 'fridge'},
    heavy_cream = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 8, storage = 'fridge'},
    ice_cream_vanilla = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 10, storage = 'freezer'},
    ice_cream_chocolate = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 10, storage = 'freezer'},
    ice_cream_strawberry = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 10, storage = 'freezer'},
    whipped_cream = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 5, storage = 'fridge'},
    
    -- Dry Goods / Carbs
    burger_bun = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 10, storage = 'dry'},
    hotdog_bun = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 8, storage = 'dry'},
    pizza_dough = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 12, storage = 'fridge'},
    flour = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 5, storage = 'dry'},
    sugar = {category = 'dry_goods', hungerComponent = 'sugar', hungerValue = 4, storage = 'dry'},
    salt = {category = 'dry_goods', hungerComponent = nil, hungerValue = 0, storage = 'dry'},
    pepper = {category = 'dry_goods', hungerComponent = nil, hungerValue = 0, storage = 'dry'},
    oregano = {category = 'dry_goods', hungerComponent = nil, hungerValue = 0, storage = 'dry'},
    breadcrumbs = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 5, storage = 'dry'},
    tortilla = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 8, storage = 'dry'},
    rice = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 10, storage = 'dry'},
    pasta = {category = 'dry_goods', hungerComponent = 'carb', hungerValue = 12, storage = 'dry'},
    
    -- Sauces & Condiments
    ketchup = {category = 'dry_goods', hungerComponent = 'sugar', hungerValue = 2, storage = 'dry'},
    mustard = {category = 'dry_goods', hungerComponent = nil, hungerValue = 1, storage = 'dry'},
    mayonnaise = {category = 'dry_goods', hungerComponent = 'fat', hungerValue = 8, storage = 'fridge'},
    bbq_sauce = {category = 'dry_goods', hungerComponent = 'sugar', hungerValue = 3, storage = 'dry'},
    hot_sauce = {category = 'dry_goods', hungerComponent = nil, hungerValue = 1, storage = 'dry'},
    ranch_dressing = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 5, storage = 'fridge'},
    tomato_sauce = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 3, storage = 'dry'},
    marinara_sauce = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 4, storage = 'dry'},
    alfredo_sauce = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 8, storage = 'fridge'},
    pesto_sauce = {category = 'produce', hungerComponent = 'vegetable', hungerValue = 5, storage = 'fridge'},
    
    -- Beverages - Dry/Syrup
    soda_syrup_cola = {category = 'beverages', thirstComponent = 'soda', thirstValue = 15, storage = 'dry'},
    soda_syrup_orange = {category = 'beverages', thirstComponent = 'soda', thirstValue = 15, storage = 'dry'},
    soda_syrup_lemon = {category = 'beverages', thirstComponent = 'soda', thirstValue = 15, storage = 'dry'},
    soda_syrup_cherry = {category = 'beverages', thirstComponent = 'soda', thirstValue = 15, storage = 'dry'},
    coffee_beans = {category = 'beverages', thirstComponent = 'coffee', thirstValue = 12, storage = 'dry'},
    tea_bags = {category = 'beverages', thirstComponent = 'water', thirstValue = 10, storage = 'dry'},
    orange_juice_concentrate = {category = 'beverages', thirstComponent = 'juice', thirstValue = 18, storage = 'freezer'},
    apple_juice_concentrate = {category = 'beverages', thirstComponent = 'juice', thirstValue = 18, storage = 'freezer'},
    chocolate_syrup = {category = 'beverages', hungerComponent = 'sugar', hungerValue = 6, storage = 'dry'},
    strawberry_syrup = {category = 'beverages', hungerComponent = 'sugar', hungerValue = 6, storage = 'dry'},
    vanilla_extract = {category = 'beverages', hungerComponent = nil, hungerValue = 0, storage = 'dry'},
    -- from the vineyard (pf-jobs vineyard job, sold to restaurants through the Supplier app)
    wine = {category = 'beverages', thirstComponent = 'juice', thirstValue = 10, storage = 'dry'},
    grapejuice = {category = 'beverages', thirstComponent = 'juice', thirstValue = 18, storage = 'fridge'},

    -- Dessert Ingredients
    brownie_mix = {category = 'dry_goods', hungerComponent = 'sugar', hungerValue = 15, storage = 'dry'},
    cookie_dough = {category = 'frozen', hungerComponent = 'sugar', hungerValue = 12, storage = 'freezer'},
    pie_crust = {category = 'frozen', hungerComponent = 'carb', hungerValue = 8, storage = 'freezer'},
    apple_pie_filling = {category = 'dry_goods', hungerComponent = 'sugar', hungerValue = 10, storage = 'dry'},
    cherry_pie_filling = {category = 'dry_goods', hungerComponent = 'sugar', hungerValue = 10, storage = 'dry'},
    chocolate_chips = {category = 'dry_goods', hungerComponent = 'sugar', hungerValue = 8, storage = 'dry'},
    
    -- Oils & Fats
    cooking_oil = {category = 'dry_goods', hungerComponent = 'fat', hungerValue = 12, storage = 'dry'},
    olive_oil = {category = 'dry_goods', hungerComponent = 'fat', hungerValue = 12, storage = 'dry'},
    
    -- Prepared Components (outputs from prep stations)
    lettuce_shredded = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 3, storage = 'fridge'},
    tomato_sliced = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 4, storage = 'fridge'},
    onions_chopped = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 4, storage = 'fridge'},
    onions_sliced = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 4, storage = 'fridge'},
    pickles_sliced = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 2, storage = 'fridge'},
    mushrooms_sliced = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 3, storage = 'fridge'},
    bell_pepper_sliced = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 4, storage = 'fridge'},
    jalapeno_sliced = {category = 'meat_cooked', hungerComponent = 'vegetable', hungerValue = 2, storage = 'fridge'},
    fries_raw = {category = 'produce', hungerComponent = 'carb', hungerValue = 10, storage = 'fridge'},
    pizza_dough_stretched = {category = 'meat_cooked', hungerComponent = 'carb', hungerValue = 12, storage = 'fridge'},
    
    -- Raw Items for Frying/Breading
    onion_rings_raw = {category = 'produce', hungerComponent = 'carb', hungerValue = 8, storage = 'fridge'},
    chicken_tenders_raw = {category = 'meat_raw', hungerComponent = 'protein', hungerValue = 14, storage = 'fridge'},
    mozzarella_sticks_raw = {category = 'dairy', hungerComponent = 'dairy', hungerValue = 10, storage = 'fridge'},
    
    -- Cooked Components
    patty_cooked = {category = 'meat_cooked', hungerComponent = 'protein', hungerValue = 15, storage = 'fridge', requiresDoneness = true},
    bacon_cooked = {category = 'meat_cooked', hungerComponent = 'protein', hungerValue = 10, storage = 'fridge'},
    chicken_cooked = {category = 'meat_cooked', hungerComponent = 'protein', hungerValue = 15, storage = 'fridge', requiresDoneness = true},
    sausage_cooked = {category = 'meat_cooked', hungerComponent = 'protein', hungerValue = 12, storage = 'fridge'},
    fries_cooked = {category = 'meat_cooked', hungerComponent = 'carb', hungerValue = 12, storage = 'fridge'},
    onion_rings_cooked = {category = 'meat_cooked', hungerComponent = 'carb', hungerValue = 10, storage = 'fridge'},
    chicken_tenders_cooked = {category = 'meat_cooked', hungerComponent = 'protein', hungerValue = 16, storage = 'fridge'},
    mozzarella_sticks_cooked = {category = 'meat_cooked', hungerComponent = 'dairy', hungerValue = 12, storage = 'fridge'},
    
    -- Burnt Items
    patty_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -5, storage = 'none'},
    bacon_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -3, storage = 'none'},
    chicken_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -5, storage = 'none'},
    sausage_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -4, storage = 'none'},
    fries_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -3, storage = 'none'},
    onion_rings_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -3, storage = 'none'},
    chicken_tenders_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -5, storage = 'none'},
    mozzarella_sticks_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -4, storage = 'none'},
    pizza_burnt = {category = 'waste', hungerComponent = nil, hungerValue = -8, storage = 'none'},
    
    -- Final Products - Burgers
    burger_classic = {category = 'final', hungerValue = 45, isConsumable = true},
    burger_cheese = {category = 'final', hungerValue = 50, isConsumable = true},
    burger_double = {category = 'final', hungerValue = 65, isConsumable = true},
    burger_triple = {category = 'final', hungerValue = 80, isConsumable = true},
    burger_bacon = {category = 'final', hungerValue = 55, isConsumable = true},
    burger_mushroom = {category = 'final', hungerValue = 52, isConsumable = true},
    burger_veggie = {category = 'final', hungerValue = 40, isConsumable = true},
    burger_chicken = {category = 'final', hungerValue = 48, isConsumable = true},
    
    -- Final Products - Sandwiches & Hotdogs
    hotdog_classic = {category = 'final', hungerValue = 35, isConsumable = true},
    hotdog_chili = {category = 'final', hungerValue = 42, isConsumable = true},
    sandwich_blt = {category = 'final', hungerValue = 45, isConsumable = true},
    sandwich_club = {category = 'final', hungerValue = 52, isConsumable = true},
    sandwich_chicken = {category = 'final', hungerValue = 48, isConsumable = true},
    
    -- Final Products - Pizza
    pizza_margherita = {category = 'final', hungerValue = 60, isConsumable = true},
    pizza_pepperoni = {category = 'final', hungerValue = 65, isConsumable = true},
    pizza_supreme = {category = 'final', hungerValue = 75, isConsumable = true},
    pizza_meat_lovers = {category = 'final', hungerValue = 80, isConsumable = true},
    pizza_veggie = {category = 'final', hungerValue = 58, isConsumable = true},
    pizza_bbq_chicken = {category = 'final', hungerValue = 70, isConsumable = true},
    pizza_hawaiian = {category = 'final', hungerValue = 65, isConsumable = true},
    pizza_slice_pepperoni = {category = 'final', hungerValue = 12, isConsumable = true},
    pizza_slice_cheese = {category = 'final', hungerValue = 10, isConsumable = true},
    
    -- Final Products - Sides
    fries_small = {category = 'final', hungerValue = 15, isConsumable = true},
    fries_medium = {category = 'final', hungerValue = 22, isConsumable = true},
    fries_large = {category = 'final', hungerValue = 30, isConsumable = true},
    onion_rings = {category = 'final', hungerValue = 25, isConsumable = true},
    chicken_tenders = {category = 'final', hungerValue = 35, isConsumable = true},
    chicken_wings = {category = 'final', hungerValue = 40, isConsumable = true},
    mozzarella_sticks = {category = 'final', hungerValue = 28, isConsumable = true},
    garlic_bread = {category = 'final', hungerValue = 20, isConsumable = true},
    breadsticks = {category = 'final', hungerValue = 18, isConsumable = true},
    
    -- Final Products - Desserts
    brownie = {category = 'final', hungerValue = 25, isConsumable = true},
    cookie_chocolate_chip = {category = 'final', hungerValue = 15, isConsumable = true},
    apple_pie = {category = 'final', hungerValue = 35, isConsumable = true},
    cherry_pie = {category = 'final', hungerValue = 35, isConsumable = true},
    ice_cream_sundae = {category = 'final', hungerValue = 30, isConsumable = true},
    milkshake_vanilla = {category = 'final', hungerValue = 20, thirstValue = 15, isConsumable = true},
    milkshake_chocolate = {category = 'final', hungerValue = 22, thirstValue = 15, isConsumable = true},
    milkshake_strawberry = {category = 'final', hungerValue = 22, thirstValue = 15, isConsumable = true},
    
    -- Final Products - Drinks
    soda_small = {category = 'final', thirstValue = 20, isConsumable = true},
    soda_medium = {category = 'final', thirstValue = 30, isConsumable = true},
    soda_large = {category = 'final', thirstValue = 40, isConsumable = true},
    coffee_black = {category = 'final', thirstValue = 25, isConsumable = true},
    coffee_latte = {category = 'final', thirstValue = 22, hungerValue = 8, isConsumable = true},
    coffee_cappuccino = {category = 'final', thirstValue = 22, hungerValue = 8, isConsumable = true},
    orange_juice = {category = 'final', thirstValue = 35, isConsumable = true},
    apple_juice = {category = 'final', thirstValue = 35, isConsumable = true},
    water_bottle = {category = 'final', thirstValue = 40, isConsumable = true},
    iced_tea = {category = 'final', thirstValue = 30, isConsumable = true},
    wine_glass = {category = 'final', thirstValue = 15, isConsumable = true},          -- poured from a bottle of wine
    grape_juice_glass = {category = 'final', thirstValue = 30, isConsumable = true},   -- poured from grape juice
    
    -- Supplies & Equipment
    cleaning_supplies = {category = 'supplies', storage = 'dry'},
    fryer_oil_new = {category = 'supplies', storage = 'dry'},
    ice_bag = {category = 'supplies', storage = 'freezer'},
    pest_spray = {category = 'supplies', storage = 'dry'},
    fire_extinguisher = {category = 'supplies', storage = 'dry'},
    trash_bag = {category = 'supplies', storage = 'dry'},
    
    -- Waste
    burnt_food = {category = 'waste', storage = 'none'},
    food_waste = {category = 'waste', storage = 'none'},
}
