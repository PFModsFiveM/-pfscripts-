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
    -- (client/dispatch_callouts.lua and client/dispatch_autocalls.lua, the police MDT's crime
    -- detection, are no longer loaded: batch 20 removed their server side, which never made a call)
    , 'client/item_handler.lua'
    -- pf-ambulancejob's exam and treatment catalogues (pure data): labels and targeting for the
    -- patient care page's menus; the server decides every exam and treatment
    , '@pf-ambulancejob/shared/medical/anatomy.lua'
    , '@pf-ambulancejob/shared/medical/findings.lua'
    , '@pf-ambulancejob/shared/medical/treatments.lua'
    , 'client/injury_integration.lua' -- patient care, unit board and PCR bridge (batch 21)
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/schema.lua', -- owns the 'pf-emsmdt' migrations; the other files wait for it (PFEmsSchema.OnReady)
    'server/main.lua'
    , 'server/roster.lua'
    , 'server/sop.lua'
    , 'server/officers.lua'
    , 'server/item_handler.lua'
    , 'server/units.lua' -- unit board (batch 20); before pcr.lua, which reads it
    , 'server/pcr.lua' -- patient care reports charted from pf-ambulancejob events (batch 20)
    , 'server/hospital_app.lua' -- hospital workstation app handlers (batch 21); before devices.lua, which registers it
    , 'server/devices.lua' -- the MDT as a tablet and computer app (pf-devices)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/locales.js',
    'html/app.js',
    'html/injury_panel.js',
    'html/exam.js', -- patient care page: exams, treatments, chart (batch 21)
    'html/monitor.js', -- vitals monitor (batch 21)
    'html/pcr.js', -- PCR editor and unit board (batch 21)
    'html/sop.js',
    'html/roster.js',
    'html/officers.js',
    'html/device_embed.js',
    'html/device_embed.css',
    'html/apps/hospital.js', -- hospital workstation pf-devices module (batch 21)
    'html/apps/hospital.css',
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
