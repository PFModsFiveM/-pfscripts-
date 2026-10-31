-- PF Devices: exports, player callbacks and start-up.

PFDevices = PFDevices or {}

local QBCore = exports['pfm-core']:GetCoreObject()

-- ── exports used by other resources ────────────────────────────────
exports('RegisterApp', function(def) return PFDevices.RegisterApp(def, GetInvokingResource()) end)
exports('UnregisterApp', function(id) return PFDevices.UnregisterApp(id, GetInvokingResource()) end)
exports('RegisterAppHandler', function(id, method, fn) return PFDevices.RegisterAppHandler(id, method, fn, GetInvokingResource()) end)
exports('RegisterAppHandlers', function(id, map) return PFDevices.RegisterAppHandlers(id, map, GetInvokingResource()) end)
exports('GetApp', function(id) return PFDevices.GetApp(id) end)
exports('GetApps', function() return PFDevices.GetApps() end)
exports('GetAppsFor', function(src, device) return PFDevices.GetAppsFor(src, device) end)
exports('CanUseApp', function(src, id) return PFDevices.CanUseApp(src, id) end)
exports('CanAccess', function(src, id) return PFDevices.CanAccess(src, id) end)
exports('Push', function(src, appId, event, payload) return PFDevices.Push(src, appId, event, payload) end)
exports('PushToCitizen', function(cid, appId, event, payload) return PFDevices.PushToCitizen(cid, appId, event, payload) end)
exports('PushToJob', function(job, appId, event, payload, ondutyOnly) return PFDevices.PushToJob(job, appId, event, payload, ondutyOnly) end)
exports('Broadcast', function(appId, event, payload) return PFDevices.Broadcast(appId, event, payload) end)
exports('NotifyAppsChanged', function(target) return PFDevices.NotifyAppsChanged(target) end)
exports('InstallApp', function(src, id) return PFDevices.InstallApp(src, id) end)
exports('UninstallApp', function(src, id) return PFDevices.UninstallApp(src, id) end)
exports('IsAppInstalled', function(cid, id) return PFDevices.IsAppInstalled(cid, id) end)
exports('RegisterSite', function(def) return PFDevices.RegisterSite(def, GetInvokingResource()) end)
exports('RegisterSiteHandler', function(host, method, fn) return PFDevices.RegisterSiteHandler(host, method, fn, GetInvokingResource()) end)
exports('GetSitesFor', function(src) return PFDevices.GetSitesFor(src) end)
exports('HandleRpc', function(src, appId, method, payload) return PFDevices.HandleRpc(src, appId, method, payload) end)

-- ── player callbacks used by the shells ────────────────────────────
QBCore.Functions.CreateCallback('pf-devices:apps', function(src, cb, device)
    cb(PFDevices.GetAppsFor(src, device))
end)

QBCore.Functions.CreateCallback('pf-devices:sites', function(src, cb)
    cb({ ok = true, sites = PFDevices.GetSitesFor(src) })
end)

-- App lists depend on job, grade and duty: tell the player's shells to refresh.
AddEventHandler('QBCore:Server:OnJobUpdate', function(src)
    if tonumber(src) then PFDevices.NotifyAppsChanged(src) end
end)
AddEventHandler('QBCore:Server:SetDuty', function(src)
    if tonumber(src) then PFDevices.NotifyAppsChanged(src) end
end)
AddEventHandler('QBCore:Server:OnPermissionUpdate', function(src)
    if tonumber(src) then PFDevices.NotifyAppsChanged(src) end
end)

-- A resource that registers apps may start before or after this one; when it starts after,
-- it registers itself. When pf-devices restarts, ask every started resource to register again.
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local ok, err = pcall(function() return exports['pfm-core']:RunMigrations(GetCurrentResourceName(), PFDevices.Migrations) end)
    if not ok then print('^1[pf-devices]^7 migrations failed: ' .. tostring(err)) end
    PFDevices.RegisterBuiltinApps()
    TriggerEvent('pf-devices:server:ready')
end)
