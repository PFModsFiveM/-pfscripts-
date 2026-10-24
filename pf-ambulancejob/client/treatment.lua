-- Treatment System
-- Handles treatment application to players

function ApplyTreatment(targetId, treatmentType)
    if not IsPlayerAEMSMember() then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'You are not authorized' },
            color = { 255, 0, 0 }
        })
        return
    end
    
    local treatment = Config.Treatments[treatmentType]
    if not treatment then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'Invalid treatment type' },
            color = { 255, 0, 0 }
        })
        return
    end
    
    local playerPed = PlayerPedId()
    local targetPed = GetPlayerPed(targetId)
    
    if not targetPed or not DoesEntityExist(targetPed) then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'Target player not found' },
            color = { 255, 0, 0 }
        })
        return
    end
    
    -- Check distance
    local playerPos = GetEntityCoords(playerPed)
    local targetPos = GetEntityCoords(targetPed)
    local distance = #(playerPos - targetPos)
    
    if distance > 3.0 then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'You are too far away' },
            color = { 255, 0, 0 }
        })
        return
    end
    
    -- Play animation
    PlayTreatmentAnimation(playerPed, treatment)
    
    -- Show progress
    ShowProgressBar("Applying " .. treatment.label .. "...", treatment.duration)
    
    -- Apply treatment on server
    TriggerServerEvent('pf-ambulancejob:server:applyTreatment', targetId, treatmentType)
    
    -- Show completion message
    TriggerEvent('chat:addMessage', {
        args = { 'EMS', treatment.label .. ' applied' },
        color = { 0, 255, 0 }
    })
end

function PlayTreatmentAnimation(ped, treatment)
    if not treatment.animation then return end
    
    local animDict = treatment.animation.dict
    local animName = treatment.animation.anim
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
    end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0, false, false, false)
end

-- Treatment effects
RegisterNetEvent('pf-ambulancejob:client:applyTreatmentEffects', function(treatmentType)
    local treatment = Config.Treatments[treatmentType]
    if not treatment then return end
    
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    
    if treatment.effects.health then
        SetEntityHealth(ped, treatment.effects.health)
    end
    
    if treatment.effects.healing then
        SetEntityHealth(ped, math.min(health + treatment.effects.healing, 200))
    end
    
    if treatment.effects.status_effect == 'clear_injuries' then
        -- Clear ragdoll
        ClearPedTasksImmediately(ped)
        SetPedToRagdoll(ped, 0, 0, 0, 0, 0, 0)
    end
    
    PFAmbulance.DebugPrint("Treatment effects applied: " .. treatmentType)
end)

-- Menu command for treatment selection
RegisterCommand('treat', function(source, args, rawCommand)
    if not IsPlayerAEMSMember() then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'You are not authorized' },
            color = { 255, 0, 0 }
        })
        return
    end
    
    if #args < 2 then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'Usage: /treat [player_id] [treatment_type]' },
            color = { 255, 165, 0 }
        })
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'Treatments: revive, bandage, splint, oxygen' },
            color = { 255, 165, 0 }
        })
        return
    end
    
    local targetId = tonumber(args[1])
    local treatmentType = args[2]
    
    if not targetId then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'Invalid player ID' },
            color = { 255, 0, 0 }
        })
        return
    end
    
    ApplyTreatment(targetId, treatmentType)
end, false)
