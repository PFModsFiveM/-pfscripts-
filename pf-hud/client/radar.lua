-- Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
-- Port of whip_core/client/hud.lua (the radar: mask, component rects, the health/armour bars, GTA's car names).
-- Free software under the GNU Lesser General Public License 3.0 (see COPYING.LESSER and COPYING).
--
-- GTA's radar stays the minimap (WHIP's own 3D NUI minimap is not ported, see NOTICE.md). This file:
--   * swaps its mask for the shape the player chose (stream/pfmask_<shape>.ytd, WHIP's art);
--   * places it with the three component rects WHIP tuned (or this player's own, saved by /radartuner);
--   * hides the health and armour bars round it (the minimap scaleform's SETUP_HEALTH_ARMOUR 3; this replaces the
--     old modified minimap.gfx, which is gone);
--   * hides GTA's vehicle name, class, area and street texts every frame (Config.HideGtaCarNames);
--   * runs the one per-frame loop the HUD needs, which also draws the minimap's frame (client/skin.lua).

HudRadar = {}

local TUNE_KVP = 'pf-hud:radar'

--- The three component rects, tuned by eye with WHIP's /radar. posX, posY, sizeX, sizeY, anchored Left/Bottom.
--- `minimap` also places the scaleform overlay (compass N, waypoint arrow); `minimap_mask` is the GPS route layer on its
--- own mapping (hence several times the others); `minimap_blur` resizes the map (never zero it: the map vanishes).
local SHIPPED = {
    minimap      = {  0.0000, -0.0505, 0.1795, 0.2000 },
    minimap_mask = {  0.0295,  0.0780, 0.4355, 0.5160 },
    minimap_blur = {  0.0040, -0.0670, 0.1761, 0.1708 },
}
local SHIPPED_CLIP = 0

--- The live rects: the shipped ones, or what this player saved with the tuner.
local rects = {
    minimap      = { table.unpack(SHIPPED.minimap) },
    minimap_mask = { table.unpack(SHIPPED.minimap_mask) },
    minimap_blur = { table.unpack(SHIPPED.minimap_blur) },
}
local clipType = SHIPPED_CLIP
local maskShape = 'rounded'

-- the tuner's saved values (client/radar_tuner.lua writes them): rects, clip and the frame box
local saved = nil
do
    local raw = GetResourceKvpString(TUNE_KVP)
    if raw and raw ~= '' then
        local ok, t = pcall(json.decode, raw)
        if ok and type(t) == 'table' then saved = t end
    end
    if saved and type(saved.rects) == 'table' then
        for name, r in pairs(saved.rects) do
            if rects[name] and type(r) == 'table' and #r >= 4 then
                rects[name] = { tonumber(r[1]) or 0, tonumber(r[2]) or 0, tonumber(r[3]) or 0.1, tonumber(r[4]) or 0.1 }
            end
        end
    end
    if saved and tonumber(saved.clip) then clipType = math.floor(tonumber(saved.clip)) end
end

--- What the tuner saved (nil: nothing), for client/skin.lua's frame and the tuner.
function HudRadar.saved() return saved end

function HudRadar.setSaved(t)
    saved = t
    if t then SetResourceKvp(TUNE_KVP, json.encode(t)) else DeleteResourceKvp(TUNE_KVP) end
end

function HudRadar.getShippedRect(key) return SHIPPED[key] end
function HudRadar.getShippedClip() return SHIPPED_CLIP end
function HudRadar.getRect(key) return rects[key] end
function HudRadar.getClip() return clipType end

local minimapScaleform = nil

--- Hide the health and armour bars round the minimap (param 3 is "no bars"). The game re-creates the scaleform at times
--- (model swap, death), so the loop below reasserts it.
function HudRadar.hideHealthArmour()
    if not minimapScaleform or minimapScaleform == 0 then minimapScaleform = RequestScaleformMovie('minimap') end
    BeginScaleformMovieMethod(minimapScaleform, 'SETUP_HEALTH_ARMOUR')
    ScaleformMovieMethodAddParamInt(3)
    EndScaleformMovieMethod()
end

--- Wait for a streamed texture dictionary, up to `ms`.
function HudRadar.loadDict(dict, ms)
    if HasStreamedTextureDictLoaded(dict) then return true end
    RequestStreamedTextureDict(dict, false)
    local deadline = GetGameTimer() + (ms or 2000)
    while not HasStreamedTextureDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    return true
end

--- Swap the radar mask for the shape's (radarmasksm: brightness is the map's opacity, its edge the falloff). A dictionary
--- that does not stream leaves the game's mask. false/nil: the game's own.
---@return boolean applied
function HudRadar.applyMask(shape)
    maskShape = shape
    if not shape then
        RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
        return false
    end
    local dict = 'pfmask_' .. tostring(shape)
    if not HudRadar.loadDict(dict, 2000) then
        print(('[pf-hud] minimap mask "%s" did not stream; keeping the game\'s own (stream/%s.ytd)'):format(tostring(shape), dict))
        return false
    end
    if maskShape ~= shape then return false end   -- changed again while it loaded
    -- the texture inside WHIP's mask dictionaries is named radarmasksm, like the game's
    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', dict, 'radarmasksm')
    return true
end

function HudRadar.maskShape() return maskShape end

local rebuildGen = 0

--- Push the rects at the game and rebuild the radar (a bigmap toggle with a real frame between), then reassert the clip
--- and the bars, which the rebuild resets.
function HudRadar.applyRects(rebuild)
    for name, r in pairs(rects) do
        SetMinimapComponentPosition(name, 'L', 'B', r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, r[4] + 0.0)
    end
    if rebuild == false then return end
    rebuildGen = rebuildGen + 1
    local gen = rebuildGen
    CreateThread(function()
        SetRadarBigmapEnabled(true, false)
        Wait(50)
        if gen ~= rebuildGen then return end
        SetRadarBigmapEnabled(false, false)
        Wait(0)
        if clipType >= 0 then SetMinimapClipType(clipType) end
        HudRadar.hideHealthArmour()
    end)
end

--- Set a rect live (the tuner). Not saved.
function HudRadar.setRect(name, r)
    if not rects[name] then return end
    rects[name] = { r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, r[4] + 0.0 }
end

function HudRadar.setClip(c) clipType = math.floor(tonumber(c) or SHIPPED_CLIP) end

--- Back to the shipped rects (the tuner's Reset).
function HudRadar.resetRects()
    for name, r in pairs(SHIPPED) do rects[name] = { r[1], r[2], r[3], r[4] } end
    clipType = SHIPPED_CLIP
end

--- Rebuild with the current rects (after a texture swap: client/skin.lua's tiles).
function HudRadar.rebuild() HudRadar.applyRects(true) end

-- ── radar shown or hidden ────────────────────────────────────────────

local shown = nil

--- Show or hide GTA's radar; change-gated, and again whenever the game disagrees (another script's DisplayRadar).
function HudRadar.setVisible(want)
    want = want and true or false
    -- IsRadarHidden is a BOOL native (1 or false)
    local gameShows = not IsRadarHidden()
    if want == shown and gameShows == want then return end
    local cameBack = want and not shown
    shown = want
    DisplayRadar(want)
    if cameBack then HudRadar.hideHealthArmour() end
end

-- ── the per-frame loop ───────────────────────────────────────────────

local CAR_NAMES = { 6, 7, 8, 9 }   -- VEHICLE_NAME, AREA_NAME, VEHICLE_CLASS, STREET_NAME
local active = false

--- Start or stop the per-frame loop (while a character is loaded). It hides GTA's car names and draws the frame.
function HudRadar.setActive(on)
    on = on and true or false
    if on == active then return end
    active = on
    if not on then return end
    CreateThread(function()
        local hideNames = Config.HideGtaCarNames ~= false
        local reassert = 0
        while active do
            if hideNames then
                for i = 1, #CAR_NAMES do HideHudComponentThisFrame(CAR_NAMES[i]) end
            end
            if HudSkin and HudSkin.drawFrame then HudSkin.drawFrame() end
            -- the bars come back after a death or a model swap: reasserted every 5 s (a scaleform call is not free)
            reassert = reassert + 1
            if reassert >= 300 then
                reassert = 0
                HudRadar.hideHealthArmour()
            end
            Wait(0)
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
    DisplayRadar(true)
end)
