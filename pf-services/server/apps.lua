-- The two platform apps (pf-devices) on the tablet and the computer:
--   Dispatch — workers of a job see the requests for their job, accept, navigate, complete.
--   Services — any citizen asks for a tow, a mechanic, a taxi, a medic or the police where they stand.

PFServices = PFServices or {}

local function QB() return exports['pfm-core']:GetCoreObject() end

local function playerOf(src) return QB().Functions.GetPlayer(tonumber(src)) end

local function dispatchJobs()
    local jobs = {}
    for _, def in pairs(PFServices.GetRequestKinds()) do
        if type(def.job) == 'table' then for _, j in ipairs(def.job) do jobs[j] = true end else jobs[def.job] = true end
    end
    for _, j in ipairs(Config.DispatchJobs or {}) do jobs[j] = true end
    return jobs
end

local function onDutyCounts()
    local counts = {}
    for _, Player in pairs(QB().Functions.GetQBPlayers() or {}) do
        local job = Player.PlayerData and Player.PlayerData.job
        if job and job.onduty then counts[job.name] = (counts[job.name] or 0) + 1 end
    end
    return counts
end

-- The visibility rule of the Dispatch list: a request is for a job when it was made for that job
-- or its kind lists the job (mechanic.roadside: every mechanic shop). Every per-request action uses it.
local function worksOn(jobName, req)
    if type(jobName) ~= 'string' or type(req) ~= 'table' then return false end
    if req.job == jobName then return true end
    local def = PFServices.GetRequestKind(req.kind)
    if not def then return false end
    local jobs = type(def.job) == 'table' and def.job or { def.job }
    for _, j in ipairs(jobs) do if j == jobName then return true end end
    return false
end
PFServices.WorksOn = worksOn

-- City Hall business requests belong to pf-government: claiming one needs the permission its
-- Business Requests app checks for that kind (pf-government/server/apps/requests.lua, KINDS[kind].perm).
-- A gov.request.* kind not listed here, or pf-government not running, is never claimable here.
local GOV_REQUEST_PERMS = {
    ['gov.request.slot'] = 'businesses',
    ['gov.request.inspection'] = 'businesses',
    ['gov.request.license'] = 'licenses',
    ['gov.request.delivery_zone'] = 'businesses',
}

local function isGovRequestKind(kind) return type(kind) == 'string' and kind:sub(1, 12) == 'gov.request.' end

local function mayClaim(src, kind)
    if not isGovRequestKind(kind) then return true end
    local perm = GOV_REQUEST_PERMS[kind]
    if not perm or GetResourceState('pf-government') ~= 'started' then return false end
    local ok, res = pcall(function() return exports['pf-government']:HasPermission(src, perm) end)
    return ok and res == true
end
PFServices.MayClaimFromDispatch = mayClaim

local function viewList(list, cid, job, src)
    local out, claim = {}, {}
    for _, r in ipairs(list) do
        local v = PFServices.PublicView(r, cid, job)
        if v and src ~= nil then
            if claim[r.kind] == nil then claim[r.kind] = mayClaim(src, r.kind) end
            v.canClaim = claim[r.kind]
        end
        out[#out + 1] = v
    end
    return out
end

-- RPC results carry the public view of the request, never the row (requester citizen id, meta).
-- `asWorker` = the Dispatch app (the viewer's job counts); the Services app views as a citizen.
local function viewed(src, res, asWorker)
    if type(res) ~= 'table' or type(res.request) ~= 'table' then return res end
    local Player = playerOf(src)
    local pd = Player and Player.PlayerData or {}
    local out = {}
    for k, v in pairs(res) do out[k] = v end
    out.request = PFServices.PublicView(res.request, pd.citizenid, asWorker and pd.job and pd.job.name or nil)
    return out
end
PFServices.ViewedResult = viewed

-- City Directory: registered businesses (government registry) and the public services on duty.
local DIRECTORY_SERVICES = {
    { job = 'police', label = 'Police', icon = '🚓' },
    { job = 'ambulance', label = 'EMS', icon = '🚑' },
    { job = 'mechanic', label = 'LS Customs', icon = '🔧' },
    { job = 'bennys', label = "Benny's", icon = '🛠️' },
    { job = 'beeker', label = "Beeker's", icon = '🏁' },
    { job = 'tow', label = 'Towing', icon = '🛻' },
    { job = 'taxi', label = 'Taxi', icon = '🚕' },
    { job = 'reporter', label = 'Weazel News', icon = '📰' },
    { job = 'realestate', label = 'Real Estate', icon = '🏠' },
    { job = 'cardealer', label = 'Car Dealer', icon = '🚗' },
    { job = 'government', label = 'City Hall', icon = '🏛️' },
}

local directoryCache = { at = 0, rows = {} }
local function directoryBusinesses()
    if os.time() - directoryCache.at < 30 then return directoryCache.rows end
    -- the registry belongs to pf-government: read it through its export, never its table
    local list = {}
    if GetResourceState('pf-government') == 'started' then
        local ok, res = pcall(function() return exports['pf-government']:ListBusinesses({ limit = 300 }) end)
        if ok and type(res) == 'table' then list = res end
    end
    local out, coords = {}, {}
    for _, b in ipairs(list) do
        out[#out + 1] = {
            id = b.id, name = b.name, type = b.type,
            open = b.status ~= 'closed', address = b.address,
            hasLocation = b.coords ~= nil,
        }
        if b.coords then coords[b.id] = { x = b.coords.x, y = b.coords.y } end
    end
    directoryCache = { at = os.time(), rows = out, coords = coords }
    return out
end

function PFServices.RegisterApps()
    local me = GetCurrentResourceName()
    local devices = exports['pf-devices']

    devices:RegisterApp({
        id = 'directory', name = 'Directory', icon = '🗂️',
        entry = 'html/apps/directory.js', styles = { 'html/apps/services.css' },
        category = 'apps', order = 7, access = { anyone = true },
        description = 'Businesses in the city and the services on duty',
    })
    devices:RegisterAppHandlers('directory', {
        list = function()
            local counts = onDutyCounts()
            local services = {}
            for _, s in ipairs(DIRECTORY_SERVICES) do
                services[#services + 1] = { job = s.job, label = s.label, icon = s.icon, onDuty = counts[s.job] or 0 }
            end
            return { ok = true, services = services, businesses = directoryBusinesses() }
        end,
        waypoint = function(src, p)
            directoryBusinesses()
            local c = type(p) == 'table' and type(p.id) == 'string' and directoryCache.coords and directoryCache.coords[p.id]
            if not c then return { ok = false, error = 'no_location' } end
            TriggerClientEvent('pf-services:client:waypoint', src, c.x, c.y)
            return { ok = true }
        end,
    })

    devices:RegisterApp({
        id = 'dispatch', name = 'Dispatch', icon = '📟',
        entry = 'html/apps/dispatch.js', styles = { 'html/apps/services.css' },
        category = 'jobs', order = 5, access = { handler = true },
        description = 'Requests from other jobs and citizens for your job',
        window = { width = 980, height = 660 },
    })
    devices:RegisterApp({
        id = 'services', name = 'Services', icon = '🆘',
        entry = 'html/apps/services.js', styles = { 'html/apps/services.css' },
        category = 'apps', order = 6, access = { anyone = true },
        description = 'Call a tow truck, a mechanic, a taxi, a medic or the police',
    })

    devices:RegisterAppHandlers('dispatch', {
        __access = function(src)
            local Player = playerOf(src)
            local job = Player and Player.PlayerData.job
            if not job or dispatchJobs()[job.name] ~= true then return false end
            -- police and EMS dispatch is their MDT app while it runs
            local mdt = Config.MdtJobs and Config.MdtJobs[job.name]
            if mdt and PFServices.MdtResourceFor and PFServices.MdtResourceFor(mdt) then return false end
            return true
        end,
        list = function(src)
            local Player = playerOf(src)
            if not Player then return { ok = false, error = 'no_player' } end
            local job = Player.PlayerData.job or {}
            local cid = Player.PlayerData.citizenid
            local kinds = {}
            for _, kind in ipairs(PFServices.KindsForJob(job.name)) do
                local def = PFServices.GetRequestKind(kind)
                kinds[#kinds + 1] = { kind = kind, label = def.label, icon = def.icon, reward = def.reward, description = def.description }
            end
            table.sort(kinds, function(a, b) return a.label < b.label end)
            return {
                ok = true, job = job.name, jobLabel = job.label, onduty = job.onduty == true,
                requests = viewList(PFServices.ListForJob(job.name, true), cid, job.name, src),
                mine = viewList(PFServices.ListForAssignee(cid), cid, job.name, src),
                kinds = kinds,
            }
        end,
        accept = function(src, p)
            local req = type(p) == 'table' and PFServices.GetRequest(p.id) or nil
            if not req then return { ok = false, error = 'not_found' } end
            -- City Hall requests: only staff with the government app's permission for the kind
            if not mayClaim(src, req.kind) then return { ok = false, error = 'no_permission' } end
            return viewed(src, PFServices.AcceptRequest(src, req.id), true)
        end,
        release = function(src, p) return viewed(src, PFServices.ReleaseRequest(src, p.id), true) end,
        complete = function(src, p)
            local req = type(p) == 'table' and PFServices.GetRequest(p.id) or nil
            if not req then return { ok = false, error = 'not_found' } end
            if not mayClaim(src, req.kind) then return { ok = false, error = 'no_permission' } end
            return viewed(src, PFServices.CompleteRequest(src, req.id, p.proof), true)
        end,
        cancel = function(src, p) return viewed(src, PFServices.CancelRequest(src, p.id, 'cancelled_by_job'), true) end,
        waypoint = function(src, p)
            local Player = playerOf(src)
            local req = type(p) == 'table' and PFServices.GetRequest(p.id) or nil
            if not Player or not req or not worksOn((Player.PlayerData.job or {}).name, req) then return { ok = false, error = 'not_found' } end
            if not req.coords then return { ok = false, error = 'no_location' } end
            TriggerClientEvent('pf-services:client:waypoint', src, req.coords.x, req.coords.y)
            return { ok = true, coords = req.coords }
        end,
    })

    devices:RegisterAppHandlers('services', {
        kinds = function(src)
            local counts = onDutyCounts()
            local out = {}
            for kind, def in pairs(PFServices.GetRequestKinds()) do
                if def.citizen then
                    local job = type(def.job) == 'table' and def.job[1] or def.job
                    out[#out + 1] = {
                        kind = kind, label = def.label, icon = def.icon, description = def.description,
                        fee = (def.payer == 'requester') and def.reward or 0, available = (counts[job] or 0) > 0,
                        onDuty = counts[job] or 0,
                    }
                end
            end
            table.sort(out, function(a, b) return a.label < b.label end)
            return { ok = true, kinds = out }
        end,
        request = function(src, p) return viewed(src, PFServices.CitizenRequest(src, p.kind, p.details), false) end,
        mine = function(src)
            local Player = playerOf(src)
            if not Player then return { ok = false, error = 'no_player' } end
            local cid = Player.PlayerData.citizenid
            return { ok = true, requests = viewList(PFServices.ListForCitizen(cid), cid, nil) }
        end,
        cancel = function(src, p) return viewed(src, PFServices.CancelRequest(src, p.id, 'cancelled_by_requester'), false) end,
        confirm = function(src, p) return viewed(src, PFServices.ConfirmRequest(src, p.id), false) end,
        dispute = function(src, p) return viewed(src, PFServices.DisputeRequest(src, p.id), false) end,
    })
end
