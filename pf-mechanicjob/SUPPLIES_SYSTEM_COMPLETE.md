# Supplies Ordering System - Complete Implementation Summary

## Overview
A fully functional supplies ordering system for pf-computer with interactive forklift-based pickup missions. Players can order parts/supplies for their business, then pick them up using a forklift to load pallets into a truck and deliver them to a configurable location.

## Features Implemented

### 1. Window Resizing (pf-computer)
- **Fixed**: Window corner/edge dragging now works properly
- **Files**: `pf-computer/style.css`
- **Changes**: Added CSS for all 8 resize handles (n, e, s, w, ne, se, sw, nw)

### 2. Specific Pallet Coordinates
- **Config**: `pf-mechanicjob/config.lua`
- **Location**: 8 specific pallet spawn coordinates at warehouse
- **Coordinates**:
  ```lua
  vector3(1184.02, -3251.22, 6.03)
  vector3(1184.02, -3248.93, 6.03)
  vector3(1184.02, -3246.64, 6.03)
  vector3(1184.02, -3244.35, 6.03)
  vector3(1185.56, -3251.22, 6.03)
  vector3(1185.56, -3248.93, 6.03)
  vector3(1185.56, -3246.64, 6.03)
  vector3(1185.56, -3244.23, 6.03)
  ```

### 3. Server-Side Vehicle Spawning
- **Pattern**: Follows pf-rentals server-side spawning approach
- **Files**: `pf-mechanicjob/server/supplies.lua`
- **Features**:
  - Uses `CreateVehicleServerSetter` for networked vehicles
  - Automatic qb-vehiclekeys integration
  - Proper vehicle health and properties setup
  - Network ID tracking for client synchronization

### 4. Forklift Pallet Interaction System
- **Inspired by**: qb-garbagejob dumpster pickup mechanics
- **Files**: `pf-mechanicjob/client/supplies.lua`
- **Flow**:
  1. Player gets in forklift
  2. Drive near pallet (5m detection radius)
  3. Press `[E]` to pick up pallet (attaches to forklift)
  4. Drive to back of truck
  5. Truck back door must be open (checks door angle ratio)
  6. Press `[E]` to load pallet into truck
  7. Pallet is deleted and server is notified
  8. Repeat for all pallets

### 5. Truck Loading System
- **Requirements**:
  - Must be in forklift
  - Pallet must be attached to forklift
  - Must be within 3m of truck back
  - Truck rear doors must be open (angle > 0.3)
- **Features**:
  - Real-time progress tracking
  - Notifications for remaining pallets
  - Automatic delivery phase when all loaded

### 6. Delivery Location Setting
- **UI**: Settings tab in Order Supplies program
- **Process**:
  1. Click "Set Delivery Location" button
  2. Computer UI closes
  3. Semi-transparent phantom 'mule' truck spawns
  4. Truck follows player position/rotation
  5. Press `[E]` to confirm location
  6. Press `[X]` to cancel
  7. Location saved to business data
- **Files**:
  - `pf-computer/script.js` - Settings tab and UI
  - `pf-computer/client.lua` - Phantom truck placement
  - `pf-computer/server.lua` - Save delivery location
  - `pf-computer/style.css` - Settings page styling

## Technical Implementation Details

### Config Structure (pf-mechanicjob/config.lua)
```lua
Config.SuppliesOrder = {
    timing = {
        baseSorting = 60,
        basePacking = 90,
        baseReady = 60,
        perCase = 8
    },
    casesPerPallet = 10,
    palletSpawns = { ... }, -- 8 specific coords
    forkliftSpawn = vector4(1191.24, -3236.42, 6.03, 89.04),
    truckSpawn = vector4(1187.60, -3248.50, 5.50, 90.0),
    defaultDropoffLocation = vector4(-350.18, -133.84, 39.01, 0.0),
    truckModel = 'mule',
    palletModels = { 'prop_pallet_02a', 'prop_boxpile_07a' },
    forkliftModel = 'forklift'
}
```

### Server Events (pf-mechanicjob/server/supplies.lua)
- `pf-mechanicjob:server:supplies:startPickup` - Spawns truck, gives keys, triggers client
- `pf-mechanicjob:server:pickupPallet` - Tracks pallet loading progress
- `pf-mechanicjob:server:completeDelivery` - Completes delivery and cleans up mission

### Client Events (pf-mechanicjob/client/supplies.lua)
- `pf-mechanicjob:client:supplies:pickupStart` - Spawns forklift, pallets, starts interaction loop
- `pf-mechanicjob:client:supplies:startDelivery` - Creates blip and delivery zone
- `pf-mechanicjob:client:supplies:cleanup` - Deletes all mission entities

### Computer Integration (pf-computer)
**NUI Callbacks**:
- `pc:supplies:getCatalog` - Get supplies catalog
- `pc:supplies:orders:list` - List orders
- `pc:supplies:orders:create` - Create order (includes deliveryLocation)
- `pc:supplies:orders:pickup` - Start pickup mission
- `pc:supplies:setDeliveryLocation` - Set delivery location (custom handling)

**Server Handlers**:
- `business:supplies:catalog` - Returns catalog from pf-mechanicjob
- `business:supplies:orders:create` - Creates order, debits account, includes delivery location
- `business:supplies:orders:pickup` - Triggers pf-mechanicjob pickup mission
- `pf-computer:server:setDeliveryLocation` - Saves delivery location to business data

### Data Storage
**Location**: `pf-computer/pc_data.json`
**New Fields**:
```json
{
  "businessDeliveryLocations": {
    "mechanic": { "x": 123.45, "y": 67.89, "z": 10.11, "w": 90.0 },
    "mechanic2": { ... }
  },
  "businessOrders": {
    "mechanic": [
      {
        "id": 1,
        "deliveryLocation": { "x": 123.45, "y": 67.89, "z": 10.11, "w": 90.0 },
        ...
      }
    ]
  }
}
```

## User Guide

### Ordering Supplies
1. Open Business Manager on computer
2. Click "Order Supplies" program
3. Browse catalog, add items to cart
4. Select "Pickup" fulfillment
5. Checkout (debits company account)
6. Wait for order to be ready (timeline shown in Orders tab)

### Setting Delivery Location (Optional)
1. Open Order Supplies → Settings tab
2. Click "Set Delivery Location"
3. Computer closes, phantom truck appears
4. Walk to desired delivery location
5. Press `[E]` to confirm or `[X]` to cancel
6. Location saved for all future orders

### Pickup Mission
1. When order is "Ready", click "Pickup" button
2. Truck spawns at warehouse with keys given
3. Get in forklift (also spawned nearby)
4. Drive to pallets and press `[E]` to pick up
5. Drive to back of truck (open rear doors first!)
6. Press `[E]` to load pallet
7. Repeat for all pallets
8. Once loaded, drive truck to delivery location
9. Enter delivery zone and press `[E]` to complete

## Testing Checklist

- [x] Window resizing works on all corners/edges
- [x] Pallets spawn at exact coordinates
- [x] Truck spawns server-side with keys
- [x] Forklift can be driven
- [x] Pallet pickup attaches to forklift
- [x] Truck door check works
- [x] Pallet loading deletes prop
- [x] Server tracks progress
- [x] Delivery blip appears after loading
- [x] Delivery completion works
- [x] Settings tab displays
- [x] Phantom truck placement works
- [x] Delivery location saves to server
- [x] Orders include delivery location

## Known Limitations

1. **Truck Model**: Currently hardcoded to 'mule' (as requested)
2. **Door Detection**: Checks doors 2-5, may need adjustment for other truck models
3. **Pallet Attachment**: Offset may need tweaking for different forklift models
4. **No Inventory Integration**: Delivery completion doesn't add items to inventory (marked as TODO)

## Future Enhancements

1. **Inventory Integration**: Add items to pf-mechanicjob parts stock system on delivery
2. **Multiple Trucks**: Re-enable truckOptions based on order size
3. **Custom Pallets**: Support different pallet models per item type
4. **Progress Persistence**: Save mission state to survive disconnects
5. **Multi-Location Warehouses**: Support multiple pickup locations
6. **NPC Assistance**: Add warehouse workers or automated loading

## Files Modified

### pf-computer
- `style.css` - Window resize handles, settings page styling
- `script.js` - Settings tab, renderSettings(), setDeliveryLocation()
- `client.lua` - SetDeliveryLocationClient(), phantom truck placement
- `server.lua` - Save delivery location, include in orders

### pf-mechanicjob
- `config.lua` - Updated SuppliesOrder config
- `client/supplies.lua` - Complete rewrite for interactive system
- `server/supplies.lua` - Server-side spawning, progress tracking
- `fxmanifest.lua` - Already includes supplies scripts

## Version Information
- **Date**: February 2025
- **QBCore**: Compatible
- **Dependencies**: qb-core, qb-vehiclekeys, oxmysql
- **Resources**: pf-computer, pf-mechanicjob

## Credits
- Window resize fix
- Server-side spawning pattern from pf-rentals
- Interaction mechanics inspired by qb-garbagejob
- Phantom placement concept from various delivery scripts
