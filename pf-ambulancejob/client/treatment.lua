-- Field treatment (/treat [id] [treatment]): an on-duty medic next to the patient applies a treatment
-- from Config.Treatments; the server checks everything again, uses up the item and removes the
-- injuries it treats. Patients are addressed by server id.

function ApplyTreatment(targetServerId, treatmentType)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return QBCore.Functions.Notify('Invalid player ID', 'error') end
    if not IsPlayerAEMSMember() then return QBCore.Functions.Notify('You are not authorized', 'error') end
    local treatment = Config.Treatments[treatmentType]
    if not treatment then return QBCore.Functions.Notify('Invalid treatment type', 'error') end
    local _, err = GetPatientPed(targetServerId)
    if err then return QBCore.Functions.Notify(err, 'error') end
    if not QBCore.Functions.HasItem(treatment.item) then
        return QBCore.Functions.Notify(('You need a %s'):format(treatment.item), 'error')
    end

    local anim = treatment.animation or Config.CheckInjuries.Animation
    QBCore.Functions.Progressbar('ems_treatment', 'Applying ' .. treatment.label .. '...', treatment.duration, false, true,
        { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
        { animDict = anim.dict, anim = anim.anim, flags = 49 }, {}, {}, function()
            StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0)
            TriggerServerEvent('pf-ambulancejob:server:applyTreatment', targetServerId, treatmentType)
        end, function()
            StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0)
        end)
end

-- Sent by the server to the patient after a treatment it accepted
RegisterNetEvent('pf-ambulancejob:client:applyTreatmentEffects', function(treatmentType)
    local treatment = Config.Treatments[treatmentType]
    if not treatment then return end
    local ped = PlayerPedId()
    if treatment.healing and treatment.healing > 0 and not IsEntityDead(ped) then
        SetEntityHealth(ped, math.min(GetEntityHealth(ped) + treatment.healing, GetEntityMaxHealth(ped)))
    end
end)

RegisterCommand('treat', function(_, args)
    if not args[1] or not args[2] then
        local names = {}
        for name in pairs(Config.Treatments) do names[#names + 1] = name end
        table.sort(names)
        return QBCore.Functions.Notify('Usage: /treat [id] [' .. table.concat(names, ', ') .. ']', 'primary')
    end
    ApplyTreatment(args[1], args[2])
end, false)
