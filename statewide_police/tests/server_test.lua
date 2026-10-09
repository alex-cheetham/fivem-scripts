-- Server tests for the AI patrol (Phase 3: calls, CAD board, weighting, wk_wars2x ALPR).
-- Run from the resource folder:  cd tests && lua5.4 server_test.lua ..
local ROOT = arg[1]
dofile('stubs.lua')
local realTime = os.time
FAKE_NOW = realTime()
os.time = function(t) if t then return realTime(t) end return FAKE_NOW end
function Player(src) return { state = { duty = { key = Config.PoliceDepts[1], unit = '1-ADAM-' .. src } } } end
local function loadf(f)
    local src = io.open(ROOT .. '/' .. f):read('a'):gsub('`[^`]*`', '0')
    assert(load(src, '@' .. f))()
end
for _, f in ipairs({ 'config.lua', 'config_ai.lua', 'config_calls.lua', 'commands.lua', 'server/core.lua', 'server/restraint.lua', 'server/people.lua',
    'server/justice.lua', 'server/traffic.lua', 'server/evidence.lua', 'server/commands.lua', 'server/ai.lua', 'server/ai_deep.lua',
    'server/ai_places.lua', 'server/ai_people.lua', 'server/ai_units.lua', 'server/ai_calls.lua', 'server/ai_cad.lua' }) do loadf(f) end

local fails, passes = 0, 0
local function check(cond, msg) if cond then passes = passes + 1 else fails = fails + 1 print('FAIL: ' .. msg) end end

local reqId = 0
local function CB(src, name, ...)
    reqId = reqId + 1
    source = src
    NetEvents[EV .. 'cb'](reqId, name, ...)
    for i = #SENT, 1, -1 do
        local s = SENT[i]
        if s.name == EV .. 'cbr' and s.args[1] == reqId then return s.args[2] end
    end
end
local function Sent(name, src)
    for i = #SENT, 1, -1 do if SENT[i].name == name and (src == nil or SENT[i].src == src) then return SENT[i].args[1], i end end
end

local AI = Config.AI
local X = AIX

-- 1. every call has a unique key, a nature code and a priority
local seen = {}
for _, c in ipairs(AI.Callouts) do
    check(not seen[c.key], 'duplicate callout key ' .. c.key)
    seen[c.key] = true
    check(c.nature ~= nil, 'no nature code for ' .. c.key)
    check(c.prio ~= nil, 'no prio for ' .. c.key)
    for _, u in ipairs(c.units or {}) do check(AI.Units[u] ~= nil, c.key .. ' auto unit missing: ' .. u) end
    for k in pairs(AI.CalloutPlaces[c.key] and {} or {}) do end
    for _, pt in ipairs(AI.CalloutPlaces[c.key] or {}) do
        local ok = false
        for _, t in ipairs(AI.PlaceTypes) do if t.key == pt then ok = true end end
        check(ok, c.key .. ' uses unknown place type ' .. pt)
    end
end
print(('callouts: %d'):format(#AI.Callouts))
for _, d in ipairs(AI.Divisions) do for _, k in ipairs(d.callouts) do check(seen[k], 'division ' .. d.key .. ' lists unknown call ' .. k) end end
for _, o in ipairs(AI.OnViewExtra) do check(seen[o.key], 'on-view unknown ' .. o.key) end

-- 2. new people
local function many(profile, n, f)
    for i = 1, n do f(X.MakePersona(profile, i % 2 == 0 and 'f' or 'm')) end
end
for _, k in ipairs({ 'activeshooter', 'barricaded', 'highrisk', 'bankrobber', 'kidnapper', 'carjacker', 'stabber', 'gunman', 'escapee', 'arsonist',
    'cook', 'fraudster', 'vandal', 'prowler', 'stalker', 'driveoff', 'poacher', 'racer', 'wrongway', 'trucker', 'elderly', 'partygoer', 'host', 'dogowner' }) do
    check(X.PROFILES[k] and X.PROFILE_OK[k], 'profile missing ' .. k)
    many(k, 30, function(p) check(p and p.pid and p.name, 'persona ' .. k) end)
end
many('activeshooter', 50, function(p)
    check(p.weapon and ({ WEAPON_CARBINERIFLE = 1, WEAPON_ASSAULTRIFLE = 1, WEAPON_PUMPSHOTGUN = 1, WEAPON_PISTOL50 = 1 })[p.weapon], 'shooter gun ' .. tostring(p.weapon))
    check(p.fight > 0.5, 'shooter fights')
end)
many('barricaded', 30, function(p) check(p.hostage == true and p.nego == 20 and p.barricade == true, 'barricaded nego') end)
many('escapee', 30, function(p) check(p.warrant and p.warrant:find('Escape'), 'escapee warrant') check(p.hasId == false, 'escapee no id') end)
many('cook', 30, function(p) check(p.drugs.meth, 'cook meth') local has = false for _, it in ipairs(p.items) do if it.label:find('meth') then has = true end end check(has, 'cook carries meth') end)
many('trucker', 30, function(p)
    local lading
    for _, it in ipairs(p.items) do if it.label == 'Bill of lading' then lading = it end end
    check(lading and lading.legal == true, 'trucker lading is legal')
end)
many('elderly', 30, function(p) check(p.flee == 0 and p.fight == 0 and not p.warrant, 'elderly clean') end)
local guns = 0
many('cook', 200, function(p) if p.weapon then guns = guns + 1 end end)
check(guns > 50 and guns < 140, 'cook gunChance ~0.45 got ' .. guns)

-- 3. barricade lines exist and the nego prefix is used
for _, k in ipairs({ 'barricade_good', 'barricade_bad', 'barricade_release', 'barricade_snap', 'cad_update' }) do check(AI.Lines[k] and #AI.Lines[k] > 0, 'line ' .. k) end

-- 4. weighting: time / weather / area
source = 1
NetEvents[EV .. 'aiContext'](2, false, true)    -- 2am, dry, city
local cityNight = {}
for i = 1, 20000 do local c = X.PickCallout(1) cityNight[c.key] = (cityNight[c.key] or 0) + 1 end
check(not cityNight.poaching and not cityNight.livestock, 'no poaching / livestock in the city')
NetEvents[EV .. 'aiContext'](14, false, false)  -- 2pm, dry, county
local countyDay = {}
for i = 1, 20000 do local c = X.PickCallout(1) countyDay[c.key] = (countyDay[c.key] or 0) + 1 end
check((countyDay.livestock or 0) > 0, 'livestock in the county')
check((cityNight.loud_party or 0) > (countyDay.loud_party or 0) * 4, 'loud parties at night: ' .. tostring(cityNight.loud_party) .. ' vs ' .. tostring(countyDay.loud_party))
check((countyDay.bank_robbery or 0) > (cityNight.bank_robbery or 0), 'bank jobs by day')
NetEvents[EV .. 'aiContext'](14, true, false)
local rain = {}
for i = 1, 20000 do local c = X.PickCallout(1) rain[c.key] = (rain[c.key] or 0) + 1 end
check(rain.crash > countyDay.crash * 1.6, 'more crashes in rain ' .. rain.crash .. ' vs ' .. countyDay.crash)
NetEvents[EV .. 'aiContext'](99, 'x', 'y')      -- junk is cleaned
check(X.PickCallout(1) ~= nil, 'junk context')

-- 5. offer -> accept -> CAD
local st = CB(1, 'patrolToggle', true)
check(st and st.ok and st.on, 'patrol on')
local def
for _, c in ipairs(AI.Callouts) do if c.key == 'active_shooter' then def = c end end
local offer = X.Offer(1, def)
local o = Sent(EV .. 'aiOffer', 1)
check(o and o.incident and o.incident:match('^SW%d+%-%d%d%d%d$'), 'offer has incident number ' .. tostring(o and o.incident))
check(o.nature == def.nature and o.prio == 1, 'offer nature/prio')
local board = CB(1, 'cadBoard')
check(board.ok and #board.list == 1 and board.list[1].status == 'offered' and board.list[1].mine, 'board shows my offer')
PLAYERS = { 1, 2 }
local b2 = CB(2, 'cadBoard')
check(#b2.list == 0, 'other officers can\'t see my offer')
local acc = CB(1, 'calloutAccept', offer.id)
check(acc.ok and acc.callout.incident == o.incident and acc.callout.nature == def.nature and acc.callout.units[1] == 'swat', 'accept carries CAD info')
board = CB(1, 'cadBoard')
check(board.list[1].status == 'enroute' and board.busy, 'board en route, busy')
check(#CB(2, 'cadBoard').list == 1, 'others see it once assigned')
CB(1, 'cadOnScene')
check(CB(1, 'cadBoard').list[1].status == 'onscene', 'on scene')
FAKE_NOW = FAKE_NOW + 60
CB(1, 'calloutEnd', true)
board = CB(1, 'cadBoard')
check(board.list[1].status == 'closed' and board.list[1].disposition == 'Code 4', 'closed code 4')
-- declining puts it back in the queue
local offer2 = X.Offer(1, def)
CB(1, 'calloutDecline', offer2.id)
local pend
for _, b in ipairs(CB(2, 'cadBoard').list) do if b.status == 'pending' then pend = b end end
check(pend ~= nil, 'declined call goes back to pending for everyone')

-- 6. board thread: new calls, other units, self-assign
local ticks = 0
local loopStop = {}
Wait = function() ticks = ticks + 1 if ticks % 1 == 0 then FAKE_NOW = FAKE_NOW + 5 end if ticks > 600 then error(loopStop) end end
-- find and run the CAD board thread (the one that references BoardEvery)
local ran = false
for _, fn in ipairs(Threads) do
    local info = debug.getinfo(fn, 'S')
    if info.source == '@server/ai_cad.lua' then
        ticks = 0
        local ok, err = pcall(fn)
        check(not ok and err == loopStop, 'cad thread ran: ' .. tostring(err))
        ran = true
    end
end
check(ran, 'cad thread found')
board = CB(2, 'cadBoard')
local counts = {}
for _, b in ipairs(board.list) do counts[b.status] = (counts[b.status] or 0) + 1 end
print('board after ~50 min:', (function() local t = {} for k, v in pairs(counts) do t[#t + 1] = k .. '=' .. v end return table.concat(t, ' ') end)())
check(#board.list > 3, 'board has calls')
check((counts.closed or 0) + (counts.enroute or 0) + (counts.onscene or 0) > 0, 'other units take calls')
-- self-assign one that's pending
Wait = function() end
local target
for _, b in ipairs(board.list) do if b.status == 'pending' then target = b end end
if not target then
    -- make one
    X.Offer(2, def) local of = X.Patrol[2].offer CB(2, 'calloutDecline', of.id)
    for _, b in ipairs(CB(2, 'cadBoard').list) do if b.status == 'pending' then target = b end end
end
check(target ~= nil, 'a pending call to take')
CB(2, 'patrolToggle', true)
local take = CB(2, 'cadTake', target.id)
check(take and take.ok and take.callout and take.callout.incident == target.id, 'self-assign works: ' .. tostring(take and take.msg))
local again = CB(1, 'cadTake', target.id)
check(again and not again.ok, 'can\'t take a call someone else has')
local busy = CB(2, 'cadTake', target.id)
check(busy and not busy.ok, 'can\'t take two calls')

-- 7. ALPR
STARTED.wk_wars2x = true
Plates['STOLE1'] = { owner = 'A B', reg = 'Valid', insurance = 'Insured', stolen = true, contraband = {} }
SENT = {}
source = 1
NetEvents['wk:onPlateScanned']('front', 'STOLE1 ', 1)
local hit = Sent(EV .. 'alprHit', 1)
check(hit and hit.plate == 'STOLE1' and hit.hits[1] == 'REPORTED STOLEN', 'ALPR stolen hit')
local locked = false
for _, e in ipairs(EXPORT_CALLS) do if e.res == 'wk_wars2x' and e.fn == 'TogglePlateLock' and e.args[1] == 1 and e.args[2] == 'front' then locked = true end end
check(locked, 'ALPR locks the camera')
SENT = {}
NetEvents['wk:onPlateScanned']('front', 'STOLE1', 1)
check(Sent(EV .. 'alprHit', 1) == nil, 'ALPR cooldown')
-- clean plates do nothing (and don't fill plates.json)
local before = 0 for _ in pairs(Plates) do before = before + 1 end
math.randomseed(1)
for i = 1, 200 do NetEvents['wk:onPlateScanned']('rear', 'CLN' .. i, 1) end
local after = 0 for _ in pairs(Plates) do after = after + 1 end
check(after - before < 15, 'unknown plates only saved on a hit: ' .. (after - before))
-- a player's car is never flagged
GetVehiclePedIsIn = function(ped) return ped == 102 and 900 or 0 end
GetVehicleNumberPlateText = function(v) return v == 900 and 'PLAYR1' or '' end
Plates['PLAYR1'] = { stolen = true, reg = 'Valid', insurance = 'Insured' }
SENT = {}
NetEvents['wk:onPlateScanned']('front', 'PLAYR1', 1)
check(Sent(EV .. 'alprHit', 1) == nil, 'player cars not flagged')
-- lock runs the plate
SENT = {}
NetEvents['wk:onPlateLocked']('front', 'STOLE1', 1)
local run = Sent(EV .. 'alprRun', 1)
check(run and run.owner == 'A B' and run.hits[1] == 'REPORTED STOLEN', 'plate lock runs it')
-- not police: nothing
PLAYERS = { 2 }
SENT = {}
source = 1
NetEvents['wk:onPlateScanned']('front', 'STOLE1', 1)
check(Sent(EV .. 'alprHit') == nil, 'non-police ignored')

print(('%d passed, %d failed'):format(passes, fails))
local m = {}
for k in pairs(rawget(_G, 'MISSING') or {}) do m[#m + 1] = k end
table.sort(m)
print('stubbed natives: ' .. table.concat(m, ', '))
os.exit(fails == 0 and 0 or 1)
