-- AI patrol: the interaction panel, the patrol computer and the keys/commands that open them
PanelEntry = nil
PanelRemote = false
local pcOpen = false

local function Restrained(e) return e.status == 'cuffed' or e.status == 'escorted' or e.status == 'seated' end

local function PanelData(e)
    local ped = e.ped
    local inVeh = IsPedInAnyVehicle(ped, false)
    local veh = inVeh and GetVehiclePedIsIn(ped, false) or e.veh
    local hasVeh = veh ~= nil and veh ~= 0 and DoesEntityExist(veh)
    if inVeh and not e.veh then e.veh = veh end
    local station = NearStationClient()
    local transport = TransportReady and TransportReady(e) ~= nil or false
    local r = Restrained(e)
    return {
        pid = e.pid, label = Label(e), role = e.role or 'ped', status = e.status, mood = e.persona and e.persona.mood or 'calm',
        known = e.persona and e.persona.name ~= nil, log = e.log or {}, result = e.result,
        inVeh = inVeh, hasVeh = hasVeh, plate = hasVeh and GetVehicleNumberPlateText(veh) or nil,
        isDriver = inVeh and GetPedInVehicleSeat(veh, -1) == ped,
        restrained = r, escorted = e.status == 'escorted', seated = e.status == 'seated', following = e.status == 'following',
        surrendered = e.status == 'surrendered', noId = e.noId == true, pc = e.pc == true,
        canBook = r and (station ~= nil or Config.BookAnywhere or transport), transport = transport,
        station = station and station.label or nil,
        story = e.role == 'victim' or e.role == 'witness' or e.callout ~= nil,
        trespass = e.persona and e.persona.profile == 'trespass',
        injured = e.injured == true,
        tone = e.tone or 'calm', remote = PanelRemote, tab = e.tab,
        stress = e.persona and e.persona.stress or 0, rapport = e.persona and e.persona.rapport or 0,
        lies = e.persona and e.persona.lies or {}, confessed = e.persona and e.persona.confessed or {},
        asked = e.persona and e.persona.asked or {}, warrant = e.persona and e.persona.warrant or false,
        hostage = e.persona and e.persona.hostage or false, nego = e.persona and e.persona.nego or nil,
        sfst = e.persona and e.persona.sfst or nil, k9 = e.persona and e.persona.k9 or nil,
        matches = e.persona and e.persona.matches or false, felony = e.felony == true,
        partner = PartnerPed and PartnerPed() ~= nil and not IsPedDeadOrDying(PartnerPed(), true) or false,
        partnerDog = PartnerIsDog and PartnerIsDog() or false,
        fear = e.persona and e.persona.fear or 0, anger = e.persona and e.persona.anger or 0, cues = e.persona and e.persona.cues or {},
        lang = e.persona and e.persona.lang or nil, interpreter = e.persona and e.persona.interpreter or false,
        child = e.persona and e.persona.child or nil, childCared = e.persona and e.persona.childCared or false,
        interfere = (e.persona and e.persona.interfere and e.role == 'passenger') or false, interfering = e.interfering == true,
        crisis = e.persona and e.persona.crisis or false, voluntary = e.persona and e.persona.voluntary or false,
        clinician = e.persona and e.persona.clinician or false, filmed = e.persona and e.persona.filmed or false,
        supervision = e.persona and e.persona.supervision or nil, history = e.persona and e.persona.history or nil,
        knowsYou = e.persona and e.persona.knowsYou or nil,
        occupants = (function()
            if not hasVeh or not FelonyOccupants then return {} end
            local out = {}
            for _, o in ipairs(FelonyOccupants(veh)) do
                out[#out + 1] = { pid = o.pid, label = Label(o), seat = o.seat or -1, inVeh = IsPedInAnyVehicle(o.ped, false), status = o.status }
            end
            return out
        end)(),
    }
end

function OpenPanelAI(e, remote)
    if not e or not DoesEntityExist(e.ped) then return end
    if pcOpen then ClosePCUI() end
    PanelRemote = remote == true
    PanelEntry = e
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'aiPanel', data = PanelData(e) })
end

function PanelRefresh()
    local e = PanelEntry
    if not e then return end
    if not DoesEntityExist(e.ped) or AIPeds[e.ped] ~= e then return ClosePanelAI() end
    SendNUIMessage({ action = 'aiPanel', data = PanelData(e), update = true })
end

function ClosePanelAI()
    if not PanelEntry then return end
    PanelEntry = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'aiPanelClose' })
end

RegisterNUICallback('aiClose', function(_, cb)
    PanelEntry = nil
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('aiAct', function(d, cb)
    cb('ok')
    local e = PanelEntry
    if not e or type(d) ~= 'table' then return end
    local fn = ACTIONS_AI[d.act]
    if not fn then return end
    CreateThread(function()
        if Busy then return end
        if not DoesEntityExist(e.ped) then return ClosePanelAI() end
        fn(e, d)
        if PanelEntry == e then PanelRefresh() end
    end)
end)

-- Panel closes itself if you walk away
CreateThread(function()
    while true do
        Wait(500)
        local e = PanelEntry
        if e and (not DoesEntityExist(e.ped) or Dist(e.ped, Me()) > (PanelRemote and 45.0 or 12.0)) then ClosePanelAI() end
    end
end)

---------------------------------------------------------------------------
-- Patrol computer
---------------------------------------------------------------------------
local function PcData(state)
    state = state or TriggerCallback('patrolState')
    if not state or not state.ok then return nil end
    OnPatrol = state.on
    if SetDivision then SetDivision(state.division) end
    return {
        on = state.on, busy = state.busy, nextIn = state.nextIn, shift = state.shift or {}, total = state.total or {},
        log = state.log or {}, callout = CalloutInfo and CalloutInfo() or nil, units = UnitList and UnitList() or {},
        unitsCfg = (function()
            local out = {}
            for _, k in ipairs({ 'backup', 'swat', 'k9', 'partner', 'transport', 'roadblock', 'spikes', 'air', 'ems', 'tow', 'coroner', 'crisis', 'cps' }) do
                if AI.Units[k] then out[#out + 1] = { kind = k, label = AI.Units[k].label } end
            end
            return out
        end)(),
        street = Street(MyPos()), keys = AI.Keys, callouts = #AI.Callouts,
        rank = state.rank, paused = state.paused, callsign = Callsign(), radio = RadioLog and RadioLog() or {},
        cases = (TriggerCallback('caseList') or {}).cases or {},
        reports = (TriggerCallback('aiReports') or {}).reports or {},
        ia = (function() local r = TriggerCallback('iaList') return (r and r.ok) and r or { mine = {} } end)(),
        places = (function() local r = TriggerCallback('placeList') return (r and r.ok and r.admin) and r or nil end)(),
        brand = AI.Brand, brandLong = AI.BrandLong,
        division = state.division or 'patrol', admin = state.admin == true,
        divisions = (function() local o = {} for _, d in ipairs(AI.Divisions or {}) do o[#o + 1] = { key = d.key, label = d.label } end return o end)(),
        uniforms = UniformSummary and UniformSummary() or {},
        partner = PartnerInfo and PartnerInfo() or nil, partnerDog = PartnerIsDog and PartnerIsDog() or false,
        pursuit = PursuitInfo and PursuitInfo() or nil,
    }
end

function OpenPC()
    if not IsPolice then return Notify('You need to be on duty with a police department (/onduty).') end
    if PanelEntry or Busy then return end
    local data = PcData()
    if not data then return Notify('The patrol computer isn\'t responding.') end
    pcOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'pcOpen', data = data })
    if not IsPedInAnyVehicle(Me(), false) then
        PlayAnim('tablet', 49)
        PcProp = AttachProp('tablet')
    end
end

function PcRefresh(state)
    if not pcOpen then return end
    local data = PcData(state and state.ok and state or nil)
    if data then SendNUIMessage({ action = 'pcOpen', data = data, update = true }) end
end

function ClosePCUI() ClosePC() end
function ClosePC()
    pcOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'pcClose' })
    if PcProp then DeleteProp(PcProp) PcProp = nil StopAnim('tablet') end
end

RegisterNUICallback('pcClose', function(_, cb)
    pcOpen = false
    SetNuiFocus(false, false)
    if PcProp then DeleteProp(PcProp) PcProp = nil StopAnim('tablet') end
    cb('ok')
end)

RegisterNUICallback('pcAct', function(d, cb)
    if type(d) ~= 'table' then return cb({}) end
    local act = d.act
    if act == 'board' then
        CreateThread(function() cb(TriggerCallback('aiBoard') or {}) end)
        return
    end
    if act == 'cad' then
        CreateThread(function() cb(TriggerCallback('cadBoard') or {}) end)
        return
    end
    if act == 'cadTake' then
        CreateThread(function()
            if CurrentCallout then cb({ ok = false, msg = 'Finish your current call first (Code 4).' }) return end
            local r = TriggerCallback('cadTake', d.id)
            cb(r or {})
            if r and r.ok and r.callout then
                ClosePC()
                OnPatrol = true
                RadioLine(Callsign() .. ': show me assigned to ' .. (r.callout.incident or r.callout.title) .. '.', true)
                RunCallout(r.callout)
            else
                Result(r)
            end
        end)
        return
    end
    cb('ok')
    CreateThread(function()
        if act == 'toggle' then
            local r = TriggerCallback('patrolToggle', not OnPatrol)
            if r and r.ok then
                OnPatrol = r.on
                Notify(OnPatrol and '~g~Statewide PD - AI patrol on.~s~ Dispatch will send you callouts. Pull cars over with ' .. AI.Keys.stop .. ', hold ' .. AI.Keys.interact .. ' to stop people on foot.'
                    or 'AI patrol off. You won\'t get any more callouts.')
                if AIHud then AIHud() end
            end
            PcRefresh(r)
        elseif act == 'accept' then
            if AcceptOffer then AcceptOffer() end
            PcRefresh()
        elseif act == 'decline' then
            if DeclineOffer then DeclineOffer() end
        elseif act == 'code4' then
            if EndCallout then EndCallout(true) end
            Wait(300)
            PcRefresh()
        elseif act == 'route' then
            if CalloutRoute then CalloutRoute() end
            Notify('Route set.')
        elseif act == 'unit' then
            ClosePC()
            RequestUnit(d.kind, {})
        elseif act == 'dismiss' then
            local n = DismissUnits and DismissUnits(d.kind) or 0
            Notify(n > 0 and 'Units dismissed - thanks for the help.' or 'No units to dismiss.')
            PcRefresh()
        elseif act == 'mdt' then
            ClosePC()
            DoMDT()
        elseif act == 'runplate' then
            ClosePC()
            DoRunPlate()
        elseif act == 'bolo' then
            local r = TriggerCallback('caseBolo', d.id)
            if Result(r) then StartHunt(r, d.id) end
            PcRefresh()
        elseif act == 'warrant' then
            local r = TriggerCallback('caseWarrant', d.id)
            Result(r)
            if r and r.ok then RadioLine(Callsign() .. ': requesting an arrest warrant for case ' .. d.id .. '.', true) end
            PcRefresh()
        elseif act == 'serve' then
            local r = TriggerCallback('caseServe', d.id)
            if Result(r) then ClosePC() StartWarrant(r, d.id) end
        elseif act == 'report' then
            local r = TriggerCallback('aiReportSubmit', d.case, d.text)
            Result(r)
            PcRefresh()
        elseif act == 'pause' then
            local r = TriggerCallback('patrolPause', d.on == true)
            if r and r.ok then RadioLine(Callsign() .. (d.on and ': 10-6, busy - hold my calls.' or ': 10-8, back in service.'), true) end
            PcRefresh(r)
        elseif act == 'division' then
            local r = TriggerCallback('aiDivision', d.key)
            if Result(r) then
                if SetDivision then SetDivision(r.division) end
                -- swap partner type if needed
                if PartnerInfo and PartnerInfo() and ((r.division == 'k9') ~= PartnerIsDog()) then DismissPartner() end
                Notify('Division: ' .. (d.label or d.key) .. '. You\'ll get more of the callouts that suit it.')
            end
            PcRefresh(r)
        elseif act == 'uniformSave' then
            local r = TriggerCallback('aiUniformSet', d.slot, CaptureOutfit(d.label))
            if Result(r) then Notify(('Uniform saved for %s (%d saved - units pick one at random).'):format(d.slot, r.count or 1)) end
            Wait(300)
            PcRefresh()
        elseif act == 'uniformReset' then
            local r = TriggerCallback('aiUniformReset', d.slot)
            if Result(r) then Notify('Uniforms cleared for ' .. d.slot .. '.') end
            Wait(300)
            PcRefresh()
        elseif act == 'uniformPreview' then
            ClosePC()
            if PreviewUniform then PreviewUniform(d.slot) end
        elseif act == 'partnerCmd' then
            ClosePC()
            if PartnerOrder then PartnerOrder(nil, { cmd = d.cmd }) end
        elseif act == 'placeAdd' then
            local r = TriggerCallback('placeAdd', d.kind, d.label)
            Result(r)
            PcRefresh()
        elseif act == 'placeRemove' then
            local r = TriggerCallback('placeRemove', d.id)
            Result(r)
            PcRefresh()
        elseif act == 'iaRespond' then
            local r = TriggerCallback('iaRespond', d.id, d.text)
            Result(r)
            PcRefresh()
        elseif act == 'iaDecide' then
            local r = TriggerCallback('iaDecide', d.id, d.outcome)
            if Result(r) then Notify('Decision recorded - it\'ll be applied in a moment.') end
            PcRefresh()
        elseif act == 'terminate' then
            if TerminatePursuit then TerminatePursuit() end
            PcRefresh()
        elseif act == 'status' then
            local lines = { ['10-8'] = ': 10-8, in service.', ['10-7'] = ': 10-7, out of service.', ['10-23'] = ': 10-23, arrived on scene.',
                ['10-97'] = ': 10-97, en route.', ['code4'] = ': Code 4, no further assistance needed.', ['10-15'] = ': 10-15, prisoner in custody.' }
            if lines[d.code] then RadioLine(Callsign() .. lines[d.code]) end
            SetTimeout(1500, function() RadioLine('Dispatch: copy, ' .. Callsign() .. '.') end)
            PcRefresh()
        end
    end)
end)

RegisterCommand('+swai_computer', function() if IsPolice then CreateThread(OpenPC) end end, false)
RegisterCommand('-swai_computer', function() end, false)
RegisterKeyMapping('+swai_computer', 'Statewide PD: open the patrol computer', 'keyboard', AI.Keys.computer)

RegisterCommand('patrol', function() CreateThread(OpenPC) end, false)
local QUICK = { callbackup = 'backup', calltransport = 'transport', calltow = 'tow', callems = 'ems', callcoroner = 'coroner', callair = 'air',
    callswat = 'swat', callspikes = 'spikes', callroadblock = 'roadblock', callk9 = 'k9', callpartner = 'partner' }
for cmd, k in pairs(QUICK) do
    RegisterCommand(cmd, function()
        if not IsPolice then return Notify('You need to be on duty.') end
        RequestUnit(k, {})
    end, false)
end
RegisterCommand('dismissunits', function() if IsPolice then Notify(DismissUnits() > 0 and 'Units dismissed.' or 'No units to dismiss.') end end, false)

-- Status chip refresh + switching duty off
CreateThread(function()
    Wait(5000)
    while true do
        if AIHud then AIHud() end
        Wait(10000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if PanelEntry or pcOpen then SetNuiFocus(false, false) end
end)

-- Promotions, court results, report reminders
RegisterNetEvent(EV .. 'aiPromoted', function(rank)
    SendNUIMessage({ action = 'aiToast', kind = 'rank', title = 'Promoted!', text = 'You are now ' .. rank .. '.' })
    PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
    RadioLine(('Dispatch: congratulations %s on your promotion to %s.'):format(Callsign(), rank))
end)

RegisterNetEvent(EV .. 'aiCourt', function(d)
    local text = ('%s: %d guilty, %d dismissed.'):format(d.name, d.guilty, d.dismissed)
    if d.bail then text = text .. ' ' .. d.bail .. '.' end
    if d.violation then text = text .. ' ' .. d.violation .. '.' end
    SendNUIMessage({ action = 'aiToast', kind = d.guilty > 0 and 'good' or 'bad', title = 'Court verdict - ' .. d.case, text = text, verdicts = d.verdicts })
    RadioLine('Dispatch: court result for ' .. d.case .. ' - ' .. text)
    PcRefresh()
end)

function ReportReminder(case)
    SetTimeout(4000, function()
        Notify(('~b~Arrest report %s~s~ is waiting in the patrol computer (Reports). A good report wins cases in court.'):format(case))
    end)
end
