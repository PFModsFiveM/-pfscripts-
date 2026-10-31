fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF Citizen: one mailbox, one bills view, documents and a calendar for every citizen, shared by the tablet, the computer and the phone'
version '1.0.0'

dependencies {
    'pfm-core',
    'pf-devices',
}

shared_scripts {
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua', -- government bills are charged through the money ledger
    'server/schema.lua',
    'server/util.lua',
    'server/mail.lua',
    'server/bills.lua',
    'server/documents.lua',
    'server/calendar.lua',
    'server/apps.lua',
    'server/main.lua',
}

-- No client code: the apps run in the pf-devices runtime and talk to the server through its RPC bridge.
files {
    'html/apps/citizen.css',
    'html/apps/mail.js',
    'html/apps/bills.js',
    'html/apps/documents.js',
    'html/apps/calendar.js',
}

lua54 'yes'
