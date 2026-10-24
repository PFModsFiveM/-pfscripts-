# Supplies System Quick Reference

## Player Commands
- **No commands needed** - Everything is UI-driven through pf-computer

## Key Bindings (In Mission)
- `[E]` - Pick up pallet / Load pallet / Complete delivery
- `[X]` - Cancel delivery location setting
- Arrow keys - Drive forklift/truck

## Mission Flow

```
Order Created → Sorting (60s) → Packing (90s) → Ready (60s) → Pickup Available
                                                                      ↓
                                              Click Pickup Button ← ─ ┘
                                                                      ↓
                                              Truck & Forklift Spawn
                                                                      ↓
                                              Get in Forklift ← ─ ─ ─ ┘
                                                                      ↓
                                              Drive to Pallets
                                                                      ↓
                                              Press [E] to Pick Up ← ─┘
                                                                      ↓
                                              Drive to Truck Back
                                                                      ↓
                                              Open Truck Doors
                                                                      ↓
                                              Press [E] to Load ← ─ ─ ┘
                                                                      ↓
                                              Repeat for All Pallets
                                                                      ↓
                                              Drive Truck to Delivery Zone
                                                                      ↓
                                              Press [E] to Complete
                                                                      ↓
                                              Mission Complete!
```

## Config Quick Edit

**Pallet Locations**: `pf-mechanicjob/config.lua` → `Config.SuppliesOrder.palletSpawns`
**Forklift Spawn**: `Config.SuppliesOrder.forkliftSpawn`
**Truck Spawn**: `Config.SuppliesOrder.truckSpawn`
**Truck Model**: `Config.SuppliesOrder.truckModel` (default: 'mule')

## Troubleshooting

### "Truck back must be open"
- Open truck rear doors before loading
- Doors 2, 3, 4, or 5 must have angle > 0.3
- For 'mule', use door 2 or 3

### Pallet won't attach
- Must be in forklift
- Drive closer to pallet (< 5m)
- Make sure pallet isn't already loaded

### Truck didn't spawn
- Check server console for errors
- Ensure 'mule' model exists
- Verify qb-vehiclekeys is running

### Delivery location not saving
- Check pc_data.json permissions
- Verify you have job permission
- Check server console for errors

## Developer Notes

### Adding Custom Pallet Spawn
```lua
-- config.lua
palletSpawns = {
    vector3(x, y, z),
    vector3(x, y, z),
    -- Add more...
}
```

### Changing Truck Model
```lua
-- config.lua
truckModel = 'benson', -- Instead of 'mule'
```

### Adjusting Pallet Attachment Offset
```lua
-- client/supplies.lua → PickupPallet()
AttachEntityToEntity(pallet, forkliftEntity, 0, 
    0.0,  -- Forward/back (increase to move forward)
    2.2,  -- Left/right
    0.3,  -- Up/down (increase to raise)
    0.0, 0.0, 0.0, false, false, false, false, 2, true
)
```

### Adjusting Door Detection
```lua
-- client/supplies.lua → StartForkliftInteraction()
for doorIdx = 2, 5 do -- Check doors 2-5
    local doorAngle = GetVehicleDoorAngleRatio(truckEntity, doorIdx)
    if doorAngle > 0.3 then -- Angle threshold
        doorOpen = true
        break
    end
end
```

## Data Storage

**Orders**: `pf-computer/pc_data.json` → `businessOrders[job]`
**Delivery Locations**: `businessDeliveryLocations[job]`
**Accounts**: `businessAccounts[job]`

## Integration Points

### pf-computer → pf-mechanicjob
- Catalog: Uses `exports['pf-mechanicjob']:GetBusinessConfig()`
- Pickup trigger: `TriggerEvent('pf-mechanicjob:server:supplies:startPickup', src, order)`

### pf-mechanicjob → qb-vehiclekeys
- Keys given via `exports['pfm-vehiclekeys']:GiveKeys(src, plate)`

### Client → Server
- Pallet loaded: `TriggerServerEvent('pf-mechanicjob:server:pickupPallet')`
- Delivery complete: `TriggerServerEvent('pf-mechanicjob:server:completeDelivery')`

## Performance Considerations

- Pallets use FreezeEntityPosition (no physics)
- Forklift is a driven vehicle (physics enabled)
- Phantom truck uses alpha + no collision (optimized)
- Mission cleanup on disconnect handled
- One active mission per player maximum

## Common Modifications

### Change Order Processing Time
```lua
-- config.lua
timing = {
    baseSorting = 30,  -- 30 seconds instead of 60
    basePacking = 60,  -- 60 seconds instead of 90
    baseReady = 30,    -- 30 seconds instead of 60
    perCase = 5        -- 5 seconds per case instead of 8
}
```

### Change Detection Ranges
```lua
-- client/supplies.lua
local closestDist = 5.0  -- Pallet pickup range
if distToTruck < 3.0 then -- Truck loading range
if dist < 10.0 then      -- Delivery zone range
```

### Add More Pallet Models
```lua
-- config.lua
palletModels = {
    'prop_pallet_02a',
    'prop_boxpile_07a',
    'prop_pallet_01a',      -- Add more
    'hei_prop_carrier_cargo_02a'
}
```

## Version History
- v1.0 - Initial release with all features
- Window resizing fix
- Server-side spawning
- Interactive forklift system
- Delivery location setting
