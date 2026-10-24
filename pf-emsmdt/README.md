
# pf-emsmdt + pf-ambulancejob (EMS Injury MDT)

Single install guide for the EMS MDT and injury system.

## Requirements
- FiveM (cerulean)
- QBCore
- oxmysql
- screenshot-basic
- Resources: pf-emsmdt, pf-ambulancejob

## File Locations
- Config: [config.lua](config.lua)
- Ambulance schema: [../pf-ambulancejob/sql/pf-ambulancejob-qb.sql](../pf-ambulancejob/sql/pf-ambulancejob-qb.sql)
- Item: qb-core [shared/items.lua](../../[qb]/qb-core/shared/items.lua)

## Install Steps
1) Place resources
- Keep pf-emsmdt and pf-ambulancejob in resources/[custom]/.

2) Server cfg order
```cfg
ensure oxmysql
ensure screenshot-basic
ensure pf-ambulancejob
ensure pf-emsmdt
```

3) Import SQL
- Run pf-ambulancejob-qb.sql on your database (creates injury/treatment tables).

4) Add EMS MDT item (QBCore)
- In qb-core/shared/items.lua (Job System section) ensure this entry exists:
```lua
ems_mdt = { name = 'ems_mdt', label = 'EMS MDT Tablet', weight = 500, type = 'item', image = 'tablet.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'EMS mobile data terminal for medical records and injury assessments.' },
```
- Add tablet.png to your inventory images (e.g., qb-inventory/html/images/tablet.png) if missing.

5) Configure
- pf-emsmdt [config.lua](config.lua):
  - Config.AllowedJobs = { ambulance = true, ems = true, fire = true }
  - Config.Item.Name = 'ems_mdt'
  - Adjust Command/Keybind if desired
- pf-ambulancejob [config.lua](../pf-ambulancejob/config.lua):
  - Set AllowedJobs, ScanDuration, CheckDistance, Debug, treatments/weapons as needed.

6) Usage
- Give ems_mdt to EMS or add to shop/stash.
- EMS runs /checkinjuries [id] near a patient (3m). Progress bar → MDT opens on Injury Assessment.
- Treatments and notes save to DB; injuries persist by citizen_id.

## Quick Verify Checklist
- Server boots with no errors.
- Items file contains ems_mdt.
- SQL tables from pf-ambulancejob-qb.sql exist.
- Using ems_mdt opens the EMS MDT.
- /checkinjuries shows progress bar then injury panel with body map.
- Treatments/notes succeed without console errors.
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



Exports

Server exports

- `exports['pf-emsmdt']:CreateDispatchCall(callData)`
	- Creates a dispatch call.
	- Returns: created call table, or `nil` on invalid input.
	- `callData` supports: `title`, `description`, `suspect`, `priority`, `status`, `locationLabel`, `coords`, `callType`, `code`, `createdAt`, `createdBy`, `assignedUnits`.

- `exports['pf-emsmdt']:CreateDispatchCallout(calloutType, coords, locationLabel)`
	- Triggers a configured callout type (subject to callout rules/cooldowns).
	- Returns: `true` if created, `false` otherwise.

Client exports

- `exports['pf-emsmdt']:IsMDTOpen()`
	- Returns `true` if the MDT UI is open.

- `exports['pf-emsmdt']:IsUsingMDT()`
	- Returns `true` if the tablet visuals/usage state is active.

# Troubleshooting

Calls show but no dispatch ding

- Confirm `Config.DispatchNotifications.Enabled = true`.
- If you changed sound settings, restart the resource.
- If you use `Mode = 'native'`, try a different `Sound.name`/`Sound.soundset`.

MDT opens but no data / blank pages

- SQL not imported or oxmysql not connected.
	- Import the correct SQL for your framework:
		  - QBCore: `sql/pf-emsmdt-qb.sql`
		  - ESX: `sql/pf-emsmdt-esx.sql`
	- Verify oxmysql connection string and that `ensure oxmysql` runs before this resource.

“You do not have access to the MDT”

- Your job is not listed in `Config.AllowedJobs`.
- Make sure the player is actually on the correct job (and on duty if your server enforces duty).

/911 does nothing

- Make sure `Config.Dispatch911.Enabled = true`.
- Cooldown can block repeated calls: `Config.Dispatch911.CooldownSeconds`.
- Ensure the resource is started and not erroring in F8/server console.



# Support

When requesting support, include:

- Your `config.lua` (remove webhook URLs before sharing)
- Server console errors and client F8 errors
- The exact steps to reproduce the issue
- Confirmation that the correct SQL was imported (`sql/pf-emsmdt-qb.sql` or `sql/pf-emsmdt-esx.sql`) and `oxmysql` is connected

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
- `restart pf-emsmdt`

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
- Confirm you imported the correct SQL (`sql/pf-emsmdt-qb.sql` or `sql/pf-emsmdt-esx.sql`)
- Confirm your server database has the expected QBCore player tables (this MDT reads from `players` for character data)

### CCTV page is empty
- Ensure `Config.CCTV.Enabled = true`
- Stand near CCTV props (they must be streamed in) and wait for discovery to run
- CCTV is not part of pf-emsmdt (PD module removed/disabled)

## Support Notes

This resource ships as-is and is intended for QBCore environments. If you need help tailoring job names, banking/prison integrations, or map calibration for a custom map pack, adjust `config.lua` first.

