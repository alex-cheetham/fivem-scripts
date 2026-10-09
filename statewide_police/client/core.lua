EV = 'statewide_police:'
IsPolice = false
IsAdmin = false
Points = { stations = {}, spawns = {}, chores = {}, comserv = {} }
Busy = false

function Notify(msg) Config.Notify(msg) end
RegisterNetEvent(EV .. 'notify', Notify)

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
local cbId, cbWait = 0, {}
function TriggerCallback(name, ...)
    cbId = cbId + 1
    local id, p = cbId, promise.new()
    cbWait[id] = p
    TriggerServerEvent(EV .. 'cb', id, name, ...)
    SetTimeout(20000, function() if cbWait[id] then cbWait[id] = nil p:resolve({ ok = false, msg = 'The server didn\'t answer.' }) end end)
    return Citizen.Await(p)
end
RegisterNetEvent(EV .. 'cbr', function(id, res)
    local p = cbWait[id]
    if p then cbWait[id] = nil p:resolve(res) end
end)

-- The server asking this client something (weapons, consent...)
Answers = {}
RegisterNetEvent(EV .. 'ask', function(id, what, data)
    local fn = Answers[what]
    CreateThread(function()
        local value = fn and fn(data) or nil
        TriggerServerEvent(EV .. 'answer', id, value)
    end)
end)

function Result(res, okMsg)
    if not res then return false end
    if not res.ok then
        if res.msg then Notify(res.msg) end
        return false
    end
    if okMsg or res.msg then Notify(okMsg or res.msg) end
    return true
end

---------------------------------------------------------------------------
-- Models, animations and props
---------------------------------------------------------------------------
function LoadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

function LoadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

-- flag 49 = upper body + loop + can move, 1 = loop, 0 = once, 50 = upper body loop stays
function PlayAnim(key, flag, duration, ped)
    local a = Config.Anims[key]
    ped = ped or PlayerPedId()
    if not a or not LoadDict(a.dict) then return false end
    TaskPlayAnim(ped, a.dict, a.name, 8.0, -8.0, duration or -1, flag or 49, 0.0, false, false, false)
    return true
end

function StopAnim(key, ped)
    local a = Config.Anims[key]
    ped = ped or PlayerPedId()
    if a then StopAnimTask(ped, a.dict, a.name, 2.0) end
end

function IsPlaying(key, ped)
    local a = Config.Anims[key]
    return a and IsEntityPlayingAnim(ped or PlayerPedId(), a.dict, a.name, 3)
end

local held = {}
function AttachProp(key, ped, networked)
    local p = Config.Props[key]
    if not p then return nil end
    ped = ped or PlayerPedId()
    local hash = LoadModel(p.model) or LoadModel(Config.FallbackProp)
    if not hash then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.2, networked ~= false, true, false)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, p.bone), p.pos.x, p.pos.y, p.pos.z, p.rot.x, p.rot.y, p.rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    held[#held + 1] = obj
    return obj
end

function DeleteProp(obj)
    if obj and DoesEntityExist(obj) then
        DetachEntity(obj, true, false)
        DeleteEntity(obj)
    end
end

function ClearHeld()
    for _, o in ipairs(held) do DeleteProp(o) end
    held = {}
end

-- Do something with an animation and props for a while. Returns false if cancelled (X).
function Action(label, ms, anim, props, flag)
    Busy = true
    local ped = PlayerPedId()
    local made = {}
    for _, k in ipairs(props or {}) do made[#made + 1] = AttachProp(k) end
    if anim then PlayAnim(anim, flag or 49) end
    SendNUIMessage({ action = 'progress', label = label, ms = ms })
    local ends, cancelled = GetGameTimer() + ms, false
    while GetGameTimer() < ends do
        Wait(0)
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        DisableControlAction(0, 21, true) DisableControlAction(0, 22, true)
        if IsControlJustPressed(0, 73) then cancelled = true break end   -- X
        if anim and not IsPlaying(anim, ped) then PlayAnim(anim, flag or 49) end
    end
    SendNUIMessage({ action = 'progressEnd' })
    if anim then StopAnim(anim) end
    for _, o in ipairs(made) do DeleteProp(o) end
    Busy = false
    return not cancelled
end

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------
function PlayersNear(radius)
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local list = {}
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            local d = #(GetEntityCoords(ped) - pos)
            if d <= radius then
                list[#list + 1] = { id = GetPlayerServerId(pid), ped = ped, dist = d, name = GetPlayerName(pid) }
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

-- The nearest player (or a given server id). Returns serverId, ped
function Target(arg, radius)
    local id = tonumber(arg)
    if id then
        local pid = GetPlayerFromServerId(id)
        if pid == -1 then return nil end
        return id, GetPlayerPed(pid)
    end
    local list = PlayersNear(radius or 2.5)
    if #list == 0 then return nil end
    return list[1].id, list[1].ped
end

function NeedTarget(arg, radius)
    local id, ped = Target(arg, radius)
    if not id then Notify('Nobody close enough.') end
    return id, ped
end

-- Vehicle in front of me (or the one I'm in)
function VehicleAhead(dist)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and not dist then return veh end
    local from = GetEntityCoords(ped)
    local to = GetOffsetFromEntityInWorldCoords(ped, 0.0, dist or 5.0, 0.0)
    local ray = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 1.2, 10, ped, 7)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if hit == 1 and ent ~= 0 and IsEntityAVehicle(ent) then return ent end
    -- fall back to the closest vehicle
    local best, bd = nil, (dist or 5.0) + 1.0
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - from)
        if d < bd then best, bd = v, d end
    end
    return best
end

function Help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

function Text3D(pos, text, scale)
    local on, x, y = World3dToScreen2d(pos.x, pos.y, pos.z)
    if not on then return end
    SetTextScale(scale or 0.32, scale or 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

function V3(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

---------------------------------------------------------------------------
-- Start up
---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'police', function(state) IsPolice = state end)
RegisterNetEvent(EV .. 'points', function(p) Points = p end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(2000)
    local res = TriggerCallback('init')
    if res and res.ok then
        IsPolice, IsAdmin, Points = res.police, res.admin, res.points
    end
    TriggerServerEvent(EV .. 'joined')
end)
