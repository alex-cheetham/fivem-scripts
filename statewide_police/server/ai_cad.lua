-- Statewide PD - dispatch (CAD): incident numbers, the county-wide calls board, self-assigning calls,
-- time / weather / area weighting, and wk_wars2x plate reader hits.
local AI = Config.AI
local X = AIX
local Chance, Pick, Clamp, Limited = X.Chance, X.Pick, X.Clamp, X.Limited
local CAD = AI.CAD or {}
local CTX = AI.Context or {}

---------------------------------------------------------------------------
-- Incident numbers
---------------------------------------------------------------------------
local seq = 0
local seqDay = os.date('%y%m%d')
local function Incident()
    local day = os.date('%y%m%d')
    if day ~= seqDay then seqDay, seq = day, 0 end
    seq = seq + 1
    return ('%s%s-%04d'):format(CAD.Prefix or 'SW', day, seq)
end
NewIncident = Incident

---------------------------------------------------------------------------
-- Where and when each officer is (sent by their client): hour, rain, city
---------------------------------------------------------------------------
local Ctx = {}
RegisterNetEvent(EV .. 'aiContext', function(hour, rain, city)
    local src = source
    if not IsPolice(src) then return end
    hour = math.floor(tonumber(hour) or 12)
    if hour < 0 or hour > 23 then hour = 12 end
    Ctx[src] = { hour = hour, rain = rain == true, city = city == true, t = os.time() }
end)
AddEventHandler('playerDropped', function() Ctx[source] = nil end)

local function IsNight(hour)
    local from, to = CTX.NightFrom or 21, CTX.NightTo or 5
    if from > to then return hour >= from or hour < to end
    return hour >= from and hour < to
end
CadIsNight = IsNight

-- Used by PickCallout in server/ai.lua
function CalloutWeightMod(src, c)
    local ctx = src and Ctx[src]
    if not ctx then return 1 end
    local m = 1
    if IsNight(ctx.hour) then m = m * (c.night or 1) else m = m * (c.day or 1) end
    if ctx.rain then m = m * (c.rain or 1) end
    if ctx.city then m = m * (c.city or 1) else m = m * (c.county or 1) end
    return m
end

---------------------------------------------------------------------------
-- The calls board
---------------------------------------------------------------------------
local Board = {}    -- list of { id, key, title, code, prio, nature, area, loc, created, status, unit, src, closeAt, takeAt, offer }

local function Find(id)
    for i, b in ipairs(Board) do if b.id == id then return b, i end end
    return nil
end

local function Trim()
    -- closed calls drop off after a few minutes; keep the board to BoardMax
    local now = os.time()
    for i = #Board, 1, -1 do
        local b = Board[i]
        if b.status == 'closed' and now - (b.closedAt or now) > 240 then table.remove(Board, i) end
    end
    -- oldest first: finished calls, then other units' calls, then unclaimed ones. Never an officer's own call.
    for _, want in ipairs({ 'closed', 'other', 'pending' }) do
        local i = 1
        while #Board > (CAD.BoardMax or 12) + 4 and i <= #Board do
            local b = Board[i]
            local match = not b.src and ((want == 'closed' and b.status == 'closed') or (want == 'other' and b.status ~= 'pending')
                or (want == 'pending' and b.status == 'pending'))
            if match then table.remove(Board, i) else i = i + 1 end
        end
    end
end

local function AreaFor(loc)
    if loc and loc.label then return loc.label end
    return Pick(CAD.Areas or { 'County' })
end

-- A call dispatch is offering to an officer goes on the board as theirs
function CadOffered(src, offer)
    offer.incident = offer.incident or Incident()
    local b = Find(offer.incident)
    if not b then
        local d = offer.def
        b = { id = offer.incident, key = d.key, title = d.title, code = d.code, prio = d.prio or (d.code == 3 and 1 or 2), nature = d.nature,
            area = AreaFor(offer.loc), loc = offer.loc, created = os.time() }
        table.insert(Board, b)
    end
    b.status, b.src, b.offer = 'offered', src, offer.id
    Trim()
end

-- Declined or ignored: it goes back into the queue for someone else
function CadReleased(offer)
    local b = offer and offer.incident and Find(offer.incident)
    if not b or b.status ~= 'offered' then return end
    b.status, b.src, b.offer = 'pending', nil, nil
    b.takeAt = os.time() + math.random((CAD.OtherUnitsTake or { 120, 420 })[1], (CAD.OtherUnitsTake or { 120, 420 })[2])
end

function CadAccepted(src, offer)
    local b = offer and offer.incident and Find(offer.incident)
    if not b then return end
    b.status, b.src, b.unit = 'enroute', src, OfficerLabel(src)
    b.assigned = os.time()
end

function CadClosed(src, callout, done)
    local b = callout and callout.incident and Find(callout.incident)
    if not b then return end
    b.status, b.closedAt = 'closed', os.time()
    b.disposition = done and 'Code 4' or 'Cancelled'
end

-- the officer's client says they've arrived
PoliceCallback('cadOnScene', function(src)
    local p = X.Patrol[src]
    local b = p and p.callout and p.callout.incident and Find(p.callout.incident)
    if b and b.src == src and b.status == 'enroute' then b.status = 'onscene' end
    return { ok = true }
end)

-- New calls appear on the board while anyone is on AI patrol; other (AI) units pick up what nobody takes
local function AnyonePatrolling()
    for src, p in pairs(X.Patrol) do if p.on and Online(src) then return src end end
    return nil
end

local function OtherUnit()
    local list = CAD.OtherUnits or { '2-LINCOLN-7' }
    return Pick(list)
end

CreateThread(function()
    if CAD.Board == false then return end
    local nextAt = os.time() + 20
    while true do
        Wait(5000)
        local now = os.time()
        local who = AnyonePatrolling()
        if who and now >= nextAt then
            nextAt = now + math.random((CAD.BoardEvery or { 45, 120 })[1], (CAD.BoardEvery or { 45, 120 })[2])
            local pending = 0
            for _, b in ipairs(Board) do if b.status == 'pending' then pending = pending + 1 end end
            if pending < math.ceil((CAD.BoardMax or 12) / 2) then
                local def = X.PickCallout(who)
                if def then
                    local loc
                    if PlaceFor and AI.CalloutPlaces[def.key] then
                        -- somewhere in the county (not necessarily near anyone)
                        local list = AIPlaces and AIPlaces() or {}
                        local want = {}
                        for _, k in ipairs(AI.CalloutPlaces[def.key]) do want[k] = true end
                        local options = {}
                        for _, pl in ipairs(list) do if want[pl.type] then options[#options + 1] = pl end end
                        if #options > 0 then loc = Pick(options) end
                    end
                    table.insert(Board, { id = Incident(), key = def.key, title = def.title, code = def.code, prio = def.prio or (def.code == 3 and 1 or 2),
                        nature = def.nature, area = AreaFor(loc), loc = loc, created = now, status = 'pending',
                        takeAt = now + math.random((CAD.OtherUnitsTake or { 120, 420 })[1], (CAD.OtherUnitsTake or { 120, 420 })[2]) })
                    Trim()
                end
            end
        end
        -- other units
        for _, b in ipairs(Board) do
            if b.status == 'pending' and b.takeAt and now >= b.takeAt then
                b.status, b.unit, b.assigned = 'enroute', OtherUnit(), now
                b.onsceneAt = now + math.random(60, 240)
                b.closeAt = now + math.random((CAD.OtherUnitsClear or { 300, 900 })[1], (CAD.OtherUnitsClear or { 300, 900 })[2])
            elseif not b.src and b.status == 'enroute' and b.onsceneAt and now >= b.onsceneAt then
                b.status = 'onscene'
            elseif not b.src and (b.status == 'onscene' or b.status == 'enroute') and b.closeAt and now >= b.closeAt then
                b.status, b.closedAt = 'closed', now
                b.disposition = Pick({ 'Code 4', 'Report taken', 'Arrest made', 'Gone on arrival', 'Citation issued', 'Referred' })
            end
        end
        Trim()
    end
end)

local function BoardView(src)
    local out = {}
    local now = os.time()
    for i = #Board, 1, -1 do
        local b = Board[i]
        -- calls offered to someone else are private until they take them
        if not (b.status == 'offered' and b.src ~= src) then
            out[#out + 1] = { id = b.id, title = b.title, code = b.code, prio = b.prio, nature = b.nature, area = b.area, status = b.status,
                unit = b.unit, mine = b.src == src, age = math.floor((now - b.created) / 60), disposition = b.disposition }
        end
    end
    table.sort(out, function(a, b)
        local ra = a.status == 'pending' and 0 or (a.status == 'closed' and 2 or 1)
        local rb = b.status == 'pending' and 0 or (b.status == 'closed' and 2 or 1)
        if ra ~= rb then return ra < rb end
        if a.prio ~= b.prio then return (a.prio or 3) < (b.prio or 3) end
        return a.id > b.id
    end)
    return out
end

PoliceCallback('cadBoard', function(src)
    local p = X.Patrol[src]
    return { ok = true, list = BoardView(src), busy = p and (p.busy or p.callout ~= nil) or false, on = p and p.on or false }
end)

-- Self-assign a pending call from the board
PoliceCallback('cadTake', function(src, id)
    if Limited(src, 'cadtake', 6) then return Fail('Slow down.') end
    local p = X.NewPatrol(src)
    if p.callout then return Fail('Finish your current call first (Code 4).') end
    if p.stopBusy then return Fail('Finish what you\'re doing first.') end
    local b = Find(tostring(id or ''))
    if not b or b.status ~= 'pending' then return Fail('Another unit has that call.') end
    local def = X.CalloutDef(b.key)
    if not def then return Fail('That call type is switched off.') end
    if p.offer then
        CadReleased(p.offer)
        TriggerClientEvent(EV .. 'aiOfferGone', src, p.offer.id)
        p.offer = nil
    end
    p.on = true
    -- a place far away is fine (you chose to drive there); no place = somewhere near you
    local loc = b.loc
    if loc and PlaceFor then
        local ped = GetPlayerPed(src)
        local d = ped ~= 0 and #(GetEntityCoords(ped) - vector3(loc.x, loc.y, loc.z)) or 0
        if d > 6000.0 then loc = PlaceFor(src, def.key) end
    end
    local offer = X.Offer(src, def, loc, b.id, true)
    local r = X.AcceptCallout(src, offer.id)
    if r and r.ok then
        X.Log(src, 'Self-assigned ' .. b.id)
    end
    return r
end)

---------------------------------------------------------------------------
-- wk_wars2x plate reader
---------------------------------------------------------------------------
local ALPR = AI.ALPR or {}
local Seen = {}    -- [src] = { [plate] = os.time() }

local function CleanPlate(p) return tostring(p or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8) end

-- a player's own car? (never flag those from made-up records)
local function PlayersCar(plate)
    if RecentDriver and RecentDriver(plate) then return true end
    for _, pl in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(pl)
        local veh = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
        if veh ~= 0 and CleanPlate(GetVehicleNumberPlateText(veh)) == plate then return true end
    end
    return false
end

local function Hits(plate)
    local out = {}
    local rec = Plates[plate]
    if rec then
        if rec.stolen then out[#out + 1] = 'REPORTED STOLEN' end
        if rec.ownerWarrant then out[#out + 1] = 'Registered owner has an active warrant' end
        if rec.reg and rec.reg ~= 'Valid' then out[#out + 1] = 'Registration: ' .. rec.reg end
        if rec.insurance and rec.insurance ~= 'Insured' then out[#out + 1] = 'No insurance on record' end
    end
    for _, c in pairs(Cases or {}) do
        if c.plate == plate and not c.solved then out[#out + 1] = ('BOLO - case %s (%s)'):format(c.id, c.title or 'investigation') end
    end
    return out, rec
end

local function Lock(src, cam)
    if GetResourceState(ALPR.Resource or 'wk_wars2x') ~= 'started' then return end
    pcall(function() exports[ALPR.Resource or 'wk_wars2x']:TogglePlateLock(src, cam, true, true) end)
end

RegisterNetEvent('wk:onPlateScanned', function(cam, plate, index)
    local src = source
    if ALPR.Enabled == false or not IsPolice(src) then return end
    plate = CleanPlate(plate)
    if plate == '' or Limited(src, 'alpr', 240) then return end
    Seen[src] = Seen[src] or {}
    local last = Seen[src][plate]
    if last and os.time() - last < (ALPR.Cooldown or 90) then return end
    Seen[src][plate] = os.time()
    if Config.CompanyPlates then
        local compact = plate:gsub('%s', '')
        for prefix in pairs(Config.CompanyPlates) do if compact:sub(1, #prefix) == prefix then return end end
    end
    if PlayersCar(plate) then return end
    local hits = Hits(plate)
    if #hits == 0 and not Plates[plate] and GeneratePlate and Chance(ALPR.RandomHit or 0.015) then
        -- an unknown car that turns out to have something on it
        local rec = GeneratePlate(plate)
        local roll = math.random()
        if roll < 0.35 then rec.stolen = true
        elseif roll < 0.6 then rec.ownerWarrant = true
        elseif roll < 0.8 then rec.insurance = 'No insurance'
        else rec.reg = 'Expired' end
        Dirty.plates = true
        hits = Hits(plate)
    end
    if #hits == 0 then return end
    Lock(src, cam)
    TriggerClientEvent(EV .. 'alprHit', src, { plate = plate, cam = cam, hits = hits })
end)

-- Locking a plate yourself runs it
RegisterNetEvent('wk:onPlateLocked', function(cam, plate, index)
    local src = source
    if ALPR.Enabled == false or ALPR.LockRuns == false or not IsPolice(src) then return end
    plate = CleanPlate(plate)
    if plate == '' or Limited(src, 'alprlock', 20) then return end
    if PlayersCar(plate) then
        return TriggerClientEvent(EV .. 'alprRun', src, { plate = plate, player = true })
    end
    local rec = GeneratePlate and GeneratePlate(plate)
    if not rec then return end
    local hits = Hits(plate)
    TriggerClientEvent(EV .. 'alprRun', src, { plate = plate, owner = rec.owner, reg = rec.reg, insurance = rec.insurance, hits = hits })
end)

AddEventHandler('playerDropped', function() Seen[source] = nil end)
