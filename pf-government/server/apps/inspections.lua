-- Inspections (tablet): which businesses are due, overdue or waiting for a follow-up; file an
-- inspection only while standing at the business (registry location); history. Needs 'businesses'.
-- Filing goes through RecordBusinessInspection (validated, audited, on the city timeline); a failed
-- inspection books a follow-up; an open inspection request from the business is completed by it.

local A = GovApps

local RESULTS = { compliant = true, warning = true, non_compliant = true, flagged = true }
local FAILS = { non_compliant = true, flagged = true }

local function icfg() return A.cfg().Inspections or {} end

local handlers = {}

--- Every business with its inspection state, worst first. Ages come from the database clock.
function handlers.list(src)
    if not GovSchema.Ensure() then return { ok = false, error = 'db_unavailable' } end
    local interval = (icfg().IntervalDays or 14) * 86400
    local overdue = (icfg().OverdueDays or 28) * 86400
    -- three plain reads joined here: the registry and the tables made by other modules may have
    -- different collations, so no SQL comparison across them
    local rows = MySQL.query.await([[SELECT business_id, business_name, business_type, compliance_status,
            COALESCE(business_status, 'active') AS business_status, location_x, location_y, location_z, location_address, district
        FROM pf_gov_businesses ORDER BY business_name LIMIT 300]]) or {}
    local latest = {}
    for _, i in ipairs(MySQL.query.await([[SELECT business_id, result_status, TIMESTAMPDIFF(SECOND, inspected_at, NOW()) AS age,
            UNIX_TIMESTAMP(follow_up_at) AS follow_up_at, (follow_up_at IS NOT NULL AND follow_up_at <= NOW()) AS follow_up_due
        FROM pf_gov_business_inspections ORDER BY inspected_at DESC, id DESC LIMIT 2000]]) or {}) do
        if not latest[i.business_id] then latest[i.business_id] = i end
    end
    local requested = {}
    for _, r in ipairs(MySQL.query.await("SELECT request_id, business_id FROM pf_gov_business_requests WHERE kind = 'gov.request.inspection' AND status IN ('open', 'accepted')") or {}) do
        requested[r.business_id] = tonumber(r.request_id)
    end
    for _, r in ipairs(rows) do
        local i = latest[r.business_id] or {}
        r.age, r.last_result, r.follow_up_at, r.follow_up_due, r.request_id = i.age, i.result_status, i.follow_up_at, i.follow_up_due, requested[r.business_id]
    end
    local rank = { follow_up = 1, requested = 2, overdue = 3, never = 4, due = 5, ok = 6 }
    local out = {}
    for _, r in ipairs(rows) do
        local age = tonumber(r.age)
        local state = 'ok'
        if tonumber(r.follow_up_due) == 1 then state = 'follow_up'
        elseif r.request_id then state = 'requested'
        elseif not age then state = 'never'
        elseif age > overdue then state = 'overdue'
        elseif age > interval then state = 'due' end
        out[#out + 1] = {
            id = r.business_id, name = r.business_name, type = r.business_type, compliance = r.compliance_status,
            status = r.business_status, address = r.location_address, district = r.district,
            location = A.BusinessPos(r), lastResult = r.last_result, ageDays = age and math.floor(age / 86400) or nil,
            followUpAt = tonumber(r.follow_up_at), requestId = tonumber(r.request_id), state = state,
        }
    end
    table.sort(out, function(a, b)
        if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
        return tostring(a.name) < tostring(b.name)
    end)
    return { ok = true, businesses = out, canFile = HasPermission(src, 'businesses') }
end

function handlers.history(src, p)
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local res = A.CallNui('business:inspections:list', src, { businessId = biz.business_id })
    if not res.ok then return res end
    local out = {}
    for i, r in ipairs(res.inspections or {}) do
        if i > 30 then break end
        out[#out + 1] = { id = tonumber(r.id), result = r.result_status, findings = r.findings, inspector = r.inspected_by_name,
            at = tostring(r.inspected_at or ''), followUpAt = r.follow_up_at and tostring(r.follow_up_at) or nil }
    end
    return { ok = true, business = { id = biz.business_id, name = biz.business_name }, inspections = out }
end

function handlers.waypoint(src, p)
    local biz = A.Business(p.businessId)
    local at = A.BusinessPos(biz)
    if not at then return { ok = false, error = 'no_business_location' } end
    return { ok = true, coords = at }
end

--- payload = { businessId, result, findings, followUpDays? }
function handlers.file(src, p)
    if not HasPermission(src, 'businesses') then return { ok = false, error = 'no_permission' } end
    if not GovSchema.Ensure() then return { ok = false, error = 'db_unavailable' } end
    local result = type(p.result) == 'string' and p.result or nil
    if not RESULTS[result] then return { ok = false, error = 'invalid_result' } end
    local findings = A.Text(p.findings, 1000)
    if FAILS[result] and not findings then return { ok = false, error = 'findings_required' } end
    local biz = A.Business(p.businessId)
    if not biz then return { ok = false, error = 'business_not_found' } end
    local here, why = A.AtBusiness(src, biz, true)
    if not here then return { ok = false, error = why } end

    local cid, name = A.Cid(src), GetPlayerName(src)
    local ok, inspectionId = RecordBusinessInspection(biz.business_id, result, findings or '', cid, name)
    if not ok or not inspectionId then return { ok = false, error = 'inspection_failed' } end

    local followDays = nil
    if FAILS[result] then
        followDays = math.floor(tonumber(p.followUpDays) or icfg().FollowUpDays or 3)
        followDays = math.max(1, math.min(followDays, 30))
        MySQL.update.await('UPDATE pf_gov_business_inspections SET follow_up_at = NOW() + INTERVAL ? DAY WHERE id = ?', { followDays, inspectionId })
    end

    -- the business asked for this inspection: the request is done now
    local completed = nil
    if GovRequests and GovRequests.CompleteInspection then
        completed = GovRequests.CompleteInspection(src, biz.business_id, inspectionId)
    end
    return { ok = true, inspectionId = inspectionId, followUpDays = followDays, requestCompleted = completed }
end

A.Define({
    id = 'govinspections', name = 'Inspections', icon = '🧾',
    devices = { 'tablet' },
    entry = 'html/apps/inspections.js', styles = { 'html/apps/gov.css' },
    category = 'government', order = 21,
    access = { gov = 'businesses' },
    description = 'Businesses due for inspection; file results on site; follow-ups and history',
    window = { width = 960, height = 660 },
}, handlers)

GovApps.Inspections = handlers
