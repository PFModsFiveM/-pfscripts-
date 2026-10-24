Config = {}

-- Prints diagnostics to F8 and registers the /dry* and /water* build tools.
-- Turn this OFF on your live server.
Config.Debug = true

-- How often (ms) the client re-evaluates dynamic water-quad zones.
Config.Interval = 500

--------------------------------------------------------------------------------
-- 1. DRY VOLUMES
--
-- NOTE: tested against the out-of-bounds ocean at y 8050 and it does NOT work
-- there. The native's docs are accurate: "no effect on waterquads, only water
-- created from drawables and collisions". Out-of-bounds ocean is neither, so
-- the hook never sees it. Use the clip rect in section 2 for that.
--
-- Still useful for water that DOES come from a collision or drawable, e.g. a
-- pool or a water plane baked into a map that floods the room below it.
--
-- A dry volume is a 3D box in which water physics and the underwater screen
-- effect do not happen. No swimming, no buoyancy, no blue overlay.
--
-- It does not delete the visible water surface. Inside an enclosed MLO you
-- never see that surface, so it doesn't matter. If you DO need the surface
-- gone as well, add a quad zone in section 4 on top of this.
--
-- Two shapes:
--
--   BOX      min + max            a single axis-aligned box
--   POLYGON  points + minZ/maxZ   any outline, convex or concave
--
-- The game treats a point as dry if it falls inside ANY volume, so a polygon
-- is tiled into a row of boxes automatically. `resolution` is the height of
-- each strip in metres: smaller hugs the outline more tightly but costs more
-- boxes, and every water query scans every box.
--
-- Build in-game:
--   box     -> /drybox at one bottom corner, /drybox at the opposite top corner
--   polygon -> /drypoint at each corner, then /drypoly to close it
-- Both create the volume immediately and print a paste-ready block to F8.
--------------------------------------------------------------------------------

-- Strip height for polygon tiling, and a sanity cap so a fine polygon over a
-- large area can't quietly register hundreds of boxes.
-- Last resort: while inside any dry volume above, make the PED behave as if
-- there were no water, rather than removing the water. Every frame it clears
-- the swimming config flags (so they walk instead of swim), clears wetness (so
-- they aren't visibly drenched) and stops them drowning.
--
-- This does NOT remove the water. It fights the game's swim state every frame,
-- so it can look rough at the waterline, and it does not remove the underwater
-- screen tint or muffled audio. Use it when the water itself can't be reached.
Config.ForceNoSwim = true

Config.DefaultResolution  = 4.0
Config.MaxBoxesPerVolume  = 64

Config.DryVolumes = {

    -- Names must be unique: a repeated key silently overwrites the earlier one.
    -- Overlapping volumes are fine, they just union.
    my_basement = {
        min = vec3(117.19, 8046.25, -6.59),
        max = vec3(185.63, 8121.96, 8.92),
    },

    my_basement_wide = {
        min = vec3(80.27, 8004.35, -9.85),
        max = vec3(254.18, 8189.44, 6.81),
    },

    -- A plain box.
    -- example_basement = {
    --     min = vec3(1480.0, 6480.0, -40.0),
    --     max = vec3(1520.0, 6520.0,  10.0),
    -- },

    -- A pentagon. Points go in order around the outline; only x and y are read.
    -- example_pentagon = {
    --     points = {
    --         vec2(1500.0, 6540.0),
    --         vec2(1538.0, 6512.0),
    --         vec2(1524.0, 6468.0),
    --         vec2(1476.0, 6468.0),
    --         vec2(1462.0, 6512.0),
    --     },
    --     minZ = -40.0,
    --     maxZ =  10.0,
    --     resolution = 4.0,
    -- },

}

--------------------------------------------------------------------------------
-- 2. WATER AREA CLIP RECT
--
-- The game keeps a world rectangle outside of which water quads are not
-- allowed to exist at all. Shrinking it and reloading the water is a blunt but
-- effective "delete all water past here".
--
-- !! DANGEROUS - DISABLED. Tested 2026-09-23 and it corrupts the water system.
--
-- What we saw: setting a non-default rect and reloading produced water planes
-- stacked at several heights across the whole map, ocean sitting in mid-air
-- over Paleto, and a hard freeze + crash shortly after. An earlier attempt
-- appeared to work -- the out-of-bounds vault went dry -- but that was almost
-- certainly the same corruption seen from a viewpoint where missing water
-- looked like the desired result. It crashed a second later.
--
-- Guesswork as to why: water quad bounds are stored as int16 and the rect is
-- "the maximum allowed coordinates for water quads", so the rect plausibly
-- feeds the world-to-quad coordinate mapping. Reloading water.xml under a rect
-- it was not authored for would then place every quad wrong, which is what the
-- screenshots look like.
--
-- Leave this off. If you ever want to retry it, reconnect first for a clean
-- water state, enable it, restart the resource exactly ONCE, and fly the whole
-- map before trusting it. The script now refuses to reshape water more than
-- once per session, because doing it twice is what produced the worst damage.
--------------------------------------------------------------------------------
Config.ClipRect = {
    enabled = true,
    minX = -4000, minY = -4000,
    maxX =  4500, maxY =  8250,   -- map uses 8000; 8250 reaches past the build
}

--------------------------------------------------------------------------------
-- 3. WATER FILE OVERRIDE  <- the real fix for out-of-bounds water
--
-- A water quad only governs the water where the LOADED water area covers it,
-- and the clip rect that defines that area is only read WHEN WATER IS LOADED.
--
-- This server's map (amb-roxwood-map/water.lua) sets a rect of
--   -4000,-4000 -> 4500,8000
-- and then loads its own water.xml. The build at y 8004..8189 sits just past
-- maxY 8000, i.e. OUTSIDE the water area, where the game draws fallback ocean
-- at z=0 that no quad and no dry volume can touch. That is the flooding.
--
-- So: set a rect that REACHES PAST the build, then load the map's own water
-- file so the rect takes effect. The build then sits inside the water area
-- with no quad over it, which means no water at all - surface and physics.
--
-- Load the MAP'S file, never ResetWater(): that loads the game's vanilla
-- water.xml and throws the map's away, which breaks water server-wide.
--
-- Runs once per session, and waits until you are out of the water first --
-- reloading water while your ped floats in it freezes and crashes the game.
--------------------------------------------------------------------------------
Config.WaterFileOverride = {
    enabled  = true,
    resource = 'amb-roxwood-map', -- whose water.xml to load
    file     = 'water.xml',
}

--------------------------------------------------------------------------------
-- 3b. FILL SPANS
--
-- Side effect of section 3: inside the clip rect, "no quad" means "no water",
-- so the whole strip the rect newly covers (y 8000..8250 across x -4000..4500)
-- goes dry, not just the build. Left alone that reads as a trench: ocean, a
-- 250m dry band, then ocean again north of the rect edge.
--
-- These spans put the ocean back across that band, with a gap from x 40..300
-- so the build at x 80..254 stays dry. Derived from the map's own water.xml:
-- only quad 470 (x -568..-308) already covers part of the band, so the spans
-- below cover everything either side of it except the build.
--
-- Donor quads are ones lying entirely outside the clip rect - already excluded
-- and rendering nothing, so moving them costs nothing. There are 28 available.
--
-- Set enabled = false if you would rather the whole band stayed dry.
--------------------------------------------------------------------------------
Config.FillSpans = {
    enabled = true,
    band    = { minY = 8000, maxY = 8250, level = 0.0 },
    spans   = {
        { minX = -4000, maxX = -568 },  -- up to quad 470
        { minX =  -308, maxX =    40 },  -- quad 470's east edge, up to the build
        { minX =   300, maxX =  4500 },  -- past the build, out to the rect edge
    },
}

--------------------------------------------------------------------------------
-- 4. WATER QUAD ZONES (optional, surface removal)
--
-- Only useful where a water quad actually exists -- check with /waterquad,
-- which prints -1 if the water under you isn't quad-driven. Where a quad does
-- exist, this sinks it out of sight while the player is nearby and restores it
-- when they leave, which removes the visible surface too.
--
-- Trigger wide, cut narrow: quads are large, so keep `areaSize` tight and
-- `radius` generous and nobody ever sees a hole in the sea.
--
-- Fields:
--   center      vec3   trigger point
--   radius      number trigger radius                    (default 75)
--   minZ/maxZ   number only trigger inside this Z slice  (optional)
--   interiorAt  vec3   also trigger while inside the MLO containing this point
--   interiorOnly bool  true = interior match only, ignore radius
--   areaSize    number half-size of the XY box whose quads get cut (default 40)
--   area        table  explicit cut box { minX=, minY=, maxX=, maxY= }
--   quads       table  explicit quad indices (overrides area)
--   sinkTo      number level to push the quads to        (default -500)
--   hide        bool   also mark them invisible          (default true)
--   permanent   bool   apply once on load, never restore
--   enabled     bool   set false to disable without deleting
--------------------------------------------------------------------------------
Config.DefaultRadius   = 75.0
Config.DefaultAreaSize = 40.0
Config.DefaultSinkTo   = -500.0

Config.Zones = {

    -- example_surface = {
    --     center   = vec3(1500.0, 6500.0, 20.0),
    --     radius   = 100.0,
    --     areaSize = 50.0,
    -- },

}
