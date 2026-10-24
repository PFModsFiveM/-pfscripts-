# PF-Restaurants Setup Guide

## 1. Installation

### Step 1: Resource Files
1. Ensure `pf-restaurants` is in your `[pfscripts]` folder
2. All items have been added to `qb-core/shared/items.lua` ✅

### Step 2: Server Configuration
Add to your `server.cfg`:
```cfg
ensure pf-restaurants
```

### Step 3: Database (Optional - if using persistent storage)
The script can work without a database (data stored in memory), but for persistence, create these tables:

```sql
CREATE TABLE IF NOT EXISTS `restaurant_businesses` (
    `id` varchar(50) NOT NULL PRIMARY KEY,
    `name` varchar(100) NOT NULL,
    `owner` varchar(50) DEFAULT NULL,
    `balance` int(11) DEFAULT 0,
    `data` longtext DEFAULT NULL
);

CREATE TABLE IF NOT EXISTS `restaurant_employees` (
    `id` int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `business_id` varchar(50) NOT NULL,
    `citizenid` varchar(50) NOT NULL,
    `role` varchar(50) DEFAULT 'employee',
    `hired_at` timestamp DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `restaurant_orders` (
    `order_id` varchar(50) NOT NULL PRIMARY KEY,
    `business_id` varchar(50) NOT NULL,
    `items` longtext DEFAULT NULL,
    `total` decimal(10,2) DEFAULT 0,
    `status` varchar(20) DEFAULT 'placed',
    `created_at` timestamp DEFAULT CURRENT_TIMESTAMP
);
```

---

## 2. Restaurant Configuration

### Adding/Editing Restaurants

Edit `config/restaurants.lua`:

```lua
Config.Restaurants['your_restaurant_id'] = {
    name = "Your Restaurant Name",
    businessType = "burger_joint", -- or "pizzeria", "sandwich_shop"
    
    zones = {
        -- Kitchen area (employees only)
        kitchen = {
            coords = vector3(x, y, z),
            length = 10.0,
            width = 10.0,
            heading = 0.0,
            minZ = z - 2.0,
            maxZ = z + 3.0
        },
        
        -- Dining area (public)
        dining = {
            coords = vector3(x, y, z),
            length = 15.0,
            width = 15.0,
            heading = 0.0,
            minZ = z - 2.0,
            maxZ = z + 3.0
        },
        
        -- Storage room
        storage = {
            coords = vector3(x, y, z),
            length = 5.0,
            width = 5.0,
            heading = 0.0,
            minZ = z - 2.0,
            maxZ = z + 3.0
        }
    },
    
    storage = {
        dry = {coords = vector3(x, y, z), maxSlots = 50},
        fridge = {coords = vector3(x, y, z), maxSlots = 40},
        freezer = {coords = vector3(x, y, z), maxSlots = 40}
    },
    
    hygieneSpawns = {
        trash = {
            vector3(x, y, z),
            vector3(x, y, z)
        },
        roaches = {
            vector3(x, y, z)
        }
    }
}
```

---

## 3. Station Placement

Edit `config/stations.lua`:

```lua
Config.Stations['your_restaurant_id'] = {
    -- Cooking stations
    stations = {
        {
            id = 'grill_1',
            type = 'grill',
            coords = vector3(x, y, z),
            heading = 0.0,
            slots = {
                {id = 1, propOffset = vector3(0.0, 0.0, 1.0)},
                {id = 2, propOffset = vector3(0.5, 0.0, 1.0)}
            }
        },
        {
            id = 'fryer_1',
            type = 'fryer',
            coords = vector3(x, y, z),
            heading = 0.0,
            slots = {
                {id = 1, propOffset = vector3(0.0, 0.0, 1.0)}
            }
        },
        {
            id = 'prep_1',
            type = 'prep',
            coords = vector3(x, y, z),
            heading = 0.0,
            slots = {
                {id = 1, propOffset = vector3(0.0, 0.0, 1.0)}
            }
        },
        {
            id = 'assembly_1',
            type = 'assembly',
            coords = vector3(x, y, z),
            heading = 0.0,
            slots = {
                {id = 1, propOffset = vector3(0.0, 0.0, 1.0)}
            }
        },
        {
            id = 'drink_1',
            type = 'drink',
            coords = vector3(x, y, z),
            heading = 0.0,
            slots = {
                {id = 1, propOffset = vector3(0.0, 0.0, 1.0)}
            }
        }
    },
    
    -- POS Registers
    registers = {
        {
            id = 'register_1',
            coords = vector3(x, y, z),
            heading = 0.0
        }
    },
    
    -- DUI Screens (KDS & Menu)
    duiScreens = {
        {
            id = 'kds_1',
            type = 'kds',
            coords = vector3(x, y, z),
            heading = 0.0,
            width = 1.0,
            height = 0.75,
            renderDistance = 15.0
        },
        {
            id = 'menu_1',
            type = 'menu',
            coords = vector3(x, y, z),
            heading = 0.0,
            width = 1.5,
            height = 1.0,
            renderDistance = 20.0
        }
    }
}
```

---

## 4. Finding Coordinates

### In-Game Method
1. Stand where you want to place something
2. Use command: `/getcoords` or `/coords` (if you have a developer menu)
3. Copy the vector3 coordinates

### Alternative
Use a teleport/coords script or check your F8 console with:
```lua
/clientconsole
GetEntityCoords(PlayerPedId())
```

---

## 5. Testing Checklist

### Basic Setup
- [ ] Resource starts without errors
- [ ] No console errors on player join
- [ ] Items appear in QB inventory

### Restaurant Zones
- [ ] Kitchen zone restricts non-employees
- [ ] Dining area accessible to everyone
- [ ] Storage zone working

### Stations
- [ ] Can interact with grill (qb-target)
- [ ] Can interact with fryer
- [ ] Can interact with prep station
- [ ] Can interact with assembly counter
- [ ] Can interact with drink station

### POS System
- [ ] Register opens POS NUI
- [ ] Can add items to cart
- [ ] Can complete order
- [ ] Order appears on KDS screen

### KDS Display
- [ ] Orders appear on screen
- [ ] Timer counts up
- [ ] Orders expire after 2 minutes
- [ ] Color changes based on urgency (green → orange → red)

---

## 6. Quick Start - Burgershot Vespucci

The script comes with **Burgershot Vespucci** pre-configured:

**Location**: `-1199.0, -885.0, 14.0` (Vespucci Beach)

### Default Setup Included:
✅ 2 Grills (2 slots each)  
✅ 2 Fryers (1 slot each)  
✅ 2 Prep stations  
✅ 1 Assembly counter  
✅ 1 Drink station  
✅ 2 POS registers  
✅ 1 KDS screen  
✅ 1 Menu board  

**Just restart and start testing!**

---

## 7. Employee Management

### Hiring Players
```lua
-- Via pf-computer (recommended)
-- Or via server console:
TriggerEvent('pf-restaurants:server:addEmployee', businessId, citizenid, 'employee')
```

### Roles & Permissions
- `owner` - Full access
- `manager` - Hire/fire, order supplies, access analytics
- `cook` - Use stations, view orders
- `cashier` - Use POS, view orders
- `employee` - Basic station access

---

## 8. Troubleshooting

### "No target showing on stations"
- Ensure qb-target or ox_target is running
- Check station coordinates are correct
- Verify you're an employee

### "POS won't open"
- Check you're near a register
- Verify you're clocked in as employee
- Check F8 console for errors

### "KDS not showing orders"
- Verify DUI screen coordinates
- Check screen type is 'kds'
- Ensure orders are being created

### "Items not showing in inventory"
- Check qb-core/shared/items.lua has restaurant items
- Restart pfm-core after adding items
- Clear inventory cache

---

## 9. Next Steps

1. **Add Menu Items**: Use recipes from `config/recipes.lua`
2. **Set Prices**: Configure in `config/items.lua` 
3. **Customize Stations**: Add more stations as needed
4. **Add More Restaurants**: Clone config for Pizza This, etc.

---

## Support

Check logs in F8 console for errors. Most issues are:
- Missing coordinates
- Incorrect zone sizes
- Missing employee permissions
