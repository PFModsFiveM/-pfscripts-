local QBCore = PFMdt.GetCore()

local function isAllowedJob()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    return Config and Config.AllowedJobs and Config.AllowedJobs[PlayerData.job.name] == true
end

local function isOwner(PlayerData)
    if not PlayerData then return false end
    local meta = PlayerData.metadata or {}
    if type(meta) ~= 'table' then
        local ok, parsed = pcall(json.decode, meta)
        if ok and type(parsed) == 'table' then meta = parsed else meta = {} end
    end
    return meta.isOwner == true or meta.isowner == true or meta.owner == true
end

local function canManage()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local level = (PlayerData and PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.level) or 0
    return level >= 4 or isOwner(PlayerData)
end

RegisterNUICallback('getOfficersList', function(_, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    local replied = false
    SetTimeout(8000, function()
        if replied then return end
        replied = true
        cb({ success = false, error = 'server_timeout' })
    end)
    QBCore.Functions.TriggerCallback('pf_emsmdt:officers:list', function(result)
        if replied then return end
        replied = true
        cb(result or { success = false, error = 'no_response' })
    end)
end)

RegisterNUICallback('getOfficerProfile', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    local replied = false
    SetTimeout(8000, function()
        if replied then return end
        replied = true
        cb({ success = false, error = 'server_timeout' })
    end)
    QBCore.Functions.TriggerCallback('pf_emsmdt:officers:get', function(result)
        if replied then return end
        replied = true
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('updateOfficerEmployment', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canManage() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:officers:updateEmployment', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('updateOfficerProfileFlags', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canManage() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:officers:setFlags', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('addOfficerDiscipline', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canManage() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:officers:addDiscipline', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('updateOfficerDiscipline', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canManage() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:officers:updateDiscipline', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('fireOfficer', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canManage() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:officers:fire', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)
