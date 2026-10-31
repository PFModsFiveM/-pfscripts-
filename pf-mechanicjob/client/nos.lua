local QBCore = exports['pfm-core']:GetCoreObject()
local cfg = Config.NOS or {}

-- Track active sounds to force cleanup
local activeSounds = {}
local emptyBottleGiven = {}

-- NEW: Local damage accumulator (prevents state bag flooding)
local damageAccumulator = {}
local lastDamageSync = 0
local DAMAGE_SYNC_INTERVAL = 2000  -- Sync to server every 2 seconds

-- The car's 'nos' state is set by the server only (sv_stateBagStrictMode). While this player
-- drives, the bottle level falls here every frame and is reported every 2 s; the boost level picked
-- shows at once and is sent to the server. A higher level from the server is a new bottle or a
-- refill; a lower one is our own report arriving back.
local nosView = { veh = 0 }
local function syncNosView(veh, nos)
    local srv = math.max(0, tonumber(nos.level) or 0)
    local srvSel = tonumber(nos.levelSel) or 1
    if nosView.veh ~= veh then
        nosView = { veh = veh, level = srv, server = srv, sel = srvSel, serverSel = srvSel }
        return nosView
    end
    if srv ~= nosView.server then
        nosView.level = (srv > nosView.server) and srv or math.min(nosView.level, srv)
        nosView.server = srv
    end
    if srvSel ~= nosView.serverSel then
        nosView.sel, nosView.serverSel = srvSel, srvSel
    end
    return nosView
end

-- Particle helpers
local function LoadPtfxAsset(dict)
    if not HasNamedPtfxAssetLoaded(dict) then
        RequestNamedPtfxAsset(dict)
        while not HasNamedPtfxAssetLoaded(dict) do Wait(0) end
    end
end

-- Screen effect toggle
local function ScreenEffectToggle(enabled)
    if enabled then
        StopScreenEffect("RaceTurbo")
        StartScreenEffect("RaceTurbo", 0, false)
        SetTimecycleModifier("rply_motionblur")
        ShakeGameplayCam("SKY_DIVING_SHAKE", 0.15)
    else
        StopGameplayCamShaking(true)
        SetTransitionTimecycleModifier("default", 0.35)
    end
end

-- Exhaust flame backfire
local function VehicleBackfire(vehicle)
    local exhaustNames = { "exhaust", "exhaust_2", "exhaust_3", "exhaust_4" }
    LoadPtfxAsset('core')
    
    for _, exhaustName in ipairs(exhaustNames) do
        local boneIndex = GetEntityBoneIndexByName(vehicle, exhaustName)
        if boneIndex ~= -1 then
            UseParticleFxAssetNextCall("core")
            local bonePos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, bonePos)
            StartParticleFxNonLoopedOnEntity(
                "veh_backfire",
                vehicle,
                offset.x, offset.y, offset.z,
                0.0, 0.0, 0.0,
                1.5,
                false, false, false
            )
        end
    end
end

-- INSTALL event
RegisterNetEvent('pf_mech:nos:install', function()
    if not cfg.enabled then return end
    local ped = PlayerPedId()
    local veh
    
    if IsPedInAnyVehicle(ped,false) then
        veh = GetVehiclePedIsIn(ped,false)
        if GetPedInVehicleSeat(veh,-1) ~= ped then 
            QBCore.Functions.Notify('Driver seat required','error'); return 
        end
    else
        local pos = GetEntityCoords(ped)
        veh = GetClosestVehicle(pos.x,pos.y,pos.z,6.0,0,70)
        if veh == 0 or not DoesEntityExist(veh) then 
            QBCore.Functions.Notify('No vehicle nearby','error'); return 
        end
    end
    
    if GetIsVehicleEngineRunning(veh) then 
        QBCore.Functions.Notify('Turn engine off first','error'); return 
    end
    
    local hasTurbo = IsToggleModOn(veh, 18) and true or false
    if Config and type(Config.HasTurbo) == 'function' then
        hasTurbo = Config.HasTurbo(veh) and true or false
    end
    if not hasTurbo then
        QBCore.Functions.Notify('Turbo required before installing NOS','error')
        return
    end
    
    -- FIXED: Check state properly
    local st = Entity(veh).state.nos
    if st and st.has and (tonumber(st.level) or 0) > 0 then 
        QBCore.Functions.Notify('NOS already installed','error'); return 
    end

    local start = GetGameTimer()
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() - start < 1500 do
        NetworkRequestControlOfEntity(veh); Wait(0)
    end

    RequestAnimDict('mini@repair')
    while not HasAnimDictLoaded('mini@repair') do Wait(0) end
    TaskPlayAnim(ped,'mini@repair','fixing_a_ped',8.0,-8.0,-1,49,0,false,false,false)

    local ok = true
    if QBCore.Functions.Progressbar then
        local done = false
        QBCore.Functions.Progressbar('install_nos','Installing NOS...',4500,false,true,
            { disableMovement=true, disableCarMovement=true, disableCombat=true },
            { animDict='mini@repair', anim='fixing_a_ped', flags=49 },{},{},
            function() done=true end, function() done=false end)
        while not done do Wait(50) end
        ok = done
    else
        Wait(4500)
    end
    
    ClearPedTasks(ped)
    if not ok then 
        QBCore.Functions.Notify('Installation cancelled','error'); return 
    end

    -- the server checks the car and the bottle, takes the bottle, sets the car's NOS and notifies
    TriggerServerEvent('pf_mech:nos:consumeBottle', NetworkGetNetworkIdFromEntity(veh))
end)

-- BOOST CONTROLLER (FIXED: batch damage updates)
CreateThread(function()
    local keyBoost     = (cfg.keys and cfg.keys.boost) or 21
    local keyPurge     = (cfg.keys and cfg.keys.purge) or 36
    local keyLevelUp   = (cfg.keys and cfg.keys.levelUp) or 172
    local keyLevelDown = (cfg.keys and cfg.keys.levelDown) or 173
    local boosting = false
    local lastSync = 0
    local trailFx = {}
    local cooldownUntil = 0
    local lastVehicle = 0
    local lastForceApply = 0

    while true do
        Wait(0)
        if not cfg.enabled then 
            if boosting then
                boosting = false
                ScreenEffectToggle(false)
                CleanupSounds()
                for _, fx in ipairs(trailFx) do
                    if fx and DoesParticleFxLoopedExist(fx) then
                        StopParticleFxLooped(fx, false)
                    end
                end
                trailFx = {}
                TriggerEvent('hud:client:UpdateNitrous', false, 0, 0)
            end
            goto cont 
        end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped,false) then
            if boosting or #trailFx > 0 then
                boosting = false
                ScreenEffectToggle(false)
                CleanupSounds()
                for _, fx in ipairs(trailFx) do
                    if fx and DoesParticleFxLoopedExist(fx) then
                        StopParticleFxLooped(fx, false)
                    end
                end
                trailFx = {}
                TriggerEvent('hud:client:UpdateNitrous', false, 0, 0)
            end
            lastVehicle = 0
            goto cont
        end
        
        local veh = GetVehiclePedIsIn(ped,false)
        if veh == 0 or GetPedInVehicleSeat(veh,-1) ~= ped then
            if boosting or #trailFx > 0 then
                boosting = false
                ScreenEffectToggle(false)
                CleanupSounds()
                for _, fx in ipairs(trailFx) do
                    if fx and DoesParticleFxLoopedExist(fx) then
                        StopParticleFxLooped(fx, false)
                    end
                end
                trailFx = {}
                TriggerEvent('hud:client:UpdateNitrous', false, 0, 0)
            end
            lastVehicle = 0
            goto cont
        end
        
        -- Vehicle change detection
        if veh ~= lastVehicle then
            if boosting or #trailFx > 0 then
                boosting = false
                ScreenEffectToggle(false)
                CleanupSounds()
                for _, fx in ipairs(trailFx) do
                    if fx and DoesParticleFxLoopedExist(fx) then
                        StopParticleFxLooped(fx, false)
                    end
                end
                trailFx = {}
            end
            lastVehicle = veh
            -- CHANGED: Clear empty bottle flag when changing vehicles
            emptyBottleGiven[veh] = nil
        end
        
        local nos = Entity(veh).state.nos
        
        if not (nos and nos.has) then
            if boosting or #trailFx > 0 then
                boosting = false
                ScreenEffectToggle(false)
                CleanupSounds()
                for _, fx in ipairs(trailFx) do
                    if fx and DoesParticleFxLoopedExist(fx) then
                        StopParticleFxLooped(fx, false)
                    end
                end
                trailFx = {}
            end
            TriggerEvent('hud:client:UpdateNitrous', false, 0, 0)
            emptyGiven = false  -- NEW: reset flag when NOS not installed
            goto cont
        end
        
        local view = syncNosView(veh, nos)
        local netId = NetworkGetNetworkIdFromEntity(veh)

        -- Level selection
        if IsControlJustPressed(0,keyLevelUp) then
            view.sel = math.min(3,(view.sel or 1)+1)
            TriggerServerEvent('pf_mech:nos:setLevelSel', netId, view.sel)
            QBCore.Functions.Notify('NOS Level '..view.sel,'primary',1200)
        elseif IsControlJustPressed(0,keyLevelDown) then
            view.sel = math.max(1,(view.sel or 1)-1)
            TriggerServerEvent('pf_mech:nos:setLevelSel', netId, view.sel)
            QBCore.Functions.Notify('NOS Level '..view.sel,'primary',1200)
        end

        local levelCfg = cfg.levels[view.sel or 1] or cfg.levels[1]
        local speed = GetEntitySpeed(veh)*2.236936

        -- Update HUD
        local maxLevel = cfg.capacity or 100
        local currentLevel = math.max(0, tonumber(view.level) or 0)
        TriggerEvent('hud:client:UpdateNitrous', true, currentLevel, maxLevel)

        -- NEW: Check cooldown status
        local now = GetGameTimer()
        local onCooldown = now < cooldownUntil

        -- CHANGED: Apply force every 50ms instead of every frame (reduces from 60x/sec to 20x/sec)
        if IsControlPressed(0,keyBoost) and currentLevel > 0 and speed >= 50.0 and not onCooldown then
            if not boosting then
                boosting = true
                SetVehicleBoostActive(veh,true)
                ScreenEffectToggle(true)
                QBCore.Functions.Notify('NOS Active (Level '..view.sel..')','success',800)
                
                LoadPtfxAsset('veh_xs_vehicle_mods')
                local wheels = { 'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr' }
                for _, wheelName in ipairs(wheels) do
                    local bone = GetEntityBoneIndexByName(veh, wheelName)
                    if bone ~= -1 then
                        UseParticleFxAssetNextCall('veh_xs_vehicle_mods')
                        local fx = StartParticleFxLoopedOnEntityBone(
                            'veh_xs_turbo_blue',
                            veh,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            bone,
                            0.6,
                            false, false, false
                        )
                        trailFx[#trailFx+1] = fx
                    end
                end
                
                -- Initialize accumulator for this vehicle
                local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
                damageAccumulator[plate] = damageAccumulator[plate] or {}
            end

            -- CHANGED: Only apply force every 50ms (not every frame)
            if (now - lastForceApply) >= 50 then
                lastForceApply = now
                
                local fwd = GetEntityForwardVector(veh)
                local power = levelCfg.powerMult or 0.015
                
                -- Apply small forward force
                ApplyForceToEntity(veh, 1, fwd.x * power, fwd.y * power, 0.0, 0.0,0.0,0.0, 0, false, true, true, false, true)
            end

            -- Drain NOS (this driver's view; reported to the server below)
            local drain = (levelCfg.drainPerSec or 12) / 60.0
            view.level = math.max(0, view.level - drain)

            -- CHANGED: Accumulate damage locally (no state updates)
            local damageConfig = levelCfg.damagePerSec or {}
            local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
            local acc = damageAccumulator[plate] or {}
            
            -- Calculate per-frame damage (divide by 60 for 60 FPS)
            local engineDmg = (damageConfig.engine_part or 0.20) / 60.0
            local sparkDmg = (damageConfig.sparkplugs or 0.30) / 60.0
            local fuelDmg = (damageConfig.fuel_injector or 0.15) / 60.0
            local oilDmg = (damageConfig.engine_oil or 0.05) / 60.0
            local axleDmg = (damageConfig.axle or 0.05) / 60.0
            
            -- Check if in low gear (1st or 2nd) for axle damage
            local gear = GetVehicleCurrentGear(veh)
            local inLowGear = (gear == 1 or gear == 2)
            
            -- Check engine temp for heat penalty
            local engineTemp = GetVehicleEngineTemperature(veh) or 90.0
            local overheating = engineTemp > 110.0
            local heatPenalty = overheating and ((damageConfig.heatPenalty or 0.1) / 60.0) or 0.0
            
            -- Accumulate damage (don't write to state yet)
            acc.engine_part = (acc.engine_part or 0) + engineDmg + heatPenalty
            acc.sparkplugs = (acc.sparkplugs or 0) + sparkDmg
            acc.fuel_injector = (acc.fuel_injector or 0) + fuelDmg
            acc.oil = (acc.oil or 0) + oilDmg
            
            if inLowGear then
                acc.axle = (acc.axle or 0) + axleDmg
            end
            
            damageAccumulator[plate] = acc
            
            -- Sync accumulated damage to server every 2 seconds
            if (now - lastDamageSync) >= DAMAGE_SYNC_INTERVAL then
                lastDamageSync = now
                TriggerServerEvent('pf_mech:nos:applyDamage', plate, acc)
                -- Reset accumulator after sync
                damageAccumulator[plate] = {}
            end
            
            -- Also apply GTA engine health damage (visual)
            local gta_eng_dmg = ((damageConfig.engine_part or 0.20) / 60.0) * 10.0
            local eng = GetVehicleEngineHealth(veh)
            SetVehicleEngineHealth(veh, eng - gta_eng_dmg)

            -- Backfire
            if math.random(100) < 15 then
                VehicleBackfire(veh)
            end

            -- Sync NOS level to server
            if now - lastSync > 2000 then
                lastSync = now
                TriggerServerEvent('pf_mech:nos:updateLevel', netId, view.level)
            end

            -- Check empty
            if view.level <= 0 and not emptyBottleGiven[veh] then
                emptyBottleGiven[veh] = true
                
                boosting = false
                SetVehicleBoostActive(veh,false)
                SetVehicleCheatPowerIncrease(veh,1.0)
                ScreenEffectToggle(false)
                CleanupSounds()
                
                for _, fx in ipairs(trailFx) do
                    if fx and DoesParticleFxLoopedExist(fx) then
                        StopParticleFxLooped(fx, false)
                    end
                end
                trailFx = {}
                
                if Config.Debug then
                    print('[NOS CLIENT] NOS depleted, requesting empty bottle (once)')
                end
                
                -- the server clears the car's NOS (it sits in it) and hands back the empty bottle
                TriggerServerEvent('pf_mech:nos:giveEmpty', netId)
                
                QBCore.Functions.Notify('NOS empty - check inventory for empty bottle','error',4000)
                TriggerEvent('hud:client:UpdateNitrous', false, 0, 0)
            end
        else
            if IsControlJustPressed(0,keyBoost) and currentLevel > 0 and speed < 50.0 and not onCooldown then
                QBCore.Functions.Notify('NOS requires 50+ MPH','error',2000)
            end
            
            if boosting then
                boosting = false
                SetVehicleBoostActive(veh,false)
                ScreenEffectToggle(false)
                TriggerServerEvent('pf_mech:nos:updateLevel', netId, view.level)
                
                local cooldownMs = cfg.cooldownMs or 10000
                cooldownUntil = GetGameTimer() + cooldownMs
                
                for _, fx in ipairs(trailFx) do
                    if fx and DoesParticleFxLoopedExist(fx) then
                        StopParticleFxLooped(fx, false)
                    end
                end
                trailFx = {}
                
                CreateThread(function()
                    Wait(cooldownMs)
                    if DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) == ped then
                        RequestAmbientAudioBank("dlc_xm_heists_fm_uc_sounds", 0)
                        local soundId = GetSoundId()
                        PlaySoundFromEntity(soundId, "download_complete", veh, "dlc_xm_heists_fm_uc_sounds", 1, 0)
                        Wait(200)
                        StopSound(soundId)
                        ReleaseSoundId(soundId)
                    end
                end)
                
                QBCore.Functions.Notify('NOS released - cooldown active','primary',1200)
            elseif onCooldown and IsControlJustPressed(0,keyBoost) then
                local remaining = math.ceil((cooldownUntil - now) / 1000)
                QBCore.Functions.Notify(('NOS cooldown: %ds'):format(remaining),'error',800)
            end
        end

        ::cont::
    end
end)

-- NEW: Sound tracking and cleanup helpers
function PlayCooldownCompleteSound()
    local soundId = GetSoundId()
    activeSounds[soundId] = true
    
    RequestAmbientAudioBank("dlc_xm_heists_fm_uc_sounds", 0)
    PlaySoundFrontend(soundId, "download_complete", "dlc_xm_heists_fm_uc_sounds", true)
    
    CreateThread(function()
        Wait(1000)
        if activeSounds[soundId] then
            StopSound(soundId)
            ReleaseSoundId(soundId)
            activeSounds[soundId] = nil
        end
    end)
end

function CleanupSounds()
    for soundId, _ in pairs(activeSounds) do
        pcall(function()
            StopSound(soundId)
            ReleaseSoundId(soundId)
        end)
    end
    activeSounds = {}
end

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ScreenEffectToggle(false)
    CleanupSounds()
end)

-- Debug
if Config.Debug then
    RegisterCommand('nosdebug', function()
        local ped=PlayerPedId()
        if not IsPedInAnyVehicle(ped,false) then print('[NOS] No vehicle') return end
        local veh=GetVehiclePedIsIn(ped,false)
        local nos=Entity(veh).state.nos
        if nos then
            print('[NOS DEBUG] has='..tostring(nos.has)..' level='..tostring(nos.level)..' capacity='..tostring(cfg.capacity or 100))
        else
            print('[NOS DEBUG] No NOS installed')
        end
    end,false)
end
