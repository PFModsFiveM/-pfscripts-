-- Functional effect profile of a patient, computed on the server from the true injuries, the
-- derived vitals and active drugs/toxins (shared/medical/effects_model.lua). Batch 17 pushes it to
-- the client applier on change (PFMed.Effects.Push); here it feeds the summary's restrictions.

PFMed = PFMed or {}
PFMed.Effects = PFMed.Effects or {}
local F = PFMed.Effects
local P, EM = PFMed.Physiology, PFMed.EffectsModel

local lastSignature = {}   -- [cid] = signature of the last profile handed out

--- Modifiers from the patient's state: analgesia from active drugs, toxin intensities.
function F.Mods(p, at)
    local c = P.Cfg(Config.Medical)
    local mods = { toxins = {} }
    for name, def in pairs(c.Drugs) do
        if def.analgesia and P.DrugActive(p, name, at, c) then mods.analgesia = true end
    end
    for name in pairs(p.toxins or {}) do mods.toxins[name] = P.ToxinIntensity(p, name, at, c) end
    if type(p.restrictions) == 'table' and p.restrictions.crutches then mods.crutches = true end
    return mods
end

--- Profile of a cached patient object.
function F.ProfileOf(p, at)
    at = at or os.time()
    local v = PFMed.Engine.Vitals(p, at)
    return EM.Combine(p.injuries, v, F.Mods(p, at))
end

--- Profile by citizen id (nil when the patient is not in memory).
function F.Profile(cid, at)
    local p = PFMed.Store.Peek(cid)
    if not p then return nil end
    return F.ProfileOf(p, at)
end

--- Restrictions that follow from the profile: list of { kind, reason }.
function F.Restrictions(p, at)
    local profile = F.ProfileOf(p, at)
    return EM.Restrictions(profile, p.injuries), profile
end

--- The profile and whether it differs from the last one handed out for this patient.
function F.Changed(cid, at)
    local profile = F.Profile(cid, at)
    if not profile then return nil, false end
    local sig = EM.Signature(profile)
    local changed = lastSignature[cid] ~= sig
    lastSignature[cid] = sig
    return profile, changed
end

function F.Forget(cid) lastSignature[cid] = nil end
