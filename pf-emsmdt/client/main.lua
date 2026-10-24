local QBCore = PFMdt.GetCore()

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end

-- State
local isUIOpen = false
local isOpening = false
local lastUpdateTime = 0
local updateThrottle = 1000 -- ms

-- Vehicle freeze prevention
local vehicleBeforeOpen = nil

-- Helper Functions

local function GetVehicleLabelFromModel(model)
    if not model then return nil end

    local hash = model
    if type(model) ~= 'number' then
        if type(model) == 'string' then
            local s = model:gsub('^%s*(.-)%s*$', '%1')
            if s:lower():sub(1, 2) == '0x' then
                hash = tonumber(s)
            else
                local n = tonumber(s)
                if n ~= nil then
                    hash = n
                else
                    hash = joaat(s)
                end
            end
        else
            hash = joaat(tostring(model))
        end
    end

    if type(hash) == 'number' then
        hash = math.floor(hash)
        -- Some DBs store hashes as signed 32-bit ints; GTA natives expect unsigned.
        if hash < 0 then
            hash = hash + 4294967296
        end
        if hash > 4294967295 then
            hash = hash % 4294967296
        end
    end

    local disp = GetDisplayNameFromVehicleModel(hash)
    if not disp or disp == '' or disp == 'CARNOTFOUND' then
        return type(model) == 'string' and model or tostring(model)
    end

    local label = GetLabelText(disp)
    if label and label ~= '' and label ~= 'NULL' then
        return label
    end

    return disp
end

local function _isHashLikeString(val)
    local s = tostring(val or ''):gsub('^%s*(.-)%s*$', '%1')
    if s == '' then return false end
    if s:lower():match('^0x[%da-f]+$') then return true end
    if s:match('^[%+%-]?%d+%.?0*$') then return true end
    return false
end

local function _isUnknownModelLabel(label)
    local s = tostring(label or ''):gsub('^%s*(.-)%s*$', '%1')
    if s == '' then return true end
    if s == 'NULL' then return true end
    local lower = s:lower()
    if lower:find('unknown model', 1, true) == 1 then return true end
    if lower == 'vehicle' then return true end
    if _isHashLikeString(s) then return true end
    return false
end

local function IsAllowedJob()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    return Config.AllowedJobs[PlayerData.job.name] == true
end

local function GetPlayerPermissions()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then 
        return { allowed = false, isSupervisor = false, isOwner = false }
    end
    local jobName = PlayerData.job.name
    local gradeLevel = (PlayerData.job.grade and PlayerData.job.grade.level) or 0
    local meta = PlayerData.metadata or {}
    local isOwnerFlag = meta.isOwner == true or meta.isowner == true or meta.owner == true
    
    return {
        allowed = Config.AllowedJobs[jobName] == true,
        isSupervisor = Config.SupervisorGrades[jobName] and Config.SupervisorGrades[jobName][gradeLevel] == true,
        isOwner = isOwnerFlag
    }
end

-- Location Helpers

local function GetZoneLabelAtCoord(x, y, z)
    local zone = GetNameOfZone(x, y, z)
    if not zone then return nil end
    local label = GetLabelText(zone)
    if not label or label == "NULL" then
        return zone
    end
    return label
end

local function ComputeLocationLabel(coords)
    if not coords then return nil end
    local x, y, z = coords.x or 0.0, coords.y or 0.0, coords.z or 0.0
    local streetHash, crossHash = GetStreetNameAtCoord(x, y, z)
    local street = (streetHash and streetHash ~= 0) and GetStreetNameFromHashKey(streetHash) or nil
    local cross = (crossHash and crossHash ~= 0) and GetStreetNameFromHashKey(crossHash) or nil
    local zoneLabel = GetZoneLabelAtCoord(x, y, z)

    if street and cross and zoneLabel then
        return string.format("%s & %s, %s", street, cross, zoneLabel)
    elseif street and zoneLabel then
        return string.format("%s, %s", street, zoneLabel)
    elseif street then
        return street
    elseif zoneLabel then
        return zoneLabel
    else
        return nil
    end
end
-- Try to derive a street from the nearest vehicle nodes if direct lookup fails
local function ComputeNearestRoadLabel(coords)
    if not coords then return nil end
    local x, y, z = coords.x or 0.0, coords.y or 0.0, coords.z or 0.0
    -- Search the first few closest vehicle nodes
    for n = 1, 5 do
        local nodeX, nodeY, nodeZ = GetNthClosestVehicleNode(x, y, z, n, 0.0, 0.0, 0.0)
        if nodeX and nodeY then
            local sHash, cHash = GetStreetNameAtCoord(nodeX, nodeY, nodeZ or z)
            local sName = (sHash and sHash ~= 0) and GetStreetNameFromHashKey(sHash) or nil
            local cName = (cHash and cHash ~= 0) and GetStreetNameFromHashKey(cHash) or nil
            local zoneLabel = GetZoneLabelAtCoord(nodeX, nodeY, nodeZ or z)
            if sName and cName and zoneLabel then
                return string.format("%s & %s, %s", sName, cName, zoneLabel)
            elseif sName and zoneLabel then
                return string.format("%s, %s", sName, zoneLabel)
            elseif sName then
                return sName
            end
        end
    end
    return nil
end

local function GetAreaLabelFromBounds(coords)
    if not coords or not Config.LocationAreas then return nil end
    for _, area in ipairs(Config.LocationAreas) do
        if coords.x >= area.minX and coords.x <= area.maxX and coords.y >= area.minY and coords.y <= area.maxY then
            return area.label
        end
    end
    return nil
end

local function EnrichCallsWithLocation(calls)
    if not calls or type(calls) ~= "table" then return calls end

    local function normalizeCoords(c)
        if not c then return nil end
        if type(c) ~= 'table' then
            local x = tonumber(c.x)
            local y = tonumber(c.y)
            local z = tonumber(c.z)
            if x and y and z then
                return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
            end
            return nil
        end
        local x = tonumber(c.x) or tonumber(c[1])
        local y = tonumber(c.y) or tonumber(c[2])
        local z = tonumber(c.z) or tonumber(c[3])
        if not x or not y or not z then return nil end
        return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
    end

    -- Support both array-like lists and map-like tables
    for key, call in pairs(calls) do
        if call and type(call) == "table" and call.coords then
            call.coords = normalizeCoords(call.coords) or call.coords
            local label = ComputeLocationLabel(call.coords)
            if not label then
                label = ComputeNearestRoadLabel(call.coords)
            end
            if not label or label == "" then
                -- Fallback to zone or generic string to avoid raw coords in UI
                local zlabel = GetZoneLabelAtCoord(call.coords.x or 0.0, call.coords.y or 0.0, call.coords.z or 0.0)
                label = zlabel or GetAreaLabelFromBounds(call.coords) or "Unknown Area"
            end
            call.locationLabel = label
        end
    end
    return calls
end

-- UI Functions

local function TryLoadLocaleFile(lang)
    if not lang or lang == '' then return false end
    local resource = GetCurrentResourceName()
    local path = string.format('locales/%s.lua', tostring(lang))
    local content = LoadResourceFile(resource, path)
    if not content or content == '' then
        return false
    end

    local chunk, err = load(content, string.format('@%s', path), 't', _ENV)
    if not chunk then
        print(string.format('[LOCALE] Failed to compile %s: %s', path, tostring(err)))
        return false
    end

    local ok, execErr = pcall(chunk)
    if not ok then
        print(string.format('[LOCALE] Failed to execute %s: %s', path, tostring(execErr)))
        return false
    end

    return type(Locales) == 'table' and type(Locales[lang]) == 'table'
end

local function OpenMDT(openSource)
    if isUIOpen or isOpening then
        return
    end

    if not IsAllowedJob() then
        QBCore.Functions.Notify("You do not have access to the MDT", "error")
        return
    end

    isOpening = true

    -- Ensure tablet prop/animation is active regardless of how MDT is opened (item/command/keybind)
    TriggerEvent('pf_emsmdt:client:TabletVisualsStart', openSource or 'command')
    
    -- Store vehicle before opening (so we don't freeze it if moving)
    local ped = PlayerPedId()
    vehicleBeforeOpen = GetVehiclePedIsIn(ped, false)

    -- Get player data for topbar
    local PlayerData = QBCore.Functions.GetPlayerData() or {}
    local firstName = (PlayerData.charinfo and PlayerData.charinfo.firstname) or ""
    local lastName = (PlayerData.charinfo and PlayerData.charinfo.lastname) or "Officer"
    local playerName = ((firstName ~= "" and string.sub(firstName, 1, 1) .. " ") or "") .. lastName
    local jobLabel = (PlayerData.job and PlayerData.job.label) or "EMS"
    local rankLevel = (PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.level) or 0

    -- Permissions for UI
    local perms = GetPlayerPermissions()

    local localeData = nil
    local locale = string.lower(tostring(Config.Locale or 'en'))

    -- Locales are loaded as shared scripts into a global Locales table.
    -- If that table isn't populated (some deployments), fallback to loading locale files directly.
    if type(Locales) ~= 'table' then
        Locales = {}
    end

    localeData = Locales[locale] or Locales['en']
    if not localeData then
        -- Attempt to load on-demand from disk
        TryLoadLocaleFile(locale)
        TryLoadLocaleFile('en')
        localeData = Locales[locale] or Locales['en']
    end

    if not localeData then
        print(string.format('[LOCALE] Missing locale table for %s (Locales=%s)', tostring(locale), tostring(type(Locales))))
    end

    -- Open UI immediately so it's not blocked by server callback failures/timeouts.
    SetNuiFocus(true, true)
    isUIOpen = true
    isOpening = false
    TriggerEvent('pf_emsmdt:client:UIOpenState', true)

    local metaCallsign = (PlayerData.metadata and PlayerData.metadata.callsign) or ""
    local baseCallsign = (metaCallsign ~= '' and metaCallsign) or PlayerData.citizenid or ""

    SendNUIMessage({
        action = "open",
        calls = {},
        config = {
            debug = (Config and Config.Debug == true) or false,
            map = Config.Map,
            priorities = Config.CallPriorities,
            statuses = Config.CallStatuses,
            tabletTitle = Config.TabletTitle or 'EMS MDT',
            mode = 'ems',
            locale = Config.Locale or 'en',
            localeData = localeData,
            sentencing = {
                reductions = (Config.Sentencing and Config.Sentencing.Reductions) or {},
                allowNegativeBank = (Config.Sentencing and Config.Sentencing.AllowNegativeBank) == true,
                prisonScript = (Config.Sentencing and Config.Sentencing.PrisonScript) or 'default'
            }
        },
        permissions = perms,
        user = {
            name = playerName,
            rank = jobLabel,
            rankLevel = rankLevel,
            grade = (PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.name) or "Officer",
            callsign = baseCallsign,
            isSupervisor = perms.isSupervisor,
            isOwner = perms.isOwner,
            status = (PlayerData.metadata and PlayerData.metadata.mdt_status) or 'available',
            avatarUrl = (PlayerData.metadata and PlayerData.metadata.mdt_avatar) or nil
        }
    })

    -- Hydrate dispatch calls asynchronously.
    QBCore.Functions.TriggerCallback("pf_emsmdt_dispatch:server:GetCalls", function(calls)
        if type(calls) ~= 'table' then
            QBCore.Functions.Notify("Failed to load dispatch calls", "error")
            calls = {}
        end
        calls = EnrichCallsWithLocation(calls)
        SendNUIMessage({ action = 'setCalls', calls = calls })
    end)

    -- Hydrate dashboard data asynchronously.
    QBCore.Functions.TriggerCallback('pf_emsmdt_dispatch:server:GetDashboard', function(data)
        if data then
            SendNUIMessage({ action = 'setDashboard', data = data })
        end
    end)

    -- Hydrate user profile asynchronously (topbar callsign/status/avatar).
    QBCore.Functions.TriggerCallback('pf_emsmdt_dispatch:server:GetUserProfile', function(profile)
        local userProfile = profile or {}
        local finalCallsign = (userProfile.callsign and userProfile.callsign ~= '') and userProfile.callsign or baseCallsign
        local finalStatus = userProfile.status or (PlayerData.metadata and PlayerData.metadata.mdt_status) or 'available'
        local finalAvatar = userProfile.avatarUrl or (PlayerData.metadata and PlayerData.metadata.mdt_avatar) or nil

        SendNUIMessage({
            action = 'setUserInfo',
            user = {
                name = playerName,
                rank = jobLabel,
                rankLevel = rankLevel,
                grade = (PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.name) or "Officer",
                callsign = finalCallsign,
                isSupervisor = perms.isSupervisor,
                isOwner = perms.isOwner,
                status = finalStatus,
                avatarUrl = finalAvatar
            }
        })
        SendNUIMessage({ action = 'setUserPerms', permissions = perms })
    end)

    -- Hydrate chat history asynchronously.
    QBCore.Functions.TriggerCallback('pf_emsmdt_dispatch:server:GetChatHistory', function(messages)
        if not isUIOpen then return end
        if type(messages) ~= 'table' then return end
        for _, m in ipairs(messages) do
            if type(m) == 'table' and m.message then
                SendNUIMessage({ action = 'chatMessage', name = m.name or 'Medic', message = m.message, createdAt = m.createdAt })
            end
        end
    end)
end

local function CloseMDT()
    -- Remove NUI focus (hides cursor and enables input)
    SetNuiFocus(false, false)
    isUIOpen = false
    isOpening = false
    TriggerEvent('pf_emsmdt:client:UIOpenState', false)

    -- Stop tablet prop/animation on close (covers command/keybind opens too)
    TriggerEvent('pf_emsmdt:client:TabletVisualsStop')
    vehicleBeforeOpen = nil
    
    SendNUIMessage({
        action = "closeTablet"
    })
end

-- NUI Callbacks
RegisterNUICallback("close", function(data, cb)
    CloseMDT()
    if not data.id then
        cb({ success = false })
        return
    end
    
    TriggerServerEvent("pf_emsmdt_dispatch:server:CompleteCall", data.id)
    cb({ success = true })
end)

-- Dispatch modal actions (used by html/app.js)
RegisterNUICallback("acceptCall", function(data, cb)
    if not data or not data.id then
        cb({ success = false })
        return
    end
    TriggerServerEvent("pf_emsmdt_dispatch:server:AcceptCall", data.id)
    cb({ success = true })
end)

RegisterNUICallback("completeCall", function(data, cb)
    if not data or not data.id then
        cb({ success = false })
        return
    end
    TriggerServerEvent("pf_emsmdt_dispatch:server:CompleteCall", data.id)
    cb({ success = true })
end)

RegisterNUICallback("deleteCall", function(data, cb)
    if not data.id then
        cb({ success = false })
        return
    end
    
    TriggerServerEvent("pf_emsmdt_dispatch:server:DeleteCall", data.id)
    cb({ success = true })
end)

RegisterNUICallback("setWaypoint", function(data, cb)
    if not data.coords then
        cb({ success = false })
        return
    end
    
    SetNewWaypoint(data.coords.x, data.coords.y)
    QBCore.Functions.Notify("Waypoint set", "success")
    cb({ success = true })
end)

RegisterNUICallback("createCall", function(data, cb)
    -- Placeholder for future implementation
    -- This would open a form to create a new call
    QBCore.Functions.Notify("Create call feature coming soon", "info")
    cb({ success = true })
end)

-- Bulletins: grade 4+ can create, others view only (enforced server-side too)
RegisterNUICallback('createBulletin', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_emsmdt_dispatch:server:CreateBulletin', function(res)
        cb(res or { success = false, error = 'Unknown error' })
    end, {
        title = data and data.title or nil,
        body = data and data.body or nil
    })
end)

RegisterNetEvent('pf_emsmdt:client:bulletinCreated', function(bulletin)
    if not isUIOpen then return end
    SendNUIMessage({ action = 'bulletinCreated', bulletin = bulletin })
end)

-- Records/Search NUI callbacks
RegisterNUICallback("searchPatients", function(data, cb)
    local q = data and data.query or ""
    local page = data and data.page or 1
    local size = data and data.pageSize or 9
    QBCore.Functions.TriggerCallback('pf_emsmdt:searchPatients', function(result)
        SendNUIMessage({ action = 'setCitizens', citizens = result and result.data or {}, totalCount = result and result.total or 0 })
        cb({ success = true })
    end, { query = q, page = page, pageSize = size })
end)

RegisterNUICallback("searchCitizens", function(data, cb)
    local q = data and data.query or ""
    local page = data and data.page or 1
    local size = data and data.pageSize or 9
    QBCore.Functions.TriggerCallback('pf_emsmdt:searchPatients', function(result)
        SendNUIMessage({ action = 'setCitizens', citizens = result and result.data or {}, totalCount = result and result.total or 0 })
        cb({ success = true })
    end, { query = q, page = page, pageSize = size })
end)

RegisterNUICallback("searchVehicles", function(data, cb)
    -- Disabled in EMS MDT
    SendNUIMessage({ action = 'setVehicles', vehicles = {}, totalCount = 0 })
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("getOwnedVehicles", function(data, cb)
    -- Disabled in EMS MDT
    SendNUIMessage({ action = 'setVehicles', vehicles = {}, totalCount = 0 })
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("searchWarrants", function(data, cb)
    -- Disabled in EMS MDT
    SendNUIMessage({ action = 'setWarrants', warrants = {}, totalCount = 0 })
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("createWarrant", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("getWarrantDetails", function(data, cb)
    -- Disabled in EMS MDT
    cb({ error = 'disabled' })
end)

RegisterNUICallback("searchIncidents", function(data, cb)
    SendNUIMessage({ action = 'setIncidents', incidents = {} })
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("searchReports", function(data, cb)
    SendNUIMessage({ action = 'setReports', reports = {} })
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("getIncident", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Create report (UI expects this callback name)
RegisterNUICallback("createReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)
-- Get single report for details modal
RegisterNUICallback("getReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("searchFTOReports", function(data, cb)
    SendNUIMessage({ action = 'setFTOReports', reports = {} })
    cb({ success = false, error = 'disabled' })
end)

-- FTO Reports v2
RegisterNUICallback("getFtoReportsList", function(data, cb)
    SendNUIMessage({ action = 'setFTOReports', reports = {}, totalCount = 0 })
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("getFtoReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("searchTrainees", function(data, cb)
    cb({ success = false, trainees = {}, error = 'disabled' })
end)

RegisterNUICallback("saveFtoDraft", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("submitFtoReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("reviewFtoReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("getCharges", function(data, cb)
    cb({ success = false, charges = {}, error = 'disabled' })
end)

RegisterNUICallback("createCharge", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("updateCharge", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("deleteCharge", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- ============================================================================
-- Weapons Registry
-- ============================================================================

RegisterNUICallback("getWeaponRegistry", function(data, cb)
    cb({ success = false, weapons = {}, error = 'disabled' })
end)

RegisterNUICallback("getCitizenWeapons", function(data, cb)
    cb({ success = false, weapons = {}, error = 'disabled' })
end)

RegisterNUICallback("getWeaponModels", function(data, cb)
    cb({ success = false, models = {}, error = 'disabled' })
end)

RegisterNUICallback("searchWeaponOwners", function(data, cb)
    cb({ success = false, citizens = {}, error = 'disabled' })
end)

RegisterNUICallback("checkWeaponSerial", function(data, cb)
    cb({ success = false, exists = false, error = 'disabled' })
end)

RegisterNUICallback("registerWeapon", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("getServerTime", function(data, cb)
    cb({ success = true, time = os.time() })
end)

-- Creation flows
RegisterNUICallback("newIncident", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Unified Incident endpoints used by the UI
RegisterNUICallback("createIncident", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("updateIncident", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- ============================================================================
-- Dashboard: Chat System
-- ============================================================================

RegisterNUICallback("sendChatMessage", function(data, cb)
    local msg = data and (data.message or data.text) or ''
    msg = tostring(msg or '')
    msg = msg:gsub('[\r\n\t]', ' ')
    msg = msg:gsub('^%s*(.-)%s*$', '%1')
    if msg == '' then
        cb({ success = false, error = 'empty' })
        return
    end

    TriggerServerEvent('pf_emsmdt_dispatch:server:SendChatMessage', { message = msg })
    cb({ success = true })
end)

RegisterNetEvent('pf_emsmdt:client:chatMessage', function(msg)
    if not isUIOpen then return end
    if type(msg) ~= 'table' then return end
    SendNUIMessage({ action = 'chatMessage', name = msg.name or 'Medic', message = msg.message or '', createdAt = msg.createdAt })
end)

-- ============================================================================
-- Dashboard: Status & Callsign Management
-- ============================================================================

RegisterNUICallback("updatePlayerStatus", function(data, cb)
    TriggerServerEvent('pf_emsmdt_dispatch:server:SaveProfile', {
        status = data and (data.status or data.value) or nil,
        callsign = data and data.callsign or nil
    })
    cb({ success = true })
end)

RegisterNUICallback("getPersonalInfo", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_emsmdt_dispatch:server:GetUserProfile', function(profile)
        local pd = QBCore.Functions.GetPlayerData() or {}
        local ci = pd.charinfo or {}
        cb({
            success = true,
            name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')),
            callsign = profile and profile.callsign or nil,
            status = profile and profile.status or nil,
            avatarUrl = profile and profile.avatarUrl or nil
        })
    end)
end)

RegisterNUICallback("closeIncident", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("newReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("approveReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("newFTOReport", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback("openCitizen", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_emsmdt:getPatientProfile', function(result)
        SendNUIMessage({ action = 'setCitizenProfile', profile = (result and result.profile) or {} })
        cb({ success = true })
    end, data)
end)

-- Sentencing: history for a citizen
RegisterNUICallback("getCitizenSentences", function(data, cb)
    cb({ success = false, sentences = {}, error = 'disabled' })
end)

-- Sentencing: execute/create a new sentence
RegisterNUICallback("createSentence", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Sentencing: post bail to release a currently jailed citizen
RegisterNUICallback("postBail", function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Default MDT prison flow (teleport + wait + release)
local mdtSentenceActive = false
local mdtSentenceEndsAt = 0
local mdtSentenceStartedAt = 0
local mdtSentenceMinutes = 0
local mdtSentenceReason = ''

local mdtSavedAppearance = nil

local custodyHudTexLoaded = false

local function capturePedAppearance(ped)
    local app = { components = {}, props = {} }

    -- Components 0..11
    for i = 0, 11 do
        app.components[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i),
            palette = GetPedPaletteVariation(ped, i)
        }
    end

    -- Props 0..7
    for i = 0, 7 do
        local propIndex = GetPedPropIndex(ped, i)
        local propTexture = GetPedPropTextureIndex(ped, i)
        app.props[i] = { index = propIndex, texture = propTexture }
    end

    return app
end

local function applyPedAppearance(ped, app)
    if not app then return end

    if app.components then
        for i = 0, 11 do
            local c = app.components[i]
            if c then
                SetPedComponentVariation(ped, i, c.drawable or 0, c.texture or 0, c.palette or 0)
            end
        end
    end

    if app.props then
        for i = 0, 7 do
            local p = app.props[i]
            if p then
                if (p.index or -1) == -1 then
                    ClearPedProp(ped, i)
                else
                    SetPedPropIndex(ped, i, p.index or 0, p.texture or 0, true)
                end
            end
        end
    end
end

local function applyPrisonOutfit(ped)
    local outfit = Config.Sentencing and Config.Sentencing.PrisonOutfit or nil
    if not outfit then return end

    -- jacket -> component 11
    if outfit.jacket then
        SetPedComponentVariation(ped, 11, outfit.jacket.drawable or 0, outfit.jacket.texture or 0, 0)
    end
    -- shirt -> component 8
    if outfit.shirt then
        SetPedComponentVariation(ped, 8, outfit.shirt.drawable or 0, outfit.shirt.texture or 0, 0)
    end
    -- hands -> component 3
    if outfit.hands then
        SetPedComponentVariation(ped, 3, outfit.hands.drawable or 0, outfit.hands.texture or 0, 0)
    end
    -- legs -> component 4
    if outfit.legs then
        SetPedComponentVariation(ped, 4, outfit.legs.drawable or 0, outfit.legs.texture or 0, 0)
    end
    -- shoes -> component 6
    if outfit.shoes then
        SetPedComponentVariation(ped, 6, outfit.shoes.drawable or 0, outfit.shoes.texture or 0, 0)
    end
end

local function drawSentenceHud(secondsLeft)
    secondsLeft = math.max(0, tonumber(secondsLeft) or 0)
    local minsLeft = math.floor(secondsLeft / 60)
    local secsLeft = math.floor(secondsLeft % 60)

    local totalSeconds = math.max(1, (tonumber(mdtSentenceMinutes) or 0) * 60)
    local progress = 1.0 - (secondsLeft / totalSeconds)
    if progress < 0.0 then progress = 0.0 end
    if progress > 1.0 then progress = 1.0 end

    local timerLine = ('%02d:%02d'):format(minsLeft, secsLeft)

    -- Rounded background (uses a built-in UI sprite)
    if not custodyHudTexLoaded then
        RequestStreamedTextureDict('commonmenu', true)
        custodyHudTexLoaded = HasStreamedTextureDictLoaded('commonmenu')
    end

    if custodyHudTexLoaded then
        -- interaction_bgd has rounded corners and a soft gradient
        DrawSprite('commonmenu', 'interaction_bgd', 0.5, 0.075, 0.34, 0.070, 0.0, 255, 255, 255, 140)
    else
        -- Fallback: flat rect
        DrawRect(0.5, 0.075, 0.34, 0.060, 15, 18, 26, 140)
    end

    -- Label
    SetTextFont(4)
    SetTextScale(0.30, 0.30)
    SetTextColour(210, 216, 228, 230)
    SetTextCentre(true)
    SetTextDropShadow(1, 0, 0, 0, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName('Time Left')
    EndTextCommandDisplayText(0.5, 0.048)

    -- Timer
    SetTextFont(4)
    SetTextScale(0.46, 0.46)
    SetTextColour(240, 244, 255, 255)
    SetTextCentre(true)
    SetTextDropShadow(1, 0, 0, 0, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(timerLine)
    EndTextCommandDisplayText(0.5, 0.070)

    -- Progress bar background (more subtle)
    DrawRect(0.5, 0.098, 0.30, 0.008, 255, 255, 255, 14)
    -- Progress bar fill
    DrawRect(0.35 + (0.30 * progress / 2.0), 0.098, 0.30 * progress, 0.008, 255, 80, 80, 185)
end

local function setCustodyOverlay(visible, secondsLeft, totalSeconds)
    local progress = 0.0
    if totalSeconds and totalSeconds > 0 then
        progress = 1.0 - (secondsLeft / totalSeconds)
    end

    SendNUIMessage({
        action = 'custodyTimer',
        show = visible == true,
        secondsLeft = math.max(0, math.floor(secondsLeft or 0)),
        progress = math.max(0.0, math.min(1.0, progress)),
    })
end

local function releaseFromMdtSentence()
    if not mdtSentenceActive then return end
    mdtSentenceActive = false

    setCustodyOverlay(false, 0, 0)

    local ped = PlayerPedId()
    if mdtSavedAppearance then
        applyPedAppearance(ped, mdtSavedAppearance)
        mdtSavedAppearance = nil
    end

    local prisonCfg = Config.Sentencing and Config.Sentencing.Prison or nil
    local release = prisonCfg and prisonCfg.Release or nil

    if release then
        SetEntityCoords(ped, release.x, release.y, release.z, false, false, false, false)
        SetEntityHeading(ped, release.w or 0.0)
    end

    -- EMS MDT does not use sentencing/jail flows.
    QBCore.Functions.Notify('You have been released', 'success')
end

RegisterNetEvent('pf_emsmdt:client:StartMdtSentence', function(payload)
    local minutes = tonumber(payload and payload.minutes) or 0
    if minutes <= 0 then return end
    mdtSentenceReason = tostring(payload and payload.reason or 'MDT Sentence')

    local prisonCfg = Config.Sentencing and Config.Sentencing.Prison or nil
    if not prisonCfg or not prisonCfg.Spawns or #prisonCfg.Spawns < 1 then
        QBCore.Functions.Notify('Prison spawns are not configured', 'error')
        return
    end

    local spawns = prisonCfg.Spawns
    local pick = spawns[math.random(1, #spawns)]
    local ped = PlayerPedId()

    if not mdtSavedAppearance then
        mdtSavedAppearance = capturePedAppearance(ped)
    end

    applyPrisonOutfit(ped)

    mdtSentenceActive = true
    mdtSentenceStartedAt = GetGameTimer()
    mdtSentenceMinutes = minutes
    mdtSentenceEndsAt = GetGameTimer() + (minutes * 60 * 1000)

    local totalSeconds = math.max(0, math.floor(minutes * 60))
    setCustodyOverlay(true, totalSeconds, totalSeconds)

    SetEntityCoords(ped, pick.x, pick.y, pick.z, false, false, false, false)
    SetEntityHeading(ped, pick.w or 0.0)
    QBCore.Functions.Notify(('You have been sentenced for %s months'):format(minutes), 'error')

    CreateThread(function()
        while mdtSentenceActive do
            local now = GetGameTimer()
            if now >= mdtSentenceEndsAt then
                break
            end

            local msLeft = mdtSentenceEndsAt - now
            local secondsLeft = math.floor(msLeft / 1000)
            setCustodyOverlay(true, secondsLeft, totalSeconds)
            Wait(250)
        end

        if not mdtSentenceActive then return end
        releaseFromMdtSentence()
    end)
end)

-- Release early (e.g. bail posted)
RegisterNetEvent('pf_emsmdt:client:ReleaseMdtSentence', function()
    releaseFromMdtSentence()
end)

-- Inventory snapshot helper for built-in MDT jail (server-side stash/restore)
RegisterNetEvent('pf_emsmdt:client:SendInventorySnapshot', function(token)
    local items = {}
    local pd = QBCore.Functions.GetPlayerData() or {}
    local inv = pd.items or {}

    for slot, it in pairs(inv or {}) do
        if it and it.name and (tonumber(it.amount) or 0) > 0 then
            items[#items+1] = {
                name = it.name,
                amount = tonumber(it.amount) or 0,
                slot = tonumber(it.slot) or tonumber(slot) or nil,
                info = it.info,
            }
        end
    end

    -- Disabled in EMS MDT
end)

-- Citizen profile operations
RegisterNUICallback('addCitizenNote', function(data, cb)
    TriggerServerEvent('pf_emsmdt:addPatientNote', data)
    cb({ success = true })
end)

RegisterNUICallback('addPatientNote', function(data, cb)
    TriggerServerEvent('pf_emsmdt:addPatientNote', data)
    cb({ success = true })
end)
RegisterNUICallback('addCitizenFlag', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback('removeCitizenFlag', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Warrant operations
RegisterNUICallback('updateWarrantStatus', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Vehicle profile operations
RegisterNUICallback('addVehicleNote', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)
RegisterNUICallback('addVehicleFlag', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)
RegisterNUICallback('addVehicleStrike', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)
RegisterNUICallback('clearVehicleStrikes', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- License operations
RegisterNUICallback('suspendLicense', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)
RegisterNUICallback('removeLicense', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)
RegisterNUICallback('unsuspendLicense', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

RegisterNUICallback('getPlayerLocation', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Return a friendly street/area label for coords to NUI
RegisterNUICallback('getStreetLabel', function(data, cb)
    local coords = data and data.coords or nil
    local label = nil
    if coords then
        label = ComputeLocationLabel(coords)
        if not label or label == '' then
            label = ComputeNearestRoadLabel(coords)
        end
        if not label or label == '' then
            label = GetAreaLabelFromBounds(coords)
        end
    end
    if not label or label == '' then
        label = 'Unknown Area'
    end
    cb({ success = true, label = label })
end)

-- Save profile from NUI
RegisterNUICallback("saveProfile", function(data, cb)
    TriggerServerEvent("pf_emsmdt_dispatch:server:SaveProfile", {
        name = data.name,
        callsign = data.callsign,
        status = data.status,
        avatarUrl = data.avatarUrl
    })
    cb({ success = true })
end)

-- Update citizen profile picture
RegisterNUICallback('updateProfilePicture', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Update vehicle profile picture
RegisterNUICallback('updateVehiclePhoto', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Calibration NUI callback
RegisterNUICallback("calibResult", function(data, cb)
    if data.coefficients then
        dprint("^2[MDT CALIBRATION]^7 Affine coefficients computed:")
        dprint("^3Copy these values into Config.Map.affine in config.lua:^7")
        dprint("a = " .. data.coefficients.a)
        dprint("b = " .. data.coefficients.b)
        dprint("c = " .. data.coefficients.c)
        dprint("d = " .. data.coefficients.d)
        dprint("e = " .. data.coefficients.e)
        dprint("f = " .. data.coefficients.f)
        dprint("^3Then set enabled = true and debugCalibration = false^7")
    end
    cb({ success = true })
end)

-- Update profile picture
RegisterNUICallback('openVehicle', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- Client Events

local _dispatchSeenCallIds = {}
local _dispatchSeenInitialized = false

local function playDispatchDing()
    if not Config or Config.DispatchNotifications == nil then return end
    if Config.DispatchNotifications.Enabled ~= true then return end
    local mode = tostring(Config.DispatchNotifications.Mode or 'native'):lower()

    local function tryPlayNui()
        local n = Config.DispatchNotifications.NUI or {}
        if n.enabled == false then return end
        local vol = tonumber(n.volume) or 1.0
        if vol < 0.0 then vol = 0.0 end
        SendNUIMessage({
            action = 'playDispatchDing',
            volume = vol,
            waveform = n.waveform,
            tone1Hz = n.tone1Hz,
            tone2Hz = n.tone2Hz,
            tone2AtMs = n.tone2AtMs,
            durationMs = n.durationMs
        })
    end

    if mode == 'nui' then
        tryPlayNui()
        return
    end

    local s = Config.DispatchNotifications.Sound or {}
    if s.enabled == false then return end
    local name = tostring(s.name or 'SELECT')
    local set = tostring(s.soundset or 'HUD_FRONTEND_DEFAULT_SOUNDSET')

    local rep = Config.DispatchNotifications.NativeRepeat or {}
    local count = tonumber(rep.count) or 1
    local interval = tonumber(rep.intervalMs) or 0
    if count < 1 then count = 1 end
    if count > 5 then count = 5 end
    if interval < 0 then interval = 0 end
    if interval > 500 then interval = 500 end

    for i = 1, count do
        if i == 1 or interval == 0 then
            PlaySoundFrontend(-1, name, set, true)
        else
            SetTimeout((i - 1) * interval, function()
                PlaySoundFrontend(-1, name, set, true)
            end)
        end
    end

    -- Fallback: also try NUI audio if enabled (helps when native sound name/set is invalid).
    -- Note: NUI audio may be blocked until a user gesture.
    pcall(tryPlayNui)
end

-- Manual test: /pfmdt_testding
RegisterCommand('pfmdt_testding', function()
    if isDebugEnabled() then
        dprint('[MDT DEBUG] Manual ding test triggered')
    end
    playDispatchDing()
end, false)

RegisterNetEvent("pf_emsmdt_dispatch:client:CallsUpdated", function(calls)
    -- New-call detection (by id). This runs even if the UI is closed.
    local hasNewCall = false
    if type(calls) == 'table' then
        local firstUpdate = (_dispatchSeenInitialized ~= true)
        local incoming = {}
        local nowEpoch = 0
        if type(GetCloudTimeAsInt) == 'function' then
            nowEpoch = tonumber(GetCloudTimeAsInt()) or 0
        end
        local initialWindow = 15
        if Config and Config.DispatchNotifications and tonumber(Config.DispatchNotifications.InitialDingWindowSeconds) then
            initialWindow = tonumber(Config.DispatchNotifications.InitialDingWindowSeconds) or 15
        end
        if initialWindow < 0 then initialWindow = 0 end
        for _, c in pairs(calls) do
            if type(c) == 'table' and c.id then
                local id = tostring(c.id)
                incoming[id] = true
                if (not firstUpdate) and (not _dispatchSeenCallIds[id]) then
                    hasNewCall = true
                end

                -- If this is the first ever update we received, treat very recent calls as new.
                if firstUpdate and (not hasNewCall) and initialWindow > 0 and nowEpoch > 0 then
                    local createdAt = tonumber(c.createdAt)
                    if createdAt and (nowEpoch - createdAt) <= initialWindow then
                        hasNewCall = true
                    else
                        local createdBy = tostring(c.createdBy or '')
                        if createdBy:sub(1, 4) == '911:' and createdAt and (nowEpoch - createdAt) <= (initialWindow * 2) then
                            hasNewCall = true
                        end
                    end
                end
            end
        end
        _dispatchSeenCallIds = incoming
        _dispatchSeenInitialized = true
    end

    if hasNewCall then
        playDispatchDing()
    end

    -- Throttle updates to avoid spam
    local currentTime = GetGameTimer()
    if (not hasNewCall) and (currentTime - lastUpdateTime < updateThrottle) then
        return
    end
    lastUpdateTime = currentTime

    -- Keep NUI state warm even when MDT isn't open.
    -- NUI (html/index.html) stays loaded in the background, so we can push updates
    -- and have calls immediately visible once the user opens the tablet / navigates.
    calls = EnrichCallsWithLocation(calls)
    SendNUIMessage({
        action = "setCalls",
        calls = calls
    })
end)

-- Immediate per-call event (does not require MDT/Dispatch UI to be opened)
RegisterNetEvent('pf_emsmdt:dispatch:newCall', function(call)
    if type(call) ~= 'table' or not call.id then
        playDispatchDing()
        return
    end

    local id = tostring(call.id)
    if id ~= '' and _dispatchSeenInitialized and _dispatchSeenCallIds[id] then
        return
    end

    if id ~= '' then
        _dispatchSeenCallIds[id] = true
        _dispatchSeenInitialized = true
    end

    playDispatchDing()
end)

RegisterNetEvent('pf_emsmdt:client:RequestPlayerLocation', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash)
    
    local location = 'Unknown Location'
    if streetName and streetName ~= '' then
        location = streetName
    else
        location = string.format('%.1f, %.1f, %.1f', coords.x, coords.y, coords.z)
    end
    
    -- Send directly to NUI
    SendNUIMessage({
        action = 'setPlayerLocation',
        location = location
    })
end)

RegisterNetEvent('pf_emsmdt:client:SetPlayerLocation', function(location)
    SendNUIMessage({
        action = 'setPlayerLocation',
        location = location
    })
end)

RegisterNetEvent('pf_emsmdt:client:VehicleStrikeAdded', function(plate)
    SendNUIMessage({
        action = 'vehicleStrikeAdded',
        plate = plate
    })
end)

RegisterNetEvent("pf_emsmdt_dispatch:client:OpenMDT", function()
    OpenMDT('command')
end)

RegisterNetEvent("pf_emsmdt_dispatch:client:CloseMDT", function()
    CloseMDT()
end)

RegisterNetEvent('pf_emsmdt:client:UnitsUpdated', function(units)
    -- Update the dashboard units display
    if router and router.pages and router.pages.get('dashboard') then
        SendNUIMessage({
            action = 'setUnits',
            units = units
        })
    end
end)

RegisterNetEvent('pf_emsmdt:client:ChatMessage', function(data)
    -- Forward chat message to NUI
    SendNUIMessage(data)
end)

RegisterNetEvent('pf_emsmdt:client:UpdatePersonalInfo', function(data)
    -- Forward personal info update to NUI
    SendNUIMessage(data)
end)

-- Command & Keybind Registration

-- Register command if enabled in config
if Config.Command and Config.Command.Enabled then
    RegisterCommand(Config.Command.Name, function()
        if IsAllowedJob() then
            OpenMDT('command')
        else
            QBCore.Functions.Notify("You do not have access to the MDT", "error")
        end
    end, false)
end

-- Register keybind if enabled in config
if Config.Keybind and Config.Keybind.Enabled then
    local keybindCommand = (Config.Keybind.CommandName and tostring(Config.Keybind.CommandName)) or 'pfmdt_open'
    local inputType = (Config.Keybind.InputType and tostring(Config.Keybind.InputType)) or 'keyboard'
    local defaultKey = (Config.Keybind.Key and tostring(Config.Keybind.Key)) or ''

    RegisterCommand(keybindCommand, function()
        if IsAllowedJob() then
            OpenMDT('keybind')
        else
            QBCore.Functions.Notify("You do not have access to the MDT", "error")
        end
    end, false)

    RegisterKeyMapping(keybindCommand, Config.Keybind.Description or 'Open EMS MDT', inputType, defaultKey)
end

-- Event listener for item-based MDT opening
RegisterNetEvent('pf_emsmdt:client:TriggerMainOpen', function()
    if IsAllowedJob() then
        OpenMDT('item')
    end
end)

-- Event listener for item-based MDT closing
RegisterNetEvent('pf_emsmdt:client:CloseMDT', function()
    CloseMDT()
end)

-- Escape key to close MDT
RegisterCommand("closemdt", function()
    if isUIOpen then
        CloseMDT()
    end
end, false)

RegisterKeyMapping("closemdt", "Close EMS MDT", "keyboard", "ESCAPE")

-- =========================================================================
-- /911 COMMAND (Civilian Dispatch Calls)
-- =========================================================================

local function Play911PhoneAnim()
    local ped = PlayerPedId()
    if ped == 0 then return end

    CreateThread(function()
        -- Basic 3-second phone call animation
        -- (scenario is reliable and does not require anim dicts)
        local scenario = 'WORLD_HUMAN_STAND_MOBILE'
        ClearPedTasks(ped)
        TaskStartScenarioInPlace(ped, scenario, 0, true)
        Wait(3000)
        ClearPedTasks(ped)
    end)
end

RegisterCommand('911', function(_, args)
    if not Config.Dispatch911 or Config.Dispatch911.Enabled ~= true then
        return
    end

    local desc = table.concat(args or {}, ' ')
    desc = tostring(desc or ''):gsub('^%s*(.-)%s*$', '%1')
    if desc == '' then
        QBCore.Functions.Notify('Usage: /911 <description>', 'error')
        return
    end

    local maxLen = tonumber(Config.Dispatch911.MaxDescriptionLength) or 200
    if #desc > maxLen then
        desc = desc:sub(1, maxLen)
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local locationLabel = ComputeLocationLabel({ x = coords.x, y = coords.y, z = coords.z })
    if not locationLabel or locationLabel == '' then
        locationLabel = ComputeNearestRoadLabel({ x = coords.x, y = coords.y, z = coords.z })
    end
    if not locationLabel or locationLabel == '' then
        locationLabel = GetAreaLabelFromBounds({ x = coords.x, y = coords.y, z = coords.z })
    end

    Play911PhoneAnim()

    TriggerServerEvent('pf_emsmdt_dispatch:server:Create911Call', {
        description = desc,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        locationLabel = locationLabel
    })
end, false)

-- Calibration command (debug-only)
if isDebugEnabled() then
    RegisterCommand("mdt_calib_point", function()
        if not IsAllowedJob() then
            QBCore.Functions.Notify("You do not have access to MDT calibration", "error")
            return
        end

        if not isUIOpen then
            QBCore.Functions.Notify("Open the MDT first", "error")
            return
        end

        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)

        SendNUIMessage({
            action = "calibWorldPoint",
            point = {
                x = coords.x,
                y = coords.y
            }
        })

        QBCore.Functions.Notify("Calibration point captured. Now click the same location on the map.", "success", 5000)
    end, false)
end

-- Initialize

CreateThread(function()
    -- Update player job on resource start
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end
    
    dprint("^2[PF EMS MDT]^7 Client initialized")
end)

-- VEHICLE MOVEMENT THREAD REMOVED: applying forces while MDT is open was propelling vehicles in reverse/forward.

-- ============================================================================
-- UI & DISPATCH MANAGEMENT
-- ============================================================================
CreateThread(function()
    while true do
        if isUIOpen then
            -- Calls are pushed from server via pf_emsmdt_dispatch:client:CallsUpdated.
            -- Avoid polling here to reduce server/client/NUI load.

            -- Poll units every 5s
            QBCore.Functions.TriggerCallback("pf_emsmdt_dispatch:server:GetUnits", function(units)
                if units then
                    SendNUIMessage({ action = "setUnits", units = units })
                end
            end)

            -- Send player position every 1s (run a quick inner wait loop)
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local locationLabel = ComputeLocationLabel({ x = coords.x, y = coords.y, z = coords.z })
            if not locationLabel or locationLabel == '' then
                locationLabel = ComputeNearestRoadLabel({ x = coords.x, y = coords.y, z = coords.z })
            end
            if not locationLabel or locationLabel == '' then
                locationLabel = GetAreaLabelFromBounds({ x = coords.x, y = coords.y, z = coords.z })
            end
            SendNUIMessage({
                action = "playerPos",
                coords = { x = coords.x, y = coords.y, z = coords.z },
                location = locationLabel
            })

            -- Combined wait across refreshes
            Wait(5000)
        else
            Wait(500)
        end
    end
end)

-- NUI callback: fetch officers (online + offline) with allowed jobs
RegisterNUICallback('getPoliceOfficers', function(_, cb)
    cb({})
end)

-- NUI callback: fetch all players for witness selection
RegisterNUICallback('getAllPlayers', function(_, cb)
    cb({})
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if isUIOpen then
        CloseMDT()
    end
end)

-- Export MDT open state for other client scripts (e.g., CCTV)
exports('IsMDTOpen', function()
    return isUIOpen == true
end)

-- NUI callback: get CCTV camera list
RegisterNUICallback('getCCTVList', function(data, cb)
    dprint('[MDT CCTV] NUI callback getCCTVList received')
    QBCore.Functions.TriggerCallback('pf_emsmdt:cctv:getCameraList', function(cameras)
        dprint('[MDT CCTV] NUI callback received cameras from server:', #(cameras or {}))
        cb(cameras or {})
    end)
end)

-- NUI callback: get CCTV recordings
RegisterNUICallback('getCCTVRecordings', function(data, cb)
    dprint('[MDT CCTV] NUI callback getCCTVRecordings received')
    QBCore.Functions.TriggerCallback('pf_emsmdt:cctv:getCameraRecordings', function(recordings)
        dprint('[MDT CCTV] NUI callback received recordings from server:', #(recordings or {}))
        cb(recordings or {})
    end, data.camera_key)
end)

-- ============================================================================
-- EVIDENCE SYSTEM - Screenshot Capture
-- ============================================================================

-- Refresh incident evidence after photo added
RegisterNetEvent('pf_emsmdt:client:RefreshIncidentEvidence', function(incidentId)
    if isUIOpen then
        SendNUIMessage({ 
            action = 'refreshIncidentEvidence', 
            incidentId = incidentId 
        })
    end
end)

-- Refresh standalone evidence
RegisterNetEvent('pf_emsmdt:client:RefreshEvidence', function()
    if isUIOpen then
        SendNUIMessage({ 
            action = 'refreshEvidence'
        })
    end
end)

-- Evidence Camera Mode State
local inEvidenceCameraMode = false
local evidenceCaptureCallback = nil
local evidenceReturnData = nil
local evidenceCaptureType = 'standalone' -- 'standalone' or 'incident'
local showCameraInstructions = true

-- NUI Callback: Take evidence photo (standalone)
RegisterNUICallback('mdt:takeEvidencePhoto', function(data, cb)
    -- Check if screenshot-basic is available
    if not GetResourceState('screenshot-basic'):find('start') then
        QBCore.Functions.Notify('Screenshot resource not available', 'error')
        cb({ success = false })
        return
    end
    
    -- Check webhook configuration
    local webhookUrl = Config.Webhooks and Config.Webhooks.Evidence
    if not webhookUrl or webhookUrl == '' then
        QBCore.Functions.Notify('Evidence webhook not configured', 'error')
        cb({ success = false })
        return
    end
    
    -- Store callback and data for later use
    evidenceCaptureCallback = cb
    evidenceReturnData = data
    evidenceCaptureType = 'standalone'
    
    -- Enter Evidence Camera Mode
    EnterEvidenceCameraMode()
end)

-- Enter Evidence Camera Mode
function EnterEvidenceCameraMode()
    if inEvidenceCameraMode then return end
    
    inEvidenceCameraMode = true
    showCameraInstructions = true
    
    -- Hide MDT completely
    SendNUIMessage({ action = 'closeMDTForScreenshot' })
    SetNuiFocus(false, false)
    isUIOpen = false
    
    -- Disable combat controls and display instructions (do not freeze movement/vehicles)
    CreateThread(function()
        while inEvidenceCameraMode do
            DisableControlAction(0, 24, true) -- Attack
            DisableControlAction(0, 25, true) -- Aim
            DisableControlAction(0, 47, true) -- Weapon wheel
            DisableControlAction(0, 58, true) -- Weapon wheel
            DisableControlAction(0, 140, true) -- Melee attack light
            DisableControlAction(0, 141, true) -- Melee attack heavy
            DisableControlAction(0, 142, true) -- Melee attack alternate
            DisableControlAction(0, 257, true) -- Attack 2
            DisableControlAction(0, 263, true) -- Melee attack 1
            DisableControlAction(0, 264, true) -- Melee attack 2
            DisableControlAction(0, 68, true) -- Vehicle attack
            DisableControlAction(0, 91, true) -- Vehicle aim
            DisableControlAction(0, 99, true) -- Vehicle next weapon
            DisableControlAction(0, 115, true) -- Vehicle prev weapon
            DisableControlAction(0, 331, true) -- Vehicle duck
            DisableControlAction(0, 333, true) -- Vehicle dodge
            DisableControlAction(0, 334, true) -- Vehicle melee
            DisableControlAction(0, 335, true) -- Vehicle melee alt
            DisableControlAction(0, 336, true) -- Vehicle melee alt 2
            DisableControlAction(0, 80, true) -- Vehicle cinematic cam
            DisableControlAction(0, 22, true) -- Jump
            DisableControlAction(0, 44, true) -- Cover
            DisableControlAction(0, 37, true) -- Select weapon
            DisableControlAction(0, 45, true) -- Reload

            -- Allow common interactions so players can enter/exit vehicles and talk
            EnableControlAction(0, 249, true) -- Push-to-talk
            EnableControlAction(0, 75, true) -- Exit vehicle
            EnableControlAction(0, 23, true) -- Enter vehicle
            EnableControlAction(0, 21, true) -- Sprint
            
            -- Display on-screen instruction (only if showCameraInstructions is true)
            if showCameraInstructions then
                SetTextFont(4)
                SetTextScale(0.5, 0.5)
                SetTextColour(255, 255, 255, 255)
                SetTextOutline()
                SetTextEntry("STRING")
                AddTextComponentString("~b~[E]~w~ Take Evidence Photo  ~r~[X]~w~ Cancel")
                DrawText(0.5, 0.92)
            end
            
            Wait(0)
        end
    end)
    
    -- Listen for E key to capture or X to cancel
    CreateThread(function()
        while inEvidenceCameraMode do
            if IsControlJustPressed(0, 38) then -- E key
                CaptureEvidencePhoto()
                break
            elseif IsControlJustPressed(0, 73) then -- X key
                CancelEvidenceCapture()
                break
            end
            Wait(0)
        end
    end)
end

-- Capture Evidence Photo
function CaptureEvidencePhoto()
    if not inEvidenceCameraMode then return end
    
    -- Hide instructions text
    showCameraInstructions = false
    
    -- Hide minimap
    DisplayRadar(false)
    
    -- Brief wait to ensure UI elements are hidden
    Wait(100)
    
    -- Get webhook URL
    local webhookUrl = Config.Webhooks and Config.Webhooks.Evidence
    
    -- Capture screenshot and upload to Discord
    exports['screenshot-basic']:requestScreenshotUpload(webhookUrl, 'files[]', function(responseData)
        -- Exit camera mode
        ExitEvidenceCameraMode()
        
        if not responseData then
            QBCore.Functions.Notify('Screenshot upload failed', 'error')
            if evidenceCaptureCallback then
                evidenceCaptureCallback({ success = false })
                evidenceCaptureCallback = nil
                evidenceReturnData = nil
            end
            return
        end
        
        -- Parse Discord response
        local response = type(responseData) == 'string' and json.decode(responseData) or responseData
        if not response or not response.attachments or not response.attachments[1] then
            QBCore.Functions.Notify('Failed to get image URL from Discord', 'error')
            if evidenceCaptureCallback then
                evidenceCaptureCallback({ success = false })
                evidenceCaptureCallback = nil
                evidenceReturnData = nil
            end
            return
        end
        
        local imageUrl = response.attachments[1].url
        
        -- Evidence workflows are disabled in EMS MDT
        QBCore.Functions.Notify('Photo captured successfully', 'success')
        
        -- Return to callback
        if evidenceCaptureCallback then
            evidenceCaptureCallback({ success = true, imageUrl = imageUrl })
            evidenceCaptureCallback = nil
            evidenceReturnData = nil
        end
    end)
end

-- Cancel Evidence Capture
function CancelEvidenceCapture()
    if not inEvidenceCameraMode then return end
    
    -- Restore minimap
    DisplayRadar(true)
    
    ExitEvidenceCameraMode()
    
    QBCore.Functions.Notify('Photo capture cancelled', 'error')
    
    if evidenceCaptureCallback then
        evidenceCaptureCallback({ success = false, cancelled = true })
        evidenceCaptureCallback = nil
        evidenceReturnData = nil
    end
end

-- Exit Evidence Camera Mode
function ExitEvidenceCameraMode()
    if not inEvidenceCameraMode then return end
    
    inEvidenceCameraMode = false
    showCameraInstructions = false
    
    -- Restore minimap
    DisplayRadar(true)
    
    -- Restore MDT
    OpenMDT()
    SendNUIMessage({ action = 'restoreMDTAfterScreenshot', returnData = evidenceReturnData })
end

-- NUI Callback: Take evidence photo (for incidents)
RegisterNUICallback('mdt:evidenceTakePhoto', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)

-- NUI Callback: Get incident evidence
RegisterNUICallback('mdt:getIncidentEvidence', function(data, cb)
    cb({ success = false, evidence = {}, error = 'disabled' })
end)

-- NUI Callback: Get all vehicles
RegisterNUICallback('mdt:getAllVehicles', function(_, cb)
    cb({})
end)

-- NUI Callback: Get all charges
RegisterNUICallback('mdt:getAllCharges', function(_, cb)
    cb({})
end)

-- NUI Callback: Get all citizens
RegisterNUICallback('pf_emsmdt:getAllCitizens', function(data, cb)
    cb({})
end)

-- NUI Callback: Get all incidents
RegisterNUICallback('pf_emsmdt:getAllIncidents', function(data, cb)
    cb({})
end)

-- NUI Callback: Get all vehicles (pf_mdt version)
RegisterNUICallback('pf_emsmdt:getAllVehicles', function(data, cb)
    cb({})
end)

-- NUI Callback: Get all charges (pf_mdt version)
RegisterNUICallback('pf_emsmdt:getAllCharges', function(data, cb)
    cb({})
end)

-- NUI Callback: Search evidence
RegisterNUICallback('pf_emsmdt:searchEvidence', function(data, cb)
    SendNUIMessage({ action = 'setEvidence', evidence = {}, totalCount = 0 })
    cb({ success = false, error = 'disabled' })
end)

-- NUI Callback: Create evidence
RegisterNUICallback('pf_emsmdt:createEvidence', function(data, cb)
    cb({ success = false, error = 'disabled' })
end)
