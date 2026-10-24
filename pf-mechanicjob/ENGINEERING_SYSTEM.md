-- ============================================================================
-- PF MECHANICJOB - ADVANCED VEHICLE ENGINEERING & TUNING SYSTEM
-- Complete Implementation Documentation
-- ============================================================================

/*
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║           ADVANCED VEHICLE ENGINEERING AND TUNING SYSTEM                  ║
║                      For pf-mechanicjob v2.0+                            ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

## OVERVIEW

This comprehensive upgrade transforms the pf-mechanicjob system into a 
realistic vehicle engineering and tuning platform with:

✓ Persistent mechanical components and upgrades
✓ Advanced wear and heat management systems
✓ Realistic power delivery and torque curves
✓ Component compatibility validation
✓ Service history and maintenance tracking
✓ Dynamic fuel consumption and drivetrain stress
✓ Backwards compatible with existing upgrade systems
✓ Full tablet integration with Dyno and Tuning apps

## KEY FEATURES

### 1. COMPONENT SYSTEM

Instead of flat "engine level 1,2,3" upgrades, each vehicle now has:
- Engine block (stock, strengthened, forged)
- Internals (pistons, compression)
- Forced induction (none, turbo stages 1-3, supercharger stages 1-2)
- Intercooler (street, race)
- Fuel system (injectors, pump, fuel type)
- ECU maps (stock, eco, street, performance, race, valet)
- Ignition, cooling, oil systems
- Drivetrain (clutch, gearbox, differential)
- Tires (street, sport, semi-slick, slick)

### 2. REALISTIC POWER DELIVERY

- Torque curves vary by build type
- Turbo builds peak mid-high RPM
- Superchargers provide low-RPM torque
- Dynamic RPM-based multipliers
- Wear causes power loss
- Heat triggers limp mode

### 3. WEAR & HEAT DYNAMICS

Per-vehicle tracking of:
- Engine wear (0-100%)
- Turbo wear
- Clutch wear
- Gearbox wear
- Differential wear
- Oil quality
- Coolant quality
- Engine temperature
- Turbo temperature

Heavy use of boosted vehicles increases wear exponentially.

### 4. FUEL CONSUMPTION

Consumption scales based on:
- Horsepower ratio (exponentially)
- Throttle input
- RPM
- ECU map (eco reduces by 25%)
- Fuel type (E85 increases by 35%)
- Oil/coolant quality
- Engine wear

### 5. DRIVETRAIN STRESS

- Torque rated components (clutch, gearbox, differential)
- Over-limit = wear increase + failure chance
- Launch detection for hard acceleration effects
- Wheelspin causes differential wear

### 6. SIMPLE MODE (BACKWARDS COMPATIBILITY)

Minor upgrades that don't require complex builds:
- Air filter: +2% HP
- Cat-back exhaust: +3% HP
- Spark plugs: +1% HP, -50% misfire
- Basic ECU tune: +5% HP
- Oil change: Reset wear
- Coolant flush: Reset heat issues
- Tire upgrade: Better grip

## CONFIGURATION

All settings are in: `config/engineering.lua`

### Enable/Disable
```lua
EngineConfig.Enabled = true
```

### Realism Level
```lua
EngineConfig.RealisticMode = 'balanced'  -- casual, balanced, hardcore
```

### Quick Toggles
```lua
-- Enforce component limits
EngineConfig.ValidationRules.enforce_drivetrain_limits = true
EngineConfig.ValidationRules.enforce_cooling_limits = true
EngineConfig.ValidationRules.enforce_tire_limits = true

-- Enable failure system
EngineConfig.RealisticPresets[EngineConfig.RealisticMode].max_power_allowed = 5.0
```

## DATABASE SCHEMA

### pf_vehicle_tuning
Main tuning record per vehicle. Stores all component selections, wear, and condition.

**Key fields:**
- plate (unique)
- engine_block, internals, forced_induction, etc. (VARCHAR 32)
- engine_wear, turbo_wear, ... (INT 0-100)
- oil_quality, coolant_quality (INT 0-100)
- engine_heat, turbo_heat (INT 0-100)
- fuel_consumption_multiplier, maintenance_cost_multiplier

**Indexed on:** plate, updated_at

### pf_vehicle_service_history
Transaction log of all services performed.

**Fields:**
- plate, service_type, cost, mechanic_id, created_at

## SERVER API

### Core Functions
```lua
local Engineering = require('server.engineering.sv_engineering')

-- Get or create tuning
local tuning = Engineering:GetOrCreateTuning(plate, model)

-- Get tuning
local tuning = Engineering:GetTuning(plate)

-- Save tuning
Engineering:SaveTuning(plate, tuningData)

-- Install component
Engineering:InstallComponent(plate, componentType, componentValue)

-- Set ECU map
Engineering:SetECUMap(plate, mapName)

-- Set boost
Engineering:SetBoost(plate, psi)

-- Services
Engineering:ServiceOil(plate, cost, mechanicId)
Engineering:ServiceCooling(plate, cost, mechanicId)
Engineering:RebuildEngine(plate, cost, mechanicId)
Engineering:ReplaceClutch(plate, cost, mechanicId)
Engineering:RebuildGearbox(plate, cost, mechanicId)

-- Get summary for UI
local summary = Engineering:GetBuildSummary(plate)
```

### Exports
```lua
-- Server exports (can be triggered by tablets/menus)
exports('GetTuning', function(plate) ... end)
exports('GetBuildSummary', function(plate) ... end)
exports('ApplySimpleUpgrade', function(plate, upgradeId) ... end)
exports('InstallComponent', function(plate, componentType, value) ... end)
```

## CLIENT API

### Events (from server → client)
```lua
-- Receive tuning sync
RegisterNetEvent('engineering:syncTuning', function(tuning) ... end)

-- Heat/wear updated
RegisterNetEvent('engineering:syncWearHeat', function(wear, heat, ...) ... end)
```

### Events (from client → server)
```lua
-- Request tuning
TriggerServerEvent('engineering:requestTuning', plate)

-- Sync wear/heat
TriggerServerEvent('engineering:syncWearAndHeat', plate, engineWear, ...)

-- Change ECU
TriggerServerEvent('engineering:setECUMap', plate, mapName)

-- Set boost
TriggerServerEvent('engineering:setBoost', plate, psi)
```

### Exports
```lua
-- Client exports
exports('GetTuning', function() ... end)
exports('GetRuntimeState', function() ... end)
exports('SetECUMap', function(plate, mapName) ... end)
exports('SetBoost', function(plate, psi) ... end)
```

## TABLET INTEGRATION

### Tuning App
Provides UI for:
- Viewing current build
- Installing components
- Applying simple upgrades
- Changing ECU map
- Viewing wear/heat status
- Boost adjustment

### Dyno App
- Live RPM sweep simulation
- Torque and HP curve display
- Boost graph
- Save results to history

### Callbacks Available
```lua
-- Get simple upgrades
QBCore.Functions.CreateCallback('tablet:tuning:getSimpleUpgrades', ...)

-- Get major components by type
QBCore.Functions.CreateCallback('tablet:tuning:getMajorComponents', ...)

-- Get ECU maps
QBCore.Functions.CreateCallback('tablet:tuning:getECUMaps', ...)

-- Validate build
QBCore.Functions.CreateCallback('tablet:tuning:validateBuild', ...)

-- Run dyno test
QBCore.Functions.CreateCallback('tablet:tuning:runDyno', ...)

-- Generate receipt
QBCore.Functions.CreateCallback('tablet:tuning:generateReceipt', ...)

-- Get parts catalog
QBCore.Functions.CreateCallback('tablet:tuning:getPartsCatalog', ...)

-- Get upgrade recommendations
QBCore.Functions.CreateCallback('tablet:tuning:getUpgradePath', ...)
```

## BACKWARDS COMPATIBILITY

### Existing Upgrades
Old "Engine Level 1" items map to new system:
- Engine Level 1 → intake street + exhaust street + ecu_map street
- Engine Level 2 → injectors 550cc + fuel pump street + ecu_map performance
- Turbo upgrade → turbo_stage1 + intercooler street + ecu_map performance

Add custom mappings in `sv_integration.lua`:
```lua
local upgradeMap = {
    ['your_item_name'] = 'simple_upgrade_id',
    ...
}
```

### Vehicles Without Tuning
Vehicles without a tuning record behave as completely stock.
No tuning system effects applied.
No wear, heat, or consumption scaling.

### Disable System
Set in config:
```lua
EngineConfig.Enabled = false  -- Everything bypassed
```

## CONSOLE COMMANDS (Optional - Can Add)

```lua
-- Check vehicle tuning
/checktuning [plate]

-- Force create tuning
/createtuning [plate]

-- Reset wear
/resetwear [plate]

-- Set boost
/setboost [plate] [psi]

-- Test dyno
/testdyno [plate]
```

## PERFORMANCE CONSIDERATIONS

### Server Load
- Per-vehicle cache for tuning data
- Periodic flush to database (every 30 seconds)
- Service history is write-once (minimal overhead)
- Calculation cached when player enters vehicle

### Client Load
- Physics update loop: 30 ticks/sec (33ms)
- Sync to server: every 10 seconds
- Only runs when player is driving
- Automatic cleanup on vehicle exit

### Database
- Indexed on plate for O(1) lookups
- Tuning table: ~100 bytes per vehicle
- Service history: ~50 bytes per service
- Created tables auto-indexed on create

## TROUBLESHOOTING

### Tuning not persisting?
1. Check `pf_vehicle_tuning` table exists (auto-created by sql_init)
2. Verify plate format (should be uppercase, spaces trimmed)
3. Check server logs for SQL errors

### Power not scaling?
1. Verify `SetVehicleEnginePowerMultiplier` is working
2. Check player is in driver seat (required)
3. Try disabling other power scripts temporarily

### Heat not building?
1. Check `engine_heat` is being updated in physics loop
2. Verify coolingConfig is loaded properly
3. Ensure vehicle stays at high RPM/boost

### No tablet integration?
1. Confirm callbacks are registered (check console)
2. Verify tablet script is calling callbacks with correct syntax
3. Check event names match exactly

## FUTURE ENHANCEMENTS

Potential additions to build on this system:

1. **Turbo Anti-Lag** (fuel enrichment, backfires)
2. **Nitrous Override** (temporary power boost with risk)
3. **Custom Handling** (per-build handling modifications)
4. **Paint Code System** (color/finish customization)
5. **Sound Packs** (engine sound variations)
6. **Leaderboards** (dyno records, fastest builds)
7. **Build Sharing** (export/import configs)
8. **AI Driver Telemetry** (AI performance comparison)

## SUPPORT

For issues:
1. Check `Config.Debug = true` for detailed logs
2. Monitor server console during startup
3. Verify all files in `/server/engineering/` folder
4. Check `fxmanifest.lua` includes all scripts
5. Test with `EngineConfig.RealisticMode = 'casual'` first

## VERSION HISTORY

v1.0.0 - Initial comprehensive implementation
- Full component system
- Wear and heat tracking
- Service integration
- Tablet support
- Client physics loop

---
Made with ❤️ for the PF Mechanic community
Last updated: February 27, 2026
*/
