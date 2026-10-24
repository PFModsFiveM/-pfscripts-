local QBCore = exports['pfm-core']:GetCoreObject()

-- ── money display commands ───────────────────────────────────────────
QBCore.Commands.Add('cash', 'Check your cash balance', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('hud:client:ShowAccounts', source, 'cash', Player.PlayerData.money.cash)
end)

QBCore.Commands.Add('bank', 'Check your bank balance', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('hud:client:ShowAccounts', source, 'bank', Player.PlayerData.money.bank)
end)

-- ── stress (validated server-side) ───────────────────────────────────
RegisterNetEvent('hud:server:GainStress', function(amount)
    local src = source
    if not Config.StressEnabled then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local value = math.floor(tonumber(amount) or 0)
    if value < 1 then return end
    if value > 10 then value = 10 end
    if Config.DisablePoliceStress and Player.PlayerData.job.name == 'police' then return end
    local newStress = math.min(100, (Player.PlayerData.metadata.stress or 0) + value)
    Player.Functions.SetMetaData('stress', newStress)
    TriggerClientEvent('hud:client:UpdateStress', src, newStress)
end)

RegisterNetEvent('hud:server:RelieveStress', function(amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local value = math.floor(tonumber(amount) or 0)
    if value < 1 then return end
    if value > 100 then value = 100 end
    local newStress = math.max(0, (Player.PlayerData.metadata.stress or 0) - value)
    Player.Functions.SetMetaData('stress', newStress)
    TriggerClientEvent('hud:client:UpdateStress', src, newStress)
end)

-- ── legacy compat stubs (old pf-hud API; settings are client-side now) ─
RegisterNetEvent('hud:server:saveUIData', function() end)
RegisterNetEvent('hud:server:getRank', function() end)
