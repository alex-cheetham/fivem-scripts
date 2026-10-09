-- Statewide PD: using real places in scenes - store counters, house doors and the inside of houses,
-- getaway cars at the kerb, and the knock / force-entry flow for wanted people at home.
local function Fwd(h) local r = math.rad(h or 0.0) return vector3(-math.sin(r), math.cos(r), 0.0) end
local function Right(h) local f = Fwd(h) return vector3(f.y, -f.x, 0.0) end
local function V(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

-- A walkable spot near pos (pavement / floor), falling back to pos itself
function FootNear(pos, radius, pavement)
    for _ = 1, 6 do
        local x, y = pos.x + math.random(-(radius or 3), radius or 3), pos.y + math.random(-(radius or 3), radius or 3)
        local ok, p = GetSafeCoordForPed(x, y, pos.z, pavement == true, pavement and 16 or 0)
        if ok and p and #(p - pos) < (radius or 3) + 6.0 and math.abs(p.z - pos.z) < 3.0 then return p end
    end
    return pos
end

-- Everything a scene needs to know about a place
function PlaceSpots(loc)
    if not loc then return nil end
    local base, h = V(loc), loc.w or 0.0
    local s = { base = base, heading = h, type = loc.type, label = loc.label, house = loc.house }
    if loc.counter then
        -- the place is the shopkeeper's spot behind the counter, facing the customers
        local f, r = Fwd(h), Right(h)
        s.counter = base
        s.front = base + f * 1.7
        s.aisle = base + f * 4.0 + r * (math.random() < 0.5 and -2.5 or 2.5)
    end
    -- the road outside (for getaway cars, and the doorstep)
    local ok, node, nh = GetClosestVehicleNodeWithHeading(base.x, base.y, base.z, 1, 3.0, 0)
    if ok and node and #(vector3(node.x, node.y, node.z) - base) < 120.0 then
        s.road, s.roadHeading = vector3(node.x, node.y, node.z), nh
        local side, kerb = false, nil
        pcall(function() side, kerb = GetPointOnRoadSide(node.x, node.y, node.z, -1) end)
        s.kerb = (side and kerb) and vector3(kerb.x, kerb.y, kerb.z) or s.road
        local dir = base - s.road
        local len = #dir
        s.outside = len > 1.0 and FootNear(s.road + dir / len * math.max(2.0, len - 6.0), 3, true) or FootNear(base, 6, true)
    else
        s.outside = FootNear(base, 8, true)
    end
    if loc.house then
        local hs = loc.house
        s.door = hs.doors and hs.doors[1] and V(hs.doors[1]) or base
        s.back = hs.doors and hs.doors[2] and V(hs.doors[2]) or nil
        s.yard = base
        s.inside = {}
        for _, p in ipairs(hs.inside or {}) do s.inside[#s.inside + 1] = V(p) end
        if not hs.teleports and #s.inside == 0 and s.door then
            -- no inside point saved: a few metres past the front door, away from the doorstep
            local dir = s.door - base
            local len = #dir
            if len > 0.5 then s.inside[1] = s.door + dir / len * 3.0 end
        end
        s.walkin = not hs.teleports and #s.inside > 0
    end
    return s
end

---------------------------------------------------------------------------
-- E at a door (knock / force entry) - WorldInteract checks these first
---------------------------------------------------------------------------
if type(WorldHooks) ~= 'table' then WorldHooks = {} end
local Doors = {}       -- active door scenes

local function DoorAt(pos)
    for _, d in ipairs(Doors) do
        if not d.done and #(pos - d.door) < 2.6 then return d end
    end
    return nil
end

table.insert(WorldHooks, function()
    local d = DoorAt(MyPos())
    if not d or (d.stage ~= 'closed' and d.stage ~= 'refused') then return false end
    CreateThread(function()
        if d.stage == 'closed' then d.knock(d) elseif d.stage == 'refused' then d.force(d) end
    end)
    return true
end)

CreateThread(function()
    while true do
        local wait = 1000
        local pos = MyPos()
        for _, d in ipairs(Doors) do
            if not d.done and #(pos - d.door) < 25.0 then
                wait = 0
                DrawMarker(1, d.door.x, d.door.y, d.door.z - 0.98, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 0.25, 59, 130, 246, 110, false, false, 2, false, nil, nil, false)
                if #(pos - d.door) < 3.5 then
                    local t = d.stage == 'closed' and '~b~[E]~s~ Knock and announce' or d.stage == 'refused' and '~r~[E]~s~ Force entry' or nil
                    if t then Text3D(d.door + vector3(0.0, 0.0, 0.3), t) end
                end
            end
        end
        Wait(wait)
    end
end)

local function Shout(text)
    SendNUIMessage({ action = 'aiSay', name = 'You', text = text, me = true })
end

-- Reveal a suspect who was waiting out of sight behind the door
local function Reveal(e, at)
    if not Control(e.ped, 600) then return end
    if at then SetEntityCoords(e.ped, at.x, at.y, at.z - 0.9, false, false, false, false) end
    FreezeEntityPosition(e.ped, false)
    SetEntityCollision(e.ped, true, true)
    SetEntityVisible(e.ped, true, false)
    SetEntityInvincible(e.ped, false)
    e.hidden = false
end

--[[ A wanted person at home.
  opts = { loc, model, profile, bind (planned pid), story, title, onSpawn(e), C (callout, optional) }
  Returns the door scene. The suspect is created when you get within 70m. ]]
function HouseSuspect(opts)
    local s = PlaceSpots(opts.loc)
    if not s then return nil end
    local d = { stage = 'closed', door = s.door or s.base, spots = s, opts = opts, done = false }
    Doors[#Doors + 1] = d

    local function Track(ped)
        if opts.C then opts.C.ents[#opts.C.ents + 1] = ped end
    end

    local function Spawn()
        if d.e or d.spawning then return d.e end
        d.spawning = true
        local at, hidden
        if s.walkin then
            at = s.inside[1]
        else
            -- a teleport house: they wait behind the door, out of sight
            at, hidden = s.yard, true
        end
        local ped = SpawnPed(opts.model or PickOne(AI.Peds), at, s.heading)
        if not ped then d.spawning = false return nil end
        Track(ped)
        local e = Persona(ped, 'suspect', opts.profile or 'wanted', nil, opts.story or 'none', opts.bind)
        if not e then Vanish(ped) d.spawning = false return nil end
        d.e = e
        d.spawning = false
        Hold(ped)
        e.status = 'free'
        e.callout = opts.C
        if opts.C then opts.C.people[#opts.C.people + 1] = e end
        if e.persona and (e.persona.weapon or e.persona.melee) then
            GiveWeaponToPed(ped, GetHashKey(e.persona.weapon or e.persona.melee), 60, false, false)
        end
        if hidden then
            e.hidden = true
            SetEntityVisible(ped, false, false)
            SetEntityCollision(ped, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
        else
            TaskStartScenarioInPlace(ped, PickOne({ 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_STAND_IMPATIENT' }), 0, true)
        end
        if opts.onSpawn then opts.onSpawn(e) end
        return e
    end

    local function Open(minutes)
        local h = s.house
        if not h then return true end
        local r = TriggerCallback('aiHouseOpen', h.id, minutes or 12)
        return r and r.ok
    end

    local function Inside(e, act)
        local ped = e.ped
        if act == 'surrender' or act == 'comply' then
            if e.hidden then Reveal(e, s.door) end
            Surrender(e, true)
            Notify('~g~They\'re giving up.~s~ Move in and cuff them.')
        elseif act == 'fight' then
            if e.hidden then Reveal(e, s.door) end
            Fight(e)
            RadioLine(Callsign() .. ': shots fired inside the residence!')
        elseif act == 'flee' then
            if e.hidden then Reveal(e, s.back or s.door) end
            FleeOnFoot(e)
            RadioLine(Callsign() .. ': suspect running from the house!')
        else
            -- hiding inside
            if e.hidden then
                -- teleport house: you find them in the hallway
                Reveal(e, s.door)
                local act2 = AIReact(e, 'cornered')
                if act2 == 'surrender' then Surrender(e) elseif act2 == 'fight' then Fight(e) else FleeOnFoot(e) end
            elseif Control(ped, 400) then
                local spot = s.inside[2] or s.inside[1]
                ClearPedTasks(ped)
                SetPedStealthMovement(ped, true, 'DEFAULT_ACTION')
                TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.2, 6000, 0.0, 0.5)
                SetTimeout(5000, function() if AIPeds[ped] == e and Control(ped, 300) then TaskStandStill(ped, -1) end end)
                e.status, e.hidAt = 'hiding', GetGameTimer()
                Notify('They\'re hiding somewhere inside. Search the house.')
            end
        end
    end

    d.knock = function()
        if d.stage ~= 'closed' then return end
        d.stage = 'knocking'
        Shout(PickOne({ 'Sheriff\'s office! Open the door!', 'Police! We have a warrant - open the door!', 'Sheriff\'s office, come to the door!' }))
        PlayAnim('place', 0, 1500)
        Wait(1600)
        local e = d.e or Spawn()
        if not e then d.stage = 'closed' return end
        Wait(math.random(2500, 5000))
        local act = AIReact(e, 'knock')
        if act == 'comply' then
            if s.walkin then
                Open(3)
                if Control(e.ped, 400) then ClearPedTasks(e.ped) TaskGoToCoordAnyMeans(e.ped, s.yard.x, s.yard.y, s.yard.z, 1.0, 0, false, 786603, 0.0) end
                local t = GetGameTimer() + 15000
                while AIPeds[e.ped] == e and Dist(e.ped, s.yard) > 2.0 and GetGameTimer() < t do Wait(300) end
            else
                Reveal(e, s.yard)
            end
            HoldOnFoot(e)
            Say(e, PickOne({ 'Alright, alright... what is this?', 'What do you want? It\'s late.', 'Okay! I\'m coming out.' }))
            Notify('They\'ve come to the door.')
            d.done = true
        elseif act == 'flee' then
            if s.walkin then
                Open(5)
                if s.back and Control(e.ped, 400) then
                    ClearPedTasks(e.ped)
                    TaskGoToCoordAnyMeans(e.ped, s.back.x, s.back.y, s.back.z, 3.0, 0, false, 786603, 0.0)
                    Wait(3500)
                end
            else
                Reveal(e, s.back or s.yard)
            end
            FleeOnFoot(e)
            Notify('~o~They\'re running out of the ' .. (s.back and 'back door' or 'house') .. '!')
            RadioLine(Callsign() .. ': suspect fleeing the residence on foot!')
            d.done = true
        elseif act == 'fight' then
            d.stage = 'refused'
            d.barricaded = true
            Notify('~r~"Get off my property!"~s~ They\'re armed and won\'t come out. Call backup / SWAT, then force entry.')
            RadioLine(Callsign() .. ': barricaded subject, believed armed. Requesting backup.')
            if not s.walkin then
                -- teleport house: they open the door shooting
                Wait(1500)
                Inside(e, 'fight')
                d.done = true
            end
        else
            d.stage = 'refused'
            Notify('No answer... but you can hear someone moving inside. ~r~[E]~s~ at the door to force entry.')
        end
    end

    d.force = function()
        if d.stage ~= 'refused' then return end
        d.stage = 'forcing'
        RadioLine(Callsign() .. ': forcing entry.')
        if not Action('Forcing the door', 4000, 'place') then d.stage = 'refused' return end
        if not Open(15) then d.stage = 'refused' return Notify('The door won\'t give - try again.') end
        PlaySoundFromCoord(-1, 'Door_Open_Limit', d.door.x, d.door.y, d.door.z, 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false, 20, false)
        Notify('~b~Door forced.~s~ Clear the house.')
        local e = d.e
        d.done = true
        if not e or AIPeds[e.ped] ~= e then return end
        if d.barricaded and not e.hidden then
            -- they wait for you inside
            CreateThread(function()
                local t = GetGameTimer() + 120000
                while AIPeds[e.ped] == e and e.status == 'free' and GetGameTimer() < t do
                    if Dist(e.ped, Me()) < 14.0 and HasEntityClearLosToEntity(e.ped, Me(), 17) then Fight(e) return end
                    Wait(300)
                end
            end)
            return
        end
        Wait(1500)
        Inside(e, AIReact(e, 'raid'))
    end

    -- spawn when you get close, close the house again when it's over
    CreateThread(function()
        local giveUp = GetGameTimer() + 1800000
        while not d.e and not d.done and GetGameTimer() < giveUp do
            Wait(1000)
            if #(MyPos() - d.door) < 70.0 then Spawn() end
        end
        while not d.cancelled and GetGameTimer() < giveUp do
            Wait(2000)
            local e = d.e
            if not e or AIPeds[e.ped] ~= e or not DoesEntityExist(e.ped) then break end
            local st = e.status
            if st == 'cuffed' or st == 'escorted' or st == 'seated' or st == 'dead' then break end
        end
        d.done = true
        for i, x in ipairs(Doors) do if x == d then table.remove(Doors, i) break end end
        if s.house then SetTimeout(120000, function() TriggerCallback('aiHouseClose', s.house.id) end) end
    end)
    return d
end

function CancelHouse(d)
    if not d then return end
    d.cancelled, d.done = true, true
    local e = d.e
    if e and e.hidden and DoesEntityExist(e.ped) then
        Untrack(e)
        SetEntityAsMissionEntity(e.ped, true, true)
        DeleteEntity(e.ped)
    end
end
