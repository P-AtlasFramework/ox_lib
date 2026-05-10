fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ox_lib'
author 'Atlas Framework'
description 'ox_lib drop-in compatibility shim — routes lib.* calls through atlas_core. Lets resources that require ox_lib run on Atlas without forking.'
version '0.1.0'

-- Resources consuming `@ox_lib/init.lua` get our shim instead. Real
-- ox_lib lives in Atlas_Study/ox_lib for reference, not ensured.
files {
    'init.lua',
}

shared_script 'init.lua'

server_scripts {
    'server.lua',
}

client_scripts {
    'client.lua',
}

dependencies {
    'atlas_core',
}
