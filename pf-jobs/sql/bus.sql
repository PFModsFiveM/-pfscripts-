-- Bus Job System - Database Schema
-- Import this file into your FiveM server database

-- ============================================================================
-- BUS PLAYER STATISTICS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS `bus_stats` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizen_id` VARCHAR(50) UNIQUE NOT NULL,
    `total_passengers` INT DEFAULT 0 COMMENT 'Total passengers delivered',
    `total_earnings` INT DEFAULT 0 COMMENT 'Total money earned',
    `routes_completed` INT DEFAULT 0 COMMENT 'Total routes completed',
    `total_time` INT DEFAULT 0 COMMENT 'Total driving time in minutes',
    `average_rating` FLOAT DEFAULT 5.0 COMMENT 'Average passenger rating',
    `best_rating` FLOAT DEFAULT 5.0 COMMENT 'Best single route rating',
    `on_time_count` INT DEFAULT 0 COMMENT 'Number of on-time deliveries',
    `current_level` INT DEFAULT 1 COMMENT 'Current driver level (1-5)',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `last_updated` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_citizen_id` (`citizen_id`),
    INDEX `idx_level` (`current_level`),
    INDEX `idx_routes_completed` (`routes_completed`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Tracks bus driver statistics and progression';

-- ============================================================================
-- BUS ROUTES HISTORY LOG TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS `bus_routes_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizen_id` VARCHAR(50) NOT NULL,
    `route_id` INT NOT NULL COMMENT '1-5 for available routes',
    `distance` FLOAT DEFAULT 0 COMMENT 'Miles traveled',
    `fare_earned` INT DEFAULT 0 COMMENT 'Money earned this route',
    `passengers_delivered` INT DEFAULT 0 COMMENT 'Passengers delivered',
    `complete_time` INT DEFAULT 0 COMMENT 'Time to complete in seconds',
    `rating` FLOAT DEFAULT 5.0 COMMENT 'Passenger rating for this route',
    `on_time` TINYINT DEFAULT 0 COMMENT '1 if completed on-time, 0 otherwise',
    `completed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizen_id` (`citizen_id`),
    INDEX `idx_route_id` (`route_id`),
    INDEX `idx_completed_at` (`completed_at`),
    FOREIGN KEY (`citizen_id`) REFERENCES `bus_stats` (`citizen_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Historical log of all bus routes completed';

-- ============================================================================
-- SAMPLE DATA (Optional - remove if not needed)
-- ============================================================================

-- Insert sample player if testing
-- INSERT INTO `bus_stats` (`citizen_id`, `total_passengers`, `total_earnings`, `routes_completed`, `total_time`, `average_rating`, `best_rating`, `on_time_count`, `current_level`) 
-- VALUES ('ABC12345678', 0, 0, 0, 0, 5.0, 5.0, 0, 1);

-- ============================================================================
-- USEFUL QUERIES
-- ============================================================================

-- Get top 10 earners
-- SELECT citizen_id, total_earnings, routes_completed FROM bus_stats ORDER BY total_earnings DESC LIMIT 10;

-- Get average earnings per route
-- SELECT citizen_id, ROUND(total_earnings / routes_completed, 2) as avg_per_route FROM bus_stats WHERE routes_completed > 0 ORDER BY avg_per_route DESC LIMIT 10;

-- Get highest rated drivers
-- SELECT citizen_id, average_rating, routes_completed FROM bus_stats WHERE routes_completed >= 5 ORDER BY average_rating DESC LIMIT 10;

-- Get on-time delivery rate
-- SELECT citizen_id, on_time_count, routes_completed, ROUND((on_time_count / routes_completed) * 100, 1) as on_time_percent FROM bus_stats WHERE routes_completed > 0 ORDER BY on_time_percent DESC LIMIT 10;