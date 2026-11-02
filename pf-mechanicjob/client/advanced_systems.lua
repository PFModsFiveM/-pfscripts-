local QBCore = exports['pfm-core']:GetCoreObject()

local Advanced = Config.AdvancedSystems or {}
local ActiveRoadside = nil

local function normPlate(plate)
    return tostring(plate or ''):gsub('%s+', ''):upper()
end

local function notify(msg, t)
    QBCore.Functions.Notify(msg, t or 'primary')
end

local function getClosestVehicle(radius)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh = GetClosestVehicle(coords.x, coords.y, coords.z, radius or 5.0, 0, 70)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        return veh
    end
    return nil
end

local function waitProgress(id, text, ms, anim)
    local done = false
    local canceled = false

    if QBCore and QBCore.Functions and QBCore.Functions.Progressbar then
        QBCore.Functions.Progressbar(id, text, ms, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableCombat = true
        }, anim or {
            animDict = 'mini@repair',
            anim = 'fixing_a_ped',
            flags = 49,
        }, {}, {}, function()
            done = true
        end, function()
            done = true
            canceled = true
        end)

        while not done do
            Wait(0)
        end
    else
        Wait(ms)
    end

    return not canceled
end

local function callback(name, ...)
    local p = promise.new()
    QBCore.Functions.TriggerCallback(name, function(res)
        p:resolve(res)
    end, ...)
    return Citizen.Await(p)
end

local function isInPitBay(coords)
    local pitCfg = (Advanced.PitBays or {})
    if not pitCfg.Enabled then return false end
    for _, zone in ipairs(pitCfg.Zones or {}) do
        if #(coords - zone.coords) <= (zone.radius or 6.0) then
            return true, zone
        end
    end
    return false, nil
end

-- the server keeps the lift per car (a mechanic with a floor jack at it)
local function setLiftState(veh, state)
    TriggerServerEvent('pf-mechanicjob:server:advanced:setLiftState', NetworkGetNetworkIdFromEntity(veh), state == true)
end

local function isLifted(veh)
    return callback('pf-mechanicjob:server:advanced:getLiftState', NetworkGetNetworkIdFromEntity(veh)) == true
end

local function liftVehicle(veh, height)
    local coords = GetEntityCoords(veh)
    SetEntityCoords(veh, coords.x, coords.y, coords.z + (height or 0.42), false, false, false, false)
    FreezeEntityPosition(veh, true)
end

local function lowerVehicle(veh)
    FreezeEntityPosition(veh, false)
    SetVehicleOnGroundProperly(veh)
end

local function runAlignment()
    local veh = getClosestVehicle(5.5)
    if not veh then
        notify('No vehicle nearby', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    local inBay = isInPitBay(coords)

    local duration = (Advanced.Alignment and Advanced.Alignment.BaseDurationMs) or 20000
    if inBay then
        duration = math.floor(duration * ((Advanced.PitBays and Advanced.PitBays.ServiceSpeedMultiplier) or 1.0))
    end

    if not waitProgress('pf_align_rack', 'Running alignment rack calibration...', duration) then
        return
    end

    -- the server lowers the suspension and axle wear (partDamage is a server-set state bag) and
    -- confirms with a notification
    TriggerServerEvent('pf-mechanicjob:server:advanced:completeAlignment', NetworkGetNetworkIdFromEntity(veh))
end

local function runDiagnosticsTool(toolName)
    local veh = getClosestVehicle(5.0)
    if not veh then
        notify('No vehicle nearby for diagnostics', 'error')
        return
    end

    local plate = normPlate(GetVehicleNumberPlateText(veh))
    local st = Entity(veh).state
    local dmg = st.partDamage or {}
    local eng = math.floor(GetVehicleEngineHealth(veh) / 10)
    local body = math.floor(GetVehicleBodyHealth(veh) / 10)

    local msg = 'No critical faults detected'

    if toolName == 'obd_scanner' then
        if eng < 75 then
            msg = ('OBD report: Engine fault trend detected (%d%% health)'):format(eng)
        else
            msg = 'OBD report: Fuel trims and ignition timing within range'
        end
    elseif toolName == 'multimeter' then
        local alt = 100 - (dmg.alternator or 0)
        msg = ('Multimeter: Charging output estimated at %d%%'):format(math.max(0, alt))
    elseif toolName == 'coolant_pressure_tester' then
        local coolant = 100 - (dmg.coolant or 0)
        local radiator = 100 - (dmg.radiator or 0)
        msg = ('Coolant pressure test: Coolant %d%% / Radiator %d%%'):format(math.max(0, coolant), math.max(0, radiator))
    elseif toolName == 'evap_smoke_machine' then
        if body < 70 then
            msg = 'EVAP smoke result: potential vacuum leak near intake routing'
        else
            msg = 'EVAP smoke result: no visible leak'
        end
    end

    if waitProgress('pf_adv_diag', 'Collecting diagnostic data...', 6500) then
        notify(msg, 'primary')
        -- the server prices the scan and reads the car itself
        TriggerServerEvent('pf-mechanicjob:server:advanced:diagnosticReport', {
            netId = NetworkGetNetworkIdFromEntity(veh),
            tool = toolName,
        })

        -- offered on the server's own rule (shared/tow_check.lua): engine, body, tank or a worn-out
        -- part, not only a low engine. The shop's account pays a tow, so only the boss orders one;
        -- the server reads the car again, checks the boss and says whether the tow was ordered.
        local why = PFMechTow and DoesEntityExist(veh) and PFMechTow.Reason(GetVehicleEngineHealth(veh),
            GetVehicleBodyHealth(veh), GetVehiclePetrolTankHealth(veh), Entity(veh).state.partDamage)
        if why then
            local job = (QBCore.Functions.GetPlayerData() or {}).job or {}
            if job.isboss == true then
                TriggerServerEvent('pf-mechanicjob:server:advanced:requestTow', {
                    plate = plate,
                    reason = PFMechTow.ReasonLabels[why] or 'service_request',
                })
            else
                notify('This car cannot be driven: your shop boss can order a tow', 'error')
            end
        end
    end
end

local function beginClutchWorkflow()
    local veh = getClosestVehicle(5.5)
    if not veh then
        notify('No vehicle nearby', 'error')
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)

    local clutchCfg = (Advanced.ClutchWorkflow or {})
    if clutchCfg.Enabled and clutchCfg.RequireLiftedVehicle and not isLifted(veh) then
        notify('Lift vehicle with floor jack + jack stands first', 'error')
        return
    end

    local needed = {
        service_clutch_replacement = 1,
        transmission_jack = clutchCfg.RequireTransmissionJack and 1 or 0,
        flywheel_service_kit = clutchCfg.RequireFlywheelServiceKit and 1 or 0,
    }

    local hasNeeded = callback('pf-mechanicjob:server:advanced:hasItems', needed)
    if not hasNeeded then
        notify('Missing required clutch workflow tools/items', 'error')
        return
    end

    -- the server records the start (car and time); it completes the job only after the steps' time
    local p = promise.new()
    QBCore.Functions.TriggerCallback('pf-mechanicjob:server:advanced:startClutch', function(ok, why)
        p:resolve({ ok = ok, why = why })
    end, netId)
    local started = Citizen.Await(p)
    if not started.ok then
        notify(started.why or 'The clutch job could not be started', 'error')
        return
    end

    if not waitProgress('pf_clutch_1', 'Raising vehicle and removing undertray...', 7500) then return end
    if not waitProgress('pf_clutch_2', 'Disconnecting transmission wiring...', 7000) then return end
    if not waitProgress('pf_clutch_3', 'Positioning transmission jack...', 6000) then return end
    if not waitProgress('pf_clutch_4', 'Removing transmission assembly...', 11000) then return end
    if not waitProgress('pf_clutch_5', 'Removing clutch and pressure plate...', 9000) then return end
    if not waitProgress('pf_clutch_6', 'Inspecting flywheel, resurfacing/replacing as needed...', 9000) then return end

    local toolChoice = callback('pf-mechanicjob:server:advanced:hasAnyItems', {
        { id = 'pulley_puller', items = { pulley_puller = 1 } },
        { id = 'bread_method', items = { mechanic_hammer = 1, mechanic_socket = 1, sliced_bread = 1 } },
    })

    if not toolChoice then
        notify('Need pulley puller OR hammer + socket + sliced bread for pilot bearing step', 'error')
        return
    end

    local methodText = toolChoice == 'pulley_puller' and 'Pulling pilot bearing with puller...' or 'Hydraulic bread method for pilot bearing...'
    if not waitProgress('pf_clutch_7', methodText, 7000) then return end
    if not waitProgress('pf_clutch_8', 'Installing new clutch components and reassembly...', 12000) then return end

    -- the server checks the car, the lift, the items and the time, and takes what the method uses
    TriggerServerEvent('pf-mechanicjob:server:advanced:completeClutchWorkflow', {
        netId = netId,
        pilotBearingMethod = toolChoice
    })
end

local function isNearChopZone(coords)
    local cfg = (Advanced.ChopShop or {})
    for _, zone in ipairs(cfg.Zones or {}) do
        if #(coords - zone.coords) <= (zone.radius or 15.0) then
            return true, zone
        end
    end
    return false, nil
end

local function startChop()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        notify('Sit in the target vehicle first', 'error')
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    local coords = GetEntityCoords(ped)
    local nearZone = isNearChopZone(coords)
    if not nearZone then
        notify('You are not in a chop zone', 'error')
        return
    end

    local plate = normPlate(GetVehicleNumberPlateText(veh))

    if not waitProgress('pf_chop_1', 'Stripping body panels...', 8500) then return end
    if not waitProgress('pf_chop_2', 'Pulling drivetrain components...', 10000) then return end
    if not waitProgress('pf_chop_3', 'Cutting frame and collecting salvage...', 9000) then return end

    -- the server checks the car and the zone, then removes the car
    TriggerServerEvent('pf-mechanicjob:server:advanced:completeChop', { plate = plate, netId = NetworkGetNetworkIdFromEntity(veh) })
end

-- A road spot 55-145 m from the mechanic for the call's car (the server spawns the car there and
-- checks the distance; it cannot read road nodes itself).
local function findRoadsideSpot()
    local p = GetEntityCoords(PlayerPedId())
    for _ = 1, 15 do
        local ang = math.random() * 2.0 * math.pi
        local dist = 70.0 + math.random() * 60.0
        local found, node, heading = GetClosestVehicleNodeWithHeading(p.x + math.cos(ang) * dist, p.y + math.sin(ang) * dist, p.z, 1, 3.0, 0)
        if found and node then
            local d = #(vector2(node.x, node.y) - vector2(p.x, p.y))
            if d >= 55.0 and d <= 145.0 and math.abs(node.z - p.z) <= 35.0 then
                return { x = node.x, y = node.y, z = node.z, h = heading or 0.0 }
            end
        end
    end
    return nil
end

local function endRoadside()
    if not ActiveRoadside then return end
    if ActiveRoadside.blip and DoesBlipExist(ActiveRoadside.blip) then RemoveBlip(ActiveRoadside.blip) end
    ActiveRoadside = nil
end

local function spawnRoadsideJob()
    if ActiveRoadside then
        notify('Roadside task already active', 'error')
        return
    end
    local spot = findRoadsideSpot()
    if not spot then
        notify('No road nearby for a roadside call', 'error')
        return
    end
    -- the server makes the broken car and answers with roadsideStarted
    TriggerServerEvent('pf-mechanicjob:server:advanced:startRoadside', spot)
end

-- The server spawned the call's car (its engine and body worn out on the server): show it, make it
-- look broken for the diagnostics, and tell the server once both parts read repaired. The server
-- decides the payment from its own state of that car.
RegisterNetEvent('pf-mechanicjob:client:advanced:roadsideStarted', function(data)
    if type(data) ~= 'table' or not data.netId then return end
    endRoadside()
    local blip = AddBlipForCoord(data.x or 0.0, data.y or 0.0, data.z or 0.0)
    SetBlipSprite(blip, 446)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.9)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Roadside Service')
    EndTextCommandSetBlipName(blip)
    local job = { netId = data.netId, blip = blip, damaged = false }
    ActiveRoadside = job
    notify('Roadside call: a broken-down car is waiting. Repair the engine and body with parts.', 'success')

    CreateThread(function()
        while ActiveRoadside == job do
            Wait(2000)
            local veh = NetworkDoesNetworkIdExist(job.netId) and NetToVeh(job.netId) or 0
            if veh ~= 0 and DoesEntityExist(veh) then
                if not job.damaged then
                    -- the look of a breakdown: diagnostics read engine and body health from the car
                    local t = GetGameTimer()
                    while not NetworkHasControlOfEntity(veh) and GetGameTimer() - t < 1500 do
                        NetworkRequestControlOfEntity(veh)
                        Wait(0)
                    end
                    if NetworkHasControlOfEntity(veh) then
                        SetVehicleEngineHealth(veh, 250.0)
                        SetVehicleBodyHealth(veh, 450.0)
                        SetVehicleUndriveable(veh, true)
                        SetVehicleDoorsLocked(veh, 2)
                        job.damaged = true
                    end
                end
                local pd = Entity(veh).state.partDamage or {}
                if (tonumber(pd.engine_part) or 0) <= 0 and (tonumber(pd.body_part) or 0) <= 0 then
                    -- keeps asking until the server confirms (it pays after a minimum repair time)
                    TriggerServerEvent('pf-mechanicjob:server:advanced:completeRoadside')
                end
            end
        end
    end)
end)

RegisterNetEvent('pf-mechanicjob:client:advanced:roadsideDone', function()
    endRoadside()
end)

RegisterNetEvent('pf-mechanicjob:client:advanced:beginClutchWorkflow', function()
    beginClutchWorkflow()
end)

RegisterNetEvent('pf-mechanicjob:client:advanced:useTool', function(toolName)
    if not (Advanced.Enabled == true) then return end

    if toolName == 'alignment_rack_tool' then
        runAlignment()
        return
    end

    if toolName == 'floor_jack' then
        local veh = getClosestVehicle(5.0)
        if not veh then notify('No vehicle nearby', 'error') return end

        if isLifted(veh) then
            if waitProgress('pf_lower_car', 'Lowering vehicle from jack...', 4500) then
                lowerVehicle(veh)
                setLiftState(veh, false)
                notify('Vehicle lowered', 'success')
            end
        else
            if waitProgress('pf_lift_car', 'Lifting vehicle with floor jack...', 5500) then
                local h = ((Advanced.LiftSystem or {}).JackLiftHeight) or 0.42
                liftVehicle(veh, h)
                setLiftState(veh, true)
                notify('Vehicle lifted', 'success')
            end
        end
        return
    end

    if toolName == 'jack_stands' then
        local veh = getClosestVehicle(5.0)
        if not veh then notify('No vehicle nearby', 'error') return end
        if not isLifted(veh) then
            notify('Use floor jack first', 'error')
            return
        end
        if waitProgress('pf_stands', 'Securing jack stands...', 5000) then
            notify('Jack stands secured', 'success')
        end
        return
    end

    if toolName == 'transmission_jack' then
        notify('Transmission jack ready for drivetrain work', 'primary')
        return
    end

    if toolName == 'obd_scanner' or toolName == 'multimeter' or toolName == 'coolant_pressure_tester' or toolName == 'evap_smoke_machine' then
        runDiagnosticsTool(toolName)
        return
    end

    if toolName == 'chop_kit' then
        startChop()
        return
    end
end)

RegisterNetEvent('pf-mechanicjob:client:openTuningWorkbench', function(sourceType)
    -- Fallback path: open existing work orders/tablet while keeping tuning entrypoint.
    TriggerEvent('pf-mechanicjob:client:openWorkOrders', sourceType or 'computer')
    notify('Tuning workbench opened through mechanic tablet', 'success')
end)

RegisterCommand((Advanced.RoadsideService and Advanced.RoadsideService.Command) or 'roadside', function()
    if not (Advanced.Enabled and (Advanced.RoadsideService or {}).Enabled) then
        notify('Roadside system disabled', 'error')
        return
    end
    spawnRoadsideJob()
end, false)

RegisterCommand((Advanced.ChopShop and Advanced.ChopShop.Command) or 'chopshop', function()
    if not (Advanced.Enabled and (Advanced.ChopShop or {}).Enabled) then
        notify('Chop shop system disabled', 'error')
        return
    end
    startChop()
end, false)

RegisterCommand('mechskills', function()
    if not (Advanced.Enabled and (Advanced.SkillTree or {}).Enabled) then
        notify('Skill tree disabled', 'error')
        return
    end

    local data = callback('pf-mechanicjob:server:advanced:getSkillTree')
    if not data then
        notify('Could not load skill tree', 'error')
        return
    end

    local menu = {
        { header = ('Mechanic Skills (Points: %d)'):format(data.availablePoints or 0), isMenuHeader = true },
    }

    for skillId, node in pairs(data.nodes or {}) do
        local unlocked = (data.unlocked or {})[skillId] == true
        local reqText = ''
        if not unlocked and node.requires and #node.requires > 0 then
            reqText = (' | req: %s'):format(table.concat(node.requires, ', '))
        end

        menu[#menu + 1] = {
            header = ('%s %s'):format(unlocked and '[UNLOCKED]' or '[LOCKED]', node.label or skillId),
            txt = ('Cost: %d%s | %s'):format(node.cost or 1, reqText, node.description or ''),
            params = unlocked and {} or {
                event = 'pf-mechanicjob:client:advanced:unlockSkill',
                args = { skillId = skillId }
            }
        }
    end

    exports['pfm-menu']:openMenu(menu)
end, false)

RegisterNetEvent('pf-mechanicjob:client:advanced:unlockSkill', function(data)
    if not data or not data.skillId then return end
    TriggerServerEvent('pf-mechanicjob:server:advanced:unlockSkill', data.skillId)
end)
