-- ============================================================================
-- PF MECHANIC JOB - ENGINEERING EFFECTS (Client Visual/Audio)
-- ============================================================================

local EngineConfig = require('config.engineering')

local Effects = {}

-- ============================================================================
-- Sound Effects
-- ============================================================================

---Play turbo spool sound
---@param vehicle number Vehicle entity
---@param boost number Current boost 0-25
function Effects:PlayTurboSpool(vehicle, boost)
    if not DoesEntityExist(vehicle) then return end
    
    local spoolLevel = math.min(1.0, boost / 15)
    
    -- Could use native audio functions here
    -- PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
end

---Play boost relief sound
---@param vehicle number Vehicle entity
function Effects:PlayBoostRelief(vehicle)
    if not DoesEntityExist(vehicle) then return end
    -- Play PSHHH sound
end

---Play misfire/backfire
---@param vehicle number Vehicle entity
function Effects:PlayBackfire(vehicle)
    if not DoesEntityExist(vehicle) then return end
    
    local x, y, z = table.unpack(GetEntityCoords(vehicle))
    local heading = GetEntityHeading(vehicle)
    
    -- Spawn backfire particle at exhaust
    SmashVehicleWindow(vehicle, 1)  -- Placeholder
end

---Play engine knock/ping
---@param vehicle number Vehicle entity
function Effects:PlayEngineKnock(vehicle)
    if not DoesEntityExist(vehicle) then return end
    -- Metal ping sound
end

-- ============================================================================
-- Particle Effects
-- ============================================================================

---Create turbo heat distortion effect
---@param vehicle number Vehicle entity
function Effects:CreateTurboHeatEffect(vehicle, intensity)
    if not DoesEntityExist(vehicle) then return end
    
    intensity = math.min(1.0, intensity / 100)
    
    if intensity < 0.3 then return end
    
    -- Could use particle effects library here
    -- LoadModel(GetHashKey("prop_distort_turbine"))
end

---Create engine smoke effect (overheating)
---@param vehicle number Vehicle entity
---@param intensity number 0-100
function Effects:CreateEngineSmoke(vehicle, intensity)
    if not DoesEntityExist(vehicle) then return end
    
    intensity = math.min(1.0, intensity / 100)
    
    if intensity < 0.7 then return end
    
    -- Use native particle effects
    local x, y, z = table.unpack(GetEntityCoords(vehicle))
    
    USE_PARTICLE_FX_ASSET_NEXT_CALL("core")
    StartParticleFxLoopedAtCoord(
        GetHashKey("engine_overheat"),
        x, y, z,
        0, 0, 0,
        intensity,
        false,
        false,
        false
    )
end

-- ============================================================================
-- HUD Displays
-- ============================================================================

---Display tuning stats on screen
---@param tuning table Tuning data
---@param runtime table Runtime state
function Effects:DisplayTuningHUD(tuning, runtime)
    if not tuning or not runtime then return end
    
    -- Draw on screen (would need screen coords)
    local text = string.format(
        "HP: ~g~%d ~s~| TQ: ~g~%d Nm ~s~| Boost: ~g~%.1f PSI~n~" ..
        "Engine: ~r~%d%% ~s~| Turbo: ~r~%d%% ~s~| Oil: ~y~%d%% ~s~| Coolant: ~b~%d%%",
        tuning.estimated_hp or 150,
        tuning.estimated_torque or 200,
        runtime.boostCurrent or 0,
        runtime.engineWear or 0,
        runtime.turboWear or 0,
        tuning.oil_quality or 100,
        tuning.coolant_quality or 100
    )
    
    DrawTextOnScreen(0.5, 0.9, 0.4, text)
end

---Display warning notifications
---@param type string Warning type: heat, wear, misfire
---@param severity number 0-1 severity
function Effects:DisplayWarning(type, severity)
    local color = {255, 255, 0}  -- Yellow
    local message = "Engine warning"
    
    if type == "heat" then
        message = "Engine overheating!"
        color = {255, 100, 0}  -- Orange
    elseif type == "wear" then
        message = "Critical wear detected"
        color = {255, 50, 0}  -- Red
    elseif type == "misfire" then
        message = "Engine misfiring"
        color = {255, 150, 0}
    end
    
    TriggerEvent('chat:addMessage', {
        color = color,
        multiline = true,
        args = {"Engine", message}
    })
end

-- ============================================================================
-- Screen Drawing Helper
-- ============================================================================

local function DrawTextOnScreen(x, y, size, text)
    SetTextFont(0)
    SetTextProportional(0)
    SetTextScale(0.0, size)
    SetTextColour(255, 255, 255, 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentString(text)
    EndTextCommandDisplayText(x, y)
end

return Effects
