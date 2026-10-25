fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'PF Mods'
description 'Farming: persistent crop plots feeding the shared inventory, freshness and supplier system'
version '1.0.0'

dependencies {
    'pfm-core',
    'pfm-inventory',
    'pfm-banking',
    'oxmysql',
}

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-core/server/migrations.lua',
    '@pfm-banking/payouts.lua',
    'server/main.lua',
}
