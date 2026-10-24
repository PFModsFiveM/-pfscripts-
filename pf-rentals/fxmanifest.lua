fx_version 'cerulean'
game 'gta5'

author 'ProjectFusion'
description 'Vehicle Rental System with Modern UI'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/integration.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua',
    'server/integration.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/assets/*.png',
    'html/assets/*.svg'
}

-- Dependencies
dependencies {
    'pfm-core',
    'pfm-target',
    'oxmysql'
}

lua54 'yes'
