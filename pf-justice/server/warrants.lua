-- pf-justice warrant reviews (PF_ARCHITECTURE 4.7.7, state machine 5.10; unit 19A).
--
-- The police MDT files a review for every new warrant (RequestWarrantReview, key
-- pf-policemdt:warrant:<id>:review) and then accepts the decision only from pf-justice
-- (exports['pf-policemdt-DEV']:SetWarrantApproval(warrantId, 'approve'|'deny'|'needs_info', { reviewId, judgeCid, note, actor })).
--
--   requested -> approved | denied | needs_info;  needs_info -> requested (the same key with a new affidavit)
--
-- An on-duty judge decides (DecideWarrant, or /warrantreviews and /warrantdecide until the b21 court app).
-- Warrants never auto-decide. Low population (Config.Courts.WarrantFallback): when no judge has been on duty
-- since AfterSeconds after the request, an on-duty police officer of the configured grade who did not request
-- it may decide through the same path, labelled as a fallback in the audit (the MDT's own supervisor approval
-- is closed once a judge review exists, so this keeps warrants usable on a server without judges).
--
-- The decision is stored first (notify_state 'pending'), then sent to the MDT; a send that did not reach the
-- MDT is retried by Warrants.Tick, a clear MDT refusal is kept as 'refused' with an audit row.

PFJustice = PFJustice or {}
PFJustice.Warrants = PFJustice.Warrants or {}
local J = PFJustice
local W = J.Warrants
local U = J.Util
local Err = J.Result.Err
local Courts = J.Courts

local function C(key, default)
    local cfg = (Config and Config.Courts) or {}
    local v = cfg[key]
    if v == nil then return default end
    return v
end

W.SQL = {
    byKey = 'SELECT * FROM pf_justice_warrant_reviews WHERE idem_key = ? LIMIT 1',
    byId = 'SELECT * FROM pf_justice_warrant_reviews WHERE id = ? LIMIT 1',
    openOfWarrant = "SELECT * FROM pf_justice_warrant_reviews WHERE warrant_id = ? AND state IN ('requested', 'needs_info') ORDER BY id DESC LIMIT 1",
    insert = [[INSERT INTO pf_justice_warrant_reviews (warrant_id, type, target_cid, address, affidavit, requested_by, state, requested_at, idem_key)
        VALUES (?, ?, ?, ?, ?, ?, 'requested', ?, ?)]],
    reopen = [[UPDATE pf_justice_warrant_reviews SET state = 'requested', affidavit = ?, note = NULL, judge_cid = NULL, decided_at = NULL,
        notify_state = NULL, requested_at = ? WHERE id = ? AND state = 'needs_info']],
    decide = [[UPDATE pf_justice_warrant_reviews SET state = ?, judge_cid = ?, note = ?, decided_at = ?, notify_state = 'pending'
        WHERE id = ? AND state = 'requested']],
    notified = 'UPDATE pf_justice_warrant_reviews SET notify_state = ? WHERE id = ? AND notify_state = ?',
    pendingNotify = "SELECT * FROM pf_justice_warrant_reviews WHERE notify_state = 'pending' ORDER BY id ASC LIMIT 25",
    listOpen = "SELECT * FROM pf_justice_warrant_reviews WHERE state = 'requested' ORDER BY requested_at ASC LIMIT ?",
}
local SQL = W.SQL

local TYPES = { arrest = true, search = true, bench = true }
local DECISIONS = { approve = 'approved', deny = 'denied', needs_info = 'needs_info' }
-- MDT refusals that a retry cannot change
local FINAL = { not_found = true, invalid_state = true, conflict = true, bad_args = true, not_allowed = true }

local function db() return Courts.One, Courts.Many, Courts.Update, Courts.Insert end

function W.Public(r)
    if not r then return nil end
    return { id = tonumber(r.id), warrantId = r.warrant_id, type = r.type, targetCid = r.target_cid, address = r.address,
        affidavit = r.affidavit, requestedBy = r.requested_by, state = r.state, judgeCid = r.judge_cid, note = r.note,
        requestedAt = tonumber(r.requested_at), decidedAt = tonumber(r.decided_at), notifyState = r.notify_state }
end

function W.Row(id) local one = db() return (one(SQL.byId, { id })) end

--- Tells the on-duty judges a review is waiting (no personal data in the notice).
local function pingJudges(r)
    for _, src in ipairs(Courts.JudgesOnDuty()) do
        TriggerClientEvent('QBCore:Notify', src, ('Warrant review #%d (%s warrant %s) is waiting'):format(tonumber(r.id), r.type, r.warrant_id), 'primary')
    end
end

--- RequestWarrantReview(spec, opts): spec = { warrantId, type, targetCid?, address?, affidavit, requestedBy },
--- opts = { key }. Returns { ok, reviewId, duplicate?, reopened? }.
function W.Request(spec, opts, ctx)
    if not Courts.Ready() then return Err('db_unavailable', 'The court database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    if type(spec) ~= 'table' then return Err('bad_args', 'spec must be a table') end
    local warrantId = U.Str(spec.warrantId, 32)
    if not warrantId or not warrantId:match('^[%w%-_]+$') then return Err('bad_args', 'warrantId is invalid') end
    if not TYPES[spec.type] then return Err('bad_args', 'type is arrest, search or bench') end
    local target
    if spec.targetCid ~= nil and spec.targetCid ~= '' then
        if not U.ValidCid(spec.targetCid) then return Err('bad_args', 'targetCid is invalid') end
        target = spec.targetCid
    end
    local address = U.Str(spec.address, 128)
    if spec.type == 'search' and not target and not address then return Err('bad_args', 'A search warrant names a person or an address') end
    if spec.type ~= 'search' and not target then return Err('bad_args', 'An arrest or bench warrant names the person') end
    -- the affidavit may be short (the judge can ask for more); control characters except new lines are removed
    local affidavit = ''
    if type(spec.affidavit) == 'string' then
        affidavit = spec.affidavit:sub(1, 8000):gsub('%c', function(c) return c == '\n' and c or ' ' end)
    end
    if not U.ValidCid(spec.requestedBy) then return Err('bad_args', 'requestedBy is invalid') end
    local key = opts.key
    if key ~= nil and not U.ValidKey(key) then return Err('bad_args', 'opts.key is invalid') end
    if key == nil and not internal then return Err('bad_args', 'opts.key is required') end
    local one, _, update, insert = db()
    return J.Locks.With('warrant:' .. warrantId, function()
        if key then
            local r, okq = one(SQL.byKey, { key })
            if not okq then return Err('db_unavailable', 'The court database did not answer') end
            if r then
                if r.warrant_id ~= warrantId or r.type ~= spec.type then return Err('key_reused', 'This key was used for a different warrant') end
                if r.state == 'needs_info' and affidavit ~= r.affidavit then
                    -- the officer answered the judge: the same review is asked again with the new affidavit
                    if update(SQL.reopen, { affidavit, os.time(), r.id }) ~= 1 then return Err('busy', 'The review changed meanwhile') end
                    J.Audit.Write('warrant_review', r.id, 'reopened', { warrantId = warrantId }, { kind = 'system', label = 'warrant review', resource = ctx.invoker })
                    pingJudges(r)
                    return { ok = true, reviewId = tonumber(r.id), reopened = true }
                end
                return { ok = true, duplicate = true, reviewId = tonumber(r.id), state = r.state }
            end
        end
        local open = one(SQL.openOfWarrant, { warrantId })
        if open then return Err('conflict', 'This warrant already has an open review') end
        local id = insert(SQL.insert, { warrantId, spec.type, target, address, affidavit, spec.requestedBy, os.time(), key })
        if not id then
            if key then
                local r = one(SQL.byKey, { key })
                if r then return { ok = true, duplicate = true, reviewId = tonumber(r.id), state = r.state } end
            end
            return Err('db_unavailable', 'The review could not be stored')
        end
        J.Audit.Write('warrant_review', id, 'requested', { warrantId = warrantId, type = spec.type, target = target, by = spec.requestedBy },
            { kind = 'system', label = 'warrant review', resource = ctx.invoker })
        J.Emit('warrantReviewChanged', W.Public(W.Row(id)), { action = 'requested' })
        pingJudges({ id = id, type = spec.type, warrant_id = warrantId })
        return { ok = true, reviewId = id }
    end)
end

--- Whether the actor may decide this review: an on-duty judge, an admin, pf-justice itself, or (fallback) an
--- on-duty police officer of Config.Courts.WarrantFallback grade when no judge has been on duty since the
--- review waited AfterSeconds; never the officer who requested it.
function W.MayDecide(actor, r, now)
    if Courts.HasRole(actor, 'judge') then return true, 'judge' end
    local fb = C('WarrantFallback', {}) or {}
    if not fb.Enabled or type(actor) ~= 'table' or actor.kind ~= 'player' or not actor.onduty then return false end
    local min = (fb.PoliceJobs or {})[actor.job or '']
    if min == nil or (tonumber(actor.grade) or 0) < tonumber(min) then return false end
    if actor.cid == r.requested_by then return false, 'own' end
    now = now or os.time()
    local after = tonumber(fb.AfterSeconds) or 1800
    if #Courts.JudgesOnDuty() > 0 then return false, 'judge_on_duty' end
    if now - (tonumber(r.requested_at) or now) < after or now - (Courts.lastJudgeAt or 0) < after then return false, 'too_soon' end
    return true, 'fallback'
end

--- Sends a stored decision to the MDT. Returns 'sent' | 'pending' | 'refused'.
function W.Notify(r)
    local _, _, update = db()
    local decision
    for k, v in pairs(DECISIONS) do if v == r.state then decision = k end end
    if not decision then return 'refused' end
    if GetResourceState('pf-policemdt-DEV') ~= 'started' then return 'pending' end
    local ok, res = pcall(function()
        return exports['pf-policemdt-DEV']:SetWarrantApproval(r.warrant_id, decision, { reviewId = tonumber(r.id), judgeCid = r.judge_cid,
            note = r.note, actor = { kind = 'judge', cid = r.judge_cid } })
    end)
    if not ok or type(res) ~= 'table' then return 'pending' end
    local outcome = res.ok and 'sent' or (FINAL[res.error or ''] and 'refused' or 'pending')
    if outcome ~= 'pending' then
        update(SQL.notified, { outcome, r.id, 'pending' })
        if outcome == 'refused' then
            J.Audit.Write('warrant_review', r.id, 'mdt_refused', { error = res.error, warrantId = r.warrant_id }, { kind = 'system', label = 'warrant review' })
        end
    end
    return outcome
end

--- DecideWarrant(reviewId, decision, opts): decision approve | deny | needs_info; opts = { actor, note }.
--- Returns { ok, state, notified }.
function W.Decide(reviewId, decision, opts, ctx)
    if not Courts.Ready() then return Err('db_unavailable', 'The court database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    local id = U.Int(reviewId, 1, 2147483647)
    local to = DECISIONS[decision]
    if not id or not to then return Err('bad_args', 'reviewId and a decision (approve, deny, needs_info) are required') end
    local note = U.Str(opts.note, 500)
    if decision ~= 'approve' and not note then return Err('bad_args', 'Say why (a note is required to deny or ask for more)') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if ctx.invoker == 'pfm-adminmenu' and actor.kind ~= 'admin' then return Err('no_permission', 'An admin actor is required') end
    if actor.kind == 'system' and not (ctx.invoker == nil or ctx.invoker == J.RESOURCE) then return Err('no_permission', 'A judge decides warrants') end
    local one, _, update = db()
    return J.Locks.With('review:' .. id, function()
        local r = one(SQL.byId, { id })
        if not r then return Err('not_found', 'No such warrant review') end
        if r.state == to and r.decided_at then return { ok = true, duplicate = true, state = r.state, notified = r.notify_state == 'sent' } end
        if r.state ~= 'requested' then return Err('invalid_state', 'The review is ' .. r.state) end
        local may, how = W.MayDecide(actor, r)
        if not may then
            if how == 'own' then return Err('no_permission', 'You requested this warrant') end
            if how == 'too_soon' or how == 'judge_on_duty' then return Err('no_permission', 'A judge decides this warrant (the fallback opens when no judge is on duty)') end
            return Courts.RoleErr(actor, { 'judge' })
        end
        local judge = actor.cid or J.Actor.Tag(actor) or 'court'
        if update(SQL.decide, { to, judge:sub(1, 64), note, os.time(), id }) ~= 1 then return Err('busy', 'The review changed meanwhile') end
        J.Audit.Write('warrant_review', id, to, { warrantId = r.warrant_id, by = how, note = note }, actor)
        r = one(SQL.byId, { id }) or r
        local sent = W.Notify(r)
        J.Emit('warrantReviewChanged', W.Public(r), { action = 'decided', decision = decision, by = how })
        local subject = ('Warrant %s: %s'):format(r.warrant_id, decision == 'needs_info' and 'more information needed' or to)
        Courts.Mail(r.requested_by, subject, ('Review #%d of warrant %s was %s.%s'):format(id, r.warrant_id,
            decision == 'needs_info' and 'returned for more information' or to, note and (' Note: ' .. note) or ''),
            ('pf-justice:review:%d:%s:%d'):format(id, to, tonumber(r.decided_at) or 0))
        return { ok = true, state = to, notified = sent == 'sent', mdt = sent }
    end)
end

--- Retries decisions that did not reach the MDT (named tick).
function W.Tick(now)
    if not Courts.Ready() then return 0 end
    local _, many = db()
    local n = 0
    for _, r in ipairs(many(SQL.pendingNotify, {}) or {}) do
        if W.Notify(r) == 'sent' then n = n + 1 end
    end
    return n
end

function W.Get(reviewId)
    if not Courts.Ready() then return Err('db_unavailable', 'The court database is not ready') end
    local id = U.Int(reviewId, 1, 2147483647)
    if not id then return Err('bad_args', 'reviewId is invalid') end
    local r = W.Row(id)
    if not r then return Err('not_found', 'No such warrant review') end
    return { ok = true, review = W.Public(r) }
end

-- ── exports ───────────────────────────────────────────────────────────────────────────────────

Courts.Export('RequestWarrantReview', function(ctx, spec, opts) return W.Request(spec, opts, ctx) end)
Courts.Export('DecideWarrant', function(ctx, reviewId, decision, opts) return W.Decide(reviewId, decision, opts, ctx) end)
Courts.Export('GetWarrantReview', function(ctx, reviewId) return W.Get(reviewId) end)

-- ── commands for judges (until the b21 court app) ─────────────────────────────────────────────

--- /warrantreviews: the waiting reviews (judges, or police allowed by the fallback).
function W.CommandList(src)
    src = U.Src(src)
    if not src then return end
    local actor = J.Actor.Resolve({ src = src }, nil)
    if not actor then return end
    local fb = C('WarrantFallback', {}) or {}
    local police = actor.onduty and (fb.PoliceJobs or {})[actor.job or ''] ~= nil
    if not Courts.HasRole(actor, 'judge') and not police then
        Courts.Reply(src, 'Only an on-duty judge reviews warrants', 'error')
        return
    end
    local _, many = db()
    local rows = many(SQL.listOpen, { 10 }) or {}
    if #rows == 0 then Courts.Reply(src, 'No warrant reviews are waiting') return rows end
    for _, r in ipairs(rows) do
        Courts.Reply(src, ('#%d %s warrant %s for %s, by %s: %s'):format(tonumber(r.id), r.type, r.warrant_id, r.target_cid or r.address or '?',
            r.requested_by, (r.affidavit or ''):sub(1, 200)))
    end
    return rows
end

--- /warrantdecide <reviewId> <approve|deny|needs_info> [note]
function W.CommandDecide(src, args)
    src = U.Src(src)
    if not src then return end
    args = type(args) == 'table' and args or {}
    local note = #args > 2 and table.concat(args, ' ', 3) or nil
    local res = W.Decide(tonumber(args[1]), args[2], { actor = { src = src }, note = note }, {})
    if res.ok then
        Courts.Reply(src, ('Warrant review #%s: %s%s'):format(tostring(args[1]), res.state, res.notified and '' or ' (the MDT is told when it is back)'), 'success')
    else
        Courts.Reply(src, 'Not decided: ' .. tostring(res.message or res.error), 'error')
    end
    return res
end

if C('Commands', true) then
    RegisterCommand('warrantreviews', function(source) W.CommandList(source) end, false)
    RegisterCommand('warrantdecide', function(source, args) W.CommandDecide(source, args) end, false)
end
