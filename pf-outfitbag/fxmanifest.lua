fx_version 'cerulean'
game 'gta5'

author 'PF Mods | https://discord.gg/3cVgnrtXZd'
description 'PF Mods Outfit Bag - An outfit storage solution for QBCore and ESX'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua',
    'server/item.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js'
}

escrow_ignore 'config.lua'

lua54 'yes'