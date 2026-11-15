-- pf-hud settings: where each one is kept.
--
-- With pfm-ui started, the simple settings (toggles, choices, sliders) are pfm-ui player prefs in the group 'HUD',
-- so they show in the pause menu's Server Settings and pfm-ui keeps them (and the server can force them). The rest
-- (the theme's colours, the per-element boxes, the layout) and every setting when pfm-ui is not running are kept
-- here, in this resource's KVP 'pf-hud:settings', as before.
--
--     HudPrefs.load()            -> the settings table (Config.Defaults filled in)
--     HudPrefs.save(settings)    -> stores it (prefs through pfm-ui, the rest in KVP)
--     HudPrefs.define()          -> declares the prefs with pfm-ui (again after pfm-ui restarts)
--     HudPrefs.onChange(fn)      -> fn(name, value) when a pref changes outside the HUD (the pause menu)

HudPrefs = {}

local KVP = 'pf-hud:settings'
local UI = 'pfm-ui'
local GROUP = 'HUD'

local function opts(...)
    local out = {}
    for _, pair in ipairs({ ... }) do out[#out + 1] = { value = pair[1], label = pair[2] } end
    return out
end

--- Every setting that is also a pfm-ui pref: the HUD's name for it, the pref's key, and how it is shown.
--- `scale` is a percentage there (a slider of whole numbers) and a factor here.
HudPrefs.DEFS = {
    { name = 'hudStyle', key = 'hud.style', type = 'choice', label = 'Gauges',
      help = 'Black discs in a white rim that drains, discs that fill white in a capsule, or only the gauges that are not full.',
      options = opts({ 'black', 'Black' }, { 'classic', 'Classic' }, { 'minimal', 'Minimal' }) },
    { name = 'statusLayout', key = 'hud.statusLayout', type = 'choice', label = 'Gauge position',
      help = 'A row under the minimap\'s frame, or the bottom-left corner.',
      options = opts({ 'map', 'Under the map' }, { 'corner', 'Corner' }) },
    { name = 'idleFade', key = 'hud.idleFade', type = 'toggle', label = 'Fade full gauges',
      help = 'Gauges that are full or idle are drawn fainter.' },
    { name = 'scale', key = 'hud.scale', type = 'slider', label = 'HUD size', min = 80, max = 130, step = 5,
      help = 'The gauges, the dial and the capsules.', percent = true },
    { name = 'minimapStyle', key = 'hud.mapStyle', type = 'choice', label = 'Minimap look',
      help = 'A dark map in a white frame with a blue route, the dark map alone, or GTA\'s own map.',
      options = opts({ 'frame', 'Framed' }, { 'dark', 'Dark' }, { 'native', 'GTA' }) },
    { name = 'minimapShape', key = 'hud.mapShape', type = 'choice', label = 'Minimap shape',
      options = opts({ 'rounded', 'Rounded' }, { 'square', 'Square' }, { 'circle', 'Circle' }) },
    { name = 'mapBackground', key = 'hud.mapBackground', type = 'slider', label = 'Map background',
      min = 0, max = 100, step = 5,
      help = 'How solid the black behind the framed minimap is. Lower lets the world show through, as GTA\'s does.' },
    { name = 'minimapOnFoot', key = 'hud.mapOnFoot', type = 'toggle', label = 'Minimap on foot' },
    { name = 'minimapInVehicle', key = 'hud.mapInVehicle', type = 'toggle', label = 'Minimap in a vehicle' },
    { name = 'showLogo', key = 'hud.mapLogo', type = 'toggle', label = 'iFruit logo on the map' },
    { name = 'dialStyle', key = 'hud.dial', type = 'choice', label = 'Vehicle dial',
      help = 'Each car\'s own dashboard look, the PF dial on every car, a flat dial, or none.',
      options = opts({ 'custom', 'Each car\'s own' }, { 'pf', 'PF dial' }, { 'simple', 'Flat' }, { 'none', 'None' }) },
    { name = 'dialHorizon', key = 'hud.dialHorizon', type = 'choice', label = 'Aircraft horizon',
      options = opts({ 'ball', '3D ball' }, { 'flat', 'Flat disc' }) },
    { name = 'speedUnit', key = 'hud.speedUnit', type = 'choice', label = 'Speed unit',
      options = opts({ 'mph', 'mph' }, { 'kmh', 'km/h' }) },
    { name = 'showCompass', key = 'hud.compass', type = 'toggle', label = 'Compass' },
    { name = 'compassOnFoot', key = 'hud.compassOnFoot', type = 'toggle', label = 'Compass on foot' },
    { name = 'showStreets', key = 'hud.streets', type = 'toggle', label = 'Street names' },
    { name = 'showMoney', key = 'hud.money', type = 'toggle', label = 'Money changes',
      help = 'Cash and bank changes shown in the gauge capsule.' },
    { name = 'cinematicMode', key = 'hud.cinematic', type = 'toggle', label = 'Cinematic mode',
      help = 'Black bars, no HUD.' },
}

local BY_NAME, BY_KEY = {}, {}
for _, d in ipairs(HudPrefs.DEFS) do
    BY_NAME[d.name] = d
    BY_KEY[d.key] = d
end

function HudPrefs.uiRunning()
    return GetResourceState(UI) == 'started'
end

local function deepCopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

--- A pref value as the HUD keeps it, and back.
local function toHud(d, v)
    if d.percent then return (tonumber(v) or 100) / 100 end
    return v
end
local function toPref(d, v)
    if d.percent then return math.floor((tonumber(v) or 1) * 100 + 0.5) end
    return v
end

--- Older saved values, from before the WHIP look.
local STYLE_RENAMED = { rings = 'black', bars = 'classic' }

local function readKvp()
    local saved = GetResourceKvpString(KVP)
    if not saved or saved == '' then return {} end
    local ok, data = pcall(json.decode, saved)
    return (ok and type(data) == 'table') and data or {}
end

--- Declare every pref with pfm-ui (the default is this server's Config.Defaults). Safe to call again.
---@return integer defined
function HudPrefs.define()
    if not HudPrefs.uiRunning() then return 0 end
    local n = 0
    for _, d in ipairs(HudPrefs.DEFS) do
        local def = {
            key = d.key, group = GROUP, type = d.type, label = d.label, help = d.help,
            options = d.options, min = d.min, max = d.max, step = d.step,
            default = toPref(d, Config.Defaults[d.name]),
        }
        local ok, res = pcall(function() return exports[UI]:DefinePref(def) end)
        if ok and res ~= false then n = n + 1 end
    end
    return n
end

--- The settings: Config.Defaults, then what is saved here, then (pfm-ui running) the prefs.
---@return table
function HudPrefs.load()
    local merged = deepCopy(Config.Defaults)
    local data = readKvp()
    for k, v in pairs(data) do
        if merged[k] ~= nil then
            if type(merged[k]) == 'table' and type(v) == 'table' then
                for kk, vv in pairs(v) do merged[k][kk] = vv end
            else
                merged[k] = v
            end
        end
    end
    merged.hudStyle = STYLE_RENAMED[merged.hudStyle] or merged.hudStyle
    -- Once, for settings saved before the WHIP look: the old defaults that would hide it (a box behind the gauges, the
    -- logo on the map) go back to the new ones. A player can turn them on again.
    if next(data) ~= nil and GetResourceKvpInt('pf-hud:lookV4') ~= 1 then
        if type(merged.boxes) == 'table' then merged.boxes.status = Config.Defaults.boxes.status end
        merged.showLogo = Config.Defaults.showLogo
        SetResourceKvpInt('pf-hud:lookV4', 1)
    end
    if type(merged.layout) == 'table' then
        -- the old speedometer and icon chips are the dial now
        merged.layout.speedo, merged.layout.vehicleIcons, merged.layout.nitro = nil, nil, nil
    end

    if HudPrefs.uiRunning() then
        -- First run with pfm-ui: a value this player saved here before becomes their pref, once.
        local migrate = GetResourceKvpInt('pf-hud:prefsMigrated') ~= 1
        for _, d in ipairs(HudPrefs.DEFS) do
            local ok, v = pcall(function() return exports[UI]:GetPref(d.key) end)
            if migrate and data[d.name] ~= nil and data[d.name] ~= Config.Defaults[d.name] then
                local want = d.name == 'hudStyle' and (STYLE_RENAMED[data[d.name]] or data[d.name]) or data[d.name]
                pcall(function() exports[UI]:SetPref(d.key, toPref(d, want)) end)
                ok, v = pcall(function() return exports[UI]:GetPref(d.key) end)
            end
            if ok and v ~= nil then merged[d.name] = toHud(d, v) end
        end
        if migrate then SetResourceKvpInt('pf-hud:prefsMigrated', 1) end
    end
    merged.accent = (merged.theme and merged.theme.accent) or merged.accent
    return merged
end

--- Store the settings: the prefs through pfm-ui when it runs (the KVP keeps the rest), else all in KVP.
---@param settings table
function HudPrefs.save(settings)
    local useUi = HudPrefs.uiRunning()
    local kvp = {}
    for k, v in pairs(settings) do
        local d = BY_NAME[k]
        if d and useUi then
            local want = toPref(d, v)
            local ok, cur = pcall(function() return exports[UI]:GetPref(d.key) end)
            if not ok or cur ~= want then
                pcall(function() exports[UI]:SetPref(d.key, want) end)
            end
        else
            kvp[k] = v
        end
    end
    SetResourceKvp(KVP, json.encode(kvp))
end

local listeners = {}

--- fn(name, value) when one of the HUD's prefs changes in pfm-ui (the pause menu), in the HUD's terms.
function HudPrefs.onChange(fn)
    listeners[#listeners + 1] = fn
end

--- The pref's key for a setting (nil: kept only here).
function HudPrefs.keyOf(name)
    local d = BY_NAME[name]
    return d and d.key or nil
end

AddEventHandler('pfm-ui:prefChanged', function(key, value)
    local d = type(key) == 'string' and BY_KEY[key]
    if not d then return end
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, d.name, toHud(d, value))
        if not ok then print(('[pf-hud] pref %s: %s'):format(key, tostring(err))) end
    end
end)
