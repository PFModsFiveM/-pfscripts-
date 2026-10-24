# PF Garage UI - Integration Guide

Complete integration documentation for connecting pf-garageuionly with pf-mechanicjob and pf-policemdt.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Database Setup](#database-setup)
3. [pf-mechanicjob Integration](#pf-mechanicjob-integration)
4. [pf-policemdt Integration](#pf-policemdt-integration)
5. [Server Exports](#server-exports)
6. [Client Exports](#client-exports)
7. [Events](#events)
8. [Code Examples](#code-examples)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The pf-garageuionly resource integrates seamlessly with:
- **pf-mechanicjob**: Vehicle damage, repairs, upgrades, service history
- **pf-policemdt**: Vehicle incidents, police heat tracking

All integrations are automatic - if the resources are present, data flows between them.

---

## Database Setup

### Option 1: Extend Existing Tables (Recommended)

If you already have `player_vehicles` table from qb-core/ESX:

```sql
-- Run this to add garage UI columns to your existing table
ALTER TABLE `player_vehicles`
    ADD COLUMN IF NOT EXISTS `title_status` ENUM('clean', 'salvage', 'rebuilt', 'scrapped') DEFAULT 'clean',
    ADD COLUMN IF NOT EXISTS `insurance_tier` ENUM('none', 'basic', 'standard', 'premium', 'government') DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS `police_heat` ENUM('none', 'low', 'medium', 'high') DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS `is_favorite` BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS `folder_id` INT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `is_job_vehicle` BOOLEAN DEFAULT FALSE;

-- Create folder management table
CREATE TABLE IF NOT EXISTS `vehicle_folders` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner` VARCHAR(50) NOT NULL,
    `folder_name` VARCHAR(50) NOT NULL,
    `folder_icon` VARCHAR(50) DEFAULT 'folder',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Option 2: Full Schema

Import the complete schema from `sql/garage.sql` if you want all optional tables (history, impounds, insurance).

---

## pf-mechanicjob Integration

### What Data is Shared

The garage UI automatically displays:

| Data Type | Source Table | Description |
|-----------|-------------|-------------|
| Part Damage | `vehicle_diagnostics` | Oil, brakes, suspension, etc. |
| Mileage | `vehicle_diagnostics.mileage` | Total kilometers driven |
| Engine/Body Health | `vehicle_diagnostics` | Health percentages |
| Dirt Level | `vehicle_diagnostics.dirtLevel` | Cleanliness (0-100) |
| NOS Upgrades | `player_vehicles.hasnitrom` | NOS installed status |
| Repair History | `pf_job_history` | Completed repair jobs |
| Service Log | `pf_service_log` | Service book entries |

### Automatic Sync

Vehicle state syncs automatically:
- When player enters/exits vehicle
- Every 30 seconds while driving
- When vehicle is stored in garage

### Code Integration

#### Add Repair to Vehicle Timeline

```lua
-- Server-side (from pf-mechanicjob)
exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
    citizenid = citizenid,
    author = 'John Mechanic',
    description = 'Replaced brake pads - Cost: $250'
})
```

#### Update Vehicle Damage from Mechanic Script

```lua
-- Server-side
exports['pf-garageuionly']:UpdateVehicleDamage(plate, {
    engineHealth = 950,
    bodyHealth = 850,
    tankHealth = 1000,
    dirtLevel = 25
})
```

#### Notify Garage UI of Repair

```lua
-- Server-side (after repair complete)
local Player = QBCore.Functions.GetPlayer(src)
TriggerClientEvent('pf-garage:client:updateVehicle', src, plate, {
    partDamage = {
        brakes = 0, -- Fixed
        oil = 15    -- Still needs attention
    }
})
```

### pf-mechanicjob Events to Listen For

```lua
-- Client-side in pf-mechanicjob
RegisterNetEvent('pf-mechanicjob:client:repairComplete', function(plate, repairs)
    -- Notify garage UI
    TriggerEvent('pf-mechanicjob:client:vehicleRepaired', plate, 'brakes', 0)
end)

-- Server-side in pf-mechanicjob
RegisterNetEvent('pf-mechanicjob:server:applyUpgrade', function(plate, upgradeType)
    -- After applying NOS
    if upgradeType == 'nos' then
        -- Garage UI will automatically pick this up from player_vehicles
        MySQL.update.await([[
            UPDATE player_vehicles 
            SET hasnitrom = 1, noslevel = 100 
            WHERE plate = ?
        ]], { plate })
    end
end)
```

---

## pf-policemdt Integration

### What Data is Shared

| Data Type | Source Table | Description |
|-----------|-------------|-------------|
| Incidents | `pf_mdt_incidents` | Criminal incidents involving vehicle |
| Police Heat | Calculated | Based on incident count |

### How It Works

1. MDT creates incidents with `involvedVehicleIds` containing plate numbers
2. Garage UI queries MDT database for incidents matching vehicle plate
3. Incidents appear in vehicle timeline/history
4. Police heat calculated:
   - **None**: 0 incidents
   - **Low**: 1-2 incidents
   - **Medium**: 3-5 incidents
   - **High**: 6+ incidents

### Code Integration

#### Link Vehicle to MDT Incident

```lua
-- Server-side in pf-policemdt-DEV
-- When creating an incident
MySQL.insert.await([[
    INSERT INTO pf_mdt_incidents 
    (incidentId, title, involvedVehicles, involvedVehicleIds, ...) 
    VALUES (?, ?, ?, ?, ...)
]], {
    incidentId,
    'High Speed Chase',
    json.encode({'ABC123 - Grotti Turismo R'}),
    json.encode({'ABC123'}), -- This links to garage UI
    -- ... other fields
})
```

#### Query Vehicle Incidents from Garage

```lua
-- Server-side export
local incidents = exports['pf-garageuionly']:GetVehicleData('ABC123')
if incidents and incidents.history then
    for _, event in ipairs(incidents.history) do
        if event.type == 'crime' then
            print('Incident:', event.title, event.description)
        end
    end
end
```

---

## Server Exports

All server-side exports available from pf-garageuionly:

### GetVehicleData(plate)

Get comprehensive data for a single vehicle.

```lua
local vehicleData = exports['pf-garageuionly']:GetVehicleData('ABC123')

-- Returns:
{
    id = 1,
    plate = 'ABC123',
    owner = 'ABC12345',
    vehicle = 'turismor',
    mileage = 12345,
    fuel = 75,
    enginePercent = 90,
    bodyPercent = 85,
    policeHeat = 'low',
    hasNOS = true,
    nosLevel = 100,
    damage = {
        parts = { oil = 15, brakes = 0, ... },
        panels = {...},
        tires = {...}
    },
    history = {
        { type = 'purchase', date = '...', title = '...', description = '...' },
        { type = 'repair', date = '...', ... },
        { type = 'crime', date = '...', incidentId = '...' }
    }
}
```

### GetPlayerVehicles(citizenid)

Get all vehicles for a player.

```lua
local vehicles = exports['pf-garageuionly']:GetPlayerVehicles('ABC12345')

-- Returns array of vehicle data objects
for _, vehicle in ipairs(vehicles) do
    print(vehicle.plate, vehicle.mileage, vehicle.policeHeat)
end
```

### UpdateVehicleDamage(plate, damageData)

Update vehicle damage externally.

```lua
local success = exports['pf-garageuionly']:UpdateVehicleDamage('ABC123', {
    engineHealth = 950,
    bodyHealth = 850,
    tankHealth = 1000,
    dirtLevel = 25
})
```

### AddVehicleHistoryEvent(plate, eventData)

Add custom event to vehicle timeline.

```lua
exports['pf-garageuionly']:AddVehicleHistoryEvent('ABC123', {
    citizenid = 'ABC12345',
    author = 'John Mechanic',
    description = 'Full service completed - $500'
})
```

---

## Client Exports

All client-side exports available from pf-garageuionly:

### OpenGarageUI()

Open the garage UI for the player.

```lua
exports['pf-garageuionly']:OpenGarageUI()
```

### GetVehicleData(plate)

Get vehicle data (client-side callback).

```lua
local data = exports['pf-garageuionly']:GetVehicleData('ABC123')
```

### GetAllPlayerVehicles()

Get all player vehicles (client-side).

```lua
local vehicles = exports['pf-garageuionly']:GetAllPlayerVehicles()
```

---

## Events

### Server Events

#### pf-garage:syncVehicleState

Sent from client when vehicle state changes.

```lua
-- Client sends:
TriggerServerEvent('pf-garage:syncVehicleState', {
    plate = 'ABC123',
    mileage = 12345,
    fuel = 75,
    engineHealth = 950,
    partDamage = {...}
})
```

#### pf-garage:toggleFavorite

Toggle favorite status for a vehicle.

```lua
-- Client sends:
TriggerServerEvent('pf-garage:toggleFavorite', 'ABC123')
```

#### pf-garage:createFolder

Create a new vehicle folder.

```lua
-- Client sends:
TriggerServerEvent('pf-garage:createFolder', 'My Race Cars', 'flag-checkered')
```

### Client Events

#### pf-garage:client:openUI

Open the garage UI.

```lua
TriggerClientEvent('pf-garage:client:openUI', src, 'Legion Square Parking')
```

#### pf-garage:client:updateVehicle

Update specific vehicle in UI.

```lua
TriggerClientEvent('pf-garage:client:updateVehicle', src, 'ABC123', {
    fuel = 50,
    enginePercent = 85
})
```

---

## Code Examples

### Example 1: pf-mechanicjob - Add Repair to Timeline

Add this to your pf-mechanicjob repair completion:

```lua
-- server/repair.lua (pf-mechanicjob)
RegisterNetEvent('pf-mechanicjob:server:completeRepair', function(plate, repairType, cost)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    -- Your existing repair logic...
    
    -- Add to garage timeline
    if GetResourceState('pf-garageuionly') == 'started' then
        exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
            citizenid = Player.PlayerData.citizenid,
            author = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
            description = string.format('Repair: %s - Cost: $%d', repairType, cost)
        })
    end
end)
```

### Example 2: pf-mechanicjob - Live Damage Updates

Sync damage in real-time:

```lua
-- server/damage.lua (pf-mechanicjob)
RegisterNetEvent('pf_mech:server:updatePartDamage', function(vehNet, partName, damage)
    -- Your existing damage logic...
    
    local veh = NetworkGetEntityFromNetworkId(vehNet)
    if not veh then return end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    
    -- Update garage UI
    if GetResourceState('pf-garageuionly') == 'started' then
        exports['pf-garageuionly']:UpdateVehicleDamage(plate, {
            engineHealth = GetVehicleEngineHealth(veh),
            bodyHealth = GetVehicleBodyHealth(veh)
        })
    end
end)
```

### Example 3: pf-policemdt - Link Vehicle to Incident

When creating MDT incident:

```lua
-- server/main.lua (pf-policemdt-DEV)
RegisterNetEvent('pf-mdt:server:createIncident', function(data)
    -- Your existing logic...
    
    -- Ensure vehicle plates are in involvedVehicleIds
    local vehiclePlates = {}
    for _, vehicle in ipairs(data.involvedVehicles or {}) do
        -- Extract plate from vehicle data
        local plate = vehicle.plate or ExtractPlate(vehicle.name)
        table.insert(vehiclePlates, plate)
    end
    
    -- Insert with proper vehicle ID linking
    MySQL.insert.await([[
        INSERT INTO pf_mdt_incidents (..., involvedVehicleIds, ...)
        VALUES (..., ?, ...)
    ]], {
        -- ... other fields
        json.encode(vehiclePlates), -- This enables garage UI integration
        -- ... other fields
    })
end)
```

### Example 4: Custom Garage Script Integration

Integrate with your existing garage system:

```lua
-- Your garage script
RegisterCommand('opengarage', function()
    -- Open garage UI instead of your old UI
    exports['pf-garageuionly']:OpenGarageUI()
end)

-- Handle vehicle spawn from garage UI
RegisterNetEvent('garage:client:spawnVehicle', function(vehicleData)
    -- Your existing spawn logic
    -- vehicleData contains all the vehicle information
    
    QBCore.Functions.SpawnVehicle(vehicleData.vehicle, function(veh)
        -- Apply mods from vehicleData.mods
        QBCore.Functions.SetVehicleProperties(veh, json.decode(vehicleData.mods))
        
        -- Set fuel, damage, etc.
        SetVehicleFuelLevel(veh, vehicleData.fuel or 100)
        SetVehicleEngineHealth(veh, vehicleData.engine or 1000)
        SetVehicleBodyHealth(veh, vehicleData.body or 1000)
    end)
end)
```

### Example 5: Add Custom Timeline Event

```lua
-- Any resource can add timeline events
RegisterNetEvent('customs:vehiclePainted', function(plate, color, cost)
    if GetResourceState('pf-garageuionly') == 'started' then
        exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
            citizenid = QBCore.Functions.GetPlayer(source).PlayerData.citizenid,
            author = 'Los Santos Customs',
            description = string.format('Vehicle repainted to %s - Cost: $%d', color, cost)
        })
    end
end)
```

---

## Troubleshooting

### Vehicle data not showing

**Problem**: Vehicles appear but have no damage/mileage data  
**Solution**: Ensure pf-mechanicjob's `vehicle_diagnostics` table exists and is being populated

```sql
-- Check if data exists
SELECT * FROM vehicle_diagnostics WHERE plate = 'ABC123';

-- If empty, make sure pf-mechanicjob is running and vehicles have been driven
```

### MDT incidents not appearing

**Problem**: Vehicle timeline doesn't show police incidents  
**Solution**: Check MDT database structure

```sql
-- Verify incidents are linked properly
SELECT incidentId, title, involvedVehicleIds 
FROM pf_mdt_incidents 
WHERE involvedVehicleIds LIKE '%ABC123%';

-- Should return incidents with that plate in the JSON array
```

### UI won't open

**Problem**: `/opengarage` or export doesn't work  
**Solution**: 
1. Check resource is started: `ensure pf-garageuionly`
2. Check console for errors
3. Verify NUI files exist in `html/` folder

```lua
-- Debug in F8 console
print(GetResourceState('pf-garageuionly'))
-- Should print 'started'
```

### Folders not saving

**Problem**: Created folders disappear after restart  
**Solution**: Ensure `vehicle_folders` table exists

```sql
CREATE TABLE IF NOT EXISTS `vehicle_folders` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner` VARCHAR(50) NOT NULL,
    `folder_name` VARCHAR(50) NOT NULL,
    `folder_icon` VARCHAR(50) DEFAULT 'folder',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## Support

For issues or questions:
1. Check this integration guide
2. Verify database tables exist (see [Database Setup](#database-setup))
3. Enable debug mode in `server/integration.lua`: `Config.Debug = true`
4. Check server console for detailed logs

---

**Version**: 1.0.0  
**Last Updated**: February 2026  
**Compatible With**:
- pf-mechanicjob v1.0+
- pf-policemdt-DEV v1.0+
- qb-core / ESX
