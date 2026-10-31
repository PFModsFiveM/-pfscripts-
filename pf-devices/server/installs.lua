-- Installable apps: which citizen installed which app (pf_device_apps). An app with
-- access.installable = true shows in the App Store until installed, then on the home screen.

PFDevices = PFDevices or {}

local cache = {}      -- citizenid -> { appId = true } or nil when not loaded
local dirty = {}      -- citizenid -> true while a write is in flight

PFDevices.Migrations = {
    {
        version = 1,
        name = 'installed apps per citizen',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_device_apps` (
                `citizenid` VARCHAR(50) NOT NULL,
                `app_id` VARCHAR(48) NOT NULL,
                `installed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`, `app_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

local function load(citizenid)
    local set = {}
    local rows = MySQL.query.await('SELECT app_id FROM pf_device_apps WHERE citizenid = ?', { citizenid }) or {}
    for _, r in ipairs(rows) do set[r.app_id] = true end
    cache[citizenid] = set
    return set
end

function PFDevices.IsAppInstalled(citizenid, appId)
    if type(citizenid) ~= 'string' or type(appId) ~= 'string' then return false end
    local set = cache[citizenid] or load(citizenid)
    return set[appId] == true
end

function PFDevices.GetInstalledApps(citizenid)
    if type(citizenid) ~= 'string' then return {} end
    local set = cache[citizenid] or load(citizenid)
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function citizenOf(src)
    local QBCore = exports['pfm-core']:GetCoreObject()
    local Player = QBCore.Functions.GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end

--- Installs an app for the player. The app must be installable and the player must pass its
--- access rules; a paid app is charged through the bank ledger when pfm-banking is running.
function PFDevices.InstallApp(src, appId)
    local app = PFDevices.GetApp(appId)
    if not app then return { ok = false, error = 'unknown_app' } end
    if not app.access.installable then return { ok = false, error = 'not_installable' } end
    if not PFDevices.CanAccess(src, app) then return { ok = false, error = 'not_authorized' } end
    local citizenid = citizenOf(src)
    if not citizenid then return { ok = false, error = 'no_player' } end
    if PFDevices.IsAppInstalled(citizenid, app.id) then return { ok = true, installed = true, already = true } end
    if dirty[citizenid] then return { ok = false, error = 'busy' } end

    -- A paid app is one ledger charge (PFPayout from @pfm-banking/payouts.lua) with a key that
    -- repeats for the same citizen and app, so a retry never charges twice.
    local price = app.store and app.store.price or 0
    if price > 0 then
        if type(PFPayout) ~= 'table' or type(PFPayout.Charge) ~= 'function' then return { ok = false, error = 'banking_down' } end
        local ok, account = pcall(PFPayout.Charge, src, { 'bank', 'cash' }, price,
            { key = 'pf-devices:install:' .. citizenid .. ':' .. app.id, reason = ('App: %s'):format(app.name), kind = 'purchase' })
        if not ok or not account then return { ok = false, error = 'payment_failed' } end
    end

    dirty[citizenid] = true
    local ok = pcall(function()
        MySQL.insert.await('INSERT IGNORE INTO pf_device_apps (citizenid, app_id) VALUES (?, ?)', { citizenid, app.id })
    end)
    dirty[citizenid] = nil
    if not ok then return { ok = false, error = 'db_error' } end
    cache[citizenid] = cache[citizenid] or {}
    cache[citizenid][app.id] = true
    PFDevices.NotifyAppsChanged(src)
    return { ok = true, installed = true }
end

function PFDevices.UninstallApp(src, appId)
    local app = PFDevices.GetApp(appId)
    local citizenid = citizenOf(src)
    if not citizenid then return { ok = false, error = 'no_player' } end
    local id = app and app.id or (type(appId) == 'string' and appId:lower() or nil)
    if not id then return { ok = false, error = 'unknown_app' } end
    if dirty[citizenid] then return { ok = false, error = 'busy' } end
    dirty[citizenid] = true
    local ok = pcall(function()
        MySQL.query.await('DELETE FROM pf_device_apps WHERE citizenid = ? AND app_id = ?', { citizenid, id })
    end)
    dirty[citizenid] = nil
    if not ok then return { ok = false, error = 'db_error' } end
    if cache[citizenid] then cache[citizenid][id] = nil end
    PFDevices.NotifyAppsChanged(src)
    return { ok = true, installed = false }
end

AddEventHandler('playerDropped', function()
    local src = source
    local citizenid = citizenOf(src)
    if citizenid then cache[citizenid] = nil end
end)

function PFDevices.__resetInstalls()
    cache, dirty = {}, {}
end
