local QBCore = exports['pfm-core']:GetCoreObject()

local Advanced = Config.AdvancedSystems or {}
local LiftedByPlate = {}
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

local function setLiftState(plate, state)
    plate = normPlate(plate)
    LiftedByPlate[plate] = state == true
    TriggerServerEvent('pf-mechanicjob:server:advanced:setLiftState', plate, state == true)
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

    local plate = normPlate(GetVehicleNumberPlateText(veh))
    local coords = GetEntityCoords(PlayerPedId())
    local inBay = isInPitBay(coords)

    local duration = (Advanced.Alignment and Advanced.Alignment.BaseDurationMs) or 20000
    if inBay then
        duration = math.floor(duration * ((Advanced.PitBays and Advanced.PitBays.ServiceSpeedMultiplier) or 1.0))
    end

    if not waitProgress('pf_align_rack', 'Running alignment rack calibration...', duration) then
        return
    end

    local st = Entity(veh).state
    local partDamage = st.partDamage or {}
    local reduction = (Advanced.Alignment and Advanced.Alignment.WearReduction) or 12
    partDamage.suspension = math.max(0, (partDamage.suspension or 0) - reduction)
    partDamage.axle = math.max(0, (partDamage.axle or 0) - math.floor(reduction * 0.8))

    Entity(veh).state:set('partDamage', partDamage, true)
    notify(('Alignment complete for %s'):format(plate), 'success')
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
    local cost = 120

    if toolName == 'obd_scanner' then
        if eng < 75 then
            msg = ('OBD report: Engine fault trend detected (%d%% health)'):format(eng)
        else
            msg = 'OBD report: Fuel trims and ignition timing within range'
        end
        cost = 150
    elseif toolName == 'multimeter' then
        local alt = 100 - (dmg.alternator or 0)
        msg = ('Multimeter: Charging output estimated at %d%%'):format(math.max(0, alt))
        cost = 100
    elseif toolName == 'coolant_pressure_tester' then
        local coolant = 100 - (dmg.coolant or 0)
        local radiator = 100 - (dmg.radiator or 0)
        msg = ('Coolant pressure test: Coolant %d%% / Radiator %d%%'):format(math.max(0, coolant), math.max(0, radiator))
        cost = 180
    elseif toolName == 'evap_smoke_machine' then
        if body < 70 then
            msg = 'EVAP smoke result: potential vacuum leak near intake routing'
        else
            msg = 'EVAP smoke result: no visible leak'
        end
        cost = 200
    end

    if waitProgress('pf_adv_diag', 'Collecting diagnostic data...', 6500) then
        notify(msg, 'primary')
        TriggerServerEvent('pf-mechanicjob:server:advanced:diagnosticReport', {
            plate = plate,
            tool = toolName,
            cost = cost,
            engine = eng,
            body = body
        })

        if eng <= 30 then
            local coords = GetEntityCoords(veh)
            TriggerServerEvent('pf-mechanicjob:server:advanced:requestTow', {
                plate = plate,
                reason = 'critical_engine_failure',
                coords = { x = coords.x, y = coords.y, z = coords.z }
            })
            notify('Tow integration notified: vehicle is in critical condition', 'error')
        end
    end
end

local function beginClutchWorkflow()
    local veh = getClosestVehicle(5.5)
    if not veh then
        notify('No vehicle nearby', 'error')
        return
    end

    local plate = normPlate(GetVehicleNumberPlateText(veh))

    local clutchCfg = (Advanced.ClutchWorkflow or {})
    if clutchCfg.Enabled and clutchCfg.RequireLiftedVehicle then
        local isLifted = callback('pf-mechanicjob:server:advanced:getLiftState', plate)
        if not isLifted then
            notify('Lift vehicle with floor jack + jack stands first', 'error')
            return
        end
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

    local consume = {}
    if toolChoice == 'bread_method' then
        consume.sliced_bread = 1
    end

    local methodText = toolChoice == 'pulley_puller' and 'Pulling pilot bearing with puller...' or 'Hydraulic bread method for pilot bearing...'
    if not waitProgress('pf_clutch_7', methodText, 7000) then return end
    if not waitProgress('pf_clutch_8', 'Installing new clutch components and reassembly...', 12000) then return end

    TriggerServerEvent('pf-mechanicjob:server:advanced:completeClutchWorkflow', {
        plate = plate,
        consume = consume,
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

local function spawnRoadsideJob()
    if ActiveRoadside then
        notify('Roadside task already active', 'error')
        return
    end

    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local fwd = GetEntityForwardVector(ped)

    local spawn = vector3(pcoords.x + (fwd.x * 35.0), pcoords.y + (fwd.y * 35.0), pcoords.z)
    local model = joaat((Config.WorkOrderSystem and Config.WorkOrderSystem.vehicles and Config.WorkOrderSystem.vehicles[math.random(#Config.WorkOrderSystem.vehicles)]) or 'sultan')

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local veh = CreateVehicle(model, spawn.x, spawn.y, spawn.z, heading, true, false)
    SetVehicleEngineHealth(veh, 250.0)
    SetVehicleBodyHealth(veh, 450.0)
    SetVehicleUndriveable(veh, true)
    SetVehicleDoorsLocked(veh, 2)

    local blip = AddBlipForEntity(veh)
    SetBlipSprite(blip, 446)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.9)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Roadside Service')
    EndTextCommandSetBlipName(blip)

    ActiveRoadside = {
        vehicle = veh,
        blip = blip,
        plate = normPlate(GetVehicleNumberPlateText(veh)),
    }
    -- the server records the job; it pays only for this car
    TriggerServerEvent('pf-mechanicjob:server:advanced:startRoadside', NetworkGetNetworkIdFromEntity(veh))

    notify('Roadside service generated. Repair and stabilize the vehicle.', 'success')

    CreateThread(function()
        while ActiveRoadside do
            Wait(2000)
            if not DoesEntityExist(ActiveRoadside.vehicle) then
                RemoveBlip(ActiveRoadside.blip)
                ActiveRoadside = nil
                break
            end

            local eng = GetVehicleEngineHealth(ActiveRoadside.vehicle)
            local body = GetVehicleBodyHealth(ActiveRoadside.vehicle)
            local repaired = eng >= 900.0 and body >= 900.0

            if repaired then
                SetVehicleUndriveable(ActiveRoadside.vehicle, false)
                -- keeps reporting until the server confirms (it pays after a minimum repair time)
                TriggerServerEvent('pf-mechanicjob:server:advanced:completeRoadside', {
                    plate = ActiveRoadside.plate,
                    engine = eng,
                    body = body,
                })
            end
        end
    end)
end

RegisterNetEvent('pf-mechanicjob:client:advanced:roadsideDone', function()
    if not ActiveRoadside then return end
    if ActiveRoadside.blip then RemoveBlip(ActiveRoadside.blip) end
    ActiveRoadside = nil
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

        local plate = normPlate(GetVehicleNumberPlateText(veh))
        local lifted = callback('pf-mechanicjob:server:advanced:getLiftState', plate)

        if lifted then
            if waitProgress('pf_lower_car', 'Lowering vehicle from jack...', 4500) then
                lowerVehicle(veh)
                setLiftState(plate, false)
                notify('Vehicle lowered', 'success')
            end
        else
            if waitProgress('pf_lift_car', 'Lifting vehicle with floor jack...', 5500) then
                local h = ((Advanced.LiftSystem or {}).JackLiftHeight) or 0.42
                liftVehicle(veh, h)
                setLiftState(plate, true)
                notify('Vehicle lifted', 'success')
            end
        end
        return
    end

    if toolName == 'jack_stands' then
        local veh = getClosestVehicle(5.0)
        if not veh then notify('No vehicle nearby', 'error') return end
        local plate = normPlate(GetVehicleNumberPlateText(veh))
        local lifted = callback('pf-mechanicjob:server:advanced:getLiftState', plate)
        if not lifted then
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
