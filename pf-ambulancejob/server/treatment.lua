-- Legacy field treatment entry point (architecture 9): pf-ambulancejob:server:applyTreatment(targetId,
-- treatmentType) from the EMS MDT injury panel and old clients. The old keys map onto the treatment
-- engine (server/medical/treatment.lua): bandage -> pressure_dressing, splint -> splint,
-- burn_dressing -> burn_dressing, oxygen -> oxygen. Every check, the item use and the effect are the
-- engine's; this file only forwards. (The old handler removed rows from the frozen player_injuries
-- table and healed the ped; neither happens any more.)

RegisterNetEvent('pf-ambulancejob:server:applyTreatment', function(targetId, treatmentType)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if not PFMed or not PFMed.Treat then return end
    PFMed.Treat.Legacy(src, targetId, treatmentType)
end)
