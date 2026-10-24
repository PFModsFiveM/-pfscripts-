-- Ensure qb-garages compatibility (safe to run anytime)
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `mods` LONGTEXT NULL,
  ADD INDEX IF NOT EXISTS `idx_plate` (`plate`);

-- NEW: Dedicated vehicle diagnostics table
CREATE TABLE IF NOT EXISTS `vehicle_diagnostics` (
  `plate` varchar(50) NOT NULL,
  `citizenid` varchar(50) DEFAULT NULL,

  `alternator` float DEFAULT 0,
  `sparkplugs` float DEFAULT 0,
  `carbattery` float DEFAULT 0,
  `oil` float DEFAULT 0,
  `oil_filter` float DEFAULT 0,
  `brakes` float DEFAULT 0,
  `suspension` float DEFAULT 0,
  `axle` float DEFAULT 0,
  `fuel_injector` float DEFAULT 0,
  `powersteeringpump` float DEFAULT 0,
  `radiator` float DEFAULT 0,
  `power_steering_fluid` float DEFAULT 0,
  `transmissionfluid` float DEFAULT 0,
  `brakefluid` float DEFAULT 0,
  `coolant` float DEFAULT 0,

  `engine_part` float DEFAULT 0,
  `body_part` float DEFAULT 0,

  `mileage` double DEFAULT 0,
  `engineHealth` float DEFAULT 1000,
  `bodyHealth` float DEFAULT 1000,
  `tankHealth` float DEFAULT 1000,
  `dirtLevel` float DEFAULT 0,

  PRIMARY KEY (`plate`),
  KEY `citizenid_idx` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pf_parts_catalog (
  part_id VARCHAR(64) PRIMARY KEY,
  label VARCHAR(64) NOT NULL,
  base_cost INT NOT NULL,
  supplier VARCHAR(32) NOT NULL,
  lead_minutes INT NOT NULL DEFAULT 10
);

CREATE TABLE IF NOT EXISTS pf_parts_stock (
  id INT AUTO_INCREMENT PRIMARY KEY,
  society VARCHAR(32) NOT NULL,
  part_id VARCHAR(64) NOT NULL,
  qty INT NOT NULL DEFAULT 0,
  UNIQUE KEY uniq_society_part (society, part_id)
);

CREATE TABLE IF NOT EXISTS pf_supplier_orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  society VARCHAR(32) NOT NULL,
  part_id VARCHAR(64) NOT NULL,
  qty INT NOT NULL,
  unit_cost INT NOT NULL,
  eta_at TIMESTAMP NOT NULL,
  status ENUM('pending','delivered','cancelled') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pf_work_orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  type ENUM('engine','suspension','cosmetic','service') NOT NULL,
  source ENUM('npc','player') NOT NULL,
  requester_name VARCHAR(64) DEFAULT NULL,
  requester_identifier VARCHAR(64) DEFAULT NULL,
  plate VARCHAR(16) NOT NULL,
  veh_model VARCHAR(64) NOT NULL,
  notes VARCHAR(256) DEFAULT NULL,
  required_parts JSON NOT NULL,
  deadline_at TIMESTAMP NULL,
  status ENUM('new','accepted','in_progress','awaiting_parts','complete','failed','cancelled') NOT NULL DEFAULT 'new',
  quality TINYINT DEFAULT 0,
  payout INT DEFAULT 0,
  assigned_to VARCHAR(50) DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pf_mech_profiles (
  citizenid VARCHAR(50) PRIMARY KEY,
  xp INT NOT NULL DEFAULT 0,
  rank INT NOT NULL DEFAULT 1,
  total_earnings INT NOT NULL DEFAULT 0,
  jobs_done INT NOT NULL DEFAULT 0,
  rating_avg FLOAT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS pf_job_history (
  id INT AUTO_INCREMENT PRIMARY KEY,
  work_order_id INT NOT NULL,
  citizenid VARCHAR(50) NOT NULL,
  plate VARCHAR(16) NOT NULL,
  type VARCHAR(32) NOT NULL,
  quality TINYINT NOT NULL,
  payout INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX (citizenid), INDEX (plate)
);

CREATE TABLE IF NOT EXISTS `pf_service_log` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `author` VARCHAR(128) NOT NULL,
  `note` TEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- NOS: persist basic state on the base vehicle table (idempotent)
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `hasnitrom` TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `noslevel`  INT        NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `noscolor`  VARCHAR(16) NULL DEFAULT NULL;

-- Optional: If you want mileage persisted in DB (alternatively use entity statebag)
ALTER TABLE `player_vehicles` ADD COLUMN IF NOT EXISTS `mileage` FLOAT DEFAULT 0.0;

-- ============================================================================
-- WORK ORDER LEVEL SYSTEM
-- ============================================================================

CREATE TABLE IF NOT EXISTS `pf_mechanic_progress` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `level` int(11) DEFAULT 1,
    `xp` int(11) DEFAULT 0,
    `total_jobs` int(11) DEFAULT 0,
    `last_refresh` int(11) DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- mechanic_prices schema for POS overrides/custom charges
CREATE TABLE IF NOT EXISTS `mechanic_prices` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `business` VARCHAR(50) NOT NULL,
    `item` VARCHAR(100) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `category` VARCHAR(50) NOT NULL,
    `price` INT NOT NULL,
    `is_custom` TINYINT(1) NOT NULL DEFAULT 0,
    `is_deleted` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_business_item` (`business`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ensure soft-delete column exists for safe upgrades
ALTER TABLE `mechanic_prices`
  ADD COLUMN IF NOT EXISTS `is_deleted` TINYINT(1) NOT NULL DEFAULT 0;

-- POS Transactions history table
CREATE TABLE IF NOT EXISTS `pf_pos_transactions` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `business` VARCHAR(50) NOT NULL,
    `transaction_id` VARCHAR(100) NOT NULL UNIQUE,
    `customer_id` VARCHAR(50),
    `mechanic_id` VARCHAR(50) NOT NULL,
    `mechanic_name` VARCHAR(100),
    `items` LONGTEXT NOT NULL,
    `subtotal` INT NOT NULL,
    `tax` INT NOT NULL,
    `total` INT NOT NULL,
    `payment_type` VARCHAR(20) NOT NULL,
    `status` VARCHAR(20) DEFAULT 'completed',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_business` (`business`),
    KEY `idx_created_at` (`created_at`),
    KEY `idx_mechanic` (`mechanic_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- BUSINESS MANAGEMENT SYSTEM
-- ============================================================================

-- Core business information table
CREATE TABLE IF NOT EXISTS `pf_business` (
  `business` VARCHAR(50) NOT NULL PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL,
  `primary_color` VARCHAR(7),
  `secondary_color` VARCHAR(7),
  `logo` VARCHAR(256),
  `open` TINYINT(1) DEFAULT 1,
  `tax` FLOAT DEFAULT 0.05,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- POS items/products catalog per business
CREATE TABLE IF NOT EXISTS `pf_pos_items` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_business_settings` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `business_name` VARCHAR(64) NOT NULL DEFAULT 'Los Santos Customs',
  `blip_name` VARCHAR(64) NOT NULL DEFAULT 'Customs Shop',
  `blip_color` INT NOT NULL DEFAULT 3,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_business_employees` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL UNIQUE,
  `name` VARCHAR(80) NOT NULL,
  `role` ENUM('owner','manager','employee') NOT NULL DEFAULT 'employee',
  `hired_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `last_promoted_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ensure promotion timestamp column exists for safe upgrades
ALTER TABLE `pf_business_employees`
  ADD COLUMN IF NOT EXISTS `last_promoted_at` TIMESTAMP NULL DEFAULT NULL;

CREATE TABLE IF NOT EXISTS `pf_business_products` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `product_name` VARCHAR(80) NOT NULL UNIQUE,
  `base_price` INT NOT NULL,
  `current_price` INT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_product_name` (`product_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_business_inventory` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `product_id` INT NOT NULL,
  `quantity` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_product_id` (`product_id`),
  CONSTRAINT `fk_product_id` FOREIGN KEY (`product_id`) REFERENCES `pf_business_products`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_business_sales` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `employee_name` VARCHAR(80) NOT NULL,
  `product_id` INT NOT NULL,
  `product_name` VARCHAR(80) NOT NULL,
  `quantity` INT NOT NULL,
  `total_price` INT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_citizenid` (`citizenid`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_product_id` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_business_locations` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `type` ENUM('stash_shared','locker','duty') NOT NULL,
  `x` FLOAT NOT NULL,
  `y` FLOAT NOT NULL,
  `z` FLOAT NOT NULL,
  `heading` FLOAT NULL,
  `is_prop` TINYINT(1) DEFAULT 0,
  `prop_model` VARCHAR(60) NULL,
  `citizenid` VARCHAR(50) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- MANAGEMENT APP: BUSINESS-KEYED PRODUCTS & SETTINGS
-- ============================================================================

-- Product catalog per business
CREATE TABLE IF NOT EXISTS pf_mechanic_products (
  id INT AUTO_INCREMENT PRIMARY KEY,
  business VARCHAR(50) NOT NULL,
  category VARCHAR(50) NOT NULL,
  name VARCHAR(100) NOT NULL,
  price INT NOT NULL
);

-- Optional business settings
CREATE TABLE IF NOT EXISTS pf_mechanic_settings (
  business VARCHAR(50) PRIMARY KEY,
  markup INT DEFAULT 0
);

-- Core transactions table for management stats (created if missing)
CREATE TABLE IF NOT EXISTS pf_mechanic_transactions (
  id INT NOT NULL AUTO_INCREMENT,
  business VARCHAR(50) NOT NULL,
  employee VARCHAR(50) NULL,
  amount INT NOT NULL DEFAULT 0,
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_business (business),
  KEY idx_employee (employee),
  KEY idx_timestamp (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ensure pf_mechanic_transactions has required columns for management stats
ALTER TABLE pf_mechanic_transactions
  ADD COLUMN IF NOT EXISTS business VARCHAR(50) NOT NULL AFTER id,
  ADD COLUMN IF NOT EXISTS employee VARCHAR(50) NULL,
  ADD COLUMN IF NOT EXISTS amount INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- ============================================================================
-- SAMPLE DATA: POS TRANSACTIONS FOR 30-DAY CHART
-- ============================================================================
-- Insert sample sales data for the last 30 days (for testing chart display)
-- Each day has 2-5 transactions with random amounts between $500-$2500
-- Comment out or delete this section if you don't want test data
INSERT IGNORE INTO `pf_pos_transactions` 
  (`business`, `transaction_id`, `customer_id`, `mechanic_id`, `mechanic_name`, `items`, `subtotal`, `tax`, `total`, `payment_type`, `status`, `created_at`) 
VALUES
-- 30 days ago
(N'mechanic', N'TX-SAMPLE-1', N'ABC1111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 30 DAY),
(N'mechanic', N'TX-SAMPLE-2', N'ABC2222222222', N'MECH1', N'John Mechanic', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'cash', N'completed', NOW() - INTERVAL 30 DAY),
(N'mechanic', N'TX-SAMPLE-3', N'ABC3333333333', N'MECH2', N'Jane Smith', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'bank', N'completed', NOW() - INTERVAL 30 DAY),

-- 29 days ago
(N'mechanic', N'TX-SAMPLE-4', N'ABC4444444444', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 29 DAY),
(N'mechanic', N'TX-SAMPLE-5', N'ABC5555555555', N'MECH2', N'Jane Smith', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'cash', N'completed', NOW() - INTERVAL 29 DAY),

-- 28 days ago
(N'mechanic', N'TX-SAMPLE-6', N'ABC6666666666', N'MECH1', N'John Mechanic', N'[{"item":"coolant","qty":2}]', 400, 20, 420, N'bank', N'completed', NOW() - INTERVAL 28 DAY),
(N'mechanic', N'TX-SAMPLE-7', N'ABC7777777777', N'MECH2', N'Jane Smith', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 28 DAY),
(N'mechanic', N'TX-SAMPLE-8', N'ABC8888888888', N'MECH1', N'John Mechanic', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'cash', N'completed', NOW() - INTERVAL 28 DAY),

-- 27 days ago
(N'mechanic', N'TX-SAMPLE-9', N'ABC9999999999', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 27 DAY),
(N'mechanic', N'TX-SAMPLE-10', N'ABCA111111111', N'MECH1', N'John Mechanic', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'cash', N'completed', NOW() - INTERVAL 27 DAY),
(N'mechanic', N'TX-SAMPLE-11', N'ABCB111111111', N'MECH2', N'Jane Smith', N'[{"item":"brake_fluid","qty":1}]', 250, 12, 262, N'bank', N'completed', NOW() - INTERVAL 27 DAY),

-- 26 days ago
(N'mechanic', N'TX-SAMPLE-12', N'ABCC111111111', N'MECH1', N'John Mechanic', N'[{"item":"transmission_fluid","qty":1}]', 350, 17, 367, N'bank', N'completed', NOW() - INTERVAL 26 DAY),
(N'mechanic', N'TX-SAMPLE-13', N'ABCD111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 26 DAY),

-- 25 days ago
(N'mechanic', N'TX-SAMPLE-14', N'ABCE111111111', N'MECH1', N'John Mechanic', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'bank', N'completed', NOW() - INTERVAL 25 DAY),
(N'mechanic', N'TX-SAMPLE-15', N'ABCF111111111', N'MECH2', N'Jane Smith', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 25 DAY),
(N'mechanic', N'TX-SAMPLE-16', N'ABCG111111111', N'MECH1', N'John Mechanic', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'cash', N'completed', NOW() - INTERVAL 25 DAY),
(N'mechanic', N'TX-SAMPLE-17', N'ABCH111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 25 DAY),

-- 24 days ago
(N'mechanic', N'TX-SAMPLE-18', N'ABCI111111111', N'MECH1', N'John Mechanic', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'cash', N'completed', NOW() - INTERVAL 24 DAY),
(N'mechanic', N'TX-SAMPLE-19', N'ABCJ111111111', N'MECH2', N'Jane Smith', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'bank', N'completed', NOW() - INTERVAL 24 DAY),
(N'mechanic', N'TX-SAMPLE-20', N'ABCK111111111', N'MECH1', N'John Mechanic', N'[{"item":"coolant","qty":2}]', 400, 20, 420, N'bank', N'completed', NOW() - INTERVAL 24 DAY),

-- 23 days ago
(N'mechanic', N'TX-SAMPLE-21', N'ABCL111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 23 DAY),
(N'mechanic', N'TX-SAMPLE-22', N'ABCM111111111', N'MECH1', N'John Mechanic', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'bank', N'completed', NOW() - INTERVAL 23 DAY),
(N'mechanic', N'TX-SAMPLE-23', N'ABCN111111111', N'MECH2', N'Jane Smith', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'bank', N'completed', NOW() - INTERVAL 23 DAY),

-- 22 days ago
(N'mechanic', N'TX-SAMPLE-24', N'ABCO111111111', N'MECH1', N'John Mechanic', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'cash', N'completed', NOW() - INTERVAL 22 DAY),
(N'mechanic', N'TX-SAMPLE-25', N'ABCP111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 22 DAY),
(N'mechanic', N'TX-SAMPLE-26', N'ABCQ111111111', N'MECH1', N'John Mechanic', N'[{"item":"transmission_fluid","qty":1}]', 350, 17, 367, N'bank', N'completed', NOW() - INTERVAL 22 DAY),
(N'mechanic', N'TX-SAMPLE-27', N'ABCR111111111', N'MECH2', N'Jane Smith', N'[{"item":"brake_fluid","qty":1}]', 250, 12, 262, N'cash', N'completed', NOW() - INTERVAL 22 DAY),

-- 21 days ago
(N'mechanic', N'TX-SAMPLE-28', N'ABCS111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 21 DAY),
(N'mechanic', N'TX-SAMPLE-29', N'ABCT111111111', N'MECH2', N'Jane Smith', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 21 DAY),
(N'mechanic', N'TX-SAMPLE-30', N'ABCU111111111', N'MECH1', N'John Mechanic', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'cash', N'completed', NOW() - INTERVAL 21 DAY),

-- 20 days ago
(N'mechanic', N'TX-SAMPLE-31', N'ABCV111111111', N'MECH2', N'Jane Smith', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'bank', N'completed', NOW() - INTERVAL 20 DAY),
(N'mechanic', N'TX-SAMPLE-32', N'ABCW111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 20 DAY),

-- 19 days ago
(N'mechanic', N'TX-SAMPLE-33', N'ABCX111111111', N'MECH2', N'Jane Smith', N'[{"item":"coolant","qty":2}]', 400, 20, 420, N'cash', N'completed', NOW() - INTERVAL 19 DAY),
(N'mechanic', N'TX-SAMPLE-34', N'ABCY111111111', N'MECH1', N'John Mechanic', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 19 DAY),
(N'mechanic', N'TX-SAMPLE-35', N'ABCZ111111111', N'MECH2', N'Jane Smith', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'bank', N'completed', NOW() - INTERVAL 19 DAY),

-- 18 days ago
(N'mechanic', N'TX-SAMPLE-36', N'ABD1111111111', N'MECH1', N'John Mechanic', N'[{"item":"transmission_fluid","qty":1}]', 350, 17, 367, N'cash', N'completed', NOW() - INTERVAL 18 DAY),
(N'mechanic', N'TX-SAMPLE-37', N'ABD2111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 18 DAY),

-- 17 days ago
(N'mechanic', N'TX-SAMPLE-38', N'ABD3111111111', N'MECH1', N'John Mechanic', N'[{"item":"brake_fluid","qty":1}]', 250, 12, 262, N'bank', N'completed', NOW() - INTERVAL 17 DAY),
(N'mechanic', N'TX-SAMPLE-39', N'ABD4111111111', N'MECH2', N'Jane Smith', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 17 DAY),
(N'mechanic', N'TX-SAMPLE-40', N'ABD5111111111', N'MECH1', N'John Mechanic', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'cash', N'completed', NOW() - INTERVAL 17 DAY),

-- 16 days ago
(N'mechanic', N'TX-SAMPLE-41', N'ABD6111111111', N'MECH2', N'Jane Smith', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'bank', N'completed', NOW() - INTERVAL 16 DAY),
(N'mechanic', N'TX-SAMPLE-42', N'ABD7111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 16 DAY),
(N'mechanic', N'TX-SAMPLE-43', N'ABD8111111111', N'MECH2', N'Jane Smith', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'cash', N'completed', NOW() - INTERVAL 16 DAY),

-- 15 days ago
(N'mechanic', N'TX-SAMPLE-44', N'ABD9111111111', N'MECH1', N'John Mechanic', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 15 DAY),
(N'mechanic', N'TX-SAMPLE-45', N'ABDA111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 15 DAY),
(N'mechanic', N'TX-SAMPLE-46', N'ABDB111111111', N'MECH1', N'John Mechanic', N'[{"item":"coolant","qty":2}]', 400, 20, 420, N'cash', N'completed', NOW() - INTERVAL 15 DAY),

-- 14 days ago
(N'mechanic', N'TX-SAMPLE-47', N'ABDC111111111', N'MECH2', N'Jane Smith', N'[{"item":"transmission_fluid","qty":1}]', 350, 17, 367, N'bank', N'completed', NOW() - INTERVAL 14 DAY),
(N'mechanic', N'TX-SAMPLE-48', N'ABDD111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 14 DAY),

-- 13 days ago
(N'mechanic', N'TX-SAMPLE-49', N'ABDE111111111', N'MECH2', N'Jane Smith', N'[{"item":"brake_fluid","qty":1}]', 250, 12, 262, N'cash', N'completed', NOW() - INTERVAL 13 DAY),
(N'mechanic', N'TX-SAMPLE-50', N'ABDF111111111', N'MECH1', N'John Mechanic', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 13 DAY),
(N'mechanic', N'TX-SAMPLE-51', N'ABDG111111111', N'MECH2', N'Jane Smith', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'bank', N'completed', NOW() - INTERVAL 13 DAY),

-- 12 days ago
(N'mechanic', N'TX-SAMPLE-52', N'ABDH111111111', N'MECH1', N'John Mechanic', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'cash', N'completed', NOW() - INTERVAL 12 DAY),
(N'mechanic', N'TX-SAMPLE-53', N'ABDI111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 12 DAY),
(N'mechanic', N'TX-SAMPLE-54', N'ABDJ111111111', N'MECH1', N'John Mechanic', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'bank', N'completed', NOW() - INTERVAL 12 DAY),

-- 11 days ago
(N'mechanic', N'TX-SAMPLE-55', N'ABDK111111111', N'MECH2', N'Jane Smith', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 11 DAY),
(N'mechanic', N'TX-SAMPLE-56', N'ABDL111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 11 DAY),

-- 10 days ago
(N'mechanic', N'TX-SAMPLE-57', N'ABDM111111111', N'MECH2', N'Jane Smith', N'[{"item":"coolant","qty":2}]', 400, 20, 420, N'bank', N'completed', NOW() - INTERVAL 10 DAY),
(N'mechanic', N'TX-SAMPLE-58', N'ABDN111111111', N'MECH1', N'John Mechanic', N'[{"item":"transmission_fluid","qty":1}]', 350, 17, 367, N'bank', N'completed', NOW() - INTERVAL 10 DAY),
(N'mechanic', N'TX-SAMPLE-59', N'ABDO111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 10 DAY),

-- 9 days ago
(N'mechanic', N'TX-SAMPLE-60', N'ABDP111111111', N'MECH1', N'John Mechanic', N'[{"item":"brake_fluid","qty":1}]', 250, 12, 262, N'bank', N'completed', NOW() - INTERVAL 9 DAY),
(N'mechanic', N'TX-SAMPLE-61', N'ABDQ111111111', N'MECH2', N'Jane Smith', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 9 DAY),
(N'mechanic', N'TX-SAMPLE-62', N'ABDR111111111', N'MECH1', N'John Mechanic', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'bank', N'completed', NOW() - INTERVAL 9 DAY),

-- 8 days ago
(N'mechanic', N'TX-SAMPLE-63', N'ABDS111111111', N'MECH2', N'Jane Smith', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'cash', N'completed', NOW() - INTERVAL 8 DAY),
(N'mechanic', N'TX-SAMPLE-64', N'ABDT111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 8 DAY),
(N'mechanic', N'TX-SAMPLE-65', N'ABDU111111111', N'MECH2', N'Jane Smith', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'bank', N'completed', NOW() - INTERVAL 8 DAY),

-- 7 days ago
(N'mechanic', N'TX-SAMPLE-66', N'ABDV111111111', N'MECH1', N'John Mechanic', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 7 DAY),
(N'mechanic', N'TX-SAMPLE-67', N'ABDW111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 7 DAY),
(N'mechanic', N'TX-SAMPLE-68', N'ABDX111111111', N'MECH1', N'John Mechanic', N'[{"item":"coolant","qty":2}]', 400, 20, 420, N'bank', N'completed', NOW() - INTERVAL 7 DAY),
(N'mechanic', N'TX-SAMPLE-69', N'ABDY111111111', N'MECH2', N'Jane Smith', N'[{"item":"transmission_fluid","qty":1}]', 350, 17, 367, N'bank', N'completed', NOW() - INTERVAL 7 DAY),

-- 6 days ago
(N'mechanic', N'TX-SAMPLE-70', N'ABDZ111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 6 DAY),
(N'mechanic', N'TX-SAMPLE-71', N'ABE1111111111', N'MECH2', N'Jane Smith', N'[{"item":"brake_fluid","qty":1}]', 250, 12, 262, N'bank', N'completed', NOW() - INTERVAL 6 DAY),
(N'mechanic', N'TX-SAMPLE-72', N'ABE2111111111', N'MECH1', N'John Mechanic', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 6 DAY),

-- 5 days ago
(N'mechanic', N'TX-SAMPLE-73', N'ABE3111111111', N'MECH2', N'Jane Smith', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'bank', N'completed', NOW() - INTERVAL 5 DAY),
(N'mechanic', N'TX-SAMPLE-74', N'ABE4111111111', N'MECH1', N'John Mechanic', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'cash', N'completed', NOW() - INTERVAL 5 DAY),
(N'mechanic', N'TX-SAMPLE-75', N'ABE5111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 5 DAY),

-- 4 days ago
(N'mechanic', N'TX-SAMPLE-76', N'ABE6111111111', N'MECH1', N'John Mechanic', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'bank', N'completed', NOW() - INTERVAL 4 DAY),
(N'mechanic', N'TX-SAMPLE-77', N'ABE7111111111', N'MECH2', N'Jane Smith', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 4 DAY),
(N'mechanic', N'TX-SAMPLE-78', N'ABE8111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 4 DAY),

-- 3 days ago
(N'mechanic', N'TX-SAMPLE-79', N'ABE9111111111', N'MECH2', N'Jane Smith', N'[{"item":"coolant","qty":2}]', 400, 20, 420, N'bank', N'completed', NOW() - INTERVAL 3 DAY),
(N'mechanic', N'TX-SAMPLE-80', N'ABEA111111111', N'MECH1', N'John Mechanic', N'[{"item":"transmission_fluid","qty":1}]', 350, 17, 367, N'bank', N'completed', NOW() - INTERVAL 3 DAY),

-- 2 days ago
(N'mechanic', N'TX-SAMPLE-81', N'ABEB111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'cash', N'completed', NOW() - INTERVAL 2 DAY),
(N'mechanic', N'TX-SAMPLE-82', N'ABEC111111111', N'MECH1', N'John Mechanic', N'[{"item":"brake_fluid","qty":1}]', 250, 12, 262, N'bank', N'completed', NOW() - INTERVAL 2 DAY),
(N'mechanic', N'TX-SAMPLE-83', N'ABED111111111', N'MECH2', N'Jane Smith', N'[{"item":"tire_rotation","qty":1}]', 300, 15, 315, N'bank', N'completed', NOW() - INTERVAL 2 DAY),

-- 1 day ago
(N'mechanic', N'TX-SAMPLE-84', N'ABEE111111111', N'MECH1', N'John Mechanic', N'[{"item":"brake_pad","qty":1}]', 650, 32, 682, N'bank', N'completed', NOW() - INTERVAL 1 DAY),
(N'mechanic', N'TX-SAMPLE-85', N'ABEF111111111', N'MECH2', N'Jane Smith', N'[{"item":"air_filter","qty":1}]', 200, 10, 210, N'cash', N'completed', NOW() - INTERVAL 1 DAY),
(N'mechanic', N'TX-SAMPLE-86', N'ABEG111111111', N'MECH1', N'John Mechanic', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW() - INTERVAL 1 DAY),

-- Today
(N'mechanic', N'TX-SAMPLE-87', N'ABEH111111111', N'MECH2', N'Jane Smith', N'[{"item":"battery","qty":1}]', 800, 40, 840, N'bank', N'completed', NOW()),
(N'mechanic', N'TX-SAMPLE-88', N'ABEI111111111', N'MECH1', N'John Mechanic', N'[{"item":"spark_plug","qty":4}]', 300, 15, 315, N'cash', N'completed', NOW()),
(N'mechanic', N'TX-SAMPLE-89', N'ABEJ111111111', N'MECH2', N'Jane Smith', N'[{"item":"oil_change","qty":1}]', 450, 22, 472, N'bank', N'completed', NOW());


-- ============================================================================
-- MERGED SQL FILES
-- The content below was previously split across separate *.sql files in the
-- resource root. They have been merged here for convenience.
-- ============================================================================

-- ============================================================================
-- pf_mechanic_prices.sql (legacy/split file)
-- ============================================================================

-- mechanic_prices schema for POS overrides/custom charges
CREATE TABLE IF NOT EXISTS `mechanic_prices` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `business` VARCHAR(50) NOT NULL,
    `item` VARCHAR(100) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `category` VARCHAR(50) NOT NULL,
    `price` INT NOT NULL,
    `is_custom` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_business_item` (`business`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================================
-- pf_mechanic_workorders.sql (legacy/split file)
-- ============================================================================

-- PF Mechanic Job - Work Order Level System
-- Database table for player progression

CREATE TABLE IF NOT EXISTS `pf_mechanic_progress` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `level` int(11) DEFAULT 1,
    `xp` int(11) DEFAULT 0,
    `total_jobs` int(11) DEFAULT 0,
    `last_refresh` int(11) DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================================
-- pf_mechanic_sample_data.sql
-- ============================================================================

-- ============================================================================
-- SAMPLE DATA FOR MANAGEMENT APP (for testing/development)
-- Run this AFTER pf_mechanic.sql to populate with test data
-- 
-- NOTE: Real employees will be pulled from players table automatically
-- No need to manually add placeholder employees anymore
-- Real mechanics will show in the Employees tab
-- ============================================================================

-- Insert business settings
INSERT IGNORE INTO `pf_business_settings` (`id`, `business_name`, `blip_name`, `blip_color`) 
VALUES (1, 'Los Santos Customs', 'Customs Shop', 3);

-- Insert mechanic prices (cash register items with business-specific pricing)
-- These are the actual products that show in the pricing/inventory management
INSERT IGNORE INTO `mechanic_prices` (`business`, `item`, `label`, `category`, `price`, `is_custom`) VALUES
('Los Santos Customs', 'engine', 'Engine Repair', 'Engine Services', 1500, 0),
('Los Santos Customs', 'transmission', 'Transmission Fix', 'Engine Services', 2500, 0),
('Los Santos Customs', 'suspension', 'Suspension Service', 'Suspension', 800, 0),
('Los Santos Customs', 'brakes', 'Brake Service', 'Braking', 600, 0),
('Los Santos Customs', 'paint', 'Paint Job', 'Cosmetic', 5000, 0),
('Los Santos Customs', 'tires', 'Tire Replacement', 'Wheels', 400, 0),
('Los Santos Customs', 'oil_change', 'Oil Change', 'Maintenance', 200, 0),
('Los Santos Customs', 'tuning', 'Engine Tuning', 'Performance', 3000, 0),
('Los Santos Customs', 'exhaust', 'Custom Exhaust', 'Performance', 1200, 0),
('Los Santos Customs', 'diagnostic', 'Diagnostic Scan', 'Diagnostics', 150, 0);

-- Insert sample products (required for inventory FK: pf_business_inventory.product_id -> pf_business_products.id)
INSERT IGNORE INTO `pf_business_products` (`id`, `product_name`, `base_price`, `current_price`) VALUES
(1,  'Engine Repair',        1500, 1500),
(2,  'Transmission Fix',     2500, 2500),
(3,  'Suspension Service',    800,  800),
(4,  'Brake Service',         600,  600),
(5,  'Paint Job',            5000, 5000),
(6,  'Tire Replacement',      400,  400),
(7,  'Oil Change',            200,  200),
(8,  'Engine Tuning',        3000, 3000),
(9,  'Custom Exhaust',       1200, 1200),
(10, 'Diagnostic Scan',       150,  150);

-- Insert sample inventory (stock of parts/services available)
INSERT IGNORE INTO `pf_business_inventory` (`id`, `product_id`, `quantity`) VALUES
(1, 1, 25),
(2, 2, 15),
(3, 3, 30),
(4, 4, 40),
(5, 5, 8),
(6, 6, 50),
(7, 7, 100),
(8, 8, 12),
(9, 9, 20),
(10, 10, 200);

-- Insert sample locations for stash/locker/duty
INSERT IGNORE INTO `pf_business_locations` (`id`, `type`, `x`, `y`, `z`, `heading`, `is_prop`, `prop_model`) VALUES
(1, 'stash_shared', 729.5, -987.3, 24.3, 180.0, 1, 'prop_tool_box_03'),
(2, 'locker', 741.2, -1001.5, 28.4, 90.0, 0, NULL),
(3, 'duty', 750.8, -1010.2, 22.1, 0.0, 0, NULL);


-- ============================================================================
-- GET_REAL_PLAYER_DATA.sql
-- ============================================================================

-- ============================================================================
-- HOW TO GET REAL PLAYER DATA FROM QBCORE
-- ============================================================================

-- ============================================================================
-- GET ACTUAL MECHANIC PLAYERS
-- ============================================================================

-- Get mechanics with their actual names (QBCore stores names in JSON)
SELECT 
  citizenid, 
  JSON_EXTRACT(charinfo, '$.firstname') as firstname,
  JSON_EXTRACT(charinfo, '$.lastname') as lastname,
  JSON_EXTRACT(charinfo, '$.phone') as phone
FROM `players` 
WHERE JSON_EXTRACT(job, '$.name') = 'mechanic'
LIMIT 10;

-- Alternative: Get ANY players (not just mechanics)
SELECT 
  citizenid, 
  JSON_EXTRACT(charinfo, '$.firstname') as firstname,
  JSON_EXTRACT(charinfo, '$.lastname') as lastname
FROM `players` 
LIMIT 5;


-- ============================================================================
-- REPLACE SAMPLE DATA WITH REAL PLAYERS (One-liner version)
-- ============================================================================

-- This will INSERT your REAL mechanic players into the employees table
-- WARNING: This will add duplicate employees if you run it twice!
-- Use this ONLY if you haven't already populated employees

-- First, CLEAR the sample employees:
TRUNCATE TABLE `pf_business_employees`;

-- Then INSERT real mechanic players:
INSERT INTO `pf_business_employees` (citizenid, name, role)
SELECT 
  citizenid,
  CONCAT(JSON_EXTRACT(charinfo, '$.firstname'), ' ', JSON_EXTRACT(charinfo, '$.lastname')) as name,
  'employee' as role
FROM `players`
WHERE JSON_EXTRACT(job, '$.name') = 'mechanic'
LIMIT 5;

-- Or set the first one as owner:
-- Change 'employee' to 'owner' for the first player


-- ============================================================================
-- VERIFY IT WORKED
-- ============================================================================

-- Check how many employees are now in the system:
SELECT COUNT(*) as total_employees FROM `pf_business_employees`;

-- See all employees:
SELECT citizenid, name, role FROM `pf_business_employees`;


-- ============================================================================
-- MANUAL UPDATE (if you want to pick specific players)
-- ============================================================================

-- Step 1: Get the list of players
SELECT 
  @index:=@index+1 as num,
  citizenid, 
  JSON_EXTRACT(charinfo, '$.firstname') as firstname,
  JSON_EXTRACT(charinfo, '$.lastname') as lastname
FROM `players`, (SELECT @index:=0) as t
LIMIT 10;

-- Step 2: Copy a citizenid from the results above

-- Step 3: Insert it as an employee (replace ABC1234567DEFGH with real citizenid):
INSERT INTO `pf_business_employees` (citizenid, name, role, hired_at)
VALUES ('ABC1234567DEFGH', 'Player Name', 'owner', NOW())
ON DUPLICATE KEY UPDATE role='owner';  -- Update if already exists


-- ============================================================================
-- BATCH UPDATE EXAMPLE (Multiple Real Players)
-- ============================================================================

-- If you want to use REAL data instead of placeholders, run this:
-- It will DELETE sample data and INSERT actual mechanics from your server

-- DELETE FROM `pf_business_employees`;  -- UNCOMMENT TO DELETE SAMPLE DATA

-- INSERT INTO `pf_business_employees` (citizenid, name, role, hired_at) VALUES
-- ('ABC1234567DEFGH', 'John Smith', 'owner', NOW()),
-- ('XYZ9876543QWERT', 'Jane Doe', 'manager', NOW()),
-- ('DEF4567890ASDFG', 'Mike Johnson', 'employee', NOW());


-- ============================================================================
-- CHECK WHAT JOB STRUCTURE LOOKS LIKE
-- ============================================================================

-- See the JSON structure for one player:
SELECT citizenid, job, charinfo FROM `players` LIMIT 1;

-- This will show you the exact format, something like:
-- job: {"name":"mechanic","grade":0,"payment":0}
-- charinfo: {"firstname":"John","lastname":"Doe",...}

-- ============================================================================
-- ADVANCED VEHICLE ENGINEERING AND TUNING SYSTEM
-- ============================================================================

CREATE TABLE IF NOT EXISTS `pf_vehicle_tuning` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL UNIQUE,
  `model` VARCHAR(64),
  
  -- Engine Configuration
  `engine_block` VARCHAR(32) DEFAULT 'stock',           -- stock, strengthened, forged
  `internals` VARCHAR(32) DEFAULT 'stock',              -- stock, forged
  `forced_induction` VARCHAR(32) DEFAULT 'none',        -- none, turbo_stage1, turbo_stage2, turbo_stage3, supercharger_stage1, supercharger_stage2
  `intercooler` VARCHAR(32) DEFAULT 'none',             -- none, street, race
  `intake` VARCHAR(32) DEFAULT 'stock',                 -- stock, street, race
  `exhaust` VARCHAR(32) DEFAULT 'stock',                -- stock, street, race
  `fuel_injectors` VARCHAR(32) DEFAULT 'stock',         -- stock, 550cc, 1000cc, 2000cc
  `fuel_pump` VARCHAR(32) DEFAULT 'stock',              -- stock, street, race
  `fuel_type` VARCHAR(32) DEFAULT 'pump',               -- pump, premium, e85, race
  `ecu_map` VARCHAR(32) DEFAULT 'stock',                -- stock, eco, street, performance, race, valet
  `ignition` VARCHAR(32) DEFAULT 'stock',               -- stock, upgraded
  `cooling` VARCHAR(32) DEFAULT 'stock',                -- stock, street, race
  `oil_system` VARCHAR(32) DEFAULT 'stock',             -- stock, upgraded
  
  -- Drivetrain Configuration
  `clutch` VARCHAR(32) DEFAULT 'stock',                 -- stock, street, race
  `gearbox` VARCHAR(32) DEFAULT 'stock',                -- stock, strengthened, race
  `differential` VARCHAR(32) DEFAULT 'stock',           -- stock, lsd, race
  `drivetrain_rating_nm` INT DEFAULT 250,               -- Torque rating in Nm
  
  -- Performance Targets
  `target_boost_psi` FLOAT DEFAULT 0,
  `target_hp` INT,
  `target_torque_nm` INT,
  `power_limit_multiplier` FLOAT DEFAULT 1.0,
  `torque_limit_multiplier` FLOAT DEFAULT 1.0,
  
  -- Wear and Condition (0-100)
  `engine_wear` INT DEFAULT 0,
  `turbo_wear` INT DEFAULT 0,
  `clutch_wear` INT DEFAULT 0,
  `gearbox_wear` INT DEFAULT 0,
  `diff_wear` INT DEFAULT 0,
  `oil_quality` INT DEFAULT 100,
  `coolant_quality` INT DEFAULT 100,
  
  -- Thermal State (0-100)
  `engine_heat` INT DEFAULT 0,
  `turbo_heat` INT DEFAULT 0,
  
  -- Tires
  `tire_compound` VARCHAR(32) DEFAULT 'street',         -- street, sport, semi_slick, slick
  `tire_wear` INT DEFAULT 0,
  
  -- Economy Scaling
  `fuel_consumption_multiplier` FLOAT DEFAULT 1.0,
  `maintenance_cost_multiplier` FLOAT DEFAULT 1.0,
  
  -- Timestamps
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_plate` (`plate`),
  INDEX `idx_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Service history table for tracking maintenance
CREATE TABLE IF NOT EXISTS `pf_vehicle_service_history` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `service_type` VARCHAR(64) NOT NULL,  -- oil_change, cooling_service, engine_rebuild, clutch_replacement, gearbox_service
  `cost` INT DEFAULT 0,
  `mechanic_id` VARCHAR(50),
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- DIAGNOSTIC_QUERIES.sql
-- ============================================================================

-- ============================================================================
-- DIAGNOSTIC QUERIES - Check what's in the Management App database
-- Run these queries in your database manager to see what data exists
-- ============================================================================

-- Check if business settings exist
SELECT COUNT(*) as settings_count FROM `pf_business_settings`;
SELECT * FROM `pf_business_settings`;

-- Check if products exist
SELECT COUNT(*) as products_count FROM `pf_business_products`;
SELECT * FROM `pf_business_products` LIMIT 10;

-- Check if employees exist
SELECT COUNT(*) as employees_count FROM `pf_business_employees`;
SELECT * FROM `pf_business_employees`;

-- Check if inventory exists
SELECT COUNT(*) as inventory_count FROM `pf_business_inventory`;
SELECT * FROM `pf_business_inventory`;

-- Check if sales exist
SELECT COUNT(*) as sales_count FROM `pf_business_sales`;
SELECT * FROM `pf_business_sales` ORDER BY created_at DESC LIMIT 20;

-- Check sales by date (what the chart uses)
SELECT DATE(created_at) as date, SUM(total_price) as total 
FROM `pf_business_sales` 
WHERE created_at >= NOW() - INTERVAL 30 DAY
GROUP BY DATE(created_at) 
ORDER BY DATE(created_at);

-- Check if your actual player exists for employee role lookup
-- QBCore stores names in a JSON 'charinfo' column, not separate firstname/lastname columns
SELECT citizenid, JSON_EXTRACT(charinfo, '$.firstname') as firstname, JSON_EXTRACT(charinfo, '$.lastname') as lastname FROM `players` LIMIT 5;

-- Or if you want to see all player columns:
-- SELECT * FROM `players` LIMIT 1;

-- After running pf_mechanic_sample_data.sql, you should see:
-- - 1 settings record
-- - 10 products
-- - 5 employees (with placeholder citizenids)
-- - 10 inventory records
-- - 13 sales records

