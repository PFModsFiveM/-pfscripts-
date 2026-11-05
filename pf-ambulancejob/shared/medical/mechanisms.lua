-- Damage mechanisms (architecture 11.5): turns what the server observed about one damage episode
-- (health and armour drops, the weapon from an attacker's weaponDamageEvent, its own velocity
-- samples, the protection a player wears) into injury specs for PFMed.Engine.AddInjury.
--
-- Pure functions plus tunables; server/medical/ingest.lua decides what is verified and calls
-- M.Build. Everything random goes through ctx.roll, so specs drive the rules deterministically.
-- The victim client's bone report only picks a region (or a fall's landing) among the plausible
-- ones; severity always comes from the server-seen drop (M.SeverityCap).

PFMed = PFMed or {}
PFMed.Mechanisms = PFMed.Mechanisms or {}
local M = PFMed.Mechanisms

M.G = 9.81

-- Tunables. Config.Medical.Ingest overrides any key (config_medical.lua); listed here so the
-- resource works without that block.
M.Defaults = {
    SettleMs = 2000,           -- an episode resolves this long after its last signal (> the 1 s sampler)
    MaxEpisodeMs = 15000,      -- a continuous exposure (fire, a firefight) resolves at the latest after this
    DropWindowMs = 2000,       -- a hint needs a server-seen drop within this window
    AttackWindowMs = 1500,     -- or an attacker's weaponDamageEvent within this window
    BodySampleMs = 1000,       -- health/armour sampler (every online character)
    MotionSampleMs = 500,      -- velocity sampler (only players in a vehicle or falling)
    MotionTailMs = 3000,       -- sampling continues this long after landing / leaving a vehicle
    AirborneMaxMs = 15000,     -- an 'airborne' scope expires after this (parachutes, glitches)
    HintRate = 10, HintBurst = 20,          -- DamageHint per player (architecture 6.3)
    MotionRate = 4, MotionBurst = 8,        -- MotionHint per player
    AttackRate = 40, AttackBurst = 80,      -- weaponDamageEvent per sender (automatic weapons)
    MaxHitsPerEpisode = 8,
    MinFallSpeed = 5.0,        -- m/s downward (about 1.3 m): below this a server-only drop is not a fall
    MinDeltaV = 8,             -- km/h: below this a crash is not an injury mechanism
    FallBands = { 3, 6, 10 },  -- metres: < 3, 3-6, 6-10, > 10
    DeltaVBands = { 20, 50, 80 }, -- km/h: < 20, 20-50, 50-80, > 80
    -- weaponDamageEvent.hitComponent -> region, only for components verified in game (architecture 10);
    -- 20 is the head according to the community and must be confirmed in game.
    HitComponents = { [20] = 'head' },
    -- Inside these zones weaponDamageEvent is cancelled (no damage). Empty: never cancelled.
    -- { { coords = vector3(x, y, z), radius = 25.0, label = 'Pillbox lobby' } }
    SafeZones = {},
    -- chance that worn protection stops a bullet (by Config.WeaponClasses name)
    ArmourStop = { SMALL_CALIBER = 0.80, MEDIUM_CALIBER = 0.50, HIGH_CALIBER = 0.15, SHOTGUN = 0.50 },
    -- chance that a bullet leaves an exit wound (otherwise it is retained)
    ExitChance = { SMALL_CALIBER = 0.35, MEDIUM_CALIBER = 0.60, HIGH_CALIBER = 0.85, SHOTGUN = 0.10 },
    -- protection items (the server reads the inventory; architecture 10: helmets are item based)
    ProtectionItems = {
        helmet = { covers = 'head', reduce = 1, stop = { SMALL_CALIBER = 0.60, MEDIUM_CALIBER = 0.30, HIGH_CALIBER = 0.05, SHOTGUN = 0.40 } },
    },
    VestReduce = 1,            -- a vest lowers blunt/fall/crash torso injuries by this many levels
    AnomalyLogSeconds = 60,    -- at most one pf_med_events anomaly row per citizen and kind per window
}

local function copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

--- The tunables with Config.Medical.Ingest applied (one level deep).
function M.Cfg()
    local over = Config and Config.Medical and Config.Medical.Ingest
    if type(over) ~= 'table' then return M.Defaults end
    local out = {}
    for k, v in pairs(M.Defaults) do out[k] = v end
    for k, v in pairs(over) do if M.Defaults[k] ~= nil then out[k] = v end end
    return out
end

local function finite(v)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
M.Finite = finite

--- A weapon or model hash as an unsigned 32-bit integer (the game hands out signed and unsigned).
function M.Hash(v)
    v = finite(v)
    if not v or v < -2147483648 or v > 4294967295 then return nil end
    local n = math.tointeger(v)
    if not n then return nil end
    return n & 0xFFFFFFFF
end

-- ── weapons ────────────────────────────────────────────────────────────────────────────────────

local function H(name) return M.Hash(GetHashKey(name)) end

-- Hashes whose mechanism is not their Config.Weapons class.
local SPECIAL = {
    WEAPON_FALL = 'fall',
    WEAPON_RAMMED_BY_CAR = 'pedestrian', WEAPON_RUN_OVER_BY_CAR = 'pedestrian',
    WEAPON_STUNGUN = 'taser', WEAPON_STUNGUN_MP = 'taser',
    WEAPON_ELECTRIC_FENCE = 'electric_fence',
    WEAPON_DROWNING = 'drowning', WEAPON_DROWNING_IN_VEHICLE = 'drowning',
    WEAPON_BZGAS = 'smoke', WEAPON_SMOKEGRENADE = 'smoke',
    WEAPON_EXHAUSTION = 'exhaustion',
    WEAPON_HELI_CRASH = 'explosion',
    WEAPON_BARBED_WIRE = 'animal',            -- tearing wounds, like a bite
    WEAPON_HIT_BY_WATER_CANNON = 'blunt',
    WEAPON_UNARMED = 'blunt', WEAPON_NIGHTSTICK = 'blunt', WEAPON_FLASHLIGHT = 'blunt',
}
-- Thrusting blades stab; the others slash.
local THRUST = { WEAPON_KNIFE = true, WEAPON_DAGGER = true, WEAPON_SWITCHBLADE = true, WEAPON_BOTTLE = true }

local BY_CLASS = {
    SMALL_CALIBER = 'firearm', MEDIUM_CALIBER = 'firearm', HIGH_CALIBER = 'firearm', SHOTGUN = 'firearm',
    CUTTING = 'edged', LIGHT_IMPACT = 'blunt', HEAVY_IMPACT = 'blunt', OTHER = 'blunt',
    EXPLOSIVE = 'explosion', FIRE = 'burn', SUFFOCATING = 'smoke', WILDLIFE = 'animal',
}

-- Groups an attacker's client reports with weaponDamageEvent: a claim of one of these with no such
-- event is downgraded. The others (falls, fire, water, vehicles, animals...) have no attacker event.
M.NeedsAttacker = { firearm = true, edged = true, blunt = true, taser = true }

-- Mechanism (pf_med_injuries.mechanism) per group.
M.MechanismOf = {
    firearm = 'firearm', edged = 'edged', blunt = 'blunt', fall = 'fall', vehicle = 'vehicle', pedestrian = 'pedestrian',
    burn = 'burn', taser = 'electrical', electric_fence = 'electrical', explosion = 'explosion', drowning = 'drowning',
    smoke = 'environment', animal = 'animal', unknown = 'unknown',
}

local weaponIndex   -- [hash] = { group, class, thrust }

local function buildIndex()
    weaponIndex = {}
    local className = {}
    for name, id in pairs(Config and Config.WeaponClasses or {}) do className[id] = name end
    for hash, classId in pairs(Config and Config.Weapons or {}) do
        local h = M.Hash(hash)
        local cname = className[classId]
        if h and cname and BY_CLASS[cname] then weaponIndex[h] = { group = BY_CLASS[cname], class = cname } end
    end
    for name, group in pairs(SPECIAL) do
        local h = H(name)
        local prev = weaponIndex[h]
        weaponIndex[h] = { group = group, class = prev and prev.class or (group == 'blunt' and 'LIGHT_IMPACT' or nil) }
    end
    for name in pairs(THRUST) do
        local e = weaponIndex[H(name)]
        if e then e.thrust = true end
    end
end

--- { group, class, thrust } for a weapon hash; group 'unknown' when the hash is not known.
function M.Classify(weapon)
    if not weaponIndex then buildIndex() end
    local h = M.Hash(weapon)
    local e = h and weaponIndex[h]
    if not e then return { group = 'unknown' } end
    return { group = e.group, class = e.class, thrust = e.thrust == true }
end

function M.ResetIndex() weaponIndex = nil end

-- ── bands and caps ─────────────────────────────────────────────────────────────────────────────

--- Fall height (m) from the peak downward speed (m/s): h = v^2 / 2g.
function M.FallHeight(downSpeed)
    downSpeed = finite(downSpeed) or 0
    if downSpeed <= 0 then return 0 end
    return downSpeed * downSpeed / (2 * M.G)
end

--- 1..#edges+1: which band `value` falls in (edges ascending; a value on an edge is the upper band).
function M.Band(value, edges)
    value = finite(value) or 0
    local band = 1
    for i, e in ipairs(edges) do if value >= e then band = i + 1 end end
    return band
end

--- Total new severity one episode may create: ceil((hpDrop + 0.5 * armourDrop) / 10) + 1 (11.5).
function M.SeverityCap(hpDrop, armourDrop)
    local hp = math.max(0, finite(hpDrop) or 0)
    local ar = math.max(0, finite(armourDrop) or 0)
    if hp <= 0 and ar <= 0 then return 0 end
    return math.ceil((hp + 0.5 * ar) / 10) + 1
end

--- Severity 1..5 of one wound from the health it cost (GTA health: about 100 points of life).
function M.SeverityForDrop(drop)
    drop = finite(drop) or 0
    if drop < 8 then return 1 elseif drop < 18 then return 2 elseif drop < 35 then return 3 elseif drop < 60 then return 4 end
    return 5
end

-- ── regions ────────────────────────────────────────────────────────────────────────────────────

-- Where an unplaced hit lands, by exposed body area (torso-heavy).
M.RegionWeights = {
    { 'head', 0.06 }, { 'face', 0.03 }, { 'neck', 0.03 }, { 'chest_l', 0.10 }, { 'chest_r', 0.10 }, { 'abdomen', 0.12 },
    { 'back_upper', 0.06 }, { 'back_lower', 0.05 }, { 'pelvis', 0.05 },
    { 'shoulder_l', 0.03 }, { 'shoulder_r', 0.03 }, { 'upper_arm_l', 0.04 }, { 'upper_arm_r', 0.04 },
    { 'forearm_l', 0.03 }, { 'forearm_r', 0.03 }, { 'hand_l', 0.01 }, { 'hand_r', 0.01 },
    { 'thigh_l', 0.06 }, { 'thigh_r', 0.06 }, { 'knee_l', 0.01 }, { 'knee_r', 0.01 },
    { 'lower_leg_l', 0.04 }, { 'lower_leg_r', 0.04 }, { 'foot_l', 0.01 }, { 'foot_r', 0.01 },
}

local function weighted(list, roll)
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local target, acc = (roll or 0.5) * total, 0
    for _, e in ipairs(list) do
        acc = acc + e[2]
        if target <= acc then return e[1] end
    end
    return list[#list][1]
end

function M.RandomRegion(roll) return weighted(M.RegionWeights, roll) end

--- 'head', 'neck', 'torso', 'pelvis', 'arm', 'leg' of a region (nil when unknown).
function M.KindOfRegion(region)
    local A = PFMed.Anatomy
    local r = A and A.Regions[region]
    return r and A.GroupKind[r.group] or nil
end

--- How a fall landed, from the victim's bone hint: 'feet' (default), 'head' or 'side'.
function M.Landing(hintRegion)
    local kind = M.KindOfRegion(hintRegion)
    if kind == 'head' or kind == 'neck' then return 'head' end
    if kind == 'arm' or kind == 'torso' or kind == 'pelvis' then return 'side' end
    return 'feet'
end

-- ── rule tables ────────────────────────────────────────────────────────────────────────────────
-- An entry: { type, subtype, region = '..%s..', structure = '..%s..', sev, chance?, minSev?, attrs? }
-- or { pick = { entry, entry, ... }, sev } (one of them by roll). %s is the side of the episode.

local function E(t, sub, place, sev, extra)
    local e = { type = t, subtype = sub, sev = sev }
    if place and place:find('^R:') then e.region = place:sub(3) elseif place then e.structure = place end
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

-- Falls by landing and height band (< 3 m, 3-6 m, 6-10 m, > 10 m).
M.FallRules = {
    feet = {
        { E('bruising', 'contusion', 'R:lower_leg_%s', 1), E('sprain', 'ankle', 'ankle_%s', 1, { chance = 0.5 }) },
        { { pick = { E('fracture', 'closed', 'heel_%s', 2), E('fracture', 'closed', 'fibula_%s', 2, { attrs = { site = 'ankle' } }), E('fracture', 'closed', 'tibia_%s', 2) } },
          E('bruising', 'contusion', 'R:foot_%s', 1) },
        { E('fracture', 'closed', 'heel_%s', 3), { pick = { E('fracture', 'closed', 'femur_%s', 3), E('fracture', 'closed', 'pelvis', 3) } },
          E('spinal', 'lumbar', 'spine_lumbar', 2) },
        { E('fracture', 'comminuted', 'pelvis', 4), E('fracture', 'closed', 'femur_%s', 4), E('spinal', 'lumbar', 'spine_lumbar', 3),
          E('internal_bleeding', 'pelvic', 'pelvis', 3), E('head_trauma', 'concussion', 'brain', 3) },
    },
    head = {
        { E('bruising', 'hematoma', 'R:head', 1) },
        { E('head_trauma', 'concussion', 'brain', 2), E('bruising', 'contusion', 'R:face', 1), E('sprain', 'neck', 'neck', 1, { chance = 0.5 }) },
        { E('head_trauma', 'skull_fracture', 'skull', 3), E('spinal', 'cervical', 'spine_cervical', 2), E('fracture', 'closed', 'clavicle_%s', 2, { chance = 0.5 }) },
        { E('head_trauma', 'subdural', 'brain', 4), E('spinal', 'cervical', 'spine_cervical', 3), E('head_trauma', 'skull_fracture', 'skull', 4),
          E('fracture', 'closed', 'ribs_%s', 3) },
    },
    side = {
        { E('bruising', 'contusion', 'R:hint', 1) },
        { E('fracture', 'closed', 'forearm_%s', 2, { attrs = { site = 'wrist' } }), E('bruising', 'contusion', 'R:chest_%s', 1) },
        { E('fracture', 'closed', 'ribs_%s', 3), { pick = { E('fracture', 'closed', 'pelvis', 3), E('fracture', 'closed', 'clavicle_%s', 3) } },
          E('fracture', 'closed', 'forearm_%s', 2) },
        { E('fracture', 'comminuted', 'ribs_%s', 4), E('internal_bleeding', 'spleen', 'spleen', 3), E('fracture', 'closed', 'pelvis', 3),
          E('head_trauma', 'concussion', 'brain', 3) },
    },
}

-- Vehicle occupants by delta-v band (< 20, 20-50, 50-80, > 80 km/h).
M.VehicleRules = {
    { E('bruising', 'contusion', 'R:chest_%s', 1) },
    { E('sprain', 'neck', 'neck', 2), E('bruising', 'contusion', 'R:chest_%s', 2), E('fracture', 'closed', 'ribs_%s', 2, { chance = 0.4 }) },
    { E('fracture', 'closed', 'ribs_%s', 3), E('internal_bleeding', 'spleen', 'spleen', 3), E('head_trauma', 'concussion', 'brain', 2),
      E('fracture', 'closed', 'femur_%s', 3, { chance = 0.5 }) },
    { E('head_trauma', 'subdural', 'brain', 4), E('internal_bleeding', 'liver', 'liver', 4), E('fracture', 'closed', 'femur_%s', 4),
      E('fracture', 'comminuted', 'ribs_%s', 4), E('spinal', 'cervical', 'spine_cervical', 3) },
}

-- Which body parts each fall landing may injure (plausibility: a head-first fall does not produce an
-- isolated ankle fracture, a feet-first fall hits the lower body).
M.FallAllowed = {
    feet = { leg = true, pelvis = true, torso = true, head = 'band4' },
    head = { head = true, neck = true, torso = true, arm = true },
    side = { arm = true, torso = true, pelvis = true, leg = 'band3', head = 'band4' },
}

-- ── building specs ─────────────────────────────────────────────────────────────────────────────

local function rollOf(ctx)
    local r = ctx.roll
    return function()
        local v = r and r() or 0.5
        v = finite(v) or 0.5
        if v < 0 then v = 0 elseif v >= 1 then v = 0.999 end
        return v
    end
end

local function fill(s, side, hint)
    if not s then return nil end
    s = s:gsub('%%s', side)
    if s == 'hint' then return hint end
    return s
end

local function fromEntry(e, ctx, mech, roll)
    if e.pick then
        local i = math.min(#e.pick, math.floor(roll() * #e.pick) + 1)
        e = e.pick[i]
    end
    if e.chance and roll() >= e.chance then return nil end
    local spec = { mechanism = mech, type = e.type, subtype = e.subtype, severity = e.sev, attrs = copy(e.attrs) or {} }
    spec.region = fill(e.region, ctx.side, ctx.region or 'chest_' .. ctx.side)
    spec.structure = fill(e.structure, ctx.side)
    return spec
end

local function fromRules(list, ctx, mech, roll)
    local out = {}
    for _, e in ipairs(list or {}) do
        local s = fromEntry(e, ctx, mech, roll)
        if s then out[#out + 1] = s end
    end
    return out
end

local function S(mech, t, sub, region, structure, sev, attrs)
    return { mechanism = mech, type = t, subtype = sub, region = region, structure = structure, severity = math.max(1, math.min(5, sev)), attrs = attrs or {} }
end

-- a structure in the region the type allows, by roll (nil = skin and muscle only)
local function pickStructure(typeName, subtype, region, roll, surfaceOk)
    local A, I = PFMed.Anatomy, PFMed.Injuries
    local s, depth, found = A.PickStructure(region, roll(), function(id) return I.AllowsStructure(typeName, subtype, id) end, surfaceOk)
    if not found then return nil, nil, false end
    return s, depth, true
end

local function firstBoneIn(region)
    local A = PFMed.Anatomy
    local r = A.Regions[region]
    if not r then return nil end
    for _, e in ipairs(r.structures) do
        if e[1] and A.Structures[e[1]].kind == 'bone' then return e[1] end
    end
    return nil
end

local Rules = {}
M.Rules = Rules

function Rules.firearm(ctx, roll)
    local cfg = ctx.cfg
    local region = ctx.region or M.RandomRegion(roll())
    local A = PFMed.Anatomy
    local sev = ctx.sev
    if ctx.class == 'HIGH_CALIBER' then sev = sev + 1 end
    local attrs = { weapon = ctx.weapon, caliber = ctx.class }
    -- worn protection over the region may stop the bullet (blunt trauma under the vest instead)
    local cover = A.ArmourFor(region)
    local stop
    if cover == 'vest' and ctx.vest then stop = cfg.ArmourStop[ctx.class] or 0
    elseif cover == 'helmet' and ctx.helmet then stop = (ctx.helmet.stop or {})[ctx.class] or 0 end
    if stop and roll() < stop then
        attrs.stopped = cover
        local out = { S('firearm', 'bruising', cover == 'helmet' and 'hematoma' or 'contusion', region, nil, math.min(2, sev), attrs) }
        local kind = M.KindOfRegion(region)
        if kind == 'torso' and ctx.class ~= 'SMALL_CALIBER' and roll() < 0.25 then
            local side = region:sub(-1) == 'r' and 'r' or 'l'
            out[#out + 1] = S('firearm', 'fracture', 'closed', nil, 'ribs_' .. side, 2, { weapon = ctx.weapon, stopped = cover })
        end
        return out
    end
    local subtype
    if sev <= 1 and roll() < 0.5 then subtype = 'graze'
    elseif roll() < (cfg.ExitChance[ctx.class] or 0.5) then subtype = 'perforating'
    else subtype = 'retained'; attrs.projectile = true end
    local structure = nil
    if subtype ~= 'graze' then structure = pickStructure('gunshot', subtype, region, roll, true) end
    return { S('firearm', 'gunshot', subtype, region, structure, sev, attrs) }
end

function Rules.edged(ctx, roll)
    local region = ctx.region or M.RandomRegion(roll())
    local kind = M.KindOfRegion(region)
    local attrs = { weapon = ctx.weapon }
    if ctx.thrust then
        local subtype = (kind == 'torso' or kind == 'neck' or ctx.sev >= 3) and 'penetrating' or 'superficial'
        local structure = subtype == 'penetrating' and pickStructure('stab', subtype, region, roll, true) or nil
        return { S('edged', 'stab', subtype, region, structure, ctx.sev, attrs) }
    end
    local structure = pickStructure('laceration', nil, region, roll, true)
    local subtype = ctx.sev >= 2 and 'deep' or 'superficial'
    if structure and PFMed.Anatomy.Structures[structure].kind == 'vessel' then
        if ctx.sev >= 3 then subtype = 'arterial' else structure = nil end
    end
    return { S('edged', 'laceration', subtype, region, structure, ctx.sev, attrs) }
end

function Rules.blunt(ctx, roll)
    local region = ctx.region or M.RandomRegion(roll())
    local kind = M.KindOfRegion(region)
    local heavy = ctx.class == 'HEAVY_IMPACT'
    local attrs = { weapon = ctx.weapon }
    local out = { S('blunt', 'bruising', kind == 'head' and region == 'head' and 'hematoma' or 'contusion', region, nil, ctx.sev, attrs) }
    if region == 'face' and ctx.sev >= 2 and roll() < 0.4 then
        out[#out + 1] = S('blunt', 'fracture', 'closed', 'face', 'face_jaw', ctx.sev, { weapon = ctx.weapon })
    elseif region == 'head' and ctx.sev >= 2 and roll() < 0.5 then
        out[#out + 1] = S('blunt', 'head_trauma', 'concussion', 'head', 'brain', ctx.sev - 1, { weapon = ctx.weapon })
    elseif heavy and ctx.sev >= 3 and roll() < 0.4 then
        local bone
        if kind == 'torso' then bone = 'ribs_' .. (region:sub(-1) == 'r' and 'r' or 'l') else bone = firstBoneIn(region) end
        if bone then out[#out + 1] = S('blunt', 'fracture', 'closed', nil, bone, ctx.sev - 1, { weapon = ctx.weapon }) end
    end
    return out
end

function Rules.animal(ctx, roll)
    local region = ctx.region or ('lower_leg_' .. ctx.side)
    return { S('animal', 'laceration', ctx.sev >= 2 and 'deep' or 'superficial', region, nil, ctx.sev, { weapon = ctx.weapon }) }
end

function Rules.burn(ctx, roll)
    local region = ctx.region or ('chest_' .. ctx.side)
    local seconds = math.max(1, ctx.duration or 1)
    local rate = (ctx.hpDrop or 0) / seconds
    local subtype = rate < 5 and 'first' or rate < 15 and 'second' or 'third'
    local tbsa = math.floor(math.max(1, math.min(90, seconds * 3 + (ctx.hpDrop or 0) / 4)) + 0.5)
    local sev = tbsa < 5 and 1 or tbsa < 10 and 2 or tbsa < 20 and 3 or tbsa < 40 and 4 or 5
    return { S('burn', 'burn', subtype, region, nil, sev, { weapon = ctx.weapon, tbsa = tbsa }) }
end

function Rules.taser(ctx)
    return { S('electrical', 'electrical', 'taser', ctx.region or 'back_upper', nil, 1, { weapon = ctx.weapon }) }
end

function Rules.electric_fence(ctx)
    local high = (ctx.hpDrop or 0) >= 40
    return {
        S('electrical', 'electrical', high and 'high_voltage' or 'low_voltage', 'hand_' .. ctx.side, nil, ctx.sev, { weapon = ctx.weapon }),
        S('electrical', 'burn', high and 'second' or 'first', 'hand_' .. ctx.side, nil, math.max(1, ctx.sev - 1), { tbsa = 1 }),
    }
end

function Rules.explosion(ctx, roll)
    local region = ctx.region or ('chest_' .. ctx.side)
    local tbsa = math.floor(math.max(2, math.min(60, (ctx.hpDrop or 0) / 2)) + 0.5)
    local out = {
        S('explosion', 'burn', 'second', region, nil, tbsa < 10 and 2 or tbsa < 20 and 3 or 4, { weapon = ctx.weapon, tbsa = tbsa, blast = true }),
        S('explosion', 'bruising', 'contusion', M.RandomRegion(roll()), nil, math.max(1, ctx.sev - 1), { blast = true }),
    }
    if (ctx.hpDrop or 0) >= 50 then
        out[#out + 1] = S('explosion', 'organ_trauma', 'pneumothorax', 'chest_' .. ctx.side, 'lung_' .. ctx.side, 3, { blast = true })
    end
    return out
end

function Rules.drowning(ctx)
    return { S('drowning', 'drowning', 'near_drowning', nil, 'airway', ctx.sev, {}) }
end

function Rules.smoke(ctx)
    return { S('environment', 'respiratory', 'smoke_inhalation', nil, 'airway', math.min(3, ctx.sev), { weapon = ctx.weapon }) }
end

function Rules.exhaustion() return {} end

function Rules.unknown(ctx, roll)
    local region = ctx.region or 'chest_' .. ctx.side
    return { S('unknown', 'bruising', 'contusion', region, nil, math.min(2, ctx.sev), { claimed = ctx.claimed }) }
end

function Rules.pedestrian(ctx)
    local s, sd = ctx.side, ctx.sev
    local attrs = { weapon = ctx.weapon }
    local out = { S('pedestrian', 'fracture', 'closed', nil, 'tibia_' .. s, math.max(2, sd), attrs) }
    if sd >= 2 then out[#out + 1] = S('pedestrian', 'sprain', 'knee', nil, 'knee_' .. s, sd - 1, {}) end
    if sd >= 3 then out[#out + 1] = S('pedestrian', 'fracture', 'closed', nil, 'pelvis', sd - 1, {}) end
    if sd >= 4 then out[#out + 1] = S('pedestrian', 'head_trauma', 'concussion', nil, 'brain', sd - 1, {}) end
    if ctx.runOver then out[#out + 1] = S('pedestrian', 'crush', 'chest', 'chest_' .. s, nil, sd, {}) end
    return out
end

--- Fall rules: ctx.downSpeed (m/s, server-bounded), ctx.landing ('feet' | 'head' | 'side').
function Rules.fall(ctx, roll)
    local h = M.FallHeight(ctx.downSpeed)
    local band = M.Band(h, ctx.cfg.FallBands)
    local landing = M.FallRules[ctx.landing] and ctx.landing or 'feet'
    local out = fromRules(M.FallRules[landing][band], ctx, 'fall', roll)
    for _, s in ipairs(out) do s.attrs.fallHeight = math.floor(h * 10 + 0.5) / 10; s.attrs.landing = landing end
    return out, { band = band, height = h, landing = landing }
end

--- Vehicle occupant rules: ctx.deltaV (km/h, server-bounded), ctx.seatbelt (true / false / nil).
function Rules.vehicle(ctx, roll)
    local dv = finite(ctx.deltaV) or 0
    if dv < (ctx.cfg.MinDeltaV or 8) then return {}, { band = 0 } end
    local band = M.Band(dv, ctx.cfg.DeltaVBands)
    -- the seatbelt is a client claim: it moves the band by one at most (architecture 10)
    if ctx.seatbelt == true then band = math.max(1, band - 1) elseif ctx.seatbelt == false then band = math.min(#M.VehicleRules, band + 1) end
    local out = fromRules(M.VehicleRules[band], ctx, 'vehicle', roll)
    for _, s in ipairs(out) do s.attrs.deltaV = math.floor(dv + 0.5) end
    return out, { band = band }
end

-- ── protection, plausibility, cap ──────────────────────────────────────────────────────────────

local BLUNT_LIKE = { blunt = true, fall = true, vehicle = true, pedestrian = true, explosion = true, unknown = true }

--- Lowers injuries under worn protection: a helmet (item) for the head, a vest (server armour) for
--- the torso, against blunt mechanisms. Bullets are handled by the stop roll in Rules.firearm.
function M.Protect(specs, ctx)
    for _, s in ipairs(specs) do
        if BLUNT_LIKE[s.mechanism] then
            local kind = PFMed.Anatomy.GroupKindOf(s.region, s.structure)
            if kind == 'head' and ctx.helmet then
                s.severity = math.max(1, s.severity - (ctx.helmet.reduce or 1))
                if s.type == 'head_trauma' and s.subtype ~= 'concussion' then s.subtype = 'concussion'; s.structure = 'brain' end
                s.attrs.protected = 'helmet'
            elseif kind == 'torso' and ctx.vest and s.type ~= 'internal_bleeding' then
                s.severity = math.max(1, s.severity - (ctx.cfg.VestReduce or 1))
                s.attrs.protected = 'vest'
            end
        end
    end
    return specs
end

--- Drops fall injuries the landing cannot produce. Returns kept, dropped.
function M.Plausible(specs, ctx, info)
    if not info or not info.landing then return specs, {} end
    local allowed = M.FallAllowed[info.landing] or {}
    local kept, dropped = {}, {}
    for _, s in ipairs(specs) do
        local kind = PFMed.Anatomy.GroupKindOf(s.region, s.structure)
        local rule = kind and allowed[kind]
        local ok = rule == true or (rule == 'band3' and (info.band or 0) >= 3) or (rule == 'band4' and (info.band or 0) >= 4)
        if ok then kept[#kept + 1] = s else dropped[#dropped + 1] = s end
    end
    return kept, dropped
end

--- Caps the total severity of a list in order (the first injuries keep theirs). Returns the list.
function M.ApplyCap(specs, cap)
    local out, left = {}, math.max(0, math.floor(cap or 0))
    for _, s in ipairs(specs) do
        if left <= 0 then break end
        s.severity = math.min(s.severity, left, 5)
        left = left - s.severity
        out[#out + 1] = s
    end
    return out
end

--- Injury specs for one cause. ctx = { group, class, thrust, weapon, region, hpDrop, armourDrop,
--- sev, vest, helmet, downSpeed, landing, deltaV, seatbelt, duration, side, runOver, claimed,
--- roll, cfg }. Returns specs (protection applied, implausible ones removed, no cap), info.
function M.Build(ctx)
    ctx.cfg = ctx.cfg or M.Cfg()
    local roll = rollOf(ctx)
    ctx.side = ctx.side or (roll() < 0.5 and 'l' or 'r')
    if not ctx.sev then ctx.sev = M.SeverityForDrop((ctx.hpDrop or 0) + 0.5 * (ctx.armourDrop or 0)) end
    local rule = Rules[ctx.group] or Rules.unknown
    local specs, info = rule(ctx, roll)
    specs = specs or {}
    M.Protect(specs, ctx)
    local dropped
    specs, dropped = M.Plausible(specs, ctx, info)
    return specs, info or {}, dropped or {}
end
