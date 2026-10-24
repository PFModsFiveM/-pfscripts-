local function ShowForPlayer(target, title, subtitle, progress)
    local playerId = tonumber(target)
    if not playerId then return false end
    TriggerClientEvent('pf-scoreboard:client:show', playerId, title, subtitle, progress)
    return true
end

local function UpdateForPlayer(target, title, subtitle, progress)
    local playerId = tonumber(target)
    if not playerId then return false end
    TriggerClientEvent('pf-scoreboard:client:update', playerId, title, subtitle, progress)
    return true
end

local function HideForPlayer(target)
    local playerId = tonumber(target)
    if not playerId then return false end
    TriggerClientEvent('pf-scoreboard:client:hide', playerId)
    return true
end

exports('ShowForPlayer', ShowForPlayer)
exports('UpdateForPlayer', UpdateForPlayer)
exports('HideForPlayer', HideForPlayer)

RegisterNetEvent('pf-scoreboard:server:showForPlayer', function(target, title, subtitle, progress)
    ShowForPlayer(target, title, subtitle, progress)
end)

RegisterNetEvent('pf-scoreboard:server:updateForPlayer', function(target, title, subtitle, progress)
    UpdateForPlayer(target, title, subtitle, progress)
end)

RegisterNetEvent('pf-scoreboard:server:hideForPlayer', function(target)
    HideForPlayer(target)
end)
