RES = GetCurrentResourceName()
EV = 'statewide_police:'

---------------------------------------------------------------------------
-- Helpers used by every part of the script
---------------------------------------------------------------------------
function Notify(src, msg)
    if src == 0 then return print('[statewide_police] ' .. msg) end
    TriggerClientEvent(EV .. 'notify', src, msg)
end

function Fail(msg) return { ok = false, msg = msg } end
function Started(res) return GetResourceState(res) == 'started' end
function Online(src) src = tonumber(src) return src and src > 0 and GetPlayerName(src) ~= nil end
function Name(src) return GetPlayerName(src) or ('ID ' .. tostring(src)) end
function Pos(src) return GetEntityCoords(GetPlayerPed(src)) end
function Money(n)
    local s = tostring(math.floor((tonumber(n) or 0) + 0.5)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return Config.Currency .. s
end
function V3(t) return vector3((t.x or t[1]) + 0.0, (t.y or t[2]) + 0.0, (t.z or t[3]) + 0.0) end

function Ident(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return GetPlayerIdentifier(src, 0)
end

function SrcFromIdent(ident)
    for _, p in ipairs(GetPlayers()) do
        if Ident(tonumber(p)) == ident then return tonumber(p) end
    end
    return nil
end

function Near(a, b, dist)
    if not Online(a) or not Online(b) then return false end
    return #(Pos(a) - Pos(b)) <= dist
end

function IsAdmin(src) return src == 0 or IsPlayerAceAllowed(src, Config.AdminAce) end

-- On duty (duty-sync) with a police department?
function Duty(src)
    local st = Player(src).state.duty
    if type(st) ~= 'table' or not st.key then return nil end
    local key = tostring(st.key):upper()
    for _, k in ipairs(Config.PoliceDepts) do
        if k:upper() == key then return st end
    end
    return nil
end

function IsPolice(src) return Online(src) and (Duty(src) ~= nil or IsAdmin(src)) end

function OfficerLabel(src)
    local d = Duty(src)
    local unit = d and d.unit and d.unit ~= '' and (d.unit .. ' ') or ''
    local dept = d and d.key and (' (' .. tostring(d.key):upper() .. ')') or ''
    return unit .. Name(src) .. dept
end

function Stamp() return os.date('%d/%m/%Y %H:%M') end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
local Callbacks = {}
function RegisterCallback(name, fn) Callbacks[name] = fn end

RegisterNetEvent(EV .. 'cb', function(reqId, name, ...)
    local src = source
    local fn = Callbacks[name]
    local ok, res = false, nil
    if fn then ok, res = pcall(fn, src, ...) end
    if not ok then
        if fn then print(('[statewide_police] error in %s: %s'):format(name, tostring(res))) end
        res = Fail('Something went wrong, try again.')
    end
    TriggerClientEvent(EV .. 'cbr', src, reqId, res or { ok = true })
end)

-- Police-only callback
function PoliceCallback(name, fn)
    RegisterCallback(name, function(src, ...)
        if not IsPolice(src) then return Fail('Only on-duty police can do that (/onduty).') end
        return fn(src, ...)
    end)
end

-- Checks a target is a real player close enough to the officer
function CheckTarget(src, target, dist)
    target = tonumber(target)
    if not target or target == src or not Online(target) then return nil, Fail('Nobody there.') end
    if not Near(src, target, dist or 3.0) then return nil, Fail('Get closer to them.') end
    return target
end

-- Ask a player's client something and wait for the answer
local Asks, AskId = {}, 0
function AskClient(target, what, data, timeout)
    AskId = AskId + 1
    local id, p = AskId, promise.new()
    Asks[id] = { p = p, target = target }
    TriggerClientEvent(EV .. 'ask', target, id, what, data)
    SetTimeout(timeout or 4000, function() if Asks[id] then Asks[id] = nil p:resolve(nil) end end)
    return Citizen.Await(p)
end
RegisterNetEvent(EV .. 'answer', function(id, value)
    local a = Asks[id]
    if a and a.target == source then Asks[id] = nil a.p:resolve(value) end
end)

---------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------
function LoadJson(file, fallback)
    local raw = LoadResourceFile(RES, file)
    if not raw or raw == '' then return fallback end
    local ok, data = pcall(json.decode, raw)
    return (ok and type(data) == 'table') and data or fallback
end
function SaveJson(file, data) SaveResourceFile(RES, file, json.encode(data, { indent = true }), -1) end

Dirty = {}
Records = LoadJson('data/records.json', {})    -- [ident] = { name, fines, arrests, warrants, notes, dna, prints }
Sentences = LoadJson('data/sentences.json', {}) -- [ident] = { kind = 'jail'|'comserv', left = seconds|tasks, ... }
Plates = LoadJson('data/plates.json', {})      -- [plate] = generated registration record
Locker = LoadJson('data/evidence.json', {})    -- list of collected evidence
Points = LoadJson('data/points.json', {})      -- staff overrides of stations / jail / community service points

CreateThread(function()
    while true do
        Wait(30000)
        if Dirty.records then SaveJson('data/records.json', Records) Dirty.records = false end
        if Dirty.sentences then SaveJson('data/sentences.json', Sentences) Dirty.sentences = false end
        if Dirty.plates then SaveJson('data/plates.json', Plates) Dirty.plates = false end
        if Dirty.locker then SaveJson('data/evidence.json', Locker) Dirty.locker = false end
    end
end)
AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    SaveJson('data/records.json', Records)
    SaveJson('data/sentences.json', Sentences)
    SaveJson('data/plates.json', Plates)
    SaveJson('data/evidence.json', Locker)
end)

function Record(ident, name)
    if not ident then return nil end
    local r = Records[ident]
    if not r then
        r = { name = name or 'Unknown', fines = {}, arrests = {}, warrants = {}, notes = {}, dna = false, prints = false }
        Records[ident] = r
    end
    if name then r.name = name end
    r.fines, r.arrests, r.warrants, r.notes = r.fines or {}, r.arrests or {}, r.warrants or {}, r.notes or {}
    Dirty.records = true
    return r
end

function RecordOf(src) return Record(Ident(src), Name(src)) end

NextId = LoadJson('data/counter.json', { n = 1000 })
function NewCaseId(prefix)
    NextId.n = NextId.n + 1
    SaveJson('data/counter.json', NextId)
    return (prefix or '') .. NextId.n
end

---------------------------------------------------------------------------
-- Points (stations, jail, community service) - config defaults, staff can override
---------------------------------------------------------------------------
local function toT(v) return { x = v.x, y = v.y, z = v.z, w = v.w } end
function GetPoints()
    local p = {
        stations = {}, spawns = {}, chores = {}, comserv = {},
        release = Points.release or toT(Config.Jail.release),
    }
    for _, s in ipairs(Points.stations or Config.Stations) do
        p.stations[#p.stations + 1] = { id = s.id, label = s.label, pos = s.pos and toT(s.pos) or { x = s.x, y = s.y, z = s.z } }
    end
    for _, v in ipairs(Points.spawns or Config.Jail.spawns) do p.spawns[#p.spawns + 1] = toT(v) end
    for _, v in ipairs(Points.chores or Config.Jail.chores) do p.chores[#p.chores + 1] = toT(v) end
    for _, v in ipairs(Points.comserv or Config.ComServ.spots) do p.comserv[#p.comserv + 1] = toT(v) end
    return p
end

function NearStation(src)
    local pos = Pos(src)
    for _, s in ipairs(GetPoints().stations) do
        if #(pos - V3(s.pos)) <= Config.StationRadius then return s end
    end
    return nil
end

function BroadcastPoints(target) TriggerClientEvent(EV .. 'points', target or -1, GetPoints()) end

RegisterCallback('init', function(src)
    return { ok = true, police = IsPolice(src), admin = IsAdmin(src), points = GetPoints() }
end)

-- Tell a player whether they count as police whenever their duty changes
AddStateBagChangeHandler('duty', nil, function(bagName, _, _)
    local src = GetPlayerFromStateBagName(bagName)
    if src and src > 0 then
        SetTimeout(200, function()
            if Online(src) then TriggerClientEvent(EV .. 'police', src, IsPolice(src)) end
        end)
    end
end)
