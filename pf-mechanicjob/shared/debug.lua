PFMech = PFMech or {}

-- Preserve originals (resource-local Lua state)
PFMech._print = PFMech._print or print
PFMech._trace = PFMech._trace or (Citizen and Citizen.Trace)

function PFMech.IsDebug()
    return Config ~= nil and Config.Debug == true
end

-- Debug logging helper (safe even if global print is muted)
function PFMech.Debug(...)
    if not PFMech.IsDebug() then return end
    PFMech._print(...)
end

-- When debug is off, completely silence console prints for this resource.
-- This prevents stray/unwrapped print() calls from spamming the server/client console.
function PFMech.ApplyConsoleMute()
    if PFMech.IsDebug() then
        if PFMech._print then _G.print = PFMech._print end
        if Citizen and PFMech._trace then Citizen.Trace = PFMech._trace end
        return
    end

    _G.print = function() end

    if Citizen and Citizen.Trace then
        Citizen.Trace = function() end
    end
end

PFMech.ApplyConsoleMute()
