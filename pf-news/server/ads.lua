-- Ads: a business buys a slot on the news front page (app and site).
-- Who may buy for which business is decided here, never by the client:
--   * the boss of a job buys for that job, paid from society:<job>;
--   * the owner of a business on the pf-government registry (owner_id = their citizen id, or
--     job:<name> for a boss of that job) buys for it, paid from the business's own account_ref.
-- Payment is one ledger transfer from the business account to society:<Config.CompanyAccount>
-- with key pf-news:ad:<ad id>; a rejected ad is refunded in full with key pf-news:ad:<ad id>:refund.

PFNews = PFNews or {}
PFNews.SQL = PFNews.SQL or {}
local U = PFNews.U
local SQL = PFNews.SQL
local Ads = {}
PFNews.Ads = Ads

local COLS = [[id, business_id, business_name, account_ref, buyer_cid, buyer_name, text, image_url, duration_id, hours, price, status,
 paid_tx, error, refund_state, refund_tx, refund_attempts, reject_note, rejected_name, UNIX_TIMESTAMP(created_at) AS created_at,
 UNIX_TIMESTAMP(starts_at) AS starts_at, UNIX_TIMESTAMP(ends_at) AS ends_at]]

SQL.getAd = 'SELECT ' .. COLS .. ' FROM pf_news_ads WHERE id = ?'
SQL.registryOwned = [[SELECT business_id, business_name, account_ref, COALESCE(business_status, 'active') AS business_status
    FROM pf_gov_businesses WHERE owner_id = ? OR owner_id = ?]]
SQL.registryOwnedOld = 'SELECT business_id, business_name, account_ref FROM pf_gov_businesses WHERE owner_id = ? OR owner_id = ?'
SQL.countActiveAds = "SELECT COUNT(*) FROM pf_news_ads WHERE status IN ('pending', 'active') AND (ends_at IS NULL OR ends_at > FROM_UNIXTIME(?))"
SQL.countBusinessAds = "SELECT COUNT(*) FROM pf_news_ads WHERE business_id = ? AND status IN ('pending', 'active') AND (ends_at IS NULL OR ends_at > FROM_UNIXTIME(?))"
SQL.insertAd = [[INSERT INTO pf_news_ads (business_id, business_name, account_ref, buyer_cid, buyer_name, text, image_url, duration_id, hours, price, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', FROM_UNIXTIME(?))]]
SQL.activateAd = [[UPDATE pf_news_ads SET status = 'active', paid_tx = ?, starts_at = FROM_UNIXTIME(?), ends_at = FROM_UNIXTIME(?)
    WHERE id = ? AND status = 'pending']]
SQL.failAd = "UPDATE pf_news_ads SET status = 'failed', error = ? WHERE id = ? AND status = 'pending'"
SQL.rejectAd = [[UPDATE pf_news_ads SET status = 'rejected', reject_note = ?, rejected_by = ?, rejected_name = ?, rejected_at = FROM_UNIXTIME(?),
    refund_state = 'pending' WHERE id = ? AND status = 'active']]
SQL.refundDone = "UPDATE pf_news_ads SET refund_state = 'done', refund_tx = ? WHERE id = ? AND refund_state = 'pending'"
SQL.refundRetry = "UPDATE pf_news_ads SET refund_attempts = refund_attempts + 1 WHERE id = ? AND refund_state = 'pending' AND refund_attempts = ?"
SQL.activeAds = 'SELECT ' .. COLS .. " FROM pf_news_ads WHERE status = 'active' AND ends_at > FROM_UNIXTIME(?) ORDER BY starts_at DESC, id DESC LIMIT %d"
SQL.adsFor = 'SELECT ' .. COLS .. ' FROM pf_news_ads WHERE business_id IN (%s) ORDER BY id DESC LIMIT 30'
SQL.expireAds = "UPDATE pf_news_ads SET status = 'expired' WHERE status = 'active' AND ends_at <= FROM_UNIXTIME(?)"
SQL.stuckAds = "SELECT id FROM pf_news_ads WHERE status = 'pending' AND created_at < FROM_UNIXTIME(?) LIMIT 20"
SQL.pendingRefunds = 'SELECT ' .. COLS .. " FROM pf_news_ads WHERE refund_state = 'pending' LIMIT 20"
SQL.newsroomAds = 'SELECT ' .. COLS .. " FROM pf_news_ads WHERE status IN ('active', 'rejected', 'expired') ORDER BY id DESC LIMIT 40"

local function norm(r)
    if type(r) ~= 'table' then return nil end
    for _, k in ipairs({ 'id', 'hours', 'price', 'created_at', 'starts_at', 'ends_at', 'refund_attempts' }) do r[k] = tonumber(r[k]) end
    return r
end

function Ads.Get(id)
    id = U.int(id, 1)
    return id and norm(MySQL.single.await(SQL.getAd, { id })) or nil
end

function Ads.KeyFor(id) return 'pf-news:ad:' .. tostring(id) end
-- A ledger key whose transfer failed stays failed, so each retry after a recorded failure gets its
-- own key (:refund, :refund:1, ...). The attempt only moves on after a failure, so a refund that
-- went through before a crash is found again under the same key and never paid twice.
function Ads.RefundKeyFor(id, attempt)
    attempt = tonumber(attempt) or 0
    return 'pf-news:ad:' .. tostring(id) .. ':refund' .. (attempt > 0 and (':' .. attempt) or '')
end
local function company() return 'society:' .. (Config.CompanyAccount or Config.Job) end

local function validAccount(ref)
    return type(ref) == 'string' and #ref <= 96 and (ref:match('^society:[%w_%-%.]+$') or ref:match('^acct:%d+$')) ~= nil
end

--- The businesses `src` may buy ads for: list of { id, name, account, via }.
function Ads.Eligible(src)
    local Player = U.player(src)
    if not Player then return {} end
    local cid = U.cidOf(Player)
    local job = Player.PlayerData.job or {}
    local isBoss = job.isboss == true or (type(job.grade) == 'table' and job.grade.isboss == true)
    local excluded = Config.Ads.excludedJobs or {}
    local out, seen = {}, {}
    local function add(b)
        if seen[b.id] or seen['acct:' .. b.account] or b.account == company() then return end
        seen[b.id], seen['acct:' .. b.account] = true, true
        out[#out + 1] = b
    end
    if Config.Ads.bossJobs and isBoss and type(job.name) == 'string' and not excluded[job.name] then
        add({ id = 'job:' .. job.name, name = U.line(job.label, 80) or job.name, account = 'society:' .. job.name, via = 'job' })
    end
    if Config.Ads.registryOwners and cid then
        local jobOwner = (isBoss and type(job.name) == 'string') and ('job:' .. job.name) or '-'
        -- pf_gov_businesses belongs to pf-government; older installs lack business_status
        local ok, list = pcall(MySQL.query.await, SQL.registryOwned, { cid, jobOwner })
        if not ok or list == nil then ok, list = pcall(MySQL.query.await, SQL.registryOwnedOld, { cid, jobOwner }) end
        for _, r in ipairs(ok and type(list) == 'table' and list or {}) do
            if validAccount(r.account_ref) and tostring(r.business_status or 'active') ~= 'closed' and type(r.business_id) == 'string' then
                add({ id = r.business_id, name = U.line(r.business_name, 80) or r.business_id, account = r.account_ref, via = 'registry' })
            end
        end
    end
    return out
end

function Ads.Durations()
    local out = {}
    for _, d in ipairs(Config.Ads.durations or {}) do out[#out + 1] = { id = d.id, label = d.label, hours = d.hours, price = d.price } end
    return out
end

local function durationOf(id)
    for _, d in ipairs(Config.Ads.durations or {}) do if d.id == id then return d end end
    return nil
end

--- Public view (no buyer, no account).
function Ads.View(r)
    return { id = r.id, business = r.business_name, text = r.text, image = r.image_url, endsAt = r.ends_at }
end

--- Newsroom / owner view.
function Ads.FullView(r)
    local v = Ads.View(r)
    v.status, v.price, v.duration, v.buyer = r.status, r.price, r.duration_id, r.buyer_name
    v.startsAt, v.createdAt, v.refund, v.rejectNote, v.rejectedBy, v.error = r.starts_at, r.created_at, r.refund_state, r.reject_note, r.rejected_name, r.error
    return v
end

local activeCache
function Ads.Invalidate() activeCache = nil end

function Ads.Active()
    if not Config.Ads.enabled then return {} end
    local now = os.time()
    if activeCache and now - activeCache.at < (Config.Reader.cacheSeconds or 10) then return activeCache.list end
    local list = {}
    for _, r in ipairs(MySQL.query.await(SQL.activeAds:format(Config.Ads.maxActive or 8), { now }) or {}) do list[#list + 1] = Ads.View(norm(r)) end
    activeCache = { at = now, list = list }
    return list
end

local buying = {}

--- Buys an ad. payload: { businessId, durationId, text, image }.
function Ads.Buy(src, p)
    if not Config.Ads.enabled then return { ok = false, error = 'ads_disabled' } end
    if type(p) ~= 'table' or type(p.businessId) ~= 'string' or #p.businessId > 100 then return { ok = false, error = 'bad_request' } end
    local Player = U.player(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local biz
    for _, b in ipairs(Ads.Eligible(src)) do if b.id == p.businessId then biz = b break end end
    if not biz then return { ok = false, error = 'not_business_owner' } end
    local d = type(p.durationId) == 'string' and durationOf(p.durationId) or nil
    if not d then return { ok = false, error = 'bad_duration' } end
    local text = U.line(p.text, Config.Ads.textMax or 220)
    if not text or U.len(text) < (Config.Ads.textMin or 10) then return { ok = false, error = 'text_too_short' } end
    local image
    if p.image ~= nil and p.image ~= '' then
        image = U.imageUrl(p.image)
        if not image then return { ok = false, error = 'bad_image' } end
    end
    if buying[biz.id] then return { ok = false, error = 'busy' } end
    buying[biz.id] = true
    local ok, res = pcall(function()
        local now = os.time()
        if (tonumber(MySQL.scalar.await(SQL.countActiveAds, { now })) or 0) >= (Config.Ads.maxActive or 8) then return { ok = false, error = 'no_slots' } end
        if (tonumber(MySQL.scalar.await(SQL.countBusinessAds, { biz.id, now })) or 0) >= (Config.Ads.maxPerBusiness or 2) then return { ok = false, error = 'business_limit' } end
        if GetResourceState('pfm-banking') ~= 'started' then return { ok = false, error = 'bank_unavailable' } end
        local okAcc, exists = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(Config.CompanyAccount or Config.Job) end)
        if not okAcc or not exists then return { ok = false, error = 'news_account_missing' } end
        local cid = U.cidOf(Player)
        local id = tonumber(MySQL.insert.await(SQL.insertAd, {
            biz.id, biz.name, biz.account, cid, U.nameOf(Player), text, image, d.id, d.hours, d.price, now,
        }))
        if not id or id < 1 then return { ok = false, error = 'db_error' } end
        local pay = PFPayout.Transfer({
            from = biz.account, to = company(), amount = d.price, key = Ads.KeyFor(id), kind = 'purchase',
            reason = ('Weazel News ad #%d (%s)'):format(id, biz.name), actor = cid,
        })
        if not pay.ok then
            MySQL.update.await(SQL.failAd, { tostring(pay.error or 'payment_failed'):sub(1, 64), id })
            return { ok = false, error = pay.error == 'insufficient_funds' and 'insufficient_funds' or 'payment_failed', id = id }
        end
        MySQL.update.await(SQL.activateAd, { pay.txId, now, now + d.hours * 3600, id })
        Ads.Invalidate()
        PFNews.Articles.Invalidate()
        U.broadcast('ads', { id = id })
        return { ok = true, id = id, price = d.price, endsAt = now + d.hours * 3600 }
    end)
    buying[biz.id] = nil
    if not ok then
        print('^1[pf-news]^7 ad purchase failed: ' .. tostring(res))
        return { ok = false, error = 'server_error' }
    end
    return res
end

--- Pays back a rejected ad (retried by the sweep until it goes through).
function Ads.Refund(r)
    if not r or r.refund_state ~= 'pending' then return false end
    local attempt = tonumber(r.refund_attempts) or 0
    local res = PFPayout.Transfer({
        from = company(), to = r.account_ref, amount = r.price, key = Ads.RefundKeyFor(r.id, attempt), kind = 'refund',
        reason = ('Weazel News ad #%d refund'):format(r.id),
    })
    if res.ok then
        MySQL.update.await(SQL.refundDone, { res.txId, r.id })
        return true
    end
    if res.error ~= 'in_progress' then MySQL.update.await(SQL.refundRetry, { r.id, attempt }) end
    return false
end

--- A reporter with the ads role takes an ad down; the business gets its money back.
function Ads.Reject(src, id, note)
    local Player, job = U.reporter(src)
    if not Player or not U.hasRole(job, 'ads') then return { ok = false, error = 'not_authorized' } end
    id = U.int(id, 1)
    if not id then return { ok = false, error = 'bad_request' } end
    note = U.line(note, Config.Limits.noteMax or 300)
    if not note then return { ok = false, error = 'note_required' } end
    local n = U.affected(MySQL.update.await(SQL.rejectAd, { note, U.cidOf(Player), U.nameOf(Player), os.time(), id }))
    if n ~= 1 then return { ok = false, error = 'not_active' } end
    Ads.Invalidate()
    PFNews.Articles.Invalidate()
    U.broadcast('ads', { id = id })
    local refunded = Ads.Refund(Ads.Get(id))
    return { ok = true, id = id, refunded = refunded, refundPending = not refunded }
end

--- Ads of the businesses the player may buy for (their status, end dates, rejections).
function Ads.Mine(src)
    local list = Ads.Eligible(src)
    if #list == 0 then return {} end
    local marks, params = {}, {}
    for i, b in ipairs(list) do marks[i] = '?'; params[i] = b.id end
    local out = {}
    for _, r in ipairs(MySQL.query.await(SQL.adsFor:format(table.concat(marks, ', ')), params) or {}) do out[#out + 1] = Ads.FullView(norm(r)) end
    return out
end

function Ads.Newsroom()
    local out = {}
    for _, r in ipairs(MySQL.query.await(SQL.newsroomAds) or {}) do out[#out + 1] = Ads.FullView(norm(r)) end
    return out
end

--- Expires finished ads, settles purchases interrupted between payment and activation, retries refunds.
function Ads.Sweep()
    local now = os.time()
    local changed = U.affected(MySQL.update.await(SQL.expireAds, { now })) > 0
    for _, row in ipairs(MySQL.query.await(SQL.stuckAds, { now - 120 }) or {}) do
        local r = Ads.Get(row.id)
        if r and r.status == 'pending' and U.started('pfm-banking') then
            local okTx, tx = pcall(function() return exports['pfm-banking']:GetTransaction(Ads.KeyFor(r.id)) end)
            if okTx then
                if type(tx) == 'table' and tx.state == 'completed' then
                    MySQL.update.await(SQL.activateAd, { tx.tx_id, now, now + (r.hours or 24) * 3600, r.id })
                    changed = true
                elseif tx == nil or (type(tx) == 'table' and (tx.state == 'failed' or tx.state == 'compensated')) then
                    MySQL.update.await(SQL.failAd, { 'not_paid', r.id })
                end
            end
        end
    end
    for _, r in ipairs(MySQL.query.await(SQL.pendingRefunds) or {}) do Ads.Refund(norm(r)) end
    if changed then
        Ads.Invalidate()
        PFNews.Articles.Invalidate()
        U.broadcast('ads', {})
    end
end

function Ads.__reset() activeCache = nil; buying = {} end
