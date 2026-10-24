--[[
    pf-watercontrol

    THIS SERVER DEFINES ITS OWN WATER. [roxwood]/amb-roxwood-map/water.lua:

        SetWaterAreaClipRect(-4000, -4000, 4500, 8000)
        LoadWaterFromPath("amb-roxwood-map", "water.xml")

    Read that before touching anything here.

    THE CAUSE of water flooding the out-of-bounds build at y 8004..8189:
    that rect stops at maxY 8000, so the build sits OUTSIDE the water area.
    Outside it the game draws fallback ocean at z=0 which no quad and no dry
    volume can touch - the quad natives only govern water INSIDE the area.
    Hence a quad at level -500 over the build changing nothing, while the same
    trick works fine at the beach.

    THE FIX (Config.ClipRect + Config.WaterFileOverride): set a rect reaching
    past the build, then load the map's own water.xml so the rect takes effect.
    The build then falls inside the water area with no quad over it, which
    means no water at all - surface and physics.

    NEVER call ResetWater() here. It loads the GAME'S vanilla water.xml and
    throws the map's away. Doing that mid-session stacked water planes across
    the map, crashed the game, and left GetWaterQuadCount() at 0 for the rest
    of the session - which made every later quad reading meaningless.

    Reloading water while the local ped floats in it also freezes and crashes
    the game, so the reload is deferred until the player is out of the water.

    Mechanisms, in the order to reach for them:

    1. Dry volumes (CREATE_DRY_VOLUME) - a box where water physics and the
       underwater screen effect are skipped. Per its docs, "no effect on
       waterquads, only water created from drawables and collisions".

    2. Water quad zones (SET_WATER_QUAD_LEVEL) - sinks the visible surface of
       quads covering an area. Needs a populated quad array.

    3. Clip rect / custom water file (SET_WATER_AREA_CLIP_RECT,
       LOAD_WATER_FROM_PATH) - session-wide reshaping. DANGEROUS on this build,
       see above. Disabled in config, hard-limited to one reload per session.

    All client-side. Quad zones restore on stop; a water reload does not, so
    reconnecting is the way back to a clean water state.
]]

local dryVolumes  = {}   -- [name] = { handles = { ... }, boxes = { ... } }
local quadCache   = {}   -- array of cached quad state
local quadByIndex = {}   -- [quadIndex] = cache entry
local quadRefs    = {}   -- [quadIndex] = how many active zones are suppressing it
local zoneState   = {}   -- [zoneId]    = { active = bool, quads = { idx, ... } }
local runtimeZones = {}  -- zones added via exports
local waterFile   = -1   -- which global water file is loaded (mainland vs Cayo)
local lastQuadCount = -1 -- GetWaterQuadCount() at the last cache build
local ready       = false
local lastSwimFix = 0    -- throttle for the stale-swim-task cleanup
local swimFixTries = 0   -- give up clearing swim tasks that refuse to stay cleared
local lastSwimSeen = 0   -- last time the ped was actually swimming
local pendingWater = false -- clip rect / custom file waiting for a safe moment
local seenCount    = -1    -- quad count seen on the previous tick
local waterStableSince = 0 -- when the quad count last changed
local reapplyBudget = 1    -- re-applies allowed if another resource reloads water
local waterWaitStarted = 0 -- when we started waiting for the player to leave water

local function log(fmt, ...)
    if Config.Debug then
        print(('[pf-watercontrol] ' .. fmt):format(...))
    end
end

--------------------------------------------------------------------------------
-- native output helpers
--
-- Measured on build 3258: GetWaterQuadBounds returns 5 values (BOOL retval
-- then the 4 ints) and GetWaterQuadLevel returns 2 (BOOL retval then float).
-- The fallbacks below cover the outputs-only shape in case another artifact
-- differs, but the retval-first shape is the confirmed one.
--------------------------------------------------------------------------------

local function readBounds(idx)
    local a, b, c, d, e = GetWaterQuadBounds(idx)
    if e ~= nil then return a, b, c, d, e end
    return true, a, b, c, d
end

local function readOne(a, b)
    if b ~= nil then return b end
    return a
end

local function truthy(v)
    return v == true or v == 1
end

-- The native is _GET_GLOBAL_WATER_TYPE (0xF741BD853611592D), Lua name
-- GetGlobalWaterType. An earlier version of this file called
-- "GetGlobalWaterFile", which does not exist in the native database at all --
-- it always read as missing, and the fallback below silently hid that. Keep
-- the fallback anyway so a missing native can never kill the startup thread.
local getGlobalWaterType = GetGlobalWaterType or function() return 0 end

--------------------------------------------------------------------------------
-- 1. dry volumes
--
-- CREATE_DRY_VOLUME takes an axis-aligned box and nothing else. But the game
-- tests each point against EVERY registered volume and calls it dry if it
-- falls inside any one of them, so volumes union together -- which means an
-- arbitrary polygon can be built by tiling boxes across it.
--------------------------------------------------------------------------------

-- X coordinates where the horizontal line at `y` crosses the polygon's edges,
-- sorted. Consecutive pairs bracket the inside of the shape, so this handles
-- concave outlines too.
local function crossingsAt(points, y)
    local xs = {}
    local n = #points

    for i = 1, n do
        local a = points[i]
        local b = points[i % n + 1]

        -- Half-open test so a vertex exactly on the line isn't counted twice.
        if (a.y <= y and b.y > y) or (b.y <= y and a.y > y) then
            xs[#xs + 1] = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
        end
    end

    table.sort(xs)
    return xs
end

-- Rasterise a polygon into horizontal strips of axis-aligned boxes.
--
-- Strip boundaries are the regular grid PLUS every vertex's Y. That matters:
-- if a vertex sits in the middle of a strip, the widest part of the shape
-- falls between the two sampled edges and the strip under-covers it, leaving
-- wet gaps inside the polygon. With a boundary at every vertex the outline is
-- straight across each strip, so measuring its two edges is exact.
local function polygonToBoxes(points, minZ, maxZ, res, pad)
    local eps = 0.001

    local minY, maxY = math.huge, -math.huge
    for i = 1, #points do
        minY = math.min(minY, points[i].y)
        maxY = math.max(maxY, points[i].y)
    end

    local bounds = {}
    for i = 1, #points do bounds[#bounds + 1] = points[i].y end

    local y = minY
    while y < maxY do
        bounds[#bounds + 1] = y
        y = y + res
    end
    bounds[#bounds + 1] = maxY

    table.sort(bounds)

    local boxes = {}

    local function emit(x1, x2, y1, y2)
        if x2 - x1 < eps then return end
        boxes[#boxes + 1] = { x1 - pad, y1 - pad, minZ, x2 + pad, y2 + pad, maxZ }
    end

    for i = 1, #bounds - 1 do
        local y1, y2 = bounds[i], bounds[i + 1]

        if y2 - y1 >= eps then
            local lo = crossingsAt(points, y1 + eps)
            local hi = crossingsAt(points, y2 - eps)

            if #lo == #hi and #lo > 0 then
                for j = 1, #lo - 1, 2 do
                    emit(math.min(lo[j], hi[j]), math.max(lo[j + 1], hi[j + 1]), y1, y2)
                end
            else
                -- Span count changed across the strip. Emit both sets;
                -- overlapping boxes are harmless, they just union.
                for _, xs in ipairs({ lo, hi }) do
                    for j = 1, #xs - 1, 2 do
                        emit(xs[j], xs[j + 1], y1, y2)
                    end
                end
            end
        end
    end

    return boxes
end

-- Resolve either shape definition down to a list of boxes.
local function boxesFor(name, vol)
    if vol.points and #vol.points >= 3 then
        local minZ = vol.minZ or (vol.min and vol.min.z)
        local maxZ = vol.maxZ or (vol.max and vol.max.z)

        if not minZ or not maxZ then
            print(('[pf-watercontrol] dry volume "%s" has points but no minZ/maxZ'):format(name))
            return {}
        end

        return polygonToBoxes(vol.points,
            math.min(minZ, maxZ), math.max(minZ, maxZ),
            vol.resolution or Config.DefaultResolution,
            vol.pad or 0.0)
    end

    if vol.min and vol.max then
        return { {
            math.min(vol.min.x, vol.max.x), math.min(vol.min.y, vol.max.y), math.min(vol.min.z, vol.max.z),
            math.max(vol.min.x, vol.max.x), math.max(vol.min.y, vol.max.y), math.max(vol.min.z, vol.max.z),
        } }
    end

    print(('[pf-watercontrol] dry volume "%s" needs either min/max or points+minZ/maxZ'):format(name))
    return {}
end

-- Handles are indices into a list that only ever grows -- removing a volume
-- marks the slot dead rather than freeing it. So create these once at startup,
-- never per player movement.
local function createDryVolume(name, vol)
    if dryVolumes[name] then return dryVolumes[name].handles end

    local boxes = boxesFor(name, vol)
    if #boxes == 0 then return nil end

    -- Every water query scans the whole volume list, so a needlessly fine
    -- polygon costs performance on every entity, every frame.
    if #boxes > Config.MaxBoxesPerVolume then
        print(('[pf-watercontrol] dry volume "%s" needs %d boxes (limit %d) - raise its `resolution`')
            :format(name, #boxes, Config.MaxBoxesPerVolume))
        return nil
    end

    local handles = {}
    for i = 1, #boxes do
        local b = boxes[i]
        handles[i] = CreateDryVolume(b[1], b[2], b[3], b[4], b[5], b[6])
    end

    dryVolumes[name] = { handles = handles, boxes = boxes }
    log('dry volume "%s" created as %d box%s', name, #boxes, #boxes == 1 and '' or 'es')

    return handles
end

local function removeDryVolume(name)
    local vol = dryVolumes[name]
    if not vol then return false end

    for i = 1, #vol.handles do
        RemoveDryVolume(vol.handles[i])
    end

    dryVolumes[name] = nil
    log('dry volume "%s" removed', name)
    return true
end

-- Which active dry volume, if any, contains this point?
local function dryVolumeAt(x, y, z)
    for name, vol in pairs(dryVolumes) do
        for i = 1, #vol.boxes do
            local b = vol.boxes[i]
            if x >= b[1] and x <= b[4] and y >= b[2] and y <= b[5] and z >= b[3] and z <= b[6] then
                return name, i
            end
        end
    end
    return nil
end

-- Is there actually water at this point, per the game itself?
local function waterHere(x, y, z)
    local a, b = GetWaterHeightNoWaves(x, y, z)
    if b ~= nil then return a == true or a == 1, b end
    return a ~= nil, a
end

-- Break a swim task that has outlived the water it was started in.
--
-- A ped that was swimming when the water went away keeps the task: the swim
-- animation carries on over dry ground until something re-tests. Fires when
-- the ped is swimming and either the game reports no water at their feet, or
-- they are inside a dry volume that should be suppressing it.
local function clearStaleSwim(ped)
    local c = GetEntityCoords(ped)
    local hasWater = waterHere(c.x, c.y, c.z)

    if hasWater and not dryVolumeAt(c.x, c.y, c.z) then
        return false -- real water, real swim, leave them alone
    end

    ClearPedTasksImmediately(ped)
    log('cleared a swim task with no water under it')
    return true
end

local function createConfiguredVolumes()
    for name, vol in pairs(Config.DryVolumes) do
        if vol.enabled ~= false then
            createDryVolume(name, vol)
        end
    end

    -- The native's docs warn against creating a volume while the local ped is
    -- swimming. Waiting for that to stop is useless here: a player floating in
    -- out-of-bounds water is exactly who needs the volume. So create it anyway
    -- and clean up the swim state afterwards.
    local ped = PlayerPedId()
    if IsPedSwimming(ped) then
        clearStaleSwim(ped)
    end
end

--------------------------------------------------------------------------------
-- 2. clip rect / custom water file
--------------------------------------------------------------------------------

-- Reshaping water means unloading and reloading the whole water set. Doing it
-- twice in one session produced stacked water planes across the entire map and
-- then a crash, so this is hard-limited to once. The flag lives on the player
-- statebag rather than a local, so a resource restart can't reset it.
local function alreadyReshaped()
    return LocalPlayer.state.pfWaterReshaped == true
end

local function markReshaped()
    LocalPlayer.state:set('pfWaterReshaped', true, false)
end

local function clearReshaped()
    LocalPlayer.state:set('pfWaterReshaped', false, false)
end

local function applyWaterFile()
    local clip = Config.ClipRect
    local custom = Config.WaterFileOverride
    local needsReload = false

    if alreadyReshaped() then
        print('[pf-watercontrol] water was already reshaped this session - refusing to reload again')
        print('[pf-watercontrol] reconnect for a clean water state')
        return false
    end

    -- The clip rect is read when the water file is parsed, so it has to be set
    -- before the (re)load, not after.
    if clip and clip.enabled then
        if clip.maxX < clip.minX or clip.maxY < clip.minY then
            print('[pf-watercontrol] ClipRect is inverted (min must be <= max) - skipping')
        else
            SetWaterAreaClipRect(math.floor(clip.minX), math.floor(clip.minY),
                                 math.floor(clip.maxX), math.floor(clip.maxY))
            needsReload = true
            log('clip rect set to %d %d -> %d %d (needs build 2189+)',
                clip.minX, clip.minY, clip.maxX, clip.maxY)
        end
    end

    if custom and custom.enabled and custom.file then
        local from = custom.resource or GetCurrentResourceName()
        local before = GetWaterQuadCount()
        local ok = LoadWaterFromPath(from, custom.file)

        Wait(1500) -- the load is not instant; let it settle before counting

        local after = GetWaterQuadCount()
        print(('[pf-watercontrol] LoadWaterFromPath("%s", "%s") returned %s | quads %d -> %d')
            :format(from, custom.file, tostring(ok), before, after))

        if ok and after ~= before then
            markReshaped()
            return true
        end

        -- The map file didn't load. That is the normal case on this server --
        -- the map's OWN LoadWaterFromPath doesn't take effect either, which is
        -- why the quad count sits at vanilla's ~1001 rather than its 727.
        --
        -- A clip rect only takes effect when water is loaded, so with no reload
        -- the rect does nothing and the water stays. ResetWater() is the one
        -- reload we've seen actually work. It loads the game's vanilla
        -- water.xml - which costs nothing here, because vanilla is already what
        -- is loaded. (This is safe ONLY while that stays true: if the map's
        -- water ever does load, resetting would throw it away.)
        print('[pf-watercontrol] map water file did not load (returned ' .. tostring(ok) ..
              ', count unchanged) - falling back to ResetWater()')

        if before ~= 0 and before ~= 1001 then
            print('[pf-watercontrol] WARNING: the loaded water does not look like vanilla')
            print(('[pf-watercontrol] (%d quads). ResetWater() would discard it. Skipping.'):format(before))
            return false
        end

        ResetWater()
        Wait(1500)

        local reset = GetWaterQuadCount()
        print(('[pf-watercontrol] ResetWater() done | quads %d -> %d, clip rect now applies')
            :format(after, reset))

        markReshaped()
        return true
    end

    -- Deliberately no ResetWater() fallback. On a server whose map supplies its
    -- own water, resetting loads the GAME'S vanilla water.xml and throws the
    -- map's away - which is what wrecked this client's water earlier. If you
    -- want a reload, point WaterFileOverride at the map's own file instead.
    if needsReload then
        print('[pf-watercontrol] clip rect set, but a clip rect only takes effect when water')
        print('[pf-watercontrol] is LOADED. Set Config.WaterFileOverride so there is something')
        print('[pf-watercontrol] to load, otherwise this does nothing.')
    end

    return false
end

--------------------------------------------------------------------------------
-- 3. water quad cache
--------------------------------------------------------------------------------

local function buildQuadCache()
    quadCache, quadByIndex = {}, {}

    local count = GetWaterQuadCount()
    for i = 0, count - 1 do
        local ok, minX, minY, maxX, maxY = readBounds(i)
        if ok and minX then
            local entry = {
                idx  = i,
                minX = minX + 0.0,
                minY = minY + 0.0,
                maxX = maxX + 0.0,
                maxY = maxY + 0.0,
                level        = readOne(GetWaterQuadLevel(i)) or 0.0,
                invisible    = truthy(readOne(GetWaterQuadIsInvisible(i))),
                limitedDepth = truthy(readOne(GetWaterQuadHasLimitedDepth(i))),
            }
            quadCache[#quadCache + 1] = entry
            quadByIndex[i] = entry
        end
    end

    waterFile = getGlobalWaterType()
    lastQuadCount = count
    return #quadCache
end

local function allZones()
    local out = {}
    for id, zone in pairs(Config.Zones) do out[id] = zone end
    for id, zone in pairs(runtimeZones) do out[id] = zone end
    return out
end

local function suppressQuad(idx, zone)
    local entry = quadByIndex[idx]
    if not entry then return end

    local refs = (quadRefs[idx] or 0) + 1
    quadRefs[idx] = refs
    if refs > 1 then return end -- another active zone already removed it

    SetWaterQuadLevel(idx, zone.sinkTo or Config.DefaultSinkTo)
    if zone.hide ~= false then
        SetWaterQuadIsInvisible(idx, true)
    end
end

local function restoreQuad(idx)
    local entry = quadByIndex[idx]
    if not entry then return end

    local refs = (quadRefs[idx] or 1) - 1
    if refs > 0 then
        quadRefs[idx] = refs
        return
    end

    quadRefs[idx] = nil
    SetWaterQuadBounds(idx, entry.minX, entry.minY, entry.maxX, entry.maxY)
    SetWaterQuadLevel(idx, entry.level)
    SetWaterQuadIsInvisible(idx, entry.invisible)
    SetWaterQuadHasLimitedDepth(idx, entry.limitedDepth)
end

-- Put every suppressed quad back, ignoring ref counts. Must run before any
-- cache rebuild, otherwise we'd memorise the sunk level as the original one.
local function restoreEverything()
    for idx in pairs(quadRefs) do
        local entry = quadByIndex[idx]
        if entry then
            SetWaterQuadBounds(idx, entry.minX, entry.minY, entry.maxX, entry.maxY)
            SetWaterQuadLevel(idx, entry.level)
            SetWaterQuadIsInvisible(idx, entry.invisible)
            SetWaterQuadHasLimitedDepth(idx, entry.limitedDepth)
        end
    end

    quadRefs, zoneState = {}, {}
end

-- FILL SPANS
--
-- Bringing the build inside the clip rect has a cost: inside the rect, "no
-- quad" means "no water", so the whole strip the rect newly covers goes dry,
-- not just the build. That reads as a trench - ocean, dry band, then ocean
-- again past the rect edge.
--
-- So put the ocean back across that strip with quads, leaving a gap over the
-- build. Donors are quads lying entirely OUTSIDE the clip rect: they are
-- already excluded and render nothing, so moving them costs nothing.

local function outsideClipRect(q, clip)
    return q.maxX < clip.minX or q.minX > clip.maxX
        or q.maxY < clip.minY or q.minY > clip.maxY
end

local function applyFillSpans()
    local fill = Config.FillSpans
    local clip = Config.ClipRect
    if not (fill and fill.enabled and clip and clip.enabled and fill.band and fill.spans) then
        return
    end

    local donors = {}
    for i = 1, #quadCache do
        local q = quadCache[i]
        if outsideClipRect(q, clip) and not quadRefs[q.idx] then
            donors[#donors + 1] = q.idx
        end
    end

    local band, used = fill.band, 0

    for i = 1, #fill.spans do
        local span = fill.spans[i]
        local idx = donors[used + 1]

        if not idx then
            print(('[pf-watercontrol] out of spare quads: %d of %d fill spans applied;')
                :format(used, #fill.spans))
            print('[pf-watercontrol] the unfilled part of the band will be dry.')
            break
        end

        quadRefs[idx] = (quadRefs[idx] or 0) + 1
        SetWaterQuadBounds(idx, math.floor(span.minX), math.floor(band.minY),
                                math.ceil(span.maxX), math.ceil(band.maxY))
        SetWaterQuadLevel(idx, band.level or 0.0)
        SetWaterQuadIsInvisible(idx, false)
        used = used + 1
    end

    if used > 0 then
        log('filled %d span(s) of the y %d..%d band, leaving the build dry',
            used, band.minY, band.maxY)
    end
end

local function zoneArea(zone)
    if zone.area then return zone.area end

    local c = zone.center or zone.interiorAt
    if not c then return nil end

    local size = zone.areaSize or Config.DefaultAreaSize
    return { minX = c.x - size, minY = c.y - size, maxX = c.x + size, maxY = c.y + size }
end

local function quadsInArea(area)
    local out = {}
    for i = 1, #quadCache do
        local q = quadCache[i]
        if q.minX <= area.maxX and q.maxX >= area.minX
        and q.minY <= area.maxY and q.maxY >= area.minY then
            out[#out + 1] = q.idx
        end
    end
    return out
end

local function activateZone(id, zone)
    local quads = zone.quads or quadsInArea(zoneArea(zone) or { minX = 0, minY = 0, maxX = 0, maxY = 0 })
    for i = 1, #quads do
        suppressQuad(quads[i], zone)
    end

    zoneState[id] = { active = true, quads = quads }
    log('zone "%s" ON (%d quad%s)', id, #quads, #quads == 1 and '' or 's')
end

local function deactivateZone(id)
    local state = zoneState[id]
    if not state or not state.active then return end

    for i = 1, #state.quads do
        restoreQuad(state.quads[i])
    end

    zoneState[id] = nil
    log('zone "%s" OFF', id)
end

local function shouldBeActive(zone, coords, interiorId)
    -- Interior match: resolve the MLO id from a point inside it, once.
    if zone.interiorAt then
        if not zone._interiorId or zone._interiorId == 0 then
            zone._interiorId = GetInteriorAtCoords(zone.interiorAt.x, zone.interiorAt.y, zone.interiorAt.z)
        end

        if zone._interiorId ~= 0 and interiorId == zone._interiorId then
            return true
        end

        if zone.interiorOnly then return false end
    end

    if not zone.center then return false end
    if zone.maxZ and coords.z > zone.maxZ then return false end
    if zone.minZ and coords.z < zone.minZ then return false end

    local radius = zone.radius or Config.DefaultRadius
    local dx = coords.x - zone.center.x
    local dy = coords.y - zone.center.y

    return (dx * dx + dy * dy) <= (radius * radius)
end

local function applyPermanentZones()
    for id, zone in pairs(allZones()) do
        if zone.enabled ~= false and zone.permanent and not zoneState[id] then
            activateZone(id, zone)
        end
    end
end

--------------------------------------------------------------------------------
-- startup + main loop
--------------------------------------------------------------------------------

CreateThread(function()
    -- Dry volumes don't depend on the quad array, so set them up before we go
    -- anywhere near it. Previously they sat behind the quad wait, which meant
    -- a client with no quads loaded got no dry volumes either.
    Wait(500)
    createConfiguredVolumes()

    -- Then wait for quads, but don't block forever. A client whose quad array
    -- never populates (corrupted session, or a game build FiveM's pattern scan
    -- doesn't resolve on) would otherwise hang here and never start the loop.
    local waited = 0
    while GetWaterQuadCount() <= 0 and waited < 30000 do
        Wait(250)
        waited = waited + 250
        if waited % 10000 == 0 then
            print(('[pf-watercontrol] waiting for water quads (%ds) - GetWaterQuadCount() is 0')
                :format(waited / 1000))
        end
    end

    if GetWaterQuadCount() <= 0 then
        print('[pf-watercontrol] no water quads loaded on this client.')
        print('[pf-watercontrol] every quad-based feature is inert; /waterquad will say -1 everywhere.')
        print('[pf-watercontrol] check a normal ocean spot with /waterquad to tell a broken session')
        print('[pf-watercontrol] apart from FiveM not resolving the quad array on this game build.')
    end

    -- Reshaping the water tears it down and rebuilds it. Doing that while the
    -- local ped is in the water being removed leaves physics referencing water
    -- that no longer exists, and the game freezes and dies. So don't do it
    -- here -- flag it and let the main loop apply it the moment we're on dry
    -- land. The cache is rebuilt then too, since reloading reindexes quads.
    if (Config.ClipRect and Config.ClipRect.enabled)
    or (Config.WaterFileOverride and Config.WaterFileOverride.enabled) then
        pendingWater = true
    end

    local cached = buildQuadCache()
    ready = true
    log('cached %d water quads (water file %d)', cached, waterFile)

    applyPermanentZones()

    while true do
        -- Going to / leaving Cayo Perico swaps the whole water file, which
        -- invalidates every cached index. Rebuild instead of restoring stale ones.
        -- Another resource can swap the whole water set after we cached it --
        -- a map calling LoadWaterFromPath at its own start, for instance, which
        -- is exactly what happens on this server. _GET_GLOBAL_WATER_TYPE alone isn't
        -- available here to detect that, so watch the quad count instead.
        -- Compare against the count we last saw, not #quadCache: quads that
        -- fail to read are skipped, so #quadCache can legitimately be smaller
        -- and comparing to it would rebuild on every tick forever.
        local nowCount = GetWaterQuadCount()

        if getGlobalWaterType() ~= waterFile or nowCount ~= lastQuadCount then
            -- Never rebuild while we're holding modified quads: the rebuild
            -- would read our own edits back as their "original" values, and
            -- restoring afterwards would put the game's water back wrong.
            if next(quadRefs) ~= nil then
                lastQuadCount = nowCount
                print('[pf-watercontrol] water changed while quads are modified - not rebuilding.')
                print('[pf-watercontrol] restore them first (/quadrestore, /waterreload) to resync.')
            else
                zoneState = {}
                buildQuadCache()
                applyPermanentZones()
                log('water changed underneath us -> rebuilt cache (%d of %d quads)', #quadCache, nowCount)
            end
        end

        local ped      = PlayerPedId()
        local coords   = GetEntityCoords(ped)
        local interior = GetInteriorFromEntity(ped)

        -- Apply a deferred clip rect / custom water file as soon as it's safe.
        -- Wait for the water to stop changing before reshaping it. The map
        -- resource loads its own water at ITS start, which may be after ours;
        -- applying first would just be silently undone a moment later.
        if nowCount ~= seenCount then
            seenCount = nowCount
            waterStableSince = GetGameTimer()

            -- Someone reloaded the water after we had already reshaped it.
            -- Re-arm once so our changes go back on top.
            if not pendingWater and alreadyReshaped() and reapplyBudget > 0 then
                reapplyBudget = reapplyBudget - 1
                clearReshaped()
                pendingWater = true
                log('water was reloaded by another resource - re-applying ours')
            end
        end

        if pendingWater and GetGameTimer() - waterStableSince > 10000 then
            local inWater = IsPedSwimming(ped) or IsEntityInWater(ped)

            -- Waiting to be out of the water deadlocks for the very player
            -- this is meant to help: someone standing in a flooded basement is
            -- ALWAYS in water, so the reshape would never run. Reloading water
            -- under a floating ped crashes the game, so lift them clear, do it,
            -- and put them back.
            local lifted, proceed = false, true

            if inWater then
                if waterWaitStarted == 0 then
                    waterWaitStarted = GetGameTimer()
                end

                if GetGameTimer() - waterWaitStarted > 15000 then
                    lifted = true   -- waited long enough; lift them out instead
                else
                    proceed = false -- give them a moment to walk out on their own
                end
            end

            if proceed then
                pendingWater = false

                local home = GetEntityCoords(ped)
                if lifted then
                    log('you have been in water for 15s - lifting you clear to reshape it')
                    SetEntityCoords(ped, home.x, home.y, home.z + 150.0, false, false, false, true)
                    FreezeEntityPosition(ped, true)
                    Wait(1500)
                end

                applyWaterFile()
                Wait(250)
                buildQuadCache()
                applyFillSpans()
                log('water reshaped, %d quads now loaded', #quadCache)

                if lifted then
                    FreezeEntityPosition(ped, false)
                    SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, true)
                end
            end
        end


        -- Someone who swims into the area can keep a swim task the water test
        -- no longer justifies. Clearing it only helps if the volume is actually
        -- working: if the ped is still swimming after a few tries, the water is
        -- real and retrying forever just rips them out of their animation every
        -- few seconds. So give up and say why, and only rearm once they're dry.
        -- Only rearm after a sustained dry spell. Clearing the task makes
        -- IsPedSwimming false for a single tick, so resetting on that alone
        -- let the counter reset every attempt and the "give up" never fired --
        -- which is the stutter of dropping out of the swim animation for a
        -- split second, over and over.
        if IsPedSwimming(ped) then
            lastSwimSeen = GetGameTimer()
        elseif GetGameTimer() - lastSwimSeen > 10000 then
            swimFixTries = 0
        end

        if IsPedSwimming(ped) and swimFixTries < 3 and GetGameTimer() - lastSwimFix > 3000 then
            if clearStaleSwim(ped) then
                lastSwimFix = GetGameTimer()
                swimFixTries = swimFixTries + 1

                if swimFixTries >= 3 then
                    print('[pf-watercontrol] still swimming after 3 clears - the dry volume is not')
                    print('[pf-watercontrol] suppressing this water. Giving up so you can play.')
                end
            end
        end

        for id, zone in pairs(allZones()) do
            if zone.enabled ~= false and not zone.permanent then
                local want   = shouldBeActive(zone, coords, interior)
                local state  = zoneState[id]
                local active = state ~= nil and state.active

                if want and not active then
                    activateZone(id, zone)
                elseif not want and active then
                    deactivateZone(id)
                end
            end
        end

        Wait(Config.Interval)
    end
end)

--------------------------------------------------------------------------------
-- 4. force-no-swim (last resort)
--
-- Everything above tries to remove the water. This doesn't: it stops the PED
-- entering the swim state while inside a configured dry volume, by clearing
-- CPED_CONFIG_FLAG_IsSwimming (65) and friends every frame.
--
-- It is a workaround, not a fix. The game re-sets those flags from the water
-- test each frame, so this fights it continuously -- expect it to look rough
-- at the waterline, and expect no underwater screen effect change. But where
-- the water itself is unreachable and the surface is already hidden by the
-- clip rect, it's what makes the basement walkable.
--------------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500

        if Config.ForceNoSwim then
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)

            if dryVolumeAt(c.x, c.y, c.z) then
                sleep = 0

                SetPedConfigFlag(ped, 65, false)  -- IsSwimming
                SetPedConfigFlag(ped, 66, false)  -- WasSwimming
                SetPedConfigFlag(ped, 3,  false)  -- DrownsInWater

                -- Otherwise they walk around visibly drenched, which gives the
                -- whole thing away. Height 0 stops it re-applying, ClearPedWetness
                -- removes what's already on the clothes.
                SetPedWetnessHeight(ped, 0.0)
                ClearPedWetness(ped)

                -- Belt and braces: with DrownsInWater off they shouldn't drown,
                -- but the underwater timer still ticks down and drives the
                -- gasping-for-air audio and HUD.
                SetPedMaxTimeUnderwater(ped, 50.0)
            end
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end

    for volName in pairs(dryVolumes) do
        removeDryVolume(volName)
    end

    restoreEverything()

    -- Deliberately NOT calling ResetWater() here. It would be the second water
    -- reload of the session on any resource restart, and a second reload is
    -- what stacked water planes across the map and crashed the game. The water
    -- state is restored by reconnecting; FiveM resets the clip rect itself on
    -- disconnect.
    if (Config.WaterFileOverride and Config.WaterFileOverride.enabled)
    or (Config.ClipRect and Config.ClipRect.enabled) then
        print('[pf-watercontrol] water was reshaped this session - reconnect to restore it')
    end
end)

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

exports('addDryVolume', function(name, min, max)
    if type(name) ~= 'string' or not min or not max then return nil end
    return createDryVolume(name, { min = min, max = max })
end)

-- points: array of vec2/vec3 (only x and y are read), in order around the shape.
exports('addDryPolygon', function(name, points, minZ, maxZ, resolution)
    if type(name) ~= 'string' or type(points) ~= 'table' or #points < 3 then return nil end
    return createDryVolume(name, {
        points = points, minZ = minZ, maxZ = maxZ, resolution = resolution,
    })
end)

exports('removeDryVolume', function(name)
    return removeDryVolume(name)
end)

exports('addZone', function(id, zone)
    if type(id) ~= 'string' or type(zone) ~= 'table' then return false end
    runtimeZones[id] = zone
    return true
end)

exports('removeZone', function(id)
    deactivateZone(id)
    runtimeZones[id] = nil
    return true
end)

exports('setZoneEnabled', function(id, enabled)
    local zone = runtimeZones[id] or Config.Zones[id]
    if not zone then return false end
    zone.enabled = enabled and true or false
    if not enabled then deactivateZone(id) end
    return true
end)

exports('removeWaterAt', function(x, y, size, sinkTo)
    if not ready then return 0 end

    size = size or Config.DefaultAreaSize
    local quads = quadsInArea({ minX = x - size, minY = y - size, maxX = x + size, maxY = y + size })
    for i = 1, #quads do
        suppressQuad(quads[i], { sinkTo = sinkTo or Config.DefaultSinkTo, hide = true })
    end
    return #quads
end)

exports('restoreAll', function()
    restoreEverything()
    return true
end)

--------------------------------------------------------------------------------
-- build tools (Config.Debug only)
--------------------------------------------------------------------------------

if not Config.Debug then return end

local function say(msg)
    print('[pf-watercontrol] ' .. msg)
    TriggerEvent('chat:addMessage', { args = { 'water', msg } })
end

-- GET_WATER_QUAD_AT_COORDS_3D's generated Lua name varies by artifact, so
-- resolve whichever spelling this build exposes instead of assuming one.
local getQuad3d = GetWaterQuadAtCoords3d or GetWaterQuadAtCoords3D or GetWaterQuadAtCoords_3d

-- Is the water under the player quad-driven, or the out-of-bounds ocean?
RegisterCommand('waterquad', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local flat = GetWaterQuadAtCoords(c.x, c.y)
    local vol  = getQuad3d and getQuad3d(c.x, c.y, c.z) or nil
    local hasWater, height = waterHere(c.x, c.y, c.z)

    local dryName, dryBox = dryVolumeAt(c.x, c.y, c.z)
    local swimming = IsPedSwimming(ped)

    print(('[pf-watercontrol] at %.1f, %.1f, %.1f'):format(c.x, c.y, c.z))
    print(('  quad (2d): %d   quad (3d): %s')
        :format(flat or -1, vol and tostring(vol) or 'n/a'))

    -- The distinction that matters here: the surface can be gone while the
    -- physics water is still present. "physics water: YES" with nothing
    -- visible means the render was removed but the swim volume was not.
    print(('  physics water here: %s   height: %s')
        :format(hasWater and 'YES' or 'no',
            type(height) == 'number' and ('%.2f'):format(height) or 'n/a'))
    print(('  dry volume here: %s   ped swimming: %s')
        :format(dryName and ('"%s" (box %d)'):format(dryName, dryBox) or 'NONE',
            swimming and 'YES' or 'no'))

    -- The one combination that means the dry volume isn't doing its job.
    if dryName and swimming then
        print('  -> inside a dry volume but still swimming: the volume is not taking effect')
    end

    if flat and flat >= 0 then
        local q = quadByIndex[flat]
        if q then
            print(('  bounds %.1f %.1f -> %.1f %.1f | cached original level %.2f | suppressed: %s')
                :format(q.minX, q.minY, q.maxX, q.maxY, q.level, quadRefs[flat] and 'yes' or 'no'))
        end

        -- Read the level back from the game, not from our cache. If a write
        -- didn't take, this is the only place it shows up -- and mistaking a
        -- failed write for "quads don't affect physics" would be the wrong
        -- conclusion entirely.
        local okL, liveLevel = GetWaterQuadLevel(flat)
        if liveLevel == nil then okL, liveLevel = true, okL end
        print(('  LIVE level of quad %d per the game: %s')
            :format(flat, type(liveLevel) == 'number' and ('%.2f'):format(liveLevel) or tostring(liveLevel)))
        say(('quad %d here - a water quad zone will work'):format(flat))
    else
        say('no water quad here - use a dry volume (/drybox), quad zones will not help')
    end
end, false)

RegisterCommand('waterscan', function(_, args)
    local size = tonumber(args[1]) or Config.DefaultAreaSize
    local c = GetEntityCoords(PlayerPedId())
    local quads = quadsInArea({ minX = c.x - size, minY = c.y - size, maxX = c.x + size, maxY = c.y + size })

    print(('[pf-watercontrol] %d quad(s) within %.0fm of %.1f, %.1f:'):format(#quads, size, c.x, c.y))
    for i = 1, #quads do
        local q = quadByIndex[quads[i]]
        print(('  quad %-5d  x %8.1f .. %8.1f   y %8.1f .. %8.1f   level %7.2f')
            :format(q.idx, q.minX, q.maxX, q.minY, q.maxY, q.level))
    end
    say(('%d quad(s) listed in F8'):format(#quads))
end, false)

-- Two-corner dry volume builder.
local corner = nil
RegisterCommand('drybox', function(_, args)
    local c = GetEntityCoords(PlayerPedId())

    if not corner then
        corner = c
        say(('corner 1 set at %.1f %.1f %.1f - walk to the opposite corner and run /drybox again')
            :format(c.x, c.y, c.z))
        return
    end

    local padUp   = tonumber(args[1]) or 5.0  -- headroom above the higher corner
    local padDown = tonumber(args[2]) or 3.0  -- margin below the lower corner

    local minX, maxX = math.min(corner.x, c.x), math.max(corner.x, c.x)
    local minY, maxY = math.min(corner.y, c.y), math.max(corner.y, c.y)
    local minZ, maxZ = math.min(corner.z, c.z) - padDown, math.max(corner.z, c.z) + padUp

    print('[pf-watercontrol] paste into Config.DryVolumes:')
    print('')
    print('    my_basement = {')
    print(('        min = vec3(%.2f, %.2f, %.2f),'):format(minX, minY, minZ))
    print(('        max = vec3(%.2f, %.2f, %.2f),'):format(maxX, maxY, maxZ))
    print('    },')
    print('')

    -- Create it right away so it can be walked through immediately.
    removeDryVolume('__drybox')
    createDryVolume('__drybox', { min = vec3(minX, minY, minZ), max = vec3(maxX, maxY, maxZ) })

    corner = nil
    say('dry volume created and printed to F8 - /dryclear to remove it')
end, false)

RegisterCommand('dryclear', function()
    corner = nil
    if removeDryVolume('__drybox') then
        say('test dry volume removed')
    else
        say('no test dry volume active')
    end
end, false)

-- Polygon builder: drop a point at each corner, then close the shape.
local poly = {}
RegisterCommand('drypoint', function()
    local c = GetEntityCoords(PlayerPedId())
    poly[#poly + 1] = c
    say(('point %d at %.1f %.1f (z %.1f) - /drypoly to close, /drypolyclear to start over')
        :format(#poly, c.x, c.y, c.z))
end, false)

RegisterCommand('drypolyclear', function()
    poly = {}
    removeDryVolume('__drypoly')
    say('polygon points cleared')
end, false)

RegisterCommand('drypoly', function(_, args)
    if #poly < 3 then
        say(('need at least 3 points, have %d - use /drypoint'):format(#poly))
        return
    end

    -- Default the Z range to the points themselves plus head/foot room.
    local lo, hi = math.huge, -math.huge
    for i = 1, #poly do
        lo = math.min(lo, poly[i].z)
        hi = math.max(hi, poly[i].z)
    end

    local minZ = tonumber(args[1]) or (lo - 3.0)
    local maxZ = tonumber(args[2]) or (hi + 5.0)
    local res  = tonumber(args[3]) or Config.DefaultResolution

    removeDryVolume('__drypoly')
    local handles = createDryVolume('__drypoly', {
        points = poly, minZ = minZ, maxZ = maxZ, resolution = res,
    })

    if not handles then
        say('could not build polygon - see F8')
        return
    end

    print('[pf-watercontrol] paste into Config.DryVolumes:')
    print('')
    print('    my_shape = {')
    print('        points = {')
    for i = 1, #poly do
        print(('            vec2(%.2f, %.2f),'):format(poly[i].x, poly[i].y))
    end
    print('        },')
    print(('        minZ = %.2f,'):format(minZ))
    print(('        maxZ = %.2f,'):format(maxZ))
    print(('        resolution = %.1f,'):format(res))
    print('    },')
    print('')

    say(('polygon built from %d points as %d box(es) - printed to F8')
        :format(#poly, #dryVolumes['__drypoly'].boxes))
end, false)

-- Rebuild the configured volumes without restarting the resource. Handles are
-- never reclaimed, so this grows the game's volume list each time -- fine while
-- iterating, restart the resource once you're done.
RegisterCommand('dryreload', function()
    for name in pairs(Config.DryVolumes) do
        removeDryVolume(name)
    end

    createConfiguredVolumes()

    local n = 0
    for _ in pairs(dryVolumes) do n = n + 1 end
    say(('recreated %d configured dry volume(s)'):format(n))
end, false)

RegisterCommand('drylist', function()
    local n = 0
    for name, vol in pairs(dryVolumes) do
        print(('[pf-watercontrol] dry volume "%s" -> %d box(es), handles %s')
            :format(name, #vol.boxes, table.concat(vol.handles, ', ')))
        n = n + 1
    end
    say(('%d dry volume(s) active'):format(n))
end, false)

-- Wireframe preview of every dry volume that actually got created.
local showing = false
RegisterCommand('dryshow', function()
    showing = not showing
    say(showing and 'drawing dry volumes' or 'stopped drawing dry volumes')

    if not showing then return end

    local edges = {
        {1,2},{2,3},{3,4},{4,1},
        {5,6},{6,7},{7,8},{8,5},
        {1,5},{2,6},{3,7},{4,8},
    }

    CreateThread(function()
        while showing do
            local origin = GetEntityCoords(PlayerPedId())

            for _, vol in pairs(dryVolumes) do
                for i = 1, #vol.boxes do
                    local b = vol.boxes[i]
                    local cx, cy = (b[1] + b[4]) * 0.5, (b[2] + b[5]) * 0.5

                    if #(origin - vec3(cx, cy, origin.z)) < 300.0 then
                        local corners = {
                            { b[1], b[2], b[3] }, { b[4], b[2], b[3] }, { b[4], b[5], b[3] }, { b[1], b[5], b[3] },
                            { b[1], b[2], b[6] }, { b[4], b[2], b[6] }, { b[4], b[5], b[6] }, { b[1], b[5], b[6] },
                        }
                        for e = 1, #edges do
                            local p, q = corners[edges[e][1]], corners[edges[e][2]]
                            DrawLine(p[1], p[2], p[3], q[1], q[2], q[3], 0, 200, 255, 200)
                        end
                    end
                end
            end

            Wait(0)
        end
    end)
end, false)

--------------------------------------------------------------------------------
-- experiments for water that isn't quad-driven and ignores dry volumes
--------------------------------------------------------------------------------

-- The clip rect experiment lived here. It is gone on purpose: every one of
-- those commands called ResetWater(), and reloading the water a second time in
-- a session stacked water planes across the whole map and then crashed the
-- game. There is no safe way to toggle this live. If you want to retry the
-- clip rect, reconnect, set Config.ClipRect.enabled, and restart the resource
-- once. MODIFY_WATER was also tested here and had no effect on out-of-bounds
-- water, so it is gone too.

--------------------------------------------------------------------------------
-- Does defining a quad over out-of-bounds water suppress it?
--
-- This is the assumption the custom-water.xml plan depends on: that the game
-- falls back to default ocean only where no quad is defined, so an explicit
-- quad at a low level would win. Rather than spend hours in CodeWalker to find
-- out, borrow a quad that already exists, move it over your area and sink it.
--
-- Nothing is reloaded, so there is no corruption or crash risk, and
-- /quadrestore puts the quad back exactly where it was.
--
-- Side effect while testing: water vanishes wherever the borrowed quad used to
-- be. That is expected, and is itself proof the manipulation is taking effect.
--------------------------------------------------------------------------------
-- Is the client actually receiving the edited Roxwood water files, or a stale
-- cached copy? FiveM hashes a resource's files when the RESOURCE starts, so
-- editing them on disk without restarting that resource server-side leaves
-- clients downloading the old content no matter how often they reconnect.
RegisterCommand('checkwaterfile', function(_, args)
    local res = args[1] or 'amb-roxwood-map'

    local lua = LoadResourceFile(res, 'water.lua')
    if lua then
        local rect = lua:match('SetWaterAreaClipRect%b()')
        print(('[pf-watercontrol] %s/water.lua on this client: %s'):format(res, rect or '(no clip rect call found)'))
    else
        print(('[pf-watercontrol] could not read %s/water.lua from this client'):format(res))
    end

    local xml = LoadResourceFile(res, 'water.xml')
    if not xml then
        print(('[pf-watercontrol] could not read %s/water.xml from this client'):format(res))
        say('client has no readable water.xml - see F8')
        return
    end

    local first = xml:match('<Item>.-</Item>')
    local _, items = xml:gsub('<Item>', '')

    print(('  water.xml: %d bytes, %d quad items'):format(#xml, items))
    print('  first quad in the CLIENT copy:')
    print('    ' .. (first and first:gsub('%s+', ' ') or 'n/a'))

    say('client water file dumped to F8')
end, false)

-- The three steps that have to happen together.
--
-- A quad only governs the water where the LOADED water area covers it, and the
-- clip rect only takes effect when water is loaded. Roxwood sets the rect and
-- then calls LoadWaterFromPath, which isn't taking effect here (the quad count
-- stays at vanilla's 1001, not its 727), so the rect never applied and the
-- build sits outside the water area - which is why a quad at -500 over it did
-- nothing while the same trick works at the beach.
--
-- So: set the rect, force a reload so it applies, then put a quad over the
-- area. Reloading vanilla costs nothing because vanilla is what's loaded.
local fixApplied = false

RegisterCommand('fixvault', function(_, args)
    if fixApplied then
        say('already applied this session - reconnect before running it again')
        return
    end

    CreateThread(function()
        fixApplied = true

        local size = tonumber(args[1]) or 150.0
        local ped  = PlayerPedId()
        local home = GetEntityCoords(ped)

        say('applying clip rect + reload + quad override - you will be lifted briefly')

        -- Reloading water while the ped is floating in it is what crashed the
        -- game before. Get well clear of it first.
        SetEntityCoords(ped, home.x, home.y, home.z + 150.0, false, false, false, true)
        FreezeEntityPosition(ped, true)
        Wait(1500)

        -- Load the MAP'S water file, not ResetWater() (which loads vanilla
        -- and throws the map's water away).
        local ov = Config.WaterFileOverride
        SetWaterAreaClipRect(Config.ClipRect.minX, Config.ClipRect.minY,
                             Config.ClipRect.maxX, Config.ClipRect.maxY)
        local ok = LoadWaterFromPath(ov.resource, ov.file)
        print(('[pf-watercontrol] LoadWaterFromPath -> %s'):format(tostring(ok)))
        Wait(2500)

        buildQuadCache()
        print(('[pf-watercontrol] after reload: %d quads cached'):format(#quadCache))

        -- Borrow the furthest quad, so the hole it leaves is nowhere anyone is.
        local best, bestD
        for i = 1, #quadCache do
            local q = quadCache[i]
            local cx, cy = (q.minX + q.maxX) * 0.5, (q.minY + q.maxY) * 0.5
            local d = (cx - home.x) ^ 2 + (cy - home.y) ^ 2
            if not bestD or d > bestD then best, bestD = q, d end
        end

        if best then
            SetWaterQuadBounds(best.idx,
                math.floor(home.x - size), math.floor(home.y - size),
                math.ceil(home.x + size), math.ceil(home.y + size))
            SetWaterQuadLevel(best.idx, -500.0)
            print(('  quad %d moved over the area at level -500 (was %.0fm away)')
                :format(best.idx, math.sqrt(bestD)))
        else
            print('  no quads available to borrow')
        end

        FreezeEntityPosition(ped, false)
        SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, true)
        Wait(3000)

        local c = GetEntityCoords(ped)
        local hasWater = waterHere(c.x, c.y, c.z)
        local swim = IsPedSwimming(ped)

        print(('  RESULT: physics water: %s   swimming: %s')
            :format(hasWater and 'YES' or 'no', swim and 'YES' or 'no'))
        say(swim and 'still swimming - see F8' or 'NOT swimming - it worked')
    end)
end, false)

-- Control test: do dry volumes work AT ALL, on ordinary water?
--
-- Every dry volume failure so far has been at the out-of-bounds build, which
-- can't distinguish "this water is special" from "dry volumes are broken on
-- this client". This samples the same ordinary ocean twice - once clear of any
-- volume, once inside one - and compares. You get moved briefly and put back.
RegisterCommand('beachtest', function()
    CreateThread(function()
        local ped  = PlayerPedId()
        local home = GetEntityCoords(ped)

        -- Centre of the configured beach box, and a point just outside it in
        -- the same body of water.
        local inside  = vec3(-370.2, -3516.0, 0.0)
        local outside = vec3(-370.2, -3450.0, 0.0)

        local function sample(label, p)
            SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, true)
            Wait(4000) -- let the ped settle and the swim state resolve

            local c = GetEntityCoords(ped)
            local hasWater = waterHere(c.x, c.y, c.z)
            local dry = dryVolumeAt(c.x, c.y, c.z)
            local swim = IsPedSwimming(ped)

            print(('  %-7s at %.1f %.1f %.1f | water: %-3s | dry volume: %-18s | swimming: %s')
                :format(label, c.x, c.y, c.z,
                    hasWater and 'YES' or 'no',
                    dry and ('"' .. dry .. '"') or 'NONE',
                    swim and 'YES' or 'no'))

            return swim, hasWater, dry
        end

        say('control test running - you will be moved for ~10s and put back')
        print('[pf-watercontrol] ---- dry volume control test on ORDINARY ocean ----')

        local swimOut, waterOut = sample('OUTSIDE', outside)
        local swimIn,  waterIn,  dryIn = sample('INSIDE', inside)

        SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, true)

        print('  verdict:')
        if not waterOut and not waterIn then
            print('    neither sample landed in water - coords are wrong, test says nothing')
        elseif not dryIn then
            print('    the INSIDE sample was not in a dry volume - is the beach box configured?')
        elseif swimOut and not swimIn then
            print('    dry volumes WORK on ordinary water (swimming outside, dry inside).')
            print('    So the out-of-bounds water is a kind nothing in the water system reaches.')
        elseif swimIn then
            print('    dry volumes DO NOT WORK even on ordinary water, where they are')
            print('    documented to. This is a client/artifact problem, not your map.')
        else
            print('    inconclusive - neither sample was swimming, see the rows above')
        end

        say('control test done - verdict in F8')
    end)
end, false)

-- Raw state dump. Run this when something reports "no quads" or otherwise
-- behaves as if the script never started.
RegisterCommand('waterdebug', function()
    print('[pf-watercontrol] ---- diagnostics ----')
    print(('  startup finished (ready): %s'):format(tostring(ready)))
    print(('  #quadCache: %d'):format(#quadCache))
    print(('  GetWaterQuadCount(): %s'):format(tostring(GetWaterQuadCount())))
    print(('  GetGlobalWaterType present: %s'):format(tostring(GetGlobalWaterType ~= nil)))
    print(('  CreateDryVolume present: %s'):format(tostring(CreateDryVolume ~= nil)))
    print(('  SetWaterAreaClipRect present: %s'):format(tostring(SetWaterAreaClipRect ~= nil)))
    print(('  pendingWater: %s'):format(tostring(pendingWater)))

    -- Print exactly what the bounds native hands back, values and types, so we
    -- stop guessing at its return shape.
    local packed = table.pack(GetWaterQuadBounds(0))
    print(('  GetWaterQuadBounds(0) returned %d value(s):'):format(packed.n))
    for i = 1, packed.n do
        print(('    [%d] %s (%s)'):format(i, tostring(packed[i]), type(packed[i])))
    end

    local lvl = table.pack(GetWaterQuadLevel(0))
    print(('  GetWaterQuadLevel(0) returned %d value(s): %s')
        :format(lvl.n, tostring(lvl[1]) .. (lvl.n > 1 and (', ' .. tostring(lvl[2])) or '')))

    say('diagnostics printed to F8')
end, false)

local borrowed = nil

RegisterCommand('quadtest', function(_, args)
    if borrowed then
        say('already borrowing a quad - /quadrestore first')
        return
    end

    local size = tonumber(args[1]) or 100.0
    local c = GetEntityCoords(PlayerPedId())

    local best, bestDist
    for i = 1, #quadCache do
        local q = quadCache[i]
        local cx, cy = (q.minX + q.maxX) * 0.5, (q.minY + q.maxY) * 0.5
        local d = (cx - c.x) ^ 2 + (cy - c.y) ^ 2
        if not bestDist or d < bestDist then best, bestDist = q, d end
    end

    if not best then
        say('no quads cached - nothing to borrow')
        return
    end

    borrowed = {
        idx = best.idx, minX = best.minX, minY = best.minY,
        maxX = best.maxX, maxY = best.maxY, level = best.level,
    }

    local wroteBounds = SetWaterQuadBounds(best.idx,
        math.floor(c.x - size), math.floor(c.y - size),
        math.ceil(c.x + size), math.ceil(c.y + size))
    local wroteLevel = SetWaterQuadLevel(best.idx, -500.0)

    -- Read the level straight back. A silently failed write looks exactly like
    -- "quad levels don't drive the water", so prove the write landed first.
    local okL, readback = GetWaterQuadLevel(best.idx)
    if readback == nil then readback = okL end

    print(('[pf-watercontrol] SetWaterQuadBounds returned %s, SetWaterQuadLevel returned %s')
        :format(tostring(wroteBounds), tostring(wroteLevel)))
    print(('  level read back from the game: %s (expected -500)'):format(tostring(readback)))

    -- If the array now reports a quad here, the move took effect.
    local found = GetWaterQuadAtCoords(c.x, c.y)

    print(('[pf-watercontrol] borrowed quad %d (was %.0f %.0f -> %.0f %.0f, level %.1f, %.0fm away)')
        :format(best.idx, best.minX, best.minY, best.maxX, best.maxY, best.level, math.sqrt(bestDist)))
    print(('  moved over you (+/-%.0fm) at level -500'):format(size))
    print(('  GetWaterQuadAtCoords here now returns: %d  (was -1)'):format(found or -1))
    say('quad moved over you - is the water gone? /quadrestore to undo')
end, false)

RegisterCommand('quadrestore', function()
    if not borrowed then
        say('no borrowed quad to restore')
        return
    end

    SetWaterQuadBounds(borrowed.idx, borrowed.minX, borrowed.minY, borrowed.maxX, borrowed.maxY)
    SetWaterQuadLevel(borrowed.idx, borrowed.level)

    say(('quad %d put back'):format(borrowed.idx))
    borrowed = nil
end, false)

RegisterCommand('waterreload', function()
    restoreEverything()
    local n = buildQuadCache()
    applyPermanentZones()
    say(('rebuilt cache: %d quads'):format(n))
end, false)
