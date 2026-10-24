-- =====================================================
-- PF GOVERNMENT - ASSISTANT MAIN HANDLER
-- =====================================================

local CATEGORY_LABELS = {
    police = 'Police Station',
    hospital = 'Hospital',
    mechanic = 'Mechanic',
    store = 'Store',
    gas = 'Gas Station',
    bank = 'Bank',
    cityhall = 'City Hall',
    government = 'Government Office',
    airport = 'Airport',
    taxi = 'Taxi'
}

local function makeLocationCard(loc, category, dist, isNearest)
    local distText = dist and ('~%d meters away'):format(math.floor(dist)) or nil
    local description = loc.description or (CATEGORY_LABELS[category] or category)
    if distText then
        description = description .. ' | ' .. distText
    end

    return {
        title = loc.name,
        description = description,
        category = category,
        hasWaypoint = true,
        waypoint = { x = loc.x, y = loc.y, z = loc.z or 0.0 },
        coords = { x = loc.x, y = loc.y, z = loc.z or 0.0 },
        distance = dist and math.floor(dist) or nil,
        nearest = isNearest or false
    }
end

local function handleNearest(category, clientCoords)
    local label = CATEGORY_LABELS[category] or category
    local nearest, dist, allSorted = AssistantGetNearest(category, clientCoords)

    if not nearest then
        return {
            ok = true,
            mode = 'answer',
            intent = 'nearest_location',
            summary = ('No %s locations are registered in the city database.'):format(label),
            results = {},
            actions = {}
        }
    end

    local results = {}
    for i, entry in ipairs(allSorted) do
        if i > 3 then break end
        results[#results + 1] = makeLocationCard(entry.loc, category, entry.dist, i == 1)
    end

    return {
        ok = true,
        mode = 'answer',
        intent = 'nearest_location',
        summary = ('Nearest %s is %s (~%dm away).'):format(label, nearest.name, math.floor(dist or 0)),
        results = results,
        actions = {
            {
                type = 'waypoint',
                label = 'Navigate to ' .. nearest.name,
                coords = { x = nearest.x, y = nearest.y, z = nearest.z or 0.0 }
            }
        }
    }
end

local function handleTaxInfo()
    local rows, lines = AssistantGetTaxes()
    local results = {}
    for _, row in ipairs(rows) do
        local label = (row.tax_type or ''):gsub('_', ' '):gsub('^(%l)', string.upper)
        results[#results + 1] = {
            title = label,
            description = (row.description or '') .. ' | Rate: ' .. tostring(row.rate or 0) .. '%',
            category = 'taxes',
            hasWaypoint = false,
            url = 'https://los-santos.gov#taxes'
        }
    end

    return {
        ok = true,
        mode = 'answer',
        intent = 'tax_info',
        summary = #lines > 0 and ('Current taxes: ' .. table.concat(lines, ', ')) or 'No active taxes are configured.',
        results = results,
        actions = {
            { type = 'open_url', label = 'Open Tax Portal', url = 'https://los-santos.gov#taxes' }
        }
    }
end

local function buildLawCards(rows)
    local results = {}
    for _, row in ipairs(rows) do
        local fineText = (row.fine_max and tonumber(row.fine_max) and tonumber(row.fine_max) > 0)
            and (' | Fine up to $%d'):format(math.floor(tonumber(row.fine_max)))
            or ''
        results[#results + 1] = {
            title = row.title or 'City Law',
            description = (row.category or 'Ordinance') .. fineText,
            category = 'laws',
            hasWaypoint = false,
            url = 'https://los-santos.gov#laws'
        }
    end
    return results
end

local function handleLawInfo(subIntent)
    if subIntent == 'latest_laws' then
        local recentRows, days = AssistantGetRecentLaws()
        if #recentRows > 0 then
            return {
                ok = true,
                mode = 'answer',
                intent = 'law_info',
                summary = ('Found %d new/updated law(s) in the last %d day(s).'):format(#recentRows, days),
                results = buildLawCards(recentRows),
                actions = {
                    { type = 'open_url', label = 'Browse Municipal Code', url = 'https://los-santos.gov#laws' }
                }
            }
        end

        local latest = AssistantGetLatestLaws(3)
        return {
            ok = true,
            mode = 'answer',
            intent = 'law_info',
            summary = ('No new laws in the last %d day(s). Showing latest active laws instead.'):format(days),
            results = buildLawCards(latest),
            actions = {
                { type = 'open_url', label = 'Browse Municipal Code', url = 'https://los-santos.gov#laws' }
            }
        }
    end

    local rows = AssistantGetLatestLaws(3)
    return {
        ok = true,
        mode = 'answer',
        intent = 'law_info',
        summary = #rows > 0 and ('Found %d active law(s).'):format(#rows) or 'No active laws have been published yet.',
        results = buildLawCards(rows),
        actions = {
            { type = 'open_url', label = 'Browse Municipal Code', url = 'https://los-santos.gov#laws' }
        }
    }
end

local function handleAnnouncementInfo()
    local rows = AssistantGetLatestAnnouncements()
    local results = {}
    for _, row in ipairs(rows) do
        local snippet = tostring(row.content or '')
        if #snippet > 130 then snippet = snippet:sub(1, 130) .. '...' end
        results[#results + 1] = {
            title = row.title or 'Announcement',
            description = snippet,
            category = 'announcements',
            hasWaypoint = false,
            url = 'https://los-santos.gov#announcements'
        }
    end

    return {
        ok = true,
        mode = 'answer',
        intent = 'announcement_info',
        summary = #rows > 0 and ('Found %d active announcement(s).'):format(#rows) or 'No active announcements at this time.',
        results = results,
        actions = {
            { type = 'open_url', label = 'View All Announcements', url = 'https://los-santos.gov#announcements' }
        }
    }
end

local function handleWeatherInfo()
    local weatherType, description, provider = AssistantGetWeather()
    local results = {}

    if weatherType then
        results[#results + 1] = {
            title = 'Current Weather: ' .. weatherType,
            description = provider and (description .. ' | Provider: ' .. provider) or description,
            category = 'weather',
            hasWaypoint = false
        }
    end

    return {
        ok = true,
        mode = 'answer',
        intent = 'weather_info',
        summary = description,
        results = results,
        actions = {}
    }
end

local function handleGovernmentInfo()
    local services = AssistantGetGovernmentServices()
    local results = {}
    local actions = {
        { type = 'open_url', label = 'Government Portal', url = 'https://los-santos.gov#home' }
    }

    for _, svc in ipairs(services) do
        results[#results + 1] = {
            title = svc.name,
            description = svc.description,
            category = 'government',
            hasWaypoint = svc.x ~= nil,
            waypoint = svc.x and { x = svc.x, y = svc.y, z = svc.z or 0.0 } or nil,
            coords = svc.x and { x = svc.x, y = svc.y, z = svc.z or 0.0 } or nil,
            url = svc.url
        }
        if svc.url then
            actions[#actions + 1] = { type = 'open_url', label = 'Open ' .. svc.name, url = svc.url }
        end
    end

    return {
        ok = true,
        mode = 'answer',
        intent = 'government_info',
        summary = 'The city provides the following public services.',
        results = results,
        actions = actions
    }
end

local function handleJobInfo()
    local jobs = AssistantGetJobs()
    local results = {}
    for _, job in ipairs(jobs) do
        results[#results + 1] = {
            title = job.label,
            description = 'Job ID: ' .. job.name,
            category = 'jobs',
            hasWaypoint = false
        }
    end

    return {
        ok = true,
        mode = 'answer',
        intent = 'job_info',
        summary = #results > 0 and ('There are %d registered jobs available.'):format(#results) or 'No jobs are currently registered.',
        results = results,
        actions = {}
    }
end

local function handleBusinessInfo(normalized)
    local rows = AssistantSearchBusinesses(normalized)
    local results = {}

    for _, row in ipairs(rows) do
        local hasWp = tonumber(row.location_x) ~= nil and tonumber(row.location_y) ~= nil
        local desc = row.business_type or 'Business'
        if row.location_address and row.location_address ~= '' then
            desc = desc .. ' | ' .. row.location_address
        end

        results[#results + 1] = {
            title = row.business_name or row.business_id or 'Business',
            description = desc,
            category = 'business',
            hasWaypoint = hasWp,
            waypoint = hasWp and { x = tonumber(row.location_x), y = tonumber(row.location_y), z = tonumber(row.location_z or 0) } or nil,
            coords = hasWp and { x = tonumber(row.location_x), y = tonumber(row.location_y), z = tonumber(row.location_z or 0) } or nil,
            url = 'https://business.ls'
        }
    end

    return {
        ok = true,
        mode = 'answer',
        intent = 'business_info',
        summary = #results > 0 and ('Found %d matching business(es).'):format(#results) or 'No businesses found. Try a name, type, or owner.',
        results = results,
        actions = {
            { type = 'open_url', label = 'Open Business Registry', url = 'https://business.ls' }
        }
    }
end

local function handleHelp()
    return {
        ok = true,
        mode = 'answer',
        intent = 'help',
        summary = 'Ask for nearest locations, taxes, laws, weather, services, jobs, or business lookups.',
        results = {
            { title = 'Nearest Location', description = 'Try: nearest hospital, nearest mechanic, closest gas station', category = 'help', hasWaypoint = false },
            { title = 'Government', description = 'Try: current taxes, latest laws, city announcements, government services', category = 'help', hasWaypoint = false },
            { title = 'Registry', description = 'Try: business lookup [name], available jobs', category = 'help', hasWaypoint = false }
        },
        actions = {}
    }
end

local function handleFallback(normalized, originalQuery)
    local results = {}

    for _, loc in ipairs(AssistantGetAllLocations()) do
        local score = 0
        local haystack = string.lower(loc.name or '')

        if string.find(haystack, normalized, 1, true) then
            score = score + 10
        end

        for _, kw in ipairs(loc.keywords or {}) do
            local k = string.lower(kw)
            if string.find(normalized, k, 1, true) then score = score + 5 end
            if string.find(k, normalized, 1, true) then score = score + 2 end
        end

        if score > 0 then
            results[#results + 1] = {
                title = loc.name,
                description = loc.description or loc.category or 'Location',
                category = loc.category or 'location',
                hasWaypoint = true,
                waypoint = { x = loc.x, y = loc.y, z = loc.z or 0.0 },
                coords = { x = loc.x, y = loc.y, z = loc.z or 0.0 },
                score = score
            }
        end
    end

    table.sort(results, function(a, b)
        return tonumber(a.score or 0) > tonumber(b.score or 0)
    end)

    local trimmed = {}
    for i, item in ipairs(results) do
        if i > 10 then break end
        trimmed[#trimmed + 1] = item
    end

    return {
        ok = true,
        mode = 'search',
        intent = 'fallback',
        summary = #trimmed > 0
            and ('Found %d result(s) for "%s".'):format(#trimmed, originalQuery)
            or 'No direct result found. Try nearest hospital, latest laws, current taxes, weather, or business lookup.',
        results = trimmed,
        actions = {
            { type = 'open_url', label = 'Government Portal', url = 'https://los-santos.gov#home' }
        }
    }
end

function AssistantHandleQuery(data)
    local rawQuery = tostring(data and data.query or '')
    local coords = data and data.coords
    local normalized = AssistantNormalizeQuery(rawQuery)

    if AssistantIsIllegal(normalized) then
        return {
            ok = true,
            mode = 'restricted',
            intent = 'restricted',
            summary = 'This assistant only supports legal city services and public government information.',
            results = {},
            actions = {}
        }
    end

    local route = nil
    route, normalized = AssistantRouteIntent(rawQuery)
    route = route or { intent = 'fallback', subIntent = nil, targetCategory = nil }

    if route.intent == 'nearest_location' and route.targetCategory then
        return handleNearest(route.targetCategory, coords)
    end

    if route.intent == 'tax_info' then return handleTaxInfo() end
    if route.intent == 'law_info' then return handleLawInfo(route.subIntent) end
    if route.intent == 'announcement_info' then return handleAnnouncementInfo() end
    if route.intent == 'weather_info' then return handleWeatherInfo() end
    if route.intent == 'government_info' then return handleGovernmentInfo() end
    if route.intent == 'job_info' then return handleJobInfo() end
    if route.intent == 'business_info' then return handleBusinessInfo(normalized) end
    if route.intent == 'help' then return handleHelp() end

    return handleFallback(normalized, rawQuery)
end

print('^2[PF-GOVERNMENT]^7 Assistant main handler loaded')
