-- Statewide PD - Phase 3 calls: major incidents (active shooter, barricades, SWAT warrants, bank jobs, 11-99s),
-- violent crime, crimes in progress, traffic and community calls. Uses the building blocks in ai_callouts.lua.
local S = CalloutScenes
local K = CalloutKit
local Car, Person, Writhe, Wander, Approach, Comply, HandsUp = K.Car, K.Person, K.Writhe, K.Wander, K.Approach, K.Comply, K.HandsUp
local TrackMover, Resolved, Spots, Profile = K.TrackMover, K.Resolved, K.Spots, K.Profile

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Alive(e) return e and AIPeds[e.ped] == e and DoesEntityExist(e.ped) end

local function Arm(e, weapon, ammo, equip)
    if not e or not DoesEntityExist(e.ped) then return end
    local w = weapon or (e.persona and (e.persona.weapon or e.persona.melee)) or 'WEAPON_PISTOL'
    GiveWeaponToPed(e.ped, GetHashKey(w), ammo or 120, false, equip ~= false)
end

local function Scenario(e, list)
    if e and DoesEntityExist(e.ped) then TaskStartScenarioInPlace(e.ped, type(list) == 'table' and PickOne(list) or list, 0, true) end
end

-- Somewhere to stand at the place (or on the pavement near the call)
local function Spot(C, pick)
    local s = Spots(C)
    if s then
        if pick == 'front' and s.front then return s.front, s.heading end
        if pick == 'back' and s.back then return s.back, s.heading end
        if pick == 'door' and s.door then return s.door, s.heading end
        if pick == 'outside' and s.outside then return s.outside, s.heading end
        if pick == 'yard' and s.yard then return s.yard, s.heading end
        return (s.house and s.yard) or s.outside or FootNear(s.base, 4), s.heading
    end
    return FindFoot(C.pos), 0.0
end

local function Around(pos, r)
    return FindFoot(pos + vector3(math.random(-r, r) + 0.0, math.random(-r, r) + 0.0, 0.0))
end

-- People in the background (no persona): panicking, filming, standing around
local function Crowd(C, center, n, mode, models)
    local list = {}
    for i = 1, n do
        local ped = SpawnPed(PickOne(models or AI.Peds), Around(center, 14), math.random(0, 359) + 0.0)
        if ped then
            C.ents[#C.ents + 1] = ped
            SetBlockingOfNonTemporaryEvents(ped, mode ~= 'flee')
            if mode == 'flee' then
                TaskSmartFleeCoord(ped, center.x, center.y, center.z, 150.0, -1, false, false)
                SetPedKeepTask(ped, true)
            elseif mode == 'film' then
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 0, true)
            elseif mode == 'cower' then
                TaskCower(ped, -1)
            else
                TaskStartScenarioInPlace(ped, PickOne({ 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_STAND_IMPATIENT', 'WORLD_HUMAN_SMOKING' }), 0, true)
            end
            list[#list + 1] = ped
        end
    end
    return list
end

local function Body(C, pos, model)
    local ped = SpawnPed(model or PickOne(AI.Peds), pos, math.random(0, 359) + 0.0)
    if not ped then return nil end
    C.ents[#C.ents + 1] = ped
    SetEntityHealth(ped, 0)
    return ped
end

local function Prop(C, model, pos, heading)
    local hash = LoadModel(model)
    if not hash then return nil end
    local obj = CreateObject(hash, pos.x, pos.y, pos.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return nil end
    SetEntityHeading(obj, heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    C.ents[#C.ents + 1] = obj
    return obj
end

local function Fire(C, pos)
    C.fires = C.fires or {}
    C.fires[#C.fires + 1] = StartScriptFire(pos.x, pos.y, pos.z - 0.6, 25, false)
end

local function PutOut(C)
    for _, f in ipairs(C.fires or {}) do RemoveScriptFire(f) end
    C.fires = {}
    StopFireInRange(C.pos.x, C.pos.y, C.pos.z, 40.0)
end

-- A friendly deputy (not a suspect - on our side)
local function Deputy(C, pos, heading, veh, seat)
    local ped = SpawnPed(PickOne(AI.Units.backup.peds or { 's_m_y_sheriff_01' }), pos, heading, veh, seat)
    if not ped then return nil end
    C.ents[#C.ents + 1] = ped
    SetPedRelationshipGroupHash(ped, CopsGroup())
    SetPedArmour(ped, 100)
    GiveWeaponToPed(ped, GetHashKey('WEAPON_COMBATPISTOL'), 200, false, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if TagUnitEntity then pcall(TagUnitEntity, ped) end
    return ped
end

local function PatrolCar(C, model, pos, heading)
    local veh = Car(C, model or PickOne(AI.SheriffCars), pos, heading)
    if veh then
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, true)
        if TagUnitEntity then pcall(TagUnitEntity, veh) end
    end
    return veh
end

-- When you get close: they react (fight / run / give up), or do onComply
local function Engage(e, dist, onComply)
    if not Alive(e) or e.triggered or e.status ~= 'free' then return end
    if Dist(e.ped, Me()) > dist then return end
    e.triggered = true
    CreateThread(function()
        local act = AIReact(e, 'approach')
        if not ApplyReaction(e, act) then (onComply or Comply)(e) end
    end)
end

local function Surrenders(e) Surrender(e, false) end

local function Every(C, key, ms)
    if GetGameTimer() < (C[key] or 0) then return false end
    C[key] = GetGameTimer() + ms
    return true
end

local function ShootNear(e, pos, ms)
    if not Alive(e) or not Control(e.ped, 300) then return end
    TaskShootAtCoord(e.ped, pos.x + math.random(-6, 6), pos.y + math.random(-6, 6), pos.z + math.random(0, 3), ms or 1500,
        GetHashKey('FIRING_PATTERN_BURST_FIRE'))
end

local function KeepWrithing(e)
    if Alive(e) and e.status == 'free' and not IsEntityPlayingAnim(e.ped, 'combat@damage@writhe', 'writhe_loop', 3) then Writhe(e) end
end

local function TimeOnScene(C, ms) return C.arrived and GetGameTimer() - (C.arrivedAt or 0) > ms end

---------------------------------------------------------------------------
-- MAJOR INCIDENTS
---------------------------------------------------------------------------

-- Active shooter: a gunman shooting at people, victims down, everyone running
S.active_shooter = {
    setup = function(C)
        local pos = Spot(C, 'front')
        C.shooters = {}
        for i = 1, (math.random() < 0.3 and 2 or 1) do
            local s = Person(C, Around(pos, 6), 0.0, 'activeshooter', 'suspect', 'shooter')
            if s then Arm(s, nil, 400) SetPedArmour(s.ped, math.random(0, 1) * 100) C.shooters[#C.shooters + 1] = s end
        end
        for i = 1, math.random(2, 3) do
            local v = Person(C, Around(pos, 12), 0.0, 'victim', 'victim', 'shooting_victim')
            if v then Writhe(v) C.victims = C.victims or {} C.victims[#C.victims + 1] = v end
        end
        if math.random() < 0.6 then Body(C, Around(pos, 10)) end
        C.crowd = Crowd(C, pos, math.random(4, 7), 'flee')
        Crowd(C, pos + vector3(25.0, 20.0, 0.0), 2, 'cower')
    end,
    arrive = function(C)
        Notify('~r~ACTIVE SHOOTER.~s~ Move to the threat and stop it. Treat the wounded once it\'s safe. SWAT and EMS are coming.')
    end,
    tick = function(C)
        for _, s in ipairs(C.shooters or {}) do
            if Alive(s) and s.status == 'free' and not s.triggered then
                if Dist(s.ped, Me()) > 60.0 then
                    -- still shooting
                    if Every(s, 'shotAt', math.random(2500, 5000)) then
                        local tgt = C.crowd and C.crowd[math.random(1, #C.crowd)]
                        local at = (tgt and DoesEntityExist(tgt)) and GetEntityCoords(tgt) or C.pos
                        ShootNear(s, at, 1400)
                    end
                else
                    -- police here: most turn on you, some run and hide, a few give up
                    s.triggered = true
                    CreateThread(function()
                        local act = AIReact(s, 'approach')
                        if act == 'comply' or act == 'reach' then act = math.random() < 0.6 and 'fight' or 'surrender' end
                        ApplyReaction(s, act)
                    end)
                end
            end
        end
        for _, v in ipairs(C.victims or {}) do KeepWrithing(v) end
    end,
}

-- Barricaded subject: armed, inside / in the doorway, fires now and then. Negotiate (E within 25m).
S.barricaded = {
    setup = function(C)
        local s = Spots(C)
        local pos, h = Spot(C, 'door')
        local b = Person(C, pos, h or 0.0, 'barricaded', 'suspect', 'none')
        if not b then return end
        Arm(b, nil, 200)
        if s and s.walkin and s.inside[1] then
            SetEntityCoords(b.ped, s.inside[1].x, s.inside[1].y, s.inside[1].z, false, false, false, false)
        end
        TaskStandGuard(b.ped, pos.x, pos.y, pos.z, h or 0.0, 'WORLD_HUMAN_GUARD_STAND')
        C.subject = b
        local n = Person(C, Around(C.pos, 28), 0.0, 'witness', 'witness', 'witness')
        if n then Scenario(n, 'WORLD_HUMAN_STAND_MOBILE') end
    end,
    arrive = function(C)
        Notify('~r~Barricaded armed subject.~s~ Take cover and set a perimeter. Press ~INPUT_CONTEXT~ within 25m to negotiate - don\'t rush the door.')
        RadioLine(Callsign() .. ': on scene, setting up a perimeter. Requesting SWAT and a negotiator.')
    end,
    tick = function(C)
        local b = C.subject
        if not Alive(b) then return end
        if b.persona.hostage then
            -- shots from inside every so often while nobody is talking to them
            if Dist(b.ped, Me()) > 30.0 and Every(C, 'shots', math.random(18000, 32000)) then
                local p = GetEntityCoords(b.ped)
                ShootNear(b, p + vector3(0.0, 0.0, 15.0), 900)
                RadioLine(Callsign() .. ': shots fired from inside the residence!')
            end
            if Dist(b.ped, Me()) < 4.0 and not b.rushed then
                b.rushed = true
                CreateThread(function()
                    local act = AIReact(b, 'approach')
                    HostageOutcome(b, act == 'flee' and 'flee' or 'fight')
                end)
            end
        end
    end,
}

-- High-risk warrant: armed suspect at home, lookouts outside. SWAT meets you there.
S.swat_warrant = {
    setup = function(C)
        local s = Spots(C)
        if s and s.house and HouseSuspect then
            C.deferred = true
            C.door = HouseSuspect({ loc = C.loc, profile = 'highrisk', C = C, story = 'none' })
        else
            local x = Person(C, FindFoot(C.pos), 0.0, 'highrisk', 'suspect', 'none')
            if x then Arm(x, nil, 120, false) Scenario(x, { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_MOBILE' }) C.target = x end
        end
        C.guards = {}
        for i = 1, math.random(1, 2) do
            local g = Person(C, Around(C.pos, 8), 0.0, 'gang', 'suspect', 'none', { gang = true })
            if g then Arm(g, nil, 120, false) Scenario(g, { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRUG_DEALER_HARD', 'WORLD_HUMAN_HANG_OUT_STREET' }) C.guards[#C.guards + 1] = g end
        end
    end,
    arrive = function(C)
        Notify(C.door and 'Warrant address. Let SWAT stack up, then knock and announce at the ~b~front door~s~ (E) - or force entry.'
            or 'The suspect is outside. Contain them and make the arrest.')
    end,
    tick = function(C)
        for _, g in ipairs(C.guards or {}) do Engage(g, 40.0, Surrenders) end
        if C.target then Engage(C.target, 25.0, Surrenders) end
    end,
    resolved = function(C)
        if C.door and not C.door.e then return false end
        return Resolved(C)
    end,
}

-- Bank robbery: armed crew coming out to a getaway car, maybe a teller as a shield
S.bank_robbery = {
    setup = function(C)
        local s = Spots(C)
        local door = (s and s.base) or FindFoot(C.pos)
        local h = (s and s.heading) or 0.0
        C.crew = {}
        for i = 1, math.random(2, 3) do
            local r = Person(C, Around(door, 3), h, 'bankrobber', 'suspect', 'none', { model = PickOne({ 'g_m_m_chicold_01', 'g_m_y_mexgoon_03', 's_m_y_robber_01', 'mp_m_freemode_01' }) })
            if r then
                Arm(r, nil, 300)
                SetPedArmour(r.ped, 100)
                TaskStandGuard(r.ped, door.x, door.y, door.z, h, 'WORLD_HUMAN_GUARD_STAND')
                C.crew[#C.crew + 1] = r
            end
        end
        local t = Person(C, Around(door, 2), h, 'victim', 'victim', 'bank_teller', { model = PickOne({ 'a_f_y_business_01', 'a_m_y_business_01', 'a_f_y_business_02' }) })
        if t then TaskHandsUp(t.ped, -1, 0, -1, true) C.teller = t end
        local kerb = (s and s.kerb) or FindRoad(10.0, 40.0, door)
        if kerb then
            local car = Car(C, PickOne({ 'kuruma', 'baller2', 'granger', 'schafter2', 'sultan' }), kerb, (s and s.roadHeading) or h)
            if car then
                SetVehicleEngineOn(car, true, true, false)
                SetVehicleDoorsLocked(car, 1)
                C.getaway = car
                local d = Person(C, nil, nil, 'bankrobber', 'suspect', 'none', { veh = car, seat = -1 })
                if d then Arm(d, nil, 200, false) C.driver = d end
            end
        end
        Crowd(C, door + vector3(18.0, 12.0, 0.0), 3, 'cower')
        C.leaveAt = GetGameTimer() + math.random(70000, 140000)
    end,
    arrive = function(C) Notify('~r~Bank robbery.~s~ Armed crew at the doors. Take cover - they may run for the car or take a hostage.') end,
    tick = function(C)
        if C.taker then return K.HostageTick(C) end
        if C.mover then TrackMover(C, C.mover, 'Getaway vehicle') end
        if C.moving then return end
        local close = Dist(Me(), C.pos) < 80.0
        if not close and GetGameTimer() < (C.leaveAt or 0) then return end
        C.moving = true
        CreateThread(function()
            local lead = C.crew[1]
            -- the lead robber may grab the teller
            if close and lead and Alive(lead) and C.teller and Alive(C.teller) and math.random() < 0.3 then
                local res = TriggerCallback('aiTakeHostage', lead.pid)
                if res and res.ok then
                    if res.persona then lead.persona = res.persona end
                    lead.hostagePed, C.teller.status = C.teller, 'hostage'
                    K.HoldHostage(lead, C.teller)
                    C.taker = lead
                    Notify('~r~They\'ve taken the teller hostage!~s~ Stay back and negotiate (E within 25m).')
                    RadioLine(Callsign() .. ': suspects have taken a hostage at the bank!')
                end
            end
            -- everyone else runs for the car (or fights)
            local car = C.getaway
            local seat = 0
            for _, r in ipairs(C.crew) do
                if r ~= C.taker and Alive(r) and r.status == 'free' and Control(r.ped, 500) then
                    r.triggered = true
                    if car and DoesEntityExist(car) and seat <= 2 and math.random() < 0.8 then
                        ClearPedTasks(r.ped)
                        TaskEnterVehicle(r.ped, car, 12000, seat, 2.0, 1, 0)
                        r.veh, r.seat = car, seat
                        seat = seat + 1
                    else
                        Fight(r)
                    end
                end
            end
            local t = GetGameTimer() + 12000
            while GetGameTimer() < t do
                local allIn = true
                for _, r in ipairs(C.crew) do
                    if r.veh == car and Alive(r) and r.status == 'free' and not IsPedInVehicle(r.ped, car, false) then allIn = false end
                end
                if allIn then break end
                Wait(300)
            end
            for _, r in ipairs(C.crew) do
                if r.veh == car and Alive(r) and r.status == 'free' and not IsPedInVehicle(r.ped, car, false) then Fight(r) end
            end
            local d = C.driver
            if d and Alive(d) and d.status == 'free' and car and DoesEntityExist(car) then
                d.veh = car
                FleeInVehicle(d)
                C.mover = car
                RadioLine(Callsign() .. ': suspects leaving the bank in the getaway vehicle - I\'m in pursuit!')
            end
        end)
    end,
}

-- 11-99: a deputy down at a stop, suspects still shooting
S.officer_down = {
    setup = function(C)
        local car = PatrolCar(C, nil, C.pos, C.heading)
        if not car then return end
        local dpos = GetOffsetFromEntityInWorldCoords(car, -1.6, -1.0, 0.0)
        local dep = Deputy(C, dpos, C.heading)
        if dep then
            SetEntityHealth(dep, 140)
            if LoadDict('combat@damage@writhe') then TaskPlayAnim(dep, 'combat@damage@writhe', 'writhe_loop', 8.0, -8.0, -1, 1, 0.0, false, false, false) end
            C.deputy = dep
        end
        local spos = GetOffsetFromEntityInWorldCoords(car, 0.0, 22.0, 0.0)
        local sus = Car(C, nil, spos, C.heading + 180.0)
        C.shooters = {}
        for i = 1, math.random(2, 3) do
            local g = Person(C, FindFoot(spos + vector3(i * 1.5, 0.0, 0.0)), 0.0, Profile({ 'gang', 'armed', 'gang' }), 'suspect', 'none', { gang = true })
            if g then Arm(g, nil, 300) if sus then g.veh = sus end C.shooters[#C.shooters + 1] = g end
        end
    end,
    arrive = function(C)
        Notify('~r~11-99 - deputy down!~s~ Neutralise the threat, then get to the deputy.')
    end,
    tick = function(C)
        for _, g in ipairs(C.shooters or {}) do
            if Alive(g) and g.status == 'free' and not g.triggered then
                if Dist(g.ped, Me()) > 70.0 then
                    if Every(g, 'shotAt', math.random(2500, 4500)) and C.deputy and DoesEntityExist(C.deputy) then ShootNear(g, GetEntityCoords(C.deputy) + vector3(0.0, 0.0, 1.5), 1200) end
                else
                    g.triggered = true
                    CreateThread(function()
                        local act = AIReact(g, 'approach')
                        if act == 'comply' or act == 'reach' then act = math.random() < 0.55 and 'fight' or 'surrender' end
                        ApplyReaction(g, act)
                    end)
                end
            end
        end
        local dep = C.deputy
        if dep and DoesEntityExist(dep) and not C.dsaid and Dist(dep, Me()) < 4.0 then
            C.dsaid = true
            SendNUIMessage({ action = 'aiSay', name = 'Deputy', text = AI.Lines.story_deputy[math.random(1, #AI.Lines.story_deputy)] })
            Notify('Apply a tourniquet and keep the deputy talking until EMS get here.')
        end
    end,
}

---------------------------------------------------------------------------
-- VIOLENT CRIME
---------------------------------------------------------------------------

-- Drive-by: victims at the scene, the car is long gone
S.drive_by = {
    moving = true,
    setup = function(C)
        local pos = FindFoot(C.pos)
        for i = 1, math.random(1, 2) do
            local v = Person(C, Around(pos, 4), 0.0, 'victim', 'victim', 'drive_by')
            if v then Writhe(v) C.victims = C.victims or {} C.victims[#C.victims + 1] = v end
        end
        local w = Person(C, Around(pos, 10), 0.0, 'witness', 'witness', 'witness')
        if w then Scenario(w, 'WORLD_HUMAN_STAND_MOBILE') end
        local rpos, rh = FindRoad(140.0, 260.0, C.pos)
        if rpos then
            local veh = Car(C, PickOne({ 'buccaneer', 'chino', 'primo', 'emperor', 'manana', 'voodoo2', 'tornado' }), rpos, rh)
            if veh then
                local d = Person(C, nil, nil, 'gang', 'suspect', nil, { veh = veh, seat = -1, gang = true })
                if d then Wander(d, 20.0) C.driver = d end
                C.gunners = {}
                for seat = 0, math.random(0, 1) do
                    local g = Person(C, nil, nil, 'gang', 'suspect', nil, { veh = veh, seat = seat, gang = true })
                    if g then Arm(g, nil, 300, true) C.gunners[#C.gunners + 1] = g end
                end
                C.mover = veh
            end
        end
    end,
    arrive = function(C) Notify('Victims down. Get EMS rolling, get a description from the witness, then find the car.') end,
    tick = function(C)
        for _, v in ipairs(C.victims or {}) do KeepWrithing(v) end
        if C.mover and C.arrived then TrackMover(C, C.mover, 'Drive-by vehicle') end
        local d = C.driver
        if d and Alive(d) and d.status == 'free' and not d.triggered and C.mover and DoesEntityExist(C.mover) and Dist(C.mover, Me()) < 45.0 then
            d.triggered = true
            CreateThread(function()
                local act = AIReact(d, 'stop')
                if act ~= 'comply' then
                    FleeInVehicle(d)
                    -- the passengers shoot back out of the windows
                    for _, g in ipairs(C.gunners or {}) do
                        if Alive(g) and Control(g.ped, 300) then
                            SetPedRelationshipGroupHash(g.ped, SuspectGroup())
                            TaskDriveBy(g.ped, Me(), 0, 0.0, 0.0, 0.0, 60.0, 60, false, GetHashKey('FIRING_PATTERN_BURST_FIRE_DRIVEBY'))
                        end
                    end
                end
            end)
        end
    end,
}

-- Kidnapping: van driving off with the victim inside
S.kidnapping = {
    moving = true,
    setup = function(C)
        local w = Person(C, FindFoot(C.pos), 0.0, 'witness', 'witness', 'kidnap_witness')
        if w then Scenario(w, 'WORLD_HUMAN_STAND_MOBILE') end
        local rpos, rh = FindRoad(110.0, 220.0, C.pos)
        if not rpos then return end
        local van = Car(C, PickOne({ 'burrito3', 'speedo', 'youga', 'rumpo', 'pony' }), rpos, rh)
        if not van then return end
        SetVehicleColours(van, 111, 111)
        local d = Person(C, nil, nil, 'kidnapper', 'suspect', nil, { veh = van, seat = -1 })
        if d then Wander(d, 19.0) C.driver = d end
        local v = Person(C, nil, nil, 'victim', 'victim', 'kidnap_victim', { veh = van, seat = 1, model = PickOne({ 'a_f_y_business_01', 'a_f_y_hipster_02', 'a_f_y_eastsa_03' }) })
        if v then v.veh, v.status, C.victim = nil, 'hostage', v end
        C.mover, C.van = van, van
    end,
    tick = function(C)
        local d, v, van = C.driver, C.victim, C.van
        if C.mover then TrackMover(C, C.mover, 'Kidnap van') end
        if d and Alive(d) and d.status == 'free' and not d.triggered and van and DoesEntityExist(van) and Dist(van, Me()) < 40.0 then
            d.triggered = true
            CreateThread(function()
                local act = AIReact(d, 'stop')
                if act == 'fight' then Fight(d) elseif act == 'comply' or act == 'reach' then HoldInVehicle(d) else FleeInVehicle(d) end
            end)
        end
        -- once the van stops and the driver is dealt with, the victim gets out
        if v and Alive(v) and v.status == 'hostage' and van and DoesEntityExist(van) and GetEntitySpeed(van) < 1.0
            and (not d or not Alive(d) or (d.status ~= 'free' and d.status ~= 'pursuit')) and Dist(van, Me()) < 25.0 then
            v.status = 'free'
            CreateThread(function()
                if Control(v.ped, 500) then TaskLeaveVehicle(v.ped, van, 256) end
                Wait(2000)
                HoldOnFoot(v)
                Say(v, AI.Lines.story_kidnap_victim[math.random(1, #AI.Lines.story_kidnap_victim)])
                Notify('~g~Victim safe.~s~ Check them over and take their statement.')
            end)
        end
    end,
    resolved = function(C)
        if C.victim and Alive(C.victim) and C.victim.status == 'hostage' then return false end
        return Resolved(C)
    end,
}

-- Carjacking: victim at the scene, armed suspect in their car
S.carjacking = {
    moving = true,
    setup = function(C)
        local v = Person(C, FindFoot(C.pos), 0.0, 'victim', 'victim', 'carjacked')
        if v then Scenario(v, 'WORLD_HUMAN_STAND_MOBILE') end
        local rpos, rh = FindRoad(90.0, 180.0, C.pos)
        if not rpos then return end
        local veh = Car(C, PickOne(math.random() < 0.5 and AI.FastCars or AI.Cars), rpos, rh)
        if not veh then return end
        local s = Person(C, nil, nil, 'carjacker', 'suspect', nil, { veh = veh, seat = -1 })
        if s then Arm(s, nil, 60, false) Wander(s, 24.0, 1074528293) C.suspect = s end
        C.mover = veh
    end,
    tick = function(C)
        if C.mover then TrackMover(C, C.mover, 'Carjacked vehicle') end
        local s = C.suspect
        if s and Alive(s) and s.status == 'free' and not s.triggered and C.mover and DoesEntityExist(C.mover) and Dist(C.mover, Me()) < 40.0 then
            s.triggered = true
            CreateThread(function()
                local act = AIReact(s, 'stop')
                if act == 'fight' then Fight(s) elseif act == 'comply' then HoldInVehicle(s) else FleeInVehicle(s) end
            end)
        end
    end,
}

-- Stabbing: victim bleeding, suspect walking off with the knife
S.stabbing = {
    setup = function(C)
        local pos = Spot(C)
        local v = Person(C, pos, 0.0, 'victim', 'victim', 'stabbed')
        if v then Writhe(v) C.victim = v end
        local s = Person(C, Around(pos, 18), 0.0, 'stabber', 'suspect', 'none')
        if s then Arm(s, s.persona.melee or 'WEAPON_KNIFE', 1, true) Wander(s) C.suspect = s end
        Crowd(C, pos, 2, 'film')
    end,
    arrive = function(C) Notify('Victim stabbed. The suspect still has the knife - keep your distance and draw your weapon.') end,
    tick = function(C)
        KeepWrithing(C.victim)
        Engage(C.suspect, 22.0)
    end,
}

-- Man with a gun: waving it at people
S.man_with_gun = {
    setup = function(C)
        local pos = Spot(C)
        local g = Person(C, pos, 0.0, 'gunman', 'suspect', 'none')
        if not g then return end
        Arm(g, nil, 30, true)
        C.gunman = g
        Crowd(C, pos, math.random(2, 4), 'cower')
    end,
    arrive = function(C) Notify('~r~Man with a gun.~s~ Use cover, give clear commands. He hasn\'t fired - yet.') end,
    tick = function(C)
        local g = C.gunman
        if not Alive(g) then return end
        if g.status == 'free' and not g.triggered and Dist(g.ped, Me()) > 35.0 and Every(C, 'wave', 6000) and Control(g.ped, 300) then
            local p = GetEntityCoords(g.ped)
            TaskAimGunAtCoord(g.ped, p.x + math.random(-8, 8), p.y + math.random(-8, 8), p.z, 4000, false, false)
        end
        Engage(g, 35.0, Surrenders)
    end,
}

---------------------------------------------------------------------------
-- CRIMES IN PROGRESS
---------------------------------------------------------------------------

-- Burglary in progress: at the back, crowbar and loot, sometimes a lookout car
S.burglary_progress = {
    setup = function(C)
        local s = Spots(C)
        local pos = (s and (s.back or (s.walkin and s.inside[1]) or s.yard)) or FindFoot(C.pos)
        C.burglars = {}
        for i = 1, (math.random() < 0.4 and 2 or 1) do
            local b = Person(C, Around(pos, 2), 0.0, 'burglar', 'suspect', 'none')
            if b then Scenario(b, { 'PROP_HUMAN_BUM_BIN', 'WORLD_HUMAN_WELDING', 'PROP_HUMAN_PARKING_METER' }) C.burglars[#C.burglars + 1] = b end
        end
        Prop(C, 'prop_cs_cardbox_01', Around(pos, 2), 0.0)
        if math.random() < 0.45 then
            local rpos, rh = FindRoad(15.0, 60.0, pos)
            if rpos then
                local car = Car(C, nil, rpos, rh)
                if car then
                    SetVehicleEngineOn(car, true, true, false)
                    local d = Person(C, nil, nil, 'burglar', 'suspect', 'none', { veh = car, seat = -1 })
                    if d then C.lookout = d end
                end
            end
        end
    end,
    arrive = function(C) Notify('Burglary in progress. Approach quietly - check the back.') end,
    tick = function(C)
        for _, b in ipairs(C.burglars or {}) do Engage(b, 16.0) end
        local d = C.lookout
        if d and Alive(d) and d.status == 'free' and not d.triggered and Dist(d.ped, Me()) < 35.0 then
            d.triggered = true
            CreateThread(function() local act = AIReact(d, 'stop') if act == 'comply' then HoldInVehicle(d) else FleeInVehicle(d) end end)
        end
    end,
}

-- Escaped prisoner in orange, on foot
S.escaped_prisoner = {
    moving = true,
    setup = function(C)
        local e = Person(C, FindFoot(C.pos), 0.0, 'escapee', 'suspect', 'escapee', { model = 's_m_y_prisoner_01' })
        if e then
            Wander(e)
            SetPedMoveRateOverride(e.ped, 1.1)
            C.escapee, C.mover = e, e.ped
        end
    end,
    tick = function(C)
        local e = C.escapee
        if e and Alive(e) and e.status == 'free' then TrackMover(C, C.mover, 'Escaped prisoner') end
        Engage(e, 22.0)
    end,
}

-- Large fight at a bar
S.bar_brawl = {
    setup = function(C)
        local pos = Spot(C, 'outside')
        C.fighters = {}
        local n = math.random(2, 3)
        for i = 1, n do
            local a = Person(C, Around(pos, 4), 0.0, Profile({ 'drunk', 'violent', 'drunk' }), 'suspect', 'fight')
            local b = Person(C, Around(pos, 4), 0.0, Profile({ 'drunk', 'violent', 'public' }), 'suspect', 'fight')
            if a and b then
                for _, x in ipairs({ a, b }) do
                    SetPedMaxHealth(x.ped, 400)
                    SetEntityHealth(x.ped, 400)
                    SetPedFleeAttributes(x.ped, 0, false)
                    C.fighters[#C.fighters + 1] = x
                end
                TaskCombatPed(a.ped, b.ped, 0, 16)
                TaskCombatPed(b.ped, a.ped, 0, 16)
            end
        end
        local staff = Person(C, Around(pos, 8), 0.0, 'witness', 'witness', 'bar_staff', { model = PickOne({ 's_m_y_barman_01', 's_f_y_bartender_01' }) })
        if staff then Scenario(staff, 'WORLD_HUMAN_STAND_IMPATIENT') end
        Crowd(C, pos, 3, 'film')
    end,
    arrive = function(C) Notify('Large fight. Wait for backup if you can - then break it up and detain the main aggressors.') end,
    tick = function(C)
        if not C.broken and Dist(Me(), C.pos) < 28.0 then
            C.broken = true
            for _, x in ipairs(C.fighters or {}) do
                if Alive(x) and Control(x.ped, 300) then ClearPedTasks(x.ped) end
            end
            Wait(300)
            for _, x in ipairs(C.fighters or {}) do Approach(x, 99.0, Comply) end
        end
    end,
}

-- Arson: a burning car and the person who lit it watching
S.arson = {
    setup = function(C)
        local pos = Spot(C)
        local veh = Car(C, nil, pos, C.heading)
        if veh then
            SetVehicleEngineHealth(veh, -900.0)
            SetVehicleDoorsLocked(veh, 2)
            StartEntityFire(veh)
            C.burning = veh
        end
        Fire(C, pos + vector3(1.5, 1.5, 0.0))
        local a = Person(C, Around(pos, 28), 0.0, 'arsonist', 'suspect', 'none')
        if a then
            GiveWeaponToPed(a.ped, GetHashKey('WEAPON_PETROLCAN'), 1000, false, true)
            TaskTurnPedToFaceCoord(a.ped, pos.x, pos.y, pos.z, -1)
            C.suspect = a
        end
        local w = Person(C, Around(pos, 20), 0.0, 'witness', 'witness', 'arson_witness')
        if w then Scenario(w, 'WORLD_HUMAN_STAND_MOBILE') end
        C.outAt = GetGameTimer() + 240000
    end,
    arrive = function(C) Notify('Stay back from the fire. Find the person who started it - they may still be watching.') end,
    tick = function(C)
        Engage(C.suspect, 20.0)
        if C.fires and #C.fires > 0 and GetGameTimer() > C.outAt then
            PutOut(C)
            RadioLine('Fire: fire is out, we\'re clear. Scene is yours.')
        end
    end,
    cleanup = PutOut,
}

-- Drug lab in a trailer / house: chemicals, armed cooks
S.drug_lab = {
    setup = function(C)
        local pos = Spot(C, 'yard')
        Prop(C, 'prop_barrel_02a', Around(pos, 3), 0.0)
        Prop(C, 'prop_gascyl_01a', Around(pos, 3), 0.0)
        Prop(C, 'prop_cs_cardbox_01', Around(pos, 3), 0.0)
        C.cooks = {}
        for i = 1, math.random(1, 2) do
            local c = Person(C, Around(pos, 4), 0.0, 'cook', 'suspect', 'none', { model = PickOne({ 'a_m_y_methhead_01', 'a_m_m_rurmeth_01', 'a_f_y_rurmeth_01' }) })
            if c then Scenario(c, { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRUG_DEALER', 'WORLD_HUMAN_STAND_IMPATIENT' }) C.cooks[#C.cooks + 1] = c end
        end
    end,
    arrive = function(C) Notify('Strong chemical smell. Don\'t smoke, don\'t switch anything on. Detain the cooks, then request a hazmat team (tow) and SWAT if armed.') end,
    tick = function(C) for _, c in ipairs(C.cooks or {}) do Engage(c, 22.0) end end,
}

-- Card fraud at the counter
S.fraud = {
    setup = function(C)
        local s = Spots(C)
        local pos = (s and s.front) or FindFoot(C.pos)
        local f = Person(C, pos, (s and (s.heading + 180.0) % 360.0) or 0.0, 'fraudster', 'suspect', 'fraudster')
        if f then Scenario(f, 'WORLD_HUMAN_STAND_IMPATIENT') C.suspect = f end
        local clerk = Person(C, (s and s.counter) or Around(pos, 3), (s and s.heading) or 0.0, 'witness', 'witness', 'fraud_clerk', { model = PickOne({ 'mp_m_shopkeep_01', 's_f_y_shop_low' }) })
        if clerk then Scenario(clerk, 'WORLD_HUMAN_STAND_IMPATIENT') end
    end,
    tick = function(C) Engage(C.suspect, 12.0) end,
}

-- Vandalism: tagging a wall
S.vandalism = {
    setup = function(C)
        local pos = Spot(C)
        local v = Person(C, pos, 0.0, 'vandal', 'suspect', 'vandal', { model = PickOne({ 'a_m_y_skater_01', 'a_m_y_stbla_02', 'a_m_y_genstreet_01', 'a_f_y_skater_01' }) })
        if v then
            if LoadDict('switch@franklin@lamar_tagging_wall') then
                TaskPlayAnim(v.ped, 'switch@franklin@lamar_tagging_wall', 'lamar_tagging_wall_loop_lamar', 8.0, -8.0, -1, 1, 0.0, false, false, false)
            else
                Scenario(v, 'WORLD_HUMAN_HAMMERING')
            end
            C.suspect = v
        end
        if math.random() < 0.5 then
            local l = Person(C, Around(pos, 10), 0.0, 'vandal', 'suspect', 'vandal')
            if l then Scenario(l, 'WORLD_HUMAN_SMOKING') C.lookout = l end
        end
    end,
    tick = function(C)
        Engage(C.suspect, 15.0)
        Engage(C.lookout, 22.0)
    end,
}

-- Prowler at the windows
S.prowler = {
    setup = function(C)
        local s = Spots(C)
        local pos = (s and (s.back or s.yard)) or FindFoot(C.pos)
        local p = Person(C, Around(pos, 3), 0.0, 'prowler', 'suspect', 'prowler')
        if p then
            SetPedStealthMovement(p.ped, true, 'DEFAULT_ACTION')
            TaskWanderInArea(p.ped, pos.x, pos.y, pos.z, 8.0, 2.0, 3.0)
            C.suspect = p
        end
        local h = Person(C, (s and s.door) or Around(pos, 6), 0.0, 'witness', 'witness', 'homeowner')
        if h then Scenario(h, 'WORLD_HUMAN_STAND_IMPATIENT') end
    end,
    tick = function(C) Engage(C.suspect, 16.0) end,
}

-- Restraining order: ex outside the house, getting angrier
S.restraining_order = {
    setup = function(C)
        local pos = Spot(C, 'door')
        local v = Person(C, pos, 0.0, 'victim', 'victim', 'ro_victim')
        local x = Person(C, Around(pos, 4), 0.0, 'stalker', 'suspect', 'stalker')
        if v and x then
            TaskTurnPedToFaceEntity(v.ped, x.ped, -1)
            TaskTurnPedToFaceEntity(x.ped, v.ped, -1)
            C.victim, C.suspect = v, x
        end
    end,
    arrive = function(C) Notify('Check the order on the MDT (run them), separate them, and arrest for the violation if it\'s valid.') end,
    tick = K.DomesticTick,
}

-- Gas drive-off
S.gas_driveoff = {
    moving = true,
    setup = function(C)
        local clerk = Person(C, Spot(C), 0.0, 'witness', 'witness', 'driveoff_clerk', { model = PickOne({ 'mp_m_shopkeep_01', 's_f_y_shop_low', 's_m_m_autoshop_01' }) })
        if clerk then Scenario(clerk, 'WORLD_HUMAN_STAND_IMPATIENT') end
        local rpos, rh = FindRoad(120.0, 240.0, C.pos)
        if not rpos then return end
        local veh = Car(C, nil, rpos, rh)
        if not veh then return end
        local d = Person(C, nil, nil, 'driveoff', 'suspect', nil, { veh = veh, seat = -1 })
        if d then Wander(d, 18.0) end
        C.mover = veh
    end,
    tick = function(C) if C.arrived and C.mover then TrackMover(C, C.mover, 'Drive-off vehicle') end end,
}

-- Poacher with a rifle and a spotlight
S.poaching = {
    setup = function(C)
        local pos = FindFoot(C.pos)
        local p = Person(C, pos, 0.0, 'poacher', 'suspect', 'poacher', { model = PickOne({ 'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02', 'csb_cletus', 'a_m_m_farmer_01' }) })
        if p then Arm(p, nil, 30, true) Scenario(p, 'WORLD_HUMAN_SMOKING') C.suspect = p end
        local deer = SpawnPed('a_c_deer', Around(pos, 6), 0.0)
        if deer then C.ents[#C.ents + 1] = deer SetEntityHealth(deer, 0) end
        local rpos, rh = FindRoad(15.0, 60.0, pos)
        if rpos then
            local truck = Car(C, PickOne({ 'sadler', 'bison', 'rebel', 'bobcatxl' }), rpos, rh)
            if truck then SetVehicleLights(truck, 1) if p then p.veh = truck end end
        end
    end,
    arrive = function(C) Notify('Armed subject - probably a hunter, but treat the rifle as a threat. Make them put it down.') end,
    tick = function(C) Engage(C.suspect, 30.0, Surrenders) end,
}

---------------------------------------------------------------------------
-- TRAFFIC
---------------------------------------------------------------------------

-- Two cars racing
S.street_race = {
    moving = true,
    setup = function(C)
        local a = Car(C, PickOne(AI.FastCars), C.pos, C.heading)
        if not a then return end
        local b = Car(C, PickOne(AI.FastCars), GetOffsetFromEntityInWorldCoords(a, 3.5, -6.0, 0.0), C.heading)
        local d1 = Person(C, nil, nil, 'racer', 'suspect', nil, { veh = a, seat = -1 })
        if d1 then Wander(d1, 45.0, 1074528293) end
        if b then
            local d2 = Person(C, nil, nil, 'racer', 'suspect', nil, { veh = b, seat = -1 })
            if d2 then Wander(d2, 45.0, 1074528293) end
        end
        C.mover = a
    end,
    arrive = function(C) Notify('Pick one and light them up (' .. AI.Keys.stop .. '). Call for a second unit for the other car.') end,
    tick = function(C) TrackMover(C, C.mover, 'Street racers') end,
}

-- Wrong-way driver
S.wrong_way = {
    moving = true,
    setup = function(C)
        local veh = Car(C, nil, C.pos, (C.heading + 180.0) % 360.0)
        if not veh then return end
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
        local d = Person(C, nil, nil, 'wrongway', 'suspect', nil, { veh = veh, seat = -1 })
        if d then
            SetDriverAbility(d.ped, 0.2)
            local ahead = GetOffsetFromEntityInWorldCoords(veh, 0.0, 900.0, 0.0)
            TaskVehicleDriveToCoordLongrange(d.ped, veh, ahead.x, ahead.y, ahead.z, 22.0, 1074528293, 20.0)
            SetPedKeepTask(d.ped, true)
        end
        C.mover, C.driver = veh, d
    end,
    arrive = function(C) Notify('Get ahead of them with lights on and stop them (' .. AI.Keys.stop .. '). Watch for oncoming traffic.') end,
    tick = function(C) TrackMover(C, C.mover, 'Wrong-way driver') end,
}

-- Unsafe truck
S.truck_inspection = {
    moving = true,
    setup = function(C)
        local truck = Car(C, PickOne({ 'mule', 'mule3', 'pounder', 'benson', 'boxville2', 'biff' }), C.pos, C.heading)
        if not truck then return end
        local d = Person(C, nil, nil, 'trucker', 'suspect', 'trucker', { veh = truck, seat = -1, model = PickOne({ 's_m_m_trucker_01', 'a_m_m_farmer_01', 'a_m_m_hillbilly_01' }) })
        if d then Wander(d, 15.0) C.driver = d end
        C.mover = truck
    end,
    arrive = function(C) Notify('Pull the truck over (' .. AI.Keys.stop .. '). Check the driver\'s licence, the log book and the load (search the vehicle).') end,
    tick = function(C)
        TrackMover(C, C.mover, 'Commercial vehicle')
        local d = C.driver
        if d and Alive(d) and d.status == 'free' and Every(C, 'sway', math.random(7000, 12000)) and Control(d.ped, 300) and IsPedInVehicle(d.ped, C.mover, false) then
            TaskVehicleTempAction(d.ped, C.mover, math.random(7, 8), 500)
            SetTimeout(1000, function() if d.status == 'free' then Wander(d, 15.0) end end)
        end
    end,
}

-- Pursuit coming your way: another agency's car chasing a stolen vehicle
S.assist_pursuit = {
    moving = true,
    spawnAt = 320.0,
    setup = function(C)
        local veh = Car(C, PickOne(AI.FastCars), C.pos, C.heading)
        if not veh then return end
        local s = Person(C, nil, nil, 'stolen', 'suspect', nil, { veh = veh, seat = -1 })
        if s then Wander(s, 38.0, 1074528293) C.suspect = s end
        local cop = PatrolCar(C, PickOne({ 'police', 'police2', 'police3' }), GetOffsetFromEntityInWorldCoords(veh, 0.0, -18.0, 0.0), C.heading)
        if cop and s then
            SetVehicleHasMutedSirens(cop, false)
            local dep = Deputy(C, nil, nil, cop, -1)
            if dep then
                SetDriverAbility(dep, 1.0)
                TaskVehicleChase(dep, s.ped)
                SetTaskVehicleChaseBehaviorFlag(dep, 1, true)
                SetPedKeepTask(dep, true)
            end
        end
        C.mover = veh
    end,
    tick = function(C)
        local s = C.suspect
        if s and Alive(s) and s.status == 'free' then
            TrackMover(C, C.mover, 'Pursuit')
            if not s.triggered and C.mover and DoesEntityExist(C.mover) and Dist(C.mover, Me()) < 180.0 then
                s.triggered = true
                CreateThread(function() FleeInVehicle(s) end)
                RadioLine('LSPD: county units, we\'re in pursuit heading your way - taking you as primary!')
            end
        end
    end,
}

-- Someone walking in the lanes of the highway
S.ped_on_freeway = {
    moving = true,
    setup = function(C)
        local p = Person(C, C.pos, C.heading, Profile({ 'drunk', 'drugged', 'missing', 'drunk' }), 'suspect', 'none')
        if not p then return end
        local ahead = C.pos + vector3(math.sin(-math.rad(C.heading)) * 200.0, math.cos(-math.rad(C.heading)) * 200.0, 0.0)
        TaskGoStraightToCoord(p.ped, ahead.x, ahead.y, ahead.z, 1.0, -1, C.heading, 0.5)
        C.person, C.mover = p, p.ped
    end,
    arrive = function(C) Notify('Lights on, slow the traffic behind you, and get them off the road.') end,
    tick = function(C)
        local p = C.person
        if p and Alive(p) and p.status == 'free' then TrackMover(C, C.mover, 'Pedestrian') end
        Engage(p, 12.0)
    end,
}

-- Cattle on the road
S.livestock = {
    setup = function(C)
        C.cows = {}
        for i = 1, math.random(2, 4) do
            local cow = SpawnPed('a_c_cow', C.pos + vector3(math.random(-6, 6) + 0.0, math.random(-6, 6) + 0.0, 0.0), math.random(0, 359) + 0.0)
            if cow then
                C.ents[#C.ents + 1] = cow
                SetBlockingOfNonTemporaryEvents(cow, true)
                TaskWanderInArea(cow, C.pos.x, C.pos.y, C.pos.z, 8.0, 3.0, 5.0)
                C.cows[#C.cows + 1] = cow
            end
        end
        local f = Person(C, FindFoot(C.pos + vector3(12.0, 8.0, 0.0)), 0.0, 'witness', 'witness', 'farmer', { model = PickOne({ 'a_m_m_farmer_01', 'a_m_m_hillbilly_01' }) })
        if f then Scenario(f, 'WORLD_HUMAN_STAND_IMPATIENT') C.farmer = f end
    end,
    arrive = function(C) Notify('Park across the lane with your lights on, then walk the cattle off the road (stand next to them).') end,
    tick = function(C)
        for _, cow in ipairs(C.cows or {}) do
            if DoesEntityExist(cow) and not C['moved' .. cow] and Dist(cow, Me()) < 6.0 then
                C['moved' .. cow] = true
                local away = GetOffsetFromEntityInWorldCoords(Me(), math.random(-20, 20) + 0.0, 25.0, 0.0)
                local ok, side = GetSafeCoordForPed(away.x, away.y, away.z, false, 0)
                local to = ok and side or away
                TaskGoStraightToCoord(cow, to.x, to.y, to.z, 1.0, -1, 0.0, 0.5)
            end
        end
    end,
    resolved = function(C)
        if not C.arrived then return false end
        for _, cow in ipairs(C.cows or {}) do
            if DoesEntityExist(cow) and not IsPedDeadOrDying(cow, true) and not C['moved' .. cow] then return TimeOnScene(C, 240000) end
        end
        return TimeOnScene(C, 20000)
    end,
}

---------------------------------------------------------------------------
-- COMMUNITY
---------------------------------------------------------------------------

-- Welfare check: fine, fallen, or passed away
S.welfare_check = {
    setup = function(C)
        local pos = Spot(C, 'door')
        local roll = math.random()
        local model = PickOne({ 'a_m_o_genstreet_01', 'a_f_o_genstreet_01', 'a_m_o_soucent_01', 'a_f_o_soucent_02', 'a_m_o_salton_01' })
        if roll < 0.2 then
            Body(C, pos, model)
            C.outcome = 'dead'
        else
            local p = Person(C, pos, 0.0, 'elderly', 'victim', roll < 0.5 and 'elderly_hurt' or 'elderly', { model = model })
            if p then
                if roll < 0.5 then Writhe(p) C.outcome = 'hurt' else Scenario(p, 'WORLD_HUMAN_STAND_IMPATIENT') C.outcome = 'fine' end
                C.person = p
            end
        end
    end,
    arrive = function(C)
        if C.outcome == 'dead' then Notify('No answer... you find them inside. They\'ve passed away. Secure the scene and request the coroner.')
        elseif C.outcome == 'hurt' then Notify('They\'ve had a fall. Request EMS and stay with them.')
        else Notify('Knock and talk to them. Make sure they\'re okay.') end
    end,
    tick = function(C) if C.outcome == 'hurt' then KeepWrithing(C.person) end end,
    resolved = function(C)
        if not C.arrived then return false end
        if C.outcome == 'dead' then return (UnitsNear and UnitsNear('coroner', C.pos, 50.0) > 0) or TimeOnScene(C, 240000) end
        if C.outcome == 'hurt' then return (UnitsNear and UnitsNear('ems', C.pos, 50.0) > 0) or TimeOnScene(C, 180000) end
        return TimeOnScene(C, 45000)
    end,
}

-- Loud party: drunk guests and an unhappy host
S.loud_party = {
    setup = function(C)
        local pos = Spot(C, 'yard')
        Prop(C, 'prop_boombox_01', Around(pos, 2), 0.0)
        for i = 1, math.random(3, 5) do
            local g = Person(C, Around(pos, 5), 0.0, 'partygoer', 'witness', 'none')
            if g then Scenario(g, { 'WORLD_HUMAN_PARTYING', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_SMOKING_POT', 'WORLD_HUMAN_HANG_OUT_STREET' }) end
        end
        local h = Person(C, Around(pos, 3), 0.0, 'host', 'suspect', 'party_host')
        if h then Scenario(h, 'WORLD_HUMAN_DRINKING') C.host = h end
        local n = Person(C, Around(C.pos, 30), 0.0, 'witness', 'witness', 'neighbour')
        if n then Scenario(n, 'WORLD_HUMAN_STAND_IMPATIENT') end
    end,
    arrive = function(C) Notify('Talk to the host. A warning usually does it - a citation if it\'s the third time.') end,
    tick = function(C) Approach(C.host, 12.0, Comply) end,
}

-- Dog attack
S.dog_attack = {
    setup = function(C)
        local pos = Spot(C)
        local v = Person(C, pos, 0.0, 'victim', 'victim', 'dog_victim')
        if v then Writhe(v) C.victim = v end
        local dog = SpawnPed(PickOne({ 'a_c_rottweiler', 'a_c_chop', 'a_c_shepherd' }), Around(pos, 3), 0.0)
        if dog then
            C.ents[#C.ents + 1] = dog
            SetPedRelationshipGroupHash(dog, SuspectGroup())
            SetBlockingOfNonTemporaryEvents(dog, true)
            SetPedCombatAttributes(dog, 46, true)
            C.dog = dog
        end
        local o = Person(C, Around(pos, 8), 0.0, 'dogowner', 'suspect', 'dog_owner')
        if o then Scenario(o, 'WORLD_HUMAN_STAND_IMPATIENT') C.owner = o end
    end,
    arrive = function(C) Notify('Protect the victim. If the dog turns on you, use your taser or your weapon. Then deal with the owner.') end,
    tick = function(C)
        KeepWrithing(C.victim)
        local dog = C.dog
        if dog and DoesEntityExist(dog) and not IsPedDeadOrDying(dog, true) and not C.dogOn and Dist(dog, Me()) < 18.0 then
            C.dogOn = true
            ClearPedTasks(dog)
            TaskCombatPed(dog, Me(), 0, 16)
            SetPedKeepTask(dog, true)
        end
    end,
    resolved = function(C)
        if not C.arrived then return false end
        local dogDone = not C.dog or not DoesEntityExist(C.dog) or IsPedDeadOrDying(C.dog, true) or IsPedBeingStunned(C.dog, 0) or TimeOnScene(C, 180000)
        return dogDone and Resolved(C)
    end,
}

-- Suspicious package: clear the area, wait for the bomb squad (SWAT)
S.bomb_threat = {
    setup = function(C)
        local pos = Spot(C, 'outside')
        C.package = Prop(C, PickOne({ 'prop_ld_suitcase_01', 'prop_cs_heist_bag_01', 'prop_cs_package_01' }), pos, 0.0)
        C.pkgPos = pos
        local m = Person(C, Around(pos, 14), 0.0, 'witness', 'witness', 'bomb_manager', { model = PickOne({ 'a_m_y_business_02', 'a_f_y_business_04', 'a_m_m_business_01' }) })
        if m then Scenario(m, 'WORLD_HUMAN_STAND_MOBILE') end
        C.crowd = Crowd(C, pos, math.random(3, 5), 'stand')
        C.giveUpAt = GetGameTimer() + 480000
    end,
    arrive = function(C) Notify('~o~Suspicious package.~s~ Don\'t touch it. Walk up to the people nearby to move them back, set cones, and wait for the bomb squad (SWAT).') end,
    tick = function(C)
        -- move people back as you reach them
        for i, ped in ipairs(C.crowd or {}) do
            if DoesEntityExist(ped) and not C['cleared' .. i] and Dist(ped, Me()) < 6.0 and Control(ped, 300) then
                C['cleared' .. i] = true
                ClearPedTasks(ped)
                TaskSmartFleeCoord(ped, C.pkgPos.x, C.pkgPos.y, C.pkgPos.z, 80.0, -1, false, false)
            end
        end
        if C.safe then return end
        local squad = UnitsNear and UnitsNear('swat', C.pkgPos, 40.0) > 0
        if squad then
            C.squadSince = C.squadSince or GetGameTimer()
            if GetGameTimer() - C.squadSince > 25000 then
                C.safe = true
                if C.package and DoesEntityExist(C.package) then DeleteEntity(C.package) end
                RadioLine('Bomb squad: device rendered safe. It was a hoax - wires taped to a power bank. Scene is yours.')
            end
        elseif GetGameTimer() > (C.giveUpAt or 0) then
            C.safe = true
            if C.package and DoesEntityExist(C.package) then DeleteEntity(C.package) end
            RadioLine('Bomb squad: arrived from the other side, package removed and rendered safe.')
        end
    end,
    resolved = function(C) return C.safe == true end,
}

-- Body found
S.body_found = {
    setup = function(C)
        local pos = Spot(C)
        Body(C, pos)
        local j = Person(C, Around(pos, 12), 0.0, 'witness', 'witness', 'body_finder', { model = PickOne({ 'a_m_y_runner_01', 'a_f_y_runner_01', 'a_m_y_runner_02' }) })
        if j then Scenario(j, 'WORLD_HUMAN_STAND_MOBILE') end
        if math.random() < 0.5 then Prop(C, 'prop_ld_wallet_01', Around(pos, 2), 0.0) end
    end,
    arrive = function(C) Notify('Secure the scene (cones / tape), take the jogger\'s statement and request the coroner from the patrol computer.') end,
    resolved = function(C)
        return C.arrived and ((UnitsNear and UnitsNear('coroner', C.pos, 50.0) > 0) or TimeOnScene(C, 300000))
    end,
}
