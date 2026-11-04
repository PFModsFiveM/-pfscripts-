fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'PF Scripts'
description 'PF Government - Comprehensive City Government Framework'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    'client/main.lua',
    'client/nui.lua',
    'client/civil.lua',
    'client/infrastructure.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua',
    'server/core.lua',
    'server/schema.lua',
    'server/treasury.lua',
    'server/taxes.lua',
    'server/budgets.lua',
    'server/departments/core.lua',           -- department of a job, config, audit writer (15I)
    'server/departments/qualifications.lua', -- implied and granted qualifications (15I)
    'server/departments/shifts.lua',         -- shift rows from QBCore:Server:SetDuty (15I)
    'server/laws.lua',
    'server/licenses.lua',
    'server/utilities.lua',
    'server/bills.lua',
    'server/property_tax.lua', -- weekly property tax on owned houses (pfm-houses GetOwnedHouses)
    'server/businesses.lua',
    'server/registry_views.lua',
    'server/premises.lua',
    'server/delivery_zones.lua',
    'server/loans.lua',
    'server/employees.lua',
    'server/staff.lua',
    'server/audit.lua',
    'server/infrastructure.lua',
    'server/workorders.lua', -- municipal work orders from the district state (claims, unit proofs, payouts)
    'server/integrations.lua',
    'server/assistant_data.lua',
    'server/assistant_parser.lua',
    'server/assistant_tools.lua',
    'server/assistant.lua',
    'server/callbacks.lua',
    'server/civil.lua',
    'server/main.lua',
    'server/characters.lua', -- a deleted character's staff role, businesses and property records
    -- field apps on the tablet and the computer (pf-devices) and City Hall requests (pf-services)
    'server/apps/common.lua',
    'server/apps/fines.lua',
    'server/apps/inspections.lua',
    'server/apps/requests.lua',
    'server/apps/budget.lua',
    'server/apps/announcements.lua',
    'server/apps/setup.lua',
    'server/apps/register.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/rte.js',
    'html/rte.css',
    'html/games.js',
    'html/apps/gov.css',
    'html/apps/fines.js',
    'html/apps/inspections.js',
    'html/apps/requests.js',
    'html/apps/budget.js',
    'html/apps/announcements.js',
    'html/apps/setup.js',
    'html/apps/cityhall.js'
}

dependencies {
    'oxmysql',
    'pfm-core',
    'pf-computer'
}
