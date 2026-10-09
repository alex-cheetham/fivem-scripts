-- AI patrol: callouts. The server offers one, you accept with Y, the scene is set up as you get close.
local C = nil              -- the callout you're on
local pendingOffer = nil

local function Profile(list) return list[math.random(1, #list)] end

---------------------------------------------------------------------------
-- Building blocks for scenes
---------------------------------------------------------------------------
local function Car(C, model, pos, heading)
    local veh = SpawnVeh(model or PickOne(AI.Cars), pos, heading)
    if veh then C.ents[#C.ents + 1] = veh end
    return veh
end

-- A person in the scene. role: suspect / victim / witness
local function Person(C, pos, heading, profile, role, story, opts)
    opts = opts or {}
    local model = opts.model or PickOne(opts.gang and AI.Gangs or AI.Peds)
    local ped = SpawnPed(model, pos, heading, opts.veh, opts.seat)
    if not ped then return nil end
    C.ents[#C.ents + 1] = ped
    local e = Persona(ped, role, profile, opts.veh, story, opts.bind)
    if not e then return nil end
    e.callout, e.status = C, 'free'
    if opts.veh then e.veh, e.seat = opts.veh, opts.seat or -1 end
    C.people[#C.people + 1] = e
    Hold(ped)
    return e
end

local function Writhe(e)
    if not e or not DoesEntityExist(e.ped) or not Control(e.ped, 300) then return end
    e.injured = true
    if LoadDict('combat@damage@writhe') then
        TaskPlayAnim(e.ped, 'combat@damage@writhe', 'writhe_loop', 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end
    SetEntityHealth(e.ped, 150)
end

local function Wander(e, speed, style)
    if not DoesEntityExist(e.ped) or not Control(e.ped, 500) then return end
    if e.veh and IsPedInVehicle(e.ped, e.veh, false) then
        SetDriverAbility(e.ped, 0.8)
        TaskVehicleDriveWander(e.ped, e.veh, speed or 17.0, style or 786603)
    else
        TaskWanderStandard(e.ped, 10.0, 10)
    end
    SetPedKeepTask(e.ped, true)
end

-- When the officer gets close: comply, run or fight
local function Approach(e, dist, onComply)
    if not e or e.triggered or e.status ~= 'free' or not DoesEntityExist(e.ped) then return end
    if Dist(e.ped, Me()) < dist then
        e.triggered = true
        CreateThread(function()
            local act = AIReact(e, 'approach')
            if not ApplyReaction(e, act) and onComply then onComply(e) end
        end)
    end
end

local function Comply(e)
    if not Control(e.ped) then return end
    HoldOnFoot(e)
end

local function HandsUp(e)
    Surrender(e, false)
end

-- Search area for something on the move, turning into an exact blip when you're close
local function TrackMover(C, ent, label)
    if not ent or not DoesEntityExist(ent) then return end
    local d = Dist(ent, Me())
    if d < 110.0 then
        if C.area then RemoveBlipSafe(C.area) C.area = nil end
        if not C.exact then
            C.exact = AddBlipForEntity(ent)
            SetBlipColour(C.exact, 5)
            NamedBlip(C.exact, label or 'Callout')
            if C.blip then SetBlipRoute(C.blip, false) end
        end
    elseif GetGameTimer() > (C.areaAt or 0) then
        C.areaAt = GetGameTimer() + 12000
        local p = GetEntityCoords(ent)
        local off = vector3(math.random(-60, 60) + 0.0, math.random(-60, 60) + 0.0, 0.0)
        RemoveBlipSafe(C.area)
        C.area = AddBlipForRadius(p.x + off.x, p.y + off.y, p.z, 140.0)
        SetBlipColour(C.area, 5)
        SetBlipAlpha(C.area, 90)
        if C.blip then SetBlipCoords(C.blip, p.x + off.x, p.y + off.y, p.z) end
    end
end

local function Suspects(C)
    local out = {}
    for _, e in ipairs(C.people) do if e.role == 'suspect' then out[#out + 1] = e end end
    return out
end

-- Every suspect dealt with (in cuffs, dead, gone, released or lost)?
local function Resolved(C)
    local list = Suspects(C)
    if #list == 0 then return C.arrived and GetGameTimer() - (C.arrivedAt or 0) > 30000 end
    for _, e in ipairs(list) do
        local tracked = AIPeds[e.ped] == e
        if tracked and DoesEntityExist(e.ped) then
            local s = e.status
            if not (s == 'cuffed' or s == 'escorted' or s == 'seated' or s == 'dead') then return false end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- The scenes. setup() runs when you get near, tick() twice a second after that.
---------------------------------------------------------------------------
local SCENES = {}

SCENES.stolen_vehicle = {
    moving = true,
    setup = function(C)
        local veh = Car(C, PickOne(math.random() < 0.4 and AI.FastCars or AI.Cars), C.pos, C.heading)
        if not veh then return end
        local e = Person(C, nil, nil, 'stolen', 'suspect', nil, { veh = veh, seat = -1 })
        if e then Wander(e, 18.0) end
        C.mover = veh
    end,
    tick = function(C) TrackMover(C, C.mover, 'Stolen vehicle') end,
}

SCENES.drunk_driver = {
    moving = true,
    setup = function(C)
        local veh = Car(C, nil, C.pos, C.heading)
        if not veh then return end
        local e = Person(C, nil, nil, 'drunk', 'suspect', nil, { veh = veh, seat = -1 })
        if e then Wander(e, 14.0) end
        C.mover, C.driver = veh, e
    end,
    tick = function(C)
        TrackMover(C, C.mover, 'Drunk driver')
        local e = C.driver
        if e and e.status == 'free' and DoesEntityExist(e.ped) and GetGameTimer() > (C.swerve or 0) then
            C.swerve = GetGameTimer() + math.random(5000, 10000)
            if Control(e.ped, 300) and IsPedInVehicle(e.ped, C.mover, false) then
                TaskVehicleTempAction(e.ped, C.mover, math.random(7, 8), math.random(400, 900))
                SetTimeout(1200, function() if e.status == 'free' then Wander(e, 14.0) end end)
            end
        end
    end,
}

SCENES.speeder = {
    moving = true,
    setup = function(C)
        local veh = Car(C, PickOne(AI.FastCars), C.pos, C.heading)
        if not veh then return end
        local e = Person(C, nil, nil, 'reckless', 'suspect', nil, { veh = veh, seat = -1 })
        if e then Wander(e, 38.0, 1074528293) end
        C.mover = veh
    end,
    tick = function(C) TrackMover(C, C.mover, 'Reckless driver') end,
}

SCENES.shots_fired = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local s = Person(C, spot, 0.0, 'shooter', 'suspect')
        if s then
            GiveWeaponToPed(s.ped, GetHashKey(s.persona.weapon or 'WEAPON_PISTOL'), 60, false, true)
            C.shooter = s
        end
        local w = Person(C, FindFoot(C.pos + vector3(15.0, 10.0, 0.0)), 0.0, 'witness', 'witness', 'witness')
        if w then TaskStartScenarioInPlace(w.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true) end
    end,
    tick = function(C)
        local s = C.shooter
        if not s or not DoesEntityExist(s.ped) then return end
        if s.status == 'free' and not s.triggered and GetGameTimer() > (C.shootAt or 0) and Dist(s.ped, Me()) > 45.0 then
            C.shootAt = GetGameTimer() + math.random(4000, 9000)
            if Control(s.ped, 300) then
                local p = GetEntityCoords(s.ped)
                TaskShootAtCoord(s.ped, p.x + math.random(-5, 5), p.y + math.random(-5, 5), p.z + 12.0, 1200, GetHashKey('FIRING_PATTERN_SINGLE_SHOT'))
            end
        end
        Approach(s, 40.0, HandsUp)
    end,
}

SCENES.domestic = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local v = Person(C, spot, 0.0, 'victim', 'victim', 'domestic_victim')
        local s = Person(C, spot + vector3(1.5, 0.5, 0.0), 0.0, 'violent', 'suspect', 'domestic_suspect')
        if v and s then
            TaskTurnPedToFaceEntity(v.ped, s.ped, -1)
            TaskTurnPedToFaceEntity(s.ped, v.ped, -1)
            C.victim, C.suspect = v, s
        end
    end,
    tick = function(C)
        local s, v = C.suspect, C.victim
        if s and s.status == 'free' and v and DoesEntityExist(v.ped) and GetGameTimer() > (C.argue or 0) and Dist(s.ped, Me()) > 30.0 then
            C.argue = GetGameTimer() + 6000
            if Control(s.ped, 300) and LoadDict('misscarsteal4@actor') then
                TaskPlayAnim(s.ped, 'misscarsteal4@actor', 'actor_berating_loop', 8.0, -8.0, 5000, 49, 0.0, false, false, false)
            end
        end
        Approach(s, 25.0, Comply)
        if v and v.status == 'free' and Dist(v.ped, Me()) < 20.0 then Comply(v) end
    end,
}

SCENES.fight = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local a = Person(C, spot, 0.0, 'violent', 'suspect', 'fight')
        local b = Person(C, spot + vector3(1.2, 0.0, 0.0), 0.0, Profile({ 'violent', 'drunk', 'public' }), 'suspect', 'fight')
        if a and b then
            for _, x in ipairs({ a, b }) do
                SetPedMaxHealth(x.ped, 400)
                SetEntityHealth(x.ped, 400)
                SetPedFleeAttributes(x.ped, 0, false)
            end
            TaskCombatPed(a.ped, b.ped, 0, 16)
            TaskCombatPed(b.ped, a.ped, 0, 16)
            C.a, C.b = a, b
        end
    end,
    tick = function(C)
        if not C.a or not C.b then return end
        if not C.broken and Dist(C.a.ped, Me()) < 25.0 then
            C.broken = true
            for _, x in ipairs({ C.a, C.b }) do
                if DoesEntityExist(x.ped) and Control(x.ped, 500) then ClearPedTasks(x.ped) end
            end
            Wait(300)
            Approach(C.a, 99.0, Comply)
            Approach(C.b, 99.0, Comply)
        end
    end,
}

SCENES.shoplifter = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local s = Person(C, spot + vector3(8.0, 6.0, 0.0), 0.0, 'thief', 'suspect', 'shop')
        if s then Wander(s) C.suspect = s end
        local w = Person(C, spot, 0.0, 'witness', 'witness', 'witness')
        if w then TaskStartScenarioInPlace(w.ped, 'WORLD_HUMAN_CLIPBOARD', 0, true) end
    end,
    tick = function(C) Approach(C.suspect, 18.0, Comply) end,
}

SCENES.drunk_person = {
    setup = function(C)
        local s = Person(C, FindFoot(C.pos), 0.0, 'drunk', 'suspect', 'none')
        if s then
            RequestAnimSet('move_m@drunk@verydrunk')
            local t = GetGameTimer() + 2000
            while not HasAnimSetLoaded('move_m@drunk@verydrunk') and GetGameTimer() < t do Wait(10) end
            SetPedMovementClipset(s.ped, 'move_m@drunk@verydrunk', 1.0)
            Wander(s)
            C.suspect = s
        end
    end,
    tick = function(C) Approach(C.suspect, 15.0, Comply) end,
}

SCENES.suspicious = {
    setup = function(C)
        local s = Person(C, FindFoot(C.pos), 0.0, Profile({ 'drugged', 'wanted', 'public', 'thief', 'armed' }), 'suspect', 'none')
        if s then TaskStartScenarioInPlace(s.ped, PickOne({ 'WORLD_HUMAN_DRUG_DEALER', 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_IMPATIENT' }), 0, true) C.suspect = s end
    end,
    tick = function(C) Approach(C.suspect, 15.0, Comply) end,
}

SCENES.crash = {
    setup = function(C)
        local veh = Car(C, nil, C.pos, C.heading)
        if not veh then return end
        SetVehicleEngineHealth(veh, 80.0)
        SetVehicleBodyHealth(veh, 200.0)
        SetVehicleEngineOn(veh, false, true, true)
        SmashVehicleWindow(veh, 0)
        SetVehicleDoorBroken(veh, 4, true)
        SetVehicleDamage(veh, 0.0, 1.5, 0.3, 900.0, 200.0, true)
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
        local spot = FindFoot(GetEntityCoords(veh))
        local d = Person(C, spot, 0.0, Profile({ 'drunk', 'public', 'public', 'drugged' }), 'suspect', 'crash', { })
        if d then d.veh = veh TaskStartScenarioInPlace(d.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true) C.driver = d end
        if math.random() < 0.6 then
            local v = Person(C, spot + vector3(2.0, 1.5, 0.0), 0.0, 'victim', 'victim', 'crash')
            if v then Writhe(v) C.victim = v end
        end
    end,
    tick = function(C)
        Approach(C.driver, 20.0, Comply)
        local v = C.victim
        if v and AIPeds[v.ped] == v and v.status == 'free' and not IsEntityPlayingAnim(v.ped, 'combat@damage@writhe', 'writhe_loop', 3) then Writhe(v) end
    end,
    resolved = function(C)
        return C.arrived and GetGameTimer() - (C.arrivedAt or 0) > 45000 and (not C.driver or C.driver.status ~= 'free')
    end,
}

SCENES.hit_and_run = {
    moving = true,
    setup = function(C)
        local v = Person(C, FindFoot(C.pos), 0.0, 'victim', 'victim', 'victim_hit')
        if v then Writhe(v) C.victim = v end
        local w = Person(C, FindFoot(C.pos + vector3(6.0, 4.0, 0.0)), 0.0, 'witness', 'witness', 'witness')
        if w then TaskStartScenarioInPlace(w.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true) end
        local pos, heading = FindRoad(90.0, 180.0, C.pos)
        if pos then
            local veh = Car(C, nil, pos, heading)
            if veh then
                SetVehicleDamage(veh, 0.0, 1.8, 0.2, 400.0, 150.0, true)
                local s = Person(C, nil, nil, Profile({ 'reckless', 'drunk', 'wanted' }), 'suspect', nil, { veh = veh, seat = -1 })
                if s then Wander(s, 22.0) end
                C.mover = veh
            end
        end
    end,
    tick = function(C)
        if C.mover and C.arrived then TrackMover(C, C.mover, 'Hit and run vehicle') end
        local v = C.victim
        if v and AIPeds[v.ped] == v and v.status == 'free' and not IsEntityPlayingAnim(v.ped, 'combat@damage@writhe', 'writhe_loop', 3) then Writhe(v) end
    end,
}

SCENES.armed_robbery = {
    moving = true,
    setup = function(C)
        local w = Person(C, FindFoot(C.pos), 0.0, 'witness', 'witness', 'witness')
        if w then TaskStartScenarioInPlace(w.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true) end
        local pos, heading = FindRoad(60.0, 140.0, C.pos)
        local veh = Car(C, PickOne(AI.FastCars), pos or C.pos, heading or C.heading)
        if not veh then return end
        local s = Person(C, nil, nil, 'robber', 'suspect', nil, { veh = veh, seat = -1 })
        if s then
            GiveWeaponToPed(s.ped, GetHashKey(s.persona.weapon or 'WEAPON_PISTOL'), 60, false, false)
            Wander(s, 26.0, 1074528293)
            C.robber = s
        end
        if math.random() < 0.5 then
            local p = Person(C, nil, nil, 'robber', 'suspect', nil, { veh = veh, seat = 0 })
            if p then GiveWeaponToPed(p.ped, GetHashKey(p.persona.weapon or 'WEAPON_PISTOL'), 60, false, false) end
        end
        C.mover = veh
    end,
    tick = function(C)
        TrackMover(C, C.mover, 'Robbery suspect vehicle')
        local s = C.robber
        if s and s.status == 'free' and not s.triggered and Dist(s.ped, Me()) < 45.0 then
            s.triggered = true
            CreateThread(function()
                local act = AIReact(s, 'stop')
                if act == 'fight' then Fight(s) else FleeInVehicle(s) end
            end)
        end
    end,
}

SCENES.wanted_person = {
    setup = function(C)
        local s = Person(C, FindFoot(C.pos), 0.0, 'wanted', 'suspect', 'none')
        if s then Wander(s) C.suspect = s C.mover = s.ped end
    end,
    tick = function(C)
        if C.suspect and C.suspect.status == 'free' then TrackMover(C, C.mover, 'Wanted person') end
        Approach(C.suspect, 14.0, Comply)
    end,
}

SCENES.abandoned = {
    setup = function(C)
        local veh = Car(C, nil, C.pos, C.heading)
        if not veh then return end
        SetVehicleEngineOn(veh, false, true, true)
        SetVehicleDoorsLocked(veh, 1)
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
        C.vehicle = veh
    end,
    arrive = function(C) Notify('Check the vehicle: run its plate (F7 > Vehicle) and request a tow from the patrol computer.') end,
    resolved = function(C)
        return C.arrived and (not C.vehicle or not DoesEntityExist(C.vehicle) or IsEntityAttached(C.vehicle) or GetGameTimer() - (C.arrivedAt or 0) > 120000)
    end,
}

SCENES.road_rage = {
    setup = function(C)
        local v1 = Car(C, nil, C.pos, C.heading)
        if not v1 then return end
        local v2 = Car(C, nil, GetOffsetFromEntityInWorldCoords(v1, 0.0, -7.0, 0.0), C.heading)
        if not v2 then return end
        SetVehicleDamage(v1, 0.0, -2.0, 0.2, 300.0, 100.0, true)
        local spot = FindFoot(GetEntityCoords(v1))
        local s = Person(C, spot, 0.0, 'violent', 'suspect', 'roadrage', { model = PickOne(AI.Peds) })
        local v = Person(C, spot + vector3(1.8, 0.0, 0.0), 0.0, 'victim', 'victim', 'roadrage')
        if s then
            s.veh = v2
            if s.persona.melee then GiveWeaponToPed(s.ped, GetHashKey(s.persona.melee), 1, false, true) end
            if v then TaskTurnPedToFaceEntity(s.ped, v.ped, -1) TaskTurnPedToFaceEntity(v.ped, s.ped, -1) v.veh = v1 end
            C.suspect = s
        end
    end,
    tick = function(C) Approach(C.suspect, 25.0, Comply) end,
}

SCENES.trespass = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local s = Person(C, spot, 0.0, 'trespass', 'suspect', 'trespass')
        if s then TaskStartScenarioInPlace(s.ped, PickOne({ 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_LEANING' }), 0, true) C.suspect = s end
        local o = Person(C, spot + vector3(6.0, -4.0, 0.0), 0.0, 'witness', 'witness', 'witness')
        if o then TaskStartScenarioInPlace(o.ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true) end
    end,
    tick = function(C) Approach(C.suspect, 15.0, Comply) end,
}

SCENES.gang_shootout = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        C.gang = {}
        for i = 1, math.random(2, 4) do
            local g = Person(C, spot + vector3(i * 1.6, (i % 2) * 1.5, 0.0), 0.0, 'gang', 'suspect', 'none', { gang = true })
            if g then
                GiveWeaponToPed(g.ped, GetHashKey(g.persona.weapon or 'WEAPON_PISTOL'), 120, false, true)
                TaskStartScenarioInPlace(g.ped, PickOne({ 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRUG_DEALER_HARD', 'WORLD_HUMAN_HANG_OUT_STREET' }), 0, true)
                C.gang[#C.gang + 1] = g
            end
        end
    end,
    tick = function(C)
        for _, g in ipairs(C.gang or {}) do Approach(g, 55.0, HandsUp) end
    end,
}


---------------------------------------------------------------------------
-- Hostage situations
---------------------------------------------------------------------------
local function HoldHostage(s, h)
    if not LoadDict('anim@gangops@hostage@') then return end
    AttachEntityToEntity(h.ped, s.ped, 0, -0.24, 0.11, 0.0, 0.5, -0.4, -0.2, false, false, false, false, 2, false)
    TaskPlayAnim(s.ped, 'anim@gangops@hostage@', 'perp_idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)
    TaskPlayAnim(h.ped, 'anim@gangops@hostage@', 'victim_idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)
end

local function FreeHostage(s)
    local h = s.hostagePed
    if not h or not DoesEntityExist(h.ped) then return end
    s.hostagePed = nil
    if Control(h.ped, 800) then
        DetachEntity(h.ped, true, false)
        ClearPedTasks(h.ped)
        local away = GetOffsetFromEntityInWorldCoords(s.ped, 0.0, -12.0, 0.0)
        TaskGoToCoordAnyMeans(h.ped, away.x, away.y, away.z, 2.5, 0, false, 786603, 0.0)
        SetTimeout(5000, function() if AIPeds[h.ped] == h then HoldOnFoot(h) end end)
    end
end

function HostageOutcome(e, outcome)
    FreeHostage(e)
    if not Control(e.ped) then return end
    ClearPedTasks(e.ped)
    if outcome == 'release' then
        Surrender(e, false)
        Notify('~g~The hostage is free!~s~ The suspect is surrendering - move in and cuff them.')
        RadioLine(Callsign() .. ': hostage released, suspect surrendering.')
    elseif outcome == 'flee' then
        FleeOnFoot(e)
        RadioLine(Callsign() .. ': hostage released, suspect running!')
    else
        Fight(e)
        RadioLine(Callsign() .. ': shots fired! Suspect is engaging!')
    end
end

SCENES.hostage = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local s = Person(C, spot, 0.0, 'hostagetaker', 'suspect', 'none')
        local h = Person(C, spot + vector3(0.5, 0.0, 0.0), 0.0, 'victim', 'victim', 'hostage')
        if not s or not h then return end
        GiveWeaponToPed(s.ped, GetHashKey(s.persona.weapon or 'WEAPON_PISTOL'), 60, false, true)
        s.hostagePed, h.status = h, 'hostage'
        HoldHostage(s, h)
        C.taker, C.victim = s, h
    end,
    arrive = function(C) Notify('~r~Hostage situation.~s~ Stay back. Press ~INPUT_CONTEXT~ within 25m to negotiate. Rushing in could get someone hurt.') end,
    tick = function(C)
        local s = C.taker
        if not s or not DoesEntityExist(s.ped) then return end
        if s.hostagePed and IsPedDeadOrDying(s.ped, true) then FreeHostage(s) end
        if s.hostagePed and s.persona.hostage then
            if not IsEntityPlayingAnim(s.ped, 'anim@gangops@hostage@', 'perp_idle', 3) and Control(s.ped, 300) then HoldHostage(s, s.hostagePed) end
            if Control(s.ped, 300) then TaskTurnPedToFaceEntity(s.ped, Me(), 500) end
            if Dist(s.ped, Me()) < 5.0 and not s.rushed then
                s.rushed = true
                CreateThread(function()
                    local act = AIReact(s, 'approach')
                    HostageOutcome(s, act == 'flee' and 'flee' or 'fight')
                end)
            end
        end
    end,
}

---------------------------------------------------------------------------
-- Person in crisis: talk them round, call the mental health team, no force if you can help it
---------------------------------------------------------------------------
SCENES.crisis = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local p = Person(C, spot, 0.0, 'crisis', 'suspect', 'crisis')
        if not p then return end
        if p.persona.melee then GiveWeaponToPed(p.ped, GetHashKey(p.persona.melee), 1, false, true) end
        TaskWanderInArea(p.ped, spot.x, spot.y, spot.z, 6.0, 2.0, 1.0)
        C.person = p
    end,
    arrive = function(C)
        Notify('~b~Person in crisis.~s~ Slow down and keep your distance. Press ~INPUT_CONTEXT~ within 25m to talk. Request the mental health team from the patrol computer.')
    end,
    tick = function(C)
        local p = C.person
        if not p or not DoesEntityExist(p.ped) or AIPeds[p.ped] ~= p then return end
        if p.persona.crisis then
            if Control(p.ped, 300) and Dist(p.ped, Me()) < 25.0 and math.random() < 0.3 then TaskTurnPedToFaceEntity(p.ped, Me(), 800) end
            -- rushing in without talking frightens them
            if Dist(p.ped, Me()) < 3.0 and not p.rushed and (p.persona.nego or 0) < 70 then
                p.rushed = true
                CreateThread(function()
                    local act = AIReact(p, 'approach')
                    ApplyReaction(p, act)
                end)
            end
        end
    end,
    resolved = function(C)
        local p = C.person
        if not p then return true end
        if p.hospitalised then return true end
        if AIPeds[p.ped] ~= p or not DoesEntityExist(p.ped) then return true end
        local s = p.status
        return s == 'cuffed' or s == 'escorted' or s == 'seated' or s == 'dead'
    end,
}

---------------------------------------------------------------------------
-- Street crime
---------------------------------------------------------------------------
SCENES.mugging = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local v = Person(C, spot, 0.0, 'victim', 'victim', 'mugged')
        local s = Person(C, spot + vector3(1.2, 0.3, 0.0), 0.0, 'mugger', 'suspect', 'none')
        if not v or not s then return end
        if s.persona.melee then GiveWeaponToPed(s.ped, GetHashKey(s.persona.melee), 1, false, true) end
        TaskTurnPedToFaceEntity(s.ped, v.ped, -1)
        TaskHandsUp(v.ped, -1, s.ped, -1, true)
        C.mugger, C.victim = s, v
    end,
    tick = function(C)
        local s, v = C.mugger, C.victim
        if s and s.status == 'free' and not s.triggered and Dist(s.ped, Me()) < 55.0 then
            s.triggered = true
            CreateThread(function()
                local act = AIReact(s, 'approach')
                if not ApplyReaction(s, act == 'comply' and 'flee' or act) then FleeOnFoot(s) end
                if v and Control(v.ped, 300) then ClearPedTasks(v.ped) v.status = 'free' end
            end)
        end
    end,
}

SCENES.drug_deal = {
    setup = function(C)
        local spot = FindFoot(C.pos)
        local d = Person(C, spot, 0.0, 'dealer', 'suspect', 'none')
        local b = Person(C, spot + vector3(1.1, 0.0, 0.0), 0.0, 'drugged', 'suspect', 'none')
        if not d or not b then return end
        TaskTurnPedToFaceEntity(d.ped, b.ped, -1)
        TaskTurnPedToFaceEntity(b.ped, d.ped, -1)
        C.dealer, C.buyer = d, b
    end,
    tick = function(C)
        local d, b = C.dealer, C.buyer
        if d and d.status == 'free' and Dist(d.ped, Me()) > 40.0 and GetGameTimer() > (C.swap or 0) and LoadDict('mp_common') then
            C.swap = GetGameTimer() + 7000
            if Control(d.ped, 300) then TaskPlayAnim(d.ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 2000, 49, 0.0, false, false, false) end
            if b and Control(b.ped, 300) then TaskPlayAnim(b.ped, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 49, 0.0, false, false, false) end
        end
        Approach(d, 30.0, Comply)
        Approach(b, 30.0, Comply)
    end,
}

SCENES.missing_person = {
    moving = true,
    setup = function(C)
        local carer = Person(C, FindFoot(C.pos), 0.0, 'witness', 'witness', 'witness')
        if carer then TaskStartScenarioInPlace(carer.ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true) C.carer = carer end
        local pos = FindRoad(120.0, 260.0, C.pos)
        local m = Person(C, FindFoot(pos or C.pos), 0.0, 'missing', 'victim', 'missing', { model = PickOne({ 'a_m_o_genstreet_01', 'a_f_o_genstreet_01', 'a_m_o_soucent_01', 'a_f_o_soucent_02' }) })
        if m then
            RequestAnimSet('move_m@injured')
            SetPedMovementClipset(m.ped, 'move_m@injured', 1.0)
            TaskWanderStandard(m.ped, 10.0, 10)
            C.missing, C.mover = m, m.ped
        end
    end,
    arrive = function(C) Notify('Talk to the carer, then search the area for the missing person. Tell them to follow you and bring them back.') end,
    tick = function(C)
        local m = C.missing
        if m and m.status == 'free' then TrackMover(C, C.mover, 'Missing person') end
        if m and m.status == 'held' and not m.calmed then m.calmed = true Notify('Found them! Use Orders > Come with me and walk them back to their carer.') end
    end,
    resolved = function(C)
        local m, carer = C.missing, C.carer
        if not m or AIPeds[m.ped] ~= m then return true end
        return carer and DoesEntityExist(m.ped) and DoesEntityExist(carer.ped) and Dist(m.ped, carer.ped) < 10.0
    end,
}


---------------------------------------------------------------------------
-- Scenes at real places (stores, houses). These replace the street versions when dispatch has a place.
---------------------------------------------------------------------------
local function Spots(C)
    if not C.loc then return nil end
    C.spots = C.spots or PlaceSpots(C.loc)
    return C.spots
end

local streetRobbery = SCENES.armed_robbery
local streetShoplifter = SCENES.shoplifter
local streetDomestic = SCENES.domestic
local streetWanted = SCENES.wanted_person
local streetHostage = SCENES.hostage

-- Armed robbery in progress: inside the store, gun on the cashier, getaway car at the kerb
SCENES.armed_robbery = {
    setup = function(C)
        local s = Spots(C)
        if not s or not s.counter then C.street_ = true return streetRobbery.setup(C) end
        local r = Person(C, s.front, (s.heading + 180.0) % 360.0, 'robber', 'suspect', 'none')
        if not r then return end
        GiveWeaponToPed(r.ped, GetHashKey(r.persona.weapon or 'WEAPON_PISTOL'), 60, false, true)
        TaskAimGunAtCoord(r.ped, s.counter.x, s.counter.y, s.counter.z + 0.4, -1, false, false)
        C.robber = r
        local v = Person(C, s.aisle, 0.0, 'victim', 'victim', 'robbery_witness')
        if v then TaskHandsUp(v.ped, -1, r.ped, -1, true) C.victim = v end
        if s.kerb then
            local car = Car(C, PickOne(AI.FastCars), s.kerb, s.roadHeading or s.heading)
            if car then
                SetVehicleEngineOn(car, true, true, false)
                SetVehicleDoorsLocked(car, 1)
                C.getaway = car
                if math.random() < 0.45 then
                    local d = Person(C, nil, nil, 'robber', 'suspect', 'none', { veh = car, seat = -1 })
                    if d then
                        C.driver = d
                        GiveWeaponToPed(d.ped, GetHashKey(d.persona.weapon or 'WEAPON_PISTOL'), 60, false, false)
                    end
                end
            end
        end
        C.leaveAt = GetGameTimer() + math.random(90000, 160000)
    end,
    arrive = function(C)
        if C.street_ then return end
        Notify('~r~Robbery in progress inside the store.~s~ Approach carefully - they may run for the car outside.')
    end,
    tick = function(C)
        if C.street_ then return streetRobbery.tick(C) end
        if C.mover then TrackMover(C, C.mover, 'Robbery suspect vehicle') end
        if C.taker then return SCENES.hostage.tick(C) end
        -- the getaway driver: drives off (or fights) once the robber is dealt with or you walk up to the car
        local dr = C.driver
        if dr and not dr.triggered and AIPeds[dr.ped] == dr and dr.status == 'free' and C.getaway and DoesEntityExist(C.getaway) then
            local robberDone = not C.robber or AIPeds[C.robber.ped] ~= C.robber or (C.robber.status ~= 'free' and C.robber.veh ~= C.getaway)
            if robberDone or Dist(C.getaway, Me()) < 30.0 then
                dr.triggered = true
                CreateThread(function()
                    local act = AIReact(dr, 'stop')
                    if act == 'fight' then Fight(dr)
                    elseif act == 'comply' or act == 'reach' then
                        if Control(dr.ped, 300) then TaskLeaveVehicle(dr.ped, C.getaway, 256) end
                        Wait(1500)
                        Surrender(dr)
                    else
                        dr.veh = C.getaway
                        FleeInVehicle(dr)
                        C.mover = C.getaway
                    end
                end)
            end
        end
        local r = C.robber
        if not r or AIPeds[r.ped] ~= r or r.status ~= 'free' or r.triggered then return end
        local d = Dist(r.ped, Me())
        if d > 55.0 and GetGameTimer() < (C.leaveAt or 0) then
            -- keep the gun on the cashier
            if GetGameTimer() > (C.reaim or 0) and Control(r.ped, 200) then
                C.reaim = GetGameTimer() + 8000
                local s = Spots(C)
                TaskAimGunAtCoord(r.ped, s.counter.x, s.counter.y, s.counter.z + 0.4, -1, false, false)
            end
            return
        end
        r.triggered = true
        CreateThread(function()
            local act = d <= 55.0 and AIReact(r, 'approach') or 'flee'
            if act == 'comply' and C.victim and AIPeds[C.victim.ped] == C.victim and math.random() < 0.4 then
                -- grabs the customer
                local res = TriggerCallback('aiTakeHostage', r.pid)
                if res and res.ok then
                    if res.persona then r.persona = res.persona end
                    r.hostagePed, C.victim.status = C.victim, 'hostage'
                    HoldHostage(r, C.victim)
                    C.taker = r
                    Notify('~r~He\'s grabbed a customer!~s~ Hostage situation - stay back and negotiate (E within 25m).')
                    RadioLine(Callsign() .. ': suspect has taken a hostage inside the store!')
                    return
                end
            end
            if act == 'comply' or act == 'surrender' then Surrender(r) return end
            if act == 'fight' then Fight(r) return end
            if act == 'reach' then ApplyReaction(r, 'fight') return end
            -- run for the car
            local car = C.getaway
            if car and DoesEntityExist(car) and GetVehicleEngineHealth(car) > 300 and Control(r.ped, 500) then
                ClearPedTasks(r.ped)
                local drv = C.driver and AIPeds[C.driver.ped] == C.driver and C.driver or nil
                local seat = drv and 0 or -1
                TaskEnterVehicle(r.ped, car, 15000, seat, 2.0, 1, 0)
                r.veh, r.seat = car, seat
                local t = GetGameTimer() + 15000
                while AIPeds[r.ped] == r and not IsPedInVehicle(r.ped, car, false) and GetGameTimer() < t do Wait(200) end
                if AIPeds[r.ped] == r and IsPedInVehicle(r.ped, car, false) then
                    local who = drv or r
                    who.veh = car
                    FleeInVehicle(who)
                    if who ~= r then r.status = 'pursuit' end
                    C.mover = car
                    return
                end
            end
            FleeOnFoot(r)
        end)
    end,
}

-- Shoplifter walking out of the store with the goods
SCENES.shoplifter = {
    setup = function(C)
        local s = Spots(C)
        if not s or not s.counter then C.street_ = true return streetShoplifter.setup(C) end
        local t = Person(C, s.aisle, 0.0, 'thief', 'suspect', 'shop')
        if t then
            TaskGoToCoordAnyMeans(t.ped, s.outside.x, s.outside.y, s.outside.z, 1.0, 0, false, 786603, 0.0)
            C.suspect = t
        end
        local m = Person(C, s.outside + vector3(2.0, 1.0, 0.0), 0.0, 'witness', 'witness', 'witness')
        if m then TaskStartScenarioInPlace(m.ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true) end
    end,
    tick = function(C)
        local t = C.suspect
        if not C.street_ and t and t.status == 'free' and not t.left and DoesEntityExist(t.ped) then
            local s = Spots(C)
            if Dist(t.ped, s.outside) < 3.0 then t.left = true Wander(t) end
        end
        Approach(t, 18.0, Comply)
    end,
}

-- Domestic: on the doorstep / in the yard of a real house
SCENES.domestic = {
    setup = function(C)
        local s = Spots(C)
        if not s then return streetDomestic.setup(C) end
        local spot = s.house and s.yard or FootNear(s.base, 4)
        local v = Person(C, spot, 0.0, 'victim', 'victim', 'domestic_victim')
        local x = Person(C, spot + vector3(1.4, 0.6, 0.0), 0.0, 'violent', 'suspect', 'domestic_suspect')
        if v and x then
            TaskTurnPedToFaceEntity(v.ped, x.ped, -1)
            TaskTurnPedToFaceEntity(x.ped, v.ped, -1)
            C.victim, C.suspect = v, x
        end
    end,
    tick = streetDomestic.tick,
}

-- Wanted person: at home. Knock and announce, or force entry.
SCENES.wanted_person = {
    setup = function(C)
        local s = Spots(C)
        if not s or not s.house then return streetWanted.setup(C) end
        C.deferred = true
        C.door = HouseSuspect({ loc = C.loc, profile = 'wanted', C = C, story = 'none' })
    end,
    arrive = function(C)
        if C.door then Notify('This is their address. Go to the ~b~front door~s~ and knock (E) - or force entry if they won\'t come out.') end
    end,
    tick = function(C) if not C.door then return streetWanted.tick(C) end end,
    resolved = function(C)
        if not C.door then return Resolved(C) end
        if not C.door.e then return false end
        return Resolved(C)
    end,
}

-- Hostage: inside the store, or at a house
SCENES.hostage = {
    setup = function(C)
        local s = Spots(C)
        if not s then return streetHostage.setup(C) end
        local spot, h = s.front or (s.walkin and s.inside[1]) or s.yard or FootNear(s.base, 3), s.heading
        local t = Person(C, spot, h, 'hostagetaker', 'suspect', 'none')
        local v = Person(C, spot + vector3(0.5, 0.0, 0.0), h, 'victim', 'victim', 'hostage')
        if not t or not v then return end
        GiveWeaponToPed(t.ped, GetHashKey(t.persona.weapon or 'WEAPON_PISTOL'), 60, false, true)
        t.hostagePed, v.status = v, 'hostage'
        HoldHostage(t, v)
        C.taker, C.victim = t, v
    end,
    arrive = streetHostage.arrive,
    tick = streetHostage.tick,
}

---------------------------------------------------------------------------
-- Investigations: victim + evidence at the scene, then a BOLO / warrant from the Cases tab
---------------------------------------------------------------------------
local function CaseScene(C, storyKey)
    local s = Spots(C)
    local spot = (s and (s.front or (s.house and s.yard))) or FindFoot(C.pos)
    local v = Person(C, spot, 0.0, 'victim', 'victim', storyKey)
    if v then TaskStartScenarioInPlace(v.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true) end
    if math.random() < 0.6 then
        local w = Person(C, FindFoot(C.pos + vector3(8.0, -6.0, 0.0)), 0.0, 'witness', 'witness', 'witness')
        if w then TaskStartScenarioInPlace(w.ped, 'WORLD_HUMAN_SMOKING', 0, true) end
    end
    local r = TriggerCallback('caseOpen', C.key, C.street)
    if not r or not r.ok then return Result(r) end
    C.case, C.caseId = r.id, r.id
    for i, cl in ipairs(r.clues or {}) do
        local p
        if s and s.counter then
            -- inside the store: by the counter and down the aisle
            p = FootNear((i % 2 == 1) and s.front or s.aisle, 2)
        elseif s and s.house then
            p = FootNear((i == 1 and s.door) or (s.back and i == 2 and s.back) or s.yard, 3)
        else
            p = FindFoot(spot + vector3(math.random(-9, 9) + 0.0, math.random(-9, 9) + 0.0, 0.0))
        end
        AddClue(r.id, cl.index, cl.model, cl.label, p)
    end
    if CaseUpdated then CaseUpdated(r.view) end
end

local function CaseResolved(C)
    if not C.caseId or not C.arrived then return false end
    local v = C.view
    if not v then return false end
    local found = 0
    for _, cl in ipairs(v.clues or {}) do if cl.found then found = found + 1 end end
    return #(v.statements or {}) >= 1 and found >= 1
end

for _, key in ipairs({ 'burglary', 'assault_report', 'vehicle_theft', 'robbery_report' }) do
    SCENES[key] = {
        setup = function(C) CaseScene(C, 'witness') end,
        arrive = function(C) Notify('~b~Investigation.~s~ Ask the victim what happened (Talk > What happened?) and examine the evidence (blue markers).') end,
        resolved = CaseResolved,
    }
end

-- The building blocks, for the scenes in client/ai_calls.lua
CalloutScenes = SCENES
CalloutKit = {
    Car = Car, Person = Person, Writhe = Writhe, Wander = Wander, Approach = Approach, Comply = Comply, HandsUp = HandsUp,
    TrackMover = TrackMover, Suspects = Suspects, Resolved = Resolved, Spots = Spots, HoldHostage = HoldHostage, FreeHostage = FreeHostage,
    Profile = Profile, HostageTick = streetHostage.tick, DomesticTick = streetDomestic.tick, CaseScene = CaseScene, CaseResolved = CaseResolved,
}

-- Case file changes (from statements and evidence)
function CaseUpdated(view)
    if not view then return end
    if C and C.caseId == view.id then C.view = view end
    if PcRefresh then PcRefresh() end
    if view.canBolo and not (C and C.boloHinted) then
        if C then C.boloHinted = true end
        Notify('~b~Enough for a description.~s~ Issue a BOLO from the Cases tab in the patrol computer.')
    end
end

-- BOLO: the suspect is out there somewhere
local Hunts = {}
function StartHunt(r, caseId)
    CreateThread(function()
        local pos, heading = FindRoad(300.0, 700.0)
        if not pos then
            TriggerCallback('caseRetry', caseId, 'bolo')
            return Notify('Dispatch couldn\'t place the suspect - try again in a moment.')
        end
        local h = { caseId = caseId, pos = pos, ents = {}, people = {} }
        Hunts[#Hunts + 1] = h
        h.area = AddBlipForRadius(pos.x, pos.y, pos.z, 220.0)
        SetBlipColour(h.area, 1)
        SetBlipAlpha(h.area, 80)
        RadioLine(('Dispatch: all units, BOLO for case %s - suspect last seen near %s.'):format(caseId, Street(pos)))
        Notify('~r~BOLO issued.~s~ The suspect is somewhere in the red area. Check the description in the Cases tab.')
        -- wait until you're close enough for them to exist (or give up after 20 minutes / off duty)
        local giveUp = GetGameTimer() + 1200000
        while #(MyPos() - pos) > 250.0 do
            Wait(1000)
            if not IsPolice or GetGameTimer() > giveUp then
                RemoveBlipSafe(h.area)
                TriggerCallback('caseRetry', caseId, 'bolo')
                Notify('The BOLO for case ' .. caseId .. ' has expired - you can issue it again.')
                return
            end
        end
        local veh
        if r.mode == 'vehicle' then
            veh = SpawnVeh(r.vehModel or PickOne(AI.Cars), pos, heading)
            if veh then
                SetVehicleColours(veh, r.colour or 0, r.colour or 0)
                if r.plate then SetVehicleNumberPlateText(veh, r.plate) end
                h.ents[#h.ents + 1] = veh
            end
        end
        local ped = SpawnPed(r.model, veh and nil or FindFoot(pos), 0.0, veh, veh and -1 or nil)
        if not ped then return end
        h.ents[#h.ents + 1] = ped
        local e = Persona(ped, 'suspect', 'public', veh, nil, r.pid)
        if not e then return end
        e.status, e.veh, e.seat, e.hunt = 'free', veh, -1, h
        Hold(ped)
        if veh then TaskVehicleDriveWander(ped, veh, 17.0, 786603) else TaskWanderStandard(ped, 10.0, 10) end
        h.suspect = e
        -- the red area keeps up with them until you get close
        while AIPeds[ped] == e and e.status == 'free' do
            Wait(5000)
            if DoesEntityExist(ped) then
                local p = GetEntityCoords(ped)
                if #(p - MyPos()) < 60.0 then RemoveBlipSafe(h.area) h.area = nil break end
                RemoveBlipSafe(h.area)
                h.area = AddBlipForRadius(p.x + math.random(-50, 50), p.y + math.random(-50, 50), p.z, 180.0)
                SetBlipColour(h.area, 1)
                SetBlipAlpha(h.area, 80)
            end
        end
        RemoveBlipSafe(h.area)
        for _, ent in ipairs(h.ents) do if DoesEntityExist(ent) and not AIPeds[ent] then SetEntityAsNoLongerNeeded(ent) end end
        for i, x in ipairs(Hunts) do if x == h then table.remove(Hunts, i) break end end
    end)
end

-- Warrant service: knock on the door
function StartWarrant(r, caseId)
    if r.loc and r.loc.house and HouseSuspect then
        local loc = r.loc
        local door = vector3(loc.x, loc.y, loc.z)
        local blip = AddBlipForCoord(door.x, door.y, door.z)
        SetBlipSprite(blip, 40)
        SetBlipColour(blip, 1)
        SetBlipRoute(blip, true)
        NamedBlip(blip, 'Warrant: ' .. (r.title or caseId))
        RadioLine(('Dispatch: %s, warrant for case %s approved. Suspect\'s address is %s, %s.'):format(Callsign(), caseId, loc.label, Street(door)))
        Notify('~g~Warrant approved.~s~ Go to the address, knock and announce. Force entry if they won\'t come out.')
        local d = HouseSuspect({ loc = loc, model = r.model, bind = r.pid, profile = 'public' })
        CreateThread(function()
            local giveUp = GetGameTimer() + 1200000
            while not d.e and GetGameTimer() < giveUp and IsPolice do Wait(1000) end
            SetBlipRoute(blip, false)
            if not d.e then
                RemoveBlipSafe(blip)
                CancelHouse(d)
                TriggerCallback('caseRetry', caseId, 'serve')
                return Notify('You didn\'t serve the warrant for case ' .. caseId .. ' - you can try again from the Cases tab.')
            end
            while not d.done do Wait(1000) end
            RemoveBlipSafe(blip)
        end)
        return
    end
    CreateThread(function()
        local pos = FindRoad(300.0, 800.0)
        if not pos then
            TriggerCallback('caseRetry', caseId, 'serve')
            return Notify('Couldn\'t find the address - try again.')
        end
        local door = FindFoot(pos)
        local blip = AddBlipForCoord(door.x, door.y, door.z)
        SetBlipSprite(blip, 40)
        SetBlipColour(blip, 1)
        SetBlipRoute(blip, true)
        NamedBlip(blip, 'Warrant: ' .. (r.title or caseId))
        RadioLine(('Dispatch: %s, warrant for case %s approved. Suspect\'s address is %s.'):format(Callsign(), caseId, Street(door)))
        Notify('~g~Warrant approved.~s~ Go to the address and arrest the suspect.')
        local giveUp = GetGameTimer() + 1200000
        while #(MyPos() - door) > 120.0 do
            Wait(1000)
            if not IsPolice or GetGameTimer() > giveUp then
                RemoveBlipSafe(blip)
                TriggerCallback('caseRetry', caseId, 'serve')
                return Notify('You didn\'t serve the warrant for case ' .. caseId .. ' - you can try again from the Cases tab.')
            end
        end
        local ped = SpawnPed(r.model, door, 0.0)
        if not ped then RemoveBlipSafe(blip) return end
        local e = Persona(ped, 'suspect', 'public', nil, nil, r.pid)
        if not e then RemoveBlipSafe(blip) return end
        Hold(ped)
        e.status = 'free'
        TaskStartScenarioInPlace(ped, PickOne({ 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_DRINKING' }), 0, true)
        while AIPeds[ped] == e and e.status == 'free' and Dist(ped, Me()) > 14.0 do Wait(500) end
        SetBlipRoute(blip, false)
        RemoveBlipSafe(blip)
        if AIPeds[ped] == e and e.status == 'free' then
            local act = AIReact(e, 'approach')
            if not ApplyReaction(e, act) then HoldOnFoot(e) Notify('They\'re at the door. Arrest them.') end
        end
    end)
end

RegisterNetEvent(EV .. 'aiWarrant', function(d)
    if d.status == 'approved' then
        Notify(('~g~Judge approved the warrant~s~ for case %s. Serve it from the Cases tab.'):format(d.id))
        RadioLine(('Dispatch: warrant approved for case %s.'):format(d.id))
    else
        Notify(('~r~Judge denied the warrant~s~ for case %s - not enough evidence.'):format(d.id))
    end
    if PcRefresh then PcRefresh() end
end)

---------------------------------------------------------------------------
-- On-view incidents: things that happen in front of you between callouts
---------------------------------------------------------------------------
local ONVIEW = {
    { key = 'speeder', title = 'Speeding vehicle' }, { key = 'drunk_driver', title = 'Vehicle weaving across lanes' },
    { key = 'mugging', title = 'Robbery in progress' }, { key = 'drug_deal', title = 'Suspected drug deal' },
    { key = 'fight', title = 'Fight in the street' }, { key = 'suspicious', title = 'Suspicious person' },
}
for _, o in ipairs(AI.OnViewExtra or {}) do ONVIEW[#ONVIEW + 1] = o end
CreateThread(function()
    local cfg = AI.OnView or {}
    if cfg.enabled == false then return end
    local nextAt = GetGameTimer() + math.random(cfg.every[1], cfg.every[2]) * 1000
    while true do
        Wait(5000)
        if OnPatrol and IsPolice and not C and GetGameTimer() >= nextAt then
            nextAt = GetGameTimer() + math.random(cfg.every[1], cfg.every[2]) * 1000
            local busy = false
            for _, e in pairs(AIPeds) do if e.status ~= 'free' and e.status ~= 'dead' then busy = true end end
            if not busy and math.random() < (cfg.chance or 0.5) and IsPedInAnyVehicle(Me(), false) then
                local pick = ONVIEW[math.random(1, #ONVIEW)]
                if not SCENES[pick.key] then pick = ONVIEW[1] end
                RunCallout({ key = pick.key, title = pick.title, code = 2, text = 'You saw it happen.', onview = true, dist = { 110, 220 } })
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Running a callout
---------------------------------------------------------------------------
local function Hud()
    if not OnPatrol then return SendNUIMessage({ action = 'aiHud', data = { on = false } }) end
    SendNUIMessage({ action = 'aiHud', data = { on = true, callout = C and { title = C.def.title, code = C.def.code, street = C.street, arrived = C.arrived, clear = C.clear,
        incident = C.def.incident } or nil } })
end
AIHud = Hud

function EndCallout(done)
    if not C then return end
    local c = C
    C = nil
    CurrentCallout = nil
    RemoveBlipSafe(c.blip)
    RemoveBlipSafe(c.area)
    RemoveBlipSafe(c.exact)
    if c.door and CancelHouse then CancelHouse(c.door) end
    local sc = SCENES[c.key]
    if sc and sc.cleanup then
        local ok, err = pcall(sc.cleanup, c)
        if not ok then print('[statewide_police] callout cleanup error: ' .. tostring(err)) end
    end
    -- tidy up: anyone still in your hands stays; everyone else goes about their day
    for _, e in ipairs(c.people) do
        if AIPeds[e.ped] == e then
            local s = e.status
            if not (s == 'cuffed' or s == 'escorted' or s == 'seated' or s == 'pursuit' or s == 'fleeing' or s == 'fighting') then
                if s == 'dead' then Untrack(e) else Release(e) end
            end
        end
    end
    for _, ent in ipairs(c.ents) do
        if DoesEntityExist(ent) and not AIPeds[ent] and not IsEntityAttached(ent) then
            if Dist(ent, Me()) > 120.0 then Vanish(ent) else SetEntityAsNoLongerNeeded(ent) end
        end
    end
    CreateThread(function()
        local r = TriggerCallback('calloutEnd', done == true)
        if PcRefresh then PcRefresh(r) end
    end)
    Notify(done and '~g~Code 4~s~ - callout closed.' or 'Callout closed.')
    if done then RadioLine(Callsign() .. ': Code 4, back in service.', true) end
    if c.case and ClearClues then
        -- clues stay for a while in case you come back
        local id = c.case
        SetTimeout(600000, function() ClearClues(id) end)
    end
    Hud()
end

function RunCallout(def)
    local scene = SCENES[def.key]
    if not scene then
        Notify('That callout isn\'t set up yet.')
        TriggerCallback('calloutEnd', false)
        return
    end
    local range = def.dist or AI.CalloutDistance
    local pos, heading
    if def.loc then
        pos, heading = vector3(def.loc.x, def.loc.y, def.loc.z), def.loc.w or 0.0
    else
        pos, heading = FindRoad(range[1], range[2])
    end
    if not pos then
        Notify('Dispatch couldn\'t give a location - callout cancelled.')
        TriggerCallback('calloutEnd', false)
        return
    end
    C = { def = def, key = def.key, pos = pos, heading = heading, ents = {}, people = {}, started = GetGameTimer(),
        loc = def.loc, street = def.loc and (def.loc.label .. ', ' .. Street(pos)) or Street(pos) }
    CurrentCallout = C
    local c = C
    c.blip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipColour(c.blip, def.code == 3 and 1 or 5)
    if not def.onview then
        SetBlipRoute(c.blip, true)
        SetBlipRouteColour(c.blip, def.code == 3 and 1 or 5)
    end
    NamedBlip(c.blip, def.title)
    c.notes = {}
    if def.onview then
        RadioLine(('%s: on-view, %s near %s.'):format(Callsign(), def.title:lower(), c.street))
    else
        local nature = def.nature and (' (' .. def.nature .. ')') or ''
        local inc = def.incident and (', incident ' .. def.incident) or ''
        RadioLine(('Dispatch: %s, respond Code %d - %s%s, %s%s.'):format(Callsign(), def.code, def.title:lower(), nature, c.street, inc))
        SetTimeout(2500, function() if C == c then RadioLine(Callsign() .. ': copy, en route.', true) end end)
        -- caller updates while you drive
        if AI.CAD and AI.CAD.Updates ~= false and def.notes and #def.notes > 0 then
            local pool = {}
            for _, n in ipairs(def.notes) do pool[#pool + 1] = n end
            local count = math.min(#pool, math.random(1, 2))
            for i = 1, count do
                local note = table.remove(pool, math.random(1, #pool))
                SetTimeout(9000 + (i - 1) * 16000 + math.random(0, 6000), function()
                    if C ~= c or c.arrived then return end
                    c.notes[#c.notes + 1] = { t = GetClockHours() .. ':' .. ('%02d'):format(GetClockMinutes()), text = note }
                    local tpl = AI.Lines.cad_update and AI.Lines.cad_update[math.random(1, #AI.Lines.cad_update)] or 'Dispatch: %s, update on %s - %s'
                    RadioLine(tpl:format(Callsign(), def.incident or def.title:lower(), note))
                end)
            end
        end
    end
    if scene.moving and not def.onview then
        c.area = AddBlipForRadius(pos.x, pos.y, pos.z, 140.0)
        SetBlipColour(c.area, 5)
        SetBlipAlpha(c.area, 90)
    end
    Notify(('~%s~Code %d:~s~ %s - %s'):format(def.code == 3 and 'r' or 'y', def.code, def.title, c.street))
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', true)
    Hud()
    CreateThread(function()
        while C == c do
            Wait(500)
            local d = #(MyPos() - c.pos)
            if not c.spawned and d < (scene.spawnAt or 260.0) then
                c.spawned = true
                local ok, err = pcall(scene.setup, c)
                if not ok then print('[statewide_police] callout setup error: ' .. tostring(err)) end
                if #c.ents == 0 and not c.deferred then
                    Notify('Dispatch: the caller has gone - callout closed.')
                    EndCallout(false)
                    return
                end
            end
            if c.spawned and not c.arrived and (d < AI.ArriveDistance or (c.exact and DoesBlipExist(c.exact))) then
                c.arrived, c.arrivedAt = true, GetGameTimer()
                if c.blip then SetBlipRoute(c.blip, false) end
                if scene.arrive then pcall(scene.arrive, c) end
                Notify('~b~On scene.~s~ Hold ~INPUT_CONTEXT~ next to someone to stop them, tap it to talk.')
                if not def.onview then
                    RadioLine(Callsign() .. ': 10-23, on scene.', true)
                    if def.incident then CreateThread(function() TriggerCallback('cadOnScene') end) end
                end
                -- units dispatch rolls automatically for this kind of call
                if def.units and RequestUnit then
                    for i, kind in ipairs(def.units) do
                        if AI.Units[kind] then
                            SetTimeout(1500 + i * 1200, function()
                                if C ~= c then return end
                                RadioLine(('Dispatch: %s, %s is en route to you.'):format(Callsign(), AI.Units[kind].label:lower()))
                                RequestUnit(kind, {})
                            end)
                        end
                    end
                end
                Hud()
            end
            if c.spawned and scene.tick then
                local ok, err = pcall(scene.tick, c)
                if not ok then print('[statewide_police] callout tick error: ' .. tostring(err)) end
            end
            if c.spawned and not c.clear then
                local done = scene.resolved and scene.resolved(c) or (not scene.resolved and Resolved(c))
                if done then
                    c.clear = true
                    Notify('~g~Scene clear.~s~ Finish up, then press Code 4 in the patrol computer (' .. AI.Keys.computer .. ') or type /code4.')
                    Hud()
                end
            end
            if c.clear and d > AI.LeaveSceneDistance then EndCallout(true) end
        end
    end)
end

---------------------------------------------------------------------------
-- Offers from dispatch
---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'aiOffer', function(offer)
    if not IsPolice then return end
    pendingOffer = offer
    OnPatrol = true
    SendNUIMessage({ action = 'aiOffer', data = offer, key = AI.Keys.accept })
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
end)

RegisterNetEvent(EV .. 'aiOfferGone', function(id)
    if pendingOffer and pendingOffer.id == id then
        pendingOffer = nil
        SendNUIMessage({ action = 'aiOfferGone' })
    end
end)

RegisterNetEvent(EV .. 'aiPatrolOff', function()
    OnPatrol = false
    pendingOffer = nil
    SendNUIMessage({ action = 'aiOfferGone' })
    Hud()
    Notify('AI patrol switched off (you went off duty).')
end)

function AcceptOffer()
    local o = pendingOffer
    if not o then return end
    pendingOffer = nil
    SendNUIMessage({ action = 'aiOfferGone' })
    if C then return Notify('Finish your current callout first (Code 4).') end
    local r = TriggerCallback('calloutAccept', o.id)
    if not Result(r) then return end
    RunCallout(r.callout)
end

function DeclineOffer()
    local o = pendingOffer
    if not o then return end
    pendingOffer = nil
    SendNUIMessage({ action = 'aiOfferGone' })
    CreateThread(function() TriggerCallback('calloutDecline', o.id) end)
end

RegisterCommand('+swai_accept', function()
    -- an officer asking for backup takes priority over an AI callout
    if BackupPending and BackupPending() then CreateThread(RespondBackup)
    elseif pendingOffer then CreateThread(AcceptOffer) end
end, false)
RegisterCommand('-swai_accept', function() end, false)
RegisterKeyMapping('+swai_accept', 'Statewide PD: accept a callout / respond to a backup request', 'keyboard', AI.Keys.accept)

RegisterCommand('code4', function()
    if C then EndCallout(true) else Notify('You\'re not on a callout.') end
end, false)

function CalloutInfo()
    if not C then return nil end
    local s = {}
    for _, e in ipairs(C.people) do
        if AIPeds[e.ped] == e then s[#s + 1] = { role = e.role, status = e.status, name = e.persona and e.persona.name or nil } end
    end
    return { title = C.def.title, code = C.def.code, text = C.def.text, street = C.street, arrived = C.arrived == true, clear = C.clear == true,
        people = s, minutes = math.floor((GetGameTimer() - C.started) / 60000), incident = C.def.incident, nature = C.def.nature,
        prio = C.def.prio, notes = C.notes or {} }
end

function CalloutRoute()
    if C and C.blip and DoesBlipExist(C.blip) then SetBlipRoute(C.blip, true) end
end
