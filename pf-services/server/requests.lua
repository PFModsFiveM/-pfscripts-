-- Service requests: one job (or a citizen, or the city) asks another job to do something.
--
--   local res = exports['pf-services']:CreateRequest({
--       kind = 'tow.impound', title = 'Impound ABC123', details = 'Parked on the sidewalk',
--       coords = GetEntityCoords(veh), plate = 'ABC123',
--       ref = { type = 'vehicle', id = 'ABC123' },          -- one open request per kind and ref
--       from = { type = 'job', id = 'police', name = 'Officer Smith' },
--   })
--   -- workers see it in the Dispatch app, accept it, do it, and complete it; the worker resource
--   -- registers the check that proves the work was done:
--   exports['pf-services']:RegisterRequestHandler('tow.impound', {
--       canComplete = function(req, src, proof) return vehicleIsInImpoundLot(req.plate) end,
--       onCompleted = function(req, src) ... end,
--   })
--
-- The database row is the truth: accept/complete/cancel are single conditional UPDATEs, so two
-- workers can never take the same request and a restart keeps every request. A reward is escrowed
-- from the payer into system:pf-services when the request is made, paid to the worker on completion
-- and refunded when the request is cancelled or expires (all ledger transfers with fixed keys).
-- Kinds with `confirm` pay only on proof: the worker marks the work done on site (server position),
-- the requester confirms or disputes it, and the sweep pays a worker seen on site once the
-- requester's window has passed. Once a worker has accepted, only that worker can give the request
-- back; the requester and the creating job may cancel only while it is open.

PFServices = PFServices or {}

local RequestKinds = {}
for kind, def in pairs(PFCatalog.Requests) do RequestKinds[kind] = def end
local Handlers = {}        -- kind -> { canComplete, onAccepted, onCompleted, onClosed, resource }
local lastCitizenRequest = {} -- citizenid -> os.time()

local OPEN, ACCEPTED, COMPLETED, CANCELLED, EXPIRED = 'open', 'accepted', 'completed', 'cancelled', 'expired'

local function QB() return exports['pfm-core']:GetCoreObject() end

local function playerOf(src)
    return QB().Functions.GetPlayer(tonumber(src))
end

local function cleanText(v, max)
    if v == nil then return nil end
    v = tostring(v):gsub('[%c]', ' ')
    if v == '' then return nil end
    return v:sub(1, max)
end

local function nameOf(Player)
    local ci = Player and Player.PlayerData and Player.PlayerData.charinfo or {}
    local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n or nil
end

local function jobsOf(def)
    if type(def.job) == 'table' then return def.job end
    return { def.job }
end

local function jobMatches(def, jobName)
    for _, j in ipairs(jobsOf(def)) do if j == jobName then return true end end
    return false
end

--- Whether `jobName` works `req`: it was made for that job, or its kind lists the job
--- (mechanic.roadside: every mechanic shop). The same rule as ListForJob's SQL; the Dispatch list,
--- accept and waypoint all use it.
function PFServices.WorksOn(jobName, req)
    if type(jobName) ~= 'string' or type(req) ~= 'table' then return false end
    if req.job == jobName then return true end
    local def = RequestKinds[req.kind]
    return def ~= nil and jobMatches(def, jobName)
end

local function affected(res)
    if type(res) == 'number' then return res end
    if type(res) == 'table' then return tonumber(res.affectedRows or res.changedRows) or 0 end
    return 0
end

-- ── kinds and handlers ─────────────────────────────────────────────

function PFServices.RegisterRequestKind(kind, def)
    if type(kind) ~= 'string' or not kind:match('^[%w%._%-]+$') or #kind > 64 then return false, 'bad kind' end
    if type(def) ~= 'table' or (type(def.job) ~= 'string' and type(def.job) ~= 'table') then return false, 'kind needs a job' end
    RequestKinds[kind] = {
        label = cleanText(def.label, 80) or kind,
        icon = cleanText(def.icon, 16) or '📋',
        job = def.job,
        payer = type(def.payer) == 'string' and def.payer or 'none',
        reward = math.max(0, tonumber(def.reward) or 0),
        verify = def.verify == true,
        expires = math.max(60, tonumber(def.expires) or 1800),
        citizen = def.citizen == true,
        business = def.business == true,
        confirm = def.confirm == true,
        onSiteRange = tonumber(def.onSiteRange),
        confirmWindow = tonumber(def.confirmWindow),
        supersedes = type(def.supersedes) == 'table' and def.supersedes or nil,
        description = cleanText(def.description, 200) or '',
    }
    return true
end

function PFServices.GetRequestKind(kind) return RequestKinds[kind] end
function PFServices.GetRequestKinds() return RequestKinds end

-- Handlers come from other resources through the RegisterRequestHandler export, so their functions
-- arrive as callable tables (FiveM function references, __cfx_functionReference), not as Lua
-- functions: they are checked with this, never with type(fn) == 'function'.
local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end
PFServices.Callable = callable

function PFServices.RegisterRequestHandler(kind, handler, resource)
    -- a funcref is a table too, but not a handler table (and cannot be indexed)
    if not RequestKinds[kind] or type(handler) ~= 'table' or callable(handler) then return false, 'unknown kind' end
    Handlers[kind] = {
        canComplete = callable(handler.canComplete) and handler.canComplete or nil,
        onAccepted = callable(handler.onAccepted) and handler.onAccepted or nil,
        onCompleted = callable(handler.onCompleted) and handler.onCompleted or nil,
        onClosed = callable(handler.onClosed) and handler.onClosed or nil,
        resource = resource or GetInvokingResource() or GetCurrentResourceName(),
    }
    return true
end

local function callHandler(kind, name, ...)
    local h = Handlers[kind]
    local fn = h and h[name]
    if not fn then return nil end
    if h.resource ~= GetCurrentResourceName() and GetResourceState(h.resource) ~= 'started' then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        print(('^1[pf-services]^7 %s.%s failed: %s'):format(kind, name, tostring(a)))
        return false, 'handler_error'
    end
    return a, b
end

-- ── rows ───────────────────────────────────────────────────────────

local COLUMNS = [[id, kind, job, status, title, details, x, y, z, plate, ref_type, ref_id, from_type, from_id, from_name,
    requester_cid, assignee_cid, assignee_name, payer, reward, escrow_state, meta,
    UNIX_TIMESTAMP(created_at) AS created, UNIX_TIMESTAMP(accepted_at) AS accepted,
    UNIX_TIMESTAMP(closed_at) AS closed, UNIX_TIMESTAMP(expires_at) AS expires, close_reason]]

local function decodeRow(r)
    if not r then return nil end
    local meta = {}
    if type(r.meta) == 'string' and r.meta ~= '' then meta = json.decode(r.meta) or {} end
    return {
        id = tonumber(r.id), kind = r.kind, job = r.job, status = r.status, title = r.title, details = r.details,
        coords = r.x and { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z) } or nil,
        plate = r.plate, ref = r.ref_type and { type = r.ref_type, id = r.ref_id } or nil,
        from = { type = r.from_type, id = r.from_id, name = r.from_name },
        requester = r.requester_cid, assignee = r.assignee_cid, assigneeName = r.assignee_name,
        payer = r.payer, reward = tonumber(r.reward) or 0, escrow = r.escrow_state, meta = meta,
        created = tonumber(r.created), accepted = tonumber(r.accepted), closed = tonumber(r.closed),
        expires = tonumber(r.expires), closeReason = r.close_reason,
    }
end

function PFServices.GetRequest(id)
    id = tonumber(id)
    if not id then return nil end
    return decodeRow(MySQL.single.await('SELECT ' .. COLUMNS .. ' FROM pf_service_requests WHERE id = ?', { id }))
end

local function listWhere(where, params, limit)
    local rows = MySQL.query.await('SELECT ' .. COLUMNS .. ' FROM pf_service_requests WHERE ' .. where ..
        ' ORDER BY id DESC LIMIT ' .. math.floor(limit or 50), params) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = decodeRow(r) end
    return out
end

-- Kinds a job works (a kind may list several jobs, e.g. every mechanic shop).
local function kindsForJob(job)
    local out = {}
    for kind, def in pairs(RequestKinds) do if jobMatches(def, job) then out[#out + 1] = kind end end
    table.sort(out)
    return out
end
PFServices.KindsForJob = kindsForJob

function PFServices.ListForJob(job, includeClosed)
    local kinds = kindsForJob(job)
    local cond, params = 'job = ?', { job }
    if #kinds > 0 then
        cond = '(job = ? OR kind IN (' .. string.rep('?', #kinds, ', ') .. '))'
        for _, k in ipairs(kinds) do params[#params + 1] = k end
    end
    params[#params + 1] = OPEN
    params[#params + 1] = ACCEPTED
    if includeClosed then
        return listWhere(cond .. ' AND (status IN (?, ?) OR closed_at >= NOW() - INTERVAL 1 DAY)', params, 100)
    end
    return listWhere(cond .. ' AND status IN (?, ?)', params, 100)
end

function PFServices.ListForCitizen(cid)
    return listWhere('requester_cid = ? AND (status IN (?, ?) OR closed_at >= NOW() - INTERVAL 1 DAY)', { cid, OPEN, ACCEPTED }, 30)
end

function PFServices.ListForAssignee(cid)
    return listWhere('assignee_cid = ? AND status = ?', { cid, ACCEPTED }, 20)
end

--- The open (or accepted) request on a ref; with `kind`, only a request of that kind.
function PFServices.FindOpenByRef(refType, refId, kind)
    if not refType or refId == nil then return nil end
    if type(kind) == 'string' then
        local rows = listWhere('ref_type = ? AND ref_id = ? AND kind = ? AND status IN (?, ?)', { refType, tostring(refId), kind, OPEN, ACCEPTED }, 1)
        return rows[1]
    end
    local rows = listWhere('ref_type = ? AND ref_id = ? AND status IN (?, ?)', { refType, tostring(refId), OPEN, ACCEPTED }, 1)
    return rows[1]
end

-- Open requests of `kinds` about the same vehicle: the same plate or the same ref.
local function openOfKindsFor(kinds, plate, refType, refId)
    if type(kinds) ~= 'table' or #kinds == 0 or (not plate and not refType) then return {} end
    local params = {}
    for _, k in ipairs(kinds) do params[#params + 1] = k end
    params[#params + 1] = OPEN
    params[#params + 1] = ACCEPTED
    params[#params + 1] = plate or ''
    params[#params + 1] = refType or ''
    params[#params + 1] = refId and tostring(refId) or ''
    return listWhere('kind IN (' .. string.rep('?', #kinds, ', ') .. ') AND status IN (?, ?) AND (plate = ? OR (ref_type = ? AND ref_id = ?))', params, 20)
end

-- Kinds whose catalog entry supersedes `kind`.
local function supersedersOf(kind)
    local out = {}
    for k, def in pairs(RequestKinds) do
        for _, s in ipairs(type(def.supersedes) == 'table' and def.supersedes or {}) do
            if s == kind then out[#out + 1] = k break end
        end
    end
    table.sort(out)
    return out
end

-- The worker's recorded on-site visit, if it belongs to the current assignee.
local function onSiteOf(req)
    local v = req and type(req.meta) == 'table' and req.meta.onSite
    if type(v) ~= 'table' or not req.assignee or v.cid ~= req.assignee or not tonumber(v.at) then return nil end
    return v
end

local function confirmWindowOf(def)
    return tonumber(def and def.confirmWindow) or tonumber(Config.Requests.confirmWindow) or 600
end

local function metaWithout(meta, key)
    local out = {}
    for k, v in pairs(type(meta) == 'table' and meta or {}) do if k ~= key then out[k] = v end end
    local ok, s = pcall(json.encode, out)
    return ok and s or '{}'
end

-- ── money ──────────────────────────────────────────────────────────

local function payerAccount(req)
    if req.payer == 'requester' then
        return req.requester and ('player:%s:bank'):format(req.requester) or nil
    end
    if type(req.payer) == 'string' and req.payer:match('^society:[%w_%-]+$') then return req.payer end
    return nil
end

local function transfer(opts)
    if type(PFPayout) == 'table' and type(PFPayout.Transfer) == 'function' then
        return PFPayout.Transfer(opts)
    end
    if GetResourceState('pfm-banking') ~= 'started' then return { ok = false, error = 'bank_unavailable' } end
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

local ESCROW = 'system:pf-services'

local function holdEscrow(req)
    local from = payerAccount(req)
    if not from or req.reward <= 0 then return { ok = true, skipped = true } end
    return transfer({ from = from, to = ESCROW, amount = req.reward, key = ('pf-services:req:%d:escrow'):format(req.id),
        kind = 'service_escrow', reason = req.title, actor = req.requester, metadata = { request = req.id, kind = req.kind } })
end

local function payWorker(req, cid)
    if req.escrow ~= 'held' or req.reward <= 0 then return { ok = true, skipped = true } end
    return transfer({ from = ESCROW, to = ('player:%s:bank'):format(cid), amount = req.reward,
        key = ('pf-services:req:%d:pay'):format(req.id), kind = 'wage', reason = req.title, actor = cid,
        metadata = { request = req.id, kind = req.kind } })
end

-- A ledger key whose attempt failed or was compensated can never succeed again, so a retry after
-- such an attempt uses the next numbered key (the sweep used to retry the dead key forever). A
-- payer whose account is gone (a deleted character) cannot be refunded at all: the result says
-- `forfeit` and the money stays in escrow.
local REFUND_ATTEMPTS = 10
local function refund(req)
    if req.escrow ~= 'held' or req.reward <= 0 then return { ok = true, skipped = true } end
    local to = payerAccount(req)
    if not to then return { ok = false, error = 'no_payer' } end
    local base = ('pf-services:req:%d:refund'):format(req.id)
    local res
    for attempt = 0, REFUND_ATTEMPTS - 1 do
        res = transfer({ from = ESCROW, to = to, amount = req.reward, key = attempt == 0 and base or (base .. ':' .. attempt),
            kind = 'refund', reason = req.title, metadata = { request = req.id, kind = req.kind } })
        local dead = not res.ok and res.duplicate and (res.state == 'failed' or res.state == 'compensated')
        if not dead then break end
    end
    -- only a fresh attempt's error counts: a stored attempt carries the error it had back then
    if not res.ok and not res.duplicate and res.error == 'unknown_account' then res.forfeit = true end
    return res
end

-- ── views and notifications ────────────────────────────────────────

-- Only these meta fields reach clients (meta may hold citizen ids and internal values).
local PUBLIC_META = { reason = true, shop = true, destination = true, kind = true, price = true, fullImpound = true }
local function safeMeta(meta)
    if type(meta) ~= 'table' then return nil end
    local out = {}
    for k, v in pairs(meta) do if PUBLIC_META[k] then out[k] = v end end
    return out
end

--- What a client may see of a request. Workers of the job and the requester get the position.
function PFServices.PublicView(req, viewerCid, viewerJob)
    if not req then return nil end
    local def = RequestKinds[req.kind] or {}
    local isWorker = PFServices.WorksOn(viewerJob, req)
    local isRequester = viewerCid ~= nil and req.requester == viewerCid
    local isAssignee = viewerCid ~= nil and req.assignee == viewerCid
    local view = {
        id = req.id, kind = req.kind, label = def.label or req.kind, icon = def.icon or '📋', job = req.job,
        status = req.status, title = req.title, details = req.details,
        coords = (isWorker or isRequester) and req.coords or nil,
        plate = (isWorker or isRequester) and req.plate or nil,
        fromName = req.from and req.from.name or nil, fromType = req.from and req.from.type or nil,
        assigneeName = req.assigneeName, reward = req.reward, paid = req.escrow == 'held' or req.escrow == 'paid',
        created = req.created, accepted = req.accepted, closed = req.closed, expires = req.expires,
        closeReason = req.closeReason, mine = isAssignee, requestedByMe = isRequester,
        verify = def.verify == true, business = def.business == true,
        meta = (isWorker or isRequester) and safeMeta(req.meta) or nil,
    }
    if def.confirm then
        local site = onSiteOf(req)
        view.confirm = true
        view.onSite = site ~= nil
        view.confirmBy = site and (math.floor(tonumber(site.at)) + confirmWindowOf(def)) or nil
    end
    return view
end

local function workerJobs(req)
    local def = RequestKinds[req.kind]
    local jobs, seen = {}, {}
    for _, j in ipairs(def and jobsOf(def) or {}) do if not seen[j] then seen[j] = true; jobs[#jobs + 1] = j end end
    if not seen[req.job] then jobs[#jobs + 1] = req.job end
    return jobs, seen
end

local function push(req, event)
    if GetResourceState('pf-devices') ~= 'started' and GetCurrentResourceName() ~= 'pf-devices' then return end
    pcall(function()
        for _, job in ipairs((workerJobs(req))) do
            exports['pf-devices']:PushToJob(job, 'dispatch', event, { id = req.id, status = req.status, kind = req.kind }, true)
        end
        if req.requester then
            exports['pf-devices']:PushToCitizen(req.requester, 'services', event, { id = req.id, status = req.status, kind = req.kind })
        end
    end)
end

local function notifyJob(req)
    local def = RequestKinds[req.kind] or {}
    local _, isWorkerJob = workerJobs(req)
    for src, Player in pairs(QB().Functions.GetQBPlayers() or {}) do
        local job = Player.PlayerData and Player.PlayerData.job
        if job and isWorkerJob[job.name] and job.onduty then
            TriggerClientEvent('QBCore:Notify', Player.PlayerData.source or src, ('%s %s: %s'):format(def.icon or '📋', def.label or req.kind, req.title), 'primary', 6000)
            TriggerClientEvent('pf-services:client:newRequest', Player.PlayerData.source or src, PFServices.PublicView(req, nil, job.name))
        end
    end
end

local function tellCitizen(cid, message, kind)
    if not cid then return end
    local Player = QB().Functions.GetPlayerByCitizenId(cid)
    if Player then TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, message, kind or 'primary', 6000) end
end

-- ── lifecycle ──────────────────────────────────────────────────────

local finish -- defined below; closes a request and settles its escrow

--- Creates a request. Returns { ok, id, request } or { ok = false, error }. Server-only.
--- One open request per kind and ref: a second call returns the open one (existing = true).
function PFServices.CreateRequest(opts)
    if type(opts) ~= 'table' then return { ok = false, error = 'bad_request' } end
    local def = RequestKinds[opts.kind]
    if not def then return { ok = false, error = 'unknown_kind' } end

    local ref = type(opts.ref) == 'table' and opts.ref.type and opts.ref.id ~= nil and opts.ref or nil
    local refType, refId = ref and cleanText(ref.type, 32) or nil, ref and cleanText(ref.id, 64) or nil
    if ref then
        local existing = PFServices.FindOpenByRef(refType, refId, opts.kind)
        if existing then return { ok = true, id = existing.id, request = existing, existing = true } end
    end
    local plateKey = cleanText(opts.plate, 16)
    -- a kind that supersedes this one is already working the vehicle (police impound over a tow)
    local blocking = openOfKindsFor(supersedersOf(opts.kind), plateKey, refType, refId)
    if blocking[1] then return { ok = false, error = 'superseded', by = blocking[1].id, byKind = blocking[1].kind } end
    -- this kind takes precedence: the requests it replaces are cancelled and refunded first
    for _, old in ipairs(openOfKindsFor(def.supersedes, plateKey, refType, refId)) do
        if finish(old, CANCELLED, 'superseded') then
            tellCitizen(old.requester, ('Your %s request was cancelled: %s'):format((RequestKinds[old.kind] or {}).label or 'service', def.label or opts.kind), 'error')
            if old.assignee then tellCitizen(old.assignee, ('Request #%d was cancelled (%s).'):format(old.id, def.label or opts.kind), 'error') end
        end
    end

    local from = type(opts.from) == 'table' and opts.from or { type = 'system' }
    local fromType = from.type
    if fromType ~= 'job' and fromType ~= 'citizen' and fromType ~= 'system' and fromType ~= 'business' then fromType = 'system' end
    local coords = PFServices.coordsOf(opts.coords)
    local job = type(def.job) == 'table' and (opts.job or def.job[1]) or def.job
    if not jobMatches(def, job) then return { ok = false, error = 'bad_job' } end

    local reward = def.reward
    if opts.reward ~= nil then reward = math.max(0, math.floor((tonumber(opts.reward) or 0) * 100) / 100) end
    local payer = opts.payer or def.payer
    if payer == 'none' then reward = 0 end
    local requester = cleanText(opts.requester, 50)
    if payer == 'requester' and not requester then payer, reward = 'none', 0 end

    local okMeta, metaJson = pcall(json.encode, type(opts.meta) == 'table' and opts.meta or {})
    local expiresIn = math.max(60, tonumber(opts.expires) or def.expires or 1800)
    local id = MySQL.insert.await([[INSERT INTO pf_service_requests
        (kind, job, status, title, details, x, y, z, plate, ref_type, ref_id, from_type, from_id, from_name,
         requester_cid, payer, reward, escrow_state, meta, expires_at)
        VALUES (?, ?, 'open', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? SECOND)]], {
        opts.kind, job, cleanText(opts.title, 160) or def.label, cleanText(opts.details, 1000),
        coords and coords.x or nil, coords and coords.y or nil, coords and coords.z or nil,
        cleanText(opts.plate, 16), ref and cleanText(ref.type, 32) or nil, ref and cleanText(ref.id, 64) or nil,
        fromType, cleanText(from.id, 64), cleanText(from.name, 100), requester, payer, reward,
        reward > 0 and 'pending' or 'none', okMeta and metaJson or '{}', math.floor(expiresIn),
    })
    id = tonumber(id)
    if not id then return { ok = false, error = 'db_error' } end
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'db_error' } end

    if reward > 0 then
        local res = holdEscrow(req)
        -- another call holds the escrow key (the sweep): wait for its result instead of cancelling
        -- a request whose money may be moving right now
        for _ = 1, 20 do
            if res.ok or res.error ~= 'in_progress' then break end
            Wait(250)
            res = holdEscrow(req)
        end
        if not res.ok and res.error == 'in_progress' then
            -- still undecided: the row stays 'pending' and the sweep settles it from the ledger key
            notifyJob(req)
            push(req, 'request:new')
            TriggerEvent('pf-services:requestChanged', req, 'created')
            return { ok = true, id = id, request = req, pending = true }
        elseif res.ok then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'held' WHERE id = ?", { id })
            req.escrow = 'held'
        elseif payer == 'requester' then
            -- a citizen who cannot pay does not get the call-out
            MySQL.update.await("UPDATE pf_service_requests SET status = 'cancelled', escrow_state = 'failed', closed_at = NOW(), close_reason = 'payment_failed' WHERE id = ?", { id })
            return { ok = false, error = res.error == 'bank_unavailable' and 'bank_unavailable' or 'insufficient_funds' }
        else
            -- a job or the city could not fund it: the work is still needed, it is just unpaid
            MySQL.update.await("UPDATE pf_service_requests SET reward = 0, escrow_state = 'failed' WHERE id = ?", { id })
            req.reward, req.escrow = 0, 'failed'
        end
    end

    notifyJob(req)
    push(req, 'request:new')
    TriggerEvent('pf-services:requestChanged', req, 'created')
    return { ok = true, id = id, request = req }
end

local function workerCheck(src, req)
    local Player = playerOf(src)
    if not Player then return nil, 'no_player' end
    local job = Player.PlayerData.job or {}
    if not RequestKinds[req.kind] or not PFServices.WorksOn(job.name, req) then return nil, 'wrong_job' end
    if not job.onduty then return nil, 'off_duty' end
    return Player
end

function PFServices.AcceptRequest(src, id)
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.status ~= OPEN then return { ok = false, error = 'not_open' } end
    local Player, err = workerCheck(src, req)
    if not Player then return { ok = false, error = err } end
    local cid = Player.PlayerData.citizenid
    if req.requester and req.requester == cid then return { ok = false, error = 'own_request' } end
    local active = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM pf_service_requests WHERE assignee_cid = ? AND status = 'accepted'", { cid })) or 0
    if active >= (Config.Requests.maxActivePerWorker or 2) then return { ok = false, error = 'too_many_active' } end
    if Config.Requests.acceptRange and req.coords then
        local pos = GetEntityCoords(GetPlayerPed(src))
        if #(pos - vector3(req.coords.x, req.coords.y, req.coords.z or 0.0)) > Config.Requests.acceptRange then
            return { ok = false, error = 'too_far' }
        end
    end
    local n = affected(MySQL.update.await([[UPDATE pf_service_requests SET status = 'accepted', assignee_cid = ?, assignee_name = ?, accepted_at = NOW()
        WHERE id = ? AND status = 'open']], { cid, nameOf(Player), req.id }))
    if n ~= 1 then return { ok = false, error = 'taken' } end
    req = PFServices.GetRequest(req.id)
    callHandler(req.kind, 'onAccepted', req, src)
    tellCitizen(req.requester, ('%s is on the way.'):format(req.assigneeName or 'Someone'), 'success')
    push(req, 'request:changed')
    TriggerEvent('pf-services:requestChanged', req, 'accepted')
    return { ok = true, request = req }
end

--- The assignee gives the request back to the queue.
function PFServices.ReleaseRequest(src, id)
    local Player = playerOf(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.status ~= ACCEPTED or req.assignee ~= Player.PlayerData.citizenid then return { ok = false, error = 'not_yours' } end
    -- an on-site visit belongs to the worker who gives the request back: it is dropped with them
    local n = affected(MySQL.update.await([[UPDATE pf_service_requests SET status = 'open', assignee_cid = NULL, assignee_name = NULL, accepted_at = NULL, meta = ?
        WHERE id = ? AND status = 'accepted' AND assignee_cid = ?]], { metaWithout(req.meta, 'onSite'), req.id, req.assignee }))
    if n ~= 1 then return { ok = false, error = 'changed' } end
    req = PFServices.GetRequest(req.id)
    push(req, 'request:changed')
    TriggerEvent('pf-services:requestChanged', req, 'released')
    return { ok = true, request = req }
end

-- `fromStatus` limits the close to a request still in that status (a player's cancel: 'open').
function finish(req, status, reason, workerCid, fromStatus)
    local n
    if fromStatus then
        n = affected(MySQL.update.await([[UPDATE pf_service_requests SET status = ?, closed_at = NOW(), close_reason = ?
            WHERE id = ? AND status = ?]], { status, reason, req.id, fromStatus }))
    else
        n = affected(MySQL.update.await([[UPDATE pf_service_requests SET status = ?, closed_at = NOW(), close_reason = ?
            WHERE id = ? AND status IN ('open', 'accepted')]], { status, reason, req.id }))
    end
    if n ~= 1 then return false end
    req.status, req.closeReason = status, reason
    -- completed with nobody to pay (closed by the system before anyone accepted): the payer gets it back
    if status == COMPLETED and not workerCid then status = 'completed_unassigned' end
    if status == COMPLETED and workerCid then
        local res = payWorker(req, workerCid)
        if res.ok and not res.skipped then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'paid' WHERE id = ?", { req.id })
            req.escrow = 'paid'
        elseif not res.ok then
            -- the job is done; the payment is retried by the sweep (same ledger key, so never twice)
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'owed' WHERE id = ?", { req.id })
            req.escrow = 'owed'
        end
    elseif status ~= COMPLETED then
        local res = refund(req)
        if res.ok and not res.skipped then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'refunded' WHERE id = ?", { req.id })
            req.escrow = 'refunded'
        elseif res.forfeit then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'forfeited' WHERE id = ?", { req.id })
            req.escrow = 'forfeited'
        elseif not res.ok then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'refund_owed' WHERE id = ?", { req.id })
            req.escrow = 'refund_owed'
        end
    end
    if status == 'completed_unassigned' then status = COMPLETED end
    callHandler(req.kind, status == COMPLETED and 'onCompleted' or 'onClosed', req, reason)
    push(req, 'request:changed')
    TriggerEvent('pf-services:requestChanged', req, status)
    return true
end

-- Kinds paid on the requester's confirmation: the worker reports the work done only from the
-- request's location (server-side position), and that visit is recorded. Nothing is paid here.
local function markOnSite(src, Player, req, def, proof)
    if Handlers[req.kind] and Handlers[req.kind].canComplete then
        local ok, why = callHandler(req.kind, 'canComplete', req, src, type(proof) == 'table' and proof or {})
        if ok ~= true then return { ok = false, error = why or 'not_done' } end
    end
    if not req.coords then return { ok = false, error = 'no_location' } end
    local cid = Player.PlayerData.citizenid
    if not onSiteOf(req) then
        local range = tonumber(def.onSiteRange) or tonumber(Config.Requests.onSiteRange) or 30.0
        local pos = GetEntityCoords(GetPlayerPed(src))
        if not pos then return { ok = false, error = 'too_far' } end
        local dist = #(vector3(pos.x, pos.y, pos.z or 0.0) - vector3(req.coords.x, req.coords.y, req.coords.z or 0.0))
        if dist > range then return { ok = false, error = 'too_far', range = range } end
        local meta = type(req.meta) == 'table' and req.meta or {}
        meta.onSite = { cid = cid, at = os.time(), dist = math.floor(dist * 10) / 10,
            x = math.floor(pos.x * 10) / 10, y = math.floor(pos.y * 10) / 10 }
        local okMeta, metaJson = pcall(json.encode, meta)
        if not okMeta then return { ok = false, error = 'db_error' } end
        local n = affected(MySQL.update.await("UPDATE pf_service_requests SET meta = ? WHERE id = ? AND status = 'accepted' AND assignee_cid = ?",
            { metaJson, req.id, cid }))
        if n ~= 1 then return { ok = false, error = 'changed' } end
        req = PFServices.GetRequest(req.id) or req
        tellCitizen(req.requester, ('%s says your %s is done. Confirm it or report it in the Services app.'):format(
            req.assigneeName or 'The worker', (def.label or 'service'):lower()), 'primary')
        push(req, 'request:changed')
        TriggerEvent('pf-services:requestChanged', req, 'on_site')
    end
    return { ok = true, pending = 'requester_confirmation', request = req }
end

--- The assignee reports the work done. Kinds that verify need the worker resource's check to pass;
--- kinds that confirm only record the on-site visit (the requester confirms, or the window ends).
function PFServices.CompleteRequest(src, id, proof)
    local Player = playerOf(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.status ~= ACCEPTED or req.assignee ~= Player.PlayerData.citizenid then return { ok = false, error = 'not_yours' } end
    local def = RequestKinds[req.kind] or {}
    local handler = Handlers[req.kind]
    if def.confirm then return markOnSite(src, Player, req, def, proof) end
    if handler and handler.canComplete then
        local ok, why = callHandler(req.kind, 'canComplete', req, src, type(proof) == 'table' and proof or {})
        if ok ~= true then return { ok = false, error = why or 'not_done' } end
    elseif def.verify and req.reward > 0 then
        -- paid work nobody can check yet: the requester has to confirm it
        if not req.requester then return { ok = false, error = 'needs_verification' } end
        return { ok = false, error = 'needs_requester_confirmation' }
    end
    if not finish(req, COMPLETED, 'done', Player.PlayerData.citizenid) then return { ok = false, error = 'changed' } end
    tellCitizen(req.requester, ('Your %s request is complete.'):format(def.label or 'service'), 'success')
    return { ok = true, request = PFServices.GetRequest(req.id) }
end

--- The citizen who asked confirms the work was done (pays the worker if there is a reward).
function PFServices.ConfirmRequest(src, id)
    local Player = playerOf(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.requester ~= Player.PlayerData.citizenid then return { ok = false, error = 'not_yours' } end
    if req.status ~= ACCEPTED or not req.assignee then return { ok = false, error = 'not_accepted' } end
    if not finish(req, COMPLETED, 'confirmed', req.assignee, ACCEPTED) then return { ok = false, error = 'changed' } end
    tellCitizen(req.assignee, ('%s confirmed the job. Payment sent.'):format(nameOf(Player) or 'The customer'), 'success')
    return { ok = true, request = PFServices.GetRequest(req.id) }
end

--- The requester reports the work of a confirm kind as not done (after the worker marked it done
--- on site): the request closes and the requester is refunded.
function PFServices.DisputeRequest(src, id)
    local Player = playerOf(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.requester ~= Player.PlayerData.citizenid then return { ok = false, error = 'not_yours' } end
    local def = RequestKinds[req.kind] or {}
    if not def.confirm then return { ok = false, error = 'no_dispute' } end
    if req.status ~= ACCEPTED or not req.assignee then return { ok = false, error = 'not_accepted' } end
    if not onSiteOf(req) then return { ok = false, error = 'not_marked_done' } end
    if not finish(req, CANCELLED, 'disputed', nil, ACCEPTED) then return { ok = false, error = 'changed' } end
    tellCitizen(req.assignee, ('%s reported request #%d as not fixed. No payment.'):format(nameOf(Player) or 'The customer', req.id), 'error')
    return { ok = true, request = PFServices.GetRequest(req.id) }
end

--- The requester (or the job that made it) cancels an OPEN request (refund); once a worker has
--- accepted it only that worker can give it back, and expiry settles the rest. A server resource
--- closes a request in any open state (src = nil).
function PFServices.CancelRequest(src, id, reason)
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.status ~= OPEN and req.status ~= ACCEPTED then return { ok = false, error = 'closed' } end
    local fromStatus
    if src ~= nil then
        local Player = playerOf(src)
        if not Player then return { ok = false, error = 'no_player' } end
        local cid = Player.PlayerData.citizenid
        local job = Player.PlayerData.job or {}
        local creatorJob = req.from and req.from.type == 'job' and req.from.id == job.name and job.onduty
        if req.requester ~= cid and not creatorJob then return { ok = false, error = 'not_yours' } end
        if req.status ~= OPEN then return { ok = false, error = 'already_accepted' } end
        fromStatus = OPEN
    end
    if not finish(req, CANCELLED, cleanText(reason, 64) or 'cancelled', nil, fromStatus) then return { ok = false, error = 'changed' } end
    if req.assignee then tellCitizen(req.assignee, ('Request #%d was cancelled.'):format(req.id), 'error') end
    return { ok = true }
end

--- Server resources close the request tied to something they track (EMS revived the patient, the
--- impounded car was released). status: 'completed' (pays the assignee, if any) or 'cancelled'.
--- kind (optional) limits it to a request of that kind.
function PFServices.CloseByRef(refType, refId, status, reason, kind)
    local req = PFServices.FindOpenByRef(refType, refId, kind)
    if not req then return { ok = false, error = 'not_found' } end
    if status == COMPLETED then
        if not finish(req, COMPLETED, cleanText(reason, 64) or 'done', req.assignee) then return { ok = false, error = 'changed' } end
    else
        if not finish(req, CANCELLED, cleanText(reason, 64) or 'cancelled') then return { ok = false, error = 'changed' } end
    end
    return { ok = true, id = req.id }
end

--- Expired requests close (and refund); completed requests whose payment failed are paid again.
--- Confirm kinds: a worker seen on site is paid once the requester's window has passed (an
--- on-site visit keeps the request from expiring into a refund); without a visit expiry refunds.
function PFServices.SweepRequests()
    local confirmKinds = {}
    for kind, def in pairs(RequestKinds) do if def.confirm then confirmKinds[#confirmKinds + 1] = kind end end
    table.sort(confirmKinds)
    if #confirmKinds > 0 then
        local params = {}
        for _, k in ipairs(confirmKinds) do params[#params + 1] = k end
        local rows = listWhere("status = 'accepted' AND kind IN (" .. string.rep('?', #confirmKinds, ', ') .. ')', params, 200)
        local now = os.time()
        for _, req in ipairs(rows) do
            local site = onSiteOf(req)
            if site and now - tonumber(site.at) >= confirmWindowOf(RequestKinds[req.kind]) then
                if finish(req, COMPLETED, 'auto_confirmed', req.assignee, ACCEPTED) then
                    tellCitizen(req.assignee, ('Request #%d: the customer did not respond. Payment sent.'):format(req.id), 'success')
                end
            end
        end
    end
    local expired = listWhere("status IN ('open', 'accepted') AND expires_at IS NOT NULL AND expires_at < NOW()", {}, 200)
    local closed = 0
    for _, req in ipairs(expired) do
        local def = RequestKinds[req.kind] or {}
        if not (def.confirm and req.status == ACCEPTED and onSiteOf(req)) then
            if finish(req, EXPIRED, 'expired') then closed = closed + 1 end
        end
    end
    for _, req in ipairs(listWhere("status = 'completed' AND escrow_state = 'owed'", {}, 100)) do
        req.escrow = 'held'
        local res = payWorker(req, req.assignee)
        if res.ok then MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'paid' WHERE id = ?", { req.id }) end
    end
    for _, req in ipairs(listWhere("status IN ('cancelled', 'expired') AND escrow_state = 'refund_owed'", {}, 100)) do
        req.escrow = 'held'
        local res = refund(req)
        if res.ok then MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'refunded' WHERE id = ?", { req.id })
        elseif res.forfeit then MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'forfeited' WHERE id = ?", { req.id }) end
    end
    -- a crash between the insert and the escrow leaves 'pending': the ledger key tells whether it
    -- moved. Only rows older than a minute (CreateRequest settles its own), and the row is updated
    -- only while it is still open and pending: if it closed meanwhile, money that moved goes back.
    for _, req in ipairs(listWhere("status IN ('open', 'accepted') AND escrow_state = 'pending' AND created_at < NOW() - INTERVAL 60 SECOND", {}, 100)) do
        local res = holdEscrow(req)
        if res.ok then
            local n = affected(MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'held' WHERE id = ? AND escrow_state = 'pending' AND status IN ('open', 'accepted')", { req.id }))
            if n ~= 1 and not res.skipped then
                local cur = PFServices.GetRequest(req.id)
                if cur and cur.status ~= OPEN and cur.status ~= ACCEPTED and (cur.escrow == 'pending' or cur.escrow == 'failed') then
                    cur.escrow = 'held'
                    local r = refund(cur)
                    local state = r.ok and 'refunded' or (r.forfeit and 'forfeited' or 'refund_owed')
                    MySQL.update.await('UPDATE pf_service_requests SET escrow_state = ? WHERE id = ?', { state, cur.id })
                end
            end
        elseif res.error ~= 'in_progress' then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'failed' WHERE id = ? AND escrow_state = 'pending'", { req.id })
        end
    end
    return closed
end

-- ── citizen requests (the Services app) ────────────────────────────

--- A citizen asks for a service at their own position (never a client-sent position).
function PFServices.CitizenRequest(src, kind, details)
    local def = RequestKinds[kind]
    if not def or not def.citizen then return { ok = false, error = 'unknown_kind' } end
    local Player = playerOf(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local cid = Player.PlayerData.citizenid
    local now = os.time()
    if lastCitizenRequest[cid] and now - lastCitizenRequest[cid] < (Config.Requests.citizenCooldown or 60) then
        return { ok = false, error = 'cooldown' }
    end
    local open = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM pf_service_requests WHERE requester_cid = ? AND status IN ('open', 'accepted')", { cid })) or 0
    if open >= (Config.Requests.maxOpenPerCitizen or 2) then return { ok = false, error = 'too_many_open' } end
    local ped = GetPlayerPed(src)
    local pos = GetEntityCoords(ped)
    lastCitizenRequest[cid] = now
    local name = nameOf(Player) or 'A citizen'
    -- vehicle services are about the car the citizen is in, or the one right next to them
    local plate
    if kind == 'tow.recovery' or kind == 'mechanic.roadside' then
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then
            for _, v in ipairs(GetAllVehicles and GetAllVehicles() or {}) do
                if #(GetEntityCoords(v) - pos) <= 6.0 then veh = v break end
            end
        end
        if veh and veh ~= 0 then plate = (tostring(GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
        if kind == 'tow.recovery' and (not plate or plate == '') then
            lastCitizenRequest[cid] = nil
            return { ok = false, error = 'no_vehicle' }
        end
    end
    local res = PFServices.CreateRequest({
        kind = kind, title = ('%s for %s'):format(def.label, name), details = cleanText(details, 300),
        coords = pos, plate = plate, from = { type = 'citizen', id = cid, name = name }, requester = cid,
        ref = { type = 'citizen:' .. kind, id = cid },
    })
    if not res.ok then lastCitizenRequest[cid] = nil end
    return res
end

--- A character was deleted: its own open requests are cancelled (the escrow is refunded the
--- usual way) and requests it had accepted go back to the queue so another worker can take them.
function PFServices.ForgetCitizen(cid)
    if type(cid) ~= 'string' or cid == '' then return 0 end
    local cancelled = 0
    for _, req in ipairs(listWhere("requester_cid = ? AND status IN ('open', 'accepted')", { cid }, 50)) do
        -- the character paid from their own bank, which is gone: the escrow stays (forfeited)
        if req.payer == 'requester' and req.escrow == 'held' then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'forfeited' WHERE id = ? AND escrow_state = 'held'", { req.id })
            req.escrow = 'forfeited'
        end
        if finish(req, CANCELLED, 'character_deleted') then cancelled = cancelled + 1 end
    end
    for _, req in ipairs(listWhere("assignee_cid = ? AND status = 'accepted'", { cid }, 50)) do
        local n = affected(MySQL.update.await([[UPDATE pf_service_requests SET status = 'open', assignee_cid = NULL, assignee_name = NULL, accepted_at = NULL, meta = ?
            WHERE id = ? AND status = 'accepted' AND assignee_cid = ?]], { metaWithout(req.meta, 'onSite'), req.id, cid }))
        if n == 1 then
            req = PFServices.GetRequest(req.id)
            if req then
                push(req, 'request:changed')
                TriggerEvent('pf-services:requestChanged', req, 'released')
            end
        end
    end
    return cancelled
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    PFServices.ForgetCitizen(citizenid)
end)

function PFServices.__resetRequests()
    RequestKinds, Handlers, lastCitizenRequest = {}, {}, {}
    for kind, def in pairs(PFCatalog.Requests) do RequestKinds[kind] = def end
end
