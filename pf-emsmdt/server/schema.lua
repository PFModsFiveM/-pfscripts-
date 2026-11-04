-- pf-emsmdt database schema: the only file that runs this resource's migrations.
--
-- pfm-core keeps the applied versions per key in pf_schema_migrations and refuses a second run of the
-- same key while one is going, so no other file of this resource may call RunMigrations. The key is the
-- resource name, as v1 used it (batch 14, from server/roster.lua): renaming the folder re-applies every
-- version, which is harmless because every step is rerun-safe.
--
-- v1  roster reset backups (moved here unchanged; installed servers do not re-apply it).
-- v2  every table the MDT used to create at start (server/main.lua, roster.lua, sop.lua, officers.lua),
--     with the same columns, plus the column upgrades that code ran on older installs.
--
-- Other files wait with PFEmsSchema.OnReady(fn) before their start-up work (seeds, legacy copies).

PFEmsSchema = PFEmsSchema or {}
local S = PFEmsSchema

S.KEY = GetCurrentResourceName()
-- The roster table name is fixed (server/roster.lua and server/officers.lua query it by this name).
S.ROSTER_TABLE = 'pf_emsmdt_roster'

-- Tables of v2, in creation order. Each statement is the one the start-up code ran before (same
-- columns and keys), so an install made by that code is left as it is.
S.TABLES = {
    { name = 'pf_emsmdt_patient_notes', sql = [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_patient_notes` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `citizenId` VARCHAR(50) NOT NULL,
        `text` LONGTEXT NOT NULL,
        `author` VARCHAR(100) NOT NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_pf_emsmdt_patient_notes_citizenId` (`citizenId`),
        KEY `idx_pf_emsmdt_patient_notes_createdAt` (`createdAt`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_emsmdt_user_profiles', sql = [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_user_profiles` (
        `citizenId` VARCHAR(50) NOT NULL,
        `callsign` VARCHAR(50) NULL,
        `status` VARCHAR(50) NULL,
        `avatarUrl` VARCHAR(255) NULL,
        `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`citizenId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_emsmdt_bulletins', sql = [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_bulletins` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `title` VARCHAR(255) NOT NULL,
        `body` LONGTEXT NOT NULL,
        `createdByCitizenId` VARCHAR(50) NULL,
        `createdByName` VARCHAR(100) NULL,
        `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_pf_emsmdt_bulletins_createdAt` (`createdAt`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = S.ROSTER_TABLE, sql = ([[CREATE TABLE IF NOT EXISTS `%s` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `callsign` VARCHAR(32) NOT NULL,
        `rank` VARCHAR(64) NOT NULL,
        `officer_name` VARCHAR(128) NOT NULL DEFAULT '',
        `citizenid` VARCHAR(64) NULL,
        `unit_type` VARCHAR(64) NOT NULL DEFAULT '',
        `training_status` VARCHAR(16) NOT NULL DEFAULT 'NONE',
        `notes` TEXT NULL,
        `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uniq_callsign` (`callsign`),
        KEY `idx_citizenid` (`citizenid`),
        KEY `idx_unit_type` (`unit_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(S.ROSTER_TABLE) },
    { name = 'pf_emsmdt_sops', sql = [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_sops` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `title` VARCHAR(128) NOT NULL,
        `category` VARCHAR(64) NOT NULL,
        `purpose` TEXT NOT NULL,
        `policy` TEXT NOT NULL,
        `procedure_text` TEXT NOT NULL,
        `notes` TEXT NULL,
        `updated_by` VARCHAR(128) NULL,
        `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_category` (`category`),
        KEY `idx_title` (`title`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_emsmdt_staff_mgmt_profiles', sql = [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_mgmt_profiles` (
        `citizenid` VARCHAR(64) NOT NULL,
        `hire_date` DATETIME NULL,
        `probation_until` DATETIME NULL,
        `is_fto` TINYINT(1) NOT NULL DEFAULT 0,
        `status` VARCHAR(32) NOT NULL DEFAULT 'ACTIVE',
        `terminated` TINYINT(1) NOT NULL DEFAULT 0,
        `terminated_at` DATETIME NULL,
        `terminated_by` VARCHAR(128) NULL,
        `terminated_reason` VARCHAR(255) NULL,
        `restrictions_json` LONGTEXT NULL,
        `flags_json` LONGTEXT NULL,
        `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_emsmdt_staff_discipline', sql = [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_discipline` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(64) NOT NULL,
        `type` VARCHAR(16) NOT NULL,
        `reason` TEXT NOT NULL,
        `issued_by` VARCHAR(128) NULL,
        `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `active` TINYINT(1) NOT NULL DEFAULT 1,
        `resolved_by` VARCHAR(128) NULL,
        `resolved_at` DATETIME NULL,
        `expires_at` DATETIME NULL,
        PRIMARY KEY (`id`),
        KEY `idx_disc_citizenid` (`citizenid`),
        KEY `idx_disc_active` (`active`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_emsmdt_staff_audit', sql = [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_audit` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `actor_citizenid` VARCHAR(64) NULL,
        `actor_name` VARCHAR(128) NULL,
        `target_citizenid` VARCHAR(64) NULL,
        `action` VARCHAR(64) NOT NULL,
        `before_json` LONGTEXT NULL,
        `after_json` LONGTEXT NULL,
        `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_audit_target` (`target_citizenid`),
        KEY `idx_audit_created` (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
}

-- Columns an older install may lack (server/officers.lua added these at every start). Checked through
-- information_schema, so the step also works on MySQL, which has no ADD COLUMN IF NOT EXISTS.
S.COLUMNS = {
    { 'pf_emsmdt_staff_mgmt_profiles', 'status', "`status` VARCHAR(32) NOT NULL DEFAULT 'ACTIVE'" },
    { 'pf_emsmdt_staff_mgmt_profiles', 'terminated', '`terminated` TINYINT(1) NOT NULL DEFAULT 0' },
    { 'pf_emsmdt_staff_mgmt_profiles', 'terminated_at', '`terminated_at` DATETIME NULL' },
    { 'pf_emsmdt_staff_mgmt_profiles', 'terminated_by', '`terminated_by` VARCHAR(128) NULL' },
    { 'pf_emsmdt_staff_mgmt_profiles', 'terminated_reason', '`terminated_reason` VARCHAR(255) NULL' },
}

local function columnExists(tableName, columnName)
    local n = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?]], { tableName, columnName })
    return (tonumber(n) or 0) > 0
end

-- v2 is one function step: plain SQL lists cannot hold the guarded column checks. Every part checks
-- before it writes, so a run cut off halfway simply starts again.
function S.ApplyV2()
    for _, t in ipairs(S.TABLES) do MySQL.query.await(t.sql) end
    for _, c in ipairs(S.COLUMNS) do
        if not columnExists(c[1], c[2]) then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(c[1], c[3]))
        end
    end
    -- An SOP table copied from the police MDT's old layout keeps its text in `procedure`; the code reads
    -- `procedure_text`. Renaming keeps the text (only when the new column is not there yet).
    if columnExists('pf_emsmdt_sops', 'procedure') and not columnExists('pf_emsmdt_sops', 'procedure_text') then
        MySQL.query.await('ALTER TABLE `pf_emsmdt_sops` CHANGE `procedure` `procedure_text` TEXT NOT NULL')
    end
end

S.Migrations = {
    {
        version = 1,
        name = 'roster reset backups',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_emsmdt_roster_backup` (
                `backup_id` INT NOT NULL AUTO_INCREMENT,
                `batch` VARCHAR(40) NOT NULL,
                `roster_id` INT NULL,
                `callsign` VARCHAR(32) NOT NULL,
                `rank` VARCHAR(64) NOT NULL DEFAULT '',
                `officer_name` VARCHAR(128) NOT NULL DEFAULT '',
                `citizenid` VARCHAR(64) NULL,
                `unit_type` VARCHAR(64) NOT NULL DEFAULT '',
                `training_status` VARCHAR(16) NOT NULL DEFAULT 'NONE',
                `notes` TEXT NULL,
                `by_citizenid` VARCHAR(64) NULL,
                `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`backup_id`),
                KEY `idx_emsmdt_roster_backup_batch` (`batch`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 2,
        name = 'EMS MDT tables (moved from start-up code)',
        up = function() S.ApplyV2() end,
    },
}

local ready, lastError = false, nil
local waiting = {}

function S.Ready() return ready end
function S.LastError() return lastError end

-- Runs fn once the schema is in place (in its own thread, so it may wait on the database).
function S.OnReady(fn)
    if ready then CreateThread(fn) return end
    waiting[#waiting + 1] = fn
end

-- One attempt; true when every version is applied. Safe to call again after a failure.
function S.Apply()
    if ready then return true end
    local ok, res, err = pcall(function() return exports['pfm-core']:RunMigrations(S.KEY, S.Migrations) end)
    if not (ok and res == true) then
        lastError = tostring(ok and (err or res) or res)
        print(('^1[pf-emsmdt]^7 schema migration failed (%s)'):format(lastError))
        return false
    end
    ready, lastError = true, nil
    local queued = waiting
    waiting = {}
    for _, fn in ipairs(queued) do CreateThread(fn) end
    return true
end

-- Start-up: a database or pfm-core that is not up yet gets a few more tries.
S.START_ATTEMPTS, S.RETRY_MS = 5, 10000
function S.Start()
    for attempt = 1, S.START_ATTEMPTS do
        if S.Apply() then return true end
        if attempt < S.START_ATTEMPTS then Wait(S.RETRY_MS) end
    end
    print('^1[pf-emsmdt]^7 the MDT tables are not ready: patient profiles, the roster reset and start-up seeds stay off until a restart')
    return false
end

-- For callers that need the tables now (the roster reset): applies the schema if it is not ready yet.
function S.Ensure()
    return ready or S.Apply()
end

CreateThread(S.Start)
