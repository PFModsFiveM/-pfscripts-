fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'QBCore Job System with Tablet UI'
version '1.0.0'

-- Ensure dependencies are started before this resource
dependencies {
    'pfm-core',
    'pfm-target'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    -- Use wildcard only once to avoid double loading
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/*.lua',
    'server/apps/*.lua'
}

escrow_ignore 'config.lua'

-- UI page for standalone scoreboard (only one allowed per resource)
ui_page 'html/scoreboard.html'

files {
    'html/index.html',
    'html/style.css',
    'html/css/*.css',
    'html/scoreboard.html',
    'html/scoreboard.css',
    'html/scoreboard.js',
    'html/script.js',
    'html/tablet_module.js',
    'html/business.js',
    'html/*.js',
    'html/taxi_meter.html',
    'html/css/taxi_meter.css',
    'html/taxi_meter.js',
    'html/images/**/*'
}

-- Removed duplicate client_script wildcard (was causing double load)

lua54 'yes'
