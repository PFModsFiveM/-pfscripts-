-- Server-owned down / death state (architecture 1, 4.1, 5.1, 9; batch 16A).
--
-- This module is the only writer of the metadata flags `inlaststand` / `isdead` and of the state bag
-- `pf:down`. They mirror the engine's level of consciousness: unconscious or arrest = last stand,
-- dead = dead. Clients only ask:
--   * ReportDown: "my ped died". Accepted when the server reads the ped health at or below
--     Config.Medical.Down.DownHealth (or the engine already has the patient down). The patient then
--     goes unconscious with a hold (persisted in hold_until), and the client resurrects into the
--     last-stand pose only after the server's SetDown.
--   * ReviveApplied(token): the answer to a revive the server started. The server issued the token
--     after its own checks (distance, state, item consumed), and re-reads the ped health before the
--     patient is marked up. A refused or unanswered revive leaves the patient down.
--   * RequestHelp, RequestRespawn (respawn is in server/main.lua, which owns the hospital beds).
-- The legacy last stand stays: an unconscious patient nobody revived dies after LaststandSeconds
-- (the transition kind 'laststand', registered below), then may respawn after RespawnAfterSeconds.
-- A down player moving faster than an escort without being attached is logged as an anomaly and is
-- sent the down state again. Armour is saved from the server ped (the client SetArmor is ignored).
-- When the patient record cannot be loaded (database down) the state is kept in memory for that
-- player, so nobody is stuck dead on the ground; it is pushed into the engine once it loads.

PFMed = PFMed or {}
PFMed.Down = PFMed.Down or {}
local D = PFMed.Down
local Store, Engine, P = PFMed.Store, PFMed.Engine, PFMed.Physiology

-- The legacy last-stand rule as an engine transition: an unconscious patient whose last stand ran
-- out (or who is killed again while down, or by an admin Kill) dies. Registered here because this
-- module owns that rule; the automatic machine never uses the kind.
P.Transitions.unconscious.dead = P.Transitions.unconscious.dead or {}
P.Transitions.unconscious.dead.laststand = true
P.Transitions.arrest.dead.laststand = true

local function cfg() return (Config.Medical and Config.Medical.Down) or {} end
local function now() return os.time() end
local function num(v, default) v = tonumber(v) if v == nil or v ~= v or v == math.huge or v == -math.huge then return default end return v end

local recs = {}        -- [src] = { cid, state, since, pos, posAt, anomalyAt, resentAt, moveGraceUntil, fallback, alertAt }
local downSet = {}     -- [src] = true while the server has them down (the 1 s tick visits only these)
local tokens = {}      -- [token] = { src, cid, mode, reset, by, reason, expires, close }
local tokenOf = {}     -- [src] = token of the revive in flight
local firstAid = {}    -- [targetSrc] = { helper, cid, started, duration }
local rateAt = {}      -- [src] = { [action] = os.time() of the last accepted call }
local pendingSync = {} -- [src] = tries: a player whose record was not loaded yet
local reportBusy = {}  -- [src] = true while a report waits for the ped
local SYNC_TRIES = 60

D.stats = { anomalies = 0, refusedReports = 0, refusedRevives = 0 }

-- ── helpers ────────────────────────────────────────────────────────────────────────────────────

local function getPlayer(src)
    if not src then return nil end
    local ok, Player = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(Player) == 'table' and type(Player.PlayerData) == 'table' then return Player end
    return nil
end
D.GetPlayer = getPlayer

local function setMeta(Player, key, value)
    local f = (type(Player.Functions) == 'table' and Player.Functions.SetMetaData) or Player.SetMetaData
    if f then f(key, value) end
end

local function notify(src, text, kind)
    TriggerClientEvent('QBCore:Notify', src, text, kind or 'error')
end

--- false when the action is allowed now (and stamps it), true when the caller is too fast.
local function limited(src, action, seconds)
    local t = now()
    rateAt[src] = rateAt[src] or {}
    local last = rateAt[src][action]
    if last and t - last < seconds then return true end
    rateAt[src][action] = t
    return false
end
D.Limited = limited

local function pedOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return ped
end

local function healthOf(src)
    local ped = pedOf(src)
    return ped and tonumber(GetEntityHealth(ped)) or nil
end
D.HealthOf = healthOf

local function coordsOf(src)
    local ped = pedOf(src)
    return ped and GetEntityCoords(ped) or nil
end

local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
D.Dist = dist

--- Server distance between two players (math.huge when one has no ped).
function D.PlayerDistance(a, b) return dist(coordsOf(a), coordsOf(b)) end

local function isOnDutyMedic(Player)
    local job = Player and Player.PlayerData.job
    return type(job) == 'table' and (Config.AllowedJobs or { ambulance = true })[job.name] == true and job.onduty == true
end
D.IsOnDutyMedic = isOnDutyMedic

local function respawnAfter()
    return num(P.Cfg(Config.Medical).Consciousness.RespawnAfterSeconds, 300)
end

local function newToken()
    local parts = {}
    for i = 1, 4 do parts[i] = ('%06x'):format(math.random(0, 0xFFFFFF)) end
    return table.concat(parts)
end

local function emit(name, ...)
    TriggerEvent('pf-ambulancejob:server:' .. name, ...)
end

-- ── level and mirrors ──────────────────────────────────────────────────────────────────────────

--- The down state for a level of consciousness: false, 'unconscious', 'arrest' or 'dead'.
function D.StateOf(level)
    if level == 'unconscious' or level == 'arrest' or level == 'dead' then return level end
    return false
end

--- level, patient (engine record, when loaded for this player), rec. Without a loaded record the
--- in-memory fallback decides ('alert' when there is none).
function D.Level(src)
    local rec = recs[src]
    local cid = (rec and rec.cid) or Store.CidOf(src)
    local p = cid and Store.Peek(cid) or nil
    if p and p.src == src then return p.consciousness, p, rec end
    if rec and rec.fallback then return rec.fallback.level, nil, rec end
    return 'alert', nil, rec
end

--- down:boolean, state for a server id (what other modules and resources should read).
function D.IsDown(src)
    local level = D.Level(src)
    local st = D.StateOf(level)
    return st ~= false, st or level
end

local function ensureRec(src, Player)
    Player = Player or getPlayer(src)
    if not Player then return nil end
    local cid = Player.PlayerData.citizenid
    local rec = recs[src]
    if not rec or rec.cid ~= cid then
        rec = { cid = cid }
        recs[src] = rec
    end
    return rec, Player
end

--- Seconds of last stand left for an unconscious patient (nil when the rule is off or not unconscious).
local function laststandLeft(p, rec, at)
    local c = cfg()
    if c.LaststandEndsInDeath == false then return nil end
    local level = p and p.consciousness or (rec and rec.fallback and rec.fallback.level)
    if level ~= 'unconscious' then return nil end
    local since = (p and p.down_since) or (rec and rec.fallback and rec.fallback.since) or at
    return math.max(0, since + num(c.LaststandSeconds, 360) - at)
end

--- What the client needs to show the state: times are relative seconds (client clocks differ).
function D.Info(src, cause)
    local at = now()
    local level, p, rec = D.Level(src)
    local f = rec and rec.fallback or {}
    local since = (p and p.down_since) or f.since or (rec and rec.since) or at
    local info = { since = since, cause = cause, serverTime = at, downFor = math.max(0, at - since) }
    if level == 'dead' then
        local canAt = (p and p.can_respawn_at) or f.canRespawnAt or at
        info.canRespawnAt = canAt
        info.respawnIn = math.max(0, canAt - at)
        info.cost = Config.BillCost
    elseif level == 'unconscious' then
        info.laststandIn = laststandLeft(p, rec, at)
        info.helpIn = math.max(0, num(cfg().FirstAidAfterSeconds, 60) - info.downFor)
    elseif level == 'arrest' then
        local arrestSince = p and p.arrest_since or at
        info.arrestIn = math.max(0, arrestSince + num(P.Cfg(Config.Medical).Consciousness.ArrestToDeathSeconds, 300) - at)
        info.helpIn = 0
    end
    info.holdHealth = num(cfg().HoldHealth, 150)
    return info
end

--- Sends the server's down state to the player's client (the client resurrects only after this).
function D.SendState(src, cause)
    local level = D.Level(src)
    local st = D.StateOf(level)
    TriggerClientEvent('pf-ambulancejob:client:SetDown', src, st, D.Info(src, cause))
end

local function setBag(src, value)
    pcall(function() Player(src).state:set('pf:down', value, true) end)
end

--- Writes the mirrors of a player's level: metadata, state bag, client, EMS request.
--- opts = { cause, close = { status, reason, includeCitizen } } (the close for a down that ended).
function D.Apply(src, level, opts)
    opts = opts or {}
    local rec, Player = ensureRec(src)
    if not rec then return end
    local st = D.StateOf(level)
    local was = rec.state
    rec.state = st
    if st then
        downSet[src] = true
        rec.since = rec.since or now()
    else
        downSet[src] = nil
        rec.since, rec.pos, rec.posAt = nil, nil, nil
    end
    local m = Player.PlayerData.metadata or {}
    local wantLast, wantDead = st == 'unconscious' or st == 'arrest', st == 'dead'
    if m.inlaststand ~= wantLast then setMeta(Player, 'inlaststand', wantLast) end
    if m.isdead ~= wantDead then setMeta(Player, 'isdead', wantDead) end
    setBag(src, st)
    D.SendState(src, opts.cause)
    if (was and true or false) ~= (st and true or false) and PFEmsRequests and PFEmsRequests.OnDownChanged then
        local close = opts.close or rec.upClose or {}
        rec.upClose = nil
        PFEmsRequests.OnDownChanged(src, close[1], close[2], close[3])
    end
end

--- The engine changed a patient's level (engine listener; also the fallback's own changes).
function D.OnLevel(cid, from, to, cause, srcHint)
    local src = srcHint or Store.SourceOf(cid)
    if not src or not getPlayer(src) then return end
    local wasDown, isDown = D.StateOf(from), D.StateOf(to)
    D.Apply(src, to, { cause = cause })
    local rec = recs[src]
    if isDown and not wasDown then
        emit('patientDown', src, cid, isDown, (rec and rec.cause) or { mechanism = tostring(cause or 'unknown') })
        D.AlertEms(src, Lang:t('info.civ_down'))
    end
    if to == 'dead' and from ~= 'dead' then
        emit('patientDied', src, cid, cause)
        D.AlertEms(src, Lang:t('info.civ_died'))
    end
    if not isDown and rec then rec.cause = nil end
end

Engine.OnConsciousness(function(cid, from, to, cause) D.OnLevel(cid, from, to, cause) end)

--- Moves a player to a level through the engine, or the in-memory fallback without a record.
--- Returns true | nil, error, current level.
function D.SetLevel(src, to, kind, cause, opts)
    local level, p = D.Level(src)
    if p then return Engine.SetConsciousness(p.cid, to, kind, cause, opts) end
    local rec = ensureRec(src)
    if not rec then return nil, 'offline' end
    if level == to then return true end
    if not P.CanTransition(level, to, kind) then return nil, 'invalid_state', level end
    local at = now()
    if D.StateOf(to) then
        local f = rec.fallback or { since = at }
        f.level = to
        if to == 'dead' then f.deadAt, f.canRespawnAt = at, at + respawnAfter() end
        rec.fallback = f
    else
        rec.fallback = nil
    end
    D.OnLevel(rec.cid, level, to, cause, src)
    return true
end

--- The engine record of an online player, loading it when the store is ready (nil without one).
local function recordOf(src, cid)
    local p = Store.Peek(cid)
    if p and p.src == src then return p end
    if Store.Ready() then
        local loaded = Store.OnPlayerLoaded(src, cid)
        if loaded and loaded.src == src then return loaded end
    end
    return nil
end

-- ── reports ────────────────────────────────────────────────────────────────────────────────────

local function cleanHint(h)
    if type(h) ~= 'table' then return nil end
    local out = {}
    local w = h.weapon
    if type(w) == 'number' and w == w and math.abs(w) < 2 ^ 32 then out.weapon = math.floor(w)
    elseif type(w) == 'string' and #w <= 64 then out.weapon = w:gsub('[^%w_]', '') end
    local att = math.tointeger(tonumber(h.attacker))
    if att and att > 0 then
        local A = getPlayer(att)
        -- the attacker's identity is the server's; the claim is only a hint (marked as such)
        if A then out.attackerCid = A.PlayerData.citizenid end
    end
    return out
end

--- Puts a player down (unconscious, held for the last stand). cause = short text.
function D.ForceDown(src, cause, opts)
    opts = opts or {}
    local rec, Player = ensureRec(src)
    if not rec then return nil, 'offline' end
    rec.cause = opts.causeInfo or { mechanism = cause }
    local p = recordOf(src, Player.PlayerData.citizenid)
    if p then
        local ok, err, cur = Engine.SetConsciousness(p.cid, 'unconscious', 'report', cause, {
            actor = opts.actor, holdSeconds = num(cfg().ReportHoldSeconds, 360),
        })
        if not ok then
            -- already further down (arrest, dead): the client is put back into that state
            D.SendState(src)
            return nil, err, cur
        end
        if D.StateOf(p.consciousness) and rec.state ~= D.StateOf(p.consciousness) then D.Apply(src, p.consciousness) end
        return true
    end
    return D.SetLevel(src, 'unconscious', 'report', cause, opts)
end

--- ReportDown: payload = { nonce, kind = 'dead' | 'laststand', hint = { weapon, attacker } }.
--- Returns true when the player is (now) down.
function D.Report(src, payload)
    if type(payload) ~= 'table' then payload = {} end
    local kind = payload.kind == 'dead' and 'dead' or 'laststand'
    if payload.nonce ~= nil and (type(payload.nonce) ~= 'string' or #payload.nonce > 32) then return false end
    local rec = ensureRec(src)
    if not rec then return false end
    local level = D.Level(src)
    local st = D.StateOf(level)
    local c = cfg()
    if st then
        -- killed again while down (the legacy "dead in last stand"): only with the ped really down
        if kind == 'dead' and st ~= 'dead' then
            local h = healthOf(src)
            if h and h <= num(c.DeadHealth, 100) then
                return D.SetLevel(src, 'dead', 'laststand', 'killed_while_down') == true
            end
        end
        D.SendState(src)
        return true
    end
    if reportBusy[src] then return false end
    reportBusy[src] = true
    local seen = false
    local okWait = pcall(function()
        local checks = math.max(1, math.floor(num(c.ReportChecks, 6)))
        for i = 1, checks do
            local h = healthOf(src)
            if h and h <= num(c.DownHealth, 150) then seen = true return end
            if i < checks then Wait(num(c.ReportCheckMs, 500)) end
        end
    end)
    reportBusy[src] = nil
    if not okWait or not seen then
        D.stats.refusedReports = D.stats.refusedReports + 1
        D.Anomaly(src, 'report_refused', { health = healthOf(src), kind = kind })
        D.SendState(src)
        return false
    end
    if not getPlayer(src) then return false end
    if D.StateOf(D.Level(src)) then D.SendState(src) return true end
    local hint = cleanHint(payload.hint) or {}
    local ok = D.ForceDown(src, 'report', { causeInfo = { mechanism = 'reported', weapon = hint.weapon, attackerCid = hint.attackerCid, claimed = true } })
    return ok == true
end

-- ── anomalies and the 1 s tick ─────────────────────────────────────────────────────────────────

--- One audit row (rate limited per player) for something the server saw that should not happen.
function D.Anomaly(src, what, detail)
    local rec = recs[src]
    local cid = (rec and rec.cid) or Store.CidOf(src)
    if not cid then return end
    local at = now()
    rec = rec or {}
    rec.anomalyAt = rec.anomalyAt or {}
    if (rec.anomalyAt[what] or 0) + num(cfg().AnomalyLogSeconds, 30) > at then return end
    rec.anomalyAt[what] = at
    D.stats.anomalies = D.stats.anomalies + 1
    detail = type(detail) == 'table' and detail or {}
    detail.kind = what
    Store.Audit(cid, 'anomaly', { kind = 'system', label = 'downstate', src = src }, detail)
end

--- No movement check for a while (a teleport the server made: hospital bed, respawn).
function D.MoveGrace(src, seconds)
    local rec = recs[src]
    if rec then rec.moveGraceUntil = now() + (seconds or 10); rec.pos, rec.posAt = nil, nil end
end

local function attached(ped)
    if not GetEntityAttachedTo then return false end
    local ok, e = pcall(GetEntityAttachedTo, ped)
    return ok and e ~= nil and e ~= 0
end

local function escorted(src)
    local ok, v = pcall(function()
        local s = Player(src).state
        return s['pf:escort'] or s['pf:onStretcher']
    end)
    return ok and v ~= nil and v ~= false
end

--- A down player moving faster than an escort, not attached and not in a vehicle (architecture 6.8).
function D.CheckMovement(src, rec, at)
    local ped = pedOf(src)
    if not ped then return end
    local pos = GetEntityCoords(ped)
    if rec.pos and rec.posAt and at > rec.posAt and at >= (rec.moveGraceUntil or 0) then
        local speed = dist(pos, rec.pos) / (at - rec.posAt)
        if speed > num(cfg().EscortSpeed, 3.0) and not attached(ped) and GetVehiclePedIsIn(ped, false) == 0 and not escorted(src) then
            D.Anomaly(src, 'moving_while_down', { speed = math.floor(speed * 10 + 0.5) / 10, state = rec.state })
            if at - (rec.resentAt or 0) >= num(cfg().ResendSeconds, 5) then
                rec.resentAt = at
                D.SendState(src, 'resync')
            end
        end
    end
    rec.pos, rec.posAt = pos, at
end

local function expireTokens(at)
    for token, t in pairs(tokens) do
        if at > t.expires then
            tokens[token] = nil
            if tokenOf[t.src] == token then tokenOf[t.src] = nil end
            -- an unanswered revive leaves the player down: put the client back into that state
            if D.StateOf(D.Level(t.src)) and getPlayer(t.src) then D.SendState(t.src, 'revive_expired') end
        end
    end
    for target, fa in pairs(firstAid) do
        if at > fa.started + fa.duration + 60 then firstAid[target] = nil end
    end
end

--- One pass (every second): last stand expiry, movement checks of down players, revive token
--- expiry, players whose record was still loading. Returns how many down players were visited.
function D.Tick(at)
    at = at or now()
    local n = 0
    for src in pairs(downSet) do
        local rec = recs[src]
        if not rec or not getPlayer(src) then
            downSet[src] = nil
        else
            n = n + 1
            local level, p = D.Level(src)
            local st = D.StateOf(level)
            if st ~= rec.state then
                D.Apply(src, level)
            elseif st then
                local left = laststandLeft(p, rec, at)
                if left and left <= 0 and not tokenOf[src] then
                    D.SetLevel(src, 'dead', 'laststand', 'laststand_expired')
                else
                    D.CheckMovement(src, rec, at)
                end
            end
        end
    end
    expireTokens(at)
    for src, tries in pairs(pendingSync) do
        if tries >= SYNC_TRIES or not getPlayer(src) then pendingSync[src] = nil else D.Sync(src) end
    end
    return n
end

-- ── sync at load / leave ───────────────────────────────────────────────────────────────────────

--- Writes the mirrors from the patient record of a player who came online (login, resource
--- restart). A record that is not loaded yet is retried by the tick.
function D.Sync(src)
    local rec, Player = ensureRec(src)
    if not rec then return false end
    local cid = Player.PlayerData.citizenid
    local p = Store.Peek(cid)
    if not p or p.src ~= src then
        pendingSync[src] = (pendingSync[src] or 0) + 1
        if pendingSync[src] >= SYNC_TRIES then
            -- the record never loaded: keep the down flags the player had, in memory
            local m = Player.PlayerData.metadata or {}
            if m.isdead == true or m.inlaststand == true then
                local at = now()
                rec.fallback = rec.fallback or { level = m.isdead and 'dead' or 'unconscious', since = at }
                if rec.fallback.level == 'dead' then rec.fallback.deadAt, rec.fallback.canRespawnAt = at, at + respawnAfter() end
            end
            pendingSync[src] = nil
            D.Apply(src, D.Level(src))
        end
        return false
    end
    pendingSync[src] = nil
    local m = Player.PlayerData.metadata or {}
    local at = now()
    -- down in memory while the record was unavailable: the record learns it now
    if rec.fallback and not D.StateOf(p.consciousness) then
        local f = rec.fallback
        rec.fallback = nil
        Engine.SetConsciousness(cid, 'unconscious', 'report', 'fallback', { holdSeconds = num(cfg().ReportHoldSeconds, 360) })
        if f.level == 'dead' then Engine.SetConsciousness(cid, 'dead', 'laststand', 'fallback') end
    elseif not p.persisted and not D.StateOf(p.consciousness) and (m.isdead == true or m.inlaststand == true) then
        -- first login since the engine owns the down state: the flags the old client wrote count once
        rec.cause = { mechanism = 'legacy' }
        Engine.SetConsciousness(cid, 'unconscious', 'report', 'legacy', { holdSeconds = num(cfg().ReportHoldSeconds, 360) })
        if m.isdead == true then Engine.SetConsciousness(cid, 'dead', 'laststand', 'legacy') end
    elseif p.consciousness == 'unconscious' and not rec.resumed then
        -- offline time does not count toward the last stand (relog, crash, restart): the record was
        -- last written while they were online (an unconscious patient ticks every few seconds), so
        -- the clock and the hold resume from there
        rec.resumed = true
        local offline = math.max(0, at - num(p.updated_at, at))
        if offline > 0 and p.down_since then
            p.down_since = p.down_since + offline
            if p.ctx and p.ctx.holdUntil then p.ctx.holdUntil = p.ctx.holdUntil + offline end
            p.updated_at = at
            Store.MarkDirty(cid)
        end
    end
    rec.fallback = nil
    D.Apply(src, p.consciousness, { cause = 'sync' })
    return true
end

function D.Forget(src)
    recs[src], downSet[src], rateAt[src], pendingSync[src], reportBusy[src] = nil, nil, nil, nil, nil
    local token = tokenOf[src]
    if token then tokens[token] = nil end
    tokenOf[src] = nil
    firstAid[src] = nil
    for target, fa in pairs(firstAid) do if fa.helper == src then firstAid[target] = nil end end
end

-- ── physiology reset (revive, respawn) ─────────────────────────────────────────────────────────

local RESETS = { full = true, physiology = true, stabilize = true, first_aid = true, none = true }
D.Resets = RESETS

--- Applies a reset to a state table (a patient record or a copy of it).
local function resetState(s, reset, c)
    local healthy = P.NewState(c)
    if reset == 'full' or reset == 'physiology' then
        s.blood_ml, s.hgb_factor, s.airway, s.breathing, s.temp_c = healthy.blood_ml, healthy.hgb_factor, healthy.airway, healthy.breathing, healthy.temp_c
        s.toxins, s.drugs, s.pain = {}, {}, 0
    elseif reset == 'stabilize' then
        local floor = c.Physiology.BloodMl * num(cfg().ReviveBloodFraction, 0.8)
        s.blood_ml = math.max(num(s.blood_ml, floor), floor)
        s.airway, s.breathing = 'clear', 1.0
    elseif reset == 'first_aid' then
        s.airway, s.breathing = 'clear', 1.0
    end
end

--- What a reset does to one open injury: 'recovered' (healed) or 'stop' (bleeding stopped).
local function injuryAction(inj, reset)
    if not inj or inj.stage == 'recovered' or reset == 'none' then return nil end
    if reset == 'full' then return 'recovered' end
    if (tonumber(inj.bleed_ml_min) or 0) > 0 or inj.stage == 'injured' or inj.stage == 'complicated' then return 'stop' end
    return nil
end

local function stateCopy(p)
    return P.CopyState({ blood_ml = p.blood_ml, hgb_factor = p.hgb_factor, airway = p.airway, breathing = p.breathing,
        pain = p.pain, temp_c = p.temp_c, toxins = p.toxins, drugs = p.drugs })
end

--- Whether a patient would stay conscious after a reset. Returns viable, reason
--- ('intoxicated', 'head_injury', an arrest cause, or 'unresponsive').
function D.Viable(p, reset, at)
    at = at or now()
    local c = P.Cfg(Config.Medical)
    local s = stateCopy(p)
    resetState(s, reset, c)
    local injuries = {}
    for id, inj in pairs(p.injuries or {}) do
        local action = injuryAction(inj, reset)
        if action ~= 'recovered' and inj.stage ~= 'recovered' then
            local copy = {}
            for k, v in pairs(inj) do copy[k] = v end
            if action == 'stop' then copy.bleed_ml_min = 0; if copy.stage == 'injured' or copy.stage == 'complicated' then copy.stage = 'stabilized' end end
            injuries[id] = copy
        end
    end
    local v = P.Vitals(s, injuries, at, c, 'alert')
    local cause = P.ArrestCause(v, {}, at, c)
    if cause then return false, cause end
    if (v.gcsRaw or v.gcs) <= 8 then
        local toxic = false
        for name in pairs(s.toxins or {}) do if P.ToxinIntensity(s, name, at, c) > 0.5 then toxic = true end end
        if toxic then return false, 'intoxicated' end
        if (v.conditions and v.conditions.headPenalty or 0) > 0 then return false, 'head_injury' end
        return false, 'unresponsive'
    end
    return true
end

--- Resets a loaded patient's physiology for a revive or respawn (reset = 'full' | 'physiology' |
--- 'stabilize' | 'first_aid' | 'none'). Healed injuries become 'recovered' (the store keeps them
--- as history); a stopped bleed leaves the injury 'stabilized'. One audit row lists what changed.
function D.ResetPhysiology(cid, reset, actor)
    if not RESETS[reset] then return nil, 'bad_args' end
    local p = Store.Peek(cid)
    if not p then return nil, 'not_found' end
    if reset == 'none' then return true end
    if not Store.Lock(cid) then return nil, 'busy' end
    local ok, err = pcall(function()
        local at = now()
        local c = P.Cfg(Config.Medical)
        Engine.Touch(p, at)
        resetState(p, reset, c)
        local healed, stopped = {}, {}
        for id, inj in pairs(p.injuries) do
            local action = injuryAction(inj, reset)
            if action == 'recovered' then
                inj.stage, inj.bleed_ml_min, inj.recovered_at = 'recovered', 0, at
                healed[#healed + 1] = id
                Store.MarkDirty(cid, id)
            elseif action == 'stop' then
                inj.bleed_ml_min = 0
                if inj.stage == 'injured' or inj.stage == 'complicated' then inj.stage, inj.stabilized_at = 'stabilized', at end
                stopped[#stopped + 1] = id
                Store.MarkDirty(cid, id)
            end
        end
        if p.ctx then p.ctx.hypoxSince = nil end
        p.updated_at, p.vitals_at = at, nil
        Store.MarkDirty(cid)
        Store.Audit(cid, 'reset', actor, { mode = reset, healed = healed, stopped = stopped })
        Engine.Evaluate(p, at)
        Engine.ActivateIfOnline(p, at)
    end)
    Store.Unlock(cid)
    if not ok then
        print('^1[pf-ambulancejob]^7 physiology reset failed: ' .. tostring(err))
        return nil, 'db_unavailable'
    end
    return true
end

-- ── revives ────────────────────────────────────────────────────────────────────────────────────

-- How each kind of revive ends the down: the reset, the engine transition kind, the EMS request close.
D.Modes = {
    ems       = { kind = 'revive', close = { 'completed', 'revived', true } },
    first_aid = { kind = 'revive', reset = 'first_aid', close = { 'completed', 'revived', true } },
    admin     = { kind = 'revive', reset = 'full', close = { 'cancelled', 'admin_revive', false } },
    script    = { kind = 'revive', reset = 'full', close = { 'cancelled', 'admin_revive', false } },
    respawn   = { kind = 'respawn', reset = 'full', close = { 'cancelled', 'respawned', true } },
    checkin   = { kind = 'revive', reset = 'full', close = { 'cancelled', 'checked_in', true } },
}

local function resetFor(mode)
    if mode == 'ems' then
        local r = cfg().EmsReviveReset
        return RESETS[r] and r or 'stabilize'
    end
    return D.Modes[mode] and D.Modes[mode].reset or 'none'
end
D.ResetFor = resetFor

--- Starts a revive the server decided on: issues a token and asks the client to resurrect.
--- opts = { by = { src, cid, kind }, reason, reset, delay (s, hospital beds), send = false (the
--- caller sends the token itself, e.g. with the hospital bed) }. Returns token.
function D.IssueReviveToken(src, mode, opts)
    opts = opts or {}
    local rec = ensureRec(src)
    if not rec or not D.Modes[mode] then return nil end
    local old = tokenOf[src]
    if old then tokens[old] = nil end
    local token = newToken()
    local delay = math.max(0, num(opts.delay, 0))
    tokens[token] = {
        src = src, cid = rec.cid, mode = mode, reset = opts.reset or resetFor(mode), by = opts.by, reason = opts.reason,
        expires = now() + num(cfg().ReviveTokenSeconds, 20) + delay,
    }
    tokenOf[src] = token
    if opts.send ~= false then
        TriggerClientEvent('pf-ambulancejob:client:Revive', src, token, mode, { health = num(cfg().ReviveHealth, 200) })
    end
    return token
end

--- The pending revive of a player (nil when none): { mode, expires }.
function D.PendingRevive(src)
    local token = tokenOf[src]
    local t = token and tokens[token]
    if not t then return nil end
    return { mode = t.mode, expires = t.expires, token = token }
end

local function commit(t)
    local src, cid = t.src, t.cid
    local Player = getPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= cid then return false end
    local def = D.Modes[t.mode]
    local level, p, rec = D.Level(src)
    local actor = t.by and t.by.src and { src = t.by.src, cid = t.by.cid, kind = t.by.kind } or { kind = 'system', label = t.mode }
    if p then
        local ok, err = D.ResetPhysiology(cid, t.reset, actor)
        if not ok then print(('^3[pf-ambulancejob]^7 revive of %s: reset %s failed (%s)'):format(cid, tostring(t.reset), tostring(err))) end
    end
    rec = rec or recs[src]
    if D.StateOf(level) then
        if rec then rec.upClose = def.close end
        local ok, err = D.SetLevel(src, 'alert', def.kind, t.mode, { actor = actor })
        if not ok and def.kind == 'respawn' then ok, err = D.SetLevel(src, 'alert', 'revive', t.mode, { actor = actor }) end
        if not ok then
            if rec then rec.upClose = nil end
            print(('^3[pf-ambulancejob]^7 revive of %s refused by the engine: %s'):format(cid, tostring(err)))
            D.SendState(src)
            return false
        end
        -- the engine may still hold them below alert (altered): the mirrors follow its level
        if rec and rec.state then D.Apply(src, (D.Level(src))) end
    else
        -- not down (check-in, admin heal): the request a medic or the citizen made is still closed
        if PFEmsRequests and PFEmsRequests.Close and t.mode ~= 'ems' and t.mode ~= 'first_aid' then
            PFEmsRequests.Close(cid, def.close[1], def.close[2], def.close[3])
        end
        D.SendState(src, t.mode)
    end
    if (cfg().ReviveResetsNeeds or {})[t.mode] then
        setMeta(Player, 'hunger', 100)
        setMeta(Player, 'thirst', 100)
        TriggerClientEvent('hud:client:UpdateNeeds', src, 100, 100)
    end
    if firstAid[src] then firstAid[src] = nil end
    emit('patientRevived', src, cid, { cid = t.by and t.by.cid or nil, kind = (t.by and t.by.kind) or t.mode }, t.mode)
    return true
end

--- ReviveApplied(token): the client resurrected; the server re-reads the ped before the patient is up.
function D.ReviveApplied(src, token)
    if type(token) ~= 'string' or #token > 64 then return false end
    if limited(src, 'reviveApplied', 1) then return false end
    local t = tokens[token]
    if not t or t.src ~= src then return false end
    if now() > t.expires then
        tokens[token] = nil
        if tokenOf[src] == token then tokenOf[src] = nil end
        D.SendState(src)
        return false
    end
    if t.verifying then return false end
    t.verifying = true
    Wait(num(cfg().ReviveVerifyMs, 1500))
    t.verifying = nil
    if tokens[token] ~= t then return false end
    local h = healthOf(src)
    if not h or h <= num(cfg().DownHealth, 150) then
        -- the ped did not come back up: still down; the client may answer again until the token expires
        D.stats.refusedRevives = D.stats.refusedRevives + 1
        D.Anomaly(src, 'revive_unverified', { health = h, mode = t.mode })
        D.SendState(src)
        return false
    end
    tokens[token] = nil
    if tokenOf[src] == token then tokenOf[src] = nil end
    return commit(t)
end

--- A medic's revive or a citizen's first aid on a down player (hospital:server:RevivePlayer).
--- Returns true when a revive was started.
function D.RequestRevive(src, targetId)
    if limited(src, 'revive', 1) then return false end
    local target = math.tointeger(tonumber(targetId))
    if not target or target <= 0 or target == src then return false end
    local Helper, Target = getPlayer(src), getPlayer(target)
    if not Helper or not Target then return false end
    if D.IsDown(src) then return false end
    local c = cfg()
    local _, st = D.IsDown(target)
    if not D.StateOf(st) then notify(src, Lang:t('error.cant_help')) return false end
    if D.PlayerDistance(src, target) > num(c.ReviveDistance, 2.5) then notify(src, Lang:t('error.no_player')) return false end
    if tokenOf[target] then notify(src, Lang:t('error.impossible')) return false end
    local mode
    if isOnDutyMedic(Helper) then
        if st == 'dead' and c.EmsReviveDead == false then notify(src, Lang:t('error.cant_help')) return false end
        mode = 'ems'
    elseif Helper.PlayerData.job and Helper.PlayerData.job.name == 'ambulance' then
        notify(src, Lang:t('error.not_ems')) -- an off-duty medic is refused (never banned)
        return false
    else
        -- civilian first aid: only what the server started (UseFirstAid), after its full time,
        -- and only on an unconscious patient
        local fa = firstAid[target]
        if st ~= 'unconscious' then notify(src, Lang:t('error.cant_help')) return false end
        if not fa or fa.helper ~= src or now() < fa.started + fa.duration - 2 then notify(src, Lang:t('error.cant_help')) return false end
        mode = 'first_aid'
    end
    local reset = resetFor(mode)
    local _, p = D.Level(target)
    if p then
        local viable, why = D.Viable(p, reset)
        if not viable then
            notify(src, ('They do not respond: %s. They need more care than this.'):format(tostring(why):gsub('_', ' ')))
            return false
        end
    end
    local item = c.ReviveItem
    if mode == 'first_aid' and not item then item = 'firstaid' end
    if item then
        -- the item goes first (on the server); no item, no revive (and no ban: a race is not cheating)
        local removed = false
        pcall(function() removed = exports['pfm-inventory']:RemoveItem(src, item, 1, false, 'pf-ambulancejob:revive') == true end)
        if not removed then notify(src, Lang:t('error.no_firstaid')) return false end
        local items = exports['pfm-core']:GetShared('Items') or {}
        TriggerClientEvent('qb-inventory:client:ItemBox', src, items[item], 'remove')
    end
    firstAid[target] = nil
    D.IssueReviveToken(target, mode, { by = { src = src, cid = Helper.PlayerData.citizenid, kind = mode == 'ems' and 'ems' or 'civilian' } })
    return true
end

--- A citizen with a first-aid kit starts helping an unconscious player (hospital:server:UseFirstAid).
function D.StartFirstAid(src, targetId)
    if limited(src, 'firstAid', 2) then return false end
    local target = math.tointeger(tonumber(targetId))
    if not target or target <= 0 or target == src then return false end
    local Helper, Target = getPlayer(src), getPlayer(target)
    if not Helper or not Target or D.IsDown(src) then return false end
    local c = cfg()
    local has = false
    pcall(function() has = PFAmbulance.GetCore().Functions.HasItem(src, c.ReviveItem or 'firstaid', 1) == true end)
    if not has then notify(src, Lang:t('error.no_firstaid')) return false end
    if D.PlayerDistance(src, target) > num(c.ReviveDistance, 2.5) then notify(src, Lang:t('error.no_player')) return false end
    local level, p, rec = D.Level(target)
    if level ~= 'unconscious' then notify(src, Lang:t('error.cant_help')) return false end
    local since = (p and p.down_since) or (rec and rec.fallback and rec.fallback.since) or now()
    if now() - since < num(c.FirstAidAfterSeconds, 60) then notify(src, Lang:t('error.cant_help')) return false end
    local fa = firstAid[target]
    if (fa and fa.helper ~= src and now() <= fa.started + fa.duration + 10) or tokenOf[target] then notify(src, Lang:t('error.impossible')) return false end
    if p then
        local viable, why = D.Viable(p, 'first_aid')
        if not viable then notify(src, ('First aid will not wake them (%s): they need a medic.'):format(tostring(why):gsub('_', ' '))) return false end
    end
    local range = type(c.FirstAidSeconds) == 'table' and c.FirstAidSeconds or { 30, 60 }
    local lo, hi = math.floor(num(range[1], 30)), math.floor(num(range[2], 60))
    local duration = math.random(math.min(lo, hi), math.max(lo, hi))
    firstAid[target] = { helper = src, cid = Target.PlayerData.citizenid, started = now(), duration = duration }
    TriggerClientEvent('hospital:client:HelpPerson', src, target, duration * 1000)
    return true
end

--- Admin or script revive (export Revive). opts = { mode = 'admin' | 'script', by, reason,
--- keepInjuries }. The patient may also be up (an admin heal).
function D.Revive(src, opts)
    opts = opts or {}
    local mode = opts.mode == 'script' and 'script' or 'admin'
    local rec = ensureRec(src)
    if not rec then return nil, 'offline' end
    local reset = opts.keepInjuries and 'physiology' or 'full'
    local by = opts.byInfo or { kind = mode }
    local token = D.IssueReviveToken(src, mode, { by = by, reason = opts.reason, reset = reset })
    return token ~= nil
end

--- Admin kill (export Kill): a patient who is up goes down (last stand); one already down dies.
function D.Kill(src, opts)
    opts = opts or {}
    local rec = ensureRec(src)
    if not rec then return nil, 'offline' end
    local level = D.Level(src)
    local st = D.StateOf(level)
    if st == 'dead' then return true end
    if st then return D.SetLevel(src, 'dead', 'laststand', 'admin_kill', { actor = opts.actor }) end
    return D.ForceDown(src, 'admin_kill', { actor = opts.actor, causeInfo = { mechanism = 'admin' } })
end

-- ── respawn (main.lua places the player; this module decides whether they may) ────────────────

--- Whether a player may respawn now. Returns ok, info = { deadAt, canRespawnAt } | nil, error, info.
function D.CanRespawn(src)
    local level, p, rec = D.Level(src)
    if level ~= 'dead' then return nil, 'invalid_state' end
    local f = rec and rec.fallback or {}
    local canAt = (p and p.can_respawn_at) or f.canRespawnAt or 0
    local info = { deadAt = (p and p.dead_at) or f.deadAt or 0, canRespawnAt = canAt }
    if now() < canAt then return nil, 'too_soon', info end
    return true, info
end

-- ── EMS alerts, help, status ───────────────────────────────────────────────────────────────────

local function emsSources()
    local out = {}
    local ok, players = pcall(function() return PFAmbulance.GetCore().Functions.GetQBPlayers() end)
    if not ok or type(players) ~= 'table' then return out end
    for _, v in pairs(players) do
        if isOnDutyMedic(v) then out[#out + 1] = v.PlayerData.source end
    end
    return out
end
D.EmsSources = emsSources

--- Blip alert to on-duty EMS at the player's server position (text built on the server).
function D.AlertEms(src, text)
    local pos = coordsOf(src)
    if not pos then return 0 end
    local list = emsSources()
    for _, ems in ipairs(list) do
        TriggerClientEvent('hospital:client:ambulanceAlert', ems, pos, tostring(text):gsub('%c', ' '):sub(1, 120))
    end
    return #list
end

--- RequestHelp: a down player asks for EMS (blip alert, and the dispatch request if none is open).
function D.RequestHelp(src)
    if not D.IsDown(src) then return false end
    if limited(src, 'help', num(cfg().HelpSeconds, 60)) then return false end
    local _, st = D.IsDown(src)
    D.AlertEms(src, st == 'dead' and Lang:t('info.civ_died') or Lang:t('info.civ_down'))
    if PFEmsRequests and PFEmsRequests.Help then PFEmsRequests.Help(src) end
    return true
end

local LEGACY_LIMB = { head = 'HEAD', neck = 'NECK', torso = 'UPPER_BODY', pelvis = 'LOWER_BODY', arm_l = 'LARM', arm_r = 'RARM', leg_l = 'LLEG', leg_r = 'RLEG' }
local SPINE = { spine_cervical = true, spine_thoracic = true, spine_lumbar = true }
local LIMB_LABEL = { HEAD = 'head', NECK = 'neck', SPINE = 'spine', UPPER_BODY = 'upper_body', LOWER_BODY = 'lower_body',
    LARM = 'left_arm', RARM = 'right_arm', LLEG = 'left_leg', RLEG = 'right_leg' }

--- The engine's open injuries in the shape hospital:GetPlayerStatus always returned:
--- { WEAPONWOUNDS = {}, BLEED = level (when bleeding), [LIMB] = { label, severity 1..4, isDamaged } }.
function D.LegacyStatus(cid)
    local out = { WEAPONWOUNDS = {} }
    local p = Store.Peek(cid)
    if not p then return out end
    local A = PFMed.Anatomy
    for _, inj in pairs(p.injuries or {}) do
        if inj.stage ~= 'recovered' then
            local limb
            if inj.structure and SPINE[inj.structure] then limb = 'SPINE' end
            if not limb then
                local group = (inj.structure and A.Structures[inj.structure] and A.Structures[inj.structure].group)
                    or (inj.region and A.Regions[inj.region] and A.Regions[inj.region].group)
                limb = LEGACY_LIMB[group or '']
            end
            if limb then
                local sev = math.max(1, math.min(4, math.floor(num(inj.severity, 1))))
                local cur = out[limb]
                if not cur or cur.severity < sev then
                    out[limb] = { label = Lang:t('body.' .. LIMB_LABEL[limb]), severity = sev, isDamaged = true }
                end
            end
        end
    end
    local bleed = Engine.BleedLevel(Engine.Bleeding(p, now()).external)
    if bleed > 0 then out.BLEED = bleed end
    return out
end

--- The caller's own visible bleeding level (hospital:GetPlayerBleeding), nil when unknown.
function D.OwnBleeding(src)
    local _, p = D.Level(src)
    if not p then return nil end
    return Engine.BleedLevel(Engine.Bleeding(p, now()).external)
end

-- ── armour (saved from the server ped; the client's SetArmor is ignored) ─────────────────────

function D.SaveArmour(src, Player)
    Player = Player or getPlayer(src)
    local ped = pedOf(src)
    if not Player or not ped or not GetPedArmour then return nil end
    local ok, armour = pcall(GetPedArmour, ped)
    armour = ok and math.tointeger(math.floor(num(armour, -1))) or -1
    if armour < 0 then return nil end
    armour = math.min(100, armour)
    if (Player.PlayerData.metadata or {}).armor ~= armour then setMeta(Player, 'armor', armour) end
    return armour
end

--- Every ArmourSaveSeconds: the armour of everyone online (2 natives per player).
function D.ArmourTick()
    local n = 0
    local ok, players = pcall(function() return PFAmbulance.GetCore().Functions.GetQBPlayers() end)
    if not ok or type(players) ~= 'table' then return 0 end
    for src, Player in pairs(players) do
        local s = tonumber(Player.PlayerData and Player.PlayerData.source) or tonumber(src)
        if s and D.SaveArmour(s, Player) then n = n + 1 end
    end
    return n
end

-- ── net events ─────────────────────────────────────────────────────────────────────────────────

local function netSource()
    local src = tonumber(source)
    if not src or src <= 0 then return nil end
    return math.tointeger(src)
end

RegisterNetEvent('pf-ambulancejob:server:ReportDown', function(payload)
    local src = netSource()
    if not src or limited(src, 'report', 2) then return end
    D.Report(src, payload)
end)

RegisterNetEvent('pf-ambulancejob:server:ReviveApplied', function(token)
    local src = netSource()
    if not src then return end
    D.ReviveApplied(src, token)
end)

RegisterNetEvent('pf-ambulancejob:server:RequestHelp', function()
    local src = netSource()
    if not src then return end
    D.RequestHelp(src)
end)

-- Legacy reports (architecture 9): true counts as a report, false is ignored (only the server ends
-- a down state). Old clients and third-party scripts keep working.
RegisterNetEvent('hospital:server:SetDeathStatus', function(isDead)
    local src = netSource()
    if not src or isDead ~= true or limited(src, 'report', 2) then return end
    D.Report(src, { kind = 'dead' })
end)

RegisterNetEvent('hospital:server:SetLaststandStatus', function(bool)
    local src = netSource()
    if not src or bool ~= true or limited(src, 'report', 2) then return end
    D.Report(src, { kind = 'laststand' })
end)

-- The client asks for its own state after loading (its handlers may have missed the first push).
PFAmbulance.GetCore().Functions.CreateCallback('pf-ambulancejob:server:getDownState', function(source, cb)
    local src = tonumber(source)
    local level = src and D.Level(src) or 'alert'
    cb(D.StateOf(level), src and D.Info(src) or {})
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local pd = type(Player) == 'table' and Player.PlayerData
    local src = pd and tonumber(pd.source)
    if src then D.Sync(src) end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    src = tonumber(src)
    if src then D.Forget(src) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then D.Forget(src) end
end)

if PFMed.Schema then
    PFMed.Schema.OnReady(function()
        -- a resource restart: everyone online gets their state back from the records
        local ok, players = pcall(function() return PFAmbulance.GetCore().Functions.GetQBPlayers() end)
        if ok and type(players) == 'table' then
            for src, Player in pairs(players) do D.Sync(tonumber(Player.PlayerData and Player.PlayerData.source) or tonumber(src)) end
        end
    end)
end

CreateThread(function()
    while true do
        Wait(1000)
        local ok, err = pcall(D.Tick, os.time())
        if not ok then print('^1[pf-ambulancejob]^7 down-state tick failed: ' .. tostring(err)) end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(10, num(cfg().ArmourSaveSeconds, 60)) * 1000)
        pcall(D.ArmourTick)
    end
end)
