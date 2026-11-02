-- Versioned schema for the mechanic job's own tables (job offers, fitted parts, per-shop roles and
-- settings, the POS catalog key, the service book). The SQL auto-import (server/sql_init.lua) may
-- run after this, so every table altered here is first created with the definition from
-- pf_mechanic.sql. Steps are rerun-safe.
PFMech = PFMech or {}
PFMech.SchemaReady = false

local MIGRATION_KEY = 'pf-mechanicjob:core'
local DEFAULT_SHOP = (Config.DEFAULT_BRANDING and Config.DEFAULT_BRANDING.business) or 'mechanic'

local function tableExists(name)
    return (tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { name })) or 0) > 0
end

local function indexExists(tableName, indexName)
    return (tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?',
        { tableName, indexName })) or 0) > 0
end

local EMPLOYEES_TABLE = [[CREATE TABLE IF NOT EXISTS `pf_business_employees` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL UNIQUE,
  `name` VARCHAR(80) NOT NULL,
  `role` ENUM('owner','manager','employee') NOT NULL DEFAULT 'employee',
  `hired_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `last_promoted_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

local SETTINGS_TABLE = [[CREATE TABLE IF NOT EXISTS `pf_business_settings` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `business_name` VARCHAR(64) NOT NULL DEFAULT 'Los Santos Customs',
  `blip_name` VARCHAR(64) NOT NULL DEFAULT 'Customs Shop',
  `blip_color` INT NOT NULL DEFAULT 3,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

local POS_ITEMS_TABLE = [[CREATE TABLE IF NOT EXISTS `pf_pos_items` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `business` VARCHAR(50) NOT NULL,
  `item_id` VARCHAR(100) NOT NULL,
  `category` VARCHAR(50) NOT NULL,
  `label` VARCHAR(100) NOT NULL,
  `price` INT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_business` (`business`),
  UNIQUE KEY `unique_business_item` (`business`, `item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

local Migrations = {
    {
        version = 1,
        name = 'job offers a citizen accepts before joining a shop',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mech_job_offers` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `business` VARCHAR(50) NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `offered_by` VARCHAR(50) NOT NULL,
                `status` ENUM('pending','accepted','declined','cancelled') NOT NULL DEFAULT 'pending',
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `expires_at` DATETIME NOT NULL,
                `responded_at` DATETIME NULL DEFAULT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_business_citizen` (`business`, `citizenid`),
                KEY `idx_citizen_status` (`citizenid`, `status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 2,
        name = 'performance parts fitted per car slot',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mech_fitted_parts` (
                `plate` VARCHAR(16) NOT NULL,
                `slot` VARCHAR(24) NOT NULL,
                `item` VARCHAR(50) NOT NULL,
                `fitted_by` VARCHAR(50) NULL,
                `fitted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`plate`, `slot`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 3,
        name = 'staff roles belong to one shop',
        up = function()
            MySQL.query.await(EMPLOYEES_TABLE)
            MySQL.query.await([[ALTER TABLE `pf_business_employees`
                ADD COLUMN IF NOT EXISTS `business` VARCHAR(50) NULL,
                ADD COLUMN IF NOT EXISTS `grade` INT NOT NULL DEFAULT 0,
                ADD COLUMN IF NOT EXISTS `salary` INT NOT NULL DEFAULT 0,
                ADD COLUMN IF NOT EXISTS `avatar` VARCHAR(512) NULL,
                ADD COLUMN IF NOT EXISTS `last_online` TIMESTAMP NULL DEFAULT NULL,
                ADD INDEX IF NOT EXISTS `idx_business` (`business`)]])
            -- rows from before the column: the shop is the character's current job (row by row: the
            -- two tables may have different collations, which a join between them refuses)
            if tableExists('players') then
                local rows = MySQL.query.await('SELECT citizenid FROM pf_business_employees WHERE business IS NULL') or {}
                for _, r in ipairs(rows) do
                    local job = MySQL.scalar.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { r.citizenid })
                    local ok, parsed = pcall(json.decode, job or '')
                    if ok and type(parsed) == 'table' and type(parsed.name) == 'string' and #parsed.name <= 50 then
                        MySQL.update.await('UPDATE pf_business_employees SET business = ? WHERE citizenid = ? AND business IS NULL',
                            { parsed.name, r.citizenid })
                    end
                end
            end
        end,
    },
    {
        version = 4,
        name = 'business settings per shop',
        up = function()
            MySQL.query.await(SETTINGS_TABLE)
            MySQL.query.await('ALTER TABLE `pf_business_settings` ADD COLUMN IF NOT EXISTS `business` VARCHAR(50) NULL')
            -- the one global row belonged to the default shop
            MySQL.update.await('UPDATE pf_business_settings SET business = ? WHERE business IS NULL ORDER BY id LIMIT 1', { DEFAULT_SHOP })
            MySQL.update.await('DELETE FROM pf_business_settings WHERE business IS NULL')
            if not indexExists('pf_business_settings', 'uniq_settings_business') then
                MySQL.update.await([[DELETE s1 FROM pf_business_settings s1 JOIN pf_business_settings s2
                    ON s1.business = s2.business AND s1.id > s2.id]])
                MySQL.query.await('ALTER TABLE `pf_business_settings` ADD UNIQUE KEY `uniq_settings_business` (`business`)')
            end
        end,
    },
    {
        version = 5,
        name = 'one POS catalog row per shop and item',
        up = function()
            MySQL.query.await(POS_ITEMS_TABLE)
            if not indexExists('pf_pos_items', 'unique_business_item') then
                MySQL.update.await([[DELETE p1 FROM pf_pos_items p1 JOIN pf_pos_items p2
                    ON p1.business = p2.business AND p1.item_id = p2.item_id AND p1.id > p2.id]])
                MySQL.query.await('ALTER TABLE `pf_pos_items` ADD UNIQUE KEY `unique_business_item` (`business`, `item_id`)')
            end
        end,
    },
    {
        version = 6,
        name = 'service book entries',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_service_book` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `plate` VARCHAR(16) NOT NULL,
                `model` VARCHAR(60) NOT NULL DEFAULT '',
                `color` VARCHAR(40) NOT NULL DEFAULT '',
                `paint` VARCHAR(120) NOT NULL DEFAULT '',
                `title` VARCHAR(80) NOT NULL,
                `service` TEXT NOT NULL,
                `service_description` TEXT NOT NULL,
                `svc_date` VARCHAR(32) NOT NULL,
                `mileage` INT NOT NULL DEFAULT 0,
                `serviced_by` VARCHAR(80) NOT NULL DEFAULT '',
                `location` VARCHAR(80) NOT NULL DEFAULT '',
                KEY `plate_idx` (`plate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

--- Runs the pending migrations; true when every table is ready.
function PFMech.CoreSchema()
    local ok, res, err = pcall(function()
        if type(RunMigrations) == 'function' then return RunMigrations(MIGRATION_KEY, Migrations) end
        return exports['pfm-core']:RunMigrations(MIGRATION_KEY, Migrations)
    end)
    PFMech.SchemaReady = ok and res == true
    if not PFMech.SchemaReady then
        print('^1[pf-mechanicjob]^7 schema not ready (job offers, fitted parts, settings): ' .. tostring(ok and err or res))
    end
    return PFMech.SchemaReady
end

CreateThread(function() PFMech.CoreSchema() end)
