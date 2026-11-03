fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF Justice: legal orders (jail, prison, fines, citations, restitution, community service, probation, parole, remand), the one sentence clock, criminal records, custody, booking, property lockers and bail'
version '1.0.0'

dependencies {
    'pfm-core',
    'oxmysql',
    'pfm-banking',
    'pfm-inventory',
}

shared_scripts {
    'config.lua',
    'shared/states.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua', -- PFPayout.Transfer / IsClearFailure: fines and bail move only on the ledger
    'server/main.lua',
    'server/schema.lua',
    'server/orders.lua',
    'server/clock.lua',
    'server/records.lua',
    'server/custody.lua',
    'server/booking.lua',
    'server/property.lua',
    'server/bail.lua',
    'server/legacy_import.lua',
    'server/compat.lua',
    'server/api.lua',
}

lua54 'yes'
