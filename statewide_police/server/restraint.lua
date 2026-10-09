-- Cuffs, zip ties, escorting, putting people in vehicles, tackles
local Busy = {}          -- [target] = true while being cuffed / uncuffed
local CuffedIdents = {}  -- people who left while cuffed stay cuffed when they come back
local LastTackle = {}

function IsCuffed(src) return Player(src).state.cuffed end

local function SetCuffed(src, kind)
    Player(src).state:set('cuffed', kind or false, true)
    local ident = Ident(src)
    if ident then CuffedIdents[ident] = kind or nil end
    if not kind then Player(src).state:set('escort', false, true) end
end
function Uncuff(src) SetCuffed(src, nil) end

PoliceCallback('cuff', function(src, target, kind)
    local t, err = CheckTarget(src, target, 2.2)
    if not t then return err end
    kind = kind == 'zip' and 'zip' or 'cuffs'
    if Busy[t] then return Fail('Hold on...') end
    if GetVehiclePedIsIn(GetPlayerPed(t), false) ~= 0 then return Fail('Get them out of the vehicle first.') end
    if IsCuffed(t) then return Fail('They\'re already restrained.') end
    Busy[t] = true
    TriggerClientEvent(EV .. 'cuffSeq', t, src, kind)
    TriggerClientEvent(EV .. 'cuffSeqCop', src, t, kind)
    SetTimeout(3600, function()
        Busy[t] = nil
        if Online(t) then
            SetCuffed(t, kind)
            Notify(t, kind == 'zip' and 'You\'ve been zip-tied.' or 'You\'ve been handcuffed.')
        end
    end)
    return { ok = true }
end)

PoliceCallback('uncuff', function(src, target)
    local t, err = CheckTarget(src, target, 2.2)
    if not t then return err end
    if not IsCuffed(t) then return Fail('They aren\'t restrained.') end
    if Busy[t] then return Fail('Hold on...') end
    Busy[t] = true
    Player(t).state:set('escort', false, true)
    TriggerClientEvent(EV .. 'uncuffSeq', t, src)
    TriggerClientEvent(EV .. 'uncuffSeqCop', src, t)
    SetTimeout(4800, function()
        Busy[t] = nil
        if Online(t) then SetCuffed(t, nil) Notify(t, 'You\'ve been released from your restraints.') end
    end)
    return { ok = true }
end)

PoliceCallback('escort', function(src, target)
    local t, err = CheckTarget(src, target, 3.0)
    if not t then return err end
    if not IsCuffed(t) then return Fail('They need to be restrained first.') end
    local cur = Player(t).state.escort
    if cur == src then
        Player(t).state:set('escort', false, true)
        return { ok = true, msg = 'You let go of them.' }
    end
    if cur and Online(cur) and cur ~= src then return Fail('Someone else is escorting them.') end
    Player(t).state:set('escort', src, true)
    return { ok = true, msg = 'Escorting.' }
end)

PoliceCallback('seat', function(src, target, netId)
    local t, err = CheckTarget(src, target, 6.0)
    if not t then return err end
    if not IsCuffed(t) then return Fail('They need to be restrained first.') end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return Fail('No vehicle there.') end
    if #(GetEntityCoords(veh) - Pos(src)) > 7.0 then return Fail('Get closer to the vehicle.') end
    Player(t).state:set('escort', false, true)
    TriggerClientEvent(EV .. 'seat', t, netId)
    return { ok = true }
end)

PoliceCallback('unseat', function(src, target)
    target = tonumber(target)
    if not Online(target) then return Fail('Nobody there.') end
    local veh = GetVehiclePedIsIn(GetPlayerPed(target), false)
    if veh == 0 then return Fail('They aren\'t in a vehicle.') end
    if #(GetEntityCoords(veh) - Pos(src)) > 7.0 then return Fail('Get closer to the vehicle.') end
    if not IsCuffed(target) then return Fail('Only restrained people can be pulled out - ask them to step out.') end
    TriggerClientEvent(EV .. 'unseat', target, src)
    SetTimeout(2200, function()
        if Online(target) and Online(src) and IsCuffed(target) then Player(target).state:set('escort', src, true) end
    end)
    return { ok = true }
end)

PoliceCallback('tackle', function(src, target)
    local t, err = CheckTarget(src, target, Config.Tackle.distance + 1.0)
    if not t then return err end
    if os.time() - (LastTackle[src] or 0) < Config.Tackle.cooldown then return Fail('You\'re still getting your breath back.') end
    LastTackle[src] = os.time()
    TriggerClientEvent(EV .. 'tackled', t, src)
    return { ok = true }
end)

-- Coming back after leaving while cuffed
RegisterNetEvent(EV .. 'joined', function()
    local src = source
    local ident = Ident(src)
    local kind = ident and CuffedIdents[ident]
    if kind then
        SetTimeout(4000, function()
            if not Online(src) then return end
            SetCuffed(src, kind)
            Notify(src, 'You left while restrained, so you\'re still restrained.')
            for _, p in ipairs(GetPlayers()) do
                p = tonumber(p)
                if IsPolice(p) then Notify(p, ('%s (ID %d) came back while still restrained.'):format(Name(src), src)) end
            end
        end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    Busy[src] = nil
    -- let go of anyone this player was escorting
    for _, p in ipairs(GetPlayers()) do
        p = tonumber(p)
        if Player(p).state.escort == src then Player(p).state:set('escort', false, true) end
    end
end)
