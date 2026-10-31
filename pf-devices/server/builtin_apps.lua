-- Apps that ship with the platform: the App Store (install/uninstall installable apps) and the
-- Browser (opens registered sites with the same UI on every device).

PFDevices = PFDevices or {}

--- Registers the configured launchers whose resource is running (owned by that resource, so they
--- disappear when it stops).
function PFDevices.RegisterLaunchers(onlyResource)
    for _, l in ipairs(Config.Launchers or {}) do
        for _, res in ipairs(l.resources or {}) do
            if (not onlyResource or onlyResource == res) and GetResourceState(res) == 'started' then
                PFDevices.RegisterApp({
                    id = l.id, name = l.name, icon = l.icon, category = l.category, order = l.order,
                    kind = 'launch', launch = l.launch, access = l.access, devices = l.devices,
                    description = l.description,
                }, res)
                break
            end
        end
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then PFDevices.RegisterLaunchers(resource) end
end)

function PFDevices.RegisterBuiltinApps()
    local me = GetCurrentResourceName()
    PFDevices.RegisterLaunchers()

    PFDevices.RegisterApp({
        id = 'appstore',
        name = 'App Store',
        icon = '🛍️',
        entry = 'html/apps/appstore.js',
        category = 'system',
        order = 900,
        access = { anyone = true },
        description = 'Install and remove apps on this device',
    }, me)

    PFDevices.RegisterAppHandlers('appstore', {
        list = function(src, payload)
            local device = type(payload) == 'table' and payload.device or nil
            local view = PFDevices.GetAppsFor(src, device)
            local installed = {}
            for _, a in ipairs(view.apps or {}) do
                if a.installable then installed[#installed + 1] = a end
            end
            return { ok = true, store = view.store or {}, installed = installed }
        end,
        install = function(src, payload)
            return PFDevices.InstallApp(src, type(payload) == 'table' and payload.app or nil)
        end,
        uninstall = function(src, payload)
            return PFDevices.UninstallApp(src, type(payload) == 'table' and payload.app or nil)
        end,
    }, me)

    PFDevices.RegisterApp({
        id = 'browser',
        name = 'Browser',
        icon = '🌐',
        entry = 'html/apps/browser.js',
        devices = { 'tablet' }, -- the computer renders sites in its own browser
        category = 'system',
        order = 20,
        pinned = true,
        access = { anyone = true },
        description = 'City websites',
        window = { width = 980, height = 680 },
    }, me)

    PFDevices.RegisterAppHandlers('browser', {
        sites = function(src)
            return { ok = true, sites = PFDevices.GetSitesFor(src) }
        end,
    }, me)
end
