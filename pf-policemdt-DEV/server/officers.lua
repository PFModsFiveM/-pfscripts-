local QBCore = PFMdt.GetCore()

-- Forward declare for helpers that need it (defined later).
local getOnlinePlayerByCitizenId

-- Cache for optional qb-management DB fallback.
local mgmtFundsTableExists = nil

-- Ensure our tables/columns exist (some older MariaDB installs choke on IF NOT EXISTS migrations).
local _tablesEnsured = false
local function ensureTablesOnce()
    if _tablesEnsured then return end
    local ok, err = pcall(function()
        ensureTables()
    end)
    if ok then
        _tablesEnsured = true
    else
        print(('[pf-policemdt] OfficerMgmt ensureTables failed: %s'):format(tostring(err)))
    end
end

local function hasDb()
    return exports and exports.oxmysql ~= nil
end

local function isESXFramework()
    return PFMdt and PFMdt.GetFrameworkName and PFMdt.GetFrameworkName() == 'esx'
end

local function trim(val)
    return (tostring(val or ''):gsub('^%s*(.-)%s*$', '%1'))
end

local function isAllowedJob(jobName)
    return jobName ~= '' and Config and Config.AllowedJobs and Config.AllowedJobs[jobName] == true
end

local function getIsOwnerFlag(player)
    local meta = player and player.PlayerData and player.PlayerData.metadata or {}
    if type(meta) ~= 'table' then
        local ok, parsed = pcall(json.decode, meta)
        if ok and type(parsed) == 'table' then meta = parsed else meta = {} end
    end
    return meta.isOwner == true or meta.isowner == true or meta.owner == true
end

local function getPlayerInfo(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end
    local job = Player.PlayerData.job or {}
    local grade = (job.grade and job.grade.level) or 0
    local jobName = job.name or ''
    return {
        player = Player,
        jobName = jobName,
        grade = grade,
        allowed = isAllowedJob(jobName),
        isOwner = getIsOwnerFlag(Player),
    }
end

local function canManage(info)
    return info and info.allowed and ((info.grade or 0) >= 4 or info.isOwner)
end

local function getFullNameFromCharinfo(charinfo)
    local ci = charinfo or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name
end

local function decodeMaybeJson(v)
    if type(v) ~= 'string' then return v end
    local ok, parsed = pcall(json.decode, v)
    if ok then return parsed end
    return v
end

local function firstAllowedJobName()
    if not Config or not Config.AllowedJobs then return 'police' end
    if Config.AllowedJobs.police == true then return 'police' end
    for k, v in pairs(Config.AllowedJobs) do
        if v == true and tostring(k) ~= '' then return tostring(k) end
    end
    return 'police'
end

local function getSocietyJobName(info)
    if info and isAllowedJob(info.jobName or '') then return tostring(info.jobName) end
    return firstAllowedJobName()
end

-- Convert MySQL DATETIME string to Unix timestamp
local function parseMysqlDateStringToTimestamp(d)
    if not d then return nil end
    if type(d) == 'number' then return d end
    local y, m, day, hh, mm, ss = tostring(d):match('^(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
    if not y then
        y, m, day = tostring(d):match('^(%d+)-(%d+)-(%d+)$')
        hh, mm, ss = '00', '00', '00'
    end
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(day), hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) })
end

-- Convert Unix timestamp (or MySQL timestamp number) back to datetime string
local function formatTimestampToMysqlDateString(ts)
    if not ts then return nil end
    if type(ts) == 'string' then
        -- If it's already a string and looks like a datetime, return it
        if ts:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d') then
            return ts
        end
    end
    -- Convert number (timestamp) to datetime string
    if type(ts) == 'number' then
        -- Handle millisecond timestamps (divide by 1000)
        if ts > 100000000000 then
            ts = math.floor(ts / 1000)
        end
        return os.date('%Y-%m-%d %H:%M:%S', ts)
    end
    return tostring(ts)
end

local function ensureColumn(tableName, columnName, columnDef)
    if not hasDb() then return end
    tableName = trim(tableName)
    columnName = trim(columnName)
    if tableName == '' or columnName == '' or trim(columnDef) == '' then return end

    local p = promise.new()
    exports.oxmysql:execute(
        'SELECT COUNT(*) AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tableName, columnName },
        function(rows)
            local exists = (rows and rows[1] and tonumber(rows[1].c) or 0) > 0
            if exists then
                p:resolve(true)
                return
            end
            exports.oxmysql:execute(('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, columnDef), {}, function()
                p:resolve(true)
            end)
        end
    )
    Citizen.Await(p)
end

local function ensureTables()
    if not hasDb() then return end

    exports.oxmysql:execute([[
                CREATE TABLE IF NOT EXISTS `pf_mdt_officer_mgmt_profiles` (
          `citizenid` VARCHAR(64) NOT NULL,
          `hire_date` DATETIME NULL,
          `probation_until` DATETIME NULL,
          `is_fto` TINYINT(1) NOT NULL DEFAULT 0,
          `status` VARCHAR(32) NOT NULL DEFAULT 'ACTIVE',
                    `terminated` TINYINT(1) NOT NULL DEFAULT 0,
                    `terminated_at` DATETIME NULL,
                    `terminated_by` VARCHAR(128) NULL,
                    `terminated_reason` VARCHAR(255) NULL,
          `restrictions_json` LONGTEXT NULL,
          `flags_json` LONGTEXT NULL,
          `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Best-effort schema upgrades for existing installs (works on older MariaDB too).
    ensureColumn('pf_mdt_officer_mgmt_profiles', 'status', "`status` VARCHAR(32) NOT NULL DEFAULT 'ACTIVE'")
    ensureColumn('pf_mdt_officer_mgmt_profiles', 'terminated', '`terminated` TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('pf_mdt_officer_mgmt_profiles', 'terminated_at', '`terminated_at` DATETIME NULL')
    ensureColumn('pf_mdt_officer_mgmt_profiles', 'terminated_by', '`terminated_by` VARCHAR(128) NULL')
    ensureColumn('pf_mdt_officer_mgmt_profiles', 'terminated_reason', '`terminated_reason` VARCHAR(255) NULL')
    ensureColumn('pf_mdt_officer_mgmt_profiles', 'is_supervisor', '`is_supervisor` TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('pf_mdt_weapons_registry', 'stolen_status', '`stolen_status` TINYINT(1) NOT NULL DEFAULT 0')

    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS `pf_mdt_officer_discipline` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `citizenid` VARCHAR(64) NOT NULL,
          `type` VARCHAR(16) NOT NULL,
          `reason` TEXT NOT NULL,
          `issued_by` VARCHAR(128) NULL,
          `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `resolved_by` VARCHAR(128) NULL,
          `resolved_at` DATETIME NULL,
          `expires_at` DATETIME NULL,
          PRIMARY KEY (`id`),
          KEY `idx_disc_citizenid` (`citizenid`),
          KEY `idx_disc_active` (`active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS `pf_mdt_officer_audit` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `actor_citizenid` VARCHAR(64) NULL,
          `actor_name` VARCHAR(128) NULL,
          `target_citizenid` VARCHAR(64) NULL,
          `action` VARCHAR(64) NOT NULL,
          `before_json` LONGTEXT NULL,
          `after_json` LONGTEXT NULL,
          `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_audit_target` (`target_citizenid`),
          KEY `idx_audit_created` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end

local function audit(actorInfo, targetCitizenId, action, beforeObj, afterObj)
    if not hasDb() then return end
    local pd = actorInfo and actorInfo.player and actorInfo.player.PlayerData or {}
    local actorCid = pd.citizenid
    local actorName = getFullNameFromCharinfo(pd.charinfo)
    -- Avoid showing citizenid as the display name in UI (looks like random digits).
    if actorName == '' then actorName = 'Unknown' end

    local beforeJson = beforeObj and json.encode(beforeObj) or nil
    local afterJson = afterObj and json.encode(afterObj) or nil
    local now = os.date('%Y-%m-%d %H:%M:%S')

    exports.oxmysql:insert(
        'INSERT INTO `pf_mdt_officer_audit` (actor_citizenid, actor_name, target_citizenid, action, before_json, after_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { actorCid, actorName, targetCitizenId, action, beforeJson, afterJson, now }
    )
end

local function ensureProfileRow(citizenid)
    if not hasDb() then return end
    local now = os.date('%Y-%m-%d %H:%M:%S')
    exports.oxmysql:insert(
        'INSERT IGNORE INTO `pf_mdt_officer_mgmt_profiles` (citizenid, created_at, updated_at) VALUES (?, ?, ?)',
        { citizenid, now, now }
    )
end

local function getOnlineOfficerState()
    local stateByCid = {}
    local players = QBCore.Functions.GetQBPlayers()

    for _, P in pairs(players) do
        local pd = P.PlayerData or {}
        local cid = pd.citizenid
        if cid and tostring(cid) ~= '' then
            local currentJob = pd.job or {}
            local currentJobName = currentJob.name or ''
            local isWorking = isAllowedJob(currentJobName)

            local hasMemberJob = isWorking

            -- Multi-job compatibility: try common patterns
            local jobs = pd.jobs
            if type(jobs) == 'table' then
                for k, v in pairs(jobs) do
                    if type(v) == 'table' then
                        if isAllowedJob(v.name or k or '') then hasMemberJob = true end
                    else
                        if isAllowedJob(k) then hasMemberJob = true end
                    end
                end
            end

            local meta = pd.metadata or {}
            if type(meta) ~= 'table' then meta = decodeMaybeJson(meta) or {} end
            local metaJobs = meta.jobs or meta.multijob or meta.multiJob or meta.jobList
            if type(metaJobs) == 'table' then
                for k, v in pairs(metaJobs) do
                    if type(v) == 'table' then
                        if isAllowedJob(v.name or k or '') then hasMemberJob = true end
                    else
                        if isAllowedJob(k) then hasMemberJob = true end
                    end
                end
            end

            stateByCid[tostring(cid)] = {
                online = true,
                working = isWorking,
                hasPolice = hasMemberJob,
                currentJob = currentJobName,
                onduty = currentJob.onduty == true,
            }

            if hasMemberJob then
                ensureProfileRow(tostring(cid))
            end
        end
    end

    return stateByCid
end

local function upsertRosterForOfficer(citizenid, name, callsign, rank, unitType, trainingStatus)
    if not hasDb() then return false, 'no_db' end

    citizenid = trim(citizenid)
    if citizenid == '' then return false, 'invalid_id' end

    callsign = trim(callsign)
    rank = trim(rank)
    unitType = trim(unitType)
    trainingStatus = trim(trainingStatus)
    name = trim(name)

    if callsign == '' then return false, 'missing_callsign' end
    if #callsign > 32 then return false, 'callsign_too_long' end

    exports.oxmysql:execute(
        'SELECT id, citizenid FROM pf_mdt_roster WHERE callsign = ? LIMIT 1',
        { callsign },
        function(rows)
            local existing = rows and rows[1] or nil
            if existing and tostring(existing.citizenid or '') ~= '' and tostring(existing.citizenid) ~= citizenid then
                return
            end
        end
    )

    -- Duplicate callsign check (async-safe): do a second query synchronously via callback chain
    local p = promise.new()
    exports.oxmysql:execute('SELECT id, citizenid FROM pf_mdt_roster WHERE callsign = ? LIMIT 1', { callsign }, function(rows)
        local existing = rows and rows[1] or nil
        if existing and tostring(existing.citizenid or '') ~= '' and tostring(existing.citizenid) ~= citizenid then
            p:resolve({ ok = false, err = 'duplicate_callsign' })
            return
        end
        p:resolve({ ok = true })
    end)
    local dupeCheck = Citizen.Await(p)
    if not dupeCheck.ok then return false, dupeCheck.err end

    local p2 = promise.new()
    exports.oxmysql:execute('SELECT id FROM pf_mdt_roster WHERE citizenid = ? LIMIT 1', { citizenid }, function(rows)
        local row = rows and rows[1] or nil
        if row and row.id then
            exports.oxmysql:execute(
                'UPDATE pf_mdt_roster SET callsign = ?, rank = ?, officer_name = ?, unit_type = ?, training_status = ?, updated_at = NOW() WHERE id = ?',
                { callsign, rank, name, unitType, trainingStatus, row.id },
                function()
                    p2:resolve({ ok = true })
                end
            )
        else
            local now = os.date('%Y-%m-%d %H:%M:%S')
            exports.oxmysql:insert(
                'INSERT INTO pf_mdt_roster (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?)',
                { callsign, rank, name, citizenid, unitType, trainingStatus, now, now },
                function()
                    p2:resolve({ ok = true })
                end
            )
        end
    end)

    local res = Citizen.Await(p2)
    return res.ok == true
end

-- Staff actions only apply to police staff: someone with an allowed job now, or on the roster /
-- staff list (not terminated). Returns isStaff, currentGrade (nil when not in an allowed job now).
-- (Command could fire, discipline or flag any citizen on the server before, e.g. set an EMS chief
-- or a mechanic to unemployed.)
local function staffTarget(cid)
    local p = promise.new()
    exports.oxmysql:execute('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local job = rows and rows[1] and decodeMaybeJson(rows[1].job) or nil
        local jobName = type(job) == 'table' and job.name or nil
        local grade = type(job) == 'table' and job.grade and tonumber(job.grade.level) or nil
        if isAllowedJob(jobName or '') then p:resolve({ true, grade or 0 }) return end
        exports.oxmysql:execute('SELECT (SELECT COUNT(*) FROM pf_mdt_roster WHERE citizenid = ?) AS r, (SELECT COUNT(*) FROM pf_mdt_officer_mgmt_profiles WHERE citizenid = ? AND `terminated` = 0) AS s',
            { cid, cid }, function(srows)
                local r = srows and srows[1] or {}
                p:resolve({ (tonumber(r.r) or 0) > 0 or (tonumber(r.s) or 0) > 0, nil })
            end)
    end)
    local res = Citizen.Await(p)
    return res[1] == true, res[2]
end

local function clip(v, n)
    if type(v) ~= 'string' and type(v) ~= 'number' then return '' end
    return trim(v):sub(1, n)
end

local function canViewDiscipline(info, targetCitizenId)
    if not info or not info.player then return false end
    if canManage(info) then return true end
    return tostring(info.player.PlayerData.citizenid or '') == tostring(targetCitizenId or '')
end

-- ============================================================
-- Callbacks
-- ============================================================

QBCore.Functions.CreateCallback('pf_mdt:officers:getMeta', function(source, cb)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end

    -- Reuse roster meta lists (ranks/unit/training) by hardcoding server-side? Keep it simple:
    -- fetch from roster meta callback is not possible server-side, so return minimal.
    cb({
        success = true,
        canManage = canManage(info)
    })
end)

QBCore.Functions.CreateCallback('pf_mdt:officers:list', function(source, cb)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end
    ensureTablesOnce()

    -- Safety: do not leave the UI stuck on "Loading officers...".
    local replied = false
    local function replyOnce(payload)
        if replied then return end
        replied = true
        cb(payload)
    end
    SetTimeout(8000, function()
        replyOnce({ success = false, error = 'timeout_loading_officers' })
    end)

    local online = getOnlineOfficerState()

    -- Officer membership persistence:
    -- - If they ever held a police job (or are in roster), they should keep showing even if they swap jobs.
    -- - If they are terminated/fired, they must never show.
    exports.oxmysql:execute('SELECT citizenid FROM pf_mdt_officer_mgmt_profiles WHERE `terminated` = 0', {}, function(mrows)
        local saved = {}
        for _, r in ipairs(mrows or {}) do
            local cid = tostring(r.citizenid or '')
            if cid ~= '' then saved[cid] = true end
        end

        exports.oxmysql:execute('SELECT citizenid FROM pf_mdt_roster WHERE citizenid IS NOT NULL AND citizenid <> ""', {}, function(rrows)
            for _, r in ipairs(rrows or {}) do
                local cid = tostring(r.citizenid or '')
                if cid ~= '' then
                    saved[cid] = true
                    -- Ensure mgmt profile exists for roster officers
                    ensureProfileRow(cid)
                end
            end

            exports.oxmysql:execute('SELECT citizenid, charinfo, job FROM players', {}, function(rows)
                local result = {}

                for _, r in ipairs(rows or {}) do
                    local cid = tostring(r.citizenid or '')
                    if cid ~= '' then
                        local job = decodeMaybeJson(r.job) or {}
                        local jobName = (type(job) == 'table' and (job.name or job.label)) or tostring(job or '')
                        local allowedByDb = isAllowedJob(jobName)

                        -- If they currently have a police job, persist membership.
                        if allowedByDb then
                            saved[cid] = true
                            ensureProfileRow(cid)
                        end

                        local st = online[cid]

                        -- Treat as officer if:
                        -- - currently police job, OR
                        -- - online multi-job indicates police membership, OR
                        -- - previously saved membership (not terminated)
                        local isOfficer = saved[cid] == true or allowedByDb or (st and st.hasPolice)

                        if isOfficer then
                            local ci = decodeMaybeJson(r.charinfo) or {}
                            local name = getFullNameFromCharinfo(ci)
                            if name == '' then name = cid end

                            result[#result + 1] = {
                                citizenid = cid,
                                name = name,
                                online = st and st.online or false,
                                working = st and st.working or false,
                                duty = st and (st.onduty == true) or false,
                                currentJob = st and st.currentJob or jobName,
                                lastOnline = st and st.online and os.time() or nil, -- Current time if online
                                _rehireCandidate = (allowedByDb == true) or (st and st.hasPolice == true) or false,
                            }
                        end
                    end
                end

                local byCid = {}
                local citizenIds = {}
                for i = 1, #result do
                    byCid[result[i].citizenid] = result[i]
                    citizenIds[#citizenIds + 1] = result[i].citizenid
                end

                if #citizenIds == 0 then
                    replyOnce({ success = true, officers = {} })
                    return
                end

            local placeholders = {}
            for _ = 1, #citizenIds do placeholders[#placeholders + 1] = '?' end
            local inClause = table.concat(placeholders, ',')

                local pending = 3
                local function done()
                    pending = pending - 1
                    if pending > 0 then return end

                    -- Filter fired/terminated officers out completely
                    local filtered = {}
                    for i = 1, #result do
                        local cid = result[i].citizenid
                        local item = byCid[cid]
                        if item and item.terminated ~= true then
                            filtered[#filtered + 1] = item
                        end
                    end

                    table.sort(filtered, function(a, b)
                        return tostring(a.name or ''):lower() < tostring(b.name or ''):lower()
                    end)

                    replyOnce({ success = true, officers = filtered })
                end

                -- Merge roster fields
                exports.oxmysql:execute(
                    'SELECT citizenid, callsign, rank, unit_type, training_status FROM pf_mdt_roster WHERE citizenid IN (' .. inClause .. ')',
                    citizenIds,
                    function(rrows2)
                        for _, rr in ipairs(rrows2 or {}) do
                            local cid = tostring(rr.citizenid or '')
                            local item = byCid[cid]
                            if item then
                                item.callsign = rr.callsign or ''
                                item.rank = rr.rank or ''
                                item.unit_type = rr.unit_type or ''
                                item.training_status = rr.training_status or ''
                            end
                        end
                        done()
                    end
                )

                -- Merge mgmt profile fields (incl termination)
                exports.oxmysql:execute(
                    'SELECT * FROM pf_mdt_officer_mgmt_profiles WHERE citizenid IN (' .. inClause .. ')',
                    citizenIds,
                    function(prows)
                        for _, pr in ipairs(prows or {}) do
                            local cid = tostring(pr.citizenid or '')
                            local item = byCid[cid]
                            if item then
                                -- Check if probation has expired and auto-clear it
                                local probation = pr.probation_until
                                if probation and probation ~= '' then
                                    local probationStr = formatTimestampToMysqlDateString(probation)
                                    local expiryTime = parseMysqlDateStringToTimestamp(probationStr)
                                    if expiryTime and os.time() >= expiryTime then
                                        probation = nil
                                        -- Update database to clear expired probation
                                        exports.oxmysql:execute('UPDATE pf_mdt_officer_mgmt_profiles SET probation_until = NULL, updated_at = NOW() WHERE citizenid = ?', { cid })
                                    else
                                        probation = probationStr  -- Use formatted string
                                    end
                                end
                                
                                item.probation_until = probation or nil
                                item.is_fto = (tonumber(pr.is_fto) or 0) == 1
            item.is_supervisor = (tonumber(pr.is_supervisor) or 0) == 1
                                item.status = pr.status or 'ACTIVE'

                                local restrictions = decodeMaybeJson(pr.restrictions_json)
                                local flags = decodeMaybeJson(pr.flags_json)
                                item.restrictionCount = (type(restrictions) == 'table' and #restrictions) or 0
                                item.flagCount = (type(flags) == 'table' and #flags) or 0

                                item.terminated = (tonumber(pr.terminated) or 0) == 1

                                -- If someone was rehired (allowed job again), clear the terminated state so they reappear.
                                if item.terminated == true and item._rehireCandidate == true then
                                    item.terminated = false
                                    item.status = 'ACTIVE'
                                    exports.oxmysql:execute(
                                        'UPDATE pf_mdt_officer_mgmt_profiles SET `terminated` = 0, status = "ACTIVE", terminated_at = NULL, terminated_by = NULL, terminated_reason = NULL, updated_at = NOW() WHERE citizenid = ?',
                                        { cid }
                                    )
                                end
                            end
                        end
                        done()
                    end
                )

                -- Merge avatar URLs and last online from officer profiles
                exports.oxmysql:execute(
                    'SELECT citizenId, avatarUrl FROM pf_mdt_officer_profiles WHERE citizenId IN (' .. inClause .. ')',
                    citizenIds,
                    function(arows)
                        for _, ar in ipairs(arows or {}) do
                            local cid = tostring(ar.citizenId or '')
                            local item = byCid[cid]
                            if item then
                                item.avatarUrl = ar.avatarUrl or nil
                            end
                        end
                        done()
                    end
                )
            end)
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:officers:get', function(source, cb, data)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    ensureTablesOnce()

    -- Safety: do not leave the UI stuck on "Loading profile...".
    local replied = false
    local function replyOnce(payload)
        if replied then return end
        replied = true
        cb(payload)
    end
    SetTimeout(8000, function()
        replyOnce({ success = false, error = 'timeout_loading_profile' })
    end)

    local cid = trim((data and data.citizenid) or '')
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end

    ensureProfileRow(cid)

    exports.oxmysql:execute('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local row = rows and rows[1] or nil
        local ci = row and decodeMaybeJson(row.charinfo) or {}
        local name = getFullNameFromCharinfo(ci)
        if name == '' then name = cid end

        exports.oxmysql:execute('SELECT callsign, rank, unit_type, training_status, notes FROM pf_mdt_roster WHERE citizenid = ? LIMIT 1', { cid }, function(rrows)
            local roster = rrows and rrows[1] or {}

            exports.oxmysql:execute('SELECT * FROM pf_mdt_officer_mgmt_profiles WHERE citizenid = ? LIMIT 1', { cid }, function(prows)
                local prof = prows and prows[1] or {}

                -- Check if probation has expired and auto-clear it
                if prof.probation_until and prof.probation_until ~= '' then
                    local probationStr = formatTimestampToMysqlDateString(prof.probation_until)
                    local expiryTime = parseMysqlDateStringToTimestamp(probationStr)
                    if expiryTime and os.time() >= expiryTime then
                        prof.probation_until = nil
                        -- Update database to clear expired probation
                        exports.oxmysql:execute('UPDATE pf_mdt_officer_mgmt_profiles SET probation_until = NULL, updated_at = NOW() WHERE citizenid = ?', { cid })
                    else
                        prof.probation_until = probationStr  -- Use formatted string
                    end
                end

                local onlineMap = getOnlineOfficerState()
                local st = onlineMap[cid]

                local base = {
                    citizenid = cid,
                    name = name,
                    roster = roster,
                    profile = prof,
                    presence = {
                        online = st and st.online or false,
                        working = st and st.working or false,
                        duty = st and (st.onduty == true) or false,
                        currentJob = st and st.currentJob or ''
                    }
                }

                local tasksRemaining = 3
                local function done()
                    tasksRemaining = tasksRemaining - 1
                    if tasksRemaining <= 0 then
                        replyOnce({ success = true, data = base })
                    end
                end

                -- Discipline (restricted for non-command)
                if canViewDiscipline(info, cid) then
                    exports.oxmysql:execute('SELECT id, type, reason, issued_by, issued_at, active, resolved_by, resolved_at, expires_at FROM pf_mdt_officer_discipline WHERE citizenid = ? ORDER BY issued_at DESC LIMIT 50', { cid }, function(drows)
                        base.discipline = drows or {}
                        done()
                    end)
                else
                    base.discipline = nil
                    done()
                end

                -- Audit history
                exports.oxmysql:execute('SELECT id, actor_name, action, before_json, after_json, created_at FROM pf_mdt_officer_audit WHERE target_citizenid = ? ORDER BY created_at DESC LIMIT 50', { cid }, function(arows)
                    base.history = arows or {}
                    done()
                end)

                -- Activity overview (last 30 days)
                local since = os.date('%Y-%m-%d %H:%M:%S', os.time() - (30 * 24 * 60 * 60))
                local fullName = name
                exports.oxmysql:execute([[
                    SELECT
                      (SELECT COUNT(*) FROM pf_mdt_incidents WHERE createdBy = ? AND createdAt >= ?) AS incidents,
                      (SELECT COUNT(*) FROM pf_mdt_reports WHERE officer = ? AND createdAt >= ?) AS reports,
                      (SELECT COUNT(*) FROM pf_mdt_warrants WHERE issuedBy = ? AND createdAt >= ?) AS warrants,
                      (SELECT COUNT(*) FROM pf_mdt_evidence WHERE created_by_citizenid = ? AND created_at >= ?) AS evidence
                ]], { cid, since, fullName, since, fullName, since, cid, since }, function(actRows)
                    base.activity = (actRows and actRows[1]) or { incidents = 0, reports = 0, warrants = 0, evidence = 0 }
                    done()
                end)
            end)
        end)
    end)
end)

local function buildUnemployedJobJson()
    -- Keep this minimal but compatible with common QBCore job parsing
    return {
        name = 'unemployed',
        label = 'Unemployed',
        payment = 0,
        onduty = false,
        isboss = false,
        grade = { name = 'Unemployed', level = 0 }
    }
end

getOnlinePlayerByCitizenId = function(citizenid)
    local players = QBCore.Functions.GetQBPlayers()
    for _, P in pairs(players) do
        if P and P.PlayerData and tostring(P.PlayerData.citizenid or '') == tostring(citizenid or '') then
            return P
        end
    end
    return nil
end

QBCore.Functions.CreateCallback('pf_mdt:officers:fire', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    ensureTablesOnce()

    local cid = clip(payload and payload.citizenid, 50)
    local reason = clip(payload and payload.reason, 500)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end
    if cid == tostring(info.player.PlayerData.citizenid) then cb({ success = false, error = 'cannot_fire_self' }); return end
    local isStaff, targetGrade = staffTarget(cid)
    if not isStaff then cb({ success = false, error = 'not_staff' }); return end
    if targetGrade and targetGrade >= (info.grade or 0) and not info.isOwner then cb({ success = false, error = 'rank_too_high' }); return end

    ensureProfileRow(cid)

    local pd = info.player.PlayerData
    local actor = getFullNameFromCharinfo(pd.charinfo)
    if actor == '' then actor = 'Command' end

    exports.oxmysql:execute('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local beforeJob = rows and rows[1] and decodeMaybeJson(rows[1].job) or nil

        exports.oxmysql:execute('SELECT callsign, rank, unit_type, training_status FROM pf_mdt_roster WHERE citizenid = ? LIMIT 1', { cid }, function(rrows)
            local beforeRoster = rrows and rrows[1] or nil

            exports.oxmysql:execute('SELECT * FROM pf_mdt_officer_mgmt_profiles WHERE citizenid = ? LIMIT 1', { cid }, function(prows)
                local beforeProf = prows and prows[1] or {}
                if (tonumber(beforeProf.terminated) or 0) == 1 then
                    cb({ success = false, error = 'already_terminated' })
                    return
                end

                -- 1) Vacate their roster slot (keep the line/callsign), but remove the assignment.
                exports.oxmysql:execute(
                    'UPDATE pf_mdt_roster SET officer_name = "", citizenid = NULL, updated_at = NOW() WHERE citizenid = ?',
                    { cid }
                )

                -- 2) Mark terminated so they never show again
                exports.oxmysql:execute(
                    'UPDATE pf_mdt_officer_mgmt_profiles SET `terminated` = 1, status = "TERMINATED", terminated_at = NOW(), terminated_by = ?, terminated_reason = ?, probation_until = NULL, is_fto = 0, updated_at = NOW() WHERE citizenid = ?',
                    { actor, reason ~= '' and reason or nil, cid }
                )

                -- 3) Force DB job to unemployed grade 0
                local unemployed = buildUnemployedJobJson()
                if isESXFramework() then
                    exports.oxmysql:execute('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { 'unemployed', 0, cid })
                else
                    exports.oxmysql:execute('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(unemployed), cid })
                end

                -- 4) If online, immediately switch their job server-side
                local target = getOnlinePlayerByCitizenId(cid)
                if target and target.Functions and target.Functions.SetJob then
                    target.Functions.SetJob('unemployed', 0)
                end

                audit(info, cid, 'fire_officer', { job = beforeJob, roster = beforeRoster, profile = beforeProf }, { job = unemployed, terminated = true, terminated_by = actor, reason = reason })
                cb({ success = true })
            end)
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:officers:updateEmployment', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = clip(payload and payload.citizenid, 50)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end
    if not staffTarget(cid) then cb({ success = false, error = 'not_staff' }); return end

    -- If they were previously fired, a (command) rehire via employment save should reinstate them.
    ensureProfileRow(cid)
    exports.oxmysql:execute('SELECT `terminated`, status FROM pf_mdt_officer_mgmt_profiles WHERE citizenid = ? LIMIT 1', { cid }, function(trows)
        local tr = trows and trows[1] or {}
        if (tonumber(tr.terminated) or 0) == 1 then
            exports.oxmysql:execute(
                'UPDATE pf_mdt_officer_mgmt_profiles SET `terminated` = 0, status = "ACTIVE", terminated_at = NULL, terminated_by = NULL, terminated_reason = NULL, updated_at = NOW() WHERE citizenid = ?',
                { cid }
            )
        elseif tostring(tr.status or ''):upper() == 'TERMINATED' then
            exports.oxmysql:execute(
                'UPDATE pf_mdt_officer_mgmt_profiles SET status = "ACTIVE", updated_at = NOW() WHERE citizenid = ?',
                { cid }
            )
        end
    end)

    local callsign = clip(payload and payload.callsign, 32)
    local rank = clip(payload and payload.rank, 64)
    local unitType = clip(payload and payload.unit_type, 64)
    local training = clip(payload and payload.training_status, 64)

    exports.oxmysql:execute('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local row = rows and rows[1] or nil
        local ci = row and decodeMaybeJson(row.charinfo) or {}
        local name = getFullNameFromCharinfo(ci)
        if name == '' then name = cid end

        local before = { citizenid = cid }

        exports.oxmysql:execute('SELECT callsign, rank, unit_type, training_status FROM pf_mdt_roster WHERE citizenid = ? LIMIT 1', { cid }, function(rrows)
            local rr = rrows and rrows[1] or {}
            before.roster = rr

            local ok, err = upsertRosterForOfficer(cid, name, callsign, rank, unitType, training)
            if not ok then cb({ success = false, error = err or 'failed' }); return end

            audit(info, cid, 'employment_update', before, { callsign = callsign, rank = rank, unit_type = unitType, training_status = training })
            cb({ success = true })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:officers:setFlags', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = clip(payload and payload.citizenid, 50)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end
    if not staffTarget(cid) then cb({ success = false, error = 'not_staff' }); return end

    ensureProfileRow(cid)

    local probationUntil = payload and payload.probation_until or nil
    -- Ensure probation_until is nil if empty string
    if probationUntil == '' then probationUntil = nil end
    
    -- Validate probation datetime format if provided
    if probationUntil and probationUntil ~= '' then
        -- Check format: YYYY-MM-DD HH:mm:ss
        if type(probationUntil) ~= 'string' or not probationUntil:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$') then
            cb({ success = false, error = 'invalid_datetime_format' })
            return
        end
        -- Verify it can be parsed as a valid timestamp
        local expiryTime = parseMysqlDateStringToTimestamp(probationUntil)
        if not expiryTime or expiryTime == 0 then
            cb({ success = false, error = 'invalid_datetime' })
            return
        end
    end
    
    local isFto = payload and payload.is_fto
    local isSupervisorFlag = payload and payload.is_supervisor
    local status = trim(payload and payload.status)
    
    -- Validate status if provided
    local validStatuses = { ACTIVE = true, DESK_DUTY = true, SUSPENDED = true, TERMINATED = true }
    if status ~= '' and not validStatuses[status:upper()] then
        cb({ success = false, error = 'invalid_status' })
        return
    end

    exports.oxmysql:execute('SELECT probation_until, is_fto, status FROM pf_mdt_officer_mgmt_profiles WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local before = rows and rows[1] or {}

        local setParts = {}
        local params = {}

        if probationUntil ~= nil then
            table.insert(setParts, 'probation_until = ?')
            table.insert(params, probationUntil)
        end
        if isFto ~= nil then
            table.insert(setParts, 'is_fto = ?')
            table.insert(params, (isFto and 1) or 0)
        end
        if isSupervisorFlag ~= nil then
            table.insert(setParts, 'is_supervisor = ?')
            table.insert(params, (isSupervisorFlag and 1) or 0)
        end
        if status ~= '' then
            table.insert(setParts, 'status = ?')
            table.insert(params, status:upper())
        end

        if #setParts == 0 then cb({ success = true }); return end

        table.insert(params, cid)
        local query = 'UPDATE pf_mdt_officer_mgmt_profiles SET ' .. table.concat(setParts, ', ') .. ', updated_at = NOW() WHERE citizenid = ?'
        
        exports.oxmysql:execute(query, params, function(affectedRows)
            audit(info, cid, 'profile_update', before, { probation_until = probationUntil, is_fto = isFto, status = status })
            cb({ success = true })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:officers:addDiscipline', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = clip(payload and payload.citizenid, 50)
    local dtype = clip(payload and payload.type, 32)
    local reason = clip(payload and payload.reason, 1000)
    if cid == '' or dtype == '' or reason == '' then cb({ success = false, error = 'missing_fields' }); return end
    if not staffTarget(cid) then cb({ success = false, error = 'not_staff' }); return end

    local pd = info.player.PlayerData
    local issuer = getFullNameFromCharinfo(pd.charinfo)
    if issuer == '' then issuer = pd.citizenid or 'Command' end

    exports.oxmysql:insert(
        'INSERT INTO pf_mdt_officer_discipline (citizenid, type, reason, issued_by, issued_at, active) VALUES (?, ?, ?, ?, NOW(), 1)',
        { cid, dtype:upper(), reason, issuer },
        function(id)
            audit(info, cid, 'discipline_add', nil, { id = id, type = dtype:upper(), reason = reason })
            cb({ success = true, id = id })
        end
    )
end)

QBCore.Functions.CreateCallback('pf_mdt:officers:updateDiscipline', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local id = tonumber(payload and payload.id)
    local action = trim(payload and payload.action)
    if not id or action == '' then cb({ success = false, error = 'invalid' }); return end

    local pd = info.player.PlayerData
    local actor = getFullNameFromCharinfo(pd.charinfo)
    if actor == '' then actor = pd.citizenid or 'Command' end

    exports.oxmysql:execute('SELECT citizenid, type, reason, active FROM pf_mdt_officer_discipline WHERE id = ? LIMIT 1', { id }, function(rows)
        local row = rows and rows[1] or nil
        if not row then cb({ success = false, error = 'not_found' }); return end

        if action == 'resolve' then
            exports.oxmysql:execute('UPDATE pf_mdt_officer_discipline SET active = 0, resolved_by = ?, resolved_at = NOW() WHERE id = ?', { actor, id }, function()
                audit(info, row.citizenid, 'discipline_resolve', row, { id = id, active = 0 })
                cb({ success = true })
            end)
        elseif action == 'remove' then
            exports.oxmysql:execute('DELETE FROM pf_mdt_officer_discipline WHERE id = ?', { id }, function()
                audit(info, row.citizenid, 'discipline_remove', row, nil)
                cb({ success = true })
            end)
        else
            cb({ success = false, error = 'invalid_action' })
        end
    end)
end)


-- Bonuses removed

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        ensureTables()
    end)
end)
