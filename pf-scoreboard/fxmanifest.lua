fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'PFMods'
description 'PF Job Scoreboard (standalone resource)'
version '1.0.0'

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'html/scoreboard.html'

files {
    'html/scoreboard.html',
    'html/scoreboard.css',
    'html/scoreboard.js'
}

exports {
    'ShowScoreboard',
    'HideScoreboard',
    'UpdateScoreboard'
}

server_exports {
    'ShowForPlayer',
    'UpdateForPlayer',
    'HideForPlayer'
}
