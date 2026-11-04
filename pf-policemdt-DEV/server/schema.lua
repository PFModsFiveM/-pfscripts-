-- ============================================================================
-- PF Police MDT - the database schema (the one owner of this resource's migration key)
-- ============================================================================
-- Every table the MDT reads is created here, through pfm-core's versioned migration runner, under
-- the key GetCurrentResourceName() (pf_schema_migrations.resource = 'pf-policemdt-DEV' on a normal
-- install). The runner refuses a second concurrent run of one key, so no other file of this
-- resource calls it: they wait for PFMdtSchema.WaitReady() before their first query.
--
-- v1-v6 moved here unchanged from server/sentencing.lua (same numbers, names and SQL), so an
-- installed server does not apply them again. v7 creates the tables that used to exist only when
-- someone imported sql/pf-policemdt-qb.sql (and pf-policemdt-templates.sql) by hand, plus the ones
-- server/officers.lua, server/sop.lua and server/main.lua created on the fly. It is safe on a
-- database where those files were imported, also an older copy of them: tables are created only
-- when missing, the columns later versions of the file added are added only when missing, nothing
-- is dropped or rewritten, and the default rows are written only into a table that has none yet.

PFMdtSchema = PFMdtSchema or {}
local Schema = PFMdtSchema

Schema.KEY = GetCurrentResourceName()
Schema.state = Schema.state or 'idle' -- idle | running | ready | failed
Schema.lastError = Schema.lastError or nil

-- ── v1-v6 (moved unchanged from server/sentencing.lua) ──────────────────────

Schema.Migrations = {
    {
        version = 1,
        name = 'server-owned MDT jail',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_active_jails` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `sentence_id` INT NULL,
                `remaining_seconds` INT NOT NULL,
                `total_seconds` INT NOT NULL,
                `bail_amount` INT NOT NULL DEFAULT 0,
                `bail_key` VARCHAR(128) NULL,
                `bail_payer_cid` VARCHAR(64) NULL,
                `bail_payer_name` VARCHAR(128) NULL,
                `bail_started_at` INT NULL,
                `reason` VARCHAR(255) NULL,
                `items` LONGTEXT NULL,
                `provider` VARCHAR(32) NULL,
                `officer_citizenid` VARCHAR(64) NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_mdt_jail_citizen` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- the sentence row is written before any money moves; its id is the fine's ledger key
        version = 2,
        name = 'sentence payment state',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_sentences` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenId` VARCHAR(64) NOT NULL,
                `citizenName` VARCHAR(128) NULL,
                `officerCitizenId` VARCHAR(64) NULL,
                `officerName` VARCHAR(128) NULL,
                `title` VARCHAR(255) NOT NULL,
                `description` LONGTEXT NULL,
                `sentenceType` VARCHAR(24) NOT NULL,
                `charges` LONGTEXT NULL,
                `reductions` LONGTEXT NULL,
                `fineAmount` INT NOT NULL DEFAULT 0,
                `prisonTime` INT NOT NULL DEFAULT 0,
                `prisonTimeBeforeReduction` INT NOT NULL DEFAULT 0,
                `prisonTimeAfterReduction` INT NOT NULL DEFAULT 0,
                `reductionPercent` INT NOT NULL DEFAULT 0,
                `executed` TINYINT(1) NOT NULL DEFAULT 0,
                `fineSuccess` TINYINT(1) NOT NULL DEFAULT 0,
                `jailSuccess` TINYINT(1) NOT NULL DEFAULT 0,
                `error` TEXT NULL,
                `bailAmount` INT NOT NULL DEFAULT 0,
                `bailed` TINYINT(1) NOT NULL DEFAULT 0,
                `bailPaidByCitizenId` VARCHAR(64) NULL,
                `bailPaidByName` VARCHAR(128) NULL,
                `bailPaidAt` DATETIME NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_citizen` (`citizenId`),
                KEY `idx_createdAt` (`createdAt`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailAmount` INT NOT NULL DEFAULT 0',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailed` TINYINT(1) NOT NULL DEFAULT 0',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailPaidByCitizenId` VARCHAR(64) NULL',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailPaidByName` VARCHAR(128) NULL',
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `bailPaidAt` DATETIME NULL',
            "ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `status` VARCHAR(24) NOT NULL DEFAULT 'done'",
            'ALTER TABLE `pf_mdt_sentences` ADD COLUMN IF NOT EXISTS `fine_key` VARCHAR(128) NULL',
            'CREATE INDEX IF NOT EXISTS `idx_mdt_sentence_status` ON `pf_mdt_sentences` (`status`)',
        },
    },
    {
        version = 3,
        name = 'licence actions audit',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_license_actions` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `license_type` VARCHAR(32) NOT NULL,
                `action` VARCHAR(16) NOT NULL,
                `days` DECIMAL(10,2) NULL,
                `reason` VARCHAR(300) NULL,
                `by_citizenid` VARCHAR(64) NULL,
                `by_name` VARCHAR(128) NULL,
                `by_job` VARCHAR(32) NULL,
                `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_mdt_license_actions_cid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 4,
        name = 'charge changes audit',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_charge_audit` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `charge_id` INT NULL,
                `code` VARCHAR(16) NULL,
                `action` VARCHAR(16) NOT NULL,
                `before_json` LONGTEXT NULL,
                `after_json` LONGTEXT NULL,
                `by_citizenid` VARCHAR(64) NULL,
                `by_name` VARCHAR(128) NULL,
                `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_mdt_charge_audit_charge` (`charge_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- a roster reset copies every row here first (one batch per reset)
        version = 5,
        name = 'roster reset backups',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_mdt_roster_backup` (
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
                KEY `idx_mdt_roster_backup_batch` (`batch`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- a prisoner released while offline (bail, unjail) keeps the row until they load in, so the
        -- items come back then; this marks it as released so no second bail can be taken for it
        version = 6,
        name = 'jail released while offline',
        up = {
            'ALTER TABLE `pf_mdt_active_jails` ADD COLUMN IF NOT EXISTS `released_why` VARCHAR(16) NULL',
        },
    },
}

-- ── v7 tables ───────────────────────────────────────────────────────────────
-- Ported from sql/pf-policemdt-qb.sql and sql/pf-policemdt-templates.sql as CREATE TABLE IF NOT
-- EXISTS (the files' DROP TABLE lines are not ported). pf_mdt_sentences is v2's. The officer
-- management table carries is_supervisor and the indexes the SQL file added afterwards, and
-- pf_mdt_esx_license_suspensions (only ESX servers use it) used to be created by server/main.lua.
-- pf_mdt_fto_reports_legacy is not created: it is a pre-v2 FTO table that main.lua reads only
-- when an old install still has it.

Schema.Tables = {
    { name = 'pf_mdt_warrants', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_warrants` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `warrantId` VARCHAR(16) NOT NULL,
                `suspectCitizenId` VARCHAR(64) NULL,
                `suspectName` VARCHAR(128) NOT NULL,
                `charges` LONGTEXT NULL,
                `officers` LONGTEXT NULL,
                `witnesses` LONGTEXT NULL,
                `issuedBy` VARCHAR(128) NOT NULL,
                `title` VARCHAR(255) NULL,
                `narrative` LONGTEXT NULL,
                `status` VARCHAR(16) NOT NULL DEFAULT 'active',
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `expiresAt` DATETIME NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_warrantId` (`warrantId`),
                KEY `idx_suspect` (`suspectName`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_incidents', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_incidents` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `incidentId` VARCHAR(16) NOT NULL,
                `title` VARCHAR(255) NOT NULL,
                `priority` VARCHAR(12) NOT NULL DEFAULT 'LOW',
                `status` VARCHAR(16) NOT NULL DEFAULT 'active',
                `reportingOfficer` VARCHAR(128) NULL,
                `involvedCitizens` LONGTEXT NULL,
                `involvedOfficers` LONGTEXT NULL,
                `involvedVictims` LONGTEXT NULL,
                `involvedVehicles` LONGTEXT NULL,
                `charges` LONGTEXT NULL,
                `evidence_ids` LONGTEXT NULL,
                `involvedCitizenIds` LONGTEXT NULL,
                `involvedOfficerIds` LONGTEXT NULL,
                `involvedVictimIds` LONGTEXT NULL,
                `involvedVehicleIds` LONGTEXT NULL,
                `dateTime` DATETIME NULL,
                `location` VARCHAR(255) NULL,
                `narrative` LONGTEXT NULL,
                `createdBy` VARCHAR(64) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_incidentId` (`incidentId`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_reports', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_reports` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `reportId` VARCHAR(16) NOT NULL,
                `type` VARCHAR(64) NOT NULL,
                `category` VARCHAR(64) NULL,
                `title` VARCHAR(255) NOT NULL,
                `officer` VARCHAR(128) NOT NULL DEFAULT '',
                `procedure_text` TEXT NULL,
                `narrative` LONGTEXT NULL,
                `content` LONGTEXT NULL,
                `location` VARCHAR(255) NULL,
                `vehiclePlate` VARCHAR(16) NULL,
                `involvedParties` LONGTEXT NULL,
                `linkedEvidence` LONGTEXT NULL,
                `approvalStatus` VARCHAR(16) NOT NULL DEFAULT 'pending',
                `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
                `timestamp` DATETIME NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_reportId` (`reportId`),
                KEY `idx_content` (`content`(50)),
                KEY `idx_type` (`type`),
                KEY `idx_officer` (`officer`),
                KEY `idx_vehiclePlate` (`vehiclePlate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_roster', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_roster` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `callsign` VARCHAR(32) NOT NULL,
                `rank` VARCHAR(64) NOT NULL DEFAULT '',
                `officer_name` VARCHAR(128) NOT NULL DEFAULT '',
                `citizenid` VARCHAR(64) NULL,
                `unit_type` VARCHAR(64) NOT NULL DEFAULT '',
                `training_status` ENUM('NONE','TRAINING','TRAINEE') NOT NULL DEFAULT 'NONE',
                `notes` TEXT NULL,
                `created_at` DATETIME NOT NULL,
                `updated_at` DATETIME NOT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_callsign` (`callsign`),
                KEY `idx_citizenid` (`citizenid`),
                KEY `idx_rank` (`rank`),
                KEY `idx_unit_type` (`unit_type`),
                KEY `idx_training_status` (`training_status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_sops', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_sops` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `title` VARCHAR(128) NOT NULL,
                `category` VARCHAR(64) NOT NULL,
                `purpose` TEXT NOT NULL,
                `policy` TEXT NOT NULL,
                `procedure_text` TEXT NOT NULL,
                `notes` TEXT NULL,
                `updated_by` VARCHAR(128) NULL,
                `updated_at` DATETIME NULL,
                `created_at` DATETIME NULL,
                PRIMARY KEY (`id`),
                KEY `idx_sop_category` (`category`),
                KEY `idx_sop_title` (`title`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_fto_reports', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_fto_reports` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `report_uid` VARCHAR(16) NOT NULL,
                `status` ENUM('DRAFT','SUBMITTED','APPROVED','REJECTED') NOT NULL DEFAULT 'DRAFT',
                `trainee_cid` VARCHAR(50) NOT NULL,
                `trainee_name` VARCHAR(100) NOT NULL,
                `trainee_callsign` VARCHAR(50) DEFAULT NULL,
                `author_cid` VARCHAR(50) NOT NULL,
                `author_name` VARCHAR(100) NOT NULL,
                `phase` INT NOT NULL DEFAULT 1,
                `shift` ENUM('Morning','Evening','Night') NOT NULL DEFAULT 'Morning',
                `ride_date` DATETIME NOT NULL,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                `submitted_at` DATETIME DEFAULT NULL,
                `reviewed_by_cid` VARCHAR(50) DEFAULT NULL,
                `reviewed_by_name` VARCHAR(100) DEFAULT NULL,
                `reviewed_at` DATETIME DEFAULT NULL,
                `review_note` TEXT DEFAULT NULL,
                `ride_description` LONGTEXT DEFAULT NULL,
                `overall_rating` DECIMAL(3,1) DEFAULT NULL,
                `safety_concern` TINYINT(1) NOT NULL DEFAULT 0,
                `safety_concern_notes` TEXT DEFAULT NULL,
                `recommendation` ENUM('ADVANCE','REMAIN','REMEDIAL','TERMINATION') DEFAULT NULL,
                `strengths` TEXT DEFAULT NULL,
                `improvements` TEXT DEFAULT NULL,
                `evaluation_json` LONGTEXT NOT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_report_uid` (`report_uid`),
                KEY `idx_status` (`status`),
                KEY `idx_trainee` (`trainee_cid`),
                KEY `idx_author` (`author_cid`),
                KEY `idx_dates` (`ride_date`, `created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_bulletins', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_bulletins` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `title` VARCHAR(255) NOT NULL,
                `body` LONGTEXT NOT NULL,
                `createdByCitizenId` VARCHAR(64) NULL,
                `createdByName` VARCHAR(128) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_createdAt` (`createdAt`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_fto_report_audit', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_fto_report_audit` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `report_uid` VARCHAR(16) NOT NULL,
                `action` VARCHAR(32) NOT NULL,
                `actor_cid` VARCHAR(50) NOT NULL,
                `actor_name` VARCHAR(100) NOT NULL,
                `at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `details_json` LONGTEXT DEFAULT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_report_uid` (`report_uid`),
                KEY `idx_action` (`action`),
                KEY `idx_at` (`at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_citizen_notes', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_citizen_notes` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenId` VARCHAR(64) NOT NULL,
                `text` LONGTEXT NOT NULL,
                `author` VARCHAR(128) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_citizen` (`citizenId`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_citizen_flags', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_citizen_flags` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenId` VARCHAR(64) NOT NULL,
                `flag` VARCHAR(64) NOT NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_citizen` (`citizenId`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_citizen_profiles', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_citizen_profiles` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenId` VARCHAR(64) NOT NULL UNIQUE,
                `profilePicture` VARCHAR(512) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_citizen` (`citizenId`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_officer_mgmt_profiles', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_officer_mgmt_profiles` (
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
                `is_supervisor` TINYINT(1) NOT NULL DEFAULT 0,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`),
                KEY `idx_officer_terminated` (`terminated`),
                KEY `idx_status` (`status`),
                KEY `idx_terminated_status` (`terminated`, `status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_officer_discipline', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_officer_discipline` (
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
    { name = 'pf_mdt_officer_audit', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_officer_audit` (
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
    { name = 'pf_mdt_weapons_registry', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_weapons_registry` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `serial` VARCHAR(64) NOT NULL,
                `weapon` VARCHAR(64) NOT NULL,
                `weaponLabel` VARCHAR(128) NULL,
                `ownerCitizenId` VARCHAR(64) NOT NULL,
                `ownerName` VARCHAR(128) NULL,
                `registeredAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `registeredByCitizenId` VARCHAR(64) NULL,
                `registeredByName` VARCHAR(128) NULL,
                `notes` TEXT NULL,
                `stolen_status` TINYINT(1) NOT NULL DEFAULT 0,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_serial` (`serial`),
                KEY `idx_owner` (`ownerCitizenId`),
                KEY `idx_registered_at` (`registeredAt`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_officer_profiles', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_officer_profiles` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenId` VARCHAR(64) NOT NULL UNIQUE,
                `callsign` VARCHAR(32) NULL,
                `status` VARCHAR(16) NULL,
                `avatarUrl` VARCHAR(512) NULL,
                `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_officer_citizen` (`citizenId`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_vehicle_notes', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_notes` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(16) NOT NULL,
                `text` LONGTEXT NOT NULL,
                `author` VARCHAR(128) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_plate` (`plate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_vehicle_flags', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_flags` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(16) NOT NULL,
                `flag` VARCHAR(64) NOT NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_plate` (`plate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_vehicle_strikes', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_strikes` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(16) NOT NULL,
                `title` VARCHAR(255) NOT NULL,
                `offenseType` VARCHAR(64) NOT NULL,
                `points` INT NOT NULL DEFAULT 4,
                `description` TEXT NULL,
                `officer` VARCHAR(128) NOT NULL,
                `location` VARCHAR(255) NULL,
                `status` ENUM('active', 'expired', 'dismissed') NOT NULL DEFAULT 'active',
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `expiresAt` DATETIME NULL,
                `createdByName` VARCHAR(128) NULL,
                PRIMARY KEY (`id`),
                KEY `idx_plate` (`plate`),
                KEY `idx_status` (`status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_vehicle_activity', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_activity` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(16) NOT NULL,
                `type` VARCHAR(64) NOT NULL,
                `timestamp` DATETIME NULL,
                `location` VARCHAR(255) NULL,
                `officer` VARCHAR(128) NULL,
                `officerName` VARCHAR(128) NULL,
                `referenceId` VARCHAR(64) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_plate` (`plate`),
                KEY `idx_type` (`type`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_charges', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_charges` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `code` VARCHAR(16) NOT NULL UNIQUE,
                `name` VARCHAR(128) NOT NULL,
                `description` LONGTEXT NULL,
                `fineAmount` INT NOT NULL DEFAULT 0,
                `bailAmount` INT NOT NULL DEFAULT 0,
                `prisonTime` INT NOT NULL DEFAULT 0,
                `category` VARCHAR(64) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_code` (`code`),
                KEY `idx_category` (`category`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_pending_sentences', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_pending_sentences` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `minutes` INT NOT NULL DEFAULT 0,
                `reason` VARCHAR(255) NULL,
                `officer_citizenid` VARCHAR(64) NULL,
                `officer_name` VARCHAR(128) NULL,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_citizenid` (`citizenid`),
                KEY `idx_created_at` (`created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_incident_evidence', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_incident_evidence` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `incident_id` VARCHAR(64) NOT NULL,
                `evidence_number` INT NOT NULL,
                `title` VARCHAR(128) NOT NULL DEFAULT '',
                `description` TEXT NULL,
                `image_url` TEXT NOT NULL,
                `created_by_citizenid` VARCHAR(64) NOT NULL,
                `created_by_name` VARCHAR(128) NOT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_evidence` (`incident_id`, `evidence_number`),
                KEY `idx_incident` (`incident_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_evidence', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_evidence` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `evidence_id` VARCHAR(32) NOT NULL,
                `evidence_number` INT NOT NULL,
                `title` VARCHAR(255) NOT NULL,
                `description` TEXT NULL,
                `image_url` TEXT NOT NULL,
                `tags` VARCHAR(255) NULL,
                `location_details` VARCHAR(255) NULL,
                `incident_id` VARCHAR(64) NULL,
                `citizens_involved` LONGTEXT NULL,
                `vehicles_involved` LONGTEXT NULL,
                `weapons_involved` TEXT NULL,
                `related_charges` LONGTEXT NULL,
                `status` VARCHAR(32) NOT NULL DEFAULT 'Collected',
                `created_by_citizenid` VARCHAR(64) NOT NULL,
                `created_by_name` VARCHAR(128) NOT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_evidence_id` (`evidence_id`),
                UNIQUE KEY `uniq_evidence_number` (`evidence_number`),
                KEY `idx_incident` (`incident_id`),
                KEY `idx_created_by` (`created_by_citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_vehicle_profiles', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_profiles` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(16) NOT NULL UNIQUE,
                `vehiclePhoto` VARCHAR(512) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_plate` (`plate`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_manual_citizens', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_manual_citizens` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenId` VARCHAR(64) NOT NULL,
                `firstname` VARCHAR(64) NOT NULL,
                `lastname` VARCHAR(64) NOT NULL,
                `dob` VARCHAR(32) NULL,
                `phone` VARCHAR(64) NULL,
                `nationality` VARCHAR(64) NULL,
                `gender` VARCHAR(32) NULL,
                `job` VARCHAR(128) NULL,
                `address` VARCHAR(255) NULL,
                `profilePicture` VARCHAR(512) NULL,
                `createdByCitizenId` VARCHAR(64) NULL,
                `createdByName` VARCHAR(128) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_manual_citizen_id` (`citizenId`),
                KEY `idx_manual_citizen_name` (`lastname`, `firstname`),
                KEY `idx_manual_citizen_phone` (`phone`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_manual_vehicles', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_manual_vehicles` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(16) NOT NULL,
                `ownerCitizenId` VARCHAR(64) NULL,
                `ownerName` VARCHAR(128) NULL,
                `model` VARCHAR(128) NULL,
                `modelLabel` VARCHAR(128) NULL,
                `brand` VARCHAR(64) NULL,
                `primaryColorId` INT NULL,
                `secondaryColorId` INT NULL,
                `vehiclePhoto` VARCHAR(512) NULL,
                `createdByCitizenId` VARCHAR(64) NULL,
                `createdByName` VARCHAR(128) NULL,
                `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_manual_vehicle_plate` (`plate`),
                KEY `idx_manual_vehicle_owner_cid` (`ownerCitizenId`),
                KEY `idx_manual_vehicle_owner_name` (`ownerName`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_cctv_cameras', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_cctv_cameras` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `camera_key` VARCHAR(128) NOT NULL UNIQUE,
                `model_hash` BIGINT NULL,
                `model_name` VARCHAR(64) NULL,
                `x` FLOAT NOT NULL,
                `y` FLOAT NOT NULL,
                `z` FLOAT NOT NULL,
                `heading` FLOAT NOT NULL,
                `location_label` VARCHAR(128) NULL,
                `status` ENUM('ONLINE','OFFLINE') DEFAULT 'ONLINE',
                `last_seen_at` DATETIME NULL,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_camera_key` (`camera_key`),
                KEY `idx_status` (`status`),
                KEY `idx_location` (`location_label`),
                KEY `idx_created_at` (`created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_chat', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_chat` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `officer_name` VARCHAR(128) NOT NULL,
                `message` TEXT NOT NULL,
                `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_created_at` (`created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_templates', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_templates` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `title` VARCHAR(120) NOT NULL,
                `body_html` LONGTEXT NOT NULL,
                `visibility` VARCHAR(16) NOT NULL DEFAULT 'private',
                `allowed_grades` TEXT NULL,
                `allowed_officers` TEXT NULL,
                `author_cid` VARCHAR(50) NOT NULL,
                `author_name` VARCHAR(120) NOT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
    { name = 'pf_mdt_esx_license_suspensions', sql = [[CREATE TABLE IF NOT EXISTS `pf_mdt_esx_license_suspensions` (
                `identifier` VARCHAR(64) NOT NULL,
                `license_type` VARCHAR(32) NOT NULL,
                `expires_at` DATETIME NULL,
                `stored_types` LONGTEXT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`identifier`, `license_type`),
                KEY `idx_pf_mdt_esx_license_suspensions_expires` (`expires_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]] },
}

-- Columns added to existing tables after their first release: { table, column, definition, sql
-- to run once right after adding it }. Each has a default or allows NULL, so existing rows stay
-- valid. pf_mdt_charges' money columns are left alone on purpose: an old install may still use
-- fine_amount/bail_amount/jail_time, and main.lua/sentencing.lua pick whichever set exists.
Schema.Columns = {
    { 'pf_mdt_charges', 'description', '`description` LONGTEXT NULL' },
    { 'pf_mdt_reports', 'officer', "`officer` VARCHAR(128) NOT NULL DEFAULT ''" },
    { 'pf_mdt_reports', 'status', "`status` VARCHAR(16) NOT NULL DEFAULT 'pending'",
        -- the new column starts out as the report's approval state, not 'pending' for every old report
        'UPDATE `pf_mdt_reports` SET `status` = `approvalStatus` WHERE `approvalStatus` IS NOT NULL' },
    { 'pf_mdt_reports', 'vehiclePlate', '`vehiclePlate` VARCHAR(16) NULL' },
    { 'pf_mdt_warrants', 'officers', '`officers` LONGTEXT NULL' },
    { 'pf_mdt_warrants', 'witnesses', '`witnesses` LONGTEXT NULL' },
    { 'pf_mdt_warrants', 'title', '`title` VARCHAR(255) NULL' },
    { 'pf_mdt_incidents', 'reportingOfficer', '`reportingOfficer` VARCHAR(128) NULL' },
    { 'pf_mdt_incidents', 'involvedCitizens', '`involvedCitizens` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'involvedOfficers', '`involvedOfficers` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'involvedVictims', '`involvedVictims` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'involvedVehicles', '`involvedVehicles` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'evidence_ids', '`evidence_ids` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'involvedCitizenIds', '`involvedCitizenIds` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'involvedOfficerIds', '`involvedOfficerIds` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'involvedVictimIds', '`involvedVictimIds` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'involvedVehicleIds', '`involvedVehicleIds` LONGTEXT NULL' },
    { 'pf_mdt_incidents', 'dateTime', '`dateTime` DATETIME NULL' },
    { 'pf_mdt_vehicle_strikes', 'points', '`points` INT NOT NULL DEFAULT 4' },
    { 'pf_mdt_vehicle_strikes', 'description', '`description` TEXT NULL' },
    { 'pf_mdt_vehicle_strikes', 'location', '`location` VARCHAR(255) NULL' },
    { 'pf_mdt_vehicle_strikes', 'status', "`status` ENUM('active', 'expired', 'dismissed') NOT NULL DEFAULT 'active'" },
    { 'pf_mdt_vehicle_strikes', 'expiresAt', '`expiresAt` DATETIME NULL' },
    { 'pf_mdt_vehicle_strikes', 'createdByName', '`createdByName` VARCHAR(128) NULL' },
    -- the ALTER loop server/officers.lua ran on every start
    { 'pf_mdt_officer_mgmt_profiles', 'status', "`status` VARCHAR(32) NOT NULL DEFAULT 'ACTIVE'" },
    { 'pf_mdt_officer_mgmt_profiles', 'terminated', '`terminated` TINYINT(1) NOT NULL DEFAULT 0' },
    { 'pf_mdt_officer_mgmt_profiles', 'terminated_at', '`terminated_at` DATETIME NULL' },
    { 'pf_mdt_officer_mgmt_profiles', 'terminated_by', '`terminated_by` VARCHAR(128) NULL' },
    { 'pf_mdt_officer_mgmt_profiles', 'terminated_reason', '`terminated_reason` VARCHAR(255) NULL' },
    { 'pf_mdt_officer_mgmt_profiles', 'is_supervisor', '`is_supervisor` TINYINT(1) NOT NULL DEFAULT 0' },
    { 'pf_mdt_weapons_registry', 'stolen_status', '`stolen_status` TINYINT(1) NOT NULL DEFAULT 0' },
}

-- Plain (non-unique) indexes added after a table's first release: { table, name, columns }.
-- A unique key is never added to an existing table (old duplicates would make it fail).
Schema.Indexes = {
    { 'pf_mdt_officer_mgmt_profiles', 'idx_officer_terminated', '(`terminated`)' },
    { 'pf_mdt_officer_mgmt_profiles', 'idx_status', '(`status`)' },
    { 'pf_mdt_officer_mgmt_profiles', 'idx_terminated_status', '(`terminated`, `status`)' },
    { 'pf_mdt_roster', 'idx_citizenid', '(`citizenid`)' },
}

-- Default rows of the SQL files, as a hand import leaves them: the penal code (the file's short
-- descriptions; its detailed backfill only rewrites blank ones or ones equal to the name, which
-- the seed has none of), the example report template and the seeded CCTV cameras. Each runs only
-- for a table v7 created itself, as INSERT IGNORE on the unique keys.
Schema.Seeds = {
    { table = 'pf_mdt_charges', sql = [==[INSERT IGNORE INTO `pf_mdt_charges` (`code`, `name`, `description`, `fineAmount`, `bailAmount`, `prisonTime`, `category`) VALUES
    ('PC-187', 'Murder', 'Unlawful killing of a human being', 50000, 100000, 240, 'Violent'),
    ('PC-191', 'Manslaughter', 'Unlawful killing without malice aforethought', 20000, 50000, 120, 'Violent'),
    ('PC-245', 'Assault with Deadly Weapon', 'Assault with deadly weapon or force', 10000, 25000, 60, 'Violent'),
    ('PC-242', 'Assault', 'Intentional application of force against another', 2000, 5000, 6, 'Violent'),
    ('PC-243', 'Battery', 'Willful and unlawful touching of another', 2000, 5000, 6, 'Violent'),
    ('PC-261', 'Rape', 'Non-consensual sexual intercourse', 60000, 120000, 300, 'Violent'),
    ('PC-262', 'Rape of Spouse', 'Non-consensual sexual intercourse with spouse', 40000, 80000, 240, 'Violent'),
    ('PC-264', 'Indecent Exposure', 'Exposure of genitals with intent to offend', 1000, 2500, 12, 'Violent'),
    ('PC-207', 'Kidnapping', 'Unlawful restraint or taking of person', 40000, 80000, 180, 'Violent'),
    ('PC-208', 'Child Abduction', 'Taking of minor without consent', 35000, 75000, 150, 'Violent'),
    ('PC-219', 'Torture', 'Infliction of extreme pain with intent to cause injury', 50000, 100000, 240, 'Violent'),
    ('PC-273', 'Child Abuse', 'Willful cruelty or endangerment of child', 15000, 35000, 90, 'Violent'),
    ('PC-273.5', 'Domestic Violence', 'Willful infliction of corporal injury on intimate partner', 10000, 25000, 48, 'Violent'),
    ('PC-415', 'Disturbing the Peace', 'Fighting, loud/unreasonable noise, abusive language', 250, 500, 0, 'Violent'),
    ('PC-417', 'Drawing or Exhibiting a Firearm', 'Drawing or exhibiting firearm in rude or threatening manner', 5000, 12000, 30, 'Violent'),
    ('PC-459', 'Burglary', 'Unlawful entry with intent to commit felony', 15000, 35000, 120, 'Property'),
    ('PC-459.5', 'Vehicle Burglary', 'Unlawful entry into vehicle with intent to steal', 8000, 20000, 60, 'Property'),
    ('PC-484', 'Theft', 'Unlawful taking of personal property', 8000, 15000, 60, 'Property'),
    ('PC-487', 'Grand Theft', 'Theft of property worth $950 or more', 12000, 30000, 90, 'Property'),
    ('PC-488', 'Petty Theft', 'Theft of property worth less than $950', 2000, 5000, 12, 'Property'),
    ('PC-496', 'Receiving Stolen Property', 'Knowingly receiving stolen goods', 7000, 14000, 45, 'Property'),
    ('PC-503', 'Embezzlement', 'Fraudulent appropriation of another property', 10000, 25000, 60, 'Property'),
    ('PC-530.5', 'Identity Theft', 'Unauthorized use of identity', 5000, 12000, 30, 'Property'),
    ('PC-537', 'Fraudulent Sale of Real Property', 'Fraudulent transfer of real estate', 20000, 50000, 120, 'Property'),
    ('PC-666', 'Shoplifting', 'Theft from retail establishment', 2000, 4000, 15, 'Property'),
    ('PC-484F', 'Theft by Bad Check', 'Writing check knowing insufficient funds', 3000, 8000, 20, 'Property'),
    ('PC-518', 'Extortion', 'Obtaining property by threat or coercion', 15000, 35000, 90, 'Property'),
    ('PC-550', 'Insurance Fraud', 'Fraudulent insurance claim', 10000, 25000, 60, 'Property'),
    ('VC-10001', 'Speeding', 'Exceeding posted speed limit', 500, 1000, 0, 'Traffic'),
    ('VC-10002', 'Reckless Driving', 'Operating vehicle with wanton disregard', 2000, 5000, 15, 'Traffic'),
    ('VC-10003', 'Driving Under the Influence', 'Operating vehicle while intoxicated', 5000, 15000, 30, 'Traffic'),
    ('VC-10004', 'Driving with Suspended License', 'Operating vehicle without valid license', 3000, 8000, 20, 'Traffic'),
    ('VC-10005', 'Failure to Stop at Red Light', 'Running red light or stop sign', 350, 500, 0, 'Traffic'),
    ('VC-10006', 'Failure to Obey Traffic Control Device', 'Ignoring traffic signals or signs', 300, 500, 0, 'Traffic'),
    ('VC-10007', 'Illegal Parking', 'Parking in restricted area', 100, 200, 0, 'Traffic'),
    ('VC-480', 'Hit and Run - Property Damage', 'Leaving scene of accident with property damage', 5000, 12000, 30, 'Traffic'),
    ('VC-20001', 'Hit and Run - Injury', 'Leaving scene of accident with injury', 10000, 25000, 60, 'Traffic'),
    ('VC-14601', 'Driving Without a License', 'Operating vehicle without valid license', 2000, 5000, 15, 'Traffic'),
    ('VC-23152', 'DUI - First Offense', 'Driving under influence of alcohol/drugs', 5000, 15000, 30, 'Traffic'),
    ('VC-23153', 'DUI - Injury', 'DUI causing injury to another person', 15000, 35000, 90, 'Traffic'),
    ('HS-11350', 'Possession of Controlled Substance', 'Possession of illegal drugs', 3000, 8000, 30, 'Narcotics'),
    ('HS-11352', 'Transportation of Controlled Substance', 'Transport of illegal drugs', 20000, 50000, 120, 'Narcotics'),
    ('HS-11351', 'Possession for Sale', 'Possession of controlled substance with intent to sell', 15000, 35000, 90, 'Narcotics'),
    ('HS-11359', 'Possession of Marijuana for Sale', 'Possession of marijuana with intent to sell', 10000, 25000, 60, 'Narcotics'),
    ('HS-11360', 'Transportation of Marijuana', 'Transport of marijuana for sale', 12000, 30000, 75, 'Narcotics'),
    ('HS-11370', 'Sale of Controlled Substance Near School', 'Drug sales within 600 feet of school', 25000, 60000, 150, 'Narcotics'),
    ('HS-11377', 'Possession of Methamphetamine', 'Possession of crystal meth', 5000, 12000, 36, 'Narcotics'),
    ('PC-25400', 'Carrying Concealed Weapon', 'Carrying hidden firearm without permit', 3000, 7500, 20, 'Weapons'),
    ('PC-25850', 'Carrying Loaded Firearm', 'Carrying loaded firearm in public', 5000, 12000, 30, 'Weapons'),
    ('PC-26350', 'Carrying Unloaded Firearm', 'Carrying unloaded firearm in public', 2000, 5000, 15, 'Weapons'),
    ('PC-21510', 'Brandishing a Weapon', 'Brandishing knife or other dangerous weapon', 4000, 10000, 25, 'Weapons'),
    ('PC-182', 'Criminal Conspiracy', 'Conspiracy to commit crime', 15000, 35000, 90, 'General'),
    ('PC-211', 'Robbery', 'Taking property by force or threat', 20000, 50000, 150, 'Violent'),
    ('PC-212.5', 'Aggravated Assault', 'Assault on peace officer or elder', 15000, 35000, 90, 'Violent'),
    ('PC-664', 'Attempted Felony', 'Attempted commission of felony', 10000, 25000, 60, 'General'),
    ('PC-270', 'Jail Break', 'Escape from custody', 25000, 60000, 180, 'Police'),
    ('PC-148', 'Resisting Arrest', 'Resisting or obstructing police officer', 5000, 10000, 30, 'Police'),
    ('PC-149', 'Assault on Officer', 'Assault on peace officer performing duties', 8000, 20000, 45, 'Police'),
    ('PC-187.5', 'Killing a Police Officer', 'Murder of peace officer in performance of duty', 100000, 200000, 360, 'Violent'),
    ('PC-266', 'Pimping and Pandering', 'Profiting from prostitution', 8000, 20000, 45, 'General'),
    ('PC-314', 'Indecent Exposure', 'Exposing genitals in reckless manner', 1000, 2500, 12, 'General'),
    ('PC-381', 'Threatening Public Safety', 'Threats to public safety or infrastructure', 5000, 12000, 30, 'General'),
    ('PC-384', 'Loitering for Drug Purposes', 'Loitering with intent to sell drugs', 3000, 8000, 20, 'Narcotics'),
    ('PC-484H', 'Theft of Vehicle', 'Stealing a motor vehicle', 10000, 25000, 60, 'Property')]==] },
    { table = 'pf_mdt_templates', sql = [==[INSERT IGNORE INTO `pf_mdt_templates` (`title`, `body_html`, `visibility`, `allowed_grades`, `allowed_officers`, `author_cid`, `author_name`) VALUES
    ('Traffic Stop Report', '<h2>Traffic Stop Details</h2><p><strong>Date &amp; Time:</strong> ___________</p><p><strong>Location:</strong> ___________</p><p><strong>Vehicle:</strong> ___________</p><p><strong>Plate:</strong> ___________</p><p><strong>Driver:</strong> ___________</p><br><h3>Reason for Stop</h3><p>___________</p><br><h3>Actions Taken</h3><ul><li>Warning issued</li><li>Citation issued</li><li>Arrest made</li></ul><br><h3>Additional Notes</h3><p>___________</p>', 'public', '[]', '[]', 'SYSTEM', 'System Generated')]==] },
    { table = 'pf_mdt_cctv_cameras', sql = [==[INSERT IGNORE INTO `pf_mdt_cctv_cameras` (`camera_key`, `model_hash`, `model_name`, `x`, `y`, `z`, `heading`, `location_label`, `status`) VALUES
    ('seed_0001', -1159421424, NULL, 218.407, -1459.7, 36.3576, 167.285, 'Innocence Blvd, Davis', 'ONLINE'),
    ('seed_0002', 548760764, NULL, 192.195, -1475.55, 33.554, 225, 'Innocence Blvd, Davis', 'ONLINE'),
    ('seed_0003', -1159421424, NULL, 185.516, -1481.72, 35.644, 250.705, 'Davis Ave, Davis', 'ONLINE'),
    ('seed_0004', 548760764, NULL, 175.997, -1523.13, 34.9092, 311, 'Davis Ave, Davis', 'ONLINE'),
    ('seed_0005', 548760764, NULL, 252.275, -1487.92, 34.959, 141.5, 'Innocence Blvd, Davis', 'ONLINE'),
    ('seed_0006', -1340405475, NULL, 146.522, -1038.2, 31.0197, 159.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0007', 168901740, NULL, 153.179, -1042.19, 31.0526, 239.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0008', 168901740, NULL, 151.103, -1047.01, 31.4522, 239.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0009', -1340405475, NULL, 150.015, -1051.31, 31.4355, 159.846, 'Elgin Ave, Pillbox Hill', 'ONLINE'),
    ('seed_0010', 168901740, NULL, 142.675, -1041.54, 31.558, 44.8462, 'Vespucci Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0011', 168901740, NULL, 151.904, -1043.64, 31.7034, 229.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0012', 168901740, NULL, 143.094, -1040.4, 31.5581, 139.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0013', 168901740, NULL, 144.953, -1042.98, 31.3438, 44.8462, 'Vespucci Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0014', -1340405475, NULL, 529.828, 724.27, 200.566, 301.495, 'Marlowe Dr, Vinewood Hills', 'ONLINE'),
    ('seed_0015', -1340405475, NULL, 520.933, 744.572, 205.029, 301.495, 'Marlowe Dr, Vinewood Hills', 'ONLINE'),
    ('seed_0016', 168901740, NULL, 180.052, 1242.7, 228.144, 328, 'Baytree Canyon Rd, Vinewood Hills', 'ONLINE'),
    ('seed_0017', 548760764, NULL, 538.301, 2671.71, 44.7499, 276.846, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0018', 548760764, NULL, 552.517, 2741.17, 47.096, 4.0865, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0019', 548760764, NULL, 572.757, 2742.4, 45.898, 4.0865, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0020', 168901740, NULL, 550.276, 2666.5, 44.687, 232.5, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0021', 168901740, NULL, 539.009, 2671.48, 44.687, 52.4999, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0022', 168901740, NULL, 543.014, 2664.61, 44.687, 52.4999, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0023', 548760764, NULL, 549.503, 2673.54, 44.1283, 186.846, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0024', -1159421424, NULL, 531.241, 2675.78, 42.8807, 0, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0025', -1159421424, NULL, 540.896, 2671.78, 49.9135, 0, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0026', -1159421424, NULL, 540.279, 2670.61, 51.126, 0, 'Route 68, Harmony', 'ONLINE'),
    ('seed_0027', 548760764, NULL, -1116.75, 2687.28, 20.6915, 41.8771, 'Route 68, Zancudo River', 'ONLINE'),
    ('seed_0028', 548760764, NULL, -40.4313, 6407.14, 36.8945, 225, 'Great Ocean Hwy, Paleto Bay', 'ONLINE'),
    ('seed_0029', 548760764, NULL, -53.0901, 6359.1, 37.4509, 44.9999, 'Great Ocean Hwy, Paleto Bay', 'ONLINE'),
    ('seed_0030', 548760764, NULL, 172.452, 6401.38, 36.1377, 208.761, 'Great Ocean Hwy, Mount Chiliad', 'ONLINE'),
    ('seed_0031', 548760764, NULL, -447.85, 6022.81, 34.3594, 135, 'Paleto Blvd, Paleto Bay', 'ONLINE'),
    ('seed_0032', 548760764, NULL, -435.4, 6010.35, 34.3594, 135, 'Paleto Blvd, Paleto Bay', 'ONLINE'),
    ('seed_0033', 548760764, NULL, -431.793, 5989.64, 34.3594, 45, 'Paleto Blvd, Paleto Forest', 'ONLINE'),
    ('seed_0034', -1340405475, NULL, -113.146, 6464.39, 33.2862, 315, 'Paleto Blvd, Paleto Bay', 'ONLINE'),
    ('seed_0035', 168901740, NULL, -108.022, 6462.62, 33.7407, 190, 'Paleto Blvd, Paleto Bay', 'ONLINE'),
    ('seed_0036', -1340405475, NULL, -107.892, 6468.55, 34.2675, 315, 'Paleto Blvd, Paleto Bay', 'ONLINE'),
    ('seed_0037', 548760764, NULL, -168.281, 6441.59, 34.1285, 315, 'Cascabel Ave, Paleto Bay', 'ONLINE'),
    ('seed_0038', 168901740, NULL, -107.422, 6475.98, 33.7407, 35.0001, 'Paleto Blvd, Paleto Bay', 'ONLINE'),
    ('seed_0039', -1340405475, NULL, -104.629, 6479.42, 33.724, 315, 'Paleto Blvd, Paleto Bay', 'ONLINE'),
    ('seed_0040', 168901740, NULL, 1963.1, 3748.55, 34.8742, 255, 'Alhambra Dr, Sandy Shores', 'ONLINE'),
    ('seed_0041', 168901740, NULL, 1969.44, 3743.73, 34.8742, 255, 'Alhambra Dr, Sandy Shores', 'ONLINE'),
    ('seed_0042', 168901740, NULL, 1957.12, 3744.02, 34.8742, 74.9999, 'Niland Ave, Sandy Shores', 'ONLINE'),
    ('seed_0043', 548760764, NULL, 1791.72, 2547.78, 51.0436, 89.9917, 'Route 68, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0044', 168901740, NULL, 1845.03, 2594.78, 47.9529, 326.113, 'Route 68, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0045', 168901740, NULL, 1837.16, 2594.46, 47.952, 56.1132, 'Route 68, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0046', 168901740, NULL, 1845.27, 2584.03, 47.953, 216.113, 'Route 68, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0047', -173206916, NULL, 1834.16, 2604.49, 47.4014, 104.041, 'Route 68, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0048', 168901740, NULL, 1824.2, 2472.81, 64.7177, 145, 'Senora Fwy, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0049', 168901740, NULL, 1824.29, 2478.26, 64.7177, 355, 'Senora Fwy, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0050', -173206916, NULL, 1786.95, 2489.94, 47.6627, 15.1131, 'Senora Fwy, Bolingbroke Penitentiary', 'ONLINE'),
    ('seed_0051', 168901740, NULL, 317.51, -280.554, 55.8493, 239.866, 'Meteor St, Alta', 'ONLINE'),
    ('seed_0052', 548760764, NULL, -965.475, -181.509, 40.2058, 297.014, 'Boulevard Del Perro, Rockford Hills', 'ONLINE'),
    ('seed_0053', -1340405475, NULL, -943.948, -338.01, 40.7521, 0, 'Marathon Ave, Rockford Hills', 'ONLINE'),
    ('seed_0054', 548760764, NULL, 342.154, -1620.75, 35.2191, 139.928, 'Innocence Blvd, Rancho', 'ONLINE'),
    ('seed_0055', -1340405475, NULL, -1473.56, -593.2, 39.8044, 0, 'Marathon Ave, Del Perro', 'ONLINE'),
    ('seed_0056', -1340405475, NULL, -1441.34, -543.761, 38.5156, 305, 'Prosperity St, Del Perro', 'ONLINE'),
    ('seed_0057', 1449155105, NULL, -1509.53, -512.623, 39.3235, 215, 'Boulevard Del Perro, Del Perro', 'ONLINE'),
    ('seed_0058', -1340405475, NULL, -1495.84, -608.812, 39.8044, 0, 'Marathon Ave, Del Perro', 'ONLINE'),
    ('seed_0059', 1449155105, NULL, -1493.89, -530.623, 37.107, 305, 'Marathon Ave, Del Perro', 'ONLINE'),
    ('seed_0060', 548760764, NULL, -917.643, -448.178, 41.1305, 343.181, 'Movie Star Way, Rockford Hills', 'ONLINE'),
    ('seed_0061', -1159421424, NULL, 2.77843, 216.167, 113.274, 65.0001, 'Las Lagunas Blvd, West Vinewood', 'ONLINE'),
    ('seed_0062', 168901740, NULL, -1072.51, -1678.67, 6.25555, 175.861, 'Bay City Ave, La Puerta', 'ONLINE'),
    ('seed_0063', 548760764, NULL, -1114.15, -837.548, 22.8457, 308.389, 'San Andreas Ave, Vespucci Canals', 'ONLINE'),
    ('seed_0064', 548760764, NULL, -1090.17, -808.307, 21.6384, 218.389, 'San Andreas Ave, Vespucci Canals', 'ONLINE'),
    ('seed_0065', 1449155105, NULL, -1143.28, -843.612, 19.5049, 307.906, 'San Andreas Ave, Vespucci Canals', 'ONLINE'),
    ('seed_0066', 548760764, NULL, -1130.62, -857.659, 17.4837, 311.337, 'Prosperity St, Vespucci Canals', 'ONLINE'),
    ('seed_0067', 548760764, NULL, -1095.49, -854.243, 10.3694, 342.779, 'Vespucci Blvd, Vespucci Canals', 'ONLINE'),
    ('seed_0068', 168901740, NULL, 513.191, -891.64, 18.5065, 160.021, 'Little Bighorn Ave, La Mesa', 'ONLINE'),
    ('seed_0069', 168901740, NULL, 515.728, -805.105, 18.1026, 10.7175, 'Little Bighorn Ave, La Mesa', 'ONLINE'),
    ('seed_0070', 548760764, NULL, 831.816, -1893.93, 33.1025, 265, 'Popular St, Cypress Flats', 'ONLINE'),
    ('seed_0071', 548760764, NULL, 856.816, -1822.01, 33.7035, 270, 'Popular St, Cypress Flats', 'ONLINE'),
    ('seed_0072', 548760764, NULL, 829.364, -1921.97, 32.2095, 265, 'Popular St, Cypress Flats', 'ONLINE'),
    ('seed_0073', 548760764, NULL, 829.766, -1922.48, 32.2095, 355, 'Popular St, Cypress Flats', 'ONLINE'),
    ('seed_0074', 168901740, NULL, 138.264, -1702.92, 31.389, 0.00000512264, 'Carson Ave, Davis', 'ONLINE'),
    ('seed_0075', -1159421424, NULL, -167.111, -1459.94, 37.652, 91, 'Carson Ave, Chamberlain Hills', 'ONLINE'),
    ('seed_0076', -1159421424, NULL, -175.889, -1452.64, 38.4027, 144.5, 'Carson Ave, Chamberlain Hills', 'ONLINE'),
    ('seed_0077', 168901740, NULL, 16.0022, -1107.07, 32.2741, 205, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0078', 168901740, NULL, 6.77947, -1097.7, 32.7716, 115, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0079', 168901740, NULL, 18.3869, -1101.92, 32.7716, 205, 'Elgin Ave, Pillbox Hill', 'ONLINE'),
    ('seed_0080', 168901740, NULL, 3.03235, -1108.98, 32.2741, 115, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0081', 548760764, NULL, -27.9912, -1118.19, 29.5588, 70.0001, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0082', 168901740, NULL, 19.2829, -1103.16, 32.2741, 25, 'Elgin Ave, Pillbox Hill', 'ONLINE'),
    ('seed_0083', 548760764, NULL, -0.909945, -1081.58, 29.564, 250, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0084', 548760764, NULL, -7.3872, -1099.39, 29.564, 250, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0085', 548760764, NULL, -23.3573, -1086.05, 28.9277, 160, 'Power St, Pillbox Hill', 'ONLINE'),
    ('seed_0086', 168901740, NULL, 15.5155, -1113.7, 32.2741, 115, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0087', 168901740, NULL, 6.516, -1098.57, 32.2741, 25, 'Adam''s Apple Blvd, Pillbox Hill', 'ONLINE'),
    ('seed_0088', -1340405475, NULL, 139.561, -764.216, 47.3775, 250, 'San Andreas Ave, Pillbox Hill', 'ONLINE'),
    ('seed_0089', -1340405475, NULL, 136.742, -763.19, 47.3775, 250, 'San Andreas Ave, Pillbox Hill', 'ONLINE'),
    ('seed_0090', 548760764, NULL, -128.118, -207.777, 48.5751, 336, 'Carcer Way, Burton', 'ONLINE'),
    ('seed_0091', 548760764, NULL, -151.685, -285.596, 43.7289, 341, 'Las Lagunas Blvd, Burton', 'ONLINE'),
    ('seed_0092', 548760764, NULL, -238.601, -216.596, 38.7973, 270, 'San Vitus Blvd, Burton', 'ONLINE'),
    ('seed_0093', 548760764, NULL, -483.822, -63.7358, 43.507, 177, 'Abe Milton Pkwy, Burton', 'ONLINE'),
    ('seed_0094', 548760764, NULL, -486.796, -63.2061, 43.6193, 236, 'Abe Milton Pkwy, Burton', 'ONLINE'),
    ('seed_0095', 548760764, NULL, -607.202, -153.524, 44.627, 293, 'Eastbourne Way, Rockford Hills', 'ONLINE'),
    ('seed_0096', 548760764, NULL, -638.142, -125.561, 42.8434, 119.6, 'Rockford Dr, Rockford Hills', 'ONLINE'),
    ('seed_0097', 1449155105, NULL, -765.399, -216.798, 42.9494, 300, 'Eastbourne Way, Rockford Hills', 'ONLINE'),
    ('seed_0098', -1340405475, NULL, -838.713, -235.077, 40.3279, 270, 'Mad Wayne Thunder Dr, Rockford Hills', 'ONLINE'),
    ('seed_0099', -1340405475, NULL, -857.016, -231.007, 63.1081, 270, 'Mad Wayne Thunder Dr, Rockford Hills', 'ONLINE'),
    ('seed_0100', -1340405475, NULL, -869.872, -218.455, 43.3319, 90, 'Mad Wayne Thunder Dr, Rockford Hills', 'ONLINE'),
    ('seed_0101', 548760764, NULL, -956.591, -179.555, 39.7788, 28, 'Boulevard Del Perro, Rockford Hills', 'ONLINE'),
    ('seed_0102', 548760764, NULL, -896.13, -154.699, 39.8647, 117.014, 'South Boulevard Del Perro, Rockford Hills', 'ONLINE'),
    ('seed_0103', 548760764, NULL, -1097.58, -252.338, 40.9512, 297.778, 'South Boulevard Del Perro, Rockford Hills', 'ONLINE'),
    ('seed_0104', -173206916, NULL, -1145.31, -202.232, 42.8787, 281.356, 'Boulevard Del Perro, Rockford Hills', 'ONLINE'),
    ('seed_0105', -173206916, NULL, -1144.25, -201.769, 42.8787, 117.908, 'Boulevard Del Perro, Rockford Hills', 'ONLINE'),
    ('seed_0106', -173206916, NULL, -1192.22, -259.355, 40.5788, 281.356, 'Boulevard Del Perro, Rockford Hills', 'ONLINE'),
    ('seed_0107', 548760764, NULL, -1412.33, -387.4, 40.7334, 32.9611, 'Boulevard Del Perro, Morningwood', 'ONLINE'),
    ('seed_0108', 548760764, NULL, -1437.48, -381.678, 40.9081, 302.961, 'Boulevard Del Perro, Morningwood', 'ONLINE'),
    ('seed_0109', 548760764, NULL, -1432.9, -398.987, 41.3606, 122.105, 'Boulevard Del Perro, Morningwood', 'ONLINE'),
    ('seed_0110', 548760764, NULL, -1444.17, -382.058, 41.5677, 212.105, 'Boulevard Del Perro, Morningwood', 'ONLINE'),
    ('seed_0111', 548760764, NULL, -1460.53, -392.411, 40.7035, 212.105, 'Prosperity St, Morningwood', 'ONLINE'),
    ('seed_0112', 548760764, NULL, -1468.91, -348.312, 47.7176, 312.09, 'North Rockford Dr, Morningwood', 'ONLINE'),
    ('seed_0113', 168901740, NULL, -1482.96, -380.392, 42.7402, 250.926, 'Prosperity St, Morningwood', 'ONLINE'),
    ('seed_0114', 548760764, NULL, -1531.44, -341.124, 47.9424, 315.675, 'Prosperity St, Morningwood', 'ONLINE'),
    ('seed_0115', 548760764, NULL, -1489.51, -323.761, 49.9616, 312.09, 'North Rockford Dr, Morningwood', 'ONLINE'),
    ('seed_0116', 548760764, NULL, -1588.56, -396.326, 46.1337, 225, 'Cougar Ave, Pacific Bluffs', 'ONLINE'),
    ('seed_0117', 548760764, NULL, -1662.28, -396.302, 47.9069, 142.105, 'Bay City Ave, Pacific Bluffs', 'ONLINE'),
    ('seed_0118', 168901740, NULL, -2104.3, -308.597, 16.6005, 34, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE'),
    ('seed_0119', 168901740, NULL, -2097.69, -328.5, 16.6005, 149, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE'),
    ('seed_0120', 548760764, NULL, -2024.8, -259.736, 27.0446, 235, 'West Eclipse Blvd, Pacific Bluffs', 'ONLINE'),
    ('seed_0121', 548760764, NULL, -1938.69, -533.228, 13.4978, 140.312, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE'),
    ('seed_0122', 548760764, NULL, -1932.4, -538.16, 14.7938, 140, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE'),
    ('seed_0123', 548760764, NULL, -1919.43, -542.359, 14.7938, 140, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE'),
    ('seed_0124', -1340405475, NULL, -1594.52, -567.268, 42.9233, 0, 'Bay City Ave, Del Perro', 'ONLINE')]==] },
}

-- ── v7 helpers ──────────────────────────────────────────────────────────────

local function q(sql, params) return MySQL.query.await(sql, params or {}) end

local function tableNames()
    local names = {}
    for _, t in ipairs(Schema.Tables) do names[#names + 1] = t.name end
    for _, c in ipairs(Schema.Columns) do names[#names + 1] = c[1] end
    return names
end

-- one read of information_schema for every column of our tables: [table][column] = true
local function existingColumns()
    local names = tableNames()
    local marks = string.rep('?,', #names):sub(1, -2)
    local rows = q(('SELECT TABLE_NAME AS t, COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (%s)'):format(marks), names) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local t = r.t or r.TABLE_NAME
        out[t] = out[t] or {}
        out[t][r.c or r.COLUMN_NAME] = true
    end
    return out
end

local function existingIndexes()
    local names = tableNames()
    local marks = string.rep('?,', #names):sub(1, -2)
    local rows = q(('SELECT DISTINCT TABLE_NAME AS t, INDEX_NAME AS i FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (%s)'):format(marks), names) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local t = r.t or r.TABLE_NAME
        out[t] = out[t] or {}
        out[t][r.i or r.INDEX_NAME] = true
    end
    return out
end

-- the tables of this resource that exist right now: [name] = true
local function existingTables()
    local names = tableNames()
    local marks = string.rep('?,', #names):sub(1, -2)
    local rows = q(('SELECT TABLE_NAME AS t FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (%s)'):format(marks), names) or {}
    local out = {}
    for _, r in ipairs(rows) do out[r.t or r.TABLE_NAME] = true end
    return out
end

--- v7: the tables of the SQL files and the ad-hoc ones. Every step checks before it writes, so an
--- interrupted run (DDL commits on its own) simply starts again from the top.
function Schema.ApplyV7()
    -- read before creating anything: only a table this step creates gets the default rows
    local hadTable = existingTables()
    for _, t in ipairs(Schema.Tables) do q(t.sql) end

    local cols = existingColumns()

    -- server/sop.lua renamed this column on the fly; `procedure` is a reserved word in MySQL 8
    local sops = cols.pf_mdt_sops or {}
    if sops['procedure'] and not sops.procedure_text then
        q('ALTER TABLE `pf_mdt_sops` CHANGE `procedure` `procedure_text` TEXT NOT NULL')
        sops.procedure_text, sops['procedure'] = true, nil
    end

    -- columns later versions of the SQL file (and server/officers.lua) added to existing tables;
    -- plain ADD COLUMN behind the check, so it also works where ADD COLUMN IF NOT EXISTS does not
    for _, c in ipairs(Schema.Columns) do
        local t, name, def = c[1], c[2], c[3]
        if cols[t] and not cols[t][name] then
            q(('ALTER TABLE `%s` ADD COLUMN %s'):format(t, def))
            cols[t][name] = true
            if c[4] then q(c[4]) end
        end
    end

    local idx = existingIndexes()
    for _, i in ipairs(Schema.Indexes) do
        local t, name, columns = i[1], i[2], i[3]
        if idx[t] and not idx[t][name] then
            q(('ALTER TABLE `%s` ADD INDEX `%s` %s'):format(t, name, columns))
            idx[t][name] = true
        end
    end

    -- default rows go only into a table created just now. A table that was already there (a hand
    -- import, then staff edits, even an emptied one) keeps exactly what its staff left in it, and
    -- an old charges table with snake_case money columns is never written with the new names.
    -- If this step is cut off between creating a table and seeding it, the rerun finds the table
    -- and leaves it empty; the staff can add the rows through the MDT.
    for _, s in ipairs(Schema.Seeds) do
        if not hadTable[s.table] then q(s.sql) end
    end
end

Schema.Migrations[#Schema.Migrations + 1] = {
    -- one function step: the column and index checks must read the database before they write
    version = 7,
    name = 'MDT tables from the SQL files',
    up = function() Schema.ApplyV7() end,
}

-- ── running ─────────────────────────────────────────────────────────────────

local function announceReady()
    -- server-only event (never registered as a net event) for modules that load their caches
    TriggerEvent('pf_mdt:server:schemaReady')
end

function Schema.Ready() return Schema.state == 'ready' end

--- Applies the pending versions once. A caller that arrives while it runs waits for that run
--- instead of starting its own (the runner would refuse it). After a failure, Run tries again.
function Schema.Run()
    if Schema.state == 'ready' then return true end
    if Schema.state == 'running' then return Schema.WaitReady(300000) end
    Schema.state = 'running'
    local ok, res, err = pcall(function() return exports['pfm-core']:RunMigrations(Schema.KEY, Schema.Migrations) end)
    if ok and res == true then
        Schema.state, Schema.lastError = 'ready', nil
        announceReady()
        return true
    end
    Schema.state = 'failed'
    Schema.lastError = tostring(ok and (err or res) or res)
    print(('^1[pf-policemdt]^7 database migrations failed (%s): the MDT cannot use its tables'):format(Schema.lastError))
    return false
end

--- True once the schema is applied. Starts the run when nobody has yet; waits up to timeoutMs
--- (default 5 minutes) while it runs; false at once after a failed run.
function Schema.WaitReady(timeoutMs)
    if Schema.state == 'idle' then return Schema.Run() end
    local waited, limit = 0, tonumber(timeoutMs) or 300000
    while Schema.state == 'running' do
        if waited >= limit then return false end
        Wait(250)
        waited = waited + 250
    end
    return Schema.state == 'ready'
end

CreateThread(function()
    if Schema.state == 'idle' then Schema.Run() end
end)
