# Integration Examples

This folder contains example code showing how to integrate pf-garageuionly with your existing scripts.

## Files

### integration_example.lua

Complete integration examples including:

1. **Replace Old Garage Command** - Simple garage UI trigger
2. **Zone-Based Garage Access** - Open garage when near specific locations
3. **Custom Vehicle Spawn** - Handle vehicle spawning from UI
4. **Timeline Events** - Add custom events to vehicle history
5. **Damage Monitoring** - Track and sync vehicle damage
6. **Data Retrieval** - Get vehicle information for other systems
7. **Mechanic Job Integration** - Link repairs to timeline
8. **Police MDT Integration** - Connect incidents to vehicles
9. **Player Vehicle Management** - List and manage all vehicles

## How to Use

These are **example files only** - do not add to fxmanifest.lua.

Copy the code you need into your own resources:

```lua
-- In your garage script (client.lua)
RegisterCommand('garage', function()
    exports['pf-garageuionly']:OpenGarageUI()
end)

-- In your mechanic script (server.lua)
RegisterNetEvent('mechanic:repairComplete', function(plate, cost)
    exports['pf-garageuionly']:AddVehicleHistoryEvent(plate, {
        citizenid = Player.PlayerData.citizenid,
        author = 'Mechanic Shop',
        description = 'Repair completed - $' .. cost
    })
end)
```

## Quick Start

### 1. Open Garage UI
```lua
-- Client-side
exports['pf-garageuionly']:OpenGarageUI()
```

### 2. Get Vehicle Data
```lua
-- Server-side
local data = exports['pf-garageuionly']:GetVehicleData('ABC123')
print(data.mileage, data.policeHeat)
```

### 3. Add Timeline Event
```lua
-- Server-side
exports['pf-garageuionly']:AddVehicleHistoryEvent('ABC123', {
    citizenid = 'ABC12345',
    author = 'System',
    description = 'Custom event'
})
```

### 4. Update Damage
```lua
-- Server-side
exports['pf-garageuionly']:UpdateVehicleDamage('ABC123', {
    engineHealth = 950,
    bodyHealth = 850
})
```

## Full Documentation

See parent folder documentation:
- **[INTEGRATION.md](../INTEGRATION.md)** - Complete API reference
- **[QUICK_REFERENCE.md](../QUICK_REFERENCE.md)** - Quick lookup guide
- **[README.md](../README.md)** - Feature documentation

## Testing

To test the examples:

1. Ensure pf-garageuionly is running
2. Import the SQL schema
3. Use the commands:
   - `/mygarage` - Open garage UI
   - `/checkvehicle ABC123` - Check vehicle data
   - `/myvehicles` - List your vehicles

## Need Help?

Check the troubleshooting section in [INTEGRATION.md](../INTEGRATION.md#troubleshooting).
