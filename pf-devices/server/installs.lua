-- Installable apps: which citizen installed which app (pf_device_apps), and which paid apps a
-- citizen bought (pf_device_app_purchases). An app with access.installable = true shows in the
-- App Store until installed, then on the home screen.

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
    {
        -- A paid app is bought once per citizen; the purchase outlives an uninstall, so a reinstall
        -- is free. Each purchase attempt has its own ledger key (tx_key), recorded here when paid.
        version = 2,
        name = 'paid app purchases per citizen',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_device_app_purchases` (
                `citizenid` VARCHAR(50) NOT NULL,
                `app_id` VARCHAR(48) NOT NULL,
                `price` INT NOT NULL,
                `tx_key` VARCHAR(128) NOT NULL,
                `purchased_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
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

--- Whether the citizen already bought this paid app. nil when the database could not be read.
local function ownsApp(citizenid, appId)
    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT app_id FROM pf_device_app_purchases WHERE citizenid = ? AND app_id = ?', { citizenid, appId })
    end)
    if not ok then return nil end
    return type(rows) == 'table' and rows[1] ~= nil
end

local function newPurchaseId()
    if type(PFPayout) == 'table' and type(PFPayout.NewId) == 'function' then return PFPayout.NewId() end
    return ('%d-%d'):format(os.time(), math.random(100000, 999999))
end

--- Charges a paid app once and records the purchase. Runs under the citizen's lock and only
--- when the citizen does not own the app yet. Every attempt has its own ledger key, so a failed
--- attempt (e.g. not enough money) never blocks a later one; the lock plus the ownership check
--- keep it to one charge per app. When the purchase cannot be recorded the charge is refunded.
local function buyApp(src, citizenid, app, price)
    if type(PFPayout) ~= 'table' or type(PFPayout.Charge) ~= 'function' then return { ok = false, error = 'banking_down' } end
    local key = ('pf-devices:install:%s:%s:%s'):format(citizenid, app.id, newPurchaseId())
    local ok, account = pcall(PFPayout.Charge, src, { 'bank', 'cash' }, price,
        { key = key, reason = ('App: %s'):format(app.name), kind = 'purchase' })
    if not ok or not account then return { ok = false, error = 'payment_failed' } end

    local recorded = pcall(function()
        MySQL.insert.await('INSERT INTO pf_device_app_purchases (citizenid, app_id, price, tx_key) VALUES (?, ?, ?, ?)',
            { citizenid, app.id, price, key .. ':' .. account })
    end)
    if recorded then return { ok = true } end

    local refunded = false
    if type(PFPayout.Pay) == 'function' then
        local pok, paid = pcall(PFPayout.Pay, citizenid, account, price,
            { key = key .. ':' .. account .. ':refund', kind = 'refund', reason = ('App refund: %s'):format(app.name), quiet = true })
        refunded = pok and paid == true
    end
    if not refunded then
        print(('^1[pf-devices]^7 purchase of %s by %s was charged (%s) but not recorded, and the refund failed'):format(app.id, citizenid, key .. ':' .. account))
    end
    return { ok = false, error = 'db_error', refunded = refunded }
end

local function installLocked(src, citizenid, app)
    if PFDevices.IsAppInstalled(citizenid, app.id) then return { ok = true, installed = true, already = true } end

    local price = app.store and tonumber(app.store.price) or 0
    if price > 0 then
        local owned = ownsApp(citizenid, app.id)
        if owned == nil then return { ok = false, error = 'db_error' } end
        if not owned then
            local res = buyApp(src, citizenid, app, price)
            if not res.ok then return res end
        end
    end

    local ok = pcall(function()
        MySQL.insert.await('INSERT IGNORE INTO pf_device_apps (citizenid, app_id) VALUES (?, ?)', { citizenid, app.id })
    end)
    if not ok then return { ok = false, error = 'db_error' } end
    cache[citizenid] = cache[citizenid] or {}
    cache[citizenid][app.id] = true
    return { ok = true, installed = true }
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

    -- One install or uninstall per citizen at a time: the lock is taken before the first wait
    -- (cache load, ownership check, charge), so two calls cannot both pass the checks and pay twice.
    if dirty[citizenid] then return { ok = false, error = 'busy' } end
    dirty[citizenid] = true
    local ok, res = pcall(installLocked, src, citizenid, app)
    dirty[citizenid] = nil
    if not ok then
        print(('^1[pf-devices]^7 install of %s failed: %s'):format(app.id, tostring(res)))
        return { ok = false, error = 'db_error' }
    end
    if res.ok and not res.already then PFDevices.NotifyAppsChanged(src) end
    return res
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

-- A deleted character's installed apps go with it (pfm-core fires this after the delete).
AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return end
    pcall(function() MySQL.query.await('DELETE FROM pf_device_apps WHERE citizenid = ?', { citizenid }) end)
    pcall(function() MySQL.query.await('DELETE FROM pf_device_app_purchases WHERE citizenid = ?', { citizenid }) end)
    cache[citizenid], dirty[citizenid] = nil, nil
end)

function PFDevices.__resetInstalls()
    cache, dirty = {}, {}
end
