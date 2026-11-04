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

local function getIsOwnerFlag(player)
    local meta = player and player.PlayerData and player.PlayerData.metadata or {}
    return type(meta) == 'table' and (meta.isOwner == true or meta.isowner == true or meta.owner == true)
end

-- Minimum grade for an action in this job (Config.Permissions[action][job], or the default given).
local function minGrade(action, jobName, default)
    local perms = Config and Config.Permissions and Config.Permissions[action]
    if type(perms) == 'number' then return perms end
    return type(perms) == 'table' and tonumber(perms[jobName]) or default
end

-- Rank for roster changes: Config.Permissions.manageRoster (grade 4 by default) or the owner flag.
-- Shown as canEdit; a change also needs the editor on duty (canChangeRoster).
local function isGrade4Plus(source)
    local jobName, gradeLevel, Player = getPlayerJobAndGrade(source)
    if not isAllowedJob(jobName) then return false end
    return (gradeLevel or 0) >= minGrade('manageRoster', jobName, 4) or getIsOwnerFlag(Player)
end

local function canChangeRoster(source)
    local _, _, Player = getPlayerJobAndGrade(source)
    local job = Player and Player.PlayerData and Player.PlayerData.job
    return isGrade4Plus(source) and type(job) == 'table' and job.onduty == true
end

-- The department boss (job.isboss, or the top grade of that job), or the owner flag.
local function isBoss(source)
    local jobName, gradeLevel, Player = getPlayerJobAndGrade(source)
    if not isAllowedJob(jobName) or not Player then return false end
    if Player.PlayerData.job.isboss == true or getIsOwnerFlag(Player) then return true end
    local def = QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[jobName]
    local top = nil
    for g in pairs(type(def) == 'table' and type(def.grades) == 'table' and def.grades or {}) do
        local n = tonumber(g)
        if n and (not top or n > top) then top = n end
    end
    return top ~= nil and (gradeLevel or 0) >= top
end

local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if type(rawget(v, '__cfx_functionReference')) == 'string' then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

local function decodeJob(v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' then return nil end
    local ok, t = pcall(json.decode, v)
    return ok and type(t) == 'table' and t or nil
end

-- A citizen's current job (live when online, else the players row): calls done(name, grade).
local function citizenJob(cid, done)
    local get = QBCore.Functions.GetPlayerByCitizenId
    local okLive, live = false, nil
    if callable(get) then okLive, live = pcall(get, cid) end
    if okLive and type(live) == 'table' and live.PlayerData and type(live.PlayerData.job) == 'table' then
        local j = live.PlayerData.job
        return done(j.name, type(j.grade) == 'table' and tonumber(j.grade.level) or tonumber(j.grade) or 0)
    end
    exports.oxmysql:execute('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local j = rows and rows[1] and decodeJob(rows[1].job) or nil
        if not j then return done(nil, nil) end
        done(j.name, type(j.grade) == 'table' and tonumber(j.grade.level) or tonumber(j.grade) or 0)
    end)
end

local PROTECTED_RANKS = { ['Chief'] = true, ['EMS Chief'] = true, ['Fire Chief'] = true }

local function hasDb()
    return exports and exports.oxmysql ~= nil
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

local TRAINING_STATUSES = { NONE = true, TRAINING = true, TRAINEE = true }

local DEFAULT_RANK_BY_UNIT_TYPE = {
    ['Command'] = 'EMS Chief',
    ['Supervision'] = 'EMS Supervisor',
    ['Ambulance'] = 'Paramedic',
    ['Training'] = 'Trainee',
    ['Rescue'] = 'Rescue',
    ['Other'] = '',
}

local function defaultRankForUnitType(unitType)
    local ut = trim(unitType)
    if ut == '' then return '' end
    return DEFAULT_RANK_BY_UNIT_TYPE[ut] or ''
end

local function defaultTrainingForUnitType(unitType)
    local ut = trim(unitType)
    if ut == 'Training' then return 'TRAINEE' end
    return 'NONE'
end

local officerDirectoryCache = { at = 0, data = nil }

local ROSTER_TABLE = 'pf_emsmdt_roster'
local LEGACY_ROSTER_TABLE = 'pf_mdt_roster'

local ensureDefaultsIfEmpty

-- The roster tables come from server/schema.lua (v1 backups, v2 the roster). Start-up work waits for it.
local function schemaReady()
    return PFEmsSchema ~= nil and PFEmsSchema.Ready() == true
end

-- Legacy pf_mdt_roster copy into an empty EMS roster: off unless Config.MigrateLegacyPoliceTables (that
-- table is the police MDT's roster on this server). Calls done() when finished either way.
local function copyLegacyRoster(done)
    if Config.MigrateLegacyPoliceTables ~= true or not hasDb() then return done() end
    exports.oxmysql:scalar(
        'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
        { LEGACY_ROSTER_TABLE },
        function(legacyExists)
            if (tonumber(legacyExists) or 0) <= 0 then return done() end
            exports.oxmysql:scalar(('SELECT COUNT(*) FROM `%s`'):format(ROSTER_TABLE), {}, function(newCount)
                if (tonumber(newCount) or 0) > 0 then return done() end
                exports.oxmysql:execute(([[
                    INSERT INTO `%s` (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at)
                    SELECT callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at
                    FROM `%s`
                ]]):format(ROSTER_TABLE, LEGACY_ROSTER_TABLE), {}, function() done() end)
            end)
        end
    )
end

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
        -- Command / Supervision
        { callsign = 'EMS-01', rank = 'EMS Chief', unit_type = 'Command', training_status = 'NONE' },
        { callsign = 'EMS-02', rank = 'EMS Deputy Chief', unit_type = 'Command', training_status = 'NONE' },
        { callsign = 'EMS-10', rank = 'EMS Supervisor', unit_type = 'Supervision', training_status = 'NONE' },

        -- Ambulance / Transport
        { callsign = 'MED-11', rank = 'Paramedic', unit_type = 'Ambulance', training_status = 'NONE' },
        { callsign = 'MED-12', rank = 'Paramedic', unit_type = 'Ambulance', training_status = 'NONE' },
        { callsign = 'MED-13', rank = 'EMT', unit_type = 'Ambulance', training_status = 'NONE' },

        -- Training
        { callsign = 'MED-20', rank = 'Field Training Officer', unit_type = 'Training', training_status = 'NONE' },
        { callsign = 'MED-21', rank = 'Trainee', unit_type = 'Training', training_status = 'TRAINEE' },

        -- Fire / Rescue (optional)
        { callsign = 'RES-31', rank = 'Rescue', unit_type = 'Rescue', training_status = 'NONE' },
    }
end

local DEFAULT_META = {
    ranks = {
        '',
        -- Command / Supervision
        'EMS Chief',
        'EMS Deputy Chief',
        'EMS Captain',
        'EMS Lieutenant',
        'EMS Supervisor',

        -- Field / Training
        'Paramedic',
        'EMT',
        'Field Training Officer',
        'Trainee',

        -- Specialty
        'Rescue',
        'Dispatch',
    },
    unit_types = {
        '',
        -- EMS MDT
        'Command',
        'Supervision',
        'Ambulance',
        'Training',
        'Rescue',
        'Support',
        'Other',
    },
    training_statuses = { 'NONE', 'TRAINING', 'TRAINEE' }
}

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
    TriggerEvent('pf_emsmdt:server:RosterUpdated')
end

ensureDefaultsIfEmpty = function()
    if not hasDb() or not schemaReady() then return end

    exports.oxmysql:scalar('SELECT COUNT(*) FROM pf_emsmdt_roster', {}, function(count)
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
            exports.oxmysql:insert(
                'INSERT IGNORE INTO pf_emsmdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())',
                { row.callsign, row.rank, row.officer_name, row.citizenid, row.unit_type, row.training_status, row.notes },
                function()
                    pending = pending - 1
                    if pending <= 0 then
                        dprint('[pf-emsmdt] Roster defaults generated')
                    end
                end
            )
        end
    end)
end

-- Reset: every line is copied to pf_emsmdt_roster_backup first (one batch per reset), then only the
-- lines nobody holds are removed and the default lines come back; assigned lines and their
-- callsigns stay. (It used to delete the whole roster, with no copy.)
local function reseedRoster(cb, actorCid)
    if not hasDb() then
        if cb then cb(false, 'no_db') end
        return
    end
    -- no backup table, no reset: the schema (v1 holds the backup table) is applied now if it has not
    -- been yet. The copy below is checked too, so a missing table refuses the reset in any case.
    if PFEmsSchema and not PFEmsSchema.Ensure() then
        if cb then cb(false, 'backup_unavailable') end
        return
    end
    local batch = ('%d-%d'):format(os.time(), math.random(100000, 999999))
    exports.oxmysql:execute([[INSERT INTO pf_emsmdt_roster_backup (batch, roster_id, callsign, `rank`, officer_name, citizenid, unit_type, training_status, notes, by_citizenid)
        SELECT ?, id, callsign, `rank`, officer_name, citizenid, unit_type, training_status, notes, ? FROM pf_emsmdt_roster]], { batch, actorCid }, function(copied)
        -- oxmysql answers an INSERT with a result table; anything else means the copy failed
        if type(copied) ~= 'table' then
            if cb then cb(false, 'backup_failed') end
            return
        end
        exports.oxmysql:execute("DELETE FROM pf_emsmdt_roster WHERE (citizenid IS NULL OR citizenid = '') AND officer_name = ''", {}, function()
            local rows = getDefaultRosterRows()
            if #rows == 0 then
                if cb then cb(true, batch) end
                notifyRosterChanged()
                return
            end

            local values = {}
            local params = {}
            for _, r in ipairs(rows) do
                values[#values + 1] = '(?, ?, ?, NULL, ?, ?, NULL, NOW(), NOW())'
                params[#params + 1] = r.callsign
                params[#params + 1] = r.rank
                params[#params + 1] = '' -- officer_name
                params[#params + 1] = r.unit_type
                params[#params + 1] = r.training_status
            end

            local sql = 'INSERT IGNORE INTO pf_emsmdt_roster (callsign, `rank`, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES ' .. table.concat(values, ',')
            exports.oxmysql:execute(sql, params, function()
                print(('[pf-emsmdt] Roster reset by %s (backup batch %s)'):format(tostring(actorCid or 'console'), batch))
                if cb then cb(true, batch) end
                notifyRosterChanged()
            end)
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
        notes = tostring(notes):sub(1, 2000)
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
    if not canChangeRoster(source) then cb({ success = false, error = 'no_permission' }); return end

    local data, err = validateAndNormalizeRowPayload(payload)
    if not data then cb({ success = false, error = err }); return end
    local editorJob, editorGrade, Editor = getPlayerJobAndGrade(source)
    local editorCid = Editor and Editor.PlayerData and Editor.PlayerData.citizenid
    local boss = isBoss(source)

    exports.oxmysql:execute('SELECT id, citizenid, `rank` FROM pf_emsmdt_roster WHERE id = ? LIMIT 1', { data.id }, function(rows)
        if not rows or not rows[1] then
            cb({ success = false, error = 'row_not_found' })
            return
        end
        local current = rows[1]
        -- the chief's line is the boss's to change, and so is giving a line the chief's rank
        if (PROTECTED_RANKS[tostring(current.rank or '')] or PROTECTED_RANKS[data.rank]) and not boss then
            cb({ success = false, error = 'protected_chief' })
            return
        end

        -- A line held by another member of the same or a higher grade (or of another department) is
        -- not this editor's to change; a citizen written into a line must be in the editor's job now
        -- (a roster line used to let command fire anyone on the server, a police chief included).
        local function checkAssignee(nextStep)
            local held = current.citizenid and tostring(current.citizenid) ~= '' and tostring(current.citizenid) ~= tostring(editorCid) and current.citizenid or nil
            if not held or boss then return nextStep() end
            citizenJob(held, function(jobName, grade)
                if jobName and isAllowedJob(jobName) and jobName ~= editorJob then cb({ success = false, error = 'other_department' }) return end
                if jobName == editorJob and (grade or 0) >= (editorGrade or 0) then cb({ success = false, error = 'rank_too_high' }) return end
                nextStep()
            end)
        end
        local function checkNew(nextStep)
            if not data.citizenid or data.citizenid == '' or tostring(data.citizenid) == tostring(current.citizenid or '') then return nextStep() end
            citizenJob(data.citizenid, function(jobName)
                if jobName ~= editorJob then cb({ success = false, error = 'not_an_officer' }) return end
                nextStep()
            end)
        end
        checkAssignee(function() checkNew(function()

        exports.oxmysql:execute('SELECT id FROM pf_emsmdt_roster WHERE callsign = ? AND id <> ? LIMIT 1', { data.callsign, data.id }, function(dupe)
            if dupe and dupe[1] then
                cb({ success = false, error = 'callsign_not_unique' })
                return
            end

            if data.citizenid and data.citizenid ~= '' then
                exports.oxmysql:execute('SELECT id, callsign FROM pf_emsmdt_roster WHERE citizenid = ? AND id <> ? LIMIT 1', { data.citizenid, data.id }, function(crows)
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
                        'UPDATE pf_emsmdt_roster SET callsign = ?, rank = ?, officer_name = ?, citizenid = ?, unit_type = ?, training_status = ?, notes = ?, updated_at = NOW() WHERE id = ?',
                        { data.callsign, data.rank, data.officer_name, data.citizenid, data.unit_type, data.training_status, data.notes, data.id },
                        function()
                            exports.oxmysql:execute('SELECT * FROM pf_emsmdt_roster WHERE id = ? LIMIT 1', { data.id }, function(updated)
                                local row = updated and updated[1] or nil
                                if row then
                                    enrichRosterRows({ row })
                                end

                                local jobName, gradeLevel, Player = getPlayerJobAndGrade(source)
                                local actorCid = Player and Player.PlayerData and Player.PlayerData.citizenid or 'unknown'
                                dprint(('[pf-emsmdt] Roster updated by %s (%s:%s) id=%s callsign=%s'):format(actorCid, tostring(jobName), tostring(gradeLevel), tostring(data.id), data.callsign))

                                notifyRosterChanged()
                                cb({ success = true, row = row })
                            end)
                        end
                    )
                end)
            else
                exports.oxmysql:execute(
                    'UPDATE pf_emsmdt_roster SET callsign = ?, rank = ?, officer_name = ?, citizenid = NULL, unit_type = ?, training_status = ?, notes = ?, updated_at = NOW() WHERE id = ?',
                    { data.callsign, data.rank, data.officer_name, data.unit_type, data.training_status, data.notes, data.id },
                    function()
                        exports.oxmysql:execute('SELECT * FROM pf_emsmdt_roster WHERE id = ? LIMIT 1', { data.id }, function(updated)
                            local row = updated and updated[1] or nil
                            if row then
                                enrichRosterRows({ row })
                            end

                            local jobName, gradeLevel, Player = getPlayerJobAndGrade(source)
                            local actorCid = Player and Player.PlayerData and Player.PlayerData.citizenid or 'unknown'
                            dprint(('[pf-emsmdt] Roster updated by %s (%s:%s) id=%s callsign=%s'):format(actorCid, tostring(jobName), tostring(gradeLevel), tostring(data.id), data.callsign))

                            notifyRosterChanged()
                            cb({ success = true, row = row })
                        end)
                    end
                )
            end
        end)
        end) end)
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
    if not canChangeRoster(source) then cb({ success = false, error = 'no_permission' }); return end

    local unitType = trim(payload and payload.unit_type)
    local groupKey = trim(payload and payload.groupKey)

    local callsign = nil

    if groupKey ~= '' then
        local like = groupKey .. '-%'
        exports.oxmysql:execute('SELECT callsign FROM pf_emsmdt_roster WHERE callsign LIKE ? ORDER BY id DESC LIMIT 250', { like }, function(rows)
            local callsigns = {}
            for _, r in ipairs(rows or {}) do
                if r.callsign then callsigns[#callsigns+1] = tostring(r.callsign):upper() end
            end
            callsign = computeNextForGroup(unitType, groupKey:upper(), callsigns)
            if not callsign then
                callsign = generatePlaceholderCallsign()
            end

            exports.oxmysql:execute('SELECT id FROM pf_emsmdt_roster WHERE callsign = ? LIMIT 1', { callsign }, function(dupe)
                if dupe and dupe[1] then
                    callsign = generatePlaceholderCallsign()
                end

                local rank = defaultRankForUnitType(unitType)
                local training = defaultTrainingForUnitType(unitType)
                exports.oxmysql:insert(
                    'INSERT INTO pf_emsmdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?, NULL, NOW(), NOW())',
                    { callsign, rank, '', unitType, training },
                    function(insertId)
                        exports.oxmysql:execute('SELECT * FROM pf_emsmdt_roster WHERE id = ? LIMIT 1', { insertId }, function(newRows)
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
    exports.oxmysql:insert(
        'INSERT INTO pf_emsmdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?, NULL, NOW(), NOW())',
        { callsign, rank, '', unitType, training },
        function(insertId)
            exports.oxmysql:execute('SELECT * FROM pf_emsmdt_roster WHERE id = ? LIMIT 1', { insertId }, function(newRows)
                local row = newRows and newRows[1] or nil
                if row then enrichRosterRows({ row }) end
                notifyRosterChanged()
                cb({ success = true, row = row })
            end)
        end
    )
end

QBCore.Functions.CreateCallback('pf_emsmdt:roster:getOfficerDirectory', function(source, cb)
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
    if not canChangeRoster(source) then cb({ success = false, error = 'no_permission' }); return end

    local id = tonumber(payload and payload.id)
    if not id then cb({ success = false, error = 'missing_id' }); return end

    exports.oxmysql:execute('SELECT id, rank, officer_name, citizenid FROM pf_emsmdt_roster WHERE id = ? LIMIT 1', { id }, function(rows)
        if not rows or not rows[1] then cb({ success = false, error = 'row_not_found' }); return end

        local r = rows[1]
        local rr = tostring(r.rank or '')
        if rr == 'Chief' or rr == 'EMS Chief' or rr == 'Fire Chief' then
            cb({ success = false, error = 'protected_chief' })
            return
        end

        local hasAssignment = (r.officer_name and tostring(r.officer_name) ~= '') or (r.citizenid and tostring(r.citizenid) ~= '')
        if hasAssignment then
            cb({ success = false, error = 'cannot_delete_assigned' })
            return
        end

        exports.oxmysql:execute('DELETE FROM pf_emsmdt_roster WHERE id = ?', { id }, function()
            notifyRosterChanged()
            cb({ success = true })
        end)
    end)
end

-- Callbacks
QBCore.Functions.CreateCallback('pf_emsmdt:getRoster', function(source, cb, filters)
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

    exports.oxmysql:execute('SELECT id, callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at FROM pf_emsmdt_roster ' .. where .. ' ORDER BY unit_type ASC, callsign ASC', params, function(rows)
        rows = rows or {}
        enrichRosterRows(rows)
        cb({ success = true, rows = rows })
    end)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:getRosterMeta', function(source, cb)
    local jobName = select(1, getPlayerJobAndGrade(source))
    if not isAllowedJob(jobName) then cb({ success = false, error = 'no_access' }); return end
    cb({
        success = true,
        ranks = DEFAULT_META.ranks,
        unitTypes = DEFAULT_META.unit_types,
        trainingStatuses = DEFAULT_META.training_statuses,
        canEdit = isGrade4Plus(source)
    })
end)

-- Operational callbacks (used by NUI) + matching events (per spec)
QBCore.Functions.CreateCallback('pf_emsmdt:roster:updateRowCb', function(source, cb, data)
    doUpdateRow(source, data, cb)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:roster:addRowCb', function(source, cb, data)
    doAddRow(source, data, cb)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:roster:deleteRowCb', function(source, cb, data)
    doDeleteRow(source, data, cb)
end)

-- Boss only, on duty, in two steps: the first call answers with a token, the second must bring it
-- back within 30 seconds.
local resetTokens = {}
QBCore.Functions.CreateCallback('pf_emsmdt:roster:resetCb', function(source, cb, data)
    if not (isBoss(source) and canChangeRoster(source)) then cb({ success = false, error = 'no_permission' }); return end
    local token = type(data) == 'table' and type(data.token) == 'string' and data.token or nil
    local pending = resetTokens[source]
    if not token or not pending or pending.token ~= token or pending.expires < os.time() then
        local t = ('%d%06d'):format(os.time(), math.random(0, 999999))
        resetTokens[source] = { token = t, expires = os.time() + 30 }
        cb({ success = false, confirmRequired = true, token = t, expiresIn = 30, message = 'Send the reset again with this token within 30 seconds to confirm' })
        return
    end
    resetTokens[source] = nil
    local _, _, Player = getPlayerJobAndGrade(source)
    reseedRoster(function(ok, errOrBatch)
        if not ok then cb({ success = false, error = errOrBatch or 'failed' }); return end
        cb({ success = true, backup = errOrBatch })
    end, Player and Player.PlayerData and Player.PlayerData.citizenid)
end)
AddEventHandler('playerDropped', function() resetTokens[source] = nil end)

RegisterNetEvent('pf_emsmdt:roster:updateRow', function(rowData)
    local src = source
    doUpdateRow(src, rowData, function(_) end)
end)

RegisterNetEvent('pf_emsmdt:roster:addRow', function(data)
    local src = source
    doAddRow(src, data, function(_) end)
end)

RegisterNetEvent('pf_emsmdt:roster:deleteRow', function(data)
    local src = source
    doDeleteRow(src, data, function(_) end)
end)

-- Reset/reseed from the server console only. The police MDT registered the same command name
-- (pfmdt_roster_reset), so the two collided; this one is pfemsmdt_roster_reset.
RegisterCommand('pfemsmdt_roster_reset', function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    reseedRoster(function(ok, errOrBatch)
        if not ok then
            print(('[pf-emsmdt] Roster reset failed: %s'):format(tostring(errOrBatch or 'failed')))
            return
        end
        print(('[pf-emsmdt] Roster reset complete (backup batch %s)'):format(tostring(errOrBatch)))
    end, nil)
end, true)

-- A player who leaves the EMS departments leaves their roster line (the line stays, vacant).
AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    local P = QBCore.Functions.GetPlayer(tonumber(src) or src)
    local live = P and P.PlayerData and P.PlayerData.job
    if not live or isAllowedJob(live.name) or not hasDb() then return end
    exports.oxmysql:execute("UPDATE pf_emsmdt_roster SET officer_name = '', citizenid = NULL, updated_at = NOW() WHERE citizenid = ?", { P.PlayerData.citizenid }, function(n)
        local changed = type(n) == 'table' and (n.affectedRows or n.changedRows) or n
        if (tonumber(changed) or 0) > 0 then notifyRosterChanged() end
    end)
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    math.randomseed(GetGameTimer())
end)

-- Runs once the schema is ready (registered last, after every helper it calls): the opt-in legacy
-- copy first, then the default lines if the roster is still empty.
function PFEmsRosterStartup()
    copyLegacyRoster(function() ensureDefaultsIfEmpty() end)
end
if PFEmsSchema then
    PFEmsSchema.OnReady(PFEmsRosterStartup)
else
    print('^1[pf-emsmdt]^7 server/schema.lua is not loaded: the roster start-up seed is off')
end
