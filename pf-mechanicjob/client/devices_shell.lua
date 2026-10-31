-- Sends mechanic app messages (work orders, register, management updates) to the device the player
-- has open: the tablet or the computer both host the same mechanic app modules through pf-devices.
-- Falls back to the tablet when pf-devices is not running.

function PFMechShell(payload)
    if type(payload) ~= 'table' then return false end
    if GetResourceState('pf-devices') == 'started' then
        local ok = pcall(function() exports['pf-devices']:SendToShell(payload) end)
        if ok then return true end
    end
    if GetResourceState('pf-tablet') == 'started' then
        return pcall(function() exports['pf-tablet']:SendNuiMessage(payload) end)
    end
    return false
end

function PFMechShellOpen()
    if GetResourceState('pf-devices') == 'started' then
        local ok, open = pcall(function() return exports['pf-devices']:IsShellOpen() end)
        if ok then return open == true end
    end
    if GetResourceState('pf-tablet') == 'started' then
        local ok, open = pcall(function() return exports['pf-tablet']:IsTabletOpen() end)
        return ok and open == true
    end
    return false
end
