-- Injury Handler
-- Manages injury display, treatment, and integration with MDT

local playerInjuries = {}

-- Get all injuries for a player
function GetInjuriesForPlayer(citizenId)
    return playerInjuries[citizenId] or {}
end

-- Add injury to tracking
function AddPlayerInjury(citizenId, injuryData)
    if not playerInjuries[citizenId] then
        playerInjuries[citizenId] = {}
    end
    
    table.insert(playerInjuries[citizenId], {
        id = #playerInjuries[citizenId] + 1,
        type = injuryData.type,
        severity = injuryData.severity,
        zone = injuryData.zone,
        health = injuryData.health,
        weapon = injuryData.weapon,
        timestamp = GetGameTimer()
    })
end

-- Display injury assessment UI
-- (local event from check_injuries.lua; AddEventHandler so the server or other clients cannot send it)
AddEventHandler('pf-emsmdt:client:displayInjuryAssessment', function(assessmentData)
    if type(assessmentData) ~= 'table' or type(assessmentData.playerData) ~= 'table' then return end
    local playerData = assessmentData.playerData
    local injuries = assessmentData.injuries
    
    PFAmbulance.DebugPrint("Displaying injury assessment for " .. playerData.firstname)
    
    -- Store locally for MDT rendering
    playerInjuries[playerData.citizenid] = injuries
    
    -- Trigger MDT to display injuries
    if GetResourceState('pf-emsmdt') == 'started' then
        TriggerEvent('pf-emsmdt:client:openInjuryPage', {
            citizenId = playerData.citizenid,
            firstname = playerData.firstname,
            lastname = playerData.lastname,
            injuries = injuries
        })
    end
end)

-- Format injury for display (labels from the config)
function FormatInjuryForDisplay(injury)
    return {
        zone = Config.BodyZones[injury.body_zone] or injury.body_zone,
        type = Config.InjuryTypes[injury.injury_type] or injury.injury_type,
        severity = string.upper(injury.severity or ''),
        health = injury.health_percentage,
        weapon = injury.weapon,
        timestamp = injury.created_at
    }
end

-- Get injuries by severity
function GetInjuriesBySeverity(citizenId, severity)
    local injuries = GetInjuriesForPlayer(citizenId)
    local filtered = {}
    
    for _, injury in ipairs(injuries) do
        if injury.severity == severity then
            table.insert(filtered, injury)
        end
    end
    
    return filtered
end

-- Get injuries by body zone
function GetInjuriesByZone(citizenId, zone)
    local injuries = GetInjuriesForPlayer(citizenId)
    local filtered = {}
    
    for _, injury in ipairs(injuries) do
        if injury.zone == zone then
            table.insert(filtered, injury)
        end
    end
    
    return filtered
end
