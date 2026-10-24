fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'PF Water Control - dry volumes and water quad control for out-of-bounds builds and submerged basements'
author 'Dom'
version '2.0.0'

client_scripts {
    'config.lua',
    'client.lua'
}

-- If you enable Config.CustomWaterFile, drop your water.xml in this resource
-- and uncomment the block below so LOAD_WATER_FROM_PATH can find it.
-- files {
--     'water.xml'
-- }
