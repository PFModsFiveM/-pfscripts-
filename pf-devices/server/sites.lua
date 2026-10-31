-- Websites for the in-device browsers. A resource registers a site once and the same module
-- renders it in the tablet browser and the computer browser:
--
--   exports['pf-devices']:RegisterSite({ host = 'news.ls', name = 'Weazel News', icon = '📰',
--       entry = 'html/sites/news.js', styles = { 'html/css/news.css' }, access = { anyone = true } })
--
-- The module registers with PFApps.registerSite(host, { mount(container, ctx) }) and uses
-- ctx.rpc(method, payload), which runs the handlers registered for the site through RegisterSiteHandler.

PFDevices = PFDevices or {}

local Sites = {}        -- host -> def
local ByResource = {}   -- resource -> { host = true }

local function cleanHost(v)
    if type(v) ~= 'string' then return nil end
    local host = v:lower():gsub('^https?://', ''):gsub('/.*$', ''):gsub('[^%w%.%-]', '')
    if host == '' or #host > 64 then return nil end
    return host
end

function PFDevices.RegisterSite(def, resource)
    resource = resource or GetInvokingResource() or GetCurrentResourceName()
    if type(def) ~= 'table' then return false, 'site definition must be a table' end
    local host = cleanHost(def.host)
    if not host then return false, 'site host required' end
    local entry = type(def.entry) == 'string' and def.entry or nil
    if not entry or entry:find('^https?://') or entry:find('%.%.') then return false, 'site entry must be a script path inside the resource' end
    local existing = Sites[host]
    if existing and existing.resource ~= resource and GetResourceState(existing.resource) == 'started' then
        return false, 'host owned by ' .. existing.resource
    end
    local styles = {}
    for _, s in ipairs(type(def.styles) == 'table' and def.styles or {}) do
        if type(s) == 'string' and not s:find('%.%.') then styles[#styles + 1] = s end
    end
    -- Sites reuse the app registry for access rules and RPC handlers, under the id 'site:<host>'.
    local appId = ('site-' .. host:gsub('[^%w%-]', '-')):sub(1, 48)
    local ok, err = PFDevices.RegisterApp({
        id = appId,
        name = def.name or host,
        icon = def.icon or '🌐',
        kind = 'module',
        entry = entry,
        styles = styles,
        devices = {},
        category = 'media',
        access = def.access or { anyone = true },
        description = def.description,
    }, resource)
    if not ok then return false, err end
    local app = PFDevices.GetApp(appId)
    app.site = true          -- hidden from the home screen; GetAppsFor lists only non-site apps
    Sites[host] = { host = host, appId = appId, resource = resource, name = app.name, icon = app.icon, description = app.description }
    ByResource[resource] = ByResource[resource] or {}
    ByResource[resource][host] = true
    PFDevices.NotifyAppsChanged(-1)
    return true
end

function PFDevices.RegisterSiteHandler(host, method, fn, resource)
    resource = resource or GetInvokingResource() or GetCurrentResourceName()
    host = cleanHost(host)
    local site = host and Sites[host]
    if not site then return false, 'unknown site' end
    return PFDevices.RegisterAppHandler(site.appId, method, fn, resource)
end

function PFDevices.GetSite(host)
    host = cleanHost(host)
    return host and Sites[host] or nil
end

--- The sites `src` may open: list of { host, name, icon, appId, entry, styles, description }.
function PFDevices.GetSitesFor(src)
    local out = {}
    for host, site in pairs(Sites) do
        local app = PFDevices.GetApp(site.appId)
        if app and (app.resource == GetCurrentResourceName() or GetResourceState(app.resource) == 'started') and PFDevices.CanAccess(src, app) then
            local base = 'https://cfx-nui-' .. app.resource .. '/'
            local styles = {}
            for i, s in ipairs(app.styles) do styles[i] = base .. s end
            out[#out + 1] = { host = host, name = app.name, icon = app.icon, appId = app.id, entry = base .. app.entry, styles = styles, description = app.description, resource = app.resource }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

AddEventHandler('onResourceStop', function(resource)
    local owned = ByResource[resource]
    if not owned then return end
    for host in pairs(owned) do Sites[host] = nil end
    ByResource[resource] = nil
end)

function PFDevices.__resetSites()
    Sites, ByResource = {}, {}
end
