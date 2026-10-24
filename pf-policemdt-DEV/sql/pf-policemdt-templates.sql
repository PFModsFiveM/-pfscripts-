CREATE TABLE IF NOT EXISTS `pf_mdt_templates` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(120) NOT NULL,
  `body_html` LONGTEXT NOT NULL,
  `visibility` VARCHAR(16) NOT NULL DEFAULT 'private',
  `allowed_grades` TEXT NULL,
  `allowed_officers` TEXT NULL,
  `author_cid` VARCHAR(50) NOT NULL,
  `author_name` VARCHAR(120) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Example template
INSERT INTO `pf_mdt_templates` (`title`, `body_html`, `visibility`, `allowed_grades`, `allowed_officers`, `author_cid`, `author_name`) VALUES
('Traffic Stop Report', '<h2>Traffic Stop Details</h2><p><strong>Date &amp; Time:</strong> ___________</p><p><strong>Location:</strong> ___________</p><p><strong>Vehicle:</strong> ___________</p><p><strong>Plate:</strong> ___________</p><p><strong>Driver:</strong> ___________</p><br><h3>Reason for Stop</h3><p>___________</p><br><h3>Actions Taken</h3><ul><li>Warning issued</li><li>Citation issued</li><li>Arrest made</li></ul><br><h3>Additional Notes</h3><p>___________</p>', 'public', '[]', '[]', 'SYSTEM', 'System Generated');

