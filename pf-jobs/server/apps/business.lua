local QBCore = exports['pfm-core']:GetCoreObject()

QBCore.Functions.CreateCallback('pf-jobs:server:getJobOnlineCounts', function(src, cb, jobs)
    local counts = {}
    for _, job in ipairs(jobs or {}) do counts[job.role] = 0 end

    local players = QBCore.Functions.GetQBPlayers and QBCore.Functions.GetQBPlayers() or {}
    if next(players) == nil then
        for _, pid in ipairs(QBCore.Functions.GetPlayers()) do
            local P = QBCore.Functions.GetPlayer(pid)
            if P then players[pid] = P end
        end
    end

    for _, P in pairs(players) do
        local j = P.PlayerData.job
        if j and j.onduty and counts[j.name] ~= nil then
            counts[j.name] = counts[j.name] + 1
        end
    end

    local list = {}
    for _, job in ipairs(jobs or {}) do
        list[#list+1] = {
            role        = job.role,
            label       = job.label,
            icon        = job.icon,
            description = job.description or '',
            online      = counts[job.role] or 0
        }
    end
    cb(list)
end)

-- Push refresh when duty/job changes. Every client re-fetches on a push, and QBCore:ToggleDuty is
-- a client event, so pushes are limited to one a second (a change inside that second is pushed
-- once the second is over).
local lastPush, pushQueued = 0, false
local function PushBusinessRefresh()
    local now = GetGameTimer()
    if now - lastPush < 1000 then
        if not pushQueued then
            pushQueued = true
            SetTimeout(1000, function()
                pushQueued = false
                PushBusinessRefresh()
            end)
        end
        return
    end
    lastPush = now
    TriggerClientEvent('pf-jobs:client:businessPushRefresh', -1)
end

-- pfm-core raises this on the server (TriggerEvent); it is not a client event
AddEventHandler('QBCore:Server:OnJobUpdate', function(_, _)
    PushBusinessRefresh()
end)

RegisterNetEvent('QBCore:ToggleDuty', function()
    PushBusinessRefresh()
end)

AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    PushBusinessRefresh()
end)
