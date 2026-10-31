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

local function viewList(list, cid, job)
    local out = {}
    for _, r in ipairs(list) do out[#out + 1] = PFServices.PublicView(r, cid, job) end
    return out
end

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
    local ok, rows = pcall(function()
        return MySQL.query.await([[SELECT business_id, business_name, business_type, business_status, location_x, location_y,
            location_address, license_status FROM pf_gov_businesses ORDER BY business_name LIMIT 300]])
    end)
    local out = {}
    for _, r in ipairs(ok and rows or {}) do
        out[#out + 1] = {
            id = r.business_id, name = r.business_name, type = r.business_type,
            open = r.business_status ~= 'closed', address = r.location_address,
            hasLocation = r.location_x ~= nil and r.location_y ~= nil,
        }
    end
    directoryCache = { at = os.time(), rows = out, coords = {} }
    for _, r in ipairs(ok and rows or {}) do
        if r.location_x and r.location_y then directoryCache.coords[r.business_id] = { x = tonumber(r.location_x), y = tonumber(r.location_y) } end
    end
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
            return job ~= nil and dispatchJobs()[job.name] == true
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
                requests = viewList(PFServices.ListForJob(job.name, true), cid, job.name),
                mine = viewList(PFServices.ListForAssignee(cid), cid, job.name),
                kinds = kinds,
            }
        end,
        accept = function(src, p) return PFServices.AcceptRequest(src, p.id) end,
        release = function(src, p) return PFServices.ReleaseRequest(src, p.id) end,
        complete = function(src, p) return PFServices.CompleteRequest(src, p.id, p.proof) end,
        cancel = function(src, p) return PFServices.CancelRequest(src, p.id, 'cancelled_by_job') end,
        waypoint = function(src, p)
            local Player = playerOf(src)
            local req = PFServices.GetRequest(p.id)
            if not Player or not req or req.job ~= (Player.PlayerData.job or {}).name then return { ok = false, error = 'not_found' } end
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
        request = function(src, p) return PFServices.CitizenRequest(src, p.kind, p.details) end,
        mine = function(src)
            local Player = playerOf(src)
            if not Player then return { ok = false, error = 'no_player' } end
            local cid = Player.PlayerData.citizenid
            return { ok = true, requests = viewList(PFServices.ListForCitizen(cid), cid, nil) }
        end,
        cancel = function(src, p) return PFServices.CancelRequest(src, p.id, 'cancelled_by_requester') end,
        confirm = function(src, p) return PFServices.ConfirmRequest(src, p.id) end,
    })
end
