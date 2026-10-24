-- Injury Check System
-- Allows EMS to scan players for injuries with progress bar

local isCheckingInjuries = false
local scanStartTime = 0

function StartInjuryCheck(targetId)
    if isCheckingInjuries then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'Already performing an injury check' },
            color = { 255, 165, 0 }
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
    
    if distance > Config.CheckInjuries.CheckDistance then
        TriggerEvent('chat:addMessage', {
            args = { 'EMS', 'You are too far away' },
            color = { 255, 0, 0 }
        })
        return
    end
    
    -- Start check
    isCheckingInjuries = true
    scanStartTime = GetGameTimer()
    
    -- Play animation
    PlayCheckInjuriesAnimation(playerPed)
    
    -- Show progress bar
    ShowProgressBar("Scanning Patient...", Config.CheckInjuries.ScanDuration)
    
    -- Scan injuries
    ScanPlayerInjuries(targetId)
    
    -- Wait for scan to complete
    SetTimeout(Config.CheckInjuries.ScanDuration, function()
        isCheckingInjuries = false
        
        -- Get injuries from server
        TriggerServerEvent('pf-ambulancejob:server:getPlayerInjuries', targetId)
        
        -- Open MDT on injuries page
        OpenMDTOnInjuriesPage(targetId)
    end)
end

function PlayCheckInjuriesAnimation(ped)
    local animDict = Config.CheckInjuries.Animation.dict
    local animName = Config.CheckInjuries.Animation.anim
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
    end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0, false, false, false)
end

function ShowProgressBar(text, duration)
    local startTime = GetGameTimer()
    local lastUpdate = 0
    
    while (GetGameTimer() - startTime) < duration do
        -- This would integrate with ox_lib or similar progress system
        -- For now, simple chat indicator
        if (GetGameTimer() - lastUpdate) > 500 then
            lastUpdate = GetGameTimer()
            local progress = ((GetGameTimer() - startTime) / duration) * 100
            PFAmbulance.DebugPrint(string.format("Progress: %.0f%%", progress))
        end
        
        Wait(100)
    end
end

function ScanPlayerInjuries(targetId)
    local targetPed = GetPlayerPed(targetId)
    if not targetPed or not DoesEntityExist(targetPed) then return end
    
    -- Get recent damage history from this player
    local recentDamage = {}
    
    -- Query server for stored injuries
    -- This is done in the callback after scan completes
end

function OpenMDTOnInjuriesPage(targetId)
    -- Get server ID of target
    local targetServerId = GetPlayerServerId(targetId)
    
    -- Request injuries and player data from server
    PFAmbulance.Framework.TriggerCallback('pf-ambulancejob:server:getInjuriesAndData', function(data)
        if not data or not data.success then
            TriggerEvent('chat:addMessage', {
                args = { 'EMS', 'Failed to retrieve patient data' },
                color = { 255, 0, 0 }
            })
            return
        end
        
        -- Trigger MDT to display injuries
        TriggerEvent('pf-emsmdt:client:displayInjuries', 
            targetServerId,
            data.injuries or {},
            data.health or 100,
            data.armor or 0
        )
    end, targetServerId)
end

-- Receive injuries from server
RegisterNetEvent('pf-ambulancejob:client:receiveDamageHistory', function(injuries, targetPlayerData)
    PFAmbulance.DebugPrint("Received " .. #injuries .. " injuries for " .. targetPlayerData.firstname)
    
    -- This data will be used by the MDT
    TriggerEvent('pf-emsmdt:client:displayInjuryAssessment', {
        playerData = targetPlayerData,
        injuries = injuries
    })
end)

-- Scan complete notification
RegisterNetEvent('pf-ambulancejob:client:scanComplete', function(targetId, injuryAssessment)
    TriggerEvent('chat:addMessage', {
        args = { 'EMS', 'Injury scan complete' },
        color = { 0, 255, 0 }
    })
end)
