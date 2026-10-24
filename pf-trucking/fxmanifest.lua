fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF Trucking (NUI app + NPC jobs + depot work truck rental)'
version '0.1.0'

dependencies {
    'pfm-core',
    'pf-scoreboard'
}

ui_page 'html/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

lua54 'yes'
