-- PF News: start-up, the city event listener, exports and the sweeps.

PFNews = PFNews or {}
local U = PFNews.U
PFNews.ready = false

-- City events are server-only (pf-services raises them with TriggerEvent).
AddEventHandler('pf-services:cityEvent', function(event)
    PFNews.Auto.Handle(event)
end)

-- the newsroom lists who is on duty (pfm-newsjob duty point, or any pfm-core duty change)
AddEventHandler('QBCore:Server:SetDuty', function(src)
    if PFNews.ready and U.reporter(src) then U.pushNewsroom('refresh', { what = 'staff' }) end
end)

function PFNews.Sweep()
    for _, fn in ipairs({ PFNews.Leads.Sweep, PFNews.Ads.Sweep, PFNews.Pay.Sweep }) do
        local ok, err = pcall(fn)
        if not ok then print('^1[pf-news]^7 sweep failed: ' .. tostring(err)) end
    end
end

function PFNews.Start()
    local ok, res, err = pcall(function() return exports['pfm-core']:RunMigrations(GetCurrentResourceName(), PFNews.Migrations) end)
    if not ok or res == false then
        print('^1[pf-news]^7 migrations failed: ' .. tostring(ok and err or res))
        return false
    end
    PFNews.ready = true
    if U.started('pfm-banking') then
        pcall(function() exports['pfm-banking']:EnsureSocietyAccount(Config.CompanyAccount or Config.Job) end)
    end
    PFNews.RegisterApps()
    PFNews.Auto.Start()
    return true
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        CreateThread(function() PFNews.Start() end)
    elseif resource == 'pf-devices' then
        PFNews.RegisterApps()
    end
end)

-- pf-devices raises this when it (re)starts
AddEventHandler('pf-devices:server:ready', function()
    PFNews.RegisterApps()
end)

CreateThread(function()
    while true do
        Wait(60000)
        if PFNews.ready then PFNews.Sweep() end
    end
end)

-- ── exports ─────────────────────────────────────────────────────────
-- The latest published articles (public view), e.g. for a TV ticker or a loading screen.
exports('GetLatest', function(limit)
    local front = PFNews.Articles.Front()
    local out = {}
    for i, a in ipairs(front.latest or {}) do
        if i > (tonumber(limit) or 10) then break end
        out[#out + 1] = a
    end
    return out
end)
exports('GetArticle', function(id)
    local r = PFNews.Articles.Get(id)
    if not r or r.status ~= 'published' then return nil end
    return PFNews.Articles.PublicView(r, true)
end)
exports('GetBreaking', function() return PFNews.Articles.Front().breaking or {} end)
-- Server code may hand pf-news an event that did not come through pf-services (same shape).
exports('HandleCityEvent', function(event) PFNews.Auto.Handle(event) end)

-- A deleted reporter: unfinished drafts go, published articles keep their byline (the paper's
-- archive) but lose the link to the character, and claimed leads go back to the newsroom.
PFNews.CharacterCleanupQueries = {
    "DELETE FROM pf_news_articles WHERE author_cid = ? AND status IN ('draft', 'review')",
    'UPDATE pf_news_articles SET author_cid = NULL WHERE author_cid = ?',
    [[UPDATE pf_news_leads SET status = 'open', claimed_cid = NULL, claimed_name = NULL, claimed_at = NULL
        WHERE claimed_cid = ? AND status = 'claimed']],
    'DELETE FROM pf_news_views WHERE citizenid = ?',
}

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return end
    for _, q in ipairs(PFNews.CharacterCleanupQueries) do
        pcall(function() MySQL.query.await(q, { citizenid }) end)
    end
end)
