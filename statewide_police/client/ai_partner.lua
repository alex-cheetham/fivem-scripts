-- Statewide PD: your AI partner (a deputy who rides with you) or, in the K9 division, your police dog.
-- The partner follows you, gets in and out of the car with you, covers your stops, joins fights,
-- and takes orders: frisk, search, cuff, put in the car, watch them, run the plate.
-- The dog: sniff a vehicle, track a runner, search for thrown-away evidence, bite on command, heel.
local P = nil              -- { ped, dog, busyUntil, retask, mode, blip }
local Division = 'patrol'

local function Alive(p) return p and DoesEntityExist(p) and not IsPedDeadOrDying(p, true) end
local function IsRestrained(e) return e.status == 'cuffed' or e.status == 'escorted' or e.status == 'seated' end
function PartnerPed() return P and P.ped or nil end
function PartnerIsDog() return P ~= nil and P.dog == true and Alive(P.ped) end
function SetDivision(d) Division = d or 'patrol' end
function MyDivision() return Division end

function PartnerInfo()
    if not P then return nil end
    return { kind = 'partner', label = P.dog and 'K9 partner' or 'Partner', state = not Alive(P.ped) and 'down' or (P.busyUntil and GetGameTimer() < P.busyUntil and 'busy' or 'with you') }
end

local function Register(ped)
    CreateThread(function()
        if not ped then TriggerCallback('aiPartner', nil) return end
        local t = GetGameTimer() + 5000
        while DoesEntityExist(ped) and not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < t do Wait(100) end
        for _ = 1, 6 do
            if not P or P.ped ~= ped or not DoesEntityExist(ped) then return end
            local r = TriggerCallback('aiPartner', NetworkGetNetworkIdFromEntity(ped))
            if r and r.ok then return end
            Wait(1500)
        end
    end)
end

local function GoTo(ped, target, dist, ms, run)
    if not Control(ped, 500) then return false end
    ClearPedTasks(ped)
    TaskGoToEntity(ped, target, ms or 12000, dist or 1.2, run and 3.0 or 2.0, 1073741824, 0)
    local t = GetGameTimer() + (ms or 12000)
    while GetGameTimer() < t do
        if not Alive(ped) or not DoesEntityExist(target) then return false end
        if Dist(ped, target) <= (dist or 1.2) + 0.6 then return true end
        Wait(200)
    end
    return Dist(ped, target) <= (dist or 1.2) + 1.5
end

local function Busy(ms) if P then P.busyUntil = GetGameTimer() + ms end end
local function Free() if P then P.busyUntil = nil end end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------
function SpawnPartner()
    if P and Alive(P.ped) then return Notify('Your partner is already with you.') end
    if P then DismissPartner() end
    local me = Me()
    local dog = Division == 'k9'
    local veh = GetVehiclePedIsIn(me, false)
    local ped
    if dog then
        local model = (AI.Units.k9 and AI.Units.k9.dog) or 'a_c_shepherd'
        if veh ~= 0 then
            local seat = IsVehicleSeatFree(veh, 1) and 1 or (IsVehicleSeatFree(veh, 0) and 0 or nil)
            if seat then ped = SpawnPed(model, nil, nil, veh, seat) end
        end
        if not ped then
            local pos = GetOffsetFromEntityInWorldCoords(me, 1.0, -1.0, 0.0)
            ped = SpawnPed(model, pos - vector3(0.0, 0.0, 0.9), GetEntityHeading(me))
        end
        if ped then
            SetPedRelationshipGroupHash(ped, CopsGroup())
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetEntityMaxHealth(ped, 400)
            SetEntityHealth(ped, 400)
        end
    else
        if veh ~= 0 and IsVehicleSeatFree(veh, 0) then
            ped = SpawnUnitPed('partner', veh, 0)
        else
            local pos = GetOffsetFromEntityInWorldCoords(me, 1.2, -1.4, 0.0)
            ped = SpawnUnitPed('partner', nil, nil, pos - vector3(0.0, 0.0, 0.9), GetEntityHeading(me))
        end
    end
    if not ped then return Notify('Couldn\'t find a partner for you right now.') end
    TagUnitEntity(ped)
    SetPedKeepTask(ped, true)
    SetEntityInvincible(ped, false)
    local blip = AddBlipForEntity(ped)
    SetBlipColour(blip, 3)
    SetBlipScale(blip, 0.6)
    SetBlipAsShortRange(blip, true)
    NamedBlip(blip, dog and 'K9 partner' or 'Partner')
    P = { ped = ped, dog = dog, retask = 0, blip = blip }
    Register(ped)
    if dog then
        Notify('~b~Your K9 partner is with you.~s~ Use K9 orders in the stop menu or the patrol computer (Units).')
        RadioLine(Callsign() .. ': K9 unit in service.', true)
    else
        Notify('~b~Your partner is riding with you.~s~ Give orders from the stop menu (Orders > Partner).')
        RadioLine(Callsign() .. ': two-officer unit, in service.', true)
    end
end

function DismissPartner()
    if not P then return false end
    local p = P
    P = nil
    RemoveBlipSafe(p.blip)
    Register(nil)
    if DoesEntityExist(p.ped) then
        if IsPedInAnyVehicle(p.ped, false) and Control(p.ped, 500) then TaskLeaveVehicle(p.ped, GetVehiclePedIsIn(p.ped, false), 0) end
        SetTimeout(3000, function()
            if DoesEntityExist(p.ped) and Control(p.ped, 500) then TaskWanderStandard(p.ped, 10.0, 10) end
            SetTimeout(20000, function() Vanish(p.ped) end)
        end)
    end
    return true
end

---------------------------------------------------------------------------
-- K9 work (shared with the K9 unit you can call)
---------------------------------------------------------------------------
function K9Sniff(dog, veh, entry)
    for _, off in ipairs({ { -1.8, 2.6 }, { 1.8, 2.6 }, { 1.8, -2.6 }, { -1.8, -2.6 } }) do
        local p = GetOffsetFromEntityInWorldCoords(veh, off[1], off[2], 0.0)
        if Control(dog, 300) then TaskGoToCoordAnyMeans(dog, p.x, p.y, p.z, 1.6, 0, false, 786603, 0.0) end
        local t = GetGameTimer() + 5000
        while #(GetEntityCoords(dog) - p) > 1.3 and GetGameTimer() < t do Wait(200) end
    end
    local r = TriggerCallback('aiK9', VehToNet(veh), entry and entry.pid or nil)
    if not r or not r.ok then return Result(r) end
    if r.alert then
        if Control(dog, 300) and LoadDict('creatures@rottweiler@amb@world_dog_sitting@base') then
            TaskPlayAnim(dog, 'creatures@rottweiler@amb@world_dog_sitting@base', 'base', 8.0, -8.0, 6000, 1, 0.0, false, false, false)
        end
        Notify('~r~K9 indication!~s~ The dog has alerted on the vehicle - you have probable cause to search.')
        RadioLine('K9: positive indication on the vehicle.')
        for _, o in pairs(AIPeds) do if o.veh == veh then o.pc = true end end
    else
        Notify('K9: no indication from the dog.')
        RadioLine('K9: negative, no indication.', true)
    end
    Wait(4000)
    return r.alert
end

-- Runs the target down and holds them. Returns true once they're on the ground.
function K9Bite(dog, e)
    if not Alive(dog) or not e or not DoesEntityExist(e.ped) or not Control(dog, 300) then return false end
    if Dist(dog, e.ped) < 2.0 then
        if Control(e.ped, 300) then
            if e.status == 'hiding' then SetPedStealthMovement(e.ped, false, 'DEFAULT_ACTION') end
            if LoadDict('creatures@rottweiler@melee@') then
                TaskPlayAnim(dog, 'creatures@rottweiler@melee@', 'dog_takedown_from_front', 8.0, -8.0, 2500, 0, 0.0, false, false, false)
            end
            SetPedToRagdoll(e.ped, 3500, 3500, 0, false, false, false)
            ApplyDamageToPed(e.ped, 8, false)
            Notify('~b~K9~s~ has the suspect!')
            RadioLine('K9: dog has made contact, suspect detained.', true)
            local tg = e
            SetTimeout(3500, function() if AIPeds[tg.ped] == tg then Surrender(tg) end end)
            return true
        end
    else
        TaskGoToEntity(dog, e.ped, -1, 1.0, 5.0, 1073741824, 0)
    end
    return false
end

local function NearestRunner(from, range, statuses)
    local best, bd = nil, range
    for ped, e in pairs(AIPeds) do
        if statuses[e.status] then
            local d = #(GetEntityCoords(ped) - from)
            if d < bd then best, bd = e, d end
        end
    end
    return best, bd
end

local function K9Track()
    local dog = P.ped
    local e, d = NearestRunner(GetEntityCoords(dog), 260.0, { fleeing = true, hiding = true, fighting = true })
    if not e then
        -- nothing live: maybe a case suspect hiding out of range
        Notify('K9: the dog can\'t pick up a scent here.')
        return
    end
    Busy(90000)
    Notify(('~b~K9:~s~ the dog has a scent - follow it (%dm).'):format(math.floor(d)))
    RadioLine(Callsign() .. ': K9 is tracking, ' .. Heading(dog) .. '.', true)
    CreateThread(function()
        local t = GetGameTimer() + 90000
        while P and P.ped == dog and Alive(dog) and GetGameTimer() < t and AIPeds[e.ped] == e do
            if e.status ~= 'fleeing' and e.status ~= 'hiding' and e.status ~= 'fighting' then break end
            if K9Bite(dog, e) then break end
            Wait(600)
        end
        Free()
    end)
end

local function K9Articles()
    local dog = P.ped
    local drop = NearestDrop and NearestDrop(GetEntityCoords(dog), 80.0)
    if not drop then
        Busy(9000)
        CreateThread(function()
            local c = GetEntityCoords(dog)
            for _ = 1, 3 do
                local p = c + vector3(math.random(-8, 8), math.random(-8, 8), 0.0)
                if Control(dog, 300) then TaskGoToCoordAnyMeans(dog, p.x, p.y, p.z, 1.6, 0, false, 786603, 0.0) end
                Wait(2800)
            end
            Notify('K9: article search - nothing found nearby.')
            Free()
        end)
        return
    end
    Busy(30000)
    Notify('~b~K9:~s~ searching for articles...')
    CreateThread(function()
        if Control(dog, 300) then TaskGoToCoordAnyMeans(dog, drop.x, drop.y, drop.z, 2.5, 0, false, 786603, 0.0) end
        local t = GetGameTimer() + 25000
        while Alive(dog) and #(GetEntityCoords(dog) - drop) > 1.5 and GetGameTimer() < t do Wait(300) end
        if Alive(dog) and #(GetEntityCoords(dog) - drop) <= 2.5 then
            if Control(dog, 300) and LoadDict('creatures@rottweiler@amb@world_dog_sitting@base') then
                TaskPlayAnim(dog, 'creatures@rottweiler@amb@world_dog_sitting@base', 'base', 8.0, -8.0, 8000, 1, 0.0, false, false, false)
            end
            Notify('~y~K9 indication!~s~ The dog is sitting on something - go and bag it.')
            RadioLine('K9: dog has indicated on an article.', true)
            SetNewWaypoint(drop.x, drop.y)
        end
        Wait(8000)
        Free()
    end)
end

---------------------------------------------------------------------------
-- Orders
---------------------------------------------------------------------------
local function PartnerSay(text) SendNUIMessage({ action = 'aiSay', name = P and P.dog and 'K9' or 'Partner', text = text, me = true }) end

local function CuffBy(cop, e)
    local ped = e.ped
    if not Control(ped) or not Control(cop) then return false end
    e.status = 'cuffing'
    ClearPedTasksImmediately(ped)
    local spot = GetOffsetFromEntityInWorldCoords(cop, 0.0, 0.7, 0.0)
    SetEntityCoords(ped, spot.x, spot.y, spot.z - 1.0, false, false, false, false)
    SetEntityHeading(ped, GetEntityHeading(cop))
    if LoadDict('mp_arrest_paired') then
        TaskPlayAnim(ped, 'mp_arrest_paired', 'crook_p2_back_right', 8.0, -8.0, 3700, 0, 0.0, false, false, false)
        TaskPlayAnim(cop, 'mp_arrest_paired', 'cop_p2_back_right', 8.0, -8.0, 3700, 0, 0.0, false, false, false)
    end
    Wait(3700)
    if not DoesEntityExist(ped) then return false end
    SetEnableHandcuffs(ped, true)
    RemoveAllPedWeapons(ped, true)
    if LoadDict('mp_arresting') then TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false) end
    e.cuffProp = AttachProp('cuffs', ped)
    e.status, e.kneel = 'cuffed', false
    RemoveBlipSafe(e.blip)
    e.blip = nil
    local r = TriggerCallback('aiState', e.pid, 'cuffed', true)
    if r and r.say then Say(e, r.say) end
    return true
end

local function SeatBy(cop, e)
    local myCar = GetVehiclePedIsIn(Me(), true)
    if myCar == 0 or not DoesEntityExist(myCar) then return Notify('Partner: where\'s the car?') end
    local seat
    for _, s in ipairs({ 1, 2 }) do if IsVehicleSeatFree(myCar, s) then seat = s break end end
    if not seat then return Notify('Partner: the back seats are full.') end
    if not GoTo(cop, e.ped, 1.2) or not Control(e.ped) then return Notify('Partner couldn\'t get to them.') end
    DetachEntity(e.ped, true, false)
    ClearPedTasksImmediately(e.ped)
    SetPedCanRagdoll(e.ped, false)
    AttachEntityToEntity(e.ped, cop, 11816, 0.38, 0.55, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    e.escortBy = cop
    e.status = 'escorted'
    local door = GetOffsetFromEntityInWorldCoords(myCar, seat == 1 and -1.6 or 1.6, -0.6, 0.0)
    TaskGoToCoordAnyMeans(cop, door.x, door.y, door.z, 1.0, 0, false, 786603, 0.0)
    local t = GetGameTimer() + 20000
    while GetGameTimer() < t and Alive(cop) and #(GetEntityCoords(cop) - door) > 1.6 do Wait(250) end
    if not DoesEntityExist(e.ped) or not Control(e.ped) then return end
    DetachEntity(e.ped, true, false)
    SetPedCanRagdoll(e.ped, true)
    e.escortBy = nil
    if e.status ~= 'escorted' then return Notify('Partner lost hold of them.') end
    TaskWarpPedIntoVehicle(e.ped, myCar, seat)
    e.status, e.seatVeh, e.escAnim = 'seated', myCar, nil
    PartnerSay('They\'re in the back of the car.')
end

local TESTS = { frisk = { ms = 5000 }, search = { ms = 8000 } }

function PartnerOrder(e, d)
    if not P or not Alive(P.ped) then return Notify('You don\'t have a partner with you (request one from Units).') end
    local cmd = d.cmd
    local cop = P.ped
    if P.busyUntil and GetGameTimer() < P.busyUntil and cmd ~= 'heel' then return Notify('Your partner is busy.') end
    if IsPedInAnyVehicle(cop, false) and cmd ~= 'plate' and cmd ~= 'heel' then
        if Control(cop, 300) then TaskLeaveVehicle(cop, GetVehiclePedIsIn(cop, false), 0) end
        Wait(1500)
    end
    if cmd == 'heel' then
        Free()
        if Control(cop, 300) then ClearPedTasks(cop) end
        return Notify(P.dog and 'K9: heel.' or 'Partner: back with you.')
    end
    if P.dog then
        if cmd == 'sniff' then
            local veh = e and e.veh
            if not veh or not DoesEntityExist(veh) then return Notify('No vehicle to sniff.') end
            ClosePanelAI()
            Busy(40000)
            CreateThread(function() K9Sniff(cop, veh, e) Free() end)
        elseif cmd == 'bite' then
            if not e then return end
            ClosePanelAI()
            Busy(30000)
            RadioLine(Callsign() .. ': releasing the dog!', true)
            CreateThread(function()
                local t = GetGameTimer() + 30000
                while P and Alive(cop) and GetGameTimer() < t and AIPeds[e.ped] == e and not IsRestrained(e) do
                    if K9Bite(cop, e) then break end
                    Wait(500)
                end
                Free()
            end)
        elseif cmd == 'track' then
            K9Track()
        elseif cmd == 'articles' then
            K9Articles()
        end
        return
    end
    -- a human partner
    if cmd == 'plate' then
        if not e or not e.veh then return Notify('No vehicle.') end
        PartnerSay('I\'ll run the plate.')
        local veh = e.veh
        local r = TriggerCallback('aiVehicle', VehToNet(veh), e.pid)
        if not r or not r.ok then return Result(r) end
        r.kind = 'plate'
        r.model = VehLabel and VehLabel(veh) or ''
        for _, f in ipairs(r.flags or {}) do if f:find('STOLEN') then e.pc = true end end
        RadioLine(('Dispatch: %s comes back to %s%s.'):format(r.plate, r.owner, #(r.flags or {}) > 0 and (' - ' .. table.concat(r.flags, ', ')) or ', no flags'))
        e.result = r
        PanelRefresh()
        return
    end
    if not e or not DoesEntityExist(e.ped) then return end
    if cmd == 'watch' then
        PartnerSay('I\'ve got eyes on them.')
        Busy(30000)
        if Control(cop, 300) then TaskAimGunAtEntity(cop, e.ped, 30000, false) end
        return
    end
    ClosePanelAI()
    Busy(45000)
    CreateThread(function()
        if cmd == 'frisk' or cmd == 'search' then
            if IsPedInAnyVehicle(e.ped, false) then Free() return Notify('Get them out of the vehicle first.') end
            if cmd == 'search' and not IsRestrained(e) and not e.pc and not (e.consent and e.consent.person) then
                local c = TriggerCallback('aiConsent', e.pid, 'person')
                if c and c.ok then Say(e, c.say) end
                e.consent = e.consent or {}
                e.consent.person = c and c.yes or false
                if not e.consent.person then Free() return Notify('They refused. Your partner can pat them down, or you need probable cause.') end
            end
            PartnerSay(cmd == 'frisk' and 'Turn around, I\'m going to pat you down for weapons.' or 'Turn around, I\'m going to search you.')
            if not GoTo(cop, e.ped, 1.0) then Free() return Notify('Partner couldn\'t get to them.') end
            if not IsRestrained(e) and e.status ~= 'surrendered' then
                local act = AIReact(e, 'search')
                if ApplyReaction(e, act) then Free() return end
            end
            TaskTurnPedToFaceEntity(cop, e.ped, 1000)
            Wait(800)
            if Control(cop, 300) then TaskStartScenarioInPlace(cop, 'PROP_HUMAN_BUM_BIN', 0, true) end
            Wait(TESTS[cmd].ms)
            if Control(cop, 300) then ClearPedTasks(cop) end
            local r = TriggerCallback('aiTest', e.pid, cmd)
            if not r or not r.ok then Free() return Result(r) end
            if r.items then for _, it in ipairs(r.items) do if not it.legal then e.pc = true end end end
            e.result = r
            local n = r.items and #r.items or 0
            PartnerSay(n > 0 and ('Found ' .. n .. ' item' .. (n == 1 and '' or 's') .. ' - check the results.') or 'They\'re clean.')
            OpenPanelAI(e)
        elseif cmd == 'cuff' then
            if IsRestrained(e) then Free() return Notify('They\'re already cuffed.') end
            if IsPedInAnyVehicle(e.ped, false) then Free() return Notify('Get them out of the vehicle first.') end
            PartnerSay('Hands behind your back!')
            if not GoTo(cop, e.ped, 0.9) then Free() return Notify('Partner couldn\'t get to them.') end
            if e.status ~= 'surrendered' then
                local act = AIReact(e, 'cuff')
                if ApplyReaction(e, act) then Free() return end
            end
            if CuffBy(cop, e) then PartnerSay('Cuffs on.') end
        elseif cmd == 'seat' then
            if e.status ~= 'cuffed' and e.status ~= 'escorted' then Free() return Notify('Cuff them first.') end
            if e.status == 'escorted' then
                Free()
                return Notify('You\'re holding them - seat them yourself, or let go first.')
            end
            SeatBy(cop, e)
        end
        Free()
    end)
end

-- Stop menu buttons
ACTIONS_AI.partner = function(e, d) PartnerOrder(e, d) end
local oldK9 = ACTIONS_AI.k9
ACTIONS_AI.k9 = function(e, d)
    if PartnerIsDog() then return PartnerOrder(e, { cmd = 'sniff' }) end
    return oldK9(e, d)
end

---------------------------------------------------------------------------
-- Behaviour loop
---------------------------------------------------------------------------
local function Threat(from, range)
    local best, bd = nil, range
    for ped, e in pairs(AIPeds) do
        if e.status == 'fighting' then
            local d = #(GetEntityCoords(ped) - from)
            if d < bd then best, bd = e, d end
        end
    end
    return best
end

CreateThread(function()
    while true do
        Wait(500)
        if P then
            local ped = P.ped
            local me = Me()
            local now = GetGameTimer()
            if not DoesEntityExist(ped) then
                RemoveBlipSafe(P.blip)
                P = nil
                Register(nil)
            elseif IsPedDeadOrDying(ped, true) then
                if not P.downAt then
                    P.downAt = now
                    Notify(P.dog and '~r~Your K9 is down!' or '~r~Your partner is down!')
                    RadioLine('Dispatch: all units, officer down - ' .. Street(GetEntityCoords(ped)) .. '!')
                    RemoveBlipSafe(P.blip)
                elseif now - P.downAt > 90000 then
                    local p = P
                    P = nil
                    Register(nil)
                    Vanish(p.ped)
                end
            elseif not IsPedAPlayer(ped) and Control(ped, 200) then
                local myVeh = GetVehiclePedIsIn(me, false)
                local inVeh = IsPedInAnyVehicle(ped, false)
                local busy = P.busyUntil and now < P.busyUntil
                if not busy then
                    if myVeh ~= 0 then
                        -- in the car with you
                        if not IsPedInVehicle(ped, myVeh, false) then
                            local seat = P.dog and (IsVehicleSeatFree(myVeh, 1) and 1 or 2) or (IsVehicleSeatFree(myVeh, 0) and 0 or 1)
                            local far = Dist(ped, myVeh) > 30.0 or (GetEntitySpeed(myVeh) > 4.0)
                            if P.dog or far then
                                if IsVehicleSeatFree(myVeh, seat) and (Dist(ped, myVeh) < 6.0 or far) then TaskWarpPedIntoVehicle(ped, myVeh, seat) end
                                if not P.dog and far then P.retask = now end
                                if P.dog and Dist(ped, myVeh) >= 6.0 and not far and now > P.retask then
                                    P.retask = now + 2500
                                    TaskGoToEntity(ped, myVeh, -1, 2.0, 3.0, 1073741824, 0)
                                end
                            elseif now > P.retask and IsVehicleSeatFree(myVeh, seat) then
                                P.retask = now + 6000
                                TaskEnterVehicle(ped, myVeh, 8000, seat, 2.0, 1, 0)
                            end
                        end
                    else
                        if inVeh then
                            local v = GetVehiclePedIsIn(ped, false)
                            if GetEntitySpeed(v) < 1.0 and now > P.retask then
                                P.retask = now + 3000
                                if P.dog then
                                    local s = GetOffsetFromEntityInWorldCoords(v, -1.8, -1.2, 0.0)
                                    SetEntityCoords(ped, s.x, s.y, s.z - 0.9, false, false, false, false)
                                else
                                    TaskLeaveVehicle(ped, v, 0)
                                end
                            end
                        elseif now > P.retask then
                            P.retask = now + 2000
                            local threat = Threat(GetEntityCoords(ped), 60.0)
                            if threat and P.dog then
                                K9Bite(ped, threat)
                            elseif threat then
                                if not IsPedInCombat(ped, threat.ped) then TaskCombatPed(ped, threat.ped, 0, 16) end
                            elseif not P.dog and StopCover and CurrentStop and CurrentStop() and StopCover(P, ped, 0) then
                                -- covering the stop on the passenger side
                            elseif Dist(ped, me) > 4.0 then
                                TaskFollowToOffsetOfEntity(ped, me, P.dog and 0.8 or 1.3, P.dog and -0.6 or -1.6, 0.0, P.dog and 3.0 or 2.0, -1, 1.5, true)
                            elseif not P.dog and not IsPedUsingAnyScenario(ped) and GetEntitySpeed(ped) < 0.2 and GetEntitySpeed(me) < 0.2 then
                                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_COP_IDLES', 0, true)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Partner goes when you go off duty
CreateThread(function()
    while true do
        Wait(5000)
        if P and not IsPolice then DismissPartner() end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if P and DoesEntityExist(P.ped) then DeleteEntity(P.ped) end
end)
