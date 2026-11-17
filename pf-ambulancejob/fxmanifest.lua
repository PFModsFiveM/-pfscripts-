fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Kakarot'
description 'Player health, death, and wounding system with ems job'
version '1.2.4'

shared_scripts {
	'@pfm-core/shared/locale.lua',
	'locales/en.lua',
	'locales/*.lua',
	'config.lua',
	'config_medical.lua',
	'config_ems.lua', -- 17D: stretchers, wheelchairs, medbags, rig stock
	'config_hospital.lua', -- 17E: facilities, departments, beds, tariff, AI care
	'shared/framework.lua',
	'shared/medical/anatomy.lua',
	'shared/medical/injuries.lua',
	'shared/medical/physiology_model.lua',
	'shared/medical/effects_model.lua',
	'shared/medical/mechanisms.lua', -- 16B: damage source -> injury rules
	'shared/medical/findings.lua', -- 17A: exam modalities, signs, sensitivity per tier
	'shared/medical/treatments.lua' -- 17B: treatment action catalog
}

client_scripts {
	'client/main.lua',
	'client/wounding.lua',
	'client/laststand.lua',
	'client/job.lua',
	'client/dead.lua',
	'client/damage_detection.lua',
	'client/check_injuries.lua',
	'client/treatment.lua',
	'client/medical_hints.lua', -- 16B: event-driven fall / vehicle / water hints
	'client/exam.lua', -- 17A: exam target options -> EMDT exam UI
	'client/effects.lua', -- 17C: applies the server's effect profile (no loop while it is empty)
	'client/ems_equipment.lua', -- 17D: stretcher/wheelchair visuals from entity state bags
	'client/hospital.lua', -- 17E: reception, bed and department interactions (20A: pharmacy counter)
	'client/morgue.lua', -- 20B: morgue and medical examiner interactions
	'@PolyZone/client.lua',
	'@PolyZone/BoxZone.lua',
	'@PolyZone/ComboZone.lua'
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'@pfm-banking/payouts.lua', -- hospital bills through the bank ledger (PFPayout)
	'@pfm-core/server/migrations.lua',
	'server/main.lua',
	'server/injury_database.lua',
	'server/medical/schema.lua', -- owns the 'pf-ambulancejob' migrations (v1 moved here)
	'server/medical/store.lua',
	'server/medical/engine.lua',
	'server/medical/downstate.lua', -- 16A: the only writer of isdead/inlaststand/pf:down; revive tokens
	'server/medical/ingest.lua', -- 16B: damage hints and samplers -> injuries
	'server/medical/legacy_import.lua', -- 16B: player_injuries -> pf_med_injuries (once)
	'server/medical/effects.lua',
	'server/medical/api.lua',
	'server/medical/diagnosis.lua', -- 17A: findings, suspected/confirmed diagnoses
	'server/medical/exam.lua', -- 17A: exam actions per modality
	'server/medical/treatment.lua', -- 17B: treatment engine
	'server/medical/recovery.lua', -- 17C: stage machine, restrictions, offline recovery, GetRestrictions
	'server/items.lua', -- 17B: usable medical items (consumed on the server first)
	'server/ems/equipment.lua', -- 17D: stretchers, wheelchairs, medbags, loading
	'server/hospital/facility.lua', -- 17E: hospitals, departments, zones, staffing
	'server/hospital/admissions.lua', -- 17E: check-in, triage, admit, discharge, transfer
	'server/hospital/beds.lua', -- 17E: server bed occupancy
	'server/hospital/billing.lua', -- 17E: itemised bills through the ledger
	'server/hospital/ai_care.lua', -- 17E: low-population care
	'server/hospital/custody.lua', -- 19G: infirmary, screening, escorted transfers with custody continuity
	'server/hospital/pharmacy.lua', -- 20A: prescriptions, dispensing, controlled-substance log
	'server/hospital/lab.lua', -- 20A: lab orders (blood type, CBC, tox, BAC) from engine state
	'server/hospital/imaging.lua', -- 20A: x-ray / CT orders that confirm diagnoses
	'server/hospital/surgery.lua', -- 20A: surgery in OR rooms, projectile recovery, ward/ICU stays
	'server/hospital/morgue.lua', -- 20B: morgue intake, autopsy, death records
	'server/hospital/supplies.lua', -- 20C: facility stock from pf-stores deliveries
	'server/ems/fleet.lua', -- 20C: rig stock, restock, fleet maintenance requests
	'server/injury_handler.lua',
	'server/treatment.lua'
}
