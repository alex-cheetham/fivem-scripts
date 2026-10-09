-- Statewide PD: pursuits. Backup joins the chase, takes roles (primary / rolling roadblock / support),
-- can PIT the suspect, boxes them in when they slow down, and spike strips / roadblocks are set up
-- ahead of the suspect on the road they're heading down. A supervisor calls it off if it drags on.
local PC = AI.Pursuit or {}
local S = nil            -- current pursuit { e, veh, started, terminated, lastPit, warned }
local Strips = {}        -- { obj, u, until }
local PIT_SPIN = 2.8

local function Alive(p) return p and DoesEntityExist(p) and not IsPedDeadOrDying(p, true) end

local function FindSuspect()
    local best, bd = nil, 1200.0
    local pos = MyPos()
    for ped, e in pairs(AIPeds) do
        if e.status == 'pursuit' and e.veh and DoesEntityExist(e.veh) and GetPedInVehicleSeat(e.veh, -1) == ped then
            local d = #(GetEntityCoords(e.veh) - pos)
            if d < bd then best, bd = e, d end
        end
    end
    return best
end

function PursuitActive() return S ~= nil and not S.terminated end

---------------------------------------------------------------------------
-- PIT manoeuvre (yours or an AI unit's)
---------------------------------------------------------------------------
local function Spin(veh, side, who)
    if not Control(veh, 400) then return false end
    SetVehicleReduceGrip(veh, true)
    SetEntityAngularVelocity(veh, 0.0, 0.0, side * PIT_SPIN)
    SetTimeout(1300, function() if DoesEntityExist(veh) then SetVehicleReduceGrip(veh, false) end end)
    SetTimeout(900, function()
        if DoesEntityExist(veh) and Control(veh, 300) then
            SetVehicleEngineOn(veh, false, true, true)
            SetTimeout(3500, function() if DoesEntityExist(veh) then SetVehicleEngineOn(veh, true, true, false) end end)
        end
    end)
    Notify(who and ('~b~' .. who .. '~s~ performed a PIT!') or '~g~PIT successful!')
    RadioLine((who or Callsign()) .. ': PIT executed, suspect vehicle spun out!')
    return true
end

-- Which side of the suspect's rear quarter is this car on? nil if it's not in a PIT position
local function PitSide(suspectVeh, carPos)
    local o = GetOffsetFromEntityGivenWorldCoords(suspectVeh, carPos.x, carPos.y, carPos.z)
    if o.y < -5.5 or o.y > -0.5 then return nil end
    if math.abs(o.x) < 0.6 or math.abs(o.x) > 2.8 then return nil end
    return o.x > 0 and -1.0 or 1.0     -- hit on the right rear pushes the back left: clockwise (negative z)
end

local function PitAllowed()
    return PC.PIT ~= false and S and GetGameTimer() - S.started > (PC.PITAfter or 20) * 1000 and GetGameTimer() - (S.lastPit or 0) > 7000
end

-- You hitting their rear quarter at a sensible speed
CreateThread(function()
    while true do
        local wait = 500
        if S and not S.terminated and DoesEntityExist(S.veh) then
            local myVeh = GetVehiclePedIsIn(Me(), false)
            if myVeh ~= 0 and #(GetEntityCoords(myVeh) - GetEntityCoords(S.veh)) < 12.0 then
                wait = 0
                if PitAllowed() and IsEntityTouchingEntity(myVeh, S.veh) then
                    local mine, theirs = GetEntitySpeed(myVeh), GetEntitySpeed(S.veh)
                    local side = PitSide(S.veh, GetOffsetFromEntityInWorldCoords(myVeh, 0.0, 2.2, 0.0))
                    if side and mine > 8.0 and mine < 42.0 and math.abs(mine - theirs) < 9.0 then
                        S.lastPit = GetGameTimer()
                        if math.random() < (PC.PITChance or 0.8) then Spin(S.veh, side) else Notify('PIT failed - they held it.') end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

---------------------------------------------------------------------------
-- Spike strips and roadblocks ahead of the suspect
---------------------------------------------------------------------------
local function AheadPoint(veh, seconds, minD)
    local pos = GetEntityCoords(veh)
    local vel = GetEntityVelocity(veh)
    local speed = math.max(#vel, 15.0)
    local fwd = GetEntityForwardVector(veh)
    local lead = math.max(minD or 140.0, speed * (seconds or 12))
    for _, extra in ipairs({ 0.0, 60.0, 120.0, -40.0 }) do
        local p = pos + fwd * (lead + extra)
        local ok, node, heading = GetClosestVehicleNodeWithHeading(p.x, p.y, p.z, 1, 3.0, 0)
        if ok and node then
            local n = vector3(node.x, node.y, node.z)
            local to = n - pos
            if #to > 90.0 and (to.x * fwd.x + to.y * fwd.y) > 0 then return n, heading end
        end
    end
    return nil
end

local function PlaceStrip(pos, heading)
    local hash = LoadModel('p_ld_stinger_s')
    if not hash then return nil end
    local ok, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 2.0, false)
    local obj = CreateObject(hash, pos.x, pos.y, (ok and gz or pos.z), true, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    TagUnitEntity(obj)
    return obj
end

-- Called by RequestUnit for roadblock / spikes. Returns true if it handled it (there's a pursuit on).
function DeployAhead(kind)
    if not S or S.terminated or not DoesEntityExist(S.veh) then return false end
    local node, heading = AheadPoint(S.veh, kind == 'spikes' and (PC.SpikeLead or 12) or (PC.RoadblockLead or 16))
    if not node then Notify('No good spot ahead of them - try again in a moment.') return true end
    local fwd = vector3(-math.sin(math.rad(heading)), math.cos(math.rad(heading)), 0.0)
    -- make "forward" the direction the suspect is travelling
    local sf = GetEntityForwardVector(S.veh)
    if fwd.x * sf.x + fwd.y * sf.y < 0 then heading = (heading + 180.0) % 360.0 fwd = -fwd end
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local u
    if kind == 'roadblock' then
        u = BuildUnit('roadblock', node + fwd * 6.0, (heading + 90.0) % 360.0, {})
        if not u then return true end
        u.state = 'blocking'
        u.until_ = GetGameTimer() + 150000
        SetVehicleSiren(u.veh, true)
        SetVehicleHasMutedSirens(u.veh, true)
        SetVehicleEngineOn(u.veh, true, true, false)
        -- a second car if one is spare, nose to tail across the other lane
        Notify('~b~Roadblock~s~ is being set up ahead of the suspect.')
        RadioLine(('Unit: roadblock set on %s.'):format(Street(node)))
        CreateThread(function()
            Wait(500)
            UnitGetOut(u)
            Wait(2000)
            for k, p in ipairs(u.crew) do
                if Alive(p) and Control(p, 300) then
                    local spot = GetOffsetFromEntityInWorldCoords(u.veh, (k % 2 == 1) and 1.0 or -1.0, -2.5, 0.0)
                    TaskGoToCoordAnyMeans(p, spot.x, spot.y, spot.z, 2.0, 0, false, 786603, 0.0)
                end
            end
        end)
    else
        u = BuildUnit('spikes', node + right * 7.5 - fwd * 4.0, heading, {})
        if not u then return true end
        u.state = 'spiking'
        u.until_ = GetGameTimer() + 120000
        u.props = {}
        SetVehicleSiren(u.veh, true)
        SetVehicleHasMutedSirens(u.veh, true)
        for _, x in ipairs({ -5.2, -1.8, 1.6 }) do
            local o = PlaceStrip(node + right * x, heading + 0.0)
            if o then u.props[#u.props + 1] = o Strips[#Strips + 1] = { obj = o, u = u } end
        end
        Notify('~b~Spike strips~s~ are down ahead of the suspect - drive them into it.')
        RadioLine(('Unit: stop sticks deployed on %s.'):format(Street(node)))
        CreateThread(function()
            Wait(500)
            UnitGetOut(u)
            Wait(2500)
            local d = UnitDriver(u)
            if d and Control(d, 300) then
                local spot = node + right * 11.0
                TaskGoToCoordAnyMeans(d, spot.x, spot.y, spot.z, 2.0, 0, false, 786603, 0.0)
            end
        end)
    end
    return true
end

local WHEELS = { { 'wheel_lf', 0 }, { 'wheel_rf', 1 }, { 'wheel_lm1', 2 }, { 'wheel_rm1', 3 }, { 'wheel_lr', 4 }, { 'wheel_rr', 5 } }

local function CheckStrips(veh)
    local hit = false
    for _, s in ipairs(Strips) do
        if DoesEntityExist(s.obj) and #(GetEntityCoords(s.obj) - GetEntityCoords(veh)) < 8.0 then
            for _, w in ipairs(WHEELS) do
                local b = GetEntityBoneIndexByName(veh, w[1])
                if b ~= -1 then
                    local wp = GetWorldPositionOfEntityBone(veh, b)
                    local o = GetOffsetFromEntityGivenWorldCoords(s.obj, wp.x, wp.y, wp.z)
                    if math.abs(o.x) < 2.1 and math.abs(o.y) < 0.55 and math.abs(o.z) < 1.2 and not IsVehicleTyreBurst(veh, w[2], false) then
                        if Control(veh, 200) then SetVehicleTyreBurst(veh, w[2], true, 1000.0) end
                        hit = true
                    end
                end
            end
        end
    end
    return hit
end

CreateThread(function()
    while true do
        local wait = 500
        if #Strips > 0 then
            -- the suspect, plus any non-emergency car that drives over them
            local near = false
            local pos = MyPos()
            for _, s in ipairs(Strips) do if DoesEntityExist(s.obj) and #(GetEntityCoords(s.obj) - pos) < 400.0 then near = true end end
            if near then
                wait = 0
                if S and DoesEntityExist(S.veh) and CheckStrips(S.veh) and not S.spiked then
                    S.spiked = true
                    Notify('~g~They hit the spikes!')
                    RadioLine('Unit: suspect vehicle has hit the stop sticks, tyres are deflating!')
                    if PC.SpikedSlow ~= false and Control(S.veh, 300) then SetVehicleMaxSpeed(S.veh, 18.0) end
                end
            end
        end
        Wait(wait)
    end
end)

local function ClearStrips(u)
    for i = #Strips, 1, -1 do
        local s = Strips[i]
        if not u or s.u == u then
            if DoesEntityExist(s.obj) then DeleteEntity(s.obj) end
            table.remove(Strips, i)
        end
    end
end

---------------------------------------------------------------------------
-- Units in the chase
---------------------------------------------------------------------------
local CHASERS = { backup = true, swat = true, k9 = true }

local function Ahead(sVeh, pos)
    local o = GetOffsetFromEntityGivenWorldCoords(sVeh, pos.x, pos.y, pos.z)
    return o.y > 4.0
end

local function JoinChase(u)
    u.pursuit = true
    u.role = nil
    u.state = 'pursuit'
    u.retask = 0
    if DoesEntityExist(u.veh) and Control(u.veh, 300) then
        SetVehicleSiren(u.veh, true)
        SetVehicleHasMutedSirens(u.veh, false)
    end
    UnitBoard(u)
end

local function LeaveChase(u, stay)
    u.pursuit, u.role, u.chaseTask = nil, nil, nil
    if u.kind == 'k9' then u.k9done = true end
    if u.veh == 0 or not DoesEntityExist(u.veh) then return end
    if Control(u.veh, 300) then SetVehicleHasMutedSirens(u.veh, true) end
    local d = UnitDriver(u)
    if stay and #(GetEntityCoords(u.veh) - MyPos()) < 80.0 then
        u.state = 'arriving'
        CreateThread(function()
            if d and Control(d, 300) then TaskVehicleTempAction(d, u.veh, 27, 2500) end
            Wait(1200)
            if u.pursuit or u.state ~= 'arriving' then return end
            UnitGetOut(u)
            u.state = 'onscene'
        end)
    else
        u.state = 'enroute'
        u.lastMove, u.started = GetGameTimer(), GetGameTimer()
        UnitDrive(u, MyPos(), false)
    end
end

local function DriveChase(u, idx)
    local d = UnitDriver(u)
    if not d or not Control(d, 300) or not IsPedInVehicle(d, u.veh, false) then return end
    local sDrv = GetPedInVehicleSeat(S.veh, -1)
    if sDrv == 0 then return end
    local upos = GetEntityCoords(u.veh)
    local dist = #(upos - GetEntityCoords(S.veh))
    SetDriverAbility(d, 1.0)
    SetDriverAggressiveness(d, 0.85)
    local now = GetGameTimer()
    local function Fresh(role, every)
        -- only re-issue a task when the role changes (or now and then for long tasks), so cars don't stutter
        if u.role == role and now - (u.chaseTask or 0) < (every or 20000) then return false end
        u.role, u.chaseTask = role, now
        return true
    end
    if dist > 250.0 then
        if Fresh('catchup', 6000) then
            local sp = GetEntityCoords(S.veh)
            TaskVehicleDriveToCoordLongrange(d, u.veh, sp.x, sp.y, sp.z, 45.0, 1074528293, 20.0)
        end
    elseif idx == 2 and PC.RollingBlock ~= false and Ahead(S.veh, upos) and dist < 60.0 then
        -- got in front: rolling roadblock, slow them down from the front
        if u.role ~= 'block' then RadioLine('Unit: I\'m in front, starting a rolling roadblock.', true) end
        if Fresh('block', 5000) then
            TaskVehicleEscort(d, u.veh, S.veh, 0, math.max(8.0, GetEntitySpeed(S.veh) - 4.0), 1074528293, 4.0, 0, 20.0)
        end
    elseif idx == 3 and dist < 60.0 then
        if Fresh('flank', 8000) then
            TaskVehicleEscort(d, u.veh, S.veh, 3, GetEntitySpeed(S.veh) + 6.0, 1074528293, 3.0, 0, 20.0)
        end
    else
        if Fresh(idx == 1 and 'primary' or 'support') then
            TaskVehicleChase(d, sDrv)
            pcall(SetTaskVehicleChaseIdealPursuitDistance, d, idx == 1 and 0.0 or 14.0)
            pcall(SetTaskVehicleChaseBehaviorFlag, d, 1, true)
        end
    end
end

local function AIPit(u)
    if u.role ~= 'primary' or not PitAllowed() or PC.AIPIT == false then return end
    local upos = GetOffsetFromEntityInWorldCoords(u.veh, 0.0, 2.2, 0.0)
    local side = PitSide(S.veh, upos)
    local sp, us = GetEntitySpeed(S.veh), GetEntitySpeed(u.veh)
    if side and IsEntityTouchingEntity(u.veh, S.veh) and sp > 8.0 and sp < 40.0 and math.abs(sp - us) < 9.0 and math.random() < 0.5 then
        S.lastPit = GetGameTimer()
        Spin(S.veh, side, 'Backup')
    end
end

local function BoxIn()
    if S.boxed or not DoesEntityExist(S.veh) then return end
    if GetEntitySpeed(S.veh) > 3.0 then return end
    local sp = GetEntityCoords(S.veh)
    local n = 0
    for _, u in ipairs(SWUnits) do if u.pursuit and DoesEntityExist(u.veh) and #(GetEntityCoords(u.veh) - sp) < 12.0 then n = n + 1 end end
    local myVeh = GetVehiclePedIsIn(Me(), false)
    if myVeh ~= 0 and #(GetEntityCoords(myVeh) - sp) < 12.0 then n = n + 1 end
    if n >= 2 then
        S.boxed = true
        S.terminated = true      -- nobody rejoins the chase on a boxed-in car
        if Control(S.veh, 300) then
            SetVehicleEngineOn(S.veh, false, true, true)
            SetVehicleUndriveable(S.veh, true)
        end
        Notify('~g~Suspect boxed in!~s~ Get them out at gunpoint.')
        RadioLine(Callsign() .. ': suspect vehicle boxed in, pursuit terminated - felony stop!')
        -- units stop where they are
        for _, u in ipairs(SWUnits) do if u.pursuit then LeaveChase(u, true) end end
    end
end

function TerminatePursuit()
    if not S then return Notify('There\'s no pursuit to call off.') end
    S.terminated = true
    for _, u in ipairs(SWUnits) do if u.pursuit then LeaveChase(u, false) end end
    RadioLine(Callsign() .. ': terminating the pursuit, all units disengage.')
    SetTimeout(1500, function() RadioLine('Dispatch: copy, pursuit terminated. Units resume normal patrol.') end)
    if S.e and S.e.blip then SetBlipFlashes(S.e.blip, false) end
end
RegisterCommand('terminate', function() TerminatePursuit() end, false)

CreateThread(function()
    while true do
        Wait(600)
        local e = FindSuspect()
        if e and (not S or S.e ~= e) then
            S = { e = e, veh = e.veh, started = GetGameTimer(), lastPit = 0 }
        elseif not e and S then
            -- it's over: they bailed, crashed, gave up or got away
            for _, u in ipairs(SWUnits) do if u.pursuit then LeaveChase(u, true) end end
            for _, u in ipairs(SWUnits) do
                if (u.kind == 'spikes' or u.kind == 'roadblock') and u.state ~= 'leaving' then
                    SetTimeout(20000, function() ClearStrips(u) UnitLeave(u) end)
                end
            end
            S = nil
        end
        if S and not S.terminated then
            local now = GetGameTimer()
            local sp = DoesEntityExist(S.veh) and GetEntityCoords(S.veh)
            if sp then
                local idx = 0
                for _, u in ipairs(SWUnits) do
                    if CHASERS[u.kind] and u.state ~= 'leaving' and u.veh ~= 0 and DoesEntityExist(u.veh) then
                        if not u.pursuit and u.state ~= 'arriving' and u.state ~= 'parking' and #(GetEntityCoords(u.veh) - sp) < 900.0 then JoinChase(u) end
                        if u.pursuit then
                            idx = idx + 1
                            if now > (u.retask or 0) then
                                u.retask = now + 2500
                                if UnitAllIn(u) then
                                    DriveChase(u, idx)
                                elseif now - (u.boardAt or 0) > 8000 then
                                    -- someone didn't make it in: try again, and go without them after a while
                                    u.boardAt = now
                                    u.boardTries = (u.boardTries or 0) + 1
                                    if u.boardTries > 3 then
                                        local alive = {}
                                        for _, p in ipairs(u.crew) do if p ~= u.dog and IsPedInVehicle(p, u.veh, false) then alive[#alive + 1] = p end end
                                        if #alive > 0 then
                                            for _, p in ipairs(u.crew) do if not IsPedInVehicle(p, u.veh, false) then u.left = u.left or {} u.left[#u.left + 1] = p end end
                                            u.crew = alive
                                            if u.dog and DoesEntityExist(u.dog) then u.crew[#u.crew + 1] = u.dog end
                                        end
                                    else
                                        UnitBoard(u)
                                    end
                                end
                            end
                            AIPit(u)
                        end
                    end
                end
                BoxIn()
                -- supervisor
                local mins = (now - S.started) / 60000
                if not S.warned and mins * 60 > (PC.TerminateAfter or 420) then
                    S.warned = true
                    RadioLine('Supervisor: ' .. Callsign() .. ', this pursuit has gone on long enough. Terminate unless you have air support or a clear plan.')
                    Notify('~o~Supervisor advises terminating the pursuit.~s~ Type /terminate or use the patrol computer.')
                elseif not S.speedWarned and GetEntitySpeed(S.veh) > (PC.DangerSpeed or 55.0) then
                    S.speedWarned = true
                    RadioLine('Supervisor: speeds are getting dangerous - consider spike strips or backing off.', true)
                end
            end
        end
        -- strips whose unit has gone or was dismissed
        for i = #Strips, 1, -1 do
            local s = Strips[i]
            if not DoesEntityExist(s.obj) or s.u.state == 'leaving' then
                if DoesEntityExist(s.obj) then DeleteEntity(s.obj) end
                table.remove(Strips, i)
            end
        end
        -- strips and roadblocks time out
        for _, u in ipairs(SWUnits) do
            if (u.state == 'spiking' or u.state == 'blocking') and GetGameTimer() > (u.until_ or 0) then
                ClearStrips(u)
                UnitLeave(u)
            end
        end
    end
end)

function PursuitInfo()
    if not S then return nil end
    local units = 0
    for _, u in ipairs(SWUnits) do if u.pursuit then units = units + 1 end end
    return { minutes = math.floor((GetGameTimer() - S.started) / 60000), units = units, terminated = S.terminated == true,
        street = DoesEntityExist(S.veh) and Street(GetEntityCoords(S.veh)) or '' }
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearStrips()
end)
