fx_version 'cerulean'
game 'gta5'
lua54 'yes'
this_is_a_map 'yes'

description 'PF Elevator Script'
author 'Dom'

client_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'client.lua'
}

server_scripts {
    'config.lua',
    'server.lua'
}

files {
    'stream/elevator.ymap',
    'stream/pf_elevator.ytyp',
    'stream/pf_elevatormo.ydr',
    'stream/_manifest.ymf'
}

data_file 'DLC_ITYP_REQUEST' 'stream/pf_elevator.ytyp'
