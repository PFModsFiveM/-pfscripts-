-- Injury records: versioned tables (pfm-core migrations) and the queries the injury system uses.
-- (The tables used to be created by a net event any client could trigger, and the treatment log's
-- foreign key had no ON DELETE rule, so clearing a treated patient's injuries failed.)

local T_INJURIES = Config.Database.PlayerInjuries
local T_TREATMENTS = Config.Database.PlayerTreatmentLog

InjuryDB = InjuryDB or {}
local DB = InjuryDB

DB.Migrations = {
    {
        version = 1,
        name = 'injury records, treatment log, health snapshots',
        up = function()
            MySQL.query.await(([[
                CREATE TABLE IF NOT EXISTS `%s` (
                    `id` INT AUTO_INCREMENT PRIMARY KEY,
                    `citizen_id` VARCHAR(50) NOT NULL,
                    `injury_type` VARCHAR(50) NOT NULL,
                    `severity` VARCHAR(20) NOT NULL,
                    `body_zone` VARCHAR(50) NOT NULL,
                    `health_percentage` INT DEFAULT 0,
                    `weapon` VARCHAR(50),
                    `recorded_by` VARCHAR(50),
                    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    `deleted_at` TIMESTAMP NULL,
                    INDEX `idx_citizen_id` (`citizen_id`),
                    INDEX `idx_created_at` (`created_at`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T_INJURIES))
            MySQL.query.await(([[
                CREATE TABLE IF NOT EXISTS `%s` (
                    `id` INT AUTO_INCREMENT PRIMARY KEY,
                    `citizen_id` VARCHAR(50) NOT NULL,
                    `treatment_type` VARCHAR(50) NOT NULL,
                    `treated_by` VARCHAR(50) NOT NULL,
                    `injury_id` INT NULL,
                    `duration` INT,
                    `effectiveness` INT DEFAULT 100,
                    `notes` TEXT,
                    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    `deleted_at` TIMESTAMP NULL,
                    INDEX `idx_citizen_id` (`citizen_id`),
                    INDEX `idx_treated_by` (`treated_by`),
                    FOREIGN KEY (`injury_id`) REFERENCES `%s`(`id`) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]):format(T_TREATMENTS, T_INJURIES))
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS `player_health_snapshot` (
                    `id` INT AUTO_INCREMENT PRIMARY KEY,
                    `citizen_id` VARCHAR(50) NOT NULL,
                    `health` INT,
                    `armor` INT,
                    `is_unconscious` BOOLEAN DEFAULT FALSE,
                    `last_damage_weapon` VARCHAR(50),
                    `last_damage_zone` VARCHAR(50),
                    `snapshot_taken_by` VARCHAR(50),
                    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX `idx_citizen_id` (`citizen_id`),
                    INDEX `idx_created_at` (`created_at`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]])
        end,
    },
}

DB.ready = false
function DB.Start()
    local ok, err = RunMigrations('pf-ambulancejob', DB.Migrations)
    if not ok then
        PFAmbulance.LogError('injury tables not ready: ' .. tostring(err))
        return false
    end
    DB.ready = true
    return true
end

function GetCitizenInjuries(citizenId)
    if not DB.ready then return {} end
    return MySQL.query.await(('SELECT id, injury_type, severity, body_zone, health_percentage, weapon, recorded_by, created_at FROM `%s` WHERE citizen_id = ? ORDER BY id DESC LIMIT 50'):format(T_INJURIES), { citizenId }) or {}
end

--- Stores a checked injury (PFAmbulance.CleanInjury) and keeps only the latest MaxStoredPerCitizen.
function AddInjury(citizenId, injury, recordedBy)
    if not DB.ready then return nil end
    local id = MySQL.insert.await(('INSERT INTO `%s` (citizen_id, injury_type, severity, body_zone, health_percentage, weapon, recorded_by) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(T_INJURIES),
        { citizenId, injury.type, injury.severity, injury.zone, injury.health, injury.weapon, recordedBy or 'damage_detection' })
    local keep = tonumber(Config.DamageTracking.MaxStoredPerCitizen) or 50
    local cutoff = MySQL.scalar.await(('SELECT id FROM `%s` WHERE citizen_id = ? ORDER BY id DESC LIMIT 1 OFFSET ?'):format(T_INJURIES), { citizenId, keep })
    if cutoff then
        MySQL.update.await(('DELETE FROM `%s` WHERE citizen_id = ? AND id <= ?'):format(T_INJURIES), { citizenId, cutoff })
    end
    return id
end

--- Removes the injuries of the given types up to maxSeverity; returns how many were removed.
function RemoveTreatedInjuries(citizenId, types, maxSeverity)
    if not DB.ready then return 0 end
    local maxRank = PFAmbulance.SeverityRank(maxSeverity) or 0
    local allowed, placeholders = {}, {}
    for _, s in ipairs(Config.InjurySeverities) do
        if PFAmbulance.SeverityRank(s) <= maxRank then allowed[#allowed + 1] = s end
    end
    local typeList = {}
    for t in pairs(types) do typeList[#typeList + 1] = t end
    if #typeList == 0 or #allowed == 0 then return 0 end
    local params = { citizenId }
    for _, t in ipairs(typeList) do params[#params + 1] = t; placeholders[#placeholders + 1] = '?' end
    local sevHolders = {}
    for _, s in ipairs(allowed) do params[#params + 1] = s; sevHolders[#sevHolders + 1] = '?' end
    return MySQL.update.await(('DELETE FROM `%s` WHERE citizen_id = ? AND injury_type IN (%s) AND severity IN (%s)'):format(
        T_INJURIES, table.concat(placeholders, ','), table.concat(sevHolders, ',')), params) or 0
end

function ClearCitizenInjuries(citizenId)
    if not DB.ready then return 0 end
    return MySQL.update.await(('DELETE FROM `%s` WHERE citizen_id = ?'):format(T_INJURIES), { citizenId }) or 0
end

function LogTreatment(citizenId, treatment)
    if not DB.ready then return nil end
    return MySQL.insert.await(('INSERT INTO `%s` (citizen_id, treatment_type, treated_by, duration, notes) VALUES (?, ?, ?, ?, ?)'):format(T_TREATMENTS),
        { citizenId, treatment.type, treatment.treatedBy or 'system', treatment.duration or 0, treatment.notes })
end

CreateThread(function()
    DB.Start()
end)
