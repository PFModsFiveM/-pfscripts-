local QBCore = PFMdt.GetCore()

-- Forward declare for helpers that need it (defined later).
local getOnlinePlayerByCitizenId


local ROSTER_TABLE = 'pf_emsmdt_roster'
local STAFF_PROFILE_TABLE = 'pf_emsmdt_staff_mgmt_profiles'
local STAFF_DISCIPLINE_TABLE = 'pf_emsmdt_staff_discipline'
local STAFF_AUDIT_TABLE = 'pf_emsmdt_staff_audit'

local LEGACY_ROSTER_TABLE = 'pf_mdt_roster'
local LEGACY_PROFILE_TABLE = 'pf_mdt_officer_mgmt_profiles'
local LEGACY_DISCIPLINE_TABLE = 'pf_mdt_officer_discipline'
local LEGACY_AUDIT_TABLE = 'pf_mdt_officer_audit'

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

-- The chief ranks are the boss's to give or take, here as on the roster page (server/roster.lua).
local CHIEF_RANKS = { ['chief'] = true, ['ems chief'] = true, ['fire chief'] = true }
local function chiefRank(r) return CHIEF_RANKS[tostring(r or ''):gsub('^%s*(.-)%s*$', '%1'):lower()] == true end

-- Values from another resource are funcrefs (tables with __call), not plain functions.
local function callable(v)
    if type(v) == 'function' then return true end
    local mt = type(v) == 'table' and getmetatable(v)
    return type(mt) == 'table' and mt.__call ~= nil
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

-- The department boss: job.isboss, the top grade of the job, or the owner flag.
local function isBossInfo(info)
    local job = info and info.player and info.player.PlayerData and info.player.PlayerData.job or {}
    if job.isboss == true or info.isOwner == true then return true end
    local def = QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[info.jobName]
    local top = nil
    for g in pairs(type(def) == 'table' and type(def.grades) == 'table' and def.grades or {}) do
        local n = tonumber(g)
        if n and (not top or n > top) then top = n end
    end
    return top ~= nil and (info.grade or 0) >= top
end

-- Staff management needs Config.Permissions.manageOfficers (grade 4 by default) or the owner flag;
-- a change (fire, employment, flags, discipline) also needs the actor on duty.
local function canManage(info)
    if not (info and info.allowed) then return false end
    local perms = Config and Config.Permissions and Config.Permissions.manageOfficers
    local need = type(perms) == 'number' and perms or (type(perms) == 'table' and tonumber(perms[info.jobName])) or 4
    return (info.grade or 0) >= need or info.isOwner == true
end

local function canChange(info)
    local job = info and info.player and info.player.PlayerData and info.player.PlayerData.job
    return canManage(info) and type(job) == 'table' and job.onduty == true
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

-- The staff tables (and the columns older installs lacked) come from server/schema.lua (v2).
-- Opt-in copy of the old pf_mdt_* staff tables into the empty EMS ones, run once the schema is ready.
-- Off unless Config.MigrateLegacyPoliceTables: on this server those tables belong to pf-policemdt, so
-- the first start copied police staff, discipline and audit records into the EMS MDT.
function PFEmsCopyLegacyStaff()
    if Config.MigrateLegacyPoliceTables ~= true or not hasDb() then return end

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
if PFEmsSchema then PFEmsSchema.OnReady(PFEmsCopyLegacyStaff) end

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

-- How a citizen relates to the actor's department, from their job now (live when online, else the
-- players row):
--   'member'  in the actor's job now (grade returned)
--   'other'   in another EMS MDT job now: never managed from this one
--   'former'  in no EMS MDT job now, but still on the roster or the staff list (not terminated)
--   nil       not staff
-- Command could fire, discipline or flag any citizen before: a roster line with someone's citizenid
-- made them "staff", so a police chief or a mechanic could be set unemployed.
local function staffTarget(cid, actorJob)
    local p = promise.new()
    local function classify(job)
        local jobName = type(job) == 'table' and job.name or nil
        local grade = type(job) == 'table' and (type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade)) or nil
        if isAllowedJob(jobName or '') then
            p:resolve({ jobName == actorJob and 'member' or 'other', grade or 0 })
            return
        end
        exports.oxmysql:execute(('SELECT (SELECT COUNT(*) FROM `%s` WHERE citizenid = ?) AS r, (SELECT COUNT(*) FROM `%s` WHERE citizenid = ? AND `terminated` = 0) AS s'):format(ROSTER_TABLE, STAFF_PROFILE_TABLE),
            { cid, cid }, function(srows)
                local r = srows and srows[1] or {}
                p:resolve({ ((tonumber(r.r) or 0) > 0 or (tonumber(r.s) or 0) > 0) and 'former' or false, nil })
            end)
    end
    local live = getOnlinePlayerByCitizenId(cid)
    if live and live.PlayerData and type(live.PlayerData.job) == 'table' then
        classify(live.PlayerData.job)
    else
        exports.oxmysql:execute('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { cid }, function(rows)
            classify(rows and rows[1] and decodeMaybeJson(rows[1].job) or nil)
        end)
    end
    local res = Citizen.Await(p)
    return res[1] or nil, res[2]
end

-- The actor may act on this citizen: same department and a lower grade (the owner flag skips the
-- grade), or a former member (records only). Returns relation, grade or nil, error.
local function manageable(info, cid, allowSelf)
    local relation, grade = staffTarget(cid, info.jobName)
    if not relation then return nil, nil, 'not_staff' end
    if relation == 'other' then return nil, nil, 'other_department' end
    local self = tostring(cid) == tostring(info.player.PlayerData.citizenid)
    if relation == 'member' and not info.isOwner and not (allowSelf and self) and (grade or 0) >= (info.grade or 0) then
        return nil, nil, 'rank_too_high'
    end
    return relation, grade, nil
end

local function clip(v, n) return trim(v):sub(1, n) end

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

    local cid = clip((data and data.citizenid) or '', 50)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end
    -- only staff have a profile (viewing used to create a profile row, which made anyone "staff")
    if not staffTarget(cid) then replyOnce({ success = false, error = 'not_staff' }); return end

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
    if not canChange(info) then cb({ success = false, error = canManage(info) and 'off_duty' or 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end


    local cid = clip(payload and payload.citizenid, 50)
    local reason = clip(payload and payload.reason, 500)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end
    if cid == tostring(info.player.PlayerData.citizenid) then cb({ success = false, error = 'cannot_fire_self' }); return end
    local relation, _, merr = manageable(info, cid, false)
    if not relation then cb({ success = false, error = merr }); return end
    -- only a member of the actor's department loses their job; a former member only leaves the
    -- roster and the staff list (their job now belongs to someone else)
    local changeJob = relation == 'member'

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

                -- 3) Force DB job to unemployed grade 0 (members of this department only, and only
                --    while the row still holds that job)
                local unemployed = changeJob and buildUnemployedJobJson() or nil
                if changeJob then
                    if isESXFramework() then
                        exports.oxmysql:execute('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ? AND job = ?', { 'unemployed', 0, cid, info.jobName })
                    else
                        exports.oxmysql:execute("UPDATE players SET job = ? WHERE citizenid = ? AND JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?", { json.encode(unemployed), cid, info.jobName })
                    end

                    -- 4) If online, immediately switch their job server-side (still in this job)
                    local target = getOnlinePlayerByCitizenId(cid)
                    local tjob = target and target.PlayerData and target.PlayerData.job
                    if tjob and tjob.name == info.jobName and target.Functions and callable(target.Functions.SetJob) then
                        target.Functions.SetJob('unemployed', 0)
                    end
                end

                audit(info, cid, 'fire_officer', { job = beforeJob, roster = beforeRoster, profile = beforeProf }, { job = unemployed, terminated = true, terminated_by = actor, reason = reason, jobChanged = changeJob })
                cb({ success = true, jobChanged = changeJob })
            end)
        end)
    end)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:officers:updateEmployment', function(source, cb, payload)
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canChange(info) then cb({ success = false, error = canManage(info) and 'off_duty' or 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = clip(payload and payload.citizenid, 50)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end
    -- the roster line goes to a member of this department only
    local relation, _, merr = manageable(info, cid, true)
    if not relation then cb({ success = false, error = merr }); return end
    if relation ~= 'member' then cb({ success = false, error = 'not_an_officer' }); return end

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

        exports.oxmysql:execute(('SELECT callsign, rank, unit_type, training_status FROM %s WHERE citizenid = ? LIMIT 1'):format(ROSTER_TABLE), { cid }, function(rrows)
            local rr = rrows and rrows[1] or {}
            before.roster = rr
            if (chiefRank(rank) or chiefRank(rr.rank)) and not isBossInfo(info) then
                cb({ success = false, error = 'protected_chief' }); return
            end

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
    if not canChange(info) then cb({ success = false, error = canManage(info) and 'off_duty' or 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = clip(payload and payload.citizenid, 50)
    if cid == '' then cb({ success = false, error = 'invalid_id' }); return end
    local relation, _, merr = manageable(info, cid, false)
    if not relation then cb({ success = false, error = merr }); return end

    ensureProfileRow(cid)

    local probationUntil = payload and payload.probation_until or nil
    if probationUntil ~= nil and probationUntil ~= '' and not tostring(probationUntil):match('^%d%d%d%d%-%d%d%-%d%d[%d :T%-]*$') then
        cb({ success = false, error = 'invalid_date' }); return
    end
    local isFto = payload and payload.is_fto
    local status = clip(payload and payload.status, 32)

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
    if not canChange(info) then cb({ success = false, error = canManage(info) and 'off_duty' or 'no_permission' }); return end
    if not hasDb() then cb({ success = false, error = 'no_db' }); return end

    local cid = clip(payload and payload.citizenid, 50)
    local dtype = clip(payload and payload.type, 32)
    local reason = clip(payload and payload.reason, 1000)
    if cid == '' or dtype == '' or reason == '' then cb({ success = false, error = 'missing_fields' }); return end
    local relation, _, merr = manageable(info, cid, false)
    if not relation then cb({ success = false, error = merr }); return end

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
    if not canChange(info) then cb({ success = false, error = canManage(info) and 'off_duty' or 'no_permission' }); return end
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
        local relation, _, merr = manageable(info, row.citizenid, false)
        if not relation then cb({ success = false, error = merr }); return end

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


