-- Medical engine exports (architecture 4.1, batch 15): GetPatientSummary, IsDown, ApplyInjury,
-- AddToxin; plus the pfm-smallresources consumption listener that turns alcohol and poisoned food
-- into toxins. Every export checks the invoking resource against Config.Medical.Callers, and the
-- summary is filtered per caller (Config.Medical.SummaryFields): police, prison and courts see only
-- whether someone is down, their level of consciousness, their stage and their restrictions.

PFMed = PFMed or {}
PFMed.Api = PFMed.Api or {}
local Api = PFMed.Api
local Store, Engine = PFMed.Store, PFMed.Engine

local MESSAGES = {
    bad_args = 'Invalid request.',
    not_allowed = 'This resource may not use the medical engine.',
    no_permission = 'Not permitted.',
    not_found = 'Patient not found.',
    offline = 'The patient is not online.',
    busy = 'The patient record is busy; try again.',
    key_reused = 'That key was already used for a different request.',
    conflict = 'The patient record is full.',
    db_unavailable = 'Medical records are unavailable right now.',
}

local function fail(code, message)
    return { ok = false, error = code, message = message or MESSAGES[code] or code }
end

-- ── caller allowlist ───────────────────────────────────────────────────────────────────────────

local refusedLog = {}   -- [resource] = last time a refusal was printed (one line per minute)

--- Returns allowed, invoker. The resource itself (no invoker) always passes.
function Api.Allowed(name)
    local invoker = GetInvokingResource()
    if invoker == nil or invoker == GetCurrentResourceName() then return true, nil end
    local list = Config.Medical.Callers and Config.Medical.Callers[name]
    if list == '*' or (type(list) == 'table' and list[invoker] == true) then return true, invoker end
    local t = os.time()
    if (refusedLog[invoker] or 0) + 60 <= t then
        refusedLog[invoker] = t
        print(('^3[pf-ambulancejob]^7 %s refused for resource %s (not in Config.Medical.Callers)'):format(name, invoker))
    end
    return false, invoker
end

-- ── who / actor ────────────────────────────────────────────────────────────────────────────────

local function playerOf(src)
    local ok, Player = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(Player) == 'table' and type(Player.PlayerData) == 'table' then return Player end
    return nil
end

--- cid, src (nil when offline) for a server id or a citizen id. Nothing for a bad value, and for
--- a server id nobody uses (then the second value is 'not_found').
function Api.Resolve(who)
    if type(who) == 'number' then
        local src = math.tointeger(who)
        if not src or src <= 0 then return nil end
        local cid = Store.CidOf(src)
        if cid then return cid, src end
        local Player = playerOf(src)
        cid = Player and Player.PlayerData.citizenid
        if not Store.ValidCitizenId(cid) then return nil, 'not_found' end
        -- online but not loaded yet (e.g. the tables were not ready when they joined)
        if Store.Ready() then Store.OnPlayerLoaded(src, cid) end
        return cid, src
    elseif type(who) == 'string' then
        if not Store.ValidCitizenId(who) then return nil end
        return who, Store.SourceOf(who)
    end
    return nil
end

--- Who acts (architecture 3.5): nothing from opts.actor is trusted except the server id, whose
--- citizen id and job are read from pfm-core. Returns actor or nil, error code.
function Api.Actor(actor, invoker)
    if actor == nil then return { kind = 'resource', label = invoker } end
    if type(actor) ~= 'table' then return nil, 'bad_args' end
    if actor.src ~= nil then
        local src = math.tointeger(tonumber(actor.src))
        if not src or src <= 0 then return nil, 'bad_args' end
        local Player = playerOf(src)
        if not Player then return nil, 'offline' end
        local admin = actor.kind == 'admin'
        if admin and not IsPlayerAceAllowed(src, Config.Medical.AdminAce or 'admin') then return nil, 'no_permission' end
        local pd = Player.PlayerData
        return { src = src, cid = pd.citizenid, job = type(pd.job) == 'table' and pd.job.name or nil, kind = admin and 'admin' or 'player', label = invoker }
    end
    if actor.kind == 'system' then
        local label = type(actor.label) == 'string' and actor.label:gsub('%c', ''):sub(1, 64) or invoker
        return { kind = 'system', label = label }
    end
    return nil, 'bad_args'
end

-- ── GetPatientSummary ──────────────────────────────────────────────────────────────────────────

local ALL_FIELDS = { 'consciousness', 'down', 'stage', 'bleeding', 'triage', 'vitals', 'restrictions', 'updatedAt' }

--- Full summary of a patient object (no filtering).
function Api.Summary(p, at)
    at = at or os.time()
    local v = Engine.Vitals(p, at)
    local restrictions = PFMed.Effects.Restrictions(p, at)
    local level = p.consciousness
    return {
        ok = true, cid = p.cid, online = p.src ~= nil,
        consciousness = level, down = level == 'unconscious' or level == 'arrest' or level == 'dead',
        stage = Engine.StageOf(p),
        bleeding = Engine.BleedLevel(Engine.Bleeding(p, at).external),   -- visible bleeding only
        triage = p.triage,
        vitals = { hr = v.hr, sbp = v.sbp, dbp = v.dbp, rr = v.rr, spo2 = v.spo2, temp = v.temp, gcs = v.gcs, pain = v.pain },
        restrictions = restrictions,
        updatedAt = p.updated_at,
    }
end

--- The fields a caller receives (nil invoker: all).
function Api.FilterSummary(full, invoker)
    if invoker == nil then return full end
    local spec = Config.Medical.SummaryFields and Config.Medical.SummaryFields[invoker]
    if spec == 'all' then return full end
    if type(spec) ~= 'table' then spec = Config.Medical.NonMedicalSummaryFields or { 'down', 'consciousness', 'stage', 'restrictions' } end
    local out = { ok = full.ok, cid = full.cid, online = full.online }
    local allowedField = {}
    for _, f in ipairs(ALL_FIELDS) do allowedField[f] = true end
    for _, f in ipairs(spec) do
        if allowedField[f] then out[f] = full[f] end
    end
    return out
end

function Api.GetPatientSummary(who)
    local ok, invoker = Api.Allowed('GetPatientSummary')
    if not ok then return fail('not_allowed') end
    local cid, why = Api.Resolve(who)
    if not cid then return fail(why == 'not_found' and 'not_found' or 'bad_args') end
    local p = Store.Peek(cid)
    if not p then
        local err
        p, err = Store.Get(cid)
        if not p then return fail(err or 'not_found') end
    end
    return Api.FilterSummary(Api.Summary(p, os.time()), invoker)
end

-- ── IsDown ─────────────────────────────────────────────────────────────────────────────────────

--- down:boolean, level:string. Memory only: a citizen who is not loaded reads false, 'unknown'.
function Api.IsDown(who)
    local ok = Api.Allowed('IsDown')
    if not ok then return false, 'not_allowed' end
    local cid
    if type(who) == 'number' then cid = Store.CidOf(math.tointeger(who) or -1)
    elseif Store.ValidCitizenId(who) then cid = who end
    if not cid then return false, 'unknown' end
    return Engine.IsDown(cid)
end

-- ── ApplyInjury ────────────────────────────────────────────────────────────────────────────────

--- spec = { mechanism, type, subtype?, region?, structure?, severity 1..5, attrs?, note?, attackerCid? },
--- opts = { key (required), actor }. The patient must be online.
function Api.ApplyInjury(who, spec, opts)
    local ok, invoker = Api.Allowed('ApplyInjury')
    if not ok then return fail('not_allowed') end
    if type(opts) ~= 'table' or not Engine.ValidKey(opts.key) then return fail('bad_args', 'opts.key is required (1-128 of [A-Za-z0-9-_:.]).') end
    local actor, aerr = Api.Actor(opts.actor, invoker)
    if not actor then return fail(aerr) end
    local cid, src = Api.Resolve(who)
    if not cid then return fail(src == 'not_found' and 'offline' or 'bad_args') end
    if not src then return fail('offline') end
    local inj, code, extra = Engine.AddInjury(cid, spec, { key = opts.key, actor = actor, source = 'export', invoker = invoker })
    if not inj then return fail(code, type(extra) == 'string' and extra or nil) end
    return { ok = true, injuryId = inj.id, duplicate = extra == true or nil }
end

-- ── AddToxin ───────────────────────────────────────────────────────────────────────────────────

local toxinKeys = {}        -- [key] = { fp, at } for a repeat with the same key (1 hour)
local TOXIN_KEY_TTL = 3600

local function pruneToxinKeys(at)
    for k, v in pairs(toxinKeys) do if at - v.at > TOXIN_KEY_TTL then toxinKeys[k] = nil end end
end

--- toxin in Config.Medical.Toxins (see config_medical.lua for units); opts = { key?, actor }.
function Api.AddToxin(who, toxin, amount, opts)
    local ok, invoker = Api.Allowed('AddToxin')
    if not ok then return fail('not_allowed') end
    opts = opts or {}
    if type(opts) ~= 'table' then return fail('bad_args') end
    if opts.key ~= nil and not Engine.ValidKey(opts.key) then return fail('bad_args', 'Bad idempotency key.') end
    local actor, aerr = Api.Actor(opts.actor, invoker)
    if not actor then return fail(aerr) end
    local cid, src = Api.Resolve(who)
    if not cid then return fail(src == 'not_found' and 'offline' or 'bad_args') end
    if not src then return fail('offline') end
    local at = os.time()
    local fp = table.concat({ cid, tostring(toxin), tostring(amount) }, '|')
    if opts.key then
        pruneToxinKeys(at)
        local seen = toxinKeys[opts.key]
        if seen then
            if seen.fp ~= fp then return fail('key_reused') end
            return { ok = true, duplicate = true }
        end
    end
    local level, code, msg = Engine.AddToxin(cid, toxin, amount, { actor = actor, source = 'export', invoker = invoker })
    if not level then return fail(code, msg) end
    if opts.key then toxinKeys[opts.key] = { fp = fp, at = at } end
    return { ok = true }
end

-- ── consumables (pfm-smallresources, batch 15H) ───────────────────────────────────────────────

--- An item was consumed (pfm-smallresources raises this after it removed the item on the server).
function Api.OnConsumed(src, itemName, kind, info)
    src = math.tointeger(tonumber(src))
    if not src or src <= 0 then return nil end
    if type(itemName) ~= 'string' or itemName == '' or #itemName > 64 then return nil end
    local cid, online = Api.Resolve(src)
    if not cid or type(online) ~= 'number' then return nil end
    local c = Config.Medical.Consumables or {}
    local actor = { src = src, cid = cid }
    if kind == 'alcohol' then
        local dose = tonumber(c.Alcohol and c.Alcohol[itemName]) or tonumber(c.AlcoholDefault) or 0.03
        return Engine.AddToxin(cid, 'ethanol', dose, { actor = actor, source = 'consumed:' .. itemName })
    end
    if (kind == 'food' or kind == 'drink') and type(info) == 'table' and info.poisoned == true then
        return Engine.AddToxin(cid, 'food_poisoning', tonumber(c.FoodPoisoningDose) or 0.6, { actor = actor, source = 'consumed:' .. itemName })
    end
    return nil
end

-- server-only (AddEventHandler): a client cannot raise it; a call with a player source is ignored
AddEventHandler('pfm-smallresources:server:consumed', function(src, itemName, kind, info)
    local s = tonumber(source)
    if s and s > 0 then return end
    Api.OnConsumed(src, itemName, kind, info)
end)

-- ── Revive / Kill (batch 16A: admin and script paths; medical revives go through EMS) ───────

local reviveKeys = {}       -- [key] = { fp, at, result } for a repeat with the same key (1 hour)

--- opts.by (a server id) acting as an admin needs one of Config.Medical.AdminAces. Returns the
--- by-info or nil, error code.
local function adminBy(by)
    if by == nil then return {} end
    local src = math.tointeger(tonumber(by))
    if not src or src <= 0 then return nil, 'bad_args' end
    local Player = playerOf(src)
    if not Player then return nil, 'offline' end
    local aces = Config.Medical.AdminAces or { Config.Medical.AdminAce or 'admin' }
    if type(aces) == 'string' then aces = { aces } end
    for _, ace in ipairs(aces) do
        if IsPlayerAceAllowed(src, ace) then return { src = src, cid = Player.PlayerData.citizenid, kind = 'admin' } end
    end
    return nil, 'no_permission'
end

local function onlineTarget(who)
    local cid, src = Api.Resolve(who)
    if not cid then return nil, src == 'not_found' and 'offline' or 'bad_args' end
    if not src then return nil, 'offline' end
    return src
end

--- who = server id or citizenid (online); opts = { mode = 'admin' | 'script', by = src?, reason,
--- key?, keepInjuries = false }. The patient's client answers a revive token; the patient is up
--- once the server read the ped back up (result.pending = true until then).
function Api.Revive(who, opts)
    local ok = Api.Allowed('Revive')
    if not ok then return fail('not_allowed') end
    opts = opts or {}
    if type(opts) ~= 'table' then return fail('bad_args') end
    if opts.key ~= nil and not Engine.ValidKey(opts.key) then return fail('bad_args', 'Bad idempotency key.') end
    local by, berr = adminBy(opts.by)
    if not by then return fail(berr) end
    local src, terr = onlineTarget(who)
    if not src then return fail(terr) end
    local at = os.time()
    local fp = table.concat({ tostring(src), tostring(opts.mode), tostring(opts.keepInjuries == true) }, '|')
    if opts.key then
        for k, v in pairs(reviveKeys) do if at - v.at > 3600 then reviveKeys[k] = nil end end
        local seen = reviveKeys[opts.key]
        if seen then
            if seen.fp ~= fp then return fail('key_reused') end
            return { ok = true, pending = true, duplicate = true }
        end
    end
    by.kind = by.kind or (opts.mode == 'script' and 'script' or 'admin')
    local reason = type(opts.reason) == 'string' and opts.reason:gsub('%c', ''):sub(1, 64) or nil
    if not PFMed.Down.Revive(src, { mode = opts.mode == 'script' and 'script' or 'admin', byInfo = by, reason = reason, keepInjuries = opts.keepInjuries == true }) then
        return fail('offline')
    end
    if opts.key then reviveKeys[opts.key] = { fp = fp, at = at } end
    return { ok = true, pending = true }
end

--- who = server id or citizenid (online); opts = { by = src?, reason }. Up -> down (last stand);
--- already down -> dead.
function Api.Kill(who, opts)
    local ok = Api.Allowed('Kill')
    if not ok then return fail('not_allowed') end
    opts = opts or {}
    if type(opts) ~= 'table' then return fail('bad_args') end
    local by, berr = adminBy(opts.by)
    if not by then return fail(berr) end
    local src, terr = onlineTarget(who)
    if not src then return fail(terr) end
    local done, err = PFMed.Down.Kill(src, { actor = by.src and by or { kind = 'system', label = 'kill' } })
    if not done then return fail(err == 'invalid_state' and 'invalid_state' or (err or 'offline')) end
    return { ok = true }
end

exports('Revive', function(who, opts) return Api.Revive(who, opts) end)
exports('Kill', function(who, opts) return Api.Kill(who, opts) end)
exports('GetPatientSummary', function(who) return Api.GetPatientSummary(who) end)
exports('IsDown', function(who) return Api.IsDown(who) end)
exports('ApplyInjury', function(who, spec, opts) return Api.ApplyInjury(who, spec, opts) end)
exports('AddToxin', function(who, toxin, amount, opts) return Api.AddToxin(who, toxin, amount, opts) end)
