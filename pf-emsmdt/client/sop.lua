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

local function canEdit()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local level = (PlayerData and PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.level) or 0
    return level >= 4 or isOwner(PlayerData)
end

RegisterNUICallback('getSOPs', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:getSOPs', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('getSOP', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:getSOP', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('createSOP', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canEdit() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:createSOP', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('updateSOP', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canEdit() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:updateSOP', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('deleteSOP', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not canEdit() then cb({ success = false, error = 'no_permission' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:deleteSOP', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)
