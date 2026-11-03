-- pf-justice tables (pf_schema_migrations key 'pf-justice'; PF_DATABASE_MIGRATIONS.md section 7).
-- This is the only file of the resource that runs migrations (the runner refuses a second
-- concurrent run of the same key). Other modules wait for PFJustice.Schema.Ready().
--
--   v1 core: every table of units 15B and 15C (orders, order events, citations, records, custody,
--      custody log, bookings, property, property items, bail) plus pf_justice_audit (the generic
--      audit table of architecture 3.8 for records and other non-order entities) and an idem_key
--      column on pf_justice_order_events (AdjustOrder / PayOrder retries are deduplicated by it).
--   v2 legacy import: a function step that calls PFJustice.LegacyImport.Run() (code in 15C
--      server/legacy_import.lua). If that code is not loaded or fails, v2 stays unapplied and runs
--      again at the next start (the import itself is idempotent through legacy_ref).
--
-- Every step is rerun-safe: DDL auto-commits, so an interrupted version restarts from its first step.

PFJustice = PFJustice or {}
PFJustice.Schema = PFJustice.Schema or {}
local Schema = PFJustice.Schema

Schema.KEY = 'pf-justice'

Schema.V1 = {
    [[CREATE TABLE IF NOT EXISTS `pf_justice_orders` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `citizenid` VARCHAR(64) NOT NULL,
      `kind` VARCHAR(20) NOT NULL,
      `state` VARCHAR(16) NOT NULL,
      `facility` VARCHAR(32) NULL,
      `clock` VARCHAR(8) NULL,
      `required_seconds` INT NULL, `served_seconds` INT NOT NULL DEFAULT 0,
      `credit_seconds` INT NOT NULL DEFAULT 0, `forfeit_seconds` INT NOT NULL DEFAULT 0,
      `last_tick_at` BIGINT NULL, `release_at` BIGINT NULL,
      `amount` INT NULL, `paid_amount` INT NOT NULL DEFAULT 0, `pay_attempt` INT NOT NULL DEFAULT 0, `pay_key` VARCHAR(128) NULL,
      `invoice_id` INT NULL, `victim_cid` VARCHAR(64) NULL,
      `units` INT NULL, `units_done` INT NOT NULL DEFAULT 0,
      `days` INT NULL, `conditions` LONGTEXT NULL,
      `charges` LONGTEXT NULL,
      `source_type` VARCHAR(16) NULL, `source_id` VARCHAR(64) NULL,
      `custody_id` INT NULL, `parent_order_id` INT NULL,
      `starts_at` BIGINT NULL, `due_at` BIGINT NULL, `ends_at` BIGINT NULL,
      `idem_key` VARCHAR(128) NULL, `legacy_ref` VARCHAR(64) NULL,
      `created_by` VARCHAR(64) NULL, `created_at` BIGINT NOT NULL, `updated_at` BIGINT NOT NULL,
      PRIMARY KEY (`id`),
      UNIQUE KEY `uq_jo_key` (`idem_key`), UNIQUE KEY `uq_jo_legacy` (`legacy_ref`),
      KEY `idx_jo_cid` (`citizenid`, `kind`, `state`), KEY `idx_jo_state` (`kind`, `state`), KEY `idx_jo_source` (`source_type`, `source_id`),
      KEY `idx_jo_invoice` (`invoice_id`), KEY `idx_jo_victim` (`victim_cid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_order_events` (
      `id` BIGINT NOT NULL AUTO_INCREMENT, `order_id` INT NOT NULL, `action` VARCHAR(20) NOT NULL,
      `detail` LONGTEXT NULL, `actor_cid` VARCHAR(64) NULL, `actor_kind` VARCHAR(8) NULL, `actor_resource` VARCHAR(48) NULL,
      `idem_key` VARCHAR(128) NULL, `at` BIGINT NOT NULL,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_joe_key` (`idem_key`), KEY `idx_joe_order` (`order_id`, `at`), KEY `idx_joe_at` (`at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    -- an installation that created the events table from the plan's first draft gets the column too
    'ALTER TABLE `pf_justice_order_events` ADD COLUMN IF NOT EXISTS `idem_key` VARCHAR(128) NULL AFTER `actor_resource`',
    'CREATE UNIQUE INDEX IF NOT EXISTS `uq_joe_key` ON `pf_justice_order_events` (`idem_key`)',

    [[CREATE TABLE IF NOT EXISTS `pf_justice_citations` (
      `id` INT NOT NULL AUTO_INCREMENT, `order_id` INT NOT NULL, `uid` VARCHAR(32) NOT NULL,
      `violation` VARCHAR(48) NOT NULL, `plate` VARCHAR(16) NULL, `speed_kmh` SMALLINT NULL, `limit_kmh` SMALLINT NULL,
      `x` DECIMAL(9,2) NULL, `y` DECIMAL(9,2) NULL, `officer_cid` VARCHAR(64) NOT NULL, `contest_until` BIGINT NULL,
      `at` BIGINT NOT NULL,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_cit_uid` (`uid`), KEY `idx_cit_order` (`order_id`), KEY `idx_cit_officer` (`officer_cid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_records` (
      `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL,
      `kind` VARCHAR(12) NOT NULL,
      `ref_type` VARCHAR(16) NULL, `ref_id` VARCHAR(64) NULL, `summary` VARCHAR(500) NOT NULL,
      `expunged_at` BIGINT NULL, `expunged_by` VARCHAR(64) NULL, `expunge_ref` VARCHAR(64) NULL,
      `at` BIGINT NOT NULL,
      PRIMARY KEY (`id`), KEY `idx_jr_cid` (`citizenid`, `expunged_at`), KEY `idx_jr_ref` (`ref_type`, `ref_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_custody` (
      `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL,
      `state` VARCHAR(16) NOT NULL,
      `prev_state` VARCHAR(16) NULL,
      `facility` VARCHAR(32) NULL, `cell_id` VARCHAR(32) NULL, `officer_cid` VARCHAR(64) NULL,
      `reason` VARCHAR(255) NULL, `charges` LONGTEXT NULL, `incident_id` VARCHAR(32) NULL,
      `booking_no` VARCHAR(24) NULL, `hold_until` BIGINT NULL, `release_reason` VARCHAR(24) NULL,
      `opened_at` BIGINT NOT NULL, `updated_at` BIGINT NOT NULL, `closed_at` BIGINT NULL, `idem_key` VARCHAR(128) NULL,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_jc_key` (`idem_key`),
      KEY `idx_jc_cid` (`citizenid`, `closed_at`), KEY `idx_jc_state` (`state`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_custody_log` (
      `id` BIGINT NOT NULL AUTO_INCREMENT, `custody_id` INT NOT NULL, `kind` VARCHAR(20) NOT NULL,
      `data` LONGTEXT NULL, `actor_cid` VARCHAR(64) NULL, `at` BIGINT NOT NULL,
      PRIMARY KEY (`id`), KEY `idx_jcl_custody` (`custody_id`, `at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_bookings` (
      `id` INT NOT NULL AUTO_INCREMENT, `custody_id` INT NOT NULL, `booking_no` VARCHAR(24) NOT NULL,
      `citizenid` VARCHAR(64) NOT NULL, `fingerprint` VARCHAR(64) NULL, `bloodtype` VARCHAR(4) NULL,
      `dna_sample_ref` VARCHAR(64) NULL,
      `mugshot_url` VARCHAR(512) NULL, `client_supplied` TINYINT(1) NOT NULL DEFAULT 1,
      `height_cm` SMALLINT NULL, `marks` VARCHAR(255) NULL, `screening` VARCHAR(24) NULL, `notes` VARCHAR(500) NULL,
      `booked_by` VARCHAR(64) NOT NULL, `at` BIGINT NOT NULL,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_jb_no` (`booking_no`), UNIQUE KEY `uq_jb_custody` (`custody_id`), KEY `idx_jb_cid` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_property` (
      `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL, `custody_id` INT NULL, `order_id` INT NULL,
      `stash_id` VARCHAR(64) NOT NULL,
      `state` VARCHAR(12) NOT NULL,
      `reason` VARCHAR(128) NULL, `seized_by` VARCHAR(64) NULL, `seized_at` BIGINT NOT NULL, `returned_at` BIGINT NULL,
      `idem_key` VARCHAR(128) NULL, `legacy_ref` VARCHAR(64) NULL,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_jp_stash` (`stash_id`), UNIQUE KEY `uq_jp_key` (`idem_key`), UNIQUE KEY `uq_jp_legacy` (`legacy_ref`),
      KEY `idx_jp_cid` (`citizenid`, `state`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_property_items` (
      `id` BIGINT NOT NULL AUTO_INCREMENT, `property_id` INT NOT NULL, `item` VARCHAR(64) NOT NULL, `amount` INT NOT NULL,
      `info` LONGTEXT NULL, `state` VARCHAR(10) NOT NULL DEFAULT 'held',
      `evidence_id` INT NULL,
      PRIMARY KEY (`id`), KEY `idx_jpi_prop` (`property_id`),
      CONSTRAINT `fk_jpi_prop` FOREIGN KEY (`property_id`) REFERENCES `pf_justice_property` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_bail` (
      `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL, `custody_id` INT NULL, `order_id` INT NULL,
      `amount` INT NOT NULL, `conditions` LONGTEXT NULL,
      `state` VARCHAR(16) NOT NULL,
      `payer_cid` VARCHAR(64) NULL, `payer_name` VARCHAR(128) NULL, `pay_attempt` INT NOT NULL DEFAULT 0, `pay_key` VARCHAR(128) NULL,
      `offered_by` VARCHAR(64) NULL, `offered_at` BIGINT NOT NULL, `expires_at` BIGINT NOT NULL, `posted_at` BIGINT NULL,
      `closed_at` BIGINT NULL, `legacy_ref` VARCHAR(64) NULL,
      PRIMARY KEY (`id`), UNIQUE KEY `uq_jbl_legacy` (`legacy_ref`), KEY `idx_jbl_cid` (`citizenid`, `state`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `pf_justice_audit` (
      `id` BIGINT NOT NULL AUTO_INCREMENT, `entity` VARCHAR(24) NOT NULL, `entity_id` VARCHAR(64) NOT NULL,
      `action` VARCHAR(24) NOT NULL, `actor_cid` VARCHAR(64) NULL, `actor_kind` VARCHAR(8) NULL, `actor_resource` VARCHAR(48) NULL,
      `detail` LONGTEXT NULL, `at` BIGINT NOT NULL,
      PRIMARY KEY (`id`), KEY `idx_ja_entity` (`entity`, `entity_id`, `at`), KEY `idx_ja_at` (`at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

--- The v2 step: the legacy import of unit 15C. Raises when the code is missing so v2 is not recorded.
function Schema.LegacyImportStep()
    local LI = PFJustice.LegacyImport
    if type(LI) ~= 'table' or not PFJustice.Util.Callable(LI.Run) then
        error('PFJustice.LegacyImport.Run is not loaded; the legacy import runs at the next start')
    end
    local res = LI.Run()
    if type(res) == 'table' and res.ok == false then
        error('legacy import failed: ' .. tostring(res.error or res.message))
    end
end

Schema.Migrations = {
    { version = 1, name = 'justice core: orders, clock, records, custody, booking, property, bail', up = Schema.V1 },
    { version = 2, name = 'justice legacy import (MDT jails, offline injail, criminal-record flags)', up = Schema.LegacyImportStep },
}

local ready = false

local function run(list)
    local ok, res, err = pcall(function() return exports['pfm-core']:RunMigrations(Schema.KEY, list) end)
    if not ok then return false, tostring(res) end
    if res == false then return false, tostring(err) end
    return true
end

--- Applies v1 (tables) and then v2 (the import). Ready means v1 is applied: a failing import does not
--- stop orders from working, it is retried at the next start.
function Schema.Run()
    local ok, err = run({ Schema.Migrations[1] })
    if not ok then
        print(('^1[pf-justice]^7 schema v1 failed: %s'):format(tostring(err)))
        ready = false
        return false
    end
    ready = true
    local okImport, errImport = run(Schema.Migrations)
    if not okImport then
        print(('^3[pf-justice]^7 legacy import (v2) not applied yet: %s'):format(tostring(errImport)))
    end
    Schema.importApplied = okImport
    return true
end

function Schema.Ready() return ready end
