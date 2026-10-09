-- Leaving evidence (everyone) and finding it (police)
local evidenceMode = false
local nearby = {}
local torch = nil

-- Firing a gun leaves a casing and gunshot residue
CreateThread(function()
    local last = 0
    while true do
        local ped = PlayerPedId()
        if IsPedShooting(ped) then
            local now = GetGameTimer()
            if now - last > 1200 then
                last = now
                local p = GetOffsetFromEntityInWorldCoords(ped, 0.4, 0.2, -0.95)
                TriggerServerEvent(EV .. 'shot', GetSelectedPedWeapon(ped), p.x, p.y, p.z)
            end
            Wait(0)
        else
            Wait(IsPedArmed(ped, 4) and 0 or 500)
        end
    end
end)

-- Getting hurt leaves blood, driving leaves prints, water washes residue off
CreateThread(function()
    local lastHealth = GetEntityHealth(PlayerPedId())
    local lastPlate, wasInWater = nil, false
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local hp = GetEntityHealth(ped)
        if hp < lastHealth - 10 and not IsPedInAnyVehicle(ped, false) then
            local c = GetEntityCoords(ped)
            TriggerServerEvent(EV .. 'blood', c.x, c.y, c.z - 0.95)
        end
        lastHealth = hp
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local plate = GetVehicleNumberPlateText(veh)
            if plate ~= lastPlate then lastPlate = plate TriggerServerEvent(EV .. 'drove', plate) end
        else
            lastPlate = nil
        end
        local inWater = IsEntityInWater(ped) and IsPedSwimming(ped)
        if inWater and not wasInWater then TriggerServerEvent(EV .. 'washed') end
        wasInWater = inWater
    end
end)

RegisterCommand('washhands', function()
    if Busy or AmCuffed() then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local water, _ = TestProbeAgainstWater(c.x, c.y, c.z + 1.0, c.x, c.y, c.z - 3.0)
    if not water and not IsEntityInWater(ped) then
        return Notify('You need to be at water (a lake, the sea or a pool) - or wash up somewhere and roleplay it.')
    end
    if Action('Washing your hands', 8000, 'kneel', {}) then
        TriggerServerEvent(EV .. 'washed')
        Notify('Hands washed.')
    end
end, false)

---------------------------------------------------------------------------
-- Evidence mode (police)
---------------------------------------------------------------------------
function DoEvidenceMode()
    evidenceMode = not evidenceMode
    if evidenceMode then
        torch = AttachProp('torch')
        Notify('Evidence mode on - casings and blood near you are marked. Press E to bag them.')
    else
        DeleteProp(torch)
        torch = nil
        nearby = {}
        Notify('Evidence mode off.')
    end
end

CreateThread(function()
    while true do
        if evidenceMode then
            if not IsPolice then DoEvidenceMode() end
            local res = TriggerCallback('sceneNearby')
            nearby = res and res.ok and res.list or {}
            Wait(2500)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 800
        if evidenceMode and #nearby > 0 then
            sleep = 0
            local pos = GetEntityCoords(PlayerPedId())
            local closest, cd = nil, 1.4
            for _, e in ipairs(nearby) do
                local p = vector3(e.x, e.y, e.z)
                local d = #(pos - p)
                local blood = e.type == 'blood'
                DrawMarker(blood and 23 or 27, p.x, p.y, p.z + 0.03, 0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35,
                    blood and 170 or 255, blood and 10 or 200, blood and 10 or 40, 180, false, false, 2, false, nil, nil, false)
                if d < 8.0 then
                    Text3D(vector3(p.x, p.y, p.z + 0.25), (blood and 'Blood' or 'Casing') .. (' ~c~(%d min)'):format(e.age), 0.28)
                end
                if d < cd then closest, cd = e, d end
            end
            if closest and not Busy then
                Help('~INPUT_CONTEXT~ Bag the ' .. (closest.type == 'blood' and 'blood sample' or 'casing'))
                if IsControlJustReleased(0, 38) then
                    local e = closest
                    if Action('Bagging evidence', 3500, 'kneel', { 'evidencebag' }) then
                        Result(TriggerCallback('collect', e.id))
                        for i, x in ipairs(nearby) do if x.id == e.id then table.remove(nearby, i) break end end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Locker & lab (from the MDT)
RegisterNUICallback('locker', function(_, cb)
    CreateThread(function() cb(TriggerCallback('locker') or { ok = false }) end)
end)
RegisterNUICallback('analyse', function(d, cb)
    CreateThread(function()
        local res = TriggerCallback('analyse', d.id)
        if res and not res.ok then Result(res) end
        cb(res or { ok = false })
    end)
end)
