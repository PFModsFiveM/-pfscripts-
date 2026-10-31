-- pf-citizen tables (pf_schema_migrations, resource 'pf-citizen').
--
-- Mail lives in the phone's own `player_mails` table, so the phone, the tablet and the computer show
-- one mailbox. The phone's columns stay as they are (sender, subject, message, read, mailid, date,
-- button); the columns added here all have defaults, so the phone's own inserts keep working and its
-- rows land in the inbox.

PFCitizen = PFCitizen or {}

PFCitizen.Migrations = {
    {
        version = 1,
        name = 'one mailbox, documents, calendar, bill history',
        up = {
            -- the phone's table, for servers that never imported qb-phone.sql
            [[CREATE TABLE IF NOT EXISTS `player_mails` (
                `id` INT(11) NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(50) DEFAULT NULL,
                `sender` VARCHAR(80) DEFAULT NULL,
                `subject` VARCHAR(128) DEFAULT NULL,
                `message` TEXT DEFAULT NULL,
                `read` TINYINT(4) DEFAULT 0,
                `mailid` INT(11) DEFAULT NULL,
                `date` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                `button` TEXT DEFAULT NULL,
                PRIMARY KEY (`id`),
                KEY `citizenid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- the phone stored at most 50 characters; mail from other resources is longer
            'ALTER TABLE `player_mails` MODIFY `sender` VARCHAR(80) DEFAULT NULL, MODIFY `subject` VARCHAR(128) DEFAULT NULL',
            [[ALTER TABLE `player_mails`
                ADD COLUMN IF NOT EXISTS `folder` VARCHAR(12) NOT NULL DEFAULT 'inbox',
                ADD COLUMN IF NOT EXISTS `thread` VARCHAR(40) NULL,
                ADD COLUMN IF NOT EXISTS `sender_type` VARCHAR(16) NOT NULL DEFAULT 'system',
                ADD COLUMN IF NOT EXISTS `sender_cid` VARCHAR(50) NULL,
                ADD COLUMN IF NOT EXISTS `sender_address` VARCHAR(120) NULL,
                ADD COLUMN IF NOT EXISTS `recipients` VARCHAR(400) NULL,
                ADD COLUMN IF NOT EXISTS `attachments` TEXT NULL,
                ADD COLUMN IF NOT EXISTS `ref` VARCHAR(100) NULL,
                ADD COLUMN IF NOT EXISTS `prev_folder` VARCHAR(12) NULL,
                ADD COLUMN IF NOT EXISTS `moved_at` TIMESTAMP NULL]],
            'ALTER TABLE `player_mails` ADD INDEX IF NOT EXISTS `idx_mail_box` (`citizenid`, `folder`, `id`)',
            'ALTER TABLE `player_mails` ADD INDEX IF NOT EXISTS `idx_mail_thread` (`citizenid`, `thread`)',
            'ALTER TABLE `player_mails` ADD INDEX IF NOT EXISTS `idx_mail_ref` (`ref`)',
            -- one copy of a broadcast (an announcement) per citizen; NULL refs do not collide
            'ALTER TABLE `player_mails` ADD UNIQUE INDEX IF NOT EXISTS `uq_mail_ref` (`citizenid`, `ref`)',
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_mail_broadcasts` (
                `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `ref` VARCHAR(100) NOT NULL,
                `sender` VARCHAR(80) NOT NULL,
                `sender_type` VARCHAR(16) NOT NULL DEFAULT 'government',
                `subject` VARCHAR(128) NOT NULL,
                `message` TEXT NOT NULL,
                `active` TINYINT(1) NOT NULL DEFAULT 1,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `expires_at` TIMESTAMP NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_broadcast_ref` (`ref`),
                KEY `idx_broadcast_active` (`active`, `expires_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- who already got a broadcast, so a citizen who deleted it does not get it again
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_broadcast_receipts` (
                `broadcast_id` INT UNSIGNED NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `delivered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`broadcast_id`, `citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_documents` (
                `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                `owner_cid` VARCHAR(50) NOT NULL,
                `title` VARCHAR(160) NOT NULL,
                `body` MEDIUMTEXT NOT NULL,
                `copied_from` BIGINT UNSIGNED NULL,
                `locked` TINYINT(1) NOT NULL DEFAULT 0,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `deleted_at` TIMESTAMP NULL,
                PRIMARY KEY (`id`),
                KEY `idx_doc_owner` (`owner_cid`, `deleted_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_document_shares` (
                `document_id` BIGINT UNSIGNED NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `shared_by` VARCHAR(50) NOT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`document_id`, `citizenid`),
                KEY `idx_share_cid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- a signature stamps the text it was given for: the fingerprint is SHA-256 of title and body
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_document_signatures` (
                `document_id` BIGINT UNSIGNED NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `name` VARCHAR(100) NOT NULL,
                `fingerprint` CHAR(64) NOT NULL,
                `signed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`document_id`, `citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_events` (
                `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                `scope` VARCHAR(12) NOT NULL,
                `owner` VARCHAR(100) NOT NULL,
                `title` VARCHAR(120) NOT NULL,
                `description` TEXT NULL,
                `location` VARCHAR(120) NULL,
                `starts_at` DATETIME NOT NULL,
                `ends_at` DATETIME NULL,
                `remind_minutes` INT NOT NULL DEFAULT 0,
                `created_by` VARCHAR(50) NOT NULL,
                `created_by_name` VARCHAR(100) NULL,
                `cancelled` TINYINT(1) NOT NULL DEFAULT 0,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_event_owner` (`scope`, `owner`, `starts_at`),
                KEY `idx_event_start` (`starts_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- "remind me" on a city or business event
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_event_subs` (
                `event_id` BIGINT UNSIGNED NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`event_id`, `citizenid`),
                KEY `idx_sub_cid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_event_reminders` (
                `event_id` BIGINT UNSIGNED NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `sent_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`event_id`, `citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- bills whose own system forgets them once settled (phone invoices are deleted when paid)
            [[CREATE TABLE IF NOT EXISTS `pf_citizen_bill_history` (
                `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(50) NOT NULL,
                `source` VARCHAR(16) NOT NULL,
                `ref` VARCHAR(64) NOT NULL,
                `title` VARCHAR(160) NOT NULL,
                `counterparty` VARCHAR(100) NULL,
                `amount` DECIMAL(12,2) NOT NULL,
                `outcome` VARCHAR(12) NOT NULL DEFAULT 'paid',
                `settled_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_bill_history` (`source`, `ref`, `citizenid`),
                KEY `idx_bill_history_cid` (`citizenid`, `settled_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}
