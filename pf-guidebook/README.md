# pf-guidebook

Dynamic in-game guidebook with admin editing, rich text pages, GPS embeds, and category/page permissions.

Supports:
- QBCore
- ESX
- Standalone (no framework dependency, command-only)

## Framework Support

| Mode | Dependency | Jobs list in admin UI | Useable item support |
|------|------------|------------------------|----------------------|
| `qbcore` | `qb-core` | Yes (from `QBCore.Shared.Jobs`) | Yes |
| `esx` | `es_extended` | Yes (from `ESX.GetJobs()`) | Yes |
| `standalone` | None | No (manual/no framework jobs) | No (command-only) |

## Commands

- `/guidebook` - open guidebook
- `/help` - alias for `/guidebook`
- `/guidebookadmin` - open admin control panel (admin only)
- `/helpadmin` - alias for `/guidebookadmin` (admin only)
- `/sendhelp <playerId> <pageKey(optional)>` - open guidebook for another player (admin only)
- `/pointgps <pointKey>` - set waypoint for a saved guide GPS button key (if accessible)

## Core Features

- In-game guidebook UI with category accordion and search
- Admin category/page CRUD from a gear menu
- Category/page permissions by job and minimum grade
- Rich text editor with headings, fonts, colors, embeds, tables, code blocks, GPS, and emoji
- Category emoji assignment with persisted server-side storage
- GPS button embeds that can set map waypoint

## Rich Text Editor

| Group | Controls |
|-------|----------|
| History | Undo, Redo |
| Block format | Paragraph, Heading 1-4, Blockquote, Preformatted |
| Font | Family, Size |
| Color | Text color, Highlight color |
| Inline | Bold, Italic, Underline, Strikethrough, Subscript, Superscript |
| Alignment | Left, Center, Right, Justify, Bullet list, Numbered list, Outdent, Indent |
| Insert | Link, Unlink, Image, Video, Embed (iframe), Table, Horizontal rule, Code block, Emoji, GPS button |
| Clear | Remove formatting |

### Emoji Insertion

1. Place the cursor in page content.
2. Click the Emoji toolbar button.
3. Search/filter emojis.
4. Use arrow keys to move in the grid, Enter to select, Escape to cancel.

### GPS Buttons

1. Click `GPS` in toolbar.
2. Enter label, X, and Y.
3. The editor inserts a clickable GPS button.
4. Players can click it or use `/pointgps <pointKey>`.

## Installation

### 1. Copy Resource

Put `pf-guidebook` in your resources folder, e.g.:

```txt
resources/
  [pfscripts]/
    pf-guidebook/
```

### 2. Configure Framework Mode

Open `config.lua` and set:

```lua
-- auto | qbcore | esx | standalone
Config.Framework = 'auto'
```

Recommended values:
- QBCore server: `Config.Framework = 'qbcore'`
- ESX server: `Config.Framework = 'esx'`
- No framework server: `Config.Framework = 'standalone'`

### 3. server.cfg Start Order

Add this resource to `server.cfg`.

QBCore:
```cfg
ensure pfm-core
ensure pf-guidebook
```

ESX:
```cfg
ensure es_extended
ensure pf-guidebook
```

Standalone:
```cfg
ensure pf-guidebook
```

### 4. Item Setup (Framework modes only)

Useable items are supported only in QBCore/ESX mode. Standalone is command-only.

If you want command-only in any framework, set:

```lua
Config.EnableUseableItem = false
```

#### QBCore item

Add to `qb-core/shared/items.lua` (if item usage enabled):

```lua
['guidebook'] = { name = 'guidebook', label = 'Guidebook', weight = 100, type = 'item', image = 'guidebook.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'City guidebook' },
```

#### ESX item

Add a `guidebook` item in your ESX inventory/item system if you want item usage. Exact file depends on your ESX inventory resource.

### 5. Start Resource

```cfg
restart pf-guidebook
```

On first start, `guidebook_data.json` is created from `Config.DefaultData`.

## Standalone Notes

For pure standalone mode (no dependencies, no item), use:

```lua
Config.Framework = 'standalone'
Config.EnableUseableItem = false
```

Then open with commands only:
- `/guidebook`
- `/help`

## Admin Access

Admin checks are layered in this order:

1. `Config.AdminIdentifiers`
2. `Config.AdminAcePermissions` (via `IsPlayerAceAllowed`)
3. Framework-specific admin checks

### QBCore

Uses `Config.AdminPermissions` with `QBCore.Functions.HasPermission`.

```lua
Config.AdminPermissions = {
    'god',
    'admin'
}
```

### ESX

Uses `Config.AdminGroups` from player group.

```lua
Config.AdminGroups = {
    'admin',
    'superadmin'
}
```

### Standalone

Uses ace/identifier lists only.

```lua
Config.AdminAcePermissions = {
    'guidebook.admin'
}

Config.AdminIdentifiers = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
}
```

Example ace grant:

```cfg
add_ace group.admin guidebook.admin allow
add_principal identifier.license:YOUR_LICENSE_HERE group.admin
```

## Config Reference

Key options in `config.lua`:

- `Config.Framework`
- `Config.ItemName`
- `Config.EnableUseableItem`
- `Config.DataFile`
- `Config.CallbackTimeoutMs`
- `Config.AdminPermissions` (QBCore)
- `Config.AdminGroups` (ESX)
- `Config.AdminAcePermissions` (all/standalone)
- `Config.AdminIdentifiers` (all/standalone)
- `Config.Commands`
- `Config.DefaultData`

## Data Storage

- File: `guidebook_data.json`
- Location: resource root (`pf-guidebook` folder)
- Persistence: saved via `SaveResourceFile`

To reset data:
1. `stop pf-guidebook`
2. Delete `guidebook_data.json`
3. `start pf-guidebook`

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| UI does not open | Wrong `Config.Framework` or bad start order | Set correct framework mode and ensure framework starts first |
| Admin panel locked | No matching admin permission/group/ace/identifier | Update admin config values |
| Item not useable | Item not registered, or standalone mode | Register item for framework mode, or use commands |
| No jobs available in admin picker | Standalone mode or framework job table unavailable | Expected in standalone; verify framework job exports otherwise |
| Data not saving | Resource folder/file permission issue | Ensure `guidebook_data.json` is writable |
| Callback timeout | Server callback not responding in time | Check server console errors and increase `Config.CallbackTimeoutMs` |

## Notes

- No world 3D markers/blips are included.
- GPS navigation works through embedded page buttons and `/pointgps`.
