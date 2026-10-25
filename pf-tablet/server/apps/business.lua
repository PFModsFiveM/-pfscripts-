local QBCore = exports['pfm-core']:GetCoreObject()

-- Load pf-computer config if available for business names
local ComputerConfig = nil
pcall(function()
    -- Try to load pf-computer config
    local configPath = GetResourcePath('pf-computer')
    if configPath then
        local configFile = LoadResourceFile('pf-computer', 'config/config.lua')
        if configFile then
            -- Run pf-computer's config in its own environment: it assigns the global Config,
            -- which would otherwise overwrite pf-tablet's Config. Reads fall through to _G.
            local env = setmetatable({}, { __index = _G })
            local chunk = load(configFile, '@pf-computer/config/config.lua', 't', env)
            if chunk then
                chunk()
                ComputerConfig = env.Config
            end
        end
    end
end)

local function GetJobOnlineCounts(src, cb, jobs)
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
end

-- Get businesses with proper names from pf-computer config
local function GetBusinessList(src, cb)
    local businesses = {}
    
    -- Get all players and count by job
    local jobCounts = {}
    local players = QBCore.Functions.GetQBPlayers and QBCore.Functions.GetQBPlayers() or {}
    if next(players) == nil then
        for _, pid in ipairs(QBCore.Functions.GetPlayers()) do
            local P = QBCore.Functions.GetPlayer(pid)
            if P then players[pid] = P end
        end
    end

    for _, P in pairs(players) do
        local j = P.PlayerData.job
        if j and j.onduty then
            jobCounts[j.name] = (jobCounts[j.name] or 0) + 1
        end
    end

    -- Build business list with names from pf-computer config
    if ComputerConfig and ComputerConfig.BusinessManager and ComputerConfig.BusinessManager.AllowedJobs then
        for jobName, jobConfig in pairs(ComputerConfig.BusinessManager.AllowedJobs) do
            local businessType = jobConfig.businessType or 'business'
            local icon = '🏢'
            
            -- Get icon from business type
            if ComputerConfig.BusinessManager.BusinessTypes and ComputerConfig.BusinessManager.BusinessTypes[businessType] then
                icon = ComputerConfig.BusinessManager.BusinessTypes[businessType].icon or icon
            end
            
            table.insert(businesses, {
                role = jobName,
                label = jobConfig.businessName or jobName,
                businessName = jobConfig.businessName or jobName,
                icon = icon,
                businessType = businessType,
                description = businessType:gsub("^%l", string.upper) .. ' business',
                online = jobCounts[jobName] or 0
            })
        end
    else
        -- Fallback: use default job list if pf-computer config not available
        -- You can add default jobs here or keep empty
        print('[pf-tablet] Warning: pf-computer config not loaded, businesses list may be limited')
    end
    
    cb(businesses)
end

-- Primary (pf-tablet)
QBCore.Functions.CreateCallback('pf-tablet:server:getJobOnlineCounts', GetJobOnlineCounts)
QBCore.Functions.CreateCallback('pf-tablet:server:getBusinesses', GetBusinessList)
-- Backward compat alias
QBCore.Functions.CreateCallback('pf-jobsystem:server:getJobOnlineCounts', GetJobOnlineCounts)

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
    TriggerClientEvent('pf-tablet:client:businessPushRefresh', -1)
    -- Backward compat alias
    TriggerClientEvent('pf-jobsystem:client:businessPushRefresh', -1)
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
