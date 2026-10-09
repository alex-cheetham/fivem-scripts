-- Cuffs, zip ties, escorting, vehicles, tackles (both the officer and the person restrained)
local myBag = nil
local cuffKind = nil
local cuffProp = nil
local escortedBy = nil

local function OfficerPed(serverId)
    local pid = GetPlayerFromServerId(serverId)
    if pid == -1 then return nil end
    return GetPlayerPed(pid)
end

---------------------------------------------------------------------------
-- Officer side animations
---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'cuffSeqCop', function(target)
    local ped = PlayerPedId()
    local tped = OfficerPed(target)
    if tped then TaskTurnPedToFaceEntity(ped, tped, 300) Wait(300) end
    local prop = AttachProp('cuffsHand')
    PlayAnim('cuffCop', 0, Config.Anims.cuffCop.time)
    Wait(Config.Anims.cuffCop.time)
    DeleteProp(prop)
    ClearPedTasks(ped)
end)

RegisterNetEvent(EV .. 'uncuffSeqCop', function(target)
    local ped = PlayerPedId()
    local tped = OfficerPed(target)
    if tped then TaskTurnPedToFaceEntity(ped, tped, 300) Wait(300) end
    PlayAnim('uncuffCop', 0, Config.Anims.uncuffCop.time)
    Wait(Config.Anims.uncuffCop.time)
    ClearPedTasks(ped)
end)

---------------------------------------------------------------------------
-- Being cuffed
---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'cuffSeq', function(officer)
    local ped = PlayerPedId()
    local oped = OfficerPed(officer)
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    if oped then
        AttachEntityToEntity(ped, oped, 11816, -0.1, 0.45, 0.0, 0.0, 0.0, 20.0, false, false, false, false, 20, false)
    end
    PlayAnim('cuffCrook', 0, Config.Anims.cuffCrook.time)
    Wait(Config.Anims.cuffCrook.time - 200)
    DetachEntity(ped, true, false)
end)

RegisterNetEvent(EV .. 'uncuffSeq', function(officer)
    local ped = PlayerPedId()
    local oped = OfficerPed(officer)
    if oped then
        local fwd = GetOffsetFromEntityInWorldCoords(oped, 0.0, 0.8, 0.0)
        SetEntityCoords(ped, fwd.x, fwd.y, fwd.z - 1.0, false, false, false, false)
        SetEntityHeading(ped, GetEntityHeading(oped))
    end
    PlayAnim('uncuffCrook', 0, Config.Anims.uncuffCrook.time)
end)

local function ApplyCuffs(kind)
    cuffKind = kind
    local ped = PlayerPedId()
    DeleteProp(cuffProp)
    cuffProp = AttachProp(kind == 'zip' and 'ziptie' or 'cuffs', ped, true)
    SetEnableHandcuffs(ped, true)
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
end

local function RemoveCuffs()
    cuffKind = nil
    local ped = PlayerPedId()
    DeleteProp(cuffProp)
    cuffProp = nil
    SetEnableHandcuffs(ped, false)
    StopAnim('cuffedIdle')
    StopAnim('zipIdle')
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    escortedBy = nil
end

function AmCuffed() return cuffKind ~= nil end

-- Keep restrained players restrained
CreateThread(function()
    while true do
        if cuffKind then
            local ped = PlayerPedId()
            DisableControlAction(0, 24, true)  DisableControlAction(0, 25, true)   -- attack / aim
            DisableControlAction(0, 140, true) DisableControlAction(0, 141, true)  -- melee
            DisableControlAction(0, 142, true) DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true) DisableControlAction(0, 264, true)
            DisableControlAction(0, 21, true)  DisableControlAction(0, 22, true)   -- sprint / jump
            DisableControlAction(0, 23, true)  DisableControlAction(0, 75, true)   -- enter / exit vehicle
            DisableControlAction(0, 37, true)  DisableControlAction(0, 44, true)   -- weapon wheel / cover
            DisableControlAction(0, 45, true)  DisableControlAction(27, 75, true)
            if GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true) end
            local idle = cuffKind == 'zip' and 'zipIdle' or 'cuffedIdle'
            if not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped) and not IsPlaying(idle, ped)
                and not IsPlaying('cuffCrook', ped) and not IsPlaying('uncuffCrook', ped) and not IsPlaying('tackleCrook', ped) then
                PlayAnim(idle, 49)
            end
            Wait(0)
        else
            Wait(400)
        end
    end
end)

-- Escorting: the restrained player follows the officer
CreateThread(function()
    while true do
        local sleep = 500
        if escortedBy then
            sleep = 0
            local ped = PlayerPedId()
            local oped = OfficerPed(escortedBy)
            if oped and not IsPedInAnyVehicle(ped, false) then
                if not IsEntityAttachedToEntity(ped, oped) then
                    AttachEntityToEntity(ped, oped, 11816, 0.54, 0.54, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                end
            end
        end
        Wait(sleep)
    end
end)

local function OnMyState(key, value)
    if key == 'cuffed' then
        if value then ApplyCuffs(value) else RemoveCuffs() end
    elseif key == 'escort' then
        local ped = PlayerPedId()
        escortedBy = value or nil
        if not value and IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    end
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    myBag = ('player:%d'):format(GetPlayerServerId(PlayerId()))
    AddStateBagChangeHandler('cuffed', myBag, function(_, _, value) OnMyState('cuffed', value) end)
    AddStateBagChangeHandler('escort', myBag, function(_, _, value) OnMyState('escort', value) end)
    if LocalPlayer.state.cuffed then ApplyCuffs(LocalPlayer.state.cuffed) end
end)

-- Put in / taken out of a vehicle
RegisterNetEvent(EV .. 'seat', function(netId)
    local veh = NetToVeh(netId)
    if veh == 0 then return end
    local ped = PlayerPedId()
    escortedBy = nil
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    local seats = GetVehicleMaxNumberOfPassengers(veh)
    for _, seat in ipairs({ 1, 2, 0, 3, 4, 5 }) do
        if seat <= seats - 1 and IsVehicleSeatFree(veh, seat) then
            TaskWarpPedIntoVehicle(ped, veh, seat)
            return
        end
    end
    Notify('There\'s no free seat.')
end)

RegisterNetEvent(EV .. 'unseat', function(officer)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return end
    TaskLeaveVehicle(ped, veh, 16)
    Wait(1200)
    local oped = OfficerPed(officer)
    if oped then
        local p = GetOffsetFromEntityInWorldCoords(oped, 0.6, 0.6, 0.0)
        SetEntityCoords(ped, p.x, p.y, p.z - 1.0, false, false, false, false)
    end
end)

-- Tackled
RegisterNetEvent(EV .. 'tackled', function(officer)
    local ped = PlayerPedId()
    local oped = OfficerPed(officer)
    if oped then
        AttachEntityToEntity(ped, oped, 11816, 0.25, 0.5, 0.0, 0.5, 0.5, 180.0, false, false, false, false, 2, false)
        PlayAnim('tackleCrook', 0, 3000)
        Wait(3000)
        DetachEntity(ped, true, false)
    end
    SetPedToRagdoll(ped, Config.Tackle.ragdoll, Config.Tackle.ragdoll, 0, false, false, false)
end)

---------------------------------------------------------------------------
-- Officer actions (menu buttons and commands call these)
---------------------------------------------------------------------------
function DoCuff(arg, kind)
    if Busy then return end
    local id = NeedTarget(arg)
    if not id then return end
    local st = Player(id).state.cuffed
    if st and not kind then return DoUncuff(id) end
    Result(TriggerCallback('cuff', id, kind or 'cuffs'))
end

function DoUncuff(arg)
    if Busy then return end
    local id = NeedTarget(arg)
    if not id then return end
    Result(TriggerCallback('uncuff', id))
end

function DoEscort(arg)
    local id = NeedTarget(arg, 3.0)
    if not id then return end
    Result(TriggerCallback('escort', id))
end

function DoSeat(arg)
    local id = tonumber(arg)
    if not id then
        -- whoever I'm escorting, else the nearest person
        for _, p in ipairs(PlayersNear(4.0)) do
            if Player(p.id).state.escort == GetPlayerServerId(PlayerId()) then id = p.id break end
        end
        id = id or Target(nil, 3.0)
    end
    if not id then return Notify('Nobody close enough.') end
    local veh = VehicleAhead(6.0)
    if not veh or veh == 0 then return Notify('No vehicle nearby.') end
    Result(TriggerCallback('seat', id, VehToNet(veh)))
end

function DoUnseat(arg)
    local id = tonumber(arg)
    if not id then
        local veh = VehicleAhead(6.0)
        if not veh or veh == 0 then return Notify('No vehicle nearby.') end
        for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
            local p = GetPedInVehicleSeat(veh, seat)
            if p ~= 0 and IsPedAPlayer(p) then
                local sid = GetPlayerServerId(NetworkGetPlayerIndexFromPed(p))
                if Player(sid).state.cuffed then id = sid break end
            end
        end
    end
    if not id then return Notify('Nobody restrained in that vehicle.') end
    Result(TriggerCallback('unseat', id))
end

-- Tackle (while sprinting at someone)
RegisterCommand('+police_tackle', function()
    if not IsPolice or Busy then return end
    local ped = PlayerPedId()
    if not IsPedSprinting(ped) or IsPedInAnyVehicle(ped, false) then return end
    local fwd = GetEntityForwardVector(ped)
    local pos = GetEntityCoords(ped)
    for _, p in ipairs(PlayersNear(Config.Tackle.distance)) do
        local dir = GetEntityCoords(p.ped) - pos
        local len = #dir
        if len > 0.1 and (dir.x * fwd.x + dir.y * fwd.y) / len > 0.6 then
            local res = TriggerCallback('tackle', p.id)
            if res and res.ok then
                PlayAnim('tackleCop', 0, 3000)
                Wait(600)
                SetPedToRagdoll(ped, 1200, 1200, 0, false, false, false)
            else
                Result(res)
            end
            return
        end
    end
end, false)
RegisterCommand('-police_tackle', function() end, false)
RegisterKeyMapping('+police_tackle', 'Statewide PD: tackle (while sprinting)', 'keyboard', Config.Keys.tackle)

RegisterCommand('+police_quickcuff', function() if IsPolice then DoCuff() end end, false)
RegisterCommand('-police_quickcuff', function() end, false)
RegisterKeyMapping('+police_quickcuff', 'Statewide PD: cuff / uncuff nearest person', 'keyboard', Config.Keys.cuff)
RegisterCommand('+police_quickescort', function() if IsPolice then DoEscort() end end, false)
RegisterCommand('-police_quickescort', function() end, false)
RegisterKeyMapping('+police_quickescort', 'Statewide PD: escort nearest person', 'keyboard', Config.Keys.escort)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    DeleteProp(cuffProp)
    ClearHeld()
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    SetEnableHandcuffs(ped, false)
end)
