-- PF Government Database Schema
-- Install ALL tables required for the government system

-- =====================================================
-- TREASURY SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_treasury` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `balance` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `updated_by` VARCHAR(50) DEFAULT NULL,
    INDEX `idx_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert initial treasury balance
INSERT INTO `pf_gov_treasury` (`balance`) VALUES (100000.00) ON DUPLICATE KEY UPDATE `balance` = `balance`;

-- =====================================================
-- TAX SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_taxes` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `tax_type` VARCHAR(50) NOT NULL UNIQUE,
    `rate` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    `min_rate` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    `max_rate` DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `description` TEXT DEFAULT NULL,
    `last_changed_by` VARCHAR(50) DEFAULT NULL,
    `last_changed_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_tax_type` (`tax_type`),
    INDEX `idx_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert default tax types
INSERT INTO `pf_gov_taxes` (`tax_type`, `rate`, `min_rate`, `max_rate`, `description`) VALUES
    ('income', 15.00, 0.00, 50.00, 'Income tax on paychecks and job payments'),
    ('business', 10.00, 0.00, 30.00, 'Business revenue tax'),
    ('property_transfer', 5.00, 0.00, 20.00, 'Property purchase/transfer tax'),
    ('vehicle_registration', 500.00, 0.00, 5000.00, 'Vehicle registration fee (flat)'),
    ('vehicle_purchase', 8.00, 0.00, 20.00, 'Vehicle purchase tax'),
    ('sales', 8.50, 0.00, 15.00, 'Sales tax on transactions'),
    ('supplies', 6.00, 0.00, 20.00, 'Business supplies purchase tax')
ON DUPLICATE KEY UPDATE `tax_type` = `tax_type`;

-- =====================================================
-- BUDGET SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_budgets` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `department` VARCHAR(50) NOT NULL UNIQUE,
    `weekly_budget` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `spent_this_week` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `last_reset` TIMESTAMP NULL DEFAULT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `description` TEXT DEFAULT NULL,
    `updated_by` VARCHAR(50) DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_department` (`department`),
    INDEX `idx_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert default departments
INSERT INTO `pf_gov_budgets` (`department`, `weekly_budget`, `description`) VALUES
    ('police', 50000.00, 'Police Department'),
    ('ems', 40000.00, 'Emergency Medical Services'),
    ('dot', 25000.00, 'Department of Transportation'),
    ('utilities', 15000.00, 'Utilities and Public Works'),
    ('government', 30000.00, 'Government Payroll and Operations')
ON DUPLICATE KEY UPDATE `department` = `department`;

-- =====================================================
-- LAWS SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_laws` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(255) NOT NULL,
    `category` VARCHAR(100) NOT NULL,
    `content` TEXT NOT NULL,
    `penalty_min` INT(11) DEFAULT 0,
    `penalty_max` INT(11) DEFAULT 0,
    `fine_min` DECIMAL(10,2) DEFAULT 0.00,
    `fine_max` DECIMAL(10,2) DEFAULT 0.00,
    `status` ENUM('draft', 'active', 'repealed') NOT NULL DEFAULT 'draft',
    `effective_date` TIMESTAMP NULL DEFAULT NULL,
    `created_by` VARCHAR(50) NOT NULL,
    `created_by_name` VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_by` VARCHAR(50) DEFAULT NULL,
    `updated_by_name` VARCHAR(255) DEFAULT NULL,
    `updated_at` TIMESTAMP NULL DEFAULT NULL,
    `repealed_by` VARCHAR(50) DEFAULT NULL,
    `repealed_at` TIMESTAMP NULL DEFAULT NULL,
    INDEX `idx_status` (`status`),
    INDEX `idx_category` (`category`),
    INDEX `idx_effective_date` (`effective_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert example laws
INSERT INTO `pf_gov_laws` (`title`, `category`, `content`, `penalty_min`, `penalty_max`, `fine_min`, `fine_max`, `status`, `effective_date`, `created_by`, `created_by_name`) VALUES
    ('Speed Limit Enforcement', 'Traffic', 'Speed limits must be observed at all times. Exceeding posted limits may result in fines.', 0, 0, 100.00, 500.00, 'active', NOW(), 'system', 'System'),
    ('Weapons Permit Required', 'Criminal', 'All firearms must be registered and carried with a valid permit.', 30, 180, 1000.00, 5000.00, 'active', NOW(), 'system', 'System'),
    ('Business License Requirement', 'Business', 'All businesses must obtain and maintain a valid business license.', 0, 0, 500.00, 2500.00, 'active', NOW(), 'system', 'System')
ON DUPLICATE KEY UPDATE `title` = `title`;

-- =====================================================
-- LICENSES AND PERMITS
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_licenses` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `license_type` VARCHAR(100) NOT NULL,
    `owner_type` ENUM('citizen', 'business') NOT NULL,
    `owner_id` VARCHAR(50) NOT NULL,
    `owner_name` VARCHAR(255) DEFAULT NULL,
    `status` ENUM('active', 'suspended', 'revoked', 'expired') NOT NULL DEFAULT 'active',
    `issued_by` VARCHAR(50) NOT NULL,
    `issued_by_name` VARCHAR(255) DEFAULT NULL,
    `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL DEFAULT NULL,
    `notes` TEXT DEFAULT NULL,
    INDEX `idx_license_type` (`license_type`),
    INDEX `idx_owner` (`owner_type`, `owner_id`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- BILLS AND FINES
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_bills` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `bill_type` ENUM('fine', 'tax', 'utility', 'license', 'invoice', 'other') NOT NULL,
    `target_type` ENUM('citizen', 'business') NOT NULL,
    `target_id` VARCHAR(50) NOT NULL,
    `target_name` VARCHAR(255) DEFAULT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `amount_paid` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `status` ENUM('unpaid', 'partial', 'paid', 'delinquent', 'waived') NOT NULL DEFAULT 'unpaid',
    `description` TEXT DEFAULT NULL,
    `due_date` TIMESTAMP NULL DEFAULT NULL,
    `issued_by` VARCHAR(50) NOT NULL,
    `issued_by_name` VARCHAR(255) DEFAULT NULL,
    `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `paid_at` TIMESTAMP NULL DEFAULT NULL,
    `last_updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_target` (`target_type`, `target_id`),
    INDEX `idx_status` (`status`),
    INDEX `idx_bill_type` (`bill_type`),
    INDEX `idx_due_date` (`due_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- UTILITIES AND SERVICES
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_utilities` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `property_type` ENUM('property', 'business') NOT NULL,
    `property_id` VARCHAR(100) NOT NULL,
    `property_name` VARCHAR(255) DEFAULT NULL,
    `owner_id` VARCHAR(50) DEFAULT NULL,
    `owner_name` VARCHAR(255) DEFAULT NULL,
    `power_status` ENUM('active', 'disconnected', 'delinquent') NOT NULL DEFAULT 'active',
    `water_status` ENUM('active', 'disconnected', 'delinquent') NOT NULL DEFAULT 'active',
    `outstanding_balance` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `last_payment` TIMESTAMP NULL DEFAULT NULL,
    `last_bill_date` TIMESTAMP NULL DEFAULT NULL,
    `disconnected_by` VARCHAR(50) DEFAULT NULL,
    `disconnected_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_property` (`property_type`, `property_id`),
    INDEX `idx_owner` (`owner_id`),
    INDEX `idx_power_status` (`power_status`),
    INDEX `idx_water_status` (`water_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- BUSINESS REGISTRY AND OVERSIGHT
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_businesses` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `business_id` VARCHAR(100) NOT NULL UNIQUE,
    `business_name` VARCHAR(255) NOT NULL,
    `business_type` VARCHAR(100) DEFAULT NULL,
    `owner_id` VARCHAR(50) NOT NULL,
    `owner_name` VARCHAR(255) DEFAULT NULL,
    `employee_count` INT(11) NOT NULL DEFAULT 0,
    `total_revenue` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `total_taxes_paid` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `license_status` ENUM('active', 'suspended', 'revoked', 'expired', 'none') NOT NULL DEFAULT 'none',
    `compliance_status` ENUM('compliant', 'warning', 'non_compliant', 'flagged') NOT NULL DEFAULT 'compliant',
    `notes` TEXT DEFAULT NULL,
    `registered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_business_id` (`business_id`),
    INDEX `idx_owner` (`owner_id`),
    INDEX `idx_license_status` (`license_status`),
    INDEX `idx_compliance_status` (`compliance_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- GOVERNMENT STAFF MANAGEMENT
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_staff` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL UNIQUE,
    `name` VARCHAR(255) NOT NULL,
    `role` VARCHAR(100) NOT NULL,
    `permissions` TEXT DEFAULT NULL,
    `appointed_by` VARCHAR(50) DEFAULT NULL,
    `appointed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_role` (`role`),
    INDEX `idx_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- AUDIT LOG (IMMUTABLE)
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_audit_log` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `action_type` VARCHAR(100) NOT NULL,
    `actor_citizenid` VARCHAR(50) NOT NULL,
    `actor_name` VARCHAR(255) DEFAULT NULL,
    `actor_role` VARCHAR(100) DEFAULT NULL,
    `target_type` VARCHAR(50) DEFAULT NULL,
    `target_id` VARCHAR(100) DEFAULT NULL,
    `details` TEXT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_action_type` (`action_type`),
    INDEX `idx_actor` (`actor_citizenid`),
    INDEX `idx_created_at` (`created_at`),
    INDEX `idx_target` (`target_type`, `target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- ANNOUNCEMENTS
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_announcements` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(255) NOT NULL,
    `content` TEXT NOT NULL,
    `priority` ENUM('low', 'normal', 'high', 'urgent') NOT NULL DEFAULT 'normal',
    `category` VARCHAR(100) DEFAULT 'general',
    `created_by` VARCHAR(50) NOT NULL,
    `created_by_name` VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL DEFAULT NULL,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    INDEX `idx_active` (`active`),
    INDEX `idx_priority` (`priority`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TRANSACTION HISTORY
-- =====================================================

CREATE TABLE IF NOT EXISTS `pf_gov_transactions` (
    `id` INT(11) AUTO_INCREMENT PRIMARY KEY,
    `transaction_type` ENUM('deposit', 'withdrawal', 'tax_collection', 'budget_allocation', 'fine_collection', 'other') NOT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `balance_before` DECIMAL(15,2) NOT NULL,
    `balance_after` DECIMAL(15,2) NOT NULL,
    `source_type` VARCHAR(100) DEFAULT NULL,
    `source_id` VARCHAR(100) DEFAULT NULL,
    `description` TEXT DEFAULT NULL,
    `performed_by` VARCHAR(50) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_transaction_type` (`transaction_type`),
    INDEX `idx_created_at` (`created_at`),
    INDEX `idx_source` (`source_type`, `source_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- COMPLETE
-- =====================================================
