-- Statewide PD: AI units you can call - backup, SWAT, K9, transport, roadblocks, spikes, tow, EMS, coroner, air.
-- Units spawn out of sight on a road, drive in properly (lights and sirens, code 2 or 3), park up behind you,
-- recover themselves if they get stuck, follow you if you leave, and join pursuits (see ai_pursuit.lua).
local Units = {}
local Dead = {}           -- downed units, cleaned up after a while
SWUnits = Units           -- shared with ai_pursuit.lua / ai_partner.lua
local lastReq = {}
local air = nil

local COLOURS = { backup = 3, swat = 40, k9 = 3, transport = 3, roadblock = 3, spikes = 3, tow = 47, ems = 2, coroner = 40, air = 3, crisis = 2, cps = 5 }
local ARMED = { backup = true, swat = true, k9 = true, transport = true, roadblock = true, spikes = true, partner = true }
local CODE3 = 1074528293     -- drive fast, avoid traffic, go round obstacles
local CODE2 = 786603         -- normal careful driving

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Tag everything we spawn so other scripts (RemoveAICopsEMS) leave it alone
function TagUnitEntity(ent)
    if not ent or not DoesEntityExist(ent) then return end
    SetEntityAsMissionEntity(ent, true, true)
    pcall(function() Entity(ent).state:set('swpd', true, true) end)
end

function Hidden(pos)
    local ok, vis = pcall(IsSphereVisible, pos.x, pos.y, pos.z, 4.0)
    if not ok then return #(pos - MyPos()) > 120.0 end
    return not vis
end

local function ModelOk(m)
    if not m then return false end
    local h = type(m) == 'number' and m or GetHashKey(m)
    return IsModelInCdimage(h) and IsModelAVehicle(h)
end

local FALLBACK = { 'sheriff', 'sheriff2', 'police', 'police3' }
local warnedModels = false
local function PickVehicle(kind)
    local cfg = AI.Units[kind]
    local ok = {}
    for _, m in ipairs(cfg.vehicles or {}) do if ModelOk(m) then ok[#ok + 1] = m end end
    if #ok == 0 and AI.PoliceUnits[kind] then
        if not warnedModels then
            warnedModels = true
            print('[Statewide PD] None of the cars for "' .. kind .. '" are streamed - is 2023slrpackallblue started before statewide_police? Using GTA sheriff cars.')
        end
        for _, m in ipairs(FALLBACK) do if ModelOk(m) then ok[#ok + 1] = m end end
    end
    return #ok > 0 and PickOne(ok) or nil
end

-- Saved uniforms (staff set them from the patrol computer). Falls back to the default slot, then to cfg.peds.
local function OutfitFor(kind)
    local all = GlobalState.swpdUniforms
    if type(all) ~= 'table' then return nil end
    local list = all[kind]
    if type(list) ~= 'table' or #list == 0 then list = all.default end
    if type(list) ~= 'table' or #list == 0 then return nil end
    return list[math.random(1, #list)]
end

local function OutfitModel(o)
    local m = tostring(o.model or '')
    if m:sub(1, 1) == 'h' and tonumber(m:sub(2)) then return tonumber(m:sub(2)) end
    return m
end

local FREEMODE = { [GetHashKey('mp_m_freemode_01')] = true, [GetHashKey('mp_f_freemode_01')] = true }

function ApplyOutfit(ped, o)
    if not o or not DoesEntityExist(ped) then return end
    if FREEMODE[GetEntityModel(ped)] then
        -- a random face so a squad doesn't look like clones
        local a, b = math.random(0, 45), math.random(0, 45)
        SetPedHeadBlendData(ped, a, b, 0, a, b, 0, math.random() * 1.0, math.random() * 1.0, 0.0, false)
    end
    local comps, props = o.comps or {}, o.props or {}
    for i = 0, 11 do
        local c = comps[tostring(i)] or comps[i]
        if c then SetPedComponentVariation(ped, i, c[1], c[2], 0) end
    end
    ClearAllPedProps(ped)
    for i = 0, 7 do
        local p = props[tostring(i)] or props[i]
        if p and p[1] >= 0 then SetPedPropIndex(ped, i, p[1], p[2], true) end
    end
end

-- One officer for a unit, dressed and armed
function SpawnUnitPed(kind, veh, seat, pos, heading)
    local cfg = AI.Units[kind] or AI.Units.backup
    local outfit = AI.PoliceUnits[kind] and OutfitFor(kind) or nil
    local ped
    if outfit then
        local m = OutfitModel(outfit)
        local h = type(m) == 'number' and m or GetHashKey(m)
        if IsModelInCdimage(h) then
            ped = SpawnPed(m, pos, heading, veh, seat)
            if ped then ApplyOutfit(ped, outfit) end
        end
    end
    if not ped then ped = SpawnPed(PickOne(cfg.peds), pos, heading, veh, seat) end
    if not ped then return nil end
    TagUnitEntity(ped)
    SetPedKeepTask(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedConfigFlag(ped, 32, false)       -- don't fly through the windscreen
    if ARMED[kind] then
        SetPedRelationshipGroupHash(ped, CopsGroup())
        for i, w in ipairs(cfg.weapons or { 'WEAPON_COMBATPISTOL' }) do
            GiveWeaponToPed(ped, GetHashKey(w), 400, false, i == 1)
        end
        SetPedArmour(ped, cfg.armour or 100)
        SetPedAccuracy(ped, cfg.accuracy or 55)
        SetPedCombatAbility(ped, kind == 'swat' and 2 or 1)
        SetPedCombatRange(ped, 1)
        SetPedCombatMovement(ped, kind == 'swat' and 2 or 1)
        SetPedCombatAttributes(ped, 46, true)   -- always fight
        SetPedCombatAttributes(ped, 0, true)    -- use cover
        SetPedCombatAttributes(ped, 5, true)
        SetPedFleeAttributes(ped, 0, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedDropsWeaponsWhenDead(ped, false)
        SetPedSuffersCriticalHits(ped, false)
        SetEntityMaxHealth(ped, 300)
        SetEntityHealth(ped, 300)
    else
        SetBlockingOfNonTemporaryEvents(ped, true)
    end
    return ped
end

local function Alive(p) return p and DoesEntityExist(p) and not IsPedDeadOrDying(p, true) end

local function Driver(u)
    for _, p in ipairs(u.crew) do
        if Alive(p) and p ~= u.dog then return p end
    end
    return nil
end
UnitDriver = Driver

local function SetLights(u, on, quiet)
    if not DoesEntityExist(u.veh) or not Control(u.veh, 300) then return end
    SetVehicleSiren(u.veh, on)
    SetVehicleHasMutedSirens(u.veh, quiet == true)
end

function UnitDrive(u, dest, fast)
    local d = Driver(u)
    if not d or not DoesEntityExist(u.veh) or not Control(d, 500) then return end
    if not IsPedInVehicle(d, u.veh, false) then return end
    u.dest = dest
    SetDriverAbility(d, 1.0)
    SetDriverAggressiveness(d, fast and 0.75 or 0.3)
    TaskVehicleDriveToCoordLongrange(d, u.veh, dest.x, dest.y, dest.z, fast and 34.0 or 18.0, fast and CODE3 or CODE2, 15.0)
    SetPedKeepTask(d, true)
end
local DriveTo = UnitDrive

-- Everyone back in the car
function UnitBoard(u)
    for i, p in ipairs(u.crew) do
        if Alive(p) and not IsPedInVehicle(p, u.veh, false) and DoesEntityExist(u.veh) and Control(p, 300) then
            ClearPedTasks(p)
            if p == u.dog then
                TaskWarpPedIntoVehicle(p, u.veh, 1)
            else
                TaskEnterVehicle(p, u.veh, 15000, i == 1 and -1 or (i - 2), 2.0, 1, 0)
            end
        end
    end
end

function UnitAllIn(u)
    for _, p in ipairs(u.crew) do if Alive(p) and not IsPedInVehicle(p, u.veh, false) then return false end end
    return true
end

local function Leave(u)
    if u.state == 'leaving' then return end
    u.state = 'leaving'
    u.leftAt = GetGameTimer()
    u.pursuit = nil
    RemoveBlipSafe(u.blip)
    CreateThread(function()
        UnitBoard(u)
        local t = GetGameTimer() + 15000
        while GetGameTimer() < t and not UnitAllIn(u) do Wait(500) end
        local d = Driver(u)
        if d and DoesEntityExist(u.veh) and Control(d, 500) then
            SetLights(u, false)
            TaskVehicleDriveWander(d, u.veh, 18.0, CODE2)
        end
    end)
end
UnitLeave = Leave

local function Remove(u)
    for _, p in ipairs(u.crew) do Vanish(p) end
    for _, p in ipairs(u.left or {}) do Vanish(p) end
    for _, p in ipairs(u.cargo or {}) do Vanish(p) end
    for _, o in ipairs(u.props or {}) do if DoesEntityExist(o) then DeleteEntity(o) end end
    Vanish(u.veh)
    RemoveBlipSafe(u.blip)
end

function DismissUnits(kind)
    local n = 0
    for _, u in ipairs(Units) do
        if (not kind or u.kind == kind) and u.state ~= 'leaving' then Leave(u) n = n + 1 end
    end
    if air and (not kind or kind == 'air') then air.ends = 0 n = n + 1 end
    if kind == 'partner' and DismissPartner and DismissPartner() then n = n + 1 end   -- "dismiss all" keeps your partner
    return n
end

local STATE_TEXT = { enroute = 'en route', parking = 'arriving', arriving = 'arriving', onscene = 'on scene', following = 'following you',
    pursuit = 'in pursuit', waiting = 'waiting', working = 'working', blocking = 'roadblock set', spiking = 'spikes down' }
-- Units of a kind (on scene, not leaving) within r metres of pos
function UnitsNear(kind, pos, r)
    local n = 0
    for _, u in ipairs(Units) do
        if u.kind == kind and u.state ~= 'leaving' and DoesEntityExist(u.veh) then
            local close = #(GetEntityCoords(u.veh) - pos) <= r
            for _, p in ipairs(u.crew or {}) do if DoesEntityExist(p) and #(GetEntityCoords(p) - pos) <= r then close = true end end
            if close then n = n + 1 end
        end
    end
    return n
end

function UnitList()
    local out = {}
    for _, u in ipairs(Units) do
        if u.state ~= 'leaving' then
            local d = DoesEntityExist(u.veh) and math.floor(#(GetEntityCoords(u.veh) - MyPos())) or 0
            out[#out + 1] = { kind = u.kind, label = AI.Units[u.kind].label, state = STATE_TEXT[u.state] or u.state, dist = d }
        end
    end
    if air then out[#out + 1] = { kind = 'air', label = AI.Units.air.label, state = 'overhead' } end
    if PartnerInfo then local p = PartnerInfo() if p then out[#out + 1] = p end end
    return out
end

---------------------------------------------------------------------------
-- Air unit (helicopter following the suspect with a spotlight)
---------------------------------------------------------------------------
local function AirTarget()
    local best, bd = nil, 2000.0
    local pos = MyPos()
    for ped, e in pairs(AIPeds) do
        if e.status == 'pursuit' or e.status == 'fleeing' or e.status == 'fighting' or e.status == 'hiding' then
            local d = #(GetEntityCoords(ped) - pos)
            if d < bd then best, bd = e, d end
        end
    end
    return best
end

function AirWatching(e) return air ~= nil and air.target == e end

local function SpawnAir()
    local cfg = AI.Units.air
    local pos = MyPos()
    local ang = math.random() * math.pi * 2
    local spawn = vector3(pos.x + math.cos(ang) * 450.0, pos.y + math.sin(ang) * 450.0, pos.z + 120.0)
    local model = ModelOk(cfg.vehicles[1]) and PickOne(cfg.vehicles) or 'polmav'
    local hash = LoadModel(model)
    local heli = hash and CreateVehicle(hash, spawn.x, spawn.y, spawn.z, 0.0, true, false) or nil
    if hash then SetModelAsNoLongerNeeded(hash) end
    if not heli or heli == 0 then return Notify('No air unit available (helicopter model missing).') end
    TagUnitEntity(heli)
    SetHeliBladesFullSpeed(heli)
    SetVehicleEngineOn(heli, true, true, false)
    local pilot = SpawnUnitPed('air', heli, -1)
    if not pilot then Vanish(heli) return end
    SetBlockingOfNonTemporaryEvents(pilot, true)
    SetPedRelationshipGroupHash(pilot, CopsGroup())
    local blip = AddBlipForEntity(heli)
    SetBlipSprite(blip, 43)
    SetBlipColour(blip, 3)
    NamedBlip(blip, cfg.label)
    air = { heli = heli, pilot = pilot, blip = blip, ends = GetGameTimer() + (cfg.seconds or 240) * 1000, target = nil, retask = 0 }
    Notify('~b~Air unit~s~ is up and on its way.')
    RadioLine('Air-1: ' .. Callsign() .. ', Air-1 en route to your location.')
    CreateThread(function()
        while air and GetGameTimer() < air.ends and DoesEntityExist(air.heli) and not IsEntityDead(air.heli) do
            Wait(0)
            if GetGameTimer() > air.retask then
                air.retask = GetGameTimer() + 4000
                local e = AirTarget()
                if e ~= air.target then
                    air.target = e
                    if e then
                        Notify('~b~Air unit:~s~ eyes on the suspect.')
                        RadioLine(('Air-1: we have the suspect, %s on %s.'):format(Heading(e.ped), Street(GetEntityCoords(e.ped))))
                        if e.status == 'hiding' then
                            RemoveBlipSafe(e.blip)
                            e.blip = AddBlipForEntity(e.ped)
                            SetBlipColour(e.blip, 1)
                            NamedBlip(e.blip, 'Suspect (Air-1)')
                        end
                    end
                end
                local follow = e and ((e.status == 'pursuit' and e.veh and DoesEntityExist(e.veh)) and e.veh or e.ped) or PlayerPedId()
                if Control(air.pilot, 300) then TaskHeliChase(air.pilot, follow, 0.0, 0.0, 55.0) end
                air.follow = follow
            end
            if air.follow and DoesEntityExist(air.follow) then
                local from = GetOffsetFromEntityInWorldCoords(air.heli, 0.0, 2.0, -1.6)
                local to = GetEntityCoords(air.follow)
                local dir = to - from
                local len = #dir
                if len > 1.0 then
                    dir = dir / len
                    DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, 255, 255, 235, len + 40.0, 40.0, 0.0, 9.0, 25.0)
                end
            end
        end
        if air then
            Notify('~b~Air unit~s~ is leaving the area.')
            RadioLine('Air-1: low on fuel, returning to base.', true)
            local a = air
            air = nil
            RemoveBlipSafe(a.blip)
            if DoesEntityExist(a.pilot) and DoesEntityExist(a.heli) and Control(a.pilot, 500) then
                local p = GetEntityCoords(a.heli)
                TaskHeliMission(a.pilot, a.heli, 0, 0, p.x + 2000.0, p.y + 2000.0, p.z + 150.0, 4, 40.0, 10.0, -1.0, -1, -1, -1.0, 0)
            end
            SetTimeout(30000, function() Vanish(a.pilot) Vanish(a.heli) end)
        end
    end)
end

---------------------------------------------------------------------------
-- Ground units
---------------------------------------------------------------------------
-- Somewhere on a road, out of your sight, facing towards you
local function SpawnPoint(target, minD, maxD)
    local best, bh
    for _ = 1, 8 do
        local pos, h = FindRoad(minD, maxD, target)
        if pos and #(pos - MyPos()) > minD * 0.6 then
            best, bh = best or pos, bh or h
            if Hidden(pos) then best, bh = pos, h break end
        end
    end
    if not best then best, bh = FindRoad(60.0, maxD * 1.8, target) end
    if not best then return nil end
    -- turn to face the target if the road heading points away
    local to = target - best
    local fx, fy = -math.sin(math.rad(bh or 0.0)), math.cos(math.rad(bh or 0.0))
    if fx * to.x + fy * to.y < 0 then bh = ((bh or 0.0) + 180.0) % 360.0 end
    return best, bh
end
UnitSpawnPoint = SpawnPoint

-- Builds a unit's car and crew. Returns the unit (not yet driving).
function BuildUnit(kind, pos, heading, data)
    local cfg = AI.Units[kind]
    local model = PickVehicle(kind)
    if not model then Notify('Couldn\'t send a ' .. cfg.label:lower() .. ' (vehicle model missing).') return nil end
    local veh = SpawnVeh(model, pos, heading)
    if not veh then Notify('Couldn\'t send a ' .. cfg.label:lower() .. '.') return nil end
    TagUnitEntity(veh)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleModKit(veh, 0)
    if AI.SheriffCarLivery and AI.PoliceUnits[kind] then SetVehicleLivery(veh, AI.SheriffCarLivery) end
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleCanBeVisiblyDamaged(veh, true)
    SetEntityProofs(veh, false, true, false, false, false, false, false, false)   -- fireproof, still crashable
    local crew = {}
    local seats = GetVehicleMaxNumberOfPassengers(veh) + 1
    for i = 1, math.min(cfg.crew or 1, seats) do
        local p = SpawnUnitPed(kind, veh, i == 1 and -1 or (i - 2))
        if p then crew[#crew + 1] = p end
    end
    if #crew == 0 then Vanish(veh) return nil end
    local dog
    if cfg.dog then
        dog = SpawnPed(cfg.dog, nil, nil, veh, IsVehicleSeatFree(veh, 1) and 1 or 0)
        if dog then
            TagUnitEntity(dog)
            SetPedRelationshipGroupHash(dog, CopsGroup())
            SetBlockingOfNonTemporaryEvents(dog, true)
            SetPedKeepTask(dog, true)
            crew[#crew + 1] = dog
        end
    end
    local blip = AddBlipForEntity(veh)
    SetBlipColour(blip, COLOURS[kind] or 3)
    SetBlipScale(blip, 0.8)
    NamedBlip(blip, cfg.label)
    local u = { kind = kind, veh = veh, crew = crew, state = 'enroute', siren = cfg.siren, blip = blip, started = GetGameTimer(),
        data = data or {}, target = pos, retask = 0, dog = dog, lastMove = GetGameTimer(), reverses = 0 }
    table.insert(Units, u)
    return u
end

local function SpawnUnit(kind, data)
    local cfg = AI.Units[kind]
    if kind == 'air' then return SpawnAir() end
    if kind == 'partner' then return SpawnPartner and SpawnPartner() end
    if (kind == 'roadblock' or kind == 'spikes') and DeployAhead then
        if DeployAhead(kind) then return end
        -- no pursuit on: they just come to you like backup
    end
    local target = (data.veh and DoesEntityExist(data.veh)) and GetEntityCoords(data.veh) or MyPos()
    local pos, heading = SpawnPoint(target, 160.0, 280.0)
    if not pos then return Notify('No ' .. cfg.label:lower() .. ' can reach you here.') end
    local u = BuildUnit(kind, pos, heading, data)
    if not u then return end
    u.target = target
    u.code3 = cfg.siren and (kind ~= 'backup' or data.code3 ~= false)
    if cfg.siren then SetLights(u, true, not u.code3) end
    DriveTo(u, target, u.code3)
    Notify(('~b~%s~s~ is en route.'):format(cfg.label))
    local eta = math.max(1, math.floor(#(GetEntityCoords(u.veh) - target) / 300 + 0.5))
    RadioLine(('Dispatch: %s, %s en route to you, ETA %d minute%s.'):format(Callsign(), cfg.label:lower(), eta, eta == 1 and '' or 's'))
    return u
end

function RequestUnit(kind, data)
    local cfg = AI.Units[kind]
    if not cfg then return end
    if not IsPolice then return Notify('You need to be on duty.') end
    if lastReq[kind] and GetGameTimer() - lastReq[kind] < AI.UnitCooldown * 1000 then return Notify('Wait a moment before requesting another.') end
    if kind == 'air' and air then return Notify('The air unit is already up.') end
    if kind == 'k9' and PartnerIsDog and PartnerIsDog() then
        if data and data.entry and PartnerOrder then return PartnerOrder(data.entry, { cmd = 'sniff' }) end
        return Notify('Your K9 is with you - use the K9 commands in the patrol computer.')
    end
    local count = 0
    for _, u in ipairs(Units) do if u.kind == kind and u.state ~= 'leaving' then count = count + 1 end end
    if count >= (cfg.max or 1) then return Notify(('You already have the maximum %s units.'):format(cfg.label:lower())) end
    data = data or {}
    if kind == 'k9' and (not data.veh or not DoesEntityExist(data.veh)) then
        for _, e in pairs(AIPeds) do if e.veh and DoesEntityExist(e.veh) and e.role == 'driver' and Dist(e.veh, Me()) < 40.0 then data.veh, data.entry = e.veh, e end end
    end
    if kind == 'tow' and (not data.veh or not DoesEntityExist(data.veh)) then
        data.veh = VehicleAhead(8.0)
        if data.veh == GetVehiclePedIsIn(Me(), false) or (data.veh and GetVehicleClass(data.veh) == 18) then data.veh = nil end
        if not data.veh then return Notify('Stand next to the vehicle you want towed.') end
    end
    lastReq[kind] = GetGameTimer()
    CreateThread(function() TriggerCallback('aiUnit', kind, Street(MyPos())) end)
    CreateThread(function() SpawnUnit(kind, data) end)
end

-- Prisoner transport is parked up and waiting near this prisoner?
function TransportReady(e)
    for _, u in ipairs(Units) do
        if u.kind == 'transport' and u.state == 'waiting' and DoesEntityExist(u.veh) and Dist(e.ped, u.veh) < 30.0 then return u end
    end
    return nil
end

function HandToTransport(e)
    local u = TransportReady(e)
    if not u then return end
    CreateThread(function()
        local ped = e.ped
        Untrack(e)
        if not Control(ped) then return end
        DetachEntity(ped, true, false)
        SetPedCanRagdoll(ped, true)
        if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16) Wait(600) end
        local seat = IsVehicleSeatFree(u.veh, 1) and 1 or (IsVehicleSeatFree(u.veh, 2) and 2 or 0)
        TaskWarpPedIntoVehicle(ped, u.veh, seat)
        u.cargo = u.cargo or {}
        u.cargo[#u.cargo + 1] = ped
        Notify('Prisoner handed over to transport.')
        Wait(2500)
        local more = false
        for _, o in pairs(AIPeds) do
            if (o.status == 'cuffed' or o.status == 'escorted' or o.status == 'seated') and Dist(o.ped, u.veh) < 40.0 then more = true end
        end
        if not more then
            RadioLine('Transport: prisoner secured, en route to county jail.', true)
            Leave(u)
        end
    end)
end

-- The stop (if any) the officer is working right now
function CurrentStop()
    for _, e in pairs(AIPeds) do
        if e.role == 'driver' and e.veh and DoesEntityExist(e.veh) and (e.status == 'held' or e.felony) and Dist(e.veh, Me()) < 45.0 then return e end
    end
    return nil
end

-- Backup takes position on a stop: guns on the car for a felony stop, otherwise by the passenger side
function StopCover(u, p, k)
    local stop = CurrentStop()
    if not stop then return false end
    local myCar = GetVehiclePedIsIn(Me(), true)
    if stop.felony then
        local base = (myCar ~= 0 and DoesEntityExist(myCar)) and myCar or Me()
        local spot = GetOffsetFromEntityInWorldCoords(base, (k % 2 == 1) and 1.4 or -1.4, 1.2 - math.floor((k - 1) / 2) * 1.6, 0.0)
        if #(GetEntityCoords(p) - spot) > 1.5 then
            TaskGoToCoordAnyMeans(p, spot.x, spot.y, spot.z, 2.0, 0, false, 786603, 0.0)
        elseif GetGameTimer() - ((u.aimAt or {})[p] or 0) > 8000 then
            u.aimAt = u.aimAt or {}
            u.aimAt[p] = GetGameTimer()
            TaskAimGunAtEntity(p, stop.veh, 10000, false)
        end
    else
        local spot = GetOffsetFromEntityInWorldCoords(stop.veh, 2.2, -0.8 - k, 0.0)
        if #(GetEntityCoords(p) - spot) > 1.5 then
            TaskGoToCoordAnyMeans(p, spot.x, spot.y, spot.z, 1.2, 0, false, 786603, 0.0)
        elseif not IsPedUsingAnyScenario(p) then
            TaskStartScenarioInPlace(p, 'WORLD_HUMAN_COP_IDLES', 0, true)
        end
    end
    return true
end

-- Where to park: behind your car (staggered for each unit), or next to you on foot
local function ParkSpot(u)
    local myCar = GetVehiclePedIsIn(Me(), true)
    local n = 0
    for _, o in ipairs(Units) do if o ~= u and (o.state == 'onscene' or o.state == 'parking') then n = n + 1 end end
    if myCar ~= 0 and DoesEntityExist(myCar) and #(GetEntityCoords(myCar) - MyPos()) < 40.0 then
        return GetOffsetFromEntityInWorldCoords(myCar, 0.6, -8.5 - n * 7.0, 0.0), GetEntityHeading(myCar)
    end
    return nil
end

local function GetOut(u)
    for _, p in ipairs(u.crew) do
        if Alive(p) and IsPedInAnyVehicle(p, false) and Control(p, 500) then
            if p == u.dog then
                local s = GetOffsetFromEntityInWorldCoords(u.veh, -1.8, -1.5, 0.0)
                SetEntityCoords(p, s.x, s.y, s.z - 0.9, false, false, false, false)
            else
                TaskLeaveVehicle(p, u.veh, 256)
            end
        end
    end
end
UnitGetOut = GetOut

local function Arrive(u)
    if u.pursuit then return end
    local d = Driver(u)
    if d and Control(d, 500) and DoesEntityExist(u.veh) then TaskVehicleTempAction(d, u.veh, 27, 3000) end
    if u.siren and DoesEntityExist(u.veh) then SetLights(u, true, true) end    -- lights stay on, siren off
    Wait(1200)
    if u.kind == 'backup' or u.kind == 'swat' or u.kind == 'roadblock' or u.kind == 'spikes' then
        u.state = 'onscene'
        GetOut(u)
        Notify(('~b~%s~s~ is on scene.'):format(AI.Units[u.kind].label))
        RadioLine(('%s: on scene with %s.'):format(u.kind == 'swat' and 'SWAT' or 'Unit ' .. (u.callsign or 'backup'), Callsign()), true)
    elseif u.kind == 'k9' then
        u.state = 'onscene'
        CreateThread(function()
            GetOut(u)
            Wait(2500)
            local veh = u.data.veh
            local dog = u.dog
            if veh and DoesEntityExist(veh) and dog and DoesEntityExist(dog) then
                Notify('~b~K9:~s~ running the dog around the vehicle.')
                if K9Sniff then K9Sniff(dog, veh, u.data.entry) end
            end
            u.k9done = true
        end)
    elseif u.kind == 'crisis' or u.kind == 'cps' then
        u.state = 'working'
        CreateThread(function() if PeopleUnitArrive then PeopleUnitArrive(u) end end)
    elseif u.kind == 'transport' then
        u.state = 'waiting'
        u.waitUntil = GetGameTimer() + 300000
        Notify('~b~Prisoner transport~s~ is here. Book your prisoner with the arrest form (they\'ll take them away).')
    elseif u.kind == 'tow' then
        u.state = 'working'
        CreateThread(function()
            local veh = u.data.veh
            if not veh or not DoesEntityExist(veh) then Notify('The tow truck couldn\'t find the vehicle.') return Leave(u) end
            local t = GetGameTimer() + 60000
            while GetGameTimer() < t do
                local empty = true
                for seat = -1, 6 do if GetPedInVehicleSeat(veh, seat) ~= 0 then empty = false end end
                if empty then break end
                if not u.warned then u.warned = true Notify('The tow driver is waiting for the vehicle to be empty.') end
                Wait(500)
            end
            for seat = -1, 6 do
                if GetPedInVehicleSeat(veh, seat) ~= 0 then
                    Notify('The tow truck left - the vehicle still had someone in it.')
                    return Leave(u)
                end
            end
            if Control(d, 500) then
                TaskLeaveVehicle(d, u.veh, 256)
                Wait(1500)
                TaskGoToEntity(d, veh, -1, 2.5, 1.5, 1073741824, 0)
                Wait(5000)
                if LoadDict('mini@repair') then TaskPlayAnim(d, 'mini@repair', 'fixing_a_ped', 8.0, -8.0, 5000, 1, 0.0, false, false, false) end
                Wait(5000)
                TaskEnterVehicle(d, u.veh, 10000, -1, 1.5, 1, 0)
                Wait(4000)
            end
            if DoesEntityExist(veh) and Control(veh, 1500) then
                local plate = GetVehicleNumberPlateText(veh)
                for _, o in pairs(AIPeds) do if o.veh == veh then o.veh = nil end end
                if GetEntityModel(u.veh) == GetHashKey('flatbed') then
                    AttachEntityToEntity(veh, u.veh, GetEntityBoneIndexByName(u.veh, 'bodyshell'), 0.0, -2.2, 1.05, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                    u.cargo = { veh }
                else
                    Vanish(veh)
                end
                CreateThread(function() TriggerCallback('aiTowed', plate) end)
                Notify('Vehicle towed (' .. plate .. ').')
            end
            Leave(u)
        end)
    elseif u.kind == 'ems' then
        u.state = 'working'
        CreateThread(function()
            local pos = u.target
            local patients = {}
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and #(GetEntityCoords(ped) - pos) < 45.0 then
                    local e = AIPeds[ped]
                    local hurt = GetEntityHealth(ped) < 180 or IsPedDeadOrDying(ped, true) or (e and e.role == 'victim' and e.injured)
                    local crew = IsUnitPed(ped)
                    local prisoner = e and (e.status == 'cuffed' or e.status == 'escorted' or e.status == 'seated' or e.status == 'cuffing')
                    if hurt and not crew and not prisoner then patients[#patients + 1] = ped end
                end
            end
            if #patients == 0 then Notify('~g~EMS:~s~ nobody here needs treatment.') return Leave(u) end
            GetOut(u)
            Wait(2000)
            local medic = u.crew[#u.crew]
            for _, pt in ipairs(patients) do
                if DoesEntityExist(pt) and Alive(medic) and Control(medic, 500) then
                    TaskGoToEntity(medic, pt, 12000, 1.2, 2.0, 1073741824, 0)
                    local t = GetGameTimer() + 12000
                    while Dist(medic, pt) > 1.8 and GetGameTimer() < t do Wait(300) end
                    TaskStartScenarioInPlace(medic, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
                    Wait(7000)
                    ClearPedTasks(medic)
                    local e = AIPeds[pt]
                    if IsPedDeadOrDying(pt, true) then
                        Notify('~g~EMS:~s~ the patient didn\'t make it. Request a coroner.')
                    else
                        Notify('~g~EMS:~s~ patient treated and taken to hospital.')
                        if e then Untrack(e) end
                        Vanish(pt)
                    end
                end
            end
            Leave(u)
        end)
    elseif u.kind == 'coroner' then
        u.state = 'working'
        CreateThread(function()
            local pos = u.target
            local bodies = {}
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and IsPedDeadOrDying(ped, true) and #(GetEntityCoords(ped) - pos) < 60.0 then bodies[#bodies + 1] = ped end
            end
            if #bodies == 0 then Notify('Coroner: there are no bodies here.') return Leave(u) end
            GetOut(u)
            Wait(1800)
            for _, b in ipairs(bodies) do
                if DoesEntityExist(b) and Alive(d) and Control(d, 500) then
                    TaskGoToEntity(d, b, 12000, 1.2, 1.0, 1073741824, 0)
                    local t = GetGameTimer() + 12000
                    while Dist(d, b) > 1.8 and GetGameTimer() < t do Wait(300) end
                    TaskStartScenarioInPlace(d, 'CODE_HUMAN_MEDIC_KNEEL', 0, true)
                    Wait(6000)
                    ClearPedTasks(d)
                    local e = AIPeds[b]
                    if e then Untrack(e) end
                    Vanish(b)
                end
            end
            Notify('Coroner: the scene is clear.')
            Leave(u)
        end)
    end
end

function IsUnitPed(ped)
    for _, u in ipairs(Units) do for _, p in ipairs(u.crew) do if p == ped then return u end end end
    if PartnerPed and PartnerPed() == ped then return true end
    return nil
end

---------------------------------------------------------------------------
-- Getting unstuck: reverse out, try again, and only teleport if nobody can see
---------------------------------------------------------------------------
local function Unstick(u, dest)
    local d = Driver(u)
    if not d or not Control(d, 300) or not Control(u.veh, 300) then return end
    u.reverses = u.reverses + 1
    if u.reverses <= 2 then
        TaskVehicleTempAction(d, u.veh, u.reverses == 1 and 3 or 4, 2500)
        SetTimeout(2600, function() if u.state == 'enroute' then DriveTo(u, dest, u.code3) end end)
    else
        local pos, heading = SpawnPoint(dest, 40.0, 110.0)
        if pos and Hidden(GetEntityCoords(u.veh)) and Hidden(pos) then
            SetEntityCoords(u.veh, pos.x, pos.y, pos.z + 0.5, false, false, false, false)
            SetEntityHeading(u.veh, heading or 0.0)
            SetVehicleOnGroundProperly(u.veh)
            u.reverses = 0
        elseif u.reverses > 6 then
            -- can't get through and you can see it: walk the rest
            u.walked = true
            u.state = 'arriving'
            CreateThread(function() Arrive(u) end)
            return
        end
        DriveTo(u, dest, u.code3)
    end
    u.lastMove = GetGameTimer()
end

---------------------------------------------------------------------------
-- Keep every unit doing its job
---------------------------------------------------------------------------
local function NearestThreat(from, range)
    local target, td = nil, range
    for ped, e in pairs(AIPeds) do
        if e.status == 'fighting' or e.status == 'fleeing' then
            local dd = #(GetEntityCoords(ped) - from)
            if dd < td then target, td = e, dd end
        end
    end
    return target
end

local function OnFootDuty(u, me, mypos)
    local target = NearestThreat(mypos, u.kind == 'swat' and 120.0 or 70.0)
    for k, p in ipairs(u.crew) do
        if Alive(p) and p ~= u.dog and Control(p, 300) then
            if IsPedInAnyVehicle(p, false) then
                if GetEntitySpeed(u.veh) < 1.0 then TaskLeaveVehicle(p, u.veh, 256) end
            elseif target and target.status == 'fighting' then
                if not IsPedInCombat(p, target.ped) then TaskCombatPed(p, target.ped, 0, 16) end
            elseif target and target.status == 'fleeing' then
                if Dist(p, target.ped) < 2.2 then
                    if Control(target.ped, 300) then
                        SetPedToRagdoll(target.ped, 3000, 3000, 0, false, false, false)
                        local tg = target
                        SetTimeout(3000, function() if AIPeds[tg.ped] == tg then Surrender(tg) end end)
                    end
                else
                    TaskGoToEntity(p, target.ped, -1, 1.5, 3.0, 1073741824, 0)
                end
            elseif StopCover(u, p, k) then
                -- covering a stop
            elseif #(GetEntityCoords(p) - mypos) > 7.0 then
                TaskFollowToOffsetOfEntity(p, me, (k % 2 == 1) and 2.2 or -2.2, -2.5 - k, 0.0, 2.0, -1, 2.5, true)
            elseif not IsPedUsingAnyScenario(p) and GetEntitySpeed(p) < 0.2 then
                TaskStartScenarioInPlace(p, 'WORLD_HUMAN_COP_IDLES', 0, true)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(500)
        local me = Me()
        local mypos = GetEntityCoords(me)
        local myVeh = GetVehiclePedIsIn(me, false)
        local now = GetGameTimer()
        for i = #Units, 1, -1 do
            local u = Units[i]
            local d = Driver(u)
            if not d then
                if u.state ~= 'leaving' then
                    Notify(AI.Units[u.kind].label .. ' is down!')
                    if AI.PoliceUnits[u.kind] then RadioLine('Dispatch: all units, officer down at ' .. Street(u.veh ~= 0 and DoesEntityExist(u.veh) and GetEntityCoords(u.veh) or mypos) .. '!') end
                end
                -- bodies stay a while, then are cleaned up
                local dead = u
                RemoveBlipSafe(dead.blip)
                Dead[#Dead + 1] = dead
                SetTimeout(120000, function()
                    Remove(dead)
                    for k = #Dead, 1, -1 do if Dead[k] == dead then table.remove(Dead, k) end end
                end)
                table.remove(Units, i)
            elseif u.veh ~= 0 and not DoesEntityExist(u.veh) then
                -- the car's gone but the crew aren't: they stay on foot with you
                Notify(AI.Units[u.kind].label .. ' lost their vehicle - they\'ll stay with you on foot.')
                u.veh, u.pursuit = 0, nil
                if u.state ~= 'leaving' then u.state = 'onscene' end
            elseif u.veh == 0 and u.state ~= 'onscene' and u.state ~= 'leaving' then
                u.state = 'onscene'
            elseif u.veh == 0 and u.state == 'leaving' then
                if #(GetEntityCoords(d) - mypos) > 120.0 or now - u.leftAt > 60000 then Remove(u) table.remove(Units, i)
                elseif not u.wander and Control(d, 200) then u.wander = true for _, p in ipairs(u.crew) do if Alive(p) then TaskWanderStandard(p, 10.0, 10) end end end
            elseif u.veh == 0 then
                if now > u.retask then u.retask = now + 2500 OnFootDuty(u, me, mypos) end
            elseif u.pursuit then
                -- ai_pursuit.lua is driving this unit
            elseif u.state == 'leaving' then
                local far = #(GetEntityCoords(u.veh) - mypos)
                if (far > 180.0 and Hidden(GetEntityCoords(u.veh))) or far > 400.0 or now - u.leftAt > 120000 then
                    Remove(u)
                    table.remove(Units, i)
                end
            elseif u.state == 'enroute' then
                local dest = (u.kind == 'tow' or u.kind == 'ems' or u.kind == 'coroner' or u.kind == 'k9') and u.target or mypos
                if u.kind == 'k9' and u.data.veh and DoesEntityExist(u.data.veh) then dest = GetEntityCoords(u.data.veh) end
                local dist = #(GetEntityCoords(u.veh) - dest)
                if GetEntitySpeed(u.veh) > 2.0 then u.lastMove = now u.reverses = 0 end
                if dist < 50.0 and (u.kind == 'backup' or u.kind == 'swat' or u.kind == 'transport' or u.kind == 'roadblock' or u.kind == 'spikes') and ParkSpot(u) then
                    local spot, h = ParkSpot(u)
                    u.state, u.parkUntil, u.spot = 'parking', now + 12000, spot
                    if Control(d, 300) then
                        TaskVehicleDriveToCoord(d, u.veh, spot.x, spot.y, spot.z, 9.0, 0, GetEntityModel(u.veh), 786469, 2.0, true)
                    end
                elseif dist < 26.0 then
                    u.state = 'arriving'
                    CreateThread(function() Arrive(u) end)
                elseif now - u.lastMove > (u.code3 and 7000 or 20000) then
                    Unstick(u, dest)
                elseif now - u.started > 240000 then
                    u.started = now
                    u.reverses = 3
                    Unstick(u, dest)
                elseif now > u.retask and #(dest - (u.dest or dest)) > 40.0 then
                    u.retask = now + 4000
                    DriveTo(u, dest, u.code3)
                end
            elseif u.state == 'parking' then
                if #(GetEntityCoords(u.veh) - u.spot) < 4.0 or now > u.parkUntil or (GetEntitySpeed(u.veh) < 0.5 and now > u.parkUntil - 9000) then
                    u.state = 'arriving'
                    CreateThread(function() Arrive(u) end)
                end
            elseif (u.kind == 'backup' or u.kind == 'swat' or u.kind == 'roadblock' or u.kind == 'spikes') and u.state == 'onscene' then
                -- you drove off: everyone back in and follow you
                local carOk = u.veh ~= 0 and DoesEntityExist(u.veh)
                if carOk and myVeh ~= 0 and GetEntitySpeed(myVeh) > 6.0 and #(GetEntityCoords(u.veh) - mypos) > 35.0 and not NearestThreat(mypos, 70.0) and not CurrentStop() then
                    u.state = 'following'
                    UnitBoard(u)
                    u.followAt = now + 8000
                elseif now > u.retask then
                    u.retask = now + 2500
                    OnFootDuty(u, me, mypos)
                end
            elseif u.state == 'following' then
                -- you stopped and got out: park up and join you
                if myVeh == 0 and #(GetEntityCoords(u.veh) - mypos) < 50.0 and GetEntitySpeed(u.veh) < 3.0 then
                    u.state = 'arriving'
                    u.followVeh = nil
                    CreateThread(function() Arrive(u) end)
                elseif now > (u.followAt or 0) and now > u.retask then
                    u.retask = now + 5000
                    if Control(d, 300) and IsPedInVehicle(d, u.veh, false) then
                        if myVeh ~= 0 then
                            -- only re-issue the escort if you changed car or it fell way behind
                            if u.followVeh ~= myVeh or #(GetEntityCoords(u.veh) - mypos) > 150.0 then
                                u.followVeh = myVeh
                                TaskVehicleEscort(d, u.veh, myVeh, -1, 40.0, CODE2, 10.0 + 6.0 * i, 0, 20.0)
                            end
                        elseif #(mypos - (u.dest or vector3(0.0, 0.0, 0.0))) > 25.0 then
                            u.followVeh = nil
                            DriveTo(u, mypos, false)
                        end
                    end
                end
            elseif u.kind == 'k9' and u.state == 'onscene' and u.k9done and now > u.retask then
                u.retask = now + 2500
                local dog, handler = u.dog, Driver(u)
                local target = nil
                local td = 140.0
                for ped, e in pairs(AIPeds) do
                    if e.status == 'fleeing' or e.status == 'hiding' or e.status == 'fighting' then
                        local dd = #(GetEntityCoords(ped) - mypos)
                        if dd < td then target, td = e, dd end
                    end
                end
                if Alive(dog) and Control(dog, 300) then
                    if target and K9Bite then
                        K9Bite(dog, target)
                    elseif handler then
                        TaskFollowToOffsetOfEntity(dog, handler, 0.6, -0.8, 0.0, 3.0, -1, 1.5, true)
                    end
                end
                if handler and Control(handler, 300) and not IsPedInAnyVehicle(handler, false) and #(GetEntityCoords(handler) - mypos) > 8.0 then
                    TaskFollowToOffsetOfEntity(handler, me, 2.0, -3.0, 0.0, 2.0, -1, 3.0, true)
                end
            elseif u.kind == 'transport' and u.state == 'waiting' then
                if now > (u.waitUntil or 0) then
                    Notify('Prisoner transport has left - request it again when you\'re ready.')
                    Leave(u)
                elseif not u.out and IsPedInAnyVehicle(d, false) then
                    u.out = true
                    if Control(d, 300) then TaskLeaveVehicle(d, u.veh, 256) end
                    SetTimeout(2500, function() if Alive(d) and Control(d, 300) then TaskStartScenarioInPlace(d, 'WORLD_HUMAN_COP_IDLES', 0, true) end end)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, u in ipairs(Dead) do Units[#Units + 1] = u end
    for _, u in ipairs(Units) do
        for _, p in ipairs(u.crew) do if DoesEntityExist(p) then DeleteEntity(p) end end
        for _, p in ipairs(u.left or {}) do if DoesEntityExist(p) then DeleteEntity(p) end end
        for _, p in ipairs(u.cargo or {}) do if DoesEntityExist(p) then DeleteEntity(p) end end
        for _, o in ipairs(u.props or {}) do if DoesEntityExist(o) then DeleteEntity(o) end end
        if u.veh ~= 0 and DoesEntityExist(u.veh) then DeleteEntity(u.veh) end
        RemoveBlipSafe(u.blip)
    end
    if air then
        if DoesEntityExist(air.pilot) then DeleteEntity(air.pilot) end
        if DoesEntityExist(air.heli) then DeleteEntity(air.heli) end
        RemoveBlipSafe(air.blip)
    end
end)
