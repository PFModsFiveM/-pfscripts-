-- pf-stores schema
-- Run this in your server database (oxmysql / MariaDB / MySQL).

CREATE TABLE IF NOT EXISTS `pf_stores` (
  `store_id` VARCHAR(64) NOT NULL,
  `label` VARCHAR(128) NOT NULL,
  `store_type` VARCHAR(32) NOT NULL,
  `owner_citizenid` VARCHAR(64) NULL,
  `purchased_at` BIGINT NULL,
  `balance` DECIMAL(14,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Existing installs: the resource also detects and adds this column automatically at runtime.
-- ALTER TABLE `pf_stores` ADD COLUMN `balance` DECIMAL(14,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS `pf_store_supply_stock` (
  `store_id` VARCHAR(64) NOT NULL,
  `supply_name` VARCHAR(128) NOT NULL,
  `stock_cases` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`store_id`, `supply_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Owner price overrides for storefront items (absent row = config default price).
CREATE TABLE IF NOT EXISTS `pf_store_prices` (
  `store_id` VARCHAR(64) NOT NULL,
  `item` VARCHAR(128) NOT NULL,
  `price` DECIMAL(12,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (`store_id`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Storefront sales ledger (one row per line item; '__withdraw__' rows are owner withdrawals).
CREATE TABLE IF NOT EXISTS `pf_store_ledger` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `store_id` VARCHAR(64) NOT NULL,
  `item` VARCHAR(128) NOT NULL,
  `amount` INT NOT NULL DEFAULT 0,
  `unit_price` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `total` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `tax` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `buyer_citizenid` VARCHAR(64) NULL,
  `created_at` BIGINT NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_store` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_store_supply_orders` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `store_id` VARCHAR(64) NOT NULL,
  `owner_citizenid` VARCHAR(64) NOT NULL,
  `method` VARCHAR(16) NOT NULL,
  `status` VARCHAR(32) NOT NULL,
  `total` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `items_json` LONGTEXT NOT NULL,
  `created_at` BIGINT NOT NULL,
  `delivered_at` BIGINT NULL,
  `external_contract_id` VARCHAR(64) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_store_id` (`store_id`),
  KEY `idx_owner` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
