Config = {}

-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  PF HUD — configuration                                          ║
-- ║  The look is ported from WHIP's HUD (see NOTICE.md): a row of    ║
-- ║  gauges under a framed dark minimap, and a 3D rev dial at the    ║
-- ║  bottom right in a vehicle.                                      ║
-- ║  Everything a player can change in-game lives under              ║
-- ║  Config.Defaults (menu: /hud or the key below; with pfm-ui       ║
-- ║  started most of them are also in the pause menu's Server        ║
-- ║  Settings, group HUD). Everything the server controls lives in   ║
-- ║  the sections after it.                                          ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ── Keybinds ─────────────────────────────────────────────────────────
Config.OpenMenu = 'I'       -- Key that opens the HUD settings menu (players can rebind in GTA settings)

-- ── Player-adjustable defaults (saved per player, changed via menu) ──
Config.Defaults = {
    hudStyle      = 'black',   -- the gauges: 'black' (black discs in a white rim that drains), 'classic' (discs
                               -- that fill white, in a capsule), 'minimal' (black, only gauges that are not full)
    statusLayout  = 'map',     -- 'map' (a row under the minimap's frame) | 'corner' (bottom left, under nothing)
    accent        = '#5b9dff', -- accent color; menu offers presets (kept in step with theme.accent)
    scale         = 1.0,       -- overall HUD scale (0.8 - 1.3)
    idleFade      = true,      -- fade out statuses that are full / inactive
    showCompass   = true,      -- compass capsule at the top
    compassOnFoot = false,     -- also show the compass while on foot
    showStreets   = true,      -- street names inside the compass capsule
    minimapStyle  = 'frame',   -- 'frame' (dark map, white frame, blue route) | 'dark' (dark map, no frame)
                               -- | 'native' (GTA's own map). The dark map needs pfm-media-map started.
    minimapShape  = 'rounded', -- 'rounded' | 'square' | 'circle'
    mapBackground = 100,       -- how solid the black behind the framed map is (0 - 100)
    minimapOnFoot = false,     -- keep the minimap visible while on foot
    minimapInVehicle = true,   -- show the minimap in a vehicle
    speedUnit     = 'mph',     -- 'mph' | 'kmh'
    dialStyle     = 'custom',  -- the vehicle dial: 'custom' (each car's own dashboard look, needs pfm-media-map),
                               -- 'pf' (the dial as designed on every car), 'simple' (a flat disc, no WebGL), 'none'
    dialHorizon   = 'ball',    -- aircraft attitude indicator: 'ball' (3D) | 'flat'
    showMoney     = true,      -- cash/bank changes shown in the gauge capsule
    cinematicMode = false,     -- black bars + hidden HUD
    showLogo      = false,     -- white iFruit logo on the minimap's top-left corner

    -- Global UI theme: shared with every PF-themed interface (menus, input,
    -- banking, multicharacter, scoreboard, notifications). Players edit these
    -- with RGB pickers in the HUD menu.
    theme = {
        primary   = '#111217', -- panel background
        secondary = '#1c1e26', -- fields / rows / headers
        accent    = '#5b9dff', -- highlights, buttons, rails
        text      = '#eceef2', -- foreground text
        opacity   = 0.92,      -- panel background opacity (0.5 - 1)
    },

    -- Per-element backgrounds. false = clean floating gauges/text.
    -- (speedo and icons are kept for old saved settings; the dial has no box.)
    boxes = {
        speedo  = true,
        status  = false, -- a capsule behind the gauges (the classic style always has one)
        compass = true,
        icons   = true,
        money   = true,
    },

    -- HUD layout: per-element position (percent of screen) and scale.
    -- nil = the element's default spot. Players edit via "Edit layout" (mouse or controller).
    -- Elements: status, dial, compass, money.
    layout = {
        status  = nil, -- e.g. { x = 1.5, y = 85.0, scale = 1.0 }
        dial    = nil, -- { x, y } is where the dial's box starts (percent), scale its size
        compass = nil,
        money   = nil,
    },
}

-- ── Minimap / native HUD ─────────────────────────────────────────────
Config.HideGtaCarNames = true   -- hide GTA's vehicle name, class, area and street texts (the compass shows streets)
Config.HideWhenDead = true      -- the gauges and dial fade out while the player is dead
Config.MediaMapResource = 'pfm-media-map' -- the dark radar tiles and the dial's dashboard looks live here

-- The radar tuner (/radartuner): an on-screen editor for the 18 SetMinimapComponentPosition values
-- and the frame. Admin-only (QBCore permission below); what it saves is this player's own.
Config.RadarTunerPermission = 'admin'

-- ── Vehicle ──────────────────────────────────────────────────────────
Config.DisableCarHud = false      -- true: never show the vehicle HUD
Config.LowFuelThreshold = 20      -- % at which the fuel gauge turns red
Config.FuelExport = 'LegacyFuel'  -- resource with a GetFuel(vehicle) export ('' = use native fuel level)

-- The 3D rev dial (WHIP's). GTA has no readable rev counter, so the top of the dial comes from the engine:
-- rpmByModel, else rpmElectric for an electric motor, else rpmByClass, else the measured class top
-- (pfm-media-map's data/rpm_by_model.lua), else rpmMax.
Config.VehicleHud = {
    rpmMax = 8,          -- the top of the dial in thousands (2 to 20) when nothing else says
    redline = 0.87,      -- where the red zone starts, as a share of the dial
    rpmElectric = 20,    -- an electric motor's top; its needle rests at 0
    idleRpm = 0.8,       -- where the needle rests at idle (thousands), every engine alike
    idleMeasured = false,-- true: each engine's own measured idle (needs pfm-media-map)
    rpmByClass = {
        compacts = 7, sedans = 7, suvs = 6, coupes = 7.5, muscle = 6.5, sportsclassics = 6.5, sports = 8,
        super = 9, motorcycles = 12, offroad = 6, industrial = 4, utility = 4, vans = 5.5, service = 4,
        emergency = 6.5, military = 4, commercial = 4, openwheel = 15,
    },
    rpmByModel = {},     -- { sultan = 8.5 }: one model's engine top, beats everything else
    flipBank = false,    -- true if an aircraft's horizon tips the wrong way when banking
}

-- ── Stress (same mechanics as before, server-validated) ──────────────
Config.StressEnabled = true
Config.StressChance = 0.1          -- chance (0-1) to gain stress per shot fired
Config.MinimumSpeed = 100          -- speeding over this (buckled) can cause stress
Config.MinimumSpeedUnbuckled = 50  -- speeding over this (unbuckled) can cause stress
Config.MinimumStress = 50          -- stress level where screen effects start
Config.DisablePoliceStress = false -- true: police job gains no stress

-- Weapons that never cause shooting stress
Config.WhitelistedWeaponStress = {
    `weapon_petrolcan`,
    `weapon_hazardcan`,
    `weapon_fireextinguisher`,
}

-- ── Money ────────────────────────────────────────────────────────────
Config.CurrencyText = '$'

-- ── Misc ─────────────────────────────────────────────────────────────
Config.UpdateRates = {
    status  = 250,  -- ms between status checks (sent only when something changed)
    vehicle = 120,  -- ms between vehicle checks while driving (fuel, belt, cruise; sent on change)
    compass = 200,  -- ms between compass updates
}
