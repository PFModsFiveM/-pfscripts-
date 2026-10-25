Config = Config or {}

-- pf-farming: crops grown on persistent plots. Harvests are ordinary pfm-inventory items with
-- freshness, sold to the produce market (NPC) or to businesses through pf-stores' player suppliers
-- (/supplier, /supplyoffer, /supplystock), which pays better than the market.
Config.Farming = {
    PlantRange = 2.5,           -- how close a player must be to a plot to water or harvest it
    MinPlotSpacing = 1.5,       -- metres between two plots
    MaxPlotsPerPlayer = 12,
    WaterItem = 'water_bottle', -- one is used per watering
    DieAfterDryMinutes = 120,   -- a plot left dry this long after its water ran out dies
    RotAfterReadyMinutes = 240, -- a ripe crop not harvested in this time rots
    ActionCooldownMs = 750,     -- per player, between plant/water/harvest/sell requests
    MarketRange = 4.0,

    Fields = {
        grapeseed = { label = 'Grapeseed Fields', coords = vector3(2030.6, 4910.4, 41.0), radius = 45.0 },
        paleto = { label = 'Paleto Farm', coords = vector3(410.4, 6474.8, 28.8), radius = 30.0 },
    },

    -- growMinutes: watered growing time needed (growth pauses while the plot is dry)
    -- waterMinutes: how long one watering lasts
    Crops = {
        tomato = { label = 'Tomato', seed = 'seed_tomato', item = 'tomato', growMinutes = 60, waterMinutes = 30, yield = { 4, 7 }, seedPrice = 2 },
        lettuce = { label = 'Lettuce', seed = 'seed_lettuce', item = 'lettuce', growMinutes = 45, waterMinutes = 30, yield = { 2, 4 }, seedPrice = 2 },
        potato = { label = 'Potato', seed = 'seed_potato', item = 'potato', growMinutes = 75, waterMinutes = 45, yield = { 4, 8 }, seedPrice = 2 },
        onion = { label = 'Onion', seed = 'seed_onion', item = 'onion', growMinutes = 60, waterMinutes = 45, yield = { 3, 6 }, seedPrice = 2 },
        bell_pepper = { label = 'Bell Pepper', seed = 'seed_bell_pepper', item = 'bell_pepper', growMinutes = 70, waterMinutes = 30, yield = { 3, 5 }, seedPrice = 3 },
        garlic = { label = 'Garlic', seed = 'seed_garlic', item = 'garlic', growMinutes = 50, waterMinutes = 45, yield = { 3, 6 }, seedPrice = 2 },
    },

    -- Crop props by growth stage (client only)
    StageModels = { 'prop_veg_crop_03_pump', 'prop_veg_crop_03_cab', 'prop_veg_crop_04_leaf' },

    -- The produce market buys below wholesale (pf-restaurants pays its AI wholesaler 1.5 per produce
    -- unit plus a markup), so selling to a business as a supplier earns more.
    Market = {
        label = 'Grapeseed Produce Market',
        coords = vector3(1678.4, 4881.6, 42.06),
        Buys = { tomato = 0.8, lettuce = 0.8, potato = 0.7, onion = 0.7, bell_pepper = 0.9, garlic = 0.8 },
        -- price share by freshness state; spoiled produce is refused
        FreshnessPrice = { fresh = 1.0, good = 0.85, stale = 0.4 },
        MaxPerSale = 500,
    },
}

-- Items this resource needs. Added at start only when no other resource defined them
-- (pf-restaurants defines the produce itself).
Config.FarmingItems = {
    seed_tomato = { label = 'Tomato Seeds', weight = 10 },
    seed_lettuce = { label = 'Lettuce Seeds', weight = 10 },
    seed_potato = { label = 'Seed Potatoes', weight = 50 },
    seed_onion = { label = 'Onion Sets', weight = 20 },
    seed_bell_pepper = { label = 'Pepper Seeds', weight = 10 },
    seed_garlic = { label = 'Garlic Cloves', weight = 20 },
    tomato = { label = 'Tomato', weight = 100 },
    lettuce = { label = 'Lettuce', weight = 200 },
    potato = { label = 'Potato', weight = 200 },
    onion = { label = 'Onion', weight = 150 },
    bell_pepper = { label = 'Bell Pepper', weight = 150 },
    garlic = { label = 'Garlic', weight = 50 },
}
