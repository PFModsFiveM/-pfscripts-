-- Calendar: personal events (owner = the server's citizen id), city events (posted by government
-- staff with one of CitizenConfig.Calendar.CityPermissions) and business events (posted by those
-- who manage a registered business, for its staff). Reminders go out as a notification and a push
-- shortly before the start, once per person, while they are online.

PFCitizen = PFCitizen or {}
PFCitizen.Calendar = PFCitizen.Calendar or {}
local C = PFCitizen
local K = PFCitizen.Calendar
local CFG = CitizenConfig.Calendar

local SCOPES = { personal = true, city = true, business = true }
local COLUMNS = [[id, scope, owner, title, description, location, UNIX_TIMESTAMP(starts_at) AS starts, UNIX_TIMESTAMP(ends_at) AS ends,
    remind_minutes, created_by, created_by_name, cancelled]]

local function eventRow(id)
    id = C.Int(id, 1)
    if not id then return nil end
    return MySQL.single.await('SELECT ' .. COLUMNS .. ' FROM pf_citizen_events WHERE id = ? LIMIT 1', { id })
end

local function staffOf(businessId)
    local out = {}
    for _, e in ipairs(C.BusinessStaff(businessId)) do if e.citizenid then out[e.citizenid] = true end end
    return out
end

--- May `src` see this event?
local function canSee(src, cid, ev, cache)
    if ev.scope == 'personal' then return ev.owner == cid end
    if ev.scope == 'city' then return true end
    cache = cache or {}
    if cache[ev.owner] == nil then
        cache[ev.owner] = C.ManagesBusiness(src, ev.owner) or staffOf(ev.owner)[cid] == true
    end
    return cache[ev.owner]
end

--- May `src` change or cancel this event?
local function canEdit(src, cid, ev)
    if ev.scope == 'personal' then return ev.owner == cid end
    if ev.scope == 'city' then return C.GovPermission(src, CFG.CityPermissions) end
    return C.ManagesBusiness(src, ev.owner)
end

local function view(src, cid, r, subs, names, editCache)
    local key = r.scope .. ':' .. r.owner
    if editCache[key] == nil then editCache[key] = canEdit(src, cid, r) end
    return {
        id = tonumber(r.id), scope = r.scope, owner = r.scope == 'business' and r.owner or nil,
        ownerName = r.scope == 'business' and (names[r.owner] or r.owner) or (r.scope == 'city' and 'City of Los Santos' or nil),
        title = r.title, description = r.description, location = r.location,
        starts = tonumber(r.starts), ends = tonumber(r.ends), remind = tonumber(r.remind_minutes) or 0,
        by = r.created_by_name, canEdit = editCache[key], subscribed = subs[tonumber(r.id)] == true,
    }
end

function K.List(src, p)
    local P = C.Player(src)
    if not P then return { ok = false, error = 'no_player' } end
    local cid = P.PlayerData.citizenid
    local now = os.time()
    local from = C.Int(p.from, 0) or (now - 7 * 86400)
    local to = C.Int(p.to, 0) or (now + 45 * 86400)
    if to < from or to - from > 100 * 86400 then to = from + 45 * 86400 end
    local rows = MySQL.query.await('SELECT ' .. COLUMNS .. [[ FROM pf_citizen_events
        WHERE cancelled = 0 AND starts_at BETWEEN FROM_UNIXTIME(?) AND FROM_UNIXTIME(?)
          AND ((scope = 'personal' AND owner = ?) OR scope IN ('city', 'business'))
        ORDER BY starts_at, id LIMIT 400]], { from, to, cid }) or {}
    local subs = {}
    for _, s in ipairs(MySQL.query.await('SELECT event_id FROM pf_citizen_event_subs WHERE citizenid = ?', { cid }) or {}) do subs[tonumber(s.event_id)] = true end
    local managed = C.ManagedBusinesses(src)
    local names = {}
    for _, b in ipairs(managed) do names[b.business_id] = b.business_name end
    local seeCache, editCache, out = {}, {}, {}
    for _, r in ipairs(rows) do
        if canSee(src, cid, r, seeCache) then
            if r.scope == 'business' and not names[r.owner] then
                local b = C.Business(r.owner)
                names[r.owner] = b and b.business_name or r.owner
            end
            out[#out + 1] = view(src, cid, r, subs, names, editCache)
        end
    end
    local businesses = {}
    for _, b in ipairs(managed) do businesses[#businesses + 1] = { id = b.business_id, name = b.business_name } end
    return { ok = true, events = out, canPostCity = C.GovPermission(src, CFG.CityPermissions), businesses = businesses, now = now }
end

--- Validates the editable fields; returns a table or nil, error.
local function fields(p)
    local now = os.time()
    local title = C.Text(p.title, CFG.MaxTitle)
    if not title then return nil, 'no_title' end
    local starts = C.Int(p.starts, now - 86400, now + 366 * 86400)
    if not starts then return nil, 'bad_time' end
    local ends
    if p.ends ~= nil and p.ends ~= false and p.ends ~= '' then
        ends = C.Int(p.ends, starts, starts + 7 * 86400)
        if not ends then return nil, 'bad_end' end
    end
    local remind = 0
    if p.remind ~= nil then
        remind = C.Int(p.remind, 0, CFG.MaxRemindMinutes)
        if not remind then return nil, 'bad_reminder' end
    end
    return { title = title, description = C.Text(p.description, CFG.MaxDescription, true), location = C.Text(p.location, CFG.MaxLocation),
        starts = starts, ends = ends, remind = remind }
end

local function changed(scope, owner, cid)
    if scope == 'personal' then C.Push(cid, 'calendar', 'changed', {})
    elseif scope == 'city' then
        if C.Started('pf-devices') then pcall(function() exports['pf-devices']:Broadcast('calendar', 'changed', {}) end) end
    else
        for staff in pairs(staffOf(owner)) do C.Push(staff, 'calendar', 'changed', {}) end
        for _, boss in ipairs(C.BusinessBosses(owner) or {}) do C.Push(boss, 'calendar', 'changed', {}) end
    end
end

--- Stores an event. `src` may be nil for server callers (AddEvent export); then `by` names the poster.
function K.Insert(scope, owner, f, byCid, byName)
    local id = MySQL.insert.await([[INSERT INTO pf_citizen_events (scope, owner, title, description, location, starts_at, ends_at, remind_minutes, created_by, created_by_name)
        VALUES (?, ?, ?, ?, ?, FROM_UNIXTIME(?), IF(? IS NULL, NULL, FROM_UNIXTIME(?)), ?, ?, ?)]],
        { scope, owner, f.title, f.description, f.location, f.starts, f.ends, f.ends, f.remind, byCid, byName })
    return tonumber(id)
end

function K.Create(src, p)
    local P = C.Player(src)
    if not P then return { ok = false, error = 'no_player' } end
    local cid = P.PlayerData.citizenid
    local scope = SCOPES[p.scope] and p.scope or 'personal'
    local f, err = fields(p)
    if not f then return { ok = false, error = err } end
    local owner
    if scope == 'personal' then
        owner = cid
        if p.remind == nil then f.remind = CFG.DefaultRemindMinutes end
        local count = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM pf_citizen_events WHERE scope = 'personal' AND owner = ? AND cancelled = 0 AND starts_at > NOW()", { cid })) or 0
        if count >= CFG.MaxPersonalUpcoming then return { ok = false, error = 'too_many_events' } end
    elseif scope == 'city' then
        if not C.GovPermission(src, CFG.CityPermissions) then return { ok = false, error = 'not_authorized' } end
        owner = 'city'
    else
        owner = C.Token(p.businessId, 100)
        if not owner or not C.ManagesBusiness(src, owner) then return { ok = false, error = 'not_authorized' } end
    end
    if not C.Allow(cid, 'calendar:create', CFG.CreateBurst, CFG.CreateRefillSeconds) then return { ok = false, error = 'rate_limited' } end
    local id = K.Insert(scope, owner, f, cid, C.NameOfPlayer(P))
    if not id then return { ok = false, error = 'not_stored' } end
    if scope == 'business' then
        -- staff hear about it in their mail, so those offline see it too
        local biz = C.Business(owner)
        for staff in pairs(staffOf(owner)) do
            if staff ~= cid then
                C.Mail.Send(staff, { sender = biz and biz.business_name or owner, senderType = 'business', senderAddress = 'biz:' .. owner,
                    subject = 'New event: ' .. f.title, ref = 'event:' .. id,
                    message = ('%s\n%s%s'):format(f.title, os.date('%Y-%m-%d %H:%M', f.starts), f.location and ('\n' .. f.location) or '') .. (f.description and ('\n\n' .. f.description) or '') }, true)
            end
        end
    end
    changed(scope, owner, cid)
    return { ok = true, id = id }
end

function K.Update(src, p)
    local cid = C.Cid(src)
    local ev = cid and eventRow(p.id)
    if not ev or tonumber(ev.cancelled) == 1 then return { ok = false, error = 'not_found' } end
    if not canEdit(src, cid, ev) then return { ok = false, error = 'not_authorized' } end
    local f, err = fields(p)
    if not f then return { ok = false, error = err } end
    MySQL.update.await([[UPDATE pf_citizen_events SET title = ?, description = ?, location = ?, starts_at = FROM_UNIXTIME(?),
        ends_at = IF(? IS NULL, NULL, FROM_UNIXTIME(?)), remind_minutes = ?, updated_at = NOW() WHERE id = ?]],
        { f.title, f.description, f.location, f.starts, f.ends, f.ends, f.remind, ev.id })
    -- a moved event reminds again
    MySQL.update.await('DELETE FROM pf_citizen_event_reminders WHERE event_id = ?', { ev.id })
    changed(ev.scope, ev.owner, cid)
    return { ok = true, id = tonumber(ev.id) }
end

function K.Cancel(src, p)
    local cid = C.Cid(src)
    local ev = cid and eventRow(p.id)
    if not ev or tonumber(ev.cancelled) == 1 then return { ok = false, error = 'not_found' } end
    if not canEdit(src, cid, ev) then return { ok = false, error = 'not_authorized' } end
    MySQL.update.await('UPDATE pf_citizen_events SET cancelled = 1, updated_at = NOW() WHERE id = ?', { ev.id })
    changed(ev.scope, ev.owner, cid)
    return { ok = true }
end

--- "Remind me" for a city or business event the player can see.
function K.Subscribe(src, p)
    local cid = C.Cid(src)
    local ev = cid and eventRow(p.id)
    if not ev or tonumber(ev.cancelled) == 1 or ev.scope == 'personal' or not canSee(src, cid, ev) then return { ok = false, error = 'not_found' } end
    if p.on == false then
        MySQL.update.await('DELETE FROM pf_citizen_event_subs WHERE event_id = ? AND citizenid = ?', { ev.id, cid })
        return { ok = true, subscribed = false }
    end
    MySQL.update.await('INSERT IGNORE INTO pf_citizen_event_subs (event_id, citizenid) VALUES (?, ?)', { ev.id, cid })
    return { ok = true, subscribed = true }
end

--- Who an event reminds: the owner of a personal event; subscribers of a city event; the staff,
--- bosses and subscribers of a business event.
local function reminded(ev)
    local out = {}
    if ev.scope == 'personal' then out[ev.owner] = true return out end
    for _, s in ipairs(MySQL.query.await('SELECT citizenid FROM pf_citizen_event_subs WHERE event_id = ?', { ev.id }) or {}) do out[s.citizenid] = true end
    if ev.scope == 'business' then
        for staff in pairs(staffOf(ev.owner)) do out[staff] = true end
        for _, boss in ipairs(C.BusinessBosses(ev.owner) or {}) do out[boss] = true end
    end
    return out
end

function K.Remind()
    local rows = MySQL.query.await('SELECT ' .. COLUMNS .. [[ FROM pf_citizen_events
        WHERE cancelled = 0 AND remind_minutes > 0 AND starts_at > NOW() AND starts_at <= NOW() + INTERVAL remind_minutes MINUTE
        ORDER BY starts_at LIMIT 200]]) or {}
    local sent = 0
    for _, ev in ipairs(rows) do
        for cid in pairs(reminded(ev)) do
            if C.Online(cid) then
                local claimed = MySQL.update.await('INSERT IGNORE INTO pf_citizen_event_reminders (event_id, citizenid) VALUES (?, ?)', { ev.id, cid })
                if C.Affected(claimed) > 0 then
                    local mins = math.max(1, math.floor(((tonumber(ev.starts) or os.time()) - os.time()) / 60 + 0.5))
                    C.Notify(cid, ('📅 %s starts in %d min%s'):format(ev.title, mins, ev.location and (' · ' .. ev.location) or ''), 'primary')
                    C.Push(cid, 'calendar', 'reminder', { id = tonumber(ev.id), title = ev.title, starts = tonumber(ev.starts), location = ev.location })
                    sent = sent + 1
                end
            end
        end
    end
    return sent
end

--- Server callers (a court date, a delivery slot): scope personal|city|business, owner cid|'city'|businessId.
function K.AddEvent(scope, owner, p, byName)
    if not SCOPES[scope] or type(p) ~= 'table' then return nil, 'bad_request' end
    owner = scope == 'city' and 'city' or C.Token(owner, 100)
    if not owner then return nil, 'bad_request' end
    local f, err = fields(p)
    if not f then return nil, err end
    local id = K.Insert(scope, owner, f, 'system', C.Text(byName, 100) or 'System')
    if id then changed(scope, owner, owner) end
    return id
end
