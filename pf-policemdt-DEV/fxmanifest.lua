fx_version 'cerulean'
game 'gta5'

name 'pf-policemdt'
author 'PF Mods'
description 'Advanced Police MDT by PF Mods'
version '1.0.4'

dependencies {
    'pfm-core',
    'screenshot-basic',
    'oxmysql'
}

shared_scripts {
    'shared/framework.lua',    -- Load compatibility settings first
    'config.lua',              -- Then main config (can reference framework settings)
    'shared/debug_print.lua',
    'locales/*.lua'
}

client_scripts {
    'client/device_mode.lua', -- the MDT inside the tablet and the computer (pf-devices); first on purpose
    'client/main.lua',
    'client/roster.lua',
    'client/sop.lua',
    'client/officers.lua',
    'client/dispatch_callouts.lua',
    'client/dispatch_autocalls.lua',
    'client/cctv.lua',
    'client/item_handler.lua'
}

server_scripts {
    'server/access.lua',       -- police-only gate for MDT callbacks/events; must load first
    'server/main.lua',
    'server/roster.lua',
    'server/sop.lua',
    'server/officers.lua',
    'server/cctv.lua',
    'server/item_handler.lua',
    'server/devices.lua'       -- the MDT as a tablet and computer app (pf-devices)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/rte.css',
    'html/locales.js',
    'html/app.js',
    'html/app-extended.js',
    'html/cctv.js',
    'html/cctv.css',
    'html/sop.js',
    'html/roster.js',
    'html/officers.js',
    'html/device_embed.js',
    'html/device_embed.css',
    'html/rte.js',
    'html/rte-init.js',
    'html/assets/**/*',
    'html/tiles/**/*.png',
    'html/map/**/*',
    'locales/*.lua',
    'locales/**/*.lua'
}

escrow_ignore {
    'config.lua',
    'shared/framework.lua',
    'locales/*.lua',
    'sql/*.sql'
}

lua54 'yes'
