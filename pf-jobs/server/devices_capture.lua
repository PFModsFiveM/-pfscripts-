-- Lets the tablet and computer apps (server/devices.lua) run the same job code the legacy UIs and
-- the world scripts use. Loaded before server/apps/*.lua, it records:
--   * every net event handler this resource registers (RegisterNetEvent is wrapped here), and
--   * every QBCore callback registered through PFJobsCallback(name, fn).
-- PFJobsCapture.fire / .call then invoke them for a player's real source, so every check inside
-- them (distance, ownership, invites, ledger keys) still applies to app requests.

PFJobsCapture = PFJobsCapture or { net = {}, callbacks = {} }

local QBCore = exports['pfm-core']:GetCoreObject()

-- How long an app request waits for a callback that answers later (database reads)
local CALLBACK_TIMEOUT_MS = 8000

local rawRegisterNetEvent = RegisterNetEvent
RegisterNetEvent = function(name, fn, ...)
    if type(name) == 'string' and type(fn) == 'function' then
        local list = PFJobsCapture.net[name] or {}
        list[#list + 1] = fn
        PFJobsCapture.net[name] = list
    end
    return rawRegisterNetEvent(name, fn, ...)
end

--- Registers a QBCore server callback and remembers it for the device apps.
function PFJobsCallback(name, fn)
    if type(name) == 'string' and type(fn) == 'function' then
        PFJobsCapture.callbacks[name] = fn
    end
    return QBCore.Functions.CreateCallback(name, fn)
end

function PFJobsCapture.hasNet(name)
    return PFJobsCapture.net[name] ~= nil
end

--- Runs every handler of net event `name` as if player `src` had triggered it with `...`.
--- FiveM sets the global `source` around a net handler; it is set and restored the same way here.
function PFJobsCapture.fire(name, src, ...)
    local list = PFJobsCapture.net[name]
    if not list then return false end
    local previous = source
    for _, fn in ipairs(list) do
        source = src
        local ok, err = pcall(fn, ...)
        if not ok then
            source = previous
            error(('%s: %s'):format(name, tostring(err)), 0)
        end
    end
    source = previous
    return true
end

--- Runs callback `name` for `src` and returns true plus what it answered, or false when it did not
--- answer. A callback may answer at once or later (after a database read); both are handled.
function PFJobsCapture.call(name, src, ...)
    local fn = PFJobsCapture.callbacks[name]
    if not fn then return false end
    local done, result = false, nil
    local p = (type(promise) == 'table' and promise.new) and promise.new() or nil
    local ok, err = pcall(fn, src, function(...)
        if done then return end
        done = true
        result = table.pack(...)
        if p then p:resolve(true) end
    end, ...)
    if not ok then error(('%s: %s'):format(name, tostring(err)), 0) end
    if not done and p and Citizen and Citizen.Await then
        SetTimeout(CALLBACK_TIMEOUT_MS, function()
            if not done then
                done = true
                p:resolve(false)
            end
        end)
        Citizen.Await(p)
    end
    if not result then return false end
    return true, table.unpack(result, 1, result.n)
end
