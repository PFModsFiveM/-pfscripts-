-- pf-jobgarages schema (MySQL / MariaDB)

-- -----------------------------------------------------
-- Table: job_garage_vehicles
-- Stores fleet vehicles for each job garage and their state
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `job_garage_vehicles` (
  `id`                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `garage_id`         VARCHAR(64)  NOT NULL,   -- e.g., 'mechanic_main'
  `plate`             VARCHAR(32)  NOT NULL,
  `model`             VARCHAR(64)  NOT NULL,
  `label`             VARCHAR(128) NULL,

  `min_grade`         INT          NOT NULL DEFAULT 0, -- base grade restriction per vehicle
  `active`            TINYINT(1)   NOT NULL DEFAULT 1, -- soft delete / hide from fleet

  `assignment_type`   ENUM('none','citizenid','grade') NOT NULL DEFAULT 'none',
  `assigned_citizenid` VARCHAR(64) NULL,
  `assigned_name`      VARCHAR(128) NULL,
  `assigned_grade`     INT          NULL,

  `out`                TINYINT(1)   NOT NULL DEFAULT 0, -- currently signed out
  `out_citizenid`      VARCHAR(64)  NULL,
  `out_name`           VARCHAR(128) NULL,
  `out_since`          DATETIME     NULL,

  `last_used_at`       DATETIME     NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_garage_plate` (`garage_id`, `plate`),
  KEY `idx_garage_active` (`garage_id`, `active`),
  KEY `idx_garage_out`    (`garage_id`, `out`),
  KEY `idx_plate`         (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------
-- Table: job_garage_permissions
-- Per-garage minimum grades for use and manage
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `job_garage_permissions` (
  `garage_id`          VARCHAR(64) NOT NULL,
  `min_grade_use`      INT         NOT NULL DEFAULT 0,
  `min_grade_manage`   INT         NOT NULL DEFAULT 4,

  PRIMARY KEY (`garage_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------
-- Table: job_garage_logs
-- Recent actions for auditing and UI display
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `job_garage_logs` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `garage_id`      VARCHAR(64)  NOT NULL,
  `vehicle_id`     INT UNSIGNED NULL,
  `plate`          VARCHAR(32)  NULL,
  `model`          VARCHAR(64)  NULL,
  `action`         VARCHAR(32)  NOT NULL,

  `actor_cid`      VARCHAR(64)  NULL,
  `actor_name`     VARCHAR(128) NULL,
  `target_cid`     VARCHAR(64)  NULL,
  `target_name`    VARCHAR(128) NULL,

  `extra`          TEXT         NULL, 
  `created_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  KEY `idx_garage_created` (`garage_id`, `created_at`),
  KEY `idx_vehicle` (`vehicle_id`),
  KEY `idx_action`  (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `player_vehicles` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid`  VARCHAR(64)  NOT NULL,
  `plate`      VARCHAR(32)  NOT NULL,
  `vehicle`    TEXT         NULL,       
  `mods`       TEXT         NULL,       
  `engine`     INT          NULL,
  `body`       INT          NULL,
  `custom_label` VARCHAR(128) NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_plate` (`plate`),
  KEY `idx_owner` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------
-- Seed examples (optional)
-- -----------------------------------------------------
-- INSERT INTO job_garage_permissions (garage_id, min_grade_use, min_grade_manage) VALUES
--   ('mechanic_main', 0, 4),
--   ('police_main',   0, 4),
--   ('ambulance_main',0, 4);

-- Example fleet entries
-- INSERT INTO job_garage_vehicles (garage_id, plate, model, label, min_grade, active, assignment_type)
-- VALUES
--   ('mechanic_main', 'MECH001', 'flatbed',  'Flatbed 1', 0, 1, 'none'),
--   ('police_main',   'LSPD001', 'police3',  'Patrol 3',  0, 1, 'none'),
--   ('ambulance_main','EMS001',  'ambulance','Ambulance', 0, 1, 'none');
