-- =====================================================
-- PF GOVERNMENT - ASSISTANT TOOLS
-- =====================================================

local function asNumber(v, d)
    local n = tonumber(v)
    if n == nil then return d or 0 end
    return n
end

local function toUpper(v)
    return string.upper(tostring(v or ''))
end

local function weatherDescription(weatherType)
    local descriptions = {
        CLEAR = 'Clear skies and sunshine.',
        EXTRASUNNY = 'Extra sunny and bright.',
        CLOUDS = 'Partly cloudy conditions.',
        OVERCAST = 'Grey overcast skies.',
        RAIN = 'Rainy conditions.',
        CLEARING = 'Clearing weather after rain.',
        THUNDER = 'Thunderstorm conditions.',
        FOGGY = 'Foggy low-visibility conditions.',
        SMOG = 'Smoggy air conditions.',
        XMAS = 'Light winter weather.',
        SNOWLIGHT = 'Light snowfall.',
        SNOW = 'Heavy snowfall.',
        BLIZZARD = 'Blizzard conditions.',
        HALLOWEEN = 'Dark overcast conditions.',
        NEUTRAL = 'Mild neutral weather.'
    }
    local upper = toUpper(weatherType)
    return descriptions[upper] or ('Current weather: %s.'):format(tostring(weatherType))
end

local WEATHER_PROVIDERS = {
    qb_weathersync = function()
        return exports['pfm-weathersync']:GetCurrentWeather()
    end,
    weather = function()
        return exports['weather']:getCurrentWeather()
    end,
    vsync = function()
        return exports['vSync']:getWeatherType()
    end
}

local function normalizeWeatherProviderKey(provider)
    local key = string.lower(tostring(provider or '')):gsub('%s+', '')
    if key == '' then return nil end
    if key == 'qb-weathersync' then return 'qb_weathersync' end
    if key == 'vsync' then return 'vsync' end
    return key
end

local function resolveProviderResource(key)
    if key == 'qb_weathersync' then return 'qb-weathersync' end
    if key == 'vsync' then return 'vSync' end
    return key
end

local function getWeatherProviderOrder()
    local providers = {}
    local seen = {}

    local function addProvider(raw)
        local key = normalizeWeatherProviderKey(raw)
        if not key or seen[key] then return end
        seen[key] = true
        providers[#providers + 1] = key
    end

    local configured = Config.AssistantWeather and Config.AssistantWeather.Provider
    addProvider(configured)

    for _, key in ipairs((Config.AssistantWeather and Config.AssistantWeather.FallbackProviders) or {}) do
        addProvider(key)
    end

    addProvider('qb_weathersync')
    addProvider('weather')
    addProvider('vsync')

    return providers
end

local function tryWeatherProvider(providerKey)
    local handler = WEATHER_PROVIDERS[providerKey]
    if not handler then return nil end

    local resource = resolveProviderResource(providerKey)
    if GetResourceState(resource) ~= 'started' then
        return nil
    end

    local ok, result = pcall(handler)
    if ok and type(result) == 'string' and result ~= '' then
        return result
    end

    return nil
end

local function servicePointsFromConfig()
    local points = {}
    for _, row in ipairs(Config.AssistantServicePoints or {}) do
        if tonumber(row.x) and tonumber(row.y) then
            points[#points + 1] = {
                name = row.name,
                description = row.description or 'Government service point',
                x = tonumber(row.x),
                y = tonumber(row.y),
                z = tonumber(row.z) or 0,
                category = row.category or 'cityhall',
                keywords = row.keywords or {},
                url = row.url
            }
        end
    end
    return points
end

local function businessPointsFromRegistry()
    local rows = MySQL.query.await(
        'SELECT business_name, business_type, location_x, location_y, location_z, location_address FROM pf_gov_businesses WHERE location_x IS NOT NULL AND location_y IS NOT NULL LIMIT 100',
        {}
    ) or {}

    local points = {}
    for _, row in ipairs(rows) do
        local rawType = tostring(row.business_type or '')
        local mappedCategory = type(MapBusinessCategory) == 'function' and MapBusinessCategory(rawType) or 'business'

        local basePoint = {
            name = row.business_name or 'Business',
            description = (rawType ~= '' and rawType or 'Business') .. (row.location_address and (' | ' .. row.location_address) or ''),
            x = asNumber(row.location_x, 0),
            y = asNumber(row.location_y, 0),
            z = asNumber(row.location_z, 0),
            category = mappedCategory,
            keywords = { 'business', rawType:lower(), tostring(row.business_name or ''):lower() },
            url = 'https://business.ls'
        }

        points[#points + 1] = basePoint

        if mappedCategory ~= 'business' then
            points[#points + 1] = {
                name = basePoint.name,
                description = basePoint.description,
                x = basePoint.x,
                y = basePoint.y,
                z = basePoint.z,
                category = 'business',
                keywords = basePoint.keywords,
                url = basePoint.url
            }
        end
    end

    return points
end

function AssistantGetDynamicLocations()
    local all = {}
    for _, item in ipairs(servicePointsFromConfig()) do
        all[#all + 1] = item
    end
    for _, item in ipairs(businessPointsFromRegistry()) do
        all[#all + 1] = item
    end
    return all
end

function AssistantGetLocationPool(category)
    local pool = {}
    local added = {}

    local categories = { category }
    if category == 'government' then categories[#categories + 1] = 'cityhall' end
    if category == 'cityhall' then categories[#categories + 1] = 'government' end

    for _, cat in ipairs(categories) do
        local static = Config.AssistantLocations and Config.AssistantLocations[cat] or {}
        for _, loc in ipairs(static or {}) do
            local key = ('%s:%s:%s'):format(tostring(loc.name), tostring(loc.x), tostring(loc.y))
            if not added[key] then
                added[key] = true
                pool[#pool + 1] = {
                    name = loc.name,
                    description = loc.description,
                    x = asNumber(loc.x, 0),
                    y = asNumber(loc.y, 0),
                    z = asNumber(loc.z, 0),
                    category = cat,
                    keywords = loc.keywords or {}
                }
            end
        end
    end

    for _, d in ipairs(AssistantGetDynamicLocations()) do
        for _, cat in ipairs(categories) do
            if d.category == cat then
                local key = ('%s:%s:%s'):format(tostring(d.name), tostring(d.x), tostring(d.y))
                if not added[key] then
                    added[key] = true
                    pool[#pool + 1] = d
                end
            end
        end
    end

    return pool
end

function AssistantGetNearest(category, clientCoords)
    local locations = AssistantGetLocationPool(category)
    if not locations or #locations == 0 then
        return nil, nil, {}
    end

    local cx = asNumber(clientCoords and clientCoords.x, 0)
    local cy = asNumber(clientCoords and clientCoords.y, 0)

    local paired = {}
    for _, loc in ipairs(locations) do
        local dx = asNumber(loc.x, 0) - cx
        local dy = asNumber(loc.y, 0) - cy
        local dist = math.sqrt(dx * dx + dy * dy)
        paired[#paired + 1] = { loc = loc, dist = dist }
    end

    table.sort(paired, function(a, b) return a.dist < b.dist end)
    return paired[1].loc, paired[1].dist, paired
end

function AssistantGetTaxes()
    local rows = MySQL.query.await(
        'SELECT tax_type, rate, description, enabled FROM pf_gov_taxes WHERE enabled = 1 ORDER BY tax_type ASC',
        {}
    ) or {}

    local lines = {}
    for _, row in ipairs(rows) do
        local label = (row.tax_type or ''):gsub('_', ' '):gsub('^(%l)', string.upper)
        lines[#lines + 1] = ('%s: %.2f%%'):format(label, asNumber(row.rate, 0))
    end

    return rows, lines
end

function AssistantGetLatestLaws(limit)
    limit = math.max(1, math.floor(asNumber(limit, 3)))
    return MySQL.query.await(
        ('SELECT id, title, category, content, fine_min, fine_max, penalty_min, penalty_max, status, effective_date, created_at FROM pf_gov_laws WHERE status = \'active\' ORDER BY effective_date DESC, created_at DESC LIMIT %d'):format(limit),
        {}
    ) or {}
end

function AssistantGetRecentLaws(windowDays)
    local days = math.max(1, math.floor(asNumber(windowDays, asNumber(Config.AssistantRecentLawWindowDays, 7))))
    local rows = MySQL.query.await(
        'SELECT id, title, category, content, fine_min, fine_max, penalty_min, penalty_max, status, effective_date, created_at FROM pf_gov_laws WHERE status = ? AND COALESCE(effective_date, created_at) >= DATE_SUB(NOW(), INTERVAL ? DAY) ORDER BY COALESCE(effective_date, created_at) DESC LIMIT 5',
        { 'active', days }
    ) or {}
    return rows, days
end

function AssistantGetLatestAnnouncements()
    return MySQL.query.await(
        'SELECT title, content, priority, category, created_by_name, created_at FROM pf_gov_announcements WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY created_at DESC LIMIT 3',
        {}
    ) or {}
end

function AssistantGetWeather()
    local providerOrder = getWeatherProviderOrder()
    for _, providerKey in ipairs(providerOrder) do
        local weatherType = tryWeatherProvider(providerKey)
        if weatherType then
            return weatherType, weatherDescription(weatherType), providerKey
        end
    end

    local fallback = (Config.AssistantWeather and Config.AssistantWeather.UnavailableText)
        or 'Weather data is currently unavailable.'
    return nil, fallback, nil
end

function AssistantGetGovernmentServices()
    local services = {
        { name = 'Government Portal', url = 'https://los-santos.gov#home', description = 'Official city government homepage' },
        { name = 'Tax Information', url = 'https://los-santos.gov#taxes', description = 'View current city tax rates' },
        { name = 'City Laws', url = 'https://los-santos.gov#laws', description = 'Browse municipal laws and regulations' },
        { name = 'Public Announcements', url = 'https://los-santos.gov#announcements', description = 'Latest city notices and alerts' },
        { name = 'Business Registry', url = 'https://business.ls', description = 'Business registration and compliance' }
    }

    for _, point in ipairs(servicePointsFromConfig()) do
        services[#services + 1] = {
            name = point.name,
            description = point.description,
            x = point.x,
            y = point.y,
            z = point.z,
            category = point.category,
            url = point.url
        }
    end

    return services
end

function AssistantGetJobs()
    local qbJobs = QBCore and QBCore.Shared and QBCore.Shared.Jobs or {}
    local out = {}

    for jobName, jobData in pairs(qbJobs) do
        if not AssistantIsIllegal(jobName) then
            out[#out + 1] = {
                name = jobName,
                label = (jobData and jobData.label) or jobName
            }
        end
    end

    table.sort(out, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)

    return out
end

function AssistantSearchBusinesses(query)
    if not query or query == '' then return {} end

    local like = '%' .. query .. '%'

    local hasX = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',
        { 'pf_gov_businesses', 'location_x' }
    )
    local hasAddr = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',
        { 'pf_gov_businesses', 'location_address' }
    )

    local selectCols = 'business_id, business_name, business_type, owner_name'
    if asNumber(hasX, 0) > 0 then
        selectCols = selectCols .. ', location_x, location_y, location_z'
    end
    if asNumber(hasAddr, 0) > 0 then
        selectCols = selectCols .. ', location_address'
    end

    return MySQL.query.await(
        ('SELECT %s FROM pf_gov_businesses WHERE business_name LIKE ? OR business_type LIKE ? OR owner_name LIKE ? ORDER BY business_name ASC LIMIT 10'):format(selectCols),
        { like, like, like }
    ) or {}
end

print('^2[PF-GOVERNMENT]^7 Assistant tools loaded')
