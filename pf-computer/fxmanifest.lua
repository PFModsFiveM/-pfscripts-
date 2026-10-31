fx_version 'cerulean'
game 'gta5'

author 'PF Scripts'
description 'Computer System - Windows-like Interface with QBCore Integration'
version '2.0.0'

-- Dependencies
dependencies {
    'pfm-core',
    'pfm-target',
    'pf-devices' -- shared platform apps run in this shell
}

ui_page 'ui/index.html'

shared_scripts {
    'config/config.lua',
    'config/config_hack.lua',
    'config/config_dark.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua',
    'server/gov_announcements_sync.lua'
}

files {
    'ui/index.html',
    -- every stylesheet and script the page loads (cityhall.js and domains-theme.css were missing,
    -- so the City Hall app and the domains theme never loaded in game)
    'ui/css/*.css',
    'ui/js/*.js',
    'ui/assets/wallpaper.jpg',
    'ui/assets/wallpaper_light.png',
    'ui/assets/wallpaper_dark.png',
    'ui/assets/icons/*.png',
    'data/computer_props.json'
}

lua54 'yes'
