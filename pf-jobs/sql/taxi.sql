-- Taxi Stats Table
CREATE TABLE IF NOT EXISTS `taxi_stats` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizen_id` VARCHAR(50) UNIQUE NOT NULL,
    `total_miles` FLOAT DEFAULT 0,
    `total_earnings` INT DEFAULT 0,
    `total_rides` INT DEFAULT 0,
    `total_time` INT DEFAULT 0,
    `average_rating` FLOAT DEFAULT 5.0,
    `streak_count` INT DEFAULT 0,
    `best_streak` INT DEFAULT 0,
    `current_level` INT DEFAULT 1,
    `last_ride` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_citizen_id` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Taxi Rides Log Table (for historical tracking)
CREATE TABLE IF NOT EXISTS `taxi_rides_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `ride_id` VARCHAR(50) UNIQUE,
    `citizen_id` VARCHAR(50),
    `start_coords` VARCHAR(100),
    `end_coords` VARCHAR(100),
    `distance` FLOAT,
    `fare_earned` INT,
    `ride_type` VARCHAR(20),
    `is_private_vehicle` BOOLEAN DEFAULT FALSE,
    `vehicle_health` INT,
    `duration_minutes` INT,
    `passenger_rating` FLOAT DEFAULT 5.0,
    `streak_bonus_applied` INT DEFAULT 0,
    `completed_clean` BOOLEAN DEFAULT TRUE,
    `completed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizen_id` (`citizen_id`),
    INDEX `idx_completed_at` (`completed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
