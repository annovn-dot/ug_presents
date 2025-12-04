fx_version 'cerulean'
game 'gta5'

name 'ug_presents'
description 'Simple present system with ox_inventory, ox_target and ox_lib'
author 'You'
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config/*.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql'
}
