# Modular Lua Structure for pf-jobs

This document describes the recommended Lua file organization by job type.

## Current Structure

```
pf-jobs/
├── client/
│   ├── main.lua           (Core initialization)
│   ├── garbage.lua         (Garbage job client logic)
│   ├── gruppe6.lua         (Gruppe6 job client logic)
│   ├── taxi.lua            (Taxi job client logic)
│   ├── bus.lua             (Bus job client logic)
│   └── scoreboard.lua      (Shared scoreboard management)
├── server/
│   ├── main.lua            (Core initialization)
│   ├── gruppe6.lua         (Gruppe6 contract management, pickups, deposits)
│   └── apps/
│       ├── garbage.lua     (Garbage server logic)
│       ├── taxi.lua        (Taxi server logic)
│       ├── bus.lua         (Bus server logic)
│       ├── business.lua    (Job listing and status)
│       └── apps.lua        (App framework)
```

## File Responsibilities

### Client Files

**main.lua**
- NUI callback registration
- Player name updates
- Business app callbacks
- Cleanup on resource stop

**garbage.lua**
- Garbage job initiation
- Trash collection mechanics
- Trashmaster vehicle management
- Group management for garbage collection

**gruppe6.lua**
- Contract browsing and acceptance
- Vehicle spawning for contracts
- Pickup and delivery logic
- Group creation and management
- Invite system handling

**taxi.lua**
- Taxi ride initiation
- Route updates and GPS
- Fare calculation
- Ratings management

**bus.lua**
- Bus route management
- Passenger boarding/exiting
- Route completion
- Earnings tracking

**scoreboard.lua**
- Job progress display
- Scoreboard show/hide
- Progress bar updates
- Title and subtitle management

### Server Files

**main.lua**
- QBCore Bridge
- Player data initialization
- Global event handlers
- Server-side logging

**apps/business.lua**
- Job online player counts
- Job listing status
- Business app data

**apps/garbage.lua**
- Trash bag creation/removal
- Trashmaster spawning
- Payment processing
- XP/level system

**apps/gruppe6.lua**
- Contract generation
- Delivery verification
- Group profit splitting
- Vehicle registration

**apps/taxi.lua**
- Ride generation
- Route validation
- Fare calculation
- Rating system

**apps/bus.lua**
- Route definition
- Stop management
- Completion rewards

## Adding a New Job

### Step 1: Create Lua Files
```
pf-jobs/client/newjob.lua
pf-jobs/server/apps/newjob.lua
```

### Step 2: Structure Template

**client/newjob.lua**
```lua
local QBCore = exports['pfm-core']:GetCoreObject()

-- Job state
local jobActive = false

-- Initialize job system
RegisterNetEvent('pf-jobs:client:openNewJobApp', function()
    -- Handle app opening
end)

-- Receive state updates from server
window.addEventListener('message', function(event)
    if event.data.action == 'newjob:init' then
        -- Handle init
    end
end)
```

**server/apps/newjob.lua**
```lua
local QBCore = exports['pfm-core']:GetCoreObject()

-- Callbacks for client initialization
QBCore.Functions.CreateCallback('pf-jobs:newjob:getInit', function(source, cb)
    -- Return job state
    cb({ status = 'ready' })
end)

-- Event handlers for job actions
RegisterNetEvent('pf-jobs:newjob:startJob', function()
    -- Handle job start
end)
```

### Step 3: Register HTML Module
Add corresponding HTML/JavaScript module and link in index.html

### Step 4: Link in Client/Server Main
Import the new job file in respective main.lua files (or auto-load via manifest)

## Best Practices

1. **Use job prefixes** - All events use `pf-jobs:newjob:*` format
2. **Modular functions** - Keep each job's logic self-contained
3. **Shared utilities** - Common functions go in main.lua
4. **Event naming** - Use consistent naming: `action:subject:verb`
5. **Documentation** - Comment complex logic and event flows
6. **Testing** - Test job logic independently before integration

## Current Jobs

- ✅ **Garbage** - Trash collection and delivery
- ✅ **Gruppe6** - Contractor job with vehicle heists
- ✅ **Taxi** - Ride sharing service
- ✅ **Bus** - Route-based passenger transport
- ✅ **Business** - Job listing and status display

## Planned Jobs

- 🔲 Mining
- 🔲 Fishing
- 🔲 Cooking
- 🔲 Crafting
