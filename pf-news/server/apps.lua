-- pf-devices apps:
--   news      the reader (installable from the App Store, tablet + computer)
--   news.ls   the website: the SAME module (html/news_ui.js) and the SAME handlers, open to anyone
--   newsroom  the reporters' app (job reporter): leads, editor, review queue, ads moderation
-- Every handler checks the player itself; pf-devices only decides who may open the app.

PFNews = PFNews or {}
local U = PFNews.U

local function payload(p) return type(p) == 'table' and p or {} end

-- ── reader (app + site) ─────────────────────────────────────────────
local Reader = {
    front = function(src)
        local data = PFNews.Articles.Front()
        return { ok = true, front = data, canAdvertise = Config.Ads.enabled and #PFNews.Ads.Eligible(src) > 0 }
    end,
    list = function(_, p)
        p = payload(p)
        return PFNews.Articles.List(p.category, p.page)
    end,
    article = function(src, p) return PFNews.Articles.View(src, payload(p).id) end,
    search = function(_, p) return PFNews.Articles.Search(payload(p).q) end,
    ads = function() return { ok = true, ads = PFNews.Ads.Active() } end,
    adOptions = function(src)
        local list = {}
        for _, b in ipairs(PFNews.Ads.Eligible(src)) do list[#list + 1] = { id = b.id, name = b.name, via = b.via } end
        return {
            ok = true, enabled = Config.Ads.enabled, businesses = list, durations = PFNews.Ads.Durations(),
            textMin = Config.Ads.textMin, textMax = Config.Ads.textMax, mine = PFNews.Ads.Mine(src),
        }
    end,
    buyAd = function(src, p) return PFNews.Ads.Buy(src, payload(p)) end,
}
PFNews.ReaderHandlers = Reader

-- ── newsroom ────────────────────────────────────────────────────────

local function staff()
    local field = {}
    if U.started('pfm-newsjob') then
        local ok, res = pcall(function() return exports['pfm-newsjob']:GetFieldStatus() end)
        if ok and type(res) == 'table' then field = res end
    end
    local out = {}
    for _, Player in pairs(U.QB().Functions.GetQBPlayers() or {}) do
        local job = Player.PlayerData and Player.PlayerData.job
        if job and job.name == Config.Job then
            local cid = U.cidOf(Player)
            local f = field[cid]
            out[#out + 1] = {
                name = U.nameOf(Player), grade = type(job.grade) == 'table' and job.grade.name or nil,
                onduty = job.onduty == true, field = type(f) == 'table' and (f.label or f.model) or nil,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.onduty ~= b.onduty then return a.onduty end
        return a.name < b.name
    end)
    return out
end

local function me(src)
    local Player, job = U.reporter(src)
    if not Player then return nil end
    return Player, job, U.cidOf(Player)
end

local function guard(fn)
    return function(src, p)
        local Player, job, cid = me(src)
        if not Player then return { ok = false, error = 'not_authorized' } end
        return fn(src, payload(p), Player, job, cid)
    end
end

local Newsroom = {
    dashboard = guard(function(src, _, Player, job, cid)
        local roles = U.roles(job)
        local leads = PFNews.Leads.Active(cid)
        local claimed = {}
        for _, l in ipairs(leads) do if l.mine then claimed[#claimed + 1] = l end end
        return {
            ok = true,
            me = { name = U.nameOf(Player), grade = type(job.grade) == 'table' and job.grade.name or nil, onduty = job.onduty == true, roles = roles },
            staff = staff(),
            leads = leads,
            myLeads = claimed,
            drafts = PFNews.Articles.Mine(cid),
            myPublished = PFNews.Articles.MyPublished(cid),
            review = roles.editor and PFNews.Articles.ReviewQueue(cid) or {},
            recent = PFNews.Articles.RecentPublished(cid),
            stats = PFNews.Articles.Stats(cid),
            payouts = PFNews.Pay.Mine(cid),
            categories = Config.Categories,
            limits = {
                titleMin = Config.Limits.titleMin, titleMax = Config.Limits.titleMax, summaryMax = Config.Limits.summaryMax,
                bodyMin = Config.Limits.bodyMin, bodyMax = Config.Limits.bodyMax, images = Config.Limits.images,
                payMinBody = Config.Pay.minBodyLength, perArticle = Config.Pay.perArticle, leadBonus = Config.Pay.leadBonus,
            },
            requireOnDuty = Config.Leads.requireOnDuty,
        }
    end),
    getArticle = guard(function(_, p, _, job, cid)
        local r = PFNews.Articles.Get(p.id)
        if not r then return { ok = false, error = 'not_found' } end
        -- your own work, anything published, or anything for an editor
        if r.author_cid ~= cid and r.status ~= 'published' and r.status ~= 'retracted' and not U.hasRole(job, 'editor') then
            return { ok = false, error = 'not_found' }
        end
        return { ok = true, article = PFNews.Articles.EditorView(r, cid, true), canEdit = (r.author_cid == cid and (r.status == 'draft' or r.status == 'review')) or U.hasRole(job, 'editor') }
    end),
    save = function(src, p) return PFNews.Articles.Save(src, payload(p)) end,
    submit = function(src, p) return PFNews.Articles.Submit(src, payload(p).id) end,
    publish = function(src, p) return PFNews.Articles.Publish(src, payload(p).id) end,
    reject = function(src, p) p = payload(p) return PFNews.Articles.Reject(src, p.id, p.note) end,
    retract = function(src, p) p = payload(p) return PFNews.Articles.Retract(src, p.id, p.note) end,
    pin = function(src, p) p = payload(p) return PFNews.Articles.Pin(src, p.id, p.pinned == true) end,
    delete = function(src, p) return PFNews.Articles.Delete(src, payload(p).id) end,
    claimLead = function(src, p) return PFNews.Leads.Claim(src, payload(p).id) end,
    releaseLead = function(src, p) return PFNews.Leads.Release(src, payload(p).id) end,
    leadWaypoint = function(src, p) return PFNews.Leads.Waypoint(src, payload(p).id) end,
    dismissLead = function(src, p) return PFNews.Leads.Dismiss(src, payload(p).id) end,
    ads = guard(function(_, _, _, job)
        return { ok = true, ads = PFNews.Ads.Newsroom(), canReject = U.hasRole(job, 'ads') }
    end),
    rejectAd = function(src, p) p = payload(p) return PFNews.Ads.Reject(src, p.id, p.note) end,
}
PFNews.NewsroomHandlers = Newsroom

function PFNews.RegisterApps()
    if not U.started('pf-devices') then return false end
    local devices = exports['pf-devices']
    local entry, styles = 'html/news_ui.js', { 'html/news.css' }
    devices:RegisterApp({
        id = 'news', name = 'Weazel News', icon = '📰', entry = entry, styles = styles,
        devices = { 'tablet', 'computer' }, category = 'media', order = 30,
        access = { installable = true },
        store = { description = 'Los Santos news as it happens: City Hall decisions, breaking alerts, crime, business and local ads.', publisher = 'Weazel News' },
        description = 'City news, breaking alerts and local ads',
        window = { width = 1040, height = 720 },
    })
    devices:RegisterAppHandlers('news', Reader)
    devices:RegisterSite({
        host = U.SITE_HOST, name = 'Weazel News', icon = '📰', entry = entry, styles = styles,
        access = { anyone = true }, description = 'The news of Los Santos',
    })
    for method, fn in pairs(Reader) do devices:RegisterSiteHandler(U.SITE_HOST, method, fn) end
    devices:RegisterApp({
        id = 'newsroom', name = 'Newsroom', icon = '🗞️', entry = 'html/newsroom.js', styles = styles,
        devices = { 'tablet', 'computer' }, category = 'jobs', order = 12,
        access = { jobs = { [Config.Job] = 0 } },
        description = 'Leads, stories, review and ads for Weazel News',
        window = { width = 1100, height = 740 },
    })
    devices:RegisterAppHandlers('newsroom', Newsroom)
    return true
end
