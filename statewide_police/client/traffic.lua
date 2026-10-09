-- Radar, plates, vehicle searches, impound, spikes, cones & barriers
local radarOn, radarLocked = false, false
local radarData = {}
local spikes = {}          -- from the server: { id, x, y, z, h }
local markers = {}         -- numbered evidence markers { id, n }
local placing = false

local UNIT = Config.Speed == 'kmh' and 3.6 or 2.236936

---------------------------------------------------------------------------
-- Plates
---------------------------------------------------------------------------
local function ModelName(veh)
    local name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
    if name == 'NULL' then name = GetDisplayNameFromVehicleModel(GetEntityModel(veh)) end
    return name
end

function DoRunPlate(plate)
    local veh
    if not plate or plate == '' then
        local ped = PlayerPedId()
        if radarOn and radarData.front and radarData.front.netId then
            veh = NetToVeh(radarData.front.netId)
        end
        if not veh or veh == 0 then
            local mine = GetVehiclePedIsIn(ped, false)
            veh = VehicleAhead(12.0)
            if veh == mine then
                -- in a car: look further ahead for the car in front
                local from = GetOffsetFromEntityInWorldCoords(mine, 0.0, 3.0, 0.3)
                local to = GetOffsetFromEntityInWorldCoords(mine, 0.0, 25.0, 0.3)
                local ray = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 2.0, 10, mine, 7)
                local _, hit, _, _, ent = GetShapeTestResult(ray)
                veh = (hit == 1 and ent ~= 0 and IsEntityAVehicle(ent)) and ent or nil
            end
        end
        if not veh or veh == 0 then return Notify('No vehicle in front of you - or type /runplate <plate>.') end
    end
    local res = TriggerCallback('runPlate', plate, veh and VehToNet(veh) or nil, veh and ModelName(veh) or nil)
    if not Result(res) then return end
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    OpenPanel('plate', res)
end

---------------------------------------------------------------------------
-- Vehicle search & impound
---------------------------------------------------------------------------
function DoVehSearch()
    if Busy then return end
    local veh = VehicleAhead(4.0)
    if not veh or veh == 0 or IsPedInAnyVehicle(PlayerPedId(), false) then return Notify('Stand next to the vehicle.') end
    local res = TriggerCallback('vehSearchStart', VehToNet(veh))
    if not Result(res) then return end
    SetVehicleDoorOpen(veh, 5, false, false)
    SetVehicleDoorOpen(veh, 0, false, false)
    local done = Action('Searching the vehicle', res.time, 'vehicleSearch', {})
    SetVehicleDoorShut(veh, 5, false)
    SetVehicleDoorShut(veh, 0, false)
    if not done then return Notify('Cancelled.') end
    local r = TriggerCallback('vehSearchResult')
    if Result(r) then OpenPanel('result', r) end
end

RegisterNUICallback('vehSeize', function(d, cb)
    cb('ok')
    CreateThread(function()
        local res = TriggerCallback('vehSeize', d.index)
        if res and res.ok then SendNUIMessage({ action = 'panelUpdate', panel = 'result', data = res }) Notify('Seized and bagged.') else Result(res) end
    end)
end)

function DoImpound()
    if Busy then return end
    local veh = VehicleAhead(5.0)
    if not veh or veh == 0 or IsPedInAnyVehicle(PlayerPedId(), false) then return Notify('Stand next to the vehicle.') end
    if not Action('Filling in the impound form', 8000, 'clipboard', { 'clipboard' }) then return Notify('Cancelled.') end
    Result(TriggerCallback('impound', VehToNet(veh)))
end

function DoDust()
    if Busy then return end
    local veh = VehicleAhead(4.0)
    if not veh or veh == 0 or IsPedInAnyVehicle(PlayerPedId(), false) then return Notify('Stand next to the vehicle.') end
    if not Action('Dusting for fingerprints', 7000, 'dust', { 'printcard' }) then return Notify('Cancelled.') end
    Result(TriggerCallback('dustPrints', VehToNet(veh)))
end

---------------------------------------------------------------------------
-- Radar
---------------------------------------------------------------------------
local function Scan(veh, forward)
    local sign = forward and 1.0 or -1.0
    local from = GetOffsetFromEntityInWorldCoords(veh, 0.0, sign * 3.5, 0.4)
    local to = GetOffsetFromEntityInWorldCoords(veh, 0.0, sign * Config.Radar.range, 0.4)
    local ray = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 3.0, 10, veh, 7)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if hit == 1 and ent ~= 0 and IsEntityAVehicle(ent) then
        return { speed = math.floor(GetEntitySpeed(ent) * UNIT + 0.5), plate = GetVehicleNumberPlateText(ent), netId = NetworkGetEntityIsNetworked(ent) and VehToNet(ent) or nil }
    end
    return nil
end

function DoRadar()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if not radarOn and veh == 0 then return Notify('Get in a vehicle to use the radar.') end
    radarOn = not radarOn
    radarLocked = false
    SendNUIMessage({ action = 'radar', show = radarOn })
    Notify(radarOn and 'Radar on.' or 'Radar off.')
end

CreateThread(function()
    while true do
        if radarOn then
            local veh = GetVehiclePedIsIn(PlayerPedId(), false)
            if veh == 0 or not IsPolice then
                radarOn = false
                SendNUIMessage({ action = 'radar', show = false })
            elseif not radarLocked then
                radarData.front = Scan(veh, true)
                radarData.rear = Scan(veh, false)
                radarData.patrol = math.floor(GetEntitySpeed(veh) * UNIT + 0.5)
                SendNUIMessage({ action = 'radar', show = true, data = radarData, locked = false, fast = Config.Radar.fastLimit,
                    unit = Config.Speed == 'kmh' and 'KMH' or 'MPH' })
            end
            Wait(250)
        else
            Wait(800)
        end
    end
end)

RegisterCommand('+police_radarlock', function()
    if not radarOn then return end
    radarLocked = not radarLocked
    SendNUIMessage({ action = 'radar', show = true, data = radarData, locked = radarLocked, fast = Config.Radar.fastLimit,
        unit = Config.Speed == 'kmh' and 'KMH' or 'MPH' })
    PlaySoundFrontend(-1, radarLocked and 'Beep_Red' or 'Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
end, false)
RegisterCommand('-police_radarlock', function() end, false)
RegisterKeyMapping('+police_radarlock', 'Statewide PD: lock / unlock radar', 'keyboard', Config.Keys.radarLock)

---------------------------------------------------------------------------
-- Placing props (cones, barriers, spikes, markers)
---------------------------------------------------------------------------
local function Place(model, onPlaced)
    if placing or Busy then return end
    local hash = LoadModel(model)
    if not hash then return Notify('That prop isn\'t available.') end
    placing = true
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local ghost = CreateObject(hash, c.x, c.y, c.z, false, false, false)
    SetEntityAlpha(ghost, 160, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    local heading = GetEntityHeading(ped)
    local result = nil
    while true do
        Wait(0)
        local p = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.2, 0.0)
        local found, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)
        SetEntityCoordsNoOffset(ghost, p.x, p.y, found and gz or p.z - 1.0, false, false, false)
        if IsControlPressed(0, 174) then heading = heading + 2.0 end
        if IsControlPressed(0, 175) then heading = heading - 2.0 end
        SetEntityHeading(ghost, heading)
        Help('~INPUT_CONTEXT~ Place~n~~INPUT_CELLPHONE_LEFT~ ~INPUT_CELLPHONE_RIGHT~ Rotate~n~~INPUT_FRONTEND_RRIGHT~ Cancel')
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        if IsControlJustReleased(0, 38) then
            result = { pos = GetEntityCoords(ghost), heading = heading }
            break
        end
        if IsControlJustReleased(0, 177) or IsControlJustReleased(0, 73) then break end
    end
    DeleteEntity(ghost)
    placing = false
    if not result then return Notify('Cancelled.') end
    PlayAnim('place', 0, 1500)
    Wait(1200)
    local obj = CreateObject(hash, result.pos.x, result.pos.y, result.pos.z, true, true, false)
    SetEntityHeading(obj, result.heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    local t = GetGameTimer() + 2000
    while not NetworkGetEntityIsNetworked(obj) and GetGameTimer() < t do NetworkRegisterEntityAsNetworked(obj) Wait(10) end
    onPlaced(obj, ObjToNet(obj))
end

function DoPlace(key)
    local def
    for _, p in ipairs(Config.SceneProps) do if p.key == key then def = p end end
    if not def then return end
    Place(def.model, function(obj, net)
        local res = TriggerCallback('propPlaced', net, key)
        if not Result(res) and DoesEntityExist(obj) then DeleteEntity(obj) end
    end)
end

function DoPickup()
    local pos = GetEntityCoords(PlayerPedId())
    local best, bd = nil, 3.5
    for _, obj in ipairs(GetGamePool('CObject')) do
        local d = #(GetEntityCoords(obj) - pos)
        if d < bd and NetworkGetEntityIsNetworked(obj) then
            local m = GetEntityModel(obj)
            local ok = m == GetHashKey(Config.SpikeModel)
            for _, p in ipairs(Config.SceneProps) do if m == GetHashKey(p.model) then ok = true end end
            if ok then best, bd = obj, d end
        end
    end
    if not best then return Notify('Nothing to pick up here.') end
    PlayAnim('place', 0, 1200)
    Wait(900)
    local net = ObjToNet(best)
    if GetEntityModel(best) == GetHashKey(Config.SpikeModel) then
        Result(TriggerCallback('spikePickup', net))
    else
        Result(TriggerCallback('propPickup', net), 'Picked up.')
    end
end

function DoSpikes()
    -- pick up a nearby strip first, otherwise deploy one
    local pos = GetEntityCoords(PlayerPedId())
    for _, s in ipairs(spikes) do
        if #(vector3(s.x, s.y, s.z) - pos) < 4.0 then
            PlayAnim('place', 0, 1200)
            Wait(900)
            return Result(TriggerCallback('spikePickup', s.id))
        end
    end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return Notify('Get out of the vehicle first.') end
    Place(Config.SpikeModel, function(obj, net)
        local res = TriggerCallback('spikeDeployed', net)
        if not Result(res) and DoesEntityExist(obj) then DeleteEntity(obj) end
    end)
end

RegisterNetEvent(EV .. 'spikes', function(list) spikes = list or {} end)
RegisterNetEvent(EV .. 'markers', function(list) markers = list or {} end)

-- Tyres burst when you drive over a spike strip
local WHEELS = { { 'wheel_lf', 0 }, { 'wheel_rf', 1 }, { 'wheel_lm1', 2 }, { 'wheel_rm1', 3 }, { 'wheel_lr', 4 }, { 'wheel_rr', 5 } }
CreateThread(function()
    local mins, maxs
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and #spikes > 0 then
            local vpos = GetEntityCoords(veh)
            for _, s in ipairs(spikes) do
                if #(vpos - vector3(s.x, s.y, s.z)) < 25.0 then
                    sleep = 0
                    local obj = NetToObj(s.id)
                    if obj ~= 0 and DoesEntityExist(obj) then
                        if not mins then mins, maxs = GetModelDimensions(GetEntityModel(obj)) end
                        for _, w in ipairs(WHEELS) do
                            local bone = GetEntityBoneIndexByName(veh, w[1])
                            if bone ~= -1 and not IsVehicleTyreBurst(veh, w[2], false) then
                                local wp = GetWorldPositionOfEntityBone(veh, bone)
                                local l = GetOffsetFromEntityGivenWorldCoords(obj, wp.x, wp.y, wp.z)
                                if l.x >= mins.x - 0.2 and l.x <= maxs.x + 0.2 and l.y >= mins.y - 0.35 and l.y <= maxs.y + 0.35 and math.abs(l.z) < 1.2 then
                                    SetVehicleTyreBurst(veh, w[2], false, 1000.0)
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Numbers above evidence markers
CreateThread(function()
    while true do
        local sleep = 1000
        if #markers > 0 then
            local pos = GetEntityCoords(PlayerPedId())
            for _, m in ipairs(markers) do
                local obj = NetToObj(m.id)
                if obj ~= 0 and DoesEntityExist(obj) then
                    local p = GetEntityCoords(obj)
                    if #(p - pos) < 15.0 then
                        sleep = 0
                        Text3D(vector3(p.x, p.y, p.z + 0.55), tostring(m.n), 0.45)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
