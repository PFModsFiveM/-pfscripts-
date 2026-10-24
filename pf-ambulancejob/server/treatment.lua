local QBCore = PFAmbulance.GetCore()

-- Apply treatment to player
RegisterNetEvent('pf-ambulancejob:server:applyTreatment', function(targetId, treatmentType)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    if not Config.AllowedJobs[Player.PlayerData.job.name] then
        TriggerClientEvent('QBCore:Notify', src, 'You are not authorized', 'error')
        return
    end
    
    local targetPlayer = QBCore.Functions.GetPlayer(targetId)
    if not targetPlayer then
        TriggerClientEvent('QBCore:Notify', src, 'Player not found', 'error')
        return
    end
    
    local treatment = Config.Treatments[treatmentType]
    if not treatment then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid treatment type', 'error')
        return
    end
    
    -- Log treatment
    LogTreatment(targetPlayer.PlayerData.citizenid, {
        type = treatmentType,
        treatedBy = Player.PlayerData.citizenid,
        duration = treatment.duration
    })
    
    -- Apply effects to target
    TriggerClientEvent('pf-ambulancejob:client:applyTreatmentEffects', targetId, treatmentType)
    
    -- Notify both players
    TriggerClientEvent('QBCore:Notify', src, 'Treatment applied: ' .. treatment.label, 'success')
    TriggerClientEvent('QBCore:Notify', targetId, 'Receiving ' .. treatment.label, 'success')
end)

-- Revive player
RegisterNetEvent('pf-ambulancejob:server:revivePlayerEvent', function(targetId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    if not Config.AllowedJobs[Player.PlayerData.job.name] then
        TriggerClientEvent('QBCore:Notify', src, 'You are not authorized', 'error')
        return
    end
    
    local targetPlayer = QBCore.Functions.GetPlayer(targetId)
    if not targetPlayer then
        TriggerClientEvent('QBCore:Notify', src, 'Player not found', 'error')
        return
    end
    
    -- Log treatment
    LogTreatment(targetPlayer.PlayerData.citizenid, {
        type = 'revive',
        treatedBy = Player.PlayerData.citizenid,
        duration = 5000
    })
    
    -- Revive the player
    TriggerClientEvent('pf-ambulancejob:client:revivePlayer', targetId)
    
    -- Notify both players
    TriggerClientEvent('QBCore:Notify', src, 'Player revived', 'success')
    TriggerClientEvent('QBCore:Notify', targetId, 'You have been revived', 'success')
end)
