-- Damage ingestion (architecture 4.1, 6.4, 10, 11.5): injuries come from what the server observes,
-- never from what a client says it suffered.
--
-- Signals, from most to least trusted:
--   * health and armour drops: a 1 s sampler over every online character (2 natives each), plus an
--     immediate read when a hint arrives;
--   * weaponDamageEvent from the attacker's client (weapon, victim, hit component);
--   * velocity samples every 0.5 s, only for players in a vehicle or falling (they enter that scope
--     through MotionHint and leave it when the server sees them out of the vehicle / on the ground);
--   * the victim client's DamageHint (bone, weapon, fall speed, vehicle speeds, seatbelt, water,
--     fire): it can only choose among plausible regions and landings and is clamped to the server's
--     own samples.
-- Signals of one player that arrive close together form an episode; an episode resolves
-- Config SettleMs after its last signal into injury specs (shared/medical/mechanisms.lua), capped by
-- the server-seen drop, and each spec is added with an idempotency key derived from the episode.
-- Inconsistencies (a hint with no damage, an attack with no drop, a claimed weapon nobody fired, a
-- fall or crash the server never saw) are logged as pf_med_events 'anomaly' rows with counts.
-- A drop with no hint, no attacker event and no server-seen fall or crash creates nothing: the
-- server cannot tell it from scripted damage (hunger, /kill, other resources).

PFMed = PFMed or {}
PFMed.Ingest = PFMed.Ingest or {}
local Ing = PFMed.Ingest
local M = PFMed.Mechanisms

local function Store() return PFMed.Store end
local function Engine() return PFMed.Engine end

Ing.Random = function() return math.random() end   -- specs replace this for determinism

local SESSION = tostring(os.time())

local body = {}        -- [src] = { hp, ar }: last sampled values
local episodes = {}    -- [src] = open episode
local scope = {}       -- [src] = { state, untilMs, outSince }: players the velocity sampler reads
local motion = {}      -- [src] = { { at, vz, speed, inVeh }, ... } newest last (bounded)
local buckets = { hint = {}, motion = {}, attack = {} }
local seqs = {}        -- [src] = { [seq] = true, order = { ... } } recent hint numbers
local pedSrc = {}      -- [ped] = src (refreshed by the body sampler)
local anomalies = {}   -- [cid .. '|' .. kind] = { count, lastWrite }
local retries = {}     -- { { cid, spec, key, attempts } } injuries that met a busy patient record
local counter = 0

Ing.stats = { resolved = 0, created = 0, anomalies = {} }

local MAX_MOTION = 12
local MAX_SEQS = 32
local MAX_DROPS = 16
local MAX_HINTS = 8
local MAX_RETRIES = 200

local function cfg() return M.Cfg() end

--- Clears every per-player table (specs; resource restart).
function Ing.Reset()
    body, episodes, scope, motion, seqs, pedSrc, anomalies, retries = {}, {}, {}, {}, {}, {}, {}, {}
    buckets = { hint = {}, motion = {}, attack = {} }
    Ing.stats = { resolved = 0, created = 0, anomalies = {} }
end

-- token bucket per source
local function take(kind, src, rate, burst, now)
    local b = buckets[kind][src]
    if not b then b = { tokens = burst, at = now }; buckets[kind][src] = b end
    b.tokens = math.min(burst, b.tokens + math.max(0, now - b.at) * rate / 1000)
    b.at = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

local function validSrc(src)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return nil end
    return src
end

-- ── anomalies ──────────────────────────────────────────────────────────────────────────────────

local function writeAnomaly(cid, a, kind)
    local detail = {}
    for k, v in pairs(a.detail or {}) do detail[k] = v end
    detail.kind, detail.count = kind, a.count
    Store().Audit(cid, 'anomaly', { src = a.src, cid = cid }, detail)
    a.count, a.lastWrite = 0, os.time()
end

--- Counts an anomaly; at most one row per citizen and kind per AnomalyLogSeconds (with the count).
local function anomaly(cid, src, kind, detail)
    if not cid then return end
    local key = cid .. '|' .. kind
    local a = anomalies[key]
    if not a then a = { count = 0 }; anomalies[key] = a end
    a.count, a.src, a.detail = a.count + 1, src, detail
    Ing.stats.anomalies[kind] = (Ing.stats.anomalies[kind] or 0) + 1
    if a.lastWrite and os.time() - a.lastWrite < (cfg().AnomalyLogSeconds or 60) then return end
    writeAnomaly(cid, a, kind)
end
Ing.Anomaly = anomaly

local function flushAnomalies(cid)
    for key, a in pairs(anomalies) do
        local c, kind = key:match('^(.-)|(.+)$')
        if c == cid then
            if a.count > 0 then writeAnomaly(cid, a, kind) end
            anomalies[key] = nil
        end
    end
end

-- ── episodes ───────────────────────────────────────────────────────────────────────────────────

local function newEpisode(src, cid, now)
    counter = counter + 1
    return {
        id = SESSION .. '-' .. counter, src = src, cid = cid, firstAt = now, lastAt = now,
        hpDrop = 0, armourDrop = 0, armourBefore = body[src] and body[src].ar or 0,
        drops = {}, attacks = {}, hints = {},
    }
end

local function due(ep, now, c)
    return now - ep.lastAt >= c.SettleMs or now - ep.firstAt >= c.MaxEpisodeMs
end

local resolve -- forward

--- The open episode of a player (a due one is resolved first). nil for a player without a character.
local function episodeFor(src, now)
    local cid = Store().CidOf(src)
    if not cid then return nil end
    local ep = episodes[src]
    if ep and (ep.cid ~= cid or due(ep, now, cfg())) then
        episodes[src] = nil
        resolve(src, ep, now)
        ep = nil
    end
    if not ep then
        ep = newEpisode(src, cid, now)
        episodes[src] = ep
    end
    return ep
end

local function addDrop(src, hpDrop, arDrop, armourBefore, now)
    local ep = episodeFor(src, now)
    if not ep then return end
    if #ep.drops == 0 then ep.armourBefore = armourBefore end
    ep.hpDrop = ep.hpDrop + hpDrop
    ep.armourDrop = ep.armourDrop + arDrop
    if #ep.drops < MAX_DROPS then ep.drops[#ep.drops + 1] = now end
    ep.lastAt = now
end

-- ── body sampler (health and armour) ───────────────────────────────────────────────────────────

local function sampleOne(src, now)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    pedSrc[ped] = src
    local hp = math.tointeger(math.floor(tonumber(GetEntityHealth(ped)) or 0)) or 0
    local ar = math.tointeger(math.floor(tonumber(GetPedArmour(ped)) or 0)) or 0
    local cid = Store().CidOf(src)
    local b = body[src]
    -- a new character on this server id starts from its own health, not the last one's
    if not b or b.cid ~= cid then body[src] = { hp = hp, ar = ar, cid = cid } return end
    local hpDrop = hp < b.hp and (b.hp - hp) or 0
    local arDrop = ar < b.ar and (b.ar - ar) or 0
    if hpDrop > 0 or arDrop > 0 then addDrop(src, hpDrop, arDrop, b.ar, now) end
    b.hp, b.ar = hp, ar
end
Ing.SampleOne = sampleOne

--- One pass of the 1 s sampler over every online character. Returns how many were read.
local passes = 0
function Ing.SampleBody(now)
    now = now or GetGameTimer()
    local n = 0
    local alive = {}
    Store().Each(function(_, p)
        if p.src then
            n = n + 1
            alive[p.src] = true
            sampleOne(p.src, now)
        end
    end)
    passes = passes + 1
    if passes % 30 == 0 then Ing.Sweep(alive) end
    return n
end

--- Last health/armour the sampler read (16A may use the armour instead of a client report).
function Ing.LastBody(src)
    local b = body[tonumber(src) or -1]
    if not b then return nil end
    return b.hp, b.ar
end

-- ── velocity sampler (scoped) ──────────────────────────────────────────────────────────────────

local function sampleMotion(src, sc, now, c)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then scope[src] = nil return end
    local veh = GetVehiclePedIsIn(ped, false) or 0
    local v = GetEntityVelocity(veh ~= 0 and veh or ped)
    local vx, vy, vz = 0, 0, 0
    if type(v) == 'table' or type(v) == 'userdata' or type(v) == 'vector3' then vx, vy, vz = tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0 end
    local list = motion[src]
    if not list then list = {}; motion[src] = list end
    list[#list + 1] = { at = now, vz = vz, speed = math.sqrt(vx * vx + vy * vy + vz * vz), inVeh = veh ~= 0 }
    while #list > MAX_MOTION do table.remove(list, 1) end
    -- the server, not the client, decides when the scope ends
    if sc.state == 'vehicle' then
        if veh == 0 then
            sc.outSince = sc.outSince or now
            if now - sc.outSince >= c.MotionTailMs then scope[src] = nil end
        else
            sc.outSince = nil
        end
    elseif veh == 0 and vz > -1.0 and sc.state == 'airborne' then
        sc.state, sc.untilMs = 'tail', math.min(sc.untilMs or now, now + c.MotionTailMs)
    end
end

--- One pass of the 0.5 s sampler: only players in the scope are read. Returns how many.
function Ing.SampleMotion(now)
    now = now or GetGameTimer()
    local c = cfg()
    local n = 0
    for src, sc in pairs(scope) do
        if sc.untilMs and now > sc.untilMs then
            scope[src] = nil
        else
            n = n + 1
            sampleMotion(src, sc, now, c)
        end
    end
    return n
end

function Ing.InScope(src) return scope[tonumber(src) or -1] ~= nil end
function Ing.ScopeCount()
    local n = 0
    for _ in pairs(scope) do n = n + 1 end
    return n
end

local MOTION_STATES = { airborne = true, vehicle = true, ground = true, water = true }

--- The client's motion state changed: it only changes what the velocity sampler reads.
function Ing.OnMotionHint(src, state, now)
    src = validSrc(src)
    if not src or type(state) ~= 'string' or not MOTION_STATES[state] then return 'bad_args' end
    now = now or GetGameTimer()
    local c = cfg()
    if not take('motion', src, c.MotionRate, c.MotionBurst, now) then return 'rate_limited' end
    if not Store().CidOf(src) then return 'no_patient' end
    local sc = scope[src]
    if state == 'airborne' then
        scope[src] = { state = 'airborne', untilMs = now + c.AirborneMaxMs }
    elseif state == 'vehicle' then
        scope[src] = { state = 'vehicle' }
    elseif sc then
        sc.state, sc.untilMs = 'tail', now + c.MotionTailMs
    end
    if scope[src] then sampleMotion(src, scope[src], now, c) end
    return 'ok'
end

-- ── weaponDamageEvent ──────────────────────────────────────────────────────────────────────────

local function victimOf(netId)
    netId = math.tointeger(tonumber(netId))
    if not netId or netId <= 0 then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return nil end
    local src = pedSrc[entity]
    if src and GetPlayerPed(src) == entity then return src end
    -- a player's ped is owned by that player
    if NetworkGetEntityOwner then
        local ok, owner = pcall(NetworkGetEntityOwner, entity)
        owner = ok and validSrc(owner) or nil
        if owner and GetPlayerPed(owner) == entity then pedSrc[entity] = owner return owner end
    end
    return nil
end

local function inSafeZone(src, c)
    local zones = c.SafeZones
    if type(zones) ~= 'table' or #zones == 0 then return false end
    local pos = GetEntityCoords(GetPlayerPed(src))
    for _, z in ipairs(zones) do
        if type(z) == 'table' and z.coords and tonumber(z.radius) and #(pos - z.coords) <= z.radius then return true end
    end
    return false
end

local function recordAttack(victim, sender, weapon, data, now, c)
    local ep = episodeFor(victim, now)
    if not ep or #ep.attacks >= c.MaxHitsPerEpisode * 2 then return end
    local attackerCid
    if sender ~= victim then
        -- the sender's own ped holds the weapon: it is the attacker (an NPC it owns is not)
        local sp = GetPlayerPed(sender)
        if sp and sp ~= 0 and M.Hash(GetSelectedPedWeapon(sp)) == weapon then attackerCid = Store().CidOf(sender) end
    end
    ep.attacks[#ep.attacks + 1] = {
        at = now, weapon = weapon, sender = sender, attackerCid = attackerCid,
        hitComponent = math.tointeger(tonumber(data.hitComponent)),
    }
    ep.lastAt = now
end

--- weaponDamageEvent (attacker's client, before the damage applies). Returns true when the event
--- must be cancelled (victim inside a configured safe zone); nothing else is ever cancelled.
function Ing.OnWeaponDamage(sender, data, now)
    sender = validSrc(sender)
    if not sender or type(data) ~= 'table' then return false end
    now = now or GetGameTimer()
    local c = cfg()
    if not take('attack', sender, c.AttackRate, c.AttackBurst, now) then return false end
    local weapon = M.Hash(data.weaponType)
    if not weapon then return false end
    local ids = {}
    if type(data.hitGlobalIds) == 'table' then
        for i = 1, math.min(8, #data.hitGlobalIds) do ids[#ids + 1] = data.hitGlobalIds[i] end
    end
    if #ids == 0 and data.hitGlobalId ~= nil then ids[1] = data.hitGlobalId end
    local cancel = false
    for _, netId in ipairs(ids) do
        local victim = victimOf(netId)
        if victim then
            if inSafeZone(victim, c) then cancel = true else recordAttack(victim, sender, weapon, data, now, c) end
        end
    end
    return cancel
end

-- ── hints ──────────────────────────────────────────────────────────────────────────────────────

local function int(v, lo, hi)
    v = M.Finite(v)
    if not v then return nil end
    v = math.floor(v)
    if v < lo or v > hi then return nil end
    return math.tointeger(v)
end
local function num(v, lo, hi)
    v = M.Finite(v)
    if not v or v < lo or v > hi then return nil end
    return v
end
local function smallTable(t, max)
    if type(t) ~= 'table' then return nil end
    local n = 0
    for k in pairs(t) do
        n = n + 1
        if n > max or type(k) ~= 'string' then return nil end
    end
    return t
end

--- Checks a DamageHint payload (<= 16 fields, nested tables <= 4). Returns a clean hint or nil.
function Ing.CleanHint(t)
    if not smallTable(t, 16) then return nil end
    local h = {
        seq = t.seq ~= nil and int(t.seq, 0, 2147483647) or nil,
        weapon = t.weapon ~= nil and M.Hash(t.weapon) or nil,
        bone = t.bone ~= nil and int(t.bone, 0, 65535) or nil,
        hpBefore = int(t.hpBefore, 0, 1000), hpAfter = int(t.hpAfter, 0, 1000),
        armourBefore = int(t.armourBefore, 0, 200), armourAfter = int(t.armourAfter, 0, 200),
        attacker = t.attacker ~= nil and int(t.attacker, 1, 65535) or nil,
        water = t.water == true or nil, fire = t.fire == true or nil,
    }
    if t.seq ~= nil and not h.seq then return nil end
    local fall = smallTable(t.fall, 4)
    if fall then h.fall = { vz = num(fall.vz, -100, 100) } end
    local veh = smallTable(t.vehicle, 4)
    if veh then
        h.vehicle = { speedBefore = num(veh.speedBefore, 0, 150), speedAfter = num(veh.speedAfter, 0, 150) }
        if type(veh.seatbelt) == 'boolean' then h.vehicle.seatbelt = veh.seatbelt end
    end
    return h
end

local function seenSeq(src, seq)
    local s = seqs[src]
    if not s then s = { set = {}, order = {} }; seqs[src] = s end
    if s.set[seq] then return true end
    s.set[seq] = true
    s.order[#s.order + 1] = seq
    if #s.order > MAX_SEQS then s.set[table.remove(s.order, 1)] = nil end
    return false
end

local function addHint(src, h, now)
    sampleOne(src, now) -- the drop may already be visible to the server
    local ep = episodeFor(src, now)
    if not ep then return 'no_patient' end
    if #ep.hints >= MAX_HINTS then return 'ignored' end
    h.at = now
    if h.bone and not h.region then h.region = PFMed.Anatomy.RegionForBone(h.bone, Ing.Random()) end
    ep.hints[#ep.hints + 1] = h
    ep.lastAt = now
    return 'ok'
end

--- pf-ambulancejob:server:DamageHint. Returns a status (specs read it).
function Ing.OnHint(src, payload, now)
    src = validSrc(src)
    if not src then return 'bad_args' end
    now = now or GetGameTimer()
    local c = cfg()
    if not take('hint', src, c.HintRate, c.HintBurst, now) then return 'rate_limited' end
    local h = Ing.CleanHint(payload)
    if not h then return 'bad_args' end
    if not Store().CidOf(src) then return 'no_patient' end
    if h.seq and seenSeq(src, h.seq) then return 'duplicate' end
    h.origin = 'hint'
    return addHint(src, h, now)
end

-- legacy report (pf-ambulancejob:server:processDamage): its type and zone become a claim and a region
local LEGACY_CLAIM = {
    gunshot_wound = 'firearm', laceration = 'edged', blunt_trauma = 'blunt', burn = 'burn', fracture = 'unknown',
    respiratory = 'smoke', electrical_burn = 'electric_fence', blast_injury = 'explosion',
}
local LEGACY_REGION = { head = 'head', torso = 'chest_l', left_arm = 'upper_arm_l', right_arm = 'upper_arm_r', left_leg = 'thigh_l', right_leg = 'thigh_r' }

--- An old client's self-reported injury, treated as a hint (same checks as DamageHint).
function Ing.OnLegacyReport(src, data, now)
    src = validSrc(src)
    if not src or type(data) ~= 'table' then return 'bad_args' end
    now = now or GetGameTimer()
    local c = cfg()
    if not take('hint', src, c.HintRate, c.HintBurst, now) then return 'rate_limited' end
    local claim = type(data.injuryType) == 'string' and LEGACY_CLAIM[data.injuryType]
    if not claim then return 'bad_args' end
    if not Store().CidOf(src) then return 'no_patient' end
    local region = type(data.bodyZone) == 'string' and LEGACY_REGION[data.bodyZone] or nil
    return addHint(src, { origin = 'legacy', claim = claim, region = region }, now)
end

-- ── resolving an episode ───────────────────────────────────────────────────────────────────────

local function near(list, at, window)
    for _, t in ipairs(list) do if math.abs(t - at) <= window then return true end end
    return false
end
local function attackTimes(ep)
    local out = {}
    for _, a in ipairs(ep.attacks) do out[#out + 1] = a.at end
    return out
end

-- the server's motion samples around the damage
local function motionFacts(src, ep, c)
    local list = motion[src] or {}
    local from = (ep.drops[1] or ep.firstAt) - 3000
    local to = (ep.drops[#ep.drops] or ep.lastAt) + 500
    local facts = { peakDown = 0, sampled = false, inVeh = false, before = 0, after = nil, lastAirAt = nil }
    local firstDrop = ep.drops[1] or ep.firstAt
    for _, s in ipairs(list) do
        if s.at >= from and s.at <= to then
            facts.sampled = true
            if not s.inVeh and -s.vz > facts.peakDown then facts.peakDown = -s.vz; facts.lastAirAt = s.at end
            if s.inVeh then
                facts.inVeh = true
                if s.at <= firstDrop and s.at >= firstDrop - 2500 and s.speed > facts.before then facts.before = s.speed end
            end
            if s.at >= firstDrop then facts.after = s.speed end
        end
    end
    if facts.inVeh and facts.after == nil and #list > 0 then facts.after = list[#list].speed end
    return facts
end

-- a hint claim in the light of the server's facts: returns a cause or nil (and logs anomalies)
local function verifyClaim(h, group, ep, facts, c)
    local cid, src = ep.cid, ep.src
    if h.vehicle and facts.inVeh then group = 'vehicle'
    elseif h.fall and (group == 'unknown' or group == 'fall') then group = 'fall'
    elseif h.water and (group == 'unknown' or group == 'drowning') then group = 'drowning'
    elseif h.fire and group == 'unknown' then group = 'burn' end

    if group == 'fall' then
        if not facts.sampled or facts.peakDown < c.MinFallSpeed then
            anomaly(cid, src, 'fall_unverified', { claimed = h.fall and h.fall.vz or nil, seen = facts.peakDown })
            return { group = 'unknown', claimed = 'fall', region = h.region }
        end
        -- the client saw the impact; the server's last sample may be up to one interval before it
        local peak = facts.peakDown
        local allowance = M.G * math.min(0.6, ((ep.drops[1] or ep.lastAt) - (facts.lastAirAt or ep.lastAt)) / 1000)
        local claimed = h.fall and h.fall.vz and -h.fall.vz or peak
        local down = math.max(peak, math.min(claimed, peak + math.max(0, allowance)))
        return { group = 'fall', downSpeed = down, landing = M.Landing(h.region), region = h.region }
    end
    if group == 'vehicle' or h.vehicle then
        if not facts.inVeh or facts.before <= 0 then
            anomaly(cid, src, 'vehicle_unverified', { claimed = h.vehicle and h.vehicle.speedBefore or nil })
            return { group = 'unknown', claimed = 'vehicle', region = h.region }
        end
        local before, after = facts.before, facts.after or 0
        if h.vehicle and h.vehicle.speedBefore then before = math.max(facts.before * 0.85, math.min(h.vehicle.speedBefore, facts.before * 1.15)) end
        if h.vehicle and h.vehicle.speedAfter then after = math.max(0, math.max((facts.after or 0) - 3, math.min(h.vehicle.speedAfter, (facts.after or 0) + 3))) end
        local dv = math.max(0, (before - after) * 3.6)
        return { group = 'vehicle', deltaV = dv, seatbelt = h.vehicle and h.vehicle.seatbelt, region = h.region }
    end
    if M.NeedsAttacker[group] then
        anomaly(cid, src, 'weapon_unconfirmed', { weapon = h.weapon, claim = group })
        return { group = 'unknown', claimed = group, region = h.region }
    end
    if group == 'pedestrian' then
        local runOver = h.weapon and h.weapon == M.Hash(GetHashKey('WEAPON_RUN_OVER_BY_CAR'))
        return { group = 'pedestrian', weapon = h.weapon, runOver = runOver, region = h.region }
    end
    local cl = h.weapon and M.Classify(h.weapon) or {}
    return { group = group, weapon = h.weapon, class = cl.class, region = h.region }
end

local function helmetOf(src, c)
    for name, def in pairs(c.ProtectionItems or {}) do
        if type(def) == 'table' and def.covers == 'head' then
            local ok, has = pcall(function() return exports['pfm-inventory']:HasItem(src, name) end)
            if ok and has == true then return def end
        end
    end
    return nil
end

local function addOne(cid, spec, key)
    local E = Engine()
    local ctx = { key = key, actor = { kind = 'system', label = 'damage ingestion' }, source = 'ingest' }
    local inj, err, extra = E.AddInjury(cid, spec, ctx)
    if inj then return inj, nil, extra end
    if err == 'conflict' then
        -- the record is at its open-injury cap: keyed requests are refused, so merge once without a key
        ctx.key = nil
        inj, err = E.AddInjury(cid, spec, ctx)
        if inj then return inj end
    end
    return nil, err
end

--- Turns one finished episode into injuries. Returns { created = { injury... }, causes = n } | nil.
function resolve(src, ep, now)
    local S = Store()
    -- the damage happened to the episode's character, even if that player has left since
    local cid = ep.cid
    Ing.stats.resolved = Ing.stats.resolved + 1
    local c = cfg()
    local hp, ar = ep.hpDrop, ep.armourDrop
    if hp <= 0 and ar <= 0 then
        if #ep.attacks > 0 then anomaly(cid, src, 'attack_without_drop', { hits = #ep.attacks, weapon = ep.attacks[1].weapon, attacker = ep.attacks[1].attackerCid }) end
        if #ep.hints > 0 then anomaly(cid, src, 'hint_without_damage', { hints = #ep.hints, weapon = ep.hints[1].weapon }) end
        return { created = {}, causes = 0 }
    end
    local p = S.Peek(cid)
    if p and p.consciousness == 'dead' then return { created = {}, causes = 0 } end

    -- a hint counts only next to a server-seen drop or an attacker event
    local hints, aTimes = {}, attackTimes(ep)
    for _, h in ipairs(ep.hints) do
        if near(ep.drops, h.at, c.DropWindowMs) or near(aTimes, h.at, c.AttackWindowMs) then hints[#hints + 1] = h
        else anomaly(cid, src, 'hint_without_damage', { weapon = h.weapon }) end
    end

    local causes, used = {}, {}
    -- one wound per confirmed hit; the region from a verified hit component, else the nearest hint
    for _, a in ipairs(ep.attacks) do
        if #causes >= c.MaxHitsPerEpisode then break end
        local cl = M.Classify(a.weapon)
        if cl.group ~= 'unknown' and cl.group ~= 'exhaustion' then
            local region, from = c.HitComponents[a.hitComponent], 'component'
            if not region then
                local best, bestDt
                for _, h in ipairs(hints) do
                    local dt = math.abs(h.at - a.at)
                    if not used[h] and h.region and dt <= c.AttackWindowMs and (not bestDt or dt < bestDt) then best, bestDt = h, dt end
                end
                if best then used[best] = true; region, from = best.region, 'hint' else from = 'random' end
            end
            causes[#causes + 1] = { group = cl.group, class = cl.class, thrust = cl.thrust, weapon = a.weapon, region = region,
                regionFrom = from, attackerCid = a.attackerCid, hit = true }
        end
    end
    -- what the hints claim beyond the confirmed hits (one cause per kind)
    local facts = motionFacts(src, ep, c)
    local seen = {}
    for _, h in ipairs(hints) do
        if not used[h] then
            local group = h.claim or (h.weapon and M.Classify(h.weapon).group) or 'unknown'
            if not (#ep.attacks > 0 and M.NeedsAttacker[group]) then
                local cause = verifyClaim(h, group, ep, facts, c)
                if cause and not seen[cause.group] then
                    seen[cause.group] = true
                    cause.regionFrom = 'hint'
                    causes[#causes + 1] = cause
                end
            end
        end
    end
    -- no hint and no attacker: only a fall or crash the server itself sampled is a mechanism
    if #causes == 0 then
        if facts.sampled and not facts.inVeh and facts.peakDown >= c.MinFallSpeed then
            causes[1] = { group = 'fall', downSpeed = facts.peakDown, landing = 'feet', regionFrom = 'server' }
        elseif facts.inVeh and facts.before > 0 then
            local dv = math.max(0, (facts.before - (facts.after or 0)) * 3.6)
            if dv >= c.MinDeltaV then causes[1] = { group = 'vehicle', deltaV = dv, regionFrom = 'server' } end
        end
    end
    if #causes == 0 then return { created = {}, causes = 0 } end

    local vest = (ep.armourBefore or 0) > 0 or ar > 0
    local helmet = helmetOf(src, c)
    local hits = 0
    for _, cause in ipairs(causes) do if cause.hit then hits = hits + 1 end end
    local eff = hp + 0.5 * ar
    local duration = ((ep.drops[#ep.drops] or now) - (ep.drops[1] or now)) / 1000 + 1
    local specs = {}
    for _, cause in ipairs(causes) do
        local share = cause.hit and eff / math.max(1, hits) or eff
        local ctx = {
            group = cause.group, class = cause.class, thrust = cause.thrust, weapon = cause.weapon, region = cause.region,
            hpDrop = cause.hit and hp / math.max(1, hits) or hp, armourDrop = cause.hit and ar / math.max(1, hits) or ar,
            sev = M.SeverityForDrop(share), vest = vest, helmet = helmet, downSpeed = cause.downSpeed, landing = cause.landing,
            deltaV = cause.deltaV, seatbelt = cause.seatbelt, duration = duration, runOver = cause.runOver, claimed = cause.claimed,
            roll = Ing.Random, cfg = c,
        }
        local list = M.Build(ctx)
        for _, s in ipairs(list) do
            s.attrs = s.attrs or {}
            s.attrs.place = cause.regionFrom
            s.attackerCid = cause.attackerCid
            specs[#specs + 1] = s
        end
    end
    specs = M.ApplyCap(specs, M.SeverityCap(hp, ar))

    local created = {}
    for i, spec in ipairs(specs) do
        local key = ('pf-ambulancejob:dmg:%s:%s:%d'):format(cid, ep.id, i)
        local inj, err = addOne(cid, spec, key)
        if inj then
            created[#created + 1] = inj
        elseif err == 'busy' and #retries < MAX_RETRIES then
            retries[#retries + 1] = { cid = cid, spec = spec, key = key, attempts = 1 }
        else
            print(('^3[pf-ambulancejob]^7 damage injury for %s not stored: %s'):format(cid, tostring(err)))
        end
    end
    Ing.stats.created = Ing.stats.created + #created
    return { created = created, causes = #causes }
end
Ing.Resolve = function(src, ep, now) return resolve(src, ep, now or GetGameTimer()) end

--- Resolves every episode whose settle time passed, and retries injuries that met a busy record.
--- Returns the results of this pass ({ [src] = result }).
function Ing.ResolveDue(now)
    now = now or GetGameTimer()
    local c = cfg()
    local results = {}
    for src, ep in pairs(episodes) do
        if due(ep, now, c) then
            episodes[src] = nil
            results[src] = resolve(src, ep, now)
        end
    end
    if #retries > 0 then
        local list = retries
        retries = {}
        for _, r in ipairs(list) do
            local inj, err = addOne(r.cid, r.spec, r.key)
            if not inj and err == 'busy' and r.attempts < 5 then
                r.attempts = r.attempts + 1
                retries[#retries + 1] = r
            end
        end
    end
    return results
end

function Ing.OpenEpisode(src) return episodes[tonumber(src) or -1] end

--- Clears a player who left: their open episode is resolved now (a hit just before a logout still
--- counts), their anomaly counts are written, and every per-player table is cleared.
function Ing.Forget(src)
    src = validSrc(src)
    if not src then return end
    local ep = episodes[src]
    episodes[src] = nil
    local cid = ep and ep.cid or (body[src] and body[src].cid)
    if ep then
        local ok, err = pcall(resolve, src, ep, GetGameTimer())
        if not ok then print('^1[pf-ambulancejob]^7 resolving damage on leave failed: ' .. tostring(err)) end
    end
    if cid then flushAnomalies(cid) end
    body[src], scope[src], motion[src], seqs[src] = nil, nil, nil, nil
    buckets.hint[src], buckets.motion[src], buckets.attack[src] = nil, nil, nil
    for ped, s in pairs(pedSrc) do if s == src then pedSrc[ped] = nil end end
end

--- Every 30 sampler passes: forgets players who are no longer online (no playerDropped handler is
--- needed, so the store's lifecycle handlers stay the only ones), writes anomaly counts that waited
--- longer than the log window and drops idle counters. Bounded by the online players.
function Ing.Sweep(alive)
    local gone = {}
    for _, t in ipairs({ body, scope, motion, seqs, buckets.hint, buckets.motion, buckets.attack }) do
        for src in pairs(t) do if not alive[src] and not episodes[src] then gone[src] = true end end
    end
    for src in pairs(gone) do Ing.Forget(src) end
    local t, window = os.time(), cfg().AnomalyLogSeconds or 60
    for key, a in pairs(anomalies) do
        if not a.lastWrite or t - a.lastWrite >= window then
            if a.count > 0 then
                local cid, kind = key:match('^(.-)|(.+)$')
                writeAnomaly(cid, a, kind)
            else
                anomalies[key] = nil
            end
        end
    end
end

-- ── events and loops ───────────────────────────────────────────────────────────────────────────

RegisterNetEvent('pf-ambulancejob:server:DamageHint', function(payload)
    Ing.OnHint(source, payload)
end)

RegisterNetEvent('pf-ambulancejob:server:MotionHint', function(state)
    Ing.OnMotionHint(source, state)
end)

-- weaponDamageEvent is a server game event (sender, data); CancelEvent only inside a safe zone
AddEventHandler('weaponDamageEvent', function(sender, data)
    if Ing.OnWeaponDamage(sender, data) then CancelEvent() end
end)

CreateThread(function()
    while true do
        Wait(cfg().BodySampleMs or 1000)
        local ok, err = pcall(Ing.SampleBody)
        if not ok then print('^1[pf-ambulancejob]^7 health sampler failed: ' .. tostring(err)) end
        ok, err = pcall(Ing.ResolveDue)
        if not ok then print('^1[pf-ambulancejob]^7 damage ingestion failed: ' .. tostring(err)) end
    end
end)

CreateThread(function()
    while true do
        Wait(cfg().MotionSampleMs or 500)
        if next(scope) then
            local ok, err = pcall(Ing.SampleMotion)
            if not ok then print('^1[pf-ambulancejob]^7 velocity sampler failed: ' .. tostring(err)) end
        end
    end
end)
