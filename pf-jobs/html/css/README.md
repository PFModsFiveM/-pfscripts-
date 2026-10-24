# Modular CSS Structure for pf-jobs

This directory contains modular CSS files organized by job type for better maintainability.

## File Organization

### Core Styling
- **core.css** - Shared/core styles for the tablet UI framework, scoreboard, and universal components

### Job-Specific Styling
- **gruppe6.css** - Gruppe6 contractor job styling (cyan/blue theme)
- **business.css** - Business app listing and status display styling
- **garbage.css** - Garbage collection job styling
- **taxi.css** - Taxi service job styling (yellow/gold theme)
- **bus.css** - Bus driver job styling (placeholder for future expansion)

## Benefits of Modular Structure

1. **Separation of Concerns** - Each job's styles are isolated and independent
2. **Easier Maintenance** - Changes to one job don't affect others
3. **Better Performance** - Smaller CSS files can be cached individually
4. **Scalability** - New jobs can easily add their own CSS file
5. **Code Reusability** - Common patterns are in core.css

## Adding a New Job

1. Create a new CSS file: `css/newjob.css`
2. Add job-specific styles (use `.newjob-` class prefix)
3. Link it in `index.html`: `<link rel="stylesheet" href="css/newjob.css">`
4. Update the JavaScript module to match the class names

## CSS Naming Conventions

- **Gruppe6** - `.g6-*` classes (e.g., `.g6-container`, `.g6-button`)
- **Business** - `.business-*` classes (e.g., `.business-card`, `.business-header`)
- **Garbage** - `.garbage-*` classes
- **Taxi** - `.taxi-*` classes
- **Bus** - `.bus-*` classes (when implemented)
- **Core** - `.tablet-*`, `.app-window`, `.scoreboard-*` classes

## Note on OLD style.css

The original `style.css` file (1918 lines) has been split across the modular files above.
You can safely remove the old `style.css` file once all styles have been migrated.

Old path: `pf-jobs/html/style.css` → DEPRECATED, use modular CSS files instead
