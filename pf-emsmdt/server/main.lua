local QBCore = PFMdt.GetCore()

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end

local function hasOxMySQL()
    return exports and exports.oxmysql ~= nil
end

local function sanitizeText(label, maxLen)
    label = tostring(label or '')
    label = label:gsub('[\r\n\t]', ' ')
    if maxLen and #label > maxLen then
        label = label:sub(1, maxLen)
    end
    if label:gsub('%s+', '') == '' then return '' end
    return label
end

local function sanitizeCoords(coords)
    if not coords then return nil end
    local t = type(coords)

    -- FiveM vector types (serialize badly to NUI if left as vectors)
    if t == 'vector3' or t == 'vector4' then
        local x = tonumber(coords.x)
        local y = tonumber(coords.y)
        local z = tonumber(coords.z)
        if not x or not y or not z then return nil end
        return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
    end

    if t ~= 'table' then return nil end

    -- Support both {x=,y=,z=} and array-like { [1]=x,[2]=y,[3]=z }
    local x = tonumber(coords.x) or tonumber(coords[1])
    local y = tonumber(coords.y) or tonumber(coords[2])
    local z = tonumber(coords.z) or tonumber(coords[3])
    if not x or not y or not z then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function GetPlayerJob(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil, nil end
    local job = Player.PlayerData and Player.PlayerData.job or nil
    return job and job.name or nil, job and job.grade and job.grade.level or 0
end

local function IsAllowedJob(jobName)
    return jobName and Config and Config.AllowedJobs and Config.AllowedJobs[jobName] == true
end

local function IsSupervisor(jobName, gradeLevel)
    if not (Config and Config.SupervisorGrades and Config.SupervisorGrades[jobName]) then return false end
    return Config.SupervisorGrades[jobName][gradeLevel] == true
end

local function IsOnDuty(source)
    local P = QBCore.Functions.GetPlayer(source)
    local job = P and P.PlayerData and P.PlayerData.job
    return job ~= nil and job.onduty == true
end

-- Reports from civilians' clients (/911) are about where the caller is: the
-- location must be near them (any client could place a call anywhere on the map before).
local REPORT_RADIUS = 150.0
local function nearCaller(src, coords)
    if not src or src == 0 then return true end -- server-side exports
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local p = GetEntityCoords(ped)
    return #(vector3(p.x, p.y, p.z) - vector3(coords.x, coords.y, coords.z)) <= REPORT_RADIUS
end

-- simple per-player rate limit: true when allowed
local _rate = {}
local function allowRate(src, key, ms)
    _rate[src] = _rate[src] or {}
    local now = GetGameTimer()
    if _rate[src][key] and now - _rate[src][key] < ms then return false end
    _rate[src][key] = now
    return true
end
AddEventHandler('playerDropped', function() _rate[source] = nil end)

local function getMedicName(src)
    local P = QBCore.Functions.GetPlayer(src)
    local ci = P and P.PlayerData and P.PlayerData.charinfo or nil
    if not ci then return 'Medic' end
    local first = tostring(ci.firstname or '')
    local last = tostring(ci.lastname or '')
    local name = (first .. ' ' .. last):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or 'Medic'
end

-- =====================================================================================
-- Patient Notes (EMS): table pf_emsmdt_patient_notes, created by server/schema.lua (v2)
-- =====================================================================================

-- =====================================================================================
-- Dispatch State
-- =====================================================================================
local ActiveCalls = {}
local CallIdCounter = 1

local function GenerateCallId()
    local id = string.format('DISP-%04d', CallIdCounter)
    CallIdCounter = CallIdCounter + 1
    return id
end

-- Debounce call list broadcasts (reduces dispatch lag/spam)
local _callsBroadcastQueued = false
local _callsBroadcastDelayMs = 200

local function broadcastNewCall(call)
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        local jobName = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
        if IsAllowedJob(jobName) then
            TriggerClientEvent('pf_emsmdt:dispatch:newCall', Player.PlayerData.source, call)
        end
    end
end

local function BroadcastCallsUpdateNow()
    local callsArray = {}

    local Players = QBCore.Functions.GetQBPlayers()
    local nameByCitizen = {}
    for _, P in pairs(Players) do
        local char = P.PlayerData and P.PlayerData.charinfo or {}
        local fullname = (char.firstname and char.lastname) and (char.firstname .. ' ' .. char.lastname) or getMedicName(P.PlayerData.source)
        nameByCitizen[P.PlayerData.citizenid] = fullname
    end

    for _, call in pairs(ActiveCalls) do
        local c = {}
        for k, v in pairs(call) do c[k] = v end
        c.assignedUnitNames = {}
        if c.assignedUnits then
            for _, cid in ipairs(c.assignedUnits) do
                table.insert(c.assignedUnitNames, nameByCitizen[cid] or cid)
            end
        end
        table.insert(callsArray, c)
    end

    for _, Player in pairs(Players) do
        local jobName = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
        if IsAllowedJob(jobName) then
            TriggerClientEvent('pf_emsmdt_dispatch:client:CallsUpdated', Player.PlayerData.source, callsArray)
        end
    end
end

local function BroadcastCallsUpdate()
    if _callsBroadcastQueued then return end
    _callsBroadcastQueued = true
    SetTimeout(_callsBroadcastDelayMs, function()
        _callsBroadcastQueued = false
        BroadcastCallsUpdateNow()
    end)
end

local function CreateCall(callData)
    -- a pf-services request has one call on the board (the same request is never posted twice)
    local requestId = tonumber(callData and callData.requestId)
    if requestId then
        for _, existing in pairs(ActiveCalls) do
            if existing.requestId == requestId then return existing end
        end
    end

    local id = GenerateCallId()
    local numericId = CallIdCounter - 1

    local safeCoords = sanitizeCoords(callData and callData.coords) or { x = 0.0, y = 0.0, z = 0.0 }

    local call = {
        id = id,
        callId = numericId,
        callType = callData.callType or callData.type or nil,
        code = callData.code or nil,
        title = callData.title or 'Call',
        description = callData.description or nil,
        status = callData.status or 'pending',
        priority = callData.priority or 2,
        locationLabel = callData.locationLabel or 'Unknown Location',
        coords = safeCoords,
        createdAt = callData.createdAt or os.time(),
        createdBy = callData.createdBy or 'system',
        assignedUnits = callData.assignedUnits or {},
        requestId = requestId,
    }

    ActiveCalls[call.id] = call
    broadcastNewCall(call)
    BroadcastCallsUpdate()
    return call
end

local function GetCall(callId)
    return ActiveCalls[tostring(callId or '')]
end

local function UpdateCall(callId, updates)
    local id = tostring(callId or '')
    local call = ActiveCalls[id]
    if not call then return false end

    for k, v in pairs(updates or {}) do
        call[k] = v
    end

    BroadcastCallsUpdate()
    return true
end

local function DeleteCall(callId)
    local id = tostring(callId or '')
    if id == '' or not ActiveCalls[id] then return false end
    ActiveCalls[id] = nil
    BroadcastCallsUpdate()
    return true
end

-- For server/pcr.lua and server/units.lua: a call by id, and the open call a medic is assigned to
-- (the newest one; completed calls do not count).
PFEmsDispatch = PFEmsDispatch or {}
PFEmsDispatch.GetCall = function(callId) return GetCall(callId) end
PFEmsDispatch.CallOf = function(cid)
    if type(cid) ~= 'string' or cid == '' then return nil end
    local best
    for _, call in pairs(ActiveCalls) do
        if call.status ~= 'completed' then
            for _, assigned in ipairs(call.assignedUnits or {}) do
                if assigned == cid and (not best or (call.callId or 0) > (best.callId or 0)) then best = call end
            end
        end
    end
    return best
end

local function unitsHook(name, ...)
    local U = PFEmsUnits
    if U and U[name] then pcall(U[name], ...) end
end

exports('CreateDispatchCall', function(callData)
    if type(callData) ~= 'table' then return nil end
    return CreateCall(callData)
end)

-- pf-services posts its EMS requests ('Person down', medic calls) on this board with the request's
-- id (requestId). When the request closes (patient revived, respawned, checked in, logged out, left,
-- expired) its call leaves the board, so medics are not sent to a patient who is gone (the calls
-- stayed 'pending' for ever before). Only the call carrying that request id is touched.
local REQUEST_CLOSED = { completed = true, cancelled = true, expired = true }

local function callForRequest(req)
    local id = tonumber(req.id)
    if not id then return nil end
    for _, call in pairs(ActiveCalls) do
        if call.requestId == id then return call end
    end
    return nil
end

local function closeRequestCall(req, what)
    if type(req) ~= 'table' or not REQUEST_CLOSED[what] then return false end
    local call = callForRequest(req)
    if not call then return false end
    unitsHook('OnCallClosed', call.id)
    if what == 'completed' then
        return UpdateCall(call.id, { status = 'completed' }) -- seen to: shown as done, like a call a medic completes
    end
    return DeleteCall(call.id) -- the patient is gone (or nobody came): nothing left to respond to
end

-- server-local event (TriggerEvent in pf-services; never a net event, so no client can raise it)
AddEventHandler('pf-services:requestChanged', function(req, what)
    local s = tonumber(source)
    if s and s > 0 then return end
    closeRequestCall(req, what)
end)

-- (The police MDT's crime callouts and auto calls (gunshots, vehicle theft, homicide with suspect
-- weapon and plate) were removed in batch 20: they never made a call here, because the config tables
-- they read did not exist, and EMS gets person-down calls from pf-ambulancejob through pf-services.)

-- =====================================================================================
-- /911 Calls (civilian)
-- =====================================================================================
local _last911 = {} -- [src] = os.time()

local function _trim(s)
    s = tostring(s or '')
    return (s:gsub('^%s*(.-)%s*$', '%1'))
end

local function _lower(s)
    return tostring(s or ''):lower()
end

local function _escapePattern(s)
    return tostring(s or ''):gsub('(%W)', '%%%1')
end

local function _containsKeyword(descLower, keyword)
    local k = _lower(_trim(keyword))
    if k == '' then return false end

    if k:match('^%w+$') then
        local pat = '%f[%w]' .. _escapePattern(k) .. '%f[%W]'
        return descLower:find(pat) ~= nil
    end

    return descLower:find(k, 1, true) ~= nil
end

local function classify911Matches(description, maxCalls)
    local cfg = Config and Config.Dispatch911 or nil
    local desc = _lower(description)
    if not cfg or cfg.Enabled ~= true then return {}, cfg and cfg.Default or nil end

    local types = cfg.Types
    if type(types) ~= 'table' then
        return {}, cfg.Default
    end

    local matches = {}
    for _, t in pairs(types) do
        if type(t) == 'table' and type(t.keywords) == 'table' then
            local hits = 0
            for _, kw in ipairs(t.keywords) do
                if _containsKeyword(desc, kw) then
                    hits = hits + 1
                end
            end
            if hits > 0 then
                table.insert(matches, {
                    meta = t,
                    priority = tonumber(t.priority) or 2,
                    hits = hits
                })
            end
        end
    end

    table.sort(matches, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.hits ~= b.hits then return a.hits > b.hits end
        return false
    end)

    local out = {}
    local limit = tonumber(maxCalls) or 1
    if limit < 1 then limit = 1 end

    for _, m in ipairs(matches) do
        if #out >= limit then break end
        table.insert(out, m.meta)
    end

    return out, cfg.Default
end

-- One /911 for both departments: pf-policemdt-DEV and this MDT both register a /911 command and
-- only one of them gets it, so this also listens to the police MDT's 911 event and creates an EMS
-- call when the description matches the EMS 911 keywords (onlyMatches).
local function handle911(src, payload, onlyMatches)
    local cfg = Config and Config.Dispatch911 or nil
    if not cfg or cfg.Enabled ~= true then return end
    if type(payload) ~= 'table' then return end

    local desc = payload and sanitizeText(payload.description, tonumber(cfg.MaxDescriptionLength) or 200) or ''
    if desc == '' then return end

    local coords = sanitizeCoords(payload and payload.coords)
    if not coords then return end
    if not nearCaller(src, coords) then return end

    local locationLabel = sanitizeText(payload and payload.locationLabel, 128)
    if locationLabel == '' then locationLabel = 'Unknown Location' end

    local maxCalls = tonumber(cfg.MaxCallsPerMessage) or 1
    local matched, defaultMeta = classify911Matches(desc, maxCalls)
    -- a police /911 that is nothing for EMS does not use up the caller's EMS cooldown
    if onlyMatches and #matched == 0 then return end

    local now = os.time()
    local cd = tonumber(cfg.CooldownSeconds) or 10
    if cd < 0 then cd = 0 end
    local last = tonumber(_last911[src]) or 0
    if cd > 0 and (now - last) < cd then
        return
    end
    _last911[src] = now

    if #matched == 0 then
        local meta = defaultMeta or { title = '911 Call', priority = 2, code = '911' }
        CreateCall({
            callType = '911',
            code = meta.code or '911',
            title = meta.title or '911 Call',
            description = desc,
            locationLabel = locationLabel,
            coords = coords,
            priority = tonumber(meta.priority) or 2,
            createdBy = ('911:' .. tostring(src))
        })
        return
    end

    for _, meta in ipairs(matched) do
        CreateCall({
            callType = '911',
            code = meta.code or '911',
            title = meta.title or '911 Call',
            description = desc,
            locationLabel = locationLabel,
            coords = coords,
            priority = tonumber(meta.priority) or 2,
            createdBy = ('911:' .. tostring(src))
        })
    end
end

RegisterNetEvent('pf_emsmdt_dispatch:server:Create911Call', function(payload)
    handle911(source, payload, false)
end)

RegisterNetEvent('pf_mdt_dispatch:server:Create911Call', function(payload)
    handle911(source, payload, true)
end)

-- =====================================================================================
-- Dispatch Server Callbacks & Events (client/main.lua)
-- =====================================================================================
QBCore.Functions.CreateCallback('pf_emsmdt_dispatch:server:GetCalls', function(source, cb)
    local jobName = GetPlayerJob(source)
    if not IsAllowedJob(jobName) then
        cb(nil)
        return
    end

    local callsArray = {}
    for _, call in pairs(ActiveCalls) do
        -- Ensure coords are always a plain table for NUI/JS consumers.
        if call and call.coords then
            call.coords = sanitizeCoords(call.coords) or { x = 0.0, y = 0.0, z = 0.0 }
        end
        table.insert(callsArray, call)
    end
    cb(callsArray)
end)

-- Units cache via roster table
local PlayerCallsigns = {}
local PlayerRosterRanks = {}
local RosterCache = { at = 0, ttl = 60 }
local broadcastUnitsUpdate

-- A medic's status on the board: their unit's status (server/units.lua), 'available' when on duty
-- without a unit, 'off_duty' otherwise. It was the medic's own free-text metadata before.
local function boardStatus(cid, onduty)
    if onduty ~= true then return 'off_duty' end
    local U = PFEmsUnits
    local st = U and U.StatusOf and U.StatusOf(cid) or nil
    return st or 'available'
end

local function ensureRosterCache(cb)
    if not hasOxMySQL() then
        if cb then cb(false) end
        return
    end

    local now = os.time()
    if (RosterCache.at or 0) > 0 and (now - (RosterCache.at or 0)) < (RosterCache.ttl or 60) then
        if cb then cb(true) end
        return
    end

    exports.oxmysql:fetch('SELECT citizenid, callsign, rank FROM pf_emsmdt_roster WHERE citizenid IS NOT NULL AND citizenid != ""', {}, function(results)
        local callsigns = {}
        local ranks = {}
        for _, row in ipairs(results or {}) do
            local cid = row.citizenid and tostring(row.citizenid) or ''
            if cid ~= '' then
                local cs = row.callsign and tostring(row.callsign) or ''
                local rk = row.rank and tostring(row.rank) or ''
                if cs ~= '' then callsigns[cid] = cs end
                if rk ~= '' then ranks[cid] = rk end
            end
        end
        PlayerCallsigns = callsigns
        PlayerRosterRanks = ranks
        RosterCache.at = os.time()
        if cb then cb(true) end
    end)
end

-- server-only (raised by server/roster.lua); any client could force a roster reload and broadcast
AddEventHandler('pf_emsmdt:server:RosterUpdated', function()
    RosterCache.at = 0
    if broadcastUnitsUpdate then
        broadcastUnitsUpdate()
    end
end)

broadcastUnitsUpdate = function()
    local Players = QBCore.Functions.GetQBPlayers()
    ensureRosterCache(function()
        local unitsList = {}

        for _, Player in pairs(Players) do
            local jobName = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
            if IsAllowedJob(jobName) then
                local cid = Player.PlayerData.citizenid
                local charinfo = Player.PlayerData.charinfo or {}
                local meta = Player.PlayerData.metadata or {}
                local name = (tostring(charinfo.firstname or '') .. ' ' .. tostring(charinfo.lastname or ''))

                table.insert(unitsList, {
                    name = name:gsub('^%s*(.-)%s*$', '%1'),
                    phone = charinfo.phone or charinfo.phone_number or meta.phone or meta.phonenumber or '',
                    callsign = PlayerCallsigns[cid] or meta.callsign or meta.mdt_callsign or ('UNIT-' .. (cid or ''):sub(1, 4)),
                    rank = PlayerRosterRanks[cid] or '',
                    job = jobName,
                    grade = (Player.PlayerData.job.grade and (Player.PlayerData.job.grade.label or Player.PlayerData.job.grade.level)) or 'Medic',
                    duty = (Player.PlayerData.job.onduty and 'on_duty') or 'off_duty',
                    status = boardStatus(cid, Player.PlayerData.job.onduty),
                    unit = PFEmsUnits and PFEmsUnits.UnitOf(cid) or nil,
                })
            end
        end

        for _, Player in pairs(Players) do
            local jobName = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
            if IsAllowedJob(jobName) then
                TriggerClientEvent('pf_emsmdt:client:UnitsUpdated', Player.PlayerData.source, unitsList)
            end
        end
    end)
end

-- server/units.lua pushes the dispatch units list again when a crew or status changes
PFEmsDispatch.BroadcastUnits = function() if broadcastUnitsUpdate then broadcastUnitsUpdate() end end

-- (No warm-up read here: on a fresh database it ran before server/roster.lua had created the table.
-- The cache fills on the first units request or roster change.)

QBCore.Functions.CreateCallback('pf_emsmdt_dispatch:server:GetUnits', function(source, cb)
    local jobName = GetPlayerJob(source)
    if not IsAllowedJob(jobName) then
        cb(nil)
        return
    end

    ensureRosterCache(function()
        local units = {}
        local players = QBCore.Functions.GetQBPlayers()
        for _, P in pairs(players) do
            local pj = P.PlayerData and P.PlayerData.job and P.PlayerData.job.name or nil
            if IsAllowedJob(pj) then
                local ci = P.PlayerData.charinfo or {}
                local meta = P.PlayerData.metadata or {}
                local cid = P.PlayerData.citizenid
                local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')

                table.insert(units, {
                    citizenid = cid,
                    source = P.PlayerData.source,
                    name = (name ~= '' and name) or 'Medic',
                    phone = ci.phone or ci.phone_number or meta.phone or meta.phonenumber or '',
                    callsign = PlayerCallsigns[cid] or meta.callsign or meta.mdt_callsign or '',
                    rank = PlayerRosterRanks[cid] or '',
                    job = pj,
                    department = P.PlayerData.job.label or pj,
                    grade = (P.PlayerData.job.grade and P.PlayerData.job.grade.level) or 0,
                    duty = (P.PlayerData.job.onduty and 'on_duty') or 'off_duty',
                    status = boardStatus(cid, P.PlayerData.job.onduty),
                    unit = PFEmsUnits and PFEmsUnits.UnitOf(cid) or nil,
                })
            end
        end

        cb(units)
    end)
end)

RegisterNetEvent('pf_emsmdt_dispatch:server:AcceptCall', function(callId)
    local src = source
    local jobName = GetPlayerJob(src)
    if not IsAllowedJob(jobName) or not IsOnDuty(src) then return end

    local call = GetCall(callId)
    if not call then return end

    local Player = QBCore.Functions.GetPlayer(src)
    local citizenid = Player.PlayerData.citizenid

    call.assignedUnits = call.assignedUnits or {}
    local alreadyAssigned = false
    for _, unit in ipairs(call.assignedUnits) do
        if unit == citizenid then
            alreadyAssigned = true
            break
        end
    end

    if not alreadyAssigned then
        table.insert(call.assignedUnits, citizenid)
    end

    UpdateCall(callId, { status = 'accepted', assignedUnits = call.assignedUnits })
    unitsHook('OnCallAccepted', citizenid, call.id)
end)

RegisterNetEvent('pf_emsmdt_dispatch:server:CompleteCall', function(callId)
    local src = source
    local jobName = GetPlayerJob(src)
    if not IsAllowedJob(jobName) or not IsOnDuty(src) then return end

    local call = GetCall(callId)
    if not call then return end
    UpdateCall(call.id, { status = 'completed' })
    unitsHook('OnCallClosed', call.id)
end)

RegisterNetEvent('pf_emsmdt_dispatch:server:DeleteCall', function(callId)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    if not IsAllowedJob(jobName) or not IsOnDuty(src) then return end
    if not IsSupervisor(jobName, gradeLevel) then return end

    local call = GetCall(callId)
    if call and DeleteCall(call.id) then unitsHook('OnCallClosed', call.id) end
end)

-- =====================================================================================
-- Persistent Profile (callsign/status/avatar): table pf_emsmdt_user_profiles (server/schema.lua)
-- =====================================================================================

-- Medics only; a short callsign, a status word and an https image URL (anyone could set any text or
-- URL before, shown to every medic)
local function cleanCallsign(v)
    v = sanitizeText(v, 16)
    return (v ~= '' and v:match('^[%w%- ]+$')) and v or nil
end
local function cleanStatus(v)
    v = sanitizeText(v, 24)
    return (v ~= '' and v:match('^[%w_%-]+$')) and v or nil
end
local function cleanAvatar(v)
    v = sanitizeText(v, 255)
    return (v ~= '' and v:match('^https://[%w%.%-]+/[%w%-%._~:/%?#%[%]@!%$&%(%)%*%+,;=%%]*$')) and v or nil
end

RegisterNetEvent('pf_emsmdt_dispatch:server:SaveProfile', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' then return end
    if not IsAllowedJob(GetPlayerJob(src)) then return end
    if not allowRate(src, 'profile', 2000) then return end

    local callsign, status, avatarUrl = cleanCallsign(data.callsign), cleanStatus(data.status), cleanAvatar(data.avatarUrl)
    if callsign then Player.Functions.SetMetaData('callsign', callsign) end
    if status then Player.Functions.SetMetaData('mdt_status', status) end
    if avatarUrl then Player.Functions.SetMetaData('mdt_avatar', avatarUrl) end

    if hasOxMySQL() and exports.oxmysql then
        local citizenId = Player.PlayerData.citizenid

        exports.oxmysql:execute([[ 
            INSERT INTO pf_emsmdt_user_profiles (citizenId, callsign, status, avatarUrl)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
              callsign = VALUES(callsign),
              status = VALUES(status),
              avatarUrl = VALUES(avatarUrl),
              updatedAt = CURRENT_TIMESTAMP
        ]], { citizenId, callsign, status, avatarUrl })
    end
end)

QBCore.Functions.CreateCallback('pf_emsmdt_dispatch:server:GetUserProfile', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({}) return end

    local citizenId = Player.PlayerData.citizenid
    local result = {
        callsign = (Player.PlayerData.metadata and Player.PlayerData.metadata.callsign) or nil,
        status = (Player.PlayerData.metadata and Player.PlayerData.metadata.mdt_status) or nil,
        avatarUrl = (Player.PlayerData.metadata and Player.PlayerData.metadata.mdt_avatar) or nil
    }

    -- Prefer roster-assigned callsign when present.
    ensureRosterCache(function()
        local rosterCallsign = PlayerCallsigns[citizenId]
        if rosterCallsign and rosterCallsign ~= '' then
            result.callsign = rosterCallsign
        end

        if hasOxMySQL() and exports.oxmysql then
            exports.oxmysql:execute('SELECT callsign, status, avatarUrl FROM pf_emsmdt_user_profiles WHERE citizenId = ? LIMIT 1', { citizenId }, function(rows)
                if rows and rows[1] then
                    -- Callsign remains roster-first.
                    result.status = rows[1].status or result.status
                    result.avatarUrl = rows[1].avatarUrl or result.avatarUrl
                end
                cb(result)
            end)
        else
            cb(result)
        end
    end)
end)

-- =====================================================================================
-- Dashboard Chat (EMS MDT)
-- =====================================================================================
local ChatHistory = {}
local CHAT_HISTORY_MAX = 50

local function pushChatMessage(msg)
    table.insert(ChatHistory, msg)
    while #ChatHistory > CHAT_HISTORY_MAX do
        table.remove(ChatHistory, 1)
    end
end

QBCore.Functions.CreateCallback('pf_emsmdt_dispatch:server:GetChatHistory', function(source, cb)
    local jobName = GetPlayerJob(source)
    if not IsAllowedJob(jobName) then
        cb({})
        return
    end
    cb(ChatHistory)
end)

RegisterNetEvent('pf_emsmdt_dispatch:server:SendChatMessage', function(payload)
    local src = source
    local jobName = GetPlayerJob(src)
    if not IsAllowedJob(jobName) then return end

    if not allowRate(src, 'chat', 1000) then return end
    local text = sanitizeText(payload and payload.message, 500)
    if text == '' then return end

    local msg = {
        name = getMedicName(src),
        citizenId = (QBCore.Functions.GetPlayer(src) and QBCore.Functions.GetPlayer(src).PlayerData and QBCore.Functions.GetPlayer(src).PlayerData.citizenid) or nil,
        message = text,
        createdAt = os.time(),
    }

    pushChatMessage(msg)

    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        local jn = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
        if IsAllowedJob(jn) then
            TriggerClientEvent('pf_emsmdt:client:chatMessage', Player.PlayerData.source, msg)
        end
    end
end)

-- =====================================================================================
-- Dashboard Bulletins: table pf_emsmdt_bulletins (server/schema.lua)
-- =====================================================================================
QBCore.Functions.CreateCallback('pf_emsmdt_dispatch:server:GetDashboard', function(source, cb)
    local jobName = GetPlayerJob(source)
    if not IsAllowedJob(jobName) then
        cb({ bulletins = {}, reports = {} })
        return
    end

    local data = {
        bulletins = {},
        reports = Config.Dashboard and Config.Dashboard.reports or {}
    }

    if not (hasOxMySQL() and exports.oxmysql) then
        data.bulletins = Config.Dashboard and Config.Dashboard.bulletins or {}
        cb(data)
        return
    end

    exports.oxmysql:execute(
        'SELECT id, title, body, UNIX_TIMESTAMP(createdAt) AS createdAt, createdByName FROM pf_emsmdt_bulletins ORDER BY createdAt DESC LIMIT 10',
        {},
        function(rows)
            for _, b in ipairs(rows or {}) do
                table.insert(data.bulletins, {
                    id = b.id,
                    title = b.title,
                    body = b.body,
                    createdAt = tonumber(b.createdAt) or nil,
                    createdByName = b.createdByName
                })
            end
            cb(data)
        end
    )
end)

QBCore.Functions.CreateCallback('pf_emsmdt_dispatch:server:CreateBulletin', function(source, cb, payload)
    local jobName, gradeLevel = GetPlayerJob(source)
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'not_allowed' })
        return
    end

    if tonumber(gradeLevel) < 4 then
        cb({ success = false, error = 'Insufficient rank' })
        return
    end
    if not IsOnDuty(source) then
        cb({ success = false, error = 'off_duty' })
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database not available' })
        return
    end

    local title = sanitizeText(payload and payload.title, 255)
    local body = sanitizeText(payload and payload.body, 4000)
    if title == '' or body == '' then
        cb({ success = false, error = 'Missing title or description' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    local citizenId = Player.PlayerData.citizenid
    local createdByName = getMedicName(source)
    local createdAtUnix = os.time()

    exports.oxmysql:insert(
        'INSERT INTO pf_emsmdt_bulletins (title, body, createdByCitizenId, createdByName) VALUES (?, ?, ?, ?)',
        { title, body, citizenId, createdByName },
        function(insertId)
            local bulletin = {
                id = insertId,
                title = title,
                body = body,
                createdAt = createdAtUnix,
                createdByName = createdByName
            }

            -- to medics only (it went to every player)
            for _, P in pairs(QBCore.Functions.GetQBPlayers()) do
                local jn = P.PlayerData and P.PlayerData.job and P.PlayerData.job.name or nil
                if IsAllowedJob(jn) then TriggerClientEvent('pf_emsmdt:client:bulletinCreated', P.PlayerData.source, bulletin) end
            end
            cb({ success = true, bulletin = bulletin })
        end
    )
end)

-- =====================================================================================
-- Patients (EMS)
-- =====================================================================================
QBCore.Functions.CreateCallback('pf_emsmdt:searchPatients', function(source, cb, data)
    local jobName = GetPlayerJob(source)
    if not IsAllowedJob(jobName) then
        cb({ data = {}, total = 0, error = 'not_allowed' })
        return
    end

    -- bounded search (any page size was accepted, so one request could list every player)
    local query = (type(data) == 'table' and type(data.query) == 'string') and data.query:lower():sub(1, 64) or ''
    local page = math.max(1, math.min(1000, math.floor(tonumber(type(data) == 'table' and data.page) or 1)))
    local size = math.max(1, math.min(25, math.floor(tonumber(type(data) == 'table' and data.pageSize) or 9)))
    local results = {}

    if hasOxMySQL() and exports.oxmysql then
        local like = '%' .. query .. '%'
        exports.oxmysql:execute('SELECT COUNT(*) as c FROM players WHERE charinfo LIKE ? OR citizenid LIKE ?', { like, like }, function(countRows)
            local total = (countRows and countRows[1] and countRows[1].c) or 0
            exports.oxmysql:execute('SELECT citizenid, charinfo FROM players WHERE charinfo LIKE ? OR citizenid LIKE ? LIMIT ? OFFSET ?'
            , { like, like, size, (page-1)*size }, function(rows)
                for _, r in ipairs(rows or {}) do
                    local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
                    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$','%1')
                    results[#results+1] = {
                        citizenId = r.citizenid,
                        name = name ~= '' and name or 'Unknown',
                        dob = ci.birthdate or '',
                        phone = ci.phone or '',
                    }
                end
                cb({ data = results, total = total })
            end)
        end)
        return
    end

    local players = QBCore.Functions.GetQBPlayers()
    for _, P in pairs(players) do
        local cid = P.PlayerData.citizenid or ''
        local ci = P.PlayerData.charinfo or {}
        local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$','%1')
        local phone = ci.phone or ''
        if query == '' or cid:lower():find(query, 1, true) or name:lower():find(query, 1, true) or phone:lower():find(query, 1, true) then
            table.insert(results, {
                citizenId = cid,
                name = name ~= '' and name or 'Unknown',
                dob = ci.birthdate or '',
                phone = phone,
            })
        end
    end
    cb({ data = results, total = #results })
end)

-- ── the Medical tab ──────────────────────────────────────────────────────────────────────────────
-- The patient's documented record comes from pf-ambulancejob's GetMedicalRecord (this MDT is on its
-- caller list). pf-ambulancejob decides who may see it (architecture 6.6: the patient, a medic with the
-- patient or who treated them in the last 24 h, staff of an admitted patient, physicians) and audits
-- every read. The page gets plain text lines (it shows them as text) plus the structured record.
local MEDICAL_LINES = 50

local function humanize(id)
    local s = tostring(id or ''):gsub('_', ' ')
    return (s:gsub('^%l', string.upper))
end

local function stamp(at)
    at = tonumber(at)
    return at and os.date('%Y-%m-%d %H:%M', math.floor(at)) or ''
end

local function clip(text) return sanitizeText(text, 200) end

local function medicalSection(src, cid)
    local out = { available = false, injuries = {}, conditions = {}, medications = {}, allergies = {}, treatments = {}, admissions = {} }
    if GetResourceState('pf-ambulancejob') ~= 'started' then out.error = 'unavailable' return out, nil end
    local P = QBCore.Functions.GetPlayer(src)
    local viewerCid = P and P.PlayerData and P.PlayerData.citizenid
    local purpose = (viewerCid == cid) and 'self' or 'treatment'
    local ok, res = pcall(function() return exports['pf-ambulancejob']:GetMedicalRecord(cid, { viewer = src, purpose = purpose }) end)
    if not ok or type(res) ~= 'table' then out.error = 'unavailable' return out, nil end
    if res.ok ~= true or type(res.record) ~= 'table' then out.error = tostring(res.error or 'unavailable'):sub(1, 32) return out, nil end
    local r = res.record
    out.available = true
    for _, inj in ipairs(type(r.injuries) == 'table' and r.injuries or {}) do
        if #out.injuries >= MEDICAL_LINES then break end
        if type(inj) == 'table' then
            local where = inj.region and humanize(inj.region) or (inj.structure and humanize(inj.structure)) or nil
            local line = tostring(inj.label or humanize(inj.type))
            if where then line = line .. ', ' .. where end
            if tonumber(inj.severity) then line = line .. (' (severity %d)'):format(math.floor(tonumber(inj.severity))) end
            if inj.stage then line = line .. ' - ' .. humanize(inj.stage) end
            out.injuries[#out.injuries + 1] = clip(line)
        end
    end
    for _, d in ipairs(type(r.diagnoses) == 'table' and r.diagnoses or {}) do
        if #out.conditions >= MEDICAL_LINES then break end
        if type(d) == 'table' then
            local line = tostring(d.label or humanize(d.injuryType))
            if d.structure then line = line .. ' (' .. humanize(d.structure) .. ')' end
            out.conditions[#out.conditions + 1] = clip(line)
        end
    end
    for _, m in ipairs(type(r.prescriptions) == 'table' and r.prescriptions or {}) do
        if #out.medications >= MEDICAL_LINES then break end
        if type(m) == 'table' then
            local line = tostring(m.label or m.drug or m.item or m.name or 'Prescription')
            local dose = m.dose or m.dosage
            if dose then line = line .. ' ' .. tostring(dose) end
            if m.state then line = line .. ' (' .. humanize(m.state) .. ')' end
            out.medications[#out.medications + 1] = clip(line)
        end
    end
    for _, t in ipairs(type(r.treatments) == 'table' and r.treatments or {}) do
        if #out.treatments >= MEDICAL_LINES then break end
        if type(t) == 'table' then
            out.treatments[#out.treatments + 1] = clip(('%s %s (%s)'):format(stamp(t.at), humanize(t.action), humanize(t.result)))
        end
    end
    for _, a in ipairs(type(r.admissions) == 'table' and r.admissions or {}) do
        if #out.admissions >= MEDICAL_LINES then break end
        if type(a) == 'table' then
            out.admissions[#out.admissions + 1] = clip(('%s %s - %s'):format(stamp(a.arrivedAt), humanize(a.hospitalId), humanize(a.state)))
        end
    end
    return out, r
end

-- The profile always answers: before the schema is in place it says so, and a database that never
-- answers (oxmysql does not call back on an SQL error) ends in a timeout reply instead of a stuck page.
local PROFILE_TIMEOUT_MS = 8000
QBCore.Functions.CreateCallback('pf_emsmdt:getPatientProfile', function(source, cb, data)
    local answer, replied = cb, false
    local function reply(payload)
        if replied then return end
        replied = true
        answer(payload)
    end
    cb = reply

    local jobName = GetPlayerJob(source)
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'not_allowed' })
        return
    end

    local citizenId = data and (data.citizenId or data.id) or ''
    citizenId = tostring(citizenId or '')
    if citizenId == '' or #citizenId > 64 then
        cb({ success = false, error = 'missing_citizenId' })
        return
    end

    local function calcAge(dob)
        if type(dob) ~= 'string' then return nil end
        local y, m, d = dob:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
        y, m, d = tonumber(y), tonumber(m), tonumber(d)
        if not y or not m or not d then return nil end
        local now = os.date('*t')
        local age = now.year - y
        if (now.month < m) or (now.month == m and now.day < d) then age = age - 1 end
        if age < 0 or age > 130 then return nil end
        return age
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'no_db' })
        return
    end
    if not (PFEmsSchema and PFEmsSchema.Ready()) then
        cb({ success = false, error = 'not_ready' })
        return
    end
    SetTimeout(PROFILE_TIMEOUT_MS, function() reply({ success = false, error = 'timeout' }) end)

    -- the Medical tab and the PCR list (both decided and read on the server, before the async queries)
    local medical, record = medicalSection(source, citizenId)
    local pcrs = {}
    if PFEmsPcr and PFEmsPcr.ListForViewer then
        local okL, list = pcall(PFEmsPcr.ListForViewer, source, citizenId, medical.available == true)
        if okL and type(list) == 'table' then pcrs = list end
    end

    exports.oxmysql:execute('SELECT citizenid, charinfo, metadata FROM players WHERE citizenid = ? LIMIT 1', { citizenId }, function(rows)
        local r = rows and rows[1] or nil
        if not r then
            cb({ success = false, error = 'not_found' })
            return
        end

        local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
        local meta = type(r.metadata) == 'string' and json.decode(r.metadata) or r.metadata or {}

        local firstname = tostring(ci.firstname or '')
        local lastname = tostring(ci.lastname or '')
        local fullName = ((firstname or '') .. ' ' .. (lastname or '')):gsub('^%s*(.-)%s*$','%1')

        local gender = ci.gender
        if type(gender) == 'number' then
            if gender == 0 then gender = 'Male'
            elseif gender == 1 then gender = 'Female'
            else gender = 'Unknown' end
        end
        if type(gender) ~= 'string' or gender == '' then gender = 'Unknown' end

        local profile = {
            citizenId = r.citizenid,
            firstname = firstname,
            lastname = lastname,
            name = fullName ~= '' and fullName or 'Unknown',
            dob = ci.birthdate or '',
            age = calcAge(ci.birthdate),
            gender = gender,
            nationality = ci.nationality or '',
            phone = ci.phone or '',
            bloodtype = meta.bloodtype or meta.bloodType or meta.blood_type or '',
            injuries = medical.injuries,
            medical = medical,
            medicalRecord = record,
            pcrs = pcrs,
            notes = {},
        }

        exports.oxmysql:execute('SELECT text, author, createdAt FROM pf_emsmdt_patient_notes WHERE citizenId = ? ORDER BY createdAt DESC LIMIT 50', { citizenId }, function(nrows)
            profile.notes = nrows or {}

            -- (the old PCR count read patient_care_reports, a table nothing writes, by a missing column;
            -- profile.pcrs above comes from this MDT's own PCRs)
            cb({ success = true, profile = profile })
        end)
    end)
end)

RegisterNetEvent('pf_emsmdt:addPatientNote', function(data)
    local src = source
    local jobName = GetPlayerJob(src)
    if not IsAllowedJob(jobName) or not IsOnDuty(src) then return end
    if not (hasOxMySQL() and exports.oxmysql) then return end
    if type(data) ~= 'table' or not allowRate(src, 'note', 2000) then return end

    local citizenId = sanitizeText(data.citizenId, 50)
    local text = sanitizeText(data.text, 2000)
    if citizenId == '' or text == '' then return end

    -- only for a real citizen
    exports.oxmysql:execute('SELECT 1 AS ok FROM players WHERE citizenid = ? LIMIT 1', { citizenId }, function(rows)
        if not (rows and rows[1]) then return end
        exports.oxmysql:insert('INSERT INTO pf_emsmdt_patient_notes (citizenId, text, author) VALUES (?, ?, ?)', { citizenId, text, getMedicName(src) })
    end)
end)

-- Injury integration helper
-- An on-duty medic next to the patient (it answered anyone, so any client could turn server ids into
-- citizen ids and names)
QBCore.Functions.CreateCallback('pf-emsmdt:server:getCitizenData', function(source, cb, targetId)
    local targetSrc = tonumber(targetId)
    if not targetSrc or not IsAllowedJob(GetPlayerJob(source)) or not IsOnDuty(source) then
        cb(nil)
        return
    end
    local a, b = GetEntityCoords(GetPlayerPed(source)), GetEntityCoords(GetPlayerPed(targetSrc))
    if #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) > 5.0 then
        cb(nil)
        return
    end

    local Target = QBCore.Functions.GetPlayer(targetSrc)
    if Target and Target.PlayerData and Target.PlayerData.citizenid then
        local ci = Target.PlayerData.charinfo or {}
        cb({
            citizenid = Target.PlayerData.citizenid,
            firstname = ci.firstname or 'Unknown',
            lastname = ci.lastname or 'Unknown'
        })
        return
    end

    cb(nil)
end)

print('^2[pf-emsmdt]^7 EMS server main loaded (EMS-only)')
