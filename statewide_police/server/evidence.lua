-- Scene evidence (casings, blood), fingerprints on vehicles, the evidence locker and lab
local SHOPS = 'statewide_shops'
local Scene = {}          -- list of { id, type, x, y, z, ident, weapon, t }
local Prints = {}         -- [plate] = { { ident, t } } last drivers
local LastShot, LastBlood = {}, {}
local SceneId = 0
local NoCasing = {}
for _, w in ipairs(Config.NoCasingWeapons) do NoCasing[GetHashKey(w)] = true end

local WEAPON_CLASS = {}   -- hash -> readable name (filled from the searchable weapon list)
for _, w in ipairs(Config.Weapons) do WEAPON_CLASS[GetHashKey(w)] = w end

local function AddScene(kind, pos, ident, extra)
    SceneId = SceneId + 1
    local e = { id = SceneId, type = kind, x = pos.x, y = pos.y, z = pos.z, ident = ident, t = os.time() }
    for k, v in pairs(extra or {}) do e[k] = v end
    Scene[#Scene + 1] = e
    if #Scene > Config.MaxSceneEvidence then table.remove(Scene, 1) end
end

-- A player fired a gun
RegisterNetEvent(EV .. 'shot', function(weaponHash, x, y, z)
    local src = source
    weaponHash = tonumber(weaponHash)
    if not weaponHash or NoCasing[weaponHash] then return end
    local now = GetGameTimer()
    if now - (LastShot[src] or 0) < 1200 then return end
    LastShot[src] = now
    local pos = vector3(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
    if #(pos - Pos(src)) > 15.0 then return end
    local ident = Ident(src)
    Residue[ident] = os.time()
    AddScene('casing', pos, ident, { weapon = WEAPON_CLASS[weaponHash] or 'unknown', name = Name(src) })
end)

-- A player was hurt and is bleeding
RegisterNetEvent(EV .. 'blood', function(x, y, z)
    local src = source
    local now = GetGameTimer()
    if now - (LastBlood[src] or 0) < 8000 then return end
    LastBlood[src] = now
    local pos = vector3(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
    if #(pos - Pos(src)) > 10.0 then return end
    AddScene('blood', pos, Ident(src), { name = Name(src) })
end)

-- Washing / swimming clears gunshot residue
RegisterNetEvent(EV .. 'washed', function() Residue[Ident(source)] = nil end)

-- A player drove a vehicle (fingerprints)
RegisterNetEvent(EV .. 'drove', function(plate)
    local src = source
    plate = tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' then return end
    local ident = Ident(src)
    local list = Prints[plate] or {}
    for i = #list, 1, -1 do if list[i].ident == ident then table.remove(list, i) end end
    table.insert(list, 1, { ident = ident, name = Name(src), t = os.time() })
    while #list > 3 do table.remove(list) end
    Prints[plate] = list
end)

function LastDriverName(plate)
    local list = Prints[plate]
    return list and list[1] and list[1].name or nil
end

function RecentDriver(plate)
    local list = Prints[plate]
    return list and list[1] and os.time() - list[1].t < 1800 or false
end

-- Old evidence washes away
CreateThread(function()
    while true do
        Wait(60000)
        local cutoff = os.time() - Config.EvidenceMinutes * 60
        for i = #Scene, 1, -1 do if Scene[i].t < cutoff then table.remove(Scene, i) end end
    end
end)

---------------------------------------------------------------------------
-- Evidence mode: what's near an officer
---------------------------------------------------------------------------
PoliceCallback('sceneNearby', function(src)
    local pos = Pos(src)
    local out = {}
    for _, e in ipairs(Scene) do
        if #(vector3(e.x, e.y, e.z) - pos) <= Config.EvidenceRange then
            out[#out + 1] = { id = e.id, type = e.type, x = e.x, y = e.y, z = e.z, age = math.floor((os.time() - e.t) / 60) }
        end
    end
    return { ok = true, list = out }
end)

PoliceCallback('collect', function(src, id)
    id = tonumber(id)
    for i, e in ipairs(Scene) do
        if e.id == id then
            if #(vector3(e.x, e.y, e.z) - Pos(src)) > 3.0 then return Fail('Get closer.') end
            table.remove(Scene, i)
            local label = e.type == 'casing' and ('Bullet casing (%s)'):format(e.weapon and WeaponLabel(e.weapon) or 'unknown')
                or 'Blood sample'
            AddToLocker(src, { type = e.type, label = label, ident = e.ident, weapon = e.weapon, found = Stamp() })
            return { ok = true, msg = label .. ' bagged.' }
        end
    end
    return Fail('Someone already collected that.')
end)

PoliceCallback('dustPrints', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if veh == 0 or not DoesEntityExist(veh) then return Fail('No vehicle there.') end
    if #(GetEntityCoords(veh) - Pos(src)) > 5.0 then return Fail('Get closer to the vehicle.') end
    local plate = tostring(GetVehicleNumberPlateText(veh)):upper():gsub('^%s+', ''):gsub('%s+$', '')
    local found = 0
    for _, p in ipairs(Prints[plate] or {}) do
        if math.random() < 0.8 then   -- not every print lifts cleanly
            AddToLocker(src, { type = 'prints', label = ('Fingerprints - vehicle %s'):format(plate), ident = p.ident })
            found = found + 1
        end
    end
    if found == 0 then return { ok = true, msg = 'No usable prints on the vehicle.' } end
    return { ok = true, msg = ('Lifted %d set%s of prints.'):format(found, found == 1 and '' or 's') }
end)

---------------------------------------------------------------------------
-- Evidence locker (shared by all police) and the lab
---------------------------------------------------------------------------
function AddToLocker(src, e)
    e.id = NewCaseId('E')
    e.officer = OfficerLabel(src)
    e.date = Stamp()
    table.insert(Locker, 1, e)
    while #Locker > 500 do table.remove(Locker) end
    Dirty.locker = true
    return e
end

local function Public(e)
    return { id = e.id, type = e.type, label = e.label, from = e.from, officer = e.officer, date = e.date, result = e.result, analysed = e.analysed }
end

PoliceCallback('locker', function(src)
    local list = {}
    for i = 1, math.min(#Locker, 150) do list[#list + 1] = Public(Locker[i]) end
    return { ok = true, list = list, atLab = NearStation(src) ~= nil }
end)

local function OwnerOf(ident, weapon)
    if not Started(SHOPS) or not weapon then return nil end
    local ok, owns = pcall(function() return exports[SHOPS]:OwnsWeapon(ident, weapon) end)
    return ok and owns or false
end

PoliceCallback('analyse', function(src, id)
    if not NearStation(src) then return Fail('Take it to a station lab.') end
    for _, e in ipairs(Locker) do
        if e.id == id then
            local r = e.ident and Records[e.ident]
            if e.type == 'casing' then
                local owner = OwnerOf(e.ident, e.weapon)
                if owner then
                    e.result = ('Ballistics: %s. Matches a legally registered weapon owned by %s.'):format(e.weapon and WeaponLabel(e.weapon) or 'unknown weapon', r and r.name or 'a registered owner')
                else
                    e.result = ('Ballistics: %s. No match to any registered weapon.'):format(e.weapon and WeaponLabel(e.weapon) or 'unknown weapon')
                end
            elseif e.type == 'blood' then
                e.result = (r and r.dna) and ('DNA match: %s.'):format(r.name) or 'DNA profile not on file - analyse again once more people are swabbed.'
            elseif e.type == 'prints' then
                e.result = (r and r.prints) and ('Fingerprint match: %s.'):format(r.name) or 'Prints not on file - analyse again once more people are booked.'
            elseif e.type == 'dna' then
                e.result = ('Reference sample for %s - on file.'):format(e.from or 'unknown')
            else
                e.result = 'Logged as evidence.'
            end
            e.analysed = Stamp()
            Dirty.locker = true
            return { ok = true, item = Public(e) }
        end
    end
    return Fail('Not found.')
end)

AddEventHandler('playerDropped', function()
    LastShot[source], LastBlood[source] = nil, nil
end)
