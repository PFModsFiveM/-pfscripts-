-- PF Devices app registry.
--
-- Any resource registers its apps once:
--   exports['pf-devices']:RegisterApp({
--       id = 'taxi', name = 'Taxi', icon = '🚕',
--       devices = { 'tablet', 'computer' },          -- default: every device
--       entry = 'html/apps/taxi.js',                 -- module script, served from the registering resource
--       styles = { 'html/css/taxi.css' },            -- optional stylesheets
--       -- or kind = 'iframe', url = 'https://cfx-nui-<res>/page.html' for a legacy page
--       category = 'jobs', order = 10,
--       access = { jobs = { taxi = 0 }, onduty = false },  -- who sees it (see CanAccess)
--       window = { width = 900, height = 640 },
--   })
-- and its server handlers:
--   exports['pf-devices']:RegisterAppHandler('taxi', 'getInit', function(src, payload) ... return { ok = true, ... } end)
--
-- Both shells ask the server which apps the player may use on that device (GetAppsFor). Nothing
-- about visibility is decided on the client.

PFDevices = PFDevices or {}

local Apps = {}        -- id -> normalized definition
local Handlers = {}    -- id -> { method -> fn(src, payload, ctx) }
local ByResource = {}  -- resource -> { id = true }

local function dbg(...)
    if Config.Debug then print('^5[pf-devices]^7', ...) end
end

local function started(resource)
    if resource == GetCurrentResourceName() then return true end
    return GetResourceState(resource) == 'started'
end

local function cleanId(v)
    if type(v) ~= 'string' then return nil end
    local id = v:lower():gsub('[^%w%-_]', '')
    if id == '' or #id > 48 then return nil end
    return id
end

local function cleanText(v, max, default)
    if type(v) ~= 'string' then return default end
    v = v:gsub('[%c]', ''):sub(1, max)
    if v == '' then return default end
    return v
end

local function normalizeDevices(list)
    local out, seen = {}, {}
    if type(list) ~= 'table' or next(list) == nil then
        for name in pairs(Config.Devices) do out[#out + 1] = name end
        table.sort(out)
        return out
    end
    for _, d in ipairs(list) do
        d = tostring(d):lower()
        if Config.Devices[d] and not seen[d] then
            seen[d] = true
            out[#out + 1] = d
        end
    end
    table.sort(out)
    return out
end

local function normalizeAccess(access)
    if access == nil then return { anyone = true } end
    if type(access) ~= 'table' then return nil, 'access must be a table' end
    local out = {}
    if access.anyone == true then out.anyone = true end
    if access.jobs ~= nil then
        if type(access.jobs) ~= 'table' then return nil, 'access.jobs must be a table' end
        local jobs = {}
        for k, v in pairs(access.jobs) do
            if type(k) == 'number' then
                if type(v) == 'string' then jobs[v] = 0 end
            elseif type(k) == 'string' then
                jobs[k] = tonumber(v) or 0
            end
        end
        if next(jobs) == nil then return nil, 'access.jobs is empty' end
        out.jobs = jobs
    end
    if access.onduty == true then out.onduty = true end
    if access.gov ~= nil then
        local perms = {}
        if type(access.gov) == 'string' then perms[1] = access.gov
        elseif type(access.gov) == 'table' then for _, p in ipairs(access.gov) do if type(p) == 'string' then perms[#perms + 1] = p end end end
        if #perms == 0 then return nil, 'access.gov must name a permission' end
        out.gov = perms
    end
    if access.admin == true then out.admin = true end
    if access.installable == true then out.installable = true end
    if access.check ~= nil then
        if type(access.check) ~= 'table' or type(access.check.resource) ~= 'string' or type(access.check.export) ~= 'string' then
            return nil, 'access.check needs { resource, export }'
        end
        out.check = { resource = access.check.resource, export = access.check.export }
    end
    if access.handler == true then out.handler = true end
    if next(out) == nil then return nil, 'access has no rule' end
    return out
end

--- Validates and normalizes an app definition. Returns def or nil, err.
local function normalize(def, resource)
    if type(def) ~= 'table' then return nil, 'app definition must be a table' end
    local id = cleanId(def.id)
    if not id then return nil, 'app id must be a short string (letters, digits, - or _)' end
    if type(resource) ~= 'string' or resource == '' then return nil, 'unknown registering resource' end

    local kind = def.kind
    if kind == nil then kind = (type(def.url) == 'string') and 'iframe' or 'module' end
    if kind ~= 'module' and kind ~= 'iframe' and kind ~= 'launch' then return nil, 'kind must be module, iframe or launch' end

    local entry, url, launch
    if kind == 'launch' then
        -- opens a resource's own screen (e.g. an MDT) with a client event of that resource
        if type(def.launch) ~= 'table' or type(def.launch.event) ~= 'string' or def.launch.event == '' then
            return nil, 'launch apps need launch.event'
        end
        launch = { event = def.launch.event:sub(1, 120), args = type(def.launch.args) == 'table' and def.launch.args or nil }
    elseif kind == 'module' then
        entry = cleanText(def.entry, 200)
        if not entry or entry:find('^https?://') or entry:find('%.%.') then return nil, 'module apps need an entry script path inside the resource' end
    else
        url = cleanText(def.url, 400)
        if not url or not url:find('^https://cfx%-nui%-[%w%-_]+/') then return nil, 'iframe apps need a url of the form https://cfx-nui-<resource>/...' end
    end

    local styles = {}
    if type(def.styles) == 'table' then
        for _, s in ipairs(def.styles) do
            local st = cleanText(s, 200)
            if st and not st:find('%.%.') then styles[#styles + 1] = st end
        end
    end

    local access, err = normalizeAccess(def.access)
    if not access then return nil, err end

    local category = cleanText(def.category, 32, 'apps'):lower()
    local known = false
    for _, c in ipairs(Config.Categories) do if c.id == category then known = true break end end
    if not known then category = 'apps' end

    local window
    if type(def.window) == 'table' then
        window = { width = tonumber(def.window.width), height = tonumber(def.window.height) }
    end

    local store
    if type(def.store) == 'table' then
        store = {
            description = cleanText(def.store.description, 400, ''),
            publisher = cleanText(def.store.publisher, 80, resource),
            price = math.max(0, math.floor(tonumber(def.store.price) or 0)),
        }
    end

    return {
        id = id,
        name = cleanText(def.name or def.label, 60, id),
        icon = cleanText(def.icon, 80, '📦'),
        resource = resource,
        kind = kind,
        entry = entry,
        url = url,
        launch = launch,
        styles = styles,
        devices = normalizeDevices(def.devices),
        category = category,
        order = tonumber(def.order) or 100,
        access = access,
        window = window,
        store = store,
        pinned = def.pinned == true,
        version = cleanText(def.version and tostring(def.version), 16, '1'),
        description = cleanText(def.description, 200, ''),
    }
end

--- Registers (or replaces) an app. `resource` defaults to the invoking resource.
function PFDevices.RegisterApp(def, resource)
    resource = resource or GetInvokingResource() or GetCurrentResourceName()
    local app, err = normalize(def, resource)
    if not app then
        print(('^1[pf-devices]^7 %s: app not registered: %s'):format(tostring(resource), tostring(err)))
        return false, err
    end
    local existing = Apps[app.id]
    if existing and existing.resource ~= resource and started(existing.resource) then
        print(('^1[pf-devices]^7 %s: app id %s is owned by %s'):format(resource, app.id, existing.resource))
        return false, 'app id owned by ' .. existing.resource
    end
    Apps[app.id] = app
    ByResource[resource] = ByResource[resource] or {}
    ByResource[resource][app.id] = true
    if existing and existing.resource ~= resource then Handlers[app.id] = nil end
    dbg('registered', app.id, 'from', resource)
    PFDevices.NotifyAppsChanged(-1)
    return true
end

function PFDevices.UnregisterApp(id, resource)
    resource = resource or GetInvokingResource() or GetCurrentResourceName()
    id = cleanId(id)
    local app = id and Apps[id]
    if not app then return false end
    if app.resource ~= resource then return false end
    Apps[id] = nil
    Handlers[id] = nil
    if ByResource[resource] then ByResource[resource][id] = nil end
    PFDevices.NotifyAppsChanged(-1)
    return true
end

--- Registers a server handler for app `id`, called as fn(src, payload, ctx) from the RPC bridge.
function PFDevices.RegisterAppHandler(id, method, fn, resource)
    resource = resource or GetInvokingResource() or GetCurrentResourceName()
    id = cleanId(id)
    method = cleanText(method, 64)
    if not id or not method or type(fn) ~= 'function' then return false, 'bad handler' end
    local app = Apps[id]
    if app and app.resource ~= resource then return false, 'app id owned by ' .. app.resource end
    Handlers[id] = Handlers[id] or {}
    Handlers[id][method] = fn
    ByResource[resource] = ByResource[resource] or {}
    ByResource[resource]['__handlers:' .. id] = true
    return true
end

function PFDevices.RegisterAppHandlers(id, map, resource)
    resource = resource or GetInvokingResource() or GetCurrentResourceName()
    if type(map) ~= 'table' then return false, 'handlers must be a table' end
    for method, fn in pairs(map) do
        local ok, err = PFDevices.RegisterAppHandler(id, method, fn, resource)
        if not ok then return false, err end
    end
    return true
end

function PFDevices.GetHandler(id, method)
    local h = Handlers[id]
    return h and h[method] or nil
end

function PFDevices.GetApp(id)
    id = cleanId(id)
    return id and Apps[id] or nil
end

function PFDevices.GetApps()
    local out = {}
    for _, app in pairs(Apps) do out[#out + 1] = app end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return out
end

-- ── access ──────────────────────────────────────────────────────────

local function playerOf(src)
    local QBCore = exports['pfm-core']:GetCoreObject()
    return QBCore.Functions.GetPlayer(src)
end

local function isAdmin(src)
    if IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'pfdevices.admin') then return true end
    local ok, QBCore = pcall(function() return exports['pfm-core']:GetCoreObject() end)
    if ok and QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
        local ok2, allowed = pcall(QBCore.Functions.HasPermission, src, { 'admin', 'god' })
        return ok2 and allowed == true
    end
    return false
end

local function govAllows(src, perms)
    if GetResourceState('pf-government') ~= 'started' then return false end
    for _, perm in ipairs(perms) do
        local ok, allowed = pcall(function() return exports['pf-government']:HasPermission(src, perm) end)
        if ok and allowed == true then return true end
    end
    return false
end

--- Decides whether `src` may see and use the app, ignoring installation (see installs.lua).
--- Every rule in `access` must pass (`anyone` passes by itself).
function PFDevices.CanAccess(src, app)
    if type(app) == 'string' then app = Apps[app] end
    if not app then return false end
    local access = app.access
    if access.jobs or access.onduty then
        local Player = playerOf(src)
        local job = Player and Player.PlayerData and Player.PlayerData.job
        if not job then return false end
        if access.jobs then
            local min = access.jobs[job.name]
            if min == nil then return false end
            local grade = tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or 0
            if grade < min then return false end
        end
        if access.onduty and not job.onduty then return false end
    end
    if access.gov and not govAllows(src, access.gov) then return false end
    if access.admin and not isAdmin(src) then return false end
    if access.check then
        if not started(access.check.resource) then return false end
        local ok, allowed = pcall(function() return exports[access.check.resource][access.check.export](nil, src, app.id) end)
        if not (ok and allowed == true) then return false end
    end
    if access.handler then
        local fn = PFDevices.GetHandler(app.id, '__access')
        if not fn then return false end
        local ok, allowed = pcall(fn, src, {}, { app = app.id, method = '__access' })
        if not (ok and allowed == true) then return false end
    end
    return true
end

--- Public view of an app for a client (no access rules, URLs resolved).
local function publicView(app, installed)
    local base = 'https://cfx-nui-' .. app.resource .. '/'
    local styles = {}
    for i, s in ipairs(app.styles) do styles[i] = base .. s end
    return {
        id = app.id,
        name = app.name,
        icon = app.icon,
        resource = app.resource,
        kind = app.kind,
        entry = app.entry and (base .. app.entry) or nil,
        url = app.url,
        styles = styles,
        category = app.category,
        order = app.order,
        window = app.window,
        pinned = app.pinned,
        version = app.version,
        description = app.description,
        installable = app.access.installable == true,
        installed = installed,
        store = app.store,
    }
end

--- The apps `src` may use on `device`: { apps = {...}, store = {...} }. `store` lists the
--- installable apps the player is allowed to install but has not.
function PFDevices.GetAppsFor(src, device)
    device = type(device) == 'string' and device:lower() or nil
    if not device or not Config.Devices[device] then return { apps = {}, store = {}, error = 'unknown_device' } end
    local Player = playerOf(src)
    local citizenid = Player and Player.PlayerData and Player.PlayerData.citizenid
    local apps, store = {}, {}
    for _, app in ipairs(PFDevices.GetApps()) do
        local onDevice = false
        for _, d in ipairs(app.devices) do if d == device then onDevice = true break end end
        if onDevice and not app.site and started(app.resource) and PFDevices.CanAccess(src, app) then
            if app.access.installable then
                local installed = citizenid ~= nil and PFDevices.IsAppInstalled(citizenid, app.id)
                if installed then apps[#apps + 1] = publicView(app, true)
                else store[#store + 1] = publicView(app, false) end
            else
                apps[#apps + 1] = publicView(app, false)
            end
        end
    end
    return { apps = apps, store = store, categories = Config.Categories, device = device }
end

--- True when the player may use the app right now (access rules and, if installable, installed).
function PFDevices.CanUseApp(src, id)
    local app = PFDevices.GetApp(id)
    if not app or not started(app.resource) then return false, 'unknown_app' end
    if not PFDevices.CanAccess(src, app) then return false, 'not_authorized' end
    if app.access.installable then
        local Player = playerOf(src)
        local citizenid = Player and Player.PlayerData and Player.PlayerData.citizenid
        if not citizenid or not PFDevices.IsAppInstalled(citizenid, app.id) then return false, 'not_installed' end
    end
    return true
end

-- Apps and handlers of a stopped resource disappear; it registers again when it starts.
AddEventHandler('onResourceStop', function(resource)
    local owned = ByResource[resource]
    if not owned then return end
    for key in pairs(owned) do
        local id = key:match('^__handlers:(.+)$')
        if id then Handlers[id] = nil
        else Apps[key] = nil; Handlers[key] = nil end
    end
    ByResource[resource] = nil
    PFDevices.NotifyAppsChanged(-1)
end)

-- Test hook: wipe the registry (used by the test harness only).
function PFDevices.__reset()
    Apps, Handlers, ByResource = {}, {}, {}
end
