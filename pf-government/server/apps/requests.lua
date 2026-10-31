-- Business requests to City Hall, worked on the government tablet and computer.
--
-- A business owner (or a boss of a job-owned business) asks from the "City Hall Requests" app for an
-- equipment slot, an inspection, a license or a delivery zone. Each ask is a pf-services request
-- (kind gov.request.*, from = the business, one open request per business + kind + subject) plus a
-- row in pf_gov_business_requests with the exact spot the business recorded and, later, the decision.
--
-- Staff work them in "Business Requests" (or the Dispatch app): accept, go there, approve or deny.
-- Approving does the real thing with the existing logic, then completes the request:
--   slot           standing at the recorded spot: premises:slot:approve creates the slot there
--   delivery_zone  standing at the recorded spot: the business's default delivery zone is set there
--   license        IssueLicense (fee billed as usual); the registry's license status becomes active
--   inspection     filed from the Inspections app at the business; filing completes the request
-- The request handler (canComplete) only lets a request complete when that decision is recorded and
-- its result (slot, zone, license, inspection) exists.

GovRequests = GovRequests or {}
local R = GovRequests
local A = GovApps

local KINDS = {
    ['gov.request.slot'] = { short = 'slot', perm = 'businesses', spot = true, label = 'Equipment slot' },
    ['gov.request.inspection'] = { short = 'inspection', perm = 'businesses', label = 'Inspection' },
    ['gov.request.license'] = { short = 'license', perm = 'licenses', label = 'License' },
    ['gov.request.delivery_zone'] = { short = 'delivery_zone', perm = 'businesses', spot = true, label = 'Delivery zone' },
}
R.Kinds = KINDS

local lastSubmit = {}   -- citizenid -> os.time()
local approving = {}    -- request id -> true while a decision is being made

local function licenseDef(licenseType)
    for _, lic in ipairs((Config.Licenses and Config.Licenses.BusinessTypes) or {}) do
        if lic.type == licenseType then return lic end
    end
    return nil
end

local function slotLabel(slotType) return (tostring(slotType):gsub('_', ' ')) end

local function rowOf(id)
    return MySQL.single.await('SELECT * FROM pf_gov_business_requests WHERE request_id = ? LIMIT 1', { tonumber(id) })
end

local function setStatus(id, status)
    if not GovSchema.Ensure() then return end
    MySQL.update.await('UPDATE pf_gov_business_requests SET status = ? WHERE request_id = ?', { status, tonumber(id) })
end

local function tellBusiness(req, row, message, kind)
    local cid = (row and row.requested_by) or req.requester
    if not cid then return end
    local P = QBCore.Functions.GetPlayerByCitizenId(cid)
    if P then A.Notify(P.PlayerData.source, message, kind) end
    A.PushCitizen(cid, 'cityhallrequests', 'changed', { id = req.id, status = req.status })
end

-- ── which businesses a player may ask for ───────────────────────────

--- Registered businesses `src` manages: owner on the registry, the restaurant's owner role, or a
--- boss of the job that owns the business.
function R.ManagedBusinesses(src)
    local P = A.Player(src)
    if not P then return {} end
    local cid = P.PlayerData.citizenid
    local job = P.PlayerData.job or {}
    local jobOwner = job.isboss == true and ('job:' .. tostring(job.name)) or '-'
    local rows = MySQL.query.await([[SELECT * FROM pf_gov_businesses WHERE owner_id = ? OR owner_id = ? OR business_id LIKE 'restaurant:%'
        ORDER BY business_name LIMIT 100]], { cid, jobOwner }) or {}
    local out = {}
    for _, biz in ipairs(rows) do
        if Premises.MayManage(src, biz, cid) then out[#out + 1] = biz end
    end
    return out
end

function R.ManagedBusiness(src, businessId)
    local biz = A.Business(businessId)
    if not biz then return nil end
    if not Premises.MayManage(src, biz, A.Cid(src)) then return nil end
    return biz
end

-- ── business side: submit ───────────────────────────────────────────

--- kind = gov.request.*; p = { businessId, slotType | licenseType, note }
function R.Submit(src, kind, p)
    local def = KINDS[kind]
    if not def then return { ok = false, error = 'bad_request' } end
    if not GovSchema.Ensure() then return { ok = false, error = 'db_unavailable' } end
    local services = A.Services()
    if not services then return { ok = false, error = 'services_offline' } end
    local cid = A.Cid(src)
    if not cid then return { ok = false, error = 'no_player' } end
    local now = os.time()
    if lastSubmit[cid] and now - lastSubmit[cid] < (A.cfg().RequestCooldownSeconds or 15) then return { ok = false, error = 'cooldown' } end
    local biz = R.ManagedBusiness(src, p.businessId)
    if not biz then return { ok = false, error = 'not_owner' } end

    local note = A.Text(p.note, A.cfg().MaxNoteLength or 300)
    local subject, pos = nil, nil
    if def.short == 'slot' then
        if type(p.slotType) ~= 'string' or not Premises.SlotTypeKnown(p.slotType) then return { ok = false, error = 'invalid_slot_type' } end
        subject = p.slotType
    elseif def.short == 'license' then
        local lic = type(p.licenseType) == 'string' and licenseDef(p.licenseType) or nil
        if not lic then return { ok = false, error = 'invalid_license_type' } end
        if MySQL.scalar.await("SELECT 1 FROM pf_gov_licenses WHERE owner_type = 'business' AND owner_id = ? AND license_type = ? AND status = 'active' LIMIT 1",
            { biz.business_id, lic.type }) then
            return { ok = false, error = 'license_active' }
        end
        subject = lic.type
    end
    if def.spot then
        -- the spot is where the owner stands, at their own business
        pos = A.Pos(src)
        if not pos then return { ok = false, error = 'no_position' } end
        local here, why = A.AtBusiness(src, biz, false)
        if not here then return { ok = false, error = why } end
    else
        pos = A.BusinessPos(biz) or A.Pos(src)
    end

    local title = ('%s: %s'):format(biz.business_name, def.label)
    if def.short == 'slot' then title = ('%s: %s slot'):format(biz.business_name, slotLabel(subject))
    elseif def.short == 'license' then title = ('%s: %s'):format(biz.business_name, licenseDef(subject).label) end

    local res = services:CreateRequest({
        kind = kind, title = title, details = note, coords = pos,
        ref = { type = kind, id = (biz.business_id .. (subject and ('#' .. subject) or '')):sub(1, 64) },
        from = { type = 'business', id = biz.business_id, name = biz.business_name },
        requester = cid,
        meta = { businessId = biz.business_id, subject = subject, spot = def.spot and pos or nil },
    })
    if type(res) ~= 'table' or not res.ok then return { ok = false, error = (type(res) == 'table' and res.error) or 'request_failed' } end
    if res.existing then return { ok = false, error = 'already_requested', id = res.id } end

    MySQL.insert.await([[INSERT INTO pf_gov_business_requests (request_id, business_id, kind, subject, note, x, y, z, heading, requested_by, requested_by_name, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open')]],
        { res.id, biz.business_id, kind, subject, note, pos and pos.x, pos and pos.y, pos and pos.z, pos and pos.heading, cid, GetPlayerName(src) })
    lastSubmit[cid] = now
    A.PushJob('govrequests', 'changed', { id = res.id })
    return { ok = true, id = res.id }
end

-- ── government side ─────────────────────────────────────────────────

local function govRequest(id)
    local services = A.Services()
    if not services then return nil, 'services_offline' end
    local req = services:GetRequest(tonumber(id))
    if type(req) ~= 'table' or not KINDS[req.kind] then return nil, 'not_found' end
    return req, nil, services
end

local function businessOf(req, row)
    local id = (row and row.business_id) or (req.meta and req.meta.businessId) or (req.from and req.from.type == 'business' and req.from.id)
    return A.Business(id)
end

function R.List(src)
    local services = A.Services()
    if not services then return { ok = false, error = 'services_offline' } end
    local cid = A.Cid(src)
    local list = services:ListForJob(Config.GovernmentJob, true) or {}
    local ids, out = {}, {}
    for _, req in ipairs(list) do if KINDS[req.kind] then ids[#ids + 1] = req.id end end
    local rows = {}
    if #ids > 0 and GovSchema.Ensure() then
        for _, r in ipairs(MySQL.query.await('SELECT * FROM pf_gov_business_requests WHERE request_id IN (' .. string.rep('?', #ids, ',') .. ')', ids) or {}) do
            rows[tonumber(r.request_id)] = r
        end
    end
    for _, req in ipairs(list) do
        local def = KINDS[req.kind]
        if def then
            local row = rows[req.id] or {}
            out[#out + 1] = {
                id = req.id, kind = def.short, label = def.label, title = req.title, details = req.details,
                status = req.status, business = req.from and req.from.name, businessId = row.business_id or (req.meta and req.meta.businessId),
                subject = row.subject, coords = req.coords, requester = row.requested_by_name,
                assignee = req.assigneeName, mine = req.assignee ~= nil and req.assignee == cid,
                created = req.created, decision = row.decision, decisionNote = row.decision_note,
                canDecide = HasPermission(src, def.perm),
            }
        end
    end
    return { ok = true, requests = out }
end

function R.Accept(src, id)
    local req, err, services = govRequest(id)
    if not req then return { ok = false, error = err } end
    if not HasPermission(src, KINDS[req.kind].perm) then return { ok = false, error = 'no_permission' } end
    local res = services:AcceptRequest(src, req.id)
    return { ok = res and res.ok == true, error = res and res.error }
end

function R.Waypoint(src, id)
    local req, err = govRequest(id)
    if not req then return { ok = false, error = err } end
    local row = rowOf(req.id)
    local at = (row and tonumber(row.x)) and { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) } or req.coords
    if not at then return { ok = false, error = 'no_location' } end
    return { ok = true, coords = at }
end

-- Takes the request for `src` if it is still open; refuses one someone else is working.
local function claim(src, req, services)
    local cid = A.Cid(src)
    if req.status == 'open' then
        local res = services:AcceptRequest(src, req.id)
        if not (res and res.ok) then return false, res and res.error or 'accept_failed' end
        return true
    end
    if req.status ~= 'accepted' then return false, 'closed' end
    if req.assignee ~= cid then return false, 'not_yours' end
    return true
end

local function recordDecision(id, decision, note, src, outcome)
    MySQL.update.await([[UPDATE pf_gov_business_requests SET decision = ?, decision_note = ?, decided_by = ?, decided_by_name = ?,
        decided_at = NOW(), outcome_ref = ? WHERE request_id = ?]], { decision, note, A.Cid(src), GetPlayerName(src), outcome and tostring(outcome) or nil, id })
end

-- The spot the business recorded (exact, from our row; the request's own coords as a fallback).
local function recordedSpot(req, row)
    if row and tonumber(row.x) then return { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) or 0.0, heading = tonumber(row.heading) or 0.0 } end
    return req.coords
end

local function doApprove(src, req, row, biz, note)
    local def = KINDS[req.kind]
    local cid, name = A.Cid(src), GetPlayerName(src)
    if def.spot then
        local spot = recordedSpot(req, row)
        if not spot then return false, 'no_location' end
        local pos = A.Pos(src)
        if not pos or A.Dist(pos, spot) > (A.cfg().RequestSpotRange or 6.0) then return false, 'too_far' end
    end
    if def.short == 'slot' then
        local subject = row and row.subject or (req.meta and req.meta.subject)
        local res = A.CallNui('premises:slot:approve', src, { businessId = biz.business_id, slotType = subject, label = A.Text(note, 64) })
        if not res.ok then return false, res.error or 'slot_failed' end
        return true, res.data and res.data.slotId
    elseif def.short == 'delivery_zone' then
        return DeliveryZones.Set('business', biz.business_id, A.Pos(src), { requestId = req.id, cid = cid, name = name, label = A.Text(note, 64) })
    elseif def.short == 'license' then
        local lic = licenseDef(row and row.subject or (req.meta and req.meta.subject))
        if not lic then return false, 'invalid_license_type' end
        local ok, msg, licenseId = IssueLicense(lic.type, 'business', biz.business_id, biz.business_name, cid, name,
            GetLicenseDuration(lic.type, 'business'), note)
        if not ok then return false, msg == 'License already exists and is active' and 'license_active' or 'license_failed' end
        MySQL.update.await("UPDATE pf_gov_businesses SET license_status = 'active', updated_at = NOW() WHERE business_id = ?", { biz.business_id })
        return true, licenseId
    end
    return false, 'bad_request'
end

--- Approves a request (the work is done here, then the request is completed). An approval that
--- already happened (a retry after a failed completion) is not done twice.
function R.Approve(src, id, note)
    local req, err, services = govRequest(id)
    if not req then return { ok = false, error = err } end
    local def = KINDS[req.kind]
    if not HasPermission(src, def.perm) then return { ok = false, error = 'no_permission' } end
    if def.short == 'inspection' then
        return { ok = false, error = 'file_inspection', businessId = req.meta and req.meta.businessId or (req.from and req.from.id) }
    end
    if not GovSchema.Ensure() then return { ok = false, error = 'db_unavailable' } end
    note = A.Text(note, A.cfg().MaxNoteLength or 300)
    if approving[req.id] then return { ok = false, error = 'busy' } end
    approving[req.id] = true
    local ok, res = pcall(function()
        local row = rowOf(req.id)
        local biz = businessOf(req, row)
        if not biz then return { ok = false, error = 'business_not_found' } end
        if row and row.decision == 'denied' then return { ok = false, error = 'closed' } end
        local claimed, why = claim(src, req, services)
        if not claimed then return { ok = false, error = why } end
        local outcome = row and row.decision == 'approved' and row.outcome_ref or nil
        if not outcome then
            local done, result = doApprove(src, req, row, biz, note)
            if not done then return { ok = false, error = result } end
            outcome = result
            if row then recordDecision(req.id, 'approved', note, src, outcome) end
        end
        local fin = services:CompleteRequest(src, req.id, { outcome = outcome })
        if not (fin and fin.ok) then return { ok = false, error = fin and fin.error or 'complete_failed', approved = true } end
        tellBusiness(req, row, ('City Hall approved: %s'):format(req.title), 'success')
        A.PushJob('govrequests', 'changed', { id = req.id })
        return { ok = true, outcome = outcome }
    end)
    approving[req.id] = nil
    if not ok then
        print('^1[PF-GOVERNMENT]^7 request approval failed: ' .. tostring(res))
        return { ok = false, error = 'server_error' }
    end
    return res
end

function R.Deny(src, id, note)
    local req, err, services = govRequest(id)
    if not req then return { ok = false, error = err } end
    if not HasPermission(src, KINDS[req.kind].perm) then return { ok = false, error = 'no_permission' } end
    note = A.Text(note, A.cfg().MaxNoteLength or 300)
    if not note then return { ok = false, error = 'note_required' } end
    if req.status ~= 'open' and req.status ~= 'accepted' then return { ok = false, error = 'closed' } end
    if req.status == 'accepted' and req.assignee ~= A.Cid(src) then return { ok = false, error = 'not_yours' } end
    if not GovSchema.Ensure() then return { ok = false, error = 'db_unavailable' } end
    local row = rowOf(req.id)
    if row then recordDecision(req.id, 'denied', note, src, nil) end
    local res = services:CancelRequest(nil, req.id, 'denied')
    if not (res and res.ok) then return { ok = false, error = res and res.error or 'cancel_failed' } end
    tellBusiness(req, row, ('City Hall denied: %s (%s)'):format(req.title, note), 'error')
    A.PushJob('govrequests', 'changed', { id = req.id })
    return { ok = true }
end

--- An inspection was filed at a business: its open inspection request (if any) is done.
function R.CompleteInspection(src, businessId, inspectionId)
    local services = A.Services()
    if not services or not GovSchema.Ensure() then return nil end
    local req = services:FindOpenByRef('gov.request.inspection', businessId)
    if type(req) ~= 'table' then return nil end
    local row = rowOf(req.id)
    if row then recordDecision(req.id, 'approved', 'Inspection filed', src, inspectionId) end
    if req.status == 'open' then services:AcceptRequest(src, req.id) req = services:GetRequest(req.id) or req end
    local res
    if req.status == 'accepted' and req.assignee == A.Cid(src) then
        res = services:CompleteRequest(src, req.id, { outcome = inspectionId })
    else
        -- someone else had taken it, or it could not be taken: the inspection is the proof
        res = services:CloseByRef('gov.request.inspection', businessId, 'completed', 'inspected')
    end
    if res and res.ok then tellBusiness(req, row, 'City Hall inspected your business.', 'success') end
    return res and res.ok == true
end

-- ── pf-services request handlers: completion needs the recorded approval ──

local function approvalExists(req)
    if not GovSchema.Ensure() then return false, 'db_unavailable' end
    local row = rowOf(req.id)
    if not row or row.decision ~= 'approved' or not row.outcome_ref then return false, 'not_approved' end
    local ref, biz = tonumber(row.outcome_ref), row.business_id
    local short = KINDS[req.kind] and KINDS[req.kind].short
    local found
    if short == 'slot' then
        found = MySQL.scalar.await('SELECT 1 FROM pf_gov_premises_slots WHERE id = ? AND business_id = ? AND active = 1', { ref, biz })
    elseif short == 'delivery_zone' then
        found = MySQL.scalar.await("SELECT 1 FROM pf_gov_delivery_zones WHERE id = ? AND scope = 'business' AND ref = ?", { ref, biz })
    elseif short == 'license' then
        found = MySQL.scalar.await("SELECT 1 FROM pf_gov_licenses WHERE id = ? AND owner_type = 'business' AND owner_id = ? AND status = 'active'", { ref, biz })
    elseif short == 'inspection' then
        found = MySQL.scalar.await('SELECT 1 FROM pf_gov_business_inspections WHERE id = ? AND business_id = ?', { ref, biz })
    end
    if not found then return false, 'not_approved' end
    return true
end
R.ApprovalExists = approvalExists

function R.RegisterHandlers()
    local services = A.Services()
    if not services then return false end
    local handler = {
        canComplete = function(req) return approvalExists(req) end,
        onAccepted = function(req)
            setStatus(req.id, 'accepted')
            tellBusiness(req, rowOf(req.id), ('%s is handling your request: %s'):format(req.assigneeName or 'City Hall', req.title), 'primary')
        end,
        onCompleted = function(req) setStatus(req.id, 'completed') end,
        onClosed = function(req)
            setStatus(req.id, req.status or 'cancelled')
            A.PushJob('govrequests', 'changed', { id = req.id })
        end,
    }
    local all = true
    for kind in pairs(KINDS) do
        local ok, res = pcall(function() return services:RegisterRequestHandler(kind, handler) end)
        all = all and ok and res ~= false
    end
    return all
end

-- ── the business side app: City Hall Requests ──────────────────────

local function myRequests(src, businesses)
    local ids = {}
    for _, b in ipairs(businesses) do ids[#ids + 1] = b.business_id end
    if #ids == 0 or not GovSchema.Ensure() then return {} end
    local rows = MySQL.query.await('SELECT *, UNIX_TIMESTAMP(created_at) AS created, UNIX_TIMESTAMP(decided_at) AS decided FROM pf_gov_business_requests WHERE business_id IN ('
        .. string.rep('?', #ids, ',') .. ') ORDER BY created_at DESC, request_id DESC LIMIT 60', ids) or {}
    local services = A.Services()
    local out = {}
    for _, r in ipairs(rows) do
        local status = r.status
        if services and (status == 'open' or status == 'accepted') then
            -- refresh from the request itself (it may have expired)
            local req = services:GetRequest(tonumber(r.request_id))
            if type(req) == 'table' and req.status and req.status ~= status then
                status = req.status
                setStatus(r.request_id, status)
            end
        end
        local def = KINDS[r.kind] or {}
        out[#out + 1] = {
            id = tonumber(r.request_id), kind = def.short, label = def.label, businessId = r.business_id, subject = r.subject,
            note = r.note, status = status, decision = r.decision, decisionNote = r.decision_note, decidedBy = r.decided_by_name,
            requestedBy = r.requested_by_name, created = tonumber(r.created), decided = tonumber(r.decided),
        }
    end
    return out
end

local business = {}

function business.__access(src) return #R.ManagedBusinesses(src) > 0 end

function business.overview(src)
    local list = R.ManagedBusinesses(src)
    local out = {}
    for _, b in ipairs(list) do
        out[#out + 1] = { id = b.business_id, name = b.business_name, type = b.business_type, status = b.business_status or 'active',
            licenseStatus = b.license_status, compliance = b.compliance_status, hasLocation = A.BusinessPos(b) ~= nil }
    end
    local licenses = {}
    for _, lic in ipairs((Config.Licenses and Config.Licenses.BusinessTypes) or {}) do
        licenses[#licenses + 1] = { type = lic.type, label = lic.label, fee = lic.fee }
    end
    return { ok = true, businesses = out, slotTypes = (Config.Premises and Config.Premises.SlotTypes) or {}, licenseTypes = licenses,
        requests = myRequests(src, list) }
end

function business.requestSlot(src, p) return R.Submit(src, 'gov.request.slot', p) end
function business.requestInspection(src, p) return R.Submit(src, 'gov.request.inspection', p) end
function business.requestLicense(src, p) return R.Submit(src, 'gov.request.license', p) end
function business.requestDeliveryZone(src, p) return R.Submit(src, 'gov.request.delivery_zone', p) end

function business.cancel(src, p)
    local row = GovSchema.Ensure() and rowOf(p.id) or nil
    if not row or not R.ManagedBusiness(src, row.business_id) then return { ok = false, error = 'not_found' } end
    local services = A.Services()
    if not services then return { ok = false, error = 'services_offline' } end
    -- ownership was checked above, so any manager of the business may withdraw it
    local res = services:CancelRequest(nil, tonumber(row.request_id), 'cancelled_by_business')
    if not (res and res.ok) then return { ok = false, error = res and res.error or 'cancel_failed' } end
    setStatus(row.request_id, 'cancelled')
    A.PushJob('govrequests', 'changed', { id = tonumber(row.request_id) })
    return { ok = true }
end

local gov = {
    list = function(src) return R.List(src) end,
    accept = function(src, p) return R.Accept(src, p.id) end,
    waypoint = function(src, p) return R.Waypoint(src, p.id) end,
    approve = function(src, p) return R.Approve(src, p.id, p.note) end,
    deny = function(src, p) return R.Deny(src, p.id, p.note) end,
}

A.Define({
    id = 'govrequests', name = 'Business Requests', icon = '📥',
    devices = { 'tablet', 'computer' },
    entry = 'html/apps/requests.js', styles = { 'html/apps/gov.css' },
    category = 'government', order = 22,
    access = { gov = { 'businesses', 'licenses' } },
    description = 'Slot, inspection, license and delivery zone requests from businesses',
    window = { width = 980, height = 660 },
}, gov)

A.Define({
    id = 'cityhallrequests', name = 'City Hall Requests', icon = '🏛️',
    devices = { 'tablet', 'computer' },
    entry = 'html/apps/cityhall.js', styles = { 'html/apps/gov.css' },
    category = 'business', order = 30,
    access = { handler = true },
    description = 'Ask City Hall for equipment slots, inspections, licenses and a delivery zone',
    window = { width = 900, height = 640 },
}, business)

R.GovHandlers, R.BusinessHandlers = gov, business

function R.__reset() lastSubmit, approving = {}, {} end
