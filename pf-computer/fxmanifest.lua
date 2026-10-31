fx_version 'cerulean'
game 'gta5'

author 'PF Scripts'
description 'Computer System - Windows-like Interface with QBCore Integration'
version '2.0.0'

-- Dependencies
dependencies {
    'pfm-core',
    'pfm-target',
    'oxmysql',
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
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/jobboard.lua',
    'server/devices.lua'
}

files {
    'ui/index.html',
    -- every stylesheet and script the page loads
    'ui/css/*.css',
    'ui/js/*.js',
    'ui/assets/wallpaper.jpg',
    'ui/assets/wallpaper_light.png',
    'ui/assets/wallpaper_dark.png',
    'ui/assets/icons/*.png'
}

lua54 'yes'
