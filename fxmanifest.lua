fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'BK Union Scripts'
description 'BK Union Admin Tool – Modern, lightweight admin menu for FiveM'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'locales/en.lua',
    'locales/de.lua',
}

client_scripts {
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/ui.js',
}

dependencies {
    'qbx_core',
    'oxmysql'
}