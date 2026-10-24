-- Framework Bridge for QB-Core and ESX (currently QB-Core only)
PFAmbulance = {}

function PFAmbulance.GetCore()
    if Config.Framework == 'qbcore' then
        return exports['pfm-core']:GetCoreObject()
    elseif Config.Framework == 'esx' then
        return exports['es_extended']:getSharedObject()
    end
    error("Invalid framework: " .. tostring(Config.Framework))
end

function PFAmbulance.GetPlayer(source)
    local QBCore = PFAmbulance.GetCore()
    if Config.Framework == 'qbcore' then
        return QBCore.Functions.GetPlayer(source)
    end
end

function PFAmbulance.IsAllowedJob(jobName)
    return Config.AllowedJobs[jobName] == true
end

function PFAmbulance.GetInjuries(citizenId)
    return MySQL.Sync.fetchAll('SELECT * FROM ' .. Config.Database.PlayerInjuries .. ' WHERE citizen_id = ?', {citizenId})
end

function PFAmbulance.DebugPrint(...)
    if Config.Debug then
        print("^2[PF-Ambulance]^7", ...)
    end
end

function PFAmbulance.LogError(message)
    print("^1[PF-Ambulance ERROR]^7 " .. tostring(message))
end
