fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF Devices: one app registry, RPC bridge, push channel and NUI runtime shared by the tablet and the computer'
version '1.0.0'

dependency 'pfm-core'

shared_scripts {
    'shared/config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua', -- PFPayout: paid app installs go through the money ledger
    'server/registry.lua',
    'server/installs.lua',
    'server/rpc.lua',
    'server/push.lua',
    'server/sites.lua',
    'server/builtin_apps.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

-- No ui_page: the runtime is loaded by the shells (pf-tablet, pf-computer) from these files.
files {
    'html/runtime.js',
    'html/runtime.css',
    'html/vendor/jquery-3.6.0.min.js',
    'html/apps/appstore.js',
    'html/apps/browser.js'
}

lua54 'yes'
