-- Garbage Job SQL Schema

-- Player XP and Level for Garbage job
CREATE TABLE IF NOT EXISTS pf_garbage_xp (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(64) NOT NULL,
    xp INT NOT NULL DEFAULT 0,
    level INT NOT NULL DEFAULT 1,
    last_update TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_cid (citizenid)
);

-- Player upgrades for Garbage job (JSON bag)
CREATE TABLE IF NOT EXISTS pf_garbage_upgrades (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(64) NOT NULL,
    upgrades JSON NOT NULL,
    last_update TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_cid (citizenid)
);

-- Optional: per-session stats (bags deposited per session)
CREATE TABLE IF NOT EXISTS pf_garbage_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(64) NOT NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP NULL,
    bags_deposited INT NOT NULL DEFAULT 0,
    xp_earned INT NOT NULL DEFAULT 0
);
