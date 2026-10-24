# Business Manager Integration Guide

## Overview

pf-computer's Business Manager now acts as a **universal dashboard** that displays business data from multiple job scripts. Each job script (like pf-mechanicjob, pf-restaurant, pf-shops) controls its own data, and the computer simply displays it.

## How It Works

### Architecture

```
┌─────────────────┐
│   pf-computer   │ ← Dashboard/Viewer
│ Business Manager│
└────────┬────────┘
         │
         ├── Requests data based on player's job
         │
    ┌────▼─────┬─────────┬─────────┐
    │          │         │         │
┌───▼────┐ ┌──▼───┐ ┌───▼────┐ ┌──▼──────┐
│mechanic│ │burger│ │ police │ │ (more)  │
│  job   │ │shot  │ │database│ │ scripts │
│ script │ │script│ │ script │ │         │
└────────┘ └──────┘ └────────┘ └─────────┘
     └── Each owns and controls its data
```

### Data Flow

1. **Player opens computer** → pf-computer detects their job
2. **Computer requests data** → Checks if job has external provider
3. **If provider exists** → Fetches live data from job script
4. **If no provider** → Falls back to internal pc_data.json (legacy)
5. **Displays data** → Shows in Business Manager UI

## For Job Script Developers

### Adding Integration to Your Resource

#### Step 1: Create Business Data Provider

Create `server/business_data_provider.lua` in your resource:

```lua
local QBCore = exports['pfm-core']:GetCoreObject()

-- Export: Get transactions for business
local function GetBusinessTransactions(business, limit)
    limit = tonumber(limit) or 50
    
    local rows = MySQL.query.await([[
        SELECT 
            transaction_id,
            business,
            items,
            subtotal,
            tax,
            total,
            payment_type,
            created_at
        FROM your_transactions_table
        WHERE business = ?
        ORDER BY created_at DESC
        LIMIT ?
    ]], { business, limit }) or {}
    
    -- Parse items JSON if needed
    for _, tx in ipairs(rows) do
        if tx.items and type(tx.items) == 'string' then
            tx.items = json.decode(tx.items) or {}
        end
    end
    
    return rows
end

-- Export: Get analytics/statistics
local function GetBusinessAnalytics(business)
    -- Get today, week, month, all-time stats
    -- Return structured data
    return {
        today = { sales = 0, revenue = 0, transactions = 0 },
        week = { sales = 0, revenue = 0, transactions = 0 },
        month = { sales = 0, revenue = 0, transactions = 0 },
        allTime = { sales = 0, revenue = 0, transactions = 0 }
    }
end

-- Export: Get employees
local function GetBusinessEmployees(business)
    local employees = {}
    -- Fetch from database or QBCore
    return employees
end

-- Export: Get business configuration
local function GetBusinessConfig(business, source)
    return {
        businessId = business,
        businessName = 'My Business',
        businessType = 'mechanic',
        blipColor = 5,
        taxRate = 0.05,
        currency = '$'
    }
end

-- Export: Get inventory
local function GetBusinessInventory(business)
    local inventory = {}
    -- Fetch from your inventory system
    return inventory
end

-- Make functions available
exports('GetBusinessTransactions', GetBusinessTransactions)
exports('GetBusinessAnalytics', GetBusinessAnalytics)
exports('GetBusinessEmployees', GetBusinessEmployees)
exports('GetBusinessConfig', GetBusinessConfig)
exports('GetBusinessInventory', GetBusinessInventory)
```

#### Step 2: Add to fxmanifest.lua

```lua
server_scripts {
    'server/business_data_provider.lua'
}

exports {
    'GetBusinessTransactions',
    'GetBusinessAnalytics',
    'GetBusinessEmployees',
    'GetBusinessConfig',
    'GetBusinessInventory'
}
```

#### Step 3: Register with pf-computer

Edit `pf-computer/server.lua` and add your job mapping:

```lua
-- Line ~563 in pf-computer/server.lua
local JobDataProviders = {
    mechanic = 'pf-mechanicjob',
    mechanic2 = 'pf-mechanicjob',
    mechanic3 = 'pf-mechanicjob',
    
    -- Add your jobs here:
    burgershot = 'pf-restaurant',
    uwu = 'pf-restaurant',
    pizzathis = 'pf-restaurant',
    
    police = 'pf-policejob',
    sheriff = 'pf-policejob',
}
```

## Export Function Reference

### GetBusinessTransactions(business, limit)

**Parameters:**
- `business` (string): Job name (e.g., 'mechanic', 'burgershot')
- `limit` (number): Maximum transactions to return

**Returns:** Array of transaction objects:
```lua
{
    { 
        transaction_id = "TX-12345",
        business = "mechanic",
        items = { {item = "repair", qty = 1, price = 500} },
        subtotal = 500,
        tax = 25,
        total = 525,
        payment_type = "cash",
        created_at = "2026-02-22 10:30:00"
    }
}
```

### GetBusinessAnalytics(business)

**Parameters:**
- `business` (string): Job name

**Returns:** Analytics object:
```lua
{
    today = { sales = 10, revenue = 5000, transactions = 10 },
    week = { sales = 50, revenue = 25000, transactions = 50 },
    month = { sales = 200, revenue = 100000, transactions = 200 },
    allTime = { sales = 1000, revenue = 500000, transactions = 1000 },
    topItems = { {label = "Oil Change", count = 50} }
}
```

### GetBusinessEmployees(business)

**Parameters:**
- `business` (string): Job name

**Returns:** Array of employees:
```lua
{
    {
        citizenid = "ABC123",
        name = "John Doe",
        grade = 2,
        gradeName = "Mechanic",
        role = "employee"
    }
}
```

### GetBusinessConfig(business, source)

**Parameters:**
- `business` (string): Job name
- `source` (number): Player server ID

**Returns:** Configuration object:
```lua
{
    businessId = "mechanic",
    businessName = "Los Santos Customs",
    businessType = "mechanic",
    blipColor = 5,
    taxRate = 0.05,
    currency = "$",
    playerGrade = 2,
    playerIsBoss = false
}
```

### GetBusinessInventory(business)

**Parameters:**
- `business` (string): Job name

**Returns:** Array of inventory items:
```lua
{
    {
        item = "engine_oil",
        name = "Engine Oil",
        stock = 45,
        category = "Parts",
        cost = 20
    }
}
```

## Benefits

✅ **Separation of Concerns**: Each job script manages its own data
✅ **No Data Duplication**: Single source of truth per job
✅ **Live Data**: Always shows current database state
✅ **Modular**: Easy to add new job integrations
✅ **Backward Compatible**: Falls back to internal data if no provider
✅ **Scalable**: Works with unlimited job scripts

## Example: pf-mechanicjob Integration

Already integrated! When a mechanic opens the computer:

1. Business Manager detects job = 'mechanic'
2. Looks up provider: `JobDataProviders['mechanic']` = 'pf-mechanicjob'
3. Calls `exports['pf-mechanicjob']:GetBusinessTransactions('mechanic', 50)`
4. Displays real cash register sales in dashboard
5. Shows analytics from actual mechanic transactions

## Troubleshooting

### Data not showing

1. Check F8 console for: `[pf-computer] Using external data from...`
2. Verify resource is started: `ensure pf-mechanicjob`
3. Check exports are declared in fxmanifest.lua
4. Verify job name matches in JobDataProviders map

### Using internal data instead of external

- Check if resource exports the required functions
- Ensure resource is started before pf-computer
- Verify no errors in F8 console

### Adding a new job

1. Create business_data_provider.lua with exports
2. Add to fxmanifest.lua
3. Add job → resource mapping in pf-computer/server.lua
4. Restart both resources

## Future Enhancements

- Real-time data synchronization via events
- Caching layer for performance
- Admin panel to manage job data providers
- Automatic provider detection (no manual mapping needed)

---

**Version**: 1.0.0
**Date**: February 22, 2026
**Compatible with**: QBCore, ESX
