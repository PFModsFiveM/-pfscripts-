local QBCore = PFMdt.GetCore()

local function isAllowedJob()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    return Config and Config.AllowedJobs and Config.AllowedJobs[PlayerData.job.name] == true
end

local function isGrade4Plus()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local level = (PlayerData and PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.level) or 0
    return level >= 4
end

RegisterNUICallback('getRoster', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:getRoster', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('getRosterMeta', function(_, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:getRosterMeta', function(result)
        cb(result or { success = false, error = 'no_response' })
    end)
end)

RegisterNUICallback('rosterUpdateRow', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not isGrade4Plus() then cb({ success = false, error = 'no_permission' }); return end

    QBCore.Functions.TriggerCallback('pf_emsmdt:roster:updateRowCb', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('rosterAddRow', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not isGrade4Plus() then cb({ success = false, error = 'no_permission' }); return end

    QBCore.Functions.TriggerCallback('pf_emsmdt:roster:addRowCb', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('rosterDeleteRow', function(data, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    if not isGrade4Plus() then cb({ success = false, error = 'no_permission' }); return end

    QBCore.Functions.TriggerCallback('pf_emsmdt:roster:deleteRowCb', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback('getRosterOfficerDirectory', function(_, cb)
    if not isAllowedJob() then cb({ success = false, error = 'no_access' }); return end
    QBCore.Functions.TriggerCallback('pf_emsmdt:roster:getOfficerDirectory', function(result)
        cb(result or { success = false, error = 'no_response' })
    end)
end)
