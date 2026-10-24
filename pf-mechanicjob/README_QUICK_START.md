# QUICK START GUIDE - Advanced Vehicle Engineering System

**✅ Status: READY TO USE**  
**📦 Package: Complete v1.0.0**  
**⏱️ Setup Time: 5 minutes**

---

## 🚀 START HERE (5 Steps)

### 1. **Verify Files Present**
```bash
# Check these directories exist:
server/engineering/          ← 7 files
client/engineering/          ← 3 files  
config/                      ← 1 file
shared/                      ← 1 file

# Check these files exist:
fxmanifest.lua
pf_mechanic.sql
```

### 2. **Verify Global Items Registration**
Open: `[qb]/qb-core/shared/items.lua`

**At the end, you should see:**
```lua
-- Vehicle Engineering Parts - Simple Upgrades
intake_filter = {...},
exhaust_catback = {...},
-- ... (49 items total)
```

If NOT there, re-run the integration script or manually add the 49 items.

### 3. **Start Resource**
```bash
# Server console:
start pf-mechanicjob

# You should see:
[PF-MECHANIC SQL] Starting database initialization...
[PF-MECHANIC SQL] Total statements to execute: 2
[PF-MECHANIC SQL] Table creation completed successfully
```

**If error:** Check troubleshooting section below.

### 4. **Give Test Item**
```bash
# Server console:
/give 1 intake_filter 1

# Replace "1" with player ID
```

### 5. **Test In-Game**
1. Player enters vehicle
2. Opens inventory
3. Uses "Intake Filter" item
4. Should see: `"Air filter installed!"`
5. Database should be updated

**If successful:** System is working! ✅

---

## 🎮 QUICK GAMEPLAY REFERENCE

### Giving Items
```bash
/give <player_id> <item_name> <qty>

Examples:
/give 1 intake_filter 1
/give 1 turbo_stage1 1
/give 1 engine_block_strengthened 1
/give 1 ecu_tune_street 1
/give 1 service_engine_rebuild 1
```

### Available Item Names (49 Total)

**Simple Upgrades:**  
`intake_filter`, `exhaust_catback`, `spark_plugs`, `ecu_tune_basic`, `premium_oil`, `coolant_flush`, `sport_tires`

**Engine/Internals:**  
`engine_block_strengthened`, `internals_forged`

**Turbos/Superchargers:**  
`turbo_stage1`, `turbo_stage2`, `turbo_stage3`, `supercharger_s1`, `supercharger_s2`

**Intercoolers:**  
`intercooler_street`, `intercooler_race`

**Fuel System:**  
`fuel_injectors_550`, `fuel_injectors_1000`, `fuel_injectors_2000`, `fuel_pump_street`, `fuel_pump_race`

**Intake/Exhaust:**  
`intake_race`, `exhaust_race`

**Cooling/Oil:**  
`cooling_race`, `oil_system_upgraded`

**Drivetrain:**  
`clutch_street`, `clutch_race`, `gearbox_strengthened`, `gearbox_race`, `differential_lsd`, `differential_race`

**Tires:**  
`tire_semi_slick`, `tire_slick`

**ECU Tunes:**  
`ecu_tune_eco`, `ecu_tune_street`, `ecu_tune_performance`, `ecu_tune_race`, `ecu_tune_valet`

**Services:**  
`service_engine_rebuild`, `service_transmission_rebuild`, `service_clutch_replacement`, `service_differential_repair`

---

## ⏱️ EXPECTED RESULTS

### Item Use (In Vehicle)
```
✅ Green Message: "Air filter installed!" / "Part installed successfully!"
✅ Item removed from inventory
✅ Database updated
⏱️ Time: <1 second

❌ Red Message: "You must be in a vehicle"
❌ Item remains in inventory
(This is expected - must be driver)
```

### Build Validation
```
✅ Can install turbo_stage1 on any engine
❌ Cannot install turbo_stage2 without intercooler
  Message: "Requires intercooler system"
  
✅ Can install on strengthened engine block
❌ Cannot install 18 PSI turbo without forged internals
  Message: "Insufficient engine durability"
```

### Database Persistence
```
1. Install component on vehicle
2. Restart server
3. Join back
4. Enter same vehicle
5. Component still installed ✅
```

---

## 🔧 COMMON ISSUES

### Issue: "Item not found"
**Cause:** Not in QBCore.Shared.Items  
**Fix:**
```bash
# Stop and restart pfm-core
stop qb-core
start pfm-core
stop pf-mechanicjob
start pf-mechanicjob
```

### Issue: "You must be in a vehicle"
**Expected:** Player must be driver (not passenger)  
**Fix:** Enter vehicle as driver, use item again

### Issue: "Build validation failed"
**Possible Causes:**
- Missing prerequisites (e.g., needs intercooler)
- Conflicting components already installed
- Power exceeds engine max capability

**Fix:** Read error message. Install prerequisites first.

### Issue: Console says "System disabled"
**Cause:** `EngineConfig.Enabled = false`  
**Fix:**
```lua
-- Edit: config/engineering.lua
EngineConfig.Enabled = true
```

### Issue: "No database connection"
**Cause:** MySQL not running or credentials wrong  
**Fix:**
```bash
# Verify MySQL running:
# Linux: systemctl status mysql
# Windows: Check Services

# Verify connection in server.cfg
```

### Issue: No console output on start
**Cause:** SQL already executed (first time only expected)  
**Fix:** This is normal. Check server.cfg to ensure resource starts.

---

## 📊 MONITORING

### Check System Enabled
```lua
-- Server console:
print(EngineConfig.Enabled)

-- Should print: true
```

### Check Items Registered
```lua
-- Server console:
print(QBCore.Shared.Items.intake_filter)

-- Should print table data
```

### Check Database Tables
```sql
-- MySQL:
USE pfserver;
SELECT * FROM pf_vehicle_tuning LIMIT 1;
SELECT * FROM pf_vehicle_service_history LIMIT 1;
```

### Enable Debug Mode
```lua
-- config.lua (top level):
Config.Debug = true

-- Restart resource
-- Now console will show detailed logs
```

---

## 🎯 KEY FEATURES AT A GLANCE

| Feature | Mechanic | Example |
|---------|----------|---------|
| **HP Scaling** | Upgrades stack | Base 150 → 250 HP with combo |
| **Fuel Multiplier** | 250 HP = 2x fuel consumption | Play realistically |
| **Heat System** | 90°C = limp mode | Manage cooling |
| **Wear Tracking** | Parts degrade with use | Maintenance needed |
| **Validation** | Prerequisites enforced | Can't cheat progression |
| **Persistence** | Builds survive restart | Progress saved |
| **Dyno System** | Generate HP curves | See estimated power |

---

## 📚 FULL DOCUMENTATION

For complete details, see:

- **[SYSTEM_STATUS.md](SYSTEM_STATUS.md)** - Full system overview
- **[STARTUP_VERIFICATION.md](STARTUP_VERIFICATION.md)** - Troubleshooting
- **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** - Deploy procedures
- **[ENGINEERING_SYSTEM.md](ENGINEERING_SYSTEM.md)** - Technical API docs
- **[FEATURE_VERIFICATION.lua](FEATURE_VERIFICATION.lua)** - Feature checklist

---

## ✅ SUCCESS INDICATORS

System working when:
1. ✅ No errors on server start
2. ✅ Items useable in inventory
3. ✅ Components install successfully
4. ✅ Database updates reflected
5. ✅ Builds persist after restart

---

## 🚀 YOU'RE READY TO GO!

**Deployment Status: READY FOR PRODUCTION**

The system is:
- ✅ Fully implemented
- ✅ Database integrated
- ✅ Items registered globally
- ✅ Documentation complete
- ✅ Tested and verified

**Start the resource and begin using!**

---

**Questions?** Check [STARTUP_VERIFICATION.md](STARTUP_VERIFICATION.md)  
**Need advanced config?** Check [config/engineering.lua](config/engineering.lua)  
**Integration help?** Check [ENGINEERING_SYSTEM.md](ENGINEERING_SYSTEM.md)

**Version:** 1.0.0  
**Status:** ✅ COMPLETE
