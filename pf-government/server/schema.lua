-- pf-government versioned tables (pf_schema_migrations, resource 'pf-government').
-- The older tables come from sql/install.sql and the Ensure* helpers in each module; everything
-- added for the field apps (tablet and computer) lives here.

GovSchema = GovSchema or {}

GovSchema.Migrations = {
    {
        version = 1,
        name = 'delivery zones, business requests, inspection follow-ups, business districts, bill notes',
        up = {
            -- default delivery zones: one per business (scope business, ref = business id) and one per
            -- district (scope district, ref = district name), approved on site by staff
            [[CREATE TABLE IF NOT EXISTS `pf_gov_delivery_zones` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `scope` VARCHAR(16) NOT NULL,
                `ref` VARCHAR(100) NOT NULL,
                `label` VARCHAR(64) NULL,
                `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
                `heading` DOUBLE NOT NULL DEFAULT 0,
                `request_id` BIGINT NULL,
                `set_by` VARCHAR(50) NULL,
                `set_by_name` VARCHAR(255) NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_scope_ref` (`scope`, `ref`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            -- what a business asked City Hall for (one row per pf-services request) and the decision
            [[CREATE TABLE IF NOT EXISTS `pf_gov_business_requests` (
                `request_id` BIGINT UNSIGNED NOT NULL,
                `business_id` VARCHAR(100) NOT NULL,
                `kind` VARCHAR(48) NOT NULL,
                `subject` VARCHAR(64) NULL,
                `note` VARCHAR(500) NULL,
                `x` DOUBLE NULL, `y` DOUBLE NULL, `z` DOUBLE NULL, `heading` DOUBLE NULL,
                `requested_by` VARCHAR(50) NOT NULL,
                `requested_by_name` VARCHAR(255) NULL,
                `status` VARCHAR(16) NOT NULL DEFAULT 'open',
                `decision` VARCHAR(16) NULL,
                `decision_note` VARCHAR(500) NULL,
                `decided_by` VARCHAR(50) NULL,
                `decided_by_name` VARCHAR(255) NULL,
                `decided_at` TIMESTAMP NULL DEFAULT NULL,
                `outcome_ref` VARCHAR(64) NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`request_id`),
                KEY `idx_business` (`business_id`, `created_at`),
                KEY `idx_status` (`status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            -- same definition as businesses.lua, so the ALTER below always has a table
            [[CREATE TABLE IF NOT EXISTS `pf_gov_business_inspections` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `business_id` VARCHAR(100) NOT NULL,
                `result_status` ENUM('compliant', 'warning', 'non_compliant', 'flagged') NOT NULL DEFAULT 'compliant',
                `findings` TEXT DEFAULT NULL,
                `inspected_by` VARCHAR(50) DEFAULT NULL,
                `inspected_by_name` VARCHAR(255) DEFAULT NULL,
                `inspected_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX `idx_business_id` (`business_id`),
                INDEX `idx_inspected_at` (`inspected_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            'ALTER TABLE `pf_gov_business_inspections` ADD COLUMN IF NOT EXISTS `follow_up_at` TIMESTAMP NULL DEFAULT NULL',
            'ALTER TABLE `pf_gov_business_inspections` ADD COLUMN IF NOT EXISTS `request_id` BIGINT NULL DEFAULT NULL',
            -- the district a business trades in (its fallback delivery zone and the district of its news)
            'ALTER TABLE `pf_gov_businesses` ADD COLUMN IF NOT EXISTS `district` VARCHAR(60) NULL DEFAULT NULL',
            -- WaiveBill always wrote the waiver reason here; the column never existed, so waivers failed
            'ALTER TABLE `pf_gov_bills` ADD COLUMN IF NOT EXISTS `notes` TEXT NULL DEFAULT NULL',
        },
    },
}

local ready, busy = false, false

--- Runs the migrations once (at start, and lazily from the first caller that needs the tables).
function GovSchema.Ensure()
    if ready then return true end
    while busy do Wait(0) end
    if ready then return true end
    busy = true
    local ok, res, err = pcall(function()
        if type(RunMigrations) == 'function' then return RunMigrations('pf-government', GovSchema.Migrations) end
        return exports['pfm-core']:RunMigrations('pf-government', GovSchema.Migrations)
    end)
    busy = false
    if ok and res == true then
        ready = true
        return true
    end
    print('^1[PF-GOVERNMENT]^7 migrations failed: ' .. tostring(ok and err or res))
    return false
end

function GovSchema.__reset() ready, busy = false, false end
