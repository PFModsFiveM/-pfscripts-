-- ============================================================================
-- PF Police MDT - server access gate
-- ============================================================================
-- Loaded before every other server script. Every MDT callback and net event of this resource is
-- for police jobs (Config.AllowedJobs) unless it is listed in PUBLIC below. Most handlers never
-- checked the caller's job, so any player could read citizen records, warrants and reports, or
-- create and delete them, by triggering the event from a modified client.

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtAccess = PFMdtAccess or {}

-- Callbacks and net events any player may use (each checks its own caller).
local PUBLIC = {
    ['pf_mdt:auth:canAccess'] = true,
    ['pf_mdt:getOwnedVehicles'] = true,           -- the caller's own vehicles
    ['pf_mdt:getCitationPaperData'] = true,       -- citizen holding a citation paper
    ['pf_mdt:server:mdtSentenceReleased'] = true, -- jailed citizen at the end of the sentence
    ['pf_mdt_dispatch:server:CreateCallout'] = true,
    ['pf_mdt_dispatch:server:Create911Call'] = true,
    ['pf_mdt:dispatch:shotsFired'] = true,
    ['pf_mdt:dispatch:vehicleTheft'] = true,
    ['pf_mdt:dispatch:homicide'] = true,
}

local function isGated(name)
    name = tostring(name or '')
    if PUBLIC[name] then return false end
    return name:sub(1, 7) == 'pf_mdt:' or name:sub(1, 16) == 'pf_mdt_dispatch:'
end

function PFMdtAccess.IsOfficer(src)
    local P = QBCore.Functions.GetPlayer(tonumber(src) or src)
    local job = P and P.PlayerData and P.PlayerData.job
    return job ~= nil and Config and Config.AllowedJobs and Config.AllowedJobs[job.name] == true or false
end

-- Reports from civilians' clients (callouts, auto calls, /911) are about where the caller is.
local REPORT_RADIUS = 150.0
function PFMdtAccess.NearCaller(src, coords)
    if not src or src == 0 then return true end -- server-side exports
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local p = GetEntityCoords(ped)
    return #(vector3(p.x, p.y, p.z) - vector3(coords.x, coords.y, coords.z)) <= REPORT_RADIUS
end

-- simple per-player rate limit: true when allowed
local _rate = {}
function PFMdtAccess.AllowRate(src, key, ms)
    _rate[src] = _rate[src] or {}
    local now = GetGameTimer()
    if _rate[src][key] and now - _rate[src][key] < ms then return false end
    _rate[src][key] = now
    return true
end
AddEventHandler('playerDropped', function() _rate[source] = nil end)

-- Clip a client string: plain text, no control characters, at most maxLen bytes.
function PFMdtAccess.Text(v, maxLen)
    if type(v) ~= 'string' and type(v) ~= 'number' then return '' end
    local s = tostring(v):gsub('[%c]', ' ')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

-- pfm-core calls a callback with its own cb, which reaches this resource as a callable table (a
-- FiveM function reference), never as a Lua function: test it with this, not type(cb) == 'function'.
local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end
PFMdtAccess.Callable = callable

local origCreateCallback = QBCore.Functions.CreateCallback
QBCore.Functions.CreateCallback = function(name, fn, ...)
    if callable(fn) and isGated(name) then
        local inner = fn
        fn = function(src, cb, ...)
            if not PFMdtAccess.IsOfficer(src) then
                if callable(cb) then cb({ success = false, error = 'no_access' }) end
                return
            end
            return inner(src, cb, ...)
        end
    end
    return origCreateCallback(name, fn, ...)
end

local origRegisterNetEvent = RegisterNetEvent
RegisterNetEvent = function(name, fn, ...)
    if callable(fn) and isGated(name) then
        local inner = fn
        fn = function(...)
            if not PFMdtAccess.IsOfficer(source) then return end
            return inner(...)
        end
    end
    return origRegisterNetEvent(name, fn, ...)
end
RegisterServerEvent = RegisterNetEvent
