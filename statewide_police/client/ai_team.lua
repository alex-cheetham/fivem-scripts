-- Statewide PD: working with real officers (backup requests you can answer with Y, a live route to them),
-- divisions, and staff saving the uniforms AI units wear.
local pendingBackup = nil   -- { id, from, label, street, code, pos, expires }
local responding = nil      -- { id, blip, from }

function BackupPending()
    return pendingBackup ~= nil and GetGameTimer() < pendingBackup.expires
end

RegisterNetEvent(EV .. 'aiBackupReq', function(r)
    if not IsPolice or type(r) ~= 'table' then return end
    r.expires = GetGameTimer() + (r.seconds or 30) * 1000
    pendingBackup = r
    local dist = r.pos and math.floor(#(vector3(r.pos.x, r.pos.y, r.pos.z) - MyPos())) or 0
    SendNUIMessage({ action = 'aiBackup', data = { id = r.id, from = r.from, label = r.label, street = r.street, code = r.code, dist = dist, seconds = r.seconds or 30 }, key = AI.Keys.accept })
    PlaySoundFrontend(-1, r.code == 3 and 'TIMER_STOP' or 'Text_Arrive_Tone', r.code == 3 and 'HUD_MINI_GAME_SOUNDSET' or 'Phone_SoundSet_Default', true)
    RadioLine(('Dispatch: %s requesting %s, code %d, %s.'):format(r.from, r.label:lower(), r.code or 2, r.street ~= '' and r.street or 'their location'))
    SetTimeout((r.seconds or 30) * 1000, function()
        if pendingBackup == r then pendingBackup = nil SendNUIMessage({ action = 'aiBackupGone' }) end
    end)
end)

local function StopResponding()
    if not responding then return end
    RemoveBlipSafe(responding.blip)
    responding = nil
end

function RespondBackup()
    local r = pendingBackup
    if not r then return end
    pendingBackup = nil
    SendNUIMessage({ action = 'aiBackupGone' })
    local res = TriggerCallback('backupRespond', r.id)
    if not Result(res) then return end
    StopResponding()
    local p = res.pos or r.pos
    local blip = AddBlipForCoord(p.x, p.y, p.z)
    SetBlipSprite(blip, 526)
    SetBlipColour(blip, 3)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 3)
    NamedBlip(blip, 'Assist ' .. (res.from or r.from))
    responding = { id = r.id, blip = blip, from = res.from or r.from }
    RadioLine(Callsign() .. ': show me responding to ' .. (res.from or r.from) .. '.', true)
    Notify('~b~Responding.~s~ Route set - it follows them if they move.')
end

-- Keep the route on the officer who asked, clear it once you're there
CreateThread(function()
    while true do
        Wait(3000)
        if responding then
            local r = TriggerCallback('backupWhere', responding.id)
            if not r or not r.ok or not r.pos then
                StopResponding()
            else
                local p = vector3(r.pos.x, r.pos.y, r.pos.z)
                if DoesBlipExist(responding.blip) then SetBlipCoords(responding.blip, p.x, p.y, p.z) end
                if #(p - MyPos()) < 40.0 then
                    RadioLine(Callsign() .. ': 10-23, on scene with ' .. responding.from .. '.', true)
                    StopResponding()
                end
            end
        end
    end
end)

RegisterNetEvent(EV .. 'aiBackupClear', function(id)
    if responding and responding.id == id then
        Notify('The officer has cancelled their backup request.')
        StopResponding()
    end
end)

RegisterNUICallback('aiBackupRespond', function(_, cb) cb('ok') CreateThread(RespondBackup) end)
RegisterCommand('respond', function() if BackupPending() then CreateThread(RespondBackup) else Notify('No backup request to respond to.') end end, false)

---------------------------------------------------------------------------
-- Uniform capture (staff): whatever you're wearing becomes a uniform for a unit
---------------------------------------------------------------------------
local MALE, FEMALE = GetHashKey('mp_m_freemode_01'), GetHashKey('mp_f_freemode_01')

function CaptureOutfit(label)
    local ped = Me()
    local model = GetEntityModel(ped)
    local name
    if model == MALE then name = 'mp_m_freemode_01'
    elseif model == FEMALE then name = 'mp_f_freemode_01'
    else name = 'h' .. tostring(model % 4294967296) end
    local comps, props = {}, {}
    for i = 0, 11 do comps[tostring(i)] = { GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i) } end
    for i = 0, 7 do props[tostring(i)] = { GetPedPropIndex(ped, i), math.max(0, GetPedPropTextureIndex(ped, i)) } end
    return { model = name, comps = comps, props = props, label = label or '' }
end

function UniformSummary()
    local all = GlobalState.swpdUniforms
    local out = {}
    for _, k in ipairs({ 'default', 'backup', 'swat', 'k9', 'transport', 'roadblock', 'spikes', 'partner', 'air' }) do
        local list = type(all) == 'table' and all[k] or nil
        out[#out + 1] = { slot = k, label = k == 'default' and 'All units (default)' or (AI.Units[k] and AI.Units[k].label or k), count = type(list) == 'table' and #list or 0 }
    end
    return out
end

-- Preview: spawn a unit ped wearing the slot's uniform next to you for 15 seconds
function PreviewUniform(slot)
    CreateThread(function()
        local pos = GetOffsetFromEntityInWorldCoords(Me(), 0.0, 2.0, 0.0)
        local all = GlobalState.swpdUniforms or {}
        local list = all[slot]
        local ped
        if type(list) == 'table' and #list > 0 and ApplyOutfit then
            local o = list[math.random(1, #list)]
            local m = tostring(o.model or '')
            if m:sub(1, 1) == 'h' and tonumber(m:sub(2)) then m = tonumber(m:sub(2)) end
            ped = SpawnPed(m, pos - vector3(0.0, 0.0, 0.9), GetEntityHeading(Me()) + 180.0)
            if ped then ApplyOutfit(ped, o) end
        else
            ped = SpawnUnitPed(slot == 'default' and 'backup' or slot, nil, nil, pos - vector3(0.0, 0.0, 0.9), GetEntityHeading(Me()) + 180.0)
        end
        if not ped then return end
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_COP_IDLES', 0, true)
        Wait(15000)
        Vanish(ped)
    end)
end
