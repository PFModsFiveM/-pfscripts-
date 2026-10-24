# pf-watercontrol

Stops water flooding out-of-bounds builds and MLO basements that sit below sea
level.

## Which tool for which water

GTA V has more than one kind of water, and that's the whole difficulty:

| Water | Where it comes from | What removes it |
| --- | --- | --- |
| Quad water | `water.xml` — the ocean, rivers, the visible surface | `SET_WATER_QUAD_LEVEL`, or a custom `water.xml` |
| Everything else | Collision meshes and drawables, and anything past the quad set — i.e. the out-of-bounds ocean | **`CREATE_DRY_VOLUME`** |

If the water flooding your basement is not described in `water.xml`, sinking
quads does nothing, because there is no quad to sink. You need a **dry volume**.

**Find out which you're dealing with in ten seconds:** stand in the flooded
spot and run `/waterquad`. It prints the quad index under you, or tells you
there isn't one.

## 1. Dry volumes — the usual answer

### What it actually does

FiveM hooks the game's water-physics test (3 call sites) and its
underwater-visuals test (1 call site). Every time the game asks *"is there
water at point P?"*, the hook first checks P against every registered volume
and answers "no water" if it's inside one.

So it's a **point test on the query coordinate**, not a carving-out of the
water body. Inside the box: no swim state, no buoyancy, no drowning, no
underwater screen effect. The water *surface* still renders — that's a
separate code path — which is why this is right for an enclosed basement and
wrong for an open hole in the sea. If you need the surface gone too, add a
quad zone (section 4) on top.

It does not care whether a water quad exists, which is what makes it the fix
for out-of-bounds water.

### Shapes

A single volume is an axis-aligned box — no rotation. But the game calls a
point dry if it's inside **any** volume, so volumes union, and arbitrary
outlines are built by tiling boxes:

```lua
-- box
example_basement = {
    min = vec3(1480.0, 6480.0, -40.0),
    max = vec3(1520.0, 6520.0,  10.0),
},

-- pentagon (or any polygon, convex or concave)
example_pentagon = {
    points = {
        vec2(1500.0, 6540.0),
        vec2(1538.0, 6512.0),
        vec2(1524.0, 6468.0),
        vec2(1476.0, 6468.0),
        vec2(1462.0, 6512.0),
    },
    minZ = -40.0,
    maxZ =  10.0,
    resolution = 4.0,
},
```

`resolution` is the strip height in metres. Smaller hugs the outline more
tightly but costs more boxes, and **every water query scans every box**, so
keep it sane — `Config.MaxBoxesPerVolume` (default 64) refuses anything
sillier. A pentagon at 4.0 is 18 boxes; at 8.0 it's 10.

The tiling puts a strip boundary at every vertex as well as on the regular
grid, so the interior is always fully covered. It errs slightly *outside* the
outline rather than leaving wet gaps inside it.

### Building in-game

- **Box:** `/drybox` at one bottom corner → `/drybox` at the opposite top
  corner. Optional args: `/drybox <headroom> <margin below>` (default 5 and 3).
- **Polygon:** `/drypoint` at each corner, in order → `/drypoly` to close it.
  Optional args: `/drypoly <minZ> <maxZ> <resolution>`.

Both create the volume immediately so you can walk around and check it, and
print a paste-ready block to F8. `/dryshow` draws wireframes of everything
active, `/dryclear` and `/drypolyclear` remove the test ones.

## 2. Clip rect — bluntly cutting water past a boundary

`Config.ClipRect` shrinks the world rectangle outside of which water quads are
allowed to exist at all, then reloads the water. Everything past it is gone.

Requires game build **2189 or newer**. The map runs roughly x −4000..4500,
y −4000..8000, so leave margin or you'll cut real coastline and Cayo Perico.
Note this only bounds *quad* water — it won't help with collision-driven water.

## 3. Custom water.xml

`Config.CustomWaterFile` loads your own `water.xml` in place of the game's via
`LOAD_WATER_FROM_PATH`. Export the original with CodeWalker, delete or resize
the quads you don't want, drop the file in this resource, and add it to
`files{}` in `fxmanifest.lua`. Cleanest permanent fix if you're reshaping the
ocean rather than patching one building.

This changes every quad index, so build your section 4 zones against the new file.

## 4. Water quad zones — removing the visible surface

Only works where a quad exists (`/waterquad` to confirm). Sinks the quads
covering an area while the player is nearby, restores them when they leave.

```lua
my_zone = {
    center     = vec3(x, y, z), -- trigger point
    radius     = 100.0,         -- trigger radius
    areaSize   = 40.0,          -- half-size of the XY box whose quads get cut
    minZ, maxZ = nil, nil,      -- optional: only trigger inside this Z slice
    interiorAt = vec3(x, y, z), -- optional: also trigger while inside that MLO
    interiorOnly = false,       -- true = interior match only, ignore radius
    area       = { minX =, minY =, maxX =, maxY = }, -- explicit cut box
    quads      = { 1204, 1205 },-- explicit quad indices (overrides area)
    sinkTo     = -500.0,
    hide       = true,
    permanent  = false,
    enabled    = true,
}
```

**Trigger wide, cut narrow.** Quads are large — the one under your basement may
also cover ocean visible from the shore. A tight `areaSize` and a generous
`radius` means the water only disappears while someone is actually there.

## Commands (only while `Config.Debug = true`)

| Command | What it does |
| --- | --- |
| `/waterquad` | **Start here.** Quad index + water height under you, or "no quad" |
| `/drybox [up] [down]` | Two-corner box builder; creates it and prints the config |
| `/drypoint` | Adds a polygon corner at your position |
| `/drypoly [minZ] [maxZ] [res]` | Closes the polygon, builds it, prints the config |
| `/dryclear` / `/drypolyclear` | Removes the test box / polygon |
| `/drylist` | Lists active dry volumes and their box counts |
| `/dryshow` | Toggles wireframe rendering of active volumes |
| `/waterscan [size]` | Lists water quads within a box |
| `/waterreload` | Restores quads and rebuilds the cache |

## Exports

```lua
exports['pf-watercontrol']:addDryVolume('house_42', vec3(...), vec3(...))
exports['pf-watercontrol']:addDryPolygon('plaza', { vec2(...), vec2(...), vec2(...) }, minZ, maxZ, resolution)
exports['pf-watercontrol']:removeDryVolume('house_42')
exports['pf-watercontrol']:addZone('house_42', { center = vec3(...), areaSize = 30.0 })
exports['pf-watercontrol']:removeZone('house_42')
exports['pf-watercontrol']:setZoneEnabled('house_42', false)
exports['pf-watercontrol']:removeWaterAt(x, y, size, sinkTo)
exports['pf-watercontrol']:restoreAll()
```

## Notes

- Client-side only, which is what you want: one player's dry basement doesn't
  drain the ocean for everyone else.
- **Dry volume handles are never freed** — removing one marks its slot dead
  rather than reclaiming it. Create them once at startup (as `Config.DryVolumes`
  does); don't add and remove them as players move around.
- The native misbehaves if created while your ped is swimming, so the script
  waits until you're out of the water before creating the configured volumes.
- Travelling to/from Cayo Perico swaps the whole water file and invalidates
  every quad index. The script detects this and rebuilds its cache.
