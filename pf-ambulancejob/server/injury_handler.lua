local QBCore = PFAmbulance.GetCore()

-- Callback: Get injuries and player data for MDT display
PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:getInjuriesAndData', function(source, cb, targetServerId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then
        cb({ success = false, message = 'Source player not found' })
        return
    end
    
    if not Config.AllowedJobs[Player.PlayerData.job.name] then
        cb({ success = false, message = 'Not authorized' })
        return
    end
    
    local targetPlayer = QBCore.Functions.GetPlayer(targetServerId)
    if not targetPlayer then
        cb({ success = false, message = 'Target player not found' })
        return
    end
    
    -- Get injuries from database
    local injuries = GetCitizenInjuries(targetPlayer.PlayerData.citizenid)
    
    -- Get current health/armor
    local targetPed = GetPlayerPed(targetServerId)
    local health = GetEntityHealth(targetPed)
    local armor = GetPedArmour(targetPed)
    
    -- Convert health to percentage
    local healthPercent = ((health - 100) / 100) * 100  -- GTA health is 100-200
    healthPercent = math.max(0, math.min(100, healthPercent))
    
    cb({
        success = true,
        injuries = injuries,
        health = healthPercent,
        armor = armor,
        playerData = {
            citizenid = targetPlayer.PlayerData.citizenid,
            firstname = targetPlayer.PlayerData.charinfo.firstname,
            lastname = targetPlayer.PlayerData.charinfo.lastname
        }
    })
end)

-- Get player damage history
RegisterNetEvent('pf-ambulancejob:server:getDamageHistory', function(targetId)
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
    
    -- Get injuries from database
    local injuries = GetCitizenInjuries(targetPlayer.PlayerData.citizenid)
    
    -- Send to client
    TriggerClientEvent('pf-ambulancejob:client:receiveDamageHistory', src, injuries, targetPlayer.PlayerData)
end)

-- Process damage detection
RegisterNetEvent('pf-ambulancejob:server:processDamage', function(damageData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    PFAmbulance.DebugPrint("Processing damage for player: " .. Player.PlayerData.citizenid, damageData)
    
    -- Store injury data for later retrieval
    AddInjury(Player.PlayerData.citizenid, {
        type = damageData.injuryType or 'blunt_trauma',
        severity = damageData.severity or 'moderate',
        zone = damageData.bodyZone or 'unknown',
        health = damageData.health or 0,
        weapon = damageData.weapon or 'unknown',
        recordedBy = 'damage_detection'
    })
end)

-- Process injury scan completion
RegisterNetEvent('pf-ambulancejob:server:injuryScanComplete', function(targetId, injuryAssessment)
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
    
    PFAmbulance.DebugPrint("Injury scan complete for: " .. targetPlayer.PlayerData.firstname)
    
    -- Send MDT notification
    TriggerClientEvent('pf-ambulancejob:client:scanComplete', src, targetId, injuryAssessment)
end)
