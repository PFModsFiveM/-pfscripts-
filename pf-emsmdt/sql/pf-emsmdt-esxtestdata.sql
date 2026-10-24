-- ============================================================================
-- PF EMS MDT - TEST DATA
-- ============================================================================
-- Date: 2025-12-30
--
-- IMPORTANT
-- - Run this AFTER importing `sql/pf-emsmdt-esx.sql`.
-- - This file ALSO seeds ESX tables `users`, `owned_vehicles`, and `user_licenses`
--   using a common/default ESX schema.
-- - If your ESX `users`/`owned_vehicles`/`user_licenses` schema differs, adjust
--   the INSERT column lists.
--
-- Cleanup
-- - All test citizen IDs start with `MDTTEST`.
-- - All test plates start with `MDT`.
--   You can delete by those prefixes if you want to remove test data later.
-- ============================================================================

START TRANSACTION;

-- ============================================================================
-- CLEANUP: Remove existing test data (allows re-running this file)
-- ============================================================================
DELETE FROM `pf_mdt_bulletins` WHERE `createdByCitizenId` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_fto_report_audit` WHERE `actor_cid` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_fto_reports` WHERE `trainee_cid` LIKE 'MDTTEST%' OR `author_cid` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_chat` WHERE `officer_name` LIKE '%MDTTEST%';
DELETE FROM `pf_mdt_officer_discipline` WHERE `citizenid` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_officer_mgmt_profiles` WHERE `citizenid` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_officer_profiles` WHERE `citizenId` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_weapons_registry` WHERE `ownerCitizenId` LIKE 'MDTTEST%' OR `registeredByCitizenId` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_reports` WHERE `createdAt` IS NOT NULL AND `createdAt` > DATE_SUB(NOW(), INTERVAL 1 YEAR) AND `officer` LIKE 'Jackson Reed%' OR `officer` LIKE 'Olivia Nguyen%';
DELETE FROM `pf_mdt_incident_evidence` WHERE `incident_id` LIKE 'INCMDT%';
DELETE FROM `pf_mdt_incidents` WHERE `incidentId` LIKE 'INCMDT%';
DELETE FROM `pf_mdt_evidence` WHERE `evidence_id` LIKE 'EVD-MDT%';
DELETE FROM `pf_mdt_warrants` WHERE `warrantId` LIKE 'WMDT%';
DELETE FROM `pf_mdt_citizen_flags` WHERE `citizenId` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_citizen_notes` WHERE `citizenId` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_citizen_profiles` WHERE `citizenId` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_vehicle_activity` WHERE `officer` LIKE '2A-%' OR `officer` LIKE '1L-%';
DELETE FROM `pf_mdt_vehicle_strikes` WHERE `officer` LIKE '2A-%' OR `officer` LIKE '1L-%';
DELETE FROM `pf_mdt_vehicle_flags` WHERE `plate` LIKE 'MDT%';
DELETE FROM `pf_mdt_vehicle_notes` WHERE `plate` LIKE 'MDT%';
DELETE FROM `pf_mdt_vehicle_profiles` WHERE `plate` LIKE 'MDT%';
DELETE FROM `pf_mdt_roster` WHERE `citizenid` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_esx_license_suspensions` WHERE `identifier` LIKE 'MDTTEST%';
DELETE FROM `pf_mdt_esx_player_meta` WHERE `identifier` LIKE 'MDTTEST%';
DELETE FROM `user_licenses` WHERE `owner` LIKE 'MDTTEST%';
DELETE FROM `owned_vehicles` WHERE `plate` LIKE 'MDT%';
DELETE FROM `users` WHERE `identifier` LIKE 'MDTTEST%';

-- ----------------------------------------------------------------------------
-- ESX: Fake citizens (users)
-- ----------------------------------------------------------------------------
-- Common ESX `users` schema columns used here:
--   identifier, accounts, group, inventory, job, job_grade, loadout, position,
--   firstname, lastname, dateofbirth, sex, height
-- If your table has extra NOT NULL columns without defaults, add them here.

INSERT INTO `users`
  (`identifier`, `accounts`, `group`, `inventory`, `job`, `job_grade`, `loadout`, `position`, `firstname`, `lastname`, `dateofbirth`, `sex`, `height`)
VALUES
  (
    'MDTTEST01',
    '[{"name":"bank","money":5200},{"name":"money","money":450},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'unemployed',
    0,
    '[]',
    '{"x":440.2,"y":-981.1,"z":30.7}',
    'Ava',
    'Morales',
    '1999-04-12',
    'f',
    170
  ),
  (
    'MDTTEST02',
    '[{"name":"bank","money":1800},{"name":"money","money":120},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'unemployed',
    0,
    '[]',
    '{"x":185.8,"y":-1005.4,"z":29.3}',
    'Noah',
    'Keller',
    '1995-11-02',
    'm',
    182
  ),
  (
    'MDTTEST03',
    '[{"name":"bank","money":24000},{"name":"money","money":980},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'mechanic',
    1,
    '[]',
    '{"x":-339.3,"y":-135.8,"z":39.0}',
    'Sophia',
    'Bennett',
    '1988-07-23',
    'f',
    168
  ),
  (
    'MDTTEST04',
    '[{"name":"bank","money":640},{"name":"money","money":65},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'taxi',
    0,
    '[]',
    '{"x":905.4,"y":-170.3,"z":74.0}',
    'Liam',
    'Price',
    '2001-01-16',
    'm',
    180
  ),
  (
    'MDTTEST05',
    '[{"name":"bank","money":120000},{"name":"money","money":2200},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'realestate',
    4,
    '[]',
    '{"x":-713.8,"y":268.0,"z":84.1}',
    'Mia',
    'Carter',
    '1992-09-05',
    'f',
    165
  ),
  (
    'MDTTEST06',
    '[{"name":"bank","money":90},{"name":"money","money":15},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'unemployed',
    0,
    '[]',
    '{"x":121.7,"y":-222.9,"z":54.6}',
    'Ethan',
    'Hayes',
    '1998-12-30',
    'm',
    178
  ),
  (
    'MDTTEST07',
    '[{"name":"bank","money":8500},{"name":"money","money":900},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'police',
    2,
    '[]',
    '{"x":440.2,"y":-981.1,"z":30.7}',
    'Olivia',
    'Nguyen',
    '1996-03-18',
    'f',
    167
  ),
  (
    'MDTTEST08',
    '[{"name":"bank","money":12400},{"name":"money","money":1100},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'police',
    4,
    '[]',
    '{"x":440.2,"y":-981.1,"z":30.7}',
    'Jackson',
    'Reed',
    '1990-06-01',
    'm',
    185
  ),
  (
    'MDTTEST09',
    '[{"name":"bank","money":3900},{"name":"money","money":600},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'sheriff',
    2,
    '[]',
    '{"x":1853.3,"y":3686.5,"z":34.2}',
    'Amelia',
    'Stone',
    '1994-02-14',
    'f',
    172
  ),
  (
    'MDTTEST10',
    '[{"name":"bank","money":2100},{"name":"money","money":300},{"name":"black_money","money":0}]',
    'user',
    '[]',
    'unemployed',
    0,
    '[]',
    '{"x":-1034.2,"y":-2733.6,"z":20.2}',
    'Benjamin',
    'Flores',
    '1985-10-10',
    'm',
    183
  );

-- ----------------------------------------------------------------------------
-- ESX: Fake owned vehicles (owned_vehicles)
-- ----------------------------------------------------------------------------
-- The MDT reads these columns:
--   plate, citizenid, vehicle, mods
-- This inserts owned vehicle rows for the ESX `player_vehicles` view.

INSERT INTO `owned_vehicles`
  (`owner`, `plate`, `vehicle`, `type`, `stored`)
VALUES
  (
    'MDTTEST01',
    'MDT001',
    '{"model":"sultan","plate":"MDT001","color1":11,"color2":0,"pearlescentColor":111,"wheelColor":156}',
    'car',
    1
  ),
  (
    'MDTTEST02',
    'MDT002',
    '{"model":"bati","plate":"MDT002","color1":0,"color2":0,"wheelColor":0}',
    'bike',
    1
  ),
  (
    'MDTTEST03',
    'MDT003',
    '{"model":"towtruck","plate":"MDT003","color1":25,"color2":0,"wheelColor":144}',
    'car',
    0
  ),
  (
    'MDTTEST05',
    'MDT004',
    '{"model":"baller","plate":"MDT004","color1":111,"color2":111,"wheelColor":144}',
    'car',
    1
  );

-- ----------------------------------------------------------------------------
-- ESX: Fake licenses (user_licenses)
-- ----------------------------------------------------------------------------
INSERT INTO `user_licenses` (`type`, `owner`)
VALUES
  ('drive', 'MDTTEST01'),
  ('drive', 'MDTTEST02'),
  ('weapon', 'MDTTEST02'),
  ('drive', 'MDTTEST03'),
  ('drive', 'MDTTEST04'),
  ('drive', 'MDTTEST05'),
  ('weapon', 'MDTTEST05'),
  ('drive', 'MDTTEST07'),
  ('weapon', 'MDTTEST07'),
  ('drive', 'MDTTEST08'),
  ('weapon', 'MDTTEST08'),
  ('drive', 'MDTTEST09'),
  ('weapon', 'MDTTEST09'),
  ('drive', 'MDTTEST10');

-- ----------------------------------------------------------------------------
-- ESX: Seed MDT metadata (pf_mdt_esx_player_meta)
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_esx_player_meta` (`identifier`, `metadata`)
VALUES
  ('MDTTEST07', '{"mdt_callsign":"2A-11","mdt_status":"available"}'),
  ('MDTTEST08', '{"mdt_callsign":"2A-10","mdt_status":"busy"}'),
  ('MDTTEST09', '{"mdt_callsign":"1L-12","mdt_status":"available"}')
ON DUPLICATE KEY UPDATE `metadata` = VALUES(`metadata`);

-- ----------------------------------------------------------------------------
-- MDT: Citizen profiles / notes / flags
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_citizen_profiles` (`citizenId`, `profilePicture`)
VALUES
  ('MDTTEST01', 'https://picsum.photos/seed/mdt01/256/256'),
  ('MDTTEST02', 'https://picsum.photos/seed/mdt02/256/256'),
  ('MDTTEST05', 'https://picsum.photos/seed/mdt05/256/256')
ON DUPLICATE KEY UPDATE `profilePicture` = VALUES(`profilePicture`);

INSERT INTO `pf_mdt_citizen_notes` (`citizenId`, `text`, `author`)
VALUES
  ('MDTTEST01', 'Frequent flyer at Vespucci boardwalk. Known to cooperate when approached calmly.', 'Sgt. Reed'),
  ('MDTTEST02', 'Valid weapon license. Prior traffic citations.', 'Officer Nguyen'),
  ('MDTTEST06', 'No ID presented during prior contact.', 'Officer Nguyen');

INSERT INTO `pf_mdt_citizen_flags` (`citizenId`, `flag`)
VALUES
  ('MDTTEST02', 'dangerous'),
  ('MDTTEST05', 'firearms_permit_verified'),
  ('MDTTEST06', 'no_license');

-- ----------------------------------------------------------------------------
-- MDT: Vehicle profiles / notes / flags / strikes / activity
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_vehicle_profiles` (`plate`, `vehiclePhoto`)
VALUES
  ('MDT001', 'https://picsum.photos/seed/plateMDT001/640/360'),
  ('MDT002', 'https://picsum.photos/seed/plateMDT002/640/360')
ON DUPLICATE KEY UPDATE `vehiclePhoto` = VALUES(`vehiclePhoto`);

INSERT INTO `pf_mdt_vehicle_notes` (`plate`, `text`, `author`)
VALUES
  ('MDT001', 'Observed circling Legion Square repeatedly at night.', 'Officer Nguyen'),
  ('MDT003', 'Impounded due to outstanding warrant stop.', 'Sgt. Reed');

INSERT INTO `pf_mdt_vehicle_flags` (`plate`, `flag`)
VALUES
  ('MDT001', 'stolen_suspected'),
  ('MDT003', 'impounded');

INSERT INTO `pf_mdt_vehicle_strikes` (`plate`, `title`, `offenseType`, `points`, `description`, `officer`, `location`, `status`, `expiresAt`, `createdByName`)
VALUES
  ('MDT001', 'Reckless Driving', 'Traffic', 4, 'High speed through intersections; failure to yield.', '2A-11', 'Downtown Vinewood', 'active', DATE_ADD(NOW(), INTERVAL 14 DAY), 'Olivia Nguyen'),
  ('MDT002', 'No Helmet', 'Traffic', 2, 'Rider observed without helmet (policy violation).', '2A-11', 'Del Perro', 'dismissed', NULL, 'Olivia Nguyen');

INSERT INTO `pf_mdt_vehicle_activity` (`plate`, `type`, `timestamp`, `location`, `officer`, `officerName`, `referenceId`)
VALUES
  ('MDT001', 'Traffic Stop', NOW(), 'Integrity Way', '2A-11', 'Olivia Nguyen', 'IR-0003'),
  ('MDT003', 'Impound', NOW(), 'Davis PD Lot', '2A-10', 'Jackson Reed', 'INC-0002');

-- ----------------------------------------------------------------------------
-- MDT: Charges catalog (sample)
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_charges` (`code`, `name`, `description`, `fineAmount`, `bailAmount`, `prisonTime`, `category`)
VALUES
  ('PC-001', 'Disorderly Conduct', 'Engaging in disruptive behavior in public.', 250, 500, 0, 'Misdemeanor'),
  ('PC-101', 'Reckless Driving', 'Operating a vehicle with willful disregard for safety.', 500, 750, 0, 'Traffic'),
  ('PC-210', 'Robbery', 'Taking property by force or threat.', 2000, 2500, 30, 'Felony'),
  ('PC-310', 'Possession of Illegal Firearm', 'Possession of an unregistered or prohibited firearm.', 1500, 2000, 20, 'Felony')
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `description` = VALUES(`description`),
  `fineAmount` = VALUES(`fineAmount`),
  `bailAmount` = VALUES(`bailAmount`),
  `prisonTime` = VALUES(`prisonTime`),
  `category` = VALUES(`category`);

-- ----------------------------------------------------------------------------
-- MDT: Warrants
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_warrants`
  (`warrantId`, `suspectCitizenId`, `suspectName`, `charges`, `officers`, `witnesses`, `issuedBy`, `title`, `narrative`, `status`, `createdAt`, `expiresAt`)
VALUES
  (
    'WMDT0001',
    'MDTTEST02',
    'Noah Keller',
    '[{"code":"PC-210","name":"Robbery"}]',
    '["Olivia Nguyen (2A-11)","Jackson Reed (2A-10)"]',
    '["Store Clerk - LTD Gasoline"]',
    'Jackson Reed',
    'Robbery Warrant',
    'Suspect identified on CCTV during armed robbery. Probable cause established from witness statement and video evidence.',
    'active',
    NOW(),
    DATE_ADD(NOW(), INTERVAL 30 DAY)
  ),
  (
    'WMDT0002',
    'MDTTEST06',
    'Ethan Hayes',
    '[{"code":"PC-001","name":"Disorderly Conduct"}]',
    '["Olivia Nguyen (2A-11)"]',
    '["Security Guard - Maze Bank Arena"]',
    'Olivia Nguyen',
    'Failure to Appear',
    'Suspect failed to appear in court on prior citation. Bench warrant requested.',
    'active',
    NOW(),
    DATE_ADD(NOW(), INTERVAL 14 DAY)
  ),
  (
    'WMDT0003',
    NULL,
    'Benjamin Flores',
    '[{"code":"PC-101","name":"Reckless Driving"}]',
    '["Jackson Reed (2A-10)"]',
    '[]',
    'Jackson Reed',
    'Traffic Warrant',
    'Multiple documented reckless driving incidents. Vehicle observed fleeing stop.',
    'closed',
    DATE_SUB(NOW(), INTERVAL 10 DAY),
    DATE_SUB(NOW(), INTERVAL 1 DAY)
  );

-- ----------------------------------------------------------------------------
-- MDT: Evidence (standalone) + Incident Evidence (photos)
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_evidence`
  (`evidence_id`, `evidence_number`, `title`, `description`, `image_url`, `tags`, `location_details`, `incident_id`, `citizens_involved`, `vehicles_involved`, `weapons_involved`, `related_charges`, `status`, `created_by_citizenid`, `created_by_name`)
VALUES
  (
    'EVD-MDT-0001',
    1001,
    'Store CCTV Still',
    'Still image from store CCTV showing suspect face and clothing.',
    'https://picsum.photos/seed/evidence1001/800/450',
    'cctv,robbery,photo',
    'Strawberry Ave / Innocence Blvd',
    'INCMDT0001',
    '[{"citizenId":"MDTTEST02","name":"Noah Keller"}]',
    '[{"plate":"MDT001","model":"Sultan"}]',
    '["WEAPON_PISTOL"]',
    '["PC-210 Robbery"]',
    'Collected',
    'MDTTEST08',
    'Jackson Reed'
  ),
  (
    'EVD-MDT-0002',
    1002,
    'Recovered Handgun',
    'Handgun recovered near scene, bagged and logged.',
    'https://picsum.photos/seed/evidence1002/800/450',
    'weapon,firearm',
    'Davis / Grove St',
    'INCMDT0002',
    '[{"citizenId":"MDTTEST06","name":"Ethan Hayes"}]',
    '[]',
    '["WEAPON_PISTOL"]',
    '["PC-310 Possession of Illegal Firearm"]',
    'Collected',
    'MDTTEST07',
    'Olivia Nguyen'
  );

INSERT INTO `pf_mdt_incident_evidence`
  (`incident_id`, `evidence_number`, `title`, `description`, `image_url`, `created_by_citizenid`, `created_by_name`)
VALUES
  (
    'INCMDT0001',
    1,
    'Register Area Photo',
    'Photo of register area after robbery.',
    'https://picsum.photos/seed/incmdt0001ev1/800/450',
    'MDTTEST08',
    'Jackson Reed'
  ),
  (
    'INCMDT0002',
    1,
    'Recovered Firearm Photo',
    'Photo of recovered firearm at scene.',
    'https://picsum.photos/seed/incmdt0002ev1/800/450',
    'MDTTEST07',
    'Olivia Nguyen'
  );

-- ----------------------------------------------------------------------------
-- MDT: Incidents
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_incidents`
  (`incidentId`, `title`, `priority`, `status`, `reportingOfficer`, `involvedCitizens`, `involvedOfficers`, `involvedVictims`, `involvedVehicles`, `charges`, `evidence_ids`, `involvedCitizenIds`, `involvedOfficerIds`, `involvedVictimIds`, `involvedVehicleIds`, `dateTime`, `location`, `narrative`, `createdBy`, `createdAt`)
VALUES
  (
    'INCMDT0001',
    'Armed Robbery - LTD Strawberry',
    'HIGH',
    'active',
    'Jackson Reed',
    '[{"citizenId":"MDTTEST02","name":"Noah Keller"}]',
    '[{"citizenId":"MDTTEST08","name":"Jackson Reed"},{"citizenId":"MDTTEST07","name":"Olivia Nguyen"}]',
    '[{"name":"Store Clerk"}]',
    '[{"plate":"MDT001","model":"sultan"}]',
    '[{"code":"PC-210","name":"Robbery"}]',
    '["EVD-MDT-0001"]',
    '["MDTTEST02"]',
    '["MDTTEST08","MDTTEST07"]',
    '["VICTIM-0001"]',
    '["MDT001"]',
    NOW(),
    'Strawberry / Innocence Blvd',
    'Suspect brandished handgun, demanded cash, fled in dark sedan. CCTV collected and warrant requested.',
    'MDTTEST08',
    NOW()
  ),
  (
    'INCMDT0002',
    'Firearm Recovered - Grove St',
    'MEDIUM',
    'closed',
    'Olivia Nguyen',
    '[{"citizenId":"MDTTEST06","name":"Ethan Hayes"}]',
    '[{"citizenId":"MDTTEST07","name":"Olivia Nguyen"}]',
    '[]',
    '[]',
    '[{"code":"PC-310","name":"Possession of Illegal Firearm"}]',
    '["EVD-MDT-0002"]',
    '["MDTTEST06"]',
    '["MDTTEST07"]',
    '[]',
    '[]',
    DATE_SUB(NOW(), INTERVAL 2 DAY),
    'Davis / Grove St',
    'Recovered firearm and logged evidence. Case closed after no additional leads.',
    'MDTTEST07',
    DATE_SUB(NOW(), INTERVAL 2 DAY)
  );

-- ----------------------------------------------------------------------------
-- MDT: Reports
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_reports`
  (`reportId`, `type`, `category`, `title`, `procedure_text`, `officer`, `narrative`, `content`, `location`, `vehiclePlate`, `involvedParties`, `linkedEvidence`, `approvalStatus`, `status`, `timestamp`, `createdAt`)
VALUES
  (
    'RMDT0001',
    'Incident Report',
    'Robbery',
    'LTD Strawberry Armed Robbery',
    'Initial response, scene security, witness statements, and evidence collection.',
    'Jackson Reed',
    'Suspect threatened clerk with handgun and fled. Witness provided partial description.',
    'Units responded code 3. Scene secured. CCTV still obtained and logged as evidence. Warrant requested for suspect based on ID from witness and video.',
    'Strawberry / Innocence Blvd',
    'MDT001',
    '[{"citizenId":"MDTTEST02","name":"Noah Keller","role":"Suspect"},{"name":"Store Clerk","role":"Victim"}]',
    '[{"evidence_id":"EVD-MDT-0001","title":"Store CCTV Still"}]',
    'approved',
    'approved',
    NOW(),
    NOW()
  ),
  (
    'RMDT0002',
    'Traffic Stop',
    'Traffic',
    'Traffic Stop - MDT002',
    'Stop, identify driver, check warrants, issue citation/warning.',
    'Olivia Nguyen',
    'Conducted traffic stop for failure to signal. Rider produced ID and valid licenses.',
    'Stop completed without incident. Warning issued. No contraband located.',
    'Del Perro',
    'MDT002',
    '[{"citizenId":"MDTTEST02","name":"Noah Keller","role":"Driver"}]',
    '[]',
    'pending',
    'pending',
    DATE_SUB(NOW(), INTERVAL 1 DAY),
    DATE_SUB(NOW(), INTERVAL 1 DAY)
  );

-- ----------------------------------------------------------------------------
-- MDT: Weapons Registry
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_weapons_registry`
  (`serial`, `weapon`, `weaponLabel`, `ownerCitizenId`, `ownerName`, `registeredByCitizenId`, `registeredByName`, `notes`)
VALUES
  ('MDT-WPN-0001', 'WEAPON_PISTOL', '9mm Pistol', 'MDTTEST02', 'Noah Keller', 'MDTTEST08', 'Jackson Reed', 'Registered after verification of serial and license.'),
  ('MDT-WPN-0002', 'WEAPON_SMG', 'SMG', 'MDTTEST05', 'Mia Carter', 'MDTTEST08', 'Jackson Reed', 'High-value owner; business license on file.'),
  ('MDT-WPN-0003', 'WEAPON_PISTOL', '9mm Pistol', 'MDTTEST06', 'Ethan Hayes', 'MDTTEST07', 'Olivia Nguyen', 'Recovered at scene; pending disposition.');

-- ----------------------------------------------------------------------------
-- MDT: Officer Profiles (persistent UI callsign/status/avatar)
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_officer_profiles` (`citizenId`, `callsign`, `status`, `avatarUrl`)
VALUES
  ('MDTTEST07', '2A-11', 'available', 'https://picsum.photos/seed/officer07/256/256'),
  ('MDTTEST08', '2A-10', 'busy', 'https://picsum.photos/seed/officer08/256/256'),
  ('MDTTEST09', '1L-12', 'available', 'https://picsum.photos/seed/officer09/256/256')
ON DUPLICATE KEY UPDATE
  `callsign` = VALUES(`callsign`),
  `status` = VALUES(`status`),
  `avatarUrl` = VALUES(`avatarUrl`);

-- ----------------------------------------------------------------------------
-- MDT: Officer Management (HR) profiles + discipline
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_officer_mgmt_profiles`
  (`citizenid`, `hire_date`, `probation_until`, `is_fto`, `status`, `terminated`, `terminated_at`, `terminated_by`, `terminated_reason`, `restrictions_json`, `flags_json`)
VALUES
  ('MDTTEST07', DATE_SUB(NOW(), INTERVAL 90 DAY), DATE_ADD(NOW(), INTERVAL 30 DAY), 0, 'ACTIVE', 0, NULL, NULL, NULL, '{"restrictions":[]}', '{"flags":["field_training"]}'),
  ('MDTTEST08', DATE_SUB(NOW(), INTERVAL 450 DAY), NULL, 1, 'ACTIVE', 0, NULL, NULL, NULL, '{"restrictions":[]}', '{"flags":["supervisor","fto"]}'),
  ('MDTTEST09', DATE_SUB(NOW(), INTERVAL 200 DAY), NULL, 0, 'ACTIVE', 0, NULL, NULL, NULL, '{"restrictions":[]}', '{"flags":[]}')
ON DUPLICATE KEY UPDATE
  `probation_until` = VALUES(`probation_until`),
  `is_fto` = VALUES(`is_fto`),
  `status` = VALUES(`status`),
  `restrictions_json` = VALUES(`restrictions_json`),
  `flags_json` = VALUES(`flags_json`);

INSERT INTO `pf_mdt_officer_discipline`
  (`citizenid`, `type`, `reason`, `issued_by`, `active`, `expires_at`)
VALUES
  ('MDTTEST07', 'NOTE', 'Counseled for report formatting. No further action required.', 'Jackson Reed', 0, NULL),
  ('MDTTEST09', 'STRIKE', 'Missed radio check-ins during shift. Corrective action assigned.', 'Jackson Reed', 1, DATE_ADD(NOW(), INTERVAL 21 DAY));

-- ----------------------------------------------------------------------------
-- MDT: Roster (callsign assignments)
-- ----------------------------------------------------------------------------
-- Note: `pf_mdt_roster.callsign` is UNIQUE, so we use INSERT IGNORE.
INSERT IGNORE INTO `pf_mdt_roster`
  (`callsign`, `rank`, `officer_name`, `citizenid`, `unit_type`, `training_status`, `notes`, `created_at`, `updated_at`)
VALUES
  ('2A-10', 'Patrol Sergeant', 'Jackson Reed', 'MDTTEST08', 'Watch Command / Field Command', 'NONE', 'Test data assignment', NOW(), NOW()),
  ('2A-11', 'Patrol Officer', 'Olivia Nguyen', 'MDTTEST07', 'Patrol Units', 'NONE', 'Test data assignment', NOW(), NOW()),
  ('1L-12', 'Deputy', 'Amelia Stone', 'MDTTEST09', 'Patrol Units', 'NONE', 'Test data assignment', NOW(), NOW());

-- ----------------------------------------------------------------------------
-- MDT: FTO v2 report + audit trail
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_fto_reports`
  (`report_uid`, `status`, `trainee_cid`, `trainee_name`, `trainee_callsign`, `author_cid`, `author_name`, `phase`, `shift`, `ride_date`, `submitted_at`, `reviewed_by_cid`, `reviewed_by_name`, `reviewed_at`, `review_note`, `ride_description`, `overall_rating`, `safety_concern`, `safety_concern_notes`, `recommendation`, `strengths`, `improvements`, `evaluation_json`)
VALUES
  (
    'FTO-MDT01',
    'SUBMITTED',
    'MDTTEST07',
    'Olivia Nguyen',
    '2A-11',
    'MDTTEST08',
    'Jackson Reed',
    2,
    'Evening',
    DATE_SUB(NOW(), INTERVAL 3 DAY),
    DATE_SUB(NOW(), INTERVAL 3 DAY),
    'MDTTEST08',
    'Jackson Reed',
    DATE_SUB(NOW(), INTERVAL 2 DAY),
    'Solid performance. Continue improving radio brevity and report structure.',
    'Patrol shift covering downtown calls. Conducted traffic stop and assisted on robbery follow-up.',
    4.2,
    0,
    NULL,
    'ADVANCE',
    'Good officer safety, professional demeanor, strong communication with citizens.',
    'Write reports with clearer chronology; include evidence references consistently.',
    '{"radio":{"rating":4,"notes":"Good radio discipline."},"officer_safety":{"rating":5,"notes":"Maintained distance and cover."},"report_writing":{"rating":3,"notes":"Needs more structure."}}'
  );

INSERT INTO `pf_mdt_fto_report_audit`
  (`report_uid`, `action`, `actor_cid`, `actor_name`, `details_json`)
VALUES
  ('FTO-MDT01', 'create', 'MDTTEST08', 'Jackson Reed', '{"source":"testdata"}'),
  ('FTO-MDT01', 'submit', 'MDTTEST08', 'Jackson Reed', '{"status":"SUBMITTED"}');

-- ----------------------------------------------------------------------------
-- MDT: Chat messages (dashboard)
-- ----------------------------------------------------------------------------
INSERT INTO `pf_mdt_chat` (`officer_name`, `message`, `created_at`)
VALUES
  ('Olivia Nguyen (2A-11)', 'Unit available for calls. Starting patrol in Del Perro.', DATE_SUB(NOW(), INTERVAL 30 MINUTE)),
  ('Jackson Reed (2A-10)', 'Reminder: tag all evidence photos with incident IDs.', DATE_SUB(NOW(), INTERVAL 20 MINUTE)),
  ('Amelia Stone (1L-12)', '10-8 in Sandy Shores.', DATE_SUB(NOW(), INTERVAL 10 MINUTE));

-- ============================================================================
-- MDT: Test Bulletins
-- ============================================================================
INSERT INTO `pf_mdt_bulletins` (`title`, `body`, `createdByCitizenId`, `createdByName`, `createdAt`)
VALUES
  (
    'Patrol Zone Reorganization',
    'Effective immediately, patrol zones have been reorganized to improve coverage and response times. Zone 2A now includes Downtown, Pillbox, and Mirror Park. Zone 1L covers Sandy Shores and Paleto Bay. See dispatch for full briefing.',
    'MDTTEST08',
    'Jackson Reed',
    DATE_SUB(NOW(), INTERVAL 2 DAY)
  ),
  (
    'Annual Firearms Qualification Due',
    'All sworn personnel must complete firearms qualification by end of month. Schedule appointments via the HR portal. Failure to qualify will result in desk duty pending remediation.',
    'MDTTEST08',
    'Jackson Reed',
    DATE_SUB(NOW(), INTERVAL 1 DAY)
  ),
  (
    'Evidence Handling Procedures Update',
    'Updated evidence tagging and photo standards are now in effect. All evidence must include location photos and chain-of-custody documentation. Training refresher scheduled for next shift briefing.',
    'MDTTEST07',
    'Olivia Nguyen',
    NOW()
  ),
  (
    'High-Risk Traffic Stop Protocol Changes',
    'Effective next week, all traffic stops flagged with wanted persons or outstanding warrants must be initiated with Code 2 backup. Updated protocol in dispatch system. Questions contact supervision.',
    'MDTTEST08',
    'Jackson Reed',
    DATE_SUB(NOW(), INTERVAL 12 HOUR)
  ),
  (
    'Community Outreach - Beach Safety Initiative',
    'Department is hosting beach safety awareness event this Saturday. Officers interested in volunteering contact community relations. Free lunch provided for volunteers.',
    'MDTTEST07',
    'Olivia Nguyen',
    DATE_SUB(NOW(), INTERVAL 6 HOUR)
  ),
  (
    'Vehicle Pursuit Authorization Update',
    'New tire deflation device (spike strips) now authorized for tactical vehicle pursuits. All officers must review refresher training module before end of shift. See training portal for details.',
    'MDTTEST08',
    'Jackson Reed',
    DATE_SUB(NOW(), INTERVAL 3 HOUR)
  );

COMMIT;
