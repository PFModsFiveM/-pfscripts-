-- pf-jobs database tables (pf_schema_migrations, resource 'pf-jobs') and the clean-up when a
-- character is deleted. The garbage tables are still created by server/apps/garbage.lua itself;
-- taxi_* tables come from sql/taxi.sql.

PFJobsSchema = PFJobsSchema or {}

PFJobsSchema.Migrations = {
    {
        version = 1,
        name = 'bus driver stats and route log',
        up = {
            [[CREATE TABLE IF NOT EXISTS `bus_stats` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `citizen_id` VARCHAR(50) NOT NULL,
                `total_passengers` INT NOT NULL DEFAULT 0,
                `total_earnings` INT NOT NULL DEFAULT 0,
                `routes_completed` INT NOT NULL DEFAULT 0,
                `total_time` INT NOT NULL DEFAULT 0,
                `average_rating` FLOAT NOT NULL DEFAULT 5.0,
                `best_rating` FLOAT NOT NULL DEFAULT 0,
                `on_time_count` INT NOT NULL DEFAULT 0,
                `current_level` INT NOT NULL DEFAULT 1,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `last_updated` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY `uniq_citizen` (`citizen_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `bus_routes_log` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `citizen_id` VARCHAR(50) NOT NULL,
                `route_id` INT NOT NULL,
                `distance` FLOAT NOT NULL DEFAULT 0,
                `fare_earned` INT NOT NULL DEFAULT 0,
                `passengers_delivered` INT NOT NULL DEFAULT 0,
                `complete_time` INT NOT NULL DEFAULT 0,
                `rating` FLOAT NOT NULL DEFAULT 5.0,
                `on_time` TINYINT NOT NULL DEFAULT 0,
                `completed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY `idx_citizen` (`citizen_id`),
                KEY `idx_completed` (`completed_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 2,
        name = 'gruppe 6 levels and bought upgrades',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_gruppe6_xp` (
                `citizenid` VARCHAR(64) NOT NULL,
                `xp` INT NOT NULL DEFAULT 0,
                `level` INT NOT NULL DEFAULT 1,
                `last_contract` TIMESTAMP NULL DEFAULT NULL,
                `total_contracts` INT NOT NULL DEFAULT 0,
                `total_earned` INT NOT NULL DEFAULT 0,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- one row per upgrade a character owns; the price is what the ledger charged
            [[CREATE TABLE IF NOT EXISTS `pf_gruppe6_upgrades` (
                `citizenid` VARCHAR(64) NOT NULL,
                `upgrade_id` VARCHAR(32) NOT NULL,
                `price` INT NOT NULL DEFAULT 0,
                `purchased_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`, `upgrade_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 3,
        name = 'tow driver stats and flatbed rentals',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_tow_stats` (
                `citizenid` VARCHAR(64) NOT NULL,
                `xp` INT NOT NULL DEFAULT 0,
                `contracts` INT NOT NULL DEFAULT 0,
                `requests` INT NOT NULL DEFAULT 0,
                `towed` INT NOT NULL DEFAULT 0,
                `earned` INT NOT NULL DEFAULT 0,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- an open rental keeps its deposit; the row outlives a restart so the deposit can come back
            [[CREATE TABLE IF NOT EXISTS `pf_tow_rentals` (
                `citizenid` VARCHAR(64) NOT NULL,
                `rental_id` VARCHAR(64) NOT NULL,
                `model` VARCHAR(32) NOT NULL,
                `plate` VARCHAR(8) NOT NULL,
                `deposit` INT NOT NULL DEFAULT 0,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`),
                UNIQUE KEY `uniq_rental` (`rental_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

function PFJobsSchema.Run()
    local ok, res, err = pcall(function() return exports['pfm-core']:RunMigrations(GetCurrentResourceName(), PFJobsSchema.Migrations) end)
    if not ok or res == false then
        print('^1[pf-jobs]^7 migrations failed: ' .. tostring(ok and err or res))
        return false
    end
    TriggerEvent('pf-jobs:server:schemaReady')
    return true
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then PFJobsSchema.Run() end
end)

-- ── deleted characters ──────────────────────────────────────────────

-- Per-character rows, child tables first. Tables that do not exist on this server are skipped.
PFJobsSchema.CharacterRows = {
    { 'bus_routes_log', 'citizen_id' }, { 'bus_stats', 'citizen_id' },
    { 'taxi_rides_log', 'citizen_id' }, { 'taxi_vehicle_photos', 'citizen_id' }, { 'taxi_stats', 'citizen_id' },
    { 'pf_gruppe6_upgrades', 'citizenid' }, { 'pf_gruppe6_xp_log', 'citizenid' }, { 'pf_gruppe6_xp', 'citizenid' },
    { 'pf_gruppe6_group_members', 'citizenid' }, { 'pf_gruppe6_groups', 'host_citizenid' },
    { 'pf_garbage_group_members', 'citizenid' }, { 'pf_garbage_groups', 'host_citizenid' },
    { 'pf_garbage_xp', 'citizenid' }, { 'pf_garbage_upgrades', 'citizenid' }, { 'pf_garbage_sessions', 'citizenid' },
    { 'pf_tow_rentals', 'citizenid' }, { 'pf_tow_stats', 'citizenid' },
}

local function validCitizenId(cid)
    return type(cid) == 'string' and #cid > 0 and #cid <= 64 and cid:find('^[%w_%-]+$') ~= nil
end

--- Removes everything pf-jobs keeps for a deleted character: its rows, any crew or route it is in,
--- its flatbed. Returns the number of rows deleted, or nil for a bad citizen id.
function PFJobsSchema.ForgetCharacter(cid)
    if not validCitizenId(cid) then return nil end
    for _, module in ipairs({ PFJobsBus, PFJobsTow, PFJobsG6, PFJobsGarbage }) do
        if type(module) == 'table' and type(module.ForgetCitizen) == 'function' then
            local ok, err = pcall(module.ForgetCitizen, cid)
            if not ok then print('^1[pf-jobs]^7 forgetting a character failed: ' .. tostring(err)) end
        end
    end
    local names = {}
    for _, t in ipairs(PFJobsSchema.CharacterRows) do names[#names + 1] = t[1] end
    local ok, rows = pcall(MySQL.query.await, ('SELECT TABLE_NAME AS name FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (%s)')
        :format(string.rep('?', #names, ', ')), names)
    if not ok or type(rows) ~= 'table' then return 0 end
    local present = {}
    for _, r in ipairs(rows) do present[r.name or r.TABLE_NAME] = true end
    local deleted = 0
    for _, t in ipairs(PFJobsSchema.CharacterRows) do
        if present[t[1]] then
            local okDel, res = pcall(MySQL.update.await, ('DELETE FROM `%s` WHERE `%s` = ?'):format(t[1], t[2]), { cid })
            if okDel then deleted = deleted + (tonumber(res) or 0) end
        end
    end
    return deleted
end

-- Raised by pfm-core on the server after a character is deleted (not a net event).
AddEventHandler('pfm-core:server:characterDeleted', function(cid)
    PFJobsSchema.ForgetCharacter(cid)
end)
