-- Service requests: one job (or a citizen, or the city) asks another job to do something.
--
--   local res = exports['pf-services']:CreateRequest({
--       kind = 'tow.impound', title = 'Impound ABC123', details = 'Parked on the sidewalk',
--       coords = GetEntityCoords(veh), plate = 'ABC123',
--       ref = { type = 'vehicle', id = 'ABC123' },          -- one open request per ref
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
        description = cleanText(def.description, 200) or '',
    }
    return true
end

function PFServices.GetRequestKind(kind) return RequestKinds[kind] end
function PFServices.GetRequestKinds() return RequestKinds end

function PFServices.RegisterRequestHandler(kind, handler, resource)
    if not RequestKinds[kind] or type(handler) ~= 'table' then return false, 'unknown kind' end
    Handlers[kind] = {
        canComplete = type(handler.canComplete) == 'function' and handler.canComplete or nil,
        onAccepted = type(handler.onAccepted) == 'function' and handler.onAccepted or nil,
        onCompleted = type(handler.onCompleted) == 'function' and handler.onCompleted or nil,
        onClosed = type(handler.onClosed) == 'function' and handler.onClosed or nil,
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

function PFServices.FindOpenByRef(refType, refId)
    if not refType or refId == nil then return nil end
    local rows = listWhere('ref_type = ? AND ref_id = ? AND status IN (?, ?)', { refType, tostring(refId), OPEN, ACCEPTED }, 1)
    return rows[1]
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

local function refund(req)
    if req.escrow ~= 'held' or req.reward <= 0 then return { ok = true, skipped = true } end
    local to = payerAccount(req)
    if not to then return { ok = false, error = 'no_payer' } end
    return transfer({ from = ESCROW, to = to, amount = req.reward, key = ('pf-services:req:%d:refund'):format(req.id),
        kind = 'refund', reason = req.title, metadata = { request = req.id, kind = req.kind } })
end

-- ── views and notifications ────────────────────────────────────────

--- What a client may see of a request. Workers of the job and the requester get the position.
function PFServices.PublicView(req, viewerCid, viewerJob)
    if not req then return nil end
    local def = RequestKinds[req.kind] or {}
    local isWorker = viewerJob ~= nil and (req.job == viewerJob or (def.job ~= nil and jobMatches(def, viewerJob)))
    local isRequester = viewerCid ~= nil and req.requester == viewerCid
    local isAssignee = viewerCid ~= nil and req.assignee == viewerCid
    return {
        id = req.id, kind = req.kind, label = def.label or req.kind, icon = def.icon or '📋', job = req.job,
        status = req.status, title = req.title, details = req.details,
        coords = (isWorker or isRequester) and req.coords or nil,
        plate = (isWorker or isRequester) and req.plate or nil,
        fromName = req.from and req.from.name or nil, fromType = req.from and req.from.type or nil,
        assigneeName = req.assigneeName, reward = req.reward, paid = req.escrow == 'held' or req.escrow == 'paid',
        created = req.created, accepted = req.accepted, closed = req.closed, expires = req.expires,
        closeReason = req.closeReason, mine = isAssignee, requestedByMe = isRequester,
        verify = def.verify == true, business = def.business == true,
        meta = (isWorker or isRequester) and req.meta or nil,
    }
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

--- Creates a request. Returns { ok, id, request } or { ok = false, error }. Server-only.
function PFServices.CreateRequest(opts)
    if type(opts) ~= 'table' then return { ok = false, error = 'bad_request' } end
    local def = RequestKinds[opts.kind]
    if not def then return { ok = false, error = 'unknown_kind' } end

    local ref = type(opts.ref) == 'table' and opts.ref.type and opts.ref.id ~= nil and opts.ref or nil
    if ref then
        local existing = PFServices.FindOpenByRef(cleanText(ref.type, 32), cleanText(ref.id, 64))
        if existing then return { ok = true, id = existing.id, request = existing, existing = true } end
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
        if res.ok then
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
    local def = RequestKinds[req.kind]
    if not def or (job.name ~= req.job and not jobMatches(def, job.name)) then return nil, 'wrong_job' end
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
    local n = affected(MySQL.update.await([[UPDATE pf_service_requests SET status = 'open', assignee_cid = NULL, assignee_name = NULL, accepted_at = NULL
        WHERE id = ? AND status = 'accepted' AND assignee_cid = ?]], { req.id, req.assignee }))
    if n ~= 1 then return { ok = false, error = 'changed' } end
    req = PFServices.GetRequest(req.id)
    push(req, 'request:changed')
    TriggerEvent('pf-services:requestChanged', req, 'released')
    return { ok = true, request = req }
end

local function finish(req, status, reason, workerCid)
    local n = affected(MySQL.update.await([[UPDATE pf_service_requests SET status = ?, closed_at = NOW(), close_reason = ?
        WHERE id = ? AND status IN ('open', 'accepted')]], { status, reason, req.id }))
    if n ~= 1 then return false end
    req.status, req.closeReason = status, reason
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
        elseif not res.ok then
            MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'refund_owed' WHERE id = ?", { req.id })
            req.escrow = 'refund_owed'
        end
    end
    callHandler(req.kind, status == COMPLETED and 'onCompleted' or 'onClosed', req, reason)
    push(req, 'request:changed')
    TriggerEvent('pf-services:requestChanged', req, status)
    return true
end

--- The assignee reports the work done. Kinds that verify need the worker resource's check to pass.
function PFServices.CompleteRequest(src, id, proof)
    local Player = playerOf(src)
    if not Player then return { ok = false, error = 'no_player' } end
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.status ~= ACCEPTED or req.assignee ~= Player.PlayerData.citizenid then return { ok = false, error = 'not_yours' } end
    local def = RequestKinds[req.kind] or {}
    local handler = Handlers[req.kind]
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
    if not finish(req, COMPLETED, 'confirmed', req.assignee) then return { ok = false, error = 'changed' } end
    tellCitizen(req.assignee, ('%s confirmed the job. Payment sent.'):format(nameOf(Player) or 'The customer'), 'success')
    return { ok = true, request = PFServices.GetRequest(req.id) }
end

--- The requester cancels (refund), or a server resource closes a request (src = nil).
function PFServices.CancelRequest(src, id, reason)
    local req = PFServices.GetRequest(id)
    if not req then return { ok = false, error = 'not_found' } end
    if req.status ~= OPEN and req.status ~= ACCEPTED then return { ok = false, error = 'closed' } end
    if src ~= nil then
        local Player = playerOf(src)
        if not Player then return { ok = false, error = 'no_player' } end
        local cid = Player.PlayerData.citizenid
        local job = Player.PlayerData.job or {}
        local creatorJob = req.from and req.from.type == 'job' and req.from.id == job.name and job.onduty
        if req.requester ~= cid and not creatorJob then return { ok = false, error = 'not_yours' } end
    end
    if not finish(req, CANCELLED, cleanText(reason, 64) or 'cancelled') then return { ok = false, error = 'changed' } end
    if req.assignee then tellCitizen(req.assignee, ('Request #%d was cancelled.'):format(req.id), 'error') end
    return { ok = true }
end

--- Server resources close the request tied to something they track (EMS revived the patient, the
--- impounded car was released). status: 'completed' (pays the assignee, if any) or 'cancelled'.
function PFServices.CloseByRef(refType, refId, status, reason)
    local req = PFServices.FindOpenByRef(refType, refId)
    if not req then return { ok = false, error = 'not_found' } end
    if status == COMPLETED then
        if not finish(req, COMPLETED, cleanText(reason, 64) or 'done', req.assignee) then return { ok = false, error = 'changed' } end
    else
        if not finish(req, CANCELLED, cleanText(reason, 64) or 'cancelled') then return { ok = false, error = 'changed' } end
    end
    return { ok = true, id = req.id }
end

--- Expired requests close (and refund); completed requests whose payment failed are paid again.
function PFServices.SweepRequests()
    local expired = listWhere("status IN ('open', 'accepted') AND expires_at IS NOT NULL AND expires_at < NOW()", {}, 200)
    for _, req in ipairs(expired) do finish(req, EXPIRED, 'expired') end
    for _, req in ipairs(listWhere("status = 'completed' AND escrow_state = 'owed'", {}, 100)) do
        req.escrow = 'held'
        local res = payWorker(req, req.assignee)
        if res.ok then MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'paid' WHERE id = ?", { req.id }) end
    end
    for _, req in ipairs(listWhere("status IN ('cancelled', 'expired') AND escrow_state = 'refund_owed'", {}, 100)) do
        req.escrow = 'held'
        local res = refund(req)
        if res.ok then MySQL.update.await("UPDATE pf_service_requests SET escrow_state = 'refunded' WHERE id = ?", { req.id }) end
    end
    -- a crash between the insert and the escrow leaves 'pending': the ledger key tells whether it moved
    for _, req in ipairs(listWhere("status IN ('open', 'accepted') AND escrow_state = 'pending'", {}, 100)) do
        local res = holdEscrow(req)
        MySQL.update.await('UPDATE pf_service_requests SET escrow_state = ? WHERE id = ?', { res.ok and 'held' or 'failed', req.id })
    end
    return #expired
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

function PFServices.__resetRequests()
    RequestKinds, Handlers, lastCitizenRequest = {}, {}, {}
    for kind, def in pairs(PFCatalog.Requests) do RequestKinds[kind] = def end
end
