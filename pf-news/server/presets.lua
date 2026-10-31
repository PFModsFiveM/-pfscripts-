-- Preset rendering for City Desk articles and newsroom leads (pure functions, no database).
--
-- P.Snapshot(event)            the safe, flat fields of a city event (stored with the event so a
--                              digest can be rebuilt later)
-- P.Render(snap)               { presetId, title, summary, body, category, breaking } for one event
-- P.RenderDigest(group, snaps) the same for several events of one group (one article)
-- P.LeadText(snap)             { title, details } for a newsroom lead
-- Template rules are documented above Config.Presets in config.lua.

PFNews = PFNews or {}
local U = PFNews.U
local P = {}
PFNews.Presets = P

-- event data keys never shown anywhere (people's ids, plates, numbers, accounts)
local PRIVATE = {
    citizenid = true, cid = true, actor = true, source = true, src = true, plate = true, identifier = true,
    license_id = true, phone = true, phonenumber = true, iban = true, account = true, accountref = true,
    coords = true, x = true, y = true, z = true, owner = true, ownerid = true, owner_id = true, steam = true, discord = true,
}

local kindLabels = {}

--- Label of a city event kind (pf-services), cached.
function P.KindLabel(kind)
    if kindLabels[kind] ~= nil then return kindLabels[kind] or nil end
    local label
    if U.started('pf-services') then
        local ok, def = pcall(function() return exports['pf-services']:GetEventKind(kind) end)
        if ok and type(def) == 'table' then label = U.line(def.label, 80) end
    end
    if not label and PFCatalog and PFCatalog.Events and PFCatalog.Events[kind] then label = PFCatalog.Events[kind].label end
    kindLabels[kind] = label or false
    return label
end

function P.__resetLabels() kindLabels = {} end

local function titleCase(s)
    return (tostring(s):gsub('[_%-]+', ' '):gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b:lower() end))
end

local function humanize(s)
    s = tostring(s):gsub('[_%-]+', ' '):gsub('(%l)(%u)', '%1 %2'):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return (s:sub(1, 1):upper() .. s:sub(2):lower())
end
P.humanize = humanize

-- field values may not contain template syntax (a value is never parsed as a template)
local function cleanValue(v, max)
    local s = U.line(v, max)
    if not s then return nil end
    s = s:gsub('[{}]', ''):gsub('%[', '('):gsub('%]', ')')
    if s == '' then return nil end
    return s
end

local function cleanLong(v, max)
    local s = U.text(v, max)
    if not s then return nil end
    s = s:gsub('[{}]', ''):gsub('%[', '('):gsub('%]', ')')
    if s == '' then return nil end
    return s
end

--- The flat, safe view of an event: { id, kind, at, headline, district, category, bulletin, kindLabel, fields }.
function P.Snapshot(event)
    local f = {}
    local long = (Config.Auto and Config.Auto.longFields) or {}
    for k, v in pairs(type(event.data) == 'table' and event.data or {}) do
        if type(k) == 'string' and #k <= 32 and k:match('^%a[%w_]*$') and not PRIVATE[k:lower()] then
            local tv = type(v)
            if tv == 'string' then
                local s = long[k] and cleanLong(v, long[k]) or cleanValue(v, 200)
                if s then f[k] = s end
            elseif tv == 'number' then
                if v == v and math.abs(v) < 1e12 then f[k] = v end
            elseif tv == 'boolean' then
                f[k] = v
            end
        end
    end
    local district = cleanValue(event.district, 64) or (type(f.district) == 'string' and f.district) or nil
    if district then district = titleCase(district) end
    local coords = type(event.coords) == 'table' and event.coords or nil
    local x, y, z
    if coords then
        x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
        if not (x and y) or x ~= x or y ~= y or math.abs(x) > 1e5 or math.abs(y) > 1e5 then x, y, z = nil, nil, nil end
    end
    return {
        id = tonumber(event.id),
        kind = tostring(event.kind),
        at = tonumber(event.at) or os.time(),
        headline = cleanValue(event.title, 160),
        district = district,
        category = cleanValue(event.category, 32),
        bulletin = event.bulletin == true,
        kindLabel = P.KindLabel(tostring(event.kind)),
        coords = x and { x = x, y = y, z = z or 0.0 } or nil,
        fields = f,
    }
end

-- derived fields for the templates (documented in config.lua)
local PAIRS = { { 'oldRate', 'newRate' }, { 'oldBudget', 'newBudget' }, { 'oldAmount', 'newAmount' }, { 'oldValue', 'newValue' }, { 'old', 'new' } }

local function fieldsOf(snap)
    local f = {}
    for k, v in pairs(snap.fields or {}) do f[k] = v end
    f.headline = snap.headline
    f.district = snap.district
    f.kindLabel = snap.kindLabel
    f.time = os.date('%H:%M', snap.at or os.time())
    for _, pr in ipairs(PAIRS) do
        local o, n = tonumber(f[pr[1]]), tonumber(f[pr[2]])
        if o and n then
            if n > o then f.direction, f.fromWord, f.change = 'rises', 'up from', 'increase'
            elseif n < o then f.direction, f.fromWord, f.change = 'falls', 'down from', 'cut'
            else f.direction, f.fromWord, f.change = 'is set', 'unchanged from', 'no change' end
            f.delta = math.abs(n - o)
            break
        end
    end
    local kind = snap.kind or ''
    if kind:sub(1, 8) == 'gov.tax.' then
        local name = type(f.label) == 'string' and f.label or (type(f.tax) == 'string' and humanize(f.tax)) or nil
        if name and not name:lower():find('tax') then name = name .. ' tax' end
        f.taxName = name
    end
    if type(f.enabled) == 'boolean' then
        f.state = f.enabled and 'switched on' or 'suspended'
        f.stateVerb = f.enabled and 'reinstates' or 'suspends'
    end
    local dept = (type(f.label) == 'string' and kind:find('^gov%.budget') and f.label) or f.departmentLabel or f.department
    if type(dept) == 'string' then f.deptName = dept:find('%u') and dept or titleCase(dept) end
    return f
end
P.fieldsOf = fieldsOf

-- ── templates ───────────────────────────────────────────────────────

local function comma(n)
    local neg = n < 0
    n = math.abs(n)
    local whole = math.floor(n)
    local frac = n - whole
    local s = tostring(whole):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    if frac > 0.004 then s = s .. ('%.2f'):format(frac):sub(2):gsub('0+$', '') end
    return (neg and '-' or '') .. s
end

local FORMATS = {
    pct = function(v) local n = tonumber(v) if not n then return nil end return (('%.2f'):format(n):gsub('%.?0+$', '')) .. '%' end,
    money = function(v) local n = tonumber(v) if not n then return nil end return '$' .. comma(math.floor(n + 0.5)) end,
    num = function(v) local n = tonumber(v) if not n then return nil end return comma(n) end,
    lower = function(v) return tostring(v):lower() end,
    upper = function(v) return tostring(v):upper() end,
    title = function(v) return titleCase(v) end,
    cap = function(v) v = tostring(v) return v:sub(1, 1):upper() .. v:sub(2) end,
}

local function plain(v)
    if type(v) == 'boolean' then return v and 'yes' or 'no' end
    if type(v) == 'number' then return comma(v) end
    return v
end

local function lookup(f, spec)
    local names, fmt = spec:match('^([^:]*):?(.*)$')
    for name in (names or ''):gmatch('[^,%s]+') do
        local v = f[name]
        if v ~= nil and v ~= '' then
            if fmt ~= '' and FORMATS[fmt] then return FORMATS[fmt](v) end
            return plain(v)
        end
    end
    return nil
end

-- one pass of {placeholders}; `missing` is true when a placeholder without fallback had no value
local function fill(tpl, f)
    local missing = false
    local out = tpl:gsub('{([^{}]*)}', function(inner)
        local spec, fallback = inner:match('^([^|]*)|(.*)$')
        local v = lookup(f, spec or inner)
        if v ~= nil then return tostring(v) end
        if fallback then return fallback end
        missing = true
        return ''
    end)
    return out, missing
end

local function tidy(s)
    s = s:gsub('[ \t]+', ' '):gsub(' +([%.,;:!%?%)])', '%1'):gsub('%( +', '('):gsub('%(%)', '')
    s = s:gsub(',%s*%.', '.'):gsub('%.%.+', '.'):gsub(' *\n *', '\n'):gsub('\n\n\n+', '\n\n')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Fills a template. Returns text, missing (a required field had no value).
function P.Fill(tpl, f)
    if type(tpl) ~= 'string' then return '', false end
    local text = tpl:gsub('%[([^%[%]]*)%]', function(seg)
        local s, miss = fill(seg, f)
        if miss then return '' end
        return s
    end)
    local s, miss = fill(text, f)
    return tidy(s), miss
end

local function capFirst(s) return (s:gsub('^%l', string.upper)) end

-- The last variant of a preset is its fallback: it is used only when no other variant fits.
local function pickVariant(def, f, id, prefix)
    local eligible = {}
    local variants = def.variants or {}
    local function try(i)
        local v = variants[i]
        local t, m1 = P.Fill(v.title, f)
        local s, m2 = P.Fill(v.summary, f)
        local b, m3 = P.Fill(v.body, f)
        if not (m1 or m2 or m3) and t ~= '' then
            eligible[#eligible + 1] = { id = v.id or (prefix .. '/' .. i), title = t, summary = s, body = b }
        end
    end
    for i = 1, #variants - 1 do try(i) end
    if #eligible == 0 and #variants > 0 then try(#variants) end
    if #eligible == 0 then return nil end
    return eligible[(math.floor(tonumber(id) or 0) % #eligible) + 1]
end

local function categoryOf(def, snap)
    local c = def and def.category or snap.category
    if c and U.categoryOk(c) then return c end
    if snap.category and U.categoryOk(snap.category) then return snap.category end
    return Config.DefaultCategory or 'city'
end

local function breakingOf(def, snap)
    if snap.bulletin then return true end
    local w = def and def.breakingWhen
    if type(w) == 'table' and type(w.field) == 'string' and type(w.values) == 'table' then
        local v = snap.fields and snap.fields[w.field]
        if v ~= nil and w.values[tostring(v):lower()] then return true end
    end
    return false
end

local function finish(r)
    local L = Config.Limits
    r.title = U.cut(capFirst(r.title), L.titleMax or 120)
    r.summary = U.cut(capFirst(r.summary or ''), L.summaryMax or 280)
    r.body = U.cut(r.body or '', L.bodyMax or 8000)
    if r.summary == '' then r.summary = nil end
    return r
end

--- The article for one event.
function P.Render(snap)
    local f = fieldsOf(snap)
    local def = Config.Presets[snap.kind]
    local v = def and pickVariant(def, f, snap.id, snap.kind)
    if not v then
        def = nil
        v = pickVariant(Config.GenericPreset, f, snap.id, 'generic')
    end
    if not v then v = { id = 'generic/fallback', title = snap.headline or snap.kindLabel or 'City update', summary = '', body = '' } end
    return finish({
        presetId = v.id, title = v.title, summary = v.summary, body = v.body,
        category = categoryOf(Config.Presets[snap.kind], snap),
        breaking = breakingOf(Config.Presets[snap.kind], snap),
    })
end

--- The one-line form of an event (digest bullet).
function P.Line(snap)
    local f = fieldsOf(snap)
    local def = Config.Presets[snap.kind] or Config.GenericPreset
    local s, miss = P.Fill(def.line, f)
    if miss or s == '' then s = P.Render(snap).title end
    return capFirst(s)
end

--- The article for several events of one group.
function P.RenderDigest(group, snaps)
    if #snaps <= 1 then return P.Render(snaps[1]) end
    local first = P.Render(snaps[1])
    local lines, short = {}, {}
    local district = snaps[1].district
    local breaking = false
    for _, s in ipairs(snaps) do
        local line = P.Line(s)
        lines[#lines + 1] = '- ' .. line
        short[#short + 1] = line
        if s.district ~= district then district = nil end
        if breakingOf(Config.Presets[s.kind], s) then breaking = true end
    end
    local f = {
        count = #snaps, more = #snaps - 1,
        lines = table.concat(lines, '\n'),
        short = U.cut(table.concat(short, '; '), 220),
        firstTitle = first.title, district = district, kindLabel = snaps[1].kindLabel,
    }
    local def = (Config.Digests or {})[group]
    local v = def and pickVariant(def, f, snaps[1].id, 'digest:' .. group)
    if not v then v = pickVariant(Config.GenericDigest, f, snaps[1].id, 'digest:generic') end
    if not v then v = { id = 'digest:fallback', title = first.title, summary = f.short, body = f.lines } end
    return finish({ presetId = v.id, title = v.title, summary = v.summary, body = v.body, category = first.category, breaking = breaking or first.breaking })
end

--- The coalescing group of an event kind.
function P.GroupOf(kind)
    return (Config.Auto.groups or {})[kind] or kind
end

local function keyLabel(k)
    return humanize(k)
end

--- Title and safe details of a newsroom lead.
function P.LeadText(snap)
    local f = snap.fields or {}
    local title = snap.headline
    if not title then
        title = (snap.kindLabel or humanize(snap.kind:gsub('%.', ' ')))
        if snap.district then title = title .. ' in ' .. snap.district end
    end
    local lines = {}
    if snap.kindLabel then lines[#lines + 1] = 'Type: ' .. snap.kindLabel end
    if snap.district then lines[#lines + 1] = 'District: ' .. snap.district end
    for _, key in ipairs(Config.Leads.publicFields or {}) do
        local v = f[key]
        if v ~= nil and v ~= '' then
            if type(v) == 'number' then v = (key == 'amount') and FORMATS.money(v) or comma(v) end
            if type(v) == 'boolean' then v = v and 'yes' or 'no' end
            lines[#lines + 1] = keyLabel(key) .. ': ' .. tostring(v)
        end
    end
    lines[#lines + 1] = 'Reported at ' .. os.date('%H:%M', snap.at or os.time())
    return { title = U.cut(capFirst(title), 160), details = U.cut(table.concat(lines, '\n'), 1000) }
end
