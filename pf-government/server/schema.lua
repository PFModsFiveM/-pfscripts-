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
    {
        version = 2,
        name = 'recurring bills: one bill per subject and period (weekly property tax)',
        up = {
            -- what a recurring bill is for (e.g. 'house:<name>') and its period (e.g. the Monday of the
            -- week). The unique key makes a second bill for the same subject and period impossible,
            -- whatever runs twice; bills without a period (fines, invoices) leave both NULL.
            'ALTER TABLE `pf_gov_bills` ADD COLUMN IF NOT EXISTS `bill_ref` VARCHAR(100) NULL DEFAULT NULL',
            'ALTER TABLE `pf_gov_bills` ADD COLUMN IF NOT EXISTS `bill_period` VARCHAR(16) NULL DEFAULT NULL',
            -- period first: the weekly run reads every bill of one period
            'CREATE UNIQUE INDEX IF NOT EXISTS `uq_bill_period_ref` ON `pf_gov_bills` (`bill_period`, `bill_ref`)',
        },
    },
    {
        version = 3,
        name = 'late fees counted per bill; house utility bills that had no valid payer',
        up = {
            -- how many late fees a bill got and their total, so each overdue bill gets its fee once per
            -- configured period (Config.Bills) and the fee is a share of the original amount, never of
            -- an amount that already holds fees
            'ALTER TABLE `pf_gov_bills` ADD COLUMN IF NOT EXISTS `late_fee_count` INT NOT NULL DEFAULT 0',
            'ALTER TABLE `pf_gov_bills` ADD COLUMN IF NOT EXISTS `late_fee_amount` DECIMAL(12,2) NOT NULL DEFAULT 0.00',
            'ALTER TABLE `pf_gov_bills` ADD COLUMN IF NOT EXISTS `last_late_fee_at` TIMESTAMP NULL DEFAULT NULL',
            -- house utility bills used to be written with target_type 'property', which this column does
            -- not allow: a lenient database stored them with an empty type, so nobody could see or pay
            -- them. They are closed; house utilities are billed to the owner from now on.
            [[UPDATE `pf_gov_bills` SET `status` = 'waived', `notes` = 'Closed: a house utility bill stored without a payer (schema v3)'
                WHERE `target_type` = '' AND `status` IN ('unpaid', 'partial', 'delinquent')]],
        },
    },
    {
        version = 4,
        name = 'bill payment attempts, so a charge the bank settles late still credits the bill',
        up = {
            -- one row per charge that pays a bill (a payment from the Bills app or the terminal, a fine
            -- collected in person), written before the charge. ledger_key is the charge's key in the
            -- bank ledger. pending: charged or being charged, outcome not known yet (that citizen cannot
            -- pay the bill again meanwhile); applied: credited to the bill (applied = how much; refunded
            -- = what went back because less was still due, NULL while that refund is owed); failed:
            -- nothing was taken.
            [[CREATE TABLE IF NOT EXISTS `pf_gov_bill_payments` (
                `pay_key` VARCHAR(100) NOT NULL,
                `ledger_key` VARCHAR(128) NOT NULL,
                `bill_id` INT NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `amount` DECIMAL(12,2) NOT NULL,
                `state` VARCHAR(16) NOT NULL DEFAULT 'pending',
                `applied` DECIMAL(12,2) NULL DEFAULT NULL,
                `refunded` DECIMAL(12,2) NULL DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`pay_key`),
                KEY `idx_bill_state` (`bill_id`, `state`),
                KEY `idx_state_created` (`state`, `created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            -- officials' fine counts per hour and per target per day (Config.Bills limits)
            'CREATE INDEX IF NOT EXISTS `idx_issued_by_at` ON `pf_gov_bills` (`issued_by`, `issued_at`)',
        },
    },
    {
        version = 5,
        name = 'municipal work orders, unit claims and worker payouts',
        up = {
            -- one maintenance job at a site of a district (server/workorders.lua). effect_delta is the
            -- whole order's change to the district field, applied unit by unit; pay_amount is per unit.
            [[CREATE TABLE IF NOT EXISTS `pf_gov_work_orders` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `kind` VARCHAR(16) NOT NULL,
                `district` VARCHAR(60) NOT NULL,
                `site_label` VARCHAR(64) NULL,
                `x` DECIMAL(9,2) NOT NULL, `y` DECIMAL(9,2) NOT NULL, `z` DECIMAL(9,2) NOT NULL,
                `radius` DECIMAL(6,2) NOT NULL,
                `units` TINYINT NOT NULL,
                `units_done` TINYINT NOT NULL DEFAULT 0,
                `effect_field` VARCHAR(32) NOT NULL,
                `effect_delta` DECIMAL(10,2) NOT NULL,
                `cs_eligible` TINYINT(1) NOT NULL DEFAULT 1,
                `pay_amount` INT NOT NULL DEFAULT 0,
                `pay_dept` VARCHAR(32) NULL,
                `source_type` VARCHAR(16) NOT NULL,
                `source_id` VARCHAR(64) NULL,
                `status` VARCHAR(12) NOT NULL,
                `created_at` BIGINT NOT NULL,
                `expires_at` BIGINT NOT NULL,
                `completed_at` BIGINT NULL,
                `idem_key` VARCHAR(128) NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_wo_key` (`idem_key`),
                KEY `idx_wo_open` (`status`, `district`),
                KEY `idx_wo_exp` (`status`, `expires_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- one claimed unit: claimed -> done | released | expired. proof_key is the reporter's
            -- idempotency key (unique), so a repeated report never counts twice.
            [[CREATE TABLE IF NOT EXISTS `pf_gov_work_claims` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `work_order_id` INT NOT NULL,
                `claimant_kind` VARCHAR(8) NOT NULL,
                `citizenid` VARCHAR(64) NOT NULL,
                `ref` VARCHAR(64) NULL,
                `state` VARCHAR(10) NOT NULL,
                `claimed_at` BIGINT NOT NULL,
                `expires_at` BIGINT NOT NULL,
                `done_at` BIGINT NULL,
                `proof_key` VARCHAR(128) NULL,
                `paid_key` VARCHAR(128) NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_wc_proof` (`proof_key`),
                KEY `idx_wc_wo` (`work_order_id`, `state`),
                KEY `idx_wc_cid` (`citizenid`, `state`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- one payout per worker and order (base_key pf-government:wo:<id>:pay:<cid>); the ledger
            -- moves it under numbered attempt keys <base_key>:<n>. owed -> paid | failed.
            [[CREATE TABLE IF NOT EXISTS `pf_gov_work_payments` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `work_order_id` INT NOT NULL,
                `citizenid` VARCHAR(64) NOT NULL,
                `units` TINYINT NOT NULL,
                `amount` INT NOT NULL,
                `pay_dept` VARCHAR(32) NOT NULL,
                `base_key` VARCHAR(128) NOT NULL,
                `ledger_key` VARCHAR(128) NULL,
                `state` VARCHAR(8) NOT NULL DEFAULT 'owed',
                `attempts` INT NOT NULL DEFAULT 0,
                `next_try_at` BIGINT NOT NULL DEFAULT 0,
                `created_at` BIGINT NOT NULL,
                `settled_at` BIGINT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_wp_key` (`base_key`),
                KEY `idx_wp_state` (`state`, `next_try_at`),
                KEY `idx_wp_cid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        version = 6,
        name = 'department core (qualifications, shifts, audit); keyed budget moves',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_gov_dept_qualifications` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `qual` VARCHAR(32) NOT NULL,
                `state` VARCHAR(8) NOT NULL,
                `granted_by` VARCHAR(64) NULL,
                `source` VARCHAR(16) NOT NULL DEFAULT 'manual',
                `expires_at` BIGINT NULL,
                `at` BIGINT NOT NULL,
                `idem_key` VARCHAR(128) NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_dq_cid_qual` (`citizenid`, `qual`),
                UNIQUE KEY `uq_dq_key` (`idem_key`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_gov_dept_shifts` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(64) NOT NULL,
                `dept` VARCHAR(16) NOT NULL,
                `job` VARCHAR(32) NOT NULL,
                `grade` TINYINT NOT NULL,
                `started_at` BIGINT NOT NULL,
                `ended_at` BIGINT NULL,
                `end_reason` VARCHAR(16) NULL,
                PRIMARY KEY (`id`),
                KEY `idx_ds_cid` (`citizenid`, `started_at`),
                KEY `idx_ds_open` (`dept`, `ended_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_gov_dept_audit` (
                `id` BIGINT NOT NULL AUTO_INCREMENT,
                `dept` VARCHAR(16) NOT NULL,
                `action` VARCHAR(32) NOT NULL,
                `actor_cid` VARCHAR(64) NULL,
                `actor_resource` VARCHAR(48) NULL,
                `target` VARCHAR(64) NULL,
                `detail` LONGTEXT NULL,
                `at` BIGINT NOT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_da_dept` (`dept`, `at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- same definition as server/budgets.lua (and sql/install.sql), so the ALTERs below always
            -- have a table, whichever runs first
            [[CREATE TABLE IF NOT EXISTS `pf_gov_budget_transactions` (
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- a keyed society move (SpendFromDepartmentSociety / AddFundsToDepartmentSociety with a
            -- key) writes its row first with the caller's key: pending while the ledger move is under
            -- way or its outcome unknown, failed when the ledger clearly refused it (the next try uses
            -- the next numbered ledger key), applied once booked. Unkeyed rows keep NULL in all three.
            'ALTER TABLE `pf_gov_budget_transactions` ADD COLUMN IF NOT EXISTS `idem_key` VARCHAR(128) NULL',
            'ALTER TABLE `pf_gov_budget_transactions` ADD COLUMN IF NOT EXISTS `state` VARCHAR(10) NULL',
            'ALTER TABLE `pf_gov_budget_transactions` ADD COLUMN IF NOT EXISTS `ledger_key` VARCHAR(128) NULL',
            'CREATE UNIQUE INDEX IF NOT EXISTS `uq_gov_budget_tx_key` ON `pf_gov_budget_transactions` (`idem_key`)',
            'CREATE INDEX IF NOT EXISTS `idx_gov_budget_tx_state` ON `pf_gov_budget_transactions` (`state`)',
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
