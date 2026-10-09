-- Statewide PD: where things happen. Callouts go to real places - store robberies at 24/7s and liquor
-- stores, warrants at real (empty) houses you can force your way into, bar fights at bars, deals in lots and
-- trailer parks... Places come from statewide_shops, statewide_fuel, statewide_housing, the list in
-- config_ai.lua and the ones staff add in game (patrol computer > Places).
local AI = Config.AI
local X = AIX
local Chance, Pick, Clamp, CleanText, Limited = X.Chance, X.Pick, X.Clamp, X.CleanText, X.Limited

local Added = LoadJson('data/ai_places.json', { seq = 0, list = {} })   -- staff-added places
Added.list = Added.list or {}
local Recent = {}        -- [place id] = os.time() last used
AllowedHouse = {}        -- [src] = { [houseId] = true } houses this officer was sent to
local Opened = {}        -- [houseId] = src who forced it
local Cache, cacheAt = {}, 0

local TYPES = AI.PlaceTypes or {}

local function P(id, kind, label, x, y, z, w, extra)
    local p = { id = id, type = kind, label = label, x = x + 0.0, y = y + 0.0, z = z + 0.0, w = (w or 0.0) + 0.0 }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

local SHOP_TYPE = { store = 'store', liquor = 'liquor', hardware = 'hardware', diner = 'diner', coffee = 'diner', burgershot = 'diner', ammunation = 'gunstore' }

local function Started(res) return GetResourceState(res) == 'started' end

local function Build()
    local out = {}
    -- shops (the counter: where the shopkeeper stands, facing the customers)
    local shops
    if Started('statewide_shops') then
        local ok, list = pcall(function() return exports['statewide_shops']:GetShops() end)
        if ok and type(list) == 'table' then shops = list end
    end
    for i, s in ipairs(shops or AI.FallbackShops or {}) do
        local t = SHOP_TYPE[s.kind]
        if t then
            local c = s.coords or s
            out[#out + 1] = P('shop' .. i, t, s.label, c.x, c.y, c.z, c.w or s.w, { counter = true })
        end
    end
    -- fuel stations (forecourts)
    if Started('statewide_fuel') then
        local ok, list = pcall(function() return exports['statewide_fuel']:GetStations() end)
        if ok and type(list) == 'table' then
            for i, f in ipairs(list) do
                if f.x and f.y then out[#out + 1] = P('fuel' .. (f.id or i), 'gas', f.label or 'Gas station', f.x, f.y, f.z or 0.0, 0.0) end
            end
        end
    end
    -- empty houses (statewide_housing): addresses for warrants, domestics, burglaries...
    if Started('statewide_housing') then
        local ok, list = pcall(function() return exports['statewide_housing']:AIHouses() end)
        if ok and type(list) == 'table' then
            for _, h in ipairs(list) do
                if h.entrance then
                    out[#out + 1] = P('house' .. h.id, 'house', h.label or 'House', h.entrance.x, h.entrance.y, h.entrance.z, h.entrance.w,
                        { house = { id = h.id, teleports = h.teleports == true, inside = h.inside or {}, doors = h.doors or {} } })
                end
            end
        end
    end
    -- the list in config_ai.lua
    for i, c in ipairs(AI.PlaceList or {}) do
        out[#out + 1] = P('cfg' .. i, c.type, c.label, c.pos.x, c.pos.y, c.pos.z, c.pos.w)
    end
    -- added in game by staff
    for _, a in ipairs(Added.list) do
        out[#out + 1] = P(a.id, a.type, a.label, a.x, a.y, a.z, a.w, { staff = true })
    end
    return out
end

local function All()
    if os.time() - cacheAt > 120 or #Cache == 0 then Cache, cacheAt = Build(), os.time() end
    return Cache
end
AIPlaces = All

-- A place for a callout near the officer. nil = let the client pick a spot on the road.
function PlaceFor(src, key, kinds)
    kinds = kinds or (AI.CalloutPlaces or {})[key]
    if not kinds or #kinds == 0 then return nil end
    local want = {}
    for _, k in ipairs(kinds) do want[k] = true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local me = GetEntityCoords(ped)
    local range = AI.PlaceRange or { 250, 1800 }
    local near, far = {}, {}
    local now = os.time()
    for _, p in ipairs(All()) do
        if want[p.type] and now - (Recent[p.id] or 0) > (AI.PlaceCooldown or 900) then
            local d = #(vector3(p.x, p.y, p.z) - me)
            if d >= range[1] and d <= range[2] then near[#near + 1] = { p = p, d = d }
            elseif d < (AI.PlaceMaxRange or 4500) and d >= 120 then far[#far + 1] = { p = p, d = d } end
        end
    end
    local pick
    if #near > 0 then
        pick = Pick(near).p
    elseif #far > 0 then
        table.sort(far, function(a, b) return a.d < b.d end)
        pick = far[math.random(1, math.min(3, #far))].p
    end
    if not pick then return nil end
    Recent[pick.id] = now - (AI.PlaceCooldown or 900) + 60     -- held for a minute; the full cooldown starts when accepted
    return pick
end

-- The officer took the job: the place is used, and they may force the house
function PlaceTaken(src, loc)
    if not loc then return end
    Recent[loc.id] = os.time()
    if loc.house then
        AllowedHouse[src] = AllowedHouse[src] or {}
        AllowedHouse[src][loc.house.id] = true
    end
end

AddEventHandler('playerDropped', function() AllowedHouse[source] = nil end)

---------------------------------------------------------------------------
-- Forcing entry to a suspect's house (statewide_housing opens the doors for police)
---------------------------------------------------------------------------
PoliceCallback('aiHouseOpen', function(src, houseId, minutes)
    if Limited(src, 'houseopen', 6) then return Fail('Slow down.') end
    if not Started('statewide_housing') then return { ok = true, none = true } end
    houseId = tonumber(houseId)
    if not (AllowedHouse[src] and AllowedHouse[src][houseId]) then return Fail('That isn\'t your suspect\'s address.') end
    minutes = Clamp(math.floor(tonumber(minutes) or 12), 1, 15)
    local place
    for _, p in ipairs(All()) do if p.house and p.house.id == tonumber(houseId) then place = p end end
    if not place then return Fail('That isn\'t a suspect\'s address.') end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - vector3(place.x, place.y, place.z)) > 60.0 then return Fail('Get to the house first.') end
    local ok, res = pcall(function() return exports['statewide_housing']:AIOpen(houseId, minutes) end)
    if not ok or not res then return Fail('The door won\'t give.') end
    Opened[houseId] = src
    return { ok = true }
end)

PoliceCallback('aiHouseClose', function(src, houseId)
    houseId = tonumber(houseId)
    if Opened[houseId] ~= src then return { ok = true } end
    Opened[houseId] = nil
    if AllowedHouse[src] then AllowedHouse[src][houseId] = nil end
    if Started('statewide_housing') then pcall(function() exports['statewide_housing']:AIClose(houseId) end) end
    return { ok = true }
end)

---------------------------------------------------------------------------
-- Staff: add / remove places in game
---------------------------------------------------------------------------
local function SaveAdded() SaveJson('data/ai_places.json', Added) end

PoliceCallback('placeList', function(src)
    local ped = GetPlayerPed(src)
    local me = ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
    local counts, nearby = {}, {}
    for _, p in ipairs(All()) do
        counts[p.type] = (counts[p.type] or 0) + 1
        local d = #(vector3(p.x, p.y, p.z) - me)
        if d < 600.0 then nearby[#nearby + 1] = { id = p.id, type = p.type, label = p.label, dist = math.floor(d), staff = p.staff == true } end
    end
    table.sort(nearby, function(a, b) return a.dist < b.dist end)
    while #nearby > 25 do table.remove(nearby) end
    local types = {}
    for _, t in ipairs(TYPES) do types[#types + 1] = { key = t.key, label = t.label, count = counts[t.key] or 0, auto = t.auto == true } end
    return { ok = true, types = types, nearby = nearby, admin = IsAdmin(src) }
end)

PoliceCallback('placeAdd', function(src, kind, label)
    if not IsAdmin(src) then return Fail('Staff only.') end
    local okType = false
    for _, t in ipairs(TYPES) do if t.key == kind and not t.auto then okType = true end end
    if not okType then return Fail('Pick a place type.') end
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    Added.seq = (tonumber(Added.seq) or 0) + 1
    label = CleanText(label, 40)
    if label == '' then label = kind:gsub('^%l', string.upper) end
    Added.list[#Added.list + 1] = { id = 'staff' .. Added.seq, type = kind, label = label, x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
    SaveAdded()
    cacheAt = 0
    return { ok = true, msg = ('Saved "%s" as a %s place. Callouts can happen here now.'):format(label, kind) }
end)

PoliceCallback('placeRemove', function(src, id)
    if not IsAdmin(src) then return Fail('Staff only.') end
    for i, a in ipairs(Added.list) do
        if a.id == id then
            table.remove(Added.list, i)
            SaveAdded()
            cacheAt = 0
            return { ok = true, msg = 'Place removed.' }
        end
    end
    return Fail('Only places added in game can be removed here (the others come from your shops, fuel and housing scripts or config_ai.lua).')
end)
