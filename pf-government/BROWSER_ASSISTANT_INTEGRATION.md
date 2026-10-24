# Browser Assistant Integration Steps

This resource now includes:
- Browser homepage assistant (`assistant:query`)
- Waypoint action (`assistant:setWaypoint`)
- Waypoint-capable business results when business coordinates are present
- Business location persistence (`location_x`, `location_y`, `location_z`, `location_address`)
- Legal-only AI-style search across started resources (manifest/script indexing), jobs, services, and locations

## 1. Apply DB schema updates

If this is a fresh install, run:
- `sql/install.sql`

If this is an existing install, restart `pf-government` once after updating files.
The resource will auto-add missing business columns at runtime:
- `location_x`
- `location_y`
- `location_z`
- `location_address`
- `business_status`
- `closed_at`

## 2. Restart order

Restart in this order:
1. `qb-core`
2. `oxmysql`
3. `pf-government`

## 3. Seed/maintain business location data

Open Government > Businesses > Registry > Create Business and fill:
- `Location X`
- `Location Y`
- `Location Z` (optional)
- `Location Address` (optional)

To update existing businesses:
- Open Government > Businesses
- In Registry row menu, choose `Edit Location`
- Or open `View Details` and click `Edit Location`
- Save coordinates/address

Assistant results for those businesses will then show `Set Waypoint`.

## 4. Verify browser behavior

In-game, open the mayor browser and verify:
- Home button opens `browser://home`
- Assistant chips run searches
- Results include `Open` for pages
- Waypoint-capable results show `Set Waypoint`
- Clicking `Set Waypoint` creates a map route

## 5. Recommended smoke tests

Run these queries in assistant:
- `where is city hall`
- `public notices`
- `tax rates`
- `nearest mechanic`

Expected:
- City locations return waypoint actions
- Portal intents return deep links
- Businesses with stored coordinates return waypoint actions

## 6. Notes

- Businesses without coordinates still appear, but without waypoint action.
- `Config.AccessControl.AllowedLocations` entries are included in assistant location matches.
- The assistant now indexes legal service hints from started resources by reading `fxmanifest.lua` / `__resource.lua` and referenced script files.
- Illegal/drug-related prompts are intentionally blocked with a legal-services-only response.
- Resource indexing is cached for ~5 minutes to reduce query cost.
