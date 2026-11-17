-- Hospital lab and the order table shared with imaging and surgery (batch 20A, architecture 4.2,
-- 4.5, 11.3, 11.6).
--
-- Lab orders (blood_type, cbc, tox, bac) follow ordered -> in_progress -> resulted (or cancelled):
--   * a nurse (Lab.OrderTier) orders for a patient with an open admission, inside that hospital;
--   * a paramedic or above (Lab.DrawTier) draws the sample next to the patient (server positions).
--     What the sample shows is read from the medical engine's state at that moment (blood volume,
--     haemoglobin, toxins, injuries; blood type from the character) and kept in the order row,
--     hidden, until the result is due (`ready_at`); nothing a client sends goes into a result;
--   * Lab.Tick (a named step the thread calls) releases due results: confirmed lab findings go
--     through the 17A diagnosis layer (Dx.Record), which confirms the diagnosis of that injury.
-- The tox screen and infection markers use 17A's lab sensitivity at the lab's reading tier (a miss
-- reports nothing, never a false positive); CBC values and BAC are measurements of the state.
-- Resulted lab and imaging orders are billed on the admission (Tariff.Lab / Tariff.Imaging).

PFHospital = PFHospital or {}
local H = PFHospital
H.Lab = H.Lab or {}
local L = H.Lab
H.Orders = H.Orders or {}
local O = H.Orders
H.SQL = H.SQL or {}
local Q = H.SQL
local A = H.Admissions

local function cfg() return Config.Hospital.Lab end
local function now() return H.Now() end

-- ── SQL: pf_hosp_orders (lab, imaging, procedure) ──────────────────────────────────────────

local ORD_COLS = 'id, citizenid, admission_id, hospital_id, kind, test, state, ordered_by, done_by, result, sample, ordered_at, ready_at, resulted_at, bill_id, idem_key'

function Q.OrdInsert(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_orders (citizenid, admission_id, hospital_id, kind, test, state, ordered_by, done_by, ordered_at,
        ready_at, idem_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { r.citizenid, r.admission_id, r.hospital_id, r.kind, r.test, r.state or 'ordered', r.ordered_by, r.done_by, r.ordered_at, r.ready_at, r.idem_key })
end

function Q.OrdGet(id)
    return MySQL.single.await('SELECT ' .. ORD_COLS .. ' FROM pf_hosp_orders WHERE id = ? LIMIT 1', { id })
end

function Q.OrdOpenFor(cid, kind, test)
    return MySQL.single.await([[SELECT ]] .. ORD_COLS .. [[ FROM pf_hosp_orders WHERE citizenid = ? AND kind = ? AND test = ?
        AND state IN ('ordered', 'in_progress') ORDER BY id LIMIT 1]], { cid, kind, test })
end

--- ordered -> in_progress, only while the order is still 'ordered'. Returns rows changed.
function Q.OrdStart(id, doneBy, readyAt, sample)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_orders SET state = 'in_progress', done_by = ?, ready_at = ?, sample = ?
        WHERE id = ? AND state = 'ordered']], { doneBy, readyAt, sample, id }))
end

--- An interrupted scan goes back to 'ordered'.
function Q.OrdReset(id)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_orders SET state = 'ordered', done_by = NULL, ready_at = NULL, sample = NULL
        WHERE id = ? AND state = 'in_progress']], { id }))
end

--- in_progress -> resulted (once). The hidden sample is cleared.
function Q.OrdResult(id, result, at)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_orders SET state = 'resulted', result = ?, resulted_at = ?, sample = NULL
        WHERE id = ? AND state = 'in_progress']], { result, at, id }))
end

function Q.OrdCancel(id)
    return H.Affected(MySQL.update.await("UPDATE pf_hosp_orders SET state = 'cancelled' WHERE id = ? AND state IN ('ordered', 'in_progress')", { id }))
end

function Q.OrdDue(kind, at, limit)
    return MySQL.query.await([[SELECT id FROM pf_hosp_orders WHERE kind = ? AND state = 'in_progress' AND ready_at <= ? ORDER BY ready_at, id LIMIT ?]],
        { kind, at, limit or 50 }) or {}
end

function Q.OrdExpire(kind, before)
    return H.Affected(MySQL.update.await("UPDATE pf_hosp_orders SET state = 'cancelled' WHERE kind = ? AND state = 'ordered' AND ordered_at < ?", { kind, before }))
end

function Q.OrdForCid(cid, limit)
    return MySQL.query.await('SELECT ' .. ORD_COLS .. ' FROM pf_hosp_orders WHERE citizenid = ? ORDER BY id DESC LIMIT ?', { cid, limit or 20 }) or {}
end

function Q.OrdList(hospitalId, openOnly, limit)
    local where = openOnly and " AND state IN ('ordered', 'in_progress')" or ''
    return MySQL.query.await('SELECT ' .. ORD_COLS .. ' FROM pf_hosp_orders WHERE hospital_id = ?' .. where .. ' ORDER BY id DESC LIMIT ?',
        { hospitalId, limit or 50 }) or {}
end

--- Billable orders of an admission: resulted lab and imaging orders.
function Q.OrdBillable(admissionId)
    return MySQL.query.await([[SELECT id, kind, test FROM pf_hosp_orders WHERE admission_id = ? AND state = 'resulted' AND kind IN ('lab', 'imaging')
        ORDER BY id LIMIT 100]], { admissionId }) or {}
end

function Q.OrdSetBill(admissionId, billId)
    return MySQL.update.await('UPDATE pf_hosp_orders SET bill_id = ? WHERE admission_id = ? AND bill_id IS NULL AND state = ?', { billId, admissionId, 'resulted' })
end

function Q.OrdDeleteCharacter(cid)
    return MySQL.update.await('DELETE FROM pf_hosp_orders WHERE citizenid = ?', { cid })
end

-- ── shared order helpers (imaging.lua and surgery.lua use them) ──────────────────────────────

local function decode(v)
    if type(v) ~= 'string' or v == '' then return nil end
    local ok, t = pcall(json.decode, v)
    return ok and type(t) == 'table' and t or nil
end
O.Decode = decode

local function testLabel(kind, test)
    local c = kind == 'lab' and cfg().Tests[test] or (kind == 'imaging' and Config.Hospital.Imaging.Tests[test])
        or (kind == 'procedure' and Config.Hospital.Surgery.Procedures[test]) or nil
    return c and c.label or test
end
O.Label = testLabel

--- What staff see of an order; the hidden sample never leaves the server.
function O.View(r)
    if not r then return nil end
    return { id = tonumber(r.id), citizenid = r.citizenid, admissionId = tonumber(r.admission_id), hospitalId = r.hospital_id, kind = r.kind,
        test = r.test, label = testLabel(r.kind, r.test), state = r.state, orderedBy = r.ordered_by, doneBy = r.done_by,
        orderedAt = tonumber(r.ordered_at), readyAt = tonumber(r.ready_at), resultedAt = tonumber(r.resulted_at),
        result = r.state == 'resulted' and decode(r.result) or nil }
end

--- Public findings (17A shape) for a result.
function O.PublicFindings(list)
    local out = {}
    local Dx = PFMed.Diagnosis
    for _, f in ipairs(list or {}) do out[#out + 1] = Dx.PublicFinding(f) end
    return out
end

--- The patient (online), their open admission and the provider's position check for an order
--- action. Returns ctx = { P, tier, T, psrc, cid, a } | nil, code, message.
function O.Context(src, target, minTier, maxDist)
    local P, tier, msg = H.Provider(src, nil, minTier)
    if not P then return nil, tier, msg end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T then return nil, 'offline', 'Patient not found.' end
    if target == src then return nil, 'bad_args', 'Not on yourself.' end
    local cid = T.PlayerData.citizenid
    local a = A.OpenOf(cid)
    if not a then return nil, 'invalid_state', 'The patient needs an open admission (check-in or triage) first.' end
    if not H.Facility.InFacility(src, a.hospital_id) then return nil, 'too_far', 'You must be in the patient\'s hospital.' end
    if maxDist and H.Dist(H.Pos(src), H.Pos(target)) > maxDist then return nil, 'too_far', 'Stand next to the patient.' end
    return { P = P, tier = tier, T = T, psrc = target, cid = cid, a = a }
end

--- Creates one order (one open order per patient, kind and test). Returns { ok, orderId, duplicate? }.
function O.Create(ctx, kind, test)
    local res, err = H.WithLock('ord:' .. ctx.cid, function()
        local okF, open = pcall(Q.OrdOpenFor, ctx.cid, kind, test)
        if not okF then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        if open then return { ok = true, duplicate = true, orderId = tonumber(open.id), state = open.state } end
        local ok, id = pcall(Q.OrdInsert, { citizenid = ctx.cid, admission_id = ctx.a.id, hospital_id = ctx.a.hospital_id, kind = kind, test = test,
            ordered_by = ctx.P.PlayerData.citizenid, ordered_at = now() })
        id = ok and tonumber(id) or nil
        if not id then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        H.Audit(ctx.cid, 'order', H.ActorOf(ctx.P.PlayerData.source, ctx.P), { id = id, kind = kind, test = test, admission = ctx.a.id })
        return { ok = true, orderId = id, state = 'ordered' }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

--- Loads an order of `kind` and its patient for a staff action. Returns r, psrc, a | nil, code, msg.
function O.Load(orderId, kind)
    orderId = H.Int(orderId, 1)
    if not orderId then return nil, 'bad_args', 'Invalid order.' end
    local ok, r = pcall(Q.OrdGet, orderId)
    if not ok then return nil, 'db_unavailable', 'Hospital records are unavailable.' end
    if not r or r.kind ~= kind then return nil, 'not_found', 'No such order.' end
    r.id = tonumber(r.id)
    local a = A.OpenOf(r.citizenid)
    if not a or a.id ~= tonumber(r.admission_id) then return nil, 'invalid_state', 'The admission of this order is closed.' end
    local psrc = H.SourceOfCid(r.citizenid)
    if not psrc then return nil, 'offline', 'The patient is not here.' end
    return r, psrc, a
end

local function notifyCid(cid, text, kind)
    local src = cid and H.SourceOfCid(cid)
    if src then H.Notify(src, text, kind or 'primary') end
end
O.NotifyCid = notifyCid

-- ── lab: order, draw, results ─────────────────────────────────────────────────────────────────

function L.Order(src, target, test)
    if H.Limited(src, 'lab_order', 1) then return H.Fail('rate_limited', 'Slow down.') end
    if type(test) ~= 'string' or not cfg().Tests[test] then return H.Fail('bad_args', 'Test: blood_type, cbc, tox or bac.') end
    local ctx, code, msg = O.Context(src, target, cfg().OrderTier, Config.Hospital.Roles.TouchDistance * 4)
    if not ctx then return H.Fail(code, msg) end
    return O.Create(ctx, 'lab', test)
end

-- which lab-panel signs (17A findings.lua) each test reports
local LOOK = { cbc = { infection_markers = true, gi_pathogen = true }, tox = { tox_screen = true } }

--- What a sample drawn now shows (engine state only). Returns { values, findings } | nil, code.
function L.Sample(cid, test, T, at)
    local Store, E, Dx = PFMed.Store, PFMed.Engine, PFMed.Diagnosis
    local p, err = Store.Get(cid)
    if not p then return nil, err or 'db_unavailable' end
    E.Touch(p, at)
    local values, findings = {}, {}
    if test == 'blood_type' then
        local md = T and T.PlayerData.metadata or {}
        local bt = type(md.bloodtype) == 'string' and md.bloodtype:gsub('[^%w%+%-]', ''):sub(1, 4) or nil
        values.bloodType = (bt and bt ~= '') and bt or 'undetermined'
    elseif test == 'bac' then
        values.bac = math.floor((tonumber(p.toxins and p.toxins.ethanol) or 0) * 1000 + 0.5) / 1000
    else
        if test == 'cbc' then
            local Ph = PFMed.Physiology
            local loss = tonumber(Ph.LossFraction(tonumber(p.blood_ml) or 5000, Ph.Cfg(Config.Medical))) or 0
            local hb = 14.5 * (tonumber(p.hgb_factor) or 1) * (1 - 0.5 * loss)
            local wbc = 7.0
            for _, inj in pairs(p.injuries or {}) do
                if inj.stage ~= 'recovered' and (inj.type == 'infection' or (inj.type == 'illness' and inj.subtype == 'infection_sepsis')) then
                    wbc = math.max(wbc, 7.0 + 3.5 * (tonumber(inj.severity) or 1))
                end
            end
            values.hemoglobin = math.floor(hb * 10 + 0.5) / 10
            values.hematocrit = math.floor(hb * 3 + 0.5)
            values.wbc = math.floor(wbc * 10 + 0.5) / 10
            values.platelets = math.floor(250 * (1 - 0.6 * loss) + 0.5)
        end
        local list = Dx.Generate(p, 'labs', cfg().ReadTier, at)
        for _, f in ipairs(list) do
            if LOOK[test] and LOOK[test][f.sign] then findings[#findings + 1] = f end
        end
        if test == 'tox' then
            local pos = {}
            for _, f in ipairs(findings) do if f.value then pos[#pos + 1] = f.value end end
            table.sort(pos)
            values.positive = pos
        end
    end
    return { values = values, findings = findings }
end

function L.Draw(src, orderId)
    if H.Limited(src, 'lab_draw', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local r, psrc, a = O.Load(orderId, 'lab')
    if not r then return H.Fail(psrc, a) end
    if r.state ~= 'ordered' then return H.Fail('invalid_state', ('The order is %s.'):format(r.state)) end
    local P, tierOrErr, msg = H.Provider(src, a.hospital_id, cfg().DrawTier)
    if not P then return H.Fail(tierOrErr, msg) end
    if psrc == src then return H.Fail('bad_args', 'Not on yourself.') end
    if H.Dist(H.Pos(src), H.Pos(psrc)) > Config.Hospital.Roles.TouchDistance then return H.Fail('too_far', 'Stand next to the patient.') end
    if not H.Facility.InFacility(psrc, a.hospital_id) then return H.Fail('too_far', 'The patient is not in the hospital.') end
    local res, err = H.WithLock('ordrun:' .. r.id, function()
        local at = now()
        local sample, serr = L.Sample(r.citizenid, r.test, H.Player(psrc), at)
        if not sample then return H.Fail(serr or 'db_unavailable', 'Medical records are unavailable.') end
        local readyAt = at + (tonumber(cfg().Tests[r.test].seconds) or 60)
        local ok, n = pcall(Q.OrdStart, r.id, P.PlayerData.citizenid, readyAt, json.encode(sample))
        if not ok then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
        if n ~= 1 then return H.Fail('invalid_state', 'The order changed; try again.') end
        PFMed.Diagnosis.NoteCare(r.citizenid, P.PlayerData.citizenid, at)
        H.Audit(r.citizenid, 'sample', H.ActorOf(src, P), { order = r.id, test = r.test })
        return { ok = true, orderId = r.id, readyAt = readyAt }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

--- Releases one due result: findings through the diagnosis layer, then the order is resulted.
function L.Release(id, at)
    local res = H.WithLock('ordrun:' .. id, function()
        local ok, r = pcall(Q.OrdGet, id)
        if not ok or not r or r.state ~= 'in_progress' or (tonumber(r.ready_at) or math.huge) > at then return 'skip' end
        local sample = decode(r.sample) or { values = {}, findings = {} }
        local stored = {}
        if #(sample.findings or {}) > 0 then
            local saved = PFMed.Diagnosis.Record(r.citizenid, sample.findings, { cid = r.done_by, tier = cfg().ReadTier }, at)
            if not saved then return 'wait' end
            stored = saved
        end
        local result = { values = sample.values or {}, findings = O.PublicFindings(stored) }
        local okR, n = pcall(Q.OrdResult, tonumber(r.id), json.encode(result), at)
        if not okR or n ~= 1 then return 'skip' end
        H.Audit(r.citizenid, 'result', { kind = 'system', label = 'lab' }, { order = tonumber(r.id), test = r.test, findings = #stored })
        notifyCid(r.ordered_by, ('Lab result ready: %s (order #%d).'):format(testLabel('lab', r.test), tonumber(r.id)), 'success')
        TriggerEvent('pf-ambulancejob:server:orderResulted', O.View({ id = r.id, citizenid = r.citizenid, admission_id = r.admission_id,
            hospital_id = r.hospital_id, kind = r.kind, test = r.test, state = 'resulted', ordered_by = r.ordered_by, done_by = r.done_by,
            ordered_at = r.ordered_at, ready_at = r.ready_at, resulted_at = at, result = json.encode(result) }))
        return 'resulted'
    end)
    return res or 'busy'
end

--- One pass: due results released, orders nobody drew within OrderValidHours cancelled.
function L.Tick(at)
    at = at or now()
    pcall(Q.OrdExpire, 'lab', at - (cfg().OrderValidHours or 24) * 3600)
    local ok, rows = pcall(Q.OrdDue, 'lab', at, 50)
    if not ok then return {} end
    local out = {}
    for _, row in ipairs(rows) do out[tonumber(row.id)] = L.Release(tonumber(row.id), at) end
    return out
end

-- ── results for staff (chart access, 17A 6.6) ─────────────────────────────────────────────────

--- The orders of a patient this provider may see (lab, imaging, procedures), newest first.
function O.ForPatient(src, target)
    local Dx = PFMed.Diagnosis
    local provider, perr = Dx.Provider(src)
    if not provider then return H.Fail(perr, 'You are not loaded.') end
    if provider.tier < 1 then return H.Fail('no_permission', 'Only on-duty medical staff see results.') end
    local cid, psrc = Dx.Patient(H.Int(target, 1) or target)
    if not cid then return H.Fail(psrc or 'not_found', 'Patient not found.') end
    local okSee, why = Dx.CanSeeChart(provider, cid, psrc)
    Dx.Audit(cid, 'record_read', provider, { via = 'orders', reason = okSee and why or nil, denied = (not okSee) and why or nil })
    if not okSee then return H.Fail(why, 'You may not see this patient\'s results.') end
    local ok, rows = pcall(Q.OrdForCid, cid, 20)
    if not ok then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = O.View(r) end
    return { ok = true, list = list }
end

-- ── billing: resulted lab and imaging orders of the admission ─────────────────────────────────

if H.Billing and H.Billing.Lines then
    local lines = H.Billing.Lines
    H.Billing.Lines = function(a)
        local out, err = lines(a)
        if not out then return out, err end
        local ok, rows = pcall(Q.OrdBillable, a.id)
        if not ok then return nil, 'db_unavailable' end
        local tariff = Config.Hospital.Tariff
        local mult = H.ServiceMultiplier and H.ServiceMultiplier(a) or 1
        for _, r in ipairs(rows) do
            local prices = r.kind == 'lab' and tariff.Lab or tariff.Imaging
            local price = math.floor((tonumber(prices and prices[r.test]) or 0) * mult + 0.5)
            if price > 0 then
                out[#out + 1] = { kind = 'procedure', ref_id = tonumber(r.id), label = ('%s: %s'):format(r.kind == 'lab' and 'Lab' or 'Imaging',
                    testLabel(r.kind, r.test)):sub(1, 96), qty = 1, unit_price = price }
            end
        end
        return out
    end
end

if H.Billing and H.Billing.ForAdmission then
    local forAdmission = H.Billing.ForAdmission
    --- The bill made for an admission is stamped on its orders (what was billed where).
    H.Billing.ForAdmission = function(a, ctx)
        local id = forAdmission(a, ctx)
        if id and a and a.id then pcall(Q.OrdSetBill, a.id, id) end
        return id
    end
end

-- ── export (read) and callbacks ───────────────────────────────────────────────────────────────

exports('ListHospitalOrders', function(hospitalId, filter)
    if not (H.ServiceAllowed and H.ServiceAllowed('ListHospitalOrders')) then return H.Fail('not_allowed', 'Not allowed.') end
    local fid = H.Facility.Id(hospitalId)
    if not fid then return H.Fail('bad_args', 'Unknown hospital.') end
    filter = type(filter) == 'table' and filter or {}
    local ok, rows = pcall(Q.OrdList, fid, filter.open ~= false, H.Int(filter.limit, 1, 100) or 50)
    if not ok then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
    local list = {}
    for _, r in ipairs(rows) do
        local v = O.View(r)
        if filter.kind == nil or filter.kind == v.kind then list[#list + 1] = v end
    end
    return { ok = true, list = list }
end)

local callback = H.ServiceCallback
callback('labOrder', function(src, target, test) return L.Order(src, target, test) end)
callback('labDraw', function(src, orderId) return L.Draw(src, orderId) end)
callback('orderCancel', function(src, orderId) return O.Cancel(src, orderId) end)
callback('patientOrders', function(src, target) return O.ForPatient(src, target) end)

--- Staff who could order it cancel an open order (lab, imaging).
function O.Cancel(src, orderId)
    orderId = H.Int(orderId, 1)
    if not orderId then return H.Fail('bad_args', 'Invalid order.') end
    local ok, r = pcall(Q.OrdGet, orderId)
    if not ok then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
    if not r or (r.kind ~= 'lab' and r.kind ~= 'imaging') then return H.Fail('not_found', 'No such order.') end
    local tier = r.kind == 'lab' and cfg().OrderTier or Config.Hospital.Imaging.OrderTier
    local P, tierOrErr, msg = H.Provider(src, r.hospital_id, tier)
    if not P then return H.Fail(tierOrErr, msg) end
    local okC, n = pcall(Q.OrdCancel, orderId)
    if not okC then return H.Fail('db_unavailable', 'Hospital records are unavailable.') end
    if n ~= 1 then return H.Fail('invalid_state', 'The order is not open.') end
    H.Audit(r.citizenid, 'order_cancel', H.ActorOf(src, P), { id = orderId })
    return { ok = true }
end

local function reply(src, res, okText)
    if res and res.ok then H.Notify(src, okText, 'success') else H.Notify(src, (res and res.message) or 'Refused.', 'error') end
end

function L.RegisterCommands()
    local QB = PFAmbulance.GetCore()
    if not QB.Commands or not QB.Commands.Add then return end
    local add = QB.Commands.Add
    add('hlab', 'Hospital: order a lab test (blood_type, cbc, tox, bac)', { { name = 'id', help = 'Player id' }, { name = 'test', help = 'Test' } }, true, function(source, args)
        local res = L.Order(source, args[1], tostring(args[2] or ''):lower())
        reply(source, res, res.ok and ('Lab order #%d.'):format(res.orderId) or '')
    end)
    add('hdraw', 'Hospital: draw the sample for a lab order', { { name = 'order', help = 'Order number' } }, true, function(source, args)
        local res = L.Draw(source, args[1])
        reply(source, res, res.ok and ('Sample sent; result in %d s.'):format(math.max(0, res.readyAt - now())) or '')
    end)
    add('hordercancel', 'Hospital: cancel a lab or imaging order', { { name = 'order', help = 'Order number' } }, true, function(source, args)
        reply(source, O.Cancel(source, args[1]), 'Order cancelled.')
    end)
    add('hresults', 'Hospital: lab and imaging orders of a patient', { { name = 'id', help = 'Player id' } }, true, function(source, args)
        local res = O.ForPatient(source, args[1])
        if not res.ok then return H.Notify(source, res.message or 'Refused.', 'error') end
        local parts = {}
        for i = 1, math.min(6, #res.list) do
            local o = res.list[i]
            local summary = o.state
            if o.result then
                local bits = {}
                for k, v in pairs(o.result.values or {}) do bits[#bits + 1] = k .. '=' .. (type(v) == 'table' and table.concat(v, '/') or tostring(v)) end
                for _, f in ipairs(o.result.findings or {}) do bits[#bits + 1] = tostring(f.label) .. (f.value and (' ' .. tostring(f.value)) or '') end
                table.sort(bits)
                summary = #bits > 0 and table.concat(bits, ', ') or 'nothing found'
            end
            parts[#parts + 1] = ('#%d %s: %s'):format(o.id, o.label, summary)
        end
        H.Notify(source, #parts > 0 and table.concat(parts, ' | ') or 'No orders.', 'primary')
    end)
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if type(citizenid) ~= 'string' or not (PFMed.Schema and PFMed.Schema.Ready()) then return end
    pcall(Q.OrdDeleteCharacter, citizenid)
end)

CreateThread(function()
    L.RegisterCommands()
    while true do
        Wait((cfg().TickSeconds or 15) * 1000)
        if PFMed.Schema and PFMed.Schema.Ready() and A.Ready() then
            local ok, err = pcall(L.Tick, now())
            if not ok then print('^1[pf-ambulancejob]^7 lab tick failed: ' .. tostring(err)) end
        end
    end
end)
