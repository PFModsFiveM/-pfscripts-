-- EMS unit board (batch 20, architecture 4.11): crews of on-duty medics, the unit's status, its rig and
-- the call it works. Everything comes from the server: members must be on duty in an EMS job (pfm-core
-- duty state, checked on every change and by a sweep), the rig plate is read from the vehicle the medic
-- sits in, and the call from the dispatch board when a crew member accepts it. The client only asks.
--
-- State lives in memory (Units, UnitOf) and is written to pf_emsmdt_units (schema v3) so a resource
-- restart keeps the board; on load every member is checked again and empty units are dropped.
--
-- Callbacks (all answer { ok = true, ... } or { ok = false, error, message }):
--   pf_emsmdt:units:list                    the board
--   pf_emsmdt:units:join      { unit }      join or create a unit (leaves the current one)
--   pf_emsmdt:units:leave                   leave the unit
--   pf_emsmdt:units:setStatus { status }    a crew member sets the unit's status
--   pf_emsmdt:units:setRig    { clear? }    the vehicle the medic sits in becomes the unit's rig
-- Export GetUnitStatus(src) -> { ok, onDuty, unit = { unit, status, crew, rigPlate, callRef, statusAt } | nil }.
-- Client event pf_emsmdt:client:UnitBoard(board) goes to on-duty medics on every change.

PFEmsUnits = PFEmsUnits or {}
local U = PFEmsUnits
local QBCore = PFMdt.GetCore()

U.Units = {}       -- [unit] = { unit, status, crew = { cid, ... }, rigPlate, callRef, statusAt, updatedAt }
U.UnitOfCid = {}   -- [cid] = unit
U.CidOfSrc = {}    -- [src] = cid of a crew member (playerDropped no longer has the player)

local function cfg() return Config.Units or {} end
local function now() return os.time() end

local function fail(code, message) return { ok = false, error = code, message = message } end

local function player(src)
    local P = QBCore.Functions.GetPlayer(src)
    if type(P) == 'table' and type(P.PlayerData) == 'table' then return P end
    return nil
end

local function playerByCid(cid)
    local P = QBCore.Functions.GetPlayerByCitizenId(cid)
    if type(P) == 'table' and type(P.PlayerData) == 'table' then return P end
    return nil
end

--- An on-duty member of an EMS MDT job (Config.AllowedJobs).
function U.IsOnDutyMedic(P)
    local job = P and P.PlayerData.job
    return type(job) == 'table' and Config.AllowedJobs and Config.AllowedJobs[job.name] == true and job.onduty == true
end

local function nameOf(P)
    local ci = P and P.PlayerData.charinfo or {}
    local name = (tostring(ci.firstname or '') .. ' ' .. tostring(ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or 'Medic'
end

-- per-source rate limit (1 action per second)
local last = {}
local function limited(src)
    local t = GetGameTimer()
    if last[src] and t - last[src] < 1000 then return true end
    last[src] = t
    return false
end

--- Unit names: 2..16 letters, digits, spaces or dashes, kept upper case ("MEDIC 12").
function U.CleanName(v)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' '):upper()
    if #v < 2 or #v > 16 or not v:match('^[A-Z0-9][A-Z0-9 %-]*$') then return nil end
    return v
end

-- ── persistence (one writer at a time, always the latest state) ────────────────────────────────

local dirty, flushing = {}, false

local function writeUnit(name)
    local u = U.Units[name]
    if not u or #u.crew == 0 then
        MySQL.query.await('DELETE FROM `pf_emsmdt_units` WHERE `unit` = ?', { name })
        return
    end
    MySQL.query.await([[INSERT INTO `pf_emsmdt_units` (`unit`, `status`, `crew`, `rig_plate`, `call_ref`, `status_at`, `updated_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE `status` = VALUES(`status`), `crew` = VALUES(`crew`),
        `rig_plate` = VALUES(`rig_plate`), `call_ref` = VALUES(`call_ref`), `status_at` = VALUES(`status_at`), `updated_at` = VALUES(`updated_at`)]],
        { name, u.status, json.encode(u.crew), u.rigPlate, u.callRef, u.statusAt, u.updatedAt })
end

--- Writes every changed unit, one at a time; a write in progress picks up later changes, so the
--- table always ends with the memory state. Nothing is written before the schema is ready.
function U.Flush()
    if flushing or not (PFEmsSchema and PFEmsSchema.Ready()) then return end
    flushing = true
    while true do
        local nextName = next(dirty)
        if not nextName then break end
        dirty[nextName] = nil
        local ok, err = pcall(writeUnit, nextName)
        if not ok then print(('^3[pf-emsmdt]^7 unit %s not saved: %s'):format(nextName, tostring(err))) end
    end
    flushing = false
end

--- Marks a unit changed and writes it.
function U.Save(name)
    dirty[name] = true
    U.Flush()
end

-- ── board ──────────────────────────────────────────────────────────────────────────────────────

function U.UnitOf(cid) return U.UnitOfCid[cid] end

function U.StatusOf(cid)
    local u = U.Units[U.UnitOfCid[cid] or '']
    return u and u.status or nil
end

function U.Get(name) return U.Units[name] end

local function publicUnit(u)
    local crew = {}
    for _, cid in ipairs(u.crew) do
        local P = playerByCid(cid)
        crew[#crew + 1] = { citizenid = cid, name = nameOf(P) }
    end
    return { unit = u.unit, status = u.status, statusLabel = (cfg().Statuses or {})[u.status] or u.status, crew = crew,
        rigPlate = u.rigPlate, callRef = u.callRef, statusAt = u.statusAt, updatedAt = u.updatedAt }
end

--- The board: every unit with a crew, sorted by name, and the on-duty medics in no unit.
function U.Board()
    local units, names = {}, {}
    for name in pairs(U.Units) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local u = U.Units[name]
        if #u.crew > 0 then units[#units + 1] = publicUnit(u) end
    end
    local free = {}
    for _, P in pairs(QBCore.Functions.GetQBPlayers() or {}) do
        if U.IsOnDutyMedic(P) and not U.UnitOfCid[P.PlayerData.citizenid] then
            free[#free + 1] = { citizenid = P.PlayerData.citizenid, name = nameOf(P) }
        end
    end
    table.sort(free, function(a, b) return a.name < b.name end)
    return { units = units, unassigned = free, statuses = cfg().Statuses or {} }
end

--- Sends the board to every on-duty medic and refreshes the dispatch units list.
function U.Push()
    local board = U.Board()
    for _, P in pairs(QBCore.Functions.GetQBPlayers() or {}) do
        if U.IsOnDutyMedic(P) then TriggerClientEvent('pf_emsmdt:client:UnitBoard', P.PlayerData.source, board) end
    end
    if PFEmsDispatch and PFEmsDispatch.BroadcastUnits then pcall(PFEmsDispatch.BroadcastUnits) end
end

-- ── crew changes ───────────────────────────────────────────────────────────────────────────────

local function removeCid(cid)
    local name = U.UnitOfCid[cid]
    if not name then return nil end
    U.UnitOfCid[cid] = nil
    local u = U.Units[name]
    if u then
        for i = #u.crew, 1, -1 do if u.crew[i] == cid then table.remove(u.crew, i) end end
        u.updatedAt = now()
        if #u.crew == 0 then U.Units[name] = nil end
    end
    for s, c in pairs(U.CidOfSrc) do if c == cid then U.CidOfSrc[s] = nil end end
    return name
end

local function setStatus(u, status)
    if u.status ~= status then u.status, u.statusAt = status, now() end
    u.updatedAt = now()
end

--- Joins (or creates) a unit. A medic is in one unit at a time.
function U.Join(src, rawName)
    local P = player(src)
    if not P then return fail('offline', 'You are not loaded.') end
    if not U.IsOnDutyMedic(P) then return fail('not_on_duty', 'Go on duty as a medic first.') end
    local name = U.CleanName(rawName)
    if not name then return fail('bad_args', 'Unit names are 2-16 letters, digits, spaces or dashes.') end
    local cid = P.PlayerData.citizenid
    if U.UnitOfCid[cid] == name then return { ok = true, unit = publicUnit(U.Units[name]), unchanged = true } end
    local u = U.Units[name]
    if u and #u.crew >= (tonumber(cfg().MaxCrew) or 4) then return fail('conflict', 'That unit is full.') end
    local left = removeCid(cid)
    if left then U.Save(left) end
    if not u then
        u = { unit = name, status = 'available', crew = {}, statusAt = now(), updatedAt = now() }
        U.Units[name] = u
    end
    u.crew[#u.crew + 1] = cid
    u.updatedAt = now()
    U.UnitOfCid[cid] = name
    U.CidOfSrc[src] = cid
    U.Save(name)
    U.Push()
    return { ok = true, unit = publicUnit(u) }
end

function U.Leave(src)
    local P = player(src)
    if not P then return fail('offline', 'You are not loaded.') end
    local name = removeCid(P.PlayerData.citizenid)
    if not name then return fail('not_found', 'You are not in a unit.') end
    U.Save(name)
    U.Push()
    return { ok = true }
end

--- A crew member sets the unit's status. On scene and transporting also time-stamp the crew's open
--- patient care reports (server/pcr.lua).
function U.SetStatus(src, status)
    local P = player(src)
    if not P then return fail('offline', 'You are not loaded.') end
    if not U.IsOnDutyMedic(P) then return fail('not_on_duty', 'You are off duty.') end
    if type(status) ~= 'string' or not (cfg().Statuses or {})[status] then return fail('bad_args', 'Unknown status.') end
    local name = U.UnitOfCid[P.PlayerData.citizenid]
    local u = name and U.Units[name]
    if not u then return fail('not_found', 'You are not in a unit.') end
    setStatus(u, status)
    U.Save(name)
    if PFEmsPcr and PFEmsPcr.OnUnitStatus then pcall(PFEmsPcr.OnUnitStatus, u.unit, u.crew, status, u.statusAt) end
    U.Push()
    return { ok = true, unit = publicUnit(u) }
end

local function rigAllowed(veh)
    local models = cfg().RigModels or {}
    if next(models) == nil then return true end
    local model = GetEntityModel(veh)
    for _, m in ipairs(models) do
        if model == GetHashKey(m) or model == (GetHashKey(m) & 0xFFFFFFFF) then return true end
    end
    return false
end

--- The vehicle the medic sits in (server view) becomes the unit's rig; `clear` removes the rig.
function U.SetRig(src, clear)
    local P = player(src)
    if not P then return fail('offline', 'You are not loaded.') end
    if not U.IsOnDutyMedic(P) then return fail('not_on_duty', 'You are off duty.') end
    local name = U.UnitOfCid[P.PlayerData.citizenid]
    local u = name and U.Units[name]
    if not u then return fail('not_found', 'You are not in a unit.') end
    if clear == true then
        u.rigPlate, u.updatedAt = nil, now()
    else
        local veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
        if not veh or veh == 0 then return fail('bad_args', 'Sit in the rig first.') end
        if not rigAllowed(veh) then return fail('no_permission', 'That vehicle is not an EMS rig.') end
        local plate = tostring(GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper():sub(1, 16)
        if plate == '' then return fail('bad_args', 'That vehicle has no plate.') end
        for other, o in pairs(U.Units) do
            if other ~= name and o.rigPlate == plate then return fail('conflict', ('That rig is with %s.'):format(other)) end
        end
        u.rigPlate, u.updatedAt = plate, now()
    end
    U.Save(name)
    U.Push()
    return { ok = true, unit = publicUnit(u) }
end

-- ── dispatch hooks (server/main.lua) ───────────────────────────────────────────────────────────

--- A crew member accepted a call: the unit works it and goes en route when it was available.
function U.OnCallAccepted(cid, callId)
    local name = U.UnitOfCid[cid]
    local u = name and U.Units[name]
    if not u then return end
    u.callRef = tostring(callId):sub(1, 64)
    if u.status == 'available' then setStatus(u, 'en_route') end
    u.updatedAt = now()
    U.Save(name)
    U.Push()
end

--- The call was completed or removed: units working it drop it.
function U.OnCallClosed(callId)
    local ref = tostring(callId)
    local changed = false
    for name, u in pairs(U.Units) do
        if u.callRef == ref then
            u.callRef, u.updatedAt = nil, now()
            U.Save(name)
            changed = true
        end
    end
    if changed then U.Push() end
end

-- ── duty state ─────────────────────────────────────────────────────────────────────────────────

--- Takes every crew member who is no longer an online, on-duty medic off their unit. Runs on duty
--- and job changes, on drops and on a timer. Returns how many were removed.
function U.Sweep()
    local removed, touched = 0, {}
    for name, u in pairs(U.Units) do
        for i = #u.crew, 1, -1 do
            local cid = u.crew[i]
            if not U.IsOnDutyMedic(playerByCid(cid)) then
                removeCid(cid)
                touched[name] = true
                removed = removed + 1
            end
        end
    end
    for name in pairs(touched) do U.Save(name) end
    if removed > 0 then U.Push() end
    return removed
end

--- A player who left: their crew seat is freed at once (the player object may already be gone).
function U.OnDropped(src)
    local cid = U.CidOfSrc[src]
    last[src] = nil
    if not cid then return end
    U.CidOfSrc[src] = nil
    local name = removeCid(cid)
    if name then
        U.Save(name)
        U.Push()
    end
end

--- Loads the saved board (schema ready). Members are checked against the duty state at once.
function U.Load()
    local rows = MySQL.query.await('SELECT `unit`, `status`, `crew`, `rig_plate`, `call_ref`, `status_at`, `updated_at` FROM `pf_emsmdt_units`') or {}
    for _, r in ipairs(rows) do
        local name = U.CleanName(r.unit)
        local crew = type(r.crew) == 'string' and json.decode(r.crew) or nil
        if name and type(crew) == 'table' and not U.Units[name] then
            local u = { unit = name, status = (cfg().Statuses or {})[r.status] and r.status or 'available', crew = {}, rigPlate = r.rig_plate,
                callRef = r.call_ref, statusAt = tonumber(r.status_at), updatedAt = tonumber(r.updated_at) or now() }
            for _, cid in ipairs(crew) do
                if type(cid) == 'string' and not U.UnitOfCid[cid] then
                    u.crew[#u.crew + 1] = cid
                    U.UnitOfCid[cid] = name
                    local P = playerByCid(cid)
                    if P then U.CidOfSrc[P.PlayerData.source] = cid end
                end
            end
            U.Units[name] = u
        end
    end
    -- rows whose crew is gone are deleted by the sweep's save; an empty crew row is deleted here
    for _, r in ipairs(rows) do if not U.Units[U.CleanName(r.unit) or ''] then dirty[r.unit] = true end end
    U.Sweep()
    U.Flush()
end

--- GetUnitStatus(src) export (Config.Callers.GetUnitStatus).
function U.ExportGetUnitStatus(src)
    local invoker = GetInvokingResource()
    if invoker and invoker ~= GetCurrentResourceName() then
        local list = Config.Callers and Config.Callers.GetUnitStatus
        if not (list == '*' or (type(list) == 'table' and list[invoker] == true)) then return fail('not_allowed', 'Not allowed.') end
    end
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return fail('bad_args', 'Invalid player.') end
    local P = player(src)
    if not P then return fail('offline', 'Player not loaded.') end
    local name = U.UnitOfCid[P.PlayerData.citizenid]
    return { ok = true, onDuty = U.IsOnDutyMedic(P), unit = name and U.Units[name] and publicUnit(U.Units[name]) or nil }
end

exports('GetUnitStatus', function(src) return U.ExportGetUnitStatus(src) end)

-- ── callbacks and events ───────────────────────────────────────────────────────────────────────

local function gate(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil, fail('bad_args', 'Invalid player.') end
    if limited(src) then return nil, fail('rate_limited', 'Slow down.') end
    return src
end

QBCore.Functions.CreateCallback('pf_emsmdt:units:list', function(source, cb)
    local P = player(source)
    local job = P and P.PlayerData.job
    if not (type(job) == 'table' and Config.AllowedJobs and Config.AllowedJobs[job.name]) then return cb(fail('no_permission', 'EMS only.')) end
    local board = U.Board()
    board.ok = true
    cb(board)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:units:join', function(source, cb, data)
    local src, err = gate(source)
    if not src then return cb(err) end
    cb(U.Join(src, type(data) == 'table' and data.unit or nil))
end)

QBCore.Functions.CreateCallback('pf_emsmdt:units:leave', function(source, cb)
    local src, err = gate(source)
    if not src then return cb(err) end
    cb(U.Leave(src))
end)

QBCore.Functions.CreateCallback('pf_emsmdt:units:setStatus', function(source, cb, data)
    local src, err = gate(source)
    if not src then return cb(err) end
    cb(U.SetStatus(src, type(data) == 'table' and data.status or nil))
end)

QBCore.Functions.CreateCallback('pf_emsmdt:units:setRig', function(source, cb, data)
    local src, err = gate(source)
    if not src then return cb(err) end
    cb(U.SetRig(src, type(data) == 'table' and data.clear == true))
end)

-- Duty and job changes are server events from pfm-core; the sweep re-reads the duty state itself, so
-- nothing in the event's arguments is trusted.
AddEventHandler('QBCore:Server:SetDuty', function() U.Sweep() end)
AddEventHandler('QBCore:Server:OnJobUpdate', function() U.Sweep() end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) U.OnDropped(tonumber(src) or 0) end)
AddEventHandler('playerDropped', function() U.OnDropped(source) end)

function U.Tick()
    U.Sweep()
end

if PFEmsSchema and PFEmsSchema.OnReady then
    PFEmsSchema.OnReady(function()
        local ok, err = pcall(U.Load)
        if not ok then print('^3[pf-emsmdt]^7 unit board not loaded: ' .. tostring(err)) end
    end)
end

CreateThread(function()
    while true do
        Wait(math.max(5, tonumber(cfg().SweepSeconds) or 30) * 1000)
        U.Tick()
    end
end)
