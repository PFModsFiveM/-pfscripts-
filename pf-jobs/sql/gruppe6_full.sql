-- pf-jobs Gruppe6 Complete Schema (Fresh Install + Upgrade Guide)
-- -------------------------------------------------------------
-- FRESH INSTALL: Execute this entire file.
-- UPGRADE (older minimal schema installed): Execute only the section
-- labeled 'UPGRADE FROM MINIMAL SCHEMA'.
-- -------------------------------------------------------------
-- Notes:
--  * Uses utf8mb4 + unicode_ci for full character support.
--  * xp log table tracks changes for auditing/debugging.
--  * group + group_members tables manage persistent parties (optional).
--  * All CREATE TABLE use IF NOT EXISTS for safety.
-- -------------------------------------------------------------

/* =========================
   CORE XP TABLE
   ========================= */
CREATE TABLE IF NOT EXISTS `pf_gruppe6_xp` (
  `citizenid` VARCHAR(64) NOT NULL,
  `xp` INT(11) NOT NULL DEFAULT 0,
  `level` INT(11) NOT NULL DEFAULT 1,
  `last_contract` TIMESTAMP NULL DEFAULT NULL,
  `total_contracts` INT(11) NOT NULL DEFAULT 0,
  `total_earned` INT(11) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`),
  KEY `idx_level` (`level`),
  KEY `idx_xp` (`xp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================
   XP CHANGE LOG
   ========================= */
CREATE TABLE IF NOT EXISTS `pf_gruppe6_xp_log` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(64) NOT NULL,
  `action` VARCHAR(50) NOT NULL,
  `xp_before` INT(11) NOT NULL,
  `xp_after` INT(11) NOT NULL,
  `amount` INT(11) NOT NULL,
  `reason` VARCHAR(255) DEFAULT NULL,
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_citizenid` (`citizenid`),
  KEY `idx_timestamp` (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================
   GROUPS (Party Metadata)
   ========================= */
CREATE TABLE IF NOT EXISTS `pf_gruppe6_groups` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `host_citizenid` VARCHAR(64) NOT NULL,
  `open` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_host` (`host_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================
   GROUP MEMBERS (Party Splits)
   ========================= */
CREATE TABLE IF NOT EXISTS `pf_gruppe6_group_members` (
  `group_id` INT(11) NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `display_name` VARCHAR(64) NOT NULL,
  `cut_percent` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`group_id`, `citizenid`),
  KEY `idx_member` (`citizenid`),
  KEY `idx_group` (`group_id`),
  CONSTRAINT `fk_group_members_group` FOREIGN KEY (`group_id`) REFERENCES `pf_gruppe6_groups`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `pf_gruppe6_xp`
ADD COLUMN IF NOT EXISTS `upgrades` TEXT DEFAULT '{}' AFTER `level`;