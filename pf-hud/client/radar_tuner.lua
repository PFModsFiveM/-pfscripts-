-- Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
-- Port of whip_core/client/radar_debug.lua (/radardebug) as /radartuner. Free software under the GNU Lesser General
-- Public License 3.0 (see COPYING.LESSER and COPYING).
--
-- The minimap's geometry is six numbers per component across three components, and the game applies none of them the
-- way the names suggest: `minimap_mask` places the GPS route line, `minimap_blur` resizes the map, and `minimap` places
-- both the map and the scaleform overlay (the N, the clamped waypoint arrow). This draws every rect on screen, gives each
-- a slider, and lets the numbers be dragged while watching the map. Set a waypoint before judging minimap_mask.
--
-- PF: an admin tool (the server's /radartuner, Config.RadarTunerPermission). Unlike WHIP's, "Save" keeps this player's
-- tuning (KVP, read by client/radar.lua and client/skin.lua at start) and "Print" writes the table to F8 to paste into
-- radar.lua's SHIPPED / skin.lua's SHIPPED_FRAME for everyone.

HudTuner = { open = false }

local COMPONENTS = {
    { key = 'minimap',       label = 'minimap',       note = 'map render + scaleform (N, waypoint)' },
    { key = 'minimap_mask',  label = 'minimap_mask',  note = 'the GPS route line: set a waypoint to see it' },
    { key = 'minimap_blur',  label = 'minimap_blur',  note = 'resizes the map, leaves the N alone' },
    { key = 'bigmap',        label = 'bigmap',        note = 'the expanded map (hold the toggle)' },
    { key = 'bigmap_mask',   label = 'bigmap_mask',   note = '' },
    { key = 'bigmap_blur',   label = 'bigmap_blur',   note = '' },
    { key = 'golf_courses',  label = 'golf_courses',  note = 'unused; probe fodder' },
    -- not a game component: the frame round the map (client/skin.lua), plus a scale on its corners (1 = the mask's)
    { key = 'frame',         label = 'frame',         note = 'the map\'s white border: line it up with the map\'s edge' },
}

--- posX, posY, sizeX, sizeY, alignX, alignY: the stock frontend.xml values.
local STOCK = {
    minimap      = { -0.0045, -0.022,    0.210,  0.258888,    'L', 'B' },
    minimap_mask = {  0.000,   0.032,    0.101,  0.259,       'L', 'B' },
    minimap_blur = {  0.012,   0.022,    0.256,  0.337,       'L', 'B' },
    bigmap       = { -0.003975, 0.022,   0.364,  0.460416666, 'L', 'B' },
    bigmap_mask  = {  0.145,   0.015,    0.176,  0.395,       'L', 'B' },
    bigmap_blur  = { -0.019,   0.022,    0.262,  0.464,       'L', 'B' },
    golf_courses = {  0.003,  -0.038,    0.27375, 0.347,      'L', 'B' },
    frame        = {  0.0060,  0.0700,   0.1720,  0.1655,     'L', 'B', 1.0 },
}

--- The limits every value is held to (the page's sliders use the same). A typed value outside them is clamped, and a
--- size never reaches zero (a zero minimap_blur makes the whole map invisible).
local LIMITS = {
    pos    = { -1.0, 1.0 },
    size   = { 0.01, 1.5 },
    corner = { 0.0, 3.0 },
    zoom   = { 0, 1400 },
    clip   = { -1, 3 },
}
local ALIGN_X = { L = true, R = true, C = true, I = true }
local ALIGN_Y = { T = true, B = true, C = true, I = true }

local function clamp(v, lim, fallback)
    v = tonumber(v)
    if not v or v ~= v then return fallback end
    return math.max(lim[1], math.min(lim[2], v))
end
HudTuner.clamp = clamp
HudTuner.LIMITS = LIMITS

local rects = {}
local outlines = {}
local opts = {
    showOutlines = true,
    radarZoom    = 0,
    clipType     = -1,
    bigmapOn     = false,
    hideBars     = true,
    maskShape    = 'rounded',
    frameOver    = false,
}
local seeded = false

local function seedFromLive()
    for _, c in ipairs(COMPONENTS) do
        local s = STOCK[c.key]
        if c.key == 'frame' then
            local f = HudSkin.getFrame()
            rects.frame = { f[1], f[2], f[3], f[4], 'L', 'B', f[5] or 1.0 }
        else
            local live = HudRadar.getRect(c.key)
            if live then
                rects[c.key] = { live[1], live[2], live[3], live[4], 'L', 'B' }
            else
                rects[c.key] = { s[1], s[2], s[3], s[4], s[5], s[6] }
            end
        end
    end
    opts.clipType = HudRadar.getClip()
    opts.maskShape = HudRadar.maskShape() or false
end

local function seedFromShipped()
    for _, c in ipairs(COMPONENTS) do
        local s = STOCK[c.key]
        if c.key == 'frame' then
            local f = HudSkin.getShippedFrame()
            rects.frame = { f[1], f[2], f[3], f[4], 'L', 'B', f[5] }
        else
            local live = HudRadar.getShippedRect(c.key)
            if live then
                rects[c.key] = { live[1], live[2], live[3], live[4], 'L', 'B' }
            else
                rects[c.key] = { s[1], s[2], s[3], s[4], s[5], s[6] }
            end
        end
    end
    opts.clipType = HudRadar.getShippedClip()
end

local rebuildPending = false

--- Push every rect at the game; the rebuild (a bigmap flick) is debounced so a slider drag is one rebuild.
local function applyAll(rebuild)
    for _, c in ipairs(COMPONENTS) do
        local r = rects[c.key]
        if r and c.key == 'frame' then
            HudSkin.setFrame({ r[1], r[2], r[3], r[4], r[7] })
        elseif r then
            HudRadar.setRect(c.key, r)
            SetMinimapComponentPosition(c.key, r[5], r[6], r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, r[4] + 0.0)
        end
    end
    HudSkin.frameOver(opts.frameOver == true)
    if opts.radarZoom and opts.radarZoom > 0 then SetRadarZoom(math.floor(opts.radarZoom)) end
    if opts.clipType and opts.clipType >= 0 then
        HudRadar.setClip(opts.clipType)
        SetMinimapClipType(math.floor(opts.clipType))
    end
    if rebuild == false or rebuildPending then return end
    rebuildPending = true
    CreateThread(function()
        Wait(180)
        rebuildPending = false
        SetRadarBigmapEnabled(true, false)
        Wait(50)
        SetRadarBigmapEnabled(opts.bigmapOn == true, false)
        Wait(0)
        if opts.hideBars then HudRadar.hideHealthArmour() end
    end)
end

-- ── outlines (a reference, not the truth: the game's own mapping adds the safe zone and an aspect correction) ──

local OUTLINE_COLOURS = {
    minimap      = { 96, 165, 250 },
    minimap_mask = { 74, 222, 128 },
    minimap_blur = { 251, 191, 36 },
    bigmap       = { 248, 113, 113 },
    bigmap_mask  = { 167, 139, 250 },
    bigmap_blur  = { 56, 189, 248 },
    golf_courses = { 255, 255, 255 },
    frame        = { 244, 114, 182 },
}
local OUTLINE_FALLBACK = { 255, 255, 255 }

local function drawOutline(r, col)
    local x, w, h = r[1], r[3], r[4]
    local bottom = 1.0 - r[2]
    local top = bottom - h
    local t = 0.0015
    local cr, cg, cb = col[1], col[2], col[3]
    DrawRect(x + w / 2, top, w, t, cr, cg, cb, 200)
    DrawRect(x + w / 2, bottom, w, t, cr, cg, cb, 200)
    DrawRect(x, top + h / 2, t * 0.56, h, cr, cg, cb, 200)
    DrawRect(x + w, top + h / 2, t * 0.56, h, cr, cg, cb, 200)
end

local outlineThread = false

local function startOutlineThread()
    if outlineThread then return end
    outlineThread = true
    CreateThread(function()
        while HudTuner.open do
            if opts.showOutlines then
                for key, on in pairs(outlines) do
                    if on and rects[key] then drawOutline(rects[key], OUTLINE_COLOURS[key] or OUTLINE_FALLBACK) end
                end
                Wait(0)
            else
                Wait(250)
            end
        end
        outlineThread = false
    end)
end

-- ── open / close ─────────────────────────────────────────────────────

local function payload()
    local comps = {}
    for i, c in ipairs(COMPONENTS) do
        local r = rects[c.key]
        comps[i] = {
            key = c.key, label = c.label, note = c.note,
            posX = r[1], posY = r[2], sizeX = r[3], sizeY = r[4], alignX = r[5], alignY = r[6],
            outline = outlines[c.key] and true or false,
            colour = OUTLINE_COLOURS[c.key],
            managed = (c.key == 'minimap' or c.key == 'minimap_mask' or c.key == 'minimap_blur' or c.key == 'frame'),
        }
        if c.key == 'frame' then
            comps[i].corner = r[7]
            comps[i].fields = { 'posX', 'posY', 'sizeX', 'sizeY', 'corner' }
            comps[i].noAlign = true
        end
    end
    return { components = comps, opts = opts, limits = LIMITS }
end

local function openTuner()
    if HudTuner.open then return end
    if not seeded then seedFromLive(); seeded = true end
    HudTuner.open = true
    startOutlineThread()
    SetNuiFocus(true, true)
    if PadBridge then PadBridge.attach({ active = function() return HudTuner.open end }) end
    HudSkin.tuner(true)
    HudRadar.setVisible(true)
    SendNUIMessage({ action = 'radarTunerOpen', data = payload() })
    applyAll(true)
end

local function closeTuner()
    if not HudTuner.open then return end
    HudTuner.open = false
    SetNuiFocus(false, false)
    if PadBridge then PadBridge.detach() end
    HudSkin.tuner(false)
    SendNUIMessage({ action = 'radarTunerClose' })
end
HudTuner.close = closeTuner

-- the server says this player may (QBCore permission, server.lua)
RegisterNetEvent('pf-hud:client:radarTuner', function()
    if HudTuner.open then closeTuner() else openTuner() end
end)

-- ── NUI callbacks ────────────────────────────────────────────────────

--- One component's values from the page, clamped.
function HudTuner.set(data)
    local r = type(data) == 'table' and data.key and rects[data.key]
    if not r then return false end
    if data.posX ~= nil then r[1] = clamp(data.posX, LIMITS.pos, r[1]) end
    if data.posY ~= nil then r[2] = clamp(data.posY, LIMITS.pos, r[2]) end
    if data.sizeX ~= nil then r[3] = clamp(data.sizeX, LIMITS.size, r[3]) end
    if data.sizeY ~= nil then r[4] = clamp(data.sizeY, LIMITS.size, r[4]) end
    if data.alignX and ALIGN_X[data.alignX] then r[5] = data.alignX end
    if data.alignY and ALIGN_Y[data.alignY] then r[6] = data.alignY end
    if data.corner ~= nil and data.key == 'frame' then r[7] = clamp(data.corner, LIMITS.corner, r[7]) end
    applyAll(data.rebuild ~= false)
    return true
end

function HudTuner.rect(key) return rects[key] end

RegisterNUICallback('radarTunerSet', function(data, cb)
    HudTuner.set(data)
    cb('ok')
end)

RegisterNUICallback('radarTunerOutline', function(data, cb)
    if type(data) == 'table' and data.key and rects[data.key] then outlines[data.key] = data.on and true or false end
    cb('ok')
end)

local OPT_KINDS = { showOutlines = 'bool', bigmapOn = 'bool', hideBars = 'bool', frameOver = 'bool',
    radarZoom = 'zoom', clipType = 'clip', maskShape = 'shape' }
local SHAPES = { rounded = true, square = true, circle = true }

RegisterNUICallback('radarTunerOpt', function(data, cb)
    local kind = type(data) == 'table' and OPT_KINDS[data.name]
    if kind then
        local v = data.value
        if kind == 'bool' then v = v == true
        elseif kind == 'zoom' then v = math.floor(clamp(v, LIMITS.zoom, 0))
        elseif kind == 'clip' then v = math.floor(clamp(v, LIMITS.clip, -1))
        elseif kind == 'shape' then
            v = SHAPES[v] and v or false
            CreateThread(function() HudRadar.applyMask(v) end)
        end
        opts[data.name] = v
        applyAll(true)
    end
    cb('ok')
end)

--- Keep this player's tuning (client/radar.lua and client/skin.lua read it at start).
function HudTuner.save()
    local f = rects.frame
    HudRadar.setSaved({
        rects = {
            minimap = { rects.minimap[1], rects.minimap[2], rects.minimap[3], rects.minimap[4] },
            minimap_mask = { rects.minimap_mask[1], rects.minimap_mask[2], rects.minimap_mask[3], rects.minimap_mask[4] },
            minimap_blur = { rects.minimap_blur[1], rects.minimap_blur[2], rects.minimap_blur[3], rects.minimap_blur[4] },
        },
        clip = opts.clipType,
        frame = { f[1], f[2], f[3], f[4], f[7] or 1.0 },
    })
end

RegisterNUICallback('radarTunerSave', function(_, cb)
    HudTuner.save()
    print('[pf-hud:radartuner] saved for this player (KVP pf-hud:radar)')
    cb('ok')
end)

RegisterNUICallback('radarTunerReset', function(data, cb)
    if type(data) == 'table' and data.mode == 'stock' then
        for _, c in ipairs(COMPONENTS) do
            local s = STOCK[c.key]
            rects[c.key] = { s[1], s[2], s[3], s[4], s[5], s[6], s[7] }
        end
        opts.clipType = -1
    elseif type(data) == 'table' and data.mode == 'forget' then
        HudRadar.setSaved(nil)   -- the saved tuning gone: back to the shipped values
        HudRadar.resetRects()
        seedFromShipped()
    else
        seedFromShipped()
    end
    applyAll(true)
    SendNUIMessage({ action = 'radarTunerOpen', data = payload() })
    cb('ok')
end)

RegisterNUICallback('radarTunerPrint', function(_, cb)
    print('[pf-hud:radartuner] client/radar.lua SHIPPED = {')
    for _, key in ipairs({ 'minimap', 'minimap_mask', 'minimap_blur' }) do
        local r = rects[key]
        print(('    %-13s = { %8.4f, %8.4f, %8.4f, %8.4f },'):format(key, r[1], r[2], r[3], r[4]))
    end
    print('}')
    for _, key in ipairs({ 'bigmap', 'bigmap_mask', 'bigmap_blur', 'golf_courses' }) do
        local r, s = rects[key], STOCK[key]
        if r[1] ~= s[1] or r[2] ~= s[2] or r[3] ~= s[3] or r[4] ~= s[4] then
            print(('    %-13s = { %8.4f, %8.4f, %8.4f, %8.4f },   -- non-default'):format(key, r[1], r[2], r[3], r[4]))
        end
    end
    print(('    clipType = %d, radarZoom = %d, maskShape = %s, hideBars = %s'):format(
        opts.clipType, opts.radarZoom, tostring(opts.maskShape), tostring(opts.hideBars)))
    local f = rects.frame
    print(('[pf-hud:radartuner] client/skin.lua SHIPPED_FRAME = { %.4f, %.4f, %.4f, %.4f }  -- corner %.2f'):format(
        f[1], f[2], f[3], f[4], f[7] or 1))
    print(('    (this player\'s safe zone: %.3f; frameOver = %s)'):format(GetSafeZoneSize(), tostring(opts.frameOver)))
    cb('ok')
end)

RegisterNUICallback('radarTunerClose', function(_, cb)
    closeTuner()
    cb('ok')
end)
