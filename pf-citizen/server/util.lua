-- Shared server helpers: players and names, input cleaning, rate limits, pushes and the recipient
-- resolver used by mail and document sharing. Every identity used here is read on the server.

PFCitizen = PFCitizen or {}
local C = PFCitizen

function C.QB() return exports['pfm-core']:GetCoreObject() end

function C.Player(src)
    src = tonumber(src)
    return src and C.QB().Functions.GetPlayer(src) or nil
end

function C.Cid(src)
    local P = C.Player(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

function C.Online(cid)
    if type(cid) ~= 'string' then return nil end
    return C.QB().Functions.GetPlayerByCitizenId(cid)
end

function C.Started(resource) return GetResourceState(resource) == 'started' end

local function charName(ci)
    if type(ci) == 'string' then
        local ok, decoded = pcall(json.decode, ci)
        ci = ok and decoded or nil
    end
    if type(ci) ~= 'table' then return nil end
    local name = (tostring(ci.firstname or '') .. ' ' .. tostring(ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or nil
end

function C.NameOfPlayer(P)
    return P and charName(P.PlayerData.charinfo) or 'Unknown'
end

function C.PhoneOfPlayer(P)
    local ci = P and P.PlayerData.charinfo
    return type(ci) == 'table' and ci.phone and tostring(ci.phone) or nil
end

--- { cid, name, phone } of a citizen, online or not; nil when there is no such citizen.
function C.Citizen(cid)
    if type(cid) ~= 'string' or cid == '' or #cid > 50 then return nil end
    local P = C.Online(cid)
    if P then return { cid = cid, name = C.NameOfPlayer(P), phone = C.PhoneOfPlayer(P), online = true } end
    local row = MySQL.single.await('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid })
    if not row then return nil end
    local ok, ci = pcall(json.decode, row.charinfo or '')
    ci = ok and type(ci) == 'table' and ci or {}
    return { cid = row.citizenid, name = charName(ci) or row.citizenid, phone = ci.phone and tostring(ci.phone) or nil, online = false }
end

function C.IsPhoneNumber(v)
    return type(v) == 'string' and #v >= 3 and #v <= 20 and v:match('^[%d%-]+$') ~= nil
end

--- The citizen holding exactly this phone number (the stock lookups matched any partial number).
function C.CitizenByPhone(number)
    if not C.IsPhoneNumber(number) then return nil end
    local QB = C.QB()
    if QB.Functions.GetPlayerByPhone then
        local P = QB.Functions.GetPlayerByPhone(number)
        if P then return C.Citizen(P.PlayerData.citizenid) end
    end
    local rows = MySQL.query.await('SELECT citizenid FROM players WHERE charinfo LIKE ? LIMIT 2', { '%"phone":"' .. number .. '"%' })
    if rows and rows[1] and not rows[2] then return C.Citizen(rows[1].citizenid) end
    return nil
end

-- ── input ────────────────────────────────────────────────────────────

--- Cuts a string to at most max bytes without splitting a UTF-8 character.
function C.Cut(s, max)
    if #s <= max then return s end
    local cut = max
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end

--- A client string made safe: control characters removed (newlines kept when multiline), trimmed,
--- cut to max. nil when not a string or empty.
function C.Text(v, max, multiline)
    if type(v) ~= 'string' then return nil end
    if multiline then
        v = v:gsub('\r\n?', '\n'):gsub('[\0-\9\11-\31\127]', '')
        v = v:gsub('\n\n\n+', '\n\n')
    else
        v = v:gsub('[%c]', ' ')
    end
    v = v:gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return C.Cut(v, max)
end

function C.Int(v, min, max)
    v = tonumber(v)
    if not v or v ~= v or v % 1 ~= 0 then return nil end
    if (min and v < min) or (max and v > max) then return nil end
    return math.floor(v)
end

--- An id or address token: no spaces or control characters.
function C.Token(v, max)
    if type(v) ~= 'string' or v == '' or #v > (max or 100) or v:find('[%c%s]') then return nil end
    return v
end

function C.LikeEscape(s) return (s:gsub('[\\%%_]', '\\%0')) end

--- Affected rows from an oxmysql update/query result (number or { affectedRows }).
function C.Affected(res)
    if type(res) == 'number' then return res end
    if type(res) == 'table' then return tonumber(res.affectedRows) or 0 end
    return 0
end

-- ── rate limits (token buckets per citizen and action) ───────────────

local buckets = {}

--- True when the action is allowed now (and spends `cost` tokens).
function C.Allow(cid, action, burst, refillSeconds, cost)
    cost = cost or 1
    local key = action .. ':' .. tostring(cid)
    local now = GetGameTimer() / 1000
    local b = buckets[key]
    if not b then b = { tokens = burst, at = now }; buckets[key] = b end
    b.tokens = math.min(burst, b.tokens + (now - b.at) / refillSeconds)
    b.at = now
    if b.tokens < cost then return false end
    b.tokens = b.tokens - cost
    return true
end

function C.__resetLimits() buckets = {} end

-- ── pushes and notifications ────────────────────────────────────────

function C.Push(cid, appId, event, payload)
    if not cid or not C.Started('pf-devices') then return false end
    local ok, res = pcall(function() return exports['pf-devices']:PushToCitizen(cid, appId, event, payload or {}) end)
    return ok and res == true
end

function C.Notify(cid, message, kind)
    local P = C.Online(cid)
    if P then TriggerClientEvent('QBCore:Notify', P.PlayerData.source, message, kind or 'primary') end
end

-- ── businesses (pf-government registry) ─────────────────────────────

function C.Gov() return C.Started('pf-government') and exports['pf-government'] or nil end

function C.GovPermission(src, perms)
    local gov = C.Gov()
    if not gov then return false end
    for _, perm in ipairs(perms) do
        local ok, allowed = pcall(function() return gov:HasPermission(src, perm) end)
        if ok and allowed == true then return true end
    end
    return false
end

function C.Business(businessId)
    if not C.Token(businessId, 100) then return nil end
    local ok, row = pcall(MySQL.single.await, 'SELECT business_id, business_name, owner_id FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })
    return ok and row or nil
end

--- The registered businesses `src` manages (the registry's own ManagesBusiness rule decides).
function C.ManagedBusinesses(src)
    local P = C.Player(src)
    local gov = C.Gov()
    if not P or not gov then return {} end
    local job = P.PlayerData.job or {}
    local jobOwner = job.isboss == true and ('job:' .. tostring(job.name)) or '-'
    local ok, rows = pcall(MySQL.query.await, [[SELECT business_id, business_name, owner_id FROM pf_gov_businesses
        WHERE owner_id = ? OR owner_id = ? OR business_id = ? ORDER BY business_name LIMIT 50]],
        { P.PlayerData.citizenid, jobOwner, 'mechanic:' .. tostring(job.name) })
    local out = {}
    for _, b in ipairs(ok and rows or {}) do
        local okM, manages = pcall(function() return gov:ManagesBusiness(src, b.business_id) end)
        if okM and manages == true then out[#out + 1] = b end
    end
    return out
end

function C.ManagesBusiness(src, businessId)
    local gov = C.Gov()
    if not gov or not C.Token(businessId, 100) then return false end
    local ok, manages = pcall(function() return gov:ManagesBusiness(src, businessId) end)
    return ok and manages == true
end

local staffCache = {}  -- businessId -> { at, list }

--- { { citizenid, role, name } } of a registered business, cached for a minute.
function C.BusinessStaff(businessId)
    local hit = staffCache[businessId]
    if hit and os.time() - hit.at < 60 then return hit.list end
    local gov = C.Gov()
    local list = {}
    if gov then
        local ok, res = pcall(function() return gov:GetBusinessEmployees(businessId) end)
        if ok and type(res) == 'table' and res.ok and type(res.employees) == 'table' then list = res.employees end
    end
    staffCache[businessId] = { at = os.time(), list = list }
    return list
end

function C.__resetStaffCache() staffCache = {} end

--- Owner and bosses of a registered business: the people its mail goes to.
function C.BusinessBosses(businessId)
    local biz = C.Business(businessId)
    if not biz then return nil end
    local seen, out = {}, {}
    local function add(cid) if type(cid) == 'string' and cid ~= '' and not seen[cid] then seen[cid] = true; out[#out + 1] = cid end end
    local owner = tostring(biz.owner_id or '')
    local ownerJob = owner:match('^job:(.+)$')
    if ownerJob then
        -- job-owned shop: every boss of that job
        local ok, rows = pcall(MySQL.query.await, [[SELECT citizenid FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?
            AND JSON_EXTRACT(job, '$.isboss') = 'true' LIMIT 50]], { ownerJob })
        for _, r in ipairs(ok and rows or {}) do add(r.citizenid) end
        for _, P in pairs(C.QB().Functions.GetQBPlayers() or {}) do
            local j = P.PlayerData.job
            if j and j.name == ownerJob and j.isboss then add(P.PlayerData.citizenid) end
        end
    elseif owner ~= '' and owner ~= 'unowned' then
        add(owner)
    end
    for _, e in ipairs(C.BusinessStaff(businessId)) do
        if CitizenConfig.Mail.BossRoles[tostring(e.role or ''):lower()] then add(e.citizenid) end
    end
    return out, biz
end

-- ── recipients ──────────────────────────────────────────────────────

--- Turns what a citizen typed in a To field into a recipient:
---   5551234 / 5551234@ls.mail   the holder of that phone number
---   cid:ABC12345 / ABC12345      that citizen id
---   biz:restaurant:x             the owner and bosses of a registered business
--- Returns { kind = 'person', cid, name } | { kind = 'business', id, name } or nil, error.
function C.ResolveRecipient(token)
    token = C.Token(type(token) == 'string' and token:gsub('^%s+', ''):gsub('%s+$', '') or nil, 120)
    if not token then return nil, 'bad_recipient' end
    local biz = token:match('^biz:(.+)$')
    if biz then
        local row = C.Business(biz)
        if not row then return nil, 'unknown_business' end
        return { kind = 'business', id = row.business_id, name = row.business_name, address = 'biz:' .. row.business_id }
    end
    local localPart, domain = token:match('^([^@]+)@(.+)$')
    if localPart then
        domain = domain:lower()
        -- pf-computer's old addresses were <citizenid>@los-santos.gov
        if domain == 'los-santos.gov' and localPart:match('^%w+$') then
            localPart = 'cid:' .. localPart:upper()
        elseif domain ~= CitizenConfig.Mail.Domain then
            return nil, 'unknown_recipient'
        end
        token = localPart
    end
    local person
    if C.IsPhoneNumber(token) then
        person = C.CitizenByPhone(token)
    else
        local cid = token:match('^cid:(.+)$') or token
        if cid:match('^[%w]+$') then person = C.Citizen(cid) end
    end
    if not person then return nil, 'unknown_recipient' end
    return { kind = 'person', cid = person.cid, name = person.name, address = C.AddressOf(person) }
end

function C.AddressOf(person)
    if person.phone and C.IsPhoneNumber(person.phone) then return person.phone .. '@' .. CitizenConfig.Mail.Domain end
    return 'cid:' .. tostring(person.cid)
end
