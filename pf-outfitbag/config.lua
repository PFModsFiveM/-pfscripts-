Config = {}

-- Framework selection: 'qbcore' or 'esx'
Config.Framework = 'qbcore'

-- Inventory system: for ESX, use 'ox_inventory' or 'core_inventory'
Config.Inventory = 'default' -- For QBCore: 'default'. For ESX: 'ox_inventory' or 'core_inventory'

-- Item name for the outfit bag
Config.ItemName = 'outfitbag'

-- Prop model for the outfit bag
Config.PropModel = 'prop_cs_heist_bag_02'

-- Distance to interact with the bag
Config.InteractDistance = 2.0

-- Target system to use: 'qb-target' or 'ox_target'
Config.TargetSystem = 'qb-target' -- Change to 'qb-target' if using qb-target

-- Command settings
Config.command = {
    enabled = true,
    command = 'outfitbag',
    shortCommand = 'ob'
}

-- QB-Target specific options (if using qb-target)
Config.QBTargetOptions = {
    {
        type = "client",
        event = "pf-outfitbag:pickupBag",
        icon = "fas fa-hand",
        label = "Pick Up"
    },
    {
        type = "client",
        event = "pf-outfitbag:openBag",
        icon = "fas fa-backpack",
        label = "Open"
    }
}

-- OX Target specific options (if using ox_target)
Config.OXTargetOptions = {
    {
        name = 'outfitbag_pickup',
        type = 'client',
        event = 'pf-outfitbag:pickupBag',
        icon = 'fas fa-hand',
        label = 'Pick Up',
        distance = 2.0,
        onSelect = function()
            TriggerEvent('pf-outfitbag:pickupBag')
        end
    },
    {
        name = 'outfitbag_open',
        type = 'client',
        event = 'pf-outfitbag:openBag',
        icon = 'fas fa-backpack',
        label = 'Open',
        distance = 2.0,
        onSelect = function()
            TriggerEvent('pf-outfitbag:openBag')
        end
    }
}

-- Clothing system to use: 'qb-clothing' or 'illenium_appearance'
Config.ClothingSystem = 'qb-clothing'

-- Default outfit prefix
Config.OutfitPrefix = 'Outfit'

-- UI Settings
Config.UIPosition = 'right' -- 'right' or 'left'
Config.UIWidth = '400px'

-- Notifications
Config.NotifyType = 'inform' -- 'inform', 'success', 'error'

-- Debug mode
Config.Debug = false

-- Animation settings
Config.bagAnimation = {
    enabled = true,
    dict = 'amb@medic@standing@tendtodead@idle_a',
    anim = 'idle_a',
}

Config.outfitChangeAnimation = {
    head = {
        duration = 2000,
        dict = 'mp_cp_stolen_tut',
        anim = 'b_think',
    },
    top = {
        duration = 4000,
        dict = 'mp_safehouseshower@male@',
        anim = 'male_shower_towel_dry_to_get_dressed',
    },
    bottom = {
        duration = 4000,
        dict = 'clothingshoes',
        anim = 'try_shoes_positive_d',
    },
}
