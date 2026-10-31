-- PF Services: exports, start-up, police dispatch from city events, sweeps.

PFServices = PFServices or {}

exports('Emit', function(kind, data, opts)
    opts = type(opts) == 'table' and opts or {}
    opts.resource = opts.resource or GetInvokingResource()
    local ev, err = PFServices.Emit(kind, data, opts)
    return ev and ev.id or nil, err
end)
exports('RegisterEventKind', function(kind, def) return PFServices.RegisterEventKind(kind, def) end)
exports('GetEventKind', function(kind) return PFServices.GetEventKind(kind) end)
exports('GetEventKinds', function() return PFServices.GetEventKinds() end)
exports('GetRecentEvents', function(filter) return PFServices.GetRecentEvents(filter) end)

exports('RegisterRequestKind', function(kind, def) return PFServices.RegisterRequestKind(kind, def) end)
exports('RegisterRequestHandler', function(kind, handler) return PFServices.RegisterRequestHandler(kind, handler, GetInvokingResource()) end)
exports('GetRequestKind', function(kind) return PFServices.GetRequestKind(kind) end)
exports('CreateRequest', function(opts) return PFServices.CreateRequest(opts) end)
exports('GetRequest', function(id) return PFServices.GetRequest(id) end)
exports('FindOpenByRef', function(t, id) return PFServices.FindOpenByRef(t, id) end)
exports('AcceptRequest', function(src, id) return PFServices.AcceptRequest(src, id) end)
exports('CompleteRequest', function(src, id, proof) return PFServices.CompleteRequest(src, id, proof) end)
exports('CancelRequest', function(src, id, reason) return PFServices.CancelRequest(src, id, reason) end)
exports('CloseByRef', function(t, id, status, reason) return PFServices.CloseByRef(t, id, status, reason) end)
exports('ListForJob', function(job, includeClosed) return PFServices.ListForJob(job, includeClosed) end)
exports('PublicView', function(req, cid, job) return PFServices.PublicView(req, cid, job) end)

-- Events marked police = true put a police dispatch request on the map (one per dedupe/event).
PFServices.OnEvent(function(event)
    if not event.police then return end
    local def = PFServices.GetEventKind(event.kind) or {}
    PFServices.CreateRequest({
        kind = 'police.assist',
        title = event.title or def.label or event.kind,
        details = event.data and event.data.details or nil,
        coords = event.coords,
        ref = { type = 'event', id = tostring(event.data and event.data.ref or event.id or event.kind) },
        from = { type = 'system', id = event.kind, name = def.label },
        meta = { event = event.id, kind = event.kind },
    })
end)

-- Police and EMS requests go onto their MDT's dispatch board (the MDT is their dispatch app).
local function startedOf(list)
    for _, res in ipairs(list or {}) do
        if GetResourceState(res) == 'started' then return res end
    end
    return nil
end
PFServices.MdtResourceFor = startedOf

AddEventHandler('pf-services:requestChanged', function(req, what)
    if what ~= 'created' or type(req) ~= 'table' then return end
    local route = Config.MdtDispatch and Config.MdtDispatch[req.kind]
    local mdt = route and startedOf(route.resources)
    if not mdt then return end
    local def = PFServices.GetRequestKind(req.kind) or {}
    pcall(function()
        exports[mdt]:CreateDispatchCall({
            title = req.title or def.label or req.kind,
            description = req.details,
            code = route.code,
            priority = route.priority or 2,
            coords = req.coords,
            locationLabel = req.title,
            createdBy = req.from and req.from.name or 'system',
            callType = req.kind,
            status = 'pending',
        })
    end)
end)

local function start()
    local ok, err = pcall(function() return exports['pfm-core']:RunMigrations(GetCurrentResourceName(), PFServices.Migrations) end)
    if not ok then print('^1[pf-services]^7 migrations failed: ' .. tostring(err)) end
    PFServices.PruneEvents()
    if GetResourceState('pf-devices') == 'started' then PFServices.RegisterApps() end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        start()
    elseif resource == 'pf-devices' then
        PFServices.RegisterApps()
    end
end)

-- pf-devices raises this when it (re)starts
AddEventHandler('pf-devices:server:ready', function()
    PFServices.RegisterApps()
end)

CreateThread(function()
    while true do
        Wait((Config.Requests.expireCheckSeconds or 30) * 1000)
        local ok, err = pcall(PFServices.SweepRequests)
        if not ok then print('^1[pf-services]^7 sweep failed: ' .. tostring(err)) end
    end
end)
