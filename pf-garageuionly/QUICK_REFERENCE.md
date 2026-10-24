# PF Garage UI - Quick Reference

Fast reference for developers integrating with pf-garageuionly.

---

## 📦 Installation

```bash
# 1. Place resource in [pfscripts] folder
# 2. Add to server.cfg:
ensure oxmysql
ensure pfm-core
ensure pf-mechanicjob    # Optional
ensure pf-policemdt-DEV  # Optional  
ensure pf-garageuionly

# 3. Run SQL (sql/garage.sql)
# 4. Restart server
```

---

## 🎯 Server Exports

```lua
-- Get vehicle data with all integrations
local data = exports['pf-garageuionly']:GetVehicleData('ABC123')

-- Get all player vehicles
local vehicles = exports['pf-garageuionly']:GetPlayerVehicles('ABC12345')

-- Update damage externally
exports['pf-garageuionly']:UpdateVehicleDamage('ABC123', {
    engineHealth = 950,
    bodyHealth = 850,
    tankHealth = 1000,
    dirtLevel = 25
})

-- Add timeline event
exports['pf-garageuionly']:AddVehicleHistoryEvent('ABC123', {
    citizenid = 'ABC12345',
    author = 'John Mechanic',
    description = 'Full service - $500'
})
```

---

## 💻 Client Exports

```lua
-- Open garage UI
exports['pf-garageuionly']:OpenGarageUI()

-- Get vehicle data (client callback)
local data = exports['pf-garageuionly']:GetVehicleData('ABC123')

-- Get all vehicles
local vehicles = exports['pf-garageuionly']:GetAllPlayerVehicles()
```

---

## 📡 Events

### Server Events (Receive)
```lua
-- Sync vehicle state
RegisterNetEvent('pf-garage:syncVehicleState', function(data) end)

-- Toggle favorite
RegisterNetEvent('pf-garage:toggleFavorite', function(plate) end)

-- Create folder
RegisterNetEvent('pf-garage:createFolder', function(name, icon) end)

-- Add to folder
RegisterNetEvent('pf-garage:addVehicleToFolder', function(vehicleId, folderId) end)
```

### Client Events (Send)
```lua
-- Open UI
TriggerClientEvent('pf-garage:client:openUI', src, 'Legion Square')

-- Update vehicle in UI
TriggerClientEvent('pf-garage:client:updateVehicle', src, 'ABC123', vehicleData)
```

---

## 🔧 pf-mechanicjob Integration

### Add Repair to Timeline
```lua
-- Server-side in pf-mechanicjob
RegisterNetEvent('pf-mechanicjob:server:completeRepair', function(plate, type, cost)
    -- Your repair logic...
    
    -- Add to garage timeline
    if GetResourceState('pf-garageuionly') == 'started' then
        exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
            citizenid = Player.PlayerData.citizenid,
            author = mechanic_name,
            description = string.format('Repair: %s - $%d', type, cost)
        })
    end
end)
```

### Update Damage After Repair
```lua
-- After fixing brakes, oil, etc.
if GetResourceState('pf-garageuionly') == 'started' then
    exports['pf-garageuionly']:UpdateVehicleDamage(plate, {
        engineHealth = newEngineHealth,
        bodyHealth = newBodyHealth
    })
    
    -- Notify player's UI
    TriggerClientEvent('pf-garage:client:updateVehicle', src, plate, {
        enginePercent = math.floor((newEngineHealth / 1000) * 100)
    })
end
```

### Track NOS Installation
```lua
-- After installing NOS
MySQL.update.await([[
    UPDATE player_vehicles 
    SET hasnitrom = 1, noslevel = 100, noscolor = ?
    WHERE plate = ?
]], { color, plate })

-- Garage UI will auto-detect on next open
```

---

## 👮 pf-policemdt Integration

### Link Vehicle to Incident
```lua
-- Server-side in pf-policemdt-DEV
RegisterNetEvent('pf-mdt:server:createIncident', function(data)
    -- Extract vehicle plates
    local plates = {}
    for _, vehicle in ipairs(data.involvedVehicles) do
        table.insert(plates, vehicle.plate)
    end
    
    -- Save incident with vehicle IDs
    MySQL.insert.await([[
        INSERT INTO pf_mdt_incidents 
        (..., involvedVehicleIds, ...)
        VALUES (..., ?, ...)
    ]], {
        -- ...
        json.encode(plates), -- This enables garage integration
        -- ...
    })
end)
```

Garage UI will automatically:
- Show incidents in vehicle timeline
- Calculate police heat level
- Display incident details

---

## 🗄️ Database Tables Used

### From pf-mechanicjob
- `vehicle_diagnostics` - Part damage, mileage, health
- `pf_work_orders` - Repair jobs
- `pf_job_history` - Completed repairs
- `pf_service_log` - Service book
- `player_vehicles.hasnitrom/noslevel/noscolor` - NOS

### From pf-policemdt-DEV
- `pf_mdt_incidents` - Police incidents
  - Uses `involvedVehicleIds` column (JSON array of plates)

### From pf-garageuionly
- `player_vehicles.*` - Extended columns (title_status, insurance, favorite, etc.)
- `vehicle_folders` - Player organization

---

## 🎨 Vehicle Data Structure

```lua
{
    id = 1,
    plate = 'ABC123',
    owner = 'ABC12345',
    vehicle = 'turismor',
    mileage = 12345,
    
    -- Percentages for UI
    fuelPercent = 75,
    enginePercent = 90,
    bodyPercent = 85,
    cleanliness = 50,
    
    -- Status
    titleStatus = 'clean', -- clean|salvage|rebuilt|scrapped
    insurance = 'Premium',
    policeHeat = 'low', -- none|low|medium|high
    
    -- Flags
    favorite = true,
    isJobVehicle = false,
    folderId = nil,
    
    -- Upgrades
    hasNOS = true,
    nosLevel = 100,
    
    -- Damage breakdown
    damage = {
        parts = {
            oil = 15,
            brakes = 0,
            suspension = 25,
            -- ... all parts from vehicle_diagnostics
        },
        panels = {
            { name = 'Hood', severity = 'minor' }
        },
        tires = {'good', 'good', 'worn', 'blown'}
    },
    
    -- Timeline
    history = {
        {
            type = 'purchase',
            date = '2025-06-15',
            title = 'Vehicle Purchased',
            description = 'Bought from dealership'
        },
        {
            type = 'repair',
            date = '2025-09-10',
            title = 'Engine Maintenance',
            description = 'Oil change - $150'
        },
        {
            type = 'crime',
            date = '2025-11-22',
            title = 'Police Chase',
            description = 'High Priority | Del Perro',
            incidentId = 'INC-001'
        }
    }
}
```

---

## ⚡ Common Tasks

### Replace Garage UI in Your Script
```lua
-- Old way:
TriggerEvent('old-garage:open')

-- New way:
exports['pf-garageuionly']:OpenGarageUI()
```

### Add Custom Event Type
```lua
-- Any resource can add timeline events
RegisterNetEvent('carwash:vehicleWashed', function(plate)
    exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
        citizenid = Player.PlayerData.citizenid,
        author = 'Car Wash',
        description = 'Vehicle washed - $50'
    })
end)
```

### Check Resource State Before Using
```lua
if GetResourceState('pf-garageuionly') == 'started' then
    exports['pf-garageuionly']:AddVehicleHistoryEvent(...)
end
```

---

## 🐛 Debug Mode

Enable in `server/integration.lua`:
```lua
local Config = {
    Debug = true, -- Set to true
    -- ...
}
```

Prints detailed logs:
- Vehicle data queries
- Database updates
- Integration detection
- Export calls

---

## 📚 Full Documentation

- **[INTEGRATION.md](INTEGRATION.md)** - Complete integration guide
- **[README.md](README.md)** - Feature documentation
- **[sql/garage.sql](sql/garage.sql)** - Database schema

---

**Version**: 1.0.0  
**Author**: ProjectFusion  
**Compatible**: QBCore, ESX, pf-mechanicjob, pf-policemdt-DEV
