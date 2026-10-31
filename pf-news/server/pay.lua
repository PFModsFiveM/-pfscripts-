-- Reporter bonus: one payment per published article (ledger key pf-news:bonus:<article id>).
-- Recorded when the article is published and paid by the sweep after Config.Pay.holdSeconds, if the
-- article is still published: an editor who retracts junk in time stops the payment. Articles shorter
-- than minBodyLength earn nothing; a reporter earns at most dailyCap a day; covering a claimed lead
-- adds leadBonus. City Desk articles have no author and pay nothing.

PFNews = PFNews or {}
PFNews.SQL = PFNews.SQL or {}
local U = PFNews.U
local SQL = PFNews.SQL
local Pay = {}
PFNews.Pay = Pay

SQL.dayTotal = "SELECT COALESCE(SUM(amount), 0) FROM pf_news_payouts WHERE citizenid = ? AND day = ? AND state IN ('pending', 'paid')"
SQL.insertPayout = [[INSERT IGNORE INTO pf_news_payouts (article_id, citizenid, amount, day, lead_bonus, state, due_at, created_at)
    VALUES (?, ?, ?, ?, ?, 'pending', FROM_UNIXTIME(?), FROM_UNIXTIME(?))]]
SQL.duePayouts = [[SELECT p.article_id, p.citizenid, p.amount, p.attempts, a.status, a.title FROM pf_news_payouts p
    JOIN pf_news_articles a ON a.id = p.article_id WHERE p.state = 'pending' AND p.due_at <= FROM_UNIXTIME(?) ORDER BY p.article_id LIMIT 50]]
SQL.payoutPaid = "UPDATE pf_news_payouts SET state = 'paid', paid_at = FROM_UNIXTIME(?), tx_id = ? WHERE article_id = ? AND state = 'pending'"
SQL.payoutCancel = "UPDATE pf_news_payouts SET state = 'cancelled' WHERE article_id = ? AND state = 'pending'"
-- state first: MySQL evaluates single-table assignments left to right
SQL.payoutRetry = "UPDATE pf_news_payouts SET state = IF(attempts + 1 >= ?, 'failed', state), attempts = attempts + 1, error = ? WHERE article_id = ? AND state = 'pending'"
SQL.myPayouts = "SELECT article_id, amount, state, lead_bonus, UNIX_TIMESTAMP(due_at) AS due_at FROM pf_news_payouts WHERE citizenid = ? ORDER BY article_id DESC LIMIT 20"

-- pf-news:bonus:<id>; a retry after a failure the ledger recorded (a failed key stays failed) uses
-- pf-news:bonus:<id>:<attempt>. The attempt only moves on after a failure, so a payment that went
-- through before a crash is found again under the same key and never paid twice.
function Pay.KeyFor(articleId, attempt)
    attempt = tonumber(attempt) or 0
    return 'pf-news:bonus:' .. tostring(articleId) .. (attempt > 0 and (':' .. attempt) or '')
end

--- Records the bonus for a newly published article. Returns { amount, dueAt } or { skipped = why }.
function Pay.OnPublished(r, coveredLead)
    local C = Config.Pay
    if not C.enabled then return { skipped = 'disabled' } end
    if r.auto or type(r.author_cid) ~= 'string' then return { skipped = 'no_author' } end
    if U.len(r.body or '') < (C.minBodyLength or 0) then return { skipped = 'too_short' } end
    local now = os.time()
    local day = os.date('%Y-%m-%d', now)
    local total = tonumber(MySQL.scalar.await(SQL.dayTotal, { r.author_cid, day })) or 0
    local remaining = (C.dailyCap or 0) - total
    if remaining <= 0 then return { skipped = 'daily_cap' } end
    local amount = math.min((C.perArticle or 0) + (coveredLead and (C.leadBonus or 0) or 0), remaining)
    if amount <= 0 then return { skipped = 'no_amount' } end
    local due = now + (C.holdSeconds or 0)
    local n = U.affected(MySQL.update.await(SQL.insertPayout, { r.id, r.author_cid, amount, day, coveredLead and 1 or 0, due, now }))
    if n ~= 1 then return { skipped = 'already_recorded' } end
    if (C.holdSeconds or 0) <= 0 then Pay.Sweep() end
    return { amount = amount, dueAt = due, leadBonus = coveredLead == true }
end

function Pay.Cancel(articleId)
    return U.affected(MySQL.update.await(SQL.payoutCancel, { articleId })) == 1
end

--- Pays every bonus that is due. A bank that is down leaves the bonus pending (same key next time).
local sweeping = false
function Pay.Sweep()
    if sweeping then return 0 end
    sweeping = true
    local ok, res = pcall(Pay.SweepNow)
    sweeping = false
    if not ok then error(res) end
    return res
end

function Pay.SweepNow()
    local now = os.time()
    local paid = 0
    for _, p in ipairs(MySQL.query.await(SQL.duePayouts, { now }) or {}) do
        local id = tonumber(p.article_id)
        if p.status ~= 'published' then
            MySQL.update.await(SQL.payoutCancel, { id })
        else
            local opts = { key = Pay.KeyFor(id, p.attempts), reason = ('Weazel News article #%d'):format(id), kind = 'wage', quiet = true }
            if Config.Pay.fundFrom == 'society' then opts.from = 'society:' .. (Config.CompanyAccount or Config.Job) end
            local ok, res = PFPayout.Pay(p.citizenid, Config.Pay.account or 'bank', tonumber(p.amount), opts)
            if ok then
                MySQL.update.await(SQL.payoutPaid, { now, res and res.txId or nil, id })
                paid = paid + 1
                local Author = U.QB().Functions.GetPlayerByCitizenId(p.citizenid)
                if Author then
                    U.notify(Author.PlayerData.source, ('Weazel News paid you $%s for "%s"'):format(tostring(p.amount), tostring(p.title)), 'success', 7000)
                end
            elseif not (res and res.error == 'in_progress') then
                MySQL.update.await(SQL.payoutRetry, { Config.Pay.maxAttempts or 10, tostring(res and res.error or 'payment_failed'):sub(1, 64), id })
            end
        end
    end
    return paid
end

function Pay.Mine(cid)
    local out = {}
    for _, r in ipairs(MySQL.query.await(SQL.myPayouts, { cid }) or {}) do
        out[#out + 1] = { articleId = tonumber(r.article_id), amount = tonumber(r.amount), state = r.state, leadBonus = U.bool(r.lead_bonus), dueAt = tonumber(r.due_at) }
    end
    return out
end
