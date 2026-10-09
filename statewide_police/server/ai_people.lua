-- Statewide PD: the people side - memory between encounters, emotions, body language, reaching,
-- language barriers, mental health crises, children and interfering passengers, bystanders filming,
-- bail / probation / parole, and complaints & Internal Affairs.
local AI = Config.AI
local X = AIX
local PC = AI.People or {}
local Get, Public, Bump, Log, Limited, Chance, Pick, Clamp, CleanText = X.Get, X.Public, X.Bump, X.Log, X.Limited, X.Chance, X.Pick, X.Clamp, X.CleanText

local function Pct(v) return math.floor(Clamp(v or 0, 0, 100)) end

---------------------------------------------------------------------------
-- Memory: people you've dealt with before come back (repeat offenders recognise you)
---------------------------------------------------------------------------
local Known = LoadJson('data/known.json', {})     -- [recordIdent] = { name, first, last, dob, age, gender, enc = { {by, byName, what, date} }, seen, supervision }
local knownDirty = false

local function KnownSave()
    if not knownDirty then return end
    -- keep it small: forget the least recently seen
    local list = {}
    for k, v in pairs(Known) do list[#list + 1] = { k = k, seen = tonumber(v.seen) or 0 } end
    if #list > (PC.MaxKnown or 400) then
        table.sort(list, function(a, b) return a.seen < b.seen end)
        for i = 1, #list - (PC.MaxKnown or 400) do Known[list[i].k] = nil end
    end
    SaveJson('data/known.json', Known)
    knownDirty = false
end

local function RecordIdent(p) return p.recordIdent or ('ai:' .. p.pid) end

-- Something happened between an officer and this person: remember it
function Encounter(src, p, what)
    if not p or not p.name then return end
    local id = RecordIdent(p)
    local k = Known[id]
    if not k then
        k = { name = p.name, first = p.first, last = p.last, dob = p.dob, age = p.age, gender = p.gender, enc = {} }
        Known[id] = k
    end
    k.enc = k.enc or {}
    table.insert(k.enc, 1, { by = Ident(src), byName = Name(src), what = what, date = os.date('%d/%m %H:%M') })
    while #k.enc > 8 do table.remove(k.enc) end
    k.seen = os.time()
    if p.supervision then k.supervision = p.supervision end
    knownDirty = true
    -- conduct checks when a stop ends
    if what == 'released' or what == 'warning' or what == 'citation' then
        if RudeCheck then RudeCheck(src, p) end
    end
end

local function ActiveIdent(id)
    for _, o in pairs(Personas) do if RecordIdent(o) == id and not o.goneAt then return true end end
    return false
end

-- A new person might be someone already known (same gender, not around right now)
local function MaybeReturning(src, p)
    if p.vehicle == 'own' or p.planned or p.recordIdent then return end
    if p.profile == 'victim' or p.profile == 'witness' or p.profile == 'missing' or p.crisis then return end
    if not Chance(PC.RepeatChance or 0.12) then return end
    local me = Ident(src)
    local mine, any = {}, {}
    for id, k in pairs(Known) do
        if k.gender == p.gender and Records[id] and os.time() - (tonumber(k.seen) or 0) > 600 and not ActiveIdent(id) then
            local metMe = false
            for _, e in ipairs(k.enc or {}) do if e.by == me then metMe = true end end
            if metMe then mine[#mine + 1] = id else any[#any + 1] = id end
        end
    end
    local pool = (#mine > 0 and Chance(0.65)) and mine or (#any > 0 and any or mine)
    if #pool == 0 then return end
    local id = Pick(pool)
    local k = Known[id]
    p.recordIdent = id
    p.first, p.last, p.name, p.dob, p.age = k.first or p.first, k.last or p.last, k.name, k.dob or p.dob, k.age or p.age
    p.priors = true
    p.returning = true
    local rec = Records[id]
    if rec and not p.warrant then
        for _, w in ipairs(rec.warrants or {}) do if w.active then p.warrant = w.reason break end end
    end
    if p.warrant and rec then
        rec.warrants = rec.warrants or {}
        table.insert(rec.warrants, 1, { id = 'W' .. math.random(1000, 9999), date = os.date('%d/%m/%Y %H:%M'), officer = 'County Court', reason = p.warrant, active = true })
        Dirty.records = true
    end
    if k.supervision then p.supervision = k.supervision end
    -- how they feel about seeing you again
    local arrestsByYou, stopsByYou = 0, 0
    for _, e in ipairs(k.enc or {}) do
        if e.by == me then
            stopsByYou = stopsByYou + 1
            if e.what == 'arrest' then arrestsByYou = arrestsByYou + 1 end
        end
    end
    if stopsByYou > 0 then
        p.knowsYou = { stops = stopsByYou, arrests = arrestsByYou, last = (k.enc[1] or {}).what }
        p.anger = Clamp((p.anger or 0) + arrestsByYou * 20 + 10, 0, 100)
        p.stress = Clamp((p.stress or 0) + 10, 0, 100)
        if arrestsByYou > 0 then p.flee = Clamp((p.flee or 0) + 0.12, 0, 0.9) p.mood = 'hostile' end
    end
end

local function HistoryText(p)
    local k = Known[RecordIdent(p)]
    if not k or not k.enc or #k.enc == 0 then return nil end
    local stops, arrests, cites = 0, 0, 0
    for _, e in ipairs(k.enc) do
        stops = stops + 1
        if e.what == 'arrest' then arrests = arrests + 1 elseif e.what == 'citation' then cites = cites + 1 end
    end
    return ('Dealt with %d time(s) before: %d arrest(s), %d citation(s). Last: %s by %s'):format(stops, arrests, cites, k.enc[1].what, k.enc[1].byName or 'an officer')
end

---------------------------------------------------------------------------
-- Probation, parole and bail
---------------------------------------------------------------------------
local CONDITIONS = {
    alcohol = 'No alcohol', drugs = 'No drugs', weapons = 'No weapons', driving = 'Must not drive', contact = 'No contact with the victim',
}

local function MakeSupervision(p)
    if not p.priors or p.profile == 'victim' or p.profile == 'witness' or p.profile == 'missing' then return end
    local r = math.random()
    local kind
    if r < (PC.Parole or 0.07) then kind = 'Parole'
    elseif r < (PC.Parole or 0.07) + (PC.Probation or 0.14) then kind = 'Probation'
    elseif r < (PC.Parole or 0.07) + (PC.Probation or 0.14) + (PC.Bail or 0.07) then kind = 'Bail' end
    if not kind then return end
    local pool = { 'alcohol', 'drugs', 'weapons', 'driving' }
    if kind == 'Bail' then pool[#pool + 1] = 'contact' end
    local conds = {}
    for _ = 1, math.random(1, 3) do
        local c = Pick(pool)
        local dup = false
        for _, x in ipairs(conds) do if x == c then dup = true end end
        if not dup then conds[#conds + 1] = c end
    end
    p.supervision = { kind = kind, conds = conds, officer = Pick({ 'PO Ramirez', 'PO Daniels', 'PO Okafor', 'PO Fischer', 'PO Hale' }) }
end

-- Conditions broken (only the ones you have evidence for)
function Violations(p)
    local s = p.supervision
    if not s then return {} end
    local out = {}
    for _, c in ipairs(s.conds or {}) do
        if c == 'alcohol' and p.results and (p.results.breath or 0) >= 0.02 then out[#out + 1] = ('%s: no alcohol - blew %.3f%%'):format(s.kind, p.results.breath)
        elseif c == 'drugs' and p.results and p.results.drug then out[#out + 1] = s.kind .. ': no drugs - positive swab'
        elseif c == 'weapons' then
            for _, it in ipairs(p.items or {}) do
                if it.weapon and (it.seized or it.found) then out[#out + 1] = s.kind .. ': no weapons - carrying ' .. it.label:lower() break end
            end
        elseif c == 'driving' and p.role == 'driver' then out[#out + 1] = s.kind .. ': must not drive - stopped driving'
        end
    end
    return out
end

function SupervisionInfo(p)
    local s = p.supervision
    if not s then return nil end
    local list = {}
    for _, c in ipairs(s.conds or {}) do list[#list + 1] = CONDITIONS[c] or c end
    return { kind = s.kind, conditions = list, officer = s.officer, violations = Violations(p) }
end

---------------------------------------------------------------------------
-- Emotions: fear and anger, on top of nervousness and rapport
---------------------------------------------------------------------------
local EMOTE = {
    firm = { fear = 3, anger = 4 }, calm = { fear = -3, anger = -4 },
    moment_stop = { fear = 4 }, moment_out = { fear = 5, anger = 2 }, moment_search = { anger = 6, fear = 3 },
    moment_cuff = { fear = 12, anger = 6 }, moment_aimed = { fear = 26, anger = 6 }, moment_felony = { fear = 20 },
    moment_cornered = { fear = 10, anger = 8 }, gunpoint = { fear = 22, anger = 5 }, struck = { fear = 15, anger = 25 },
    tased = { fear = 25, anger = 15 }, shout = { fear = 6, anger = 8 }, reassure = { fear = -10, anger = -6 },
}

function Emote(p, key)
    local e = EMOTE[key]
    if not e then return end
    p.fear = Clamp((p.fear or 10) + (e.fear or 0), 0, 100)
    p.anger = Clamp((p.anger or 10) + (e.anger or 0), 0, 100)
end

-- How fear and anger change the odds of running / fighting
function EmotionMod(p, moment)
    local fear, anger = p.fear or 10, p.anger or 10
    local flee = 1 + fear / 160 - (fear > 80 and 0.35 or 0)    -- terrified people freeze
    local fight = 1 + anger / 110 - fear / 260
    if p.crisis then fight = fight + 0.2 end
    return Clamp(flee, 0.4, 2.0), Clamp(fight, 0.3, 2.2)
end

---------------------------------------------------------------------------
-- Body language: tells you can read (true ones, plus a bit of noise)
---------------------------------------------------------------------------
local function MakeCues(p)
    local c = {}
    local function add(text, chance, kind) if Chance(chance) then c[#c + 1] = { text = text, kind = kind } end end
    if p.weapon or p.melee then
        add('Keeps touching their waistband', 0.7, 'waist')
        add('Blading their body away from you', 0.45, 'blade')
    end
    local illegalNonWeapon = false
    for _, it in ipairs(p.items or {}) do if not it.legal and not it.weapon then illegalNonWeapon = true end end
    if illegalNonWeapon then add('Keeps glancing at their pocket', 0.55, 'pocket') end
    if p.role == 'driver' and p.illegal and p.illegal > 0 then add('Glancing at the glovebox', 0.45, 'car') end
    if next(p.drugs or {}) then
        add('Pupils dilated', 0.6, 'eyes')
        add('Jittery, talking fast', 0.45, 'jitter')
    end
    if (p.bac or 0) >= 0.06 then
        add('Smell of alcohol', 0.85, 'smell')
        add('Glassy, bloodshot eyes', 0.6, 'eyes')
        if p.bac >= 0.12 then add('Slurred speech', 0.8, 'slur') end
    end
    if p.warrant then add('Avoiding eye contact', 0.5, 'eyes') end
    if (p.flee or 0) > 0.35 then add('Looking around for a way out', 0.6, 'look') end
    if p.mood == 'hostile' then add('Fists clenched', 0.5, 'fists') end
    if p.crisis then add('Talking to themselves, pacing', 0.9, 'pace') end
    -- innocent people get nervous too
    if not p.guilty and Chance(PC.FalseCue or 0.18) then
        c[#c + 1] = { text = Pick({ 'Hands shaking', 'Sweating', 'Avoiding eye contact', 'Fidgeting with their keys' }), kind = 'nervous' }
    end
    p.cues = c
end

---------------------------------------------------------------------------
-- Reaching for something (a 2-second call: aim, or let them)
---------------------------------------------------------------------------
local ReachMoments = { stop = 0.5, out = 1.0, search = 0.8, cuff = 0.6 }

function ReachRoll(p, moment)
    local w = ReachMoments[moment]
    if not w or p.cuffed or p.surrendered or p.crisis or p.reach then return nil end
    local chance
    if p.weapon or p.melee then
        chance = (PC.ReachArmed or 0.22) * w * (1 + (p.anger or 0) / 100)
        if Chance(chance) then
            p.reach = { what = Chance(0.75 + (p.anger or 0) / 400) and 'weapon' or 'wallet', at = os.time() }
            return p.reach.what
        end
    else
        chance = (PC.ReachInnocent or 0.05) * w
        if Chance(chance) then
            p.reach = { what = Pick({ 'wallet', 'phone', 'wallet' }), at = os.time() }
            return p.reach.what
        end
    end
    return nil
end

PoliceCallback('aiReachResolve', function(src, pid, aimed)
    local p, err = Get(src, pid, 40.0)
    if not p then return err end
    local r = p.reach
    if not r or r.resolved then return Fail() end
    r.resolved = true
    r.aimed = aimed == true
    local out = { ok = true, what = r.what }
    if r.what == 'weapon' then
        if aimed then
            -- caught red-handed: most freeze and drop it
            if Chance(0.75 - (p.anger or 0) / 300) then
                out.result, out.say = 'drop', Line('reach_drop')
                p.surrendered = true
                for _, it in ipairs(p.items) do if it.weapon then it.found = true end end
                Emote(p, 'gunpoint')
                Ev(p, 'Reached for a weapon - stopped at gunpoint and dropped it')
                p.reachedWeapon = true
            else
                out.result, out.say = 'draw', Line('fight')
                p.fought, p.fled, p.resisted = true, true, true
                Ev(p, 'Reached for a weapon and drew it on the officer')
            end
        else
            out.result, out.say = 'draw', Line('fight')
            p.fought, p.fled, p.resisted = true, true, true
            Ev(p, 'Drew a weapon on the officer')
        end
    else
        if aimed then
            out.result, out.say = 'freeze', Line('reach_freeze')
            Emote(p, 'gunpoint')
            p.rapport = Clamp((p.rapport or 30) - 12, 0, 100)
            Ev(p, 'Reached for their ' .. r.what .. ' - stopped at gunpoint')
        else
            out.result, out.say = 'produce', Line('reach_' .. r.what)
            if r.what == 'wallet' then p.hasId = true end
        end
    end
    out.persona = Public(p)
    return out
end)

---------------------------------------------------------------------------
-- Language barriers and the interpreter line
---------------------------------------------------------------------------
local LANGS = PC.Languages or { 'Spanish', 'Portuguese', 'Vietnamese', 'Korean', 'Russian', 'Arabic' }
local NONVERBAL_OK = { greet = true }

-- Returns what they say instead of an answer (or nil if they understand)
function LanguageGate(p, what)
    if not p.lang or p.interpreter then return nil end
    if NONVERBAL_OK[what] then return Line('lang_' .. p.lang:lower()) end
    return Line('lang_' .. p.lang:lower())
end

function InterpreterPrefix(p, say)
    if p.lang and p.interpreter and say and say ~= '' then return '[' .. p.lang .. ' interpreter] ' .. say end
    return say
end

PoliceCallback('aiInterpreter', function(src, pid)
    local p, err = Get(src, pid, 15.0)
    if not p then return err end
    if not p.lang then return Fail('They speak English.') end
    if p.interpreter then return Fail('The interpreter is already on the line.') end
    if Limited(src, 'interp', 6) then return Fail('Slow down.') end
    p.interpreter = true
    Ev(p, 'Language line interpreter used (' .. p.lang .. ')')
    return { ok = true, say = Line('lang_thanks'), persona = Public(p), msg = ('%s interpreter connected - you can talk to them now.'):format(p.lang) }
end)

---------------------------------------------------------------------------
-- Persona extras (called when a person is made up and when they're seen)
---------------------------------------------------------------------------
function PersonaHook(p, profileKey)
    p.fear = ({ calm = 12, nervous = 35, hostile = 15, drunk = 10 })[p.mood] or 15
    p.anger = ({ calm = 5, nervous = 10, hostile = 45, drunk = 20 })[p.mood] or 10
    if profileKey == 'crisis' then
        p.crisis, p.nego, p.mood = true, 30, 'nervous'
        p.fear, p.anger = 70, 30
    end
    if profileKey ~= 'crisis' and profileKey ~= 'victim' and profileKey ~= 'witness' and Chance(PC.LanguageChance or 0.07) then
        p.lang = Pick(LANGS)
    end
    MakeSupervision(p)
end

function PersonaRole(src, p)
    MaybeReturning(src, p)
    -- a child in the back (only the driver knows about it - the panel shows it on the driver)
    if p.role == 'driver' and not p.crisis and Chance(PC.ChildChance or 0.1) then
        p.child = Pick({ 'Infant in a rear car seat', 'Young child in a booster seat', 'Two young children in the back' })
    end
    if p.role == 'passenger' and (p.mood == 'hostile' or p.mood == 'drunk' or (p.anger or 0) > 30) and Chance(PC.InterfereChance or 0.3) then
        p.interfere = true
    end
    MakeCues(p)
end

function PublicExtra(p, t)
    t.fear, t.anger = Pct(p.fear), Pct(p.anger)
    t.cues = {}
    for _, c in ipairs(p.cues or {}) do t.cues[#t.cues + 1] = c end
    t.lang, t.interpreter = p.lang, p.interpreter == true
    t.child, t.childCared = p.child, p.childCared == true
    t.interfere, t.crisis, t.voluntary, t.clinician = p.interfere == true, p.crisis == true, p.voluntary == true, p.clinician == true
    t.filmed = p.filmed == true
    t.reach = p.reach and not p.reach.resolved and p.reach.what or nil
    if p.idChecked then
        t.supervision = SupervisionInfo(p)
        t.history = HistoryText(p)
    end
    t.knowsYou = p.knowsYou
    return t
end

---------------------------------------------------------------------------
-- Mental health crisis: talk them round, call the crisis team, voluntary assessment
---------------------------------------------------------------------------
CrisisReq = {}   -- [src] = when they asked for the mental health team
PoliceCallback('aiCrisisTeam', function(src, pid)
    local p, err = Get(src, pid, 80.0)
    if not p then return err end
    if not p.crisis or p.owner ~= src then return Fail() end
    if not CrisisReq[src] or os.time() - CrisisReq[src] > 900 then return Fail('Request the mental health team first.') end
    p.clinician = true
    Ev(p, 'Mental health crisis team arrived')
    return { ok = true, persona = Public(p) }
end)

PoliceCallback('aiHospital', function(src, pid)
    local p, err = Get(src, pid, 12.0)
    if not p then return err end
    if not p.voluntary or p.owner ~= src then return Fail('They haven\'t agreed to go yet.') end
    if p.hospitalised then return Fail() end
    p.hospitalised = true
    Ev(p, 'Taken for a voluntary mental health assessment')
    Bump(src, 'deescalations')
    Commend(src, p, 'Resolved a mental health crisis without force')
    Log(src, 'Crisis resolved - voluntary assessment')
    return { ok = true, say = Line('crisis_thanks'), msg = 'They\'re going for a voluntary assessment. Well handled - no force used.' }
end)

---------------------------------------------------------------------------
-- Children: someone has to look after them if the driver is arrested
---------------------------------------------------------------------------
local ChildWatch = {}   -- [pid] = { src, at }
CPSReq = {}

PoliceCallback('aiRelative', function(src, pid)
    local p = Personas[tostring(pid or '')]
    if not p or not p.child or p.owner ~= src then return Fail() end
    p.relativeAt = p.relativeAt or os.time()
    return { ok = true }
end)

PoliceCallback('aiChildCared', function(src, pid, how)
    local p = Personas[tostring(pid or '')]
    if not p or not p.child then return Fail() end
    if p.owner ~= src then return Fail() end
    if p.childCared then return { ok = true } end
    if how == 'cps' and (not CPSReq[src] or os.time() - CPSReq[src] > 1200) then return Fail('Request Child & Family Services first.') end
    if how == 'family' and os.time() - (p.relativeAt or 0) < 80 then return Fail('The relative isn\'t here yet.') end
    p.childCared = true
    ChildWatch[p.pid] = nil
    Ev(p, how == 'family' and 'Child collected by a family member' or 'Child handed to Child & Family Services')
    Log(src, 'Child safeguarded')
    return { ok = true }
end)

function ChildCheckOnArrest(src, p)
    if p.child and not p.childCared then ChildWatch[p.pid] = { src = src, at = os.time(), p = p } end
end

---------------------------------------------------------------------------
-- Interfering passengers
---------------------------------------------------------------------------
PoliceCallback('aiBackoff', function(src, pid)
    local p, err = Get(src, pid, 25.0)
    if not p then return err end
    if Limited(src, 'backoff', 20) then return Fail('Slow down.') end
    p.backoffs = (p.backoffs or 0) + 1
    Emote(p, 'shout')
    local comply = Chance(Clamp(0.7 - (p.anger or 0) / 200 + (p.fear or 0) / 300 - (p.backoffs - 1) * 0.05, 0.15, 0.9))
    if comply then
        p.interfere = false
        Ev(p, 'Told to back off - complied')
        return { ok = true, comply = true, say = Line('backoff_ok'), persona = Public(p) }
    end
    p.obstructed = (p.obstructed or 0) + 1
    Ev(p, 'Told to back off - refused (' .. p.obstructed .. ')')
    return { ok = true, comply = false, say = Line('backoff_no'), persona = Public(p),
        msg = p.obstructed >= 2 and 'They keep interfering - you can detain them for obstruction.' or nil }
end)

---------------------------------------------------------------------------
-- Bystanders filming
---------------------------------------------------------------------------
PoliceCallback('aiFilming', function(src, pid)
    local p, err = Get(src, pid, 80.0)
    if not p then return err end
    if p.owner ~= src then return { ok = true } end
    p.filmed = true
    Ev(p, 'A bystander was filming the encounter')
    return { ok = true }
end)

---------------------------------------------------------------------------
-- Complaints, commendations and Internal Affairs
---------------------------------------------------------------------------
local IA = LoadJson('data/ia.json', { seq = 1000, list = {} })
IA.list = IA.list or {}
local iaDirty = false
local Trim

local function NewComplaint(src, p, kind, text, evidence, base)
    IA.seq = (tonumber(IA.seq) or 1000) + 1
    local c = {
        id = 'IA' .. IA.seq, officer = Ident(src), officerName = OfficerLabel(src), kind = kind, text = text,
        person = p and (p.idChecked and p.name or 'Member of the public') or 'Member of the public', pid = p and p.pid,
        evidence = evidence or {}, base = base or 0.4, created = os.time(), due = os.time() + (PC.ReviewMinutes or 10) * 60,
        status = 'open', date = os.date('%d/%m %H:%M'),
    }
    table.insert(IA.list, 1, c)
    Trim()
    iaDirty = true
    if Online(src) then
        TriggerClientEvent(EV .. 'aiComplaint', src, { id = c.id, kind = kind, text = text })
    end
    return c
end

local lastCommend = {}
Trim = function()
    -- drop the oldest closed complaints / commendations first; open ones are kept
    while #IA.list > 300 do
        local removed = false
        for i = #IA.list, 1, -1 do
            if IA.list[i].status ~= 'open' then table.remove(IA.list, i) removed = true break end
        end
        if not removed then table.remove(IA.list) end
    end
end

function Commend(src, p, text)
    local me = Ident(src)
    if me and lastCommend[me] and os.time() - lastCommend[me] < (PC.CommendGap or 600) then return end
    if me then lastCommend[me] = os.time() end
    IA.seq = (tonumber(IA.seq) or 1000) + 1
    table.insert(IA.list, 1, { id = 'CM' .. IA.seq, officer = Ident(src), officerName = OfficerLabel(src), kind = 'commendation', text = text,
        person = p and p.idChecked and p.name or nil, created = os.time(), status = 'commendation', date = os.date('%d/%m %H:%M') })
    Trim()
    iaDirty = true
    if Online(src) then Bump(src, 'commendations') end
    if Online(src) then TriggerClientEvent(EV .. 'aiCommend', src, text) end
end

-- Force used on someone who wasn't a threat
PoliceCallback('aiForce', function(src, pid, kind)
    local p = Personas[tostring(pid or '')]
    if not p then return { ok = true } end
    if Limited(src, 'force', 6) then return { ok = true } end
    kind = tostring(kind or '')
    if p.forceLogged and p.forceLogged[kind] then return { ok = true } end
    p.forceLogged = p.forceLogged or {}
    -- justified: they were fighting, drew a weapon, or reached for one
    if p.fought and kind ~= 'restrained' then return { ok = true } end
    if p.reachedWeapon then return { ok = true } end
    if p.owner ~= src then return { ok = true } end
    if (p.obstructed or 0) >= 2 and kind ~= 'restrained' and kind ~= 'shot_unarmed' then return { ok = true } end
    local texts = {
        restrained = 'Used force on a person who was already restrained',
        compliant = 'Used force on a compliant person',
        shot_unarmed = 'Shot an unarmed person',
        shot_reaching = 'Shot a person who was reaching for their ' .. ((p.reach and p.reach.what) or 'wallet'),
        tased = 'Tased a compliant person',
        vehicle = 'Struck a person with a vehicle',
    }
    local text = texts[kind]
    if not text then return { ok = true } end
    p.forceLogged[kind] = true
    local ev = {}
    if p.filmed then ev[#ev + 1] = 'Bystander video' end
    local base = ({ restrained = 0.75, compliant = 0.55, shot_unarmed = 0.8, shot_reaching = 0.45, tased = 0.5, vehicle = 0.4 })[kind] or 0.5
    if kind == 'shot_reaching' and p.reach and p.reach.aimed then base = base - 0.15 end   -- they kept reaching at gunpoint
    Emote(p, kind == 'tased' and 'tased' or 'struck')
    Ev(p, 'Force: ' .. text)
    NewComplaint(src, p, 'Excessive force', text, ev, base)
    return { ok = true }
end)

-- Full search with no consent, no arrest and no probable cause
function SearchCheck(src, p, kind, found)
    if kind ~= 'search' or p.searchComplained then return end
    local consent = p.consentGiven and p.consentGiven.person
    local found = false
    for _, it in ipairs(p.items or {}) do if it.found and not it.legal then found = true end end
    local sfstFail = false
    for _, v in pairs(p.sfst or {}) do if v then sfstFail = true end end
    local cause = p.cuffed or (p.warrant and p.idChecked) or (p.results and ((p.results.breath or 0) >= (Config.DrinkLimit or 0.08) or p.results.drug or p.results.gsr))
        or p.k9 or #(p.lies or {}) > 0 or #(p.confessed or {}) > 0 or p.reachedWeapon or p.fled or found or sfstFail
        or p.stolenCar or (p.vehFinds or 0) > 0 or p.matches or (p.obstructed or 0) >= 2
    if consent or cause then return end
    local illegal = 0
    for _, o in ipairs(found or {}) do if not o.legal then illegal = illegal + 1 end end
    if Chance(illegal > 0 and 0.2 or 0.6) then
        p.searchComplained = true
        NewComplaint(src, p, 'Unlawful search', 'Searched without consent, arrest or probable cause', p.filmed and { 'Bystander video' } or {}, illegal > 0 and 0.35 or 0.6)
    end
end

-- Released people who were treated harshly may complain
function RudeCheck(src, p)
    if p.rudeChecked or p.guilty or not p.stopCounted or p.owner ~= src then return end
    p.rudeChecked = true
    if (p.rapport or 30) < 18 and (p.toned or 0) >= 6 and Chance(0.35) then
        NewComplaint(src, p, 'Discourtesy', 'Rude and aggressive manner during a stop - nothing was found', p.filmed and { 'Bystander video' } or {}, 0.45)
    elseif (p.rapport or 0) >= 70 and Chance(0.12) then
        Commend(src, p, 'A member of the public praised your professionalism during a stop')
    end
end

PoliceCallback('iaList', function(src)
    local me = Ident(src)
    local admin = IsAdmin(src)
    local mine, all = {}, {}
    for _, c in ipairs(IA.list) do
        local v = { id = c.id, kind = c.kind, text = c.text, person = c.person, evidence = c.evidence, status = c.status, date = c.date,
            response = c.response, outcome = c.outcome, officer = c.officerName, due = c.due and math.max(0, c.due - os.time()) or nil }
        if c.officer == me then mine[#mine + 1] = v end
        if admin and #all < 60 then all[#all + 1] = v end
    end
    local s = X.StatsOf(src) or {}
    return { ok = true, mine = mine, all = admin and all or nil, admin = admin, sustained = s.sustained or 0, commendations = s.commendations or 0 }
end)

PoliceCallback('iaRespond', function(src, id, text)
    text = CleanText(text, 1500)
    for _, c in ipairs(IA.list) do
        if c.id == id then
            if c.officer ~= Ident(src) then return Fail('That isn\'t your complaint.') end
            if c.status ~= 'open' then return Fail('That complaint has been decided.') end
            if #text < 40 then return Fail('Write a bit more in your statement.') end
            c.response = text
            iaDirty = true
            return { ok = true, msg = 'Statement submitted to Internal Affairs.' }
        end
    end
    return Fail('Complaint not found.')
end)

-- Staff can decide a complaint themselves
PoliceCallback('iaDecide', function(src, id, outcome)
    if not IsAdmin(src) then return Fail('Staff only.') end
    if outcome ~= 'sustained' and outcome ~= 'not sustained' and outcome ~= 'exonerated' then return Fail() end
    for _, c in ipairs(IA.list) do
        if c.id == id and c.status == 'open' then c.due = 0 c.forced = outcome iaDirty = true return { ok = true } end
    end
    return Fail('Complaint not found.')
end)

local function Decide(c)
    local s = c.base or 0.4
    if #(c.evidence or {}) > 0 then s = s + 0.25 end
    if c.response and #c.response >= 120 then s = s - 0.15 elseif c.response then s = s - 0.07 else s = s + 0.05 end
    local outcome = c.forced
    if not outcome then
        local roll = math.random()
        if roll < Clamp(s, 0.05, 0.95) then outcome = 'sustained'
        elseif roll < Clamp(s, 0.05, 0.95) + 0.25 then outcome = 'not sustained'
        else outcome = 'exonerated' end
    end
    c.status, c.outcome = 'closed', outcome
    iaDirty = true
    local src = SrcFromIdent(c.officer)
    local st = src and X.StatsOf(src) or (X.Stats and X.Stats[c.officer])
    if outcome == 'sustained' then
        if st then
            st.sustained = (st.sustained or 0) + 1
            st.xp = math.max(0, (st.xp or 0) - (PC.SustainedXP or 60))
            X.MarkStats()
        end
    end
    if src then TriggerClientEvent(EV .. 'aiIADecision', src, { id = c.id, kind = c.kind, outcome = outcome }) end
end

CreateThread(function()
    while true do
        Wait(20000)
        local now = os.time()
        for _, c in ipairs(IA.list) do
            if c.status == 'open' and now >= (c.due or 0) then
                -- only decide while the officer is around (so they hear about it), or after a day regardless (or when staff decided)
                if SrcFromIdent(c.officer) or c.forced or now - c.created > 86400 then
                    local ok, e = pcall(Decide, c)
                    if not ok then print('[statewide_police] IA error: ' .. tostring(e)) c.status = 'closed' end
                end
            end
        end
        -- children left with nobody to look after them
        for pid, w in pairs(ChildWatch) do
            if w.p.childCared then ChildWatch[pid] = nil
            elseif now - w.at > (PC.ChildMinutes or 6) * 60 then
                ChildWatch[pid] = nil
                if Online(w.src) then
                    NewComplaint(w.src, w.p, 'Neglect of duty', 'Arrested a parent and left a child without arranging care', {}, 0.7)
                end
            end
        end
        -- memory saving
        KnownSave()
        if iaDirty then SaveJson('data/ia.json', IA) iaDirty = false end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    knownDirty = true
    KnownSave()
    if iaDirty then SaveJson('data/ia.json', IA) end
end)

---------------------------------------------------------------------------
-- Court extras: supervision violations, bail decisions, wrongful arrests
---------------------------------------------------------------------------
function CourtExtra(r)
    local c = r.court
    local ev = r.ev or {}
    if #(ev.violations or {}) > 0 then
        c.violation = (ev.supervisionKind or 'Supervision') .. ' violated - ' .. (ev.supervisionKind == 'Parole' and 'parole revoked, returned to prison'
            or ev.supervisionKind == 'Bail' and 'bail revoked, remanded in custody' or 'back before the judge, probation extended')
    end
    if c.guilty > 0 then
        local serious = false
        for _, v in ipairs(c.verdicts) do
            local l = v.charge:lower()
            if v.guilty and (l:find('firearm') or l:find('robbery') or l:find('assault') or l:find('murder') or l:find('kidnap') or l:find('supply')) then serious = true end
        end
        if c.violation or serious and Chance(0.6) then
            c.bail = 'Remanded in custody'
        else
            c.bail = ('Bail set at %s - conditions: %s'):format(Money and Money(Pick({ 500, 1000, 2500, 5000, 10000 })) or '$2,500', Pick({ 'no alcohol', 'no drugs', 'no weapons', 'must not drive', 'curfew' }))
            -- next time they're seen, they're on bail
            local k = Known[r.ident]
            if k then
                k.supervision = { kind = 'Bail', conds = { Pick({ 'alcohol', 'drugs', 'weapons', 'driving' }) }, officer = 'County Court' }
                knownDirty = true
            end
        end
    elseif c.guilty == 0 and #c.verdicts > 0 and Chance(0.3) then
        local src = SrcFromIdent(r.officer)
        if src then NewComplaint(src, { name = r.name, idChecked = true }, 'Wrongful arrest', 'Every charge was dismissed in court', {}, 0.35) end
    end
end

---------------------------------------------------------------------------
-- A robber grabbing someone when police arrive
---------------------------------------------------------------------------
PoliceCallback('aiTakeHostage', function(src, pid)
    local p, err = Get(src, pid, 200.0)
    if not p then return err end
    if p.cuffed or p.surrendered or p.hostage then return Fail() end
    p.hostage, p.nego = true, 25
    p.reach = nil
    Ev(p, 'Took a hostage when police arrived')
    return { ok = true, persona = Public(p) }
end)
