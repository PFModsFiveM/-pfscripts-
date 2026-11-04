-- ============================================================================
-- pf-emsmdt: no SQL import needed
-- ============================================================================
-- The resource creates and upgrades its own tables at start through pfm-core migrations
-- (server/schema.lua, key 'pf-emsmdt': v1 roster reset backups, v2 the MDT tables). This file is the
-- same schema for reference or for a manual import: every statement is CREATE TABLE IF NOT EXISTS, so
-- importing it before or after the resource has started changes no data, and the migrations still run
-- over it without error (a spec keeps the two identical).
--
-- This file used to be a copy of the police MDT's schema (pf_mdt_* tables, with police SOPs and CCTV
-- cameras as data). Importing it on a server that runs pf-policemdt wrote into the police MDT's own
-- tables (duplicate SOPs, a duplicate-key error on the cameras). It is in git history if needed.
-- Injury and medical tables come from pf-ambulancejob (its own migrations).

-- v1 roster reset backups
CREATE TABLE IF NOT EXISTS `pf_emsmdt_roster_backup` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- v2 MDT tables
CREATE TABLE IF NOT EXISTS `pf_emsmdt_patient_notes` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenId` VARCHAR(50) NOT NULL,
  `text` LONGTEXT NOT NULL,
  `author` VARCHAR(100) NOT NULL,
  `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pf_emsmdt_patient_notes_citizenId` (`citizenId`),
  KEY `idx_pf_emsmdt_patient_notes_createdAt` (`createdAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_emsmdt_user_profiles` (
  `citizenId` VARCHAR(50) NOT NULL,
  `callsign` VARCHAR(50) NULL,
  `status` VARCHAR(50) NULL,
  `avatarUrl` VARCHAR(255) NULL,
  `updatedAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_emsmdt_bulletins` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(255) NOT NULL,
  `body` LONGTEXT NOT NULL,
  `createdByCitizenId` VARCHAR(50) NULL,
  `createdByName` VARCHAR(100) NULL,
  `createdAt` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pf_emsmdt_bulletins_createdAt` (`createdAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_emsmdt_roster` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_emsmdt_sops` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_mgmt_profiles` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_discipline` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_audit` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
