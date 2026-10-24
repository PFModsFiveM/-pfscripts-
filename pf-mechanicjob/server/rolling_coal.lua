RegisterNetEvent("Smoke:SyncStartParticles")
AddEventHandler("Smoke:SyncStartParticles", function(carid)
    TriggerClientEvent("Smoke:StartParticles", -1, carid)
end)

RegisterNetEvent("Smoke:SyncStopParticles")
AddEventHandler("Smoke:SyncStopParticles", function(carid)
    TriggerClientEvent("Smoke:StopParticles", -1)
end)
