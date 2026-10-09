-- Statewide PD - dispatch context (time, weather, city / county) and wk_wars2x plate reader hits
local CTX = AI.Context or {}
local RAIN = { [GetHashKey('RAIN')] = true, [GetHashKey('THUNDER')] = true, [GetHashKey('CLEARING')] = true,
    [GetHashKey('SNOW')] = true, [GetHashKey('BLIZZARD')] = true, [GetHashKey('SNOWLIGHT')] = true, [GetHashKey('XMAS')] = true }

-- Tell dispatch what it's like where you are (so calls fit the time, weather and area)
CreateThread(function()
    local last
    while true do
        Wait(20000)
        if IsPolice and OnPatrol then
            local hour = GetClockHours()
            local w = GetPrevWeatherTypeHashName()
            local rain = RAIN[w] == true or GetRainLevel() > 0.2
            local city = MyPos().y < (CTX.CityLine or 1150.0)
            local key = hour .. tostring(rain) .. tostring(city)
            if key ~= last then
                last = key
                TriggerServerEvent(EV .. 'aiContext', hour, rain, city)
            end
        else
            last = nil
        end
    end
end)

---------------------------------------------------------------------------
-- wk_wars2x plate reader
---------------------------------------------------------------------------
local function FindVehicle(plate)
    local best, bd = nil, 120.0
    local me = MyPos()
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local p = tostring(GetVehicleNumberPlateText(veh) or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
        if p == plate then
            local d = #(GetEntityCoords(veh) - me)
            if d < bd then best, bd = veh, d end
        end
    end
    return best
end

RegisterNetEvent(EV .. 'alprHit', function(d)
    if not IsPolice or type(d) ~= 'table' then return end
    local text = table.concat(d.hits or {}, ' · ')
    Notify(('~r~ALPR HIT~s~ (%s camera) - ~y~%s~s~: %s'):format(d.cam == 'rear' and 'rear' or 'front', d.plate, text))
    if RadioLine then RadioLine(('ALPR: hit on %s - %s.'):format(d.plate, text)) end
    SendNUIMessage({ action = 'aiToast', kind = 'bad', title = 'ALPR hit - ' .. d.plate, text = text })
    local veh = FindVehicle(d.plate)
    if veh then
        local b = AddBlipForEntity(veh)
        SetBlipColour(b, 1)
        SetBlipFlashes(b, true)
        NamedBlip(b, 'ALPR hit ' .. d.plate)
        SetTimeout(45000, function() RemoveBlipSafe(b) end)
    end
end)

RegisterNetEvent(EV .. 'alprRun', function(d)
    if not IsPolice or type(d) ~= 'table' then return end
    if d.player then return Notify(('10-28 %s: registered to a local resident. Run them with F7 if you stop them.'):format(d.plate)) end
    local flags = (d.hits and #d.hits > 0) and ('~r~' .. table.concat(d.hits, ', ') .. '~s~') or '~g~no flags~s~'
    Notify(('10-28 %s: %s · reg %s · %s · %s'):format(d.plate, d.owner or '?', d.reg or '?', d.insurance or '?', flags))
    if RadioLine then RadioLine(('Dispatch: %s returns to %s, %s.'):format(d.plate, d.owner or 'unknown', (d.hits and #d.hits > 0) and table.concat(d.hits, ', ') or 'no wants')) end
end)
