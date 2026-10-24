-- =============================================
-- OUTFIT BAG - ESX SETUP
-- =============================================

-- =============================================
-- 1. OUTFIT STORAGE TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS `outfitbag_outfits` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `bag_id` varchar(255) NOT NULL,
  `outfit_name` varchar(100) NOT NULL,
  `outfit_data` longtext NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `bag_id` (`bag_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- 2. ESX ITEM REGISTRATION
-- =============================================
-- Add outfit bag item to ESX items table
INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) 
VALUES ('outfitbag', 'Outfit Bag', 0, 0, 1)
ON DUPLICATE KEY UPDATE 
  `label` = 'Outfit Bag',
  `weight` = 0,
  `rare` = 0,
  `can_remove` = 1;

-- =============================================
-- VERIFICATION QUERIES
-- =============================================

-- Check if outfit table was created:
SHOW TABLES LIKE 'outfitbag_outfits';

-- Check if item was added:
SELECT * FROM items WHERE name = 'outfitbag';

-- View all stored outfits:
SELECT bag_id, outfit_name, created_at FROM outfitbag_outfits ORDER BY created_at DESC;
