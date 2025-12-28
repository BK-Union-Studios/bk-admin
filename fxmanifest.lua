fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'BK Union Scripts'
description 'BK Union - Admin Tool'
version '1.0.2'

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

escrow_ignore {
    'config.lua',       
    'locales/*.lua'     
}

dependencies {
    'qbx_core',
    'oxmysql'
}
