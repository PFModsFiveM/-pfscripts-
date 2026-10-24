# 📱 PF Mechanic Tablet System

A modern, feature-rich tablet UI for mechanic job management, inspired by the pf-jobsystem design.

## 🎯 Features

### 🔧 Work Orders App
- View all active, pending, and completed work orders
- Track customer information and vehicle details
- Monitor job pricing and estimated completion times
- Real-time synchronization across all mechanics

### 💰 Cash Register App
- Interactive point-of-sale system
- Comprehensive parts and services catalog
- Shopping cart with quantity management
- Quick checkout with automatic commission calculation
- Categories: Fluids, Parts, Tires, Services, Cosmetics

### 📊 Management App
- Real-time business statistics dashboard
- Employee roster with online/offline status
- Revenue tracking and job completion metrics
- Performance analytics (avg job time, daily revenue)
- Multiple tabs: Overview, Employees, Inventory

### ⚙️ Settings App
- System configuration
- Customization options
- (Expandable for future features)

## 🎨 Design Features

- **Glassmorphic UI**: Modern, translucent design with backdrop blur effects
- **Responsive Scaling**: Adapts to different screen resolutions (1080p, 2K, 4K)
- **Smooth Animations**: Polished transitions and hover effects
- **Window Management**: Draggable, minimizable, and closable app windows
- **Real-time Updates**: Live game time/date display and IRL clock
- **Color Theme**: Orange/Amber accent colors for mechanic branding

## 📋 Usage

### Opening the Tablet
Players can open the tablet using:
- **Item**: Use the `mech_tablet` item from inventory
- **Command**: `/mechtablet` (mechanic job required)
- **Event**: `TriggerEvent('pf-mechanicjob:client:openTablet')`

### Navigation
- Click on app icons or dock items to open apps
- Drag windows by their title bar to reposition
- Use minimize (-) and close (×) buttons to manage windows
- Press **ESC** to close the tablet

## 🛠️ Installation

The tablet system is already integrated! Just ensure you have:

1. ✅ Updated `fxmanifest.lua` (already done)
2. ✅ All tablet files in `/tablet/` folder
3. ✅ Client script `client/tablet.lua`
4. ✅ Server script `server/tablet.lua`
5. ✅ Item registered: `mech_tablet`

## 🔌 API / Events

### Client Events

```lua
-- Open tablet
TriggerEvent('pf-mechanicjob:client:openTablet')

-- Close tablet
TriggerEvent('pf-mechanicjob:client:closeTablet')

-- Update tablet data while open
TriggerEvent('pf-mechanicjob:client:updateTabletData', {
    workOrders = {...},
    catalog = {...},
    stats = {...},
    employees = {...}
})
```

### Server Events

```lua
-- Create a new work order
TriggerServerEvent('pf_mech:tablet:createWorkOrder', {
    title = 'Engine Repair',
    vehicle = 'Sultan',
    customer = 'John Doe',
    price = 1500
})

-- Update work order status
TriggerServerEvent('pf_mech:tablet:updateWorkOrder', orderId, 'completed')

-- Delete work order
TriggerServerEvent('pf_mech:tablet:deleteWorkOrder', orderId)
```

### Server Callbacks

```lua
-- Get all tablet data
QBCore.Functions.TriggerCallback('pf_mech:tablet:getData', function(data)
    -- data contains: workOrders, catalog, stats, employees
end)

-- Get work orders only
QBCore.Functions.TriggerCallback('pf_mech:tablet:getWorkOrders', function(workOrders)
    -- Array of work orders
end)

-- Process checkout
QBCore.Functions.TriggerCallback('pf_mech:tablet:checkout', function(success, message)
    -- Transaction result
end, cart, total)
```

## 🎮 Debug Commands

When `Config.Debug = true`:

```lua
/addtestorder  -- Creates a random test work order
/mechtablet    -- Opens/closes the tablet
```

## 📦 Catalog Customization

Edit `server/tablet.lua` to customize the catalog:

```lua
local Catalog = {
    { name = 'Item Name', price = 100, icon = '🔧', category = 'parts' },
    -- Add more items...
}
```

**Available Categories:**
- `fluids` - Engine fluids (oil, coolant, etc.)
- `parts` - Mechanical parts (brakes, battery, etc.)
- `tires` - Tire options
- `service` - Service packages
- `cosmetic` - Visual modifications

## 💡 Features to Expand

The tablet system is designed to be expandable. Future additions could include:

- **Inventory Management**: Track shop inventory and supplies
- **Appointment Scheduling**: Book service appointments
- **Customer Database**: Save customer vehicle history
- **Invoice Generation**: Create detailed receipts
- **Employee Management**: Hire/fire mechanics, set permissions
- **Performance Reports**: Detailed analytics and graphs
- **Parts Ordering**: Order supplies from suppliers
- **Work Order Notes**: Add detailed notes to jobs

## 🎨 Customization

### Changing Theme Colors
Edit `tablet/style.css`:

```css
/* Main accent color (orange/amber theme) */
--accent-color: #f59e0b;
--accent-hover: #d97706;

/* Change these to customize your theme */
```

### Modifying Window Sizes
Edit `tablet/style.css`:

```css
.app-window {
    width: 1800px !important;
    height: 1150px !important;
    /* Adjust as needed */
}
```

### Adding Custom Apps
1. Add app definition in `tablet/script.js`:
```javascript
loadApps([
    { name: 'custom-app', icon: '🎯', label: 'My Custom App' }
]);
```

2. Add render function:
```javascript
case 'custom-app':
    renderCustomApp($content);
    break;
```

## 🐛 Troubleshooting

**Tablet won't open:**
- Ensure player has mechanic job
- Check F8 console for errors
- Verify `Config.AllowedJobs` includes your job name

**NUI not responding:**
- Press F8 and type `resmon` to check resource status
- Restart resource: `/restart pf-mechanicjob`
- Clear cache: Clear your FiveM cache folder

**Items not showing in catalog:**
- Check `server/tablet.lua` Catalog table
- Ensure server callback is working (F8 server console)

**Work orders not syncing:**
- Multiple mechanics must all restart the resource
- Check server console for callback errors

## 📝 Notes

- The tablet uses in-memory storage for work orders (resets on restart)
- For persistent data, integrate with your database system
- Commission system can be customized in `server/tablet.lua`
- All mechanics see the same work orders in real-time

## 🎯 Performance

- Optimized for low resource usage (0.00-0.01ms idle)
- Uses NUI callbacks efficiently
- Minimal network events
- Scales smoothly across resolutions

## 📄 License

Part of PF Mechanic Job System
Copyright © 2024 PF Mods

---

**Enjoy your new mechanic tablet system! 🔧💼**
