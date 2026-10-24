-- =============================================
-- OUTFIT BAG DATABASE SETUP
-- =============================================

-- Create the outfit storage table
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
-- VERIFICATION QUERIES
-- =============================================

-- Check if outfit table was created:
SHOW TABLES LIKE 'outfitbag_outfits';

-- View all stored outfits:
SELECT bag_id, outfit_name, created_at FROM outfitbag_outfits ORDER BY created_at DESC;
