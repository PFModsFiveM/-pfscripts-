-- =====================================================
-- DEPARTMENTS: QUALIFICATIONS
-- =====================================================
-- What a department employee is certified to do (Config.Departments.Qualifications), on top of the
-- job and grade pfm-core holds:
--   * implied: Config.Departments.Implied[job][grade] lists what a grade carries, so every action
--     works on a live server before anyone grants a certification (no rows needed);
--   * granted: a department manager (ManagerGrade of the qualification's department) certifies an
--     employee of that department; a grant counts while the holder works in that department and
--     until expires_at (a revocation may also target a former member);
--   * revoked: a revocation row overrides the implied qualification; with expires_at it is a
--     suspension that lapses at that time (the grade's implied qualification comes back).
-- One row per (citizen, qualification) in pf_gov_dept_qualifications holds the current decision;
-- every change also writes a pf_gov_dept_audit row (qual_grant / qual_revoke) with the caller's key.
--
-- Idempotency (architecture 3.3): opts.key is stored on the row (UNIQUE idem_key) and in the audit
-- detail. A repeat with the same key and arguments returns duplicate = true without changing
-- anything; with other arguments key_reused. Keys displaced from the row by a later change are still
-- found in the department's audit rows of the last KeyWindowDays (default 30).
--
-- Reads are cached per citizen (only this file writes the table, so a change clears the entry).

GovDept = GovDept or {}
local D = GovDept
local U = D.U
D.Q = D.Q or {}
local Q = D.Q

local function cfg() return D.Cfg() end

local TEN_YEARS = 10 * 365 * 86400
Q.CACHE_TTL = 300
Q.CACHE_MAX = 1000

local function defOf(qual)
    if type(qual) ~= 'string' or #qual > 32 then return nil end
    return (cfg().Qualifications or {})[qual]
end
Q.Def = defOf

-- ── cache of granted / revoked rows ─────────────────────────────────────

local cache, cacheCount = {}, 0
Q.cache = cache

function Q.Forget(cid)
    if cache[cid] then
        cache[cid] = nil
        cacheCount = cacheCount - 1
    end
end

local function prune(t)
    for cid, c in pairs(cache) do
        if t - c.at >= Q.CACHE_TTL then cache[cid] = nil; cacheCount = cacheCount - 1 end
    end
    if cacheCount >= Q.CACHE_MAX then
        for cid in pairs(cache) do cache[cid] = nil end
        cacheCount = 0
    end
end

--- { [qual] = { state, expiresAt, grantedBy, source, at } } for `cid`; nil when the database failed.
function Q.Rows(cid)
    local t = U.now()
    local c = cache[cid]
    if c and t - c.at < Q.CACHE_TTL then return c.rows end
    if not U.dbReady() then return nil end
    local ok, rows = pcall(MySQL.query.await,
        'SELECT qual, state, granted_by, source, expires_at, at FROM pf_gov_dept_qualifications WHERE citizenid = ?', { cid })
    if not ok or type(rows) ~= 'table' then
        print('^1[PF-GOVERNMENT]^7 qualifications of ' .. tostring(cid) .. ' not read: ' .. tostring(rows))
        return nil
    end
    local map = {}
    for _, r in ipairs(rows) do
        map[r.qual] = {
            state = r.state, expiresAt = tonumber(r.expires_at), grantedBy = r.granted_by, source = r.source, at = tonumber(r.at),
        }
    end
    if not c then
        if cacheCount >= Q.CACHE_MAX then prune(t) end
        cacheCount = cacheCount + 1
    end
    cache[cid] = { at = t, rows = map }
    return map
end

-- ── evaluation ──────────────────────────────────────────────────────────

--- True when the member's live job and grade imply `qual`.
function Q.Implied(m, qual)
    if type(m) ~= 'table' or not m.job then return false end
    local byJob = (cfg().Implied or {})[m.job]
    if type(byJob) ~= 'table' then return false end
    local list = byJob[m.grade] or byJob[tostring(m.grade)]
    if type(list) ~= 'table' then return false end
    for _, q in ipairs(list) do if q == qual then return true end end
    return false
end

local function active(row, t) return row and (row.expiresAt == nil or row.expiresAt > t) end

--- has, source ('granted'|'implied'), expiresAt, reason (why not: none|revoked|expired|not_employed).
local function evaluate(m, rows, qual, t)
    local row = rows[qual]
    if row and row.state == 'revoked' and active(row, t) then return false, nil, row.expiresAt, 'revoked' end
    if row and row.state == 'granted' and active(row, t) then
        -- a certification only counts while its holder works for the department that owns it
        -- (a fired officer's grant does not come back with a job in another department)
        local def = defOf(qual)
        if m and m.dept and def and m.dept == def.dept then return true, 'granted', row.expiresAt end
        return false, nil, row.expiresAt, (m and m.dept) and 'other_department' or 'not_employed'
    end
    if m and Q.Implied(m, qual) then return true, 'implied' end
    if row and row.state == 'granted' then return false, nil, row.expiresAt, 'expired' end
    return false, nil, nil, 'none'
end

local function cidOf(who)
    if type(who) == 'number' then
        local m = D.Member(who)
        return m and m.cid or nil
    end
    return U.validCid(who) and who or nil
end

--- has:boolean, source, expiresAt. Fails closed (false) when the records cannot be read.
function Q.Has(who, qual)
    local cid = cidOf(who)
    if not cid or not defOf(qual) then return false end
    local m = D.MemberByCid(cid)
    if m == false then return false end
    local rows = Q.Rows(cid)
    if not rows then return false end
    local has, source, expiresAt = evaluate(m or nil, rows, qual, U.now())
    if has then return true, source, expiresAt end
    return false
end

--- { ok, list = { { qual, label, dept, has, source?, state?, expiresAt?, grantedBy?, at?, reason } } }:
--- every qualification the citizen holds, is implied, or has a row for (revoked, expired...).
function Q.List(who)
    local cid = cidOf(who)
    if not cid then return U.fail('bad_args', 'Invalid citizen id.') end
    local m = D.MemberByCid(cid)
    if m == false then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local rows = Q.Rows(cid)
    if not rows then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local t, list = U.now(), {}
    for qual, def in pairs(cfg().Qualifications or {}) do
        local has, source, expiresAt, reason = evaluate(m or nil, rows, qual, t)
        local row = rows[qual]
        if has or row then
            list[#list + 1] = {
                qual = qual, label = def.label or qual, dept = def.dept, has = has, source = source,
                state = row and row.state or nil, expiresAt = expiresAt, grantedBy = row and row.grantedBy or nil,
                at = row and row.at or nil, reason = reason,
            }
        end
    end
    table.sort(list, function(a, b)
        if (a.dept or '') ~= (b.dept or '') then return (a.dept or '') < (b.dept or '') end
        return a.qual < b.qual
    end)
    return { ok = true, list = list, dept = m and m.dept or nil }
end

-- ── grant / revoke ──────────────────────────────────────────────────────

local ACTIONS = { granted = 'qual_grant', revoked = 'qual_revoke' }
local SOURCES = { manual = true, training = true, import = true }

local function sameArgs(cid, qual, state, expiresAt, r)
    return r.cid == cid and r.qual == qual and r.state == state and r.expiresAt == expiresAt
end

--- The first use of `key`: { cid, qual, state, expiresAt } or nil. false when the lookup failed.
local function keyUse(key, dept, t)
    local ok, row = pcall(MySQL.single.await,
        'SELECT citizenid, qual, state, expires_at FROM pf_gov_dept_qualifications WHERE idem_key = ? LIMIT 1', { key })
    if not ok then return false end
    if row then return { cid = row.citizenid, qual = row.qual, state = row.state, expiresAt = tonumber(row.expires_at) } end
    local days = U.int(cfg().KeyWindowDays or 30, 1, 3650) or 30
    local ok2, a = pcall(MySQL.single.await,
        [[SELECT action, target, detail FROM pf_gov_dept_audit WHERE dept = ? AND at >= ? AND action IN ('qual_grant', 'qual_revoke')
            AND JSON_UNQUOTE(JSON_EXTRACT(detail, '$.key')) = ? LIMIT 1]], { dept, t - days * 86400, key })
    if not ok2 then return false end
    if not a then return nil end
    local d = type(a.detail) == 'string' and json.decode(a.detail) or {}
    if type(d) ~= 'table' or d.key ~= key then return nil end
    return { cid = a.target, qual = d.qual, state = a.action == 'qual_grant' and 'granted' or 'revoked', expiresAt = tonumber(d.expiresAt) }
end

--- Grant ('granted') or revoke ('revoked') `qual` for `cid`.
--- opts = { actor = { src } | { kind = 'admin', src } | { kind = 'system', label }, expiresAt?, key?, reason?, source? }
function Q.Change(state, cid, qual, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    if not U.validCid(cid) then return U.fail('bad_args', 'Invalid citizen id.') end
    local def = defOf(qual)
    if not def then return U.fail('bad_args', 'Unknown qualification.') end
    local dept = def.dept
    local key = opts.key
    if key ~= nil and not U.validKey(key) then return U.fail('bad_args', 'Invalid key.') end
    local t = U.now()
    local expiresAt
    if opts.expiresAt ~= nil then
        expiresAt = U.int(opts.expiresAt, t + 1, t + TEN_YEARS)
        if not expiresAt then return U.fail('bad_args', 'The expiry must be a future time within ten years.') end
    end
    local reason
    if opts.reason ~= nil then
        reason = U.cleanText(opts.reason, 200)
        if not reason then return U.fail('bad_args', 'Invalid reason.') end
    end
    local source = 'manual'
    if opts.source ~= nil then
        if invoker ~= nil or not SOURCES[opts.source] then return U.fail('bad_args', 'Invalid source.') end
        source = opts.source
    end

    local actor, aerr = D.ResolveActor(opts.actor, invoker)
    if not actor then return aerr end
    if actor.kind == 'player' then
        if not D.IsManager(actor.member, dept) then
            return U.fail('no_permission', 'Only a manager of this department can change its qualifications.')
        end
        if actor.cid == cid then return U.fail('no_permission', 'You cannot change your own qualifications.') end
    end

    local lockNames = { 'dq:' .. cid .. ':' .. qual }
    if key then lockNames[2] = 'dqk:' .. key end
    return U.withLocks(lockNames, function()
        if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
        if key then
            local used = keyUse(key, dept, t)
            if used == false then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
            if used then
                if sameArgs(cid, qual, state, expiresAt, used) then
                    return { ok = true, duplicate = true, qual = qual, state = state, expiresAt = expiresAt }
                end
                return U.fail('key_reused', 'This key was used for a different change.')
            end
        end

        local target = D.MemberByCid(cid)
        if target == false then error('players lookup failed') end
        if not target then return U.fail('not_found', 'No such citizen.') end
        -- a grant only means something to a member of the owning department; a revocation may also
        -- strip a former member (fired or moved) before a rehire
        if state == 'granted' and target.dept ~= dept then
            return U.fail('invalid_state', 'This citizen does not work for this department.')
        end
        if actor.kind == 'player' and target.dept == dept and not actor.member.isBoss and actor.member.grade <= target.grade then
            return U.fail('no_permission', 'You can only change qualifications of lower ranks.')
        end

        local row = MySQL.single.await('SELECT id, state, expires_at FROM pf_gov_dept_qualifications WHERE citizenid = ? AND qual = ? LIMIT 1', { cid, qual })
        if row and row.state == state and tonumber(row.expires_at) == expiresAt then
            if key then
                -- remember the key even though nothing changed, so a replay after a later change
                -- returns duplicate instead of applying this one again (row first, audit as backup)
                MySQL.update.await('UPDATE pf_gov_dept_qualifications SET idem_key = ? WHERE id = ?', { key, row.id })
                D.Audit(dept, ACTIONS[state], actor.cid, cid, {
                    qual = qual, expiresAt = expiresAt, key = key, reason = reason, unchanged = true, actorKind = actor.kind,
                }, invoker and invoker:sub(1, 48) or nil)
            end
            return { ok = true, unchanged = true, qual = qual, state = state, expiresAt = expiresAt }
        end
        local by = actor.cid or ('system:' .. (actor.label or 'system')):sub(1, 64)
        if row then
            MySQL.update.await(
                'UPDATE pf_gov_dept_qualifications SET state = ?, granted_by = ?, source = ?, expires_at = ?, at = ?, idem_key = ? WHERE id = ?',
                { state, by, source, expiresAt, t, key, row.id })
        else
            local ok, err = pcall(MySQL.insert.await,
                'INSERT INTO pf_gov_dept_qualifications (citizenid, qual, state, granted_by, source, expires_at, at, idem_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                { cid, qual, state, by, source, expiresAt, t, key })
            if not ok then
                if key and tostring(err):lower():find('duplicate', 1, true) then
                    return U.fail('key_reused', 'This key was used for a different change.')
                end
                error(err)
            end
        end
        Q.Forget(cid)
        D.Audit(dept, ACTIONS[state], actor.cid, cid, {
            qual = qual, expiresAt = expiresAt, key = key, reason = reason, prev = row and row.state or nil,
            actorKind = actor.kind, source = source,
        }, invoker and invoker:sub(1, 48) or nil)
        TriggerEvent('pf-government:server:qualificationChanged', cid, qual, state, expiresAt)
        if target.src then
            local label = def.label or qual
            local msg = state == 'granted' and ('Qualification granted: ' .. label) or ('Qualification revoked: ' .. label)
            TriggerClientEvent('QBCore:Notify', target.src, msg, state == 'granted' and 'success' or 'error')
        end
        return { ok = true, qual = qual, state = state, expiresAt = expiresAt }
    end)
end

function Q.Grant(cid, qual, opts, invoker) return Q.Change('granted', cid, qual, opts, invoker) end
function Q.Revoke(cid, qual, opts, invoker) return Q.Change('revoked', cid, qual, opts, invoker) end

-- ── exports ─────────────────────────────────────────────────────────────

exports('HasQualification', function(cid, qual) return Q.Has(cid, qual) end)

exports('ListQualifications', function(cid) return Q.List(cid) end)

exports('GrantQualification', function(cid, qual, opts)
    local allowed, inv = U.callerAllowed('GrantQualification')
    if not allowed then return U.notAllowed() end
    return Q.Grant(cid, qual, opts, inv)
end)

exports('RevokeQualification', function(cid, qual, opts)
    local allowed, inv = U.callerAllowed('RevokeQualification')
    if not allowed then return U.notAllowed() end
    return Q.Revoke(cid, qual, opts, inv)
end)
