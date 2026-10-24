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
RegisterNetEvent('pf-emsmdt:client:displayInjuryAssessment', function(assessmentData)
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

-- Format injury for display
function FormatInjuryForDisplay(injury)
    local zoneDisplay = {
        ['head'] = 'Head',
        ['torso'] = 'Chest/Abdomen',
        ['left_arm'] = 'Left Arm',
        ['right_arm'] = 'Right Arm',
        ['left_leg'] = 'Left Leg',
        ['right_leg'] = 'Right Leg'
    }
    
    local typeDisplay = {
        ['gunshot_wound'] = 'Gunshot Wound',
        ['laceration'] = 'Laceration',
        ['blunt_trauma'] = 'Blunt Trauma',
        ['burn'] = 'Burn',
        ['fracture'] = 'Fracture',
        ['respiratory'] = 'Respiratory Issue',
        ['electrical_burn'] = 'Electrical Burn',
        ['blast_injury'] = 'Blast Injury'
    }
    
    local severityDisplay = {
        ['critical'] = 'CRITICAL',
        ['severe'] = 'SEVERE',
        ['moderate'] = 'MODERATE',
        ['minor'] = 'MINOR'
    }
    
    return {
        zone = zoneDisplay[injury.body_zone] or injury.body_zone,
        type = typeDisplay[injury.injury_type] or injury.injury_type,
        severity = severityDisplay[injury.severity] or injury.severity,
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
