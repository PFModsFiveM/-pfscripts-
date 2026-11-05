-- Motion hints for the server's damage ingestion (server/medical/ingest.lua). The server samples
-- velocity only for players in a vehicle or falling; this file tells it when that starts and ends
-- (MotionHint) and keeps what only the client sees for the next DamageHint: a fall's peak speed,
-- the vehicle's recent speeds and the seatbelt. The server clamps all of it to its own samples.
-- Vehicles are event driven (QBCore:Client:EnteredVehicle / LeftVehicle); on foot a slow check
-- (every 400 ms, 100 ms only during a fall) notices falls. There is no per-frame loop.

PFMedHints = PFMedHints or {}
local H = PFMedHints

local state = 'ground'
local fallPeak, fallAt = 0, 0        -- highest downward speed of the last fall (m/s), when it ended
local speeds = {}                    -- { { at, speed } } while in a vehicle (newest last)

local function tell(newState)
    if newState == state then return end
    state = newState
    TriggerServerEvent('pf-ambulancejob:server:MotionHint', newState)
end

local function inVehicleWatch()
    CreateThread(function()
        while state == 'vehicle' do
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 then tell('ground') break end
            speeds[#speeds + 1] = { at = GetGameTimer(), speed = GetEntitySpeed(veh) }
            while #speeds > 8 do table.remove(speeds, 1) end
            Wait(250)
        end
    end)
end

AddEventHandler('QBCore:Client:EnteredVehicle', function()
    speeds = {}
    tell('vehicle')
    inVehicleWatch()
end)

AddEventHandler('QBCore:Client:LeftVehicle', function()
    if state == 'vehicle' then tell('ground') end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if state ~= 'vehicle' then
            local vz = GetEntityVelocity(ped).z
            if (IsPedFalling(ped) or vz < -4.0) and not IsPedInParachuteFreeFall(ped) then
                if state ~= 'airborne' then fallPeak = 0 end
                tell('airborne')
                if -vz > fallPeak then fallPeak = -vz end
                Wait(100)
            else
                if state == 'airborne' then fallAt = GetGameTimer(); tell('ground') end
                Wait(400)
            end
        else
            Wait(1000)
        end
    end
end)

--- What the client knows about its motion right now, for a DamageHint (nil fields when unknown).
function H.Snapshot()
    local out = {}
    local now = GetGameTimer()
    if state == 'airborne' or now - fallAt < 1500 then
        if fallPeak > 0 then out.fall = { vz = -fallPeak } end
    end
    if state == 'vehicle' and #speeds > 0 then
        local before = 0
        for _, s in ipairs(speeds) do if now - s.at <= 1500 and s.speed > before then before = s.speed end end
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        local belt
        if GetResourceState('pfm-smallresources') == 'started' then
            local ok, on = pcall(function() return exports['pfm-smallresources']:HasSeatbeltOn() or exports['pfm-smallresources']:HasHarness() end)
            if ok then belt = on == true end
        end
        out.vehicle = { speedBefore = before, speedAfter = veh ~= 0 and GetEntitySpeed(veh) or 0, seatbelt = belt }
    end
    local ped = PlayerPedId()
    if IsEntityInWater(ped) then out.water = true end
    if IsEntityOnFire(ped) then out.fire = true end
    return out
end
