-- Government field apps on the pf-devices platform (tablet and computer): shared helpers.
--
-- Every app handler runs on the server with the player's real id after pf-devices checked the app's
-- access rule; each handler still checks the permission its action needs, and reuses the existing
-- government logic (the NUI actions in Government.NuiCallbacks, Premises, IssueLicense, ...).

GovApps = GovApps or { list = {} }
local A = GovApps

function A.cfg() return Config.GovApps or {} end

function A.Player(src) return QBCore.Functions.GetPlayer(tonumber(src)) end

function A.Cid(src)
    local P = A.Player(src)
    return P and P.PlayerData.citizenid or nil
end

--- Where the player stands, read on the server.
function A.Pos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if not c then return nil end
    local heading = (type(GetEntityHeading) == 'function' and GetEntityHeading(ped)) or 0.0
    return { x = c.x + 0.0, y = c.y + 0.0, z = (c.z or 0.0) + 0.0, heading = tonumber(heading) or 0.0 }
end

function A.Dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- A client string made safe: one line, trimmed, cut to max; nil when empty or not a string.
function A.Text(v, max)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    v = tostring(v):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max or 200)
end

function A.Id(v, max)
    if type(v) ~= 'string' or v == '' or #v > (max or 100) or v:find('[%c%s]') then return nil end
    return v
end

--- Runs an existing government NUI action as `src` and returns what it replied. Most reply at once;
--- the few that reply from an async query are waited for (bounded).
function A.CallNui(action, src, data)
    local handler = Government.NuiCallbacks[action]
    if type(handler) ~= 'function' then return { ok = false, error = 'unavailable' } end
    data = type(data) == 'table' and data or {}
    data.source = src
    local result, done = nil, false
    local p = (type(promise) == 'table' and promise.new) and promise.new() or nil
    local ok, err = pcall(handler, data, function(r)
        if done then return end
        done, result = true, r
        if p then p:resolve(r) end
    end)
    if not ok then
        print(('^1[PF-GOVERNMENT]^7 %s failed: %s'):format(action, tostring(err)))
        return { ok = false, error = 'server_error' }
    end
    if not done and p and Citizen and Citizen.Await then
        SetTimeout(10000, function() if not done then done = true p:resolve({ ok = false, error = 'timeout' }) end end)
        result = Citizen.Await(p)
    end
    if type(result) ~= 'table' then return { ok = false, error = 'empty_response' } end
    return result
end

function A.Business(businessId)
    businessId = A.Id(businessId)
    if not businessId then return nil end
    return MySQL.single.await('SELECT * FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })
end

function A.BusinessPos(biz)
    local x, y, z = tonumber(biz and biz.location_x), tonumber(biz and biz.location_y), tonumber(biz and biz.location_z)
    if not (x and y) then return nil end
    return { x = x, y = y, z = z or 0.0 }
end

--- The official stands at the business (registry location). `required` refuses a business with no
--- recorded location; otherwise such a business passes.
function A.AtBusiness(src, biz, required)
    local at = A.BusinessPos(biz)
    if not at then
        if required then return false, 'no_business_location' end
        return true
    end
    local pos = A.Pos(src)
    if not pos then return false, 'no_position' end
    -- the registry location may lack a height: compare on the ground plane then
    local d = biz.location_z and A.Dist(pos, at) or A.Dist({ x = pos.x, y = pos.y, z = 0 }, { x = at.x, y = at.y, z = 0 })
    if d > (A.cfg().BusinessRange or 60.0) then return false, 'too_far' end
    return true
end

function A.Services()
    if GetResourceState('pf-services') ~= 'started' then return nil end
    return exports['pf-services']
end

function A.Devices()
    if GetResourceState('pf-devices') ~= 'started' then return nil end
    return exports['pf-devices']
end

function A.PushJob(appId, event, payload)
    local d = A.Devices()
    if d then pcall(function() d:PushToJob(Config.GovernmentJob, appId, event, payload or {}, false) end) end
end

function A.PushCitizen(cid, appId, event, payload)
    local d = A.Devices()
    if d and cid then pcall(function() d:PushToCitizen(cid, appId, event, payload or {}) end) end
end

function A.Notify(src, message, kind)
    if src then TriggerClientEvent('QBCore:Notify', src, message, kind or 'primary', 6000) end
end

--- Declares an app for pf-devices. def = RegisterApp definition, handlers = { method = fn(src, payload) }.
function A.Define(def, handlers)
    for i, entry in ipairs(A.list) do
        if entry.def.id == def.id then A.list[i] = { def = def, handlers = handlers } return end
    end
    A.list[#A.list + 1] = { def = def, handlers = handlers }
end

function A.Get(id)
    for _, entry in ipairs(A.list) do if entry.def.id == id then return entry end end
    return nil
end

--- Registers every app with pf-devices (at start, and again whenever pf-devices restarts).
function A.RegisterAll()
    local devices = A.Devices()
    if not devices then return false end
    local all = true
    for _, entry in ipairs(A.list) do
        local ok = pcall(function()
            devices:RegisterApp(entry.def)
            devices:RegisterAppHandlers(entry.def.id, entry.handlers)
        end)
        all = all and ok
    end
    return all
end
