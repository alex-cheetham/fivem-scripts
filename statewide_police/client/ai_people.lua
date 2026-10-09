-- Statewide PD: the people side on the client - reaching for things, body language, interfering passengers,
-- bystanders filming, force reporting, interpreters, crisis calls, child services.
local A = ACTIONS_AI
local PC = AI.People or {}

local function Alive(p) return p and DoesEntityExist(p) and not IsPedDeadOrDying(p, true) end
local function Restrained(e) return e.status == 'cuffed' or e.status == 'escorted' or e.status == 'seated' or e.status == 'cuffing' end
local function LineC(key)
    local pool = AI.Lines[key]
    if not pool or #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

---------------------------------------------------------------------------
-- Reaching: a 2-second decision. Aim at them, or let them carry on.
---------------------------------------------------------------------------
local REACH_DICT, REACH_ANIM = 'reaction@intimidation@1h', 'intro'

function ReachFor(e)
    local ped = e.ped
    if not Control(ped) then return end
    ClosePanelAI()
    e.reachAt = GetGameTimer()
    e.reachWhat = e.reach
    local inVeh = IsPedInAnyVehicle(ped, false)
    if not inVeh and LoadDict(REACH_DICT) then
        ClearPedTasks(ped)
        TaskPlayAnim(ped, REACH_DICT, REACH_ANIM, 4.0, -4.0, 2200, 48, 0.0, false, false, false)
    end
    SendNUIMessage({ action = 'aiReach', seconds = 2 })
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    local aimed = false
    local t = GetGameTimer() + 2000
    while GetGameTimer() < t do
        if PlayerAimingAtPed and PlayerAimingAtPed(ped) then aimed = true break end
        if not Alive(ped) then break end
        Wait(0)
    end
    SendNUIMessage({ action = 'aiReachDone' })
    if not Alive(ped) then return end
    local r = TriggerCallback('aiReachResolve', e.pid, aimed)
    if not r or not r.ok then return end
    if r.persona then e.persona = r.persona end
    if r.say then Say(e, r.say) end
    if r.result == 'draw' then
        local w = (e.persona and (e.persona.weapon or e.persona.melee)) or 'WEAPON_PISTOL'
        if Control(ped, 300) then GiveWeaponToPed(ped, GetHashKey(w), 60, false, true) end
        Fight(e)
        RadioLine(Callsign() .. ': suspect has drawn a weapon!')
    elseif r.result == 'drop' then
        if Control(ped, 300) then RemoveAllPedWeapons(ped, true) end
        Surrender(e, true)
        Notify('~g~You stopped them.~s~ They had a weapon - it\'s on the floor. Cuff them.')
        e.pc = true
    elseif r.result == 'freeze' then
        if Control(ped, 300) and not inVeh then ClearPedTasks(ped) TaskHandsUp(ped, 4000, Me(), -1, true) end
        Notify('It was only their ' .. (r.what or 'wallet') .. '.')
        SetTimeout(4200, function() if AIPeds[ped] == e and e.status ~= 'fleeing' and not inVeh then HoldOnFoot(e) end end)
    else
        Notify('They took out their ' .. (r.what or 'wallet') .. '.')
        if r.what == 'wallet' then e.noId = false end
        if not inVeh then HoldOnFoot(e) end
    end
end

---------------------------------------------------------------------------
-- Force: hurting someone who wasn't a threat gets reported (Internal Affairs decide)
---------------------------------------------------------------------------
local function ForceKind(e)
    local ped = e.ped
    local tased = HasEntityBeenDamagedByWeapon(ped, GetHashKey('WEAPON_STUNGUN'), 0)
    local melee = HasEntityBeenDamagedByWeapon(ped, 0, 1)
    if Restrained(e) then return 'restrained' end
    if e.reachAt and GetGameTimer() - e.reachAt < 6000 and e.reachWhat ~= 'weapon' and not tased and not melee then return 'shot_reaching' end
    if e.status == 'held' or e.status == 'surrendered' or e.status == 'following' then
        if tased then return 'tased' end
        if melee then return 'compliant' end
        return 'shot_unarmed'
    end
    return nil
end

CreateThread(function()
    while true do
        Wait(250)
        local me = Me()
        for ped, e in pairs(AIPeds) do
            if e.pid and DoesEntityExist(ped) and HasEntityBeenDamagedByEntity(ped, me, true) then
                local kind = ForceKind(e)
                ClearEntityLastDamageEntity(ped)
                if kind then
                    local pid = e.pid
                    CreateThread(function() TriggerCallback('aiForce', pid, kind) end)
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Body language: people show what they're hiding (if you're watching)
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(3500)
        local me = Me()
        local mypos = GetEntityCoords(me)
        for ped, e in pairs(AIPeds) do
            local cues = e.persona and e.persona.cues
            if cues and #cues > 0 and e.status == 'held' and DoesEntityExist(ped) and #(GetEntityCoords(ped) - mypos) < 14.0
                and math.random() < 0.55 and Control(ped, 200) then
                local c = cues[math.random(1, #cues)]
                if c.kind == 'look' then
                    local back = GetOffsetFromEntityInWorldCoords(ped, math.random(-8, 8) + 0.0, -10.0, 0.0)
                    TaskLookAtCoord(ped, back.x, back.y, back.z, 2500, 0, 2)
                elseif c.kind == 'car' and e.veh and DoesEntityExist(e.veh) then
                    TaskLookAtEntity(ped, e.veh, 2500, 0, 2)
                elseif c.kind == 'waist' or c.kind == 'pocket' then
                    local low = GetOffsetFromEntityInWorldCoords(ped, 0.2, 0.3, -0.6)
                    TaskLookAtCoord(ped, low.x, low.y, low.z, 1500, 0, 2)
                elseif c.kind == 'eyes' or c.kind == 'nervous' then
                    local away = GetOffsetFromEntityInWorldCoords(ped, 3.0, 2.0, 0.0)
                    TaskLookAtCoord(ped, away.x, away.y, away.z, 2000, 0, 2)
                end
                if not e.cueNoticed then
                    e.cueNoticed = true
                    Notify('~y~You notice:~s~ ' .. c.text:lower() .. '.')
                end
            end
            -- terrified people put their hands up when a gun is pointed at them
            if e.status == 'held' and e.persona and (e.persona.fear or 0) >= 70 and PlayerAimingAtPed and PlayerAimingAtPed(ped)
                and not IsPedInAnyVehicle(ped, false) and not e.handsUp and Control(ped, 200) then
                e.handsUp = true
                TaskHandsUp(ped, 5000, me, -1, true)
                SetTimeout(5200, function() e.handsUp = nil end)
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Interfering passengers
---------------------------------------------------------------------------
local function Shout(e)
    local l = LineC('interfere')
    if l then Say(e, l) end
end

CreateThread(function()
    while true do
        Wait(1000)
        local me = Me()
        local now = GetGameTimer()
        local onFoot = not IsPedInAnyVehicle(me, false)
        for ped, e in pairs(AIPeds) do
            if e.role == 'passenger' and e.persona and e.persona.interfere and e.status == 'held' and DoesEntityExist(ped) then
                e.heldAt = e.heldAt or now
                if not e.interfering and onFoot and now - e.heldAt > (e.interfereDelay or 0) and Dist(ped, me) < 30.0 then
                    e.interfereDelay = e.interfereDelay or math.random(15000, 35000)
                    if now - e.heldAt > e.interfereDelay and Control(ped, 400) then
                        e.interfering = true
                        e.nextShout = now
                        if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 256) end
                        Notify('~o~The passenger is getting out!~s~ Order them back in the car (stop menu > Orders).')
                        if math.random() < 0.5 then e.filming = true end
                    end
                elseif e.interfering and Control(ped, 200) then
                    if not IsPedInAnyVehicle(ped, false) then
                        if Dist(ped, me) > 4.0 then
                            if now > (e.walkTask or 0) then e.walkTask = now + 4000 TaskGoToEntity(ped, me, -1, 3.0, 1.2, 1073741824, 0) end
                        elseif e.filming and not IsPedUsingScenario(ped, 'WORLD_HUMAN_MOBILE_FILM_SHOCKING') then
                            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 0, true)
                            if not e.filmReported then
                                e.filmReported = true
                                for _, o in pairs(AIPeds) do
                                    if o.veh and o.veh == e.veh and o.pid then local pid = o.pid CreateThread(function() TriggerCallback('aiFilming', pid) end) end
                                end
                            end
                        else
                            TaskTurnPedToFaceEntity(ped, me, 1000)
                        end
                        if now > (e.nextShout or 0) then e.nextShout = now + math.random(7000, 12000) Shout(e) end
                    end
                end
            end
        end
    end
end)

A.backoff = function(e)
    OfficerSay(e, 'Get back in the vehicle. Now. This doesn\'t involve you.')
    local r = TriggerCallback('aiBackoff', e.pid)
    if not r or not r.ok then return Result(r) end
    if r.persona then e.persona = r.persona end
    Say(e, r.say)
    if r.msg then Notify(r.msg) end
    if r.comply then
        e.interfering, e.filming = false, false
        ClosePanelAI()
        local ped = e.ped
        if Control(ped, 400) then
            ClearPedTasks(ped)
            if e.veh and DoesEntityExist(e.veh) then
                TaskEnterVehicle(ped, e.veh, 10000, e.seat or 0, 1.0, 1, 0)
                SetTimeout(9000, function() if AIPeds[ped] == e and IsPedInAnyVehicle(ped, false) then HoldInVehicle(e) end end)
            else
                HoldOnFoot(e)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Bystanders film stops in town
---------------------------------------------------------------------------
local bystander = nil   -- { ped, near, until }

local function StopCentre()
    for ped, e in pairs(AIPeds) do
        if e.status == 'held' and DoesEntityExist(ped) and Dist(ped, Me()) < 30.0 then return e end
    end
    return nil
end

local function BusyStreet(pos)
    local n = 0
    for _, p in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(p) and #(GetEntityCoords(p) - pos) < 60.0 then n = n + 1 end
    end
    return n >= 3
end

CreateThread(function()
    while true do
        Wait(4000)
        if bystander then
            local e = StopCentre()
            if not e or GetGameTimer() > bystander.untilT or not DoesEntityExist(bystander.ped) then
                local b = bystander.ped
                bystander = nil
                if DoesEntityExist(b) and Control(b, 300) then ClearPedTasks(b) TaskWanderStandard(b, 10.0, 10) end
                SetTimeout(20000, function() Vanish(b) end)
            elseif not IsPedUsingScenario(bystander.ped, 'WORLD_HUMAN_MOBILE_FILM_SHOCKING') and Control(bystander.ped, 200) then
                TaskTurnPedToFaceEntity(bystander.ped, e.ped, 1000)
                SetTimeout(1100, function()
                    if bystander and DoesEntityExist(bystander.ped) and Control(bystander.ped, 200) then
                        TaskStartScenarioInPlace(bystander.ped, 'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 0, true)
                    end
                end)
            end
        elseif IsPolice then
            local e = StopCentre()
            if e and not e.filmRolled then
                -- one roll per stop
                for _, o in pairs(AIPeds) do if o.veh and o.veh == e.veh then o.filmRolled = true end end
                e.filmRolled = true
                local pos = GetEntityCoords(e.ped)
                if math.random() < (PC.FilmingChance or 0.35) and BusyStreet(pos) then
                    local spot = FindFoot(pos + vector3(math.random(-18, 18) + 0.0, math.random(-18, 18) + 0.0, 0.0))
                    local ped = SpawnPed(PickOne(AI.Peds), spot, 0.0)
                    if ped then
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        SetPedKeepTask(ped, true)
                        TaskTurnPedToFaceEntity(ped, e.ped, 1500)
                        SetTimeout(1600, function() if DoesEntityExist(ped) then TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 0, true) end end)
                        bystander = { ped = ped, untilT = GetGameTimer() + 360000 }
                        Notify('~y~Someone is filming you.~s~ Stay professional.')
                        for _, o in pairs(AIPeds) do
                            if o.pid and (o == e or (o.veh and o.veh == e.veh)) then local pid = o.pid CreateThread(function() TriggerCallback('aiFilming', pid) end) end
                        end
                    end
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Interpreter line
---------------------------------------------------------------------------
A.interpreter = function(e)
    OfficerSay(e, 'One moment - I\'m getting an interpreter on the phone.')
    if not Action('Calling the language line', 6000, 'holdDevice', { 'phone' }) then return end
    local r = TriggerCallback('aiInterpreter', e.pid)
    if not Result(r) then return end
    if r.persona then e.persona = r.persona end
    Say(e, r.say)
    OpenPanelAI(e)
end

---------------------------------------------------------------------------
-- Children in the car
---------------------------------------------------------------------------
local Children = {}   -- [pid] = { veh, cared }

CreateThread(function()
    while true do
        Wait(2000)
        for ped, e in pairs(AIPeds) do
            if e.pid and e.persona and e.persona.child and not e.persona.childCared and not Children[e.pid] then
                Children[e.pid] = { veh = e.veh, entry = e, at = GetGameTimer() }
            end
        end
        -- forget children whose parent drove away (released and gone) or were dealt with long ago
        for pid, c in pairs(Children) do
            local e = c.entry
            local gone = not e or AIPeds[e.ped] ~= e
            if c.cared or (gone and not c.arrested and GetGameTimer() - (c.at or 0) > 60000) or GetGameTimer() - (c.at or 0) > 1800000 then Children[pid] = nil
            elseif e and (e.status == 'cuffed' or e.status == 'escorted' or e.status == 'seated') then c.arrested = true end
        end
    end
end)

A.relative = function(e)
    if not e.persona or not e.persona.child then return end
    local pid = e.pid
    local rr = TriggerCallback('aiRelative', pid)
    if not rr or not rr.ok then return Result(rr) end
    OfficerSay(e, 'Is there someone who can come and collect the children?')
    Say(e, 'My sister... she lives close. Please call her.')
    Notify('A relative is on the way to collect the child (about 90 seconds). Stay with the vehicle.')
    SetTimeout(90000, function()
        local r = TriggerCallback('aiChildCared', pid, 'family')
        if r and r.ok then
            if Children[pid] then Children[pid].cared = true end
            Notify('~g~A relative has collected the child.')
            RadioLine(Callsign() .. ': child released to a family member.', true)
        end
    end)
end

---------------------------------------------------------------------------
-- Crisis calls
---------------------------------------------------------------------------
local CRISIS_TEXT = {
    listen = 'I\'m here. I\'m listening. Tell me what\'s going on.',
    calm = 'Take a breath with me. Nobody\'s going to rush you.',
    time = 'We\'ve got all the time you need. No hurry.',
    family = 'Is there someone you\'d like me to call for you?',
    promise = 'I promise you\'re not in trouble. I just want you safe.',
    demand = 'Put it down and get on the ground. Now!',
    clinician = 'This is a mental health nurse. They\'re here to help you.',
}

local oldNego = A.nego
A.nego = function(e, d)
    if not (e.persona and e.persona.crisis) then return oldNego(e, d) end
    local opt = tostring(d.opt or '')
    if not CRISIS_TEXT[opt] then return end
    OfficerSay(e, CRISIS_TEXT[opt])
    local r = TriggerCallback('aiNego', e.pid, opt)
    if not r or not r.ok then return Result(r) end
    if r.persona then e.persona = r.persona end
    Say(e, r.say)
    if r.outcome then
        ClosePanelAI()
        local ped = e.ped
        if r.outcome == 'help' then
            if Control(ped, 400) then RemoveAllPedWeapons(ped, true) ClearPedTasks(ped) end
            HoldOnFoot(e)
            e.status = 'held'
            Notify('~g~They\'ve agreed to get help.~s~ Use Outcome > Voluntary assessment.')
            RadioLine(Callsign() .. ': subject has calmed down and agreed to an assessment.', true)
        else
            ApplyReaction(e, r.outcome)
        end
    end
end

A.hospital = function(e)
    local r = TriggerCallback('aiHospital', e.pid)
    if not Result(r) then return end
    if r.say then Say(e, r.say) end
    ClosePanelAI()
    e.hospitalised = true
    local ped = e.ped
    -- the crisis team takes them; otherwise they're collected
    local team
    for _, u in ipairs(SWUnits or {}) do if u.kind == 'crisis' and u.state ~= 'leaving' and u.veh ~= 0 and DoesEntityExist(u.veh) then team = u end end
    CreateThread(function()
        Untrack(e)
        if team and Control(ped, 500) then
            TaskEnterVehicle(ped, team.veh, 15000, IsVehicleSeatFree(team.veh, 1) and 1 or 2, 1.0, 1, 0)
            local t = GetGameTimer() + 15000
            while DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) and GetGameTimer() < t do Wait(300) end
            team.cargo = team.cargo or {}
            team.cargo[#team.cargo + 1] = ped
            if UnitBoard then UnitBoard(team) end
            Wait(5000)
            if UnitLeave then UnitLeave(team) end
        else
            Notify('A crisis team car is collecting them.')
            if Control(ped, 500) then TaskWanderStandard(ped, 10.0, 10) end
            Wait(8000)
            Vanish(ped)
        end
    end)
end

---------------------------------------------------------------------------
-- When the crisis team / child services arrive
---------------------------------------------------------------------------
function PeopleUnitArrive(u)
    local d = UnitDriver and UnitDriver(u)
    if UnitGetOut then UnitGetOut(u) end
    Wait(2000)
    if u.kind == 'crisis' then
        local target
        for ped, e in pairs(AIPeds) do
            if e.persona and (e.persona.crisis or e.persona.voluntary) and Dist(ped, u.veh) < 120.0 then target = e end
        end
        if not target then
            Notify('Mental health team: there\'s nobody here for us.')
            return UnitLeave(u)
        end
        local r = TriggerCallback('aiCrisisTeam', target.pid)
        if r and r.persona then target.persona = r.persona end
        Notify('~b~Mental health team~s~ is on scene. Let the clinician talk to them (Negotiate tab).')
        RadioLine('Crisis team: on scene with ' .. Callsign() .. '.', true)
        for _, p in ipairs(u.crew) do
            if Alive(p) and Control(p, 300) then
                local spot = GetOffsetFromEntityInWorldCoords(target.ped, math.random(-4, 4) + 0.0, -6.0, 0.0)
                TaskGoToCoordAnyMeans(p, spot.x, spot.y, spot.z, 1.2, 0, false, 786603, 0.0)
                SetTimeout(7000, function() if Alive(p) and Control(p, 300) then TaskStartScenarioInPlace(p, 'WORLD_HUMAN_CLIPBOARD', 0, true) end end)
            end
        end
        u.waitUntil = GetGameTimer() + 600000
        CreateThread(function()
            while u.state ~= 'leaving' and GetGameTimer() < u.waitUntil do Wait(2000) end
            if u.state ~= 'leaving' then UnitLeave(u) end
        end)
    elseif u.kind == 'cps' then
        local best, bd
        local want = u.data and u.data.entry and u.data.entry.pid
        if want and Children[want] and not Children[want].cared then best, bd = want, 0 end
        for pid, c in pairs(best and {} or Children) do
            if not c.cared and c.arrested then
                local pos = (c.veh and DoesEntityExist(c.veh)) and GetEntityCoords(c.veh) or MyPos()
                local dd = #(pos - GetEntityCoords(u.veh))
                if not bd or dd < bd then best, bd = pid, dd end
            end
        end
        if not best then
            Notify('Child & Family Services: there\'s no child here who needs us.')
            return UnitLeave(u)
        end
        local c = Children[best]
        if d and Control(d, 400) then
            local to = (c.veh and DoesEntityExist(c.veh)) and GetOffsetFromEntityInWorldCoords(c.veh, -1.8, -0.5, 0.0) or MyPos()
            TaskGoToCoordAnyMeans(d, to.x, to.y, to.z, 1.2, 0, false, 786603, 0.0)
            local t = GetGameTimer() + 20000
            while Alive(d) and #(GetEntityCoords(d) - to) > 2.0 and GetGameTimer() < t do Wait(300) end
            TaskStartScenarioInPlace(d, 'WORLD_HUMAN_CLIPBOARD', 0, true)
            Wait(8000)
            ClearPedTasks(d)
        end
        local r = TriggerCallback('aiChildCared', best, 'cps')
        if r and r.ok then
            c.cared = true
            Notify('~g~Child & Family Services~s~ have taken care of the child.')
            RadioLine('CFS: we have the child, thank you officer.', true)
        end
        UnitLeave(u)
    end
end

---------------------------------------------------------------------------
-- Messages from Internal Affairs
---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'aiComplaint', function(c)
    SendNUIMessage({ action = 'aiToast', kind = 'bad', title = 'Complaint ' .. c.id .. ' - ' .. c.kind, text = c.text .. '. Answer it in the patrol computer (Conduct).' })
end)

RegisterNetEvent(EV .. 'aiCommend', function(text)
    SendNUIMessage({ action = 'aiToast', kind = 'good', title = 'Commendation', text = text })
    PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
end)

RegisterNetEvent(EV .. 'aiIADecision', function(d)
    local good = d.outcome ~= 'sustained'
    SendNUIMessage({ action = 'aiToast', kind = good and 'good' or 'bad', title = 'Internal Affairs - ' .. d.id,
        text = ('%s: %s.'):format(d.kind, d.outcome:upper()) .. (good and '' or ' XP deducted.') })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if bystander and DoesEntityExist(bystander.ped) then DeleteEntity(bystander.ped) end
end)
