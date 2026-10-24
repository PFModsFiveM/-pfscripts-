-- EMS MDT - Injury System Integration
-- Bridges pf-ambulancejob injury system with the MDT interface

local QBCore = PFMdt.GetCore()

-- Store current patient
local currentPatient = nil
local currentInjuries = {}
local currentTargetServerId = nil

local function openInjuryPanel(targetServerId, citizenData, injuries, health, armor)
    currentTargetServerId = tonumber(targetServerId)
    currentPatient = citizenData
    currentInjuries = injuries or {}

    if not citizenData then
        print('[EMS MDT] Missing citizen data for injury panel')
        return
    end

    -- Format injuries for display
    local formattedInjuries = {}
    for _, injury in ipairs(injuries or {}) do
        table.insert(formattedInjuries, {
            injuryType = injury.injury_type or injury.type or 'Unknown',
            bodyPart = injury.body_zone or injury.zone or injury.location or 'Unknown',
            location = injury.body_zone or injury.zone or injury.location or 'Unknown',
            severity = injury.severity or 'minor',
            description = injury.description or injury.weapon or 'No description',
            timestamp = injury.timestamp or injury.created_at or 0
        })
    end

    -- Send to NUI
    SendNUIMessage({
        action = 'displayInjuryAssessment',
        citizenId = citizenData.citizenid,
        patientName = (citizenData.firstname or 'Unknown') .. ' ' .. (citizenData.lastname or 'Unknown'),
        injuries = formattedInjuries,
        health = health or 100,
        armor = armor or 0
    })

    SetNuiFocus(true, true)
end

-- Event: Display injuries in MDT
RegisterNetEvent('pf-emsmdt:client:displayInjuries', function(targetId, injuries, health, armor)
    DebugPrint('[EMS MDT] Displaying injuries for target:', targetId)
    
    -- Get player data
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
    local targetCoords = GetEntityCoords(targetPed)
    
    -- Request citizen data from server
    QBCore.Functions.TriggerCallback('pf-emsmdt:server:getCitizenData', function(citizenData)
        if not citizenData then
            print('[EMS MDT] Failed to get citizen data')
            return
        end
        openInjuryPanel(targetId, citizenData, injuries, health, armor)
    end, targetId)
end)

-- Some pf-ambulancejob flows send injuries via this event
RegisterNetEvent('pf-emsmdt:client:displayInjuryAssessment', function(payload)
    local p = payload or {}
    local pd = p.playerData or {}
    openInjuryPanel(p.targetServerId or currentTargetServerId, {
        citizenid = pd.citizenid,
        firstname = (pd.charinfo and pd.charinfo.firstname) or pd.firstname or 'Unknown',
        lastname = (pd.charinfo and pd.charinfo.lastname) or pd.lastname or 'Unknown'
    }, p.injuries or {}, 100, 0)
end)

-- Refresh callback source: pf-ambulancejob sends this to the requester
RegisterNetEvent('pf-ambulancejob:client:receiveDamageHistory', function(injuries, targetPlayerData)
    local pd = targetPlayerData or {}
    local ci = pd.charinfo or {}
    openInjuryPanel(currentTargetServerId, {
        citizenid = pd.citizenid,
        firstname = ci.firstname or pd.firstname or 'Unknown',
        lastname = ci.lastname or pd.lastname or 'Unknown'
    }, injuries or {}, 100, 0)
end)

-- NUI Callback: Treat patient
RegisterNUICallback('treatPatient', function(data, cb)
    DebugPrint('[EMS MDT] Treating patient:', data.citizenId, 'with', data.treatmentType)
    
    if not data.citizenId or not data.treatmentType then
        cb({ success = false, message = 'Invalid treatment data' })
        return
    end
    
    -- Route to pf-ambulancejob treatment event (expects target server id, not citizenid)
    if not currentTargetServerId then
        cb({ success = false, message = 'No active patient selected' })
        return
    end

    TriggerServerEvent('pf-ambulancejob:server:applyTreatment', currentTargetServerId, data.treatmentType)
    
    cb({ success = true, message = 'Treatment applied successfully' })
end)

-- NUI Callback: Save medical notes
RegisterNUICallback('saveMedicalNotes', function(data, cb)
    DebugPrint('[EMS MDT] Saving medical notes for:', data.citizenId)
    
    if not data.citizenId or not data.notes then
        cb({ success = false, message = 'Invalid notes data' })
        return
    end
    
    -- Store as an EMS MDT patient note
    TriggerServerEvent('pf_emsmdt:addPatientNote', { citizenId = data.citizenId, text = data.notes })
    
    cb({ success = true, message = 'Notes saved successfully' })
end)

-- NUI Callback: Refresh injuries
RegisterNUICallback('refreshInjuries', function(data, cb)
    DebugPrint('[EMS MDT] Refreshing injuries for:', data.citizenId)
    
    if not data.citizenId then
        cb({ success = false, message = 'Invalid citizen ID' })
        return
    end
    
    if not currentTargetServerId then
        cb({ success = false, message = 'No active patient selected' })
        return
    end

    -- Ask pf-ambulancejob for latest injuries; results arrive via pf-ambulancejob:client:receiveDamageHistory
    TriggerServerEvent('pf-ambulancejob:server:getDamageHistory', currentTargetServerId)
    
    cb({ success = true, message = 'Refresh requested' })
end)

-- NUI Callback: Close injury panel
RegisterNUICallback('closeInjuryPanel', function(data, cb)
    DebugPrint('[EMS MDT] Closing injury panel')
    
    SetNuiFocus(false, false)
    currentPatient = nil
    currentInjuries = {}
    currentTargetServerId = nil
    
    cb({ success = true })
end)

print("^2[pf-emsmdt]^7 Injury system integration loaded")
