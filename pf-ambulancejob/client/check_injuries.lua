-- Injury check: /checkinjuries [id] opens the exam flow on a patient next to you (client/exam.lua,
-- batch 17A); what an exam finds is decided on the server. IsPlayerAEMSMember and GetPatientPed are
-- shared with client/treatment.lua. The legacy damage-history event below still lists recorded
-- injuries when pf-emsmdt is not running (its own refresh button asks for them).

local isCheckingInjuries = false

function IsPlayerAEMSMember()
    local data = QBCore.Functions.GetPlayerData()
    local job = data and data.job
    return job ~= nil and Config.AllowedJobs[job.name] == true and job.onduty == true
end

--- The patient's ped for a server id, if close enough; otherwise nil and a message.
function GetPatientPed(targetServerId)
    local index = GetPlayerFromServerId(targetServerId)
    if index == -1 then return nil, 'Patient not found' end
    local ped = GetPlayerPed(index)
    if not ped or not DoesEntityExist(ped) then return nil, 'Patient not found' end
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) > Config.CheckInjuries.CheckDistance then
        return nil, 'You are too far away'
    end
    return ped
end

local function showInjuryList(data)
    local pd = data.playerData or {}
    local menu = {
        { header = ('%s %s'):format(pd.firstname or '?', pd.lastname or '?'), txt = data.health and ('Health %d%% | Armor %d'):format(math.floor(data.health), data.armor or 0) or 'Injury history', isMenuHeader = true },
    }
    local injuries = data.injuries or {}
    if #injuries == 0 then
        menu[#menu + 1] = { header = 'No recorded injuries', isMenuHeader = true }
    end
    for _, injury in ipairs(injuries) do
        menu[#menu + 1] = {
            header = ('%s: %s'):format(string.upper(injury.severity or '?'), Config.InjuryTypes[injury.injury_type] or injury.injury_type),
            txt = ('%s - %s'):format(Config.BodyZones[injury.body_zone] or injury.body_zone, injury.weapon or 'unknown'),
            isMenuHeader = true,
        }
    end
    exports['pfm-menu']:openMenu(menu)
end

--- /checkinjuries [id] (and the old StartInjuryCheck entry point) now open the exam flow
--- (client/exam.lua): the server decides which exams this provider may do and what they find.
--- Without an id the closest player within reach is examined.
function StartInjuryCheck(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then
        local player, distance = QBCore.Functions.GetClosestPlayer()
        if player == -1 or not distance or distance > Config.CheckInjuries.CheckDistance then
            return QBCore.Functions.Notify('No patient nearby', 'error')
        end
        targetServerId = GetPlayerServerId(player)
    end
    if isCheckingInjuries then return QBCore.Functions.Notify('Already performing an injury check', 'error') end
    local _, err = GetPatientPed(targetServerId)
    if err then return QBCore.Functions.Notify(err, 'error') end
    isCheckingInjuries = true
    CreateThread(function()
        local ok, e = pcall(PFExam.Open, targetServerId)
        isCheckingInjuries = false
        if not ok then print('^1[pf-ambulancejob]^7 exam menu failed: ' .. tostring(e)) end
    end)
end

RegisterCommand('checkinjuries', function(_, args)
    StartInjuryCheck(args[1])
end, false)

-- Injuries sent by pf-ambulancejob:server:getDamageHistory. pf-emsmdt handles this event itself (its
-- refresh button), so here they are only shown when pf-emsmdt is not running.
RegisterNetEvent('pf-ambulancejob:client:receiveDamageHistory', function(injuries, targetPlayerData)
    if type(injuries) ~= 'table' or type(targetPlayerData) ~= 'table' then return end
    if GetResourceState('pf-emsmdt') == 'started' then return end
    showInjuryList({ injuries = injuries, playerData = targetPlayerData })
end)
