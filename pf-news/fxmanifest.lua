fx_version 'cerulean'
game 'gta5'

author 'PFMods'
description 'PF News: Weazel News. City Desk articles from city events, newsroom leads, reporter stories with review, paid ads; one reader UI for the News app and the news.ls website'
version '1.0.0'

dependencies {
    'pfm-core',
    'pf-devices',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@pfm-banking/payouts.lua', -- PFPayout: reporter bonuses and ad payments go through the money ledger
    'config.lua',
    '@pf-services/shared/catalog.lua', -- kind labels when pf-services is not running yet
    'server/util.lua',
    'server/schema.lua',
    'server/presets.lua',
    'server/articles.lua',
    'server/leads.lua',
    'server/auto.lua',
    'server/ads.lua',
    'server/pay.lua',
    'server/apps.lua',
    'server/main.lua',
}

-- No ui_page: both shells load these through pf-devices.
files {
    'html/news_ui.js',
    'html/newsroom.js',
    'html/news.css',
}

lua54 'yes'
