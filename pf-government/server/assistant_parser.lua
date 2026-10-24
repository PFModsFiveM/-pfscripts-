-- =====================================================
-- PF GOVERNMENT - ASSISTANT PARSER (PRIORITY ROUTER)
-- =====================================================

local ASSISTANT_ILLEGAL_TERMS = {
    'drug', 'drugs', 'weed', 'cocaine', 'coke', 'meth', 'heroin',
    'blackmarket', 'gang', 'cartel', 'launder', 'money wash',
    'robbery', 'heist', 'weapon trafficking', 'arms deal'
}

local CATEGORY_KEYWORDS = {
    police = { 'police station', 'police', 'pd', 'sheriff', 'lspd', 'bcso' },
    hospital = { 'hospital', 'doctor', 'ems', 'medical', 'clinic', 'ambulance' },
    mechanic = { 'mechanic', 'repair', 'auto shop', 'garage', 'car fix' },
    store = { 'store', 'shop', 'market', 'supermarket', 'grocery' },
    gas = { 'gas station', 'gas', 'fuel', 'petrol' },
    bank = { 'bank', 'atm', 'fleeca' },
    cityhall = { 'city hall', 'cityhall', 'government office', 'town hall' },
    airport = { 'airport', 'lsia', 'airfield' },
    taxi = { 'taxi', 'cab' }
}

local CATEGORY_ALIASES = {
    government = 'cityhall'
}

local EXACT_INTENTS = {
    ['weather'] = { intent = 'weather_info', subIntent = 'weather_info' },
    ['what jobs are available'] = { intent = 'job_info', subIntent = 'job_info' },
    ['available jobs'] = { intent = 'job_info', subIntent = 'job_info' },
    ['jobs'] = { intent = 'job_info', subIntent = 'job_info' }
}

local INTENT_RULES = {
    {
        intent = 'law_info',
        subIntent = 'latest_laws',
        phrases = { 'new laws', 'latest laws', 'recent laws', 'recent law updates' },
        weight = 140
    },
    {
        intent = 'tax_info',
        subIntent = 'current_taxes',
        phrases = { 'current taxes', 'tax rates', 'latest taxes', 'sales tax', 'income tax' },
        weight = 130
    },
    {
        intent = 'weather_info',
        subIntent = 'weather_info',
        phrases = { 'weather forecast', 'current weather', 'is it raining', 'weather now' },
        weight = 120
    },
    {
        intent = 'government_info',
        subIntent = 'government_services',
        phrases = { 'government services', 'city services', 'public services', 'city hall services' },
        weight = 110
    },
    {
        intent = 'business_info',
        subIntent = 'business_lookup',
        phrases = { 'business lookup', 'business registry', 'find business', 'registered businesses' },
        weight = 110
    },
    {
        intent = 'announcement_info',
        subIntent = 'announcement_info',
        phrases = { 'city announcements', 'latest announcements', 'city news', 'public notice' },
        weight = 110
    },
    {
        intent = 'job_info',
        subIntent = 'job_info',
        phrases = { 'available jobs', 'job listings', 'find a job', 'employment' },
        weight = 90
    },
    {
        intent = 'nearest_location',
        subIntent = 'nearest_location',
        phrases = { 'nearest', 'closest', 'where is', 'find nearest', 'location of' },
        weight = 70
    },
    {
        intent = 'help',
        subIntent = 'help',
        phrases = { 'help', 'what can you do', 'assistant help', 'commands' },
        weight = 60
    }
}

function AssistantNormalizeQuery(text)
    local normalized = string.lower(tostring(text or ''))
    normalized = normalized:gsub('[^%w%s%-]', ' ')
    normalized = normalized:gsub('%s+', ' ')
    return normalized:match('^%s*(.-)%s*$')
end

function AssistantIsIllegal(text)
    local normalized = AssistantNormalizeQuery(text)
    for _, term in ipairs(ASSISTANT_ILLEGAL_TERMS) do
        if string.find(normalized, term, 1, true) then
            return true
        end
    end
    return false
end

local function detectNearestCategory(normalized)
    local bestCategory = nil
    local bestScore = 0

    for category, words in pairs(CATEGORY_KEYWORDS) do
        local score = 0
        for _, phrase in ipairs(words) do
            if normalized == phrase then
                score = score + 200
            elseif string.find(normalized, phrase, 1, true) then
                score = score + (50 + #phrase)
            end
        end
        if score > bestScore then
            bestScore = score
            bestCategory = category
        end
    end

    return bestCategory, bestScore
end

function AssistantRouteIntent(query)
    local normalized = AssistantNormalizeQuery(query)
    local exact = EXACT_INTENTS[normalized]
    if exact then
        return {
            intent = exact.intent,
            subIntent = exact.subIntent,
            score = 9999,
            targetCategory = nil,
            normalized = normalized
        }, normalized
    end

    local route = {
        intent = 'fallback',
        subIntent = nil,
        score = 0,
        targetCategory = nil,
        normalized = normalized
    }

    local nearestCategory, nearestCategoryScore = detectNearestCategory(normalized)
    nearestCategory = CATEGORY_ALIASES[nearestCategory] or nearestCategory

    for _, rule in ipairs(INTENT_RULES) do
        local score = 0
        for _, phrase in ipairs(rule.phrases) do
            if normalized == phrase then
                -- Exact phrase matches should dominate broad token matches.
                score = score + 1000 + rule.weight + (#phrase * 2)
            elseif string.find(normalized, phrase, 1, true) then
                score = score + rule.weight + #phrase
            end
        end

        if rule.intent == 'nearest_location' and nearestCategory then
            score = score + nearestCategoryScore
        end

        if score > route.score then
            route.intent = rule.intent
            route.subIntent = rule.subIntent
            route.score = score
            route.targetCategory = rule.intent == 'nearest_location' and nearestCategory or nil
        end
    end

    -- Direct category mention with no explicit nearest phrase still routes to nearest lookup.
    if route.score < 100 and nearestCategory and nearestCategoryScore >= 55 then
        route.intent = 'nearest_location'
        route.subIntent = 'nearest_location'
        route.targetCategory = nearestCategory
        route.score = nearestCategoryScore
    end

    -- Reduce false positives for generic words.
    if normalized == 'services' or normalized == 'business' or normalized == 'job' or normalized == 'news' then
        route.intent = 'help'
        route.subIntent = 'help'
        route.targetCategory = nil
    end

    return route, normalized
end

print('^2[PF-GOVERNMENT]^7 Assistant parser loaded (priority router)')
