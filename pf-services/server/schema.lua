-- pf-services tables (pf_schema_migrations, resource 'pf-services').

PFServices = PFServices or {}

PFServices.Migrations = {
    {
        version = 1,
        name = 'city events timeline and service requests',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_city_events` (
                `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                `kind` VARCHAR(64) NOT NULL,
                `category` VARCHAR(32) NOT NULL DEFAULT 'city',
                `news_mode` VARCHAR(8) NOT NULL DEFAULT 'none',
                `title` VARCHAR(160) NULL,
                `data` LONGTEXT NULL,
                `district` VARCHAR(64) NULL,
                `x` FLOAT NULL, `y` FLOAT NULL, `z` FLOAT NULL,
                `source_resource` VARCHAR(64) NULL,
                `actor_cid` VARCHAR(50) NULL,
                `dedupe_key` VARCHAR(160) NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_kind_time` (`kind`, `created_at`),
                KEY `idx_time` (`created_at`),
                KEY `idx_dedupe` (`dedupe_key`, `created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_service_requests` (
                `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                `kind` VARCHAR(64) NOT NULL,
                `job` VARCHAR(50) NOT NULL,
                `status` VARCHAR(16) NOT NULL DEFAULT 'open',
                `title` VARCHAR(160) NOT NULL,
                `details` TEXT NULL,
                `x` FLOAT NULL, `y` FLOAT NULL, `z` FLOAT NULL,
                `plate` VARCHAR(16) NULL,
                `ref_type` VARCHAR(32) NULL,
                `ref_id` VARCHAR(64) NULL,
                `from_type` VARCHAR(16) NOT NULL DEFAULT 'system',
                `from_id` VARCHAR(64) NULL,
                `from_name` VARCHAR(100) NULL,
                `requester_cid` VARCHAR(50) NULL,
                `assignee_cid` VARCHAR(50) NULL,
                `assignee_name` VARCHAR(100) NULL,
                `payer` VARCHAR(80) NOT NULL DEFAULT 'none',
                `reward` DECIMAL(12,2) NOT NULL DEFAULT 0,
                `escrow_state` VARCHAR(12) NOT NULL DEFAULT 'none',
                `meta` LONGTEXT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `accepted_at` TIMESTAMP NULL,
                `closed_at` TIMESTAMP NULL,
                `expires_at` TIMESTAMP NULL,
                `close_reason` VARCHAR(64) NULL,
                PRIMARY KEY (`id`),
                KEY `idx_job_status` (`job`, `status`),
                KEY `idx_assignee` (`assignee_cid`, `status`),
                KEY `idx_requester` (`requester_cid`, `status`),
                KEY `idx_ref` (`ref_type`, `ref_id`, `status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}
