-- RPC bridge: an app module in either shell calls ctx.rpc(method, payload); the shell's NUI posts
-- to pf-devices, the client sends 'pf-devices:server:rpc', and the handler the owning resource
-- registered runs here with the real `src`. Results go back to that player only.

PFDevices = PFDevices or {}

local buckets = {}   -- src -> { tokens, last }

local function takeToken(src)
    local now = GetGameTimer()
    local b = buckets[src]
    if not b then
        b = { tokens = Config.Rpc.burst, last = now }
        buckets[src] = b
    end
    local elapsed = (now - b.last) / 1000
    if elapsed > 0 then
        b.tokens = math.min(Config.Rpc.burst, b.tokens + elapsed * Config.Rpc.perSecond)
        b.last = now
    end
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

local function payloadTooLarge(payload)
    if payload == nil then return false end
    local ok, encoded = pcall(json.encode, payload)
    if not ok then return true end
    return #encoded > Config.Rpc.maxPayloadBytes
end

--- Runs an RPC for `src` and returns the result table. Shared by the net event and tests.
function PFDevices.HandleRpc(src, appId, method, payload)
    if type(appId) ~= 'string' or type(method) ~= 'string' or (payload ~= nil and type(payload) ~= 'table') then
        return { ok = false, error = 'bad_request' }
    end
    if not takeToken(src) then return { ok = false, error = 'rate_limited' } end
    if payloadTooLarge(payload) then return { ok = false, error = 'payload_too_large' } end

    local app = PFDevices.GetApp(appId)
    if not app then return { ok = false, error = 'unknown_app' } end
    if app.resource ~= GetCurrentResourceName() and GetResourceState(app.resource) ~= 'started' then
        return { ok = false, error = 'app_offline' }
    end
    if method:sub(1, 2) == '__' then return { ok = false, error = 'unknown_method' } end
    local allowed, why = PFDevices.CanUseApp(src, app.id)
    if not allowed then return { ok = false, error = why } end

    local fn = PFDevices.GetHandler(app.id, method)
    if not fn then
        -- Fallback for resources that route everything through one export.
        local ok, res = pcall(function() return exports[app.resource]:AppRpc(src, app.id, method, payload or {}) end)
        if ok and res ~= nil then return type(res) == 'table' and res or { ok = true, data = res } end
        return { ok = false, error = 'unknown_method' }
    end

    local ok, res = pcall(fn, src, payload or {}, { app = app.id, method = method, resource = app.resource })
    if not ok then
        print(('^1[pf-devices]^7 %s.%s failed for %s: %s'):format(app.id, method, tostring(src), tostring(res)))
        return { ok = false, error = 'server_error' }
    end
    if res == nil then return { ok = true } end
    if type(res) ~= 'table' then return { ok = true, data = res } end
    if res.ok == nil then res.ok = true end
    return res
end

RegisterNetEvent('pf-devices:server:rpc', function(reqId, appId, method, payload)
    local src = source
    local result = PFDevices.HandleRpc(src, appId, method, payload)
    TriggerClientEvent('pf-devices:client:rpc', src, reqId, result)
end)

AddEventHandler('playerDropped', function()
    buckets[source] = nil
end)

function PFDevices.__resetRpc()
    buckets = {}
end
