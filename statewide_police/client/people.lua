-- Searches, ID and roadside tests (officer + the person being tested)
local TESTS = {
    frisk  = { label = 'Patting down',              anim = 'search',     props = {} },
    search = { label = 'Searching',                 anim = 'search',     props = {} },
    breath = { label = 'Breathalysing',             anim = 'holdDevice', props = { 'breath' } },
    drug   = { label = 'Drug swab - waiting for the result', anim = 'holdDevice', props = { 'swab' } },
    gsr    = { label = 'Swabbing hands for GSR',    anim = 'swabHands',  props = { 'gsr' } },
    dna    = { label = 'Taking a DNA swab',         anim = 'holdDevice', props = { 'swab' } },
}

function DoTest(kind, arg)
    if Busy then return end
    local def = TESTS[kind]
    local id, tped = NeedTarget(arg, 2.5)
    if not id then return end
    local start = TriggerCallback('testStart', id, kind)
    if not Result(start) then return end
    if tped then TaskTurnPedToFaceEntity(PlayerPedId(), tped, 400) Wait(400) end
    if not Action(def.label, start.time, def.anim, def.props) then return Notify('Cancelled.') end
    local res = TriggerCallback('testResult', kind)
    if not res or not res.ok then return Result(res) end
    if res.msg then Notify(res.msg) end
    OpenPanel('result', res)
end

-- The person being tested
RegisterNetEvent(EV .. 'testTarget', function(anim, ms)
    local ped = PlayerPedId()
    if AmCuffed() or IsPedInAnyVehicle(ped, false) then return end
    PlayAnim(anim, 49, ms)
    SetTimeout(ms, function() StopAnim(anim) end)
end)

-- Answers the server asks for
Answers.weapons = function()
    local ped = PlayerPedId()
    local list = {}
    for _, w in ipairs(Config.Weapons) do
        if HasPedGotWeapon(ped, GetHashKey(w), false) then list[#list + 1] = w end
    end
    return list
end

local consentP = nil
Answers.consent = function(data)
    if consentP then return false end   -- already answering someone else
    local p = promise.new()
    consentP = p
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'consent', officer = data.officer, seconds = Config.ConsentSeconds })
    SetTimeout(Config.ConsentSeconds * 1000, function() if consentP == p then consentP = nil p:resolve(false) end end)
    local yes = Citizen.Await(p)
    if consentP == p then consentP = nil end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'consentClose' })
    return yes == true
end
RegisterNUICallback('consent', function(d, cb)
    cb('ok')
    local p = consentP
    if p then consentP = nil p:resolve(d.yes == true) end
end)

RegisterNetEvent(EV .. 'removeWeapon', function(name)
    local ped = PlayerPedId()
    RemoveWeaponFromPed(ped, GetHashKey(name))
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
end)

-- Seizing from the search panel
RegisterNUICallback('seize', function(d, cb)
    cb('ok')
    CreateThread(function()
        local res = TriggerCallback('seize', d.target, d.what, d.name, d.count)
        if res and res.ok then SendNUIMessage({ action = 'panelUpdate', panel = 'result', data = res }) else Result(res) end
    end)
end)

---------------------------------------------------------------------------
-- ID
---------------------------------------------------------------------------
local function Mugshot(ped)
    if not ped or ped == 0 then return nil end
    local h = RegisterPedheadshot(ped)
    local t = GetGameTimer() + 2000
    while not IsPedheadshotReady(h) and GetGameTimer() < t do Wait(20) end
    if not IsPedheadshotReady(h) then UnregisterPedheadshot(h) return nil end
    local txd = GetPedheadshotTxdString(h)
    SetTimeout(30000, function() UnregisterPedheadshot(h) end)
    return txd
end

function DoCheckId(arg)
    if Busy then return end
    local id, ped = NeedTarget(arg, 4.0)
    if not id then return end
    local res = TriggerCallback('checkId', id)
    if not Result(res) then return end
    Action('Checking ID', 2500, 'tablet', { 'tablet' })
    res.photo = Mugshot(ped)
    OpenPanel('idcheck', res)
end

RegisterCommand('showid', function()
    if Busy or AmCuffed() then return end
    local id = NeedTarget(nil, 3.0)
    if not id then return end
    local res = TriggerCallback('showId', id)
    if Result(res) then
        local prop = AttachProp('idcard')
        PlayAnim('giveId', 0, 2000)
        Wait(2000)
        DeleteProp(prop)
    end
end, false)

RegisterNetEvent(EV .. 'idCard', function(card)
    local pid = GetPlayerFromServerId(card.from)
    card.photo = pid ~= -1 and Mugshot(GetPlayerPed(pid)) or nil
    SendNUIMessage({ action = 'idCard', data = card })
end)

function DoBadge()
    local res = TriggerCallback('badge')
    if not Result(res) then return end
    local prop = AttachProp('badge')
    PlayAnim('giveId', 0, 2500)
    Wait(2500)
    DeleteProp(prop)
end

RegisterNetEvent(EV .. 'badgeCard', function(card)
    SendNUIMessage({ action = 'badgeCard', data = card })
end)

---------------------------------------------------------------------------
-- Drunk effects (real drinks only)
---------------------------------------------------------------------------
local drunk = false
RegisterNetEvent(EV .. 'bac', function(bac)
    if not Config.DrunkEffects then return end
    local ped = PlayerPedId()
    local should = bac >= Config.DrinkLimit
    if should and not drunk then
        drunk = true
        RequestAnimSet('move_m@drunk@slightlydrunk')
        local t = GetGameTimer() + 3000
        while not HasAnimSetLoaded('move_m@drunk@slightlydrunk') and GetGameTimer() < t do Wait(10) end
        SetPedMovementClipset(ped, 'move_m@drunk@slightlydrunk', 1.0)
        ShakeGameplayCam('DRUNK_SHAKE', math.min(2.0, bac * 12))
        Notify('You\'re feeling the drink...')
    elseif not should and drunk then
        drunk = false
        ResetPedMovementClipset(ped, 1.0)
        StopGameplayCamShaking(true)
        Notify('You\'re sobering up.')
    elseif should then
        ShakeGameplayCam('DRUNK_SHAKE', math.min(2.0, bac * 12))
    end
end)
