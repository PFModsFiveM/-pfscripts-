-- Injury Check: an on-duty medic scans a patient next to them (/checkinjuries [id]) and sees the
-- recorded injuries: in pf-emsmdt when that resource runs, otherwise in a pfm-menu list.
-- (Patients are addressed by server id throughout; the old code mixed server ids with local player
-- indexes, called a server event that did not exist and had no command or menu to start a scan.)

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

local function showInjuryList(targetServerId, data)
    if GetResourceState('pf-emsmdt') == 'started' then
        TriggerEvent('pf-emsmdt:client:displayInjuries', targetServerId, data.injuries or {}, data.health or 100, data.armor or 0)
        return
    end
    local pd = data.playerData or {}
    local menu = {
        { header = ('%s %s'):format(pd.firstname or '?', pd.lastname or '?'), txt = ('Health %d%% | Armor %d'):format(math.floor(data.health or 0), data.armor or 0), isMenuHeader = true },
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

function StartInjuryCheck(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return QBCore.Functions.Notify('Invalid player ID', 'error') end
    if not IsPlayerAEMSMember() then return QBCore.Functions.Notify('You are not authorized', 'error') end
    if isCheckingInjuries then return QBCore.Functions.Notify('Already performing an injury check', 'error') end
    local _, err = GetPatientPed(targetServerId)
    if err then return QBCore.Functions.Notify(err, 'error') end

    isCheckingInjuries = true
    local anim = Config.CheckInjuries.Animation
    QBCore.Functions.Progressbar('ems_injury_scan', 'Scanning patient...', Config.CheckInjuries.ScanDuration, false, true,
        { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
        { animDict = anim.dict, anim = anim.anim, flags = 49 }, {}, {}, function()
            isCheckingInjuries = false
            StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0)
            PFAmbulance.Framework.TriggerCallback('pf-ambulancejob:server:getInjuriesAndData', function(data)
                if not data or not data.success then
                    return QBCore.Functions.Notify((data and data.message) or 'Failed to retrieve patient data', 'error')
                end
                showInjuryList(targetServerId, data)
            end, targetServerId)
        end, function()
            isCheckingInjuries = false
            StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0)
        end)
end

RegisterCommand('checkinjuries', function(_, args)
    StartInjuryCheck(args[1])
end, false)

-- Injuries sent by pf-ambulancejob:server:getDamageHistory (pf-emsmdt)
RegisterNetEvent('pf-ambulancejob:client:receiveDamageHistory', function(injuries, targetPlayerData)
    if type(injuries) ~= 'table' or type(targetPlayerData) ~= 'table' then return end
    TriggerEvent('pf-emsmdt:client:displayInjuryAssessment', { playerData = targetPlayerData, injuries = injuries })
end)
