-- Framework Detection
local QBCore = nil
local ESX = nil

if Config.Framework == 'qbcore' then
    QBCore = exports['pfm-core']:GetCoreObject()
elseif Config.Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
end

-- Helper function to get player from source
local function GetPlayer(source)
    if Config.Framework == 'qbcore' and QBCore then
        return QBCore.Functions.GetPlayer(source)
    elseif Config.Framework == 'esx' and ESX then
        return ESX.GetPlayerFromId(source)
    end
    return nil
end

-- Helper function to get player job
local function GetPlayerJob(source)
    local Player = GetPlayer(source)
    if not Player then return nil, 0 end
    
    if Config.Framework == 'qbcore' then
        return Player.PlayerData.job.name, Player.PlayerData.job.grade.level
    elseif Config.Framework == 'esx' then
        return Player.job.name, Player.job.grade
    end
    return nil, 0
end

-- Helper function to get player identifier
local function GetPlayerIdentifier(source)
    local Player = GetPlayer(source)
    if not Player then return nil end
    
    if Config.Framework == 'qbcore' then
        return Player.PlayerData.citizenid
    elseif Config.Framework == 'esx' then
        return Player.identifier
    end
    return nil
end

local function GetPlayerHasItem(source, itemName)
    if not source or not itemName or itemName == '' then return false, 0 end

    if GetResourceState('ox_inventory') == 'started' then
        local ok, amount = pcall(function()
            return exports.ox_inventory:Search(source, 'count', itemName)
        end)
        if ok and tonumber(amount) and tonumber(amount) > 0 then
            return true, tonumber(amount)
        end
    end

    local Player = GetPlayer(source)
    if not Player then return false, 0 end

    if Config.Framework == 'qbcore' then
        local item = Player.Functions.GetItemByName(itemName)
        local amount = (item and item.amount) or 0
        return amount > 0, amount
    end

    if Config.Framework == 'esx' then
        local item = Player.getInventoryItem(itemName)
        local amount = (item and item.count) or 0
        return amount > 0, amount
    end

    return false, 0
end

local function HasSecurityRecoveryAccess(source)
    if not source then return false end
    if IsPlayerAceAllowed(source, (Config.Security and Config.Security.AdminAce) or 'pf-computer.admin') then
        return true
    end

    local jobName = GetPlayerJob(source)
    local allowedJobs = (Config.Security and Config.Security.AdminRecoveryJobs) or {}
    for _, name in ipairs(allowedJobs) do
        if name == jobName then
            return true
        end
    end

    return false
end

local function NormalizePhoneImages(rawImages)
    local images = {}
    if type(rawImages) ~= 'table' then
        return images
    end

    for idx, item in ipairs(rawImages) do
        local url = ''
        local name = ''
        local created = ''

        if type(item) == 'string' then
            url = item
            name = ('phone-image-%s.jpg'):format(idx)
        elseif type(item) == 'table' then
            url = item.image or item.url or item.src or item.link or ''
            name = item.name or item.label or ('phone-image-%s.jpg'):format(idx)
            created = item.created_at or item.createdAt or item.date or ''
        end

        if type(url) == 'string' and url ~= '' then
            images[#images + 1] = {
                url = url,
                name = tostring(name or ('phone-image-%s.jpg'):format(idx)),
                createdAt = tostring(created or '')
            }
        end
    end

    return images
end

local function GetPlayerPhoneImages(source)
    local citizenId = GetPlayerIdentifier(source)
    if not citizenId or citizenId == '' then
        return {}
    end

    if GetResourceState('pfm-phone') ~= 'started' then
        return {}
    end

    local exportCandidates = {
        'GetPhoneImages',
        'GetGallery',
        'GetGalleryByCitizenId',
        'GetGalleryPhotos',
        'GetPhotos',
        'GetCameraRoll'
    }

    for _, exportName in ipairs(exportCandidates) do
        local ok, result = pcall(function()
            return exports['pfm-phone'][exportName](citizenId)
        end)
        if ok and type(result) == 'table' then
            local normalized = NormalizePhoneImages(result)
            if #normalized > 0 then
                return normalized
            end
        end
    end

    return {}
end

local RESOURCE = GetCurrentResourceName()
local DATA_FILE = 'data/pc_data.json'

local dataStore = nil
local computerProps = {} -- Store spawned computer props

-- ============================================================================
-- World computers (props). The server owns the list: it makes each prop's id, checks the model,
-- position and heading against the staff member's real position, refuses duplicates, and only
-- lets the person who placed a computer (or a senior admin) remove it. Clients only preview.
-- ============================================================================
local MAX_COMPUTER_PROPS = 500
local PLACE_REACH = 5.0       -- how far from the staff member a computer can be placed or removed
local DUPLICATE_RADIUS = 0.75 -- two computers can't occupy the same spot
local nextPropId = 0

local function newPropId()
    nextPropId = nextPropId + 1
    return ('pc-%d-%d'):format(os.time(), nextPropId)
end

-- Load computer props from file; entries saved before ids existed get one
local function LoadComputerProps()
    local file = LoadResourceFile(RESOURCE, 'data/computer_props.json')
    computerProps = (file and json.decode(file)) or {}
    local changed = false
    for _, propData in ipairs(computerProps) do
        if not propData.id then
            propData.id = newPropId()
            changed = true
        end
    end
    print('^2[pf-computer]^7 Loaded ' .. #computerProps .. ' saved computer props')
    return changed
end

-- Save computer props to file
local function SaveComputerProps()
    SaveResourceFile(RESOURCE, 'data/computer_props.json', json.encode(computerProps, { indent = true }), -1)
end

local function publicProp(propData)
    return { id = propData.id, model = propData.model, x = propData.x, y = propData.y, z = propData.z, heading = propData.heading }
end

-- Load props on resource start and send them to everyone online
CreateThread(function()
    Wait(1000)
    if LoadComputerProps() then SaveComputerProps() end
    for _, propData in ipairs(computerProps) do
        TriggerClientEvent('pf-computer:client:spawnProp', -1, publicProp(propData))
    end
end)

-- Players who join later ask for the list (it used to be sent only once, at resource start)
local propRequests = {}
RegisterNetEvent('pf-computer:server:requestProps', function()
    local src = source
    local now = os.time()
    if propRequests[src] and now - propRequests[src] < 10 then return end
    propRequests[src] = now
    for _, propData in ipairs(computerProps) do
        TriggerClientEvent('pf-computer:client:spawnProp', src, publicProp(propData))
    end
end)
AddEventHandler('playerDropped', function() propRequests[source] = nil end)

local function adminAce()
    return (Config.Security and Config.Security.AdminAce) or 'pf-computer.admin'
end

local function canManageComputerProps(src)
    if not src or src <= 0 then return false end
    return IsPlayerAceAllowed(src, adminAce()) or IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'god')
end

-- Removing a computer someone else placed needs the senior permission
local function canRemoveAnyComputer(src)
    return IsPlayerAceAllowed(src, (Config.Security and Config.Security.SeniorAdminAce) or 'pf-computer.admin.all')
        or IsPlayerAceAllowed(src, 'god')
end

local function placerId(src)
    local Player = QBCore and QBCore.Functions.GetPlayer(src)
    return (Player and Player.PlayerData.citizenid) or GetPlayerIdentifier(src, 0) or ('src:' .. tostring(src))
end

local function isComputerModel(model)
    if type(model) ~= 'string' or #model > 64 then return false end
    local hash = GetHashKey(model)
    for _, allowed in ipairs(Config.ComputerProps or {}) do
        if allowed == hash or allowed == model then return true end
    end
    return false
end

local function finiteNumber(v)
    v = tonumber(v)
    return v ~= nil and v == v and v ~= math.huge and v ~= -math.huge and math.abs(v) < 100000 and v or nil
end

-- Server event to save a placed computer
RegisterNetEvent('pf-computer:server:saveProp', function(propData)
    local src = source
    if not canManageComputerProps(src) then return end
    if type(propData) ~= 'table' or not isComputerModel(propData.model) then return end
    local x, y, z, h = finiteNumber(propData.x), finiteNumber(propData.y), finiteNumber(propData.z), finiteNumber(propData.heading or 0)
    if not (x and y and z and h) then return end
    if #computerProps >= MAX_COMPUTER_PROPS then return end
    local at = vector3(x, y, z)
    -- placed where the staff member is, not at a coordinate sent from anywhere on the map
    if #(GetEntityCoords(GetPlayerPed(src)) - at) > PLACE_REACH then
        TriggerClientEvent('QBCore:Notify', src, 'Place the computer next to you', 'error')
        return
    end
    for _, existing in ipairs(computerProps) do
        if #(vector3(existing.x, existing.y, existing.z) - at) < DUPLICATE_RADIUS then
            TriggerClientEvent('QBCore:Notify', src, 'There is already a computer here', 'error')
            return
        end
    end

    local clean = {
        id = newPropId(), model = propData.model, x = x, y = y, z = z,
        heading = h % 360, placedBy = placerId(src), placedAt = os.time(),
    }
    table.insert(computerProps, clean)
    SaveComputerProps()
    TriggerClientEvent('pf-computer:client:spawnProp', -1, publicProp(clean))
end)

-- Server event to delete a computer: the nearest saved computer to the staff member (the client's
-- coordinates only pick which one when several are close), placed by them unless they are senior.
RegisterNetEvent('pf-computer:server:deleteProp', function(target)
    local src = source
    if not canManageComputerProps(src) then return end
    local me = GetEntityCoords(GetPlayerPed(src))
    local hint = me
    if type(target) == 'table' or type(target) == 'vector3' then
        local cx, cy, cz = finiteNumber(target.x), finiteNumber(target.y), finiteNumber(target.z)
        if cx and cy and cz then hint = vector3(cx, cy, cz) end
    end

    local bestIndex, bestDist
    for i, propData in ipairs(computerProps) do
        local pos = vector3(propData.x, propData.y, propData.z)
        local matchesId = type(target) == 'string' and propData.id == target
        local d = #(pos - hint)
        if #(pos - me) <= PLACE_REACH and (matchesId or d < 2.0) and (not bestDist or d < bestDist) then
            bestIndex, bestDist = i, d
        end
    end
    if not bestIndex then
        TriggerClientEvent('QBCore:Notify', src, 'No saved computer next to you', 'error')
        return
    end
    local propData = computerProps[bestIndex]
    if propData.placedBy ~= placerId(src) and not canRemoveAnyComputer(src) then
        TriggerClientEvent('QBCore:Notify', src, 'Only the person who placed this computer can remove it', 'error')
        return
    end
    table.remove(computerProps, bestIndex)
    SaveComputerProps()
    TriggerClientEvent('pf-computer:client:deleteProp', -1, vector3(propData.x, propData.y, propData.z), propData.id)
end)

-- ISO-8601 UTC timestamp. It was called throughout this resource (and by gov_announcements_sync.lua)
-- but never defined, so every caller errored: company deposits took the player's money and then
-- failed before recording it.
function nowIso()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

-- Used by functions defined above their definitions (law sync, emails); declared here so those calls
-- reach them instead of a missing global.
local loadData, saveData, nextId

local function ensureDefaults(data)
    data.counters = data.counters or {}
    data.emails = data.emails or {}
    data.calendarEvents = data.calendarEvents or {}
    data.jobPosts = data.jobPosts or {}
    data.jobApplications = data.jobApplications or {}
    data.marketItems = data.marketItems or {}
    data.chatRooms = data.chatRooms or {}
    data.announcements = data.announcements or {}
    data.laws = data.laws or {}
    data.businesses = data.businesses or {}
    data.businessTransactions = data.businessTransactions or {}
    data.businessEmployees = data.businessEmployees or {}
    data.businessMenus = data.businessMenus or {}
    data.businessMeals = data.businessMeals or {}
    data.businessWages = data.businessWages or {}
    data.wageCaps = data.wageCaps or {}
    data.businessBlips = data.businessBlips or {}
    data.businessAccounts = data.businessAccounts or {}
    data.businessOrders = data.businessOrders or {}
    data.browserDomains = data.browserDomains or {}
    data.browserWebsites = data.browserWebsites or {}
    data.browserGuideStats = data.browserGuideStats or { queries = 0 }
    return data
end

local function getOnlinePlayerMailboxes()
    local mailboxes = {}
    local players = GetPlayers()

    for _, playerSrc in ipairs(players) do
        local src = tonumber(playerSrc)
        local identifier = src and GetPlayerIdentifier(src) or nil
        if identifier and identifier ~= '' then
            mailboxes[(identifier .. '@los-santos.gov')] = true
        end
    end

    -- Keep a system mailbox as a stable fallback.
    mailboxes['announcements@los-santos.gov'] = true
    return mailboxes
end

local function syncLawFeed(law)
    if type(law) ~= 'table' or not law.id then
        return
    end

    local data = loadData()
    local lawId = tonumber(law.id) or law.id
    local existing = nil

    for _, row in ipairs(data.laws) do
        if row.id == lawId then
            existing = row
            break
        end
    end

    if existing then
        existing.title = law.title or existing.title
        existing.category = law.category or existing.category
        existing.content = law.content or existing.content
        existing.status = law.status or existing.status
        existing.effective_date = law.effective_date or existing.effective_date
        existing.updated_at = law.updated_at or nowIso()
    else
        data.laws[#data.laws + 1] = {
            id = lawId,
            title = law.title or ('Law #' .. tostring(lawId)),
            category = law.category or 'General',
            content = law.content or '',
            penalty_min = tonumber(law.penalty_min) or 0,
            penalty_max = tonumber(law.penalty_max) or 0,
            fine_min = tonumber(law.fine_min) or 0,
            fine_max = tonumber(law.fine_max) or 0,
            status = law.status or 'active',
            effective_date = law.effective_date,
            updated_at = law.updated_at or nowIso(),
            source = law.source or 'government'
        }
    end
end

local function createLawAnnouncementEmails(law, action)
    local data = loadData()
    if type(law) ~= 'table' or not law.id then
        return
    end

    local statusText = action == 'repeal' and 'Repealed' or 'Published'
    local subject = ('[City Hall Laws] %s: %s'):format(statusText, law.title or ('Law #' .. tostring(law.id)))
    local body = law.content or ''
    local preview = string.sub(body, 1, 120)
    local sentAt = law.updated_at or law.effective_date or nowIso()

    for mailbox, _ in pairs(getOnlinePlayerMailboxes()) do
        local emailId = nextId('emails')
        data.emails[#data.emails + 1] = {
            id = emailId,
            mailbox = mailbox,
            folder = 'inbox',
            from = 'City Hall',
            to = mailbox,
            subject = subject,
            body = body,
            preview = preview,
            time = sentAt,
            unread = true,
            threadId = emailId,
            metadata = {
                gov_law = true,
                gov_law_id = tostring(law.id),
                gov_law_action = action or 'publish'
            }
        }
    end
end

function loadData()
    if dataStore then
        return dataStore
    end

    local raw = LoadResourceFile(RESOURCE, DATA_FILE)
    if raw and raw ~= '' then
        local decoded = json.decode(raw)
        if type(decoded) == 'table' then
            dataStore = ensureDefaults(decoded)
            return dataStore
        end
    end

    dataStore = ensureDefaults({})
    return dataStore
end

function saveData()
    if not dataStore then
        return
    end
    SaveResourceFile(RESOURCE, DATA_FILE, json.encode(dataStore, { indent = true }), -1)
end

function nextId(key)
    local data = loadData()
    data.counters[key] = (data.counters[key] or 0) + 1
    return data.counters[key]
end


local function safeString(value)
    if value == nil then return '' end
    return tostring(value)
end

local function normalizeDomain(domain)
    local raw = string.lower(safeString(domain)):gsub('^https?://', ''):gsub('/.*$', ''):gsub('%s+', '')
    raw = raw:gsub('^www%.', '')
    if raw == '' then return nil end
    if not raw:find('%.') then
        raw = raw .. '.ls'
    end
    if not raw:match('^[a-z0-9][a-z0-9%-%.]+[a-z0-9]$') then
        return nil
    end
    return raw
end

local function getReservedDomainInfo(domain)
    local cfg = Config.Browser and Config.Browser.Domains and Config.Browser.Domains.Reserved or {}
    return cfg[domain]
end

local function getDomainOwnerRecord(data, domain)
    for _, entry in ipairs(data.browserDomains or {}) do
        if entry.domain == domain then
            return entry
        end
    end
    return nil
end

local function createDefaultWebsiteState(domain, ownerIdentifier, ownerName, templateId)
    local templates = Config.Browser and Config.Browser.WebsiteTemplates or {}
    local template = templates[templateId] or templates.services
    local pageDefs = (template and template.pages) or {
        { slug = 'home', label = 'Home' },
        { slug = 'about', label = 'About' }
    }

    local pages = {}
    for _, page in ipairs(pageDefs) do
        local slug = tostring(page.slug or 'home')
        pages[slug] = {
            title = page.label or slug,
            modules = {
                {
                    id = ('hero_%s'):format(slug),
                    type = 'hero',
                    title = slug == 'home' and (domain or 'Website') or (page.label or slug),
                    body = slug == 'home' and 'Welcome to your website. Use the editor to customize sections, branding, pages, and content modules.' or 'Add details for this page.',
                    buttonLabel = 'Learn More',
                    buttonUrl = slug == 'home' and '#about' or ''
                },
                {
                    id = ('text_%s'):format(slug),
                    type = 'text',
                    title = page.label or slug,
                    body = 'Click Edit Site to update this content.'
                }
            }
        }
    end

    return {
        domain = domain,
        owner = {
            identifier = ownerIdentifier,
            name = ownerName or ownerIdentifier or 'Unknown'
        },
        theme = {
            accent = '#143d6b',
            background = '#f5f7fb',
            surface = '#ffffff',
            text = '#10233a'
        },
        branding = {
            siteName = domain,
            tagline = 'Player-owned website',
            logoUrl = '',
            headerLinks = pageDefs
        },
        pages = pages,
        updatedAt = nowIso()
    }
end

local function ensureWebsiteForDomain(data, record)
    if not record or not record.domain then return nil end
    data.browserWebsites = data.browserWebsites or {}
    if not data.browserWebsites[record.domain] then
        data.browserWebsites[record.domain] = createDefaultWebsiteState(record.domain, record.ownerIdentifier, record.ownerName, record.templateId)
    end
    return data.browserWebsites[record.domain]
end

local function getPlayerName(source)
    local Player = GetPlayer(source)
    if not Player then return 'Unknown Citizen' end
    if Config.Framework == 'qbcore' then
        local char = Player.PlayerData and Player.PlayerData.charinfo or {}
        return ((char.firstname or '') .. ' ' .. (char.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    elseif Config.Framework == 'esx' then
        return Player.getName and Player.getName() or (Player.name or 'Unknown Citizen')
    end
    return 'Unknown Citizen'
end

local function getBrowserConfigPayload(src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local ownedDomains = {}
    for _, entry in ipairs(data.browserDomains or {}) do
        if entry.ownerIdentifier == identifier then
            ownedDomains[#ownedDomains + 1] = entry
        end
    end

    return {
        homeUrl = (Config.Browser and Config.Browser.HomeUrl) or 'https://start.ls',
        featuredSites = (Config.Browser and Config.Browser.FeaturedSites) or {},
        shortcuts = (Config.Browser and Config.Browser.Shortcuts) or {},
        defaultBookmarks = (Config.Browser and Config.Browser.DefaultBookmarks) or {},
        domainPrice = (Config.Browser and Config.Browser.DefaultDomainPrice) or 2500,
        ownedDomains = ownedDomains,
        templates = (Config.Browser and Config.Browser.WebsiteTemplates) or {},
        assistant = (Config.Browser and Config.Browser.Assistant) or {}
    }
end

local function splitKeywords(value)
    local out = {}
    for token in string.gmatch(string.lower(safeString(value)), '[^%s,]+') do
        out[#out + 1] = token
    end
    return out
end

local function containsKeyword(haystack, needle)
    haystack = string.lower(safeString(haystack))
    needle = string.lower(safeString(needle))
    return haystack:find(needle, 1, true) ~= nil
end

local function findAssistantResponse(query)
    local lowered = string.lower(safeString(query))
    local assistant = Config.Browser and Config.Browser.Assistant or {}
    local best = nil
    local bestScore = 0

    for _, intent in ipairs(assistant.Intents or {}) do
        local score = 0
        for _, keyword in ipairs(intent.keywords or {}) do
            if containsKeyword(lowered, keyword) then
                score = score + 2
            else
                for _, token in ipairs(splitKeywords(keyword)) do
                    if containsKeyword(lowered, token) then
                        score = score + 1
                    end
                end
            end
        end
        if score > bestScore then
            bestScore = score
            best = {
                type = 'intent',
                title = intent.title,
                body = intent.body,
                url = intent.url,
                score = score
            }
        end
    end

    for _, location in ipairs(assistant.Locations or {}) do
        local score = 0
        for _, keyword in ipairs(location.keywords or {}) do
            if containsKeyword(lowered, keyword) then
                score = score + 3
            end
        end
        if score > bestScore then
            bestScore = score
            best = {
                type = 'location',
                title = location.name,
                body = ('%s Located on %s.'):format(location.description or location.name, location.street or 'city streets'),
                waypoint = location.coords,
                score = score
            }
        end
    end

    if best then return best end

    return {
        type = 'fallback',
        title = 'Guide',
        body = assistant.DefaultReply or 'No match found.'
    }
end

local handlers = {}

-- City government actions use pf-government's own roles (government job + a grade permission such as
-- 'fines', 'taxes' or 'budgets'). They used to accept any job in Config.GovJobs at any grade, so a
-- grade-0 police officer, medic or lawyer could fine players, change taxes or cut utilities.
-- Fails closed when pf-government is not running.
local function govCan(src, permission)
    if not src or GetResourceState('pf-government') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['pf-government']:HasPermission(src, permission) end)
    return ok and allowed == true
end

-- Any government role (every role has 'audit'); the dispatcher checks each action's own permission.
local function isGovAuthorized(src)
    return govCan(src, 'audit')
end

-- Mail and calendar belong to the player: the server works out their address and owner. (The app
-- sent no mailbox, so everyone shared one inbox, and a modified client could read, send as or delete
-- from any mailbox.) Government notices are delivered to <identifier>@los-santos.gov already.
local MAX_SUBJECT, MAX_BODY, MAX_ADDRESS = 120, 4000, 80

local function ownMailbox(src)
    local identifier = src and GetPlayerIdentifier(src)
    if not identifier or identifier == '' then return nil end
    return identifier .. '@los-santos.gov'
end

local function cleanText(value, maxLen, default)
    if type(value) ~= 'string' then return default end
    value = value:gsub('%c', ' ')
    if #value > maxLen then value = value:sub(1, maxLen) end
    return value
end

local function cleanAddress(value)
    if type(value) ~= 'string' or #value > MAX_ADDRESS then return nil end
    if not value:match('^[%w%._%-]+@[%w%.%-]+$') then return nil end
    return value
end

-- addresses compare without case (citizen ids are upper case, typed addresses often are not)
local function sameMailbox(a, b)
    return type(a) == 'string' and type(b) == 'string' and a:lower() == b:lower()
end

handlers['emails:list'] = function(payload, src)
    local mailbox = ownMailbox(src)
    if not mailbox then return { ok = false, error = 'no_identifier' } end
    local data = loadData()
    local folder = type(payload.folder) == 'string' and payload.folder or nil
    local out = {}
    for _, email in ipairs(data.emails) do
        if sameMailbox(email.mailbox, mailbox) and (not folder or email.folder == folder) then
            out[#out + 1] = email
        end
    end
    return { ok = true, data = out, mailbox = mailbox }
end

local function sendEmail(src, to, subject, body, threadId)
    local mailbox = ownMailbox(src)
    if not mailbox then return { ok = false, error = 'no_identifier' } end
    to = cleanAddress(to)
    if not to then return { ok = false, error = 'invalid_recipient' } end
    subject = cleanText(subject, MAX_SUBJECT, '(no subject)')
    body = cleanText(body, MAX_BODY, '')
    local data = loadData()
    local time = nowIso()

    local sentId = nextId('emails')
    local sentItem = {
        id = sentId, mailbox = mailbox, folder = 'sent', from = mailbox, to = to,
        subject = subject, body = body, preview = string.sub(body, 1, 120),
        time = time, unread = false, threadId = threadId or sentId,
    }
    data.emails[#data.emails + 1] = sentItem

    local inboxId = nextId('emails')
    data.emails[#data.emails + 1] = {
        id = inboxId, mailbox = to, folder = 'inbox', from = mailbox, to = to,
        subject = subject, body = body, preview = string.sub(body, 1, 120),
        time = time, unread = true, threadId = threadId or sentItem.threadId,
    }

    saveData()
    return { ok = true, data = sentItem }
end

handlers['emails:send'] = function(payload, src)
    return sendEmail(src, payload.to, payload.subject, payload.body, nil)
end

handlers['emails:reply'] = function(payload, src)
    local mailbox = ownMailbox(src)
    if not mailbox then return { ok = false, error = 'no_identifier' } end
    local data = loadData()
    local original = nil
    for _, email in ipairs(data.emails) do
        if email.id == payload.replyToId and sameMailbox(email.mailbox, mailbox) then
            original = email
            break
        end
    end
    if not original then
        return { ok = false, error = 'email_not_found' }
    end
    local subject = payload.subject or ('Re: ' .. (original.subject or '(no subject)'))
    return sendEmail(src, original.from, subject, payload.body, original.threadId or original.id)
end

handlers['emails:saveDraft'] = function(payload, src)
    local mailbox = ownMailbox(src)
    if not mailbox then return { ok = false, error = 'no_identifier' } end
    local data = loadData()
    local draftId = nextId('emails')
    local body = cleanText(payload.body, MAX_BODY, '')
    local draft = {
        id = draftId, mailbox = mailbox, folder = 'drafts', from = mailbox,
        to = cleanAddress(payload.to) or '', subject = cleanText(payload.subject, MAX_SUBJECT, '(no subject)'),
        body = body, preview = string.sub(body, 1, 120), time = nowIso(), unread = false,
    }
    data.emails[#data.emails + 1] = draft
    saveData()
    return { ok = true, data = draft }
end

handlers['emails:delete'] = function(payload, src)
    local mailbox = ownMailbox(src)
    if not mailbox then return { ok = false, error = 'no_identifier' } end
    local emailId = payload.emailId
    if not emailId then
        return { ok = false, error = 'missing_email_id' }
    end
    local data = loadData()
    for i, email in ipairs(data.emails) do
        if email.id == emailId and sameMailbox(email.mailbox, mailbox) then
            table.remove(data.emails, i)
            saveData()
            return { ok = true }
        end
    end
    return { ok = false, error = 'email_not_found' }
end

-- Calendar: everyone sees the shared 'global' events plus their own; only government staff with the
-- 'laws' permission (or a computer admin) add or remove global events.
local function calendarOwner(src)
    local identifier = src and GetPlayerIdentifier(src)
    return identifier and identifier ~= '' and identifier or nil
end

local function canEditGlobalCalendar(src)
    return govCan(src, 'laws') or IsPlayerAceAllowed(src, (Config.Security and Config.Security.AdminAce) or 'pf-computer.admin')
end

handlers['calendar:list'] = function(_, src)
    local owner = calendarOwner(src)
    local data = loadData()
    local out = {}
    for _, event in ipairs(data.calendarEvents) do
        if event.owner == 'global' or (owner and event.owner == owner) then
            out[#out + 1] = event
        end
    end
    return { ok = true, data = out }
end

handlers['calendar:add'] = function(payload, src)
    local owner = calendarOwner(src)
    if not owner then return { ok = false, error = 'no_identifier' } end
    if payload.owner == 'global' then
        if not canEditGlobalCalendar(src) then return { ok = false, error = 'not_authorized' } end
        owner = 'global'
    end
    local data = loadData()
    local event = {
        id = nextId('calendar'),
        owner = owner,
        title = cleanText(payload.title, MAX_SUBJECT, 'Reminder'),
        date = cleanText(payload.date, 32, nil),
        time = cleanText(payload.time, 32, 'All Day'),
        description = cleanText(payload.description, 1000, ''),
    }
    data.calendarEvents[#data.calendarEvents + 1] = event
    saveData()
    return { ok = true, data = event }
end

handlers['calendar:remove'] = function(payload, src)
    local owner = calendarOwner(src)
    local eventId = payload.eventId
    if not eventId then
        return { ok = false, error = 'missing_event_id' }
    end
    local data = loadData()
    for i, event in ipairs(data.calendarEvents) do
        if event.id == eventId then
            local allowed = (owner and event.owner == owner) or (event.owner == 'global' and canEditGlobalCalendar(src))
            if not allowed then return { ok = false, error = 'not_authorized' } end
            table.remove(data.calendarEvents, i)
            saveData()
            return { ok = true }
        end
    end
    return { ok = false, error = 'event_not_found' }
end

handlers['jobs:list'] = function(_)
    local data = loadData()
    return { ok = true, data = data.jobPosts }
end

handlers['jobs:create'] = function(payload, src)
    local data = loadData()
    local jobId = nextId('jobs')
    local creatorId = src and GetPlayerIdentifier(src) or 'unknown'
    -- plain bounded strings only (the board rendered these as HTML; the UI now escapes them too)
    local tags = {}
    for _, tag in ipairs(type(payload.tags) == 'table' and payload.tags or {}) do
        if #tags >= 8 then break end
        tags[#tags + 1] = cleanText(tag, 24, nil)
    end
    local job = {
        id = jobId,
        title = cleanText(payload.title, 80, 'Untitled Role'),
        company = cleanText(payload.company, 80, 'Unknown'),
        location = cleanText(payload.location, 80, 'Los Santos'),
        salary = cleanText(payload.salary, 40, 'Negotiable'),
        type = cleanText(payload.type, 30, 'Full-time'),
        category = cleanText(payload.category, 30, 'general'),
        description = cleanText(payload.description, 2000, ''),
        tags = tags,
        createdAt = nowIso(),
        creatorIdentifier = creatorId
    }
    data.jobPosts[#data.jobPosts + 1] = job
    saveData()
    return { ok = true, data = job }
end

handlers['jobs:myJobs'] = function(_, src)
    local data = loadData()
    local identifier = src and GetPlayerIdentifier(src) or 'unknown'
    local myJobs = {}
    for _, job in ipairs(data.jobPosts) do
        if job.creatorIdentifier == identifier then
            -- Count applicants for this job
            local count = 0
            for _, app in ipairs(data.jobApplications) do
                if app.jobId == job.id then
                    count = count + 1
                end
            end
            local jobCopy = {}
            for k, v in pairs(job) do jobCopy[k] = v end
            jobCopy.applicantCount = count
            myJobs[#myJobs + 1] = jobCopy
        end
    end
    return { ok = true, data = myJobs }
end

handlers['jobs:getApplicants'] = function(payload, src)
    local data = loadData()
    local identifier = src and GetPlayerIdentifier(src) or 'unknown'
    local jobId = payload.jobId
    if not jobId then
        return { ok = false, error = 'missing_job_id' }
    end
    -- Verify the requesting player owns the job
    local isOwner = false
    for _, job in ipairs(data.jobPosts) do
        if job.id == jobId and job.creatorIdentifier == identifier then
            isOwner = true
            break
        end
    end
    if not isOwner then
        return { ok = false, error = 'not_authorized' }
    end
    local applicants = {}
    for _, app in ipairs(data.jobApplications) do
        if app.jobId == jobId then
            applicants[#applicants + 1] = app
        end
    end
    return { ok = true, data = applicants }
end

handlers['jobs:apply'] = function(payload)
    local data = loadData()
    local jobId = payload.jobId
    if not jobId then
        return { ok = false, error = 'missing_job_id' }
    end

    -- plain bounded strings, only for posts that exist, and the oldest dropped past a cap (the data
    -- file is re-saved on every write; unbounded text grew it without limit)
    local exists = false
    for _, job in ipairs(data.jobPosts) do
        if job.id == jobId then exists = true break end
    end
    if not exists then
        return { ok = false, error = 'job_not_found' }
    end
    local appId = nextId('applications')
    local app = {
        id = appId,
        jobId = jobId,
        name = cleanText(payload.name, 60, 'Applicant'),
        phone = cleanText(payload.phone, 20, ''),
        email = cleanText(payload.email, 80, ''),
        experience = cleanText(payload.experience, 1000, ''),
        message = cleanText(payload.message, 1000, ''),
        createdAt = nowIso()
    }
    data.jobApplications[#data.jobApplications + 1] = app
    while #data.jobApplications > 500 do table.remove(data.jobApplications, 1) end
    saveData()
    return { ok = true, data = app }
end

handlers['darkweb:market:list'] = function(_)
    local data = loadData()
    return { ok = true, data = data.marketItems }
end

handlers['darkweb:market:create'] = function(payload)
    local data = loadData()
    local itemId = nextId('market')
    local item = {
        id = itemId,
        title = cleanText(payload.title, 80, 'Untitled Item'),
        price = cleanText(tostring(payload.price or ''), 30, '0 BTC'),
        condition = cleanText(payload.condition, 20, 'used'),
        description = cleanText(payload.description, 1000, ''),
        contact = cleanText(payload.contact, 60, 'darkchat:market'),
        createdAt = nowIso()
    }
    data.marketItems[#data.marketItems + 1] = item
    while #data.marketItems > 200 do table.remove(data.marketItems, 1) end
    saveData()
    return { ok = true, data = item }
end

handlers['darkweb:chat:rooms'] = function(_)
    local data = loadData()
    local rooms = {}
    for name, room in pairs(data.chatRooms) do
        rooms[#rooms + 1] = {
            name = name,
            count = #(room.messages or {})
        }
    end
    table.sort(rooms, function(a, b) return a.name < b.name end)
    return { ok = true, data = rooms }
end

-- room names are short plain words, and only so many rooms exist (each join of a new name used to
-- add a room to the data file forever)
local MAX_CHAT_ROOMS = 50
local function chatRoomName(value)
    if value == nil then return 'market' end
    if type(value) ~= 'string' or #value > 24 or not value:match('^[%w_%-]+$') then return nil end
    return value:lower()
end
local function chatRoomCount(rooms)
    local n = 0
    for _ in pairs(rooms) do n = n + 1 end
    return n
end

handlers['darkweb:chat:join'] = function(payload)
    local data = loadData()
    local name = chatRoomName(payload.room)
    if not name then return { ok = false, error = 'invalid_room' } end
    if not data.chatRooms[name] and chatRoomCount(data.chatRooms) >= MAX_CHAT_ROOMS then
        return { ok = false, error = 'too_many_rooms' }
    end
    if not data.chatRooms[name] then
        data.chatRooms[name] = { messages = {} }
        saveData()
    end
    return { ok = true, data = { room = name, messages = data.chatRooms[name].messages } }
end

handlers['darkweb:chat:post'] = function(payload)
    local data = loadData()
    local room = chatRoomName(payload.room)
    local message = cleanText(payload.message, 500, '')
    local author = cleanText(payload.author, 30, 'Anonymous')
    if not room then
        return { ok = false, error = 'invalid_room' }
    end
    if message == '' then
        return { ok = false, error = 'empty_message' }
    end
    if not data.chatRooms[room] and chatRoomCount(data.chatRooms) >= MAX_CHAT_ROOMS then
        return { ok = false, error = 'too_many_rooms' }
    end

    if not data.chatRooms[room] then
        data.chatRooms[room] = { messages = {} }
    end

    local entry = {
        id = nextId('chat'),
        author = author,
        message = message,
        time = nowIso()
    }
    local messages = data.chatRooms[room].messages
    messages[#messages + 1] = entry
    if #messages > 50 then
        table.remove(messages, 1)
    end

    saveData()
    return { ok = true, data = entry }
end

handlers['security:config:get'] = function(_, src)
    local securityConfig = Config.Security or {}
    local hackingConfig = Config.Hacking or {}

    return {
        ok = true,
        data = {
            security = securityConfig,
            hacking = hackingConfig,
            adminRecoveryAllowed = HasSecurityRecoveryAccess(src)
        }
    }
end

handlers['security:hack:checkTool'] = function(payload, src)
    local tier = tostring(payload.tier or 'basic')
    local hackCfg = Config.Hacking or {}
    local toolCfg = hackCfg.Tools and hackCfg.Tools[tier] or nil

    if not toolCfg then
        return { ok = false, error = 'invalid_tier' }
    end

    local hasItem, count = GetPlayerHasItem(src, toolCfg.item)
    if not hasItem then
        return { ok = false, error = 'missing_tool', data = { requiredItem = toolCfg.item, label = toolCfg.label or tier, count = 0 } }
    end

    return {
        ok = true,
        data = {
            tier = tier,
            item = toolCfg.item,
            label = toolCfg.label or tier,
            count = count
        }
    }
end

handlers['security:hack:detectTool'] = function(_, src)
    local hackCfg = Config.Hacking or {}
    local tools = hackCfg.Tools or {}
    local priority = { 'master', 'advanced', 'basic' }

    for _, tier in ipairs(priority) do
        local toolCfg = tools[tier]
        if toolCfg and toolCfg.item and toolCfg.item ~= '' then
            local hasItem, count = GetPlayerHasItem(src, toolCfg.item)
            if hasItem then
                return {
                    ok = true,
                    data = {
                        tier = tier,
                        item = toolCfg.item,
                        label = toolCfg.label or tier,
                        count = count,
                        config = toolCfg
                    }
                }
            end
        end
    end

    return { ok = false, error = 'no_hack_tool' }
end

handlers['security:admin:recovery'] = function(_, src)
    if not HasSecurityRecoveryAccess(src) then
        return { ok = false, error = 'not_authorized' }
    end

    return { ok = true, data = { authorized = true } }
end

handlers['devices:phoneImages'] = function(_, src)
    local images = GetPlayerPhoneImages(src)
    return {
        ok = true,
        data = {
            source = (GetResourceState('pfm-phone') == 'started') and 'qb-phone' or 'none',
            images = images
        }
    }
end

handlers['gov:announcements:list'] = function(_)
    local data = loadData()

    if GetResourceState('pf-government') == 'started' then
        local ok, announcements = pcall(function()
            return exports['pf-government']:GetActiveAnnouncements()
        end)

        if ok and type(announcements) == 'table' then
            data.announcements = announcements
            saveData()
            return { ok = true, data = announcements }
        end
    end

    return { ok = true, data = data.announcements or {} }
end

handlers['gov:laws:list'] = function(_)
    local data = loadData()

    if GetResourceState('pf-government') == 'started' then
        local ok, laws = pcall(function()
            return exports['pf-government']:GetPublicLaws()
        end)

        if ok and type(laws) == 'table' then
            data.laws = laws
            saveData()
            return { ok = true, data = laws }
        end
    end

    return { ok = true, data = data.laws or {} }
end

handlers['gov:taxes:list'] = function(_)
    if GetResourceState('pf-government') == 'started' then
        local ok, taxes = pcall(function()
            return exports['pf-government']:GetTaxSchedule()
        end)
        if ok and type(taxes) == 'table' then
            return { ok = true, data = taxes }
        end
    end
    return { ok = true, data = {} }
end

handlers['gov:website:get'] = function(_)
    if GetResourceState('pf-government') == 'started' then
        local ok, siteState = pcall(function()
            return exports['pf-government']:GetWebsiteState()
        end)
        if ok and type(siteState) == 'table' then
            return { ok = true, data = siteState }
        end
    end
    return { ok = true, data = {} }
end

handlers['browser:config:get'] = function(_, src)
    return { ok = true, data = getBrowserConfigPayload(src) }
end

handlers['browser:assistant:query'] = function(payload, _)
    local data = loadData()
    data.browserGuideStats.queries = (tonumber(data.browserGuideStats.queries) or 0) + 1
    saveData()
    return { ok = true, data = findAssistantResponse(payload.query or '') }
end

handlers['browser:domains:list'] = function(_, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local out = {}
    for _, entry in ipairs(data.browserDomains or {}) do
        out[#out + 1] = {
            domain = entry.domain,
            ownerIdentifier = entry.ownerIdentifier,
            ownerName = entry.ownerName,
            templateId = entry.templateId,
            purchasedAt = entry.purchasedAt,
            isOwner = identifier ~= nil and entry.ownerIdentifier == identifier
        }
    end
    table.sort(out, function(a, b) return tostring(a.domain) < tostring(b.domain) end)
    return { ok = true, data = out }
end

handlers['browser:domain:buy'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    if not identifier then
        return { ok = false, error = 'no_identifier' }
    end

    local domain = normalizeDomain(payload.domain)
    if not domain then
        return { ok = false, error = 'invalid_domain' }
    end
    if getReservedDomainInfo(domain) then
        return { ok = false, error = 'reserved_domain' }
    end
    if getDomainOwnerRecord(data, domain) then
        return { ok = false, error = 'domain_taken' }
    end

    -- the price is the server's (the client's payload.price used to be charged, so 0 was free), and
    -- it is paid through the bank ledger
    local price = tonumber((Config.Browser and Config.Browser.DefaultDomainPrice) or 2500) or 2500
    local Player = GetPlayer(src)
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if not cid or GetResourceState('pfm-banking') ~= 'started' then
        return { ok = false, error = 'bank_unavailable' }
    end
    local okCall, res = pcall(function()
        return exports['pfm-banking']:Transfer({
            from = ('player:%s:bank'):format(cid), to = 'system:pf-computer-domains', amount = price,
            key = ('pf-computer:domain:%s:%s'):format(domain, cid), kind = 'purchase',
            reason = 'Domain ' .. domain, actor = cid,
        })
    end)
    if not okCall or type(res) ~= 'table' or not res.ok then
        return { ok = false, error = 'insufficient_funds' }
    end

    local record = {
        domain = domain,
        ownerIdentifier = identifier,
        ownerName = getPlayerName(src),
        templateId = payload.templateId or 'services',
        purchasedAt = nowIso(),
        price = price
    }
    data.browserDomains[#data.browserDomains + 1] = record
    ensureWebsiteForDomain(data, record)
    saveData()

    return { ok = true, data = { domain = domain, website = data.browserWebsites[domain] } }
end

handlers['browser:website:get'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local domain = normalizeDomain(payload.domain)
    if not domain then
        return { ok = false, error = 'invalid_domain' }
    end

    local reserved = getReservedDomainInfo(domain)
    if reserved and reserved.type == 'government' then
        local siteState = {}
        if GetResourceState('pf-government') == 'started' then
            local ok, exported = pcall(function() return exports['pf-government']:GetWebsiteState() end)
            if ok and type(exported) == 'table' then
                siteState = exported
            end
        end
        return { ok = true, data = { domain = domain, kind = 'government', editable = false, state = siteState } }
    end

    local record = getDomainOwnerRecord(data, domain)
    if not record then
        return { ok = false, error = 'domain_not_found' }
    end

    local state = ensureWebsiteForDomain(data, record)
    saveData()

    return {
        ok = true,
        data = {
            domain = domain,
            kind = 'player',
            editable = identifier ~= nil and record.ownerIdentifier == identifier,
            ownerIdentifier = record.ownerIdentifier,
            ownerName = record.ownerName,
            state = state
        }
    }
end

handlers['browser:website:save'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local domain = normalizeDomain(payload.domain)
    if not domain or type(payload.state) ~= 'table' then
        return { ok = false, error = 'invalid_payload' }
    end

    local record = getDomainOwnerRecord(data, domain)
    if not record then
        return { ok = false, error = 'domain_not_found' }
    end
    if record.ownerIdentifier ~= identifier then
        return { ok = false, error = 'not_owner' }
    end

    payload.state.domain = domain
    payload.state.owner = payload.state.owner or {}
    payload.state.owner.identifier = record.ownerIdentifier
    payload.state.owner.name = record.ownerName
    payload.state.updatedAt = nowIso()

    data.browserWebsites[domain] = payload.state
    saveData()
    return { ok = true, data = payload.state }
end

handlers['browser:domain:transfer'] = function(payload, src)
    local data = loadData()
    local identifier = GetPlayerIdentifier(src)
    local domain = normalizeDomain(payload.domain)
    local targetIdentifier = safeString(payload.targetIdentifier)
    local targetName = safeString(payload.targetName)

    if not domain or targetIdentifier == '' then
        return { ok = false, error = 'invalid_payload' }
    end

    local record = getDomainOwnerRecord(data, domain)
    if not record then
        return { ok = false, error = 'domain_not_found' }
    end
    if record.ownerIdentifier ~= identifier then
        return { ok = false, error = 'not_owner' }
    end

    record.ownerIdentifier = targetIdentifier
    record.ownerName = targetName ~= '' and targetName or targetIdentifier

    local site = ensureWebsiteForDomain(data, record)
    if site then
        site.owner = site.owner or {}
        site.owner.identifier = record.ownerIdentifier
        site.owner.name = record.ownerName
        site.updatedAt = nowIso()
    end

    saveData()
    return { ok = true, data = record }
end

handlers['gov:announcements:create'] = function(payload, src)
    -- government staff with the 'laws' permission only; the author is the player, not the payload
    if not govCan(src, 'laws') then
        return { ok = false, error = 'not_authorized' }
    end
    payload.title = cleanText(payload.title, MAX_SUBJECT, 'Announcement')
    payload.body = cleanText(payload.body, MAX_BODY, '')
    payload.author = getPlayerName(src)
    payload.mailbox = 'announcements@los-santos.gov'
    local data = loadData()
    local itemId = nextId('announcements')
    local item = {
        id = itemId,
        title = payload.title,
        body = payload.body,
        author = payload.author,
        createdAt = nowIso()
    }
    data.announcements[#data.announcements + 1] = item

    local emailId = nextId('emails')
    data.emails[#data.emails + 1] = {
        id = emailId,
        mailbox = payload.mailbox or 'admin@los-santos.gov',
        folder = 'inbox',
        from = payload.author or 'Mayor',
        to = payload.mailbox or 'admin@los-santos.gov',
        subject = '[City Hall] ' .. (payload.title or 'Announcement'),
        body = payload.body or '',
        preview = string.sub(payload.body or '', 1, 120),
        time = nowIso(),
        unread = true,
        threadId = emailId
    }

    saveData()
    return { ok = true, data = item }
end

handlers['gov:cityhall:bootstrap'] = function(_, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    local payload = {
        announcements = {},
        laws = {},
        taxes = {},
        budgets = {},
        utilities = { power = { active = 0, delinquent = 0, disconnected = 0 }, water = { active = 0, delinquent = 0, disconnected = 0 }, totalAccounts = 0 },
        delinquentUtilities = {},
        infrastructure = nil
    }

    if GetResourceState('pf-government') == 'started' then
        local okAnnouncements, announcements = pcall(function()
            return exports['pf-government']:GetActiveAnnouncements()
        end)
        if okAnnouncements and type(announcements) == 'table' then
            payload.announcements = announcements
        end

        local okLaws, laws = pcall(function()
            return exports['pf-government']:GetPublicLaws()
        end)
        if okLaws and type(laws) == 'table' then
            payload.laws = laws
        end

        local okTaxes, taxes = pcall(function()
            return exports['pf-government']:GetTaxSchedule()
        end)
        if okTaxes and type(taxes) == 'table' then
            payload.taxes = taxes
        end

        local okBudgets, budgets = pcall(function()
            return exports['pf-government']:GetAllBudgetDetails()
        end)
        if okBudgets and type(budgets) == 'table' then
            payload.budgets = budgets
        end

        local okUtilities, utilities = pcall(function()
            return exports['pf-government']:GetUtilityOverview()
        end)
        if okUtilities and type(utilities) == 'table' then
            payload.utilities = utilities
        end

        local okDelinquent, delinquent = pcall(function()
            return exports['pf-government']:GetUtilityDelinquentAccounts()
        end)
        if okDelinquent and type(delinquent) == 'table' then
            payload.delinquentUtilities = delinquent
        end

        local okInfra, infra = pcall(function()
            return exports['pf-government']:GetWeeklyUpkeepSummary()
        end)
        if okInfra and type(infra) == 'table' then
            payload.infrastructure = infra
        end
    end

    return { ok = true, data = payload }
end

handlers['gov:laws:setDisplay'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, result = pcall(function()
        return exports['pf-government']:SetLawDisplayEnabled(payload.lawId, payload.sourceType or payload.source, payload.enabled == true, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'law_visibility_failed' }
    end

    return { ok = result == true or type(result) == 'table' }
end

handlers['gov:taxes:update'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:SetTaxRate(payload.taxType, payload.rate, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'tax_update_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:taxes:toggle'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:SetTaxEnabled(payload.taxType, payload.enabled == true, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'tax_toggle_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:budgets:update'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:SetDepartmentBudget(payload.department, payload.weeklyBudget, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'budget_update_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:budgets:upgrade'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, result = pcall(function()
        return exports['pf-government']:PurchaseDepartmentUpgrade(payload.department, payload.upgradeKey, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'upgrade_failed' }
    end

    return { ok = success == true, data = result }
end

handlers['gov:budgets:uninstallUpgrade'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, result = pcall(function()
        return exports['pf-government']:UninstallDepartmentUpgrade(payload.department, payload.upgradeKey, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'uninstall_failed' }
    end

    return { ok = success == true, data = result }
end

handlers['gov:utilities:disconnect'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:DisconnectService(payload.propertyType, payload.propertyId, payload.serviceType, actorId, actorName, payload.reason or 'City Hall action')
    end)

    if not ok then
        return { ok = false, error = 'disconnect_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:utilities:restore'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, message = pcall(function()
        return exports['pf-government']:RestoreService(payload.propertyType, payload.propertyId, payload.serviceType, actorId, actorName)
    end)

    if not ok then
        return { ok = false, error = 'restore_failed' }
    end

    return { ok = success == true, message = message }
end

handlers['gov:fines:issue'] = function(payload, src)
    if not isGovAuthorized(src) then
        return { ok = false, error = 'not_authorized' }
    end

    if GetResourceState('pf-government') ~= 'started' then
        return { ok = false, error = 'government_offline' }
    end

    local amount = tonumber(payload.amount)
    local maxFine = tonumber(Config.Government and Config.Government.MaxFine) or 50000
    if not amount or amount ~= amount or amount < 1 or amount > maxFine then
        return { ok = false, error = 'invalid_amount' }
    end
    if type(payload.targetCitizenId) ~= 'string' or #payload.targetCitizenId > 20 then
        return { ok = false, error = 'invalid_target' }
    end
    amount = math.floor(amount)
    local actorId = GetPlayerIdentifier(src)
    local actorName = GetPlayerName(src)
    local ok, success, result = pcall(function()
        return exports['pf-government']:IssueFineImmediate(payload.targetCitizenId, amount, cleanText(payload.description, 200, 'City fine'), actorId, actorName, payload.dueDate)
    end)

    if not ok then
        return { ok = false, error = 'fine_issue_failed' }
    end

    return { ok = success == true, data = result }
end

-- Server-only: pf-government raises it with TriggerEvent. (As a net event, any client could send
-- fake "[City Hall Laws]" emails to every player.)
AddEventHandler('pf-computer:gov:laws:sync', function(payload)
    if type(payload) ~= 'table' or type(payload.law) ~= 'table' then
        return
    end

    syncLawFeed(payload.law)
    createLawAnnouncementEmails(payload.law, payload.action or 'publish')
    saveData()
end)

-- =====================================================
-- BUSINESS MANAGER HANDLERS
-- =====================================================

-- Defined below; declared here because getAuthorizedBusiness calls it (it used to resolve to a
-- missing global and error for every non-boss player whose job is not configured).
local isGovJob

local function getAuthorizedBusiness(src, payload)
    local Player = GetPlayer(src)
    local job, grade = GetPlayerJob(src)
    if not job then
        return nil, nil, nil, { ok = false, error = 'missing_job' }
    end

    -- Check if player is boss or government employee
    local isBoss = Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.isboss or false
    
    -- Check for configured job with specific rules
    local jobConfig = Config.BusinessManager.AllowedJobs[job]
    if jobConfig then
        -- Job is configured - check grade requirement
        if grade < jobConfig.minGrade then
            return nil, nil, nil, { ok = false, error = 'insufficient_grade' }
        end
    else
        -- Job not in configured list: bosses only (government jobs used to get in at grade 0)
        if not isBoss then
            return nil, nil, nil, { ok = false, error = 'job_not_allowed' }
        end
        
        -- Create dynamic config for boss/government jobs
        local label = Player.PlayerData.job.label or job
        local blipColor = isGovJob(job) and 1 or 5
        jobConfig = {
            minGrade = 0,
            businessType = isGovJob(job) and 'government' or 'business',
            businessName = label,
            blipColor = blipColor
        }
    end

    if payload and payload.businessId and payload.businessId ~= job then
        return nil, nil, nil, { ok = false, error = 'job_mismatch' }
    end

    return job, grade, jobConfig
end

-- =====================================================
-- BUSINESS MONEY (pfm-banking society accounts)
-- =====================================================
-- A job business's money is its bank society account (the same account paychecks, the boss menu and
-- the bank use), moved only through the pfm-banking ledger. data.businessAccounts[job].transactions is
-- kept as the Business Manager's history/analytics log; its old `balance` field is no longer used
-- (MigrateBusinessAccountsToBank moves the player-funded part of it into the bank once).

local function bizBankReady()
    if GetResourceState('pfm-banking') ~= 'started' then return false end
    local ok, ready = pcall(function() return exports['pfm-banking']:IsLedgerReady() end)
    return ok and ready == true
end

local function bizTransfer(opts)
    local ok, res = pcall(function() return exports['pfm-banking']:Transfer(opts) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'bank_unavailable' } end
    return res
end

local function bizKey(prefix)
    local ok, key = pcall(function() return exports['pfm-banking']:LedgerAutoKey(prefix) end)
    if ok and type(key) == 'string' then return key end
    return ('%s:%d:%d'):format(prefix, os.time(), math.random(1, 1000000000))
end

local function ensureBusinessBankAccount(job)
    local ok, exists = pcall(function() return exports['pfm-banking']:EnsureSocietyAccount(job) end)
    return ok and exists == true
end

--- The business's bank balance, or nil when the bank cannot be read.
local function businessBalance(job)
    if GetResourceState('pfm-banking') ~= 'started' then return nil end
    local ok, balance = pcall(function() return exports['pfm-banking']:GetAccountBalance(job) end)
    if not ok then return nil end
    return tonumber(balance) or 0
end

local function businessHistory(job)
    local data = loadData()
    data.businessAccounts = data.businessAccounts or {}
    local account = data.businessAccounts[job] or { transactions = {} }
    account.transactions = account.transactions or {}
    data.businessAccounts[job] = account
    return account
end

--- Appends an entry to the business history log (no money moves here) and saves.
local function logBusinessTx(job, entry)
    local account = businessHistory(job)
    entry.date = entry.date or nowIso()
    entry.balanceAfter = businessBalance(job)
    table.insert(account.transactions, 1, entry)
    saveData()
end

--- What the Business Manager shows as the company account: the bank balance plus the history log.
local function businessAccountView(job)
    local account = businessHistory(job)
    return { balance = businessBalance(job) or 0, transactions = account.transactions }
end

local function getWageCap(level)
    local data = loadData()
    if data.wageCaps[tostring(level)] then
        return data.wageCaps[tostring(level)]
    end
    return Config.BusinessManager.WageCaps[tostring(level)] or 0
end

function isGovJob(job)
    if job == 'mayor' then
        return true
    end
    for _, name in ipairs(Config.GovJobs or {}) do
        if name == job then
            return true
        end
    end
    return false
end

-- Calculate business statistics from transactions
local function calculateBusinessStats(businessId, transactions)
    local now = os.time()
    local stats = {
        today = { sales = 0, transactions = 0, revenue = 0 },
        week = { sales = 0, transactions = 0, revenue = 0 },
        month = { sales = 0, transactions = 0, revenue = 0 }
    }

    for _, tx in ipairs(transactions) do
        if tx.businessId == businessId then
            -- Parse ISO timestamp to get transaction time
            local txTime = 0
            if tx.timestamp then
                txTime = tonumber(tx.timestamp)
            elseif tx.createdAt then
                -- Parse ISO timestamp (e.g., "2024-01-15T12:30:45Z")
                -- This is a simplified conversion; a more robust solution would use a datelib
                local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
                local year, month, day, hour, min, sec = tx.createdAt:match(pattern)
                if year then
                    txTime = os.time({year=tonumber(year), month=tonumber(month), day=tonumber(day), 
                                     hour=tonumber(hour), min=tonumber(min), sec=tonumber(sec)})
                end
            end
            
            local timeDiff = now - txTime

            -- 24 hours = 86400 seconds
            if timeDiff <= 86400 then
                stats.today.revenue = stats.today.revenue + (tx.total or 0)
                stats.today.transactions = stats.today.transactions + 1
                stats.today.sales = stats.today.sales + (tx.quantity or #(tx.items or {}))
                stats.week.revenue = stats.week.revenue + (tx.total or 0)
                stats.week.transactions = stats.week.transactions + 1
                stats.week.sales = stats.week.sales + (tx.quantity or #(tx.items or {}))
            -- 7 days = 604800 seconds
            elseif timeDiff <= 604800 then
                stats.week.revenue = stats.week.revenue + (tx.total or 0)
                stats.week.transactions = stats.week.transactions + 1
                stats.week.sales = stats.week.sales + (tx.quantity or #(tx.items or {}))
            -- 30 days = 2592000 seconds
            elseif timeDiff <= 2592000 then
                stats.month.revenue = stats.month.revenue + (tx.total or 0)
                stats.month.transactions = stats.month.transactions + 1
                stats.month.sales = stats.month.sales + (tx.quantity or #(tx.items or {}))
            end
        end
    end

    return stats
end

-- =====================================================
-- EXTERNAL DATA PROVIDER SYSTEM
-- =====================================================

-- Map of job names to their data provider resources
local JobDataProviders = {
    mechanic = 'pf-mechanicjob',
    mechanic2 = 'pf-mechanicjob',
    mechanic3 = 'pf-mechanicjob',
    bennys = 'pf-mechanicjob',
    beeker = 'pf-mechanicjob',
    -- Add more mappings as needed:
    -- burgershot = 'pf-restaurant',
    -- uwu = 'pf-restaurant',
}

-- Helper: Check if job has an external data provider
local function GetDataProvider(job)
    local resource = JobDataProviders[job]
    if not resource then
        print(string.format('[pf-computer DEBUG] No provider mapped for job: %s', job))
        return nil
    end
    
    if GetResourceState(resource) ~= 'started' then
        print(string.format('[pf-computer DEBUG] Provider resource %s not started', resource))
        return nil
    end
    
    -- Check if resource exports the required functions
    local hasExports = pcall(function()
        return exports[resource].GetBusinessConfig
    end)
    
    if not hasExports then
        print(string.format('[pf-computer DEBUG] Provider %s has no exports', resource))
        return nil
    end
    
    print(string.format('[pf-computer DEBUG] Found valid provider %s for job %s', resource, job))
    return resource
end

-- Helper: Get data from external provider or fallback to internal
local function GetExternalOrInternal(job, dataType, ...)
    local provider = GetDataProvider(job)
    local args = { ... }
    
    if not provider then
        print(string.format('[pf-computer DEBUG] No provider available for %s (%s)', job, dataType))
        return nil, false -- No external provider
    end
    
    local success, result = pcall(function()
        if dataType == 'config' then
            return exports[provider]:GetBusinessConfig(job, table.unpack(args))
        elseif dataType == 'transactions' then
            return exports[provider]:GetBusinessTransactions(job, table.unpack(args))
        elseif dataType == 'analytics' then
            return exports[provider]:GetBusinessAnalytics(job, table.unpack(args))
        elseif dataType == 'employees' then
            return exports[provider]:GetBusinessEmployees(job, table.unpack(args))
        elseif dataType == 'inventory' then
            return exports[provider]:GetBusinessInventory(job, table.unpack(args))
        elseif dataType == 'menuItems' then
            return exports[provider]:GetMenuItems(job, table.unpack(args))
        elseif dataType == 'menuCategories' then
            return exports[provider]:GetMenuCategories(job, table.unpack(args))
        end
    end)
    
    if success and result then
        print(string.format('[pf-computer] Using external data from %s for %s (%s)', provider, job, dataType))
        return result, true -- External data available
    else
        local errMsg = result or 'Unknown error'
        print(string.format('[pf-computer DEBUG] External call failed for %s (%s): %s', job, dataType, tostring(errMsg)))
    end
    
    return nil, false -- External call failed, use internal
end

-- Get business config for player's job
handlers['business:getConfig'] = function(payload, src)
    local job, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not job then
        return errorResult
    end

    -- Try to get config from external data provider
    local externalConfig, hasExternal = GetExternalOrInternal(job, 'config', src)
    if hasExternal and externalConfig then
        return {
            ok = true,
            data = externalConfig,
            source = 'external'
        }
    end

    -- Fallback to internal data
    local data = loadData()
    local businessType = Config.BusinessManager.BusinessTypes[jobConfig.businessType]
    local settings = data.businesses[job] and data.businesses[job].settings or {}

    return {
        ok = true,
        data = {
            job = job,
            businessName = settings.name or jobConfig.businessName,
            logoUrl = settings.logoUrl or nil,
            businessType = jobConfig.businessType,
            businessTypeConfig = businessType,
            blipColor = settings.blipColor or jobConfig.blipColor,
            blipCoords = settings.blipCoords or nil
        },
        source = 'internal'
    }
end

-- Get business data (overview, stats, etc.)
handlers['business:getData'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try to get analytics from external data provider
    local externalAnalytics, hasExternal = GetExternalOrInternal(businessId, 'analytics', payload.period)
    if hasExternal and externalAnalytics then
        return {
            ok = true,
            data = {
                id = businessId,
                stats = externalAnalytics,
                totalRevenue = externalAnalytics.allTime and externalAnalytics.allTime.revenue or 0,
                totalTransactions = externalAnalytics.allTime and externalAnalytics.allTime.sales or 0
            },
            source = 'external'
        }
    end

    -- Fallback to internal data
    local data = loadData()
    
    -- Initialize business data if doesn't exist
    if not data.businesses[businessId] then
        data.businesses[businessId] = {
            id = businessId,
            totalRevenue = 0,
            totalTransactions = 0,
            employeeCount = 0,
            createdAt = nowIso(),
            stats = {
                today = { sales = 0, transactions = 0, revenue = 0 },
                week = { sales = 0, transactions = 0, revenue = 0 },
                month = { sales = 0, transactions = 0, revenue = 0 }
            },
            settings = {
                name = Config.BusinessManager.AllowedJobs[businessId] and Config.BusinessManager.AllowedJobs[businessId].businessName or businessId,
                blipColor = Config.BusinessManager.AllowedJobs[businessId] and Config.BusinessManager.AllowedJobs[businessId].blipColor or nil
            }
        }
        saveData()
    end

    -- Calculate fresh statistics from transactions
    local businessData = data.businesses[businessId]
    businessData.stats = calculateBusinessStats(businessId, data.businessTransactions or {})
    
    return { ok = true, data = businessData, source = 'internal' }
end

-- Get analytics data
handlers['business:analytics'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try to get analytics from external data provider
    local externalAnalytics, hasExternal = GetExternalOrInternal(businessId, 'analytics', payload.period)
    if hasExternal and externalAnalytics then
        return {
            ok = true,
            data = externalAnalytics,
            source = 'external'
        }
    end

    -- Pull from REAL company account data
    local data = loadData()
    data.businessAccounts = data.businessAccounts or {}
    
    local account = data.businessAccounts[businessId]
    local transactions = account and account.transactions or {}
    
    local period = payload.period or 'week' -- day, week, month
    
    -- Initialize analytics
    local analytics = {
        totalSales = 0,
        totalRevenue = 0,
        transactionCount = 0,
        averageTicket = 0,
        topItems = {
            { name = 'Tire Replacement', count = 0, revenue = 0 },
            { name = 'Oil Change', count = 0, revenue = 0 },
            { name = 'Battery Service', count = 0, revenue = 0 },
        },
        salesByHour = {},
        salesByDay = {},
        revenueGrowth = 0
    }
    
    -- Calculate from REAL transactions
    local salesCount = 0
    for _, tx in ipairs(transactions) do
        if tx.type == 'sale' then
            analytics.totalRevenue = analytics.totalRevenue + (tx.amount or 0)
            salesCount = salesCount + 1
        end
    end
    
    analytics.totalSales = salesCount
    analytics.transactionCount = #transactions
    
    if salesCount > 0 then
        analytics.averageTicket = analytics.totalRevenue / salesCount
    end
    
    -- Generate realistic chart data based on transaction dates
    local dateHourMap = {}
    local dateDayMap = {}
    
    for _, tx in ipairs(transactions) do
        if tx.date and tx.type == 'sale' then
            -- Parse date (ISO8601 format)
            local hour = tonumber(tx.date:match('T(%d+):') or 0)
            local dayOfMonth = tonumber(tx.date:match('-(%d+)T') or 0)
            
            if hour then
                dateHourMap[hour] = (dateHourMap[hour] or 0) + (tx.amount or 0)
            end
            if dayOfMonth then
                dateDayMap[dayOfMonth] = (dateDayMap[dayOfMonth] or 0) + (tx.amount or 0)
            end
        end
    end
    
    -- Build chart data based on period
    if period == 'day' then
        for hour = 0, 23 do
            analytics.salesByHour[hour + 1] = dateHourMap[hour] or 0
        end
    elseif period == 'week' then
        local days = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'}
        -- Note: This is simplified; a proper implementation would calculate actual weekdays
        for i, day in ipairs(days) do
            analytics.salesByDay[i] = {
                day = day,
                sales = (i <= salesCount) and 1 or 0,
                revenue = (dateHourMap[(i-1) * 3] or 0)  -- Rough approximation
            }
        end
    elseif period == 'month' then
        for day = 1, 31 do
            analytics.salesByDay[day] = {
                day = tostring(day),
                sales = (dateDayMap[day] and 1 or 0),
                revenue = (dateDayMap[day] or 0)
            }
        end
    end
    
    return { ok = true, data = analytics }
end

-- Company Account Handlers
handlers['business:account:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    return { ok = true, data = businessAccountView(businessId) }
end

-- A valid amount: finite, positive, at most 2 decimals; nil otherwise.
local function moneyAmount(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n <= 0 or n > 1000000000 then return nil end
    n = math.floor(n * 100 + 0.5) / 100
    if n <= 0 then return nil end
    return n
end

local function bizMoneyError(res)
    if res.error == 'insufficient_funds' then return 'insufficient_funds' end
    if res.error == 'ledger_unavailable' or res.error == 'bank_unavailable' then return 'bank_unavailable' end
    return 'payment_failed'
end

handlers['business:account:deposit'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local amount = moneyAmount(payload.amount)
    if not amount then
        return { ok = false, error = 'invalid_amount' }
    end
    local description = tostring(payload.description or 'Deposit'):sub(1, 100)

    local citizenid = GetPlayerIdentifier(src)
    if not citizenid then
        return { ok = false, error = 'player_not_found' }
    end
    if not bizBankReady() or not ensureBusinessBankAccount(businessId) then
        return { ok = false, error = 'bank_unavailable' }
    end

    -- one ledger transfer: the player's bank -> the business's bank society account
    local res = bizTransfer({
        from = ('player:%s:bank'):format(citizenid), to = 'society:' .. businessId, amount = amount,
        key = bizKey('bizdep'), kind = 'deposit', reason = 'Company account deposit', actor = citizenid,
    })
    if not res.ok then
        return { ok = false, error = bizMoneyError(res) }
    end

    logBusinessTx(businessId, { type = 'deposit', amount = amount, description = description, processedBy = citizenid, txId = res.txId })
    return { ok = true, data = businessAccountView(businessId) }
end

handlers['business:account:withdraw'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- The company account is the job's bank account (wages, sales); like the bank and the boss menu,
    -- only the boss may take money out of it.
    local Player = GetPlayer(src)
    if not (Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.isboss == true) then
        return { ok = false, error = 'not_boss' }
    end

    local amount = moneyAmount(payload.amount)
    if not amount then
        return { ok = false, error = 'invalid_amount' }
    end
    local description = tostring(payload.description or 'Withdrawal'):sub(1, 100)

    local citizenid = GetPlayerIdentifier(src)
    if not citizenid then
        return { ok = false, error = 'player_not_found' }
    end
    if not bizBankReady() then
        return { ok = false, error = 'bank_unavailable' }
    end

    local res = bizTransfer({
        from = 'society:' .. businessId, to = ('player:%s:bank'):format(citizenid), amount = amount,
        key = bizKey('bizwd'), kind = 'withdraw', reason = 'Company account withdrawal', actor = citizenid,
    })
    if not res.ok then
        return { ok = false, error = bizMoneyError(res) }
    end

    logBusinessTx(businessId, { type = 'withdrawal', amount = amount, description = description, processedBy = citizenid, txId = res.txId })
    return { ok = true, data = businessAccountView(businessId) }
end

-- Supplies Ordering Handlers
local function normalizeSuppliesItem(raw)
    local label = raw.label or raw.name or raw.item or raw.id or 'Item'
    local itemId = raw.item or raw.id or (label:gsub('%s+', '_'):lower())
    local category = raw.category or 'General'
    local caseSize = tonumber(raw.caseSize or raw.case_size) or 10
    local pricePerCase = tonumber(raw.pricePerCase or raw.casePrice or raw.cost or raw.price) or 0
    local caseContents = raw.caseContents or (tostring(caseSize) .. 'x ' .. label)

    return {
        item = itemId,
        label = label,
        category = category,
        caseSize = caseSize,
        caseContents = caseContents,
        pricePerCase = pricePerCase,
        image = raw.image
    }
end

local function buildSuppliesCatalog(businessId, src)
    local catalog = {
        items = {},
        categories = {},
        imageBase = 'https://cfx-nui-qb-inventory/html/images/'
    }

    local configResult, hasExternal = GetExternalOrInternal(businessId, 'config', src)
    local sourceCatalog = configResult and (configResult.suppliesCatalog or (configResult.businessTypeConfig and configResult.businessTypeConfig.suppliesCatalog))

    if sourceCatalog and sourceCatalog.items then
        catalog.imageBase = sourceCatalog.imageBase or catalog.imageBase
        for _, raw in ipairs(sourceCatalog.items) do
            catalog.items[#catalog.items + 1] = normalizeSuppliesItem(raw)
        end
        if sourceCatalog.categories then
            catalog.categories = sourceCatalog.categories
        end
    else
        local businessTypeConfig = configResult and configResult.businessTypeConfig or nil
        local fallbackItems = (businessTypeConfig and (businessTypeConfig.parts or businessTypeConfig.ingredients)) or {}
        for _, raw in ipairs(fallbackItems) do
            catalog.items[#catalog.items + 1] = normalizeSuppliesItem(raw)
        end
    end

    if #catalog.categories == 0 then
        local seen = {}
        for _, item in ipairs(catalog.items) do
            if item.category and not seen[item.category] then
                seen[item.category] = true
                catalog.categories[#catalog.categories + 1] = { id = item.category, label = item.category }
            end
        end
    end

    -- Apply government business license gates when available (ex: tuning).
    if GetResourceState('pf-government') == 'started' then
        local success, licenses = pcall(function()
            return exports['pf-government']:GetBusinessLicenses(businessId)
        end)

        local licenseFlags = {}
        if success and type(licenses) == 'table' then
            for _, license in ipairs(licenses) do
                if tonumber(license.active or 0) == 1 or license.active == true then
                    licenseFlags[tostring(license.license_key or ''):lower()] = true
                end
            end
        end

        if not licenseFlags['tuning_license'] then
            catalog.items = (catalog.items or {})
            local filtered = {}
            for _, item in ipairs(catalog.items) do
                if tostring(item.category or ''):lower() ~= 'tuning' then
                    filtered[#filtered + 1] = item
                end
            end
            catalog.items = filtered

            local catFiltered = {}
            for _, category in ipairs(catalog.categories or {}) do
                local catId = tostring(category.id or category.label or ''):lower()
                if catId ~= 'tuning' then
                    catFiltered[#catFiltered + 1] = category
                end
            end
            catalog.categories = catFiltered
        end
    end

    return catalog
end

local function calculateSupplyOrderTimeline(caseCount)
    -- Default timing - change these for faster/slower orders
    -- Reduced to 5 seconds each for testing/development
    local baseSorting = 5
    local basePacking = 5
    local baseReady = 5
    local perCase = 0

    -- Try to get timing from pf-mechanicjob config
    local resourceName = 'pf-mechanicjob'
    if GetResourceState(resourceName) == 'started' then
        local success, config = pcall(function()
            return exports[resourceName]:GetBusinessConfig()
        end)
        if success and config and config.suppliesOrder and config.suppliesOrder.timing then
            local timing = config.suppliesOrder.timing
            baseSorting = timing.baseSorting or baseSorting
            basePacking = timing.basePacking or basePacking
            baseReady = timing.baseReady or baseReady
            perCase = timing.perCase or perCase
        end
    end

    local nowTs = os.time()
    local sortingAt = nowTs + baseSorting + (caseCount * perCase)
    local packingAt = sortingAt + basePacking + (caseCount * perCase)
    local readyAt = packingAt + baseReady

    return {
        orderedAt = nowTs,
        sortingAt = sortingAt,
        packingAt = packingAt,
        readyAt = readyAt
    }
end

local function getOrderStatus(order, nowTs)
    if order.pickedUp then
        return 'picked_up'
    end
    if nowTs >= (order.timeline and order.timeline.readyAt or 0) then
        return 'ready'
    end
    if nowTs >= (order.timeline and order.timeline.packingAt or 0) then
        return 'packing'
    end
    if nowTs >= (order.timeline and order.timeline.sortingAt or 0) then
        return 'sorting'
    end
    return 'ordered'
end

-- =====================================================
-- STORE SUPPLIES (pf-stores)
-- =====================================================
-- Player-owned stores are owned by a citizen, not a job. Their supply orders go through pf-stores'
-- exports, which charge the store's bank account (pfm-banking ledger); the JSON business accounts in
-- this resource's data file are never used for stores.
-- payload.mode: 'store' or 'job' picks the business when a player has both; without it a player with
-- an authorised job business gets that, otherwise their store.

local function storeCall(fnName, src, payload)
    if GetResourceState('pf-stores') ~= 'started' then return { ok = false, error = 'stores_offline' } end
    local ok, res = pcall(function() return exports['pf-stores'][fnName](exports['pf-stores'], src, payload) end)
    if not ok or type(res) ~= 'table' then return { ok = false, error = 'stores_unavailable' } end
    return res
end

-- Returns the store this request is about (owned by the player) and the list of their stores.
local function resolveStoreContext(src, payload)
    if GetResourceState('pf-stores') ~= 'started' then return nil, {} end
    local res = storeCall('ListOwnedStores', src, {})
    local stores = (res.ok and res.data and res.data.stores) or {}
    if #stores == 0 then return nil, stores end
    local wanted = payload and payload.storeId and tostring(payload.storeId) or nil
    for _, s in ipairs(stores) do
        if wanted and s.storeId == wanted then return s, stores end
    end
    return stores[1], stores
end

-- Decides which business the Order Supplies request is for. Returns 'store', store, stores or
-- 'job', businessId, nil (or nil, errorResult).
local function resolveSuppliesBusiness(src, payload)
    local mode = payload and payload.mode or nil
    local store, stores = resolveStoreContext(src, payload)
    if mode == 'store' then
        if not store then return nil, { ok = false, error = 'no_store' } end
        return 'store', store, stores
    end
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if businessId then return 'job', businessId, stores end
    if mode ~= 'job' and store then return 'store', store, stores end
    return nil, errorResult
end

-- supply order statuses (pf-stores order service) -> the app's statuses. The app keeps its labels;
-- the order's own status is sent along as `orderStatus` for anything that wants the detail.
local STORE_ORDER_STATUS = {
    created = 'pending', paid = 'pending',
    ready = 'ready',                         -- paid, waiting for the owner to collect
    awaiting_supplier = 'pending', awaiting_delivery = 'pending',
    assigned = 'in_transit', in_transit = 'in_transit',
    delivered = 'delivered',                 -- on the pallet at the store, not unpacked yet
    unpacked = 'picked_up',
    cancelled = 'cancelled', failed = 'failed',
}
local CANCELLABLE = { awaiting_supplier = true, awaiting_delivery = true }

local function storeCatalog(src, store)
    local res = storeCall('GetOrderSuppliesConfig', src, { storeId = store.storeId })
    if not res.ok then return nil, res end
    local data = res.data or {}
    local catalog = { items = {}, categories = {}, imageBase = 'https://cfx-nui-qb-inventory/html/images/' }
    local seen = {}
    for _, ing in ipairs((data.businessTypeConfig and data.businessTypeConfig.ingredients) or {}) do
        local category = ing.category or 'Supplies'
        catalog.items[#catalog.items + 1] = {
            item = ing.name, label = ing.label or ing.name, category = category,
            caseSize = 1, caseContents = '1 case', pricePerCase = tonumber(ing.cost) or 0,
            stock = tonumber(ing.stock) or 0,
        }
        if not seen[category] then
            seen[category] = true
            catalog.categories[#catalog.categories + 1] = { id = category, label = category }
        end
    end
    local trucking = data.delivery and data.delivery.trucking or {}
    return catalog, nil, { businessName = data.businessName or store.label, deliveryAvailable = trucking.available == true }
end

local function storeBalance(src, store)
    local res = storeCall('GetStoreBalance', src, { storeId = store.storeId })
    return res.ok and res.data and tonumber(res.data.balance) or nil
end

local function storeOrders(src, store)
    local res = storeCall('ListSupplyOrders', src, { storeId = store.storeId })
    if not res.ok then return nil, res end
    local formatted = {}
    for _, o in ipairs((res.data and res.data.orders) or {}) do
        formatted[#formatted + 1] = {
            id = o.id,
            createdAt = o.createdAt,
            status = STORE_ORDER_STATUS[o.status] or o.status,
            orderStatus = o.status,
            fulfillment = o.method == 'trucking' and 'delivery' or 'pickup',
            total = tonumber(o.total) or 0,
            totalCases = o.totalCases or 0,
            items = o.items or {},
            cancellable = o.method == 'trucking' and CANCELLABLE[o.status] == true,
        }
    end
    return formatted
end

handlers['business:supplies:catalog'] = function(payload, src)
    local mode, business, stores = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end

    if mode == 'store' then
        local catalog, err, meta = storeCatalog(src, business)
        if not catalog then return err end
        return {
            ok = true,
            data = {
                mode = 'store',
                storeId = business.storeId,
                stores = stores,
                businessId = business.storeId,
                businessName = meta.businessName,
                businessType = 'store',
                balance = storeBalance(src, business),
                deliveryAvailable = meta.deliveryAvailable,
                canSwitch = getAuthorizedBusiness(src, {}) ~= nil,
                catalog = catalog,
            }
        }
    end

    local businessId = business

    local catalog = buildSuppliesCatalog(businessId, src)
    local configResult = GetExternalOrInternal(businessId, 'config', src)

    return {
        ok = true,
        data = {
            mode = 'job',
            businessId = businessId,
            businessName = configResult and configResult.businessName or businessId,
            businessType = configResult and configResult.businessType or 'business',
            canSwitch = stores ~= nil and #stores > 0,
            catalog = catalog
        }
    }
end

handlers['business:supplies:orders:list'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end
    if mode == 'store' then
        local orders, err = storeOrders(src, business)
        if not orders then return err end
        return { ok = true, data = orders, balance = storeBalance(src, business) }
    end
    local businessId = business

    local data = loadData()
    data.businessOrders = data.businessOrders or {}
    local orders = data.businessOrders[businessId] or {}
    local nowTs = os.time()

    local formatted = {}
    for _, order in ipairs(orders) do
        local status = getOrderStatus(order, nowTs)
        formatted[#formatted + 1] = {
            id = order.id,
            createdAt = order.createdAt,
            status = status,
            fulfillment = order.fulfillment,
            total = order.total,
            totalCases = order.totalCases,
            items = order.items,
            timeline = order.timeline,
            pickedUpAt = order.pickedUpAt
        }
    end

    return { ok = true, data = formatted }
end

handlers['business:supplies:orders:create'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end

    if mode == 'store' then
        -- pf-stores prices the cart from its own catalog and charges the store's bank account
        local cart = {}
        for _, req in ipairs(type(payload.items) == 'table' and payload.items or {}) do
            if type(req) == 'table' and req.item then
                cart[#cart + 1] = { name = tostring(req.item), quantity = tonumber(req.quantity) or 0 }
            end
        end
        if #cart == 0 then return { ok = false, error = 'empty_cart' } end
        local method = payload.fulfillment == 'delivery' and 'trucking' or 'pickup'
        local res = storeCall('CheckoutSupplies', src, { storeId = business.storeId, method = method, cart = cart })
        if not res.ok then return res end
        return { ok = true, data = res.data, message = res.message, balance = storeBalance(src, business) }
    end

    local businessId = business
    -- spending a job business's bank account is for its boss
    local orderer = GetPlayer(src)
    if not (orderer and orderer.PlayerData and orderer.PlayerData.job and orderer.PlayerData.job.isboss == true) then
        return { ok = false, error = 'not_authorized' }
    end

    local fulfillment = payload.fulfillment or 'pickup'
    if fulfillment ~= 'pickup' then
        return { ok = false, error = 'delivery_unavailable' }
    end

    local catalog = buildSuppliesCatalog(businessId, src)
    local catalogMap = {}
    for _, item in ipairs(catalog.items) do
        catalogMap[item.item] = item
    end

    local items = payload.items or {}
    if type(items) ~= 'table' or #items == 0 then
        return { ok = false, error = 'empty_cart' }
    end

    local orderItems = {}
    local total = 0
    local totalCases = 0

    for _, req in ipairs(items) do
        local itemId = type(req) == 'table' and req.item or nil
        local qty = type(req) == 'table' and tonumber(req.quantity) or 0
        if not qty or qty ~= qty or qty ~= math.floor(qty) or qty > 1000 then qty = 0 end
        local catalogItem = itemId and catalogMap[itemId]
        if catalogItem and qty > 0 then
            local lineTotal = (catalogItem.pricePerCase or 0) * qty
            total = total + lineTotal
            totalCases = totalCases + qty
            orderItems[#orderItems + 1] = {
                item = catalogItem.item,
                label = catalogItem.label,
                category = catalogItem.category,
                caseSize = catalogItem.caseSize,
                caseContents = catalogItem.caseContents,
                pricePerCase = catalogItem.pricePerCase,
                quantity = qty,
                lineTotal = lineTotal
            }
        end
    end

    if #orderItems == 0 then
        return { ok = false, error = 'invalid_items' }
    end

    -- Paid from the business's bank society account through the ledger.
    if total > 0 then
        if not bizBankReady() or not ensureBusinessBankAccount(businessId) then
            return { ok = false, error = 'bank_unavailable' }
        end
        local charge = bizTransfer({
            from = 'society:' .. businessId, to = 'system:pf-computer-supplier', amount = total,
            key = bizKey('bizsupply'), kind = 'supplies', reason = 'Supplies order', actor = GetPlayerIdentifier(src),
        })
        if not charge.ok then
            return { ok = false, error = bizMoneyError(charge) }
        end
        logBusinessTx(businessId, { type = 'supplies', amount = total, description = 'Supplies Order', txId = charge.txId })
    end

    local data = loadData()
    data.businessOrders = data.businessOrders or {}

    -- Get saved delivery location for this business
    data.businessDeliveryLocations = data.businessDeliveryLocations or {}
    local deliveryLocation = data.businessDeliveryLocations[businessId]

    local orderId = nextId('businessOrders')
    local timeline = calculateSupplyOrderTimeline(totalCases)
    local order = {
        id = orderId,
        createdAt = nowIso(),
        fulfillment = fulfillment,
        total = total,
        totalCases = totalCases,
        items = orderItems,
        timeline = timeline,
        pickedUp = false,
        deliveryLocation = deliveryLocation -- Include saved delivery location
    }

    data.businessOrders[businessId] = data.businessOrders[businessId] or {}
    table.insert(data.businessOrders[businessId], 1, order)
    saveData()

    return { ok = true, data = order }
end

handlers['business:supplies:orders:cancel'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end
    if mode ~= 'store' then
        return { ok = false, error = 'not_cancellable' }
    end
    local res = storeCall('CancelSupplyOrder', src, { storeId = business.storeId, orderId = tonumber(payload.orderId) })
    if not res.ok then return res end
    return { ok = true, data = res.data, balance = storeBalance(src, business) }
end

handlers['business:supplies:orders:pickup'] = function(payload, src)
    local mode, business = resolveSuppliesBusiness(src, payload)
    if not mode then
        return business
    end
    if mode == 'store' then
        -- a paid order waiting at the supplier goes straight into the store's stock
        return storeCall('DeliverSupplyOrder', src, { storeId = business.storeId, orderId = tonumber(payload.orderId) })
    end
    local businessId = business

    local orderId = tonumber(payload.orderId)
    if not orderId then
        return { ok = false, error = 'invalid_order' }
    end

    local data = loadData()
    data.businessOrders = data.businessOrders or {}
    local orders = data.businessOrders[businessId] or {}

    for _, order in ipairs(orders) do
        if order.id == orderId then
            local status = getOrderStatus(order, os.time())
            if status ~= 'ready' then
                return { ok = false, error = 'order_not_ready' }
            end

            if GetResourceState('pf-mechanicjob') ~= 'started' then
                return { ok = false, error = 'mechanic_resource_offline' }
            end

            print('^3[pf-computer]^7 Triggering pickup mission for player: ' .. src .. ' | Order: ' .. orderId)
            local called, missionOk, missionReason = pcall(function()
                return exports['pf-mechanicjob']:StartSuppliesPickup(src, order)
            end)

            if not called then
                print('^1[pf-computer]^7 Failed to call StartSuppliesPickup export')
                return { ok = false, error = 'pickup_start_failed' }
            end

            if missionOk ~= true then
                return { ok = false, error = missionReason or 'pickup_start_failed' }
            end

            order.pickupMissionStartedAt = nowIso()
            saveData()
            return { ok = true, data = order }
        end
    end

    return { ok = false, error = 'order_not_found' }
end

-- Server-only (pf-mechanicjob raises it when the pickup mission finishes). It used to be a network
-- event, so any client could mark any job business's orders as picked up.
AddEventHandler('pf-computer:server:supplies:completeOrder', function(playerSrc, orderId)
    local src = tonumber(playerSrc)
    local targetOrderId = tonumber(orderId)
    if not src or not targetOrderId then
        return
    end

    local businessId = GetPlayerJob(src)
    if not businessId then
        return
    end

    local data = loadData()
    data.businessOrders = data.businessOrders or {}
    local orders = data.businessOrders[businessId] or {}

    for _, order in ipairs(orders) do
        if tonumber(order.id) == targetOrderId then
            order.pickedUp = true
            order.pickedUpAt = nowIso()
            order.pickupMissionCompletedAt = nowIso()
            saveData()
            print('^2[pf-computer]^7 Order #' .. tostring(targetOrderId) .. ' marked picked up for ' .. tostring(businessId))
            return
        end
    end

    print('^3[pf-computer]^7 Order completion event received but order not found: ' .. tostring(targetOrderId))
end)

-- List menu items
handlers['business:menu:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try external data provider first (for mechanic jobs)
    local externalMenu, hasExternal = GetExternalOrInternal(businessId, 'menuItems')
    if hasExternal and externalMenu then
        return { ok = true, data = externalMenu }
    end

    -- Fallback to internal data
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    return { ok = true, data = menu }
end

-- Add menu item
handlers['business:menu:add'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local item = payload.item or {}
    
    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database insert
        local success, addResult = pcall(function()
            return exports[provider]:AddMenuItem(businessId, item)
        end)
        
        if success and addResult then
            local resultItem = {
                business = businessId,
                item_id = item.id or item.name or 'item_' .. os.time(),
                category = item.category or 'General',
                name = item.name or 'New Item',
                label = item.name or 'New Item',
                price = tonumber(item.price) or 0
            }
            return { ok = true, data = resultItem }
        else
            local errorMsg = success and tostring(addResult) or tostring(success)
            print(string.format('[ERROR] Failed to add menu item via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_add_item', message = errorMsg }
        end
    end

    -- Fallback to internal data storage
    local data = loadData()
    
    if not data.businessMenus[businessId] then
        data.businessMenus[businessId] = {}
    end
    
    local itemId = nextId('menuItems')
    local menuItem = {
        id = itemId,
        name = item.name or 'New Item',
        description = item.description or '',
        category = item.category or 'General',
        price = item.price or 10.00,
        cost = item.cost or 5.00,
        ingredients = item.ingredients or {},
        image = item.image or '',
        available = item.available ~= false,
        onSale = item.onSale or false,
        salePrice = item.salePrice or nil,
        createdAt = nowIso()
    }
    
    data.businessMenus[businessId][#data.businessMenus[businessId] + 1] = menuItem
    saveData()
    
    return { ok = true, data = menuItem }
end

-- Update menu item
handlers['business:menu:update'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local itemId = payload.itemId

    if not itemId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    local menu = data.businessMenus[businessId] or {}
    for i, item in ipairs(menu) do
        if item.id == itemId then
            -- Update fields
            if payload.name then item.name = payload.name end
            if payload.description then item.description = payload.description end
            if payload.category then item.category = payload.category end
            if payload.price then item.price = payload.price end
            if payload.cost then item.cost = payload.cost end
            if payload.ingredients then item.ingredients = payload.ingredients end
            if payload.available ~= nil then item.available = payload.available end
            if payload.onSale ~= nil then item.onSale = payload.onSale end
            if payload.salePrice then item.salePrice = payload.salePrice end
            
            item.updatedAt = nowIso()
            saveData()
            
            return { ok = true, data = item }
        end
    end
    
    return { ok = false, error = 'item_not_found' }
end

-- Delete menu item
handlers['business:menu:delete'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local itemId = payload.itemId

    if not itemId then
        return { ok = false, error = 'missing_parameters' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database delete
        local success, deleteResult = pcall(function()
            return exports[provider]:DeleteMenuItem(businessId, itemId)
        end)
        
        if success and deleteResult then
            return { ok = true }
        else
            local errorMsg = success and tostring(deleteResult) or tostring(success)
            print(string.format('[ERROR] Failed to delete menu item via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_delete_item', message = errorMsg }
        end
    end

    -- Fallback to internal data storage
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    for i, item in ipairs(menu) do
        if item.id == itemId then
            table.remove(menu, i)
            saveData()
            return { ok = true }
        end
    end
    
    return { ok = false, error = 'item_not_found' }
end

-- =====================================================
-- MEAL ITEMS MANAGEMENT (composite dishes)
-- =====================================================

-- List meal items
handlers['business:meals:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    data.businessMeals = data.businessMeals or {}
    
    local meals = data.businessMeals[businessId] or {}
    return { ok = true, data = meals }
end

-- Add meal item
handlers['business:meals:add'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    data.businessMeals = data.businessMeals or {}
    
    if not data.businessMeals[businessId] then
        data.businessMeals[businessId] = {}
    end
    
    local mealId = nextId('meals')
    local meal = {
        id = mealId,
        name = payload.name or 'New Meal',
        description = payload.description or '',
        items = payload.items or {},
        price = payload.price or 0,
        available = payload.available ~= false,
        createdAt = nowIso()
    }
    
    data.businessMeals[businessId][#data.businessMeals[businessId] + 1] = meal
    saveData()
    
    return { ok = true, data = meal }
end

-- Update meal item
handlers['business:meals:update'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local mealId = payload.mealId

    if not mealId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    data.businessMeals = data.businessMeals or {}
    local meals = data.businessMeals[businessId] or {}
    for i, meal in ipairs(meals) do
        if meal.id == mealId then
            if payload.name then meal.name = payload.name end
            if payload.description then meal.description = payload.description end
            if payload.items then meal.items = payload.items end
            if payload.price then meal.price = payload.price end
            if payload.available ~= nil then meal.available = payload.available end
            
            meal.updatedAt = nowIso()
            saveData()
            
            return { ok = true, data = meal }
        end
    end
    
    return { ok = false, error = 'meal_not_found' }
end

-- Delete meal item
handlers['business:meals:delete'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local mealId = payload.mealId

    if not mealId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    data.businessMeals = data.businessMeals or {}
    local meals = data.businessMeals[businessId] or {}
    for i, meal in ipairs(meals) do
        if meal.id == mealId then
            table.remove(meals, i)
            saveData()
            return { ok = true }
        end
    end
    
    return { ok = false, error = 'meal_not_found' }
end

-- List transactions
handlers['business:transactions:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local limit = payload.limit or 50

    -- Try to get transactions from external data provider
    local externalTransactions, hasExternal = GetExternalOrInternal(businessId, 'transactions', limit)
    if hasExternal and externalTransactions then
        local normalized = {}
        for _, tx in ipairs(externalTransactions) do
            local items = {}
            if tx.items and type(tx.items) == 'table' then
                for _, item in ipairs(tx.items) do
                    items[#items + 1] = {
                        name = item.label or item.item or 'Item',
                        quantity = item.qty or item.quantity or 1,
                        price = item.unitPrice or item.price or 0
                    }
                end
            end

            normalized[#normalized + 1] = {
                id = tx.transaction_id or tx.id,
                date = tx.created_at or tx.createdAt,
                type = tx.type or 'sale',
                items = items,
                itemsCount = #items,
                employee = tx.mechanic_name or tx.employee or tx.processedBy,
                paymentMethod = tx.payment_type or tx.paymentMethod,
                amount = tx.total or tx.amount or 0
            }
        end

        return {
            ok = true,
            data = normalized,
            source = 'external'
        }
    end

    -- Fallback to internal data
    local data = loadData()
    data.businessAccounts = data.businessAccounts or {}
    
    -- Get transactions from company account
    local account = data.businessAccounts[businessId] or {
        balance = 0,
        transactions = {}
    }
    
    local transactions = account.transactions or {}
    
    -- Sort by date descending (most recent first)
    table.sort(transactions, function(a, b)
        return (a.date or '') > (b.date or '')
    end)
    
    -- Format transactions for frontend compatibility
    local formatted = {}
    for i, tx in ipairs(transactions) do
        formatted[i] = {
            id = tx.id or ('tx-' .. i),
            date = tx.date,
            type = tx.type or 'sale',
            amount = tx.amount or 0,
            description = tx.description or '',
            employee = tx.employee or 'System',
            processedBy = tx.processedBy or 'System'
        }
    end
    
    -- Limit results
    local limited = {}
    for i = 1, math.min(limit, #formatted) do
        limited[i] = formatted[i]
    end
    
    return { ok = true, data = limited, source = 'internal' }
end

-- Add transaction
handlers['business:transactions:add'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    
    local txId = nextId('businessTransactions')
    local tx = {
        id = txId,
        businessId = businessId,
        type = payload.type or 'sale', -- sale, refund, expense
        items = payload.items or {},
        subtotal = payload.subtotal or 0,
        tax = payload.tax or 0,
        total = payload.total or 0,
        paymentMethod = payload.paymentMethod or 'cash',
        employee = payload.employee or 'Unknown',
        customer = payload.customer or nil,
        notes = payload.notes or '',
        createdAt = nowIso()
    }
    
    data.businessTransactions[#data.businessTransactions + 1] = tx
    
    -- Update business stats
    if not data.businesses[businessId] then
        data.businesses[businessId] = {
            id = businessId,
            totalRevenue = 0,
            totalTransactions = 0,
            employeeCount = 0,
            createdAt = nowIso(),
            stats = {
                today = { sales = 0, transactions = 0, revenue = 0 },
                week = { sales = 0, transactions = 0, revenue = 0 },
                month = { sales = 0, transactions = 0, revenue = 0 }
            }
        }
    end
    
    data.businesses[businessId].totalRevenue = data.businesses[businessId].totalRevenue + tx.total
    data.businesses[businessId].totalTransactions = data.businesses[businessId].totalTransactions + 1
    
    saveData()
    
    return { ok = true, data = tx }
end

-- List employees
handlers['business:employees:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try to get employees from external data provider
    local externalEmployees, hasExternal = GetExternalOrInternal(businessId, 'employees')
    if hasExternal and externalEmployees then
        return {
            ok = true,
            data = externalEmployees,
            source = 'external'
        }
    end

    -- Fallback to internal data
    local employees = {}
    local foundBoss = false
    
    -- Get all online players with the same job
    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local playerJob, playerGrade = GetPlayerJob(tonumber(playerId))
        if playerJob == businessId then
            local Player = GetPlayer(tonumber(playerId))
            if Player then
                local isBoss = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.isboss or false
                local employeeName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname or 'Unknown'
                local gradeName = Player.PlayerData.job.grade.name or 'Employee'
                
                employees[#employees + 1] = {
                    id = playerId,
                    name = employeeName,
                    rank = gradeName,
                    grade = playerGrade,
                    isBoss = isBoss,
                    isActive = true,
                    salesToday = 0,
                    salesTotal = 0,
                    performance = math.random(60, 100),
                    salary = tonumber(Player.PlayerData.job.payment) or 0
                }
                
                if isBoss then
                    foundBoss = true
                end
            end
        end
    end
    
    -- Sort by: Boss first, then by grade (highest first), then by name
    table.sort(employees, function(a, b)
        if a.isBoss ~= b.isBoss then
            return a.isBoss -- Boss first
        end
        if a.grade ~= b.grade then
            return a.grade > b.grade -- Higher grade first
        end
        return a.name < b.name -- Alphabetical
    end)
    
    return { ok = true, data = employees }
end

-- Update employee (promote/demote/bonus)
handlers['business:employees:update'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local employeeId = payload.employeeId

    if not employeeId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    for i, emp in ipairs(data.businessEmployees) do
        if emp.businessId == businessId and emp.id == employeeId then
            if payload.rank then emp.rank = payload.rank end
            if payload.salary then emp.salary = payload.salary end
            if payload.bonus then
                emp.totalBonus = (emp.totalBonus or 0) + payload.bonus
                emp.lastBonus = { amount = payload.bonus, date = nowIso() }
            end
            emp.updatedAt = nowIso()
            saveData()
            return { ok = true, data = emp }
        end
    end
    
    return { ok = false, error = 'employee_not_found' }
end

-- Fire employee
handlers['business:employees:fire'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local employeeId = payload.employeeId

    if not employeeId then
        return { ok = false, error = 'missing_parameters' }
    end
    
    for i, emp in ipairs(data.businessEmployees) do
        if emp.businessId == businessId and emp.id == employeeId then
            table.remove(data.businessEmployees, i)
            saveData()
            return { ok = true }
        end
    end
    
    return { ok = false, error = 'employee_not_found' }
end

-- Inventory management with stash integration
handlers['business:inventory:get'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local itemName = payload.item
    
    -- Try to get item from external data provider
    local externalInventory, hasExternal = GetExternalOrInternal(businessId, 'inventory')
    if hasExternal and externalInventory then
        -- Find the specific item
        for _, item in ipairs(externalInventory) do
            if item.item == itemName or item.name == itemName then
                return {
                    ok = true,
                    stock = item.stock or item.qty or 0,
                    item = itemName,
                    source = 'external'
                }
            end
        end
        return {
            ok = true,
            stock = 0,
            item = itemName,
            source = 'external'
        }
    end
    
    -- TODO: Integrate with your stash/inventory system
    -- Example for ox_inventory:
    -- local stashId = 'business_' .. businessId
    -- local items = exports.ox_inventory:GetInventory(stashId, false)
    -- Find item count
    
    -- Example for qb-inventory:
    -- local stash = exports['pfm-inventory']:GetStashItems(stashId)
    
    -- For now, return demo data
    return { 
        ok = true, 
        stock = math.random(10, 100),
        item = itemName,
        source = 'internal'
    }
end

handlers['business:inventory:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end
    
    -- Try to get inventory from external data provider
    local externalInventory, hasExternal = GetExternalOrInternal(businessId, 'inventory')
    if hasExternal and externalInventory then
        return {
            ok = true,
            items = externalInventory,
            source = 'external'
        }
    end
    
    -- TODO: Fetch all items from stash
    -- Return list of items with counts
    
    return { 
        ok = true, 
        items = {}, -- Will be populated from stash
        source = 'internal'
    }
end

handlers['business:update:settings'] = function(payload, src)
    local businessId, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local name = payload.name
    local logoUrl = payload.logoUrl
    local blipColor = payload.blipColor
    local blipCoords = payload.blipCoords

    if not data.businesses[businessId] then
        data.businesses[businessId] = {
            id = businessId,
            totalRevenue = 0,
            totalTransactions = 0,
            employeeCount = 0,
            createdAt = nowIso(),
            stats = {
                today = { sales = 0, transactions = 0, revenue = 0 },
                week = { sales = 0, transactions = 0, revenue = 0 },
                month = { sales = 0, transactions = 0, revenue = 0 }
            },
            settings = {}
        }
    end

    data.businesses[businessId].settings = data.businesses[businessId].settings or {}
    if name and name ~= '' then
        data.businesses[businessId].settings.name = name
    end
    if logoUrl ~= nil then  -- Allow empty string to remove logo
        data.businesses[businessId].settings.logoUrl = logoUrl
    end
    if blipColor then
        data.businesses[businessId].settings.blipColor = blipColor
    end
    if type(blipCoords) == 'table' and blipCoords.x and blipCoords.y and blipCoords.z then
        data.businesses[businessId].settings.blipCoords = {
            x = blipCoords.x,
            y = blipCoords.y,
            z = blipCoords.z
        }
    end

    saveData()

    TriggerClientEvent('pf-computer:client:updateBusinessBlip', -1, {
        businessId = businessId,
        name = data.businesses[businessId].settings.name or jobConfig.businessName,
        color = data.businesses[businessId].settings.blipColor or jobConfig.blipColor,
        coords = data.businesses[businessId].settings.blipCoords,
        businessType = jobConfig.businessType,
        sprite = jobConfig.blipSprite
    })

    return { ok = true }
end

-- Wage settings for bosses
handlers['business:wages:get'] = function(payload, src)
    local Player = GetPlayer(src)
    if not Player or not Player.PlayerData.job.isboss then
        return { ok = false, error = 'not_boss' }
    end

    local job = Player.PlayerData.job.name
    local jobData = QBCore.Shared.Jobs[job]
    if not jobData then
        return { ok = false, error = 'job_not_found' }
    end

    local data = loadData()
    data.businessWages[job] = data.businessWages[job] or {}

    local grades = {}
    for grade, gradeInfo in pairs(jobData.grades or {}) do
        local level = tostring(grade)
        local defaultPay = gradeInfo.payment or 0
        local wage = data.businessWages[job][level] or defaultPay
        grades[#grades + 1] = {
            level = tonumber(level) or 0,
            label = gradeInfo.name or ('Grade ' .. level),
            wage = wage,
            cap = getWageCap(level)
        }
    end

    table.sort(grades, function(a, b)
        return a.level < b.level
    end)

    return { ok = true, data = { job = job, grades = grades } }
end

handlers['business:wages:set'] = function(payload, src)
    local Player = GetPlayer(src)
    if not Player or not Player.PlayerData.job.isboss then
        return { ok = false, error = 'not_boss' }
    end

    local job = Player.PlayerData.job.name
    local jobData = QBCore.Shared.Jobs[job]
    if not jobData then
        return { ok = false, error = 'job_not_found' }
    end

    local wages = payload.wages or {}
    local data = loadData()
    data.businessWages[job] = data.businessWages[job] or {}

    local errors = {}
    for level, amount in pairs(wages) do
        local levelKey = tostring(level)
        local numeric = tonumber(amount)
        if numeric and numeric >= 0 then
            local cap = getWageCap(levelKey)
            if cap > 0 and numeric > cap then
                errors[#errors + 1] = { level = tonumber(levelKey) or levelKey, cap = cap }
            else
                data.businessWages[job][levelKey] = math.floor(numeric)
            end
        end
    end

    saveData()

    if #errors > 0 then
        return { ok = false, error = 'cap_exceeded', data = { errors = errors } }
    end

    return handlers['business:wages:get']({}, src)
end

-- Stash/Storage placement handler
handlers['business:stash:place'] = function(payload, src)
    local businessId, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local coords = payload.coords
    if type(coords) ~= 'table' or not coords.x or not coords.y or not coords.z then
        return { ok = false, error = 'invalid_coords' }
    end
    -- placed where the boss stands (the UI sends the player's position), and a limited number
    local cx, cy, cz = finiteNumber(coords.x), finiteNumber(coords.y), finiteNumber(coords.z)
    if not (cx and cy and cz) or #(GetEntityCoords(GetPlayerPed(src)) - vector3(cx, cy, cz)) > 10.0 then
        return { ok = false, error = 'invalid_coords' }
    end
    coords = { x = cx, y = cy, z = cz }

    local data = loadData()
    data.businesses = data.businesses or {}
    data.businesses[businessId] = data.businesses[businessId] or {
        id = businessId,
        settings = {}
    }
    data.businesses[businessId].stashLocations = data.businesses[businessId].stashLocations or {}
    if #data.businesses[businessId].stashLocations >= ((Config.BusinessManager and Config.BusinessManager.MaxStashes) or 10) then
        return { ok = false, error = 'too_many_stashes' }
    end

    -- Add new stash location
    table.insert(data.businesses[businessId].stashLocations, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        createdAt = nowIso(),
        createdBy = GetPlayer(src).PlayerData.citizenid
    })

    saveData()

    -- Notify all clients to update stash targets
    TriggerClientEvent('pf-computer:client:updateStashes', -1, {
        businessId = businessId,
        stashLocations = data.businesses[businessId].stashLocations
    })

    return { ok = true, data = { count = #data.businesses[businessId].stashLocations } }
end

-- Get all business stashes (for resource start initialization)
handlers['business:stashes:getAll'] = function(payload, src)
    local data = loadData()
    local stashes = {}
    
    for businessId, businessData in pairs(data.businesses or {}) do
        if businessData.stashLocations and #businessData.stashLocations > 0 then
            stashes[businessId] = businessData.stashLocations
        end
    end
    
    return { ok = true, data = stashes }
end

-- Wage caps for mayor
handlers['gov:wagecaps:get'] = function(_, src)
    local job, _ = GetPlayerJob(src)
    if not job or not isGovJob(job) then
        return { ok = false, error = 'not_authorized' }
    end

    local data = loadData()
    local caps = {}
    for level, cap in pairs(Config.BusinessManager.WageCaps) do
        caps[level] = data.wageCaps[level] or cap
    end
    for level, cap in pairs(data.wageCaps) do
        if caps[level] == nil then
            caps[level] = cap
        end
    end

    return { ok = true, data = { caps = caps } }
end

handlers['gov:wagecaps:set'] = function(payload, src)
    local job, _ = GetPlayerJob(src)
    if not job or not isGovJob(job) then
        return { ok = false, error = 'not_authorized' }
    end

    local data = loadData()
    local caps = payload.caps or {}
    for level, cap in pairs(caps) do
        local numeric = tonumber(cap)
        if numeric and numeric >= 0 then
            data.wageCaps[tostring(level)] = math.floor(numeric)
        end
    end
    saveData()

    return handlers['gov:wagecaps:get']({}, src)
end

-- Get persisted business blips on startup
handlers['business:blips:get'] = function(payload, src)
    local data = loadData()
    data.businessBlips = data.businessBlips or {}
    
    local blips = {}
    for businessId, blipData in pairs(data.businessBlips) do
        blips[#blips + 1] = blipData
    end
    
    return { ok = true, data = blips }
end

-- Save business blip
handlers['business:blips:save'] = function(payload, src)
    if not payload.businessId or not payload.coords then
        return { ok = false, error = 'missing_parameters' }
    end

    local businessId, _, jobConfig, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end
    -- the blip goes where the boss stands (the UI sends the player's position)
    local bx, by, bz = finiteNumber(payload.coords.x), finiteNumber(payload.coords.y), finiteNumber(payload.coords.z)
    if not (bx and by and bz) or #(GetEntityCoords(GetPlayerPed(src)) - vector3(bx, by, bz)) > 10.0 then
        return { ok = false, error = 'invalid_coords' }
    end
    payload.coords = { x = bx, y = by, z = bz }
    payload.name = cleanText(payload.name, 50, nil)
    payload.icon = tonumber(payload.icon) and math.floor(tonumber(payload.icon)) or nil
    payload.color = tonumber(payload.color) and math.floor(tonumber(payload.color)) or nil

    local data = loadData()
    data.businessBlips = data.businessBlips or {}
    
    -- Determine blip icon based on business type
    local blipIcon = payload.icon or 1
    if jobConfig.businessType == 'restaurant' then
        blipIcon = 889  -- Restaurant/food icon
    elseif jobConfig.businessType == 'mechanic' then
        blipIcon = 446  -- Wrench icon
    end
    
    data.businessBlips[businessId] = {
        businessId = businessId,
        businessType = jobConfig.businessType,
        name = payload.name or jobConfig.businessName,
        coords = {
            x = payload.coords.x,
            y = payload.coords.y,
            z = payload.coords.z
        },
        sprite = blipIcon,
        color = payload.color or jobConfig.blipColor,
        scale = 0.6,
        shortRange = true
    }
    
    saveData()
    
    -- Notify all clients to update their blips
    TriggerClientEvent('pf-computer:client:updateBusinessBlip', -1, data.businessBlips[businessId])
    
    return { ok = true, data = data.businessBlips[businessId] }
end

-- Update menu item
handlers['business:menu:editItem'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local itemId = payload.itemId
    local item = payload.item

    if not itemId or not item then
        return { ok = false, error = 'missing_item_data' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database update
        local success, updateResult = pcall(function()
            return exports[provider]:UpdateMenuItem(businessId, itemId, item)
        end)
        
        if success and updateResult then
            print(string.format('[pf-computer] Menu item %s updated successfully via %s', itemId, provider))
            return { ok = true, data = {
                id = itemId,
                item_id = itemId,
                name = item.name,
                label = item.name,
                price = tonumber(item.price) or 0,
                category = item.category or 'General'
            }}
        else
            local errorMsg = success and tostring(updateResult) or tostring(success)
            print(string.format('[ERROR] Failed to update menu item via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_update_item', message = errorMsg }
        end
    end

    -- Fallback to internal data storage
    local data = loadData()
    data.businessMenus = data.businessMenus or {}
    
    local menu = data.businessMenus[businessId] or {}
    for i, menuItem in ipairs(menu) do
        if menuItem.id == tonumber(itemId) then
            menuItem.name = item.name or menuItem.name
            menuItem.description = item.description or menuItem.description
            menuItem.price = tonumber(item.price) or menuItem.price
            menuItem.category = item.category or menuItem.category
            menuItem.available = item.available ~= nil and item.available or menuItem.available
            saveData()
            return { ok = true, data = menuItem }
        end
    end

    return { ok = false, error = 'item_not_found' }
end

-- Get menu categories
handlers['business:menu:categories:list'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    -- Try external data provider first (for mechanic jobs)
    local externalCategories, hasExternal = GetExternalOrInternal(businessId, 'menuCategories')
    if hasExternal and externalCategories then
        return { ok = true, data = externalCategories }
    end

    -- Fallback to internal data - build list from menu items
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    local categories = {}
    local seen = {}
    
    for _, item in ipairs(menu) do
        local cat = item.category or 'General'
        if not seen[cat] then
            table.insert(categories, cat)
            seen[cat] = true
        end
    end
    
    -- Ensure General is always present
    if not seen['General'] then
        table.insert(categories, 'General')
    end
    
    table.sort(categories)
    return { ok = true, data = categories }
end

-- Add menu category
handlers['business:menu:categories:add'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local categoryName = payload.category or 'New Category'

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- For mechanic jobs, just return success
        -- The category will be created when the first item with that category is added
        return { ok = true, data = { category = categoryName } }
    end

    -- For internal data, just return success
    -- Categories are dynamically created from items
    return { ok = true, data = { category = categoryName } }
end

-- Delete menu category (removes all items in that category)
handlers['business:menu:categories:delete'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local categoryName = payload.category

    if not categoryName then
        return { ok = false, error = 'missing_category_name' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database delete
        local success, deleteResult = pcall(function()
            return exports[provider]:DeleteCategory(businessId, categoryName)
        end)
        
        if success and deleteResult then
            return { ok = true }
        else
            local errorMsg = success and tostring(deleteResult) or tostring(success)
            print(string.format('[ERROR] Failed to delete category via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_delete_category', message = errorMsg }
        end
    end

    -- Fallback to internal data
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    
    -- Remove all items in this category
    local newMenu = {}
    for _, item in ipairs(menu) do
        if item.category ~= categoryName then
            table.insert(newMenu, item)
        end
    end
    
    data.businessMenus[businessId] = newMenu
    saveData()
    
    return { ok = true }
end

-- Rename menu category
handlers['business:menu:categories:rename'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local oldCategory = payload.oldCategory
    local newCategory = payload.newCategory

    if not oldCategory or not newCategory then
        return { ok = false, error = 'missing_parameters' }
    end

    -- Check if this is a mechanic job with external provider
    local provider = GetDataProvider(businessId)
    if provider then
        -- Delegate to external provider (e.g., pf-mechanicjob) for database update
        local success, updateResult = pcall(function()
            return exports[provider]:UpdateCategory(businessId, oldCategory, newCategory)
        end)
        
        if success and updateResult then
            return { ok = true }
        else
            local errorMsg = success and tostring(updateResult) or tostring(success)
            print(string.format('[ERROR] Failed to rename category via provider %s: %s', provider, errorMsg))
            return { ok = false, error = 'failed_to_rename_category', message = errorMsg }
        end
    end

    -- Fallback to internal data
    local data = loadData()
    local menu = data.businessMenus[businessId] or {}
    
    -- Rename category for all items
    for _, item in ipairs(menu) do
        if item.category == oldCategory then
            item.category = newCategory
        end
    end
    
    saveData()
    return { ok = true }
end

-- Update ingredient quantity
handlers['business:inventory:updateQuantity'] = function(payload, src)
    local businessId, _, _, errorResult = getAuthorizedBusiness(src, payload)
    if not businessId then
        return errorResult
    end

    local data = loadData()
    local ingredientId = payload.ingredientId
    local quantity = tonumber(payload.quantity) or 0

    if not ingredientId or quantity < 0 then
        return { ok = false, error = 'invalid_quantity' }
    end

    data.businesses[businessId] = data.businesses[businessId] or {}
    data.businesses[businessId].inventory = data.businesses[businessId].inventory or {}
    data.businesses[businessId].inventory[ingredientId] = quantity
    
    saveData()
    return { ok = true, quantity = quantity }
end

-- Actions that change a business need the business boss (several only needed the job before, so any
-- employee could spend the society account on supplies, change POS prices, move the public blip, ...).
local BOSS_ACTIONS = {
    -- (supply orders check the boss inside the handler: player-owned stores authorize by ownership)
    ['business:menu:add'] = true, ['business:menu:update'] = true, ['business:menu:editItem'] = true,
    ['business:menu:delete'] = true, ['business:menu:categories:add'] = true,
    ['business:menu:categories:delete'] = true, ['business:menu:categories:rename'] = true,
    ['business:meals:add'] = true, ['business:meals:update'] = true, ['business:meals:delete'] = true,
    ['business:update:settings'] = true, ['business:blips:save'] = true, ['business:stash:place'] = true,
    ['business:employees:update'] = true, ['business:employees:fire'] = true,
    ['business:inventory:updateQuantity'] = true, ['business:transactions:add'] = true,
}

-- City government actions and the pf-government permission each needs
local GOV_ACTIONS = {
    ['gov:cityhall:bootstrap'] = 'audit', ['gov:laws:setDisplay'] = 'laws',
    ['gov:taxes:update'] = 'taxes', ['gov:taxes:toggle'] = 'taxes',
    ['gov:budgets:update'] = 'budgets', ['gov:budgets:upgrade'] = 'budgets', ['gov:budgets:uninstallUpgrade'] = 'budgets',
    ['gov:utilities:disconnect'] = 'utilities', ['gov:utilities:restore'] = 'utilities',
    ['gov:fines:issue'] = 'fines', ['gov:announcements:create'] = 'laws',
    ['gov:wagecaps:set'] = 'budgets',
}

-- Every write re-saves the whole data file, so calls are rate limited per player
local CALLBACK_BURST, CALLBACK_REFILL_PER_SEC = 20, 5
local callbackBudget = {}

local function takeCallbackToken(src)
    local now = GetGameTimer()
    local b = callbackBudget[src]
    if not b then b = { tokens = CALLBACK_BURST, at = now }; callbackBudget[src] = b end
    b.tokens = math.min(CALLBACK_BURST, b.tokens + (now - b.at) / 1000 * CALLBACK_REFILL_PER_SEC)
    b.at = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end
AddEventHandler('playerDropped', function() callbackBudget[source] = nil end)

local function isBusinessBoss(src)
    local Player = GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.isboss == true
end

RegisterNetEvent('pf-computer:server:callback', function(id, action, payload)
    local src = source
    local result
    if type(action) ~= 'string' or (payload ~= nil and type(payload) ~= 'table') then
        result = { ok = false, error = 'bad_request' }
    elseif not takeCallbackToken(src) then
        result = { ok = false, error = 'rate_limited' }
    elseif not handlers[action] then
        result = { ok = false, error = 'unknown_action' }
    elseif BOSS_ACTIONS[action] and not isBusinessBoss(src) then
        result = { ok = false, error = 'not_authorized' }
    elseif GOV_ACTIONS[action] and not govCan(src, GOV_ACTIONS[action]) then
        result = { ok = false, error = 'not_authorized' }
    else
        local ok, res = pcall(handlers[action], payload or {}, src)
        result = ok and res or { ok = false, error = 'server_error' }
        if not ok then print(('^1[pf-computer]^7 %s failed: %s'):format(action, tostring(res))) end
    end
    TriggerClientEvent('pf-computer:client:callback', src, id, result)
end)

-- 'pf-computer:announcements:create' was a net event with no checks at all (anyone could post City
-- Hall announcements); nothing used it, so it is gone. Use the 'gov:announcements:create' action.

-- Set delivery location for supplies
RegisterNetEvent('pf-computer:server:setDeliveryLocation', function(location)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    -- a business boss sets their own business's delivery point, to real coordinates where they stand
    local authJob, _, _, authErr = getAuthorizedBusiness(src, {})
    if not authJob or not (Player.PlayerData.job and Player.PlayerData.job.isboss) then
        TriggerClientEvent('QBCore:Notify', src, 'Only the business boss can set the delivery point', 'error')
        return
    end
    if type(location) ~= 'table' and type(location) ~= 'vector3' and type(location) ~= 'vector4' then return end
    local lx, ly, lz = finiteNumber(location.x), finiteNumber(location.y), finiteNumber(location.z)
    if not (lx and ly and lz) then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - vector3(lx, ly, lz)) > 25.0 then
        TriggerClientEvent('QBCore:Notify', src, 'Stand at the delivery point to set it', 'error')
        return
    end
    location = { x = lx, y = ly, z = lz, w = finiteNumber(location.w) or 0.0 }

    local job = authJob
    local data = loadData()
    
    -- Initialize business delivery locations if not exists
    if not data.businessDeliveryLocations then
        data.businessDeliveryLocations = {}
    end
    
    -- Save the delivery location for this business
    data.businessDeliveryLocations[job] = location
    
    saveData(data)
    
    if Config.Debug then
        print(string.format('[pf-computer] Delivery location set for %s: %.2f, %.2f, %.2f', 
            job, location.x, location.y, location.z))
    end
    
    TriggerClientEvent('QBCore:Notify', src, 'Delivery location updated!', 'success')
end)

local function GetJobGradeWage(job, grade)
    if not job then return nil end
    local data = loadData()
    local level = tostring(grade or '0')
    if data.businessWages[job] and data.businessWages[job][level] then
        return data.businessWages[job][level]
    end
    local jobData = QBCore.Shared.Jobs[job]
    if jobData and jobData.grades and jobData.grades[level] then
        return jobData.grades[level].payment
    end
    return nil
end

exports('GetJobGradeWage', GetJobGradeWage)

-- Startup: Log external data providers
CreateThread(function()
    Wait(2000) -- Wait for other resources to load
    
    print('[pf-computer] Business Manager Integration System Loaded')
    print('[pf-computer] Checking for external data providers...')
    
    local foundProviders = 0
    for job, resource in pairs(JobDataProviders) do
        if GetResourceState(resource) == 'started' then
            local hasExports = pcall(function()
                return exports[resource].GetBusinessConfig
            end)
            if hasExports then
                foundProviders = foundProviders + 1
                print(string.format('  ✓ %s → %s', job, resource))
            else
                print(string.format('  ✗ %s → %s (no exports)', job, resource))
            end
        else
            print(string.format('  ✗ %s → %s (not started)', job, resource))
        end
    end
    
    if foundProviders > 0 then
        print(string.format('[pf-computer] Found %d external data provider(s)', foundProviders))
    else
        print('[pf-computer] No external data providers found, using internal data only')
    end
end)

RegisterCommand('pc_setwagecap', function(source, args)
    local src = source
    if src == 0 then return end
    -- the same permission as the app's 'gov:wagecaps:set' (any job in Config.GovJobs, e.g. police, could)
    if not govCan(src, GOV_ACTIONS['gov:wagecaps:set']) then
        TriggerClientEvent('QBCore:Notify', src, 'Not authorized.', 'error')
        return
    end

    local grade = args[1]
    local amount = args[2]
    if not grade or not amount then
        TriggerClientEvent('QBCore:Notify', src, 'Usage: /pc_setwagecap <grade> <amount>', 'error')
        return
    end

    local numeric = tonumber(amount)
    if not numeric or numeric < 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Amount must be >= 0.', 'error')
        return
    end

    handlers['gov:wagecaps:set']({ caps = { [grade] = math.floor(numeric) } }, src)
    TriggerClientEvent('QBCore:Notify', src, ('Wage cap set: grade %s -> %s'):format(grade, math.floor(numeric)), 'success')
end, false)

-- ============================================================================
-- EXPORTS FOR OTHER RESOURCES
-- ============================================================================

-- Records a sale in the Business Manager's history and analytics.
-- Usage: exports['pf-computer']:DepositSale(businessName, amount, description)
-- It no longer adds money: the company account is the job's bank account, and the money of a sale
-- must be moved by the resource that took it from the customer (e.g. pf-mechanicjob's register pays
-- the society through the bank). Callers pass amounts their clients chose, so crediting here would
-- create money from nothing.
function DepositSale(businessName, amount, description)
    amount = tonumber(amount)
    if type(businessName) ~= 'string' or businessName == '' or #businessName > 50 or not amount or amount ~= amount or amount <= 0 or amount > 1000000000 then
        return { ok = false, error = 'invalid_parameters' }
    end

    logBusinessTx(businessName, {
        type = 'sale',
        amount = math.floor(amount * 100 + 0.5) / 100,
        description = tostring(description or 'POS Sale'):sub(1, 100),
        recordOnly = true,
    })

    return { ok = true, balance = businessBalance(businessName) }
end
exports('DepositSale', DepositSale)

-- One-time move of the old data-file balances into the bank. Only the player-funded part moves:
-- deposits minus withdrawals minus supply spending (the history is complete, it was never trimmed),
-- capped at the old balance. Sale entries are not moved: the register already paid the bank for those,
-- and the tablet sales were never paid by anyone. Config.BusinessManager.MigrateSalesBalance = true
-- moves the whole old balance instead. Safe to re-run: keyed per business, and marked when done.
function MigrateBusinessAccountsToBank()
    local data = loadData()
    local moved, skipped = 0, 0
    for job, account in pairs(data.businessAccounts or {}) do
        local old = tonumber(account.balance) or 0
        if not account.bankMigration and old > 0 then
            local funded = 0
            for _, tx in ipairs(account.transactions or {}) do
                local amount = tonumber(tx.amount) or 0
                if tx.type == 'deposit' then funded = funded + amount
                elseif tx.type == 'withdrawal' or tx.type == 'supplies' then funded = funded - amount end
            end
            local toMove = (Config.BusinessManager and Config.BusinessManager.MigrateSalesBalance) and old or math.max(0, math.min(funded, old))
            toMove = math.floor(toMove * 100 + 0.5) / 100
            local ok = true
            if toMove > 0 then
                ok = ensureBusinessBankAccount(job)
                if ok then
                    local res = bizTransfer({
                        from = 'system:pf-computer-migration', to = 'society:' .. job, amount = toMove,
                        key = ('pf-computer:account-to-bank:%s:%.2f'):format(job, toMove),
                        kind = 'migration', reason = 'Company account moved to bank',
                    })
                    ok = res.ok
                end
            end
            if ok then
                account.bankMigration = { at = nowIso(), oldBalance = old, moved = toMove, notMoved = math.floor((old - toMove) * 100 + 0.5) / 100 }
                account.balance = nil
                moved = moved + 1
            else
                skipped = skipped + 1
                print(('^1[pf-computer]^7 could not move the company balance of %s to the bank; will retry next start'):format(job))
            end
        elseif account.balance ~= nil and old <= 0 and not account.bankMigration then
            account.bankMigration = { at = nowIso(), oldBalance = old, moved = 0, notMoved = 0 }
            account.balance = nil
        end
    end
    saveData()
    if moved > 0 then print(('[pf-computer] moved %d company account balance(s) into the bank'):format(moved)) end
    return moved, skipped
end

CreateThread(function()
    local waited = 0
    while not bizBankReady() and waited < 120 do
        Wait(1000)
        waited = waited + 1
    end
    if bizBankReady() then
        MigrateBusinessAccountsToBank()
    else
        print('^1[pf-computer]^7 pfm-banking ledger not available: company accounts are read-only until it is')
    end
end)
