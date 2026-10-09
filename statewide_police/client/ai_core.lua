-- AI patrol: shared helpers for the AI people officers deal with (tracking, behaviour, spawning, finding places)
AI = Config.AI
AIPeds = {}            -- [ped] = entry { ped, pid, persona, role, status, veh, seat, blip, log, callout, ... }
OnPatrol = false
CurrentCallout = nil   -- set by ai_callouts.lua

local G_SUSPECT, G_COPS
CreateThread(function()
    local _, s = AddRelationshipGroup('SW_AI_SUSPECT')
    local _, c = AddRelationshipGroup('SW_AI_COPS')
    G_SUSPECT, G_COPS = s, c
    local PLAYER, COP = GetHashKey('PLAYER'), GetHashKey('COP')
    SetRelationshipBetweenGroups(5, G_SUSPECT, PLAYER)
    SetRelationshipBetweenGroups(5, G_SUSPECT, G_COPS)
    SetRelationshipBetweenGroups(5, G_SUSPECT, COP)
    SetRelationshipBetweenGroups(5, G_COPS, G_SUSPECT)
    SetRelationshipBetweenGroups(5, COP, G_SUSPECT)
    SetRelationshipBetweenGroups(0, G_COPS, PLAYER)
    SetRelationshipBetweenGroups(0, PLAYER, G_COPS)
    SetRelationshipBetweenGroups(0, G_COPS, COP)
end)
function CopsGroup() return G_COPS end
function SuspectGroup() return G_SUSPECT end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
function Me() return PlayerPedId() end
function MyPos() return GetEntityCoords(PlayerPedId()) end
function PickOne(t) return t[math.random(1, #t)] end
function Dist(a, b) return #(GetEntityCoords(a) - (type(b) == 'number' and GetEntityCoords(b) or b)) end

function Control(ent, ms)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    local t = GetGameTimer() + (ms or 1500)
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        Wait(40)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

function Street(pos)
    local a, b = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    local s = GetStreetNameFromHashKey(a)
    local cross = b ~= 0 and GetStreetNameFromHashKey(b) or ''
    local zone = GetLabelText(GetNameOfZone(pos.x, pos.y, pos.z))
    local out = s ~= '' and s or 'Unknown road'
    if cross ~= '' then out = out .. ' / ' .. cross end
    if zone and zone ~= 'NULL' and zone ~= '' then out = out .. ', ' .. zone end
    return out
end

function NamedBlip(blip, text)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandSetBlipName(blip)
end

-- Network id for a vehicle (registers it with the network first if the game hasn't)
function VehToNet(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if not NetworkGetEntityIsNetworked(veh) then NetworkRegisterEntityAsNetworked(veh) end
    return NetworkGetNetworkIdFromEntity(veh)
end

function RemoveBlipSafe(b) if b and DoesBlipExist(b) then RemoveBlip(b) end end

function Label(e)
    if not e then return 'Subject' end
    if e.persona and e.persona.name then return e.persona.name end
    if e.role == 'driver' then return 'Driver' end
    if e.role == 'passenger' then return 'Passenger' end
    if e.role == 'victim' then return 'Victim' end
    if e.role == 'witness' then return 'Witness' end
    if e.role == 'suspect' then return 'Suspect' end
    return 'Pedestrian'
end

---------------------------------------------------------------------------
-- Talking (subtitles + the panel's conversation log)
---------------------------------------------------------------------------
function Say(e, text)
    if not text or text == '' then return end
    e.log = e.log or {}
    e.log[#e.log + 1] = { who = 'them', text = text }
    SendNUIMessage({ action = 'aiSay', name = Label(e), text = text })
    if PanelEntry == e then PanelRefresh() end
end

function OfficerSay(e, text)
    e.log = e.log or {}
    e.log[#e.log + 1] = { who = 'you', text = text }
    SendNUIMessage({ action = 'aiSay', name = 'You', text = text, me = true })
end

---------------------------------------------------------------------------
-- Tracking people
---------------------------------------------------------------------------
function Track(ped, persona, role, extra)
    local e = AIPeds[ped]
    if not e then
        e = { ped = ped, status = 'free', log = {} }
        AIPeds[ped] = e
    end
    e.pid = persona.pid
    e.persona = persona
    e.role = role or e.role
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

function Untrack(e)
    if not e then return end
    RemoveBlipSafe(e.blip)
    if e.cuffProp then DeleteProp(e.cuffProp) e.cuffProp = nil end
    AIPeds[e.ped] = nil
    if PanelEntry == e then ClosePanelAI() end
end

-- Get (or make up) the person behind a ped. role: driver/passenger/ped/suspect/victim/witness
function Persona(ped, role, profile, veh, story, bindPid)
    local e = AIPeds[ped]
    if e and e.persona then return e end
    if not DoesEntityExist(ped) then return nil end
    if not NetworkGetEntityIsNetworked(ped) then
        NetworkRegisterEntityAsNetworked(ped)
        local t = GetGameTimer() + 1000
        while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < t do Wait(20) end
    end
    local res
    for try = 1, 6 do
        -- a ped we've only just spawned can take a moment to reach the server
        res = TriggerCallback('aiPersona', PedToNet(ped), role, profile or 'public', veh and veh ~= 0 and VehToNet(veh) or nil,
            IsPedMale(ped) and 'm' or 'f', story, bindPid)
        if res and res.ok then break end
        if not DoesEntityExist(ped) then return nil end
        Wait(250 * try)
    end
    if not res or not res.ok then Result(res) return nil end
    if AIPeds[ped] and AIPeds[ped].persona then return AIPeds[ped] end
    return Track(ped, res.persona, role)
end

function Hold(ped)
    if not DoesEntityExist(ped) then return end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, true)
end

---------------------------------------------------------------------------
-- Behaviour
---------------------------------------------------------------------------
-- Stand still facing the officer
function HoldOnFoot(e)
    local ped = e.ped
    if not Control(ped) then return end
    Hold(ped)
    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, Me(), 1500)
    e.status = 'held'
    SetTimeout(1300, function()
        if AIPeds[ped] == e and e.status == 'held' and not IsPedInAnyVehicle(ped, false) and Control(ped, 500) then
            TaskStartScenarioInPlace(ped, PickOne({ 'WORLD_HUMAN_STAND_IMPATIENT', 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT' }), 0, true)
        end
    end)
end

-- Sit in the vehicle with the brakes on
function HoldInVehicle(e)
    local ped, veh = e.ped, GetVehiclePedIsIn(e.ped, false)
    if veh == 0 or not Control(ped) then return end
    Hold(ped)
    if GetPedInVehicleSeat(veh, -1) == ped then
        Control(veh, 800)
        SetEntityAsMissionEntity(veh, true, true)
        TaskVehicleTempAction(ped, veh, 27, 1000000)
    else
        ClearPedTasks(ped)
    end
    e.status = 'held'
end

function SuspectBlip(e, colour)
    RemoveBlipSafe(e.blip)
    local target = (e.status == 'pursuit' and e.veh and DoesEntityExist(e.veh)) and e.veh or e.ped
    e.blip = AddBlipForEntity(target)
    SetBlipColour(e.blip, colour or 1)
    SetBlipScale(e.blip, 0.85)
    SetBlipFlashes(e.blip, true)
    SetBlipAsShortRange(e.blip, false)
    NamedBlip(e.blip, 'Suspect')
end

function FleeOnFoot(e)
    local ped = e.ped
    if not Control(ped) then return end
    Hold(ped)
    ClearPedTasks(ped)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, false)
    SetPedKeepTask(ped, true)
    TaskSmartFleePed(ped, Me(), 800.0, -1, false, false)
    SetPedMoveRateOverride(ped, 1.05)
    e.status = 'fleeing'
    e.fleeSince = GetGameTimer()
    SuspectBlip(e)
    -- some throw away what they're carrying while they run
    if not e.ditchTried then
        e.ditchTried = true
        SetTimeout(math.random(2500, 7000), function()
            if AIPeds[ped] ~= e or e.status ~= 'fleeing' or not DoesEntityExist(ped) or math.random() > 0.7 then return end
            local p = GetEntityCoords(ped)
            local r = TriggerCallback('aiDitch', e.pid, p.x, p.y, p.z)
            if r and r.ok and DropEvidence then
                DropEvidence(r.id, r.label, r.weapon, GetEntityCoords(ped))
            end
        end)
    end
end

-- Out of sight: find somewhere to hide
function Hide(e)
    local ped = e.ped
    if not Control(ped) then return end
    local from = GetEntityCoords(ped)
    local spot = FindFoot(from)
    ClearPedTasks(ped)
    SetPedStealthMovement(ped, true, 'DEFAULT_ACTION')
    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.6, 8000, 0.0, 0.5)
    SetTimeout(5000, function()
        if AIPeds[ped] == e and e.status == 'hiding' and Control(ped, 300) then TaskStandStill(ped, -1) end
    end)
    e.status = 'hiding'
    e.hidAt = GetGameTimer()
    RemoveBlipSafe(e.blip)
    e.blip = AddBlipForRadius(from.x, from.y, from.z, 55.0)
    SetBlipColour(e.blip, 1)
    SetBlipAlpha(e.blip, 90)
    Notify('~o~You lost sight of them.~s~ They\'re hiding somewhere nearby - search the area, or call K9 / the air unit.')
    if RadioLine then RadioLine(Callsign() .. ': lost visual on the suspect, searching the area.') end
end

function FleeInVehicle(e)
    local ped = e.ped
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return FleeOnFoot(e) end
    if not Control(ped) then return end
    Control(veh, 800)
    Hold(ped)
    e.veh = veh
    SetVehicleIndicatorLights(veh, 0, false)
    SetVehicleIndicatorLights(veh, 1, false)
    SetVehicleEngineOn(veh, true, true, false)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 1.0)
    ClearPedTasks(ped)
    TaskVehicleMissionPedTarget(ped, veh, Me(), 8, 55.0, 1074528293, 800.0, 10.0, true)
    e.status = 'pursuit'
    e.fleeSince = GetGameTimer()
    SuspectBlip(e)
    for _, other in pairs(AIPeds) do
        if other ~= e and other.veh == veh and IsPedInVehicle(other.ped, veh, false) then other.status = 'pursuit' end
    end
    CreateThread(function() TriggerCallback('aiPursuit') end)
    if RadioLine then RadioLine(('%s: in pursuit, %s on %s! Vehicle failing to stop.'):format(Callsign(), Heading(veh), Street(GetEntityCoords(veh)))) end
    Notify('~r~The vehicle is fleeing!~s~ Pursue it - request backup or an air unit from the patrol computer (' .. AI.Keys.computer .. ').')
end

function Fight(e)
    local ped = e.ped
    if not Control(ped) then return end
    Hold(ped)
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 256)
        Wait(1200)
    end
    local w = (e.persona and (e.persona.weapon or e.persona.melee)) or 'WEAPON_UNARMED'
    GiveWeaponToPed(ped, GetHashKey(w), 120, false, true)
    SetCurrentPedWeapon(ped, GetHashKey(w), true)
    SetPedRelationshipGroupHash(ped, SuspectGroup())
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAbility(ped, 1)
    SetPedAccuracy(ped, 25)
    ClearPedTasks(ped)
    TaskCombatPed(ped, Me(), 0, 16)
    SetPedKeepTask(ped, true)
    e.status = 'fighting'
    SuspectBlip(e)
end

function Surrender(e, kneel)
    local ped = e.ped
    if not Control(ped) then return end
    Hold(ped)
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 256)
        local t = GetGameTimer() + 3000
        while IsPedInAnyVehicle(ped, false) and GetGameTimer() < t do Wait(100) end
    end
    RemoveAllPedWeapons(ped, true)
    SetPedRelationshipGroupHash(ped, GetHashKey('CIVMALE'))
    ClearPedTasks(ped)
    if kneel ~= false and LoadDict('random@arrests@busted') then
        TaskPlayAnim(ped, 'random@arrests@busted', 'idle_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
    else
        TaskHandsUp(ped, -1, Me(), -1, true)
    end
    e.status = 'surrendered'
    e.kneel = kneel ~= false
    if e.blip then SetBlipFlashes(e.blip, false) SetBlipColour(e.blip, 5) end
    CreateThread(function() TriggerCallback('aiState', e.pid, 'surrendered', true) end)
end

-- Let them go about their day
function Release(e, keepWalking)
    local ped = e.ped
    if DoesEntityExist(ped) and Control(ped, 800) then
        if e.cuffProp then DeleteProp(e.cuffProp) e.cuffProp = nil end
        DetachEntity(ped, true, false)
        SetPedCanRagdoll(ped, true)
        SetEnableHandcuffs(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        ClearPedTasks(ped)
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            Control(veh, 600)
            SetVehicleIndicatorLights(veh, 0, false)
            SetVehicleIndicatorLights(veh, 1, false)
            TaskVehicleDriveWander(ped, veh, 17.0, 786603)
            SetTimeout(20000, function() if DoesEntityExist(veh) then SetEntityAsNoLongerNeeded(veh) end end)
        elseif veh == 0 and keepWalking ~= false then
            TaskWanderStandard(ped, 10.0, 10)
        end
        SetTimeout(15000, function() if DoesEntityExist(ped) and not AIPeds[ped] then SetEntityAsNoLongerNeeded(ped) end end)
    end
    if e.pid then CreateThread(function() TriggerCallback('aiRelease', e.pid) end) end
    Untrack(e)
end

-- Gone for good (booked, transported, towed...). Fades out.
function Vanish(ent)
    if not ent or not DoesEntityExist(ent) then return end
    CreateThread(function()
        if not Control(ent, 1500) then SetEntityAsNoLongerNeeded(ent) return end
        if IsEntityAPed(ent) then DetachEntity(ent, true, false) end
        for a = 255, 0, -25 do SetEntityAlpha(ent, a, false) Wait(40) end
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end)
end

---------------------------------------------------------------------------
-- Spawning and finding places
---------------------------------------------------------------------------
function SpawnPed(model, pos, heading, veh, seat)
    local hash = LoadModel(model) or LoadModel('a_m_m_hillbilly_01')
    if not hash then return nil end
    local ped
    if veh then
        ped = CreatePedInsideVehicle(veh, 4, hash, seat or -1, true, true)
    else
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)
        ped = CreatePed(4, hash, pos.x, pos.y, pos.z, heading or 0.0, true, true)
    end
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRandomComponentVariation(ped, 0)
    SetPedRandomProps(ped)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedDiesWhenInjured(ped, false)
    return ped
end

function SpawnVeh(model, pos, heading)
    local hash = LoadModel(model)
    if not hash then hash = LoadModel('emperor') end
    if not hash then return nil end
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    local veh = CreateVehicle(hash, pos.x, pos.y, pos.z + 0.3, heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(veh, false)
    SetVehicleNeedsToBeHotwired(veh, false)
    return veh
end

-- A road node between minD and maxD from a point. Returns pos, heading
function FindRoad(minD, maxD, from)
    from = from or MyPos()
    for _ = 1, 40 do
        local ang = math.random() * math.pi * 2
        local d = minD + math.random() * (maxD - minD)
        local x, y = from.x + math.cos(ang) * d, from.y + math.sin(ang) * d
        local ok, pos, heading = GetNthClosestVehicleNodeWithHeading(x, y, from.z, 1, 1, 3.0, 0)
        if ok and pos then
            local dd = #(vector3(pos.x, pos.y, 0.0) - vector3(from.x, from.y, 0.0))
            if dd >= minD * 0.6 and dd <= maxD * 1.4 then return vector3(pos.x, pos.y, pos.z), heading end
        end
    end
    return nil
end

-- A spot for someone on foot near a point (pavement if possible)
function FindFoot(near)
    for _ = 1, 8 do
        local x, y = near.x + math.random(-12, 12), near.y + math.random(-12, 12)
        local ok, pos = GetSafeCoordForPed(x, y, near.z, true, 16)
        if ok and pos and #(pos - near) < 40.0 then return pos end
        ok, pos = GetSafeCoordForPed(x, y, near.z, false, 0)
        if ok and pos and #(pos - near) < 40.0 then return pos end
    end
    return near + vector3(3.0, 3.0, 0.0)
end

function NearStationClient()
    local pos = MyPos()
    for _, s in ipairs(Points.stations or {}) do
        if #(pos - V3(s.pos)) <= Config.StationRadius then return s end
    end
    return nil
end

---------------------------------------------------------------------------
-- The "busy" flag (no callouts are offered while you're dealing with someone)
---------------------------------------------------------------------------
local lastBusy = nil
function SyncBusy()
    local busy = false
    local pos = MyPos()
    for _, e in pairs(AIPeds) do
        if DoesEntityExist(e.ped) and e.status ~= 'free' and e.status ~= 'dead' and #(GetEntityCoords(e.ped) - pos) < 250.0 then busy = true break end
    end
    if busy ~= lastBusy then
        lastBusy = busy
        TriggerServerEvent(EV .. 'aiBusy', busy)
    end
end

---------------------------------------------------------------------------
-- Keeps everyone doing what they should (fleeing, fighting, cuffed, giving up...)
---------------------------------------------------------------------------
local function Tazed(ped)
    return IsPedBeingStunned(ped, 0) or HasPedBeenDamagedByWeapon(ped, GetHashKey('WEAPON_STUNGUN'), 0)
end

local function PlayerAimingAt(ped)
    local pid = PlayerId()
    return IsPlayerFreeAimingAtEntity(pid, ped) or IsPlayerTargettingEntity(pid, ped)
end

local function Stalled(e, veh)
    if GetEntitySpeed(veh) < 1.5 then
        e.slowSince = e.slowSince or GetGameTimer()
    else
        e.slowSince = nil
    end
    local burst = 0
    for _, w in ipairs({ 0, 1, 4, 5 }) do if IsVehicleTyreBurst(veh, w, false) then burst = burst + 1 end end
    return (e.slowSince and GetGameTimer() - e.slowSince > 4500) or GetVehicleEngineHealth(veh) < 120.0
        or IsEntityUpsidedown(veh) or burst >= 2 or IsEntityInWater(veh)
end

local function Lost(e, far)
    if AirWatching and AirWatching(e) then e.farSince = nil return false end
    if Dist(e.ped, Me()) > far then
        e.farSince = e.farSince or GetGameTimer()
        if GetGameTimer() - e.farSince > 25000 then
            Notify('~o~You lost the suspect.')
            RemoveBlipSafe(e.blip)
            SetEntityAsNoLongerNeeded(e.ped)
            if e.veh and DoesEntityExist(e.veh) then SetEntityAsNoLongerNeeded(e.veh) end
            e.status = 'lost'
            Untrack(e)
            return true
        end
    else
        e.farSince = nil
    end
    return false
end

local function React(e, moment)
    local res = TriggerCallback('aiReact', e.pid, moment)
    if res and res.ok then
        if res.persona then e.persona = res.persona end
        e.reach = res.reach
        if res.say then Say(e, res.say) end
        return res.act
    end
    return 'comply'
end
AIReact = React
PlayerAimingAtPed = PlayerAimingAt

function ApplyReaction(e, act)
    if act == 'flee' then
        if IsPedInAnyVehicle(e.ped, false) and GetPedInVehicleSeat(GetVehiclePedIsIn(e.ped, false), -1) == e.ped then FleeInVehicle(e) else FleeOnFoot(e) end
        return true
    elseif act == 'fight' then
        Fight(e)
        return true
    elseif act == 'surrender' then
        Surrender(e)
        return true
    elseif act == 'reach' then
        if ReachFor then CreateThread(function() ReachFor(e) end) end
        return true
    end
    return false
end

CreateThread(function()
    while true do
        local wait = 1000
        local me = Me()
        local list = {}
        for ped, e in pairs(AIPeds) do list[#list + 1] = e end
        for _, e in ipairs(list) do
            local ped = e.ped
            if AIPeds[ped] ~= e then
                -- dealt with while we were busy
            elseif not DoesEntityExist(ped) then
                Untrack(e)
            elseif IsPedDeadOrDying(ped, true) then
                if e.status ~= 'dead' then
                    e.status = 'dead'
                    e.deadAt = GetGameTimer()
                    RemoveBlipSafe(e.blip)
                    e.blip = nil
                elseif GetGameTimer() - e.deadAt > 600000 or Dist(ped, me) > 150.0 then
                    -- leave the body to the game (or the coroner)
                    Untrack(e)
                    SetEntityAsNoLongerNeeded(ped)
                end
            elseif e.status == 'pursuit' then
                wait = 250
                local veh = GetVehiclePedIsIn(ped, false)
                local isDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
                if veh ~= 0 and not isDriver then
                    -- a passenger: bail out when the car stops or the driver has gone
                    local drv = GetPedInVehicleSeat(veh, -1)
                    local stopped = GetEntitySpeed(veh) < 1.0 and Dist(ped, me) < 50.0
                    if (drv == 0 or IsPedDeadOrDying(drv, true) or stopped) and Control(ped, 500) then
                        TaskLeaveVehicle(ped, veh, 256)
                        Wait(1200)
                        local act = React(e, 'cornered')
                        if act == 'surrender' then Surrender(e) elseif act == 'fight' then Fight(e) else FleeOnFoot(e) end
                    else
                        Lost(e, 900.0)
                    end
                elseif veh == 0 then
                    -- bailed out on foot
                    local act = React(e, 'cornered')
                    if act == 'surrender' then Surrender(e) elseif act == 'fight' then Fight(e) else FleeOnFoot(e) end
                elseif GetPedInVehicleSeat(veh, -1) == ped and Stalled(e, veh) and Dist(ped, me) < 60.0 then
                    if Control(ped) then
                        TaskLeaveVehicle(ped, veh, 256)
                        Wait(1500)
                        local act = React(e, 'cornered')
                        if act == 'surrender' then Surrender(e) elseif act == 'fight' then Fight(e) else FleeOnFoot(e) end
                    end
                elseif not Lost(e, 900.0) then
                    if GetGameTimer() - (e.fleeSince or 0) > 15000 and GetPedInVehicleSeat(veh, -1) == ped and Control(ped, 300) then
                        e.fleeSince = GetGameTimer()
                        TaskVehicleMissionPedTarget(ped, veh, me, 8, 55.0, 1074528293, 800.0, 10.0, true)
                    end
                end
            elseif e.status == 'fleeing' then
                wait = 250
                if Tazed(ped) or IsPedRagdoll(ped) then
                    ClearPedLastWeaponDamage(ped)
                    e.downAt = e.downAt or GetGameTimer()
                    if GetGameTimer() - e.downAt > 2500 then e.downAt = nil Surrender(e) end
                elseif not Lost(e, 450.0) then
                    local d = Dist(ped, me)
                    local seen = d < 25.0 or HasEntityClearLosToEntity(me, ped, 17)
                    if seen then e.unseen = nil else e.unseen = e.unseen or GetGameTimer() end
                    if not e.hid and e.unseen and GetGameTimer() - e.unseen > 2500 and d > 35.0 and not (AirWatching and AirWatching(e)) then
                        e.hid = true
                        if math.random() < 0.5 then Hide(e) end
                    elseif PlayerAimingAt(ped) and d < 30.0 and GetGameTimer() - (e.aimCheck or 0) > 2500 then
                        e.aimCheck = GetGameTimer()
                        if React(e, 'aimed') == 'surrender' then Surrender(e, false) end
                    elseif GetGameTimer() - (e.fleeSince or 0) > 12000 and Control(ped, 300) then
                        e.fleeSince = GetGameTimer()
                        TaskSmartFleePed(ped, me, 800.0, -1, false, false)
                    end
                end
            elseif e.status == 'fighting' then
                wait = 300
                if Tazed(ped) then
                    ClearPedLastWeaponDamage(ped)
                    e.downAt = e.downAt or GetGameTimer()
                    if GetGameTimer() - e.downAt > 2500 then e.downAt = nil Surrender(e) end
                elseif GetEntityHealth(ped) < 130 then
                    Surrender(e)
                elseif PlayerAimingAt(ped) and GetGameTimer() - (e.aimCheck or 0) > 3000 then
                    e.aimCheck = GetGameTimer()
                    if React(e, 'aimed') == 'surrender' then Surrender(e, false) end
                elseif GetGameTimer() - (e.fightTask or 0) > 8000 and Control(ped, 300) then
                    e.fightTask = GetGameTimer()
                    if not IsPedInCombat(ped, me) then TaskCombatPed(ped, me, 0, 16) end
                end
            elseif e.status == 'hiding' then
                local d = Dist(ped, me)
                if d < 9.0 and HasEntityClearLosToEntity(me, ped, 17) then
                    -- found them
                    RemoveBlipSafe(e.blip)
                    e.blip = nil
                    SetPedStealthMovement(ped, false, 'DEFAULT_ACTION')
                    Notify('~y~Found them!')
                    local act = React(e, 'cornered')
                    if act == 'surrender' then Surrender(e) elseif act == 'fight' then Fight(e) else e.status = 'fleeing' FleeOnFoot(e) end
                elseif d > 350.0 then
                    e.farSince = e.farSince or GetGameTimer()
                    if GetGameTimer() - e.farSince > 60000 then
                        Notify('~o~The suspect got away.')
                        RemoveBlipSafe(e.blip)
                        SetEntityAsNoLongerNeeded(ped)
                        Untrack(e)
                    end
                else
                    e.farSince = nil
                end
            elseif e.status == 'surrendered' then
                if e.kneel and not IsEntityPlayingAnim(ped, 'random@arrests@busted', 'idle_a', 3) and Control(ped, 300) then
                    TaskPlayAnim(ped, 'random@arrests@busted', 'idle_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
                end
            elseif e.status == 'escorted' then
                wait = 100
                local holder = (e.escortBy and DoesEntityExist(e.escortBy)) and e.escortBy or me
                if IsPedInAnyVehicle(holder, true) or IsPedDeadOrDying(holder, true) or not IsEntityAttachedToEntity(ped, holder) then
                    if Control(ped, 300) then DetachEntity(ped, true, false) SetPedCanRagdoll(ped, true) end
                    e.status, e.escAnim, e.escortBy = 'cuffed', nil, nil
                elseif Control(ped, 200) then
                    -- walk (or jog) in step with whoever's holding them, cuffed hands behind the back
                    local speed = GetEntitySpeed(holder)
                    local want = speed > 3.2 and 'run' or speed > 0.4 and 'walk' or 'idle'
                    if e.escAnim ~= want or not IsEntityPlayingAnim(ped, 'mp_arresting', want, 3) then
                        e.escAnim = want
                        LoadDict('mp_arresting')
                        TaskPlayAnim(ped, 'mp_arresting', want, 8.0, -8.0, -1, want == 'idle' and 49 or 1, 0.0, false, false, false)
                    end
                end
            elseif e.status == 'cuffed' then
                if not IsPedInAnyVehicle(ped, false) and not IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3) and not IsPedRagdoll(ped)
                    and Control(ped, 300) then
                    LoadDict('mp_arresting')
                    TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)
                end
            elseif e.status == 'held' then
                -- the stop ends if the officer drives off
                if Dist(ped, me) > AI.AbandonDistance then
                    Notify('You left the stop - they\'ve gone on their way.')
                    Release(e)
                end
            end
        end
        SyncBusy()
        Wait(wait)
    end
end)

-- Clean up everything if the resource stops
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, e in pairs(AIPeds) do
        RemoveBlipSafe(e.blip)
        if e.cuffProp then DeleteProp(e.cuffProp) end
        if DoesEntityExist(e.ped) then
            DetachEntity(e.ped, true, false)
            SetEntityAsNoLongerNeeded(e.ped)
        end
    end
end)
