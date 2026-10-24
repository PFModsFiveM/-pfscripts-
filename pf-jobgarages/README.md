# pf-jobgarages

Job-based fleet garages for **QBCore** with a modern NUI.

Players can open a job garage, sign out a fleet vehicle, and return it. Managers can maintain the fleet, force-return vehicles, and set assignment rules.

## Features

- **Job-locked garages** (police / ambulance / mechanic, etc.)
- **Fleet vehicles** stored in a DB table (per-garage)
- **Per-vehicle grade requirement** (`min_grade`)
- **Assignments**
  - Open to all
  - Assigned to a specific employee (by `citizenid`)
  - Reserved for a minimum grade
- **Vehicles Out** tab (who has what out + since when)
- **Manager tools**
  - Add/remove fleet vehicles
  - Force return + force despawn by plate
  - Permissions UI (stored per garage)
- **Action logs** (recent actions shown in UI)
- **Vehicle thumbnails**: `html/images/vehicles/<model>.webp` (tries webp/png/jpg/jpeg)

## Dependencies

Required:

- `qb-core`
- `qb-target`
- `oxmysql`

Recommended / optional:

- A vehicle keys resource that supports `vehiclekeys:client:SetOwner` (commonly `qb-vehiclekeys`).
- If you set `Config.GarageProvider = 'cd'`: `cd_garage` (used only to verify keys before adding a fleet vehicle).

## Installation

1. Put the folder in your resources directory (you already have it under):
   - `resources/[custom]/pf-jobgarages`

2. Import the SQL:
   - Run `sql/pf_jobgarages.sql`

   Notes:
   - The **required** tables for this resource are:
     - `job_garage_vehicles`
     - `job_garage_permissions`
     - `job_garage_logs`
   - The `pf_jobgarages.sql` file also contains a `CREATE TABLE player_vehicles` section as a reference.
     - **If you are using QBCore, you almost certainly already have `player_vehicles`.**
     - Do **not** re-create it if it already exists on your server.

3. Ensure the resource in your `server.cfg`:

   ```cfg
   ensure oxmysql
   ensure pfm-target
   ensure pf-jobgarages
   ```

## Configuration

Edit `config.lua`.

### Core settings

```lua
-- Garage provider: 'cd', 'qb', or 'none'
Config.GarageProvider = 'qb'

-- Player vehicles owner column: 'citizenid', 'owner', 'license', 'identifier'
-- (Used when the UI loads "My Vehicles" from your player_vehicles table.)
Config.PlayerVehiclesOwnerColumn = 'license'
```

### Adding / editing garages

Each entry in `Config.JobGarages` defines one job garage target + spawn point.

```lua
Config.JobGarages = {
  ['police_main'] = {
    label = 'MRPD Fleet',
    job = 'police',

    -- Minimum grade required to OPEN the garage target (qb-target interaction)
    minGrade = 0,

    -- The prop spawned as the qb-target entity
    targetProp = 'prop_parkingpay',
    targetCoords = vector4(458.61, -1023.36, 28.33, 268.63),

    -- Where vehicles spawn when taken out
    spawnCoords = vector4(410.12, -971.35, 25.45, 180.0),

    -- UI accent color for this garage
    themeColor = '#53a2ff',

    -- Optional: manager grade threshold (defaults to 4)
    manageGrade = 4,

    -- Optional defaults used when the permissions row does not exist yet
    defaultMinGradeUse = 0,
  }
}
```

## How it works (quick)

- **Open garage**: interact with the spawned prop (qb-target) → NUI opens.
- **Take a vehicle**: selecting a fleet vehicle marks it as **out** in the DB, then spawns it client-side.
- **Store a vehicle**: “Store Job Vehicle” only works for the plate currently taken out via this UI.
- **Add fleet vehicles** (manager): in the **Manage Fleet** tab, load your owned vehicles and add them into the fleet.
  - The script checks ownership/keys depending on `Config.GarageProvider`.
- **Assignments** (manager): reserve a vehicle to a specific employee (online server ID) or to a minimum grade.
- **Logs**: the last ~50 actions per garage are shown in the Logs tab.

## Images & sounds

### Vehicle images

- Place vehicle images at:
  - `html/images/vehicles/<model>.webp`
- The UI will also try `.png`, `.jpg`, `.jpeg` if `.webp` is missing.

### UI sounds (optional)

`html/index.html` references:

- `html/sounds/take.wav`
- `html/sounds/store.wav`
- `html/sounds/error.wav`

The folder currently only contains a placeholder, so add those `.wav` files if you want sounds.

## Troubleshooting

- **Garage target doesn’t show**: confirm `qb-target` is running and the resource is started; the script spawns a prop at each `targetCoords`.
- **“My Vehicles” list is empty**: set `Config.PlayerVehiclesOwnerColumn` to match your `player_vehicles` schema (`citizenid`, `license`, `owner`, etc.).
- **Can’t add a vehicle to fleet**:
  - With `Config.GarageProvider = 'qb'`: the plate must exist in `player_vehicles` for your `citizenid`.
  - With `Config.GarageProvider = 'cd'`: you must have keys per `cd_garage`.
- **Vehicle keys not working after spawn**: make sure your keys resource listens for `vehiclekeys:client:SetOwner`.

## Version

`1.0.0` (see `fxmanifest.lua`).
