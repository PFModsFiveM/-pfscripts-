# PF Garage UI Only

A modern, clean, and feature-rich garage UI for FiveM in portrait format with full integration for pf-mechanicjob and pf-policemdt.

## 🎯 Quick Links

- **[📦 Installation Guide](INSTALL.md)** - Step-by-step setup instructions
- **[🔗 Integration Guide](INTEGRATION.md)** - Full API documentation for pf-mechanicjob and pf-policemdt
- **[⚡ Quick Reference](QUICK_REFERENCE.md)** - Fast lookup for exports and events
- **[📝 Examples](examples/README.md)** - Code examples and integration samples
- **[🗄️ Database Setup](sql/garage.sql)** - SQL schema with integration support

---

### 🚗 Real Persistent Vehicle State
- **Fuel & Engine Health** - Real-time tracking
- **Dirt Level Persistence** - Vehicles stay dirty until washed
- **Body Panel Damage Zones** - Detailed damage tracking per panel
- **Broken Lights & Windows** - Individual component tracking
- **Tire Wear & Blowout History** - Track tire condition
- **Last Parked Location & Heading** - Remember where you parked

### 📋 Salvage / Title Status System
Vehicle title states:
- **Clean Title** - No major incidents
- **Salvage** - Damaged beyond economical repair
- **Rebuilt** - Salvaged and repaired
- **Scrapped** - VIN blacklisted, cannot be used

### 🔍 Search & Filters
- **Real-time Search** - Search by name, plate, category, or location
- **Filter by:**
  - All Vehicles
  - Favorites
  - Job Vehicles
  - Recently Used
  - Damaged Only

### 📖 Vehicle Timeline / History Page
Comprehensive vehicle history showing:
- Purchase date & original owner
- Previous owners
- Repair records
- Crimes linked to the vehicle
- Impound records
- Insurance claims
- Mileage graph (future enhancement)

### 📁 Drag-and-Drop Garage Organization
Players can:
- **Reorder Vehicles** - Drag to rearrange
- **Create Custom Folders:**
  - "Daily Drivers"
  - "Race Cars"
  - "Illegal Vehicles"
  - Custom names with icons
- **Pin Favorites** - Always appear at top

### 💳 Live Vehicle Status Cards
Each vehicle card displays:
- **Fuel %** - Real-time fuel level
- **Engine %** - Engine health
- **Cleanliness** - Dirt level
- **Insurance Tier** - None/Basic/Standard/Premium/Government
- **Police Heat** - Low/Medium/High
- **Stored Location** - Current garage
- All synced in real-time

## UI Design

### Portrait Format
- Positioned on the left side of screen
- Takes ~25% of screen width (420px)
- Clean, modern glassmorphism design
- Smooth animations and transitions
- Easy to read with high contrast

### Color Scheme
- Dark theme with blue/purple gradient accents
- Color-coded status indicators
- Clear visual hierarchy

### Components
- Responsive vehicle cards with live stats
- Detailed modal with tabs (Overview, Condition, History)
- Folder management system
- Drag-and-drop interface
- Search and filter system

## Database Schema

The UI is ready to work with a comprehensive database schema including:

- `player_vehicles` - Main vehicle data with all persistent states
- `vehicle_history` - Timeline events and history
- `vehicle_folders` - Player-created organization folders
- `vehicle_damage_zones` - Granular damage tracking
- `vehicle_impounds` - Impound records
- `vehicle_insurance_claims` - Insurance claim tracking

See `sql/garage.sql` for the complete schema.

## Installation

1. Place `pf-garageuionly` in your resources folder
2. Add `ensure pf-garageuionly` to your server.cfg
3. Import the SQL schema from `sql/garage.sql`
   - If you have existing `player_vehicles` table, only the ALTER statements will run
   - This is safe to run on existing databases
4. **(Optional)** If using pf-mechanicjob, ensure it's started before pf-garageuionly
5. **(Optional)** If using pf-policemdt-DEV, ensure it's started before pf-garageuionly
6. Restart your server

```cfg
# server.cfg
ensure oxmysql
ensure pfm-core
ensure pf-mechanicjob    # Optional but recommended
ensure pf-policemdt-DEV  # Optional but recommended
ensure pf-garageuionly
```

## 🔗 Integrations

### pf-mechanicjob Integration

When pf-mechanicjob is running, the garage UI automatically displays:
- ✅ Real-time part damage (oil, brakes, suspension, etc.)
- ✅ Mileage tracking
- ✅ Engine/body/tank health
- ✅ Dirt level and cleanliness
- ✅ NOS upgrades and levels
- ✅ Repair history from completed work orders
- ✅ Service book entries

**No additional setup required** - just ensure both resources are running.

### pf-policemdt Integration

When pf-policemdt-DEV is running, the garage UI automatically displays:
- ✅ Vehicle involvement in police incidents
- ✅ Police heat level (calculated from incident count)
- ✅ Incident details in vehicle timeline
- ✅ Crime history linked to vehicle

**No additional setup required** - vehicle plates are automatically linked from MDT incidents.

### Integration Code Examples

See **[INTEGRATION.md](INTEGRATION.md)** for:
- Complete API documentation
- Server/client exports
- Event documentation  
- Code examples for custom integrations
- Troubleshooting guide

## Usage

### Opening the UI

#### Option 1: Command (for testing)
```lua
RegisterCommand('garage', function()
    exports['pf-garageuionly']:OpenGarageUI()
end)
```

#### Option 2: From Your Garage Script
```lua
-- Replace your existing garage UI with this
TriggerEvent('pf-garage:client:openUI', 'Legion Square Parking')
```

#### Option 3: Export
```lua
exports['pf-garageuionly']:OpenGarageUI()
```

### Spawning Vehicles

The UI sends a callback when player wants to spawn a vehicle. Integrate with your existing garage system:

```lua
-- client/integration.lua (already included)
RegisterNUICallback('spawnVehicle', function(data, cb)
    -- This calls your existing garage spawn system
    TriggerEvent('garage:client:spawnVehicle', data)
    cb({ success = true })
end)
```

### Adding Custom Timeline Events

Any resource can add events to the vehicle timeline:

```lua
-- Server-side from any resource
exports['pf-garageuionly']:AddVehicleHistoryEvent('ABC123', {
    citizenid = 'ABC12345',
    author = 'System',
    description = 'Custom event description'
})
```

## Usage (Legacy - UI Only Mode)

This is a **UI with full integration** resource. For pureUI-only mode without backend:

### Opening the UI (UI Only)
```javascript
// From client-side script
SendNUIMessage({
    action: 'openGarage',
    vehicles: vehicleData // Your vehicle data array
});
SetNuiFocus(true, true);
```

### Closing the UI
The UI will send a callback when closed:
```javascript
// In your client script
RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)
```

### Spawning Vehicles
```javascript
// Handle spawn callback
RegisterNUICallback('spawnVehicle', function(data, cb)
    local vehicleId = data.vehicleId
    -- Your spawn logic here
    cb('ok')
end)
```

## Data Format

The UI expects vehicle data in this format:

```javascript
{
    id: 1,
    name: 'Grotti Turismo R',
    plate: 'ABC 123',
    model: 'turismor',
    category: 'Super',
    titleStatus: 'clean', // 'clean', 'salvage', 'rebuilt', 'scrapped'
    location: 'Legion Square Parking',
    heading: 90.5,
    mileage: 12345,
    insurance: 'Premium',
    policeHeat: 'low', // 'none', 'low', 'medium', 'high'
    fuel: 75,
    engine: 90,
    body: 85,
    cleanliness: 50,
    favorite: true,
    isJobVehicle: false,
    lastUsed: '2026-02-17T14:30:00',
    purchaseDate: '2025-06-15',
    damage: {
        panels: [
            { name: 'Front Bumper', severity: 'minor' },
            { name: 'Hood', severity: 'severe' }
        ],
        lights: ['Headlight (R)'],
        windows: ['Window (Driver)'],
        tires: ['good', 'good', 'worn', 'blown']
    },
    history: [
        {
            type: 'purchase',
            date: '2025-06-15',
            title: 'Vehicle Purchased',
            description: 'Bought from Luxury Autos for $550,000'
        }
    ]
}
```

## Customization

### Colors
Edit CSS variables in `html/style.css`:
```css
:root {
    --primary-color: #3b82f6;
    --secondary-color: #8b5cf6;
    /* ... */
}
```

### Sample Data
The UI includes sample data for testing. Remove or modify in `html/script.js`:
```javascript
const sampleVehicles = [
    // Your sample vehicles
];
```

## Features Roadmap

- [ ] Mileage graph visualization
- [ ] Vehicle comparison view
- [ ] Export vehicle history as PDF
- [ ] Sharing vehicle stats
- [ ] Vehicle marketplace integration
- [ ] Garage capacity management
- [ ] Parking spot visualization on map

## Credits

- **Author:** ProjectFusion
- **Version:** 1.0.0
- **License:** See LICENSE file

## Support

For issues, suggestions, or contributions, please contact ProjectFusion.

---

**Note:** This is a UI-only resource. Server-side integration and game logic must be implemented separately.
