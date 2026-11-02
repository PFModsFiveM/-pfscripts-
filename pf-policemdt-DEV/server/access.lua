-- ============================================================================
-- PF Police MDT - server access gate
-- ============================================================================
-- Loaded before every other server script. Every MDT callback and net event of this resource is
-- for police jobs (Config.AllowedJobs) unless it is listed in PUBLIC below. Most handlers never
-- checked the caller's job, so any player could read citizen records, warrants and reports, or
-- create and delete them, by triggering the event from a modified client.

local QBCore = PFMdt.GetCore()
if not QBCore then return end

PFMdtAccess = PFMdtAccess or {}

-- Callbacks and net events any player may use (each checks its own caller).
local PUBLIC = {
    ['pf_mdt:auth:canAccess'] = true,
    ['pf_mdt:getOwnedVehicles'] = true,           -- the caller's own vehicles
    ['pf_mdt:getCitationPaperData'] = true,       -- citizen holding a citation paper
    ['pf_mdt:server:mdtSentenceReleased'] = true, -- jailed citizen at the end of the sentence
    ['pf_mdt:server:acceptBail'] = true,          -- the payer of a bail offer made to them
    ['pf_mdt:server:declineBail'] = true,
    ['pf_mdt_dispatch:server:CreateCallout'] = true,
    ['pf_mdt_dispatch:server:Create911Call'] = true,
    ['pf_mdt:dispatch:shotsFired'] = true,
    ['pf_mdt:dispatch:vehicleTheft'] = true,
    ['pf_mdt:dispatch:homicide'] = true,
}

local function isGated(name)
    name = tostring(name or '')
    if PUBLIC[name] then return false end
    return name:sub(1, 7) == 'pf_mdt:' or name:sub(1, 16) == 'pf_mdt_dispatch:'
end

function PFMdtAccess.IsOfficer(src)
    local P = QBCore.Functions.GetPlayer(tonumber(src) or src)
    local job = P and P.PlayerData and P.PlayerData.job
    return job ~= nil and Config and Config.AllowedJobs and Config.AllowedJobs[job.name] == true or false
end

-- The caller's job (name, grade, isboss, onduty) from the server's player, or nil.
function PFMdtAccess.Job(src)
    local P = QBCore.Functions.GetPlayer(tonumber(src) or src)
    local job = P and P.PlayerData and P.PlayerData.job
    if type(job) ~= 'table' or type(job.name) ~= 'string' then return nil end
    local grade = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade) or 0
    return { name = job.name, grade = grade, isboss = job.isboss == true, onduty = job.onduty == true }, P
end

-- An officer of an allowed job who is on duty (QBCore duty, job.onduty). Everything in the MDT that
-- changes a record, a citizen or money needs this: an officer who clocked off keeps reading access only.
function PFMdtAccess.IsOnDutyOfficer(src)
    local job = PFMdtAccess.Job(src)
    return job ~= nil and Config and Config.AllowedJobs and Config.AllowedJobs[job.name] == true and job.onduty or false
end

-- Minimum grade for an action in this job (Config.Permissions[action][job]; 0 when not listed).
function PFMdtAccess.MinGrade(action, jobName)
    local perms = Config and Config.Permissions and Config.Permissions[action]
    if type(perms) == 'number' then return perms end
    return type(perms) == 'table' and tonumber(perms[jobName]) or 0
end

-- On duty, allowed job and at least the action's grade. Returns ok, error code.
function PFMdtAccess.Can(src, action)
    local job = PFMdtAccess.Job(src)
    if not job or not (Config and Config.AllowedJobs and Config.AllowedJobs[job.name] == true) then return false, 'no_access' end
    if not job.onduty then return false, 'off_duty' end
    if action and job.grade < PFMdtAccess.MinGrade(action, job.name) then return false, 'no_permission' end
    return true, nil
end

-- The department boss (job.isboss, or the highest grade of that job in QBCore.Shared.Jobs).
function PFMdtAccess.IsBoss(src)
    local job = PFMdtAccess.Job(src)
    if not job or not (Config and Config.AllowedJobs and Config.AllowedJobs[job.name] == true) then return false end
    if job.isboss then return true end
    local def = QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[job.name]
    local top = nil
    for g in pairs(type(def) == 'table' and type(def.grades) == 'table' and def.grades or {}) do
        local n = tonumber(g)
        if n and (not top or n > top) then top = n end
    end
    return top ~= nil and job.grade >= top
end

-- Distance between two players' peds on the server (math.huge when either is missing).
function PFMdtAccess.Distance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return math.huge end
    local ca, cb = GetEntityCoords(pa), GetEntityCoords(pb)
    if not ca or not cb then return math.huge end
    return #(vector3(ca.x, ca.y, ca.z) - vector3(cb.x, cb.y, cb.z))
end

-- Server position of a player, or nil.
function PFMdtAccess.Coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return c and vector3(c.x, c.y, c.z) or nil
end

-- An https image URL safe to store and show (no quotes, spaces, backslashes, brackets or angle
-- brackets), on a host from Config.Images.AllowedHosts, at most MaxLength bytes; nil otherwise.
-- Officers set citizen photos, vehicle photos and evidence images: a free-form value could break
-- out of the page for every officer who opens the record, or load a host that logs their IP.
function PFMdtAccess.ImageUrl(v)
    if type(v) ~= 'string' then return nil end
    local cfg = Config and Config.Images or {}
    if #v == 0 or #v > (tonumber(cfg.MaxLength) or 512) then return nil end
    local host, rest = v:match('^https://([%w%.%-]+)(/[%w%-%._~/%%%?=&#:+,;@!%$%*]*)$')
    if not host or host:find('..', 1, true) or host:sub(1, 1) == '.' or not host:find('.', 1, true) then return nil end
    host = host:lower()
    local hosts = cfg.AllowedHosts or {}
    if #hosts == 0 then return nil end
    for _, h in ipairs(hosts) do
        h = tostring(h):lower()
        if host == h or host:sub(-(#h + 1)) == '.' .. h then return 'https://' .. host .. rest end
    end
    return nil
end

-- Reports from civilians' clients (callouts, auto calls, /911) are about where the caller is.
local REPORT_RADIUS = 150.0
function PFMdtAccess.NearCaller(src, coords)
    if not src or src == 0 then return true end -- server-side exports
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local p = GetEntityCoords(ped)
    return #(vector3(p.x, p.y, p.z) - vector3(coords.x, coords.y, coords.z)) <= REPORT_RADIUS
end

-- simple per-player rate limit: true when allowed
local _rate = {}
function PFMdtAccess.AllowRate(src, key, ms)
    _rate[src] = _rate[src] or {}
    local now = GetGameTimer()
    if _rate[src][key] and now - _rate[src][key] < ms then return false end
    _rate[src][key] = now
    return true
end
AddEventHandler('playerDropped', function() _rate[source] = nil end)

-- Clip a client string: plain text, no control characters, at most maxLen bytes.
function PFMdtAccess.Text(v, maxLen)
    if type(v) ~= 'string' and type(v) ~= 'number' then return '' end
    local s = tostring(v):gsub('[%c]', ' ')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

-- pfm-core calls a callback with its own cb, which reaches this resource as a callable table (a
-- FiveM function reference), never as a Lua function: test it with this, not type(cb) == 'function'.
local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end
PFMdtAccess.Callable = callable

-- Callbacks and net events that change something: on duty and the action's grade
-- (Config.Permissions) are checked here, before the handler runs. `deny` is what a refused callback
-- answers when its page expects something other than { success = false }.
local ACTIONS = {
    -- sentencing and custody
    ['pf_mdt:createSentence'] = { action = 'sentence' },
    ['pf_mdt:postBail'] = { action = 'bail' },
    ['pf_mdt:printCitationPaper'] = { action = 'printCitation' },
    ['pf_mdt:prison:Jail'] = { action = 'prisonManage' },
    ['pf_mdt:prison:Unjail'] = { action = 'prisonManage' },
    ['pf_mdt:prison:EditSentence'] = { action = 'prisonManage' },
    -- records
    ['pf_mdt:createWarrant'] = { action = 'createWarrant' },
    ['pf_mdt:updateWarrantStatus'] = { action = 'serveWarrant' },
    ['pf_mdt:createIncident'] = { action = 'createIncident' },
    ['pf_mdt:updateIncident'] = { action = 'createIncident' },
    ['pf_mdt:closeIncident'] = { action = 'createIncident' },
    ['pf_mdt:deleteIncident'] = { action = 'deleteIncidents' },
    ['pf_mdt:createReport'] = { action = 'createReport' },
    ['pf_mdt:approveReport'] = { action = 'approveReport' },
    ['pf_mdt:deleteReport'] = { action = 'deleteReports' },
    ['pf_mdt:createFTOReport'] = { action = 'ftoReports' },
    ['pf_mdt:saveFtoDraft'] = { action = 'ftoReports' },
    ['pf_mdt:submitFtoReport'] = { action = 'ftoReports' },
    ['pf_mdt:reviewFtoReport'] = { action = 'ftoReports' },
    ['pf_mdt:addCitizenNote'] = { action = 'citizenRecords' },
    ['pf_mdt:addCitizenFlag'] = { action = 'citizenRecords' },
    ['pf_mdt:removeCitizenFlag'] = { action = 'citizenRecords' },
    ['pf_mdt:addVehicleNote'] = { action = 'vehicleRecords' },
    ['pf_mdt:addVehicleFlag'] = { action = 'vehicleRecords' },
    ['pf_mdt:removeVehicleFlag'] = { action = 'vehicleRecords' },
    ['pf_mdt:addVehicleStrike'] = { action = 'vehicleRecords' },
    ['pf_mdt:clearVehicleStrikes'] = { action = 'clearVehicleStrikes' },
    ['pf_mdt:suspendLicense'] = { action = 'suspendLicense' },
    ['pf_mdt:unsuspendLicense'] = { action = 'unsuspendLicense' },
    ['pf_mdt:removeLicense'] = { action = 'removeLicense' },
    ['pf_mdt:updateProfilePicture'] = { action = 'photos' },
    ['pf_mdt:updateVehiclePhoto'] = { action = 'photos' },
    ['pf_mdt:registerWeapon'] = { action = 'weapons' },
    ['pf_mdt:createManualWeapon'] = { action = 'manualEntries' },
    ['pf_mdt:createManualCitizen'] = { action = 'manualEntries' },
    ['pf_mdt:createManualVehicle'] = { action = 'manualEntries' },
    ['pf_mdt:server:AddIncidentEvidencePhoto'] = { action = 'addEvidence' },
    ['pf_mdt:createEvidence'] = { action = 'addEvidence' },
    ['pf_mdt:server:DeleteEvidence'] = { action = 'deleteEvidence' },
    ['pf_mdt:createTemplate'] = { action = 'templates' },
    ['pf_mdt:updateTemplate'] = { action = 'templates' },
    ['pf_mdt:deleteTemplate'] = { action = 'templates' },
    -- dispatch
    ['pf_mdt_dispatch:server:CreateCall'] = { action = 'dispatch' },
    ['pf_mdt_dispatch:server:AcceptCall'] = { action = 'dispatch' },
    ['pf_mdt_dispatch:server:CompleteCall'] = { action = 'dispatch' },
    ['pf_mdt_dispatch:server:DeleteCall'] = { action = 'deleteCall' },
    ['pf_mdt:dispatch:clearCall'] = { action = 'clearCall', deny = false },
    -- department management
    ['pf_mdt_dispatch:server:CreateBulletin'] = { action = 'bulletin' },
    ['pf_mdt:createCharge'] = { action = 'manageCharges' },
    ['pf_mdt:updateCharge'] = { action = 'manageCharges' },
    ['pf_mdt:deleteCharge'] = { action = 'manageCharges' },
    ['pf_mdt:roster:updateRowCb'] = { action = 'manageRoster' },
    ['pf_mdt:roster:addRowCb'] = { action = 'manageRoster' },
    ['pf_mdt:roster:deleteRowCb'] = { action = 'manageRoster' },
    ['pf_mdt:roster:resetCb'] = { action = 'manageRoster' },
    ['pf_mdt:roster:updateRow'] = { action = 'manageRoster' },
    ['pf_mdt:roster:addRow'] = { action = 'manageRoster' },
    ['pf_mdt:roster:deleteRow'] = { action = 'manageRoster' },
    ['pf_mdt:officers:fire'] = { action = 'manageOfficers' },
    ['pf_mdt:officers:updateEmployment'] = { action = 'manageOfficers' },
    ['pf_mdt:officers:setFlags'] = { action = 'manageOfficers' },
    ['pf_mdt:officers:addDiscipline'] = { action = 'manageOfficers' },
    ['pf_mdt:officers:updateDiscipline'] = { action = 'manageOfficers' },
    ['pf_mdt:createSOP'] = { action = 'manageSOPs' },
    ['pf_mdt:updateSOP'] = { action = 'manageSOPs' },
    ['pf_mdt:deleteSOP'] = { action = 'manageSOPs' },
}
PFMdtAccess.Actions = ACTIONS

local DENY_TEXT = {
    off_duty = 'You must be on duty to do that',
    no_permission = 'Your rank cannot do that',
}

-- The MDT owner flag (metadata.isOwner) keeps its old bypass of rank rules, never of duty.
local function ownerBypass(src)
    local P = QBCore.Functions.GetPlayer(tonumber(src) or src)
    local meta = P and P.PlayerData and P.PlayerData.metadata
    return type(meta) == 'table' and (meta.isOwner == true or meta.isowner == true or meta.owner == true)
end

local function refusal(src, name)
    if not PFMdtAccess.IsOfficer(src) then return 'no_access' end
    local entry = ACTIONS[name]
    if not entry then return nil end
    local ok, err = PFMdtAccess.Can(src, entry.action)
    if ok then return nil end
    if err == 'no_permission' and ownerBypass(src) then return nil end
    return err
end

local origCreateCallback = QBCore.Functions.CreateCallback
QBCore.Functions.CreateCallback = function(name, fn, ...)
    if callable(fn) and isGated(name) then
        local inner = fn
        fn = function(src, cb, ...)
            local err = refusal(src, name)
            if err then
                local entry = ACTIONS[name]
                if callable(cb) then
                    if entry and entry.deny ~= nil and err ~= 'no_access' then cb(entry.deny)
                    else cb({ success = false, error = err, message = DENY_TEXT[err] }) end
                end
                return
            end
            return inner(src, cb, ...)
        end
    end
    return origCreateCallback(name, fn, ...)
end

local origRegisterNetEvent = RegisterNetEvent
RegisterNetEvent = function(name, fn, ...)
    if callable(fn) and isGated(name) then
        local inner = fn
        fn = function(...)
            local src = source
            local err = refusal(src, name)
            if err then
                if DENY_TEXT[err] then TriggerClientEvent('QBCore:Notify', src, DENY_TEXT[err], 'error') end
                return
            end
            return inner(...)
        end
    end
    return origRegisterNetEvent(name, fn, ...)
end
RegisterServerEvent = RegisterNetEvent
