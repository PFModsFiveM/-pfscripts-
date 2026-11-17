-- Hospital workstation (batch 21D): the server side of the pf-devices app 'hospital'
-- (html/apps/hospital.js) on the tablet and the computer. Reception queue, triage board, bed board,
-- admissions, discharge orders, lab / imaging / pharmacy queues and bills.
--
-- Every handler re-reads the player on the server (on-duty hospital staff; bills: supervisors) and
-- then goes to pf-ambulancejob, which owns the hospital and checks everything again:
--   * reads through its exports (ListAdmissions, GetHospitalStatus, ListHospitalOrders,
--     IsInCustodyCare; Config.Medical.Callers / Config.Hospital.Services.Callers list pf-emsmdt);
--   * actions through its own server callbacks (triage, admit, transfer, careLevel, labOrder,
--     labDraw, imagingOrder, imagingPerform, orderCancel, patientOrders, rxPrescribe, rxCancel,
--     pharmacyLog), called with the real player id, exactly as the player's own client would call
--     them. The medical tier, positions, rate limits and locks stay in pf-ambulancejob; this file
--     never decides a result. The patient is resolved here from the admission (never a client id);
--   * the discharge through its export DischargePatient with actor = { src } and a key per admission;
--   * bills and the pharmacy counter queue are read-only SELECTs on pf-ambulancejob's tables
--     (pf_hosp_bills, pf_hosp_bill_lines, pf_hosp_prescriptions): it has no export for them yet.

PFHospitalApp = PFHospitalApp or {}
local HA = PFHospitalApp

local APP_ID = 'hospital'
local AJ = 'pf-ambulancejob'
HA.AppId = APP_ID
HA.Entry = 'html/apps/hospital.js'

-- Mirrors pf-ambulancejob's Config.Hospital.StaffJobs (its staff check runs again on every action).
HA.StaffJobs = { ambulance = true }
-- GetHospitalStatus(1..n) lists the facilities in pf-ambulancejob's Order; facilities outside the
-- Order (the prison infirmary) are probed by id. An id pf-ambulancejob does not know is dropped.
HA.ExtraFacilities = { 'bolingbroke' }
HA.RelayTimeoutMs = 9000        -- under pf-devices' 10 s client timeout
HA.ScanTimeoutMs = 120000       -- an imaging scan waits the modality's time on the server
HA.PageSize = 25

-- What the forms offer. pf-ambulancejob validates every value again (config_hospital.lua:
-- Triage.Levels, Discharge.RestrictionKinds, Pharmacy.Formulary, Lab.Tests, Imaging.Tests,
-- Stays.Levels); a value it does not know is refused with its own message.
HA.Options = {
    triage = { 'red', 'orange', 'yellow', 'green', 'blue' },
    restrictions = {
        { id = 'no_drive', label = 'No driving' }, { id = 'no_sprint', label = 'No sprinting' },
        { id = 'crutches', label = 'Crutches' }, { id = 'concussion', label = 'Concussion care' },
        { id = 'cast_arm_l', label = 'Cast, left arm' }, { id = 'cast_arm_r', label = 'Cast, right arm' },
        { id = 'no_heavy_work', label = 'No heavy work' },
    },
    maxRestrictionHours = 168, maxFollowUpDays = 30,
    formulary = {
        { id = 'painkillers', label = 'Painkillers', maxUnits = 12, maxFills = 3 },
        { id = 'antibiotics', label = 'Antibiotics', maxUnits = 6, maxFills = 2 },
        { id = 'bandage', label = 'Bandages', maxUnits = 10, maxFills = 2 },
        { id = 'crutches', label = 'Crutches', maxUnits = 1, maxFills = 1 },
    },
    lab = { { id = 'blood_type', label = 'Blood type' }, { id = 'cbc', label = 'Complete blood count' },
        { id = 'tox', label = 'Toxicology screen' }, { id = 'bac', label = 'Blood alcohol' } },
    imaging = { { id = 'xray', label = 'X-ray' }, { id = 'ct', label = 'CT scan' } },
    careLevels = { { id = 'standard', label = 'Standard' }, { id = 'icu', label = 'Intensive care' } },
    departments = { ed = 'Emergency department', ward = 'Ward', infirmary = 'Infirmary' },
}

local PAGES = { 'reception', 'triage', 'beds', 'admissions', 'discharge', 'lab', 'imaging', 'pharmacy' }
local BILL_STATES = { open = true, charging = true, payment_pending = true, invoiced = true, paid = true, waived = true }
local ADM_STATES = { arrived = true, checked_in = true, triaged = true, waiting = true, in_treatment = true, admitted = true,
    discharged = true, transferred = true, left_ama = true, deceased = true }

HA.lastFacility = HA.lastFacility or {}   -- [citizenid] = facility id the staff member looked at last
HA.scanning = HA.scanning or {}           -- [src] = order id of the scan this player runs now
HA.facilityCache = HA.facilityCache or { list = nil, at = 0 }

-- ── small helpers ────────────────────────────────────────────────────────────────────────────

local function fail(code, message)
    return { ok = false, error = code, message = message }
end
HA.Fail = fail

local function started(res)
    local ok, state = pcall(GetResourceState, res)
    return ok and state == 'started'
end

--- A callable value from another resource (funcrefs are tables): never type(x) == 'function'.
local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

local function int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    v = math.tointeger(v)
    if not v or (lo and v < lo) or (hi and v > hi) then return nil end
    return v
end

local function text(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max or 255)
end

local function ident(v, max)
    if type(v) ~= 'string' or #v < 1 or #v > (max or 32) or v:find('[^%w_%-]') then return nil end
    return v
end

local function now() return os.time() end

--- Calls a pf-ambulancejob export. Returns the result | nil, error code.
local function aj(name, ...)
    if not started(AJ) then return nil, 'hospital_offline' end
    local args = table.pack(...)
    local ok, res, extra = pcall(function()
        local e = exports[AJ]
        return e[name](e, table.unpack(args, 1, args.n))
    end)
    if not ok then
        print(('^1[pf-emsmdt]^7 hospital app: %s failed: %s'):format(name, tostring(res)))
        return nil, 'hospital_offline'
    end
    return res, extra
end
HA.Call = aj

-- ── who is asking (re-read on every call) ────────────────────────────────────────────────────

local function player(src)
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(P) == 'table' and type(P.PlayerData) == 'table' then return P end
    return nil
end

local function gradeOf(job)
    local g = type(job) == 'table' and job.grade or nil
    if type(g) == 'table' then g = g.level end
    return tonumber(g) or 0
end

--- On-duty hospital staff. Returns P | nil, failure.
function HA.Staff(src)
    local P = player(src)
    if not P then return nil, fail('offline', 'You are not loaded.') end
    local job = P.PlayerData.job
    if type(job) ~= 'table' or not HA.StaffJobs[job.name] then return nil, fail('not_staff', 'Only hospital staff use the workstation.') end
    if job.onduty ~= true then return nil, fail('not_on_duty', 'Go on duty first.') end
    return P
end

--- Supervisors (pf-emsmdt Config.SupervisorGrades, or the job's boss flag) see the bills.
function HA.Supervisor(P)
    local job = P and P.PlayerData.job
    if type(job) ~= 'table' then return false end
    if job.isboss == true then return true end
    local grades = Config and Config.SupervisorGrades and Config.SupervisorGrades[job.name]
    return type(grades) == 'table' and grades[gradeOf(job)] == true
end

local function charName(P)
    local ci = P and P.PlayerData.charinfo or {}
    local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n or nil
end

-- ── facilities ───────────────────────────────────────────────────────────────────────────────

--- { { id, label } } from GetHospitalStatus: the Order by index, then the extra ids. Cached 5 min.
function HA.Facilities(force)
    local c = HA.facilityCache
    if not force and c.list and #c.list > 0 and now() - c.at < 300 then return c.list end
    local out, seen = {}, {}
    local function probe(id)
        local res = aj('GetHospitalStatus', id)
        if type(res) ~= 'table' or res.ok ~= true then return false end
        local fid = ident(res.hospitalId)
        if fid and not seen[fid] then
            seen[fid] = true
            out[#out + 1] = { id = fid, label = text(res.label, 64) or fid }
        end
        return true
    end
    for i = 1, 8 do
        if not probe(i) then break end
    end
    for _, id in ipairs(HA.ExtraFacilities) do probe(id) end
    c.list, c.at = out, now()
    return out
end

--- The facility a payload names, when pf-ambulancejob knows it. Returns id, label | nil.
local function facilityOf(p)
    local fid = ident(type(p) == 'table' and p.facility or nil)
    if not fid then return nil end
    for _, f in ipairs(HA.Facilities()) do
        if f.id == fid then return f.id, f.label end
    end
    return nil
end

-- ── patients: names and online ids ───────────────────────────────────────────────────────────

local function onlineByCid(cid)
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayerByCitizenId(cid) end)
    if ok and type(P) == 'table' and type(P.PlayerData) == 'table' then return P end
    return nil
end

local function nameFromCharinfo(raw)
    local ci = raw
    if type(raw) == 'string' then
        local ok, t = pcall(json.decode, raw)
        ci = ok and t or nil
    end
    if type(ci) ~= 'table' then return nil end
    local n = ((type(ci.firstname) == 'string' and ci.firstname or '') .. ' ' .. (type(ci.lastname) == 'string' and ci.lastname or ''))
        :gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n:sub(1, 64) or nil
end
HA.NameFromCharinfo = nameFromCharinfo

--- [cid] = { name, online } for a list of citizen ids: online players from the core, the others
--- in one SELECT on players.
function HA.Names(cids)
    local out, missing, seen = {}, {}, {}
    for _, cid in ipairs(cids) do
        if type(cid) == 'string' and not seen[cid] then
            seen[cid] = true
            local P = onlineByCid(cid)
            if P then out[cid] = { name = charName(P), online = true }
            elseif #missing < 100 then missing[#missing + 1] = cid end
        end
    end
    if #missing > 0 then
        local marks = {}
        for i = 1, #missing do marks[i] = '?' end
        local ok, rows = pcall(MySQL.query.await, 'SELECT citizenid, charinfo FROM players WHERE citizenid IN (' .. table.concat(marks, ', ') .. ')', missing)
        if ok and type(rows) == 'table' then
            for _, r in ipairs(rows) do out[r.citizenid] = { name = nameFromCharinfo(r.charinfo), online = false } end
        end
    end
    return out
end

--- The patient's server id, when online (the target of bedside actions).
local function patientSrc(cid)
    local P = onlineByCid(cid)
    return P and tonumber(P.PlayerData.source) or nil
end

-- ── admissions ───────────────────────────────────────────────────────────────────────────────

local function admView(a, names)
    if type(a) ~= 'table' then return nil end
    local n = names[a.citizenid] or {}
    local view = {
        id = int(a.id), citizenid = text(a.citizenid, 64), name = n.name, online = n.online == true,
        state = text(a.state, 16), mode = text(a.mode, 8), triage = text(a.triage, 8), dept = text(a.dept, 16), bedId = text(a.bedId, 32),
        reason = text(a.reason, 64), hospitalId = text(a.hospitalId, 32), arrivedAt = int(a.arrivedAt), triagedAt = int(a.triagedAt),
        admittedAt = int(a.admittedAt), dischargedAt = int(a.dischargedAt), open = a.open == true,
    }
    if view.open then
        local inCare, kind = aj('IsInCustodyCare', a.citizenid)
        if inCare == true then view.custody = text(kind, 16) or 'custody' end
    end
    return view
end

local function views(list)
    local cids = {}
    for _, a in ipairs(list) do if type(a) == 'table' then cids[#cids + 1] = a.citizenid end end
    local names = HA.Names(cids)
    local out = {}
    for _, a in ipairs(list) do out[#out + 1] = admView(a, names) end
    return out
end

--- One open admission of a facility, from pf-ambulancejob. Returns admission | nil, failure.
function HA.OpenAdmission(fid, id)
    id = int(id, 1)
    if not id then return nil, fail('bad_args', 'Choose an admission.') end
    local res, err = aj('ListAdmissions', fid, { limit = 100 })
    if type(res) ~= 'table' then return nil, fail(err or 'hospital_offline', 'The hospital records are unavailable.') end
    if not res.ok then return nil, fail(res.error or 'hospital_offline', res.message) end
    for _, a in ipairs(res.list or {}) do
        if type(a) == 'table' and int(a.id) == id then return a end
    end
    return nil, fail('not_found', 'No open admission with that number here.')
end

-- ── relay to pf-ambulancejob's server callbacks ──────────────────────────────────────────────

--- The server callback pf-ambulancejob registered (through pfm-core), looked up at call time so a
--- restart of either resource is picked up.
function HA.Callback(name)
    local ok, core = pcall(function() return exports['pfm-core']:GetCoreObject({ 'ServerCallbacks' }) end)
    local list = ok and type(core) == 'table' and core.ServerCallbacks or nil
    local fn = type(list) == 'table' and list['pf-ambulancejob:server:' .. name] or nil
    return callable(fn) and fn or nil
end

--- Runs pf-ambulancejob's callback `name` as player `src` (the same call that player's client
--- makes) and returns its answer. A callback that answers later is awaited up to timeoutMs.
function HA.Relay(name, src, timeoutMs, ...)
    if not started(AJ) then return fail('hospital_offline', 'The hospital system is offline.') end
    local fn = HA.Callback(name)
    if not fn then return fail('hospital_offline', 'The hospital system is offline.') end
    local result, done = nil, false
    local p = (type(promise) == 'table' and callable(promise.new)) and promise.new() or nil
    local okCall, err = pcall(fn, src, function(res)
        if done then return end
        done, result = true, res
        if p then p:resolve(true) end
    end, ...)
    if not okCall then
        print(('^1[pf-emsmdt]^7 hospital app: %s failed: %s'):format(name, tostring(err)))
        return fail('server_error', 'Something went wrong.')
    end
    if not done and p and Citizen and callable(Citizen.Await) then
        SetTimeout(timeoutMs or HA.RelayTimeoutMs, function()
            if not done then done = true p:resolve(false) end
        end)
        Citizen.Await(p)
    end
    if type(result) ~= 'table' then
        return fail('no_answer', 'The hospital did not answer in time; refresh to see whether it went through.')
    end
    if result.ok == nil then result.ok = true end
    return result
end

--- Resolves the staff member, the facility, the open admission and the patient's server id, then
--- runs fn(P, admission, patientSrc, facilityId).
local function withPatient(src, p, fn)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    local a, aerr = HA.OpenAdmission(fid, p.admissionId)
    if not a then return aerr end
    local psrc = patientSrc(a.citizenid)
    if not psrc then return fail('patient_offline', 'The patient is not in the city.') end
    return fn(P, a, psrc, fid)
end

-- ── pushes (live boards) ─────────────────────────────────────────────────────────────────────

function HA.PushStaff(event, payload)
    if not started('pf-devices') then return end
    for job in pairs(HA.StaffJobs) do
        pcall(function() exports['pf-devices']:PushToJob(job, APP_ID, event, payload, true) end)
    end
end

function HA.Push(src, event, payload)
    if not started('pf-devices') then return end
    pcall(function() exports['pf-devices']:Push(src, APP_ID, event, payload) end)
end

--- pf-ambulancejob raised admissionChanged: open boards reload (only ids and the state are sent).
function HA.OnAdmissionChanged(adm, from, to)
    if type(adm) ~= 'table' then return end
    HA.PushStaff('changed', { hospitalId = ident(adm.hospitalId), admissionId = int(adm.id), state = ident(to, 16) or ident(adm.state, 16) })
end

function HA.OnOrderResulted(order)
    if type(order) ~= 'table' then return end
    HA.PushStaff('orders', { hospitalId = ident(order.hospitalId), orderId = int(order.id), kind = ident(order.kind, 16) })
end

-- server-local events of pf-ambulancejob (TriggerEvent); not net events, a client cannot raise them here
AddEventHandler('pf-ambulancejob:server:admissionChanged', function(adm, from, to) HA.OnAdmissionChanged(adm, from, to) end)
AddEventHandler('pf-ambulancejob:server:orderResulted', function(order) HA.OnOrderResulted(order) end)
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then HA.scanning[src] = nil end
end)

-- ── handlers ─────────────────────────────────────────────────────────────────────────────────

local handlers = {}
HA.Handlers = handlers

--- Who is asking, the facilities, the pages this player may open and the form options.
function handlers.init(src)
    local P, why = HA.Staff(src)
    if not P then return why end
    if not started(AJ) then return fail('hospital_offline', 'The hospital system is offline.') end
    local list = HA.Facilities(true)
    if #list == 0 then return fail('hospital_offline', 'The hospital system is offline.') end
    local cid = P.PlayerData.citizenid
    local current = HA.lastFacility[cid]
    local known = false
    for _, f in ipairs(list) do if f.id == current then known = true end end
    local supervisor = HA.Supervisor(P)
    local pages = {}
    for i, page in ipairs(PAGES) do pages[i] = page end
    if supervisor then pages[#pages + 1] = 'bills' end
    return {
        ok = true, facilities = list, facility = known and current or list[1].id, pages = pages,
        me = { name = charName(P), grade = gradeOf(P.PlayerData.job), supervisor = supervisor },
        options = HA.Options,
    }
end

--- Bed counts and every open admission of a facility (reception, triage, beds, admissions).
function handlers.board(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid, label = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    HA.lastFacility[P.PlayerData.citizenid] = fid
    local status, serr = aj('GetHospitalStatus', fid)
    if type(status) ~= 'table' or not status.ok then return fail((status and status.error) or serr or 'hospital_offline', status and status.message) end
    local res, lerr = aj('ListAdmissions', fid, { limit = 100 })
    if type(res) ~= 'table' or not res.ok then return fail((res and res.error) or lerr or 'hospital_offline', res and res.message) end
    local beds = {}
    for dept, b in pairs(type(status.beds) == 'table' and status.beds or {}) do
        local d = ident(dept, 16)
        if d and type(b) == 'table' then
            beds[#beds + 1] = { dept = d, label = HA.Options.departments[d] or d, total = int(b.total, 0) or 0, free = int(b.free, 0) or 0 }
        end
    end
    table.sort(beds, function(x, y) return x.dept < y.dept end)
    return { ok = true, facility = fid, label = label, beds = beds, staffOnDuty = int(status.staffOnDuty, 0) or 0, aiActive = status.aiActive == true,
        admissions = views(res.list or {}), at = now() }
end

--- Recent admissions of a facility, open and closed, newest first (pf-ambulancejob keeps at most
--- 100 per answer); filtered by state here.
function handlers.history(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    local state = p.state
    if state ~= nil and state ~= '' and not ADM_STATES[state] then return fail('bad_args', 'Unknown state.') end
    local limit = int(p.limit, 1, 100) or 50
    local res, err = aj('ListAdmissions', fid, { open = false, limit = limit })
    if type(res) ~= 'table' or not res.ok then return fail((res and res.error) or err or 'hospital_offline', res and res.message) end
    local list = {}
    for _, a in ipairs(res.list or {}) do
        if type(a) == 'table' and (state == nil or state == '' or a.state == state) then list[#list + 1] = a end
    end
    return { ok = true, facility = fid, admissions = views(list), limit = limit, more = #(res.list or {}) >= limit and limit < 100 }
end

function handlers.triage(src, p)
    if type(p.level) ~= 'string' or #p.level > 8 then return fail('bad_args', 'Choose a triage colour.') end
    return withPatient(src, p, function(_, a, psrc)
        return HA.Relay('triage', src, nil, psrc, p.level)
    end)
end

function handlers.admit(src, p)
    local dept = ident(p.dept, 16)
    if not dept then return fail('bad_args', 'Choose a department.') end
    local bed = nil
    if p.bedId ~= nil and p.bedId ~= '' then
        bed = ident(p.bedId, 32)
        if not bed then return fail('bad_args', 'Invalid bed.') end
    end
    return withPatient(src, p, function(_, a)
        return HA.Relay('admit', src, nil, int(a.id), dept, bed)
    end)
end

function handlers.transfer(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid = facilityOf(p)
    local to = facilityOf({ facility = p.to })
    if not fid or not to then return fail('bad_args', 'Choose where to.') end
    local a, aerr = HA.OpenAdmission(fid, p.admissionId)
    if not a then return aerr end
    return HA.Relay('transfer', src, nil, int(a.id), { hospitalId = to })
end

function handlers.careLevel(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local level = ident(p.level, 16)
    if not level then return fail('bad_args', 'Choose a care level.') end
    local fid = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    local a, aerr = HA.OpenAdmission(fid, p.admissionId)
    if not a then return aerr end
    return HA.Relay('careLevel', src, nil, int(a.id), level)
end

--- Discharge orders in the shape pf-ambulancejob validates (types and counts only; it checks the
--- kinds, hours, drugs and amounts itself).
function HA.CleanOrders(o)
    if type(o) ~= 'table' then return {} end
    local out = {}
    if type(o.restrictions) == 'table' then
        out.restrictions = {}
        for i, r in ipairs(o.restrictions) do
            if i > 8 then break end
            if type(r) == 'table' then
                out.restrictions[#out.restrictions + 1] = { kind = ident(r.kind, 32) or '', hours = tonumber(r.hours), reason = text(r.reason, 128) }
            end
        end
    end
    if o.followUpHours ~= nil and o.followUpHours ~= '' then out.followUpHours = tonumber(o.followUpHours) or -1 end
    out.note = text(o.note, 255)
    if type(o.prescriptions) == 'table' and #o.prescriptions > 0 then
        out.prescriptions = {}
        for i, r in ipairs(o.prescriptions) do
            if i > 8 then break end
            if type(r) == 'table' then
                out.prescriptions[#out.prescriptions + 1] = { drug = ident(r.drug, 32) or '', units = tonumber(r.units), fills = tonumber(r.fills),
                    note = text(r.note, 255) }
            end
        end
    end
    return out
end

--- The discharge through DischargePatient: pf-ambulancejob checks this player as the provider
--- (tier, inside the hospital; prescriptions need a physician). The key is per admission, so a
--- second click is answered as a duplicate and never discharges twice.
function handlers.discharge(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    local id = int(p.admissionId, 1)
    if not id then return fail('bad_args', 'Choose an admission.') end
    local res, err = aj('DischargePatient', id, { actor = { src = src }, orders = HA.CleanOrders(p.orders), reason = 'workstation',
        key = ('pf-emsmdt:hospital:discharge:%d'):format(id) })
    if type(res) ~= 'table' then return fail(err or 'hospital_offline', 'The hospital system is offline.') end
    return res
end

local function orderKind(kind)
    if kind == 'lab' or kind == 'imaging' then return kind end
    return nil
end

--- The lab or imaging queue of a facility. Results are not in the queue: they are opened per
--- patient (results), where pf-ambulancejob checks chart access and writes the audit row.
function handlers.orders(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid = facilityOf(p)
    local kind = orderKind(p.kind)
    if not fid or not kind then return fail('bad_args', 'Choose a hospital and a queue.') end
    local res, err = aj('ListHospitalOrders', fid, { kind = kind, open = p.open ~= false, limit = 100 })
    if type(res) ~= 'table' or not res.ok then return fail((res and res.error) or err or 'hospital_offline', res and res.message) end
    local cids = {}
    for _, o in ipairs(res.list or {}) do if type(o) == 'table' then cids[#cids + 1] = o.citizenid end end
    local names = HA.Names(cids)
    local list = {}
    for _, o in ipairs(res.list or {}) do
        if type(o) == 'table' and o.kind == kind then
            local n = names[o.citizenid] or {}
            list[#list + 1] = { id = int(o.id), citizenid = text(o.citizenid, 64), name = n.name, online = n.online == true,
                admissionId = int(o.admissionId), test = text(o.test, 32), label = text(o.label, 64), state = text(o.state, 16),
                orderedAt = int(o.orderedAt), readyAt = int(o.readyAt), resultedAt = int(o.resultedAt), hasResult = o.result ~= nil }
        end
    end
    return { ok = true, facility = fid, kind = kind, orders = list }
end

function handlers.labOrder(src, p)
    local test = ident(p.test, 32)
    if not test then return fail('bad_args', 'Choose a test.') end
    return withPatient(src, p, function(_, _, psrc) return HA.Relay('labOrder', src, nil, psrc, test) end)
end

function handlers.imagingOrder(src, p)
    local test = ident(p.test, 32)
    if not test then return fail('bad_args', 'Choose a scan.') end
    return withPatient(src, p, function(_, _, psrc) return HA.Relay('imagingOrder', src, nil, psrc, test) end)
end

function handlers.labDraw(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local id = int(p.orderId, 1)
    if not id then return fail('bad_args', 'Choose an order.') end
    return HA.Relay('labDraw', src, nil, id)
end

function handlers.orderCancel(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local id = int(p.orderId, 1)
    if not id then return fail('bad_args', 'Choose an order.') end
    return HA.Relay('orderCancel', src, nil, id)
end

--- Runs one scan for `src` and pushes the outcome to the app (a scan takes longer than an RPC may).
function HA.RunImaging(src, orderId)
    local res = HA.Relay('imagingPerform', src, HA.ScanTimeoutMs, orderId)
    HA.scanning[src] = nil
    local findings = {}
    for i, f in ipairs(type(res.findings) == 'table' and res.findings or {}) do
        if i > 20 then break end
        if type(f) == 'table' then findings[#findings + 1] = { label = text(f.label, 64), structure = text(f.structure, 32), value = text(tostring(f.value or ''), 32) } end
    end
    HA.Push(src, 'imaging', { orderId = orderId, ok = res.ok == true, error = res.error, message = text(res.message, 160), findings = findings })
    return res
end

function handlers.imagingPerform(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local id = int(p.orderId, 1)
    if not id then return fail('bad_args', 'Choose an order.') end
    if HA.scanning[src] then return fail('busy', 'You are already running a scan.') end
    HA.scanning[src] = id
    CreateThread(function() HA.RunImaging(src, id) end)
    return { ok = true, started = true, orderId = id }
end

--- A patient's lab and imaging results, through pf-ambulancejob's chart-access check.
function handlers.results(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    local a, aerr = HA.OpenAdmission(fid, p.admissionId)
    if not a then return aerr end
    return HA.Relay('patientOrders', src, nil, a.citizenid)
end

function handlers.prescribe(src, p)
    local drug = ident(p.drug, 32)
    if not drug then return fail('bad_args', 'Choose a drug.') end
    return withPatient(src, p, function(_, _, psrc)
        return HA.Relay('rxPrescribe', src, nil, psrc, drug, tonumber(p.units), tonumber(p.fills), text(p.note, 255))
    end)
end

function handlers.rxCancel(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local id = int(p.rxId, 1)
    if not id then return fail('bad_args', 'Choose a prescription.') end
    return HA.Relay('rxCancel', src, nil, id)
end

--- The controlled-substance log of the hospital this player stands in (pf-ambulancejob: nurse and
--- up, inside the hospital; the read is audited there).
function handlers.controlledLog(src)
    local P, why = HA.Staff(src)
    if not P then return why end
    local res = HA.Relay('pharmacyLog', src, nil)
    if not res.ok then return res end
    local cids = {}
    for _, r in ipairs(res.list or {}) do if type(r) == 'table' then cids[#cids + 1] = r.citizenid cids[#cids + 1] = r.byCid end end
    local names = HA.Names(cids)
    local list = {}
    for _, r in ipairs(res.list or {}) do
        if type(r) == 'table' then
            list[#list + 1] = { id = int(r.id), drug = text(r.drug, 32), qty = int(r.qty), kind = text(r.kind, 12), at = int(r.at),
                admissionId = int(r.admissionId), patient = (names[r.citizenid] or {}).name or text(r.citizenid, 64),
                by = (names[r.byCid] or {}).name or text(r.byCid, 64) }
        end
    end
    return { ok = true, hospitalId = text(res.hospitalId, 32), list = list }
end

-- ── pharmacy counter queue and bills (read-only SQL on pf-ambulancejob's tables) ──────────────

--- LIKE pattern for a search word (wildcards in the word are literal).
local function likeWord(w)
    return '%' .. w:gsub('[\\%%_]', function(c) return '\\' .. c end) .. '%'
end

HA.SQL = {}

--- Citizen ids whose character name holds every search word (players.charinfo; at most 50).
--- players is matched on its own: its collation can differ from pf-ambulancejob's tables, so the
--- queries never compare citizen ids across the two (a JOIN fails on a mixed-collation install).
function HA.SQL.CidsByName(q)
    local words = {}
    for w in q:gmatch('%S+') do
        if #words < 2 then words[#words + 1] = w end
    end
    if #words == 0 then return {} end
    local likes, params = {}, {}
    for i, w in ipairs(words) do
        likes[i] = 'charinfo LIKE ?'
        params[i] = likeWord(w)
    end
    local rows = MySQL.query.await('SELECT citizenid FROM players WHERE ' .. table.concat(likes, ' AND ') .. ' LIMIT 50', params) or {}
    local out = {}
    for _, r in ipairs(rows) do if type(r.citizenid) == 'string' then out[#out + 1] = r.citizenid end end
    return out
end

--- Search filter on a citizen id column: the exact id, or a character whose name matches.
--- Returns sql, params.
local function searchSql(q, cidCol)
    q = text(q, 48)
    if not q then return '', {} end
    local cids = HA.SQL.CidsByName(q)
    local params = { q }
    if #cids == 0 then return (' AND %s = ?'):format(cidCol), params end
    local marks = {}
    for i, cid in ipairs(cids) do marks[i] = '?' params[#params + 1] = cid end
    return (' AND (%s = ? OR %s IN (%s))'):format(cidCol, cidCol, table.concat(marks, ', ')), params
end

local FORMULARY = {}
for _, f in ipairs(HA.Options.formulary) do FORMULARY[f.id] = f.label end

function HA.SQL.PharmacyQueue(fid, at, q, limit, offset)
    local where, sp = searchSql(q, 'citizenid')
    local params = { fid, at }
    for _, v in ipairs(sp) do params[#params + 1] = v end
    params[#params + 1], params[#params + 2] = limit, offset
    return MySQL.query.await([[SELECT id, citizenid, drug, qty, units_per_fill, dispensed, controlled, prescriber_cid, created_at, expires_at,
        last_dispensed_at, interval_seconds, admission_id FROM pf_hosp_prescriptions
        WHERE hospital_id = ? AND state = 'active' AND expires_at > ?]] .. where .. ' ORDER BY id DESC LIMIT ? OFFSET ?', params) or {}
end

function HA.SQL.Bills(fid, state, q, limit, offset)
    local where, sp = searchSql(q, 'citizenid')
    local params = { fid }
    local stateSql = ''
    if state then stateSql, params[#params + 1] = ' AND state = ?', state end
    for _, v in ipairs(sp) do params[#params + 1] = v end
    params[#params + 1], params[#params + 2] = limit, offset
    return MySQL.query.await([[SELECT id, citizenid, admission_id, total, discount, state, created_at, settled_at
        FROM pf_hosp_bills WHERE hospital_id = ?]] .. stateSql .. where .. ' ORDER BY id DESC LIMIT ? OFFSET ?', params) or {}
end

function HA.SQL.Bill(id)
    return MySQL.single.await('SELECT id, citizenid, hospital_id, total, discount, state FROM pf_hosp_bills WHERE id = ? LIMIT 1', { id })
end

function HA.SQL.BillLines(id)
    return MySQL.query.await('SELECT kind, label, qty, unit_price FROM pf_hosp_bill_lines WHERE bill_id = ? ORDER BY id LIMIT 200', { id }) or {}
end

local function cidsOf(rows, max)
    local out = {}
    for i, r in ipairs(rows) do
        if i > max then break end
        out[#out + 1] = r.citizenid
    end
    return out
end

local function page(p)
    return int(p.page, 1, 1000) or 1
end

--- Prescriptions waiting at the facility's counter (active, not expired), newest first, paged.
function handlers.pharmacy(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    local fid = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    local n = page(p)
    local size = HA.PageSize
    local ok, rows = pcall(HA.SQL.PharmacyQueue, fid, now(), p.q, size + 1, (n - 1) * size)
    if not ok or type(rows) ~= 'table' then return fail('db_unavailable', 'Pharmacy records are unavailable.') end
    local names = HA.Names(cidsOf(rows, size))
    local list = {}
    for i, r in ipairs(rows) do
        if i > size then break end
        local last, every = tonumber(r.last_dispensed_at), tonumber(r.interval_seconds) or 0
        list[#list + 1] = { id = int(r.id), citizenid = r.citizenid, name = (names[r.citizenid] or {}).name, drug = r.drug,
            label = FORMULARY[r.drug] or r.drug, fills = int(r.qty), filled = int(r.dispensed) or 0, units = int(r.units_per_fill) or 1,
            controlled = tonumber(r.controlled) == 1, prescriber = r.prescriber_cid, createdAt = int(r.created_at), expiresAt = int(r.expires_at),
            nextAt = last and (last + every) or nil, admissionId = int(r.admission_id) }
    end
    return { ok = true, facility = fid, page = n, more = #rows > size, list = list }
end

--- The facility's hospital bills (supervisors), newest first, paged, by state and search.
function handlers.bills(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    if not HA.Supervisor(P) then return fail('no_permission', 'Bills are for supervisors.') end
    local fid = facilityOf(p)
    if not fid then return fail('bad_args', 'Choose a hospital.') end
    local state = nil
    if p.state ~= nil and p.state ~= '' then
        if not BILL_STATES[p.state] then return fail('bad_args', 'Unknown bill state.') end
        state = p.state
    end
    local n = page(p)
    local size = HA.PageSize
    local ok, rows = pcall(HA.SQL.Bills, fid, state, p.q, size + 1, (n - 1) * size)
    if not ok or type(rows) ~= 'table' then return fail('db_unavailable', 'Billing records are unavailable.') end
    local names = HA.Names(cidsOf(rows, size))
    local list = {}
    for i, r in ipairs(rows) do
        if i > size then break end
        local total, discount = int(r.total) or 0, int(r.discount) or 0
        list[#list + 1] = { id = int(r.id), citizenid = r.citizenid, name = (names[r.citizenid] or {}).name, admissionId = int(r.admission_id),
            total = total, discount = discount, due = math.max(0, total - discount), state = r.state, createdAt = int(r.created_at),
            settledAt = int(r.settled_at) }
    end
    return { ok = true, facility = fid, page = n, more = #rows > size, list = list }
end

function handlers.billLines(src, p)
    local P, why = HA.Staff(src)
    if not P then return why end
    if not HA.Supervisor(P) then return fail('no_permission', 'Bills are for supervisors.') end
    local id = int(p.billId, 1)
    if not id then return fail('bad_args', 'Choose a bill.') end
    local ok, bill = pcall(HA.SQL.Bill, id)
    if not ok then return fail('db_unavailable', 'Billing records are unavailable.') end
    if type(bill) ~= 'table' or not facilityOf({ facility = bill.hospital_id }) then return fail('not_found', 'No such bill.') end
    local okL, rows = pcall(HA.SQL.BillLines, id)
    if not okL or type(rows) ~= 'table' then return fail('db_unavailable', 'Billing records are unavailable.') end
    local lines = {}
    for _, r in ipairs(rows) do
        local qty, price = int(r.qty) or 1, int(r.unit_price) or 0
        lines[#lines + 1] = { kind = r.kind, label = r.label, qty = qty, unitPrice = price, amount = qty * price }
    end
    return { ok = true, billId = id, total = int(bill.total) or 0, discount = int(bill.discount) or 0, state = bill.state, lines = lines }
end

-- ── registration (server/devices.lua calls this when pf-devices is up) ────────────────────────

--- The app is offered only while its module ships with this resource.
function HA.ModuleReady()
    if not callable(LoadResourceFile) then return false end
    local ok, body = pcall(LoadResourceFile, GetCurrentResourceName(), HA.Entry)
    return ok and type(body) == 'string' and #body > 0
end

function HA.Register()
    if not started('pf-devices') or not HA.ModuleReady() then return false end
    local jobs = {}
    for job in pairs(HA.StaffJobs) do jobs[job] = 0 end
    local devices = exports['pf-devices']
    local ok = pcall(function()
        devices:RegisterApp({
            id = APP_ID, name = 'Hospital', icon = '🏥', kind = 'module',
            entry = HA.Entry, styles = { 'html/apps/hospital.css' },
            devices = { 'tablet', 'computer' }, category = 'jobs', order = 10,
            access = { jobs = jobs, onduty = true },
            description = 'Reception, triage, beds, admissions, discharge, lab, imaging, pharmacy and bills',
            window = { width = 1180, height = 760 },
        })
        devices:RegisterAppHandlers(APP_ID, handlers)
    end)
    return ok
end
