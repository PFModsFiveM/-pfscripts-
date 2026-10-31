local QBCore = PFMdt.GetCore()

if not QBCore then
    print('[pf-policemdt] CRITICAL ERROR: Failed to get QBCore object. Resource will not function.')
    print('[pf-policemdt] Please ensure pfm-core is started before pf-policemdt-DEV in your server.cfg')
    return
end

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end

-- ============================================================================
-- PHONE INTEGRATION HELPERS
-- ============================================================================
-- Private phone retrieval method mappings (not configurable)
-- Scripts:
--   'qb-phone'    - uses charinfo.phone or charinfo.phone_number
--   'lb-phone'    - uses exports['lb-phone']:GetEquippedPhoneNumber(source)
--   'tgg-phone'   - uses exports['yseries']:GetPhoneNumberBySourceId(source)
local PHONE_METHOD = {
    ['qb-phone'] = 'charinfo',    
    ['lb-phone'] = 'export',      
    ['tgg-phone'] = 'export'      
}

-- Private phone field names for charinfo method
local PHONE_FIELDS = {
    ['qb-phone'] = { 'phone', 'phone_number' },
    ['lb-phone'] = { 'phone', 'phone_number', 'phonenumber' },
    ['tgg-phone'] = { 'phone', 'phone_number', 'phonenumber' }
}

-- Retrieves phone number based on configured phone script
local function GetPlayerPhone(Player)
    if not Player or not Player.PlayerData then return '' end
    
    local phoneScript = Config.Phone or 'qb-phone'
    local method = PHONE_METHOD[phoneScript] or 'charinfo'
    
    -- Method 1: Use phone script exports
    if method == 'export' then
        if phoneScript == 'lb-phone' then
            local equipped = exports['lb-phone']:GetEquippedPhoneNumber(Player.PlayerData.source)
            if equipped then return equipped end
        elseif phoneScript == 'tgg-phone' then
            local phone = exports['yseries']:GetPhoneNumberBySourceId(Player.PlayerData.source)
            if phone then return phone end
        end
        -- Fallback to charinfo if export fails
        method = 'charinfo'
    end
    
    -- Method 2: Retrieve from charinfo/metadata
    local dataSource
    if method == 'metadata' then
        dataSource = Player.PlayerData.metadata or {}
    else
        dataSource = Player.PlayerData.charinfo or {}
    end
    
    -- Try configured field names first
    local fieldNames = PHONE_FIELDS[phoneScript] or { 'phone', 'phone_number' }
    for _, fieldName in ipairs(fieldNames) do
        if dataSource[fieldName] then
            return dataSource[fieldName]
        end
    end
    
    -- Ultimate fallback: try all common field names
    return dataSource.phone or dataSource.phone_number or dataSource.phonenumber or ''
end

-- ============================================================================
-- GARAGE INTEGRATION HELPERS
-- ============================================================================
-- Private garage retrieval method mappings (not configurable)
-- Scripts:
--   'qb-garages'  - uses database query (player_vehicles table)
--   'cd-garages'  - uses exports['cd-garages']:GetOwnedVehicles(citizenId)
--   'jg-garages'  - uses exports['jg-garages']:GetOwnedVehicles(citizenId)
local GARAGE_METHOD = {
    ['qb-garages'] = 'database',    
    ['cd-garages'] = 'export',      
    ['jg-garages'] = 'export'       
}

-- Retrieves player vehicles based on configured garage script
local function GetPlayerVehicles(citizenId)
    if not citizenId or citizenId == '' then return {} end
    
    local garageScript = Config.Garage or 'qb-garages'
    local method = GARAGE_METHOD[garageScript] or 'database'
    
    local vehicles = {}
    
    -- Method 1: Use garage script exports
    if method == 'export' then
        if garageScript == 'cd-garages' then
            if exports['cd-garages'] then
                vehicles = exports['cd-garages']:GetOwnedVehicles(citizenId) or {}
            end
        elseif garageScript == 'jg-garages' then
            if exports['jg-garages'] then
                vehicles = exports['jg-garages']:GetOwnedVehicles(citizenId) or {}
            end
        end
        -- If export method fails or returns empty, fall back to database
        if #vehicles == 0 then
            method = 'database'
        end
    end
    
    -- Method 2: Query player_vehicles table directly
    if method == 'database' then
        if hasOxMySQL() and exports.oxmysql then
            local result = promise.new()
            exports.oxmysql:execute(
                'SELECT plate, vehicle FROM player_vehicles WHERE citizenid = ? ORDER BY plate LIMIT 100',
                { citizenId },
                function(rows)
                    vehicles = rows or {}
                    result:resolve(true)
                end
            )
            Citizen.Await(result)
        end
    end
    
    return vehicles
end

-- Active calls storage
local ActiveCalls = {}
local CallIdCounter = 1

-- Chat system storage
local ChatMessages = {}
local PlayerCallsigns = {}
local PlayerRosterRanks = {}
local PlayerStatuses = {}
local PlayerDuties = {}

local broadcastUnitsUpdate
-- defined further down; declared here so the callout handler and clearCall above them can call them
local CreateCall, DeleteCall

local RosterCache = { at = 0, ttl = 60 }

-- Auto Calls cooldown storage (per source, per type)
local AutoCallLastTriggered = {}

-- Function to check if oxmysql is available
local function hasOxMySQL()
    return exports and exports.oxmysql ~= nil
end

local function isESXFramework()
    return PFMdt and PFMdt.GetFrameworkName and PFMdt.GetFrameworkName() == 'esx'
end

local _esxCompatEnsured = false
local _esxUserLicensesExists = nil
local _esxUserSkinsExists = nil

-- Lua tables passed by value; keep explicit setters for cached vars.
local function setEsxUserLicensesExists(v) _esxUserLicensesExists = v end
local function setEsxUserSkinsExists(v) _esxUserSkinsExists = v end

-- Override helpers to keep cache in sync
local function esxHasUserLicensesCached()
    if _esxUserLicensesExists ~= nil then return _esxUserLicensesExists == true end
    local p = promise.new()
    exports.oxmysql:execute(
        'SELECT COUNT(*) AS c FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = "user_licenses"',
        {},
        function(rows)
            setEsxUserLicensesExists((rows and rows[1] and tonumber(rows[1].c) or 0) > 0)
            p:resolve(true)
        end
    )
    Citizen.Await(p)
    return _esxUserLicensesExists == true
end

local function esxHasUserSkinsCached()
    if _esxUserSkinsExists ~= nil then return _esxUserSkinsExists == true end
    local p = promise.new()
    exports.oxmysql:execute(
        'SELECT COUNT(*) AS c FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = "userskins"',
        {},
        function(rows)
            setEsxUserSkinsExists((rows and rows[1] and tonumber(rows[1].c) or 0) > 0)
            p:resolve(true)
        end
    )
    Citizen.Await(p)
    return _esxUserSkinsExists == true
end
local function ensureEsxCompatTablesOnce()
    if _esxCompatEnsured then return end
    if not (hasOxMySQL() and exports.oxmysql) then return end
    if not isESXFramework() then return end

    local p = promise.new()
    exports.oxmysql:execute(
        [[
            CREATE TABLE IF NOT EXISTS `pf_mdt_esx_license_suspensions` (
              `identifier` VARCHAR(64) NOT NULL,
              `license_type` VARCHAR(32) NOT NULL,
              `expires_at` DATETIME NULL,
              `stored_types` LONGTEXT NULL,
              `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
              PRIMARY KEY (`identifier`, `license_type`),
              KEY `idx_pf_mdt_esx_license_suspensions_expires` (`expires_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        {},
        function()
            p:resolve(true)
        end
    )
    Citizen.Await(p)
    _esxCompatEnsured = true
end

local function esxLicenseTypesFor(mdtLicenseType)
    local t = tostring(mdtLicenseType or ''):lower()
    if t == 'driver' then return { 'drive', 'drive_bike', 'drive_truck' } end
    if t == 'weapon' then return { 'weapon' } end
    if t == 'business' then return { 'business' } end
    return {}
end

local function esxRestoreExpiredSuspensions(identifier)
    ensureEsxCompatTablesOnce()
    if not (hasOxMySQL() and exports.oxmysql) then return end
    if not isESXFramework() then return end
    if not esxHasUserLicensesCached() then return end
    identifier = tostring(identifier or '')
    if identifier == '' then return end

    local nowStr = os.date('%Y-%m-%d %H:%M:%S')
    local p = promise.new()
    exports.oxmysql:execute(
        'SELECT license_type, expires_at, stored_types FROM pf_mdt_esx_license_suspensions WHERE identifier = ? AND expires_at IS NOT NULL AND expires_at <= ?',
        { identifier, nowStr },
        function(rows)
            if not rows or #rows == 0 then
                p:resolve(true)
                return
            end

            local remaining = #rows
            for _, r in ipairs(rows) do
                local stored = {}
                if type(r.stored_types) == 'string' and r.stored_types ~= '' then
                    local ok, parsed = pcall(json.decode, r.stored_types)
                    if ok and type(parsed) == 'table' then stored = parsed end
                end

                if stored and type(stored) == 'table' then
                    for _, lt in ipairs(stored) do
                        if lt and lt ~= '' then
                            exports.oxmysql:execute(
                                'INSERT IGNORE INTO user_licenses (type, owner) VALUES (?, ?)',
                                { tostring(lt), identifier }
                            )
                        end
                    end
                end

                exports.oxmysql:execute(
                    'DELETE FROM pf_mdt_esx_license_suspensions WHERE identifier = ? AND license_type = ?',
                    { identifier, tostring(r.license_type) },
                    function()
                        remaining = remaining - 1
                        if remaining <= 0 then
                            p:resolve(true)
                        end
                    end
                )
            end
        end
    )
    Citizen.Await(p)
end

local function esxGetLicenseState(identifier)
    ensureEsxCompatTablesOnce()
    identifier = tostring(identifier or '')
    if identifier == '' or not (hasOxMySQL() and exports.oxmysql) or not isESXFramework() then
        return { driver = false, weapon = false, business = false }, {}
    end

    if not esxHasUserLicensesCached() then
        -- Server doesn't use esx_license; don't hang and just report no licenses.
        local suspensions = {}
        local p = promise.new()
        exports.oxmysql:execute(
            'SELECT license_type, expires_at FROM pf_mdt_esx_license_suspensions WHERE identifier = ?',
            { identifier },
            function(rows)
                for _, r in ipairs(rows or {}) do
                    if r.license_type and r.expires_at then
                        suspensions[tostring(r.license_type)] = tostring(r.expires_at)
                    end
                end
                p:resolve(true)
            end
        )
        Citizen.Await(p)
        return { driver = false, weapon = false, business = false }, suspensions
    end

    -- Auto-restore any expired suspensions first
    esxRestoreExpiredSuspensions(identifier)

    local suspensions = {}
    do
        local p = promise.new()
        exports.oxmysql:execute(
            'SELECT license_type, expires_at FROM pf_mdt_esx_license_suspensions WHERE identifier = ?',
            { identifier },
            function(rows)
                for _, r in ipairs(rows or {}) do
                    if r.license_type and r.expires_at then
                        suspensions[tostring(r.license_type)] = tostring(r.expires_at)
                    end
                end
                p:resolve(true)
            end
        )
        Citizen.Await(p)
    end

    local ownedTypes = {}
    do
        local p = promise.new()
        exports.oxmysql:execute(
            'SELECT type FROM user_licenses WHERE owner = ?',
            { identifier },
            function(rows)
                for _, r in ipairs(rows or {}) do
                    if r.type then ownedTypes[tostring(r.type)] = true end
                end
                p:resolve(true)
            end
        )
        Citizen.Await(p)
    end

    local function hasAny(types)
        for _, t in ipairs(types) do
            if ownedTypes[t] then return true end
        end
        return false
    end

    return {
        driver = hasAny(esxLicenseTypesFor('driver')) and suspensions.driver == nil,
        weapon = hasAny(esxLicenseTypesFor('weapon')) and suspensions.weapon == nil,
        business = hasAny(esxLicenseTypesFor('business')) and suspensions.business == nil,
    }, suspensions
end

-- Load callsigns from database on startup
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

    exports.oxmysql:fetch('SELECT citizenid, callsign, rank FROM pf_mdt_roster WHERE citizenid IS NOT NULL AND citizenid != ""', {}, function(results)
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

-- server-only (roster.lua): a net event let any client force roster reloads and unit broadcasts
AddEventHandler('pf_mdt:server:RosterUpdated', function()
    RosterCache.at = 0
    if broadcastUnitsUpdate then
        broadcastUnitsUpdate()
    end
end)

local function loadCallsignsFromDB()
    if not hasOxMySQL() then
        dprint('[pf-policemdt] oxmysql not available, skipping roster cache load')
        return
    end

    ensureRosterCache(function(ok)
        if ok then
            local n = 0
            for _ in pairs(PlayerCallsigns or {}) do n = n + 1 end
            dprint('[pf-policemdt] Loaded roster cache for ' .. n .. ' officers')
        else
            dprint('[pf-policemdt] Failed to load roster cache')
        end
    end)
end

-- Load callsigns on resource start
SetTimeout(1000, loadCallsignsFromDB)

--[[
    Call object structure:
    {
        id = "DISP-0001",
        title = "Gun Shot",
        status = "pending", -- pending, accepted, completed
        priority = 2, -- 1-3
        locationLabel = "Grove St",
        coords = { x = 123.45, y = 456.78, z = 21.0 },
        createdAt = os.time(),
        createdBy = "system",
        assignedUnits = { citizenid1, citizenid2 }
    }
]]

-- Helper Functions

local function GenerateCallId()
    local id = string.format("DISP-%04d", CallIdCounter)
    CallIdCounter = CallIdCounter + 1
    return id
end

local function getAutoCfg()
    return Config and Config.DispatchAutoCalls or nil
end

local function isAutoCallsEnabled()
    local cfg = getAutoCfg()
    return cfg and cfg.Enabled == true
end

local function autoChancePasses()
    local cfg = getAutoCfg()
    -- Backward compat:
    --   cfg.Chance (0..1)
    -- Current schema:
    --   cfg.GlobalChance (0..1 multiplier; if >1 treat as percent)
    local chance = 1.0

    if cfg and cfg.GlobalChance ~= nil then
        chance = tonumber(cfg.GlobalChance) or 0.0
        if chance > 1.0 then
            chance = chance / 100.0
        end
    elseif cfg and cfg.Chance ~= nil then
        chance = tonumber(cfg.Chance) or 0.0
    end

    if chance >= 1.0 then return true end
    if chance <= 0.0 then return false end
    return math.random() <= chance
end

local function shouldIgnoreSourceAsPolice(src)
    local cfg = getAutoCfg()
    if not cfg or cfg.IgnorePolice ~= true then return false end
    local jobName = nil
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.job then
        jobName = Player.PlayerData.job.name
    end
    return jobName and Config and Config.AllowedJobs and Config.AllowedJobs[jobName] == true
end

local function canTriggerAutoCall(src, key, cooldownSeconds)
    AutoCallLastTriggered[src] = AutoCallLastTriggered[src] or {}
    local last = tonumber(AutoCallLastTriggered[src][key]) or 0
    local now = os.time()
    if (now - last) < (tonumber(cooldownSeconds) or 0) then
        return false
    end
    AutoCallLastTriggered[src][key] = now
    return true
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

local function broadcastNewCall(call)
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        local jobName = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
        if jobName and Config and Config.AllowedJobs and Config.AllowedJobs[jobName] == true then
            TriggerClientEvent('pf_mdt:dispatch:newCall', Player.PlayerData.source, call)
        end
    end
end

local function GetPlayerJob(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil, nil end
    return Player.PlayerData.job.name, Player.PlayerData.job.grade.level
end

local function IsAllowedJob(jobName)
    return Config.AllowedJobs[jobName] == true
end

local function IsSupervisor(jobName, gradeLevel)
    if not Config.SupervisorGrades[jobName] then return false end
    return Config.SupervisorGrades[jobName][gradeLevel] == true
end

-- Debounce call list broadcasts (reduces dispatch lag / spam)
local _callsBroadcastQueued = false
local _callsBroadcastDelayMs = 200

local function BroadcastCallsUpdateNow()
    -- Prepare a shallow copy with assigned officer names for UI
    local callsArray = {}
    local Players = QBCore.Functions.GetQBPlayers()
    local nameByCitizen = {}
    for _, P in pairs(Players) do
        local char = P.PlayerData.charinfo
        local fullname = char and (char.firstname .. " " .. char.lastname) or "Officer"
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

    -- Send updated calls to all relevant clients (police jobs)
    for _, Player in pairs(Players) do
        if IsAllowedJob(Player.PlayerData.job.name) then
            TriggerClientEvent("pf_mdt_dispatch:client:CallsUpdated", Player.PlayerData.source, callsArray)
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

broadcastUnitsUpdate = function()
    -- Broadcast current units to all police officers
    local Players = QBCore.Functions.GetQBPlayers()
    ensureRosterCache(function()
        local unitsList = {}

        for _, Player in pairs(Players) do
            if IsAllowedJob(Player.PlayerData.job.name) then
                local cid = Player.PlayerData.citizenid
                local charinfo = Player.PlayerData.charinfo or {}
                local meta = Player.PlayerData.metadata or {}
                local name = (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')

                table.insert(unitsList, {
                    name = name:gsub('^%s*(.-)%s*$', '%1'),
                    phone = GetPlayerPhone(Player),
                    callsign = PlayerCallsigns[cid] or meta.callsign or meta.mdt_callsign or ('UNIT-' .. (cid or ''):sub(1, 4)),
                    rank = PlayerRosterRanks[cid] or '',
                    job = Player.PlayerData.job.name,
                    grade = (Player.PlayerData.job.grade and (Player.PlayerData.job.grade.label or Player.PlayerData.job.grade.level)) or 'Officer',
                    duty = meta.mdt_duty or PlayerDuties[cid] or ((Player.PlayerData.job.onduty and 'on_duty') or 'off_duty'),
                    status = meta.mdt_status or PlayerStatuses[cid] or 'available'
                })
            end
        end

        for _, Player in pairs(Players) do
            if IsAllowedJob(Player.PlayerData.job.name) then
                TriggerClientEvent('pf_mdt:client:UnitsUpdated', Player.PlayerData.source, unitsList)
            end
        end
    end)
end

-- Dispatch callouts (civilian-triggered)
local CalloutCooldowns = {} -- [src] = { [type]=lastMs }

local function getCalloutConfig(calloutType)
    local t = tostring(calloutType or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    if t == '' then return nil, '' end
    local cfg = Config and Config.DispatchCallouts and Config.DispatchCallouts[t] or nil
    if not cfg or cfg.enabled == false then return nil, t end
    return cfg, t
end

local function getCalloutCooldownMs(cfg)
    local cd = tonumber(cfg and cfg.cooldownSeconds) or tonumber(Config and Config.DispatchCalloutsDefaultCooldownSeconds) or 30
    if cd < 0 then cd = 0 end
    return math.floor(cd * 1000)
end

local function shouldCreateCallout(calloutType, cfg)
    -- Per spec: robberies and GTA always alert (ignore chance)
    if calloutType == 'robbery' or calloutType == 'gta' then
        return true
    end

    local chance = tonumber(cfg and cfg.chance) or 100
    if chance >= 100 then return true end
    if chance <= 0 then return false end
    return math.random(100) <= chance
end

local function sanitizeCoords(coords)
    if type(coords) ~= 'table' then return nil end
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function sanitizeLabel(label)
    label = tostring(label or '')
    label = label:gsub('[\r\n\t]', ' ')
    if #label > 64 then
        label = label:sub(1, 64)
    end
    if label:gsub('%s+', '') == '' then return 'Unknown' end
    return label
end

local function handleDispatchCallout(src, calloutType, coords, locationLabel)
    local cfg, t = getCalloutConfig(calloutType)
    if not cfg then return false end

    coords = sanitizeCoords(coords)
    if not coords then return false end
    if not PFMdtAccess.NearCaller(src, coords) then return false end
    locationLabel = sanitizeLabel(locationLabel)

    CalloutCooldowns[src] = CalloutCooldowns[src] or {}
    local now = GetGameTimer()
    local last = tonumber(CalloutCooldowns[src][t]) or 0
    local cdMs = getCalloutCooldownMs(cfg)
    if cdMs > 0 and (now - last) < cdMs then
        return false
    end
    CalloutCooldowns[src][t] = now

    if not shouldCreateCallout(t, cfg) then
        return false
    end

    local title = tostring(cfg.title or t)
    local priority = tonumber(cfg.priority) or 2
    if priority < 1 then priority = 1 end
    if priority > 3 then priority = 3 end

    CreateCall({
        title = title,
        priority = priority,
        locationLabel = locationLabel,
        coords = coords,
        createdBy = 'system'
    })
    return true
end

RegisterNetEvent('pf_mdt_dispatch:server:CreateCallout', function(calloutType, coords, locationLabel)
    local src = source
    dprint('[MDT DEBUG] CreateCallout received from ' .. src .. ': type=' .. tostring(calloutType))
    handleDispatchCallout(src, calloutType, coords, locationLabel)
end)

-- Allow other server scripts to trigger callouts without a player source.
exports('CreateDispatchCallout', function(calloutType, coords, locationLabel)
    return handleDispatchCallout(0, calloutType, coords, locationLabel)
end)

-- Call Management Functions

function CreateCall(callData)
    local id = GenerateCallId()
    local numericId = CallIdCounter - 1

    local call = {
        id = id,
        callId = numericId,
        callType = callData.callType or callData.type or nil,
        code = callData.code or nil,
        title = callData.title or "Unknown Incident",
        description = callData.description or nil,
        suspect = callData.suspect or nil,
        status = callData.status or "pending",
        priority = callData.priority or 2,
        locationLabel = callData.locationLabel or "Unknown Location",
        coords = callData.coords or { x = 0.0, y = 0.0, z = 0.0 },
        createdAt = callData.createdAt or os.time(),
        createdBy = callData.createdBy or "system",
        assignedUnits = callData.assignedUnits or {}
    }
    
    ActiveCalls[call.id] = call

    -- Immediate new-call push (used for client-side notification sounds)
    broadcastNewCall(call)

    BroadcastCallsUpdate()
    
    return call
end

-- Public export: create a dispatch call (bypasses callout gating)
exports('CreateDispatchCall', function(callData)
    if type(callData) ~= 'table' then return nil end
    return CreateCall(callData)
end)

-- Server event for external dispatch systems (like lb-dispatches) to send calls to MDT.
-- Server-only: as a net event any client could push any call text to every officer.
AddEventHandler('pf_mdt:server:CreateDispatchFromExternal', function(callData)
    if type(callData) ~= 'table' then return end

    -- Convert lb-dispatches format to MDT format
    local mdtCall = {
        title = callData.alertTitle or callData.title or callData.codeName or '911 Call',
        description = callData.message or callData.description or '',
        code = callData.code or callData.codeName or '911',
        priority = tonumber(callData.priority) or 2,
        coords = callData.coords or { x = 0.0, y = 0.0, z = 0.0 },
        locationLabel = callData.street or callData.locationLabel or 'Unknown Location',
        createdBy = string.format('911:%s', callData.name or callData.caller or 'Civilian'),
        callType = callData.callType or '911_call',
        status = 'pending'
    }
    
    CreateCall(mdtCall)
    
    if isDebugEnabled() then
        dprint('[MDT] Received dispatch call from external system: ' .. mdtCall.title)
    end
end)

-- =========================================================================
-- /911 CALLS (Civilian)
-- =========================================================================

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

    -- For simple single-word keywords, use word-boundary style matching to avoid
    -- false positives like "car" matching inside "scar".
    if k:match('^%w+$') then
        local pat = '%f[%w]' .. _escapePattern(k) .. '%f[%W]'
        return descLower:find(pat) ~= nil
    end

    -- For phrases / hyphenated keywords, plain substring match is usually desired.
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
    for key, t in pairs(types) do
        if type(t) == 'table' and type(t.keywords) == 'table' then
            local hits = 0
            for _, kw in ipairs(t.keywords) do
                if _containsKeyword(desc, kw) then
                    hits = hits + 1
                end
            end
            if hits > 0 then
                table.insert(matches, {
                    key = tostring(key),
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
        return a.key < b.key
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

RegisterNetEvent('pf_mdt_dispatch:server:Create911Call', function(payload)
    local src = source
    local cfg = Config and Config.Dispatch911 or nil
    if not cfg or cfg.Enabled ~= true then return end
    if type(payload) ~= 'table' then return end

    -- Cooldown
    local cd = tonumber(cfg.CooldownSeconds) or 20
    local now = os.time()
    local last = tonumber(_last911[src]) or 0
    if cd > 0 and (now - last) < cd then
        return
    end
    _last911[src] = now

    local maxLen = tonumber(cfg.MaxDescriptionLength) or 200
    local desc = _trim(PFMdtAccess.Text(payload.description, maxLen))
    if desc == '' then return end

    local coords = payload.coords
    if type(coords) ~= 'table' then return end
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then return end
    if not PFMdtAccess.NearCaller(src, { x = x, y = y, z = z }) then return end

    local locationLabel = _trim(PFMdtAccess.Text(payload.locationLabel, 128))
    if locationLabel == '' then locationLabel = 'Unknown Location' end

    -- Check if mfp_lb-dispatches integration is enabled
    local dispatchCfg = Config and Config.Dispatch or {}
    local useLBDispatches = dispatchCfg.UseLBDispatches == true

    -- Resolve caller information
    local callerName = 'Unknown'
    local callerNumber = nil
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.charinfo then
        local ci = Player.PlayerData.charinfo
        callerName = _trim((ci.firstname or '') .. ' ' .. (ci.lastname or ''))
        if callerName == '' then callerName = 'Unknown' end
    end
    if Player and Player.PlayerData and Player.PlayerData.phone then
        callerNumber = Player.PlayerData.phone.number
    end

    -- Route to mfp_lb-dispatches if enabled
    if useLBDispatches then
        local success, err = pcall(function()
            -- lb-dispatches uses lb-tablet's AddDispatch export
            exports['lb-tablet']:AddDispatch({
                message = desc,
                codeName = '911',
                code = '911',
                icon = 'fas fa-phone',
                priority = 2,
                coords = vector3(x, y, z),
                gender = 0,
                name = callerName,
                phone_number = callerNumber or 'Unknown',
                alertTitle = '911 Emergency Call',
                street = locationLabel,
                jobs = { 'police', 'sheriff', 'bcso' }
            })
        end)
        if success then
            if isDebugEnabled() then
                dprint('[MDT] 911 call successfully routed to lb-dispatches')
            end
            TriggerClientEvent('QBCore:Notify', src, 'Emergency services have been notified', 'success')
            return
        else
            -- Log error and fall back to built-in system
            print('^3[pf-policemdt]^7 Failed to send to lb-dispatches: ' .. tostring(err))
            print('^3[pf-policemdt]^7 Falling back to built-in MDT dispatch system')
            -- Fall through to built-in system below
        end
    end

    -- Use built-in MDT dispatch system
    local maxCalls = 1
    if cfg.MultiMatch and cfg.MultiMatch.enabled == true then
        maxCalls = tonumber(cfg.MultiMatch.maxCalls) or 2
    end

    local metas, defaultMeta = classify911Matches(desc, maxCalls)
    if type(metas) ~= 'table' then metas = {} end

    -- If no keywords matched, don't fall back to a configured category title.
    -- Instead, show the player's original /911 description as the call title.
    if #metas == 0 then
        local pr = 2
        if type(defaultMeta) == 'table' and defaultMeta.priority ~= nil then
            pr = tonumber(defaultMeta.priority) or 2
        end
        if pr < 1 then pr = 1 end
        if pr > 3 then pr = 3 end

        local t = desc
        if #t > 64 then
            t = t:sub(1, 61) .. '...'
        end

        metas = {
            {
                callType = '911',
                code = '911',
                title = t,
                priority = pr,
            }
        }
    end

    for i, meta in ipairs(metas) do
        if type(meta) == 'table' then
            local code = _trim(meta.code)
            local title = _trim(meta.title)
            local priority = tonumber(meta.priority) or 2
            if priority < 1 then priority = 1 end
            if priority > 3 then priority = 3 end

            CreateCall({
                callType = meta.callType or '911',
                code = code ~= '' and code or '911',
                title = title ~= '' and title or '911 Call',
                description = desc,
                locationLabel = locationLabel,
                coords = { x = x + 0.0, y = y + 0.0, z = z + 0.0 },
                priority = priority,
                status = 'pending',
                createdBy = '911:' .. tostring(src) .. ':' .. tostring(i),
                suspect = { caller = callerName }
            })
        end
    end
end)

-- ============================================================================
-- Dispatch Auto Calls (Server)
-- ============================================================================

local function createAutoCallFromSource(src, key, payload)
    if not isAutoCallsEnabled() then return false end
    if type(payload) ~= 'table' then return false end
    if shouldIgnoreSourceAsPolice(src) then return false end

    local cfg = getAutoCfg() or {}

    -- Resolve call metadata from current schema (DispatchAutoCalls.Calls)
    -- while keeping backward compatibility with legacy (Codes/Cooldowns).
    local meta = nil
    local cd = 0
    local perChance = nil -- 0..1

    if type(cfg.Calls) == 'table' then
        local mappedKey = key
        if key == 'ShotsFired' then mappedKey = 'Shooting'
        elseif key == 'VehicleTheft' then mappedKey = 'CarJack'
        elseif key == 'Homicide' then mappedKey = 'PlayerDead'
        end

        meta = cfg.Calls[mappedKey] or cfg.Calls[key]
        if type(meta) ~= 'table' then return false end
        if meta.enabled == false then return false end

        local globalChance = 1.0
        if cfg.GlobalChance ~= nil then
            globalChance = tonumber(cfg.GlobalChance) or 0.0
            if globalChance > 1.0 then globalChance = globalChance / 100.0 end
        elseif cfg.Chance ~= nil then
            globalChance = tonumber(cfg.Chance) or 0.0
        end

        local callChance = tonumber(meta.chance)
        if callChance == nil then
            -- If not specified, default to always.
            callChance = 100
        end
        callChance = math.max(0.0, math.min(100.0, callChance))

        perChance = (callChance / 100.0) * math.max(0.0, math.min(1.0, globalChance))
        if perChance <= 0.0 then return false end
        if perChance < 1.0 and math.random() > perChance then return false end

        cd = tonumber(meta.cooldown) or tonumber(meta.cooldownSeconds) or 0
        if cd > 0 and not canTriggerAutoCall(src, key, cd) then
            return false
        end
    else
        -- Legacy schema
        if not autoChancePasses() then return false end

        local codes = cfg and cfg.Codes or nil
        meta = codes and codes[key] or nil
        if not meta then return false end

        cd = (cfg and cfg.Cooldowns and tonumber(cfg.Cooldowns[key])) or 0
        if cd > 0 and not canTriggerAutoCall(src, key, cd) then
            return false
        end
    end

    local coords = payload and payload.coords or nil
    if type(coords) ~= 'table' then return false end
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then return false end
    if not PFMdtAccess.NearCaller(src, { x = x, y = y, z = z }) then return false end

    local locationLabel = sanitizeText(payload.locationLabel, 128)
    if locationLabel == '' then locationLabel = 'Unknown Location' end

    local code = sanitizeText(meta.code, 16)
    local shortTitle = sanitizeText(meta.title, 64)
    local baseDesc = sanitizeText(meta.desc or meta.description, 200)

    local details = ''
    if key == 'ShotsFired' then
        local w = sanitizeText(payload.weaponLabel, 64)
        if w ~= '' then details = (' (%s)'):format(w) end
    elseif key == 'VehicleTheft' then
        local mdl = sanitizeText(payload.modelLabel, 64)
        local plate = sanitizeText(payload.plate, 16)
        if mdl ~= '' and plate ~= '' then
            details = (' (%s %s)'):format(mdl, plate)
        elseif mdl ~= '' then
            details = (' (%s)'):format(mdl)
        elseif plate ~= '' then
            details = (' (%s)'):format(plate)
        end
    elseif key == 'Homicide' then
        local vt = sanitizeText(payload.victimType, 16)
        if vt ~= '' then
            details = (' (%s)'):format(vt)
        end
    end

    local title = (code ~= '' and (code .. ' ') or '') .. (shortTitle ~= '' and shortTitle or 'Call') .. details

    local priority = tonumber(meta.priority) or 2
    if priority < 1 then priority = 1 end
    if priority > 3 then priority = 3 end

    local call = CreateCall({
        callType = key,
        code = code,
        title = title,
        description = baseDesc,
        locationLabel = locationLabel,
        coords = { x = x + 0.0, y = y + 0.0, z = z + 0.0 },
        priority = priority,
        status = 'pending',
        createdBy = 'system',
        suspect = {
            weaponHash = tonumber(payload.weaponHash),
            weaponLabel = sanitizeText(payload.weaponLabel, 64),
            model = tonumber(payload.model) or sanitizeText(payload.model, 64),
            modelLabel = sanitizeText(payload.modelLabel, 64),
            plate = sanitizeText(payload.plate, 16),
            victimType = sanitizeText(payload.victimType, 16),
        }
    })

    -- Console logs (testing requirement)
    if key == 'ShotsFired' then
        dprint(('[MDT DISPATCH] Created call %s at (%s) from src %s'):format(code, locationLabel, tostring(src)))
    elseif key == 'VehicleTheft' then
        local mdl = sanitizeText(payload.modelLabel, 64)
        local plate = sanitizeText(payload.plate, 16)
        dprint(('[MDT DISPATCH] Created call %s vehicle %s plate %s at (%s)'):format(code, mdl ~= '' and mdl or 'Unknown', plate ~= '' and plate or 'Unknown', locationLabel))
    elseif key == 'Homicide' then
        dprint(('[MDT DISPATCH] Created call %s at (%s) from src %s'):format(code, locationLabel, tostring(src)))
    else
        dprint(('[MDT DISPATCH] Created call %s at (%s) from src %s'):format(code, locationLabel, tostring(src)))
    end

    return true
end

RegisterNetEvent('pf_mdt:dispatch:shotsFired', function(payload)
    local src = source
    createAutoCallFromSource(src, 'ShotsFired', payload or {})
end)

RegisterNetEvent('pf_mdt:dispatch:vehicleTheft', function(payload)
    local src = source
    createAutoCallFromSource(src, 'VehicleTheft', payload or {})
end)

RegisterNetEvent('pf_mdt:dispatch:homicide', function(payload)
    local src = source
    createAutoCallFromSource(src, 'Homicide', payload or {})
end)

-- Auth callback
QBCore.Functions.CreateCallback('pf_mdt:auth:canAccess', function(source, cb)
    local jobName = GetPlayerJob(source)
    local allowed = IsAllowedJob(jobName)
    cb({ allowed = allowed })
end)

-- Call list callback aliases (requested API)
QBCore.Functions.CreateCallback('pf_mdt:dispatch:getCalls', function(source, cb)
    local src = source
    local jobName = GetPlayerJob(src)
    if not IsAllowedJob(jobName) then
        cb(nil)
        return
    end

    local callsArray = {}
    for _, call in pairs(ActiveCalls) do
        table.insert(callsArray, call)
    end
    cb(callsArray)
end)

QBCore.Functions.CreateCallback('pf_mdt:dispatch:clearCall', function(source, cb, callId)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    if not IsAllowedJob(jobName) then
        cb(false)
        return
    end
    if not IsSupervisor(jobName, gradeLevel) then
        cb(false)
        return
    end

    local id = tostring(callId or '')
    if id == '' then
        cb(false)
        return
    end

    local ok = DeleteCall(id)
    cb(ok == true)
end)

local function GetCall(callId)
    return ActiveCalls[callId]
end

local function UpdateCall(callId, updates)
    local call = ActiveCalls[callId]
    if not call then return false end
    
    for k, v in pairs(updates) do
        call[k] = v
    end
    
    BroadcastCallsUpdate()
    return true
end

function DeleteCall(callId)
    if not ActiveCalls[callId] then return false end
    ActiveCalls[callId] = nil
    BroadcastCallsUpdate()
    return true
end

-- Server Callbacks

QBCore.Functions.CreateCallback('pf_mdt_dispatch:server:GetCalls', function(source, cb)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    
    if not IsAllowedJob(jobName) then
        cb(nil)
        return
    end
    
    -- Convert ActiveCalls map to array
    local callsArray = {}
    for _, call in pairs(ActiveCalls) do
        table.insert(callsArray, call)
    end
    
    cb(callsArray)
end)

QBCore.Functions.CreateCallback('pf_mdt_dispatch:server:GetUnits', function(source, cb)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    
    if not IsAllowedJob(jobName) then
        dprint('[MDT DEBUG] GetUnits: Player ' .. src .. ' not allowed job')
        cb(nil)
        return
    end
    
    ensureRosterCache(function()
        -- Get online police officers
        local units = {}
        local players = QBCore.Functions.GetQBPlayers()
        for _, P in pairs(players) do
            if P.PlayerData and P.PlayerData.job then
                local playerJobName = P.PlayerData.job.name
                if IsAllowedJob(playerJobName) then
                    local ci = P.PlayerData.charinfo or {}
                    local meta = P.PlayerData.metadata or {}
                    local cid = P.PlayerData.citizenid
                    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')

                    -- Try to get player coordinates
                    local coords = nil
                    if P.PlayerData.source then
                        local ped = GetPlayerPed(tonumber(P.PlayerData.source))
                        if ped > 0 then
                            local pedCoords = GetEntityCoords(ped)
                            coords = { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z }
                        end
                    end

                    table.insert(units, {
                        citizenid = cid,
                        source = P.PlayerData.source,
                        name = (name ~= '' and name) or 'Officer',
                        phone = ci.phone or ci.phone_number or meta.phone or meta.phonenumber or '',
                        callsign = PlayerCallsigns[cid] or meta.callsign or meta.mdt_callsign or '',
                        rank = PlayerRosterRanks[cid] or '',
                        job = playerJobName,
                        department = P.PlayerData.job.label or playerJobName,
                        grade = (P.PlayerData.job.grade and P.PlayerData.job.grade.level) or 0,
                        duty = meta.mdt_duty or PlayerDuties[cid] or ((P.PlayerData.job.onduty and 'on_duty') or 'off_duty'),
                        status = meta.mdt_status or PlayerStatuses[cid] or 'available',
                        coords = coords
                    })
                end
            end
        end

        dprint('[MDT DEBUG] GetUnits: Returning ' .. #units .. ' units to player ' .. src)
        cb(units)
    end)
end)

-- Server Events

RegisterNetEvent("pf_mdt_dispatch:server:CreateCall", function(callData)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    
    if not IsAllowedJob(jobName) then
        TriggerClientEvent('QBCore:Notify', src, "You do not have permission to create calls", "error")
        return
    end
    
    if type(callData) ~= 'table' or not PFMdtAccess.AllowRate(src, 'createCall', 2000) then return end
    local Player = QBCore.Functions.GetPlayer(src)
    local function T(v, n)
        local s = PFMdtAccess.Text(v, n)
        if s:gsub('%s+', '') == '' then return nil end
        return s
    end
    -- only the call fields; status, units and timestamps are the server's
    local coords = sanitizeCoords(callData.coords)
    local priority = math.floor(tonumber(callData.priority) or 2)
    CreateCall({
        callType = T(callData.callType or callData.type, 32),
        code = T(callData.code, 16),
        title = T(callData.title, 64),
        description = T(callData.description, 500),
        locationLabel = T(callData.locationLabel, 128),
        coords = coords,
        priority = math.max(1, math.min(3, priority)),
        createdBy = Player.PlayerData.citizenid
    })
    TriggerClientEvent('QBCore:Notify', src, "Dispatch call created", "success")
end)

RegisterNetEvent("pf_mdt_dispatch:server:AcceptCall", function(callId)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    
    if not IsAllowedJob(jobName) then
        TriggerClientEvent('QBCore:Notify', src, "You do not have permission", "error")
        return
    end
    
    local call = GetCall(callId)
    if not call then
        TriggerClientEvent('QBCore:Notify', src, "Call not found", "error")
        return
    end
    
    local Player = QBCore.Functions.GetPlayer(src)
    local citizenid = Player.PlayerData.citizenid
    
    -- Add unit to assigned units if not already present
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
    
    -- Update status to accepted
    UpdateCall(callId, { status = "accepted", assignedUnits = call.assignedUnits })
    TriggerClientEvent('QBCore:Notify', src, "Call accepted", "success")
end)

RegisterNetEvent("pf_mdt_dispatch:server:CompleteCall", function(callId)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    
    if not IsAllowedJob(jobName) then
        TriggerClientEvent('QBCore:Notify', src, "You do not have permission", "error")
        return
    end
    
    local call = GetCall(callId)
    if not call then
        TriggerClientEvent('QBCore:Notify', src, "Call not found", "error")
        return
    end
    
    -- Delete the call (removes from all officers' view)
    DeleteCall(callId)
    TriggerClientEvent('QBCore:Notify', src, "Call completed and removed", "success")
end)

RegisterNetEvent("pf_mdt_dispatch:server:DeleteCall", function(callId)
    local src = source
    local jobName, gradeLevel = GetPlayerJob(src)
    
    if not IsAllowedJob(jobName) then
        TriggerClientEvent('QBCore:Notify', src, "You do not have permission", "error")
        return
    end
    
    -- Only supervisors can delete calls
    if not IsSupervisor(jobName, gradeLevel) then
        TriggerClientEvent('QBCore:Notify', src, "You do not have permission to delete calls", "error")
        return
    end
    
    local call = GetCall(callId)
    if not call then
        TriggerClientEvent('QBCore:Notify', src, "Call not found", "error")
        return
    end
    
    -- Delete the call
    DeleteCall(callId)
    TriggerClientEvent('QBCore:Notify', src, "Call deleted", "success")
end)

QBCore.Commands.Add("unjail", "Release a player from MDT jail (Admin)", {
    { name = "id", help = "Server ID" }
}, false, function(source, args)
    local src = source
    local targetId = tonumber(args and args[1])
    if not targetId then
        TriggerClientEvent('QBCore:Notify', src, 'Usage: /unjail <id>', 'error')
        return
    end

    local Target = QBCore.Functions.GetPlayer(targetId)
    if not Target then
        TriggerClientEvent('QBCore:Notify', src, 'Player not found', 'error')
        return
    end

    local citizenId = Target.PlayerData and Target.PlayerData.citizenid or nil
    if citizenId and citizenId ~= '' then
        clearActiveJail(citizenId)
    end

    local ok, err = PFMdt.Prison.Unjail(targetId, false)
    if not ok then
        TriggerClientEvent('QBCore:Notify', src, ('Prison Unjail failed: %s'):format(err or 'unknown error'), 'error')
        return
    else
        TriggerClientEvent('pf_mdt:client:ReleaseMdtSentence', targetId)
    end

    TriggerClientEvent('QBCore:Notify', src, ('Unjailed player %s'):format(targetId), 'success')
end, "admin")

if isDebugEnabled() then
    QBCore.Commands.Add("testcall", "Create a test dispatch call", {}, false, function(source, args)
        local src = source
        local ped = GetPlayerPed(src)
        local coords = GetEntityCoords(ped)

        CreateCall({
            title = "Test Dispatch Call",
            priority = 2,
            locationLabel = "Test Location",
            coords = { x = coords.x, y = coords.y, z = coords.z },
            status = "pending",
            assignedUnits = {}
        })

        TriggerClientEvent('QBCore:Notify', src, 'Test call created', 'success')
    end, "admin")
end

-- Initialize
CreateThread(function()
    dprint("^2[PF MDT Dispatch]^7 Server initialized")
end)

-- Expire old calls
CreateThread(function()
    while true do
        local now = os.time()
        local expiry = Config.CallExpirySeconds or 300
        local changed = false
        for id, call in pairs(ActiveCalls) do
            if now - (call.createdAt or now) > expiry then
                ActiveCalls[id] = nil
                changed = true
            end
        end
        if changed then BroadcastCallsUpdate() end
        Wait(60000)
    end
end)

-- ============================================================================
-- Records/Search: Citizens, Vehicles, Warrants, Incidents, Reports, FTO
-- ============================================================================

local function hasRcorePrison()
    return GetResourceState and GetResourceState('rcore_prison') == 'started'
end

local function safeRcore(fn)
    if not hasRcorePrison() then
        return false, 'rcore_prison is not started'
    end
    local ok, res = pcall(fn)
    if not ok then
        return false, tostring(res)
    end
    return true, res
end

-- Resolve vehicle display name via GTA native safely (server may not expose the native)
local function SafeGetVehicleDisplayName(model)
    if type(GetDisplayNameFromVehicleModel) ~= 'function' then return nil end

    -- Convert numeric strings to numbers for hash comparison
    if type(model) == 'string' and tonumber(model) then
        model = tonumber(model)
    end

    local hash = nil
    if type(model) == 'number' then
        hash = model
    elseif type(model) == 'string' then
        if type(GetHashKey) == 'function' then
            local ok, h = pcall(GetHashKey, model)
            if ok and h then hash = h end
        end
    end

    if not hash then return nil end

    local ok, disp = pcall(GetDisplayNameFromVehicleModel, hash)
    if ok and disp and disp ~= '' then
        -- Prefer localized label text if available
        if type(GetLabelText) == 'function' then
            local label = GetLabelText(disp)
            if label and label ~= '' and label ~= 'NULL' then
                return label
            end
        end
        return disp
    end

    return nil
end

-- Resolve vehicle label/brand from QBCore.Shared.Vehicles using model string or hash
local function ResolveVehicleMeta(model, hash)
    local label, brand = nil, nil
    if QBCore and QBCore.Shared and QBCore.Shared.Vehicles then
        if type(model) == 'string' then
            local entry = QBCore.Shared.Vehicles[model]
            if entry then
                label = entry.name
                brand = entry.brand
            end
        end

        -- Try matching by hash if we still have nothing
        local hashToMatch = nil
        if (not label or label == '') then
            if type(model) == 'number' then hashToMatch = model end
            if not hashToMatch and hash and tonumber(hash) then hashToMatch = tonumber(hash) end
            if not hashToMatch and type(model) == 'string' and tonumber(model) then hashToMatch = tonumber(model) end
            if hashToMatch then
                for _, veh in pairs(QBCore.Shared.Vehicles) do
                    if veh and veh.hash and tonumber(veh.hash) == hashToMatch then
                        label = veh.name
                        brand = veh.brand
                        break
                    end
                end
            end
        end

        -- If model is string but keyed by hash in the table (rare), try hash lookup
        if (not label or label == '') and type(model) == 'string' and type(GetHashKey) == 'function' then
            local ok, h = pcall(GetHashKey, model)
            if ok and h then
                for _, veh in pairs(QBCore.Shared.Vehicles) do
                    if veh and veh.hash and tonumber(veh.hash) == h then
                        label = veh.name
                        brand = veh.brand
                        break
                    end
                end
            end
        end
    end
    return label, brand
end

-- Normalize a player_vehicles row into UI-ready vehicle info
local function MapVehicleRow(r)
    if not r then return nil end

    local rawVehicle = r.vehicle
    local vdata = nil

    -- Decode vehicle JSON safely (some servers store plain model strings)
    if type(rawVehicle) == 'string' then
        local trimmed = rawVehicle:gsub('^%s+', '')
        if trimmed:sub(1, 1) == '{' or trimmed:sub(1, 1) == '[' then
            local ok, decoded = pcall(json.decode, rawVehicle)
            if ok and type(decoded) == 'table' then
                vdata = decoded
            end
        end
    elseif type(rawVehicle) == 'table' then
        vdata = rawVehicle
    end

    local model = nil
    local modelHash = nil
    if vdata then
        model = vdata.model or vdata.modelName or vdata.name or vdata.vehicle or vdata.hash or vdata.modelHash
        modelHash = vdata.hash or vdata.modelHash or modelHash
        if not modelHash and type(model) == 'number' then modelHash = model end
    end

    -- If vehicle was stored as plain string or hash, keep it
    if not model and type(rawVehicle) == 'string' and rawVehicle ~= '' then
        model = rawVehicle
    elseif not model and type(rawVehicle) == 'number' then
        model = rawVehicle
    end

    -- Resolve friendly label/brand
    local modelLabel, brand = ResolveVehicleMeta(model, modelHash)
    if not modelLabel then
        local nativeName = SafeGetVehicleDisplayName(model) or SafeGetVehicleDisplayName(modelHash)
        if nativeName and nativeName ~= '' then
            modelLabel = nativeName
        end
    end

    local rawModel = (type(model) == 'string' or type(model) == 'number') and tostring(model) or nil

    -- Fallbacks: prefer raw model string over generic "Vehicle".
    -- Avoid showing numeric hashes in the UI (they look like random numbers).
    if (not modelLabel or modelLabel == '' or (type(modelLabel) == 'string' and modelLabel:lower() == 'vehicle')) and rawModel then
        local s = tostring(rawModel)
        local isHashLike = false
        if s:match('^[%+%-]?%d+%.?0*$') then
            isHashLike = true
        elseif s:lower():match('^0x[%da-f]+$') then
            isHashLike = true
        end

        if not isHashLike then
            modelLabel = rawModel
        end
    end
    if not modelLabel or modelLabel == '' then
        modelLabel = r.plate and ('Unknown Model (' .. r.plate .. ')') or 'Unknown Vehicle'
    end
    modelLabel = tostring(modelLabel):gsub('^%s*(.-)%s*$', '%1')

    -- Extract paint colors from mods JSON
    local primaryColorId, secondaryColorId, pearlId, wheelColorId = nil, nil, nil, nil
    local neonColor, tyreSmokeColor = nil, nil
    do
        local mods = nil
        if type(r.mods) == 'string' and r.mods ~= '' then
            local ok, decoded = pcall(json.decode, r.mods)
            if ok and type(decoded) == 'table' then mods = decoded end
        elseif type(r.mods) == 'table' then
            mods = r.mods
        end
        if type(mods) == 'table' then
            if tonumber(mods.color1) ~= nil then primaryColorId = tonumber(mods.color1) end
            if tonumber(mods.color2) ~= nil then secondaryColorId = tonumber(mods.color2) end
            if tonumber(mods.pearlescentColor) ~= nil then pearlId = tonumber(mods.pearlescentColor) end
            if tonumber(mods.wheelColor) ~= nil then wheelColorId = tonumber(mods.wheelColor) end

            if type(mods.neonColor) == 'table' then neonColor = mods.neonColor end
            if type(mods.tyreSmokeColor) == 'table' then tyreSmokeColor = mods.tyreSmokeColor end
        end
    end

    return {
        plate = r.plate,
        model = rawModel or modelLabel,
        modelLabel = modelLabel,
        brand = brand,
        -- Color IDs from mods JSON for UI mapping
        primaryColorId = primaryColorId,
        secondaryColorId = secondaryColorId,
        pearlescentColorId = pearlId,
        wheelColorId = wheelColorId,
        neonColor = neonColor,
        tyreSmokeColor = tyreSmokeColor,
        status = 'CLEAR',
        ownerName = r.citizenid or 'Unknown',
        activeFlag = r.activeFlag or nil,
        photo = r.vehiclePhoto or nil
    }
end

local function IsManualEntriesEnabled()
    return Config and Config.ManualEntries and Config.ManualEntries.Enabled == true
end

local function MapManualCitizenRow(r)
    if not r then return nil end
    local first = tostring(r.firstname or ''):gsub('^%s*(.-)%s*$', '%1')
    local last = tostring(r.lastname or ''):gsub('^%s*(.-)%s*$', '%1')
    local full = (first .. ' ' .. last):gsub('^%s*(.-)%s*$', '%1')
    if full == '' then full = 'Unknown' end

    return {
        citizenId = tostring(r.citizenId or ''),
        name = full,
        dob = tostring(r.dob or ''),
        phone = tostring(r.phone or ''),
        nationality = tostring(r.nationality or ''),
        job = tostring(r.job or 'Unemployed'),
        licenses = {},
        hasWarrant = false,
        isDangerous = false,
        manualEntry = true,
        gender = tostring(r.gender or ''),
        address = tostring(r.address or ''),
        profilePicture = tostring(r.profilePicture or '')
    }
end

local function MapManualVehicleRow(r)
    if not r then return nil end
    local model = tostring(r.model or '')
    local label = tostring(r.modelLabel or '')
    if label == '' then label = model end
    if label == '' then label = r.plate and ('Unknown Model (' .. tostring(r.plate) .. ')') or 'Unknown Vehicle' end

    return {
        plate = tostring(r.plate or ''),
        model = model ~= '' and model or label,
        modelLabel = label,
        brand = tostring(r.brand or ''),
        primaryColorId = tonumber(r.primaryColorId),
        secondaryColorId = tonumber(r.secondaryColorId),
        pearlescentColorId = nil,
        wheelColorId = nil,
        neonColor = nil,
        tyreSmokeColor = nil,
        status = 'CLEAR',
        ownerName = tostring(r.ownerName or r.ownerCitizenId or 'Unknown'),
        activeFlag = nil,
        photo = tostring(r.vehiclePhoto or ''),
        manualEntry = true
    }
end

-- Appearance helpers (playerskins parsing)
local EyeColorLabels = {
    "Green", "Emerald", "Light Blue", "Ocean Blue", "Light Brown", "Dark Brown",
    "Hazel", "Dark Gray", "Light Gray", "Pink", "Yellow", "Purple",
    "Blackout", "Shades of Gray", "Tequila Sunrise", "Atomic",
    "Warp", "ECola", "Space Ranger", "Ying Yang", "Bullseye", "Lizard", "Dragon", "ExtraTerrestrial"
}

local HairColorLabels = {
    "Black", "Dark Brown", "Brown", "Light Brown", "Dirty Blonde", "Blonde", "Platinum",
    "Ash", "Gray", "White", "Red", "Auburn", "Ginger", "Strawberry Blonde", "Pink",
    "Purple", "Blue", "Green", "Teal", "Mint"
}

local function mapEyeColorLabel(idx)
    local i = tonumber(idx)
    if not i then return nil end
    return EyeColorLabels[i + 1] or 'Unknown'
end

local function mapHairColorLabel(idx)
    local i = tonumber(idx)
    if not i then return nil end
    return HairColorLabels[i + 1] or ('Color ' .. tostring(i))
end

local function deriveSkinToneLabel(headBlend)
    if type(headBlend) ~= 'table' then return nil end
    local a = tonumber(headBlend.skinFirst) or tonumber(headBlend.firstSkin) or tonumber(headBlend.skinFirstId)
    local b = tonumber(headBlend.skinSecond) or tonumber(headBlend.secondSkin) or tonumber(headBlend.skinSecondId)
    local mix = tonumber(headBlend.skinMix) or tonumber(headBlend.mix) or 0.5
    if not a and not b then return nil end
    local avg = ((a or b or 0) + (b or a or 0)) / 2
    local score = avg + mix * 2
    if score <= 3 then return 'Light' end
    if score <= 8 then return 'Medium' end
    return 'Dark'
end

local function buildAppearanceFromPlayerskin(row)
    if not row then return nil end
    local skinData = row.skin
    if type(skinData) == 'string' then
        local ok, decoded = pcall(json.decode, skinData)
        if ok and decoded then
            skinData = decoded
        end
    end
    if type(skinData) ~= 'table' then return { model = row.model or nil } end

    local eyeColor = skinData.eyeColor
    if not eyeColor and skinData.eye_color and skinData.eye_color.item and skinData.eye_color.item >= 0 then
        eyeColor = skinData.eye_color.item
    end

    local hairColor = nil
    local hairHighlight = nil
    if skinData.hair and type(skinData.hair) == 'table' then
        hairColor = skinData.hair.color or skinData.hair.hairColor or skinData.hair.colorID
        hairHighlight = skinData.hair.highlight or skinData.hair.highlightColor or skinData.hair.highlightID
        if not hairColor and skinData.hair.item then
            hairColor = skinData.hair.item -- legacy qb-clothing hair number
        end
    end

    local headBlend = skinData.headBlend or skinData.facemix

    local appearance = {
        model = skinData.model or row.model or nil,
        eyeColor = eyeColor,
        eyeColorLabel = mapEyeColorLabel(eyeColor),
        hairColor = hairColor,
        hairColorLabel = mapHairColorLabel(hairColor),
        hairHighlight = hairHighlight,
        hairHighlightLabel = mapHairColorLabel(hairHighlight),
        skinToneLabel = deriveSkinToneLabel(headBlend)
    }

    return appearance
end

-- Citizens search
QBCore.Functions.CreateCallback('pf_mdt:searchCitizens', function(source, cb, data)
    local query = (data and data.query or ''):lower()
    local page = (data and data.page) or 1
    local size = (data and data.pageSize) or 9
    local allResults = {}

    local function finalizePagedResults()
        table.sort(allResults, function(a, b)
            local an = tostring(a.name or ''):lower()
            local bn = tostring(b.name or ''):lower()
            if an == bn then
                return tostring(a.citizenId or '') < tostring(b.citizenId or '')
            end
            return an < bn
        end)

        local total = #allResults
        local fromIdx = math.max(1, ((tonumber(page) or 1) - 1) * (tonumber(size) or 9) + 1)
        local toIdx = math.min(total, fromIdx + (tonumber(size) or 9) - 1)
        local pageRows = {}
        for i = fromIdx, toIdx do
            if allResults[i] then pageRows[#pageRows + 1] = allResults[i] end
        end

        if not (hasOxMySQL() and exports.oxmysql) or #pageRows == 0 then
            cb({ data = pageRows, total = total })
            return
        end

        local pending = #pageRows
        for _, res in ipairs(pageRows) do
            exports.oxmysql:execute(
                'SELECT COUNT(*) as cnt FROM pf_mdt_warrants WHERE status = ? AND (suspectCitizenId = ? OR suspectName = ?)',
                { 'active', res.citizenId, res.name },
                function(wrows)
                    if wrows and wrows[1] and wrows[1].cnt > 0 then
                        res.hasWarrant = true
                    end
                    pending = pending - 1
                    if pending == 0 then
                        cb({ data = pageRows, total = total })
                    end
                end
            )

            exports.oxmysql:execute(
                'SELECT COUNT(*) as cnt FROM pf_mdt_citizen_flags WHERE citizenId = ? AND flag LIKE ?',
                { res.citizenId, '%dangerous%' },
                function(frows)
                    if frows and frows[1] and frows[1].cnt > 0 then
                        res.isDangerous = true
                    end
                end
            )
        end
    end

    if hasOxMySQL() and exports.oxmysql then
        local like = '%' .. query .. '%'
        exports.oxmysql:execute(
            'SELECT citizenid, charinfo, job, metadata FROM players WHERE charinfo LIKE ? OR citizenid LIKE ?',
            { like, like },
            function(rows)
                for _, r in ipairs(rows or {}) do
                    local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
                    local meta = type(r.metadata) == 'string' and json.decode(r.metadata) or r.metadata or {}
                    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
                    local job = r.job
                    if type(job) == 'string' then
                        local ok, parsed = pcall(json.decode, job)
                        if ok and parsed then job = parsed end
                    end
                    local jobLabel = (job and (job.label or job.name)) or 'Unemployed'

                    local licenses = {}
                    if meta.licences then
                        if meta.licences.driver then table.insert(licenses, 'Driver License') end
                        if meta.licences.weapon then table.insert(licenses, 'Weapon License') end
                        if meta.licences.business then table.insert(licenses, 'Business License') end
                    end

                    allResults[#allResults + 1] = {
                        citizenId = r.citizenid,
                        name = name ~= '' and name or 'Unknown',
                        dob = ci.birthdate or '',
                        phone = ci.phone or '',
                        nationality = ci.nationality or '',
                        job = jobLabel,
                        licenses = licenses,
                        hasWarrant = false,
                        isDangerous = false,
                    }
                end

                if not IsManualEntriesEnabled() then
                    finalizePagedResults()
                    return
                end

                exports.oxmysql:execute(
                    [[
                        SELECT citizenId, firstname, lastname, dob, phone, nationality, gender, job, address, profilePicture
                        FROM pf_mdt_manual_citizens
                        WHERE citizenId LIKE ?
                           OR firstname LIKE ?
                           OR lastname LIKE ?
                           OR phone LIKE ?
                    ]],
                    { like, like, like, like },
                    function(manualRows)
                        for _, mr in ipairs(manualRows or {}) do
                            local mapped = MapManualCitizenRow(mr)
                            if mapped then allResults[#allResults + 1] = mapped end
                        end
                        finalizePagedResults()
                    end
                )
            end
        )
        return
    end

    -- Fallback: online players only
    local players = QBCore.Functions.GetQBPlayers()
    for _, P in pairs(players) do
        local cid = P.PlayerData.citizenid or ''
        local ci = P.PlayerData.charinfo or {}
        local meta = P.PlayerData.metadata or {}
        local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
        local phone = ci.phone or ''
        if query == '' or cid:lower():find(query, 1, true) or name:lower():find(query, 1, true) or phone:lower():find(query, 1, true) then
            local licenses = {}
            local lic = meta.licences or meta.licenses or {}
            local licFlags = {
                driver = lic.driver == true,
                weapon = lic.weapon == true,
                business = lic.business == true,
            }
            if licFlags.driver then table.insert(licenses, 'Driver License') end
            if licFlags.weapon then table.insert(licenses, 'Weapon License') end
            if licFlags.business then table.insert(licenses, 'Business License') end
            table.insert(allResults, {
                citizenId = cid,
                name = name ~= '' and name or 'Unknown',
                dob = ci.birthdate or '',
                phone = phone,
                nationality = ci.nationality or '',
                job = (P.PlayerData.job and P.PlayerData.job.label) or 'Unemployed',
                licenses = licenses,
                hasWarrant = false,
                isDangerous = false,
            })
        end
    end
    cb({ data = allResults, total = #allResults })
end)
QBCore.Functions.CreateCallback('pf_mdt:searchVehicles', function(source, cb, data)
    local query = (data and data.query or ''):lower()
    local page = (data and data.page) or 1
    local size = (data and data.pageSize) or 9
    local allResults = {}

    if hasOxMySQL() and exports.oxmysql then
        local like = '%' .. query .. '%'
        local params
        local sql
        if query == '' then
            sql = [[
                SELECT v.plate, v.citizenid, v.vehicle, v.mods, vp.vehiclePhoto,
                       (SELECT f.flag FROM pf_mdt_vehicle_flags f WHERE f.plate = v.plate ORDER BY f.createdAt DESC LIMIT 1) AS activeFlag
                FROM player_vehicles v
                LEFT JOIN pf_mdt_vehicle_profiles vp ON vp.plate = v.plate
            ]]
            params = {}
        else
            sql = [[
                SELECT v.plate, v.citizenid, v.vehicle, v.mods, vp.vehiclePhoto,
                       (SELECT f.flag FROM pf_mdt_vehicle_flags f WHERE f.plate = v.plate ORDER BY f.createdAt DESC LIMIT 1) AS activeFlag
                FROM player_vehicles v
                LEFT JOIN pf_mdt_vehicle_profiles vp ON vp.plate = v.plate
                WHERE v.plate LIKE ? OR v.citizenid LIKE ?
            ]]
            params = { like, like }
        end

        exports.oxmysql:execute(sql, params, function(rows)
            for _, r in ipairs(rows or {}) do
                local mapped = MapVehicleRow(r)
                if mapped then allResults[#allResults + 1] = mapped end
            end

            local function finalizeVehicles()
                table.sort(allResults, function(a, b)
                    return tostring(a.plate or '') < tostring(b.plate or '')
                end)

                local total = #allResults
                local fromIdx = math.max(1, ((tonumber(page) or 1) - 1) * (tonumber(size) or 9) + 1)
                local toIdx = math.min(total, fromIdx + (tonumber(size) or 9) - 1)
                local pageRows = {}
                for i = fromIdx, toIdx do
                    if allResults[i] then pageRows[#pageRows + 1] = allResults[i] end
                end
                cb({ data = pageRows, total = total })
            end

            if not IsManualEntriesEnabled() then
                finalizeVehicles()
                return
            end

            local manualSql
            local manualParams
            if query == '' then
                manualSql = [[
                    SELECT plate, ownerCitizenId, ownerName, model, modelLabel, brand, primaryColorId, secondaryColorId, vehiclePhoto
                    FROM pf_mdt_manual_vehicles
                ]]
                manualParams = {}
            else
                manualSql = [[
                    SELECT plate, ownerCitizenId, ownerName, model, modelLabel, brand, primaryColorId, secondaryColorId, vehiclePhoto
                    FROM pf_mdt_manual_vehicles
                    WHERE plate LIKE ? OR ownerCitizenId LIKE ? OR ownerName LIKE ? OR model LIKE ? OR modelLabel LIKE ?
                ]]
                manualParams = { like, like, like, like, like }
            end

            exports.oxmysql:execute(manualSql, manualParams, function(manualRows)
                for _, r in ipairs(manualRows or {}) do
                    local mapped = MapManualVehicleRow(r)
                    if mapped then allResults[#allResults + 1] = mapped end
                end
                finalizeVehicles()
            end)
        end)
        return
    end

    -- Fallback: empty
    cb({ data = {}, total = 0 })
end)

QBCore.Functions.CreateCallback('pf_mdt:getOwnedVehicles', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ data = {}, total = 0 })
        return
    end
    
    local citizenId = Player.PlayerData.citizenid
    local page = (data and data.page) or 1
    local size = (data and data.pageSize) or 9
    local results = {}

    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute('SELECT COUNT(*) as c FROM player_vehicles WHERE citizenid = ?', { citizenId }, function(countRows)
            local total = (countRows and countRows[1] and countRows[1].c) or 0
            exports.oxmysql:execute('SELECT v.plate, v.citizenid, v.vehicle, p.charinfo FROM player_vehicles v LEFT JOIN players p ON p.citizenid = v.citizenid WHERE v.citizenid = ? LIMIT ? OFFSET ?',
            { citizenId, size, (page-1)*size }, function(rows)
                for _, r in ipairs(rows or {}) do
                    local vdata = type(r.vehicle) == 'string' and json.decode(r.vehicle) or r.vehicle or {}
                    local modelName = vdata.model or vdata.name or 'Vehicle'
                    -- Get vehicle model display name
                    local displayName = GetDisplayNameFromVehicleModel(GetHashKey(modelName)) or modelName
                    if type(displayName) == 'string' and displayName ~= '' then
                        displayName = displayName
                    else
                        displayName = modelName
                    end
                    local color = vdata.color or 'Unknown'
                    if type(color) == 'number' then color = 'Color ' .. color end
                    local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
                    local owner = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$','%1')
                    results[#results+1] = {
                        vehicleId = r.plate,
                        plate = r.plate,
                        model = displayName,
                        color = color,
                        status = 'CLEAR',
                        ownerName = owner ~= '' and owner or r.citizenid,
                        lastSeen = 'Unknown'
                    }
                end
                cb({ data = results, total = total })
            end)
        end)
        return
    end

    -- Fallback: empty
    cb({ data = {}, total = 0 })
end)

-- City events (pf-services): warrants and sentences are court records the newsroom gets as leads.
-- Only public facts are sent: names, charge titles, sentence length and fine; never the narrative,
-- witnesses, officers' notes or citizen ids.
local function CityEvent(kind, data, opts)
    if GetResourceState('pf-services') ~= 'started' then return nil end
    local svc = exports['pf-services']
    if not svc then return nil end
    local ok, id = pcall(function() return svc:Emit(kind, data, opts) end)
    return ok and id or nil
end

local function PublicText(v, max)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v):gsub('[%c<>]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    return s:sub(1, max)
end

-- charge titles only (a list of strings or of { name / label / title })
local function PublicCharges(list)
    local out = {}
    if type(list) ~= 'table' then return out end
    for _, c in ipairs(list) do
        local name = type(c) == 'table' and (c.name or c.label or c.title) or c
        name = PublicText(name, 60)
        if name then out[#out + 1] = name end
        if #out >= 10 then break end
    end
    return out
end

local function ReportWarrant(warrantId, suspect, charges, actorCid)
    local name = PublicText(suspect, 60) or 'Unknown suspect'
    CityEvent('police.warrant', { warrantId = PublicText(warrantId, 16), suspect = name, charges = PublicCharges(charges) }, {
        title = 'Warrant issued for ' .. name, actor = actorCid, dedupe = PublicText(warrantId, 16) or name,
    })
end

-- Warrants storage fallback
local WarrantsStore = {}
local function NextWarrantId()
    return ("W%05d"):format(math.random(1,99999))
end

RegisterNetEvent('pf_mdt:createWarrant', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local Player = QBCore.Functions.GetPlayer(src)
    local issuedBy = Player and Player.PlayerData and (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname) or 'Officer'
    local actorCid = Player and Player.PlayerData and Player.PlayerData.citizenid or nil

    if hasOxMySQL() and exports.oxmysql then
        local incomingId = data and data.warrantId or nil
        local wId = incomingId or NextWarrantId()
        local narrative = data and data.narrative or ''
        local title = (data and data.title) and tostring(data.title) or nil
        local officers = (data and data.officers) or {}
        local witnesses = (data and data.witnesses) or {}

        exports.oxmysql:insert('INSERT INTO pf_mdt_warrants (warrantId, suspectName, charges, officers, witnesses, issuedBy, title, narrative, expiresAt, status, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())',
            { wId, data.suspect or '', json.encode(data.charges or {}), json.encode(officers), json.encode(witnesses), issuedBy, title, narrative, data and data.expiry or nil, 'active' },
            function(insertId)
                -- reported only once the warrant is really on record
                if insertId then ReportWarrant(wId, data.suspect, data.charges, actorCid) end
            end)
        return
    end

    local incomingId = data and data.warrantId or nil
    table.insert(WarrantsStore, {
        warrantId = incomingId or NextWarrantId(),
        suspectName = data.suspect or 'Unknown',
        charges = data.charges or {},
        officers = data.officers or {},
        witnesses = data.witnesses or {},
        issuedBy = issuedBy,
        title = data.title or nil,
        issuedAt = os.date('%Y-%m-%d %H:%M:%S'),
        status = 'active',
        narrative = data and data.narrative or ''
    })
    ReportWarrant(WarrantsStore[#WarrantsStore].warrantId, data.suspect, data.charges, actorCid)
end)

QBCore.Functions.CreateCallback('pf_mdt:searchWarrants', function(source, cb, data)
    local query = (data and data.query or ''):lower()
    local page = (data and data.page) or 1
    local size = (data and data.pageSize) or 12
    if hasOxMySQL() and exports.oxmysql then
        local like = '%' .. query .. '%'
        exports.oxmysql:execute('SELECT COUNT(*) as c FROM pf_mdt_warrants WHERE suspectName LIKE ? OR warrantId LIKE ?', { like, like }, function(countRows)
            local total = (countRows and countRows[1] and countRows[1].c) or 0
            exports.oxmysql:execute('SELECT warrantId, suspectName, charges, officers, witnesses, issuedBy, title, narrative, createdAt, expiresAt, status FROM pf_mdt_warrants WHERE suspectName LIKE ? OR warrantId LIKE ? ORDER BY createdAt DESC LIMIT ? OFFSET ?',
            { like, like, size, (page-1)*size }, function(rows)
                local mapped = {}
                for _, r in ipairs(rows or {}) do
                    local officers = (type(r.officers)=='string' and json.decode(r.officers)) or r.officers or {}
                    local witnesses = (type(r.witnesses)=='string' and json.decode(r.witnesses)) or r.witnesses or {}
                    mapped[#mapped+1] = {
                        warrantId = r.warrantId,
                        suspectName = r.suspectName,
                        charges = (type(r.charges)=='string' and json.decode(r.charges)) or r.charges or {},
                        officers = officers,
                        witnesses = witnesses,
                        title = r.title,
                        narrative = r.narrative,
                        issuedBy = r.issuedBy,
                        issuedAt = r.createdAt,
                        status = r.status or 'active'
                    }
                end
                cb({ data = mapped, total = total })
            end)
        end)
        return
    end

    -- Fallback: in-memory
    local filtered = {}
    for _, w in ipairs(WarrantsStore) do
        if query == '' or (w.suspectName and w.suspectName:lower():find(query,1,true)) or (w.warrantId and w.warrantId:lower():find(query,1,true)) then
            table.insert(filtered, w)
        end
    end
    local total = #filtered
    local start = (page-1)*size + 1
    local stop = math.min(page*size, total)
    local paged = {}
    for i=start, stop do paged[#paged+1] = filtered[i] end
    cb({ data = paged, total = total })
end)

-- Incidents / Reports / FTO placeholders
-- Incidents
QBCore.Functions.CreateCallback('pf_mdt:searchIncidents', function(source, cb, data)
    local query = (data and data.query or ''):lower()
    local page = (data and data.page) or 1
    local size = (data and data.pageSize) or 12
    local status = (data and data.status) or nil
    if hasOxMySQL() and exports.oxmysql then
        local like = '%' .. query .. '%'
        local where = 'WHERE (title LIKE ? OR incidentId LIKE ? OR location LIKE ?)'
        local paramsCount = { like, like, like }
        if status and status ~= '' and status ~= 'all' then
            where = where .. ' AND status = ?'
            table.insert(paramsCount, status)
        end
        exports.oxmysql:execute('SELECT COUNT(*) as c FROM pf_mdt_incidents ' .. where, paramsCount, function(countRows)
            local total = (countRows and countRows[1] and countRows[1].c) or 0
            local params = { like, like, like }
            if status and status ~= '' and status ~= 'all' then table.insert(params, status) end
            table.insert(params, size)
            table.insert(params, (page-1)*size)
            exports.oxmysql:execute('SELECT incidentId as id, title, priority, status, reportingOfficer, location, narrative, involvedCitizens, involvedOfficers, involvedCitizenIds, involvedOfficerIds, dateTime, createdAt FROM pf_mdt_incidents ' .. where .. ' ORDER BY createdAt DESC LIMIT ? OFFSET ?',
                params,
                function(rows)
                    local mapped = {}
                    for _, r in ipairs(rows or {}) do
                        local citizens = (type(r.involvedCitizens)=='string' and json.decode(r.involvedCitizens)) or (r.involvedCitizens or {})
                        local officers = (type(r.involvedOfficers)=='string' and json.decode(r.involvedOfficers)) or (r.involvedOfficers or {})
                        mapped[#mapped+1] = {
                            id = r.id,
                            title = r.title,
                            priority = r.priority,
                            status = r.status,
                            reportingOfficer = r.reportingOfficer,
                            location = r.location,
                            narrative = r.narrative,
                            involvedCitizens = citizens,
                            involvedOfficers = officers,
                            dateTime = r.dateTime,
                            createdAt = r.createdAt
                        }
                    end
                    cb({ data = mapped, total = total })
                end)
        end)
    else
        cb({ data = {}, total = 0 })
    end
end)

-- Reports
QBCore.Functions.CreateCallback('pf_mdt:searchReports', function(source, cb, data)
    local query = (data and data.query or ''):lower()
    local page = (data and data.page) or 1
    local size = (data and data.pageSize) or 12
    if hasOxMySQL() and exports.oxmysql then
        local like = '%' .. query .. '%'
        exports.oxmysql:execute('SELECT COUNT(*) as c FROM pf_mdt_reports WHERE title LIKE ? OR reportId LIKE ? OR officer LIKE ? OR type LIKE ?', { like, like, like, like }, function(countRows)
            local total = (countRows and countRows[1] and countRows[1].c) or 0
            exports.oxmysql:execute('SELECT reportId as id, type, title, officer, createdAt FROM pf_mdt_reports WHERE title LIKE ? OR reportId LIKE ? OR officer LIKE ? OR type LIKE ? ORDER BY createdAt DESC LIMIT ? OFFSET ?',
            { like, like, like, like, size, (page-1)*size }, function(rows)
                cb({ data = rows or {}, total = total })
            end)
        end)
    else
        cb({ data = {}, total = 0 })
    end
end)

-- Get single report by id
QBCore.Functions.CreateCallback('pf_mdt:getReport', function(source, cb, data)
    local id = data and (data.id or data.reportId) or nil
    if not id or id == '' then cb({ success = false, error = 'invalid_id' }); return end
    if not (hasOxMySQL() and exports.oxmysql) then cb({ success = false, error = 'no_db' }); return end

    exports.oxmysql:execute('SELECT reportId, type, category, title, officer, narrative, content, location, vehiclePlate, involvedParties, linkedEvidence, approvalStatus, status, timestamp, createdAt FROM pf_mdt_reports WHERE reportId = ? LIMIT 1', { id }, function(rows)
        local r = rows and rows[1]
        if not r then cb({ success = false, error = 'not_found' }); return end
        local involved = nil
        local evidence = nil
        if r.involvedParties then
            local ok, parsed = pcall(json.decode, r.involvedParties)
            if ok then involved = parsed end
        end
        if r.linkedEvidence then
            local ok, parsed = pcall(json.decode, r.linkedEvidence)
            if ok then evidence = parsed end
        end
        cb({ success = true, report = {
            id = r.reportId,
            type = r.type,
            category = r.category,
            title = r.title,
            officer = r.officer,
            narrative = r.narrative,
            content = r.content,
            location = r.location,
            vehiclePlate = r.vehiclePlate,
            involvedParties = involved,
            linkedEvidence = evidence,
            approvalStatus = r.approvalStatus,
            status = r.status,
            timestamp = r.timestamp,
            createdAt = r.createdAt
        } })
    end)
end)

-- FTO Reports
local function getJobNameAndGrade(player)
    local jobName = (player and player.PlayerData and player.PlayerData.job and player.PlayerData.job.name) or ''
    local grade = tonumber((player and player.PlayerData and player.PlayerData.job and player.PlayerData.job.grade and player.PlayerData.job.grade.level) or 0) or 0
    return jobName, grade
end

-- Map legacy FTO rows (v1 table) into the v2 shape used by the UI
local function mapLegacyFtoRow(r)
    if not r then return nil end
    local uid = r.report_uid or r.reportUid or r.report_id or r.reportId or r.reportid or ('LEG-' .. tostring(r.id or ''))
    local trainee = r.trainee_name or r.traineeName or r.trainee or r.trainee_fullname or 'Unknown'
    local author = r.author_name or r.authorName or r.ftoName or r.fto_name or 'Unknown'
    local phase = tonumber(r.phase or r.phase_number or r.phaseNumber or 1) or 1
    local shift = r.shift or r.shift_name or r.shiftName or 'Morning'
    local rideDate = r.ride_date or r.date or r.rideDate or r.created_at or r.createdAt
    local rating = r.overall_rating or r.rating or r.avg_rating or r.average_rating
    local status = (r.status or 'DRAFT')

    return {
        report_uid = uid,
        status = status,
        trainee_name = trainee,
        author_name = author,
        ride_date = rideDate,
        phase = phase,
        shift = shift,
        overall_rating = rating and tonumber(rating) or nil,
        canEdit = true -- legacy rows: allow editing so they can be migrated if needed
    }
end

local function legacyMatchesFilter(mapped, search, status)
    if not mapped then return false end
    local ok = true
    if search and search ~= '' then
        local s = string.lower(search)
        local function contains(val)
            return val and string.find(string.lower(tostring(val)), s, 1, true) ~= nil
        end
        ok = contains(mapped.report_uid) or contains(mapped.trainee_name) or contains(mapped.author_name) or contains(mapped.status)
    end
    if ok and status and status ~= '' then
        ok = (string.upper(mapped.status or '') == string.upper(status))
    end
    return ok
end

local function isAllowedMdtJob(jobName)
    return jobName ~= '' and Config and Config.AllowedJobs and Config.AllowedJobs[jobName] == true
end

local function getIsOwnerFlag(player)
    local meta = player and player.PlayerData and player.PlayerData.metadata or {}
    if type(meta) ~= 'table' then
        local ok, parsed = pcall(json.decode, meta)
        if ok and type(parsed) == 'table' then meta = parsed else meta = {} end
    end
    return meta.isOwner == true or meta.isowner == true or meta.owner == true
end

local function isCommand(player)
    local _, grade = getJobNameAndGrade(player)
    return grade >= 4 or getIsOwnerFlag(player)
end

local function canViewDraft(playerCid, reportRow, command, playerName)
    if not reportRow then return false end
    -- User-requested behavior: drafts should be visible alongside non-drafts.
    -- Editing is still restricted via canEditReport.
    return true
end

local function canEditReport(playerCid, reportRow, command, playerName)
    if not reportRow then return false end
    local st = tostring(reportRow.status or ''):upper()
    if st == 'APPROVED' or st == 'REJECTED' then return false end
    if command then return true end
    local authorCid = tostring(reportRow.author_cid or '')
    if authorCid ~= '' then
        return authorCid == tostring(playerCid or '')
    end
    local authorName = tostring(reportRow.author_name or '')
    return authorName ~= '' and authorName == tostring(playerName or '')
end

local function parseMysqlDateStringToTimestamp(d)
    if not d then return nil end
    if type(d) == 'number' then return d end
    local y, m, day, hh, mm, ss = tostring(d):match('^(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
    if not y then
        y, m, day = tostring(d):match('^(%d+)-(%d+)-(%d+)$')
        hh, mm, ss = '00', '00', '00'
    end
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(day), hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) })
end

local function normalizeRideDate(payload)
    local rd = payload and (payload.ride_date or payload.rideDate) or nil
    if not rd or rd == '' then return nil end
    if type(rd) == 'string' then
        -- Accept HTML datetime-local (YYYY-MM-DDTHH:MM)
        rd = rd:gsub('T', ' ')
        if #rd == 16 then rd = rd .. ':00' end
        return rd
    end
    return tostring(rd)
end

local function computeOverallRatingFromEvaluation(evalTable)
    if type(evalTable) ~= 'table' then return nil end
    local sum, n = 0, 0
    for _, v in pairs(evalTable) do
        local r = tonumber(v and v.rating or nil)
        if r and r >= 1 and r <= 5 then
            sum = sum + r
            n = n + 1
        end
    end
    if n == 0 then return nil end
    local avg = sum / n
    return math.floor(avg * 10 + 0.5) / 10
end

local function validateSubmitPayload(payload)
    local errors = {}
    local function req(cond, msg)
        if not cond then errors[#errors+1] = msg end
    end

    local traineeCid = tostring(payload and (payload.trainee_cid or payload.traineeCid) or '')
    req(traineeCid ~= '', 'trainee_required')

    local rideDate = normalizeRideDate(payload)
    req(rideDate ~= nil, 'ride_date_required')

    local phase = tonumber(payload and payload.phase or 1) or 1
    req(phase >= 1, 'phase_required')

    local shift = tostring(payload and payload.shift or '')
    req(shift == 'Morning' or shift == 'Evening' or shift == 'Night', 'shift_required')

    local rideDescription = tostring(payload and payload.ride_description or payload.rideDescription or '')
    req(rideDescription ~= '', 'ride_description_required')

    local strengths = tostring(payload and payload.strengths or '')
    req(strengths ~= '', 'strengths_required')

    local improvements = tostring(payload and payload.improvements or '')
    req(improvements ~= '', 'improvements_required')

    local recommendation = tostring(payload and payload.recommendation or '')
    req(recommendation == 'ADVANCE' or recommendation == 'REMAIN' or recommendation == 'REMEDIAL' or recommendation == 'TERMINATION', 'recommendation_required')

    local safetyConcern = (payload and payload.safety_concern) and (payload.safety_concern == true or payload.safety_concern == 1 or payload.safety_concern == '1') or false
    local safetyNotes = tostring(payload and payload.safety_concern_notes or payload.safetyConcernNotes or '')
    if safetyConcern then
        req(safetyNotes ~= '', 'safety_concern_notes_required')
    end

    local evalJson = payload and (payload.evaluation_json or payload.evaluationJson) or {}
    if type(evalJson) == 'string' then
        local ok, parsed = pcall(json.decode, evalJson)
        if ok and type(parsed) == 'table' then evalJson = parsed else evalJson = {} end
    end

    -- Require ratings present (1-5) for each category present
    local ratingCount = 0
    for _, v in pairs(evalJson or {}) do
        local r = tonumber(v and v.rating or nil)
        if r and r >= 1 and r <= 5 then ratingCount = ratingCount + 1 end
    end
    req(ratingCount > 0, 'evaluation_required')

    return (#errors == 0), errors
end

local function insertFtoAudit(reportUid, action, actorCid, actorName, details)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local d = nil
    if details ~= nil then
        if type(details) == 'string' then d = details else d = json.encode(details) end
    end
    exports.oxmysql:insert('INSERT INTO pf_mdt_fto_report_audit (report_uid, action, actor_cid, actor_name, details_json) VALUES (?, ?, ?, ?, ?)',
        { reportUid, action, actorCid, actorName, d })
end

local function generateFtoUid(cb)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb(nil)
        return
    end
    local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local function rand8()
        local out = {}
        for i=1,8 do
            local idx = math.random(1, #alphabet)
            out[#out+1] = alphabet:sub(idx, idx)
        end
        return table.concat(out)
    end

    local tries = 0
    local function attempt()
        tries = tries + 1
        if tries > 20 then
            cb(nil)
            return
        end
        local uid = ('FTO-%s'):format(rand8())
        exports.oxmysql:scalar('SELECT COUNT(*) FROM pf_mdt_fto_reports WHERE report_uid = ? LIMIT 1', { uid }, function(count)
            if tonumber(count or 0) == 0 then
                cb(uid)
            else
                attempt()
            end
        end)
    end
    attempt()
end

-- New v2 API (preferred)
QBCore.Functions.CreateCallback('pf_mdt:getFtoReportsList', function(source, cb, filters)
    if not (hasOxMySQL() and exports.oxmysql) then
        dprint('[MDT FTO LIST] No oxmysql available')
        cb({ success = false, reports = {}, totalCount = 0, error = 'no_db' })
        return
    end

    -- Normalize filters up front so legacy branch can use them safely
    local search = tostring(filters and filters.search or filters and filters.query or '')
    local status = tostring(filters and filters.status or '')
    local page = tonumber(filters and filters.page or 1) or 1
    local limit = tonumber(filters and (filters.limit or filters.pageSize) or 12) or 12
    if page < 1 then page = 1 end
    if limit < 1 then limit = 12 end
    if limit > 50 then limit = 50 end
    local offset = (page - 1) * limit

    -- Check table schema before proceeding
    exports.oxmysql:scalar('SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = "pf_mdt_fto_reports" AND COLUMN_NAME = "report_uid"', {}, function(hasReportUid)
        if not hasReportUid or tonumber(hasReportUid) == 0 then
            dprint('^3[MDT FTO LIST WARN] pf_mdt_fto_reports missing report_uid; treating as legacy table^0')
            -- Fetch legacy rows from the old table schema and paginate in Lua
            exports.oxmysql:execute('SELECT * FROM pf_mdt_fto_reports ORDER BY id DESC', {}, function(rows)
                local mapped = {}
                for _, r in ipairs(rows or {}) do
                    local m = mapLegacyFtoRow(r)
                    if legacyMatchesFilter(m, search, status) then
                        mapped[#mapped+1] = m
                    end
                end

                local totalLegacy = #mapped
                local startIdx = offset + 1
                local endIdx = math.min(offset + limit, totalLegacy)
                local paged = {}
                for i = startIdx, endIdx do
                    if mapped[i] then paged[#paged+1] = mapped[i] end
                end
                dprint(('^3[MDT FTO LIST WARN] Using legacy pf_mdt_fto_reports table; total=%d, returning=%d^0'):format(totalLegacy, #paged))
                cb({ success = true, reports = paged, totalCount = totalLegacy })
            end)
            return
        end
        dprint('^2[MDT FTO LIST] Schema OK - report_uid column exists^0')
        
        local player = QBCore.Functions.GetPlayer(source)
        if not player then
            dprint('[MDT FTO LIST] No player found for source ' .. tostring(source))
            cb({ success = false, reports = {}, totalCount = 0, error = 'no_player' })
            return
        end

        local jobName, grade = getJobNameAndGrade(player)
        if not isAllowedMdtJob(jobName) then
            dprint('[MDT FTO LIST] Job not allowed: ' .. tostring(jobName))
            cb({ success = false, reports = {}, totalCount = 0, error = 'not_allowed' })
            return
        end

        local cid = player.PlayerData.citizenid
        local ci = player.PlayerData.charinfo or {}
        local playerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
        local command = isCommand(player)
        dprint('[MDT FTO LIST] Request from: ' .. tostring(playerName) .. ' (cid: ' .. tostring(cid) .. ', command: ' .. tostring(command) .. ')')

        local where = {}
        local params = {}

        if search ~= '' then
            local like = '%' .. search .. '%'
            where[#where+1] = '(report_uid LIKE ? OR trainee_name LIKE ? OR author_name LIKE ? OR status LIKE ?)'
            params[#params+1] = like
            params[#params+1] = like
            params[#params+1] = like
            params[#params+1] = like
        end

        if status ~= '' then
            where[#where+1] = 'status = ?'
            params[#params+1] = status
        end

        -- User-requested behavior: show drafts and non-drafts in the list.
        -- Keep edit permissions enforced separately.

        local whereSql = (#where > 0) and ('WHERE ' .. table.concat(where, ' AND ')) or ''
        dprint('[MDT FTO LIST] Query WHERE: ' .. whereSql .. ', params count: ' .. #params)

        exports.oxmysql:scalar(('SELECT COUNT(*) FROM pf_mdt_fto_reports %s'):format(whereSql), params, function(total)
            local totalNum = tonumber(total or 0) or 0
            dprint('[MDT FTO LIST] Total count from DB: ' .. tostring(totalNum))

            -- If no rows in the v2 table, fall back to legacy table (if present)
            if totalNum == 0 then
                exports.oxmysql:scalar('SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = "pf_mdt_fto_reports_legacy"', {}, function(hasLegacy)
                    if hasLegacy and tonumber(hasLegacy) > 0 then
                        dprint('[MDT FTO LIST] No v2 rows, falling back to pf_mdt_fto_reports_legacy')
                        exports.oxmysql:scalar('SELECT COUNT(*) FROM pf_mdt_fto_reports_legacy', {}, function(legacyTotal)
                            exports.oxmysql:execute('SELECT * FROM pf_mdt_fto_reports_legacy ORDER BY id DESC LIMIT ? OFFSET ?', { limit, offset }, function(legacyRows)
                                local out = {}
                                for _, r in ipairs(legacyRows or {}) do
                                    local mapped = mapLegacyFtoRow(r)
                                    if mapped then out[#out+1] = mapped end
                                end
                                dprint('[MDT FTO LIST] Legacy rows returned: ' .. tostring(#out))
                                cb({ success = true, reports = out, totalCount = tonumber(legacyTotal or #out) or #out })
                            end)
                        end)
                        return
                    end

                    dprint('[MDT FTO LIST] No v2 rows and no legacy table; returning empty list')
                    cb({ success = true, reports = {}, totalCount = 0 })
                end)
                return
            end

            local listSql = ('SELECT report_uid, status, trainee_cid, trainee_name, author_cid, author_name, phase, shift, ride_date, overall_rating, submitted_at, reviewed_at FROM pf_mdt_fto_reports %s ORDER BY ride_date DESC, id DESC LIMIT ? OFFSET ?'):format(whereSql)
            local listParams = {}
            for i=1,#params do listParams[i] = params[i] end
            listParams[#listParams+1] = limit
            listParams[#listParams+1] = offset

            exports.oxmysql:execute(listSql, listParams, function(rows)
                dprint('[MDT FTO LIST] Rows returned: ' .. tostring(rows and #rows or 0))
                local out = {}
                if rows and rows[1] then
                    local sample = {
                        uid = rows[1].report_uid,
                        status = rows[1].status,
                        trainee = rows[1].trainee_name,
                        author = rows[1].author_name,
                        ride_date = rows[1].ride_date
                    }
                    dprint('[MDT FTO LIST] Sample row: ' .. json.encode(sample))
                end
                for _, r in ipairs(rows or {}) do
                    local canEdit = canEditReport(cid, r, command, playerName)
                    out[#out+1] = {
                        report_uid = r.report_uid,
                        status = r.status,
                        trainee_name = r.trainee_name,
                        author_name = r.author_name,
                        ride_date = r.ride_date,
                        phase = tonumber(r.phase) or 1,
                        shift = r.shift,
                        overall_rating = r.overall_rating ~= nil and tonumber(r.overall_rating) or nil,
                        canEdit = canEdit
                    }
                end
                dprint('[MDT FTO LIST] Returning ' .. #out .. ' reports to client')
                cb({ success = true, reports = out, totalCount = totalNum })
            end)
        end)
    end) -- Close schema check callback
end)

QBCore.Functions.CreateCallback('pf_mdt:getFtoReport', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'no_db' })
        return
    end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        cb({ success = false, error = 'no_player' })
        return
    end
    local jobName = getJobNameAndGrade(player)
    if not isAllowedMdtJob(jobName) then
        cb({ success = false, error = 'not_allowed' })
        return
    end
    local reportUid = data and (data.report_uid or data.reportUid) or nil
    if not reportUid or reportUid == '' then
        cb({ success = false, error = 'missing_report_uid' })
        return
    end
    local cid = player.PlayerData.citizenid
    local ci = player.PlayerData.charinfo or {}
    local playerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    local command = isCommand(player)

    exports.oxmysql:execute('SELECT * FROM pf_mdt_fto_reports WHERE report_uid = ? LIMIT 1', { reportUid }, function(rows)
        local r = rows and rows[1] or nil
        if not r then
            cb({ success = false, error = 'not_found' })
            return
        end
        if not canViewDraft(cid, r, command, playerName) then
            cb({ success = false, error = 'forbidden' })
            return
        end

        local evalObj = {}
        if r.evaluation_json and r.evaluation_json ~= '' then
            local ok, parsed = pcall(json.decode, r.evaluation_json)
            if ok and type(parsed) == 'table' then evalObj = parsed end
        end

        exports.oxmysql:execute('SELECT action, actor_cid, actor_name, at, details_json FROM pf_mdt_fto_report_audit WHERE report_uid = ? ORDER BY id DESC LIMIT 50', { reportUid }, function(auditRows)
            cb({
                success = true,
                report = {
                    report_uid = r.report_uid,
                    status = r.status,
                    trainee_cid = r.trainee_cid,
                    trainee_name = r.trainee_name,
                    trainee_callsign = r.trainee_callsign,
                    author_cid = r.author_cid,
                    author_name = r.author_name,
                    phase = tonumber(r.phase) or 1,
                    shift = r.shift,
                    ride_date = r.ride_date,
                    created_at = r.created_at,
                    updated_at = r.updated_at,
                    submitted_at = r.submitted_at,
                    reviewed_by_cid = r.reviewed_by_cid,
                    reviewed_by_name = r.reviewed_by_name,
                    reviewed_at = r.reviewed_at,
                    review_note = r.review_note,
                    ride_description = r.ride_description,
                    overall_rating = r.overall_rating ~= nil and tonumber(r.overall_rating) or nil,
                    safety_concern = tonumber(r.safety_concern) == 1,
                    safety_concern_notes = r.safety_concern_notes,
                    recommendation = r.recommendation,
                    strengths = r.strengths,
                    improvements = r.improvements,
                    evaluation = evalObj,
                },
                permissions = {
                    canEdit = canEditReport(cid, r, command, playerName),
                    isCommand = command
                },
                audit = auditRows or {}
            })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:searchTrainees', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, trainees = {}, error = 'no_db' })
        return
    end

    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        cb({ success = false, trainees = {}, error = 'no_player' })
        return
    end
    local jobName = getJobNameAndGrade(player)
    if not isAllowedMdtJob(jobName) then
        cb({ success = false, trainees = {}, error = 'not_allowed' })
        return
    end

    local q = tostring(data and (data.query or data.search) or '')
    -- If query is empty, return a bounded "all officers" list for dropdowns.
    local like = (q == '' and '%' or ('%' .. q .. '%'))
    local limit = tonumber(data and data.limit or 50) or 50
    if q == '' and (not data or data.limit == nil) then
        limit = 200
    end
    if limit > 200 then limit = 200 end

    local whereJob = ''
    if Config and Config.FTOReports and Config.FTOReports.TraineePoliceOnly then
        local jobLikes = {}
        for j, allowed in pairs(Config.AllowedJobs or {}) do
            if allowed then
                jobLikes[#jobLikes+1] = 'p.job LIKE ' .. exports.oxmysql:escape('%"name":"' .. j .. '"%')
            end
        end
        if #jobLikes > 0 then
            whereJob = ' AND (' .. table.concat(jobLikes, ' OR ') .. ')'
        end
    end

    local sql = [[
        SELECT p.citizenid, p.charinfo, op.callsign
        FROM players p
        LEFT JOIN pf_mdt_officer_profiles op ON op.citizenId = p.citizenid
        WHERE (p.citizenid LIKE ? OR p.charinfo LIKE ?) ]] .. whereJob .. [[
        LIMIT ?
    ]]

    exports.oxmysql:execute(sql, { like, like, limit }, function(rows)
        local out = {}
        for _, r in ipairs(rows or {}) do
            local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
            local firstname = ci.firstname or ''
            local lastname = ci.lastname or ''
            local name = (firstname .. ' ' .. lastname):gsub('^%s*(.-)%s*$', '%1')
            if name ~= '' then
                out[#out+1] = {
                    cid = r.citizenid,
                    name = name,
                    callsign = r.callsign
                }
            end
        end
        cb({ success = true, trainees = out })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:saveFtoDraft', function(source, cb, payload)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'no_db' })
        return
    end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        cb({ success = false, error = 'no_player' })
        return
    end
    local jobName, grade = getJobNameAndGrade(player)
    if not isAllowedMdtJob(jobName) then
        cb({ success = false, error = 'not_allowed' })
        return
    end

    local minCreate = (Config and Config.FTOReports and tonumber(Config.FTOReports.MinGradeCreate)) or 2
    if grade < minCreate and not isCommand(player) then
        cb({ success = false, error = 'no_create_permission' })
        return
    end

    local authorCid = player.PlayerData.citizenid
    local ci = player.PlayerData.charinfo or {}
    local authorName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')

    local reportUid = payload and (payload.report_uid or payload.reportUid) or ''
    local traineeCid = tostring(payload and (payload.trainee_cid or payload.traineeCid) or '')
    local traineeName = tostring(payload and (payload.trainee_name or payload.traineeName) or '')
    local traineeCallsign = payload and (payload.trainee_callsign or payload.traineeCallsign) or nil
    if traineeCid == '' then
        cb({ success = false, error = 'trainee_required' })
        return
    end

    local phase = tonumber(payload and payload.phase or 1) or 1
    local maxPhase = (Config and Config.FTOReports and tonumber(Config.FTOReports.MaxPhase)) or 4
    if phase < 1 then phase = 1 end
    if phase > maxPhase then phase = maxPhase end
    local shift = tostring(payload and payload.shift or 'Morning')
    if shift ~= 'Morning' and shift ~= 'Evening' and shift ~= 'Night' then shift = 'Morning' end
    local rideDate = normalizeRideDate(payload) or os.date('%Y-%m-%d %H:%M:%S')

    local rideDescription = payload and (payload.ride_description or payload.rideDescription) or nil
    local safetyConcern = (payload and payload.safety_concern) and (payload.safety_concern == true or payload.safety_concern == 1 or payload.safety_concern == '1') or false
    local safetyNotes = payload and (payload.safety_concern_notes or payload.safetyConcernNotes) or nil
    local recommendation = payload and payload.recommendation or nil
    local strengths = payload and payload.strengths or nil
    local improvements = payload and payload.improvements or nil

    local evalObj = payload and (payload.evaluation_json or payload.evaluationJson or payload.evaluation) or {}
    if type(evalObj) == 'string' then
        local ok, parsed = pcall(json.decode, evalObj)
        if ok and type(parsed) == 'table' then evalObj = parsed else evalObj = {} end
    end
    local evalJson = json.encode(evalObj or {})

    if reportUid == '' then
        generateFtoUid(function(newUid)
            if not newUid then
                cb({ success = false, error = 'uid_generation_failed' })
                return
            end

            local insertSql = [[
                INSERT INTO pf_mdt_fto_reports
                (report_uid, status, trainee_cid, trainee_name, trainee_callsign, author_cid, author_name, phase, shift, ride_date, created_at, updated_at,
                 ride_description, safety_concern, safety_concern_notes, recommendation, strengths, improvements, evaluation_json)
                VALUES
                (?, 'DRAFT', ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), ?, ?, ?, ?, ?, ?, ?)
            ]]
            exports.oxmysql:insert(insertSql, {
                newUid,
                traineeCid,
                traineeName,
                traineeCallsign,
                authorCid,
                authorName,
                phase,
                shift,
                rideDate,
                rideDescription,
                safetyConcern and 1 or 0,
                safetyNotes,
                recommendation,
                strengths,
                improvements,
                evalJson
            }, function(_)
                insertFtoAudit(newUid, 'DRAFT_SAVED', authorCid, authorName, { new = true })
                cb({ success = true, report_uid = newUid, status = 'DRAFT' })
            end)
        end)
        return
    end

    -- Update existing draft
    exports.oxmysql:execute('SELECT report_uid, status, author_cid, author_name FROM pf_mdt_fto_reports WHERE report_uid = ? LIMIT 1', { reportUid }, function(rows)
        local r = rows and rows[1] or nil
        if not r then
            cb({ success = false, error = 'not_found' })
            return
        end

        local command = isCommand(player)
        if not canEditReport(authorCid, r, command, authorName) then
            cb({ success = false, error = 'forbidden' })
            return
        end
        local st = tostring(r.status or ''):upper()
        if st ~= 'DRAFT' then
            cb({ success = false, error = 'not_draft' })
            return
        end

        local updateSql = [[
            UPDATE pf_mdt_fto_reports
            SET trainee_cid = ?, trainee_name = ?, trainee_callsign = ?,
                phase = ?, shift = ?, ride_date = ?,
                ride_description = ?,
                safety_concern = ?, safety_concern_notes = ?,
                recommendation = ?, strengths = ?, improvements = ?,
                evaluation_json = ?,
                updated_at = NOW()
            WHERE report_uid = ?
        ]]

        exports.oxmysql:execute(updateSql, {
            traineeCid,
            traineeName,
            traineeCallsign,
            phase,
            shift,
            rideDate,
            rideDescription,
            safetyConcern and 1 or 0,
            safetyNotes,
            recommendation,
            strengths,
            improvements,
            evalJson,
            reportUid
        }, function(_)
            insertFtoAudit(reportUid, 'DRAFT_SAVED', authorCid, authorName, { new = false })
            cb({ success = true, report_uid = reportUid, status = 'DRAFT' })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:submitFtoReport', function(source, cb, payload)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'no_db' })
        return
    end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        cb({ success = false, error = 'no_player' })
        return
    end
    local jobName = getJobNameAndGrade(player)
    if not isAllowedMdtJob(jobName) then
        cb({ success = false, error = 'not_allowed' })
        return
    end

    local ok, errors = validateSubmitPayload(payload or {})
    if not ok then
        cb({ success = false, error = 'validation_failed', errors = errors })
        return
    end

    local authorCid = player.PlayerData.citizenid
    local ci = player.PlayerData.charinfo or {}
    local authorName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    local command = isCommand(player)

    local reportUid = payload and (payload.report_uid or payload.reportUid) or ''
    local traineeCid = tostring(payload and (payload.trainee_cid or payload.traineeCid) or '')
    local traineeName = tostring(payload and (payload.trainee_name or payload.traineeName) or '')
    local traineeCallsign = payload and (payload.trainee_callsign or payload.traineeCallsign) or nil
    local phase = tonumber(payload and payload.phase or 1) or 1
    local maxPhase = (Config and Config.FTOReports and tonumber(Config.FTOReports.MaxPhase)) or 4
    if phase < 1 then phase = 1 end
    if phase > maxPhase then phase = maxPhase end
    local shift = tostring(payload and payload.shift or 'Morning')
    if shift ~= 'Morning' and shift ~= 'Evening' and shift ~= 'Night' then shift = 'Morning' end
    local rideDate = normalizeRideDate(payload) or os.date('%Y-%m-%d %H:%M:%S')

    local rideDescription = payload and (payload.ride_description or payload.rideDescription) or nil
    local safetyConcern = (payload and payload.safety_concern) and (payload.safety_concern == true or payload.safety_concern == 1 or payload.safety_concern == '1') or false
    local safetyNotes = payload and (payload.safety_concern_notes or payload.safetyConcernNotes) or nil
    local recommendation = payload and payload.recommendation or nil
    local strengths = payload and payload.strengths or nil
    local improvements = payload and payload.improvements or nil

    local evalObj = payload and (payload.evaluation_json or payload.evaluationJson or payload.evaluation) or {}
    if type(evalObj) == 'string' then
        local ok2, parsed = pcall(json.decode, evalObj)
        if ok2 and type(parsed) == 'table' then evalObj = parsed else evalObj = {} end
    end
    local overallRating = tonumber(payload and payload.overall_rating or payload.overallRating) or computeOverallRatingFromEvaluation(evalObj)
    local evalJson = json.encode(evalObj or {})

    local function doUpsert(newUid)
        local submitSql = [[
            INSERT INTO pf_mdt_fto_reports
            (report_uid, status, trainee_cid, trainee_name, trainee_callsign, author_cid, author_name, phase, shift, ride_date,
             created_at, updated_at, submitted_at,
             ride_description, overall_rating, safety_concern, safety_concern_notes, recommendation, strengths, improvements, evaluation_json)
            VALUES
            (?, 'SUBMITTED', ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), NOW(), ?, ?, ?, ?, ?, ?, ?, ?)
        ]]
        exports.oxmysql:insert(submitSql, {
            newUid,
            traineeCid,
            traineeName,
            traineeCallsign,
            authorCid,
            authorName,
            phase,
            shift,
            rideDate,
            rideDescription,
            overallRating,
            safetyConcern and 1 or 0,
            safetyNotes,
            recommendation,
            strengths,
            improvements,
            evalJson
        }, function(_)
            insertFtoAudit(newUid, 'SUBMITTED', authorCid, authorName, { new = true })
            cb({ success = true, report_uid = newUid, status = 'SUBMITTED' })
        end)
    end

    if reportUid == '' then
        generateFtoUid(function(newUid)
            if not newUid then
                cb({ success = false, error = 'uid_generation_failed' })
                return
            end
            doUpsert(newUid)
        end)
        return
    end

    exports.oxmysql:execute('SELECT report_uid, status, author_cid FROM pf_mdt_fto_reports WHERE report_uid = ? LIMIT 1', { reportUid }, function(rows)
        local r = rows and rows[1] or nil
        if not r then
            -- Treat as new submit if uid missing in DB
            doUpsert(reportUid)
            return
        end

        local st = tostring(r.status or ''):upper()
        if st == 'APPROVED' or st == 'REJECTED' then
            cb({ success = false, error = 'locked' })
            return
        end

        -- SUBMIT permission: author (own report) or command
        if not command and tostring(r.author_cid or '') ~= tostring(authorCid or '') then
            cb({ success = false, error = 'forbidden' })
            return
        end

        local updateSql = [[
            UPDATE pf_mdt_fto_reports
            SET status = 'SUBMITTED',
                trainee_cid = ?, trainee_name = ?, trainee_callsign = ?,
                phase = ?, shift = ?, ride_date = ?,
                ride_description = ?,
                overall_rating = ?,
                safety_concern = ?, safety_concern_notes = ?,
                recommendation = ?, strengths = ?, improvements = ?,
                evaluation_json = ?,
                submitted_at = IF(submitted_at IS NULL, NOW(), submitted_at),
                updated_at = NOW()
            WHERE report_uid = ?
        ]]
        exports.oxmysql:execute(updateSql, {
            traineeCid,
            traineeName,
            traineeCallsign,
            phase,
            shift,
            rideDate,
            rideDescription,
            overallRating,
            safetyConcern and 1 or 0,
            safetyNotes,
            recommendation,
            strengths,
            improvements,
            evalJson,
            reportUid
        }, function(_)
            insertFtoAudit(reportUid, 'SUBMITTED', authorCid, authorName, { new = false })
            cb({ success = true, report_uid = reportUid, status = 'SUBMITTED' })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:reviewFtoReport', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'no_db' })
        return
    end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        cb({ success = false, error = 'no_player' })
        return
    end
    local jobName = getJobNameAndGrade(player)
    if not isAllowedMdtJob(jobName) then
        cb({ success = false, error = 'not_allowed' })
        return
    end

    if not isCommand(player) then
        cb({ success = false, error = 'not_command' })
        return
    end

    local reportUid = data and (data.report_uid or data.reportUid) or ''
    local action = tostring(data and data.action or ''):upper()
    local note = data and (data.review_note or data.reviewNote) or nil
    if reportUid == '' then
        cb({ success = false, error = 'missing_report_uid' })
        return
    end
    if action ~= 'APPROVE' and action ~= 'REJECT' then
        cb({ success = false, error = 'invalid_action' })
        return
    end

    local reviewerCid = player.PlayerData.citizenid
    local ci = player.PlayerData.charinfo or {}
    local reviewerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    local newStatus = (action == 'APPROVE') and 'APPROVED' or 'REJECTED'

    exports.oxmysql:execute('SELECT status FROM pf_mdt_fto_reports WHERE report_uid = ? LIMIT 1', { reportUid }, function(rows)
        local r = rows and rows[1] or nil
        if not r then
            cb({ success = false, error = 'not_found' })
            return
        end
        local st = tostring(r.status or ''):upper()
        if st ~= 'SUBMITTED' then
            cb({ success = false, error = 'not_submitted' })
            return
        end

        exports.oxmysql:execute([[
            UPDATE pf_mdt_fto_reports
            SET status = ?, reviewed_by_cid = ?, reviewed_by_name = ?, reviewed_at = NOW(), review_note = ?, updated_at = NOW()
            WHERE report_uid = ?
        ]], { newStatus, reviewerCid, reviewerName, note, reportUid }, function(_)
            insertFtoAudit(reportUid, newStatus, reviewerCid, reviewerName, { note = note })
            cb({ success = true, report_uid = reportUid, status = newStatus })
        end)
    end)
end)

-- Optional net-event wrappers (no return path)
RegisterNetEvent('pf_mdt:saveFtoDraft', function(payload)
    local src = source
    QBCore.Functions.TriggerCallback('pf_mdt:saveFtoDraft', src, function(_) end, payload or {})
end)
RegisterNetEvent('pf_mdt:submitFtoReport', function(payload)
    local src = source
    QBCore.Functions.TriggerCallback('pf_mdt:submitFtoReport', src, function(_) end, payload or {})
end)
RegisterNetEvent('pf_mdt:reviewFtoReport', function(payload)
    local src = source
    QBCore.Functions.TriggerCallback('pf_mdt:reviewFtoReport', src, function(_) end, payload or {})
end)

-- Legacy callback used by existing UI: map to v2 list
QBCore.Functions.CreateCallback('pf_mdt:searchFTOReports', function(source, cb, data)
    QBCore.Functions.TriggerCallback('pf_mdt:getFtoReportsList', source, function(result)
        local mapped = {}
        for _, r in ipairs((result and result.reports) or {}) do
            mapped[#mapped+1] = {
                traineeName = r.trainee_name,
                ftoName = r.author_name,
                phase = r.phase,
                rating = r.overall_rating or 0,
                status = r.status,
                date = r.ride_date
            }
        end
        cb({ data = mapped, total = (result and result.totalCount) or #mapped })
    end, { search = data and data.query or '', status = data and data.status or '', page = data and data.page or 1, limit = data and data.pageSize or 12 })
end)

-- Create endpoints
RegisterNetEvent('pf_mdt:createIncident', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local Player = QBCore.Functions.GetPlayer(source)
    local createdBy = Player and Player.PlayerData and Player.PlayerData.citizenid or 'system'
    local officerName = ''
    if Player and Player.PlayerData and Player.PlayerData.charinfo then
        local ci = Player.PlayerData.charinfo
        officerName = (ci.firstname or '') .. ' ' .. (ci.lastname or '')
        officerName = officerName:gsub('^%s*(.-)%s*$', '%1')
    end
    local incId = ("INC-%05d"):format(math.random(1,99999))

    local involvedCitizens = json.encode(data and data.involvedCitizens or {})
    local involvedVictims = json.encode(data and data.involvedVictims or {})
    local involvedOfficers = json.encode(data and data.involvedOfficers or {})
    local involvedCitizenIds = json.encode(data and data.involvedCitizenIds or {})
    local involvedVictimIds = json.encode(data and data.involvedVictimIds or {})
    local involvedOfficerIds = json.encode(data and data.involvedOfficerIds or {})
    local involvedVehicles = json.encode(data and data.involvedVehicles or {})
    local involvedVehicleIds = json.encode(data and data.involvedVehicleIds or {})
    local charges = json.encode(data and data.charges or {})
    local evidenceIds = json.encode(data and data.evidenceIds or {})
    local reportingOfficer = (data and data.reportingOfficer) or officerName
    local dtStr = (data and data.dateTime) or nil
    local dateTime = dtStr and dtStr:gsub('T',' '):gsub('Z','') or os.date('%Y-%m-%d %H:%M:%S')
    local title = (data and data.title) or 'Incident'
    local narrative = (data and data.description) or (data and data.narrative) or ''
    local location = (data and data.location) or ''
    local priority = (data and data.priority) or 'LOW'

    exports.oxmysql:insert('INSERT INTO pf_mdt_incidents (incidentId, title, priority, status, reportingOfficer, location, narrative, involvedCitizens, involvedVictims, involvedOfficers, involvedCitizenIds, involvedVictimIds, involvedOfficerIds, involvedVehicles, involvedVehicleIds, charges, evidence_ids, dateTime, createdBy) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { incId, title, priority, 'active', reportingOfficer, location, narrative, involvedCitizens, involvedVictims, involvedOfficers, involvedCitizenIds, involvedVictimIds, involvedOfficerIds, involvedVehicles, involvedVehicleIds, charges, evidenceIds, dateTime, createdBy })
end)

RegisterNetEvent('pf_mdt:updateIncident', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local id = data and data.id or nil
    if not id then return end
    local title = data and data.title or nil
    local narrative = (data and data.description) or (data and data.narrative) or nil
    local status = data and data.status or nil
    local location = data and data.location or nil
    local involvedCitizens = (data and data.involvedCitizens) and json.encode(data.involvedCitizens) or nil
    local involvedVictims = (data and data.involvedVictims) and json.encode(data.involvedVictims) or nil
    local involvedOfficers = (data and data.involvedOfficers) and json.encode(data.involvedOfficers) or nil
    local involvedCitizenIds = (data and data.involvedCitizenIds) and json.encode(data.involvedCitizenIds) or nil
    local involvedVictimIds = (data and data.involvedVictimIds) and json.encode(data.involvedVictimIds) or nil
    local involvedOfficerIds = (data and data.involvedOfficerIds) and json.encode(data.involvedOfficerIds) or nil
    local involvedVehicles = (data and data.involvedVehicles) and json.encode(data.involvedVehicles) or nil
    local involvedVehicleIds = (data and data.involvedVehicleIds) and json.encode(data.involvedVehicleIds) or nil
    local charges = (data and data.charges) and json.encode(data.charges) or nil
    local sets = {}
    local params = {}
    if title then table.insert(sets, 'title = ?'); table.insert(params, title) end
    if narrative then table.insert(sets, 'narrative = ?'); table.insert(params, narrative) end
    if status then table.insert(sets, 'status = ?'); table.insert(params, status) end
    if location then table.insert(sets, 'location = ?'); table.insert(params, location) end
    if involvedCitizens then table.insert(sets, 'involvedCitizens = ?'); table.insert(params, involvedCitizens) end
    if involvedVictims then table.insert(sets, 'involvedVictims = ?'); table.insert(params, involvedVictims) end
    if involvedOfficers then table.insert(sets, 'involvedOfficers = ?'); table.insert(params, involvedOfficers) end
    if involvedCitizenIds then table.insert(sets, 'involvedCitizenIds = ?'); table.insert(params, involvedCitizenIds) end
    if involvedVictimIds then table.insert(sets, 'involvedVictimIds = ?'); table.insert(params, involvedVictimIds) end
    if involvedOfficerIds then table.insert(sets, 'involvedOfficerIds = ?'); table.insert(params, involvedOfficerIds) end
    if involvedVehicles then table.insert(sets, 'involvedVehicles = ?'); table.insert(params, involvedVehicles) end
    if involvedVehicleIds then table.insert(sets, 'involvedVehicleIds = ?'); table.insert(params, involvedVehicleIds) end
    if charges then table.insert(sets, 'charges = ?'); table.insert(params, charges) end
    if #sets == 0 then return end
    table.insert(params, id)
    local sql = 'UPDATE pf_mdt_incidents SET ' .. table.concat(sets, ', ') .. ' WHERE incidentId = ?'
    exports.oxmysql:execute(sql, params)
end)

RegisterNetEvent('pf_mdt:closeIncident', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local id = data and data.id or nil
    if not id then return end
    exports.oxmysql:execute('UPDATE pf_mdt_incidents SET status = ? WHERE incidentId = ?', { 'closed', id })
end)

RegisterNetEvent('pf_mdt:deleteIncident', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Check permissions
    local jobName = Player.PlayerData.job.name or 'police'
    local grade = Player.PlayerData.job.grade.level or 0
    local minGrade = Config.Permissions.deleteIncidents and Config.Permissions.deleteIncidents[jobName] or 4
    
    if grade < minGrade then
        return
    end
    
    local incidentId = data and data.incidentId or nil
    if not incidentId then return end
    
    -- Delete the incident
    exports.oxmysql:execute('DELETE FROM pf_mdt_incidents WHERE incidentId = ?', { incidentId })
end)

RegisterNetEvent('pf_mdt:createReport', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local officer = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    local repId = (data and data.reportId and data.reportId ~= '') and data.reportId or ("RPT-%05d"):format(math.random(1,99999))
    local typeVal = data and data.type or 'Incident Report'
    local category = (data and (data.category or data.type)) or 'General'
    local title = data and data.title or 'Report'
    local narrative = data and data.narrative or (data and data.content) or 'N/A'
    local content = data and data.content or narrative
    local location = data and data.location or 'N/A'
    -- a new report always waits for approval (pf_mdt:approveReport); the client could set 'approved'
    local status = 'pending'
    local approvalStatus = 'pending'
    local ts = data and data.timestamp or nil
    local timestamp = ts and ts:gsub('T', ' '):gsub('Z', '') or os.date('%Y-%m-%d %H:%M:%S')
    local vehiclePlate = data and data.vehiclePlate or nil
    
    -- Build involved parties JSON
    local involved = json.encode({
        vehiclePlate = vehiclePlate,
        vehicleName = data and data.vehicleName or nil,
        citizens = data and data.linkedCitizens or {},
        weapons = data and data.linkedWeapons or {},
        incidents = data and data.linkedIncidents or {}
    })
    local evidence = json.encode(data and data.linkedEvidence or {})

    exports.oxmysql:insert('INSERT INTO pf_mdt_reports (reportId, type, category, title, officer, narrative, content, location, vehiclePlate, involvedParties, linkedEvidence, approvalStatus, status, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { repId, typeVal, category, title, officer, narrative, content, location, vehiclePlate, involved, evidence, approvalStatus, status, timestamp },
        function(insertId)
            if insertId then
                dprint('[MDT] Report created: ' .. repId .. ' by ' .. officer)
            else
                print('[MDT ERROR] Failed to create report')
            end
        end)
end)

RegisterNetEvent('pf_mdt:approveReport', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Check rank permission (ranks 3 and 4 only)
    local rankLevel = tonumber(Player.PlayerData.job.grade.level) or 0
    if rankLevel ~= 3 and rankLevel ~= 4 then
        dprint('[MDT] Player ' .. src .. ' attempted to approve report without permission (rank ' .. rankLevel .. ')')
        return
    end
    
    local reportId = data and data.reportId
    if not reportId then return end
    
    exports.oxmysql:execute('UPDATE pf_mdt_reports SET approvalStatus = ?, status = ? WHERE reportId = ?',
        { 'approved', 'approved', reportId },
        function(affectedRows)
            local affected = affectedRows
            if type(affected) == 'table' then
                affected = affected.affectedRows or affected.changedRows or 0
            end
            affected = tonumber(affected) or 0
            if affected > 0 then
                dprint('[MDT] Report ' .. reportId .. ' approved by ' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname)
            end
        end)
end)

RegisterNetEvent('pf_mdt:deleteReport', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Check permissions
    local jobName = Player.PlayerData.job.name or 'police'
    local grade = Player.PlayerData.job.grade.level or 0
    local minGrade = Config.Permissions.deleteReports and Config.Permissions.deleteReports[jobName] or 4
    
    if grade < minGrade then
        return
    end
    
    local reportId = data and data.reportId or nil
    if not reportId then return end
    
    -- Delete the report
    exports.oxmysql:execute('DELETE FROM pf_mdt_reports WHERE reportId = ?', { reportId })
end)

RegisterNetEvent('pf_mdt:createFTOReport', function(data)
    -- Legacy net event: store as a draft in the new system (best-effort)
    local src = source
    local payload = {
        traineeCid = data and (data.traineeCitizenId or data.traineeCid) or '',
        traineeName = data and (data.traineeName) or '',
        phase = tonumber(data and data.phase or 1) or 1,
        shift = 'Morning',
        rideDate = (data and data.date) and (tostring(data.date) .. ' 00:00:00') or os.date('%Y-%m-%d %H:%M:%S'),
        rideDescription = data and data.notes or nil,
        evaluation = {},
        strengths = nil,
        improvements = nil,
        recommendation = nil,
        safety_concern = 0
    }
    QBCore.Functions.TriggerCallback('pf_mdt:saveFtoDraft', src, function(_) end, payload)
end)

-- Seed command to quickly populate sample data for UI testing
QBCore.Commands.Add("mdt_seed", "Seed sample MDT records (Admin)", {}, false, function(source, args)
    local src = source
    local seeded = 0
    -- Writes fake warrants and reports into the real tables, so it stays off unless the
    -- server owner turns it on for a test server.
    if not (Config and Config.AllowSeedCommand == true) then
        TriggerClientEvent('QBCore:Notify', src, 'mdt_seed is disabled (Config.AllowSeedCommand)', 'error')
        return
    end

    if hasOxMySQL() and exports.oxmysql then
        -- Warrant
        exports.oxmysql:insert('INSERT INTO pf_mdt_warrants (warrantId, suspectName, charges, officers, witnesses, issuedBy, title, narrative, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { 'W00001', 'John Doe', json.encode({'Robbery','GTA'}), json.encode({'Chief Tester'}), json.encode({}), 'Chief Tester', 'Test Warrant', 'Armed and dangerous', 'active' })
        seeded = seeded + 1

        -- Incident
        exports.oxmysql:insert('INSERT INTO pf_mdt_incidents (incidentId, title, priority, status, location, narrative, createdBy) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { 'INC-00001', 'Store Robbery', 'HIGH', 'active', 'Grove St', 'Multiple suspects fled in a black Sultan', 'system' })
        seeded = seeded + 1

        -- Report
        exports.oxmysql:insert('INSERT INTO pf_mdt_reports (reportId, type, title, officer, content) VALUES (?, ?, ?, ?, ?)',
            { 'REP-00001', 'Incident Report', 'Pursuit Summary', 'Chief Tester', 'Summary of pursuit with outcome.' })
        seeded = seeded + 1

        -- FTO Report
        exports.oxmysql:insert('INSERT INTO pf_mdt_fto_reports (traineeCitizenId, traineeName, ftoCitizenId, ftoName, phase, rating, status, notes, date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { 'CIDTEST', 'Probationary Officer', 'CIDFTO', 'FTO Smith', 'Phase 1', 4.5, 'completed', 'Good performance', os.date('%Y-%m-%d') })
        seeded = seeded + 1

        TriggerClientEvent('QBCore:Notify', src, ('Seeded %d records'):format(seeded), 'success')
    else
        -- Fallback: memory-only warrant
        table.insert(WarrantsStore, {
            warrantId = 'W00002', suspectName = 'Jane Roe', charges = {'Assault'}, issuedBy = 'Chief Tester', issuedAt = os.date('%Y-%m-%d %H:%M:%S'), status = 'active'
        })
        TriggerClientEvent('QBCore:Notify', src, 'Seeded in-memory warrant (no DB)', 'success')
    end
end, "admin")

-- Government records for a citizen (pf-government tables): licenses, unpaid bills and
-- fines, registered businesses. Read only. Missing tables give an empty record.
local function fetchGovernmentRecord(citizenId, done)
    local record = { licenses = {}, unpaidBills = {}, unpaidTotal = 0, businesses = {} }
    if not citizenId or citizenId == '' or not exports.oxmysql then return done(record) end
    local pending = 3
    local function step()
        pending = pending - 1
        if pending == 0 then done(record) end
    end
    local function q(sql, params, onRows)
        local ok = pcall(function()
            exports.oxmysql:query(sql, params, function(rows)
                if type(rows) == 'table' then pcall(onRows, rows) end
                step()
            end)
        end)
        if not ok then step() end
    end
    q([[SELECT license_type, status, issued_at, expires_at FROM pf_gov_licenses
        WHERE owner_type = 'citizen' AND owner_id = ? ORDER BY issued_at DESC LIMIT 50]], { citizenId }, function(rows)
        for _, r in ipairs(rows) do
            record.licenses[#record.licenses + 1] = { type = r.license_type, status = r.status, issuedAt = r.issued_at, expiresAt = r.expires_at }
        end
    end)
    q([[SELECT id, bill_type, amount, amount_paid, status, description, due_date, issued_at FROM pf_gov_bills
        WHERE target_type = 'citizen' AND target_id = ? AND status IN ('unpaid','partial','delinquent')
        ORDER BY issued_at DESC LIMIT 50]], { citizenId }, function(rows)
        for _, r in ipairs(rows) do
            local owed = (tonumber(r.amount) or 0) - (tonumber(r.amount_paid) or 0)
            record.unpaidTotal = record.unpaidTotal + owed
            record.unpaidBills[#record.unpaidBills + 1] = { id = r.id, type = r.bill_type, owed = owed, status = r.status, description = r.description, dueDate = r.due_date, issuedAt = r.issued_at }
        end
    end)
    -- businesses come from pf-government's registry export (its table is not ours to read)
    CreateThread(function()
        local ok, list = pcall(function() return exports['pf-government']:GetBusinessesOwnedBy({ citizenId }) end)
        for _, b in ipairs(ok and type(list) == 'table' and list or {}) do
            if #record.businesses >= 25 then break end
            record.businesses[#record.businesses + 1] = { id = b.id, name = b.name, type = b.type, license = b.license, compliance = b.compliance }
        end
        step()
    end)
end

-- Profiles: Citizens & Vehicles (details + CRUD for notes/flags/strikes)
QBCore.Functions.CreateCallback('pf_mdt:getCitizenProfile', function(source, cb, data)
    local citizenId = data and (data.citizenId or data.id) or ''

    -- Best-effort DB schema caches to avoid repeated information_schema hits.
    local __schemaCache = __schemaCache or { tables = {}, columns = {} }

    local function dbTableExists(tableName, done)
        if tableName == nil or tableName == '' then return done(false) end
        if __schemaCache.tables[tableName] ~= nil then return done(__schemaCache.tables[tableName]) end
        exports.oxmysql:execute(
            'SELECT COUNT(*) as c FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? LIMIT 1',
            { tableName },
            function(rows)
                local ok = rows and rows[1] and tonumber(rows[1].c or 0) > 0 or false
                __schemaCache.tables[tableName] = ok
                done(ok)
            end
        )
    end

    local function dbTableHasColumn(tableName, columnName, done)
        if tableName == nil or tableName == '' or columnName == nil or columnName == '' then return done(false) end
        __schemaCache.columns[tableName] = __schemaCache.columns[tableName] or {}
        if __schemaCache.columns[tableName][columnName] ~= nil then return done(__schemaCache.columns[tableName][columnName]) end
        exports.oxmysql:execute(
            'SELECT COUNT(*) as c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? LIMIT 1',
            { tableName, columnName },
            function(rows)
                local ok = rows and rows[1] and tonumber(rows[1].c or 0) > 0 or false
                __schemaCache.columns[tableName][columnName] = ok
                done(ok)
            end
        )
    end

    local function resolveCitizenPhone(preferredFallbackPhone, done)
        local cfg = (Config and Config.Integrations and Config.Integrations.Phone) or {}
        local preferQbPhone = cfg.PreferQbPhone == true
        local fallbackAllowed = cfg.FallbackToCharinfo ~= false

        local function finish(phone)
            if phone ~= nil and tostring(phone) ~= '' then
                done(tostring(phone))
                return
            end
            if fallbackAllowed then
                done(tostring(preferredFallbackPhone or ''))
                return
            end
            done('')
        end

        if not preferQbPhone then
            finish(nil)
            return
        end

        -- Try common qb-phone style tables/columns (best-effort).
        local candidates = {
            { table = 'phone_phones', cidCol = 'citizenid', phoneCol = 'phone_number' },
            { table = 'phone_phones', cidCol = 'citizenid', phoneCol = 'number' },
            { table = 'player_phones', cidCol = 'citizenid', phoneCol = 'phone_number' },
            { table = 'player_phones', cidCol = 'citizenid', phoneCol = 'number' },
            { table = 'phone_users', cidCol = 'citizenid', phoneCol = 'phone_number' },
            { table = 'phone_users', cidCol = 'citizenid', phoneCol = 'number' },
        }

        local i = 1
        local function nextCandidate()
            local c = candidates[i]
            i = i + 1
            if not c then
                finish(nil)
                return
            end

            dbTableExists(c.table, function(exists)
                if not exists then
                    nextCandidate()
                    return
                end
                dbTableHasColumn(c.table, c.cidCol, function(hasCid)
                    if not hasCid then
                        nextCandidate()
                        return
                    end
                    dbTableHasColumn(c.table, c.phoneCol, function(hasPhone)
                        if not hasPhone then
                            nextCandidate()
                            return
                        end
                        exports.oxmysql:execute(
                            ('SELECT `%s` as phone FROM `%s` WHERE `%s` = ? LIMIT 1'):format(c.phoneCol, c.table, c.cidCol),
                            { citizenId },
                            function(rows)
                                local phone = rows and rows[1] and rows[1].phone or nil
                                finish(phone)
                            end
                        )
                    end)
                end)
            end)
        end

        nextCandidate()
    end

    local function fetchCitizenProperties(done)
        local propsCfg = (Config and Config.Integrations and Config.Integrations.Properties) or {}
        if propsCfg.Enabled == false then
            done({})
            return
        end

        local properties = {}

        local function normalizeCoords(raw)
            if raw == nil then return nil end
            if type(raw) == 'table' then
                -- Common patterns: {x=,y=,z=} or {enter={x=,y=,z=}} or {coords={x=,y=,z=}}
                if raw.x and raw.y then return { x = tonumber(raw.x), y = tonumber(raw.y), z = tonumber(raw.z) or 0.0 } end
                if raw.enter and type(raw.enter) == 'table' and raw.enter.x and raw.enter.y then
                    return { x = tonumber(raw.enter.x), y = tonumber(raw.enter.y), z = tonumber(raw.enter.z) or 0.0 }
                end
                if raw.coords and type(raw.coords) == 'table' and raw.coords.x and raw.coords.y then
                    return { x = tonumber(raw.coords.x), y = tonumber(raw.coords.y), z = tonumber(raw.coords.z) or 0.0 }
                end
                if raw.coords and type(raw.coords) == 'table' and raw.coords.enter and type(raw.coords.enter) == 'table' and raw.coords.enter.x and raw.coords.enter.y then
                    return { x = tonumber(raw.coords.enter.x), y = tonumber(raw.coords.enter.y), z = tonumber(raw.coords.enter.z) or 0.0 }
                end
                return nil
            end
            if type(raw) == 'string' then
                local ok, decoded = pcall(json.decode, raw)
                if ok and decoded ~= nil then
                    return normalizeCoords(decoded)
                end
            end
            return nil
        end

        local function addProp(sourceName, displayName, address, coords)
            if displayName == nil or tostring(displayName) == '' then return end
            local name = tostring(displayName)
            local addr = (address ~= nil and tostring(address) ~= '') and tostring(address) or name
            local c = normalizeCoords(coords)
            properties[#properties + 1] = { source = sourceName, name = name, address = addr, coords = c }
        end

        local function fetchQbHouses(next)
            if not (propsCfg.Providers and propsCfg.Providers.QbHouses) then
                next()
                return
            end
            dbTableExists('player_houses', function(exists)
                if not exists then
                    next()
                    return
                end

                -- Common qb-houses schema: player_houses(citizenid, house, keyholders, ...)
                dbTableHasColumn('player_houses', 'citizenid', function(hasCid)
                    if not hasCid then
                        next()
                        return
                    end
                    dbTableHasColumn('player_houses', 'house', function(hasHouse)
                        if not hasHouse then
                            next()
                            return
                        end
                        exports.oxmysql:execute('SELECT house FROM player_houses WHERE citizenid = ? ORDER BY house ASC', { citizenId }, function(rows)
                            local houses = {}
                            for _, r in ipairs(rows or {}) do
                                if r.house ~= nil and tostring(r.house) ~= '' then
                                    houses[#houses + 1] = tostring(r.house)
                                end
                            end
                            if #houses == 0 then
                                next()
                                return
                            end

                            -- Optional enrichment from houselocations if present.
                            dbTableExists('houselocations', function(hasLoc)
                                if not hasLoc then
                                    for _, h in ipairs(houses) do addProp('qb-houses', h, h, nil) end
                                    next()
                                    return
                                end

                                local nameCols = { 'name', 'house', 'housename' }
                                local labelCols = { 'label', 'address', 'street' }
                                local coordsCols = { 'coords', 'enter', 'location', 'pos', 'position' }

                                local function pickFirstColumn(tableName, candidates, doneCol)
                                    local idx = 1
                                    local function step()
                                        local c = candidates[idx]
                                        idx = idx + 1
                                        if not c then doneCol(nil); return end
                                        dbTableHasColumn(tableName, c, function(ok)
                                            if ok then doneCol(c) else step() end
                                        end)
                                    end
                                    step()
                                end

                                pickFirstColumn('houselocations', nameCols, function(locNameCol)
                                    if not locNameCol then
                                        for _, h in ipairs(houses) do addProp('qb-houses', h, h, nil) end
                                        next()
                                        return
                                    end

                                    pickFirstColumn('houselocations', labelCols, function(locLabelCol)
                                        pickFirstColumn('houselocations', coordsCols, function(locCoordsCol)
                                            -- Build IN clause placeholders
                                            local ph = {}
                                            for _ = 1, #houses do ph[#ph+1] = '?' end
                                            local selectCols = ('`%s` as houseKey'):format(locNameCol)
                                            if locLabelCol then selectCols = selectCols .. (', `' .. locLabelCol .. '` as label') end
                                            if locCoordsCol then selectCols = selectCols .. (', `' .. locCoordsCol .. '` as coords') end
                                            local q = ('SELECT %s FROM `houselocations` WHERE `%s` IN (%s)'):format(selectCols, locNameCol, table.concat(ph, ','))

                                            exports.oxmysql:execute(q, houses, function(lrows)
                                                local map = {}
                                                for _, lr in ipairs(lrows or {}) do
                                                    local key = lr.houseKey ~= nil and tostring(lr.houseKey) or nil
                                                    if key and key ~= '' then
                                                        map[key] = {
                                                            label = lr.label,
                                                            coords = lr.coords,
                                                        }
                                                    end
                                                end
                                                for _, h in ipairs(houses) do
                                                    local m = map[h]
                                                    local addr = (m and m.label and tostring(m.label) ~= '') and tostring(m.label) or h
                                                    local coords = m and m.coords or nil
                                                    addProp('qb-houses', h, addr, coords)
                                                end
                                                next()
                                            end)
                                        end)
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end

        local function fetchNoLag(next)
            if not (propsCfg.Providers and propsCfg.Providers.NoLag) then
                next()
                return
            end

            -- Best-effort: locate a table name that looks like NoLag properties and has a citizenid-like column.
            exports.oxmysql:execute(
                "SELECT TABLE_NAME as name FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND (TABLE_NAME LIKE 'nolag%propert%' OR TABLE_NAME LIKE 'nolag%house%' OR TABLE_NAME LIKE 'nl_%propert%' OR TABLE_NAME LIKE 'nl_%house%') LIMIT 10",
                {},
                function(trows)
                    local tables = {}
                    for _, tr in ipairs(trows or {}) do tables[#tables + 1] = tr.name end
                    if #tables == 0 then
                        next()
                        return
                    end

                    local ti = 1
                    local function tryTable()
                        local tableName = tables[ti]
                        ti = ti + 1
                        if not tableName then
                            next()
                            return
                        end

                        local cidCols = { 'citizenid', 'owner', 'owner_citizenid', 'ownerCitizenId', 'citizenId' }
                        local nameCols = { 'label', 'name', 'property', 'house', 'address', 'street', 'property_id', 'propertyId', 'id' }
                        local coordsCols = { 'coords', 'enter', 'location', 'pos', 'position' }

                        local cidIdx = 1
                        local function pickCidCol(chosenCidCol)
                            if chosenCidCol then
                                local nameIdx = 1
                                local function pickNameCol(chosenNameCol)
                                    if chosenNameCol then
                                        -- Try to include coords if available
                                        local function pickCoordsCol(doneCoordsCol)
                                            local idx = 1
                                            local function stepC()
                                                local c = coordsCols[idx]
                                                idx = idx + 1
                                                if not c then doneCoordsCol(nil); return end
                                                dbTableHasColumn(tableName, c, function(has)
                                                    if has then doneCoordsCol(c) else stepC() end
                                                end)
                                            end
                                            stepC()
                                        end

                                        pickCoordsCol(function(chosenCoordsCol)
                                            local selectCols = ('`%s` as pname'):format(chosenNameCol)
                                            if chosenCoordsCol then selectCols = selectCols .. (', `' .. chosenCoordsCol .. '` as coords') end
                                            local q = ('SELECT %s FROM `%s` WHERE `%s` = ? LIMIT 50'):format(selectCols, tableName, chosenCidCol)
                                            exports.oxmysql:execute(q, { citizenId }, function(rows)
                                                for _, r in ipairs(rows or {}) do
                                                    addProp('nolag-properties', r.pname, r.pname, r.coords)
                                                end
                                                next()
                                            end)
                                        end)
                                        return
                                    end

                                    local col = nameCols[nameIdx]
                                    nameIdx = nameIdx + 1
                                    if not col then
                                        -- No name-ish columns; skip.
                                        tryTable()
                                        return
                                    end
                                    dbTableHasColumn(tableName, col, function(has)
                                        if has then
                                            pickNameCol(col)
                                        else
                                            pickNameCol(nil)
                                        end
                                    end)
                                end
                                pickNameCol(nil)
                                return
                            end

                            local col = cidCols[cidIdx]
                            cidIdx = cidIdx + 1
                            if not col then
                                tryTable()
                                return
                            end
                            dbTableHasColumn(tableName, col, function(has)
                                if has then
                                    pickCidCol(col)
                                else
                                    pickCidCol(nil)
                                end
                            end)
                        end

                        pickCidCol(nil)
                    end

                    tryTable()
                end
            )
        end

        local function fetchApartments(next)
            -- Include apartments automatically when an `apartments` table exists.
            dbTableExists('apartments', function(exists)
                if not exists then
                    next()
                    return
                end

                -- Your schema (qb-apartments style): apartments(id, name, type, label, citizenid)
                dbTableHasColumn('apartments', 'citizenid', function(hasCid)
                    if not hasCid then
                        next()
                        return
                    end

                    dbTableHasColumn('apartments', 'type', function(hasType)
                        -- type is optional for display, but helps for coords mapping.
                        local selectCols = 'label as label'
                        if hasType then selectCols = selectCols .. ', type as aptType' end
                        exports.oxmysql:execute(('SELECT %s FROM apartments WHERE citizenid = ? LIMIT 50'):format(selectCols), { citizenId }, function(rows)
                                local types = {}
                                for _, r in ipairs(rows or {}) do
                                    if r.aptType ~= nil and tostring(r.aptType) ~= '' then
                                        types[#types + 1] = tostring(r.aptType)
                                    end
                                end

                                local function buildTypeCoordsMap(doneMap)
                                    if not hasType or #types == 0 then
                                        doneMap({})
                                        return
                                    end

                                    local locationTables = {
                                        'apartments_locations',
                                        'apartment_locations',
                                        'apartmentlocations',
                                        'apartments_location',
                                        'apartment_location',
                                    }

                                    local tableIdx = 1
                                    local function tryNextTable()
                                        local tname = locationTables[tableIdx]
                                        tableIdx = tableIdx + 1
                                        if not tname then
                                            doneMap({})
                                            return
                                        end

                                        dbTableExists(tname, function(existsLoc)
                                            if not existsLoc then
                                                tryNextTable()
                                                return
                                            end

                                            local typeCols = { 'type', 'name', 'apartment', 'apartment_type' }
                                            local coordsCols = { 'coords', 'enter', 'location', 'pos', 'position' }

                                            local function pickFirstColumn(tableName, candidates, doneCol)
                                                local idx = 1
                                                local function step()
                                                    local c = candidates[idx]
                                                    idx = idx + 1
                                                    if not c then doneCol(nil); return end
                                                    dbTableHasColumn(tableName, c, function(ok)
                                                        if ok then doneCol(c) else step() end
                                                    end)
                                                end
                                                step()
                                            end

                                            pickFirstColumn(tname, typeCols, function(typeCol)
                                                if not typeCol then
                                                    tryNextTable()
                                                    return
                                                end
                                                pickFirstColumn(tname, coordsCols, function(coordsCol)
                                                    if not coordsCol then
                                                        tryNextTable()
                                                        return
                                                    end

                                                    local ph = {}
                                                    for _ = 1, #types do ph[#ph+1] = '?' end
                                                    local q = ('SELECT `%s` as t, `%s` as coords FROM `%s` WHERE `%s` IN (%s)'):format(typeCol, coordsCol, tname, typeCol, table.concat(ph, ','))
                                                    exports.oxmysql:execute(q, types, function(lrows)
                                                        local map = {}
                                                        for _, lr in ipairs(lrows or {}) do
                                                            local key = lr.t ~= nil and tostring(lr.t) or nil
                                                            if key and key ~= '' then
                                                                map[key] = lr.coords
                                                            end
                                                        end
                                                        doneMap(map)
                                                    end)
                                                end)
                                            end)
                                        end)
                                    end

                                    tryNextTable()
                                end

                                buildTypeCoordsMap(function(typeCoords)
                                    for _, r in ipairs(rows or {}) do
                                        local label = r.label
                                        local t = r.aptType ~= nil and tostring(r.aptType) or nil
                                        local coords = (t and typeCoords and typeCoords[t]) or nil
                                        addProp('apartments', label, label, coords)
                                    end
                                    next()
                                end)
                            end)
                        end)
                    end)
            end)
        end

        fetchQbHouses(function()
            fetchApartments(function()
                fetchNoLag(function()
                    done(properties)
                end)
            end)
        end)
    end

    local profile = {
        citizenId = citizenId,
        name = 'Unknown',
        firstname = '',
        lastname = '',
        dob = '',
        age = -1,  -- Use -1 as sentinel to distinguish from 0
        phone = '',
        nationality = '',
        gender = '',
        job = 'Unemployed',
        address = '',
        -- Physical appearance with better defaults
        skin = 'Not recorded',
        hairColor = 'Not recorded',
        eyeColor = 'Not recorded',
        height = 'Not recorded',
        -- Status flags
        hasWarrant = false,
        isDangerous = false,
        isBOLO = false,
        -- Counters
        warrantCount = 0,
        arrestCount = 0,
        convictionCount = 0,
        vehicleCount = 0,
        -- Data arrays
        licenses = {},
        flags = {},
        notes = {},
        warrants = {},
        vehicles = {},
        properties = {},
        incidents = {},
        reports = {},
        -- Optional panels
        insurancePanelEnabled = (Config and Config.Integrations and Config.Integrations.Insurance and Config.Integrations.Insurance.Enabled) == true,
        insurance = {
            active = false,
            provider = nil,
            label = nil,
            expiresAt = nil,
        }
    }
    
    if hasOxMySQL() and exports.oxmysql and citizenId ~= '' then
        exports.oxmysql:execute('SELECT citizenid, charinfo, job, metadata FROM players WHERE citizenid = ? LIMIT 1', { citizenId }, function(rows)
            local fallbackPhone = ''
            if rows and rows[1] then
                local r = rows[1]
                local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
                local meta = type(r.metadata) == 'string' and json.decode(r.metadata) or r.metadata or {}
                local job = r.job
                if type(job) == 'string' then
                    local ok, parsed = pcall(json.decode, job)
                    if ok and parsed then job = parsed end
                end
                
                -- Basic identity
                profile.firstname = ci.firstname or ''
                profile.lastname = ci.lastname or ''
                profile.name = (profile.firstname .. ' ' .. profile.lastname):gsub('^%s*(.-)%s*$', '%1')
                profile.dob = ci.birthdate or ''
                fallbackPhone = ci.phone or ''
                profile.phone = fallbackPhone
                profile.nationality = ci.nationality or ''
                
                -- Gender from charinfo (0 = Male, 1 = Female)
                if ci.gender == 0 then
                    profile.gender = 'Male'
                elseif ci.gender == 1 then
                    profile.gender = 'Female'
                else
                    profile.gender = 'Unknown'
                end
                
                profile.address = ci.address or ''
                profile.job = (job and (job.label or job.name)) or 'Unemployed'

                -- Licenses
                if isESXFramework() then
                    local licFlags, suspensions = esxGetLicenseState(citizenId)
                    profile.licenses = licFlags
                    profile.licenseSuspensions = suspensions
                else
                    -- QBCore: Licenses from metadata.licences (UK spelling)
                    do
                        local lic = (meta.licences or meta.licenses or {})
                        local suspensions = meta.licenseSuspensions or {}
                        local now = os.time()
                        local updated = false

                        -- Check and restore expired suspensions
                        for licType, expiryStr in pairs(suspensions) do
                            if expiryStr then
                                -- Parse expiry date (YYYY-MM-DD HH:MM:SS)
                                local y, m, d, h, min, s = expiryStr:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
                                if y then
                                    local expiryTime = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=tonumber(h), min=tonumber(min), sec=tonumber(s)})
                                    if now >= expiryTime then
                                        -- Suspension expired, restore license
                                        if not meta.licences then meta.licences = {} end
                                        meta.licences[licType] = true
                                        suspensions[licType] = nil
                                        updated = true
                                        dprint('^2[MDT]^7 Auto-restored expired license: ' .. licType .. ' for citizen ' .. licType)
                                    end
                                end
                            end
                        end

                        -- Update database if any suspensions expired
                        if updated then
                            meta.licenseSuspensions = suspensions
                            exports.oxmysql:execute('UPDATE players SET metadata = ? WHERE citizenid = ?', { json.encode(meta), citizenId })
                        end

                        profile.licenses = {
                            driver = lic.driver == true,
                            weapon = lic.weapon == true,
                            business = lic.business == true,
                        }
                        profile.licenseSuspensions = suspensions
                    end
                end
                
                -- Physical appearance defaults; will be overridden by playerskins when available
                profile.skin = meta.skin or meta.skinType or 'Not recorded'
                profile.hairColor = meta.hairColor or meta.hair or 'Not recorded'
                profile.eyeColor = meta.eyeColor or meta.eyes or 'Not recorded'
                profile.height = meta.height or 'Not recorded'
                profile.appearance = nil
                
                -- Calculate age from DOB
                if profile.dob and profile.dob ~= '' then
                    local y, m, d = profile.dob:match('(%d%d%d%d)%-(%d%d)%-(%d%d)')
                    if y and m and d then
                        local birthYear = tonumber(y)
                        local birthMonth = tonumber(m)
                        local birthDay = tonumber(d)
                        local currentYear = tonumber(os.date('%Y'))
                        local currentMonth = tonumber(os.date('%m'))
                        local currentDay = tonumber(os.date('%d'))
                        
                        profile.age = currentYear - birthYear
                        -- Adjust if birthday hasn't occurred this year
                        if currentMonth < birthMonth or (currentMonth == birthMonth and currentDay < birthDay) then
                            profile.age = profile.age - 1
                        end
                        dprint('^2[MDT DEBUG]^7 Age calculated: DOB=' .. profile.dob .. ' Age=' .. profile.age)
                    else
                        -- Fallback if regex doesn't match - just use year subtraction
                        local y = profile.dob:match('(%d%d%d%d)')
                        if y then
                            profile.age = tonumber(os.date('%Y')) - tonumber(y)
                            dprint('^2[MDT DEBUG]^7 Age calculated (fallback): DOB=' .. profile.dob .. ' Age=' .. profile.age)
                        else
                            dprint('^3[MDT DEBUG]^7 DOB parsing failed: ' .. tostring(profile.dob))
                        end
                    end
                else
                    dprint('^3[MDT DEBUG]^7 No DOB found for citizen ' .. citizenId)
                end
            end

            if (not rows or not rows[1]) and IsManualEntriesEnabled() then
                local p = promise.new()
                exports.oxmysql:execute(
                    'SELECT citizenId, firstname, lastname, dob, phone, nationality, gender, job, address, profilePicture FROM pf_mdt_manual_citizens WHERE citizenId = ? LIMIT 1',
                    { citizenId },
                    function(mrows)
                        local mr = mrows and mrows[1]
                        if mr then
                            profile.citizenId = tostring(mr.citizenId or citizenId)
                            profile.firstname = tostring(mr.firstname or '')
                            profile.lastname = tostring(mr.lastname or '')
                            profile.name = (profile.firstname .. ' ' .. profile.lastname):gsub('^%s*(.-)%s*$', '%1')
                            if profile.name == '' then profile.name = 'Unknown' end
                            profile.dob = tostring(mr.dob or '')
                            fallbackPhone = tostring(mr.phone or '')
                            profile.phone = fallbackPhone
                            profile.nationality = tostring(mr.nationality or '')
                            profile.gender = tostring(mr.gender or 'Unknown')
                            profile.job = tostring(mr.job or 'Unemployed')
                            profile.address = tostring(mr.address or '')
                            profile.profilePicture = tostring(mr.profilePicture or '')

                            if profile.dob ~= '' then
                                local y, m, d = profile.dob:match('(%d%d%d%d)%-(%d%d)%-(%d%d)')
                                if y and m and d then
                                    local birthYear = tonumber(y)
                                    local birthMonth = tonumber(m)
                                    local birthDay = tonumber(d)
                                    local currentYear = tonumber(os.date('%Y'))
                                    local currentMonth = tonumber(os.date('%m'))
                                    local currentDay = tonumber(os.date('%d'))
                                    profile.age = currentYear - birthYear
                                    if currentMonth < birthMonth or (currentMonth == birthMonth and currentDay < birthDay) then
                                        profile.age = profile.age - 1
                                    end
                                end
                            end
                        end
                        p:resolve(true)
                    end
                )
                Citizen.Await(p)
            end

            local function continueProfileFetch()
                -- Resolve qb-phone number before rendering the profile.
                resolveCitizenPhone(fallbackPhone, function(resolvedPhone)
                    profile.phone = resolvedPhone or profile.phone or ''

                    -- Fetch flags
                    exports.oxmysql:execute('SELECT flag FROM pf_mdt_citizen_flags WHERE citizenId = ? ORDER BY createdAt DESC', { citizenId }, function(frows)
                        profile.flags = {}
                        profile.isDangerous = false
                        profile.isBOLO = false
                        for _, fr in ipairs(frows or {}) do
                            if fr.flag then
                                profile.flags[#profile.flags+1] = fr.flag
                                local low = tostring(fr.flag):lower()
                                if low == 'dangerous' then profile.isDangerous = true end
                                if low == 'bolo' then profile.isBOLO = true end
                            end
                        end

                        -- Fetch profile picture
                        exports.oxmysql:execute('SELECT profilePicture FROM pf_mdt_citizen_profiles WHERE citizenId = ? LIMIT 1', { citizenId }, function(prows)
                            if prows and prows[1] then
                                profile.profilePicture = prows[1].profilePicture
                            end

                            -- Fetch notes
                            exports.oxmysql:execute('SELECT text, author, createdAt FROM pf_mdt_citizen_notes WHERE citizenId = ? ORDER BY createdAt DESC', { citizenId }, function(nrows)
                                profile.notes = nrows or {}

                                -- Fetch warrants
                                exports.oxmysql:execute('SELECT warrantId, suspectName, charges, officers, witnesses, issuedBy, title, createdAt, status, narrative FROM pf_mdt_warrants WHERE suspectCitizenId = ? OR suspectName = ? ORDER BY createdAt DESC', { citizenId, profile.name }, function(wrows)
                                    profile.warrants = {}
                                    profile.hasWarrant = false
                                    profile.warrantCount = 0
                                    for _, w in ipairs(wrows or {}) do
                                        local charges = type(w.charges) == 'string' and json.decode(w.charges) or w.charges or {}
                                        local officers = type(w.officers) == 'string' and json.decode(w.officers) or w.officers or {}
                                        local witnesses = type(w.witnesses) == 'string' and json.decode(w.witnesses) or w.witnesses or {}
                                        profile.warrants[#profile.warrants+1] = {
                                            warrantId = w.warrantId,
                                            suspectName = w.suspectName or profile.name,
                                            charges = charges,
                                            officers = officers,
                                            witnesses = witnesses,
                                            title = w.title,
                                            issuedBy = w.issuedBy,
                                            createdAt = w.createdAt,
                                            status = w.status,
                                            narrative = w.narrative
                                        }
                                        if w.status == 'active' then
                                            profile.hasWarrant = true
                                            profile.warrantCount = profile.warrantCount + 1
                                        end
                                    end

                                    -- Vehicles
                                    exports.oxmysql:execute('SELECT plate, vehicle, mods FROM player_vehicles WHERE citizenid = ?', { citizenId }, function(vrows)
                                        profile.vehicles = {}
                                        profile.vehicleCount = 0
                                        for _, v in ipairs(vrows or {}) do
                                            local mapped = MapVehicleRow(v)
                                            if mapped then
                                                profile.vehicles[#profile.vehicles+1] = mapped
                                                profile.vehicleCount = profile.vehicleCount + 1
                                            end
                                        end

                                        if IsManualEntriesEnabled() then
                                            local pv = promise.new()
                                            exports.oxmysql:execute(
                                                'SELECT plate, ownerCitizenId, ownerName, model, modelLabel, brand, primaryColorId, secondaryColorId, vehiclePhoto FROM pf_mdt_manual_vehicles WHERE ownerCitizenId = ?',
                                                { citizenId },
                                                function(mrows)
                                                    for _, mv in ipairs(mrows or {}) do
                                                        local mapped = MapManualVehicleRow(mv)
                                                        if mapped then
                                                            profile.vehicles[#profile.vehicles + 1] = mapped
                                                            profile.vehicleCount = profile.vehicleCount + 1
                                                        end
                                                    end
                                                    pv:resolve(true)
                                                end
                                            )
                                            Citizen.Await(pv)
                                        end

                                        -- Incidents
                                        local nameLike = '%' .. (profile.name or '') .. '%'
                                        local idLike = '%' .. citizenId .. '%'
                                        exports.oxmysql:execute('SELECT incidentId, title, status, location, createdAt FROM pf_mdt_incidents WHERE involvedCitizenIds LIKE ? OR involvedCitizens LIKE ? ORDER BY createdAt DESC LIMIT 20', { idLike, nameLike }, function(irows)
                                            profile.incidents = irows or {}

                                            -- Reports (content OR involvedParties)
                                            local likeCid = '%"' .. citizenId .. '"%'
                                            exports.oxmysql:execute('SELECT reportId, type, title, officer, createdAt FROM pf_mdt_reports WHERE content LIKE ? OR involvedParties LIKE ? ORDER BY createdAt DESC LIMIT 50', { nameLike, likeCid }, function(rrows)
                                                profile.reports = rrows or {}

                                                -- Properties (qb-houses / nolag)
                                                fetchCitizenProperties(function(properties)
                                                    profile.properties = properties or {}
                                                    profile.propertyCount = #profile.properties

                                                    local function fetchConvictionCount(done)
                                                        -- Convictions = number of times actually jailed (prison time > 0)
                                                        dbTableExists('pf_mdt_sentences', function(exists)
                                                            if not exists then done(0) return end
                                                            dbTableHasColumn('pf_mdt_sentences', 'prisonTimeAfterReduction', function(hasAfter)
                                                                local timeCol = hasAfter and 'prisonTimeAfterReduction' or 'prisonTime'
                                                                dbTableHasColumn('pf_mdt_sentences', 'jailSuccess', function(hasJailSuccess)
                                                                    local where = ' AND `' .. timeCol .. '` > 0'
                                                                    if hasJailSuccess then
                                                                        where = where .. ' AND jailSuccess = 1'
                                                                    end
                                                                    exports.oxmysql:execute('SELECT COUNT(*) as c FROM pf_mdt_sentences WHERE citizenId = ?' .. where, { citizenId }, function(crows)
                                                                        local cnt = 0
                                                                        if crows and crows[1] and crows[1].c ~= nil then
                                                                            cnt = tonumber(crows[1].c) or 0
                                                                        end
                                                                        done(cnt)
                                                                    end)
                                                                end)
                                                            end)
                                                        end)
                                                    end

                                                    -- Insurance: no DB backing yet (pf-government later)
                                                    profile.insurancePanelEnabled = (Config and Config.Integrations and Config.Integrations.Insurance and Config.Integrations.Insurance.Enabled) == true
                                                    profile.insurance = profile.insurance or { active = false }
                                                    profile.insurance.active = false

                                                    fetchGovernmentRecord(citizenId, function(gov)
                                                    profile.government = gov
                                                    fetchConvictionCount(function(cnt)
                                                        profile.convictionCount = tonumber(cnt) or 0
                                                        dprint('^6[MDT PROFILE]^7 Returning profile for ' .. (profile.name or 'Unknown') .. ' (properties=' .. tostring(profile.propertyCount or 0) .. ', convictions=' .. tostring(profile.convictionCount or 0) .. ')')
                                                        cb(profile)
                                                    end)
                                                    end)
                                                end)
                                            end)
                                        end)
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end

            local function fetchAppearanceAndContinue()
                if not (hasOxMySQL() and exports.oxmysql) then
                    continueProfileFetch()
                    return
                end

                if isESXFramework() then
                    if not esxHasUserSkinsCached() then
                        continueProfileFetch()
                        return
                    end

                    exports.oxmysql:execute('SELECT skin FROM userskins WHERE identifier = ? LIMIT 1', { citizenId }, function(psRows)
                        if psRows and psRows[1] and psRows[1].skin then
                            local appearance = buildAppearanceFromPlayerskin({ model = nil, skin = psRows[1].skin }) or {}
                            profile.appearance = appearance
                            profile.skin = appearance.skinToneLabel or profile.skin or 'Not recorded'
                            profile.hairColor = appearance.hairColorLabel or profile.hairColor or 'Not recorded'
                            profile.eyeColor = appearance.eyeColorLabel or profile.eyeColor or 'Not recorded'
                            profile.height = appearance.heightLabel or profile.height or 'Not recorded'
                        else
                            dprint('[pf_mdt] No userskins row found for identifier ' .. citizenId)
                            profile.skin = profile.skin or 'Not recorded'
                            profile.hairColor = profile.hairColor or 'Not recorded'
                            profile.eyeColor = profile.eyeColor or 'Not recorded'
                            profile.height = profile.height or 'Not recorded'
                        end
                        continueProfileFetch()
                    end)
                    return
                end

                exports.oxmysql:execute('SELECT model, skin FROM playerskins WHERE citizenid = ? AND active = 1 ORDER BY id DESC LIMIT 1', { citizenId }, function(psRows)
                    if psRows and psRows[1] then
                        local appearance = buildAppearanceFromPlayerskin(psRows[1]) or {}
                        profile.appearance = appearance
                        profile.skin = appearance.skinToneLabel or profile.skin or 'Not recorded'
                        profile.hairColor = appearance.hairColorLabel or profile.hairColor or 'Not recorded'
                        profile.eyeColor = appearance.eyeColorLabel or profile.eyeColor or 'Not recorded'
                        profile.height = appearance.heightLabel or profile.height or 'Not recorded'
                    else
                        dprint('[pf_mdt] No active playerskin found for citizenid ' .. citizenId)
                        profile.skin = profile.skin or 'Not recorded'
                        profile.hairColor = profile.hairColor or 'Not recorded'
                        profile.eyeColor = profile.eyeColor or 'Not recorded'
                        profile.height = profile.height or 'Not recorded'
                    end
                    continueProfileFetch()
                end)
            end

            fetchAppearanceAndContinue()
        end)
    else
        cb(profile)
    end
end)

-- Create report (returns success + reportId)
QBCore.Functions.CreateCallback('pf_mdt:createReport', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'no_db' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ success = false, error = 'no_player' })
        return
    end

    local officer = ''
    if Player.PlayerData and Player.PlayerData.charinfo then
        local ci = Player.PlayerData.charinfo
        officer = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    end
    if officer == '' then officer = 'Officer' end

    local repId = (data and data.reportId and data.reportId ~= '') and data.reportId or ("RPT-%05d"):format(math.random(1,99999))
    local typeVal = (data and data.type) or 'Incident Report'
    local category = (data and (data.category or data.type)) or 'General'
    local title = (data and data.title) or 'Report'
    local narrative = (data and (data.narrative or data.description)) or (data and data.content) or ''
    local content = (data and data.content) or narrative
    local location = (data and data.location) or ''
    -- a new report always waits for approval (pf_mdt:approveReport); the client could set 'approved'
    local status = 'pending'
    local approvalStatus = 'pending'
    local vehiclePlate = data and data.vehiclePlate or nil

    local ts = data and (data.timestamp or data.date) or nil
    local timestamp = nil
    if ts and ts ~= '' then
        -- Accept YYYY-MM-DD or HTML datetime-local
        if ts:find('T') then
            timestamp = ts:gsub('T', ' '):gsub('Z', '')
        else
            timestamp = ts .. ' 00:00:00'
        end
    else
        timestamp = os.date('%Y-%m-%d %H:%M:%S')
    end

    -- Normalize linked citizens
    local linkedCitizens = {}
    if data and type(data.linkedCitizens) == 'table' then
        for _, v in ipairs(data.linkedCitizens) do
            if type(v) == 'table' then
                local name = v.name or v.fullname or ''
                local cid = v.citizenid or v.id or v.citizenId or ''
                if name ~= '' or cid ~= '' then 
                    table.insert(linkedCitizens, { name = tostring(name), citizenid = tostring(cid) })
                end
            elseif type(v) == 'string' then
                if v ~= '' then table.insert(linkedCitizens, { name = tostring(v), citizenid = '' }) end
            end
        end
    elseif data and type(data.involvedParties) == 'table' then
        -- Backwards compatibility (UI used to send names here)
        for _, name in ipairs(data.involvedParties) do
            if type(name) == 'string' and name ~= '' then
                table.insert(linkedCitizens, { name = tostring(name), citizenid = '' })
            end
        end
    end

    -- Normalize linked officers
    local linkedOfficers = {}
    if data and type(data.linkedOfficers) == 'table' then
        for _, v in ipairs(data.linkedOfficers) do
            if type(v) == 'table' and v.name then
                table.insert(linkedOfficers, { name = tostring(v.name) })
            end
        end
    end

    local involved = json.encode({
        vehiclePlate = vehiclePlate,
        vehicleName = data and data.vehicleName or nil,
        citizens = linkedCitizens,
        officers = linkedOfficers,
        weapons = data and data.linkedWeapons or {},
        incidents = data and data.linkedIncidents or {}
    })
    local evidence = json.encode(data and data.linkedEvidence or {})

    exports.oxmysql:insert(
        'INSERT INTO pf_mdt_reports (reportId, type, category, title, officer, narrative, content, location, vehiclePlate, involvedParties, linkedEvidence, approvalStatus, status, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { repId, typeVal, category, title, officer, narrative, content, location, vehiclePlate, involved, evidence, approvalStatus, status, timestamp },
        function(insertId)
            if insertId then
                cb({
                    success = true,
                    reportId = repId,
                    report = { id = repId, type = typeVal, title = title, officer = officer, createdAt = os.date('%Y-%m-%d %H:%M:%S') }
                })
            else
                cb({ success = false, error = 'insert_failed' })
            end
        end
    )
end)

-- Update Profile Picture
QBCore.Functions.CreateCallback('pf_mdt:updateProfilePicture', function(source, cb, data)
    local citizenId = data and data.citizenId or ''
    local url = data and data.url or ''
    
    if citizenId == '' or url == '' then
        cb({ success = false, message = 'Invalid data' })
        return
    end
    
    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute('INSERT INTO pf_mdt_citizen_profiles (citizenId, profilePicture) VALUES (?, ?) ON DUPLICATE KEY UPDATE profilePicture = ?', 
            { citizenId, url, url }, function(result)
            cb({ success = true })
            TriggerClientEvent('QBCore:Notify', source, 'Profile picture updated', 'success')
        end)
    else
        cb({ success = false, message = 'Database not available' })
    end
end)

QBCore.Functions.CreateCallback('pf_mdt:updateVehiclePhoto', function(source, cb, data)
    local plate = data and data.plate or ''
    local url = data and data.url or ''
    
    if plate == '' or url == '' then
        cb({ success = false, message = 'Invalid data' })
        return
    end
    
    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute('INSERT INTO pf_mdt_vehicle_profiles (plate, vehiclePhoto) VALUES (?, ?) ON DUPLICATE KEY UPDATE vehiclePhoto = ?', 
            { plate, url, url }, function(result)
            cb({ success = true })
            TriggerClientEvent('QBCore:Notify', source, 'Vehicle photo updated', 'success')
        end)
    else
        cb({ success = false, message = 'Database not available' })
    end
end)

QBCore.Functions.CreateCallback('pf_mdt:getVehicleProfile', function(source, cb, data)
    local plate = data and (data.vehicleId or data.plate) or ''
    
    if not hasOxMySQL() or not exports.oxmysql or plate == '' then
        cb(nil)
        return
    end

    -- Prepare profile early so any timeout still returns a valid table
    local profile = {
        plate = plate,
        citizenid = nil,
        ownerName = 'Unknown',
        model = 'Vehicle',
        modelLabel = nil,
        brand = nil,
        flags = {},
        notes = {},
        strikes = {},
        reports = {},
        activity = {}
    }

    -- Always respond fast: global safeguard will return partial data if anything stalls
    local responded = false
    local function respondOnce()
        if responded then return end
        responded = true
        cb(profile)
    end

    SetTimeout(1500, function()
        if responded then return end
        dprint('^3[MDT WARN]^7 Vehicle profile global timeout hit; returning partial data early')
        respondOnce()
    end)

    exports.oxmysql:execute([[ 
        SELECT v.plate, v.vehicle, v.citizenid, p.charinfo
        FROM player_vehicles v
        LEFT JOIN players p ON p.citizenid = v.citizenid
        WHERE v.plate = ?
        LIMIT 1
    ]], { plate }, function(rows)
        -- If global timeout already fired, do not proceed further
        if responded then return end

        local r = rows and rows[1]
        if r then
            profile.plate = r.plate or plate
            profile.citizenid = r.citizenid

            if r.charinfo then
                local ok, info = pcall(json.decode, r.charinfo)
                if ok and info and info.firstname and info.lastname then
                    profile.ownerName = info.firstname .. ' ' .. info.lastname
                end
            end

            local rawVehicle = r.vehicle
            local vdata = nil

            if type(rawVehicle) == 'string' then
                local trimmed = rawVehicle:gsub('^%s+', '')
                if trimmed:sub(1,1) == '{' or trimmed:sub(1,1) == '[' then
                    local ok, decoded = pcall(json.decode, rawVehicle)
                    if ok and type(decoded) == 'table' then
                        vdata = decoded
                    end
                end
            elseif type(rawVehicle) == 'table' then
                vdata = rawVehicle
            end

            local model = nil
            if vdata then
                model = vdata.model or vdata.name or vdata.vehicle or vdata.hash
            end
            if not model then
                model = rawVehicle
            end

            profile.model = model

            if type(model) == 'string' and QBCore.Shared and QBCore.Shared.Vehicles then
                local v = QBCore.Shared.Vehicles[model]
                if v and v.name then
                    profile.modelLabel = v.name
                    profile.brand = v.brand
                end
            end
        end

        if (not r) and IsManualEntriesEnabled() then
            local p = promise.new()
            exports.oxmysql:execute(
                'SELECT plate, ownerCitizenId, ownerName, model, modelLabel, brand, primaryColorId, secondaryColorId, vehiclePhoto FROM pf_mdt_manual_vehicles WHERE plate = ? LIMIT 1',
                { plate },
                function(mrows)
                    local mr = mrows and mrows[1]
                    if mr then
                        profile.plate = tostring(mr.plate or plate)
                        profile.citizenid = tostring(mr.ownerCitizenId or '')
                        profile.ownerName = tostring(mr.ownerName or mr.ownerCitizenId or 'Unknown')
                        profile.model = tostring(mr.model or mr.modelLabel or 'Vehicle')
                        profile.modelLabel = tostring(mr.modelLabel or mr.model or '')
                        profile.brand = tostring(mr.brand or '')
                        profile.manualEntry = true
                        profile.vehiclePhoto = tostring(mr.vehiclePhoto or '')
                        profile.primaryColorId = tonumber(mr.primaryColorId)
                        profile.secondaryColorId = tonumber(mr.secondaryColorId)
                    end
                    p:resolve(true)
                end
            )
            Citizen.Await(p)
        end

        dprint('[MDT] Vehicle resolve:', plate, 'model:', tostring(profile.model), 'label:', tostring(profile.modelLabel))

        -- Fetch vehicle photo from profiles table
        exports.oxmysql:execute('SELECT vehiclePhoto FROM pf_mdt_vehicle_profiles WHERE plate = ? LIMIT 1', { plate }, function(photoRows)
            if photoRows and photoRows[1] and photoRows[1].vehiclePhoto then
                profile.vehiclePhoto = photoRows[1].vehiclePhoto
            end
        end)

        -- Fetch flags, notes, strikes, and reports for this plate
        local pendingQueries = 4
        local function checkAllQueriesDone()
            pendingQueries = pendingQueries - 1
            if pendingQueries == 0 then
                dprint('[MDT] All queries complete, sending profile to client')
                respondOnce()
            end
        end

        -- Per-query timeout so UI is responsive even if a single SELECT errors out
        local function runQuery(label, sql, params, handler)
            local finished = false
            exports.oxmysql:execute(sql, params, function(rows)
                if finished or responded then return end
                finished = true
                handler(rows)
                checkAllQueriesDone()
            end)
            SetTimeout(1000, function()
                if finished or responded then return end
                finished = true
                dprint(('[MDT WARN] Vehicle query "%s" timed out; returning partial results'):format(label))
                handler(nil)
                checkAllQueriesDone()
            end)
        end

        runQuery('flags', 'SELECT flag FROM pf_mdt_vehicle_flags WHERE plate = ? ORDER BY createdAt DESC LIMIT 1', { plate }, function(frows)
            profile.flags = {}
            if frows then
                for _, fr in ipairs(frows) do 
                    profile.flags[#profile.flags+1] = fr.flag 
                end
            end
        end)

        runQuery('notes', 'SELECT text, author, createdAt FROM pf_mdt_vehicle_notes WHERE plate = ? ORDER BY createdAt DESC', { plate }, function(nrows)
            profile.notes = nrows or {}
        end)

        -- Avoid selecting columns that may not exist on older schemas; officer name is duplicated in createdByName when present
        runQuery('strikes', 'SELECT id, title, offenseType, points, description, officer, location, status, createdAt, expiresAt, createdByName FROM pf_mdt_vehicle_strikes WHERE plate = ? ORDER BY createdAt DESC', { plate }, function(srows)
            profile.strikes = srows or {}
        end)
        
        -- Query reports by vehiclePlate column (primary) and fallback to content search for legacy reports
        local likePlate = '%' .. plate .. '%'
        runQuery('reports', [[SELECT reportId, type, title, officer, narrative, content, location, approvalStatus, status, timestamp, createdAt, vehiclePlate
                                FROM pf_mdt_reports
                                WHERE vehiclePlate = ? OR content LIKE ? OR title LIKE ? OR narrative LIKE ?
                                ORDER BY IFNULL(timestamp, createdAt) DESC, createdAt DESC
                                LIMIT 50]], { plate, likePlate, likePlate, likePlate }, function(rrows)
            profile.reports = {}
            for _, r in ipairs(rrows or {}) do
                profile.reports[#profile.reports+1] = {
                    reportId = r.reportId,
                    type = r.type,
                    title = r.title,
                    officer = r.officer,
                    narrative = r.narrative,
                    content = r.content,
                    location = r.location,
                    approvalStatus = r.approvalStatus or 'pending',
                    status = r.status,
                    timestamp = r.timestamp,
                    createdAt = r.createdAt
                }
            end
        end)

        profile.activity = {}
    end)
end)

local function getOfficerName(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P or not P.PlayerData or not P.PlayerData.charinfo then return 'Officer' end
    return (P.PlayerData.charinfo.firstname or 'Officer') .. ' ' .. (P.PlayerData.charinfo.lastname or '')
end

RegisterNetEvent('pf_mdt:addCitizenNote', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local citizenId = data and data.citizenId or ''
    local text = data and data.text or ''
    if citizenId == '' or text == '' then return end
    exports.oxmysql:insert('INSERT INTO pf_mdt_citizen_notes (citizenId, text, author) VALUES (?, ?, ?)', { citizenId, text, getOfficerName(src) })
end)

RegisterNetEvent('pf_mdt:addCitizenFlag', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local citizenId = data and data.citizenId or ''
    local flag = data and data.flag or ''
    if citizenId == '' or flag == '' then return end
    exports.oxmysql:insert('INSERT INTO pf_mdt_citizen_flags (citizenId, flag) VALUES (?, ?)', { citizenId, flag })
end)

RegisterNetEvent('pf_mdt:removeCitizenFlag', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local citizenId = data and data.citizenId or ''
    local flag = data and data.flag or ''
    if citizenId == '' or flag == '' then return end
    exports.oxmysql:execute('DELETE FROM pf_mdt_citizen_flags WHERE citizenId = ? AND flag = ?', { citizenId, flag })
end)

RegisterNetEvent('pf_mdt:addVehicleNote', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local plate = data and data.plate or ''
    local text = data and data.text or ''
    if plate == '' or text == '' then return end
    exports.oxmysql:insert('INSERT INTO pf_mdt_vehicle_notes (plate, text, author) VALUES (?, ?, ?)', { plate, text, getOfficerName(src) })
end)

RegisterNetEvent('pf_mdt:addVehicleFlag', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local plate = data and data.plate or ''
    local flag = data and data.flag or ''
    if plate == '' or flag == '' then return end
    plate = tostring(plate):gsub('^%s*(.-)%s*$', '%1')
    flag = tostring(flag):gsub('^%s*(.-)%s*$', '%1')
    -- Single-select model: clear existing flags for this plate, then insert.
    exports.oxmysql:execute('DELETE FROM pf_mdt_vehicle_flags WHERE plate = ?', { plate }, function()
        exports.oxmysql:insert('INSERT INTO pf_mdt_vehicle_flags (plate, flag) VALUES (?, ?)', { plate, flag })
    end)
end)

RegisterNetEvent('pf_mdt:removeVehicleFlag', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local plate = data and data.plate or ''
    if plate == '' then return end
    plate = tostring(plate):gsub('^%s*(.-)%s*$', '%1')
    exports.oxmysql:execute('DELETE FROM pf_mdt_vehicle_flags WHERE plate = ?', { plate })
end)

RegisterNetEvent('pf_mdt:addVehicleStrike', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    if type(data) ~= 'table' then return end
    local T = PFMdtAccess.Text
    local plate = T(data.plate, 16)
    local title = T(data.title or 'Strike', 128)
    local offenseType = T(data.offenseType or 'other', 32)
    local points = math.floor(tonumber(data.points) or 4)
    local description = T(data.description, 2000)
    local officer = getOfficerName(src)
    local location = T(data.location or 'Unknown', 128)
    local expiryDays = tonumber(data.expiryDays) or 60

    if plate == '' or title == '' then return end
    if points < 0 or points > 100 or expiryDays <= 0 or expiryDays > 3650 then return end
    
    -- Calculate expiry date
    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + (expiryDays * 86400))
    
    exports.oxmysql:insert(
        'INSERT INTO pf_mdt_vehicle_strikes (plate, title, offenseType, points, description, officer, location, status, expiresAt, createdByName) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { plate, title, offenseType, points, description, officer, location, 'active', expiresAt, officer },
        function(insertId)
            -- Broadcast to all connected MDT clients
            local Players = QBCore.Functions.GetQBPlayers()
            for _, Player in pairs(Players) do
                if IsAllowedJob(Player.PlayerData.job.name) then
                    TriggerClientEvent('pf_mdt:client:VehicleStrikeAdded', Player.PlayerData.source, plate)
                end
            end
        end
    )
end)

RegisterNetEvent('pf_mdt:clearVehicleStrikes', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local plate = data and data.plate or ''
    if plate == '' then return end

    exports.oxmysql:execute('DELETE FROM pf_mdt_vehicle_strikes WHERE plate = ?', { plate })
end)

-- License suspension/removal. Only the MDT's own license kinds: the type was any metadata key, so
-- "unsuspend" could hand out any license (or one never suspended) to anyone, the officer included.
local MDT_LICENSE_TYPES = { driver = true, weapon = true, business = true }

RegisterNetEvent('pf_mdt:suspendLicense', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local citizenId = data and data.citizenId or ''
    local licenseType = data and data.licenseType or ''
    local durationDays = tonumber(data and data.durationDays or 7)
    
    dprint('[MDT LICENSE] Suspend request - citizenId:', citizenId, 'licenseType:', licenseType, 'durationDays:', durationDays, 'type:', type(durationDays))
    
    if citizenId == '' or not MDT_LICENSE_TYPES[licenseType] or not durationDays or durationDays <= 0 or durationDays > 365 then 
        dprint('[MDT LICENSE] Validation failed - citizenId empty:', citizenId == '', 'licenseType empty:', licenseType == '', 'durationDays invalid:', not durationDays or durationDays <= 0)
        return 
    end
    
    -- Get player to check if online
    local targetPlayer = nil
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        if Player.PlayerData.citizenid == citizenId then
            targetPlayer = Player
            break
        end
    end
    
    if isESXFramework() then
        ensureEsxCompatTablesOnce()
        local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + (durationDays * 86400))
        local types = esxLicenseTypesFor(licenseType)
        if #types == 0 then return end

        if not esxHasUserLicensesCached() then
            exports.oxmysql:execute(
                'INSERT INTO pf_mdt_esx_license_suspensions (identifier, license_type, expires_at, stored_types) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at), stored_types = VALUES(stored_types)',
                { citizenId, licenseType, expiresAt, json.encode({}) }
            )
            if targetPlayer then
                TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                    ('Your %s has been suspended'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License')),
                    'error')
            end
        else

        -- Fetch currently owned types so we can restore later
        local owned = {}
        do
            local q = ('SELECT type FROM user_licenses WHERE owner = ? AND type IN (%s)'):format(string.rep('?,', #types):sub(1, -2))
            local params = { citizenId }
            for _, t in ipairs(types) do params[#params + 1] = t end
            local p = promise.new()
            exports.oxmysql:execute(q, params, function(rows)
                for _, r in ipairs(rows or {}) do
                    if r.type then owned[#owned + 1] = tostring(r.type) end
                end
                p:resolve(true)
            end)
            Citizen.Await(p)
        end

        -- Remove license rows (suspension)
        do
            local q = ('DELETE FROM user_licenses WHERE owner = ? AND type IN (%s)'):format(string.rep('?,', #types):sub(1, -2))
            local params = { citizenId }
            for _, t in ipairs(types) do params[#params + 1] = t end
            exports.oxmysql:execute(q, params)
        end

        exports.oxmysql:execute(
            'INSERT INTO pf_mdt_esx_license_suspensions (identifier, license_type, expires_at, stored_types) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at), stored_types = VALUES(stored_types)',
            { citizenId, licenseType, expiresAt, json.encode(owned) }
        )

        if targetPlayer then
            local durationMsg = ''
            if durationDays < 1 then
                local minutes = math.floor(durationDays * 1440)
                durationMsg = ('%d minutes'):format(minutes)
            elseif durationDays == 1 then
                durationMsg = '1 day'
            else
                durationMsg = ('%d days'):format(durationDays)
            end
            TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                ('Your %s has been suspended for %s'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License'), durationMsg),
                'error')
        end
        end
    else
        -- QBCore metadata-based license storage
        exports.oxmysql:execute('SELECT metadata FROM players WHERE citizenid = ? LIMIT 1', { citizenId }, function(rows)
            if rows and rows[1] then
                local meta = type(rows[1].metadata) == 'string' and json.decode(rows[1].metadata) or rows[1].metadata or {}
                if not meta.licences then meta.licences = {} end

                -- Mark license as suspended with expiration
                if meta.licences[licenseType] == true then
                    meta.licences[licenseType] = false  -- Suspend the license
                    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + (durationDays * 86400))
                    meta.licenseSuspensions = meta.licenseSuspensions or {}
                    meta.licenseSuspensions[licenseType] = expiresAt

                    exports.oxmysql:execute('UPDATE players SET metadata = ? WHERE citizenid = ?',
                        { json.encode(meta), citizenId })

                    -- If player is online, update their metadata
                    if targetPlayer then
                        targetPlayer.PlayerData.metadata.licences = meta.licences
                        targetPlayer.PlayerData.metadata.licenseSuspensions = meta.licenseSuspensions
                        -- Format duration message appropriately
                        local durationMsg = ''
                        if durationDays < 1 then
                            local minutes = math.floor(durationDays * 1440)
                            durationMsg = ('%d minutes'):format(minutes)
                        elseif durationDays == 1 then
                            durationMsg = '1 day'
                        else
                            durationMsg = ('%d days'):format(durationDays)
                        end
                        TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                            ('Your %s has been suspended for %s'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License'), durationMsg),
                            'error')
                    end
                end
            end
        end)
    end
    
    -- Format success message
    local durationMsg = ''
    if durationDays < 1 then
        local minutes = math.floor(durationDays * 1440)
        durationMsg = ('%d minutes'):format(minutes)
    elseif durationDays == 1 then
        durationMsg = '1 day'
    else
        durationMsg = ('%d days'):format(durationDays)
    end
    TriggerClientEvent('QBCore:Notify', src, ('License suspended for %s'):format(durationMsg), 'success')
end)

RegisterNetEvent('pf_mdt:removeLicense', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local citizenId = data and data.citizenId or ''
    local licenseType = data and data.licenseType or ''
    
    if type(citizenId) ~= 'string' or citizenId == '' or not MDT_LICENSE_TYPES[licenseType] then return end
    
    -- Get player to check if online
    local targetPlayer = nil
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        if Player.PlayerData.citizenid == citizenId then
            targetPlayer = Player
            break
        end
    end
    
    if isESXFramework() then
        ensureEsxCompatTablesOnce()
        local types = esxLicenseTypesFor(licenseType)
        if #types == 0 then return end

        if not esxHasUserLicensesCached() then
            exports.oxmysql:execute('DELETE FROM pf_mdt_esx_license_suspensions WHERE identifier = ? AND license_type = ?', { citizenId, licenseType })
            if targetPlayer then
                TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                    ('Your %s has been removed'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License')),
                    'error')
            end
        else
        do
            local q = ('DELETE FROM user_licenses WHERE owner = ? AND type IN (%s)'):format(string.rep('?,', #types):sub(1, -2))
            local params = { citizenId }
            for _, t in ipairs(types) do params[#params + 1] = t end
            exports.oxmysql:execute(q, params)
        end
        exports.oxmysql:execute('DELETE FROM pf_mdt_esx_license_suspensions WHERE identifier = ? AND license_type = ?', { citizenId, licenseType })

        if targetPlayer then
            TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                ('Your %s has been removed'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License')),
                'error')
        end
        end
    else
        -- QBCore metadata-based license storage
        exports.oxmysql:execute('SELECT metadata FROM players WHERE citizenid = ? LIMIT 1', { citizenId }, function(rows)
            if rows and rows[1] then
                local meta = type(rows[1].metadata) == 'string' and json.decode(rows[1].metadata) or rows[1].metadata or {}
                if not meta.licences then meta.licences = {} end

                -- Remove the license
                if meta.licences[licenseType] ~= nil then
                    meta.licences[licenseType] = false
                    -- Also clear any suspension data
                    if meta.licenseSuspensions then
                        meta.licenseSuspensions[licenseType] = nil
                    end

                    exports.oxmysql:execute('UPDATE players SET metadata = ? WHERE citizenid = ?',
                        { json.encode(meta), citizenId })

                    -- If player is online, update their metadata
                    if targetPlayer then
                        targetPlayer.PlayerData.metadata.licences = meta.licences
                        if meta.licenseSuspensions then
                            targetPlayer.PlayerData.metadata.licenseSuspensions = meta.licenseSuspensions
                        end
                        TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                            ('Your %s has been removed'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License')),
                            'error')
                    end
                end
            end
        end)
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'License removed', 'success')
end)

-- Unsuspend (early restoration)
RegisterNetEvent('pf_mdt:unsuspendLicense', function(data)
    if not (hasOxMySQL() and exports.oxmysql) then return end
    local src = source
    local citizenId = data and data.citizenId or ''
    local licenseType = data and data.licenseType or ''
    
    if type(citizenId) ~= 'string' or citizenId == '' or not MDT_LICENSE_TYPES[licenseType] then return end
    
    -- Get player to check if online
    local targetPlayer = nil
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        if Player.PlayerData.citizenid == citizenId then
            targetPlayer = Player
            break
        end
    end
    
    if isESXFramework() then
        ensureEsxCompatTablesOnce()

        if not esxHasUserLicensesCached() then
            exports.oxmysql:execute('DELETE FROM pf_mdt_esx_license_suspensions WHERE identifier = ? AND license_type = ?', { citizenId, licenseType })
            if targetPlayer then
                TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                    ('Your %s suspension has been lifted'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License')),
                    'success')
            end
        else
        local p = promise.new()
        exports.oxmysql:execute(
            'SELECT stored_types FROM pf_mdt_esx_license_suspensions WHERE identifier = ? AND license_type = ? LIMIT 1',
            { citizenId, licenseType },
            function(rows)
                local stored = {}
                if rows and rows[1] and type(rows[1].stored_types) == 'string' and rows[1].stored_types ~= '' then
                    local ok, parsed = pcall(json.decode, rows[1].stored_types)
                    if ok and type(parsed) == 'table' then stored = parsed end
                end
                for _, lt in ipairs(stored or {}) do
                    if lt and lt ~= '' then
                        exports.oxmysql:execute('INSERT IGNORE INTO user_licenses (type, owner) VALUES (?, ?)', { tostring(lt), citizenId })
                    end
                end
                exports.oxmysql:execute('DELETE FROM pf_mdt_esx_license_suspensions WHERE identifier = ? AND license_type = ?', { citizenId, licenseType }, function()
                    p:resolve(true)
                end)
            end
        )
        Citizen.Await(p)

        if targetPlayer then
            TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                ('Your %s suspension has been lifted'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License')),
                'success')
        end
        end
    else
        -- QBCore metadata-based license storage
        exports.oxmysql:execute('SELECT metadata FROM players WHERE citizenid = ? LIMIT 1', { citizenId }, function(rows)
            if rows and rows[1] then
                local meta = type(rows[1].metadata) == 'string' and json.decode(rows[1].metadata) or rows[1].metadata or {}
                if not meta.licences then meta.licences = {} end

                -- Only a license that is suspended now comes back
                if not (type(meta.licenseSuspensions) == 'table' and meta.licenseSuspensions[licenseType]) then return end

                -- Restore the license and clear suspension
                meta.licences[licenseType] = true
                if meta.licenseSuspensions then
                    meta.licenseSuspensions[licenseType] = nil
                end

                exports.oxmysql:execute('UPDATE players SET metadata = ? WHERE citizenid = ?',
                    { json.encode(meta), citizenId })

                -- If player is online, update their metadata
                if targetPlayer then
                    targetPlayer.PlayerData.metadata.licences = meta.licences
                    if meta.licenseSuspensions then
                        targetPlayer.PlayerData.metadata.licenseSuspensions = meta.licenseSuspensions
                    end
                    TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source,
                        ('Your %s suspension has been lifted'):format(licenseType:gsub('driver','Driver License'):gsub('weapon','Weapon License'):gsub('business','Business License')),
                        'success')
                end
            end
        end)
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'License suspension lifted', 'success')
end)

RegisterNetEvent('pf_mdt:getPlayerLocation', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Request location from client since GetStreetNameAtCoord is client-side only
    TriggerClientEvent('pf_mdt:client:RequestPlayerLocation', src)
end)

-- Profile save
RegisterNetEvent("pf_mdt_dispatch:server:SaveProfile", function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if type(data) ~= 'table' or not PFMdtAccess.AllowRate(src, 'saveProfile', 2000) then return end
    local function opt(v, n)
        local s = PFMdtAccess.Text(v, n)
        return s ~= '' and s or nil
    end
    local callsign = opt(data.callsign, 10)
    local status = opt(data.status, 32)
    local avatarUrl = opt(data.avatarUrl, 512)

    if callsign then Player.Functions.SetMetaData('callsign', callsign) end
    if status then Player.Functions.SetMetaData('mdt_status', status) end
    if avatarUrl then Player.Functions.SetMetaData('mdt_avatar', avatarUrl) end
    -- Persist to MDT database (pf_mdt_officer_profiles)
    if hasOxMySQL() and exports.oxmysql then
        local citizenId = Player.PlayerData.citizenid
        exports.oxmysql:execute([[
            INSERT INTO pf_mdt_officer_profiles (citizenId, callsign, status, avatarUrl)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
              callsign = VALUES(callsign),
              status = VALUES(status),
              avatarUrl = VALUES(avatarUrl),
              updatedAt = CURRENT_TIMESTAMP
        ]], { citizenId, callsign, status, avatarUrl })
    end
    TriggerClientEvent('QBCore:Notify', src, 'Profile saved', 'success')
end)

-- User profile fetch for persistent callsign/status/avatar
QBCore.Functions.CreateCallback('pf_mdt_dispatch:server:GetUserProfile', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({}) return end
    local citizenId = Player.PlayerData.citizenid

    local result = {
        callsign = (Player.PlayerData.metadata and Player.PlayerData.metadata.callsign) or nil,
        status = (Player.PlayerData.metadata and Player.PlayerData.metadata.mdt_status) or nil,
        avatarUrl = (Player.PlayerData.metadata and Player.PlayerData.metadata.mdt_avatar) or nil
    }

    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute('SELECT callsign, status, avatarUrl FROM pf_mdt_officer_profiles WHERE citizenId = ? LIMIT 1', { citizenId }, function(rows)
            if rows and rows[1] then
                result.callsign = rows[1].callsign or result.callsign
                result.status = rows[1].status or result.status
                result.avatarUrl = rows[1].avatarUrl or result.avatarUrl
            end
            cb(result)
        end)
    else
        cb(result)
    end
end)

-- Dashboard data callback - includes active warrants
QBCore.Functions.CreateCallback('pf_mdt_dispatch:server:GetDashboard', function(source, cb)
    local data = {
        bulletins = {},
        reports = Config.Dashboard and Config.Dashboard.reports or {},
        warrants = {}
    }

    if not (hasOxMySQL() and exports.oxmysql) then
        data.bulletins = Config.Dashboard and Config.Dashboard.bulletins or {}
        cb(data)
        return
    end

    -- Load bulletins
    exports.oxmysql:execute(
        'SELECT title, body, UNIX_TIMESTAMP(createdAt) AS createdAt FROM pf_mdt_bulletins ORDER BY createdAt DESC LIMIT 10',
        {},
        function(bRows)
            for _, b in ipairs(bRows or {}) do
                table.insert(data.bulletins, {
                    title = b.title,
                    body = b.body,
                    createdAt = tonumber(b.createdAt) or nil
                })
            end

            -- Load active warrants
            exports.oxmysql:execute('SELECT warrantId, suspectName, status, UNIX_TIMESTAMP(createdAt) AS createdAt FROM pf_mdt_warrants WHERE status = ? ORDER BY createdAt DESC LIMIT 10', { 'active' }, function(rows)
                for _, r in ipairs(rows or {}) do
                    table.insert(data.warrants, {
                        id = r.warrantId,
                        name = r.suspectName,
                        status = r.status,
                        createdAt = tonumber(r.createdAt) or nil
                    })
                end
                cb(data)
            end)
        end
    )
end)

-- Create bulletin (grade 4+ only)
QBCore.Functions.CreateCallback('pf_mdt_dispatch:server:CreateBulletin', function(source, cb, payload)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database not available' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then
        cb({ success = false, error = 'Player not found' })
        return
    end

    local gradeLevel = 0
    if Player.PlayerData.job.grade and Player.PlayerData.job.grade.level then
        gradeLevel = tonumber(Player.PlayerData.job.grade.level) or 0
    end

    if gradeLevel < 4 then
        cb({ success = false, error = 'Insufficient rank' })
        return
    end

    local title = payload and tostring(payload.title or '') or ''
    local body = payload and tostring(payload.body or '') or ''
    title = title:gsub('^%s+', ''):gsub('%s+$', '')
    body = body:gsub('^%s+', ''):gsub('%s+$', '')

    if title == '' or body == '' then
        cb({ success = false, error = 'Missing title or description' })
        return
    end

    if #title > 255 then title = title:sub(1, 255) end
    if #body > 4000 then body = body:sub(1, 4000) end

    local charinfo = Player.PlayerData.charinfo or {}
    local firstName = charinfo.firstname or ''
    local lastName = charinfo.lastname or ''
    local createdByName = (firstName .. ' ' .. lastName):gsub('^%s+', ''):gsub('%s+$', '')
    if createdByName == '' then createdByName = Player.PlayerData.name or 'Officer' end

    local citizenId = Player.PlayerData.citizenid
    local createdAtUnix = os.time()

    exports.oxmysql:insert(
        'INSERT INTO pf_mdt_bulletins (title, body, createdByCitizenId, createdByName) VALUES (?, ?, ?, ?)',
        { title, body, citizenId, createdByName },
        function(insertId)
            local bulletin = {
                id = insertId,
                title = title,
                body = body,
                createdAt = createdAtUnix,
                createdByName = createdByName
            }

            -- Push to officers so open dashboards update immediately (not to every client)
            for _, P in pairs(QBCore.Functions.GetQBPlayers()) do
                if P.PlayerData and P.PlayerData.job and IsAllowedJob(P.PlayerData.job.name) then
                    TriggerClientEvent('pf-policemdt:client:bulletinCreated', P.PlayerData.source, bulletin)
                end
            end

            cb({ success = true, bulletin = bulletin })
        end
    )
end)

-- Get warrant details by ID
QBCore.Functions.CreateCallback('pf_mdt_dispatch:server:GetWarrantDetails', function(source, cb, warrantId)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb(nil)
        return
    end

    if not warrantId then
        cb(nil)
        return
    end

    exports.oxmysql:fetch(
        'SELECT id, warrantId, suspectCitizenId, suspectName, charges, officers, witnesses, issuedBy, title, narrative, status, createdAt, expiresAt FROM pf_mdt_warrants WHERE warrantId = ? OR id = ? LIMIT 1',
        { tostring(warrantId), tonumber(warrantId) or 0 },
        function(results)
            if results and results[1] then
                local row = results[1]
                local charges = {}
                if row.charges and row.charges ~= '' then
                    local ok, parsed = pcall(json.decode, row.charges)
                    charges = ok and parsed or {}
                end

                local officers = {}
                if row.officers and row.officers ~= '' then
                    local ok, parsed = pcall(json.decode, row.officers)
                    officers = ok and parsed or {}
                end

                local witnesses = {}
                if row.witnesses and row.witnesses ~= '' then
                    local ok, parsed = pcall(json.decode, row.witnesses)
                    witnesses = ok and parsed or {}
                end

                local warrant = {
                    id = row.warrantId or tostring(row.id),
                    suspectCitizenId = row.suspectCitizenId,
                    suspectName = row.suspectName,
                    charges = charges,
                    officers = officers,
                    witnesses = witnesses,
                    issuedBy = row.issuedBy,
                    title = row.title,
                    narrative = row.narrative,
                    status = row.status,
                    createdAt = row.createdAt,
                    expiresAt = row.expiresAt
                }
                cb(warrant)
            else
                cb(nil)
            end
        end
    )
end)

-- ============================================================================
-- CHARGES System
-- ============================================================================

local _chargesSchemaCache = nil
local _chargesSchemaCacheAt = 0
local function GetChargesSchema(cb)
    if _chargesSchemaCache and (GetGameTimer() - (_chargesSchemaCacheAt or 0) < 60000) then
        cb(_chargesSchemaCache)
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        local fallback = {
            hasLegacySnake = false,
            hasCamel = true,
            camelGenerated = false
        }
        _chargesSchemaCache = fallback
        _chargesSchemaCacheAt = GetGameTimer()
        cb(fallback)
        return
    end

    exports.oxmysql:execute([[ 
        SELECT COLUMN_NAME, EXTRA
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'pf_mdt_charges'
          AND COLUMN_NAME IN ('fineAmount','bailAmount','prisonTime','fine_amount','bail_amount','jail_time')
    ]], {}, function(rows)
        local present = {}
        local generated = {}
        for _, r in ipairs(rows or {}) do
            local col = r.COLUMN_NAME
            present[col] = true
            local extra = tostring(r.EXTRA or ''):lower()
            if extra:find('generated') then
                generated[col] = true
            end
        end

        local schema = {
            hasLegacySnake = (present.fine_amount or present.bail_amount or present.jail_time) == true,
            hasCamel = (present.fineAmount or present.bailAmount or present.prisonTime) == true,
            camelGenerated = (generated.fineAmount or generated.bailAmount or generated.prisonTime) == true
        }
        _chargesSchemaCache = schema
        _chargesSchemaCacheAt = GetGameTimer()
        cb(schema)
    end)
end

local function FetchChargesDiagnostics(cb)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end

    exports.oxmysql:execute('SELECT DATABASE() AS db, @@hostname AS host, @@port AS port, @@sql_mode AS sql_mode', {}, function(connRows)
        local conn = (connRows and connRows[1]) or {}

        exports.oxmysql:execute([[ 
            SELECT TABLE_TYPE, ENGINE, TABLE_COLLATION
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'pf_mdt_charges'
            LIMIT 1
        ]], {}, function(tableRows)
            local tbl = (tableRows and tableRows[1]) or {}

            exports.oxmysql:execute([[ 
                SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'pf_mdt_charges'
                  AND COLUMN_NAME IN ('fineAmount','bailAmount','prisonTime')
                ORDER BY COLUMN_NAME ASC
            ]], {}, function(colRows)
                exports.oxmysql:execute([[ 
                    SELECT TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION, ACTION_STATEMENT
                    FROM information_schema.TRIGGERS
                    WHERE TRIGGER_SCHEMA = DATABASE()
                      AND EVENT_OBJECT_TABLE = 'pf_mdt_charges'
                    ORDER BY TRIGGER_NAME ASC
                ]], {}, function(trigRows)
                    exports.oxmysql:execute('SHOW CREATE TABLE pf_mdt_charges', {}, function(createRows)
                        local createSql = nil
                        if createRows and createRows[1] then
                            createSql = createRows[1]['Create Table'] or createRows[1]['Create View'] or createRows[1]['Create Table '] or nil
                        end

                        cb({
                            connection = conn,
                            table = tbl,
                            columns = colRows or {},
                            triggers = trigRows or {},
                            create = createSql
                        })
                    end)
                end)
            end)
        end)
    end)
end

QBCore.Functions.CreateCallback('pf_mdt:getCharges', function(source, cb, data)
    if hasOxMySQL() and exports.oxmysql then
        GetChargesSchema(function(schema)
            local selectSql
            if schema.hasCamel then
                selectSql = 'SELECT id, code, name, description, fineAmount, bailAmount, prisonTime, category FROM pf_mdt_charges ORDER BY category ASC, name ASC'
            elseif schema.hasLegacySnake then
                -- Only snake_case exists; alias to the expected camelCase fields.
                selectSql = 'SELECT id, code, name, description, fine_amount AS fineAmount, bail_amount AS bailAmount, jail_time AS prisonTime, category FROM pf_mdt_charges ORDER BY category ASC, name ASC'
            else
                selectSql = 'SELECT id, code, name, description, category FROM pf_mdt_charges ORDER BY category ASC, name ASC'
            end

            exports.oxmysql:execute(selectSql, {}, function(rows)
                cb({ success = true, charges = rows or {} })
            end)
        end)
    else
        cb({ success = false, charges = {} })
    end
end)

QBCore.Functions.CreateCallback('pf_mdt:getChargesByCategory', function(source, cb, data)
    local category = data and data.category or nil
    if hasOxMySQL() and exports.oxmysql then
        if category then
            GetChargesSchema(function(schema)
                local sql
                if schema.hasCamel then
                    sql = 'SELECT id, code, name, fineAmount, bailAmount, prisonTime, category FROM pf_mdt_charges WHERE category = ? ORDER BY name ASC'
                elseif schema.hasLegacySnake then
                    sql = 'SELECT id, code, name, fine_amount AS fineAmount, bail_amount AS bailAmount, jail_time AS prisonTime, category FROM pf_mdt_charges WHERE category = ? ORDER BY name ASC'
                else
                    sql = 'SELECT id, code, name, category FROM pf_mdt_charges WHERE category = ? ORDER BY name ASC'
                end
                exports.oxmysql:execute(sql, { category }, function(rows)
                    cb(rows or {})
                end)
            end)
        else
            exports.oxmysql:execute('SELECT DISTINCT category FROM pf_mdt_charges ORDER BY category ASC', {}, function(rows)
                local categories = {}
                for _, r in ipairs(rows or {}) do
                    table.insert(categories, r.category)
                end
                cb(categories)
            end)
        end
    else
        cb({})
    end
end)

-- All officers (online + offline) with allowed jobs
QBCore.Functions.CreateCallback('pf_mdt:getPoliceOfficers', function(source, cb)
    local function pushOnlineFallback()
        local list = {}
        local players = QBCore.Functions.GetQBPlayers()
        for _, P in pairs(players) do
            local jobName = P.PlayerData.job and P.PlayerData.job.name
            if jobName and Config.AllowedJobs[jobName] then
                local ci = P.PlayerData.charinfo or {}
                local meta = P.PlayerData.metadata or {}
                local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
                table.insert(list, {
                    citizenid = P.PlayerData.citizenid,
                    name = (name ~= '' and name) or 'Officer',
                    callsign = meta.callsign or meta.mdt_callsign or '',
                    job = jobName,
                    department = P.PlayerData.job.label or jobName,
                    grade = (P.PlayerData.job.grade and P.PlayerData.job.grade.level) or 0
                })
            end
        end
        cb(list)
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        pushOnlineFallback()
        return
    end

    exports.oxmysql:execute('SELECT citizenid, charinfo, job, metadata FROM players', {}, function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            local job = r.job
            if type(job) == 'string' then
                local ok, parsed = pcall(json.decode, job)
                if ok and parsed then job = parsed end
            end
            -- Extract job name - handle both string and table formats
            local jobName = nil
            if type(job) == 'table' then
                jobName = job.name or job.label
            elseif type(job) == 'string' then
                jobName = job
            end
            -- Check if job is in allowed list
            if jobName and Config.AllowedJobs[jobName] then
                local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
                local meta = type(r.metadata) == 'string' and json.decode(r.metadata) or r.metadata or {}
                local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
                local jobLabel = (type(job) == 'table' and job.label) or jobName
                local jobGrade = (type(job) == 'table' and job.grade and (job.grade.level or job.grade)) or 0
                table.insert(list, {
                    citizenid = r.citizenid,
                    name = (name ~= '' and name) or 'Officer',
                    callsign = meta.callsign or meta.mdt_callsign or '',
                    job = jobName,
                    department = jobLabel,
                    grade = jobGrade
                })
            end
        end
        dprint('[MDT] Fetched ' .. #list .. ' police officers from database')
        cb(list)
    end)
end)

-- All players in database for witness selection
QBCore.Functions.CreateCallback('pf_mdt:getAllPlayers', function(source, cb)
    if not (hasOxMySQL() and exports.oxmysql) then
        -- Fallback to online players
        local list = {}
        local players = QBCore.Functions.GetQBPlayers()
        for _, P in pairs(players) do
            local ci = P.PlayerData.charinfo or {}
            local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
            table.insert(list, {
                citizenid = P.PlayerData.citizenid,
                name = (name ~= '' and name) or 'Citizen',
                charinfo = ci
            })
        end
        cb(list)
        return
    end

    exports.oxmysql:execute('SELECT citizenid, charinfo FROM players ORDER BY charinfo DESC', {}, function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            local ci = {}
            if type(r.charinfo) == 'string' then
                local ok, decoded = pcall(json.decode, r.charinfo)
                if ok and decoded then
                    ci = decoded
                end
            elseif type(r.charinfo) == 'table' then
                ci = r.charinfo
            end
            local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$','%1')
            table.insert(list, {
                citizenid = r.citizenid,
                name = (name ~= '' and name) or 'Citizen',
                charinfo = ci
            })
        end
        cb(list)
    end)
end)

-- Update charge (admin/chief only)
QBCore.Functions.CreateCallback('pf_mdt:updateCharge', function(source, cb, data)
    if not data or not data.id then
        cb({ success = false, error = 'Invalid data' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ success = false, error = 'Player not found' })
        return
    end

    local jobName, gradeLevel = GetPlayerJob(source)
    if not jobName or not IsAllowedJob(jobName) or (tonumber(gradeLevel) or 0) < 4 then
        cb({ success = false, error = 'Insufficient permissions' })
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local chargeId = tonumber(data.id)
    if not chargeId then
        cb({ success = false, error = 'Invalid charge ID' })
        return
    end

    -- Accept both snake_case and camelCase from older/newer UIs
    local fineAmount = tonumber(data.fine_amount or data.fineAmount) or 0
    local bailAmount = tonumber(data.bail_amount or data.bailAmount) or 0
    local prisonTime = tonumber(data.jail_time or data.prisonTime) or 0
    fineAmount = math.max(0, math.floor(fineAmount))
    bailAmount = math.max(0, math.floor(bailAmount))
    prisonTime = math.max(0, math.floor(prisonTime))

    -- Load current row to validate ID and log before/after
    exports.oxmysql:execute('SELECT id, code, name, description, fineAmount, bailAmount, prisonTime, category FROM pf_mdt_charges WHERE id = ? LIMIT 1', { chargeId }, function(beforeRows)
        local before = beforeRows and beforeRows[1] or nil
        if not before then
            cb({ success = false, error = 'Charge not found' })
            return
        end

        local newCode = data.code or before.code or 'UNKNOWN'
        local newName = data.name or before.name or 'Unknown'
        local newDesc = (data.description ~= nil) and data.description or (before.description or '')
        local newCategory = data.category or before.category or 'General'

        -- Check for code uniqueness collision (code is UNIQUE)
        exports.oxmysql:execute('SELECT id FROM pf_mdt_charges WHERE code = ? AND id <> ? LIMIT 1', { newCode, chargeId }, function(conflictRows)
            if conflictRows and conflictRows[1] and conflictRows[1].id then
                cb({ success = false, error = 'Charge code already exists: ' .. tostring(newCode) })
                return
            end

            dprint(('[MDT] updateCharge BEFORE id=%s code=%s fine=%s bail=%s prison=%s'):format(
                tostring(before.id), tostring(before.code), tostring(before.fineAmount), tostring(before.bailAmount), tostring(before.prisonTime)
            ))
            dprint(('[MDT] updateCharge APPLY  id=%s code=%s fine=%s bail=%s prison=%s'):format(
                tostring(chargeId), tostring(newCode), tostring(fineAmount), tostring(bailAmount), tostring(prisonTime)
            ))

            local query = [[
                UPDATE pf_mdt_charges
                SET code = ?, name = ?, description = ?, fineAmount = ?, bailAmount = ?, prisonTime = ?, category = ?
                WHERE id = ?
            ]]

            GetChargesSchema(function(schema)
                -- If camelCase numeric columns are generated, we must write the backing snake_case columns.
                if schema.camelGenerated and schema.hasLegacySnake then
                    query = [[
                        UPDATE pf_mdt_charges
                        SET code = ?, name = ?, description = ?, fine_amount = ?, bail_amount = ?, jail_time = ?, category = ?
                        WHERE id = ?
                    ]]
                end

                local params = {
                    newCode,
                    newName,
                    newDesc,
                    fineAmount,
                    bailAmount,
                    prisonTime,
                    newCategory,
                    chargeId
                }

                local function finishUpdate(affectedRows)
                    local n = tonumber(affectedRows) or 0
                    dprint('[MDT] updateCharge affectedRows=' .. tostring(n))

                    exports.oxmysql:execute('SELECT id, code, name, description, fineAmount, bailAmount, prisonTime, category FROM pf_mdt_charges WHERE id = ? LIMIT 1', { chargeId }, function(afterRows)
                        local after = afterRows and afterRows[1] or nil
                        if after then
                            dprint(('[MDT] updateCharge AFTER  id=%s code=%s fine=%s bail=%s prison=%s'):format(
                                tostring(after.id), tostring(after.code), tostring(after.fineAmount), tostring(after.bailAmount), tostring(after.prisonTime)
                            ))
                        end

                        if not after then
                            cb({ success = false, error = 'Charge not found after update' })
                            return
                        end

                        local req = { fineAmount = fineAmount, bailAmount = bailAmount, prisonTime = prisonTime }

                        -- If DB still doesn't reflect requested numeric values, surface it clearly.
                        local dbFine = tonumber(after.fineAmount) or 0
                        local dbBail = tonumber(after.bailAmount) or 0
                        local dbPrison = tonumber(after.prisonTime) or 0
                        if dbFine ~= fineAmount or dbBail ~= bailAmount or dbPrison ~= prisonTime then
                            -- Attempt to diagnose common DB causes: triggers, view/table mismatch, generated columns, or wrong DB connection.
                            FetchChargesDiagnostics(function(diag)
                                local conn = diag.connection or {}
                                local tbl = diag.table or {}
                                dprint(('[MDT] updateCharge DB mismatch: connected db=%s host=%s port=%s sql_mode=%s'):format(
                                    tostring(conn.db), tostring(conn.host), tostring(conn.port), tostring(conn.sql_mode)
                                ))
                                dprint(('[MDT] updateCharge tableInfo: type=%s engine=%s collation=%s'):format(
                                    tostring(tbl.TABLE_TYPE), tostring(tbl.ENGINE), tostring(tbl.TABLE_COLLATION)
                                ))
                                dprint('[MDT] updateCharge requested=' .. json.encode(req))
                                dprint('[MDT] updateCharge afterRow=' .. json.encode(after))
                                dprint('[MDT] updateCharge diagnostics=' .. json.encode({ columns = diag.columns or {}, triggers = diag.triggers or {} }))

                                cb({
                                    success = false,
                                    error = 'Database did not persist numeric values',
                                    requested = req,
                                    charge = after,
                                    diagnostics = diag
                                })
                            end)
                            return
                        end

                        -- Treat 0 affected rows as success when values are unchanged.
                        cb({
                            success = true,
                            message = (n > 0) and 'Charge updated' or 'No changes detected',
                            requested = req,
                            charge = after
                        })
                    end)
                end

                -- Prefer oxmysql:update if present; fall back to execute
                local ok = pcall(function()
                    exports.oxmysql:update(query, params, function(affectedRows)
                        finishUpdate(affectedRows)
                    end)
                end)
                if not ok then
                    exports.oxmysql:execute(query, params, function(affectedRows)
                        finishUpdate(affectedRows)
                    end)
                end
            end)
        end)
    end)
end)

-- Create new charge (admin/chief only)
QBCore.Functions.CreateCallback('pf_mdt:createCharge', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, error = 'Player not found' }) return end
    
    local jobName, gradeLevel = GetPlayerJob(source)
    if not IsSupervisor(jobName, gradeLevel) then
        cb({ success = false, error = 'Only supervisors can create charges' })
        return
    end
    
    if not (hasOxMySQL() and exports.oxmysql) then cb({ success = false, error = 'Database unavailable' }) return end
    
    dprint('[MDT DEBUG] Raw data received:', json.encode(data))
    
    local code = data and data.code or 'CUSTOM'
    local name = data and data.name or 'Custom Charge'
    local description = data and data.description or ''
    local fineAmount = math.max(0, math.floor(tonumber(data and data.fine_amount) or 0))
    local bailAmount = math.max(0, math.floor(tonumber(data and data.bail_amount) or 0))
    local prisonTime = math.max(0, math.floor(tonumber(data and data.jail_time) or 0))
    local category = data and data.category or 'General'
    
    dprint('[MDT DEBUG] Parsed values - Fine:', fineAmount, 'Bail:', bailAmount, 'Prison:', prisonTime)
    dprint('[MDT DEBUG] Raw fine_amount field:', data and data.fine_amount)
    dprint('[MDT DEBUG] Raw bail_amount field:', data and data.bail_amount)
    dprint('[MDT DEBUG] Raw jail_time field:', data and data.jail_time)
    
    if not code or not name then
        cb({ success = false, error = 'Code and Name are required' })
        return
    end
    
    GetChargesSchema(function(schema)
        local insertSql = 'INSERT INTO pf_mdt_charges (code, name, description, fineAmount, bailAmount, prisonTime, category) VALUES (?, ?, ?, ?, ?, ?, ?)'
        if schema.camelGenerated and schema.hasLegacySnake then
            insertSql = 'INSERT INTO pf_mdt_charges (code, name, description, fine_amount, bail_amount, jail_time, category) VALUES (?, ?, ?, ?, ?, ?, ?)'
        end

        exports.oxmysql:insert(insertSql,
            { code, name, description, fineAmount, bailAmount, prisonTime, category },
            function(id)
            dprint('[MDT DEBUG] Insert result - ID:', id, 'Inserted values - Fine:', fineAmount, 'Bail:', bailAmount, 'Prison:', prisonTime)
            if not id then
                cb({ success = false, error = 'Failed to create charge' })
                return
            end

            exports.oxmysql:execute('SELECT id, code, name, description, fineAmount, bailAmount, prisonTime, category FROM pf_mdt_charges WHERE id = ? LIMIT 1', { id }, function(afterRows)
                local after = afterRows and afterRows[1] or nil
                if not after then
                    cb({ success = true, message = 'Charge created', id = id })
                    return
                end

                local dbFine = tonumber(after.fineAmount) or 0
                local dbBail = tonumber(after.bailAmount) or 0
                local dbPrison = tonumber(after.prisonTime) or 0
                if dbFine ~= math.floor(fineAmount) or dbBail ~= math.floor(bailAmount) or dbPrison ~= math.floor(prisonTime) then
                    FetchChargesDiagnostics(function(diag)
                        local conn = diag.connection or {}
                        local tbl = diag.table or {}
                        dprint(('[MDT] createCharge DB mismatch: connected db=%s host=%s port=%s sql_mode=%s'):format(
                            tostring(conn.db), tostring(conn.host), tostring(conn.port), tostring(conn.sql_mode)
                        ))
                        dprint(('[MDT] createCharge tableInfo: type=%s engine=%s collation=%s'):format(
                            tostring(tbl.TABLE_TYPE), tostring(tbl.ENGINE), tostring(tbl.TABLE_COLLATION)
                        ))
                        dprint('[MDT] createCharge requested=' .. json.encode({ fineAmount = fineAmount, bailAmount = bailAmount, prisonTime = prisonTime }))
                        dprint('[MDT] createCharge afterRow=' .. json.encode(after))
                        cb({
                            success = false,
                            error = 'Database did not persist numeric values',
                            requested = { fineAmount = fineAmount, bailAmount = bailAmount, prisonTime = prisonTime },
                            charge = after,
                            diagnostics = diag
                        })
                    end)
                    return
                end

                cb({ success = true, message = 'Charge created', id = id, charge = after })
            end)
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:deleteCharge', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, error = 'Player not found' }) return end
    
    local jobName, gradeLevel = GetPlayerJob(source)
    if not IsSupervisor(jobName, gradeLevel) then
        cb({ success = false, error = 'Only supervisors can delete charges' })
        return
    end
    
    if not (hasOxMySQL() and exports.oxmysql) then cb({ success = false, error = 'Database unavailable' }) return end
    
    local chargeId = data and data.id
    if not chargeId then cb({ success = false, error = 'Charge ID required' }) return end
    
    exports.oxmysql:execute('DELETE FROM pf_mdt_charges WHERE id = ?', { chargeId }, function(affected)
        local changed = affected
        if type(changed) == 'table' then
            changed = changed.affectedRows or changed.changedRows or 0
        end
        changed = tonumber(changed) or 0
        if changed > 0 then
            cb({ success = true, message = 'Charge deleted' })
        else
            cb({ success = false, error = 'Charge not found' })
        end
    end)
end)

-- ============================================================================
-- Weapons Registry
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mdt:getServerTime', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end
    cb({ success = true, now = os.date('%Y-%m-%d %H:%M:%S') })
end)

QBCore.Functions.CreateCallback('pf_mdt:getWeaponModels', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, models = {}, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, models = {}, error = 'Access denied' })
        return
    end

    local models = {}
    if QBCore and QBCore.Shared and QBCore.Shared.Weapons then
        for key, w in pairs(QBCore.Shared.Weapons) do
            local weaponName = (type(w) == 'table' and (w.name or w.weapon)) or key
            local label = (type(w) == 'table' and w.label) or weaponName
            if weaponName and weaponName ~= '' then
                models[#models+1] = { weapon = weaponName, label = label or weaponName }
            end
        end
        table.sort(models, function(a, b)
            return tostring(a.label or '') < tostring(b.label or '')
        end)
    end

    cb({ success = true, models = models })
end)

QBCore.Functions.CreateCallback('pf_mdt:getWeaponRegistry', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, weapons = {}, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, weapons = {}, error = 'Access denied' })
        return
    end
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, weapons = {}, error = 'Database unavailable' })
        return
    end

    exports.oxmysql:execute([[
        SELECT id,
               serial,
               weapon,
               weaponLabel,
               ownerCitizenId,
               ownerName,
               DATE_FORMAT(registeredAt, '%Y-%m-%d %H:%i:%s') as registeredAt
        FROM pf_mdt_weapons_registry
        ORDER BY registeredAt DESC, id DESC
    ]], {}, function(rows)
        cb({ success = true, weapons = rows or {} })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:getCitizenWeapons', function(source, cb, citizenId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, weapons = {}, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, weapons = {}, error = 'Access denied' })
        return
    end
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, weapons = {}, error = 'Database unavailable' })
        return
    end

    local cid = tostring(citizenId or ''):gsub('^%s*(.-)%s*$', '%1')
    if cid == '' then
        cb({ success = true, weapons = {} })
        return
    end

    exports.oxmysql:execute([[
        SELECT id,
               serial,
               weapon,
               weaponLabel,
               ownerCitizenId,
               ownerName,
               notes,
               DATE_FORMAT(registeredAt, '%Y-%m-%d %H:%i:%s') as registeredAt
        FROM pf_mdt_weapons_registry
        WHERE ownerCitizenId = ?
        ORDER BY registeredAt DESC, id DESC
    ]], { cid }, function(rows)
        cb({ success = true, weapons = rows or {} })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:checkWeaponSerial', function(source, cb, serial)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, exists = true, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, exists = true, error = 'Access denied' })
        return
    end
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, exists = true, error = 'Database unavailable' })
        return
    end

    local s = tostring(serial or ''):gsub('^%s*(.-)%s*$', '%1')
    if s == '' then
        cb({ success = true, exists = false })
        return
    end

    exports.oxmysql:execute('SELECT id FROM pf_mdt_weapons_registry WHERE serial = ? LIMIT 1', { s }, function(rows)
        local exists = (rows and rows[1] and rows[1].id) ~= nil
        cb({ success = true, exists = exists })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:searchWeaponOwners', function(source, cb, query)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, citizens = {}, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, citizens = {}, error = 'Access denied' })
        return
    end

    local q = tostring(query or ''):gsub('^%s*(.-)%s*$', '%1')
    if q == '' or #q < 2 then
        cb({ success = true, citizens = {} })
        return
    end

    -- Prefer DB search so offline citizens appear
    if hasOxMySQL() and exports.oxmysql then
        local like = '%' .. q .. '%'
        exports.oxmysql:execute('SELECT citizenid, charinfo FROM players WHERE citizenid LIKE ? OR charinfo LIKE ? LIMIT 25', { like, like }, function(rows)
            local out = {}
            for _, r in ipairs(rows or {}) do
                local ci = (type(r.charinfo) == 'string' and json.decode(r.charinfo)) or r.charinfo or {}
                local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
                out[#out+1] = { citizenid = r.citizenid, name = (name ~= '' and name) or r.citizenid }
            end
            cb({ success = true, citizens = out })
        end)
        return
    end

    -- Fallback: online players only
    local out = {}
    local players = QBCore.Functions.GetQBPlayers()
    local qLower = q:lower()
    for _, P in pairs(players) do
        local cid = P.PlayerData.citizenid or ''
        local ci = P.PlayerData.charinfo or {}
        local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
        if cid:lower():find(qLower, 1, true) or name:lower():find(qLower, 1, true) then
            out[#out+1] = { citizenid = cid, name = (name ~= '' and name) or cid }
        end
        if #out >= 25 then break end
    end
    cb({ success = true, citizens = out })
end)

QBCore.Functions.CreateCallback('pf_mdt:registerWeapon', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local ownerCitizenId = data and (data.ownerCitizenId or data.ownerCitizenID or data.ownerCitizenid or data.owner) or nil
    local ownerName = data and (data.ownerName or data.owner_name) or nil
    local weapon = data and (data.weapon or data.model) or nil
    local weaponLabel = data and (data.weaponLabel or data.weapon_label) or nil
    local serial = data and data.serial or nil
    local notes = data and data.notes or nil

    ownerCitizenId = tostring(ownerCitizenId or ''):gsub('^%s*(.-)%s*$', '%1')
    weapon = tostring(weapon or ''):gsub('^%s*(.-)%s*$', '%1')
    serial = tostring(serial or ''):gsub('^%s*(.-)%s*$', '%1')
    ownerName = tostring(ownerName or ''):gsub('^%s*(.-)%s*$', '%1')
    weaponLabel = tostring(weaponLabel or ''):gsub('^%s*(.-)%s*$', '%1')
    notes = tostring(notes or '')

    if ownerCitizenId == '' or weapon == '' or serial == '' then
        cb({ success = false, error = 'Missing required fields' })
        return
    end

    local officerCid = Player.PlayerData.citizenid
    local ci = Player.PlayerData.charinfo or {}
    local officerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    if officerName == '' then officerName = 'Officer' end

    exports.oxmysql:execute('SELECT id FROM pf_mdt_weapons_registry WHERE serial = ? LIMIT 1', { serial }, function(existing)
        if existing and existing[1] and existing[1].id then
            cb({ success = false, error = 'Serial already exists' })
            return
        end

        exports.oxmysql:insert([[
            INSERT INTO pf_mdt_weapons_registry
                (serial, weapon, weaponLabel, ownerCitizenId, ownerName, registeredAt, registeredByCitizenId, registeredByName, notes)
            VALUES
                (?, ?, ?, ?, ?, NOW(), ?, ?, ?)
        ]], { serial, weapon, weaponLabel, ownerCitizenId, ownerName, officerCid, officerName, notes }, function(id)
            if not id then
                cb({ success = false, error = 'Insert failed' })
                return
            end
            exports.oxmysql:execute([[
                SELECT id,
                       serial,
                       weapon,
                       weaponLabel,
                       ownerCitizenId,
                       ownerName,
                       DATE_FORMAT(registeredAt, '%Y-%m-%d %H:%i:%s') as registeredAt
                FROM pf_mdt_weapons_registry
                WHERE id = ?
                LIMIT 1
            ]], { id }, function(rows)
                cb({ success = true, weapon = (rows and rows[1]) or nil })
            end)
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:createManualWeapon', function(source, cb, data)
    if not IsManualEntriesEnabled() then
        cb({ success = false, error = 'Manual entries are disabled in config' })
        return
    end
    QBCore.Functions.TriggerCallback('pf_mdt:registerWeapon', source, function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

QBCore.Functions.CreateCallback('pf_mdt:createManualCitizen', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end
    if not IsManualEntriesEnabled() then
        cb({ success = false, error = 'Manual entries are disabled in config' })
        return
    end
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local function clean(v)
        return tostring(v or ''):gsub('^%s*(.-)%s*$', '%1')
    end

    local citizenId = clean(data and data.citizenId)
    if citizenId == '' then
        citizenId = ('MAN-%s-%04d'):format(os.date('%y%m%d%H%M%S'), math.random(1000, 9999))
    end

    local firstname = clean(data and data.firstname)
    local lastname = clean(data and data.lastname)
    if firstname == '' or lastname == '' then
        cb({ success = false, error = 'First name and last name are required' })
        return
    end

    local dob = clean(data and data.dob)
    local phone = clean(data and data.phone)
    local nationality = clean(data and data.nationality)
    local gender = clean(data and data.gender)
    local job = clean(data and data.job)
    local address = clean(data and data.address)
    local profilePicture = clean(data and data.profilePicture)

    local ci = Player.PlayerData.charinfo or {}
    local officerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    if officerName == '' then officerName = 'Officer' end
    local officerCid = tostring(Player.PlayerData.citizenid or '')

    exports.oxmysql:execute('SELECT id FROM pf_mdt_manual_citizens WHERE citizenId = ? LIMIT 1', { citizenId }, function(existing)
        if existing and existing[1] and existing[1].id then
            cb({ success = false, error = 'Citizen ID already exists' })
            return
        end

        exports.oxmysql:insert([[
            INSERT INTO pf_mdt_manual_citizens
                (citizenId, firstname, lastname, dob, phone, nationality, gender, job, address, profilePicture, createdByCitizenId, createdByName, createdAt)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
        ]], { citizenId, firstname, lastname, dob, phone, nationality, gender, job, address, profilePicture, officerCid, officerName }, function(insertId)
            if not insertId then
                cb({ success = false, error = 'Insert failed' })
                return
            end
            cb({ success = true, citizenId = citizenId })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:createManualVehicle', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ success = false, error = 'Player not found' }) return end
    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end
    if not IsManualEntriesEnabled() then
        cb({ success = false, error = 'Manual entries are disabled in config' })
        return
    end
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local function clean(v)
        return tostring(v or ''):gsub('^%s*(.-)%s*$', '%1')
    end

    local plate = clean(data and data.plate)
    if plate == '' then
        cb({ success = false, error = 'Plate is required' })
        return
    end

    local ownerCitizenId = clean(data and data.ownerCitizenId)
    local ownerName = clean(data and data.ownerName)
    local model = clean(data and data.model)
    local modelLabel = clean(data and data.modelLabel)
    local brand = clean(data and data.brand)
    local primaryColorId = tonumber(data and data.primaryColorId)
    local secondaryColorId = tonumber(data and data.secondaryColorId)
    local vehiclePhoto = clean(data and data.vehiclePhoto)

    local ci = Player.PlayerData.charinfo or {}
    local officerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    if officerName == '' then officerName = 'Officer' end
    local officerCid = tostring(Player.PlayerData.citizenid or '')

    exports.oxmysql:execute('SELECT plate FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }, function(autoRows)
        if autoRows and autoRows[1] then
            cb({ success = false, error = 'Plate already exists in automatic vehicles' })
            return
        end

        exports.oxmysql:execute('SELECT id FROM pf_mdt_manual_vehicles WHERE plate = ? LIMIT 1', { plate }, function(existing)
            if existing and existing[1] and existing[1].id then
                cb({ success = false, error = 'Plate already exists' })
                return
            end

            exports.oxmysql:insert([[
                INSERT INTO pf_mdt_manual_vehicles
                    (plate, ownerCitizenId, ownerName, model, modelLabel, brand, primaryColorId, secondaryColorId, vehiclePhoto, createdByCitizenId, createdByName, createdAt)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
            ]], { plate, ownerCitizenId, ownerName, model, modelLabel, brand, primaryColorId, secondaryColorId, vehiclePhoto, officerCid, officerName }, function(insertId)
                if not insertId then
                    cb({ success = false, error = 'Insert failed' })
                    return
                end
                cb({ success = true, plate = plate })
            end)
        end)
    end)
end)

-- Auto-approve reports older than 24 hours
-- Runs every hour to check for pending reports
CreateThread(function()
    while true do
        Wait(3600000) -- Check every hour (3600000 ms = 1 hour)
        
        if hasOxMySQL() and exports.oxmysql then
            -- Auto-approve reports that are older than 24 hours and still pending
            exports.oxmysql:execute('UPDATE pf_mdt_reports SET approvalStatus = ?, status = ? WHERE approvalStatus = ? AND createdAt < DATE_SUB(NOW(), INTERVAL 24 HOUR)',
                { 'approved', 'approved', 'pending' },
                function(affectedRows)
                    local affected = affectedRows
                    if type(affected) == 'table' then
                        affected = affected.affectedRows or affected.changedRows or 0
                    end
                    affected = tonumber(affected) or 0
                    if affected > 0 then
                        dprint('[MDT] Auto-approved ' .. affected .. ' reports older than 24 hours')
                    end
                end)
        end
    end
end)

-- Update a warrant's status (e.g., served or removed)
RegisterNetEvent('pf_mdt:updateWarrantStatus', function(data)
    local src = source
    local status = data and data.status or nil
    local warrantId = data and data.warrantId or nil
    if not status or not warrantId then return end
    local allowed = { served = true, removed = true }
    if not allowed[status] then return end
    if status == 'removed' then
        local jobName, gradeLevel = GetPlayerJob(src)
        local perms = Config.Permissions and Config.Permissions.deleteWarrant or nil
        local minGrade = tonumber(perms and perms[jobName]) or 3
        if (tonumber(gradeLevel) or 0) < minGrade then
            TriggerClientEvent('QBCore:Notify', src, 'Insufficient rank to remove warrants', 'error')
            return
        end
    end

    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute('UPDATE pf_mdt_warrants SET status = ? WHERE warrantId = ?', { status, warrantId }, function(affected)
            local changed = affected
            if type(changed) == 'table' then
                changed = changed.affectedRows or changed.changedRows or 0
            end
            changed = tonumber(changed) or 0
            if changed > 0 then
                TriggerClientEvent('QBCore:Notify', src, ('Warrant %s marked as %s.'):format(warrantId, status), 'success')
            else
                TriggerClientEvent('QBCore:Notify', src, 'Failed to update warrant status.', 'error')
            end
        end)
    else
        for i, w in ipairs(WarrantsStore) do
            if w.warrantId == warrantId then
                w.status = status
                TriggerClientEvent('QBCore:Notify', src, ('Warrant %s marked as %s.'):format(warrantId, status), 'success')
                break
            end
        end
    end
end)

-- ============================================================================
-- EVIDENCE SYSTEM
-- ============================================================================

-- Helper: Get next evidence number for an incident
local function GetNextEvidenceNumber(incidentId, cb)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb(1)
        return
    end
    
    exports.oxmysql:scalar('SELECT COALESCE(MAX(evidence_number), 0) + 1 FROM pf_mdt_incident_evidence WHERE incident_id = ?', 
        { incidentId }, 
        function(nextNum)
            cb(nextNum or 1)
        end)
end

-- Add evidence photo to incident
RegisterNetEvent('pf_mdt:server:AddIncidentEvidencePhoto', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local jobName, gradeLevel = GetPlayerJob(src)
    if not IsAllowedJob(jobName) then
        TriggerClientEvent('QBCore:Notify', src, 'Access denied', 'error')
        return
    end
    
    -- Check minimum grade for evidence creation
    if gradeLevel < (Config.Evidence and Config.Evidence.MinGradeCreate or 0) then
        TriggerClientEvent('QBCore:Notify', src, 'Insufficient rank to add evidence', 'error')
        return
    end
    
    local incidentId = data.incidentId
    local imageUrl = data.imageUrl
    local title = data.title or ''
    local description = data.description or ''
    
    if not incidentId or not imageUrl then
        TriggerClientEvent('QBCore:Notify', src, 'Missing required data', 'error')
        return
    end
    
    if not (hasOxMySQL() and exports.oxmysql) then
        TriggerClientEvent('QBCore:Notify', src, 'Database unavailable', 'error')
        return
    end
    
    local charinfo = Player.PlayerData.charinfo or {}
    local creatorName = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    if creatorName == '' then creatorName = 'Officer' end
    
    GetNextEvidenceNumber(incidentId, function(evidenceNumber)
        exports.oxmysql:insert('INSERT INTO pf_mdt_incident_evidence (incident_id, evidence_number, title, description, image_url, created_by_citizenid, created_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { incidentId, evidenceNumber, title, description, imageUrl, Player.PlayerData.citizenid, creatorName },
            function(insertId)
                if insertId then
                    TriggerClientEvent('QBCore:Notify', src, 'Evidence photo added: #' .. evidenceNumber, 'success')
                    TriggerClientEvent('pf_mdt:client:RefreshIncidentEvidence', src, incidentId)
                else
                    TriggerClientEvent('QBCore:Notify', src, 'Failed to add evidence', 'error')
                end
            end)
    end)
end)

-- Get all evidence for an incident
QBCore.Functions.CreateCallback('pf_mdt:getIncidentEvidence', function(source, cb, data)
    local incidentId = data and data.incidentId
    if not incidentId then
        cb({ success = false, evidence = {} })
        return
    end
    
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, evidence = {} })
        return
    end
    
    exports.oxmysql:execute('SELECT * FROM pf_mdt_incident_evidence WHERE incident_id = ? ORDER BY evidence_number ASC',
        { incidentId },
        function(rows)
            cb({ success = true, evidence = rows or {} })
        end)
end)

-- Get all vehicles (for dropdowns)
QBCore.Functions.CreateCallback('pf_mdt:getAllVehicles', function(source, cb)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end
    
    exports.oxmysql:execute('SELECT plate, vehicle, citizenid FROM player_vehicles ORDER BY plate ASC',
        {},
        function(rows)
            local vehicles = {}
            for _, v in ipairs(rows or {}) do
                local vehicleData = json.decode(v.vehicle or '{}')
                table.insert(vehicles, {
                    plate = v.plate,
                    model = vehicleData.model or 'Unknown',
                    owner = v.citizenid
                })
            end
            cb(vehicles)
        end)
end)

-- Get all charges (for dropdowns)
QBCore.Functions.CreateCallback('pf_mdt:getAllCharges', function(source, cb)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end
    
    exports.oxmysql:execute('SELECT code, name, description, fineAmount, bailAmount, prisonTime, category FROM pf_mdt_charges ORDER BY code ASC',
        {},
        function(rows)
            cb(rows or {})
        end)
end)

-- ============================================================================
-- STANDALONE EVIDENCE SYSTEM
-- ============================================================================

-- Helper: Generate evidence ID
local function GenerateEvidenceId()
    local timestamp = os.time()
    local random = math.random(1000, 9999)
    return string.format("EVD-%d-%d", timestamp, random)
end

-- Search/Get all evidence
QBCore.Functions.CreateCallback('pf_mdt:searchEvidence', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, evidence = {}, totalCount = 0 })
        return
    end
    
    local query = data and data.query or ''
    local page = (data and data.page or 1)
    local pageSize = (data and data.pageSize or 12)
    local offset = (page - 1) * pageSize
    
    local searchPattern = '%' .. query .. '%'
    local sql = [[
        SELECT * FROM pf_mdt_evidence 
        WHERE title LIKE ? OR description LIKE ? OR evidence_id LIKE ? OR tags LIKE ?
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]]
    
    exports.oxmysql:execute(sql, { searchPattern, searchPattern, searchPattern, searchPattern, pageSize, offset }, function(rows)
        -- Get total count
        exports.oxmysql:scalar('SELECT COUNT(*) FROM pf_mdt_evidence WHERE title LIKE ? OR description LIKE ? OR evidence_id LIKE ? OR tags LIKE ?',
            { searchPattern, searchPattern, searchPattern, searchPattern },
            function(count)
                cb({ success = true, evidence = rows or {}, totalCount = count or 0 })
            end)
    end)
end)

-- Get all citizens for dropdowns (from database, not just online players)
QBCore.Functions.CreateCallback('pf_mdt:getAllCitizens', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end
    
    exports.oxmysql:execute('SELECT citizenid, charinfo FROM players LIMIT 5000', {}, function(rows)
        local results = {}
        for _, r in ipairs(rows or {}) do
            local charinfo = (type(r.charinfo) == 'string' and json.decode(r.charinfo)) or r.charinfo or {}
            local firstname = charinfo.firstname or ''
            local lastname = charinfo.lastname or ''
            local name = (firstname .. ' ' .. lastname):gsub('^%s*(.-)%s*$', '%1')
            if name ~= '' and r.citizenid then
                results[#results+1] = {
                    citizenId = r.citizenid,
                    name = name
                }
            end
        end
        cb(results)
    end)
end)

-- Get all vehicles for dropdowns
QBCore.Functions.CreateCallback('pf_mdt:getAllVehicles', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end
    
    exports.oxmysql:execute('SELECT plate, vehicle FROM player_vehicles ORDER BY plate LIMIT 1000', {}, function(rows)
        local results = {}
        for _, r in ipairs(rows or {}) do
            results[#results+1] = {
                plate = r.plate,
                model = r.vehicle or 'Unknown'
            }
        end
        cb(results)
    end)
end)

-- Get all charges for dropdowns
QBCore.Functions.CreateCallback('pf_mdt:getAllCharges', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end
    
    exports.oxmysql:execute('SELECT code, name, description, fineAmount, bailAmount, prisonTime, category FROM pf_mdt_charges ORDER BY code', {}, function(rows)
        cb(rows or {})
    end)
end)

-- ============================================================================
-- SENTENCING / PRISON
-- ============================================================================

local function getReductionPercentByKey(key)
    local cfg = Config.Sentencing and Config.Sentencing.Reductions or {}
    for _, r in ipairs(cfg) do
        if r and r.key == key then
            return tonumber(r.percent) or 0
        end
    end
    return 0
end

local function normalizeSentenceType(t)
    t = string.lower(tostring(t or ''))
    if t == 'fine' then return 'fine' end
    if t == 'sentence' then return 'sentence' end
    if t == 'fine+sentence' or t == 'fine_sentence' or t == 'fineandsentence' or t == 'both' then return 'fine+sentence' end
    return 'sentence'
end

local function getOfficerIdentity(Player)
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid or nil
    local char = Player and Player.PlayerData and Player.PlayerData.charinfo or nil
    local name = (char and ((char.firstname or '') .. ' ' .. (char.lastname or ''))) or ''
    name = (name:gsub('^%s*(.-)%s*$', '%1'))
    return cid, (name ~= '' and name or (cid or 'Officer'))
end

local function getOnlinePlayerByCitizenId(citizenId)
    if not citizenId then return nil end
    if QBCore.Functions.GetPlayerByCitizenId then
        return QBCore.Functions.GetPlayerByCitizenId(citizenId)
    end
    for _, P in pairs(QBCore.Functions.GetQBPlayers() or {}) do
        if P and P.PlayerData and P.PlayerData.citizenid == citizenId then
            return P
        end
    end
    return nil
end

-- Required helper: resolve server source from citizenid by iterating QBCore.Functions.GetPlayers()
function ResolveSourceFromCitizenId(citizenid)
    citizenid = tostring(citizenid or '')
    if citizenid == '' then return nil end

    local players = QBCore.Functions.GetPlayers and QBCore.Functions.GetPlayers() or {}
    for _, src in pairs(players) do
        local s = tonumber(src)
        if s then
            local P = QBCore.Functions.GetPlayer(s)
            if P and P.PlayerData and P.PlayerData.citizenid == citizenid then
                return s
            end
        end
    end
    return nil
end

local function isPoliceSupervisor(source)
    local jobName, gradeLevel = GetPlayerJob(source)
    if jobName ~= 'police' then
        return false, 'Access denied'
    end
    if not IsSupervisor(jobName, gradeLevel) then
        return false, 'Insufficient permissions'
    end
    return true, nil
end

-- Runtime state: who is currently jailed from MDT sentencing (for Bail button + time left)
local ActiveJails = {} -- citizenId -> { endsAt=os.time(), bailAmount=number, sentenceId=number|nil, targetSource=number|nil }
local PendingJailSentenceIds = {} -- citizenId -> last sentence DB id (used when jail is scheduled after insert)

-- Inventory stash for built-in MDT jail flow
-- citizenId -> { source=number, items=table, savedAt=os.time() }
local StoredJailInventories = {}

-- The confiscated items are read from the server's inventory only. They used to come from a
-- snapshot the jailed player's own client sent back (pf_mdt:server:InventorySnapshot), so a modified
-- client could list any items and get them all "restored" on release.

local function getInventoryProvider()
    if GetResourceState and GetResourceState('ox_inventory') == 'started' then
        return 'ox_inventory'
    end
    if GetResourceState and GetResourceState('pfm-inventory') == 'started' then
        return 'qb-inventory'
    end
    if GetResourceState and GetResourceState('lj-inventory') == 'started' then
        return 'lj-inventory'
    end
    if GetResourceState and GetResourceState('ps-inventory') == 'started' then
        return 'ps-inventory'
    end
    if GetResourceState and GetResourceState('qs-inventory') == 'started' then
        return 'qs-inventory'
    end
    return 'qbcore'
end

local function getActiveJail(citizenId)
    if not citizenId or citizenId == '' then return nil end
    local st = ActiveJails[citizenId]
    if not st then return nil end
    if (tonumber(st.endsAt) or 0) <= os.time() then
        -- Expired; keep state until the client signals release so we can restore inventory safely.
        return nil
    end
    return st
end

local function stashInventoryForBuiltInMdtJail(targetSource)
    local P = QBCore.Functions.GetPlayer(tonumber(targetSource))
    if not P or not P.PlayerData then return false, 'Player not found' end

    local cid = P.PlayerData.citizenid
    if not cid or cid == '' then return false, 'Missing citizenid' end
    if StoredJailInventories[cid] then
        return true, nil
    end

    local provider = getInventoryProvider()

    local items = {}
    do
        if provider == 'ox_inventory' then
            local okItems, oxItems = pcall(function()
                if exports.ox_inventory.GetInventoryItems then
                    return exports.ox_inventory:GetInventoryItems(tonumber(targetSource))
                end
                local inv = exports.ox_inventory:GetInventory(tonumber(targetSource))
                return inv and inv.items or {}
            end)
            if okItems and type(oxItems) == 'table' then
                for slot, it in pairs(oxItems) do
                    local count = tonumber(it.count or it.amount) or 0
                    if it and it.name and count > 0 then
                        items[#items + 1] = {
                            name = it.name,
                            amount = count,
                            slot = tonumber(it.slot) or tonumber(slot) or nil,
                            info = it.metadata,
                        }
                    end
                end
            end
        else
            local inv = (P.PlayerData and P.PlayerData.items) or {}
            for slot, it in pairs(inv or {}) do
                if it and it.name and (tonumber(it.amount) or 0) > 0 then
                    items[#items + 1] = {
                        name = it.name,
                        amount = tonumber(it.amount) or 0,
                        slot = tonumber(it.slot) or tonumber(slot) or nil,
                        info = it.info,
                    }
                end
            end
        end
    end

    StoredJailInventories[cid] = {
        source = tonumber(targetSource),
        items = items,
        savedAt = os.time(),
        provider = provider
    }

    print(('[MDT] Jail stash: cid=%s provider=%s items=%d'):format(tostring(cid), tostring(provider), tonumber(#items) or 0))

    TriggerClientEvent('QBCore:Notify', targetSource, ('MDT: Items confiscated (%s)'):format(tonumber(#items) or 0), 'error')

    if provider == 'ox_inventory' then
        local okClear, errClear = pcall(function()
            exports.ox_inventory:ClearInventory(tonumber(targetSource))
        end)
        if okClear then
            return true, nil
        end
        -- fallback remove
        for _, it in ipairs(items) do
            pcall(function()
                exports.ox_inventory:RemoveItem(tonumber(targetSource), it.name, it.amount, it.metadata, it.slot)
            end)
        end
        return true, tostring(errClear)
    end

    if provider == 'qb-inventory' then
        pcall(function()
            exports['pfm-inventory']:ClearInventory(tonumber(targetSource))
        end)

        -- Some forks accept a second arg (keep table)
        pcall(function()
            exports['pfm-inventory']:ClearInventory(tonumber(targetSource), {})
        end)
    end

    if provider == 'lj-inventory' then
        pcall(function()
            exports['lj-inventory']:ClearInventory(tonumber(targetSource))
        end)
    end

    if provider == 'ps-inventory' then
        pcall(function()
            exports['ps-inventory']:ClearInventory(tonumber(targetSource))
        end)
    end

    if provider == 'qs-inventory' then
        pcall(function()
            exports['qs-inventory']:ClearInventory(tonumber(targetSource))
        end)
    end

    if P.Functions and type(P.Functions.ClearInventory) == 'function' then
        pcall(function()
            P.Functions.ClearInventory()
        end)
    end

    -- Ensure hotbar slots are cleared too (some inventories may not clear them via one call)
    if P.Functions and type(P.Functions.RemoveItem) == 'function' then
        for _, it in ipairs(items) do
            pcall(function()
                local ok = P.Functions.RemoveItem(it.name, it.amount, it.slot)
                if ok == false then
                    P.Functions.RemoveItem(it.name, it.amount)
                end
            end)
        end
    end

    return true, nil
end

local function restoreInventoryForBuiltInMdtJail(targetSource)
    local P = QBCore.Functions.GetPlayer(tonumber(targetSource))
    if not P or not P.PlayerData then return false, 'Player not found' end

    local cid = P.PlayerData.citizenid
    if not cid or cid == '' then return false, 'Missing citizenid' end

    local st = StoredJailInventories[cid]
    if not st then return true, nil end
    -- Allow restore even if the player reconnected (source changed), since citizenid is authoritative.
    if tonumber(st.source) ~= tonumber(targetSource) then
        print(('[MDT] Inventory restore source mismatch for %s (was %s now %s) - proceeding'):format(
            tostring(cid), tostring(st.source), tostring(targetSource)
        ))
        st.source = tonumber(targetSource)
    end

    local provider = st.provider or getInventoryProvider()
    local restored = 0

    -- Clear whatever the player currently has to avoid duplicates and ensure a clean restore.
    if provider == 'ox_inventory' then
        pcall(function()
            exports.ox_inventory:ClearInventory(tonumber(targetSource))
        end)
    elseif provider == 'qb-inventory' then
        pcall(function()
            exports['pfm-inventory']:ClearInventory(tonumber(targetSource))
        end)
        pcall(function()
            exports['pfm-inventory']:ClearInventory(tonumber(targetSource), {})
        end)
    elseif provider == 'lj-inventory' then
        pcall(function()
            exports['lj-inventory']:ClearInventory(tonumber(targetSource))
        end)
    elseif provider == 'ps-inventory' then
        pcall(function()
            exports['ps-inventory']:ClearInventory(tonumber(targetSource))
        end)
    elseif provider == 'qs-inventory' then
        pcall(function()
            exports['qs-inventory']:ClearInventory(tonumber(targetSource))
        end)
    elseif P.Functions and type(P.Functions.ClearInventory) == 'function' then
        pcall(function()
            P.Functions.ClearInventory()
        end)
    end

    if provider == 'ox_inventory' then
        for _, it in ipairs(st.items or {}) do
            if it and it.name and (tonumber(it.amount) or 0) > 0 then
                pcall(function()
                    local ok = exports.ox_inventory:AddItem(tonumber(targetSource), it.name, it.amount, it.metadata or it.info, it.slot)
                    if ok == false then
                        exports.ox_inventory:AddItem(tonumber(targetSource), it.name, it.amount, it.metadata or it.info)
                    end
                end)
                restored = restored + 1
            end
        end
    else
        for _, it in ipairs(st.items or {}) do
            if it and it.name and (tonumber(it.amount) or 0) > 0 then
                pcall(function()
                    -- Prefer inventory resource exports if present
                    local done = false
                    if provider == 'qb-inventory' and exports['pfm-inventory'] and exports['pfm-inventory'].AddItem then
                        done = exports['pfm-inventory']:AddItem(tonumber(targetSource), it.name, it.amount, it.slot, it.info) == true
                        if not done then
                            done = exports['pfm-inventory']:AddItem(tonumber(targetSource), it.name, it.amount, false, it.info) == true
                        end
                    elseif provider == 'lj-inventory' and exports['lj-inventory'] and exports['lj-inventory'].AddItem then
                        done = exports['lj-inventory']:AddItem(tonumber(targetSource), it.name, it.amount, it.slot, it.info) == true
                    elseif provider == 'ps-inventory' and exports['ps-inventory'] and exports['ps-inventory'].AddItem then
                        done = exports['ps-inventory']:AddItem(tonumber(targetSource), it.name, it.amount, it.slot, it.info) == true
                    elseif provider == 'qs-inventory' and exports['qs-inventory'] and exports['qs-inventory'].AddItem then
                        done = exports['qs-inventory']:AddItem(tonumber(targetSource), it.name, it.amount, it.slot, it.info) == true
                    end

                    if not done and P.Functions and type(P.Functions.AddItem) == 'function' then
                        local ok = P.Functions.AddItem(it.name, it.amount, it.slot, it.info)
                        if ok == false then
                            P.Functions.AddItem(it.name, it.amount, nil, it.info)
                        end
                    end
                end)
                restored = restored + 1
            end
        end
    end

    StoredJailInventories[cid] = nil
    return true, restored
end

local function setActiveJail(citizenId, targetSource, minutes, bailAmount)
    if not citizenId or citizenId == '' then return end
    minutes = tonumber(minutes) or 0
    if minutes <= 0 then return end
    local sid = PendingJailSentenceIds[citizenId]
    ActiveJails[citizenId] = {
        endsAt = os.time() + (minutes * 60),
        bailAmount = tonumber(bailAmount) or 0,
        sentenceId = sid,
        targetSource = tonumber(targetSource)
    }
end

function clearActiveJail(citizenId)
    if not citizenId or citizenId == '' then return end
    ActiveJails[citizenId] = nil
    PendingJailSentenceIds[citizenId] = nil
end

-- With pfm-banking running, a fine is one keyed ledger transfer from the citizen's bank, and the
-- department deposit reuses that key, so neither can happen twice or without the other being paid.
local function ledgerRunning()
    return GetResourceState('pfm-banking') == 'started'
end

local fineCounter = 0
local function tryChargeBank(Player, amount, allowNegative, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true, nil end
    if not Player or not Player.Functions then return false, 'Player not online' end

    if ledgerRunning() and not allowNegative then
        fineCounter = fineCounter + 1
        local cid = Player.PlayerData.citizenid
        local key = ('pf-policemdt:fine:%s:%d-%d'):format(cid, os.time(), fineCounter)
        local ok, res = pcall(function()
            return exports['pfm-banking']:Transfer({
                from = ('player:%s:bank'):format(cid), to = 'system:pf-policemdt', amount = amount,
                key = key, kind = 'fine', reason = reason or 'MDT fine', actor = cid,
            })
        end)
        if ok and type(res) == 'table' and res.ok then return true, nil, key end
        if ok and type(res) == 'table' and res.error == 'insufficient_funds' then return false, 'Insufficient bank funds' end
        return false, 'Bank unavailable'
    end

    -- Scrapped negative balances: for normal payments, trust QBCore RemoveMoney.
    if (not allowNegative) then
        local current = 0
        if Player.Functions.GetMoney then
            current = tonumber(Player.Functions.GetMoney('bank')) or 0
        elseif Player.PlayerData and Player.PlayerData.money and Player.PlayerData.money.bank ~= nil then
            current = tonumber(Player.PlayerData.money.bank) or 0
        end

        if current < amount then
            return false, 'Insufficient bank funds'
        end

        if Player.Functions.RemoveMoney then
            local ok = Player.Functions.RemoveMoney('bank', amount, reason or 'pf_mdt:sentence_fine')
            if ok == false then
                return false, 'Insufficient bank funds'
            end
            return true, nil
        end

        return false, 'Unable to charge bank'
    end

    -- Allow negative (legacy/unused): attempt SetMoney; fall back to direct set + save/update

    local current = 0
    if Player.PlayerData and Player.PlayerData.money and Player.PlayerData.money.bank ~= nil then
        current = tonumber(Player.PlayerData.money.bank) or 0
    end
    local newBal = current - amount

    local okSet = false
    if Player.Functions.SetMoney then
        local ok, res = pcall(function()
            return Player.Functions.SetMoney('bank', newBal, reason or 'pf_mdt:sentence_fine')
        end)
        okSet = ok and (res ~= false)
    end

    if not okSet then
        if Player.PlayerData and Player.PlayerData.money then
            Player.PlayerData.money.bank = newBal
        end
        if Player.Functions.Save then pcall(Player.Functions.Save) end
        if Player.Functions.UpdatePlayerData then pcall(Player.Functions.UpdatePlayerData) end
    end

    return true, nil
end

local function isBillingDisabled()
    local billing = tostring((Config and Config.Billing) or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    return billing == '' or billing == 'none'
end

-- Society deposit (fine revenue)
local mgmtFundsTableExists = nil
local bankAccountsTableExists = nil
local function getFinesSocietyJobName()
    local jobName = (Config and Config.Sentencing and Config.Sentencing.FinesSocietyJob) or 'police'
    jobName = tostring(jobName or ''):gsub('^%s*(.-)%s*$', '%1')
    if jobName == '' then jobName = 'police' end
    return jobName
end

local function getBankingProvider()
    local provider = (Config and Config.Banking and Config.Banking.Provider) or 'auto'
    provider = tostring(provider or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    if provider == '' then provider = 'auto' end
    return provider
end

local function tryAddSocietyMoney(jobName, amount, key)
    if ledgerRunning() and key then
        local ok, done = pcall(function()
            return exports['pfm-banking']:AddMoney(jobName, amount, 'MDT fine', key .. ':society')
        end)
        if ok and done then return true, nil end
        return false, 'society_unavailable'
    end
    return PFMdt.Society.AddMoney(jobName, amount)
end

local function executeUnjailRcore(targetSource, skipTeleport)
    return PFMdt.Prison.Unjail(targetSource, skipTeleport)
end

-- Execute jail for the configured prison system.
-- Returns: ok:boolean, err:string|nil
local function getPrisonScript()
    local script = (Config and Config.Sentencing and Config.Sentencing.PrisonScript) or (Config and Config.Prison) or 'default'
    script = tostring(script or 'default'):lower()
    if script == 'rcore_prison' then script = 'rcore' end
    if script ~= 'rcore' then script = 'default' end
    return script
end

local function executeJailDefault(targetSource, minutes, reason)
    -- Built-in flow: strip inventory server-side, handle outfit client-side.
    local okInv, invErr = stashInventoryForBuiltInMdtJail(targetSource)
    if not okInv then
        print(('[MDT] Failed to stash/clear inventory for %s: %s'):format(tostring(targetSource), tostring(invErr)))
    end

    TriggerClientEvent('pf_mdt:client:StartMdtSentence', targetSource, {
        minutes = minutes,
        reason = reason
    })
    return true, nil
end

local function executeJail(targetSource, minutes, reason, officerSource)
    targetSource = tonumber(targetSource)
    minutes = tonumber(minutes) or 0
    reason = tostring(reason or 'MDT Sentence')

    if not targetSource or targetSource <= 0 then
        return false, 'invalid_target'
    end
    if minutes <= 0 then
        return false, 'invalid_minutes'
    end

    local prisonScript = getPrisonScript()
    
    -- Handle default jail with inventory stashing
    if prisonScript == 'default' then
        return executeJailDefault(targetSource, minutes, reason)
    end
    
    -- Use framework export for other prison systems
    return PFMdt.Prison.Jail(targetSource, minutes, reason, officerSource)
end

local function executeEditSentenceRcore(targetSource, minutes)
    return PFMdt.Prison.EditSentence(targetSource, minutes)
end

local function executeIsPrisonerRcore(targetSource)
    local isPrisoner = PFMdt.Prison.IsPrisoner(targetSource)
    return true, isPrisoner
end

local function applyPendingRcoreSentenceForSource(playerSrc)
    local prisonScript = getPrisonScript()
    if prisonScript ~= 'rcore' then return end
    if not (hasOxMySQL() and exports.oxmysql) then return end

    local P = QBCore.Functions.GetPlayer(playerSrc)
    if not P then return end
    local cid = P.PlayerData and P.PlayerData.citizenid or nil
    if not cid or cid == '' then return end

    exports.oxmysql:execute('SELECT id, minutes, reason FROM pf_mdt_pending_sentences WHERE citizenid = ? ORDER BY id ASC', { cid }, function(rows)
        if not rows or #rows == 0 then return end
        local row = rows[#rows]
        local minutes = tonumber(row.minutes) or 0
        local reason = tostring(row.reason or 'MDT Sentence')
        if minutes <= 0 then
            exports.oxmysql:execute('DELETE FROM pf_mdt_pending_sentences WHERE citizenid = ?', { cid })
            return
        end

        local okJail, jailErr = executeJail(playerSrc, minutes, reason, nil)
        if okJail then
            exports.oxmysql:execute('DELETE FROM pf_mdt_pending_sentences WHERE citizenid = ?', { cid })
        else
            print(('[MDT] Failed to apply pending rcore sentence for %s: %s'):format(cid, tostring(jailErr)))
        end
    end)
end

-- Apply pending sentences when player loads
if isESXFramework() then
    -- ESX: `esx:playerLoaded` is emitted after character is loaded.
    AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
        local src = source
        if type(playerId) == 'number' then src = playerId end
        if type(xPlayer) == 'table' and xPlayer.source then src = xPlayer.source end
        if tonumber(src) then
            applyPendingRcoreSentenceForSource(tonumber(src))
        end
    end)
else
    -- QBCore
    AddEventHandler('QBCore:Server:OnPlayerLoaded', function(player)
        local src = source
        if type(player) == 'number' then src = player end
        if type(player) == 'table' and player.PlayerData and player.PlayerData.source then src = player.PlayerData.source end
        if tonumber(src) then
            applyPendingRcoreSentenceForSource(tonumber(src))
        end
    end)

    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        local src = source
        if type(player) == 'number' then src = player end
        if type(player) == 'table' and player.PlayerData and player.PlayerData.source then src = player.PlayerData.source end
        if tonumber(src) then
            applyPendingRcoreSentenceForSource(tonumber(src))
        end
    end)
end

-- Requested server callbacks/events for UI
QBCore.Functions.CreateCallback('pf_mdt:prison:Jail', function(source, cb, data)
    local src = source
    local prisonScript = getPrisonScript()
    if prisonScript ~= 'rcore' then
        cb({ success = false, error = 'Prison system is not set to rcore' })
        return
    end

    local okPerm, permErr = isPoliceSupervisor(src)
    if not okPerm then
        cb({ success = false, error = permErr or 'Access denied' })
        return
    end

    local citizenId = tostring((data and (data.citizenid or data.citizenId)) or '')
    local minutes = tonumber(data and data.minutes) or 0
    local reason = tostring((data and data.reason) or 'MDT Sentence')
    if citizenId == '' or minutes <= 0 then
        cb({ success = false, error = 'Invalid data' })
        return
    end

    local targetSrc = ResolveSourceFromCitizenId(citizenId)
    if targetSrc then
        local okJail, jailErr = executeJail(targetSrc, minutes, reason, src)
        if not okJail then
            cb({ success = false, error = jailErr or 'Failed to jail' })
            return
        end
        cb({ success = true, applied = 'online' })
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local Officer = QBCore.Functions.GetPlayer(src)
    local officerCid, officerName = getOfficerIdentity(Officer)
    exports.oxmysql:insert(
        'INSERT INTO pf_mdt_pending_sentences (citizenid, minutes, reason, officer_citizenid, officer_name, created_at) VALUES (?, ?, ?, ?, ?, NOW())',
        { citizenId, minutes, reason, officerCid, officerName },
        function()
            cb({ success = true, applied = 'pending' })
        end
    )
end)

QBCore.Functions.CreateCallback('pf_mdt:prison:Unjail', function(source, cb, data)
    local src = source
    local prisonScript = getPrisonScript()
    if prisonScript ~= 'rcore' then
        cb({ success = false, error = 'Prison system is not set to rcore' })
        return
    end

    local okPerm, permErr = isPoliceSupervisor(src)
    if not okPerm then
        cb({ success = false, error = permErr or 'Access denied' })
        return
    end

    local citizenId = tostring((data and (data.citizenid or data.citizenId)) or '')
    local skipTeleport = (data and data.skipTeleport) == true
    if citizenId == '' then
        cb({ success = false, error = 'Invalid citizenid' })
        return
    end

    local targetSrc = ResolveSourceFromCitizenId(citizenId)
    if targetSrc then
        local okUnjail, unjailErr = executeUnjailRcore(targetSrc, skipTeleport)
        if not okUnjail then
            cb({ success = false, error = unjailErr or 'Failed to unjail' })
            return
        end
        clearActiveJail(citizenId)
        cb({ success = true, applied = 'online' })
        return
    end

    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute('DELETE FROM pf_mdt_pending_sentences WHERE citizenid = ?', { citizenId })
    end

    clearActiveJail(citizenId)
    cb({ success = true, applied = 'offline' })
end)

QBCore.Functions.CreateCallback('pf_mdt:prison:EditSentence', function(source, cb, data)
    local src = source
    local prisonScript = getPrisonScript()
    if prisonScript ~= 'rcore' then
        cb({ success = false, error = 'Prison system is not set to rcore' })
        return
    end

    local okPerm, permErr = isPoliceSupervisor(src)
    if not okPerm then
        cb({ success = false, error = permErr or 'Access denied' })
        return
    end

    local citizenId = tostring((data and (data.citizenid or data.citizenId)) or '')
    local minutes = tonumber(data and data.minutes) or 0
    if citizenId == '' or minutes < 0 then
        cb({ success = false, error = 'Invalid data' })
        return
    end

    local targetSrc = ResolveSourceFromCitizenId(citizenId)
    if not targetSrc then
        cb({ success = false, error = 'Citizen must be online to edit sentence' })
        return
    end

    local okEdit, editErr = executeEditSentenceRcore(targetSrc, minutes)
    if not okEdit then
        cb({ success = false, error = editErr or 'Failed to edit sentence' })
        return
    end
    cb({ success = true })
end)

QBCore.Functions.CreateCallback('pf_mdt:prison:IsPrisoner', function(source, cb, data)
    local prisonScript = getPrisonScript()
    if prisonScript ~= 'rcore' then
        cb({ success = false, error = 'Prison system is not set to rcore' })
        return
    end

    local citizenId = tostring((data and (data.citizenid or data.citizenId)) or '')
    if citizenId == '' then
        cb({ success = false, error = 'Invalid citizenid' })
        return
    end

    local targetSrc = ResolveSourceFromCitizenId(citizenId)
    if targetSrc then
        local okIs, resOrErr = executeIsPrisonerRcore(targetSrc)
        if not okIs then
            cb({ success = false, error = resOrErr or 'Failed to check prisoner status' })
            return
        end
        cb({ success = true, isPrisoner = (resOrErr == true) })
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = true, isPrisoner = false })
        return
    end

    exports.oxmysql:execute('SELECT id FROM pf_mdt_pending_sentences WHERE citizenid = ? LIMIT 1', { citizenId }, function(rows)
        cb({ success = true, isPrisoner = (rows and rows[1] ~= nil) })
    end)
end)

RegisterNetEvent('pf_mdt:server:mdtSentenceReleased', function()
    local src = source
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return end
    local cid = P.PlayerData and P.PlayerData.citizenid or nil
    if cid and cid ~= '' then
        -- The client sends this when its sentence timer ends; before the server's end time (and
        -- while not released by bail or unjail) it is refused, or the items came back at once.
        local jail = ActiveJails[cid]
        if jail and (tonumber(jail.endsAt) or 0) - 30 > os.time() then
            return
        end
        local st = StoredJailInventories[cid]
        local expected = st and tonumber(#(st.items or {})) or 0
        local provider = st and st.provider or getInventoryProvider()

        local okRestore, restoredOrErr = restoreInventoryForBuiltInMdtJail(src)
        if not okRestore then
            print(('[MDT] Inventory restore failed for %s: %s'):format(tostring(cid), tostring(restoredOrErr)))
            TriggerClientEvent('QBCore:Notify', src, 'MDT: Failed to restore inventory (check server console)', 'error')
        else
            local restoredCount = tonumber(restoredOrErr) or 0
            dprint(('[MDT] Restored %s item entries for %s'):format(tostring(restoredCount), tostring(cid)))
            TriggerClientEvent('QBCore:Notify', src, ('MDT: Inventory restored (%s/%s) [%s]'):format(restoredCount, expected, provider), 'success')
        end
        clearActiveJail(cid)
    end
end)

QBCore.Functions.CreateCallback('pf_mdt:getCitizenSentences', function(source, cb, data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb({ success = false, sentences = {}, error = 'Player not found' }); return end

    local jobName = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, sentences = {}, error = 'Access denied' })
        return
    end

    local citizenId = data and data.citizenId
    if not citizenId or citizenId == '' then
        cb({ success = false, sentences = {}, error = 'Invalid citizenId' })
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, sentences = {}, error = 'Database unavailable' })
        return
    end

    exports.oxmysql:execute('SELECT * FROM pf_mdt_sentences WHERE citizenId = ? ORDER BY id DESC LIMIT 200', { citizenId }, function(rows)
        local active = getActiveJail(citizenId)
        local activePayload = { active = false }
        if active then
            local rem = math.max(0, (tonumber(active.endsAt) or os.time()) - os.time())
            activePayload = {
                active = true,
                endsAt = tonumber(active.endsAt) or os.time(),
                remainingMinutes = math.max(0, math.ceil(rem / 60)),
                bailAmount = tonumber(active.bailAmount) or 0,
                sentenceId = active.sentenceId
            }
        end
        cb({ success = true, sentences = rows or {}, activeJail = activePayload })
    end)
end)

local function canReadCitation(src, row, sentenceId)
    if PFMdtAccess.IsOfficer(src) then return true end
    local P = QBCore.Functions.GetPlayer(src)
    if not P or not P.PlayerData then return false end
    if tostring(row.citizenId or '') == tostring(P.PlayerData.citizenid or '') then return true end
    for _, it in pairs(P.PlayerData.items or {}) do
        local info = type(it) == 'table' and (it.info or it.metadata) or nil
        if type(info) == 'table' and it.name == 'citation_paper' and tonumber(info.sentenceId) == sentenceId then
            return true
        end
    end
    return false
end

QBCore.Functions.CreateCallback('pf_mdt:getCitationPaperData', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local sentenceId = tonumber(data and data.sentenceId or 0)
    if not sentenceId or sentenceId <= 0 then
        cb({ success = false, error = 'Invalid sentence id' })
        return
    end

    exports.oxmysql:execute(
        'SELECT id, citizenId, citizenName, officerName, title, description, fineAmount, fineSuccess, createdAt FROM pf_mdt_sentences WHERE id = ? LIMIT 1',
        { sentenceId },
        function(rows)
            local row = rows and rows[1] or nil
            if not row then
                cb({ success = false, error = 'Sentence record not found' })
                return
            end
            -- Anyone could read any sentence record by id: only police, the sentenced citizen, or
            -- someone holding the printed citation for this sentence.
            if not canReadCitation(source, row, sentenceId) then
                cb({ success = false, error = 'no_access' })
                return
            end

            local existing = (data and type(data.citation) == 'table') and data.citation or {}
            local fineSuccess = tonumber(row.fineSuccess)
            if fineSuccess == nil then
                local raw = tostring(row.fineSuccess or ''):lower()
                if raw == 'true' or raw == 'paid' or raw == 'success' or raw == '1' then
                    fineSuccess = 1
                else
                    fineSuccess = 0
                end
            end
            local citationInfo = {
                citationUid = tostring(existing.citationUid or existing.uid or 'N/A'),
                sentenceId = sentenceId,
                citizenId = tostring(row.citizenId or existing.citizenId or ''),
                citizenName = tostring(row.citizenName or existing.citizenName or 'Unknown Citizen'),
                officerName = tostring(row.officerName or existing.officerName or 'Unknown Officer'),
                title = tostring(row.title or existing.title or 'Citation'),
                description = tostring(row.description or existing.description or ''),
                fineAmount = tonumber(row.fineAmount) or tonumber(existing.fineAmount) or 0,
                fineSuccess = fineSuccess,
                finePaid = fineSuccess == 1,
                issuedAt = tostring(row.createdAt or existing.issuedAt or os.date('%Y-%m-%d %H:%M:%S'))
            }

            cb({ success = true, citation = citationInfo })
        end
    )
end)

RegisterNetEvent('pf_mdt_dispatch:server:CreatePanicCall', function(payload)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local jobName = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not jobName or not IsAllowedJob(jobName) then
        return
    end
    if type(payload) ~= 'table' or not PFMdtAccess.AllowRate(src, 'panic', 5000) then return end

    local coords = sanitizeCoords(payload and payload.coords)
    if not coords then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local v = GetEntityCoords(ped)
            if v then
                coords = { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 }
            end
        end
    end
    if not coords then return end

    local ci = Player.PlayerData and Player.PlayerData.charinfo or {}
    local meta = Player.PlayerData and Player.PlayerData.metadata or {}
    local officerName = _trim((tostring(ci.firstname or '') .. ' ' .. tostring(ci.lastname or '')))
    if officerName == '' then officerName = 'Unknown Officer' end
    local callsign = tostring(meta.callsign or meta.mdt_callsign or ('UNIT-' .. tostring(src)))

    local locationLabel = sanitizeLabel(payload and payload.locationLabel)
    local description = _trim(PFMdtAccess.Text(payload.description, 200))
    if description == '' then
        description = 'Officer panic button activated'
    end

    CreateCall({
        callType = 'panic',
        code = '10-99',
        title = 'OFFICER PANIC',
        description = ('%s (%s): %s'):format(officerName, callsign, description),
        locationLabel = locationLabel,
        coords = coords,
        priority = 1,
        status = 'pending',
        panic = true,
        createdBy = 'panic:' .. tostring(src)
    })
end)

QBCore.Functions.CreateCallback('pf_mdt:printCitationPaper', function(source, cb, data)
    local src = source
    local Officer = QBCore.Functions.GetPlayer(src)
    if not Officer then cb({ success = false, error = 'Player not found' }); return end

    local jobName = Officer.PlayerData.job and Officer.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local sentenceId = tonumber(data and data.sentenceId or 0)
    if not sentenceId or sentenceId <= 0 then
        cb({ success = false, error = 'Invalid sentence id' })
        return
    end

    exports.oxmysql:execute(
        'SELECT id, citizenId, citizenName, officerName, title, description, fineAmount, fineSuccess, createdAt FROM pf_mdt_sentences WHERE id = ? LIMIT 1',
        { sentenceId },
        function(rows)
            local row = rows and rows[1] or nil
            if not row then
                cb({ success = false, error = 'Sentence record not found' })
                return
            end

            local fineAmount = tonumber(row.fineAmount) or 0
            if fineAmount <= 0 then
                cb({ success = false, error = 'This sentence has no payable citation to print' })
                return
            end

            local citationUid = ('CT-%s-%06d-%04d'):format(os.date('%y%m%d'), sentenceId, math.random(1000, 9999))
            local citationInfo = {
                citationUid = citationUid,
                sentenceId = sentenceId,
                citizenId = tostring(row.citizenId or ''),
                citizenName = tostring(row.citizenName or 'Unknown Citizen'),
                officerName = tostring(row.officerName or 'Unknown Officer'),
                title = tostring(row.title or 'Citation'),
                description = tostring(row.description or ''),
                fineAmount = fineAmount,
                finePaid = ((tonumber(row.fineSuccess) or ((tostring(row.fineSuccess or ''):lower() == 'true' or tostring(row.fineSuccess or '') == '1') and 1 or 0)) == 1),
                issuedAt = tostring(row.createdAt or os.date('%Y-%m-%d %H:%M:%S'))
            }

            local okAdd = Officer.Functions.AddItem('citation_paper', 1, false, citationInfo, 'pf_mdt:printCitationPaper')
            if not okAdd then
                cb({ success = false, error = 'Inventory full or citation item missing' })
                return
            end

            local sharedItem = QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items['citation_paper'] or nil
            if sharedItem then
                TriggerClientEvent('inventory:client:ItemBox', src, sharedItem, 'add')
            end

            cb({ success = true, citationUid = citationUid })
        end
    )
end)

QBCore.Functions.CreateCallback('pf_mdt:createSentence', function(source, cb, data)
    local src = source
    local Officer = QBCore.Functions.GetPlayer(src)
    if not Officer then cb({ success = false, error = 'Player not found' }); return end

    local jobName = Officer.PlayerData.job and Officer.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end

    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end

    local citizenId = (data and data.citizenId) or nil
    local citizenName = (data and data.citizenName) or nil
    local title = (data and data.title) or ''
    local description = (data and data.description) or ''
    local sentenceType = normalizeSentenceType(data and data.sentenceType)
    local chargeCodes = (data and data.charges) or {}
    local reductionKeys = (data and data.reductions) or {}

    if not citizenId or citizenId == '' then cb({ success = false, error = 'Invalid citizenId' }); return end
    title = tostring(title or '')
    if title:gsub('%s+', '') == '' then cb({ success = false, error = 'Title is required' }); return end

    if type(chargeCodes) ~= 'table' then chargeCodes = {} end
    if type(reductionKeys) ~= 'table' then reductionKeys = {} end

    -- Compute totals server-side (do not trust UI)
    local codes = {}
    local placeholders = {}
    for _, c in ipairs(chargeCodes) do
        local code = tostring(c or ''):gsub('^%s*(.-)%s*$', '%1')
        if code ~= '' and not codes[code] then
            codes[code] = true
            table.insert(placeholders, '?')
        end
    end

    local uniqueCodes = {}
    for code, _ in pairs(codes) do table.insert(uniqueCodes, code) end

    local baseFine = 0
    local baseTime = 0
    local baseBail = 0
    local chargesForSave = {}

    if #uniqueCodes > 0 then
        GetChargesSchema(function(schema)
            local fineExpr = 'fineAmount'
            local bailExpr = 'bailAmount'
            local timeExpr = 'prisonTime'
            if schema and schema.hasCamel then
                fineExpr = 'fineAmount'
                bailExpr = 'bailAmount'
                timeExpr = 'prisonTime'
            elseif schema and schema.hasLegacySnake then
                fineExpr = 'fine_amount'
                bailExpr = 'bail_amount'
                timeExpr = 'jail_time'
            end

            local sql = string.format(
                'SELECT code, name, %s AS fineAmount, %s AS bailAmount, %s AS prisonTime FROM pf_mdt_charges WHERE code IN (%s)',
                fineExpr,
                bailExpr,
                timeExpr,
                table.concat(placeholders, ',')
            )

            exports.oxmysql:execute(sql, uniqueCodes, function(rows)
                for _, row in ipairs(rows or {}) do
                    local f = tonumber(row.fineAmount) or 0
                    local b = tonumber(row.bailAmount) or 0
                    local t = tonumber(row.prisonTime) or 0
                    baseFine = baseFine + f
                    baseBail = baseBail + b
                    baseTime = baseTime + t
                    table.insert(chargesForSave, { code = row.code, name = row.name, fineAmount = f, bailAmount = b, prisonTime = t })
                end

                local reductionPercent = 0
                local reductionSave = {}
                local seenRed = {}
                for _, k in ipairs(reductionKeys) do
                    local key = tostring(k or '')
                    if key ~= '' and not seenRed[key] then
                        seenRed[key] = true
                        local pct = getReductionPercentByKey(key)
                        if pct > 0 then
                            reductionPercent = reductionPercent + pct
                            table.insert(reductionSave, { key = key, percent = pct })
                        end
                    end
                end
                if reductionPercent > 100 then reductionPercent = 100 end

                local timeBefore = baseTime
                local timeAfter = math.floor(timeBefore * (1.0 - (reductionPercent / 100.0)))
                if timeAfter < 0 then timeAfter = 0 end

                local fineToCharge = 0
                local timeToServe = 0
                local bailToPost = 0
                if sentenceType == 'fine' then
                    fineToCharge = baseFine
                    timeToServe = 0
                    bailToPost = 0
                elseif sentenceType == 'sentence' then
                    fineToCharge = 0
                    timeToServe = timeAfter
                    bailToPost = baseBail
                else
                    fineToCharge = baseFine
                    timeToServe = timeAfter
                    bailToPost = baseBail
                end

                local prisonScript = getPrisonScript()
                local Target = getOnlinePlayerByCitizenId(citizenId)

            -- For rcore: allow offline jail-only sentences by inserting a pending row.
                local isOfflinePending = false
                if not Target then
                    if prisonScript == 'rcore' and timeToServe > 0 and fineToCharge <= 0 then
                        isOfflinePending = true
                    else
                        cb({ success = false, error = 'Citizen must be online to sentence' })
                        return
                    end
                end

                local officerCid, officerName = getOfficerIdentity(Officer)
                local allowNeg = (Config and Config.Sentencing and Config.Sentencing.AllowNegativeBank) == true

                local executed = 0
                local fineSuccess = 0
                local jailSuccess = 0
                local err = nil

                -- Execute fine first if needed (requires online target)
                if fineToCharge > 0 then
                    if not Target then
                        cb({ success = false, error = 'Citizen must be online to pay fines' })
                        return
                    end
                    local okFine = false
                    local fineErr = nil
                    local fineKey = nil

                    if isBillingDisabled() then
                        okFine, fineErr, fineKey = tryChargeBank(Target, fineToCharge, allowNeg, 'pf_mdt:sentence_fine')
                    else
                        okFine = PFMdt.Billing.SendFine(Target.PlayerData.source, fineToCharge, 'pf_mdt:sentence_fine')
                        if not okFine then
                            -- Billing provider failed/declined; fall back to direct bank charge.
                            okFine, fineErr, fineKey = tryChargeBank(Target, fineToCharge, allowNeg, 'pf_mdt:sentence_fine')
                        end
                    end

                    if not okFine then
                        err = fineErr or 'Payment was declined'
                        TriggerClientEvent('QBCore:Notify', src, 'Payment was declined', 'error')
                    else
                        fineSuccess = 1

                        -- Deposit fine into society (police by default)
                        if Config and Config.Sentencing and Config.Sentencing.FinesToSociety ~= false then
                            local socJob = getFinesSocietyJobName()
                            local okSoc, socErr = tryAddSocietyMoney(socJob, fineToCharge, fineKey)
                            if not okSoc then
                                print(('[MDT] Fine paid but society deposit failed (job=%s amount=%s): %s'):format(
                                    tostring(socJob), tostring(fineToCharge), tostring(socErr)
                                ))
                            end
                        end
                    end
                end

                -- For fine+sentence: only jail if fine succeeded
                if err == nil and timeToServe > 0 then
                    if isOfflinePending then
                        exports.oxmysql:insert(
                            'INSERT INTO pf_mdt_pending_sentences (citizenid, minutes, reason, officer_citizenid, officer_name, created_at) VALUES (?, ?, ?, ?, ?, NOW())',
                            { citizenId, timeToServe, title, officerCid, officerName },
                            function() end
                        )
                        jailSuccess = 0
                    else
                        local function doJail()
                            if prisonScript == 'rcore' then
                                local okPerm, permErr = isPoliceSupervisor(src)
                                if not okPerm then
                                    err = permErr or 'Access denied'
                                    return
                                end
                            end

                            local okJail, jailErr = executeJail(Target.PlayerData.source, timeToServe, title, src)
                            if not okJail then
                                err = jailErr or 'Failed to jail'
                            else
                                jailSuccess = 1
                                setActiveJail(citizenId, Target.PlayerData.source, timeToServe, bailToPost)
                            end
                        end

                        if sentenceType == 'fine+sentence' and fineToCharge > 0 then
                            SetTimeout(2000, doJail)
                        else
                            doJail()
                        end
                    end
                elseif err == nil and timeToServe == 0 then
                    jailSuccess = 1
                end

                executed = isOfflinePending and 0 or 1

                exports.oxmysql:execute(
                    "SELECT COUNT(*) AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pf_mdt_sentences' AND COLUMN_NAME = 'bailAmount'",
                    {},
                    function(colRows)
                        local hasBailCol = false
                        if colRows and colRows[1] and tonumber(colRows[1].c) and tonumber(colRows[1].c) > 0 then
                            hasBailCol = true
                        end

                        local insertSql
                        local params
                        if hasBailCol then
                            insertSql = [[
                                INSERT INTO pf_mdt_sentences
                                    (citizenId, citizenName, officerCitizenId, officerName, title, description, sentenceType, charges, reductions,
                                     fineAmount, prisonTime, prisonTimeBeforeReduction, prisonTimeAfterReduction, reductionPercent,
                                     executed, fineSuccess, jailSuccess, error,
                                     bailAmount)
                                VALUES
                                    (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ]]
                            params = {
                                citizenId,
                                citizenName,
                                officerCid,
                                officerName,
                                title,
                                description,
                                sentenceType,
                                json.encode(chargesForSave),
                                json.encode(reductionSave),
                                fineToCharge,
                                timeToServe,
                                timeBefore,
                                timeAfter,
                                reductionPercent,
                                executed,
                                fineSuccess,
                                jailSuccess,
                                err,
                                bailToPost
                            }
                        else
                            insertSql = [[
                                INSERT INTO pf_mdt_sentences
                                    (citizenId, citizenName, officerCitizenId, officerName, title, description, sentenceType, charges, reductions,
                                     fineAmount, prisonTime, prisonTimeBeforeReduction, prisonTimeAfterReduction, reductionPercent,
                                     executed, fineSuccess, jailSuccess, error)
                                VALUES
                                    (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ]]
                            params = {
                                citizenId,
                                citizenName,
                                officerCid,
                                officerName,
                                title,
                                description,
                                sentenceType,
                                json.encode(chargesForSave),
                                json.encode(reductionSave),
                                fineToCharge,
                                timeToServe,
                                timeBefore,
                                timeAfter,
                                reductionPercent,
                                executed,
                                fineSuccess,
                                jailSuccess,
                                err
                            }
                        end

                        exports.oxmysql:insert(insertSql, params, function(insertId)
                            PendingJailSentenceIds[citizenId] = insertId
                            if insertId and err == nil then
                                -- a carried-out sentence on record: public court facts for the newsroom
                                local ci = Target and Target.PlayerData and Target.PlayerData.charinfo or nil
                                local name = ci and PublicText((ci.firstname or '') .. ' ' .. (ci.lastname or ''), 60) or PublicText(citizenName, 60) or 'A defendant'
                                local summary = timeToServe > 0 and ('%s sentenced to %d months'):format(name, timeToServe)
                                    or ('%s fined $%d'):format(name, math.floor(fineToCharge))
                                CityEvent('police.sentenced', {
                                    name = name, months = timeToServe, fine = math.floor(fineToCharge), sentenceType = sentenceType,
                                    charges = PublicCharges(chargesForSave), place = timeToServe > 0 and 'Bolingbroke Penitentiary' or nil, by = 'mdt',
                                }, { title = summary, actor = officerCid, dedupe = 'sentence:' .. tostring(insertId) })
                            end

                            local active = getActiveJail(citizenId)
                            if active and not active.sentenceId then
                                active.sentenceId = insertId
                                ActiveJails[citizenId] = active
                            end

                            if err ~= nil then
                                cb({ success = false, error = err, id = insertId })
                            else
                                cb({ success = true, id = insertId })
                            end
                        end)
                    end
                )
            end)
        end)
    else
        cb({ success = false, error = 'At least one charge must be selected' })
    end
end)

QBCore.Functions.CreateCallback('pf_mdt:postBail', function(source, cb, data)
    local src = source
    local Officer = QBCore.Functions.GetPlayer(src)
    if not Officer then cb({ success = false, error = 'Player not found' }); return end

    local jobName = Officer.PlayerData.job and Officer.PlayerData.job.name or nil
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end

    local prisonerCitizenId = data and data.prisonerCitizenId or nil
    local payerCitizenId = data and data.payerCitizenId or nil
    if not prisonerCitizenId or prisonerCitizenId == '' then cb({ success = false, error = 'Invalid prisonerCitizenId' }); return end
    if not payerCitizenId or payerCitizenId == '' then cb({ success = false, error = 'Select a payer' }); return end

    local st = getActiveJail(prisonerCitizenId)
    if not st then
        cb({ success = false, error = 'Citizen is not currently sentenced' })
        return
    end

    local bailAmount = tonumber(st.bailAmount) or 0
    if bailAmount <= 0 then
        cb({ success = false, error = 'No bail amount for this sentence' })
        return
    end

    local Prisoner = getOnlinePlayerByCitizenId(prisonerCitizenId)
    if not Prisoner then
        cb({ success = false, error = 'Prisoner must be online to release' })
        return
    end

    local Payer = getOnlinePlayerByCitizenId(payerCitizenId)
    if not Payer then
        cb({ success = false, error = 'Selected payer must be online' })
        return
    end

    local allowNeg = false
    local okPay = PFMdt.Billing.SendInvoice(Payer.PlayerData.source, bailAmount, 'pf_mdt:sentence_bail', 'police')
    if not okPay then
        TriggerClientEvent('QBCore:Notify', src, 'Payment was declined', 'error')
        cb({ success = false, error = 'Payment was declined' })
        return
    end

    local prisonScript = getPrisonScript()
    if prisonScript == 'rcore' then
        local okUnjail, unjailErr = executeUnjailRcore(Prisoner.PlayerData.source, false)
        if not okUnjail then
            cb({ success = false, error = unjailErr or 'Failed to unjail' })
            return
        end
    else
        TriggerClientEvent('pf_mdt:client:ReleaseMdtSentence', Prisoner.PlayerData.source)
    end

    -- Persist bail if we can
    local sentenceId = st.sentenceId
    if sentenceId and hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute(
            "SELECT COUNT(*) AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pf_mdt_sentences' AND COLUMN_NAME = 'bailed'",
            {},
            function(colRows)
                local okCols = false
                if colRows and colRows[1] and tonumber(colRows[1].c) and tonumber(colRows[1].c) > 0 then
                    okCols = true
                end
                if not okCols then return end

                local ci = Payer.PlayerData and Payer.PlayerData.charinfo or {}
                local payerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
                exports.oxmysql:execute(
                    'UPDATE pf_mdt_sentences SET bailed = 1, bailPaidByCitizenId = ?, bailPaidByName = ?, bailPaidAt = NOW() WHERE id = ?',
                    { payerCitizenId, (payerName ~= '' and payerName or payerCitizenId), sentenceId }
                )
            end
        )
    end

    clearActiveJail(prisonerCitizenId)
    cb({ success = true })
end)

-- Get all incidents for dropdown
QBCore.Functions.CreateCallback('pf_mdt:getAllIncidents', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end
    
    -- NOTE: Used for dropdown pickers (incidents + vehicle reports). Keep this high enough to cover "all" incidents on typical servers.
    exports.oxmysql:execute('SELECT incidentId, title FROM pf_mdt_incidents ORDER BY id DESC LIMIT 5000', {}, function(rows)
        cb(rows or {})
    end)
end)

-- Get all evidence for dropdown pickers (vehicle reports, incident linking, etc.)
QBCore.Functions.CreateCallback('pf_mdt:getAllEvidence', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({})
        return
    end

    -- Keep payload reasonable; evidence pages are paginated, but pickers need a unified list.
    exports.oxmysql:execute('SELECT evidence_number, evidence_id, title, tags, created_at FROM pf_mdt_evidence ORDER BY created_at DESC LIMIT 5000', {}, function(rows)
        cb(rows or {})
    end)
end)

-- Create new evidence
QBCore.Functions.CreateCallback('pf_mdt:createEvidence', function(source, cb, data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then 
        cb({ success = false, error = 'Player not found' })
        return 
    end
    
    local jobName, gradeLevel = GetPlayerJob(src)
    if not IsAllowedJob(jobName) then
        cb({ success = false, error = 'Access denied' })
        return
    end
    
    -- Check minimum grade for evidence creation
    if gradeLevel < (Config.Evidence and Config.Evidence.MinGradeCreate or 0) then
        cb({ success = false, error = 'Insufficient rank to create evidence' })
        return
    end
    
    local title = data.title or 'Untitled Evidence'
    local description = data.description or ''
    local imageUrl = data.imageUrl
    local tags = data.tags or ''
    local locationDetails = data.locationDetails or ''
    local incidentId = data.incidentId or nil
    local status = data.status or 'Collected'
    local citizensInvolved = data.citizensInvolved and json.encode(data.citizensInvolved) or nil
    local vehiclesInvolved = data.vehiclesInvolved and json.encode(data.vehiclesInvolved) or nil
    local weaponsInvolved = data.weaponsInvolved or ''
    local relatedCharges = data.relatedCharges and json.encode(data.relatedCharges) or nil
    
    if not imageUrl then
        cb({ success = false, error = 'Evidence photo is required' })
        return
    end
    
    if not (hasOxMySQL() and exports.oxmysql) then
        cb({ success = false, error = 'Database unavailable' })
        return
    end
    
    local charinfo = Player.PlayerData.charinfo or {}
    local creatorName = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    if creatorName == '' then creatorName = 'Officer' end
    
    -- Get the next evidence number
    exports.oxmysql:scalar('SELECT COALESCE(MAX(evidence_number), 0) + 1 FROM pf_mdt_evidence', {}, function(evidenceNumber)
        local evidenceId = GenerateEvidenceId()
        
        exports.oxmysql:insert([[
            INSERT INTO pf_mdt_evidence 
            (evidence_id, evidence_number, title, description, image_url, tags, location_details, incident_id, 
             citizens_involved, vehicles_involved, weapons_involved, related_charges, status, 
             created_by_citizenid, created_by_name) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]],
        { evidenceId, evidenceNumber, title, description, imageUrl, tags, locationDetails, incidentId,
          citizensInvolved, vehiclesInvolved, weaponsInvolved, relatedCharges, status,
          Player.PlayerData.citizenid, creatorName },
        function(insertId)
            if insertId then
                cb({ success = true, evidenceId = evidenceId, evidenceNumber = evidenceNumber })
            else
                cb({ success = false, error = 'Failed to create evidence' })
            end
        end)
    end)
end)

-- Delete evidence (supervisors only)
RegisterNetEvent('pf_mdt:server:DeleteEvidence', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local jobName, gradeLevel = GetPlayerJob(src)
    if not IsSupervisor(jobName, gradeLevel) then
        TriggerClientEvent('QBCore:Notify', src, 'Only supervisors can delete evidence', 'error')
        return
    end
    
    local evidenceId = data and data.evidenceId
    if not evidenceId then return end
    
    if not (hasOxMySQL() and exports.oxmysql) then return end
    
    exports.oxmysql:execute('DELETE FROM pf_mdt_evidence WHERE evidence_id = ?', { evidenceId }, function(affected)
        local changed = affected
        if type(changed) == 'table' then
            changed = changed.affectedRows or changed.changedRows or 0
        end
        changed = tonumber(changed) or 0
        if changed > 0 then
            TriggerClientEvent('QBCore:Notify', src, 'Evidence deleted', 'success')
            TriggerClientEvent('pf_mdt:client:RefreshEvidence', src)
        else
            TriggerClientEvent('QBCore:Notify', src, 'Failed to delete evidence', 'error')
        end
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:getIncident', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then return cb({ success = false, error = 'no_db' }) end
    local incidentId = data and (data.incidentId or data.id) or nil
    if not incidentId then return cb({ success = false, error = 'missing_id' }) end

    local sql = 'SELECT incidentId as id, title, priority, status, reportingOfficer, location, narrative, involvedCitizens, involvedVictims, involvedOfficers, involvedCitizenIds, involvedVictimIds, involvedOfficerIds, involvedVehicles, involvedVehicleIds, charges, evidence_ids, dateTime, createdAt FROM pf_mdt_incidents WHERE incidentId = ? LIMIT 1'
    exports.oxmysql:execute(sql, { incidentId }, function(rows)
        local r = rows and rows[1] or nil
        if not r then return cb({ success = false, error = 'not_found' }) end

        local function decodeMaybe(v)
            if type(v) == 'string' then
                local ok, out = pcall(json.decode, v)
                if ok then return out end
            end
            return v or {}
        end

        cb({
            success = true,
            incident = {
                id = r.id,
                title = r.title,
                priority = r.priority,
                status = r.status,
                reportingOfficer = r.reportingOfficer,
                location = r.location,
                narrative = r.narrative,
                involvedCitizens = decodeMaybe(r.involvedCitizens),
                involvedVictims = decodeMaybe(r.involvedVictims),
                involvedOfficers = decodeMaybe(r.involvedOfficers),
                involvedVehicles = decodeMaybe(r.involvedVehicles),
                charges = decodeMaybe(r.charges),
                evidence_ids = decodeMaybe(r.evidence_ids),
                dateTime = r.dateTime,
                createdAt = r.createdAt
            }
        })
    end)
end)

-- ============================================================================
-- Templates
-- ============================================================================

local function getTemplateUserContext(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData then return nil end
    local charinfo = Player.PlayerData.charinfo or {}
    local name = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    local job = Player.PlayerData.job or {}
    return {
        citizenid = Player.PlayerData.citizenid,
        name = name ~= '' and name or 'Officer',
        job = job.name or 'police',
        grade = (job.grade and job.grade.level) or 0
    }
end

local function templateHasAccess(tpl, ctx)
    if not tpl or not ctx then return false end
    local vis = tostring(tpl.visibility or 'private')
    if vis == 'public' then return true end
    if vis == 'private' then return tpl.author_cid == ctx.citizenid end
    if vis == 'grades' then
        local grades = tpl.allowed_grades or {}
        for _, g in ipairs(grades) do
            if tonumber(g) == tonumber(ctx.grade) then return true end
        end
        return tpl.author_cid == ctx.citizenid
    end
    if vis == 'officers' then
        local officers = tpl.allowed_officers or {}
        for _, cid in ipairs(officers) do
            if tostring(cid) == tostring(ctx.citizenid) then return true end
        end
        return tpl.author_cid == ctx.citizenid
    end
    return tpl.author_cid == ctx.citizenid
end

QBCore.Functions.CreateCallback('pf_mdt:getTemplates', function(source, cb)
    if not (hasOxMySQL() and exports.oxmysql) then return cb({ success = false, error = 'no_db' }) end
    local ctx = getTemplateUserContext(source)
    if not ctx then return cb({ success = false, error = 'no_player' }) end

    exports.oxmysql:execute('SELECT * FROM pf_mdt_templates ORDER BY updated_at DESC', {}, function(rows)
        local out = {}
        for _, r in ipairs(rows or {}) do
            local okG, grades = pcall(json.decode, r.allowed_grades or '[]')
            if not okG then grades = {} end
            local okO, officers = pcall(json.decode, r.allowed_officers or '[]')
            if not okO then officers = {} end
            local tpl = {
                id = r.id,
                title = r.title,
                body_html = r.body_html,
                visibility = r.visibility,
                allowed_grades = grades,
                allowed_officers = officers,
                author_cid = r.author_cid,
                author_name = r.author_name,
                created_at = r.created_at,
                updated_at = r.updated_at
            }
            if templateHasAccess(tpl, ctx) then table.insert(out, tpl) end
        end
        cb({ success = true, templates = out })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:createTemplate', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then return cb({ success = false, error = 'no_db' }) end
    local ctx = getTemplateUserContext(source)
    if not ctx then return cb({ success = false, error = 'no_player' }) end

    local title = tostring(data and data.title or '')
    local body = tostring(data and data.body_html or '')
    if title == '' or body == '' then return cb({ success = false, error = 'missing_fields' }) end

    local visibility = tostring(data and data.visibility or 'private')
    local allowedGrades = data and data.allowed_grades or {}
    local allowedOfficers = data and data.allowed_officers or {}

    exports.oxmysql:insert('INSERT INTO pf_mdt_templates (title, body_html, visibility, allowed_grades, allowed_officers, author_cid, author_name) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        title,
        body,
        visibility,
        json.encode(allowedGrades or {}),
        json.encode(allowedOfficers or {}),
        ctx.citizenid,
        ctx.name
    }, function(id)
        cb({ success = true, id = id })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:updateTemplate', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then return cb({ success = false, error = 'no_db' }) end
    local ctx = getTemplateUserContext(source)
    if not ctx then return cb({ success = false, error = 'no_player' }) end

    local id = tonumber(data and data.id or 0)
    if id <= 0 then return cb({ success = false, error = 'missing_id' }) end

    exports.oxmysql:execute('SELECT author_cid FROM pf_mdt_templates WHERE id = ? LIMIT 1', { id }, function(rows)
        local owner = rows and rows[1] and rows[1].author_cid or nil
        if not owner then return cb({ success = false, error = 'not_found' }) end
        if tostring(owner) ~= tostring(ctx.citizenid) then return cb({ success = false, error = 'no_access' }) end

        local title = tostring(data and data.title or '')
        local body = tostring(data and data.body_html or '')
        if title == '' or body == '' then return cb({ success = false, error = 'missing_fields' }) end

        local visibility = tostring(data and data.visibility or 'private')
        local allowedGrades = data and data.allowed_grades or {}
        local allowedOfficers = data and data.allowed_officers or {}

        exports.oxmysql:execute('UPDATE pf_mdt_templates SET title = ?, body_html = ?, visibility = ?, allowed_grades = ?, allowed_officers = ? WHERE id = ?', {
            title,
            body,
            visibility,
            json.encode(allowedGrades or {}),
            json.encode(allowedOfficers or {}),
            id
        }, function()
            cb({ success = true })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:deleteTemplate', function(source, cb, data)
    if not (hasOxMySQL() and exports.oxmysql) then return cb({ success = false, error = 'no_db' }) end
    local ctx = getTemplateUserContext(source)
    if not ctx then return cb({ success = false, error = 'no_player' }) end
    local id = tonumber(data and data.id or 0)
    if id <= 0 then return cb({ success = false, error = 'missing_id' }) end

    exports.oxmysql:execute('SELECT author_cid FROM pf_mdt_templates WHERE id = ? LIMIT 1', { id }, function(rows)
        local owner = rows and rows[1] and rows[1].author_cid or nil
        if not owner then return cb({ success = false, error = 'not_found' }) end
        if tostring(owner) ~= tostring(ctx.citizenid) then return cb({ success = false, error = 'no_access' }) end

        exports.oxmysql:execute('DELETE FROM pf_mdt_templates WHERE id = ?', { id }, function()
            cb({ success = true })
        end)
    end)
end)

-- ============================================================================
-- CCTV Callbacks (proxy to cctv.lua)
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mdt:cctv:getCameraList', function(source, cb)
    -- Forward to CCTV system
    if exports['pf-policemdt'] then
        -- The actual implementation is in server/cctv.lua
        -- This is just a safety net if needed
    end
    cb({})
end)

QBCore.Functions.CreateCallback('pf_mdt:cctv:getCameraRecordings', function(source, cb, cameraKey)
    cb({})
end)

-- ============================================================================
-- Dashboard: Chat System
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mdt:sendChatMessage', function(source, cb, message)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ success = false, error = 'Player not found' })
        return
    end
    
    if not message or type(message) ~= 'string' or #message < 1 or #message > 200 then
        cb({ success = false, error = 'Invalid message' })
        return
    end
    
    if not IsAllowedJob(Player.PlayerData.job.name) then
        cb({ success = false, error = 'Access denied' })
        return
    end
    
    -- Store message in memory
    local msg = {
        id = #ChatMessages + 1,
        officer_name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        message = message,
        timestamp = os.time()
    }
    
    table.insert(ChatMessages, msg)
    
    -- Keep only last 100 messages in memory
    if #ChatMessages > 100 then
        table.remove(ChatMessages, 1)
    end
    
    -- Broadcast to all police officers
    local Players = QBCore.Functions.GetQBPlayers()
    for _, P in pairs(Players) do
        if IsAllowedJob(P.PlayerData.job.name) then
            TriggerClientEvent('pf_mdt:client:ChatMessage', P.PlayerData.source, {
                action = 'chatMessage',
                name = msg.officer_name,
                message = msg.message
            })
        end
    end
    
    -- Save to database
    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:insert(
            'INSERT INTO pf_mdt_chat (officer_name, message, created_at) VALUES (?, ?, NOW())',
            { msg.officer_name, msg.message },
            function() end
        )
    end
    
    cb({ success = true })
end)

-- ============================================================================
-- Dashboard: Status & Callsign Management
-- ============================================================================

RegisterServerEvent('pf_mdt:updatePlayerStatus')
AddEventHandler('pf_mdt:updatePlayerStatus', function(payload)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not IsAllowedJob(Player.PlayerData.job.name) then return end
    
    local cid = Player.PlayerData.citizenid
    local meta = Player.PlayerData.metadata or {}

    local function normalizeKey(v)
        local s = tostring(v or ''):lower():gsub('^%s*(.-)%s*$', '%1')
        if s == 'onmission' then s = 'on_mission' end
        if s == 'onduty' then s = 'on_duty' end
        if s == 'offduty' then s = 'off_duty' end
        return s
    end

    local validDuty = { on_duty = true, off_duty = true }
    local validStatus = { available = true, unavailable = true, busy = true, on_mission = true }

    local changed = nil
    local duty = nil
    local status = nil

    if type(payload) == 'table' then
        changed = normalizeKey(payload.changed)
        duty = normalizeKey(payload.duty)
        status = normalizeKey(payload.status)
    else
        -- Backwards compat: single string
        local one = normalizeKey(payload)
        if validDuty[one] then duty = one else status = one end
    end

    if (changed == 'duty' or changed == nil) and duty and validDuty[duty] then
        PlayerDuties[cid] = duty
        if Player.Functions and Player.Functions.SetMetaData then
            Player.Functions.SetMetaData('mdt_duty', duty)
        end
    end

    if (changed == 'status' or changed == nil) and status and validStatus[status] then
        PlayerStatuses[cid] = status
        if Player.Functions and Player.Functions.SetMetaData then
            Player.Functions.SetMetaData('mdt_status', status)
        end
    end

    local finalDuty = normalizeKey(meta.mdt_duty or PlayerDuties[cid] or ((Player.PlayerData.job and Player.PlayerData.job.onduty) and 'on_duty' or 'off_duty'))
    if not validDuty[finalDuty] then finalDuty = 'on_duty' end
    local finalStatus = normalizeKey(meta.mdt_status or PlayerStatuses[cid] or 'available')
    if not validStatus[finalStatus] then finalStatus = 'available' end

    TriggerClientEvent('pf_mdt:client:UpdatePersonalInfo', src, {
        action = 'setPersonalInfo',
        duty = finalDuty,
        status = finalStatus
    })
    
    -- Broadcast status change to all officers
    broadcastUnitsUpdate()
end)

RegisterServerEvent('pf_mdt:updatePlayerCallsign')
AddEventHandler('pf_mdt:updatePlayerCallsign', function(newCallsign)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not IsAllowedJob(Player.PlayerData.job.name) then return end
    
    if not newCallsign or type(newCallsign) ~= 'string' or #newCallsign < 1 or #newCallsign > 10 then
        return
    end
    
    PlayerCallsigns[Player.PlayerData.citizenid] = newCallsign
    
    -- Update NUI
    TriggerClientEvent('pf_mdt:client:UpdatePersonalInfo', src, {
        action = 'setPersonalInfo',
        callsign = newCallsign
    })
    
    -- Broadcast callsign change to all officers
    broadcastUnitsUpdate()
end)

-- Daily chat wipe (runs every 24 hours)
local function wipeOldChatMessages()
    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute(
            'DELETE FROM pf_mdt_chat WHERE created_at < DATE_SUB(NOW(), INTERVAL 1 DAY)',
            {},
            function() end
        )
    end
    ChatMessages = {} -- Clear in-memory cache
end

SetTimeout(1000, function()
    -- Run daily wipe at startup
    wipeOldChatMessages()

    -- Schedule it to run every 24 hours (86400000 ms)
    CreateThread(function()
        while true do
            Wait(86400000)
            wipeOldChatMessages()
        end
    end)
end)

-- ============================================================================
-- Get Personal Info for Dashboard
-- ============================================================================

QBCore.Functions.CreateCallback('pf_mdt:getPersonalInfo', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ success = false })
        return
    end
    
    if not IsAllowedJob(Player.PlayerData.job.name) then
        cb({ success = false })
        return
    end
    
    local cid = Player.PlayerData.citizenid
    local charinfo = Player.PlayerData.charinfo or {}
    local name = (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')
    
    local meta = Player.PlayerData.metadata or {}
    local duty = tostring(meta.mdt_duty or PlayerDuties[cid] or ((Player.PlayerData.job and Player.PlayerData.job.onduty) and 'on_duty' or 'off_duty'))
    local status = tostring(meta.mdt_status or PlayerStatuses[cid] or 'available')

    cb({
        success = true,
        name = name:gsub('^%s*(.-)%s*$', '%1'),
        job = Player.PlayerData.job.label or 'Officer',
        grade = Player.PlayerData.job.grade.label or 'Officer',
        callsign = PlayerCallsigns[cid] or ('UNIT-' .. (cid or ''):sub(1, 4)),
        duty = duty,
        status = status
    })
end)
