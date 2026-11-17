# pf-emsmdt (EMS MDT)

The EMS mobile data terminal: dispatch board, patients, patient care (exams and treatments decided by
pf-ambulancejob), patient care reports (PCR), the unit board, roster, SOPs and staff management, plus the
hospital workstation app for the tablet and the computer (pf-devices). It works with pf-ambulancejob, which
owns every medical record and decides every exam, treatment, admission and bill.

The police MDT (sentencing, jail, CCTV, evidence, warrants) is `pf-policemdt-DEV`; none of that is part of
this resource.

## Requirements
- pfm-core (QBCore API), oxmysql, screenshot-basic
- pf-ambulancejob (medical engine, hospital)
- Optional: pf-devices (tablet and computer apps), pf-services (EMS requests on the dispatch board),
  pf-government (qualifications behind the medical tiers)

## Install
1. `ensure` order in server.cfg:
   ```cfg
   ensure oxmysql
   ensure screenshot-basic
   ensure pfm-core
   ensure pf-ambulancejob
   ensure pf-emsmdt
   ```
2. No SQL import: the tables are created and upgraded by the resource's own migrations (`server/schema.lua`,
   key `pf-emsmdt`) on start; `sql/pf-emsmdt-qb.sql` only says so.
3. The tablet item (`Config.Item.Name`, default `ems_mdt`) is made usable by this resource; it must exist in
   pfm-core's shared items for players to hold it. Without the item the command and key mapping still work.

## Using it
- `/emsmdt` (`Config.Command`), the `F6` key mapping (`Config.Keybind`) or the `ems_mdt` item opens the MDT;
  `ESC` or `/closemdt` closes it. On the tablet and the computer it is the "EMS MDT" app.
- `/ems911 <text>` (and `/911` when the police MDT is not running) sends a call to the dispatch board.
- Patient care: stand next to the patient. The page lists nearby patients as the server sees them
  (`pf-emsmdt:server:getNearbyPatients`), and every exam and treatment goes to pf-ambulancejob.
- Care reports open by themselves on the first treatment; the narrative is the only typed part and saves to
  the server while you type and when the window closes. Lists are paged and sorted by the server.

## Configuration (`config.lua`)
- `Config.AllowedJobs`, `Config.SupervisorGrades`, `Config.Permissions`: who uses the MDT and what each grade may do.
- `Config.Item`, `Config.Command`, `Config.Keybind`, `Config.TabletTitle`, `Config.TabletVisuals`: how it opens and looks.
- `Config.Map`, `Config.LocationAreas`, `Config.CallPriorities`, `Config.CallStatuses`, `Config.DispatchNotifications`,
  `Config.Dispatch911`: the dispatch board and the call sound.
- `Config.PCR`: report charting, narrative length, handover rules, dispositions, `ListLimit` (rows per page).
- `Config.Units`: unit statuses, crew size, rig models.
- `Config.Callers`: which resources may call the exports below.
- `Config.Webhooks.Evidence`: read from the convar `pf_emsmdt_evidence_webhook` (set it in server.cfg; never in the file).

## Exports
Server:
- `CreateDispatchCall(callData)`: puts a call on the board; returns the call or `nil`.
- `GetPcr(pcrId, opts)`, `ListPcrFor(cid, opts)`: reports, with the privacy rules of pf-ambulancejob
  `GetMedicalRecord` (`opts = { viewer = src, purpose = 'treatment' | 'self' | 'court_order', courtOrderId? }`).
- `GetUnitStatus(src)`: the unit board entry of an EMS player.

Client:
- `IsMDTOpen()`, `IsUsingMDT()`
- `OpenPatientCare(target)`: opens the MDT on the patient care page for a server id.

## Debug
`Config.Debug = true` enables `/mdt_calib_point` (map calibration) and debug logging. `/pfmdt_testding` plays the
dispatch sound. `pfemsmdt_roster_reset` (server console) reseeds the roster defaults.
