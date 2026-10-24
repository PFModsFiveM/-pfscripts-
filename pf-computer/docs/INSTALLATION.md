# PF-Computer - QBCore Installation Guide

## Overview
This resource has been updated to work with **QBCore Framework** and includes full integration with targeting systems (ox_target or qb-target).

## Features
- ✅ Full QBCore integration
- ✅ Support for ox_target and qb-target
- ✅ All computer and monitor props enabled for testing
- ✅ Player data integration (job, name, money, etc.)
- ✅ ESC to close interface
- ✅ Commands for manual open/close
- ✅ Professional Windows-like UI

## Installation

### 1. Dependencies
Make sure you have these resources installed and started:
- `qb-core` (required)
- `ox_target` or `qb-target` (required)

### 2. Configuration
Edit `config.lua` to customize:

```lua
-- Framework (default: qbcore)
Config.Framework = 'qbcore' -- or 'esx'

-- Target System
Config.TargetSystem = 'ox_target' -- or 'qb-target'

-- Use third-eye targeting or key-based interaction
Config.UseThirdEye = true -- Set to false to use E key instead

-- Interaction distance (meters)
Config.InteractionDistance = 2.0
```

### 3. Start the Resource
Add to your `server.cfg`:
```
ensure pf-computer
```

Make sure it starts **after** qb-core and your target system:
```
ensure pfm-core
ensure ox_target
ensure pf-computer
```

## Usage

### For Players
1. **Walk up to any computer or monitor prop**
2. **Use your targeting system** (ox_target or qb-target) and select "Use Computer"
3. **Or use the command**: `/computer`
4. **Close with ESC key** or click Power > Shut Down

### Currently Enabled Props
All the following props are interactive:
- Desktop computers (prop_pc_01a, prop_pc_02a, etc.)
- Laptops (prop_laptop_01a, prop_laptop_lester, etc.)
- Monitors (prop_monitor_01a, prop_monitor_02a, etc.)
- Office computers (v_serv_ct_monitor01, etc.)

### Commands
- `/computer` - Open computer interface
- `/closecomputer` - Close computer interface

## Troubleshooting

### Computer doesn't open when targeting
1. Make sure your target system is installed and started
2. Check Config.TargetSystem matches your target resource name
3. Try using `/computer` command to test if the UI works

### Can't see the targeting option
1. Verify Config.UseThirdEye = true
2. Make sure you're within Config.InteractionDistance (default 2.0 meters)
3. Check that the prop model is in Config.ComputerProps list

### Framework errors
1. Ensure qb-core is started before pf-computer
2. Check that Config.Framework = 'qbcore'
3. Look in F8 console for any Lua errors

### UI doesn't show
1. Press F8 and check for JavaScript errors
2. Make sure all files are in the resource folder
3. Try restarting the resource: `restart pf-computer`

## Support
For issues or questions, check the console (F8) for any error messages.

## Credits
- Original UI: PF Scripts
- QBCore Integration: Updated for FiveM QBCore compatibility
