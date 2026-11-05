-- Scans by medics, and the legacy injury self-report (now only a damage hint).
-- A medic must have an allowed job, be on duty and stand next to the patient (the scan is in
-- person); the scan lists the engine's untreated injuries a look can find (GetCitizenInjuries).
-- (The scan callbacks only checked the job, and injury reports were stored as sent.)

local lastReport = {}   -- [src] = GetGameTimer() of the last accepted report

local function nearEachOther(a, b)
    local max = (Config.CheckInjuries and Config.CheckInjuries.CheckDistance or 3.0) + 1.0
    return #(GetEntityCoords(GetPlayerPed(a)) - GetEntityCoords(GetPlayerPed(b))) <= max
end

--- The medic and patient for a scan, or nil and a reason.
local function scanParties(src, targetServerId)
    local Medic = PFAmbulance.GetPlayer(src)
    if not Medic then return nil, nil, 'Source player not found' end
    if not PFAmbulance.IsOnDutyMedic(Medic) then return nil, nil, 'Not authorized' end
    targetServerId = tonumber(targetServerId)
    local Patient = targetServerId and PFAmbulance.GetPlayer(targetServerId)
    if not Patient then return nil, nil, 'Target player not found' end
    if not nearEachOther(src, targetServerId) then return nil, nil, 'Too far from the patient' end
    return Medic, Patient
end

-- Injuries and condition of a patient next to the medic (MDT / scan display)
PFAmbulance.Framework.CreateCallback('pf-ambulancejob:server:getInjuriesAndData', function(source, cb, targetServerId)
    local Medic, Patient, err = scanParties(source, targetServerId)
    if not Medic then
        cb({ success = false, message = err })
        return
    end
    local ped = GetPlayerPed(Patient.PlayerData.source)
    local health = math.max(0, math.min(100, (GetEntityHealth(ped) - 100)))   -- GTA health is 100-200
    cb({
        success = true,
        injuries = GetCitizenInjuries(Patient.PlayerData.citizenid),
        health = health,
        armor = GetPedArmour(ped),
        playerData = {
            citizenid = Patient.PlayerData.citizenid,
            firstname = Patient.PlayerData.charinfo.firstname,
            lastname = Patient.PlayerData.charinfo.lastname,
        },
    })
end)

-- Same data as an event (older clients / pf-emsmdt)
RegisterNetEvent('pf-ambulancejob:server:getDamageHistory', function(targetId)
    local src = source
    local Medic, Patient, err = scanParties(src, targetId)
    if not Medic then
        TriggerClientEvent('QBCore:Notify', src, err, 'error')
        return
    end
    TriggerClientEvent('pf-ambulancejob:client:receiveDamageHistory', src, GetCitizenInjuries(Patient.PlayerData.citizenid), {
        citizenid = Patient.PlayerData.citizenid,
        firstname = Patient.PlayerData.charinfo.firstname,
        lastname = Patient.PlayerData.charinfo.lastname,
    })
end)

-- An old client's injury self-report. It no longer creates a record: it is a damage hint like
-- pf-ambulancejob:server:DamageHint, and the server decides the injuries from its own observations
-- (server/medical/ingest.lua). Kept for old clients and third-party scripts.
RegisterNetEvent('pf-ambulancejob:server:processDamage', function(damageData)
    local src = source
    if not Config.DamageTracking.Enabled then return end
    if not PFAmbulance.GetPlayer(src) then return end
    local now = GetGameTimer()
    if lastReport[src] and now - lastReport[src] < (Config.DamageTracking.ReportCooldown or 2000) then return end
    if not PFAmbulance.CleanInjury(damageData) then return end
    lastReport[src] = now
    if PFMed and PFMed.Ingest then PFMed.Ingest.OnLegacyReport(src, damageData) end
end)

AddEventHandler('playerDropped', function()
    lastReport[source] = nil
end)
