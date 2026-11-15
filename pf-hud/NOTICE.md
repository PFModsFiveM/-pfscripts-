# pf-hud: licence notice

pf-hud's look and much of its code are ported from **WHIP** (whip_core), by Whippy:

    Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.

The ported files are free software under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`), with the
GNU General Public License 3.0 it builds on (`COPYING`). Each carries the line above. PF is not WHIP, is not made by
WHIP's author, and does not use WHIP's name or logo; WHIP's licence covers its code, not its name or logo.

## What is WHIP's

| pf-hud file | From whip_core | How |
|---|---|---|
| `client/radar.lua` | `client/hud.lua` (radar mask, component rects, health/armour bars, car names) | adapted: no WHIP framework calls; a player's saved tuning is read at start |
| `client/skin.lua` | `client/hud_skin.lua` (frame sprite under the HUD, dark tiles, blue route, frame box) | adapted: driven by pf-hud's settings; the tiles only while pfm-media-map runs |
| `client/radar_tuner.lua` | `client/radar_debug.lua` (`/radardebug`) | adapted: `/radartuner`, admin only, values clamped, Save keeps them |
| `client/dial.lua` | `client/vehicle_hud.lua` (the dial's feeder) | adapted: data from pfm-media-map; no WHIP registries or exports |
| `html/js/status-hud.js` | `html/js/status-hud.js`, `html/js/capsule.js` | adapted: classic script; flag gauges, placement, money in the capsule |
| `html/js/vehicle-dial.js` | `html/js/vehicle-dial.js` | adapted: classic script; flat dial without WebGL; layout editor |
| `html/js/radar-tuner.js` | `html/js/radar-debug.js` | adapted: classic script; Save, controller |
| `html/js/vehicle_hud/*.js` | `html/js/vehicle_hud/*.js` (the 3D dial) | verbatim apart from names, comments and the skins' data arriving at run time (`hud.js` `setSkinData`) |
| `html/css/status-hud.css`, `hud-skin.css`, `vehicle-dial.css`, `radar-tuner.css` | the same sheets (`radar-debug.css`) | verbatim apart from names and comments |
| `html/css/base.css`, `html/css/fonts.css` | `html/css/base.css`, `fonts.css` | a subset |
| `stream/pf*.ytd`, `stream_enhanced/pf*.ytd` | `stream*/whipframe_*`, `whipring_*`, `whipmask_*`, `whiphud.ytd` | WHIP's own art, file names changed (the textures inside keep their names: `frame`, `ring`, `radarmasksm`, `disc`) |

The gauge icons for voice, health, armour, hunger, thirst and oxygen are WHIP's SVG paths (client.lua `ICONS`); the
stress, seatbelt and cruise icons are PF's. PF's own code (client.lua, client/prefs.lua, html/app.js,
html/js/router.js, html/css/pf.css, html/preview.html) is offered under the same licence.

Not ported: WHIP's own 3D NUI minimap (`client/minimap.lua`, `html/js/minimap.js`): the native radar stays, dressed
in WHIP's frame and dark map.

## Rockstar Games material is not in this resource

This resource is public, so nothing made from GTA V is in it. The HUD radar's dark tiles, the dashboard looks per car
and the measured rev ranges live in the private resource **pfm-media-map** (see its NOTICE.md), and pf-hud reads them
at run time when it is started. Without it the radar keeps GTA's tiles and the dial its own look.

The old modified minimap scaleform (`stream/minimap.gfx`) and texture dictionary (`stream/minimap.ytd`), and the
earlier mask dictionaries (`circlemap.ytd`, `squaremap.ytd`), were removed: WHIP's approach (the scaleform's
`SETUP_HEALTH_ARMOUR` call and WHIP's own masks) makes them unnecessary.

## Third-party parts

| What | Where | Licence |
|---|---|---|
| three.js r170 (Three.js Authors) | `html/js/vehicle_hud/vendor/three.module.min.js` (its header kept) | MIT |
| Material Design Icons (Pictogrammers): "coolant-temperature" and "car-turbocharger" | `html/js/vehicle_hud/gauges.js` (dial gauge icons) | Apache 2.0 |
| Barlow | `html/fonts/*.woff2`, `html/fonts/OFL-Barlow.txt` | SIL Open Font License 1.1 |
| Roboto, Archivo Narrow, Arimo, Barlow, Barlow Condensed, Michroma, Orbitron, Rajdhani, Russo One, Saira, Saira Condensed, Saira Semi Condensed (subsets) | `html/js/vehicle_hud/fonts/*.woff2`, `html/js/vehicle_hud/fonts/OFL.txt` | SIL Open Font License 1.1 |

WHIP is not affiliated with, endorsed or sponsored by Rockstar Games or Take-Two Interactive; nor is PF.
