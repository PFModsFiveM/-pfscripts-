-- Hospital core: facilities, departments, zones, staffing counts and medical tiers (batch 17E,
-- architecture 2 AJ, 4.5). Shared helpers for the other server/hospital/* modules live here too:
-- validation, per-key locks, rate limits, positions and the audit row (pf_med_events).
--
-- Every distance is measured from the server's ped position; facility, department and bed data
-- come from config_hospital.lua only (the client sends at most a facility id, which is checked).

PFHospital = PFHospital or {}
local H = PFHospital
H.Facility = H.Facility or {}
local F = H.Facility

local function cfg() return Config.Hospital end
H.Cfg = cfg

function H.Now() return os.time() end

local function finite(v)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
H.Finite = finite

--- Integer in [lo, hi] or nil.
function H.Int(v, lo, hi)
    v = finite(v)
    if not v then return nil end
    v = math.tointeger(v)
    if not v or (lo and v < lo) or (hi and v > hi) then return nil end
    return v
end

--- Text without control characters, trimmed, clipped; nil when empty.
function H.Text(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max or 255)
end

--- Idempotency key (architecture 3.3): 1..128 of [%w-_:.].
function H.ValidKey(k)
    return type(k) == 'string' and #k >= 1 and #k <= 128 and not k:find('[^%w%-_:%.]')
end

--- A callable value from another resource (funcrefs are tables): never type(x) == 'function'.
function H.Callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

function H.Started(res)
    local ok, state = pcall(GetResourceState, res)
    return ok and state == 'started'
end

function H.Fail(code, message)
    return { ok = false, error = code, message = message or code }
end

function H.Notify(src, text, kind)
    if src then TriggerClientEvent('QBCore:Notify', src, text, kind or 'primary') end
end

-- ── locks and rate limits (memory; cleared when a player leaves) ──────────────────────────────

local locks = {}
--- Runs fn while holding the named lock. Returns fn's results, or nil, 'busy' when held. A lock is
--- taken before the first database wait of the action it guards (architecture 3.6).
function H.WithLock(name, fn)
    if locks[name] then return nil, 'busy' end
    locks[name] = true
    local res = table.pack(pcall(fn))
    locks[name] = nil
    if not res[1] then
        print(('^1[pf-ambulancejob]^7 hospital action %s failed: %s'):format(name, tostring(res[2])))
        return nil, 'db_unavailable'
    end
    return table.unpack(res, 2, res.n)
end
function H.Locked(name) return locks[name] == true end

local rate = {}
--- true when `src` did `action` less than `seconds` ago (and does not stamp it then).
function H.Limited(src, action, seconds)
    local t = os.time()
    rate[src] = rate[src] or {}
    local last = rate[src][action]
    if last and t - last < seconds then return true end
    rate[src][action] = t
    return false
end
function H.ForgetSource(src) rate[src] = nil end

-- ── players and positions ──────────────────────────────────────────────────────────────────────

function H.Player(src)
    if not src then return nil end
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayer(src) end)
    if ok and type(P) == 'table' and type(P.PlayerData) == 'table' then return P end
    return nil
end

function H.PlayerByCid(cid)
    local ok, P = pcall(function() return exports['pfm-core']:GetPlayerByCitizenId(cid) end)
    if ok and type(P) == 'table' and type(P.PlayerData) == 'table' then return P end
    return nil
end

--- Server id of an online citizen (nil when offline).
function H.SourceOfCid(cid)
    local src = PFMed and PFMed.Store and PFMed.Store.SourceOf(cid)
    if src and H.Player(src) then return src end
    local P = H.PlayerByCid(cid)
    return P and P.PlayerData.source or nil
end

function H.Pos(src)
    local ped = src and GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function H.Dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function H.CharName(P)
    local ci = P and P.PlayerData.charinfo or {}
    local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n or 'Unknown patient'
end

--- One audit row in pf_med_events (written with the medical store's next flush).
function H.Audit(cid, action, actor, detail)
    if PFMed and PFMed.Store and PFMed.Store.Audit then
        PFMed.Store.Audit(cid, ('hosp_%s'):format(action), actor, detail)
    end
end

-- ── facilities ─────────────────────────────────────────────────────────────────────────────────

--- The facility config for an id, a legacy index (1, 2) or nil.
function F.Get(id)
    local c = cfg()
    if type(id) == 'number' then
        local n = math.tointeger(id)
        local key = n and c.Order[n]
        return key and c.Facilities[key] or nil, key
    end
    if type(id) ~= 'string' or #id > 32 then return nil end
    return c.Facilities[id], (c.Facilities[id] and id or nil)
end

--- Normalised facility id (string) for an id or legacy index; nil when unknown.
function F.Id(id)
    local f, key = F.Get(id)
    return f and key or nil
end

function F.Label(id)
    local f = F.Get(id)
    return f and f.label or tostring(id)
end

function F.InZone(pos, zone)
    if not pos or type(zone) ~= 'table' then return false end
    local center = zone.center or zone.coords
    return H.Dist(pos, center) <= (tonumber(zone.radius) or 0)
end

--- The facility id whose building contains the position (nil outside every facility).
function F.At(pos)
    if not pos then return nil end
    local best, bestD
    for id, f in pairs(cfg().Facilities) do
        local d = H.Dist(pos, f.zone.center)
        if d <= f.zone.radius and (not best or d < bestD) then best, bestD = id, d end
    end
    return best
end

--- The facility a player stands in (server position).
function F.Of(src) return F.At(H.Pos(src)) end

function F.InFacility(src, id)
    local f = F.Get(id)
    return f ~= nil and F.InZone(H.Pos(src), f.zone)
end

--- At the facility's reception desk (server position).
function F.AtReception(src, id)
    local f = F.Get(id)
    if not f or not f.reception then return false end
    return H.Dist(H.Pos(src), f.reception.coords) <= (tonumber(f.reception.radius) or 4.0)
end

--- Inside a department's own zone; a department without one counts as the whole facility.
function F.InDepartment(src, id, dept)
    local f = F.Get(id)
    local d = f and f.departments[dept]
    if not d then return false end
    if d.zone then return F.InZone(H.Pos(src), d.zone) end
    return F.InZone(H.Pos(src), f.zone)
end

--- Nearest public facility to a position (by reception, then config order).
function F.Nearest(pos)
    local best, bestD
    for _, id in ipairs(cfg().Order) do
        local f = cfg().Facilities[id]
        if f then
            local d = H.Dist(pos, f.reception and f.reception.coords or f.zone.center)
            if not best or d < bestD then best, bestD = id, d end
        end
    end
    return best or cfg().Order[1]
end

-- ── staff and tiers ────────────────────────────────────────────────────────────────────────────

local function staffJob(P)
    local job = P and P.PlayerData.job
    return type(job) == 'table' and cfg().StaffJobs[job.name] == true and job, job
end

--- On-duty hospital staff (job in StaffJobs, on duty).
function H.IsStaff(P)
    local job = staffJob(P)
    return job ~= false and job ~= nil and job.onduty == true
end

local function players()
    local ok, list = pcall(function() return PFAmbulance.GetCore().Functions.GetQBPlayers() end)
    if ok and type(list) == 'table' then return list end
    return {}
end

--- Number of on-duty staff (server count; the AI threshold reads this).
function H.StaffOnDuty()
    local n = 0
    for _, P in pairs(players()) do if H.IsStaff(P) then n = n + 1 end end
    return n
end

local function hasQual(cid, qual)
    if not H.Started('pf-government') then return nil end
    local ok, has = pcall(function() return exports['pf-government']:HasQualification(cid, qual) end)
    if not ok then return nil end
    return has == true
end

local function gradeOf(P)
    local job = P.PlayerData.job or {}
    local g = job.grade
    if type(g) == 'table' then g = g.level end
    return tonumber(g) or 0
end

--- Medical tier 0..5 of an on-duty staff member (0 for anyone else). Qualifications from
--- pf-government (granted or implied by grade); the grade map when pf-government is not running.
function H.Tier(P)
    if not H.IsStaff(P) then return 0 end
    local t = cfg().Tiers
    local usedQuals = false
    for _, pair in ipairs(t.Quals) do
        local has = hasQual(P.PlayerData.citizenid, pair[1])
        if has == nil then break end
        usedQuals = true
        if has then return pair[2] end
    end
    if usedQuals then return 0 end
    return t.GradeFallback[gradeOf(P)] or 1
end

function H.IsSurgeon(P)
    if not H.IsStaff(P) then return false end
    local has = hasQual(P.PlayerData.citizenid, cfg().Tiers.SurgeonQual)
    if has ~= nil then return has end
    return gradeOf(P) >= (cfg().Tiers.SurgeonGradeFallback or 3)
end

--- Whether any on-duty surgeon is online.
function H.SurgeonOnDuty()
    for _, P in pairs(players()) do
        if H.IsSurgeon(P) then return true end
    end
    return false
end

--- Who acts, for the audit and the bill: { src, cid, job, kind }.
function H.ActorOf(src, P)
    P = P or H.Player(src)
    if not P then return { kind = 'system', label = 'hospital' } end
    local job = P.PlayerData.job
    return { src = src, cid = P.PlayerData.citizenid, job = type(job) == 'table' and job.name or nil, kind = 'player' }
end

--- Checks a provider for a hospital action: online, on duty, tier >= minTier, inside the facility.
--- Returns P, tier | nil, error code, message.
function H.Provider(src, facilityId, minTier)
    local P = H.Player(src)
    if not P then return nil, 'offline', 'You are not loaded.' end
    local job = P.PlayerData.job or {}
    if not cfg().StaffJobs[job.name] then return nil, 'no_permission', 'Only hospital staff can do that.' end
    if job.onduty ~= true then return nil, 'not_on_duty', 'You are off duty.' end
    local tier = H.Tier(P)
    if tier < minTier then return nil, 'no_permission', 'That is outside your scope of practice.' end
    if facilityId and not F.InFacility(src, facilityId) then return nil, 'too_far', 'You must be in the hospital.' end
    return P, tier
end

--- GetStaffTier(src): { ok, staff, tier, surgeon } of a player, read on the server (on-duty hospital
--- staff only; anyone else is staff = false, tier 0). Allowlisted (Services.Callers.GetStaffTier).
function H.StaffTierOf(src)
    src = H.Int(src, 1, 65535)
    if not src then return H.Fail('bad_args', 'Invalid player.') end
    local P = H.Player(src)
    if not P then return H.Fail('offline', 'Not online.') end
    local staff = H.IsStaff(P)
    return { ok = true, staff = staff, tier = staff and H.Tier(P) or 0, surgeon = staff and H.IsSurgeon(P) or false }
end

exports('GetStaffTier', function(src)
    if not (H.ServiceAllowed and H.ServiceAllowed('GetStaffTier')) then return H.Fail('not_allowed', 'Not allowed.') end
    return H.StaffTierOf(src)
end)

-- ── status (export GetHospitalStatus) ──────────────────────────────────────────────────────────

--- { ok, beds = { [dept] = { total, free } }, staffOnDuty, aiActive } for a facility.
function F.Status(id)
    local f, key = F.Get(id)
    if not f then return H.Fail('not_found', 'Unknown hospital.') end
    local beds = {}
    for dept, d in pairs(f.departments) do
        local total, free = #d.beds, 0
        for _, b in ipairs(d.beds) do if not H.Beds.Occupant(key, b.id) then free = free + 1 end end
        beds[dept] = { total = total, free = free }
    end
    local staff = H.StaffOnDuty()
    return { ok = true, hospitalId = key, label = f.label, beds = beds, staffOnDuty = staff, aiActive = staff < (cfg().AI.MinStaff or 2) }
end
