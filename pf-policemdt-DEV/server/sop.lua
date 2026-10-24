local QBCore = PFMdt.GetCore()

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

local SYNCED_LAW_ID_OFFSET = 900000000
local SyncedGovernmentLaws = {}

local function isSyncedLawId(id)
  local num = tonumber(id)
  return num and num >= SYNCED_LAW_ID_OFFSET
end

local function syncedLawEntry(law)
  local id = SYNCED_LAW_ID_OFFSET + (tonumber(law.id) or 0)
  local content = trim(law.content)
  if content == '' then
    content = 'No policy text provided.'
  end

  return {
    id = id,
    title = law.title or ('Law #' .. tostring(law.id or '?')),
    category = law.category or 'Government Laws',
    purpose = content,
    policy = ('Penalty: %s-%s months | Fine: $%s-$%s'):format(
      tostring(tonumber(law.penalty_min) or 0),
      tostring(tonumber(law.penalty_max) or 0),
      tostring(tonumber(law.fine_min) or 0),
      tostring(tonumber(law.fine_max) or 0)
    ),
    procedure = 'Published by City Hall. This record is synced from government records and is read-only in MDT.',
    notes = law.status == 'repealed' and 'Status: Repealed' or 'Status: Active',
    updated_by = 'Government Records',
    updated_at = law.updated_at or law.effective_date or os.date('%Y-%m-%d %H:%M:%S'),
    created_at = law.effective_date or law.updated_at or os.date('%Y-%m-%d %H:%M:%S'),
    source = 'government',
    readonly = true
  }
end

exports('SyncLaws', function(laws)
  SyncedGovernmentLaws = {}
  if type(laws) ~= 'table' then
    return false
  end

  for _, law in ipairs(laws) do
    if type(law) == 'table' and law.status == 'active' then
      local entry = syncedLawEntry(law)
      SyncedGovernmentLaws[entry.id] = entry
    end
  end

  dprint('[SOP DEBUG] Synced government laws:', tostring(#laws))
  return true
end)

exports('GetSyncedLaws', function()
  local out = {}
  for _, entry in pairs(SyncedGovernmentLaws) do
    out[#out + 1] = entry
  end
  table.sort(out, function(a, b)
    return tostring(a.title or '') < tostring(b.title or '')
  end)
  return out
end)

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

local function canEdit(info)
    return info and info.allowed and ((info.grade or 0) >= 4 or info.isOwner)
end

local function ensureTable(done)
  if not hasOxMySQL() then
    if done then done(false) end
    return
  end
    local sql = [[
        CREATE TABLE IF NOT EXISTS `pf_mdt_sops` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `title` VARCHAR(128) NOT NULL,
          `category` VARCHAR(64) NOT NULL,
          `purpose` TEXT NOT NULL,
          `policy` TEXT NOT NULL,
          `procedure_text` TEXT NOT NULL,
          `notes` TEXT NULL,
          `updated_by` VARCHAR(128) NULL,
          `updated_at` DATETIME NULL,
          `created_at` DATETIME NULL,
          PRIMARY KEY (`id`),
          KEY `idx_sop_category` (`category`),
          KEY `idx_sop_title` (`title`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
  exports.oxmysql:execute(sql, {}, function()
    -- Only attempt migration if the legacy column exists; some oxmysql versions
    -- may not invoke callbacks on SQL errors, which would otherwise hang init.
    exports.oxmysql:scalar(
      'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
      { 'pf_mdt_sops', 'procedure' },
      function(hasLegacy)
        if (tonumber(hasLegacy) or 0) > 0 then
          exports.oxmysql:execute(
            'ALTER TABLE `pf_mdt_sops` CHANGE `procedure` `procedure_text` TEXT NOT NULL',
            {},
            function()
              if done then done(true) end
            end
          )
        else
          if done then done(true) end
        end
      end
    )
  end)
end

local SEED_SOPS = {
    { title = 'Officer Conduct and Professionalism', category = 'General Conduct',
      purpose = 'Set expectations for demeanor, language, and professionalism when representing the department.',
      policy = 'Officers shall treat all persons with respect, avoid discriminatory language, and follow department appearance and communication standards.',
      procedure = '1) Maintain clean uniform and gear before shift.\n2) Use calm, clear, and respectful speech on all contacts.\n3) De-escalate tense interactions through tone and space.\n4) Report observed misconduct through the chain of command.',
      notes = 'Applies on and off duty while identifying as law enforcement.' },
    { title = 'Chain of Command', category = 'General Conduct',
      purpose = 'Clarify how direction flows and how officers raise issues or approvals.',
      policy = 'Personnel follow the established chain for directives, approvals, and grievances unless urgency demands immediate action.',
      procedure = '1) Take routine direction from immediate supervisor.\n2) Elevate critical issues to next level if supervisor unavailable.\n3) Document requests for approvals (leave, training, equipment).\n4) Notify command when bypassing steps for emergency reasons.',
      notes = 'Use clear timestamps when escalating beyond normal order.' },
    { title = 'On-Duty and Off-Duty Conduct', category = 'General Conduct',
      purpose = 'Outline expected conduct while working and when identifiable as an officer off duty.',
      policy = 'Officers act with integrity, avoid conflicts of interest, and do not misuse authority while off duty.',
      procedure = '1) Do not consume intoxicants on duty.\n2) Avoid enforcement while off duty unless life-threatening.\n3) Identify conflicts (business, family, financial) early.\n4) Notify supervision after any notable off-duty police action.',
      notes = 'Seek supervisor guidance before off-duty security details.' },
    { title = 'Body Camera Usage', category = 'General Conduct',
      purpose = 'Provide consistent use of body-worn cameras for accountability.',
      policy = 'BWCs are activated during enforcement, detentions, transports, and citizen contacts unless prohibited by law.',
      procedure = '1) Verify camera operational at start of shift.\n2) Activate before arrival on calls or immediately upon contact.\n3) Verbally note when privacy requires deactivation; reactivate ASAP.\n4) Tag uploads with incident identifiers before end of shift.',
      notes = 'Follow state law for restricted locations and protected communications.' },
    { title = 'Ethics and Integrity', category = 'General Conduct',
      purpose = 'Reinforce honesty, impartiality, and avoidance of corruption.',
      policy = 'Officers do not solicit gifts, falsify statements, or conceal evidence. Transparency with supervisors is mandatory.',
      procedure = '1) Disclose gifts, secondary jobs, or relationships that may affect duty.\n2) Accurately record actions and evidence.\n3) Refuse preferential treatment requests; report attempts.\n4) Immediately report corruption or integrity concerns.',
      notes = 'Misrepresentation in reports or testimony is grounds for discipline.' },
    { title = 'Traffic Stop Procedures', category = 'Patrol Operations',
      purpose = 'Provide safe, consistent approach to vehicle stops.',
      policy = 'Stops are conducted with clear identification, radio updates, and adherence to officer safety and constitutional limits.',
      procedure = '1) Radio location, plate, occupants if known.\n2) Position patrol car safely; activate lights and camera.\n3) Approach cautiously, identify yourself, and state reason.\n4) Check warrants and documents; take action within policy.\n5) Conclude with clear instructions and documentation.',
      notes = 'Use two-officer approach when available on high-risk indicators.' },
    { title = 'Pedestrian Stops', category = 'Patrol Operations',
      purpose = 'Guide contact with pedestrians while respecting constitutional rights.',
      policy = 'Officers must have reasonable suspicion for detentions and articulate the reason and duration.',
      procedure = '1) Observe and form reasonable suspicion before detaining.\n2) Identify yourself and the reason for the stop.\n3) Conduct frisk only when articulable safety concerns exist.\n4) Release promptly when suspicion is dispelled; document the stop.',
      notes = 'Voluntary contacts remain consensual and may be ended by the subject.' },
    { title = 'Field Interviews', category = 'Patrol Operations',
      purpose = 'Standardize collection of information during investigative contacts.',
      policy = 'Interviews are voluntary unless detained; officers must note demeanor, statements, and conditions.',
      procedure = '1) Confirm whether the contact is voluntary or detained.\n2) Ask concise questions tied to the observed activity.\n3) Record identifiers and statements accurately.\n4) Enter FI data into approved system before end of shift.',
      notes = 'Parents/guardians should be notified when interviewing juveniles when practical.' },
    { title = 'Arrest Procedures', category = 'Patrol Operations',
      purpose = 'Ensure arrests are lawful, safe, and documented.',
      policy = 'Probable cause is required; force and restraints follow policy; arrestees are advised of rights when interrogated.',
      procedure = '1) Confirm probable cause and articulate elements.\n2) Handcuff, search, and secure weapons/evidence.\n3) Advise Miranda when questioning post-custody.\n4) Transport safely; complete booking paperwork and reports.',
      notes = 'Medical clearance required if injury or complaint of pain.' },
    { title = 'Prisoner Transport', category = 'Patrol Operations',
      purpose = 'Provide safe, humane transport of persons in custody.',
      policy = 'Vehicles are searched before/after transport; prisoners seat-belted and monitored.',
      procedure = '1) Search prisoner and vehicle prior to loading.\n2) Seat-belt and position to reduce risk of assault or escape.\n3) Monitor during transport; advise dispatch of start/end mileage when policy requires.\n4) Transfer custody with documentation and property inventory.',
      notes = 'Opposite-sex transports require radio log and notification when possible.' },
    { title = 'Report Writing Standards', category = 'Patrol Operations',
      purpose = 'Maintain clear, timely, and accurate reports.',
      policy = 'Reports must be objective, completed before end of shift unless approved extension, and include evidence references.',
      procedure = '1) Use clear chronology and separate observations from statements.\n2) Include elements of offenses and probable cause.\n3) Reference body cam identifiers and evidence numbers.\n4) Submit for supervisory review when required.',
      notes = 'Proofread for spelling, dates, and identifiers before submission.' },
    { title = 'Use of Force Continuum', category = 'Use of Force',
      purpose = 'Explain proportional response options and expectations.',
      policy = 'Force must be reasonable, necessary, and proportional to resistance, with de-escalation preferred when feasible.',
      procedure = '1) Assess threat, severity, and subject behavior.\n2) Attempt verbal de-escalation when safe.\n3) Use lowest effective option; escalate only as needed.\n4) Render aid after force and notify supervisor immediately.\n5) Document and report per force reporting policy.',
      notes = 'Early communication reduces need for higher force options.' },
    { title = 'Firearm Discharge Policy', category = 'Use of Force',
      purpose = 'Define when intentional firearm discharge is authorized.',
      policy = 'Firearm use is restricted to defense of life or to stop serious bodily harm; warning shots are prohibited.',
      procedure = '1) Point only when deadly force conditions may exist.\n2) Consider backdrop and bystanders before firing.\n3) Notify supervisor and secure scene after discharge.\n4) Provide medical aid and preserve evidence.\n5) Complete required reports and submit firearm for inspection.',
      notes = 'Accidental discharges require immediate notification and review.' },
    { title = 'Less-Lethal Weapons', category = 'Use of Force',
      purpose = 'Set guidance for tasers, beanbag, OC, and similar tools.',
      policy = 'Less-lethal options are used when reasonably necessary to gain compliance and when benefits outweigh risks.',
      procedure = '1) Assess subject factors (age, health indicators, environment).\n2) Provide warnings when practical.\n3) Avoid sensitive areas (head, spine) unless deadly force would be justified.\n4) After use, handcuff, monitor, and arrange medical evaluation.\n5) Document cartridge numbers or munitions used.',
      notes = 'Remove probes per medical protocol; photograph impacts.' },
    { title = 'Duty to Intervene', category = 'Use of Force',
      purpose = 'Ensure officers act to stop unlawful or excessive force.',
      policy = 'Officers must intervene and report when observing unreasonable force or misconduct regardless of rank.',
      procedure = '1) Verbally direct the involved officer to stop.\n2) Physically intervene if verbal direction fails and safe.\n3) Render aid to affected persons.\n4) Notify supervisor immediately and document incident.',
      notes = 'Retaliation for intervention or reporting is prohibited.' },
    { title = 'Use of Deadly Force', category = 'Use of Force',
      purpose = 'Clarify deadly force threshold and responsibilities.',
      policy = 'Deadly force is authorized only to protect life from imminent threat of death or serious injury and must cease once threat ends.',
      procedure = '1) Confirm imminent threat; consider background and crossfire.\n2) Issue commands when feasible.\n3) Fire controlled rounds; reassess after each volley.\n4) Provide medical aid and secure scene.\n5) Notify command and cooperate with review.',
      notes = 'Vehicle ramming is deadly force and follows same standard.' },
    { title = 'Priority Call Handling', category = 'Emergency Response',
      purpose = 'Standardize response to high-priority incidents.',
      policy = 'Response level matches call priority; supervisors may downgrade or upgrade based on conditions.',
      procedure = '1) Monitor dispatch details and location.\n2) Acknowledge en route with unit status.\n3) Use lights/siren per driving policy when responding code.\n4) Stage when appropriate and wait for cover.\n5) Update dispatch with arrival, actions, and clearance.',
      notes = 'Self-dispatching to high-priority calls requires notification.' },
    { title = 'Active Shooter Response', category = 'Emergency Response',
      purpose = 'Provide immediate action steps to stop ongoing deadly threats.',
      policy = 'Primary mission is to stop the threat; officers form contact teams and move to gunfire when safe to do so.',
      procedure = '1) Arrive, assess, and move toward threat with minimum team.\n2) Bypass wounded until threat stopped; relay locations.\n3) Establish contact and rescue teams; coordinate with dispatch.\n4) Transition to perimeter and handoff to investigative units.',
      notes = 'Unified command with fire/EMS once scene stabilizes.' },
    { title = 'Officer Down Response', category = 'Emergency Response',
      purpose = 'Guide coordinated response to injured officers.',
      policy = 'Closest units respond code; command establishes rescue plan, perimeter, and medical access.',
      procedure = '1) Broadcast location, suspect info, and needs.\n2) Form rescue team; move with cover to recover officer.\n3) Provide immediate medical care and evacuate to EMS.\n4) Secure scene for investigation and peer support.',
      notes = 'Notify command staff as soon as practicable.' },
    { title = 'High-Risk Felony Stops', category = 'Emergency Response',
      purpose = 'Ensure controlled stops of high-risk vehicles.',
      policy = 'Use multiple units, clear commands, and cover positions; occupants removed one at a time.',
      procedure = '1) Coordinate location with cover units.\n2) Position vehicles for cover and containment.\n3) Issue PA commands; remove and secure occupants sequentially.\n4) Clear vehicle before approach.\n5) Document and tow per policy when needed.',
      notes = 'Consider K-9 or air support when available.' },
    { title = 'Barricaded Suspects', category = 'Emergency Response',
      purpose = 'Outline containment and negotiation for barricades.',
      policy = 'Priority is preservation of life; slow, controlled response with negotiators and specialty units as needed.',
      procedure = '1) Establish perimeter and inner/outer containment.\n2) Evacuate exposed civilians and isolate suspect.\n3) Gather intel (weapons, mental health, layout).\n4) Request negotiators/SWAT early when indicators present.\n5) Document timeline and decisions for after-action.',
      notes = 'Do not force entry unless exigency or authorized tactical plan.' },
    { title = 'Patrol Vehicle Operation', category = 'Vehicle Operations',
      purpose = 'Promote safe, professional driving in marked and unmarked units.',
      policy = 'Seatbelts are mandatory; mobile data use limited to stopped or voice-directed use when safe.',
      procedure = '1) Conduct vehicle inspection at shift start.\n2) Obey traffic laws when not in emergency mode.\n3) Avoid prolonged in-vehicle computer use while moving.\n4) Report collisions immediately and photograph damage.',
      notes = 'Fatigue driving should be reported for relief when possible.' },
    { title = 'Pursuit Policy', category = 'Vehicle Operations',
      purpose = 'Define when to initiate, continue, or terminate pursuits.',
      policy = 'Pursuits are limited to violent felonies or imminent threats; risk to public must be continuously evaluated.',
      procedure = '1) Announce location, direction, speed, and reason when initiating.\n2) Supervisor assumes control and may terminate at any time.\n3) Limit number of pursuing units per policy.\n4) Disengage when risk outweighs need for immediate capture.\n5) Complete pursuit report after termination.',
      notes = 'Aerial support may allow reduced ground pressure.' },
    { title = 'Code 3 Driving', category = 'Vehicle Operations',
      purpose = 'Set rules for lights-and-siren responses.',
      policy = 'Code 3 is authorized only for emergencies; due regard for safety is required at all times.',
      procedure = '1) Activate lights and siren before entering intersections.\n2) Slow and clear all red lights/stop signs.\n3) Notify dispatch of response level changes.\n4) Reduce speed in adverse weather or dense areas.',
      notes = 'Cancel Code 3 when scene stabilized or downgraded.' },
    { title = 'PIT Maneuver Authorization', category = 'Vehicle Operations',
      purpose = 'Govern use of Precision Immobilization Technique.',
      policy = 'PIT is a form of force and may be used when risks of continued flight outweigh maneuver risks and when trained officers execute.',
      procedure = '1) Obtain supervisor approval when practicable.\n2) Assess speed, environment, and vehicle type.\n3) Execute within trained speed thresholds.\n4) Coordinate with secondary units for containment.\n5) Provide medical check for occupants post-PIT.',
      notes = 'Avoid PIT on motorcycles, high centers of gravity, or hazardous cargo unless deadly force justified.' },
    { title = 'Air Support Coordination', category = 'Vehicle Operations',
      purpose = 'Leverage aviation assets to improve safety.',
      policy = 'Air support is requested through dispatch or supervisor; ground units adjust tactics when air has visual.',
      procedure = '1) Provide clear location, suspect description, and hazards.\n2) Yield primary following role to air unit when overhead.\n3) Use directed tactics (covert follow, perimeter guidance).\n4) Maintain comms discipline on assigned channel.',
      notes = 'Cancel ground pursuits when air can track safely when policy allows.' },
    { title = 'Crime Scene Management', category = 'Investigations',
      purpose = 'Protect scenes to preserve evidence and safety.',
      policy = 'Officers establish inner/outer perimeters, log entry, and prevent unnecessary contamination.',
      procedure = '1) Render aid and neutralize threats first.\n2) Establish tape and a single entry point.\n3) Start scene log and note initial conditions.\n4) Await investigators; do not move evidence unless necessary.\n5) Brief investigators with observations and actions taken.',
      notes = 'Weather or crowds may justify rapid evidence protection measures.' },
    { title = 'Evidence Collection and Handling', category = 'Investigations',
      purpose = 'Ensure evidence is lawfully collected, packaged, and tracked.',
      policy = 'Chain of custody must be maintained with accurate labeling and submission.',
      procedure = '1) Photograph evidence in place when safe.\n2) Use gloves and appropriate packaging for item type.\n3) Label with case number, location, collector, date/time.\n4) Complete evidence entry and submit to property promptly.',
      notes = 'Biological and digital evidence require special handling protocols.' },
    { title = 'Search and Seizure', category = 'Investigations',
      purpose = 'Guide lawful searches respecting constitutional limits.',
      policy = 'Searches require warrant, consent, exigency, or other lawful exception; scope limited to justification.',
      procedure = '1) Determine legal basis and document it.\n2) Obtain written or recorded consent when applicable.\n3) Limit search to areas authorized; stop when scope met.\n4) Inventory seized items and provide receipts when required.',
      notes = 'Consult supervisor or legal advisor for complex searches.' },
    { title = 'Warrants and Affidavits', category = 'Investigations',
      purpose = 'Standardize preparation and execution of warrants.',
      policy = 'Affidavits must be truthful, complete, and reviewed; execution follows knock-notice rules unless lawful exception.',
      procedure = '1) Draft affidavit with probable cause and nexus clearly stated.\n2) Obtain supervisory and prosecutorial review when required.\n3) Brief team on layout, risks, and roles.\n4) Execute warrant safely; record times and inventory items seized.',
      notes = 'Return warrant and inventory to issuing authority promptly.' },
    { title = 'Interview and Interrogation', category = 'Investigations',
      purpose = 'Provide lawful, ethical questioning standards.',
      policy = 'Miranda advisement is given when required; coercion, promises, or threats are prohibited.',
      procedure = '1) Determine custody status and need for Miranda.\n2) Record interviews when policy allows.\n3) Ask open-ended questions; avoid leading promises.\n4) Document verbatim statements when significant.',
      notes = 'Provide breaks and basic needs to maintain voluntariness.' },
    { title = 'SWAT Deployment', category = 'Specialized Units',
      purpose = 'Define when to request tactical team support.',
      policy = 'SWAT is activated for high-risk operations exceeding patrol capabilities and requires command approval.',
      procedure = '1) Identify high-risk factors (weapons, fortification, hostages).\n2) Notify supervisor and command with facts.\n3) Preserve perimeter and gather intel until team arrives.\n4) Support unified command post once deployed.',
      notes = 'Do not self-deploy into inner perimeter without assignment.' },
    { title = 'K-9 Deployment', category = 'Specialized Units',
      purpose = 'Set safe, lawful use of police canines.',
      policy = 'Handlers control deployment; bites require medical care and reporting; announcements made when required.',
      procedure = '1) Assess necessity (flight, hiding suspects, evidence search).\n2) Give loud announcement before apprehension deployments when practical.\n3) Maintain leash control unless directed otherwise.\n4) Provide medical aid after contact and document deployment.',
      notes = 'Avoid K-9 deployment on passive crowds or for mere non-compliance.' },
    { title = 'Traffic Enforcement Operations', category = 'Specialized Units',
      purpose = 'Coordinate planned traffic safety details.',
      policy = 'Operations focus on safety violations; citations and arrests follow standard procedures with data collection.',
      procedure = '1) Brief team on location, goals, and legal considerations.\n2) Use visible markings and cones when safe.\n3) Track stops, warnings, and citations issued.\n4) Debrief results and adjust tactics for future ops.',
      notes = 'Coordinate with media or community outreach when appropriate.' },
    { title = 'Narcotics Operations', category = 'Specialized Units',
      purpose = 'Provide safeguards for undercover and narcotics enforcement.',
      policy = 'Operations require supervisor approval, risk assessment, and adherence to informant handling rules.',
      procedure = '1) Complete operational plan with objectives and contingencies.\n2) Vet and document informant use.\n3) Maintain surveillance teams and arrest contingencies.\n4) Preserve evidence chain and submit for lab promptly.',
      notes = 'Avoid buy/bust without cover and surveillance teams.' },
    { title = 'Complaint Handling', category = 'Internal Affairs',
      purpose = 'Ensure public and internal complaints are recorded and investigated.',
      policy = 'All complaints are accepted without delay; retaliation is prohibited; documentation is mandatory.',
      procedure = '1) Accept complaint in any form; provide reference number.\n2) Notify supervisor and IA channel per policy.\n3) Preserve any evidence (video, documents).\n4) Provide status updates through established process.',
      notes = 'Anonymous complaints are documented and assessed equally.' },
    { title = 'Use of Force Review', category = 'Internal Affairs',
      purpose = 'Standardize administrative review of force incidents.',
      policy = 'Every reportable force event is reviewed for policy compliance by supervision and, when required, IA.',
      procedure = '1) Officer submits force report and uploads media before end of shift when feasible.\n2) Supervisor conducts interview and scene review.\n3) Forward package to IA/command for final determination.\n4) Track corrective actions or training needs.',
      notes = 'Serious force may trigger parallel criminal and admin reviews.' },
    { title = 'Officer Involved Incidents', category = 'Internal Affairs',
      purpose = 'Outline response to shootings, serious collisions, or critical events involving officers.',
      policy = 'Involved officers are separated, statements managed per legal and contractual requirements, and support services offered.',
      procedure = '1) Secure scene and evidence; assign investigators.\n2) Separate involved and witness officers; assign peers.\n3) Provide medical and wellness resources.\n4) Follow critical incident protocol for interviews and relief from duty.',
      notes = 'Union/employee rights are honored per agreements and law.' },
    { title = 'Internal Investigations', category = 'Internal Affairs',
      purpose = 'Ensure fair, thorough investigations of misconduct.',
      policy = 'Investigations are objective, timely, and documented; subjects are notified consistent with policy.',
      procedure = '1) Assign investigator and scope; secure evidence.\n2) Interview complainant, witnesses, and subject officer.\n3) Analyze policy compliance and document findings.\n4) Present findings to command for disposition.',
      notes = 'Maintain confidentiality and protect against retaliation.' },
    { title = 'Field Training Program', category = 'Training',
      purpose = 'Define structure for training new officers.',
      policy = 'FTOs follow approved curriculum, document daily performance, and provide timely feedback.',
      procedure = '1) Orient trainee to equipment, policy, and expectations.\n2) Use daily observation reports with specific examples.\n3) Conduct mid-phase and end-phase evaluations.\n4) Recommend advancement, extension, or remediation with justification.',
      notes = 'FTO changes require supervisor approval.' },
    { title = 'Probationary Officer Standards', category = 'Training',
      purpose = 'Set expectations for probationary performance and milestones.',
      policy = 'Probationers must meet training benchmarks, policy compliance, and attendance requirements.',
      procedure = '1) Provide probation schedule and required competencies.\n2) Meet regularly with supervisor and FTO for feedback.\n3) Address deficiencies with written improvement plans.\n4) Document completion or extension decisions in writing.',
      notes = 'Failure to meet standards may result in separation.' },
    { title = 'Remedial Training', category = 'Training',
      purpose = 'Offer structured remediation for identified performance gaps.',
      policy = 'Supervisors may assign remedial training to address deficiencies before discipline when appropriate.',
      procedure = '1) Identify specific deficiency and desired outcome.\n2) Assign targeted training or mentoring with timeline.\n3) Document completion and evaluate improvement.\n4) Escalate if performance does not improve.',
      notes = 'Serious misconduct may bypass remediation steps.' },
    { title = 'Firearms Qualification', category = 'Training',
      purpose = 'Ensure officers maintain firearms proficiency and safety.',
      policy = 'All sworn personnel must qualify on issued weapons at required intervals; failure triggers remediation.',
      procedure = '1) Attend scheduled qualification sessions.\n2) Follow range safety rules and instructor commands.\n3) Log scores and any malfunctions.\n4) Complete remedial sessions until qualified or relieved of duty weapons.',
      notes = 'Document alternative duty status if qualification is not met.' },
}

local function seedIfEmpty()
  if not hasOxMySQL() then return end
    exports.oxmysql:scalar('SELECT COUNT(*) FROM `pf_mdt_sops`', {}, function(count)
        if (tonumber(count) or 0) > 0 then return end
        local now = os.date('%Y-%m-%d %H:%M:%S')
        for _, s in ipairs(SEED_SOPS) do
            exports.oxmysql:insert(
                'INSERT INTO `pf_mdt_sops` (title, category, purpose, policy, procedure_text, notes, updated_by, updated_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                { s.title, s.category, s.purpose, s.policy, s.procedure, s.notes, 'System Seed', now, now }
            )
        end
    end)
end

CreateThread(function()
  -- Avoid hard-crashing if oxmysql isn't ready at resource start.
  Wait(1000)
  ensureTable(function(ok)
    if ok then seedIfEmpty() end
  end)
end)

local function buildUpdatedBy(info)
    if not info or not info.player then return 'Unknown' end
    local pd = info.player.PlayerData
    local gradeLabel = (pd.job and pd.job.grade and pd.job.grade.name) or 'Officer'
    local char = pd.charinfo or {}
    local name = ((char.firstname or '') .. ' ' .. (char.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    if name == '' then name = pd.citizenid or 'Officer' end
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
    local now = os.date('%Y-%m-%d %H:%M:%S')
    exports.oxmysql:insert(
        'INSERT INTO `pf_mdt_sops` (title, category, purpose, policy, procedure_text, notes, updated_by, updated_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { trim(payload.title), trim(payload.category), trim(payload.purpose), trim(payload.policy), trim(payload.procedure), notes ~= '' and notes or nil, updatedBy, now, now },
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
    if isSyncedLawId(id) then cb({ success = false, error = 'read_only_record' }); return end
    local ok, err = validatePayload(payload)
    if not ok then cb({ success = false, error = err }); return end
    local notes = trim(payload.notes)
    local updatedBy = buildUpdatedBy(info)
    exports.oxmysql:execute(
        'UPDATE `pf_mdt_sops` SET title = ?, category = ?, purpose = ?, policy = ?, procedure_text = ?, notes = ?, updated_by = ?, updated_at = NOW() WHERE id = ?',
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
    if isSyncedLawId(sopId) then cb({ success = false, error = 'read_only_record' }); return end
    exports.oxmysql:execute('DELETE FROM `pf_mdt_sops` WHERE id = ?', { sopId }, function()
        cb({ success = true })
    end)
end

QBCore.Functions.CreateCallback('pf_mdt:getSOPs', function(source, cb, data)
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
    local sql = 'SELECT id, title, category, purpose, policy, procedure_text AS `procedure`, notes, updated_by, updated_at, created_at FROM `pf_mdt_sops`'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY category ASC, title ASC, updated_at DESC'
    dprint('[SOP DEBUG] Executing SQL:', sql)
    exports.oxmysql:execute(sql, params, function(rows)
      if responded then return end
      responded = true
      local merged = rows or {}
      for _, synced in pairs(SyncedGovernmentLaws) do
        merged[#merged + 1] = synced
      end
      table.sort(merged, function(a, b)
        local ca = tostring(a.category or '')
        local cbx = tostring(b.category or '')
        if ca == cbx then
          return tostring(a.title or '') < tostring(b.title or '')
        end
        return ca < cbx
      end)
      dprint('[SOP DEBUG] Query returned', rows and #rows or 0, 'rows')
      cb({ success = true, data = merged })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:getSOP', function(source, cb, id)
  if not hasOxMySQL() then cb({ success = false, error = 'no_db' }); return end
    local info = getPlayerInfo(source)
    if not info or not info.allowed then cb({ success = false, error = 'no_access' }); return end
    local sopId = tonumber(id and id.id or id)
    if not sopId then cb({ success = false, error = 'invalid_id' }); return end
    if SyncedGovernmentLaws[sopId] then
      cb({ success = true, data = SyncedGovernmentLaws[sopId] })
      return
    end

  local responded = false
  SetTimeout(5000, function()
    if not responded then
      responded = true
      cb({ success = false, error = 'db_timeout' })
    end
  end)

    exports.oxmysql:execute('SELECT id, title, category, purpose, policy, procedure_text AS `procedure`, notes, updated_by, updated_at, created_at FROM `pf_mdt_sops` WHERE id = ? LIMIT 1', { sopId }, function(rows)
    if responded then return end
    responded = true
    cb({ success = true, data = (rows and rows[1]) or nil })
    end)
end)

QBCore.Functions.CreateCallback('pf_mdt:createSOP', function(source, cb, payload)
    handleCreate(source, payload, cb)
end)

QBCore.Functions.CreateCallback('pf_mdt:updateSOP', function(source, cb, payload)
    handleUpdate(source, payload, cb)
end)

QBCore.Functions.CreateCallback('pf_mdt:deleteSOP', function(source, cb, payload)
    handleDelete(source, payload and payload.id or payload, cb)
end)

RegisterNetEvent('pf_mdt:createSOP', function(payload)
    local src = source
    handleCreate(src, payload, function(result)
        TriggerClientEvent('pf_mdt:sop:result', src, { action = 'create', result = result })
    end)
end)

RegisterNetEvent('pf_mdt:updateSOP', function(payload)
    local src = source
    handleUpdate(src, payload, function(result)
        TriggerClientEvent('pf_mdt:sop:result', src, { action = 'update', result = result })
    end)
end)

RegisterNetEvent('pf_mdt:deleteSOP', function(id)
    local src = source
    handleDelete(src, id, function(result)
        TriggerClientEvent('pf_mdt:sop:result', src, { action = 'delete', result = result })
    end)
end)
