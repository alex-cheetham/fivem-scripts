-- Plates, vehicle searches, impound, spike strips, cones & barriers
local LICENCE = 'statewide_drivingschool'
local Spikes = {}      -- [netId] = { owner, x, y, z, h, placed }
local Scene = {}       -- [netId] = { owner, key, n }
local VehSearch = {}   -- [officer] = { netId, started }

local function CleanPlate(p) return tostring(p or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 8) end
local function Pick(list) return list[math.random(1, #list)] end

local function Driver(veh)
    local ped = GetPedInVehicleSeat(veh, -1)
    if ped ~= 0 and IsPedAPlayer(ped) then return NetworkGetEntityOwner(ped) end
    return nil
end

local function Company(plate)
    local compact = plate:gsub('%s', '')
    for prefix, name in pairs(Config.CompanyPlates) do
        if compact:sub(1, #prefix) == prefix then return name end
    end
    return nil
end

local function Generated(plate)
    local r = Plates[plate]
    if r then return r end
    local roll = math.random()
    r = {
        owner = Pick(Config.FirstNames) .. ' ' .. Pick(Config.LastNames),
        reg = roll < 0.85 and 'Valid' or (roll < 0.95 and 'Expired' or 'Not registered'),
        insurance = math.random() < 0.88 and 'Insured' or 'No insurance',
        stolen = math.random() < 0.03,
        ownerWarrant = math.random() < 0.04,
        impounds = 0,
    }
    local found = {}
    for _, c in ipairs(Config.VehicleContraband) do
        if math.random() < c.chance then found[#found + 1] = { label = c.label, seized = false } end
    end
    r.contraband = found
    Plates[plate] = r
    Dirty.plates = true
    return r
end

GeneratePlate = Generated   -- the AI patrol uses the same registrations

PoliceCallback('runPlate', function(src, plate, netId, model)
    plate = CleanPlate(plate)
    local veh = netId and NetworkGetEntityFromNetworkId(tonumber(netId) or 0) or 0
    if veh ~= 0 and DoesEntityExist(veh) then plate = CleanPlate(GetVehicleNumberPlateText(veh)) end
    if plate == '' then return Fail('No plate.') end
    local out = { ok = true, plate = plate, model = model, flags = {} }
    local company = Company(plate)
    local driver = veh ~= 0 and DoesEntityExist(veh) and Driver(veh) or nil
    local rec = Plates[plate]
    if company then
        out.owner, out.reg, out.insurance = company, 'Valid (fleet)', 'Fleet insured'
    elseif (driver or RecentDriver(plate)) and not rec then
        -- a player's car: registered to whoever drives it
        if not driver then
            out.owner, out.reg, out.insurance = LastDriverName(plate) or 'Private owner', 'Valid', 'Insured'
            return out
        end
        out.owner, out.reg, out.insurance = Name(driver), 'Valid', 'Insured'
        local sum = RecordSummary(Ident(driver))
        if #sum.warrants > 0 then out.flags[#out.flags + 1] = ('Owner has %d active warrant(s)'):format(#sum.warrants) end
        if sum.unpaid > 0 then out.flags[#out.flags + 1] = ('Owner has %d unpaid fine(s) - %s'):format(sum.unpaid, Money(sum.owed)) end
        if Started(LICENCE) then
            local ok, has = pcall(function() return exports[LICENCE]:HasLicence(driver, 'car') end)
            if ok and not has then out.flags[#out.flags + 1] = 'Owner has no driving licence' end
        end
    else
        rec = Generated(plate)
        out.owner, out.reg, out.insurance = rec.owner, rec.reg, rec.insurance
        if rec.stolen then out.flags[#out.flags + 1] = 'REPORTED STOLEN' end
        if rec.ownerWarrant then out.flags[#out.flags + 1] = 'Registered owner has an active warrant' end
        if rec.reg ~= 'Valid' then out.flags[#out.flags + 1] = 'Registration: ' .. rec.reg end
        if rec.insurance ~= 'Insured' then out.flags[#out.flags + 1] = 'No insurance on record' end
        if (rec.impounds or 0) > 0 then out.flags[#out.flags + 1] = ('Impounded %d time(s) before'):format(rec.impounds) end
    end
    return out
end)

PoliceCallback('vehSearchStart', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if veh == 0 or not DoesEntityExist(veh) then return Fail('No vehicle there.') end
    if #(GetEntityCoords(veh) - Pos(src)) > 5.0 then return Fail('Get closer to the vehicle.') end
    VehSearch[src] = { netId = netId, started = GetGameTimer() }
    return { ok = true, time = 8000 }
end)

local function VehResult(plate, veh)
    local out = { ok = true, kind = 'vehicle', plate = plate, found = {} }
    -- player cars: nothing is kept in them, so search the people instead
    if (Driver(veh) or RecentDriver(plate)) and not Plates[plate] then
        out.note = 'Nothing unusual in the vehicle. Search the occupants.'
        return out
    end
    local rec = Generated(plate)
    for i, c in ipairs(rec.contraband or {}) do
        if not c.seized then out.found[#out.found + 1] = { index = i, label = c.label } end
    end
    if #out.found == 0 then out.note = 'Nothing unusual found.' end
    return out
end

PoliceCallback('vehSearchResult', function(src)
    local s = VehSearch[src]
    if not s or GetGameTimer() - s.started < 6500 then return Fail('Start again.') end
    local veh = NetworkGetEntityFromNetworkId(tonumber(s.netId) or 0)
    if veh == 0 or not DoesEntityExist(veh) then return Fail('The vehicle has gone.') end
    s.until_ = os.time() + 90
    return VehResult(CleanPlate(GetVehicleNumberPlateText(veh)), veh)
end)

PoliceCallback('vehSeize', function(src, index)
    local s = VehSearch[src]
    if not s or os.time() > (s.until_ or 0) then return Fail('Search it again first.') end
    local veh = NetworkGetEntityFromNetworkId(tonumber(s.netId) or 0)
    if veh == 0 or not DoesEntityExist(veh) then return Fail() end
    local plate = CleanPlate(GetVehicleNumberPlateText(veh))
    local rec = Plates[plate]
    local c = rec and rec.contraband and rec.contraband[tonumber(index) or 0]
    if not c or c.seized then return Fail() end
    c.seized = true
    Dirty.plates = true
    AddToLocker(src, { type = 'vehicle', label = c.label, from = 'Vehicle ' .. plate })
    return VehResult(plate, veh)
end)

PoliceCallback('impound', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if veh == 0 or not DoesEntityExist(veh) then return Fail('No vehicle there.') end
    if #(GetEntityCoords(veh) - Pos(src)) > 7.0 then return Fail('Get closer to the vehicle.') end
    for seat = -1, 6 do
        if GetPedInVehicleSeat(veh, seat) ~= 0 then return Fail('The vehicle needs to be empty.') end
    end
    local plate = CleanPlate(GetVehicleNumberPlateText(veh))
    if not Company(plate) then
        local rec = Plates[plate] or Generated(plate)
        rec.impounds = (rec.impounds or 0) + 1
        Dirty.plates = true
    end
    DeleteEntity(veh)
    return { ok = true, msg = ('Vehicle %s impounded.'):format(plate) }
end)

---------------------------------------------------------------------------
-- Spike strips
---------------------------------------------------------------------------
local function SpikeList()
    local list = {}
    for id, s in pairs(Spikes) do list[#list + 1] = { id = id, x = s.x, y = s.y, z = s.z, h = s.h } end
    return list
end
local function SyncSpikes(target) TriggerClientEvent(EV .. 'spikes', target or -1, SpikeList()) end

local function RemoveEntity(netId)
    local e = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
end

-- The client makes the object; wait for it to reach the server, then check it's really ours
local function PlacedEntity(src, netId, model)
    netId = tonumber(netId)
    if not netId then return nil end
    local e = NetworkGetEntityFromNetworkId(netId)
    local t = GetGameTimer() + 2500
    while (e == 0 or not DoesEntityExist(e)) and GetGameTimer() < t do
        Wait(50)
        e = NetworkGetEntityFromNetworkId(netId)
    end
    if e == 0 or not DoesEntityExist(e) then return nil end
    if GetEntityType(e) ~= 3 or GetEntityModel(e) ~= GetHashKey(model) or #(GetEntityCoords(e) - Pos(src)) > 8.0 then return nil end
    return e, netId
end

PoliceCallback('spikeDeployed', function(src, netId)
    local e
    e, netId = PlacedEntity(src, netId, Config.SpikeModel)
    if not e then return Fail('Couldn\'t place that - try again.') end
    local mine = 0
    for _, s in pairs(Spikes) do if s.owner == src then mine = mine + 1 end end
    if mine >= Config.MaxSpikes then DeleteEntity(e) return Fail(('You can only have %d spike strips out.'):format(Config.MaxSpikes)) end
    local c = GetEntityCoords(e)
    Spikes[netId] = { owner = src, x = c.x, y = c.y, z = c.z, h = GetEntityHeading(e), placed = os.time() }
    SyncSpikes()
    return { ok = true, msg = 'Spike strip deployed.' }
end)

PoliceCallback('spikePickup', function(src, netId)
    netId = tonumber(netId)
    local s = Spikes[netId]
    if not s then return Fail('No spike strip there.') end
    if #(vector3(s.x, s.y, s.z) - Pos(src)) > 4.0 then return Fail('Get closer.') end
    RemoveEntity(netId)
    Spikes[netId] = nil
    SyncSpikes()
    return { ok = true, msg = 'Spike strip picked up.' }
end)

CreateThread(function()
    while true do
        Wait(30000)
        local changed = false
        for id, s in pairs(Spikes) do
            local e = NetworkGetEntityFromNetworkId(id)
            if os.time() - s.placed > Config.SpikeMinutes * 60 or e == 0 or not DoesEntityExist(e) then
                RemoveEntity(id)
                Spikes[id] = nil
                changed = true
            end
        end
        if changed then SyncSpikes() end
    end
end)

---------------------------------------------------------------------------
-- Cones, barriers and evidence markers
---------------------------------------------------------------------------
local function Markers()
    local list = {}
    for id, s in pairs(Scene) do if s.n then list[#list + 1] = { id = id, n = s.n } end end
    return list
end
local function SyncMarkers(target) TriggerClientEvent(EV .. 'markers', target or -1, Markers()) end

PoliceCallback('propPlaced', function(src, netId, key)
    local def
    for _, p in ipairs(Config.SceneProps) do if p.key == key then def = p end end
    if not def then return Fail() end
    local e
    e, netId = PlacedEntity(src, netId, def.model)
    if not e then return Fail('Couldn\'t place that - try again.') end
    local mine, n = 0, 0
    for _, s in pairs(Scene) do
        if s.owner == src then mine = mine + 1 end
        if s.n then n = math.max(n, s.n) end
    end
    if mine >= Config.MaxSceneProps then DeleteEntity(e) return Fail('You\'ve placed too many - pick some up first.') end
    Scene[netId] = { owner = src, key = key, n = def.numbered and (n + 1) or nil }
    if def.numbered then SyncMarkers() end
    return { ok = true }
end)

PoliceCallback('propPickup', function(src, netId)
    netId = tonumber(netId)
    local s = Scene[netId]
    if not s then return Fail('That wasn\'t placed by the police.') end
    local e = NetworkGetEntityFromNetworkId(netId)
    if e ~= 0 and DoesEntityExist(e) and #(GetEntityCoords(e) - Pos(src)) > 4.0 then return Fail('Get closer.') end
    RemoveEntity(netId)
    Scene[netId] = nil
    if s.n then SyncMarkers() end
    return { ok = true }
end)

PoliceCallback('propClear', function(src)
    local n = 0
    for id, s in pairs(Scene) do
        if s.owner == src then RemoveEntity(id) Scene[id] = nil n = n + 1 end
    end
    for id, s in pairs(Spikes) do
        if s.owner == src then RemoveEntity(id) Spikes[id] = nil n = n + 1 end
    end
    SyncSpikes() SyncMarkers()
    return { ok = true, msg = ('Picked up %d things.'):format(n) }
end)

function ClearAllProps()
    for id in pairs(Scene) do RemoveEntity(id) end
    for id in pairs(Spikes) do RemoveEntity(id) end
    Scene, Spikes = {}, {}
    SyncSpikes() SyncMarkers()
end

RegisterNetEvent(EV .. 'joined', function()
    local src = source
    SyncSpikes(src) SyncMarkers(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    VehSearch[src] = nil
    -- a leaving officer's cones stay until picked up; their spikes go
    local changed = false
    for id, s in pairs(Spikes) do if s.owner == src then RemoveEntity(id) Spikes[id] = nil changed = true end end
    if changed then SyncSpikes() end
end)

AddEventHandler('onResourceStop', function(res) if res == RES then ClearAllProps() end end)
