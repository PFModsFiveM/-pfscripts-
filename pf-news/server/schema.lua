-- pf-news tables (pf_schema_migrations, resource 'pf-news'). Times the code compares are written
-- with FROM_UNIXTIME(os.time()) and read back with UNIX_TIMESTAMP(), so every window uses one clock.
--
-- pf_news_articles   every article: reporter stories and City Desk articles (auto = 1)
-- pf_news_events     one row per city event handled: the exactly-once record (event_id is the
--                    pf-services event id) and the event snapshot a digest is rebuilt from
-- pf_news_leads      events the newsroom may cover; claimed by one reporter, covered by an article
-- pf_news_views      one row per (article, citizen): the view counter counts each reader once
-- pf_news_ads        paid ad slots (ledger key pf-news:ad:<id>, refund key pf-news:ad:<id>:refund)
-- pf_news_payouts    one reporter bonus per article (ledger key pf-news:bonus:<article id>)

PFNews = PFNews or {}

PFNews.Migrations = {
    {
        version = 1,
        name = 'articles, events, leads, views, ads, payouts',
        up = {
            [[CREATE TABLE IF NOT EXISTS `pf_news_articles` (
                `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `title` VARCHAR(160) NOT NULL,
                `summary` VARCHAR(400) NULL,
                `body` MEDIUMTEXT NULL,
                `category` VARCHAR(24) NOT NULL DEFAULT 'city',
                `images` TEXT NULL,
                `author_cid` VARCHAR(50) NULL,
                `author_name` VARCHAR(100) NOT NULL DEFAULT 'City Desk',
                `status` VARCHAR(12) NOT NULL DEFAULT 'draft',
                `auto` TINYINT(1) NOT NULL DEFAULT 0,
                `event_id` BIGINT UNSIGNED NULL,
                `preset_id` VARCHAR(96) NULL,
                `group_key` VARCHAR(96) NULL,
                `group_until` TIMESTAMP NULL DEFAULT NULL,
                `breaking` TINYINT(1) NOT NULL DEFAULT 0,
                `pinned` TINYINT(1) NOT NULL DEFAULT 0,
                `views` INT UNSIGNED NOT NULL DEFAULT 0,
                `lead_id` INT UNSIGNED NULL,
                `review_note` VARCHAR(400) NULL,
                `reviewed_by` VARCHAR(50) NULL,
                `reviewed_name` VARCHAR(100) NULL,
                `retract_note` VARCHAR(400) NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NULL DEFAULT NULL,
                `submitted_at` TIMESTAMP NULL DEFAULT NULL,
                `published_at` TIMESTAMP NULL DEFAULT NULL,
                `retracted_at` TIMESTAMP NULL DEFAULT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_event` (`event_id`),
                KEY `idx_status_pub` (`status`, `published_at`),
                KEY `idx_author` (`author_cid`, `status`),
                KEY `idx_group` (`group_key`, `status`, `group_until`),
                KEY `idx_category` (`category`, `status`, `published_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_news_events` (
                `event_id` BIGINT UNSIGNED NOT NULL,
                `kind` VARCHAR(64) NOT NULL,
                `mode` VARCHAR(8) NOT NULL,
                `payload` TEXT NULL,
                `article_id` INT UNSIGNED NULL,
                `lead_id` INT UNSIGNED NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`event_id`),
                KEY `idx_article` (`article_id`),
                KEY `idx_lead` (`lead_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_news_leads` (
                `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `event_id` BIGINT UNSIGNED NULL,
                `kind` VARCHAR(64) NOT NULL,
                `category` VARCHAR(24) NOT NULL DEFAULT 'city',
                `title` VARCHAR(160) NOT NULL,
                `details` TEXT NULL,
                `district` VARCHAR(64) NULL,
                `x` FLOAT NULL, `y` FLOAT NULL, `z` FLOAT NULL,
                `status` VARCHAR(12) NOT NULL DEFAULT 'open',
                `hits` INT UNSIGNED NOT NULL DEFAULT 1,
                `claimed_cid` VARCHAR(50) NULL,
                `claimed_name` VARCHAR(100) NULL,
                `claimed_at` TIMESTAMP NULL DEFAULT NULL,
                `article_id` INT UNSIGNED NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NULL DEFAULT NULL,
                `expires_at` TIMESTAMP NULL DEFAULT NULL,
                `covered_at` TIMESTAMP NULL DEFAULT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_event` (`event_id`),
                KEY `idx_status` (`status`, `expires_at`),
                KEY `idx_merge` (`kind`, `status`, `created_at`),
                KEY `idx_claimed` (`claimed_cid`, `status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_news_views` (
                `article_id` INT UNSIGNED NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `viewed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`article_id`, `citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_news_ads` (
                `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `business_id` VARCHAR(100) NOT NULL,
                `business_name` VARCHAR(120) NOT NULL,
                `account_ref` VARCHAR(96) NOT NULL,
                `buyer_cid` VARCHAR(50) NOT NULL,
                `buyer_name` VARCHAR(100) NULL,
                `text` VARCHAR(400) NOT NULL,
                `image_url` VARCHAR(320) NULL,
                `duration_id` VARCHAR(16) NOT NULL,
                `hours` INT UNSIGNED NOT NULL,
                `price` DECIMAL(12,2) NOT NULL,
                `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
                `paid_tx` VARCHAR(40) NULL,
                `error` VARCHAR(64) NULL,
                `refund_state` VARCHAR(12) NOT NULL DEFAULT 'none',
                `refund_tx` VARCHAR(40) NULL,
                `refund_attempts` INT UNSIGNED NOT NULL DEFAULT 0,
                `reject_note` VARCHAR(400) NULL,
                `rejected_by` VARCHAR(50) NULL,
                `rejected_name` VARCHAR(100) NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `starts_at` TIMESTAMP NULL DEFAULT NULL,
                `ends_at` TIMESTAMP NULL DEFAULT NULL,
                `rejected_at` TIMESTAMP NULL DEFAULT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_status_end` (`status`, `ends_at`),
                KEY `idx_business` (`business_id`, `status`),
                KEY `idx_refund` (`refund_state`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_news_payouts` (
                `article_id` INT UNSIGNED NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `amount` DECIMAL(12,2) NOT NULL,
                `day` VARCHAR(10) NOT NULL,
                `lead_bonus` TINYINT(1) NOT NULL DEFAULT 0,
                `state` VARCHAR(12) NOT NULL DEFAULT 'pending',
                `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
                `error` VARCHAR(64) NULL,
                `tx_id` VARCHAR(40) NULL,
                `due_at` TIMESTAMP NULL DEFAULT NULL,
                `paid_at` TIMESTAMP NULL DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`article_id`),
                KEY `idx_cid_day` (`citizenid`, `day`),
                KEY `idx_state_due` (`state`, `due_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}
