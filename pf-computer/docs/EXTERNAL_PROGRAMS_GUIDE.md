# External Programs Guide for pf-computer

This guide explains how to create external programs that integrate with pf-computer, similar to how pf-mechanicjob integrates apps with pf-tablet.

## Overview

External resources can register custom programs that appear in the pf-computer interface. The computer will automatically detect and load programs from any resource that exports the `GetComputerPrograms` function.

## Creating an External Program

### Step 1: Create the Export Function

In your resource's `client.lua` or `fxmanifest.lua`, create an export that returns a table of programs:

```lua
-- client.lua (or similar client-side file)

local function GetComputerPrograms()
    return {
        {
            id = 'my-custom-app',
            label = 'My Custom App',
            icon = '🎮',  -- Can be emoji or FontAwesome class like 'fas fa-gamepad'
            external = true,
            resource = GetCurrentResourceName(),
            jobRestricted = false,  -- Optional: restrict to specific jobs
            allowedJobs = {}        -- Optional: array of job names if jobRestricted = true
        }
    }
end

exports('GetComputerPrograms', GetComputerPrograms)
```

### Step 2: Program Object Properties

Each program object supports the following properties:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `id` | string | ✅ | Unique identifier for the program |
| `label` | string | ✅ | Display name shown in the computer |
| `icon` | string | ✅ | Icon (emoji or FontAwesome class) |
| `external` | boolean | ✅ | Must be `true` for external programs |
| `resource` | string | ✅ | Name of the resource providing the program |
| `jobRestricted` | boolean | ❌ | If true, only shows for specific jobs |
| `allowedJobs` | table | ❌ | Array of job names (if jobRestricted = true) |
| `description` | string | ❌ | Optional description of the program |

### Step 3: Handle Program Launch Events

When a user clicks your program, pf-computer will trigger a NUI callback. Handle it in your resource:

```lua
-- In your resource's client.lua

RegisterNUICallback('program:my-custom-app:open', function(data, cb)
    -- Your program logic here
    -- Open a custom NUI interface, trigger events, etc.
    
    cb({ ok = true })
end)

-- Or listen for a specific event
RegisterNetEvent('pf-computer:program:opened', function(programId)
    if programId == 'my-custom-app' then
        -- Handle program opening
        -- Open your custom NUI, etc.
    end
end)
```

## Example: Restaurant Management Program

Here's a complete example of a restaurant management program:

```lua
-- your-restaurant-resource/client.lua

local function GetComputerPrograms()
    return {
        {
            id = 'restaurant-manager',
            label = 'Restaurant Manager',
            icon = '🍽️',
            external = true,
            resource = 'your-restaurant-resource',
            jobRestricted = true,
            allowedJobs = {'burgershot', 'pizzathis', 'uwu'},
            description = 'Manage restaurant orders and inventory'
        },
        {
            id = 'recipe-book',
            label = 'Recipe Book',
            icon = '📖',
            external = true,
            resource = 'your-restaurant-resource',
            jobRestricted = true,
            allowedJobs = {'burgershot', 'pizzathis', 'uwu'},
            description = 'View and create recipes'
        }
    }
end

exports('GetComputerPrograms', GetComputerPrograms)

-- Handle program launches
RegisterNUICallback('program:restaurant-manager:open', function(data, cb)
    -- Open your restaurant manager NUI
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'openRestaurantManager',
        data = data
    })
    cb({ ok = true })
end)

RegisterNUICallback('program:recipe-book:open', function(data, cb)
    -- Open recipe book NUI
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'openRecipeBook'
    })
    cb({ ok = true })
end)
```

## Example: Mechanic Work Orders (Based on pf-mechanicjob)

```lua
-- pf-mechanicjob/client/computer_programs.lua

local function GetComputerPrograms()
    return {
        {
            id = 'work-orders',
            label = 'Work Orders',
            icon = '🔧',
            external = true,
            resource = 'pf-mechanicjob',
            jobRestricted = true,
            allowedJobs = {'mechanic', 'mechanic2', 'bennys'}
        },
        {
            id = 'parts-catalog',
            label = 'Parts Catalog',
            icon = '📦',
            external = true,
            resource = 'pf-mechanicjob',
            jobRestricted = true,
            allowedJobs = {'mechanic', 'mechanic2', 'bennys'}
        },
        {
            id = 'diagnostic-logs',
            label = 'Diagnostic Logs',
            icon = '🔍',
            external = true,
            resource = 'pf-mechanicjob',
            jobRestricted = true,
            allowedJobs = {'mechanic', 'mechanic2', 'bennys'}
        }
    }
end

exports('GetComputerPrograms', GetComputerPrograms)
```

## How It Works

1. **Detection**: When pf-computer loads, it scans all started resources
2. **Collection**: It calls `GetComputerPrograms()` export on each resource
3. **Registration**: Valid programs are added to the computer's program list
4. **Display**: Programs appear in the computer interface
5. **Launch**: Clicking a program triggers callbacks in your resource

## Job Restrictions

To restrict programs to specific jobs:

```lua
{
    id = 'police-database',
    label = 'Police Database',
    icon = '👮',
    external = true,
    resource = 'your-police-resource',
    jobRestricted = true,
    allowedJobs = {'police', 'sheriff', 'state'}  -- Only these jobs can see it
}
```

## Testing Your Program

1. Ensure your resource is started **before** or **at the same time** as pf-computer
2. Open a computer in-game
3. Your program should appear in the programs list
4. Click it to verify the callback is triggered
5. Check F8 console for any errors

## Troubleshooting

**Program not appearing:**
- Check that `GetComputerPrograms` is properly exported
- Verify your resource is started
- Ensure the returned table structure is correct
- Check F8 console for errors

**Program appears but doesn't work:**
- Verify you're handling the NUI callback or event
- Check that the program `id` matches your callback name
- Look for errors in F8 console

**Job restriction not working:**
- Ensure `jobRestricted = true` is set
- Verify `allowedJobs` contains correct job names (case-sensitive)
- Check that the player's job is in the allowed list

## Best Practices

1. **Unique IDs**: Use resource name as prefix (e.g., `myresource-program-name`)
2. **Clear Icons**: Use recognizable emoji or FontAwesome icons
3. **Error Handling**: Always wrap your code in pcall() for safety
4. **Documentation**: Document your programs for server admins
5. **Performance**: Don't run heavy code when programs load, only when opened

## Advanced: Communication Between Programs

Programs from different resources can communicate via events:

```lua
-- Resource A sends data
TriggerEvent('computer:program:data', {
    from = 'program-a',
    to = 'program-b',
    data = { message = 'Hello from A!' }
})

-- Resource B listens
RegisterNetEvent('computer:program:data', function(payload)
    if payload.to == 'program-b' then
        print('Received:', payload.data.message)
    end
end)
```

## Complete fxmanifest.lua Example

```lua
fx_version 'cerulean'
game 'gta5'

author 'Your Name'
description 'Custom Computer Programs'
version '1.0.0'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

-- Export must be declared
export 'GetComputerPrograms'
```

---

## Summary

Creating external programs for pf-computer is straightforward:

1. Create `GetComputerPrograms()` function returning a table of programs
2. Export it: `exports('GetComputerPrograms', GetComputerPrograms)`
3. Handle program launch via NUI callbacks or events
4. Test and deploy!

Your programs will automatically integrate with pf-computer, appearing alongside built-in programs like email, calendar, and business manager.
