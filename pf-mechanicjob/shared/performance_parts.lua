-- Performance parts: which slot of the car each part item fills and the mod it sets.
-- Shared so the server decides the mod from the item alone (a client used to send its own modType
-- and modIndex, so one cheap part could fit any upgrade). The client only clamps the index to the
-- variants the car model has (GetNumVehicleMods).
--   slot     one fitted part per slot and car (pf_mech_fitted_parts, server/main.lua)
--   modType  GTA mod type; -101 / -102 are this resource's drift and bulletproof tyre toggles
--   modIndex the level index (car_armor: the highest the car offers, clamped by the client)
--   toggle   a toggle mod (turbo, xenon, tyres) instead of a level
--   propKey  the key in the saved vehicle props (player_vehicles.mods), and its stock value
PFMechParts = PFMechParts or {}

local defs = {}
local function level(prefix, slot, modType, propKey, count)
    for lvl = 1, count do
        defs[prefix .. lvl] = { slot = slot, modType = modType, modIndex = lvl - 1, toggle = false, propKey = propKey, stock = -1 }
    end
end
level('engine', 'engine', 11, 'modEngine', 5)
level('brakes', 'brakes', 12, 'modBrakes', 3)
level('transmission', 'transmission', 13, 'modTransmission', 4)
level('suspension', 'suspension', 15, 'modSuspension', 5)
level('armor', 'armor', 16, 'modArmor', 5)
defs.car_armor   = { slot = 'armor', modType = 16, modIndex = 4, toggle = false, propKey = 'modArmor', stock = -1 }
defs.turbo       = { slot = 'turbo', modType = 18, modIndex = 0, toggle = true, propKey = 'modTurbo', stock = false }
defs.headlights  = { slot = 'xenon', modType = 22, modIndex = 0, toggle = true, propKey = 'modXenon', stock = false }
defs.drifttires  = { slot = 'drifttires', modType = -101, modIndex = 0, toggle = true }
defs.bprooftires = { slot = 'bprooftires', modType = -102, modIndex = 0, toggle = true }

PFMechParts.Items = defs

-- slot -> { modType, toggle, propKey, stock }: what removing the part from that slot sets back
PFMechParts.Slots = {}
for _, d in pairs(defs) do
    PFMechParts.Slots[d.slot] = PFMechParts.Slots[d.slot]
        or { slot = d.slot, modType = d.modType, toggle = d.toggle, propKey = d.propKey, stock = d.stock }
end

--- The part definition for an item name, or nil.
function PFMechParts.ForItem(item)
    return type(item) == 'string' and defs[item] or nil
end

--- The slot named directly ('engine', 'turbo'...) or the slot an item name fills.
function PFMechParts.SlotOf(name)
    if type(name) ~= 'string' then return nil end
    if PFMechParts.Slots[name] then return name end
    local d = defs[name]
    return d and d.slot or nil
end
