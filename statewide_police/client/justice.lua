-- Tickets, booking, jail, community service, MDT
local sentence = nil
local tabletProp = nil

local function PenalCode()
    local res = TriggerCallback('penalCode')
    return res and res.ok and res or nil
end

local function OpenForm(kind, arg)
    if Busy then return end
    local id = NeedTarget(arg, 8.0)
    if not id then return end
    local pc = PenalCode()
    if not pc then return end
    local pid = GetPlayerFromServerId(id)
    OpenPanel(kind, { target = id, name = pid ~= -1 and GetPlayerName(pid) or ('ID ' .. id), code = pc.code, maxJail = pc.maxJail, maxTasks = pc.maxTasks,
        cuffed = Player(id).state.cuffed and true or false })
end

function DoTicket(arg) OpenForm('ticket', arg) end
function DoArrest(arg) OpenForm('arrest', arg) end
function DoComserv(arg) OpenForm('comserv', arg) end

RegisterNUICallback('submitForm', function(d, cb)
    cb('ok')
    ClosePanel()
    CreateThread(function()
        if d.kind == 'ticket' then
            if not Action('Writing the citation', 6000, 'write', { 'notepad', 'pencil' }, 1) then return Notify('Cancelled.') end
            Result(TriggerCallback('ticket', d))
        elseif d.kind == 'arrest' then
            if not Action('Booking them in', 4000, 'tablet', { 'tablet' }) then return Notify('Cancelled.') end
            Result(TriggerCallback('arrest', d))
        elseif d.kind == 'comserv' then
            if not Action('Filling in the paperwork', 4000, 'clipboard', { 'clipboard' }) then return Notify('Cancelled.') end
            Result(TriggerCallback('comserv', d))
        end
    end)
end)

---------------------------------------------------------------------------
-- Fines (the person being fined)
---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'citation', function(f)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'citation', data = f })
end)

RegisterNUICallback('payFine', function(d, cb)
    CreateThread(function()
        local res = TriggerCallback('payFine', d.id, d.method)
        Result(res)
        cb(res or {})
    end)
end)

RegisterNetEvent(EV .. 'openFines', function()
    local res = TriggerCallback('myFines')
    if not res or not res.ok then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'fines', fines = res.fines })
end)

---------------------------------------------------------------------------
-- Sentences
---------------------------------------------------------------------------
local function Spot(list)
    return list[math.random(1, math.max(1, #list))]
end

RegisterNetEvent(EV .. 'sentence', function(s, fresh)
    sentence = s
    local ped = PlayerPedId()
    if fresh then
        DoScreenFadeOut(500)
        Wait(600)
        if s.kind == 'jail' then
            local sp = Spot(Points.spawns) or Config.Jail.spawns[1]
            SetEntityCoords(ped, sp.x, sp.y, sp.z, false, false, false, false)
            SetEntityHeading(ped, sp.w or 0.0)
        else
            local c = Config.ComServ.center
            SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
        end
        RemoveAllPedWeapons(ped, true)
        Wait(500)
        DoScreenFadeIn(600)
    end
    SendNUIMessage({ action = 'sentence', data = s })
end)

RegisterNetEvent(EV .. 'sentenceTick', function(left)
    if sentence then sentence.left = left SendNUIMessage({ action = 'sentence', data = sentence }) end
end)

RegisterNetEvent(EV .. 'released', function(kind, why)
    sentence = nil
    SendNUIMessage({ action = 'sentenceEnd' })
    ClearPedTasks(PlayerPedId())
    if kind == 'jail' then
        DoScreenFadeOut(500)
        Wait(600)
        local r = Points.release or Config.Jail.release
        SetEntityCoords(PlayerPedId(), r.x, r.y, r.z, false, false, false, false)
        SetEntityHeading(PlayerPedId(), r.w or 0.0)
        Wait(500)
        DoScreenFadeIn(600)
    end
    Notify(('You\'re free to go. (%s)'):format(why or 'released'))
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if sentence then
            sleep = 0
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local jail = sentence.kind == 'jail'
            local center = jail and Config.Jail.center or Config.ComServ.center
            local radius = jail and Config.Jail.radius or Config.ComServ.radius
            if #(pos - center) > radius then
                local back = jail and (Spot(Points.spawns) or Config.Jail.spawns[1]) or center
                SetEntityCoords(ped, back.x, back.y, back.z, false, false, false, false)
                Notify(jail and 'You can\'t leave the prison.' or 'Stay at Legion Square until your community service is done.')
            end
            if GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then RemoveAllPedWeapons(ped, true) end
            local list = jail and Points.chores or Points.comserv
            for i, s in ipairs(list or {}) do
                local p = V3(s)
                local d = #(pos - p)
                if d < 30.0 then
                    DrawMarker(1, p.x, p.y, p.z - 0.98, 0, 0, 0, 0, 0, 0, 1.2, 1.2, 0.4, 255, 190, 60, 120, false, false, 2, false, nil, nil, false)
                    if d < 1.6 and not Busy then
                        Help('~INPUT_CONTEXT~ Sweep up')
                        if IsControlJustReleased(0, 38) then
                            Busy = true
                            TriggerCallback('choreStart')
                            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_JANITOR', 0, true)
                            local secs = jail and Config.Jail.choreSeconds or Config.ComServ.seconds
                            SendNUIMessage({ action = 'progress', label = 'Sweeping', ms = secs * 1000 })
                            Wait(secs * 1000)
                            SendNUIMessage({ action = 'progressEnd' })
                            ClearPedTasks(ped)
                            Busy = false
                            local res = TriggerCallback('chore', i)
                            if res and res.ok and not res.done then
                                Notify(jail and ('Chore done - %d seconds off.'):format(Config.Jail.choreReduces) or 'Task done.')
                            elseif res and not res.ok then Result(res) end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------------
-- MDT
---------------------------------------------------------------------------
function DoMDT()
    if Busy then return end
    if not tabletProp then
        tabletProp = AttachProp('tablet')
        PlayAnim('tablet', 49)
    end
    OpenPanel('mdt', {})
end

function StopTablet()
    if tabletProp then
        DeleteProp(tabletProp)
        tabletProp = nil
        StopAnim('tablet')
    end
end

local MDT_CALLS = { mdtSearch = true, mdtRecord = true, mdtWarrant = true, mdtWarrantClear = true, mdtNote = true, mdtWaive = true }
RegisterNUICallback('mdt', function(d, cb)
    if not MDT_CALLS[d.call] then return cb({ ok = false }) end
    CreateThread(function()
        local res = TriggerCallback(d.call, d.a, d.b, d.c)
        if res and not res.ok and res.msg then Notify(res.msg) end
        cb(res or { ok = false })
    end)
end)
