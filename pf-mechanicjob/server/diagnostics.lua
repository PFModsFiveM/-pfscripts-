local QBCore = exports['pfm-core']:GetCoreObject()

print('[DIAG SERVER] Loading diagnostics item handler...')

-- Useable item registration (single source of truth)
QBCore.Functions.CreateUseableItem('diagnostics_tool', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    -- Optional job gate (remove if public)
    if not Config.IsMechanicJob(Player.PlayerData.job.name) then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic', 'error')
        return
    end

    TriggerClientEvent('pf-mechanicjob:client:openDiagnosticsDirect', source)
end)

print('[DIAG SERVER] Loaded.')
