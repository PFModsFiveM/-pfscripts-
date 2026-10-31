-- Articles: reporter stories (draft -> review -> published -> retracted) and City Desk articles.
-- Every state change is one conditional UPDATE, so two editors can never publish or retract the
-- same article twice. Readers only ever see published articles.

PFNews = PFNews or {}
PFNews.SQL = PFNews.SQL or {}
local U = PFNews.U
local SQL = PFNews.SQL
local A = {}
PFNews.Articles = A

local COLS = [[id, title, summary, body, category, images, author_cid, author_name, status, auto, event_id, preset_id, group_key,
 UNIX_TIMESTAMP(group_until) AS group_until, breaking, pinned, views, lead_id, review_note, reviewed_name, retract_note,
 UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(updated_at) AS updated_at, UNIX_TIMESTAMP(submitted_at) AS submitted_at,
 UNIX_TIMESTAMP(published_at) AS published_at, UNIX_TIMESTAMP(retracted_at) AS retracted_at]]
A.COLS = COLS

SQL.getArticle = 'SELECT ' .. COLS .. ' FROM pf_news_articles WHERE id = ?'
SQL.insertDraft = [[INSERT INTO pf_news_articles (title, summary, body, category, images, author_cid, author_name, status, auto, lead_id, breaking, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'draft', 0, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?))]]
SQL.updateArticle = [[UPDATE pf_news_articles SET title = ?, summary = ?, body = ?, category = ?, images = ?, lead_id = ?, breaking = ?,
    updated_at = FROM_UNIXTIME(?), group_until = NULL WHERE id = ? AND status = ?]]
SQL.countOpenDrafts = "SELECT COUNT(*) FROM pf_news_articles WHERE author_cid = ? AND status IN ('draft', 'review')"
SQL.submitArticle = "UPDATE pf_news_articles SET status = 'review', submitted_at = FROM_UNIXTIME(?), review_note = NULL WHERE id = ? AND status = 'draft'"
SQL.publishArticle = [[UPDATE pf_news_articles SET status = 'published', published_at = FROM_UNIXTIME(?), updated_at = FROM_UNIXTIME(?),
    reviewed_by = ?, reviewed_name = ?, review_note = NULL WHERE id = ? AND status IN ('draft', 'review')]]
SQL.rejectArticle = [[UPDATE pf_news_articles SET status = 'draft', review_note = ?, reviewed_by = ?, reviewed_name = ?, updated_at = FROM_UNIXTIME(?)
    WHERE id = ? AND status = 'review']]
SQL.retractArticle = [[UPDATE pf_news_articles SET status = 'retracted', retract_note = ?, retracted_at = FROM_UNIXTIME(?), pinned = 0, group_until = NULL
    WHERE id = ? AND status = 'published']]
SQL.pinArticle = "UPDATE pf_news_articles SET pinned = ? WHERE id = ? AND status = 'published'"
SQL.countPinned = "SELECT COUNT(*) FROM pf_news_articles WHERE status = 'published' AND pinned = 1"
SQL.deleteDraft = "DELETE FROM pf_news_articles WHERE id = ? AND status = 'draft'"
SQL.frontLatest = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE status = 'published' ORDER BY published_at DESC, id DESC LIMIT %d"
SQL.frontPinned = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE status = 'published' AND pinned = 1 ORDER BY published_at DESC, id DESC LIMIT %d"
SQL.frontBreaking = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE status = 'published' AND breaking = 1 AND published_at >= FROM_UNIXTIME(?) ORDER BY published_at DESC, id DESC LIMIT 3"
SQL.listCategory = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE status = 'published' AND category = ? ORDER BY published_at DESC, id DESC LIMIT %d OFFSET %d"
SQL.listAll = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE status = 'published' ORDER BY published_at DESC, id DESC LIMIT %d OFFSET %d"
SQL.search = 'SELECT ' .. COLS .. [[ FROM pf_news_articles WHERE status = 'published' AND (title LIKE ? OR summary LIKE ? OR body LIKE ?)
    ORDER BY published_at DESC, id DESC LIMIT 30]]
SQL.insertView = 'INSERT IGNORE INTO pf_news_views (article_id, citizenid, viewed_at) VALUES (?, ?, FROM_UNIXTIME(?))'
SQL.addView = 'UPDATE pf_news_articles SET views = views + 1 WHERE id = ?'
SQL.byAuthor = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE author_cid = ? AND status IN ('draft', 'review') ORDER BY id DESC LIMIT 50"
SQL.myPublished = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE author_cid = ? AND status IN ('published', 'retracted') ORDER BY id DESC LIMIT 20"
SQL.reviewQueue = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE status = 'review' ORDER BY submitted_at ASC, id ASC LIMIT 50"
SQL.recentPublished = 'SELECT ' .. COLS .. " FROM pf_news_articles WHERE status IN ('published', 'retracted') ORDER BY COALESCE(published_at, created_at) DESC, id DESC LIMIT 30"
SQL.statsToday = "SELECT COUNT(*) FROM pf_news_articles WHERE status = 'published' AND published_at >= FROM_UNIXTIME(?)"
SQL.statsMine = "SELECT COUNT(*) AS n, COALESCE(SUM(views), 0) AS views FROM pf_news_articles WHERE author_cid = ? AND status = 'published'"

local function norm(r)
    if type(r) ~= 'table' then return nil end
    r.id = tonumber(r.id)
    r.auto = U.bool(r.auto)
    r.breaking = U.bool(r.breaking)
    r.pinned = U.bool(r.pinned)
    r.views = tonumber(r.views) or 0
    r.event_id = tonumber(r.event_id)
    r.lead_id = tonumber(r.lead_id)
    for _, k in ipairs({ 'group_until', 'created_at', 'updated_at', 'submitted_at', 'published_at', 'retracted_at' }) do r[k] = tonumber(r[k]) end
    r.images = U.decode(r.images, {})
    if type(r.images) ~= 'table' then r.images = {} end
    return r
end
A.norm = norm

local function rows(list)
    local out = {}
    for _, r in ipairs(list or {}) do out[#out + 1] = norm(r) end
    return out
end

function A.Get(id)
    id = U.int(id, 1)
    if not id then return nil end
    return norm(MySQL.single.await(SQL.getArticle, { id }))
end

--- What readers see of an article (no citizen ids, no notes).
function A.PublicView(r, full)
    local v = {
        id = r.id, title = r.title, summary = r.summary, category = r.category, categoryLabel = U.categoryLabel(r.category),
        author = r.author_name, auto = r.auto, breaking = r.breaking, pinned = r.pinned, views = r.views,
        publishedAt = r.published_at, updatedAt = r.updated_at, image = r.images[1],
    }
    if full then v.body = r.body; v.images = r.images end
    return v
end

--- What the newsroom sees (status, notes; `mine` instead of the author's citizen id).
function A.EditorView(r, cid, full)
    local v = A.PublicView(r, full)
    v.status = r.status
    v.mine = cid ~= nil and r.author_cid == cid
    v.leadId = r.lead_id
    v.reviewNote = r.review_note
    v.reviewedBy = r.reviewed_name
    v.retractNote = r.retract_note
    v.createdAt = r.created_at
    v.submittedAt = r.submitted_at
    v.presetId = r.preset_id
    return v
end

local function views(list, cid)
    local out = {}
    for _, r in ipairs(list) do out[#out + 1] = cid and A.EditorView(r, cid) or A.PublicView(r) end
    return out
end
A.views = views

-- ── reader side ─────────────────────────────────────────────────────

local front = nil

function A.Invalidate() front = nil end

function A.Front()
    local now = os.time()
    if front and now - front.at < (Config.Reader.cacheSeconds or 10) then return front.data end
    local R = Config.Reader
    local data = {
        latest = views(rows(MySQL.query.await(SQL.frontLatest:format(R.latest or 20)))),
        pinned = views(rows(MySQL.query.await(SQL.frontPinned:format(R.pinnedMax or 4)))),
        breaking = views(rows(MySQL.query.await(SQL.frontBreaking, { now - (R.breakingHours or 6) * 3600 }))),
        categories = Config.Categories,
        ads = PFNews.Ads and PFNews.Ads.Active() or {},
    }
    front = { at = now, data = data }
    return data
end

function A.List(category, page)
    page = U.int(page, 0, 50) or 0
    local size = Config.Limits.pageSize or 20
    local list
    if type(category) == 'string' and category ~= '' then
        if not U.categoryOk(category) then return { ok = false, error = 'bad_category' } end
        list = MySQL.query.await(SQL.listCategory:format(size + 1, page * size), { category })
    else
        list = MySQL.query.await(SQL.listAll:format(size + 1, page * size))
    end
    list = rows(list)
    local more = #list > size
    if more then list[#list] = nil end
    return { ok = true, articles = views(list), page = page, more = more }
end

function A.Search(q)
    q = U.line(q, Config.Limits.searchMax or 60)
    if not q or U.len(q) < (Config.Limits.searchMin or 2) then return { ok = false, error = 'query_too_short' } end
    local like = U.likeTerm(q)
    return { ok = true, query = q, articles = views(rows(MySQL.query.await(SQL.search, { like, like, like }))) }
end

--- Opens an article for a reader. Each citizen counts once per article (pf_news_views), and an
--- author reading their own article does not count.
function A.View(src, id)
    local r = A.Get(id)
    if not r or r.status ~= 'published' then return { ok = false, error = 'not_found' } end
    local cid = U.cidOf(U.player(src))
    if cid and cid ~= r.author_cid then
        local n = U.affected(MySQL.update.await(SQL.insertView, { r.id, cid, os.time() }))
        if n == 1 then
            MySQL.update.await(SQL.addView, { r.id })
            r.views = r.views + 1
        end
    end
    return { ok = true, article = A.PublicView(r, true) }
end

-- ── newsroom side ───────────────────────────────────────────────────

local function contentOf(p)
    local L = Config.Limits
    local title = U.line(p.title, L.titleMax or 120)
    if not title or U.len(title) < (L.titleMin or 6) then return nil, 'title_too_short' end
    local summary = U.line(p.summary, L.summaryMax or 280)
    local body = U.text(p.body, L.bodyMax or 8000) or ''
    local category = (type(p.category) == 'string' and U.categoryOk(p.category)) and p.category or Config.DefaultCategory
    local images, err = U.images(p.images)
    if not images then return nil, err end
    return { title = title, summary = summary, body = body, category = category, images = images }
end

local function readyToPublish(r)
    if not r.title or U.len(r.title) < (Config.Limits.titleMin or 6) then return false, 'title_too_short' end
    if U.len(r.body or '') < (Config.Limits.bodyMin or 40) then return false, 'body_too_short' end
    return true
end

--- Creates or updates a draft. Reporters edit their own drafts; editors edit any draft, anything in
--- review and published articles (corrections). Only editors may set the breaking flag.
function A.Save(src, p)
    local Player, job = U.reporter(src)
    if not Player or not U.hasRole(job, 'write') then return { ok = false, error = 'not_authorized' } end
    if type(p) ~= 'table' then return { ok = false, error = 'bad_request' } end
    local cid = U.cidOf(Player)
    local editor = U.hasRole(job, 'editor')
    local c, err = contentOf(p)
    if not c then return { ok = false, error = err } end

    local leadId
    if p.leadId ~= nil and p.leadId ~= '' and p.leadId ~= false then
        leadId = U.int(p.leadId, 1)
        if not leadId then return { ok = false, error = 'bad_request' } end
    end
    local now = os.time()
    local id = p.id ~= nil and U.int(p.id, 1) or nil
    if p.id ~= nil and not id then return { ok = false, error = 'bad_request' } end

    if id then
        local r = A.Get(id)
        if not r or r.auto and not editor then return { ok = false, error = 'not_found' } end
        local mine = r.author_cid == cid
        if r.status == 'draft' or r.status == 'review' then
            if not mine and not editor then return { ok = false, error = 'not_authorized' } end
        elseif r.status == 'published' then
            if not editor then return { ok = false, error = 'published_locked' } end
        else
            return { ok = false, error = 'retracted' }
        end
        -- someone else's article keeps its own lead; a changed lead must be claimed by the author
        if not mine then leadId = r.lead_id
        elseif leadId and leadId ~= r.lead_id then
            local lead = PFNews.Leads.Get(leadId)
            if not lead or lead.status ~= 'claimed' or lead.claimed_cid ~= cid then return { ok = false, error = 'lead_not_claimed' } end
        end
        local breaking = r.breaking
        if editor then breaking = p.breaking == true end
        local n = U.affected(MySQL.update.await(SQL.updateArticle, {
            c.title, c.summary, c.body, c.category, U.encode(c.images), leadId, breaking and 1 or 0, now, id, r.status,
        }))
        if n ~= 1 then return { ok = false, error = 'changed' } end
        if r.status == 'published' then
            A.Invalidate()
            U.broadcast('updated', { id = id })
        end
        return { ok = true, id = id, status = r.status }
    end

    if leadId then
        local lead = PFNews.Leads.Get(leadId)
        if not lead or lead.status ~= 'claimed' or lead.claimed_cid ~= cid then return { ok = false, error = 'lead_not_claimed' } end
    end
    local open = tonumber(MySQL.scalar.await(SQL.countOpenDrafts, { cid })) or 0
    if open >= (Config.Limits.draftsPerAuthor or 25) then return { ok = false, error = 'too_many_drafts' } end
    local newId = MySQL.insert.await(SQL.insertDraft, {
        c.title, c.summary, c.body, c.category, U.encode(c.images), cid, U.nameOf(Player), leadId,
        (editor and p.breaking == true) and 1 or 0, now, now,
    })
    newId = tonumber(newId)
    if not newId or newId < 1 then return { ok = false, error = 'db_error' } end
    return { ok = true, id = newId, status = 'draft' }
end

--- Publishes an article that is in draft or review: the author with the publish grade, or an editor.
function A.Publish(src, id)
    local Player, job = U.reporter(src)
    if not Player or not U.hasRole(job, 'write') then return { ok = false, error = 'not_authorized' } end
    local r = A.Get(id)
    if not r or r.auto then return { ok = false, error = 'not_found' } end
    if r.status ~= 'draft' and r.status ~= 'review' then return { ok = false, error = 'not_publishable' } end
    local cid = U.cidOf(Player)
    local mine = r.author_cid == cid
    local editor = U.hasRole(job, 'editor')
    if not ((mine and U.hasRole(job, 'publish')) or editor) then return { ok = false, error = 'needs_review' } end
    local ok, why = readyToPublish(r)
    if not ok then return { ok = false, error = why } end
    local now = os.time()
    local n = U.affected(MySQL.update.await(SQL.publishArticle, {
        now, now, (not mine) and cid or nil, (not mine) and U.nameOf(Player) or nil, r.id,
    }))
    if n ~= 1 then return { ok = false, error = 'changed' } end
    r.status, r.published_at = 'published', now
    local covered = false
    if r.lead_id then covered = PFNews.Leads.Cover(r.lead_id, r.author_cid, r.id) end
    local pay = PFNews.Pay.OnPublished(r, covered)
    A.OnPublished(r, { notify = true })
    if not mine and r.author_cid then
        pcall(function() exports['pf-devices']:PushToCitizen(r.author_cid, 'newsroom', 'refresh', { what = 'published', id = r.id }) end)
    end
    return { ok = true, id = r.id, status = 'published', covered = covered, pay = pay }
end

--- Reporter: submit a draft. With the publish grade the draft is published straight away.
function A.Submit(src, id)
    local Player, job = U.reporter(src)
    if not Player or not U.hasRole(job, 'write') then return { ok = false, error = 'not_authorized' } end
    local r = A.Get(id)
    local cid = U.cidOf(Player)
    if not r or r.author_cid ~= cid then return { ok = false, error = 'not_found' } end
    if r.status ~= 'draft' then return { ok = false, error = 'not_draft' } end
    local ok, why = readyToPublish(r)
    if not ok then return { ok = false, error = why } end
    if U.hasRole(job, 'publish') then return A.Publish(src, id) end
    local n = U.affected(MySQL.update.await(SQL.submitArticle, { os.time(), r.id }))
    if n ~= 1 then return { ok = false, error = 'changed' } end
    U.pushNewsroom('refresh', { what = 'review', id = r.id })
    return { ok = true, id = r.id, status = 'review' }
end

local function editorOnly(src)
    local Player, job = U.reporter(src)
    if not Player or not U.hasRole(job, 'editor') then return nil end
    return Player, job
end

--- Editor: send an article in review back to its author with a note.
function A.Reject(src, id, note)
    local Player = editorOnly(src)
    if not Player then return { ok = false, error = 'not_authorized' } end
    local r = A.Get(id)
    if not r or r.status ~= 'review' then return { ok = false, error = 'not_in_review' } end
    note = U.line(note, Config.Limits.noteMax or 300)
    if not note then return { ok = false, error = 'note_required' } end
    local n = U.affected(MySQL.update.await(SQL.rejectArticle, { note, U.cidOf(Player), U.nameOf(Player), os.time(), r.id }))
    if n ~= 1 then return { ok = false, error = 'changed' } end
    if r.author_cid then
        pcall(function() exports['pf-devices']:PushToCitizen(r.author_cid, 'newsroom', 'refresh', { what = 'rejected', id = r.id }) end)
        local Author = U.QB().Functions.GetPlayerByCitizenId(r.author_cid)
        if Author then U.notify(Author.PlayerData.source, ('Your article "%s" needs changes: %s'):format(r.title, note), 'error', 8000) end
    end
    return { ok = true, id = r.id, status = 'draft' }
end

--- Editor: take a published article down (an unpaid bonus for it is cancelled).
function A.Retract(src, id, note)
    local Player = editorOnly(src)
    if not Player then return { ok = false, error = 'not_authorized' } end
    local r = A.Get(id)
    if not r or r.status ~= 'published' then return { ok = false, error = 'not_published' } end
    note = U.line(note, Config.Limits.noteMax or 300)
    if not note then return { ok = false, error = 'note_required' } end
    local n = U.affected(MySQL.update.await(SQL.retractArticle, { note, os.time(), r.id }))
    if n ~= 1 then return { ok = false, error = 'changed' } end
    PFNews.Pay.Cancel(r.id)
    A.Invalidate()
    U.broadcast('retracted', { id = r.id })
    return { ok = true, id = r.id, status = 'retracted' }
end

function A.Pin(src, id, pinned)
    local Player = editorOnly(src)
    if not Player then return { ok = false, error = 'not_authorized' } end
    local r = A.Get(id)
    if not r or r.status ~= 'published' then return { ok = false, error = 'not_published' } end
    pinned = pinned == true
    if pinned and not r.pinned then
        local count = tonumber(MySQL.scalar.await(SQL.countPinned)) or 0
        if count >= (Config.Reader.pinnedMax or 4) then return { ok = false, error = 'too_many_pinned' } end
    end
    MySQL.update.await(SQL.pinArticle, { pinned and 1 or 0, r.id })
    A.Invalidate()
    U.broadcast('updated', { id = r.id })
    return { ok = true, id = r.id, pinned = pinned }
end

--- Deletes a draft: the author's own, or any draft for an editor.
function A.Delete(src, id)
    local Player, job = U.reporter(src)
    if not Player then return { ok = false, error = 'not_authorized' } end
    local r = A.Get(id)
    if not r or r.status ~= 'draft' then return { ok = false, error = 'not_found' } end
    if r.author_cid ~= U.cidOf(Player) and not U.hasRole(job, 'editor') then return { ok = false, error = 'not_authorized' } end
    local n = U.affected(MySQL.update.await(SQL.deleteDraft, { r.id }))
    return { ok = n == 1, error = n == 1 and nil or 'changed' }
end

--- Everything that follows a first publication: the front page, open readers, breaking alerts.
local lastBreakingNotice = 0
function A.OnPublished(r, opts)
    opts = opts or {}
    A.Invalidate()
    local view = A.PublicView(r)
    U.broadcast('published', view)
    U.pushNewsroom('refresh', { what = 'published', id = r.id })
    if r.breaking and opts.notify ~= false then A.NotifyBreaking(r) end
end

--- Tells online players who installed the News app about a breaking story (rate limited).
function A.NotifyBreaking(r)
    if not Config.Breaking.notify then return 0 end
    local now = os.time()
    if now - lastBreakingNotice < (Config.Breaking.cooldownSeconds or 60) then return 0 end
    lastBreakingNotice = now
    if not U.started('pf-devices') then return 0 end
    local n = 0
    for src, Player in pairs(U.QB().Functions.GetQBPlayers() or {}) do
        local cid = U.cidOf(Player)
        local target = Player.PlayerData and Player.PlayerData.source or src
        local ok, installed = pcall(function() return exports['pf-devices']:IsAppInstalled(cid, 'news') end)
        if cid and ok and installed == true then
            U.notify(target, '📰 BREAKING: ' .. r.title, 'primary', Config.Breaking.duration or 9000)
            pcall(function() exports['pf-devices']:Push(target, 'news', 'breaking', { id = r.id, title = r.title }) end)
            n = n + 1
        end
    end
    return n
end

function A.__reset() front = nil; lastBreakingNotice = 0 end

-- newsroom lists
function A.Mine(cid) return views(rows(MySQL.query.await(SQL.byAuthor, { cid })), cid) end
function A.MyPublished(cid) return views(rows(MySQL.query.await(SQL.myPublished, { cid })), cid) end
function A.ReviewQueue(cid) return views(rows(MySQL.query.await(SQL.reviewQueue)), cid) end
function A.RecentPublished(cid) return views(rows(MySQL.query.await(SQL.recentPublished)), cid) end

function A.Stats(cid)
    local midnight = os.time() - (os.time() % 86400)
    local mine = MySQL.single.await(SQL.statsMine, { cid }) or {}
    return {
        publishedToday = tonumber(MySQL.scalar.await(SQL.statsToday, { midnight })) or 0,
        myPublished = tonumber(mine.n) or 0,
        myViews = tonumber(mine.views) or 0,
    }
end
