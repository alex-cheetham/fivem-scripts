---------------------------------------------------------------------------
-- PHASE 3: MORE CALLS, REALISTIC DISPATCH (CAD), TIME / WEATHER / AREA, wk_wars2x
-- Everything here can be changed. Restart the resource after editing.
---------------------------------------------------------------------------
local AI = Config.AI
local L = AI.Lines

---------------------------------------------------------------------------
-- DISPATCH (CAD)
---------------------------------------------------------------------------
Config.AI.CAD = {
    Prefix = 'SW',                 -- incident numbers look like SW261009-0042
    Board = true,                  -- county-wide calls board in the patrol computer (CAD tab)
    BoardMax = 12,                 -- calls on the board at once
    BoardEvery = { 45, 120 },      -- seconds between new calls appearing on the board
    OtherUnitsTake = { 120, 420 }, -- seconds before another (AI) unit picks up a call nobody took
    OtherUnitsClear = { 300, 900 },-- seconds other units spend on a call
    Updates = true,                -- caller updates come over the radio while you're en route
    OtherUnits = { '1-ADAM-4', '1-ADAM-22', '2-LINCOLN-7', '3-BOY-11', '4-MARY-2', '6-TOM-31', '7-KING-9', '9-NORA-5',
        'SASP 512', 'SASP 518', 'BCSO 2S14', 'BCSO 3S21', 'BCSO 4S8', 'BCSO K9-3', 'BCSO TRF-6' },
    Areas = { 'Sandy Shores', 'Grapeseed', 'Paleto Bay', 'Harmony', 'Grand Senora Desert', 'Mount Chiliad', 'Route 68', 'Alamo Sea',
        'Davis', 'Strawberry', 'Vespucci', 'Mirror Park', 'Del Perro', 'La Mesa', 'Rancho', 'Chumash', 'Great Chaparral', 'Stab City' },
}

-- Nature codes, priorities and caller updates for the original calls
-- prio: 1 = life in danger (lights & sirens), 2 = urgent, 3 = routine
local ORIGINAL = {
    stolen_vehicle = { nature = '10851 VC', prio = 2, notes = { 'Owner states the vehicle has a full tank and a child seat in the back.', 'LoJack hit pinging in your area.' } },
    drunk_driver   = { nature = '23152 VC', prio = 2, notes = { 'RP is following the vehicle. Says it nearly hit the median twice.', 'Second caller: vehicle has no headlights on.' }, night = 2.2, day = 0.5 },
    speeder        = { nature = '23103 VC', prio = 2, notes = { 'RP estimates 100+ mph weaving between lanes.' } },
    shots_fired    = { nature = '246.3 PC', prio = 1, notes = { 'Multiple callers - between 3 and 6 shots.', 'ShotSpotter activation in the area.' }, night = 1.8, city = 1.3 },
    domestic       = { nature = '273.5 PC', prio = 1, notes = { 'RP can hear a female screaming. Possible children in the house.', 'History of DV calls at this address.' }, night = 1.5 },
    fight          = { nature = '415 PC',   prio = 1, notes = { 'Now a crowd gathering.', 'One party may have a bottle.' }, night = 1.6 },
    shoplifter     = { nature = '484 PC',   prio = 3, notes = { 'Loss prevention has the suspect on camera.' }, day = 1.6, night = 0.4 },
    drunk_person   = { nature = '647(f) PC',prio = 3, notes = { 'Subject is stumbling into the road.' }, night = 1.8 },
    suspicious     = { nature = 'Suspicious person', prio = 3, notes = { 'RP says they\'ve been checking car door handles.' }, night = 1.5 },
    crash          = { nature = '20001 VC / 11-80', prio = 1, notes = { 'Fire is staging nearby.', 'One occupant may be trapped.' }, rain = 2.5 },
    hit_and_run    = { nature = '20001 VC', prio = 1, notes = { 'Witness got a partial plate.', 'Suspect vehicle has front-end damage.' }, rain = 1.5, night = 1.3 },
    armed_robbery  = { nature = '211 PC',   prio = 1, notes = { 'Clerk hit the panic alarm.', 'Suspect described as wearing a dark hoodie.' }, night = 1.6 },
    wanted_person  = { nature = 'Warrant service', prio = 2 },
    abandoned      = { nature = '22523 VC', prio = 3 },
    road_rage      = { nature = '245 PC',   prio = 1, notes = { 'One driver may have a bat.' } },
    trespass       = { nature = '602 PC',   prio = 3 },
    gang_shootout  = { nature = '417 PC',   prio = 1, notes = { 'Callers report at least one rifle.' }, city = 1.6, county = 0.7, night = 1.4 },
    hostage        = { nature = '207 PC / 417', prio = 1, notes = { 'Negotiator is on standby.' } },
    mugging        = { nature = '211 PC',   prio = 1, night = 1.5, city = 1.3 },
    drug_deal      = { nature = '11352 HS', prio = 3, night = 1.4 },
    burglary       = { nature = '459 PC',   prio = 3, day = 1.3 },
    assault_report = { nature = '242 PC',   prio = 3 },
    vehicle_theft  = { nature = '10851 VC', prio = 3 },
    robbery_report = { nature = '211 PC',   prio = 2 },
    missing_person = { nature = 'Missing person (at risk)', prio = 2 },
    crisis         = { nature = '5150 WIC', prio = 2 },
}
for _, c in ipairs(AI.Callouts) do
    local o = ORIGINAL[c.key]
    if o then for k, v in pairs(o) do if c[k] == nil then c[k] = v end end end
end

---------------------------------------------------------------------------
-- NEW CALLS
--   nature = the CAD / penal code, prio 1-3, notes = caller updates while you drive
--   units = units dispatch sends automatically when you arrive
--   night / day / rain / city / county = how much more (or less) likely at those times and places
---------------------------------------------------------------------------
local NEW = {
    -- Major incidents / SWAT
    { key = 'active_shooter', title = 'Active shooter', code = 3, prio = 1, weight = 1, nature = '245 PC / 417 - Active shooter', team = true,
      text = 'Multiple callers report a gunman shooting at people. Victims down. Every available unit respond - stop the killing, then stop the dying.',
      notes = { 'Callers say the shooter has a rifle and is wearing dark clothing.', 'At least two victims down near the entrance.', 'SWAT has been activated. EMS staging two blocks away.' },
      units = { 'swat', 'ems' }, city = 1.4 },
    { key = 'barricaded', title = 'Barricaded armed subject', code = 3, prio = 1, weight = 2, nature = '417 PC - Barricaded subject', team = true,
      text = 'An armed subject has barricaded themselves in and fired at a deputy. Set up a perimeter, call out to them and negotiate. Do not go in.',
      notes = { 'Subject is believed to have a shotgun and a history of mental illness.', 'Neighbours evacuated on one side.', 'SWAT and a negotiator are en route.' },
      units = { 'swat' } },
    { key = 'swat_warrant', title = 'High-risk warrant (SWAT)', code = 2, prio = 2, weight = 2, nature = 'Felony warrant - high risk', team = true,
      text = 'Serve a felony warrant on an armed suspect at their address. SWAT will meet you there. Knock and announce, or make entry.',
      notes = { 'Suspect is wanted for armed robbery and assault with a deadly weapon.', 'Intel says two associates may be with him.' },
      units = { 'swat' }, night = 0.6 },
    { key = 'bank_robbery', title = 'Bank robbery in progress', code = 3, prio = 1, weight = 1, nature = '211 PC - Bank (silent alarm)', team = true,
      text = 'Silent hold-up alarm at a bank. Multiple armed suspects inside with a getaway vehicle outside.',
      notes = { 'Bank security reports three masked suspects with long guns.', 'Getaway vehicle is running at the kerb.', 'Air unit is being launched.' },
      units = { 'swat', 'air' }, day = 1.8, night = 0.2 },
    { key = 'officer_down', title = '11-99 Officer needs help', code = 3, prio = 1, weight = 1, nature = '11-99 - Officer down', team = true,
      text = 'A deputy has been shot during a stop and is calling for help. Suspects are still shooting. Get there NOW.',
      notes = { 'Deputy is hit in the leg and can\'t move.', 'Suspects are using the deputy\'s own car for cover.' },
      units = { 'backup', 'ems' } },
    { key = 'drive_by', title = 'Drive-by shooting', code = 3, prio = 1, weight = 3, nature = '246 PC - Shooting from a vehicle', team = true,
      text = 'Shots fired from a passing car. People are hit. The suspect vehicle has left the scene.',
      notes = { 'Witness says the car was a dark sedan with three occupants.', 'Suspects were flashing gang signs.' },
      units = { 'ems' }, night = 1.8, city = 1.8, county = 0.5 },
    { key = 'kidnapping', title = 'Kidnapping in progress', code = 3, prio = 1, weight = 2, nature = '207 PC - Kidnapping',
      text = 'A woman was dragged into a van that drove off. Find the van - the victim is still inside.',
      notes = { 'Witness says the van is white with no rear windows.', 'Victim was screaming for help.' } },
    { key = 'carjacking', title = 'Carjacking', code = 3, prio = 1, weight = 4, nature = '215 PC - Carjacking',
      text = 'A driver was pulled out of their car at gunpoint. The suspect drove off in it.',
      notes = { 'Victim says the suspect had a handgun.', 'The car has a tracking app - it\'s moving in your area.' }, night = 1.4 },
    { key = 'stabbing', title = 'Stabbing', code = 3, prio = 1, weight = 3, nature = '245 PC - ADW (knife)',
      text = 'A person has been stabbed. The suspect is walking away from the scene.',
      notes = { 'Victim is conscious but bleeding heavily.', 'Suspect still has the knife.' }, units = { 'ems' }, night = 1.6 },
    { key = 'man_with_gun', title = 'Man with a gun', code = 3, prio = 1, weight = 4, nature = '417 PC - Brandishing',
      text = 'A man is waving a handgun at people. He hasn\'t fired yet.',
      notes = { 'He appears to be intoxicated.', 'People are hiding in the shops nearby.' } },

    -- Crime in progress
    { key = 'burglary_progress', title = 'Burglary in progress', code = 3, prio = 1, weight = 5, nature = '459 PC - In progress',
      text = 'The alarm company reports a break-in in progress. The suspects may still be inside.',
      notes = { 'Glass break sensor at the rear.', 'Neighbour sees a flashlight moving inside.' }, night = 2.5, day = 0.5 },
    { key = 'escaped_prisoner', title = 'Escaped prisoner', code = 3, prio = 2, weight = 2, nature = '4532 PC - Escape',
      text = 'An inmate has escaped and was last seen in the area on foot in prison orange. Search the area.',
      notes = { 'Inmate was serving time for armed robbery.', 'He may have changed his clothes.' }, county = 1.6, city = 0.6 },
    { key = 'bar_brawl', title = 'Large fight at a bar', code = 3, prio = 1, weight = 4, nature = '415 PC - Large fight',
      text = 'Bar staff report a large fight. Several people involved and the crowd is growing.',
      notes = { 'Bouncer is hurt.', 'Somebody has broken a bottle.' }, night = 2.6, day = 0.3 },
    { key = 'arson', title = 'Arson', code = 3, prio = 1, weight = 3, nature = '451 PC - Arson',
      text = 'A vehicle is on fire and a witness saw someone pour petrol on it. The suspect may still be watching.',
      notes = { 'Fire department is en route.', 'Witness describes the suspect holding a red jerry can.' }, night = 1.8 },
    { key = 'drug_lab', title = 'Suspected drug lab', code = 2, prio = 2, weight = 3, nature = 'HS 11379.6 - Clandestine lab',
      text = 'Neighbours report a strong chemical smell and people coming and going at all hours. Investigate - carefully.',
      notes = { 'Toxic fumes - don\'t go inside without a reason.', 'A previous caller saw a rifle in the window.' }, county = 1.8, city = 0.5 },
    { key = 'fraud', title = 'Fraud at a store', code = 2, prio = 2, weight = 4, nature = '470 PC / 484g - Card fraud',
      text = 'A clerk thinks a customer is using stolen bank cards. They\'re still at the counter.',
      notes = { 'Three cards declined, then one in a different name went through.' }, day = 1.5, night = 0.6 },
    { key = 'vandalism', title = 'Vandalism in progress', code = 2, prio = 3, weight = 4, nature = '594 PC - Vandalism',
      text = 'Someone is spray painting a wall.', notes = { 'There may be a lookout.' }, night = 2.0, city = 1.4 },
    { key = 'prowler', title = 'Prowler', code = 2, prio = 2, weight = 4, nature = 'Prowler / 647(i) PC',
      text = 'A homeowner says someone is looking through their windows.', notes = { 'RP is hiding in the bathroom.' }, night = 2.6, day = 0.3 },
    { key = 'restraining_order', title = 'Restraining order violation', code = 2, prio = 1, weight = 3, nature = '273.6 PC - Order violation',
      text = 'A woman says her ex is outside her house, which breaks a restraining order. He\'s getting angry.',
      notes = { 'Order was served last month.', 'He has a history of violence.' } },
    { key = 'gas_driveoff', title = 'Gas drive-off', code = 2, prio = 3, weight = 4, nature = '484 PC - Gas drive-off',
      text = 'A driver filled up and drove off without paying.', notes = { 'Clerk got a look at the driver.' } },
    { key = 'poaching', title = 'Shots fired - possible poacher', code = 2, prio = 2, weight = 2, nature = 'F&G 2000 / Shots fired (rural)',
      text = 'A rancher heard rifle shots and saw a spotlight in the trees. Probably a poacher - but they\'re armed.',
      notes = { 'RP saw a pickup parked without lights.' }, night = 2.5, county = 3.0, city = 0.0 },

    -- Traffic
    { key = 'street_race', title = 'Street racing', code = 3, prio = 2, weight = 4, nature = '23109 VC - Speed contest',
      text = 'Two cars are racing through traffic.', notes = { 'One is a bright sports car.', 'They\'ve run a red light.' }, night = 2.0, city = 1.5 },
    { key = 'wrong_way', title = 'Wrong-way driver', code = 3, prio = 1, weight = 3, nature = '21651 VC - Wrong-way driver',
      text = 'Multiple callers: a vehicle driving against traffic. Stop it before someone is killed.',
      notes = { 'Vehicle has its hazards on.', 'Driver may be asleep or intoxicated.' }, night = 2.5 },
    { key = 'truck_inspection', title = 'Unsafe commercial vehicle', code = 2, prio = 3, weight = 3, nature = 'CVC 34500 - Commercial vehicle',
      text = 'A truck with an unsecured load is swerving. Stop it and inspect the driver and the vehicle.',
      notes = { 'Load is shifting on corners.' }, county = 1.6 },
    { key = 'assist_pursuit', title = 'Pursuit - agency assist', code = 3, prio = 1, weight = 3, nature = '2800.2 VC - Pursuit assist', team = true,
      text = 'Another agency is in pursuit and asking for help. The suspect is heading your way.',
      notes = { 'Vehicle was taken in an armed robbery.', 'Speeds over 100 mph.' } },
    { key = 'ped_on_freeway', title = 'Pedestrian on the highway', code = 3, prio = 1, weight = 2, nature = '21960 VC - Pedestrian on freeway',
      text = 'Drivers report someone walking in the lanes of the highway.', notes = { 'Subject appears confused.' }, night = 1.6 },
    { key = 'livestock', title = 'Livestock on the roadway', code = 2, prio = 2, weight = 3, nature = 'Hazard - livestock',
      text = 'Cattle have got out onto the road. Get them off it before someone hits them.', county = 3.0, city = 0.0 },

    -- Community
    { key = 'welfare_check', title = 'Welfare check', code = 2, prio = 3, weight = 5, nature = 'Welfare check',
      text = 'Family haven\'t heard from an elderly relative for two days. Check on them.', notes = { 'Mail has been piling up.' } },
    { key = 'loud_party', title = 'Loud party', code = 2, prio = 3, weight = 4, nature = '415 PC - Loud party',
      text = 'Neighbours are complaining about a loud party. Third call tonight.', night = 3.0, day = 0.2 },
    { key = 'dog_attack', title = 'Dog attack', code = 3, prio = 1, weight = 2, nature = 'Animal attack',
      text = 'A dog is attacking someone. The owner can\'t control it.', notes = { 'Victim is on the ground.' }, units = { 'ems' } },
    { key = 'bomb_threat', title = 'Suspicious package', code = 3, prio = 1, weight = 2, nature = '148.1 PC - Suspicious package',
      text = 'A bag has been left outside a business after a threatening phone call. Clear the area and wait for the bomb squad.',
      notes = { 'Caller said it would "go off at noon".', 'Wires seen sticking out of the bag.' }, units = { 'swat' } },
    { key = 'body_found', title = 'Body found', code = 2, prio = 2, weight = 2, nature = 'Unattended death',
      text = 'A jogger has found a body. Secure the scene and call the coroner.', notes = { 'RP is waiting nearby.' } },
}
for _, c in ipairs(NEW) do table.insert(Config.AI.Callouts, c) end

-- Which places each new call uses (nothing nearby = a spot on the road)
local P = AI.CalloutPlaces
P.active_shooter = { 'store', 'business', 'diner', 'park', 'street' }
P.barricaded = { 'house', 'trailer', 'business' }
P.swat_warrant = { 'house', 'trailer' }
P.bank_robbery = { 'bank' }
P.stabbing = { 'street', 'bar', 'park', 'lot' }
P.man_with_gun = { 'street', 'park', 'gas', 'lot', 'diner' }
P.burglary_progress = { 'house', 'business', 'gunstore', 'hardware' }
P.bar_brawl = { 'bar' }
P.arson = { 'lot', 'business', 'house' }
P.drug_lab = { 'trailer', 'house', 'lot' }
P.fraud = { 'store', 'liquor', 'hardware', 'gas' }
P.vandalism = { 'business', 'street', 'park', 'lot' }
P.prowler = { 'house' }
P.restraining_order = { 'house', 'trailer' }
P.gas_driveoff = { 'gas' }
P.welfare_check = { 'house', 'trailer' }
P.loud_party = { 'house', 'trailer' }
P.dog_attack = { 'park', 'street', 'house' }
P.bomb_threat = { 'business', 'store', 'bank', 'diner' }
P.body_found = { 'park', 'lot' }
P.poaching = { 'park' }

-- Banks (vanilla Fleeca / Blaine County Savings - outside the doors). Staff can add more as "Bank" in Places.
table.insert(AI.PlaceTypes, { key = 'bank', label = 'Bank (outside the doors)' })
table.insert(AI.PlaceTypes, { key = 'gunstore', label = 'Gun store (counter)' })
local BANKS = {
    { label = 'Blaine County Savings, Paleto Bay', pos = vector4(-109.53, 6464.06, 31.63, 135.0) },
    { label = 'Fleeca, Route 68', pos = vector4(1175.06, 2702.45, 38.17, 0.0) },
    { label = 'Fleeca, Great Ocean Hwy', pos = vector4(-2966.56, 482.94, 15.69, 87.0) },
    { label = 'Fleeca, Legion Square', pos = vector4(149.46, -1038.29, 29.37, 340.0) },
    { label = 'Fleeca, Hawick Ave', pos = vector4(313.77, -276.76, 54.17, 340.0) },
    { label = 'Fleeca, Boulevard Del Perro', pos = vector4(-1214.19, -327.40, 37.67, 27.0) },
    { label = 'Fleeca, Burton', pos = vector4(-350.38, -46.88, 49.04, 340.0) },
}
for _, b in ipairs(BANKS) do table.insert(AI.PlaceList, { type = 'bank', label = b.label, pos = b.pos }) end

-- Divisions get the new calls too
local DIV = {
    traffic = { 'street_race', 'wrong_way', 'truck_inspection', 'gas_driveoff', 'livestock', 'assist_pursuit', 'carjacking' },
    highway = { 'wrong_way', 'street_race', 'truck_inspection', 'ped_on_freeway', 'assist_pursuit', 'livestock' },
    k9 = { 'escaped_prisoner', 'burglary_progress', 'prowler', 'drug_lab' },
    detective = { 'body_found', 'fraud', 'arson', 'kidnapping' },
    swat = { 'active_shooter', 'barricaded', 'swat_warrant', 'bank_robbery', 'drug_lab', 'officer_down' },
    patrol = { 'welfare_check', 'loud_party', 'restraining_order', 'vandalism' },
}
for _, d in ipairs(AI.Divisions) do
    for _, k in ipairs(DIV[d.key] or {}) do d.callouts[#d.callouts + 1] = k end
end

-- Things that happen in front of you on patrol (on-view)
Config.AI.OnViewExtra = {
    { key = 'street_race', title = 'Two cars racing' }, { key = 'wrong_way', title = 'Car going the wrong way' },
    { key = 'man_with_gun', title = 'Man waving a gun' }, { key = 'vandalism', title = 'Someone tagging a wall' },
    { key = 'stabbing', title = 'Person stabbed' }, { key = 'truck_inspection', title = 'Truck shedding its load' },
}

---------------------------------------------------------------------------
-- TIME, WEATHER AND AREA
-- Night is NightFrom..NightTo (in-game hours). City = Los Santos (south of CityLine), county = Blaine.
---------------------------------------------------------------------------
Config.AI.Context = { NightFrom = 21, NightTo = 5, CityLine = 1150.0 }

---------------------------------------------------------------------------
-- wk_wars2x (Wraith ARS 2X radar + plate reader)
-- Every plate the reader scans is checked against the records. A hit locks the camera, plays the BOLO tone
-- and tells you why. Locking a plate yourself runs it automatically.
---------------------------------------------------------------------------
Config.AI.ALPR = {
    Resource = 'wk_wars2x',
    Enabled = true,
    RandomHit = 0.015,     -- chance an unknown plate comes back with something (stolen, wanted owner, no insurance...)
    Cooldown = 90,         -- seconds before the same plate can alert you again
    LockRuns = true,       -- locking a plate on the reader runs it for you
}

---------------------------------------------------------------------------
-- PENAL CODE additions (used in the ticket / arrest forms)
---------------------------------------------------------------------------
local PC = Config.PenalCode
for _, c in ipairs({
    { cat = 'Traffic', label = 'Street racing / speed contest',       fine = 2000, jail = 10 },
    { cat = 'Traffic', label = 'Driving the wrong way',                fine = 1500, jail = 5 },
    { cat = 'Traffic', label = 'Unsafe load / commercial violation',   fine = 600,  jail = 0 },
    { cat = 'Traffic', label = 'Falsified log book',                   fine = 800,  jail = 0 },
    { cat = 'Public order', label = 'Disturbing the peace (loud party)', fine = 300, jail = 0 },
    { cat = 'Public order', label = 'Prowling / peeping',              fine = 800,  jail = 5 },
    { cat = 'Public order', label = 'Violation of a restraining order', fine = 1500, jail = 15 },
    { cat = 'Public order', label = 'Owner of a dangerous dog',        fine = 1000, jail = 0 },
    { cat = 'Public order', label = 'Bomb threat / false report of a bomb', fine = 5000, jail = 30 },
    { cat = 'Public order', label = 'Escape from custody',             fine = 0,    jail = 40 },
    { cat = 'Violent', label = 'Carjacking',                           fine = 6000, jail = 40 },
    { cat = 'Violent', label = 'Arson',                                fine = 6000, jail = 35 },
    { cat = 'Violent', label = 'Shooting from a vehicle',              fine = 9000, jail = 60 },
    { cat = 'Theft', label = 'Fraud / using stolen cards',             fine = 2500, jail = 15 },
    { cat = 'Theft', label = 'Gas drive-off (petty theft)',            fine = 400,  jail = 0 },
    { cat = 'Drugs', label = 'Manufacturing a controlled substance',  fine = 9000, jail = 50 },
    { cat = 'Weapons', label = 'Poaching / hunting without a licence', fine = 1500, jail = 0 },
}) do PC[#PC + 1] = c end

---------------------------------------------------------------------------
-- WHAT PEOPLE SAY ON THE NEW CALLS
---------------------------------------------------------------------------
L.story_shooting_victim = { 'He just started shooting... I couldn\'t get out of the way.', 'I\'m hit... please, my leg...', 'He was shooting at everyone! Why?!' }
L.story_drive_by = { 'A car came past and they just opened fire!', 'They were shooting out the window - I didn\'t even see their faces.' }
L.story_carjacked = { 'He put a gun to my head and told me to get out! He took my car!', 'I was at the lights and he pulled the door open. He had a gun.' }
L.story_stabbed = { 'He stabbed me... he just walked up and stabbed me.', 'We were arguing, and then he pulled a knife. Ahh...' }
L.story_kidnap_witness = { 'They grabbed her and threw her in a white van!', 'She was screaming! The van went that way!' }
L.story_kidnap_victim = { 'Thank God... thank God you found me.', 'They tied my hands... I didn\'t know where they were taking me.' }
L.story_fraud_clerk = { 'She tried four cards. The last one had a man\'s name on it.', 'They\'re still at the counter - I said the machine was slow.' }
L.story_fraudster = { 'It\'s my husband\'s card, he said I could use it.', 'There must be a mistake with the bank.' }
L.story_driveoff_clerk = { 'Filled up sixty bucks and just drove off!', 'Third time this month. I got a good look at him.' }
L.story_farmer = { 'Sorry officer, a fence came down in the night.', 'They\'re mine - they got through the gate. I\'ll get them in.' }
L.story_body_finder = { 'I was jogging and... I saw a foot sticking out of the bushes.', 'I didn\'t touch anything, I swear. I just called you.' }
L.story_ro_victim = { 'He\'s not allowed within 100 yards of me. He won\'t leave!', 'I have the paperwork right here. Please make him go.' }
L.story_stalker = { 'I just want to talk to her! She\'s my wife!', 'That order is a joke. I\'ve got rights too.' }
L.story_party_host = { 'It\'s my birthday, man! Come on!', 'We\'ll turn it down. Probably.', 'The neighbours are always complaining.' }
L.story_neighbour = { 'It\'s three in the morning! I have work tomorrow!', 'This is every weekend, officer. Every weekend.' }
L.story_homeowner = { 'I saw someone at the window!', 'They were trying the back door, I heard it rattle.' }
L.story_elderly = { 'Oh! Hello officer. Is something wrong?', 'My daughter sent you? I\'ve just been resting.', 'I haven\'t been well, dear.' }
L.story_elderly_hurt = { 'I fell... I\'ve been on the floor since yesterday.', 'Help me... my hip...' }
L.story_bomb_manager = { 'The call said there was a bomb in the bag. Then they hung up.', 'Nobody has touched it. Should we leave?' }
L.story_dog_owner = { 'He\'s never done that before! He\'s a good boy!', 'I couldn\'t hold him - the lead snapped!' }
L.story_dog_victim = { 'It just went for me! My arm...', 'Get it away from me!' }
L.story_prowler = { 'I was just looking for my cat.', 'I\'m lost, I thought this was my friend\'s house.' }
L.story_vandal = { 'It\'s art, man.', 'This wall was ugly anyway.' }
L.story_poacher = { 'I\'m just out here hunting.', 'Licence? It\'s at home.', 'Deer season\'s open, isn\'t it?' }
L.story_escapee = { 'I\'m not going back. I\'m not.', 'You got the wrong guy, man.' }
L.story_arson_witness = { 'He poured something on it and lit it! Then he just stood there watching!', 'The car went up like a torch.' }
L.story_trucker = { 'I\'ve been driving fourteen hours, I just want to get home.', 'The straps came loose, I was going to fix them at the next stop.' }
L.story_bar_staff = { 'It started over a pool game and then everyone was in it.', 'Our bouncer got a bottle to the head.' }
L.story_bank_teller = { 'They had rifles... they made us lie on the floor.', 'They took everything from the drawers.' }
L.story_deputy = { 'They\'re shooting from behind the car! I\'m hit!', 'Thanks... thanks for coming. I thought that was it.' }
L.story_shooter = { 'They deserved it! All of them!', 'I\'m not saying anything.' }

L.barricade_good = { 'You\'re not lying to me?', 'Alright... I\'m listening.', 'I don\'t want to die today.', 'Just... don\'t send those guys in.' }
L.barricade_bad = { 'You come in here and I\'ll shoot!', 'I\'m not going back to jail!', 'Get away from my house!', 'I\'ve got nothing to lose!' }
L.barricade_release = { 'Okay. I\'m coming out. Don\'t shoot.', 'Fine... I\'m putting the gun down. I\'m coming out.' }
L.barricade_snap = { 'That\'s it! You did this!', 'You were never going to listen!' }

-- CAD radio phrasing
L.cad_update = { 'Dispatch: %s, update on %s - %s', 'Dispatch: %s, further on %s: %s' }
