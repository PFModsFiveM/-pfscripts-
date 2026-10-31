-- City events: one timeline every system writes to and anyone can listen to.
--
--   exports['pf-services']:Emit('gov.tax.changed', { tax = 'sales', label = 'Sales tax', oldRate = 5, newRate = 7 },
--       { title = 'Sales tax rises to 7%', district = 'downtown', coords = vector3(...), actor = citizenid, dedupe = 'sales' })
--
-- Listeners in other resources:
--   AddEventHandler('pf-services:cityEvent', function(event) ... end)
-- where event = { id, kind, category, news, title, data, district, coords, source, actor, police, bulletin, at }.
-- Server-only: city events never come from a client.

PFServices = PFServices or {}

local EventKinds = {}
for kind, def in pairs(PFCatalog.Events) do EventKinds[kind] = def end

local recent = {}     -- dedupe key -> os.time() of the last record
local listeners = {}  -- in-resource listeners (tests and the dispatch bridge)

local function cleanText(v, max)
    if v == nil then return nil end
    v = tostring(v):gsub('[%c]', ' ')
    if v == '' then return nil end
    return v:sub(1, max)
end

local function coordsOf(c)
    if type(c) ~= 'table' and type(c) ~= 'vector3' and type(c) ~= 'vector4' then return nil end
    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    if not (x and y) then return nil end
    if x ~= x or y ~= y or math.abs(x) > 1e5 or math.abs(y) > 1e5 then return nil end
    return { x = x, y = y, z = z or 0.0 }
end
PFServices.coordsOf = coordsOf

function PFServices.RegisterEventKind(kind, def)
    if type(kind) ~= 'string' or not kind:match('^[%w%._%-]+$') or #kind > 64 then return false, 'bad kind' end
    def = type(def) == 'table' and def or {}
    local news = def.news
    if news ~= 'auto' and news ~= 'lead' then news = 'none' end
    EventKinds[kind] = {
        label = cleanText(def.label, 80) or kind,
        news = news,
        category = cleanText(def.category, 32) or 'city',
        police = def.police == true,
        bulletin = def.bulletin == true,
    }
    return true
end

function PFServices.GetEventKind(kind) return EventKinds[kind] end
function PFServices.GetEventKinds() return EventKinds end

function PFServices.OnEvent(fn)
    if type(fn) == 'function' then listeners[#listeners + 1] = fn end
end

--- Records a city event and tells every listener. Returns the event (with id) or nil, err.
function PFServices.Emit(kind, data, opts)
    if type(kind) ~= 'string' then return nil, 'bad kind' end
    local def = EventKinds[kind]
    if not def then return nil, 'unknown kind' end
    opts = type(opts) == 'table' and opts or {}
    data = type(data) == 'table' and data or {}

    local now = os.time()
    local dedupe = opts.dedupe and (kind .. ':' .. tostring(opts.dedupe)):sub(1, 160) or nil
    if dedupe then
        local last = recent[dedupe]
        if last and now - last < (Config.Events.dedupeSeconds or 120) then return nil, 'duplicate' end
        recent[dedupe] = now
    end

    local coords = coordsOf(opts.coords or data.coords)
    local ok, encoded = pcall(json.encode, data)
    if not ok then encoded = '{}' end
    local event = {
        kind = kind,
        category = def.category,
        news = opts.news or def.news,
        title = cleanText(opts.title, 160),
        data = data,
        district = cleanText(opts.district or data.district, 64),
        coords = coords,
        source = cleanText(opts.resource or GetInvokingResource() or GetCurrentResourceName(), 64),
        actor = cleanText(opts.actor, 50),
        police = def.police and opts.police ~= false,
        bulletin = def.bulletin == true,
        at = now,
    }

    local id
    local okDb, err = pcall(function()
        id = MySQL.insert.await([[INSERT INTO pf_city_events (kind, category, news_mode, title, data, district, x, y, z, source_resource, actor_cid, dedupe_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            kind, event.category, event.news, event.title, encoded, event.district,
            coords and coords.x or nil, coords and coords.y or nil, coords and coords.z or nil,
            event.source, event.actor, dedupe,
        })
    end)
    if not okDb then print('^1[pf-services]^7 event not recorded: ' .. tostring(err)) end
    event.id = tonumber(id)

    for _, fn in ipairs(listeners) do
        local okL, errL = pcall(fn, event)
        if not okL then print('^1[pf-services]^7 event listener failed: ' .. tostring(errL)) end
    end
    TriggerEvent('pf-services:cityEvent', event)
    return event
end

--- Recent events, newest first. filter = { kind = 'gov.%', category = 'crime', limit = 50, since = epoch }
function PFServices.GetRecentEvents(filter)
    filter = type(filter) == 'table' and filter or {}
    local where, params = {}, {}
    if type(filter.kind) == 'string' then
        if filter.kind:find('%%') then where[#where + 1] = 'kind LIKE ?' else where[#where + 1] = 'kind = ?' end
        params[#params + 1] = filter.kind
    end
    if type(filter.category) == 'string' then where[#where + 1] = 'category = ?'; params[#params + 1] = filter.category end
    if tonumber(filter.since) then where[#where + 1] = 'created_at >= FROM_UNIXTIME(?)'; params[#params + 1] = math.floor(tonumber(filter.since)) end
    local limit = math.max(1, math.min(200, math.floor(tonumber(filter.limit) or 50)))
    local sql = 'SELECT id, kind, category, news_mode, title, data, district, x, y, z, source_resource, actor_cid, UNIX_TIMESTAMP(created_at) AS at FROM pf_city_events'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY id DESC LIMIT ' .. limit
    local rows = MySQL.query.await(sql, params) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(r.id), kind = r.kind, category = r.category, news = r.news_mode, title = r.title,
            data = r.data and json.decode(r.data) or {}, district = r.district,
            coords = r.x and { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z) } or nil,
            source = r.source_resource, actor = r.actor_cid, at = tonumber(r.at),
        }
    end
    return out
end

function PFServices.PruneEvents()
    pcall(function()
        MySQL.query.await('DELETE FROM pf_city_events WHERE created_at < NOW() - INTERVAL ? DAY', { Config.Events.keepDays or 30 })
    end)
end

function PFServices.__resetEvents()
    recent, listeners = {}, {}
    EventKinds = {}
    for kind, def in pairs(PFCatalog.Events) do EventKinds[kind] = def end
end
