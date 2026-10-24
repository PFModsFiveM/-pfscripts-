# pf-mapcal-sync

Capture in-game marker coordinates and export them for AMBWeb map calibration.

Now supports live pairing mode: capture in game, click the map in browser, and both sides confirm.

## What it does

- `/mapcal_add <marker-id>` captures your current in-game position and stores it under that marker ID.
- `/mapcal_sync <marker-id>` captures your current in-game position and waits for website map click pairing.
- `/mapcal_remove <marker-id>` removes one captured marker.
- `/mapcal_list` prints captured IDs.
- `/mapcal_clear` clears all captured markers.
- `/mapcal_export` writes JSON to `Config.OutputFilePath`.

Output file format:

```json
{
  "exportedAt": "2026-07-02T00:00:00Z",
  "source": "pf-mapcal-sync",
  "points": {
    "amb_rox_03_hospital_int-instance-1": {
      "id": "amb_rox_03_hospital_int-instance-1",
      "coords": { "x": -518.2100, "y": 7378.5800, "z": 11.8400 }
    }
  }
}
```

## Install

1. Add this resource folder to your server resources.
2. Ensure it in server.cfg:
   - `ensure pf-mapcal-sync`
3. Grant permission:
   - `add_ace group.admin mapcal.admin allow`
   - `add_principal identifier.license:YOUR_LICENSE group.admin`

## Configure output path

Set this in `config.lua`:

- `Config.OutputFilePath = 'F:/AMBWeb/data/fivem-live-coords.json'`
- `Config.SyncFilePath = 'F:/AMBWeb/data/mapcal-sync.json'`

Use a path your FiveM server process can write to.

## Live Pairing Workflow (recommended)

1. Start the local sync API in `F:\AMBWeb`:
  - `node tools/mapcal-sync-server.js`
2. Open website from a local web server so `/api/mapcal/*` resolves to the sync API.
3. On map page, open **Calibration Sync** and click **Enable Sync Mode**.
4. In game, stand at marker location and run:
  - `/mapcal_sync <marker-id>`
5. On website, click **Use Next Click** and click exact map point.
6. You will receive confirmation in both places:
  - website: sync + recalibration success
  - game chat: "Sync confirmed for ..."

Each confirmation updates `data/calibration-control-points.json` and runs calibration automatically.

## Website import

After `/mapcal_export`, run in AMBWeb:

1. `node tools/import-fivem-live-coords.js`
2. `node tools/calibrate-map-from-control-points.js`

This merges live in-game coords into calibration controls and regenerates map overrides.
