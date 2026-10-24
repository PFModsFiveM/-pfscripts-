-- =====================================================
-- AUDIT LOG SYSTEM (IMMUTABLE)
-- =====================================================

function LogAudit(actionType, actorCitizenid, actorName, targetType, targetId, details)
    if not Config.AuditLog.Enabled then
        return
    end
    
    -- Check if this action type should be logged
    local shouldLog = false
    for _, loggedAction in ipairs(Config.AuditLog.LogActions) do
        if loggedAction == actionType then
            shouldLog = true
            break
        end
    end
    
    if not shouldLog then
        return
    end
    
    -- Get actor role
    local actorRole = nil
    if actorCitizenid and actorCitizenid ~= 'system' then
        local staff = MySQL.query.await('SELECT role FROM pf_gov_staff WHERE citizenid = ? AND active = 1', {actorCitizenid})
        if staff and #staff > 0 then
            actorRole = staff[1].role
        end
    else
        actorRole = 'System'
    end
    
    -- Convert details table to JSON
    local detailsJson = nil
    if details and type(details) == 'table' then
        detailsJson = json.encode(details)
    end
    
    -- Insert audit log (immutable - never updated or deleted)
    MySQL.insert('INSERT INTO pf_gov_audit_log (action_type, actor_citizenid, actor_name, actor_role, target_type, target_id, details) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {actionType, actorCitizenid, actorName, actorRole, targetType, targetId, detailsJson})
    
    DebugPrint('Audit logged: ' .. actionType .. ' by ' .. (actorName or 'system'))
end

function GetAuditLogs(filters, limit)
    limit = limit or 100
    
    local query = 'SELECT * FROM pf_gov_audit_log WHERE 1=1'
    local params = {}
    
    if filters then
        if filters.actionType then
            query = query .. ' AND action_type = ?'
            table.insert(params, filters.actionType)
        end
        
        if filters.actorCitizenid then
            query = query .. ' AND actor_citizenid = ?'
            table.insert(params, filters.actorCitizenid)
        end
        
        if filters.targetType then
            query = query .. ' AND target_type = ?'
            table.insert(params, filters.targetType)
        end
        
        if filters.targetId then
            query = query .. ' AND target_id = ?'
            table.insert(params, filters.targetId)
        end
        
        if filters.dateFrom then
            query = query .. ' AND created_at >= ?'
            table.insert(params, filters.dateFrom)
        end
        
        if filters.dateTo then
            query = query .. ' AND created_at <= ?'
            table.insert(params, filters.dateTo)
        end
    end
    
    query = query .. ' ORDER BY created_at DESC LIMIT ?'
    table.insert(params, limit)
    
    local result = MySQL.query.await(query, params)
    return result or {}
end

function GetAuditStats()
    local stats = MySQL.query.await([[
        SELECT 
            action_type,
            COUNT(*) as count,
            MAX(created_at) as last_action
        FROM pf_gov_audit_log
        GROUP BY action_type
        ORDER BY count DESC
    ]], {})
    
    return stats or {}
end

-- =====================================================
-- NUI CALLBACKS - AUDIT LOG
-- =====================================================

RegisterNUICallback('audit:getLogs', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'audit') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local limit = data.limit or 100
    local filters = data.filters or {}
    
    local logs = GetAuditLogs(filters, limit)
    
    cb({
        ok = true,
        logs = logs
    })
end)

RegisterNUICallback('audit:getStats', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'audit') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local stats = GetAuditStats()
    
    cb({
        ok = true,
        stats = stats
    })
end)

RegisterNUICallback('audit:getActionTypes', function(data, cb)
    cb({
        ok = true,
        actionTypes = Config.AuditLog.LogActions
    })
end)

-- =====================================================
-- AUDIT LOG RETENTION (Optional Cleanup)
-- =====================================================

if Config.AuditLog.RetentionDays > 0 then
    CreateThread(function()
        while true do
            Wait(86400000) -- Run once per day
            
            local retentionDate = os.date('%Y-%m-%d %H:%M:%S', os.time() - (Config.AuditLog.RetentionDays * 86400))
            
            MySQL.update('DELETE FROM pf_gov_audit_log WHERE created_at < ?', {retentionDate}, function(affectedRows)
                if affectedRows > 0 then
                    DebugPrint('Audit log cleanup: ' .. affectedRows .. ' old records removed')
                end
            end)
        end
    end)
end

print('^2[PF-GOVERNMENT]^7 Audit log system loaded')
