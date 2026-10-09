---------------------------------------------------------------------------
-- AI PATROL (FivePD-style) - traffic stops, ped stops, callouts and AI units
-- Everything here can be changed. Restart the resource after editing.
---------------------------------------------------------------------------
Config.AI = {}

-- Keys (players can rebind them in Settings > Key Bindings > FiveM)
Config.AI.Keys = {
    computer = 'F10',    -- patrol computer: AI patrol on/off, current callout, request units, stats
    stop = 'LSHIFT',     -- in a police vehicle: pull over the vehicle in front (lights need to be on)
    interact = 'E',      -- tap next to someone you've stopped to talk to them. HOLD next to anyone on foot to stop them
    accept = 'Y',        -- accept an incoming callout (only does anything while a callout is popping up)
}
Config.AI.HoldToStop = 600          -- ms you hold the interact key to stop someone on foot

-- Traffic stops
Config.AI.NeedLights = true         -- emergency lights must be on to pull someone over
Config.AI.EmergencyOnly = true      -- only from emergency-class vehicles (police cars, sheriff, unmarked)
Config.AI.StopRange = 35.0          -- how far ahead the vehicle can be
Config.AI.AbandonDistance = 120.0   -- drive this far away and the stop ends (the driver leaves)

-- Callouts (only for officers who switch AI patrol on in the patrol computer)
Config.AI.FirstCallout = { 45, 90 }     -- seconds after going on patrol before the first callout
Config.AI.CalloutGap = { 90, 240 }      -- seconds between callouts once you are free again
Config.AI.OfferSeconds = 25             -- how long you have to accept (Y)
Config.AI.CalloutDistance = { 350, 1400 } -- metres from you that callouts happen
Config.AI.ArriveDistance = 70.0         -- you're "on scene" this close
Config.AI.LeaveSceneDistance = 400.0    -- leave this far after the scene is clear and the callout closes itself
Config.AI.SkipWhenPlayers = 0           -- 0 = callouts any time. e.g. 6 = no AI callouts while 6+ players are on duty as police

-- AI records kept in the MDT (people you've stopped). Oldest are removed past this.
Config.AI.MaxRecords = 600

-- Units you can request from the patrol computer
-- Your 2023 SLR sheriff pack (2023slrpackallblue) - make sure that resource is started before statewide_police
Config.AI.SheriffCars = { 'slr11sedan', 'slr16sedan', 'slr18sedan', 'slr181500', 'slr13utility', 'slr16utility', 'slr18suv', 'slr20utility' }
Config.AI.SheriffCarLivery = nil    -- set a livery number to force one (nil = whatever the car comes with)

-- peds = models used when no uniform has been saved for that unit (see "Uniforms" below)
-- max = how many of that unit you can have at once. weapons = what they carry.
Config.AI.Units = {
    backup    = { label = 'Backup unit',        vehicles = Config.AI.SheriffCars, peds = { 's_m_y_sheriff_01', 's_f_y_sheriff_01' }, crew = 2, siren = true, max = 3,
                  weapons = { 'WEAPON_COMBATPISTOL', 'WEAPON_CARBINERIFLE' }, armour = 100, accuracy = 55 },
    swat      = { label = 'SWAT team',          vehicles = { 'riot' }, peds = { 's_m_y_swat_01' }, crew = 4, siren = true, max = 1,
                  weapons = { 'WEAPON_CARBINERIFLE', 'WEAPON_SMG' }, armour = 200, accuracy = 70 },
    k9        = { label = 'K9 unit',            vehicles = Config.AI.SheriffCars, peds = { 's_m_y_sheriff_01' }, dog = 'a_c_shepherd', crew = 1, siren = true, max = 1,
                  weapons = { 'WEAPON_COMBATPISTOL' }, armour = 100, accuracy = 55 },
    transport = { label = 'Prisoner transport', vehicles = { 'slr181500', 'slr18suv', 'slr20utility' }, peds = { 's_m_y_sheriff_01' }, crew = 1, siren = false, max = 1,
                  weapons = { 'WEAPON_COMBATPISTOL' }, armour = 100, accuracy = 50 },
    roadblock = { label = 'Roadblock',          vehicles = Config.AI.SheriffCars, peds = { 's_m_y_sheriff_01' }, crew = 1, siren = true, max = 1,
                  weapons = { 'WEAPON_CARBINERIFLE' }, armour = 100, accuracy = 55 },
    spikes    = { label = 'Spike strip unit',   vehicles = Config.AI.SheriffCars, peds = { 's_m_y_sheriff_01' }, crew = 1, siren = true, max = 1,
                  weapons = { 'WEAPON_COMBATPISTOL' }, armour = 100, accuracy = 55 },
    partner   = { label = 'Partner',            peds = { 's_m_y_sheriff_01', 's_f_y_sheriff_01' }, max = 1,
                  weapons = { 'WEAPON_COMBATPISTOL', 'WEAPON_STUNGUN' }, armour = 100, accuracy = 60 },
    tow       = { label = 'Tow truck',          vehicles = { 'flatbed' }, peds = { 's_m_m_trucker_01', 's_m_y_xmech_02' }, crew = 1, siren = false, max = 1 },
    ems       = { label = 'Ambulance',          vehicles = { 'ambulance' }, peds = { 's_m_m_paramedic_01' }, crew = 2, siren = true, max = 1 },
    coroner   = { label = 'Coroner',            vehicles = { 'speedo', 'burrito3' }, peds = { 's_m_m_doctor_01', 's_m_m_scientist_01' }, crew = 1, siren = false, max = 1 },
    air       = { label = 'Air unit',           vehicles = { 'polmav' }, peds = { 's_m_y_pilot_01' }, crew = 1, siren = false, seconds = 300, max = 1 },
}
Config.AI.PoliceUnits = { backup = true, swat = true, k9 = true, transport = true, roadblock = true, spikes = true, partner = true, air = true }
-- Divisions you can pick in the patrol computer. More of the callouts that suit your division.
Config.AI.Divisions = {
    { key = 'patrol',    label = 'Patrol',          callouts = {} },
    { key = 'traffic',   label = 'Traffic',         callouts = { 'drunk_driver', 'speeder', 'stolen_vehicle', 'crash', 'hit_and_run', 'road_rage', 'abandoned', 'vehicle_theft' } },
    { key = 'highway',   label = 'Highway Patrol',  callouts = { 'speeder', 'drunk_driver', 'crash', 'stolen_vehicle', 'hit_and_run' } },
    { key = 'k9',        label = 'K9',              callouts = { 'drug_deal', 'wanted_person', 'suspicious', 'shoplifter', 'burglary' }, partner = 'dog' },
    { key = 'detective', label = 'Detectives',      callouts = { 'burglary', 'assault_report', 'vehicle_theft', 'robbery_report', 'missing_person' } },
    { key = 'swat',      label = 'SWAT',            callouts = { 'hostage', 'gang_shootout', 'armed_robbery', 'shots_fired' } },
}
Config.AI.DivisionBoost = 3.0       -- how much more likely your division's callouts are

-- Uniforms: staff save these in game from the patrol computer (Units tab > Uniforms - wear the outfit, then save it).
-- They're stored in data/uniforms.json. You can also write them here.
Config.AI.Uniforms = {}
Config.AI.UnitCooldown = 20         -- seconds between requests of the same unit

-- Pursuits
Config.AI.Pursuit = {
    PIT = true,              -- you can PIT the suspect (hit their back corner at a sensible speed)
    PITAfter = 20,           -- seconds into the pursuit before PITs are authorised
    PITChance = 0.8,         -- how often a good PIT works
    AIPIT = true,            -- AI backup can PIT too
    RollingBlock = true,     -- AI backup that gets in front slows them down
    SpikeLead = 12,          -- spike strips go this many seconds ahead of the suspect
    RoadblockLead = 16,
    SpikedSlow = true,       -- spiked cars can't go flat out
    TerminateAfter = 420,    -- seconds before the supervisor tells you to call it off
    DangerSpeed = 55.0,      -- m/s (about 123 mph) - supervisor warns about speed
}

-- Ped models used for drivers, suspects, victims and witnesses
Config.AI.Peds = {
    'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02', 'a_m_m_salton_01', 'a_m_m_salton_02', 'a_m_m_salton_03', 'a_m_y_methhead_01',
    'a_m_m_farmer_01', 'a_m_y_hippy_01', 'a_m_m_rurmeth_01', 'a_m_y_salton_01', 'a_m_m_eastsa_01', 'a_m_y_eastsa_02',
    'a_m_y_stwhi_01', 'a_m_y_stbla_02', 'a_m_m_skater_01', 'a_m_y_genstreet_01', 'a_m_y_genstreet_02', 'a_m_m_tramp_01',
    'a_f_m_salton_01', 'a_f_y_rurmeth_01', 'a_f_m_fatwhite_01', 'a_f_y_hippie_01', 'a_f_y_eastsa_03', 'a_f_m_eastsa_02',
    'a_f_y_genhot_01', 'a_f_y_scdressy_01', 'a_m_y_cyclist_01', 'a_m_m_trampbeac_01',
}
Config.AI.Gangs = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03', 'g_m_y_salvagoon_01', 'g_m_y_mexgoon_02', 'g_m_y_famca_01' }

-- Cars used in callouts
Config.AI.Cars = { 'emperor', 'regina', 'tornado', 'rancherxl', 'bfinjection', 'rebel', 'sadler', 'bison', 'picador', 'ingot',
    'peyote', 'manana', 'voodoo2', 'asea', 'primo', 'stanier', 'premier', 'buccaneer', 'blista', 'issi2', 'dloader', 'bodhi2' }
Config.AI.FastCars = { 'sultan', 'buffalo', 'dominator', 'gauntlet', 'elegy2', 'banshee', 'futo', 'penumbra', 'kuruma' }

-- Weapons armed suspects can have
Config.AI.SuspectGuns = { 'WEAPON_PISTOL', 'WEAPON_SNSPISTOL', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_MICROSMG', 'WEAPON_REVOLVER' }
Config.AI.SuspectMelee = { 'WEAPON_KNIFE', 'WEAPON_BAT', 'WEAPON_BOTTLE', 'WEAPON_CROWBAR', 'WEAPON_HAMMER' }

---------------------------------------------------------------------------
-- WHAT PEOPLE HAVE ON THEM (chance 0-1 for a normal member of the public)
-- Callouts make suspects far more likely to be carrying.
---------------------------------------------------------------------------
Config.AI.PersonItems = {
    { label = 'Wallet',                       chance = 0.85, legal = true },
    { label = 'Phone',                        chance = 0.9,  legal = true },
    { label = 'Car keys',                     chance = 0.5,  legal = true },
    { label = 'Cigarettes and lighter',       chance = 0.3,  legal = true },
    { label = 'Small bag of cannabis',        chance = 0.07, legal = false, drug = 'cannabis' },
    { label = 'Unmarked pills',               chance = 0.04, legal = false, drug = 'benzos' },
    { label = 'Bag of white powder',          chance = 0.03, legal = false, drug = 'cocaine' },
    { label = 'Crystal meth pipe',            chance = 0.03, legal = false, drug = 'meth' },
    { label = 'Lock picks',                   chance = 0.03, legal = false },
    { label = 'Knife',                        chance = 0.05, legal = false, weapon = 'WEAPON_KNIFE' },
    { label = 'Brass knuckles',               chance = 0.02, legal = false, weapon = 'WEAPON_KNUCKLE' },
    { label = 'Unregistered pistol',          chance = 0.02, legal = false, weapon = 'WEAPON_PISTOL' },
    { label = 'Stolen credit cards',          chance = 0.02, legal = false },
    { label = 'Roll of cash ($2,300)',        chance = 0.03, legal = false },
}

-- Chances for members of the public (callouts set their own)
Config.AI.Public = {
    warrant = 0.06, suspended = 0.06, expired = 0.05, noLicence = 0.04,
    drinking = 0.08, drunk = 0.04, drugs = 0.05,
    noId = 0.12,                -- not carrying ID
    flags = 0.06,               -- probation / gang / violent history flag
    priors = 0.25,              -- has old fines or arrests on file
}
Config.AI.Warrants = { 'Failure to appear in court', 'Unpaid fines', 'Probation violation', 'Burglary', 'Assault', 'Grand theft auto',
    'Possession with intent to supply', 'Domestic battery', 'Armed robbery', 'Vandalism', 'Shoplifting' }
Config.AI.Flags = { 'On probation', 'Known gang member', 'History of violence', 'Known drug user', 'Armed and dangerous', 'Mental health marker' }
Config.AI.Places = { 'home', 'work', 'the store', 'my mom\'s place', 'the bar', 'Sandy Shores', 'Grapeseed', 'Paleto Bay', 'Harmony',
    'the lake', 'the casino', 'a friend\'s house', 'the hospital', 'Los Santos', 'the gas station', 'the trailer park', 'church', 'the gym' }

---------------------------------------------------------------------------
-- CALLOUTS. weight = how often (higher = more). code 2 = urgent, 3 = lights & sirens.
-- Turn one off with enabled = false.
---------------------------------------------------------------------------
Config.AI.Callouts = {
    { key = 'stolen_vehicle',  title = 'Stolen vehicle',            code = 3, weight = 10, text = 'A vehicle reported stolen has been spotted in the area. Locate and stop it.' },
    { key = 'drunk_driver',    title = 'Possible drunk driver',     code = 2, weight = 10, text = 'Callers report a vehicle swerving across lanes.' },
    { key = 'speeder',         title = 'Reckless driver',           code = 2, weight = 8,  text = 'A vehicle is being driven at high speed through traffic.' },
    { key = 'shots_fired',     title = 'Shots fired',               code = 3, weight = 6,  text = 'Multiple callers report gunshots. Approach with caution.', team = true },
    { key = 'domestic',        title = 'Domestic disturbance',      code = 2, weight = 8,  text = 'Neighbours report shouting and a possible assault.' },
    { key = 'fight',           title = 'Fight in progress',         code = 3, weight = 8,  text = 'Two people are fighting in the street.' },
    { key = 'shoplifter',      title = 'Shoplifting',               code = 2, weight = 8,  text = 'A store reports a shoplifter who has just left on foot.' },
    { key = 'drunk_person',    title = 'Intoxicated person',        code = 2, weight = 8,  text = 'An intoxicated person is causing a nuisance.' },
    { key = 'suspicious',      title = 'Suspicious person',         code = 2, weight = 8,  text = 'A caller reports someone acting suspiciously.' },
    { key = 'crash',           title = 'Vehicle collision',         code = 3, weight = 8,  text = 'A vehicle has crashed. Possible injuries.' },
    { key = 'hit_and_run',     title = 'Hit and run',               code = 3, weight = 6,  text = 'A pedestrian has been struck and the vehicle failed to stop.' },
    { key = 'armed_robbery',   title = 'Armed robbery',             code = 3, weight = 5,  text = 'An armed robbery has just happened. The suspect is armed and leaving the scene.', team = true },
    { key = 'wanted_person',   title = 'Wanted person sighted',     code = 2, weight = 6,  text = 'A person with an active warrant has been seen in the area.' },
    { key = 'abandoned',       title = 'Abandoned vehicle',         code = 2, weight = 5,  text = 'A vehicle has been left blocking the road.' },
    { key = 'road_rage',       title = 'Road rage',                 code = 3, weight = 6,  text = 'Two drivers have stopped and are threatening each other.' },
    { key = 'trespass',        title = 'Trespasser refusing to leave', code = 2, weight = 5, text = 'A property owner wants someone removed who refuses to leave.' },
    { key = 'gang_shootout',   title = 'Armed gang members',        code = 3, weight = 3,  text = 'A group of armed gang members has been reported. Call for backup.', team = true },
}

---------------------------------------------------------------------------
-- WHAT PEOPLE SAY. %s is filled in (a place, a name...). Add as many lines as you like.
---------------------------------------------------------------------------
Config.AI.Lines = {
    greet_calm = { 'Hello officer, is something wrong?', 'Evening officer.', 'Hi. What\'s this about?', 'Hey officer, everything okay?' },
    greet_nervous = { 'Uh... hi officer. Did I do something?', 'Oh. Hi. Hey.', 'Is there a problem, officer?' },
    greet_hostile = { 'What do you want?', 'Seriously? Again?', 'Why are you bothering me?', 'I know my rights, man.' },
    greet_drunk = { 'Offisherrr! Heyyy...', 'Wha... what\'s going on?', 'Hey buddy! *hic*' },

    why_honest = { 'I think I was going a bit fast.', 'Was it my driving? I\'m sorry.', 'I guess I wasn\'t paying attention.' },
    why_unsure = { 'No idea, officer.', 'Not really, no.', 'Was I speeding? I didn\'t think I was.' },
    why_hostile = { 'Because you\'ve got nothing better to do?', 'You tell me.', 'Profiling, probably.' },

    where = { 'I\'m heading to %s.', 'Going to %s.', 'On my way to %s, officer.', 'Just heading to %s.' },
    where_nervous = { 'Uh... to %s. I think.', 'Just... around. %s maybe.', 'Nowhere really.' },
    from = { 'I\'ve just come from %s.', 'From %s.', 'Was at %s.' },

    drink_no = { 'No, not a drop.', 'No officer, I don\'t drink.', 'Nothing at all.' },
    drink_couple = { 'Just one beer with dinner.', 'Had a couple a while ago.', 'One drink, hours ago.' },
    drink_lots_honest = { 'Yeah... I\'ve had a few. I\'m sorry.', 'I won\'t lie, I\'ve been drinking.' },
    drink_lie = { 'No! Why would you ask that?', 'Just a soda, officer.', 'Nothing, I swear.' },
    drink_slurred = { 'Jusht... two? Maybe shix. *hic*', 'I\'m totally fine to drive, offisher.', 'Nooo... well, a lil bit.' },

    drugs_no = { 'No, I don\'t do drugs.', 'Never.', 'No officer.' },
    drugs_honest = { 'I smoked a little earlier...', 'Yeah, I took something earlier. I\'m sorry.' },
    drugs_lie = { 'No way. Not me.', 'What? No.', 'I\'m clean, man.' },

    illegal_no = { 'No, nothing.', 'Not that I know of.', 'Nothing illegal, officer.' },
    illegal_honest = { 'There\'s... something you should know about. I have %s.', 'I\'ll be honest, I\'ve got %s on me.' },
    illegal_lie = { 'No. Nothing.', 'Why would I have anything?', 'Nope, nothing at all.' },

    weapons_no = { 'No weapons.', 'No, nothing like that.', 'No officer.' },
    weapons_honest = { 'I have %s on me. I\'m not reaching for it.', 'Yes - %s. Just so you know.' },
    weapons_lie = { 'No.', 'Why would I carry a weapon?', 'Nope.' },

    owner_yes = { 'Yes, it\'s mine.', 'Yeah, it\'s my car.', 'It\'s mine, the papers are in the glovebox.' },
    owner_friend = { 'It\'s my friend\'s car. %s lent it to me.', 'It belongs to %s, they said I could borrow it.' },
    owner_lie = { 'Yeah, it\'s mine.', 'Of course it\'s mine.', 'Uh, yeah. Mine.' },

    name_give = { 'My name is %s.', 'It\'s %s.', '%s.' },
    name_refuse = { 'I don\'t have to tell you that.', 'Am I being detained?', 'I\'m not giving you my name.' },

    noid = { 'I left my ID at home, sorry.', 'I don\'t have it on me.', 'My wallet\'s at home.' },
    hand_id = { 'Here you go.', 'Here\'s my licence.', 'Sure, here.' },

    consent_yes = { 'Go ahead, I\'ve got nothing to hide.', 'Sure, knock yourself out.', 'Yeah, fine.' },
    consent_no = { 'No, I don\'t consent to any searches.', 'Not without a warrant.', 'No. I know my rights.' },

    calm_ok = { 'Alright... alright. Sorry.', 'Okay, I\'m calm.', 'Fine.' },
    calm_no = { 'Don\'t tell me to calm down!', 'I am calm!', 'Whatever, man.' },

    out_ok = { 'Okay, okay.', 'Alright, I\'m getting out.', 'Sure.' },
    out_no = { 'Why do I need to get out?', 'I\'m not getting out.' },

    cited_ok = { 'Okay. Thank you officer.', 'Fair enough.', 'I understand.' },
    cited_bad = { 'This is ridiculous.', 'Whatever. Are we done?', 'Great. Just great.', 'I\'ll see you in court.' },
    warned = { 'Thank you, officer. It won\'t happen again.', 'Thanks, I appreciate it.', 'Thank you. Have a good one.' },
    released = { 'Thanks officer.', 'Have a good day.', 'Am I free to go? Great.' },

    cuffed_calm = { 'Okay, okay! I\'m not resisting.', 'Is this really necessary?', 'Alright.' },
    cuffed_angry = { 'Get off me!', 'This is harassment!', 'You\'re making a big mistake!', 'I want my lawyer!' },
    surrender = { 'Okay! Okay! Don\'t shoot!', 'I give up!', 'Alright, you got me!' },
    flee = { 'I\'m outta here!', 'Not today!', 'Catch me if you can!' },
    fight = { 'You\'re not taking me in!', 'Back off, pig!', 'Come on then!' },

    -- callout witnesses and victims (what happened?)
    story_domestic_victim = { 'He just lost it and started screaming at me. Then he shoved me.', 'We were arguing and she hit me.', 'I just want them to leave.' },
    story_domestic_suspect = { 'It\'s just a disagreement, it\'s none of your business.', 'Nothing happened. We\'re fine.', 'She\'s lying, I never touched her.' },
    story_fight = { 'He started it! He came at me!', 'He owes me money and wouldn\'t pay.', 'I was just defending myself.' },
    story_shop = { 'I paid for everything, I swear.', 'I was just walking home.', 'What shop?' },
    story_trespass = { 'This is public land, I can be here.', 'I\'m not leaving.', 'I\'m just resting here, leave me alone.' },
    story_victim_hit = { 'A car came out of nowhere and hit me... it didn\'t stop.', 'My leg... the car just drove off!' },
    story_crash = { 'I lost control, the road was slippery.', 'Something ran out in front of me.', 'I don\'t know what happened, it was so fast.' },
    story_roadrage = { 'He cut me up and then got out swinging!', 'He\'s been tailgating me for miles!' },
    story_witness = { 'They went that way!', 'I saw everything, it was crazy.', 'I just called it in, that\'s all I know.' },
    story_none = { 'I don\'t know anything about that.', 'I didn\'t see anything.', 'Nothing to say.' },
}

---------------------------------------------------------------------------
-- STATEWIDE PD branding
---------------------------------------------------------------------------
Config.AI.Brand = 'Statewide PD'
Config.AI.BrandLong = 'Statewide Police Department'

---------------------------------------------------------------------------
-- EXPERIENCE & RANKS (shown in the patrol computer)
---------------------------------------------------------------------------
Config.AI.XP = { stops = 5, citations = 10, warnings = 4, arrests = 25, callouts = 30, pursuits = 10, seized = 5,
    convictions = 20, cases = 60, lies = 3, reports = 15 }
Config.AI.Ranks = {
    { label = 'Probationary Officer', xp = 0 },
    { label = 'Officer', xp = 300 },
    { label = 'Senior Officer', xp = 900 },
    { label = 'Corporal', xp = 2000 },
    { label = 'Sergeant', xp = 4000 },
    { label = 'Lieutenant', xp = 7500 },
    { label = 'Captain', xp = 12000 },
    { label = 'Commander', xp = 20000 },
}

---------------------------------------------------------------------------
-- COURT & REPORTS
---------------------------------------------------------------------------
Config.AI.CourtMinutes = 3      -- after you file an arrest report, the court decides this many minutes later
Config.AI.ReportWindow = 900    -- seconds you have to file a report before the case goes to court without one (weaker)
Config.AI.WarrantSeconds = 45   -- how long the judge takes to decide on a warrant

-- On-view incidents: things that happen in front of you while you patrol (between callouts)
Config.AI.OnView = { enabled = true, every = { 150, 360 }, chance = 0.6 }

-- K9 unit

-- New callouts
local more = {
    { key = 'hostage',        title = 'Hostage situation',         code = 3, weight = 2,  text = 'An armed suspect is holding someone at gunpoint. Negotiate - don\'t rush in.', team = true },
    { key = 'mugging',        title = 'Robbery in progress',       code = 3, weight = 6,  text = 'A pedestrian is being robbed right now.' },
    { key = 'drug_deal',      title = 'Drug deal',                 code = 2, weight = 6,  text = 'A caller reports what looks like a drug deal on the street.' },
    { key = 'burglary',       title = 'Burglary report',           code = 2, weight = 6,  text = 'A homeowner has come back to find their home broken into. Investigate.', case = true },
    { key = 'assault_report', title = 'Assault report',            code = 2, weight = 5,  text = 'Someone has been assaulted and the attacker has left. Investigate.', case = true },
    { key = 'vehicle_theft',  title = 'Vehicle theft report',      code = 2, weight = 5,  text = 'A car has just been stolen. Get the details and find it.', case = true },
    { key = 'robbery_report', title = 'Store robbery (suspect gone)', code = 2, weight = 4, text = 'A store was robbed a few minutes ago. Check the CCTV and find the suspect.', case = true },
    { key = 'missing_person', title = 'Missing person',            code = 2, weight = 4,  text = 'A confused elderly person has wandered off. Find them and bring them back.' },
}
for _, c in ipairs(more) do table.insert(Config.AI.Callouts, c) end

-- Investigations: who did it, and the evidence left behind. reveals = what the clue tells you.
-- clue text: %s is filled with the detail it reveals.
Config.AI.Cases = {
    burglary = { title = 'Burglary', profile = 'burglar', mode = 'foot', clues = {
        { model = 'w_me_crowbar', label = 'Crowbar by the door', reveals = 'look', text = 'Fibres on the crowbar. Neighbour saw someone %s nearby.' },
        { model = 'prop_ld_wallet_01', label = 'Dropped wallet', reveals = 'name', text = 'A wallet with an ID card in the name of %s.' },
        { model = 'prop_cs_cardbox_01', label = 'Dropped box of stolen items', reveals = 'age', text = 'Items from the house. Shopkeeper sold them to someone in their %s.' },
    } },
    assault_report = { title = 'Assault', profile = 'assailant', mode = 'foot', clues = {
        { model = 'prop_amb_beer_bottle', label = 'Bottle with blood on it', reveals = 'gender', text = 'Bottle used in the attack. DNA says: %s.' },
        { model = 'prop_npc_phone', label = 'Phone dropped by the attacker', reveals = 'name', text = 'The phone belongs to %s.' },
    } },
    vehicle_theft = { title = 'Vehicle theft', profile = 'carthief', mode = 'vehicle', stolen = true, clues = {
        { model = 'p_car_keys_01', label = 'Spare key fob', reveals = 'plate', text = 'The owner\'s paperwork: plate %s.' },
        { model = 'prop_ld_flow_bottle', label = 'Drink can left by the thief', reveals = 'look', text = 'Prints match someone %s seen on a doorbell camera.' },
    } },
    robbery_report = { title = 'Store robbery', profile = 'robber', mode = 'vehicle', clues = {
        { model = 'prop_laptop_01a', label = 'CCTV footage', reveals = 'look', text = 'CCTV shows the robber %s leaving in a vehicle.' },
        { model = 'prop_cs_package_01', label = 'Dropped bag of cash', reveals = 'colour', text = 'A dye pack went off - the getaway car was %s.' },
        { model = 'p_ld_id_card_01', label = 'ID card on the floor', reveals = 'name', text = 'An ID card in the name of %s.' },
    } },
}

-- What each ped model looks like (for descriptions). Anything missing says "casual clothes".
Config.AI.Looks = {
    a_m_m_hillbilly_01 = 'a plaid shirt and jeans', a_m_m_hillbilly_02 = 'a vest and dirty jeans', a_m_m_salton_01 = 'a cap and work shirt',
    a_m_m_salton_02 = 'a checked shirt', a_m_m_salton_03 = 'a check shirt and cap', a_m_y_methhead_01 = 'a grubby tank top',
    a_m_m_farmer_01 = 'overalls and a cap', a_m_y_hippy_01 = 'long hair and a loose shirt', a_m_m_rurmeth_01 = 'a dirty vest',
    a_m_y_salton_01 = 'a hoodie', a_m_m_eastsa_01 = 'a polo shirt', a_m_y_eastsa_02 = 'a basketball top', a_m_y_stwhi_01 = 'a tracksuit',
    a_m_y_stbla_02 = 'a white tee and chain', a_m_m_skater_01 = 'skater clothes and a cap', a_m_y_genstreet_01 = 'a hoodie and jeans',
    a_m_y_genstreet_02 = 'a jacket and jeans', a_m_m_tramp_01 = 'scruffy layered clothes', a_m_y_cyclist_01 = 'cycling gear', a_m_m_trampbeac_01 = 'shorts and no shoes',
    a_f_m_salton_01 = 'a floral top', a_f_y_rurmeth_01 = 'a vest top and shorts', a_f_m_fatwhite_01 = 'a t-shirt and leggings',
    a_f_y_hippie_01 = 'a long skirt', a_f_y_eastsa_03 = 'a crop top', a_f_m_eastsa_02 = 'a cardigan', a_f_y_genhot_01 = 'a dress and sunglasses',
    a_f_y_scdressy_01 = 'a smart dress',
}

---------------------------------------------------------------------------
-- MORE THINGS PEOPLE SAY
---------------------------------------------------------------------------
local L = Config.AI.Lines
L.where_who = { 'Meeting my friend %s.', 'Seeing %s, a buddy of mine.', 'My cousin %s.' }
L.where_who_vague = { 'Just... a friend.', 'Does it matter?', 'Nobody you\'d know.' }
L.where_why = { 'Just hanging out.', 'Dinner.', 'Picking something up.', 'Work stuff.' }
L.where_why_vague = { 'Just... stuff.', 'Why do you need to know that?', 'I don\'t know, hanging out I guess.' }
L.from_long = { 'A couple of hours.', 'Not long, half an hour maybe.', 'Most of the afternoon.' }
L.from_long_bar = { 'A few hours... we were watching the game.', 'All evening, it was a birthday thing.' }
L.drink_count_low = { 'Just the one.', 'One beer, that\'s it.', 'Two, tops. Hours ago.' }
L.drink_count_high = { 'Maybe... %s? I lost count.', 'About %s beers. I know, I know.' }
L.drink_when_recent = { 'Like... twenty minutes ago?', 'Just before I left.', 'I finished my last one in the parking lot.' }
L.drink_when_earlier = { 'Hours ago, with lunch.', 'Earlier this afternoon.' }
L.drugs_what = { 'Just some %s, a few hours ago.', 'A bit of %s earlier. Not much.' }
L.illegal_again_hold = { 'I told you. No.', 'Nothing! Why do you keep asking?', 'I said no, man.' }
L.owner_name_self = { 'It\'s me. %s.', 'Me - %s. It\'s on the papers.' }
L.owner_name_right = { 'It\'s %s\'s car.', '%s. They lent it to me.' }
L.owner_name_wrong = { 'It\'s... uh... John? John something.', 'My buddy\'s. I don\'t know his last name.', 'Why does that matter?' }
L.honest_ok = { 'I am being honest.', 'Sure, no problem.', 'I\'ve got nothing to hide, officer.' }
L.honest_guilty = { 'I... yeah. Okay.', 'Look, I\'m trying here.', 'I am being honest! Mostly.' }
L.anything_none = { 'No, nothing.', 'I don\'t know what you mean.', 'There\'s nothing to tell.' }
L.anything_lie = { 'No. Nothing.', 'I don\'t have anything to say.', 'Am I being detained?' }
L.confess_item = { 'Okay... okay. I\'ve got %s on me. I\'m sorry.', 'Fine. There\'s %s. Please go easy on me.' }
L.confess_warrant = { 'Look... I know there\'s a warrant. I was going to sort it out.', 'Yeah, I missed my court date. I know.' }
L.warrant_none = { 'A warrant? For what?', 'I don\'t have any warrants.' }
L.warrant_admit = { 'Yeah... I know. I was going to hand myself in.', 'I know about it. I panicked.' }
L.warrant_deny = { 'That\'s not me. You\'ve got the wrong person.', 'No way. That\'s a mistake.' }
L.confront_admit = { 'Alright, alright. I lied. I\'m sorry.', 'Okay, you got me.', 'I panicked. I\'m sorry.' }
L.confront_angry = { 'Your machine\'s broken!', 'This is a set-up!', 'I\'m not saying anything else.' }
L.confront_deny = { 'I don\'t know what to tell you.', 'That\'s not possible.', 'I told you the truth.' }
L.nego_good = { 'I\'m listening...', 'Okay. Okay. Keep talking.', 'You promise?', 'I don\'t want anyone to get hurt...' }
L.nego_bad = { 'Back off! I mean it!', 'Don\'t come any closer!', 'You\'re lying to me!', 'Shut up! Just shut up!' }
L.nego_release = { 'Okay... okay. I\'m letting them go. Don\'t shoot.', 'Fine! Here! I\'m done...' }
L.nego_snap = { 'That\'s it! I\'m done talking!', 'You did this!' }
L.statement_burglary = { 'I got home and the back door was smashed in. They took my TV and jewellery.', 'Someone broke in while I was at work.' }
L.statement_assault_report = { 'They came out of nowhere and hit me with a bottle.', 'We argued and they punched me, then ran off.' }
L.statement_vehicle_theft = { 'I left it running for one minute and it was gone!', 'Someone took my car right off the driveway.' }
L.statement_robbery_report = { 'They pointed a gun at me and took the cash drawer.', 'They threatened me and ran out with the money.' }
L.statement_desc = { 'They were %s.', 'I saw them - %s.', 'What I remember: %s.' }
L.story_missing = { 'Where... where am I? I need to get home.', 'Have you seen my husband?', 'I was just going to the shop...' }
L.story_mugged = { 'He grabbed my bag and ran!', 'They took my wallet and my phone!' }
L.story_hostage = { 'Please help me!', 'Please... I don\'t want to die!' }
Config.AI.DefaultCallsign = '1-ADAM-12'   -- used when an officer has no unit number set

---------------------------------------------------------------------------
-- PEOPLE (Phase 2): memory, emotions, body language, reaching, languages, crisis calls,
-- children, interfering passengers, bystanders filming, bail/probation/parole, complaints
---------------------------------------------------------------------------
Config.AI.People = {
    RepeatChance = 0.12,      -- chance a new person is someone you (or the force) have dealt with before
    MaxKnown = 400,           -- people remembered between sessions (data/known.json)
    Parole = 0.07, Probation = 0.14, Bail = 0.07,   -- of people with a record
    LanguageChance = 0.07,    -- doesn't speak English (use the interpreter line)
    Languages = { 'Spanish', 'Portuguese', 'Vietnamese', 'Korean', 'Russian', 'Arabic' },
    FalseCue = 0.18,          -- innocent people showing nervous body language
    ReachArmed = 0.22, ReachInnocent = 0.05,   -- reaching for something during a stop
    ChildChance = 0.10,       -- a child in the car
    ChildMinutes = 6,         -- arrest a parent and leave the child this long = neglect complaint
    InterfereChance = 0.30,   -- angry passengers who get out and interfere
    FilmingChance = 0.35,     -- a bystander films your stop (in town)
    ReviewMinutes = 10,       -- Internal Affairs decides a complaint after this long
    SustainedXP = 60,         -- XP lost for a sustained complaint
}
Config.AI.XP.deescalations = 40
Config.AI.XP.commendations = 25

-- Units for people
Config.AI.Units.crisis = { label = 'Mental health team', vehicles = { 'speedo', 'burrito3' }, peds = { 's_m_m_doctor_01', 's_f_y_scrubs_01' }, crew = 2, siren = false, max = 1 }
Config.AI.Units.cps    = { label = 'Child & Family Services', vehicles = { 'asea', 'fugitive' }, peds = { 'a_f_y_business_02', 'a_m_y_business_02' }, crew = 1, siren = false, max = 1 }

table.insert(Config.AI.Callouts, { key = 'crisis', title = 'Person in crisis', code = 2, weight = 4,
    text = 'A caller is worried about someone who is very distressed and acting erratically. They may be holding a knife. Slow down, talk, and get them help.' })
for _, d in ipairs(Config.AI.Divisions) do
    if d.key == 'patrol' then d.callouts[#d.callouts + 1] = 'crisis' end
end

L.lang_spanish = { 'Lo siento, no hablo inglés.', '¿Qué? No entiendo...', 'No hablo inglés, señor.' }
L.lang_portuguese = { 'Desculpe, não falo inglês.', 'Não entendo...' }
L.lang_vietnamese = { 'Xin lỗi, tôi không nói được tiếng Anh.', 'Tôi không hiểu...' }
L.lang_korean = { '죄송해요, 영어를 못해요.', '이해가 안 돼요...' }
L.lang_russian = { 'Извините, я не говорю по-английски.', 'Я не понимаю...' }
L.lang_arabic = { 'آسف، لا أتكلم الإنجليزية', 'لا أفهم...' }
L.lang_thanks = { '(through the interpreter) Thank you. Yes, I understand now.', '(through the interpreter) Okay. What do you need?' }
L.reach_start = { 'Hang on, let me just...', 'One second...', 'It\'s in here somewhere...' }
L.reach_drop = { 'Okay! Okay! It\'s on the floor!', 'Don\'t shoot! I\'m dropping it!' }
L.reach_freeze = { 'Whoa! Whoa! It\'s just my wallet!', 'It\'s my phone! Don\'t shoot!', 'I was getting my ID! Please!' }
L.reach_wallet = { 'Here\'s my licence.', 'Here you go, my ID.' }
L.reach_phone = { 'I\'m just calling my wife to say I\'ll be late.', 'Sorry - I was going to record this.' }
L.backoff_ok = { 'Fine. Whatever.', 'Okay, okay, I\'m going.', 'Alright, I\'m getting back in.' }
L.backoff_no = { 'It\'s a free country!', 'I\'m not going anywhere - you can\'t treat people like this!', 'I\'m filming this!' }
L.interfere = { 'Why are you harassing them?!', 'What did they even do?!', 'This is ridiculous!', 'I know my rights!', 'Leave them alone!' }
L.crisis_good = { 'You... you actually want to help?', 'Okay... I\'m listening.', 'Nobody ever listens to me...', 'I just want it all to stop for a minute...' }
L.crisis_bad = { 'Stop shouting at me!', 'Get away from me!', 'You don\'t care! Nobody does!', 'Stay back!' }
L.crisis_agree = { 'Okay... okay. I\'ll talk to someone.', 'I think... I think I need help. Yeah.' }
L.crisis_snap = { 'Leave me ALONE!', 'You\'re just like the rest of them!' }
L.crisis_thanks = { 'Thank you... for being patient with me.', 'Thanks for not giving up on me.' }
L.story_crisis = { 'Everything is too loud... I can\'t think.', 'Why won\'t everyone just leave me alone?', 'I don\'t know what to do anymore.' }
L.known_you = { 'Oh great. You again.', 'Seriously? Not you again.', 'Every time. It\'s always you.' }

---------------------------------------------------------------------------
-- PLACES: where callouts happen
--   Shops come from statewide_shops, gas stations from statewide_fuel, houses from statewide_housing
--   (empty houses are used as suspects' addresses - police can force the door).
--   Staff can add more in game: patrol computer > Places (stand there, pick the type, save).
---------------------------------------------------------------------------
Config.AI.PlaceRange = { 250, 1800 }   -- metres from you a callout prefers
Config.AI.PlaceMaxRange = 4500         -- nothing in range? the nearest place up to this far
Config.AI.PlaceCooldown = 900          -- seconds before the same place is used again

Config.AI.PlaceTypes = {
    { key = 'store',    label = 'Convenience store (inside, at the counter)' },
    { key = 'liquor',   label = 'Liquor store (inside, at the counter)' },
    { key = 'gas',      label = 'Gas station forecourt' },
    { key = 'hardware', label = 'Hardware store (counter)' },
    { key = 'diner',    label = 'Diner / takeaway (counter)' },
    { key = 'house',    label = 'House (from statewide_housing)', auto = true },
    { key = 'bar',      label = 'Bar / pub (outside the door)' },
    { key = 'lot',      label = 'Parking lot / yard' },
    { key = 'trailer',  label = 'Trailer park' },
    { key = 'park',     label = 'Park / open area' },
    { key = 'street',   label = 'Street corner / sidewalk' },
    { key = 'business', label = 'Business (outside)' },
}

-- Which places each callout uses (first match nearby wins; nothing nearby = a spot on the road like before)
Config.AI.CalloutPlaces = {
    armed_robbery = { 'store', 'liquor', 'gas' },
    shoplifter = { 'store', 'liquor', 'hardware' },
    robbery_report = { 'store', 'liquor', 'gas' },
    mugging = { 'street', 'lot', 'park' },
    burglary = { 'house' },
    assault_report = { 'bar', 'street', 'lot' },
    vehicle_theft = { 'lot', 'house', 'gas', 'business' },
    domestic = { 'house', 'trailer' },
    wanted_person = { 'house', 'trailer' },
    warrant = { 'house' },
    hostage = { 'store', 'liquor', 'house' },
    drunk_person = { 'bar', 'street', 'gas' },
    fight = { 'bar', 'lot', 'diner' },
    drug_deal = { 'lot', 'trailer', 'park' },
    gang_shootout = { 'trailer', 'lot' },
    trespass = { 'house', 'business', 'lot' },
    suspicious = { 'lot', 'business', 'store', 'house' },
    crisis = { 'park', 'street', 'lot', 'gas' },
    shots_fired = { 'trailer', 'house', 'lot', 'bar' },
    missing_person = { 'park', 'street' },
}

-- Built-in Blaine County places (vanilla map). Check them on your map and add your own in game.
Config.AI.PlaceList = {
    { type = 'liquor',  label = 'Liquor Ace, Sandy Shores', pos = vector4(1392.71, 3606.31, 34.98, 199.0) },
    { type = 'bar',     label = 'Yellow Jack Inn', pos = vector4(1987.92, 3050.30, 47.21, 238.0) },
    { type = 'trailer', label = 'Stab City', pos = vector4(65.80, 3698.20, 39.75, 0.0) },
    { type = 'trailer', label = 'Sandy Shores trailers', pos = vector4(1975.20, 3818.10, 33.43, 30.0) },
    { type = 'lot',     label = 'Sandy Shores Airfield', pos = vector4(1730.20, 3307.30, 41.22, 195.0) },
    { type = 'lot',     label = 'O\'Neil Ranch, Grapeseed', pos = vector4(2416.10, 4993.40, 46.22, 135.0) },
    { type = 'business', label = 'Motor Motel, Harmony', pos = vector4(321.50, 2623.50, 44.50, 30.0) },
}

-- Used only if statewide_shops isn't running
Config.AI.FallbackShops = {
    { label = '24/7 Sandy Shores', kind = 'store', coords = vector4(1959.82, 3740.48, 32.34, 301.57) },
    { label = '24/7 Route 68', kind = 'store', coords = vector4(549.13, 2670.85, 42.16, 99.39) },
    { label = '24/7 Senora Fwy', kind = 'store', coords = vector4(2677.47, 3279.76, 55.24, 335.08) },
    { label = '24/7 Mount Chiliad', kind = 'store', coords = vector4(1728.07, 6415.63, 35.04, 242.95) },
    { label = 'LTD Grapeseed', kind = 'store', coords = vector4(1697.87, 4922.96, 42.06, 324.71) },
    { label = 'Scoops Liquor, Route 68', kind = 'liquor', coords = vector4(1165.17, 2710.88, 38.16, 179.43) },
}

L.story_robbery_witness = { 'He had a gun! He pointed it right at the cashier!', 'I just came in for milk... he was screaming at everyone.', 'Is he gone? Please tell me he\'s gone.' }
