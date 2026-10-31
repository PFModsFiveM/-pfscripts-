local QBCore = exports['pfm-core']:GetCoreObject()

local function GetGarageConfig(garageId)
    return Config.JobGarages[garageId]
end

local function GetPlayerJob(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil, nil, nil end
    local job = Player.PlayerData.job
    return job.name, tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or 0, Player
end

local function SafeQuery(fn, sql, params, fallback)
    local ok, res = pcall(function()
        return fn(sql, params)
    end)
    if not ok then
        print(('[pf-jobgarages] SQL error: %s'):format(res or 'unknown'))
        return fallback
    end
    return res
end

-- Plates as the game shows them are padded to 8 characters; the database keeps them trimmed.
local function NormalizePlate(plate)
    if type(plate) ~= 'string' then return '' end
    plate = plate:upper():gsub('^%s+', ''):gsub('%s+$', '')
    if #plate > 8 then return '' end
    return plate
end

-- A fleet vehicle must be one of the adding manager's own cars: its plate, model and saved mods
-- are what every employee later spawns. This always checks player_vehicles; it used to allow the
-- add whenever the keys export was missing or the provider was not 'qb'.
local function GetOwnedVehicleRow(src, plate)
    if plate == '' then return nil end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    return SafeQuery(MySQL.single.await,
        "SELECT plate, vehicle, state, depotprice FROM player_vehicles WHERE plate = ? AND (citizenid = ? OR license = ?)",
        { plate, Player.PlayerData.citizenid, Player.PlayerData.license or '' },
        nil
    )
end

local function PlayerNear(src, point, range)
    if not point then return false end
    local coords = GetEntityCoords(GetPlayerPed(src))
    return #(coords - vector3(point.x, point.y, point.z)) <= range
end

-- Garage permissions: the config's job and minGrade plus the per-garage minimum use grade the
-- managers save (job_garage_permissions), which was stored but never checked.
local function CanUseGarage(src, garageId, cfg)
    local jobName, jobGrade, Player = GetPlayerJob(src)
    if not cfg or not Player or jobName ~= cfg.job then return false, jobGrade, Player end
    jobGrade = tonumber(jobGrade) or 0
    if jobGrade < (cfg.minGrade or 0) then return false, jobGrade, Player end
    local perms = SafeQuery(MySQL.single.await,
        "SELECT min_grade_use FROM job_garage_permissions WHERE garage_id = ?",
        { garageId },
        nil
    )
    if perms and jobGrade < (tonumber(perms.min_grade_use) or 0) then return false, jobGrade, Player end
    return true, jobGrade, Player
end

-- The grade that manages this garage's fleet: the saved minimum (job_garage_permissions, which was
-- stored but never used) or the garage's / the default manage grade.
local function ManageGrade(garageId, cfg)
    local fallback = tonumber(cfg and cfg.manageGrade) or tonumber(Config.DefaultManageGrade) or 4
    local row = SafeQuery(MySQL.single.await,
        "SELECT min_grade_manage FROM job_garage_permissions WHERE garage_id = ?",
        { garageId },
        nil
    )
    local saved = row and tonumber(row.min_grade_manage)
    return saved or fallback
end

--- True (plus the grade and Player) when the player may manage this garage's fleet: the garage's
--- job at the manage grade, or that job's boss.
local function CanManageGarage(src, garageId, cfg)
    local jobName, jobGrade, Player = GetPlayerJob(src)
    if not cfg or not Player or jobName ~= cfg.job then return false, jobGrade, Player end
    if Player.PlayerData.job.isboss == true then return true, jobGrade, Player end
    return jobGrade >= ManageGrade(garageId, cfg), jobGrade, Player
end

local function NeedsDuty(cfg)
    if cfg and cfg.requireOnDuty ~= nil then return cfg.requireOnDuty == true end
    return Config.RequireOnDuty ~= false
end

local USE_RANGE = 20.0      -- the garage terminal is used from 2.5 m
local VEHICLE_RANGE = 15.0  -- the client stores the car it sits in or one within 10 m

-- The networked vehicle with this plate near the player, if any.
local function FindVehicleNear(src, plate)
    if not GetAllVehicles then return nil end
    local coords = GetEntityCoords(GetPlayerPed(src))
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) and NormalizePlate(GetVehicleNumberPlateText(veh)) == plate
            and #(GetEntityCoords(veh) - coords) <= VEHICLE_RANGE then
            return veh
        end
    end
    return nil
end

local function GetOwnedVehiclesForPlayer(citizenid, license)
    local tried = {}
    local result

    local ownerCol = (Config and Config.PlayerVehiclesOwnerColumn) or 'citizenid'
    result = SafeQuery(MySQL.query.await,
        ("SELECT plate, vehicle, hash FROM player_vehicles WHERE %s = ?"):format(ownerCol),
        { ownerCol == 'license' and license or citizenid },
        nil
    )
    tried[#tried+1] = { col = ownerCol, count = result and #result or 0 }

    if result == nil or (#result == 0) then
        result = SafeQuery(MySQL.query.await,
            "SELECT plate, vehicle, hash FROM player_vehicles WHERE owner = ?",
            { citizenid },
            nil
        )
        tried[#tried+1] = { col = 'owner', count = result and #result or 0 }
    end

    if (result == nil or (#result == 0)) and license then
        result = SafeQuery(MySQL.query.await,
            "SELECT plate, vehicle, hash FROM player_vehicles WHERE license = ?",
            { license },
            nil
        )
        tried[#tried+1] = { col = 'license', count = result and #result or 0 }
    end

    if result == nil or (#result == 0) then
        local identifiers = PlayerIdentifiersCache and PlayerIdentifiersCache[citizenid] or nil
        for _, col in ipairs({ 'steam', 'identifier' }) do
            result = SafeQuery(MySQL.query.await,
                ("SELECT plate, vehicle, hash FROM player_vehicles WHERE %s = ?"):format(col),
                { license or identifiers or '' },
                nil
            )
            tried[#tried+1] = { col = col, count = result and #result or 0 }
            if result and #result > 0 then break end
        end
    end

    result = result or {}

    local list = {}

    local function resolveModelAndLabel(data, fallbackStr)
        local mdl, lbl

        if type(data) == 'table' then
            local m = data.model or data.spawncode or data.vehicle or data.name
            local n = data.name or data.label or data.displayName

            if type(m) == 'number' then
                for key, info in pairs(QBCore.Shared.Vehicles or {}) do
                    if info and (info.hash == m or GetHashKey(info.model) == m) then
                        mdl = info.model or key
                        lbl = n or info.name or info.model or key
                        break
                    end
                end
            else
                mdl = m
                lbl = n or m
            end
        elseif type(fallbackStr) == 'string' and fallbackStr ~= '' then
            mdl = fallbackStr
            lbl = fallbackStr
        end

        if not mdl or mdl == '' then mdl = 'sultan' end
        if not lbl or lbl == '' then lbl = mdl end
        return mdl, lbl
    end

    for _, row in ipairs(result) do
        local label = nil
        local model = nil

        if row.vehicle and row.vehicle ~= '' then
            local ok, data = pcall(json.decode, row.vehicle)
            if ok then
                model, label = resolveModelAndLabel(data, row.vehicle)
            else
                model, label = resolveModelAndLabel(nil, row.vehicle)
            end
        end

        if not label or label == '' then label = model or row.plate end

        table.insert(list, {
            plate = row.plate,
            model = model or 'sultan',
            label = label,
        })
    end

    return list
end

local function LogGarageAction(garageId, vehicleRow, action, actorPlayer, opts)
    opts = opts or {}

    local vehicleId = vehicleRow and vehicleRow.id or nil
    local plate     = vehicleRow and vehicleRow.plate or nil
    local model     = vehicleRow and vehicleRow.model or nil

    local actorCid, actorName = nil, nil
    if actorPlayer then
        actorCid  = actorPlayer.PlayerData.citizenid
        actorName = actorPlayer.PlayerData.name
    end

    local targetCid  = opts.targetCid  or nil
    local targetName = opts.targetName or nil

    local extraJson = nil
    if opts.extra and next(opts.extra) ~= nil then
        extraJson = json.encode(opts.extra)
    end

    print(("[pf-jobgarages] LogGarageAction -> garage=%s action=%s plate=%s model=%s actor=%s"):format(
        tostring(garageId),
        tostring(action),
        tostring(plate),
        tostring(model),
        tostring(actorName)
    ))

    SafeQuery(MySQL.insert.await,
        "INSERT INTO job_garage_logs (garage_id, vehicle_id, plate, model, action, actor_cid, actor_name, target_cid, target_name, extra) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        { garageId, vehicleId, plate, model, action, actorCid, actorName, targetCid, targetName, extraJson },
        nil
    )
end

local function LoadFleet(garageId)
    local sql_with_out = [[
        SELECT id, garage_id, plate, model, label, min_grade,
               assignment_type, assigned_citizenid, assigned_name, assigned_grade,
               last_used_at
        FROM job_garage_vehicles
        WHERE garage_id = ? AND active = 1 AND `out` = 0
    ]]
    local sql_no_out = [[
        SELECT id, garage_id, plate, model, label, min_grade,
               assignment_type, assigned_citizenid, assigned_name, assigned_grade,
               last_used_at
        FROM job_garage_vehicles
        WHERE garage_id = ? AND active = 1
    ]]

    local result = SafeQuery(MySQL.query.await, sql_with_out, { garageId }, nil)
    if result == nil then
        result = SafeQuery(MySQL.query.await, sql_no_out, { garageId }, {})
    end
    return result or {}
end

local function LoadOutVehicles(garageId)
    local sql = [[
        SELECT id, garage_id, plate, model, label, min_grade,
               assignment_type, assigned_citizenid, assigned_name, assigned_grade,
               out_citizenid, out_name, out_since,
               last_used_at
        FROM job_garage_vehicles
        WHERE garage_id = ? AND active = 1 AND `out` = 1
    ]]
    local result = SafeQuery(MySQL.query.await, sql, { garageId }, {})
    return result or {}
end

local function LoadPermissions(garageId, cfg)
    local row = SafeQuery(MySQL.single.await,
        "SELECT min_grade_use, min_grade_manage FROM job_garage_permissions WHERE garage_id = ?",
        { garageId },
        nil
    )

    if not row then
        row = {
            min_grade_use    = cfg and (cfg.defaultMinGradeUse or 0) or 0,
            min_grade_manage = tonumber(cfg and cfg.manageGrade) or tonumber(Config.DefaultManageGrade) or 4
        }
    end

    return row
end

local function LoadLogs(garageId)
    local ok, result = pcall(function()
        return MySQL.query.await(
            "SELECT id, vehicle_id, plate, model, action, actor_name, target_name, created_at, extra FROM job_garage_logs WHERE garage_id = ? ORDER BY id DESC LIMIT 50",
            { garageId }
        )
    end)

    if not ok then
        print(('[pf-jobgarages] LoadLogs error: %s'):format(result or 'unknown'))
        return {}
    end

    return result or {}
end

QBCore.Functions.CreateCallback('jobgarages:getGarageData', function(source, cb, garageId)
    local src = source
    local jobName, jobGrade, Player = GetPlayerJob(src)
    local cfg = GetGarageConfig(garageId)

    if not cfg then
        cb({ error = 'invalid_garage' })
        return
    end

    if jobName ~= cfg.job then
        cb({ error = 'wrong_job' })
        return
    end

    local fleet       = LoadFleet(garageId)
    local outVehicles = LoadOutVehicles(garageId)
    local perms       = LoadPermissions(garageId, cfg)
    local logs        = LoadLogs(garageId)

    cb({
        garageId     = garageId,
        garageLabel  = cfg.label,
        job          = jobName,
        jobGrade     = jobGrade,
        isManager    = (CanManageGarage(src, garageId, cfg)),
        onDuty       = Player and Player.PlayerData.job.onduty == true or false,
        requireOnDuty = NeedsDuty(cfg),
        fleet        = fleet,
        outVehicles  = outVehicles,
        permissions  = perms,
        logs         = logs,
        playerCid    = Player and Player.PlayerData.citizenid or nil,
        themeColor   = cfg.themeColor or '#53a2ff'
    })
end)

QBCore.Functions.CreateCallback('jobgarages:getOwnedVehicles', function(source, cb)
    local src = source
    local _, _, Player = GetPlayerJob(src)
    if not Player then cb({}) return end
    local cid = Player.PlayerData.citizenid
    local lic = Player.PlayerData.license
    local list = GetOwnedVehiclesForPlayer(cid, lic)
    print(("[pf-jobgarages] getOwnedVehicles: cid=%s license=%s ownerCol=%s count=%d"):format(tostring(cid), tostring(lic), tostring((Config and Config.PlayerVehiclesOwnerColumn) or 'citizenid'), #(list or {})))
    if #(list or {}) == 0 then
        print("[pf-jobgarages] No owned vehicles found. Verify player_vehicles owner column (citizenid/owner/license/steam/identifier).")
    end
    cb(list)
end)

QBCore.Functions.CreateCallback('jobgarages:takeVehicle', function(source, cb, garageId, fleetId)
    local src = source
    local cfg = GetGarageConfig(garageId)

    if not cfg then
        cb(false, 'invalid_garage')
        return
    end

    local allowed, jobGrade, Player = CanUseGarage(src, garageId, cfg)
    if not allowed then
        TriggerClientEvent('QBCore:Notify', src, 'You cannot use this garage.', 'error')
        cb(false, 'wrong_job')
        return
    end

    -- fleet cars are for staff on shift
    if NeedsDuty(cfg) and not Player.PlayerData.job.onduty then
        cb(false, 'Clock in before you take a fleet vehicle.')
        return
    end

    if not PlayerNear(src, cfg.targetCoords, USE_RANGE) then
        cb(false, 'too_far')
        return
    end

    fleetId = tonumber(fleetId)
    if not fleetId then
        cb(false, 'vehicle_not_found')
        return
    end

    local row = SafeQuery(MySQL.single.await,
        "SELECT id, plate, model, label, min_grade, `out`, assignment_type, assigned_citizenid, assigned_name, assigned_grade FROM job_garage_vehicles WHERE id = ? AND garage_id = ? AND active = 1",
        { fleetId, garageId },
        nil
    )

    if not row then
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle not found.', 'error')
        cb(false, 'vehicle_not_found')
        return
    end

    if row.out == 1 then
        TriggerClientEvent('QBCore:Notify', src, 'This vehicle is already out.', 'error')
        cb(false, 'already_out')
        return
    end

    if jobGrade < (row.min_grade or 0) then
        TriggerClientEvent('QBCore:Notify', src, 'Your grade is too low for this vehicle.', 'error')
        cb(false, 'Insufficient grade for this vehicle.')
        return
    end

    local aType = row.assignment_type or 'none'
    if aType ~= 'none' and Player then
        if aType == 'citizenid' and row.assigned_citizenid and row.assigned_citizenid ~= '' then
            if Player.PlayerData.citizenid ~= row.assigned_citizenid then
                local who = row.assigned_name or 'another employee'
                TriggerClientEvent('QBCore:Notify', src, 'This vehicle is assigned to ' .. who .. '.', 'error')
                cb(false, 'assigned_to_other')
                return
            end
        elseif aType == 'grade' and row.assigned_grade then
            if jobGrade < row.assigned_grade then
                TriggerClientEvent('QBCore:Notify', src, 'This vehicle is reserved for grade ' .. row.assigned_grade .. '+.', 'error')
                cb(false, 'assigned_grade_lock')
                return
            end
        end
    end

    -- only one taker wins when two people take the same car at once
    local changed = SafeQuery(MySQL.update.await,
        "UPDATE job_garage_vehicles SET `out` = 1, out_citizenid = ?, out_name = ?, out_since = NOW(), last_used_at = NOW() WHERE id = ? AND `out` = 0",
        { Player.PlayerData.citizenid, Player.PlayerData.name, row.id },
        0
    )
    if type(changed) == 'number' and changed < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'This vehicle is already out.', 'error')
        cb(false, 'already_out')
        return
    end

    local vrow = SafeQuery(MySQL.single.await,
        "SELECT mods, engine, body FROM player_vehicles WHERE plate = ?",
        { row.plate },
        nil
    )
    if vrow then
        row.mods   = vrow.mods
        row.engine = vrow.engine
        row.body   = vrow.body
    end

    LogGarageAction(garageId, row, 'take', Player, {})

    print(('[pf-jobgarages] Spawning job vehicle %s (%s) for %s'):format(row.plate or 'N/A', row.model or 'N/A', GetPlayerName(src) or src))
    TriggerClientEvent('jobgarages:spawnVehicle', src, row)
    cb(true)
end)

RegisterNetEvent('jobgarages:addFleetVehicle', function(garageId, data)
    local src = source
    local jobName, jobGrade, Player = GetPlayerJob(src)
    local cfg = GetGarageConfig(garageId)
    if not cfg or not Player or type(data) ~= 'table' then return end

    if jobName ~= cfg.job then return end
    if not CanManageGarage(src, garageId, cfg) then
        TriggerClientEvent('QBCore:Notify', src, 'You do not manage this fleet.', 'error')
        return
    end

    local plate = NormalizePlate(data.plate)
    if plate == '' then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid plate.', 'error')
        return
    end

    local owned = GetOwnedVehicleRow(src, plate)
    if not owned then
        TriggerClientEvent('QBCore:Notify', src, 'You can only add a vehicle you own.', 'error')
        return
    end

    -- A fleet car belongs to the job garage only (pfm-garages hides and refuses it), so it must be
    -- parked in a personal garage when it joins: not out in the world and not impounded.
    if tonumber(owned.state) ~= 1 or (tonumber(owned.depotprice) or 0) > 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Park the vehicle in your garage before adding it to the fleet.', 'error')
        return
    end
    if SafeQuery(MySQL.scalar.await, "SELECT id FROM job_garage_vehicles WHERE plate = ? AND active = 1 LIMIT 1", { plate }, nil) then
        TriggerClientEvent('QBCore:Notify', src, 'This vehicle is already in a job fleet.', 'error')
        return
    end

    -- the model is the owned car's, not the client's (it is what every employee spawns)
    local model = type(owned.vehicle) == 'string' and owned.vehicle ~= '' and owned.vehicle or nil
    if not model then
        TriggerClientEvent('QBCore:Notify', src, 'This vehicle has no model on record.', 'error')
        return
    end
    local label = type(data.label) == 'string' and data.label:sub(1, 64) or model
    local minGrade = math.floor(tonumber(data.min_grade) or 0)
    if minGrade < 0 or minGrade > 50 then minGrade = 0 end

    SafeQuery(MySQL.insert.await,
        "INSERT INTO job_garage_vehicles (garage_id, plate, model, label, min_grade, active, assignment_type) VALUES (?, ?, ?, ?, ?, 1, 'none')",
        { garageId, plate, model, label, minGrade },
        nil
    )

    LogGarageAction(garageId, { id = nil, plate = plate, model = model, label = label }, 'add_vehicle', Player, {
        extra = { min_grade = minGrade }
    })

    TriggerClientEvent('QBCore:Notify', src, 'Vehicle added to job fleet.', 'success')
    TriggerClientEvent('jobgarages:refresh', src, garageId)
end)

RegisterNetEvent('jobgarages:removeFleetVehicle', function(garageId, id)
    local src = source
    local jobName, jobGrade, Player = GetPlayerJob(src)
    local cfg = GetGarageConfig(garageId)
    if not cfg then return end

    if jobName ~= cfg.job then return end
    if not CanManageGarage(src, garageId, cfg) then
        TriggerClientEvent('QBCore:Notify', src, 'You do not manage this fleet.', 'error')
        return
    end

    SafeQuery(MySQL.update.await,
        "UPDATE job_garage_vehicles SET active = 0 WHERE id = ? AND garage_id = ?",
        { id, garageId },
        0
    )

    LogGarageAction(garageId, { id = id }, 'remove_vehicle', Player, {})

    TriggerClientEvent('QBCore:Notify', src, 'Vehicle removed from job fleet.', 'success')
    TriggerClientEvent('jobgarages:refresh', src, garageId)
end)

-- Storing marks a fleet car as back in the garage, so it can be taken out again: the player must
-- work there, stand at this garage, and have the car with that plate next to them. The car is
-- removed by the server as well (the client deletes it too), so a stored car cannot stay in the
-- world and be taken out a second time.
RegisterNetEvent('jobgarages:storeVehicle', function(plate, garageId)
    local src = source
    local cfg = GetGarageConfig(garageId)
    if not cfg then return end
    plate = NormalizePlate(plate)

    if plate == '' then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid plate.', 'error')
        return
    end

    local allowed, _, Player = CanUseGarage(src, garageId, cfg)
    if not allowed then
        TriggerClientEvent('QBCore:Notify', src, 'You cannot use this garage.', 'error')
        return
    end

    if not PlayerNear(src, cfg.targetCoords, USE_RANGE) then
        TriggerClientEvent('QBCore:Notify', src, 'You are too far from the garage.', 'error')
        return
    end

    local veh = FindVehicleNear(src, plate)
    if not veh then
        TriggerClientEvent('QBCore:Notify', src, 'Bring the vehicle to the garage to store it.', 'error')
        return
    end

    local row = SafeQuery(MySQL.single.await,
        "SELECT id, plate, model FROM job_garage_vehicles WHERE plate = ? AND garage_id = ? AND active = 1",
        { plate, garageId },
        nil
    )

    if not row then
        TriggerClientEvent('QBCore:Notify', src, 'This is not a job fleet vehicle.', 'error')
        return
    end

    SafeQuery(MySQL.update.await,
    "UPDATE job_garage_vehicles SET `out` = 0, out_citizenid = NULL, out_name = NULL, out_since = NULL, last_used_at = NOW() WHERE id = ?",
    { row.id },
    0
)

    LogGarageAction(garageId, row, 'store', Player, {})

    TriggerClientEvent('jobgarages:storedVehicle', src, plate)
    TriggerClientEvent('QBCore:Notify', src, 'Vehicle stored!', 'success')
    TriggerClientEvent('jobgarages:refresh', src, garageId)

    -- give the client time to take the driver out and delete it itself
    SetTimeout(5000, function()
        if DoesEntityExist(veh) and NormalizePlate(GetVehicleNumberPlateText(veh)) == plate then
            DeleteEntity(veh)
        end
    end)
end)

RegisterNetEvent('jobgarages:forceReturn', function(garageId, vehicleId)
    local src = source
    local jobName, jobGrade, Player = GetPlayerJob(src)
    local cfg = GetGarageConfig(garageId)
    if not cfg or not Player then return end

    if jobName ~= cfg.job then
        TriggerClientEvent('QBCore:Notify', src, 'Wrong job for this garage.', 'error')
        return
    end

    if not CanManageGarage(src, garageId, cfg) then
        TriggerClientEvent('QBCore:Notify', src, 'You do not have permission to force return.', 'error')
        return
    end

    local row = SafeQuery(MySQL.single.await,
        "SELECT id, plate, model FROM job_garage_vehicles WHERE id = ? AND garage_id = ? AND active = 1",
        { vehicleId, garageId },
        nil
    )

    if not row then
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle not found in this garage.', 'error')
        return
    end

    SafeQuery(MySQL.update.await,
        "UPDATE job_garage_vehicles SET `out` = 0, out_citizenid = NULL, out_name = NULL, out_since = NULL WHERE id = ?",
        { row.id },
        0
    )

    LogGarageAction(garageId, row, 'force_return', Player, {})

    TriggerClientEvent('jobgarages:forceDespawn', -1, row.plate)

    TriggerClientEvent('QBCore:Notify', src, 'Vehicle force-returned.', 'success')
    TriggerClientEvent('jobgarages:refresh', src, garageId)
end)

RegisterNetEvent('jobgarages:savePermissions', function(garageId, perms)
    local src = source
    if not garageId or type(perms) ~= 'table' then return end

    local jobName, jobGrade, Player = GetPlayerJob(src)
    local cfg = GetGarageConfig(garageId)
    if not cfg then return end

    if jobName ~= cfg.job then
        TriggerClientEvent('QBCore:Notify', src, 'Wrong job for this garage.', 'error')
        return
    end

    local canManage = CanManageGarage(src, garageId, cfg)
    if not canManage then
        TriggerClientEvent('QBCore:Notify', src, 'You do not have permission to edit this.', 'error')
        return
    end

    local manageGrade = ManageGrade(garageId, cfg)
    local minUse    = tonumber(perms.min_grade_use)    or 0
    local minManage = tonumber(perms.min_grade_manage) or manageGrade

    minUse, minManage = math.floor(minUse), math.floor(minManage)
    if minUse < 0 or minUse > 50 then minUse = 0 end
    if minManage < 0 or minManage > 50 then minManage = manageGrade end
    -- a manager cannot lock themselves (and everyone of their grade) out of management
    if minManage > jobGrade and Player.PlayerData.job.isboss ~= true then
        TriggerClientEvent('QBCore:Notify', src, ('The manage grade cannot be above your own grade (%d).'):format(jobGrade), 'error')
        return
    end

    local row = SafeQuery(MySQL.single.await,
        "SELECT id FROM job_garage_permissions WHERE garage_id = ?",
        { garageId },
        nil
    )

    if row then
        SafeQuery(MySQL.update.await,
            "UPDATE job_garage_permissions SET min_grade_use = ?, min_grade_manage = ? WHERE garage_id = ?",
            { minUse, minManage, garageId },
            0
        )
    else
        SafeQuery(MySQL.insert.await,
            "INSERT INTO job_garage_permissions (garage_id, min_grade_use, min_grade_manage) VALUES (?, ?, ?)",
            { garageId, minUse, minManage },
            nil
        )
    end

    LogGarageAction(garageId, nil, 'update_permissions', Player, {
        extra = {
            min_grade_use    = minUse,
            min_grade_manage = minManage
        }
    })

    TriggerClientEvent('QBCore:Notify', src, 'Garage permissions updated.', 'success')
    TriggerClientEvent('jobgarages:refresh', src, garageId)
end)

RegisterNetEvent('jobgarages:setAssignment', function(garageId, data)
    local src = source
    if not garageId or type(data) ~= 'table' then return end

    local jobName, jobGrade, Player = GetPlayerJob(src)
    local cfg = GetGarageConfig(garageId)
    if not cfg then return end

    if jobName ~= cfg.job then
        TriggerClientEvent('QBCore:Notify', src, 'Wrong job for this garage.', 'error')
        return
    end

    if not CanManageGarage(src, garageId, cfg) then
        TriggerClientEvent('QBCore:Notify', src, 'You do not have permission to edit assignments.', 'error')
        return
    end

    local vehicleId = tonumber(data.id)
    if not vehicleId then return end

    local assignType = data.type or 'none'
    local target     = data.target

    local vrow = SafeQuery(MySQL.single.await,
        "SELECT id, plate, model FROM job_garage_vehicles WHERE id = ? AND garage_id = ? AND active = 1",
        { vehicleId, garageId },
        nil
    )
    if not vrow then
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle not found in this garage.', 'error')
        return
    end

    if assignType == 'none' then
        SafeQuery(MySQL.update.await,
            "UPDATE job_garage_vehicles SET assignment_type = 'none', assigned_citizenid = NULL, assigned_name = NULL, assigned_grade = NULL WHERE id = ?",
            { vehicleId },
            0
        )

        LogGarageAction(garageId, vrow, 'clear_assignment', Player, {})

        TriggerClientEvent('QBCore:Notify', src, 'Assignment cleared.', 'success')

    elseif assignType == 'player' then
        local targetSrc = tonumber(target)
        if not targetSrc then
            TriggerClientEvent('QBCore:Notify', src, 'Enter a valid server ID.', 'error')
            return
        end

        local Target = QBCore.Functions.GetPlayer(targetSrc)
        if not Target then
            TriggerClientEvent('QBCore:Notify', src, 'That player is not online.', 'error')
            return
        end

        local cid  = Target.PlayerData.citizenid
        local name = Target.PlayerData.name

        SafeQuery(MySQL.update.await,
            "UPDATE job_garage_vehicles SET assignment_type = 'citizenid', assigned_citizenid = ?, assigned_name = ?, assigned_grade = NULL WHERE id = ?",
            { cid, name, vehicleId },
            0
        )

        LogGarageAction(garageId, vrow, 'assign_player', Player, {
            targetCid  = cid,
            targetName = name
        })

        TriggerClientEvent('QBCore:Notify', src, ('Assigned to %s.'):format(name), 'success')

    elseif assignType == 'grade' then
        local gradeNum = tonumber(target) or 0
        if gradeNum < 0 then gradeNum = 0 end

        SafeQuery(MySQL.update.await,
            "UPDATE job_garage_vehicles SET assignment_type = 'grade', assigned_citizenid = NULL, assigned_name = NULL, assigned_grade = ? WHERE id = ?",
            { gradeNum, vehicleId },
            0
        )

        LogGarageAction(garageId, vrow, 'assign_grade', Player, {
            extra = { grade = gradeNum }
        })

        TriggerClientEvent('QBCore:Notify', src, ('Reserved for grade %d+.'):format(gradeNum), 'success')
    end

    TriggerClientEvent('jobgarages:refresh', src, garageId)
end)


-- A deleted character (pfm-core, server only): its personal assignments are cleared and any fleet
-- car it had out is marked back in and removed from the world. The garage logs keep its name.
local function ForgetCharacter(cid)
    if type(cid) ~= 'string' or cid == '' or #cid > 64 or not cid:find('^[%w_%-]+$') then return false end
    local out = SafeQuery(MySQL.query.await, "SELECT id, plate FROM job_garage_vehicles WHERE out_citizenid = ? AND `out` = 1", { cid }, {}) or {}
    for _, row in ipairs(out) do
        SafeQuery(MySQL.update.await,
            "UPDATE job_garage_vehicles SET `out` = 0, out_citizenid = NULL, out_name = NULL, out_since = NULL WHERE id = ?",
            { row.id }, 0)
        if row.plate then TriggerClientEvent('jobgarages:forceDespawn', -1, row.plate) end
    end
    SafeQuery(MySQL.update.await,
        "UPDATE job_garage_vehicles SET assignment_type = 'none', assigned_citizenid = NULL, assigned_name = NULL, assigned_grade = NULL WHERE assignment_type = 'citizenid' AND assigned_citizenid = ?",
        { cid }, 0)
    return true
end
PFJobGarages = { ForgetCharacter = ForgetCharacter, CanManageGarage = CanManageGarage }

AddEventHandler('pfm-core:server:characterDeleted', function(cid) ForgetCharacter(cid) end)
