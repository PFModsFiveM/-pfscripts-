-- Framework bridge and shared helpers for the injury system (QBCore / pfm-core)
PFAmbulance = PFAmbulance or {}

local core
function PFAmbulance.GetCore()
    if Config.Framework ~= 'qbcore' then error('Invalid framework: ' .. tostring(Config.Framework)) end
    core = core or exports['pfm-core']:GetCoreObject()
    return core
end

-- Callbacks (the injury files call these; they were used but never defined)
PFAmbulance.Framework = {}
if IsDuplicityVersion() then
    function PFAmbulance.Framework.CreateCallback(name, fn)
        return PFAmbulance.GetCore().Functions.CreateCallback(name, fn)
    end
else
    function PFAmbulance.Framework.TriggerCallback(name, cb, ...)
        return PFAmbulance.GetCore().Functions.TriggerCallback(name, cb, ...)
    end
end

function PFAmbulance.GetPlayer(source)
    return PFAmbulance.GetCore().Functions.GetPlayer(source)
end

function PFAmbulance.IsAllowedJob(jobName)
    return Config.AllowedJobs[jobName] == true
end

--- A player whose job may scan and treat, and who is on duty.
function PFAmbulance.IsOnDutyMedic(Player)
    local job = Player and Player.PlayerData and Player.PlayerData.job
    return job ~= nil and Config.AllowedJobs[job.name] == true and job.onduty == true
end

local severityRank = {}
for i, s in ipairs(Config.InjurySeverities or {}) do severityRank[s] = i end

function PFAmbulance.SeverityRank(severity)
    return severityRank[severity]
end

--- Severity from the health lost in one hit.
function PFAmbulance.SeverityForDamage(damage)
    damage = tonumber(damage) or 0
    if damage > 40 then return 'critical' end
    if damage > 25 then return 'severe' end
    if damage > 10 then return 'moderate' end
    return 'minor'
end

--- Injury type for a weapon hash: an override, then the weapon's class, then blunt trauma.
function PFAmbulance.InjuryTypeForWeapon(weaponHash)
    local override = Config.WeaponInjuryOverrides and Config.WeaponInjuryOverrides[weaponHash]
    if override then return override end
    local class = Config.Weapons and Config.Weapons[weaponHash]
    return (class and Config.WeaponInjuryTypes[class]) or 'blunt_trauma'
end

--- Body part (name, zone) for a bone id, through Config.Bones labels; torso when unknown.
function PFAmbulance.BodyPartForBone(boneId)
    local label = Config.Bones and Config.Bones[boneId]
    return (label and Config.BodyParts[label]) or { name = 'Torso', zone = 'torso' }
end

--- Checks a reported injury against the configured lists; returns a clean copy or nil.
function PFAmbulance.CleanInjury(data)
    if type(data) ~= 'table' then return nil end
    local injuryType, severity, zone = data.injuryType, data.severity, data.bodyZone
    if type(injuryType) ~= 'string' or not Config.InjuryTypes[injuryType] then return nil end
    if type(severity) ~= 'string' or not severityRank[severity] then return nil end
    if type(zone) ~= 'string' or not Config.BodyZones[zone] then return nil end
    local health = math.floor(tonumber(data.health) or 0)
    if health ~= health then health = 0 end
    local weapon = type(data.weapon) == 'string' and data.weapon:sub(1, 50) or 'unknown'
    return { type = injuryType, severity = severity, zone = zone, health = math.max(0, math.min(100, health)), weapon = weapon }
end

function PFAmbulance.DebugPrint(...)
    if Config.Debug then print('^2[PF-Ambulance]^7', ...) end
end

function PFAmbulance.LogError(message)
    print('^1[PF-Ambulance ERROR]^7 ' .. tostring(message))
end
