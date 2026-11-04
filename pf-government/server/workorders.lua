-- =====================================================
-- MUNICIPAL WORK ORDERS
-- =====================================================
-- Maintenance jobs made from the real infrastructure state (server/infrastructure.lua): a district
-- whose potholes, lights, signals or backlog cross Config.WorkOrders.Thresholds gets an order at one
-- of its sites, and some city events (pf-services) leave litter or graffiti where they happened.
--
-- A worker claims ONE unit (ClaimWorkOrder), works it inside the site radius out of a vehicle for
-- the kind's minimum time (server positions, sampled every SampleSeconds), and the caller reports it
-- (ReportWorkUnit). Each unit applies its share of the order's effect to the district and saves it
-- (ApplyDistrictWorkEffect); the simulation drifts from the saved value, so the repair stays.
-- Community service units (pf-justice, claimant kind 'cs') pay nothing; staff and listed jobs are
-- paid per unit from the department's society account once per worker and order, through the
-- ledger with numbered attempt keys (pf-government:wo:<id>:pay:<cid>:<n>).
--
-- Order:  open -> in_progress (any claim) -> completed (all units); open/in_progress -> expired | cancelled
-- Claim:  claimed -> done | released | expired (TTL Config.WorkOrders.ClaimSeconds)
--
-- Exports (architecture 4.12): CreateWorkOrder, ListWorkOrders, GetWorkOrder, ClaimWorkOrder,
-- ReportWorkUnit, ReleaseWorkClaim, CancelWorkOrder. Server-only event on completion:
-- pf-government:server:workOrderCompleted(order).

WorkOrders = WorkOrders or {}
local W = WorkOrders

local KINDS = {
    litter = true, graffiti = true, park = true, landscaping = true, public_building = true,
    pothole = true, streetlight = true, sign = true,
}
-- the sign of an improvement for each district field an order may change
local FIELD_DIR = {
    pothole_density = -1, maintenance_backlog = -1,
    street_light_health = 1, traffic_light_health = 1, road_condition = 1,
}
local CLAIMANTS = { cs = true, staff = true, job = true }
local STATUSES = { open = true, in_progress = true, completed = true, expired = true, cancelled = true }

-- claims being worked, by claim id: { cid, orderId, kind, x, y, z, r, since } (since = first
-- server sample on site in the current stretch; nil while off site). Bounded by the open claims.
W.active = W.active or {}
local active = W.active

local function cfg() return Config.WorkOrders or {} end
local function now() return os.time() end

local function fail(code, message, extra)
    local r = { ok = false, error = code, message = message }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end

local function finite(v, maxAbs)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge or math.abs(n) > (maxAbs or 1e6) then return nil end
    return n
end

local function int(v, min, max)
    local n = finite(v, 1e15)
    if not n then return nil end
    n = math.tointeger(n)
    if not n or n < min or n > max then return nil end
    return n
end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end
local function num(v) return tonumber(v) or 0 end

local function validKey(k)
    return type(k) == 'string' and #k >= 1 and #k <= 128 and k:match('^[%w%-_:%.]+$') ~= nil
end

local function validCid(c)
    return type(c) == 'string' and #c >= 1 and #c <= 64 and c:match('^[%w]+$') ~= nil
end

local function cleanText(v, max)
    if GovCleanText then return GovCleanText(v, max) end
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

local function coordsOf(c)
    if type(c) ~= 'table' and type(c) ~= 'vector3' and type(c) ~= 'vector4' then return nil end
    local x, y, z = finite(c.x, 1e5), finite(c.y, 1e5), finite(c.z or 0, 1e4)
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z }
end

local function districtsCfg() return (Config.Infrastructure and Config.Infrastructure.Districts) or {} end
local function districtLabel(d) local c = districtsCfg()[d] return (c and c.label) or d end
local function societyOf(dept)
    local map = (Config.Budgets and Config.Budgets.LinkedSocietyAccounts) or {}
    return type(dept) == 'string' and map[dept] or nil
end
local function minSeconds(kind) return math.max(0, num((cfg().MinUnitSeconds or {})[kind] or 60)) end

local function dbReady() return GovSchema and GovSchema.Ensure and GovSchema.Ensure() end

local function audit(action, actorId, targetId, details)
    if not LogAudit then return end
    pcall(LogAudit, action, actorId or 'system', nil, 'work_order', targetId, details)
end

-- ── caller allowlists (architecture 3.4) ────────────────────────────────

local warned = {}
local function callerAllowed(name)
    local inv = GetInvokingResource()
    if inv == nil or inv == GetCurrentResourceName() then return true end
    local list = (cfg().Callers or {})[name]
    if list == '*' then return true end
    if type(list) == 'table' and list[inv] == true then return true end
    local t, k = now(), name .. ':' .. inv
    if not warned[k] or t - warned[k] >= 60 then
        warned[k] = t
        print(('^3[PF-GOVERNMENT]^7 %s refused for %s (not in Config.WorkOrders.Callers)'):format(name, inv))
    end
    return false
end

local function notAllowed() return fail('not_allowed', 'This resource may not use that work order export.') end

-- ── locks (taken before the first database wait) ─────────────────────────

local locks = {}
local function withLocks(names, fn)
    for _, n in ipairs(names) do
        if locks[n] then return fail('busy', 'This work order is being updated. Try again.') end
    end
    for _, n in ipairs(names) do locks[n] = true end
    local ok, res = pcall(fn)
    for _, n in ipairs(names) do locks[n] = nil end
    if not ok then
        print('^1[PF-GOVERNMENT]^7 work order action failed: ' .. tostring(res))
        return fail('db_unavailable', 'City records are unavailable right now. Nothing was changed.')
    end
    return res
end

-- ── rows ─────────────────────────────────────────────────────────────────

local function orderRow(id)
    return MySQL.single.await('SELECT * FROM pf_gov_work_orders WHERE id = ? LIMIT 1', { id })
end

local function claimRow(id)
    return MySQL.single.await('SELECT * FROM pf_gov_work_claims WHERE id = ? LIMIT 1', { id })
end

local function activeClaimCounts(ids, t)
    local out = {}
    if #ids == 0 then return out end
    local marks = {}
    local params = { t }
    for i, id in ipairs(ids) do marks[i] = '?' params[#params + 1] = id end
    local rows = MySQL.query.await(("SELECT work_order_id, COUNT(*) AS n FROM pf_gov_work_claims WHERE state = 'claimed' AND expires_at > ? AND work_order_id IN (%s) GROUP BY work_order_id")
        :format(table.concat(marks, ',')), params) or {}
    for _, r in ipairs(rows) do out[tonumber(r.work_order_id)] = num(r.n) end
    return out
end

--- The public view of an order (no citizen ids): what a list, an app or a listener may show.
local function publicOrder(row, activeCount)
    local units, done = num(row.units), num(row.units_done)
    local kind = row.kind
    return {
        id = tonumber(row.id),
        kind = kind,
        label = (cfg().KindLabels or {})[kind] or kind,
        district = row.district,
        districtLabel = districtLabel(row.district),
        site = { x = num(row.x), y = num(row.y), z = num(row.z), r = num(row.radius), label = row.site_label },
        units = units,
        unitsDone = done,
        unitsOpen = math.max(0, units - done - (activeCount or 0)),
        effect = { field = row.effect_field, delta = num(row.effect_delta) },
        csEligible = num(row.cs_eligible) == 1,
        payable = num(row.pay_amount) > 0 and { amount = num(row.pay_amount), from = row.pay_dept } or nil,
        source = { type = row.source_type, id = row.source_id },
        status = row.status,
        minSeconds = minSeconds(kind),
        createdAt = num(row.created_at),
        expiresAt = num(row.expires_at),
        completedAt = row.completed_at and num(row.completed_at) or nil,
    }
end
W.PublicOrder = publicOrder

-- ── create ───────────────────────────────────────────────────────────────

--- Validates a work order spec; returns the clean order or nil and the name of the bad field.
local function normalizeSpec(spec)
    if type(spec) ~= 'table' then return nil, 'spec' end
    local c = cfg()
    local kind = spec.kind
    if type(kind) ~= 'string' or not KINDS[kind] then return nil, 'kind' end
    local district = spec.district
    if type(district) ~= 'string' or not districtsCfg()[district] then return nil, 'district' end
    local site = type(spec.site) == 'table' and spec.site or nil
    local pos = coordsOf(site)
    local r = site and finite(site.r or spec.radius, 1e4)
    if not pos or not r or r < 2 or r > num(c.MaxRadius or 60) then return nil, 'site' end
    local units = int(spec.units, 1, math.min(20, num(c.MaxUnits or 20)))
    if not units then return nil, 'units' end
    local eff = spec.effect
    if type(eff) ~= 'table' or type(eff.field) ~= 'string' or not FIELD_DIR[eff.field] then return nil, 'effect' end
    local delta = finite(eff.delta, 1e7)
    if not delta or delta == 0 or delta * FIELD_DIR[eff.field] < 0 then return nil, 'effect' end
    local cap = (c.MaxEffect or {})[eff.field]
    if cap and math.abs(delta) > cap then return nil, 'effect' end
    local sourceType, sourceId = 'manual', nil
    if spec.source ~= nil then
        local s = spec.source
        if type(s) ~= 'table' or type(s.type) ~= 'string' or #s.type > 16 or not s.type:match('^[%w_%-%.]+$') then return nil, 'source' end
        sourceType = s.type
        if s.id ~= nil then
            if type(s.id) ~= 'string' and type(s.id) ~= 'number' then return nil, 'source' end
            sourceId = cleanText(tostring(s.id), 64)
        end
    end
    local payAmount, payDept = 0, nil
    if spec.payable ~= nil then
        local p = spec.payable
        if type(p) ~= 'table' then return nil, 'payable' end
        payAmount = int(p.amount, 0, num(c.MaxPayPerUnit or 2000))
        if not payAmount then return nil, 'payable' end
        if payAmount > 0 then
            if not societyOf(p.from) then return nil, 'payable' end
            payDept = p.from
        end
    end
    local t = now()
    local expiresAt = t + num(c.DefaultLifetimeHours or 48) * 3600
    if spec.expiresAt ~= nil then
        expiresAt = int(spec.expiresAt, t + 60, t + num(c.MaxLifetimeHours or 168) * 3600)
        if not expiresAt then return nil, 'expiresAt' end
    end
    if spec.csEligible ~= nil and type(spec.csEligible) ~= 'boolean' then return nil, 'csEligible' end
    return {
        kind = kind, district = district, siteLabel = cleanText(site.label, 64),
        x = round2(pos.x), y = round2(pos.y), z = round2(pos.z), r = round2(r),
        units = units, field = eff.field, delta = round2(delta),
        csEligible = spec.csEligible ~= false, payAmount = payAmount, payDept = payDept,
        sourceType = sourceType, sourceId = sourceId, expiresAt = expiresAt, createdAt = t,
    }
end

local function sameOrder(row, o)
    return row.kind == o.kind and row.district == o.district and num(row.units) == o.units
        and row.effect_field == o.field and math.abs(num(row.effect_delta) - o.delta) < 0.005
end

local function openInDistrict(district)
    return num(MySQL.scalar.await("SELECT COUNT(*) FROM pf_gov_work_orders WHERE district = ? AND status IN ('open', 'in_progress')", { district }))
end

local function insertOrder(o, key)
    return MySQL.insert.await([[INSERT IGNORE INTO pf_gov_work_orders
        (kind, district, site_label, x, y, z, radius, units, units_done, effect_field, effect_delta, cs_eligible,
         pay_amount, pay_dept, source_type, source_id, status, created_at, expires_at, idem_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)]], {
        o.kind, o.district, o.siteLabel, o.x, o.y, o.z, o.r, o.units, o.field, o.delta, o.csEligible and 1 or 0,
        o.payAmount, o.payDept, o.sourceType, o.sourceId, o.createdAt, o.expiresAt, key,
    })
end

local function createLocked(o, key, actorId)
    if not dbReady() then return fail('db_unavailable', 'City records are unavailable right now.') end
    if key then
        local ex = MySQL.single.await('SELECT * FROM pf_gov_work_orders WHERE idem_key = ? LIMIT 1', { key })
        if ex then
            if sameOrder(ex, o) then return { ok = true, duplicate = true, workOrderId = tonumber(ex.id) } end
            return fail('key_reused', 'That key belongs to a different work order.')
        end
    end
    if openInDistrict(o.district) >= num(cfg().MaxOpenPerDistrict or 3) then
        return fail('conflict', 'This district already has its maximum of open work orders.')
    end
    local id = tonumber(insertOrder(o, key)) or 0
    if id < 1 then
        if key then
            local ex = MySQL.single.await('SELECT * FROM pf_gov_work_orders WHERE idem_key = ? LIMIT 1', { key })
            if ex and sameOrder(ex, o) then return { ok = true, duplicate = true, workOrderId = tonumber(ex.id) } end
        end
        return fail('db_unavailable', 'The work order could not be saved.')
    end
    audit('work_order_create', actorId, id, { kind = o.kind, district = o.district, units = o.units, source = o.sourceType, sourceId = o.sourceId })
    return { ok = true, workOrderId = id }
end

--- Creates a work order (no allowlist check: GOV itself and the export wrapper call it).
function W.Create(spec, opts)
    opts = type(opts) == 'table' and opts or {}
    local o, bad = normalizeSpec(spec)
    if not o then return fail('bad_args', 'Invalid work order: ' .. tostring(bad)) end
    local key = opts.key
    if key ~= nil and not validKey(key) then return fail('bad_args', 'Invalid key') end
    local actorId = type(opts.actor) == 'table' and opts.actor.src and GetPlayerIdentifier and GetPlayerIdentifier(opts.actor.src) or nil
    return withLocks({ 'district:' .. o.district }, function() return createLocked(o, key, actorId) end)
end

-- ── read ─────────────────────────────────────────────────────────────────

function W.Get(id)
    id = int(id, 1, 2147483647)
    if not id then return fail('bad_args', 'Invalid work order id') end
    if not dbReady() then return fail('db_unavailable', 'City records are unavailable right now.') end
    local row = orderRow(id)
    if not row then return fail('not_found', 'No such work order.') end
    local counts = activeClaimCounts({ id }, now())
    return { ok = true, order = publicOrder(row, counts[id]) }
end

function W.List(filter)
    filter = type(filter) == 'table' and filter or {}
    local where, params = {}, {}
    local status = filter.status
    if status == nil or status == 'open' then
        where[#where + 1] = "status IN ('open', 'in_progress')"
    elseif status ~= 'any' then
        if type(status) ~= 'string' or not STATUSES[status] then return fail('bad_args', 'Invalid status') end
        where[#where + 1] = 'status = ?' params[#params + 1] = status
    end
    if filter.district ~= nil then
        if type(filter.district) ~= 'string' or not districtsCfg()[filter.district] then return fail('bad_args', 'Invalid district') end
        where[#where + 1] = 'district = ?' params[#params + 1] = filter.district
    end
    if filter.kinds ~= nil then
        if type(filter.kinds) ~= 'table' or #filter.kinds < 1 or #filter.kinds > 8 then return fail('bad_args', 'Invalid kinds') end
        local marks = {}
        for i, k in ipairs(filter.kinds) do
            if type(k) ~= 'string' or not KINDS[k] then return fail('bad_args', 'Invalid kinds') end
            marks[i] = '?' params[#params + 1] = k
        end
        where[#where + 1] = ('kind IN (%s)'):format(table.concat(marks, ','))
    end
    if filter.csEligible ~= nil then
        if type(filter.csEligible) ~= 'boolean' then return fail('bad_args', 'Invalid csEligible') end
        where[#where + 1] = 'cs_eligible = ?' params[#params + 1] = filter.csEligible and 1 or 0
    end
    local near
    if filter.near ~= nil then
        near = coordsOf(filter.near)
        local r = type(filter.near) == 'table' and finite(filter.near.r, 1e5) or nil
        if not near or not r or r <= 0 or r > 2000 then return fail('bad_args', 'Invalid near') end
        near.r = r
        -- a box around the point (plus the largest site radius) narrows the rows; the exact
        -- distance is checked below
        local pad = r + num(cfg().MaxRadius or 60)
        where[#where + 1] = 'x BETWEEN ? AND ? AND y BETWEEN ? AND ?'
        params[#params + 1] = near.x - pad params[#params + 1] = near.x + pad
        params[#params + 1] = near.y - pad params[#params + 1] = near.y + pad
    end
    if filter.after ~= nil then
        local after = int(filter.after, 1, 2147483647)
        if not after then return fail('bad_args', 'Invalid cursor') end
        where[#where + 1] = 'id < ?' params[#params + 1] = after
    end
    local limit = filter.limit == nil and 20 or int(filter.limit, 1, 50)
    if not limit then return fail('bad_args', 'Invalid limit') end
    params[#params + 1] = limit
    if not dbReady() then return fail('db_unavailable', 'City records are unavailable right now.') end
    local sql = 'SELECT * FROM pf_gov_work_orders'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    local rows = MySQL.query.await(sql .. ' ORDER BY id DESC LIMIT ?', params) or {}
    local ids = {}
    for _, r in ipairs(rows) do ids[#ids + 1] = tonumber(r.id) end
    local counts = activeClaimCounts(ids, now())
    local list = {}
    for _, r in ipairs(rows) do
        local o = publicOrder(r, counts[tonumber(r.id)])
        if near then
            local dx, dy = o.site.x - near.x, o.site.y - near.y
            o.distance = round2(math.sqrt(dx * dx + dy * dy))
            if o.distance <= near.r + o.site.r then list[#list + 1] = o end
        else
            list[#list + 1] = o
        end
    end
    if near then table.sort(list, function(a, b) return a.distance < b.distance end) end
    local last = rows[#rows]
    return { ok = true, list = list, next = (#rows == limit and last) and tonumber(last.id) or nil }
end

-- ── presence (server positions) ──────────────────────────────────────────

local function playerOf(src)
    return QBCore and QBCore.Functions.GetPlayer(src) or nil
end

--- Whether src stands inside the site (2D within radius + tolerance, height within 15 m) on foot.
--- Returns ok, reason ('offline' | 'vehicle' | 'too_far'), distance.
local function onSite(src, site)
    if not src or not playerOf(src) then return false, 'offline' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'offline' end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false, 'vehicle' end
    local p = GetEntityCoords(ped)
    local dx, dy, dz = p.x - site.x, p.y - site.y, p.z - site.z
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > site.r + num(cfg().SiteTolerance or 2.0) or math.abs(dz) > 15.0 then return false, 'too_far', dist end
    return true, nil, dist
end
W.OnSite = onSite

local function sourceOfCid(cid)
    local P = QBCore and QBCore.Functions.GetPlayerByCitizenId(cid)
    return P and P.PlayerData and P.PlayerData.source or nil
end

--- One sample of a claim: the on-site stretch starts at the first sample inside the site and
--- breaks at any sample outside it (or offline, or in a vehicle).
local function sample(entry, src, t)
    local ok, why = onSite(src, entry)
    if ok then entry.since = entry.since or t else entry.since = nil end
    entry.seen = t
    return ok, why
end

--- The sampler tick (every SampleSeconds): every open claim of an online claimant.
function W.SampleClaims(t)
    t = t or now()
    local n = 0
    for _, entry in pairs(active) do
        if entry.expiresAt and entry.expiresAt <= t then
            entry.since = nil
        else
            sample(entry, sourceOfCid(entry.cid), t)
            n = n + 1
        end
    end
    return n
end

local function track(claimId, cid, order, expiresAt)
    active[claimId] = {
        cid = cid, orderId = tonumber(order.id), kind = order.kind, expiresAt = expiresAt,
        x = num(order.x), y = num(order.y), z = num(order.z), r = num(order.radius),
    }
    return active[claimId]
end

-- ── claims ───────────────────────────────────────────────────────────────

--- Whether a staff or job claimant may work this order: online, on duty, the right job.
local function workerAllowed(kind, cid, order)
    local src = sourceOfCid(cid)
    local P = src and playerOf(src)
    if not P then return false, fail('offline', 'The worker must be in the city to claim work.') end
    local job = P.PlayerData.job or {}
    if job.onduty == false then return false, fail('not_on_duty', 'Go on duty first.') end
    if kind == 'staff' then
        if job.name ~= Config.GovernmentJob or not HasPermission(src, cfg().StaffPermission or 'utilities') then
            return false, fail('no_permission', 'Only city maintenance staff can claim this work.')
        end
        return true
    end
    local kinds = (cfg().ClaimJobs or {})[job.name]
    if type(kinds) == 'table' then
        for _, k in ipairs(kinds) do if k == order.kind then return true end end
    end
    return false, fail('no_permission', 'Your job cannot take this kind of work.')
end

local function reopenIfIdle(orderId, t)
    MySQL.update.await([[UPDATE pf_gov_work_orders SET status = 'open'
        WHERE id = ? AND status = 'in_progress' AND units_done = 0
          AND NOT EXISTS (SELECT 1 FROM pf_gov_work_claims WHERE work_order_id = ? AND state = 'claimed' AND expires_at > ?)]],
        { orderId, orderId, t })
end

local function claimLocked(id, kind, cid, ref, t)
    if not dbReady() then return fail('db_unavailable', 'City records are unavailable right now.') end
    local order = orderRow(id)
    if not order then return fail('not_found', 'No such work order.') end
    if order.status ~= 'open' and order.status ~= 'in_progress' then
        return fail('invalid_state', 'This work order is ' .. tostring(order.status) .. '.')
    end
    if num(order.expires_at) <= t then return fail('invalid_state', 'This work order has expired.') end
    if kind == 'cs' and num(order.cs_eligible) ~= 1 then
        return fail('invalid_state', 'This work order is not open to community service.')
    end
    if kind ~= 'cs' then
        local okW, err = workerAllowed(kind, cid, order)
        if not okW then return err end
    end
    local mine = MySQL.query.await("SELECT id, work_order_id, expires_at FROM pf_gov_work_claims WHERE citizenid = ? AND state = 'claimed' AND expires_at > ?", { cid, t }) or {}
    for _, c in ipairs(mine) do
        if num(c.work_order_id) == id then
            -- a retried claim (lost answer): the same unit, not a second one
            return { ok = true, duplicate = true, claimId = tonumber(c.id), expiresAt = num(c.expires_at), workOrderId = id,
                site = { x = num(order.x), y = num(order.y), z = num(order.z), r = num(order.radius) }, minSeconds = minSeconds(order.kind) }
        end
    end
    if #mine >= math.max(1, num(cfg().MaxActiveClaimsPerCitizen or 1)) then
        return fail('conflict', 'Finish or release your current work unit first.')
    end
    local taken = activeClaimCounts({ id }, t)[id] or 0
    if num(order.units_done) + taken >= num(order.units) then
        return fail('conflict', 'Every unit of this work order is taken.')
    end
    local expiresAt = math.min(t + math.max(60, num(cfg().ClaimSeconds or 600)), num(order.expires_at))
    local claimId = tonumber(MySQL.insert.await([[INSERT INTO pf_gov_work_claims (work_order_id, claimant_kind, citizenid, ref, state, claimed_at, expires_at)
        VALUES (?, ?, ?, ?, 'claimed', ?, ?)]], { id, kind, cid, ref, t, expiresAt })) or 0
    if claimId < 1 then return fail('db_unavailable', 'The claim could not be saved.') end
    MySQL.update.await("UPDATE pf_gov_work_orders SET status = 'in_progress' WHERE id = ? AND status = 'open'", { id })
    track(claimId, cid, order, expiresAt)
    return { ok = true, claimId = claimId, expiresAt = expiresAt, workOrderId = id,
        site = { x = num(order.x), y = num(order.y), z = num(order.z), r = num(order.radius) }, minSeconds = minSeconds(order.kind) }
end

--- Claims one unit of an order. claimant = { kind = 'cs' | 'staff' | 'job', cid, ref? }.
function W.Claim(id, claimant, opts)
    id = int(id, 1, 2147483647)
    if not id or type(claimant) ~= 'table' then return fail('bad_args', 'Invalid claim') end
    local kind, cid = claimant.kind, claimant.cid
    if type(kind) ~= 'string' or not CLAIMANTS[kind] or not validCid(cid) then return fail('bad_args', 'Invalid claimant') end
    local ref = nil
    if claimant.ref ~= nil then
        if type(claimant.ref) ~= 'string' and type(claimant.ref) ~= 'number' then return fail('bad_args', 'Invalid ref') end
        ref = cleanText(tostring(claimant.ref), 64)
    end
    if kind == 'cs' then
        -- community service claims come from the order owner only (the claimant's order is its truth)
        local inv = GetInvokingResource()
        if inv ~= nil and inv ~= GetCurrentResourceName() and not (cfg().CsCallers or {})[inv] then return notAllowed() end
    end
    local t = now()
    return withLocks({ 'cid:' .. cid, 'wo:' .. id }, function() return claimLocked(id, kind, cid, ref, t) end)
end

-- ── units ────────────────────────────────────────────────────────────────

--- The share of an order's effect one unit applies: equal shares, the last one takes the rounding.
local function unitDelta(total, units, n)
    local per = round2(total / units)
    if n >= units then return round2(total - per * (units - 1)) end
    return per
end
W.UnitDelta = unitDelta

local settlePayments -- defined below

local function queuePayments(order)
    local amount = num(order.pay_amount)
    if amount <= 0 or not order.pay_dept then return 0 end
    local rows = MySQL.query.await([[SELECT citizenid, COUNT(*) AS n FROM pf_gov_work_claims
        WHERE work_order_id = ? AND state = 'done' AND claimant_kind <> 'cs' GROUP BY citizenid]], { order.id }) or {}
    local t, n = now(), 0
    for _, r in ipairs(rows) do
        local units = num(r.n)
        if units > 0 then
            MySQL.insert.await([[INSERT IGNORE INTO pf_gov_work_payments (work_order_id, citizenid, units, amount, pay_dept, base_key, state, created_at)
                VALUES (?, ?, ?, ?, ?, ?, 'owed', ?)]], {
                order.id, r.citizenid, units, amount * units, order.pay_dept,
                ('pf-government:wo:%d:pay:%s'):format(tonumber(order.id), r.citizenid), t,
            })
            n = n + 1
        end
    end
    return n
end

local function completeOrder(order, t)
    local changed = MySQL.update.await("UPDATE pf_gov_work_orders SET status = 'completed', completed_at = ? WHERE id = ? AND status IN ('open', 'in_progress')", { t, order.id })
    if num(changed) < 1 then return false end
    order.status, order.completed_at = 'completed', t
    queuePayments(order)
    audit('work_order_complete', 'system', order.id, { kind = order.kind, district = order.district, units = num(order.units) })
    TriggerEvent('pf-government:server:workOrderCompleted', publicOrder(order, 0))
    return true
end

local function reportLocked(claimId, src, key, t)
    if not dbReady() then return fail('db_unavailable', 'City records are unavailable right now.') end
    local byKey = MySQL.single.await('SELECT * FROM pf_gov_work_claims WHERE proof_key = ? LIMIT 1', { key })
    if byKey then
        if num(byKey.id) ~= claimId then return fail('key_reused', 'That key belongs to another work unit.') end
        local o = orderRow(num(byKey.work_order_id))
        return { ok = true, duplicate = true, unitsDone = num(o and o.units_done), units = num(o and o.units),
            completed = o ~= nil and o.status == 'completed', workOrderId = num(byKey.work_order_id) }
    end
    local claim = claimRow(claimId)
    if not claim then return fail('not_found', 'No such claim.') end
    if claim.state ~= 'claimed' then return fail('invalid_state', 'This claim is ' .. tostring(claim.state) .. '.') end
    local orderId = num(claim.work_order_id)
    if num(claim.expires_at) <= t then
        MySQL.update.await("UPDATE pf_gov_work_claims SET state = 'expired' WHERE id = ? AND state = 'claimed'", { claimId })
        active[claimId] = nil
        reopenIfIdle(orderId, t)
        return fail('invalid_state', 'This claim has expired.')
    end
    return withLocks({ 'wo:' .. orderId }, function()
        local order = orderRow(orderId)
        if not order or (order.status ~= 'open' and order.status ~= 'in_progress') then
            return fail('invalid_state', 'This work order is ' .. tostring(order and order.status or 'gone') .. '.')
        end
        -- the reporter is the claimant, in person, now
        local P = playerOf(src)
        if not P or P.PlayerData.citizenid ~= claim.citizenid then
            return fail('no_permission', 'Only the worker who claimed this unit can report it.')
        end
        local entry = active[claimId] or track(claimId, claim.citizenid, order, num(claim.expires_at))
        local ok, why = sample(entry, src, t)
        if not ok then
            if why == 'vehicle' then return fail('invalid_state', 'Get out of the vehicle to work.') end
            if why == 'offline' then return fail('offline', 'The worker is not in the city.') end
            return fail('too_far', 'You are not at the work site.')
        end
        local need = minSeconds(order.kind)
        local worked = t - (entry.since or t)
        if worked < need then
            return fail('too_soon', ('Keep working: %d seconds left.'):format(need - worked), { remaining = need - worked })
        end
        local done = MySQL.update.await("UPDATE pf_gov_work_claims SET state = 'done', done_at = ?, proof_key = ? WHERE id = ? AND state = 'claimed'", { t, key, claimId })
        if num(done) < 1 then return fail('invalid_state', 'This claim was already settled.') end
        active[claimId] = nil
        local counted = MySQL.update.await('UPDATE pf_gov_work_orders SET units_done = units_done + 1 WHERE id = ? AND units_done < units', { orderId })
        if num(counted) < 1 then return fail('invalid_state', 'Every unit of this work order is already done.') end
        order = orderRow(orderId)
        local unitsDone, units = num(order.units_done), num(order.units)
        if ApplyDistrictWorkEffect then
            local applied, err = ApplyDistrictWorkEffect(order.district, order.effect_field, unitDelta(num(order.effect_delta), units, unitsDone))
            if not applied then print(('^3[PF-GOVERNMENT]^7 work order %d: district effect not applied (%s)'):format(orderId, tostring(err))) end
        end
        local completed = false
        if unitsDone >= units then completed = completeOrder(order, t) end
        return { ok = true, unitsDone = unitsDone, units = units, completed = completed, workOrderId = orderId }
    end)
end

--- Reports one finished unit. proof = { src } (the server re-reads position and identity);
--- opts.key = the caller's idempotency key (default pf-government:wo:<claimId>:1).
function W.Report(claimId, proof, opts)
    claimId = int(claimId, 1, 2147483647)
    opts = type(opts) == 'table' and opts or {}
    if not claimId or type(proof) ~= 'table' then return fail('bad_args', 'Invalid report') end
    local src = int(proof.src, 1, 65535)
    if not src then return fail('bad_args', 'Invalid proof') end
    local key = opts.key
    if key == nil then key = ('pf-government:wo:%d:1'):format(claimId) end
    if not validKey(key) then return fail('bad_args', 'Invalid key') end
    local t = now()
    local res = withLocks({ 'claim:' .. claimId }, function() return reportLocked(claimId, src, key, t) end)
    if res.ok and res.completed and settlePayments then pcall(settlePayments, t, res.workOrderId) end
    return res
end

function W.Release(claimId, reason)
    claimId = int(claimId, 1, 2147483647)
    if not claimId then return fail('bad_args', 'Invalid claim id') end
    local t = now()
    return withLocks({ 'claim:' .. claimId }, function()
        if not dbReady() then return fail('db_unavailable', 'City records are unavailable right now.') end
        local claim = claimRow(claimId)
        if not claim then return fail('not_found', 'No such claim.') end
        if claim.state == 'released' then return { ok = true, duplicate = true } end
        if claim.state ~= 'claimed' then return fail('invalid_state', 'This claim is ' .. tostring(claim.state) .. '.') end
        MySQL.update.await("UPDATE pf_gov_work_claims SET state = 'released' WHERE id = ? AND state = 'claimed'", { claimId })
        active[claimId] = nil
        reopenIfIdle(num(claim.work_order_id), t)
        return { ok = true }
    end)
end

function W.Cancel(id, reason, opts)
    id = int(id, 1, 2147483647)
    opts = type(opts) == 'table' and opts or {}
    if not id then return fail('bad_args', 'Invalid work order id') end
    local actorId
    local actor = opts.actor
    if type(actor) == 'table' and actor.src ~= nil then
        local src = int(actor.src, 1, 65535)
        if not src or not playerOf(src) then return fail('bad_args', 'Invalid actor') end
        local allowed = HasPermission(src, cfg().StaffPermission or 'utilities') or HasPermission(src, 'budgets')
            or (actor.kind == 'admin' and IsPlayerAceAllowed(tostring(src), 'command'))
        if not allowed then return fail('no_permission', 'You cannot cancel work orders.') end
        actorId = GetPlayerIdentifier(src)
    end
    local why = cleanText(reason, 200)
    local t = now()
    local res = withLocks({ 'wo:' .. id }, function()
        if not dbReady() then return fail('db_unavailable', 'City records are unavailable right now.') end
        local order = orderRow(id)
        if not order then return fail('not_found', 'No such work order.') end
        if order.status == 'cancelled' then return { ok = true, duplicate = true } end
        if order.status ~= 'open' and order.status ~= 'in_progress' then
            return fail('invalid_state', 'This work order is ' .. tostring(order.status) .. '.')
        end
        local changed = MySQL.update.await("UPDATE pf_gov_work_orders SET status = 'cancelled', completed_at = ? WHERE id = ? AND status IN ('open', 'in_progress')", { t, id })
        if num(changed) < 1 then return fail('invalid_state', 'This work order changed meanwhile.') end
        MySQL.update.await("UPDATE pf_gov_work_claims SET state = 'released' WHERE work_order_id = ? AND state = 'claimed'", { id })
        for claimId, e in pairs(active) do if e.orderId == id then active[claimId] = nil end end
        -- units already done were real work: their workers are still paid
        queuePayments(order)
        audit('work_order_cancel', actorId, id, { reason = why })
        return { ok = true }
    end)
    if res.ok and not res.duplicate and settlePayments then pcall(settlePayments, t, id) end
    return res
end

-- ── payouts (ledger, numbered attempt keys) ──────────────────────────────

local function markPaid(row, key, t)
    local n = MySQL.update.await("UPDATE pf_gov_work_payments SET state = 'paid', ledger_key = ?, settled_at = ? WHERE id = ? AND state = 'owed'", { key, t, row.id })
    if num(n) < 1 then return false end
    MySQL.update.await("UPDATE pf_gov_work_claims SET paid_key = ? WHERE work_order_id = ? AND citizenid = ? AND state = 'done'", { key, row.work_order_id, row.citizenid })
    -- the department's books show the payout as a maintenance spend (no money moves here)
    if BudgetRecordSocietyPayout then
        pcall(BudgetRecordSocietyPayout, row.pay_dept, num(row.amount), 'maintenance',
            ('Work order #%d payout'):format(num(row.work_order_id)), key)
    end
    audit('work_order_payout', 'system', row.work_order_id, { amount = num(row.amount), units = num(row.units), key = key })
    local src = sourceOfCid(row.citizenid)
    if src then TriggerClientEvent('QBCore:Notify', src, ('City maintenance paid you $%d.'):format(num(row.amount)), 'success') end
    return true
end

--- One payout: 'paid', 'unclear' (held: the ledger has not settled the last attempt), 'retry'
--- (the last attempt was clearly refused; a later run uses the next numbered key), 'failed'
--- (given up after MaxPayAttempts) or 'bank_unavailable'.
local function settleOne(row, t)
    local society = societyOf(row.pay_dept)
    local retry = math.max(30, num(cfg().PayRetrySeconds or 300))
    if not society or not GovAttemptKey then
        MySQL.update.await("UPDATE pf_gov_work_payments SET state = 'failed', settled_at = ? WHERE id = ? AND state = 'owed'", { t, row.id })
        return 'failed'
    end
    local key, status = GovAttemptKey(row.base_key)
    if key == false then return 'bank_unavailable' end
    if status == 'completed' then markPaid(row, key, t) return 'paid' end
    if status == 'unclear' then
        MySQL.update.await('UPDATE pf_gov_work_payments SET ledger_key = ?, next_try_at = ? WHERE id = ?', { key, t + retry, row.id })
        return 'unclear'
    end
    if num(row.attempts) >= math.max(1, num(cfg().MaxPayAttempts or 10)) then
        MySQL.update.await("UPDATE pf_gov_work_payments SET state = 'failed', settled_at = ? WHERE id = ? AND state = 'owed'", { t, row.id })
        audit('work_order_payout', 'system', row.work_order_id, { failed = true, amount = num(row.amount), attempts = num(row.attempts) })
        return 'failed'
    end
    -- the attempt and its key are written before the money moves, so a crash leaves a trace
    MySQL.update.await('UPDATE pf_gov_work_payments SET attempts = attempts + 1, ledger_key = ?, next_try_at = ? WHERE id = ?', { key, t + retry, row.id })
    local paid, res = PFPayout.Pay(row.citizenid, 'bank', num(row.amount), {
        key = key, from = 'society:' .. society, kind = 'wage', quiet = true,
        reason = ('City maintenance: work order #%d'):format(num(row.work_order_id)),
    })
    if paid then markPaid(row, key, t) return 'paid' end
    if PFPayout.IsClearFailure(res) then return 'retry' end
    return 'unclear'
end
W.SettleOne = settleOne

--- Pays owed payouts that are due (all, or one order's).
settlePayments = function(t, orderId)
    t = t or now()
    if not dbReady() then return {} end
    local rows
    if orderId then
        rows = MySQL.query.await("SELECT * FROM pf_gov_work_payments WHERE state = 'owed' AND work_order_id = ? LIMIT 25", { orderId })
    else
        rows = MySQL.query.await("SELECT * FROM pf_gov_work_payments WHERE state = 'owed' AND next_try_at <= ? ORDER BY id LIMIT 25", { t })
    end
    local out = {}
    for _, row in ipairs(rows or {}) do
        local name = 'pay:' .. tostring(row.id)
        if not locks[name] then
            locks[name] = true
            local ok, res = pcall(settleOne, row, t)
            locks[name] = nil
            out[#out + 1] = ok and res or 'error'
            if not ok then print('^1[PF-GOVERNMENT]^7 work order payout failed: ' .. tostring(res)) end
        end
    end
    return out
end
W.SettlePayments = settlePayments

-- ── sweeps ───────────────────────────────────────────────────────────────

--- Expires claims and orders past their time, then pays what is due. Run every SweepSeconds.
function W.Sweep(t)
    t = t or now()
    if not dbReady() then return { claims = 0, orders = 0 } end
    local claims = MySQL.query.await("SELECT id, work_order_id FROM pf_gov_work_claims WHERE state = 'claimed' AND expires_at <= ? LIMIT 200", { t }) or {}
    local nClaims = 0
    for _, c in ipairs(claims) do
        local id = tonumber(c.id)
        if not locks['claim:' .. id] then
            nClaims = nClaims + num(MySQL.update.await("UPDATE pf_gov_work_claims SET state = 'expired' WHERE id = ? AND state = 'claimed'", { id }))
            active[id] = nil
            reopenIfIdle(num(c.work_order_id), t)
        end
    end
    local orders = MySQL.query.await("SELECT * FROM pf_gov_work_orders WHERE status IN ('open', 'in_progress') AND expires_at <= ? LIMIT 100", { t }) or {}
    local nOrders = 0
    for _, o in ipairs(orders) do
        withLocks({ 'wo:' .. tostring(o.id) }, function()
            local n = MySQL.update.await("UPDATE pf_gov_work_orders SET status = 'expired' WHERE id = ? AND status IN ('open', 'in_progress')", { o.id })
            if num(n) > 0 then
                nOrders = nOrders + 1
                MySQL.update.await("UPDATE pf_gov_work_claims SET state = 'expired' WHERE work_order_id = ? AND state = 'claimed'", { o.id })
                for claimId, e in pairs(active) do if e.orderId == tonumber(o.id) then active[claimId] = nil end end
                queuePayments(o)
            end
            return { ok = true }
        end)
    end
    for claimId, e in pairs(active) do
        if e.expiresAt and e.expiresAt <= t then active[claimId] = nil end
    end
    settlePayments(t)
    return { claims = nClaims, orders = nOrders }
end

-- ── generator ────────────────────────────────────────────────────────────

local rotation = {}
local generating = false

local function crosses(state, rule)
    local v = tonumber(state[rule.field])
    if not v then return false end
    if rule.above ~= nil and v > rule.above then return true end
    if rule.below ~= nil and v < rule.below then return true end
    return false
end

local function siteKey(x, y) return ('%d:%d'):format(math.floor(num(x) + 0.5), math.floor(num(y) + 0.5)) end

--- A kind of the rule and a site of the district that can host it, preferring a site no open
--- order uses; the rule's kinds take turns.
local function pickSite(district, rule, used)
    local sites = (cfg().Sites or {})[district] or {}
    local kinds = rule.kinds or { rule.kind }
    local rk = district .. ':' .. tostring(rule.id)
    local start = rotation[rk] or 1
    for pass = 1, 2 do
        for i = 0, #kinds - 1 do
            local idx = ((start - 1 + i) % #kinds) + 1
            local kind = kinds[idx]
            for _, s in ipairs(sites) do
                local hosts = false
                for _, k in ipairs(s.kinds or {}) do if k == kind then hosts = true break end end
                if hosts and (pass == 2 or not used[siteKey(s.x, s.y)]) then
                    rotation[rk] = idx % #kinds + 1
                    return kind, s
                end
            end
        end
    end
    return nil
end

--- Called by the infrastructure simulation every tick with the district states: districts over a
--- threshold get one order per rule, up to MaxOpenPerDistrict open orders. Returns how many it made.
function W.OnInfrastructureTick(districts)
    local c = cfg()
    if c.Enabled == false or type(districts) ~= 'table' or generating then return 0 end
    if not dbReady() then return 0 end
    generating = true
    local ok, made = pcall(function()
        local rows = MySQL.query.await("SELECT district, source_type, source_id, x, y FROM pf_gov_work_orders WHERE status IN ('open', 'in_progress')") or {}
        local count, rules, used = {}, {}, {}
        for _, r in ipairs(rows) do
            count[r.district] = (count[r.district] or 0) + 1
            if r.source_type == 'district' and r.source_id then rules[r.source_id] = true end
            used[r.district] = used[r.district] or {}
            used[r.district][siteKey(r.x, r.y)] = true
        end
        local names = {}
        for name in pairs(districts) do if districtsCfg()[name] then names[#names + 1] = name end end
        table.sort(names)
        local max, n, t = num(c.MaxOpenPerDistrict or 3), 0, now()
        for _, name in ipairs(names) do
            local state = districts[name]
            for _, rule in ipairs(c.Thresholds or {}) do
                local sourceId = name .. ':' .. tostring(rule.id)
                if (count[name] or 0) < max and not rules[sourceId] and crosses(state, rule) then
                    used[name] = used[name] or {}
                    local kind, site = pickSite(name, rule, used[name])
                    if kind then
                        local res = W.Create({
                            kind = kind, district = name,
                            site = { x = site.x, y = site.y, z = site.z, r = site.r or 30.0, label = site.label },
                            units = rule.units or 2, effect = { field = rule.field, delta = rule.delta },
                            source = { type = 'district', id = sourceId }, payable = rule.pay,
                            csEligible = rule.csEligible ~= false,
                            expiresAt = t + num(rule.lifetimeHours or c.DefaultLifetimeHours or 48) * 3600,
                        })
                        if res.ok and not res.duplicate then
                            n = n + 1
                            count[name] = (count[name] or 0) + 1
                            rules[sourceId] = true
                            used[name][siteKey(site.x, site.y)] = true
                        end
                    end
                end
            end
        end
        return n
    end)
    generating = false
    if not ok then error(made) end
    return made
end

--- The district of the nearest configured site within EventMaxDistance (events often carry no
--- district of ours, and the server cannot read GTA zone names).
local function nearestDistrict(pos)
    local best, bestD = nil, num(cfg().EventMaxDistance or 1500)
    for district, sites in pairs(cfg().Sites or {}) do
        if districtsCfg()[district] then
            for _, s in ipairs(sites) do
                local dx, dy = num(s.x) - pos.x, num(s.y) - pos.y
                local d = math.sqrt(dx * dx + dy * dy)
                if d <= bestD then best, bestD = district, d end
            end
        end
    end
    return best
end

--- For a city-wide event (no position, e.g. severe weather): the event's own district when it names
--- one of ours, otherwise the district with the fewest open orders (ties by name); placed at the
--- first site of that district that hosts the kind. nil when no district has such a site.
local function districtSiteFor(event, kind)
    local function siteOf(district)
        for _, s in ipairs((cfg().Sites or {})[district] or {}) do
            for _, k in ipairs(s.kinds or {}) do if k == kind then return s end end
        end
    end
    if type(event.district) == 'string' and districtsCfg()[event.district] then
        local s = siteOf(event.district)
        if s then return event.district, s end
        return nil
    end
    local open = {}
    for _, r in ipairs(MySQL.query.await("SELECT district, COUNT(*) AS n FROM pf_gov_work_orders WHERE status IN ('open', 'in_progress') GROUP BY district") or {}) do
        open[r.district] = num(r.n)
    end
    local names = {}
    for name in pairs(districtsCfg()) do if siteOf(name) then names[#names + 1] = name end end
    table.sort(names, function(a, b)
        if (open[a] or 0) ~= (open[b] or 0) then return (open[a] or 0) < (open[b] or 0) end
        return a < b
    end)
    if not names[1] then return nil end
    return names[1], siteOf(names[1])
end

--- A city event that leaves work behind (Config.WorkOrders.FromEvents) becomes one order at the
--- event's position, or, for a rule with atDistrictSite and an event without a position, at a
--- district site (districtSiteFor). The event id is the order's key, so a repeated event makes no
--- second order.
function W.OnCityEvent(event)
    if cfg().Enabled == false or type(event) ~= 'table' or type(event.kind) ~= 'string' then return nil end
    local rule = (cfg().FromEvents or {})[event.kind]
    if type(rule) ~= 'table' then return nil end
    local id = int(event.id, 1, 9007199254740991)
    if not id then return nil end
    local pos = coordsOf(event.coords)
    local district, label
    if pos then
        district = type(event.district) == 'string' and districtsCfg()[event.district] and event.district or nearestDistrict(pos)
        label = cleanText(event.title, 64)
    elseif rule.atDistrictSite then
        if not dbReady() then return nil end
        local site
        district, site = districtSiteFor(event, rule.kind)
        if site then
            pos = { x = num(site.x), y = num(site.y), z = num(site.z) }
            label = cleanText(site.label, 64)
        end
    end
    if not district or not pos then return nil end
    local c = cfg()
    return W.Create({
        kind = rule.kind, district = district,
        site = { x = pos.x, y = pos.y, z = pos.z, r = rule.radius or 25.0, label = label },
        units = rule.units or 2, effect = { field = rule.field or 'maintenance_backlog', delta = rule.delta },
        source = { type = 'event', id = tostring(id) }, payable = rule.pay, csEligible = rule.csEligible ~= false,
        expiresAt = now() + num(rule.lifetimeHours or c.DefaultLifetimeHours or 48) * 3600,
    }, { key = 'pf-government:wo:event:' .. id })
end

AddEventHandler('pf-services:cityEvent', function(event)
    local ok, err = pcall(W.OnCityEvent, event)
    if not ok then print('^1[PF-GOVERNMENT]^7 work order from city event failed: ' .. tostring(err)) end
end)

-- ── start-up ─────────────────────────────────────────────────────────────

--- Loads the open claims into the sampler (after a restart the on-site stretch starts again).
function InitializeWorkOrders()
    if not dbReady() then return false end
    local t = now()
    local rows = MySQL.query.await([[SELECT c.id, c.citizenid, c.expires_at, o.id AS work_order_id, o.kind, o.x, o.y, o.z, o.radius
        FROM pf_gov_work_claims c JOIN pf_gov_work_orders o ON o.id = c.work_order_id
        WHERE c.state = 'claimed' AND c.expires_at > ?]], { t }) or {}
    for _, r in ipairs(rows) do
        track(tonumber(r.id), r.citizenid, { id = r.work_order_id, kind = r.kind, x = r.x, y = r.y, z = r.z, radius = r.radius }, num(r.expires_at))
    end
    print(('^2[PF-GOVERNMENT]^7 Work orders ready (%d open claims)'):format(#rows))
    return true
end

function StartWorkOrderTasks()
    CreateThread(function()
        while true do
            Wait(math.max(1, num(cfg().SampleSeconds or 5)) * 1000)
            local ok, err = pcall(W.SampleClaims, now())
            if not ok then print('^1[PF-GOVERNMENT]^7 work order sampler failed: ' .. tostring(err)) end
        end
    end)
    CreateThread(function()
        while true do
            Wait(math.max(10, num(cfg().SweepSeconds or 60)) * 1000)
            local ok, err = pcall(W.Sweep, now())
            if not ok then print('^1[PF-GOVERNMENT]^7 work order sweep failed: ' .. tostring(err)) end
        end
    end)
end

-- ── exports ──────────────────────────────────────────────────────────────

local function export(name, fn)
    exports(name, function(...)
        if not callerAllowed(name) then return notAllowed() end
        local ok, res = pcall(fn, ...)
        if not ok then
            print(('^1[PF-GOVERNMENT]^7 %s failed: %s'):format(name, tostring(res)))
            return fail('db_unavailable', 'City records are unavailable right now. Nothing was changed.')
        end
        return res
    end)
end

export('CreateWorkOrder', function(spec, opts) return W.Create(spec, opts) end)
export('ListWorkOrders', function(filter) return W.List(filter) end)
export('GetWorkOrder', function(id) return W.Get(id) end)
export('ClaimWorkOrder', function(id, claimant, opts) return W.Claim(id, claimant, opts) end)
export('ReportWorkUnit', function(claimId, proof, opts) return W.Report(claimId, proof, opts) end)
export('ReleaseWorkClaim', function(claimId, reason) return W.Release(claimId, reason) end)
export('CancelWorkOrder', function(id, reason, opts) return W.Cancel(id, reason, opts) end)

print('^2[PF-GOVERNMENT]^7 Work orders module loaded')
