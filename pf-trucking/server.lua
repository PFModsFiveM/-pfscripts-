local QBCore = exports['pfm-core']:GetCoreObject()

local function dbg(msg)
    if Config and Config.Debug then
        print(('[pf-trucking] %s'):format(tostring(msg)))
    end
end

local function now()
    return os.time() * 1000
end

local function clamp(n, a, b)
    if n < a then return a end
    if n > b then return b end
    return n
end

local function randInt(a, b)
    return math.random(a, b)
end

local function pick(t)
    if type(t) ~= 'table' or #t == 0 then return nil end
    return t[math.random(1, #t)]
end

local function vecDist(a, b)
    if not a or not b then return 0.0 end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function coordsToTable(c)
    if not c then return nil end
    if type(c) == 'table' then
        return { x = c.x or c[1] or 0.0, y = c.y or c[2] or 0.0, z = c.z or c[3] or 0.0 }
    end
    -- vector3/vector4 userdata supports .x/.y/.z
    return { x = c.x or 0.0, y = c.y or 0.0, z = c.z or 0.0 }
end

local function coordsToTable4(c)
    if not c then return nil end
    if type(c) == 'table' then
        return { x = c.x or c[1] or 0.0, y = c.y or c[2] or 0.0, z = c.z or c[3] or 0.0, w = c.w or c[4] or c.h or c.heading or 0.0 }
    end
    return { x = c.x or 0.0, y = c.y or 0.0, z = c.z or 0.0, w = c.w or 0.0 }
end

local Jobs = {}
local ActiveByCitizenId = {}
local WorkTruckByCitizenId = {}
local CitizenBySource = {}

local function hasWorkTruck(citizenid)
    local wt = citizenid and WorkTruckByCitizenId[citizenid] or nil
    return wt and wt.plate ~= nil
end

local function getCitizenId(src)
    if CitizenBySource[src] then return CitizenBySource[src] end
    local Player = QBCore.Functions.GetPlayer(src)
    local citizenid = Player and Player.PlayerData and Player.PlayerData.citizenid or nil
    if citizenid then CitizenBySource[src] = citizenid end
    return citizenid
end

local function normalizePlatePrefix(prefix)
    local p = tostring(prefix or 'WK')
    p = p:gsub('%s+', ''):upper()
    if #p > 4 then p = p:sub(1, 4) end
    if #p < 1 then p = 'WK' end
    return p
end

local function makePlate()
    local prefix = normalizePlatePrefix(Config.WorkTruck and Config.WorkTruck.PlatePrefix)
    local suffix = tostring(math.random(0, 9999))
    suffix = suffix:sub(1, 4)
    suffix = string.rep('0', 4 - #suffix) .. suffix
    local plate = (prefix .. suffix)
    if #plate > 8 then plate = plate:sub(1, 8) end
    return plate
end

local function pickDepotForSource(src)
    local depots = Config.WorkTruck and Config.WorkTruck.Depots or nil
    if type(depots) ~= 'table' or #depots == 0 then return nil end

    local ped = GetPlayerPed(src)
    local pCoords = GetEntityCoords(ped)

    local best = nil
    local bestDist = nil
    for _, d in ipairs(depots) do
        if d and d.spawnCoords then
            local s = d.spawnCoords
            local dist = vecDist(pCoords, s)
            if not bestDist or dist < bestDist then
                best = d
                bestDist = dist
            end
        end
    end

    return best
end

local function isSpawnClear(coords, radius)
    if not coords then return true end
    local r = tonumber(radius or 0.0) or 0.0
    if r <= 0.0 then return true end

    -- NOTE: IsAnyVehicleNearPoint is a client native and may be nil server-side.
    -- We do the real blocked check on the client before spawning.
    if type(IsAnyVehicleNearPoint) ~= 'function' then
        return true
    end

    return not IsAnyVehicleNearPoint(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, r + 0.0)
end

local function tryDeleteEntity(ent)
    if not ent or ent == 0 then return end
    if DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
end

local function clearWorkTruck(citizenid)
    if not citizenid then return end
    local entry = WorkTruckByCitizenId[citizenid]
    WorkTruckByCitizenId[citizenid] = nil
    if entry then
        if entry.entity then
            tryDeleteEntity(entry.entity)
        end
        if entry.netId then
            local ok = pcall(function()
                local ent = NetworkGetEntityFromNetworkId(entry.netId)
                tryDeleteEntity(ent)
            end)
            if not ok then
                -- ignore
            end
        end
    end
end

-- ============================================================================
-- Delivery verification and pay
-- ============================================================================
-- Pay comes from system:pf-trucking through the pfm-banking ledger. The key is unique per claimed
-- contract (id + driver + claim time), so a repeated completion request can never pay twice.

-- Bank account holding the payment for funded contracts (pf-stores supply orders).
local FREIGHT_ESCROW = 'society:freight_escrow'

local function deliveryCfg()
    local d = Config.Delivery or {}
    return {
        dropoffRadius = tonumber(d.DropoffRadius) or 80.0,
        returnRadius = tonumber(d.ReturnRadius) or 35.0,
        minSeconds = tonumber(d.MinSeconds) or 45,
        maxSpeed = tonumber(d.MaxAverageSpeed) or 45.0,
    }
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return coordsToTable(GetEntityCoords(ped))
end

local function finalStopCoords(job)
    local stops = type(job) == 'table' and job.stops or nil
    if type(stops) ~= 'table' or #stops == 0 then return nil end
    return stops[#stops].coords
end

-- Minimum time (ms) between claiming and delivering: the pickup->drop distance at a generous speed.
local function minTripMs(job)
    local cfg = deliveryCfg()
    local stops = type(job) == 'table' and job.stops or nil
    local meters = 0.0
    if type(stops) == 'table' and #stops >= 2 then
        meters = vecDist(stops[1].coords, stops[#stops].coords)
    end
    return math.max(cfg.minSeconds, meters / cfg.maxSpeed) * 1000
end

--- Checks that `src` is at the job's final stop, late enough after claiming. Returns ok, error.
local function verifyAtDropoff(src, active)
    -- the cargo was hooked at the pickup first (cargoLoaded); driving straight to the drop-off paid too
    if not active.loaded then return false, 'Pick up the cargo first' end
    local drop = finalStopCoords(active.data)
    if not drop then return false, 'This contract has no delivery point' end
    local pos = playerCoords(src)
    if not pos or vecDist(pos, drop) > deliveryCfg().dropoffRadius then
        return false, 'You are not at the delivery point'
    end
    if now() - (tonumber(active.assignedAt) or now()) < minTripMs(active.data) then
        return false, 'Delivery is too fast to be real'
    end
    return true
end

local function verifyAtDepotReturn(src)
    local pos = playerCoords(src)
    if not pos then return false end
    local radius = deliveryCfg().returnRadius
    for _, d in ipairs((Config.WorkTruck and Config.WorkTruck.Depots) or {}) do
        if d.returnCoords and vecDist(pos, d.returnCoords) <= radius then return true end
    end
    return false
end

local function ledgerTransfer(opts)
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

--- Pays a finished contract. NPC contracts are paid by system:pf-trucking (key per claim); funded
--- contracts (store supply orders) are paid from the freight escrow under the poster's key, and the
--- depot's rental fee is taken from the same escrowed pay. Returns ok, error.
local function payContract(citizenid, active, payout)
    if GetResourceState('pfm-banking') ~= 'started' then return false, 'Payments are unavailable right now' end
    local data = type(active.data) == 'table' and active.data or {}
    local funded = data.payFrom == FREIGHT_ESCROW and type(data.payKey) == 'string'
    local driverRef = ('player:%s:bank'):format(citizenid)
    local meta = { contract = active.id, gross = active.payoutGross, rentalFee = active.rentalFee }

    if payout > 0 then
        local res = ledgerTransfer({
            from = funded and FREIGHT_ESCROW or 'system:pf-trucking',
            to = driverRef,
            amount = payout,
            key = funded and data.payKey or ('trucking:%s:%s:%s'):format(tostring(active.id), citizenid, tostring(active.assignedAt or 0)),
            kind = 'wage',
            reason = 'Trucking contract',
            actor = citizenid,
            metadata = meta,
        })
        if not res.ok then return false, 'Payment failed, try again' end
    end

    local rentalFee = tonumber(active.rentalFee) or 0
    if funded and rentalFee > 0 then
        -- the escrow holds the gross pay; the rental fee part goes to the depot instead of the driver
        local fee = math.min(rentalFee, tonumber(active.payoutGross) or rentalFee)
        local res = ledgerTransfer({
            from = FREIGHT_ESCROW, to = 'system:pf-trucking', amount = fee,
            key = data.payKey .. ':rental', kind = 'fee', reason = 'Work truck rental', actor = citizenid,
        })
        if not res.ok then
            print(('^1[pf-trucking]^7 rental fee for %s not collected from escrow (%s)'):format(tostring(active.id), tostring(res.error)))
        end
    end
    return true
end

local function buildStops(pickupLabel, pickupCoords, dropLabel, dropCoords)
    return {
        { label = 'Stop 1 – Pickup', kind = 'Pickup', location = pickupLabel, coords = coordsToTable(pickupCoords) },
        { label = 'Stop 2 – Delivery', kind = 'Delivery', location = dropLabel, coords = coordsToTable(dropCoords) },
    }
end

local function makeJobId()
    return string.format('NPC-%04d', math.random(0, 9999))
end

local function genJob()
    local locA = pick(Config.NpcLocations)
    local locB = pick(Config.NpcLocations)
    if not locA or not locB then return nil end
    local guard = 0
    while locB.label == locA.label and guard < 10 do
        locB = pick(Config.NpcLocations)
        guard = guard + 1
    end

    local cargoDef = pick(Config.NpcCargoTypes) or { title = 'Freight', cargo = 'General cargo', minQty = 10, maxQty = 20 }
    local requiredTrailer = pick(Config.NpcTrailerTypes) or 'Box Trailer'
    local qty = randInt(cargoDef.minQty or 10, cargoDef.maxQty or 20)

    local meters = vecDist(locA.coords, locB.coords)
    local miles = (meters / 1609.344) * (Config.NpcJobs.RoadFactor or 1.25)
    miles = clamp(miles, 1.0, 250.0)
    miles = math.floor(miles * 10 + 0.5) / 10

    local payout = (Config.NpcJobs.PayoutBase or 250) + miles * (Config.NpcJobs.PayoutPerMile or 85) + randInt(0, Config.NpcJobs.PayoutVariance or 220)
    payout = math.floor(payout + 0.5)

    local id = makeJobId()
    if Jobs[id] then
        id = makeJobId()
    end

    local job = {
        id = id,
        kind = 'npc',
        title = cargoDef.title,
        cargoType = cargoDef.cargo,
        cargoQuantity = qty,
        pickup = locA.label,
        dropoff = locB.label,
        distanceMi = miles,
        payout = payout,
        requiredTrailer = requiredTrailer,
        stops = buildStops(locA.label, locA.coords, locB.label, locB.coords),
        createdAt = now(),
    }

    return job
end

local function countAvailable(kind)
    local n = 0
    for _, j in pairs(Jobs) do
        if j and j.status == 'available' then
            if not kind then
                n = n + 1
            else
                local k = j.data and j.data.kind or nil
                if k == kind then
                    n = n + 1
                end
            end
        end
    end
    return n
end

local function getAvailableList()
    local list = {}
    for _, j in pairs(Jobs) do
        if j and j.status == 'available' then
            list[#list + 1] = j.data
        end
    end
    table.sort(list, function(a, b)
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return list
end

local function ensurePool()
    if not Config.NpcJobs or Config.NpcJobs.Enabled == false then return end

    -- Only count NPC jobs toward the NPC pool target.
    local available = countAvailable('npc')
    local target = Config.NpcJobs.TargetAvailable or 18
    local maxAvail = Config.NpcJobs.MaxAvailable or 30

    if available >= target then return end

    local toAdd = math.min(target - available, math.max(0, maxAvail - available))
    if toAdd > 0 then dbg(('ensurePool: available=%d target=%d adding=%d'):format(available, target, toAdd)) end
    for _ = 1, toAdd do
        local job = genJob()
        if job then
            Jobs[job.id] = {
                status = 'available',
                data = job,
                assignedCitizenId = nil,
                assignedAt = nil,
            }
        end
    end
end

CreateThread(function()
    math.randomseed(GetGameTimer() + os.time())
    ensurePool()
    while true do
        Wait((Config.NpcJobs and Config.NpcJobs.RefreshSeconds or 90) * 1000)
        ensurePool()
    end
end)

QBCore.Functions.CreateCallback('pf-trucking:server:getContracts', function(source, cb)
    ensurePool()
    dbg(('getContracts from src=%s available=%d total=%d'):format(tostring(source), countAvailable(), (function() local n=0 for _ in pairs(Jobs) do n=n+1 end return n end)()))

    local Player = QBCore.Functions.GetPlayer(source)
    local name = 'Driver'
    local citizenid = nil
    if Player then
        citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
        if citizenid then CitizenBySource[source] = citizenid end
        local ci = Player.PlayerData and Player.PlayerData.charinfo or nil
        if ci and (ci.firstname or ci.lastname) then
            name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        end
    end

    cb({
        ok = true,
        contracts = getAvailableList(),
        profile = {
            name = name,
            -- TODO: wire to your owned-truck system.
            ownsTruck = false,
        },
        workTruck = {
            enabled = (Config.WorkTruck and Config.WorkTruck.Enabled) or false,
            rentalFee = (Config.WorkTruck and tonumber(Config.WorkTruck.RentalFee or 0)) or 0,
        },
        activeJob = (citizenid and ActiveByCitizenId[citizenid]) and ActiveByCitizenId[citizenid].data or nil,
    })
end)

-- ============================================================================
-- External job injection (used by other PF resources like pf-stores)
-- ============================================================================
local function makeExternalJobId()
    return string.format('EXT-%04d', math.random(0, 9999))
end

local function CreateExternalJob(job)
    if type(job) ~= 'table' then
        return nil
    end

    job.kind = 'external'
    job.createdAt = job.createdAt or now()

    local id = tostring(job.id or '')
    if id == '' then
        id = makeExternalJobId()
        if Jobs[id] then
            id = makeExternalJobId()
        end
    elseif Jobs[id] then
        -- already posted (e.g. a re-post after the owning resource restarted): keep the live contract
        return id
    end
    job.id = id

    -- A funded job is paid from the account that holds its payment (the freight escrow) under a key
    -- fixed by the poster, so it is paid at most once however often it is posted or claimed.
    if job.payFrom ~= nil then
        if job.payFrom ~= FREIGHT_ESCROW or type(job.payKey) ~= 'string' or job.payKey == '' then
            job.payFrom, job.payKey = nil, nil
        end
    end

    -- Normalize stop coords to plain tables.
    if type(job.stops) == 'table' then
        for _, stop in ipairs(job.stops) do
            if type(stop) == 'table' and stop.coords then
                stop.coords = coordsToTable(stop.coords)
            end
        end
    end

    if job.trailerSpawn then
        job.trailerSpawn = coordsToTable4(job.trailerSpawn)
    end

    Jobs[id] = {
        status = 'available',
        data = job,
        assignedCitizenId = nil,
        assignedAt = nil,
    }

    -- Re-posted after a restart with its driver: restore the claim (the owner keeps the assignment
    -- in its own records), so the driver can carry on instead of the job going back to the pool.
    local restoreTo = type(job.assignedCitizenId) == 'string' and job.assignedCitizenId ~= '' and job.assignedCitizenId or nil
    if restoreTo and not ActiveByCitizenId[restoreTo] then
        local assignedAt = tonumber(job.assignedAt) or now()
        Jobs[id].status = 'assigned'
        Jobs[id].assignedCitizenId = restoreTo
        Jobs[id].assignedAt = assignedAt
        ActiveByCitizenId[restoreTo] = {
            id = id, data = job, payoutGross = tonumber(job.payout) or 0, rentalFee = 0,
            payoutNet = tonumber(job.payout) or 0, delivered = false, loaded = job.loaded == true,
            assignedAt = assignedAt,
        }
    end
    job.assignedCitizenId, job.assignedAt = nil, nil

    -- Push updated contract list to clients with the dispatch UI open.
    TriggerClientEvent('pf-trucking:client:contractsUpdated', -1, getAvailableList())

    return id
end

exports('CreateExternalJob', CreateExternalJob)

--- Removes an external contract nobody has claimed. Returns true when it was removed (or never
--- existed, e.g. after a restart before re-posting), false when a driver holds it.
local function CancelExternalJob(id)
    local entry = Jobs[tostring(id or '')]
    if not entry then return true end
    if entry.status ~= 'available' then return false end
    Jobs[tostring(id)] = nil
    TriggerClientEvent('pf-trucking:client:contractsUpdated', -1, getAvailableList())
    return true
end
exports('CancelExternalJob', CancelExternalJob)

--- Takes an external contract back from the driver holding it and offers it again (the owner's
--- driver deadline passed). Returns true when it is available again.
local function ReleaseExternalJob(id)
    local entry = Jobs[tostring(id or '')]
    if not entry then return false end
    if entry.status == 'available' then return true end
    local cid = entry.assignedCitizenId
    if cid and ActiveByCitizenId[cid] and ActiveByCitizenId[cid].id == tostring(id) then
        ActiveByCitizenId[cid] = nil
        local src = nil
        for s, c in pairs(CitizenBySource) do if c == cid then src = s end end
        if src then TriggerClientEvent('pf-trucking:client:jobRevoked', src, tostring(id)) end
    end
    entry.status, entry.assignedCitizenId, entry.assignedAt = 'available', nil, nil
    TriggerClientEvent('pf-trucking:client:contractsUpdated', -1, getAvailableList())
    return true
end
exports('ReleaseExternalJob', ReleaseExternalJob)

QBCore.Functions.CreateCallback('pf-trucking:server:requestWorkTruck', function(source, cb)
    if not (Config.WorkTruck and Config.WorkTruck.Enabled) then
        cb({ ok = false, error = 'Work trucks disabled' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, error = 'No player' })
        return
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if not citizenid then
        cb({ ok = false, error = 'No citizenid' })
        return
    end

    local existing = WorkTruckByCitizenId[citizenid]
    if existing and existing.plate then
        -- If we reserved a plate but never got a spawn confirmation, avoid "locking" the user out.
        if not existing.spawnedAt then
            local reservedAt = tonumber(existing.reservedAt or 0) or 0
            local ageMs = now() - reservedAt
            if ageMs < 15000 then
                cb({ ok = false, error = 'Work truck issuance in progress… try again' })
                return
            end
            -- Stale reservation; clear and allow a new request.
            WorkTruckByCitizenId[citizenid] = nil
        else
            cb({ ok = true, truck = { name = existing.model or 'Work Truck', plate = existing.plate } })
            return
        end
    end

    local depot = pickDepotForSource(source)
    if not depot or not depot.spawnCoords then
        cb({ ok = false, error = 'No depot spawn configured' })
        return
    end

    local models = Config.WorkTruck.Models
    local model = pick(models)
    if not model then
        cb({ ok = false, error = 'No work truck models configured' })
        return
    end

    if not isSpawnClear(depot.spawnCoords, Config.WorkTruck.SpawnClearRadius or 0.0) then
        cb({ ok = false, error = 'Depot spawn is blocked' })
        return
    end

    local plate = makePlate()
    WorkTruckByCitizenId[citizenid] = {
        plate = plate,
        model = model,
        depotId = depot.id,
        depotLabel = depot.label,
        reservedAt = now(),
        spawnedAt = nil,
        netId = nil,
    }

    cb({
        ok = true,
        truck = { name = model, plate = plate },
        spawn = {
            model = model,
            coords = coordsToTable(depot.spawnCoords),
            heading = depot.spawnCoords.w or 0.0,
            warp = Config.WorkTruck.WarpDriverOnSpawn ~= false,
        },
        depot = {
            id = depot.id,
            label = depot.label,
        }
    })
end)

RegisterNetEvent('pf-trucking:server:confirmWorkTruckSpawned', function(netId, plate)
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return end

    local entry = WorkTruckByCitizenId[citizenid]
    if not entry or not entry.plate then return end
    if plate and tostring(plate) ~= tostring(entry.plate) then return end

    entry.netId = tonumber(netId) or entry.netId
    entry.spawnedAt = now()

    TriggerClientEvent('vehiclekeys:client:SetOwner', src, entry.plate)
    TriggerClientEvent('pf-trucking:client:setWorkTruck', src, { name = entry.model or 'Work Truck', plate = entry.plate })
end)

RegisterNetEvent('pf-trucking:server:abortWorkTruck', function(plate)
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return end
    local entry = WorkTruckByCitizenId[citizenid]
    if not entry then return end
    if plate and entry.plate and tostring(plate) ~= tostring(entry.plate) then return end
    WorkTruckByCitizenId[citizenid] = nil
end)

QBCore.Functions.CreateCallback('pf-trucking:server:returnWorkTruck', function(source, cb)
    local citizenid = getCitizenId(source)
    if not citizenid then
        cb({ ok = false, error = 'No citizenid' })
        return
    end

    clearWorkTruck(citizenid)
    TriggerClientEvent('pf-trucking:client:setWorkTruck', source, nil)
    cb({ ok = true })
end)

-- Claims a contract for a driver. Used by the trucking app and by the AcceptJob export, so both
-- share one pool and one claim state: a contract can only be claimed while it is available.
local function claimContract(source, contractId)
    ensurePool()
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return { ok = false, error = 'No player' }
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if citizenid then CitizenBySource[source] = citizenid end
    if not citizenid then
        return { ok = false, error = 'No citizenid' }
    end

    if ActiveByCitizenId[citizenid] then
        return { ok = false, error = 'You already have an active job' }
    end

    contractId = contractId ~= nil and tostring(contractId) or nil
    local entry = contractId and Jobs[contractId] or nil
    if not entry or entry.status ~= 'available' then
        return { ok = false, error = 'Contract not available' }
    end

    entry.status = 'assigned'
    entry.assignedCitizenId = citizenid
    entry.assignedAt = now()

    -- payoutGross is remembered on first claim; data.payout is overwritten with the net amount below,
    -- so re-claiming after a cancel must not take the rental fee off a second time
    local payoutGross = tonumber(entry.data and (entry.data.payoutGross or entry.data.payout) or 0) or 0
    local rentalFee = 0
    local wt = WorkTruckByCitizenId[citizenid]
    if wt and wt.plate then
        rentalFee = (Config.WorkTruck and tonumber(Config.WorkTruck.RentalFee or 0)) or 0
    end
    local payoutNet = math.max(0, payoutGross - rentalFee)

    -- Shape the job object for UI clarity.
    entry.data.payoutGross = payoutGross
    entry.data.rentalFee = rentalFee
    entry.data.payoutNet = payoutNet
    entry.data.payout = payoutNet

    ActiveByCitizenId[citizenid] = {
        id = contractId,
        data = entry.data,
        payoutGross = payoutGross,
        rentalFee = rentalFee,
        payoutNet = payoutNet,
        delivered = false,
        assignedAt = entry.assignedAt,
    }

    if entry.data.kind == 'external' then
        TriggerEvent('pf-trucking:server:externalJobClaimed', entry.data, { citizenid = citizenid, source = source, assignedAt = entry.assignedAt })
    end
    return { ok = true, job = entry.data, contracts = getAvailableList() }
end

QBCore.Functions.CreateCallback('pf-trucking:server:claimContract', function(source, cb, contractId)
    cb(claimContract(source, contractId))
end)

QBCore.Functions.CreateCallback('pf-trucking:server:markDelivered', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, error = 'No player' })
        return
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if citizenid then CitizenBySource[source] = citizenid end
    local active = citizenid and ActiveByCitizenId[citizenid] or nil
    if not citizenid or not active then
        cb({ ok = false, error = 'No active job' })
        return
    end

    -- the client says it delivered; the server checks where the driver actually is
    local atDrop, why = verifyAtDropoff(source, active)
    if not atDrop then
        cb({ ok = false, error = why })
        return
    end

    active.delivered = true
    if type(active.data) == 'table' then
        active.data.delivered = true
    end

    cb({ ok = true, job = active.data })
end)

QBCore.Functions.CreateCallback('pf-trucking:server:completeDeliveredJob', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, error = 'No player' })
        return
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if citizenid then CitizenBySource[source] = citizenid end
    local active = citizenid and ActiveByCitizenId[citizenid] or nil
    if not citizenid or not active then
        cb({ ok = false, error = 'No active job' })
        return
    end

    -- `delivered` is only ever set by markDelivered after the server checked the drop-off position
    if not active.delivered then
        cb({ ok = false, error = 'Cargo not delivered yet' })
        return
    end
    if hasWorkTruck(citizenid) and not verifyAtDepotReturn(source) then
        cb({ ok = false, error = 'Return the work truck to the depot' })
        return
    end

    local id = active.id
    local completedJob = active.data
    ActiveByCitizenId[citizenid] = nil -- taken first so a second request finds no job

    local payout = tonumber(active.payoutNet or (active.data and active.data.payout) or 0) or 0
    local paid, payErr = payContract(citizenid, active, payout)
    if not paid then
        ActiveByCitizenId[citizenid] = active -- keep the job so the driver can retry (same key: paid once)
        cb({ ok = false, error = payErr })
        return
    end

    Jobs[id] = nil
    ensurePool()

    clearWorkTruck(citizenid)
    TriggerClientEvent('pf-trucking:client:setWorkTruck', source, nil)

    if type(completedJob) == 'table' and completedJob.kind == 'external' then
        TriggerEvent('pf-trucking:server:externalJobCompleted', completedJob, {
            source = source,
            citizenid = citizenid,
            payout = payout,
        })
    end

    cb({
        ok = true,
        contracts = getAvailableList(),
        finalPayout = payout,
        payoutGross = tonumber(active.payoutGross or 0) or 0,
        rentalFee = tonumber(active.rentalFee or 0) or 0,
        payoutNet = payout,
    })
end)

-- Gives a driver's active contract back to the pool (app callback and CancelContract export)
local function cancelActiveJob(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return { ok = false, error = 'No player' }
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if citizenid then CitizenBySource[source] = citizenid end
    local active = citizenid and ActiveByCitizenId[citizenid] or nil
    if not citizenid or not active then
        return { ok = false, error = 'No active job' }
    end

    local id = active.id
    ActiveByCitizenId[citizenid] = nil

    local entry = Jobs[id]
    if entry then
        -- Return to pool
        entry.status = 'available'
        entry.assignedCitizenId = nil
        entry.assignedAt = nil
        if type(entry.data) == 'table' and entry.data.kind == 'external' then
            TriggerEvent('pf-trucking:server:externalJobReleased', entry.data, { citizenid = citizenid })
        end
    end

    clearWorkTruck(citizenid)
    TriggerClientEvent('pf-trucking:client:setWorkTruck', source, nil)

    return { ok = true, contracts = getAvailableList() }
end

QBCore.Functions.CreateCallback('pf-trucking:server:cancelActiveJob', function(source, cb)
    cb(cancelActiveJob(source))
end)

QBCore.Functions.CreateCallback('pf-trucking:server:completeActiveJob', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, error = 'No player' })
        return
    end

    local citizenid = Player.PlayerData and Player.PlayerData.citizenid or nil
    if citizenid then CitizenBySource[source] = citizenid end
    local active = citizenid and ActiveByCitizenId[citizenid] or nil
    if not citizenid or not active then
        cb({ ok = false, error = 'No active job' })
        return
    end

    -- Work-truck jobs finish at the depot (markDelivered, then completeDeliveredJob). This used to pay
    -- here AND again on return.
    if hasWorkTruck(citizenid) then
        cb({ ok = false, error = 'Return the work truck to the depot to finish this job' })
        return
    end

    local atDrop, why = verifyAtDropoff(source, active)
    if not atDrop then
        cb({ ok = false, error = why })
        return
    end

    local id = active.id
    local completedJob = active.data
    ActiveByCitizenId[citizenid] = nil -- taken first so a second request finds no job

    local payout = tonumber(active.payoutNet or (active.data and active.data.payout) or 0) or 0
    local paid, payErr = payContract(citizenid, active, payout)
    if not paid then
        ActiveByCitizenId[citizenid] = active
        cb({ ok = false, error = payErr })
        return
    end

    -- Remove completed jobs from pool; replenisher will add new ones.
    Jobs[id] = nil
    ensurePool()

    if type(completedJob) == 'table' and completedJob.kind == 'external' then
        TriggerEvent('pf-trucking:server:externalJobCompleted', completedJob, {
            source = source,
            citizenid = citizenid,
            payout = payout,
        })
    end

    cb({
        ok = true,
        contracts = getAvailableList(),
        finalPayout = payout,
        payoutGross = tonumber(active.payoutGross or 0) or 0,
        rentalFee = tonumber(active.rentalFee or 0) or 0,
        payoutNet = payout,
    })
end)

-- The driver hooked the job's trailer at the pickup. Only counted at the first stop, once.
RegisterNetEvent('pf-trucking:server:cargoLoaded', function()
    local src = source
    local citizenid = getCitizenId(src)
    local active = citizenid and ActiveByCitizenId[citizenid] or nil
    if not active or active.loaded then return end
    local stops = type(active.data) == 'table' and active.data.stops or nil
    local pickup = type(stops) == 'table' and stops[1] and stops[1].coords or nil
    local pos = playerCoords(src)
    if not pickup or not pos or vecDist(pos, pickup) > math.max(60.0, deliveryCfg().dropoffRadius * 2) then return end
    active.loaded = true
    if active.data.kind == 'external' then
        TriggerEvent('pf-trucking:server:externalJobLoaded', active.data, { citizenid = citizenid, source = src })
    end
end)

-- Resources that post external contracts (pf-stores) re-post theirs when pf-trucking (re)starts.
CreateThread(function()
    Wait(1500)
    TriggerEvent('pf-trucking:server:started')
end)

AddEventHandler('playerDropped', function()
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return end
    clearWorkTruck(citizenid)
    CitizenBySource[src] = nil
end)

-- ============================================================================
-- EXPORTS FOR PF-COMPUTER INTEGRATION
-- ============================================================================

-- Get available jobs for a player
-- ============================================================================
-- Export API for other resources (tablet, computer). These used to be a second implementation:
-- AcceptJob searched the id-keyed Jobs table with ipairs (so it never found a job) and wrote to a
-- separate pf_trucking_contracts table; CancelContract dropped the driver's job without returning it
-- to the pool; GetAvailableJobs invented "special" jobs that could not be accepted. They now use the
-- same pool and claim state as the trucking app.
-- ============================================================================
function GetAvailableJobs(source)
    ensurePool()
    local available = {}
    for _, job in ipairs(getAvailableList()) do
        available[#available + 1] = {
            id = job.id,
            title = job.title or 'Trucking Contract',
            pickup = job.pickup or 'Unknown',
            delivery = job.dropoff or 'Unknown',
            cargo = job.cargoType or 'General Freight',
            distance = job.distanceMi or 0,
            payout = job.payout or 0,
            requiredLicense = job.requiredTrailer,
            isPlayerOwned = false,
        }
    end
    return available
end
exports('GetAvailableJobs', GetAvailableJobs)

function AcceptJob(source, jobId)
    local res = claimContract(source, jobId)
    if res.ok then TriggerClientEvent('pf-trucking:client:jobAccepted', source, res.job) end
    return res
end
exports('AcceptJob', AcceptJob)

function CancelContract(source, _)
    return cancelActiveJob(source)
end
exports('CancelContract', CancelContract)

-- Routes the driver to their active contract (the contract id argument is ignored: a driver has one)
function SetContractRoute(source, _)
    local citizenid = getCitizenId(source)
    local active = citizenid and ActiveByCitizenId[citizenid] or nil
    if not active then return { ok = false, error = 'contract_not_found' } end
    TriggerClientEvent('pf-trucking:client:setRoute', source, active.data)
    return { ok = true }
end
exports('SetContractRoute', SetContractRoute)
