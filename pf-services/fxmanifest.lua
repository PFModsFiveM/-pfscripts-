fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF Services: city events (the shared timeline news, police and apps listen to) and service requests between jobs (tow, EMS, mechanic, police, government)'
version '1.0.0'

dependencies {
    'pfm-core',
    'pf-devices',
}

shared_scripts {
    'shared/catalog.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua', -- PFPayout.Transfer: request rewards are escrowed and paid on the ledger
    'server/schema.lua',
    'server/events.lua',
    'server/requests.lua',
    'server/apps.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'html/apps/dispatch.js',
    'html/apps/services.js',
    'html/apps/services.css',
}

lua54 'yes'
