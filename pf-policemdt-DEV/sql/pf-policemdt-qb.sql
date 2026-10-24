-- ============================================================================
-- PF Police MDT - FULL MERGED SQL (Base + All Migrations)
-- ============================================================================

-- ============================================================================
-- WARRANTS
-- ============================================================================
DROP TABLE IF EXISTS `pf_mdt_warrants`;
CREATE TABLE `pf_mdt_warrants` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `warrantId` VARCHAR(16) NOT NULL,
  `suspectCitizenId` VARCHAR(64) NULL,
  `suspectName` VARCHAR(128) NOT NULL,
  `charges` LONGTEXT NULL,
  `officers` LONGTEXT NULL,
  `witnesses` LONGTEXT NULL,
  `issuedBy` VARCHAR(128) NOT NULL,
  `title` VARCHAR(255) NULL,
  `narrative` LONGTEXT NULL,
  `status` VARCHAR(16) NOT NULL DEFAULT 'active',
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expiresAt` DATETIME NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_warrantId` (`warrantId`),
  KEY `idx_suspect` (`suspectName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- INCIDENTS (includes all newer involved fields)
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_incidents` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `incidentId` VARCHAR(16) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `priority` VARCHAR(12) NOT NULL DEFAULT 'LOW',
  `status` VARCHAR(16) NOT NULL DEFAULT 'active',
  `reportingOfficer` VARCHAR(128) NULL,
  `involvedCitizens` LONGTEXT NULL,
  `involvedOfficers` LONGTEXT NULL,
  `involvedVictims` LONGTEXT NULL,
  `involvedVehicles` LONGTEXT NULL,
  `charges` LONGTEXT NULL,
  `evidence_ids` LONGTEXT NULL,
  `involvedCitizenIds` LONGTEXT NULL,
  `involvedOfficerIds` LONGTEXT NULL,
  `involvedVictimIds` LONGTEXT NULL,
  `involvedVehicleIds` LONGTEXT NULL,
  `dateTime` DATETIME NULL,
  `location` VARCHAR(255) NULL,
  `narrative` LONGTEXT NULL,
  `createdBy` VARCHAR(64) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_incidentId` (`incidentId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- REPORTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_reports` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `reportId` VARCHAR(16) NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `category` VARCHAR(64) NULL,
  `title` VARCHAR(255) NOT NULL,
  `officer` VARCHAR(128) NOT NULL DEFAULT '',
  `procedure_text` TEXT NULL,
  `narrative` LONGTEXT NULL,
  `content` LONGTEXT NULL,
  `location` VARCHAR(255) NULL,
  `vehiclePlate` VARCHAR(16) NULL,
  `involvedParties` LONGTEXT NULL,
  `linkedEvidence` LONGTEXT NULL,
  `approvalStatus` VARCHAR(16) NOT NULL DEFAULT 'pending',
  `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
  `timestamp` DATETIME NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_reportId` (`reportId`),
  KEY `idx_content` (`content`(50)),
  KEY `idx_type` (`type`),
  KEY `idx_officer` (`officer`),
  KEY `idx_vehiclePlate` (`vehiclePlate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- ROSTER (Flexible Callsign System)
-- ============================================================================
DROP TABLE IF EXISTS `pf_mdt_roster`;
CREATE TABLE `pf_mdt_roster` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `callsign` VARCHAR(32) NOT NULL,
  `rank` VARCHAR(64) NOT NULL DEFAULT '',
  `officer_name` VARCHAR(128) NOT NULL DEFAULT '',
  `citizenid` VARCHAR(64) NULL,
  `unit_type` VARCHAR(64) NOT NULL DEFAULT '',
  `training_status` ENUM('NONE','TRAINING','TRAINEE') NOT NULL DEFAULT 'NONE',
  `notes` TEXT NULL,
  `created_at` DATETIME NOT NULL,
  `updated_at` DATETIME NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_callsign` (`callsign`),
  KEY `idx_citizenid` (`citizenid`),
  KEY `idx_rank` (`rank`),
  KEY `idx_unit_type` (`unit_type`),
  KEY `idx_training_status` (`training_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

-- ============================================================================
-- Seed SOP catalog (first run only)
-- ============================================================================
INSERT INTO `pf_mdt_sops` (`title`,`category`,`purpose`,`policy`,`procedure_text`,`notes`,`updated_by`,`updated_at`,`created_at`)
SELECT * FROM (
  SELECT 'Officer Conduct and Professionalism' AS `title`, 'General Conduct' AS `category`,
    'Set expectations for demeanor, language, and professionalism when representing the department.' AS `purpose`,
    'Officers shall treat all persons with respect, avoid discriminatory language, and follow department appearance and communication standards.' AS `policy`,
    '1) Maintain clean uniform and gear before shift.
  2) Use calm, clear, and respectful speech on all contacts.
  3) De-escalate tense interactions through tone and space.
  4) Report observed misconduct through the chain of command.' AS `procedure_text`,
    'Applies on and off duty while identifying as law enforcement.' AS `notes`, 'System Seed' AS `updated_by`, NOW() AS `updated_at`, NOW() AS `created_at`
  UNION ALL SELECT 'Chain of Command', 'General Conduct',
    'Clarify how direction flows and how officers raise issues or approvals.',
    'Personnel follow the established chain for directives, approvals, and grievances unless urgency demands immediate action.',
    '1) Take routine direction from immediate supervisor.
2) Elevate critical issues to next level if supervisor unavailable.
3) Document requests for approvals (leave, training, equipment).
4) Notify command when bypassing steps for emergency reasons.',
    'Use clear timestamps when escalating beyond normal order.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'On-Duty and Off-Duty Conduct', 'General Conduct',
    'Outline expected conduct while working and when identifiable as an officer off duty.',
    'Officers act with integrity, avoid conflicts of interest, and do not misuse authority while off duty.',
    '1) Do not consume intoxicants on duty.
2) Avoid enforcement while off duty unless life-threatening.
3) Identify conflicts (business, family, financial) early.
4) Notify supervision after any notable off-duty police action.',
    'Seek supervisor guidance before off-duty security details.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Body Camera Usage', 'General Conduct',
    'Provide consistent use of body-worn cameras for accountability.',
    'BWCs are activated during enforcement, detentions, transports, and citizen contacts unless prohibited by law.',
    '1) Verify camera operational at start of shift.
2) Activate before arrival on calls or immediately upon contact.
3) Verbally note when privacy requires deactivation; reactivate ASAP.
4) Tag uploads with incident identifiers before end of shift.',
    'Follow state law for restricted locations and protected communications.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Ethics and Integrity', 'General Conduct',
    'Reinforce honesty, impartiality, and avoidance of corruption.',
    'Officers do not solicit gifts, falsify statements, or conceal evidence. Transparency with supervisors is mandatory.',
    '1) Disclose gifts, secondary jobs, or relationships that may affect duty.
2) Accurately record actions and evidence.
3) Refuse preferential treatment requests; report attempts.
4) Immediately report corruption or integrity concerns.',
    'Misrepresentation in reports or testimony is grounds for discipline.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Traffic Stop Procedures', 'Patrol Operations',
    'Provide safe, consistent approach to vehicle stops.',
    'Stops are conducted with clear identification, radio updates, and adherence to officer safety and constitutional limits.',
    '1) Radio location, plate, occupants if known.
2) Position patrol car safely; activate lights and camera.
3) Approach cautiously, identify yourself, and state reason.
4) Check warrants and documents; take action within policy.
5) Conclude with clear instructions and documentation.',
    'Use two-officer approach when available on high-risk indicators.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Pedestrian Stops', 'Patrol Operations',
    'Guide contact with pedestrians while respecting constitutional rights.',
    'Officers must have reasonable suspicion for detentions and articulate the reason and duration.',
    '1) Observe and form reasonable suspicion before detaining.
2) Identify yourself and the reason for the stop.
3) Conduct frisk only when articulable safety concerns exist.
4) Release promptly when suspicion is dispelled; document the stop.',
    'Voluntary contacts remain consensual and may be ended by the subject.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Field Interviews', 'Patrol Operations',
    'Standardize collection of information during investigative contacts.',
    'Interviews are voluntary unless detained; officers must note demeanor, statements, and conditions.',
    '1) Confirm whether the contact is voluntary or detained.
2) Ask concise questions tied to the observed activity.
3) Record identifiers and statements accurately.
4) Enter FI data into approved system before end of shift.',
    'Parents/guardians should be notified when interviewing juveniles when practical.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Arrest Procedures', 'Patrol Operations',
    'Ensure arrests are lawful, safe, and documented.',
    'Probable cause is required; force and restraints follow policy; arrestees are advised of rights when interrogated.',
    '1) Confirm probable cause and articulate elements.
2) Handcuff, search, and secure weapons/evidence.
3) Advise Miranda when questioning post-custody.
4) Transport safely; complete booking paperwork and reports.',
    'Medical clearance required if injury or complaint of pain.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Prisoner Transport', 'Patrol Operations',
    'Provide safe, humane transport of persons in custody.',
    'Vehicles are searched before/after transport; prisoners seat-belted and monitored.',
    '1) Search prisoner and vehicle prior to loading.
2) Seat-belt and position to reduce risk of assault or escape.
3) Monitor during transport; advise dispatch of start/end mileage when policy requires.
4) Transfer custody with documentation and property inventory.',
    'Opposite-sex transports require radio log and notification when possible.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Report Writing Standards', 'Patrol Operations',
    'Maintain clear, timely, and accurate reports.',
    'Reports must be objective, completed before end of shift unless approved extension, and include evidence references.',
    '1) Use clear chronology and separate observations from statements.
2) Include elements of offenses and probable cause.
3) Reference body cam identifiers and evidence numbers.
4) Submit for supervisory review when required.',
    'Proofread for spelling, dates, and identifiers before submission.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Use of Force Continuum', 'Use of Force',
    'Explain proportional response options and expectations.',
    'Force must be reasonable, necessary, and proportional to resistance, with de-escalation preferred when feasible.',
    '1) Assess threat, severity, and subject behavior.
2) Attempt verbal de-escalation when safe.
3) Use lowest effective option; escalate only as needed.
4) Render aid after force and notify supervisor immediately.
5) Document and report per force reporting policy.',
    'Early communication reduces need for higher force options.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Firearm Discharge Policy', 'Use of Force',
    'Define when intentional firearm discharge is authorized.',
    'Firearm use is restricted to defense of life or to stop serious bodily harm; warning shots are prohibited.',
    '1) Point only when deadly force conditions may exist.
2) Consider backdrop and bystanders before firing.
3) Notify supervisor and secure scene after discharge.
4) Provide medical aid and preserve evidence.
5) Complete required reports and submit firearm for inspection.',
    'Accidental discharges require immediate notification and review.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Less-Lethal Weapons', 'Use of Force',
    'Set guidance for tasers, beanbag, OC, and similar tools.',
    'Less-lethal options are used when reasonably necessary to gain compliance and when benefits outweigh risks.',
    '1) Assess subject factors (age, health indicators, environment).
2) Provide warnings when practical.
3) Avoid sensitive areas (head, spine) unless deadly force would be justified.
4) After use, handcuff, monitor, and arrange medical evaluation.
5) Document cartridge numbers or munitions used.',
    'Remove probes per medical protocol; photograph impacts.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Duty to Intervene', 'Use of Force',
    'Ensure officers act to stop unlawful or excessive force.',
    'Officers must intervene and report when observing unreasonable force or misconduct regardless of rank.',
    '1) Verbally direct the involved officer to stop.
2) Physically intervene if verbal direction fails and safe.
3) Render aid to affected persons.
4) Notify supervisor immediately and document incident.',
    'Retaliation for intervention or reporting is prohibited.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Use of Deadly Force', 'Use of Force',
    'Clarify deadly force threshold and responsibilities.',
    'Deadly force is authorized only to protect life from imminent threat of death or serious injury and must cease once threat ends.',
    '1) Confirm imminent threat; consider background and crossfire.
2) Issue commands when feasible.
3) Fire controlled rounds; reassess after each volley.
4) Provide medical aid and secure scene.
5) Notify command and cooperate with review.',
    'Vehicle ramming is deadly force and follows same standard.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Priority Call Handling', 'Emergency Response',
    'Standardize response to high-priority incidents.',
    'Response level matches call priority; supervisors may downgrade or upgrade based on conditions.',
    '1) Monitor dispatch details and location.
2) Acknowledge en route with unit status.
3) Use lights/siren per driving policy when responding code.
4) Stage when appropriate and wait for cover.
5) Update dispatch with arrival, actions, and clearance.',
    'Self-dispatching to high-priority calls requires notification.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Active Shooter Response', 'Emergency Response',
    'Provide immediate action steps to stop ongoing deadly threats.',
    'Primary mission is to stop the threat; officers form contact teams and move to gunfire when safe to do so.',
    '1) Arrive, assess, and move toward threat with minimum team.
2) Bypass wounded until threat stopped; relay locations.
3) Establish contact and rescue teams; coordinate with dispatch.
4) Transition to perimeter and handoff to investigative units.',
    'Unified command with fire/EMS once scene stabilizes.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Officer Down Response', 'Emergency Response',
    'Guide coordinated response to injured officers.',
    'Closest units respond code; command establishes rescue plan, perimeter, and medical access.',
    '1) Broadcast location, suspect info, and needs.
2) Form rescue team; move with cover to recover officer.
3) Provide immediate medical care and evacuate to EMS.
4) Secure scene for investigation and peer support.',
    'Notify command staff as soon as practicable.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'High-Risk Felony Stops', 'Emergency Response',
    'Ensure controlled stops of high-risk vehicles.',
    'Use multiple units, clear commands, and cover positions; occupants removed one at a time.',
    '1) Coordinate location with cover units.
2) Position vehicles for cover and containment.
3) Issue PA commands; remove and secure occupants sequentially.
4) Clear vehicle before approach.
5) Document and tow per policy when needed.',
    'Consider K-9 or air support when available.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Barricaded Suspects', 'Emergency Response',
    'Outline containment and negotiation for barricades.',
    'Priority is preservation of life; slow, controlled response with negotiators and specialty units as needed.',
    '1) Establish perimeter and inner/outer containment.
2) Evacuate exposed civilians and isolate suspect.
3) Gather intel (weapons, mental health, layout).
4) Request negotiators/SWAT early when indicators present.
5) Document timeline and decisions for after-action.',
    'Do not force entry unless exigency or authorized tactical plan.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Patrol Vehicle Operation', 'Vehicle Operations',
    'Promote safe, professional driving in marked and unmarked units.',
    'Seatbelts are mandatory; mobile data use limited to stopped or voice-directed use when safe.',
    '1) Conduct vehicle inspection at shift start.
2) Obey traffic laws when not in emergency mode.
3) Avoid prolonged in-vehicle computer use while moving.
4) Report collisions immediately and photograph damage.',
    'Fatigue driving should be reported for relief when possible.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Pursuit Policy', 'Vehicle Operations',
    'Define when to initiate, continue, or terminate pursuits.',
    'Pursuits are limited to violent felonies or imminent threats; risk to public must be continuously evaluated.',
    '1) Announce location, direction, speed, and reason when initiating.
2) Supervisor assumes control and may terminate at any time.
3) Limit number of pursuing units per policy.
4) Disengage when risk outweighs need for immediate capture.
5) Complete pursuit report after termination.',
    'Aerial support may allow reduced ground pressure.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Code 3 Driving', 'Vehicle Operations',
    'Set rules for lights-and-siren responses.',
    'Code 3 is authorized only for emergencies; due regard for safety is required at all times.',
    '1) Activate lights and siren before entering intersections.
2) Slow and clear all red lights/stop signs.
3) Notify dispatch of response level changes.
4) Reduce speed in adverse weather or dense areas.',
    'Cancel Code 3 when scene stabilized or downgraded.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'PIT Maneuver Authorization', 'Vehicle Operations',
    'Govern use of Precision Immobilization Technique.',
    'PIT is a form of force and may be used when risks of continued flight outweigh maneuver risks and when trained officers execute.',
    '1) Obtain supervisor approval when practicable.
2) Assess speed, environment, and vehicle type.
3) Execute within trained speed thresholds.
4) Coordinate with secondary units for containment.
5) Provide medical check for occupants post-PIT.',
    'Avoid PIT on motorcycles, high centers of gravity, or hazardous cargo unless deadly force justified.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Air Support Coordination', 'Vehicle Operations',
    'Leverage aviation assets to improve safety.',
    'Air support is requested through dispatch or supervisor; ground units adjust tactics when air has visual.',
    '1) Provide clear location, suspect description, and hazards.
2) Yield primary following role to air unit when overhead.
3) Use directed tactics (covert follow, perimeter guidance).
4) Maintain comms discipline on assigned channel.',
    'Cancel ground pursuits when air can track safely when policy allows.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Crime Scene Management', 'Investigations',
    'Protect scenes to preserve evidence and safety.',
    'Officers establish inner/outer perimeters, log entry, and prevent unnecessary contamination.',
    '1) Render aid and neutralize threats first.
2) Establish tape and a single entry point.
3) Start scene log and note initial conditions.
4) Await investigators; do not move evidence unless necessary.
5) Brief investigators with observations and actions taken.',
    'Weather or crowds may justify rapid evidence protection measures.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Evidence Collection and Handling', 'Investigations',
    'Ensure evidence is lawfully collected, packaged, and tracked.',
    'Chain of custody must be maintained with accurate labeling and submission.',
    '1) Photograph evidence in place when safe.
2) Use gloves and appropriate packaging for item type.
3) Label with case number, location, collector, date/time.
4) Complete evidence entry and submit to property promptly.',
    'Biological and digital evidence require special handling protocols.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Search and Seizure', 'Investigations',
    'Guide lawful searches respecting constitutional limits.',
    'Searches require warrant, consent, exigency, or other lawful exception; scope limited to justification.',
    '1) Determine legal basis and document it.
2) Obtain written or recorded consent when applicable.
3) Limit search to areas authorized; stop when scope met.
4) Inventory seized items and provide receipts when required.',
    'Consult supervisor or legal advisor for complex searches.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Warrants and Affidavits', 'Investigations',
    'Standardize preparation and execution of warrants.',
    'Affidavits must be truthful, complete, and reviewed; execution follows knock-notice rules unless lawful exception.',
    '1) Draft affidavit with probable cause and nexus clearly stated.
2) Obtain supervisory and prosecutorial review when required.
3) Brief team on layout, risks, and roles.
4) Execute warrant safely; record times and inventory items seized.',
    'Return warrant and inventory to issuing authority promptly.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Interview and Interrogation', 'Investigations',
    'Provide lawful, ethical questioning standards.',
    'Miranda advisement is given when required; coercion, promises, or threats are prohibited.',
    '1) Determine custody status and need for Miranda.
2) Record interviews when policy allows.
3) Ask open-ended questions; avoid leading promises.
4) Document verbatim statements when significant.',
    'Provide breaks and basic needs to maintain voluntariness.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'SWAT Deployment', 'Specialized Units',
    'Define when to request tactical team support.',
    'SWAT is activated for high-risk operations exceeding patrol capabilities and requires command approval.',
    '1) Identify high-risk factors (weapons, fortification, hostages).
2) Notify supervisor and command with facts.
3) Preserve perimeter and gather intel until team arrives.
4) Support unified command post once deployed.',
    'Do not self-deploy into inner perimeter without assignment.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'K-9 Deployment', 'Specialized Units',
    'Set safe, lawful use of police canines.',
    'Handlers control deployment; bites require medical care and reporting; announcements made when required.',
    '1) Assess necessity (flight, hiding suspects, evidence search).
2) Give loud announcement before apprehension deployments when practical.
3) Maintain leash control unless directed otherwise.
4) Provide medical aid after contact and document deployment.',
    'Avoid K-9 deployment on passive crowds or for mere non-compliance.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Traffic Enforcement Operations', 'Specialized Units',
    'Coordinate planned traffic safety details.',
    'Operations focus on safety violations; citations and arrests follow standard procedures with data collection.',
    '1) Brief team on location, goals, and legal considerations.
2) Use visible markings and cones when safe.
3) Track stops, warnings, and citations issued.
4) Debrief results and adjust tactics for future ops.',
    'Coordinate with media or community outreach when appropriate.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Narcotics Operations', 'Specialized Units',
    'Provide safeguards for undercover and narcotics enforcement.',
    'Operations require supervisor approval, risk assessment, and adherence to informant handling rules.',
    '1) Complete operational plan with objectives and contingencies.
2) Vet and document informant use.
3) Maintain surveillance teams and arrest contingencies.
4) Preserve evidence chain and submit for lab promptly.',
    'Avoid buy/bust without cover and surveillance teams.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Complaint Handling', 'Internal Affairs',
    'Ensure public and internal complaints are recorded and investigated.',
    'All complaints are accepted without delay; retaliation is prohibited; documentation is mandatory.',
    '1) Accept complaint in any form; provide reference number.
2) Notify supervisor and IA channel per policy.
3) Preserve any evidence (video, documents).
4) Provide status updates through established process.',
    'Anonymous complaints are documented and assessed equally.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Use of Force Review', 'Internal Affairs',
    'Standardize administrative review of force incidents.',
    'Every reportable force event is reviewed for policy compliance by supervision and, when required, IA.',
    '1) Officer submits force report and uploads media before end of shift when feasible.
2) Supervisor conducts interview and scene review.
3) Forward package to IA/command for final determination.
4) Track corrective actions or training needs.',
    'Serious force may trigger parallel criminal and admin reviews.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Officer Involved Incidents', 'Internal Affairs',
    'Outline response to shootings, serious collisions, or critical events involving officers.',
    'Involved officers are separated, statements managed per legal and contractual requirements, and support services offered.',
    '1) Secure scene and evidence; assign investigators.
2) Separate involved and witness officers; assign peers.
3) Provide medical and wellness resources.
4) Follow critical incident protocol for interviews and relief from duty.',
    'Union/employee rights are honored per agreements and law.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Internal Investigations', 'Internal Affairs',
    'Ensure fair, thorough investigations of misconduct.',
    'Investigations are objective, timely, and documented; subjects are notified consistent with policy.',
    '1) Assign investigator and scope; secure evidence.
2) Interview complainant, witnesses, and subject officer.
3) Analyze policy compliance and document findings.
4) Present findings to command for disposition.',
    'Maintain confidentiality and protect against retaliation.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Field Training Program', 'Training',
    'Define structure for training new officers.',
    'FTOs follow approved curriculum, document daily performance, and provide timely feedback.',
    '1) Orient trainee to equipment, policy, and expectations.
2) Use daily observation reports with specific examples.
3) Conduct mid-phase and end-phase evaluations.
4) Recommend advancement, extension, or remediation with justification.',
    'FTO changes require supervisor approval.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Probationary Officer Standards', 'Training',
    'Set expectations for probationary performance and milestones.',
    'Probationers must meet training benchmarks, policy compliance, and attendance requirements.',
    '1) Provide probation schedule and required competencies.
2) Meet regularly with supervisor and FTO for feedback.
3) Address deficiencies with written improvement plans.
4) Document completion or extension decisions in writing.',
    'Failure to meet standards may result in separation.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Remedial Training', 'Training',
    'Offer structured remediation for identified performance gaps.',
    'Supervisors may assign remedial training to address deficiencies before discipline when appropriate.',
    '1) Identify specific deficiency and desired outcome.
2) Assign targeted training or mentoring with timeline.
3) Document completion and evaluate improvement.
4) Escalate if performance does not improve.',
    'Serious misconduct may bypass remediation steps.', 'System Seed', NOW(), NOW()
  UNION ALL SELECT 'Firearms Qualification', 'Training',
    'Ensure officers maintain firearms proficiency and safety.',
    'All sworn personnel must qualify on issued weapons at required intervals; failure triggers remediation.',
    '1) Attend scheduled qualification sessions.
2) Follow range safety rules and instructor commands.
3) Log scores and any malfunctions.
4) Complete remedial sessions until qualified or relieved of duty weapons.',
    'Document alternative duty status if qualification is not met.', 'System Seed', NOW(), NOW()
) AS `seed`
WHERE NOT EXISTS (SELECT 1 FROM `pf_mdt_sops` LIMIT 1);

-- ============================================================================
-- FTO REPORTS v2 (Draft/Submit/Review)
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_fto_reports` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `report_uid` VARCHAR(16) NOT NULL,
  `status` ENUM('DRAFT','SUBMITTED','APPROVED','REJECTED') NOT NULL DEFAULT 'DRAFT',

  `trainee_cid` VARCHAR(50) NOT NULL,
  `trainee_name` VARCHAR(100) NOT NULL,
  `trainee_callsign` VARCHAR(50) DEFAULT NULL,

  `author_cid` VARCHAR(50) NOT NULL,
  `author_name` VARCHAR(100) NOT NULL,

  `phase` INT NOT NULL DEFAULT 1,
  `shift` ENUM('Morning','Evening','Night') NOT NULL DEFAULT 'Morning',
  `ride_date` DATETIME NOT NULL,

  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `submitted_at` DATETIME DEFAULT NULL,

  `reviewed_by_cid` VARCHAR(50) DEFAULT NULL,
  `reviewed_by_name` VARCHAR(100) DEFAULT NULL,
  `reviewed_at` DATETIME DEFAULT NULL,
  `review_note` TEXT DEFAULT NULL,

  `ride_description` LONGTEXT DEFAULT NULL,
  `overall_rating` DECIMAL(3,1) DEFAULT NULL,

  `safety_concern` TINYINT(1) NOT NULL DEFAULT 0,
  `safety_concern_notes` TEXT DEFAULT NULL,

  `recommendation` ENUM('ADVANCE','REMAIN','REMEDIAL','TERMINATION') DEFAULT NULL,

  `strengths` TEXT DEFAULT NULL,
  `improvements` TEXT DEFAULT NULL,

  `evaluation_json` LONGTEXT NOT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_report_uid` (`report_uid`),
  KEY `idx_status` (`status`),
  KEY `idx_trainee` (`trainee_cid`),
  KEY `idx_author` (`author_cid`),
  KEY `idx_dates` (`ride_date`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================================
-- BULLETINS (Dashboard)
-- =========================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_bulletins` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(255) NOT NULL,
  `body` LONGTEXT NOT NULL,
  `createdByCitizenId` VARCHAR(64) NULL,
  `createdByName` VARCHAR(128) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_createdAt` (`createdAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_mdt_fto_report_audit` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `report_uid` VARCHAR(16) NOT NULL,
  `action` VARCHAR(32) NOT NULL,
  `actor_cid` VARCHAR(50) NOT NULL,
  `actor_name` VARCHAR(100) NOT NULL,
  `at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `details_json` LONGTEXT DEFAULT NULL,

  PRIMARY KEY (`id`),
  KEY `idx_report_uid` (`report_uid`),
  KEY `idx_action` (`action`),
  KEY `idx_at` (`at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- CITIZEN PROFILES - Notes, Flags & Profile Pictures
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_citizen_notes` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenId` VARCHAR(64) NOT NULL,
  `text` LONGTEXT NOT NULL,
  `author` VARCHAR(128) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_citizen` (`citizenId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_mdt_citizen_flags` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenId` VARCHAR(64) NOT NULL,
  `flag` VARCHAR(64) NOT NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_citizen` (`citizenId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_mdt_citizen_profiles` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenId` VARCHAR(64) NOT NULL UNIQUE,
  `profilePicture` VARCHAR(512) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_citizen` (`citizenId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =========================================================================
-- OFFICERS MANAGEMENT (HR) - Profiles / Discipline / Audit
-- NOTE: This is intentionally separate from `pf_mdt_officer_profiles`.
--       That table is used by the MDT UI for callsign/status/avatar.
-- =========================================================================

DROP TABLE IF EXISTS `pf_mdt_officer_mgmt_profiles`;
CREATE TABLE `pf_mdt_officer_mgmt_profiles` (
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
  PRIMARY KEY (`citizenid`),
  KEY `idx_officer_terminated` (`terminated`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS `pf_mdt_officer_discipline`;
CREATE TABLE `pf_mdt_officer_discipline` (
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

DROP TABLE IF EXISTS `pf_mdt_officer_audit`;
CREATE TABLE `pf_mdt_officer_audit` (
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
-- Weapons registry
CREATE TABLE IF NOT EXISTS `pf_mdt_weapons_registry` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `serial` VARCHAR(64) NOT NULL,
  `weapon` VARCHAR(64) NOT NULL,
  `weaponLabel` VARCHAR(128) NULL,
  `ownerCitizenId` VARCHAR(64) NOT NULL,
  `ownerName` VARCHAR(128) NULL,
  `registeredAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `registeredByCitizenId` VARCHAR(64) NULL,
  `registeredByName` VARCHAR(128) NULL,
  `notes` TEXT NULL,
  `stolen_status` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_serial` (`serial`),
  KEY `idx_owner` (`ownerCitizenId`),
  KEY `idx_registered_at` (`registeredAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- OFFICER PROFILES - Callsign, Status, Avatar (Persistent)
-- ============================================================================
DROP TABLE IF EXISTS `pf_mdt_officer_profiles`;
CREATE TABLE `pf_mdt_officer_profiles` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenId` VARCHAR(64) NOT NULL UNIQUE,
  `callsign` VARCHAR(32) NULL,
  `status` VARCHAR(16) NULL,
  `avatarUrl` VARCHAR(512) NULL,
  `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_officer_citizen` (`citizenId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- VEHICLE PROFILES - Notes, Flags, Strikes & Activity
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_notes` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `text` LONGTEXT NOT NULL,
  `author` VARCHAR(128) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_flags` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `flag` VARCHAR(64) NOT NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_strikes` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `offenseType` VARCHAR(64) NOT NULL,
  `points` INT NOT NULL DEFAULT 4,
  `description` TEXT NULL,
  `officer` VARCHAR(128) NOT NULL,
  `location` VARCHAR(255) NULL,
  `status` ENUM('active', 'expired', 'dismissed') NOT NULL DEFAULT 'active',
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expiresAt` DATETIME NULL,
  `createdByName` VARCHAR(128) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_activity` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `timestamp` DATETIME NULL,
  `location` VARCHAR(255) NULL,
  `officer` VARCHAR(128) NULL,
  `officerName` VARCHAR(128) NULL,
  `referenceId` VARCHAR(64) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`),
  KEY `idx_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pf_mdt_charges` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `code` VARCHAR(16) NOT NULL UNIQUE,
  `name` VARCHAR(128) NOT NULL,
  `description` LONGTEXT NULL,
  `fineAmount` INT NOT NULL DEFAULT 0,
  `bailAmount` INT NOT NULL DEFAULT 0,
  `prisonTime` INT NOT NULL DEFAULT 0,
  `category` VARCHAR(64) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_code` (`code`),
  KEY `idx_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================================
-- SENTENCES - Citizen sentencing history
-- =========================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_sentences` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenId` VARCHAR(64) NOT NULL,
  `citizenName` VARCHAR(128) NULL,

  `officerCitizenId` VARCHAR(64) NULL,
  `officerName` VARCHAR(128) NULL,

  `title` VARCHAR(255) NOT NULL,
  `description` LONGTEXT NULL,
  `sentenceType` VARCHAR(24) NOT NULL,

  `charges` LONGTEXT NULL,
  `reductions` LONGTEXT NULL,

  `fineAmount` INT NOT NULL DEFAULT 0,
  `prisonTime` INT NOT NULL DEFAULT 0,
  `prisonTimeBeforeReduction` INT NOT NULL DEFAULT 0,
  `prisonTimeAfterReduction` INT NOT NULL DEFAULT 0,
  `reductionPercent` INT NOT NULL DEFAULT 0,

  `executed` TINYINT(1) NOT NULL DEFAULT 0,
  `fineSuccess` TINYINT(1) NOT NULL DEFAULT 0,
  `jailSuccess` TINYINT(1) NOT NULL DEFAULT 0,
  `error` TEXT NULL,

  `bailAmount` INT NOT NULL DEFAULT 0,
  `bailed` TINYINT(1) NOT NULL DEFAULT 0,
  `bailPaidByCitizenId` VARCHAR(64) NULL,
  `bailPaidByName` VARCHAR(128) NULL,
  `bailPaidAt` DATETIME NULL,

  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_citizen` (`citizenId`),
  KEY `idx_createdAt` (`createdAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================================
-- PENDING SENTENCES - Offline rcore_prison queue
-- =========================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_pending_sentences` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(64) NOT NULL,
  `minutes` INT NOT NULL DEFAULT 0,
  `reason` VARCHAR(255) NULL,
  `officer_citizenid` VARCHAR(64) NULL,
  `officer_name` VARCHAR(128) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_citizenid` (`citizenid`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  -- =========================================================================
  -- MIGRATION: Sentences bail columns
  -- =========================================================================
  SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'pf_mdt_sentences'
    AND COLUMN_NAME = 'bailAmount');
  SET @sqlstmt := IF(@exist > 0, 'SELECT ''sentences.bailAmount already exists.''',
    'ALTER TABLE `pf_mdt_sentences` ADD COLUMN `bailAmount` INT NOT NULL DEFAULT 0 AFTER `error`');
  PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

  SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'pf_mdt_sentences'
    AND COLUMN_NAME = 'bailed');
  SET @sqlstmt := IF(@exist > 0, 'SELECT ''sentences.bailed already exists.''',
    'ALTER TABLE `pf_mdt_sentences` ADD COLUMN `bailed` TINYINT(1) NOT NULL DEFAULT 0 AFTER `bailAmount`');
  PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

  SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'pf_mdt_sentences'
    AND COLUMN_NAME = 'bailPaidByCitizenId');
  SET @sqlstmt := IF(@exist > 0, 'SELECT ''sentences.bailPaidByCitizenId already exists.''',
    'ALTER TABLE `pf_mdt_sentences` ADD COLUMN `bailPaidByCitizenId` VARCHAR(64) NULL AFTER `bailed`');
  PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

  SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'pf_mdt_sentences'
    AND COLUMN_NAME = 'bailPaidByName');
  SET @sqlstmt := IF(@exist > 0, 'SELECT ''sentences.bailPaidByName already exists.''',
    'ALTER TABLE `pf_mdt_sentences` ADD COLUMN `bailPaidByName` VARCHAR(128) NULL AFTER `bailPaidByCitizenId`');
  PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

  SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'pf_mdt_sentences'
    AND COLUMN_NAME = 'bailPaidAt');
  SET @sqlstmt := IF(@exist > 0, 'SELECT ''sentences.bailPaidAt already exists.''',
    'ALTER TABLE `pf_mdt_sentences` ADD COLUMN `bailPaidAt` DATETIME NULL AFTER `bailPaidByName`');
  PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;
-- ============================================================================
-- MIGRATION: Add description column to charges if missing
-- ============================================================================
SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_charges' 
    AND COLUMN_NAME = 'description');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''description column already exists.''', 
    'ALTER TABLE `pf_mdt_charges` ADD COLUMN `description` LONGTEXT NULL AFTER `name`');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================================================
-- MIGRATION: Add status column if it doesn't exist (separate from approvalStatus)
-- ============================================================================
SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_reports' 
    AND COLUMN_NAME = 'status');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''status column already exists.''', 
    'ALTER TABLE `pf_mdt_reports` ADD COLUMN `status` VARCHAR(16) NOT NULL DEFAULT ''pending'' AFTER `approvalStatus`');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- =========================================================================
-- MIGRATION: Add officer column to reports if missing
-- =========================================================================
SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'pf_mdt_reports'
  AND COLUMN_NAME = 'officer');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''officer column already exists.''',
  'ALTER TABLE `pf_mdt_reports` ADD COLUMN `officer` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `title`');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================================================
-- MIGRATION: Add warrant title/officers/witnesses columns
-- ============================================================================
SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
  WHERE TABLE_SCHEMA = DATABASE() 
  AND TABLE_NAME = 'pf_mdt_warrants' 
  AND COLUMN_NAME = 'officers');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''warrant officers column already exists.''', 
  'ALTER TABLE `pf_mdt_warrants` ADD COLUMN `officers` LONGTEXT NULL AFTER `charges`');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
  WHERE TABLE_SCHEMA = DATABASE() 
  AND TABLE_NAME = 'pf_mdt_warrants' 
  AND COLUMN_NAME = 'witnesses');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''warrant witnesses column already exists.''', 
  'ALTER TABLE `pf_mdt_warrants` ADD COLUMN `witnesses` LONGTEXT NULL AFTER `officers`');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
  WHERE TABLE_SCHEMA = DATABASE() 
  AND TABLE_NAME = 'pf_mdt_warrants' 
  AND COLUMN_NAME = 'title');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''warrant title column already exists.''', 
  'ALTER TABLE `pf_mdt_warrants` ADD COLUMN `title` VARCHAR(255) NULL AFTER `issuedBy`');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================================================
-- MIGRATION: Add incident involved fields and reporting/timestamp
-- ============================================================================
SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_incidents' 
    AND COLUMN_NAME = 'reportingOfficer');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''reportingOfficer column already exists.''', 
    'ALTER TABLE `pf_mdt_incidents` 
        ADD COLUMN `reportingOfficer` VARCHAR(128) NULL AFTER `status`;');
PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_incidents' 
    AND COLUMN_NAME = 'involvedCitizens');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''involvedCitizens column already exists.''', 
    'ALTER TABLE `pf_mdt_incidents` 
        ADD COLUMN `involvedCitizens` LONGTEXT NULL AFTER `reportingOfficer`;');
PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_incidents' 
    AND COLUMN_NAME = 'involvedOfficers');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''involvedOfficers column already exists.''', 
    'ALTER TABLE `pf_mdt_incidents` 
        ADD COLUMN `involvedOfficers` LONGTEXT NULL AFTER `involvedCitizens`;');
PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_incidents' 
    AND COLUMN_NAME = 'involvedCitizenIds');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''involvedCitizenIds column already exists.''', 
    'ALTER TABLE `pf_mdt_incidents` 
        ADD COLUMN `involvedCitizenIds` LONGTEXT NULL AFTER `involvedOfficers`;');
PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_incidents' 
    AND COLUMN_NAME = 'involvedOfficerIds');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''involvedOfficerIds column already exists.''', 
    'ALTER TABLE `pf_mdt_incidents` 
        ADD COLUMN `involvedOfficerIds` LONGTEXT NULL AFTER `involvedCitizenIds`;');
PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = DATABASE() 
    AND TABLE_NAME = 'pf_mdt_incidents' 
    AND COLUMN_NAME = 'dateTime');
SET @sqlstmt := IF(@exist > 0, 'SELECT ''dateTime column already exists.''', 
    'ALTER TABLE `pf_mdt_incidents` 
        ADD COLUMN `dateTime` DATETIME NULL AFTER `involvedOfficerIds`;');
PREPARE stmt FROM @sqlstmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ============================================================================
-- SEED DEFAULT CHARGES
-- ============================================================================
INSERT IGNORE INTO `pf_mdt_charges` (`code`, `name`, `description`, `fineAmount`, `bailAmount`, `prisonTime`, `category`) VALUES
-- VIOLENT CRIMES
('PC-187', 'Murder', 'Unlawful killing of a human being', 50000, 100000, 240, 'Violent'),
('PC-191', 'Manslaughter', 'Unlawful killing without malice aforethought', 20000, 50000, 120, 'Violent'),
('PC-245', 'Assault with Deadly Weapon', 'Assault with deadly weapon or force', 10000, 25000, 60, 'Violent'),
('PC-242', 'Assault', 'Intentional application of force against another', 2000, 5000, 6, 'Violent'),
('PC-243', 'Battery', 'Willful and unlawful touching of another', 2000, 5000, 6, 'Violent'),
('PC-261', 'Rape', 'Non-consensual sexual intercourse', 60000, 120000, 300, 'Violent'),
('PC-262', 'Rape of Spouse', 'Non-consensual sexual intercourse with spouse', 40000, 80000, 240, 'Violent'),
('PC-264', 'Indecent Exposure', 'Exposure of genitals with intent to offend', 1000, 2500, 12, 'Violent'),
('PC-207', 'Kidnapping', 'Unlawful restraint or taking of person', 40000, 80000, 180, 'Violent'),
('PC-208', 'Child Abduction', 'Taking of minor without consent', 35000, 75000, 150, 'Violent'),
('PC-219', 'Torture', 'Infliction of extreme pain with intent to cause injury', 50000, 100000, 240, 'Violent'),
('PC-273', 'Child Abuse', 'Willful cruelty or endangerment of child', 15000, 35000, 90, 'Violent'),
('PC-273.5', 'Domestic Violence', 'Willful infliction of corporal injury on intimate partner', 10000, 25000, 48, 'Violent'),
('PC-415', 'Disturbing the Peace', 'Fighting, loud/unreasonable noise, abusive language', 250, 500, 0, 'Violent'),
('PC-417', 'Drawing or Exhibiting a Firearm', 'Drawing or exhibiting firearm in rude or threatening manner', 5000, 12000, 30, 'Violent'),

-- PROPERTY CRIMES
('PC-459', 'Burglary', 'Unlawful entry with intent to commit felony', 15000, 35000, 120, 'Property'),
('PC-459.5', 'Vehicle Burglary', 'Unlawful entry into vehicle with intent to steal', 8000, 20000, 60, 'Property'),
('PC-484', 'Theft', 'Unlawful taking of personal property', 8000, 15000, 60, 'Property'),
('PC-487', 'Grand Theft', 'Theft of property worth $950 or more', 12000, 30000, 90, 'Property'),
('PC-488', 'Petty Theft', 'Theft of property worth less than $950', 2000, 5000, 12, 'Property'),
('PC-496', 'Receiving Stolen Property', 'Knowingly receiving stolen goods', 7000, 14000, 45, 'Property'),
('PC-503', 'Embezzlement', 'Fraudulent appropriation of another property', 10000, 25000, 60, 'Property'),
('PC-530.5', 'Identity Theft', 'Unauthorized use of identity', 5000, 12000, 30, 'Property'),
('PC-537', 'Fraudulent Sale of Real Property', 'Fraudulent transfer of real estate', 20000, 50000, 120, 'Property'),
('PC-666', 'Shoplifting', 'Theft from retail establishment', 2000, 4000, 15, 'Property'),
('PC-484F', 'Theft by Bad Check', 'Writing check knowing insufficient funds', 3000, 8000, 20, 'Property'),
('PC-518', 'Extortion', 'Obtaining property by threat or coercion', 15000, 35000, 90, 'Property'),
('PC-550', 'Insurance Fraud', 'Fraudulent insurance claim', 10000, 25000, 60, 'Property'),

-- TRAFFIC VIOLATIONS
('VC-10001', 'Speeding', 'Exceeding posted speed limit', 500, 1000, 0, 'Traffic'),
('VC-10002', 'Reckless Driving', 'Operating vehicle with wanton disregard', 2000, 5000, 15, 'Traffic'),
('VC-10003', 'Driving Under the Influence', 'Operating vehicle while intoxicated', 5000, 15000, 30, 'Traffic'),
('VC-10004', 'Driving with Suspended License', 'Operating vehicle without valid license', 3000, 8000, 20, 'Traffic'),
('VC-10005', 'Failure to Stop at Red Light', 'Running red light or stop sign', 350, 500, 0, 'Traffic'),
('VC-10006', 'Failure to Obey Traffic Control Device', 'Ignoring traffic signals or signs', 300, 500, 0, 'Traffic'),
('VC-10007', 'Illegal Parking', 'Parking in restricted area', 100, 200, 0, 'Traffic'),
('VC-480', 'Hit and Run - Property Damage', 'Leaving scene of accident with property damage', 5000, 12000, 30, 'Traffic'),
('VC-20001', 'Hit and Run - Injury', 'Leaving scene of accident with injury', 10000, 25000, 60, 'Traffic'),
('VC-14601', 'Driving Without a License', 'Operating vehicle without valid license', 2000, 5000, 15, 'Traffic'),
('VC-23152', 'DUI - First Offense', 'Driving under influence of alcohol/drugs', 5000, 15000, 30, 'Traffic'),
('VC-23153', 'DUI - Injury', 'DUI causing injury to another person', 15000, 35000, 90, 'Traffic'),

-- DRUG/NARCOTICS CRIMES
('HS-11350', 'Possession of Controlled Substance', 'Possession of illegal drugs', 3000, 8000, 30, 'Narcotics'),
('HS-11352', 'Transportation of Controlled Substance', 'Transport of illegal drugs', 20000, 50000, 120, 'Narcotics'),
('HS-11351', 'Possession for Sale', 'Possession of controlled substance with intent to sell', 15000, 35000, 90, 'Narcotics'),
('HS-11359', 'Possession of Marijuana for Sale', 'Possession of marijuana with intent to sell', 10000, 25000, 60, 'Narcotics'),
('HS-11360', 'Transportation of Marijuana', 'Transport of marijuana for sale', 12000, 30000, 75, 'Narcotics'),
('HS-11370', 'Sale of Controlled Substance Near School', 'Drug sales within 600 feet of school', 25000, 60000, 150, 'Narcotics'),
('HS-11377', 'Possession of Methamphetamine', 'Possession of crystal meth', 5000, 12000, 36, 'Narcotics'),

-- WEAPONS CRIMES
('PC-25400', 'Carrying Concealed Weapon', 'Carrying hidden firearm without permit', 3000, 7500, 20, 'Weapons'),
('PC-25850', 'Carrying Loaded Firearm', 'Carrying loaded firearm in public', 5000, 12000, 30, 'Weapons'),
('PC-26350', 'Carrying Unloaded Firearm', 'Carrying unloaded firearm in public', 2000, 5000, 15, 'Weapons'),
('PC-21510', 'Brandishing a Weapon', 'Brandishing knife or other dangerous weapon', 4000, 10000, 25, 'Weapons'),
('PC-182', 'Criminal Conspiracy', 'Conspiracy to commit crime', 15000, 35000, 90, 'General'),
('PC-211', 'Robbery', 'Taking property by force or threat', 20000, 50000, 150, 'Violent'),
('PC-212.5', 'Aggravated Assault', 'Assault on peace officer or elder', 15000, 35000, 90, 'Violent'),
('PC-664', 'Attempted Felony', 'Attempted commission of felony', 10000, 25000, 60, 'General'),
('PC-270', 'Jail Break', 'Escape from custody', 25000, 60000, 180, 'Police'),
('PC-148', 'Resisting Arrest', 'Resisting or obstructing police officer', 5000, 10000, 30, 'Police'),
('PC-149', 'Assault on Officer', 'Assault on peace officer performing duties', 8000, 20000, 45, 'Police'),
('PC-187.5', 'Killing a Police Officer', 'Murder of peace officer in performance of duty', 100000, 200000, 360, 'Violent'),
('PC-266', 'Pimping and Pandering', 'Profiting from prostitution', 8000, 20000, 45, 'General'),
('PC-314', 'Indecent Exposure', 'Exposing genitals in reckless manner', 1000, 2500, 12, 'General'),
('PC-381', 'Threatening Public Safety', 'Threats to public safety or infrastructure', 5000, 12000, 30, 'General'),
('PC-384', 'Loitering for Drug Purposes', 'Loitering with intent to sell drugs', 3000, 8000, 20, 'Narcotics'),
('PC-459.5', 'Commercial Burglary', 'Burglary of business establishment', 12000, 30000, 90, 'Property'),
('PC-484H', 'Theft of Vehicle', 'Stealing a motor vehicle', 10000, 25000, 60, 'Property');

-- =========================================================================
-- BACKFILL: Ensure every charge has a description
-- - If a charge exists with NULL/blank description, default it to its name.
-- - This helps Criminal Code and Charges lists always show text.
-- =========================================================================
UPDATE `pf_mdt_charges`
SET `description` = `name`
WHERE `description` IS NULL OR TRIM(`description`) = '';

-- =========================================================================
-- BACKFILL (DETAILED): Provide richer descriptions for default charges
-- - Safe to run on existing installs.
-- - Only updates rows where description is NULL/blank OR equals name
--   (i.e., our auto-backfill or an untouched row).
-- =========================================================================
UPDATE `pf_mdt_charges`
SET `description` = CASE `code`
  -- VIOLENT CRIMES
  WHEN 'PC-187' THEN 'Unlawful killing of a person with malice. Includes intentional killing or conduct showing extreme disregard for life.'
  WHEN 'PC-191' THEN 'Unlawful killing without malice. Typically reckless, negligent, or heat-of-passion killing that does not meet murder elements.'
  WHEN 'PC-245' THEN 'Assault using a deadly weapon or force likely to cause great bodily injury. Threats and actions must show an attempt to apply violent injury.'
  WHEN 'PC-242' THEN 'Attempted or threatened use of force against another person. No injury required; intent and act creating fear of immediate harm is sufficient.'
  WHEN 'PC-243' THEN 'Willful and unlawful touching or striking of another. Any harmful or offensive contact can qualify, even if injuries are minor.'
  WHEN 'PC-261' THEN 'Non-consensual sexual intercourse by force, threat, or when the victim cannot consent. Consent must be voluntary and informed.'
  WHEN 'PC-262' THEN 'Non-consensual sexual intercourse with a spouse by force, threat, or when the victim cannot consent. Marriage does not remove consent requirements.'
  WHEN 'PC-264' THEN 'Intentional exposure of genitals in a public place or in view of others, done to offend, harass, or gratify. Repeated conduct increases severity.'
  WHEN 'PC-207' THEN 'Taking, holding, or restraining a person by force or fear, moving them a substantial distance or preventing lawful freedom of movement.'
  WHEN 'PC-208' THEN 'Taking or concealing a minor from a parent or guardian without consent. Includes detaining a child and preventing lawful custody.'
  WHEN 'PC-219' THEN 'Intentional infliction of extreme and prolonged pain to cause cruel suffering or injury. Requires specific intent to torture.'
  WHEN 'PC-273' THEN 'Willfully causing or permitting a child to suffer, or placing a child in danger. Includes neglect, endangerment, and abusive conduct.'
  WHEN 'PC-273.5' THEN 'Willful infliction of physical injury on an intimate partner resulting in a traumatic condition. Includes domestic assaults causing injury.'
  WHEN 'PC-415' THEN 'Fighting, loud or unreasonable noise, or offensive words likely to provoke an immediate violent reaction in a public place.'
  WHEN 'PC-417' THEN 'Drawing, exhibiting, or brandishing a firearm in a rude, angry, or threatening manner, or using it in a fight.'

  -- PROPERTY CRIMES
  WHEN 'PC-459' THEN 'Unlawful entry into a building or structure with intent to commit theft or any felony. Intent must exist at the time of entry.'
  WHEN 'PC-459.5' THEN 'Unlawful entry into a vehicle or premises with intent to steal or commit a felony. Covers common burglary-style entries with criminal intent.'
  WHEN 'PC-484' THEN 'Taking property belonging to another without permission and with intent to permanently deprive the owner. Includes theft by trick or fraud.'
  WHEN 'PC-487' THEN 'Theft of property over the felony threshold. Typically higher-value items, vehicles, or repeated theft conduct.'
  WHEN 'PC-488' THEN 'Lower-value theft below the felony threshold. Still requires intent to deprive the owner of property rights.'
  WHEN 'PC-496' THEN 'Receiving, buying, or concealing property known to be stolen. Knowledge and control over the stolen items are key elements.'
  WHEN 'PC-503' THEN 'Fraudulent appropriation of property by a person entrusted with it. Misuse of entrusted funds or items qualifies.'
  WHEN 'PC-530.5' THEN 'Using another persons identifying information without permission to obtain goods, services, money, or other benefits.'
  WHEN 'PC-537' THEN 'Fraud involving transfer or sale of real property through deception or false pretenses. Includes forged documents or misrepresentation.'
  WHEN 'PC-666' THEN 'Shoplifting or theft from a retail business. Taking merchandise without paying, including concealment with intent to steal.'
  WHEN 'PC-484F' THEN 'Passing a check knowing there are insufficient funds or no account. Requires intent to defraud at the time of issuance.'
  WHEN 'PC-518' THEN 'Obtaining money or property through threats, coercion, or fear. Includes threats of harm, exposure, or force to compel payment.'
  WHEN 'PC-550' THEN 'Knowingly making a false insurance claim or materially misrepresenting facts to obtain insurance benefits.'
  WHEN 'PC-484H' THEN 'Taking a motor vehicle without permission with intent to deprive the owner. Includes unlawful vehicle theft and related conduct.'

  -- TRAFFIC VIOLATIONS
  WHEN 'VC-10001' THEN 'Driving above the posted speed limit or too fast for conditions. Includes unsafe speed in poor visibility or traffic.'
  WHEN 'VC-10002' THEN 'Operating a vehicle with willful or wanton disregard for safety. Includes aggressive maneuvers endangering others.'
  WHEN 'VC-10003' THEN 'Driving while impaired by alcohol or drugs. Impairment can be shown by behavior, tests, or observed unsafe driving.'
  WHEN 'VC-10004' THEN 'Operating a vehicle while your license is suspended, revoked, or otherwise invalid. Knowledge of invalid status may be required.'
  WHEN 'VC-10005' THEN 'Failing to stop at a steady red light or stop sign when required. Includes rolling through controlled intersections.'
  WHEN 'VC-10006' THEN 'Failing to comply with posted signs, signals, lane controls, or officer direction. Includes ignoring traffic control devices.'
  WHEN 'VC-10007' THEN 'Parking in a restricted area or in a manner prohibited by posted signs or local rules. Includes blocking driveways or lanes.'
  WHEN 'VC-480' THEN 'Leaving the scene of a vehicle collision involving property damage without providing information or rendering required assistance.'
  WHEN 'VC-20001' THEN 'Leaving the scene of a collision where someone is injured or killed without stopping and providing required information and aid.'
  WHEN 'VC-14601' THEN 'Driving without a valid license or driving privilege. Includes never licensed, expired, or otherwise unauthorized operation.'
  WHEN 'VC-23152' THEN 'Driving under the influence, first offense category. Applies when impairment affects driving ability even without injury.'
  WHEN 'VC-23153' THEN 'Driving under the influence causing injury to another person. Requires DUI plus causal connection to injury.'

  -- DRUG / NARCOTICS
  WHEN 'HS-11350' THEN 'Possessing a controlled substance without a valid prescription or authorization. Knowledge and control of the substance are required.'
  WHEN 'HS-11352' THEN 'Transporting, selling, or distributing a controlled substance. Includes moving drugs for sale or supply and related trafficking conduct.'
  WHEN 'HS-11351' THEN 'Possession of a controlled substance with intent to sell. Intent can be inferred from packaging, quantity, cash, or communications.'
  WHEN 'HS-11359' THEN 'Possession of marijuana with intent to sell or distribute. Evidence may include baggies, scales, ledgers, or large quantity.'
  WHEN 'HS-11360' THEN 'Transporting marijuana for sale or distribution. Includes moving product between locations as part of supply or sales activity.'
  WHEN 'HS-11370' THEN 'Selling or possessing for sale controlled substances near a school zone. Enhanced penalty due to protected area proximity.'
  WHEN 'HS-11377' THEN 'Possession of methamphetamine. Requires knowing possession and control of the substance.'

  -- WEAPONS / POLICE / GENERAL
  WHEN 'PC-25400' THEN 'Carrying a concealed firearm on your person or in a vehicle without proper authorization. Includes hidden handguns and similar weapons.'
  WHEN 'PC-25850' THEN 'Carrying a loaded firearm in a public place or vehicle when prohibited. Public safety risk increases severity.'
  WHEN 'PC-26350' THEN 'Carrying an unloaded firearm in a public place when prohibited. Applies even if the firearm is not loaded.'
  WHEN 'PC-21510' THEN 'Brandishing a knife or similar weapon in a threatening manner. Includes displaying to intimidate or during an altercation.'
  WHEN 'PC-182' THEN 'Agreement between two or more persons to commit a crime, plus an overt act in furtherance of the plan.'
  WHEN 'PC-211' THEN 'Taking property from a person or their immediate presence by force or fear. Threats or violence elevate the offense.'
  WHEN 'PC-212.5' THEN 'Assault with aggravating factors such as victim status or severity. Applies to assaults involving heightened public safety concern.'
  WHEN 'PC-664' THEN 'Attempting to commit a felony but failing or being interrupted. Requires specific intent and a direct step toward completion.'
  WHEN 'PC-270' THEN 'Escaping custody or attempting to escape lawful detention. Includes breaking restraints, fleeing from custody, or aiding escape.'
  WHEN 'PC-148' THEN 'Resisting, delaying, or obstructing an officer during lawful duties. Includes physical resistance, fleeing, or interference.'
  WHEN 'PC-149' THEN 'Assaulting an on-duty officer. Requires force or attempt to apply force against a peace officer performing duties.'
  WHEN 'PC-187.5' THEN 'Murder of a peace officer in the performance of duty. Enhanced severity due to protected status of the victim.'
  WHEN 'PC-266' THEN 'Profiting from or facilitating prostitution by managing, directing, or benefiting from another persons sex work.'
  WHEN 'PC-314' THEN 'Indecent exposure in a reckless or offensive manner. Applies to exposing oneself in public to offend or alarm others.'
  WHEN 'PC-381' THEN 'Threats or actions targeting public safety infrastructure or causing community harm. Includes threats intended to disrupt essential services.'
  WHEN 'PC-384' THEN 'Loitering or remaining in an area with intent to engage in drug-related activity. Intent may be inferred from conduct and context.'
  ELSE `description`
END
WHERE `code` IN (
  'PC-187','PC-191','PC-245','PC-242','PC-243','PC-261','PC-262','PC-264','PC-207','PC-208','PC-219','PC-273','PC-273.5','PC-415','PC-417',
  'PC-459','PC-459.5','PC-484','PC-487','PC-488','PC-496','PC-503','PC-530.5','PC-537','PC-666','PC-484F','PC-518','PC-550','PC-484H',
  'VC-10001','VC-10002','VC-10003','VC-10004','VC-10005','VC-10006','VC-10007','VC-480','VC-20001','VC-14601','VC-23152','VC-23153',
  'HS-11350','HS-11352','HS-11351','HS-11359','HS-11360','HS-11370','HS-11377',
  'PC-25400','PC-25850','PC-26350','PC-21510','PC-182','PC-211','PC-212.5','PC-664','PC-270','PC-148','PC-149','PC-187.5','PC-266','PC-314','PC-381','PC-384'
)
AND (
  `description` IS NULL
  OR TRIM(`description`) = ''
  OR `description` = `name`
);

-- ============================================================================
-- END OF CONSOLIDATED SCHEMA
-- ============================================================================
-- This file contains all tables and migrations:
-- - fto_reports.sql
-- - incidents.sql
-- - reports.sql
-- - warrants.sql
-- - profiles.sql
-- - MIGRATION_vehicle_strikes_enhanced.sql
-- - MIGRATION_add_vehiclePlate_to_reports.sql
-- - MIGRATION_add_incident_fields.sql (incident linked fields)
-- - pf-policemdt-qb.sql / pf-policemdt-esx.sql (full merged base)
-- ============================================================================

-- ============================================================================
-- INCIDENT EVIDENCE PHOTOS
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_incident_evidence` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `incident_id` VARCHAR(64) NOT NULL,
  `evidence_number` INT NOT NULL,
  `title` VARCHAR(128) NOT NULL DEFAULT '',
  `description` TEXT NULL,
  `image_url` TEXT NOT NULL,
  `created_by_citizenid` VARCHAR(64) NOT NULL,
  `created_by_name` VARCHAR(128) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_evidence` (`incident_id`, `evidence_number`),
  KEY `idx_incident` (`incident_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- STANDALONE EVIDENCE (Independent evidence not tied to incidents)
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_evidence` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `evidence_id` VARCHAR(32) NOT NULL,
  `evidence_number` INT NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `description` TEXT NULL,
  `image_url` TEXT NOT NULL,
  `tags` VARCHAR(255) NULL,
  `location_details` VARCHAR(255) NULL,
  `incident_id` VARCHAR(64) NULL,
  `citizens_involved` LONGTEXT NULL,
  `vehicles_involved` LONGTEXT NULL,
  `weapons_involved` TEXT NULL,
  `related_charges` LONGTEXT NULL,
  `status` VARCHAR(32) NOT NULL DEFAULT 'Collected',
  `created_by_citizenid` VARCHAR(64) NOT NULL,
  `created_by_name` VARCHAR(128) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_evidence_id` (`evidence_id`),
  UNIQUE KEY `uniq_evidence_number` (`evidence_number`),
  KEY `idx_incident` (`incident_id`),
  KEY `idx_created_by` (`created_by_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- VEHICLE PROFILES - Profile Pictures
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_vehicle_profiles` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL UNIQUE,
  `vehiclePhoto` VARCHAR(512) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- MANUAL CITIZEN ENTRIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_manual_citizens` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenId` VARCHAR(64) NOT NULL,
  `firstname` VARCHAR(64) NOT NULL,
  `lastname` VARCHAR(64) NOT NULL,
  `dob` VARCHAR(32) NULL,
  `phone` VARCHAR(64) NULL,
  `nationality` VARCHAR(64) NULL,
  `gender` VARCHAR(32) NULL,
  `job` VARCHAR(128) NULL,
  `address` VARCHAR(255) NULL,
  `profilePicture` VARCHAR(512) NULL,
  `createdByCitizenId` VARCHAR(64) NULL,
  `createdByName` VARCHAR(128) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_manual_citizen_id` (`citizenId`),
  KEY `idx_manual_citizen_name` (`lastname`, `firstname`),
  KEY `idx_manual_citizen_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- MANUAL VEHICLE ENTRIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_manual_vehicles` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `ownerCitizenId` VARCHAR(64) NULL,
  `ownerName` VARCHAR(128) NULL,
  `model` VARCHAR(128) NULL,
  `modelLabel` VARCHAR(128) NULL,
  `brand` VARCHAR(64) NULL,
  `primaryColorId` INT NULL,
  `secondaryColorId` INT NULL,
  `vehiclePhoto` VARCHAR(512) NULL,
  `createdByCitizenId` VARCHAR(64) NULL,
  `createdByName` VARCHAR(128) NULL,
  `createdAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_manual_vehicle_plate` (`plate`),
  KEY `idx_manual_vehicle_owner_cid` (`ownerCitizenId`),
  KEY `idx_manual_vehicle_owner_name` (`ownerName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- CCTV CAMERAS - Auto-discovered camera registry
-- ============================================================================
DROP TABLE IF EXISTS `pf_mdt_cctv_cameras`;
CREATE TABLE `pf_mdt_cctv_cameras` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `camera_key` VARCHAR(128) NOT NULL UNIQUE,
  `model_hash` BIGINT NULL,
  `model_name` VARCHAR(64) NULL,
  `x` FLOAT NOT NULL,
  `y` FLOAT NOT NULL,
  `z` FLOAT NOT NULL,
  `heading` FLOAT NOT NULL,
  `location_label` VARCHAR(128) NULL,
  `status` ENUM('ONLINE','OFFLINE') DEFAULT 'ONLINE',
  `last_seen_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_camera_key` (`camera_key`),
  KEY `idx_status` (`status`),
  KEY `idx_location` (`location_label`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `pf_mdt_cctv_cameras` (`id`, `camera_key`, `model_hash`, `model_name`, `x`, `y`, `z`, `heading`, `location_label`, `status`, `created_at`, `updated_at`) VALUES
(1, CONCAT('seed_', LPAD(1, 4, '0')), -1159421424, NULL, 218.407, -1459.7, 36.3576, 167.285, 'Innocence Blvd, Davis', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(2, CONCAT('seed_', LPAD(2, 4, '0')), 548760764, NULL, 192.195, -1475.55, 33.554, 225, 'Innocence Blvd, Davis', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(3, CONCAT('seed_', LPAD(3, 4, '0')), -1159421424, NULL, 185.516, -1481.72, 35.644, 250.705, 'Davis Ave, Davis', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(4, CONCAT('seed_', LPAD(4, 4, '0')), 548760764, NULL, 175.997, -1523.13, 34.9092, 311, 'Davis Ave, Davis', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(5, CONCAT('seed_', LPAD(5, 4, '0')), 548760764, NULL, 252.275, -1487.92, 34.959, 141.5, 'Innocence Blvd, Davis', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(6, CONCAT('seed_', LPAD(6, 4, '0')), -1340405475, NULL, 146.522, -1038.2, 31.0197, 159.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(7, CONCAT('seed_', LPAD(7, 4, '0')), 168901740, NULL, 153.179, -1042.19, 31.0526, 239.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(8, CONCAT('seed_', LPAD(8, 4, '0')), 168901740, NULL, 151.103, -1047.01, 31.4522, 239.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(9, CONCAT('seed_', LPAD(9, 4, '0')), -1340405475, NULL, 150.015, -1051.31, 31.4355, 159.846, 'Elgin Ave, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(10, CONCAT('seed_', LPAD(10, 4, '0')), 168901740, NULL, 142.675, -1041.54, 31.558, 44.8462, 'Vespucci Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(11, CONCAT('seed_', LPAD(11, 4, '0')), 168901740, NULL, 151.904, -1043.64, 31.7034, 229.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(12, CONCAT('seed_', LPAD(12, 4, '0')), 168901740, NULL, 143.094, -1040.4, 31.5581, 139.846, 'Vespucci Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(13, CONCAT('seed_', LPAD(13, 4, '0')), 168901740, NULL, 144.953, -1042.98, 31.3438, 44.8462, 'Vespucci Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(14, CONCAT('seed_', LPAD(14, 4, '0')), -1340405475, NULL, 529.828, 724.27, 200.566, 301.495, 'Marlowe Dr, Vinewood Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(15, CONCAT('seed_', LPAD(15, 4, '0')), -1340405475, NULL, 520.933, 744.572, 205.029, 301.495, 'Marlowe Dr, Vinewood Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(16, CONCAT('seed_', LPAD(16, 4, '0')), 168901740, NULL, 180.052, 1242.7, 228.144, 328, 'Baytree Canyon Rd, Vinewood Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(17, CONCAT('seed_', LPAD(17, 4, '0')), 548760764, NULL, 538.301, 2671.71, 44.7499, 276.846, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(18, CONCAT('seed_', LPAD(18, 4, '0')), 548760764, NULL, 552.517, 2741.17, 47.096, 4.0865, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(19, CONCAT('seed_', LPAD(19, 4, '0')), 548760764, NULL, 572.757, 2742.4, 45.898, 4.0865, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(20, CONCAT('seed_', LPAD(20, 4, '0')), 168901740, NULL, 550.276, 2666.5, 44.687, 232.5, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(21, CONCAT('seed_', LPAD(21, 4, '0')), 168901740, NULL, 539.009, 2671.48, 44.687, 52.4999, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(22, CONCAT('seed_', LPAD(22, 4, '0')), 168901740, NULL, 543.014, 2664.61, 44.687, 52.4999, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(23, CONCAT('seed_', LPAD(23, 4, '0')), 548760764, NULL, 549.503, 2673.54, 44.1283, 186.846, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(24, CONCAT('seed_', LPAD(24, 4, '0')), -1159421424, NULL, 531.241, 2675.78, 42.8807, 0, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(25, CONCAT('seed_', LPAD(25, 4, '0')), -1159421424, NULL, 540.896, 2671.78, 49.9135, 0, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(26, CONCAT('seed_', LPAD(26, 4, '0')), -1159421424, NULL, 540.279, 2670.61, 51.126, 0, 'Route 68, Harmony', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(27, CONCAT('seed_', LPAD(27, 4, '0')), 548760764, NULL, -1116.75, 2687.28, 20.6915, 41.8771, 'Route 68, Zancudo River', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(28, CONCAT('seed_', LPAD(28, 4, '0')), 548760764, NULL, -40.4313, 6407.14, 36.8945, 225, 'Great Ocean Hwy, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(29, CONCAT('seed_', LPAD(29, 4, '0')), 548760764, NULL, -53.0901, 6359.1, 37.4509, 44.9999, 'Great Ocean Hwy, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(30, CONCAT('seed_', LPAD(30, 4, '0')), 548760764, NULL, 172.452, 6401.38, 36.1377, 208.761, 'Great Ocean Hwy, Mount Chiliad', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(31, CONCAT('seed_', LPAD(31, 4, '0')), 548760764, NULL, -447.85, 6022.81, 34.3594, 135, 'Paleto Blvd, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(32, CONCAT('seed_', LPAD(32, 4, '0')), 548760764, NULL, -435.4, 6010.35, 34.3594, 135, 'Paleto Blvd, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(33, CONCAT('seed_', LPAD(33, 4, '0')), 548760764, NULL, -431.793, 5989.64, 34.3594, 45, 'Paleto Blvd, Paleto Forest', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(34, CONCAT('seed_', LPAD(34, 4, '0')), -1340405475, NULL, -113.146, 6464.39, 33.2862, 315, 'Paleto Blvd, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(35, CONCAT('seed_', LPAD(35, 4, '0')), 168901740, NULL, -108.022, 6462.62, 33.7407, 190, 'Paleto Blvd, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(36, CONCAT('seed_', LPAD(36, 4, '0')), -1340405475, NULL, -107.892, 6468.55, 34.2675, 315, 'Paleto Blvd, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(37, CONCAT('seed_', LPAD(37, 4, '0')), 548760764, NULL, -168.281, 6441.59, 34.1285, 315, 'Cascabel Ave, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(38, CONCAT('seed_', LPAD(38, 4, '0')), 168901740, NULL, -107.422, 6475.98, 33.7407, 35.0001, 'Paleto Blvd, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(39, CONCAT('seed_', LPAD(39, 4, '0')), -1340405475, NULL, -104.629, 6479.42, 33.724, 315, 'Paleto Blvd, Paleto Bay', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(40, CONCAT('seed_', LPAD(40, 4, '0')), 168901740, NULL, 1963.1, 3748.55, 34.8742, 255, 'Alhambra Dr, Sandy Shores', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(41, CONCAT('seed_', LPAD(41, 4, '0')), 168901740, NULL, 1969.44, 3743.73, 34.8742, 255, 'Alhambra Dr, Sandy Shores', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(42, CONCAT('seed_', LPAD(42, 4, '0')), 168901740, NULL, 1957.12, 3744.02, 34.8742, 74.9999, 'Niland Ave, Sandy Shores', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(43, CONCAT('seed_', LPAD(43, 4, '0')), 548760764, NULL, 1791.72, 2547.78, 51.0436, 89.9917, 'Route 68, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(44, CONCAT('seed_', LPAD(44, 4, '0')), 168901740, NULL, 1845.03, 2594.78, 47.9529, 326.113, 'Route 68, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(45, CONCAT('seed_', LPAD(45, 4, '0')), 168901740, NULL, 1837.16, 2594.46, 47.952, 56.1132, 'Route 68, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(46, CONCAT('seed_', LPAD(46, 4, '0')), 168901740, NULL, 1845.27, 2584.03, 47.953, 216.113, 'Route 68, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(47, CONCAT('seed_', LPAD(47, 4, '0')), -173206916, NULL, 1834.16, 2604.49, 47.4014, 104.041, 'Route 68, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(48, CONCAT('seed_', LPAD(48, 4, '0')), 168901740, NULL, 1824.2, 2472.81, 64.7177, 145, 'Senora Fwy, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(49, CONCAT('seed_', LPAD(49, 4, '0')), 168901740, NULL, 1824.29, 2478.26, 64.7177, 355, 'Senora Fwy, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(50, CONCAT('seed_', LPAD(50, 4, '0')), -173206916, NULL, 1786.95, 2489.94, 47.6627, 15.1131, 'Senora Fwy, Bolingbroke Penitentiary', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(51, CONCAT('seed_', LPAD(51, 4, '0')), 168901740, NULL, 317.51, -280.554, 55.8493, 239.866, 'Meteor St, Alta', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(52, CONCAT('seed_', LPAD(52, 4, '0')), 548760764, NULL, -965.475, -181.509, 40.2058, 297.014, 'Boulevard Del Perro, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(53, CONCAT('seed_', LPAD(53, 4, '0')), -1340405475, NULL, -943.948, -338.01, 40.7521, 0, 'Marathon Ave, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(54, CONCAT('seed_', LPAD(54, 4, '0')), 548760764, NULL, 342.154, -1620.75, 35.2191, 139.928, 'Innocence Blvd, Rancho', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(55, CONCAT('seed_', LPAD(55, 4, '0')), -1340405475, NULL, -1473.56, -593.2, 39.8044, 0, 'Marathon Ave, Del Perro', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(56, CONCAT('seed_', LPAD(56, 4, '0')), -1340405475, NULL, -1441.34, -543.761, 38.5156, 305, 'Prosperity St, Del Perro', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(57, CONCAT('seed_', LPAD(57, 4, '0')), 1449155105, NULL, -1509.53, -512.623, 39.3235, 215, 'Boulevard Del Perro, Del Perro', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(58, CONCAT('seed_', LPAD(58, 4, '0')), -1340405475, NULL, -1495.84, -608.812, 39.8044, 0, 'Marathon Ave, Del Perro', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(59, CONCAT('seed_', LPAD(59, 4, '0')), 1449155105, NULL, -1493.89, -530.623, 37.107, 305, 'Marathon Ave, Del Perro', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(60, CONCAT('seed_', LPAD(60, 4, '0')), 548760764, NULL, -917.643, -448.178, 41.1305, 343.181, 'Movie Star Way, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(61, CONCAT('seed_', LPAD(61, 4, '0')), -1159421424, NULL, 2.77843, 216.167, 113.274, 65.0001, 'Las Lagunas Blvd, West Vinewood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(62, CONCAT('seed_', LPAD(62, 4, '0')), 168901740, NULL, -1072.51, -1678.67, 6.25555, 175.861, 'Bay City Ave, La Puerta', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(63, CONCAT('seed_', LPAD(63, 4, '0')), 548760764, NULL, -1114.15, -837.548, 22.8457, 308.389, 'San Andreas Ave, Vespucci Canals', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(64, CONCAT('seed_', LPAD(64, 4, '0')), 548760764, NULL, -1090.17, -808.307, 21.6384, 218.389, 'San Andreas Ave, Vespucci Canals', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(65, CONCAT('seed_', LPAD(65, 4, '0')), 1449155105, NULL, -1143.28, -843.612, 19.5049, 307.906, 'San Andreas Ave, Vespucci Canals', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(66, CONCAT('seed_', LPAD(66, 4, '0')), 548760764, NULL, -1130.62, -857.659, 17.4837, 311.337, 'Prosperity St, Vespucci Canals', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(67, CONCAT('seed_', LPAD(67, 4, '0')), 548760764, NULL, -1095.49, -854.243, 10.3694, 342.779, 'Vespucci Blvd, Vespucci Canals', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(68, CONCAT('seed_', LPAD(68, 4, '0')), 168901740, NULL, 513.191, -891.64, 18.5065, 160.021, 'Little Bighorn Ave, La Mesa', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(69, CONCAT('seed_', LPAD(69, 4, '0')), 168901740, NULL, 515.728, -805.105, 18.1026, 10.7175, 'Little Bighorn Ave, La Mesa', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(70, CONCAT('seed_', LPAD(70, 4, '0')), 548760764, NULL, 831.816, -1893.93, 33.1025, 265, 'Popular St, Cypress Flats', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(71, CONCAT('seed_', LPAD(71, 4, '0')), 548760764, NULL, 856.816, -1822.01, 33.7035, 270, 'Popular St, Cypress Flats', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(72, CONCAT('seed_', LPAD(72, 4, '0')), 548760764, NULL, 829.364, -1921.97, 32.2095, 265, 'Popular St, Cypress Flats', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(73, CONCAT('seed_', LPAD(73, 4, '0')), 548760764, NULL, 829.766, -1922.48, 32.2095, 355, 'Popular St, Cypress Flats', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(74, CONCAT('seed_', LPAD(74, 4, '0')), 168901740, NULL, 138.264, -1702.92, 31.389, 0.00000512264, 'Carson Ave, Davis', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(75, CONCAT('seed_', LPAD(75, 4, '0')), -1159421424, NULL, -167.111, -1459.94, 37.652, 91, 'Carson Ave, Chamberlain Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(76, CONCAT('seed_', LPAD(76, 4, '0')), -1159421424, NULL, -175.889, -1452.64, 38.4027, 144.5, 'Carson Ave, Chamberlain Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(77, CONCAT('seed_', LPAD(77, 4, '0')), 168901740, NULL, 16.0022, -1107.07, 32.2741, 205, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(78, CONCAT('seed_', LPAD(78, 4, '0')), 168901740, NULL, 6.77947, -1097.7, 32.7716, 115, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(79, CONCAT('seed_', LPAD(79, 4, '0')), 168901740, NULL, 18.3869, -1101.92, 32.7716, 205, 'Elgin Ave, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(80, CONCAT('seed_', LPAD(80, 4, '0')), 168901740, NULL, 3.03235, -1108.98, 32.2741, 115, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(81, CONCAT('seed_', LPAD(81, 4, '0')), 548760764, NULL, -27.9912, -1118.19, 29.5588, 70.0001, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(82, CONCAT('seed_', LPAD(82, 4, '0')), 168901740, NULL, 19.2829, -1103.16, 32.2741, 25, 'Elgin Ave, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(83, CONCAT('seed_', LPAD(83, 4, '0')), 548760764, NULL, -0.909945, -1081.58, 29.564, 250, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(84, CONCAT('seed_', LPAD(84, 4, '0')), 548760764, NULL, -7.3872, -1099.39, 29.564, 250, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(85, CONCAT('seed_', LPAD(85, 4, '0')), 548760764, NULL, -23.3573, -1086.05, 28.9277, 160, 'Power St, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(86, CONCAT('seed_', LPAD(86, 4, '0')), 168901740, NULL, 15.5155, -1113.7, 32.2741, 115, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(87, CONCAT('seed_', LPAD(87, 4, '0')), 168901740, NULL, 6.516, -1098.57, 32.2741, 25, 'Adam\'s Apple Blvd, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(88, CONCAT('seed_', LPAD(88, 4, '0')), -1340405475, NULL, 139.561, -764.216, 47.3775, 250, 'San Andreas Ave, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(89, CONCAT('seed_', LPAD(89, 4, '0')), -1340405475, NULL, 136.742, -763.19, 47.3775, 250, 'San Andreas Ave, Pillbox Hill', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(90, CONCAT('seed_', LPAD(90, 4, '0')), 548760764, NULL, -128.118, -207.777, 48.5751, 336, 'Carcer Way, Burton', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(91, CONCAT('seed_', LPAD(91, 4, '0')), 548760764, NULL, -151.685, -285.596, 43.7289, 341, 'Las Lagunas Blvd, Burton', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(92, CONCAT('seed_', LPAD(92, 4, '0')), 548760764, NULL, -238.601, -216.596, 38.7973, 270, 'San Vitus Blvd, Burton', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(93, CONCAT('seed_', LPAD(93, 4, '0')), 548760764, NULL, -483.822, -63.7358, 43.507, 177, 'Abe Milton Pkwy, Burton', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(94, CONCAT('seed_', LPAD(94, 4, '0')), 548760764, NULL, -486.796, -63.2061, 43.6193, 236, 'Abe Milton Pkwy, Burton', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(95, CONCAT('seed_', LPAD(95, 4, '0')), 548760764, NULL, -607.202, -153.524, 44.627, 293, 'Eastbourne Way, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(96, CONCAT('seed_', LPAD(96, 4, '0')), 548760764, NULL, -638.142, -125.561, 42.8434, 119.6, 'Rockford Dr, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(97, CONCAT('seed_', LPAD(97, 4, '0')), 1449155105, NULL, -765.399, -216.798, 42.9494, 300, 'Eastbourne Way, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(98, CONCAT('seed_', LPAD(98, 4, '0')), -1340405475, NULL, -838.713, -235.077, 40.3279, 270, 'Mad Wayne Thunder Dr, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(99, CONCAT('seed_', LPAD(99, 4, '0')), -1340405475, NULL, -857.016, -231.007, 63.1081, 270, 'Mad Wayne Thunder Dr, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(100, CONCAT('seed_', LPAD(100, 4, '0')), -1340405475, NULL, -869.872, -218.455, 43.3319, 90, 'Mad Wayne Thunder Dr, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(101, CONCAT('seed_', LPAD(101, 4, '0')), 548760764, NULL, -956.591, -179.555, 39.7788, 28, 'Boulevard Del Perro, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(102, CONCAT('seed_', LPAD(102, 4, '0')), 548760764, NULL, -896.13, -154.699, 39.8647, 117.014, 'South Boulevard Del Perro, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(103, CONCAT('seed_', LPAD(103, 4, '0')), 548760764, NULL, -1097.58, -252.338, 40.9512, 297.778, 'South Boulevard Del Perro, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(104, CONCAT('seed_', LPAD(104, 4, '0')), -173206916, NULL, -1145.31, -202.232, 42.8787, 281.356, 'Boulevard Del Perro, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(105, CONCAT('seed_', LPAD(105, 4, '0')), -173206916, NULL, -1144.25, -201.769, 42.8787, 117.908, 'Boulevard Del Perro, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(106, CONCAT('seed_', LPAD(106, 4, '0')), -173206916, NULL, -1192.22, -259.355, 40.5788, 281.356, 'Boulevard Del Perro, Rockford Hills', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(107, CONCAT('seed_', LPAD(107, 4, '0')), 548760764, NULL, -1412.33, -387.4, 40.7334, 32.9611, 'Boulevard Del Perro, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(108, CONCAT('seed_', LPAD(108, 4, '0')), 548760764, NULL, -1437.48, -381.678, 40.9081, 302.961, 'Boulevard Del Perro, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(109, CONCAT('seed_', LPAD(109, 4, '0')), 548760764, NULL, -1432.9, -398.987, 41.3606, 122.105, 'Boulevard Del Perro, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(110, CONCAT('seed_', LPAD(110, 4, '0')), 548760764, NULL, -1444.17, -382.058, 41.5677, 212.105, 'Boulevard Del Perro, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(111, CONCAT('seed_', LPAD(111, 4, '0')), 548760764, NULL, -1460.53, -392.411, 40.7035, 212.105, 'Prosperity St, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(112, CONCAT('seed_', LPAD(112, 4, '0')), 548760764, NULL, -1468.91, -348.312, 47.7176, 312.09, 'North Rockford Dr, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(113, CONCAT('seed_', LPAD(113, 4, '0')), 168901740, NULL, -1482.96, -380.392, 42.7402, 250.926, 'Prosperity St, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(114, CONCAT('seed_', LPAD(114, 4, '0')), 548760764, NULL, -1531.44, -341.124, 47.9424, 315.675, 'Prosperity St, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(115, CONCAT('seed_', LPAD(115, 4, '0')), 548760764, NULL, -1489.51, -323.761, 49.9616, 312.09, 'North Rockford Dr, Morningwood', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(116, CONCAT('seed_', LPAD(116, 4, '0')), 548760764, NULL, -1588.56, -396.326, 46.1337, 225, 'Cougar Ave, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(117, CONCAT('seed_', LPAD(117, 4, '0')), 548760764, NULL, -1662.28, -396.302, 47.9069, 142.105, 'Bay City Ave, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(118, CONCAT('seed_', LPAD(118, 4, '0')), 168901740, NULL, -2104.3, -308.597, 16.6005, 34, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(119, CONCAT('seed_', LPAD(119, 4, '0')), 168901740, NULL, -2097.69, -328.5, 16.6005, 149, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(120, CONCAT('seed_', LPAD(120, 4, '0')), 548760764, NULL, -2024.8, -259.736, 27.0446, 235, 'West Eclipse Blvd, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(121, CONCAT('seed_', LPAD(121, 4, '0')), 548760764, NULL, -1938.69, -533.228, 13.4978, 140.312, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(122, CONCAT('seed_', LPAD(122, 4, '0')), 548760764, NULL, -1932.4, -538.16, 14.7938, 140, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(123, CONCAT('seed_', LPAD(123, 4, '0')), 548760764, NULL, -1919.43, -542.359, 14.7938, 140, 'Del Perro Fwy, Pacific Bluffs', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26'),
(124, CONCAT('seed_', LPAD(124, 4, '0')), -1340405475, NULL, -1594.52, -567.268, 42.9233, 0, 'Bay City Ave, Del Perro', 'ONLINE', '2025-12-27 19:10:26', '2025-12-27 19:10:26');

-- ============================================================================
-- CHAT MESSAGES (Dashboard Officer Communications)
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pf_mdt_chat` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `officer_name` VARCHAR(128) NOT NULL,
  `message` TEXT NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- PERFORMANCE OPTIMIZATION - Add Missing Indexes
-- ============================================================================

-- Optimize officer management queries
ALTER TABLE `pf_mdt_officer_mgmt_profiles` 
  ADD INDEX IF NOT EXISTS `idx_status` (`status`),
  ADD INDEX IF NOT EXISTS `idx_terminated_status` (`terminated`, `status`);

-- Optimize roster queries  
ALTER TABLE `pf_mdt_roster`
  ADD INDEX IF NOT EXISTS `idx_citizenid` (`citizenid`);

-- ============================================================================
-- INSTALLATION VERIFICATION
-- ============================================================================

-- If you see output from these queries, the SQL imported successfully
SELECT 'Installation Check: Tables Created' AS Status, COUNT(*) AS TableCount 
FROM information_schema.TABLES 
WHERE TABLE_SCHEMA = DATABASE() 
AND TABLE_NAME LIKE 'pf_mdt_%';

SELECT 'Installation Check: Critical Table' AS Status, 
       CASE WHEN EXISTS(SELECT 1 FROM information_schema.TABLES 
                        WHERE TABLE_SCHEMA = DATABASE() 
                        AND TABLE_NAME = 'pf_mdt_officer_mgmt_profiles') 
       THEN 'EXISTS' ELSE 'MISSING - SCRIPT FAILED!' END AS Result;

SELECT 'Installation Check: Default Charges' AS Status, COUNT(*) AS ChargeCount 
FROM pf_mdt_charges;

SELECT 'Installation Check: SOPs' AS Status, COUNT(*) AS SOPCount 
FROM pf_mdt_sops;

-- ============================================================================
-- END OF INSTALLATION
-- ============================================================================
-- If you see the above results, the SQL was imported successfully.
-- Restart your FXServer and try again.
-- ============================================================================
