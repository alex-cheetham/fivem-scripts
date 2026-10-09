fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'statewide_police'
author 'Statewide Roleplay'
description 'Statewide PD - police toolkit + AI patrol - traffic stops, ped stops, callouts, AI sheriff backup, SWAT, K9, partners, 58 call types, CAD board, wk_wars2x ALPR, pursuits, spikes, roadblocks, transport/tow/EMS/coroner/air, MDT, evidence'
version '2.2.0'

shared_scripts {
    'config.lua',
    'config_ai.lua',
    'config_calls.lua',
    'commands.lua',
}

client_scripts {
    'client/core.lua',
    'client/restraint.lua',
    'client/people.lua',
    'client/justice.lua',
    'client/traffic.lua',
    'client/evidence.lua',
    'client/menu.lua',
    'client/ai_core.lua',
    'client/ai_world.lua',
    'client/ai_places.lua',
    'client/ai_stops.lua',
    'client/ai_services.lua',
    'client/ai_partner.lua',
    'client/ai_pursuit.lua',
    'client/ai_team.lua',
    'client/ai_people.lua',
    'client/ai_callouts.lua',
    'client/ai_calls.lua',
    'client/ai_cad.lua',
    'client/ai_ui.lua',
}

server_scripts {
    'server/core.lua',
    'server/restraint.lua',
    'server/people.lua',
    'server/justice.lua',
    'server/traffic.lua',
    'server/evidence.lua',
    'server/commands.lua',
    'server/ai.lua',
    'server/ai_deep.lua',
    'server/ai_places.lua',
    'server/ai_people.lua',
    'server/ai_units.lua',
    'server/ai_calls.lua',
    'server/ai_cad.lua',
}

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/ai.css',
    'html/ai.js',
    'html/img/logo.png',
}
