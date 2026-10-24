local QBCore = exports['pfm-core']:GetCoreObject()

local currentWorkTruck = nil -- { name, plate }
local depotComputerEntities = {} -- { [depotId]=entity }

local activeJob = nil
local jobTrailer = nil
local jobTrailerNetId = nil
local jobTrailerModel = nil
local jobTrailerBlip = nil
local objectiveBlip = nil
local jobStage = nil -- 'pickup' | 'delivery' | 'return'
local delivered = false

-- Forward declarations
local vec3FromStop

local function PostNUI(payload)
    -- Broadcast to local NUI (computer embed) and tablet (if present).
    -- This avoids the computer app getting stuck without pushed updates when pf-tablet is running.
    SendNUIMessage(payload)
    if GetResourceState('pf-tablet') == 'started' and exports and exports['pf-tablet'] and exports['pf-tablet'].SendNuiMessage then
        pcall(function()
            exports['pf-tablet']:SendNuiMessage(payload)
        end)
    end
end

local function computeUiStatus(job)
    if not job or type(job) ~= 'table' then return 'Assigned' end
    if delivered or jobStage == 'return' or (job.delivered == true) then
        return 'Completed'
    end
    if jobStage == 'pickup' then
        return 'En Route to Pickup'
    end
    if jobStage == 'delivery' then
        local delivery = vec3FromStop(job, 2)
        if delivery then
            local ped = PlayerPedId()
            local p = GetEntityCoords(ped)
            local dist = #(p - delivery)
            if dist < 120.0 then
                return 'Delivering'
            end
        end
        return 'In Transit'
    end
    return 'Assigned'
end

local function toUiJob(job)
    if type(job) ~= 'table' then return nil end
    local dist = tonumber(job.distanceMi or 0) or 0
    local payout = tonumber(job.payoutNet or job.payout or 0) or 0
    return {
        id = job.id,
        title = job.title,
        cargoType = job.cargoType,
        cargoQuantity = job.cargoQuantity,
        cargoStatus = 'Secured',
        pickup = job.pickup,
        dropoff = job.dropoff,
        totalDistanceMi = dist,
        distanceRemainingMi = dist,
        estimatedPayout = payout,
        currentPayout = payout,
        requiredTrailer = job.requiredTrailer,
        status = computeUiStatus(job),
        stops = job.stops,
    }
end

local lastUiStatus = nil
local function syncActiveJobToNui(full)
    if not activeJob then
        lastUiStatus = nil
        PostNUI({ action = 'pf-trucking:setActiveJob', job = nil })
        return
    end

    local status = computeUiStatus(activeJob)
    if full then
        PostNUI({ action = 'pf-trucking:setActiveJob', job = toUiJob(activeJob) })
        lastUiStatus = status
        return
    end

    if status ~= lastUiStatus then
        lastUiStatus = status
        PostNUI({ action = 'pf-trucking:updateActiveJob', job = { status = status } })
    end
end

local function hudShow(title, subtitle)
    if GetResourceState('pf-scoreboard') == 'started' then
        local ok = pcall(function()
            exports['pf-scoreboard']:ShowScoreboard(title, subtitle, '')
        end)
        if ok then return end
    end
    TriggerEvent('pf-scoreboard:client:show', title, subtitle, '')
end

local function hudUpdate(title, subtitle)
    if GetResourceState('pf-scoreboard') == 'started' then
        local ok = pcall(function()
            exports['pf-scoreboard']:UpdateScoreboard(title, subtitle, '')
        end)
        if ok then return end
    end
    TriggerEvent('pf-scoreboard:client:update', title, subtitle, '')
end

local function hudHide()
    if GetResourceState('pf-scoreboard') == 'started' then
        local ok = pcall(function()
            exports['pf-scoreboard']:HideScoreboard()
        end)
        if ok then return end
    end
    TriggerEvent('pf-scoreboard:client:hide')
end

local function updateTruckingHud()
    if not activeJob then
        hudHide()
        return
    end

    local title = 'Trucking'
    local jobTitle = type(activeJob) == 'table' and activeJob.title or nil
    if jobTitle and jobTitle ~= '' then
        title = ('Trucking – %s'):format(jobTitle)
    end

    local subtitle = ''
    if jobStage == 'pickup' then
        subtitle = 'Objective: Pick up and attach the job trailer'
    elseif jobStage == 'delivery' then
        subtitle = 'Objective: Deliver the trailer to the destination'
    elseif jobStage == 'return' then
        subtitle = 'Objective: Return the work truck to the yard'
    elseif delivered then
        subtitle = 'Objective: Complete the job'
    else
        subtitle = 'Objective: Follow the contract stops'
    end

    hudUpdate(title, subtitle)
end

vec3FromStop = function(job, stopIndex)
    if type(job) ~= 'table' or type(job.stops) ~= 'table' then return nil end
    local stop = job.stops[stopIndex]
    local c = stop and stop.coords or nil
    if type(c) ~= 'table' or not c.x or not c.y or not c.z then return nil end
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
end

-- Forward declaration (used by getNearestDepot before assignment below).
local toVector4

local function getNearestDepot()
    local depots = Config and Config.WorkTruck and Config.WorkTruck.Depots or nil
    if type(depots) ~= 'table' then return nil end
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local best, bestD
    for _, d in ipairs(depots) do
        local r = d and d.returnCoords and toVector4(d.returnCoords) or nil
        if r then
            local dist = #(p - vector3(r.x, r.y, r.z))
            if not bestD or dist < bestD then
                bestD = dist
                best = d
            end
        end
    end
    return best
end

local function safeNotify(msg, kind)
    if QBCore and QBCore.Functions and QBCore.Functions.Notify then
        QBCore.Functions.Notify(msg, kind or 'primary')
    end
end

toVector4 = function(v)
    if not v then return nil end
    if type(v) == 'vector4' then return v end
    if type(v) == 'vector3' then return vector4(v.x, v.y, v.z, 0.0) end
    if type(v) == 'table' then
        local x = v.x or v[1] or 0.0
        local y = v.y or v[2] or 0.0
        local z = v.z or v[3] or 0.0
        local w = v.w or v[4] or v.h or v.heading or 0.0
        return vector4(x + 0.0, y + 0.0, z + 0.0, w + 0.0)
    end
    return nil
end

local function ensureModel(model)
    local m = model
    if type(m) == 'string' then m = joaat(m) end
    if not m or m == 0 then return false, nil end
    if not HasModelLoaded(m) then
        RequestModel(m)
        local deadline = GetGameTimer() + 5000
        while not HasModelLoaded(m) and GetGameTimer() < deadline do
            Wait(25)
        end
    end
    return HasModelLoaded(m), m
end

local function showHelpText(msg)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, 0)
end

local function platesMatch(a, b)
    if not a or not b then return false end
    local pa = tostring(a):gsub('%s+', ''):upper()
    local pb = tostring(b):gsub('%s+', ''):upper()
    return pa == pb
end

local function getJobPickupCoords(job)
    if type(job) ~= 'table' then return nil end
    local stops = job.stops
    if type(stops) ~= 'table' or not stops[1] or type(stops[1]) ~= 'table' then return nil end
    local c = stops[1].coords
    if type(c) == 'table' and c.x and c.y and c.z then
        return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    end
    return nil
end

local function getTrailerModelForJob(job)
    local label = type(job) == 'table' and job.requiredTrailer or nil
    if label and Config and Config.Trailers and Config.Trailers[label] then
        return Config.Trailers[label]
    end

    -- Fallback: try to infer based on common keywords.
    local s = tostring(label or ''):lower()
    if s:find('tanker') then return 'tanker' end
    if s:find('flat') then return 'trflat' end
    if s ~= '' then return 'trailers' end
    return 'trailers'
end

local function setTrailerOutline(entity, enabled)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if enabled then
        local c = (Config and Config.JobTrailer and Config.JobTrailer.OutlineColor) or { 1, 255, 158, 255 }
        if type(SetEntityDrawOutlineShader) == 'function' then
            -- Some builds support selecting the shader; harmless if unavailable.
            SetEntityDrawOutlineShader(1)
        end
        -- Some builds seem to want outline enabled before color is applied.
        SetEntityDrawOutline(entity, true)
        SetEntityDrawOutlineColor(c[1] or 1, c[2] or 255, c[3] or 158, c[4] or 255)
    else
        SetEntityDrawOutline(entity, false)
    end
end

local function cleanupJobTrailer()
    if jobTrailerBlip and jobTrailerBlip ~= 0 then
        RemoveBlip(jobTrailerBlip)
    end
    jobTrailerBlip = nil
    if jobTrailer and jobTrailer ~= 0 and DoesEntityExist(jobTrailer) then
        setTrailerOutline(jobTrailer, false)
        DeleteVehicle(jobTrailer)
    end
    jobTrailer = nil
    jobTrailerNetId = nil
    jobTrailerModel = nil
end

local function clearObjectiveBlip()
    if objectiveBlip and DoesBlipExist(objectiveBlip) then
        SetBlipRoute(objectiveBlip, false)
        RemoveBlip(objectiveBlip)
    end
    objectiveBlip = nil
end

local function applyObjectiveRoute(blip)
    if not blip or blip == 0 or not DoesBlipExist(blip) then return end
    SetBlipRoute(blip, true)
    -- 5 = Yellow (matches garbage job route)
    if SetBlipRouteColour then
        SetBlipRouteColour(blip, 5)
    end
end

local function refreshObjectiveRoute()
    -- Clear any coord objective blip.
    clearObjectiveBlip()

    if not activeJob or not jobStage then
        -- Also clear any route on the trailer blip.
        if jobTrailerBlip and DoesBlipExist(jobTrailerBlip) then
            SetBlipRoute(jobTrailerBlip, false)
        end
        return
    end

    if jobStage == 'pickup' then
        -- Route to the job trailer blip if available.
        if jobTrailerBlip and DoesBlipExist(jobTrailerBlip) then
            SetBlipColour(jobTrailerBlip, 5)
            applyObjectiveRoute(jobTrailerBlip)
        else
            local pickup = vec3FromStop(activeJob, 1)
            if pickup then
                objectiveBlip = AddBlipForCoord(pickup.x, pickup.y, pickup.z)
                SetBlipSprite(objectiveBlip, 479)
                SetBlipColour(objectiveBlip, 5)
                SetBlipScale(objectiveBlip, 0.85)
                SetBlipAsShortRange(objectiveBlip, false)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName('Pickup Trailer')
                EndTextCommandSetBlipName(objectiveBlip)
                applyObjectiveRoute(objectiveBlip)
            end
        end
    elseif jobStage == 'delivery' then
        if jobTrailerBlip and DoesBlipExist(jobTrailerBlip) then
            SetBlipRoute(jobTrailerBlip, false)
        end
        local delivery = vec3FromStop(activeJob, 2)
        if delivery then
            objectiveBlip = AddBlipForCoord(delivery.x, delivery.y, delivery.z)
            SetBlipSprite(objectiveBlip, 1)
            SetBlipColour(objectiveBlip, 5)
            SetBlipScale(objectiveBlip, 0.9)
            SetBlipAsShortRange(objectiveBlip, false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Deliver Trailer')
            EndTextCommandSetBlipName(objectiveBlip)
            applyObjectiveRoute(objectiveBlip)
        end
    elseif jobStage == 'return' then
        if jobTrailerBlip and DoesBlipExist(jobTrailerBlip) then
            SetBlipRoute(jobTrailerBlip, false)
        end
        local depot = getNearestDepot()
        local ret = depot and toVector4(depot.returnCoords) or nil
        if ret then
            objectiveBlip = AddBlipForCoord(ret.x, ret.y, ret.z)
            SetBlipSprite(objectiveBlip, 50)
            SetBlipColour(objectiveBlip, 5)
            SetBlipScale(objectiveBlip, 0.95)
            SetBlipAsShortRange(objectiveBlip, false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Return Work Truck')
            EndTextCommandSetBlipName(objectiveBlip)
            applyObjectiveRoute(objectiveBlip)
        end
    end
end

local function isJobTrailerConnectedToPlayer()
    if not jobTrailer or jobTrailer == 0 or not DoesEntityExist(jobTrailer) then return false end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return false end
    local hasTrailer, tr = GetVehicleTrailerVehicle(veh)
    return hasTrailer and tr and tr ~= 0 and tr == jobTrailer
end

local function ensureJobTrailerBlip()
    local hl = Config and Config.JobTrailer and Config.JobTrailer.Highlight or nil
    if not hl or hl.Enabled == false or hl.ShowBlip == false then return end
    if not jobTrailer or jobTrailer == 0 or not DoesEntityExist(jobTrailer) then return end
    if jobTrailerBlip and jobTrailerBlip ~= 0 then return end

    jobTrailerBlip = AddBlipForEntity(jobTrailer)
    if not jobTrailerBlip or jobTrailerBlip == 0 then
        jobTrailerBlip = nil
        return
    end

    SetBlipSprite(jobTrailerBlip, tonumber(hl.BlipSprite or 479) or 479)
    SetBlipColour(jobTrailerBlip, tonumber(hl.BlipColor or 2) or 2)
    SetBlipScale(jobTrailerBlip, tonumber(hl.BlipScale or 0.75) or 0.75)
    SetBlipAsShortRange(jobTrailerBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Job Trailer')
    EndTextCommandSetBlipName(jobTrailerBlip)
end

local function clearActiveJobClient()
    activeJob = nil
    jobStage = nil
    delivered = false
    clearObjectiveBlip()
    cleanupJobTrailer()
    hudHide()
    syncActiveJobToNui(true)
end

local function isSpawnClearAt(pos, radius)
    local r = tonumber(radius or 0.0) or 0.0
    if r <= 0.0 then return true end
    return not IsAnyVehicleNearPoint(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, r + 0.0)
end

local function findTrailerSpawnLocation(baseCoords)
    local clearRadius = (Config and Config.JobTrailer and tonumber(Config.JobTrailer.SpawnClearRadius or 0.0)) or 6.0
    local searchRadius = (Config and Config.JobTrailer and tonumber(Config.JobTrailer.NodeSearchRadius or 0.0)) or 80.0
    local maxAttempts = (Config and Config.JobTrailer and tonumber(Config.JobTrailer.MaxNodeAttempts or 0)) or 20

    local offsets = {
        { x = 0.0, y = 0.0, z = 0.0 },
        { x = 3.5, y = 0.0, z = 0.0 },
        { x = -3.5, y = 0.0, z = 0.0 },
        { x = 0.0, y = 6.0, z = 0.0 },
        { x = 0.0, y = -6.0, z = 0.0 },
    }

    for nth = 1, maxAttempts do
        local success, nodePos, heading = GetNthClosestVehicleNodeWithHeading(baseCoords.x, baseCoords.y, baseCoords.z, nth, 0, 0, 0)
        if not success or not nodePos then break end
        if #(nodePos - baseCoords) > searchRadius then break end

        for _, off in ipairs(offsets) do
            local world = GetOffsetFromCoordAndHeadingInWorldCoords(nodePos.x, nodePos.y, nodePos.z, heading + 0.0, off.x, off.y, off.z)
            local _, groundZ = GetGroundZFor_3dCoord(world.x + 0.0, world.y + 0.0, (world.z + 5.0), false)
            local spawnPos = vector3(world.x + 0.0, world.y + 0.0, (groundZ and groundZ + 0.05) or (world.z + 0.0))
            if isSpawnClearAt(spawnPos, clearRadius) then
                return vector4(spawnPos.x, spawnPos.y, spawnPos.z, heading + 0.0)
            end
        end
    end

    -- Fallback to the raw pickup position (best effort).
    return vector4(baseCoords.x, baseCoords.y, baseCoords.z, 0.0)
end

local function spawnTrailerForJob(job)
    local pickup = getJobPickupCoords(job)
    if not pickup then return false end

    local model = getTrailerModelForJob(job)
    local okModel, modelHash = ensureModel(model)
    if not okModel then
        safeNotify('Failed to load trailer model', 'error')
        return false
    end

    local spawn = nil
    if type(job) == 'table' and job.trailerSpawn then
        local forced = toVector4(job.trailerSpawn)
        if forced and forced.x and forced.y and forced.z then
            local clearRadius = (Config and Config.JobTrailer and tonumber(Config.JobTrailer.SpawnClearRadius or 0.0)) or 6.0
            local pos = vector3(forced.x + 0.0, forced.y + 0.0, forced.z + 0.0)
            local _, groundZ = GetGroundZFor_3dCoord(pos.x + 0.0, pos.y + 0.0, (pos.z + 5.0), false)
            if groundZ then
                pos = vector3(pos.x, pos.y, groundZ + 0.05)
            end
            if isSpawnClearAt(pos, clearRadius) then
                spawn = vector4(pos.x, pos.y, pos.z, forced.w + 0.0)
            else
                safeNotify('Pickup spawn point is blocked; using nearest safe node.', 'error')
            end
        end
    end

    if not spawn then
        spawn = findTrailerSpawnLocation(pickup)
    end
    if not spawn then return false end

    local veh = CreateVehicle(modelHash, spawn.x, spawn.y, spawn.z, spawn.w + 0.0, true, true)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        safeNotify('Failed to spawn trailer', 'error')
        return false
    end

    SetEntityHeading(veh, spawn.w + 0.0)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleHandbrake(veh, true)
    SetVehicleNumberPlateText(veh, 'PFTRAIL')

    jobTrailer = veh
    jobTrailerNetId = NetworkGetNetworkIdFromEntity(veh)
    jobTrailerModel = model

    ensureJobTrailerBlip()
    refreshObjectiveRoute()

    -- Enable outline glow if configured (like garbage job dumpsters)
    if Config.JobTrailer.Highlight and Config.JobTrailer.Highlight.Enabled then
        setTrailerOutline(veh, true)
    end
    return true
end

local function drawTrailerHighlightMarker(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    local hl = Config and Config.JobTrailer and Config.JobTrailer.Highlight or nil
    if not hl or hl.Enabled == false then return end
    local c = hl.MarkerColor or { 1, 255, 158, 220 }

    local coords = GetEntityCoords(entity)
    -- Arrow above trailer so the yellow objective cylinder remains visible on the ground.
    DrawMarker(
        2,
        coords.x, coords.y, coords.z + 2.4,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.9, 0.9, 0.9,
        c[1] or 1, c[2] or 255, c[3] or 158, c[4] or 220,
        false, true, 2, false, nil, nil, false
    )
end

-- Always keep the correct trailer visually identifiable.
CreateThread(function()
    while true do
        local wait = 1000

        if activeJob and jobTrailer and jobTrailer ~= 0 and DoesEntityExist(jobTrailer) then
            if isJobTrailerConnectedToPlayer() then
                if jobTrailerBlip and jobTrailerBlip ~= 0 then
                    RemoveBlip(jobTrailerBlip)
                end
                jobTrailerBlip = nil
            else
                ensureJobTrailerBlip()

                local ped = PlayerPedId()
                local p = GetEntityCoords(ped)
                local t = GetEntityCoords(jobTrailer)
                local dist = #(p - t)

                local hl = Config and Config.JobTrailer and Config.JobTrailer.Highlight or nil
                local range = (hl and tonumber(hl.MarkerRange or 0.0)) or 250.0
                if dist < range then
                    wait = 0
                    drawTrailerHighlightMarker(jobTrailer)
                else
                    wait = 700
                end
            end
        end

        Wait(wait)
    end
end)

local function setWaypointToStop(job, stopIndex)
    if type(job) ~= 'table' or type(job.stops) ~= 'table' then return false end
    local stop = job.stops[stopIndex]
    local c = stop and stop.coords or nil
    if type(c) ~= 'table' or not c.x or not c.y then return false end
    SetNewWaypoint(c.x + 0.0, c.y + 0.0)
    return true
end

local function drawObjectiveMarker(pos)
    local _, groundZ = GetGroundZFor_3dCoord(pos.x + 0.0, pos.y + 0.0, (pos.z + 5.0), false)
    local z = (groundZ and groundZ + 0.05) or (pos.z + 0.0)
    DrawMarker(
        1,
        pos.x, pos.y, z,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        3.5, 3.5, 0.85,
        255, 220, 0, 175,
        false, true, 2, false, nil, nil, false
    )
end

local function attemptDropoffAtDelivery(cb)
    if type(activeJob) ~= 'table' then
        if cb then cb({ ok = false, error = 'No active job' }) end
        return
    end

    local delivery = vec3FromStop(activeJob, 2)
    if not delivery then
        if cb then cb({ ok = false, error = 'No delivery location' }) end
        return
    end

    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    if #(p - delivery) > 8.0 then
        if cb then cb({ ok = false, error = 'Not at delivery point' }) end
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        if cb then cb({ ok = false, error = 'You must be in your truck' }) end
        return
    end

    local hasTrailer, tr = GetVehicleTrailerVehicle(veh)
    if not hasTrailer or not tr or tr == 0 then
        if cb then cb({ ok = false, error = 'No trailer attached' }) end
        return
    end

    if jobTrailer and jobTrailer ~= 0 and DoesEntityExist(jobTrailer) and tr ~= jobTrailer then
        if cb then cb({ ok = false, error = 'Wrong trailer attached' }) end
        return
    end

    -- Detach and remove the spawned trailer.
    DetachVehicleFromTrailer(veh)
    Wait(250)
    if tr and tr ~= 0 and DoesEntityExist(tr) then
        DeleteVehicle(tr)
    end
    cleanupJobTrailer()

    delivered = true
    if type(activeJob) == 'table' then activeJob.delivered = true end

    -- Reflect delivery in the dispatch app immediately (even though delivery is now marker-driven).
    syncActiveJobToNui(false)

    if currentWorkTruck and currentWorkTruck.plate then
        QBCore.Functions.TriggerCallback('pf-trucking:server:markDelivered', function(result)
            jobStage = 'return'
            safeNotify('Cargo delivered. Return the work truck to the yard.', 'success')
            updateTruckingHud()
            refreshObjectiveRoute()
            syncActiveJobToNui(false)
            if cb then cb(result or { ok = false }) end
        end)
        return
    end

    -- Owner truck: finish/payout now.
    QBCore.Functions.TriggerCallback('pf-trucking:server:completeActiveJob', function(result)
        if result and result.ok then
            clearActiveJobClient()
        end
        if cb then cb(result or { ok = false }) end
    end)
end

local function GetComputerPrograms()
    return {
        {
            id = 'pf-trucking',
            label = 'Trucking',
            icon = '🚚',
            external = true,
            resource = 'pf-trucking',
            jobRestricted = false,
            allowedJobs = {}
        }
    }
end

exports('GetComputerPrograms', GetComputerPrograms)

-- pf-tablet integration (external app entry)
local function GetTabletApps()
    return {
        {
            name = 'Trucking',
            icon = '🚚',
            enabled = true,
            external = { resource = 'pf-trucking', app = 'trucking' }
        }
    }
end

exports('GetTabletApps', GetTabletApps)

-- Called by pf-computer (NUI) when a user launches the program.
RegisterNUICallback('program:pf-trucking:open', function(data, cb)
    cb({
        ok = true,
        url = 'https://cfx-nui-pf-trucking/html/index.html?embed=1&device=computer'
    })
end)

-- UI action callbacks (UI-only resource: emits client events for other scripts to implement)
local function ok(cb)
    if cb then cb({ ok = true }) end
end

local function tryCloseComputerUi()
    if GetResourceState('pf-computer') ~= 'started' then return end
    if not exports or not exports['pf-computer'] or not exports['pf-computer'].CloseComputer then return end
    pcall(function()
        exports['pf-computer']:CloseComputer()
    end)
end

RegisterNUICallback('pf-trucking:acceptContract', function(data, cb)
    local contract = data and data.contract or nil
    local contractId = contract and contract.id or nil
    if not contractId then
        cb({ ok = false, error = 'Missing contract id' })
        return
    end

    QBCore.Functions.TriggerCallback('pf-trucking:server:claimContract', function(result)
        TriggerEvent('pf-trucking:client:acceptContract', (result and result.job) or contract)
        cb(result or { ok = false, error = 'No response' })
    end, contractId)
end)

RegisterNUICallback('pf-trucking:getContracts', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-trucking:server:getContracts', function(result)
        if result and result.ok and result.activeJob and (not activeJob or (activeJob and activeJob.id ~= result.activeJob.id)) then
            TriggerEvent('pf-trucking:client:setActiveJob', result.activeJob)
        end
        cb(result or { ok = false })
    end)
end)

RegisterNetEvent('pf-trucking:client:contractsUpdated', function(contracts)
    if type(contracts) ~= 'table' then return end
    PostNUI({ action = 'pf-trucking:setContracts', contracts = contracts })
end)

RegisterNUICallback('pf-trucking:setGps', function(data, cb)
    -- We don't use player waypoints for objective guidance.
    -- Re-assert the stage objective route (yellow) like other pf jobs.
    refreshObjectiveRoute()
    cb({ ok = true })
end)

RegisterNUICallback('pf-trucking:cancelJob', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-trucking:server:cancelActiveJob', function(result)
        TriggerEvent('pf-trucking:client:cancelJob', data and data.job or nil)
        cb(result or { ok = false, error = 'No response' })
    end)
end)

RegisterNUICallback('pf-trucking:startLoading', function(data, cb)
    TriggerEvent('pf-trucking:client:startLoading', data and data.job or nil)
    ok(cb)
end)

RegisterNUICallback('pf-trucking:deliverCargo', function(data, cb)
    -- Deliver is now tied to the physical drop-off marker.
    attemptDropoffAtDelivery(function(result)
        if result and result.ok then
            TriggerEvent('pf-trucking:client:deliverCargo', data and data.job or nil)
        end
        cb(result or { ok = false, error = 'No response' })
    end)
end)

RegisterNetEvent('pf-trucking:client:setActiveJob', function(job)
    activeJob = job
    delivered = (type(job) == 'table' and job.delivered) and true or false
    if delivered then
        jobStage = (currentWorkTruck and currentWorkTruck.plate) and 'return' or nil
    else
        jobStage = 'pickup'
    end
    -- Ensure we have a trailer spawned for the pickup.
    if not delivered and (not jobTrailer or jobTrailer == 0 or not DoesEntityExist(jobTrailer)) then
        spawnTrailerForJob(job)
    end
    updateTruckingHud()
    refreshObjectiveRoute()
    syncActiveJobToNui(true)
end)

RegisterNetEvent('pf-trucking:client:acceptContract', function(job)
    activeJob = job
    delivered = false
    jobStage = 'pickup'
    cleanupJobTrailer()
    local okSpawn = spawnTrailerForJob(job)
    if okSpawn then
        safeNotify('Objective: pick up and attach the trailer', 'success')
    end
    updateTruckingHud()
    refreshObjectiveRoute()
    syncActiveJobToNui(true)
end)

RegisterNetEvent('pf-trucking:client:cancelJob', function(_job)
    clearActiveJobClient()
end)

RegisterNetEvent('pf-trucking:client:deliverCargo', function(_job)
    if not currentWorkTruck or not currentWorkTruck.plate then
        clearActiveJobClient()
    else
        updateTruckingHud()
        refreshObjectiveRoute()
        syncActiveJobToNui(false)
    end
end)

-- Keep the Trucking app status in sync with in-world state.
CreateThread(function()
    while true do
        Wait(750)
        if activeJob then
            syncActiveJobToNui(false)
        end
    end
end)

-- Objective markers + stage progression.
CreateThread(function()
    local wasConnected = false
    while true do
        local wait = 800
        if activeJob then
            -- Match pf-jobs behavior: while job is active, draw markers with Wait(0)
            wait = 0
            local ped = PlayerPedId()
            local p = GetEntityCoords(ped)

            -- Stage changes based on trailer attach.
            if jobStage == 'pickup' and jobTrailer and DoesEntityExist(jobTrailer) then
                local veh = GetVehiclePedIsIn(ped, false)
                local connected = false
                if veh and veh ~= 0 then
                    local hasTrailer, tr = GetVehicleTrailerVehicle(veh)
                    if hasTrailer and tr and tr ~= 0 and tr == jobTrailer then
                        connected = true
                    end
                end
                if connected and not wasConnected then
                    jobStage = 'delivery'
                    safeNotify('Objective: deliver the trailer to the destination', 'success')
                    updateTruckingHud()
                    refreshObjectiveRoute()
                    syncActiveJobToNui(false)
                end
                wasConnected = connected
            end

            -- Draw the current objective marker and handle interactions.
            if jobStage == 'pickup' then
                -- Anchor the objective to the actual spawned trailer so the marker matches what the driver must grab.
                local targetPos = nil
                if jobTrailer and jobTrailer ~= 0 and DoesEntityExist(jobTrailer) then
                    local tc = GetEntityCoords(jobTrailer)
                    targetPos = vector3(tc.x + 0.0, tc.y + 0.0, tc.z + 0.0)
                else
                    targetPos = vec3FromStop(activeJob, 1)
                end

                if targetPos then
                    local dist = #(p - targetPos)
                    if dist < 900.0 then
                        wait = 0
                        drawObjectiveMarker(targetPos)
                        if dist < 18.0 then
                            showHelpText('Objective: Attach the trailer')
                        end
                    end
                end
            elseif jobStage == 'delivery' then
                local delivery = vec3FromStop(activeJob, 2)
                if delivery then
                    local dist = #(p - delivery)
                    if dist < 900.0 then
                        wait = 0
                        drawObjectiveMarker(delivery)
                        if dist < 9.0 then
                            showHelpText('Press ~INPUT_CONTEXT~ to drop off trailer')
                            if IsControlJustPressed(0, 38) then
                                attemptDropoffAtDelivery()
                            end
                        end
                    end
                end
            elseif jobStage == 'return' then
                local depot = getNearestDepot()
                local ret = depot and toVector4(depot.returnCoords) or nil
                if ret then
                    local pos = vector3(ret.x, ret.y, ret.z)
                    local dist = #(p - pos)
                    if dist < 200.0 then
                        wait = 0
                        drawObjectiveMarker(pos)
                        if dist < 12.0 then
                            showHelpText('Objective: Return work truck to the yard')
                        end
                    end
                end
            end
        else
            wasConnected = false
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    cleanupJobTrailer()
    clearObjectiveBlip()
    hudHide()
end)

-- Computer-only: depot truck sourcing (UI-only; other scripts implement the actual spawn/ownership logic)
RegisterNUICallback('pf-trucking:requestWorkTruck', function(data, cb)
    local done = false
    local function finish(payload)
        if done then return end
        done = true
        cb(payload)
    end

    -- Hard timeout so UI never hangs.
    CreateThread(function()
        Wait(12000)
        if not done then
            finish({ ok = false, error = 'Work truck request timed out' })
        end
    end)

    QBCore.Functions.TriggerCallback('pf-trucking:server:requestWorkTruck', function(result)
        if done then return end
        if not result or not result.ok then
            finish(result or { ok = false, error = 'No response' })
            return
        end

        -- If server says we already have one, just sync UI state.
        if result.truck and not result.spawn then
            currentWorkTruck = { name = result.truck.name or 'Work Truck', plate = result.truck.plate }
            SendNUIMessage({ action = 'pf-trucking:setWorkTruck', truck = result.truck })
            SendNUIMessage({ action = 'pf-trucking:setPlayerVehicle', vehicle = { name = result.truck.name or 'Work Truck', capacity = 0, trailerType = '', canTow = true } })
            finish(result)

            -- Close the depot computer after successful issue/sync.
            CreateThread(function()
                Wait(0)
                tryCloseComputerUi()
            end)
            return
        end

        local spawn = result.spawn or {}
        local model = spawn.model
        local coords = toVector4(spawn.coords)
        local heading = tonumber(spawn.heading or (coords and coords.w) or 0.0) or 0.0
        local plate = result.truck and result.truck.plate or nil
        if not model or not coords or not plate then
            TriggerServerEvent('pf-trucking:server:abortWorkTruck', plate)
            finish({ ok = false, error = 'Invalid spawn data' })
            return
        end

        local okModel = ensureModel(model)
        if not okModel then
            TriggerServerEvent('pf-trucking:server:abortWorkTruck', plate)
            finish({ ok = false, error = 'Failed to load vehicle model' })
            return
        end

        local spawnCoords = vector4(coords.x, coords.y, coords.z, heading)

        local clearRadius = Config and Config.WorkTruck and tonumber(Config.WorkTruck.SpawnClearRadius or 0.0) or 0.0
        if clearRadius and clearRadius > 0.0 then
            if IsAnyVehicleNearPoint(spawnCoords.x + 0.0, spawnCoords.y + 0.0, spawnCoords.z + 0.0, clearRadius + 0.0) then
                TriggerServerEvent('pf-trucking:server:abortWorkTruck', plate)
                finish({ ok = false, error = 'Depot spawn is blocked' })
                return
            end
        end

        QBCore.Functions.SpawnVehicle(model, function(veh)
            if done then return end
            if not veh or veh == 0 or not DoesEntityExist(veh) then
                TriggerServerEvent('pf-trucking:server:abortWorkTruck', plate)
                finish({ ok = false, error = 'Failed to spawn work truck' })
                return
            end

            SetEntityHeading(veh, heading + 0.0)
            SetVehicleNumberPlateText(veh, plate)
            SetVehicleNeedsToBeHotwired(veh, false)
            SetVehRadioStation(veh, 'OFF')
            SetVehicleFuelLevel(veh, 100.0)

            local netId = NetworkGetNetworkIdFromEntity(veh)
            TriggerServerEvent('pf-trucking:server:confirmWorkTruckSpawned', netId, plate)

            currentWorkTruck = { name = model, plate = plate }
            SendNUIMessage({ action = 'pf-trucking:setWorkTruck', truck = { name = model, plate = plate } })
            SendNUIMessage({ action = 'pf-trucking:setPlayerVehicle', vehicle = { name = model, capacity = 0, trailerType = '', canTow = true } })

            finish({ ok = true, truck = { name = model, plate = plate } })

            -- Close the depot computer after the player is issued/warped into the truck.
            CreateThread(function()
                Wait(0)
                tryCloseComputerUi()
            end)
        end, spawnCoords, true, spawn.warp and true or false)
    end)
end)

RegisterNUICallback('pf-trucking:returnWorkTruck', function(data, cb)
    QBCore.Functions.TriggerCallback('pf-trucking:server:returnWorkTruck', function(result)
        if result and result.ok then
            SendNUIMessage({ action = 'pf-trucking:setWorkTruck', truck = nil })
        end
        cb(result or { ok = false, error = 'No response' })
    end)
end)

RegisterNetEvent('pf-trucking:client:setWorkTruck', function(truck)
    currentWorkTruck = truck
    SendNUIMessage({ action = 'pf-trucking:setWorkTruck', truck = truck })
end)

local function spawnDepotComputer(depot)
    if not depot or not depot.computerCoords then return end
    local pos = toVector4(depot.computerCoords)
    if not pos then return end

    local propName = depot.computerProp or 'prop_laptop_01a'
    local ok, modelHash = ensureModel(propName)
    if not ok then return end

    local obj = CreateObject(modelHash, pos.x, pos.y, pos.z, false, false, false)
    if not obj or obj == 0 then return end
    SetEntityHeading(obj, pos.w + 0.0)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetEntityAsMissionEntity(obj, true, true)
    if depot.id then
        depotComputerEntities[depot.id] = obj
    end
end

CreateThread(function()
    -- Spawn depot computer props.
    local depots = Config and Config.WorkTruck and Config.WorkTruck.Depots or nil
    if type(depots) == 'table' then
        for _, d in ipairs(depots) do
            spawnDepotComputer(d)
        end
    end
end)

CreateThread(function()
    -- Simple key interaction for the depot computer + truck return zone.
    while true do
        local wait = 1000

        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        local depots = Config and Config.WorkTruck and Config.WorkTruck.Depots or nil
        if type(depots) == 'table' then
            for _, d in ipairs(depots) do
                local comp = toVector4(d.computerCoords)
                if comp then
                    local dist = #(pCoords - vector3(comp.x, comp.y, comp.z))
                    if dist < 2.0 then
                        wait = 0
                        showHelpText('Press ~INPUT_CONTEXT~ to use depot computer')
                        if IsControlJustPressed(0, 38) then
                            local ent = d.id and depotComputerEntities[d.id] or nil
                            if GetResourceState('pf-computer') == 'started' then
                                TriggerEvent('pf-computer:client:useComputer', { entity = ent })
                            end
                        end
                    end
                end

                local ret = toVector4(d.returnCoords)
                if ret then
                    local distR = #(pCoords - vector3(ret.x, ret.y, ret.z))
                    if distR < 20.0 then
                        wait = 0
                        DrawMarker(1, ret.x, ret.y, ret.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.6, 2.6, 0.75, 80, 180, 255, 160, false, true, 2, false, nil, nil, false)

                        if distR < 3.0 then
                            local veh = GetVehiclePedIsIn(ped, false)
                            if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and currentWorkTruck and currentWorkTruck.plate then
                                local vPlate = GetVehicleNumberPlateText(veh)
                                if platesMatch(vPlate, currentWorkTruck.plate) then
                                    showHelpText('Press ~INPUT_CONTEXT~ to return work truck')
                                    if IsControlJustPressed(0, 38) then
                                        if activeJob and (delivered or (type(activeJob) == 'table' and activeJob.delivered)) then
                                            QBCore.Functions.TriggerCallback('pf-trucking:server:completeDeliveredJob', function(result)
                                                if result and result.ok then
                                                    DeleteVehicle(veh)
                                                    currentWorkTruck = nil
                                                    SendNUIMessage({ action = 'pf-trucking:setWorkTruck', truck = nil })
                                                    clearActiveJobClient()
                                                    safeNotify(('Job complete. Paid $%s'):format(tostring(result.finalPayout or 0)), 'success')
                                                else
                                                    safeNotify((result and result.error) or 'Unable to complete job', 'error')
                                                end
                                            end)
                                        else
                                            QBCore.Functions.TriggerCallback('pf-trucking:server:returnWorkTruck', function(result)
                                                if result and result.ok then
                                                    DeleteVehicle(veh)
                                                    currentWorkTruck = nil
                                                    SendNUIMessage({ action = 'pf-trucking:setWorkTruck', truck = nil })
                                                end
                                            end)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)
