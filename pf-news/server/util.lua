-- Small server helpers shared by every pf-news module: players and newsroom roles, text and URL
-- cleaning, database result shapes.

PFNews = PFNews or {}
local U = {}
PFNews.U = U

function U.QB() return exports['pfm-core']:GetCoreObject() end

function U.player(src)
    src = tonumber(src)
    if not src then return nil end
    return U.QB().Functions.GetPlayer(src)
end

function U.cidOf(Player) return Player and Player.PlayerData and Player.PlayerData.citizenid or nil end

function U.nameOf(Player)
    local ci = Player and Player.PlayerData and Player.PlayerData.charinfo or {}
    local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n:sub(1, 100) or 'Unknown'
end

function U.started(resource)
    return GetResourceState(resource) == 'started'
end

-- oxmysql returns TINYINT(1) as a boolean, a raw driver as 0/1
function U.bool(v) return v == true or v == 1 or v == '1' end

function U.affected(res)
    if type(res) == 'number' then return res end
    if type(res) == 'table' then return tonumber(res.affectedRows or res.changedRows) or 0 end
    return 0
end

function U.int(v, min, max)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.floor(n)
    if (min and n < min) or (max and n > max) then return nil end
    return n
end

function U.decode(s, default)
    if type(s) ~= 'string' or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return default
end

function U.encode(v)
    local ok, s = pcall(json.encode, v)
    return ok and s or nil
end

-- ── text ────────────────────────────────────────────────────────────
-- Stored text never holds markup: angle brackets are removed, so nothing a reporter writes can
-- become HTML in any reader (the news UI also builds its DOM from text nodes only).

--- One line of text: no control characters or angle brackets, spaces collapsed, at most `max`
--- bytes (cut on a character boundary). Returns nil for empty input.
function U.line(v, max)
    if type(v) == 'number' then v = tostring(v) end
    if type(v) ~= 'string' then return nil end
    v = v:gsub('[%c]', ' '):gsub('[<>]', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return U.cut(v, max or 200)
end

--- Multi-line text: newlines kept (at most one blank line in a row), other control characters and
--- angle brackets removed, at most `max` bytes.
function U.text(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('\r\n?', '\n'):gsub('\t', '    '):gsub('[%z\1-\9\11-\31\127]', ''):gsub('[<>]', '')
    v = v:gsub('[ ]+\n', '\n'):gsub('\n\n\n+', '\n\n'):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return U.cut(v, max or 8000)
end

--- Cuts a UTF-8 string to at most `max` bytes without splitting a character.
function U.cut(s, max)
    if #s <= max then return s end
    local cut = s:sub(1, max)
    -- drop a trailing partial multi-byte sequence
    local i = #cut
    while i > 0 do
        local b = cut:byte(i)
        if b < 0x80 then break end
        if b >= 0xC0 then
            local need = b >= 0xF0 and 4 or b >= 0xE0 and 3 or 2
            if #cut - i + 1 < need then cut = cut:sub(1, i - 1) end
            break
        end
        i = i - 1
    end
    return cut
end

--- Characters, not bytes (for minimum lengths).
function U.len(s)
    if type(s) ~= 'string' then return 0 end
    local _, n = s:gsub('[^\128-\191]', '')
    return n
end

--- LIKE pattern for a search term (wildcards in the term are literal).
function U.likeTerm(s)
    return '%' .. s:gsub('\\', '\\\\'):gsub('%%', '\\%%'):gsub('_', '\\_') .. '%'
end

-- ── image URLs ──────────────────────────────────────────────────────

--- An https image URL safe to put in an <img src>, or nil. No quotes, spaces, backslashes or
--- brackets; host from Config.Images.allowedHosts when that list is not empty; an image file
--- extension when Config.Images.requireExtension is set.
function U.imageUrl(v)
    if type(v) ~= 'string' then return nil end
    local cfg = Config.Images or {}
    if #v == 0 or #v > (cfg.maxLength or 300) then return nil end
    local host, rest = v:match('^https://([%w%.%-]+)(/[%w%-%._~/%%%?=&#:+,;@!%$%*]*)$')
    if not host or host:find('%.%.') or host:sub(1, 1) == '.' or not host:find('%.') then return nil end
    host = host:lower()
    if cfg.allowedHosts and #cfg.allowedHosts > 0 then
        local ok = false
        for _, h in ipairs(cfg.allowedHosts) do
            h = tostring(h):lower()
            if host == h or host:sub(-(#h + 1)) == '.' .. h then ok = true break end
        end
        if not ok then return nil end
    end
    if cfg.requireExtension then
        local path = rest:gsub('[%?#].*$', ''):lower()
        local ext = path:match('%.([%w]+)$')
        local okExt = false
        for _, e in ipairs(cfg.extensions or {}) do if ext == e then okExt = true break end end
        if not okExt then return nil end
    end
    return 'https://' .. host .. rest
end

--- A list of image URLs: every entry must be valid (returns nil, 'bad_image' otherwise).
function U.images(list)
    if list == nil then return {} end
    if type(list) ~= 'table' then return nil, 'bad_image' end
    local out = {}
    for i, v in ipairs(list) do
        if v ~= '' and v ~= nil then
            local url = U.imageUrl(v)
            if not url then return nil, 'bad_image' end
            out[#out + 1] = url
        end
        if i > 20 then return nil, 'too_many_images' end
    end
    if #out > (Config.Limits.images or 4) then return nil, 'too_many_images' end
    return out
end

-- ── newsroom roles ──────────────────────────────────────────────────

local function gradeLevel(job)
    if type(job) ~= 'table' then return 0 end
    return tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or 0
end
U.gradeLevel = gradeLevel

--- The highest grade the news job has (nil when the job is not in the shared list).
function U.topGrade()
    local QB = U.QB()
    local job = QB.Shared and QB.Shared.Jobs and QB.Shared.Jobs[Config.Job]
    if not job or type(job.grades) ~= 'table' then return nil end
    local top
    for k in pairs(job.grades) do
        local n = tonumber(k)
        if n and (not top or n > top) then top = n end
    end
    return top
end

--- The grade a role needs, lowered to the job's top grade when the ladder is shorter.
function U.roleGrade(role)
    local need = tonumber(Config.Grades[role]) or 0
    local top = U.topGrade()
    if top and need > top then need = top end
    return need
end

--- Player, job of a reporter (nil when `src` is not in the news job).
function U.reporter(src)
    local Player = U.player(src)
    local job = Player and Player.PlayerData and Player.PlayerData.job
    if not job or job.name ~= Config.Job then return nil end
    return Player, job
end

function U.hasRole(job, role)
    if type(job) ~= 'table' or job.name ~= Config.Job then return false end
    if role == 'editor' or role == 'publish' or role == 'ads' then
        if Config.BossIsEditor and (job.isboss == true or (type(job.grade) == 'table' and job.grade.isboss == true)) then return true end
    end
    if role == 'publish' and U.hasRole(job, 'editor') then return true end
    return gradeLevel(job) >= U.roleGrade(role)
end

function U.roles(job)
    return {
        write = U.hasRole(job, 'write'),
        publish = U.hasRole(job, 'publish'),
        editor = U.hasRole(job, 'editor'),
        ads = U.hasRole(job, 'ads'),
    }
end

function U.categoryOk(id)
    for _, c in ipairs(Config.Categories) do if c.id == id then return true end end
    return false
end

function U.categoryLabel(id)
    for _, c in ipairs(Config.Categories) do if c.id == id then return c.label end end
    return id
end

function U.notify(src, msg, kind, ms)
    if tonumber(src) then TriggerClientEvent('QBCore:Notify', tonumber(src), msg, kind or 'primary', ms or 5000) end
end

function U.dbg(...)
    if Config.Debug then print('^5[pf-news]^7', ...) end
end

-- pf-devices addresses a site's app instances by this id (registry id 'site-<host>')
U.SITE_HOST = 'news.ls'
U.SITE_APP = 'site-news-ls'

--- Push to every open reader: the News app and the news.ls site in any browser.
function U.broadcast(event, payload)
    if not U.started('pf-devices') then return end
    pcall(function()
        exports['pf-devices']:Broadcast('news', event, payload)
        exports['pf-devices']:Broadcast(U.SITE_APP, event, payload)
    end)
end

--- Push to the newsroom app of every reporter online.
function U.pushNewsroom(event, payload)
    if not U.started('pf-devices') then return end
    pcall(function() exports['pf-devices']:PushToJob(Config.Job, 'newsroom', event, payload or {}, false) end)
end
