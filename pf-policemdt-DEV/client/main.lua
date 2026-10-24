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
local isCitationPaperOpen = false
local lastUpdateTime = 0
local updateThrottle = 150 -- ms

-- Vehicle freeze prevention
local vehicleBeforeOpen = nil

-- Always-on dispatch overlay state
local _dispatchOverlayCalls = {}
local _dispatchOverlayIndex = 1
local _dispatchOverlayVisible = true
local _dispatchCallAreaBlips = {}
local _dispatchCallAreaShown = {}
local _dispatchAreaRadiusMeters = 140.0
local _dispatchAreaDurationMs = 60000
local _dispatchOverlayInputCooldownMs = 140
local _dispatchOverlayNextInputAt = 0

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
    if PFMdt and PFMdt.CanAccessMdt then
        return PFMdt.CanAccessMdt() == true
    end
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    return Config.AllowedJobs[PlayerData.job.name] == true
end

-- Server-driven access override (for DESK_DUTY / SUSPENDED, etc.)
PFMdt = PFMdt or {}
PFMdt._mdtAccessOverride = PFMdt._mdtAccessOverride or false

function PFMdt.CanAccessMdt()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local jobAllowed = false
    if PlayerData and PlayerData.job and Config and Config.AllowedJobs then
        jobAllowed = Config.AllowedJobs[PlayerData.job.name] == true
    end
    return jobAllowed or (PFMdt._mdtAccessOverride == true)
end

function PFMdt.RefreshMdtAccess()
    QBCore.Functions.TriggerCallback('pf_mdt:auth:canAccess', function(res)
        if type(res) == 'table' then
            PFMdt._mdtAccessOverride = res.allowed == true
        else
            PFMdt._mdtAccessOverride = false
        end
    end)
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
        allowed = (Config.AllowedJobs[jobName] == true) or (PFMdt and PFMdt._mdtAccessOverride == true),
        isSupervisor = Config.SupervisorGrades[jobName] and Config.SupervisorGrades[jobName][gradeLevel] == true,
        isOwner = isOwnerFlag
    }
end

-- Keep the client-side access override current.
CreateThread(function()
    Wait(2000)
    if PFMdt and PFMdt.RefreshMdtAccess then
        PFMdt.RefreshMdtAccess()
    end
    while true do
        Wait(30000)
        if PFMdt and PFMdt.RefreshMdtAccess then
            PFMdt.RefreshMdtAccess()
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    if PFMdt and PFMdt.RefreshMdtAccess then
        PFMdt.RefreshMdtAccess()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    Wait(250)
    if PFMdt and PFMdt.RefreshMdtAccess then
        PFMdt.RefreshMdtAccess()
    end
end)

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

    -- Support both array-like lists and map-like tables
    for key, call in pairs(calls) do
        if call and type(call) == "table" and call.coords then
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

local function setDispatchOverlayCalls(calls)
    local active = {}
    for _, c in pairs(calls or {}) do
        if type(c) == 'table' then
            local st = tostring(c.status or c.callStatus or ''):lower()
            if st ~= 'completed' and st ~= 'complete' and st ~= 'resolved' and st ~= 'closed' then
                active[#active + 1] = c
            end
        end
    end
    _dispatchOverlayCalls = active
    if _dispatchOverlayIndex > #_dispatchOverlayCalls then
        _dispatchOverlayIndex = math.max(1, #_dispatchOverlayCalls)
    end
    if _dispatchOverlayIndex < 1 then
        _dispatchOverlayIndex = 1
    end
end

local function isPanicDispatchCall(call)
    if type(call) ~= 'table' then return false end
    if call.panic == true or call.isPanic == true then return true end
    local blob = (
        tostring(call.callType or '') .. ' ' ..
        tostring(call.type or '') .. ' ' ..
        tostring(call.code or '') .. ' ' ..
        tostring(call.title or '') .. ' ' ..
        tostring(call.description or '')
    ):lower()
    return blob:find('panic', 1, true) ~= nil or blob:find('10-99', 1, true) ~= nil or blob:find('officer down', 1, true) ~= nil
end

local function getDispatchCallSprite(call)
    local blob = (
        tostring(call and call.callType or '') .. ' ' ..
        tostring(call and call.type or '') .. ' ' ..
        tostring(call and call.code or '') .. ' ' ..
        tostring(call and call.title or '') .. ' ' ..
        tostring(call and call.description or '')
    ):lower()

    if blob:find('panic', 1, true) or blob:find('10-99', 1, true) or blob:find('officer down', 1, true) then
        return 161
    end
    if blob:find('vehicle theft', 1, true) or blob:find('carjack', 1, true) or blob:find('gta', 1, true) or blob:find('stolen vehicle', 1, true) then
        return 225
    end
    if blob:find('robbery', 1, true) or blob:find('shoot', 1, true) or blob:find('shots fired', 1, true) or blob:find('gun', 1, true) then
        return 110
    end
    return 280
end

local function clearDispatchCallBlip(callId)
    local id = tostring(callId or '')
    local handles = _dispatchCallAreaBlips[id]
    if not handles then return end

    if handles.center and DoesBlipExist(handles.center) then
        RemoveBlip(handles.center)
    end
    if handles.radius and DoesBlipExist(handles.radius) then
        RemoveBlip(handles.radius)
    end
    _dispatchCallAreaBlips[id] = nil
end

local function createDispatchCallBlip(call)
    if type(call) ~= 'table' then return end
    local id = tostring(call.id or '')
    if id == '' then return end
    if _dispatchCallAreaShown[id] then return end
    if _dispatchCallAreaBlips[id] then return end

    local coords = call.coords
    local x = coords and tonumber(coords.x) or nil
    local y = coords and tonumber(coords.y) or nil
    local z = coords and tonumber(coords.z) or 0.0
    if not x or not y then return end

    local center = AddBlipForCoord(x + 0.0, y + 0.0, z + 0.0)
    SetBlipSprite(center, getDispatchCallSprite(call))
    SetBlipColour(center, 1)
    SetBlipScale(center, 0.9)
    SetBlipAsShortRange(center, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(call.title or call.callType or 'Dispatch Call'))
    EndTextCommandSetBlipName(center)

    local radius = AddBlipForRadius(x + 0.0, y + 0.0, z + 0.0, _dispatchAreaRadiusMeters)
    SetBlipColour(radius, 1)
    SetBlipAlpha(radius, 105)

    _dispatchCallAreaBlips[id] = { center = center, radius = radius }
    _dispatchCallAreaShown[id] = true

    SetTimeout(_dispatchAreaDurationMs, function()
        clearDispatchCallBlip(id)
    end)
end

local function sendDispatchOverlayUpdate()
    if not _dispatchOverlayVisible then
        SendNUIMessage({ action = 'setDispatchOverlayVisibility', visible = false })
        return
    end

    SendNUIMessage({ action = 'setDispatchOverlayVisibility', visible = true })
    SendNUIMessage({
        action = 'updateDispatchOverlay',
        calls = _dispatchOverlayCalls,
        currentIndex = _dispatchOverlayIndex - 1
    })
end

local function respondToCurrentOverlayCall()
    local call = _dispatchOverlayCalls[_dispatchOverlayIndex]
    if not call or not call.id then return false end

    TriggerServerEvent("pf_mdt_dispatch:server:AcceptCall", call.id)
    if call.coords and call.coords.x and call.coords.y then
        SetNewWaypoint(call.coords.x, call.coords.y)
    end
    SendNUIMessage({ action = 'dispatchOverlayResponded' })
    return true
end

local function cycleDispatchOverlay(delta)
    if not _dispatchOverlayVisible then return false end
    local count = #_dispatchOverlayCalls
    if count <= 1 then return false end

    if (tonumber(delta) or 0) < 0 then
        _dispatchOverlayIndex = _dispatchOverlayIndex - 1
        if _dispatchOverlayIndex < 1 then
            _dispatchOverlayIndex = count
        end
    else
        _dispatchOverlayIndex = _dispatchOverlayIndex + 1
        if _dispatchOverlayIndex > count then
            _dispatchOverlayIndex = 1
        end
    end

    sendDispatchOverlayUpdate()
    return true
end

local function getCitationSentenceId(payload)
    if type(payload) ~= 'table' then return 0 end

    local id = tonumber(payload.sentenceId or payload.sentenceID or payload.sentence_id or payload.sentence)
    if id and id > 0 then return math.floor(id) end

    local info = payload.info
    if type(info) == 'table' then
        id = tonumber(info.sentenceId or info.sentenceID or info.sentence_id or info.sentence)
        if id and id > 0 then return math.floor(id) end
    end

    local metadata = payload.metadata
    if type(metadata) == 'table' then
        id = tonumber(metadata.sentenceId or metadata.sentenceID or metadata.sentence_id or metadata.sentence)
        if id and id > 0 then return math.floor(id) end
    end

    return 0
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
    if not IsAllowedJob() then
        QBCore.Functions.Notify("You do not have access to the MDT", "error")
        return
    end

    -- Ensure tablet prop/animation is active regardless of how MDT is opened (item/command/keybind)
    TriggerEvent('pf-policemdt:client:TabletVisualsStart', openSource or 'command')
    
    -- Store vehicle before opening (so we don't freeze it if moving)
    local ped = PlayerPedId()
    vehicleBeforeOpen = GetVehiclePedIsIn(ped, false)
    
    -- Build a safe baseline payload and open the UI immediately.
    local PlayerData = QBCore.Functions.GetPlayerData() or {}
    local charinfo = PlayerData.charinfo or {}
    local meta = PlayerData.metadata or {}
    local job = PlayerData.job or {}
    local grade = job.grade or {}

    local firstName = charinfo.firstname or ""
    local lastName = charinfo.lastname or "Officer"
    local playerName = ((firstName ~= "" and string.sub(firstName, 1, 1) .. " ") or "") .. lastName
    local jobLabel = job.label or "Police"
    local rankLevel = grade.level or 0
    local perms = GetPlayerPermissions()

    local localeData = nil
    local locale = string.lower(tostring(Config.Locale or 'en'))
    if type(Locales) ~= 'table' then
        Locales = {}
    end
    localeData = Locales[locale] or Locales['en']
    if not localeData then
        TryLoadLocaleFile(locale)
        TryLoadLocaleFile('en')
        localeData = Locales[locale] or Locales['en']
    end

    local baseCallsign = (meta.callsign and tostring(meta.callsign)) or (PlayerData.citizenid and tostring(PlayerData.citizenid)) or ''
    local baseStatus = (meta.mdt_status and tostring(meta.mdt_status)) or 'available'
    local baseAvatar = meta.mdt_avatar or nil

    SetNuiFocus(true, true)
    isUIOpen = true
    TriggerEvent('pf_mdt:client:UIOpenState', true)

    SendNUIMessage({
        action = "open",
        calls = {},
        config = {
            debug = (Config and Config.Debug == true) or false,
            map = Config.Map,
            priorities = Config.CallPriorities,
            statuses = Config.CallStatuses,
            tabletTitle = Config.TabletTitle or 'Police MDT',
            manualEntriesEnabled = (Config and Config.ManualEntries and Config.ManualEntries.Enabled == true) or false,
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
            grade = grade.name or "Officer",
            callsign = baseCallsign,
            isSupervisor = perms.isSupervisor,
            isOwner = perms.isOwner,
            status = baseStatus,
            avatarUrl = baseAvatar
        }
    })

    -- Redundant show message: helps recover if UI script misses initial open handling.
    SendNUIMessage({ action = 'show' })

    -- Hydrate calls asynchronously (do not block UI open on callbacks).
    QBCore.Functions.TriggerCallback("pf_mdt_dispatch:server:GetCalls", function(calls)
        calls = EnrichCallsWithLocation(calls or {})
        SendNUIMessage({ action = 'setCalls', calls = calls })
        setDispatchOverlayCalls(calls)
        sendDispatchOverlayUpdate()
    end)

    -- Hydrate profile asynchronously.
    QBCore.Functions.TriggerCallback('pf_mdt_dispatch:server:GetUserProfile', function(profile)
        local userProfile = profile or {}
        local finalCallsign = (userProfile.callsign and userProfile.callsign ~= '') and userProfile.callsign or baseCallsign
        local finalStatus = userProfile.status or baseStatus
        local finalAvatar = userProfile.avatarUrl or baseAvatar

        SendNUIMessage({
            action = 'setUserInfo',
            user = {
                name = playerName,
                rank = jobLabel,
                rankLevel = rankLevel,
                grade = grade.name or "Officer",
                callsign = finalCallsign,
                isSupervisor = perms.isSupervisor,
                isOwner = perms.isOwner,
                status = finalStatus,
                avatarUrl = finalAvatar
            }
        })
    end)

    -- Hydrate dashboard asynchronously.
    QBCore.Functions.TriggerCallback('pf_mdt_dispatch:server:GetDashboard', function(data)
        if data then
            SendNUIMessage({ action = 'setDashboard', data = data })
        end
    end)
end

local function CloseMDT()
    -- Remove NUI focus (hides cursor and enables input)
    SetNuiFocus(false, false)
    isUIOpen = false
    isCitationPaperOpen = false
    TriggerEvent('pf_mdt:client:UIOpenState', false)

    -- Stop tablet prop/animation on close (covers command/keybind opens too)
    TriggerEvent('pf-policemdt:client:TabletVisualsStop')
    vehicleBeforeOpen = nil
    
    SendNUIMessage({
        action = "closeTablet"
    })
end

local function OpenCitationPaper(citation)
    SetNuiFocus(true, true)
    isCitationPaperOpen = true

    local payload = (type(citation) == 'table') and citation or {}
    local sentenceId = getCitationSentenceId(payload)

    if sentenceId > 0 then
        QBCore.Functions.TriggerCallback('pf_mdt:getCitationPaperData', function(result)
            local out = payload
            if result and result.success == true and type(result.citation) == 'table' then
                out = result.citation
            end

            SendNUIMessage({
                action = 'showCitationPaper',
                citation = out
            })
        end, { sentenceId = sentenceId, citation = payload })
        return
    end

    SendNUIMessage({
        action = 'showCitationPaper',
        citation = payload
    })
end

local function CloseCitationPaper()
    isCitationPaperOpen = false
    SendNUIMessage({ action = 'hideCitationPaper' })

    if not isUIOpen then
        -- Hide tablet shell when citation viewer was opened standalone.
        SendNUIMessage({ action = 'closeTablet' })
        SetNuiFocus(false, false)
    end
end

-- NUI Callbacks
RegisterNUICallback("close", function(data, cb)
    CloseMDT()
    if not data.id then
        cb({ success = false })
        return
    end
    
    TriggerServerEvent("pf_mdt_dispatch:server:CompleteCall", data.id)
    cb({ success = true })
end)

RegisterNUICallback('closeCitationPaper', function(_, cb)
    CloseCitationPaper()
    cb({ success = true })
end)

RegisterNUICallback("deleteCall", function(data, cb)
    if not data.id then
        cb({ success = false })
        return
    end
    
    TriggerServerEvent("pf_mdt_dispatch:server:DeleteCall", data.id)
    cb({ success = true })
end)

RegisterNUICallback("acceptCall", function(data, cb)
    if not data.id then
        cb({ success = false })
        return
    end

    -- Trigger server event to accept call
    TriggerServerEvent("pf_mdt_dispatch:server:AcceptCall", data.id)
    
    -- Set waypoint on client-side immediately
    if data.coords then
        SetNewWaypoint(data.coords.x, data.coords.y)
        QBCore.Functions.Notify("Waypoint set to call location", "success")
    end
    
    cb({ success = true })
end)

RegisterNUICallback('dispatchOverlayPrev', function(_, cb)
    cycleDispatchOverlay(-1)
    cb({ success = true })
end)

RegisterNUICallback('dispatchOverlayNext', function(_, cb)
    cycleDispatchOverlay(1)
    cb({ success = true })
end)

RegisterNUICallback('respondToCall', function(_, cb)
    respondToCurrentOverlayCall()
    cb({ success = true })
end)

RegisterNUICallback("completeCall", function(data, cb)
    if not data.id then
        cb({ success = false })
        return
    end

    TriggerServerEvent("pf_mdt_dispatch:server:CompleteCall", data.id)
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
    QBCore.Functions.TriggerCallback('pf_mdt_dispatch:server:CreateBulletin', function(res)
        cb(res or { success = false, error = 'Unknown error' })
    end, {
        title = data and data.title or nil,
        body = data and data.body or nil
    })
end)

RegisterNetEvent('pf-policemdt:client:bulletinCreated', function(bulletin)
    if not isUIOpen then return end
    SendNUIMessage({ action = 'bulletinCreated', bulletin = bulletin })
end)

-- Records/Search NUI callbacks
RegisterNUICallback("searchCitizens", function(data, cb)
    local q = data and data.query or ""
    local page = data and data.page or 1
    local size = data and data.pageSize or 9
    QBCore.Functions.TriggerCallback('pf_mdt:searchCitizens', function(result)
        SendNUIMessage({ action = 'setCitizens', citizens = result and result.data or {}, totalCount = result and result.total or 0 })
        cb({ success = true })
    end, { query = q, page = page, pageSize = size })
end)

RegisterNUICallback("searchVehicles", function(data, cb)
    local q = data and data.query or ""
    local page = data and data.page or 1
    local size = data and data.pageSize or 9
    QBCore.Functions.TriggerCallback('pf_mdt:searchVehicles', function(result)
        local vehicles = result and result.data or {}
        if type(vehicles) == 'table' then
            if isDebugEnabled() then
                local sample = vehicles[1]
                if sample then
                    dprint(('[MDT DEBUG] searchVehicles sample plate=%s model=%s modelLabel=%s'):format(
                        tostring(sample.plate), tostring(sample.model), tostring(sample.modelLabel)
                    ))
                else
                    dprint('[MDT DEBUG] searchVehicles returned 0 vehicles')
                end
            end
            for _, veh in ipairs(vehicles) do
                if veh then
                    if _isUnknownModelLabel(veh.modelLabel) then
                        local resolved = GetVehicleLabelFromModel(veh.model)
                        if resolved and not _isHashLikeString(resolved) then
                            veh.modelLabel = resolved
                        end
                    end
                end
            end
        end
        SendNUIMessage({ action = 'setVehicles', vehicles = vehicles, totalCount = result and result.total or 0 })
        cb({ success = true })
    end, { query = q, page = page, pageSize = size })
end)

RegisterNUICallback("getOwnedVehicles", function(data, cb)
    local page = data and data.page or 1
    local size = data and data.pageSize or 9
    QBCore.Functions.TriggerCallback('pf_mdt:getOwnedVehicles', function(result)
        local vehicles = result and result.data or {}
        if type(vehicles) == 'table' then
            for _, veh in ipairs(vehicles) do
                if veh then
                    if _isUnknownModelLabel(veh.modelLabel) then
                        local resolved = GetVehicleLabelFromModel(veh.model)
                        if resolved and not _isHashLikeString(resolved) then
                            veh.modelLabel = resolved
                        end
                    end
                end
            end
        end
        SendNUIMessage({ action = 'setVehicles', vehicles = vehicles, totalCount = result and result.total or 0 })
        cb({ success = true })
    end, { page = page, pageSize = size })
end)

RegisterNUICallback("searchWarrants", function(data, cb)
    local q = data and data.query or ""
    local page = data and data.page or 1
    local size = data and data.pageSize or 12
    QBCore.Functions.TriggerCallback('pf_mdt:searchWarrants', function(result)
        SendNUIMessage({ action = 'setWarrants', warrants = result and result.data or {}, totalCount = result and result.total or 0 })
        cb({ success = true })
    end, { query = q, page = page, pageSize = size })
end)

RegisterNUICallback("createWarrant", function(data, cb)
    TriggerServerEvent('pf_mdt:createWarrant', data)
    cb({ success = true })
end)

RegisterNUICallback("getWarrantDetails", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt_dispatch:server:GetWarrantDetails', function(warrant)
        cb(warrant or { error = 'Warrant not found' })
    end, data.warrantId)
end)

RegisterNUICallback("searchIncidents", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:searchIncidents', function(result)
        SendNUIMessage({ action = 'setIncidents', incidents = result and result.data or {} })
        cb({ success = true })
    end, data)
end)

RegisterNUICallback("searchReports", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:searchReports', function(result)
        SendNUIMessage({ action = 'setReports', reports = result and result.data or {} })
        cb({ success = true })
    end, data)
end)

RegisterNUICallback("getIncident", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getIncident', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

-- Create report (UI expects this callback name)
RegisterNUICallback("createReport", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:createReport', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)
-- Get single report for details modal
RegisterNUICallback("getReport", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getReport', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("searchFTOReports", function(data, cb)
    -- Legacy UI endpoint: still supported; data is mapped server-side
    QBCore.Functions.TriggerCallback('pf_mdt:searchFTOReports', function(result)
        SendNUIMessage({ action = 'setFTOReports', reports = result and result.data or {} })
        cb({ success = true })
    end, data)
end)

-- FTO Reports v2
RegisterNUICallback("getFtoReportsList", function(data, cb)
    dprint('[MDT CLIENT] getFtoReportsList called with data:', json.encode(data or {}))
    QBCore.Functions.TriggerCallback('pf_mdt:getFtoReportsList', function(result)
        dprint('[MDT CLIENT] getFtoReportsList result:', json.encode(result or {}))
        if result and result.success then
            dprint('[MDT CLIENT] Sending setFTOReports message with ' .. tostring(result.totalCount or 0) .. ' reports')
            SendNUIMessage({ action = 'setFTOReports', reports = result.reports or {}, totalCount = result.totalCount or 0 })
        else
            dprint('[MDT CLIENT] getFtoReportsList failed: ' .. tostring(result and result.error or 'unknown'))
        end
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("getFtoReport", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getFtoReport', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("searchTrainees", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:searchTrainees', function(result)
        cb(result or { success = false, trainees = {}, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("saveFtoDraft", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:saveFtoDraft', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("submitFtoReport", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:submitFtoReport', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("reviewFtoReport", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:reviewFtoReport', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("getCharges", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getCharges', function(result)
        cb(result or { success = false, charges = {} })
    end)
end)

RegisterNUICallback("createCharge", function(data, cb)
    dprint('[MDT DEBUG] Client received createCharge request with data:', json.encode(data))
    QBCore.Functions.TriggerCallback('pf_mdt:createCharge', function(result)
        dprint('[MDT DEBUG] Client received callback result:', json.encode(result))
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("updateCharge", function(data, cb)
    dprint('[MDT DEBUG] Client received updateCharge request with data:', json.encode(data))
    if not data then
        dprint('[MDT DEBUG] ERROR: No data provided')
        cb({ success = false, error = 'No data provided' })
        return
    end
    
    QBCore.Functions.TriggerCallback('pf_mdt:updateCharge', function(result)
        dprint('[MDT DEBUG] Client received updateCharge callback result:', json.encode(result))
        cb(result or { success = false, error = 'no_response' })
    end, data)
end)

RegisterNUICallback("deleteCharge", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:deleteCharge', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

-- ============================================================================
-- Weapons Registry
-- ============================================================================

RegisterNUICallback("getWeaponRegistry", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getWeaponRegistry', function(result)
        cb(result or { success = false, weapons = {} })
    end)
end)

RegisterNUICallback("getCitizenWeapons", function(data, cb)
    local citizenId = (data and (data.citizenId or data.citizenid or data.cid)) or ''
    QBCore.Functions.TriggerCallback('pf_mdt:getCitizenWeapons', function(result)
        cb(result or { success = false, weapons = {} })
    end, citizenId)
end)

RegisterNUICallback("getWeaponModels", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getWeaponModels', function(result)
        cb(result or { success = false, models = {} })
    end)
end)

RegisterNUICallback("searchWeaponOwners", function(data, cb)
    local query = (data and data.query) or ''
    QBCore.Functions.TriggerCallback('pf_mdt:searchWeaponOwners', function(result)
        cb(result or { success = false, citizens = {} })
    end, query)
end)

RegisterNUICallback("checkWeaponSerial", function(data, cb)
    local serial = (data and data.serial) or ''
    QBCore.Functions.TriggerCallback('pf_mdt:checkWeaponSerial', function(result)
        cb(result or { success = false, exists = true })
    end, serial)
end)

RegisterNUICallback("registerWeapon", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:registerWeapon', function(result)
        cb(result or { success = false })
    end, data or {})
end)

RegisterNUICallback("createManualCitizen", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:createManualCitizen', function(result)
        cb(result or { success = false })
    end, data or {})
end)

RegisterNUICallback("createManualVehicle", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:createManualVehicle', function(result)
        cb(result or { success = false })
    end, data or {})
end)

RegisterNUICallback("createManualWeapon", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:createManualWeapon', function(result)
        cb(result or { success = false })
    end, data or {})
end)

RegisterNUICallback("getServerTime", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getServerTime', function(result)
        cb(result or { success = false })
    end)
end)

-- Creation flows
RegisterNUICallback("newIncident", function(data, cb)
    TriggerServerEvent('pf_mdt:createIncident', data or {})
    cb({ success = true })
end)

-- Unified Incident endpoints used by the UI
RegisterNUICallback("createIncident", function(data, cb)
    -- Forward to server to persist; always respond with JSON
    TriggerServerEvent('pf_mdt:createIncident', data or {})
    cb({ success = true })
end)

RegisterNUICallback("updateIncident", function(data, cb)
    TriggerServerEvent('pf_mdt:updateIncident', data or {})
    cb({ success = true })
end)

-- ============================================================================
-- Dashboard: Chat System
-- ============================================================================

RegisterNUICallback("sendChatMessage", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:sendChatMessage', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data and data.message or '')
end)

-- ============================================================================
-- Dashboard: Status & Callsign Management
-- ============================================================================

RegisterNUICallback("updatePlayerStatus", function(data, cb)
    TriggerServerEvent('pf_mdt:updatePlayerStatus', data or {})
    cb({ success = true })
end)

RegisterNUICallback("getPersonalInfo", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getPersonalInfo', function(result)
        cb(result or { success = false })
    end)
end)

RegisterNUICallback("closeIncident", function(data, cb)
    TriggerServerEvent('pf_mdt:closeIncident', data or {})
    cb({ success = true })
end)

RegisterNUICallback("newReport", function(data, cb)
    -- Backwards-compat: route to the same createReport callback logic
    QBCore.Functions.TriggerCallback('pf_mdt:createReport', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("approveReport", function(data, cb)
    TriggerServerEvent('pf_mdt:approveReport', data or {})
    cb({ success = true })
end)

RegisterNUICallback("newFTOReport", function(data, cb)
    TriggerServerEvent('pf_mdt:createFTOReport', data or {})
    cb({ success = true })
end)

-- ============================================================================
-- Templates Management
-- ============================================================================

RegisterNUICallback("getTemplates", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getTemplates', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("createTemplate", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:createTemplate', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("updateTemplate", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:updateTemplate', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

RegisterNUICallback("deleteTemplate", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:deleteTemplate', function(result)
        cb(result or { success = false, error = 'no_response' })
    end, data or {})
end)

-- ============================================================================
-- Citizen Profile
-- ============================================================================

RegisterNUICallback("openCitizen", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getCitizenProfile', function(result)
        if result and result.vehicles then
            -- Resolve vehicle display names CLIENT-SIDE
            for i, veh in ipairs(result.vehicles) do
                if veh and _isUnknownModelLabel(veh.modelLabel) then
                    local resolved = GetVehicleLabelFromModel(veh.model)
                    if resolved and not _isHashLikeString(resolved) then
                        veh.modelLabel = resolved
                    end
                end
            end
        end
        SendNUIMessage({ action = 'setCitizenProfile', profile = result or {} })
        cb({ success = true })
    end, data)
end)

-- Sentencing: history for a citizen
RegisterNUICallback("getCitizenSentences", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getCitizenSentences', function(result)
        cb(result or { success = false, sentences = {} })
    end, data)
end)

-- Sentencing: execute/create a new sentence
RegisterNUICallback("createSentence", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:createSentence', function(result)
        cb(result or { success = false })
    end, data)
end)

-- Sentencing: print a citation paper item from an existing sentence
RegisterNUICallback('printCitationPaper', function(data, cb)
    -- Check if printing from the MDT is allowed
    if Config.Citations and Config.Citations.PrintFromMDT == false then
        cb({ success = false, error = 'Citation printing from the MDT is disabled. Use the station printer.' })
        return
    end
    -- If a physical printer location is configured, verify proximity
    if Config.Citations and Config.Citations.PrinterCoords then
        local coords  = Config.Citations.PrinterCoords
        local ped     = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        local dist    = #(vector3(pCoords.x, pCoords.y, pCoords.z) - vector3(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0))
        local maxDist = tonumber(Config.Citations.PrinterDistance) or 3.0
        if dist > maxDist then
            local label = tostring(Config.Citations.PrinterLabel or 'Station Printer')
            cb({ success = false, error = 'You must be near the ' .. label .. ' to print a citation.' })
            return
        end
    end
    QBCore.Functions.TriggerCallback('pf_mdt:printCitationPaper', function(result)
        cb(result or { success = false })
    end, data or {})
end)

-- Sentencing: post bail to release a currently jailed citizen
RegisterNUICallback("postBail", function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:postBail', function(result)
        cb(result or { success = false })
    end, data)
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

    TriggerServerEvent('pf_mdt:server:mdtSentenceReleased')
    QBCore.Functions.Notify('You have been released', 'success')
end

RegisterNetEvent('pf_mdt:client:StartMdtSentence', function(payload)
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
RegisterNetEvent('pf_mdt:client:ReleaseMdtSentence', function()
    releaseFromMdtSentence()
end)

-- Inventory snapshot helper for built-in MDT jail (server-side stash/restore)
RegisterNetEvent('pf_mdt:client:SendInventorySnapshot', function(token)
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

    TriggerServerEvent('pf_mdt:server:InventorySnapshot', token, items)
end)

-- Citizen profile operations
RegisterNUICallback('addCitizenNote', function(data, cb)
    TriggerServerEvent('pf_mdt:addCitizenNote', data)
    cb({ success = true })
end)
RegisterNUICallback('addCitizenFlag', function(data, cb)
    TriggerServerEvent('pf_mdt:addCitizenFlag', data)
    cb({ success = true })
end)

RegisterNUICallback('removeCitizenFlag', function(data, cb)
    TriggerServerEvent('pf_mdt:removeCitizenFlag', data)
    cb({ success = true })
end)

-- Warrant operations
RegisterNUICallback('updateWarrantStatus', function(data, cb)
    TriggerServerEvent('pf_mdt:updateWarrantStatus', data or {})
    cb({ success = true })
end)

-- Vehicle profile operations
RegisterNUICallback('addVehicleNote', function(data, cb)
    TriggerServerEvent('pf_mdt:addVehicleNote', data)
    cb({ success = true })
end)
RegisterNUICallback('addVehicleFlag', function(data, cb)
    TriggerServerEvent('pf_mdt:addVehicleFlag', data)
    cb({ success = true })
end)

RegisterNUICallback('removeVehicleFlag', function(data, cb)
    TriggerServerEvent('pf_mdt:removeVehicleFlag', data)
    cb({ success = true })
end)
RegisterNUICallback('addVehicleStrike', function(data, cb)
    TriggerServerEvent('pf_mdt:addVehicleStrike', data)
    cb({ success = true })
end)
RegisterNUICallback('clearVehicleStrikes', function(data, cb)
    TriggerServerEvent('pf_mdt:clearVehicleStrikes', data)
    cb({ success = true })
end)

-- License operations
RegisterNUICallback('suspendLicense', function(data, cb)
    TriggerServerEvent('pf_mdt:suspendLicense', data)
    cb({ success = true })
end)
RegisterNUICallback('removeLicense', function(data, cb)
    TriggerServerEvent('pf_mdt:removeLicense', data)
    cb({ success = true })
end)
RegisterNUICallback('unsuspendLicense', function(data, cb)
    TriggerServerEvent('pf_mdt:unsuspendLicense', data)
    cb({ success = true })
end)

RegisterNUICallback('getPlayerLocation', function(data, cb)
    TriggerServerEvent('pf_mdt:getPlayerLocation', data)
    cb({ success = true })
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
    TriggerServerEvent("pf_mdt_dispatch:server:SaveProfile", {
        name = data.name,
        callsign = data.callsign,
        status = data.status,
        avatarUrl = data.avatarUrl
    })
    cb({ success = true })
end)

-- Update citizen profile picture
RegisterNUICallback('updateProfilePicture', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:updateProfilePicture', function(result)
        cb(result or { success = false })
    end, data)
end)

-- Update vehicle profile picture
RegisterNUICallback('updateVehiclePhoto', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:updateVehiclePhoto', function(result)
        cb(result or { success = false })
    end, data)
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
    local plate = data and data.plate or ''
    if plate == '' then
        cb({ success = false })
        return
    end
    QBCore.Functions.TriggerCallback('pf_mdt:getVehicleProfile', function(profile)
        if not profile then 
            cb({ success = false })
            return 
        end

        -- Resolve display label CLIENT-SIDE using natives
        profile.modelLabel = profile.modelLabel or GetVehicleLabelFromModel(profile.model)

        SendNUIMessage({ 
            action = 'setVehicleProfile', 
            payload = profile
        })
        cb({ success = true })
    end, data)
end)

-- Client Events

local _dispatchSeenCallIds = {}
local _dispatchSeenInitialized = false

local function playDispatchDing()
    if not Config or not Config.Dispatch or Config.Dispatch.Notifications == nil then return end
    if Config.Dispatch.Notifications.Enabled ~= true then return end
    local mode = tostring(Config.Dispatch.Notifications.Mode or 'native'):lower()

    local function tryPlayNui()
        local n = Config.Dispatch.Notifications.NUI or {}
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

    local s = Config.Dispatch.Notifications.Sound or {}
    if s.enabled == false then return end
    local name = tostring(s.name or 'SELECT')
    local set = tostring(s.soundset or 'HUD_FRONTEND_DEFAULT_SOUNDSET')

    local rep = Config.Dispatch.Notifications.NativeRepeat or {}
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

local function playDispatchPanicDing()
    if not Config or not Config.Dispatch or Config.Dispatch.Notifications == nil then return end
    if Config.Dispatch.Notifications.Enabled ~= true then return end

    local mode = tostring(Config.Dispatch.Notifications.Mode or 'native'):lower()

    local function tryPlayNuiPanic()
        local n = Config.Dispatch.Notifications.NUI or {}
        if n.enabled == false then return end
        local vol = tonumber(n.volume) or 1.0
        if vol < 0.0 then vol = 0.0 end
        SendNUIMessage({
            action = 'playDispatchPanicDing',
            volume = vol,
            waveform = n.waveform,
            durationMs = n.durationMs
        })
    end

    if mode == 'nui' then
        tryPlayNuiPanic()
        return
    end

    local s = Config.Dispatch.Notifications.Sound or {}
    local name = tostring(s.name or 'SELECT')
    local set = tostring(s.soundset or 'HUD_FRONTEND_DEFAULT_SOUNDSET')
    local interval = 180

    for i = 0, 2 do
        if i == 0 then
            PlaySoundFrontend(-1, name, set, true)
        else
            SetTimeout(i * interval, function()
                PlaySoundFrontend(-1, name, set, true)
            end)
        end
    end

    pcall(tryPlayNuiPanic)
end

-- Manual test: /pfmdt_testding
RegisterCommand('pfmdt_testding', function()
    if isDebugEnabled() then
        dprint('[MDT DEBUG] Manual ding test triggered')
    end
    playDispatchDing()
end, false)

RegisterNetEvent("pf_mdt_dispatch:client:CallsUpdated", function(calls)
    -- New-call detection (by id). This runs even if the UI is closed.
    local hasNewCall = false
    local hasNewPanic = false
    if type(calls) == 'table' then
        local firstUpdate = (_dispatchSeenInitialized ~= true)
        local incoming = {}
        local nowEpoch = 0
        if type(GetCloudTimeAsInt) == 'function' then
            nowEpoch = tonumber(GetCloudTimeAsInt()) or 0
        end
        local initialWindow = 15
        if Config and Config.Dispatch and Config.Dispatch.Notifications and tonumber(Config.Dispatch.Notifications.InitialDingWindowSeconds) then
            initialWindow = tonumber(Config.Dispatch.Notifications.InitialDingWindowSeconds) or 15
        end
        if initialWindow < 0 then initialWindow = 0 end
        for _, c in pairs(calls) do
            if type(c) == 'table' and c.id then
                local id = tostring(c.id)
                incoming[id] = true
                createDispatchCallBlip(c)
                if (not firstUpdate) and (not _dispatchSeenCallIds[id]) then
                    hasNewCall = true
                    if isPanicDispatchCall(c) then hasNewPanic = true end
                end

                -- If this is the first ever update we received, treat very recent calls as new.
                if firstUpdate and (not hasNewCall) and initialWindow > 0 and nowEpoch > 0 then
                    local createdAt = tonumber(c.createdAt)
                    if createdAt and (nowEpoch - createdAt) <= initialWindow then
                        hasNewCall = true
                        if isPanicDispatchCall(c) then hasNewPanic = true end
                    else
                        local createdBy = tostring(c.createdBy or '')
                        if createdBy:sub(1, 4) == '911:' and createdAt and (nowEpoch - createdAt) <= (initialWindow * 2) then
                            hasNewCall = true
                            if isPanicDispatchCall(c) then hasNewPanic = true end
                        end
                    end
                end
            end
        end
        _dispatchSeenCallIds = incoming
        _dispatchSeenInitialized = true
    end

    if hasNewCall then
        if hasNewPanic then
            playDispatchPanicDing()
        else
            playDispatchDing()
        end
    end

    calls = EnrichCallsWithLocation(calls)

    -- Keep overlay state synced immediately so clear/complete actions reflect without delay.
    setDispatchOverlayCalls(calls)
    sendDispatchOverlayUpdate()

    -- Throttle heavier Dispatch page payload updates to avoid UI spam.
    local currentTime = GetGameTimer()
    if (not hasNewCall) and (currentTime - lastUpdateTime < updateThrottle) then
        return
    end
    lastUpdateTime = currentTime

    -- Keep NUI state warm even when MDT isn't open.
    -- NUI (html/index.html) stays loaded in the background, so we can push updates
    -- and have calls immediately visible once the user opens the tablet / navigates.
    SendNUIMessage({
        action = "setCalls",
        calls = calls
    })
end)

-- Immediate per-call event (does not require MDT/Dispatch UI to be opened)
RegisterNetEvent('pf_mdt:dispatch:newCall', function(call)
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

    createDispatchCallBlip(call)

    if isPanicDispatchCall(call) then
        playDispatchPanicDing()
    else
        playDispatchDing()
    end
end)

RegisterNetEvent('pf_mdt:client:RequestPlayerLocation', function()
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

RegisterNetEvent('pf_mdt:client:SetPlayerLocation', function(location)
    SendNUIMessage({
        action = 'setPlayerLocation',
        location = location
    })
end)

RegisterNetEvent('pf_mdt:client:VehicleStrikeAdded', function(plate)
    SendNUIMessage({
        action = 'vehicleStrikeAdded',
        plate = plate
    })
end)

RegisterNetEvent("pf_mdt_dispatch:client:OpenMDT", function()
    OpenMDT('command')
end)

RegisterNetEvent("pf_mdt_dispatch:client:CloseMDT", function()
    CloseMDT()
end)

RegisterNetEvent('pf_mdt:client:UnitsUpdated', function(units)
    -- Update the dashboard units display
    if router and router.pages and router.pages.get('dashboard') then
        SendNUIMessage({
            action = 'setUnits',
            units = units
        })
    end
end)

RegisterNetEvent('pf_mdt:client:ChatMessage', function(data)
    -- Forward chat message to NUI
    SendNUIMessage(data)
end)

RegisterNetEvent('pf_mdt:client:UpdatePersonalInfo', function(data)
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

    RegisterKeyMapping(keybindCommand, Config.Keybind.Description or 'Open Police MDT', inputType, defaultKey)
end

-- Event listener for item-based MDT opening
RegisterNetEvent('pf-policemdt:client:TriggerMainOpen', function()
    if IsAllowedJob() then
        OpenMDT('item')
    end
end)

-- Event listener for item-based MDT closing
RegisterNetEvent('pf-policemdt:client:CloseMDT', function()
    CloseMDT()
end)

RegisterNetEvent('pf-policemdt:client:OpenCitationPaper', function(citation)
    OpenCitationPaper(citation)
end)

-- Escape key to close MDT / citation paper viewer
RegisterCommand("closemdt", function()
    if isCitationPaperOpen then
        CloseCitationPaper()
        return
    end

    if isUIOpen then
        CloseMDT()
    end
end, false)

RegisterKeyMapping("closemdt", "Close Police MDT Dispatch", "keyboard", "ESCAPE")

-- Dispatch overlay quick-responder (matches HUD hint).
RegisterCommand('pfmdt_dispatch_respond', function()
    respondToCurrentOverlayCall()
end, false)

RegisterKeyMapping('pfmdt_dispatch_respond', 'Dispatch: respond to current call', 'keyboard', 'G')

RegisterCommand('dispatch', function()
    _dispatchOverlayVisible = not _dispatchOverlayVisible

    -- Force a fresh call pull so overlay is always hydrated when shown.
    QBCore.Functions.TriggerCallback("pf_mdt_dispatch:server:GetCalls", function(calls)
        calls = EnrichCallsWithLocation(calls or {})
        setDispatchOverlayCalls(calls)
        sendDispatchOverlayUpdate()
    end)

    QBCore.Functions.Notify(('Dispatch overlay %s'):format(_dispatchOverlayVisible and 'shown' or 'hidden'), 'primary')
end, false)

RegisterCommand('panic', function(_, args)
    if not IsAllowedJob() then
        QBCore.Functions.Notify('You do not have access to panic dispatch', 'error')
        return
    end

    local desc = table.concat(args or {}, ' ')
    desc = tostring(desc or ''):gsub('^%s*(.-)%s*$', '%1')
    if desc == '' then
        desc = 'Officer activated panic button'
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local locationLabel = ComputeLocationLabel({ x = coords.x, y = coords.y, z = coords.z })
    if not locationLabel or locationLabel == '' then
        locationLabel = ComputeNearestRoadLabel({ x = coords.x, y = coords.y, z = coords.z })
    end
    if not locationLabel or locationLabel == '' then
        locationLabel = GetAreaLabelFromBounds({ x = coords.x, y = coords.y, z = coords.z }) or 'Unknown Location'
    end

    TriggerServerEvent('pf_mdt_dispatch:server:CreatePanicCall', {
        description = desc,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        locationLabel = locationLabel
    })

    QBCore.Functions.Notify('Panic button activated', 'error')
end, false)

-- Fallback close handling: if NUI-side Escape listener fails, close from client controls.
CreateThread(function()
    while true do
        if isUIOpen or isCitationPaperOpen then
            if IsControlJustReleased(0, 200) or IsControlJustReleased(0, 322) then
                if isCitationPaperOpen then
                    CloseCitationPaper()
                else
                    CloseMDT()
                end
                Wait(250)
            else
                Wait(0)
            end
        else
            Wait(250)
        end
    end
end)

-- Gameplay-side arrow key support for dispatch overlay while moving/driving.
CreateThread(function()
    while true do
        if _dispatchOverlayVisible and (not isUIOpen) and (not isCitationPaperOpen) and #_dispatchOverlayCalls > 1 then
            local now = GetGameTimer()
            if now >= _dispatchOverlayNextInputAt then
                local changed = false
                if IsControlJustPressed(0, 174) or IsControlJustPressed(1, 174) or IsDisabledControlJustPressed(0, 174) then
                    changed = cycleDispatchOverlay(-1)
                elseif IsControlJustPressed(0, 175) or IsControlJustPressed(1, 175) or IsDisabledControlJustPressed(0, 175) then
                    changed = cycleDispatchOverlay(1)
                end

                if changed then
                    _dispatchOverlayNextInputAt = now + _dispatchOverlayInputCooldownMs
                end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

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

    TriggerServerEvent('pf_mdt_dispatch:server:Create911Call', {
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
    
    dprint("^2[PF MDT Dispatch]^7 Client initialized")
end)

-- VEHICLE MOVEMENT THREAD REMOVED: applying forces while MDT is open was propelling vehicles in reverse/forward.

-- ============================================================================
-- UI & DISPATCH MANAGEMENT
-- ============================================================================
CreateThread(function()
    while true do
        if isUIOpen then
            -- Calls are pushed from server via pf_mdt_dispatch:client:CallsUpdated.
            -- Avoid polling here to reduce server/client/NUI load.

            -- Poll units every 5s
            QBCore.Functions.TriggerCallback("pf_mdt_dispatch:server:GetUnits", function(units)
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
    QBCore.Functions.TriggerCallback('pf_mdt:getPoliceOfficers', function(list)
        cb(list or {})
    end)
end)

-- NUI callback: fetch all players for witness selection
RegisterNUICallback('getAllPlayers', function(_, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getAllPlayers', function(list)
        cb(list or {})
    end)
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for callId, _ in pairs(_dispatchCallAreaBlips) do
        clearDispatchCallBlip(callId)
    end
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
    QBCore.Functions.TriggerCallback('pf_mdt:cctv:getCameraList', function(cameras)
        dprint('[MDT CCTV] NUI callback received cameras from server:', #(cameras or {}))
        cb(cameras or {})
    end)
end)

-- NUI callback: get CCTV recordings
RegisterNUICallback('getCCTVRecordings', function(data, cb)
    dprint('[MDT CCTV] NUI callback getCCTVRecordings received')
    QBCore.Functions.TriggerCallback('pf_mdt:cctv:getCameraRecordings', function(recordings)
        dprint('[MDT CCTV] NUI callback received recordings from server:', #(recordings or {}))
        cb(recordings or {})
    end, data.camera_key)
end)

-- ============================================================================
-- EVIDENCE SYSTEM - Screenshot Capture
-- ============================================================================

-- Refresh incident evidence after photo added
RegisterNetEvent('pf_mdt:client:RefreshIncidentEvidence', function(incidentId)
    if isUIOpen then
        SendNUIMessage({ 
            action = 'refreshIncidentEvidence', 
            incidentId = incidentId 
        })
    end
end)

-- Refresh standalone evidence
RegisterNetEvent('pf_mdt:client:RefreshEvidence', function()
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
        
        -- Handle incident evidence differently
        if evidenceCaptureType == 'incident' and evidenceReturnData and evidenceReturnData.incidentId then
            -- Send to server to save in database
            TriggerServerEvent('pf_mdt:server:AddIncidentEvidencePhoto', {
                incidentId = evidenceReturnData.incidentId,
                imageUrl = imageUrl,
                title = '',
                description = ''
            })
            QBCore.Functions.Notify('Evidence photo captured successfully', 'success')
        else
            QBCore.Functions.Notify('Photo captured successfully', 'success')
        end
        
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
    local incidentId = data.incidentId
    if not incidentId then
        QBCore.Functions.Notify('Invalid incident ID', 'error')
        cb({ success = false })
        return
    end
    
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
    evidenceCaptureType = 'incident'
    
    -- Enter Evidence Camera Mode
    EnterEvidenceCameraMode()
end)

-- NUI Callback: Get incident evidence
RegisterNUICallback('mdt:getIncidentEvidence', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getIncidentEvidence', function(result)
        cb(result)
    end, data)
end)

-- NUI Callback: Get all vehicles
RegisterNUICallback('mdt:getAllVehicles', function(_, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getAllVehicles', function(vehicles)
        cb(vehicles or {})
    end)
end)

-- NUI Callback: Get all charges
RegisterNUICallback('mdt:getAllCharges', function(_, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getAllCharges', function(charges)
        cb(charges or {})
    end)
end)

-- NUI Callback: Get all citizens
RegisterNUICallback('pf_mdt:getAllCitizens', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getAllCitizens', function(citizens)
        cb(citizens or {})
    end, data)
end)

-- NUI Callback: Get all incidents
RegisterNUICallback('pf_mdt:getAllIncidents', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getAllIncidents', function(incidents)
        cb(incidents or {})
    end, data)
end)

-- NUI Callback: Get all vehicles (pf_mdt version)
RegisterNUICallback('pf_mdt:getAllVehicles', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getAllVehicles', function(vehicles)
        cb(vehicles or {})
    end, data)
end)

-- NUI Callback: Get all charges (pf_mdt version)
RegisterNUICallback('pf_mdt:getAllCharges', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:getAllCharges', function(charges)
        cb(charges or {})
    end, data)
end)

-- NUI Callback: Search evidence
RegisterNUICallback('pf_mdt:searchEvidence', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:searchEvidence', function(result)
        if result and result.success then
            SendNUIMessage({
                action = 'setEvidence',
                evidence = result.evidence or {},
                totalCount = result.totalCount or 0
            })
        end
        cb(result or { success = false })
    end, data)
end)

-- NUI Callback: Create evidence
RegisterNUICallback('pf_mdt:createEvidence', function(data, cb)
    QBCore.Functions.TriggerCallback('pf_mdt:createEvidence', function(result)
        if result and result.success then
            SendNUIMessage({ action = 'refreshEvidence' })
        end
        cb(result or { success = false })
    end, data)
end)
