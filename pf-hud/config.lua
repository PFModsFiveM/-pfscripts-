Config = {}

-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  PF HUD — configuration                                          ║
-- ║  Everything a player can change in-game lives under              ║
-- ║  Config.Defaults (menu: /hud or the key below). Everything the   ║
-- ║  server controls lives in the sections after it.                 ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ── Keybinds ─────────────────────────────────────────────────────────
Config.OpenMenu = 'I'       -- Key that opens the HUD settings menu (players can rebind in GTA settings)

-- ── Player-adjustable defaults (saved per player, changed via menu) ──
Config.Defaults = {
    hudStyle      = 'rings',   -- 'rings' (circular icons), 'bars' (slim bars), 'minimal' (icons only when low)
    accent        = '#5b9dff', -- accent color; menu offers presets
    scale         = 1.0,       -- overall HUD scale (0.8 - 1.3)
    idleFade      = true,      -- fade out statuses that are full / inactive
    showCompass   = true,      -- compass pill at the top
    compassOnFoot = false,     -- also show the compass while on foot
    showStreets   = true,      -- street names inside the compass pill
    minimapShape  = 'rounded', -- 'rounded' | 'square' | 'circle'
    minimapOnFoot = false,     -- keep the minimap visible while on foot
    speedUnit     = 'mph',     -- 'mph' | 'kmh'
    showMoney     = true,      -- cash/bank popups on change
    cinematicMode = false,     -- black bars + hidden HUD
    showLogo      = true,      -- white iFruit logo on the minimap's top-left corner

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

    -- Per-element glass backgrounds. false = clean floating text/icons.
    boxes = {
        speedo  = true,
        status  = true,  -- applies to the 'bars' HUD style
        compass = true,
        icons   = true,  -- seatbelt / engine / nitro chips
        money   = true,
    },

    -- HUD layout: per-element position (percent of screen) and scale.
    -- nil = the element's default spot. Players edit via "Edit layout".
    -- Elements: status, speedo, vehicleIcons, nitro, compass, money.
    layout = {
        status       = nil, -- e.g. { x = 1.5, y = 85.0, scale = 1.0 }
        speedo       = nil,
        vehicleIcons = nil,
        nitro        = nil,
        compass      = nil,
        money        = nil,
    },
}

-- ── Vehicle ──────────────────────────────────────────────────────────
Config.DisableCarHud = false      -- true: never show the vehicle HUD
Config.LowFuelThreshold = 20      -- % at which the fuel bar turns red + warning pulse
Config.FuelExport = 'LegacyFuel'  -- resource with a GetFuel(vehicle) export ('' = use native fuel level)

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
    status  = 400,  -- ms between status HUD updates
    vehicle = 120,  -- ms between vehicle HUD updates while driving
    compass = 200,  -- ms between compass updates
}
