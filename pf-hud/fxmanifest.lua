fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_fxv2_oal 'yes'
author 'Project Sloth / PF'
description 'Advanced customizable HUD'
version '3.1.2'

shared_scripts {
    '@pfm-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua',
    'config.lua',
    'uiconfig.lua'
}

client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/*',
    'uiconfig.lua',
}

