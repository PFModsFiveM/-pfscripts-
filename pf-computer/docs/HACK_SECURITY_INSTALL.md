# pf-computer Hack/Security Install

## Recommended stack
- Framework: `qb-core`
- Inventory: `qb-inventory` (native) or `ox_inventory` (supported fallback in server item checks)

## Required config files
Already added:
- `config/config_hack.lua`
- `config/config_dark.lua`

Ensure they are loaded in `fxmanifest.lua` under `shared_scripts`.

## Required items
For `qb-core`, items are added in:
- `[qb]/qb-core/shared/items.lua`

Added items:
- `hack_usb_basic`
- `hack_usb_advanced`
- `hack_usb_master`

## SQL requirements
- No SQL is required for the new lockscreen/hack flow.
- Runtime state is stored in `pf-computer` JSON data and per-computer scoped UI storage.

## If using ox_inventory item definitions
If your server uses standalone `ox_inventory` item files, mirror the same 3 item names there with matching labels/images.

## Restart order
1. `ensure pfm-core`
2. `ensure pf-computer`
3. Restart server or refresh resources so new item definitions are loaded.
