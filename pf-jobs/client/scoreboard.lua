-- Universal Job Scoreboard System (routes to pf-tablet when available)

local ScoreboardActive = false

local function SendScoreboardMessage(payload)
    if GetResourceState('pf-tablet') == 'started' then
        pcall(function()
            exports['pf-tablet']:SendNuiMessage(payload)
        end)
    end

    SendNUIMessage(payload)
end

function ShowScoreboard(title, subtitle, progress)
    ScoreboardActive = true
    SendScoreboardMessage({
        action = "scoreboard_open",
        title = title or 'Job Active',
        subtitle = subtitle or '',
        progress = progress or ''
    })
end

function HideScoreboard()
    ScoreboardActive = false
    SendScoreboardMessage({
        action = "scoreboard_close"
    })
end

function UpdateScoreboard(title, subtitle, progress)
    if not ScoreboardActive then
        ShowScoreboard(title, subtitle, progress)
    else
        SendScoreboardMessage({
            action = "scoreboard_update",
            title = title or '',
            subtitle = subtitle or '',
            progress = progress or ''
        })
    end
end

-- Exports for other resources to use
exports('ShowScoreboard', ShowScoreboard)
exports('HideScoreboard', HideScoreboard)
exports('UpdateScoreboard', UpdateScoreboard)

-- Register event for backwards compatibility
RegisterNetEvent('pf-jobs:client:updateScoreboard', function(title, subtitle, progress)
    UpdateScoreboard(title, subtitle, progress)
end)

RegisterNetEvent('pf-jobs:client:hideScoreboard', function()
    HideScoreboard()
end)
