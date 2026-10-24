-- pf-garageuionly SQL Schema with pf-mechanicjob and pf-policemdt Integration
-- This schema is compatible with and extends the existing qb-core/ESX vehicle system

-- ============================================================================
-- INTEGRATION MODE: Adds columns to existing player_vehicles table
-- ============================================================================
-- Use this if you already have player_vehicles table (recommended)

ALTER TABLE `player_vehicles`
    -- Title/Salvage System
    ADD COLUMN IF NOT EXISTS `title_status` ENUM('clean', 'salvage', 'rebuilt', 'scrapped') DEFAULT 'clean',
    ADD COLUMN IF NOT EXISTS `vin` VARCHAR(17) UNIQUE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `vin_blacklisted` BOOLEAN DEFAULT FALSE,
    
    -- Location Data (if not exists)
    ADD COLUMN IF NOT EXISTS `stored_heading` FLOAT DEFAULT 0.0,
    
    -- Insurance & Police
    ADD COLUMN IF NOT EXISTS `insurance_tier` ENUM('none', 'basic', 'standard', 'premium', 'government') DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS `police_heat` ENUM('none', 'low', 'medium', 'high') DEFAULT 'none',
    
    -- Damage State (JSON) - Additional to vehicle_diagnostics
    ADD COLUMN IF NOT EXISTS `damaged_panels` TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `broken_lights` TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `broken_windows` TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `tire_status` TEXT DEFAULT NULL,
    
    -- User Organization
    ADD COLUMN IF NOT EXISTS `is_favorite` BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS `folder_id` INT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `custom_order` INT DEFAULT 0,
    
    -- Job Vehicle
    ADD COLUMN IF NOT EXISTS `is_job_vehicle` BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS `job_name` VARCHAR(50) DEFAULT NULL,
    
    -- Timestamps (if not exists)
    ADD COLUMN IF NOT EXISTS `purchase_date` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS `last_used` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Indexes for performance
    ADD INDEX IF NOT EXISTS `idx_favorite` (`is_favorite`),
    ADD INDEX IF NOT EXISTS `idx_folder` (`folder_id`),
    ADD INDEX IF NOT EXISTS `idx_last_used` (`last_used`),
    ADD INDEX IF NOT EXISTS `idx_title_status` (`title_status`);

-- ============================================================================
-- STANDALONE MODE: Creates new table (use if you don't have player_vehicles)
-- ============================================================================
CREATE TABLE IF NOT EXISTS `player_vehicles_standalone` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner` VARCHAR(50) NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `plate` VARCHAR(20) UNIQUE NOT NULL,
    `vehicle` VARCHAR(50) NOT NULL,
    `hash` VARCHAR(50) NOT NULL,
    `mods` LONGTEXT DEFAULT NULL,
    `garage` VARCHAR(50) DEFAULT 'pillboxgarage',
    `fuel` INT DEFAULT 100,
    `engine` FLOAT DEFAULT 1000.0,
    `body` FLOAT DEFAULT 1000.0,
    `state` INT DEFAULT 0,
    `depotprice` INT DEFAULT 0,
    `drivingdistance` INT DEFAULT 0,
    `status` TEXT DEFAULT NULL,
    
    -- Title/Salvage System
    `title_status` ENUM('clean', 'salvage', 'rebuilt', 'scrapped') DEFAULT 'clean',
    `vin` VARCHAR(17) UNIQUE DEFAULT NULL,
    `vin_blacklisted` BOOLEAN DEFAULT FALSE,
    
    -- Location Data
    `stored_coords` TEXT DEFAULT NULL,
    `stored_heading` FLOAT DEFAULT 0.0,
    
    -- Insurance & Police
    `insurance_tier` ENUM('none', 'basic', 'standard', 'premium', 'government') DEFAULT 'none',
    `police_heat` ENUM('none', 'low', 'medium', 'high') DEFAULT 'none',
    
    -- Damage State (JSON)
    `damaged_panels` TEXT DEFAULT NULL,
    `broken_lights` TEXT DEFAULT NULL,
    `broken_windows` TEXT DEFAULT NULL,
    `tire_status` TEXT DEFAULT NULL,
    
    -- User Organization
    `is_favorite` BOOLEAN DEFAULT FALSE,
    `folder_id` INT DEFAULT NULL,
    `custom_order` INT DEFAULT 0,
    
    -- Job Vehicle
    `is_job_vehicle` BOOLEAN DEFAULT FALSE,
    `job_name` VARCHAR(50) DEFAULT NULL,
    
    -- Metadata
    `purchase_date` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `last_used` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    KEY `owner` (`owner`),
    KEY `citizenid` (`citizenid`),
    KEY `plate` (`plate`),
    KEY `title_status` (`title_status`),
    KEY `last_used` (`last_used`),
    KEY `is_favorite` (`is_favorite`),
    KEY `folder_id` (`folder_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vehicle History/Timeline
CREATE TABLE IF NOT EXISTS `vehicle_history` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `vehicle_id` INT NOT NULL,
    `plate` VARCHAR(20) NOT NULL,
    `event_type` ENUM('purchase', 'sale', 'repair', 'crime', 'impound', 'insurance_claim', 'ownership_transfer', 'title_change', 'accident') NOT NULL,
    `event_title` VARCHAR(100) NOT NULL,
    `event_description` TEXT,
    `event_cost` INT DEFAULT 0,
    `event_location` VARCHAR(100),
    `related_player` VARCHAR(50),
    `mileage_at_event` INT DEFAULT 0,
    `event_date` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    KEY `vehicle_id` (`vehicle_id`),
    KEY `plate` (`plate`),
    KEY `event_type` (`event_type`),
    FOREIGN KEY (`vehicle_id`) REFERENCES `player_vehicles`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vehicle Folders (Player Organization)
CREATE TABLE IF NOT EXISTS `vehicle_folders` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner` VARCHAR(50) NOT NULL,
    `folder_name` VARCHAR(50) NOT NULL,
    `folder_icon` VARCHAR(50) DEFAULT 'folder',
    `folder_order` INT DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Damage Zones Detail (Optional - for more granular tracking)
CREATE TABLE IF NOT EXISTS `vehicle_damage_zones` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `vehicle_id` INT NOT NULL,
    `plate` VARCHAR(20) NOT NULL,
    `zone_name` VARCHAR(50) NOT NULL, -- 'hood', 'front_bumper', 'roof', etc.
    `damage_severity` ENUM('none', 'minor', 'moderate', 'severe', 'destroyed') DEFAULT 'none',
    `repair_cost` INT DEFAULT 0,
    `last_damaged` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    KEY `vehicle_id` (`vehicle_id`),
    KEY `plate` (`plate`),
    FOREIGN KEY (`vehicle_id`) REFERENCES `player_vehicles`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Impound Records
CREATE TABLE IF NOT EXISTS `vehicle_impounds` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `vehicle_id` INT NOT NULL,
    `plate` VARCHAR(20) NOT NULL,
    `impound_reason` VARCHAR(200),
    `impound_location` VARCHAR(100),
    `impound_fee` INT DEFAULT 0,
    `impounded_by` VARCHAR(50), -- Officer name/ID
    `impounded_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `released_at` TIMESTAMP NULL,
    `is_active` BOOLEAN DEFAULT TRUE,
    
    KEY `vehicle_id` (`vehicle_id`),
    KEY `plate` (`plate`),
    KEY `is_active` (`is_active`),
    FOREIGN KEY (`vehicle_id`) REFERENCES `player_vehicles`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insurance Claims
CREATE TABLE IF NOT EXISTS `vehicle_insurance_claims` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `vehicle_id` INT NOT NULL,
    `plate` VARCHAR(20) NOT NULL,
    `claim_type` ENUM('collision', 'theft', 'vandalism', 'natural_disaster', 'total_loss') NOT NULL,
    `claim_amount` INT NOT NULL,
    `claim_status` ENUM('pending', 'approved', 'denied', 'paid') DEFAULT 'pending',
    `claim_description` TEXT,
    `filed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `processed_at` TIMESTAMP NULL,
    
    KEY `vehicle_id` (`vehicle_id`),
    KEY `plate` (`plate`),
    KEY `claim_status` (`claim_status`),
    FOREIGN KEY (`vehicle_id`) REFERENCES `player_vehicles`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sample indexes for performance
CREATE INDEX IF NOT EXISTS idx_owner_favorite ON player_vehicles(owner, is_favorite);
CREATE INDEX IF NOT EXISTS idx_owner_lastused ON player_vehicles(owner, last_used);
CREATE INDEX IF NOT EXISTS idx_folder ON player_vehicles(folder_id);
CREATE INDEX IF NOT EXISTS idx_job_vehicles ON player_vehicles(is_job_vehicle, job_name);

-- ============================================================================
-- INTEGRATION NOTES
-- ============================================================================

-- MECHANIC JOB INTEGRATION (pf-mechanicjob):
-- The following tables from pf-mechanicjob are used by this garage UI:
--   - vehicle_diagnostics: Real-time part damage, mileage, health stats
--   - pf_work_orders: Repair job history
--   - pf_job_history: Completed repair records
--   - pf_service_log: Service book entries
--   - player_vehicles.hasnitrom, noslevel, noscolor: NOS upgrade tracking
-- 
-- The garage UI automatically pulls data from these tables if pf-mechanicjob exists.
-- No additional setup required - just ensure both resources are running.

-- MDT INTEGRATION (pf-policemdt-DEV):
-- The following tables from pf-policemdt are used by this garage UI:
--   - pf_mdt_incidents: Vehicle involvement in police incidents
--     Uses involvedVehicles and involvedVehicleIds columns
-- 
-- Vehicle incidents appear in the timeline/history automatically.
-- Police heat level is calculated based on number of incidents.

-- COMPATIBILITY:
-- This schema is designed to extend your existing player_vehicles table.
-- If you don't have player_vehicles, use the standalone version above.
-- Safe to run on existing databases - uses IF NOT EXISTS and ADD COLUMN IF NOT EXISTS.

