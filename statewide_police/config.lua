Config = {}

Config.Currency = '$'

---------------------------------------------------------------------------
-- WHO IS POLICE
-- Players clocked on with /onduty (duty-sync) for one of these department
-- keys (the keys from your staff panel). Staff with the admin ace can always
-- use everything:  add_ace group.admin statewide.police.admin allow
---------------------------------------------------------------------------
Config.PoliceDepts = { 'LSPD', 'BCSO', 'SASP', 'SAHP', 'LSSD', 'SAPR', 'SACO', 'FIB', 'POLICE' }
Config.AdminAce = 'statewide.police.admin'
Config.Command = 'police'          -- /police lists every command

---------------------------------------------------------------------------
-- KEYS (players can change them in Settings > Key Bindings > FiveM)
---------------------------------------------------------------------------
Config.Keys = {
    menu = 'F7',            -- police menu
    tackle = 'E',           -- while sprinting at someone
    cuff = '',              -- quick cuff / uncuff the nearest person (blank = no default key)
    escort = '',            -- quick escort the nearest person
    radarLock = 'NUMPAD5',  -- lock / unlock the vehicle radar
}

---------------------------------------------------------------------------
-- PROPS (vanilla GTA models). Swap any for an add-on prop if you have one -
-- e.g. an "Alcolizer / breathalyser" mod that replaces prop_inhaler_01.
---------------------------------------------------------------------------
Config.FallbackProp = 'prop_cs_swipe_card'
Config.Props = {
    cuffs       = { model = 'p_cs_cuffs_02_s',            bone = 60309, pos = vector3(-0.055, 0.06, 0.04),  rot = vector3(265.0, 155.0, 80.0) },
    ziptie      = { model = 'hei_prop_zip_tie_positioned', bone = 60309, pos = vector3(-0.02, 0.063, 0.0),  rot = vector3(75.0, 0.0, 76.0) },
    cuffsHand   = { model = 'p_cs_cuffs_02_s',            bone = 57005, pos = vector3(0.12, 0.02, -0.03),  rot = vector3(0.0, 90.0, 0.0) },
    breath      = { model = 'prop_inhaler_01',            bone = 57005, pos = vector3(0.13, 0.03, -0.03),  rot = vector3(-80.0, 0.0, 0.0) },
    swab        = { model = 'prop_cs_swipe_card',         bone = 57005, pos = vector3(0.13, 0.03, -0.03),  rot = vector3(-80.0, 0.0, 90.0) },
    gsr         = { model = 'prop_cs_swipe_card',         bone = 57005, pos = vector3(0.13, 0.03, -0.03),  rot = vector3(-80.0, 0.0, 90.0) },
    notepad     = { model = 'prop_notepad_01',            bone = 18905, pos = vector3(0.1, 0.02, 0.05),    rot = vector3(10.0, 0.0, 0.0) },
    pencil      = { model = 'prop_pencil_01',             bone = 58866, pos = vector3(0.11, -0.02, 0.001), rot = vector3(-120.0, 0.0, 0.0) },
    clipboard   = { model = 'p_amb_clipboard_01',         bone = 36029, pos = vector3(0.16, 0.08, 0.1),    rot = vector3(-130.0, -50.0, 0.0) },
    tablet      = { model = 'prop_cs_tablet',             bone = 60309, pos = vector3(0.03, 0.002, -0.0),  rot = vector3(10.0, 160.0, 0.0) },
    idcard      = { model = 'p_ld_id_card_01',            bone = 28422, pos = vector3(0.06, 0.02, -0.01),  rot = vector3(-90.0, 180.0, 78.0) },
    badge       = { model = 'prop_fib_badge',             bone = 28422, pos = vector3(0.065, 0.029, -0.035), rot = vector3(80.0, -1.9, 75.0) },
    evidencebag = { model = 'prop_poly_bag_01',           bone = 57005, pos = vector3(0.14, 0.0, -0.02),   rot = vector3(0.0, 0.0, 0.0) },
    torch       = { model = 'prop_cs_police_torch',       bone = 57005, pos = vector3(0.12, 0.02, -0.02),  rot = vector3(-80.0, 0.0, 0.0) },
    printcard   = { model = 'prop_cs_swipe_card',         bone = 57005, pos = vector3(0.13, 0.03, -0.03),  rot = vector3(-80.0, 0.0, 90.0) },
    phone       = { model = 'prop_npc_phone_02',          bone = 28422, pos = vector3(0.0, 0.0, 0.0),      rot = vector3(0.0, 0.0, 0.0) },
}

---------------------------------------------------------------------------
-- ANIMATIONS
---------------------------------------------------------------------------
Config.Anims = {
    cuffCop      = { dict = 'mp_arrest_paired', name = 'cop_p2_back_right', time = 3500 },
    cuffCrook    = { dict = 'mp_arrest_paired', name = 'crook_p2_back_right', time = 3700 },
    cuffedIdle   = { dict = 'mp_arresting', name = 'idle' },
    zipIdle      = { dict = 'anim@move_m@prisoner_cuffed', name = 'idle' },
    uncuffCop    = { dict = 'mp_arresting', name = 'a_uncuff', time = 5000 },
    uncuffCrook  = { dict = 'mp_arresting', name = 'b_uncuff', time = 5000 },
    tackleCop    = { dict = 'missmic2ig_11', name = 'mic_2_ig_11_intro_goon' },
    tackleCrook  = { dict = 'missmic2ig_11', name = 'mic_2_ig_11_intro_p_one' },
    search       = { dict = 'anim@gangops@facility@servers@bodysearch@', name = 'player_search' },
    holdDevice   = { dict = 'amb@world_human_stand_mobile@male@text@base', name = 'base' },
    blow         = { dict = 'timetable@gardener@smoking_joint', name = 'smoke_idle' },
    swabHands    = { dict = 'amb@prop_human_bum_bin@idle_b', name = 'idle_d' },
    write        = { dict = 'amb@medic@standing@timeofdeath@base', name = 'base' },
    clipboard    = { dict = 'missheistdockssetup1clipboard@base', name = 'base' },
    tablet       = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', name = 'base' },
    giveId       = { dict = 'mp_common', name = 'givetake1_a' },
    kneel        = { dict = 'amb@medic@standing@kneel@base', name = 'base' },
    vehicleSearch = { dict = 'amb@prop_human_bum_bin@idle_b', name = 'idle_d' },
    dust         = { dict = 'amb@prop_human_parking_meter@male@base', name = 'base' },
    place        = { dict = 'anim@mp_fireworks', name = 'place_firework_3_box' },
}

Config.Tackle = { distance = 2.8, ragdoll = 4500, cooldown = 10 }
Config.ConsentSeconds = 15      -- how long someone has to agree to a search

---------------------------------------------------------------------------
-- BREATHALYSER & DRUGALYSER
-- Real drinks from the Job Bag raise your alcohol level, and anyone can add
-- roleplay drinks / drugs with /rpstatus.
---------------------------------------------------------------------------
Config.DrinkLimit = 0.08          -- legal driving limit (BAC %)
Config.BACDecayPerMinute = 0.002  -- how fast it wears off (0.08 clears in ~40 minutes)
Config.DrunkEffects = true        -- stagger and camera sway above the limit (from real drinks)
Config.Alcohol = {                -- BAC added per drink
    beer = 0.025, loggerbeer = 0.025, patriotbeer = 0.025, cider = 0.025,
    wine = 0.03, champagne = 0.03,
    whisky = 0.04, vodka = 0.04, rum = 0.04, tequila = 0.04,
    mojito = 0.035, margaritacocktail = 0.035, pinacolada = 0.035,
}
Config.RPDrinkBAC = 0.03          -- /rpstatus drink adds this per drink
Config.Drugs = {                  -- /rpstatus <drug> [minutes]
    cannabis = 'Cannabis (THC)', cocaine = 'Cocaine', amphetamine = 'Amphetamine', meth = 'Methamphetamine',
    mdma = 'MDMA', opiates = 'Opiates', benzos = 'Benzodiazepines', ketamine = 'Ketamine',
}
Config.DrugDefaultMinutes = 60

---------------------------------------------------------------------------
-- GSR / EVIDENCE
---------------------------------------------------------------------------
Config.GSRMinutes = 30            -- gunshot residue stays this long (washing or swimming clears it)
Config.EvidenceMinutes = 90       -- casings and blood stay at a scene this long
Config.EvidenceRange = 30.0       -- evidence mode shows things this close
Config.MaxSceneEvidence = 500
Config.NoCasingWeapons = {        -- these never leave casings / GSR
    'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN', 'WEAPON_FLARE', 'WEAPON_FLAREGUN',
    'WEAPON_SNOWBALL', 'WEAPON_BALL', 'WEAPON_SMOKEGRENADE', 'WEAPON_BZGAS',
}

---------------------------------------------------------------------------
-- STATIONS (first-run defaults - move them in game with /policesetpoint)
-- booking: where you book someone into jail and analyse evidence (lab)
---------------------------------------------------------------------------
Config.Stations = {
    { id = 'missionrow', label = 'Mission Row PD',        pos = vector3(441.05, -981.18, 30.69) },
    { id = 'vespucci',   label = 'Vespucci PD',           pos = vector3(-1096.55, -809.44, 19.26) },
    { id = 'sandy',      label = 'Sandy Shores Sheriff',  pos = vector3(1853.2, 3689.6, 34.27) },
    { id = 'paleto',     label = 'Paleto Bay Sheriff',    pos = vector3(-448.4, 6012.2, 31.72) },
    { id = 'prison',     label = 'Bolingbroke Penitentiary', pos = vector3(1846.0, 2585.8, 45.67) },
}
Config.StationRadius = 25.0       -- how close to a station you need to be to book someone / use the lab
Config.BookAnywhere = false       -- true = jail people from anywhere

---------------------------------------------------------------------------
-- JAIL (Bolingbroke)
---------------------------------------------------------------------------
Config.Jail = {
    center = vector3(1690.0, 2590.0, 45.56),
    radius = 175.0,                -- leave this and you're put back in the yard
    spawns = { vector4(1641.64, 2571.08, 45.56, 180.0), vector4(1636.2, 2565.3, 45.56, 200.0), vector4(1648.1, 2562.4, 45.56, 160.0) },
    release = vector4(1847.71, 2585.87, 45.67, 270.0),
    chores = {                     -- sweep these to cut your sentence
        vector3(1636.0, 2565.0, 45.56), vector3(1648.0, 2560.0, 45.56), vector3(1655.0, 2575.0, 45.56),
        vector3(1630.0, 2580.0, 45.56), vector3(1645.0, 2585.0, 45.56),
    },
    choreSeconds = 12,             -- how long a chore takes
    choreReduces = 30,             -- seconds off the sentence per chore
    maxMinutes = 120,
}

Config.ComServ = {
    center = vector3(195.0, -935.0, 30.69),   -- Legion Square
    radius = 70.0,
    spots = {
        vector3(185.0, -925.0, 30.69), vector3(200.0, -945.0, 30.69), vector3(215.0, -930.0, 30.69),
        vector3(175.0, -940.0, 30.69), vector3(190.0, -955.0, 30.69), vector3(205.0, -915.0, 30.69),
    },
    seconds = 12,
    maxTasks = 50,
}

---------------------------------------------------------------------------
-- PENAL CODE (fine in $, jail in minutes). Edit freely.
---------------------------------------------------------------------------
Config.PenalCode = {
    { cat = 'Traffic', label = 'Speeding (1-15 over)',             fine = 150,   jail = 0 },
    { cat = 'Traffic', label = 'Speeding (16-30 over)',            fine = 350,   jail = 0 },
    { cat = 'Traffic', label = 'Speeding (31+ over)',              fine = 750,   jail = 0 },
    { cat = 'Traffic', label = 'Running a red light / stop sign',   fine = 200,   jail = 0 },
    { cat = 'Traffic', label = 'Illegal parking',                  fine = 100,   jail = 0 },
    { cat = 'Traffic', label = 'Using a phone while driving',      fine = 150,   jail = 0 },
    { cat = 'Traffic', label = 'Driving without a licence',        fine = 500,   jail = 0 },
    { cat = 'Traffic', label = 'Driving without insurance',        fine = 400,   jail = 0 },
    { cat = 'Traffic', label = 'Unroadworthy vehicle',             fine = 250,   jail = 0 },
    { cat = 'Traffic', label = 'Reckless driving',                 fine = 1000,  jail = 5 },
    { cat = 'Traffic', label = 'Driving under the influence',      fine = 2000,  jail = 10 },
    { cat = 'Traffic', label = 'Failure to stop for police',       fine = 1500,  jail = 10 },
    { cat = 'Traffic', label = 'Evading police',                   fine = 3000,  jail = 20 },
    { cat = 'Traffic', label = 'Hit and run',                      fine = 2500,  jail = 15 },
    { cat = 'Public order', label = 'Public intoxication',          fine = 300,   jail = 0 },
    { cat = 'Public order', label = 'Disorderly conduct',           fine = 400,   jail = 0 },
    { cat = 'Public order', label = 'Trespassing',                  fine = 500,   jail = 0 },
    { cat = 'Public order', label = 'Vandalism',                    fine = 750,   jail = 5 },
    { cat = 'Public order', label = 'Obstruction of justice',       fine = 800,   jail = 5 },
    { cat = 'Public order', label = 'Resisting arrest',             fine = 1000,  jail = 10 },
    { cat = 'Public order', label = 'Failure to identify',          fine = 500,   jail = 0 },
    { cat = 'Violent', label = 'Assault',                          fine = 1500,  jail = 15 },
    { cat = 'Violent', label = 'Assault with a deadly weapon',     fine = 4000,  jail = 30 },
    { cat = 'Violent', label = 'Assault on an officer',            fine = 5000,  jail = 35 },
    { cat = 'Violent', label = 'Kidnapping',                       fine = 5000,  jail = 40 },
    { cat = 'Violent', label = 'Attempted murder',                 fine = 8000,  jail = 60 },
    { cat = 'Violent', label = 'Murder',                           fine = 15000, jail = 90 },
    { cat = 'Theft', label = 'Petty theft',                        fine = 500,   jail = 0 },
    { cat = 'Theft', label = 'Grand theft auto',                   fine = 3000,  jail = 25 },
    { cat = 'Theft', label = 'Burglary',                           fine = 3500,  jail = 25 },
    { cat = 'Theft', label = 'Robbery',                            fine = 4000,  jail = 30 },
    { cat = 'Theft', label = 'Armed robbery',                      fine = 7500,  jail = 45 },
    { cat = 'Weapons', label = 'Brandishing a firearm',            fine = 1200,  jail = 10 },
    { cat = 'Weapons', label = 'Carrying an unlicensed firearm',   fine = 2500,  jail = 20 },
    { cat = 'Weapons', label = 'Discharging a firearm in public',  fine = 2000,  jail = 15 },
    { cat = 'Drugs', label = 'Possession of a controlled substance', fine = 1000, jail = 10 },
    { cat = 'Drugs', label = 'Possession with intent to supply',  fine = 5000,  jail = 35 },
    { cat = 'Other', label = 'Outstanding warrant',                fine = 0,     jail = 15 },
    { cat = 'Other', label = 'Failure to pay fines',               fine = 500,   jail = 10 },
}

---------------------------------------------------------------------------
-- TRAFFIC
---------------------------------------------------------------------------
Config.Radar = { range = 60.0, fastLimit = 80 }   -- mph; the HUD flashes above fastLimit
Config.Speed = 'mph'                              -- 'mph' or 'kmh'
Config.SpikeModel = 'p_ld_stinger_s'
Config.MaxSpikes = 2
Config.SpikeMinutes = 10
Config.SceneProps = {
    { key = 'cone',    label = 'Traffic cone',     model = 'prop_roadcone02a' },
    { key = 'conel',   label = 'Lit cone',         model = 'prop_air_conelight' },
    { key = 'barrier', label = 'Police barrier',   model = 'prop_barrier_work05' },
    { key = 'mpbarr',  label = 'Crowd barrier',    model = 'prop_mp_barrier_02b' },
    { key = 'sign',    label = 'Road closed sign', model = 'prop_consign_02a' },
    { key = 'arrow',   label = 'Arrow board',      model = 'prop_mp_arrow_barrier_01' },
    { key = 'marker',  label = 'Evidence marker',  model = 'prop_mp_cone_02', numbered = true },
}
Config.MaxSceneProps = 25          -- per officer

-- What turns up when searching an NPC's vehicle (chance 0-1 each)
Config.VehicleContraband = {
    { label = 'Open container of alcohol',       chance = 0.12 },
    { label = 'Small bag of cannabis',           chance = 0.10 },
    { label = 'Unmarked pills',                  chance = 0.06 },
    { label = 'Bag of white powder',             chance = 0.04 },
    { label = 'Lock picks',                      chance = 0.05 },
    { label = 'Knife',                           chance = 0.06 },
    { label = 'Unregistered pistol',             chance = 0.03 },
    { label = 'Large amount of cash',            chance = 0.04 },
    { label = 'Stolen electronics',              chance = 0.04 },
}

-- Plates from job vehicles show up as company vehicles when run
Config.CompanyPlates = {
    TOW = 'Hook & Haul Recovery', DLV = 'Business Delivery Services', SAFD = 'San Andreas Fire Department',
    BCSO = "Blaine County Sheriff's Office", SASP = 'San Andreas State Police', TAXI = 'Downtown Cab Co.',
    BUS = 'Dashound Coach Lines', GPS = 'GoPostal', MECH = 'LS Customs', G6 = 'Gruppe Sechs',
}

-- Weapons checked for when searching someone
Config.Weapons = {
    'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_PISTOL50', 'WEAPON_SNSPISTOL',
    'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_REVOLVER', 'WEAPON_DOUBLEACTION', 'WEAPON_CERAMICPISTOL', 'WEAPON_NAVYREVOLVER',
    'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_ASSAULTSMG', 'WEAPON_COMBATPDW', 'WEAPON_MACHINEPISTOL', 'WEAPON_MINISMG',
    'WEAPON_PUMPSHOTGUN', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_BULLPUPSHOTGUN', 'WEAPON_HEAVYSHOTGUN', 'WEAPON_DBSHOTGUN',
    'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE',
    'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE', 'WEAPON_MUSKET', 'WEAPON_GUSENBERG', 'WEAPON_MG', 'WEAPON_COMBATMG',
    'WEAPON_KNIFE', 'WEAPON_SWITCHBLADE', 'WEAPON_DAGGER', 'WEAPON_MACHETE', 'WEAPON_HATCHET', 'WEAPON_BAT', 'WEAPON_CROWBAR',
    'WEAPON_HAMMER', 'WEAPON_WRENCH', 'WEAPON_KNUCKLE', 'WEAPON_NIGHTSTICK', 'WEAPON_BOTTLE', 'WEAPON_POOLCUE', 'WEAPON_GOLFCLUB',
    'WEAPON_STUNGUN', 'WEAPON_MOLOTOV', 'WEAPON_GRENADE', 'WEAPON_PIPEBOMB',
}

-- Random registered owners for NPC vehicles
Config.FirstNames = { 'James', 'Maria', 'Robert', 'Linda', 'Michael', 'Sarah', 'David', 'Karen', 'Daniel', 'Lisa', 'Chris', 'Nancy',
    'Kevin', 'Ashley', 'Brian', 'Emily', 'Jason', 'Megan', 'Tyler', 'Jessica', 'Carlos', 'Rosa', 'Tyrone', 'Keisha', 'Wei', 'Priya' }
Config.LastNames = { 'Smith', 'Johnson', 'Williams', 'Brown', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez', 'Wilson', 'Anderson',
    'Taylor', 'Thomas', 'Moore', 'Jackson', 'Lee', 'Harris', 'Clark', 'Lewis', 'Walker', 'Young', 'King', 'Nguyen', 'Patel', 'Chen' }

Config.Notify = function(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end
