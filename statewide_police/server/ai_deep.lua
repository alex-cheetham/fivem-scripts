-- Statewide PD AI patrol - the deeper stuff: lies, field sobriety tests, K9, hostage negotiation,
-- discarded evidence, investigations, arrest reports and court.
local AI = Config.AI
local X = AIX
local Get, Public, Bump, Log, Limited, Chance, Pick, Clamp, CleanText = X.Get, X.Public, X.Bump, X.Log, X.Limited, X.Chance, X.Pick, X.Clamp, X.CleanText

local function Copy(t) local o = {} for i, v in ipairs(t or {}) do o[i] = v end return o end

function Radio(src, text)
    if src and Online(src) then TriggerClientEvent(EV .. 'aiRadio', src, text) end
end

---------------------------------------------------------------------------
-- Lies
---------------------------------------------------------------------------
function CatchLie(src, p, key, text)
    for _, l in ipairs(p.lies) do if l.key == key then return end end
    p.lies[#p.lies + 1] = { key = key, text = text }
    Stress(p, 10)
    Ev(p, 'Caught lying: ' .. text)
    if src then Bump(src, 'lies') end
end

PoliceCallback('aiConfront', function(src, pid, key)
    local p, err = Get(src, pid, 12.0)
    if not p then return err end
    if Limited(src, 'confront', 20) then return Fail('Slow down.') end
    local lie
    for _, l in ipairs(p.lies) do if l.key == key then lie = l end end
    if not lie then return Fail('You haven\'t caught them out on that.') end
    if lie.confronted then return { ok = true, say = lie.reply, persona = Public(p) } end
    lie.confronted = true
    local out = { ok = true }
    local admit = 0.25 + ((p.rapport or 30) - 30) / 110 + ((p.stress or 0) > 70 and 0.15 or 0) + (#p.confessed > 0 and 0.1 or 0)
    local say
    if Chance(admit) then
        lie.admitted = true
        Rapport(p, 6)
        Stress(p, -6)
        p.confessed[#p.confessed + 1] = 'Admitted lying: ' .. lie.text
        Ev(p, 'Admitted lying when confronted')
        local c = Confess(p)
        say = Line('confront_admit') .. (c and (' ' .. c) or '')
    elseif (p.stress or 0) > 80 and not p.cuffed and Chance(p.flee + 0.15) then
        out.act = 'flee'
        p.fled, p.resisted = true, true
        Ev(p, 'Ran when confronted')
        say = Line('flee')
    elseif Chance(0.5) then
        Stress(p, 8)
        say = Line('confront_angry')
    else
        Stress(p, 5)
        say = Line('confront_deny')
    end
    lie.reply = say
    out.say = say
    out.persona = Public(p)
    return out
end)

---------------------------------------------------------------------------
-- Field sobriety tests
---------------------------------------------------------------------------
local HGN = { 'No smooth pursuit - left eye', 'No smooth pursuit - right eye', 'Distinct nystagmus at max deviation - left', 'Distinct nystagmus at max deviation - right',
    'Onset before 45 degrees - left', 'Onset before 45 degrees - right' }
local WALK = { 'Couldn\'t keep balance during the instructions', 'Started too soon', 'Stopped while walking', 'Missed heel-to-toe',
    'Stepped off the line', 'Raised arms for balance', 'Improper turn', 'Wrong number of steps' }
local LEG = { 'Swayed while balancing', 'Raised arms for balance', 'Hopped', 'Put their foot down' }

local function Impairment(p) return (p.bac or 0) / 0.08 + (next(p.drugs or {}) and 0.9 or 0) end

local function Take(list, n)
    local copy = Copy(list)
    for i = #copy, 2, -1 do local j = math.random(1, i) copy[i], copy[j] = copy[j], copy[i] end
    local out = {}
    for i = 1, math.min(n, #copy) do out[i] = copy[i] end
    return out
end

local function Sfst(src, p, name, test, title, list, failAt, scale)
    local lv = Impairment(p)
    local n
    if lv >= 1 then n = Clamp(math.floor(lv * scale) + math.random(-1, 1), failAt, #list)
    elseif lv >= 0.6 then n = math.random(math.max(0, failAt - 1), failAt)
    else n = math.random(0, math.max(0, failAt - 2)) end
    local fail = n >= failAt
    p.sfst = p.sfst or {}
    p.sfst[test] = fail
    Ev(p, ('%s: %d/%d clues (%s)'):format(title, n, #list, fail and 'failed' or 'passed'))
    return { ok = true, kind = 'sfst', test = test, title = title, name = name, clues = Take(list, n), count = n, max = #list, failAt = failAt,
        fail = fail, persona = Public(p) }
end

SFST = {
    hgn = function(src, p, name) return Sfst(src, p, name, 'hgn', 'Eye test (HGN)', HGN, 4, 3) end,
    walk = function(src, p, name) return Sfst(src, p, name, 'walk', 'Walk and turn', WALK, 2, 2.5) end,
    oneleg = function(src, p, name) return Sfst(src, p, name, 'oneleg', 'One leg stand', LEG, 2, 1.6) end,
}

---------------------------------------------------------------------------
-- K9
---------------------------------------------------------------------------
local DRUG_WORDS = { 'cannabis', 'powder', 'pill', 'meth', 'cocaine', 'wrap', 'bags of', 'crystal' }
local function Druggy(label)
    label = tostring(label):lower()
    for _, w in ipairs(DRUG_WORDS) do if label:find(w, 1, true) then return true end end
    return false
end
local function CarriesDrugs(p)
    for _, it in ipairs(p.items) do if not it.seized and not it.ditched and (it.drug or Druggy(it.label)) then return true end end
    return false
end

PoliceCallback('aiK9', function(src, netId, pid)
    if Limited(src, 'k9', 8) then return Fail('Slow down.') end
    local alert = false
    local people = {}
    local veh = netId and X.EntityFromNet(netId, 'veh')
    if veh then
        if not X.Near(src, veh, 30.0) then return Fail('Too far away.') end
        local plate = tostring(GetVehicleNumberPlateText(veh) or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8)
        local rec = Plates[plate]
        for _, c in ipairs(rec and rec.contraband or {}) do if not c.seized and Druggy(c.label) then alert = true end end
        for _, m in ipairs((Groups[plate] or {}).members or {}) do if Personas[m] then people[#people + 1] = Personas[m] end end
    end
    if pid then
        local p = Get(src, pid, 30.0)
        if p then people[#people + 1] = p end
    end
    for _, p in ipairs(people) do if CarriesDrugs(p) then alert = true end end
    for _, p in ipairs(people) do
        p.k9 = alert
        Ev(p, 'K9 sniff: ' .. (alert and 'the dog indicated' or 'no indication'))
    end
    Log(src, 'K9 sniff: ' .. (alert and 'positive indication' or 'nothing'))
    return { ok = true, alert = alert }
end)

---------------------------------------------------------------------------
-- Hostage negotiation
---------------------------------------------------------------------------
local NEGO = {
    listen  = { min = 5, max = 14, stress = -6 },
    calm    = { min = 3, max = 12, stress = -10 },
    promise = { min = 8, max = 18, stress = -4, needs = 40 },
    family  = { min = -5, max = 20, stress = -2 },
    time    = { min = 2, max = 7, stress = -4 },
    demand  = { min = -16, max = 12, stress = 12 },
    clinician = { min = 14, max = 28, stress = -12 },
}

PoliceCallback('aiNego', function(src, pid, opt)
    local p, err = Get(src, pid, 45.0)
    if not p then return err end
    if not p.hostage and not p.crisis then return Fail('They aren\'t holding anyone.') end
    local o = NEGO[opt]
    if opt == 'clinician' and not p.clinician then return Fail('The crisis team isn\'t here yet.') end
    if not o then return Fail() end
    if Limited(src, 'nego', 24) then return Fail('Slow down.') end
    p.negoUsed = p.negoUsed or {}
    p.negoUsed[opt] = (p.negoUsed[opt] or 0) + 1
    local d = math.random(o.min, o.max)
    if o.needs and (p.nego or 0) < o.needs then d = -math.random(3, 8) end
    if p.negoUsed[opt] > 2 then d = math.floor(d / 2) - 3 end
    p.nego = Clamp((p.nego or 30) + d, 0, 100)
    Stress(p, o.stress + (d < 0 and 6 or 0))
    local pre = p.crisis and 'crisis_' or p.barricade and 'barricade_' or 'nego_'
    local res = { ok = true, delta = d, say = Line(d >= 0 and pre .. 'good' or pre .. 'bad') }
    if p.crisis then
        if Emote then Emote(p, d >= 0 and 'reassure' or 'shout') end
        if p.nego >= 100 then
            p.crisis, p.voluntary, p.surrendered = false, true, true
            res.outcome, res.say = 'help', Line('crisis_agree')
            Ev(p, 'Agreed to get help after de-escalation')
            Log(src, 'Crisis de-escalated')
        elseif p.nego <= 0 or (p.stress or 0) >= 98 then
            p.crisis = false
            p.fled = true
            res.outcome = (p.melee and Chance(0.5)) and 'fight' or 'flee'
            res.say = Line('crisis_snap')
            Ev(p, 'De-escalation failed')
        end
        res.persona = Public(p)
        return res
    end
    if p.nego >= 100 then
        p.hostage, p.surrendered = false, true
        res.outcome, res.say = 'release', Line(pre .. 'release')
        Ev(p, p.barricade and 'Came out and surrendered after negotiation' or 'Released the hostage and surrendered after negotiation')
        Log(src, p.barricade and 'Barricaded subject surrendered - negotiation successful' or 'Hostage released - negotiation successful')
    elseif p.nego <= 0 or (p.stress or 0) >= 98 then
        p.hostage = false
        p.fled, p.resisted = true, true
        res.outcome = Chance(0.5) and 'flee' or 'fight'
        res.say = Line(pre .. 'snap')
        Ev(p, 'Negotiations broke down')
    end
    res.persona = Public(p)
    return res
end)

---------------------------------------------------------------------------
-- Things suspects throw away while running
---------------------------------------------------------------------------
local Ditched, ditchSeq = {}, 0

PoliceCallback('aiDitch', function(src, pid, x, y, z)
    local p, ped = Get(src, pid, 500.0)
    if not p then return ped end
    if p.ditchedOnce or p.owner ~= src or not p.fled then return Fail() end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return Fail() end
    if #(GetEntityCoords(ped) - vector3(x, y, z)) > 25.0 then return Fail() end
    local pick
    for _, it in ipairs(p.items) do
        if not it.legal and not it.seized and not it.ditched then
            if not pick or (it.drug or it.weapon) then pick = it end
        end
    end
    if not pick then return Fail() end
    p.ditchedOnce = true
    ditchSeq = ditchSeq + 1
    pick.ditched = ditchSeq
    Ditched[ditchSeq] = { pid = p.pid, item = pick, label = pick.label, pos = vector3(x, y, z), t = os.time(), owner = src }
    Ev(p, 'Threw something away while running')
    return { ok = true, id = ditchSeq, label = pick.label, weapon = pick.weapon ~= nil }
end)

PoliceCallback('aiPickup', function(src, id)
    if Limited(src, 'pickup', 10) then return Fail('Slow down.') end
    local d = Ditched[tonumber(id) or 0]
    if not d then return Fail('Someone already bagged that.') end
    if #(Pos(src) - d.pos) > 8.0 then return Fail('Get closer to it.') end
    Ditched[tonumber(id)] = nil
    d.item.seized = true
    local p = Personas[d.pid]
    local from = 'Discarded by a fleeing suspect'
    if p then
        p.illegal = math.max(0, (p.illegal or 1) - 1)
        p.seizedList = p.seizedList or {}
        p.seizedList[#p.seizedList + 1] = d.label .. ' (discarded)'
        if d.item.weapon and (d.item.weapon == p.weapon) then p.weapon = nil end
        Ev(p, 'Discarded item recovered: ' .. d.label)
        from = from .. (p.idChecked and (' (' .. p.name .. ')') or '')
    end
    AddToLocker(src, { type = 'item', label = d.label .. ' (discarded)', from = from })
    if d.owner == src then Bump(src, 'seized') end
    return { ok = true, msg = d.label .. ' bagged as evidence.' }
end)

CreateThread(function()
    while true do
        Wait(60000)
        for id, d in pairs(Ditched) do if os.time() - d.t > 1800 then Ditched[id] = nil end end
    end
end)

---------------------------------------------------------------------------
-- Investigations (callouts with clues, statements, a BOLO and warrants)
---------------------------------------------------------------------------
Cases = {}
local caseSeq = 0
local COLOURS = { 'black', 'white', 'silver', 'grey', 'red', 'blue', 'dark green', 'brown', 'beige', 'gold', 'orange', 'yellow' }
local COLOUR_IDX = { black = 0, white = 111, silver = 4, grey = 6, red = 27, blue = 64, ['dark green'] = 49, brown = 96, beige = 99, gold = 37, orange = 38, yellow = 88 }

local function Gendered(gender)
    local list = {}
    for _, m in ipairs(AI.Peds) do
        if (gender == 'f' and m:sub(1, 4) == 'a_f_') or (gender == 'm' and m:sub(1, 4) == 'a_m_') then list[#list + 1] = m end
    end
    return #list > 0 and Pick(list) or Pick(AI.Peds)
end

local function AgeBand(age)
    if age < 25 then return 'early twenties' elseif age < 35 then return 'late twenties to thirties'
    elseif age < 50 then return 'forties' elseif age < 62 then return 'fifties' else return 'sixties or older' end
end

local function CaseView(c, full)
    local known = {}
    for _, k in ipairs({ 'gender', 'age', 'look', 'vehicle', 'colour', 'plate', 'name' }) do
        if c.known[k] then known[#known + 1] = { k = k, text = c.known[k] } end
    end
    local statements, clues = {}, {}
    for _, s in pairs(c.statements) do statements[#statements + 1] = s end
    for i, cl in ipairs(c.clues) do clues[#clues + 1] = { index = i, label = cl.label, found = cl.found, text = cl.found and cl.text or nil } end
    return { id = c.id, key = c.key, title = c.title, created = c.createdAt, street = c.street, known = known, statements = statements, clues = clues,
        bolo = c.bolo, solved = c.solved, warrant = c.warrant and (c.warrant.status or 'pending') or nil,
        canBolo = not c.bolo and #known >= 2, canWarrant = c.known.name ~= nil and not c.warrant and not c.solved }
end

local function Reveal(c, keys, n)
    local out = {}
    for _, k in ipairs(keys) do
        if #out >= n then break end
        if c.desc[k] and not c.known[k] then c.known[k] = c.desc[k] out[#out + 1] = c.desc[k] end
    end
    return out
end

PoliceCallback('caseOpen', function(src, key, street)
    local def = AI.Cases and AI.Cases[key]
    if not def then return Fail() end
    local pt = X.Patrol[src]
    if not pt or not pt.callout or pt.callout.key ~= key then return Fail('You\'re not on that callout.') end
    if pt.callout.caseId then return Fail('Already open.') end
    local gender = Chance(0.75) and 'm' or 'f'
    local s = X.MakePersona(def.profile, gender)
    s.planned, s.owner, s.role = true, src, 'suspect'
    s.model = Gendered(gender)
    Personas[s.pid] = s
    caseSeq = caseSeq + 1
    local id = ('K%d'):format(1000 + caseSeq)
    s.caseId = id
    local c = {
        id = id, key = key, src = src, title = def.title, createdAt = os.date('%H:%M'), created = os.time(), street = CleanText(street, 80),
        suspect = s.pid, known = {}, statements = {}, clues = {}, solved = false, mode = def.mode or 'foot',
        desc = {
            gender = gender == 'f' and 'Female' or 'Male',
            age = 'Age: ' .. AgeBand(s.age),
            look = 'Wearing: ' .. ((AI.Looks or {})[s.model] or 'casual clothes'),
        },
    }
    if c.mode == 'vehicle' then
        local colour = Pick(COLOURS)
        c.vehModel = Pick(AI.Cars)
        c.colour = COLOUR_IDX[colour] or 0
        c.plate = ('%s%d%s'):format(Pick({ 'SW', 'BC', 'LS', 'SA' }), math.random(10, 99), Pick({ 'KPR', 'TXD', 'LMN', 'RZQ', 'HJB', 'WOP' }))
        c.desc.vehicle = 'Vehicle: ' .. c.vehModel:upper()
        c.desc.colour = 'Colour: ' .. colour
        c.desc.plate = 'Partial plate: ' .. c.plate:sub(1, 4) .. '...'
        if Plates then
            Plates[c.plate] = { owner = def.stolen and (Pick(Config.FirstNames) .. ' ' .. Pick(Config.LastNames)) or s.name, reg = 'Valid',
                insurance = 'Insured', stolen = def.stolen == true, ownerWarrant = false, impounds = 0, contraband = {} }
            Dirty.plates = true
        end
        s.plate = c.plate
        s.vehicle = def.stolen and 'stolen' or 'own'
    end
    for _, cl in ipairs(def.clues or {}) do
        c.clues[#c.clues + 1] = { model = cl.model, label = cl.label, reveals = cl.reveals, text = cl.text, found = false }
    end
    Cases[id] = c
    pt.callout.caseId = id
    Log(src, 'Case opened: ' .. id .. ' ' .. def.title)
    local clues = {}
    for i, cl in ipairs(c.clues) do clues[i] = { index = i, model = cl.model, label = cl.label } end
    return { ok = true, id = id, clues = clues, view = CaseView(c) }
end)

local function MyCase(src, id)
    local c = Cases[tostring(id or '')]
    if not c or c.src ~= src then return nil, Fail('That case isn\'t yours.') end
    return c
end

PoliceCallback('caseStatement', function(src, id, pid)
    local c, err = MyCase(src, id)
    if not c then return err end
    local p, e2 = Get(src, pid, 12.0)
    if not p then return e2 end
    if p.role ~= 'victim' and p.role ~= 'witness' then return Fail('They don\'t know anything about it.') end
    if c.statements[p.pid] then return { ok = true, text = c.statements[p.pid].text, view = CaseView(c) } end
    local got = Reveal(c, p.role == 'victim' and { 'gender', 'age', 'vehicle', 'look', 'colour' } or { 'look', 'colour', 'gender', 'plate', 'age' }, 2)
    local text = Line('statement_' .. c.key) .. (#got > 0 and (' ' .. Line('statement_desc', table.concat(got, ', ')):gsub('Age: ', ''):gsub('Wearing: ', 'wearing '):gsub('Vehicle: ', 'in a '):gsub('Colour: ', ''):gsub('Partial plate: ', 'plate started ')) or '')
    c.statements[p.pid] = { name = p.idChecked and p.name or (p.role == 'victim' and 'Victim' or 'Witness'), role = p.role, text = text }
    Log(src, 'Statement taken (' .. c.id .. ')')
    return { ok = true, text = text, view = CaseView(c) }
end)

PoliceCallback('caseClue', function(src, id, index)
    local c, err = MyCase(src, id)
    if not c then return err end
    local cl = c.clues[tonumber(index) or 0]
    if not cl then return Fail() end
    if cl.found then return { ok = true, text = cl.text, view = CaseView(c) } end
    if Limited(src, 'clue', 20) then return Fail('Slow down.') end
    cl.found = true
    local s = Personas[c.suspect]
    local text = cl.text or cl.label
    if cl.reveals == 'name' and s then
        c.known.name = 'Name: ' .. s.name
        text = text:gsub('%%s', s.name)
    elseif cl.reveals == 'plate' and c.desc.plate then
        c.known.plate = 'Plate: ' .. (c.plate or '')
        c.known.vehicle = c.desc.vehicle
        text = text:gsub('%%s', c.plate or '')
    elseif cl.reveals and c.desc[cl.reveals] then
        c.known[cl.reveals] = c.desc[cl.reveals]
        text = text:gsub('%%s', c.desc[cl.reveals])
    end
    text = text:gsub('Age: ', ''):gsub('Wearing: ', 'wearing '):gsub('Vehicle: ', ''):gsub('Colour: ', ''):gsub('Partial plate: ', '')
    cl.text = text
    c.cluesFound = (c.cluesFound or 0) + 1
    AddToLocker(src, { type = 'item', label = cl.label .. ' (case ' .. c.id .. ')', from = 'Crime scene' })
    Log(src, 'Evidence found (' .. c.id .. '): ' .. cl.label)
    return { ok = true, text = text, view = CaseView(c) }
end)

PoliceCallback('caseBolo', function(src, id)
    local c, err = MyCase(src, id)
    if not c then return err end
    local v = CaseView(c)
    if c.bolo then return Fail('The BOLO is already out.') end
    if #v.known < 2 then return Fail('You need more of a description first (statements or evidence).') end
    local s = Personas[c.suspect]
    if not s then return Fail('The suspect has left the area.') end
    if not s.planned then
        local ped = s.netId and X.EntityFromNet(s.netId, 'ped')
        if ped then return Fail('You\'ve already found them.') end
        s.planned, s.netId = true, nil
    end
    c.bolo = true
    Log(src, 'BOLO issued (' .. c.id .. ')')
    return { ok = true, pid = s.pid, model = s.model, gender = s.gender, mode = c.mode, vehModel = c.vehModel, colour = c.colour, plate = c.plate,
        view = CaseView(c) }
end)

PoliceCallback('caseWarrant', function(src, id)
    local c, err = MyCase(src, id)
    if not c then return err end
    if not c.known.name then return Fail('You don\'t know who they are yet.') end
    if c.warrant then return Fail('Already applied.') end
    c.warrant = { at = os.time() + (AI.WarrantSeconds or 45), status = 'pending' }
    Log(src, 'Warrant applied for (' .. c.id .. ')')
    return { ok = true, msg = 'Warrant application sent to the judge.', view = CaseView(c) }
end)

PoliceCallback('caseServe', function(src, id)
    local c, err = MyCase(src, id)
    if not c then return err end
    if not c.warrant or c.warrant.status ~= 'approved' then return Fail('You need an approved warrant.') end
    if c.served or c.solved then return Fail('Already served.') end
    local s = Personas[c.suspect]
    if not s then return Fail('The suspect can\'t be found.') end
    if not s.planned then
        local ped = s.netId and X.EntityFromNet(s.netId, 'ped')
        if ped then return Fail('You\'ve already found them - arrest them.') end
        -- lost them earlier: they've gone home
        s.planned, s.netId = true, nil
    end
    c.served = true
    local loc = PlaceFor and PlaceFor(src, 'warrant') or nil
    if PlaceTaken then PlaceTaken(src, loc) end
    return { ok = true, pid = s.pid, model = s.model, gender = s.gender, title = c.title, loc = loc }
end)

-- The client couldn't place the suspect: let the officer try again
PoliceCallback('caseRetry', function(src, id, what)
    local c, err = MyCase(src, id)
    if not c then return err end
    if what == 'bolo' then c.bolo = false elseif what == 'serve' then c.served = false end
    return { ok = true }
end)

PoliceCallback('caseList', function(src)
    local out = {}
    for _, c in pairs(Cases) do if c.src == src then out[#out + 1] = CaseView(c) end end
    table.sort(out, function(a, b) return a.id > b.id end)
    return { ok = true, cases = out }
end)

-- Shown on an ID check
function CaseFlags(p, s)
    s.flags = s.flags and Copy(s.flags) or {}
    for _, c in pairs(Cases) do
        if not c.solved and (c.suspect == p.pid) then
            p.matches = true
            table.insert(s.flags, 1, ('MATCHES THE BOLO FOR CASE %s (%s)'):format(c.id, c.title))
        end
    end
end

local function CaseSolved(src, p)
    local c = p.caseId and Cases[p.caseId]
    if not c or c.solved then return end
    c.solved = true
    Bump(src, 'cases')
    Log(src, 'Case solved: ' .. c.id)
    Radio(src, ('Dispatch: case %s (%s) marked solved. Good work.'):format(c.id, c.title))
end

---------------------------------------------------------------------------
-- Arrest reports and court
---------------------------------------------------------------------------
local Reports = {}

local function Snapshot(p)
    local sfstFails = 0
    for _, v in pairs(p.sfst or {}) do if v then sfstFails = sfstFails + 1 end end
    local c = p.caseId and Cases[p.caseId]
    local statements = 0
    if c then for _ in pairs(c.statements) do statements = statements + 1 end end
    return {
        lies = #p.lies, lieList = (function() local l = {} for _, x in ipairs(p.lies) do l[#l + 1] = x.text end return l end)(),
        confessed = Copy(p.confessed), breath = p.results and p.results.breath, drug = p.results and p.results.drug,
        gsr = p.results and p.results.gsr, sfstFails = sfstFails, seized = Copy(p.seizedList), fled = p.fled == true,
        fought = p.fought == true, warrant = p.warrant ~= nil, licence = p.licence, stolen = p.stolenCar == true or p.vehicle == 'stolen',
        k9 = p.k9 == true, profile = p.profile, caseClues = c and (c.cluesFound or 0) or 0, statements = statements, matched = p.matches == true,
        violations = Violations and Violations(p) or {}, supervisionKind = p.supervision and p.supervision.kind or nil, filmed = p.filmed == true,
    }
end

local function Has(list, words)
    for _, s in ipairs(list or {}) do
        local l = s:lower()
        for _, w in ipairs(words) do if l:find(w, 1, true) then return true end end
    end
    return false
end

local function Support(label, ev)
    local l = label:lower()
    -- Phase 3 charges
    if l:find('escape from custody') then
        return ev.warrant and 0.95 or 0.3, ev.warrant and 'escape warrant on file' or 'no escape warrant on file'
    elseif l:find('manufactur') then
        if Has(ev.seized, { 'meth', 'pseudoephedrine', 'glassware' }) then return 0.9, 'lab equipment and product seized' end
        return 0.2, 'nothing from the lab seized'
    elseif l:find('stolen cards') or l:find('fraud') then
        if Has(ev.seized, { 'credit card', 'skimmer', 'fake driving' }) then return 0.88, 'cards / skimmer seized' end
        if ev.statements > 0 then return 0.55, 'clerk statement' end
        return 0.2, 'no cards recovered'
    elseif l:find('arson') then
        if Has(ev.seized, { 'petrol', 'lighter', 'rags' }) then return 0.8, 'accelerant / lighter seized' end
        if ev.statements > 0 then return 0.6, 'witness statement' end
        return 0.2, 'no accelerant, no witness'
    elseif l:find('poaching') then
        if Has(ev.seized, { 'firearm', 'carcass', 'spotlight' }) then return 0.85, 'rifle / carcass seized' end
        return 0.3, 'nothing seized'
    elseif l:find('shooting from a vehicle') or l:find('carjacking') then
        if Has(ev.seized, { 'firearm', 'pistol', 'weapon', 'car keys' }) then return 0.85, 'weapon / victim\'s property recovered' end
        if ev.gsr then return 0.6, 'positive GSR' end
        if ev.statements > 0 then return 0.55, 'victim / witness statements' end
        return 0.25, 'no weapon or property recovered'
    elseif l:find('racing') or l:find('wrong way') then
        if ev.fled then return 0.85, 'driving witnessed, fled police' end
        return 0.7, 'officer observation'
    elseif l:find('log book') or l:find('unsafe load') then
        if Has(ev.seized, { 'log book' }) then return 0.9, 'log book seized' end
        return 0.6, 'officer inspection'
    elseif l:find('restraining order') then
        if ev.statements > 0 then return 0.75, 'victim statement' end
        return 0.45, 'officer observation'
    end
    if l:find('influence') then
        local s = 0.12
        local why = {}
        if ev.breath and ev.breath >= Config.DrinkLimit then s = s + 0.55 why[#why + 1] = ('breath %.3f%%'):format(ev.breath) end
        if ev.drug then s = s + 0.45 why[#why + 1] = 'positive drug swab' end
        if ev.sfstFails > 0 then s = s + ev.sfstFails * 0.12 why[#why + 1] = ev.sfstFails .. ' failed field test(s)' end
        return s, #why > 0 and table.concat(why, ', ') or 'no breath, drug or field tests'
    elseif l:find('intent to supply') then
        if Has(ev.seized, { 'bags of', 'wraps', '40 pills', 'scales' }) then return 0.88, 'supply quantity and scales seized' end
        return 0.15, 'no supply quantity seized'
    elseif l:find('possession') then
        if Has(ev.seized, { 'cannabis', 'powder', 'pill', 'meth', 'cocaine', 'wrap', 'crystal' }) then return 0.85, 'drugs seized' end
        if ev.k9 then return 0.35, 'K9 indication only' end
        return 0.1, 'no drugs seized'
    elseif l:find('firearm') or l:find('brandish') or l:find('deadly') or l:find('discharg') or l:find('armed') then
        if Has(ev.seized, { 'firearm', 'pistol', 'weapon', 'knife' }) then return 0.85, 'weapon seized' end
        if ev.gsr then return 0.55, 'positive GSR' end
        return 0.15, 'no weapon recovered'
    elseif l:find('resist') or l:find('evading') or l:find('failure to stop') then
        if ev.fled or ev.fought then return 0.9, 'ran from / fought officers' end
        return 0.1, 'they complied'
    elseif l:find('warrant') then
        return ev.warrant and 0.97 or 0.02, ev.warrant and 'warrant on file' or 'no warrant on file'
    elseif l:find('licence') then
        return (ev.licence and ev.licence ~= 'Valid') and 0.95 or 0.05, 'licence ' .. tostring(ev.licence)
    elseif l:find('grand theft') then
        return ev.stolen and 0.9 or 0.1, ev.stolen and 'vehicle reported stolen' or 'vehicle not reported stolen'
    elseif l:find('theft') or l:find('burglary') or l:find('robbery') then
        if Has(ev.seized, { 'stolen', 'unpaid', 'merchandise', 'jewellery', 'cash' }) then return 0.85, 'stolen property recovered' end
        if ev.caseClues > 0 or ev.matched then return 0.6, 'scene evidence / matched description' end
        return 0.15, 'no stolen property'
    elseif l:find('assault') or l:find('murder') or l:find('kidnap') then
        if ev.fought then return 0.75, 'assaulted officers' end
        if ev.statements > 0 then return 0.65, 'victim / witness statements' end
        return 0.2, 'no statements'
    elseif l:find('identify') then
        return Has(ev.lieList, { 'false name' }) and 0.9 or 0.3, 'false details given'
    elseif l:find('speed') or l:find('reckless') or l:find('red light') or l:find('hit and run') then
        if ev.profile == 'reckless' or ev.fled then return 0.8, 'driving witnessed' end
        return 0.5, 'officer observation'
    end
    return 0.6, 'officer evidence'
end

local function Draft(src, p, labels, case)
    local lines = {}
    lines[#lines + 1] = ('ARREST REPORT %s - %s'):format(case, os.date('%d/%m/%Y %H:%M'))
    lines[#lines + 1] = ('Officer: %s'):format(OfficerLabel(src))
    lines[#lines + 1] = ('Arrested: %s, DOB %s'):format(p.name, p.dob)
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Timeline:'
    for _, e in ipairs(p.events or {}) do lines[#lines + 1] = ' - ' .. e end
    if #p.lies > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'False statements:'
        for _, l in ipairs(p.lies) do lines[#lines + 1] = ' - ' .. l.text end
    end
    if #p.confessed > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Admissions:'
        for _, c in ipairs(p.confessed) do lines[#lines + 1] = ' - ' .. c end
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Charges: ' .. table.concat(labels, ', ')
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Narrative: '
    return table.concat(lines, '\n')
end

function OnArrest(src, p, case, labels, ident)
    p.fought = p.fought or false
    Reports[case] = { case = case, src = src, officer = Ident(src), ident = ident, name = p.name, charges = labels, created = os.time(),
        ev = Snapshot(p), text = Draft(src, p, labels, case), submitted = false, due = os.time() + (AI.ReportWindow or 900) }
    CaseSolved(src, p)
end

local function ReportView(r)
    return { case = r.case, name = r.name, charges = r.charges, submitted = r.submitted, text = r.text, court = r.court,
        created = os.date('%H:%M', r.created), due = math.max(0, r.due - os.time()), evidence = (function()
            local e, ev = {}, r.ev
            if ev.breath then e[#e + 1] = ('Breath %.3f%%'):format(ev.breath) end
            if ev.drug then e[#e + 1] = 'Positive drug swab' end
            if ev.sfstFails > 0 then e[#e + 1] = ev.sfstFails .. ' failed field sobriety test(s)' end
            if ev.gsr then e[#e + 1] = 'Positive GSR' end
            for _, s in ipairs(ev.seized) do e[#e + 1] = 'Seized: ' .. s end
            if ev.k9 then e[#e + 1] = 'K9 indication' end
            if ev.lies > 0 then e[#e + 1] = ev.lies .. ' false statement(s) recorded' end
            if #ev.confessed > 0 then e[#e + 1] = #ev.confessed .. ' admission(s)' end
            if ev.fled then e[#e + 1] = 'Fled from police' end
            if ev.fought then e[#e + 1] = 'Fought police' end
            if ev.statements > 0 then e[#e + 1] = ev.statements .. ' witness statement(s)' end
            if ev.caseClues > 0 then e[#e + 1] = ev.caseClues .. ' piece(s) of scene evidence' end
            if ev.warrant then e[#e + 1] = 'Active warrant' end
            for _, v in ipairs(ev.violations or {}) do e[#e + 1] = 'Violation - ' .. v end
            if ev.filmed then e[#e + 1] = 'Bystander video of the arrest' end
            return e
        end)() }
end

PoliceCallback('aiReports', function(src)
    local me = Ident(src)
    local out = {}
    for _, r in pairs(Reports) do if r.officer == me then out[#out + 1] = ReportView(r) end end
    table.sort(out, function(a, b) return a.case > b.case end)
    while #out > 30 do table.remove(out) end
    return { ok = true, reports = out, courtMinutes = AI.CourtMinutes or 3 }
end)

PoliceCallback('aiReportSubmit', function(src, case, text)
    local r = Reports[tostring(case or '')]
    if not r or r.officer ~= Ident(src) then return Fail('That isn\'t your report.') end
    if r.submitted then return Fail('Already submitted.') end
    text = CleanText(text, 4000)
    if #text < 60 then return Fail('Write a bit more in the report.') end
    r.text, r.submitted = text, true
    r.due = os.time() + (AI.CourtMinutes or 3) * 60
    local rec = Records[r.ident]
    for _, a in ipairs(rec and rec.arrests or {}) do if a.id == r.case then a.report = text end end
    Dirty.records = true
    Bump(src, 'reports')
    Log(src, 'Arrest report submitted: ' .. r.case)
    return { ok = true, msg = 'Report filed. The case goes to court in about ' .. (AI.CourtMinutes or 3) .. ' minutes.', report = ReportView(r) }
end)

local function Court(r)
    local verdicts, guilty, dismissed = {}, 0, 0
    local bonus = (r.submitted and 0.1 or -0.1) + (r.submitted and #r.text > 400 and 0.05 or 0)
        + (#r.ev.confessed > 0 and 0.12 or 0) + math.min(0.12, r.ev.lies * 0.04)
    for _, label in ipairs(r.charges) do
        local s, why = Support(label, r.ev)
        local chance = Clamp(s + bonus, 0.03, 0.97)
        local g = math.random() < chance
        verdicts[#verdicts + 1] = { charge = label, guilty = g, why = why }
        if g then guilty = guilty + 1 else dismissed = dismissed + 1 end
    end
    r.court = { date = Stamp(), verdicts = verdicts, guilty = guilty, dismissed = dismissed }
    if CourtExtra then
        local ok, e = pcall(CourtExtra, r)
        if not ok then print('[statewide_police] court extra error: ' .. tostring(e)) end
    end
    local rec = Records[r.ident]
    for _, a in ipairs(rec and rec.arrests or {}) do if a.id == r.case then a.court = r.court end end
    Dirty.records = true
    local src = SrcFromIdent(r.officer)
    if src then
        if guilty > 0 then Bump(src, 'convictions', guilty) end
        if dismissed > 0 then Bump(src, 'dismissed', dismissed) end
        TriggerClientEvent(EV .. 'aiCourt', src, { case = r.case, name = r.name, guilty = guilty, dismissed = dismissed, verdicts = verdicts,
            bail = r.court.bail, violation = r.court.violation })
    end
end

CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for _, r in pairs(Reports) do
            if not r.court and now >= r.due then
                local ok, e = pcall(Court, r)
                if not ok then print('[statewide_police] court error: ' .. tostring(e)) r.court = { verdicts = {}, guilty = 0, dismissed = 0 } end
            end
        end
        -- warrants
        for _, c in pairs(Cases) do
            if c.warrant and c.warrant.status == 'pending' and now >= c.warrant.at then
                local strength = (c.cluesFound or 0)
                for _ in pairs(c.statements) do strength = strength + 1 end
                if strength >= 2 then
                    c.warrant.status = 'approved'
                    local s = Personas[c.suspect]
                    if s then
                        s.warrant = s.warrant or c.title
                        local _, rec = X.EnsureRecord(s)
                        table.insert(rec.warrants, 1, { id = NewCaseId('W'), date = Stamp(), officer = 'County Court', reason = c.title .. ' (case ' .. c.id .. ')', active = true })
                        Dirty.records = true
                    end
                else
                    c.warrant.status = 'denied'
                end
                if Online(c.src) then TriggerClientEvent(EV .. 'aiWarrant', c.src, { id = c.id, title = c.title, status = c.warrant.status }) end
            end
        end
        -- forget old finished things
        for k, r in pairs(Reports) do if r.court and now - r.created > 7200 then Reports[k] = nil end end
        for k, c in pairs(Cases) do if now - c.created > 7200 then Cases[k] = nil if Personas[c.suspect] and Personas[c.suspect].planned then Personas[c.suspect] = nil end end end
    end
end)
