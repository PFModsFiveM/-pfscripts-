-- pf-ambulancejob tables. This is the only file that runs migrations for the key 'pf-ambulancejob'
-- (the runner refuses a second concurrent run of one key). v1 moved here unchanged from
-- server/injury_database.lua, so installed servers do not apply it again. Other modules wait for
-- PFMed.Schema.Ready() before they query.

PFMed = PFMed or {}
PFMed.Schema = PFMed.Schema or {}
local Schema = PFMed.Schema

Schema.KEY = 'pf-ambulancejob'

local T_INJURIES = Config.Database.PlayerInjuries
local T_TREATMENTS = Config.Database.PlayerTreatmentLog

Schema.Migrations = {
    {
        version = 1,
        name = 'injury records, treatment log, health snapshots',
        up = function()
            MySQL.query.await(([[
                CREATE TABLE IF NOT EXISTS `%s` (
                    `id` INT AUTO_INCREMENT PRIMARY KEY,
                    `citizen_id` VARCHAR(50) NOT NULL,
                    `injury_type` VARCHAR(50) NOT NULL,
                    `severity` VARCHAR(20) NOT NULL,
                    `body_zone` VARCHAR(50) NOT NULL,
                    `health_percentage` INT DEFAULT 0,
                    `weapon` VARCHAR(50),
                    `recorded_by` VARCHAR(50),
                    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    `deleted_at` TIMESTAMP NULL,
                    INDEX `idx_citizen_id` (`citizen_id`),
                    INDEX `idx_created_at` (`created_at`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T_INJURIES))
            MySQL.query.await(([[
                CREATE TABLE IF NOT EXISTS `%s` (
                    `id` INT AUTO_INCREMENT PRIMARY KEY,
                    `citizen_id` VARCHAR(50) NOT NULL,
                    `treatment_type` VARCHAR(50) NOT NULL,
                    `treated_by` VARCHAR(50) NOT NULL,
                    `injury_id` INT NULL,
                    `duration` INT,
                    `effectiveness` INT DEFAULT 100,
                    `notes` TEXT,
                    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    `deleted_at` TIMESTAMP NULL,
                    INDEX `idx_citizen_id` (`citizen_id`),
                    INDEX `idx_treated_by` (`treated_by`),
                    FOREIGN KEY (`injury_id`) REFERENCES `%s`(`id`) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T_TREATMENTS, T_INJURIES))
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS `player_health_snapshot` (
                    `id` INT AUTO_INCREMENT PRIMARY KEY,
                    `citizen_id` VARCHAR(50) NOT NULL,
                    `health` INT,
                    `armor` INT,
                    `is_unconscious` BOOLEAN DEFAULT FALSE,
                    `last_damage_weapon` VARCHAR(50),
                    `last_damage_zone` VARCHAR(50),
                    `snapshot_taken_by` VARCHAR(50),
                    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX `idx_citizen_id` (`citizen_id`),
                    INDEX `idx_created_at` (`created_at`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]])
        end,
    },
    {
        version = 2,
        name = 'medical core: patients and injuries',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_med_patients` (
                `citizenid` VARCHAR(64) NOT NULL,
                `consciousness` VARCHAR(16) NOT NULL DEFAULT 'alert',
                `stage` VARCHAR(16) NOT NULL DEFAULT 'healthy',
                `blood_ml` INT NOT NULL DEFAULT 5000,
                `hgb_factor` DECIMAL(4,3) NOT NULL DEFAULT 1.000,
                `airway` VARCHAR(16) NOT NULL DEFAULT 'clear',
                `breathing` DECIMAL(4,3) NOT NULL DEFAULT 1.000,
                `pain` DECIMAL(4,2) NOT NULL DEFAULT 0,
                `temp_c` DECIMAL(4,1) NOT NULL DEFAULT 37.0,
                `toxins` LONGTEXT NULL,
                `drugs` LONGTEXT NULL,
                `arrest_since` BIGINT NULL,
                `down_since` BIGINT NULL,
                `dead_at` BIGINT NULL,
                `can_respawn_at` BIGINT NULL,
                `last_tick_at` BIGINT NULL,
                `updated_at` BIGINT NOT NULL,
                PRIMARY KEY (`citizenid`),
                KEY `idx_med_pat_cons` (`consciousness`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_med_injuries` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `type` VARCHAR(32) NOT NULL,
                `subtype` VARCHAR(32) NULL,
                `region` VARCHAR(32) NULL,
                `structure` VARCHAR(32) NULL,
                `severity` TINYINT NOT NULL,
                `stage` VARCHAR(16) NOT NULL DEFAULT 'injured',
                `bleed_ml_min` DECIMAL(7,2) NOT NULL DEFAULT 0,
                `pain` DECIMAL(4,2) NOT NULL DEFAULT 0,
                `mechanism` VARCHAR(32) NOT NULL,
                `attrs` LONGTEXT NULL,
                `treatments` LONGTEXT NULL,
                `source_attacker_cid` VARCHAR(64) NULL,
                `idem_key` VARCHAR(128) NULL,
                `legacy_id` INT NULL,
                `created_at` BIGINT NOT NULL,
                `stabilized_at` BIGINT NULL,
                `treated_at` BIGINT NULL,
                `recover_at` BIGINT NULL,
                `recovered_at` BIGINT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_med_inj_key` (`idem_key`),
                UNIQUE KEY `uq_med_inj_legacy` (`legacy_id`),
                KEY `idx_med_inj_open` (`citizenid`, `stage`),
                KEY `idx_med_inj_recover` (`stage`, `recover_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- pf_med_findings and pf_med_diagnoses are the diagnosis layers (what providers found and
        -- concluded), kept apart from pf_med_injuries (what is really there). Their DDL is the one
        -- PF_DATABASE_MIGRATIONS.md lists under v5; creating them here is rerun-safe for that step.
        version = 3,
        name = 'medical events and diagnosis layers',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_med_events` (
                `id` BIGINT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `action` VARCHAR(32) NOT NULL,
                `actor_cid` VARCHAR(64) NULL,
                `actor_src` INT NULL,
                `actor_job` VARCHAR(32) NULL,
                `detail` LONGTEXT NULL,
                `at` BIGINT NOT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_med_ev_cid` (`citizenid`, `at`),
                KEY `idx_med_ev_action` (`action`, `at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_med_findings` (
                `id` BIGINT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL, `injury_id` INT NULL,
                `modality` VARCHAR(24) NOT NULL, `region` VARCHAR(32) NULL, `structure` VARCHAR(32) NULL,
                `sign` VARCHAR(48) NOT NULL, `certainty` VARCHAR(12) NOT NULL,
                `value` VARCHAR(64) NULL, `by_cid` VARCHAR(64) NULL, `by_tier` TINYINT NULL, `at` BIGINT NOT NULL,
                PRIMARY KEY (`id`), KEY `idx_med_find_cid` (`citizenid`, `at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_med_diagnoses` (
                `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL, `injury_id` INT NULL,
                `structure` VARCHAR(32) NULL, `injury_type` VARCHAR(32) NOT NULL,
                `status` VARCHAR(12) NOT NULL,
                `source` VARCHAR(16) NOT NULL,
                `by_cid` VARCHAR(64) NULL, `note` VARCHAR(255) NULL, `at` BIGINT NOT NULL,
                PRIMARY KEY (`id`), KEY `idx_med_dx_cid` (`citizenid`, `status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- a forced down state held against the automatic wake-up survives a relog
            [[ALTER TABLE `pf_med_patients` ADD COLUMN IF NOT EXISTS `hold_until` BIGINT NULL]],
        },
    },
    {
        -- 16B: anomaly reads per citizen (pf_med_events action 'anomaly'), then the one-time import
        -- of the legacy self-reported injuries (server/medical/legacy_import.lua; INSERT IGNORE on
        -- legacy_id, so a rerun after an interruption imports only what is missing). Without the
        -- import module the step fails and is retried at the next start instead of being skipped.
        version = 4,
        name = 'legacy injury import, anomaly index',
        up = function()
            MySQL.query.await('CREATE INDEX IF NOT EXISTS `idx_med_ev_cid_action` ON `pf_med_events` (`citizenid`, `action`, `at`)')
            if not (PFMed.LegacyImport and PFMed.LegacyImport.Run) then error('legacy import module not loaded') end
            PFMed.LegacyImport.Run()
        end,
    },
}

local ready = false
local running = false
local readyHandlers = {}

function Schema.Ready() return ready end

--- fn runs once the tables exist (at once when they already do).
function Schema.OnReady(fn)
    if ready then
        local ok, err = pcall(fn)
        if not ok then print('^1[pf-ambulancejob]^7 schema ready handler failed: ' .. tostring(err)) end
        return
    end
    readyHandlers[#readyHandlers + 1] = fn
end

-- pfm-core's export runs the migrations (function steps arrive there as function references); the
-- included @pfm-core/server/migrations.lua global is the fallback when the export is not reachable.
local function run(list)
    local called, ok, err = pcall(function() return exports['pfm-core']:RunMigrations(Schema.KEY, list) end)
    if called then return ok, err end
    if RunMigrations then return RunMigrations(Schema.KEY, list) end
    return false, 'pfm-core migrations unavailable: ' .. tostring(ok)
end

--- Applies pending migrations. Returns ok, err. Safe to call again.
function Schema.Start()
    if ready then return true end
    if running then return false, 'migrations already running' end
    running = true
    local ok, err = run(Schema.Migrations)
    running = false
    if not ok then
        print('^1[pf-ambulancejob]^7 medical tables not ready: ' .. tostring(err))
        return false, err
    end
    ready = true
    local handlers = readyHandlers
    readyHandlers = {}
    for _, fn in ipairs(handlers) do
        local okH, errH = pcall(fn)
        if not okH then print('^1[pf-ambulancejob]^7 schema ready handler failed: ' .. tostring(errH)) end
    end
    return true
end

CreateThread(function()
    Schema.Start()
end)
