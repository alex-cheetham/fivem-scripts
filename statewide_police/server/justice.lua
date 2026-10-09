-- Tickets, fines, booking, jail, community service, records & warrants (MDT)
local ECON, LICENCE = 'statewide_economy', 'statewide_drivingschool'
local ChoreUsed = {}   -- [src] = { [index] = os.time() }

local function Offences(list)
    local labels, fine, jail = {}, 0, 0
    for _, i in ipairs(type(list) == 'table' and list or {}) do
        local o = Config.PenalCode[tonumber(i) or 0]
        if o then
            labels[#labels + 1] = o.label
            fine = fine + o.fine
            jail = jail + o.jail
        end
    end
    return labels, fine, jail
end

local function CleanText(s, max) return tostring(s or ''):gsub('[<>]', ''):sub(1, max or 300) end

RegisterCallback('penalCode', function() return { ok = true, code = Config.PenalCode, maxJail = Config.Jail.maxMinutes, maxTasks = Config.ComServ.maxTasks } end)

---------------------------------------------------------------------------
-- Citations / fines
---------------------------------------------------------------------------
PoliceCallback('ticket', function(src, data)
    if type(data) ~= 'table' then return Fail() end
    local t, err = CheckTarget(src, data.target, 8.0)
    if not t then return err end
    local labels, fine = Offences(data.offences)
    if #labels == 0 then return Fail('Pick at least one offence.') end
    local amount = math.floor(tonumber(data.amount) or fine)
    if amount < 0 or amount > 100000 then return Fail('That fine isn\'t allowed.') end
    local ident = Ident(t)
    local r = Record(ident, Name(t))
    local f = { id = NewCaseId('C'), date = Stamp(), officer = OfficerLabel(src), offences = labels, amount = amount,
        notes = CleanText(data.notes), paid = amount == 0 }
    table.insert(r.fines, 1, f)
    Dirty.records = true
    -- licences taken away with the ticket
    local revoked = {}
    if type(data.revoke) == 'table' and Started(LICENCE) then
        for _, key in ipairs(data.revoke) do
            if key == 'car' or key == 'bike' or key == 'truck' or key == 'firearms' then
                local ok, done = pcall(function() return exports[LICENCE]:RevokeLicence(t, key) end)
                if ok and done then revoked[#revoked + 1] = key end
            end
        end
    end
    f.revoked = revoked
    TriggerClientEvent(EV .. 'citation', t, f)
    return { ok = true, msg = ('Citation %s issued to %s for %s.'):format(f.id, Name(t), Money(amount)) }
end)

RegisterCallback('myFines', function(src)
    local r = Records[Ident(src)]
    local list = {}
    for _, f in ipairs(r and r.fines or {}) do list[#list + 1] = f end
    return { ok = true, fines = list }
end)

RegisterCallback('payFine', function(src, id, method)
    local r = Records[Ident(src)]
    if not r then return Fail() end
    for _, f in ipairs(r.fines) do
        if f.id == id then
            if f.paid then return Fail('That\'s already paid.') end
            if not Started(ECON) then return Fail('Payments are down right now.') end
            local ok, paid = pcall(function() return exports[ECON]:Charge(src, f.amount, 'Fine ' .. f.id, method) end)
            if not ok or not paid then return Fail(('You can\'t afford %s%s.'):format(Money(f.amount), method and (' by ' .. method) or '')) end
            f.paid, f.paidDate = true, Stamp()
            Dirty.records = true
            local list = {}
            for _, x in ipairs(r.fines) do list[#list + 1] = x end
            return { ok = true, msg = ('Fine %s paid (%s).'):format(f.id, Money(f.amount)), fines = list }
        end
    end
    return Fail('Fine not found.')
end)

RegisterCommand('fines', function(src) if src > 0 then TriggerClientEvent(EV .. 'openFines', src) end end, false)

---------------------------------------------------------------------------
-- Sentences
---------------------------------------------------------------------------
local function SendSentence(src, fresh)
    local s = Sentences[Ident(src)]
    if s then TriggerClientEvent(EV .. 'sentence', src, s, fresh == true) end
end

function Release(src, why)
    local ident = Ident(src)
    local s = Sentences[ident]
    if not s then return false end
    Sentences[ident] = nil
    Dirty.sentences = true
    TriggerClientEvent(EV .. 'released', src, s.kind, why)
    return true
end

local function Sentence(t, kind, amount, officer, charges)
    local ident = Ident(t)
    Sentences[ident] = { kind = kind, left = amount, total = amount, officer = officer, charges = charges, date = Stamp() }
    Dirty.sentences = true
    Uncuff(t)
    SendSentence(t, true)
end

PoliceCallback('arrest', function(src, data)
    if type(data) ~= 'table' then return Fail() end
    local t, err = CheckTarget(src, data.target, 8.0)
    if not t then return err end
    if not IsCuffed(t) then return Fail('They need to be restrained first.') end
    local station = NearStation(src)
    if not Config.BookAnywhere and not station then return Fail('Take them to a station booking desk first.') end
    local labels, fine, jail = Offences(data.offences)
    if #labels == 0 then return Fail('Pick at least one charge.') end
    local minutes = math.floor(tonumber(data.minutes) or jail)
    minutes = math.max(1, math.min(Config.Jail.maxMinutes, minutes))
    local amount = math.max(0, math.min(100000, math.floor(tonumber(data.amount) or fine)))
    local ident = Ident(t)
    local r = Record(ident, Name(t))
    local case = NewCaseId('A')
    table.insert(r.arrests, 1, { id = case, date = Stamp(), officer = OfficerLabel(src), charges = labels, minutes = minutes, fine = amount,
        notes = CleanText(data.notes), station = station and station.label or 'Field' })
    r.dna, r.prints = true, true   -- booking takes prints and DNA
    for _, w in ipairs(r.warrants) do if w.active then w.active = false w.served = Stamp() end end
    if amount > 0 then
        local paid = false
        if Started(ECON) then
            local ok, done = pcall(function() return exports[ECON]:Charge(t, amount, 'Court fine ' .. case) end)
            paid = ok and done
        end
        table.insert(r.fines, 1, { id = case, date = Stamp(), officer = OfficerLabel(src), offences = labels, amount = amount,
            notes = 'Fine with arrest', paid = paid, paidDate = paid and Stamp() or nil })
    end
    Dirty.records = true
    Sentence(t, 'jail', minutes * 60, OfficerLabel(src), labels)
    Notify(t, ('You\'ve been sentenced to %d minutes in Bolingbroke%s.'):format(minutes, amount > 0 and (' and fined ' .. Money(amount)) or ''))
    return { ok = true, msg = ('%s booked (%s) - %d minutes.'):format(Name(t), case, minutes) }
end)

PoliceCallback('comserv', function(src, data)
    if type(data) ~= 'table' then return Fail() end
    local t, err = CheckTarget(src, data.target, 8.0)
    if not t then return err end
    local tasks = math.max(1, math.min(Config.ComServ.maxTasks, math.floor(tonumber(data.tasks) or 10)))
    local labels = Offences(data.offences)
    local r = Record(Ident(t), Name(t))
    table.insert(r.arrests, 1, { id = NewCaseId('S'), date = Stamp(), officer = OfficerLabel(src), charges = labels,
        comserv = tasks, notes = CleanText(data.notes), station = 'Community service' })
    Dirty.records = true
    Sentence(t, 'comserv', tasks, OfficerLabel(src), labels)
    Notify(t, ('You\'ve been given %d community service tasks at Legion Square.'):format(tasks))
    return { ok = true, msg = ('%s given %d tasks of community service.'):format(Name(t), tasks) }
end)

PoliceCallback('unjail', function(src, target)
    target = tonumber(target)
    if not Online(target) then return Fail('That player isn\'t online.') end
    if target == src then return Fail('You can\'t release yourself.') end
    if not Release(target, 'Released by ' .. OfficerLabel(src)) then return Fail('They aren\'t serving a sentence.') end
    return { ok = true, msg = ('%s released.'):format(Name(target)) }
end)

RegisterCallback('choreStart', function(src)
    ChoreUsed[src] = ChoreUsed[src] or {}
    ChoreUsed[src].last = os.time()
    return { ok = true }
end)

RegisterCallback('chore', function(src, index)
    local s = Sentences[Ident(src)]
    if not s then return Fail() end
    index = tonumber(index)
    local list = s.kind == 'jail' and GetPoints().chores or GetPoints().comserv
    local spot = list[tonumber(index) or 0]
    if not spot or #(Pos(src) - V3(spot)) > 3.0 then return Fail('Stand at the spot.') end
    ChoreUsed[src] = ChoreUsed[src] or {}
    local secs = s.kind == 'jail' and Config.Jail.choreSeconds or Config.ComServ.seconds
    if os.time() - (ChoreUsed[src].last or 0) < secs - 1 then return Fail('Slow down.') end
    if os.time() - (ChoreUsed[src][index] or 0) < 45 then return Fail('You\'ve just done this one - try another spot.') end
    ChoreUsed[src][index] = os.time()
    ChoreUsed[src].last = os.time()
    if s.kind == 'jail' then
        s.left = s.left - Config.Jail.choreReduces
    else
        s.left = s.left - 1
    end
    Dirty.sentences = true
    if s.left <= 0 then
        Release(src, s.kind == 'jail' and 'Sentence served' or 'Community service done')
        return { ok = true, done = true }
    end
    TriggerClientEvent(EV .. 'sentence', src, s, false)
    return { ok = true }
end)

-- Jail time counts down while online
CreateThread(function()
    while true do
        Wait(10000)
        for _, p in ipairs(GetPlayers()) do
            p = tonumber(p)
            local s = Sentences[Ident(p)]
            if s and s.kind == 'jail' then
                s.left = s.left - 10
                Dirty.sentences = true
                if s.left <= 0 then Release(p, 'Sentence served') else TriggerClientEvent(EV .. 'sentenceTick', p, s.left) end
            end
        end
    end
end)

RegisterNetEvent(EV .. 'joined', function()
    local src = source
    SetTimeout(5000, function() if Online(src) then SendSentence(src, true) end end)
end)

RegisterCommand('jailtime', function(src)
    if src == 0 then return end
    local s = Sentences[Ident(src)]
    if not s then return Notify(src, 'You aren\'t serving a sentence.') end
    if s.kind == 'jail' then
        Notify(src, ('%d:%02d left in jail. Do chores in the yard to cut it down.'):format(math.floor(s.left / 60), s.left % 60))
    else
        Notify(src, ('%d community service tasks left.'):format(s.left))
    end
end, false)

AddEventHandler('playerDropped', function() ChoreUsed[source] = nil end)

---------------------------------------------------------------------------
-- MDT (records, warrants, notes)
---------------------------------------------------------------------------
local function OnlineId(ident) return SrcFromIdent(ident) end

PoliceCallback('mdtSearch', function(src, query)
    query = tostring(query or ''):lower()
    local out = {}
    local id = tonumber(query)
    if id and Online(id) then
        local ident = Ident(id)
        Record(ident, Name(id))
        out[#out + 1] = { ident = ident, name = Name(id), online = id, summary = RecordSummary(ident) }
    end
    if #query >= 2 then
        for ident, r in pairs(Records) do
            if #out >= 25 then break end
            if (r.name or ''):lower():find(query, 1, true) and not (out[1] and out[1].ident == ident) then
                out[#out + 1] = { ident = ident, name = r.name, online = OnlineId(ident), summary = RecordSummary(ident) }
            end
        end
    end
    -- everyone online if nothing typed
    if query == '' then
        for _, p in ipairs(GetPlayers()) do
            p = tonumber(p)
            local ident = Ident(p)
            Record(ident, Name(p))
            out[#out + 1] = { ident = ident, name = Name(p), online = p, summary = RecordSummary(ident) }
        end
    end
    table.sort(out, function(a, b) return (a.name or '') < (b.name or '') end)
    return { ok = true, results = out }
end)

local function FullRecord(ident)
    local r = Records[ident]
    if not r then return nil end
    local online = OnlineId(ident)
    local lic = {}
    if online and Started(LICENCE) then
        local ok, list = pcall(function() return exports[LICENCE]:GetLicences(online) end)
        for k in pairs(ok and list or {}) do lic[#lic + 1] = k end
    end
    return { ok = true, ident = ident, name = r.name, online = online, fines = r.fines, arrests = r.arrests, warrants = r.warrants,
        notes = r.notes, dna = r.dna, prints = r.prints, licences = lic, sentence = Sentences[ident], admin = false }
end

PoliceCallback('mdtRecord', function(src, ident)
    local rec = FullRecord(ident)
    if not rec then return Fail('No record.') end
    rec.admin = IsAdmin(src)
    return rec
end)

PoliceCallback('mdtWarrant', function(src, ident, reason)
    local r = Records[ident]
    if not r then return Fail() end
    reason = CleanText(reason, 200)
    if #reason < 3 then return Fail('Give a reason.') end
    table.insert(r.warrants, 1, { id = NewCaseId('W'), date = Stamp(), officer = OfficerLabel(src), reason = reason, active = true })
    Dirty.records = true
    local online = OnlineId(ident)
    for _, p in ipairs(GetPlayers()) do
        p = tonumber(p)
        if IsPolice(p) and p ~= src then Notify(p, ('New warrant for %s: %s'):format(r.name, reason)) end
    end
    local rec = FullRecord(ident) rec.admin = IsAdmin(src)
    return rec
end)

PoliceCallback('mdtWarrantClear', function(src, ident, id)
    local r = Records[ident]
    if not r then return Fail() end
    for _, w in ipairs(r.warrants) do
        if w.id == id and w.active then w.active = false w.cleared = Stamp() .. ' by ' .. OfficerLabel(src) end
    end
    Dirty.records = true
    local rec = FullRecord(ident) rec.admin = IsAdmin(src)
    return rec
end)

PoliceCallback('mdtNote', function(src, ident, text)
    local r = Records[ident]
    if not r then return Fail() end
    text = CleanText(text, 300)
    if #text < 2 then return Fail() end
    table.insert(r.notes, 1, { date = Stamp(), officer = OfficerLabel(src), text = text })
    Dirty.records = true
    local rec = FullRecord(ident) rec.admin = IsAdmin(src)
    return rec
end)

PoliceCallback('mdtWaive', function(src, ident, id)
    if not IsAdmin(src) then return Fail('Staff only.') end
    local r = Records[ident]
    if not r then return Fail() end
    for _, f in ipairs(r.fines) do if f.id == id and not f.paid then f.paid, f.waived = true, Stamp() end end
    Dirty.records = true
    local rec = FullRecord(ident) rec.admin = true
    return rec
end)
