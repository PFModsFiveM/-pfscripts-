fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF Tablet UI with Job Apps Integration'
version '2.0.0'

-- Ensure qb-core is started before this resource to avoid nil exports
dependency 'pfm-core'
dependency 'pf-scoreboard'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/apps/business.lua',
    'server/apps/business_manager.lua'
}

escrow_ignore {
    'config.lua'
}

-- ONLY ONE ui_page allowed (main tablet UI)
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/taxi.css',
    'html/script.js',
    'html/business.js',
    'html/business-manager.js',
    'html/businesses.js',
    'html/taxi_module.js',
    'html/scoreboard.js',
    'html/scoreboard.css',
    'html/mechanic.js',
    'html/wallpaper.jpg',
    'html/img/*'
}

-- Removed duplicate client_script wildcard (was causing double load)

lua54 'yes'
