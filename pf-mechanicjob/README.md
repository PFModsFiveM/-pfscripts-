# PF Mechanic Job - Installation Guide

## Overview
Advanced mechanic job system for QBCore with realistic vehicle diagnostics, damage simulation, NPC jobs, POS system, and multi-business management.

## Features
- ✅ Realistic vehicle damage system (brakes, oil, engine, suspension, etc.)
- ✅ Dynamic environmental damage (water, mud, terrain)
- ✅ Vehicle diagnostics tablet with detailed part inspection
- ✅ NPC job system with automatic job generation
- ✅ Point of Sale (POS) system for customer billing
- ✅ Multi-business support (multiple mechanic shops)
- ✅ Garage integration (qb-garages & cd_garages compatible)
- ✅ Service book for vehicle maintenance history
- ✅ Performance and cosmetic upgrades
- ✅ Persistent vehicle state (damage saves to database)

---

## Requirements

### Dependencies
- **QBCore Framework** (latest version)
- **oxmysql** (latest version)
- **qb-menu** (for menus)
- **qb-target** or **qb-radialmenu** (optional, for interactions)
- **LegacyFuel** or compatible fuel script (configured in `qb-garages/config.lua`)

### Compatible Garage Systems
- `qb-garages` (default, included with QBCore)
- `cd_garages` (Codesign's garage system)

---

## Installation Steps

### 1. Database Setup

Run the SQL file to create required tables:

```sql
-- Execute this in your database (HeidiSQL, phpMyAdmin, etc.)
-- File: pf-mechanicjob/pf_mechanic.sql
```

**Tables Created:**
- `vehicle_diagnostics` - Stores vehicle damage/health data
- `pf_business` - Multi-business management
- `pf_employees` - Employee roster
- `pf_pos_items` - POS catalog
- `pf_earnings` - Employee earnings tracking
- `pf_service_book` - Vehicle service history

### 2. Add Items to QBCore

Open `qb-core/shared/items.lua` and add the mechanic parts (see lines 308-425 in the provided file, or use the snippet below):

```lua
    -- ==== PF Mechanic Job (clean, no duplicates; icons aligned to your pack) ====

    -- Mechanic Tools
    mechanic_tools   = { name='mechanic_tools',   label='Mechanic Tools',     weight=2000, type='item', image='toolkit.png',          unique=false, useable=true,  shouldClose=true, combinable=nil, description='Opens diagnostics' },
    diagnosticstool  = { name='diagnosticstool',  label='Diagnostics Tool',   weight=1200, type='item', image='diagnostic.png',        unique=false, useable=true,  shouldClose=true, combinable=nil, description='Opens diagnostics' },
    diagnostics_tool = { name='diagnostics_tool', label='Diagnostics Tool',   weight=1200, type='item', image='diagnostic.png',        unique=false, useable=true,  shouldClose=true, combinable=nil, description='Opens diagnostics' },
    service_book     = { name='service_book',     label='Service Book',       weight=200,  type='item', image='notebook.png',          unique=false, useable=true,  shouldClose=true, combinable=nil, description='Log service entries' },

    -- Repair kit
    repair_kit       = { name='repair_kit',       label='Basic Repair Kit',   weight=1200, type='item', image='repairkit.png',         unique=false, useable=true,  shouldClose=true, combinable=nil, description='Emergency repair kit' },

    -- Core repair parts
    alternator          = { name='alternator',          label='Alternator',            weight=400,  type='item', image='alternator.png',        unique=false, useable=true,  shouldClose=true, combinable=nil, description='Alternator repair.' },
    carbattery          = { name='carbattery',          label='Car Battery',           weight=500,  type='item', image='carbattery.png',        unique=false, useable=true,  shouldClose=true, combinable=nil, description='Electrical replacement.' },
    sparkplugs          = { name='sparkplugs',          label='Spark Plugs',           weight=100,  type='item', image='sparkplugs.png',        unique=false, useable=true,  shouldClose=true, combinable=nil, description='Ignition replacement.' },
    engine_oil          = { name='engine_oil',          label='Engine Oil',            weight=300,  type='item', image='oil.png',               unique=false, useable=true,  shouldClose=true, combinable=nil, description='Engine oil refill.' },
    oil_filter          = { name='oil_filter',          label='Oil Filter',            weight=150,  type='item', image='oilfilter.png',         unique=false, useable=true,  shouldClose=true, combinable=nil, description='Replacement oil filter.' },
    brake_pads          = { name='brake_pads',          label='Brake Pads',            weight=250,  type='item', image='veh_brakes.png',        unique=false, useable=true,  shouldClose=true, combinable=nil, description='Replacement brake pads.' },
    susp_arm            = { name='susp_arm',            label='Suspension Arm',        weight=500,  type='item', image='veh_suspension.png',    unique=false, useable=true,  shouldClose=true, combinable=nil, description='Suspension component.' },
    axleparts           = { name='axleparts',           label='Axle Parts',            weight=400,  type='item', image='axleparts.png',         unique=false, useable=true,  shouldClose=true, combinable=nil, description='Axle/shaft repair.' },
    radiator            = { name='radiator',            label='Radiator',              weight=1200, type='item', image='radiator.png',          unique=false, useable=true,  shouldClose=true, combinable=nil, description='Vehicle radiator.' },
    fuel_injector       = { name='fuel_injector',       label='Fuel Injector',         weight=200,  type='item', image='fuel_injector.png',     unique=false, useable=true,  shouldClose=true, combinable=nil, description='Fuel injector for engine.' },
    powersteeringpump   = { name='powersteeringpump',   label='Power Steering Pump',   weight=700,  type='item', image='powersteeringpump.png', unique=false, useable=true,  shouldClose=true, combinable=nil, description='Power steering pump.' },
    dpf                 = { name='dpf',                 label='DPF',                   weight=1500, type='item', image='dpf.png',              unique=false, useable=true,  shouldClose=true, combinable=nil, description='Diesel Particulate Filter - Remove for rolling coal.' },

    -- Fluids
    power_steering_fluid = { name='power_steering_fluid', label='Power Steering Fluid', weight=0, type='item', image='power_steering_fluid.png', unique=false, useable=true, shouldClose=true, combinable=nil, description='Power Steering Fluid.' },
    transmissionfluid    = { name='transmissionfluid',    label='Transmission Fluid',   weight=0, type='item', image='transmissionfluid.png',    unique=false, useable=true, shouldClose=true, combinable=nil, description='Transmission Fluid.' },
    brakefluid           = { name='brakefluid',           label='Brake Fluid',          weight=0, type='item', image='brakefluid.png',           unique=false, useable=true, shouldClose=true, combinable=nil, description='Brake Fluid.' },
    coolant              = { name='coolant',              label='Coolant',              weight=0, type='item', image='coolant.png',              unique=false, useable=true, shouldClose=true, combinable=nil, description='Coolant.' },

    -- Repair consumables
    engine_part       = { name='engine_part',    label='Engine Part',        weight=200, type='item', image='veh_engine.png',   unique=false, useable=true, shouldClose=true, combinable=nil, description='Used to repair engine.' },
    body_part         = { name='body_part',      label='Body Panel',         weight=350, type='item', image='bodyrepair.png',   unique=false, useable=true, shouldClose=true, combinable=nil, description='Used to repair body.' },
    newoil            = { name='newoil',         label='Car Oil',            weight=200, type='item', image='oil.png',           unique=false, useable=true, shouldClose=true, combinable=nil, description='Top up oil level.' },
    tire_new          = { name='tire_new',       label='New Tire',           weight=600, type='item', image='tire.png',          unique=false, useable=true, shouldClose=true, combinable=nil, description='Replacement tire.' },
    paint_kit         = { name='paint_kit',      label='Body Paint Kit',     weight=350, type='item', image='paintkit.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Paint kit for NPC jobs.' },

    -- Mechanic Job Items (unique benches, tools, misc)
    item_bench        = { name='item_bench',         label='Workbench',                weight=15000, type='item', image='workbench.png',      unique=true,  useable=true,  shouldClose=true, combinable=nil, description='A workbench to craft items.' },
    attachment_bench  = { name='attachment_bench',   label='Attachment Workbench',     weight=15000, type='item', image='attworkbench.png',   unique=true,  useable=true,  shouldClose=true, combinable=nil, description='A workbench for crafting attachments.' },
    mech_tablet       = { name='mech_tablet',        label='Work Order Tablet',        weight=200,   type='item', image='tablet.png',         unique=false, useable=true,  shouldClose=true,  combinable=nil, description='Opens the mechanic tablet.' },
    toolbox           = { name='toolbox',            label='Toolbox',                   weight=800,   type='item', image='veh_toolbox.png',    unique=false, useable=true,  shouldClose=true,  combinable=nil, description='Open repair menu for common systems.' },
    mech_wrench       = { name='mech_wrench',        label='Mechanic Wrench',          weight=200,   type='item', image='wrench.png',         unique=false, useable=true,  shouldClose=true,  combinable=nil, description='General purpose wrench.' },
    paintcan          = { name='paintcan',           label='Vehicle Spray Can',        weight=250,   type='item', image='spraycan.png',       unique=false, useable=true,  shouldClose=true,  combinable=nil, description='Respray player vehicles.' },
    mech_receipt      = { name='mech_receipt',       label='Mechanic Receipt',         weight=0,     type='item', image='printerdocument.png',unique=false, useable=true, shouldClose=true,  combinable=nil, description='Service receipt.' },
    preview_receipt   = { name='preview_receipt',    label='Preview Receipt',          weight=0,     type='item', image='printerdocument.png',unique=false, useable=true, shouldClose=true,  combinable=nil, description='Preview receipt.' },

    -- Cosmetic (player vehicles)
    bumper            = { name='bumper',            label='Vehicle Bumper',     weight=200, type='item', image='bumper.png',        unique=false, useable=true, shouldClose=true, combinable=nil, description='Front/Rear bumpers.' },
    vehicle_bumper    = { name='vehicle_bumper',    label='Vehicle Bumper',     weight=200, type='item', image='bumper.png',        unique=false, useable=true, shouldClose=true, combinable=nil, description='Front/Rear bumpers.' },
    exhaust           = { name='exhaust',           label='Vehicle Exhaust',    weight=200, type='item', image='exhaust.png',       unique=false, useable=true, shouldClose=true, combinable=nil, description='Exhaust options.' },
    externals         = { name='externals',         label='Exterior Cosmetics', weight=200, type='item', image='externals.png',     unique=false, useable=true, shouldClose=true, combinable=nil, description='Grille/Fenders.' },
    hood              = { name='hood',              label='Vehicle Hood',       weight=200, type='item', image='hood.png',          unique=false, useable=true, shouldClose=true, combinable=nil, description='Hood options.' },
    horn              = { name='horn',              label='Custom Horn',        weight=100, type='item', image='horn.png',          unique=false, useable=true, shouldClose=true, combinable=nil, description='Horn options.' },
    internals         = { name='internals',         label='Internal Cosmetics', weight=200, type='item', image='internals.png',     unique=false, useable=true, shouldClose=true, combinable=nil, description='Dash/trim options.' },
    livery            = { name='livery',            label='Livery Roll',        weight=150, type='item', image='livery.png',        unique=false, useable=true, shouldClose=true, combinable=nil, description='Vehicle livery.' },
    customplate       = { name='customplate',       label='Customized Plates',  weight=50,  type='item', image='plate.png',         unique=false, useable=true, shouldClose=true, combinable=nil, description='Set a custom plate.' },
    rims              = { name='rims',              label='Custom Wheel Rims',  weight=400, type='item', image='rims.png',          unique=false, useable=true, shouldClose=true, combinable=nil, description='Wheel styles.' },
    roof              = { name='roof',              label='Vehicle Roof',       weight=200, type='item', image='roof.png',          unique=false, useable=true, shouldClose=true, combinable=nil, description='Roof options.' },
    rollcage          = { name='rollcage',          label='Roll Cage',          weight=500, type='item', image='rollcage.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Roll cage options.' },
    seat              = { name='seat',              label='Seat Cosmetics',     weight=150, type='item', image='seat.png',          unique=false, useable=true, shouldClose=true, combinable=nil, description='Seat styles.' },
    skirts            = { name='skirts',            label='Vehicle Skirts',     weight=150, type='item', image='skirts.png',        unique=false, useable=true, shouldClose=true, combinable=nil, description='Side skirts.' },
    spoiler           = { name='spoiler',           label='Vehicle Spoiler',    weight=200, type='item', image='spoiler.png',       unique=false, useable=true, shouldClose=true, combinable=nil, description='Spoiler options.' },
    tint_supplies     = { name='tint_supplies',     label='Tint Supplies',      weight=120, type='item', image='tint_supplies.png', unique=false, useable=true, shouldClose=true, combinable=nil, description='Window tint options.' },

    -- Performance
    car_armor         = { name='car_armor',     label='Vehicle Armor',         weight=500, type='item', image='armor.png',        unique=false, useable=true, shouldClose=true, combinable=nil, description='Armor upgrade.' },
    brakes1           = { name='brakes1',       label='Tier 1 Brakes',         weight=250, type='item', image='brakes1.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 1 brakes.' },
    brakes2           = { name='brakes2',       label='Tier 2 Brakes',         weight=275, type='item', image='brakes2.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 2 brakes.' },
    brakes3           = { name='brakes3',       label='Tier 3 Brakes',         weight=300, type='item', image='brakes3.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 3 brakes.' },
    engine1           = { name='engine1',       label='Tier 1 Engine',         weight=500, type='item', image='engine1.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 1 engine.' },
    engine2           = { name='engine2',       label='Tier 2 Engine',         weight=550, type='item', image='engine2.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 2 engine.' },
    engine3           = { name='engine3',       label='Tier 3 Engine',         weight=600, type='item', image='engine3.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 3 engine.' },
    engine4           = { name='engine4',       label='Tier 4 Engine',         weight=650, type='item', image='engine4.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 4 engine.' },
    engine5           = { name='engine5',       label='Tier 5 Engine',         weight=700, type='item', image='engine5.png',      unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 5 engine.' },
    suspension1       = { name='suspension1',   label='Tier 1 Suspension',     weight=450, type='item', image='suspension1.png',  unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 1 suspension.' },
    suspension2       = { name='suspension2',   label='Tier 2 Suspension',     weight=475, type='item', image='suspension2.png',  unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 2 suspension.' },
    suspension3       = { name='suspension3',   label='Tier 3 Suspension',     weight=500, type='item', image='suspension3.png',  unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 3 suspension.' },
    suspension4       = { name='suspension4',   label='Tier 4 Suspension',     weight=525, type='item', image='suspension4.png',  unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 4 suspension.' },
    suspension5       = { name='suspension5',   label='Tier 5 Suspension',     weight=550, type='item', image='suspension5.png',  unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 5 suspension.' },
    transmission1     = { name='transmission1', label='Tier 1 Transmission',   weight=450, type='item', image='transmission1.png',unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 1 transmission.' },
    transmission2     = { name='transmission2', label='Tier 2 Transmission',   weight=475, type='item', image='transmission2.png',unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 2 transmission.' },
    transmission3     = { name='transmission3', label='Tier 3 Transmission',   weight=500, type='item', image='transmission3.png',unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 3 transmission.' },
    transmission4     = { name='transmission4', label='Tier 4 Transmission',   weight=525, type='item', image='transmission4.png',unique=false, useable=true, shouldClose=true, combinable=nil, description='Stage 4 transmission.' },
    drifttires        = { name='drifttires',    label='Drift Tires',           weight=400, type='item', image='drifttires.png',     unique=false, useable=true, shouldClose=true, combinable=nil, description='Enable drift tyres.' },
    bprooftires       = { name='bprooftires',   label='Bulletproof Tires',     weight=400, type='item', image='bprooftires.png',    unique=false, useable=true, shouldClose=true, combinable=nil, description='Set tyres bulletproof.' },
    turbo             = { name='turbo',         label='Supercharger Turbo',    weight=300, type='item', image='turbo.png',          unique=false, useable=true, shouldClose=true, combinable=nil, description='Turbo upgrade.' },
    headlights        = { name='headlights',    label='Xenon Headlights',      weight=100, type='item', image='veh_xenons.png',     unique=false, useable=true, shouldClose=true, combinable=nil, description='Xenon lights.' }

    -- ==== End PF Mechanic Job ====

```

### 3. Add Jobs to QBCore

Open `qb-core/shared/jobs.lua` and add mechanic job variants (if using multiple shops):

```lua
mechanic = {
    label = 'LS Customs',
    type = 'mechanic',
    defaultDuty = true,
    offDutyPay = false,
    grades = {
        ['0'] = { name = 'Recruit', payment = 50 },
        ['1'] = { name = 'Novice', payment = 75 },
        ['2'] = { name = 'Experienced', payment = 100 },
        ['3'] = { name = 'Advanced', payment = 125 },
        ['4'] = { name = 'Manager', isboss = true, payment = 150 },
    },
},
-- Add more: mechanic2, mechanic3, bennys, beeker (see qb-core/shared/jobs.lua example)
```

### 4. Configure Garage System

Open `pf-mechanicjob/config.lua` and set your garage system:

```lua
Config.GarageSystem = 'qb-garages' -- or 'cd_garages'
```

**Supported:**
- `qb-garages` (default QBCore garage)
- `cd_garages` (Codesign's garage system)

### 5. Add Items Images

Place item images in your inventory resource's images folder (e.g., `qb-inventory/html/images/` or `qb-core/html/images/`):

Required images:
- `alternator.png`
- `carbattery.png`
- `sparkplugs.png`
- `oil.png`
- `oilfilter.png`
- `veh_brakes.png`
- `veh_suspension.png`
- `axleparts.png`
- `radiator.png`
- `fuel_injector.png`
- `powersteeringpump.png`
- `power_steering_fluid.png`
- `transmissionfluid.png`
- `brakefluid.png`
- `coolant.png`
- `veh_engine.png`
- `bodyrepair.png`
- `tire.png`
- `paintkit.png`
- `repair_kit.png`
- `mechanic_tools.png`
- `service_book.png`

### 6. Start the Resource

Add to your `server.cfg`:

```cfg
ensure pf-mechanicjob
```

Restart your server or use:
```
refresh
start pf-mechanicjob
```

---

## Configuration

### Multi-Business Setup

Edit `config.lua` to add/modify mechanic shops:

```lua
Config.AllowedJobs = {
    'mechanic',   -- LS Customs
    'mechanic2',  -- LS Customs #2
    'mechanic3',  -- LS Customs #3
    'bennys',     -- Benny's Original Motor Works
    'beeker',     -- Beeker's Garage
}

Config.BusinessBranding = {
    mechanic = { business='mechanic', name='LS Customs', primary_color='#0BA378', ... },
    bennys   = { business='bennys',   name="Benny's Original Motor Works", ... },
    -- Add more here
}
```

### Wear Rate Tuning

Adjust damage rates in `config.lua` under `Config.WearRates`:

```lua
Config.WearRates = {
    brakes = {
        baselineRandomMin = 0.01,
        baselineRandomMax = 0.05,
        -- ... more settings
    },
    oil = { ... },
    radiator = { ... },
    -- etc.
}
```

### Debug Mode

Enable/disable debug messages:

```lua
Config.Debug = true -- Set to false in production
```

---

## Usage

### For Players

**Mechanic Tools:**
- Use `mechanic_tools` item to open diagnostics menu
- Inspect vehicle to see all part health %
- Use repair items (brake_pads, engine_oil, etc.) near vehicles

**Commands:**
- `/mechtab` - Open mechanic tablet (mechanics only)
- `/scanveh` - Quick vehicle scan
- `/savedamage` - Manually save vehicle damage (debug)

**Diagnostics:**
- Oil, brakes, suspension, battery, spark plugs, etc.
- Real-time wear based on driving (speed, terrain, braking)
- Persistent across garage storage

**Service Book:**
- Use `service_book` item to view/create vehicle service history
- Automatic locking: Once a service entry is added, the service book locks to that vehicle's plate
- Locked service books can only be used on their assigned vehicle
- Create multiple service books for different vehicles
- Service history is stored per vehicle plate in the database

### For Admins

**Debug Commands:**
- `/damagepart <part> <0-100>` - Set part damage
- `/damageadd <part> <delta>` - Add damage to part
- `/damageall <0-100>` - Set all parts to value
- `/damagereset` - Reset all damage to 0%
- `/diagrow <plate>` - Show database diagnostics row

**Shortcuts:**
- `/damageoil 80` - Set oil damage to 80%
- `/damagebrakes 60` - Set brake damage to 60%
- `/damagebattery 40` - Set battery damage to 40%
- (etc. for all parts)

---

## Garage Integration

### QBCore qb-garages (Default)

Works out of the box. Vehicle diagnostics are automatically saved when storing vehicles in garages.

### Codesign cd_garages

1. Set `Config.GarageSystem = 'cd_garages'` in `config.lua`
2. Ensure cd_garages is started before pf-mechanicjob in server.cfg:
   ```cfg
   ensure cd_garages
   ensure pf-mechanicjob
   ```
3. Vehicle diagnostics will automatically sync when:
   - Player enters a vehicle (diagnostics are restored)
   - Player stores a vehicle in garage (diagnostics are saved)
   - Player is driving (synced every 10 seconds)

**How it works:**
- Client monitors vehicle entry and syncs diagnostics from database
- Client detects garage storage attempts and saves current state
- Server caches vehicle state every 10 seconds while driving
- When cd_garages triggers its store event, cached state is written to database

**Note:** cd_garages uses a different event system than qb-garages. The script automatically detects which garage system you're using based on `Config.GarageSystem`.

---

## Troubleshooting

### Damage not saving
1. Check `Config.Debug = true` and watch server console
2. Verify database tables exist (`vehicle_diagnostics`)
3. Ensure garage system is configured correctly
4. Use `/savedamage` command to force save

### Items not working
1. Check items are added to `qb-core/shared/items.lua`
2. Verify item images exist in inventory folder
3. Check server console for errors
4. Ensure player has mechanic job (`/setjob [id] mechanic`)

### Garage not detecting vehicle
1. Verify `Config.GarageSystem` matches your garage resource name
2. Check garage resource is started
3. Try `/savedamage` while in vehicle before storing

### Performance issues
1. Reduce `Config.WearRates` values for less aggressive wear
2. Set `Config.Debug = false` in production
3. Increase damage check interval (5000ms default in damage.lua)

---

## Credits

**Author:** PF Mods  
**Framework:** QBCore  
**Compatible Garages:** qb-garages, cd_garages  
**Version:** 1.0.0  

---

## Support

For issues or feature requests, please contact the script author or create an issue in your project's repository.

---

## License

This script is provided as-is for use with QBCore framework. Modify as needed for your server.

