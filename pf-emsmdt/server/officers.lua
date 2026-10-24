local QBCore = PFMdt.GetCore()

-- Forward declare for helpers that need it (defined later).
local getOnlinePlayerByCitizenId

-- Cache for optional qb-management DB fallback.
local mgmtFundsTableExists = nil

local ROSTER_TABLE = 'pf_emsmdt_roster'
local STAFF_PROFILE_TABLE = 'pf_emsmdt_staff_mgmt_profiles'
local STAFF_DISCIPLINE_TABLE = 'pf_emsmdt_staff_discipline'
local STAFF_AUDIT_TABLE = 'pf_emsmdt_staff_audit'

local LEGACY_ROSTER_TABLE = 'pf_mdt_roster'
local LEGACY_PROFILE_TABLE = 'pf_mdt_officer_mgmt_profiles'
local LEGACY_DISCIPLINE_TABLE = 'pf_mdt_officer_discipline'
local LEGACY_AUDIT_TABLE = 'pf_mdt_officer_audit'

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
        print(('[pf-emsmdt] StaffMgmt ensureTables failed: %s'):format(tostring(err)))
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
    if not Config or not Config.AllowedJobs then return 'ambulance' end
    if Config.AllowedJobs.ambulance == true then return 'ambulance' end
    for k, v in pairs(Config.AllowedJobs) do
        if v == true and tostring(k) ~= '' then return tostring(k) end
    end
    return 'ambulance'
end

local function getSocietyJobName(info)
    if info and isAllowedJob(info.jobName or '') then return tostring(info.jobName) end
    return firstAllowedJobName()
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

local function creditBankByCitizenId(citizenid, amount, reason)
    if not hasDb() then return false, 'no_db' end
    citizenid = trim(citizenid)
    amount = tonumber(amount) or 0
    if citizenid == '' then return false, 'invalid_id' end
    if amount == 0 then return true end

    local target = getOnlinePlayerByCitizenId(citizenid)
    if target and target.Functions and target.Functions.AddMoney then
        target.Functions.AddMoney('bank', amount, reason or 'pf-mdt-bonus')
        return true
    end

    if isESXFramework() then
        -- ESX offline: update users.accounts JSON (best-effort across common ESX formats)
        local p = promise.new()
        exports.oxmysql:execute('SELECT accounts FROM users WHERE identifier = ? LIMIT 1', { citizenid }, function(rows)
            local accountsRaw = rows and rows[1] and rows[1].accounts or nil
            local accounts = {}
            if type(accountsRaw) == 'string' and accountsRaw ~= '' then
                local ok, parsed = pcall(json.decode, accountsRaw)
                if ok and parsed ~= nil then
                    accounts = parsed
                end
            elseif type(accountsRaw) == 'table' then
                accounts = accountsRaw
            end

            if type(accounts) == 'table' and #accounts > 0 then
                -- Newer ESX: accounts is an array of {name=..., money=...}
                local found = false
                for _, acc in ipairs(accounts) do
                    if acc and tostring(acc.name or '') == 'bank' then
                        acc.money = (tonumber(acc.money) or 0) + amount
                        found = true
                        break
                    end
                end
                if not found then
                    accounts[#accounts + 1] = { name = 'bank', money = amount }
                end
            elseif type(accounts) == 'table' then
                -- Some forks: accounts is an object map
                accounts.bank = (tonumber(accounts.bank) or 0) + amount
            else
                accounts = { { name = 'bank', money = amount } }
            end

            exports.oxmysql:execute('UPDATE users SET accounts = ? WHERE identifier = ?', { json.encode(accounts), citizenid }, function()
                p:resolve(true)
            end)
        end)
        Citizen.Await(p)
        return true
    end

    -- QBCore offline: update players.money JSON
    local p = promise.new()
    exports.oxmysql:execute('SELECT money FROM players WHERE citizenid = ? LIMIT 1', { citizenid }, function(rows)
        local money = rows and rows[1] and decodeMaybeJson(rows[1].money) or {}
        if type(money) ~= 'table' then money = {} end
        money.bank = (tonumber(money.bank) or 0) + amount
        exports.oxmysql:execute('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(money), citizenid }, function()
            p:resolve(true)
        end)
    end)
    Citizen.Await(p)
    return true
end

local function tryRemoveSocietyMoney(jobName, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end
    jobName = trim(jobName)
    if jobName == '' then return false, 'invalid_society' end

    -- Prefer qb-management export if available.
    if GetResourceState('pfm-management') == 'started' then
        local ok, res = pcall(function()
            return exports['pfm-management']:RemoveMoney(jobName, amount)
        end)
        if ok then
            -- qb-management RemoveMoney usually returns bool; treat nil as success (some forks).
            if res == nil or res == true then return true end
            return false, 'insufficient_society_funds'
        end
    end

    -- Fallback: attempt direct DB update (qb-management default table).
    if not hasDb() then return false, 'no_db' end

    if mgmtFundsTableExists == nil then
        local pExists = promise.new()
        exports.oxmysql:execute(
            'SELECT COUNT(*) AS c FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = "management_funds"',
            {},
            function(rows)
                mgmtFundsTableExists = (rows and rows[1] and tonumber(rows[1].c) or 0) > 0
                pExists:resolve(true)
            end
        )
        Citizen.Await(pExists)
    end
    if mgmtFundsTableExists ~= true then
        return false, 'society_unavailable'
    end

    local p = promise.new()
    exports.oxmysql:execute(
        'UPDATE management_funds SET amount = amount - ? WHERE job_name = ? AND amount >= ?',
        { amount, jobName, amount },
        function(result)
            local affected = 0
            if type(result) == 'table' then
                affected = tonumber(result.affectedRows or result.changedRows or 0) or 0
            elseif type(result) == 'number' then
                affected = result
            end
            p:resolve(affected > 0)
        end
    )
    local ok = Citizen.Await(p)
    if ok then return true end
    return false, 'insufficient_society_funds'
end

local function ensureTables()
    if not hasDb() then return end

    local function tableExists(tableName)
        local p = promise.new()
        exports.oxmysql:scalar(
            'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
            { tostring(tableName) },
            function(count)
                p:resolve((tonumber(count) or 0) > 0)
            end
        )
        return Citizen.Await(p)
    end

    local function tableCount(tableName)
        local p = promise.new()
        exports.oxmysql:scalar(('SELECT COUNT(*) FROM `%s`'):format(tostring(tableName)), {}, function(count)
            p:resolve(tonumber(count) or 0)
        end)
        return Citizen.Await(p)
    end

    exports.oxmysql:execute([[
                CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_mgmt_profiles` (
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
    ensureColumn(STAFF_PROFILE_TABLE, 'status', "`status` VARCHAR(32) NOT NULL DEFAULT 'ACTIVE'")
    ensureColumn(STAFF_PROFILE_TABLE, 'terminated', '`terminated` TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn(STAFF_PROFILE_TABLE, 'terminated_at', '`terminated_at` DATETIME NULL')
    ensureColumn(STAFF_PROFILE_TABLE, 'terminated_by', '`terminated_by` VARCHAR(128) NULL')
    ensureColumn(STAFF_PROFILE_TABLE, 'terminated_reason', '`terminated_reason` VARCHAR(255) NULL')

    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_discipline` (
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
        CREATE TABLE IF NOT EXISTS `pf_emsmdt_staff_audit` (
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

    -- Best-effort migrations from legacy PD table names.
    if tableExists(LEGACY_PROFILE_TABLE) and tableCount(STAFF_PROFILE_TABLE) == 0 then
        exports.oxmysql:execute(
            ('INSERT IGNORE INTO `%s` (citizenid, hire_date, probation_until, is_fto, status, terminated, terminated_at, terminated_by, terminated_reason, restrictions_json, flags_json, created_at, updated_at) SELECT citizenid, hire_date, probation_until, is_fto, status, terminated, terminated_at, terminated_by, terminated_reason, restrictions_json, flags_json, created_at, updated_at FROM `%s`'):format(STAFF_PROFILE_TABLE, LEGACY_PROFILE_TABLE),
            {}
        )
    end

    if tableExists(LEGACY_DISCIPLINE_TABLE) and tableCount(STAFF_DISCIPLINE_TABLE) == 0 then
        exports.oxmysql:execute(
            ('INSERT INTO `%s` (citizenid, type, reason, issued_by, issued_at, active, resolved_by, resolved_at, expires_at) SELECT citizenid, type, reason, issued_by, issued_at, active, resolved_by, resolved_at, expires_at FROM `%s`'):format(STAFF_DISCIPLINE_TABLE, LEGACY_DISCIPLINE_TABLE),
            {}
        )
    end

    if tableExists(LEGACY_AUDIT_TABLE) and tableCount(STAFF_AUDIT_TABLE) == 0 then
        exports.oxmysql:execute(
            ('INSERT INTO `%s` (actor_citizenid, actor_name, target_citizenid, action, before_json, after_json, created_at) SELECT actor_citizenid, actor_name, target_citizenid, action, before_json, after_json, created_at FROM `%s`'):format(STAFF_AUDIT_TABLE, LEGACY_AUDIT_TABLE),
            {}
        )
    end
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

    exports.oxmysql:insert(
        ('INSERT INTO `%s` (actor_citizenid, actor_name, target_citizenid, action, before_json, after_json, created_at) VALUES (?, ?, ?, ?, ?, ?, NOW())'):format(STAFF_AUDIT_TABLE),
        { actorCid, actorName, targetCitizenId, action, beforeJson, afterJson }
    )
end

local function ensureProfileRow(citizenid)
    if not hasDb() then return end
    exports.oxmysql:insert(
        ('INSERT IGNORE INTO `%s` (citizenid, created_at, updated_at) VALUES (?, NOW(), NOW())'):format(STAFF_PROFILE_TABLE),
        { citizenid }
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
        ('SELECT id, citizenid FROM %s WHERE callsign = ? LIMIT 1'):format(ROSTER_TABLE),
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
    exports.oxmysql:execute(('SELECT id, citizenid FROM %s WHERE callsign = ? LIMIT 1'):format(ROSTER_TABLE), { callsign }, function(rows)
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
    exports.oxmysql:execute(('SELECT id FROM %s WHERE citizenid = ? LIMIT 1'):format(ROSTER_TABLE), { citizenid }, function(rows)
        local row = rows and rows[1] or nil
        if row and row.id then
            exports.oxmysql:execute(
                ('UPDATE %s SET callsign = ?, rank = ?, officer_name = ?, unit_type = ?, training_status = ?, updated_at = NOW() WHERE id = ?'):format(ROSTER_TABLE),
                { callsign, rank, name, unitType, trainingStatus, row.id },
                function()
                    p2:resolve({ ok = true })
                end
            )
        else
            exports.oxmysql:insert(
                ('INSERT INTO %s (callsign, rank, officer_name, citizenid, unit_type, training_status, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, NULL, NOW(), NOW())'):format(ROSTER_TABLE),
                { callsign, rank, name, citizenid, unitType, trainingStatus },
                function()
                    p2:resolve({ ok = true })
                end
            )
        end
    end)

    local res = Citizen.Await(p2)
    return res.ok == true
end

local function canViewDiscipline(info, targetCitizenId)
    if not info or not info.player then return false end
    if canManage(info) then return true end
    return tostring(info.player.PlayerData.citizenid or '') == tostring(targetCitizenId or '')
end

-- ============================================================
-- Callbacks
-- ============================================================

QBCore.Functions.CreateCallback('pf_emsmdt:officers:getMeta', function(source, cb)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end

    -- Reuse roster meta lists (ranks/unit/training) by hardcoding server-side? Keep it simple:
    -- fetch from roster meta callback is not possible server-side, so return minimal.
    cb({
        success = true,
        canManage = canManage(info)
    })
end)

QBCore.Functions.CreateCallback('pf_emsmdt:officers:list', function(source, cb)
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

    -- Staff membership persistence:
    -- - If they ever held an allowed EMS job (or are in roster), they keep showing even if they swap jobs.
    -- - If they are terminated/fired, they must never show.
    exports.oxmysql:execute(('SELECT citizenid FROM %s WHERE `terminated` = 0'):format(STAFF_PROFILE_TABLE), {}, function(mrows)
        local saved = {}
        for _, r in ipairs(mrows or {}) do
            local cid = tostring(r.citizenid or '')
            if cid ~= '' then saved[cid] = true end
        end

        exports.oxmysql:execute(('SELECT citizenid FROM %s WHERE citizenid IS NOT NULL AND citizenid <> ""'):format(ROSTER_TABLE), {}, function(rrows)
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

                        -- If they currently have an allowed EMS job, persist membership.
                        if allowedByDb then
                            saved[cid] = true
                            ensureProfileRow(cid)
                        end

                        local st = online[cid]

                        -- Treat as staff if:
                        -- - currently allowed job, OR
                        -- - online multi-job indicates allowed-job membership, OR
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

                local pending = 2
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
                    ('SELECT citizenid, callsign, rank, unit_type, training_status FROM %s WHERE citizenid IN ('):format(ROSTER_TABLE) .. inClause .. ')',
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
                    ('SELECT * FROM %s WHERE citizenid IN ('):format(STAFF_PROFILE_TABLE) .. inClause .. ')',
                    citizenIds,
                    function(prows)
                        for _, pr in ipairs(prows or {}) do
                            local cid = tostring(pr.citizenid or '')
                            local item = byCid[cid]
                            if item then
                                item.probation_until = pr.probation_until
                                item.is_fto = (tonumber(pr.is_fto) or 0) == 1
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
                                        ('UPDATE %s SET `terminated` = 0, status = "ACTIVE", terminated_at = NULL, terminated_by = NULL, terminated_reason = NULL, updated_at = NOW() WHERE citizenid = ?'):format(STAFF_PROFILE_TABLE),
                                        { cid }
                                    )
                                end
                            end
                        end
                        done()
                    end
                )
            end)
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:officers:get', function(source, cb, data)
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

        exports.oxmysql:execute(('SELECT callsign, rank, unit_type, training_status, notes FROM %s WHERE citizenid = ? LIMIT 1'):format(ROSTER_TABLE), { cid }, function(rrows)
            local roster = rrows and rrows[1] or {}

            exports.oxmysql:execute(('SELECT * FROM %s WHERE citizenid = ? LIMIT 1'):format(STAFF_PROFILE_TABLE), { cid }, function(prows)
                local prof = prows and prows[1] or {}

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
                    exports.oxmysql:execute(('SELECT id, type, reason, issued_by, issued_at, active, resolved_by, resolved_at, expires_at FROM %s WHERE citizenid = ? ORDER BY issued_at DESC LIMIT 50'):format(STAFF_DISCIPLINE_TABLE), { cid }, function(drows)
                        base.discipline = drows or {}
                        done()
                    end)
                else
                    base.discipline = nil
                    done()
                end

                -- Audit history
                exports.oxmysql:execute(('SELECT id, actor_name, action, before_json, after_json, created_at FROM %s WHERE target_citizenid = ? ORDER BY created_at DESC LIMIT 50'):format(STAFF_AUDIT_TABLE), { cid }, function(arows)
                    base.history = arows or {}
                    done()
                end)

                -- Activity overview: EMS MDT keeps this minimal.
                base.activity = { incidents = 0, reports = 0 }
                done()
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

QBCore.Functions.CreateCallback('pf_emsmdt:officers:fire', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    ensureTablesOnce()

    local cid = trim(payload and payload.citizenid)
    local reason = trim(payload and payload.reason)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end

    ensureProfileRow(cid)

    local pd = info.player.PlayerData
    local actor = getFullNameFromCharinfo(pd.charinfo)
    if actor == '' then actor = 'Command' end

    exports.oxmysql:execute('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local beforeJob = rows and rows[1] and decodeMaybeJson(rows[1].job) or nil

        exports.oxmysql:execute(('SELECT callsign, rank, unit_type, training_status FROM %s WHERE citizenid = ? LIMIT 1'):format(ROSTER_TABLE), { cid }, function(rrows)
            local beforeRoster = rrows and rrows[1] or nil

            exports.oxmysql:execute(('SELECT * FROM %s WHERE citizenid = ? LIMIT 1'):format(STAFF_PROFILE_TABLE), { cid }, function(prows)
                local beforeProf = prows and prows[1] or {}
                if (tonumber(beforeProf.terminated) or 0) == 1 then
                    cb({ success = false, error = 'already_terminated' })
                    return
                end

                -- 1) Vacate their roster slot (keep the line/callsign), but remove the assignment.
                exports.oxmysql:execute(
                    ('UPDATE %s SET officer_name = "", citizenid = NULL, updated_at = NOW() WHERE citizenid = ?'):format(ROSTER_TABLE),
                    { cid }
                )

                -- 2) Mark terminated so they never show again
                exports.oxmysql:execute(
                    ('UPDATE %s SET `terminated` = 1, status = "TERMINATED", terminated_at = NOW(), terminated_by = ?, terminated_reason = ?, probation_until = NULL, is_fto = 0, updated_at = NOW() WHERE citizenid = ?'):format(STAFF_PROFILE_TABLE),
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

QBCore.Functions.CreateCallback('pf_emsmdt:officers:updateEmployment', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = trim(payload and payload.citizenid)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end

    -- If they were previously fired, a (command) rehire via employment save should reinstate them.
    ensureProfileRow(cid)
    exports.oxmysql:execute(('SELECT `terminated`, status FROM %s WHERE citizenid = ? LIMIT 1'):format(STAFF_PROFILE_TABLE), { cid }, function(trows)
        local tr = trows and trows[1] or {}
        if (tonumber(tr.terminated) or 0) == 1 then
            exports.oxmysql:execute(
                ('UPDATE %s SET `terminated` = 0, status = "ACTIVE", terminated_at = NULL, terminated_by = NULL, terminated_reason = NULL, updated_at = NOW() WHERE citizenid = ?'):format(STAFF_PROFILE_TABLE),
                { cid }
            )
        elseif tostring(tr.status or ''):upper() == 'TERMINATED' then
            exports.oxmysql:execute(
                ('UPDATE %s SET status = "ACTIVE", updated_at = NOW() WHERE citizenid = ?'):format(STAFF_PROFILE_TABLE),
                { cid }
            )
        end
    end)

    local callsign = trim(payload and payload.callsign)
    local rank = trim(payload and payload.rank)
    local unitType = trim(payload and payload.unit_type)
    local training = trim(payload and payload.training_status)

    exports.oxmysql:execute('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
        local row = rows and rows[1] or nil
        local ci = row and decodeMaybeJson(row.charinfo) or {}
        local name = getFullNameFromCharinfo(ci)
        if name == '' then name = cid end

        local before = { citizenid = cid }

        exports.oxmysql:execute(('SELECT callsign, rank, unit_type, training_status FROM %s WHERE citizenid = ? LIMIT 1'):format(ROSTER_TABLE), { cid }, function(rrows)
            local rr = rrows and rrows[1] or {}
            before.roster = rr

            local ok, err = upsertRosterForOfficer(cid, name, callsign, rank, unitType, training)
            if not ok then cb({ success = false, error = err or 'failed' }); return end

            audit(info, cid, 'employment_update', before, { callsign = callsign, rank = rank, unit_type = unitType, training_status = training })
            cb({ success = true })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:officers:setFlags', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = trim(payload and payload.citizenid)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end

    ensureProfileRow(cid)

    local probationUntil = payload and payload.probation_until or nil
    local isFto = payload and payload.is_fto
    local status = trim(payload and payload.status)

    exports.oxmysql:execute(('SELECT probation_until, is_fto, status FROM %s WHERE citizenid = ? LIMIT 1'):format(STAFF_PROFILE_TABLE), { cid }, function(rows)
        local before = rows and rows[1] or {}

        local setParts = {}
        local params = {}

        if probationUntil ~= nil then
            table.insert(setParts, 'probation_until = ?')
            table.insert(params, probationUntil == '' and nil or probationUntil)
        end
        if isFto ~= nil then
            table.insert(setParts, 'is_fto = ?')
            table.insert(params, (isFto and 1) or 0)
        end
        if status ~= '' then
            table.insert(setParts, 'status = ?')
            table.insert(params, status)
        end

        if #setParts == 0 then cb({ success = true }); return end

        table.insert(params, cid)
        exports.oxmysql:execute(('UPDATE %s SET '):format(STAFF_PROFILE_TABLE) .. table.concat(setParts, ', ') .. ', updated_at = NOW() WHERE citizenid = ?', params, function()
            audit(info, cid, 'profile_update', before, { probation_until = probationUntil, is_fto = isFto, status = status })
            cb({ success = true })
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:officers:addDiscipline', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canManage(info) then cb({ success = false, error = 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = trim(payload and payload.citizenid)
    local dtype = trim(payload and payload.type)
    local reason = trim(payload and payload.reason)
    if cid == '' or dtype == '' or reason == '' then cb({ success = false, error = 'missing_fields' }); return end

    local pd = info.player.PlayerData
    local issuer = getFullNameFromCharinfo(pd.charinfo)
    if issuer == '' then issuer = pd.citizenid or 'Command' end

    exports.oxmysql:insert(
        ('INSERT INTO %s (citizenid, type, reason, issued_by, issued_at, active) VALUES (?, ?, ?, ?, NOW(), 1)'):format(STAFF_DISCIPLINE_TABLE),
        { cid, dtype:upper(), reason, issuer },
        function(id)
            audit(info, cid, 'discipline_add', nil, { id = id, type = dtype:upper(), reason = reason })
            cb({ success = true, id = id })
        end
    )
end)

QBCore.Functions.CreateCallback('pf_emsmdt:officers:updateDiscipline', function(source, cb, payload)
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

    exports.oxmysql:execute(('SELECT citizenid, type, reason, active FROM %s WHERE id = ? LIMIT 1'):format(STAFF_DISCIPLINE_TABLE), { id }, function(rows)
        local row = rows and rows[1] or nil
        if not row then cb({ success = false, error = 'not_found' }); return end

        if action == 'resolve' then
            exports.oxmysql:execute(('UPDATE %s SET active = 0, resolved_by = ?, resolved_at = NOW() WHERE id = ?'):format(STAFF_DISCIPLINE_TABLE), { actor, id }, function()
                audit(info, row.citizenid, 'discipline_resolve', row, { id = id, active = 0 })
                cb({ success = true })
            end)
        elseif action == 'remove' then
            exports.oxmysql:execute(('DELETE FROM %s WHERE id = ?'):format(STAFF_DISCIPLINE_TABLE), { id }, function()
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
