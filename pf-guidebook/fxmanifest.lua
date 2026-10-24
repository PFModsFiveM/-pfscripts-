fx_version 'cerulean'
game 'gta5'

author 'PF Mods'
description 'City onboarding guidebook with QBCore, ESX, and standalone support'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

lua54 'yes'
