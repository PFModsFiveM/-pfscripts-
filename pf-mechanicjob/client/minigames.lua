local QBCore = exports['pfm-core']:GetCoreObject()

-- Rich wheel replacement mini-sequence (overrides stub in tools_menu.lua)
exports('DoWheelSteps', function()
    local ped = PlayerPedId()
    RequestAnimDict('mini@repair')
    while not HasAnimDictLoaded('mini@repair') do Wait(0) end

    local steps = {
        { k='pf_step_lugs',    label='Loosening lugs...',    dur=1400 },
        { k='pf_step_remove',  label='Removing wheel...',    dur=1600 },
        { k='pf_step_clean',   label='Cleaning hub...',      dur=900  },
        { k='pf_step_install', label='Installing new wheel', dur=1700 },
        { k='pf_step_torque',  label='Torquing lugs...',     dur=1200 },
    }

    for _, s in ipairs(steps) do
        if QBCore.Functions.Progressbar then
            local done = false
            QBCore.Functions.Progressbar(s.k, s.label, s.dur, false, true,
                {disableMovement=true, disableCarMovement=true, disableCombat=true},
                {animDict='mini@repair', anim='fixing_a_ped', flags=49},
                {}, {}, function() done=true end, function() done=false end)
            while not done do Wait(25) end
        else
            Wait(s.dur)
        end
    end

    ClearPedTasks(ped)
    return true
end)
