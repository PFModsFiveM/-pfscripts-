# Installation & Setup Guide

Complete step-by-step installation guide for pf-garageuionly with pf-mechanicjob and pf-policemdt integration.

---

## 📋 Prerequisites

Before installing, ensure you have:

- ✅ **QBCore** or **ESX** framework
- ✅ **oxmysql** resource
- ✅ **player_vehicles** table in database (from qb-garages or similar)
- ⭐ **pf-mechanicjob** (optional but recommended)
- ⭐ **pf-policemdt-DEV** (optional but recommended)

---

## 🚀 Installation Steps

### Step 1: Download & Place Resource

1. Download `pf-garageuionly` folder
2. Place in your FiveM resources folder: `resources/[pfscripts]/pf-garageuionly`

Your structure should look like:
```
resources/
└── [pfscripts]/
    ├── pf-mechanicjob/       (optional)
    ├── pf-policemdt-DEV/     (optional)
    └── pf-garageuionly/      ← New folder
        ├── client/
        ├── server/
        ├── html/
        ├── sql/
        ├── examples/
        ├── fxmanifest.lua
        └── README.md
```

### Step 2: Database Setup

#### Option A: Extend Existing Tables (Recommended)

If you already have `player_vehicles` table:

```sql
-- 1. Open your database management tool (HeidiSQL, phpMyAdmin, etc.)
-- 2. Select your FiveM database
-- 3. Run this SQL:

-- Add garage UI columns to existing player_vehicles
ALTER TABLE `player_vehicles`
    ADD COLUMN IF NOT EXISTS `title_status` ENUM('clean', 'salvage', 'rebuilt', 'scrapped') DEFAULT 'clean',
    ADD COLUMN IF NOT EXISTS `insurance_tier` ENUM('none', 'basic', 'standard', 'premium', 'government') DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS `police_heat` ENUM('none', 'low', 'medium', 'high') DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS `is_favorite` BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS `folder_id` INT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `custom_order` INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS `is_job_vehicle` BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS `job_name` VARCHAR(50) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `purchase_date` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS `last_used` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ADD INDEX IF NOT EXISTS `idx_favorite` (`is_favorite`),
    ADD INDEX IF NOT EXISTS `idx_folder` (`folder_id`),
    ADD INDEX IF NOT EXISTS `idx_last_used` (`last_used`);

-- Create folder management table
CREATE TABLE IF NOT EXISTS `vehicle_folders` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner` VARCHAR(50) NOT NULL,
    `folder_name` VARCHAR(50) NOT NULL,
    `folder_icon` VARCHAR(50) DEFAULT 'folder',
    `folder_order` INT DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Option B: Import Full Schema

If you want all optional features (history, impounds, insurance):

```sql
-- Import the complete schema
-- File: resources/[pfscripts]/pf-garageuionly/sql/garage.sql
```

**Note**: The SQL uses `IF NOT EXISTS` and `ADD COLUMN IF NOT EXISTS`, so it's safe to run multiple times.

### Step 3: Configure server.cfg

Add to your `server.cfg` in the correct order:

```cfg
# Core resources first
ensure oxmysql
ensure pfm-core

# Job systems
ensure pf-mechanicjob    # Optional - for damage tracking
ensure pf-policemdt-DEV  # Optional - for incident tracking

# Garage UI (load AFTER integrations)
ensure pf-garageuionly
```

**Important**: Load pf-garageuionly **after** pf-mechanicjob and pf-policemdt-DEV so it can detect them.

### Step 4: Restart Server

```bash
# In server console
restart pf-garageuionly

# Or full restart
stop
start
```

### Step 5: Verify Installation

Test with these commands:

```lua
-- In F8 console (client)
/lua exports['pf-garageuionly']:OpenGarageUI()

-- Should open the garage UI
```

If UI opens, installation successful! ✅

---

## 🔧 Integration Setup

### pf-mechanicjob Integration

If you have pf-mechanicjob installed:

1. ✅ **No code changes needed** - integration is automatic
2. ✅ Ensure `vehicle_diagnostics` table exists (from pf-mechanicjob SQL)
3. ✅ Drive a vehicle to populate diagnostic data
4. ✅ Open garage - you'll see real damage data

**What you get:**
- Real-time part damage display (oil, brakes, etc.)
- Mileage tracking
- Repair history in timeline
- NOS upgrade tracking
- Service book integration

**Optional**: Add timeline events when repairs are done (see [INTEGRATION.md](INTEGRATION.md#example-1-pf-mechanicjob---add-repair-to-timeline))

### pf-policemdt Integration

If you have pf-policemdt-DEV installed:

1. ✅ **No code changes needed** - integration is automatic
2. ✅ Create MDT incidents with vehicle plates in `involvedVehicleIds`
3. ✅ Open garage - incidents appear in vehicle timeline

**What you get:**
- Police incidents in vehicle history
- Automatic police heat calculation
- Incident details with links

**Note**: Make sure MDT incidents save vehicle plates in the `involvedVehicleIds` column as JSON array.

---

## 🎮 Usage

### Opening the Garage UI

#### Method 1: Command (for testing)
```lua
-- Add to any client script or F8 console
/lua exports['pf-garageuionly']:OpenGarageUI()
```

#### Method 2: Replace Existing Garage
```lua
-- In your garage script (client.lua)
RegisterCommand('garage', function()
    exports['pf-garageuionly']:OpenGarageUI()
end)
```

#### Method 3: Zone-Based (recommended)
```lua
-- See: examples/integration_example.lua
-- Opens garage when player presses E near garage marker
```

### Spawning Vehicles

Handle the spawn callback in your garage script:

```lua
-- client/integration.lua (already included) sends this event
RegisterNetEvent('garage:client:spawnVehicle', function(vehicleData)
    -- Your existing vehicle spawn logic
    QBCore.Functions.SpawnVehicle(vehicleData.vehicle, function(veh)
        -- Apply properties, fuel, damage, etc.
    end)
end)
```

---

## 🧪 Testing

### Test 1: UI Opens
```
1. Join server
2. Press F8
3. Type: /lua exports['pf-garageuionly']:OpenGarageUI()
4. UI should appear on left side of screen
```

### Test 2: Vehicle Data
```
1. Ensure you own at least one vehicle
2. Open garage UI
3. Should see your vehicle(s) listed
4. Click vehicle card - detailed modal should open
```

### Test 3: Mechanic Integration
```
1. Ensure pf-mechanicjob is running
2. Drive a vehicle (to damage it slightly)
3. Open garage UI
4. Click vehicle - should see damage percentages
```

### Test 4: MDT Integration
```
1. Ensure pf-policemdt-DEV is running
2. Create police incident with your vehicle plate
3. Open garage UI
4. Click vehicle → History tab
5. Should see incident in timeline
```

---

## 🛠️ Customization

### Change UI Colors

Edit `html/style.css`:

```css
:root {
    --primary-color: #3b82f6;     /* Change to your color */
    --secondary-color: #8b5cf6;   /* Change to your color */
    /* ... */
}
```

### Change UI Position

Edit `html/style.css`:

```css
.garage-container {
    left: 20px;    /* Distance from left edge */
    top: 50%;      /* Vertical position */
    width: 420px;  /* Width of UI */
}
```

### Disable Sample Data

Edit `html/script.js`:

```javascript
// Remove or comment out sample vehicles
const sampleVehicles = [];  // Empty array = no samples
```

---

## 📊 Database Tables Overview

After installation, you should have these tables:

| Table | Source | Purpose |
|-------|--------|---------|
| `player_vehicles` | qb-garages/ESX | Main vehicle data (extended) |
| `vehicle_folders` | pf-garageuionly | Player organization |
| `vehicle_diagnostics` | pf-mechanicjob | Part damage & health |
| `pf_work_orders` | pf-mechanicjob | Repair jobs |
| `pf_job_history` | pf-mechanicjob | Completed repairs |
| `pf_service_log` | pf-mechanicjob | Service book |
| `pf_mdt_incidents` | pf-policemdt-DEV | Police incidents |

**Check if tables exist:**

```sql
SHOW TABLES LIKE '%vehicle%';
SHOW TABLES LIKE 'pf_%';
```

---

## 🐛 Troubleshooting

### UI Won't Open

**Problem**: Export doesn't work  
**Solution**:
```lua
-- Check resource state in F8
/lua print(GetResourceState('pf-garageuionly'))
-- Should print: "started"

-- If not started, check server console for errors
```

### No Vehicles Showing

**Problem**: UI opens but shows "No vehicles found"  
**Solution**:
```sql
-- Check if you have vehicles in database
SELECT * FROM player_vehicles WHERE citizenid = 'YOUR_CITIZENID';

-- If empty, spawn a vehicle first
```

### No Damage Data

**Problem**: Vehicles show but no part damage  
**Solution**:
```sql
-- Check if pf-mechanicjob tables exist
SELECT * FROM vehicle_diagnostics LIMIT 1;

-- If empty, drive a vehicle to populate data
```

### MDT Incidents Not Showing

**Problem**: Police incidents don't appear in timeline  
**Solution**:
```sql
-- Check if incidents have vehicle plates
SELECT incidentId, involvedVehicleIds 
FROM pf_mdt_incidents 
WHERE involvedVehicleIds LIKE '%YOUR_PLATE%';

-- Make sure plates are in the JSON array
```

### JavaScript Errors

**Problem**: Console shows NUI errors  
**Solution**:
1. Clear FiveM cache: `%localappdata%\FiveM\FiveM Application Data\cache`
2. Restart FiveM
3. Check if all files exist in `html/` folder

---

## 📚 Next Steps

After installation:

1. **Read Integration Guide**: [INTEGRATION.md](INTEGRATION.md)
2. **Review Examples**: [examples/README.md](examples/README.md)
3. **Quick Reference**: [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
4. **Customize UI**: Edit colors, logos, styling
5. **Add Events**: Add custom timeline events from your scripts

---

## 📞 Support

If you encounter issues:

1. ✅ Check this installation guide
2. ✅ Read [INTEGRATION.md](INTEGRATION.md) troubleshooting section
3. ✅ Enable debug mode: `server/integration.lua` → `Config.Debug = true`
4. ✅ Check server console for errors
5. ✅ Verify all SQL tables exist

---

## ✅ Installation Checklist

- [ ] Resource placed in `[pfscripts]` folder
- [ ] SQL schema imported
- [ ] Added to server.cfg **after** integrations
- [ ] Server restarted
- [ ] UI opens successfully
- [ ] Vehicles appear in UI
- [ ] (Optional) pf-mechanicjob integration working
- [ ] (Optional) pf-policemdt integration working
- [ ] Custom spawn handler configured
- [ ] Tested all features

---

**Version**: 1.0.0  
**Author**: ProjectFusion  
**Last Updated**: February 2026

Congratulations! Your modern garage UI is now installed and integrated. 🎉
