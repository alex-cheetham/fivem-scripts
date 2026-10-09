-- Statewide PD: radio chatter, evidence lying in the world (thrown away / case clues), spotlights on stops
local Drops = {}      -- [id] = { obj, label, pos }
local Clues = {}      -- list of { caseId, index, obj, label, pos, done }
local radioLog = {}

---------------------------------------------------------------------------
-- Radio
---------------------------------------------------------------------------
function Callsign()
    local st = LocalPlayer.state.duty
    if type(st) == 'table' and st.unit and st.unit ~= '' then return tostring(st.unit) end
    return AI.DefaultCallsign or '1-ADAM-12'
end

function RadioLine(text, quiet)
    radioLog[#radioLog + 1] = { t = GetClockHours() .. ':' .. ('%02d'):format(GetClockMinutes()), text = text }
    while #radioLog > 40 do table.remove(radioLog, 1) end
    SendNUIMessage({ action = 'aiRadio', text = text })
    if not quiet then PlaySoundFrontend(-1, 'Start_Squelch', 'CB_RADIO_SFX', true) end
end
function RadioLog() return radioLog end

RegisterNetEvent(EV .. 'aiRadio', function(text) RadioLine(text) end)

function Heading(ent)
    local h = GetEntityHeading(ent)
    local dirs = { 'northbound', 'northwest', 'westbound', 'southwest', 'southbound', 'southeast', 'eastbound', 'northeast' }
    return dirs[(math.floor((h + 22.5) / 45) % 8) + 1]
end

---------------------------------------------------------------------------
-- Evidence on the ground
---------------------------------------------------------------------------
local function PlaceObj(model, pos)
    local hash = LoadModel(model) or LoadModel('prop_cs_package_01')
    if not hash then return nil end
    local ok, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    local obj = CreateObject(hash, pos.x, pos.y, (ok and gz or pos.z - 0.9) + 0.02, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    return obj
end

function DropEvidence(id, label, weapon, pos)
    local obj = PlaceObj(weapon and 'w_pi_pistol' or PickOne({ 'prop_meth_bag_01', 'prop_weed_bottle', 'prop_cs_package_01' }), pos)
    Drops[id] = { obj = obj, label = label, pos = pos, t = GetGameTimer() }
    Notify('~y~They threw something away!~s~ Find it and bag it (~INPUT_CONTEXT~).')
end

-- Closest thrown-away evidence or case clue (for the K9 article search)
function NearestDrop(from, range)
    local best, bd = nil, range or 80.0
    for _, d in pairs(Drops) do
        local dd = #(from - d.pos)
        if dd < bd then best, bd = d.pos, dd end
    end
    for _, c in ipairs(Clues) do
        if not c.done then
            local dd = #(from - c.pos)
            if dd < bd then best, bd = c.pos, dd end
        end
    end
    return best
end

function AddClue(caseId, index, model, label, pos)
    local obj = PlaceObj(model, pos)
    Clues[#Clues + 1] = { caseId = caseId, index = index, obj = obj, label = label, pos = pos }
end

function ClearClues(caseId)
    for i = #Clues, 1, -1 do
        local c = Clues[i]
        if not caseId or c.caseId == caseId then
            if c.obj and DoesEntityExist(c.obj) then DeleteEntity(c.obj) end
            table.remove(Clues, i)
        end
    end
end

-- Pressing E next to evidence. Returns true if it handled the key.
if type(WorldHooks) ~= 'table' then WorldHooks = {} end
function WorldInteract()
    for _, fn in ipairs(WorldHooks) do if fn() then return true end end
    local pos = MyPos()
    for id, d in pairs(Drops) do
        if #(pos - d.pos) < 2.5 then
            CreateThread(function()
                if not Action('Bagging evidence', 3500, 'kneel', { 'evidencebag' }, 1) then return end
                local r = TriggerCallback('aiPickup', id)
                local ok = Result(r)
                if ok or (r and r.msg and not r.msg:find('closer') and not r.msg:find('Slow')) then
                    if d.obj and DoesEntityExist(d.obj) then DeleteEntity(d.obj) end
                    Drops[id] = nil
                end
            end)
            return true
        end
    end
    for i, c in ipairs(Clues) do
        if not c.done and #(pos - c.pos) < 2.5 then
            CreateThread(function()
                if not Action('Examining ' .. c.label:lower(), 4000, 'kneel', { 'evidencebag' }, 1) then return end
                local r = TriggerCallback('caseClue', c.caseId, c.index)
                if not Result(r) then return end
                c.done = true
                if c.obj and DoesEntityExist(c.obj) then DeleteEntity(c.obj) end
                Notify('~b~Evidence:~s~ ' .. (r.text or c.label))
                RadioLine(Callsign() .. ': evidence recovered - ' .. c.label:lower() .. '.', true)
                if CaseUpdated then CaseUpdated(r.view) end
            end)
            return true
        end
    end
    return false
end

-- Labels over evidence
CreateThread(function()
    while true do
        local wait = 1000
        local pos = MyPos()
        for _, d in pairs(Drops) do
            local dist = #(pos - d.pos)
            if dist < 25.0 then
                wait = 0
                DrawMarker(0, d.pos.x, d.pos.y, d.pos.z + 0.2, 0, 0, 0, 0, 0, 0, 0.2, 0.2, 0.2, 245, 158, 11, 160, true, true, 2, false, nil, nil, false)
                if dist < 6.0 then Text3D(d.pos + vector3(0.0, 0.0, 0.1), '~y~[E]~s~ Bag evidence') end
            end
        end
        for _, c in ipairs(Clues) do
            if not c.done then
                local dist = #(pos - c.pos)
                if dist < 30.0 then
                    wait = 0
                    DrawMarker(0, c.pos.x, c.pos.y, c.pos.z + 0.2, 0, 0, 0, 0, 0, 0, 0.22, 0.22, 0.22, 59, 130, 246, 170, true, true, 2, false, nil, nil, false)
                    if dist < 7.0 then Text3D(c.pos + vector3(0.0, 0.0, 0.1), '~b~[E]~s~ ' .. c.label) end
                end
            end
        end
        Wait(wait)
    end
end)

-- Old dropped evidence disappears
CreateThread(function()
    while true do
        Wait(30000)
        for id, d in pairs(Drops) do
            if GetGameTimer() - d.t > 1500000 then
                if d.obj and DoesEntityExist(d.obj) then DeleteEntity(d.obj) end
                Drops[id] = nil
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Spotlight on the vehicle you've stopped (at night)
---------------------------------------------------------------------------
local function Night() local h = GetClockHours() return h >= 20 or h < 6 end

CreateThread(function()
    while true do
        local wait = 1000
        if Night() then
            local me = Me()
            local myCar = GetVehiclePedIsIn(me, true)
            if myCar ~= 0 and GetVehicleClass(myCar) == 18 then
                local target
                for _, e in pairs(AIPeds) do
                    if e.veh and DoesEntityExist(e.veh) and e.role == 'driver' and (e.status == 'held' or e.status == 'pulling') then target = e.veh break end
                end
                if target and #(GetEntityCoords(target) - GetEntityCoords(myCar)) < 40.0 then
                    wait = 0
                    local from = GetOffsetFromEntityInWorldCoords(myCar, -0.9, 1.2, 0.9)
                    local to = GetEntityCoords(target)
                    local dir = to - from
                    local len = #dir
                    dir = dir / len
                    DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, 255, 255, 240, len + 15.0, 30.0, 0.0, 8.0, 20.0)
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, d in pairs(Drops) do if d.obj and DoesEntityExist(d.obj) then DeleteEntity(d.obj) end end
    ClearClues()
end)
