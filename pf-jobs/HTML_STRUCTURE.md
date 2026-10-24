# pf-jobs HTML Module Structure

This document describes the HTML/JavaScript organization for the pf-jobs tablet UI.

## Directory Structure

```
html/
├── index.html              (Main entry point - loads all modules)
├── script.js              (Core NUI bridge and framework)
├── css/                   (Modular stylesheets)
│   ├── core.css           (Shared styles)
│   ├── gruppe6.css        (Gruppe6 styles)
│   ├── business.css       (Business app styles)
│   ├── garbage.css        (Garbage job styles)
│   ├── taxi.css           (Taxi job styles)
│   ├── bus.css            (Bus job styles)
│   └── README.md          (CSS documentation)
├── tablet_module.js       (Gruppe6 & Garbage rendering)
├── taxi_module.js         (Taxi job UI logic)
├── bus_module.js          (Bus job UI logic)
├── business.js            (Job listing and status)
├── scoreboard.js          (Scoreboard management)
├── script.js              (Framework and utilities)
├── gruppe6.html           (Gruppe6 app markup - unused, JS-rendered)
├── garbage.html           (Garbage app markup)
├── taxi.html              (Taxi app markup)
└── bus.html               (Bus app markup)
```

## Module Files

### Core Files

**index.html**
- Main HTML document
- Loads core.css and all job CSS files
- Loads all JavaScript modules
- Contains base HTML structure for tablet UI

**script.js**
- PostMessage NUI bridge
- Core keyboard handling
- Window management
- App switching logic

**scoreboard.js**
- Scoreboard display management
- Progress bar animations
- Title/subtitle updates

### Job Modules

Each job has a dedicated module file that handles rendering and interaction:

**tablet_module.js**
- `renderGruppe6Window(appName)` - Draws Gruppe6 UI
- `renderGarbageWindow(appName)` - Draws Garbage UI
- Exports: `window.PFJobsTablet.renderGruppe6Window`, `.renderGarbageWindow`

**taxi_module.js**
- `renderTaxiWindow(appName)` - Draws Taxi UI
- `switchTaxiTab(tabName)` - Tab navigation
- `startTaxiRide()`, `endTaxiRide()`, `cancelTaxiRide()`
- Exports: `window.PFJobsTablet.renderTaxiWindow`

**bus_module.js**
- Bus job UI rendering
- Route management
- Drop-off/pickup handling

**business.js**
- Job listing grid
- Status indicators
- Online player counts

### Supporting Files

**gruppe6.html**
- Legacy HTML (Gruppe6 markup - now rendered via tablet_module.js)
- Can be removed

**taxi.html**
- Taxi UI markup reference
- Used as template for rendering

**bus.html, garbage.html**
- Job-specific markup templates

## Module Export Pattern

All job modules export their render function to the global window scope:

```javascript
// At the end of each module:
window.PFJobsTablet = window.PFJobsTablet || {};
window.PFJobsTablet.renderJobWindow = renderJobWindow;
```

Then script.js calls them:

```javascript
if (window.PFJobsTablet && window.PFJobsTablet.renderJobWindow) {
    window.PFJobsTablet.renderJobWindow(appName);
}
```

## Adding a New Job Module

### Step 1: Create Module File
```javascript
// html/newjob_module.js
function renderNewJobWindow(appName) {
    const $content = $(`.app-window[data-app="${appName}"] .window-content`);
    if (!$content.length) return;
    
    $content.html(`
        <!-- Job UI HTML here -->
    `);
    
    // Bind event handlers
    bindNewJobHandlers();
}

window.PFJobsTablet = window.PFJobsTablet || {};
window.PFJobsTablet.renderNewJobWindow = renderNewJobWindow;
```

### Step 2: Create CSS File
```css
/* html/css/newjob.css */
.newjob-container {
    /* Styles here */
}
```

### Step 3: Link Files in index.html
```html
<link rel="stylesheet" href="css/newjob.css">
<script src="newjob_module.js"></script>
```

### Step 4: Update script.js
Register the new job in the app loader

## File Sizes Comparison

| File | Type | Purpose |
|------|------|---------|
| core.css | CSS | Shared UI framework (~500 lines) |
| gruppe6.css | CSS | Gruppe6 styling (~600 lines) |
| business.css | CSS | Business app styling (~400 lines) |
| garbage.css | CSS | Garbage styling (~20 lines) |
| taxi.css | CSS | Taxi styling (~30 lines) |
| tablet_module.js | JS | Gruppe6 & Garbage (~700 lines) |
| taxi_module.js | JS | Taxi module (~210 lines) |
| business.js | JS | Business app (~TBD lines) |
| script.js | JS | Framework & core (~TBD lines) |

## Benefits of This Structure

1. **Clear Separation** - Each job's UI is isolated
2. **Lazy Loading** - Jobs only load their CSS when needed
3. **Easy Debugging** - Can test individual modules independently
4. **Maintenance** - Changes to one job don't affect others
5. **Scalability** - New jobs follow the same pattern
6. **Performance** - Modular CSS can be cached separately

## NUI Communication

All modules communicate with Lua via PostMessage:

```javascript
// From JS to Lua (client event)
$.post(`https://${GetParentResourceName()}/eventName`, JSON.stringify(data), cb);

// From Lua to JS (NUI message)
window.addEventListener('message', function(e) {
    const data = e.data || {};
    if (data.action === 'jobAction') {
        // Handle message
    }
});
```

## Migration Notes

- Old `style.css` (1918 lines) has been split into modular files
- Eliminate the monolithic CSS file for better maintainability
- Each module now has its own CSS file in `/css` directory
- index.html now links all required CSS files
