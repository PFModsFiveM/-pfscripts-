-- =====================================================
-- LAWS SYSTEM
-- =====================================================

local LawsCache = {}
local LawVisibilityCache = {}
local MDT_LAW_ID_OFFSET = 900000000

local function tableExists(tableName)
    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { tableName })
    return (tonumber(exists) or 0) > 0
end

local function resolveMdtResourceName()
    local candidates = {
        Config.Laws and Config.Laws.MDTIntegration and Config.Laws.MDTIntegration.resource or nil,
        Config.Integrations and Config.Integrations.MDT and Config.Integrations.MDT.resource or nil,
        Config.Civilians and Config.Civilians.PoliceMdtResource or nil,
        'pf-policemdt',
        'pf-policemdt-DEV'
    }

    local seen = {}
    for _, resource in ipairs(candidates) do
        if resource and resource ~= '' and not seen[resource] then
            seen[resource] = true
            if GetResourceState(resource) == 'started' then
                return resource
            end
        end
    end

    return nil
end

local function buildMdtLawContent(row)
    local parts = {}
    if row.purpose and row.purpose ~= '' then
        parts[#parts + 1] = ('Purpose: %s'):format(row.purpose)
    end
    if row.policy and row.policy ~= '' then
        parts[#parts + 1] = ('Policy: %s'):format(row.policy)
    end
    if row.procedure_text and row.procedure_text ~= '' then
        parts[#parts + 1] = ('Procedure: %s'):format(row.procedure_text)
    end
    if row.notes and row.notes ~= '' then
        parts[#parts + 1] = ('Notes: %s'):format(row.notes)
    end
    return table.concat(parts, '\n\n')
end

local function getMdtLawsForGovernment()
    if not tableExists('pf_mdt_sops') then
        return {}
    end

    local rows = MySQL.query.await('SELECT id, title, category, purpose, policy, procedure_text, notes, updated_by, updated_at, created_at FROM pf_mdt_sops ORDER BY category ASC, title ASC', {}) or {}
    local out = {}

    for _, row in ipairs(rows) do
        out[#out + 1] = {
            id = MDT_LAW_ID_OFFSET + tonumber(row.id),
            title = row.title,
            category = row.category or 'MDT',
            content = buildMdtLawContent(row),
            penalty_min = 0,
            penalty_max = 0,
            fine_min = 0,
            fine_max = 0,
            status = 'active',
            source = 'pf-policemdt',
            read_only = true,
            created_by_name = row.updated_by,
            created_at = row.created_at,
            updated_at = row.updated_at
        }
    end

    return out
end

local function buildLawKey(lawId, source)
    local src = tostring(source or 'government')
    local prefix = (src == 'pf-policemdt' or src == 'mdt') and 'mdt' or 'gov'
    return ('%s:%s'):format(prefix, tostring(lawId or 'unknown'))
end

local function ensureLawVisibilityTable()
    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `pf_gov_law_visibility` (
            `law_key` VARCHAR(80) PRIMARY KEY,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `updated_by` VARCHAR(64) NULL,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

local function loadLawVisibility()
    LawVisibilityCache = {}
    local rows = MySQL.query.await('SELECT law_key, enabled FROM pf_gov_law_visibility', {}) or {}
    for _, row in ipairs(rows) do
        LawVisibilityCache[tostring(row.law_key)] = tonumber(row.enabled) == 1
    end
end

local function isLawVisible(law)
    if type(law) ~= 'table' or not law.id then
        return true
    end

    local key = buildLawKey(law.id, law.source)
    local value = LawVisibilityCache[key]
    if value == nil then
        return true
    end
    return value == true
end

function SetLawDisplayEnabled(lawId, source, enabled, updatedBy, updatedByName)
    if lawId == nil then
        return false, 'invalid_law'
    end

    local key = buildLawKey(lawId, source)
    local enabledFlag = enabled and 1 or 0

    MySQL.insert.await(
        'INSERT INTO pf_gov_law_visibility (law_key, enabled, updated_by) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE enabled = VALUES(enabled), updated_by = VALUES(updated_by)',
        { key, enabledFlag, updatedBy }
    )

    LawVisibilityCache[key] = enabledFlag == 1

    LogAudit('law_visibility_change', updatedBy or 'system', updatedByName or 'System', 'law_visibility', key, {
        law_key = key,
        enabled = enabledFlag == 1
    })

    return true, 'updated'
end

function IsLawDisplayEnabled(lawId, source)
    local key = buildLawKey(lawId, source)
    local value = LawVisibilityCache[key]
    if value == nil then
        return true
    end
    return value == true
end

function GetPortalLawFeed()
    local laws = MySQL.query.await('SELECT * FROM pf_gov_laws WHERE status = ? ORDER BY effective_date DESC, created_at DESC', { 'active' }) or {}
    local mdtLaws = getMdtLawsForGovernment()

    for _, law in ipairs(laws) do
        law.source = law.source or 'government'
    end

    for _, law in ipairs(mdtLaws) do
        laws[#laws + 1] = law
    end

    local visible = {}
    for _, law in ipairs(laws) do
        if isLawVisible(law) then
            visible[#visible + 1] = law
        end
    end

    return visible
end

local function buildLawSyncPayload(law)
    if not law then
        return nil
    end

    return {
        id = law.id,
        title = law.title,
        category = law.category,
        content = law.content,
        penalty_min = tonumber(law.penalty_min) or 0,
        penalty_max = tonumber(law.penalty_max) or 0,
        fine_min = tonumber(law.fine_min) or 0,
        fine_max = tonumber(law.fine_max) or 0,
        status = law.status,
        effective_date = law.effective_date,
        updated_at = law.updated_at,
        source = 'government'
    }
end

function InitializeLaws()
    ensureLawVisibilityTable()
    loadLawVisibility()

    MySQL.query('SELECT * FROM pf_gov_laws WHERE status = ?', {'active'}, function(result)
        if result then
            for _, law in ipairs(result) do
                LawsCache[law.id] = law
            end
            print('^2[PF-GOVERNMENT]^7 Loaded ' .. #result .. ' active laws')
            
            -- Sync with MDT if enabled
            if Config.Laws.MDTIntegration.enabled and Config.Laws.MDTIntegration.syncOnPublish then
                SyncLawsWithMDT()
            end
        end
    end)
end

function GetActiveLaws()
    local laws = {}
    for _, law in pairs(LawsCache) do
        if law.status == 'active' then
            table.insert(laws, law)
        end
    end
    return laws
end

function GetLaw(lawId)
    return LawsCache[lawId]
end

function CreateLaw(title, category, content, penaltyMin, penaltyMax, fineMin, fineMax, createdBy, createdByName)
    if not title or not category or not content then
        return false, 'Missing required fields'
    end
    
    penaltyMin = tonumber(penaltyMin) or 0
    penaltyMax = tonumber(penaltyMax) or 0
    fineMin = tonumber(fineMin) or 0
    fineMax = tonumber(fineMax) or 0
    
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_laws (title, category, content, penalty_min, penalty_max, fine_min, fine_max, status, created_by, created_by_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {title, category, content, penaltyMin, penaltyMax, fineMin, fineMax, 'draft', createdBy, createdByName})
    
    if insertId then
        -- Log audit
        LogAudit('law_create', createdBy, createdByName, 'law', insertId, {
            law_id = insertId,
            title = title,
            category = category
        })
        
        DebugPrint('Law created: ' .. title .. ' (ID: ' .. insertId .. ')')
        return true, 'Law created successfully', insertId
    end
    
    return false, 'Database error'
end

function UpdateLaw(lawId, title, category, content, penaltyMin, penaltyMax, fineMin, fineMax, updatedBy, updatedByName)
    lawId = tonumber(lawId)
    if not lawId then
        return false, 'Invalid law ID'
    end
    
    penaltyMin = tonumber(penaltyMin) or 0
    penaltyMax = tonumber(penaltyMax) or 0
    fineMin = tonumber(fineMin) or 0
    fineMax = tonumber(fineMax) or 0
    
    local affectedRows = MySQL.update.await('UPDATE pf_gov_laws SET title = ?, category = ?, content = ?, penalty_min = ?, penalty_max = ?, fine_min = ?, fine_max = ?, updated_by = ?, updated_by_name = ?, updated_at = NOW() WHERE id = ?',
        {title, category, content, penaltyMin, penaltyMax, fineMin, fineMax, updatedBy, updatedByName, lawId})
    
    if affectedRows > 0 then
        -- Update cache
        if LawsCache[lawId] then
            LawsCache[lawId].title = title
            LawsCache[lawId].category = category
            LawsCache[lawId].content = content
            LawsCache[lawId].penalty_min = penaltyMin
            LawsCache[lawId].penalty_max = penaltyMax
            LawsCache[lawId].fine_min = fineMin
            LawsCache[lawId].fine_max = fineMax
        end
        
        -- Log audit
        LogAudit('law_update', updatedBy, updatedByName, 'law', lawId, {
            law_id = lawId,
            title = title
        })
        
        -- Sync with MDT if law is active
        if LawsCache[lawId] and LawsCache[lawId].status == 'active' and Config.Laws.MDTIntegration.enabled and Config.Laws.MDTIntegration.syncOnUpdate then
            SyncLawsWithMDT()
        end
        
        DebugPrint('Law updated: ' .. title .. ' (ID: ' .. lawId .. ')')
        return true, 'Law updated successfully'
    end
    
    return false, 'Law not found or no changes made'
end

function PublishLaw(lawId, publishedBy, publishedByName)
    lawId = tonumber(lawId)
    if not lawId then
        return false, 'Invalid law ID'
    end
    
    local affectedRows = MySQL.update.await('UPDATE pf_gov_laws SET status = ?, effective_date = NOW() WHERE id = ?',
        {'active', lawId})
    
    if affectedRows > 0 then
        -- Reload law into cache
        MySQL.query('SELECT * FROM pf_gov_laws WHERE id = ?', {lawId}, function(result)
            if result and #result > 0 then
                LawsCache[lawId] = result[1]
            end
        end)
        
        -- Log audit
        LogAudit('law_publish', publishedBy, publishedByName, 'law', lawId, {
            law_id = lawId
        })
        
        -- Sync with MDT
        if Config.Laws.MDTIntegration.enabled and Config.Laws.MDTIntegration.syncOnPublish then
            SyncLawsWithMDT()
        end
        
        DebugPrint('Law published: ID ' .. lawId)
        
        -- Notify government
        NotifyGovernment('New law published: ' .. (LawsCache[lawId] and LawsCache[lawId].title or 'Law #' .. lawId), 'success')

        -- Sync law publication to pf-computer so all players get a mailbox update.
        TriggerEvent('pf-computer:gov:laws:sync', {
            action = 'publish',
            law = buildLawSyncPayload(LawsCache[lawId])
        })
        
        return true, 'Law published successfully'
    end
    
    return false, 'Law not found'
end

function RepealLaw(lawId, repealedBy, repealedByName)
    lawId = tonumber(lawId)
    if not lawId then
        return false, 'Invalid law ID'
    end
    
    local affectedRows = MySQL.update.await('UPDATE pf_gov_laws SET status = ?, repealed_by = ?, repealed_at = NOW() WHERE id = ?',
        {'repealed', repealedBy, lawId})
    
    if affectedRows > 0 then
        -- Update cache
        if LawsCache[lawId] then
            LawsCache[lawId].status = 'repealed'
            LawsCache[lawId].repealed_by = repealedBy
        end
        
        -- Log audit
        LogAudit('law_repeal', repealedBy, repealedByName, 'law', lawId, {
            law_id = lawId
        })
        
        -- Sync with MDT
        if Config.Laws.MDTIntegration.enabled and Config.Laws.MDTIntegration.syncOnRepeal then
            SyncLawsWithMDT()
        end
        
        DebugPrint('Law repealed: ID ' .. lawId)
        
        -- Notify government
        NotifyGovernment('Law repealed: ' .. (LawsCache[lawId] and LawsCache[lawId].title or 'Law #' .. lawId), 'warning')

        TriggerEvent('pf-computer:gov:laws:sync', {
            action = 'repeal',
            law = buildLawSyncPayload(LawsCache[lawId] or { id = lawId })
        })
        
        return true, 'Law repealed successfully'
    end
    
    return false, 'Law not found'
end

function DeleteLaw(lawId, deletedBy, deletedByName)
    lawId = tonumber(lawId)
    if not lawId then
        return false, 'Invalid law ID'
    end
    
    -- Only allow deletion of draft laws
    if LawsCache[lawId] and LawsCache[lawId].status ~= 'draft' then
        return false, 'Only draft laws can be deleted. Published laws should be repealed instead.'
    end
    
    local affectedRows = MySQL.update.await('DELETE FROM pf_gov_laws WHERE id = ? AND status = ?',
        {lawId, 'draft'})
    
    if affectedRows > 0 then
        -- Remove from cache
        LawsCache[lawId] = nil
        
        -- Log audit
        LogAudit('law_delete', deletedBy, deletedByName, 'law', lawId, {
            law_id = lawId
        })
        
        DebugPrint('Law deleted: ID ' .. lawId)
        return true, 'Law deleted successfully'
    end
    
    return false, 'Law not found or not a draft'
end

function SyncLawsWithMDT()
    if not Config.Laws.MDTIntegration.enabled then
        return
    end
    
    local activeLaws = GetActiveLaws()
    
    local mdtResource = resolveMdtResourceName()
    if not mdtResource then
        DebugPrint('MDT resource not started, cannot sync laws')
        return
    end
    
    -- Try to call MDT export
    local success, err = pcall(function()
        exports[mdtResource]:SyncLaws(activeLaws)
    end)
    
    if success then
        DebugPrint('Laws synced with MDT successfully')
    else
        DebugPrint('Failed to sync laws with MDT: ' .. tostring(err))
    end
end

-- =====================================================
-- NUI CALLBACKS - LAWS
-- =====================================================

RegisterNUICallback('law:getAll', function(data, cb)
    local status = data.status or 'all'

    local query = 'SELECT * FROM pf_gov_laws'
    local params = {}
    if status ~= 'all' then
        query = query .. ' WHERE status = ?'
        params = { status }
    end
    query = query .. ' ORDER BY created_at DESC'

    local govLaws = MySQL.query.await(query, params) or {}
    for _, law in ipairs(govLaws) do
        law.source = law.source or 'government'
        law.display_enabled = IsLawDisplayEnabled(law.id, law.source)
    end

    -- Always include MDT SOP/law references for City Hall visibility.
    local mdtLaws = getMdtLawsForGovernment()
    for _, law in ipairs(mdtLaws) do
        law.display_enabled = IsLawDisplayEnabled(law.id, law.source)
        govLaws[#govLaws + 1] = law
    end

    local visibleLaws = {}
    for _, law in ipairs(govLaws) do
        if law.display_enabled then
            visibleLaws[#visibleLaws + 1] = law
        end
    end

    cb({
        ok = true,
        laws = visibleLaws
    })
end)

RegisterNUICallback('law:setDisplayEnabled', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'laws') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    local lawId = data.lawId
    local lawSource = data.sourceType or data.lawSource or 'government'
    local enabled = data.enabled == true or data.enabled == 1 or data.enabled == '1'

    local ok, message = SetLawDisplayEnabled(lawId, lawSource, enabled, citizenid, name)
    cb({ ok = ok, message = message })
end)

RegisterNUICallback('law:get', function(data, cb)
    local lawId = tonumber(data.lawId)
    
    MySQL.query('SELECT * FROM pf_gov_laws WHERE id = ?', {lawId}, function(result)
        if result and #result > 0 then
            cb({ ok = true, law = result[1] })
        else
            cb({ ok = false, error = 'law_not_found' })
        end
    end)
end)

RegisterNUICallback('law:create', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'laws') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message, lawId = CreateLaw(
        data.title,
        data.category,
        data.content,
        data.penaltyMin or data.jail,
        data.penaltyMax or data.jail,
        data.fineMin or data.fine,
        data.fineMax or data.fine,
        citizenid,
        name
    )
    
    if success then
        NotifyPlayer(src, 'Law created: ' .. data.title, 'success')
    end
    
    cb({
        ok = success,
        message = message,
        lawId = lawId
    })
end)

RegisterNUICallback('law:update', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'laws') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = UpdateLaw(
        data.lawId,
        data.title,
        data.category,
        data.content,
        data.penaltyMin or data.jail,
        data.penaltyMax or data.jail,
        data.fineMin or data.fine,
        data.fineMax or data.fine,
        citizenid,
        name
    )
    
    if success then
        NotifyPlayer(src, 'Law updated: ' .. data.title, 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('law:publish', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'laws') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = PublishLaw(data.lawId, citizenid, name)
    
    if success then
        NotifyPlayer(src, 'Law published', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('law:repeal', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'laws') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = RepealLaw(data.lawId, citizenid, name)
    
    if success then
        NotifyPlayer(src, 'Law repealed', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('law:delete', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'laws') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = DeleteLaw(data.lawId, citizenid, name)
    
    if success then
        NotifyPlayer(src, 'Law deleted', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('law:getCategories', function(data, cb)
    cb({
        ok = true,
        categories = Config.Laws.Categories
    })
end)

print('^2[PF-GOVERNMENT]^7 Laws system loaded')

exports('SetLawDisplayEnabled', function(lawId, source, enabled, updatedBy, updatedByName)
    return SetLawDisplayEnabled(lawId, source, enabled, updatedBy, updatedByName)
end)

exports('IsLawDisplayEnabled', function(lawId, source)
    return IsLawDisplayEnabled(lawId, source)
end)
