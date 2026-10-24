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
	'shared/framework.lua'
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
	'client/injury_handler.lua',
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
	'server/injury_handler.lua',
	'server/treatment.lua'
}
