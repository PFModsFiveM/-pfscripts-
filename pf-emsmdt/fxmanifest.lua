fx_version 'cerulean'
game 'gta5'

name 'pf-emsmdt'
author 'PF Mods'
description 'Advanced EMS MDT by PF Mods'
version '1.0.0'

dependencies {
    'screenshot-basic',
    'oxmysql',
    'pf-ambulancejob'
}

shared_scripts {
    'config.lua',
    'shared/framework.lua',
    'shared/debug_print.lua',
    'locales/*.lua'
}

client_scripts {
    'client/device_mode.lua', -- the MDT inside the tablet and the computer (pf-devices); first on purpose
    'client/main.lua'
    , 'client/roster.lua'
    , 'client/sop.lua'
    , 'client/officers.lua'
    , 'client/dispatch_callouts.lua'
    , 'client/dispatch_autocalls.lua'
    , 'client/item_handler.lua'
    , 'client/injury_integration.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
    , 'server/roster.lua'
    , 'server/sop.lua'
    , 'server/officers.lua'
    , 'server/item_handler.lua'
    , 'server/devices.lua' -- the MDT as a tablet and computer app (pf-devices)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/locales.js',
    'html/app.js',
    'html/app-extended.js',
    'html/injury_panel.js',
    'html/sop.js',
    'html/roster.js',
    'html/officers.js',
    'html/device_embed.js',
    'html/device_embed.css',
    'html/assets/**/*',
    'html/leaflet/dist/leaflet.js',
    'html/leaflet/dist/leaflet.css',
    'html/leaflet/dist/images/*.png',
    'html/tiles/**/*.png',
    'html/map/**/*',
    'html/map2/**/*',
    'html/maps/**/*',
    'locales/*.lua',
    'locales/**/*.lua'
}

escrow_ignore 'config.lua'

lua54 'yes'
