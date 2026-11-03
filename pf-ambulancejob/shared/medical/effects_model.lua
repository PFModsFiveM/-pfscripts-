-- Functional effects model (architecture 11.4): pure functions that turn open injuries, vitals and
-- active modifiers into one effect profile. Each channel is 0..3 and is the MAXIMUM over its sources,
-- never the sum: three leg injuries make a heavy limp, not three limps added up.

PFMed = PFMed or {}
PFMed.EffectsModel = PFMed.EffectsModel or {}
local E = PFMed.EffectsModel

E.Channels = { 'walk', 'sprint', 'jump', 'climb', 'aim', 'reload', 'drive', 'stamina', 'vision', 'pain' }
-- Channels that come from the body's structure: painkillers never lower them.
E.Structural = { walk = true, sprint = true, jump = true, climb = true, drive = true, reload = true }

local function clamp3(v)
    v = math.floor(tonumber(v) or 0)
    if v < 0 then return 0 elseif v > 3 then return 3 end
    return v
end

function E.Empty()
    local p = {}
    for _, ch in ipairs(E.Channels) do p[ch] = 0 end
    return p
end

local function raise(p, ch, v)
    v = clamp3(v)
    if p[ch] ~= nil and v > p[ch] then p[ch] = v end
end

--- One injury's channels after its own treatment: a splint or cast holds a broken leg (walk 3 -> 2).
function E.InjuryChannels(inj)
    local I = PFMed.Injuries
    local ch = I.Effects(inj)
    local tr = type(inj.treatments) == 'table' and inj.treatments or {}
    if tr.splinted or tr.cast then
        for _, k in ipairs({ 'walk', 'jump', 'climb', 'aim', 'reload' }) do
            if (ch[k] or 0) > 2 then ch[k] = 2 end
        end
    end
    if inj.stage == 'recovering' then
        for k, v in pairs(ch) do ch[k] = math.max(0, v - 1) end
    end
    return ch
end

--- Combines everything into one profile.
--- injuries: open injuries; vitals: from PFMed.Physiology.Vitals (or nil);
--- mods = { analgesia = bool, crutches = bool, toxins = { name = intensity } }.
function E.Combine(injuries, vitals, mods)
    mods = mods or {}
    local p = E.Empty()
    for _, inj in pairs(injuries or {}) do
        if inj.stage ~= 'recovered' and inj.stage ~= nil then
            for ch, v in pairs(E.InjuryChannels(inj)) do raise(p, ch, v) end
        end
    end
    if vitals then
        if vitals.shock and vitals.shock >= 3 then raise(p, 'stamina', 3) elseif vitals.shock == 2 then raise(p, 'stamina', 1) end
        if vitals.spo2 and vitals.spo2 > 0 then
            if vitals.spo2 < 85 then raise(p, 'vision', 2); raise(p, 'stamina', 2) elseif vitals.spo2 < 92 then raise(p, 'vision', 1) end
        end
        if vitals.gcs and vitals.gcs <= 13 then raise(p, 'vision', 2); raise(p, 'drive', 2) end
        local pain = tonumber(vitals.pain) or 0
        if pain >= 8 then raise(p, 'pain', 3) elseif pain >= 6 then raise(p, 'pain', 2) elseif pain >= 3 then raise(p, 'pain', 1) end
        if pain >= 7 then raise(p, 'aim', 1) end
    end
    local tox = mods.toxins or {}
    local ethanol = tonumber(tox.ethanol) or 0
    if ethanol >= 0.5 then raise(p, 'drive', 2); raise(p, 'vision', 2); raise(p, 'aim', 2)
    elseif ethanol >= 0.27 then raise(p, 'drive', 1); raise(p, 'vision', 1); raise(p, 'aim', 1) end
    for _, name in ipairs({ 'opioid', 'sedative', 'cannabis', 'carbon_monoxide', 'poison' }) do
        local x = tonumber(tox[name]) or 0
        if x >= 1 then raise(p, 'drive', 2); raise(p, 'vision', 2) elseif x >= 0.5 then raise(p, 'drive', 1); raise(p, 'vision', 1) end
    end
    if mods.crutches then
        p.walk = math.min(p.walk, 2)
        if p.walk < 2 then p.walk = 2 end
        p.sprint = 3
    end
    if mods.analgesia then
        p.pain = math.max(0, p.pain - 1)
        p.aim = math.max(0, p.aim - 1)
    end
    return p
end

--- True when every channel is 0 (the client applier then runs no loop at all).
function E.IsEmpty(p)
    for _, ch in ipairs(E.Channels) do if (p[ch] or 0) ~= 0 then return false end end
    return true
end

--- A short stable string of the profile, to send it only when it changed.
function E.Signature(p)
    local parts = {}
    for i, ch in ipairs(E.Channels) do parts[i] = tostring(p[ch] or 0) end
    return table.concat(parts)
end

--- Restrictions that follow from the profile (what police, prison and work can rely on).
--- Returns a list of { kind, reason }.
function E.Restrictions(p, injuries)
    local out = {}
    local function add(kind, reason) out[#out + 1] = { kind = kind, reason = reason } end
    if (p.walk or 0) >= 3 then add('bed_rest', 'cannot walk') end
    if (p.sprint or 0) >= 2 or (p.walk or 0) >= 2 then add('no_sprint', 'injury') end
    if (p.drive or 0) >= 2 then add('no_drive', 'injury') end
    if (p.stamina or 0) >= 2 or (p.walk or 0) >= 2 or (p.reload or 0) >= 2 then add('no_heavy_work', 'injury') end
    for _, inj in pairs(injuries or {}) do
        if inj.type == 'head_trauma' and inj.stage ~= 'recovered' then add('concussion', 'head injury'); break end
    end
    return out
end
