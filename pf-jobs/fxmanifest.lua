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
    -- before server/apps/*.lua: records their net events and callbacks for the device apps
    'server/devices_capture.lua',
    'server/main.lua',
    -- database migrations (bus, Gruppe 6 upgrades, tow) and the clean-up of deleted characters
    'server/schema.lua',
    -- server/gruppe6.lua is an older Gruppe6 server that handled the same events as
    -- server/apps/gruppe6.lua; with both loaded every Gruppe6 event ran twice, and its handlers
    -- handed out money bags and spawned any vehicle on request. Only the apps version is loaded.
    'server/apps/*.lua',
    -- the Taxi, Bus, Garbage, Gruppe 6 and Tow apps for the tablet and the computer (pf-devices)
    'server/devices.lua'
}

escrow_ignore 'config.lua'

-- UI page for standalone scoreboard (only one allowed per resource)
ui_page 'html/scoreboard.html'

files {
    -- platform app modules (pf-devices): one module per job app, hosted by the tablet and the computer
    'html/apps/taxi.js',
    'html/apps/bus.js',
    'html/apps/garbage.js',
    'html/apps/gruppe6.js',
    'html/apps/tow.js',
    'html/apps/recycle.js',
    'html/apps/vineyard.js',
    'html/apps/*.css',
    'html/index.html',
    'html/style.css',
    'html/css/*.css',
    'html/scoreboard.html',
    'html/scoreboard.css',
    'html/scoreboard.js',
    'html/script.js',
    'html/business.js',
    'html/*.js',
    'html/taxi_meter.html',
    'html/css/taxi_meter.css',
    'html/taxi_meter.js',
    'html/images/**/*'
}

-- Removed duplicate client_script wildcard (was causing double load)

lua54 'yes'
