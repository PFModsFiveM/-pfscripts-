# PF-Restaurants

A comprehensive restaurant business simulation system for FiveM QBCore servers.

## Features

### Core Systems
- **Multi-Business Support**: Multiple restaurant locations (Burgershot, Pizza This, etc.)
- **Advanced Cooking Mechanics**: Doneness tracking (rare, medium-rare, medium, well-done), quality system, food poisoning risk
- **Equipment Management**: Degradation, maintenance, cleaning, oil changes, ice refills
- **Hygiene System**: Health ratings (A-F), trash accumulation, pest spawning, inspections
- **Fire Risk System**: Equipment-based fire probability, spread mechanics, extinguishing
- **Inventory System**: Lot-based tracking with FIFO/LIFO, expiry dates, spoilage mechanics
- **Order Management**: Full POS → KDS → completion workflow with status tracking

### Business Management
- **Employee System**: Hiring, firing, roles, permissions, clock in/out
- **Recipe Management**: Custom recipes, component assembly, nutrition calculation
- **Menu System**: Dynamic menus, pricing, 86 toggle, categories
- **Analytics Dashboard**: Sales data, employee performance, equipment health

### Player Features
- **Point of Sale (POS)**: Interactive NUI for order taking
- **Kitchen Display System (KDS)**: Real-time order queue with timers
- **Menu Boards**: DUI-based in-world menu displays
- **Station Interactions**: Grills, fryers, prep stations, assembly counters, drink stations
- **Visual Feedback**: 3D progress bars, cooking timers, doneness indicators, fire effects

### Integration
- **pf-computer**: Business manager dashboard exports
- **QB-Inventory**: Automatic item consumption and hunger/thirst effects
- **qb-target/ox_target**: Station and equipment interactions
- **Government System**: Placeholder functions for licensing, health inspections, fines

## Installation

1. Extract `pf-restaurants` to your `[pfscripts]` folder
2. Add all restaurant items to `qb-core/shared/items.lua` (already done if following setup)
3. Import SQL database structure (if database tables needed - see server/main.lua for structure)
4. Add to server.cfg: `ensure pf-restaurants`
5. Configure restaurants in `config/restaurants.lua`
6. Configure stations in `config/stations.lua`
7. Restart server

## Configuration

### Restaurant Setup
Edit `config/restaurants.lua` to add/modify restaurant locations:
```lua
Config.Restaurants['your_restaurant_id'] = {
    name = "Your Restaurant Name",
    businessType = "burger_joint", -- or "pizzeria", "sandwich_shop", etc.
    zones = { ... },
    storage = { ... },
    hygieneSpawns = { ... }
}
```

### Station Placement
Edit `config/stations.lua` to configure cooking stations:
```lua
Config.Stations['your_restaurant_id'] = {
    stations = { ... },
    registers = { ... },
    duiScreens = { ... }
}
```

### Items & Recipes
- **Items**: `config/items.lua` - 150+ restaurant items with nutrition values
- **Recipes**: `config/recipes.lua` - Component rules and final recipes

## Item Categories

### Raw Ingredients (70+ items)
- Meats: beef patties, bacon, chicken, sausage, pepperoni, ham
- Produce: lettuce, tomatoes, onions, mushrooms, peppers, herbs
- Dairy: cheeses, milk, cream, ice cream, butter
- Dry Goods: buns, dough, flour, sugar, spices, breadcrumbs
- Sauces: ketchup, mustard, mayo, BBQ, marinara, alfredo, pesto
- Beverages: soda syrups, coffee beans, juice concentrates

### Prepared Components (20+ items)
- Shredded lettuce, sliced tomatoes, chopped onions
- Cut fries, stretched pizza dough
- Cooked meats, fried items

### Final Products (60+ items)
- **Burgers**: Classic, cheese, double, triple, bacon, mushroom, veggie, chicken
- **Pizza**: Margherita, pepperoni, supreme, meat lovers, veggie, BBQ chicken, Hawaiian
- **Sides**: Fries (S/M/L), onion rings, chicken tenders/wings, mozzarella sticks
- **Desserts**: Brownies, cookies, pies, ice cream sundaes, milkshakes
- **Drinks**: Sodas (S/M/L), coffee varieties, juices, iced tea

### Supplies & Maintenance
- Cleaning supplies, fryer oil, ice bags, pest spray, trash bags, fire extinguishers

## Usage

### For Players
1. **Get Hired**: Apply at restaurant counter or via pf-computer
2. **Clock In**: Use POS register or manager terminal
3. **Taking Orders**: Use POS to create orders (payment processing included)
4. **Cooking**: 
   - Interact with stations (grill, fryer, prep, assembly)
   - Select recipes and start cooking
   - Watch doneness timers for quality
   - Complete items and place in holding
5. **Completing Orders**: Update order status in KDS as items are prepared

### For Managers
1. **Hiring**: Use pf-computer business manager or in-game menu
2. **Order Supplies**: Automatically delivered after delay
3. **Equipment Maintenance**: Clean equipment, change fryer oil, refill ice
4. **Hygiene**: Remove trash, mop floors, spray for pests
5. **Fire Safety**: Keep equipment maintained to reduce fire risk
6. **Health Inspections**: Government system (placeholder - requires government script)

## Dependencies

- **Required**:
  - qb-core
  - qb-target OR ox_target
  - qb-inventory (or compatible)
  - oxmysql

- **Recommended**:
  - pf-computer (for business management UI)
  - Government script with licensing/inspection support

## Exports

### Server Exports
```lua
-- Get restaurant data
exports['pf-restaurants']:GetRestaurantData(businessId)

-- Get menu
exports['pf-restaurants']:GetMenu(businessId)

-- Get recipes
exports['pf-restaurants']:GetRecipes(businessId)

-- Get analytics
exports['pf-restaurants']:GetAnalytics(businessId, timeframe)

-- Check employee status
local isEmployee = exports['pf-restaurants']:IsEmployeeOfBusiness(citizenid, businessId)
```

### Client Exports
```lua
-- Start station action
exports['pf-restaurants']:StartStationAction(stationId, recipeId, slot)

-- Complete station action
exports['pf-restaurants']:CompleteStationAction(sessionId)
```

## Database Structure

Tables created automatically on first run (if using MySQL persistent storage):
- `restaurant_businesses` - Business records
- `restaurant_employees` - Employee roster
- `restaurant_recipes` - Custom recipes
- `restaurant_menu` - Menu items
- `restaurant_orders` - Order history
- `restaurant_inventory` - Lot-based inventory
- `restaurant_equipment` - Equipment status
- `restaurant_analytics` - Sales/performance data

## Credits

- **Author**: PF Scripts
- **Framework**: QBCore
- **Version**: 1.0.0

## License

All rights reserved.

## Support

For issues, feature requests, or questions, please contact the development team.

---

**Note**: This script includes placeholder functions for government integration (licensing, inspections, fines). Full functionality requires a compatible government/business licensing script.
