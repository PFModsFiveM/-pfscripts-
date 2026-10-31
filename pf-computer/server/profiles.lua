-- Per-character computer state kept on the server (pf_computer_profiles, main.lua migration 3):
-- the desktop layout and the lock screen of each character on each computer. Both used to live
-- only in the browser cache of the player's game client, so a reinstall lost them and anyone could
-- edit the cache to read the PIN or skip the lock. The page keeps a copy of the layout as a cache
-- only; it never receives a PIN or password.
--
-- `scope` is the computer the page runs on (client/main.lua BuildComputerStateKey). It only names the
-- character's own row, so it is validated for shape and the number of rows per character is capped.
--
-- The lock screen: PIN, password and lockdown password are stored as salted SHA-256 hashes and
-- checked here; failed attempts, their timeouts, breach failures and the lockdown timer are counted
-- here, so clearing the browser cache resets nothing. Settings cannot be changed while locked.

local C = PFComputer
local handlers = C.handlers
local DB = C.DB

local MAX_SCOPES = 30            -- computers remembered per character (oldest forgotten first)
local MAX_ITEMS, MAX_FOLDERS = 150, 50
local MAX_ATTEMPTS = 5
local TIMEOUTS = { 10, 30, 60, 600, 1800 }   -- seconds locked out after the 1st..5th wrong try

local ACTIONS = {
    'profile:get', 'profile:layout:save', 'profile:layout:reset',
    'security:lock:state', 'security:lock:settings', 'security:lock:lock', 'security:lock:unlock',
    'security:lock:breach', 'security:lock:exitLockdown', 'security:lock:reset',
}
for _, name in ipairs(ACTIONS) do C.WRITE_ACTIONS[name] = true end   -- they need the tables

-- ── SHA-256 (Lua 5.3+ integers; also correct with 32-bit integers) ───────────────
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local M32 = 0xffffffff

local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & M32 end

local function sha256(msg)
    local len = #msg
    local bits = len * 8
    msg = msg .. '\128' .. string.rep('\0', (55 - len) % 64)
        .. string.char(0, 0, 0, 0, (bits >> 24) & 0xff, (bits >> 16) & 0xff, (bits >> 8) & 0xff, bits & 0xff)
    local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    local w = {}
    for chunk = 1, #msg, 64 do
        for i = 0, 15 do
            local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
            w[i] = ((a << 24) | (b << 16) | (c << 8) | d) & M32
        end
        for i = 16, 63 do
            local x, y = w[i - 15], w[i - 2]
            local s0 = rrot(x, 7) ~ rrot(x, 18) ~ (x >> 3)
            local s1 = rrot(y, 17) ~ rrot(y, 19) ~ (y >> 10)
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & M32
        end
        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for i = 0, 63 do
            local S1 = rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)
            local ch = (e & f) ~ ((~e) & g)
            local t1 = (h + S1 + ch + K[i + 1] + w[i]) & M32
            local S0 = rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local t2 = (S0 + maj) & M32
            h, g, f, e, d, c, b, a = g, f, e, (d + t1) & M32, c, b, a, (t1 + t2) & M32
        end
        H[1], H[2], H[3], H[4] = (H[1] + a) & M32, (H[2] + b) & M32, (H[3] + c) & M32, (H[4] + d) & M32
        H[5], H[6], H[7], H[8] = (H[5] + e) & M32, (H[6] + f) & M32, (H[7] + g) & M32, (H[8] + h) & M32
    end
    local out = {}
    for i = 1, 8 do
        local v = H[i]
        out[i] = ('%02x%02x%02x%02x'):format((v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff)
    end
    return table.concat(out)
end
C.sha256 = sha256

local function newSalt()
    local parts = {}
    for i = 1, 4 do parts[i] = ('%08x'):format(math.random(0, 0x7fffffff)) end
    return table.concat(parts)
end

local function secretHash(rec, secret) return sha256(rec.salt .. ':' .. secret) end

-- ── storage ──────────────────────────────────────────────────────────────────
local memory = {}   -- [cid|scope] = { layout, security } when there is no database (test harness)

local function cleanScope(v)
    if v == nil then return 'default' end
    if type(v) ~= 'string' or v == '' or #v > 160 or not v:match('^[%w:%.,%-_]+$') then return nil end
    return v
end

local function loadRow(cid, scope)
    if DB.mode == 'memory' then
        local m = memory[cid .. '|' .. scope]
        return m and m.layout, m and m.security
    end
    local row = MySQL.single.await('SELECT layout, security FROM pf_computer_profiles WHERE citizenid = ? AND scope = ? LIMIT 1', { cid, scope })
    if type(row) ~= 'table' then return nil, nil end
    return C.decodeJson(row.layout, nil), C.decodeJson(row.security, nil)
end

--- Writes one column (layout or security) of the character's row; nil clears it.
local function saveColumn(cid, scope, column, value)
    if DB.mode == 'memory' then
        local key = cid .. '|' .. scope
        memory[key] = memory[key] or {}
        memory[key][column] = value
        return true
    end
    local encoded = value ~= nil and json.encode(value) or nil
    MySQL.query.await(('INSERT INTO pf_computer_profiles (citizenid, scope, `%s`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `%s` = VALUES(`%s`)')
        :format(column, column, column), { cid, scope, encoded })
    -- forget the computers this character has not used for longest
    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM pf_computer_profiles WHERE citizenid = ?', { cid })) or 0
    if count > MAX_SCOPES then
        MySQL.query.await(('DELETE FROM pf_computer_profiles WHERE citizenid = ? AND scope <> ? ORDER BY updated_at ASC LIMIT %d'):format(count - MAX_SCOPES),
            { cid, scope })
    end
    return true
end

local function who(src, payload)
    local cid = C.citizenId(src)
    if not cid then return nil, nil, { ok = false, error = 'no_identifier' } end
    local scope = cleanScope(payload.scope)
    if not scope then return nil, nil, { ok = false, error = 'bad_scope' } end
    return cid, scope
end

-- ── the desktop layout ───────────────────────────────────────────────────────
local ID_PATTERN = '^[%w_%-:%.]+$'

local function token(v, max)
    if type(v) == 'number' then v = tostring(math.floor(v)) end
    if type(v) ~= 'string' or v == '' or #v > max or not v:match(ID_PATTERN) then return nil end
    return v
end

local function label(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('%c', ' '):sub(1, max)
    return v ~= '' and v or nil
end

local function position(p)
    if type(p) ~= 'table' then return { x = 0, y = 0 } end
    local x, y = math.floor(tonumber(p.x) or 0), math.floor(tonumber(p.y) or 0)
    return { x = math.max(0, math.min(199, x)), y = math.max(0, math.min(199, y)) }
end

--- Only the fields the desktop uses, with bounded values; anything else is dropped.
local function cleanLayout(items, folders)
    local out = { items = {}, folders = {} }
    for _, it in ipairs(type(items) == 'table' and items or {}) do
        if #out.items >= MAX_ITEMS then break end
        local id = type(it) == 'table' and token(it.id, 64)
        local kind = type(it) == 'table' and (it.type == 'document' and 'document' or (it.type == nil or it.type == 'app') and 'app' or nil)
        if id and kind then
            out.items[#out.items + 1] = {
                id = id, type = kind, app = token(it.app, 64), location = token(it.location, 64) or 'desktop',
                position = position(it.position), documentId = token(it.documentId, 64), title = label(it.title, 80),
                created = label(it.created, 40),
            }
        end
    end
    for _, f in ipairs(type(folders) == 'table' and folders or {}) do
        if #out.folders >= MAX_FOLDERS then break end
        local id = type(f) == 'table' and token(f.id, 64)
        if id then
            out.folders[#out.folders + 1] = {
                id = id, name = label(f.name, 60) or 'New Folder', location = token(f.location, 64) or 'desktop',
                position = position(f.position), created = label(f.created, 40),
            }
        end
    end
    return out
end

-- ── the lock screen ──────────────────────────────────────────────────────────
local function defaults()
    local d = (Config.Security and Config.Security.Default) or {}
    return {
        enabled = false, method = 'pin', salt = newSalt(), lockWallpaper = '',
        lockdownOnHackFail = false, lockdownThreshold = math.floor(tonumber(d.maxHackFailuresBeforeLockdown) or 3),
        locked = false, fails = 0, timeoutUntil = 0, lockdownUntil = 0, hackFailures = 0,
    }
end

local function normalizeSecurity(rec)
    local out = defaults()
    if type(rec) ~= 'table' then return out end
    for k, v in pairs(rec) do out[k] = v end
    if type(out.salt) ~= 'string' or #out.salt < 16 then out.salt = newSalt() end
    out.fails = math.floor(tonumber(out.fails) or 0)
    out.timeoutUntil = tonumber(out.timeoutUntil) or 0
    out.lockdownUntil = tonumber(out.lockdownUntil) or 0
    out.hackFailures = math.floor(tonumber(out.hackFailures) or 0)
    return out
end

local function methodAllowed(method)
    local d = (Config.Security and Config.Security.Default) or {}
    if method == 'pin' then return d.allowPin ~= false end
    if method == 'password' then return d.allowPassword ~= false end
    if method == 'fingerprint' then return d.allowFingerprint ~= false end
    return false
end

--- What the page may know: never a hash or the salt.
local function publicSecurity(rec)
    local now = os.time()
    return {
        enabled = rec.enabled == true, method = rec.method, lockWallpaper = rec.lockWallpaper or '',
        hasPin = rec.pin ~= nil, hasPassword = rec.password ~= nil, hasLockdownPassword = rec.lockdownPassword ~= nil,
        lockdownOnHackFail = rec.lockdownOnHackFail == true, lockdownThreshold = rec.lockdownThreshold,
        locked = rec.enabled == true and rec.locked == true,
        fails = rec.fails, attemptsLeft = math.max(0, MAX_ATTEMPTS - rec.fails),
        timeoutRemaining = math.max(0, rec.timeoutUntil - now), lockdownRemaining = math.max(0, rec.lockdownUntil - now),
        hackFailures = rec.hackFailures,
        methods = { pin = methodAllowed('pin'), password = methodAllowed('password'), fingerprint = methodAllowed('fingerprint') },
    }
end

local function loadSecurity(cid, scope)
    local _, sec = loadRow(cid, scope)
    return normalizeSecurity(sec)
end

local function saveSecurity(cid, scope, rec) return saveColumn(cid, scope, 'security', rec) end

local function unlocked(cid, scope, rec)
    rec.locked, rec.fails, rec.timeoutUntil, rec.hackFailures, rec.lockdownUntil = false, 0, 0, 0, 0
    saveSecurity(cid, scope, rec)
    return { ok = true, security = publicSecurity(rec) }
end

local function wrongSecret(cid, scope, rec, error)
    rec.fails = math.min(rec.fails + 1, MAX_ATTEMPTS)
    rec.timeoutUntil = os.time() + TIMEOUTS[rec.fails]
    saveSecurity(cid, scope, rec)
    return { ok = false, error = error or 'wrong_secret', security = publicSecurity(rec) }
end

local function blocked(rec)
    local now = os.time()
    if rec.lockdownUntil > now then return { ok = false, error = 'lockdown', security = publicSecurity(rec) } end
    if rec.timeoutUntil > now then return { ok = false, error = 'timeout', security = publicSecurity(rec) } end
    return nil
end

local function validPin(v) return type(v) == 'string' and v:match('^%d%d%d%d%d?%d?%d?%d?$') ~= nil end
local function validPassword(v) return type(v) == 'string' and #v >= 4 and #v <= 64 and not v:find('%c') end

local function validWallpaper(v)
    if v == '' then return true end
    if type(v) ~= 'string' or #v > 300 then return false end
    -- an image address or one of the computer's own wallpapers; no quotes or brackets (used in CSS url())
    return v:match("^https://[%w%-%._~:/%?#@!%$&%*%+,;=%%]+$") ~= nil or v:match('^assets/[%w%-_%./]+$') ~= nil
end

-- ── handlers ─────────────────────────────────────────────────────────────────
handlers['profile:get'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    local layout, sec = loadRow(cid, scope)
    return { ok = true, layout = layout, security = publicSecurity(normalizeSecurity(sec)) }
end

handlers['profile:layout:save'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    if type(payload.items) ~= 'table' then return { ok = false, error = 'bad_layout' } end
    saveColumn(cid, scope, 'layout', cleanLayout(payload.items, payload.folders))
    return { ok = true }
end

handlers['profile:layout:reset'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    saveColumn(cid, scope, 'layout', nil)
    return { ok = true }
end

handlers['security:lock:state'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    return { ok = true, security = publicSecurity(loadSecurity(cid, scope)) }
end

--- Changes the lock screen settings. Missing fields stay as they are; a PIN or password is only
--- ever set, never sent back. Refused while the lock screen is locked.
handlers['security:lock:settings'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    local rec = loadSecurity(cid, scope)
    if rec.enabled and rec.locked then return { ok = false, error = 'locked' } end
    if payload.enabled ~= nil and type(payload.enabled) ~= 'boolean' then return { ok = false, error = 'bad_request' } end
    if payload.method ~= nil and not methodAllowed(payload.method) then return { ok = false, error = 'bad_method' } end
    if payload.pin ~= nil and payload.pin ~= '' and not validPin(payload.pin) then return { ok = false, error = 'bad_pin' } end
    if payload.password ~= nil and payload.password ~= '' and not validPassword(payload.password) then return { ok = false, error = 'bad_password' } end
    if payload.lockdownPassword ~= nil and payload.lockdownPassword ~= '' and not validPassword(payload.lockdownPassword) then return { ok = false, error = 'bad_password' } end
    if payload.lockWallpaper ~= nil and not validWallpaper(payload.lockWallpaper) then return { ok = false, error = 'bad_wallpaper' } end
    local threshold = payload.lockdownThreshold ~= nil and tonumber(payload.lockdownThreshold) or nil
    if payload.lockdownThreshold ~= nil and (not threshold or threshold % 1 ~= 0 or threshold < 1 or threshold > 10) then
        return { ok = false, error = 'bad_threshold' }
    end

    if payload.enabled ~= nil then rec.enabled = payload.enabled end
    if payload.method ~= nil then rec.method = payload.method end
    if validPin(payload.pin) then rec.pin = secretHash(rec, payload.pin) end
    if validPassword(payload.password) then rec.password = secretHash(rec, payload.password) end
    if validPassword(payload.lockdownPassword) then rec.lockdownPassword = secretHash(rec, payload.lockdownPassword) end
    if payload.lockWallpaper ~= nil then rec.lockWallpaper = payload.lockWallpaper end
    if payload.lockdownOnHackFail ~= nil then rec.lockdownOnHackFail = payload.lockdownOnHackFail == true end
    if threshold then rec.lockdownThreshold = threshold end

    -- a lock screen that cannot be opened is refused, not saved
    if rec.enabled and rec.method == 'pin' and not rec.pin then return { ok = false, error = 'pin_required' } end
    if rec.enabled and rec.method == 'password' and not rec.password then return { ok = false, error = 'password_required' } end
    if not rec.enabled then rec.locked = false end
    saveSecurity(cid, scope, rec)
    return { ok = true, security = publicSecurity(rec) }
end

handlers['security:lock:lock'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    local rec = loadSecurity(cid, scope)
    if rec.enabled then
        rec.locked = true
        saveSecurity(cid, scope, rec)
    end
    return { ok = true, security = publicSecurity(rec) }
end

handlers['security:lock:unlock'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    local rec = loadSecurity(cid, scope)
    if not (rec.enabled and rec.locked) then
        rec.locked = false
        return { ok = true, security = publicSecurity(rec) }
    end
    local stop = blocked(rec)
    if stop then return stop end
    -- the fingerprint is the character itself (holding the sensor is the page's part)
    if rec.method == 'fingerprint' then return unlocked(cid, scope, rec) end
    local stored = rec.method == 'pin' and rec.pin or rec.password
    if not stored then return unlocked(cid, scope, rec) end   -- nothing was ever set
    local secret = payload.secret
    if type(secret) ~= 'string' or secret == '' or #secret > 64 or secretHash(rec, secret) ~= stored then
        return wrongSecret(cid, scope, rec)
    end
    return unlocked(cid, scope, rec)
end

--- The breach device: the tool must be in the player's inventory (checked here); the minigame runs
--- in the player's own screen and its result decides. Failures count towards the lockdown.
handlers['security:lock:breach'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    local hack = Config.Hacking or {}
    if hack.Enabled == false then return { ok = false, error = 'hacking_disabled' } end
    local tier = type(payload.tier) == 'string' and payload.tier or nil
    local tool = tier and hack.Tools and hack.Tools[tier]
    if not tool then return { ok = false, error = 'invalid_tier' } end
    if not C.hasItem(src, tool.item) then return { ok = false, error = 'missing_tool' } end
    local rec = loadSecurity(cid, scope)
    if not (rec.enabled and rec.locked) then return { ok = true, security = publicSecurity(rec) } end
    if rec.lockdownUntil > os.time() then return { ok = false, error = 'lockdown', security = publicSecurity(rec) } end
    if payload.success == true then return unlocked(cid, scope, rec) end
    rec.hackFailures = rec.hackFailures + 1
    local lockdown = false
    if rec.lockdownOnHackFail and rec.hackFailures >= (tonumber(rec.lockdownThreshold) or 3) then
        local minutes = tonumber(Config.Security and Config.Security.Default and Config.Security.Default.lockdownMinutes) or 10
        rec.lockdownUntil = os.time() + math.floor(minutes * 60)
        lockdown = true
    end
    saveSecurity(cid, scope, rec)
    return { ok = false, error = lockdown and 'lockdown' or 'breach_failed', security = publicSecurity(rec) }
end

handlers['security:lock:exitLockdown'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    local rec = loadSecurity(cid, scope)
    if rec.lockdownUntil <= os.time() then return { ok = true, security = publicSecurity(rec) } end
    if not rec.lockdownPassword then return { ok = false, error = 'no_lockdown_password' } end
    if rec.timeoutUntil > os.time() then return { ok = false, error = 'timeout', security = publicSecurity(rec) } end
    local secret = payload.password
    if type(secret) ~= 'string' or secret == '' or #secret > 64 or secretHash(rec, secret) ~= rec.lockdownPassword then
        return wrongSecret(cid, scope, rec)
    end
    rec.lockdownUntil, rec.fails, rec.timeoutUntil, rec.hackFailures = 0, 0, 0, 0
    saveSecurity(cid, scope, rec)
    return { ok = true, security = publicSecurity(rec) }
end

--- Factory reset of the lock screen (Settings > reset); refused while locked.
handlers['security:lock:reset'] = function(payload, src)
    local cid, scope, err = who(src, payload)
    if not cid then return err end
    local rec = loadSecurity(cid, scope)
    if rec.enabled and rec.locked then return { ok = false, error = 'locked' } end
    rec = defaults()
    saveSecurity(cid, scope, rec)
    return { ok = true, security = publicSecurity(rec) }
end

function C.ForgetProfiles(cid)
    if DB.mode == 'memory' then
        for key in pairs(memory) do
            if key:sub(1, #cid + 1) == cid .. '|' then memory[key] = nil end
        end
        return
    end
    MySQL.query.await('DELETE FROM pf_computer_profiles WHERE citizenid = ?', { cid })
end
