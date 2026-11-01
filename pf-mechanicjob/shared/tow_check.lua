-- The one rule for "this car cannot be driven and needs a tow" (Config.AdvancedSystems.Integrations.Tow):
-- engine or body health below the thresholds, a ruptured fuel tank, or a wear part worn out.
-- The server decides a shop's tow order with it from its own readings (server/advanced_systems.lua);
-- the client offers that order after a diagnostic scan on the same rule (client/advanced_systems.lua),
-- so a car the server would accept is never left without the offer (it used to be offered only for
-- an engine at 30% or less). The client's reading only decides whether to ask: the server reads the
-- car itself before ordering anything.

PFMechTow = PFMechTow or {}

-- The wear parts of the partDamage state bag (as server/advanced_systems.lua WEAR_PARTS).
PFMechTow.WearParts = {
    alternator = true, sparkplugs = true, carbattery = true, oil = true, oil_filter = true,
    brakes = true, suspension = true, axle = true, fuel_injector = true, powersteeringpump = true,
    radiator = true, power_steering_fluid = true, transmissionfluid = true, brakefluid = true,
    coolant = true, engine_part = true, body_part = true,
}

-- The label sent with an order for each reason (it is shown in the Dispatch app).
PFMechTow.ReasonLabels = {
    engine = 'critical_engine_failure',
    body = 'severe_body_damage',
    tank = 'ruptured_fuel_tank',
    part = 'failed_part',
}

local function towCfg()
    local adv = Config and Config.AdvancedSystems or {}
    return ((adv.Integrations or {}).Tow) or {}
end

--- Why the car needs a tow ('engine', 'body', 'tank' or 'part'), or nil while it can be driven.
--- engine, body, tank: the game's health values (0-1000; tank may be nil when unknown);
--- wear: the car's partDamage state bag (or nil); parts: which wear keys count (default WearParts).
function PFMechTow.Reason(engine, body, tank, wear, parts)
    local cfg = towCfg()
    engine, body, tank = tonumber(engine), tonumber(body), tonumber(tank)
    if engine and engine < (tonumber(cfg.EngineHealthBelow) or 400.0) then return 'engine' end
    if body and body < (tonumber(cfg.BodyHealthBelow) or 300.0) then return 'body' end
    if tank and tank <= 0 then return 'tank' end
    -- a part worn out completely leaves the car unusable (a dead battery, seized engine, no brakes)
    if type(wear) == 'table' then
        local failedAt = tonumber(cfg.FailedPartWear) or 100
        for part in pairs(parts or PFMechTow.WearParts) do
            if (tonumber(wear[part]) or 0) >= failedAt then return 'part' end
        end
    end
    return nil
end
