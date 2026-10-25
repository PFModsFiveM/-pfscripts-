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
    '@pfm-banking/payouts.lua', -- PFPayout: job payouts through the money ledger
    'server/main.lua',
    -- server/gruppe6.lua is an older Gruppe6 server that handled the same events as
    -- server/apps/gruppe6.lua; with both loaded every Gruppe6 event ran twice, and its handlers
    -- handed out money bags and spawned any vehicle on request. Only the apps version is loaded.
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
