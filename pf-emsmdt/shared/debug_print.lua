-- Shared debug print shim
-- Goal: suppress all `print(...)` output unless Config.Debug == true.

PFMDT = PFMDT or {}

local function isDebugEnabled()
    return Config ~= nil and Config.Debug == true
end

-- Keep a reference to the original print for cases where you explicitly want it.
-- Note: PFMDT.RawPrint will always print, regardless of Config.Debug.
PFMDT.RawPrint = PFMDT.RawPrint or print

-- Override global print in this resource runtime.
-- Any subsequent `print(...)` calls in loaded scripts will be gated.
local _rawPrint = print
print = function(...)
    if isDebugEnabled() then
        _rawPrint(...)
    end
end

-- Convenience helper for explicit debug prints.
function PFMDT.DebugPrint(...)
    if isDebugEnabled() then
        _rawPrint(...)
    end
end
