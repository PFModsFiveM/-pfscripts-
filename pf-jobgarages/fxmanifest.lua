fx_version 'cerulean'
game 'gta5'

author 'PF Mods'
description 'Job Garages'
version '1.0.0'

lua54 'yes'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/images/*.*',
    'html/images/vehicles/*.*',
    'html/sounds/*.*',
    'images/*.*',
    'images/vehicles/*.*'
}
