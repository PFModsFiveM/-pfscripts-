# Roxwood Vehicle Snapshot Capture

This helper captures JPG previews for `vehicles.html` using FiveM and `screenshot-basic`.

## Setup

1. Install and ensure `screenshot-basic` in your FiveM server.
2. Copy this `vehicle-snapshot-capture` folder into your server resources folder.
3. Add this to `server.cfg` after Roxwood vehicles and screenshot-basic:

```cfg
ensure screenshot-basic
ensure amb-roxwood-vehicles
ensure vehicle-snapshot-capture
```

4. From this resource folder, run the local receiver. In Command Prompt use `cd /d` because the folder is on the `F:` drive:

```cmd
cd /d "F:\fivemserver\txData\PF\resources\[pfscripts]\vehicle-snapshot-capture"
node receiver.js
```

In PowerShell use `-LiteralPath` because `[pfscripts]` contains brackets:

```powershell
Set-Location -LiteralPath "F:\fivemserver\txData\PF\resources\[pfscripts]\vehicle-snapshot-capture"
node receiver.js
```

Do not run these inside the Node.js prompt that starts with `>`. If you see that prompt, type `.exit` first.

By default it writes directly to `F:\AMBWeb\assets\images\vehicles`. To write somewhere else, start it with `AMBWEB_VEHICLE_IMAGE_DIR` set to a different folder.

5. Join the server, stand in an open flat area with good lighting, open chat/F8, and test one vehicle first:

```text
/roxvehshot roxtaxi
```

The camera uses a front-corner angle so each screenshot shows the front and side. If the test angle looks good, run the full batch:

```text
/roxvehshots
```

The client spawns each vehicle, points a scripted camera at the same angle, sends the screenshot to the local receiver, and writes images to:

```text
F:\AMBWeb\assets\images\vehicles\<spawncode>.jpg
```

`vehicles.html` automatically uses those filenames on each card.

## Notes

- Keep the FiveM client focused while the loop runs.
- Use a clear daylight location for consistent thumbnails.
- If a model is missing or not streamed, the helper skips it and continues.
- If your FiveM client is not on the same machine as this website folder, change `captureEndpoint` in `client.lua` to point at the machine running `receiver.js`.
