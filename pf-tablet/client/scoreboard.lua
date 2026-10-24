-- Universal Job Scoreboard System (based on 76b-ui working transparent design)

local ScoreboardActive = false

function ShowScoreboard(title, subtitle)
    ScoreboardActive = true
    SendNUIMessage({
        action = "scoreboard_open",
        title = title or 'Job Active',
        subtitle = subtitle or ''
    })
end

function HideScoreboard()
    ScoreboardActive = false
    SendNUIMessage({
        action = "scoreboard_close"
    })
end

function UpdateScoreboard(title, subtitle)
    if not ScoreboardActive then
        ShowScoreboard(title, subtitle)
    else
        SendNUIMessage({
            action = "scoreboard_update",
            title = title or '',
            subtitle = subtitle or ''
        })
    end
end

-- Exports for other resources to use
exports('ShowScoreboard', ShowScoreboard)
exports('HideScoreboard', HideScoreboard)
exports('UpdateScoreboard', UpdateScoreboard)

-- Register event for backwards compatibility
RegisterNetEvent('pf-jobsystem:client:updateScoreboard', function(title, subtitle, progress)
    UpdateScoreboard(title, subtitle, progress)
end)

RegisterNetEvent('pf-jobsystem:client:hideScoreboard', function()
    HideScoreboard()
end)
