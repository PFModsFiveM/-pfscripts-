
# Police MDT - Advanced Mobile Data Terminal for FiveM

An advanced, feature-rich Police MDT (Mobile Data Terminal) resource for FiveM servers. Provides dispatch management, live unit tracking, records management, roster & SOP tools, officer management, and an integrated CCTV system.

## Framework

Set `Config.Framework` in [config.lua](config.lua) to either:

- `qbcore`
- `esx`

# Features

- MDT tablet UI with item/command/keybind open methods
- Tablet prop + animation while MDT is open (configurable)
- Full gameplay input blocking while MDT is open (prevents driving/aiming issues)
- Localization system with built-in languages (configured via `Config.Locale`)

Dispatch & Units

- Dispatch call list with priorities, statuses, map markers and waypoint support
- Live units list (callsign/rank/status/duty) and unit map markers while MDT is open
- Auto dispatch calls from player actions (configured per type: chance/cooldown/code/title/priority)
- Civilian `/911 <description>` calls with keyword classification
	- Supports multiple matches in one description (creates up to 2 calls from one /911)
- Dispatch notification sound (“ding”) on new calls (no MDT/Dispatch UI required)

Map

- Interactive map inside MDT
- Map modes:
	- Tile map from `html/tiles/`
	- Full image map from `html/map/full_map.png`
	- Full image map from `html/map2/full_map.png`
- Affine and homography calibration options for accurate call/unit placement

Records & Casework

- Citizens search/profile
- Vehicles search/profile
- Warrants system (permission-based)
- Incidents and Reports
- Charges list and charge management
- Evidence system with screenshot capture (requires `screenshot-basic`)

Roster, SOP, Officers, FTO

- Roster/callsign system backed by database
- SOP catalog stored in database
- Officer management (employment/flags/discipline tools)
- FTO reports workflow

CCTV

- Auto-discover GTA camera props and persist cameras to database
- CCTV list and recordings in MDT
- Camera damage/offline handling

See `CCTV_SETUP.md` and `CCTV_IMPLEMENTATION.md` for CCTV-specific details.

# Requirements

Required

- FiveM server (Cerulean)
- One framework:
	- QBCore (`qb-core`) OR
	- ESX (`es_extended`)
- `oxmysql` + a MySQL/MariaDB database
- `screenshot-basic` (used by the evidence screenshot feature)

Optional / Compatible (only needed if you enable the integration in `config.lua`)

- Phone: `qb-phone`
- Housing: `qb-houses`, `nolag-properties`
- Garage: `qb-garages`
- Banking/society for fines: `qb-banking`, `tgg-banking`
- Prison: `rcore_prison` (optional; default is built-in)

# Installation

1) Install the resource

1. Place the folder in your resources directory, for example:
	 - `resources/[custom]/pf-policemdt`
2. Ensure dependencies are started before it in `server.cfg`:
	 ```cfg
	 # Framework (pick one)
	 # ensure pfm-core
	 # ensure es_extended

	 ensure oxmysql
	 ensure screenshot-basic
	 ensure pf-policemdt
	 ```

2) Import SQL

1. Open your database tool (HeidiSQL / phpMyAdmin / DBeaver)
2. Import the MDT SQL for your framework:
	 - QBCore: `sql/pf-policemdt-qb.sql`
	 - ESX: `sql/pf-policemdt-esx.sql`
	   - ESX file includes read-compat views (`players`, `player_vehicles`) and ESX-only MDT tables.
3. Optional (development/testing): import sample/test data:
	- QBCore: `sql/pf-policemdt-qbtestdata.sql`
	- ESX: `sql/policemdt-esxtestdata.sql`
3. Restart your server or run `refresh` then `ensure pf-policemdt`

3) Configure the resource

Edit `config.lua` and review these first:

- `Config.AllowedJobs`
- `Config.SupervisorGrades`
- `Config.Item`, `Config.Command`, `Config.Keybind`
- `Config.DispatchAutoCalls`, `Config.Dispatch911`
- `Config.DispatchNotifications`
- `Config.Map`
- `Config.Webhooks.Evidence` (recommended to replace or disable)
- Integration selectors: `Config.Phone`, `Config.Housing`, `Config.Garage`, `Config.Banking`, `Config.Prison`

4) Add the MDT item to QBCore

This resource can open via command/keybind, but the inventory item is the typical production setup.

# QBCore Integration

## Where `qb-core/shared/items.lua` is

On a standard QBCore install, the file is located at:

`resources/[qb]/qb-core/shared/items.lua`

## Item entry to add

Add this item entry (use the same key and name as `Config.Item.Name`, default is `mdt`):

```lua
['mdt'] = {
		name = 'mdt',
		label = 'Police MDT',
		weight = 500,
		type = 'item',
		image = 'mdt.png',
		unique = false,
		useable = true,
		shouldClose = true,
		combinable = nil,
		description = 'Police Mobile Data Terminal.'
},
```

What the item is used for

- `mdt`: opens the MDT UI (tablet prop/animation handled automatically)

Inventory image

- If your inventory UI shows item icons, add `mdt.png` to your inventory’s image folder.
	- Example for `qb-inventory`: `resources/[qb]/qb-inventory/html/images/mdt.png`

# Configuration

All settings are in `config.lua`.

## Debug & Locale


- `Config.Debug`
	- Enables debug logging and debug-only commands.

- `Config.Locale`
	- One of: `en`, `es`, `pl`, `fr`, `de`, `pt`.

## Jobs & Permissions


- `Config.AllowedJobs`
	- Jobs that may open and use the MDT.
	- Example:
		```lua
		Config.AllowedJobs = { police = true, sheriff = true }
		```

- `Config.SupervisorGrades`
	- Job grades considered “supervisor” for supervisor-only actions.
	- Example:
		```lua
		Config.SupervisorGrades = { police = { [3]=true, [4]=true } }
		```

## Access Methods

- `Config.Item`
	- `Enabled`: enables opening MDT via inventory item
	- `Name`: item name key in `qb-core/shared/items.lua` (default `mdt`)
	- `Description`: descriptive text

- `Config.Command`
	- `Enabled`: enables the command
	- `Name`: command name (default `mdt`)
	- `Description`: descriptive text

- `Config.Keybind`
	- `Enabled`: enables the keybind
	- `Description`: label shown in FiveM keybind settings
	- `Key`: default key (example `F6`)
	- `InputType`: input device type for `RegisterKeyMapping` (`keyboard`, `pad`, or `mouse`)
	- `CommandName`: internal command used for key mapping (default `pfmdt_open`)

## UI


- `Config.TabletTitle`
	- Title shown at the top of the MDT UI.

- `Config.TabletVisuals`
	- `Enabled`: master toggle for tablet prop/animation
	- `Item` / `Command` / `Keybind`: enable visuals per open method
	- `Attach`
		- `bone`: attachment bone (default 57005 = right hand)
		- `pos` / `rot`: attachment position/rotation tuning

## Map


- `Config.Map.mode`
	- `tiles`: uses `html/tiles/`
	- `map`: uses `html/map/full_map.png`
	- `map2`: uses `html/map2/full_map.png`


- `Config.Map.renderMode`
	- Internal map mode (`tiles` or `image`).

- `Config.Map.image`
	- `set`: folder name under `html/` (example `map`)
	- `file`: full map image file (example `full_map.png`)
	- `previewFile`: optional low-res preview used while zooming
	- `fullSwapDelayMs`: delay before returning to full-res
	- `width` / `height`: actual pixel dimensions of the full map image
	- `homography.enabled` + `h11..h33`: enables projective mapping and sets coefficients
	- `affine.enabled` + `a..f`: enables affine mapping and sets coefficients
	- `offsetX` / `offsetY`: extra pixel offsets after mapping


- `Config.Map.width` / `Config.Map.height`
	- Tile canvas size.


- `Config.Map.minZoom` / `Config.Map.maxZoom`
	- Zoom limits.


- `Config.Map.debugCalibration`
	- Enables calibration helpers in the UI.


- `Config.Map.worldBounds` + `Config.Map.flipY`
	- Simple fallback mapping bounds.


- `Config.Map.affine`
	- `enabled` + coefficients `a..f`.

## Location Areas


- `Config.LocationAreas`
	- Used as a fallback location label when street/zone resolution fails.

## Dispatch UI


- `Config.CallPriorities`
	- Defines labels/colors for priorities 1–3.

- `Config.CallStatuses`
	- Defines labels/colors for `pending`, `accepted`, `completed`.

## Dispatch Notifications (sound)


- `Config.DispatchNotifications.Enabled`
	- Enables the dispatch notification sound on new calls.

- `Config.DispatchNotifications.Mode`
	- Selects the sound system: `native` (recommended) or `nui`.

- `Config.DispatchNotifications.Sound`
	- Native frontend sound configuration.
	- `enabled`: enables native sound playback
	- `name`: native sound name
	- `soundset`: native sound set
- `Config.DispatchNotifications.NativeRepeat`
	- `count`: how many times to play the sound
	- `intervalMs`: delay between plays (milliseconds)

- `Config.DispatchNotifications.NUI`
	- NUI/WebAudio configuration (used only when `Mode = 'nui'`).
	- `enabled`: enables NUI sound playback
	- `volume`: volume multiplier (1.0 = normal)
	- `waveform`: waveform used by the tone generator
	- `tone1Hz`, `tone2Hz`: tone frequencies
	- `tone2AtMs`, `durationMs`: timing controls (milliseconds)

- `Config.DispatchNotifications.InitialDingWindowSeconds`
	- Dings on the first sync if a call was created very recently.

## /911 Civilian Calls


- `Config.Dispatch911.Enabled`
	- Enables the `/911 <description>` command.

- `Config.Dispatch911.CooldownSeconds`
	- Cooldown between `/911` calls per player.

- `Config.Dispatch911.MaxDescriptionLength`
	- Maximum length for the `/911` description.
- `Config.Dispatch911.MultiMatch`
	- `enabled`: allows one `/911` message to create multiple calls if multiple categories match
	- `maxCalls`: max calls created from one `/911`

- `Config.Dispatch911.Default`
	- `callType`, `code`, `title`, `priority`

- `Config.Dispatch911.Types`
	- Keyword-based classification entries.
	- Each type supports: `keywords`, `callType`, `code`, `title`, `priority`.

## Dispatch Templates & Expiry


- `Config.TestCallTemplates`
	- Templates used by the dispatch testing tooling.

- `Config.CallExpirySeconds`
	- How long calls remain before auto-expiring.

## Dispatch Auto Calls


- `Config.DispatchAutoCalls.Enabled`
	- Enables auto dispatch calls generated by player actions.

- `Config.DispatchAutoCalls.GlobalChance`
	- 1.0 = always, 0.5 = 50%, 0.0 = disabled.

- `Config.DispatchAutoCalls.IgnorePolice`
	- Prevents auto calls from being created by police jobs.

- `Config.DispatchAutoCalls.GlobalCooldown`
	- Minimum time between any auto calls (seconds).

- `Config.DispatchAutoCalls.Calls`
	- Per-type configuration entries.
	- Each type supports: `enabled`, `chance` (0–100), `cooldown` (seconds), `code`, `title`, `priority`.

## Dashboard


- `Config.Dashboard`
	- Optional seed arrays: `bulletins`, `reports`, `warrants`.

## Report & Charge Types


- `Config.ReportTypes`
	- Report type labels shown in the UI.

- `Config.ChargeTypes`
	- Charge type labels shown in the UI.

## Permissions


- `Config.Permissions`
	- Permission gates (job => min grade) for actions like warrants and viewing incidents/reports.

## Evidence


- `Config.Evidence.MinGradeCreate`
	- Minimum job grade required to create evidence.

- `Config.Evidence.MinGradeDelete`
	- Minimum job grade required to delete evidence.

## Webhooks


- `Config.Webhooks.Evidence`
	- Discord webhook URL for evidence logging.
	- Production recommendation: set to your own webhook URL, or set to an empty string to disable.

## FTO Reports


- `Config.FTOReports.MinGradeCreate`
	- Minimum grade required to create FTO reports.

- `Config.FTOReports.MaxPhase`
	- Maximum phase number supported by the FTO workflow.

- `Config.FTOReports.TraineePoliceOnly`
	- If enabled, restricts trainees to police-only logic.

## Integrations


- `Config.PhoneNumberFormat`
	- Optional phone formatting pattern. Leave nil to use the default.

- `Config.Phone`
	- Selects the phone provider integration.

- `Config.Housing`
	- Selects the housing/property provider integration.

- `Config.Garage`
	- Selects the garage provider integration.

- `Config.Banking`
	- Selects the banking/society backend used for fine deposits.

- `Config.Prison`
	- Selects the prison/jail integration.

## Sentencing & Prison


- `Config.Sentencing.PrisonScript`
	- Which prison system the sentencing flow uses.

- `Config.Sentencing.FinesToSociety`
	- If enabled, deposits paid fines into a society account.

- `Config.Sentencing.FinesSocietyJob`
	- Which job society receives fine deposits.

- `Config.Sentencing.Reductions`
	- Configures the “time reduction” options and their percentages.

- `Config.Sentencing.Prison.Spawns`
	- Spawn points used when jailing a player.

- `Config.Sentencing.Prison.Release`
	- Release point used when unjailing a player.

- `Config.Sentencing.PrisonOutfit`
	- Outfit applied for the built-in jail flow.

## CCTV


- `Config.CCTV.Enabled`
	- Enables the CCTV module.

- `Config.CCTV.AutoDiscover`
	- Automatically scans nearby world props for cameras.

- `Config.CCTV.PersistDiscoveredToDb`
	- Automatically saves discovered cameras to the database.

- `Config.CCTV.Debug`
	- Enables CCTV debug logging.

- `Config.CCTV.DiscoveryInterval`
	- How often clients scan for new cameras (milliseconds).

- `Config.CCTV.RecordingDistance`
	- Maximum distance for recording footage.

- `Config.CCTV.RecordingInterval`
	- How often to record footage entries (milliseconds).

- `Config.CCTV.RecordingBatchSize`
	- How many recording rows to batch per insert.

- `Config.CCTV.DamageOverlayDuration`
	- How long to show the camera damage effect (milliseconds).

- `Config.CCTVModels`
	- List of GTA camera props used for discovery.

# Compatible Scripts

Required

- `qb-core`
- `oxmysql`
- `screenshot-basic`

Optional (controlled by `config.lua`)

- `qb-phone`
- `qb-houses` / `nolag-properties`
- `qb-garages`
- `qb-banking` / `tgg-banking`
- `rcore_prison`

# Commands & Exports

Commands

- `/mdt` (default; configurable)
	- Opens the MDT (requires allowed job). Command name is `Config.Command.Name`.
- `/closemdt`
	- Closes the MDT (also bound to `ESCAPE` while the UI has focus).
- `/911 <description>`
	- Creates one or more civilian dispatch calls based on keyword classification.
- `/pfmdt_testding`
	- Plays the dispatch notification sound (testing).

Admin commands

- `/unjail <id>`
	- Releases a player from MDT jail (QBCore admin permission).
- `/mdt_seed`
	- Seeds sample MDT records for UI testing (QBCore admin permission).

Debug-only commands (require `Config.Debug = true`)

- `/mdt_calib_point`
	- Captures a world calibration point (use while MDT is open).
- `/testcall`
	- Creates a test dispatch call (QBCore admin permission + debug enabled).
- `pfmdt_roster_reset` (server command)
	- Reseeds/repairs roster defaults.

- `/dumpcctvs`
	- Dumps the CCTV registry to the server console.
	- This command is only registered if `Config.Debug = true` and `Config.CCTV.DumpCommandEnabled = true`.

Exports

Server exports

- `exports['pf-policemdt']:CreateDispatchCall(callData)`
	- Creates a dispatch call.
	- Returns: created call table, or `nil` on invalid input.
	- `callData` supports: `title`, `description`, `suspect`, `priority`, `status`, `locationLabel`, `coords`, `callType`, `code`, `createdAt`, `createdBy`, `assignedUnits`.

- `exports['pf-policemdt']:CreateDispatchCallout(calloutType, coords, locationLabel)`
	- Triggers a configured callout type (subject to callout rules/cooldowns).
	- Returns: `true` if created, `false` otherwise.

- `exports['pf-policemdt']:getCCTVCameras()`
	- Returns the server CCTV camera registry table.

Client exports

- `exports['pf-policemdt']:IsMDTOpen()`
	- Returns `true` if the MDT UI is open.

- `exports['pf-policemdt']:IsUsingMDT()`
	- Returns `true` if the tablet visuals/usage state is active.

# Troubleshooting

Calls show but no dispatch ding

- Confirm `Config.DispatchNotifications.Enabled = true`.
- If you changed sound settings, restart the resource.
- If you use `Mode = 'native'`, try a different `Sound.name`/`Sound.soundset`.

MDT opens but no data / blank pages

- SQL not imported or oxmysql not connected.
	- Import the correct SQL:
	  - QBCore: `sql/pf-policemdt-qb.sql`
	  - ESX: `sql/pf-policemdt-esx.sql`
	- Verify oxmysql connection string and that `ensure oxmysql` runs before this resource.

“You do not have access to the MDT”

- Your job is not listed in `Config.AllowedJobs`.
- Make sure the player is actually on the correct job (and on duty if your server enforces duty).

/911 does nothing

- Make sure `Config.Dispatch911.Enabled = true`.
- Cooldown can block repeated calls: `Config.Dispatch911.CooldownSeconds`.
- Ensure the resource is started and not erroring in F8/server console.

CCTV not finding cameras

- Ensure `Config.CCTV.Enabled = true` and `Config.CCTV.AutoDiscover = true`.
- Auto discovery depends on clients being near camera props.

Evidence screenshots not working

- `screenshot-basic` must be installed and started.

# Support

When requesting support, include:

- Your `config.lua` (remove webhook URLs before sharing)
- Server console errors and client F8 errors
- The exact steps to reproduce the issue
- Confirmation that the correct SQL was imported (`sql/pf-policemdt-qb.sql` or `sql/pf-policemdt-esx.sql`) and `oxmysql` is connected

- `Config.DispatchAutoCalls.Cooldowns`
	- Per-event cooldowns (seconds).

- `Config.DispatchAutoCalls.Codes`
	- Defines the dispatch code/title/description used for each auto call.

### Dashboard + UI lists

- `Config.Dashboard`
	- Optional seed data shown on the dashboard (bulletins/reports/warrants).

- `Config.ReportTypes`
	- List of report types shown in the UI.

- `Config.ChargeTypes`
	- List of charge categories/types shown in the UI.

### Permissions

- `Config.Permissions`
	- Feature permissions by job + minimum grade.
	- Example: `deleteWarrant = { police = 3, sheriff = 3 }` means grade 3+ can delete warrants.

### Evidence

- `Config.Evidence.MinGradeCreate`
	- Minimum grade required to create evidence.

- `Config.Evidence.MinGradeDelete`
	- Minimum grade required to delete evidence.

- `Config.Webhooks.Evidence`
	- Discord webhook URL used for evidence logging/notifications (if enabled by your server usage).
	- Replace with your own webhook URL.

### FTO

- `Config.FTOReports.MinGradeCreate`
	- Minimum grade required to create FTO reports.

- `Config.FTOReports.MaxPhase`
	- Maximum phase number used by the FTO UI.

- `Config.FTOReports.TraineePoliceOnly`
	- If `true`, trainee searching/selection is restricted to police jobs.

### Integrations

- `Config.Integrations.Phone`
	- `PreferQbPhone`: use `qb-phone` APIs when available.
	- `FallbackToCharinfo`: fall back to reading phone from player data when possible.

- `Config.Integrations.Properties`
	- Enables property display in citizen profiles.
	- Providers toggles which property scripts can be used.

- `Config.Integrations.Insurance`
	- Enables the (optional) insurance panel.

### Banking

- `Config.Banking.Provider`
	- Banking/society funds backend used for deposits (fines, etc.).
	- Supported values include: `auto`, `qb-management`, `qb-banking`, `tgg-banking`, `management_funds`.

### Sentencing / prison

- `Config.Sentencing.PrisonScript`
	- Which prison system to use.
	- `default` uses the built-in MDT jail flow; `rcore` integrates with `rcore_prison`.

- `Config.Sentencing.FinesToSociety` / `Config.Sentencing.FinesSocietyJob`
	- When enabled, deposits paid fines into the configured society account.

- `Config.Sentencing.Prison`
	- Built-in prison spawn/release coordinates used by the default system.

- `Config.Sentencing.PrisonOutfit`
	- Outfit applied during the built-in MDT jail flow and reverted on release.

- `Config.Sentencing.Rcore`
	- Event names used when integrating with `rcore_prison`.

- `Config.Sentencing.Reductions`
	- Jail-time reduction presets (display label + percent).

### CCTV

- `Config.CCTV.Enabled`
	- Enables CCTV module.

- `Config.CCTV.AutoDiscover`
	- Client scans the world for CCTV props and reports them.

- `Config.CCTV.PersistDiscoveredToDb`
	- When enabled, discovered cameras are inserted into the DB.

- `Config.CCTV.Debug`
	- Enables CCTV-specific debug logging.
	- Default is tied to `Config.Debug`.

- `Config.CCTV.DumpCommandEnabled`
	- When enabled (and `Config.Debug = true`), registers `/dumpcctvs`.

- `Config.CCTV.RecordingDistance`
	- Max distance for camera recording/view logic.

- `Config.CCTV.DiscoveryInterval`
	- How often the client scans for cameras (ms).

- `Config.CCTV.RecordingInterval` / `Config.CCTV.RecordingBatchSize`
	- Recording tick interval + batch sizing (performance tuning).

- `Config.CCTV.DamageOverlayDuration`
	- How long the “signal lost” overlay effect should last (ms).

- `Config.CCTVModels`
	- List of prop models that count as CCTV cameras for auto-discovery.

### 4) Restart
Restart the resource (or the server):
- `restart pf-policemdt`

## Usage

### Open/Close MDT
- Default open key: `F6` (configurable)
- Default close key: `BACKSPACE` (configurable)

Also available:
- `/openmdt`
- `/closemdt`

### Dispatch testing
- `/testcall` creates a test dispatch call (debug-only)

### Roster utilities
- `/pfmdt_roster_reset` resets/seeds the roster table (debug-only; admin/supervisor use)

### Map calibration (optional)
- `/mdt_calib_point` adds a calibration point when map debug calibration is enabled (debug-only)

### CCTV utilities
- `/dumpcctvs` dumps discovered CCTV entries (debug-only; server console command)

## Debug mode

- Set `Config.Debug = true` in `config.lua` to enable developer commands and debug console logging.
- When `Config.Debug = false` (recommended for production), the following are hidden/disabled:
	- `/testcall`
	- `/pfmdt_roster_reset`
	- `/mdt_calib_point`
	- `/dumpcctvs`
	- Most MDT debug `print()` output

## Permissions

- Access is gated by job name in `Config.AllowedJobs`.
- Supervisor features are controlled by `Config.SupervisorGrades`.
- Some modules (warrants/evidence/officer management) also use configured minimum grade thresholds in `config.lua`.

## Troubleshooting

### MDT won’t open
- Confirm your job is listed in `Config.AllowedJobs`
- Confirm the resource is started and `oxmysql` is running
- Check client F8 console for NUI/callback errors

### Searches return nothing
- Confirm you imported the correct SQL (`sql/pf-policemdt-qb.sql` or `sql/pf-policemdt-esx.sql`)
- Confirm your server database has the expected QBCore player tables (this MDT reads from `players` for character data)

### CCTV page is empty
- Ensure `Config.CCTV.Enabled = true`
- Stand near CCTV props (they must be streamed in) and wait for discovery to run
- Confirm the `pf_mdt_cctv_cameras` table exists (it is in the SQL file)

## Support Notes

This resource ships as-is and is intended for QBCore environments. If you need help tailoring job names, banking/prison integrations, or map calibration for a custom map pack, adjust `config.lua` first.

