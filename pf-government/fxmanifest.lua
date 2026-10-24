fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'PF Scripts'
description 'PF Government - Comprehensive City Government Framework'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    'client/main.lua',
    'client/nui.lua',
    'client/civil.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/core.lua',
    'server/treasury.lua',
    'server/taxes.lua',
    'server/budgets.lua',
    'server/laws.lua',
    'server/licenses.lua',
    'server/utilities.lua',
    'server/bills.lua',
    'server/businesses.lua',
    'server/staff.lua',
    'server/audit.lua',
    'server/infrastructure.lua',
    'server/integrations.lua',
    'server/assistant_data.lua',
    'server/assistant_parser.lua',
    'server/assistant_tools.lua',
    'server/assistant.lua',
    'server/callbacks.lua',
    'server/civil.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/rte.js',
    'html/rte.css',
    'html/games.js'
}

dependencies {
    'oxmysql',
    'pfm-core',
    'pf-computer'
}
