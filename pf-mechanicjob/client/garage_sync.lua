local QBCore = exports['pfm-core']:GetCoreObject()

-- Track vehicles spawned from garage
local garageSpawnedVehicles = {}

-- Helper: Which garage system is active?
local function getGarageSystem()
    return (Config and Config.GarageSystem) or 'qb-garages'
end

-- partDamage, mileage and NOS are vehicle state bags only the server writes (sv_stateBagStrictMode):
-- a spawned car asks the server to load its saved state from the database.
local function requestRestore(veh)
    if veh and veh ~= 0 and DoesEntityExist(veh) and NetworkGetEntityIsNetworked(veh) then
        TriggerServerEvent('pf_mech:server:restoreVehicleState', NetworkGetNetworkIdFromEntity(veh))
    end
end

-- Register vehicle spawn event for qb-garages
RegisterNetEvent('QBCore:Client:OnVehicleSpawn', function(veh)
    if getGarageSystem() ~= 'qb-garages' then return end
    
    if not veh or not DoesEntityExist(veh) then return end
    Wait(500)
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    
    requestRestore(veh)
    QBCore.Functions.TriggerCallback('pf_mech:loadVehicleState', function(data)
        if not data then return end
        if data.engineHealth then SetVehicleEngineHealth(veh, tonumber(data.engineHealth)) end
        if data.bodyHealth then SetVehicleBodyHealth(veh, tonumber(data.bodyHealth)) end
        if data.tankHealth then SetVehiclePetrolTankHealth(veh, tonumber(data.tankHealth)) end
        if data.dirtLevel then SetVehicleDirtLevel(veh, tonumber(data.dirtLevel)) end
    end, plate)
    
    garageSpawnedVehicles[plate] = veh
end)

-- cd_garages compatibility: monitor all vehicle entries
if getGarageSystem() == 'cd_garages' then
    local lastVehicleCheck = {}
    
    CreateThread(function()
        while true do
            Wait(1000)
            
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                
                if veh ~= 0 and DoesEntityExist(veh) then
                    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
                    
                    -- Only load once per vehicle
                    if not lastVehicleCheck[plate] then
                        lastVehicleCheck[plate] = true
                        
                        -- Load diagnostics for this vehicle
                        QBCore.Functions.TriggerCallback('pf_mech:loadVehicleState', function(data)
                            if data and data.partDamage then
                                local state = Entity(veh).state
                                local currentState = state.partDamage or {}
                                
                                -- Only apply if state is empty (freshly spawned)
                                local isEmpty = true
                                for k, v in pairs(currentState) do
                                    if tonumber(v) and tonumber(v) > 0 then
                                        isEmpty = false
                                        break
                                    end
                                end
                                
                                if isEmpty then
                                    requestRestore(veh)
                                    if data.engineHealth then SetVehicleEngineHealth(veh, tonumber(data.engineHealth)) end
                                    if data.bodyHealth then SetVehicleBodyHealth(veh, tonumber(data.bodyHealth)) end
                                    if data.tankHealth then SetVehiclePetrolTankHealth(veh, tonumber(data.tankHealth)) end
                                    if data.dirtLevel then SetVehicleDirtLevel(veh, tonumber(data.dirtLevel)) end
                                    
                                    if Config.Debug then
                                        print(string.format('[GARAGE SYNC][CD] Restored %s: oil=%.1f%%, brakes=%.1f%%', plate, 
                                            tonumber(data.partDamage.oil) or 0, 
                                            tonumber(data.partDamage.brakes) or 0))
                                    end
                                end
                            end
                        end, plate)
                    end
                end
            end
        end
    end)
    
    -- NEW: More aggressive vehicle deletion monitoring for cd_garages
    local trackedVehicles = {}
    
    CreateThread(function()
        while true do
            Wait(500) -- Check every 500ms for faster detection
            
            local ped = PlayerPedId()
            
            -- Track all vehicles player is in
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 and DoesEntityExist(veh) then
                    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
                    if GetPedInVehicleSeat(veh, -1) == ped then
                        trackedVehicles[plate] = {
                            vehicle = veh,
                            entity = veh,
                            lastSeen = GetGameTimer(),
                            plate = plate
                        }
                    end
                end
            end
            
            -- Check for deleted vehicles (garage storage)
            for plate, data in pairs(trackedVehicles) do
                local exists = DoesEntityExist(data.vehicle)
                local timeSince = GetGameTimer() - data.lastSeen
                
                -- If vehicle no longer exists OR hasn't been seen in 3 seconds (stored)
                if not exists or timeSince > 3000 then
                    if Config.Debug then
                        print(string.format('[GARAGE SYNC][CD] Vehicle %s %s, saving...', 
                            plate, 
                            not exists and 'deleted' or 'not seen'))
                    end
                    
                    -- Force save before cleanup
                    TriggerServerEvent('pf_mech:sync:forceSave', plate)
                    
                    -- Clean up tracking
                    trackedVehicles[plate] = nil
                    lastVehicleCheck[plate] = nil
                    
                    if Config.Debug then
                        print(string.format('[GARAGE SYNC][CD] Saved %s to database', plate))
                    end
                end
            end
        end
    end)
end

-- Helper: Build payload from vehicle
local function buildPayloadFromVehicle(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    local state = Entity(veh).state
    local partDamage = state.partDamage or {}
    local mileage = tonumber(state.mileage) or 0
    
    SetVehicleModKit(veh, 0)
    local mods = {}
    for i = 0, 49 do
        local mod = GetVehicleMod(veh, i)
        if mod and mod ~= -1 then mods[tostring(i)] = mod end
    end
    
    local cosmetics = {
        windowTint = GetVehicleWindowTint(veh),
        wheelType = GetVehicleWheelType(veh),
        xenonColor = GetVehicleXenonLightsColour(veh),
        plateIndex = GetVehicleNumberPlateTextIndex(veh),
        livery = GetVehicleLivery(veh),
        extras = {}
    }
    
    -- Capture extras
    for i = 0, 20 do
        if DoesExtraExist(veh, i) then
            cosmetics.extras[tostring(i)] = IsVehicleExtraTurnedOn(veh, i)
        end
    end
    
    local pr, pg, pb = GetVehicleCustomPrimaryColour(veh)
    local sr, sg, sb = GetVehicleCustomSecondaryColour(veh)
    local colors = {
        primary = (pr and pg and pb) and {pr, pg, pb} or nil,
        secondary = (sr and sg and sb) and {sr, sg, sb} or nil,
        pearlescent = GetVehicleExtraColours(veh),
        wheel = select(2, GetVehicleExtraColours(veh))
    }
    
    return {
        plate = plate,
        mods = mods,
        cosmetics = cosmetics,
        colors = colors,
        partDamage = partDamage,
        mileage = mileage,
        engineHealth = GetVehicleEngineHealth(veh),
        bodyHealth = GetVehicleBodyHealth(veh),
        tankHealth = GetVehiclePetrolTankHealth(veh),
        dirtLevel = GetVehicleDirtLevel(veh),
        -- NOS snapshot (optional)
        nos = (function()
            local s = Entity(veh).state.nos or nil
            if not s then return nil end
            return { has = s.has and true or false, level = math.floor(tonumber(s.level) or 0), color = s.color or nil }
        end)()
    }
end

-- Continuous state sync (every 10 seconds while driving)
-- This ensures server ALWAYS has latest damage state, so when qb-garages stores the car, it's up-to-date
CreateThread(function()
    while true do
        Wait(10000) -- 10 seconds
        
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and DoesEntityExist(veh) then
                if GetPedInVehicleSeat(veh, -1) == ped then
                    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
                    local state = Entity(veh).state
                    
                    -- Get FULL vehicle properties using qb-core function
                    local props = QBCore.Functions.GetVehicleProperties(veh)
                    
                    -- Add our custom diagnostics data
                    props.partDamage = state.partDamage or {}
                    props.mileage = tonumber(state.mileage) or 0
                    
                    -- Tell server to cache this full state
                    if getGarageSystem() == 'qb-garages' then
                        TriggerServerEvent('pf_mech:sync:cacheVehicleState', {
                            plate = plate,
                            netId = NetworkGetNetworkIdFromEntity(veh),
                            props = props  -- Send entire props object
                        })
                    elseif getGarageSystem() == 'cd_garages' then
                        -- cd_garages: use their export/event for state sync if needed
                        TriggerServerEvent('pf_mech:sync:cacheVehicleState', {
                            plate = plate,
                            netId = NetworkGetNetworkIdFromEntity(veh),
                            props = props  -- Send entire props object
                        })
                    end
                    
                    if Config.Debug then
                        print(string.format('[GARAGE SYNC] Synced full state: %s (oil: %.1f%%)', 
                            plate, 
                            tonumber((props.partDamage or {}).oil) or 0
                        ))
                    end
                end
            end
        end
    end
end)

-- Export for qb-garages to use (captures everything via GetVehicleProperties)
exports('SyncVehicleDiagnostics', function(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    local state = Entity(veh).state
    local props = QBCore.Functions.GetVehicleProperties(veh)
    props.partDamage = state.partDamage or {}
    props.mileage = tonumber(state.mileage) or 0
    
    TriggerServerEvent('pf_mech:saveFullDiagnostics', plate, props)
end)

-- Export for qb-garages to use
exports('RestoreVehicleDiagnostics', function(veh, diag)
    if not veh or not DoesEntityExist(veh) or not diag then return end
    -- wear and mileage come from the server's saved copy, not from the caller's data
    requestRestore(veh)
    if diag.engineHealth then SetVehicleEngineHealth(veh, diag.engineHealth + 0.0) end
    if diag.bodyHealth then SetVehicleBodyHealth(veh, diag.bodyHealth + 0.0) end
end)

-- Apply diagnostics snapshot to vehicle
exports('ApplyVehicleDiagnostics', function(veh, data)
    if not veh or not DoesEntityExist(veh) or not data then return end
    
    -- wear, mileage and NOS come from the server's saved copy, not from the caller's data
    requestRestore(veh)
    
    -- Apply standard vehicle properties
    if QBCore.Functions.SetVehicleProperties then
        QBCore.Functions.SetVehicleProperties(veh, data)
    end
end)

-- Debug export (only works when Config.Debug = true)
if Config.Debug then
    exports('DebugPrintDiag', function(veh)
        if not veh or not DoesEntityExist(veh) then return end
        local st = Entity(veh).state
        print('[DIAG DEBUG] plate='..(GetVehicleNumberPlateText(veh) or 'N/A')..' state='..json.encode(st.partDamage or {}))
    end)
end

-- NEW: Handler for server requesting live vehicle state (when cache is empty)
RegisterNetEvent('pf_mech:client:requestLiveState', function(plate)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    -- Find vehicle with this plate
    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            local vehPlate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
            if vehPlate == plate then
                -- Found it! Send current state to server
                local state = Entity(veh).state
                local props = QBCore.Functions.GetVehicleProperties(veh)
                props.partDamage = state.partDamage or {}
                props.mileage = tonumber(state.mileage) or 0
                
                TriggerServerEvent('pf_mech:sync:cacheVehicleState', {
                    plate = plate,
                    netId = NetworkGetNetworkIdFromEntity(veh),
                    props = props
                })
                
                -- Now force save
                Wait(100)
                TriggerServerEvent('pf_mech:sync:forceSave', plate)
                
                if Config.Debug then
                    print(string.format('[GARAGE SYNC] Sent live state for %s', plate))
                end
                
                return
            end
        end
    end
    
    if Config.Debug then
        print(string.format('[GARAGE SYNC] Could not find vehicle %s', plate))
    end
end)
