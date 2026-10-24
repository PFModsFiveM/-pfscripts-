local ScoreboardActive = false

local function PostNUI(payload)
    local usedTablet = false

    if GetResourceState('pf-tablet') == 'started' then
        usedTablet = pcall(function()
            exports['pf-tablet']:SendNuiMessage(payload)
        end)
    end

    if not usedTablet then
        SendNUIMessage(payload)
    end
end

function ShowScoreboard(title, subtitle, progress)
    ScoreboardActive = true
    PostNUI({
        action = 'scoreboard_open',
        title = title or 'Job Active',
        subtitle = subtitle or '',
        progress = progress or ''
    })
end

function HideScoreboard()
    ScoreboardActive = false
    PostNUI({
        action = 'scoreboard_close'
    })
end

function UpdateScoreboard(title, subtitle, progress)
    if not ScoreboardActive then
        ShowScoreboard(title, subtitle, progress)
        return
    end

    PostNUI({
        action = 'scoreboard_update',
        title = title or '',
        subtitle = subtitle or '',
        progress = progress or ''
    })
end

exports('ShowScoreboard', ShowScoreboard)
exports('HideScoreboard', HideScoreboard)
exports('UpdateScoreboard', UpdateScoreboard)

RegisterNetEvent('pf-scoreboard:client:show', function(title, subtitle, progress)
    ShowScoreboard(title, subtitle, progress)
end)

RegisterNetEvent('pf-scoreboard:client:update', function(title, subtitle, progress)
    UpdateScoreboard(title, subtitle, progress)
end)

RegisterNetEvent('pf-scoreboard:client:hide', function()
    HideScoreboard()
end)

RegisterNetEvent('pf-jobs:client:updateScoreboard', function(title, subtitle, progress)
    UpdateScoreboard(title, subtitle, progress)
end)

RegisterNetEvent('pf-jobs:client:hideScoreboard', function()
    HideScoreboard()
end)
