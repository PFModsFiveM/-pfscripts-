local QBCore = PFMdt.GetCore()

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end

local function getPlayerJobAndGrade(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil, 0, nil end
    local job = Player.PlayerData.job or {}
    return job.name, (job.grade and job.grade.level) or 0, Player
end

local function isAllowedJob(jobName)
    return jobName and Config and Config.AllowedJobs and Config.AllowedJobs[jobName] == true
end

local function isGrade4Plus(source)
    local jobName, gradeLevel = getPlayerJobAndGrade(source)
    if not isAllowedJob(jobName) then return false end
    return (gradeLevel or 0) >= 4
end

local function hasDb()
    return exports and exports.oxmysql ~= nil
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

local TRAINING_STATUSES = { NONE = true, TRAINING = true, TRAINEE = true }

local DEFAULT_RANK_BY_UNIT_TYPE = {
    ['Patrol Units'] = 'Patrol Officer',
    ['Training Units'] = 'Patrol Officer (Training)',
    ['Detectives / Investigations'] = 'Detective',
    ['Traffic Unit'] = 'Traffic Officer',
    ['K-9 Unit'] = 'K-9 Handler',
    ['Narcotics Unit'] = 'Narcotics Officer',
    ['Gang Unit'] = 'Gang Unit Officer',
    ['SWAT'] = 'SWAT Operator',
    ['Watch Command / Field Command'] = 'Patrol Sergeant',
    ['Command / Administration'] = '',
    ['Support Units'] = '',
}

local function defaultRankForUnitType(unitType)
    local ut = trim(unitType)
    if ut == '' then return '' end
    return DEFAULT_RANK_BY_UNIT_TYPE[ut] or ''
end

local function defaultTrainingForUnitType(unitType)
    local ut = trim(unitType)
    if ut == 'Training Units' then return 'TRAINING' end
    return 'NONE'
end

local officerDirectoryCache = { at = 0, data = nil }

local function buildOfficerDirectory(cb)
    if not hasDb() then cb(false, 'no_db'); return end

    local now = os.time()
    if officerDirectoryCache.data and (now - (officerDirectoryCache.at or 0)) < 60 then
        cb(true, officerDirectoryCache.data)
        return
    end

    exports.oxmysql:execute('SELECT citizenid, charinfo FROM players ORDER BY citizenid ASC', {}, function(rows)
        local result = {}
        for _, r in ipairs(rows or {}) do
            local cid = r.citizenid
            if cid and tostring(cid) ~= '' then
                local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
                local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
                result[#result + 1] = {
                    citizenid = tostring(cid),
                    name = (name ~= '' and name) or tostring(cid),
                }
            end
        end

        officerDirectoryCache.at = now
        officerDirectoryCache.data = result
        cb(true, result)
    end)
end

local function getDefaultRosterRows()
    -- Keep this in a single place so both first-time seeding and reset use
    -- the same ordered roster definition.
    return {
        -- Command / Administration
        { callsign = '1A-01', rank = 'Chief of Police', unit_type = 'Command / Administration', training_status = 'NONE' },
        { callsign = '1A-02', rank = 'Deputy Chief', unit_type = 'Command / Administration', training_status = 'NONE' },
        { callsign = '1A-10', rank = 'Captain', unit_type = 'Command / Administration', training_status = 'NONE' },
        { callsign = '1A-20', rank = 'Lieutenant (Command)', unit_type = 'Command / Administration', training_status = 'NONE' },

        -- Watch Command / Field Command
        { callsign = '2A-01', rank = 'Watch Commander', unit_type = 'Watch Command / Field Command', training_status = 'NONE' },
        { callsign = '2A-10', rank = 'Patrol Sergeant', unit_type = 'Watch Command / Field Command', training_status = 'NONE' },

        -- Patrol Units
        { callsign = '2A-11', rank = 'Patrol Officer', unit_type = 'Patrol Units', training_status = 'NONE' },
        { callsign = '2A-12', rank = 'Patrol Officer', unit_type = 'Patrol Units', training_status = 'NONE' },
        { callsign = '2A-13', rank = 'Patrol Officer', unit_type = 'Patrol Units', training_status = 'NONE' },
        { callsign = '2A-14', rank = 'Patrol Officer', unit_type = 'Patrol Units', training_status = 'NONE' },

        -- Training Units
        { callsign = '2A-15', rank = 'Patrol Officer (Training)', unit_type = 'Training Units', training_status = 'TRAINING' },

        -- Detectives / Investigations
        { callsign = '5D-01', rank = 'Detective', unit_type = 'Detectives / Investigations', training_status = 'NONE' },
        { callsign = '5D-02', rank = 'Detective', unit_type = 'Detectives / Investigations', training_status = 'NONE' },
        { callsign = '5D-03', rank = 'Detective', unit_type = 'Detectives / Investigations', training_status = 'NONE' },
        { callsign = '5D-04', rank = 'Detective', unit_type = 'Detectives / Investigations', training_status = 'NONE' },
        { callsign = '5D-05', rank = 'Detective', unit_type = 'Detectives / Investigations', training_status = 'NONE' },

        -- Traffic Unit
        { callsign = '6T-01', rank = 'Traffic Officer', unit_type = 'Traffic Unit', training_status = 'NONE' },
        { callsign = '6T-02', rank = 'Traffic Officer', unit_type = 'Traffic Unit', training_status = 'NONE' },
        { callsign = '6T-03', rank = 'Traffic Officer', unit_type = 'Traffic Unit', training_status = 'NONE' },

        -- K-9 Unit
        { callsign = '6K-01', rank = 'K-9 Handler', unit_type = 'K-9 Unit', training_status = 'NONE' },
        { callsign = '6K-02', rank = 'K-9 Handler', unit_type = 'K-9 Unit', training_status = 'NONE' },
        { callsign = '6K-03', rank = 'K-9 Handler', unit_type = 'K-9 Unit', training_status = 'NONE' },

        -- Narcotics Unit
        { callsign = '7N-01', rank = 'Narcotics Officer', unit_type = 'Narcotics Unit', training_status = 'NONE' },
        { callsign = '7N-02', rank = 'Narcotics Officer', unit_type = 'Narcotics Unit', training_status = 'NONE' },

        -- Gang Unit
        { callsign = '7G-01', rank = 'Gang Unit Officer', unit_type = 'Gang Unit', training_status = 'NONE' },
        { callsign = '7G-02', rank = 'Gang Unit Officer', unit_type = 'Gang Unit', training_status = 'NONE' },

        -- SWAT
        { callsign = '8S-01', rank = 'SWAT Commander', unit_type = 'SWAT', training_status = 'NONE' },
        { callsign = '8S-02', rank = 'SWAT Operator', unit_type = 'SWAT', training_status = 'NONE' },
        { callsign = '8S-03', rank = 'SWAT Operator', unit_type = 'SWAT', training_status = 'NONE' },

        -- Support Units
        { callsign = 'Air-1', rank = 'Air Unit', unit_type = 'Support Units', training_status = 'NONE' },
        { callsign = 'Marine-2', rank = 'Marine Unit', unit_type = 'Support Units', training_status = 'NONE' },
        { callsign = 'SRO-4', rank = 'School Resource Officer', unit_type = 'Support Units', training_status = 'NONE' },
        { callsign = 'CP-6', rank = 'Community Policing', unit_type = 'Support Units', training_status = 'NONE' },
    }
end

local DEFAULT_META = {
    ranks = {
        '',
        -- Command / Administration
        'Chief of Police',
        'Deputy Chief',
        'Captain',
        'Lieutenant (Command)',

        -- Watch / Field Command
        'Watch Commander',
        'Patrol Sergeant',

        -- Patrol / Training
        'Patrol Officer',
        'Patrol Officer (Training)',

        -- Investigations
        'Detective',

        -- Specialized
        'Traffic Officer',
        'K-9 Handler',
        'Narcotics Officer',
        'Gang Unit Officer',
        'SWAT Commander',
        'SWAT Operator',

        -- Support
        'Air Unit',
        'Marine Unit',
        'School Resource Officer',
        'Community Policing',

        -- Legacy/common
        'Chief',
        'Lieutenant',
        'Sergeant',
        'Corporal',
        'Officer',
        'Cadet',
        'Dispatcher',
    },
    unit_types = {
        '',
        -- Preferred display/grouping labels (match roster format)
        'Command / Administration',
        'Watch Command / Field Command',
        'Patrol Units',
        'Training Units',
        'Detectives / Investigations',
        'Traffic Unit',
        'K-9 Unit',
        'Narcotics Unit',
        'Gang Unit',
        'SWAT',
        'Support Units',

        -- Legacy/common values (kept for compatibility)
        'Command',
        'Patrol',
        'Detective',
        'Traffic',
        'K9',
        'Narcotics',
        'Gang',
        'SWAT',
        'Support',
        'Other',
        'Numeric',
    },
    training_statuses = { 'NONE', 'TRAINING', 'TRAINEE' }
}

local function getConfiguredGradeLabels(primaryJobName)
    local labels = {}
    local sharedJobs = (QBCore and QBCore.Shared and QBCore.Shared.Jobs) or {}

    local function addJobGrades(jobName)
        local job = sharedJobs[jobName]
        if not job or type(job.grades) ~= 'table' then return end

        for _, grade in pairs(job.grades) do
            local label = ''
            if type(grade) == 'table' then
                label = trim(grade.name or grade.label or '')
            elseif type(grade) == 'string' then
                label = trim(grade)
            end

            if label ~= '' then
                labels[#labels + 1] = label
            end
        end
    end

    if primaryJobName and primaryJobName ~= '' then
        addJobGrades(primaryJobName)
    end

    if #labels == 0 and Config and Config.AllowedJobs then
        for allowedJob, enabled in pairs(Config.AllowedJobs) do
            if enabled == true then
                addJobGrades(allowedJob)
            end
        end
    end

    return labels
end

local function buildOnlineCitizenidSet()
    local online = {}
    local Players = QBCore.Functions.GetQBPlayers()
    for _, P in pairs(Players or {}) do
        if P and P.PlayerData and P.PlayerData.citizenid then
            online[P.PlayerData.citizenid] = true
        end
    end
    return online
end

local function enrichRosterRows(rows)
    local online = buildOnlineCitizenidSet()
    for _, r in ipairs(rows or {}) do
        local cid = r.citizenid
        r.isOnline = (cid and cid ~= '' and online[cid] == true) or false
    end
    return rows
end

local function notifyRosterChanged()
    TriggerEvent('pf_mdt:server:RosterUpdated')
end

local function ensureDefaultsIfEmpty()
    if not hasDb() then return end

    exports.oxmysql:scalar('SELECT COUNT(*) FROM pf_mdt_roster', {}, function(count)
        if (tonumber(count) or 0) > 0 then return end

        local inserts = getDefaultRosterRows()
        for _, r in ipairs(inserts) do
            r.officer_name = ''
            r.citizenid = nil
            r.notes = nil
        end

        local pending = #inserts
        if pending == 0 then return end

        for _, row in ipairs(inserts) do
            local now = os.date('%Y-%m-%d %H:%M:%S')
            exports.oxmysql:insert(
                'INSERT IGNORE INTO pf_mdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                { row.callsign, row.rank, row.officer_name, row.citizenid, row.unit_type, row.training_status, row.notes, now, now },
                function()
                    pending = pending - 1
                    if pending <= 0 then
                        dprint('[pf-policemdt] Roster defaults generated')
                    end
                end
            )
        end
    end)
end

local function reseedRoster(cb)
    if not hasDb() then
        if cb then cb(false, 'no_db') end
        return
    end

    exports.oxmysql:execute('DELETE FROM pf_mdt_roster', {}, function()
        local rows = getDefaultRosterRows()
        if #rows == 0 then
            if cb then cb(true) end
            notifyRosterChanged()
            return
        end

        local values = {}
        local params = {}
        local now = os.date('%Y-%m-%d %H:%M:%S')
        for _, r in ipairs(rows) do
            values[#values + 1] = '(?, ?, ?, NULL, ?, ?, NULL, ?, ?)'
            params[#params + 1] = r.callsign
            params[#params + 1] = r.rank
            params[#params + 1] = '' -- officer_name
            params[#params + 1] = r.unit_type
            params[#params + 1] = r.training_status
            params[#params + 1] = now
            params[#params + 1] = now
        end

        local sql = 'INSERT INTO pf_mdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES ' .. table.concat(values, ',')
        exports.oxmysql:execute(sql, params, function()
            if cb then cb(true) end
            notifyRosterChanged()
        end)
    end)
end

local function validateAndNormalizeRowPayload(payload)
    local data = payload or {}

    local id = tonumber(data.id)
    if not id then return nil, 'missing_id' end

    local callsign = trim(data.callsign)
    local rank = trim(data.rank)
    local officer_name = trim(data.officer_name)
    local citizenid = trim(data.citizenid)
    local unit_type = trim(data.unit_type)
    local training_status = trim(data.training_status)
    local notes = data.notes

    if callsign == '' then
        return nil, 'callsign_required'
    end
    if #callsign > 32 then
        return nil, 'callsign_too_long'
    end
    if #rank > 64 then
        return nil, 'rank_too_long'
    end
    if #officer_name > 128 then
        return nil, 'officer_name_too_long'
    end
    if #unit_type > 64 then
        return nil, 'unit_type_too_long'
    end

    if citizenid == '' then citizenid = nil end
    if training_status == '' then training_status = 'NONE' end
    if not TRAINING_STATUSES[training_status] then
        return nil, 'invalid_training_status'
    end

    if (citizenid and citizenid ~= '') or (officer_name ~= '') then
        if callsign == '' then
            return nil, 'callsign_required_when_assigned'
        end
    end

    if notes ~= nil then
        notes = tostring(notes)
    end

    return {
        id = id,
        callsign = callsign,
        rank = rank,
        officer_name = officer_name,
        citizenid = citizenid,
        unit_type = unit_type,
        training_status = training_status,
        notes = notes,
        confirmDuplicate = data.confirmDuplicate == true,
    }, nil
end

local function doUpdateRow(source, payload, cb)
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end
    if not isGrade4Plus(source) then cb({ success = false, error = 'no_permission' }); return end

    local data, err = validateAndNormalizeRowPayload(payload)
    if not data then cb({ success = false, error = err }); return end

    exports.oxmysql:execute('SELECT id, citizenid FROM pf_mdt_roster WHERE id = ? LIMIT 1', { data.id }, function(rows)
        if not rows or not rows[1] then
            cb({ success = false, error = 'row_not_found' })
            return
        end

        exports.oxmysql:execute('SELECT id FROM pf_mdt_roster WHERE callsign = ? AND id <> ? LIMIT 1', { data.callsign, data.id }, function(dupe)
            if dupe and dupe[1] then
                cb({ success = false, error = 'callsign_not_unique' })
                return
            end

            if data.citizenid and data.citizenid ~= '' then
                exports.oxmysql:execute('SELECT id, callsign FROM pf_mdt_roster WHERE citizenid = ? AND id <> ? LIMIT 1', { data.citizenid, data.id }, function(crows)
                    if crows and crows[1] and not data.confirmDuplicate then
                        cb({
                            success = false,
                            error = 'citizenid_already_assigned',
                            requiresConfirm = true,
                            conflict = crows[1]
                        })
                        return
                    end

                    exports.oxmysql:execute(
                        'UPDATE pf_mdt_roster SET callsign = ?, rank = ?, officer_name = ?, citizenid = ?, unit_type = ?, training_status = ?, notes = ?, updated_at = NOW() WHERE id = ?',
                        { data.callsign, data.rank, data.officer_name, data.citizenid, data.unit_type, data.training_status, data.notes, data.id },
                        function()
                            exports.oxmysql:execute('SELECT * FROM pf_mdt_roster WHERE id = ? LIMIT 1', { data.id }, function(updated)
                                local row = updated and updated[1] or nil
                                if row then
                                    enrichRosterRows({ row })
                                end

                                local jobName, gradeLevel, Player = getPlayerJobAndGrade(source)
                                local actorCid = Player and Player.PlayerData and Player.PlayerData.citizenid or 'unknown'
                                dprint(('[pf-policemdt] Roster updated by %s (%s:%s) id=%s callsign=%s'):format(actorCid, tostring(jobName), tostring(gradeLevel), tostring(data.id), data.callsign))

                                notifyRosterChanged()
                                cb({ success = true, row = row })
                            end)
                        end
                    )
                end)
            else
                exports.oxmysql:execute(
                    'UPDATE pf_mdt_roster SET callsign = ?, rank = ?, officer_name = ?, citizenid = NULL, unit_type = ?, training_status = ?, notes = ?, updated_at = NOW() WHERE id = ?',
                    { data.callsign, data.rank, data.officer_name, data.unit_type, data.training_status, data.notes, data.id },
                    function()
                        exports.oxmysql:execute('SELECT * FROM pf_mdt_roster WHERE id = ? LIMIT 1', { data.id }, function(updated)
                            local row = updated and updated[1] or nil
                            if row then
                                enrichRosterRows({ row })
                            end

                            local jobName, gradeLevel, Player = getPlayerJobAndGrade(source)
                            local actorCid = Player and Player.PlayerData and Player.PlayerData.citizenid or 'unknown'
                            dprint(('[pf-policemdt] Roster updated by %s (%s:%s) id=%s callsign=%s'):format(actorCid, tostring(jobName), tostring(gradeLevel), tostring(data.id), data.callsign))

                            notifyRosterChanged()
                            cb({ success = true, row = row })
                        end)
                    end
                )
            end
        end)
    end)
end

local function computeNextForGroup(unitType, groupKey, existingCallsigns)
    local maxNum = nil

    local function consider(n)
        n = tonumber(n)
        if not n then return end
        if not maxNum or n > maxNum then maxNum = n end
    end

    local upperGroup = tostring(groupKey or '')

    if upperGroup == 'NUMERIC' then
        for _, cs in ipairs(existingCallsigns or {}) do
            local n = cs:match('^(%d+)$')
            if n then consider(n) end
        end
        if maxNum then return tostring(maxNum + 1) end
        local ut = tostring(unitType or ''):lower()
        if ut == 'command' then return '1' end
        if ut == 'numeric' then return '101' end
        return '101'
    end

    if upperGroup == 'K-9' or upperGroup == 'K9' then
        for _, cs in ipairs(existingCallsigns or {}) do
            local n = cs:match('^K%-9%-(%d+)$') or cs:match('^K9%-(%d+)$')
            if n then consider(n) end
        end
        return ('K-9-%d'):format((maxNum or 0) + 1)
    end

    -- digit+letters or letters+digits group keys: use -NN suffix (2 digits)
    if upperGroup:match('^%d+[A-Z]+$') or upperGroup:match('^[A-Z]+%d+$') then
        for _, cs in ipairs(existingCallsigns or {}) do
            local suffix = cs:match('^' .. upperGroup:gsub('%-', '%%-') .. '%-(%d+)$')
            if suffix then consider(suffix) end
        end
        return ('%s-%02d'):format(upperGroup, (maxNum or 0) + 1)
    end

    -- letters only group (Air-1)
    if upperGroup:match('^[A-Z]+$') then
        for _, cs in ipairs(existingCallsigns or {}) do
            local suffix = cs:match('^' .. upperGroup .. '%-(%d+)$')
            if suffix then consider(suffix) end
        end
        return ('%s-%d'):format(upperGroup, (maxNum or 0) + 1)
    end

    return nil
end

local function generatePlaceholderCallsign()
    local t = os.time()
    local r = math.random(100, 999)
    local cs = ('NEW-%s-%s'):format(tostring(t), tostring(r))
    if #cs > 32 then
        cs = ('NEW-%s'):format(tostring(t))
        if #cs > 32 then cs = cs:sub(1, 32) end
    end
    return cs
end

local function doAddRow(source, payload, cb)
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end
    if not isGrade4Plus(source) then cb({ success = false, error = 'no_permission' }); return end

    local unitType = trim(payload and payload.unit_type)
    local groupKey = trim(payload and payload.groupKey)

    local callsign = nil

    if groupKey ~= '' then
        local like = groupKey .. '-%'
        exports.oxmysql:execute('SELECT callsign FROM pf_mdt_roster WHERE callsign LIKE ? ORDER BY id DESC LIMIT 250', { like }, function(rows)
            local callsigns = {}
            for _, r in ipairs(rows or {}) do
                if r.callsign then callsigns[#callsigns+1] = tostring(r.callsign):upper() end
            end
            callsign = computeNextForGroup(unitType, groupKey:upper(), callsigns)
            if not callsign then
                callsign = generatePlaceholderCallsign()
            end

            exports.oxmysql:execute('SELECT id FROM pf_mdt_roster WHERE callsign = ? LIMIT 1', { callsign }, function(dupe)
                if dupe and dupe[1] then
                    callsign = generatePlaceholderCallsign()
                end

                local rank = defaultRankForUnitType(unitType)
                local training = defaultTrainingForUnitType(unitType)
                local now = os.date('%Y-%m-%d %H:%M:%S')
                exports.oxmysql:insert(
                    'INSERT INTO pf_mdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?, NULL, ?, ?)',
                    { callsign, rank, '', unitType, training, now, now },
                    function(insertId)
                        exports.oxmysql:execute('SELECT * FROM pf_mdt_roster WHERE id = ? LIMIT 1', { insertId }, function(newRows)
                            local row = newRows and newRows[1] or nil
                            if row then enrichRosterRows({ row }) end
                            notifyRosterChanged()
                            cb({ success = true, row = row })
                        end)
                    end
                )
            end)
        end)
        return
    end

    callsign = generatePlaceholderCallsign()
    local rank = defaultRankForUnitType(unitType)
    local training = defaultTrainingForUnitType(unitType)
    local now = os.date('%Y-%m-%d %H:%M:%S')
    exports.oxmysql:insert(
        'INSERT INTO pf_mdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?, NULL, ?, ?)',
        { callsign, rank, '', unitType, training, now, now },
        function(insertId)
            exports.oxmysql:execute('SELECT * FROM pf_mdt_roster WHERE id = ? LIMIT 1', { insertId }, function(newRows)
                local row = newRows and newRows[1] or nil
                if row then enrichRosterRows({ row }) end
                notifyRosterChanged()
                cb({ success = true, row = row })
            end)
        end
    )
end

QBCore.Functions.CreateCallback('pf_mdt:roster:getOfficerDirectory', function(source, cb)
    local jobName = select(1, getPlayerJobAndGrade(source))
    if not isAllowedJob(jobName) then cb({ success = false, error = 'no_access' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    buildOfficerDirectory(function(ok, dataOrErr)
        if not ok then
            cb({ success = false, error = dataOrErr or 'failed' })
            return
        end
        cb({ success = true, officers = dataOrErr or {} })
    end)
end)

local function doDeleteRow(source, payload, cb)
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end
    if not isGrade4Plus(source) then cb({ success = false, error = 'no_permission' }); return end

    local id = tonumber(payload and payload.id)
    if not id then cb({ success = false, error = 'missing_id' }); return end

    exports.oxmysql:execute('SELECT id, rank, officer_name, citizenid FROM pf_mdt_roster WHERE id = ? LIMIT 1', { id }, function(rows)
        if not rows or not rows[1] then cb({ success = false, error = 'row_not_found' }); return end

        local r = rows[1]
        local rr = tostring(r.rank or '')
        if rr == 'Chief' or rr == 'Chief of Police' then
            cb({ success = false, error = 'protected_chief' })
            return
        end

        local hasAssignment = (r.officer_name and tostring(r.officer_name) ~= '') or (r.citizenid and tostring(r.citizenid) ~= '')
        if hasAssignment then
            cb({ success = false, error = 'cannot_delete_assigned' })
            return
        end

        exports.oxmysql:execute('DELETE FROM pf_mdt_roster WHERE id = ?', { id }, function()
            notifyRosterChanged()
            cb({ success = true })
        end)
    end)
end

-- Callbacks
QBCore.Functions.CreateCallback('pf_mdt:getRoster', function(source, cb, filters)
    local jobName = select(1, getPlayerJobAndGrade(source))
    if not isAllowedJob(jobName) then cb({ success = false, error = 'no_access' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    filters = filters or {}
    local search = trim(filters.search)
    local rank = trim(filters.rank)
    local unitType = trim(filters.unit_type)
    local training = trim(filters.training_status)

    local where = 'WHERE 1=1'
    local params = {}

    if rank ~= '' then
        where = where .. ' AND rank = ?'
        params[#params+1] = rank
    end
    if unitType ~= '' then
        where = where .. ' AND unit_type = ?'
        params[#params+1] = unitType
    end
    if training ~= '' then
        where = where .. ' AND training_status = ?'
        params[#params+1] = training
    end
    if search ~= '' then
        where = where .. ' AND (callsign LIKE ? OR officer_name LIKE ?)'
        local like = '%' .. search .. '%'
        params[#params+1] = like
        params[#params+1] = like
    end

    exports.oxmysql:execute('SELECT id, callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at FROM pf_mdt_roster ' .. where .. ' ORDER BY unit_type ASC, callsign ASC', params, function(rows)
        rows = rows or {}
        enrichRosterRows(rows)
        cb({ success = true, rows = rows })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:getRosterMeta', function(source, cb)
    local jobName = select(1, getPlayerJobAndGrade(source))
    if not isAllowedJob(jobName) then cb({ success = false, error = 'no_access' }); return end

    local baseRanks = {}
    for _, rank in ipairs(DEFAULT_META.ranks or {}) do baseRanks[#baseRanks + 1] = rank end
    for _, rank in ipairs(getConfiguredGradeLabels(jobName)) do baseRanks[#baseRanks + 1] = rank end

    local function mergeMetaValues(defaults, dbRows, field)
        local seen = {}
        local values = { '' }

        local function addValue(v)
            v = trim(v)
            if v == '' then return end
            local lk = string.lower(v)
            if not seen[lk] then
                seen[lk] = true
                values[#values + 1] = v
            end
        end

        for _, v in ipairs(defaults or {}) do addValue(v) end
        for _, row in ipairs(dbRows or {}) do addValue(row[field]) end

        table.sort(values, function(a, b)
            if a == '' then return true end
            if b == '' then return false end
            return string.lower(a) < string.lower(b)
        end)

        return values
    end

    if hasOxMySQL() and exports.oxmysql then
        exports.oxmysql:execute('SELECT DISTINCT rank, unit_type FROM pf_mdt_roster', {}, function(rows)
            cb({
                success = true,
                ranks = mergeMetaValues(baseRanks, rows, 'rank'),
                unitTypes = mergeMetaValues(DEFAULT_META.unit_types, rows, 'unit_type'),
                trainingStatuses = DEFAULT_META.training_statuses,
                canEdit = isGrade4Plus(source)
            })
        end)
        return
    end

    cb({
        success = true,
        ranks = mergeMetaValues(baseRanks, nil, 'rank'),
        unitTypes = DEFAULT_META.unit_types,
        trainingStatuses = DEFAULT_META.training_statuses,
        canEdit = isGrade4Plus(source)
    })
end)

-- Operational callbacks (used by NUI) + matching events (per spec)
QBCore.Functions.CreateCallback('pf_mdt:roster:updateRowCb', function(source, cb, data)
    doUpdateRow(source, data, cb)
end)

QBCore.Functions.CreateCallback('pf_mdt:roster:addRowCb', function(source, cb, data)
    doAddRow(source, data, cb)
end)

QBCore.Functions.CreateCallback('pf_mdt:roster:deleteRowCb', function(source, cb, data)
    doDeleteRow(source, data, cb)
end)

QBCore.Functions.CreateCallback('pf_mdt:roster:resetCb', function(source, cb)
    if not isGrade4Plus(source) then cb({ success = false, error = 'no_permission' }); return end
    reseedRoster(function(ok, err)
        if not ok then cb({ success = false, error = err or 'failed' }); return end
        cb({ success = true })
    end)
end)

RegisterNetEvent('pf_mdt:roster:updateRow', function(rowData)
    local src = source
    doUpdateRow(src, rowData, function(_) end)
end)

RegisterNetEvent('pf_mdt:roster:addRow', function(data)
    local src = source
    doAddRow(src, data, function(_) end)
end)

RegisterNetEvent('pf_mdt:roster:deleteRow', function(data)
    local src = source
    doDeleteRow(src, data, function(_) end)
end)

-- Reset/reseed command (console or grade4+ LEO)
if isDebugEnabled() then
    RegisterCommand('pfmdt_roster_reset', function(source)
        local src = tonumber(source) or 0
        if src ~= 0 and not isGrade4Plus(src) then
            dprint('[pf-policemdt] pfmdt_roster_reset denied (no_permission)')
            return
        end

        reseedRoster(function(ok, err)
            if not ok then
                dprint(('[pf-policemdt] Roster reset failed: %s'):format(tostring(err or 'failed')))
                return
            end
            dprint('[pf-policemdt] Roster reset complete (defaults re-seeded)')
        end)
    end, false)
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    math.randomseed(GetGameTimer())
    ensureDefaultsIfEmpty()
end)
