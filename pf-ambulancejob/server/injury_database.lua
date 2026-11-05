-- Injury records (legacy layer): the functions the old injury system calls, now forwarders onto the
-- medical engine. Since batch 16 injuries are created by the server (server/medical/ingest.lua) and
-- the legacy rows were imported once (migration v4); player_injuries is frozen history. Rows that
-- have no engine copy (written by AddInjury after the import) are still listed and removed here.
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

-- engine injury -> the legacy shape (scan display, field treatment)
local LEGACY_TYPE = {
    gunshot = 'gunshot_wound', laceration = 'laceration', stab = 'laceration', bruising = 'blunt_trauma', crush = 'blunt_trauma',
    dislocation = 'blunt_trauma', sprain = 'blunt_trauma', burn = 'burn', electrical = 'electrical_burn', fracture = 'fracture',
    respiratory = 'respiratory', drowning = 'respiratory',
}
local LEGACY_SEVERITY = { 'minor', 'moderate', 'severe', 'severe', 'critical' }
-- what a legacy field treatment sets on the engine injury it stabilises
local TREATMENT_FLAGS = {
    gunshot_wound = { pressure = true }, laceration = { pressure = true }, fracture = { splinted = true }, blunt_trauma = { cooled = true },
    burn = { burn_dressing = true }, electrical_burn = { burn_dressing = true }, blast_injury = { burn_dressing = true }, respiratory = { oxygen = true },
}
local OPEN = { injured = true, complicated = true }

local function engineReady()
    return ready() and PFMed.Store ~= nil and PFMed.Engine ~= nil
end

--- Legacy injury_type of an engine injury (nil for hidden ones a look cannot find: internal
--- bleeding, organ, head and spinal trauma stay for the exam of batch 17).
function DB.LegacyType(inj)
    if type(inj.attrs) == 'table' and inj.attrs.blast then return 'blast_injury' end
    return LEGACY_TYPE[inj.type]
end

local function zoneOf(inj)
    local A = PFMed.Anatomy
    local kind = A.GroupKindOf(inj.region, inj.structure)
    local name = tostring(inj.structure or inj.region or '')
    local side = name:sub(-2) == '_r' and 'right' or 'left'
    if kind == 'head' or kind == 'neck' then return 'head' end
    if kind == 'arm' then return side .. '_arm' end
    if kind == 'leg' then return side .. '_leg' end
    return 'torso'
end

function DB.LegacyShape(inj)
    local t = DB.LegacyType(inj)
    if not t then return nil end
    local attrs = type(inj.attrs) == 'table' and inj.attrs or {}
    return {
        id = inj.id, source = 'engine', injury_type = t, severity = LEGACY_SEVERITY[inj.severity] or 'minor', body_zone = zoneOf(inj),
        weapon = attrs.weaponLabel or inj.mechanism, recorded_by = 'medical_engine', created_at = inj.created_at,
    }
end

local function unimported(citizenId, extra, params)
    return ('FROM `%s` p LEFT JOIN `pf_med_injuries` m ON m.`legacy_id` = p.`id` WHERE p.`citizen_id` = ? AND p.`deleted_at` IS NULL AND m.`id` IS NULL%s')
        :format(T_INJURIES, extra or ''), params
end

--- The citizen's open injuries in the legacy shape: untreated engine injuries, then legacy rows the
--- import has not copied. A treated (stabilised) injury leaves the list, as a treated row used to.
function GetCitizenInjuries(citizenId)
    if not ready() then return {} end
    local out = {}
    if engineReady() then
        local p = PFMed.Store.Get(citizenId)
        if p then
            for _, inj in pairs(p.injuries) do
                local row = OPEN[inj.stage] and DB.LegacyShape(inj)
                if row then out[#out + 1] = row end
            end
            table.sort(out, function(a, b) return (a.created_at or 0) > (b.created_at or 0) or ((a.created_at or 0) == (b.created_at or 0) and a.id > b.id) end)
        end
    end
    local from = unimported(citizenId)
    for _, r in ipairs(MySQL.query.await('SELECT p.id, p.injury_type, p.severity, p.body_zone, p.health_percentage, p.weapon, p.recorded_by, p.created_at ' .. from .. ' ORDER BY p.id DESC LIMIT 50', { citizenId }) or {}) do
        if #out >= 50 then break end
        r.source = 'legacy'
        out[#out + 1] = r
    end
    return out
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

--- Legacy field treatment: stabilises the untreated engine injuries of the given types up to
--- maxSeverity (bleeding wounds get pressure, fractures a splint) and deletes matching legacy rows
--- the import has not copied. Returns how many were treated.
function RemoveTreatedInjuries(citizenId, types, maxSeverity)
    if not ready() then return 0 end
    local maxRank = PFAmbulance.SeverityRank(maxSeverity) or 0
    local n = 0
    if engineReady() and type(types) == 'table' then
        local p = PFMed.Store.Get(citizenId)
        for id, inj in pairs(p and p.injuries or {}) do
            local t = OPEN[inj.stage] and DB.LegacyType(inj)
            if t and types[t] and (PFAmbulance.SeverityRank(LEGACY_SEVERITY[inj.severity]) or 99) <= maxRank then
                if PFMed.Engine.UpdateInjury(citizenId, id, { stage = 'stabilized', treatments = TREATMENT_FLAGS[t] or {} },
                    { actor = { kind = 'system', label = 'legacy field treatment' }, source = 'legacy_treatment' }) then n = n + 1 end
            end
        end
    end
    local allowed, typeList = {}, {}
    for _, s in ipairs(Config.InjurySeverities) do
        if PFAmbulance.SeverityRank(s) <= maxRank then allowed[#allowed + 1] = s end
    end
    for t in pairs(types or {}) do typeList[#typeList + 1] = t end
    if #typeList == 0 or #allowed == 0 then return n end
    local params, th, sh = { citizenId }, {}, {}
    for _, t in ipairs(typeList) do params[#params + 1] = t; th[#th + 1] = '?' end
    for _, s in ipairs(allowed) do params[#params + 1] = s; sh[#sh + 1] = '?' end
    local from = unimported(citizenId, (' AND p.injury_type IN (%s) AND p.severity IN (%s)'):format(table.concat(th, ','), table.concat(sh, ',')))
    return n + (tonumber(MySQL.update.await('DELETE p ' .. from, params)) or 0)
end

--- Hospital treatment (check-in bed or respawn): every open engine injury is taken through its
--- stages to recovered, and legacy rows without an engine copy are deleted. Returns the count.
function ClearCitizenInjuries(citizenId)
    if not ready() then return 0 end
    local n = 0
    if engineReady() then
        local p = PFMed.Store.Get(citizenId)
        local ctx = { actor = { kind = 'system', label = 'hospital treatment' }, source = 'legacy_hospital' }
        for id, inj in pairs(p and p.injuries or {}) do
            if inj.stage ~= 'recovered' then
                for _, st in ipairs({ 'stabilized', 'treated', 'recovering', 'recovered' }) do
                    if PFMed.Injuries.CanTransition(inj.stage, st) then PFMed.Engine.UpdateInjury(citizenId, id, { stage = st }, ctx) end
                end
                if inj.stage == 'recovered' then n = n + 1 end
            end
        end
    end
    return n + (tonumber(MySQL.update.await('DELETE p ' .. unimported(citizenId), { citizenId })) or 0)
end

function LogTreatment(citizenId, treatment)
    if not ready() then return nil end
    return MySQL.insert.await(('INSERT INTO `%s` (citizen_id, treatment_type, treated_by, duration, notes) VALUES (?, ?, ?, ?, ?)'):format(T_TREATMENTS),
        { citizenId, treatment.type, treatment.treatedBy or 'system', treatment.duration or 0, treatment.notes })
end
