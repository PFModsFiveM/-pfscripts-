-- Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
-- Port of whip_core/client/hud_skin.lua (the black skin's game half). Free software under the GNU Lesser General
-- Public License 3.0 (see COPYING.LESSER and COPYING).
--
-- The minimap's look (settings.minimapStyle):
--   'frame'   a white frame round the map, drawn UNDER GTA's HUD (GFX_ORDER_BEFORE_HUD) so the N and the blips on the
--             map's edge are drawn over it; the radar's tiles swapped for the dark map; the waypoint, its blip and the
--             GPS line in blue instead of GTA's purple.
--   'dark'    the dark map and the blue route, no frame.
--   'native'  GTA's own map.
-- The frame is not on the NUI page: everything there is drawn over the game, radar included, and would cover the N.
-- One baked sprite a frame (stream/pfframe_<shape>.ytd, WHIP's art); while the radar tuner is open, three vector
-- layers that follow its sliders live (stream/pfhud.ytd's disc for the corners).
--
-- THE DARK MAP IS NOT IN THIS RESOURCE. Its tiles are made from GTA's map (Rockstar material) and live in
-- pfm-media-map (stream/pfmap_<row>_<col>.ytd); without that resource started the radar keeps GTA's tiles and the frame
-- still works. The texture inside each tile dictionary is still named whipmap_<row>_<col>: a texture's name inside a
-- .ytd cannot be changed without rebuilding the file, so it is referenced as it is.

HudSkin = {}

local SKIN_DICT = 'pfhud'          -- 'disc', a white circle (the tuner's live frame's corners)
local FRAME_DICT = 'pfframe_'      -- 'frame', the whole frame baked per shape
local RING_DICT = 'pfring_'        -- 'ring', the frame with its middle clear (Map background under 100%)
local ROUTE_COLOUR = 142           -- HUD_COLOUR_WAYPOINT: the waypoint, its blip and the GPS line
local ROUTE_BLUE = { 96, 165, 250 }

--- GTA's radar is six tiles, minimap_sea_<row>_<col>. Each is swapped for pfmap_<row>_<col> (texture whipmap_<row>_<col>).
local MAP_TILES = { '0_0', '0_1', '1_0', '1_1', '2_0', '2_1' }

--- The map's visible box, where the frame goes: posX, posY (up from the bottom), sizeX, sizeY, as fractions of a 16:9
--- screen with the safe zone at FULL size. WHIP's, tuned in game; /radartuner's 'frame' row moves it.
local SHIPPED_FRAME = { 0.0060, 0.0700, 0.1720, 0.1655 }
local frame = { SHIPPED_FRAME[1], SHIPPED_FRAME[2], SHIPPED_FRAME[3], SHIPPED_FRAME[4] }
local frameCorner = 1.0

--- The corners follow the mask's: 'rounded' is 512 x 396 with a 46 px radius.
local MASK_CORNERS = { rounded = { 46 / 512, 46 / 396 }, square = { 0, 0 }, circle = { 0.5, 0.5 } }

--- The border from the map's edge outwards, in screen heights: black, white, black (1.3, 3.7, 1.9 px at 1080p).
local BANDS = { inner = 0.0012, white = 0.0034, outer = 0.0018 }

local drawOrder = 1                -- GFX_ORDER_BEFORE_HUD (4 = after, the tuner's switch)

local style = 'frame'
local shape = 'rounded'
local layers, sprite = nil, nil
local spriteReady, discReady, ringReady = false, false, false
local fillAlpha = 255
local layersDue = 0
local sentBox = nil
local builtW, builtH, builtSafe, builtMask = nil, nil, nil, nil
local routeWas = nil
local mapSwapped = false
local frameHeld = false
local tunerOpen = false

do
    local s = HudRadar and HudRadar.saved and HudRadar.saved()
    if s and type(s.frame) == 'table' and #s.frame >= 4 then
        frame = { tonumber(s.frame[1]) or frame[1], tonumber(s.frame[2]) or frame[2],
            tonumber(s.frame[3]) or frame[3], tonumber(s.frame[4]) or frame[4] }
        frameCorner = tonumber(s.frame[5]) or 1.0
    end
end

local function mediaRunning()
    return GetResourceState(Config.MediaMapResource or 'pfm-media-map') == 'started'
end
HudSkin.mediaRunning = mediaRunning

-- ── the frame ────────────────────────────────────────────────────────

local function checkReady()
    spriteReady = HasStreamedTextureDictLoaded(sprite.dict) and true or false
    if not spriteReady and frameHeld then RequestStreamedTextureDict(sprite.dict, false) end
    ringReady = fillAlpha < 255 and HasStreamedTextureDictLoaded(sprite.ring) and true or false
    if fillAlpha < 255 and not ringReady and frameHeld then RequestStreamedTextureDict(sprite.ring, false) end
    discReady = HasStreamedTextureDictLoaded(SKIN_DICT) and true or false
    if not discReady and tunerOpen then RequestStreamedTextureDict(SKIN_DICT, false) end
end

--- The frame's layers and sprite for this screen's shape and safe zone. Looked at once a second; worked out again only
--- when something it is made from changed (a pass that changes nothing allocates nothing).
local function buildLayers()
    layersDue = GetGameTimer() + 1000
    local w, h = GetActiveScreenResolution()
    local safe = GetSafeZoneSize() or 1.0
    if layers and w == builtW and h == builtH and safe == builtSafe and shape == builtMask then
        checkReady()
        return
    end
    builtW, builtH, builtSafe, builtMask = w, h, safe, shape
    local aspect = (h and h > 0) and (w / h) or (16 / 9)
    local xs = (16 / 9) / aspect
    local margin = (1.0 - safe) / 2
    local left = margin + frame[1] * xs
    local bottom = 1.0 - (margin + frame[2])
    local fw, fh = frame[3] * xs, frame[4]
    local top = bottom - fh
    local corner = MASK_CORNERS[shape] or MASK_CORNERS.rounded
    local cx = math.min(fw / 2, corner[1] * fw * frameCorner)
    local cy = math.min(fh / 2, corner[2] * fh * frameCorner)

    local function layer(e, colour)
        local ex = e / aspect
        local rx, ry = cx + ex, cy + e
        local L, R = left - ex, left + fw + ex
        local T, B = top - e, bottom + e
        local W, H = R - L, B - T
        return {
            colour = colour,
            rects = { { L + W / 2, T + H / 2, W, H - 2 * ry }, { L + W / 2, T + H / 2, W - 2 * rx, H } },
            discs = { { L + rx, T + ry }, { R - rx, T + ry }, { L + rx, B - ry }, { R - rx, B - ry } },
            dw = 2 * rx, dh = 2 * ry,
        }
    end

    local b = BANDS
    local outer = b.inner + b.white + b.outer
    layers = {
        layer(outer, { 0, 0, 0 }),
        layer(b.inner + b.white, { 255, 255, 255 }),
        layer(b.inner, { 0, 0, 0 }),
    }

    local s = MASK_CORNERS[shape] and shape or 'rounded'
    local L, R = left - outer / aspect, left + fw + outer / aspect
    local T, B = top - outer, bottom + outer
    sprite = { dict = FRAME_DICT .. s, ring = RING_DICT .. s, x = (L + R) / 2, y = (T + B) / 2, w = R - L, h = B - T }
    checkReady()

    -- the page lines the gauges up under the frame's outside edge, and puts its own marks over the map (fractions)
    local box = { left = left - outer / aspect, right = left + fw + outer / aspect, bottom = bottom + outer,
        top = top - outer }
    local key = ('%.4f %.4f %.4f %.4f'):format(box.left, box.right, box.bottom, box.top)
    if key ~= sentBox then
        sentBox = key
        SendNUIMessage({ action = 'hudFrameBox', left = box.left, right = box.right, bottom = box.bottom, top = box.top,
            mapLeft = left, mapTop = top, mapWidth = fw, mapHeight = fh, shape = s })
    end
end

--- Every frame while the frame is held (client/radar.lua's loop): two radar checks, the draw order there and back, and
--- one sprite (two with a see-through background).
function HudSkin.drawFrame()
    if not frameHeld then
        -- still keep the page told where the frame would be (the gauges line up under it either way), once a second
        if GetGameTimer() >= layersDue then buildLayers() end
        return
    end
    if not layers or GetGameTimer() >= layersDue then buildLayers() end
    if not IsMinimapRendering() or IsBigmapActive() then return end

    if not tunerOpen then
        if not spriteReady then return end
        SetScriptGfxDrawOrder(drawOrder)
        if fillAlpha >= 255 or not ringReady then
            DrawSprite(sprite.dict, 'frame', sprite.x, sprite.y, sprite.w, sprite.h, 0.0, 255, 255, 255, 255)
        else
            if fillAlpha > 0 then
                DrawSprite(sprite.dict, 'frame', sprite.x, sprite.y, sprite.w, sprite.h, 0.0, 255, 255, 255, fillAlpha)
            end
            DrawSprite(sprite.ring, 'ring', sprite.x, sprite.y, sprite.w, sprite.h, 0.0, 255, 255, 255, 255)
        end
        SetScriptGfxDrawOrder(4)
        return
    end

    -- the tuner is open: the live vector frame, which follows every slider exactly
    if not discReady then return end
    SetScriptGfxDrawOrder(drawOrder)
    for i = 1, #layers do
        local l = layers[i]
        local c = l.colour
        for j = 1, 2 do
            local r = l.rects[j]
            DrawRect(r[1], r[2], r[3], r[4], c[1], c[2], c[3], 255)
        end
        for j = 1, 4 do
            local d = l.discs[j]
            DrawSprite(SKIN_DICT, 'disc', d[1], d[2], l.dw, l.dh, 0.0, c[1], c[2], c[3], 255)
        end
    end
    SetScriptGfxDrawOrder(4)
end

-- ── the dark map ─────────────────────────────────────────────────────

--- Swap GTA's radar tiles for the dark map, or give them back. Only while pfm-media-map is started; a tile whose
--- dictionary did not stream keeps GTA's.
---@return boolean swapped
local function swapMap(on)
    on = on and mediaRunning() or false
    if on == mapSwapped then return mapSwapped end
    mapSwapped = on
    for _, t in ipairs(MAP_TILES) do
        local orig, dict, tex = 'minimap_sea_' .. t, 'pfmap_' .. t, 'whipmap_' .. t
        if on then
            if HudRadar.loadDict(dict, 5000) then
                AddReplaceTexture(orig, orig, dict, tex)
            else
                print(('[pf-hud] the dark map tile %s did not stream; keeping GTA\'s (pfm-media-map stream/%s.ytd)')
                    :format(t, dict))
            end
        else
            RemoveReplaceTexture(orig, orig)
            SetStreamedTextureDictAsNoLongerNeeded(dict)
        end
    end
    HudRadar.rebuild()
    return mapSwapped
end

function HudSkin.mapSwapped() return mapSwapped end

-- ── the waypoint's colour ────────────────────────────────────────────

local function blueRoute(on)
    if on then
        if not routeWas then routeWas = { GetHudColour(ROUTE_COLOUR) } end
        ReplaceHudColourWithRgba(ROUTE_COLOUR, ROUTE_BLUE[1], ROUTE_BLUE[2], ROUTE_BLUE[3], 255)
    elseif routeWas then
        ReplaceHudColourWithRgba(ROUTE_COLOUR, routeWas[1], routeWas[2], routeWas[3], routeWas[4] or 255)
    end
end

-- ── applying ─────────────────────────────────────────────────────────

local applyGen = 0

--- Apply the minimap's look. `loaded`: a character is in (the frame is drawn only then).
---@param s table settings ({ minimapStyle, minimapShape, mapBackground })
---@param loaded boolean
function HudSkin.apply(s, loaded)
    local newStyle = (s.minimapStyle == 'dark' or s.minimapStyle == 'native') and s.minimapStyle or 'frame'
    local newShape = MASK_CORNERS[s.minimapShape] and s.minimapShape or 'rounded'
    local pct = tonumber(s.mapBackground) or 100
    fillAlpha = math.floor(math.max(0, math.min(100, pct)) / 100 * 255 + 0.5)
    if newShape ~= shape then layers = nil end
    style, shape = newStyle, newShape
    layers, sentBox = nil, nil
    frameHeld = loaded == true and style == 'frame'
    applyGen = applyGen + 1
    local gen = applyGen
    CreateThread(function()
        if frameHeld then HudRadar.loadDict(FRAME_DICT .. shape, 5000) end
        if gen ~= applyGen then return end
        local dark = style ~= 'native'
        local swapped = swapMap(dark and loaded == true)
        blueRoute(dark and swapped)
    end)
end

--- The page asks where the frame is again (it reloaded).
function HudSkin.resend() sentBox = nil; layersDue = 0 end

-- ── seams for the radar tuner (client/radar_tuner.lua) ───────────────

function HudSkin.getFrame() return { frame[1], frame[2], frame[3], frame[4], frameCorner } end
function HudSkin.getShippedFrame() return { SHIPPED_FRAME[1], SHIPPED_FRAME[2], SHIPPED_FRAME[3], SHIPPED_FRAME[4], 1.0 } end

function HudSkin.setFrame(r)
    frame = { r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, r[4] + 0.0 }
    if r[5] then frameCorner = r[5] + 0.0 end
    layers = nil
end

function HudSkin.frameOver(over) drawOrder = over and 4 or 1 end

function HudSkin.tuner(open)
    tunerOpen = open == true
    layers = nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    blueRoute(false)
    for _, t in ipairs(MAP_TILES) do RemoveReplaceTexture('minimap_sea_' .. t, 'minimap_sea_' .. t) end
end)

-- pfm-media-map stopping takes its tiles with it: give GTA's back. Starting it later brings the dark map in.
AddEventHandler('onClientResourceStop', function(res)
    if res == (Config.MediaMapResource or 'pfm-media-map') and mapSwapped then
        for _, t in ipairs(MAP_TILES) do RemoveReplaceTexture('minimap_sea_' .. t, 'minimap_sea_' .. t) end
        mapSwapped = false
        blueRoute(false)
    end
end)
