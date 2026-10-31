-- City events (pf-services) into the news:
--   news = 'auto'  a City Desk article from the kind's preset, published at once; a bulletin kind is a
--                  short breaking article (and, with Config.Auto.bulletinLeads, also a lead)
--   news = 'lead'  a newsroom lead (leads.lua); never published by itself
--   news = 'none'  ignored
-- Exactly once per event id, across restarts: pf_news_events (event_id primary key) records which
-- article / lead each event made or joined, and articles/leads carry the first event's id under a
-- unique key. Events of one group close together update ONE article (a digest) instead of many.
-- Events are processed one at a time (database calls yield; two events must not race for a group).

PFNews = PFNews or {}
PFNews.SQL = PFNews.SQL or {}
local U = PFNews.U
local SQL = PFNews.SQL
local Auto = {}
PFNews.Auto = Auto

SQL.claimEvent = 'INSERT IGNORE INTO pf_news_events (event_id, kind, mode, payload, created_at) VALUES (?, ?, ?, ?, FROM_UNIXTIME(?))'
SQL.getEvent = 'SELECT article_id, lead_id FROM pf_news_events WHERE event_id = ?'
SQL.openGroup = [[SELECT id, UNIX_TIMESTAMP(published_at) AS published_at FROM pf_news_articles
    WHERE group_key = ? AND auto = 1 AND status = 'published' AND group_until >= FROM_UNIXTIME(?) ORDER BY id DESC LIMIT 1]]
SQL.linkEventArticle = 'UPDATE pf_news_events SET article_id = ? WHERE event_id = ? AND article_id IS NULL'
SQL.groupPayloads = 'SELECT event_id, payload FROM pf_news_events WHERE article_id = ? ORDER BY event_id ASC LIMIT 50'
SQL.insertAuto = [[INSERT IGNORE INTO pf_news_articles (title, summary, body, category, images, author_cid, author_name, status, auto, event_id, preset_id,
    group_key, group_until, breaking, created_at, updated_at, published_at)
    VALUES (?, ?, ?, ?, '[]', NULL, ?, 'published', 1, ?, ?, ?, FROM_UNIXTIME(?), ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), FROM_UNIXTIME(?))]]
SQL.articleByEvent = 'SELECT id FROM pf_news_articles WHERE event_id = ?'
SQL.updateDigest = [[UPDATE pf_news_articles SET title = ?, summary = ?, body = ?, preset_id = ?, breaking = GREATEST(breaking, ?),
    group_until = FROM_UNIXTIME(?), updated_at = FROM_UNIXTIME(?) WHERE id = ? AND status = 'published' AND auto = 1]]

local queue, draining = {}, false
local waiting = {}        -- events that arrived before the tables were ready
local seenNoId = {}       -- events without an id (pf-services could not record them): once per session

--- The news mode of an event after the owner's per-kind override.
function Auto.ModeOf(event)
    local o = (Config.Auto.modes or {})[event.kind]
    local mode = o or event.news
    if mode ~= 'auto' and mode ~= 'lead' then return 'none' end
    return mode
end

local function publishArticle(snap, opts)
    local now = os.time()
    local A = Config.Auto
    local group = PFNews.Presets.GroupOf(snap.kind)

    -- join an open group article (only events with an id can be linked to one)
    if snap.id then
        local open = MySQL.single.await(SQL.openGroup, { group, now })
        local openId = open and tonumber(open.id)
        if openId then
            local n = U.affected(MySQL.update.await(SQL.linkEventArticle, { openId, snap.id }))
            if n ~= 1 then return openId end
            local snaps = {}
            for _, row in ipairs(MySQL.query.await(SQL.groupPayloads, { openId }) or {}) do
                local s = U.decode(row.payload, nil)
                if type(s) == 'table' then snaps[#snaps + 1] = s end
            end
            if #snaps == 0 then snaps[1] = snap end
            local r = PFNews.Presets.RenderDigest(group, snaps)
            local untilAt = math.min(now + (A.coalesceSeconds or 90), (tonumber(open.published_at) or now) + (A.coalesceMaxSeconds or 600))
            MySQL.update.await(SQL.updateDigest, { r.title, r.summary, r.body, r.presetId, r.breaking and 1 or 0, untilAt, now, openId })
            PFNews.Articles.Invalidate()
            U.broadcast('updated', { id = openId, title = r.title })
            return openId
        end
    end

    local r = PFNews.Presets.Render(snap)
    local untilAt = now + (A.coalesceSeconds or 90)
    local id = tonumber(MySQL.insert.await(SQL.insertAuto, {
        r.title, r.summary, r.body, r.category, A.byline or 'City Desk', snap.id, r.presetId,
        snap.id and group or nil, untilAt, r.breaking and 1 or 0, now, now, now,
    }))
    local created = id ~= nil and id > 0
    if not created and snap.id then id = tonumber(MySQL.scalar.await(SQL.articleByEvent, { snap.id })) end
    if not id or id < 1 then return nil end
    if snap.id then MySQL.update.await(SQL.linkEventArticle, { id, snap.id }) end
    if created then
        local row = PFNews.Articles.Get(id)
        if row then PFNews.Articles.OnPublished(row, { notify = not opts.catchup }) end
    end
    return id
end

--- Handles one city event now. opts.catchup: replayed at start (no breaking notification).
function Auto.Process(event, opts)
    opts = opts or {}
    if type(event) ~= 'table' or type(event.kind) ~= 'string' or #event.kind > 64 then return end
    if not Config.Auto.enabled then return end
    local mode = Auto.ModeOf(event)
    if mode == 'none' then return end
    if mode == 'auto' and event.bulletin == nil and U.started('pf-services') then
        -- replayed events (GetRecentEvents) do not carry the bulletin flag; the kind does
        local ok, def = pcall(function() return exports['pf-services']:GetEventKind(event.kind) end)
        if ok and type(def) == 'table' then event.bulletin = def.bulletin == true end
    end
    local wantArticle = mode == 'auto'
    local wantLead = mode == 'lead' or (mode == 'auto' and event.bulletin == true and Config.Auto.bulletinLeads)

    local snap = PFNews.Presets.Snapshot(event)
    local done = {}
    if snap.id then
        MySQL.update.await(SQL.claimEvent, { snap.id, snap.kind, mode, U.encode(snap) or '{}', os.time() })
        local row = MySQL.single.await(SQL.getEvent, { snap.id }) or {}
        done.article = tonumber(row.article_id) ~= nil
        done.lead = tonumber(row.lead_id) ~= nil
    else
        local sig = ('%s|%s|%s'):format(snap.kind, tostring(snap.at), tostring(snap.headline))
        if seenNoId[sig] then return end
        seenNoId[sig] = true
        print(('^3[pf-news]^7 city event %s has no id; it is handled once in this session only'):format(snap.kind))
    end

    local result = {}
    if wantArticle and not done.article then result.article = publishArticle(snap, opts) end
    if wantLead and not done.lead then result.lead = PFNews.Leads.FromEvent(snap) end
    return result
end

local function drain()
    if draining then return end
    draining = true
    while #queue > 0 do
        local item = table.remove(queue, 1)
        local ok, err = pcall(Auto.Process, item.event, item.opts)
        if not ok then print('^1[pf-news]^7 city event failed: ' .. tostring(err)) end
    end
    draining = false
end

--- Queues an event (the pf-services:cityEvent handler).
function Auto.Handle(event, opts)
    if type(event) ~= 'table' then return end
    if not PFNews.ready then
        if #waiting < 500 then waiting[#waiting + 1] = { event = event, opts = opts } end
        return
    end
    queue[#queue + 1] = { event = event, opts = opts }
    drain()
end

--- Runs the events that came in while starting, then the ones missed while this resource was down.
function Auto.Start()
    local pending = waiting
    waiting = {}
    for _, item in ipairs(pending) do queue[#queue + 1] = item end
    drain()
    return Auto.CatchUp()
end

--- Replays recent events from the pf-services timeline; anything already handled is skipped by the
--- event record, so this only fills gaps.
function Auto.CatchUp()
    if not U.started('pf-services') or (Config.Auto.catchupSeconds or 0) <= 0 then return 0 end
    local ok, list = pcall(function()
        return exports['pf-services']:GetRecentEvents({ since = os.time() - Config.Auto.catchupSeconds, limit = 200 })
    end)
    if not ok or type(list) ~= 'table' then return 0 end
    local n = 0
    for i = #list, 1, -1 do   -- newest first from pf-services; replay oldest first
        local ev = list[i]
        if type(ev) == 'table' and ev.id and (ev.news == 'auto' or ev.news == 'lead' or (Config.Auto.modes or {})[ev.kind]) then
            queue[#queue + 1] = { event = ev, opts = { catchup = true } }
            n = n + 1
        end
    end
    drain()
    return n
end

function Auto.__reset() queue, draining, waiting, seenNoId = {}, false, {}, {} end
