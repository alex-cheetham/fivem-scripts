-- AI patrol: traffic stops, pedestrian stops and everything you can do with the people you stop
local penal = nil
local function PenalCode()
    if not penal then
        local r = TriggerCallback('penalCode')
        if r and r.ok then penal = { code = r.code, maxJail = r.maxJail } end
    end
    return penal
end

-- What the officer says for each question (the answers come from the server)
QUESTION_TEXT = {
    why = 'Do you know why I stopped you?',
    where = 'Where are you heading today?',
    from = 'Where are you coming from?',
    drink = 'Have you had anything to drink today?',
    drugs = 'Have you taken any drugs?',
    illegal = 'Is there anything illegal on you or in the vehicle?',
    weapons = 'Do you have any weapons on you?',
    owner = 'Is this your vehicle?',
    story = 'Can you tell me what happened here?',
    calm = 'I need you to calm down for me.',
    leave = 'You need to leave this property now.',
    where_who = 'Who are you meeting there?',
    where_why = 'What are you going there for?',
    from_long = 'How long were you there?',
    drink_count = 'How many drinks exactly?',
    drink_when = 'When was your last drink?',
    drugs_what = 'What did you take, and when?',
    illegal_again = 'I\'m going to ask you one more time - is there anything I should know about?',
    weapons_again = 'Last chance - anything sharp, anything that\'s going to hurt me?',
    owner_name = 'What\'s the registered owner\'s name?',
    honest = 'Be straight with me and this will go a lot easier for you.',
    anything = 'Is there anything you want to tell me before I find it myself?',
    warrant = 'Did you know you\'ve got a warrant out for your arrest?',
}
local FIRM = { why = 'You know exactly why I stopped you, don\'t you?', where = 'Where are you going? Don\'t lie to me.',
    drink = 'How much have you had to drink tonight?', illegal = 'What\'s in the car I\'m going to find?', weapons = 'Are you carrying? Tell me now.' }
local CONFRONT = { drink = 'You told me you hadn\'t been drinking. The breathalyser says otherwise.', drugs = 'You said no drugs. The swab says you\'re lying.',
    illegal = 'You told me there was nothing illegal. Explain this.', weapons = 'You said no weapons. So what\'s this?',
    owner = 'You told me this was your car. It\'s reported stolen.', name = 'That\'s not your name, is it? Your prints say different.',
    story = 'Your passenger is telling me a different story. Want to try again?', vehicle = 'Nothing illegal in the car, you said. What\'s this then?' }
local NEGO_TEXT = { listen = 'Talk to me. What do you need?', calm = 'Nobody has to get hurt today. Just breathe.', promise = 'Let them go and I\'ll make sure you\'re treated fairly.',
    family = 'Think about your family. They want you home.', time = 'Take your time. I\'m not going anywhere.', demand = 'Drop the weapon and let them go - NOW!' }

local function Mugshot(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local h = RegisterPedheadshot(ped)
    local t = GetGameTimer() + 2000
    while not IsPedheadshotReady(h) and GetGameTimer() < t do Wait(20) end
    if not IsPedheadshotReady(h) then UnregisterPedheadshot(h) return nil end
    local txd = GetPedheadshotTxdString(h)
    SetTimeout(60000, function() UnregisterPedheadshot(h) end)
    return txd
end

function VehLabel(veh)
    local name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
    if name == 'NULL' then name = GetDisplayNameFromVehicleModel(GetEntityModel(veh)) end
    return name
end

local function IsRestrained(e) return e.status == 'cuffed' or e.status == 'escorted' or e.status == 'seated' end

---------------------------------------------------------------------------
-- Traffic stops
---------------------------------------------------------------------------
local function VehicleInFront(myVeh)
    local from = GetOffsetFromEntityInWorldCoords(myVeh, 0.0, 3.0, 0.3)
    local to = GetOffsetFromEntityInWorldCoords(myVeh, 0.0, AI.StopRange, 0.3)
    local ray = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 2.5, 10, myVeh, 7)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if hit == 1 and ent ~= 0 and IsEntityAVehicle(ent) then return ent end
    local best, bd = nil, AI.StopRange
    local pos, fwd = GetEntityCoords(myVeh), GetEntityForwardVector(myVeh)
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if v ~= myVeh then
            local d = GetEntityCoords(v) - pos
            local len = #d
            if len > 2.0 and len < bd and (d.x * fwd.x + d.y * fwd.y) / len > 0.85 then best, bd = v, len end
        end
    end
    return best
end

-- A spot just off the edge of the road ahead, on the right, facing the way they're going
local function RoadsidePoint(veh)
    local vh = GetEntityHeading(veh)
    for _, dist in ipairs({ 30.0, 45.0, 20.0 }) do
        local ahead = GetOffsetFromEntityInWorldCoords(veh, 0.0, dist, 0.0)
        local ok, node, heading = GetClosestVehicleNodeWithHeading(ahead.x, ahead.y, ahead.z, 1, 3.0, 0)
        if ok and node then
            local diff = math.abs(((heading - vh + 180.0) % 360.0) - 180.0)
            if diff > 90.0 then heading = (heading + 180.0) % 360.0 end
            local rad = math.rad(heading)
            local right = vector3(math.cos(rad), math.sin(rad), 0.0)
            local okB, found, bound = pcall(GetRoadBoundaryUsingHeading, node.x, node.y, node.z, heading)
            local spot
            local width = (okB and found and bound) and #vector3(bound.x - node.x, bound.y - node.y, 0.0) or 0.0
            if width > 1.0 and width < 14.0 then
                -- always the right-hand edge, however far the boundary is from the centre node
                spot = node + right * width
                spot = vector3(spot.x, spot.y, bound.z)
            else
                spot = node + right * 5.5
            end
            -- fully onto the shoulder
            spot = spot + right * 1.4
            local okG, gz = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 2.0, false)
            if okG then spot = vector3(spot.x, spot.y, gz) end
            return spot, heading
        end
    end
    return GetOffsetFromEntityInWorldCoords(veh, 4.5, 28.0, 0.0), vh
end

local function PullOver(e)
    local ped, veh = e.ped, e.veh
    e.status = 'pulling'
    SetVehicleIndicatorLights(veh, 0, false)
    SetVehicleIndicatorLights(veh, 1, true)   -- right indicator while pulling in
    local target, heading = RoadsidePoint(veh)
    e.pullSpot = target
    TaskVehiclePark(ped, veh, target.x, target.y, target.z, heading, 0, 25.0, true)
    CreateThread(function()
        local t = GetGameTimer() + 16000
        local slowSince = nil
        while GetGameTimer() < t and DoesEntityExist(veh) and e.status == 'pulling' do
            Wait(250)
            local d = #(GetEntityCoords(veh) - target)
            if d < 3.0 then break end
            if GetEntitySpeed(veh) < 0.4 then slowSince = slowSince or GetGameTimer() else slowSince = nil end
            if slowSince and GetGameTimer() - slowSince > 3000 and GetGameTimer() > t - 12000 then break end
        end
        if e.status ~= 'pulling' or not DoesEntityExist(veh) then return end
        if Control(ped, 800) then
            TaskVehicleTempAction(ped, veh, 27, 1000000)
            SetVehicleBrakeLights(veh, true)
        end
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)   -- hazards once stopped
        e.status = 'held'
        Notify(('Vehicle stopped. Walk up and press ~INPUT_CONTEXT~ to talk. Not a good spot? Press %s in your car: they\'ll follow you, then mimic you.'):format(AI.Keys.stop))
    end)
end

---------------------------------------------------------------------------
-- Moving a stopped vehicle: follow me / mimic me
---------------------------------------------------------------------------
local function Brake(e)
    if DoesEntityExist(e.ped) and DoesEntityExist(e.veh) and Control(e.ped, 600) then
        ClearPedTasks(e.ped)
        TaskVehicleTempAction(e.ped, e.veh, 27, 1000000)
        SetVehicleIndicatorLights(e.veh, 0, true)
        SetVehicleIndicatorLights(e.veh, 1, true)
    end
end

function ConvoyStop(e, quiet)
    if e.status ~= 'convoy' then return end
    e.convoy = nil
    Brake(e)
    e.status = 'held'
    if not quiet then
        Notify('They\'ve stopped. Walk up and press ~INPUT_CONTEXT~ to talk to them.')
        RadioLine(Callsign() .. ': vehicle relocated, continuing the stop.', true)
    end
end

function ConvoyStart(e, mode)
    local ped, veh = e.ped, e.veh
    if not veh or not DoesEntityExist(veh) or not IsPedInVehicle(ped, veh, false) or GetPedInVehicleSeat(veh, -1) ~= ped then
        return Notify('The driver needs to be in their vehicle.')
    end
    if not Control(ped) or not Control(veh) then return end
    e.status, e.convoy = 'convoy', mode
    local token = {}
    e.convoyToken = token
    SetVehicleIndicatorLights(veh, 0, false)
    SetVehicleIndicatorLights(veh, 1, false)
    SetVehicleEngineOn(veh, true, true, false)
    if mode == 'follow' then
        Notify('~b~Follow me:~s~ they\'ll follow your car. Drive somewhere safe and stop - they\'ll pull in behind you. Press ' .. AI.Keys.stop .. ' again to switch to mimic.')
    else
        Notify('~b~Mimic me:~s~ they copy your movements from behind - steer onto the shoulder and stop, they\'ll do the same. Press ' .. AI.Keys.stop .. ' again to stop them.')
    end
    CreateThread(function()
        local lat = nil
        local lastTask, stillSince = 0, nil
        local hadCar, started = false, GetGameTimer()
        while e.convoyToken == token and e.status == 'convoy' and DoesEntityExist(ped) and DoesEntityExist(veh) do
            Wait(mode == 'mimic' and 350 or 1000)
            local me = Me()
            local myCar = GetVehiclePedIsIn(me, false)
            if myCar == 0 then
                if hadCar or GetGameTimer() - started > 45000 then
                    -- officer got out: stop where they are
                    ConvoyStop(e)
                    break
                end
                goto continue
            end
            hadCar = true
            if not IsPedInVehicle(ped, veh, false) then e.status = 'held' break end
            if #(GetEntityCoords(veh) - GetEntityCoords(myCar)) > 200.0 then
                ConvoyStop(e, true)
                Notify('They lost you - they\'ve stopped.')
                break
            end
            local mySpeed = GetEntitySpeed(myCar)
            if not Control(ped, 300) then goto continue end
            if mode == 'follow' then
                if mySpeed < 0.5 then
                    stillSince = stillSince or GetGameTimer()
                    -- you've stopped: they pull in behind you
                    if GetGameTimer() - stillSince > 2500 and not e.parkedBehind then
                        e.parkedBehind = true
                        local spot = GetOffsetFromEntityInWorldCoords(myCar, 0.0, -9.0, 0.0)
                        TaskVehiclePark(ped, veh, spot.x, spot.y, spot.z, GetEntityHeading(myCar), 0, 12.0, true)
                    end
                else
                    stillSince, e.parkedBehind = nil, false
                    if GetGameTimer() - lastTask > 5000 then
                        lastTask = GetGameTimer()
                        TaskVehicleEscort(ped, veh, myCar, -1, math.max(10.0, mySpeed + 4.0), 786603, 9.0, 0, 30.0)
                    end
                end
            else
                -- mimic: hold the same position relative to you, matching your speed and lane
                if not lat then
                    local rel = GetOffsetFromEntityGivenWorldCoords(myCar, GetEntityCoords(veh))
                    lat = math.max(-3.5, math.min(3.5, rel.x))
                end
                local target = GetOffsetFromEntityInWorldCoords(myCar, lat, -10.0, 0.0)
                local d = #(GetEntityCoords(veh) - target)
                if mySpeed < 0.4 and d < 4.0 then
                    TaskVehicleTempAction(ped, veh, 27, 800)
                else
                    TaskVehicleDriveToCoord(ped, veh, target.x, target.y, target.z, math.max(3.0, mySpeed + math.min(6.0, d * 0.4)), 0,
                        GetEntityModel(veh), 786468 | 262144, 1.0, true)
                end
            end
            ::continue::
        end
    end)
end

-- Your stopped vehicle, if you're near it (for the follow / mimic key)
local function MyStop(radius)
    local pos = MyPos()
    for _, e in pairs(AIPeds) do
        if e.veh and DoesEntityExist(e.veh) and e.seat == -1 and (e.status == 'held' or e.status == 'convoy' or e.status == 'pulling')
            and IsPedInVehicle(e.ped, e.veh, false) and #(GetEntityCoords(e.veh) - pos) < radius then
            return e
        end
    end
end

local function CycleConvoy(e)
    if e.status == 'pulling' then return Notify('They\'re still pulling over.') end
    if e.status == 'held' then
        ConvoyStart(e, 'follow')
    elseif e.convoy == 'follow' then
        e.convoyToken = nil
        e.status = 'held'
        ConvoyStart(e, 'mimic')
    else
        e.convoyToken = nil
        e.status = 'convoy'
        ConvoyStop(e)
    end
end

function StartTrafficStop()
    if not IsPolice then return Notify('You need to be on duty with a police department (/onduty).') end
    local me = Me()
    local myVeh = GetVehiclePedIsIn(me, false)
    if myVeh == 0 or GetPedInVehicleSeat(myVeh, -1) ~= me then return end
    if AI.EmergencyOnly and GetVehicleClass(myVeh) ~= 18 then return Notify('You need to be in an emergency vehicle to pull someone over.') end
    if AI.NeedLights and not IsVehicleSirenOn(myVeh) then return Notify('Turn your emergency lights on first.') end
    -- already got one stopped? the key moves them: follow me > mimic me > stop
    local cur = MyStop(70.0)
    if cur then return CycleConvoy(cur) end
    local veh = VehicleInFront(myVeh)
    if not veh then return Notify('No vehicle in front of you.') end
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver == 0 then return Notify('That vehicle is empty.') end
    if IsPedAPlayer(driver) then return Notify('That\'s a real player - roleplay the stop with them.') end
    local existing = AIPeds[driver]
    if existing and existing.status ~= 'free' then
        if existing.status == 'pursuit' then return Notify('They\'re not stopping!') end
        return Notify('You\'ve already stopped that vehicle.')
    end
    if not Control(driver) or not Control(veh) then return Notify('Couldn\'t stop that vehicle - try again.') end
    local e = Persona(driver, existing and existing.role or 'driver', existing and existing.profile or 'driver', veh)
    if not e then return end
    SetEntityAsMissionEntity(veh, true, true)
    Hold(driver)
    e.veh, e.seat, e.stopKind = veh, -1, 'traffic'
    for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local p = GetPedInVehicleSeat(veh, seat)
        if p ~= 0 and not IsPedAPlayer(p) and Control(p, 500) then
            local pe = Persona(p, 'passenger', nil, veh)
            if pe then Hold(p) pe.veh, pe.seat, pe.status = veh, seat, 'held' end
        end
    end
    CreateThread(function() TriggerCallback('aiStopStarted', 'traffic', e.pid) end)
    RadioLine(('%s: traffic stop, %s, plate %s.'):format(Callsign(), Street(GetEntityCoords(veh)), GetVehicleNumberPlateText(veh):gsub('%s+$', '')))
    local act = AIReact(e, 'stop')
    if act == 'flee' then return FleeInVehicle(e) end
    if act == 'fight' then e.ambush = true end
    PullOver(e)
    if act == 'reach' and ReachFor then
        -- they go for something as you walk up to the window
        CreateThread(function()
            local t = GetGameTimer() + 60000
            while AIPeds[e.ped] == e and Dist(e.ped, Me()) > 6.0 and GetGameTimer() < t do Wait(250) end
            if AIPeds[e.ped] == e and e.status == 'held' then ReachFor(e) end
        end)
    end
end

RegisterCommand('+swai_stop', function()
    if IsPolice and IsPedInAnyVehicle(PlayerPedId(), false) then CreateThread(StartTrafficStop) end
end, false)
RegisterCommand('-swai_stop', function() end, false)
RegisterKeyMapping('+swai_stop', 'Statewide PD: pull over the vehicle in front', 'keyboard', AI.Keys.stop)

---------------------------------------------------------------------------
-- Pedestrian stops
---------------------------------------------------------------------------
local function StoppablePed(radius)
    local me = Me()
    local pos, fwd = GetEntityCoords(me), GetEntityForwardVector(me)
    local best, bd = nil, radius
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, false) and IsPedHuman(ped)
            and not IsPedDeadOrDying(ped, true) and not AIPeds[ped] and not IsEntityAMissionEntity(ped) then
            local d = GetEntityCoords(ped) - pos
            local len = #d
            if len < bd and (len < 1.5 or (d.x * fwd.x + d.y * fwd.y) / len > 0.2) then best, bd = ped, len end
        end
    end
    return best
end

function StopOnFoot(e)
    if e.injured then
        -- hurt people stay where they are
        e.status = 'held'
        Say(e, PickOne({ 'Please... help me.', 'It hurts so bad...', 'Is an ambulance coming?' }))
        return OpenPanelAI(e)
    end
    OfficerSay(e, PickOne({ 'Police! Stop right there.', 'Excuse me - police. Can I have a word?', 'Hold on a second. Police.' }))
    local act = AIReact(e, 'stop')
    if ApplyReaction(e, act) then return end
    if e.ambush then Fight(e) return end
    HoldOnFoot(e)
    local g = TriggerCallback('aiAsk', e.pid, 'greet')
    if g and g.ok then Say(e, g.say) end
    OpenPanelAI(e)
end

local function StartPedStop(ped)
    if not Control(ped) then return Notify('Couldn\'t stop them - try again.') end
    local e = Persona(ped, 'ped')
    if not e then return end
    Hold(ped)
    e.stopKind = 'ped'
    CreateThread(function() TriggerCallback('aiStopStarted', 'ped', e.pid) end)
    StopOnFoot(e)
end

local function TrackedNear(radius)
    local pos = MyPos()
    local best, bd = nil, radius
    for ped, e in pairs(AIPeds) do
        if DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            if d < bd then best, bd = e, d end
        end
    end
    return best
end

local function TackleAI()
    local me = Me()
    local pos, fwd = GetEntityCoords(me), GetEntityForwardVector(me)
    for ped, e in pairs(AIPeds) do
        if e.status == 'fleeing' or e.status == 'fighting' then
            local d = GetEntityCoords(ped) - pos
            local len = #d
            if len > 0.1 and len < Config.Tackle.distance and (d.x * fwd.x + d.y * fwd.y) / len > 0.5 then
                if Control(ped, 400) then
                    PlayAnim('tackleCop', 0, 3000)
                    SetPedToRagdoll(ped, 3500, 3500, 0, false, false, false)
                    Wait(600)
                    SetPedToRagdoll(me, 1200, 1200, 0, false, false, false)
                    SetTimeout(3200, function() if AIPeds[ped] == e and DoesEntityExist(ped) then Surrender(e) end end)
                end
                return true
            end
        end
    end
    return false
end

-- Someone you can deal with from a distance: a hostage taker, or the occupants of a stop you're holding at gunpoint
function RemoteTarget()
    local pos = MyPos()
    local best, bd = nil, 999.0
    local aiming = IsPlayerFreeAiming(PlayerId())
    for ped, e in pairs(AIPeds) do
        if DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            local hostage = e.persona and (e.persona.hostage or e.persona.crisis) and d < 28.0
            -- felony stop orders: aim at the car (or keep going once you've started one)
            local felony = e.veh and (e.felony or (aiming and e.status == 'held')) and d > 4.0 and d < 35.0
            if (hostage or felony) and d < bd then best, bd = e, d end
        end
    end
    return best
end

function Interact(e, remote)
    if remote then
        if not Control(e.ped) then return end
        if e.persona and (e.persona.hostage or e.persona.crisis) then e.tab = 'nego' else
            e.tab = 'felony'
            -- the panel always talks to the driver; the felony tab lists every occupant
            for _, o in pairs(AIPeds) do if o.veh == e.veh and o.seat == -1 and DoesEntityExist(o.ped) then e = o e.tab = 'felony' break end end
        end
        return OpenPanelAI(e, true)
    end
    if e.status == 'fleeing' or e.status == 'pursuit' then return Notify('They\'re running - catch them first (tackle while sprinting, or taser).') end
    if e.status == 'fighting' then return Notify('They\'re fighting you!') end
    if e.persona and e.persona.hostage then return Notify('Too close! Back off and talk them down.') end
    if e.persona and e.persona.crisis then e.tab = 'nego' return OpenPanelAI(e) end
    if e.status == 'hiding' then return end
    if e.status == 'dead' then return Notify('They\'re dead. Request a coroner from the patrol computer.') end
    if e.status == 'free' then
        -- someone from a callout you haven't spoken to yet
        if not Control(e.ped) then return end
        Hold(e.ped)
        return StopOnFoot(e)
    end
    OpenPanelAI(e)
end

local holding = false
RegisterCommand('+swai_interact', function()
    holding = true
    if not IsPolice or Busy or PanelEntry then return end
    local me = Me()
    if IsPedInAnyVehicle(me, false) or IsPedDeadOrDying(me, true) then return end
    if IsPedSprinting(me) or IsPedRunning(me) then
        CreateThread(TackleAI)
        return
    end
    CreateThread(function()
        if WorldInteract and WorldInteract() then return end
        local e = TrackedNear(3.2)
        if e then return Interact(e) end
        -- talk a hostage taker down / give felony stop orders from a distance
        local far = RemoteTarget()
        if far then return Interact(far, true) end
        local start = GetGameTimer()
        while holding and GetGameTimer() - start < AI.HoldToStop do Wait(0) end
        if GetGameTimer() - start >= AI.HoldToStop then
            local ped = StoppablePed(4.5)
            if ped then StartPedStop(ped) end
        end
    end)
end, false)
RegisterCommand('-swai_interact', function() holding = false end, false)
RegisterKeyMapping('+swai_interact', 'Statewide PD: talk to / stop someone (hold to stop)', 'keyboard', AI.Keys.interact)

---------------------------------------------------------------------------
-- Restraints
---------------------------------------------------------------------------
function CuffAI(e)
    local ped, me = e.ped, Me()
    if IsPedInAnyVehicle(ped, false) then return Notify('Get them out of the vehicle first.') end
    if Dist(ped, me) > 2.6 then return Notify('Get closer to them.') end
    if e.status ~= 'surrendered' then
        local act = AIReact(e, 'cuff')
        if ApplyReaction(e, act) then ClosePanelAI() return end
    end
    if not Control(ped) then return Notify('Couldn\'t reach them - try again.') end
    ClosePanelAI()
    Busy = true
    e.status = 'cuffing'
    ClearPedTasksImmediately(ped)
    local spot = GetOffsetFromEntityInWorldCoords(me, 0.0, 0.7, 0.0)
    SetEntityCoords(ped, spot.x, spot.y, spot.z - 1.0, false, false, false, false)
    SetEntityHeading(ped, GetEntityHeading(me))
    if LoadDict('mp_arrest_paired') then
        TaskPlayAnim(ped, 'mp_arrest_paired', 'crook_p2_back_right', 8.0, -8.0, 3700, 0, 0.0, false, false, false)
    end
    PlayAnim('cuffCop', 0, 3500)
    local prop = AttachProp('cuffsHand')
    Wait(3600)
    DeleteProp(prop)
    StopAnim('cuffCop')
    SetEnableHandcuffs(ped, true)
    RemoveAllPedWeapons(ped, true)
    if LoadDict('mp_arresting') then TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false) end
    e.cuffProp = AttachProp('cuffs', ped)
    e.status, e.kneel = 'cuffed', false
    RemoveBlipSafe(e.blip)
    e.blip = nil
    Busy = false
    local r = TriggerCallback('aiState', e.pid, 'cuffed', true)
    if r and r.say then Say(e, r.say) end
end

function UncuffAI(e)
    if not IsRestrained(e) then return end
    local ped = e.ped
    if IsPedInAnyVehicle(ped, false) then return Notify('Take them out of the vehicle first.') end
    if not Control(ped) then return end
    DetachEntity(ped, true, false)
    Action('Removing cuffs', 3000, 'uncuffCop')
    if e.cuffProp then DeleteProp(e.cuffProp) e.cuffProp = nil end
    SetEnableHandcuffs(ped, false)
    ClearPedTasks(ped)
    TriggerCallback('aiState', e.pid, 'cuffed', false)
    HoldOnFoot(e)
end

function EscortAI(e)
    local ped = e.ped
    if e.status == 'escorted' then
        if Control(ped) then
            DetachEntity(ped, true, false)
            SetPedCanRagdoll(ped, true)
            ClearPedTasks(ped)
        end
        e.status, e.escAnim = 'cuffed', nil
        return
    end
    if e.status ~= 'cuffed' then return Notify('Cuff them first.') end
    if IsPedInAnyVehicle(ped, false) then return Notify('Take them out of the vehicle first.') end
    if not Control(ped) then return end
    -- stand them up first (they may be on the floor after a tackle or kneeling)
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped, false)
    -- held just in front of the officer's right shoulder, upright and facing the same way
    AttachEntityToEntity(ped, Me(), 11816, 0.38, 0.55, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    e.escAnim = nil
    e.status = 'escorted'
    Notify('Escorting. Walk them to a vehicle, then use the menu (~INPUT_CONTEXT~) to put them in.')
end

local function PrisonerVehicle()
    local pos = MyPos()
    local best, bd, bestScore = nil, 9.0, -1
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - pos)
        if d < bd + 0.01 then
            local score = (GetVehicleClass(v) == 18 and 10 or 0) - d
            if score > bestScore and GetVehicleMaxNumberOfPassengers(v) >= 1 then best, bestScore = v, score end
        end
    end
    if not best then return nil end
    for _, seat in ipairs({ 1, 2, 0 }) do
        if seat <= GetVehicleMaxNumberOfPassengers(best) - 1 and IsVehicleSeatFree(best, seat) then return best, seat end
    end
    return nil
end

function SeatAI(e)
    if e.status ~= 'cuffed' and e.status ~= 'escorted' then return Notify('Cuff them first.') end
    local veh, seat = PrisonerVehicle()
    if not veh then return Notify('No free back seat in a vehicle next to you.') end
    if not Control(e.ped) then return end
    DetachEntity(e.ped, true, false)
    SetPedCanRagdoll(e.ped, true)
    e.escAnim = nil
    TaskWarpPedIntoVehicle(e.ped, veh, seat)
    e.status, e.seatVeh = 'seated', veh
    Notify('Prisoner in the vehicle. Drive to a station to book them, or request prisoner transport.')
end

function UnseatAI(e)
    local veh = GetVehiclePedIsIn(e.ped, false)
    if veh == 0 then return end
    if not Control(e.ped) then return end
    TaskLeaveVehicle(e.ped, veh, 16)
    Wait(800)
    if IsRestrained(e) then
        e.status = 'cuffed'
        if LoadDict('mp_arresting') then TaskPlayAnim(e.ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false) end
    else
        HoldOnFoot(e)
    end
end

---------------------------------------------------------------------------
-- What the panel buttons do
---------------------------------------------------------------------------
local TESTS = {
    frisk  = { label = 'Patting down',          ms = 5000, anim = 'search' },
    search = { label = 'Searching',             ms = 8000, anim = 'search' },
    breath = { label = 'Breathalyser',          ms = 6000, anim = 'holdDevice', props = { 'breath' }, blow = true },
    drug   = { label = 'Taking a drug swab',    ms = 8000, anim = 'holdDevice', props = { 'swab' }, blow = true },
    gsr    = { label = 'Swabbing their hands',  ms = 6000, anim = 'swabHands', props = { 'gsr' } },
    dna    = { label = 'Taking a DNA swab',     ms = 5000, anim = 'holdDevice', props = { 'swab' }, blow = true },
}

local function SetResult(e, r)
    e.result = r
    PanelRefresh()
end

local function MarkCause(e, r)
    if r.kind == 'breath' and r.over then e.pc = true end
    if r.kind == 'drug' and r.positive then e.pc = true end
    if r.kind == 'gsr' and r.positive then e.pc = true end
    if r.items then for _, it in ipairs(r.items) do if not it.legal then e.pc = true end end end
end

local function NeedOut(e)
    if IsPedInAnyVehicle(e.ped, false) then Notify('Ask them to step out of the vehicle first.') return true end
    return false
end

local function AnyoneCuffed(veh)
    for _, o in pairs(AIPeds) do if o.veh == veh and IsRestrained(o) then return true end end
    return false
end

local function Consent(e, what)
    local r = TriggerCallback('aiConsent', e.pid, what)
    if not r or not r.ok then return false end
    OfficerSay(e, what == 'vehicle' and 'Do you mind if I search your vehicle?' or 'Do you mind if I search you?')
    Say(e, r.say)
    return r.yes
end

ACTIONS_AI = {}
local A = ACTIONS_AI

A.ask = function(e, d)
    local q = tostring(d.q or '')
    if not QUESTION_TEXT[q] then return end
    local firm = e.tone == 'firm'
    OfficerSay(e, (firm and FIRM[q]) or QUESTION_TEXT[q])
    local r = TriggerCallback('aiAsk', e.pid, q, firm and 'firm' or 'calm')
    if not r or not r.ok then return Result(r) end
    if r.persona then e.persona = r.persona end
    Say(e, r.say)
    -- victims and witnesses on an investigation give a statement for the case file
    if q == 'story' and (e.role == 'victim' or e.role == 'witness') and e.callout and e.callout.caseId then
        local st = TriggerCallback('caseStatement', e.callout.caseId, e.pid)
        if st and st.ok then
            Say(e, st.text)
            Notify('~b~Statement added to case ' .. e.callout.caseId .. '.~s~ Open the Cases tab in the patrol computer.')
            if CaseUpdated then CaseUpdated(st.view) end
        end
    end
    if r.leaves then
        Notify('They\'re leaving.')
        ClosePanelAI()
        Release(e)
    end
end

A.tone = function(e, d)
    e.tone = d.tone == 'firm' and 'firm' or 'calm'
end

A.confront = function(e, d)
    local key = tostring(d.key or '')
    OfficerSay(e, CONFRONT[key] or 'You lied to me.')
    local r = TriggerCallback('aiConfront', e.pid, key)
    if not r or not r.ok then return Result(r) end
    if r.persona then e.persona = r.persona end
    Say(e, r.say)
    if r.act and ApplyReaction(e, r.act) then ClosePanelAI() end
end

-- Field sobriety tests
local function Clipset(ped, set)
    RequestAnimSet(set)
    local t = GetGameTimer() + 1500
    while not HasAnimSetLoaded(set) and GetGameTimer() < t do Wait(10) end
    if HasAnimSetLoaded(set) then SetPedMovementClipset(ped, set, 0.5) end
end

A.sfst = function(e, d)
    local test = d.test
    if test ~= 'hgn' and test ~= 'walk' and test ~= 'oneleg' then return end
    if NeedOut(e) then return end
    if IsRestrained(e) then return Notify('Take the cuffs off for field tests.') end
    if Dist(e.ped, Me()) > 4.0 then return Notify('Get closer to them.') end
    local r = TriggerCallback('aiTest', e.pid, test)
    if not r or not r.ok then return Result(r) end
    local ped = e.ped
    if not Control(ped) then return end
    ClearPedTasks(ped)
    if test == 'hgn' then
        OfficerSay(e, 'Follow the tip of my pen with your eyes only. Don\'t move your head.')
        TaskTurnPedToFaceEntity(ped, Me(), 6000)
        if not Action('Eye test', 6000, 'holdDevice', { 'pencil' }) then return end
    elseif test == 'walk' then
        OfficerSay(e, 'Nine steps heel to toe along the line, turn, and nine steps back. Count out loud.')
        ClosePanelAI()
        local start = GetEntityCoords(ped)
        local fwd = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.5, 0.0)
        if r.fail then Clipset(ped, r.count >= 5 and 'move_m@drunk@verydrunk' or 'move_m@drunk@moderatedrunk') end
        TaskGoStraightToCoord(ped, fwd.x, fwd.y, fwd.z, 0.6, 9000, GetEntityHeading(ped), 0.3)
        Wait(5500)
        if r.count >= 5 and Control(ped, 300) then SetPedToRagdoll(ped, 700, 700, 0, false, false, false) Wait(1600) end
        if Control(ped, 300) then TaskGoStraightToCoord(ped, start.x, start.y, start.z, 0.6, 9000, GetEntityHeading(ped) + 180.0, 0.3) end
        Wait(5500)
        if Control(ped, 300) then ResetPedMovementClipset(ped, 0.5) end
    else
        OfficerSay(e, 'Raise one foot about six inches off the ground and count to thirty.')
        if LoadDict('missfam5_yoga') then TaskPlayAnim(ped, 'missfam5_yoga', 'a2_pose', 4.0, -4.0, 7000, 1, 0.0, false, false, false) end
        Wait(r.fail and 3500 or 7000)
        if r.fail and Control(ped, 300) then SetPedToRagdoll(ped, 600, 600, 0, false, false, false) Wait(1500) end
    end
    if Control(ped, 300) then HoldOnFoot(e) end
    if r.fail then e.pc = true end
    e.result = r
    OpenPanelAI(e)
end

A.k9 = function(e)
    ClosePanelAI()
    RequestUnit('k9', { veh = e.veh, entry = e })
end

A.nego = function(e, d)
    local opt = tostring(d.opt or '')
    if not NEGO_TEXT[opt] then return end
    OfficerSay(e, NEGO_TEXT[opt])
    local r = TriggerCallback('aiNego', e.pid, opt)
    if not r or not r.ok then return Result(r) end
    if r.persona then e.persona = r.persona end
    Say(e, r.say)
    if r.outcome then
        ClosePanelAI()
        if HostageOutcome then HostageOutcome(e, r.outcome) end
    end
end

-- Felony (high-risk) stop: orders shouted at gunpoint, one occupant at a time
local function Occupants(veh)
    local list = {}
    for _, o in pairs(AIPeds) do
        if o.veh == veh and DoesEntityExist(o.ped) then list[#list + 1] = o end
    end
    table.sort(list, function(a, b) return (a.seat or -1) < (b.seat or -1) end)
    return list
end
FelonyOccupants = Occupants

A.felony = function(e, d)
    local veh = e.veh
    if not veh or not DoesEntityExist(veh) then return end
    local target = e
    if d.pid then for _, o in ipairs(Occupants(veh)) do if o.pid == d.pid then target = o end end end
    local ped = target.ped
    local step = d.step
    for _, o in ipairs(Occupants(veh)) do o.felony = true end
    if step == 'engine' then
        OfficerSay(e, 'DRIVER! Turn off the engine and drop the keys out of the window!')
        if Control(veh, 600) then SetVehicleEngineOn(veh, false, true, true) end
        local p = GetOffsetFromEntityInWorldCoords(veh, -1.6, 0.5, 0.0)
        local hash = LoadModel('p_car_keys_01')
        if hash then
            local k = CreateObject(hash, p.x, p.y, p.z, false, false, false)
            PlaceObjectOnGroundProperly(k)
            SetModelAsNoLongerNeeded(hash)
            SetTimeout(120000, function() if DoesEntityExist(k) then DeleteEntity(k) end end)
        end
        Say(e, PickOne({ 'Okay! Okay! Engine\'s off!', 'Don\'t shoot!', 'Alright, the keys are out!' }))
    elseif step == 'hands' then
        OfficerSay(e, 'EVERYONE! Hands out of the windows where I can see them!')
        for _, o in ipairs(Occupants(veh)) do o.handsOut = true end
        Say(e, PickOne({ 'Okay! Hands are out!', 'We\'re not armed! Don\'t shoot!' }))
    elseif step == 'exit' then
        if not IsPedInAnyVehicle(ped, false) then return end
        OfficerSay(target, (target.seat == -1 and 'DRIVER' or 'PASSENGER') .. '! Open the door from the outside, step out slowly, hands up!')
        local act = AIReact(target, 'felony')
        if ApplyReaction(target, act) then ClosePanelAI() return end
        if not Control(ped) then return end
        TaskLeaveVehicle(ped, veh, 256)
        local t = GetGameTimer() + 5000
        while IsPedInAnyVehicle(ped, false) and GetGameTimer() < t do Wait(100) end
        ClearPedTasks(ped)
        TaskHandsUp(ped, -1, Me(), -1, true)
        target.status = 'held'
    elseif step == 'walk' then
        if IsPedInAnyVehicle(ped, false) then return end
        OfficerSay(target, 'Turn around! Walk backwards towards my voice! Keep your hands up!')
        if not Control(ped) then return end
        local me = GetEntityCoords(Me())
        local from = GetEntityCoords(ped)
        local dir = (me - from)
        local len = #dir
        local stop = from + dir / len * math.max(0.0, len - 3.0)
        local away = GetHeadingFromVector_2d(from.x - me.x, from.y - me.y)
        ClearPedTasks(ped)
        TaskGoStraightToCoord(ped, stop.x, stop.y, stop.z, 0.4, 15000, away, 0.5)
        LoadDict('random@arrests')
        TaskPlayAnim(ped, 'random@arrests', 'idle_2_hands_up', 8.0, -8.0, -1, 50, 0.0, false, false, false)
    elseif step == 'kneel' then
        if IsPedInAnyVehicle(ped, false) then return end
        OfficerSay(target, 'STOP! Get down on your knees! Hands on your head!')
        Surrender(target)
        Say(target, PickOne({ 'Okay! I\'m down!', 'Please don\'t shoot!' }))
    end
    PanelRefresh()
end

A.idcard = function(e)
    OfficerSay(e, 'Can I see some ID, please?')
    local r = TriggerCallback('aiCheckId', e.pid, 'card')
    if not r or not r.ok then return Result(r) end
    Say(e, r.say)
    if r.noId then e.noId = true PanelRefresh() return end
    PlayAnim('giveId', 0, 1500)
    e.persona.name = r.name
    r.kind = 'id'
    r.photo = Mugshot(e.ped)
    SetResult(e, r)
end

A.idname = function(e)
    OfficerSay(e, 'What\'s your full name and date of birth?')
    local r = TriggerCallback('aiCheckId', e.pid, 'name')
    if not r or not r.ok then return Result(r) end
    Say(e, r.say)
    if r.refused then return PanelRefresh() end
    Action('Running their name', 2500, 'tablet', { 'tablet' })
    r.kind = 'id'
    r.verbal = true
    RadioLine(('Dispatch: %s%s'):format(r.name or '?', r.notFound and ' - no record found on those details.' or (' - licence ' .. tostring(r.licence):lower() .. ((#(r.warrants or {}) > 0) and ', ACTIVE WARRANT.' or ', no warrants.'))))
    if not r.notFound then e.persona.name = r.name r.photo = Mugshot(e.ped) end
    SetResult(e, r)
end

A.prints = function(e)
    if not IsRestrained(e) then return Notify('Restrain them first.') end
    if not Action('Taking fingerprints', 5000, 'dust', { 'printcard' }) then return end
    local r = TriggerCallback('aiPrints', e.pid)
    if not r or not r.ok then return Result(r) end
    e.persona.name = r.name
    r.kind = 'id'
    r.photo = Mugshot(e.ped)
    SetResult(e, r)
end

A.runplate = function(e)
    local veh = e.veh
    if not veh or not DoesEntityExist(veh) then return Notify('No vehicle.') end
    RadioLine(Callsign() .. ': 10-28 on plate ' .. GetVehicleNumberPlateText(veh):gsub('%s+$', '') .. '.', true)
    Action('Running the plate', 2000, 'tablet', { 'tablet' })
    local r = TriggerCallback('aiVehicle', VehToNet(veh), e.pid)
    if not r or not r.ok then return Result(r) end
    r.kind = 'plate'
    r.model = VehLabel(veh)
    for _, f in ipairs(r.flags or {}) do if f:find('STOLEN') then e.pc = true end end
    RadioLine(('Dispatch: %s comes back to %s%s.'):format(r.plate, r.owner, #(r.flags or {}) > 0 and (' - ' .. table.concat(r.flags, ', ')) or ', no flags'))
    SetResult(e, r)
end

A.out = function(e)
    local veh = GetVehiclePedIsIn(e.ped, false)
    if veh == 0 then return end
    OfficerSay(e, 'Step out of the vehicle for me, please.')
    local act = AIReact(e, 'out')
    if ApplyReaction(e, act) then ClosePanelAI() return end
    if not Control(e.ped) then return end
    Say(e, PickOne({ 'Okay, okay.', 'Alright, I\'m getting out.', 'Sure.', 'Fine...' }))
    TaskLeaveVehicle(e.ped, veh, 256)
    local t = GetGameTimer() + 5000
    while IsPedInAnyVehicle(e.ped, false) and GetGameTimer() < t do Wait(100) end
    if e.ambush then e.ambush = nil ClosePanelAI() Fight(e) return end
    HoldOnFoot(e)
    PanelRefresh()
end

A.backin = function(e)
    local veh = e.veh
    if not veh or not DoesEntityExist(veh) or IsPedInAnyVehicle(e.ped, false) then return end
    if IsRestrained(e) then return Notify('Take the cuffs off first.') end
    OfficerSay(e, 'You can get back in the vehicle.')
    if not Control(e.ped) then return end
    ClearPedTasks(e.ped)
    TaskEnterVehicle(e.ped, veh, 8000, e.seat or -1, 1.0, 1, 0)
    CreateThread(function()
        local t = GetGameTimer() + 9000
        while not IsPedInVehicle(e.ped, veh, false) and GetGameTimer() < t do Wait(200) end
        HoldInVehicle(e)
        PanelRefresh()
    end)
end

A.convoy = function(e, d)
    if d.mode == 'stop' then ClosePanelAI() return ConvoyStop(e) end
    OfficerSay(e, d.mode == 'mimic' and 'Stay right behind me and copy what I do.' or 'Follow my car - I\'ll find somewhere safer to pull over.')
    Say(e, PickOne({ 'Okay, I\'ll follow you.', 'Sure, officer.', 'Alright.' }))
    ClosePanelAI()
    ConvoyStart(e, d.mode == 'mimic' and 'mimic' or 'follow')
    if d.mode ~= 'mimic' then Notify('Get back in your car and drive - they\'ll follow.') end
end

A.engine = function(e)
    local veh = GetVehiclePedIsIn(e.ped, false)
    if veh == 0 then return end
    OfficerSay(e, 'Turn the engine off and keep your hands where I can see them.')
    if Control(veh, 600) then SetVehicleEngineOn(veh, false, true, true) end
    Say(e, PickOne({ 'Okay.', 'Engine\'s off.', 'Sure thing.' }))
end

A.follow = function(e)
    if IsRestrained(e) or IsPedInAnyVehicle(e.ped, false) then return end
    if not Control(e.ped) then return end
    if e.status == 'following' then
        OfficerSay(e, 'Wait here.')
        HoldOnFoot(e)
    else
        OfficerSay(e, 'Come with me.')
        ClearPedTasks(e.ped)
        TaskFollowToOffsetOfEntity(e.ped, Me(), 0.0, -1.3, 0.0, 1.4, -1, 1.2, true)
        e.status = 'following'
    end
    PanelRefresh()
end

A.test = function(e, d)
    local kind = d.kind
    local t = TESTS[kind]
    if not t then return end
    if (kind == 'frisk' or kind == 'search' or kind == 'gsr') and NeedOut(e) then return end
    if Dist(e.ped, Me()) > 4.0 then return Notify('Get closer to them.') end
    if kind == 'search' and not IsRestrained(e) and not e.pc and not (e.consent and e.consent.person) then
        local yes = Consent(e, 'person')
        e.consent = e.consent or {}
        e.consent.person = yes
        if not yes then PanelRefresh() return Notify('They refused. Pat them down for weapons, or you need probable cause / an arrest for a full search.') end
    end
    if (kind == 'frisk' or kind == 'search') and not IsRestrained(e) and e.status ~= 'surrendered' then
        local act = AIReact(e, 'search')
        if ApplyReaction(e, act) then ClosePanelAI() return end
    end
    if t.blow and not IsPedInAnyVehicle(e.ped, false) and Control(e.ped, 500) then
        LoadDict(Config.Anims.blow.dict)
        TaskPlayAnim(e.ped, Config.Anims.blow.dict, Config.Anims.blow.name, 8.0, -8.0, t.ms, 49, 0.0, false, false, false)
    end
    if not Action(t.label, t.ms, t.anim, t.props) then return end
    local r = TriggerCallback('aiTest', e.pid, kind)
    if not r or not r.ok then return Result(r) end
    MarkCause(e, r)
    SetResult(e, r)
end

A.seize = function(e, d)
    local r = TriggerCallback('aiSeize', e.pid, d.index)
    if not Result(r) then return end
    if r.persona then e.persona = r.persona end
    if r.disarm and Control(e.ped, 500) then RemoveWeaponFromPed(e.ped, GetHashKey(r.disarm)) end
    if e.result and e.result.items then
        for i, it in ipairs(e.result.items) do if it.index == d.index then table.remove(e.result.items, i) break end end
    end
    PanelRefresh()
end

A.vehsearch = function(e)
    local veh = e.veh
    if not veh or not DoesEntityExist(veh) then return Notify('No vehicle.') end
    if #(GetEntityCoords(veh) - MyPos()) > 5.0 then return Notify('Get closer to the vehicle.') end
    if not e.pc and not AnyoneCuffed(veh) and not (e.consent and e.consent.vehicle) then
        local yes = Consent(e, 'vehicle')
        e.consent = e.consent or {}
        e.consent.vehicle = yes
        if not yes then PanelRefresh() return Notify('They refused. You need probable cause (something found, failed test, stolen, arrest) to search it.') end
    end
    ClosePanelAI()
    if not Action('Searching the vehicle', 8000, 'vehicleSearch') then return end
    local r = TriggerCallback('aiVehSearch', VehToNet(veh), e.pid)
    if not r or not r.ok then return Result(r) end
    r.kind = 'vehicle'
    if #r.items > 0 then e.pc = true end
    e.result = r
    OpenPanelAI(e)
end

A.vseize = function(e, d)
    local veh = e.veh
    if not veh or not DoesEntityExist(veh) then return end
    local r = TriggerCallback('aiVehSeize', VehToNet(veh), d.index)
    if not Result(r) then return end
    if e.result and e.result.items then
        for i, it in ipairs(e.result.items) do if it.index == d.index then table.remove(e.result.items, i) break end end
    end
    PanelRefresh()
end

A.cuff = function(e) CuffAI(e) end
A.uncuff = function(e) ClosePanelAI() UncuffAI(e) end
A.escort = function(e) ClosePanelAI() EscortAI(e) end
A.seat = function(e) ClosePanelAI() SeatAI(e) end
A.unseat = function(e) UnseatAI(e) PanelRefresh() end

A.warn = function(e)
    OfficerSay(e, 'I\'m letting you off with a warning today.')
    local r = TriggerCallback('aiWarn', e.pid, '')
    if not Result(r) then return end
    Say(e, r.say)
end

A.form = function(e, d)
    local pc = PenalCode()
    if not pc then return Notify('Couldn\'t load the penal code.') end
    local how = nil
    if d.kind == 'arrest' then
        if not IsRestrained(e) then return Notify('Cuff them first.') end
        if TransportReady and TransportReady(e) then how = 'transport'
        elseif NearStationClient() or Config.BookAnywhere then how = 'station'
        else return Notify('Drive them to a station booking desk, or request prisoner transport from the patrol computer.') end
    end
    SendNUIMessage({ action = 'aiForm', kind = d.kind, how = how, code = pc.code, maxJail = pc.maxJail })
end

A.cite = function(e, d)
    OfficerSay(e, 'I\'m issuing you a citation.')
    local r = TriggerCallback('aiCite', e.pid, d.offences, d.notes)
    if not Result(r) then return end
    Say(e, r.say)
    PlayAnim('write', 49, 3000)
    local pad = AttachProp('notepad')
    SetTimeout(3000, function() StopAnim('write') DeleteProp(pad) end)
end

A.arrest = function(e, d)
    local how = d.how == 'transport' and 'transport' or 'station'
    local r = TriggerCallback('aiArrest', e.pid, d.offences, d.minutes, d.notes, how)
    if not Result(r) then return end
    ClosePanelAI()
    RadioLine(Callsign() .. ': 10-15, one in custody.')
    if r.case and ReportReminder then ReportReminder(r.case) end
    if how == 'transport' and HandToTransport then
        HandToTransport(e)
    else
        RemoveBlipSafe(e.blip)
        Untrack(e)
        Vanish(e.ped)
        Notify('Prisoner booked into custody.')
    end
end

local function ReleaseOthers(e)
    if not e.veh then return end
    for _, o in pairs(AIPeds) do
        if o ~= e and o.veh == e.veh and o.status == 'held' then Release(o) end
    end
end

A.release = function(e)
    if e.seat == -1 then ReleaseOthers(e) end
    if IsRestrained(e) then
        if IsPedInAnyVehicle(e.ped, false) then UnseatAI(e) end
        if e.cuffProp then DeleteProp(e.cuffProp) e.cuffProp = nil end
        TriggerCallback('aiState', e.pid, 'cuffed', false)
    end
    OfficerSay(e, 'You\'re free to go.')
    local r = TriggerCallback('aiRelease', e.pid)
    if r and r.say then Say(e, r.say) end
    ClosePanelAI()
    -- send them back to their car if they got out
    if e.veh and DoesEntityExist(e.veh) and not IsPedInAnyVehicle(e.ped, false) and IsVehicleSeatFree(e.veh, e.seat or -1)
        and GetVehicleEngineHealth(e.veh) > 300 and Control(e.ped, 600) then
        ClearPedTasks(e.ped)
        TaskEnterVehicle(e.ped, e.veh, 10000, e.seat or -1, 1.0, 1, 0)
        local ped = e.ped
        CreateThread(function()
            local t = GetGameTimer() + 11000
            while DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) and GetGameTimer() < t do Wait(250) end
            Release(e)
        end)
        return
    end
    Release(e)
end

A.unit = function(e, d)
    ClosePanelAI()
    if RequestUnit then RequestUnit(d.kind, { veh = e.veh, ped = e.ped, entry = e }) end
end

A.mdt = function()
    ClosePanelAI()
    DoMDT()
end
