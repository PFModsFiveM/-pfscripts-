fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF Justice: legal orders (jail, prison, fines, citations, restitution, community service, probation, parole, remand), the one sentence clock, criminal records, custody, booking, property lockers, bail, courts, warrant reviews, supervision and community service'
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
    'shared/cs_tasks.lua',     -- community-service task kinds (19C)
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
    'server/courts.lua',             -- cases, hearings, decisions, court orders (19A)
    'server/warrants.lua',           -- judge reviews of MDT warrants (19A)
    'server/supervision.lua',        -- probation and parole (19B)
    'server/monitors.lua',           -- monitor geofence (19B)
    'server/community_service.lua',  -- community-service runtime (19C)
    'server/api.lua',
}

client_scripts {
    'client/main.lua',
    'client/community_service.lua',
}

lua54 'yes'
