-- Statewide PD - the people on the Phase 3 calls (see config_calls.lua and client/ai_calls.lua)
-- only = this person can only be made on those calls (stops anyone faking an active shooter elsewhere)
local X = AIX
local NEW = {
    activeshooter = { gun = true, guns = { 'WEAPON_CARBINERIFLE', 'WEAPON_ASSAULTRIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_PISTOL50' }, fight = 0.85, flee = 0.15,
        mood = 'hostile', flag = 'Armed and dangerous', gsr = true, carry = { 'Spare magazines', 'Notebook with a manifesto' }, only = { 'active_shooter' } },
    barricaded = { gun = true, guns = { 'WEAPON_PUMPSHOTGUN', 'WEAPON_CARBINERIFLE', 'WEAPON_PISTOL' }, fight = 0.6, flee = 0.2, mood = 'hostile', warrant = 0.7,
        flag = 'Armed and dangerous', nego = 20, barricade = true, gsr = true, only = { 'barricaded' } },
    highrisk = { gun = true, fight = 0.5, flee = 0.45, mood = 'hostile', warrant = 1.0, flag = 'Armed and dangerous',
        warrantText = 'Felony warrant - armed robbery / assault with a deadly weapon' },
    bankrobber = { gun = true, guns = { 'WEAPON_CARBINERIFLE', 'WEAPON_SMG', 'WEAPON_PUMPSHOTGUN', 'WEAPON_ASSAULTRIFLE' }, fight = 0.55, flee = 0.8,
        mood = 'hostile', warrant = 0.5, gsr = true, carry = { 'Duffel bag of stolen cash ($48,600)', 'Balaclava', 'Bank keycard (stolen)' } },
    kidnapper = { gunChance = 0.5, melee = 0.8, fight = 0.35, flee = 0.8, mood = 'hostile', warrant = 0.4, carry = { 'Duct tape', 'Zip ties', 'Ski mask' } },
    carjacker = { gun = true, guns = { 'WEAPON_PISTOL', 'WEAPON_SNSPISTOL', 'WEAPON_REVOLVER' }, fight = 0.35, flee = 0.8, mood = 'hostile', warrant = 0.5,
        noLicence = 0.5, stolenCar = true, carry = { 'Victim\'s car keys', 'Victim\'s wallet (stolen)' } },
    stabber = { melee = 1.0, melees = { 'WEAPON_KNIFE', 'WEAPON_SWITCHBLADE', 'WEAPON_DAGGER' }, fight = 0.4, flee = 0.5, mood = 'hostile', flag = 'History of violence' },
    gunman = { gun = true, guns = { 'WEAPON_PISTOL', 'WEAPON_REVOLVER', 'WEAPON_SNSPISTOL' }, fight = 0.3, flee = 0.3, mood = 'hostile', bac = { 0.0, 0.16 } },
    escapee = { warrant = 1.0, warrantText = 'Escape from custody (Bolingbroke Penitentiary)', flee = 0.75, fight = 0.25, mood = 'nervous', melee = 0.3,
        flag = 'Escaped prisoner', noId = true, fake = 0.7 },
    arsonist = { flee = 0.5, fight = 0.15, mood = 'nervous', carry = { 'Lighter', 'Rags soaked in petrol' } },
    cook = { drug = 'meth', gunChance = 0.45, flee = 0.55, fight = 0.3, mood = 'nervous', warrant = 0.4, melee = 0.3,
        carry = { 'Bag of meth (85g)', 'Boxes of pseudoephedrine', 'Lab glassware' } },
    fraudster = { flee = 0.55, fight = 0.05, mood = 'nervous', warrant = 0.35, fake = 0.6, carry = { 'Stolen credit cards (6)', 'Fake driving licence', 'Card skimmer' } },
    vandal = { flee = 0.6, fight = 0.05, mood = 'nervous', carry = { 'Spray paint cans' } },
    prowler = { flee = 0.55, fight = 0.15, mood = 'nervous', warrant = 0.3, melee = 0.3, carry = { 'Binoculars', 'Lock picks' } },
    stalker = { fight = 0.35, flee = 0.3, mood = 'hostile', flag = 'Subject of a restraining order', melee = 0.35, warrant = 0.2 },
    driveoff = { flee = 0.4, fight = 0.05, mood = 'nervous', suspended = 0.3 },
    poacher = { gun = true, guns = { 'WEAPON_MUSKET', 'WEAPON_SNIPERRIFLE' }, flee = 0.25, fight = 0.1, mood = 'nervous', bac = { 0.0, 0.07 },
        carry = { 'Spotlight', 'Untagged deer carcass' } },
    racer = { flee = 0.45, fight = 0.05, mood = 'hostile', suspended = 0.3, bac = { 0.0, 0.06 } },
    wrongway = { bac = { 0.15, 0.3 }, mood = 'drunk', flee = 0.1, fight = 0.08 },
    trucker = { flee = 0.05, fight = 0.02, mood = 'calm', drugChance = 0.25, carry = { { label = 'Log book (hours over the limit)', legal = false }, { label = 'Bill of lading', legal = true } } },
    elderly = { clean = true, mood = 'calm' },
    partygoer = { bac = { 0.03, 0.14 }, flee = 0.08, fight = 0.04 },
    host = { bac = { 0.05, 0.12 }, mood = 'hostile', flee = 0.05, fight = 0.08, refuse = true },
    dogowner = { mood = 'hostile', flee = 0.05, fight = 0.05 },
}

for k, v in pairs(NEW) do
    X.PROFILES[k] = v
    X.PROFILE_OK[k] = true
end
