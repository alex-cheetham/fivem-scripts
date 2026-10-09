-- The police menu (F7), panels and chat commands
local panelOpen = false

function OpenPanel(kind, data)
    panelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'panel', panel = kind, data = data })
end

function ClosePanel()
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePanel' })
    StopTablet()
end

RegisterNUICallback('close', function(_, cb) ClosePanel() cb('ok') end)
RegisterNUICallback('closeCiv', function(_, cb) SetNuiFocus(false, false) cb('ok') end)

local function MenuData()
    local people = {}
    for _, p in ipairs(PlayersNear(6.0)) do
        local st = Player(p.id).state
        people[#people + 1] = { id = p.id, name = p.name, dist = math.floor(p.dist * 10) / 10, cuffed = st.cuffed or false,
            escorted = st.escort == GetPlayerServerId(PlayerId()) }
    end
    local veh = VehicleAhead(6.0)
    local vinfo = nil
    if veh and veh ~= 0 then
        vinfo = { plate = GetVehicleNumberPlateText(veh), model = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh))) }
    end
    local props = {}
    for _, p in ipairs(Config.SceneProps) do props[#props + 1] = { key = p.key, label = p.label } end
    return { people = people, vehicle = vinfo, props = props, admin = IsAdmin }
end

function OpenMenu()
    if not IsPolice then return Notify('You need to be on duty with a police department (/onduty).') end
    if Busy then return end
    OpenPanel('menu', MenuData())
end
RegisterNetEvent(EV .. 'openMenu', OpenMenu)

RegisterNUICallback('refreshMenu', function(_, cb) cb(MenuData()) end)

RegisterCommand('+police_menu', function() if IsPolice then OpenMenu() end end, false)
RegisterCommand('-police_menu', function() end, false)
RegisterKeyMapping('+police_menu', 'Statewide PD: open the police menu', 'keyboard', Config.Keys.menu)

---------------------------------------------------------------------------
-- Actions (menu buttons and commands both use these)
---------------------------------------------------------------------------
local ACTIONS = {
    cuff = function(t) DoCuff(t) end,
    zip = function(t) DoCuff(t, 'zip') end,
    uncuff = function(t) DoUncuff(t) end,
    escort = function(t) DoEscort(t) end,
    seat = function(t) DoSeat(t) end,
    unseat = function(t) DoUnseat(t) end,
    frisk = function(t) DoTest('frisk', t) end,
    search = function(t) DoTest('search', t) end,
    checkid = function(t) DoCheckId(t) end,
    breath = function(t) DoTest('breath', t) end,
    drugtest = function(t) DoTest('drug', t) end,
    gsr = function(t) DoTest('gsr', t) end,
    dna = function(t) DoTest('dna', t) end,
    ticket = function(t) DoTicket(t) end,
    arrest = function(t) DoArrest(t) end,
    comserv = function(t) DoComserv(t) end,
    unjail = function(t)
        if not tonumber(t) then return Notify('Usage: /unjail <player id>') end
        Result(TriggerCallback('unjail', t))
    end,
    runplate = function(t) DoRunPlate(t) end,
    vehsearch = function() DoVehSearch() end,
    impound = function() DoImpound() end,
    dust = function() DoDust() end,
    radar = function() DoRadar() end,
    spikes = function() DoSpikes() end,
    evidence = function() DoEvidenceMode() end,
    mdt = function() DoMDT() end,
    badge = function() DoBadge() end,
    pickup = function() DoPickup() end,
    clearprops = function() Result(TriggerCallback('propClear')) end,
    place = function(t) DoPlace(t) end,
}

RegisterNUICallback('action', function(d, cb)
    cb('ok')
    local fn = ACTIONS[d.act]
    if not fn then return end
    if d.act ~= 'mdt' then ClosePanel() end
    CreateThread(function()
        Wait(100)
        fn(d.target)
    end)
end)

-- Chat commands: /cuff [id], /breath [id], /runplate [plate]...
for name, fn in pairs(ACTIONS) do
    if name ~= 'place' and name ~= 'pickup' and name ~= 'clearprops' and name ~= 'dust' then
        RegisterCommand(name, function(_, args)
            if not IsPolice then return Notify('You need to be on duty with a police department (/onduty).') end
            if name == 'runplate' then return fn(table.concat(args, ' ')) end
            fn(args[1])
        end, false)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and panelOpen then SetNuiFocus(false, false) end
end)
