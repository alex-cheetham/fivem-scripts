-- AI patrol (FivePD-style): the people officers stop, what they say and carry, callouts, stats.
-- The AI peds and vehicles themselves are spawned by the officer's game; everything that decides
-- "who is this person and what happens" lives here so every officer sees the same answers.
local AI = Config.AI

Personas = {}                                   -- [pid] = persona
local Patrol = {}                               -- [src] = patrol state
local Stats = LoadJson('data/patrol.json', {})  -- [ident] = all-time stats
local statsDirty = false
local Rate = {}                                 -- [src][kind] = { t, n }
Groups = {}                                     -- [plate] = the story shared by a car's occupants
TransportReq = {}                               -- [src] = when they last asked for prisoner transport

local function Pick(t) return t[math.random(1, #t)] end
local function Chance(p) return math.random() < (p or 0) end
local function Range(a, b) return a + math.random() * (b - a) end
local function Clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function CleanText(s, max) return (tostring(s or ''):gsub('[<>]', ''):sub(1, max or 300)) end

local function Limited(src, kind, perMinute)
    Rate[src] = Rate[src] or {}
    local now = os.time()
    local r = Rate[src][kind]
    if not r or now - r.t >= 60 then r = { t = now, n = 0 } Rate[src][kind] = r end
    r.n = r.n + 1
    return r.n > perMinute
end

function Line(key, arg)
    local pool = AI.Lines[key]
    if not pool or #pool == 0 then return '...' end
    local s = Pick(pool)
    if arg and s:find('%%s') then s = s:gsub('%%s', (tostring(arg):gsub('%%', '%%%%'))) end
    return s
end

local function Offences(list)
    local labels, fine, jail = {}, 0, 0
    for _, i in ipairs(type(list) == 'table' and list or {}) do
        local o = Config.PenalCode[tonumber(i) or 0]
        if o then labels[#labels + 1] = o.label fine = fine + o.fine jail = jail + o.jail end
    end
    return labels, fine, jail
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
local STAT_KEYS = { 'stops', 'citations', 'warnings', 'arrests', 'callouts', 'pursuits', 'seized', 'xp', 'convictions', 'dismissed', 'cases', 'lies', 'reports',
    'deescalations', 'commendations', 'sustained' }

local Log
local function StatsOf(src)
    local ident = Ident(src)
    if not ident then return nil end
    local s = Stats[ident]
    if not s then s = {} Stats[ident] = s end
    for _, k in ipairs(STAT_KEYS) do s[k] = tonumber(s[k]) or 0 end
    s.name = Name(src)
    return s
end

local function Bump(src, key, n)
    local s = StatsOf(src)
    if not s then return end
    s[key] = s[key] + (n or 1)
    s.last = Stamp()
    statsDirty = true
    local p = Patrol[src]
    if p then p.shift[key] = (p.shift[key] or 0) + (n or 1) end
    -- experience
    local xp = (AI.XP or {})[key]
    if xp and key ~= 'xp' then
        local before = RankOf(s.xp)
        s.xp = s.xp + xp * (n or 1)
        if p then p.shift.xp = (p.shift.xp or 0) + xp * (n or 1) end
        local after = RankOf(s.xp)
        if after.index > before.index then
            TriggerClientEvent(EV .. 'aiPromoted', src, after.label)
            Log(src, 'Promoted to ' .. after.label)
        end
    end
end

function RankOf(xp)
    local ranks = AI.Ranks or { { label = 'Officer', xp = 0 } }
    local idx = 1
    for i, r in ipairs(ranks) do if (xp or 0) >= r.xp then idx = i end end
    local nxt = ranks[idx + 1]
    return { index = idx, label = ranks[idx].label, xp = xp or 0, from = ranks[idx].xp, nextAt = nxt and nxt.xp or nil, nextLabel = nxt and nxt.label or nil }
end

Log = function(src, text)
    local p = Patrol[src]
    if not p then return end
    table.insert(p.log, 1, { t = os.date('%H:%M'), text = text })
    while #p.log > 25 do table.remove(p.log) end
end

CreateThread(function()
    while true do
        Wait(60000)
        if statsDirty then SaveJson('data/patrol.json', Stats) statsDirty = false end
    end
end)
AddEventHandler('onResourceStop', function(res) if res == RES and statsDirty then SaveJson('data/patrol.json', Stats) end end)

---------------------------------------------------------------------------
-- Making people up
---------------------------------------------------------------------------
local PROFILES = {
    public   = {},
    driver   = {},
    drunk    = { bac = { 0.10, 0.26 }, mood = 'drunk', flee = 0.12, fight = 0.12 },
    drugged  = { drugs = true, mood = 'nervous', flee = 0.25 },
    wanted   = { warrant = 1.0, flee = 0.45, fake = 0.5, fight = 0.1, mood = 'nervous' },
    armed    = { gun = true, fight = 0.55, flee = 0.3, warrant = 0.5, flag = 'Armed and dangerous', mood = 'hostile' },
    thief    = { loot = true, flee = 0.55, fight = 0.05, mood = 'nervous', warrant = 0.25 },
    stolen   = { flee = 0.65, warrant = 0.45, fight = 0.1, noLicence = 0.35, mood = 'nervous', stolen = true },
    reckless = { flee = 0.35, bac = { 0.0, 0.14 }, mood = 'hostile', suspended = 0.3 },
    violent  = { fight = 0.5, flee = 0.2, mood = 'hostile', melee = 0.6, flag = 'History of violence' },
    gang     = { gun = true, fight = 0.75, flee = 0.2, mood = 'hostile', flag = 'Known gang member', warrant = 0.4 },
    robber   = { gun = true, loot = true, fight = 0.5, flee = 0.75, mood = 'hostile', warrant = 0.5, gsr = true },
    shooter  = { gun = true, fight = 0.5, flee = 0.4, mood = 'hostile', gsr = true },
    victim   = { clean = true },
    witness  = { clean = true },
    trespass = { mood = 'hostile', flee = 0.15, fight = 0.15, refuse = true },
    hostagetaker = { gun = true, fight = 0.55, flee = 0.35, mood = 'hostile', warrant = 0.6, flag = 'Armed and dangerous' },
    burglar  = { loot = true, flee = 0.5, fight = 0.15, mood = 'nervous', warrant = 0.3, melee = 0.5 },
    assailant = { fight = 0.35, flee = 0.45, mood = 'hostile', melee = 0.4, flag = 'History of violence' },
    carthief = { flee = 0.7, fight = 0.1, mood = 'nervous', warrant = 0.4, noLicence = 0.4, stolen = true },
    mugger   = { loot = true, flee = 0.65, fight = 0.25, mood = 'hostile', melee = 0.7, warrant = 0.3 },
    dealer   = { drugs = true, dealer = true, flee = 0.55, fight = 0.15, mood = 'nervous', warrant = 0.3 },
    missing  = { clean = true, confused = true, mood = 'nervous' },
    crisis   = { clean = true, mood = 'nervous', melee = 0.45, flee = 0.25, fight = 0.12 },
}

local function NewPid()
    Stats._n = (tonumber(Stats._n) or 1000) + 1
    statsDirty = true
    return 'P' .. Stats._n
end

local function Dob(age)
    local y = tonumber(os.date('%Y')) - age
    return ('%02d/%02d/%d'):format(math.random(1, 28), math.random(1, 12), y)
end

local function AddItem(p, label, extra)
    local it = { label = label, legal = false }
    for k, v in pairs(extra or {}) do it[k] = v end
    p.items[#p.items + 1] = it
end

local function MakePersona(profileKey, gender, extra)
    local pr = PROFILES[profileKey] or PROFILES.public
    local pub = AI.Public
    local clean = pr.clean
    local first = Pick(Config.FirstNames)
    local last = Pick(Config.LastNames)
    local age = math.random(18, 72)
    local p = {
        pid = NewPid(), profile = profileKey, gender = gender == 'f' and 'f' or 'm',
        first = first, last = last, name = first .. ' ' .. last, age = age, dob = Dob(age),
        licence = 'Valid', items = {}, drugs = {}, flags = {}, answers = {},
        bac = 0.0, mood = pr.mood or 'calm', honesty = Range(0.2, 0.95),
        hasId = not Chance(pub.noId), where = Pick(AI.Places), from = Pick(AI.Places),
    }
    if p.where == p.from then p.from = 'home' end

    -- licence
    if pr.noLicence and Chance(pr.noLicence) then p.licence = 'None'
    elseif pr.suspended and Chance(pr.suspended) then p.licence = 'Suspended'
    elseif not clean then
        local r = math.random()
        if r < pub.suspended then p.licence = 'Suspended'
        elseif r < pub.suspended + pub.expired then p.licence = 'Expired'
        elseif r < pub.suspended + pub.expired + pub.noLicence then p.licence = 'None' end
    end

    -- alcohol & drugs
    if pr.bac then p.bac = Range(pr.bac[1], pr.bac[2])
    elseif not clean then
        if Chance(pub.drunk) then p.bac = Range(0.09, 0.2)
        elseif Chance(pub.drinking) then p.bac = Range(0.01, 0.07) end
    end
    if p.bac >= 0.12 then p.mood = 'drunk' end
    local drugKeys = {}
    for k in pairs(Config.Drugs) do drugKeys[#drugKeys + 1] = k end
    table.sort(drugKeys)
    if pr.drug then p.drugs[pr.drug] = true
    elseif pr.drugs or (pr.drugChance and Chance(pr.drugChance)) or (not clean and Chance(pub.drugs)) then p.drugs[Pick(drugKeys)] = true end

    -- warrant / flags / fake name
    local wantChance = pr.warrant or (clean and 0 or pub.warrant)
    if Chance(wantChance) then p.warrant = pr.warrantText or Pick(AI.Warrants) end
    if pr.flag then p.flags[#p.flags + 1] = pr.flag end
    if not clean and Chance(pub.flags) then
        local f = Pick(AI.Flags)
        if f ~= pr.flag then p.flags[#p.flags + 1] = f end
    end
    if p.warrant and Chance(pr.fake or 0.25) and p.honesty < 0.7 then
        p.fake = Pick(Config.FirstNames) .. ' ' .. Pick(Config.LastNames)
    end
    p.priors = not clean and Chance(p.warrant and 0.8 or pub.priors)

    -- what they carry
    for _, it in ipairs(AI.PersonItems) do
        if clean and not it.legal then goto continue end
        local ch = it.chance
        if not it.legal and (pr.loot or pr.gun or pr.drugs or p.warrant) then ch = ch * 2.5 end
        if Chance(ch) then
            p.items[#p.items + 1] = { label = it.label, legal = it.legal, drug = it.drug, weapon = it.weapon }
            if it.drug then p.drugs[it.drug] = p.drugs[it.drug] or Chance(0.6) end
        end
        ::continue::
    end
    if pr.gun or (pr.gunChance and Chance(pr.gunChance)) then
        local g = Pick(pr.guns or AI.SuspectGuns)
        p.weapon = g
        AddItem(p, 'Firearm (' .. g:gsub('WEAPON_', ''):lower() .. ')', { weapon = g })
    elseif pr.melee and Chance(pr.melee) then
        local m = Pick(pr.melees or AI.SuspectMelee)
        p.melee = m
        AddItem(p, 'Weapon (' .. m:gsub('WEAPON_', ''):lower() .. ')', { weapon = m })
    else
        for _, it in ipairs(p.items) do
            if it.weapon then p.melee = it.weapon break end
        end
    end
    for _, it in ipairs(pr.carry or {}) do
        if type(it) == 'table' then AddItem(p, it.label, it) else AddItem(p, it) end
    end
    if pr.noId then p.hasId = false end
    if pr.loot then AddItem(p, Pick({ 'Unpaid merchandise', 'Stolen jewellery', 'Stolen phone', 'Bag of stolen cash', 'Stolen watches' })) end
    if pr.dealer then
        AddItem(p, Pick({ '14 bags of cannabis', '9 wraps of cocaine', 'Bag of 40 pills', '6 bags of meth' }), { drug = 'cocaine', supply = true })
        AddItem(p, 'Digital scales')
        AddItem(p, 'Roll of cash ($1,850)')
    end
    p.gsr = pr.gsr == true

    -- behaviour
    local illegal = 0
    for _, it in ipairs(p.items) do if not it.legal then illegal = illegal + 1 end end
    p.illegal = illegal
    local base = 0.02 + (p.warrant and 0.25 or 0) + math.min(0.3, illegal * 0.1) + (p.licence ~= 'Valid' and 0.08 or 0) + (p.bac >= 0.08 and 0.06 or 0)
    p.flee = Clamp(pr.flee or base, 0, 0.95)
    p.fight = Clamp(pr.fight or ((p.weapon and 0.2 or 0) + (p.mood == 'hostile' and 0.08 or 0) + (p.melee and 0.06 or 0)), 0, 0.95)
    if clean then p.flee, p.fight = 0, 0 end
    p.surrender = Clamp(Range(0.35, 0.9) - p.fight * 0.4, 0.15, 0.95)
    p.consent = Clamp((illegal > 0 and 0.15 or 0.8) + (p.mood == 'hostile' and -0.3 or 0) + (p.honesty - 0.5) * 0.3, 0.02, 0.98)
    p.refuse = pr.refuse == true
    if profileKey == 'hostagetaker' then p.hostage, p.nego = true, 30 end
    if pr.nego then p.hostage, p.nego, p.barricade = true, pr.nego, pr.barricade == true end
    -- how they're feeling, what they've told you, what you've caught them lying about
    local guilty = illegal > 0 or p.warrant or p.bac >= 0.08 or next(p.drugs) ~= nil or pr.stolen or pr.stolenCar
    p.stress = Clamp(({ calm = 15, nervous = 45, hostile = 55, drunk = 30 })[p.mood] or 20, 0, 100) + (guilty and 15 or 0)
    p.rapport = 30
    p.claims, p.lies, p.confessed, p.events = {}, {}, {}, {}
    p.guilty = guilty and true or false
    for k, v in pairs(extra or {}) do p[k] = v end
    if PersonaHook then PersonaHook(p, profileKey) end
    return p
end

-- What the officer's client gets (everything except the dice rolls they shouldn't need to see)
local function Public(p)
    local t = {
        pid = p.pid, profile = p.profile, gender = p.gender, mood = p.mood, fled = p.fled, cuffed = p.cuffed,
        flee = p.flee, fight = p.fight, weapon = p.weapon, melee = p.melee, bac = p.bac, idChecked = p.idChecked,
        name = p.idChecked and p.name or nil, role = p.role,
        stress = math.floor(p.stress or 0), rapport = math.floor(p.rapport or 0), lies = p.lies, confessed = p.confessed,
        caseId = p.caseId, matches = p.matches, hostage = p.hostage, nego = p.nego and math.floor(p.nego) or nil,
        sfst = p.sfst, k9 = p.k9, asked = (function() local l = {} for k in pairs(p.answers or {}) do l[#l + 1] = k end return l end)(),
        warrant = p.idChecked and p.warrant ~= nil or nil,
    }
    if PublicExtra then PublicExtra(p, t) end
    return t
end
function Ev(p, text) p.events = p.events or {} p.events[#p.events + 1] = os.date('%H:%M') .. ' ' .. text end

local function EntityFromNet(netId, kind)
    local ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if kind == 'ped' and (GetEntityType(ent) ~= 1 or IsPedAPlayer(ent)) then return nil end
    if kind == 'veh' and GetEntityType(ent) ~= 2 then return nil end
    if kind == 'any' and GetEntityType(ent) ~= 1 then return nil end
    return ent
end

local function PidOf(ent)
    local st = Entity(ent).state.swai
    return type(st) == 'table' and st.pid or nil
end

local function Near(src, ent, dist)
    return ent and DoesEntityExist(ent) and #(GetEntityCoords(ent) - Pos(src)) <= dist
end

---------------------------------------------------------------------------
-- MDT records for AI people (shown in the MDT just like players)
---------------------------------------------------------------------------
local function PruneRecords()
    local list = {}
    for ident, r in pairs(Records) do
        if ident:sub(1, 3) == 'ai:' then list[#list + 1] = { ident = ident, seen = tonumber(r.seen) or 0 } end
    end
    if #list <= AI.MaxRecords then return end
    table.sort(list, function(a, b) return a.seen < b.seen end)
    for i = 1, #list - AI.MaxRecords do Records[list[i].ident] = nil end
end

local function OldDate()
    return os.date('%d/%m/%Y %H:%M', os.time() - math.random(30, 900) * 86400)
end

local function EnsureRecord(p)
    local ident = p.recordIdent or ('ai:' .. p.pid)
    local r = Records[ident]
    if not r then
        r = Record(ident, p.name)
        r.ai, r.dob, r.licence, r.flags = true, p.dob, p.licence, p.flags
        if p.priors then
            local code = Config.PenalCode
            for _ = 1, math.random(1, 3) do
                local o = code[math.random(1, #code)]
                if Chance(0.55) or o.jail == 0 then
                    table.insert(r.fines, { id = 'H' .. math.random(1000, 9999), date = OldDate(), officer = 'Archive', offences = { o.label },
                        amount = o.fine, paid = Chance(0.7), notes = '' })
                else
                    table.insert(r.arrests, { id = 'H' .. math.random(1000, 9999), date = OldDate(), officer = 'Archive', charges = { o.label },
                        minutes = math.max(1, o.jail), station = 'Archive', notes = '' })
                end
            end
        end
        if p.warrant then
            table.insert(r.warrants, 1, { id = 'W' .. math.random(1000, 9999), date = OldDate(), officer = 'County Court', reason = p.warrant, active = true })
        end
        PruneRecords()
    end
    r.seen = os.time()
    Dirty.records = true
    return ident, r
end

local function Summary(p)
    local ident, r = EnsureRecord(p)
    local s = RecordSummary(ident)
    local warrants = {}
    for _, w in ipairs(s.warrants) do warrants[#warrants + 1] = { reason = w.reason, date = w.date } end
    return {
        ok = true, ident = ident, name = p.name, dob = p.dob, age = p.age, gender = p.gender, licence = p.licence,
        flags = p.flags, warrants = warrants, unpaid = s.unpaid, owed = s.owed, arrests = s.arrests,
        fines = #(r.fines or {}), dna = r.dna == true,
        supervision = SupervisionInfo and SupervisionInfo(p) or nil,
    }
end

---------------------------------------------------------------------------
-- Getting / creating the person behind a ped
---------------------------------------------------------------------------
local PROFILE_OK = {}
for k in pairs(PROFILES) do PROFILE_OK[k] = true end

PoliceCallback('aiPersona', function(src, netId, role, profile, vehNet, gender, story, bindPid)
    local ped = EntityFromNet(netId, 'ped')
    if not ped then return Fail('They\'ve gone.') end
    local pid = PidOf(ped)
    if pid and Personas[pid] then return { ok = true, persona = Public(Personas[pid]) } end
    if not Near(src, ped, 1500.0) then return Fail('Too far away.') end
    if Limited(src, 'persona', 60) then return Fail('Slow down.') end
    profile = PROFILE_OK[profile] and profile or 'public'
    -- special people only exist on the callouts that make them
    if profile == 'crisis' or profile == 'hostagetaker' then
        local pt = Patrol[src]
        local want = profile == 'crisis' and 'crisis' or 'hostage'
        if not (pt and pt.callout and pt.callout.key == want) then profile = 'public' end
    end
    -- some people only exist on the calls that make them (an active shooter, a barricaded subject...)
    local only = PROFILES[profile] and PROFILES[profile].only
    if only then
        local pt = Patrol[src]
        local key = pt and pt.callout and pt.callout.key
        local okKey = false
        for _, k in ipairs(only) do if k == key then okKey = true end end
        if not okKey then profile = 'public' end
    end
    local p
    -- a person made up in advance (the suspect in an investigation)
    local planned = bindPid and Personas[tostring(bindPid)]
    if planned and planned.planned and planned.owner == src then
        p = planned
        p.planned = nil
    else
        p = MakePersona(profile, gender)
    end
    p.role = tostring(role or 'ped'):sub(1, 16)
    if story and AI.Lines['story_' .. tostring(story)] then p.story = tostring(story) end
    p.netId = netId

    -- link the driver to the vehicle's registration
    local veh = vehNet and EntityFromNet(vehNet, 'veh')
    if veh then
        -- only the vehicle they're actually in, and never a player's car
        local drv = GetPedInVehicleSeat(veh, -1)
        if GetVehiclePedIsIn(ped, false) ~= veh or (drv ~= 0 and IsPedAPlayer(drv)) then veh = nil end
    end
    if veh and GeneratePlate then
        local plate = tostring(GetVehicleNumberPlateText(veh) or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8)
        if plate ~= '' then
            local fresh = Plates[plate] == nil and not (RecentDriver and RecentDriver(plate))
            if not fresh and Plates[plate] == nil then plate = '' end
            local rec = plate ~= '' and GeneratePlate(plate) or { contraband = {} }
            p.plate = plate
            if profile == 'stolen' or (PROFILES[profile] and PROFILES[profile].stolenCar) then
                rec.stolen = true
                p.vehicle = 'stolen'
            elseif p.role == 'driver' and not rec.stolen and Chance(0.75) then
                -- usually they own it
                local f, l = tostring(rec.owner):match('^(%S+)%s+(.+)$')
                if f and not p.fake then p.first, p.last, p.name = f, l, rec.owner end
                p.vehicle = 'own'
                rec.ownerWarrant = p.warrant ~= nil
            else
                p.vehicle = rec.stolen and 'stolen' or 'borrowed'
                if rec.stolen and p.role == 'driver' then
                    p.flee = Clamp(math.max(p.flee, 0.45), 0, 0.95)
                    p.guilty = true
                end
            end
            p.vehOwner = rec.owner
            -- whatever they're hiding can be in the car too (only the first time the car is seen)
            if not fresh then rec = { contraband = {} } end
            if p.illegal > 0 and Chance(0.5) then
                rec.contraband = rec.contraband or {}
                rec.contraband[#rec.contraband + 1] = { label = Pick({ 'Bag of white powder', 'Small bag of cannabis', 'Unmarked pills', 'Open container of alcohol' }), seized = false }
            end
            if p.bac >= 0.08 then
                rec.contraband = rec.contraband or {}
                rec.contraband[#rec.contraband + 1] = { label = 'Open container of alcohol', seized = false }
            end
            if p.weapon and Chance(0.4) then
                rec.contraband = rec.contraband or {}
                rec.contraband[#rec.contraband + 1] = { label = 'Spare ammunition', seized = false }
            end
            Dirty.plates = true
        end
    end
    -- people in the same car share a story... unless they're hiding something
    if p.plate and p.plate ~= '' then
        Groups[p.plate] = Groups[p.plate] or { where = p.where, from = p.from, t = os.time(), members = {} }
        local g = Groups[p.plate]
        if p.role ~= 'driver' then
            if p.guilty or g.dirty then
                if Chance(0.55) then p.where = Pick(AI.Places) else p.where = g.where end
            else
                p.where, p.from = g.where, g.from
            end
        else
            g.where, g.from = p.where, p.from
        end
        if p.guilty then g.dirty = true end
        g.members[#g.members + 1] = p.pid
        p.group = p.plate
    end
    p.owner = src
    if PersonaRole and not planned then PersonaRole(src, p) end
    Personas[p.pid] = p
    Ev(p, ('Stopped (%s)'):format(p.role))
    Entity(ped).state:set('swai', { pid = p.pid }, true)
    return { ok = true, persona = Public(p) }
end)

-- Is the officer (or their AI partner, acting for them) close enough?
function NearOrPartner(src, ent, dist)
    if Near(src, ent, dist) then return true end
    local pn = PartnerNet and PartnerNet[src]
    local partner = pn and EntityFromNet(pn, 'any')
    if partner and (Entity(partner).state.swai or not Entity(partner).state.swpd) then PartnerNet[src] = nil return false end
    return partner ~= nil and #(GetEntityCoords(partner) - GetEntityCoords(ent)) <= dist and Near(src, partner, 80.0)
end

local function Get(src, pid, dist)
    local p = Personas[tostring(pid or '')]
    if not p then return nil, Fail('That person isn\'t known.') end
    local ped = EntityFromNet(p.netId, 'ped')
    if dist and (not ped or not NearOrPartner(src, ped, dist)) then return nil, Fail(ped and 'Get closer to them.' or 'They\'ve gone.') end
    return p, ped
end

-- Forget people whose ped is gone (after a while)
CreateThread(function()
    while true do
        Wait(120000)
        local now = os.time()
        for plate, g in pairs(Groups) do if now - g.t > 1800 then Groups[plate] = nil end end
        for pid, p in pairs(Personas) do
            local ped = NetworkGetEntityFromNetworkId(tonumber(p.netId) or 0)
            if p.planned then
                -- someone in an investigation we haven't found yet
            elseif not ped or ped == 0 or not DoesEntityExist(ped) then
                p.goneAt = p.goneAt or now
                if now - p.goneAt > 900 then Personas[pid] = nil end
            else
                p.goneAt = nil
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Conversation
---------------------------------------------------------------------------
local function Honest(p, firm)
    -- rapport makes people more open; pressure only works on someone already sweating
    local chance = p.honesty + ((p.rapport or 30) - 30) / 150 + ((firm and (p.stress or 0) > 60) and 0.12 or 0) - ((p.stress or 0) > 85 and 0.1 or 0)
    return math.random() < chance
end

local function FirstIllegal(p, kind)
    for _, it in ipairs(p.items) do
        if not it.legal and not it.seized and not it.ditched and (kind ~= 'weapon' or it.weapon) then return it.label:lower(), it end
    end
    return nil
end

function Stress(p, n) p.stress = Clamp((p.stress or 0) + n, 0, 100) end
function Rapport(p, n) p.rapport = Clamp((p.rapport or 0) + n, 0, 100) end

-- They own up to something
function Confess(p)
    local it, item = FirstIllegal(p)
    local text
    if it then
        text = Line('confess_item', 'a ' .. it)
        item.confessed = true
        p.confessed[#p.confessed + 1] = 'Admitted carrying ' .. it
    elseif p.warrant and not p.warrantAdmitted then
        p.warrantAdmitted = true
        text = Line('confess_warrant')
        p.confessed[#p.confessed + 1] = 'Admitted knowing about their warrant'
    elseif p.bac >= 0.06 and not p.drinkAdmitted then
        p.drinkAdmitted = true
        text = Line('drink_lots_honest')
        p.confessed[#p.confessed + 1] = 'Admitted drinking before driving'
    elseif next(p.drugs) and not p.drugsAdmitted then
        p.drugsAdmitted = true
        text = Line('drugs_honest')
        p.confessed[#p.confessed + 1] = 'Admitted taking drugs'
    end
    if text then Ev(p, 'Confession: ' .. p.confessed[#p.confessed]) end
    return text
end

local QUESTIONS = {
    greet = function(p)
        if p.knowsYou and not p.greetedKnown then p.greetedKnown = true return Line('known_you') end
        return Line('greet_' .. (p.mood == 'drunk' and 'drunk' or p.mood == 'hostile' and 'hostile' or p.mood == 'nervous' and 'nervous' or 'calm'))
    end,
    why = function(p, firm)
        if p.mood == 'hostile' then return Line('why_hostile') end
        return Honest(p, firm) and Line('why_honest') or Line('why_unsure')
    end,
    where = function(p)
        p.claims.where = p.where
        return Line(p.stress > 55 and 'where_nervous' or 'where', p.where)
    end,
    where_who = function(p)
        if p.guilty and p.stress > 50 then return Line('where_who_vague') end
        return Line('where_who', Pick(Config.FirstNames))
    end,
    where_why = function(p) return Line(p.guilty and p.stress > 45 and 'where_why_vague' or 'where_why') end,
    from = function(p) return Line('from', p.from) end,
    from_long = function(p) return Line(p.bac >= 0.06 and 'from_long_bar' or 'from_long') end,
    drink = function(p, firm)
        if p.bac >= 0.12 then p.claims.drink = 'some' return Line('drink_slurred') end
        if p.bac >= 0.06 then
            if Honest(p, firm) then p.claims.drink = 'lots' p.drinkAdmitted = true return Line('drink_lots_honest') end
            p.claims.drink = 'none'
            return Line('drink_lie')
        end
        if p.bac > 0.01 then p.claims.drink = 'couple' return Line('drink_couple') end
        p.claims.drink = 'none'
        return Line('drink_no')
    end,
    drink_count = function(p, firm)
        if p.bac >= 0.06 and not Honest(p, firm) then return Line('drink_count_low') end
        if p.bac >= 0.06 then p.claims.drink = 'lots' return Line('drink_count_high', tostring(math.max(3, math.floor(p.bac * 40)))) end
        if p.bac > 0.01 then return Line('drink_count_low') end
        return Line('drink_no')
    end,
    drink_when = function(p)
        if p.bac >= 0.06 then return Line('drink_when_recent') end
        if p.bac > 0.01 then return Line('drink_when_earlier') end
        return Line('drink_no')
    end,
    drugs = function(p, firm)
        if next(p.drugs) then
            if Honest(p, firm) then p.claims.drugs = true p.drugsAdmitted = true return Line('drugs_honest') end
            p.claims.drugs = false
            return Line('drugs_lie')
        end
        p.claims.drugs = false
        return Line('drugs_no')
    end,
    drugs_what = function(p, firm)
        local k = next(p.drugs)
        if k and Honest(p, firm) then return Line('drugs_what', (Config.Drugs[k] or k):lower()) end
        return Line('drugs_lie')
    end,
    illegal = function(p, firm)
        local it = FirstIllegal(p)
        if it then
            if Honest(p, firm) and p.honesty > 0.55 then p.claims.illegal = true return Line('illegal_honest', 'a ' .. it) end
            p.claims.illegal = false
            return Line('illegal_lie')
        end
        p.claims.illegal = false
        return Line('illegal_no')
    end,
    illegal_again = function(p, firm)
        Stress(p, 10)
        if FirstIllegal(p) and (p.stress > 70 or Honest(p, firm)) and Chance(0.55) then
            p.claims.illegal = true
            return Confess(p) or Line('illegal_lie')
        end
        return Line(FirstIllegal(p) and 'illegal_again_hold' or 'illegal_no')
    end,
    weapons = function(p, firm)
        local it = FirstIllegal(p, 'weapon')
        if it then
            if Honest(p, firm) and p.mood ~= 'hostile' then p.claims.weapons = true return Line('weapons_honest', 'a ' .. it) end
            p.claims.weapons = false
            return Line('weapons_lie')
        end
        p.claims.weapons = false
        return Line('weapons_no')
    end,
    weapons_again = function(p, firm)
        Stress(p, 8)
        local it = FirstIllegal(p, 'weapon')
        if it and (Honest(p, firm) or p.stress > 80) then p.claims.weapons = true return Line('weapons_honest', 'a ' .. it) end
        return Line(it and 'illegal_again_hold' or 'weapons_no')
    end,
    owner = function(p)
        if p.vehicle == 'own' then p.claims.owner = 'own' return Line('owner_yes') end
        if p.vehicle == 'stolen' then p.claims.owner = 'own' return Line('owner_lie') end
        if p.vehicle == 'borrowed' then p.claims.owner = 'friend' return Line('owner_friend', p.vehOwner or 'a friend') end
        return 'I\'m not in a vehicle.'
    end,
    owner_name = function(p)
        if p.vehicle == 'own' then return Line('owner_name_self', p.name) end
        if p.vehicle == 'borrowed' then return Line('owner_name_right', p.vehOwner or 'my friend') end
        if p.vehicle == 'stolen' then Stress(p, 12) return Line('owner_name_wrong') end
        return 'What vehicle?'
    end,
    story = function(p)
        local key = p.story and ('story_' .. p.story) or 'story_none'
        return Line(AI.Lines[key] and key or 'story_none')
    end,
    calm = function(p)
        if p.mood == 'hostile' and Chance(0.5) then Stress(p, 4) return Line('calm_no') end
        p.fight = p.fight * 0.6
        p.flee = p.flee * 0.8
        Stress(p, -15)
        Rapport(p, 8)
        if p.mood == 'hostile' then p.mood = 'nervous' end
        return Line('calm_ok')
    end,
    honest = function(p)
        Rapport(p, 10)
        Stress(p, -4)
        if p.guilty and p.rapport >= 55 and Chance(0.4) then return Confess(p) or Line('honest_ok') end
        return Line(p.guilty and 'honest_guilty' or 'honest_ok')
    end,
    anything = function(p, firm)
        if not p.guilty then return Line('anything_none') end
        local chance = 0.12 + (p.rapport - 30) / 120 + (p.stress > 65 and 0.15 or 0) + (#p.lies * 0.12)
        if Chance(chance) then return Confess(p) or Line('anything_none') end
        Stress(p, 6)
        return Line('anything_lie')
    end,
    warrant = function(p, firm)
        if not p.warrant then return Line('warrant_none') end
        Stress(p, 15)
        if Honest(p, firm) then p.warrantAdmitted = true return Line('warrant_admit') end
        return Line('warrant_deny')
    end,
    leave = function(p)
        -- trespass callouts: ask them to leave
        if p.refuse and Chance(0.7) then Stress(p, 5) return Line('story_trespass'), { refuse = true } end
        return 'Fine, I\'m going.', { leaves = true }
    end,
}

-- Follow-up questions open up once the first question has been asked
local FOLLOWS = { where = { 'where_who', 'where_why' }, from = { 'from_long' }, drink = { 'drink_count', 'drink_when' }, drugs = { 'drugs_what' },
    illegal = { 'illegal_again' }, weapons = { 'weapons_again' }, owner = { 'owner_name' } }
local PARENT = {}
for parent, list in pairs(FOLLOWS) do for _, q in ipairs(list) do PARENT[q] = parent end end
local REPEATABLE = { calm = true, leave = true, greet = true, honest = true, anything = true, illegal_again = true, weapons_again = true }

local function StoryCheck(src, p)
    -- occupants telling different stories about where they're going
    local g = p.group and Groups[p.group]
    if not g or not p.claims.where then return end
    for _, other in ipairs(g.members) do
        local o = Personas[other]
        if o and o ~= p and o.claims.where and o.claims.where ~= p.claims.where then
            CatchLie(src, p, 'story', ('Says they\'re going to %s - %s said %s'):format(p.claims.where, o.idChecked and o.name or 'the other occupant', o.claims.where))
            CatchLie(src, o, 'story', ('Says they\'re going to %s - %s said %s'):format(o.claims.where, p.idChecked and p.name or 'the other occupant', p.claims.where))
        end
    end
end

PoliceCallback('aiAsk', function(src, pid, q, tone)
    local p, err = Get(src, pid, 12.0)
    if not p then return err end
    if Limited(src, 'ask', 80) then return Fail('Slow down.') end
    local fn = QUESTIONS[q]
    if not fn then return Fail() end
    if PARENT[q] and not p.answers[PARENT[q]] then return Fail('Ask the first question first.') end
    if q == 'warrant' and not p.idChecked then return Fail('Check who they are first.') end
    local firm = tone == 'firm'
    if LanguageGate then
        local blocked = LanguageGate(p, q)
        if blocked then return { ok = true, say = blocked, persona = Public(p), language = true } end
    end
    -- keep the same answer to the same question (people don't change their story every time)
    local keep = not REPEATABLE[q]
    if keep and p.answers[q] then return { ok = true, say = p.answers[q], persona = Public(p), repeated = true } end
    -- tone of voice: firm raises the pressure, friendly builds rapport
    p.toned = (p.toned or 0) + 1
    if p.toned <= 14 then
        if firm then Stress(p, 5) Rapport(p, -3) else Rapport(p, 2) end
        if Emote then Emote(p, firm and 'firm' or 'calm') end
    end
    local say, extra = fn(p, firm)
    if InterpreterPrefix then say = InterpreterPrefix(p, say) end
    if keep then p.answers[q] = say end
    if q == 'where' then StoryCheck(src, p) end
    local out = { ok = true, say = say, persona = Public(p) }
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end)

-- Asking for consent to search
PoliceCallback('aiConsent', function(src, pid, what)
    if what ~= 'person' and what ~= 'vehicle' then return Fail() end
    local p, err = Get(src, pid, 12.0)
    if not p then return err end
    if LanguageGate and LanguageGate(p, 'consent') then
        return { ok = true, yes = false, say = LanguageGate(p, 'consent'), msg = 'They don\'t understand you - consent isn\'t valid. Use the interpreter line.' }
    end
    p.consentGiven = p.consentGiven or {}
    if p.consentGiven[what] == nil then p.consentGiven[what] = Chance(p.consent) end
    local yes = p.consentGiven[what]
    return { ok = true, yes = yes, say = Line(yes and 'consent_yes' or 'consent_no') }
end)

-- Name / ID checks
PoliceCallback('aiCheckId', function(src, pid, mode)
    local p, err = Get(src, pid, 12.0)
    if not p then return err end
    if mode == 'card' then
        if not p.hasId then return { ok = true, noId = true, say = Line('noid') } end
        p.idChecked = true
        local s = Summary(p)
        s.say = Line('hand_id')
        s.card = true
        p.claims.name = p.name
        if CaseFlags then CaseFlags(p, s) end
        Ev(p, 'Produced ID: ' .. p.name)
        return s
    end
    -- asked for their name
    if p.mood == 'hostile' and not p.cuffed and Chance(0.35) and not p.gaveName then
        return { ok = true, refused = true, say = Line('name_refuse') }
    end
    p.gaveName = true
    p.claims.name = p.fake or p.name
    if p.fake then
        return { ok = true, said = p.fake, say = Line('name_give', p.fake), notFound = true, name = p.fake,
            dob = Dob(math.random(19, 60)) }
    end
    p.idChecked = true
    local s = Summary(p)
    s.said = p.name
    s.say = Line('name_give', p.name)
    if CaseFlags then CaseFlags(p, s) end
    Ev(p, 'Gave name: ' .. p.name)
    return s
end)

-- Fingerprints at the roadside / when booking find out who someone really is
PoliceCallback('aiPrints', function(src, pid)
    local p, err = Get(src, pid, 4.0)
    if not p then return err end
    if not p.cuffed then return Fail('Restrain them first.') end
    if p.fake and p.claims.name == p.fake then CatchLie(src, p, 'name', ('Gave a false name (%s) - prints say %s'):format(p.fake, p.name)) end
    p.idChecked = true
    p.fake = nil
    local s = Summary(p)
    s.prints = true
    if CaseFlags then CaseFlags(p, s) end
    Ev(p, 'Identified by fingerprints: ' .. p.name)
    return s
end)

---------------------------------------------------------------------------
-- Reactions (does this person comply, run or fight?)
---------------------------------------------------------------------------
PoliceCallback('aiReact', function(src, pid, moment)
    local p, err = Get(src, pid, 300.0)
    if not p then return err end
    if Limited(src, 'react', 90) then return { ok = true, act = 'comply' } end
    local act = 'comply'
    -- stressed people run, people you've built rapport with don't
    local m = (0.65 + (p.stress or 30) / 140) * (1.2 - (p.rapport or 30) / 160)
    local flee0, fight0 = p.flee, p.fight
    local ef, eg = 1, 1
    if EmotionMod then ef, eg = EmotionMod(p, moment) end
    p.flee, p.fight = Clamp(p.flee * m * ef, 0, 0.97), Clamp(p.fight * m * eg, 0, 0.97)
    if p.surrendered and moment ~= 'aimed' then
        act = 'comply'
    elseif moment == 'stop' then
        if Chance(p.flee) then act = 'flee' elseif p.weapon and Chance(p.fight * 0.25) then act = 'fight' end
    elseif moment == 'out' then
        if Chance(p.flee * 0.35) then act = 'flee' elseif p.weapon and Chance(p.fight * 0.35) then act = 'fight' end
    elseif moment == 'search' then
        if p.illegal > 0 and Chance(p.flee * 0.45) then act = 'flee' elseif (p.weapon or p.melee) and Chance(p.fight * 0.4) then act = 'fight' end
    elseif moment == 'cuff' then
        if Chance(p.flee * 0.5) then act = 'flee' elseif Chance(p.fight * 0.35) then act = 'fight' end
        if act == 'comply' then p.cuffTry = os.time() end
    elseif moment == 'felony' then
        -- ordered out at gunpoint: most comply, the desperate run
        if Chance(p.flee * 0.25) then act = 'flee' elseif p.weapon and Chance(p.fight * 0.2) then act = 'fight' end
    elseif moment == 'approach' then
        if Chance(p.fight * 0.7) then act = 'fight' elseif Chance(p.flee * 0.7) then act = 'flee' end
    elseif moment == 'aimed' then
        act = Chance(p.surrender * 0.35) and 'surrender' or 'keep'
    elseif moment == 'knock' then
        -- someone knocking at a wanted person's door: answer, run out the back, hide, or fight from inside
        if Chance(p.fight * 0.55) and (p.weapon or p.melee) then act = 'fight'
        elseif Chance(p.flee * 0.7) then act = 'flee'
        elseif Chance(0.35 + (p.stress or 30) / 300) then act = 'hide'
        else act = 'comply' end
    elseif moment == 'raid' then
        -- police coming through the door
        if Chance(p.surrender * 0.8) then act = 'surrender'
        elseif (p.weapon or p.melee) and Chance(p.fight + 0.1) then act = 'fight'
        elseif Chance(0.5) then act = 'hide'
        else act = 'flee' end
    elseif moment == 'cornered' then
        act = Chance(p.surrender) and 'surrender' or (Chance(p.fight + 0.15) and 'fight' or 'flee')
    end
    local reach
    if act == 'comply' and ReachRoll and not p.hostage then
        reach = ReachRoll(p, moment)
        if reach then act = 'reach' end
    end
    if Emote then Emote(p, 'moment_' .. tostring(moment)) end
    if act == 'fight' then p.fought = true end
    if act == 'flee' or act == 'fight' then
        p.fled = true
        p.mood = 'hostile'
        if not p.resisted then p.resisted = true end
    elseif act == 'surrender' then
        p.surrendered = true
    end
    p.flee, p.fight = flee0, fight0
    if p.hostage and moment == 'approach' then
        -- rushed: they let go of the hostage and run or fight
        p.hostage = false
        if act ~= 'flee' and act ~= 'fight' then act = Chance(0.5) and 'flee' or 'fight' end
    end
    if moment == 'felony' and act ~= 'flee' and act ~= 'fight' then act = 'comply' end
    if act == 'flee' then Ev(p, 'Ran from police') elseif act == 'fight' then Ev(p, 'Attacked / resisted police') elseif act == 'surrender' then Ev(p, 'Surrendered') end
    if moment == 'cuff' or moment == 'search' or moment == 'out' then Stress(p, 6) end
    local say = act == 'flee' and Line('flee') or act == 'fight' and Line('fight') or act == 'surrender' and Line('surrender') or nil
    if act == 'reach' then say = Line('reach_start') end
    return { ok = true, act = act, say = say, reach = reach, persona = Public(p) }
end)

PoliceCallback('aiState', function(src, pid, key, value)
    local p, err = Get(src, pid, 30.0)
    if not p then return err end
    if key == 'cuffed' then
        if value == true then
            local ped = EntityFromNet(p.netId, 'ped')
            if not ped or not NearOrPartner(src, ped, 4.0) then return Fail('Get closer to them.') end
            if not p.surrendered and os.time() - (p.cuffTry or 0) > 30 then return Fail('They aren\'t letting you cuff them.') end
        end
        p.cuffed = value == true
        if p.cuffed then p.surrendered = true end
        return { ok = true, say = p.cuffed and Line((p.mood == 'hostile' or p.resisted) and 'cuffed_angry' or 'cuffed_calm') or nil }
    elseif key == 'surrendered' then
        p.surrendered = value == true
    end
    return { ok = true }
end)

---------------------------------------------------------------------------
-- Tests and searches
---------------------------------------------------------------------------
PoliceCallback('aiTest', function(src, pid, kind)
    local p, err = Get(src, pid, 5.0)
    if not p then return err end
    if Limited(src, 'test', 40) then return Fail('Slow down.') end
    local name = p.idChecked and p.name or 'Subject'
    p.results = p.results or {}
    if SFST and SFST[kind] then
        if LanguageGate and LanguageGate(p, 'sfst') then return Fail('They don\'t understand your instructions - use the interpreter line first.') end
        return SFST[kind](src, p, name)
    end
    if kind == 'breath' then
        local bac = math.floor((p.bac + Range(-0.004, 0.004)) * 1000 + 0.5) / 1000
        bac = math.max(0, bac)
        p.results.breath = bac
        Ev(p, ('Breath test: %.3f%%'):format(bac))
        if (p.claims.drink == 'none' and bac >= 0.03) or (p.claims.drink == 'couple' and bac >= 0.10) then
            CatchLie(src, p, 'drink', ('Said they\'d had %s to drink - blew %.3f%%'):format(p.claims.drink == 'none' and 'nothing' or 'one or two', bac))
        end
        return { ok = true, kind = 'breath', name = name, bac = bac, over = bac >= Config.DrinkLimit, limit = Config.DrinkLimit, persona = Public(p) }
    elseif kind == 'drug' then
        local res, pos = {}, false
        local keys = {}
        for k in pairs(Config.Drugs) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local hit = p.drugs[k] == true
            pos = pos or hit
            res[#res + 1] = { label = Config.Drugs[k], positive = hit }
        end
        p.results.drug = pos
        Ev(p, 'Drug swab: ' .. (pos and 'positive' or 'negative'))
        if pos and p.claims.drugs == false then CatchLie(src, p, 'drugs', 'Denied taking drugs - the swab came back positive') end
        return { ok = true, kind = 'drug', name = name, positive = pos, results = res, persona = Public(p) }
    elseif kind == 'gsr' then
        p.results.gsr = p.gsr == true
        Ev(p, 'GSR test: ' .. (p.gsr and 'positive' or 'negative'))
        return { ok = true, kind = 'gsr', name = name, positive = p.gsr == true }
    elseif kind == 'frisk' or kind == 'search' then
        local out = {}
        for i, it in ipairs(p.items) do
            if not it.seized and (kind == 'search' or it.weapon) then
                out[#out + 1] = { index = i, label = it.label, legal = it.legal }
            end
        end
        p.searched = p.searched or kind == 'search'
        for _, o in ipairs(out) do
            if not o.legal then
                local it = p.items[o.index]
                if it.weapon and p.claims.weapons == false then CatchLie(src, p, 'weapons', 'Denied carrying weapons - found ' .. it.label:lower()) end
                if p.claims.illegal == false and not it.weapon then CatchLie(src, p, 'illegal', 'Said they had nothing illegal - found ' .. it.label:lower()) end
            end
        end
        Ev(p, (kind == 'search' and 'Searched' or 'Patted down') .. (#out > 0 and (': found ' .. #out .. ' item(s)') or ': nothing found'))
        for _, o in ipairs(out) do p.items[o.index].found = true end
        if SearchCheck then SearchCheck(src, p, kind, out) end
        return { ok = true, kind = 'person', full = kind == 'search', name = name, items = out, persona = Public(p) }
    elseif kind == 'dna' then
        local ident, r = EnsureRecord(p)
        r.dna = true
        Dirty.records = true
        return { ok = true, kind = 'dna', name = name, msg = 'DNA sample taken and added to the database.' }
    end
    return Fail()
end)

PoliceCallback('aiSeize', function(src, pid, index)
    local p, err = Get(src, pid, 5.0)
    if not p then return err end
    if Limited(src, 'seize', 20) then return Fail('Slow down.') end
    local it = p.items[tonumber(index) or 0]
    if not it or it.seized then return Fail('Nothing to seize.') end
    if not p.searched and not it.weapon then return Fail('Search them first.') end
    it.seized = true
    if it.weapon and (it.weapon == p.weapon or it.weapon == p.melee) then
        if it.weapon == p.weapon then p.weapon = nil end
        if it.weapon == p.melee then p.melee = nil end
        p.fight = p.fight * 0.4
    end
    if not it.legal then p.illegal = math.max(0, p.illegal - 1) end
    AddToLocker(src, { type = 'item', label = it.label, from = (p.idChecked and p.name or 'Unknown person') })
    p.seizedList = p.seizedList or {}
    p.seizedList[#p.seizedList + 1] = it.label
    Ev(p, 'Seized: ' .. it.label)
    Bump(src, 'seized')
    Log(src, 'Seized ' .. it.label)
    return { ok = true, msg = it.label .. ' seized and logged in the evidence locker.', persona = Public(p), disarm = it.weapon }
end)

---------------------------------------------------------------------------
-- Outcomes: warning, citation, arrest, release
---------------------------------------------------------------------------
PoliceCallback('aiWarn', function(src, pid, notes)
    local p, err = Get(src, pid, 15.0)
    if not p then return err end
    if Limited(src, 'outcome', 12) then return Fail('Slow down.') end
    if p.warned then return Fail('You\'ve already warned them.') end
    p.warned = true
    local ident, r = EnsureRecord(p)
    table.insert(r.notes, 1, { id = NewCaseId('N'), date = Stamp(), officer = OfficerLabel(src), text = 'Verbal warning. ' .. CleanText(notes, 200) })
    Bump(src, 'warnings')
    Log(src, 'Warning: ' .. p.name)
    if Encounter then Encounter(src, p, 'warning') end
    return { ok = true, say = Line('warned'), msg = 'Warning recorded.' }
end)

PoliceCallback('aiCite', function(src, pid, offences, notes)
    local p, err = Get(src, pid, 15.0)
    if not p then return err end
    if Limited(src, 'outcome', 12) then return Fail('Slow down.') end
    if (p.cites or 0) >= 3 then return Fail('That\'s enough tickets for one person.') end
    local labels, fine = Offences(offences)
    if #labels == 0 then return Fail('Pick at least one offence.') end
    p.cites = (p.cites or 0) + 1
    local ident, r = EnsureRecord(p)
    local case = NewCaseId('C')
    table.insert(r.fines, 1, { id = case, date = Stamp(), officer = OfficerLabel(src), offences = labels, amount = fine,
        notes = CleanText(notes), paid = false })
    Dirty.records = true
    Bump(src, 'citations')
    Log(src, ('Citation %s: %s'):format(case, p.name))
    if Encounter then Encounter(src, p, 'citation') end
    local unhappy = p.mood == 'hostile' or fine >= 750
    return { ok = true, say = Line(unhappy and 'cited_bad' or 'cited_ok'), msg = ('Citation %s issued to %s - %s.'):format(case, p.name, Money(fine)) }
end)

PoliceCallback('aiArrest', function(src, pid, offences, minutes, notes, how)
    local p, err = Get(src, pid, 40.0)
    if not p then return err end
    if p.booked then return Fail('Already booked.') end
    if not p.cuffed then return Fail('They need to be restrained.') end
    if Limited(src, 'outcome', 12) then return Fail('Slow down.') end
    if how ~= 'station' and how ~= 'transport' then return Fail() end
    if how == 'transport' then
        local t = TransportReq[src]
        if not t or os.time() - t > 600 then return Fail('Request prisoner transport first.') end
    end
    local labels, fine, jail = Offences(offences)
    if #labels == 0 then return Fail('Pick at least one charge.') end
    if how == 'station' and not Config.BookAnywhere and not NearStation(src) then return Fail('Get to a station booking desk first.') end
    minutes = Clamp(math.floor(tonumber(minutes) or jail), 1, Config.Jail.maxMinutes)
    p.booked = true
    p.idChecked = true
    p.fake = nil
    local ident, r = EnsureRecord(p)
    local case = NewCaseId('A')
    local where = how == 'transport' and 'Prisoner transport' or ((NearStation(src) or {}).label or 'Field')
    table.insert(r.arrests, 1, { id = case, date = Stamp(), officer = OfficerLabel(src), charges = labels, minutes = minutes,
        fine = fine, notes = CleanText(notes), station = where })
    r.dna, r.prints = true, true
    for _, w in ipairs(r.warrants) do if w.active then w.active = false w.served = Stamp() end end
    Dirty.records = true
    Bump(src, 'arrests')
    Log(src, ('Arrest %s: %s (%d min)'):format(case, p.name, minutes))
    Ev(p, 'Arrested and booked (' .. where .. ')')
    if OnArrest then OnArrest(src, p, case, labels, ident) end
    if Encounter then Encounter(src, p, 'arrest') end
    if ChildCheckOnArrest then ChildCheckOnArrest(src, p) end
    return { ok = true, case = case, msg = ('%s booked - %s, %d minutes. Write your arrest report in the patrol computer.'):format(p.name, case, minutes) }
end)

PoliceCallback('aiRelease', function(src, pid)
    local p, ped = Get(src, pid)
    if p and (p.owner == src or (ped and Near(src, ped, 30.0))) and not p.released then
        p.released = true
        if Encounter and p.idChecked then Encounter(src, p, 'released') end
    end
    return { ok = true, say = p and Line('released') or nil }
end)

---------------------------------------------------------------------------
-- Vehicles
---------------------------------------------------------------------------
PoliceCallback('aiVehicle', function(src, netId, pid)
    local veh = EntityFromNet(netId, 'veh')
    if not veh then return Fail('No vehicle.') end
    if not Near(src, veh, 40.0) then return Fail('Too far away.') end
    local plate = tostring(GetVehicleNumberPlateText(veh) or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8)
    local drv = GetPedInVehicleSeat(veh, -1)
    if ((drv ~= 0 and IsPedAPlayer(drv)) or (RecentDriver and RecentDriver(plate))) and not Plates[plate] then
        return Fail('That\'s a player\'s vehicle - use the F7 police menu.')
    end
    if plate == '' or not GeneratePlate then return Fail() end
    local rec = GeneratePlate(plate)
    local flags = {}
    if rec.stolen then flags[#flags + 1] = 'REPORTED STOLEN' end
    if rec.ownerWarrant then flags[#flags + 1] = 'Registered owner has an active warrant' end
    if rec.reg ~= 'Valid' then flags[#flags + 1] = 'Registration: ' .. rec.reg end
    if rec.insurance ~= 'Insured' then flags[#flags + 1] = 'No insurance on record' end
    if (rec.impounds or 0) > 0 then flags[#flags + 1] = ('Impounded %d time(s) before'):format(rec.impounds) end
    local p = pid and Personas[tostring(pid)]
    if p and p.plate == plate then
        if rec.stolen and p.claims.owner == 'own' then CatchLie(src, p, 'owner', 'Claimed the vehicle was theirs - it\'s reported stolen') end
        if rec.stolen then p.stolenCar = true end
        Ev(p, 'Plate ' .. plate .. ' run' .. (rec.stolen and ' - REPORTED STOLEN' or ''))
    end
    return { ok = true, plate = plate, owner = rec.owner, reg = rec.reg, insurance = rec.insurance, flags = flags }
end)

PoliceCallback('aiVehSearch', function(src, netId, pid)
    local veh = EntityFromNet(netId, 'veh')
    if not veh or not Near(src, veh, 6.0) then return Fail('Get closer to the vehicle.') end
    local plate = tostring(GetVehicleNumberPlateText(veh) or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8)
    local drv = GetPedInVehicleSeat(veh, -1)
    if ((drv ~= 0 and IsPedAPlayer(drv)) or (RecentDriver and RecentDriver(plate))) and not Plates[plate] then
        return Fail('That\'s a player\'s vehicle - use the F7 police menu.')
    end
    local rec = GeneratePlate and GeneratePlate(plate)
    if not rec then return Fail() end
    local out = {}
    for i, c in ipairs(rec.contraband or {}) do
        if not c.seized then out[#out + 1] = { index = i, label = c.label } end
    end
    local g = Groups[plate]
    if #out > 0 and g then
        for _, m in ipairs(g.members) do
            local o = Personas[m]
            if o and o.role == 'driver' and o.claims.illegal == false then
                CatchLie(src, o, 'vehicle', 'Said there was nothing illegal - found ' .. out[1].label:lower() .. ' in the vehicle')
            end
            if o then o.vehFinds = (o.vehFinds or 0) + #out Ev(o, 'Vehicle searched: ' .. #out .. ' item(s) found') end
        end
    end
    return { ok = true, kind = 'vehicle', plate = plate, items = out }
end)

PoliceCallback('aiVehSeize', function(src, netId, index)
    if Limited(src, 'seize', 20) then return Fail('Slow down.') end
    local veh = EntityFromNet(netId, 'veh')
    if not veh or not Near(src, veh, 6.0) then return Fail('Get closer to the vehicle.') end
    local plate = tostring(GetVehicleNumberPlateText(veh) or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8)
    local rec = Plates[plate]
    local c = rec and rec.contraband and rec.contraband[tonumber(index) or 0]
    if not c or c.seized then return Fail('Nothing to seize.') end
    c.seized = true
    Dirty.plates = true
    AddToLocker(src, { type = 'vehicle', label = c.label, from = 'Vehicle ' .. plate })
    for _, m in ipairs((Groups[plate] or {}).members or {}) do
        local o = Personas[m]
        if o and o.role == 'driver' then o.seizedList = o.seizedList or {} o.seizedList[#o.seizedList + 1] = c.label .. ' (vehicle)' Ev(o, 'Seized from vehicle: ' .. c.label) end
    end
    Bump(src, 'seized')
    return { ok = true, msg = c.label .. ' seized and logged in the evidence locker.' }
end)

PoliceCallback('aiTowed', function(src, plate)
    if Limited(src, 'towed', 6) then return { ok = true } end
    plate = tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8)
    local rec = Plates[plate]
    if rec then rec.impounds = (rec.impounds or 0) + 1 Dirty.plates = true end
    Log(src, 'Vehicle towed: ' .. plate)
    return { ok = true }
end)

---------------------------------------------------------------------------
-- Patrol, callouts and stats
---------------------------------------------------------------------------
local function CalloutDef(key)
    for _, c in ipairs(AI.Callouts) do if c.key == key and c.enabled ~= false then return c end end
    return nil
end

local function PickCallout(src)
    local boost = {}
    local div = src and DivisionOf and DivisionOf(src)
    for _, d in ipairs(AI.Divisions or {}) do
        if d.key == div then for _, k in ipairs(d.callouts or {}) do boost[k] = AI.DivisionBoost or 3.0 end end
    end
    local function W(c)
        local w = (c.weight or 1) * (boost[c.key] or 1)
        if CalloutWeightMod then w = w * (CalloutWeightMod(src, c) or 1) end
        return w
    end
    local total = 0
    for _, c in ipairs(AI.Callouts) do if c.enabled ~= false then total = total + W(c) end end
    if total <= 0 then return nil end
    local roll = math.random() * total
    for _, c in ipairs(AI.Callouts) do
        if c.enabled ~= false then
            roll = roll - W(c)
            if roll <= 0 then return c end
        end
    end
    return AI.Callouts[1]
end

local function Gap(range) return math.random(range[1], range[2]) end

local function PatrolState(src)
    local p = Patrol[src]
    return {
        ok = true, on = p and p.on or false, busy = p and p.busy or false,
        callout = p and p.callout and { key = p.callout.key, id = p.callout.id, title = p.callout.title, code = p.callout.code, text = p.callout.text } or nil,
        shift = p and p.shift or {}, log = p and p.log or {}, total = StatsOf(src) or {},
        nextIn = p and p.on and not p.busy and math.max(0, p.nextAt - os.time()) or nil,
        rank = RankOf((StatsOf(src) or {}).xp or 0), paused = p and p.paused or false,
        division = DivisionOf and DivisionOf(src) or 'patrol', admin = IsAdmin(src),
    }
end

local function NewPatrol(src)
    Patrol[src] = Patrol[src] or { on = false, busy = false, nextAt = 0, shift = {}, log = {}, started = os.time() }
    return Patrol[src]
end

PoliceCallback('patrolState', function(src) return PatrolState(src) end)

PoliceCallback('patrolPause', function(src, on)
    local p = NewPatrol(src)
    p.paused = on == true
    if p.paused then p.offer = nil end
    Log(src, p.paused and '10-6 (busy)' or '10-8 (in service)')
    return PatrolState(src)
end)

PoliceCallback('patrolToggle', function(src, on)
    local p = NewPatrol(src)
    p.on = on == true
    p.busy, p.callout, p.stopBusy, p.offer = false, nil, false, nil
    if p.on then
        p.nextAt = os.time() + Gap(AI.FirstCallout)
        Log(src, 'AI patrol on')
    else
        p.offer = nil
        Log(src, 'AI patrol off')
    end
    return PatrolState(src)
end)

RegisterNetEvent(EV .. 'aiBusy', function(busy)
    local src = source
    if not IsPolice(src) then return end
    local p = NewPatrol(src)
    p.stopBusy = busy == true
end)

PoliceCallback('aiStopStarted', function(src, kind, pid)
    local p = Personas[tostring(pid or '')]
    if not p or p.owner ~= src or p.stopCounted then return { ok = true } end
    p.stopCounted = true
    if Limited(src, 'stopstat', 8) then return { ok = true } end
    Bump(src, 'stops')
    Log(src, kind == 'ped' and 'Pedestrian stop' or 'Traffic stop')
    return { ok = true }
end)

PoliceCallback('aiPursuit', function(src)
    if Limited(src, 'pursuit', 4) then return { ok = true } end
    Bump(src, 'pursuits')
    Log(src, 'Pursuit started')
    for _, pl in ipairs(GetPlayers()) do
        pl = tonumber(pl)
        if pl ~= src and IsPolice(pl) and Patrol[pl] and Patrol[pl].on then
            Notify(pl, ('~r~%s~s~ is in pursuit.'):format(OfficerLabel(src)))
        end
    end
    return { ok = true }
end)

local function AcceptCallout(src, id)
    local p = Patrol[src]
    if not p or not p.offer or p.offer.id ~= id then return Fail('That callout has gone.') end
    local c = p.offer.def
    p.callout = { key = c.key, id = id, title = c.title, code = c.code, text = c.text, started = os.time(), loc = p.offer.loc,
        incident = p.offer.incident, nature = c.nature, prio = c.prio or (c.code == 3 and 1 or 2), notes = c.notes, units = c.units }
    if PlaceTaken then PlaceTaken(src, p.offer.loc) end
    if CadAccepted then CadAccepted(src, p.offer) end
    p.offer = nil
    p.busy = true
    Log(src, 'Responding: ' .. c.title)
    if c.team and BackupRequest then
        SetTimeout(4000, function() if Online(src) then BackupRequest(src, 'Assist: ' .. c.title, nil, c.code) end end)
    end
    return { ok = true, callout = p.callout }
end
PoliceCallback('calloutAccept', AcceptCallout)

PoliceCallback('calloutDecline', function(src, id)
    local p = Patrol[src]
    if p and p.offer and p.offer.id == id then
        if CadReleased then CadReleased(p.offer) end
        p.offer = nil
        p.nextAt = os.time() + math.floor(Gap(AI.CalloutGap) / 2)
    end
    return { ok = true }
end)

PoliceCallback('calloutEnd', function(src, done)
    local p = Patrol[src]
    if not p or not p.callout then return PatrolState(src) end
    if CadClosed then CadClosed(src, p.callout, done == true) end
    if done and os.time() - p.callout.started >= 45 then
        Bump(src, 'callouts')
        Log(src, 'Code 4: ' .. p.callout.title)
    else
        Log(src, 'Callout closed: ' .. p.callout.title)
    end
    p.callout = nil
    p.busy = false
    p.nextAt = os.time() + Gap(AI.CalloutGap)
    return PatrolState(src)
end)

local function PoliceOnDuty()
    local n = 0
    for _, pl in ipairs(GetPlayers()) do if Duty(tonumber(pl)) then n = n + 1 end end
    return n
end

local offerSeq = 0
local function Offer(src, def, loc, incident, silent)
    local p = NewPatrol(src)
    offerSeq = offerSeq + 1
    loc = loc or (PlaceFor and PlaceFor(src, def.key) or nil)
    p.offer = { id = offerSeq, def = def, expires = os.time() + AI.OfferSeconds, loc = loc, incident = incident }
    if CadOffered then CadOffered(src, p.offer) end
    if silent then return p.offer end
    TriggerClientEvent(EV .. 'aiOffer', src, { id = offerSeq, key = def.key, title = def.title, code = def.code, text = def.text, seconds = AI.OfferSeconds,
        where = loc and loc.label or nil, incident = p.offer.incident, nature = def.nature, prio = def.prio })
    return p.offer
end

CreateThread(function()
    while true do
        Wait(2000)
        local now = os.time()
        local crowded = AI.SkipWhenPlayers > 0 and PoliceOnDuty() >= AI.SkipWhenPlayers
        for src, p in pairs(Patrol) do
            if not Online(src) then
                Patrol[src] = nil
            elseif p.on and not IsPolice(src) then
                p.on, p.offer = false, nil
                TriggerClientEvent(EV .. 'aiPatrolOff', src)
            elseif p.offer and now >= p.offer.expires then
                if CadReleased then CadReleased(p.offer) end
                TriggerClientEvent(EV .. 'aiOfferGone', src, p.offer.id)
                p.offer = nil
                p.nextAt = now + math.floor(Gap(AI.CalloutGap) / 2)
            elseif p.on and not p.busy and not p.stopBusy and not p.paused and not p.offer and now >= p.nextAt and not crowded then
                local def = PickCallout(src)
                if def then Offer(src, def) end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    Patrol[src] = nil
    Rate[src] = nil
    TransportReq[src] = nil
end)

-- Units: tell other officers on patrol what's been requested (so real players can respond too)
PoliceCallback('aiUnit', function(src, kind, street)
    local u = AI.Units[kind]
    if not u then return Fail() end
    if Limited(src, 'unit', 10) then return Fail('Slow down.') end
    street = CleanText(street, 60)
    if kind == 'backup' or kind == 'swat' or kind == 'air' or kind == 'roadblock' or kind == 'spikes' or kind == 'k9' then
        if BackupRequest then BackupRequest(src, u.label, street, kind == 'swat' and 3 or 2) end
    end
    if kind == 'transport' then TransportReq[src] = os.time() end
    if kind == 'crisis' and CrisisReq then CrisisReq[src] = os.time() end
    if kind == 'cps' and CPSReq then CPSReq[src] = os.time() end
    Log(src, u.label .. ' requested')
    return { ok = true }
end)

-- Staff: force a callout to test it - /aicallout <key> (or no key for a random one)
RegisterCommand('aicallout', function(src, args)
    if src ~= 0 and not IsAdmin(src) then return Notify(src, 'Staff only.') end
    if src == 0 then return print('Use this in game.') end
    local def = args[1] and CalloutDef(args[1]) or PickCallout(src)
    if not def then
        local keys = {}
        for _, c in ipairs(AI.Callouts) do keys[#keys + 1] = c.key end
        return Notify(src, 'Callouts: ' .. table.concat(keys, ', '))
    end
    local p = NewPatrol(src)
    p.on = true
    p.busy = false
    p.callout = nil
    Offer(src, def)
end, false)

-- Leaderboard for the patrol computer
PoliceCallback('aiBoard', function(src)
    local list = {}
    for ident, s in pairs(Stats) do
        if type(s) == 'table' and s.name then
            list[#list + 1] = { name = s.name, arrests = s.arrests or 0, citations = s.citations or 0, callouts = s.callouts or 0,
                stops = s.stops or 0, score = (s.arrests or 0) * 5 + (s.callouts or 0) * 3 + (s.citations or 0) * 2 + (s.stops or 0) }
        end
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    while #list > 10 do table.remove(list) end
    return { ok = true, list = list }
end)

-- Shared with server/ai_deep.lua
AIX = {
    Get = Get, Public = Public, Bump = Bump, Log = Log, Limited = Limited, Chance = Chance, Pick = Pick, Range = Range, Clamp = Clamp,
    CleanText = CleanText, Offences = Offences, EnsureRecord = EnsureRecord, Summary = Summary, MakePersona = MakePersona, StatsOf = StatsOf,
    Patrol = Patrol, EntityFromNet = EntityFromNet, Near = Near, PROFILES = PROFILES, PROFILE_OK = PROFILE_OK, NewPid = NewPid,
    Offer = Offer, AcceptCallout = AcceptCallout, CalloutDef = CalloutDef, PickCallout = PickCallout, Gap = Gap,
    MarkStats = function() statsDirty = true end, PatrolState = PatrolState, NewPatrol = NewPatrol, Stats = Stats,
}
