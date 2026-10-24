# Integration Complete: pf-computer ↔ Job Scripts

## What Changed

pf-computer's Business Manager is now a **universal dashboard** that displays data from external job scripts. Each job controls its own data.

## How It Works Now

### Before (Old System):
- pf-computer stored all data in `pc_data.json`
- Each transaction had to be manually added to pf-computer
- Mechanic sales were isolated to mechanic script
- Data was duplicated across systems

### After (New System):
```
Player with mechanic job opens computer
    ↓
Computer detects job = 'mechanic'
    ↓
Checks for external provider: pf-mechanicjob
    ↓
Fetches transactions from pf_pos_transactions table
    ↓
Displays LIVE data in Business Manager
```

## What This Means

✅ **Mechanic shops**: Cash register sales now appear in computer automatically
✅ **Restaurants** (future): Can add pf-restaurant exports, works instantly
✅ **Any job**: Just export 5 functions, add job mapping, done
✅ **No data loss**: Falls back to internal data if no provider
✅ **Live data**: Always shows current state from job's database

## Files Modified

### pf-mechanicjob:
- **Created**: `server/business_data_provider.lua` (exports for pf-computer)
- **Modified**: `fxmanifest.lua` (added server script + exports)

### pf-computer:
- **Modified**: `server.lua` (external provider detection + integration)
- **Created**: `BUSINESS_INTEGRATION.md` (developer guide)

## Testing

1. **Start both resources**:
   ```
   ensure pf-mechanicjob
   ensure pf-computer
   ```

2. **Check F8 console** for:
   ```
   [pf-computer] Business Manager Integration System Loaded
   [pf-computer] Checking for external data providers...
     ✓ mechanic → pf-mechanicjob
     ✓ mechanic2 → pf-mechanicjob
     ✓ mechanic3 → pf-mechanicjob
   [pf-computer] Found 3 external data provider(s)
   ```

3. **Test as mechanic**:
   - Charge a customer at cash register
   - Open computer → Business Manager
   - See the sale in Statistics and Transactions

4. **Test as non-mechanic** (e.g., police):
   - Open computer → Business Manager
   - Falls back to internal pc_data.json
   - No changes to existing behavior

## What Data Is Shared

From pf-mechanicjob to pf-computer:

| Data Type | Source | What Shows |
|-----------|--------|-----------|
| **Transactions** | `pf_pos_transactions` | All cash register sales |
| **Analytics** | Calculated from transactions | Today/week/month revenue, top items |
| **Employees** | QBCore job system | All mechanics with grades |
| **Config** | Database + Config.lua | Business name, colors, tax rate |
| **Inventory** | `pf_parts_stock` | Parts inventory levels |

## Adding More Jobs

To integrate pf-restaurant, pf-shop, etc:

1. **Copy** `pf-mechanicjob/server/business_data_provider.lua` to your resource
2. **Modify** SQL queries to match your tables
3. **Add exports** to fxmanifest.lua
4. **Map job** in `pf-computer/server.lua`:
   ```lua
   local JobDataProviders = {
       mechanic = 'pf-mechanicjob',
       burgershot = 'pf-restaurant',  -- Add this
       uwu = 'pf-restaurant',         -- Add this
   }
   ```
5. **Restart** and test

See `BUSINESS_INTEGRATION.md` for complete guide.

## Backward Compatibility

✅ Jobs without providers still work (uses pc_data.json)
✅ Existing computer features unchanged
✅ No breaking changes
✅ Can add providers incrementally

## Benefits

1. **Single Source of Truth**: Job script owns its data
2. **No Duplication**: One database, multiple viewers
3. **Real-Time**: Always shows current state
4. **Modular**: Easy to add new integrations
5. **Scalable**: Works with unlimited job types

## Example Output

**Mechanic opens computer:**
```
[F8 Console]
[pf-computer] Using external data from pf-mechanicjob for mechanic (transactions)
[pf-computer] Using external data from pf-mechanicjob for mechanic (analytics)

[Business Manager Display]
Today's Revenue: $5,250 (from actual cash register sales)
Total Transactions: 12 (from pf_pos_transactions table)
Top Service: Oil Change (from transaction items)
```

**Police opens computer:**
```
[F8 Console]
(no external provider for police)

[Business Manager Display]
(uses internal pc_data.json - existing behavior)
```

## Safety

- ✅ All external calls wrapped in pcall()
- ✅ Falls back gracefully if provider fails
- ✅ Won't break if job resource stops
- ✅ Validates data before displaying
- ✅ No SQL injection risk (parameterized queries)

## Next Steps

If you want to add more jobs:
1. Read `BUSINESS_INTEGRATION.md`
2. Copy the business_data_provider.lua template
3. Adjust for your database tables
4. Add job mapping
5. Test

---

**Status**: ✅ Complete and tested
**Compatibility**: QBCore (ESX support exists but untested)
**Version**: 1.0.0
