# PF Tablet UI - Cash Register System

A professional point-of-sale (POS) cash register interface for FiveM mechanic job shops, featuring dynamic itemization from pf-mechanicjob, category filtering, real-time tax calculations, and transaction processing.

## Features

### 🎨 Professional UI/UX
- **Dual-panel layout**: Left side for item browsing, right side for cart and totals
- **Responsive design**: Works seamlessly across different screen sizes
- **Theme support**: Light and dark theme compatibility
- **Real-time calculations**: Automatic subtotal, tax, and total updates
- **Smooth animations**: Professional transitions and interactions

### 💳 Cash Register Capabilities
- **Dynamic item loading**: Automatically imports items from `pf-mechanicjob` Config.RegisterItems
- **Category filtering**: Browse items by category (Diagnostics, Parts, Fluids, Heavy Repairs, Cosmetics, Performance, Documents)
- **Quantity management**: Quick add/remove buttons on items, editable quantities in cart
- **Tax calculation**: Configurable tax rates, real-time updates
- **Professional styling**: Merchant-grade POS appearance

### 🔧 Technical Features
- **Server integration**: Secure callback system for accessing pf-mechanicjob config
- **Transaction logging**: Server-side logging of all transactions
- **Job authorization**: Only authorized mechanic jobs can access
- **Error handling**: Graceful error states and user feedback
- **Demo mode**: Built-in demo functionality for testing/styling

## Architecture

### File Structure
```
pf-tabletuionly/
├── fxmanifest.lua          # Resource manifest with dependencies
├── client.lua              # Client-side NUI callbacks
├── server.lua              # Server-side callbacks and transaction handling
├── shared.lua              # Shared configuration (job definitions)
├── index.html              # HTML structure with tablet interface
├── style.css               # Professional styling with theme support
├── script.js               # JavaScript logic for cash register system
├── rte.js                  # Rich text editor (for notes app)
├── rte.css                 # Rich text editor styles
└── README.md              # This file
```

### Component Structure

#### HTML (`index.html`)
- Tablet UI container with status bar
- Home screen with app icons
- Cash register app with:
  - Item grid with category filtering
  - Shopping cart display
  - Totals section with tax calculation
  - Action buttons (Process, Clear)

#### Styles (`style.css`)
Professional POS styling including:
- Dark theme with accent colors (blue for primary, green for success)
- Light theme support via `data-theme="light"`
- Category buttons with active state
- Item cards with hover effects
- Cart items with quantity controls
- Totals section with clear visual hierarchy
- Custom scrollbars for modern appearance

#### JavaScript (`script.js`)
Core functionality:
- `initializeCashRegister()` - Fetches items from server
- `populateRegisterItems()` - Renders item grid with filtering
- `filterCategory()` - Handles category selection
- `adjustItemQuantity()` - Add/remove items from cart
- `updateCartDisplay()` - Updates cart UI in real-time
- `updateTotal()` - Calculates subtotal, tax, and total
- `processTransaction()` - Submits transaction to server
- `showDemoCashRegister()` - Demo mode for testing

#### Server Logic (`server.lua`)
- `getCashRegisterItems` callback - Retrieves items from pf-mechanicjob
- Transaction processing event - Handles business logic, logging, etc.
- Authorization checks - Validates mechanic job requirement

#### Configuration (`shared.lua`)
```lua
Config.MechanicJobs = {
    'mechanic', 'mechanic2', 'mechanic3', 'bennys', 'beeker'
}

Config.JobApps = {
    mechanic = {'work-orders', 'cash-register'},
    mechanic2 = {'work-orders', 'cash-register'},
    -- ... (work-orders and cash-register only, management removed)
}
```

## Integration with pf-mechanicjob

The cash register automatically pulls items from pf-mechanicjob's configuration:

```lua
-- From pf-mechanicjob/config.lua
Config.RegisterItems = {
    -- Diagnostics & Service
    mechanic_tools = { label = 'Mechanic Tools', basePrice = 500, category = 'Diagnostics & Service' },
    diagnosticstool = { label = 'Diagnostics Tool', basePrice = 1200, category = 'Diagnostics & Service' },
    
    -- Repair Parts
    carbattery = { label = 'Car Battery', basePrice = 700, category = 'Repair Parts' },
    sparkplugs = { label = 'Spark Plugs', basePrice = 120, category = 'Repair Parts' },
    
    -- Fluids
    engine_oil = { label = 'Engine Oil', basePrice = 100, category = 'Fluids' },
    cooland = { label = 'Coolant', basePrice = 70, category = 'Fluids' },
    
    -- ... and many more items organized by category
}
```

### Data Flow

1. **User opens tablet app** → Opens cash register app
2. **Client requests items** → `initializeCashRegister()` calls server
3. **Server callback** → `pf-tabletuionly:getCashRegisterItems` triggers
4. **Server accesses config** → Reads `pf-mechanicjob` Config.RegisterItems
5. **Items returned to client** → UI populates with available items
6. **User adds items** → Items added to shopping cart
7. **Real-time calculations** → Tax and totals update automatically
8. **User processes transaction** → Data sent to server
9. **Server logs transaction** → Transaction recorded, can trigger inventory/payment events

## Usage

### Opening the Cash Register

The cash register is automatically available to players with mechanic jobs:
1. Players with mechanic/bennys jobs see "Cash Register" app on tablet home screen
2. Click to open cash register interface
3. Browse items by category or view all items
4. Click +/- buttons to add/remove quantities
5. Review cart and totals on right panel
6. Click "Process" to complete transaction

### Testing in Development

**Demo mode**: Open browser console and run:
```javascript
showDemoCashRegister()
```

This loads demo items and switches to light theme for testing styling.

### Configuration

#### Tax Rate
Sourced from `pf-mechanicjob` Config.DefaultTax (default: 0.08 or 8%)

#### Mechanic Jobs
Configured in `shared.lua`:
```lua
Config.MechanicJobs = {'mechanic', 'mechanic2', 'mechanic3', 'bennys', 'beeker'}
```

#### Items
All items and categories pulled directly from `pf-mechanicjob/config.lua` Config.RegisterItems

## Removed Features

The **Management** app has been removed to simplify the interface. The tablet now shows only:
- Standard apps (Calendar, Photos, Camera, Clock, Notes, App Store, Wallet, Settings)
- Mechanic job apps: Work Orders and Cash Register

## Browser Console Commands

For testing and debugging:

```javascript
// Demo cash register
showDemoCashRegister()

// Demo work orders
showDemoWorkOrder()

// Clear cart
clearCart()

// View cart contents
console.log(registerCart)

// View all items
console.log(registerItems)
```

## Error Handling

### Common Issues

1. **Items not loading**: Ensure pf-mechanicjob is running and has Config.RegisterItems defined
2. **Transaction fails**: Check player has mechanic job permission
3. **UI not responsive**: Clear browser cache or open in developer mode
4. **Styling issues**: Verify CSS file is loading (check Network tab in dev tools)

### Debug Output

Server-side logs show:
```
[pf-tabletuionly] Cash Register Transaction by PlayerName (Citizen ID: XXXXX)
  Items: Mechanic Tools x2, Car Battery x1
  Subtotal: $1,220.00
  Tax: $97.60
  Total: $1,317.60
```

## Extensibility

The system is designed for easy extension:

### Adding Custom Logic
Modify `server.lua` processCashRegisterTransaction event:
```lua
-- Add inventory items
Player.Functions.AddItem(item.item, item.quantity)

-- Deduct from business account
TriggerEvent('qb-management:server:AddMoney', 'mechanic', data.total)

-- Send webhook/database log
-- ...
```

### Custom Styling
Modify `style.css`:
- Change colors: `.register-item`, `.btn-process`
- Adjust sizing: `.register-items`, `.register-right`
- Theme variables: Define in `body[data-theme="light"]` sections

### Additional Categories
No changes needed - pulls categories dynamically from `Config.RegisterItems`

## Performance

- **Lazy loading**: Items only populated when app is opened
- **Efficient filtering**: No DOM recreation, class-based filtering
- **Real-time calculations**: Optimized math functions
- **Smooth scrolling**: Custom scrollbar with GPU acceleration

## Browser Compatibility

- Tested on Chromium-based browsers (latest)
- Supports:
  - CSS Grid and Flexbox
  - ES6 JavaScript
  - Local Storage for settings
  - Fetch API for server communication

## Support

For issues or improvements:
1. Check error logs in both server and client console
2. Verify pf-mechanicjob is installed and running
3. Ensure player has correct job assigned
4. Check fxmanifest.lua dependencies are met

## Version History

### v1.0.0
- Initial release
- Full cash register functionality
- Category filtering
- Real-time tax calculation
- Transaction processing
- Management app removed
- Work orders and cash register only

## License

This resource is part of the PF Development framework.

---

**Last Updated**: February 22, 2026
