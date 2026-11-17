-- Self-use medical items (bandage, ifaks, painkillers): the progress bar and animation only.
--
-- Batch 17C retired the client bleed loop (client-side bleed damage, blackouts, blood drops) and the
-- per-frame move-rate loop that lived here: bleeding, pain and their effects are decided by the
-- server's medical engine and applied by client/effects.lua. The server consumes the item and
-- applies its medical effect before it sends these events (server/items.lua, batch 17B), so the
-- client neither removes items nor changes bleeding, limbs or pain relief here. What stays on the
-- client is what only the client can set: the small ped-health top-up and the stress relief the
-- items always gave (the HUD server clamps the amount).

-- read by the legacy limb code in client/main.lua; pain relief is server state now
onPainKillers = false

local function playUse(name, label, ms, dict, anim, onDone)
    local ped = PlayerPedId()
    QBCore.Functions.Progressbar(name, label, ms, false, true, {
        disableMovement = false,
        disableCarMovement = false,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = dict,
        anim = anim,
        flags = 49,
    }, {}, {}, function() -- Done
        StopAnimTask(ped, dict, anim, 1.0)
        if onDone then onDone(ped) end
    end, function() -- Cancel (the item was already used on the server)
        StopAnimTask(ped, dict, anim, 1.0)
    end)
end

RegisterNetEvent('hospital:client:UseIfaks', function()
    playUse('use_ifaks', Lang:t('progress.ifaks'), 3000, 'mp_suicide', 'pill', function(ped)
        TriggerServerEvent('hud:server:RelieveStress', math.random(12, 24))
        SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + 10))
    end)
end)

RegisterNetEvent('hospital:client:UseBandage', function()
    playUse('use_bandage', Lang:t('progress.bandage'), 4000, 'anim@amb@business@weed@weed_inspecting_high_dry@', 'weed_inspecting_high_base_inspector', function(ped)
        SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + 10))
    end)
end)

RegisterNetEvent('hospital:client:UsePainkillers', function()
    playUse('use_painkillers', Lang:t('progress.painkillers'), 3000, 'mp_suicide', 'pill')
end)

-- Legacy export kept for third-party callers. Pain relief is a server-side drug on the patient
-- record (painkillers item, batch 17B); a client call cannot grant it, so this reports false.
exports('PainKillerLoop', function()
    return false
end)
