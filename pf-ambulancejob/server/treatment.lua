-- Field treatment by medics.
-- An on-duty medic next to the patient uses up the treatment's item; the injuries it treats (up to
-- Config.FieldTreatmentMaxSeverity) are removed and the patient gets the treatment's healing.
-- (Any medic could treat anyone, anywhere, for free. The separate 'revivePlayerEvent' revived without
-- the checks of hospital:server:RevivePlayer and is gone: revives go through that event.)

local busyUntil = {}   -- [medic src] = GetGameTimer() when their current treatment ends

RegisterNetEvent('pf-ambulancejob:server:applyTreatment', function(targetId, treatmentType)
    local src = source
    local Medic = PFAmbulance.GetPlayer(src)
    if not Medic then return end
    if not PFAmbulance.IsOnDutyMedic(Medic) then
        TriggerClientEvent('QBCore:Notify', src, 'You are not authorized', 'error')
        return
    end
    targetId = tonumber(targetId)
    local Patient = targetId and PFAmbulance.GetPlayer(targetId)
    if not Patient then
        TriggerClientEvent('QBCore:Notify', src, 'Player not found', 'error')
        return
    end
    local treatment = type(treatmentType) == 'string' and Config.Treatments[treatmentType]
    if not treatment then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid treatment type', 'error')
        return
    end
    local max = (Config.CheckInjuries and Config.CheckInjuries.CheckDistance or 3.0) + 1.0
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(targetId))) > max then
        TriggerClientEvent('QBCore:Notify', src, 'You are too far away', 'error')
        return
    end
    local now = GetGameTimer()
    if busyUntil[src] and now < busyUntil[src] then return end

    -- only when there is something this treatment can treat (no item is wasted)
    local treatable = false
    local maxRank = PFAmbulance.SeverityRank(Config.FieldTreatmentMaxSeverity) or 0
    for _, injury in ipairs(GetCitizenInjuries(Patient.PlayerData.citizenid)) do
        if treatment.treats[injury.injury_type] and (PFAmbulance.SeverityRank(injury.severity) or 99) <= maxRank then
            treatable = true
            break
        end
    end
    if not treatable then
        TriggerClientEvent('QBCore:Notify', src, 'Nothing this treatment can help with', 'error')
        return
    end

    if not exports['pfm-inventory']:RemoveItem(src, treatment.item, 1, false, 'pf-ambulancejob:applyTreatment') then
        TriggerClientEvent('QBCore:Notify', src, ('You need a %s'):format(treatment.item), 'error')
        return
    end
    busyUntil[src] = now + (tonumber(treatment.duration) or 0)

    local removed = RemoveTreatedInjuries(Patient.PlayerData.citizenid, treatment.treats, Config.FieldTreatmentMaxSeverity)
    LogTreatment(Patient.PlayerData.citizenid, {
        type = treatmentType, treatedBy = Medic.PlayerData.citizenid, duration = treatment.duration,
        notes = ('%d injur%s treated'):format(removed, removed == 1 and 'y' or 'ies'),
    })

    TriggerClientEvent('pf-ambulancejob:client:applyTreatmentEffects', targetId, treatmentType)
    TriggerClientEvent('QBCore:Notify', src, 'Treatment applied: ' .. treatment.label, 'success')
    TriggerClientEvent('QBCore:Notify', targetId, 'Receiving ' .. treatment.label, 'success')
end)

AddEventHandler('playerDropped', function()
    busyUntil[source] = nil
end)
