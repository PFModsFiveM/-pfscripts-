local QBCore = nil
local ESX = nil
local ActiveFramework = 'standalone'

local RESOURCE_NAME = GetCurrentResourceName()
local DATA_FILE = Config.DataFile or 'guidebook_data.json'

local Store = {
    version = 1,
    categories = {},
    pages = {}
}

math.randomseed(os.time())

local function notify(src, msg, msgType)
    TriggerClientEvent('pf-guidebook:client:notify', src, msg, msgType or 'primary')
end

local function detectFramework()
    local configured = string.lower(tostring(Config.Framework or 'auto'))

    if configured == 'qbcore' or configured == 'auto' then
        if GetResourceState('pfm-core') == 'started' then
            local ok, core = pcall(function()
                return exports['pfm-core']:GetCoreObject()
            end)

            if ok and core then
                QBCore = core
                ActiveFramework = 'qbcore'
                return
            end
        end
    end

    if configured == 'esx' or configured == 'auto' then
        if GetResourceState('es_extended') == 'started' then
            local ok, core = pcall(function()
                return exports['es_extended']:getSharedObject()
            end)

            if ok and core then
                ESX = core
                ActiveFramework = 'esx'
                return
            end

            TriggerEvent('esx:getSharedObject', function(obj)
                ESX = obj
            end)

            if ESX then
                ActiveFramework = 'esx'
                return
            end
        end
    end

    ActiveFramework = 'standalone'
end

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end

    return value:match('^%s*(.-)%s*$')
end

local function normalizeEmoji(value)
    return trim(value)
end

local function slugify(value)
    local text = trim((value or ''):lower())
    text = text:gsub('[^%w%s_-]', '')
    text = text:gsub('%s+', '_')
    text = text:gsub('_+', '_')
    text = text:gsub('^_+', '')
    text = text:gsub('_+$', '')

    if text == '' then
        text = 'entry'
    end

    return text
end

local function makeId(prefix)
    return string.format('%s_%d_%d', prefix, os.time(), math.random(10000, 99999))
end

local function toBool(value)
    if value == true or value == 1 or value == '1' or value == 'true' then
        return true
    end

    return false
end

local function toNumber(value, fallback)
    local asNumber = tonumber(value)
    if not asNumber then
        return fallback
    end

    return asNumber
end

local function deepCopy(tbl)
    return json.decode(json.encode(tbl))
end

local function hasString(list, value)
    local needle = string.lower(trim(value))
    if needle == '' then
        return false
    end

    for _, entry in ipairs(list or {}) do
        if string.lower(trim(entry)) == needle then
            return true
        end
    end

    return false
end

local function hasIdentifierMatch(src)
    local allowed = Config.AdminIdentifiers or {}
    if #allowed == 0 then
        return false
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        for _, rule in ipairs(allowed) do
            if trim(rule) ~= '' and identifier == rule then
                return true
            end
        end
    end

    return false
end

local function hasAceAccess(src)
    for _, ace in ipairs(Config.AdminAcePermissions or {}) do
        local aceName = trim(ace)
        if aceName ~= '' and IsPlayerAceAllowed(src, aceName) then
            return true
        end
    end

    return false
end

local function doesPlayerExist(playerId)
    return GetPlayerName(playerId) ~= nil
end

local function normalizeAllowedJobs(raw)
    local result = {}
    local seen = {}

    if type(raw) ~= 'table' then
        return result
    end

    for _, entry in ipairs(raw) do
        local rawJob = trim(entry.job or entry.name or '')
        if rawJob ~= '' then
            local jobName = slugify(rawJob)
            local minGrade = math.max(0, math.floor(toNumber(entry.minGrade or entry.grade, 0)))

            -- Keep the lowest grade when duplicates are provided.
            if seen[jobName] == nil or minGrade < seen[jobName] then
                seen[jobName] = minGrade
            end
        end
    end

    for jobName, minGrade in pairs(seen) do
        result[#result + 1] = {
            job = jobName,
            minGrade = minGrade
        }
    end

    table.sort(result, function(a, b)
        if a.job == b.job then
            return a.minGrade < b.minGrade
        end

        return a.job < b.job
    end)

    return result
end

local function sortByOrder(records)
    table.sort(records, function(a, b)
        local aOrder = toNumber(a.order, 0)
        local bOrder = toNumber(b.order, 0)

        if aOrder == bOrder then
            return (a.label or ''):lower() < (b.label or ''):lower()
        end

        return aOrder < bOrder
    end)

    return records
end

local function ensureUniqueKey(records, key, currentId)
    local candidate = slugify(key)
    local suffix = 1

    local function exists(testKey)
        for _, record in ipairs(records) do
            if record.id ~= currentId and record.key == testKey then
                return true
            end
        end

        return false
    end

    while exists(candidate) do
        candidate = string.format('%s_%d', slugify(key), suffix)
        suffix = suffix + 1
    end

    return candidate
end

local function findCategoryById(id)
    for index, category in ipairs(Store.categories) do
        if category.id == id then
            return category, index
        end
    end

    return nil, nil
end

local function findPageById(id)
    for index, page in ipairs(Store.pages) do
        if page.id == id then
            return page, index
        end
    end

    return nil, nil
end

local function categoryExists(categoryId)
    local category = findCategoryById(categoryId)
    return category ~= nil
end

local function getPlayerJobInfo(src)
    if ActiveFramework == 'qbcore' and QBCore and QBCore.Functions then
        local player = QBCore.Functions.GetPlayer(src)
        if not player or not player.PlayerData or not player.PlayerData.job then
            return 'unemployed', 0
        end

        local job = player.PlayerData.job
        local jobName = slugify(job.name or 'unemployed')

        local grade = 0
        if type(job.grade) == 'table' then
            grade = toNumber(job.grade.level or job.grade.grade, 0)
        else
            grade = toNumber(job.grade, 0)
        end

        return jobName, math.max(0, math.floor(grade))
    end

    if ActiveFramework == 'esx' and ESX and ESX.GetPlayerFromId then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then
            return 'unemployed', 0
        end

        local job = xPlayer.job
        if xPlayer.getJob then
            job = xPlayer.getJob()
        end

        if type(job) ~= 'table' then
            return 'unemployed', 0
        end

        local jobName = slugify(job.name or 'unemployed')
        local grade = 0

        if type(job.grade) == 'table' then
            grade = toNumber(job.grade.level or job.grade.grade, 0)
        else
            grade = toNumber(job.grade or job.grade_level, 0)
        end

        return jobName, math.max(0, math.floor(grade))
    end

    return 'unemployed', 0
end

local function isAdmin(src)
    if src == 0 then
        return true
    end

    if hasIdentifierMatch(src) or hasAceAccess(src) then
        return true
    end

    if ActiveFramework == 'qbcore' and QBCore and QBCore.Functions then
        for _, permission in ipairs(Config.AdminPermissions or {}) do
            if QBCore.Functions.HasPermission(src, permission) then
                return true
            end
        end
    elseif ActiveFramework == 'esx' and ESX and ESX.GetPlayerFromId then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local group = 'user'
            if xPlayer.getGroup then
                group = xPlayer.getGroup() or 'user'
            elseif type(xPlayer.group) == 'string' then
                group = xPlayer.group
            end

            if hasString(Config.AdminGroups, group) then
                return true
            end
        end
    end

    return false
end

local function hasAccessByJob(obj, jobName, jobGrade)
    if not obj.permissionsEnabled then
        return true
    end

    local allowedJobs = obj.allowedJobs or {}
    for _, rule in ipairs(allowedJobs) do
        if rule.job == jobName and jobGrade >= (rule.minGrade or 0) then
            return true
        end
    end

    return false
end

local function extractGpsPointsFromContent(content)
    local points = {}
    if type(content) ~= 'string' or content == '' then
        return points
    end

    local function attr(tag, key)
        return tag:match(key .. '%s*=%s*"([^"]+)"') or tag:match(key .. "%s*=%s*'([^']+)'")
    end

    for tag in content:gmatch('<button.-</button>') do
        if tag:find('guidebook%-gps') then
            local pointKey = slugify(attr(tag, 'data%-point%-key') or '')
            local label = trim(attr(tag, 'data%-label') or '')
            local x = toNumber(attr(tag, 'data%-x'), nil)
            local y = toNumber(attr(tag, 'data%-y'), nil)
            local canNavigate = toBool(attr(tag, 'data%-can%-navigate') or '1')

            if pointKey ~= '' and x and y then
                points[#points + 1] = {
                    key = pointKey,
                    label = label ~= '' and label or pointKey,
                    x = x,
                    y = y,
                    canNavigate = canNavigate
                }
            end
        end
    end

    return points
end

local function saveStore()
    SaveResourceFile(RESOURCE_NAME, DATA_FILE, json.encode(Store), -1)
end

local function seedFromConfig()
    Store = {
        version = 1,
        categories = {},
        pages = {}
    }

    local categoryKeyToId = {}

    for _, category in ipairs(Config.DefaultData and Config.DefaultData.categories or {}) do
        local record = {
            id = makeId('cat'),
            key = slugify(category.key or category.label or 'category'),
            label = trim(category.label or 'Category'),
            emoji = normalizeEmoji(category.emoji),
            order = math.floor(toNumber(category.order, 0)),
            enabled = toBool(category.enabled ~= false),
            expanded = toBool(category.expanded ~= false),
            permissionsEnabled = toBool(category.permissionsEnabled),
            allowedJobs = normalizeAllowedJobs(category.allowedJobs)
        }

        record.key = ensureUniqueKey(Store.categories, record.key, record.id)
        Store.categories[#Store.categories + 1] = record
        categoryKeyToId[record.key] = record.id
    end

    if #Store.categories == 0 then
        local fallback = {
            id = makeId('cat'),
            key = 'general',
            label = 'General',
            emoji = '',
            order = 1,
            enabled = true,
            expanded = true,
            permissionsEnabled = false,
            allowedJobs = {}
        }

        Store.categories[#Store.categories + 1] = fallback
        categoryKeyToId[fallback.key] = fallback.id
    end

    local firstCategoryId = Store.categories[1].id

    for _, page in ipairs(Config.DefaultData and Config.DefaultData.pages or {}) do
        local categoryId = page.categoryId or categoryKeyToId[slugify(page.categoryKey or '')] or firstCategoryId

        local record = {
            id = makeId('page'),
            categoryId = categoryId,
            key = slugify(page.key or page.label or 'page'),
            label = trim(page.label or 'Page'),
            order = math.floor(toNumber(page.order, 0)),
            enabled = toBool(page.enabled ~= false),
            permissionsEnabled = toBool(page.permissionsEnabled),
            allowedJobs = normalizeAllowedJobs(page.allowedJobs),
            content = type(page.content) == 'string' and page.content or '',
            updatedAt = os.time()
        }

        record.key = ensureUniqueKey(Store.pages, record.key, record.id)
        Store.pages[#Store.pages + 1] = record
    end

    saveStore()
end

local function normalizeLoadedStore(decoded)
    if type(decoded) ~= 'table' then
        return false
    end

    local categories = type(decoded.categories) == 'table' and decoded.categories or {}
    local pages = type(decoded.pages) == 'table' and decoded.pages or {}

    Store = {
        version = 1,
        categories = {},
        pages = {}
    }

    local categoryMap = {}

    for _, category in ipairs(categories) do
        local record = {
            id = trim(category.id) ~= '' and category.id or makeId('cat'),
            key = slugify(category.key or category.label or 'category'),
            label = trim(category.label or 'Category'),
            emoji = normalizeEmoji(category.emoji),
            order = math.floor(toNumber(category.order, 0)),
            enabled = toBool(category.enabled ~= false),
            expanded = toBool(category.expanded ~= false),
            permissionsEnabled = toBool(category.permissionsEnabled),
            allowedJobs = normalizeAllowedJobs(category.allowedJobs)
        }

        record.key = ensureUniqueKey(Store.categories, record.key, record.id)
        Store.categories[#Store.categories + 1] = record
        categoryMap[record.id] = true
    end

    if #Store.categories == 0 then
        return false
    end

    local firstCategoryId = Store.categories[1].id

    for _, page in ipairs(pages) do
        local categoryId = page.categoryId
        if not categoryMap[categoryId] then
            categoryId = firstCategoryId
        end

        local record = {
            id = trim(page.id) ~= '' and page.id or makeId('page'),
            categoryId = categoryId,
            key = slugify(page.key or page.label or 'page'),
            label = trim(page.label or 'Page'),
            order = math.floor(toNumber(page.order, 0)),
            enabled = toBool(page.enabled ~= false),
            permissionsEnabled = toBool(page.permissionsEnabled),
            allowedJobs = normalizeAllowedJobs(page.allowedJobs),
            content = type(page.content) == 'string' and page.content or '',
            updatedAt = math.floor(toNumber(page.updatedAt, os.time()))
        }

        record.key = ensureUniqueKey(Store.pages, record.key, record.id)
        Store.pages[#Store.pages + 1] = record
    end

    return true
end

local function loadStore()
    local raw = LoadResourceFile(RESOURCE_NAME, DATA_FILE)
    if not raw or raw == '' then
        seedFromConfig()
        return
    end

    local decoded = json.decode(raw)
    if not normalizeLoadedStore(decoded) then
        seedFromConfig()
        return
    end

    saveStore()
end

local function getCategoryMap()
    local map = {}
    for _, category in ipairs(Store.categories) do
        map[category.id] = category
    end

    return map
end

local function exportPageRecord(page)
    return {
        id = page.id,
        categoryId = page.categoryId,
        key = page.key,
        label = page.label,
        order = page.order,
        enabled = page.enabled,
        permissionsEnabled = page.permissionsEnabled,
        allowedJobs = deepCopy(page.allowedJobs or {}),
        content = page.content,
        updatedAt = page.updatedAt or os.time()
    }
end

local function buildVisibleDataForSource(src)
    local categoryMap = getCategoryMap()
    local jobName, jobGrade = getPlayerJobInfo(src)

    local pagesByCategory = {}
    local allPages = deepCopy(Store.pages)
    sortByOrder(allPages)

    for _, page in ipairs(allPages) do
        local category = categoryMap[page.categoryId]

        if category
            and category.enabled
            and page.enabled
            and hasAccessByJob(category, jobName, jobGrade)
            and hasAccessByJob(page, jobName, jobGrade) then
            pagesByCategory[category.id] = pagesByCategory[category.id] or {}
            pagesByCategory[category.id][#pagesByCategory[category.id] + 1] = exportPageRecord(page)
        end
    end

    local visibleCategories = {}
    local allCategories = deepCopy(Store.categories)
    sortByOrder(allCategories)

    for _, category in ipairs(allCategories) do
        if category.enabled and hasAccessByJob(category, jobName, jobGrade) then
            local pages = pagesByCategory[category.id] or {}
            if #pages > 0 then
                visibleCategories[#visibleCategories + 1] = {
                    id = category.id,
                    key = category.key,
                    label = category.label,
                    emoji = category.emoji,
                    order = category.order,
                    expanded = category.expanded,
                    pages = pages
                }
            end
        end
    end

    return {
        categories = visibleCategories
    }
end

local function buildJobsList()
    local jobs = {}
    local sharedJobs = {}

    if ActiveFramework == 'qbcore' and QBCore and QBCore.Shared then
        sharedJobs = QBCore.Shared.Jobs or {}
    elseif ActiveFramework == 'esx' and ESX and ESX.GetJobs then
        sharedJobs = ESX.GetJobs() or {}
    else
        return jobs
    end

    for jobName, jobInfo in pairs(sharedJobs) do
        local grades = {}
        for level, gradeInfo in pairs(jobInfo.grades or {}) do
            local gradeLevel = math.max(
                0,
                math.floor(toNumber(level, toNumber(gradeInfo.level or gradeInfo.grade, 0)))
            )

            grades[#grades + 1] = {
                level = gradeLevel,
                label = gradeInfo.label or gradeInfo.name or ('Grade ' .. gradeLevel)
            }
        end

        if #grades == 0 then
            grades[#grades + 1] = {
                level = 0,
                label = 'Grade 0'
            }
        end

        table.sort(grades, function(a, b)
            return a.level < b.level
        end)

        jobs[#jobs + 1] = {
            name = slugify(jobName),
            label = jobInfo.label or jobName,
            grades = grades
        }
    end

    table.sort(jobs, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    return jobs
end

local function buildAdminData()
    local categories = deepCopy(Store.categories)
    local pages = deepCopy(Store.pages)
    local categoryMap = getCategoryMap()

    sortByOrder(categories)
    sortByOrder(pages)

    for _, page in ipairs(pages) do
        local category = categoryMap[page.categoryId]
        page.categoryLabel = category and category.label or 'Unknown'
    end

    return {
        categories = categories,
        pages = pages,
        jobs = buildJobsList()
    }
end

local function visibleDataHasPageKey(visibleData, key)
    if type(key) ~= 'string' or key == '' then
        return false
    end

    for _, category in ipairs(visibleData.categories or {}) do
        for _, page in ipairs(category.pages or {}) do
            if page.key == key then
                return true
            end
        end
    end

    return false
end

local function findVisibleGpsPointByKey(source, pointKey)
    local key = slugify(pointKey)
    if key == '' then
        return nil
    end

    local visibleData = buildVisibleDataForSource(source)

    for _, category in ipairs(visibleData.categories or {}) do
        for _, page in ipairs(category.pages or {}) do
            local gpsPoints = extractGpsPointsFromContent(page.content)
            for _, point in ipairs(gpsPoints) do
                if point.key == key and point.canNavigate then
                    return point
                end
            end
        end
    end

    return nil
end

local function openGuidebookForPlayer(src, adminRequested, pageKey)
    TriggerClientEvent('pf-guidebook:client:open', src, {
        adminRequested = adminRequested == true,
        pageKey = pageKey
    })
end

local CallbackHandlers = {}
local useableItemRegistered = false

local function registerCallback(name, handler)
    CallbackHandlers[name] = handler
end

registerCallback('pf-guidebook:server:getOpenPayload', function(source, payload)
    local opts = type(payload) == 'table' and payload or {}
    local admin = isAdmin(source)

    local visibleData = buildVisibleDataForSource(source)
    local pageKey = type(opts.pageKey) == 'string' and slugify(opts.pageKey) or nil

    if pageKey and not visibleDataHasPageKey(visibleData, pageKey) then
        pageKey = nil
    end

    return {
        ok = true,
        isAdmin = admin,
        openAdmin = admin and opts.adminRequested == true,
        pageKey = pageKey,
        visibleData = visibleData,
        adminData = admin and buildAdminData() or nil
    }
end)

registerCallback('pf-guidebook:server:getAdminDataset', function(source)
    if not isAdmin(source) then
        return { ok = false, error = 'Access denied' }
    end

    return {
        ok = true,
        adminData = buildAdminData()
    }
end)

registerCallback('pf-guidebook:server:saveCategory', function(source, payload)
    if not isAdmin(source) then
        return { ok = false, error = 'Access denied' }
    end

    local data = type(payload) == 'table' and payload or {}
    local category = nil

    if data.id then
        category = findCategoryById(data.id)
    end

    if not category then
        category = {
            id = makeId('cat')
        }
        Store.categories[#Store.categories + 1] = category
    end

    category.label = trim(data.label or category.label or 'Category')
    category.emoji = normalizeEmoji(data.emoji or category.emoji)
    category.order = math.floor(toNumber(data.order, category.order or 0))
    category.enabled = toBool(data.enabled ~= false)
    category.expanded = toBool(data.expanded)
    category.permissionsEnabled = toBool(data.permissionsEnabled)
    category.allowedJobs = normalizeAllowedJobs(data.allowedJobs)

    local desiredKey = trim(data.key or '') ~= '' and data.key or category.label
    category.key = ensureUniqueKey(Store.categories, slugify(desiredKey), category.id)

    saveStore()

    return {
        ok = true,
        categoryId = category.id,
        adminData = buildAdminData(),
        visibleData = buildVisibleDataForSource(source)
    }
end)

registerCallback('pf-guidebook:server:deleteCategory', function(source, payload)
    if not isAdmin(source) then
        return { ok = false, error = 'Access denied' }
    end

    local categoryId = payload
    if type(payload) == 'table' then
        categoryId = payload.id
    end

    local _, categoryIndex = findCategoryById(categoryId)
    if not categoryIndex then
        return { ok = false, error = 'Category not found' }
    end

    table.remove(Store.categories, categoryIndex)

    local keptPages = {}
    for _, page in ipairs(Store.pages) do
        if page.categoryId ~= categoryId then
            keptPages[#keptPages + 1] = page
        end
    end
    Store.pages = keptPages

    saveStore()

    return {
        ok = true,
        adminData = buildAdminData(),
        visibleData = buildVisibleDataForSource(source)
    }
end)

registerCallback('pf-guidebook:server:savePage', function(source, payload)
    if not isAdmin(source) then
        return { ok = false, error = 'Access denied' }
    end

    local data = type(payload) == 'table' and payload or {}
    local page = nil

    if data.id then
        page = findPageById(data.id)
    end

    if not page then
        page = {
            id = makeId('page')
        }
        Store.pages[#Store.pages + 1] = page
    end

    local categoryId = data.categoryId
    if not categoryExists(categoryId) then
        return { ok = false, error = 'Invalid category' }
    end

    page.categoryId = categoryId
    page.label = trim(data.label or page.label or 'Page')
    page.order = math.floor(toNumber(data.order, page.order or 0))
    page.enabled = toBool(data.enabled ~= false)
    page.permissionsEnabled = toBool(data.permissionsEnabled)
    page.allowedJobs = normalizeAllowedJobs(data.allowedJobs)
    page.content = type(data.content) == 'string' and data.content or ''
    page.updatedAt = os.time()

    local desiredKey = trim(data.key or '') ~= '' and data.key or page.label
    page.key = ensureUniqueKey(Store.pages, slugify(desiredKey), page.id)

    saveStore()

    return {
        ok = true,
        pageId = page.id,
        pageKey = page.key,
        adminData = buildAdminData(),
        visibleData = buildVisibleDataForSource(source)
    }
end)

registerCallback('pf-guidebook:server:deletePage', function(source, payload)
    if not isAdmin(source) then
        return { ok = false, error = 'Access denied' }
    end

    local pageId = payload
    if type(payload) == 'table' then
        pageId = payload.id
    end

    local _, pageIndex = findPageById(pageId)
    if not pageIndex then
        return { ok = false, error = 'Page not found' }
    end

    table.remove(Store.pages, pageIndex)
    saveStore()

    return {
        ok = true,
        adminData = buildAdminData(),
        visibleData = buildVisibleDataForSource(source)
    }
end)

registerCallback('pf-guidebook:server:resolvePointByKey', function(source, payload)
    local pointKey = payload
    if type(payload) == 'table' then
        pointKey = payload.pointKey
    end

    local point = findVisibleGpsPointByKey(source, pointKey)
    if not point then
        return { ok = false, error = 'Point not found' }
    end

    return {
        ok = true,
        point = point
    }
end)

RegisterNetEvent('pf-guidebook:server:callbackRequest', function(requestId, callbackName, payload)
    local src = source
    local reqId = tostring(requestId or '')
    local callbackKey = tostring(callbackName or '')
    local handler = CallbackHandlers[callbackKey]

    if reqId == '' then
        return
    end

    if not handler then
        TriggerClientEvent('pf-guidebook:client:callbackResponse', src, reqId, {
            ok = false,
            error = 'Unknown callback'
        })
        return
    end

    local ok, result = pcall(handler, src, payload)
    if not ok then
        print(('[pf-guidebook] callback error (%s): %s'):format(callbackKey, result))
        result = {
            ok = false,
            error = 'Internal server error'
        }
    end

    TriggerClientEvent('pf-guidebook:client:callbackResponse', src, reqId, result)
end)

local function targetPlayerExists(playerId)
    if ActiveFramework == 'qbcore' and QBCore and QBCore.Functions then
        return QBCore.Functions.GetPlayer(playerId) ~= nil
    end

    if ActiveFramework == 'esx' and ESX and ESX.GetPlayerFromId then
        return ESX.GetPlayerFromId(playerId) ~= nil
    end

    return doesPlayerExist(playerId)
end

local function registerUseableItem()
    if useableItemRegistered then
        return
    end

    if not Config.EnableUseableItem or trim(Config.ItemName or '') == '' then
        return
    end

    if ActiveFramework == 'standalone' then
        print('[pf-guidebook] Standalone mode: skipping useable item registration.')
        return
    end

    if ActiveFramework == 'qbcore' and QBCore and QBCore.Functions then
        QBCore.Functions.CreateUseableItem(Config.ItemName, function(source)
            if not QBCore.Functions.GetPlayer(source) then
                return
            end

            openGuidebookForPlayer(source, false, nil)
        end)
        useableItemRegistered = true
        return
    end

    if ActiveFramework == 'esx' and ESX and ESX.RegisterUsableItem then
        ESX.RegisterUsableItem(Config.ItemName, function(source)
            if not targetPlayerExists(source) then
                return
            end

            openGuidebookForPlayer(source, false, nil)
        end)
        useableItemRegistered = true
        return
    end

    print('[pf-guidebook] Useable item enabled, but no compatible framework item API was found.')
end

local function initializeFrameworkBindings(context)
    local previous = ActiveFramework
    detectFramework()

    if previous ~= ActiveFramework then
        useableItemRegistered = false
        print(('[pf-guidebook] Active framework switched %s -> %s (%s)'):format(previous, ActiveFramework, context or 'refresh'))
    else
        print(('[pf-guidebook] Active framework: %s (%s)'):format(ActiveFramework, context or 'init'))
    end

    registerUseableItem()
end

initializeFrameworkBindings('startup')
loadStore()

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'qb-core' or resourceName == 'es_extended' then
        initializeFrameworkBindings(('resourceStart:%s'):format(resourceName))
    end
end)

RegisterCommand(Config.Commands.Guidebook, function(source)
    if source == 0 then return end
    openGuidebookForPlayer(source, false, nil)
end, false)

RegisterCommand(Config.Commands.Help, function(source)
    if source == 0 then return end
    openGuidebookForPlayer(source, false, nil)
end, false)

RegisterCommand(Config.Commands.GuidebookAdmin, function(source)
    if source == 0 then return end

    if not isAdmin(source) then
        notify(source, 'You are not allowed to use this command.', 'error')
        return
    end

    openGuidebookForPlayer(source, true, nil)
end, false)

RegisterCommand(Config.Commands.HelpAdmin, function(source)
    if source == 0 then return end

    if not isAdmin(source) then
        notify(source, 'You are not allowed to use this command.', 'error')
        return
    end

    openGuidebookForPlayer(source, true, nil)
end, false)

RegisterCommand(Config.Commands.SendHelp, function(source, args)
    if source == 0 then
        print('[pf-guidebook] Console cannot run /sendhelp directly for now.')
        return
    end

    if not isAdmin(source) then
        notify(source, 'You are not allowed to use this command.', 'error')
        return
    end

    local target = tonumber(args[1])
    if not target then
        notify(source, 'Usage: /sendhelp <playerId> <pageKey(optional)>', 'error')
        return
    end

    if not targetPlayerExists(target) then
        notify(source, 'Target player not found.', 'error')
        return
    end

    local pageKey = args[2] and slugify(args[2]) or nil
    openGuidebookForPlayer(target, false, pageKey)

    notify(source, ('Guidebook sent to player %s.'):format(target), 'success')
end, false)

RegisterCommand(Config.Commands.PointGps, function(source, args)
    if source == 0 then return end

    local key = args[1] and slugify(args[1]) or ''
    if key == '' then
        notify(source, 'Usage: /pointgps <pointKey>', 'error')
        return
    end

    local point = findVisibleGpsPointByKey(source, key)
    if not point then
        notify(source, 'Point not found or not accessible.', 'error')
        return
    end

    TriggerClientEvent('pf-guidebook:client:setWaypoint', source, point)
end, false)
