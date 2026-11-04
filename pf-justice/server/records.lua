-- pf-justice criminal record (PF_ARCHITECTURE 4.7.1, owners table): pf_justice_records.
--
--   * A conviction entry is written once when a sentence order reaches its end state
--     (Config.Records.ConvictionOn: served jail/prison, paid fine, completed community service...);
--     a citation entry when a citation is paid or upheld. Vacated orders (overturned, released by a
--     court or an admin) leave no conviction.
--   * Other resources add arrest / note entries through AddRecordEntry (deduplicated by ref).
--   * Expunge soft-deletes (expunged_at, expunged_by, expunge_ref) and writes an audit row; nothing is
--     ever hard-deleted, and expunged entries are never returned to other resources.
--   * A deleted character's entries stay as court history under a random token (orders.lua).
--   * An entry that cannot be written when its order ends (the record lock is busy, the database
--     fails) is queued and retried every tick, and after a restart (RetryQueued / LoadQueue).
-- Changes raise 'pf-justice:server:recordChanged'(cid, change) for the criminalrecord metadata
-- mirror (15C compat.lua).

PFJustice = PFJustice or {}
PFJustice.Records = PFJustice.Records or {}
local J = PFJustice
local R = J.Records
local U = J.Util
local Err = J.Result.Err

local SQL = J.SQL
SQL.insertRecord = 'INSERT INTO pf_justice_records (citizenid, kind, ref_type, ref_id, summary, at) VALUES (?, ?, ?, ?, ?, ?)'
SQL.recordsByCid = 'SELECT * FROM pf_justice_records WHERE citizenid = ? AND expunged_at IS NULL ORDER BY id DESC LIMIT ?'
SQL.recordsAllByCid = 'SELECT * FROM pf_justice_records WHERE citizenid = ? ORDER BY id DESC LIMIT ?'
SQL.recordByRef = 'SELECT id FROM pf_justice_records WHERE citizenid = ? AND kind = ? AND ref_type = ? AND ref_id = ? LIMIT 1'
SQL.expungeRecord = [[UPDATE pf_justice_records SET expunged_at = ?, expunged_by = ?, expunge_ref = ?
    WHERE id = ? AND citizenid = ? AND expunged_at IS NULL]]
SQL.anonRecords = 'UPDATE pf_justice_records SET citizenid = ? WHERE citizenid = ?'
SQL.anonExpungedBy = 'UPDATE pf_justice_records SET expunged_by = ? WHERE expunged_by = ?'
-- entries that could not be written when their order ended (record lock busy, database error) are
-- queued: in memory, and as an order event so a restart does not lose them
SQL.recordQueued = "SELECT DISTINCT order_id FROM pf_justice_order_events WHERE action = 'record_queued' ORDER BY order_id DESC LIMIT 200"
SQL.recordQueueDone = "UPDATE pf_justice_order_events SET action = 'record_done' WHERE idem_key = ?"

local PUBLIC_KINDS = { conviction = true, arrest = true, citation = true, note = true }
local KIND_LABEL = {
    jail = 'Jail sentence', prison = 'Prison sentence', fine = 'Fine', restitution = 'Restitution',
    community_service = 'Community service', probation = 'Probation', parole = 'Parole', citation = 'Citation',
}

local function publicEntry(r)
    return {
        id = tonumber(r.id), kind = r.kind, refType = r.ref_type, refId = r.ref_id, summary = r.summary,
        at = tonumber(r.at), expungedAt = tonumber(r.expunged_at), expungedBy = r.expunged_by, expungeRef = r.expunge_ref,
    }
end

--- The summary line of a record entry made from an order.
function R.Summary(row)
    local parts = { KIND_LABEL[row.kind] or row.kind }
    if row.required_seconds then parts[#parts + 1] = ('%d min'):format(math.floor(row.required_seconds / 60)) end
    if row.amount then parts[#parts + 1] = ('$%d'):format(row.amount) end
    if row.units then parts[#parts + 1] = ('%d units'):format(row.units) end
    if row.days then parts[#parts + 1] = ('%d days'):format(row.days) end
    local charges = U.Decode(row.charges)
    if type(charges) == 'table' and #charges > 0 then
        local list = {}
        for i, c in ipairs(charges) do
            if i > 10 then list[#list + 1] = '...' break end
            local label = c.code and c.label and (c.code .. ' ' .. c.label) or c.code or c.label or '?'
            list[#list + 1] = (c.count and c.count > 1) and (label .. ' x' .. c.count) or label
        end
        parts[#parts + 1] = '(' .. table.concat(list, ', ') .. ')'
    end
    return table.concat(parts, ' '):sub(1, 500)
end

--- Adds one entry (deduplicated by kind + ref). Returns { ok, entryId, duplicate? }.
function R.AddLocked(cid, kind, refType, refId, summary, actor)
    if refType and refId then
        local ok, row = pcall(MySQL.single.await, SQL.recordByRef, { cid, kind, refType, refId })
        if not ok then return Err('db_unavailable', 'The justice database did not answer') end
        if type(row) == 'table' and row[1] and not row.id then row = row[1] end
        if type(row) == 'table' and row.id then return { ok = true, entryId = tonumber(row.id), duplicate = true } end
    end
    local ok, id = pcall(MySQL.insert.await, SQL.insertRecord, { cid, kind, refType, refId, summary, os.time() })
    id = ok and tonumber(id) or nil
    if not id then return Err('db_unavailable', 'The record entry could not be stored') end
    J.Audit.Write('record', id, 'add', { kind = kind, ref = refType and (refType .. ':' .. tostring(refId)) or nil }, actor)
    J.Emit('recordChanged', cid, { action = 'add', entryId = id, kind = kind })
    return { ok = true, entryId = id }
end

--- AddRecordEntry (architecture 4.7.1): entry = { kind = conviction|arrest|citation|note, ref = { type, id } | 'type:id', summary }.
function R.Add(cid, entry, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    if not U.ValidCid(cid) or type(entry) ~= 'table' then return Err('bad_args', 'cid and entry are required') end
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    local kind = entry.kind
    if not PUBLIC_KINDS[kind] and not (internal and kind == 'legacy_flag') then return Err('bad_args', 'unknown entry kind') end
    local summary = U.Str(entry.summary, 500)
    if not summary then return Err('bad_args', 'summary is required') end
    local refType, refId
    if type(entry.ref) == 'table' then
        refType, refId = U.Str(entry.ref.type, 16), U.Str(entry.ref.id, 64)
    elseif type(entry.ref) == 'string' then
        refType, refId = entry.ref:match('^([%w_]+):(.+)$')
        refType, refId = U.Str(refType, 16), U.Str(refId, 64)
    end
    if entry.ref ~= nil and not (refType and refId) then return Err('bad_args', 'ref is invalid') end
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    return J.Locks.With('record:' .. cid, function()
        return R.AddLocked(cid, kind, refType, refId, summary, actor)
    end)
end

R.queue = R.queue or {} -- [orderId] = true: its record entry waits for a retry

local function queueKey(orderId) return ('pf-justice:order:%d:record_queued'):format(orderId) end

--- Queues the record entry of an ended order for RetryQueued (every clock tick and after a restart).
function R.Queue(orderId)
    R.queue[orderId] = true
    if J.Orders and J.Orders.Event then J.Orders.Event(orderId, 'record_queued', nil, nil, queueKey(orderId)) end
end

--- Called by Orders.MoveLocked (and payment settlement) on every state change of an order. When
--- the citizen's record lock is held (an AddRecordEntry / Expunge waiting on the database) or the
--- write fails, the entry is queued and written by RetryQueued, never dropped.
function R.OnOrderEnded(row, to)
    local kind
    if row.kind == 'citation' then
        if (Config.Records.CitationOn or {})[to] then kind = 'citation' end
    elseif (Config.Records.ConvictionOn or {})[row.kind] == to then
        kind = 'conviction'
    end
    if not kind then return nil end
    local system = { kind = 'system', label = 'orders', resource = J.RESOURCE }
    local res = J.Locks.With('record:' .. row.citizenid, function()
        return R.AddLocked(row.citizenid, kind, 'order', tostring(row.id), R.Summary(row), system)
    end)
    if type(res) ~= 'table' or res.ok ~= true then R.Queue(row.id) end
    return res
end

--- Writes the queued entries (deduplicated by order ref, so a repeat is harmless). The row is read
--- again, so an entry follows the order's current citizen id (a deleted character's token).
function R.RetryQueued()
    local done, ids = 0, {}
    for orderId in pairs(R.queue) do ids[#ids + 1] = orderId end -- OnOrderEnded may queue again
    for _, orderId in ipairs(ids) do
        local row = J.Orders and J.Orders.Row(orderId)
        if row then
            R.queue[orderId] = nil
            local res = R.OnOrderEnded(row, row.state) -- queues it again when it still cannot be written
            if res == nil or (type(res) == 'table' and res.ok == true) then
                done = done + 1
                pcall(MySQL.update.await, SQL.recordQueueDone, { queueKey(orderId) })
            end
        end
    end
    return done
end

--- Reloads the queue after a restart.
function R.LoadQueue()
    local ok, rows = pcall(MySQL.query.await, SQL.recordQueued, {})
    if not ok or type(rows) ~= 'table' then return false end
    for _, r in ipairs(rows) do
        local id = tonumber(r.order_id)
        if id then R.queue[id] = true end
    end
    return true
end

--- GetRecord (architecture 4.7.1). opts = { viewer = src?, limit?, includeExpunged? (pf-justice only) }.
function R.Get(cid, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    if not U.ValidCid(cid) then return Err('bad_args', 'cid is invalid') end
    if opts.viewer ~= nil and not U.Src(opts.viewer) then return Err('bad_args', 'viewer is not online') end
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    local limit = U.Int(opts.limit or Config.Records.MaxEntries, 1, Config.Records.MaxEntries) or Config.Records.MaxEntries
    local sql = (internal and opts.includeExpunged) and SQL.recordsAllByCid or SQL.recordsByCid
    local ok, rows = pcall(MySQL.query.await, sql, { cid, limit })
    if not ok or type(rows) ~= 'table' then return Err('db_unavailable', 'The justice database did not answer') end
    local rule = J.Callers.FieldRule(Config.RecordFields, ctx.invoker)
    local entries = {}
    for i, r in ipairs(rows) do entries[i] = J.Callers.Filter(publicEntry(r), rule) end
    return { ok = true, entries = entries }
end

--- Whether an actor may expunge: an admin, an on-duty judge, pf-government staff with the records
--- permission, or pf-justice itself (court decisions, b19).
function R.MayExpunge(actor, internal)
    if actor.kind == 'admin' then return true end
    if actor.kind == 'system' then return internal end
    if actor.kind ~= 'player' then return false end
    if (Config.Records.ExpungeJobs or {})[actor.job] and actor.onduty then return true end
    local perm = Config.Records.ExpungeGovPermission
    if perm and GetResourceState('pf-government') == 'started' then
        local ok, allowed = pcall(function() return exports['pf-government']:HasPermission(actor.src, perm) end)
        if ok and allowed == true then return true end
    end
    return false
end

--- Expunge (architecture 4.7.1): soft-deletes the listed entries of `cid`, audited.
--- opts = { actor, courtOrderId?, reason? }. Returns { ok, n }.
function R.Expunge(cid, entryIds, opts, ctx)
    if not J.Ready() then return Err('db_unavailable', 'The justice database is not ready') end
    opts = type(opts) == 'table' and opts or {}
    ctx = ctx or {}
    if not U.ValidCid(cid) or type(entryIds) ~= 'table' or #entryIds < 1 or #entryIds > 100 then
        return Err('bad_args', 'cid and 1..100 entry ids are required')
    end
    local ids, seen = {}, {}
    for _, v in ipairs(entryIds) do
        local id = U.Int(v, 1, 2147483647)
        if not id then return Err('bad_args', 'entry ids must be integers') end
        if not seen[id] then seen[id] = true ids[#ids + 1] = id end
    end
    local internal = ctx.invoker == nil or ctx.invoker == J.RESOURCE
    local actor, aerr = J.Actor.Resolve(opts.actor, ctx.invoker)
    if not actor then return aerr end
    if not R.MayExpunge(actor, internal) then return Err('no_permission', 'Only a judge, records staff or an admin may expunge') end
    local courtRef = U.Str(opts.courtOrderId, 64)
    return J.Locks.With('record:' .. cid, function()
        local now, n, done = os.time(), 0, {}
        for _, id in ipairs(ids) do
            local ok, res = pcall(MySQL.update.await, SQL.expungeRecord, { now, J.Actor.Tag(actor), courtRef, id, cid })
            if ok and U.Affected(res) == 1 then n = n + 1 done[#done + 1] = id end
        end
        J.Audit.Write('record', cid, 'expunge', { ids = done, asked = #ids, courtOrderId = courtRef, reason = U.Str(opts.reason, 200) }, actor)
        if n > 0 then J.Emit('recordChanged', cid, { action = 'expunge', entryIds = done }) end
        return { ok = true, n = n }
    end)
end

--- Moves every entry of a deleted character to `token` (orders.lua calls it with the cid lock held).
function R.Anonymise(cid, token)
    local ok, res = pcall(MySQL.update.await, SQL.anonRecords, { token, cid })
    pcall(MySQL.update.await, SQL.anonExpungedBy, { token, cid }) -- a deleted judge or clerk
    return ok and U.Affected(res) or 0
end
