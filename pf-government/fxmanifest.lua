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
    'client/civil.lua',
    'client/infrastructure.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua',
    'server/core.lua',
    'server/schema.lua',
    'server/treasury.lua',
    'server/taxes.lua',
    'server/budgets.lua',
    'server/laws.lua',
    'server/licenses.lua',
    'server/utilities.lua',
    'server/bills.lua',
    'server/businesses.lua',
    'server/registry_views.lua',
    'server/premises.lua',
    'server/delivery_zones.lua',
    'server/loans.lua',
    'server/employees.lua',
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
    'server/main.lua',
    -- field apps on the tablet and the computer (pf-devices) and City Hall requests (pf-services)
    'server/apps/common.lua',
    'server/apps/fines.lua',
    'server/apps/inspections.lua',
    'server/apps/requests.lua',
    'server/apps/budget.lua',
    'server/apps/announcements.lua',
    'server/apps/setup.lua',
    'server/apps/register.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/rte.js',
    'html/rte.css',
    'html/games.js',
    'html/apps/gov.css',
    'html/apps/fines.js',
    'html/apps/inspections.js',
    'html/apps/requests.js',
    'html/apps/budget.js',
    'html/apps/announcements.js',
    'html/apps/setup.js',
    'html/apps/cityhall.js'
}

dependencies {
    'oxmysql',
    'pfm-core',
    'pf-computer'
}
