local QBCore = PFMdt.GetCore()

local SOP_TABLE = 'pf_emsmdt_sops'
local LEGACY_SOP_TABLE = 'pf_mdt_sops'

local function isDebugEnabled()
    return Config and Config.Debug == true
end

local function dprint(...)
    if not isDebugEnabled() then return end
    print(...)
end

local function hasOxMySQL()
    return exports and exports.oxmysql ~= nil
end

local function trim(val)
    return (tostring(val or ''):gsub('^%s*(.-)%s*$', '%1'))
end

local function isAllowedJob(jobName)
    return jobName ~= '' and Config and Config.AllowedJobs and Config.AllowedJobs[jobName] == true
end

local function getIsOwnerFlag(player)
    local meta = player and player.PlayerData and player.PlayerData.metadata or {}
    if type(meta) == 'string' then
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
        isOwner = getIsOwnerFlag(Player)
    }
end

local function canEdit(info)
    if not info then return false end
    if info.isOwner then return true end
    local sg = Config and Config.SupervisorGrades and Config.SupervisorGrades[info.jobName]
    return sg and sg[tonumber(info.grade) or 0] == true
end

local function ensureTable(done)
    if not hasOxMySQL() then
        if done then done(false) end
        return
    end

    local sql = [[
        CREATE TABLE IF NOT EXISTS `pf_emsmdt_sops` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `title` VARCHAR(128) NOT NULL,
          `category` VARCHAR(64) NOT NULL,
          `purpose` TEXT NOT NULL,
          `policy` TEXT NOT NULL,
          `procedure_text` TEXT NOT NULL,
          `notes` TEXT NULL,
          `updated_by` VARCHAR(128) NULL,
          `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_category` (`category`),
          KEY `idx_title` (`title`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]

    exports.oxmysql:execute(sql, {}, function()
        -- legacy pf_mdt_sops copy: off unless Config.MigrateLegacyPoliceTables. On this server that is the
        -- police MDT's table, and the copy also renamed a column in it (ALTER TABLE).
        if Config.MigrateLegacyPoliceTables ~= true then
            if done then done(true) end
            return
        end
        exports.oxmysql:scalar(
            'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
            { LEGACY_SOP_TABLE },
            function(hasLegacyTable)
                if (tonumber(hasLegacyTable) or 0) <= 0 then
                    if done then done(true) end
                    return
                end

                exports.oxmysql:scalar(('SELECT COUNT(*) FROM `%s`'):format(SOP_TABLE), {}, function(newCount)
                    if (tonumber(newCount) or 0) > 0 then
                        if done then done(true) end
                        return
                    end

                    exports.oxmysql:scalar(
                        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
                        { LEGACY_SOP_TABLE, 'procedure' },
                        function(hasLegacyProcedure)
                            local function doCopy()
                                exports.oxmysql:execute(
                                    ('INSERT INTO `%s` (title, category, purpose, policy, procedure_text, notes, updated_by, updated_at, created_at) SELECT title, category, purpose, policy, procedure_text, notes, updated_by, updated_at, created_at FROM `%s`'):format(SOP_TABLE, LEGACY_SOP_TABLE),
                                    {},
                                    function()
                                        if done then done(true) end
                                    end
                                )
                            end

                            if (tonumber(hasLegacyProcedure) or 0) > 0 then
                                exports.oxmysql:execute(
                                    ('ALTER TABLE `%s` CHANGE `procedure` `procedure_text` TEXT NOT NULL'):format(LEGACY_SOP_TABLE),
                                    {},
                                    function()
                                        doCopy()
                                    end
                                )
                            else
                                doCopy()
                            end
                        end
                    )
                end)
            end
        )
    end)
end

local SEED_SOPS = {
    {
        title = 'Scene Safety and Staging',
        category = 'Operations',
        purpose = 'Reduce risk to crew and patients on arrival.',
        policy = 'Crew safety comes first. Stage when hazards exist or scene security is uncertain.',
        procedure = '1) Slow approach; scan for hazards (weapons, crowds, traffic, fire).\n2) If unsafe, stage and request appropriate support.\n3) Establish safe access/egress for unit.\n4) Communicate scene status and needed resources.\n5) Enter when safe and reassess continuously.',
        notes = 'Do not rush into active threats; use cover and distance.'
    },
    {
        title = 'Primary Assessment (ABC/Trauma Check)',
        category = 'Patient Care',
        purpose = 'Standardize rapid identification of life threats.',
        policy = 'Treat immediate life threats before secondary assessments.',
        procedure = '1) PPE on; confirm scene safety.\n2) Airway: open/clear, suction as needed, adjuncts per scope.\n3) Breathing: assess rate/effort, provide oxygen/ventilation as indicated.\n4) Circulation: control hemorrhage, check pulses, start shock management.\n5) Disability/exposure: quick neuro check, expose as needed, prevent hypothermia.\n6) Reassess frequently and document changes.',
        notes = 'Upgrade transport priority for deterioration or unstable vitals.'
    },
    {
        title = 'Cardiac Arrest (CPR / Resuscitation)',
        category = 'Patient Care',
        purpose = 'Provide consistent resuscitation workflow.',
        policy = 'High-quality CPR and early defibrillation are priorities; follow local protocols and scope of practice.',
        procedure = '1) Confirm arrest; begin CPR immediately.\n2) Apply AED/monitor and defibrillate as indicated.\n3) Establish airway/ventilation per scope; minimize interruptions.\n4) Rotate compressors; monitor ETCO2 if available.\n5) Consider reversible causes and follow protocol meds as permitted.\n6) Document times, shocks, rhythm, and outcomes.',
        notes = 'Follow local ROSC/post-ROSC and termination-of-resuscitation rules.'
    },
    {
        title = 'Overdose / Opioid Reversal',
        category = 'Patient Care',
        purpose = 'Treat suspected overdose safely and consistently.',
        policy = 'Support airway and ventilation first; administer reversal agents per protocol.',
        procedure = '1) Assess airway/breathing; provide BVM ventilation if inadequate.\n2) Check glucose when indicated.\n3) Administer naloxone per protocol and reassess.\n4) Monitor for withdrawal/agitation; ensure scene safety.\n5) Recommend transport; document refusal carefully if declined.',
        notes = 'Patients may re-sedate; monitor continuously.'
    },
    {
        title = 'Medication Administration',
        category = 'Patient Care',
        purpose = 'Ensure safe medication administration and documentation.',
        policy = 'Medication must follow scope, indications/contraindications, and double-check procedures when applicable.',
        procedure = '1) Confirm indications and check allergies.\n2) Verify right patient, medication, dose, route, time.\n3) Administer and monitor for adverse reactions.\n4) Document medication, dose, route, time, and response.',
        notes = 'If an adverse reaction occurs, treat and notify medical control.'
    },
    {
        title = 'Refusal of Care / Transport',
        category = 'Documentation',
        purpose = 'Handle refusals consistently and defensibly.',
        policy = 'Refusals require capacity assessment, risks explained, and clear documentation.',
        procedure = '1) Assess decision-making capacity.\n2) Explain risks, benefits, and alternatives.\n3) Offer transport and re-contact instructions.\n4) Document refusal details and obtain signature if possible.',
        notes = 'If capacity is questionable, request medical control as appropriate.'
    },
    {
        title = 'Hospital Handoff (MIST/IMIST)',
        category = 'Operations',
        purpose = 'Improve continuity of care during transfer to ED staff.',
        policy = 'Provide a concise structured handoff with key findings and interventions.',
        procedure = '1) Identify patient and chief complaint.\n2) Mechanism/medical history and relevant timeline.\n3) Injuries/findings, vitals trends, and treatments given.\n4) Provide pending concerns and transport details.\n5) Transfer documentation and confirm questions answered.',
        notes = 'Avoid radioing private details on open channels.'
    },
    {
        title = 'Radio Communications',
        category = 'Operations',
        purpose = 'Standardize radio traffic and unit status updates.',
        policy = 'Use clear, professional communications; keep traffic concise.',
        procedure = '1) Acknowledge dispatch and provide en route status.\n2) Update on arrival, transport, and clear.\n3) Request additional resources early when needed.\n4) Use designated medical channels when available.',
        notes = 'Share only minimum necessary information.'
    },
    {
        title = 'PPE and Infection Control',
        category = 'Safety',
        purpose = 'Reduce exposure risk during patient contact and transport.',
        policy = 'Appropriate PPE is required based on exposure risk; contaminated equipment must be cleaned per protocol.',
        procedure = '1) Choose PPE based on body fluid and airborne risk.\n2) Use hand hygiene before and after patient contact.\n3) Dispose of sharps in approved containers only.\n4) Decontaminate stretcher and unit after transport as needed.',
        notes = 'Report exposures immediately and follow post-exposure procedures.'
    },
    {
        title = 'Mass Casualty Incident (MCI)',
        category = 'Critical Incidents',
        purpose = 'Coordinate triage and transport during multiple-patient incidents.',
        policy = 'Use a structured triage approach and coordinate with incident command and receiving facilities.',
        procedure = '1) Establish staging and request additional units.\n2) Implement triage and tag patients (START/other local system).\n3) Communicate patient counts and severity to command.\n4) Coordinate transport distribution with hospitals.\n5) Document triage decisions when feasible.',
        notes = 'Do not overwhelm a single facility unless directed.'
    },
    {
        title = 'Code 3 Driving',
        category = 'Vehicle Operations',
        purpose = 'Set rules for lights-and-siren responses.',
        policy = 'Code 3 is authorized only for emergencies; due regard for safety is required at all times.',
        procedure = '1) Activate lights and siren before entering intersections.\n2) Slow and clear all red lights/stop signs.\n3) Notify dispatch of response level changes.\n4) Reduce speed in adverse weather or dense areas.\n5) Cancel Code 3 when downgraded or no longer needed.',
        notes = 'Arriving safely is the priority.'
    },
}

local function seedIfEmpty()
    if not hasOxMySQL() then return end
    local force = Config and Config.SOP and Config.SOP.ForceSeed == true

    exports.oxmysql:scalar(('SELECT COUNT(*) FROM `%s`'):format(SOP_TABLE), {}, function(count)
        local existing = tonumber(count) or 0
        if existing > 0 and not force then return end

        local function doSeed()
            for _, s in ipairs(SEED_SOPS) do
                exports.oxmysql:insert(
                    ('INSERT INTO `%s` (title, category, purpose, policy, procedure_text, notes, updated_by, updated_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())'):format(SOP_TABLE),
                    { s.title, s.category, s.purpose, s.policy, s.procedure, s.notes, 'System Seed' }
                )
            end
        end

        if existing > 0 and force then
            exports.oxmysql:execute(('DELETE FROM `%s`'):format(SOP_TABLE), {}, function()
                doSeed()
            end)
            return
        end

        -- Table is empty
        doSeed()
    end)
end

CreateThread(function()
    Wait(1000)
    ensureTable(function(ok)
        if ok then seedIfEmpty() end
    end)
end)

local function buildUpdatedBy(info)
    if not info or not info.player then return 'Unknown' end
    local pd = info.player.PlayerData
  local gradeLabel = (pd.job and pd.job.grade and pd.job.grade.name) or 'Staff'
    local char = pd.charinfo or {}
    local name = ((char.firstname or '') .. ' ' .. (char.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
  if name == '' then name = pd.citizenid or 'Staff' end
    return string.format('%s %s', gradeLabel, name)
end

local function validatePayload(payload)
    if type(payload) ~= 'table' then return false, 'invalid_payload' end
    local title = trim(payload.title)
    local category = trim(payload.category)
    local purpose = trim(payload.purpose)
    local policy = trim(payload.policy)
    local procedure = trim(payload.procedure)
    if title == '' or category == '' or purpose == '' or policy == '' or procedure == '' then
        return false, 'missing_fields'
    end
    if #title > 128 or #category > 64 or #purpose > 8000 or #policy > 8000 or #procedure > 16000 or #trim(payload.notes) > 4000 then
        return false, 'too_long'
    end
    return true
end

local function handleCreate(source, payload, cb)
  if not hasOxMySQL() then cb({ success = false, error = 'no_db' }); return end
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canEdit(info) then cb({ success = false, error = 'no_permission' }); return end
    local ok, err = validatePayload(payload)
    if not ok then cb({ success = false, error = err }); return end
    local notes = trim(payload.notes)
    local updatedBy = buildUpdatedBy(info)
    exports.oxmysql:insert(
      ('INSERT INTO `%s` (title, category, purpose, policy, procedure_text, notes, updated_by, updated_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())'):format(SOP_TABLE),
        { trim(payload.title), trim(payload.category), trim(payload.purpose), trim(payload.policy), trim(payload.procedure), notes ~= '' and notes or nil, updatedBy },
        function(id)
            cb({ success = true, id = id })
        end
    )
end

local function handleUpdate(source, payload, cb)
  if not hasOxMySQL() then cb({ success = false, error = 'no_db' }); return end
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canEdit(info) then cb({ success = false, error = 'no_permission' }); return end
    local id = tonumber(payload and payload.id)
    if not id then cb({ success = false, error = 'invalid_id' }); return end
    local ok, err = validatePayload(payload)
    if not ok then cb({ success = false, error = err }); return end
    local notes = trim(payload.notes)
    local updatedBy = buildUpdatedBy(info)
    exports.oxmysql:execute(
      ('UPDATE `%s` SET title = ?, category = ?, purpose = ?, policy = ?, procedure_text = ?, notes = ?, updated_by = ?, updated_at = NOW() WHERE id = ?'):format(SOP_TABLE),
        { trim(payload.title), trim(payload.category), trim(payload.purpose), trim(payload.policy), trim(payload.procedure), notes ~= '' and notes or nil, updatedBy, id },
        function()
            cb({ success = true, id = id })
        end
    )
end

local function handleDelete(source, id, cb)
  if not hasOxMySQL() then cb({ success = false, error = 'no_db' }); return end
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    if not canEdit(info) then cb({ success = false, error = 'no_permission' }); return end
    local sopId = tonumber(id)
    if not sopId then cb({ success = false, error = 'invalid_id' }); return end
    exports.oxmysql:execute(('DELETE FROM `%s` WHERE id = ?'):format(SOP_TABLE), { sopId }, function()
        cb({ success = true })
    end)
end

QBCore.Functions.CreateCallback('pf_emsmdt:getSOPs', function(source, cb, data)
  if not hasOxMySQL() then cb({ success = false, error = 'no_db' }); return end
    local info = getPlayerInfo(source)
    dprint('[SOP DEBUG] getSOPs called by source:', source, 'allowed:', info and info.allowed)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end

  local responded = false
  SetTimeout(5000, function()
    if not responded then
      responded = true
      cb({ success = false, error = 'db_timeout' })
    end
  end)
    local search = trim(data and data.search)
    local category = trim(data and data.category)
    local where = {}
    local params = {}
    if search ~= '' then
        local like = '%' .. search .. '%'
        table.insert(where, '(title LIKE ? OR category LIKE ? OR purpose LIKE ? OR policy LIKE ? OR procedure_text LIKE ? OR notes LIKE ?)')
        for _ = 1, 6 do table.insert(params, like) end
    end
    if category ~= '' then
        table.insert(where, 'category = ?')
        table.insert(params, category)
    end
    local sql = ('SELECT id, title, category, purpose, policy, procedure_text AS `procedure`, notes, updated_by, updated_at, created_at FROM `%s`'):format(SOP_TABLE)
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY category ASC, title ASC, updated_at DESC'
    dprint('[SOP DEBUG] Executing SQL:', sql)
    exports.oxmysql:execute(sql, params, function(rows)
      if responded then return end
      responded = true
      dprint('[SOP DEBUG] Query returned', rows and #rows or 0, 'rows')
      cb({ success = true, data = rows or {} })
    end)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:getSOP', function(source, cb, id)
  if not hasOxMySQL() then cb({ success = false, error = 'no_db' }); return end
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    local sopId = tonumber(id and id.id or id)
    if not sopId then cb({ success = false, error = 'invalid_id' }); return end

  local responded = false
  SetTimeout(5000, function()
    if not responded then
      responded = true
      cb({ success = false, error = 'db_timeout' })
    end
  end)

    exports.oxmysql:execute(('SELECT id, title, category, purpose, policy, procedure_text AS `procedure`, notes, updated_by, updated_at, created_at FROM `%s` WHERE id = ? LIMIT 1'):format(SOP_TABLE), { sopId }, function(rows)
    if responded then return end
    responded = true
    cb({ success = true, data = (rows and rows[1]) or nil })
    end)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:createSOP', function(source, cb, payload)
    handleCreate(source, payload, cb)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:updateSOP', function(source, cb, payload)
    handleUpdate(source, payload, cb)
end)

QBCore.Functions.CreateCallback('pf_emsmdt:deleteSOP', function(source, cb, payload)
    handleDelete(source, payload and payload.id or payload, cb)
end)

RegisterNetEvent('pf_emsmdt:createSOP', function(payload)
    local src = source
    handleCreate(src, payload, function(result)
    TriggerClientEvent('pf_emsmdt:sop:result', src, { action = 'create', result = result })
    end)
end)

RegisterNetEvent('pf_emsmdt:updateSOP', function(payload)
    local src = source
    handleUpdate(src, payload, function(result)
    TriggerClientEvent('pf_emsmdt:sop:result', src, { action = 'update', result = result })
    end)
end)

RegisterNetEvent('pf_emsmdt:deleteSOP', function(id)
    local src = source
    handleDelete(src, id, function(result)
    TriggerClientEvent('pf_emsmdt:sop:result', src, { action = 'delete', result = result })
    end)
end)
