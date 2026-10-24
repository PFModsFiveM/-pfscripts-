-- =====================================================
-- PF GOVERNMENT MIGRATION: MONTHLY BUDGET + INFRASTRUCTURE V2
-- =====================================================

-- 1) Extend legacy pf_gov_budgets for compatibility and monthly terminology.
ALTER TABLE `pf_gov_budgets`
    ADD COLUMN IF NOT EXISTS `approved_monthly_budget` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS `linked_society_name` VARCHAR(100) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS `society_balance` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS `spent_this_month` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS `minimum_required_monthly` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS `recommended_monthly_budget` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS `projected_month_end_balance` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS `budget_status` VARCHAR(20) NOT NULL DEFAULT 'Stable',
    ADD COLUMN IF NOT EXISTS `month_key` VARCHAR(7) NULL DEFAULT NULL;

-- Optional: migrate data from weekly fields if present.
UPDATE `pf_gov_budgets`
SET
    `approved_monthly_budget` = CASE
        WHEN `approved_monthly_budget` <= 0 AND `weekly_budget` IS NOT NULL THEN `weekly_budget` * 4
        ELSE `approved_monthly_budget`
    END,
    `spent_this_month` = CASE
        WHEN `spent_this_month` <= 0 AND `spent_this_week` IS NOT NULL THEN `spent_this_week` * 4
        ELSE `spent_this_month`
    END,
    `month_key` = COALESCE(`month_key`, DATE_FORMAT(NOW(), '%Y-%m'));

-- 2) Canonical monthly budget plans.
CREATE TABLE IF NOT EXISTS `pf_gov_department_monthly_plans` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `department` VARCHAR(50) NOT NULL,
    `month_key` VARCHAR(7) NOT NULL,
    `approved_monthly_budget` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `linked_society_name` VARCHAR(100) NOT NULL,
    `society_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `spent_this_month` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `minimum_required_monthly` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `recommended_monthly_budget` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `projected_month_end_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `budget_status` VARCHAR(20) NOT NULL DEFAULT 'Stable',
    `salary_obligation_monthly` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `equipment_plan` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `fleet_plan` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `facility_plan` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `emergency_buffer` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `projected_obligations_remaining` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `updated_by` VARCHAR(64) NULL,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uniq_department_month` (`department`, `month_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `pf_gov_department_monthly_plans` (
    `department`, `month_key`, `approved_monthly_budget`, `linked_society_name`, `society_balance`, `spent_this_month`, `updated_by`
)
SELECT
    b.`department`,
    DATE_FORMAT(NOW(), '%Y-%m') AS month_key,
    COALESCE(NULLIF(b.`approved_monthly_budget`, 0), COALESCE(b.`weekly_budget`, 0) * 4) AS approved_monthly_budget,
    CASE
        WHEN b.`department` = 'ems' THEN 'ambulance'
        WHEN b.`department` IN ('police', 'government', 'dot', 'power', 'water') THEN b.`department`
        ELSE b.`department`
    END AS linked_society_name,
    COALESCE(b.`society_balance`, 0),
    COALESCE(NULLIF(b.`spent_this_month`, 0), COALESCE(b.`spent_this_week`, 0) * 4),
    'migration'
FROM `pf_gov_budgets` b
ON DUPLICATE KEY UPDATE
    `approved_monthly_budget` = VALUES(`approved_monthly_budget`),
    `linked_society_name` = VALUES(`linked_society_name`),
    `society_balance` = VALUES(`society_balance`),
    `spent_this_month` = VALUES(`spent_this_month`);

-- 3) Budget transaction ledger.
CREATE TABLE IF NOT EXISTS `pf_gov_budget_transactions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `department` VARCHAR(50) NOT NULL,
    `month_key` VARCHAR(7) NOT NULL,
    `transaction_type` ENUM('treasury_funding','society_spend','adjustment') NOT NULL,
    `category` VARCHAR(50) NOT NULL,
    `amount` DECIMAL(15,2) NOT NULL,
    `society_before` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `society_after` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `actor_id` VARCHAR(64) NULL,
    `actor_name` VARCHAR(255) NULL,
    `reason` VARCHAR(255) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_department_month` (`department`, `month_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4) Infrastructure department state (monthly operations model).
CREATE TABLE IF NOT EXISTS `pf_gov_infra_department_state` (
    `department` VARCHAR(50) PRIMARY KEY,
    `monthly_operating_budget` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `linked_society_name` VARCHAR(100) NOT NULL,
    `society_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `spent_this_month` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `monthly_maintenance_demand` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `monthly_backlog` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `condition_percent` DECIMAL(5,2) NOT NULL DEFAULT 100,
    `district_impact_stage` INT NOT NULL DEFAULT 1,
    `status` VARCHAR(24) NOT NULL DEFAULT 'Normal',
    `installed_upgrades` LONGTEXT NULL,
    `projected_month_end_balance` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5) Infrastructure district simulation state.
CREATE TABLE IF NOT EXISTS `pf_gov_infra_district_state` (
    `district_name` VARCHAR(60) PRIMARY KEY,
    `priority_order` INT NOT NULL DEFAULT 100,
    `power_stage` INT NOT NULL DEFAULT 1,
    `dot_stage` INT NOT NULL DEFAULT 1,
    `water_stage` INT NOT NULL DEFAULT 1,
    `road_condition` DECIMAL(5,2) NOT NULL DEFAULT 100,
    `pothole_density` DECIMAL(5,2) NOT NULL DEFAULT 0,
    `traffic_light_health` DECIMAL(5,2) NOT NULL DEFAULT 100,
    `street_light_health` DECIMAL(5,2) NOT NULL DEFAULT 100,
    `maintenance_backlog` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `hazard_stage` INT NOT NULL DEFAULT 1,
    `blackout_flicker` TINYINT(1) NOT NULL DEFAULT 0,
    `next_state_change_at` BIGINT NULL,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pf_gov_infra_transactions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `department` VARCHAR(50) NOT NULL,
    `month_key` VARCHAR(7) NOT NULL,
    `transaction_type` VARCHAR(50) NOT NULL,
    `category` VARCHAR(50) NOT NULL,
    `amount` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `actor_id` VARCHAR(64) NULL,
    `actor_name` VARCHAR(255) NULL,
    `reason` VARCHAR(255) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_department_month` (`department`, `month_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
