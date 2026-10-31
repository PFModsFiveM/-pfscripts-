-- =====================================================
-- PF GOVERNMENT - CORE INITIALIZATION
-- =====================================================

QBCore = exports[Config.FrameworkResourceName]:GetCoreObject()

-- Global state
Government = {
    Treasury = {},
    Taxes = {},
    Budgets = {},
    Laws = {},
    Licenses = {},
    Utilities = {},
    Bills = {},
    Businesses = {},
    Staff = {},
    Audit = {},
    NuiCallbacks = {}
}

-- Server-side NUI callback registry (client forwards NUI actions to server)
function RegisterNUICallback(action, handler)
    if type(action) ~= 'string' or type(handler) ~= 'function' then
        return
    end

    Government.NuiCallbacks[action] = handler
end

-- Utility Functions (used by all modules)
function GetPlayerIdentifier(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        return Player.PlayerData.citizenid
    end
    return nil
end

function GetPlayerName(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        return Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    end
    return 'Unknown'
end

function GetPlayerJob(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        return Player.PlayerData.job
    end
    return nil
end

function HasPermission(source, permission)
    local job = GetPlayerJob(source)
    if not job or job.name ~= Config.GovernmentJob then
        return false
    end
    
    local roleConfig = Config.Roles[job.grade.level]
    if not roleConfig then
        return false
    end
    
    -- Check if has 'all' permissions
    if roleConfig.permissions and #roleConfig.permissions > 0 then
        for _, perm in ipairs(roleConfig.permissions) do
            if perm == 'all' then
                return true
            end
            if perm == permission then
                return true
            end
        end
    end
    
    return false
end

-- Other resources (pf-computer's city hall apps) check the same roles instead of their own job lists
exports('HasPermission', function(source, permission)
    return HasPermission(source, permission) == true
end)

function NotifyPlayer(source, message, type)
    TriggerClientEvent('QBCore:Notify', source, message, type or 'primary')
end

function DebugPrint(message)
    if Config.Debug then
        print('^3[PF-GOVERNMENT DEBUG]^7 ' .. message)
    end
end

-- =====================================================
-- CITY EVENTS (pf-services timeline; the news turns them into articles)
-- =====================================================

--- True when city events can be recorded. Callers use it to skip the extra "before" reads they
--- need to tell a real change from a no-op.
function GovEventsOn()
    return GetResourceState('pf-services') == 'started'
end

--- Runs fn and returns its results, or nil when it fails. For side reads around a decision:
--- they must never break the decision itself.
function GovSafe(fn, ...)
    local res = table.pack(pcall(fn, ...))
    if not res[1] then
        DebugPrint('side read failed: ' .. tostring(res[2]))
        return nil
    end
    return table.unpack(res, 2, res.n)
end

--- Records a government decision on the city timeline. `data` may be a function returning
--- data, opts (it only runs when pf-services is up, so lookups for public names cost nothing
--- otherwise). Call it after the change succeeded, and only when something really changed.
--- Public fields only in data; the acting citizen id goes in opts.actor.
-- The news presets (pf-news) read these names; the government's own names stay as well.
local NEWS_ALIASES = {
    business = 'businessName', businessType = 'type', summary = 'description', excerpt = 'content',
    utility = 'service', departmentLabel = 'department', previousRole = 'oldRole',
}

function GovEmit(kind, data, opts)
    if not GovEventsOn() then return nil end
    local ok, id = pcall(function()
        local d, o = data, opts
        if type(data) == 'function' then d, o = data() end
        if type(d) ~= 'table' then return nil end
        for from, to in pairs(NEWS_ALIASES) do
            if d[to] == nil and d[from] ~= nil then d[to] = d[from] end
        end
        if d.fineMax ~= nil and d.fine == nil then d.fine = d.fineMax end
        if d.jailMax ~= nil and d.jail == nil then d.jail = d.jailMax end
        return exports['pf-services']:Emit(kind, d, type(o) == 'table' and o or {})
    end)
    if not ok then
        DebugPrint(('city event %s not recorded: %s'):format(tostring(kind), tostring(id)))
        return nil
    end
    return id
end

--- Public facts about a registered business for event data: name, type, district.
function GovBusinessFacts(businessId)
    local row = GovSafe(function()
        return MySQL.single.await('SELECT * FROM pf_gov_businesses WHERE business_id = ? LIMIT 1', { businessId })
    end)
    if type(row) ~= 'table' or not row.business_id then
        return { businessId = businessId, business = tostring(businessId) }
    end
    return {
        businessId = row.business_id,
        business = row.business_name or row.business_id,
        businessType = row.business_type,
        district = row.district,
        ownerName = row.owner_name,
        coords = tonumber(row.location_x) and tonumber(row.location_y)
            and { x = tonumber(row.location_x), y = tonumber(row.location_y), z = tonumber(row.location_z) or 0.0 } or nil,
    }
end

--- First `max` characters of a text, on one line, for event summaries.
function GovExcerpt(text, max)
    text = tostring(text or ''):gsub('<[^>]*>', ' '):gsub('[%c]', ' '):gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    max = max or 240
    if #text <= max then return text end
    return text:sub(1, max - 3):gsub('%s+%S*$', '') .. '...'
end

print('^2[PF-GOVERNMENT]^7 Core functions loaded')
