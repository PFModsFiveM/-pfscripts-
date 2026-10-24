fx_version 'cerulean'
game 'gta5'

description 'PF Stores (depends on pf-computer, pf-jobs, pf-trucking)'
version '0.0.1'

lua54 'yes'

ui_page 'ui/index.html'

-- Keep dependencies explicit; pf-stores will integrate with these resources.
dependencies {
    'pfm-core',
    'pfm-banking', -- store money moves through its ledger
    'pfm-target',
    'oxmysql',
    'pf-computer',
    'pf-jobs',
    'pf-trucking'
}

shared_scripts {
    'shared/config.lua'
}

files {
    'install.sql'
    ,'ui/index.html'
    ,'ui/style.css'
    ,'ui/script.js'
    ,'ui/**/*'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}
