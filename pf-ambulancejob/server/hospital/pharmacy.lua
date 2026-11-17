-- Hospital pharmacy (batch 20A, architecture 4.5, 6.6, 6.7): prescriptions, dispensing at the
-- pharmacy counter and the controlled-substance log.
--
--   * A physician (Config.Hospital.Pharmacy.PrescribeTier) prescribes from the formulary for a
--     patient with an open admission, at the bedside or as discharge orders. One prescription per
--     drug per admission (key pf-ambulancejob:rx:<admissionId>:<drug>), so a retried discharge or a
--     second click never writes two. Prescriptions are billed on that admission's bill (drug lines).
--   * Patients in custody get an infirmary schedule instead (19G rows: custody_ref, one unit per
--     dose), so the prison infirmary hands the doses out.
--   * The patient collects each fill at a pharmacy counter (server position). The fill is reserved
--     in the database first (19G's dose reservation), the log row is written with the per-fill key
--     pf-ambulancejob:rx:<rxId>:<fill> (the format of 19G's dose keys), and only then do the items
--     move from the facility stock stash to the patient; any failure gives the fill back.
--   * Staff withdraw ward drugs for an admitted patient and return what was not used; for a
--     controlled drug (morphine, fentanyl) the log row is written before the items move, so the
--     log never misses a move (a failed move deletes its own row again).
--   * The stock stash is never opened to a player: staff see it read-only and restock it through a
--     logged action; 20C's procurement unpacks deliveries into it on the server.
-- 19G's tables are extended by schema v8 (hospital_id, admission_id, units_per_fill, idem_key; log
-- kind, controlled, hospital_id, admission_id); 19G's infirmary rows keep working unchanged.

PFHospital = PFHospital or {}
local H = PFHospital
H.Pharmacy = H.Pharmacy or {}
local Ph = H.Pharmacy
H.SQL = H.SQL or {}
local Q = H.SQL
local A = H.Admissions

local function cfg() return Config.Hospital.Pharmacy end
local function now() return H.Now() end

-- ── SQL (the real-DB spec runs every statement) ─────────────────────────────────────────────

local RX_COLS = 'id, citizenid, drug, dose, qty, refills, controlled, prescriber_cid, state, created_at, expires_at, dispensed, interval_seconds, '
    .. 'last_dispensed_at, custody_ref, note, hospital_id, admission_id, units_per_fill, cancelled_by, idem_key'

function Q.PhInsertRx(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_prescriptions (citizenid, drug, dose, qty, refills, controlled, prescriber_cid, state, created_at,
        expires_at, dispensed, interval_seconds, custody_ref, note, hospital_id, admission_id, units_per_fill, idem_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)]],
        { r.citizenid, r.drug, r.dose, r.qty, r.refills or 0, r.controlled and 1 or 0, r.prescriber_cid, r.created_at, r.expires_at,
            r.interval_seconds or 0, r.custody_ref, r.note, r.hospital_id, r.admission_id, r.units_per_fill or 1, r.idem_key })
end

function Q.PhFindRxByKey(key)
    return MySQL.single.await('SELECT ' .. RX_COLS .. ' FROM pf_hosp_prescriptions WHERE idem_key = ? LIMIT 1', { key })
end

function Q.PhGetRx(id)
    return MySQL.single.await('SELECT ' .. RX_COLS .. ' FROM pf_hosp_prescriptions WHERE id = ? LIMIT 1', { id })
end

--- Active pharmacy prescriptions of a citizen (the infirmary's rows have no hospital_id).
function Q.PhActiveRx(cid, at)
    return MySQL.query.await('SELECT ' .. RX_COLS .. [[ FROM pf_hosp_prescriptions WHERE citizenid = ? AND state = 'active'
        AND hospital_id IS NOT NULL AND expires_at > ? ORDER BY id LIMIT 20]], { cid, at }) or {}
end

function Q.PhCancelRx(id, by)
    return H.Affected(MySQL.update.await("UPDATE pf_hosp_prescriptions SET state = 'cancelled', cancelled_by = ? WHERE id = ? AND state = 'active'", { by, id }))
end

--- A staff cancel: only a pharmacy prescription (never a 19G infirmary schedule) of that hospital.
function Q.PhCancelPharmacyRx(id, hospitalId, by)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_prescriptions SET state = 'cancelled', cancelled_by = ? WHERE id = ? AND state = 'active'
        AND hospital_id = ?]], { by, id, hospitalId }))
end

--- Prescriptions an admission's bill charges for (cancelled ones are not billed).
function Q.PhAdmissionRx(admissionId)
    return MySQL.query.await([[SELECT id, drug, qty, units_per_fill, state FROM pf_hosp_prescriptions WHERE admission_id = ? AND state <> 'cancelled'
        AND hospital_id IS NOT NULL ORDER BY id LIMIT 50]], { admissionId }) or {}
end

function Q.PhRecordRx(cid, limit)
    return MySQL.query.await('SELECT ' .. RX_COLS .. ' FROM pf_hosp_prescriptions WHERE citizenid = ? ORDER BY id DESC LIMIT ?', { cid, limit }) or {}
end

--- Takes fill n+1 of a prescription, only while `dispensed` is still n (two takers: one wins).
function Q.PhReserveFill(id, dispensed, at)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_prescriptions SET state = CASE WHEN dispensed + 1 >= qty THEN 'filled' ELSE state END,
        dispensed = dispensed + 1, last_dispensed_at = ? WHERE id = ? AND state = 'active' AND dispensed = ?]], { at, id, dispensed }))
end

--- Gives a reserved fill back (the items did not move).
function Q.PhUndoFill(id, dispensedAfter, prevLastAt)
    return H.Affected(MySQL.update.await([[UPDATE pf_hosp_prescriptions SET state = 'active', dispensed = dispensed - 1, last_dispensed_at = ?
        WHERE id = ? AND dispensed = ?]], { prevLastAt, id, dispensedAfter }))
end

--- Removes a log row whose move did not happen (by its own key).
function Q.PhDeleteLog(key)
    return H.Affected(MySQL.update.await('DELETE FROM pf_hosp_dispense_log WHERE idem_key = ?', { key }))
end

function Q.PhInsertLog(r)
    return MySQL.insert.await([[INSERT INTO pf_hosp_dispense_log (prescription_id, citizenid, drug, qty, by_cid, stash, at, dose_no, idem_key, kind,
        controlled, hospital_id, admission_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { r.prescription_id, r.citizenid, r.drug, r.qty, r.by_cid, r.stash, r.at, r.dose_no, r.idem_key, r.kind or 'dispense',
            r.controlled and 1 or 0, r.hospital_id, r.admission_id })
end

function Q.PhControlledLog(hospitalId, since, limit)
    return MySQL.query.await([[SELECT id, prescription_id, citizenid, drug, qty, by_cid, stash, at, kind, admission_id FROM pf_hosp_dispense_log
        WHERE controlled = 1 AND hospital_id = ? AND at >= ? ORDER BY id DESC LIMIT ?]], { hospitalId, since, limit }) or {}
end

--- Active, unexpired prescriptions waiting at one facility (newest first, paged). A public
--- hospital's counter sees its own pharmacy rows only; the prison infirmary (custody) sees the 19G
--- dose schedules (custody_ref) and nothing else. cids (optional) narrows to those patients.
function Q.PhCounterQueue(fid, custody, at, cids, limit, offset)
    local params, where = {}, nil
    if custody then
        where = "custody_ref IS NOT NULL AND custody_ref <> ''"
    else
        where = "hospital_id = ? AND (custody_ref IS NULL OR custody_ref = '')"
        params[1] = fid
    end
    params[#params + 1] = at
    local cidSql = ''
    if cids then
        local marks = {}
        for i, cid in ipairs(cids) do marks[i] = '?' params[#params + 1] = cid end
        cidSql = ' AND citizenid IN (' .. table.concat(marks, ', ') .. ')'
    end
    params[#params + 1], params[#params + 2] = limit, offset
    return MySQL.query.await('SELECT ' .. RX_COLS .. ' FROM pf_hosp_prescriptions WHERE ' .. where .. " AND state = 'active' AND expires_at > ?"
        .. cidSql .. ' ORDER BY id DESC LIMIT ? OFFSET ?', params) or {}
end

function Q.PhDeleteCharacterRx(cid)
    return MySQL.update.await("DELETE FROM pf_hosp_prescriptions WHERE citizenid = ? AND state <> 'filled'", { cid })
end

-- ── helpers ─────────────────────────────────────────────────────────────────────────────────

local function inventory(name, ...)
    local args = table.pack(...)
    local ok, res = pcall(function()
        local e = exports['pfm-inventory']
        return e[name](e, table.unpack(args, 1, args.n))
    end)
    return ok and res or nil
end
Ph.Inventory = inventory

--- The facility whose pharmacy counter the player stands at (server position), or nil.
function Ph.CounterOf(src)
    local pos = H.Pos(src)
    if not pos then return nil end
    for fid, c in pairs(cfg().Counters or {}) do
        if H.Dist(pos, c.coords) <= (tonumber(c.radius) or 3.0) then return fid, c end
    end
    return nil
end

local function notifyStaff(fid, text)
    local ok, list = pcall(function() return PFAmbulance.GetCore().Functions.GetQBPlayers() end)
    if not ok or type(list) ~= 'table' then return end
    for _, P in pairs(list) do
        if H.IsStaff(P) and H.Facility.Of(P.PlayerData.source) == fid then H.Notify(P.PlayerData.source, text, 'ambulance') end
    end
end

--- Whether a citizen is a custody patient who gets doses from the infirmary (19G).
local function custodyRef(cid)
    local C = H.Custody
    if not C or not H.Callable(C.CustodyStatus) then return nil end
    local ok, status = pcall(C.CustodyStatus, cid)
    if ok and type(status) == 'table' and (status.orderId or status.legacy) then return C.RefOf(status) end
    return nil
end

--- Validates one prescription line { drug, units, fills, note }. Returns clean | nil, message.
function Ph.CleanLine(line)
    if type(line) ~= 'table' then return nil, 'Invalid prescription.' end
    local entry = type(line.drug) == 'string' and cfg().Formulary[line.drug]
    if not entry then return nil, 'That is not on the formulary.' end
    local units = H.Int(line.units or 1, 1, entry.maxUnits)
    if not units then return nil, ('%s: 1-%d per fill.'):format(entry.label, entry.maxUnits) end
    local fills = H.Int(line.fills or 1, 1, entry.maxFills)
    if not fills then return nil, ('%s: 1-%d fills.'):format(entry.label, entry.maxFills) end
    return { drug = line.drug, units = units, fills = fills, note = H.Text(line.note, 255) }
end

function Ph.Key(admissionId, drug) return ('pf-ambulancejob:rx:%d:%s'):format(admissionId, drug) end

--- Writes one prescription for admission `a` by prescriber cid (caller holds the citizen lock).
--- Returns { ok, prescriptionId, duplicate? } | fail.
function Ph.Write(a, line, prescriberCid)
    local entry = cfg().Formulary[line.drug]
    local key = Ph.Key(a.id, line.drug)
    local okF, found = pcall(Q.PhFindRxByKey, key)
    if not okF then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
    if found then return { ok = true, duplicate = true, prescriptionId = tonumber(found.id) } end
    local t = now()
    local row = { citizenid = a.citizenid, drug = line.drug, dose = entry.dose:sub(1, 32), controlled = entry.controlled == true,
        prescriber_cid = prescriberCid, created_at = t, expires_at = t + (cfg().RxValidDays or 14) * 86400, note = line.note, idem_key = key,
        admission_id = a.id }
    local ref = custodyRef(a.citizenid)
    if ref then
        -- the infirmary hands out custody doses one unit at a time (19G's schedule)
        row.custody_ref, row.qty, row.units_per_fill = ref, line.units * line.fills, 1
        row.interval_seconds = math.max(3600, math.floor((entry.refillHours or 24) * 3600 / math.max(1, line.units)))
    else
        row.hospital_id, row.qty, row.units_per_fill, row.refills = a.hospital_id, line.fills, line.units, line.fills - 1
        row.interval_seconds = (entry.refillHours or 0) * 3600
    end
    local ok, id = pcall(Q.PhInsertRx, row)
    id = ok and tonumber(id) or nil
    if not id then
        -- a concurrent writer of the same key won: answer with its row
        local okAgain, again = pcall(Q.PhFindRxByKey, key)
        if okAgain and again then return { ok = true, duplicate = true, prescriptionId = tonumber(again.id) } end
        return H.Fail('db_unavailable', 'Pharmacy records are unavailable.')
    end
    H.Audit(a.citizenid, 'prescription', { kind = 'player', cid = prescriberCid }, { rx = id, drug = line.drug, units = line.units, fills = line.fills,
        admission = a.id, custody = ref ~= nil or nil })
    return { ok = true, prescriptionId = id, custody = ref ~= nil }
end

-- ── prescribe (callback rxPrescribe) ─────────────────────────────────────────────────────────

function Ph.Prescribe(src, target, drug, units, fills, note)
    if H.Limited(src, 'rx_write', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local line, why = Ph.CleanLine({ drug = drug, units = units, fills = fills, note = note })
    if not line then return H.Fail('bad_args', why) end
    local P, tierOrErr, msg = H.Provider(src, nil, cfg().PrescribeTier)
    if not P then return H.Fail(tierOrErr, msg) end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T or target == src then return H.Fail('offline', 'Patient not found.') end
    local cid = T.PlayerData.citizenid
    local a = A.OpenOf(cid)
    if not a then return H.Fail('invalid_state', 'The patient needs an open admission (check-in or triage) first.') end
    if not H.Facility.InFacility(src, a.hospital_id) then return H.Fail('too_far', 'You must be in the patient\'s hospital.') end
    if H.Dist(H.Pos(src), H.Pos(target)) > Config.Hospital.Roles.TouchDistance * 2 then return H.Fail('too_far', 'See the patient first.') end
    local res, err = H.WithLock('cid:' .. cid, function()
        local cur = A.OpenOf(cid)
        if not cur or cur.id ~= a.id then return H.Fail('invalid_state', 'The admission changed; try again.') end
        return Ph.Write(cur, line, P.PlayerData.citizenid)
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    if res.ok and not res.duplicate then
        H.Notify(target, res.custody and 'A prescription was written: the infirmary hands out your doses.'
            or 'A prescription was written: collect it at the pharmacy counter.', 'success')
    end
    return res
end

--- A physician inside the prescription's own hospital cancels a pharmacy prescription. Infirmary
--- dose schedules (19G, no hospital_id) are cancelled through the infirmary, never here.
function Ph.Cancel(src, rxId)
    rxId = H.Int(rxId, 1)
    if not rxId then return H.Fail('bad_args', 'Invalid prescription.') end
    local okG, row = pcall(Q.PhGetRx, rxId)
    if not okG then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
    if not row or type(row.hospital_id) ~= 'string' or row.hospital_id == '' then return H.Fail('not_found', 'No such pharmacy prescription.') end
    local P, tierOrErr, msg = H.Provider(src, row.hospital_id, cfg().PrescribeTier)
    if not P then return H.Fail(tierOrErr, msg) end
    local ok, n = pcall(Q.PhCancelPharmacyRx, rxId, row.hospital_id, P.PlayerData.citizenid)
    if not ok then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
    if n ~= 1 then return H.Fail('invalid_state', 'That prescription is not active.') end
    return { ok = true }
end

-- ── discharge orders with prescriptions (wraps 17E's admissions; looked up at call time) ──────

local cleanOrders = A.CleanOrders
--- Discharge orders may carry prescriptions = { { drug, units, fills, note } } now.
A.CleanOrders = function(orders)
    local list = type(orders) == 'table' and orders.prescriptions or nil
    if list == nil or (type(list) == 'table' and next(list) == nil) then
        if type(orders) == 'table' and orders.prescriptions ~= nil then
            local copy = {}
            for k, v in pairs(orders) do copy[k] = v end
            copy.prescriptions = nil
            orders = copy
        end
        return cleanOrders(orders)
    end
    if type(list) ~= 'table' then return nil, 'Invalid prescriptions.' end
    if #list > 8 then return nil, 'At most 8 prescriptions.' end
    local clean, seen = {}, {}
    for _, line in ipairs(list) do
        local c, why = Ph.CleanLine(line)
        if not c then return nil, why end
        if seen[c.drug] then return nil, 'One prescription per drug.' end
        seen[c.drug] = true
        clean[#clean + 1] = c
    end
    local copy = {}
    for k, v in pairs(orders) do copy[k] = v end
    copy.prescriptions = nil
    local out, why = cleanOrders(copy)
    if not out then return nil, why end
    out.prescriptions = clean
    return out
end

local function hasRx(orders)
    return type(orders) == 'table' and type(orders.prescriptions) == 'table' and next(orders.prescriptions) ~= nil
end

local discharge = A.Discharge
--- Prescriptions in discharge orders need a prescriber (the discharge itself needs a nurse).
A.Discharge = function(src, admissionId, orders)
    if hasRx(orders) then
        local P, tierOrErr, msg = H.Provider(src, nil, cfg().PrescribeTier)
        if not P then return H.Fail(tierOrErr, tierOrErr == 'no_permission' and 'Prescriptions need a physician.' or msg) end
    end
    return discharge(src, admissionId, orders)
end

local exportDischarge = A.ExportDischargePatient
A.ExportDischargePatient = function(admissionId, opts)
    if type(opts) == 'table' and hasRx(opts.orders) then
        local src = type(opts.actor) == 'table' and H.Int(opts.actor.src, 1) or nil
        local P = src and H.Provider(src, nil, cfg().PrescribeTier)
        if not P then return H.Fail('no_permission', 'Prescriptions need a physician as the actor.') end
    end
    return exportDischarge(admissionId, opts)
end

local close = A.Close
--- A discharge with prescriptions writes them BEFORE the admission closes, so the one bill that
--- the close makes includes them; when the close fails they are cancelled again.
A.Close = function(a, to, ctx)
    local orders = ctx and ctx.orders
    local written = {}
    if to == 'discharged' and hasRx(orders) and type(ctx.actor) == 'table' and type(ctx.actor.cid) == 'string' then
        for _, line in ipairs(orders.prescriptions) do
            local res = Ph.Write(a, line, ctx.actor.cid)
            if res.ok and not res.duplicate then written[#written + 1] = res.prescriptionId end
        end
    end
    local done, err = close(a, to, ctx)
    if not done then
        for _, id in ipairs(written) do pcall(Q.PhCancelRx, id, 'discharge_failed') end
        return nil, err
    end
    if #written > 0 then
        local src = H.SourceOfCid(a.citizenid)
        H.Notify(src, ('%d prescription(s) waiting at the pharmacy counter.'):format(#written), 'success')
    end
    return done, err
end

-- ── collect a fill at the counter (callback pharmacyCollect) ─────────────────────────────────

function Ph.Collect(src)
    if H.Limited(src, 'rx_collect', 3) then return H.Fail('rate_limited', 'Slow down.') end
    local P = H.Player(src)
    if not P then return H.Fail('offline', 'You are not loaded.') end
    local fid, counter = Ph.CounterOf(src)
    local stash = fid and cfg().Stashes[fid]
    if not fid or not stash then return H.Fail('too_far', 'Collect prescriptions at a pharmacy counter.') end
    local cid = P.PlayerData.citizenid
    -- the same lock as the infirmary doses: one dispense per citizen at a time
    local res, err = H.WithLock('rx:' .. cid, function()
        local at = now()
        local ok, rows = pcall(Q.PhActiveRx, cid, at)
        if not ok then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
        if #rows == 0 then return H.Fail('not_found', 'You have no prescription to collect.') end
        local due, wait
        for _, r in ipairs(rows) do
            local last, every = tonumber(r.last_dispensed_at), tonumber(r.interval_seconds) or 0
            if (tonumber(r.dispensed) or 0) < (tonumber(r.qty) or 0) then
                if not last or at >= last + every then due = due or r
                else wait = math.min(wait or math.huge, last + every - at) end
            end
        end
        if not due then
            return { ok = false, error = 'too_soon', remaining = wait, message = ('Your next fill is ready in %d min.'):format(math.ceil((wait or 0) / 60)) }
        end
        local id, dispensed, prevLast = tonumber(due.id), tonumber(due.dispensed) or 0, tonumber(due.last_dispensed_at)
        local units = math.max(1, tonumber(due.units_per_fill) or 1)
        local fillNo = dispensed + 1
        local key = ('pf-ambulancejob:rx:%d:%d'):format(id, fillNo)
        local okR, n = pcall(Q.PhReserveFill, id, dispensed, at)
        if not okR then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
        if n ~= 1 then return H.Fail('busy', 'Try again.') end
        local okL, logId = pcall(Q.PhInsertLog, { prescription_id = id, citizenid = cid, drug = due.drug, qty = units, by_cid = 'pharmacy:' .. fid,
            stash = stash.id, at = at, dose_no = fillNo, idem_key = key, kind = 'dispense', controlled = tonumber(due.controlled) == 1,
            hospital_id = fid, admission_id = tonumber(due.admission_id) })
        local function undo()
            pcall(Q.PhUndoFill, id, fillNo, prevLast)
            pcall(Q.PhDeleteLog, key)
        end
        if not okL or not logId then undo() return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
        local label = (cfg().Formulary[due.drug] or {}).label or due.drug
        if inventory('RemoveItem', stash.id, due.drug, units, nil, 'pharmacy fill ' .. key) ~= true then
            undo()
            notifyStaff(fid, ('%s is out of %s.'):format(counter.label or fid, label))
            return H.Fail('conflict', 'The pharmacy is out of stock; staff were told.')
        end
        if inventory('AddItem', src, due.drug, units, nil, nil, 'pharmacy fill ' .. key) ~= true then
            inventory('AddItem', stash.id, due.drug, units, nil, nil, 'pharmacy fill returned ' .. key)
            undo()
            return H.Fail('conflict', 'You cannot carry it.')
        end
        H.Audit(cid, 'dispense', { kind = 'system', label = 'pharmacy' }, { rx = id, fill = fillNo, drug = due.drug, units = units, hospital = fid })
        return { ok = true, item = due.drug, label = label, units = units, prescriptionId = id, fillNo = fillNo,
            fillsLeft = math.max(0, (tonumber(due.qty) or 0) - fillNo) }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

-- ── ward drugs: withdraw for an admitted patient, return unused (staff at the counter) ────────

local seq = 0
local function moveKey(kind, cid, at)
    seq = (seq % 100000) + 1
    return ('pf-ambulancejob:rx%s:%s:%d:%d'):format(kind, cid, at, seq)
end

function Ph.Withdraw(src, drug, qty, target)
    if H.Limited(src, 'rx_ward', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local entry = type(drug) == 'string' and cfg().Ward[drug]
    if not entry then return H.Fail('bad_args', 'That is not a ward drug.') end
    qty = H.Int(qty, 1, entry.max)
    if not qty then return H.Fail('bad_args', ('%s: 1-%d.'):format(entry.label, entry.max)) end
    local fid = Ph.CounterOf(src)
    local stash = fid and cfg().Stashes[fid]
    if not stash then return H.Fail('too_far', 'Draw ward drugs at the pharmacy counter.') end
    local P, tierOrErr, msg = H.Provider(src, fid, entry.tier)
    if not P then return H.Fail(tierOrErr, msg) end
    target = H.Int(target, 1)
    local T = target and H.Player(target)
    if not T then return H.Fail('offline', 'Name the patient it is for.') end
    local a = A.OpenOf(T.PlayerData.citizenid)
    if not a or a.hospital_id ~= fid then return H.Fail('invalid_state', 'The patient is not admitted here.') end
    local staffCid = P.PlayerData.citizenid
    local res, err = H.WithLock('rxw:' .. staffCid, function()
        local at = now()
        local key = moveKey('w', staffCid, at)
        -- the log row first: a controlled move is never unlogged
        local okL, logId = pcall(Q.PhInsertLog, { citizenid = a.citizenid, drug = drug, qty = qty, by_cid = staffCid, stash = stash.id, at = at,
            idem_key = key, kind = 'withdraw', controlled = entry.controlled == true, hospital_id = fid, admission_id = a.id })
        if not okL or not logId then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
        if inventory('RemoveItem', stash.id, drug, qty, nil, 'ward withdrawal ' .. key) ~= true then
            pcall(Q.PhDeleteLog, key)
            return H.Fail('conflict', 'Not enough stock.')
        end
        if inventory('AddItem', src, drug, qty, nil, nil, 'ward withdrawal ' .. key) ~= true then
            inventory('AddItem', stash.id, drug, qty, nil, nil, 'ward withdrawal returned ' .. key)
            pcall(Q.PhDeleteLog, key)
            return H.Fail('conflict', 'You cannot carry it.')
        end
        H.Audit(a.citizenid, 'ward_drug', H.ActorOf(src, P), { drug = drug, qty = qty, kind = 'withdraw', log = tonumber(logId), controlled = entry.controlled or nil })
        return { ok = true, logId = tonumber(logId), drug = drug, qty = qty }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

function Ph.Return(src, drug, qty)
    if H.Limited(src, 'rx_ward', 1) then return H.Fail('rate_limited', 'Slow down.') end
    local entry = type(drug) == 'string' and cfg().Ward[drug]
    if not entry then return H.Fail('bad_args', 'That is not a ward drug.') end
    qty = H.Int(qty, 1, 20)
    if not qty then return H.Fail('bad_args', 'Quantity 1-20.') end
    local fid = Ph.CounterOf(src)
    local stash = fid and cfg().Stashes[fid]
    if not stash then return H.Fail('too_far', 'Return ward drugs at the pharmacy counter.') end
    local P, tierOrErr, msg = H.Provider(src, fid, 1)
    if not P then return H.Fail(tierOrErr, msg) end
    local staffCid = P.PlayerData.citizenid
    local res, err = H.WithLock('rxw:' .. staffCid, function()
        local at = now()
        local key = moveKey('r', staffCid, at)
        local okL, logId = pcall(Q.PhInsertLog, { citizenid = staffCid, drug = drug, qty = qty, by_cid = staffCid, stash = stash.id, at = at,
            idem_key = key, kind = 'return', controlled = entry.controlled == true, hospital_id = fid })
        if not okL or not logId then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
        if inventory('RemoveItem', src, drug, qty, nil, 'ward return ' .. key) ~= true then
            pcall(Q.PhDeleteLog, key)
            return H.Fail('conflict', 'You do not carry that much.')
        end
        inventory('AddItem', stash.id, drug, qty, nil, nil, 'ward return ' .. key)
        return { ok = true, logId = tonumber(logId), drug = drug, qty = qty }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

-- ── reads ─────────────────────────────────────────────────────────────────────────────────────

local function logView(r)
    return { id = tonumber(r.id), prescriptionId = tonumber(r.prescription_id), citizenid = r.citizenid, drug = r.drug, qty = tonumber(r.qty),
        byCid = r.by_cid, kind = r.kind, admissionId = tonumber(r.admission_id), at = tonumber(r.at) }
end

--- The controlled-substance log of a facility (the last LogRows rows, newest first).
function Ph.ControlledLog(fid, since)
    local ok, rows = pcall(Q.PhControlledLog, fid, since or 0, cfg().LogRows or 50)
    if not ok then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = logView(r) end
    return { ok = true, hospitalId = fid, list = list }
end

function Ph.LogFor(src)
    local fid = H.Facility.Of(src)
    if not fid then return H.Fail('too_far', 'You must be in a hospital.') end
    local P, tierOrErr, msg = H.Provider(src, fid, cfg().LogTier)
    if not P then return H.Fail(tierOrErr, msg) end
    H.Audit(P.PlayerData.citizenid, 'controlled_log_read', H.ActorOf(src, P), { hospital = fid })
    return Ph.ControlledLog(fid)
end

function Ph.RxView(r)
    local entry = cfg().Formulary[r.drug] or (Config.Hospital.Custody.Formulary or {})[r.drug] or {}
    local last, every = tonumber(r.last_dispensed_at), tonumber(r.interval_seconds) or 0
    return { id = tonumber(r.id), drug = r.drug, label = entry.label or r.drug, dose = r.dose, state = r.state,
        units = tonumber(r.units_per_fill) or 1, fills = tonumber(r.qty), filled = tonumber(r.dispensed) or 0,
        controlled = tonumber(r.controlled) == 1, prescriber = r.prescriber_cid, hospitalId = r.hospital_id, admissionId = tonumber(r.admission_id),
        infirmary = r.custody_ref ~= nil and r.custody_ref ~= '' or nil, createdAt = tonumber(r.created_at), expiresAt = tonumber(r.expires_at),
        nextAt = last and (last + every) or nil }
end

function Ph.Record(cid, limit)
    local ok, rows = pcall(Q.PhRecordRx, cid, limit or 50)
    if not ok then return nil end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = Ph.RxView(r) end
    return list
end

--- The patient's own prescriptions (to know what is waiting at the counter).
function Ph.Mine(src)
    local P = H.Player(src)
    if not P then return H.Fail('offline', 'You are not loaded.') end
    local ok, rows = pcall(Q.PhActiveRx, P.PlayerData.citizenid, now())
    if not ok then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = Ph.RxView(r) end
    return { ok = true, list = list }
end

-- GetMedicalRecord (17A) lists prescriptions now: the export looks Dx.GetMedicalRecord up at call time.
if PFMed and PFMed.Diagnosis and PFMed.Diagnosis.GetMedicalRecord then
    local getRecord = PFMed.Diagnosis.GetMedicalRecord
    PFMed.Diagnosis.GetMedicalRecord = function(cid, opts)
        local res = getRecord(cid, opts)
        if type(res) == 'table' and res.ok and type(res.record) == 'table' then
            res.record.prescriptions = Ph.Record(cid, 50) or {}
        end
        return res
    end
end

-- ── billing: drug lines for the prescriptions of an admission ─────────────────────────────────

--- AI care is billed at the AI rate (17E); every 20A line follows the same rule.
function H.ServiceMultiplier(a)
    return a and a.mode == 'ai' and (Config.Hospital.AI.PriceMultiplier or 1.5) or 1
end

if H.Billing and H.Billing.Lines then
    local lines = H.Billing.Lines
    H.Billing.Lines = function(a)
        local out, err = lines(a)
        if not out then return out, err end
        local ok, rows = pcall(Q.PhAdmissionRx, a.id)
        if not ok then return nil, 'db_unavailable' end
        local mult = H.ServiceMultiplier(a)
        for _, r in ipairs(rows) do
            local entry = cfg().Formulary[r.drug]
            local units = (tonumber(r.qty) or 1) * (tonumber(r.units_per_fill) or 1)
            local price = entry and math.floor((tonumber(entry.price) or 0) * mult + 0.5) or 0
            if price > 0 then
                out[#out + 1] = { kind = 'drug', ref_id = tonumber(r.id), label = ('Prescription: %s'):format(entry.label):sub(1, 96), qty = units, unit_price = price }
            end
        end
        return out
    end
end

-- ── exports (read; Config.Hospital.Services.Callers) ──────────────────────────────────────────

local refusedLog = {}
function H.ServiceAllowed(name)
    local inv = GetInvokingResource()
    if inv == nil or inv == GetCurrentResourceName() then return true, nil end
    local list = Config.Hospital.Services.Callers[name]
    if list == '*' or (type(list) == 'table' and list[inv] == true) then return true, inv end
    local t = os.time()
    if (refusedLog[inv] or 0) + 60 <= t then
        refusedLog[inv] = t
        print(('^3[pf-ambulancejob]^7 %s refused for resource %s (not in Config.Hospital.Services.Callers)'):format(name, tostring(inv)))
    end
    return false, inv
end

exports('ListPrescriptions', function(who)
    if not H.ServiceAllowed('ListPrescriptions') then return H.Fail('not_allowed', 'Not allowed.') end
    local cid = PFMed and PFMed.Api and PFMed.Api.Resolve and PFMed.Api.Resolve(who) or (type(who) == 'string' and who or nil)
    if type(cid) ~= 'string' then return H.Fail('bad_args', 'Unknown patient.') end
    local list = Ph.Record(cid, 50)
    if not list then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
    return { ok = true, list = list }
end)

exports('GetControlledLog', function(hospitalId, opts)
    if not H.ServiceAllowed('GetControlledLog') then return H.Fail('not_allowed', 'Not allowed.') end
    local fid = H.Facility.Id(hospitalId)
    if not fid then return H.Fail('bad_args', 'Unknown hospital.') end
    local since = type(opts) == 'table' and H.Int(opts.since, 0) or 0
    return Ph.ControlledLog(fid, since)
end)

-- The hospital workstation (pf-emsmdt, batch 21D) lists the counter queue through this export.
Config.Hospital.Services.Callers.ListPharmacyQueue = Config.Hospital.Services.Callers.ListPharmacyQueue or { ['pf-emsmdt'] = true }

--- The counter queue for a staff member, under the pharmacy's own rules: on duty, at least
--- LogTier (the tier that reads the controlled-substance log and the stock), standing inside the
--- facility whose queue it is (the infirmary's dose schedules only inside the infirmary). Every
--- controlled prescription shown is an audit row on that patient's record.
--- filter = { cids = { citizenid, ... } (at most 50; narrows the list), limit (1-51), offset }.
function Ph.CounterQueue(src, filter)
    src = H.Int(src, 1)
    if not src then return H.Fail('bad_args', 'Invalid player.') end
    local fid = H.Facility.Of(src)
    if not fid then return H.Fail('too_far', 'You must be in a hospital.') end
    local P, tierOrErr, msg = H.Provider(src, fid, cfg().LogTier)
    if not P then return H.Fail(tierOrErr, msg) end
    filter = type(filter) == 'table' and filter or {}
    local cids = nil
    if filter.cids ~= nil then
        if type(filter.cids) ~= 'table' or #filter.cids > 50 then return H.Fail('bad_args', 'At most 50 patients.') end
        cids = {}
        for _, cid in ipairs(filter.cids) do
            if type(cid) == 'string' and #cid >= 1 and #cid <= 64 and not cid:find('[^%w_%-]') then cids[#cids + 1] = cid end
        end
        if #cids == 0 then return { ok = true, hospitalId = fid, infirmary = H.Facility.Get(fid).custody == true, list = {} } end
    end
    local limit = H.Int(filter.limit, 1, 51) or 26
    local offset = H.Int(filter.offset, 0, 100000) or 0
    local custody = H.Facility.Get(fid).custody == true
    local ok, rows = pcall(Q.PhCounterQueue, fid, custody, now(), cids, limit, offset)
    if not ok then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
    local actor = H.ActorOf(src, P)
    local list = {}
    for _, r in ipairs(rows) do
        local v = Ph.RxView(r)
        v.citizenid = r.citizenid
        list[#list + 1] = v
        if v.controlled then H.Audit(r.citizenid, 'rx_queue_read', actor, { rx = v.id, hospital = fid }) end
    end
    return { ok = true, hospitalId = fid, label = H.Facility.Label(fid), infirmary = custody, list = list }
end

exports('ListPharmacyQueue', function(src, filter)
    if not H.ServiceAllowed('ListPharmacyQueue') then return H.Fail('not_allowed', 'Not allowed.') end
    return Ph.CounterQueue(src, filter)
end)

-- ── callbacks and staff commands (the hospital workstation app comes in batch 21) ─────────────

local function callback(name, fn)
    PFAmbulance.GetCore().Functions.CreateCallback('pf-ambulancejob:server:' .. name, function(source, cb, ...)
        local src = tonumber(source)
        if not src or src <= 0 then return cb(H.Fail('bad_args', 'Invalid source.')) end
        if not (PFMed.Schema and PFMed.Schema.Ready()) then return cb(H.Fail('db_unavailable', 'Not ready yet.')) end
        local ok, res = pcall(fn, src, ...)
        if not ok then
            print(('^1[pf-ambulancejob]^7 %s failed: %s'):format(name, tostring(res)))
            res = H.Fail('db_unavailable', 'Something went wrong.')
        end
        cb(res)
    end)
end
H.ServiceCallback = callback

callback('rxPrescribe', function(src, target, drug, units, fills, note) return Ph.Prescribe(src, target, drug, units, fills, note) end)
callback('rxCancel', function(src, rxId) return Ph.Cancel(src, rxId) end)
callback('rxMine', function(src) return Ph.Mine(src) end)
callback('pharmacyCollect', function(src) return Ph.Collect(src) end)
callback('pharmacyWithdraw', function(src, drug, qty, target) return Ph.Withdraw(src, drug, qty, target) end)
callback('pharmacyReturn', function(src, drug, qty) return Ph.Return(src, drug, qty) end)
callback('pharmacyLog', function(src) return Ph.LogFor(src) end)
callback('pharmacyStock', function(src) return Ph.Stock(src) end)
callback('pharmacyRestock', function(src, item, qty) return Ph.Restock(src, item, qty) end)

-- The pharmacy stock stash is never opened to a player: controlled drugs could leave it without a
-- log row. Items leave only through Collect (patients) and Withdraw (staff), and enter only through
-- Return, Restock (both logged first) and the procurement unpack (20C, server side).

local function stockItems()
    local out = {}
    for name in pairs(cfg().Formulary or {}) do out[name] = true end
    for name in pairs(cfg().Ward or {}) do out[name] = true end
    return out
end

--- Read-only stock of the counter's stash for staff (LogTier): { ok, hospitalId, list = { { item, label, amount, controlled } } }.
function Ph.Stock(src)
    local fid = Ph.CounterOf(src)
    local stash = fid and cfg().Stashes[fid]
    if not stash then return H.Fail('too_far', 'Go to the pharmacy counter.') end
    local P, tierOrErr, msg = H.Provider(src, fid, cfg().LogTier)
    if not P then return H.Fail(tierOrErr, msg) end
    local inv = inventory('GetInventory', stash.id)
    local counts = {}
    for _, it in pairs(type(inv) == 'table' and type(inv.items) == 'table' and inv.items or {}) do
        if type(it) == 'table' and type(it.name) == 'string' then counts[it.name] = (counts[it.name] or 0) + (tonumber(it.amount) or 0) end
    end
    local list = {}
    for name in pairs(stockItems()) do
        local entry = cfg().Ward[name] or cfg().Formulary[name]
        list[#list + 1] = { item = name, label = entry.label or name, amount = counts[name] or 0, controlled = (cfg().Ward[name] or {}).controlled == true }
    end
    table.sort(list, function(a, b) return a.item < b.item end)
    return { ok = true, hospitalId = fid, list = list }
end

--- Staff put stock they carry into the counter's stash (any formulary or ward item); the log row is
--- written first (controlled items are in the controlled-substance log), a failed move removes it.
function Ph.Restock(src, item, qty)
    if H.Limited(src, 'rx_ward', 1) then return H.Fail('rate_limited', 'Slow down.') end
    if type(item) ~= 'string' or not stockItems()[item] then return H.Fail('bad_args', 'The pharmacy does not stock that.') end
    qty = H.Int(qty, 1, 50)
    if not qty then return H.Fail('bad_args', 'Quantity 1-50.') end
    local fid = Ph.CounterOf(src)
    local stash = fid and cfg().Stashes[fid]
    if not stash then return H.Fail('too_far', 'Restock at the pharmacy counter.') end
    local P, tierOrErr, msg = H.Provider(src, fid, cfg().LogTier)
    if not P then return H.Fail(tierOrErr, msg) end
    local staffCid = P.PlayerData.citizenid
    local controlled = (cfg().Ward[item] or {}).controlled == true
    local res, err = H.WithLock('rxw:' .. staffCid, function()
        local at = now()
        local key = moveKey('s', staffCid, at)
        local okL, logId = pcall(Q.PhInsertLog, { citizenid = staffCid, drug = item, qty = qty, by_cid = staffCid, stash = stash.id, at = at,
            idem_key = key, kind = 'restock', controlled = controlled, hospital_id = fid })
        if not okL or not logId then return H.Fail('db_unavailable', 'Pharmacy records are unavailable.') end
        if inventory('RemoveItem', src, item, qty, nil, 'pharmacy restock ' .. key) ~= true then
            pcall(Q.PhDeleteLog, key)
            return H.Fail('conflict', 'You do not carry that much.')
        end
        if inventory('AddItem', stash.id, item, qty, nil, nil, 'pharmacy restock ' .. key) ~= true then
            inventory('AddItem', src, item, qty, nil, nil, 'pharmacy restock returned ' .. key)
            pcall(Q.PhDeleteLog, key)
            return H.Fail('conflict', 'The stock is full.')
        end
        return { ok = true, logId = tonumber(logId), item = item, qty = qty }
    end)
    if res == nil then return H.Fail(err or 'busy', 'Try again.') end
    return res
end

local function reply(src, res, okText)
    if res and res.ok then H.Notify(src, okText, 'success') else H.Notify(src, (res and res.message) or 'Refused.', 'error') end
end

function Ph.RegisterCommands()
    local QB = PFAmbulance.GetCore()
    if not QB.Commands or not QB.Commands.Add then return end
    local add = QB.Commands.Add
    add('hprescribe', 'Hospital: prescribe (painkillers, antibiotics, bandage, crutches)', { { name = 'id', help = 'Player id' }, { name = 'drug', help = 'Drug' },
        { name = 'units', help = 'Units per fill' }, { name = 'fills', help = 'Fills (optional)' } }, true, function(source, args)
        reply(source, Ph.Prescribe(source, args[1], tostring(args[2] or ''):lower(), args[3], args[4] or 1), 'Prescription written.')
    end)
    add('hrxcancel', 'Hospital: cancel a prescription', { { name = 'rx', help = 'Prescription number' } }, true, function(source, args)
        reply(source, Ph.Cancel(source, args[1]), 'Prescription cancelled.')
    end)
    add('pharmacy', 'Collect your prescription at a pharmacy counter', {}, false, function(source)
        local res = Ph.Collect(source)
        reply(source, res, res.ok and ('Collected %dx %s.'):format(res.units, res.label) or '')
    end)
    add('hwithdraw', 'Hospital: draw a ward drug for a patient', { { name = 'drug', help = 'morphine, fentanyl, naloxone, txa, antibiotics' },
        { name = 'qty', help = 'Quantity' }, { name = 'id', help = 'Patient id' } }, true, function(source, args)
        reply(source, Ph.Withdraw(source, tostring(args[1] or ''):lower(), args[2], args[3]), 'Logged and handed out.')
    end)
    add('hreturn', 'Hospital: return an unused ward drug', { { name = 'drug', help = 'Drug' }, { name = 'qty', help = 'Quantity' } }, true, function(source, args)
        reply(source, Ph.Return(source, tostring(args[1] or ''):lower(), args[2]), 'Returned and logged.')
    end)
    add('hrxlog', 'Hospital: controlled-substance log here (last entries)', {}, false, function(source)
        local res = Ph.LogFor(source)
        if not res.ok then return H.Notify(source, res.message or 'Refused.', 'error') end
        local parts = {}
        for i = 1, math.min(5, #res.list) do
            local r = res.list[i]
            parts[#parts + 1] = ('#%d %s %s x%d by %s'):format(r.id, r.kind, r.drug, r.qty, tostring(r.byCid))
        end
        H.Notify(source, #parts > 0 and table.concat(parts, '; ') or 'No controlled moves recorded.', 'primary')
    end)
    add('hstock', 'Hospital: pharmacy stock here (read only)', {}, false, function(source)
        local res = Ph.Stock(source)
        if not res.ok then return H.Notify(source, res.message or 'Refused.', 'error') end
        local parts = {}
        for _, r in ipairs(res.list) do parts[#parts + 1] = ('%s %d'):format(r.label, r.amount) end
        H.Notify(source, table.concat(parts, ', '), 'primary')
    end)
    add('hrestock', 'Hospital: put stock you carry into the pharmacy (logged)', { { name = 'item', help = 'Item' }, { name = 'qty', help = 'Quantity' } }, true, function(source, args)
        reply(source, Ph.Restock(source, tostring(args[1] or ''):lower(), args[2]), 'Restocked and logged.')
    end)
end

-- ── lifecycle ─────────────────────────────────────────────────────────────────────────────────

function Ph.Start()
    for _, s in pairs(cfg().Stashes or {}) do
        inventory('CreateInventory', s.id, { label = s.label, maxweight = s.maxweight, slots = s.slots })
    end
    return true
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if type(citizenid) ~= 'string' or not (PFMed.Schema and PFMed.Schema.Ready()) then return end
    -- the dispense log is the controlled-substance audit trail and is kept
    pcall(Q.PhDeleteCharacterRx, citizenid)
end)

CreateThread(function()
    Ph.RegisterCommands()
    if PFMed and PFMed.Schema and PFMed.Schema.OnReady then
        PFMed.Schema.OnReady(function() Ph.Start() end)
    end
end)
