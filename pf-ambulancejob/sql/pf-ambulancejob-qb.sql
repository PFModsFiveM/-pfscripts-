-- ============================================================================
-- PF-AMBULANCEJOB DATABASE SCHEMA
-- ============================================================================
-- Advanced EMS Job System Database Tables

-- ============================================================================
-- PLAYER INJURIES TABLE
-- ============================================================================
-- Tracks all injuries for players
CREATE TABLE IF NOT EXISTS `player_injuries` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizen_id` VARCHAR(50) NOT NULL,
  `injury_type` VARCHAR(50) NOT NULL COMMENT 'gunshot_wound, laceration, blunt_trauma, burn, fracture, etc',
  `severity` VARCHAR(20) NOT NULL COMMENT 'critical, severe, moderate, minor',
  `body_zone` VARCHAR(50) NOT NULL COMMENT 'head, torso, left_arm, right_arm, left_leg, right_leg',
  `health_percentage` INT DEFAULT 0 COMMENT 'Health remaining in this zone (0-100)',
  `weapon` VARCHAR(50) COMMENT 'Weapon that caused the injury',
  `recorded_by` VARCHAR(50) COMMENT 'Medic who recorded this injury',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL,
  
  INDEX `idx_citizen_id` (`citizen_id`),
  INDEX `idx_created_at` (`created_at`),
  INDEX `idx_body_zone` (`body_zone`),
  INDEX `idx_severity` (`severity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- PLAYER TREATMENT LOG TABLE
-- ============================================================================
-- Tracks all treatments applied to players
CREATE TABLE IF NOT EXISTS `player_treatment_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizen_id` VARCHAR(50) NOT NULL,
  `treatment_type` VARCHAR(50) NOT NULL COMMENT 'revive, bandage, splint, oxygen, etc',
  `treated_by` VARCHAR(50) NOT NULL COMMENT 'Medic who applied treatment',
  `injury_id` INT COMMENT 'Related injury ID',
  `duration` INT COMMENT 'Treatment duration in ms',
  `effectiveness` INT DEFAULT 100 COMMENT 'Effectiveness percentage (0-100)',
  `notes` TEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL,
  
  INDEX `idx_citizen_id` (`citizen_id`),
  INDEX `idx_treated_by` (`treated_by`),
  INDEX `idx_created_at` (`created_at`),
  FOREIGN KEY (`injury_id`) REFERENCES `player_injuries`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- PLAYER HEALTH SNAPSHOT TABLE
-- ============================================================================
-- Tracks player health history for medical documentation
CREATE TABLE IF NOT EXISTS `player_health_snapshot` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizen_id` VARCHAR(50) NOT NULL,
  `health` INT COMMENT 'Overall health (0-200)',
  `armor` INT COMMENT 'Armor value',
  `is_unconscious` BOOLEAN DEFAULT FALSE,
  `last_damage_weapon` VARCHAR(50),
  `last_damage_zone` VARCHAR(50),
  `snapshot_taken_by` VARCHAR(50) COMMENT 'Medic who took this snapshot',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  INDEX `idx_citizen_id` (`citizen_id`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- PATIENT CARE REPORTS (PCR) TABLE
-- ============================================================================
-- Medical documentation and records
CREATE TABLE IF NOT EXISTS `patient_care_reports` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizen_id` VARCHAR(50) NOT NULL,
  `pcr_number` VARCHAR(20) UNIQUE,
  `call_id` INT,
  `responding_unit` VARCHAR(50),
  `primary_medic` VARCHAR(50) NOT NULL,
  `secondary_medic` VARCHAR(50),
  `chief_complaint` TEXT,
  `narrative` LONGTEXT,
  `transport_hospital` VARCHAR(100),
  `transport_time` INT COMMENT 'Transport time in seconds',
  `patient_outcome` VARCHAR(50) COMMENT 'transported, refused, doa, cancelled',
  `condition_on_arrival` VARCHAR(50) COMMENT 'critical, serious, stable, minor',
  `condition_on_transport` VARCHAR(50),
  `advanced_airway` BOOLEAN DEFAULT FALSE,
  `iv_access` BOOLEAN DEFAULT FALSE,
  `medications_given` TEXT COMMENT 'JSON array of medications',
  `vitals_scene` JSON COMMENT 'Vital signs at scene',
  `vitals_transport` JSON COMMENT 'Vital signs during transport',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL,
  
  INDEX `idx_citizen_id` (`citizen_id`),
  INDEX `idx_pcr_number` (`pcr_number`),
  INDEX `idx_created_at` (`created_at`),
  INDEX `idx_primary_medic` (`primary_medic`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- VITAL SIGNS LOG TABLE
-- ============================================================================
-- Tracks vital signs measurements
CREATE TABLE IF NOT EXISTS `vital_signs_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `pcr_id` INT NOT NULL,
  `citizen_id` VARCHAR(50) NOT NULL,
  `bp_systolic` INT COMMENT 'Blood Pressure Systolic',
  `bp_diastolic` INT COMMENT 'Blood Pressure Diastolic',
  `heart_rate` INT COMMENT 'Heart Rate (bpm)',
  `respiration_rate` INT COMMENT 'Respiration Rate (breaths/min)',
  `spo2` INT COMMENT 'Oxygen Saturation (%)',
  `temperature` DECIMAL(5, 2) COMMENT 'Temperature (Fahrenheit)',
  `gcs` INT COMMENT 'Glasgow Coma Scale (3-15)',
  `glucose` INT COMMENT 'Blood Glucose (mg/dL)',
  `pupil_response` VARCHAR(50) COMMENT 'PERL - Pupils Equal Reactive to Light',
  `recorded_at` INT COMMENT 'Time relative to call start (seconds)',
  `recorded_by` VARCHAR(50),
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  INDEX `idx_pcr_id` (`pcr_id`),
  INDEX `idx_citizen_id` (`citizen_id`),
  FOREIGN KEY (`pcr_id`) REFERENCES `patient_care_reports`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- MEDICATION ADMINISTRATION TABLE
-- ============================================================================
-- Tracks all medications given
CREATE TABLE IF NOT EXISTS `medication_administration` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `pcr_id` INT NOT NULL,
  `citizen_id` VARCHAR(50) NOT NULL,
  `medication_name` VARCHAR(100) NOT NULL,
  `dosage` VARCHAR(50),
  `route` VARCHAR(50) COMMENT 'IV, IM, PO, IO, Inhaled, etc',
  `time_administered` INT COMMENT 'Time relative to call start (seconds)',
  `administered_by` VARCHAR(50) NOT NULL,
  `indication` VARCHAR(100),
  `response` VARCHAR(255) COMMENT 'Patient response to medication',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  INDEX `idx_pcr_id` (`pcr_id`),
  INDEX `idx_citizen_id` (`citizen_id`),
  FOREIGN KEY (`pcr_id`) REFERENCES `patient_care_reports`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- DOA (DECEASED ON ARRIVAL) RECORDS TABLE
-- ============================================================================
-- Tracks death pronouncements
CREATE TABLE IF NOT EXISTS `doa_records` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizen_id` VARCHAR(50) NOT NULL,
  `pcr_id` INT,
  `pronounced_by` VARCHAR(50) NOT NULL COMMENT 'Medic who pronounced',
  `location` VARCHAR(255),
  `circumstances` TEXT,
  `resuscitation_attempted` BOOLEAN,
  `resuscitation_duration` INT COMMENT 'Duration in seconds',
  `obvious_death_criteria` TEXT COMMENT 'Decapitation, decomposition, etc',
  `police_notified` BOOLEAN DEFAULT FALSE,
  `coroner_notified` BOOLEAN DEFAULT FALSE,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL,
  
  INDEX `idx_citizen_id` (`citizen_id`),
  INDEX `idx_pronounced_by` (`pronounced_by`),
  FOREIGN KEY (`pcr_id`) REFERENCES `patient_care_reports`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- MASS CASUALTY INCIDENT (MCI) TABLE
-- ============================================================================
-- Tracks MCIs
CREATE TABLE IF NOT EXISTS `mci_incidents` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `mci_number` VARCHAR(20) UNIQUE,
  `incident_commander` VARCHAR(50),
  `location` VARCHAR(255),
  `cause` VARCHAR(255),
  `total_patients` INT DEFAULT 0,
  `triage_red` INT DEFAULT 0 COMMENT 'Immediate',
  `triage_yellow` INT DEFAULT 0 COMMENT 'Delayed',
  `triage_green` INT DEFAULT 0 COMMENT 'Minor',
  `triage_black` INT DEFAULT 0 COMMENT 'Deceased',
  `status` VARCHAR(50) COMMENT 'active, closed',
  `notes` LONGTEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `closed_at` TIMESTAMP NULL,
  
  INDEX `idx_mci_number` (`mci_number`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- MCI PATIENTS TABLE
-- ============================================================================
-- Links patients to MCIs
CREATE TABLE IF NOT EXISTS `mci_patients` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `mci_id` INT NOT NULL,
  `citizen_id` VARCHAR(50) NOT NULL,
  `triage_color` VARCHAR(20) COMMENT 'red, yellow, green, black',
  `patient_number` INT,
  `assigned_unit` VARCHAR(50),
  `pcr_id` INT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  INDEX `idx_mci_id` (`mci_id`),
  INDEX `idx_citizen_id` (`citizen_id`),
  FOREIGN KEY (`mci_id`) REFERENCES `mci_incidents`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`pcr_id`) REFERENCES `patient_care_reports`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- (No stored procedures: the three that were here used DELIMITER, which only the mysql command-line
-- client understands, so importing this file through oxmysql or most tools failed there; one also read
-- a pcr_id column player_injuries does not have, and nothing called any of them.)
-- pf-ambulancejob creates its own injury tables at start (versioned migration); this file is only
-- needed for the extra EMS tables (patient care reports, vitals, medications, MCI).
-- ============================================================================
