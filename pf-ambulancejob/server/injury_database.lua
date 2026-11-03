-- Injury records (legacy layer): the queries the old injury system uses.
-- (The tables used to be created by a net event any client could trigger, and the treatment log's
-- foreign key had no ON DELETE rule, so clearing a treated patient's injuries failed.)

local T_INJURIES = Config.Database.PlayerInjuries
local T_TREATMENTS = Config.Database.PlayerTreatmentLog

InjuryDB = InjuryDB or {}
local DB = InjuryDB

-- The table definitions (migration v1) moved to server/medical/schema.lua, which owns the
-- 'pf-ambulancejob' migration key; these legacy functions keep working for their callers.
local function ready()
    return PFMed ~= nil and PFMed.Schema ~= nil and PFMed.Schema.Ready()
end

--- Legacy entry point: applies the resource's migrations (all versions) through the schema module.
function DB.Start()
    if not (PFMed and PFMed.Schema) then
        PFAmbulance.LogError('injury tables not ready: schema module not loaded')
        return false
    end
    local ok, err = PFMed.Schema.Start()
    if not ok then
        PFAmbulance.LogError('injury tables not ready: ' .. tostring(err))
        return false
    end
    return true
end

function GetCitizenInjuries(citizenId)
    if not ready() then return {} end
    return MySQL.query.await(('SELECT id, injury_type, severity, body_zone, health_percentage, weapon, recorded_by, created_at FROM `%s` WHERE citizen_id = ? ORDER BY id DESC LIMIT 50'):format(T_INJURIES), { citizenId }) or {}
end

--- Stores a checked injury (PFAmbulance.CleanInjury) and keeps only the latest MaxStoredPerCitizen.
function AddInjury(citizenId, injury, recordedBy)
    if not ready() then return nil end
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
    if not ready() then return 0 end
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
    if not ready() then return 0 end
    return MySQL.update.await(('DELETE FROM `%s` WHERE citizen_id = ?'):format(T_INJURIES), { citizenId }) or 0
end

function LogTreatment(citizenId, treatment)
    if not ready() then return nil end
    return MySQL.insert.await(('INSERT INTO `%s` (citizen_id, treatment_type, treated_by, duration, notes) VALUES (?, ?, ?, ?, ?)'):format(T_TREATMENTS),
        { citizenId, treatment.type, treatment.treatedBy or 'system', treatment.duration or 0, treatment.notes })
end
