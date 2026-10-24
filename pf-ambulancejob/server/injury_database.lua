-- Initialize database tables
local function initializeDatabase()
    -- Player Injuries Table
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS player_injuries (
            id INT AUTO_INCREMENT PRIMARY KEY,
            citizen_id VARCHAR(50) NOT NULL,
            injury_type VARCHAR(50) NOT NULL,
            severity VARCHAR(20) NOT NULL,
            body_zone VARCHAR(50) NOT NULL,
            health_percentage INT DEFAULT 0,
            weapon VARCHAR(50),
            recorded_by VARCHAR(50),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_citizen_id (citizen_id),
            INDEX idx_created_at (created_at)
        )
    ]])
    
    -- Player Treatment Log Table
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS player_treatment_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            citizen_id VARCHAR(50) NOT NULL,
            treatment_type VARCHAR(50) NOT NULL,
            treated_by VARCHAR(50) NOT NULL,
            injury_id INT,
            duration INT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_citizen_id (citizen_id),
            INDEX idx_treated_by (treated_by),
            FOREIGN KEY (injury_id) REFERENCES player_injuries(id)
        )
    ]])
    
    -- Player Health Snapshot Table (for tracking health history)
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS player_health_snapshot (
            id INT AUTO_INCREMENT PRIMARY KEY,
            citizen_id VARCHAR(50) NOT NULL,
            health INT,
            armor INT,
            stress INT,
            hunger INT,
            thirst INT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_citizen_id (citizen_id),
            INDEX idx_created_at (created_at)
        )
    ]])
    
    print("^2[pf-ambulancejob]^7 Database tables initialized")
end

-- Register event to initialize database
RegisterServerEvent('pf-ambulancejob:initializeDatabase')
AddEventHandler('pf-ambulancejob:initializeDatabase', initializeDatabase)

-- Function to get all injuries for a citizen
function GetCitizenInjuries(citizenId)
    return MySQL.Sync.fetchAll(
        'SELECT * FROM ' .. Config.Database.PlayerInjuries .. ' WHERE citizen_id = ? ORDER BY created_at DESC LIMIT 50',
        {citizenId}
    )
end

-- Function to add injury
function AddInjury(citizenId, injuryData)
    local result = MySQL.Sync.fetchAll(
        'INSERT INTO ' .. Config.Database.PlayerInjuries .. 
        ' (citizen_id, injury_type, severity, body_zone, health_percentage, weapon, recorded_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {
            citizenId,
            injuryData.type or 'unknown',
            injuryData.severity or 'moderate',
            injuryData.zone or 'unknown',
            injuryData.health or 50,
            injuryData.weapon or 'unknown',
            injuryData.recordedBy or 'system'
        }
    )
    return result
end

-- Function to remove injury
function RemoveInjury(injuryId)
    return MySQL.Sync.execute(
        'DELETE FROM ' .. Config.Database.PlayerInjuries .. ' WHERE id = ?',
        {injuryId}
    )
end

-- Function to clear all injuries for citizen
function ClearCitizenInjuries(citizenId)
    return MySQL.Sync.execute(
        'DELETE FROM ' .. Config.Database.PlayerInjuries .. ' WHERE citizen_id = ?',
        {citizenId}
    )
end

-- Function to log treatment
function LogTreatment(citizenId, treatmentData)
    return MySQL.Sync.fetchAll(
        'INSERT INTO ' .. Config.Database.PlayerTreatmentLog .. 
        ' (citizen_id, treatment_type, treated_by, injury_id, duration) VALUES (?, ?, ?, ?, ?)',
        {
            citizenId,
            treatmentData.type or 'unknown',
            treatmentData.treatedBy or 'system',
            treatmentData.injuryId or nil,
            treatmentData.duration or 0
        }
    )
end

-- Initialize on resource start
initializeDatabase()
