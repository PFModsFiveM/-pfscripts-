fx_version 'cerulean'
game 'gta5'

author 'PF Scripts'
description 'PF Restaurants - Full Restaurant Business Simulation'
version '1.0.0'

dependencies {
    'pfm-core',
    'pfm-inventory',  -- stock lives in stashes
    'pfm-banking',    -- sales, refunds and supplies go through the ledger
    'oxmysql',
}

ui_page 'web/index.html'

shared_scripts {
    'config/shared.lua',
    'config/items.lua',
    'config/restaurants.lua',
    'config/stations.lua',
    'config/recipes.lua'
}

client_scripts {
    'client/main.lua',
    'client/stations.lua',
    'client/registers.lua',
    'client/screens.lua',
    'client/hygiene.lua',
    'client/fire.lua',
    'client/interactions.lua',
    'client/premises_equipment.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-core/server/migrations.lua',
    'server/main.lua',
    'server/persistence.lua',  -- database, staff permissions, items, stock stashes
    'server/business.lua',
    'server/recipes.lua',
    'server/menu.lua',
    'server/orders.lua',
    'server/stations.lua',
    'server/inventory.lua',
    'server/equipment.lua',
    'server/hygiene.lua',
    'server/fire.lua',
    'server/analytics.lua',
    'server/placeholders_government.lua',
    'server/integration.lua',
    'server/premises_equipment.lua'
}

files {
    'web/index.html',
    'web/pos.html',
    'web/kds.html',
    'web/menu.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/assets/**/*'
}

lua54 'yes'
