-- Searching, seizing, ID checks and roadside tests
local ITEMS, ECON, LICENCE, SHOPS = 'statewide_items', 'statewide_economy', 'statewide_drivingschool', 'statewide_shops'

Residue = {}      -- [ident] = os.time() they last fired a gun (GSR)
local Alcohol = {}      -- [ident] = { real = bac, rp = bac, t = os.time() }
local RPDrugs = {}      -- [ident] = { drug = expiresAt }
local Pending = {}      -- [officer] = { target, kind, started } - a test / search in progress

local LICENCE_LABELS = { car = 'Driving licence (car)', bike = 'Motorcycle licence', truck = 'HGV / truck licence', firearms = 'Firearms licence' }

local TESTS = {
    frisk  = { time = 5000,  targetAnim = nil },
    search = { time = 8000,  targetAnim = nil },
    breath = { time = 6000,  targetAnim = 'blow' },
    drug   = { time = 10000, targetAnim = 'blow' },
    gsr    = { time = 6000,  targetAnim = nil },
    dna    = { time = 5000,  targetAnim = 'blow' },
}

---------------------------------------------------------------------------
-- Alcohol & drugs
---------------------------------------------------------------------------
local function BAC(ident)
    local a = Alcohol[ident]
    if not a then return 0.0, 0.0 end
    local mins = (os.time() - a.t) / 60
    local decay = mins * Config.BACDecayPerMinute
    -- wear off roleplay drinks first, then real ones
    local rp = math.max(0.0, a.rp - decay)
    local left = math.max(0.0, decay - a.rp)
    local real = math.max(0.0, a.real - left)
    a.real, a.rp, a.t = real, rp, os.time()
    if real + rp <= 0 then Alcohol[ident] = nil end
    return real, rp
end

local function AddAlcohol(ident, amount, rp)
    local real, rpb = BAC(ident)
    Alcohol[ident] = { real = real + (rp and 0 or amount), rp = rpb + (rp and amount or 0), t = os.time() }
end

local function SendBAC(src)
    local real = BAC(Ident(src))
    TriggerClientEvent(EV .. 'bac', src, real)
end

AddEventHandler('statewide_items:used', function(src, name)
    local add = Config.Alcohol[name]
    if not add then return end
    local ident = Ident(src)
    if not ident then return end
    AddAlcohol(ident, add, false)
    SetTimeout(8000, function() if Online(src) then SendBAC(src) end end)
end)

-- Drunk effects wear off over time
CreateThread(function()
    while true do
        Wait(60000)
        for ident in pairs(Alcohol) do
            local src = SrcFromIdent(ident)
            if src then SendBAC(src) else BAC(ident) end
        end
    end
end)

local function ActiveDrugs(ident)
    local out, now = {}, os.time()
    for drug, exp in pairs(RPDrugs[ident] or {}) do
        if exp > now then out[drug] = true else RPDrugs[ident][drug] = nil end
    end
    return out
end

RegisterCommand('rpstatus', function(src, args)
    if src == 0 then return end
    local ident = Ident(src)
    local what = (args[1] or ''):lower()
    if what == 'clear' then
        RPDrugs[ident] = nil
        if Alcohol[ident] then Alcohol[ident].rp = 0.0 end
        return Notify(src, 'Roleplay status cleared.')
    elseif what == 'drink' or what == 'drinks' then
        local n = math.max(1, math.min(10, math.floor(tonumber(args[2]) or 1)))
        AddAlcohol(ident, Config.RPDrinkBAC * n, true)
        return Notify(src, ('Roleplay: %d drink%s added. A breathalyser will pick it up.'):format(n, n == 1 and '' or 's'))
    elseif Config.Drugs[what] then
        local mins = math.max(5, math.min(240, math.floor(tonumber(args[2]) or Config.DrugDefaultMinutes)))
        RPDrugs[ident] = RPDrugs[ident] or {}
        RPDrugs[ident][what] = os.time() + mins * 60
        return Notify(src, ('Roleplay: %s will show on a drug test for %d minutes.'):format(Config.Drugs[what], mins))
    end
    local names = {}
    for k in pairs(Config.Drugs) do names[#names + 1] = k end
    table.sort(names)
    local real, rp = BAC(ident)
    local now = {}
    for d in pairs(ActiveDrugs(ident)) do now[#now + 1] = Config.Drugs[d] end
    Notify(src, ('Usage: /rpstatus drink [amount] | /rpstatus <drug> [minutes] | /rpstatus clear. Drugs: %s'):format(table.concat(names, ', ')))
    Notify(src, ('Right now: BAC %.3f%%%s'):format(real + rp, #now > 0 and (', ' .. table.concat(now, ', ')) or ''))
end, false)

---------------------------------------------------------------------------
-- Tests & searches: start (checks + target animation) then result (after the officer's animation)
---------------------------------------------------------------------------
PoliceCallback('testStart', function(src, target, kind)
    local def = TESTS[kind]
    if not def then return Fail() end
    local t, err = CheckTarget(src, target, 2.5)
    if not t then return err end
    if kind == 'search' and not IsCuffed(t) then
        Notify(src, 'Asking for their consent...')
        local yes = AskClient(t, 'consent', { officer = OfficerLabel(src) }, (Config.ConsentSeconds + 3) * 1000)
        if not yes then return Fail('They refused the search (or didn\'t answer). Restrain them to search without consent.') end
        if not Near(src, t, 3.0) then return Fail('They moved away.') end
    end
    Pending[src] = { target = t, kind = kind, started = GetGameTimer() }
    if def.targetAnim then TriggerClientEvent(EV .. 'testTarget', t, def.targetAnim, def.time) end
    local what = ({ frisk = 'pat you down', search = 'search you', breath = 'breathalyse you', drug = 'drug test you',
        gsr = 'test your hands for gunshot residue', dna = 'take a DNA swab' })[kind]
    Notify(t, ('%s is going to %s.'):format(OfficerLabel(src), what))
    return { ok = true, time = def.time }
end)

local function Weapons(t)
    local list = AskClient(t, 'weapons', nil, 4000) or {}
    local out = {}
    for _, w in ipairs(list) do
        if type(w) == 'string' then out[#out + 1] = { name = w, label = WeaponLabel(w) } end
    end
    return out
end

function WeaponLabel(name)
    local label = name:gsub('^WEAPON_', ''):gsub('_', ' '):lower():gsub('^%l', string.upper)
    return label
end

local function SearchResult(t, full)
    local out = { ok = true, name = Name(t), id = t, weapons = Weapons(t) }
    if full then
        out.items, out.cash = {}, 0
        if Started(ITEMS) then
            local ok, items = pcall(function() return exports[ITEMS]:GetItems(t) end)
            for name, count in pairs(ok and items or {}) do
                local lok, label = pcall(function() return exports[ITEMS]:GetLabel(name) end)
                out.items[#out.items + 1] = { name = name, label = lok and label or name, count = count }
            end
            table.sort(out.items, function(a, b) return a.label < b.label end)
        end
        if Started(ECON) then
            local ok, cash = pcall(function() return exports[ECON]:GetCash(t) end)
            out.cash = ok and cash or 0
        end
    end
    return out
end

PoliceCallback('testResult', function(src, kind)
    local p = Pending[src]
    if not p or p.kind ~= kind then return Fail('Start again.') end
    if GetGameTimer() - p.started < TESTS[kind].time - 1500 then return Fail('Too quick.') end
    local t = p.target
    if not Online(t) or not Near(src, t, 4.0) then Pending[src] = nil return Fail('They moved away.') end
    local ident = Ident(t)
    if kind == 'breath' then
        Pending[src] = nil
        local real, rp = BAC(ident)
        local bac = math.floor((real + rp) * 1000 + 0.5) / 1000
        local over = bac >= Config.DrinkLimit
        Notify(t, ('You blew %.3f%% - %s.'):format(bac, over and 'over the legal limit' or 'under the limit'))
        return { ok = true, kind = 'breath', name = Name(t), bac = bac, limit = Config.DrinkLimit, over = over }
    elseif kind == 'drug' then
        Pending[src] = nil
        local active = ActiveDrugs(ident)
        local list = {}
        for key, label in pairs(Config.Drugs) do list[#list + 1] = { label = label, positive = active[key] == true } end
        table.sort(list, function(a, b) return a.label < b.label end)
        local any = next(active) ~= nil
        Notify(t, any and 'Your drug test came back positive.' or 'Your drug test came back negative.')
        return { ok = true, kind = 'drug', name = Name(t), results = list, positive = any }
    elseif kind == 'gsr' then
        Pending[src] = nil
        local shot = Residue[ident]
        local positive = shot ~= nil and os.time() - shot < Config.GSRMinutes * 60
        return { ok = true, kind = 'gsr', name = Name(t), positive = positive }
    elseif kind == 'dna' then
        Pending[src] = nil
        local r = Record(ident, Name(t))
        r.dna = true
        AddToLocker(src, { type = 'dna', label = 'DNA reference sample', from = Name(t), fromIdent = ident })
        Notify(t, 'A DNA sample was taken from you.')
        return { ok = true, kind = 'dna', name = Name(t), msg = ('DNA sample taken - %s\'s DNA is now on file.'):format(Name(t)) }
    elseif kind == 'frisk' then
        Pending[src] = nil
        Notify(t, 'You were patted down.')
        local res = SearchResult(t, false)
        res.kind = 'frisk'
        return res
    elseif kind == 'search' then
        -- keep the permission for a minute so they can seize things
        p.until_ = os.time() + 90
        Notify(t, 'You were searched.')
        local res = SearchResult(t, true)
        res.kind = 'search'
        p.weapons = {}
        for _, w in ipairs(res.weapons) do p.weapons[w.name] = true end
        return res
    end
    return Fail()
end)

local function CanSeize(src, target)
    local p = Pending[src]
    target = tonumber(target)
    if not p or p.kind ~= 'search' or p.target ~= target or os.time() > (p.until_ or 0) then return false end
    return Near(src, target, 4.0)
end

PoliceCallback('seize', function(src, target, what, name, count)
    target = tonumber(target)
    if not CanSeize(src, target) then return Fail('Search them again first.') end
    local ident = Ident(target)
    if what == 'item' then
        count = math.max(1, math.floor(tonumber(count) or 1))
        if not Started(ITEMS) then return Fail() end
        local ok, removed = pcall(function() return exports[ITEMS]:RemoveItem(target, name, count) end)
        if not ok or not removed then return Fail('They don\'t have that many.') end
        local lok, label = pcall(function() return exports[ITEMS]:GetLabel(name) end)
        AddToLocker(src, { type = 'item', label = ('%dx %s'):format(count, lok and label or name), from = Name(target), fromIdent = ident })
        Notify(target, ('Police seized %dx %s from you.'):format(count, lok and label or name))
    elseif what == 'weapon' then
        name = tostring(name):upper()
        local p = Pending[src]
        if not name:match('^WEAPON_') or not (p and p.weapons and p.weapons[name]) then return Fail('They don\'t have that on them.') end
        p.weapons[name] = nil
        TriggerClientEvent(EV .. 'removeWeapon', target, name)
        if Started(SHOPS) then pcall(function() exports[SHOPS]:SeizeWeapon(target, name) end) end
        AddToLocker(src, { type = 'weapon', label = WeaponLabel(name), weapon = name, from = Name(target), fromIdent = ident })
        Notify(target, ('Police seized your %s.'):format(WeaponLabel(name)))
    elseif what == 'cash' then
        count = math.floor(tonumber(count) or 0)
        if count < 1 or not Started(ECON) then return Fail('How much?') end
        local ok, removed = pcall(function() return exports[ECON]:RemoveCash(target, count, 'Seized by police') end)
        if not ok or not removed then return Fail('They don\'t have that much cash.') end
        AddToLocker(src, { type = 'cash', label = ('Cash - %s'):format(Money(count)), amount = count, from = Name(target), fromIdent = ident })
        Notify(target, ('Police seized %s in cash from you.'):format(Money(count)))
    else
        return Fail()
    end
    local res = SearchResult(target, true)
    res.kind = 'search'
    return res
end)

---------------------------------------------------------------------------
-- ID
---------------------------------------------------------------------------
local function Licences(t)
    local out = {}
    if Started(LICENCE) then
        local ok, list = pcall(function() return exports[LICENCE]:GetLicences(t) end)
        for key, v in pairs(ok and list or {}) do
            out[#out + 1] = { label = LICENCE_LABELS[key] or key, date = type(v) == 'table' and v.date or '' }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function RecordSummary(ident)
    local r = Records[ident] or {}
    local unpaid, owed, warrants = 0, 0, {}
    for _, f in ipairs(r.fines or {}) do if not f.paid then unpaid = unpaid + 1 owed = owed + f.amount end end
    for _, w in ipairs(r.warrants or {}) do if w.active then warrants[#warrants + 1] = w end end
    return { unpaid = unpaid, owed = owed, warrants = warrants, arrests = #(r.arrests or {}), dna = r.dna == true, prints = r.prints == true,
        sentence = Sentences[ident] and Sentences[ident].kind or nil }
end

PoliceCallback('checkId', function(src, target)
    local t, err = CheckTarget(src, target, 4.0)
    if not t then return err end
    local ident = Ident(t)
    Record(ident, Name(t))
    Notify(t, ('%s is checking your ID.'):format(OfficerLabel(src)))
    return { ok = true, name = Name(t), id = t, licences = Licences(t), record = RecordSummary(ident) }
end)

RegisterCallback('showId', function(src, target)
    local t, err = CheckTarget(src, target, 3.5)
    if not t then return err end
    TriggerClientEvent(EV .. 'idCard', t, { name = Name(src), id = src, licences = Licences(src), from = src })
    return { ok = true, msg = ('You showed your ID to %s.'):format(Name(t)) }
end)

PoliceCallback('badge', function(src)
    local d = Duty(src)
    local card = { name = Name(src), dept = d and d.name or 'Police', unit = d and d.unit or '', from = src }
    for _, p in ipairs(GetPlayers()) do
        p = tonumber(p)
        if p ~= src and Near(src, p, 6.0) then TriggerClientEvent(EV .. 'badgeCard', p, card) end
    end
    return { ok = true }
end)

AddEventHandler('playerDropped', function() Pending[source] = nil end)
