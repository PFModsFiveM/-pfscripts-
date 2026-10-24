# pf-computer Updates - February 22, 2026

## Summary of Changes

This update includes three major improvements to pf-computer:

1. **Fixed Blip Sprites** - Restaurant and mechanic blips now display correctly
2. **Simplified Inventory Display** - Removed quantity controls, shows product and stock only
3. **External Programs System** - Other resources can now register programs (like tablet apps)

---

## 1. Blip Sprite Fixes

### Problem
- Restaurant blips were showing as motorcycles (sprite 226)
- Mechanic blips were showing with wrong icon (sprite 227)

### Solution
Changed blip sprite IDs to correct values:
- **Restaurant**: Changed from sprite 226 → **889** (food/restaurant icon)
- **Mechanic**: Changed from sprite 227 → **446** (wrench/tools icon)

### Files Modified
- `server.lua` lines 1346 and 1348

### Result
✅ Restaurant businesses now show proper food icon on map
✅ Mechanic shops now show proper wrench icon on map

---

## 2. Inventory Display Simplification

### Problem
Inventory section had unnecessary quantity controls (increment/decrement buttons, save button) that weren't needed for just viewing stock levels.

### Solution
Removed all quantity manipulation controls from inventory display. Now shows:
- Product name
- Current stock amount (with color-coded levels)

### Before:
```
Product Name
Current Stock: 45 units
[➖] [45] [➕] [✓ Save]
```

### After:
```
Product Name
Product: Beef Patty
In Stock: 45 units
```

### Files Modified
- `script.js` - `renderInventoryItem()` function (lines 6556-6585)

### Result
✅ Clean, simplified inventory view
✅ Focus on displaying information rather than manipulation
✅ Stock levels still color-coded (green/yellow/red based on quantity)

---

## 3. External Programs System (Like Tablet Apps)

### Overview
Implemented a system that allows **any resource** to add custom programs to pf-computer, similar to how pf-mechanicjob adds apps to pf-tablet. This enables:

- Restaurants to add custom ordering systems
- Mechanics to add work order management
- Police to add database access
- Any job to add job-specific computer programs

### How It Works

#### For Resource Developers:

**Step 1**: Create an export function that returns program definitions
```lua
-- In your resource's client.lua
local function GetComputerPrograms()
    return {
        {
            id = 'my-program',
            label = 'My Program',
            icon = '🎮',
            external = true,
            resource = 'my-resource',
            jobRestricted = true,
            allowedJobs = {'mechanic', 'police'}
        }
    }
end

exports('GetComputerPrograms', GetComputerPrograms)
```

**Step 2**: Handle program launch
```lua
RegisterNUICallback('program:my-program:open', function(data, cb)
    -- Open your custom interface
    TriggerEvent('my-resource:openInterface')
    cb({ ok = true })
end)
```

**Step 3**: Add export to fxmanifest.lua
```lua
exports {
    'GetComputerPrograms'
}
```

### Detection & Loading Process

1. **On Computer Startup**: pf-computer scans all running resources
2. **Export Discovery**: Calls `GetComputerPrograms()` on each resource
3. **Job Filtering**: Checks player's job against `allowedJobs` (if restricted)
4. **Desktop Icons**: Creates icons for available programs
5. **Launch Handling**: Routes clicks to the source resource via NUI callbacks

### Program Object Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `id` | string | ✅ | Unique program identifier |
| `label` | string | ✅ | Display name on desktop |
| `icon` | string | ✅ | Emoji or FontAwesome class |
| `external` | boolean | ✅ | Must be `true` |
| `resource` | string | ✅ | Resource providing the program |
| `jobRestricted` | boolean | ❌ | Enable job filtering |
| `allowedJobs` | table | ❌ | Array of allowed job names |
| `description` | string | ❌ | Optional description |

### Example Implementation: pf-mechanicjob

Created example file showing how mechanic shops can add computer programs:

**File**: `pf-mechanicjob/client/computer_programs.lua`

Programs added:
- 🔧 **Work Orders** - View and manage work orders
- 📦 **Parts Catalog** - Browse parts and pricing  
- 🔍 **Diagnostic Logs** - View vehicle diagnostics

Job restricted to: `mechanic`, `mechanic2`, `mechanic3`, `bennys`, `beeker`

### Files Modified/Created

**pf-computer:**
- `client.lua` - Added `GetExternalPrograms()` function and NUI callback
- `script.js` - Added `loadExternalPrograms()` function
- `EXTERNAL_PROGRAMS_GUIDE.md` - Complete developer documentation

**pf-mechanicjob:**
- `client/computer_programs.lua` - Example implementation (NEW)
- `fxmanifest.lua` - Added client script and export declaration

### Benefits

✅ **Modular**: Programs live in their own resources
✅ **Job-Aware**: Automatic job filtering
✅ **No Conflicts**: Each resource manages its own programs
✅ **Easy Integration**: Just export a function, no core edits
✅ **Consistent UX**: Programs appear alongside built-in apps

---

## Testing Checklist

### Blip Sprites
- [ ] Create a restaurant business
- [ ] Set blip location from computer
- [ ] Verify blip shows food icon (not motorcycle)
- [ ] Create a mechanic business  
- [ ] Set blip location
- [ ] Verify blip shows wrench icon

### Inventory Display
- [ ] Open computer as restaurant owner
- [ ] Navigate to Inventory section
- [ ] Verify no increment/decrement buttons
- [ ] Verify displays product name and stock only
- [ ] Check stock levels are color-coded

### External Programs
- [ ] Start pf-mechanicjob
- [ ] Open computer as mechanic
- [ ] Verify 3 new icons on desktop (Work Orders, Parts Catalog, Diagnostic Logs)
- [ ] Click each icon to verify they trigger callbacks
- [ ] Open computer as non-mechanic
- [ ] Verify mechanic programs don't appear

---

## Developer Documentation

Full developer guide created at: `EXTERNAL_PROGRAMS_GUIDE.md`

Includes:
- Complete setup instructions
- Code examples for different use cases
- Job restriction examples
- Communication between programs
- Troubleshooting guide
- Best practices

---

## Migration Notes

### For Server Owners
No migration needed. Changes are backward compatible.

### For Script Developers
If you want to add programs to pf-computer:
1. Read `EXTERNAL_PROGRAMS_GUIDE.md`
2. Create export function in your resource
3. Handle NUI callbacks
4. Test with different job permissions

---

## Code Changes Summary

### server.lua
```lua
-- Line 1346 (before)
blipIcon = 226  -- Restaurant/food icon

-- Line 1346 (after)  
blipIcon = 889  -- Restaurant/food icon

-- Line 1348 (before)
blipIcon = 227  -- Wrench icon

-- Line 1348 (after)
blipIcon = 446  -- Wrench icon
```

### client.lua
```lua
-- Added function to collect external programs (lines ~95-120)
local function GetExternalPrograms()
    -- Scans all resources for GetComputerPrograms export
    -- Returns combined array of all programs
end

-- Added NUI callback (line ~122)
RegisterNUICallback('pc:getExternalPrograms', function(_, cb)
    local programs = GetExternalPrograms()
    cb({ ok = true, data = programs })
end)
```

### script.js
```javascript
// Added external program loader (lines ~8718-8790)
async function loadExternalPrograms() {
    // Fetches programs from Lua
    // Filters by job restrictions
    // Creates desktop icons
    // Registers click handlers
}

// Called during initialization (line ~8795)
loadExternalPrograms();

// Simplified inventory display (lines 6556-6585)
renderInventoryItem(item) {
    // Removed: quantity controls
    // Kept: product name, stock display
}
```

---

## Future Enhancements

Potential improvements for future updates:

1. **Program Categories**: Group programs by type (Business, Tools, Entertainment)
2. **Program Permissions**: More granular permissions beyond just job
3. **Inter-Program Communication**: Built-in event system for programs to communicate
4. **Program Settings**: Allow programs to save preferences
5. **Dark Mode Icons**: Support for theme-aware icons
6. **Program Updates**: Notify when external programs are added/removed dynamically

---

## Support & Issues

If you encounter issues:

1. Check F8 console for errors
2. Verify resource is started before pf-computer
3. Confirm export function is properly declared
4. Check job names match exactly (case-sensitive)
5. Review `EXTERNAL_PROGRAMS_GUIDE.md` for examples

---

## Credits

- **Blip Sprites**: Fixed based on GTA V native sprite IDs
- **External Programs**: Inspired by pf-tablet app system
- **Inventory Simplification**: User feedback-driven improvement

---

**Version**: 1.1.0  
**Date**: February 22, 2026  
**Compatibility**: QBCore, ESX
