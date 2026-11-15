-- pf-hud: the player HUD. Its look (the gauges, the framed minimap, the 3D rev dial, the radar tuner) is ported from
-- WHIP (its whip_core/ resource), Copyright (c) 2026 Whippy, LGPL-3.0, modified for PF: see NOTICE.md, COPYING.LESSER and COPYING.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_fxv2_oal 'yes'
author 'Project Sloth / PF (HUD look ported from WHIP by Whippy)'
description 'Player HUD: gauges, framed minimap, 3D vehicle dial'
version '4.0.0'

shared_scripts {
    '@pfm-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua',
    'config.lua',
    'uiconfig.lua'
}

client_scripts {
    '@pfm-ui/lib/pad_bridge.lua', -- controller support in the menu and layout editor (works without pfm-ui running)
    'client/prefs.lua',
    'client/radar.lua',
    'client/skin.lua',
    'client/radar_tuner.lua',
    'client/dial.lua',
    'client.lua',
}
server_script 'server.lua'

ui_page 'html/index.html'

-- html/preview.html is a browser preview with mock data and is deliberately not listed.
files {
    'html/index.html',
    'html/app.js',
    'html/ifruit.png',
    'html/css/*.css',
    'html/js/*.js',
    'html/js/vehicle_hud/*.js',
    'html/js/vehicle_hud/vendor/*.js',
    'html/js/vehicle_hud/fonts/*.woff2',
    'html/fonts/*.woff2',
    'uiconfig.lua',
}

-- stream/ (Legacy) and stream_enhanced/ (Enhanced): WHIP's minimap frame, ring, mask and disc art, renamed pf*.ytd.
-- The dark radar tiles are pfm-media-map's (Rockstar-derived, not in this public resource).
